# Optimal Computation implementation plan

Build the primitives needed to describe a computation, run a candidate implementation on a fixed FPGA-inspired machine model, verify its correctness, and evaluate it with different objectives.

The first release is a software experiment in Lean. It must make future optimization experiments possible without choosing or implementing a search strategy. Matrix-vector multiplication comes first; matrix-matrix multiplication then demonstrates that the foundation supports another computation.

## 1. Scope and guiding decisions

- Prefer the simplest implementation that leaves something useful to investigate.
- Model a small, explicitly defined family of accelerators grounded in the Digilent Arty A7-100T.
- Keep the machine semantics, admissibility rules, and numerical rules fixed across computations and objectives.
- Allow a candidate to select an admissible configuration. Selecting a configuration does not change the hardware model.
- Prove correctness against each computation's mathematical specification for every allowed input.
- Treat latency minimization and energy minimization as separate problems. Do not combine them into a weighted objective.
- Make computations, objective functions, and eventual search strategies independent extensions.
- Require a naive, executable, verified baseline for every computation, alongside manually constructed examples that validate the foundation.

This release does not include an LLM integration, autonomous agent loop, search algorithm, optimality claim, generated RTL, FPGA programming, or physical power measurement. A baseline program generator is allowed to produce a known straightforward implementation; it must not search for a better one.

The project brief supplies the starting assumptions. The additional defaults below make those assumptions implementable. They are project modeling decisions, not measured characteristics of the board.

### Required baseline for every computation

Each computation must ship with both its pure mathematical reference and a naive implementation that actually runs on the modeled machine. The reference defines the required answer; the baseline supplies a correct, reproducible starting point for future optimization comparisons.

- Use the ordinary nested-loop algorithm, expanded into explicit scheduled instructions, with one active lane and a simple row-major layout.
- For matrix-vector multiplication, process rows in order and accumulate each row's products in increasing column order.
- For matrix-matrix multiplication, use the conventional `i, j, k` loop order: compute each output entry with a fresh dot product.
- Load operands explicitly, accumulate in signed 48-bit arithmetic, wait for dependencies, and store every output. Do not add tiling, packing, parallel scheduling, or reuse between separate dot products.
- Prove the baseline safe and equivalent to the mathematical reference for every allowed input. Passing example inputs is additional evidence, not the correctness criterion.
- Register the baseline with a stable identifier and record its configuration, layout, latency, and energy score. Its primary configuration is the shared default of eight lanes and eight banks, with only lane zero active. Also provide configuration-specific baseline records when making later comparisons on other admissible configurations.
- Preserve baseline definitions and version their result records so future strategies have a stable comparison. A newly added computation is incomplete until its baseline is available.

## 2. What stays fixed and what can vary

| Component | Responsibility | Extension rule |
| --- | --- | --- |
| Board profile | Records the reference chip and its physical resources | Fixed for this release |
| Machine model | Defines arithmetic, storage, connections, instructions, and timing | Shared by every workload and objective |
| Admissibility rules | Define which configurations and executions are legal | Candidates cannot redefine them |
| Configuration | Selects lane and bank counts from the allowed family | May differ between candidates |
| Computation specification | Defines inputs, allowed values, and required outputs | Add a new specification for a new computation; freeze it within an experiment |
| Candidate | Supplies a configuration, data layout, and scheduled program | May differ between implementations of the same computation |
| Execution record | Contains outputs, event counts, timing, and resource information | Produced without knowledge of the selected objective |
| Objective | Converts a valid execution record into a score with a declared unit and optimization direction | Add independently; parameters remain fixed within an experiment |
| Search strategy | Proposes candidates and consumes evaluation results | Future work; uses the same public evaluation interface |

Use explicit version identifiers for the machine model, workload, candidate format, objective, and energy coefficients. A correction to frozen semantics requires a new model version and rerunning affected results. Adding an objective or a workload that uses existing primitives must not require changing machine semantics.

## 3. Hardware reference and abstraction boundary

The reference board is the **Digilent Arty A7-100T**, containing the **AMD/Xilinx Artix-7 XC7A100TCSG324-1**. Digilent lists 240 DSP slices, 4,860 Kibits of block RAM, and 256 MB of external DDR3 memory. See the [Digilent board specifications](https://digilent.com/shop/system-boards/).

AMD lists 63,400 lookup tables and 126,800 flip-flops for the XC7A100T. These are resources used to construct control and datapath logic, rather than a ready-made processor with a fixed instruction set. See [UG474, 7 Series FPGA CLB Resources](https://docs.amd.com/r/en-US/ug474_7Series_CLB/7-Series-FPGA-CLB-Resources).

| Physical feature | Relevance to the model |
| --- | --- |
| DSP48E1 arithmetic | Native 25-by-18-bit signed multiplication and 48-bit arithmetic support the narrower arithmetic selected for this project. Pipeline registers are configurable. |
| Block RAM | 4,860 Kibits equals 607.5 KiB of nominal storage. The physical allocation depends on width, depth, and port mode. |
| Programmable logic and registers | Needed for control, local registers, multiplexers, and connections between blocks. |
| External DDR3 | Present on the board, but outside the first execution model. |

The relevant primitive manuals are [UG479, DSP48E1](https://docs.amd.com/api/khub/documents/gu4oRPFEh_Pm2uaAlfY6Kg/content) and [UG473, memory resources](https://docs.amd.com/api/khub/documents/9gZGbqBxtlKXxBfkBt~lAg/content). In particular, a 36-Kibit block supports true dual-port widths up to 36 bits; its 72-bit mode has one read port and one write port. A logical 64-bit memory with two general-purpose ports therefore needs multiple physical blocks.

The model represents an accelerator built from these kinds of resources. It does not reproduce every legal Artix-7 circuit. A configuration accepted by our model has **model admissibility**, not a proof that a complete circuit has been placed, routed, and timed successfully.

Keep these boundaries explicit:

- Inputs begin in local memory. Initialization transfers, host communication, and external-memory traffic are excluded.
- A fixed abstract controller issues the supplied schedule. Instruction storage, instruction fetch, and physical controller implementation are not modeled. Record schedule size so this omission remains visible.
- Connections have explicit transfer and contention rules, but physical routing delay and exact routing area are not modeled.
- DSP and block-RAM allocations are accounted for. Architectural register storage is counted. Full LUT and flip-flop implementation costs remain uncalibrated; do not report missing costs as zero.
- Timing and energy are model results. Physical timing closure and energy calibration are later projects.

## 4. Mathematical shape of the system

For a configuration `c`, let `Admissible(c)` express the configuration rules. For a workload `w`, let `AllowedInput(w, x)` define valid input values, and let `Reference(w, x)` define the required output.

A candidate `p` contains a configuration, layout, and finite scheduled program. The machine advances through deterministic state transitions:

```text
step(model, configuration, scheduled actions, state)
    -> next state and events, or a structured error
```

A verified candidate must establish both properties for every allowed input:

```text
ExecutionSafety: execution obeys the machine rules and finishes successfully.
FunctionalCorrectness: decoded final outputs equal Reference(workload, input).
```

The evaluator then exposes a shared record:

```text
evaluate(verified candidate, allowed input)
    -> execution record

score(objective, execution record)
    -> score, unit, and breakdown
```

These are interface sketches, not required Lean syntax. Use ordinary Lean structures and functions before considering a more elaborate abstraction.

## 5. Implementation milestones

Complete the milestones in order. Each exit check must pass before a later milestone relies on it. Do not hide an unfinished proof or an undefined machine rule behind a successful example run.

### Milestone 1: Establish the Lean project and contracts

1. Create one Lean 4 package using Lake. Pin the Lean version and any dependencies. Add mathlib only if it materially simplifies the finite-sum and arithmetic proofs.
2. Establish one documented build command and one command for the executable regression checks. Keep the project usable on the current Mac without FPGA tools.
3. Create a short machine contract document and an assumptions table. Every rule should be labeled as a manufacturer fact, a project modeling choice, or a deferred physical detail.
4. Record the initial identifiers `arty-model-v1`, `candidate-v1`, `latency-v1`, and `energy-proxy-v1`.
5. Keep implementation modules separated by responsibility. A suitable starting layout is:

```text
OptimalComputation/
  Hardware/       -- board profile, configurations, arithmetic, transitions
  Workloads/      -- mathematical specifications and input/output descriptions
  Candidates/     -- layouts, scheduled programs, proof-bearing candidates
  Evaluation/     -- validation, simulation, records, objective functions
  Examples/       -- small fixtures and straightforward matrix baselines
  Tests/          -- executable positive and negative checks
Main.lean         -- a small command-line entry point
docs/             -- machine contract, assumptions, usage
```

Create modules when needed; do not generate an empty framework or a plugin loader. Keep hardware modules independent of matrix operations, objective functions, and future search code.

**Exit checks:** a clean checkout builds with the pinned toolchain; a trivial executable check runs; the documented contracts identify the current scope and version.

### Milestone 2: Define configurations and resource accounting

Implement a board profile, a configuration type, a decidable admissibility predicate, and a resource report.

Use the following small family for version one:

| Property | Fixed rule or allowed choice |
| --- | --- |
| Arithmetic lanes `L` | Choose from 1, 2, 4, or 8 |
| Logical memory banks `B` | Choose from 1, 2, 4, or 8 |
| Total local memory | Fixed at 32 KiB: 4,096 slots of 64 bits |
| Bank mapping | Slot `a` maps to bank `a mod B`, row `a / B` |
| Bank capacity | `4096 / B` slots, with two general-purpose access ports |
| Local registers | 16 per lane: constant-zero register `r0` and 15 writable signed 48-bit registers |
| Register access | Up to three operand reads and one result write per lane per cycle |
| Instruction issue | At most one instruction per lane per cycle, including loads and stores |
| Pending effects | At most three outstanding instructions per lane, each with one completion event |
| Connections | Each lane can request any bank; bank limits still apply |
| Lane-to-lane transfer | Through explicit stores and loads; no implicit shared registers |
| Configuration changes | Forbidden during execution |
| Default example configuration | 8 lanes and 8 banks, matching the brief's starting scale |

Account for one DSP allocation per lane. For the logical memory, use a simple construction from pairs of 36-Kibit blocks, each pair supplying a 64-bit-wide true dual-port memory up to 1,024 words deep. Charge whole blocks:

```text
BRAM36 blocks = B * 2 * ceil((4096 / B) / 1024)
```

This gives 8 blocks for 1, 2, or 4 banks, and 16 blocks for 8 banks. The increase for 8 banks reflects unused physical depth. Check the construction against UG473 when implementing the contract.

Report writable architectural register bits as `L * 15 * 48`. Also describe pipeline state separately; architectural registers are not the full physical flip-flop cost. Keep exact control, connection, and pipeline implementation area marked as uncalibrated.

**Exit checks:** all 16 intended `(L, B)` combinations are accepted; unsupported values are rejected with reasons; allocation calculations match hand calculations; logical memory cannot be mistaken for a flat unlimited-port array.

### Milestone 3: Define arithmetic and workload specifications

1. Use mathematical integers for reference results.
2. Define signed 16-bit and signed 48-bit ranges exactly, including their negative endpoints.
3. Support signed 16-by-16 multiplication, signed 48-bit addition, and multiply-add with signed 16-bit multiplicands and a signed 48-bit accumulator.
4. Require every arithmetic result to fit its declared range. Overflow is invalid; there is no wrapping, saturation, rounding, or floating-point approximation in version one.
5. Store memory values in 64-bit slots with a canonical sign-extended representation. Numeric values used by this machine fit signed 48 bits. Count transfers as full 64-bit slots; do not introduce packing.
6. Define a workload interface containing its identifier, input structure, input predicate, output structure, and pure reference function. Keep physical addresses out of the reference function.
7. Define matrix-vector multiplication first:

```text
A: 16 by 16 signed 16-bit values
x: 16 signed 16-bit values
y[i] = sum over k of A[i,k] * x[k]
```

8. Define the matrix-matrix reference specification, but defer its candidate implementation until Milestone 9:

```text
A, B: 16 by 16 signed 16-bit values
C[i,j] = sum over k of A[i,k] * B[k,j]
```

All matrix entries are runtime inputs. No sparsity, fixed weights, or cross-invocation reuse is assumed. Prove simple bounds showing that each 16-term dot product fits in a signed 48-bit accumulator. These bounds do not automatically justify arbitrary candidate intermediates; each candidate must also establish its own execution safety.

With 64-bit storage slots, the matrix-vector inputs and outputs occupy 2,304 bytes; the matrix-matrix inputs and outputs occupy 6,144 bytes. Both fit within the fixed local-memory budget before adding scratch storage.

**Exit checks:** exact specifications exist independently of any program; range boundaries are checked; output bounds are proved; reference calculations agree with hand-worked examples.

### Milestone 4: Define layouts and scheduled candidate programs

1. Define a finite candidate format containing a workload identifier, admissible configuration, memory layout, scratch allocation, and schedule.
2. Map each logical input and output element to a physical slot. Require injective mappings and disjoint input, output, and scratch storage. Inputs are read-only during execution.
3. Support `load`, `store`, `add`, `multiply`, and `multiply-add`. Arithmetic operands and destinations are local registers. Memory addresses are explicit, bounded addresses.
4. Give every scheduled instruction an issue cycle and lane. Unused cycles represent waiting. There are no runtime branches, implicit loops, allocation, hidden computation, or data-dependent schedules.
5. Treat each instruction's inputs as sampled at issue time. A destination may also be a source of that instruction when its old value is ready.
6. Start writable registers, scratch storage, and outputs as uninitialized. The zero register and declared inputs are the only initially readable values. Track initialization explicitly.
7. Include every intermediate in a register, pending pipeline result, or declared memory slot. The mathematical reference implementation must never provide extra storage or computation to the candidate.
8. Use a deterministic representation and stable identifiers for fixtures. Hashes may identify content but do not replace proofs.

**Exit checks:** a tiny program representing two loads, a multiplication, and a result store can be constructed and structurally validated; malformed addresses, overlapping layouts, writes to inputs, and writes to `r0` are rejected. Its actual execution is checked in Milestone 5, after the simulator exists.

### Milestone 5: Implement cycle semantics and objective-free execution

Use one executable transition definition as the source of truth for simulation and proofs.

The timing convention is:

1. At boundary `t`, commit all results due at `t`.
2. Issue the instructions scheduled for `t`, sampling the resulting state.
3. Schedule loads and stores to complete at `t + 1`.
4. Schedule arithmetic results to complete at `t + 3`.

An operation issued at cycle zero and completed at boundary three has taken three cycles. All arithmetic operations use the same three-cycle model latency. This is a fixed abstraction, not a universal DSP timing claim.

A load captures the addressed value at issue and makes it available in its destination register at completion. A store captures its source register at issue and updates memory at completion. Because completions happen before issue, a read issued at the boundary where an earlier write completes sees the new value.

Implement these legality rules:

- A lane issues at most one instruction at a boundary.
- A register with a pending write cannot be read or assigned another pending write. Reserve destination registers until completion.
- At most one register result may arrive in a lane at a boundary. Reserve future writeback slots so a load and arithmetic result cannot collide silently.
- Each bank accepts at most two accesses per cycle. Each load or store consumes one access even when another lane requests the same value.
- Two accesses to the same address in a cycle are allowed only when both are reads. Reject any same-cycle pair involving a write.
- A read cannot use an uninitialized value. Arithmetic cannot violate operand or result widths.
- Pending instructions occupy one of the lane's three completion slots, including their result or store payload and destination metadata. Do not let an unbounded host-language queue create extra machine capacity.
- A conflict is an invalid schedule. The simulator does not repair it or insert hidden stalls; waiting must appear in the candidate schedule.

Record cycle count, outputs, instruction counts by kind, loads, stores, register accesses, per-bank accesses, lane activity, allocated resources, declared storage, and schedule size. Counters must be derived from executed events rather than provided by the candidate.

Completion requires all scheduled instructions to have been processed, all pending effects to have committed, and every output slot to have been written. Record elapsed cycles through that final boundary. In particular, do not stop at the final arithmetic instruction before its output store finishes.

**Exit checks:** the tiny program from Milestone 4 executes its two loads, multiplication, and result store correctly. Hand-worked traces cover dependent and independent arithmetic, loads, stores, writeback collisions, bank contention, and completion. Permuting the representation order of simultaneous instructions cannot change the result. Event counts reconcile with the trace.

### Milestone 6: Establish verification and failure reporting

1. Separate structural validation, execution safety, and functional correctness. Passing one does not imply the others.
2. Implement decidable checks for configuration values, layout bounds, instruction shape, and the schedule properties that can be checked without inputs.
3. Prove that successful executable checks imply their corresponding declarative properties. Avoid maintaining unrelated definitions of legality in the checker and simulator.
4. Define a proof-bearing candidate that binds its workload, configuration, layout, program, and model version to safety and correctness theorems.
5. Prove correctness for all allowed inputs. Numerical examples and random tests supplement this proof; they do not replace it.
6. Include successful termination and legal intermediate widths in the safety obligation. Input-dependent runtime checks alone cannot certify a candidate for every input.
7. Audit the axioms used by accepted theorems. Accepted proofs must not rely on `sorry`, `admit`, or candidate-specific unproved assumptions. Document the proof trust boundary.
8. Return structured failures with the relevant cycle, lane, address or register, and violated rule where applicable.

Distinguish invalid input, inadmissible configuration, malformed layout, illegal schedule, arithmetic failure, incomplete output, unverified candidate, and evaluator resource exhaustion. Resource exhaustion is an inconclusive evaluation, not proof that a candidate computes the wrong answer.

For this release, accepted candidates can be Lean definitions registered with their checked proofs. Arbitrary serialized programs may be inspected or simulated as unverified candidates. A JSON field asserting correctness must never confer verified status. Do not build an automatic proof-discovery service yet.

**Exit checks:** a proof-bearing tiny candidate evaluates successfully; deliberately invalid variants are rejected; a program that works on one test input cannot acquire an all-input correctness label without a proof.

### Milestone 7: Deliver the naive verified matrix-vector baseline

1. Build the ordinary row-by-row, column-by-column algorithm as a baseline generator that processes one output dot product at a time using explicit loads, arithmetic, waiting, and output stores.
2. Use only lane zero, a row-major layout, and signed 48-bit accumulation. Reload the vector operands for each row rather than adding cross-row reuse.
3. Prove a small reusable dot-product implementation lemma, then use it to establish the whole matrix-vector result. Prefer reusable reasoning to an enormous proof by enumeration of input values.
4. Check its layout, register usage, memory usage, schedule, intermediate widths, and output completion.
5. Evaluate zeros, identity-like matrices, mixed signs, negative and positive extrema, and deterministic generated inputs against the pure reference.
6. Produce an inspectable trace for a small fixture and a summary record for the full 16-by-16 workload.
7. Exercise the baseline on the permitted configurations as conformance checks. This is a fixed test collection, not a search procedure.
8. Register it as `matvec-naive-v1` and save its configuration, layout, cycle count, and event counts. Add the energy score once Milestone 8 supplies the scoring implementation.

**Exit checks:** the runnable `matvec-naive-v1` candidate has all-input safety and correctness proofs; its reported counters and completion boundary agree with an independent hand calculation or a small independently checked fixture; the baseline can be selected and reproduced by identifier.

### Milestone 8: Add interchangeable objectives and evaluation results

Implement scoring as a pure function of the shared execution record. Scoring must not alter the program, configuration, timing rules, or execution.

The initial objectives both have direction `minimize`:

| Objective | Score | Unit |
| --- | --- | --- |
| `latency-v1` | Elapsed cycles through completion | cycles |
| `energy-proxy-v1` | The fixed activity-and-duration formula below | abstract energy units |

Keep latency in cycles initially. Converting to seconds requires an explicit clock-frequency assumption; omit a physical frequency claim from the initial result.

Use a transparent toy energy profile:

```text
energy = cycles * (base_per_cycle
                   + L * lane_per_cycle
                   + allocated_BRAM36 * bram_per_cycle)
       + loads * load_cost
       + stores * store_cost
       + additions * add_cost
       + multiplications * multiply_cost
       + multiply_adds * multiply_add_cost
       + register_reads * register_read_cost
       + register_writes * register_write_cost
```

Start with positive integer coefficients: base, lane, BRAM, register-read, register-write, and addition costs are 1; load and store costs are 4; multiplication costs 8; multiply-add costs 9. These values are intentionally hypothetical and versioned. They provide a duration, provisioned-resource, arithmetic, and data-movement trade-off; they are not measurements or calibrated estimates in joules or watt-hours.

Count multiply-add as one event charged by its own coefficient, not also as a separate multiplication and addition. Include issued operand reads, successful destination writes, and explicit transfers consistently. Specify whether accesses to the constant-zero register are charged; charge them as operand reads in this profile. Pending pipeline details are abstracted into these operation costs.

A newly added objective may use the same counters or a trace-derived statistic. Its introduction must not require changing which executions are legal. A changed coefficient set is a distinct objective profile; never silently alter the meaning of existing results.

The result should include verification status, model and workload versions, candidate identifier, configuration, input identifier, execution summary, objective identifier, score unit, coefficients where applicable, and score breakdown. Invalid or unverified evaluations must not receive an accepted optimization score.

Evaluate `matvec-naive-v1` under both objectives and save the two baseline results. Every subsequent computation must supply equivalent baseline records under the available objectives.

**Exit checks:** both objectives score the same verified execution record; switching objectives leaves the record unchanged; recomputing the formula from the breakdown gives the reported score. Two manually constructed, equivalent fixtures exhibit different resource/activity costs, including a fixture pair where latency and energy prefer different candidates. No search algorithm is needed to construct these examples.

A concrete fixture is the computation `(a * b, c * d)`. Each multiplication uses two loads, one multiply, and one store. Running the two sequences serially on one lane and one bank takes 12 cycles; running them simultaneously on two lanes of an eight-lane, eight-bank configuration takes 6 cycles. Both execute four loads, two multiplies, two stores, six register reads, and six register writes. Under the stated coefficients, their scores are 172 and 202 energy units respectively. Thus the second is faster while the first uses fewer modeled energy units. These hand-built fixtures demonstrate scoring behavior, not design optimality.

### Milestone 9: Add matrix-matrix multiplication through the same interfaces

1. Add its input/output description and naive baseline candidate using the existing matrix-matrix reference specification. Use the conventional `i, j, k` loop order, a row-major layout, one active lane, and no tiling or reuse between output entries.
2. Reuse the dot-product reasoning where possible. Supply all-input correctness and safety proofs for the full operation.
3. Use the same configuration family, machine transitions, memory rules, numerical limits, records, and objective implementations.
4. Check zero, identity, mixed-sign, and extreme-value cases against the pure reference.
5. Verify that adding the workload requires no matrix-specific branches in the simulator or objective functions.
6. Register it as `matmul-naive-v1`. Save its configuration, layout, and reproducible latency and energy results alongside those for `matvec-naive-v1`.

**Exit checks:** both matrix workloads have selectable, runnable naive baselines with all-input safety and correctness proofs and saved results under both objectives. They use the same evaluator. The existing matrix-vector fixtures and scores remain unchanged.

### Milestone 10: Finish the public interface and handoff documentation

1. Provide a small command-line interface to list workloads, list registered example candidates, evaluate one candidate, select an objective, and optionally export a trace.
2. Use structured machine-readable results as well as a concise human-readable summary. A versioned JSON result is sufficient; a database or web service is unnecessary.
3. Document how to add a workload, add an objective, construct and prove a candidate, and interpret a rejected execution.
4. Document the future strategy boundary: a strategy may construct candidates, submit them for checking, read failures and scores, and retain its own history. It receives no authority to modify workload specifications, hardware rules, or scoring profiles.
5. Leave strategy implementation for later. Do not add a scheduler that chooses improvements, an LLM client, search orchestration, a policy framework, or a strategy benchmark.
6. Run the complete build and regression checks from a clean checkout. Record toolchain versions, commands, and example results.

**Exit checks:** a new contributor can reproduce both workloads, rescore a fixed candidate under either objective, inspect a failure, and understand where a future search strategy connects.

## 6. Required regression coverage

Maintain a compact suite with independently understandable expected results:

| Area | Required examples |
| --- | --- |
| Configuration | All allowed choices; invalid lane/bank counts; resource allocation rounding |
| Storage | Out-of-bounds addresses, layout aliasing, uninitialized reads, input mutation, zero-register writes |
| Timing | Exact one-cycle memory and three-cycle arithmetic behavior; issue and writeback conflicts |
| Memory ports | Two valid accesses; rejected third access; rejected same-address read/write; valid read/read |
| Arithmetic | Signed endpoints, invalid multiplicand width, overflow, mixed-sign multiply-add |
| Completion | Pending arithmetic, pending output stores, missing outputs, explicit waiting |
| Verification | A verified candidate; a merely tested candidate; proof bindings cannot be substituted |
| Naive baselines | Both baseline identifiers resolve to executable verified programs; saved latency and energy results are reproducible |
| Objectives | Exact breakdowns, event accounting, unchanged execution when rescoring, separate units |
| Extensibility | Matrix-matrix addition leaves machine rules and prior fixture results unchanged |
| Reproducibility | Stable versions, deterministic summaries, explicit resource-exhaustion status |

Test failure behavior as carefully as successful execution. Prefer a small test that would expose a particular semantic mistake over many tests that repeat the implementation.

## 7. Completion checklist

- [x] The pinned Lean project builds from a clean checkout.
- [x] The Arty A7-100T reference and every modeling assumption are documented.
- [x] The allowed configuration family and resource accounting are executable and checked.
- [x] Arithmetic, storage, scheduling, initialization, and completion have unambiguous semantics.
- [x] Simulation and proof obligations share the same transition rules.
- [x] Accepted matrix-vector and matrix-matrix examples are proved safe and correct for all allowed inputs.
- [x] Both computations include a naive executable baseline, its correctness and safety proofs, and versioned results for latency and energy.
- [x] Invalid and unverified candidates cannot receive accepted scores.
- [x] Latency and energy are separate interchangeable objectives over shared execution records.
- [x] Energy results are labeled as abstract units, with visible fixed coefficients.
- [x] Manual examples demonstrate meaningful differences between the objectives.
- [x] New workloads and objectives can be added without changing machine semantics.
- [x] The evaluation interface is documented for future interchangeable search strategies.
- [x] No optimization strategy or autonomous AI loop was implemented as part of Sections 1–8; Section 10 adds the separately approved loop.

## 8. Instructions for the coding agent

Work on one milestone at a time. Before implementing it, read its dependencies, deliverables, and exit checks. After implementing it, run the relevant checks, summarize the evidence, and mark its completion accurately.

Choose ordinary data types, explicit functions, and small reusable proofs. Keep the trusted machine and evaluator independent from future proposal-generating code. A convenient representation must not quietly add memory ports, erase data transfers, ignore overflow, or move the completion boundary.

If implementation exposes a contradiction in the proposed contract, record the smallest correction and its effect on existing examples before proceeding. Once a contract version is established, preserve its semantics and label incompatible revisions explicitly. Never change a rule solely to make a failing candidate pass.

Stop when the completion checklist is satisfied. Exploring how AI should optimize over this foundation is a subsequent planning and implementation task; Section 9 fixes the workloads it must use.

## 9. Next phase: workloads beyond matrix-vector

Sections 1–8 are complete. This section scopes the workloads for the optimization experiments that follow. It changes no machine rule, and its checklist is separate from Section 7.

### Why matrix-vector alone cannot carry the experiment

`docs/candidates/matvec-grid-exchange-v1.json`, designed by hand in three attempts, simulates in 79 cycles against 1,344 for `matvec-naive-v2`. A counting argument puts the floor at about 77–78 instructions on the busiest lane, so 79 cycles is essentially optimal. On the default configuration one idea decides latency: split the work evenly over the lanes and count issue slots. The 3-cycle latency and the bank ports stop binding once accumulator chains are interleaved and the layout is bank-aware.

A search loop therefore has almost nothing left to find there. Keep matrix-vector at `(8, 8)` as a smoke test and as the first certification target, not as the measured experiment.

### Tasks, in order

Each task isolates one freedom the brief gives the agent. All use the existing five instructions.

| # | Task | Input domain | What it tests |
| --- | --- | --- | --- |
| 1 | Matrix-matrix product, `C = A·B` (existing `matmul-16x16-signed16-v1`) | all entries signed 16-bit | Scale and operand reuse |
| 2 | Polynomial evaluation, `p(x_i) = Σ c_k·x_i^k` for `k ≤ 7` at 16 points | `c_k` in `[-8, 7]`, `x_i` in `[-4, 3]` | Rearranging arithmetic under width limits |
| 3 | Symmetric product, `G = A·Aᵀ` | all entries signed 16-bit | Sharing intermediates |
| 4 | Two-stage linear map, `y = B·(A·x)` | `A`, `x` in `[-45, 45]`; `B` signed 16-bit | Dependent stages and data movement |

1. **Matrix-matrix product.** 4,096 products instead of 256. Every input value feeds 16 products, but a lane has 15 writable registers and each load costs an issue slot, so register allocation and reload order decide the instruction count. It also tests whether certification scales to thousands of instructions.
2. **Polynomial evaluation.** 24 inputs, 16 outputs, `|p| ≤ 170,391`. Horner's rule uses the fewest multiplications, but its running value is a multiplicand and can reach 42,596, breaking the signed 16-bit rule. This happens only when a point equals `-4`, for 6.5% of coefficient choices there: about 6% of uniformly random inputs, and none of the uniform endpoint fixtures. Horner must therefore be rejected, although a small fixture set usually passes it. The legal forms cost more multiplications: explicit powers (largest multiplicand 16,384) and Estrin's scheme (largest 663), which also shortens the dependency chain from seven steps to three. Latency and energy can therefore prefer different programs. The naive baseline is the explicit-power form, one point at a time.
3. **Symmetric product.** 256 inputs, 256 outputs. `G[i][j] = G[j][i]`, so only 136 dot products are distinct; each of the other 120 outputs costs one extra store of a value already in a register. The naive baseline computes all 256. Exploiting the symmetry is a genuine algebraic step, so the certificate must prove more than a reordering of the same operations.
4. **Two-stage linear map.** 528 inputs, 16 outputs. The bound 45 is the largest for which every intermediate `t = A·x` fits a signed 16-bit multiplicand: `16·45² = 32,400`, while 46 gives 33,856. Stage two cannot start before its `t` entries exist, and each entry is produced on one lane but needed for every output row, so intermediates or partial sums must travel through memory. This is the closest shape to layered inference in TinyTPU that the current instructions can express.

Do not add tasks that need a new primitive. Activations, normalization and softmax need comparison, shifts or division, and so a new model version.

### Rules for every task

- **Baseline first.** Add the specification, scalar adapter and a certified naive baseline before any optimization, as Section 1 requires.
- **Three reference points per instance.** Record the certified naive baseline, a hand-built reference schedule (it may be unverified if labeled so) and a counting lower bound. Report results as the share of the naive-to-floor gap closed. If the hand-built reference already sits at the floor, the instance is a smoke test and is reported as such.
- **Pin the configuration for latency.** An instance is a workload, a configuration and an objective; a candidate using another configuration is rejected for that instance. Run each task on `(8, 8)`, on `(8, 1)` where memory binds (two accesses per cycle in total) and on `(2, 8)` where compute binds. Under `energy-proxy-v1` leave the configuration free, because provisioning is part of that trade-off.
- **Extreme fixtures, and held-out inputs.** Fixtures include the endpoints of the allowed domain. For the polynomial task, give the optimizer only fixtures on which Horner stays legal, and keep inputs that break it for a held-out check.
- **Record every proposal.** Record structural validity, fixture results, certification outcome and objective improvement for accepted candidates. Distinguish fixture-passing candidates refuted by a counterexample from candidates left uncertified by conservative analysis or resource limits. Only the former demonstrate bugs missed by the fixtures.
- **Compare with a heuristic.** Use the existing greedy list scheduler as a second baseline before claiming an improvement.

### Prerequisite

The reusable symbolic checker is implemented and proved sound against the
existing machine. It certifies `matvec-grid-exchange-v1` and rejects its tested
mutants. The resolved choices are in [docs/decisions.md](docs/decisions.md);
commands and limits are in [docs/certification.md](docs/certification.md).

### Checklist

- [x] Certification path chosen, implemented and able to certify `matvec-grid-exchange-v1`.
- [x] Scheduling-heuristic baseline available for every instance.
- [x] Matrix-matrix product: hand-built reference and lower bound recorded on the three pinned configurations.
- [x] Polynomial evaluation: specification, certified naive baseline and a rejected Horner candidate.
- [x] Symmetric product: specification, certified naive baseline and a certified candidate that uses the symmetry.
- [x] Two-stage linear map: specification, certified naive baseline and reference points.
- [x] Every instance reports gap closed, proposals certified, and proposals that passed fixtures but failed certification.

Implementation note (2026-11-22): the initial Section 9 run preceded the
certification decision. The subsequent implementation adds the general checker,
one-time reference proofs for all seven workloads, bounded diagnostics and
portable kernel-checked artifacts. Section 10 implements the subsequently approved loop.

See [the experiment guide](docs/experiments.md) and
[the recorded results](docs/results/section9-v1/summary.md). The run records 232
proposals across 16 instances, with 77 certified evaluations and three Horner
proposals that pass public fixtures but are refuted on an allowed held-out input.
The other 152 evaluations were deferred in that historical run; they have not
been retroactively recertified or counted as failed proofs. Counting floors use
compulsory I/O and are conservative.

## 10. Minimal sequential LLM search

Approved on 2026-11-22: build the simplest useful propose/check/repeat loop over
the existing blocks, with a maximum of 100 attempts and a selectable provider
and model. Preserve all attempts and feedback for analysis, while keeping the
next prompt bounded. See [the search guide](docs/search.md) and
[recorded trade-offs](docs/decisions.md#minimal-search-loop-sequential-proposals-and-bounded-memory).

- [x] One model call per attempt, fresh prompt, compact history and notebook.
- [x] Generator programs execute in restricted Docker containers.
- [x] Reuse simulation, all-input certification and the existing accepted-score API.
- [x] Only a certified improvement replaces the original certified baseline.
- [x] Save prompts, provider responses, candidates, traces, proofs, scores and failures.
- [x] Resume without repeating completed or interrupted model calls.
- [x] Exercise 100 attempts offline, real Docker/Lean integration and mocked provider adapters.

This harness finds the best certified design among its attempts. It does not
claim a global optimum or add a new benchmark result to the historical ledger.

### Independent batch repeats (2026-11-23)

- [x] Fixed five-model matrix with five seeds and 50 attempts per loop.
- [x] At most five independent processes; every loop keeps its own bounded memory.
- [x] Record seeds and API support, all run archives, launch logs and a hash inventory.
- [x] Prepare without launching; resume unfinished loops without repeating consumed slots.
- [x] Offline tests for planning, concurrency, partial failure, cancellation and resume.
- [x] Complete the ten-call smoke test (two attempts per model) and audit its records.
- [ ] Launch the full 1,250-attempt experiment only after the user's next approval.
