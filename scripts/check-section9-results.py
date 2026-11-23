#!/usr/bin/env python3
"""Check saved proposal bindings, objective arithmetic and per-instance metrics.

Full simulation replay is available through experiment.py into a fresh directory;
check-experiments.py exercises every pinned hand schedule on endpoint inputs.
"""
from collections import defaultdict
import gzip
import json
from pathlib import Path
import experiment as e

if not __debug__:
    raise SystemExit('Assertions must be enabled')

root = e.ROOT / 'docs/results/section9-v1'
summary = json.loads((root / 'summary.json').read_text())
assert summary['recordVersion'] == 'section9-experiments-v1'
assert len(summary['instances']) == 16
assert summary['counts']['proposals'] == len(summary['proposals']) == 232
assert summary['counts']['certified'] == 77
assert summary['counts']['passedFixturesFailedCertification'] == 3
by_id = {r['proposal']: r for r in summary['proposals']}
assert set(by_id) == set(range(1, 233))
ledger = defaultdict(list)
for line in (root / 'proposals.jsonl').read_text().splitlines():
    row = json.loads(line)
    ledger[row['proposal']].append(row)
for ident, row in by_id.items():
    events = ledger[ident]
    assert [r['status'] for r in events] == ['submitted', 'completed', 'measured']
    assert {**events[-1], 'status': 'completed'} == row
    data = gzip.decompress((root / row['artifact']).read_bytes())
    raw = json.loads(data)
    assert e.digest(raw) == row['candidateSha256']
    assert raw['identifier'] == row['candidateIdentifier']
    assert raw['modelVersion'] == 'arty-model-v1'
    assert row['structurallyValid'] and row['fixturesPass']
    if row['objective'] == 'latency-v1':
        assert raw['configuration'] == dict(zip(('lanes', 'banks'), row['pinnedConfiguration']))
    else:
        assert row['pinnedConfiguration'] is None
    if row['certification'] == 'refuted-by-counterexample':
        assert row['role'] == 'horner-negative-control'
        assert row['heldOut']['failure']['details']['violation']['value'] == -42596
        assert row['acceptedScore'] is None and row['observedGapClosed'] is None
    if row['acceptedScore']:
        accepted = row['acceptedScore']
        assert row['certification'] == 'certified'
        assert accepted['configuration'] == raw['configuration']
        assert accepted['execution'] == row['execution']
        assert accepted['objective']['score'] == sum(t['cost'] for t in accepted['objective']['breakdown'])
        cfg = f"{raw['configuration']['lanes']},{raw['configuration']['banks']}"
        code, exported = e.cli('export-candidate', raw['identifier'], '--configuration', cfg)
        assert code == 0 and exported == raw
    else:
        assert row['acceptedGapClosed'] is None
    if row.get('energyProjection'):
        assert row['energyProjection']['value'] == e.energy_projection(row['execution'])

for instance in summary['instances']:
    rows = [by_id[i] for i in instance['proposals']]
    counts = instance['counts']
    assert counts['proposals'] == len(rows)
    assert counts['certified'] == sum(r['certification'] == 'certified' for r in rows)
    assert counts['passedFixturesFailedCertification'] == sum(r['fixturesPass'] and r['certification'] == 'refuted-by-counterexample' for r in rows)
    assert {'greedy', 'hand-reference'} <= {r['role'] for r in rows}
    if instance['objective'] == 'latency-v1':
        floor = e.counting_bound(instance['task'], tuple(instance['pinnedConfiguration']))
        assert instance['lowerBound'] == floor
        assert len([r for r in rows if r['role'] == 'naive' and r['certification'] == 'certified']) == 1
        for r in rows:
            if r['observedGapClosed']:
                assert r['observedGapClosed'] == e.gap(instance['naiveCycles'], floor['cycles'], r['observedCycles'])
    else:
        assert instance['lowerBound'] == e.energy_bound(instance['task'])
        baselines = [r for r in rows if r['role'] == 'naive-configuration']
        assert len(baselines) == 16 and all(r['certification'] == 'certified' for r in baselines)
        for r in rows:
            if r.get('energyProjection'):
                assert r['observedGapClosed'] == e.gap(instance['naiveEnergy'], instance['lowerBound']['units'], r['energyProjection']['value'])
        assert instance['handReferenceEnergyProjection']['status'] == 'unverified-counter-projection'
assert summary == e.finalize(json.loads((root / 'summary.json').read_text()))
print('PASS: 232 exact candidate bindings, 77 certified results, 16 instances and 3 held-out refutations')
