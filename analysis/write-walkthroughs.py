#!/usr/bin/env python3
"""Render report sections from the tracked, frozen model exchanges."""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
START = '<!-- BEGIN GENERATED WALKTHROUGH -->'
END = '<!-- END GENERATED WALKTHROUGH -->'


def read(p):
    return json.loads(p.read_text())


def code(value, language='text'):
    # Four backticks avoid treating a model's triple backticks as our delimiter.
    assert '````' not in value
    return f'````{language}\n{value}\n````\n'


def details(title, content):
    return f'<details>\n<summary>{title}</summary>\n\n{content}\n</details>\n\n'


def section(folder, smoke):
    w = folder/'walkthrough'
    request=read(w/'winner/request.json')
    context=json.loads(request['messages'][1]['content'])
    response=read(w/'winner/response.json')
    proposal=read(w/'winner/proposal.json')
    feedback=read(w/'winner/feedback.json')
    stats=read(w/'architecture.json')
    if smoke:
        chosen='Astra 6.2, Gram latency (8 lanes, 8 banks), seed 11, attempt 3'
        intro='''For this walkthrough, **Astra is the representative suite winner by the number
of case-wise first places**, counting ties: Astra 11, Sol 9, Fable 4, Opus 1,
Sonnet 0. These counts sum above 16 because ties count for each model. This is an
explicit descriptive selection rule for these saved runs, **not evidence that
Astra is generally the best model**. It also ignores the size of each margin.
We do not average energy and latency scores.

The figure shows **all 16 Astra trajectories**, with the original baseline at
slot zero. For the architecture example, we choose **Gram latency (8,8)** because
its symmetry and work distribution can be visualized clearly; it is not the
largest improvement ratio. That exact run improved **22,016 → 556 → 508 → 478
cycles**, and 478 was the best among all five models on that case.

![Astra's best-so-far score versus attempt count for every smoke case.](figures/04_winner_progress.png)

*Figure 4. Every panel compares against its own baseline, with independent log
axes and explicit units. One seed per case means no repeat-based confidence
interval can be estimated. This is a post-selection description of the archive.*
'''
        architecture='''The baseline computes all 256 ordered row-pair dot products, one after another
on lane 0, including both `G[i,j]` and `G[j,i]`. It uses scratch memory and later
copies results to the output region.

The winning program uses **symmetry**: there are only `16×17/2 = 136` distinct
dot products, including the diagonal. It assigns **17 per lane**, accumulates
each across the 16 input columns, and writes an off-diagonal result to both
output positions. Loaded row values serve multiple accumulators. Its generator
searches periodic load/multiply-add schedules and uses spare registers to keep
selected operands alive longer. This happens while constructing the design;
the resulting machine schedule is fixed and has no runtime search or branches.

The output map below is decoded from the actual stores: matching colors across
the diagonal show that a single lane writes both symmetric entries. The baseline
and winner use exactly the same eight lanes and eight banks. The winner has no
scratch allocation. All 256 outputs remain present and were certified.

![Baseline and Astra Gram algorithms, exact output-to-lane maps and issue schedules.](figures/05_winner_architecture.png)

*Figure 5. Boxes are explanatory summaries; output maps and issue grids come
from the saved candidate instructions. The issue grids have different time
scales. Dense baseline events are an overview; the linked JSON retains every
cycle. These are fixed artifact properties, so they receive no confidence interval.*
'''
    else:
        chosen='Sol 6.2, polynomial latency (8 lanes, 8 banks), seed 11, attempt 2'
        intro='''There is **no unique winner in final quality**: Fable, Opus, Astra and Sol all
reach 30 cycles in all five repeats. To pick one concrete example, we break that
tie by the **median attempt first reaching the final best**: Sol 1, Fable 2,
Astra 2, Opus 10. We therefore illustrate **Sol**, using the smallest fixed seed,
11. Its retained best first appeared at **attempt 2**: **1,520 → 35 → 30 cycles**.
This is an explicitly post-hoc selection rule, not a claim of statistical superiority.

![All five Sol trajectories against the baseline, with an early-attempt zoom.](figures/11_winner_progress.png)

*Figure 11. The full budget and the first five slots are shown. All five observed
trajectories are plotted, with coincident values overlapping; the dashed line is
their median. We do not attach an inferential interval to a model selected after
seeing the results. Figures 2–4 retain the original per-model uncertainty analysis.*
'''
        architecture='''The baseline computes powers of each point, writes intermediate values to
scratch memory, reloads values and coefficients, and accumulates the polynomial.
It completes one point after another on **lane 0**, leaving seven provisioned
lanes unused.

The Sol winner assigns points `l` and `l+8` to lane `l`. Each lane loads the eight
coefficients once and reuses them for both points. For each point it computes:

```text
q = c7
for k = 6, 5, 4, 3, 2: q = q*x + c[k]
s = x*x
t = c1*x + c0
y = q*s + t
```

This is the original degree-seven polynomial, factored into an upper quintic
and a linear tail. Splitting the computation keeps the values fed into the
machine's signed16 multiplier small enough; the final result can use signed48.
The two evaluations overlap on each lane, while coefficient loads and the
point/output memory layout are scheduled to respect bank limits. The generator
searches candidate schedules locally, but its **output is one static schedule**.

![Sol polynomial dataflow and instruction schedule compared with the naive baseline.](figures/12_winner_architecture.png)

*Figure 12. The dataflow boxes summarize the inspected code and algebra. The
colored grids are the actual saved issue events, using explicitly different time
scales. A colored cell denotes issue, not the instruction's execution duration.
All counts describe fixed artifacts and receive no confidence interval.*

The model's notes discuss a 29-cycle target. **The measured, certified result is
30**, and the report does not endorse the model's lower-bound arguments.
'''
    text='## Inside the loop: actual inputs, outputs and a winning design\n\n'+intro
    text+='\n### What the LLM actually sees and returns\n\n'
    text+=f'**Saved example: {chosen}.** No prompt was reconstructed with today’s code.\n\n'
    text+='''Each attempt sends two messages: a **system message** with machine rules,
output requirements and the complete `candidate_tools` helper source; and a
**user message** containing the task, objective, configuration, seeds, budget,
baseline summary, best code, latest feedback, compact history and short notebook.
The baseline summary contains its layout, instruction count and a few leading
and trailing instructions, not its entire schedule. The generated program can
read the full baseline through `candidate_tools.baseline()`.

The LLM returns **one JSON object with three strings**: `idea`, Python `code`
defining `build()`, and `notes` for the next attempt. The harness executes the
Python in its generator environment to obtain a `candidate-v1` artifact: memory
layout, configuration and static instructions with cycle/lane/register choices.
Simulations, certification and scoring happen afterward. Only a certified
improvement replaces the incumbent.

The archive is richer than the next prompt. Each call starts with a fresh
two-message request, not the entire conversation. It retains best/latest code,
short history rows and a notebook capped at 2,000 bytes. Old history rows can be
dropped to fit the prompt cap; timing fields are removed from feedback before
it is sent back. The saved request below shows exactly what survived these rules.
'''
    previous=json.loads(context['latest']['feedback'])
    text+=f'''
In this example, the prompt is **{stats['prompt_bytes']:,} bytes** (serialized
message array), contains **{len(context['history'])} earlier history row(s)**,
and shows the previous certified score **{previous['score']:,} cycles**.
The returned code is **{stats['output_code_bytes']:,} bytes**. The limits were
{('48,000' if smoke else '32,000')} prompt bytes, 8,000 code bytes and 32,768 output tokens;
these are different budgets, not interchangeable units.

**Exact previous feedback as shown to the model** (the stored JSON string decoded):

'''+code(json.dumps(previous,indent=2,ensure_ascii=False),'json')
    text+='\n**Exact returned `idea` string:**\n\n'+code(proposal['idea'])
    text+='''
Expand the following blocks to see **all input message contents and all three
output strings**, with no omitted fields. JSON objects are pretty-printed for
reading; string values are unchanged. For exact serialization, use the
[saved request](walkthrough/winner/request.json),
[normalized response](walkthrough/winner/response.json), and
[raw provider request](walkthrough/winner/provider-001-request.json).
The provider request's message array was checked to equal the harness messages.

'''
    text+=details('Complete system message (verbatim string)',code(request['messages'][0]['content']))
    text+=details('Complete user message (JSON decoded; all values preserved)',code(json.dumps(context,indent=2,ensure_ascii=False),'json'))
    text+=details('Complete output: idea, code and notes (verbatim decoded strings)',
        '\n'.join('**'+key+'**\n\n'+code(proposal[key],'python' if key=='code' else 'text') for key in ('idea','code','notes')))
    text+='**Actual harness feedback after this attempt:**\n\n'+code(json.dumps(feedback,indent=2,ensure_ascii=False),'json')
    if smoke:
        text+='\nAttempt 3 was the last slot. Its feedback and notes were saved, but **no fourth prompt was sent**.\n'
    else:
        text+='''
The [actual next request](walkthrough/next-request.json) then carries score 30,
this code as the incumbent, and this proposal's notebook. It is available to
verify the return path from feedback to the next model call.
'''
    text+='\n### What the winning implementation looks like\n\n'+architecture
    b,s=stats['baseline'],stats['winner']
    text+='\n| Fixed artifact property | Original baseline | Selected winner |\n| --- | ---: | ---: |\n'
    for label,key in [('Modeled cycles','cycles'),('Issued instructions','instructions'),('Scratch slots','scratch_slots')]:
        text+=f'| {label} | {b[key]:,} | {s[key]:,} |\n'
    for label,key in [('Loads','load'),('Stores','store'),('Adds','add'),('Multiplies','multiply'),('Multiply-adds','multiplyAdd')]:
        text+=f"| {label} | {b['counts'].get(key,0):,} | {s['counts'].get(key,0):,} |\n"
    text+=f'''
That is **{b['cycles']/s['cycles']:.1f}× baseline/winner modeled latency** and
**{100*(1-s['instructions']/b['instructions']):.1f}% fewer issued instructions**.
Instruction count and elapsed cycles measure different things: parallel work,
dependencies and bank constraints determine how the instructions fit into time.

Inspect the [winning generator](walkthrough/winner/generator.py),
[full winning schedule](walkthrough/winner/candidate.json),
[winning score](walkthrough/winner/score.json),
[full baseline schedule](walkthrough/baseline/candidate.json), and
[baseline score](walkthrough/baseline/score.json). These links work from GitHub;
they point to tracked exports, not ignored local run paths. The retained
candidate identifier still contains `naive`; it was inherited from the baseline.
The changed instructions and their hash identify the winner.

### Evidence and reproduction of this section

The [export manifest](walkthrough/provenance.json) records each original archive
path, size and SHA-256. Every copied file was checked against the original
inventory. The [derived architecture data](walkthrough/architecture.json) check
instruction counts, completion time and output formulas by symbolic execution
of the saved schedules. Archived candidate/certificate hash bindings and the
successful kernel exit were also checked. This does not rerun Lean or substitute
for the archived range and machine-validity certificates.

From the repository root, regenerate both walkthrough exports with the local
archives present, then render the sections and figures from their tracked data:

```sh
python3 analysis/build-walkthroughs.py
python3 analysis/write-walkthroughs.py
/tmp/optimal-plots-venv/bin/python analysis/plot-walkthroughs.py
```

The latter two commands do not need API keys or the original archive. Plotting
uses the report's pinned plotting requirements. [Figure provenance](figures/walkthrough-provenance.json)
records input hashes, versions and label-bound checks. These commands make no
model calls, execute no generated Python and launch no experiment.
'''
    return text


def main():
    for name,smoke in [('2026-11-23-five-model-search',False),('2026-11-23-suite-smoke',True)]:
        folder=HERE/name
        report=folder/'report.md'
        text=report.read_text()
        block=START+'\n\n'+section(folder,smoke)+'\n'+END+'\n\n'
        if START in text:
            before,tail=text.split(START,1)
            _,after=tail.split(END,1)
            text=before+block+after.lstrip('\n')
        else:
            heading='## Data preservation and reproduction' if smoke else '## Files and reproduction'
            assert heading in text
            text=text.replace(heading,block+heading)
        report.write_text(text)
    print('Rendered complete archived input/output examples and architecture sections in both reports.')


if __name__=='__main__':
    main()
