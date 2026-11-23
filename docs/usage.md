# CLI usage

Run `lake build` from the repository root. Commands below use
`lake exe optimal_computation`; for machine consumers use the already-built
`.lake/build/bin/optimal_computation` so build-tool messages cannot mix with stdout.
`--help`, `--version`, and `--check` remain available; `lake test` runs `--check`.

```sh
lake exe optimal_computation list-workloads
lake exe optimal_computation list-candidates --json
lake exe optimal_computation list-objectives
```

The lists describe the compiled certificate catalog: four workloads, five
candidates and two independent minimizing objectives. Candidate listings include
configuration and the certificate's sufficient boundary budget. The CLI selects
registered Lean artifacts by identifier; it does not import serialized programs
or proof claims. See [the API](api.md) to inspect or simulate an unverified proposal.

## Reproduce and score both baselines

```sh
lake exe optimal_computation evaluate matvec-naive-v1 --fixture generated-23 --objective latency-v1
lake exe optimal_computation evaluate matvec-naive-v1 --fixture generated-23 --objective energy-proxy-v1 --json
lake exe optimal_computation evaluate matmul-naive-v1 --fixture generated-23 --objective latency-v1
lake exe optimal_computation evaluate matmul-naive-v1 --fixture generated-23 --objective energy-proxy-v1 --json
```

| Candidate | Configuration | Cycles | Abstract energy | Instructions | Declared bytes | Default budget |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `tiny-multiply-v1` | 1 lane, 1 bank | 6 | 86 | 4 | 24 | 7 |
| `matvec-naive-v1` | 8 lanes, 8 banks | 2,143 | 59,607 | 800 | 2,304 | 2,144 |
| `matmul-naive-v1` | 8 lanes, 8 banks | 34,303 | 954,087 | 12,800 | 6,144 | 34,304 |
| `product-pair-serial-v1` | 1 lane, 1 bank | 12 | 172 | 8 | 48 | 13 |
| `product-pair-parallel-v1` | 8 lanes, 8 banks | 6 | 202 | 8 | 48 | 7 |

These schedules and event counts do not depend on input values within the allowed
domain. Matrix baselines use only lane zero. Saved [results](results/README.md)
include independent counter calculations and configuration conformance runs.
Energy units and coefficients are [abstract and fixed](objectives.md).

Each CLI invocation executes the same objective-free program and then scores its
record. Changing `--objective` does not change execution. To execute once and
rescore that very same proof-carrying value, use `AcceptedScore.rescore` as shown in
the [extension guide](extensions.md); the saved objective reproduction scripts do this.

The manual pair computes `(a*b, c*d)`. With default inputs `[-7,6,5,-3]`, both
return `[-42,-15]`; latency prefers the parallel schedule and energy prefers serial:

```sh
lake exe optimal_computation evaluate product-pair-serial-v1 --objective latency-v1
lake exe optimal_computation evaluate product-pair-parallel-v1 --objective latency-v1
lake exe optimal_computation evaluate product-pair-serial-v1 --objective energy-proxy-v1
lake exe optimal_computation evaluate product-pair-parallel-v1 --objective energy-proxy-v1
```

Neither candidate is claimed optimal. No search ran to choose them.

## Runtime inputs and fixtures

`--input FILE` reads one UTF-8 JSON array of integer values, with no object wrapper.
It is mutually exclusive with `--fixture NAME`. Every scalar is checked against
the selected workload's signed16 domain, `-32768` through `32767`, after exact
count and codec validation. Values are runtime data, not generated instructions.

| Workload / candidate family | Array order | Count |
| --- | --- | ---: |
| Scalar multiply / tiny | `[a,b]` | 2 |
| Product pair | `[a,b,c,d]` | 4 |
| Matrix-vector | A's 256 row-major entries, then x's 16 entries | 272 |
| Matrix-matrix | A's 256 row-major entries, then B's 256 row-major entries | 512 |

Outputs use scalar order: one product, two products, 16 vector entries, or 256
row-major matrix entries. JSON success includes all input and output scalars;
human output summarizes counts to stay concise. A file's path is only its input
label, never a substitute for the saved scalar values.

```sh
printf '%s\n' '[-32768,32767]' > /tmp/optimal-input.json
lake exe optimal_computation evaluate tiny-multiply-v1 --input /tmp/optimal-input.json --json
```

The output is `[-1073709056]`, with 6 cycles. Defaults are `latency-v1`, the
certificate's sufficient budget, and `generated-23` for matrix workloads or
`mixed-signs` for tiny/pair. Available fixtures are:

- Tiny/pair: `mixed-signs`, `zeros`.
- Matrix-vector: `zeros`, `identity`, `mixed-signs`, `negative-endpoints`,
  `positive-endpoints`, `opposite-endpoints`, `generated-23`.
- Matrix-matrix: `zeros`, `left-identity`, `right-identity`, `mixed-signs`,
  `negative-endpoints`, `positive-endpoints`, `opposite-endpoints`, `generated-23`.

## Inspect failures and exhaustion

```sh
printf '%s\n' '[32768,1]' > /tmp/optimal-bad-input.json
lake exe optimal_computation evaluate tiny-multiply-v1 --input /tmp/optimal-bad-input.json --json
lake exe optimal_computation evaluate tiny-multiply-v1 --budget 6 --json
```

The first exits 1 with category `invalid-input`: 32768 is outside signed16.
The second exits 3 and reports:

```json
{
  "recordVersion": "cli-error-v1",
  "status": "resource-exhausted",
  "category": "resource-exhausted",
  "message": "Boundary budget exhausted; evaluation is inconclusive.",
  "details": {
    "nextBoundary": 6,
    "issuedInstructions": 4,
    "remainingInstructions": 0,
    "pendingEffects": 1
  }
}
```

A budget counts boundaries including zero, not elapsed cycles. The tiny program
needs seven boundaries to commit its final store at cycle six. Extra budget is
capped at the certificate's sufficient bound. Exhaustion is inconclusive; it
does not establish a wrong result or an illegal schedule. Failed evaluation
never returns an accepted score.

| Exit | Meaning |
| ---: | --- |
| 0 | Successful command; evaluation emitted an accepted result |
| 1 | Invalid input/file, unknown artifact/objective/fixture, execution or trace/export failure |
| 2 | Invalid command syntax, unknown/duplicate option, missing value or invalid budget |
| 3 | Evaluator boundary budget exhausted |

With `--json`, stdout contains exactly one JSON value and no human summary.
Without it, failures go to stderr; successful summaries go to stdout. Syntax
errors detected in an invocation containing `--json` are also JSON. Success uses
the existing `accepted-objective-result-v1` schema unchanged; catalogs use
`cli-catalog-v1`; errors use `cli-error-v1`. JSON is an exported report, not a
portable proof certificate or an input accepted by the scoring API.

The Lean `Failure` type additionally distinguishes inadmissible configurations,
malformed layouts/candidates/instructions, illegal schedules, arithmetic failures,
incomplete outputs and unverified artifacts. `inspect` and `checkStatic` provide
structural/static diagnostics, `simulate` provides runtime failures, and
`evaluateObjective` accepts only exact catalog artifacts. Machine diagnostics
retain cycle, optional lane, and a rule carrying the relevant register, address,
bank or arithmetic value. An unverified proposal may pass inspection and concrete
tests while still lacking all-input correctness; that is not a scored candidate.

## Export an observational trace

```sh
lake exe optimal_computation evaluate tiny-multiply-v1 --trace /tmp/optimal-trace.json --json
```

The accepted run keeps trace capture disabled, as its certificate requires.
`--trace FILE` reruns the same candidate, allowed input and effective budget with
tracing enabled. Export proceeds only after equality of **all nontrace fields of
the complete execution record**: versions, identifiers, outputs, cycles, counters,
resources, storage and schedule size. This is an observed equality for this input,
not a generic trace-invariance theorem or a proof of the trace.

The separate `observational-trace-v1` file is labeled `observational-simulation`.
It embeds the unchanged accepted result for binding, the effective budget, and
every boundary with structured issue, commit and active events. For tiny, issues
occur at cycles 0/1/2/5 and completions at 1/2/5/6. Idle boundaries have empty event
arrays. Matrix traces are much larger. The path is written as requested and an
existing file at that path is replaced. If simulation comparison or file export
fails, the command exits nonzero and emits only a score-free error, even if the
earlier certified execution succeeded.
