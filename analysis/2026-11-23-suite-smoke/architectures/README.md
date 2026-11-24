# Preliminary workload architecture comparisons

Each example is the lowest certified final latency among the five models for
its workload at eight lanes/eight banks. All are seed 11, attempt 3. These are
selected observed designs, not claims of general model superiority.

| Workload | Winner | Baseline → winner cycles | Baseline → winner instructions | Evidence | Figure |
| --- | --- | ---: | ---: | --- | --- |
| Matrix multiplication | Astra | 21,504 → 933 | 12,800 → 7,376 | [Files](matmul/) | [PNG](../figures/06_matmul_architecture.png) · [SVG](../figures/06_matmul_architecture.svg) · [PDF](../figures/06_matmul_architecture.pdf) |
| Gram product | Astra | 22,016 → 478 | 13,312 → 3,712 | [Files](../walkthrough/) | [PNG](../figures/05_winner_architecture.png) · [SVG](../figures/05_winner_architecture.svg) · [PDF](../figures/05_winner_architecture.pdf) |
| Two-stage linear map | Sol | 2,720 → 162 | 1,632 → 1,280 | [Files](two-stage/) | [PNG](../figures/07_two_stage_architecture.png) · [SVG](../figures/07_two_stage_architecture.svg) · [PDF](../figures/07_two_stage_architecture.pdf) |

The figures show complete saved issue timelines. Left and right use different
time scales; dense baseline events form an overview at normal display size.
All individual instructions remain in `baseline/candidate.json` and
`winner/candidate.json`. Colors describe issue events, not full operation duration.
Algorithm boxes summarize the inspected source; counts and output formulas were
cross-checked directly against the schedules and stored certificate records.

`winner/request.json` is the actual input to the selected model call. Its baseline
field contains the score, full layout, instruction count, first five instructions
and last two instructions. The full baseline was also available to generated
Python through `candidate_tools.baseline()`. The figures are retrospective
visualizations of the artifacts, not pictures sent to the models.

Regenerate the evidence from local archives, then render from the tracked exports:

```sh
python3 analysis/build-walkthroughs.py
/tmp/optimal-plots-venv/bin/python analysis/plot-walkthroughs.py
```

The first command checks source inventory hashes, candidate/certificate bindings,
successful kernel exits, instruction counters and symbolic output formulas.
Neither command calls a model, runs generated Python, reruns Lean proofs or
launches an experiment. Plot dependencies are pinned in
[requirements-plots.txt](../requirements-plots.txt); input hashes and layout checks
are recorded in [figure provenance](../figures/walkthrough-provenance.json).
