#!/usr/bin/env python3
"""A deliberately sequential, bounded LLM proposal -> feedback loop."""
import argparse
import csv
import fcntl
import hashlib
import json
import math
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import time
import traceback
from urllib.parse import urlsplit

from harness import evaluate as evaluator
from harness import prompt
from harness.archive import event, read_json, write_json
from harness.model import Model, ReplayModel, scrub
from harness.randomness import attempt_seed

ROOT = Path(__file__).resolve().parents[1]
DEFAULTS = dict(task='matvec', objective='latency-v1', configuration=[8, 8], attempts=100, seed=0,
                max_tokens=32768, prompt_bytes=32000, code_bytes=8000, notes_bytes=2000,
                request_timeout=600, generator_timeout=30, check_timeout=120,
                boundaries=1000000, terms=4096, image='python:3.12-slim-bookworm')


def settings(given):
    if not isinstance(given, dict):
        raise ValueError('Configuration must be a JSON object.')
    allowed = set(DEFAULTS) | {'model', 'api_base', 'temperature', 'reasoning_effort'}
    if set(given) - allowed:
        raise ValueError(f'Unknown configuration fields: {sorted(set(given)-allowed)}')
    config = DEFAULTS | given
    if not isinstance(config.get('model'), str) or not config['model']:
        raise ValueError('model is required (provider/model).')
    if config['task'] not in evaluator.TASKS or config['objective'] not in ('latency-v1', 'energy-proxy-v1'):
        raise ValueError('Unknown task or objective.')
    if not isinstance(config['configuration'], list) or len(config['configuration']) != 2 or any(
            type(x) is not int or x not in (1, 2, 4, 8) for x in config['configuration']):
        raise ValueError('configuration must be [lanes, banks], each 1,2,4,8.')
    for key in ('attempts', 'max_tokens', 'prompt_bytes', 'code_bytes', 'notes_bytes', 'boundaries', 'terms'):
        if type(config[key]) is not int or config[key] <= 0:
            raise ValueError(f'{key} must be a positive integer.')
    if config['attempts'] > 100:
        raise ValueError('At most 100 attempts per run.')
    if type(config['seed']) is not int or not 0 <= config['seed'] <= 0x7fffffff:
        raise ValueError('seed must be an integer between 0 and 2147483647.')
    for key in ('request_timeout', 'generator_timeout', 'check_timeout'):
        if type(config[key]) not in (int, float) or not math.isfinite(config[key]) or config[key] <= 0:
            raise ValueError(f'{key} must be finite and positive.')
    if 'temperature' in config and (type(config['temperature']) not in (int, float) or
                                   not math.isfinite(config['temperature']) or not 0 <= config['temperature'] <= 2):
        raise ValueError('temperature must be between 0 and 2.')
    if 'reasoning_effort' in config and not isinstance(config['reasoning_effort'], str):
        raise ValueError('reasoning_effort must be a string.')
    if not isinstance(config['image'], str) or not config['image']:
        raise ValueError('image must be a Docker image reference.')
    if 'api_base' in config:
        if not isinstance(config['api_base'], str):
            raise ValueError('api_base must be a string.')
        url = urlsplit(config['api_base'])
        if url.scheme not in ('http', 'https') or not url.netloc or url.username or url.password or url.query or url.fragment:
            raise ValueError('api_base must be an HTTP(S) URL without credentials, query or fragment.')
    return config


def fingerprint():
    paths = list((ROOT / 'scripts').rglob('*.py')) + list((ROOT / 'OptimalComputation').rglob('*.lean'))
    paths += [ROOT / name for name in ('Main.lean', 'CertificationMain.lean', 'lakefile.toml', 'lean-toolchain', 'requirements-search.txt')]
    return {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(paths)}


def proposal(response, config):
    choice = response['choices'][0]
    if choice.get('finish_reason') not in ('stop', 'end_turn'):
        raise ValueError(f"Incomplete response: {choice.get('finish_reason')}")
    content = choice['message']['content']
    if not isinstance(content, str):
        raise ValueError('Expected a text response.')
    text = content.strip()
    if text.startswith('```json\n') and text.endswith('```'):
        text = text[8:-3]
    result = evaluator.strict_json(text)
    if not isinstance(result, dict) or set(result) != {'idea', 'code', 'notes'} or not all(isinstance(v, str) for v in result.values()):
        raise ValueError('Return exactly three strings: idea, code, notes.')
    if len(result['code'].encode()) > config['code_bytes']:
        raise ValueError('Generator exceeds code_bytes.')
    if not result['code'].strip():
        raise ValueError('Empty generator.')
    return result


def summarize(root, baseline, rows):
    best = dict(attempt=0, directory=baseline['directory'], score=baseline['score'],
                unit=baseline['unit'], accepted=True, category='baseline')
    for row in rows:
        if row['accepted'] and row['score'] < best['score']:
            best = row
    write_json(root / 'best.json', best)
    write_json(root / 'summary.json', dict(completed=len(rows), best=best, attempts=rows))
    with (root / 'summary.csv').open('w', newline='') as stream:
        fields = ['attempt', 'accepted', 'category', 'score', 'cycles', 'seconds', 'idea', 'directory']
        writer = csv.DictWriter(stream, fields, extrasaction='ignore')
        writer.writeheader()
        writer.writerows(rows)


def run(root, config=None, *, resume=False, replay=None, model=None, engine=evaluator):
    if not resume:
        config = settings(config)
    root = Path(root).resolve()
    if ',' in str(root):
        raise ValueError('The run path cannot contain commas (Docker mount syntax).')
    root.mkdir(parents=True, exist_ok=resume)
    with (root / '.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise ValueError('This run is already active.')
        current = fingerprint()
        if resume:
            manifest = read_json(root / 'manifest.json')
            config = manifest['config']
            if current != manifest['sourceHashes']:
                raise ValueError('Source changed since this run. Restore it or start a new run.')
            if platform.python_version() != manifest['python']:
                raise ValueError('Python version changed since this run.')
            replay = manifest.get('replay')
        else:
            config = settings(config)
            manifest = dict(version='naive-search-v1', config=config, created=time.time(),
                            sourceHashes=current, python=platform.python_version(), replay=replay,
                            revision=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip())
            write_json(root / 'manifest.json', manifest)
            (root / 'source').mkdir()
            for relative in current:
                target = root / 'source' / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / relative, target)
            (root / 'working-tree.patch').write_bytes(subprocess.check_output(['git', 'diff', 'HEAD'], cwd=ROOT))
        event(root, 'resumed' if resume else 'started')
        startup = root / 'startup' / str(time.time_ns())
        image = engine.resolve_image(config['image'], startup)
        if manifest.get('imageId') not in (None, image):
            raise ValueError('Docker image changed since this run.')
        manifest['imageId'] = image
        model = model or (ReplayModel(replay) if replay is not None else Model(config))
        version = getattr(model, 'version', 'injected-test-model')
        if manifest.get('adapterVersion') not in (None, version):
            raise ValueError('Model adapter version changed since this run.')
        manifest['adapterVersion'] = version
        dependencies = getattr(model, 'dependencies', {})
        if manifest.get('dependencies') not in (None, dependencies):
            raise ValueError('Model dependencies changed since this run.')
        manifest['dependencies'] = dependencies
        seed_supported = getattr(model, 'seed_supported', False)
        if manifest.get('apiSeedSupported') not in (None, seed_supported):
            raise ValueError('API seed support changed since this run.')
        manifest['apiSeedSupported'] = seed_supported
        manifest['seedPolicy'] = 'naive-search-seed-v1; local PRNG/hash seed; API seed when supported; API output is not guaranteed deterministic'
        write_json(root / 'manifest.json', manifest)
        if (root / 'baseline.json').exists():
            baseline = read_json(root / 'baseline.json')
        else:
            directory = root / 'baseline' / str(time.time_ns())
            directory.parent.mkdir(exist_ok=True)
            baseline = engine.initialize(config, directory)
            baseline['directory'] = str(directory.relative_to(root))
            write_json(root / 'baseline.json', baseline)
        (root / 'attempts').mkdir(exist_ok=True)
        rows = []
        for directory in sorted((root / 'attempts').iterdir()):
            if not directory.is_dir():
                continue
            path = directory / 'feedback.json'
            if not path.exists():
                # Never silently reissue a potentially billed model call on resume.
                container = directory / 'generation/container.json'
                if container.exists():
                    from harness.archive import command
                    command(['docker', 'rm', '-f', read_json(container)['name']],
                            directory / f'resume-cleanup-{time.time_ns()}', cwd=ROOT, timeout=30)
                row = dict(attempt=int(directory.name), directory=str(directory.relative_to(root)),
                           accepted=False, category='interrupted', message='Interrupted attempt; artifacts retained.')
                write_json(path, row)
                event(root, 'attempt-interrupted', attempt=row['attempt'])
            rows.append(read_json(path))
        summarize(root, baseline, rows)
        consecutive_api_errors = 0
        for index in range(len(rows)+1, config['attempts']+1):
            messages = prompt.build(config, baseline, rows, root)
            directory = root / 'attempts' / f'{index:04d}'
            directory.mkdir()
            started = time.monotonic()
            request = dict(model=config['model'], messages=messages, max_tokens=config['max_tokens'],
                           timeout=config['request_timeout'], num_retries=0, stream=False)
            seed = attempt_seed(config['seed'], index)
            if seed_supported:
                request['seed'] = seed
            for key in ('temperature', 'reasoning_effort', 'api_base'):
                if key in config:
                    request[key] = config[key]
            write_json(directory / 'request.json', request)
            write_json(directory / 'randomness.json', dict(version='naive-search-seed-v1',
                       runSeed=config['seed'], attemptSeed=seed,
                       apiSeed=seed if seed_supported else None, apiSeedSupported=seed_supported))
            event(root, 'attempt-started', attempt=index)
            idea = ''
            stage = 'api'
            try:
                response = model(request, directory)
                # Also enforce storage for injected adapters used in tests.
                if not (directory / 'response.json').exists():
                    write_json(directory / 'response.json', scrub(response))
                stage = 'proposal'
                parsed = proposal(response, config)
                write_json(directory / 'proposal.json', parsed)
                idea = prompt.clip(parsed['idea'], 300)
                (directory / 'generator.py').write_text(parsed['code'])
                stage = 'generation'
                feedback = engine.generate(parsed['code'], baseline['raw'], directory / 'generation', image,
                                           config['generator_timeout'], seed=seed)
                if feedback is None:
                    stage = 'evaluation'
                    feedback = engine.evaluate(config, baseline, directory)
            except Exception as exc:
                feedback = dict(accepted=False, category=f'{stage}-error', message=str(scrub(str(exc))))
                write_json(directory / 'error.json', dict(stage=stage, type=type(exc).__name__, message=feedback['message'], traceback=scrub(traceback.format_exc())))
            row = dict(feedback, attempt=index, idea=idea, directory=str(directory.relative_to(root)),
                       seconds=round(time.monotonic()-started, 3))
            previous_best = min([baseline['score']] + [r['score'] for r in rows if r['accepted']])
            row['improved'] = row['accepted'] and row['score'] < previous_best
            row['bestScore'] = min(previous_best, row['score']) if row['accepted'] else previous_best
            write_json(directory / 'feedback.json', row)
            event(root, 'attempt-completed', **row)
            rows.append(row)
            summarize(root, baseline, rows)
            print(f"{index}/{config['attempts']}: {row['category']}" + (f" score={row['score']}" if row['accepted'] else ''), flush=True)
            consecutive_api_errors = consecutive_api_errors + 1 if stage == 'api' else 0
            if consecutive_api_errors >= 3:
                event(root, 'stopped', reason='Three consecutive API errors; resume explicitly.')
                return read_json(root / 'summary.json')
        event(root, 'finished', attempts=len(rows))
        return read_json(root / 'summary.json')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, help='JSON configuration for a new run')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--resume', action='store_true')
    parser.add_argument('--replay', type=Path, help='offline JSON list of model responses; still uses the real sandbox and verifier')
    args = parser.parse_args()
    if args.resume and (args.config or args.replay):
        parser.error('--resume uses the saved configuration and responses')
    if not args.resume and not args.config:
        parser.error('--config is required for a new run')
    try:
        result = run(args.output, read_json(args.config) if args.config else None, resume=args.resume,
                     replay=read_json(args.replay) if args.replay else None)
    except (ValueError, OSError, RuntimeError, ImportError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    print('Best:', result['best']['score'], result['best']['unit'], 'from', result['best']['directory'])
    return 0


if __name__ == '__main__':
    sys.exit(main())
