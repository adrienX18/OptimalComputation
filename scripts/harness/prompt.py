"""Fresh prompts with bounded memory; the full archive never enters the prompt."""
import json
from pathlib import Path

from .evaluate import TASKS, STARTER

RULES = '''Optimize a finite candidate for the fixed arty-model-v1 machine.
Return ONLY a JSON object with strings: idea, code, notes. code defines build()
returning candidate-v1 JSON. notes replaces your short notebook for the next attempt.
Use Python's standard library and candidate_tools. No external packages or tools.
Generator loops expand a static schedule; the machine itself has no runtime branches.
You may change algorithm, layout, registers, schedule, and (only for energy) configuration.
Keep the workload and model fixed. Only a kernel-certified candidate can be best.
Hardware: lanes/banks independently 1,2,4,8; 4096 address slots (0..4095).
Bank = address % banks, at most 2 memory accesses/bank/cycle. Same-address
simultaneous accesses must both be reads. Inputs, outputs, scratch are disjoint
unique address lists. Inputs are read-only. Only inputs and r0 start initialized.
Each lane has r0=0 and writable r1..r15, one instruction issued per cycle,
at most 3 pending instructions, and at most one register writeback per cycle.
Loads/stores take 1 cycle; add/multiply/multiplyAdd take 3. Commit before issue.
A pending destination cannot be read or overwritten. Stores capture their source
at issue. Communication between lanes uses explicit stores/loads.
Signed16 multiplicands [-32768,32767], signed48 addition/accumulation/results.
Overflow is invalid, never wrapping. All stores must finish. A certification
limit means inconclusive, not necessarily wrong. The next attempt may repair your
latest failure or explore a different design. All times in feedback are modeled cycles
unless explicitly labeled seconds. Avoid repeating an unsuccessful idea unchanged.
'''


def clip(value, limit):
    return str(value).encode('utf-8')[:limit].decode('utf-8', errors='ignore')


def build(config, baseline, rows, root):
    best = min([r for r in rows if r['accepted']], key=lambda r: r['score'], default=None)
    best_code = (Path(root) / best['directory'] / 'generator.py').read_text() if best else STARTER
    latest = rows[-1] if rows else None
    last_code = ''
    notes = ''
    if latest:
        where = Path(root) / latest['directory']
        if (where / 'generator.py').exists():
            last_code = (where / 'generator.py').read_text()
    for row in reversed(rows):
        proposal = Path(root) / row['directory'] / 'proposal.json'
        if proposal.exists():
            notes = clip(json.loads(proposal.read_text()).get('notes', ''), config['notes_bytes'])
            break
    # Keep the baseline incumbent when every completed proposal is worse.
    if best is None or best['score'] >= baseline['score']:
        best_code, best_score = STARTER, baseline['score']
    else:
        best_score = best['score']
    raw = baseline['raw']
    context = dict(task=TASKS[config['task']][2], objective=config['objective'],
                   configuration=config['configuration'], attempt=len(rows)+1, limit=config['attempts'],
                   codeByteLimit=config['code_bytes'], notebookByteLimit=config['notes_bytes'],
                   baseline=dict(score=baseline['score'], unit=baseline['unit'],
                                 layout=raw['layout'], scheduleSize=len(raw['schedule']),
                                 firstInstructions=raw['schedule'][:5], lastInstructions=raw['schedule'][-2:]),
                   best=dict(score=best_score, code=best_code),
                   latest=dict(code=last_code if last_code != best_code else '(same as best)',
                               feedback=clip(json.dumps(latest, ensure_ascii=False), 3000)) if latest else None,
                   notebook=notes,
                   history=[dict(attempt=r['attempt'], idea=clip(r.get('idea', ''), 100),
                                 status=r['category'], score=r.get('score')) for r in rows])
    system = RULES + '\nAvailable candidate_tools.py:\n' + Path(__file__).with_name('candidate_tools.py').read_text()
    def messages():
        return [dict(role='system', content=system),
                dict(role='user', content=json.dumps(context, ensure_ascii=False))]
    def size():
        return len(json.dumps(messages(), ensure_ascii=False).encode('utf-8'))
    while size() > config['prompt_bytes'] and context['history']:
        context['history'].pop(0)
    if size() > config['prompt_bytes']:
        context['notebook'] = ''
    if size() > config['prompt_bytes']:
        raise ValueError('Complete current/best code cannot fit prompt_bytes; increase the budget or reduce code_bytes.')
    return messages()
