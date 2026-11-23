"""A fixed product of instances, models and seeds, using independent processes."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import csv
import fcntl
import hashlib
import json
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import threading
import time

import search
from harness.archive import command, event, read_json, write_json

ROOT = search.ROOT


def settings(given):
    required = {'models', 'seeds', 'concurrency', 'run'}
    if not isinstance(given, dict) or not required <= set(given) or set(given) - required - {'instances'}:
        raise ValueError('Batch config requires models, seeds, concurrency, run; instances is optional.')
    models, seeds = given['models'], given['seeds']
    if not isinstance(models, dict) or not models:
        raise ValueError('models must map short names to provider/model IDs.')
    for name, model in models.items():
        if not re.fullmatch(r'[a-z0-9][a-z0-9_-]{0,31}', name) or not isinstance(model, str) or '/' not in model:
            raise ValueError('Invalid model name or provider/model ID.')
    if len(set(models.values())) != len(models):
        raise ValueError('Duplicate model IDs.')
    if not isinstance(seeds, list) or not seeds or any(type(s) is not int or not 0 <= s <= 0x7fffffff for s in seeds):
        raise ValueError('seeds must be a nonempty list of integers in 0..2147483647.')
    if len(set(seeds)) != len(seeds):
        raise ValueError('Duplicate seeds.')
    concurrency = given['concurrency']
    if type(concurrency) is not int or not 1 <= concurrency <= 32:
        raise ValueError('concurrency must be in 1..32.')
    common = given['run']
    if not isinstance(common, dict) or {'model', 'seed'} & set(common):
        raise ValueError('Put model IDs and seeds in models/seeds, not run.')
    normalized = search.settings(common | dict(model=next(iter(models.values())), seed=seeds[0]))
    normalized.pop('model')
    normalized.pop('seed')
    result = dict(models=models, seeds=seeds, concurrency=concurrency, run=normalized)
    if 'instances' in given:
        instances = given['instances']
        if not isinstance(instances, dict) or not instances:
            raise ValueError('instances must be a nonempty map of names to task/objective/configuration.')
        seen = set()
        for name, instance in instances.items():
            if not re.fullmatch(r'[a-z0-9][a-z0-9_-]{0,63}', name):
                raise ValueError('Invalid instance name.')
            if not isinstance(instance, dict) or set(instance) != {'task', 'objective', 'configuration'}:
                raise ValueError('Each instance requires exactly task, objective, configuration.')
            checked = search.settings(normalized | instance | dict(model=next(iter(models.values())), seed=seeds[0]))
            key = (checked['task'], checked['objective'], tuple(checked['configuration']))
            if key in seen:
                raise ValueError('Duplicate experiment instance.')
            seen.add(key)
        result['instances'] = instances
    return result


def jobs(config, smoke=False, smoke_attempts=2):
    if type(smoke_attempts) is not int or not 1 <= smoke_attempts <= 100:
        raise ValueError('smoke_attempts must be in 1..100.')
    result = []
    for instance, overrides in config.get('instances', {'default': {}}).items():
        for seed in config['seeds'][:1] if smoke else config['seeds']:
            for name, model in config['models'].items():
                prefix = f'{instance}/' if 'instances' in config else ''
                key = f'{prefix}{name}/seed-{seed}'
                run = config['run'] | overrides | dict(model=model, seed=seed)
                if smoke:
                    run['attempts'] = smoke_attempts
                result.append(dict(key=key, name=name, model=model, seed=seed, instance=instance, config=run,
                                   configPath=f'configs/{prefix}{name}-seed-{seed}.json', runPath=f'runs/{key}'))
    return result


def summarize(root, manifest):
    rows, attempts = [], []
    for job in manifest['jobs']:
        folder = root / job['runPath']
        summary = read_json(folder / 'summary.json') if (folder / 'summary.json').exists() else None
        result_file = root / 'jobs' / job['key'] / 'result.json'
        result = read_json(result_file) if result_file.exists() else {}
        completed = summary['completed'] if summary else 0
        status = 'complete' if completed == job['config']['attempts'] else result.get('status', 'stopped' if completed else 'pending')
        if status == 'complete' and completed != job['config']['attempts']:
            status = 'stopped'
        identity = dict(instance=job.get('instance', 'default'), task=job['config']['task'],
                        objective=job['config']['objective'], configuration=job['config']['configuration'])
        rows.append(dict(identity, name=job['name'], model=job['model'], seed=job['seed'],
                         directory=job['runPath'], status=status, completed=completed,
                         budget=job['config']['attempts'], best=summary['best'] if summary else None))
        if summary:
            for attempt in summary['attempts']:
                attempts.append(dict(attempt, **identity, model=job['model'], name=job['name'], seed=job['seed'],
                                     directory=job['runPath'] + '/' + attempt['directory']))
    result = dict(version='search-batch-summary-v1', mode=manifest['mode'],
                  status='complete' if all(r['status'] == 'complete' for r in rows) else 'incomplete',
                  plannedRuns=len(rows), completedRuns=sum(r['status'] == 'complete' for r in rows),
                  plannedAttempts=sum(r['budget'] for r in rows),
                  completedAttempts=sum(r['completed'] for r in rows), runs=rows)
    write_json(root / 'summary.json', result)
    with (root / 'attempts.csv').open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=['instance', 'task', 'objective', 'configuration', 'name', 'model', 'seed', 'attempt', 'accepted',
            'category', 'score', 'cycles', 'seconds', 'idea', 'directory'], extrasaction='ignore')
        writer.writeheader()
        writer.writerows(attempts)
    return result


def launch_job(root, job, cancel):
    if cancel.is_set():
        return dict(status='cancelled')
    folder = root / job['runPath']
    args = [sys.executable, str(ROOT / 'scripts/search.py'), '--output', str(folder)]
    if (folder / 'manifest.json').exists():
        args.append('--resume')
    else:
        args.extend(['--config', str(root / job['configPath'])])
    config = job['config']
    # Other active loops can occupy the single kernel slot before this one.
    concurrency = read_json(root / 'manifest.json')['config']['concurrency']
    phases = len(search.evaluator.TASKS[config['task']][3]) + 2 + concurrency - 1
    startup = 600 + (len(search.evaluator.TASKS[config['task']][3])+1) * config['check_timeout']
    limit = startup + config['attempts'] * (config['request_timeout'] + config['generator_timeout'] +
                                       phases * config['check_timeout'] + 60)
    log = root / 'jobs' / job['key'] / 'launches' / str(time.time_ns())
    process = command(args, log, cwd=ROOT, timeout=limit, cancel=cancel)
    summary = read_json(folder / 'summary.json') if (folder / 'summary.json').exists() else None
    complete = summary is not None and summary['completed'] == config['attempts']
    return dict(status='complete' if complete else 'stopped', process=process,
                log=str(log.relative_to(root)))


def inventory(root):
    entries = []
    for path in sorted(root.rglob('*')):
        if path.is_file() and path.name not in ('.lock', 'inventory.json'):
            digest = hashlib.sha256()
            with path.open('rb') as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                    digest.update(chunk)
            entries.append(dict(path=str(path.relative_to(root)), bytes=path.stat().st_size,
                                sha256=digest.hexdigest()))
    write_json(root / 'inventory.json', entries)


def run(root, config=None, *, resume=False, smoke=False, smoke_attempts=2, prepare_only=False, worker=launch_job):
    root = Path(root).resolve()
    normalized = None if resume else settings(config)
    planned = None if resume else jobs(normalized, smoke, smoke_attempts)
    if ',' in str(root):
        raise ValueError('Batch path cannot contain commas.')
    root.mkdir(parents=True, exist_ok=resume)
    with (root / '.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError('This batch is already active.')
        if resume:
            manifest = read_json(root / 'manifest.json')
            if manifest['sourceHashes'] != search.fingerprint() or manifest['python'] != platform.python_version():
                raise ValueError('Source or Python changed since this batch was prepared.')
            for job in manifest['jobs']:
                if read_json(root / job['configPath']) != job['config']:
                    raise ValueError('A prepared run configuration was changed.')
        else:
            manifest = dict(version='search-batch-v2', mode='smoke' if smoke else 'full',
                created=time.time(), config=normalized, jobs=planned,
                sourceHashes=search.fingerprint(), python=platform.python_version(),
                revision=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip())
            write_json(root / 'manifest.json', manifest)
            for relative in manifest['sourceHashes']:
                target = root / 'source' / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, target)
            (root / 'working-tree.patch').write_bytes(subprocess.check_output(['git', 'diff', 'HEAD'], cwd=ROOT))
            for job in manifest['jobs']:
                write_json(root / job['configPath'], job['config'])
            event(root, 'prepared', runs=len(manifest['jobs']),
                  attempts=sum(j['config']['attempts'] for j in manifest['jobs']))
        summary = summarize(root, manifest)
        if prepare_only:
            inventory(root)
            return summary
        complete = {r['directory'] for r in summary['runs'] if r['status'] == 'complete'}
        pending = [job for job in manifest['jobs'] if job['runPath'] not in complete]
        cancel = threading.Event()
        pool = ThreadPoolExecutor(max_workers=manifest['config']['concurrency'])
        futures = {}
        try:
            event(root, 'started', pendingRuns=len(pending))
            for job in pending:
                futures[pool.submit(worker, root, job, cancel)] = job
            for future in as_completed(futures):
                job = futures[future]
                try:
                    result = future.result()
                except Exception as exc:
                    result = dict(status='failed', type=type(exc).__name__, message=str(exc))
                write_json(root / 'jobs' / job['key'] / 'result.json', result)
                event(root, 'run-finished', key=job['key'], status=result['status'])
                summary = summarize(root, manifest)
                print(f"{job['key']}: {result['status']} ({summary['completedAttempts']}/{summary['plannedAttempts']} attempts)", flush=True)
        except BaseException:
            cancel.set()
            for future in futures:
                future.cancel()
            event(root, 'interrupted')
            raise
        finally:
            pool.shutdown(wait=True, cancel_futures=True)
            summary = summarize(root, manifest)
            event(root, 'finished', status=summary['status'])
            inventory(root)
        return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--smoke', action='store_true', help='short run for every instance/model, first seed only')
    parser.add_argument('--smoke-attempts', type=int, default=2, help='attempts per smoke run (default: 2); requires --smoke')
    group.add_argument('--prepare-only', action='store_true', help='write the plan and configs without launching any runs')
    group.add_argument('--resume', action='store_true', help='launch a prepared batch or continue unfinished runs')
    args = parser.parse_args()
    if (args.resume and args.config) or (not args.resume and not args.config):
        parser.error('Use --config for a new batch; --resume uses its saved config.')
    if args.smoke_attempts != 2 and not args.smoke:
        parser.error('--smoke-attempts requires --smoke.')
    try:
        result = run(args.output, read_json(args.config) if args.config else None,
                     resume=args.resume, smoke=args.smoke, smoke_attempts=args.smoke_attempts, prepare_only=args.prepare_only)
    except (ValueError, OSError, RuntimeError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print(json.dumps({k: result[k] for k in ('status', 'plannedRuns', 'completedRuns', 'plannedAttempts', 'completedAttempts')}))
    return 0 if args.prepare_only or result['status'] == 'complete' else 1


if __name__ == '__main__':
    sys.exit(main())
