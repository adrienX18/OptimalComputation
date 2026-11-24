#!/usr/bin/env python3
"""Audit the raw smoke archive and export descriptive, reproducible tables."""
import argparse
from collections import Counter
import csv
import hashlib
import json
from pathlib import Path
import runpy
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT/'scripts'))


def read(path):
    return json.loads(path.read_text())


def write_csv(path, rows):
    with path.open('w', newline='') as stream:
        writer = csv.DictWriter(stream, list(rows[0]), lineterminator='\n')
        writer.writeheader()
        writer.writerows(rows)


def detail(row):
    category = row['category']
    if category == 'proposal-error':
        message = row['message']
        if 'content_filter' in message:
            return 'Filtered response'
        if message == 'Generator exceeds code_bytes.':
            return 'Code limit'
        return 'Invalid JSON'
    return {'certified': 'Certified', 'simulation-failed': 'Simulation failed',
            'range-not-proved': 'Range unproved', 'api-error': 'API error',
            'kernel-timeout': 'Proof timeout', 'interrupted': 'Interrupted'}[category]


def analyze(archive):
    audit = runpy.run_path(str(ROOT/'scripts/audit-search-batch.py'))['audit'](archive)
    manifest = read(archive/'manifest.json')
    events = [json.loads(line) for line in (archive/'events.jsonl').read_text().splitlines()]
    started = next(e['time'] for e in events if e['event'] == 'started')
    finished = [e['time'] for e in events if e['event'] == 'finished' and e['status'] == 'complete'][-1]
    attempts, runs, curves, kernels = [], [], [], []
    for job in manifest['jobs']:
        folder = archive/job['runPath']
        baseline, summary = read(folder/'baseline.json'), read(folder/'summary.json')
        best = baseline['score']
        first_best = 0
        common = dict(instance=job['instance'], task=job['config']['task'], model=job['name'],
                      model_id=job['model'], seed=job['seed'], objective=job['config']['objective'],
                      initial_lanes=job['config']['configuration'][0],
                      initial_banks=job['config']['configuration'][1], unit=baseline['unit'])
        curves.append(common | dict(attempt=0, best_score=best, baseline_ratio=1.0, interrupted=False))
        winner_lanes, winner_banks = job['config']['configuration']
        for row in summary['attempts']:
            directory = folder/row['directory']
            response = read(directory/'response.json') if (directory/'response.json').exists() else {}
            api_error = read(directory/'api-error.json') if (directory/'api-error.json').exists() else {}
            request = read(directory/'request.json') if (directory/'request.json').exists() else {}
            score = read(directory/'score.json') if row['accepted'] else {}
            if row['accepted'] and row['score'] < best:
                best, first_best = row['score'], row['attempt']
                winner_lanes, winner_banks = [score['configuration'][k] for k in ('lanes', 'banks')]
            if 'bestScore' in row:
                assert best == row['bestScore']
            assert best <= baseline['score']
            curves.append(common | dict(attempt=row['attempt'], best_score=best,
                baseline_ratio=baseline['score']/best, interrupted=row['category']=='interrupted'))
            usage = response.get('usage') or {}
            attempts.append(common | dict(attempt=row['attempt'], category=row['category'],
                outcome=detail(row), accepted=row['accepted'], score=row.get('score', ''),
                best_score=best, attempt_seconds=row.get('seconds', ''),
                api_seconds=response.get('seconds', api_error.get('seconds', '')),
                input_tokens=usage.get('prompt_tokens', ''), output_tokens=usage.get('completion_tokens', ''),
                prompt_bytes=len(json.dumps(request['messages'], ensure_ascii=False).encode()) if request else '',
                selected_lanes=score.get('configuration', {}).get('lanes', ''),
                selected_banks=score.get('configuration', {}).get('banks', ''),
                directory=str(directory.relative_to(archive))))
            kernel = directory/'certification/kernel'
            if (kernel/'result.json').exists():
                result, req = read(kernel/'result.json'), read(kernel/'request.json')
                kernels.append(common | dict(attempt=row['attempt'], status=result['status'],
                    seconds=result['seconds'], exit_code=result.get('exitCode', ''),
                    start_seconds=req['started']-started))
        assert best == summary['best']['score']
        counts = Counter(row['category'] for row in summary['attempts'])
        runs.append(common | dict(baseline=baseline['score'], best_score=best,
            baseline_ratio=baseline['score']/best, reduction_percent=100*(1-best/baseline['score']),
            certified=counts['certified'], interrupted=counts['interrupted'],
            improved=best < baseline['score'], first_final_best=first_best,
            winner_lanes=winner_lanes, winner_banks=winner_banks, directory=job['runPath']))
    assert len(runs) == 80 and len(attempts) == 240 and len(curves) == 320
    assert Counter(r['category'] for r in attempts) == Counter(audit['categories'])
    for name, rows in [('runs', runs), ('attempts', attempts), ('convergence', curves), ('kernel-checks', kernels)]:
        write_csv(HERE/(name+'.csv'), rows)
    metrics = dict(version='suite-smoke-analysis-v1', source=archive.name,
        manifest_sha256=audit['manifestSha256'], inventory_sha256=audit['inventorySha256'],
        source_revision=manifest['revision'], audit=audit | {'runs': None},
        scope=dict(cases=16, models=5, seeds=[11], slots_per_loop=3),
        elapsed_seconds=finished-started, outcomes=dict(Counter(r['outcome'] for r in attempts)),
        improved_loops=sum(r['improved'] for r in runs),
        loops_with_certified_proposal=sum(r['certified'] > 0 for r in runs),
        last_slot_improved_loops=sum(r['first_final_best'] == 3 for r in runs),
        by_model={model: dict(certified=sum(r['accepted'] for r in attempts if r['model']==model),
            improved_loops=sum(r['improved'] for r in runs if r['model']==model),
            first_final_best=dict(Counter(r['first_final_best'] for r in runs if r['model']==model)))
            for model in manifest['config']['models']},
        uncertainty='One seed per case/model. Descriptive census only; no confidence intervals or significance tests. Cases are not exchangeable repeats.',
        source_tables={name:hashlib.sha256((HERE/name).read_bytes()).hexdigest()
                       for name in ('runs.csv','attempts.csv','convergence.csv','kernel-checks.csv')})
    (HERE/'metrics.json').write_text(json.dumps(metrics, indent=2)+'\n')
    print(json.dumps({k:metrics[k] for k in ('outcomes','improved_loops','loops_with_certified_proposal','last_slot_improved_loops','by_model')}, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, default=ROOT/'runs/suite-smoke-20261123')
    analyze(parser.parse_args().archive.resolve())
