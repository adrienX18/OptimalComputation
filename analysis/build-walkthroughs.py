#!/usr/bin/env python3
"""Export frozen examples and verify the data behind the report walkthroughs.

Reads archives; never invokes a model, generated Python, Docker or Lean.
Plots can subsequently be regenerated using only the tracked exports.
"""
from collections import Counter
import csv
import hashlib
import heapq
import json
from pathlib import Path
from statistics import median

ROOT = Path(__file__).resolve().parents[1]
ANALYSIS = ROOT / 'analysis'
if not __debug__:
    raise SystemExit('Evidence verification requires assertions; do not use -O or -OO.')


def read(p):
    return json.loads(p.read_text())


def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def write(p, value):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')


def table(p):
    with p.open(newline='') as stream:
        return list(csv.DictReader(stream))


def add(a, b):
    c = Counter(a)
    c.update(b)
    return {k: v for k, v in c.items() if v}


def multiply(a, b):
    c = Counter()
    for x, i in a.items():
        for y, j in b.items():
            c[tuple(sorted(x + y))] += i * j
    return {k: v for k, v in c.items() if v}


def inspect(candidate, score):
    """Derive instruction counts/output ownership; check symbolic output formulas.

An analysis cross-check, not a replacement for archived machine/range proofs.
Registers and stores commit at their instruction's completion boundary.
"""
    schedule = candidate['schedule']
    lanes = candidate['configuration']['lanes']
    memory = {a: {(i,): 1} for i, a in enumerate(candidate['layout']['inputs'])}
    registers = [{0: {}} for _ in range(lanes)]
    pending, owners, events = [], {}, []
    counts = Counter(e['instruction']['kind'] for e in schedule)
    last = 0

    def commit(t):
        while pending and pending[0][0] <= t:
            _, _, lane, destination, expression, store = heapq.heappop(pending)
            if store:
                memory[destination] = expression
                owners[destination] = lane
            else:
                registers[lane][destination] = expression

    for index, e in enumerate(sorted(schedule, key=lambda e: (e['cycle'], e['lane']))):
        cycle, lane, op = e['cycle'], e['lane'], e['instruction']
        commit(cycle)
        kind, regs = op['kind'], registers[lane]
        if kind == 'load':
            expression = memory[op['address']]
        elif kind == 'store':
            expression = regs[op['source']]
        elif kind == 'add':
            expression = add(regs[op['left']], regs[op['right']])
        else:
            expression = multiply(regs[op['left']], regs[op['right']])
            if kind == 'multiplyAdd':
                expression = add(expression, regs[op['accumulator']])
        done = cycle + (1 if kind in ('load', 'store') else 3)
        last = max(last, done)
        destination = op['address'] if kind == 'store' else op['destination']
        heapq.heappush(pending, (done, index, lane, destination, expression, kind == 'store'))
        events.append(dict(cycle=cycle, lane=lane, kind=kind))
    commit(last)
    outputs = [memory[a] for a in candidate['layout']['outputs']]
    task = candidate['workloadIdentifier']
    if task.startswith('polynomial'):
        expected = [{tuple([k] + [8 + p] * k): 1 for k in range(8)} for p in range(16)]
    elif task.startswith('gram'):
        expected = []
        for i in range(16):
            for j in range(16):
                expected.append(dict(Counter(tuple(sorted((16*i+k, 16*j+k))) for k in range(16))))
    elif task.startswith('matmul'):
        expected = [{(16*i+k, 256+16*k+j): 1 for k in range(16)}
                    for i in range(16) for j in range(16)]
    elif task.startswith('two-stage'):
        expected = [{(16*j+k, 256+k, 272+16*i+j): 1
                     for j in range(16) for k in range(16)} for i in range(16)]
    else:
        raise ValueError(task)
    assert outputs == expected, 'Diagram interpretation disagrees with symbolic output'
    counters = score['execution']['counters']
    names = {'load': 'loads', 'store': 'stores', 'add': 'additions',
             'multiply': 'multiplications', 'multiplyAdd': 'multiplyAdds'}
    assert all(counts[k] == counters[v] for k, v in names.items())
    assert last == score['execution']['cycles']
    assert len(schedule) == score['execution']['scheduleSize']
    return dict(cycles=last, instructions=len(schedule), counts=dict(counts),
        lane_issues=[sum(e['lane'] == l for e in schedule) for l in range(lanes)],
        scratch_slots=len(candidate['layout']['scratch']),
        output_lanes=[owners[a] for a in candidate['layout']['outputs']],
        distinct_output_formulas=len({tuple(sorted(o.items())) for o in outputs}),
        symbolic_outputs_checked=True)


def export(study, archive_name, run_path, attempt, selection, output_subdir='walkthrough'):
    folder = ANALYSIS / study
    archive = ROOT / 'runs' / archive_name
    run = archive / run_path
    origin = run / 'attempts' / f'{attempt:04d}'
    out = folder / output_subdir
    sources = []
    inventory = {r['path']: r for r in read(archive / 'inventory.json')}

    def copy(source, relative):
        key = str(source.relative_to(archive))
        data = source.read_bytes()
        assert len(data) == inventory[key]['bytes'] and digest(source) == inventory[key]['sha256'], key
        dest = out / relative
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
        sources.append(dict(file=relative, source=key, bytes=len(data), sha256=digest(dest)))

    files = ['request.json', 'response.json', 'proposal.json', 'generator.py', 'candidate.json',
             'score.json', 'feedback.json', 'randomness.json', 'certification/result.json',
             'certification/kernel/result.json']
    files += [p.name for p in sorted(origin.glob('provider-*.json'))]
    for name in files:
        copy(origin / name, 'winner/' + name)
    baseline = read(run / 'baseline.json')
    for name in ('candidate.json', 'score.json', 'generator.py'):
        copy(run / baseline['directory'] / name, 'baseline/' + name)
    copy(run / 'manifest.json', 'run-manifest.json')
    copy(run / 'summary.json', 'run-summary.json')
    copy(archive / 'source/scripts/harness/prompt.py', 'prompt-at-run.py')
    if attempt > 1:
        copy(run / 'attempts' / f'{attempt-1:04d}' / 'feedback.json', 'previous-feedback.json')
    if (run / 'attempts' / f'{attempt+1:04d}' / 'request.json').exists():
        copy(run / 'attempts' / f'{attempt+1:04d}' / 'request.json', 'next-request.json')
    request, response = read(origin / 'request.json'), read(origin / 'response.json')
    proposal, feedback = read(origin / 'proposal.json'), read(origin / 'feedback.json')
    assert json.loads(response['choices'][0]['message']['content']) == proposal
    assert proposal['code'].rstrip() == (origin / 'generator.py').read_text().rstrip()
    assert feedback['accepted'] and read(origin / 'certification/kernel/result.json')['exitCode'] == 0
    cert = read(origin / 'certification/result.json')
    assert cert['candidateSha256'] == digest(origin / 'candidate.json')
    assert cert['certificateSha256'] == digest(origin / 'certification/Certificate.lean')
    context = json.loads(request['messages'][1]['content'])
    provider = read(next(origin.glob('provider-*-request.json')))
    assert provider['messages'] == request['messages']
    stats = dict(selection=selection, model=request['model'], run=run_path, attempt=attempt,
        prompt_bytes=len(json.dumps(request['messages'], ensure_ascii=False).encode()),
        output_code_bytes=len(proposal['code'].encode()), history=context['history'],
        baseline=inspect(read(out/'baseline/candidate.json'), read(out/'baseline/score.json')),
        winner=inspect(read(origin/'candidate.json'), read(origin/'score.json')),
        certificate_bindings_checked=True)
    if attempt > 1:
        previous = read(out / 'previous-feedback.json')
        seen = json.loads(context['latest']['feedback'])
        assert seen['attempt'] == previous['attempt'] and seen['score'] == previous['score']
    write(out / 'architecture.json', stats)
    write(out / 'provenance.json', dict(archive=archive_name,
        archive_inventory_sha256=digest(archive/'inventory.json'), files=sources))
    (out / 'README.md').write_text('''# Frozen walkthrough evidence

These are byte-for-byte exports of the indicated archived files. `provenance.json`
maps every copy to its source path, byte count and SHA-256, checked against the
original inventory. `architecture.json` derives exact counts, output ownership
and symbolic formula checks from the stored schedules. The analysis checks are
not a new machine/range certificate; the archived certificate bindings and kernel
exit are checked separately. Candidate identifiers may still say “naive”: the
schedule and its hash, not the inherited label, identify the actual design.

`winner/request.json` is the full harness request; the saved `provider-*` files
retain the provider adapter request/response. `response.json` is the normalized
reply; `proposal.json` contains its parsed `idea`, `code`, and `notes` strings.
The generated Python is preserved as data and is not executed by this analysis.
''')
    return out, stats


def main():
    five = '2026-11-23-five-model-search'
    smoke = '2026-11-23-suite-smoke'
    rows = table(ANALYSIS/five/'runs.csv')
    quality = {m: median(int(r['bestCycles']) for r in rows if r['model']==m)
               for m in sorted({r['model'] for r in rows})}
    tied = sorted(m for m in quality if quality[m] == min(quality.values()))
    speed = {m: median(int(r['bestFirstAttempt']) for r in rows if r['model']==m) for m in tied}
    selected = min(tied, key=lambda m: (speed[m], m))
    assert selected == 'sol'
    row = min((r for r in rows if r['model']==selected), key=lambda r: int(r['seed']))
    out, stats = export(five, 'nightly-five-models-20261123', 'runs/sol/seed-11',
        int(row['bestFirstAttempt']), dict(rule='Lowest median final cycles; ties: fewest median attempts to final best, then name. Example: smallest seed.',
            final_medians=quality, quality_ties=tied, median_first_best_attempt=speed))
    rows = table(ANALYSIS/smoke/'runs.csv')
    wins = {m: sum(float(r['best_score']) == min(float(s['best_score']) for s in rows if s['instance']==r['instance'])
                   for r in rows if r['model']==m) for m in sorted({r['model'] for r in rows})}
    selected = min(wins, key=lambda m: (-wins[m], m))
    assert selected == 'astra'
    out, stats = export(smoke, 'suite-smoke-20261123', 'runs/gram-latency-8x8/astra/seed-11', 3,
        dict(rule='Most case-wise lowest final scores (ties count); name breaks a count tie. Gram (8,8) is an illustrative architectural case, not the largest ratio.',
             case_wins_including_ties=wins))
    for task in ('matmul', 'two-stage'):
        selected = min((r for r in rows if r['instance'] == task+'-latency-8x8'),
                       key=lambda r: (int(r['best_score']), r['model']))
        export(smoke, 'suite-smoke-20261123', selected['directory'],
               int(selected['first_final_best']),
               dict(rule='Lowest final certified latency among the five models for this task at 8 lanes / 8 banks; model name breaks ties.',
                    instance=selected['instance'], selected_model=selected['model']),
               output_subdir='architectures/'+task)
    print('Exported and checked four examples: source hashes, certificate bindings, counters and exact symbolic output formulas.')


if __name__ == '__main__':
    main()
