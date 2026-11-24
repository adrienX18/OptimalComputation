# Full workload suite readiness

**Ready for the user's launch go.** The smoke batch finished at 2026-11-24T00:44:56Z: **80/80 loops, 240 scheduled slots accounted for**, comprising 236 finished attempts and four interrupted slots. The complete archive passed its audit. The full campaign is prepared and **has not been launched**. See [HANDOFF.md](../../../HANDOFF.md) for the launch procedure. The earlier [checkpoint snapshot](checkpoint-status.json) is historical, not current status.

## Scope

The suite covers all four measured Section 9 workloads: matrix multiplication, degree-seven polynomial evaluation, Gram product and a two-stage linear map. Each has three latency cases with fixed `(lanes,banks)` settings `(8,8)`, `(8,1)`, `(2,8)`, plus one energy case that can choose any supported configuration. Matrix-vector remains the separate validation workload defined in the plan.

The five models are Fable, Opus, Sonnet, Astra and Sol, with exact provider IDs in [`search.suite.json`](../../../configs/search.suite.json). The full plan is **16 cases × 5 models × 5 seeds × 50 attempts = 20,000 attempts in 400 loops**. Seeds are 11, 23, 37, 53 and 71. The smoke run uses seed 11 and three attempts per case/model: 80 loops, 240 attempts.

## Validation

- Full `scripts/validate.py` passed for the frozen search/verifier source, including proof-axiom audits and byte-identical reproduction of historical results.
- Provider adapter tests passed. Batch tests passed with the five-worker configuration. After the smoke, an audit-only fix and four regression tests were added: all 12 batch/audit tests passed. Search, generation, simulation, certification and scoring code did not change after validation.
- All 16 known-design tests passed through real Docker generation, five public input simulations, kernel certification and objective scoring.
- Energy tests deliberately use `(4,4)` hardware; the same artifact is rejected by the pinned `(8,8)` latency configuration.
- The offline archive audit verified 3,554 files and restored all 80 compressed traces byte for byte. All recorded kernel intervals were nonoverlapping.
- The archive auditor also passed against the previous 1,250-attempt campaign (83,816 files).

Detailed evidence: [offline audit](offline-audit.json), [live archive audit](smoke-audit.json), [observations and timing](smoke-observations.json), [validation log hashes](validation-evidence.json), [frozen smoke source hashes](source-hashes.json), and [prepared launch source hashes](launch-source-hashes.json).

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

## Live smoke results

The audit verified **28,001 files**, including lossless reconstruction of **970 compressed traces**, saved source snapshots, requests and available raw responses, certificate/artifact bindings, objective scores and incumbent histories. It found **236 saved model responses**. Three API errors and one interrupted request account for slots without a response; three other interrupted slots do have saved responses. The maximum prompt was **25,238 bytes**, within the 48,000-byte limit.

| Outcome | Slots | Meaning |
|---|---:|---|
| Certified | 182 | Passed the verifier and received a score |
| Proposal error | 30 | 14 incomplete/content-filter responses, 10 code-size violations, 6 invalid JSON responses |
| Simulation failed | 14 | The proposed artifact failed a public simulation check |
| Range not proved | 6 | The conservative verifier could not establish the required numeric bounds |
| API error | 3 | Two 600-second Anthropic read timeouts and one Anthropic HTTP 502 |
| Kernel timeout | 1 | The proof did not finish within its active budget |
| Interrupted | 4 | Partial attempts retained after the connection restart |
| **Total** | **240** | **Three scheduled slots for each of 80 case/model loops** |

All 20 workload/model combinations produced at least one certified candidate. Seventy-seven of the 80 individual case/model loops did so; Opus retained its certified baseline in matrix multiplication at `(2,8)`, matrix energy, and Gram at `(2,8)`. These are operational observations, not model rankings. The energy path accepted choices including `(1,1)`, `(4,4)` and `(8,4)`, confirming that it is not pinned to the initial `(8,8)` configuration.

The connection restarted near the end of the run. The foreground batch subsequently stopped at 219 finished attempts. Resume skipped 72 completed loops, retained four in-flight attempts as `interrupted`, and finished the remaining scheduled slots. It did not reissue potentially billed calls. The four interrupted slots are censored observations, not incorrect designs, and must remain separate in later analysis. The audit helper was updated to recognize their intentionally partial records while retaining strict checks for finished attempts. The targeted regressions cover interruption before metadata, during a request, and after a saved response; interrupted records cannot claim certification or change the incumbent.

## Timing and capacity

Elapsed wall time was **3 hours 55 minutes 34 seconds**, including the interruption and recovery. Five independent search loops ran concurrently; one kernel proof ran at a time. All recorded kernel intervals were nonoverlapping.

| Workload | Recorded kernel checks | Median active seconds |
|---|---:|---:|
| Matrix multiplication | 45 | 122.7 |
| Polynomial | 43 | 3.9 |
| Gram | 46 | 82.9 |
| Two-stage | 50 | 59.0 |

These timings include terminated checks and measure host verification work, not the simulated hardware's performance. The archive inventory contains **0.98 GiB**; the machine had **256.7 GiB free** at the audit.

A simple planning scenario multiplies the smoke totals by `20,000 / 240`: **13.6 days of wall time and 81.7 GiB of archived data** for the full campaign on this machine with these settings. This is not a forecast, confidence interval or upper bound. It includes smoke startup/recovery overhead; longer searches can also produce more complex candidates, larger archives, different rejection rates and additional provider delays. Plan for a multi-day campaign, approximately two weeks at the observed rate, rather than treating it as an overnight job.

## Decisions and limits

Five search loops can run concurrently, but a checkout-wide OS lock permits only one memory-heavy Lean kernel check at a time. Two simultaneous large matrix proofs caused paging and timeouts; serialized checks passed. Queue time is archived separately and does not consume the 600-second active proof budget. The batch wall-time allowance includes time spent behind other workers.

The verifier now emits a directly typed candidate and still proves its exact binding to the submitted raw artifact. It also uses indexed symbolic state, faster proved-equivalent structural checks and sorting, linear polynomial addition, and a sufficient proof boundary budget derived from completion cycles. No native-evaluation shortcut, custom axiom, machine rule or mathematical domain was added. Deliberately substituted candidates fail the binding check.

Limits remain explicit: 32,768 output tokens, 48,000 prompt bytes, 8,000 generator-code bytes, 30 seconds in the generator and 600 seconds per verification phase. A timeout or conservative range-check rejection is inconclusive, not a proof of mathematical incorrectness. Three attempts test operation and archiving; they do not establish model rankings or search convergence.

The live smoke exposed an important limit: an exact copy of the already-certified matrix baseline can exhaust the fresh 600-second symbolic proof budget. The naive harness rechecks proposals, while retaining the certified incumbent baseline. Such timeouts must be analyzed separately from invalid designs; they consume search attempts and can make the full campaign substantially slower. An isolated proof-reuse probe was not adopted because it did not establish a safe speedup.

Fixed seeds stabilize local generation and label independent repeats. Provider sampling, especially Anthropic sampling without a seed parameter, is not guaranteed reproducible. Complete requests, raw responses, seeds, source snapshots and feedback are retained so the actual experiment can be inspected.

Two early matrix checks predate extra queue-journaling fields, the lock regression test and the larger outer wait allowance. Their Lean source hashes match the final verifier; differences are listed in the offline audit. The live smoke used the frozen hashes in `source-hashes.json` for every case. Only the audit helper and its regression tests changed afterward, as listed in the launch metadata.

## Raw archives

- `runs/suite-serial-kernel-20261123`: four successful matrix checks.
- `runs/suite-other-cases-ready-20261123`: twelve successful checks for the other workloads.
- `runs/suite-readiness-checks-20261123`: complete regression logs and historical-archive audit.
- `runs/suite-smoke-20261123`: completed smoke archive, all 80 loops and all scheduled slots, including partial interrupted records.

Raw run directories remain local and Git-ignored. This folder tracks compact evidence; it does not replace the complete archives. Earlier diagnostic runs, including failed timeout tests, are preserved under `runs/`.

## Launch gate

The full campaign is prepared in **`runs/suite-full-ready-20261123`** with 400 loops and 20,000 attempts, all at zero progress. Its manifest records code commit `f158b9a39cfabdcf3c33ab8258128d3879208b7a`. Its 514 inventoried files and exact case/model/seed matrix were verified. Preparation made no model calls.

Only `scripts/audit-search-batch.py` and its regression-test file differ from the smoke snapshot. The search and verifier source is identical. The earlier `runs/suite-full-20261123` preparation is preserved but superseded; its metadata is retained in [full-plan metadata](full-plan.json). Use the new prepared directory.

**The remaining gate is the user's explicit go.** The [handoff](../../../HANDOFF.md) provides a detached launch with stdin disconnected and stdout/stderr saved outside the immutable archive. This avoids coupling a long campaign to the interactive terminal connection. Nothing in this readiness work launched the full campaign.
