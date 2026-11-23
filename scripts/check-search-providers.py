#!/usr/bin/env python3
"""Exercise real LiteLLM adapters with HTTP mocked: no network or paid calls."""
import json
from copy import deepcopy
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

import httpx

from harness.archive import read_json
from harness import model as model_module
from harness.model import Model, estimate_cost, load_environment, scrub
from search import proposal, settings

PAYLOAD = json.dumps(dict(idea='baseline', code='def build(): return {}', notes='remember'))
KEY = 'fake-provider-secret-key'


class ProviderTests(unittest.TestCase):
    def setUp(self):
        # Tests must never read the developer's actual local credentials.
        self.temp = tempfile.TemporaryDirectory()
        self.env_file = Path(self.temp.name) / '.env'
        self.env_patch = patch.object(model_module, 'ENV_FILE', self.env_file)
        self.env_patch.start()

    def tearDown(self):
        self.env_patch.stop()
        self.temp.cleanup()

    def test_unknown_model_price_is_unavailable_instead_of_free(self):
        sdk = SimpleNamespace(model_cost={}, completion_cost=Mock(return_value=0.0))
        response = SimpleNamespace(model='gpt-6.2-astra')
        self.assertIsNone(estimate_cost(sdk, response, 'openai/gpt-6.2-astra'))
        sdk.completion_cost.assert_not_called()
        sdk.model_cost['gpt-6.2-astra'] = {'input_cost_per_token': 8e-6, 'output_cost_per_token': 40e-6}
        sdk.completion_cost.return_value = .25
        self.assertEqual(estimate_cost(sdk, response, 'openai/gpt-6.2-astra'), .25)
        sdk.completion_cost.return_value = 0.0  # a known free rate is still allowed
        self.assertEqual(estimate_cost(sdk, response, 'openai/gpt-6.2-astra'), 0.0)

    def test_local_env_is_optional_literal_and_does_not_override_shell(self):
        with patch.dict(os.environ, {'ANTHROPIC_API_KEY': 'shell-value'}):
            os.environ.pop('OPENAI_API_KEY', None)
            os.environ.pop('GEMINI_API_KEY', None)
            load_environment()  # a missing .env is fine
            self.assertNotIn('OPENAI_API_KEY', os.environ)
            literal = 'literal-${HARNESS_TEST_NAME}-$(touch should-not-exist)'
            self.env_file.write_text(f'# Local credentials\nOPENAI_API_KEY="{KEY}"\n'
                                     f'ANTHROPIC_API_KEY=file-value\nGEMINI_API_KEY=\'{literal}\'\n')
            load_environment()
            self.assertEqual(os.environ['OPENAI_API_KEY'], KEY)
            self.assertEqual(os.environ['ANTHROPIC_API_KEY'], 'shell-value')
            self.assertEqual(os.environ['GEMINI_API_KEY'], literal)
            self.assertEqual(scrub('echo ' + KEY), 'echo [REDACTED]')

    def test_model_automatically_uses_local_env(self):
        self.env_file.write_text(f'OPENAI_API_KEY={KEY}\n')
        with patch.dict(os.environ):
            os.environ.pop('OPENAI_API_KEY', None)
            def send(client, request, **kwargs):
                self.assertEqual(request.headers['authorization'], 'Bearer ' + KEY)
                return httpx.Response(200, json=dict(id='chatcmpl-test', object='chat.completion',
                    created=1, model='gpt-4o-mini', choices=[dict(index=0,
                    message=dict(role='assistant', content=PAYLOAD), finish_reason='stop')],
                    usage=dict(prompt_tokens=100, completion_tokens=20, total_tokens=120)), request=request)
            adapter = Model(settings(dict(model='openai/gpt-4o-mini')))
            folder = Path(self.temp.name) / 'attempt'
            folder.mkdir()
            with patch.object(httpx.Client, 'send', send):
                adapter(dict(model='openai/gpt-4o-mini', messages=[dict(role='user', content='test')],
                             max_tokens=100, timeout=5), folder)
            for path in folder.iterdir():
                self.assertNotIn(KEY, path.read_text())

    def test_adapters_archive_and_isolate_calls(self):
        samples = [
            ('openai/gpt-6.2-astra', dict(id='chatcmpl-test', object='chat.completion', created=1,
                model='gpt-6.2-astra', choices=[dict(index=0, message=dict(role='assistant', content=PAYLOAD),
                finish_reason='stop')], usage=dict(prompt_tokens=100, completion_tokens=20, total_tokens=120))),
            ('anthropic/claude-opus-5-5', dict(id='msg_test', type='message', role='assistant',
                model='claude-opus-5-5', content=[dict(type='text', text=PAYLOAD)],
                stop_reason='end_turn', stop_sequence=None, usage=dict(input_tokens=100, output_tokens=20))),
            ('gemini/gemini-2.0-flash', dict(candidates=[dict(content=dict(role='model', parts=[dict(text=PAYLOAD)]),
                finishReason='STOP', index=0)], usageMetadata=dict(promptTokenCount=100,
                candidatesTokenCount=20, totalTokenCount=120), modelVersion='gemini-2.0-flash')),
        ]
        for name, template in [('anthropic/claude-fable-5-2', samples[1][1]),
                               ('anthropic/claude-sonnet-5-5', samples[1][1]),
                               ('openai/gpt-6.2-sol', samples[0][1])]:
            body = deepcopy(template)
            body['model'] = name.split('/', 1)[1]
            samples.append((name, body))
        with tempfile.TemporaryDirectory() as tmp, patch.dict('os.environ', {
                'OPENAI_API_KEY':KEY, 'ANTHROPIC_API_KEY':KEY, 'GEMINI_API_KEY':KEY}):
            previous = None
            for index, (name, body) in enumerate(samples):
                calls = []
                def send(client, request, **kwargs):
                    calls.append(request)
                    return httpx.Response(200, json=body, request=request, headers={'x-request-id':'request-test'})
                cfg = settings(dict(model=name))
                if not name.startswith('gemini/'):
                    cfg['reasoning_effort'] = 'medium'
                adapter = Model(cfg)
                folder = Path(tmp) / str(index)
                folder.mkdir()
                request = dict(model=name, messages=[dict(role='system', content='Return JSON.'),
                               dict(role='user', content='Try a design.')], max_tokens=cfg['max_tokens'],
                               timeout=cfg['request_timeout'])
                if 'reasoning_effort' in cfg:
                    request['reasoning_effort'] = cfg['reasoning_effort']
                if adapter.seed_supported:
                    request['seed'] = 12345
                with patch.object(httpx.Client, 'send', send):
                    response = adapter(request, folder)
                self.assertEqual(len(calls), 1)
                wire = json.loads(calls[0].content)
                if name.startswith('openai/'):
                    self.assertEqual(wire['max_completion_tokens'], 32768)
                    self.assertEqual(wire['reasoning_effort'], 'medium')
                    self.assertEqual(wire['seed'], 12345)
                elif name.startswith('anthropic/'):
                    self.assertEqual(wire['max_tokens'], 32768)
                    self.assertEqual(wire['output_config']['effort'], 'medium')
                    self.assertFalse(adapter.seed_supported)
                    self.assertNotIn('seed', wire)
                else:
                    self.assertEqual(wire['generationConfig']['max_output_tokens'], 32768)
                self.assertEqual(calls[0].extensions['timeout']['read'], 600)
                self.assertEqual(proposal(response, cfg)['idea'], 'baseline')
                self.assertEqual(response['usage']['total_tokens'], 120)
                self.assertTrue(list(folder.glob('provider-*-request.json')))
                self.assertTrue(list(folder.glob('provider-*-response.json')))
                self.assertEqual(read_json(folder/'response.json'), response)
                for p in folder.iterdir():
                    self.assertNotIn(KEY, p.read_text(), p)
                if previous:
                    old, snapshot = previous
                    self.assertEqual(snapshot, {p.name:p.read_bytes() for p in old.iterdir()})
                previous = (folder, {p.name:p.read_bytes() for p in folder.iterdir()})

    def test_error_is_archived_without_retry(self):
        with tempfile.TemporaryDirectory() as tmp, patch.dict('os.environ', {'OPENAI_API_KEY':KEY}):
            calls = []
            def send(client, request, **kwargs):
                calls.append(request)
                return httpx.Response(429, json={'error':{'message':'rate limit '+KEY,
                    'type':'rate_limit_error', 'code':'rate_limit'}}, request=request)
            adapter = Model(settings(dict(model='openai/gpt-4o-mini')))
            with patch.object(httpx.Client, 'send', send), self.assertRaises(Exception):
                adapter(dict(model='openai/gpt-4o-mini', messages=[dict(role='user', content='test')],
                             max_tokens=100, timeout=5), Path(tmp))
            self.assertEqual(len(calls), 1)
            error = read_json(Path(tmp)/'api-error.json')
            self.assertIn('rate limit', error['message'])
            self.assertIn('traceback', error)
            for p in Path(tmp).iterdir():
                self.assertNotIn(KEY, p.read_text(), p)


if __name__ == '__main__':
    unittest.main(verbosity=2)
