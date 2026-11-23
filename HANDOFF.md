# Experiment checkpoint handoff

Checkpoint time: 2026-11-23T21:14:33.388633+00:00. **This is not a full-readiness sign-off.**

## Running experiment — leave it running

- Repository: `/Users/adrien/Desktop/Niko projects/OptimalComputation` (`main`).
- Run directory: `runs/suite-smoke-20261123`.
- Terminal session: `14393`; launched under `caffeinate -i`.
- Smoke only: 16 cases × 5 models × 3 attempts, seed 11; five search loops, one kernel check at a time.
- Snapshot: **11/240 attempts**, 1/80 loops complete; 15 responses saved.
- Outcomes: {"certified": 7, "kernel-timeout": 1, "proposal-error": 2, "simulation-failed": 1}.
- Full campaign: **not prepared, not launched**. Do not launch it without a new user go.

## Completed / unfinished

Completed: full regression validation; five-worker batch tests; provider tests; all 16 offline Docker/simulation/kernel/score checks; offline archive verification (3,554 files, 80 lossless traces).

**Unfinished:** the live smoke run, final live archive audit, final readiness report and full-plan preparation. A known limitation is that fresh verification of the already-certified long matrix baseline timed out at 600 seconds; the incumbent remains certified. Refusals and invalid proposals are preserved as feedback. Proof-reuse probes were not adopted.

All current runtime source is frozen in `docs/results/full-suite-readiness-v1/source-hashes.json`. Do not edit it while the run is active. Raw runs and `.env` are Git-ignored and must not be force-added. Complete validation logs are in `runs/suite-readiness-checks-20261123`; detailed evidence and trade-offs are in `docs/results/full-suite-readiness-v1/README.md` and `docs/decisions.md`.

## Continue safely

Inspect `runs/suite-smoke-20261123/summary.json`, `events.jsonl`, individual feedback files, or poll terminal session 14393. The batch summary updates when a loop finishes; feedback files show individual attempts sooner.

Only if the existing process has stopped, resume the same smoke archive (the lock prevents a second active launcher):

```sh
cd '/Users/adrien/Desktop/Niko projects/OptimalComputation'
caffeinate -i /tmp/optimal-harness-venv/bin/python scripts/search_batch.py --output runs/suite-smoke-20261123 --resume
```

After all 240 attempts finish, audit and update the report/checklist; investigate infrastructure errors separately from rejected designs:

```sh
python3 scripts/audit-search-batch.py runs/suite-smoke-20261123 --output docs/results/full-suite-readiness-v1/smoke-audit.json
```

Then finish the readiness review, commit/push the updated evidence, and prepare the full manifest with **`--prepare-only`** if continuing the original task. The full plan is 400 loops / 20,000 attempts. **Do not start the full run until the user explicitly gives the go.**
