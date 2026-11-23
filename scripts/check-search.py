#!/usr/bin/env python3
"""Offline harness regressions. --integration adds real Docker and Lean runs."""
import argparse
from contextlib import redirect_stdout
from copy import deepcopy
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

if not __debug__:
    raise SystemExit('Tests require assertions; omit -O/-OO and unset PYTHONOPTIMIZE.')

import search
from harness import evaluate as e, prompt
from harness.archive import read_json, write_json, command, output
from harness.model import ReplayModel, scrub


class Engine:
    """Deterministic evaluator double; never executes model code on the host."""
    @staticmethod
    def resolve_image(image, directory):
        return 'sha256:test-image'
    @staticmethod
    def initialize(config, directory):
        directory.mkdir()
        (directory / 'generator.py').write_text(e.STARTER)
        return dict(fixtures={}, scoreFixture='zeros', score=100, unit='cycles',
                    raw=dict(layout=dict(inputs=[0,1], outputs=[2], scratch=[]), schedule=[]))
    @staticmethod
    def generate(code, baseline, directory, image, timeout):
        directory.mkdir()
        (directory.parent / 'candidate.json').write_text('{}\n')
        return None
    @staticmethod
    def evaluate(config, baseline, directory):
        code = (directory / 'generator.py').read_text()
        if code.startswith('invalid'):
            return dict(accepted=False, category='pending-read', message='cycle 3, register 1 pending')
        if code == 'timeout':
            return dict(accepted=False, category='kernel-timeout', message='No certificate')
        return dict(accepted=True, category='certified', score=int(code), unit='cycles', cycles=int(code))


def reply(code, idea='try', notes='remember'):
    return dict(code=code, idea=idea, notes=notes)


class SearchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / 'run'
        self.config = dict(model='replay', task='tiny', configuration=[1,1], attempts=4)
    def tearDown(self):
        self.temp.cleanup()
    def run_search(self, responses, **kwargs):
        with redirect_stdout(io.StringIO()):
            return search.run(self.root, self.config, replay=responses, engine=Engine, **kwargs)

    def test_improvement_errors_history_resume(self):
        responses = [reply('80'), reply('invalid'), 'not JSON', reply('70')]
        result = self.run_search(responses)
        self.assertEqual(result['best']['score'], 70)
        self.assertEqual(len(result['attempts']), 4)
        self.assertEqual(result['attempts'][1]['category'], 'pending-read')
        request = read_json(self.root / 'attempts/0004/request.json')
        self.assertEqual(request['max_tokens'], 32768)
        self.assertEqual(request['timeout'], 600)
        context = json.loads(request['messages'][1]['content'])
        self.assertEqual(context['best']['code'], '80')
        self.assertEqual(len(context['history']), 3)
        self.assertEqual(context['notebook'], 'remember')
        hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in (self.root/'attempts').rglob('*') if p.is_file()}
        result2 = self.run_search(None, resume=True)
        self.assertEqual(result2, result)
        self.assertEqual(hashes, {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in (self.root/'attempts').rglob('*') if p.is_file()})
        self.assertTrue((self.root / 'summary.csv').exists())
        self.assertTrue((self.root / 'source/scripts/search.py').exists())

    def test_interrupted_call_consumed_without_reissue(self):
        class Interrupted(ReplayModel):
            def __call__(self, request, directory):
                if int(directory.name) == 2:
                    raise KeyboardInterrupt()
                return super().__call__(request, directory)
        responses = [reply('80'), reply('50'), reply('75'), reply('60')]
        with self.assertRaises(KeyboardInterrupt):
            self.run_search(responses, model=Interrupted(responses))
        result = self.run_search(None, resume=True)
        self.assertEqual(result['attempts'][1]['category'], 'interrupted')
        self.assertEqual(result['best']['score'], 60)  # slot 2 was not silently regenerated
        self.assertFalse((self.root/'attempts/0002/response.json').exists())

    def test_budget_100_and_bounded_context(self):
        self.config['attempts'] = 100
        self.config['prompt_bytes'] = 9000
        result = self.run_search([reply('80', 'long idea '*50, 'memo '*1000)] * 100)
        self.assertEqual(len(result['attempts']), 100)
        self.assertEqual(len(list((self.root/'attempts').iterdir())), 100)
        for p in (self.root/'attempts').glob('*/request.json'):
            self.assertLessEqual(len(json.dumps(read_json(p)['messages'], ensure_ascii=False).encode()), 9000)
        self.assertIn('long idea', (self.root/'attempts/0100/response.json').read_text())

    def test_source_change_refuses_resume(self):
        self.run_search([reply('80')] * 4)
        with patch.object(search, 'fingerprint', return_value={'changed':'yes'}):
            with self.assertRaisesRegex(ValueError, 'Source changed'):
                self.run_search(None, resume=True)

    def test_api_failures_are_bounded(self):
        self.config['attempts'] = 100
        class Failed:
            version = 'failed-test'
            def __call__(self, *args):
                raise OSError('provider unavailable')
        result = self.run_search([], model=Failed())
        self.assertEqual(len(result['attempts']), 3)
        self.assertEqual(result['best']['score'], 100)
        self.assertTrue((self.root/'attempts/0001/error.json').exists())

    def test_uncertified_and_worse_attempts_cannot_replace_baseline(self):
        result = self.run_search([reply('timeout'), reply('101'), reply('100'), reply('invalid')])
        self.assertEqual(result['best']['attempt'], 0)
        self.assertEqual(result['best']['score'], 100)
        self.assertFalse(any(row['improved'] for row in result['attempts']))

    def test_validation_duplicate_and_oversized(self):
        for update in [dict(attempts=101), dict(temperature=float('nan')), dict(api_key='secret'), dict(configuration=[True,1])]:
            with self.assertRaises(ValueError):
                search.settings(self.config | update)
        with self.assertRaises(ValueError):
            e.strict_json('{"a":1,"\\u0061":2}')
        self.config['code_bytes'] = 3
        result = self.run_search([reply('toolong'), reply('80'), reply('81'), reply('82')])
        self.assertEqual(result['attempts'][0]['category'], 'proposal-error')
        self.assertTrue((self.root/'attempts/0001/response.json').exists())

    def test_secret_scrub_and_process_timeout(self):
        with patch.dict('os.environ', {'ANTHROPIC_API_KEY':'secret-test-key'}):
            cleaned = scrub({'x-api-key':'other-secret', 'body':'echo secret-test-key'})
        self.assertEqual(cleaned, {'x-api-key':'[REDACTED]', 'body':'echo [REDACTED]'})
        import sys
        d = Path(self.temp.name)/'process'
        result = command([sys.executable, '-c', 'import time;print("before",flush=True);time.sleep(10)'], d, cwd=search.ROOT, timeout=.15)
        self.assertEqual(result['status'], 'timeout')
        self.assertEqual(output(d), 'before\n')
        self.assertTrue((d/'result.json').exists())


def integration():
    import base64
    import certify
    import experiment
    import zlib
    with tempfile.TemporaryDirectory(prefix='search-integration-') as tmp:
        root = Path(tmp)
        code = e.STARTER
        responses = [reply(code), reply(code.replace('return baseline()', 'c=baseline()\n    c["schedule"].pop()\n    return c')),
                     reply(code.replace('return baseline()', 'c=baseline()\n    c["identifier"]="fresh"\n    c["schedule"].reverse()\n    return c'))]
        cfg = dict(model='replay',task='tiny',configuration=[1,1],attempts=3)
        result = search.run(root/'run', cfg, replay=responses)
        assert [r['accepted'] for r in result['attempts']] == [True,False,True], result
        assert result['attempts'][0]['score'] == 6
        assert (root/'run/attempts/0001/certification/kernel/stdout.txt').exists()
        before = (root/'run/attempts/0001/request.json').read_bytes()
        search.run(root/'run', resume=True)
        assert before == (root/'run/attempts/0001/request.json').read_bytes()
        base = read_json(root/'run/baseline.json')
        for name, attack in [('secret','import os\nassert "OPENAI_API_KEY" not in os.environ\n'),
                             ('readonly','from pathlib import Path\nPath("/input/baseline.json").write_text("bad")\n'),
                             ('timeout','while True: pass\n')]:
            d = root/name
            d.mkdir()
            with patch.dict('os.environ', {'OPENAI_API_KEY': 'host-secret-test-value'}):
                failed = e.generate(attack+code, base['raw'], d/'generation', read_json(root/'run/manifest.json')['imageId'], 2)
            assert (failed is None) == (name == 'secret'), (name, failed)
        scored = certify.certify(root/'run/attempts/0001/candidate.json', objective='energy-proxy-v1', fixture='mixed-signs', archive=root/'energy')
        assert scored['accepted'] and scored['score']['objective']['score'] == 86, scored
        invalid = root/'invalid.json'
        invalid.write_text('{invalid')
        failure = certify.certify(invalid, archive=root/'failed-cert')
        assert not failure['accepted'] and (root/'failed-cert/precheck/stdout.txt').exists()
        # A real improvement must pass all stages and become the incumbent.
        candidate = experiment.hand_reference('polynomial', (8, 8))
        encoded = base64.b64encode(zlib.compress(json.dumps(candidate).encode())).decode()
        generator = ('import base64, json, zlib\ndef build():\n'
                     f'    return json.loads(zlib.decompress(base64.b64decode({encoded!r})))\n')
        improved = search.run(root/'improved', dict(model='replay', task='polynomial', attempts=1),
                              replay=[reply(generator)])
        assert improved['best']['attempt'] == 1 and improved['best']['score'] == 63, improved
        assert improved['attempts'][0]['improved']
    print('PASS: real Docker isolation, timeout, archived Lean certificates and scores, failed attempts, resume, certified improvement')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--integration', action='store_true')
    args = parser.parse_args()
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(SearchTests))
    if not result.wasSuccessful():
        raise SystemExit(1)
    if args.integration:
        integration()
