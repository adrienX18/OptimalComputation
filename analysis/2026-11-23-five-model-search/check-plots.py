#!/usr/bin/env python3
"""Validate statistics, plotting inputs, exports and report links, without API calls."""
from collections import Counter
import csv
import hashlib
from itertools import product
import json
from math import isclose
from pathlib import Path
import re
from statistics import median

from PIL import Image, ImageStat
import plot

if not __debug__:
    raise SystemExit('Checks require assertions; do not use -O or -OO.')

ROOT = Path(__file__).resolve().parent
FIGURES = ROOT/'figures'


def csv_rows(path):
    with path.open(newline='') as stream:
        return list(csv.DictReader(stream))


# Exact sign-test coverage, rather than relying on a numerical bootstrap.
assert sum(min(x) <= .5 <= max(x) for x in product([0, 1], repeat=5)) == 30
assert 30/32 == .9375
assert plot.median_ci([9, 1, 5, 7, 3]) == (5, 1, 9)
assert plot.median_ci([30]*5) == (30, 30, 30)
for values in [[1,2,3,4], [1,2,3,4,float('nan')]]:
    try:
        plot.median_ci(values)
    except ValueError:
        pass
    else:
        raise AssertionError('Invalid sampling unit accepted')
mid,low,high=plot.success_ci(5)
assert mid == high == 1 and isclose(low,.025**.2,abs_tol=1e-12)
mid,low,high=plot.success_ci(0)
assert mid == low == 0 and isclose(high,1-.025**.2,abs_tol=1e-12)

metrics=json.loads((ROOT/'metrics.json').read_text())
runs=csv_rows(ROOT/'runs.csv')
attempts=csv_rows(ROOT/'attempts.csv')
curves=csv_rows(ROOT/'convergence.csv')
assert len(runs)==25 and len(attempts)==len(curves)==1250
assert Counter(plot.outcome(a) for a in attempts)=={0:1033,1:109,2:11,3:34,4:16,5:30,6:14,7:3}
assert sum(bool(a['outputCodeBytes']) for a in attempts)==1127
oversized=[a for a in attempts if a['outputCodeBytes'] and int(a['outputCodeBytes'])>8000]
assert len(oversized)==34 and all(a['model']=='sol' and plot.outcome(a)==3 for a in oversized)
assert max(int(a['promptBytes']) for a in attempts)==29861
assert all(int(a['historyRows'])==int(a['attempt'])-1 for a in attempts)
for model in plot.MODELS:
    selected=[r for r in runs if r['model']==model]
    assert sorted(int(r['seed']) for r in selected)==plot.SEEDS
    for seed in plot.SEEDS:
        a=[r for r in attempts if r['model']==model and int(r['seed'])==seed]
        c=[r for r in curves if r['model']==model and int(r['seed'])==seed]
        assert [int(r['attempt']) for r in a]==list(range(1,51))
        assert [int(r['attempt']) for r in c]==list(range(1,51))
        assert [r['best'] for r in a]==[r['bestCycles'] for r in c]
    assert sum(int(r['certified']) for r in selected)==metrics['models'][model]['certified']
    assert sum(int(r['outputTokens']) for r in selected)==metrics['models'][model]['outputTokens']
    assert isclose(sum(float(r['apiSeconds']) for r in selected),metrics['models'][model]['apiSeconds'],abs_tol=.01)

intervals=csv_rows(FIGURES/'intervals.csv')
assert len(intervals)==555
converters={
    'final_best_cycles': lambda r:float(r['bestCycles']),
    'attempt_to_eventual_best':lambda r:float(r['bestFirstAttempt']),
    'minutes_to_eventual_best':lambda r:float(r['secondsToBest'])/60,
    'percent_after_eventual_best':lambda r:2*(50-int(r['bestFirstAttempt'])),
    'within_run_unique_percent':lambda r:100*int(r['uniqueCertifiedCandidates'])/int(r['certified']),
    'run_certified_percent':lambda r:2*int(r['certified']),
    'output_ktokens_per_run':lambda r:int(r['outputTokens'])/1000,
    'api_minutes_per_run':lambda r:float(r['apiSeconds'])/60,
    'median_call_seconds_per_run':lambda r:float(r['medianApiSeconds']),
}
for record in intervals:
    model=record['model']; metric=record['metric']; assert int(record['n'])==5
    got=[float(record[k]) for k in ['estimate','lower','upper']]
    if metric=='reach_30_by_50':
        assert float(record['confidence'])==.95
        k=sum(int(r['bestCycles'])<=30 for r in runs if r['model']==model)
        expected=plot.success_ci(k)
    else:
        assert float(record['confidence'])==.9375
        if metric in converters:
            values=[converters[metric](r) for r in runs if r['model']==model]
        elif metric=='best_so_far_cycles':
            i=int(record['attempt'])
            values=[1520]*5 if i==0 else [int(r['bestCycles']) for r in curves if r['model']==model and int(r['attempt'])==i]
        elif metric=='prompt_kbytes':
            values=[int(r['promptBytes'])/1000 for r in attempts if r['model']==model and r['attempt']==record['attempt']]
        else:
            raise AssertionError(metric)
        assert len(values)==5
        expected=(median(values),min(values),max(values))
    assert all(isclose(a,b,abs_tol=1e-10) for a,b in zip(got,expected)),record

provenance=json.loads((FIGURES/'provenance.json').read_text())
for name,digest in provenance['inputHashes'].items():
    assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest
assert hashlib.sha256((ROOT/'plot.py').read_bytes()).hexdigest()==provenance['plotScriptSha256']
assert hashlib.sha256((ROOT/'analyze.py').read_bytes()).hexdigest()==provenance['analysisScriptSha256']
assert len(provenance['figureFiles'])==30
for name in provenance['figureFiles']:
    p=FIGURES/name
    if p.suffix=='.png':
        with Image.open(p) as image:
            image.verify()
        with Image.open(p) as image:
            assert image.width>=2000 and image.height>=1200
            assert ImageStat.Stat(image.convert('L')).stddev[0]>10
    elif p.suffix=='.pdf':
        assert p.read_bytes().startswith(b'%PDF-')
    elif p.suffix=='.svg':
        assert '<svg' in p.read_text()
layout=json.loads((FIGURES/'layout-check.json').read_text())
assert len(layout)==10
assert not any(row['overflowingText'] for row in layout),layout
assert not any(row['overlappingLegends'] for row in layout),layout

report=(ROOT/'report.md').read_text()
images=re.findall(r'!\[[^\]]*\]\(([^)]+)\)',report)
assert len(images)==12 and len(set(images))==12
for name in ['report.md','figure-methods.md']:
    for link in re.findall(r'\]\(([^)]+)\)',(ROOT/name).read_text()):
        if not link.startswith(('https://','http://','#')):
            assert (ROOT/link.split('#')[0]).exists(),link
print('PASS: exact interval coverage/endpoints; 1,250 inputs; 555 interval rows; 30 exports; layout bounds and report links')
