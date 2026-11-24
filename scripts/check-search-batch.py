#!/usr/bin/env python3
"""Offline batch planning, concurrency, resume and cancellation regressions."""
from contextlib import redirect_stdout
import io
import json
from pathlib import Path
import sys
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

import search_batch as batch
from harness.archive import command, read_json, write_json


class BatchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / 'batch'
        self.config = read_json(batch.ROOT/'configs/search.batch.json')
        self.active = self.maximum = 0
        self.calls = []
        self.lock = threading.Lock()

    def tearDown(self):
        self.temp.cleanup()

    def worker(self, root, job, cancel):
        with self.lock:
            self.active += 1
            self.maximum = max(self.maximum, self.active)
            self.calls.append(job['key'])
        try:
            time.sleep(.02)
            where = root / job['runPath']
            write_json(where/'summary.json', dict(completed=job['config']['attempts'],
                       best=dict(score=10, unit='cycles'), attempts=[]))
            return dict(status='complete')
        finally:
            with self.lock:
                self.active -= 1

    def run_batch(self, **kwargs):
        with redirect_stdout(io.StringIO()):
            return batch.run(self.root, self.config, worker=self.worker, **kwargs)

    def test_exact_matrix_and_prepare_does_not_launch(self):
        result = self.run_batch(prepare_only=True)
        self.assertEqual((result['plannedRuns'], result['plannedAttempts']), (25, 1250))
        self.assertEqual(self.calls, [])
        manifest = read_json(self.root/'manifest.json')
        self.assertEqual((self.root/'source/scripts/search_batch.py').read_bytes(),
                         (batch.ROOT/'scripts/search_batch.py').read_bytes())
        self.assertEqual(len({(j['model'], j['seed']) for j in manifest['jobs']}), 25)
        self.assertTrue(all(j['config']['attempts'] == 50 for j in manifest['jobs']))
        for job in manifest['jobs']:
            self.assertEqual(read_json(self.root/job['configPath']), job['config'])
        with self.assertRaises(FileExistsError):
            self.run_batch(prepare_only=True)

    def test_smoke_parallelism_and_resume_skips_completed(self):
        self.config['concurrency'] = 2
        result = self.run_batch(smoke=True)
        self.assertEqual((result['plannedRuns'], result['plannedAttempts']), (5, 10))
        self.assertEqual(result['status'], 'complete')
        self.assertEqual(self.maximum, 2)
        before = list(self.calls)
        self.run_batch(resume=True)
        self.assertEqual(before, self.calls)
        self.assertTrue((self.root/'inventory.json').exists())

    def test_prepare_then_resume_and_refuse_config_changes(self):
        self.run_batch(prepare_only=True)
        manifest = read_json(self.root/'manifest.json')
        path = self.root/manifest['jobs'][0]['configPath']
        original = path.read_bytes()
        write_json(path, {'changed': True})
        with self.assertRaisesRegex(ValueError, 'configuration was changed'):
            self.run_batch(resume=True)
        path.write_bytes(original)
        result = self.run_batch(resume=True)
        self.assertEqual(result['completedRuns'], 25)
        self.assertEqual(len(self.calls), 25)
        with patch.object(batch.search, 'fingerprint', return_value={}):
            with self.assertRaisesRegex(ValueError, 'Source or Python changed'):
                self.run_batch(resume=True)

    def test_invalid_seed_and_duplicate_models(self):
        for change in [dict(seeds=[11,11]), dict(seeds=[True]), dict(concurrency=0),
                       dict(models={'a':'openai/test','b':'openai/test'})]:
            with self.assertRaises(ValueError):
                batch.settings(self.config | change)

    def test_full_suite_and_three_step_smoke(self):
        self.config = read_json(batch.ROOT/'configs/search.suite.json')
        config = batch.settings(self.config)
        full = batch.jobs(config)
        short = batch.jobs(config, smoke=True, smoke_attempts=3)
        self.assertEqual((len(full), sum(j['config']['attempts'] for j in full)), (400, 20000))
        self.assertEqual((len(short), sum(j['config']['attempts'] for j in short)), (80, 240))
        self.assertEqual(len({j['key'] for j in full}), 400)
        self.assertEqual(len({j['configPath'] for j in full}), 400)
        self.assertEqual({j['seed'] for j in short}, {11})
        for task in ['matmul', 'polynomial', 'gram', 'two-stage']:
            selected = [j for j in short if j['config']['task'] == task]
            self.assertEqual(len(selected), 20)
            self.assertEqual({(j['config']['objective'], tuple(j['config']['configuration'])) for j in selected},
                {('latency-v1', (8,8)), ('latency-v1', (8,1)), ('latency-v1', (2,8)), ('energy-proxy-v1', (8,8))})
        result = self.run_batch(smoke=True, smoke_attempts=3)
        self.assertEqual(result['completedAttempts'], 240)
        self.assertEqual({r['instance'] for r in result['runs']}, set(config['instances']))
        before = list(self.calls)
        self.run_batch(resume=True)
        self.assertEqual(before, self.calls)

    def test_invalid_instances_and_smoke_budget(self):
        instance = dict(task='polynomial', objective='latency-v1', configuration=[8,8])
        for instances in [{}, {'../escape': instance}, {'a': instance, 'b': instance},
                          {'a': instance | {'attempts': 3}}, {'a': instance | {'configuration': [3,8]}}]:
            with self.assertRaises(ValueError):
                batch.settings(self.config | dict(instances=instances))
        for attempts in [0,101,True,3.5]:
            with self.assertRaises(ValueError):
                batch.jobs(batch.settings(self.config), smoke=True, smoke_attempts=attempts)

    def test_partial_failure_is_retained_and_resume_only_retries_that_run(self):
        def partial(root, job, cancel):
            if job['name'] == 'fable':
                write_json(root/job['runPath']/'summary.json',
                           dict(completed=1, best=dict(score=100), attempts=[]))
                return dict(status='stopped', reason='provider error')
            return self.worker(root, job, cancel)
        with redirect_stdout(io.StringIO()):
            result = batch.run(self.root, self.config, smoke=True, worker=partial)
        self.assertEqual(result['status'], 'incomplete')
        self.assertEqual(result['completedRuns'], 4)
        self.assertEqual(result['completedAttempts'], 9)
        self.assertEqual(read_json(self.root/'jobs/fable/seed-11/result.json')['reason'], 'provider error')
        self.calls.clear()
        result = self.run_batch(resume=True)
        self.assertEqual(self.calls, ['fable/seed-11'])
        self.assertEqual(result['status'], 'complete')

    def test_process_cancellation_is_recorded(self):
        cancel = threading.Event()
        timer = threading.Timer(.15, cancel.set)
        timer.start()
        try:
            result = command([sys.executable, '-c', 'import time; print("started",flush=True); time.sleep(60)'],
                             Path(self.temp.name)/'process', cwd=batch.ROOT, timeout=90, cancel=cancel)
        finally:
            timer.join()
        self.assertEqual(result['status'], 'interrupted')
        self.assertLess(result['seconds'], 6)


class AuditResumeTests(unittest.TestCase):
    def audit(self, root):
        from runpy import run_path
        return run_path(str(batch.ROOT/'scripts/audit-search-batch.py'))['audit'](root)

    def fixture(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)/'archive'
        folder = root/'runs/test/seed-11'
        config = dict(attempts=4, prompt_bytes=1024, model='openai/test',
                      objective='latency-v1', configuration=[8, 8])
        job = dict(runPath='runs/test/seed-11', config=config, model='openai/test',
                   name='test', seed=11, instance='fixture')
        write_json(root/'manifest.json', dict(jobs=[job], sourceHashes={}))
        write_json(folder/'manifest.json', dict(config=config, sourceHashes={}))
        write_json(folder/'baseline.json', dict(score=10, unit='cycles'))
        rows = []
        for index in range(1, 5):
            interrupted = index != 1
            row = dict(attempt=index, directory=f'attempts/{index:04d}', accepted=False,
                       category='interrupted' if interrupted else 'proposal-error')
            if not interrupted:
                row['bestScore'] = 10
            where = folder/row['directory']
            write_json(where/'feedback.json', row)
            # Interruptions before metadata, during a call, and after a response.
            if index != 2:
                write_json(where/'request.json', dict(model='openai/test',
                           messages=[dict(role='user', content='test')]))
                write_json(where/'randomness.json', dict(runSeed=11))
            if index in (1, 4):
                write_json(where/'response.json', {})
                write_json(where/'provider-001-response.json', {})
            rows.append(row)
        write_json(folder/'summary.json', dict(completed=4, attempts=rows, best=dict(score=10)))
        batch.inventory(root)
        return root, folder

    def test_audit_preserves_partial_attempts_after_resume(self):
        root, _ = self.fixture()
        result = self.audit(root)
        self.assertEqual(result['completedAttempts'], 4)
        self.assertEqual(result['categories'], {'proposal-error': 1, 'interrupted': 3})
        self.assertEqual(result['runs'][0]['responses'], 2)
        self.assertEqual(result['runs'][0]['best'], 10)

    def test_finished_attempts_still_require_complete_records(self):
        for filename in ('request.json', 'randomness.json', 'response.json',
                         'provider-001-response.json'):
            with self.subTest(filename=filename):
                root, folder = self.fixture()
                (folder/'attempts/0001'/filename).unlink()
                batch.inventory(root)
                with self.assertRaises(AssertionError):
                    self.audit(root)

    def test_interrupted_responses_still_require_request_and_provider_records(self):
        for filename in ('request.json', 'randomness.json', 'provider-001-response.json'):
            with self.subTest(filename=filename):
                root, folder = self.fixture()
                (folder/'attempts/0004'/filename).unlink()
                batch.inventory(root)
                with self.assertRaises(AssertionError):
                    self.audit(root)

    def test_resume_cannot_accept_an_interrupted_attempt_or_change_the_incumbent(self):
        for index, field, value in ((1, 'bestScore', None), (4, 'accepted', True),
                                    (4, 'bestScore', 9)):
            with self.subTest(index=index, field=field):
                root, folder = self.fixture()
                summary = read_json(folder/'summary.json')
                row = summary['attempts'][index-1]
                if value is None:
                    row.pop(field)
                else:
                    row[field] = value
                write_json(folder/row['directory']/'feedback.json', row)
                write_json(folder/'summary.json', summary)
                batch.inventory(root)
                with self.assertRaises(AssertionError):
                    self.audit(root)


if __name__ == '__main__':
    unittest.main(verbosity=2)
