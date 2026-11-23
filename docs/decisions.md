# Recorded decisions

These decisions were confirmed on 2026-11-22. The certification approach, range
analysis, reference-polynomial proofs and experimental focus remain open in
[questions.md](../questions.md).

## Proof evaluation: preserve the current trust boundary

Keep accepted proofs checked by Lean's kernel, with only `propext`,
`Quot.sound` and `Classical.choice` allowed by the existing axiom audits.
The current ban on `native_decide`, unfinished proofs and custom axioms remains.
Compiled simulation and measurement remain useful evidence about concrete
inputs; they do not provide all-input certificates.

This decision does not choose an automatic checker or require its implementation.
If one is chosen later, benchmark a kernel-friendly implementation on
`matvec-grid-exchange-v1` before considering any change to the proof standard.
The existing runner's list sorting and 4,096-slot vectors may be expensive to
reduce in the kernel, so its compiled speed is not a prediction of proof speed.

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
