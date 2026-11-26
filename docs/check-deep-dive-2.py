#!/usr/bin/env python3
"""Offline checks for the follow-up guide and its exported evidence.

Does not call models, execute generated Python, or claim to recheck Lean proofs.
"""
import hashlib
import json
from pathlib import Path
import re
import runpy
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / 'docs/evidence/deep-dive-2'
GUIDE = ROOT / 'DEEP_DIVE_2.md'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read(path):
    return json.loads(path.read_text())


def sha(data):
    return hashlib.sha256(data).hexdigest()


def anchors(text):
    explicit = set(re.findall(r'<a id="([^"]+)"', text))
    headings = re.findall(r'^#{1,6} (.+)$', text, re.M)
    return explicit | {re.sub(r'[^\w\s-]', '', h.lower()).replace(' ', '-') for h in headings}


def main():
    old = runpy.run_path(str(ROOT / 'docs/check-deep-dive.py'))
    guide = GUIDE.read_text()
    excerpts = old['check_excerpts'](guide)
    pattern = r'<!-- evidence-excerpt (\{[^\n]+\}) -->\n```[^\n]*\n(.*?)\n```'
    evidence_count = 0
    for encoded, actual in re.findall(pattern, guide, re.S):
        meta = json.loads(encoded)
        lines = (ROOT / meta['path']).read_text().splitlines()
        require(1 <= meta['start'] <= meta['end'] <= len(lines), f'Invalid excerpt: {meta}')
        require(actual == '\n'.join(lines[meta['start']-1:meta['end']]), f'Changed excerpt: {meta}')
        evidence_count += 1
    require(evidence_count == guide.count('<!-- evidence-excerpt '), 'Unparsed evidence excerpts')

    prose = re.sub(r'^```[^\n]*\n.*?^```[ \t]*$', '', guide, flags=re.M | re.S)
    links = re.findall(r'!?\[[^\]\n]*\]\(([^)\n]+)\)', prose)
    for target in links:
        url = urlsplit(target)
        if url.scheme:
            require(url.scheme == 'https', f'Unexpected scheme: {target}')
            if url.netloc == 'github.com' and url.path.startswith('/adrienX18/OptimalComputation/blob/'):
                revision, path = url.path.split('/blob/', 1)[1].split('/', 1)
                blob = old['blob'](revision, path)
                if url.fragment:
                    match = re.fullmatch(r'L(\d+)(?:-L(\d+))?', url.fragment)
                    require(match and 1 <= int(match[1]) <= int(match[2] or match[1]) <= len(blob.splitlines()),
                            f'Invalid source lines: {target}')
            else:
                require(url.netloc in ('github.com', 'lean-lang.org'), f'Unexpected external reference: {target}')
        else:
            path = ROOT / unquote(url.path) if url.path else GUIDE
            require(path.is_file(), f'Missing local file: {target}')
            if url.fragment:
                require(url.fragment in anchors(path.read_text()), f'Missing anchor: {target}')
    for i, code in enumerate(re.findall(r"<<'PYCODE'\n(.*?)^PYCODE$", guide, re.M | re.S)):
        compile(code, f'guide recipe {i}', 'exec')

    provenance = read(EVIDENCE / 'provenance.json')
    for row in provenance['files']:
        data = (EVIDENCE / row['file']).read_bytes()
        require(len(data) == row['bytes'] and sha(data) == row['sha256'], f'Export changed: {row["file"]}')
        original = ROOT / row['source']
        if original.exists():
            require(data == original.read_bytes(), f'Export differs from original: {row["file"]}')

    # Use the real driver rule to audit saved dependency reports, without running
    # the driver or treating its recorded exit status as a new proof.
    driver = runpy.run_path(str(ROOT / 'scripts/certify.py'))
    for row in read(EVIDENCE / 'measurements.json'):
        task = row['task']
        cert = EVIDENCE / task / 'certification'
        result = read(cert / 'result.json')
        source = (cert / 'Certificate.lean').read_bytes()
        walk = ROOT / row['walkthrough']
        require(result == read(walk / 'winner/certification/result.json'), f'Certificate result changed: {task}')
        require(result['accepted'] and sha(source) == result['certificateSha256'], f'Proof hash: {task}')
        require(sha((walk / 'winner/candidate.json').read_bytes()) == result['candidateSha256'], f'Candidate hash: {task}')
        require(result['score'] == read(walk / 'winner/score.json'), f'Score binding: {task}')
        require(driver['audit_kernel_output']((cert / 'kernel/stdout.txt').read_text(),
                result['certificateDeclaration'].removesuffix('.artifact')), f'Axiom report: {task}')
        require(read(cert / 'kernel/result.json')['exitCode'] == 0, f'Kernel exit: {task}')
        values = dict(certificateBytes=len(source), certificateLines=len(source.splitlines()),
                      modeledCycles=result['cycles'], kernelSeconds=result['kernelSeconds'],
                      certificationSeconds=result['totalSeconds'],
                      apiSeconds=read(walk / 'winner/response.json')['seconds'],
                      attemptSeconds=read(walk / 'winner/feedback.json')['seconds'],
                      precheckSeconds=read(cert / 'precheck/result.json')['seconds'],
                      kernelProcessSeconds=read(cert / 'kernel/result.json')['seconds'],
                      generationSeconds=read(EVIDENCE / task / 'generation/process/result.json')['seconds'])
        queue = cert / 'kernel-queue.json'
        values['queueSeconds'] = read(queue)['waitSeconds'] if queue.exists() else None
        require(all(row[k] == v for k, v in values.items()), f'Measurements differ: {task}')
        queue_text = f"{row['queueSeconds']:.3f}" if row['queueSeconds'] is not None else 'not recorded'
        cells = [task] + [f"{row[k]:.3f}" for k in ('apiSeconds','generationSeconds','precheckSeconds')]
        cells += [queue_text] + [f"{row[k]:.3f}" for k in ('kernelProcessSeconds','certificationSeconds','attemptSeconds')]
        cells += [f"{row['modeledCycles']:,}"]
        require('| ' + ' | '.join(cells) + ' |' in guide, f'Timing table differs: {task}')
        instructions = result['score']['execution']['scheduleSize']
        require(f"| {len(source):,} | {len(source.splitlines()):,} | {instructions:,} |" in guide,
                f'Size table differs: {task}')

    observations = read(EVIDENCE / 'response-observations.json')
    require(len(observations['observations']) == 1247, 'Response count')
    require(len({r['path'] for r in observations['observations']}) == 1247, 'Duplicate response paths')
    for model, summary in observations['summary'].items():
        rows = [r for r in observations['observations'] if r['model'] == model]
        counts = dict(responses=len(rows), withReasoningText=sum(bool(r['reasoningCharacters']) for r in rows),
                      withThinkingBlocks=sum(bool(r['thinkingBlocks']) for r in rows),
                      withToolCalls=sum(bool(r['toolCalls'] or r['functionCall']) for r in rows))
        require(all(summary[k] == v for k, v in counts.items()), f'Census differs: {model}')
        require(f"| {model.title()} | {counts['responses']} | {counts['withReasoningText']} | "
                f"{counts['withThinkingBlocks']} | {counts['withToolCalls']} |" in guide, f'Census table: {model}')
    for row in observations['observations']:
        source = ROOT / row['path']
        if source.exists():
            data = source.read_bytes()
            require(len(data) == row['bytes'] and sha(data) == row['sha256'], f'Response changed: {source}')

    def stable(value):
        if isinstance(value, dict):
            return {k: stable(v) for k, v in value.items()
                    if k not in ('seconds','kernelSeconds','totalSeconds','started','ended','time')}
        if isinstance(value, list):
            return [stable(v) for v in value]
        return value
    feedback = read(EVIDENCE / 'error/feedback.json')
    request = read(EVIDENCE / 'error/next-request.json')
    context = json.loads(request['messages'][1]['content'])
    require(json.loads(context['latest']['feedback']) == stable(feedback), 'Actual next feedback differs')
    require(len(context['latest']['feedback'].encode()) <= 3000, 'Feedback was clipped')
    require(context['latest']['code'] == (EVIDENCE / 'error/generator.py').read_text(), 'Latest code differs')
    violation = feedback['failure']['report']['details']['violation']
    require(not feedback['accepted'] and violation['value'] == -34952 and violation['bits'] == 16, 'Error example differs')
    require(feedback['bestScore'] == context['best']['score'] == 1520, 'Error incumbent differs')

    current = read(EVIDENCE / 'current-polynomial/result.json')
    require(current['accepted'] and current['cycles'] == 30 and current['certificateBoundaryBudget'] == 32, 'Current certificate result')
    require(sha((EVIDENCE / 'current-polynomial/Certificate.lean').read_bytes()) == current['certificateSha256'], 'Current proof hash')
    require(current['candidateSha256'] == read(EVIDENCE / 'polynomial/certification/result.json')['candidateSha256'], 'Current candidate differs')
    require(f"{current['totalSeconds']:.3f} seconds" in guide and f"kernelSeconds = {current['kernelSeconds']:.3f}" in guide,
            'Current timing prose differs')
    require(driver['audit_kernel_output']((EVIDENCE / 'current-polynomial/kernel/stdout.txt').read_text(),
            current['certificateDeclaration'].removesuffix('.artifact')), 'Current axiom report')
    require(read(EVIDENCE / 'current-polynomial/kernel/result.json')['exitCode'] == 0, 'Current kernel exit')
    print(f"PASS: {excerpts['source-excerpt']} pinned source excerpts, {evidence_count} evidence excerpts, {len(links)} links")
    print(f"PASS: {len(provenance['files'])} exported files, four certificate/score bindings, all timing and source-size rows")
    print('PASS: 1,247-response census, exact next-prompt error feedback, and separate current-certificate record')
    print('This is an offline evidence check; external documentation URLs were not network-tested.')


if __name__ == '__main__':
    main()
