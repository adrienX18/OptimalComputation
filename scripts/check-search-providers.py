#!/usr/bin/env python3
"""Exercise real LiteLLM adapters with HTTP mocked: no network or paid calls."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import httpx

from harness.archive import read_json
from harness.model import Model
from search import proposal, settings

PAYLOAD = json.dumps(dict(idea='baseline', code='def build(): return {}', notes='remember'))
KEY = 'fake-provider-secret-key'


class ProviderTests(unittest.TestCase):
    def test_adapters_archive_and_isolate_calls(self):
        samples = [
            ('openai/gpt-4o-mini', dict(id='chatcmpl-test', object='chat.completion', created=1,
                model='gpt-4o-mini', choices=[dict(index=0, message=dict(role='assistant', content=PAYLOAD),
                finish_reason='stop')], usage=dict(prompt_tokens=100, completion_tokens=20, total_tokens=120))),
            ('anthropic/claude-3-5-haiku-20241022', dict(id='msg_test', type='message', role='assistant',
                model='claude-3-5-haiku-20241022', content=[dict(type='text', text=PAYLOAD)],
                stop_reason='end_turn', stop_sequence=None, usage=dict(input_tokens=100, output_tokens=20))),
            ('gemini/gemini-2.0-flash', dict(candidates=[dict(content=dict(role='model', parts=[dict(text=PAYLOAD)]),
                finishReason='STOP', index=0)], usageMetadata=dict(promptTokenCount=100,
                candidatesTokenCount=20, totalTokenCount=120), modelVersion='gemini-2.0-flash')),
        ]
        with tempfile.TemporaryDirectory() as tmp, patch.dict('os.environ', {
                'OPENAI_API_KEY':KEY, 'ANTHROPIC_API_KEY':KEY, 'GEMINI_API_KEY':KEY}):
            previous = None
            for index, (name, body) in enumerate(samples):
                calls = []
                def send(client, request, **kwargs):
                    calls.append(request)
                    return httpx.Response(200, json=body, request=request, headers={'x-request-id':'request-test'})
                cfg = settings(dict(model=name))
                adapter = Model(cfg)
                folder = Path(tmp) / str(index)
                folder.mkdir()
                request = dict(model=name, messages=[dict(role='system', content='Return JSON.'),
                               dict(role='user', content='Try a design.')], max_tokens=100, timeout=5)
                with patch.object(httpx.Client, 'send', send):
                    response = adapter(request, folder)
                self.assertEqual(len(calls), 1)
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
