#!/usr/bin/env python3
"""Export selected existing records, never call a model or execute a generator.

Requires the original local archives under runs/. Optionally retain a separately
performed current-source certification with --current-archive PATH.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/evidence/deep-dive-2'
CASES = [
    ('polynomial', 'analysis/2026-11-23-five-model-search/walkthrough', 'nightly-five-models-20261123'),
    ('matmul', 'analysis/2026-11-23-suite-smoke/architectures/matmul', 'suite-smoke-20261123'),
    ('gram', 'analysis/2026-11-23-suite-smoke/walkthrough', 'suite-smoke-20261123'),
    ('two-stage', 'analysis/2026-11-23-suite-smoke/architectures/two-stage', 'suite-smoke-20261123'),
]


def read(path):
    return json.loads(path.read_text())


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--current-archive', type=Path)
    args = parser.parse_args()
    files, measurements, inventories = [], [], {}

    def inventory(archive):
        if archive not in inventories:
            path = ROOT / 'runs' / archive / 'inventory.json'
            value = read(path)
            # Both archives use a top-level list of file records.
            assert isinstance(value, list)
            inventories[archive] = {r['path']: r for r in value}
        return inventories[archive]

    def export(source, destination, archive=None):
        data = source.read_bytes()
        if archive:
            rel = str(source.relative_to(ROOT / 'runs' / archive))
            old = inventory(archive)[rel]
            assert old['sha256'] == sha(data) and old['bytes'] == len(data), source
        target = OUT / destination
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        files.append(dict(file=destination, source=str(source.relative_to(ROOT)) if source.is_relative_to(ROOT) else str(source),
                          bytes=len(data), sha256=sha(data), archive=archive))

    for name, walk, archive in CASES:
        provenance = read(ROOT / walk / 'provenance.json')
        record = next(r for r in provenance['files'] if r['file'] == 'winner/certification/result.json')
        attempt = (ROOT / 'runs' / archive / record['source']).parent.parent
        for rel in ['certification/Certificate.lean', 'certification/result.json',
                    'certification/precheck/result.json', 'certification/kernel/result.json',
                    'certification/kernel/stdout.txt', 'certification/kernel/request.json',
                    'generation/process/result.json', 'certification/kernel-queue.json']:
            source = attempt / rel
            if source.exists():
                export(source, f'{name}/{rel}', archive)
        certificate = read(attempt / 'certification/result.json')
        source = (attempt / 'certification/Certificate.lean').read_bytes()
        assert sha(source) == certificate['certificateSha256']
        assert sha((ROOT / walk / 'winner/candidate.json').read_bytes()) == certificate['candidateSha256']
        response, feedback = read(attempt / 'response.json'), read(attempt / 'feedback.json')
        queue_path = attempt / 'certification/kernel-queue.json'
        measurements.append(dict(task=name, walkthrough=walk, archive=archive,
            attempt=str(attempt.relative_to(ROOT)), sourceRevision=read(ROOT / walk / 'run-manifest.json')['revision'],
            apiSeconds=response['seconds'], generationSeconds=read(attempt / 'generation/process/result.json')['seconds'],
            precheckSeconds=read(attempt / 'certification/precheck/result.json')['seconds'],
            queueSeconds=read(queue_path)['waitSeconds'] if queue_path.exists() else None,
            kernelProcessSeconds=read(attempt / 'certification/kernel/result.json')['seconds'],
            kernelSeconds=certificate['kernelSeconds'], certificationSeconds=certificate['totalSeconds'],
            attemptSeconds=feedback['seconds'], certificateBytes=len(source),
            certificateLines=len(source.splitlines()), modeledCycles=certificate['cycles']))
        if name == 'polynomial':
            export(attempt / 'simulation/generated-23/trace.json', 'polynomial/trace.json', archive)
            export(attempt / 'generation/process/request.json', 'polynomial/generation-request.json', archive)
            export(attempt / 'generation/process/stderr.txt', 'polynomial/generation-stderr.txt', archive)

    archive = 'nightly-five-models-20261123'
    failure = ROOT / 'runs' / archive / 'runs/sonnet/seed-23/attempts/0002'
    for rel in ['feedback.json', 'candidate.json', 'generator.py', 'certification-skipped.json',
                'simulation/negative-endpoints/input.json', 'simulation/negative-endpoints/process/stdout.txt']:
        export(failure / rel, 'error/' + rel, archive)
    export(failure.parent / '0003/request.json', 'error/next-request.json', archive)

    observations, summary = [], {}
    for model in ['fable', 'opus', 'sonnet', 'astra', 'sol']:
        counts = Counter()
        for attempt in sorted((ROOT / 'runs' / archive / 'runs' / model).glob('seed-*/attempts/*')):
            request_path = attempt / 'request.json'
            if not request_path.exists():
                continue
            request = read(request_path)
            assert not request.get('tools') and not request.get('functions'), request_path
            response_path = attempt / 'response.json'
            if not response_path.exists():
                counts['apiErrors'] += 1
                continue
            raw = response_path.read_bytes()
            original = inventory(archive)[str(response_path.relative_to(ROOT / 'runs' / archive))]
            assert sha(raw) == original['sha256'] and len(raw) == original['bytes']
            response = json.loads(raw)
            message = response['choices'][0]['message']
            details = response.get('usage', {}).get('completion_tokens_details') or {}
            observed = dict(model=model, path=str(response_path.relative_to(ROOT)), sha256=sha(raw),
                bytes=len(raw), reasoningCharacters=len(message.get('reasoning_content') or ''),
                thinkingBlocks=len(message.get('thinking_blocks') or []),
                toolCalls=len(message.get('tool_calls') or []),
                functionCall=bool(message.get('function_call')),
                reasoningTokens=details.get('reasoning_tokens'))
            observations.append(observed)
            counts['responses'] += 1
            counts['withReasoningText'] += bool(observed['reasoningCharacters'])
            counts['withThinkingBlocks'] += bool(observed['thinkingBlocks'])
            counts['withToolCalls'] += bool(observed['toolCalls'] or observed['functionCall'])
        summary[model] = dict(counts)
    write(OUT / 'response-observations.json', dict(archive=archive, summary=summary, observations=observations))
    write(OUT / 'measurements.json', measurements)

    if args.current_archive:
        for rel in ['Certificate.lean', 'result.json', 'kernel/stdout.txt', 'kernel/result.json',
                    'precheck/result.json', 'kernel-queue.json']:
            export(args.current_archive.resolve() / rel, 'current-polynomial/' + rel)
    elif (OUT / 'provenance.json').exists():
        # Rebuilding historical exports does not replace an observed new check.
        files += [r for r in read(OUT / 'provenance.json')['files'] if r['archive'] is None]
    write(OUT / 'provenance.json', dict(
        description='Selected historical files copied byte for byte; current-polynomial is a separate 2026-11-25 check.',
        archiveInventories={name:sha((ROOT/'runs'/name/'inventory.json').read_bytes()) for name in inventories},
        files=files))
    print(f'Exported {len(files)} files; summarized {len(observations)} saved responses.')


if __name__ == '__main__':
    main()
