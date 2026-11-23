# Recorded decisions

These decisions were confirmed on 2026-11-22. All seven questions from the
Section 9 discussion are resolved. Implementation details and commands are in
[certification.md](certification.md). The subsequently approved minimal search
loop is recorded below and described in [search.md](search.md).

## Proof evaluation: preserve the current trust boundary

Keep accepted proofs checked by Lean's kernel, with only `propext`,
`Quot.sound` and `Classical.choice` allowed by the existing axiom audits.
The current ban on `native_decide`, unfinished proofs and custom axioms remains.
Compiled simulation and measurement remain useful evidence about concrete
inputs; they do not provide all-input certificates.

The automatic checker described below preserves this standard. Its sparse
symbolic state and structurally recursive sorting avoid reducing the concrete
runner's 4,096-slot vectors or general-purpose sorting proofs. The new sort is
proved equal to the existing sort. The exact `matvec-grid-exchange-v1` candidate
has now passed kernel checking; compiled speed is still not proof speed.

Potential alternatives for later:

- Generate compact evidence with fast code and verify that evidence in the
  kernel. This could improve speed without trusting the evidence generator,
  but requires a suitable certificate format and sound verifier.
- Use proof-producing evaluation or generated proofs, measuring their size and
  checking cost before adopting them.
- Permit native evaluation only after an explicit future decision. It can run
  faster but expands the trusted machinery to include compiled evaluation and
  changes what the current audits accept. It is not enabled by this decision.

## Diagnostics: fixed order, one failure at a time

Keep one clear failure per call. The static schedule checker visits boundaries
in increasing cycle order and passes actions to the existing hardware batch
checker in increasing lane order. At a boundary, its priority is:

1. Lane issue collisions, choosing the lowest conflicting lane.
2. Bank capacity violations, choosing the lowest conflicting bank.
3. Address conflicts, choosing the first conflicting store in lane order.

Thus permuting a structurally valid schedule does not change the first static
conflict reported. Sorting changes diagnostics only: the soundness proof still
establishes the original, order-independent `StaticScheduleLegal` predicate.
The candidate's stored instruction order and its exact certificate binding are
preserved. Structural decoding still identifies malformed entries by their
original file index; it must succeed before static checking can start.

Simulation retains its existing execution order: increasing boundaries,
completion before issue, and canonical lane order for simultaneous actions.
It stops at the first execution violation. The static pass and execution check
different obligations and need not diagnose the same failure first.

Potential alternatives for later:

- Return a bounded collection of independent structural/static errors to reduce
  repair iterations. Specify ordering and truncation so results stay reproducible.
- Separate independent errors from consequences of earlier failures. Continuing
  a failed execution without this distinction could produce misleading messages.
- Add an explicit diagnostic mode rather than changing the normal first-failure
  API or continuing an invalid machine execution.

## Candidate JSON: reject duplicate object keys

Candidate files must contain unique keys within every object, including nested
configuration, layout, schedule-entry and instruction objects. Even duplicates
with identical values are rejected as `invalid-candidate-file`; neither the
first nor the last value wins.

Keys are compared after JSON escape decoding, so `"lanes"` and
`"\u006canes"` are duplicates. The same field name in separate objects is legal.
Diagnostic key names use the existing bounded, escaped quoting so file contents
cannot inject lines or terminal controls into an error message.

`Candidates.UniqueJson.parse` checks keys before constructing each object map.
The CLI applies its existing nesting and numeric limits before using this
parser, then runs the existing exact-field decoder. `RawCandidate.fromJson?`
accepts an already constructed JSON value; it cannot recover duplicates erased
by a different text parser. External callers processing candidate text must use
the strict text path as well.

This tightens ambiguous file handling without changing the candidate schema,
machine rules, scoring rules or any existing exported candidate.

## Automatic certification: option A, a checker proved sound once

Implement one reusable symbolic checker whose success implies execution safety
and reference equality for every allowed input. It accepts arbitrary candidate
identifiers, layouts, schedules and admissible configurations. Each candidate
still needs a kernel-checked evaluation of that checker, but no new hand-written
proof about its individual instructions.

The result is binary for admission: accepted or rejected with a reason. Only an
accepted kernel certificate prints `Correct`. Rejections print `Not certified`
and explain the first failure. A range overestimate, unmatched polynomial or
exhausted budget is not itself a counterexample; calling these programs
mathematically incorrect would be misleading. Concrete simulation remains the
way to exhibit a failing input. JSON separates the admission flag, category,
message and relevant cycle/lane/range details.

The benefit is reusable verification across scheduling and algebraic changes.
The cost is the initial soundness proof and potentially expensive closed kernel
evaluation. This checker is sound, not complete: some correct programs can be
rejected. Tactic-generated boundary proofs and agent-written proofs remain
possible future alternatives, not prerequisites for ordinary candidates.

## Range analysis: start with intervals and small targeted improvements

Use integer intervals, normalized sparse polynomials, cancellation of equal
terms, and nonnegative bounds for squares. Check 16-bit multiplicands and
48-bit results at every instruction. This handles the current input domains,
the two-stage intermediate bound, and the polynomial power/Estrin schedules.
The illegal Horner schedules fail the multiplicand check.

This keeps the proof and failure messages small. It can lose dependencies
between different terms, so an interval outside the legal range means the
checker cannot establish safety. Cap polynomial terms, monomial degree,
boundaries and process time; hitting a cap is an inconclusive rejection.

Defer interval splitting, exhaustive reasoning over small domains, richer
relational range analysis, and externally generated range certificates until a
useful correct candidate requires them. No SMT solver or new trusted arithmetic
oracle is needed now.

## Workload references: prove the polynomial connection once

Each workload supplies a `Problem`: an input box that contains its allowed
domain, expected output polynomials, and proofs connecting both to its existing
scalar adapter and mathematical reference. All seven current workloads have
these proofs. The candidate file cannot replace the domain or the reference.

Canonical algebra recognizes rearrangement, multiplication commutativity,
factoring/expansion and Gram symmetry without special cases for candidate
names. Adding a workload requires its one-time reference proof; changing a
schedule does not. Equality is checked over integer polynomials, which can be
stricter than equality only on a restricted finite domain.

## Experiment focus: goal A, safe optimization

Measure how much a candidate improves latency or abstract energy while
remaining safe and correct. The optimizer will propose programs; the reusable
checker will certify them. Agent proof-writing skill is not the target metric.

Preserve the distinction between candidates refuted by an actual input and
candidates left uncertified by analysis or resource limits. Record certification
cost and failure categories separately from execution cost. A timeout must not
be counted as a discovered correctness bug. Keep the original Section 9 run
as historical evidence rather than relabeling its old deferred proposals.

That change delivered modular certification, reference and reporting blocks.
The subsequent search harness leaves those objectives and the historical
experiment unchanged. None of these results claim physical hardware performance.

## Minimal search loop: sequential proposals and bounded memory

The approved first optimizer is deliberately a single loop: ask one model for
one design, generate it, simulate it, certify it, report the result, repeat.
Use at most 100 attempt slots. There is no agent framework, parallel population,
planner, learned selection policy, automatic provider fallback or model tool use.
LiteLLM is an optional local SDK dependency for selecting the provider/model;
configuration uses JSON, which Python can read without another dependency.

Local API keys can live in a Git-ignored root `.env` file. The live adapter loads
it through `python-dotenv` (already a LiteLLM dependency, now explicitly pinned).
Existing environment values take precedence; interpolation is disabled. The
file is excluded from snapshots and containers, and loaded keys are redacted
from provider logs. This lets either the user or Codex launch experiments
without repeating shell exports or copying credentials into the conversation.

The model returns a small Python generator rather than thousands of literal
instructions. This allows algorithm, layout and schedule changes while keeping
the prompt small. The generator runs as a restricted non-root Docker process
with no network, credentials or writable host mount. Docker is the extra runtime
dependency this decision introduces. The Lean checker and scorer run separately
on the host; generated Python never runs there.

Every request starts fresh with the best certified generator, latest generator
and bounded feedback, a compact attempt history, and a bounded model-written
notebook. Drop the oldest history entries if necessary. Retain the last notebook
through malformed responses. This is cheap and transparent, but can forget old
details or preserve a mistaken note. The notebook is advice, never evidence of
correctness. The complete archive remains available for later analysis.

Keep the original certified baseline as the incumbent. Only a strictly lower
certified score replaces it. Latency fixes the lane/bank configuration; energy
allows changing it. Fixture results alone cannot win, and inconclusive proofs
remain distinct from concrete counterexamples. Fresh certificates are scored by
the existing Lean `evaluateObjective` API, without a Python score formula.

Save before calling the model, record every attempt including malformed replies
and failures, and retain all provider-exposed response data and verifier output.
Credentials are redacted; private provider reasoning that is not returned cannot
be recorded. Plain files, JSONL events and a CSV summary suffice. Storage can be
large because traces and proofs are retained. This favors analysis over disk use.

No automatic API retries: errors consume slots, and three consecutive API errors
stop the run for explicit resume. Interrupted slots also consume their number;
resume never reissues a possibly billed request. Resume requires the same source,
Python, recorded adapter dependencies and Docker image. This is conservative but
keeps one run comparable. Provider inference itself need not be deterministic.

Deferred alternatives include richer retrieval of old attempts, deduplication,
parallel search, automatic repairs, a run database, full environment locking and
measured hardware objectives. These can be evaluated against this simple loop.

## Response budget after the live pilot

On 2026-11-23, increase the common output limit to 32,768 tokens and the request
timeout to 600 seconds for new runs. Opus used its entire 16,384-token pilot
budget for reasoning in one attempt, leaving no returned design. The larger
budget gives reasoning and the final answer more room; it permits higher cost
and longer calls, and does not guarantee that every response will finish.
Keep the prompt, notebook and generator size limits independent and unchanged.
Explicit per-run settings still override these defaults. Preserve completed
pilot configurations and records, and provide fresh Opus/Astra configurations
for the next experiment.
