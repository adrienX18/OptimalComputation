"""One LiteLLM completion call. No routing, fallback, tools, or hidden retries."""
import contextlib
import io
import importlib.metadata
import json
import os
from pathlib import Path
import threading
import time
import traceback

from .archive import write_json

ENV_FILE = Path(__file__).resolve().parents[2] / '.env'


def load_environment():
    """Load local credentials as data; never source shell commands or archive them."""
    from dotenv import load_dotenv
    load_dotenv(ENV_FILE, override=False, interpolate=False)


def estimate_cost(sdk, response, requested_model):
    """An SDK fallback zero is not a price for a model absent from its rate table."""
    names = {requested_model, requested_model.split('/', 1)[-1], getattr(response, 'model', None)}
    if not any(name in sdk.model_cost for name in names):
        return None
    return sdk.completion_cost(completion_response=response)


def scrub(value):
    """Retain provider data while removing credentials, including echoed values."""
    secrets = [v for k, v in os.environ.items() if v and len(v) >= 8 and
               any(word in k.upper() for word in ('API_KEY', 'TOKEN', 'SECRET', 'PASSWORD'))]
    def clean(item):
        if isinstance(item, dict):
            return {str(k): '[REDACTED]' if any(word in str(k).lower().replace("-", "_") for word in
                    ('api_key', 'authorization', 'access_token', 'secret', 'password', 'cookie')) else clean(v)
                    for k, v in item.items()}
        if isinstance(item, (list, tuple)):
            return [clean(v) for v in item]
        if isinstance(item, str):
            for secret in secrets:
                item = item.replace(secret, '[REDACTED]')
            return item
        if item is None or isinstance(item, (int, float, bool)):
            return item
        if hasattr(item, 'model_dump'):
            return clean(item.model_dump(mode='json'))
        return clean(str(item))
    return clean(value)


class Model:
    def __init__(self, config):
        # Import only for live runs, so ordinary tests remain standard-library-only.
        load_environment()
        os.environ.setdefault('LITELLM_LOCAL_MODEL_COST_MAP', 'True')
        import litellm
        from litellm.integrations.custom_logger import CustomLogger
        self.sdk = litellm
        self.logger_base = CustomLogger
        self.config = config
        self.version = importlib.metadata.version('litellm')
        self.dependencies = {name: importlib.metadata.version(name) for name in ('litellm', 'openai', 'httpx', 'python-dotenv')}
        self.sdk.telemetry = False
        self.sdk.drop_params = False

    def __call__(self, request, directory):
        directory = Path(directory)
        sdk = self.sdk
        counter = 0
        logging_errors = []
        lock = threading.Lock()
        def save(kind, data):
            nonlocal counter
            with lock:
                counter += 1
                try:
                    write_json(directory / f'provider-{counter:03d}-{kind}.json', scrub(data))
                except Exception as exc:
                    logging_errors.append(str(exc))
                    raise
        class Logger(self.logger_base):
            def log_pre_api_call(self, model, messages, kwargs):
                save('request', dict(model=model, messages=messages,
                                    additional_args=kwargs.get('additional_args'),
                                    optional_params=kwargs.get('optional_params')))
            def log_post_api_call(self, kwargs, response_obj, start_time, end_time):
                save('response', dict(response=kwargs.get('original_response', response_obj),
                                     additional_args=kwargs.get('additional_args')))
        callback_names = ['callbacks', 'input_callback', 'success_callback', 'failure_callback',
                          '_async_input_callback', '_async_success_callback', '_async_failure_callback']
        old_callbacks = {name: getattr(sdk, name) for name in callback_names}
        for name in callback_names:
            setattr(sdk, name, [])
        stdout, stderr = io.StringIO(), io.StringIO()
        start = time.time()
        try:
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                response = sdk.completion(**(request | dict(num_retries=0, stream=False)), callbacks=[Logger()])
            if logging_errors:
                raise OSError(f'Provider archive failed: {logging_errors}')
            data = response.model_dump(mode='json')
            data['providerMetadata'] = scrub(getattr(response, '_hidden_params', {}))
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                try:
                    cost = estimate_cost(sdk, response, request['model'])
                except Exception:
                    cost = None
            data['estimatedCostUSD'] = cost
            data['seconds'] = time.time() - start
            data = scrub(data)
            write_json(directory / 'response.json', data)
            return data
        except Exception as exc:
            data = dict(type=type(exc).__name__, message=str(exc), seconds=time.time()-start, traceback=traceback.format_exc())
            response = getattr(exc, 'response', None)
            if response is not None:
                data['response'] = dict(status=getattr(response, 'status_code', None),
                                        headers=dict(getattr(response, 'headers', {})),
                                        body=getattr(response, 'text', None))
            write_json(directory / 'api-error.json', scrub(data))
            raise
        finally:
            (directory / 'model-stdout.txt').write_text(scrub(stdout.getvalue()))
            (directory / 'model-stderr.txt').write_text(scrub(stderr.getvalue()))
            for name, callbacks in old_callbacks.items():
                setattr(sdk, name, callbacks)


class ReplayModel:
    """Recorded/scripted responses for offline tests; generators still use Docker."""
    version = 'replay-v1'
    def __init__(self, responses):
        self.responses = responses
    def __call__(self, request, directory):
        index = int(Path(directory).name) - 1
        if index >= len(self.responses):
            raise ValueError('Replay has no response for this attempt.')
        item = self.responses[index]
        data = item if isinstance(item, dict) and 'choices' in item else {
            'choices': [{'message': {'content': item if isinstance(item, str) else json.dumps(item)},
                         'finish_reason': 'stop'}], 'model': 'replay', 'usage': None}
        write_json(Path(directory) / 'response.json', data)
        return data
