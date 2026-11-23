# API reference

See [usage](usage.md) for the CLI and [extension guide](extensions.md) for new workloads, proofs and objectives.

## Contracts and source layout

Read the [machine contract](machine-contract.md) and
[assumptions table](assumptions.md) before changing semantics. Manufacturer
facts, modeling choices, and deferred physical details are explicitly separated.

`OptimalComputation/Versions.lean` owns the initial identifiers.
`OptimalComputation/Hardware/Board.lean` records reference-board resources;
`Hardware/Config.lean` defines the admissible family, fixed capacities, validation,
and bank mapping; `Hardware/Resources.lean` computes allocations. These modules
include Lean proofs of the exact family, bounded and non-aliasing mapping, integer
rounding, and DSP/BRAM resource bounds. `Hardware/Arithmetic.lean` and
`Hardware/Storage.lean` provide the numerical rules. `Workloads/Specification.lean`
is the pure extensible workload interface; `DotProduct.lean`, `Matrix.lean`,
`MatVec.lean`, and `MatMul.lean` define integer reference calculations and bounds.
`Hardware/Instruction.lean` defines the five generic instruction forms;
`Candidates/Layout.lean` and `Candidates/Program.lean` validate their finite
storage and schedules. `Examples/TinyMultiply.lean` is a structurally validated
two-load/multiply/store fixture that executes in six cycles.
`Hardware/Machine.lean` defines the shared pure transition;
`Evaluation/Execution.lean` initializes inputs, runs schedules, and derives records.
`Tests/` holds executable checks; `Main.lean` is the small command-line entry point.
Future modules will be added as
needed under `Hardware`, `Workloads`, `Candidates`, `Evaluation`, and `Examples`,
with regressions under `Tests`. Hardware modules must remain independent of matrix
workloads, objectives, and future search code. Empty module scaffolding is omitted.

## Hardware API

Import `OptimalComputation` and open `OptimalComputation.Hardware`. A raw `Config`
has only `lanes` and `banks`. `validateConfig` returns either a `ValidConfig` carrying
an admissibility proof or an error identifying the first unsupported field (lanes
before banks). `defaultConfig` is the validated `(8, 8)` configuration.
`resourceReport` accepts only a `ValidConfig`; it cannot give an invalid choice an
accepted allocation report.

| Banks | Slots per bank | BRAM36 blocks |
| --- | --- | --- |
| 1 | 4,096 | 8 |
| 2 | 2,048 | 8 |
| 4 | 1,024 | 8 |
| 8 | 512 | 16 |

Each choice has two general-purpose ports per bank and 32 KiB of logical memory.
DSP allocation is one per lane; writable architectural storage is 720 bits per
lane. The default report therefore has 8 DSPs, 16 BRAM36 blocks, 5,760 architectural
register bits, and 24 pending-instruction slots. Pending slots separately account
for result/store payload and destination metadata capacity. Control, connection,
pipeline, and total logic area are `none` (uncalibrated), not zero.

An `Address` is bounded to 4,096 slots. `mapAddress` returns bounded bank/row
coordinates using modulo/division, with a reconstruction and injectivity proof.
`bankAccessesFit` checks only the two-port capacity for simultaneous requests,
counting duplicate requests separately. Full access-kind, same-address, hazard,
and cycle legality are enforced by the shared execution semantics.

## Arithmetic and workload API

`InSigned16` is the inclusive range `[-32768, 32767]`; `InSigned48` is
`[-140737488355328, 140737488355327]`. `Signed16` and `Signed48` pair an `Int`
with its range proof. `checkedAdd a b`, `checkedMul a b`, and
`checkedMac a b accumulator` take integers, validate every operand and result,
and return `Except ArithmeticError Signed48`. Diagnostics distinguish operand
width failures from result overflow. Checks proceed left-to-right, then through
the accumulator when present, and finally the result. Values never wrap or saturate.

`Slot64` contains an actual `BitVec 64` with a canonicality proof. `encodeSlot`
and `decodeSlot` round-trip signed 48-bit values; `validateSlot` rejects arbitrary
raw bit patterns outside that representation. `canonical_iff_sign_extension`
proves that canonical bits equal their low 48 bits sign-extended to 64 bits.
Every memory transfer still consumes the full slot; there is no packing.

Under `OptimalComputation.Workloads`, a `Specification` holds an identifier,
input type, allowed-input predicate, output type, and pure reference function.
`MatVec.specification` is `matvec-16x16-signed16-v1`; `MatMul.specification` is
`matmul-16x16-signed16-v1`. Both take runtime integer entries with a decidable
signed 16-bit input predicate. Their references contain no physical addresses.
The logical input/output counts occupy 288 and 768 whole slots respectively:
2,304 and 6,144 bytes before scratch storage.

`dotPrefix a b count h` accumulates terms in increasing index order, with `h`
proving `count` fits the vectors. Its all-input theorem bounds each prefix by
`±(count * 1073741824)`. Every prefix of at most 16 terms therefore fits signed
48 bits, including the final reference outputs. `dotPrefix_checkedMac` exposes
the successful exact next-prefix arithmetic step for later baseline proofs.
These are arithmetic and reference proofs; candidates must still prove their
own intermediate bounds and machine execution safety.

## Candidate structure API

`Workloads.Shape` identifies a workload and its logical input/output scalar counts.
`MatVec.shape` and `MatMul.shape` use their specification identifiers and counts.
`validateCandidate expectedShape raw` checks the supplied identity and counts
against that expected shape. Hardware and candidate modules do not import a
matrix-workload registry. Adding a workload uses the same validator; the caller
supplies its trusted shape. Semantic verification additionally binds its
specification and scalar encoding, rather than trusting an identifier alone.

A `RawCandidate` has an identifier, model/format/workload identifiers, raw
configuration, layout, and a finite list of scheduled instructions. Every entry
has a natural-number cycle and lane, with explicit register/address operands.
`load`, `store`, `add`, `multiply`, and `multiplyAdd` are the only instructions.
There are no embedded functions, runtime loops or branches, initial register
values, constants hidden in scratch, or candidate-supplied event counts.

Validation returns a `Candidate expectedShape` with an admissible configuration,
bounded addresses, bounded lane-local registers, nonzero result destinations,
and a layout carrying count and non-aliasing proofs. Input/output list positions
are logical scalar indices; `inputAddress` and `outputAddress` provide injective
bounded mappings. Scratch is an explicit list of additional reserved slots.
Loads must name declared storage; stores must name outputs or scratch. Proofs
establish that a validated store cannot modify an input. The whole layout is
injective, so all three regions are also pairwise disjoint.

Validation preserves representation order. Cycles with no entry encode waiting;
the simulator uses issue cycles and handles simultaneous instructions
independently of their list order. Old-value source/destination aliasing and
source reads of `r0` are representable. Structured failures identify the invalid
header, configuration, layout region/index, or schedule index/cycle/lane and rule.
`toRaw` exports deterministic plain data; kernel-checked round-trip theorems cover
layouts, instructions, schedules, and complete candidates.

Structural validity is not execution safety or functional correctness. The tiny
fixture `tiny-multiply-v1` loads at cycles 0 and 1, multiplies at 2, stores at 5,
and finishes when that store commits at boundary 6. For inputs `[-7, 6]`, its output
is `[-42]`. It has two loads, one multiplication, one store, three register reads,
three register writes, and three bank accesses. `Examples.TinyMultiply.execution_correct`
proves this execution for every signed16 operand pair; `Examples.TinyMultiply.verified`
binds that proof to the scalar multiplication specification.

## Execution API

`Hardware.step boundary actions state` is the pure transition used by the runner
and available to proofs. It commits all effects due at the boundary, checks the
whole issue batch, samples every instruction against the resulting state, then
enqueues captured payloads. Simultaneous actions are ordered by lane for stable
traces and error selection. Duplicate lane issues fail before per-instruction
inspection. Conflicts fail without adding stalls. Memory requests consume ports
at issue; committing an earlier request does not consume another port.

`State` contains fixed-size register/memory vectors and per-lane pending lists.
Successful reservations limit each pending list to three effects, including store
payloads. Read/write and pending-update lemmas expose ordinary vector reductions
for later proofs. Only the high-level executor initializes candidate runs: inputs
are encoded into canonical slots, `r0` reads zero, and all writable registers,
outputs, and scratch start uninitialized. Low-level transitions also accept
states supplied by proofs/tests; those states are not candidate-provided storage.

`Evaluation.execute candidate scalarInputs maxBoundaries` validates the scalar
count and signed48 transport width, then returns `ExecutionOutcome.success`,
`.failure`, or `.resourceExhausted`. Workload-specific input predicates and
all-input correctness are enforced by the separate verification layer below. The typed
`executeValues` entry point accepts a fixed-length vector of `Signed48` values.
Neither entry point calls a workload reference. A successful concrete run carries
no verification label or optimization score.

The runner sorts the schedule once and consumes each boundary's prefix. Its
budget counts processed boundaries, including zero: the six-cycle tiny fixture
needs seven boundaries. Empty zero-output programs finish at cycle zero with no
budget. A run finishes only after the schedule and pending effects are empty,
then checks every output was written. Budget exhaustion reports the next
boundary, issued/remaining instruction counts, and pending effects; it is
inconclusive. Missing outputs are a separate failure.

Records include version/identity fields, decoded outputs, elapsed cycles, resource
allocation, declared storage, schedule size, event-derived counters, and a trace.
Each trace boundary lists commits before issues. Counters charge operand reads
including repeated `r0` operands, register writes at commit, one access per
load/store, and MAC as its own operation. Per-lane activity includes issue and
completion counts plus occupied intervals `[t,t+1)` after issue; three-cycle
arithmetic occupies three such intervals. Initialization adds no events.
Pass `false` as the optional final argument to omit the trace while preserving
outputs, timing, and counters. `Counters.ofEvents` independently reconstructs
counters from a retained trace; `run_step` exposes the runner's one-boundary
recurrence for compositional reasoning.

## Verification API and trust boundary

`ScalarAdapter specification` fixes the logical scalar order. Its input and output
codecs have proved left inverses, and output decoding takes only output scalars.
The tiny codec places `a` and `b` in two input scalars and its integer output in
one output scalar. Matrix codecs use row-major inputs/outputs and concatenate
the two input regions. They only transport values;
they do not calculate reference outputs during machine initialization.

`inspect shape raw` validates structure and returns an exact `toRaw = raw` binding.
`checkStatic candidate` reuses `Hardware.checkBatch` for input-independent issue,
bank-port, and address rules. Readiness, initialization, arithmetic widths,
pipeline reservations, termination, and outputs remain execution obligations.
These checks are distinct from a certificate.

`VerifiedCandidate adapter` contains the exact candidate and separate all-input
`ExecutionSafety` and `FunctionalCorrectness` proofs against `executeValues` at a
sufficient boundary budget. Safety requires actual successful finite execution,
including drained effects and written outputs. Correctness equates every returned
output scalar to the mathematical reference through the workload codec.

`selectCandidate identifier` selects the stored `tiny-multiply-v1`,
`matvec-naive-v1`, or `matmul-naive-v1` artifact.
`evaluateRegistered raw scalarInputs maxBoundaries` recognizes those complete
artifacts, validates the signed16 workload domain, and returns `.verified record`,
`.failure reason`, or `.resourceExhausted details`. The generic `objectiveCatalog`
additionally contains both product-pair artifacts, through the proof-carrying
scoring API described below.
The tiny certificate uses seven boundaries; the matrix-vector certificate uses
2,144 boundaries; matrix-matrix uses 34,304. All fix trace capture disabled, and
accepted evaluation uses that exact path. Extra budget is capped at the certified bound.
Smaller budgets actually execute and remain inconclusive on exhaustion; proved
fuel monotonicity establishes correctness if they finish successfully.

`simulate shape raw scalarInputs maxBoundaries captureTrace` permits arbitrary
structurally valid programs and returns `.simulated record` on success. Numerical
success never upgrades them to verified status. It validates count and signed48
transport only; workload-domain validation belongs to registered evaluation.
Trace-enabled execution remains available as simulation, without a certificate
for its trace. The CLI compares every nontrace field of a second traced run with
the accepted run before exporting it; this observed equality is not a generic proof.
Accepted objective scoring uses a separate proof-carrying execution API described below.

`Hardware.Invariants` proves that every successful step from a state with at most
three pending effects per lane preserves that bound. Initialization satisfies the
bound, and `Reachable` follows the actual `Hardware.step`. `run_finished_reachable`
connects finished runs to that relation. Successful batch checks imply lane issue,
bank, and address limits; successful commits imply at most one due register write
per lane. Raw hand-built states still have unrestricted pending lists. Bounded
register values and canonical memory/pending payloads retain their signed48 types.

Run the reproducible proof-dependency audit with:

```sh
lake env lean scripts/audit-verification.lean
```

All 53 audited declarations depend only on Lean's standard `propext`, `Quot.sound`,
and `Classical.choice` axioms. There are no admitted proofs, custom axioms, or
native-decision proof shortcuts. This is a software-model proof, not physical
FPGA timing, placement, routing, or power validation.

## Naive matrix-vector baseline

`Examples.MatVecNaive.candidate` is the default `(8, 8)` `matvec-naive-v1` artifact.
It uses only lane zero and a row-major layout, explicitly resets each row's
signed48 accumulator, and reloads both operands for each column. Every primitive
waits through its completion boundary. There is no cross-row reuse or parallel
scheduling. `candidateFor config` runs the same fixed generator on any admissible
configuration; the all-input certificate is for the primary default artifact.

The full workload takes 2,143 model cycles and 800 instructions: 512 loads,
16 stores, 16 accumulator-reset adds, and 256 MACs. It uses 2,304 declared bytes.
The independent schedule/count calculation, saved JSON records, and a small
inspectable trace are in [docs/results](results/README.md).

`Evaluation.Serial.run_serial` composes successful real instruction blocks through
the actual runner. `Examples.SerialDot.executes_prefix` proves a reusable
all-input dot-product prefix property; `MatVecProof.lean` combines it with row
induction, initializer read-back, sorted-program binding and output collection.
`MatVecNaive.verified` carries separate safety and correctness proofs against
`executeValues`. Neither execution nor initialization uses reference outputs.

`lake test` includes seven certified fixtures and 112 configuration conformance
runs. Reproduce the primary record and audit the new proof roots with:

```sh
lake env lean scripts/reproduce-matvec.lean
lake env lean scripts/audit-matvec.lean
```

The new audit covers 72 declarations and uses only the same standard Lean axioms.
The default baseline scores 2,143 cycles and 59,607 abstract energy units.

## Naive matrix-matrix baseline

`Examples.MatMulNaive.candidate` is the default `(8,8)` `matmul-naive-v1` artifact.
It uses conventional `i,j,k` order, lane zero, a fresh signed48 dot product per
output, and explicit operand reloads. Slots 0–255 hold A, 256–511 hold B, and
512–767 hold C, all row-major. `MatMulNaive.execution_correct` proves actual
execution and all 256 outputs for every allowed input; `MatMulNaive.verified`
packages the certificate. It reuses `SerialDot.executes_prefix` and `Evaluation.Serial`.

The baseline uses 12,800 instructions, 6,144 bytes and 34,303 model cycles. Its
energy score is 954,087 abstract units. The [record guide](results/matmul-naive-v1.md)
gives exact counts, proof roots and reproduction commands. Its 16 configuration
variants are conformance simulations, while the default artifact has an all-input
certificate. No search strategy is implemented.

## Interchangeable objectives

`Evaluation.Objectives` supplies `latency` and `energy`, both minimizing a pure
score over the same execution record. Accepted scores require exact proof-carrying
execution evidence; a record or `.verified` display tag alone is insufficient.
`evaluateObjective objectiveCatalog raw inputs budget inputId objective` executes
an exactly registered artifact, while `accepted.rescore objective` preserves the
same record. The compiled catalog contains tiny multiply, the default matrix-vector
and matrix-matrix baselines, and the two manually scheduled product-pair comparison fixtures.

The serial pair takes 12 cycles and 172 abstract energy units; the parallel pair
takes 6 cycles and 202 units. Both are proved safe and correct for all signed16
operands. The energy profile is hypothetical and versioned, with no physical clock
or energy claim. See [objectives and trust boundary](objectives.md) for the
formula, API, proof roots, and extension rules.

```sh
lake env lean scripts/audit-objectives.lean
lake env lean scripts/reproduce-matvec-objectives.lean
lake env lean scripts/reproduce-product-pair-objectives.lean
```
