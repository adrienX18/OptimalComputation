# Figure methods and limitations

The figures describe one fixed polynomial task, one hardware configuration and
five repeats of each model. The **run**, not the individual attempt, is the unit
for uncertainty. Attempts share code and feedback, so treating 250 attempts as
250 independent observations per model would understate uncertainty.

## Median intervals with only five repeats

Continuous and fractional run-level summaries show every run, the sample median
(black diamond), and an interval from the smallest to the largest observed run.
Under independent, identically distributed runs, this is a **93.75% distribution-
free confidence interval for the population median**. For a continuous
distribution, either all five observations fall below the median or all five
fall above it with probability `2 × (1/2)^5`; the coverage is therefore
`1 − 2/32 = 0.9375`. Ties can make coverage conservative. This is the standard
[order-statistic construction for quantile intervals](https://nvlpubs.nist.gov/nistpubs/TechnicalNotes/NIST.TN.2119.pdf).

That unusual confidence level is intentional. With five observations, the full
observed range does **not** justify a finite, distribution-free 95% median
interval. We use its actual coverage instead of silently calling it 95%, assuming
normality, or presenting a narrow small-sample bootstrap interval as reliable.
Small-sample bootstrap percentile intervals can under-cover; see
[Hesterberg's methodological discussion](https://arxiv.org/abs/1411.5279).

These are intervals for the **median**, not the mean, standard deviation,
standard error, or the range of a future observation. In trajectory plots the
same calculation is made separately at each attempt: coverage is **pointwise**,
not simultaneous across an entire curve, all models, or all figures. No
multiple-comparison adjustment or significance test is performed.

Identical observed values give a collapsed interval. This is a property of this
small observed sample, not proof of deterministic behavior, zero future risk,
or global optimality. Every repeat remains visible through seed offsets/markers,
or is explicitly labeled as overlapping in trajectory plots.

## Run-level success intervals

Figure 2c defines success as reaching a certified score of at most 30 cycles by
attempt 50. Its denominator is **five runs per model**, not 250 attempts. The
points show observed fractions; whiskers are **two-sided 95% Clopper–Pearson
binomial intervals**, computed with
[`scipy.stats.binomtest(...).proportion_ci(method='exact')`](https://docs.scipy.org/doc/scipy/reference/generated/scipy.stats._result_classes.BinomTestResult.proportion_ci.html).
For five successes out of five, the interval is approximately 47.8–100%; for
zero out of five, 0–52.2%. Thus even 5/5 success leaves substantial uncertainty.

The 30-cycle threshold was selected after seeing the experiment and is explicitly
exploratory. Binomial interpretation assumes independent comparable runs with a
common success probability. The median intervals likewise assume independent,
exchangeable runs within a model. Fixed prompt seeds, shared hardware, provider
changes and scheduling can weaken those assumptions. The intervals quantify
within-task repeat variability under those assumptions; they do not generalize
to other tasks or prove superiority between providers.

## What does not get an interval

The timeline, archive accounting, outcome counts, instruction counts, individual
schedules, pooled distinct-structure counts, and sums of stored dollar estimates
are descriptive records of this completed batch. They are shown without invented
sampling intervals. The full outcome sequence is displayed without smoothing;
the code-size scatter likewise shows dependent attempts, not independent draws.

Figures 4 and 9 deliberately use different timing summaries. Figure 4 includes
all attempt work until the first attainment of the eventual best; it excludes
baseline initialization and queueing. Sonnet's target is its own final result,
not 30. Figure 9 plots each run's total API time, output tokens and within-run
median call time. The report's resource table retains its original totals and
pooled median call times, which need not equal the median of five run medians.

“First eventual best” and the count of attempts after it are retrospective.
They do not identify a stopping rule that was available online. Structural
uniqueness ignores only the candidate identifier and serialization order;
register names, schedules and layout remain significant. The pooled and
within-run diversity measures therefore have different denominators and scopes.

Reported tokens may omit usage for the three API errors. Missing dollar prices
are labeled **N/A**, never zero. SDK estimates are not billing receipts. The
pointwise prompt bands use all five runs. Code sizes are available only when a
response contains parseable JSON with a string `code`; refusals and unparseable
replies are not assigned a zero size.

## Reproduction and audit trail

1. `analyze.py` verifies the original archive and exports six small data files.
   `attempts.csv` adds individual numeric measurements, `timeline.csv` records
   process spans, and `winner-schedules.json` saves the two illustrated schedules.
   No raw archive is modified and no new model calls are made.
2. `plot.py` can render solely from the tracked data files; the 979 MB raw archive
   is not required for that step. It emits 240-dpi PNG for Markdown and vector
   SVG/PDF for scaling or publication. Model colors are consistent; seed markers
   distinguish coincident observations. Logarithmic axes are labeled explicitly.
3. `figures/intervals.csv` records all 555 plotted interval estimates, methods,
   sample sizes, coverage levels and bounds. `figures/provenance.json` binds the
   plots to data hashes, script hashes, package versions and the original source
   revision. Fixed metadata and the absence of randomized rendering permit
   byte-identical regeneration with the pinned plotting environment. The complete
   plotting dependency set is in `requirements-plots.txt`; rendering was tested
   with Python 3.14.6 on macOS. Byte identity across other platforms is not claimed.
4. `check-plots.py` tests interval calculations, grouping and accounting, report
   links, and export coverage. The figures are also visually inspected for
   clipping, overlapping text, legibility and consistent labels.

The qualitative algorithm interpretation and proposed next experiments remain
interpretations. Their supporting measurements are plotted; the figures do not
turn those interpretations into experimentally isolated causal claims.
