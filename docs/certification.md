# Automatic certification

The certifier takes one candidate and either accepts it with an all-input Lean
certificate or rejects it with an explanation. It does not search for a better
program, repair a schedule, choose an objective or change the machine model.
The design choices and deferred alternatives are in [decisions.md](decisions.md).

## Run it

From the repository root, with the pinned toolchain and Python 3:

```sh
lake build
python3 scripts/certify.py docs/candidates/matvec-grid-exchange-v1.json \
  --output /tmp/GridCertificate.lean --json
```

The saved [79-cycle candidate](candidates/matvec-grid-exchange-v1.json) has a
[reproducible certificate](certificates/matvec-grid-exchange-v1.lean). Its 624
instructions use eight lanes, eight banks and scratch-memory exchange. An
initial local measurement took approximately 28 seconds for kernel checking;
this is host time, entirely separate from the modeled 79 execution cycles.
The polynomial hand reference also passes kernel checking: its Estrin-style
program takes 63 modeled cycles and initially took about four seconds to certify.
These timings are examples, not performance guarantees.

Default limits are 1,000,000 boundaries, 4,096 terms per intermediate polynomial,
maximum monomial degree 64, 8 MiB of candidate text and 120 seconds per checking
phase. `--boundaries`, `--terms` and `--timeout` override the first, second and
last. Multiplication checks the size of the term cross product before expanding
it, even when later cancellation could reduce the result. Degree is checked
when constructing each value. A higher budget cannot make an invalid proof pass.

Success exits with code 0 and prints `Correct`. JSON contains `accepted: true`,
`status: "correct"`, the candidate/workload/model versions, budgets, modeled
cycles, proof-check time, hashes and the artifact's Lean declaration name.
`--output` saves the source after successful kernel checking and axiom audit.
The destination directory must exist. An existing destination is atomically
replaced on success; failure leaves it untouched. Re-run the command after
changing the candidate. The input is read once into a private snapshot, so a
concurrent edit cannot change which bytes the report describes.

Failure exits with code 1 and prints `Not certified`, an error category and a
message. JSON sets `accepted: false` and includes structured details. Output mismatches include the first differing
term as a coefficient and input-scalar indices. Invalid
command-line syntax uses argparse's exit code 2.

| Category | Meaning |
| --- | --- |
| `invalid-candidate-file`, `invalid-candidate` | Bad JSON, duplicate keys, versions, configuration, layout or instruction |
| `unknown-workload` | No trusted reference proof registered for this workload |
| `machine-rule` | First machine violation, including cycle, lane and violated rule |
| `missing-output` | Required output address was never written |
| `output-not-proved` | An output polynomial differs from the proved reference polynomial |
| `range-not-proved` | Derived interval does not fit the required operand/result width |
| `expression-budget`, `degree-budget`, `boundary-budget` | Analysis limit reached |
| `checker-timeout`, `kernel-timeout`, `kernel-check` | Checking did not complete successfully |

Admission is binary; its explanation matters. A conservative interval or a
timeout is not evidence of a wrong answer. Polynomial equality is sufficient
for correctness, but two different polynomials can coincide on a restricted
finite domain. Use `simulate` with an allowed input to obtain an actual
counterexample. Neither sampled success nor a caller-supplied JSON status can
produce a certificate.

## What gets proved

For every allowed input, acceptance proves successful termination of the exact
candidate on the existing `Hardware.step` / `Evaluation.executeValues`
semantics and equality of its outputs to the existing mathematical reference.
This includes initialization, completion-before-issue ordering, pending
capacity, register readiness, writeback reservation, bank/address conflicts,
16-bit multiplicands, 48-bit results and all output stores completing.

The symbolic runner carries integer polynomials and proved interval bounds in
place of individual input values. Each symbolic transition is proved to match
the original machine transition for every input in the box. The original
machine's batch-rule checker is reused. The symbolic sorter is proved equal to
the existing stable sort, including its handling of equal keys. Neither the
machine, storage format nor objective functions were changed.

A workload's `Problem` supplies its input box and output polynomials, with proofs
connecting them to its original `ScalarAdapter` and reference. The catalog
covers scalar multiplication, product pair, matrix-vector, matrix-matrix,
degree-seven polynomial evaluation, Gram product and two-stage linear map.
Only workload identifiers select a reference. Candidate names do not select
proofs, and the file supplies neither the reference nor the input domain.

The normalizer combines like terms, drops zero coefficients, sorts variables
inside products and expands multiplication. Bounds are computed after
normalization, so exact cancellation is recognized. Repeated variables use
square bounds with nonnegative lower bounds. This proves the current polynomial
and two-stage bounds without interval splitting or an external solver.

## Reusable interfaces

Import `OptimalComputation.Certification.Catalog` in Lean.

| Component | Responsibility |
| --- | --- |
| `Polynomial`, `Interval`, `Value` | Algebra and bounded arithmetic, with soundness lemmas |
| `State`, `prepare`, `step`, `run` | Symbolic state and refinement to existing machine execution |
| `Problem adapter` | One-time connection from a workload to symbolic inputs/outputs |
| `check problem candidate boundaries maxTerms` | Pure `Except Diagnostic Nat`; success returns modeled cycles |
| `check_sound` | All-input successful execution and reference equality from a successful check |
| `certificate` | Convert that premise into the existing `VerifiedCandidate` |
| `Entry.artifact` | Package the certificate as the existing `VerifiedArtifact` |

The Python driver uses a compiled precheck to obtain diagnostics quickly. The
internal `certification_check` executable returns `requires-kernel-check` on
success and **never grants acceptance**. It emits a closed Lean proposition:

```lean
(check entry.problem candidate boundaries maxTerms).toOption = some cycles
```

The generated source proves it with kernel evaluation, constructs the artifact,
and proves `artifact.verified.candidate.toRaw = raw`. That equality covers every
serialized field, including the original instruction order. The driver audits
all three roots; only `propext`, `Quot.sound` and `Classical.choice` are allowed.
Python and the source emitter organize the work; their outputs cannot replace
the proof obligation. The file hash identifies the input bytes, not a theorem.

Generated namespaces depend on the source content, allowing distinct artifacts
to be imported together. Put a saved source in a Lean module and import it. Its
reported `certificateDeclaration` is an ordinary `VerifiedArtifact`, usable in
`Evaluation.evaluateObjective [artifact] raw values budget inputId objective`.
That API checks exact candidate binding and computes the original execution
record before scoring it. `Tests.Certification.checkedTiny` exercises this path.
The main CLI's existing 71-entry candidate catalog remains unchanged; saving a
certificate does not dynamically install it into that executable.

To add a workload, provide a `Problem` with `input_sound` and `output_sound`, then
add its `Entry` to `Catalog.entries`. To add a candidate for an existing workload,
submit its JSON; no catalog entry or candidate-specific proof is needed.

## Limits and validation

The checker proves sufficient conditions, not completeness. Intervals can lose
correlations across different terms. Expansion and closed kernel evaluation can
be costly for large programs; a compiled precheck passing does not guarantee
that kernel evaluation finishes within its budget. Richer range reasoning,
shared expression representations and compact proof traces are future options.
There is no new trust assumption or native proof evaluation. The optional
[search harness](search.md) reuses this checker without changing its proof standard.

`python3 scripts/check-certification.py` checks the 79-cycle kernel certificate,
its exact saved source, a renamed/reordered candidate, a polynomial certificate,
tampered proof claims, single-instruction mutants, duplicate keys, budgets and
Horner range failures. It also runs compiled prechecks for all 12 hand references.
`lake test` checks all 71 existing artifacts against the new checker, alongside
arithmetic, ordering and diagnostic regressions. The 20-root certification axiom
audit is included in `python3 scripts/validate.py`.

The old Section 9 proposal ledger remains historical. New search runs can
use these blocks, but must distinguish actual counterexamples, inconclusive
certification and accepted proofs rather than relabel all rejections as bugs.

## Retained diagnostics and fresh accepted scores

The optional `--archive` names a new directory. It retains the input snapshot,
generated source, full precheck and kernel stdout/stderr, commands, limits,
process results and final report, including on failure. A saved source becomes
a certificate only when the final report accepts it.

The optional `--objective` invokes the existing `evaluateObjective` API on the
new proof-bearing artifact. `--fixture` selects the measurement input; use
`mixed-signs` for toy workloads or the default `generated-23` for larger ones:

```sh
python3 scripts/certify.py /tmp/candidate.json --archive /tmp/certificate-run \
  --objective latency-v1 --fixture generated-23 --json
```

The accepted JSON then includes the complete score and execution record.
`Certification.Scoring.printScore` is a thin Lean adapter, covered by the axiom
audit. Python never substitutes a performance formula. The original invocation
without an objective still produces the same certificate source byte for byte.
