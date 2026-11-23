# Section 9 experiments

The four workloads now have executable naive baselines with all-input Lean
certificates on all sixteen admissible configurations. A deterministic greedy
scheduler and hand-built schedules supply comparison points. The experiment
runner records every proposal, including rejection and inconclusive outcomes.
There is no LLM client or autonomous optimization loop.

[Automatic certification](certification.md) now handles arbitrary candidate files,
including the 79-cycle `matvec-grid-exchange-v1`. The saved experiment and its
runner retain their original catalog-based acceptance policy for reproducibility;
its deferred entries describe that historical run. Use the standalone certifier
to check an exported proposal. Connecting it to a future optimization loop is a
separate task.

## Run

```sh
lake build
lake test
python3 scripts/check-experiments.py
python3 scripts/experiment.py --output /tmp/section9-run
# A shorter run:
python3 scripts/experiment.py --task polynomial --output /tmp/polynomial-run
```

Use a new output directory for each run. The runner refuses to overwrite a
proposal log. It writes a `submitted` event before evaluation, a completion event
with fixture and certification outcomes, and a measured event with gap metrics.
An interrupted proposal therefore remains visible. The summary has one latency
instance per pinned configuration and one configuration-free energy instance per
workload. The latter admits all sixteen configurations.

Saved results include a [readable report](results/section9-v1/summary.md),
[machine-readable summary](results/section9-v1/summary.json),
and a [proposal ledger](results/section9-v1/proposals.jsonl). Candidate artifacts
are gzip-compressed canonical JSON, addressed by SHA-256 of the uncompressed JSON
without its trailing newline. The artifact field in each proposal locates the
exact schedule, layout and configuration. To inspect or simulate one:

```sh
gzip -dc docs/results/section9-v1/candidates/DIGEST.json.gz > /tmp/candidate.json
lake exe optimal_computation simulate /tmp/candidate.json --fixture generated-23 --json
```

## Workloads and certificates

| Workload identifier | Logical input scalar order | Outputs | Naive candidate |
| --- | --- | --- | --- |
| `matmul-16x16-signed16-v1` | A row-major, B row-major | C row-major | `matmul-naive-v2` |
| `polynomial-degree7-points16-v1` | c0 through c7, then x0 through x15 | p(x0) through p(x15) | `polynomial-naive-v1` |
| `gram-16x16-signed16-v1` | A row-major | G row-major, including both triangles | `gram-naive-v1` |
| `two-stage-linear-16-signed16-v1` | A row-major, x, B row-major | y | `two-stage-naive-v1` |

Matrix and Gram inputs are signed 16-bit. Polynomial coefficients are integers
in [-8,7], and points are in [-4,3]. The first 272 two-stage inputs (A and x) are
in [-45,45]; B is signed 16-bit. All arrays have the exact fixed lengths shown by
`list-workloads`; extra, missing and out-of-domain scalars are rejected.

```sh
lake exe optimal_computation evaluate polynomial-naive-v1 --configuration 8,1 --fixture negative-endpoints
lake exe optimal_computation evaluate matmul-naive-v2 --configuration 2,8 --objective energy-proxy-v1 --json
lake exe optimal_computation export-candidate two-stage-naive-v1 --configuration 8,1
```

Without `--configuration`, the default registered candidate is unchanged.
Candidate names are unique within a configuration; `list-candidates` displays
both. `simulate` takes its configuration from the candidate file and rejects an
attempt to override it with the flag.

The new serial compiler is deliberately simple: each explicitly supplied node
loads its seed (or clears the accumulator), performs at most sixteen explicit
load/load/MAC terms in order, and stores its result. Node outputs occupy distinct
scratch slots after the input and output regions. Final copies fill every
logical output slot. This costs extra loads and stores, all of which are present
in the execution and objective records. Scratch is never preinitialized.

The polynomial baseline processes one point at a time, materializes x through
x^7, and accumulates c0 + c1*x + ... + c7*x^7. It uses 128 scratch slots. Gram's
naive baseline computes all 256 dot products and uses 256 scratch slots. The
two-stage baseline computes sixteen t entries, then sixteen y entries, with 32
scratch slots; stage two explicitly loads t from memory. None of these baselines
reuses values between independent dot products. The existing matrix baseline and
its frozen instruction order and results are unchanged.

`SerialNetwork.Network` requires workload proofs of every node's arithmetic
equation, multiplicand bounds, earlier-node dependencies, and output binding.
Composition proves initialization, preservation, exact execution through the
common machine runner, output completeness and all-input correctness. It is a
proof-producing serial construction interface, not certification of files.

The separate `gram-symmetric-v1` certificate computes 136 distinct dot products.
Its output mapping uses `Gram.symmetric`, proved from integer multiplication
commutativity; mirrored outputs still receive explicit stores. Its serial
scratch-and-copy construction is distinct from the unverified parallel
hand-built reference, which stores a computed dot product directly to both
output positions.

At (8,8), the certified baselines and symmetry example have these results:

| Candidate | Cycles | Energy-proxy units |
| --- | ---: | ---: |
| `matmul-naive-v2` | 21,504 | 634,112 |
| `polynomial-naive-v1` | 1,520 | 44,128 |
| `gram-naive-v1` | 22,016 | 649,472 |
| `gram-symmetric-v1` | 11,936 | 352,232 |
| `two-stage-naive-v1` | 2,720 | 80,224 |

Energy uses the frozen hypothetical `energy-coefficients-v1`, not physical units.

## Schedulers and reference schedules

The greedy baseline splits the certified naive code at store-ended jobs. Each
job must initialize its own local registers. A memory dependency graph preserves
read-after-write, write-after-read and write-after-write ordering. Ready jobs are
chosen in original order and assigned to the first idle lane. Instructions in a
job wait for their predecessor's completion. Bank ports and same-address hazards
are reserved across lanes. It preserves the exact multiset of baseline
instructions and never examines input values.

The hand-built references make different, explicit choices:

- Matrix multiplication holds four output accumulators and shares each A load
  across four columns.
- Polynomial evaluation uses Estrin's grouping with x² and x⁴ and four adjacent
  coefficient pairs.
- Gram computes only the upper triangle and stores each off-diagonal result to
  both symmetric output positions.
- The two-stage map groups independent dot products and uses a completion barrier
  between the scratch-producing first stage and the consuming second stage.

A deterministic in-order issue packer gives these fixed lane streams their
earliest legal issue times. It tracks register readiness, future writeback
slots, three pending instructions, bank ports and same-address conflicts. It
does not search alternative algorithms or schedules. Every emitted schedule is
then checked and run by Lean's unchanged simulator on all public fixtures.

## Measurements and proof status

A latency instance pins both lane and bank count: (8,8), (8,1), or (2,8).
`check_instance` rejects a different workload or configuration before execution.
Energy instances leave configuration free and compare all sixteen choices.

Every proposal records structural validity, each fixture's result, held-out
results where applicable, and a separate certification status:

- `certified`: exact candidate equality with an entry carrying an all-input proof;
- `deferred`: fixture success without an available general certificate;
- `refuted-by-counterexample`: an allowed input demonstrates a semantic failure;
- `invalid-structure`, `inconclusive-resource-exhausted`, or `not-attempted`.

A missing certifier and resource exhaustion are never counted as failed proofs.
The main failure metric counts only proposals that passed every public fixture
but were refuted on an allowed held-out input. Counts are reported per instance
and for the full run.

Only certified proposals have `acceptedScore` and `acceptedGapClosed`.
Unverified successful schedules have observed cycle gaps. Energy instances also
show a clearly labeled `unverified-counter-projection` computed from their
recorded activity and the frozen coefficient profile; this is a diagnostic
reference point, not an accepted optimization score. Known-refuted candidates
receive no gap or energy projection. The CLI continues to return no objective
score for `simulate`.

The counting floor uses compulsory input loads and output stores. For N such
transfers, latency is at least max(ceil(N/L), ceil(N/(2B))). Every scalar input
in these domains can affect an output, and every distinct output slot must be
written. This floor holds even when the algebra or layout changes. It deliberately
does not assume that 4,096 classical matrix products are a universal algebraic
lower bound. The energy floor minimizes the compulsory transfer, register and
provisioned-duration costs over all sixteen configurations, omitting additional
required arithmetic. Both bounds are conservative, not optimality claims.

Gap closed is `(naive - candidate) / (naive - floor)`, stored as an exact fraction
and a display decimal. Negative gaps are retained; undefined zero-denominator
gaps are null. A reference at the floor makes that instance a smoke test.

## The held-out polynomial failure

Public fixtures include uniform negative and positive endpoints, zero, mixed
signs and a deterministic generated input. All are legal for Horner. The held-out
input uses coefficients `[7,-8,7,-8,7,-8,7,-8]` and sixteen points equal to -4.
The final Horner multiplication consumes -42,596, outside signed 16-bit range.
Its mathematical output is 170,391, within signed 48-bit range; the problem is
an intermediate multiplicand, not the final answer.

This input is not a named CLI fixture or supplied to the scheduler. The runner
uses it only after public fixture evaluation. It is saved with validation
results for reproducibility. The explicit-power baseline and Estrin reference
both handle it. No claim about a random-sampling probability is required for the
regression.

## Validation

`python3 scripts/validate.py` runs the original regression and frozen-result
checks, the experiment integration checks, saved-result integrity checks, and a
14-root Section 9 axiom audit. The audit allows only the standard Lean axioms
already permitted by the project. No additional trusted arithmetic evaluator,
compiler evaluation axiom, or unfinished proof is introduced.

To independently regenerate the complete proposal set, use the full experiment
command with a fresh directory. JSON records, input order, schedules, coefficient
identifiers and counters are deterministic. Gzip headers have zero timestamps.
