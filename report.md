# OptimalComputation: LLM search with Lean-certified correctness

*Preliminary research report · experiments recorded 23–24 November 2026*

**LLMs propose faster programs; Lean checks their correctness.** This repository
combines a formal accelerator model, workload specifications and a simple search
loop. A completed polynomial study reached **30 versus 1,520 modeled cycles**;
three additional workloads have preliminary results. These are model results,
not FPGA measurements or proofs of optimality.

For direct inspection of the implementation and evidence, see
[DEEP_DIVE.md](DEEP_DIVE.md): exact source excerpts, pinned file/line links,
the certification proof chain, and a complete model-exchange walkthrough.
The [follow-up deep dive](DEEP_DIVE_2.md) explains exactly how candidates become
certificates, what is proved each time, model/tool trace availability, and the
measured time and size of the proofs, with complete certificate and error examples.

## 1. The machine being optimized

`arty-model-v1` is an abstract accelerator inspired by the Arty A7-100T.
A candidate defines memory layout, registers and a **static schedule** assigning
instructions to lanes and cycles.

| Component | Rules |
| --- | --- |
| Parallelism | 1, 2, 4 or 8 lanes; one instruction issued per lane per cycle |
| Memory | 4,096 64-bit slots; 1, 2, 4 or 8 banks; two accesses per bank per cycle |
| Registers | Per lane: `r0 = 0`, 15 writable signed48 registers, three pending instructions maximum, one writeback/cycle |
| Operations | Load/store: one cycle. Add, multiply and multiply-add: three cycles |
| Arithmetic | Signed16 multiplicands; signed48 accumulators/results; overflow is invalid |
| Dependencies | Commit before issue; no uninitialized reads, pending-register hazards or conflicting writes |

Lean implements the [configuration][config], [instructions][instructions],
[arithmetic][arithmetic], [machine transition][machine] and
[candidate validation][candidate]. There are no runtime branches or automatic
stalls: conflicting schedules are rejected.

The [objectives][objectives] minimize completion cycles or a separate energy
proxy charging resources and activity. Latency experiments fix the hardware;
energy experiments may choose it. Physical implementation costs remain unmeasured.

## 2. What the LLM does, sees and learns from

The [harness][harness] repeats **propose → execute/check → return feedback**.
It starts from a certified naive baseline.

- **Input:** system instructions explain the machine and Python helpers. User
  context supplies the task, objective, hardware, seeds, budget, baseline summary,
  best/latest code, feedback, compact history and notebook.
- **Output:** JSON strings `idea`, `code` and `notes`. Python `build()` runs in
  constrained Docker to generate the layout and static schedule—not a Lean proof.
- **Feedback:** simulation errors, certification diagnostics or a certified score.
  Failures consume slots; only a strictly better certified candidate replaces
  the incumbent.

The [prompt builder][prompt] creates fresh requests, retaining best/latest code,
compact history and at most 2,000 notebook bytes. Older history is dropped if
necessary. Runs have independent memory; provider/model identifiers are configurable.

Example: Sol saw **35-cycle** feedback and proposed a **30-cycle** winner.
See its saved [request][request], [response][response], [feedback][feedback]
and [walkthrough][five-walkthrough].

## 3. What Lean certifies

Passing public test inputs is insufficient. The [certifier][certification] then:

1. Symbolically executes integer polynomials with proved interval bounds,
   checking machine legality and numeric widths.
2. Compares outputs with the workload's reference polynomials. The
   [soundness theorem][soundness] establishes legal termination and correct
   outputs on the ordinary machine **for every allowed input**.
3. Emits a closed Lean proof obligation. The [driver][driver] requires kernel
   checking, exact candidate binding and an axiom audit before acceptance.

The [verified candidate][verified] carries safety and correctness evidence;
Lean also computes its score. **“Not certified” need not mean “incorrect”:**
a concrete violation differs from an inconclusive bound or timeout. Feedback
preserves that distinction. Neither sampled success nor an LLM's claim is a proof.

## 4. Tasks

| Task | Required computation and input domain |
| --- | --- |
| Polynomial | Degree-seven polynomial at 16 points; coefficients in `[-8,7]`, points in `[-4,3]` |
| Matrix multiplication | `A × B`, both 16×16 with signed16 entries |
| Gram product | `A × Aᵀ`, 16×16 signed16 input; all 256 output entries |
| Two-stage linear map | `B × (A × x)`; 16×16 matrices and a 16-vector; `A,x` in `[-45,45]`, `B` signed16 |

References: [matrix multiplication][matmul], [other workloads][workloads].
Matrix-vector multiplication is an additional validation case, not the completed
five-model experiment.

## 5. Completed experiment: five-model polynomial search

**Five models × five seeds × 50 attempts = 1,250 slots**, on eight lanes/eight
banks, minimizing latency. Seeds were 11, 23, 37, 53 and 71. Models used medium
reasoning and a 32,768-token output cap; equal settings do not imply equal compute.

| Model | Final cycles across five repeats | Median |
| --- | --- | ---: |
| Fable 5.2 | 30, 30, 30, 30, 30 | 30 |
| Opus 5.5 | 30, 30, 30, 30, 30 | 30 |
| Sonnet 5.5 | 33, 35, 75, 67, 40 | 40 |
| Astra 6.2 | 30, 30, 30, 30, 30 | 30 |
| Sol 6.2 | 30, 30, 30, 30, 30 | 30 |

Four models tie at **50.7× baseline/winner latency**. There were 1,033 certified
submissions; 23/25 loops reached their final best by attempt ten. Repetition,
provider refusals and code-size failures limited later progress.
[Complete analysis][five-report].

![Polynomial search: all repeats and median best-so-far latency.][convergence-figure]

*Thin lines: repeats; heavy lines: medians. Bands: observed min–max, with at least
93.75% pointwise median coverage under independent, identically distributed runs;
not simultaneous bands.*

A representative Sol winner uses **224 instructions instead of 912**. It shares
coefficients across two points per lane, factors the polynomial to respect
signed16 multiplication, and overlaps independent work across eight lanes.

![Polynomial baseline versus a certified Sol winner: algorithm and actual schedule.][architecture-figure]

*Saved seed-11, attempt-2 design. The instruction grids use different time scales.
The algorithm diagram explains the same candidate whose score is reported.*

## 6. Preliminary experiments: three additional workloads

The completed **smoke test** covered four tasks at latency configurations
`(8,8), (8,1), (2,8)` and free-hardware energy: **16 cases × five models × one seed
× three slots = 240 slots**. There were 236 finished and four interrupted attempts.

Best observed eight-lane/eight-bank latency for the **three additional tasks**:

| Task | Baseline cycles | Best cycles | Model | Baseline / best |
| --- | ---: | ---: | --- | ---: |
| Matrix multiplication | 21,504 | 933 | Astra | 23.0× |
| Gram product | 22,016 | 478 | Astra | 46.1× |
| Two-stage linear map | 2,720 | 162 | Sol | 16.8× |

![Smoke-test results across all tasks, hardware settings and models.][smoke-figure]

*Each cell compares with its own baseline; higher is better. Stars mark
interruptions. Energy and latency stay separate. One seed cannot support
repeat-based confidence intervals or a general model ranking.*

**77/80 loops improved the baseline**; 35 improved on their last slot.
This establishes feasibility, not convergence. The larger suite experiment
remains unlaunched.

The comparisons below show the **full stored baseline and the best certified
candidate for each row above**, all from seed 11, attempt 3. Each model prompt
contained the baseline's score, full layout, instruction count and first five/last
two instructions; generated Python could load the complete baseline through
`candidate_tools.baseline()`. The figures reconstruct those artifacts afterward.

**Reading the schedules:** left and right use different time scales, but each
covers the entire execution. Colors identify issued instructions, not their full
duration. Dense baseline events are an overview at normal display size. These
are fixed artifacts, so no confidence intervals apply. [Source files and vector
figures][architecture-index] retain the complete schedules and provenance.

### 6.1 Matrix multiplication — Astra

The baseline computes one output at a time on lane 0. Astra assigns two output
rows to each lane, tiles columns to reuse `A` and `B` values, and overlaps loads,
arithmetic and stores. The number of products stays at 4,096; loads fall from
8,192 to 3,024. [Exact model input][matrix-request] · [Winning program][matrix-code].

![Matrix multiplication: full baseline and Astra winner schedules, algorithms and counts side by side.][matrix-architecture]

### 6.2 Gram product — Astra

The baseline computes all 256 ordered row-pair dot products serially. Astra
computes 136 distinct products across eight lanes and writes each off-diagonal
result to both symmetric positions, reusing loaded row values.
[Exact model input][gram-request] · [Winning program][gram-code] ·
[Detailed walkthrough][smoke-walkthrough].

![Gram product: full baseline and Astra winner schedules with exact output-to-lane maps.][gram-architecture]

### 6.3 Two-stage linear map — Sol

The baseline performs both matrix-vector products serially. Sol shares vector
loads across partial dot products, exchanges partial sums between paired lanes,
then computes two final output rows per lane. Both designs use 512 multiply-adds;
loads fall from 1,040 to 704. [Exact model input][two-stage-request] ·
[Winning program][two-stage-code].

![Two-stage linear map: full baseline and Sol winner schedules, algorithms and counts side by side.][two-stage-architecture]

## Evidence and limits

Prompts, responses, programs, diagnostics, scores and failures are retained
([smoke report][smoke-report], [complete smoke archive][smoke-data]). Fixed seeds
do not guarantee identical provider responses. Gains are against deliberately
naive baselines; neither physical speedups nor general model superiority are established.

<!-- Evidence links pin the existing repository snapshot; remote figures let this Markdown file travel on its own. -->
[config]: https://github.com/adrienX18/OptimalComputation/blob/cdcbe5e9734bf06f414e4fd5e6995311ce3c15ca/OptimalComputation/Hardware/Config.lean#L7
[instructions]: https://github.com/adrienX18/OptimalComputation/blob/cdcbe5e9734bf06f414e4fd5e6995311ce3c15ca/OptimalComputation/Hardware/Instruction.lean#L14
[arithmetic]: https://github.com/adrienX18/OptimalComputation/blob/cdcbe5e9734bf06f414e4fd5e6995311ce3c15ca/OptimalComputation/Hardware/Arithmetic.lean
[machine]: https://github.com/adrienX18/OptimalComputation/blob/cdcbe5e9734bf06f414e4fd5e6995311ce3c15ca/OptimalComputation/Hardware/Machine.lean#L223
[candidate]: https://github.com/adrienX18/OptimalComputation/blob/cdcbe5e9734bf06f414e4fd5e6995311ce3c15ca/OptimalComputation/Candidates/Program.lean#L153
[objectives]: https://github.com/adrienX18/OptimalComputation/blob/cdcbe5e9734bf06f414e4fd5e6995311ce3c15ca/OptimalComputation/Evaluation/Objectives.lean
[harness]: https://github.com/adrienX18/OptimalComputation/blob/cdcbe5e9734bf06f414e4fd5e6995311ce3c15ca/scripts/search.py#L193
[prompt]: https://github.com/adrienX18/OptimalComputation/blob/cdcbe5e9734bf06f414e4fd5e6995311ce3c15ca/scripts/harness/prompt.py#L76
[certification]: https://github.com/adrienX18/OptimalComputation/blob/cdcbe5e9734bf06f414e4fd5e6995311ce3c15ca/docs/certification.md
[soundness]: https://github.com/adrienX18/OptimalComputation/blob/cdcbe5e9734bf06f414e4fd5e6995311ce3c15ca/OptimalComputation/Certification/Checker.lean#L73
[driver]: https://github.com/adrienX18/OptimalComputation/blob/cdcbe5e9734bf06f414e4fd5e6995311ce3c15ca/scripts/certify.py#L149
[verified]: https://github.com/adrienX18/OptimalComputation/blob/cdcbe5e9734bf06f414e4fd5e6995311ce3c15ca/OptimalComputation/Evaluation/Verification.lean#L125
[matmul]: https://github.com/adrienX18/OptimalComputation/blob/cdcbe5e9734bf06f414e4fd5e6995311ce3c15ca/OptimalComputation/Workloads/MatMul.lean#L10
[workloads]: https://github.com/adrienX18/OptimalComputation/blob/cdcbe5e9734bf06f414e4fd5e6995311ce3c15ca/OptimalComputation/Workloads/ExperimentWorkloads.lean
[request]: https://github.com/adrienX18/OptimalComputation/blob/cdcbe5e9734bf06f414e4fd5e6995311ce3c15ca/analysis/2026-11-23-five-model-search/walkthrough/winner/request.json
[response]: https://github.com/adrienX18/OptimalComputation/blob/cdcbe5e9734bf06f414e4fd5e6995311ce3c15ca/analysis/2026-11-23-five-model-search/walkthrough/winner/response.json
[feedback]: https://github.com/adrienX18/OptimalComputation/blob/cdcbe5e9734bf06f414e4fd5e6995311ce3c15ca/analysis/2026-11-23-five-model-search/walkthrough/winner/feedback.json
[five-report]: https://github.com/adrienX18/OptimalComputation/blob/cdcbe5e9734bf06f414e4fd5e6995311ce3c15ca/analysis/2026-11-23-five-model-search/report.md
[five-walkthrough]: https://github.com/adrienX18/OptimalComputation/blob/cdcbe5e9734bf06f414e4fd5e6995311ce3c15ca/analysis/2026-11-23-five-model-search/report.md#inside-the-loop-actual-inputs-outputs-and-a-winning-design
[smoke-report]: https://github.com/adrienX18/OptimalComputation/blob/cdcbe5e9734bf06f414e4fd5e6995311ce3c15ca/analysis/2026-11-23-suite-smoke/report.md
[smoke-walkthrough]: https://github.com/adrienX18/OptimalComputation/blob/cdcbe5e9734bf06f414e4fd5e6995311ce3c15ca/analysis/2026-11-23-suite-smoke/report.md#inside-the-loop-actual-inputs-outputs-and-a-winning-design
[smoke-data]: https://github.com/adrienX18/OptimalComputation/releases/tag/suite-smoke-2026-11-23
[convergence-figure]: https://raw.githubusercontent.com/adrienX18/OptimalComputation/cdcbe5e9734bf06f414e4fd5e6995311ce3c15ca/analysis/2026-11-23-five-model-search/figures/03_convergence.png
[architecture-figure]: https://raw.githubusercontent.com/adrienX18/OptimalComputation/cdcbe5e9734bf06f414e4fd5e6995311ce3c15ca/analysis/2026-11-23-five-model-search/figures/12_winner_architecture.png
[smoke-figure]: https://raw.githubusercontent.com/adrienX18/OptimalComputation/cdcbe5e9734bf06f414e4fd5e6995311ce3c15ca/analysis/2026-11-23-suite-smoke/figures/01_quality.png
[architecture-index]: https://github.com/adrienX18/OptimalComputation/blob/9de5888e81d148772161ced59cb3d8dc1d92c97c/analysis/2026-11-23-suite-smoke/architectures/README.md
[matrix-request]: https://github.com/adrienX18/OptimalComputation/blob/9de5888e81d148772161ced59cb3d8dc1d92c97c/analysis/2026-11-23-suite-smoke/architectures/matmul/winner/request.json
[matrix-code]: https://github.com/adrienX18/OptimalComputation/blob/9de5888e81d148772161ced59cb3d8dc1d92c97c/analysis/2026-11-23-suite-smoke/architectures/matmul/winner/generator.py
[matrix-architecture]: https://raw.githubusercontent.com/adrienX18/OptimalComputation/9de5888e81d148772161ced59cb3d8dc1d92c97c/analysis/2026-11-23-suite-smoke/figures/06_matmul_architecture.png
[gram-request]: https://github.com/adrienX18/OptimalComputation/blob/9de5888e81d148772161ced59cb3d8dc1d92c97c/analysis/2026-11-23-suite-smoke/walkthrough/winner/request.json
[gram-code]: https://github.com/adrienX18/OptimalComputation/blob/9de5888e81d148772161ced59cb3d8dc1d92c97c/analysis/2026-11-23-suite-smoke/walkthrough/winner/generator.py
[gram-architecture]: https://raw.githubusercontent.com/adrienX18/OptimalComputation/9de5888e81d148772161ced59cb3d8dc1d92c97c/analysis/2026-11-23-suite-smoke/figures/05_winner_architecture.png
[two-stage-request]: https://github.com/adrienX18/OptimalComputation/blob/9de5888e81d148772161ced59cb3d8dc1d92c97c/analysis/2026-11-23-suite-smoke/architectures/two-stage/winner/request.json
[two-stage-code]: https://github.com/adrienX18/OptimalComputation/blob/9de5888e81d148772161ced59cb3d8dc1d92c97c/analysis/2026-11-23-suite-smoke/architectures/two-stage/winner/generator.py
[two-stage-architecture]: https://raw.githubusercontent.com/adrienX18/OptimalComputation/9de5888e81d148772161ced59cb3d8dc1d92c97c/analysis/2026-11-23-suite-smoke/figures/07_two_stage_architecture.png
