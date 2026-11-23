#!/usr/bin/env python3
"""Read the frozen experiment; derive small, credential-free analysis artifacts.

Standard library only. Never calls a model, executes a generator, or edits the
input archive. The saved kernel outcomes are checked, not re-run.
"""
import argparse
from collections import Counter
import csv
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
from statistics import mean, median

REPO = Path(__file__).resolve().parents[2]
if not __debug__:
    raise SystemExit('Archive verification requires assertions; do not use -O or -OO.')


def read(path):
    return json.loads(path.read_text())


def sha(path):
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def normalized_candidate(candidate):
    # Ignore names, JSON key order, and the serialization order of instructions.
    # Preserve layout, register names, instructions, cycles and all other fields.
    candidate = dict(candidate)
    candidate.pop('identifier', None)
    candidate['schedule'] = sorted(candidate['schedule'],
                                   key=lambda item: json.dumps(item, sort_keys=True))
    return hashlib.sha256(json.dumps(candidate, sort_keys=True).encode()).hexdigest()


def write_csv(path, rows):
    with path.open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator='\n')
        writer.writeheader()
        writer.writerows(rows)


def analyze(archive):
    manifest = read(archive / 'manifest.json')
    batch = read(archive / 'summary.json')
    background = read(archive / 'background/result.json')
    assert batch['status'] == 'complete' and background['exitCode'] == 0
    inventory = read(archive / 'inventory.json')
    listed = set()
    for item in inventory:
        path = archive / item['path']
        assert path.stat().st_size == item['bytes'] and sha(path) == item['sha256'], path
        listed.add(item['path'])
    actual = {str(p.relative_to(archive)) for p in archive.rglob('*')
              if p.is_file() and p.name not in ('.lock', 'inventory.json')}
    assert actual == listed, 'Inventory coverage changed'
    attempts, runs, curves = [], [], []
    raw_refusals = Counter()
    for job in manifest['jobs']:
        folder = archive / job['runPath']
        run_manifest = read(folder / 'manifest.json')
        summary = read(folder / 'summary.json')
        baseline = read(folder / 'baseline.json')
        assert run_manifest['config'] == job['config']
        assert summary['completed'] == len(summary['attempts']) == job['config']['attempts']
        incumbent = baseline['score']
        elapsed = 0
        best_seen_at = 0
        for index, row in enumerate(summary['attempts'], 1):
            assert row['attempt'] == index
            where = folder / row['directory']
            assert read(where / 'feedback.json') == row
            request = read(where / 'request.json')
            assert request['model'] == job['model']
            assert len(list(where.glob('provider-*-request.json'))) == 1
            context = json.loads(request['messages'][1]['content'])
            assert context['attempt'] == index and context['runSeed'] == job['seed']
            response = read(where / 'response.json') if (where / 'response.json').exists() else None
            error = read(where / 'api-error.json') if (where / 'api-error.json').exists() else None
            assert (response is None) != (error is None)
            usage = response.get('usage') or {} if response else {}
            finish = response['choices'][0]['finish_reason'] if response else None
            if response:
                assert list(where.glob('provider-*-response.json'))
            if finish == 'content_filter':
                raw = read(next(where.glob('provider-*-response.json')))['response']
                raw = json.loads(raw) if isinstance(raw, str) else raw
                raw_refusals[raw['stop_reason']] += 1
            generator = where / 'generator.py'
            candidate = where / 'candidate.json'
            code = sha(generator) if generator.exists() else None
            normalized = normalized_candidate(read(candidate)) if row['accepted'] else None
            if row['accepted']:
                proof = read(where / 'certification/result.json')
                score = read(where / 'score.json')
                assert proof['accepted'] and proof['candidateSha256'] == sha(candidate)
                assert proof['certificateSha256'] == sha(where / 'certification/Certificate.lean')
                assert read(where / 'certification/kernel/result.json')['exitCode'] == 0
                assert score['verificationStatus'] == 'all-input-certified'
                assert score['objective']['score'] == row['score']
                if row['score'] < incumbent:
                    incumbent = row['score']
                    best_seen_at = index
            assert incumbent == row['bestScore']
            elapsed += row['seconds']
            detail = row.get('message', '')
            if row['category'] == 'simulation-failed':
                report = row['failure'].get('report') or {}
                detail = (report.get('details') or {}).get('violation', {}).get('name', report.get('category'))
            if row['category'] == 'generator-failed':
                detail = row['process']['status']
            if row['category'] == 'range-not-proved':
                detail = row.get('message', '')
                simulations = read(where / 'simulations.json')
                assert simulations and all(check['passed'] for check in simulations)
            if error:
                detail = error['type']
            attempts.append(dict(model=job['name'], seed=job['seed'], attempt=index,
                category=row['category'], detail=detail, accepted=row['accepted'],
                score=row.get('score'), best=incumbent, improved=row['improved'],
                wallSeconds=row['seconds'], elapsedSeconds=round(elapsed, 3),
                apiSeconds=round((response or error)['seconds'], 3),
                promptTokens=usage.get('prompt_tokens'), outputTokens=usage.get('completion_tokens'),
                reasoningTokens=(usage.get('completion_tokens_details') or {}).get('reasoning_tokens'),
                estimatedCostUSD=response.get('estimatedCostUSD') if response else None,
                finishReason=finish, promptBytes=len(json.dumps(request['messages'], ensure_ascii=False).encode()),
                historyRows=len(context['history']), codeSha256=code, candidateSha256=normalized,
                directory=str(where.relative_to(archive))))
            curves.append(dict(model=job['name'], seed=job['seed'], attempt=index,
                               bestCycles=incumbent, elapsedSeconds=round(elapsed, 3)))
        assert incumbent == summary['best']['score']
        assert best_seen_at == summary['best']['attempt']
        chosen = folder / summary['best']['directory']
        score = read(chosen / 'score.json')
        counters = score['execution']['counters']
        these = [a for a in attempts if a['model'] == job['name'] and a['seed'] == job['seed']]
        runs.append(dict(model=job['name'], seed=job['seed'], attempts=len(these),
            certified=sum(a['accepted'] for a in these), baselineCycles=baseline['score'],
            bestCycles=incumbent, bestFirstAttempt=best_seen_at,
            first30Attempt=next((a['attempt'] for a in these if a['best'] <= 30), None),
            secondsToBest=next(a['elapsedSeconds'] for a in these if a['attempt'] == best_seen_at),
            wallSeconds=round(elapsed, 3),
            improvements=sum(a['improved'] for a in these),
            uniqueCertifiedCandidates=len({a['candidateSha256'] for a in these if a['accepted']}),
            scheduleSize=score['execution']['scheduleSize'], loads=counters['loads'],
            stores=counters['stores'], multiplications=counters['multiplications'],
            multiplyAdds=counters['multiplyAdds'],
            bestDirectory=str(chosen.relative_to(archive))))
    assert len(attempts) == batch['completedAttempts'] == 1250
    assert len(runs) == batch['completedRuns'] == 25
    models = {}
    for name in manifest['config']['models']:
        rows = [a for a in attempts if a['model'] == name]
        selected = [r for r in runs if r['model'] == name]
        winners = [r['bestFirstAttempt'] for r in selected]
        categories = Counter(a['category'] for a in rows)
        codes = {a['codeSha256'] for a in rows if a['codeSha256']}
        candidates = {a['candidateSha256'] for a in rows if a['accepted']}
        models[name] = dict(modelId=manifest['config']['models'][name],
            finalBests=[r['bestCycles'] for r in selected], medianBest=median(r['bestCycles'] for r in selected),
            meanBest=mean(r['bestCycles'] for r in selected),
            bestFirstAttempts=winners, medianBestFirstAttempt=median(winners),
            medianSecondsToBest=round(median(r['secondsToBest'] for r in selected), 3),
            certified=categories['certified'], categories=dict(categories),
            finishReasons=dict(Counter(a['finishReason'] for a in rows if a['finishReason'])),
            details={category: dict(Counter(a['detail'] for a in rows if a['category'] == category))
                     for category in categories if category != 'certified'},
            medianBestByAttempt={str(i): median(a['best'] for a in rows if a['attempt'] == i)
                                 for i in (1, 2, 3, 5, 10, 20, 30, 50)},
            count30ByAttempt={str(i): sum(a['best'] <= 30 for a in rows if a['attempt'] == i)
                              for i in (1, 2, 3, 5, 10, 20, 30, 50)},
            wallSeconds=round(sum(a['wallSeconds'] for a in rows), 3),
            apiSeconds=round(sum(a['apiSeconds'] for a in rows), 3),
            promptTokens=sum(a['promptTokens'] or 0 for a in rows),
            outputTokens=sum(a['outputTokens'] or 0 for a in rows),
            reasoningTokens=sum(a['reasoningTokens'] or 0 for a in rows),
            medianApiSeconds=round(median(a['apiSeconds'] for a in rows), 3),
            costEstimateCount=sum(a['estimatedCostUSD'] is not None for a in rows),
            costEstimateSumUSD=round(sum(a['estimatedCostUSD'] or 0 for a in rows), 6)
                if any(a['estimatedCostUSD'] is not None for a in rows) else None,
            maxPromptBytes=max(a['promptBytes'] for a in rows),
            historyTruncatedAttempts=sum(a['historyRows'] < a['attempt'] - 1 for a in rows),
            uniqueGeneratorSources=len(codes), uniqueCertifiedCandidates=len(candidates),
            repeatCertifiedCandidates=categories['certified']-len(candidates),
            attemptsAfterEventualBest=sum(50-i for i in winners))
    historical = read(REPO / 'docs/results/section9-v1/summary.json')
    reference = next(i for i in historical['instances'] if i['task'] == 'polynomial'
                     and i['objective'] == 'latency-v1' and i['pinnedConfiguration'] == [8, 8])
    metrics = dict(version='five-model-preliminary-analysis-v1',
        source=dict(archive=archive.name, revision=manifest['revision'],
            manifestSha256=sha(archive / 'manifest.json'), inventorySha256=sha(archive / 'inventory.json'),
            inventoryFiles=len(inventory), inventoryBytes=sum(i['bytes'] for i in inventory),
            fullInventoryVerified=True, certificateBindingsVerified=sum(a['accepted'] for a in attempts)),
        configuration=manifest['config'],
        startedUTC=datetime.fromtimestamp(background['started'], timezone.utc).isoformat(),
        endedUTC=datetime.fromtimestamp(background['ended'], timezone.utc).isoformat(),
        elapsedSeconds=round(background['ended']-background['started'], 3),
        attempts=len(attempts), runs=len(runs), categories=dict(Counter(a['category'] for a in attempts)),
        rawFilteredStopReasons=dict(raw_refusals),
        attemptsAfterEventualBest=sum(50-r['bestFirstAttempt'] for r in runs),
        runsBestBy10=sum(r['bestFirstAttempt'] <= 10 for r in runs),
        reference=reference, models=models)
    return metrics, runs, curves


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, default=REPO / 'runs/nightly-five-models-20261123')
    parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parent)
    args = parser.parse_args()
    archive = args.archive.resolve()
    args.output = args.output.resolve()
    if args.output == archive or archive in args.output.parents:
        parser.error('Output must be outside the input archive.')
    metrics, runs, curves = analyze(archive)
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / 'metrics.json').write_text(json.dumps(metrics, indent=2, ensure_ascii=False) + '\n')
    write_csv(args.output / 'runs.csv', runs)
    write_csv(args.output / 'convergence.csv', curves)
    print(f"Verified {metrics['source']['inventoryFiles']:,} files and {metrics['attempts']:,} attempts; wrote metrics.json, runs.csv, convergence.csv")


if __name__ == '__main__':
    main()
