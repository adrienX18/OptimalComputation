#!/usr/bin/env python3
"""Section 9 proposal generation and measurement on the unchanged Lean machine.

No Python simulator or certifier: all runs and accepted scores come from the
public Lean CLI. Schedulers consume instructions and static dependencies only.
"""
from __future__ import annotations

import argparse
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from dataclasses import dataclass
from fractions import Fraction
import hashlib
import gzip
import tempfile
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BINARY = ROOT / '.lake/build/bin/optimal_computation'
PINNED = ((8, 8), (8, 1), (2, 8))
CONFIGS = tuple((l, b) for l in (1, 2, 4, 8) for b in (1, 2, 4, 8))
TASKS = {
    'matmul': ('matmul-16x16-signed16-v1', 'matmul-naive-v2', 512, 256),
    'polynomial': ('polynomial-degree7-points16-v1', 'polynomial-naive-v1', 24, 16),
    'gram': ('gram-16x16-signed16-v1', 'gram-naive-v1', 256, 256),
    'two-stage': ('two-stage-linear-16-signed16-v1', 'two-stage-naive-v1', 528, 16),
}


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'))


def digest(value):
    return hashlib.sha256(canonical(value).encode()).hexdigest()


def cli(*args):
    result = subprocess.run([str(BINARY), *map(str, args), '--json'], cwd=ROOT,
                            text=True, capture_output=True, timeout=180)
    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError(f'CLI did not return JSON: {result.stderr}') from error
    if result.returncode not in (0, 1, 2, 3):
        raise RuntimeError(f'CLI exited {result.returncode}: {result.stderr}')
    return result.returncode, data


def instruction(kind, **operands):
    return dict(kind=kind, **operands)


def load(d, a):
    return instruction('load', destination=d, address=a)


def store(s, a):
    return instruction('store', source=s, address=a)


def reset(d):
    return instruction('add', destination=d, left=0, right=0)


def mac(d, a, b, c):
    return instruction('multiplyAdd', destination=d, left=a, right=b, accumulator=c)


def mul(d, a, b):
    return instruction('multiply', destination=d, left=a, right=b)


def reads(i):
    return [i[k] for k in ('source', 'left', 'right', 'accumulator') if k in i]


def latency(i):
    return 1 if i['kind'] in ('load', 'store') else 3


@dataclass
class LaneState:
    ready: list
    writes: set
    pending: list
    cursor: int = 0


def schedule_streams(streams, banks, start=0):
    """Earliest legal in-order issue for fixed, hand-constructed lane streams.

    Reservations cover RAW/WAW, writeback, pending slots, bank ports, address
    conflicts, and one issue per lane. The Lean machine independently checks it.
    Cross-lane memory dependencies must be separated by a phase barrier.
    """
    states = [LaneState([start] * 16, set(), []) for _ in streams]
    result = []
    t = start
    while any(s.cursor < len(stream) for s, stream in zip(states, streams)):
        bank_use = Counter()
        accesses = {}
        for lane, (s, stream) in enumerate(zip(states, streams)):
            s.pending = [due for due in s.pending if due > t]
            if s.cursor == len(stream):
                continue
            i = stream[s.cursor]
            d = i.get('destination')
            due = t + latency(i)
            if len(s.pending) >= 3 or any(s.ready[r] > t for r in reads(i)):
                continue
            if d is not None and (s.ready[d] > t or due in s.writes):
                continue
            a = i.get('address')
            if a is not None:
                bank = a % banks
                if bank_use[bank] == 2:
                    continue
                if a in accesses and (i['kind'] == 'store' or accesses[a] == 'store'):
                    continue
                accesses[a] = i['kind']
                bank_use[bank] += 1
            result.append(dict(cycle=t, lane=lane, instruction=i))
            s.pending.append(due)
            if d is not None:
                s.ready[d] = due
                s.writes.add(due)
            s.cursor += 1
        t += 1
    finish = max((e['cycle'] + latency(e['instruction']) for e in result), default=start)
    return result, finish


def blocks(raw):
    """Naive generators initialize their local registers in every store-ended job."""
    result, block = [], []
    for e in sorted(raw['schedule'], key=lambda e: (e['cycle'], e['lane'])):
        block.append(e['instruction'])
        if e['instruction']['kind'] == 'store':
            result.append(block)
            block = []
    if block:
        raise ValueError('A baseline job must end in a store')
    for job in result:
        initialized = {0}
        for i in job:
            if not set(reads(i)) <= initialized:
                raise ValueError('Jobs must initialize their own local registers')
            if 'destination' in i:
                initialized.add(i['destination'])
    return result


def greedy(raw, config):
    """Deterministic ready-list scheduling of baseline jobs, serial within a job.

    The dependency graph preserves memory RAW/WAR/WAW. Ready jobs are selected
    in original order; the first idle lane wins. No arithmetic or input values
    are inspected, and no instruction is added or removed.
    """
    jobs = blocks(raw)
    deps = [set() for _ in jobs]
    last_write, readers = {}, {}
    for j, job in enumerate(jobs):
        for i in job:
            if i['kind'] not in ('load', 'store'):
                continue
            a = i['address']
            if a in last_write:
                deps[j].add(last_write[a])
            if i['kind'] == 'store':
                deps[j].update(readers.get(a, set()))
                readers[a] = set()
                last_write[a] = j
            else:
                readers.setdefault(a, set()).add(j)
        deps[j].discard(j)
    lanes, banks = config
    active = [None] * lanes
    ready_at = [0] * lanes
    todo = set(range(len(jobs)))
    done = set()
    completing = []
    result = []
    t = 0
    while todo or any(a is not None for a in active) or completing:
        done.update(j for due, j in completing if due <= t)
        completing = [(due, j) for due, j in completing if due > t]
        bank_use, accesses = Counter(), {}
        for lane in range(lanes):
            if ready_at[lane] > t:
                continue
            if active[lane] is None:
                available = next((j for j in sorted(todo) if deps[j] <= done), None)
                if available is None:
                    continue
                todo.remove(available)
                active[lane] = (available, 0)
            j, cursor = active[lane]
            i = jobs[j][cursor]
            a = i.get('address')
            if a is not None:
                if bank_use[a % banks] == 2:
                    continue
                if a in accesses and (i['kind'] == 'store' or accesses[a] == 'store'):
                    continue
                bank_use[a % banks] += 1
                accesses[a] = i['kind']
            result.append(dict(cycle=t, lane=lane, instruction=i))
            ready_at[lane] = t + latency(i)
            if cursor + 1 == len(jobs[j]):
                completing.append((ready_at[lane], j))
                active[lane] = None
            else:
                active[lane] = (j, cursor + 1)
        if todo and not any(a is not None for a in active) and not completing:
            raise ValueError('Cyclic job dependencies')
        t += 1
    candidate = deepcopy(raw)
    candidate['identifier'] = f"{raw['identifier']}-greedy-l{lanes}-b{banks}-v1"
    candidate['configuration'] = dict(lanes=lanes, banks=banks)
    candidate['schedule'] = result
    return candidate


def dot_stream(pairs, destinations):
    """Four independent accumulators; operands are explicit memory loads."""
    result = [reset(3 + j) for j in range(len(pairs))]
    for k in range(16):
        for j, (a, b) in enumerate(pairs):
            result += [load(1, a[k]), load(2, b[k]), mac(3+j, 1, 2, 3+j)]
    for j, outputs in enumerate(destinations):
        result += [store(3+j, a) for a in outputs]
    return result


def distribute_dots(jobs, lanes):
    streams = [[] for _ in range(lanes)]
    for group in range(0, len(jobs), 4):
        chunk = jobs[group:group+4]
        streams[(group // 4) % lanes] += dot_stream([j[0] for j in chunk], [j[1] for j in chunk])
    return streams


def hand_reference(task, config):
    lanes, banks = config
    workload, _, inputs, outputs = TASKS[task]
    streams = [[] for _ in range(lanes)]
    scratch = []
    if task == 'matmul':
        # Four output columns share each left operand; 4 accumulators + 2 loads.
        for i in range(16):
            for col in range(0, 16, 4):
                stream = streams[(i * 4 + col // 4) % lanes]
                stream += [reset(3+j) for j in range(4)]
                for k in range(16):
                    stream += [load(1, i*16+k)]
                    for j in range(4):
                        stream += [load(2, 256+k*16+col+j), mac(3+j, 1, 2, 3+j)]
                stream += [store(3+j, 512+i*16+col+j) for j in range(4)]
    elif task == 'polynomial':
        for p in range(16):
            stream = streams[p % lanes]
            stream += [load(1, 8+p), mul(2, 1, 1), mul(3, 2, 2)]
            for pair in range(4):
                stream += [load(8, 2*pair), load(9, 2*pair+1), mac(4+pair, 9, 1, 8)]
            stream += [mac(4, 5, 2, 4), mac(6, 7, 2, 6), mac(4, 6, 3, 4), store(4, 24+p)]
    elif task == 'gram':
        jobs = []
        for i in range(16):
            for j in range(i, 16):
                dest = [256+16*i+j] + ([256+16*j+i] if i != j else [])
                jobs.append((([16*i+k for k in range(16)], [16*j+k for k in range(16)]), dest))
        streams = distribute_dots(jobs, lanes)
    else:
        scratch = list(range(544, 560))
        jobs = [(([16*i+k for k in range(16)], list(range(256, 272))), [544+i]) for i in range(16)]
        first, boundary = schedule_streams(distribute_dots(jobs, lanes), banks)
        jobs = [(([272+16*i+k for k in range(16)], scratch), [528+i]) for i in range(16)]
        second, _ = schedule_streams(distribute_dots(jobs, lanes), banks, boundary)
        schedule = first + second
    if task != 'two-stage':
        schedule, _ = schedule_streams(streams, banks)
    return dict(identifier=f'{task}-hand-reference-l{lanes}-b{banks}-v1', workloadIdentifier=workload,
                modelVersion='arty-model-v1', formatVersion='candidate-v1',
                configuration=dict(lanes=lanes, banks=banks),
                layout=dict(inputs=list(range(inputs)), outputs=list(range(inputs, inputs+outputs)), scratch=scratch),
                schedule=schedule)


def horner(config):
    lanes, banks = config
    streams = [[] for _ in range(lanes)]
    for p in range(16):
        stream = streams[p % lanes]
        stream += [load(1, 8+p), load(3, 7)]
        for k in reversed(range(7)):
            stream += [load(2, k), mac(3, 3, 1, 2)]
        stream += [store(3, 24+p)]
    schedule, _ = schedule_streams(streams, banks)
    result = hand_reference('polynomial', config)
    result.update(identifier=f'polynomial-horner-l{lanes}-b{banks}-v1', schedule=schedule)
    return result


def ceildiv(a, b):
    return (a + b - 1) // b


def counting_bound(task, config):
    """Unconditional compulsory-I/O floor, valid even for algebraic rewrites.

    Every input affects some output over the allowed domain. A fixed, universally
    correct schedule must load each input and store each distinct output slot.
    At most L instructions and 2B memory accesses issue per cycle. The final
    memory operation completes one cycle after issue. We make no unsupported
    claim that the classical number of multiplications is an algebraic minimum.
    """
    _, _, inputs, outputs = TASKS[task]
    lanes, banks = config
    accesses = inputs + outputs
    # Candidates may choose another layout, so do not use row-major imbalance.
    floor = max(ceildiv(accesses, lanes), ceildiv(accesses, 2*banks))
    return dict(kind='unconditional-compulsory-io-v1', cycles=floor,
                compulsoryLoads=inputs, compulsoryStores=outputs,
                issueBound=ceildiv(accesses, lanes), portBound=ceildiv(accesses, 2*banks),
                scope='All candidates, including changed layouts and algebraic algorithms; deliberately conservative.')


def energy_bound(task):
    _, _, n, m = TASKS[task]
    choices = []
    for l, b in CONFIGS:
        bram = b * 2 * ceildiv(4096 // b, 1024)
        cycles = counting_bound(task, (l, b))['cycles']
        # Every compulsory load writes a register; every store reads one.
        choices.append((cycles * (1+l+bram) + 5*(n+m), l, b))
    value, l, b = min(choices)
    return dict(kind='unconditional-compulsory-io-energy-v1', units=value,
                minimizingRelaxedConfiguration=dict(lanes=l, banks=b), configurationsConsidered=16)


def gap(naive, floor, actual):
    if actual is None or naive <= floor:
        return None
    f = Fraction(naive - actual, naive - floor)
    return dict(numerator=f.numerator, denominator=f.denominator, fraction=float(f))


def fixtures(task):
    if task == 'matmul':
        return ['zeros', 'left-identity', 'right-identity', 'mixed-signs',
                'negative-endpoints', 'positive-endpoints', 'opposite-endpoints', 'generated-23']
    if task == 'gram':
        return ['zeros', 'identity', 'mixed-signs', 'negative-endpoints', 'positive-endpoints', 'generated-23']
    return ['zeros', 'mixed-signs', 'negative-endpoints', 'positive-endpoints', 'generated-23']


def check_instance(raw, task, config, objective):
    if raw['workloadIdentifier'] != TASKS[task][0]:
        return 'workload-mismatch'
    if objective == 'latency-v1' and raw['configuration'] != dict(lanes=config[0], banks=config[1]):
        return 'configuration-mismatch'
    return None


class Runner:
    def __init__(self, directory):
        self.directory = Path(directory)
        self.directory.mkdir(parents=True, exist_ok=True)
        self.log = self.directory / 'proposals.jsonl'
        if self.log.exists():
            raise ValueError('A proposal log already exists. Use a new output directory to preserve history.')
        (self.directory / 'candidates').mkdir(exist_ok=True)
        self.rows = []
        self.simulations = {}
        self.runtime = tempfile.TemporaryDirectory(prefix="section9-candidates-")
        self.pool = ThreadPoolExecutor(max_workers=4)

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()

    def close(self):
        self.pool.shutdown(wait=True)
        self.runtime.cleanup()

    def append(self, row):
        with self.log.open('a') as output:
            output.write(canonical(row) + '\n')
            output.flush()

    def proposal(self, raw, task, role, config, objective, heldout=None):
        sha = digest(raw)
        path = Path(self.runtime.name) / f'{sha}.json'
        payload = (canonical(raw) + '\n').encode()
        path.write_bytes(payload)
        archive = self.directory / 'candidates' / f'{sha}.json.gz'
        archive.write_bytes(gzip.compress(payload, mtime=0))
        row = dict(recordVersion='experiment-proposal-v1', proposal=len(self.rows)+1,
                   task=task, role=role, objective=objective, pinnedConfiguration=(list(config) if objective == 'latency-v1' else None),
                   candidateIdentifier=raw['identifier'], candidateSha256=sha,
                   artifact=str(archive.relative_to(self.directory)))
        self.append(dict(row, status='submitted'))
        mismatch = check_instance(raw, task, config, objective)
        if mismatch:
            row.update(status='rejected-instance', reason=mismatch, structurallyValid=None,
                       fixturesPass=False, certification='not-attempted', acceptedScore=None, observedCycles=None)
        else:
            checks = []
            execution = None
            missing = [f for f in fixtures(task) if (sha, f) not in self.simulations]
            observed = self.pool.map(lambda f: cli('simulate', path, '--fixture', f), missing)
            for fixture, result in zip(missing, observed):
                self.simulations[(sha, fixture)] = result
            for fixture in fixtures(task):
                code, report = self.simulations[(sha, fixture)]
                checks.append(dict(fixture=fixture, passed=code == 0, exitCode=code,
                                   failure=report if code else None))
                if code == 0:
                    if execution is not None and report['execution']['cycles'] != execution['cycles']:
                        raise AssertionError('A fixed schedule changed duration between fixtures')
                    execution = report['execution']
            passed = all(c['passed'] for c in checks)
            structural_errors = {'inadmissible-configuration', 'malformed-layout', 'malformed-candidate',
                                 'structural-binding-mismatch', 'malformed-instruction', 'invalid-candidate-file'}
            structural = not any(c['failure'] and c['failure'].get('category') in structural_errors for c in checks)
            certification = 'deferred'  # Unknown is not a failed proof.
            accepted = None
            # Exact artifact equality, not its identifier, permits catalog evaluation.
            cfg = f"{raw['configuration']['lanes']},{raw['configuration']['banks']}"
            code, exported = cli('export-candidate', raw['identifier'], '--configuration', cfg)
            if code == 0 and exported == raw:
                code, accepted = cli('evaluate', raw['identifier'], '--configuration', cfg, '--fixture', 'generated-23', '--objective', objective)
                if code:
                    raise AssertionError(accepted)
                certification = 'certified'
            held = None
            if heldout is not None:
                input_path = self.directory / 'held-out-polynomial.json'
                input_path.write_text(canonical(heldout) + '\n')
                code, report = cli('simulate', path, '--input', input_path)
                held = dict(passed=code == 0, failure=report if code else None)
                if code == 1 and report.get('category') in ('arithmetic-failure', 'output-mismatch', 'illegal-schedule', 'incomplete-output'):
                    certification = 'refuted-by-counterexample'
            refutable = {'arithmetic-failure', 'output-mismatch', 'illegal-schedule', 'incomplete-output'}
            if not structural:
                certification = 'invalid-structure'
            elif any(c['failure'] and c['failure'].get('category') in refutable for c in checks):
                certification = 'refuted-by-counterexample'
            elif any(c['exitCode'] == 3 for c in checks):
                certification = 'inconclusive-resource-exhausted'
            elif not passed:
                raise RuntimeError(f'Fixture setup failed: {checks}')
            if accepted is not None and certification != 'certified':
                raise AssertionError('A certified artifact failed an allowed fixture')
            row.update(status='completed', structurallyValid=structural, fixtures=checks, fixturesPass=passed,
                       heldOut=held, certification=certification, acceptedScore=accepted,
                       observedCycles=execution['cycles'] if execution else None,
                       execution=execution)
        self.rows.append(row)
        self.append(row)
        return row


def energy_projection(execution):
    """Diagnostic projection of recorded counters; conveys no acceptance."""
    c, r = execution['counters'], execution['resources']
    return (execution['cycles'] * (1 + r['dspSlices'] + r['bram36Blocks'])
            + 4*c['loads'] + 4*c['stores'] + c['additions']
            + 8*c['multiplications'] + 9*c['multiplyAdds']
            + c['registerReads'] + c['registerWrites'])


def finalize(summary):
    for instance in summary['instances']:
        rows = [summary['proposals'][i-1] for i in instance['proposals']]
        for row in rows:
            valid_observation = row['fixturesPass'] and row['certification'] not in (
                'refuted-by-counterexample', 'invalid-structure', 'inconclusive-resource-exhausted')
            if not valid_observation:
                row['observedGapClosed'] = None
            if instance['objective'] == 'energy-proxy-v1':
                projection = energy_projection(row['execution']) if valid_observation else None
                row['energyProjection'] = None if projection is None else dict(
                    value=projection, unit='abstract energy units', profile='energy-coefficients-v1',
                    status='certified' if row['acceptedScore'] else 'unverified-counter-projection')
                row['observedGapClosed'] = gap(instance['naiveEnergy'], instance['lowerBound']['units'], projection)
                if row['acceptedScore']:
                    assert projection == row['acceptedScore']['objective']['score']
        if instance['objective'] == 'energy-proxy-v1':
            references = [r for r in rows if r['role'] == 'hand-reference' and r['energyProjection']]
            best = min(references, key=lambda r: r['energyProjection']['value'])
            instance['handReferenceEnergyProjection'] = best['energyProjection']
            instance['handReferenceProposal'] = best['proposal']
            instance['smokeTest'] = best['energyProjection']['value'] == instance['lowerBound']['units']
    return summary


def run_experiments(directory, tasks):
    with Runner(directory) as runner:
        return measure_instances(runner, tasks)


def measure_instances(runner, tasks):
    instances = []
    heldout = [7, -8, 7, -8, 7, -8, 7, -8] + [-4]*16
    for task in tasks:
        code, base = cli('export-candidate', TASKS[task][1])
        if code:
            raise AssertionError(base)
        for config in PINNED:
            print(f'{task}: latency {config}', flush=True)
            naive = deepcopy(base)
            naive['configuration'] = dict(lanes=config[0], banks=config[1])
            floor = counting_bound(task, config)
            proposals = [runner.proposal(naive, task, 'naive', config, 'latency-v1'),
                         runner.proposal(greedy(naive, config), task, 'greedy', config, 'latency-v1'),
                         runner.proposal(hand_reference(task, config), task, 'hand-reference', config, 'latency-v1',
                                         heldout if task == 'polynomial' else None)]
            if task == 'polynomial':
                proposals.append(runner.proposal(horner(config), task, 'horner-negative-control', config,
                                                 'latency-v1', heldout))
            if task == 'gram' and config == (8, 8):
                _, symmetric = cli('export-candidate', 'gram-symmetric-v1')
                proposals.append(runner.proposal(symmetric, task, 'certified-symmetry', config, 'latency-v1'))
            baseline = proposals[0]['observedCycles']
            for p in proposals:
                # Gaps on unverified schedules are observations, never accepted optimization scores.
                p['observedGapClosed'] = gap(baseline, floor['cycles'], p['observedCycles']) if p['fixturesPass'] and p['certification'] != 'refuted-by-counterexample' else None
                p['acceptedGapClosed'] = p['observedGapClosed'] if p['certification'] == 'certified' else None
            reference = proposals[2]['observedCycles']
            instances.append(dict(task=task, objective='latency-v1', pinnedConfiguration=list(config),
                                  lowerBound=floor, naiveCycles=baseline, handReferenceCycles=reference,
                                  smokeTest=reference == floor['cycles'],
                                  proposals=[p['proposal'] for p in proposals]))
        # Energy provisioning is free: every member of the family is eligible.
        print(f'{task}: energy, all 16 configurations', flush=True)
        energy_rows = []
        for config in CONFIGS:
            raw = deepcopy(base)
            raw['configuration'] = dict(lanes=config[0], banks=config[1])
            energy_rows.append(runner.proposal(raw, task, 'naive-configuration', config, 'energy-proxy-v1'))
            energy_rows.append(runner.proposal(greedy(raw, config), task, 'greedy', config, 'energy-proxy-v1'))
            energy_rows.append(runner.proposal(hand_reference(task, config), task, 'hand-reference', config, 'energy-proxy-v1'))
        floor = energy_bound(task)
        default = next(p for p in energy_rows if p['acceptedScore'] and p['acceptedScore']['configuration'] == dict(lanes=8, banks=8))
        naive_energy = default['acceptedScore']['objective']['score']
        for p in energy_rows:
            score = p['acceptedScore']['objective']['score'] if p['acceptedScore'] else None
            p['acceptedGapClosed'] = gap(naive_energy, floor['units'], score)
            p['observedGapClosed'] = None  # Unverified energy scores remain unavailable.
        instances.append(dict(task=task, objective='energy-proxy-v1', pinnedConfiguration=None,
                              lowerBound=floor, naiveEnergy=naive_energy, smokeTest=False,
                              proposals=[p['proposal'] for p in energy_rows]))
    for instance in instances:
        rows = [runner.rows[i-1] for i in instance['proposals']]
        instance['counts'] = dict(proposals=len(rows),
            certified=sum(p['certification'] == 'certified' for p in rows),
            passedFixturesFailedCertification=sum(p['fixturesPass'] and p['certification'] == 'refuted-by-counterexample' for p in rows),
            certificationDeferred=sum(p['certification'] == 'deferred' for p in rows))
        if not all(p['fixturesPass'] for p in rows if p['role'] != 'horner-negative-control'):
            raise AssertionError(f'Reference or baseline failed: {instance}')
    # Include the scope and status of the intentionally deferred prerequisite.
    summary = dict(recordVersion='section9-experiments-v1', modelVersion='arty-model-v1',
                   certificationPath='Existing serial proofs; arbitrary parallel certification deferred to questions.md',
                   instances=instances, proposals=runner.rows,
                   counts=dict(proposals=len(runner.rows),
                               certified=sum(p['certification'] == 'certified' for p in runner.rows),
                               passedFixturesFailedCertification=sum(p['fixturesPass'] and p['certification'] == 'refuted-by-counterexample' for p in runner.rows),
                               certificationDeferred=sum(p['certification'] == 'deferred' for p in runner.rows)))
    finalize(summary)
    for row in runner.rows:
        runner.append(dict(row, status='measured'))
    write_reports(runner.directory, summary)
    return summary


def write_reports(directory, summary):
    directory = Path(directory)
    (directory / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    counts = summary['counts']
    lines = ['# Section 9 results', '',
        f"{counts['proposals']} proposals; {counts['certified']} certified; "
        f"{counts['passedFixturesFailedCertification']} passed public fixtures but were refuted on held-out inputs.", '',
        'General parallel certification remains deferred. All naive baselines below are certified.', '',
        '## Latency', '',
        'Greedy and hand-reference timings are unverified observations. The floor counts compulsory I/O.', '',
        '| Task | Lanes, banks | Naive | Greedy | Hand reference | Floor | Hand gap closed |',
        '| --- | --- | ---: | ---: | ---: | ---: | ---: |']
    for instance in summary['instances']:
        if instance['objective'] != 'latency-v1':
            continue
        rows = [summary['proposals'][i-1] for i in instance['proposals']]
        greedy = next(r for r in rows if r['role'] == 'greedy')
        hand = next(r for r in rows if r['role'] == 'hand-reference')
        closed = hand['observedGapClosed']['fraction'] * 100
        l, b = instance['pinnedConfiguration']
        lines.append(f"| {instance['task']} | {l}, {b} | {instance['naiveCycles']:,} | "
                     f"{greedy['observedCycles']:,} | {hand['observedCycles']:,} | "
                     f"{instance['lowerBound']['cycles']:,} | {closed:.1f}% |")
    lines += ['', '## Energy', '',
        'All values use abstract energy-proxy units. The hand reference is the lowest diagnostic projection '
        'among its sixteen configurations; it is not an accepted score.', '',
        '| Task | Certified naive at 8,8 | Best hand projection | Floor |',
        '| --- | ---: | ---: | ---: |']
    for instance in summary['instances']:
        if instance['objective'] == 'energy-proxy-v1':
            lines.append(f"| {instance['task']} | {instance['naiveEnergy']:,} | "
                         f"{instance['handReferenceEnergyProjection']['value']:,} | {instance['lowerBound']['units']:,} |")
    lines += ['', '[Full records](summary.json) · [Proposal ledger](proposals.jsonl) · '
              '[Methods and proof boundary](../../experiments.md)', '']
    (directory / 'summary.md').write_text('\n'.join(lines))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True, help='New directory; existing proposal logs are never overwritten')
    parser.add_argument('--task', action='append', choices=TASKS, help='Default: all four tasks')
    args = parser.parse_args()
    result = run_experiments(args.output, args.task or list(TASKS))
    print(json.dumps(result['counts'], indent=2))


if __name__ == '__main__':
    main()
