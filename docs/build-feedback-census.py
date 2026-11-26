#!/usr/bin/env python3
"""Census saved live attempts, exact rejection messages, delivery, and timings.

No models, generators, or Lean commands are executed. Requires the original runs/
archives to rebuild. --check validates committed checksums, derived summaries,
and original input hashes when those original files are available.
"""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
import math
from pathlib import Path
import statistics

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'docs/evidence/deep-dive-2-census'
CATALOGUE = ROOT / 'docs/ERROR_CATALOGUE.md'
MAIN = {'nightly-five-models-20261123', 'suite-smoke-20261123'}
TIME_KEYS = {'seconds', 'kernelSeconds', 'totalSeconds', 'started', 'ended', 'time'}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def encode(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def stable(value):
    if isinstance(value, dict):
        return {k:stable(v) for k,v in value.items() if k not in TIME_KEYS}
    if isinstance(value, list):
        return [stable(v) for v in value]
    return value


def clipped(value):
    return json.dumps(value, ensure_ascii=False).encode()[:3000].decode(errors='ignore')


def family(feedback):
    category = feedback['category']
    message = feedback.get('message', '')
    if category == 'proposal-error':
        if message.startswith('Incomplete response: '):
            return category + '/' + message.removeprefix('Incomplete response: ')
        if message.startswith('Extra data:'):
            return category + '/extra-JSON-data'
        if message.startswith('Expecting value:'):
            return category + '/expected-JSON-value'
        if message == 'Generator exceeds code_bytes.':
            return category + '/code-size'
    if category == 'generator-failed':
        if feedback['process']['status'] == 'timeout':
            return category + '/timeout'
        return category + '/' + message.strip().splitlines()[-1].split(':')[0]
    if category == 'simulation-failed':
        report = feedback['failure'].get('report') or {}
        violation = ((report.get('details') or {}).get('violation') or {}).get('name')
        return category + '/' + (violation or report.get('category', 'no-report'))
    if category == 'api-error':
        return category + '/' + message.split(':')[0]
    return category


def strings(value, pointer=''):
    if isinstance(value, dict):
        for key, item in value.items():
            child = pointer + '/' + key
            if key in ('message', 'log') and isinstance(item, str) and item:
                yield child, item
            yield from strings(item, child)
    elif isinstance(value, list):
        for i, item in enumerate(value):
            yield from strings(item, pointer + '/' + str(i))


def stats(values):
    values = sorted(values)
    if not values:
        return None
    return dict(n=len(values), minimum=values[0], median=statistics.median(values),
                p90=values[math.ceil(.9 * len(values))-1], maximum=values[-1])


def derive(rows, failures):
    by_archive = defaultdict(Counter)
    groups = defaultdict(lambda: defaultdict(list))
    statuses = defaultdict(lambda: defaultdict(Counter))
    families = defaultdict(lambda: dict(recorded=0, sent=0, cases=[]))
    messages = {}
    for row in rows:
        by_archive[row['archive']][row['category']] += 1
        key = row['archive'] + '/' + row['task']
        timing = row['timing']
        for name in ('precheck', 'kernel', 'generation'):
            result = timing.get(name)
            if result:
                statuses[key][name][result['status']] += 1
                if result['status'] == 'completed':
                    groups[key][name].append(result['seconds'])
        queue = timing.get('queue')
        if queue:
            statuses[key]['queue'][queue['status']] += 1
            if queue.get('waitSeconds') is not None:
                groups[key]['queue'].append(queue['waitSeconds'])
        cert = timing.get('certification')
        if cert and cert.get('accepted') and cert.get('totalSeconds') is not None:
            groups[key]['acceptedCertificationTotal'].append(cert['totalSeconds'])
        simulations = timing.get('simulations')
        if simulations:
            groups[key]['simulationProcessSum'].append(sum(x['process']['seconds'] for x in simulations))
    for case in failures:
        entry = families[case['family']]
        entry['recorded'] += 1
        entry['sent'] += bool(case['delivery'])
        entry['cases'].append(case['path'])
        for pointer, text in strings(case['feedback']):
            key = sha(text.encode())
            if key not in messages:
                messages[key] = dict(id=key, text=text, occurrences=[])
            received = case['delivery']['text'] if case['delivery'] else ''
            # Match the exact JSON-escaped message, rather than claiming the
            # entire untruncated feedback object was delivered.
            sent = bool(received) and any(json.dumps(text, ensure_ascii=a)[1:-1] in received for a in (True, False))
            messages[key]['occurrences'].append(dict(case=case['path'], family=case['family'],
                                                     pointer=pointer, fullyPresentInNextPrompt=sent))
    unique = sorted(messages.values(), key=lambda m:(m['occurrences'][0]['family'], m['text']))
    for i, message in enumerate(unique, 1):
        message['label'] = f'E{i:03d}'
    summary = dict(
        liveAttempts=len(rows), accepted=sum(r['accepted'] for r in rows), unaccepted=len(failures),
        mainStudyAttempts=sum(r['archive'] in MAIN for r in rows),
        mainStudyUnaccepted=sum(c['archive'] in MAIN for c in failures),
        delivered=sum(bool(c['delivery']) for c in failures),
        noNextRequest=sum(not c['delivery'] for c in failures),
        clippedDeliveries=sum(bool(c['delivery']) and not c['delivery']['validJson'] for c in failures),
        uniqueNonemptyMessageStrings=len(unique),
        uniqueMessagesFullyPresentInNextPrompt=sum(any(o['fullyPresentInNextPrompt'] for o in m['occurrences']) for m in unique),
        byArchive=dict(by_archive), families=dict(sorted(families.items())),
        timing={key:dict(statistics={name:stats(v) for name,v in ms.items()},
                         processStatuses=dict(statuses[key])) for key,ms in sorted(groups.items())})
    return summary, unique


def render_catalogue(summary, messages, failures):
    lines = ['# Every observed rejection message in the saved live experiments\n\n',
        'Companion to [Deep dive 2](../DEEP_DIVE_2.md). Generated by [the census script](build-feedback-census.py). ',
        'Scope: all saved live-model attempt feedback under `runs/`, including the two reported studies and both smaller live pilots. ',
        'Offline replay/integration attempts are counted separately in the [scope record](evidence/deep-dive-2-census/scope.json); they did not send feedback to a live model.\n\n',
        f'The census contains **{summary["liveAttempts"]} attempts, {summary["unaccepted"]} unaccepted attempts, ',
        f'{summary["delivered"]} with a saved next request, and {summary["noNextRequest"]} without one**. ',
        f'One delivered feedback string was clipped mid-JSON. There are **{len(messages)} distinct nonempty message strings**, ',
        f'of which **{summary["uniqueMessagesFullyPresentInNextPrompt"]} occur in full in at least one saved next prompt**.\n\n',
        'Deduplication is by exact message text, across top-level and nested `message`/`log` fields. ',
        'Repeated identical strings appear once. Different numeric values, locations, traceback lines, or provider request IDs remain separate exact variants. ',
        'The family overview groups these variants without hiding any of them. The generic wrapper “A public fixture failed.” is also included once. ',
        'An empty generator stderr cannot supply a nonempty message: the generator timeout is represented explicitly in the family table and its full case record.\n\n',
        '“Sent” means present in a saved API request, not evidence that the model understood or acted on it. ',
        'A final-attempt failure is still included even when no next request exists. These are observed rejections; a timeout, API failure, or unproved range is not automatically a counterexample to program correctness.\n\n',
        '## Error families\n\n| Family | Recorded attempts | With next prompt |\n| --- | ---: | ---: |\n']
    for name, value in summary['families'].items():
        lines.append(f'| `{name}` | {value["recorded"]} | {value["sent"]} |\n')
    lines += ['\n## Exact messages, without duplicates\n\n',
        'The [machine-readable messages](evidence/deep-dive-2-census/messages.json) list every occurrence and its source field. ',
        'The [complete failure records](evidence/deep-dive-2-census/failures.json) retain each original feedback object and the exact next-prompt feedback string.\n']
    for message in messages:
        occurrences = message['occurrences']
        sent = sum(o['fullyPresentInNextPrompt'] for o in occurrences)
        lines.append(f'\n<a id="{message["label"].lower()}"></a>\n\n### {message["label"]} — `{occurrences[0]["family"]}`\n\n'
                     f'{len(occurrences)} recorded occurrence(s); {sent} complete occurrence(s) in next prompts. '
                     f'First source: `{occurrences[0]["case"]}/feedback.json`, field `{occurrences[0]["pointer"]}`.\n\n'
                     '```text\n' + message['text'].rstrip('\n') + '\n```\n')
    clipped_cases = [c for c in failures if c['delivery'] and not c['delivery']['validJson']]
    lines.append('\n## Exact clipped feedback\n\nThis is the whole 3,000-byte feedback string sent after the Gram mismatch; it is intentionally incomplete JSON. The outer API request remained valid JSON because this was a string value.\n')
    for case in clipped_cases:
        lines.append('\nSource: `' + case['delivery']['request'] + '`.\n\n```text\n' + case['delivery']['text'] + '\n```\n')
    lines.append('\n## Coverage of simulation failures\n\nThe harness simulated every fixture but forwarded only the first failed fixture. The [additional fixture records](evidence/deep-dive-2-census/fixture-failures.json) preserve all failing fixture reports, with the forwarded one marked. They are not all messages sent to the model.\n')
    return ''.join(lines).encode()


def build():
    sources, inventories = {}, {}

    def read(path):
        data = path.read_bytes()
        rel = str(path.relative_to(ROOT))
        archived = False
        archive = path.relative_to(ROOT / 'runs').parts[0]
        inventory_file = ROOT / 'runs' / archive / 'inventory.json'
        if archive not in inventories:
            inventories[archive] = ({r['path']:r for r in json.loads(inventory_file.read_bytes())}
                                    if inventory_file.exists() else None)
        inventory = inventories[archive]
        if inventory is not None:
            item = inventory[str(path.relative_to(inventory_file.parent))]
            require(item['sha256'] == sha(data) and item['bytes'] == len(data), f'Historical inventory mismatch: {path}')
            archived = True
        sources[rel] = dict(path=rel, bytes=len(data), sha256=sha(data), matchedHistoricalInventory=archived)
        return json.loads(data)

    rows, failures, fixtures = [], [], []
    scope = defaultdict(lambda:dict(live=0, replay=0, categories=Counter()))
    manifests = {}
    for path in sorted((ROOT / 'runs').rglob('feedback.json')):
        directory = path.parent
        run = directory.parent.parent
        if run not in manifests:
            manifests[run] = read(run / 'manifest.json')
        manifest = manifests[run]
        feedback = read(path)
        archive = path.relative_to(ROOT / 'runs').parts[0]
        scope[archive]['categories'][feedback['category']] += 1
        if manifest.get('replay') is not None:
            scope[archive]['replay'] += 1
            continue
        scope[archive]['live'] += 1
        config = manifest['config']
        row = dict(path=str(directory.relative_to(ROOT)), archive=archive, task=config['task'],
                   model=config['model'], seed=config.get('seed'), attempt=feedback['attempt'],
                   category=feedback['category'], accepted=feedback['accepted'], revision=manifest['revision'], timing={})
        timing = row['timing']
        for name, rel in [('generation', 'generation/process/result.json'), ('precheck', 'certification/precheck/result.json'),
                          ('kernel', 'certification/kernel/result.json'), ('queue', 'certification/kernel-queue.json')]:
            source = directory / rel
            if source.exists():
                timing[name] = read(source)
        cert = directory / 'certification/result.json'
        if cert.exists():
            result = read(cert)
            timing['certification'] = {k:result[k] for k in ('accepted','category','kernelSeconds','totalSeconds') if k in result}
        sims = directory / 'simulations.json'
        if sims.exists():
            simulations = read(sims)
            timing['simulations'] = [{k:s[k] for k in ('fixture','passed','process')} for s in simulations]
            for sim in simulations:
                if not sim['passed']:
                    fixtures.append(dict(case=row['path'], fixture=sim['fixture'], process=sim['process'], report=sim['report'],
                                         forwardedAsFirstFailure=feedback.get('failure',{}).get('fixture') == sim['fixture']))
        rows.append(row)
        if feedback['accepted']:
            continue
        case = {k:row[k] for k in ('path','archive','task','model','attempt')}
        case.update(family=family(feedback), feedback=feedback, delivery=None)
        next_request = directory.parent / f'{feedback["attempt"]+1:04d}' / 'request.json'
        if next_request.exists():
            request = read(next_request)
            context = json.loads(request['messages'][1]['content'])
            text = context['latest']['feedback']
            if text == clipped(stable(feedback)):
                policy = 'timing-fields-removed; 3000-byte-limit'
            elif text == clipped(feedback):
                policy = 'historical-pilot-keeps-timing; 3000-byte-limit'
            else:
                raise ValueError(f'Unexpected feedback transformation: {next_request}')
            try:
                json.loads(text)
                valid = True
            except json.JSONDecodeError:
                valid = False
            case['delivery'] = dict(request=str(next_request.relative_to(ROOT)), text=text, validJson=valid, policy=policy)
        failures.append(case)
    summary, messages = derive(rows, failures)
    outputs = {'attempts.json':encode(rows), 'failures.json':encode(failures), 'fixture-failures.json':encode(fixtures),
               'summary.json':encode(summary), 'messages.json':encode(messages), 'scope.json':encode(dict(scope))}
    for name,data in outputs.items():
        (OUT / name).write_bytes(data)
    catalogue = render_catalogue(summary, messages, failures)
    CATALOGUE.write_bytes(catalogue)
    provenance = dict(description='Saved live-attempt census; all exact feedback strings retained; replay attempts excluded from live-model statistics.',
        percentile='Nearest rank: sorted values[ceil(0.9*n)-1]; median uses statistics.median.',
        sources=sorted(sources.values(), key=lambda r:r['path']),
        outputs=[dict(file=name, bytes=len(data), sha256=sha(data)) for name,data in outputs.items()] +
                [dict(file='../../ERROR_CATALOGUE.md', bytes=len(catalogue), sha256=sha(catalogue))])
    (OUT / 'provenance.json').write_bytes(encode(provenance))


def check():
    provenance = json.loads((OUT / 'provenance.json').read_bytes())
    known_feedback = {r['path'] for r in provenance['sources'] if r['path'].endswith('/feedback.json')}
    original_feedback = {str(p.relative_to(ROOT)) for p in (ROOT / 'runs').rglob('feedback.json')}
    if original_feedback:
        require(original_feedback <= known_feedback, 'New attempt feedback exists outside the saved census; rebuild it')
    for row in provenance['outputs']:
        data = (OUT / row['file']).read_bytes()
        require(sha(data) == row['sha256'] and len(data) == row['bytes'], f'Changed output: {row["file"]}')
    for row in provenance['sources']:
        path = ROOT / row['path']
        if path.exists():
            data = path.read_bytes()
            require(sha(data) == row['sha256'] and len(data) == row['bytes'], f'Changed original: {path}')
    rows = json.loads((OUT / 'attempts.json').read_bytes())
    failures = json.loads((OUT / 'failures.json').read_bytes())
    summary, messages = derive(rows, failures)
    require(encode(summary) == (OUT / 'summary.json').read_bytes(), 'Summary mismatch')
    require(encode(messages) == (OUT / 'messages.json').read_bytes(), 'Message catalogue mismatch')
    require(render_catalogue(summary, messages, failures) == CATALOGUE.read_bytes(), 'Rendered catalogue mismatch')
    require(len({r['path'] for r in rows}) == len(rows), 'Duplicate attempts')
    require({r['path'] for r in rows if not r['accepted']} == {r['path'] for r in failures}, 'Missing failure')
    print(f'PASS: {len(rows)} live attempts, {len(failures)} failures, {len(messages)} unique messages; exact next prompts, timing statistics, and {len(provenance["sources"])} source hashes.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    if not args.check:
        OUT.mkdir(parents=True, exist_ok=True)
        build()
    check()


if __name__ == '__main__':
    main()
