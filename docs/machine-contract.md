# Initial machine contract

This is the concise contract for **`arty-model-v1`**, derived from [PLAN.md](../PLAN.md).
It specifies the full first release. The code implements the
package, identifiers, board profile, admissibility, resource accounting, and bounded
bank mapping, checked arithmetic, canonical storage, and pure matrix references
with all-input output/prefix bounds, bounded layouts, finite candidate programs,
structural validation, pure cycle execution, objective-free records, and executable
checks. The tiny multiply candidate, naive matrix-vector and matrix-matrix baselines, and two manual
product-pair candidates have all-input execution/correctness certificates. Pure
latency and abstract-energy objectives score verified executions. The small
[CLI](usage.md) exposes these artifacts and optional observational traces.
[STATUS.md](../STATUS.md) records progress. The [assumptions table](assumptions.md)
classifies the hardware facts, project choices, and deferred physical details.

## Scope and identifiers — project modeling choices

The software models a small accelerator family inspired by the Digilent Arty
A7-100T. Model admissibility is not proof of physical implementation or timing
closure. Inputs begin in local memory. No generated RTL, FPGA programming,
physical power measurement, LLM integration, optimization/search algorithm,
autonomous loop, or optimality claim is included.

| Contract | Initial identifier |
| --- | --- |
| Machine semantics and admissibility | `arty-model-v1` |
| Candidate format | `candidate-v1` |
| Latency objective | `latency-v1` |
| Energy objective | `energy-proxy-v1` |
| Energy coefficient set | `energy-coefficients-v1` |

These strings are defined in `OptimalComputation/Versions.lean`. The workload
specifications record `matvec-16x16-signed16-v1` and `matmul-16x16-signed16-v1`.
Baseline instance identifiers are
reserved as `matvec-naive-v1` and `matmul-naive-v1`. Preserve versioned baseline
results; an incompatible correction to frozen semantics requires a new model
version and rerunning affected results. New workloads and objectives must use the
same machine semantics. Changed energy coefficients require a distinct profile.

## Storage and configuration — project modeling choices

- Choose lanes `L` and banks `B` independently from `{1, 2, 4, 8}`; the default is
  `(8, 8)`. Configuration cannot change during execution.
- Local memory is exactly 4,096 slots of 64 bits (32 KiB). Address `a` maps to bank
  `a mod B`, row `a / B`. Each bank has `4096 / B` slots and two general-purpose
  access ports. Every lane may request any bank, subject to contention.
- Charge one DSP per lane and `B * 2 * ceil((4096 / B) / 1024)` BRAM36 blocks:
  8 blocks for 1, 2, or 4 banks, and 16 for 8 banks. This models pairs of physical
  blocks providing up to 1,024 64-bit words per pair; it is not a flat unlimited-port RAM.
  `bramPairsForDepth` uses integer ceiling, including the partially used pair at
  512 words per bank in the eight-bank configuration. UG473 v1.14, Chapter 1,
  pages 11 and 21, confirms that a single block's 72-bit mode instead has one
  read-only and one write-only port. The paired-block construction preserves two
  general-purpose ports; depth-selection logic remains uncalibrated.
- Each lane has constant-zero `r0` and 15 writable signed 48-bit registers, at most
  three operand reads and one result write per cycle, one issued instruction per
  cycle, and three outstanding instruction slots (one completion event each).
  Writable architectural register storage is `L * 15 * 48` bits; pipeline storage
  is separate. Lanes communicate only through explicit stores and loads.
- Layouts have bounded, injective mappings and disjoint input, output, and scratch
  regions. Inputs are read-only. Only inputs and `r0` are initially readable;
  writable registers, scratch, and outputs start uninitialized.

## Arithmetic and programs — project modeling choices

References use mathematical integers. Signed 16-bit operands range from `-2^15`
through `2^15 - 1`; signed 48-bit values range from `-2^47` through `2^47 - 1`.
Supported arithmetic is signed 16-by-16 multiplication, signed 48-bit addition,
and multiply-add with signed 16-bit multiplicands and a signed 48-bit accumulator.
All results must fit; overflow is invalid. There is no wrapping, saturation,
rounding, floating point, or packed memory arithmetic. Memory uses canonical
64-bit sign extension of signed 48-bit values and transfers whole 64-bit slots.
The executable arithmetic checks each operand left-to-right, then the accumulator
for multiply-add, then the result. `Slot64` carries a 64-bit pattern whose signed
interpretation fits 48 bits. The code proves equivalence to truncating to 48 bits
and sign-extending back to 64, and both value/slot round trips. Raw noncanonical
patterns are rejected rather than normalized silently.

A candidate binds a workload identifier, admissible configuration, layout,
scratch allocation, and finite schedule. Instructions are `load`, `store`, `add`,
`multiply`, and `multiply-add`, with explicit issue cycles, lanes, local registers,
and bounded memory addresses. Waiting is explicit. No runtime branches, implicit
loops, hidden computation/storage, allocation, or data-dependent schedules are
allowed. Inputs are sampled at issue; a destination may also be a ready source,
using its old value. Every intermediate occupies a register, pending effect, or
declared memory slot. The reference supplies no computational help to a candidate.

The implemented structural validator takes an expected workload shape (identifier
and logical input/output counts). It rejects mismatched versions, identifiers,
counts, non-admissible configurations, out-of-range operands, all storage aliases,
undeclared memory accesses, and writes to inputs or `r0`. Each accepted layout
carries bounded input/output mappings and a proof of global slot uniqueness;
each accepted instruction carries its memory-access permission. Candidate data
contains no runtime values or initialization overrides. Hardware and candidate
validation remain independent of the concrete matrix workloads.

Schedules retain their supplied list order and explicit natural-number cycles;
list position is not a timing rule. The generic syntax allows source/destination
aliasing, reads of `r0`, and loads from declared outputs/scratch. Whether those
values are ready and initialized must be decided at execution. Structural
validation does not certify issue conflicts, dependencies, arithmetic widths,
pending capacity, output completion, or correctness. The `tiny-multiply-v1`
fixture's two loads, multiply, and store are structurally validated and execute
in six elapsed cycles, including the final output store. No semantics/version
correction was introduced by this staging.

## Boundaries and legality — project modeling choices

At boundary `t`, commit effects due at `t`, then issue instructions for `t`.
Loads and stores complete at `t + 1`; all arithmetic completes at `t + 3`.
A load captures memory at issue; a store captures its source register at issue.
A read at the boundary where an earlier write completes sees that completed write.
An instruction issued at zero and completed at three takes three cycles.

A pending destination cannot be read or assigned another pending write. Reserve
future writeback slots: only one register result may arrive per lane per boundary.
Each load/store consumes one bank access, including repeated reads of one value.
Two same-cycle accesses to one address are allowed only if both are reads.
Reject uninitialized reads, writes to inputs or `r0`, invalid widths, excess bank
accesses, issue/writeback conflicts, and more than three pending effects per lane.
Pending slots include result/store payload and destination metadata. Conflicts
are errors; simulation never inserts stalls or repairs schedules. Representation
order of simultaneous instructions must not affect results.

Completion requires every scheduled instruction to be processed, every pending
effect to commit, and every output slot to be written. Elapsed cycles include
that final boundary, including the final output store.

The executable implementation is `Hardware.step`: fixed-size register and memory
vectors, per-lane reserved pending effects, and a pure transition returning events
or a structured error. It checks the complete issue batch and prepares all payloads
against one post-commit state before enqueueing any of them. Lane ordering fixes
trace and diagnostic order; instruction list order supplies no hidden priority.
Bank ports are charged once, at request issue, not again at completion. Low-level
states are available for proofs and tests; actual candidate execution always
starts from the shared input-only initializer and validated schedule.

The runner counts processed boundaries explicitly for its resource budget. The
tiny six-cycle run uses boundaries zero through six. An empty zero-output program
finishes at cycle zero even with zero budget. Exhausting a budget before the final
commit is inconclusive, even if the output store has already issued. The runner
sorts once and consumes a schedule prefix each boundary, including empty waits.

## Verification and evaluation — project modeling choices

Use one executable transition definition for simulation and proofs. Structural
validation, execution safety, and functional correctness are distinct obligations.
Accepted candidates bind their exact program, model version, workload, layout,
and configuration to Lean proofs of successful, legal execution and agreement
with the reference **for every allowed input**. Examples alone cannot certify
them; `sorry`, `admit`, and candidate-specific unproved assumptions are forbidden.
Audit accepted theorem axioms. Serialized assertions or hashes are not proofs.

Report structured failures for invalid input, inadmissible configuration,
malformed layout, illegal schedule, arithmetic failure, incomplete output,
unverified candidate, and evaluator resource exhaustion, with relevant cycle,
lane, address/register, and violated rule. Exhaustion is inconclusive.

Execution is objective-independent. Derive outputs, elapsed cycles, instruction
counts by kind, loads/stores, register reads/writes, per-bank accesses, lane
activity, resource allocations, declared storage, and schedule size from execution
and its bound configuration/program, never candidate-supplied activity counts.
Only verified valid evaluations receive accepted optimization scores.

Implemented counters charge loads/stores/arithmetic and operand reads at issue,
register writes at completion, and each memory request against its selected bank.
Repeated operands and reads of `r0` count individually. Per-lane reports include
issued/completed instruction counts and active intervals `[t,t+1)` in which at
least one pending effect remains after issue. Three-cycle arithmetic therefore
occupies three active intervals. Initialization contributes no execution events.
Tracing can be disabled without changing any outputs, timing, or counters.
The low-level scalar transport adapter checks exact count and signed48 width.
Registered evaluation additionally validates the workload domain: both tiny
multiplication operands must be signed16. Concrete simulation success does not
assert all-input correctness. The certified path currently fixes tracing off;
trace-enabled records remain simulations. Fuel monotonicity proves that reducing
a certified budget cannot change a successful record.

Both initial objectives minimize: latency is elapsed cycles, and energy is in
abstract energy units. With `R` allocated BRAM36 blocks, the coefficient profile is:

```text
energy = cycles * (1 + L + R)
       + 4 * loads + 4 * stores
       + additions + 8 * multiplications + 9 * multiply_adds
       + register_reads + register_writes
```

Multiply-add is one event, not additional multiply/add events. Count issued
operand reads (including `r0`), successful destination writes, and explicit
transfers consistently. Operation costs abstract pending pipeline details.
Store verification status, all relevant versions, candidate/configuration/input
identifiers, execution summary, objective/unit, coefficients, and score breakdown.
Scoring must not alter execution; objectives are separate, never a weighted sum.

## Workloads and baselines — project modeling choices

First specify 16-by-16 matrix times 16-vector, then 16-by-16 matrix multiplication,
with runtime signed 16-bit entries, exact integer dot products, and no sparsity,
fixed weights, or cross-invocation reuse. References contain no physical addresses.
Their data occupies 2,304 and 6,144 bytes respectively before scratch.
Each 16-term dot product must be proved to fit signed 48 bits; arbitrary candidate
intermediates require their own safety proof.
The implemented increasing-index `dotPrefix` reference bounds every prefix of
`n ≤ 16` terms by `±(n * 1073741824)`, hence by `±17179869184` at full length.
The proof covers every allowed signed 16-bit input, including `-32768`, and
establishes exact checked multiply-add success for each next prefix. It does not
establish schedule or storage safety for a candidate.

Every workload needs a runnable, verified naive baseline: row-major layout,
lane zero only, increasing-column dot products, explicit loads, signed 48-bit
accumulation, waits, and output stores. Matrix multiplication uses `i, j, k` order.
No tiling, packing, parallel scheduling, or reuse between dot products. Register
the default `(8, 8)` baseline and configuration-specific comparison records;
preserve versioned layout, latency, activity, and energy results. These known
baseline generators and manual comparison fixtures do not perform search.

## Abstraction boundary — deferred physical details

Host communication, initialization transfers, and external DDR3 traffic are
excluded. The abstract controller issues the supplied schedule; instruction
storage/fetch and controller implementation are unmodeled, so schedule size is
reported. Physical routing delay/area and full control, connection, and pipeline
LUT/flip-flop costs are uncalibrated, never reported as zero. Model cycles have no
claimed clock frequency; model energy is hypothetical, not joules or watt-hours.
Physical implementation, timing closure, and power calibration are future work.

## Implemented verification scope

`ExecutionSafety` and `FunctionalCorrectness` quantify over every allowed logical
input, use the workload-owned scalar adapter, and refer to the actual
`executeValues`/`run`/`Hardware.step` path. A certificate contains the exact
configuration, layout, schedule and model-bound candidate, plus its sufficient
boundary budget. Registry lookup compares the complete artifact; an identifier
or serialized correctness assertion cannot confer verified status.

The tiny multiply certificate covers every pair in `[-32768, 32767]`, with result
`a*b`, store completion at boundary 6, and seven processed boundaries. The default
`matvec-naive-v1` artifact also has an all-input certificate, with store completion
at boundary 2143 and 2,144 processed boundaries. It uses only lane zero, resets
each row, reloads vector operands for every row, and waits through each primitive
completion. The certificate uses the shared initializer/runner/step and a reusable
dot-product proof composed across rows. All 16 configurations have conformance
simulations; the certificate covers the default `(8, 8)` artifact. The default
`matmul-naive-v1` artifact has an all-input certificate for conventional `i,j,k`
execution with fresh operand loads for every output, 34,304 processed boundaries,
and final store completion at cycle 34,303. Its 16 configuration variants are
also conformance simulations. The fixed
model rules above are unchanged; [baseline records](results/README.md) document
the schedule and independently checked counters.

Generic invariant proofs establish the three-pending-effects-per-lane bound for
states reachable from initialization through successful machine steps. A finished
`run` is proved reachable by those same steps. Successful `checkBatch` implies at
most one issue per lane, at most two bank accesses, and no same-address write
conflict; successful `commit` implies at most one due register result per lane.
The raw State type remains unbounded in its pending lists. No machine transition,
latency, numeric rule, or version was changed to obtain these proofs.

Unified failures distinguish invalid input, inadmissible configuration, malformed
layout/artifact/instruction, illegal schedule, arithmetic failure, incomplete
output and unverified candidate. Resource exhaustion is a separate inconclusive
outcome with real runner progress details. The reproducible axiom audit is
`scripts/audit-verification.lean`; accepted declarations use only Lean's standard
`propext`, `Quot.sound` and `Classical.choice` axioms.


## Implemented objective scope

The pure latency and abstract-energy objectives share the unchanged execution
record. `CertifiedExecution` binds an actual trace-disabled `executeValues` success
to an allowed runtime input and complete proof-bearing candidate. Accepted scoring
requires this evidence and exact raw-artifact equality, not an `Outcome.verified`
tag or JSON status. Failures, simulations and exhaustion are never promoted into
accepted optimization scores. Rescoring preserves the original execution.

The frozen energy formula and coefficient profile, default matrix-vector costs,
and all-input-certified serial/parallel product-pair fixtures are documented in
[objectives](objectives.md). Both objectives minimize; cycle counts have no assumed
physical clock and energy units are hypothetical. Hardware semantics, numeric
rules, versions and original objective-free results are unchanged.
