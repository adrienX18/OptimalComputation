#!/usr/bin/env python3
"""Regression checks for automatic certification and its trust boundary."""
from copy import deepcopy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time

import certify as c
import experiment as e

if not __debug__:
    raise SystemExit('Assertions must be enabled')

ROOT = Path(__file__).resolve().parents[1]
GRID = ROOT / 'docs/candidates/matvec-grid-exchange-v1.json'


def precheck(path, boundaries=1000000, terms=4096):
    result = subprocess.run([str(c.CHECKER), str(path), str(boundaries), str(terms)],
                            cwd=ROOT, capture_output=True, text=True, check=True, timeout=60)
    return json.loads(result.stdout)


with tempfile.TemporaryDirectory(prefix='certification-regressions-') as directory:
    tmp = Path(directory)
    path = tmp / 'candidate.json'
    source = tmp / 'Certificate.lean'

    # Separate processes must queue for the kernel slot, and a killed holder
    # must not leave a stale lock that prevents an experiment from continuing.
    lock_root = tmp / 'lock-root'
    (lock_root / '.lake').mkdir(parents=True)
    lock_code = '''import pathlib,sys,time
sys.path.insert(0, 'scripts')
import certify
certify.ROOT = pathlib.Path(sys.argv[1])
pathlib.Path(sys.argv[2] + '.request').write_text('waiting')
with certify.kernel_slot():
    pathlib.Path(sys.argv[2]).write_text('acquired')
    time.sleep(float(sys.argv[3]))
'''
    holder = subprocess.Popen([sys.executable, '-c', lock_code, str(lock_root), str(tmp/'holder'), '30'], cwd=ROOT)
    waiter = None
    try:
        deadline = time.monotonic() + 10
        while not (tmp/'holder').exists() and time.monotonic() < deadline:
            time.sleep(.01)
        assert (tmp/'holder').exists(), 'Kernel lock holder did not start'
        waiter = subprocess.Popen([sys.executable, '-c', lock_code, str(lock_root), str(tmp/'waiter'), '0'], cwd=ROOT)
        deadline = time.monotonic() + 10
        while not (tmp/'waiter.request').exists() and time.monotonic() < deadline:
            time.sleep(.01)
        assert (tmp/'waiter.request').exists(), 'Kernel lock waiter did not start'
        time.sleep(.2)
        assert not (tmp/'waiter').exists(), 'Two processes entered the kernel slot'
        holder.terminate()
        holder.wait(timeout=10)
        assert waiter.wait(timeout=10) == 0 and (tmp/'waiter').exists(), 'Stale kernel lock'
    finally:
        for process in (holder, waiter):
            if process is not None and process.poll() is None:
                process.kill()
                process.wait()

    def check_raw(raw, category=None, **budgets):
        path.write_text(json.dumps(raw))
        report = precheck(path, **budgets)
        if category:
            assert not report['accepted'] and report['category'] == category, report
            assert 'source' not in report, report
        else:
            assert report['status'] == 'requires-kernel-check' and not report['accepted'], report
        return report

    grid = json.loads(GRID.read_text())
    for field, value in [('configuration', {'lanes': 3, 'banks': 8}),
                         ('workloadIdentifier', 'unknown-v1'), ('modelVersion', 'different-model')]:
        raw = deepcopy(grid)
        raw[field] = value
        check_raw(raw, 'unknown-workload' if field == 'workloadIdentifier' else 'invalid-candidate')
    raw = deepcopy(grid)
    raw['layout']['outputs'][0] = raw['layout']['inputs'][0]
    check_raw(raw, 'invalid-candidate')
    raw = deepcopy(grid)
    raw['schedule'][0]['instruction']['address'] = 257
    report = check_raw(raw, 'output-not-proved')
    assert report['details']['firstDifference']['expected'] != report['details']['firstDifference']['actual']
    raw = deepcopy(grid)
    raw['schedule'][72]['instruction']['left'] = 0
    check_raw(raw, 'output-not-proved')
    raw = deepcopy(grid)
    raw['schedule'][88]['instruction']['accumulator'] = 9
    report = check_raw(raw, 'machine-rule')
    assert report['details']['violation']['name'] == 'pendingRead', report
    raw = deepcopy(grid)
    raw['schedule'][1]['lane'] = 0
    report = check_raw(raw, 'machine-rule')
    assert report['details']['violation']['name'] == 'issueCollision', report
    raw = deepcopy(grid)
    raw['schedule'][-1]['instruction']['source'] = 0
    check_raw(raw, 'output-not-proved')
    raw = deepcopy(grid)
    raw['configuration']['banks'] = 1
    report = check_raw(raw, 'machine-rule')
    assert report['details']['violation']['name'] == 'bankCapacity', report
    raw = deepcopy(grid)
    raw['schedule'].pop()
    check_raw(raw, 'missing-output')
    check_raw(grid, 'boundary-budget', boundaries=5)
    check_raw(grid, 'expression-budget', terms=0)
    raw = deepcopy(grid)
    raw['identifier'] = 'fresh-grid-name'
    raw['schedule'].reverse()
    check_raw(raw)

    path.write_text(GRID.read_text().replace('"identifier":', '"identifier":"duplicate", "identifier":', 1))
    assert precheck(path)['category'] == 'invalid-candidate-file'
    path.write_text(GRID.read_text().replace('"identifier":', '"\\u0069dentifier":"duplicate", "identifier":', 1))
    assert precheck(path)['category'] == 'invalid-candidate-file'

    # Compiled checks cover all hand references, but never grant acceptance themselves.
    for task in e.TASKS:
        for config in e.PINNED:
            check_raw(e.hand_reference(task, config))
    for config in e.PINNED:
        report = check_raw(e.horner(config), 'range-not-proved')
        assert report['details']['bits'] == 16

    # Independent small candidate, renamed and reordered; no identifier dispatch.
    _, tiny = e.cli('export-candidate', 'tiny-multiply-v1')
    tiny['identifier'] = 'unregistered-kernel-regression'
    tiny['schedule'].reverse()
    path.write_text(json.dumps(tiny))
    result = c.certify(path, output=source)
    assert result['accepted'] and result['cycles'] == 6, result
    assert result['certificateDeclaration'].split('.')[0] in source.read_text()
    previous = source.read_bytes()
    path.write_text('{invalid')
    assert not c.certify(path, output=source)['accepted']
    assert source.read_bytes() == previous  # rejection does not replace a prior artifact
    assert not c.certify(GRID, timeout=.0001)['accepted']
    assert not c.certify(GRID, timeout=float('nan'))['accepted']
    assert not c.certify(GRID, output=GRID)['accepted']

    # Kernel-check the main acceptance target and compare the committed proof source.
    result = c.certify(GRID, output=source)
    assert result['accepted'] and result['status'] == 'correct' and result['cycles'] == 79, result
    assert source.read_bytes() == (ROOT / 'docs/certificates/matvec-grid-exchange-v1.lean').read_bytes()
    # Corrupt the claimed result: compiled success cannot turn it into a proof.
    tampered = previous.decode().replace('= some 6 :=', '= some 5 :=')
    source.write_text(tampered)
    rejected = c.run_process(['lake', 'env', 'lean', str(source)], 120)
    assert rejected.returncode != 0
    # The untrusted formatter cannot substitute a different typed candidate,
    # even if that substitute computes the same mathematical result.
    source.write_text(previous.decode().replace('identifier := raw.identifier',
                                               'identifier := "substituted-candidate"'))
    rejected = c.run_process(['lake', 'env', 'lean', str(source)], 120)
    assert rejected.returncode != 0 and 'exactBinding' in rejected.stdout
    assert not c.audit_kernel_output('')
    assert not c.audit_kernel_output("'GeneratedCertificate.checked' depends on axioms: [untrusted]")

    # Direct candidate emission must handle sparse, nonmonotone addresses and
    # scratch storage, not assume the contiguous reference layout.
    _, sparse = e.cli('export-candidate', 'tiny-multiply-v1')
    sparse['identifier'] = 'sparse-layout-kernel-regression'
    sparse['layout'] = dict(inputs=[4095, 42], outputs=[303], scratch=[11])
    for row in sparse['schedule']:
        instruction = row['instruction']
        if 'address' in instruction:
            instruction['address'] = {0:4095, 1:42, 2:11}[instruction['address']]
    sparse['schedule'] += [
        dict(cycle=7, lane=0, instruction=dict(kind='load', destination=4, address=11)),
        dict(cycle=8, lane=0, instruction=dict(kind='store', source=4, address=303))]
    sparse['schedule'].reverse()
    path.write_text(json.dumps(sparse))
    result = c.certify(path)
    assert result['accepted'] and result['cycles'] == 9, result

    # The polynomial reference uses powers; the program uses an Estrin-style tree.
    path.write_text(json.dumps(e.hand_reference('polynomial', (8, 8))))
    result = c.certify(path)
    assert result['accepted'] and result['cycles'] == 63, result

    # Hundreds of harmless instructions exercise a longer execution with an
    # automatically reduced proof budget, including pending effects at the end.
    _, padded = e.cli('export-candidate', 'tiny-multiply-v1')
    padded['identifier'] = 'proof-budget-regression'
    shifted = [dict(row, cycle=row['cycle']+31) for row in padded['schedule']]
    def zero_add(i):
        return dict(cycle=i, lane=0, instruction=dict(kind='add', destination=13+i%3, left=0, right=0))
    padded['schedule'] = [zero_add(i) for i in range(28)] + shifted + [zero_add(i) for i in range(40,520)]
    path.write_text(json.dumps(padded))
    result = c.certify(path, output=source, boundaries=530)
    assert result['accepted'] and result['cycles'] == 522, result
    assert result['certificateBoundaryBudget'] == 524 and result['boundaryBudget'] == 530, result
    assert 'candidate 524 4096' in source.read_text()
    exhausted = c.certify(path, boundaries=32)
    assert not exhausted['accepted'] and exhausted['category'] == 'boundary-budget', exhausted

print('PASS: automatic kernel certificates, exact binding, mutants, budgets, duplicate keys, '
      'Horner rejection, all 12 hand references, proof budgets/tampering, and unchanged generated artifact')
