# Reproducible validation

From a checkout with the pinned Lean toolchain installed:

```sh
python3 scripts/validate.py
```

This standard-library-only driver runs `lake build`, `lake test`, the process-level
CLI smoke suite, and compiled documentation examples. It then runs all four axiom
audits (53 verification, 72 matrix-vector, 26 objectives and 40 matrix-matrix
declarations), allowing only `propext`, `Quot.sound` and `Classical.choice`. It
reproduces all eight saved artifacts byte for byte, runs both independent Python
result checkers, and checks `git diff --check`, all tracked/untracked nonignored
text files for whitespace, and Lean sources for proof shortcuts.

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
python3 scripts/check-objective-results.py
python3 scripts/check-matmul-results.py
git diff --check
```

The reproduction scripts use `#eval`, so run `lake env lean scripts/reproduce-X.lean`
without `--run`. The full driver maps every script to its exact saved result.
`scripts/check-cli.py` tests real process exits, JSON parsing, unchanged saved
baseline results, both objectives, custom input files, malformed input, missing
files, exhaustion, human output and trace binding/export failures. `lake test`
also exercises the same CLI dispatch and checks that changing any nontrace field
is rejected by the trace comparison. Existing machine and proof regressions remain
part of that command.

## Milestone 10 clean-checkout record

On 2026-11-22 the complete driver passed in both the working tree and a fresh
local Git clone. At snapshot creation, the real checkout had uncommitted M7–M10
work after the M1–M6 checkpoint `aee594d16dbd90a06ebc0ad35cb7a89cda102cf6`.
The snapshot below is a local validation revision, not the remote repository HEAD.
The worker did not stage, commit or push in the real repository.

| Item | Recorded value |
| --- | --- |
| Snapshot revision | `53612eff96b93e7802fb3d329533c0502473d84f` |
| Snapshot source repository | `/private/tmp/optimal-m10-clean-x0lgsq8a/source` |
| Fresh checkout | `/private/tmp/optimal-m10-clean-x0lgsq8a/checkout` |
| File manifest | `/private/tmp/optimal-m10-clean-x0lgsq8a/manifest.json` (99 SHA-256 entries) |
| Clean validation log | `/private/tmp/optimal-m10-clean-x0lgsq8a/validation.log` |
| Working-tree validation log | `/private/tmp/optimal-m10-validation.log` |
| Lean | `4.35.0`, `arm64-apple-darwin24.6.0`, commit `eb6cafb7290e8bd5f2937522d8d804f58f02bafc` |
| Lake | `5.0.0-src+eb6cafb` (bundled with Lean 4.35.0) |
| Python | `3.14.6`, standard library only |

The snapshot copied exactly the tracked and untracked nonignored files reported
by `git ls-files --cached --others --exclude-standard`, excluding `.git` and
`.lake`. Those 99 files were committed only in the temporary source repository,
then cloned with:

```sh
git clone --no-hardlinks /private/tmp/optimal-m10-clean-x0lgsq8a/source /private/tmp/optimal-m10-clean-x0lgsq8a/checkout
cd /private/tmp/optimal-m10-clean-x0lgsq8a/checkout
python3 scripts/validate.py /private/tmp/optimal-m9-frozen.json
git status --porcelain
```

`.lake` did not exist before the run. The clone used the installed pinned toolchain
and no copied or shared project build cache, dependency download, or network
access. The final `git status --porcelain` was empty. The external optional hash
map checked all 36 frozen machine/workload/core/baseline/result files; it is not
needed to run the in-repository validation driver on another machine.

Both runs passed the 119-job build and every regression suite, including the
new CLI suite. All four proof audits passed (53/72/26/40 declarations), all eight
saved artifacts reproduced byte for byte, both independent result checkers
passed, and all 99 text files passed whitespace/source checks. The CLI process
suite reproduced both saved baseline objective records exactly, checked all five
candidate costs, custom signed-endpoint inputs, JSON and human output, bad
arguments, invalid inputs/files, exhaustion and observational trace export.

Reproduced scores are 6/86 for tiny, 2143/59607 for matrix-vector, 34303/954087 for
matrix-matrix, 12/172 for serial pair, and 6/202 for parallel pair (cycles/abstract
energy). These are software model results, not physical timing or power evidence.

The coordinator independently reran the full validation driver in the clean
checkout and all checks passed again. Every milestone deliverable and all fourteen
plan completion requirements then passed coordinator review.

After the clean run, only this file, `STATUS.md`, and the fourteen completion
checkboxes in `PLAN.md` changed to record validation and acceptance. All executable,
proof, test, script, fixture, result and other documentation bytes match the
snapshot manifest. Final documentation edits were separately checked for
whitespace and links; no code changed after the clean gate.
