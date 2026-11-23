#!/usr/bin/env python3
"""Offline end-to-end coverage of all 16 suite cases; real Docker and Lean, no API calls."""
import argparse
import base64
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
from pathlib import Path
import zlib

import experiment
import search
import search_batch
from harness import evaluate, prompt
from harness.archive import read_json, write_json


def check(root, name, config):
    # Deliberately change the hardware for energy, keeping the same mathematical task.
    hardware = (4, 4) if config['objective'] == 'energy-proxy-v1' else tuple(config['configuration'])
    candidate = experiment.hand_reference(config['task'], hardware)
    candidate['identifier'] = 'suite-integration-' + name
    encoded = base64.b64encode(zlib.compress(json.dumps(candidate).encode())).decode()
    code = ('import base64,json,zlib\ndef build():\n'
            f'    return json.loads(zlib.decompress(base64.b64decode({encoded!r})))\n')
    # Test fixtures transport larger known schedules; live generators keep their 8k limit.
    config = config | dict(model='replay', attempts=1, code_bytes=max(8000,len(code.encode())))
    folder = root / name
    result = search.run(folder, config, replay=[dict(idea='Known reference integration', code=code, notes='')])
    feedback = result['attempts'][0]
    assert feedback['accepted'], (name, feedback)
    scored = read_json(folder/'attempts/0001/score.json')
    assert scored['configuration'] == dict(zip(['lanes','banks'],hardware)), name
    assert scored['objective']['identifier'] == config['objective'], name
    assert sum(t['quantity']*t['coefficient'] for t in scored['objective']['breakdown']) == feedback['score'], name
    if config['objective'] == 'energy-proxy-v1':
        request = read_json(folder/'attempts/0001/request.json')
        assert prompt.ENERGY_RULES in request['messages'][0]['content']
        # The exact same artifact must be rejected under pinned latency hardware.
        rejected = evaluate.evaluate(config | dict(objective='latency-v1'),
                                      read_json(folder/'baseline.json'), folder/'attempts/0001')
        assert rejected['category'] == 'wrong-configuration', rejected
    return dict(instance=name, accepted=True, score=feedback['score'],
                unit=feedback['unit'], hardware=list(hardware))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--workers', type=int, default=2)
    parser.add_argument('--case', action='append', help='check only these named cases (repeatable)')
    args = parser.parse_args()
    if not __debug__:
        parser.error('Assertions must be enabled.')
    args.output.mkdir(parents=True, exist_ok=False)
    config = search_batch.settings(read_json(search.ROOT/'configs/search.suite.json'))
    order = ['polynomial', 'two-stage', 'gram', 'matmul']
    cases = sorted(config['instances'].items(), key=lambda item: order.index(item[1]['task']))
    if args.case:
        if set(args.case) - set(config['instances']):
            parser.error('Unknown suite case.')
        cases = [(name, case) for name, case in cases if name in args.case]
    pool = ThreadPoolExecutor(max_workers=args.workers)
    try:
        futures = {pool.submit(check,args.output,name,config['run'] | case | dict(seed=11)): name
                   for name,case in cases}
        results = []
        for future in as_completed(futures):
            try:
                results.append(future.result())
            except Exception as exc:
                results.append(dict(instance=futures[future], accepted=False, error=str(exc)))
            write_json(args.output/'checked.json',results)
            print('PASS:' if results[-1]['accepted'] else 'FAIL:',results[-1]['instance'],flush=True)
    finally:
        pool.shutdown(wait=True, cancel_futures=True)
    search_batch.inventory(args.output)
    if not all(r['accepted'] for r in results):
        raise SystemExit('Some suite checks failed; see checked.json and the complete run archives.')
    print(f'PASS: all {len(cases)} selected cases, kernel certification and score breakdowns')


if __name__ == '__main__':
    main()
