# Reproducible validation

From a checkout with the pinned Lean toolchain installed:

```sh
python3 scripts/validate.py
```

Run without Python's `-O`/`-OO` flags and with `PYTHONOPTIMIZE` unset. The driver
and standalone Python checkers refuse optimized mode because it disables their
assertions; they must not report success after skipping validation.

This standard-library-only driver runs, in order:

1. `lake build` and `lake test`.
2. The process-level CLI suite and the compiled documentation examples.
3. Five axiom audits, allowing only `propext`, `Quot.sound` and `Classical.choice`:
   48 verification, 65 matrix-vector, 26 objectives, 34 matrix-matrix and
   32 naive-v2 declarations.
4. Byte-for-byte reproduction of the ten saved artifacts in `docs/results/`.
5. Both independent Python result checkers.
6. `git diff --check`, whitespace checks on every tracked or untracked nonignored
   text file, and a scan of Lean sources for proof shortcuts (`sorry`, `admit`,
   `native_decide`, custom axioms, `unsafe`, `implemented_by`, `extern`).

An optional argument names a JSON map from relative paths to SHA-256 digests; the
driver then also confirms that those files are unchanged.

Individual commands are useful while changing one area:

```sh
lake build
lake test
python3 scripts/check-cli.py
lake env lean scripts/check-doc-examples.lean
lake env lean scripts/audit-verification.lean
lake env lean scripts/audit-matvec.lean
lake env lean scripts/audit-objectives.lean
lake env lean scripts/audit-matmul.lean
lake env lean scripts/audit-naive-v2.lean
python3 scripts/check-objective-results.py
python3 scripts/check-matmul-results.py
git diff --check
```

The reproduction scripts use `#eval`, so run `lake env lean scripts/reproduce-X.lean`
without `--run`. The full driver maps every script to its exact saved result.

What each layer protects:

- `lake build` checks every proof. The serial baselines only exercise one lane,
  so their proofs do not pin the rules that matter for parallel schedules.
- `lake test` pins those rules with executable cases: register hazards on lane
  zero and on a second lane, bank ports for loads and stores, same-address
  conflicts, issue collisions, order independence, counters and completion.
- `scripts/check-cli.py` tests real process exits, JSON output, unchanged saved
  baseline results, both objectives, custom and malformed inputs, exhaustion,
  trace export, structured failure details, hostile candidate files and the
  hand-built 79-cycle reference candidate.

## Clean-checkout check

To confirm that nothing depends on a local build cache or untracked file:

```sh
git clone <repository> /tmp/optimal-clean
cd /tmp/optimal-clean
python3 scripts/validate.py
git status --porcelain   # must print nothing
```

## Latest recorded run

On 2026-11-22 the full driver passed in the working tree and in a fresh clone
with no build cache.

| Item | Recorded value |
| --- | --- |
| Lean | `4.35.0`, `arm64-apple-darwin24.6.0`, commit `eb6cafb7290e8bd5f2937522d8d804f58f02bafc` |
| Lake | `5.0.0-src+eb6cafb` (bundled with Lean 4.35.0) |
| Python | `3.15.2`, standard library only |
| Build | 125 jobs |
| Tests | 13 suites |
| Axiom audits | 48 / 65 / 26 / 34 / 32 declarations, standard axioms only |
| Saved artifacts | 10 reproduced byte for byte |

Reproduced certified scores, as cycles / abstract energy units:

| Candidate | Result |
| --- | ---: |
| `tiny-multiply-v1` | 6 / 86 |
| `matvec-naive-v1` | 2,143 / 59,607 |
| `matmul-naive-v1` | 34,303 / 954,087 |
| `product-pair-serial-v1` | 12 / 172 |
| `product-pair-parallel-v1` | 6 / 202 |
| `matvec-naive-v2` | 1,344 / 39,632 |
| `matmul-naive-v2` | 21,504 / 634,112 |

These are software model results, not physical timing or power evidence.
