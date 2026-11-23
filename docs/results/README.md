# Matrix-vector baseline records

`matvec-naive-v1` computes the 16×16 matrix-vector product row by row, with each
row's columns in increasing order. It uses lane 0, registers r1/r2 for operands,
r3 for a signed48 accumulator, and r0 to reset r3 before each row. Every vector
operand is reloaded for every row. Slots 0–255 hold the matrix in row-major order,
256–271 hold the vector, and 272–287 hold the output. There is no scratch storage;
the 288 declared 64-bit slots occupy 2,304 bytes.

The all-input certificate covers the exact default `(8, 8)` artifact with trace
capture disabled. The 16 configuration records are conformance simulations of
the same fixed generator. They do not confer additional all-input certificates.
The two-term trace is also a simulation. These original objective-free records
remain unchanged; the additional objective records below use proof-bound executions.

## Independent schedule and count calculation

Every primitive owns its issue through completion boundary. The next instruction
issues one boundary after completion, so loads/stores consume two scheduled
boundaries and arithmetic consumes four. These conservative waits are deliberate.

For row `i`, let `base = 134*i`. The row issues:

| Operation | Issue | Completion |
| --- | --- | --- |
| `add r3,r0,r0` | `base` | `base+3` |
| Load matrix column `k` into r1 | `base+4+8*k` | `base+5+8*k` |
| Load vector column `k` into r2 | `base+6+8*k` | `base+7+8*k` |
| `multiplyAdd r3,r1,r2,r3` | `base+8+8*k` | `base+11+8*k` |
| Store output row `i` | `base+132` | `base+133` |

Here `i,k` each range from 0 through 15. Each row consumes
`4 + 16*(2+2+4) + 2 = 134` boundaries. The final store commits at
`15*134+133 = 2143`; the runner processes 2,144 boundaries including boundary zero.
The reported elapsed cycle count is **2,143**.

| Counter | Independent formula | Result |
| --- | --- | --- |
| Instructions / issues / completions | `16*(1+16*3+1)` | 800 |
| Loads | `16*16*2` | 512 |
| Stores | `16` | 16 |
| Adds (accumulator resets) | `16` | 16 |
| MACs | `16*16` | 256 |
| Multiplies | `0` | 0 |
| Register reads | `16*(2+16*3+1)` | 816 |
| Register writes | `16*(1+16*3)` | 784 |
| Bank accesses | `512+16` | 528 |
| Lane 0 active intervals | `16*(3+16*(1+1+3)+1)` | 1,344 |

Other lanes have zero issues, completions and active intervals. Every allowed bank
count divides the matrix, vector and output extents evenly, so each of `B` banks
receives `528/B` accesses. For the default eight banks, this is 66 per bank.
The regression suite compares every actual counter and the entire 800-entry
schedule with these independent formulas.

## Reproduction

Run from the repository root after `lake build`:

```sh
lake env lean scripts/reproduce-matvec.lean
lake env lean scripts/reproduce-matvec-configurations.lean
lake env lean scripts/reproduce-serial-dot-trace.lean
```

The first command selects the exact artifact with
`selectCandidate "matvec-naive-v1"` and uses `evaluateRegistered`; it prints
[the primary JSON record](matvec-naive-v1.json). The second prints
[all configuration records](matvec-naive-v1-configurations.json). Both use the
fixed `generated-23` fixture defined in `Examples/MatVecBaseline.lean`.
The third prints [the two-term trace](serial-dot-two-term-v1.txt):
`(-7)*6 + 5*(-3) = -57`, eight instructions, 21 elapsed cycles, and 22 processed
boundaries. Its issues, completions, payloads, active intervals and counters are
checked by `lake test`.

The proof audit is `lake env lean scripts/audit-matvec.lean`. Its 72 declarations
include every new public theorem, the exact candidate and certificate, and
registry roots. All depend only on Lean's standard `propext`, `Quot.sound`, and
`Classical.choice` axioms. The proof derives execution from shared machine steps;
fixtures are additional regression evidence.

## Versioned objective results

[Matrix-vector results](matvec-naive-v1-objectives.json) record the same certified
`generated-23` execution under `latency-v1` (2,143 cycles) and `energy-proxy-v1`
(59,607 abstract energy units). [Product-pair results](product-pair-v1-objectives.json)
record both hand-written candidates under both objectives, using `[-7,6,5,-3]`
and outputs `[-42,-15]`. Their all-input proofs also cover every allowed signed16
quadruple; these concrete inputs only make the reports reproducible.

```sh
lake env lean scripts/reproduce-matvec-objectives.lean
lake env lean scripts/reproduce-product-pair-objectives.lean
lake env lean scripts/audit-objectives.lean
```

Each candidate executes once and its exact proof-carrying record is rescored.
Reports use `accepted-objective-result-v1`; the fixed coefficient profile is
`energy-coefficients-v1`. See [objectives](../objectives.md) for the arithmetic,
manual 172/202 comparison, trust boundary, and limitations. JSON metadata is a
report of certification, not itself proof evidence or an accepted-score input.

## Matrix-matrix baseline

The [matrix-matrix baseline record guide](matmul-naive-v1.md) documents
`matmul-naive-v1`, its all-input proof, row-major layout, reproduction commands,
and saved results: **34,303 cycles / 954,087 abstract energy units** at `(8, 8)`.
Its configuration records are conformance simulations. The matrix-vector and
product-pair results above remain unchanged.
