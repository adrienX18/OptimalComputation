# Full-suite readiness handoff

**Ready for the user's go. The full experiment has not started.**

- Repository: `/Users/adrien/Desktop/Niko projects/OptimalComputation`, branch `main`.
- Completed smoke: `runs/suite-smoke-20261123`; no smoke process remains active.
- Result: 80/80 loops, 240 scheduled slots: 236 finished attempts and 4 interrupted slots retained after the connection restart. There are 182 certified candidates.
- Audit passed: 28,001 files and 970 lossless traces. See [readiness report](docs/results/full-suite-readiness-v1/README.md), [audit](docs/results/full-suite-readiness-v1/smoke-audit.json), and [observations](docs/results/full-suite-readiness-v1/smoke-observations.json).
- Full regression validation and all 16 offline reference checks passed. The audit recovery fix passed all 12 batch/audit tests. Code commit: `f158b9a39cfabdcf3c33ab8258128d3879208b7a`; original checkpoint: `ec5f9ffa13c91b61b5035d50ce72a41e0df8f684`.
- Prepared full campaign: **`runs/suite-full-ready-20261123`**, 400 loops / 20,000 attempts, zero progress. Its 514-file inventory and source/configuration checks passed. The older `runs/suite-full-20261123` preparation is superseded and preserved.
- Five parallel search loops, one memory-heavy kernel proof at a time. Smoke-rate scaling suggests about 13.6 days and 81.7 GiB for the full run; this is a planning scenario, not a bound or guarantee.
- Raw archives and `.env` remain Git-ignored. Do not force-add them. All complete validation logs remain in `runs/suite-readiness-checks-20261123`.

## Remaining work

Wait for explicit user authorization to launch the full campaign. No implementation or smoke-audit work remains. Use a detached process with persistent console output: the prior foreground smoke batch was interrupted after the interactive connection restarted. Standard resume retained every existing attempt and did not repeat calls.

## Launch only after the user's go

The following command is prepared, **not executed**. It starts the already-prepared full campaign in a separate process session, with no dependence on the interactive terminal's input or output. The console log and PID file sit outside the batch archive so they cannot invalidate its final inventory.

```sh
cd '/Users/adrien/Desktop/Niko projects/OptimalComputation'
/tmp/optimal-harness-venv/bin/python - <<'PY'
from pathlib import Path
import subprocess
import sys

run = Path('runs/suite-full-ready-20261123')
console = run.with_name(run.name + '.console.log')
with console.open('ab', buffering=0) as log:
    process = subprocess.Popen(
        ['caffeinate', '-i', sys.executable, 'scripts/search_batch.py',
         '--output', str(run), '--resume'],
        stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
        start_new_session=True,
    )
run.with_name(run.name + '.pid').write_text(str(process.pid) + '\n')
print('Started PID', process.pid, 'console:', console)
PY
```

After launch, inspect `runs/suite-full-ready-20261123.console.log`, the batch's `summary.json` and `events.jsonl`, and individual `feedback.json` files. Summary totals refresh at loop completion. If a launched campaign stops, first verify that it has no active process, then use the same saved-run command to resume; file locks prevent duplicate launchers. Keep Docker available.

The completed smoke audit can be reproduced without model calls:

```sh
python3 scripts/audit-search-batch.py runs/suite-smoke-20261123 --output /tmp/suite-smoke-audit.json
```
