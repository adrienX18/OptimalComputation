# Matrix-matrix baseline records

`matmul-naive-v1` computes the 16×16 matrix product with conventional `i,j,k`
loop order. Flattening `q = 16*i+j` only numbers the output entries: each entry
starts a fresh signed48 accumulator, then explicitly loads `A[i,k]` and `B[k,j]`
for every increasing `k`. There is no tiling, packing or reuse across entries.
Only lane 0 is active. Registers r1 and r2 hold operands; r3 holds the accumulator.

Both input matrices are runtime values in row-major order. A occupies slots
0–255, B occupies 256–511 and C occupies 512–767. The 768 full 64-bit slots use
6,144 bytes, including outputs, with no scratch storage.

The default `(8 lanes, 8 banks)` artifact is all-input certified. Its
[objective-free record](matmul-naive-v1.json) and
[latency and energy results](matmul-naive-v1-objectives.json) use `generated-23`.
The [sixteen configuration records](matmul-naive-v1-configurations.json) are
conformance simulations of the same generator; they are not separately certified.

## Schedule and independent totals

Let `base = 134*(16*i+j)`. Each primitive waits through its completion boundary;
the next instruction issues one boundary later. These conservative waits are part
of the fixed baseline.

| Operation | Issue | Completion |
| --- | --- | --- |
| `add r3,r0,r0` | `base` | `base+3` |
| Load `A[i,k]` into r1 | `base+4+8*k` | `base+5+8*k` |
| Load `B[k,j]` into r2 | `base+6+8*k` | `base+7+8*k` |
| `multiplyAdd r3,r1,r2,r3` | `base+8+8*k` | `base+11+8*k` |
| Store `C[i,j]` | `base+132` | `base+133` |

There are 256 dot products of 134 processed boundaries each. The final store
commits at boundary **34,303**, so the execution needs **34,304** boundaries,
including zero. One fewer boundary produces resource exhaustion with the final
store pending; it cannot receive an accepted score.

| Counter | Formula | Result |
| --- | --- | --- |
| Instructions / issues / completions | `256*(1+16*3+1)` | 12,800 |
| Loads | `256*16*2` | 8,192 |
| Stores | `256` | 256 |
| Adds (resets) | `256` | 256 |
| MACs | `256*16` | 4,096 |
| Multiplies | `0` | 0 |
| Register reads | `256*(2+16*3+1)` | 13,056 |
| Register writes | `256*(1+16*3)` | 12,544 |
| Bank accesses | `8192+256` | 8,448 |
| Lane 0 active intervals | `256*(3+16*(1+1+3)+1)` | 21,504 |

The `B` banks each receive `8448/B` accesses. All other lanes have zero issues,
completions and active intervals. `latency-v1` scores **34,303 cycles**.
The unchanged `energy-proxy-v1` profile produces **954,087 abstract energy units**:

```text
34303 + 274424 + 548848 + 32768 + 1024 + 256 + 0 + 36864 + 13056 + 12544
```

These are the base, lane and BRAM cycle costs followed by loads, stores, adds,
multiplies, MACs, register reads and writes. The default resource allocation has
8 DSPs and 16 BRAM36 blocks. Energy is hypothetical, not a physical measurement.

## Proof and reproduction

`Examples/MatMulProof.lean` proves `execution_correct` for every pair of matrices
whose entries fit signed16. It composes `SerialDot.executes_prefix` with an
induction over all output entries, preserves both input matrices, and binds the
common initializer, sorted actual program, `Hardware.step`/`Evaluation.run`, and
row-major output collector. `verified` packages safety and correctness for the
exact artifact. Small generic runner/finisher lemmas keep the proof from unfolding
the entire 12,800-instruction program during kernel checking.

The diagnostic registry checks complete artifact equality. The generic objective
catalog adds only a `VerifiedArtifact` entry; scoring uses `CertifiedExecution`
and `AcceptedScore`, retaining the actual execution equality. Display labels and
saved JSON are reports, not portable proof certificates. Accepted execution has
tracing disabled; the full trace used in regressions is an observational simulation.

Run from the repository root after `lake build`:

```sh
lake test
lake env lean scripts/audit-matmul.lean
lake env lean scripts/reproduce-matmul.lean
lake env lean scripts/reproduce-matmul-configurations.lean
lake env lean scripts/reproduce-matmul-objectives.lean
python3 scripts/check-matmul-results.py
```

The three reproduction commands print the saved JSON files. The objective script
executes once and rescores the same proof-carrying record. The independent Python
check recomputes all 256 products from the 512 runtime input scalars, counts bank
accesses from nested loops, and checks every saved counter and objective term.
Regressions also cover zeros, both identity orders, mixed signs, positive and
negative signed16 endpoints, exact stores, budget exhaustion, and altered bindings.
The 40-declaration audit includes every new public theorem and the certificate and
registry roots, with only the standard Lean axioms.
