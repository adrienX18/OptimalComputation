#!/usr/bin/env python3
"""Independent regressions for experiment admission, schedulers and refutation."""
from collections import Counter
from copy import deepcopy
import json
from pathlib import Path
import tempfile
import experiment as e

if not __debug__:
    raise SystemExit('Assertions must be enabled')

_, base = e.cli('export-candidate', 'polynomial-naive-v1')
assert e.check_instance(base, 'polynomial', (8, 1), 'latency-v1') == 'configuration-mismatch'
assert e.check_instance(base, 'polynomial', (8, 1), 'energy-proxy-v1') is None
assert e.check_instance(base, 'gram', (8, 8), 'latency-v1') == 'workload-mismatch'
assert [e.counting_bound('matmul', c)['cycles'] for c in e.PINNED] == [96, 384, 384]
assert e.gap(100, 20, 60) == dict(numerator=1, denominator=2, fraction=.5)
assert e.gap(100, 20, 120)['fraction'] == -.25
assert e.gap(20, 20, 20) is None

for config in e.PINNED:
    greedy = e.greedy(base, config)
    assert Counter(e.canonical(i['instruction']) for i in base['schedule']) == Counter(e.canonical(i['instruction']) for i in greedy['schedule'])

with tempfile.TemporaryDirectory(prefix='section9-check-') as tmp:
    tmp = Path(tmp)
    for name, size, mutations in [
        ('polynomial-naive-v1', 24, [(0, 8), (8, 4), (0, -9), (8, -5)]),
        ('gram-naive-v1', 256, [(0, 32768), (255, -32769)]),
        ('two-stage-naive-v1', 528, [(0, 46), (256, -46), (272, 32768)])]:
        for index, value in mutations:
            values = [0] * size
            values[index] = value
            path = tmp / 'outside-domain.json'
            path.write_text(json.dumps(values))
            code, report = e.cli('evaluate', name, '--input', path)
            assert code == 1 and report['category'] == 'invalid-input', report
    held_path = tmp / 'held.json'
    held_path.write_text(json.dumps([7,-8,7,-8,7,-8,7,-8] + [-4]*16))
    code, held_result = e.cli('evaluate', 'polynomial-naive-v1', '--input', held_path)
    assert code == 0 and held_result['execution']['outputs'] == [170391]*16
    # Test the hand-built arithmetic and both domain endpoints on the actual machine.
    for task in e.TASKS:
        for config in e.PINNED:
            path = tmp / f'{task}-{config[0]}-{config[1]}.json'
            path.write_text(e.canonical(e.hand_reference(task, config)))
            for fixture in ['negative-endpoints', 'positive-endpoints', 'generated-23']:
                code, report = e.cli('simulate', path, '--fixture', fixture)
                assert code == 0, (task, config, report)
                assert report['referenceCheck']['status'] == 'match'
                assert report['execution']['cycles'] >= e.counting_bound(task, config)['cycles']
                assert 'objective' not in report
    runner = e.Runner(tmp / 'log')
    rejected = runner.proposal(base, 'polynomial', 'wrong-config', (8, 1), 'latency-v1')
    assert rejected['status'] == 'rejected-instance' and rejected['acceptedScore'] is None
    bad = deepcopy(base)
    bad['layout']['outputs'][0] = bad['layout']['inputs'][0]
    rejected = runner.proposal(bad, 'polynomial', 'bad-layout', (8, 8), 'latency-v1')
    assert not rejected['structurallyValid'] and rejected['certification'] == 'invalid-structure'
    held = [7,-8,7,-8,7,-8,7,-8] + [-4]*16
    horner = runner.proposal(e.horner((8, 8)), 'polynomial', 'horner', (8, 8), 'latency-v1', held)
    assert horner['fixturesPass'] and horner['certification'] == 'refuted-by-counterexample'
    assert horner['heldOut']['failure']['details']['violation']['value'] == -42596
    assert horner['acceptedScore'] is None
    late = deepcopy(base)
    late['schedule'] = [dict(row, cycle=row['cycle']+2_000_000) for row in base['schedule']]
    # Check exhaustion classification without spending a million simulated boundaries.
    original_cli = e.cli
    def exhausted(*args):
        if args[0] == 'simulate':
            return 3, dict(category='resource-exhausted', status='resource-exhausted')
        return original_cli(*args)
    e.cli = exhausted
    inconclusive = runner.proposal(late, 'polynomial', 'late', (8, 8), 'latency-v1')
    e.cli = original_cli
    assert inconclusive['certification'] == 'inconclusive-resource-exhausted'
    try:
        e.Runner(tmp / 'log')
    except ValueError:
        pass
    else:
        raise AssertionError('Existing history was not protected')
    events = [json.loads(line) for line in runner.log.read_text().splitlines()]
    assert len(events) == 8 and sum(row['status'] == 'submitted' for row in events) == 4
    runner.close()

for name in ['matmul-naive-v2', 'gram-naive-v1', 'two-stage-naive-v1', 'polynomial-naive-v1']:
    for config in e.PINNED:
        cfg = f'{config[0]},{config[1]}'
        code, result = e.cli('evaluate', name, '--configuration', cfg, '--fixture', 'generated-23')
        assert code == 0 and result['verificationStatus'] == 'all-input-certified'
        assert result['configuration'] == dict(lanes=config[0], banks=config[1])
        code, energy = e.cli('evaluate', name, '--configuration', cfg, '--fixture', 'generated-23', '--objective', 'energy-proxy-v1')
        assert code == 0 and energy['execution'] == result['execution']
        assert sum(b['cost'] for b in energy['objective']['breakdown']) == energy['objective']['score']
code, invalid = e.cli('evaluate', 'polynomial-naive-v1', '--configuration', '3,8')
assert code == 1 and invalid['category'] == 'inadmissible-configuration'
print('PASS: experiment admission, schedulers, configured certificates, objectives, Horner refutation and durable logs')
