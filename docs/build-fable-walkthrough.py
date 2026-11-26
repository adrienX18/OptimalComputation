#!/usr/bin/env python3
"""Export and audit two complete historical attempts; never call a model.

Default: copy originals after checking the historical inventory, decode the
model-visible text, and rebuild the generated portion of FABLE_WALKTHROUGH.md.
--check: check the committed evidence and rendered text without writing files.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import runpy
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / 'runs/nightly-five-models-20261123'
RUN = ARCHIVE / 'runs/fable/seed-11'
OUT = ROOT / 'docs/evidence/fable-two-iterations'
GUIDE = ROOT / 'docs/FABLE_WALKTHROUGH.md'
MARKER = '<!-- generated-transcript: docs/build-fable-walkthrough.py -->'
ATTEMPTS = ('0001', '0002')


def read(path):
    return json.loads(path.read_text())


def sha(data):
    return hashlib.sha256(data).hexdigest()


def formatted(value):
    return json.dumps(value, ensure_ascii=False, indent=2) + '\n'


def require(value, message):
    if not value:
        raise ValueError(message)


def export():
    inventory_path = ARCHIVE / 'inventory.json'
    inventory = {r['path']: r for r in read(inventory_path)}
    sources = [RUN / 'manifest.json', RUN / 'baseline.json']
    sources += [RUN / 'source' / name for name in (
        'scripts/search.py', 'scripts/harness/model.py',
        'scripts/harness/prompt.py', 'scripts/harness/evaluate.py')]
    for n in ATTEMPTS:
        sources += sorted(p for p in (RUN / 'attempts' / n).rglob('*') if p.is_file())
    records = []
    for source in sources:
        data = source.read_bytes()
        old = inventory[str(source.relative_to(ARCHIVE))]
        require(sha(data) == old['sha256'] and len(data) == old['bytes'], f'Archive changed: {source}')
        rel = source.relative_to(RUN)
        destination = OUT / rel
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
        records.append(dict(file=str(rel), source=str(source.relative_to(ROOT)),
                            bytes=len(data), sha256=sha(data)))
    (OUT / 'provenance.json').write_text(formatted(dict(
        description='Two complete historical attempt directories, with run metadata and relevant historical harness source. Byte-for-byte exports; decoded/ contains derived text.',
        inventorySha256=sha(inventory_path.read_bytes()), files=records)))


def decoded(n):
    p = OUT / 'attempts' / n
    request, response = read(p / 'request.json'), read(p / 'response.json')
    message = response['choices'][0]['message']
    require([m['role'] for m in request['messages']] == ['system', 'user'], 'Unexpected messages')
    require(not request.get('tools') and not request.get('functions'), 'Unexpected tools')
    require(not message.get('tool_calls') and not message.get('function_call'), 'Unexpected calls')
    raw = read(p / 'provider-002-response.json')['response']
    raw = json.loads(raw) if isinstance(raw, str) else raw
    require([b['type'] for b in raw['content']] == ['thinking', 'text'], 'Unexpected blocks')
    require(raw['content'][0]['thinking'] == message['reasoning_content'], 'Thinking text mismatch')
    require(raw['content'][1]['text'] == message['content'], 'Answer text mismatch')
    body = read(p / 'provider-001-request.json')['additional_args']['complete_input_dict']
    require(body['thinking'] == dict(type='adaptive', display='summarized'), 'Unexpected thinking mode')
    require(not body.get('tools'), 'Provider tools present')
    require(body['system'] == [dict(type='text', text=request['messages'][0]['content'])], 'System changed by adapter')
    require(body['messages'] == [dict(role='user', content=[dict(type='text', text=request['messages'][1]['content'])])], 'User message changed by adapter')
    proposal = read(p / 'proposal.json')
    require(json.loads(message['content']) == proposal, 'Proposal mismatch')
    require(proposal['code'] == (p / 'generator.py').read_text(), 'Code mismatch')
    require(read(p / 'generation/process/stdout.txt') == read(p / 'candidate.json'), 'Candidate mismatch')
    certificate = read(p / 'certification/result.json')
    require(sha((p / 'candidate.json').read_bytes()) == certificate['candidateSha256'], 'Candidate hash mismatch')
    require(sha((p / 'certification/Certificate.lean').read_bytes()) == certificate['certificateSha256'], 'Certificate hash mismatch')
    return {
        'system.txt': request['messages'][0]['content'],
        'user.txt': request['messages'][1]['content'],
        'user.pretty.json': formatted(json.loads(request['messages'][1]['content'])),
        'thinking.txt': message['reasoning_content'],
        'answer.txt': message['content'],
        'provider-body.pretty.json': formatted(body),
    }


def render(all_decoded):
    chunks = ['\n\n<a id="transcript"></a>\n\n## Complete transcript and execution records\n\n'
              'The sections below are generated from the archived bytes. All prompt, returned thinking-summary, idea, code, and notes text is included. JSON user messages are indented for readability; the linked `.txt` files preserve their exact original strings. The two system messages are identical and are printed once. Machine traces and raw response metadata are linked in full.\n']

    def block(language, text):
        chunks.append('\n```' + language + '\n' + text.rstrip('\n') + '\n```\n')

    chunks.append('\n### System message supplied in both iterations\n')
    block('text', all_decoded['0001']['system.txt'])
    require(all_decoded['0001']['system.txt'] == all_decoded['0002']['system.txt'], 'Systems differ')
    for n in ATTEMPTS:
        p = OUT / 'attempts' / n
        prefix = f'evidence/fable-two-iterations/attempts/{n}'
        d = all_decoded[n]
        response, proposal = read(p / 'response.json'), read(p / 'proposal.json')
        request = read(p / 'request.json')
        chunks.append(f'\n<a id="iteration-{int(n)}"></a>\n\n### Iteration {int(n)} — exact request\n\n'
                      f'[Original request]({prefix}/request.json) · [Provider request, including transformed body]({prefix}/provider-001-request.json) · '
                      f'[Exact user-message string](evidence/fable-two-iterations/decoded/{n}/user.txt)\n\n'
                      'Request settings (the two messages follow separately):\n')
        block('json', formatted({k:v for k,v in request.items() if k != 'messages'}))
        block('json', d['user.pretty.json'])
        chunks.append(f'\n### Iteration {int(n)} — complete returned thinking summary\n\n'
                      f'[Exact returned text](evidence/fable-two-iterations/decoded/{n}/thinking.txt) · '
                      f'[Raw provider response]({prefix}/provider-002-response.json) · [Normalized response]({prefix}/response.json)\n\n'
                      'This is the provider\'s `thinking` block under `display: "summarized"`, reproduced without abridgment. It is not an exhaustive private reasoning trace or a verified argument. In particular, language such as “testing” in this text does not establish that any program was run.\n')
        block('text', d['thinking.txt'])
        chunks.append(f'\n### Iteration {int(n)} — complete final answer\n\n'
                      f'The model returned one JSON-encoded string in `message.content`. [Exact string](evidence/fable-two-iterations/decoded/{n}/answer.txt); '
                      f'[parsed object]({prefix}/proposal.json). Its three string values are decoded in full below. This Python had not yet been run by the harness.\n\n**`idea`**\n')
        block('text', proposal['idea'])
        chunks.append('\n**`code`**\n')
        block('python', proposal['code'])
        chunks.append('\n**`notes`**\n')
        block('text', proposal['notes'])
        chunks.append('\n**Returned metadata and usage** (reported token counts are not a transcript of those tokens):\n')
        block('json', formatted({k:response[k] for k in ('model','seconds','usage')} |
                               dict(finish_reason=response['choices'][0]['finish_reason'])))
        chunks.append(f'\n### Iteration {int(n)} — what the harness did after the answer\n\n'
                      f'1. Parsed the three strings and wrote [`generator.py`]({prefix}/generator.py).\n'
                      f'2. Mounted the [baseline]({prefix}/generation/input/baseline.json), [helpers]({prefix}/generation/input/candidate_tools.py), '
                      f'[entrypoint]({prefix}/generation/input/container_entry.py), [seed]({prefix}/generation/input/randomness.json), and generator. '
                      'Ran this recorded command and got this process result:\n')
        block('json', (p / 'generation/process/request.json').read_text())
        block('json', (p / 'generation/process/result.json').read_text())
        chunks.append(f'\nThe [full stdout]({prefix}/generation/process/stdout.txt) is the expanded candidate; '
                      f'[stderr]({prefix}/generation/process/stderr.txt) is empty. The stored [candidate JSON]({prefix}/candidate.json) contains all 224 scheduled instructions. '
                      f'[Container metadata]({prefix}/generation/container.json) and [cleanup result]({prefix}/generation/cleanup/result.json) are also retained.\n\n'
                      '3. Simulated the candidate on five fixtures in the order below. Every trace is the machine execution for that input, not an LLM or Python trace.\n\n'
                      '| Fixture | Passed | Cycles | Full records |\n| --- | --- | ---: | --- |\n')
        for row in read(p / 'simulations.json'):
            f = row['fixture']
            chunks.append(f'| {f} | {str(row["passed"]).lower()} | {row["report"]["execution"]["cycles"]} | '
                          f'[input]({prefix}/simulation/{f}/input.json), [trace]({prefix}/simulation/{f}/trace.json), '
                          f'[command]({prefix}/simulation/{f}/process/request.json), [result]({prefix}/simulation/{f}/process/result.json) |\n')
        chunks.append(f'\n4. Ran the [compiled symbolic precheck]({prefix}/certification/precheck/request.json) '
                      f'([output]({prefix}/certification/precheck/stdout.txt)), emitted [the complete Lean certificate]({prefix}/certification/Certificate.lean), '
                      f'then ran [Lean]({prefix}/certification/kernel/request.json) ([output]({prefix}/certification/kernel/stdout.txt), '
                      f'[process result]({prefix}/certification/kernel/result.json)). The [certification result]({prefix}/certification/result.json) '
                      f'and [score]({prefix}/score.json) bind the exact candidate and certificate hashes.\n\n'
                      '5. Saved the following feedback. The timing field is removed before the next prompt; the original thinking block is not carried forward.\n')
        block('json', (p / 'feedback.json').read_text())
        if n == '0001':
            chunks.append('\nThe next user message below shows precisely how this feedback, the best code, and the notes were carried forward. There is no intervening model call in this harness.\n')
        else:
            chunks.append('\nThis ends the requested two-iteration window. The run continued; later iterations are outside this transcript.\n')
    return ''.join(chunks).rstrip() + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    if not args.check:
        export()
    provenance = read(OUT / 'provenance.json')
    for row in provenance['files']:
        data = (OUT / row['file']).read_bytes()
        require(sha(data) == row['sha256'] and len(data) == row['bytes'], f'Export changed: {row["file"]}')
        source = ROOT / row['source']
        if source.exists():
            require(data == source.read_bytes(), f'Original/export mismatch: {source}')
    for n in ATTEMPTS:
        original = RUN / 'attempts' / n
        if original.exists():
            originals = {str(p.relative_to(original)) for p in original.rglob('*') if p.is_file()}
            exported = {str(p.relative_to(OUT / 'attempts' / n))
                        for p in (OUT / 'attempts' / n).rglob('*') if p.is_file()}
            require(originals == exported, f'Incomplete attempt export: {n}')
    all_decoded = {n:decoded(n) for n in ATTEMPTS}
    for n, texts in all_decoded.items():
        for name, value in texts.items():
            path = OUT / 'decoded' / n / name
            if args.check:
                require(path.read_text() == value, f'Decoded text changed: {path}')
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(value)
    for name in ('generator.py', 'candidate.json', 'certification/Certificate.lean'):
        require((OUT / 'attempts/0001' / name).read_bytes() == (OUT / 'attempts/0002' / name).read_bytes(), f'Iterations differ: {name}')
    first = read(OUT / 'attempts/0001/feedback.json')
    second_prompt = json.loads(all_decoded['0002']['user.txt'])
    require(json.loads(second_prompt['latest']['feedback']) == {k:v for k,v in first.items() if k != 'seconds'}, 'Feedback carry-forward mismatch')
    require(second_prompt['notebook'] == read(OUT / 'attempts/0001/proposal.json')['notes'], 'Notebook mismatch')
    # A separate real Lean invocation produced this new explanatory proof record.
    # Checking its hashes here is not itself another kernel verification.
    recheck = OUT / 'recheck'
    result = read(recheck / 'result.json')
    require(result['exitCode'] == 0, 'Explanatory theorem did not check')
    for name, field in [('FableContract.lean', 'sourceSha256'), ('stdout.txt', 'stdoutSha256'), ('stderr.txt', 'stderrSha256')]:
        require(sha((recheck / name).read_bytes()) == result[field], f'Changed recheck record: {name}')
    contract = (recheck / 'FableContract.lean').read_text()
    require(contract.startswith((OUT / 'attempts/0001/certification/Certificate.lean').read_text()), 'Original certificate not preserved in recheck')
    namespace = read(OUT / 'attempts/0001/certification/result.json')['certificateDeclaration'].removesuffix('.artifact')
    audit = runpy.run_path(str(ROOT / 'scripts/certify.py'))
    output = (recheck / 'stdout.txt').read_text()
    require(audit['audit_kernel_output'](output, namespace), 'Certificate axiom audit failed')
    axioms = re.search(r"'FableExplanation.all_inputs' depends on axioms:\s*\[([^]]*)\]", output)
    require(axioms is not None and set(re.sub(r'\s+', '', axioms[1]).split(',')) <= audit['ALLOWED_AXIOMS'], 'All-input theorem axiom audit failed')
    text = GUIDE.read_text()
    require(text.count(MARKER) == 1, 'Missing/duplicate transcript marker')
    expected = text.split(MARKER)[0] + MARKER + render(all_decoded)
    if args.check:
        require(text == expected, 'Transcript needs rebuilding')
    else:
        GUIDE.write_text(expected)
    prose = re.sub(r'^```[^\n]*\n.*?^```[ \t]*$', '', expected, flags=re.M | re.S)
    for link in re.findall(r'\[[^\]\n]*\]\(([^)\n]+)\)', prose):
        url = urlsplit(link)
        if not url.scheme:
            target = GUIDE.parent / unquote(url.path) if url.path else GUIDE
            require(target.exists(), f'Missing link: {link}')
            if url.fragment:
                require(f'<a id="{url.fragment}"></a>' in target.read_text(), f'Missing anchor: {link}')
    print(f'Checked {len(provenance["files"])} original files, 12 decoded files, both complete transcripts, provider thinking mode, code/candidate/certificate identity, feedback carry-forward, and saved Lean recheck records.')


if __name__ == '__main__':
    main()
