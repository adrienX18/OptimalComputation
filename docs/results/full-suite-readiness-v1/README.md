# Full workload suite readiness

**Unfinished checkpoint (2026-11-23T21:14:33.388633+00:00):** the live smoke test is still running, with 11/240 attempts complete. Final smoke validation and its archive audit are unfinished. The full campaign has not been prepared or launched. See [HANDOFF.md](../../../HANDOFF.md) and the [status snapshot](checkpoint-status.json).

## Scope

The suite covers all four measured Section 9 workloads: matrix multiplication, degree-seven polynomial evaluation, Gram product and a two-stage linear map. Each has three latency cases with fixed `(lanes,banks)` settings `(8,8)`, `(8,1)`, `(2,8)`, plus one energy case that can choose any supported configuration. Matrix-vector remains the separate validation workload defined in the plan.

The five models are Fable, Opus, Sonnet, Astra and Sol, with exact provider IDs in [`search.suite.json`](../../../configs/search.suite.json). The full plan is **16 cases × 5 models × 5 seeds × 50 attempts = 20,000 attempts in 400 loops**. Seeds are 11, 23, 37, 53 and 71. The smoke run uses seed 11 and three attempts per case/model: 80 loops, 240 attempts.

## Validation

- Full `scripts/validate.py` passed, including proof-axiom audits and byte-identical reproduction of historical results.
- Provider adapter tests passed. Batch tests passed with the final five-worker configuration.
- All 16 known-design tests passed through real Docker generation, five public input simulations, kernel certification and objective scoring.
- Energy tests deliberately use `(4,4)` hardware; the same artifact is rejected by the pinned `(8,8)` latency configuration.
- The offline archive audit verified 3,554 files and restored all 80 compressed traces byte for byte. All recorded kernel intervals were nonoverlapping.
- The archive auditor also passed against the previous 1,250-attempt campaign (83,816 files).

Detailed evidence: [offline audit](offline-audit.json), [validation log hashes](validation-evidence.json), [final source hashes](source-hashes.json).

| Case | Certified score | Unit | Active kernel seconds |
|---|---:|---|---:|
| gram-energy | 83,293 | abstract energy units | 74.5 |
| gram-latency-2x8 | 4,565 | cycles | 72.7 |
| gram-latency-8x1 | 2,479 | cycles | 88.1 |
| gram-latency-8x8 | 1,343 | cycles | 78.2 |
| matmul-energy | 116,421 | abstract energy units | 118.3 |
| matmul-latency-2x8 | 5,408 | cycles | 118.4 |
| matmul-latency-8x1 | 2,824 | cycles | 134.9 |
| matmul-latency-8x8 | 1,372 | cycles | 126.0 |
| polynomial-energy | 4,181 | abstract energy units | 2.6 |
| polynomial-latency-2x8 | 240 | cycles | 2.5 |
| polynomial-latency-8x1 | 103 | cycles | 2.8 |
| polynomial-latency-8x8 | 63 | cycles | 2.8 |
| two-stage-energy | 19,032 | abstract energy units | 60.3 |
| two-stage-latency-2x8 | 1,060 | cycles | 61.6 |
| two-stage-latency-8x1 | 542 | cycles | 61.8 |
| two-stage-latency-8x8 | 536 | cycles | 63.3 |

These are known reference designs used to test the pipeline, not model-search results. Timings describe this machine and are not hardware-performance scores.

## Decisions and limits

Five search loops can run concurrently, but a checkout-wide OS lock permits only one memory-heavy Lean kernel check at a time. Two simultaneous large matrix proofs caused paging and timeouts; serialized checks passed. Queue time is archived separately and does not consume the 600-second active proof budget. The batch wall-time allowance includes time spent behind other workers.

The verifier now emits a directly typed candidate and still proves its exact binding to the submitted raw artifact. It also uses indexed symbolic state, faster proved-equivalent structural checks and sorting, linear polynomial addition, and a sufficient proof boundary budget derived from completion cycles. No native-evaluation shortcut, custom axiom, machine rule or mathematical domain was added. Deliberately substituted candidates fail the binding check.

Limits remain explicit: 32,768 output tokens, 48,000 prompt bytes, 8,000 generator-code bytes, 30 seconds in the generator and 600 seconds per verification phase. A timeout or conservative range-check rejection is inconclusive, not a proof of mathematical incorrectness. Three attempts test operation and archiving; they do not establish model rankings or search convergence.

The live pilot has exposed an important limit: an exact copy of the already-certified matrix baseline can exhaust the fresh 600-second symbolic proof budget. The naive harness rechecks proposals, while retaining the certified incumbent baseline. Such timeouts must be analyzed separately from invalid designs; they consume search attempts and can make the full campaign substantially slower. An isolated proof-reuse probe was not adopted because it did not establish a safe speedup.

Fixed seeds stabilize local generation and label independent repeats. Provider sampling, especially Anthropic sampling without a seed parameter, is not guaranteed reproducible. Complete requests, raw responses, seeds, source snapshots and feedback are retained so the actual experiment can be inspected.

Two early matrix checks predate extra queue-journaling fields, the lock regression test and the larger outer wait allowance. Their Lean source hashes match the final verifier; differences are listed in the offline audit. The live smoke run uses the exact final source hashes for every case.

## Raw archives

- `runs/suite-serial-kernel-20261123`: four successful matrix checks.
- `runs/suite-other-cases-ready-20261123`: twelve successful checks for the other workloads.
- `runs/suite-readiness-checks-20261123`: complete regression logs and historical-archive audit.
- `runs/suite-smoke-20261123`: live smoke run, all 80 loops and their attempts.

Raw run directories remain local and Git-ignored. This folder tracks compact evidence; it does not replace the complete archives. Earlier diagnostic runs, including failed timeout tests, are preserved under `runs/`.

## Launch gate

The full campaign still requires the user’s go. Its prepared manifest and the final live-smoke audit will be recorded here after the smoke run completes.
