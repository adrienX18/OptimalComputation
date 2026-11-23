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

The lists describe the compiled certificate catalog: four workloads, seven
candidates and two independent minimizing objectives. Candidate listings include
configuration and the certificate's sufficient boundary budget. `evaluate` selects
registered Lean artifacts by identifier; it never imports serialized programs or
proof claims. To run a program written outside Lean, see
[Simulate an unverified candidate file](#simulate-an-unverified-candidate-file).

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
| `matvec-naive-v2` | 8 lanes, 8 banks | 1,344 | 39,632 | 800 | 2,304 | 1,345 |
| `matmul-naive-v2` | 8 lanes, 8 banks | 21,504 | 634,112 | 12,800 | 6,144 | 21,505 |

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
The transport accepts only a flat numeric array. Before JSON parsing, it rejects
numeric tokens longer than 4,096 characters (excluding surrounding whitespace)
and positive exponents that expand the mantissa by more than 4,096 decimal places.
These limits prevent a short exponent such as `0e1000000000` from causing enormous
integer allocation. Violations return `invalid-input-file`, independently of the
execution boundary budget. Ordinary scientific integer forms such as `1e2` and
`1.2e1` are supported; decimal or negative-exponent forms must reduce to an integer
representation in Lean's JSON parser (`1.0` and `10e-1` are rejected).

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
| 0 | Successful command; evaluation emitted an accepted result, or a simulation matched the reference for its input |
| 1 | Invalid input/file, unknown artifact/objective/fixture/workload, execution or trace/export failure, simulation output mismatch |
| 2 | Invalid command syntax, unknown/duplicate option, missing value or invalid budget |
| 3 | Evaluator boundary budget exhausted |

With `--json`, stdout contains exactly one JSON value and no human summary.
Without it, failures go to stderr; successful summaries go to stdout. Syntax
errors detected in an invocation containing `--json` are also JSON. Success uses
the existing `accepted-objective-result-v1` schema unchanged; simulations use
`simulation-result-v1`; catalogs use `cli-catalog-v1`; errors use `cli-error-v1`.
JSON is an exported report, not a portable proof certificate or an input accepted
by the scoring API.

The Lean `Failure` type additionally distinguishes inadmissible configurations,
malformed layouts/candidates/instructions, illegal schedules, arithmetic failures,
incomplete outputs and unverified artifacts. `inspect` and `checkStatic` provide
structural/static diagnostics, `simulate` provides runtime failures, and
`evaluateObjective` accepts only exact catalog artifacts. An unverified proposal
may pass inspection and concrete tests while still lacking all-input correctness;
that is not a scored candidate.

Structural and machine failures name the violated rule in `details.violation`,
an object with a `name` and named arguments. Only the first violation is reported.
An early store in the tiny program, for example, returns:

```json
"details": {"cycle": 4, "lane": 0,
            "rule": "OptimalComputation.Hardware.MachineRule.pendingRead 3",
            "violation": {"name": "pendingRead", "register": 3}}
```

| Category | Other `details` fields | `violation` names and arguments |
| --- | --- | --- |
| `illegal-schedule` | `cycle`, `lane` (null for batch-wide rules), `rule` (Lean text) | `issueCollision`; `bankCapacity {bank, accesses}`; `addressConflict {address}`; `pendingRead`, `pendingWrite`, `uninitializedRegister {register}`; `writebackCollision {due}`; `uninitializedMemory {address}`; `pendingCapacity {outstanding}` |
| `arithmetic-failure` | `cycle`, `lane`, `rule` | `operandOutOfRange {operand, bits, value}`; `resultOutOfRange {bits, value}` |
| `malformed-instruction` | `index`, `cycle`, `lane` | `laneOutOfBounds {lane, laneCount}`; `registerOutOfBounds {register}`; `zeroRegisterDestination`; `addressOutOfBounds`, `undeclaredRead`, `undeclaredWrite`, `writeToInput {address}` |
| `malformed-layout` | | `wrongInputCount`, `wrongOutputCount {expected, actual}`; `addressOutOfBounds {region, index, address}`; `aliasedStorage` |
| `inadmissible-configuration` | | `unsupportedLanes`, `unsupportedBanks {actual, allowed}` |
| `malformed-candidate` | | `emptyIdentifier`; `wrongModelVersion`, `wrongFormatVersion`, `wrongWorkloadIdentifier {expected, actual}` |

`incomplete-output` lists the unwritten `addresses`; input failures report the
scalar count, or the offending `index` and `value`.

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

## Simulate an unverified candidate file

Use `simulate` to run a program written outside Lean, for example by an optimizer.
Start from a registered candidate, edit the file, then simulate it:

```sh
.lake/build/bin/optimal_computation export-candidate matvec-naive-v1 > /tmp/candidate.json
.lake/build/bin/optimal_computation simulate /tmp/candidate.json --json
```

A candidate file is one JSON object with exactly the fields below. Every field is
required, and unknown fields are rejected, so a claim such as `"verified": true`
is an error rather than silently ignored. This is the complete `tiny-multiply-v1`
program:

```json
{"identifier": "my-tiny", "workloadIdentifier": "scalar-multiply-signed16-v1",
 "modelVersion": "arty-model-v1", "formatVersion": "candidate-v1",
 "configuration": {"lanes": 1, "banks": 1},
 "layout": {"inputs": [0, 1], "outputs": [2], "scratch": []},
 "schedule": [
  {"cycle": 0, "lane": 0, "instruction": {"kind": "load", "destination": 1, "address": 0}},
  {"cycle": 1, "lane": 0, "instruction": {"kind": "load", "destination": 2, "address": 1}},
  {"cycle": 2, "lane": 0, "instruction": {"kind": "multiply", "destination": 3, "left": 1, "right": 2}},
  {"cycle": 5, "lane": 0, "instruction": {"kind": "store", "source": 3, "address": 2}}]}
```

Layout lists give one address per logical scalar, in the scalar order of the table
above. Instruction operands are `load {destination, address}`, `store {source,
address}`, `add` and `multiply {destination, left, right}`, and `multiplyAdd
{destination, left, right, accumulator}`, the same names trace events use. Numbers
must be plain nonnegative integers: no fractions or exponents, at most 4,096 digits,
and nesting at most eight levels deep. Violations return `invalid-candidate-file`
before JSON parsing, so a hostile file cannot trigger exponent expansion.
`identifier` may use at most 64 characters from `A-Z`, `a-z`, `0-9`, `.`, `_` and
`-`. It is echoed in plain-text output, and other file-supplied text is escaped
there, so a file cannot print lines that imitate another command's result.

`simulate` takes the workload's scalar shape, input domain and reference from the
compiled catalog, selected by `workloadIdentifier` (otherwise `unknown-workload`),
never from the file. `--fixture` and `--input` work exactly as for `evaluate`. The
candidate then gets the same structural checks and cycle-accurate machine as every
other program, with the same failure categories: `malformed-candidate`,
`malformed-layout`, `malformed-instruction`, `inadmissible-configuration`,
`illegal-schedule`, `arithmetic-failure` or `incomplete-output`, each with the
[structured details](#inspect-failures-and-exhaustion) above. The default budget is the last issue cycle plus four
boundaries, enough for any run that does not fail, capped at 1,000,000 boundaries
so a huge cycle value cannot stall the evaluator. `--budget` overrides it, and
exhaustion exits 3 as usual.

A completed run is compared with the reference **for that one input only**. A match
prints `simulation-result-v1`, labeled `unverified-simulation`, with the same
`execution` object as accepted results and a `referenceCheck`. A mismatch exits 1
with `output-mismatch` and the expected outputs, actual outputs and mismatched
indices. `--trace FILE` writes a `simulation-trace-v1` file whenever the run
completes, including on a mismatch, when it is most useful.

Simulations are never certified and never scored: `--objective` is rejected, and
nothing in a file can change that. An accepted score still requires a Lean
candidate with an all-input certificate; see [extensions](extensions.md). For
example, retiming the exported `matvec-naive-v1` so that each instruction issues
on its predecessor's completion boundary reproduces exactly the certified
`matvec-naive-v2` schedule: 1,344 cycles instead of 2,143, with matching outputs.
`scripts/check-cli.py` runs that example for both matrix workloads. A hand-built
eight-lane example, `docs/candidates/matvec-grid-exchange-v1.json`, simulates in
79 cycles; see the [results guide](results/README.md#hand-built-unverified-reference).
