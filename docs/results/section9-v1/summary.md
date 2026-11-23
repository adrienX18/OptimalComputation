# Section 9 results

232 proposals; 77 certified; 3 passed public fixtures but were refuted on held-out inputs.

General parallel certification remains deferred. All naive baselines below are certified.

## Latency

Greedy and hand-reference timings are unverified observations. The floor counts compulsory I/O.

| Task | Lanes, banks | Naive | Greedy | Hand reference | Floor | Hand gap closed |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| matmul | 8, 8 | 21,504 | 2,694 | 1,372 | 96 | 94.0% |
| matmul | 8, 1 | 21,504 | 4,245 | 2,824 | 384 | 88.4% |
| matmul | 2, 8 | 21,504 | 10,752 | 5,408 | 384 | 76.2% |
| polynomial | 8, 8 | 1,520 | 204 | 63 | 5 | 96.2% |
| polynomial | 8, 1 | 1,520 | 312 | 103 | 20 | 94.5% |
| polynomial | 2, 8 | 1,520 | 760 | 240 | 20 | 85.3% |
| gram | 8, 8 | 22,016 | 2,756 | 1,343 | 64 | 94.2% |
| gram | 8, 1 | 22,016 | 4,499 | 2,479 | 256 | 89.8% |
| gram | 2, 8 | 22,016 | 11,008 | 4,565 | 256 | 80.2% |
| two-stage | 8, 8 | 2,720 | 350 | 536 | 68 | 82.4% |
| two-stage | 8, 1 | 2,720 | 592 | 542 | 272 | 89.0% |
| two-stage | 2, 8 | 2,720 | 1,360 | 1,060 | 272 | 67.8% |

## Energy

All values use abstract energy-proxy units. The hand reference is the lowest diagnostic projection among its sixteen configurations; it is not an accepted score.

| Task | Certified naive at 8,8 | Best hand projection | Floor |
| --- | ---: | ---: | ---: |
| matmul | 634,112 | 107,621 | 5,472 |
| polynomial | 44,128 | 3,679 | 285 |
| gram | 649,472 | 74,703 | 3,648 |
| two-stage | 80,224 | 19,032 | 3,876 |

[Full records](summary.json) · [Proposal ledger](proposals.jsonl) · [Methods and proof boundary](../../experiments.md)
