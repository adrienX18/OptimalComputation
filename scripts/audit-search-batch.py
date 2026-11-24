#!/usr/bin/env python3
"""Verify a completed batch archive and export small readiness/analysis summaries."""
import argparse
from collections import Counter
import hashlib
import gzip
import json
from pathlib import Path

from harness.archive import read_json, write_json


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024*1024), b''):
            h.update(chunk)
    return h.hexdigest()


def audit(root):
    manifest = read_json(root/'manifest.json')
    inventory = read_json(root/'inventory.json')
    listed = {row['path'] for row in inventory}
    assert len(listed) == len(inventory), 'Duplicate inventory entries'
    actual = {str(p.relative_to(root)) for p in root.rglob('*')
              if p.is_file() and p.name not in ('.lock', 'inventory.json')}
    assert listed == actual, 'Inventory coverage differs'
    for row in inventory:
        path = root/row['path']
        assert path.stat().st_size == row['bytes'] and digest(path) == row['sha256'], path
    for metadata in root.rglob('trace.metadata.json'):
        info = read_json(metadata)
        h, size = hashlib.sha256(), 0
        with gzip.open(metadata.parent/info['file'],'rb') as stream:
            for chunk in iter(lambda: stream.read(1024*1024),b''):
                h.update(chunk)
                size += len(chunk)
        assert size == info['originalBytes'] and h.hexdigest() == info['originalSha256'], metadata
    runs, outcomes = [], Counter()
    for job in manifest['jobs']:
        folder = root/job['runPath']
        saved = read_json(folder/'manifest.json')
        assert saved['config'] == job['config'], folder
        assert saved['sourceHashes'] == manifest['sourceHashes'], folder
        summary = read_json(folder/'summary.json')
        assert summary['completed'] == len(summary['attempts']) == job['config']['attempts'], folder
        baseline = read_json(folder/'baseline.json')
        best = baseline['score']
        certified = responses = 0
        categories = Counter()
        max_prompt = 0
        for i, row in enumerate(summary['attempts'], 1):
            attempt = folder/row['directory']
            assert read_json(attempt/'feedback.json') == row and row['attempt'] == i, attempt
            interrupted = row['category'] == 'interrupted'
            response = (attempt/'response.json').exists()
            api_error = (attempt/'api-error.json').exists()
            request_path = attempt/'request.json'
            # Resume preserves a partially written attempt without reissuing its call.
            # Validate every available record; only interrupted slots may lack them.
            partial_request = interrupted and not response and not api_error
            assert request_path.exists() or partial_request, attempt
            if request_path.exists():
                request = read_json(request_path)
                prompt_bytes = len(json.dumps(request['messages'],ensure_ascii=False).encode())
                assert prompt_bytes <= job['config']['prompt_bytes'], attempt
                max_prompt = max(max_prompt,prompt_bytes)
                assert request['model'] == job['model'], attempt
            assert (attempt/'randomness.json').exists() or partial_request, attempt
            assert interrupted or response or api_error, attempt
            if interrupted:
                assert row['accepted'] is False, attempt
            if response:
                assert list(attempt.glob('provider-*-response.json')), attempt
                responses += 1
            if row['accepted']:
                certificate = read_json(attempt/'certification/result.json')
                score = read_json(attempt/'score.json')
                assert certificate['accepted'] and certificate['candidateSha256'] == digest(attempt/'candidate.json'), attempt
                assert certificate['certificateSha256'] == digest(attempt/'certification/Certificate.lean'), attempt
                assert read_json(attempt/'certification/kernel/result.json')['exitCode'] == 0, attempt
                assert score == certificate['score'] and row['score'] == score['objective']['score'], attempt
                assert score['objective']['identifier'] == job['config']['objective'], attempt
                if job['config']['objective'] == 'latency-v1':
                    assert list(score['configuration'][k] for k in ('lanes','banks')) == job['config']['configuration'], attempt
                best = min(best,row['score'])
                certified += 1
            assert interrupted or 'bestScore' in row, attempt
            if 'bestScore' in row:
                assert row['bestScore'] == best, attempt
            categories[row['category']] += 1
            outcomes[row['category']] += 1
        assert summary['best']['score'] == best, folder
        runs.append(dict(instance=job.get('instance','default'), model=job['name'], seed=job['seed'],
                         attempts=summary['completed'], responses=responses, certified=certified,
                         categories=dict(categories), baseline=baseline['score'], best=best,
                         unit=baseline['unit'], maxPromptBytes=max_prompt))
    return dict(version='search-batch-audit-v1', archive=root.name,
                manifestSha256=digest(root/'manifest.json'), inventorySha256=digest(root/'inventory.json'),
                inventoryFiles=len(inventory), inventoryBytes=sum(r['bytes'] for r in inventory),
                completedRuns=len(runs), completedAttempts=sum(r['attempts'] for r in runs),
                categories=dict(outcomes), runs=runs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive',type=Path)
    parser.add_argument('--output',required=True,type=Path)
    args = parser.parse_args()
    if not __debug__:
        parser.error('Assertions must be enabled.')
    root, destination = args.archive.resolve(), args.output.resolve()
    if destination == root or root in destination.parents:
        parser.error('Save the audit outside the immutable archive.')
    result = audit(root)
    write_json(destination,result)
    print(f"Verified {result['inventoryFiles']:,} files, {result['completedRuns']} runs, {result['completedAttempts']} attempts")
    print(result['categories'])


if __name__ == '__main__':
    main()
