# Minimal LLM search

One model proposes one design, receives feedback, and tries again, for at most
100 attempts. The result is the best certified design found, including the
original certified baseline. There is no claim that it is globally optimal.

## Start a run

Requires the pinned Lean toolchain, Python 3.10–3.15, and a running Docker
engine. Run from the repository root on macOS or Linux:

```sh
lake build
python3 -m venv .venv
.venv/bin/pip install -r requirements-search.txt
docker pull python:3.12-slim-bookworm
cp configs/search.example.json /tmp/search.json
```

Edit `/tmp/search.json`: replace `model` with a model you have access to and
select a task. Copy `.env.example` to `.env` in the repository root and fill in
the key for your chosen provider. For example:

```dotenv
ANTHROPIC_API_KEY=your_key_here
```

The harness loads `.env` automatically for live calls, including when resumed
or launched by Codex. Shell exports still work and take precedence over `.env`.
Values are read literally, without variable expansion or shell execution.
The file is ignored by Git, omitted from run snapshots, and never mounted in
generator containers. Loaded keys receive the same log redaction as exported
keys. Do not put secrets in the JSON configuration or commit them.

Then run:

```sh
.venv/bin/python scripts/search.py --config /tmp/search.json --output runs/first
```

The output directory must be new. Run directories and `.venv` are gitignored.
API calls incur the chosen provider's charges. Start with a few attempts to
check your chosen model and budgets before using all 100.

| Provider | `model` value | Environment variable |
| --- | --- | --- |
| OpenAI | `openai/YOUR_MODEL_ID` | `OPENAI_API_KEY` |
| Anthropic | `anthropic/YOUR_MODEL_ID` | `ANTHROPIC_API_KEY` |
| Google Gemini | `gemini/YOUR_MODEL_ID` | `GEMINI_API_KEY` |

The adapter uses [LiteLLM's local Python SDK](https://docs.litellm.ai/docs/python_sdk),
not a proxy server. Other SDK-supported providers can be selected through their
provider/model names. The optional `api_base` supports alternate endpoints;
do not put credentials in the URL or configuration. Additional provider-specific
authentication follows the SDK. The three adapters above are tested with mocked
HTTP responses; access to a particular live model depends on your account.

Optional `temperature` and `reasoning_effort` are passed through if specified.
Unsupported parameters cause an archived error rather than being silently
dropped. Omit parameters that your model does not support. The model must return
text; streaming, tools, provider fallbacks and automatic retries are disabled.

## Configuration

The example file lists all default resource controls. Config files use JSON and
reject unknown fields, including API keys.

| Setting | Meaning |
| --- | --- |
| `task` | `matvec`, `matmul`, `polynomial`, `gram`, `two-stage`, or toy tasks `tiny`, `pair` |
| `objective` | `latency-v1` or `energy-proxy-v1`; lower is better |
| `configuration` | Initial `[lanes, banks]`, each 1, 2, 4 or 8; toy tasks use `[1, 1]` |
| `attempts` | 1–100 slots, including malformed replies, errors and interruptions; baseline is extra |
| `seed` | Run seed, integer 0–2147483647; default 0; see reproducibility below |
| `max_tokens` | Provider output-token limit, default 32768 |
| `prompt_bytes` | Maximum UTF-8 bytes of serialized messages, default 32000 |
| `code_bytes` / `notes_bytes` | Maximum accepted generator size / notebook shown next time, default 8000 / 2000 |
| `request_timeout` | Provider request timeout in seconds, default 600 |
| `generator_timeout` | Docker generation wall-time limit in seconds, default 30 |
| `check_timeout` | Wall-time limit per simulation and per certification phase, default 120 |
| `boundaries` / `terms` | Existing checker limits, default 1000000 / 4096 |
| `image` | Already pulled Python Docker image, resolved to an immutable local image ID |

For latency, the candidate must retain the configured lane/bank counts. For
energy, it can change them because provisioning contributes to energy. Energy
remains the existing abstract proxy, not measured electricity consumption.

Large candidates may require longer proof time. A limit is recorded as an
inconclusive failure; it does not establish that the candidate is incorrect.
The prompt byte limit is deliberately simple and is not an exact token count.
Leave space within the chosen model's context window for its output as well.

The shared output budget is 32,768 tokens for all providers. For reasoning
models it may include thinking as well as the returned text; the pilot's
16,384-token budget was exhausted by one Opus response before it produced code.
The ten-minute request timeout allows longer answers to finish. Both settings
can still be overridden per run. Prompt and generator byte limits stay the same.

Ready-to-run configurations for the two selected models are
[`search.opus.json`](../configs/search.opus.json) and
[`search.astra.json`](../configs/search.astra.json). Each uses the polynomial
task, medium reasoning, eight lanes/banks, and 100 attempts with these increased
budgets. The earlier smoke-test files retain their original settings.

## Five-model batch

[`search.batch.json`](../configs/search.batch.json) specifies five models, seeds
`11, 23, 37, 53, 71`, and 50 attempts per model/seed: **25 independent loops and
1,250 total attempt slots**. At most five loops run concurrently in separate
processes. Each starts from the original baseline with its own notebook and
history; it cannot see another run's discoveries. The task stays polynomial,
the objective latency, the hardware eight lanes/eight banks, and reasoning
effort medium, with the common 32,768-token output budget.

The model IDs were checked on 2026-11-23 and are fixed in the configuration:

| Name | Provider/model ID |
| --- | --- |
| Fable 5.2 | `anthropic/claude-fable-5-2` |
| Opus 5.5 | `anthropic/claude-opus-5-5` |
| Sonnet 5.5 | `anthropic/claude-sonnet-5-5` |
| Astra 6.2 | `openai/gpt-6.2-astra` |
| Sol 6.2 | `openai/gpt-6.2-sol` |

See Anthropic's [Fable overview](https://platform.claude.com/docs/en/models/fable-5-2/overview)
and [model lifecycle](https://platform.claude.com/docs/en/about-claude/model-deprecations),
and the [OpenAI model catalog](https://developers.openai.com/api/docs/models).
No automatic substitution or upgrade takes place. The actual response model
and any provider fingerprint are retained with the response.

Test exactly two attempts per model, using only the first seed (ten calls total):

```sh
.venv/bin/python scripts/search_batch.py --config configs/search.batch.json --output runs/five-model-smoke --smoke
```

Prepare the full experiment without calling any model or launching generators:

```sh
.venv/bin/python scripts/search_batch.py --config configs/search.batch.json --output runs/five-model-night --prepare-only
```

**Only when ready to launch**, run the saved plan:

```sh
.venv/bin/python scripts/search_batch.py --output runs/five-model-night --resume
```

Keep this process and Docker running, and prevent the computer from sleeping.
This is a local foreground runner, not a hosted scheduler. Repeating `--resume`
continues unfinished loops and skips completed ones. A failed or interrupted
attempt still consumes its slot. Three consecutive API errors stop that loop;
other loops continue. The batch reports incomplete and exits nonzero if any
loop stops early. It never silently adds paid retries to reach 50 successes.
Providing `--config` without `--smoke` or `--prepare-only` starts a full batch
immediately; use the prepare/resume pair when staging an experiment.

Each batch saves a manifest with its exact matrix, configurations, source hashes,
Python version and Git revision, plus a source snapshot and working-tree patch.
`runs/<model>/seed-<seed>/` contains the complete individual run archive described
below. `jobs/` preserves every launch's command, stdout, stderr and result, even
after resuming. `events.jsonl`, `summary.json` and `attempts.csv` provide batch
progress and comparisons; summaries refresh as loops finish. `inventory.json`
records every artifact's size and SHA-256 at preparation and orderly shutdown,
excluding locks and the inventory itself. Raw records are retained even for
rejected designs. Batch resume refuses changed source, Python or saved configs;
individual resume also checks the recorded SDK dependencies and Docker image.

## Full workload suite

[`search.suite.json`](../configs/search.suite.json) lists all sixteen cases:
matrix multiplication, polynomial evaluation, Gram/symmetric product and the
two-stage linear map, each on three fixed latency configurations `(8,8)`, `(8,1)`
and `(2,8)`, plus one energy case with a free choice of all sixteen configurations.
The energy baseline starts at `(8,8)`; proposals may change it. Matrix-vector
remains a separate validation case, outside this measured suite.

The same five fixed model IDs and seeds apply to every case. Fifty attempts per
loop gives **400 loops and 20,000 attempt slots**, with at most five loops active
across the entire suite. This is a new campaign: polynomial `(8,8)` is repeated,
and the earlier 1,250-attempt archive remains unchanged.
Only one memory-heavy Lean kernel check runs at a time per checkout, guarded by
an OS file lock. Model calls can still overlap. `certification/kernel-queue.json`
records waiting separately from the active verification timeout.

The batch runner accepts an optional `instances` map. Each name specifies exactly
`task`, `objective` and `configuration`; the shared `run` settings supply budgets.
Names become directories under `runs/<instance>/<model>/seed-<seed>/`. The manifest,
summary and attempt CSV retain the instance and objective, so unlike units are
never implicitly pooled into one best score. Older single-case configurations
continue to work with their original directory layout.

Test three attempts for every case/model using the first seed (80 loops, 240 calls
at most), then audit the complete archive:

```sh
.venv/bin/python scripts/search_batch.py --config configs/search.suite.json --output runs/suite-smoke --smoke --smoke-attempts 3
python3 scripts/audit-search-batch.py runs/suite-smoke --output /tmp/suite-smoke-audit.json
```

Prepare the full campaign without any calls; launch it only after approval:

```sh
.venv/bin/python scripts/search_batch.py --config configs/search.suite.json --output runs/suite-full --prepare-only
# Only after the go:
.venv/bin/python scripts/search_batch.py --output runs/suite-full --resume
```

The suite uses a 48,000-byte prompt budget and 600 seconds per verification phase.
The larger prompt fits larger workload layouts, two complete 8,000-byte generators
and compact history; it is still bounded. The longer verification budget accommodates
larger certificates. Output tokens (32,768), generator bytes (8,000), generator
runtime (30 seconds) and the other machine/checker rules are unchanged. These budget
and prompt changes are recorded, so the prior polynomial campaign is a historical
comparison rather than an identical rerun. Energy prompts state the frozen formula,
BRAM allocation rule, and the baseline's actual score breakdown.

New simulation traces are stored as `trace.json.gz`, with original byte counts
and SHA-256 hashes in `trace.metadata.json`. Compression is verified by a full
decompression/hash check before removing the redundant plain JSON. No events are
sampled, shortened or discarded. The archive auditor checks both stored-file
hashes and the decompressed trace hashes. This matters for matrix workloads,
where retaining both copies would multiply disk use. Read a trace with
`gzip -dc path/to/trace.json.gz`; older archives retain their original format.

`check-search-suite.py --output <new-directory>` runs all sixteen cases through
real Docker generation, simulation, certification and scoring using known
reference designs, with no API calls. Its energy designs change hardware to
`(4,4)` and are also rejected under a pinned `(8,8)` latency objective. This tests
the infrastructure independently of whether a model succeeds in three attempts.

### What the seeds reproduce

For attempt `i`, derive a 31-bit seed from the first four bytes of
SHA-256(`naive-search-seed-v1:<run seed>:<i>`), in big-endian order, then mask with
`0x7fffffff`. The derivation is independent of parallel execution order. Put both
seeds in the prompt and save them in `attempts/NNNN/randomness.json`. Seed Python's
global `random` generator and `PYTHONHASHSEED` in the container; generated code
can use `candidate_tools.seed()` for its own PRNG. Wall-clock durations are kept
in the archive but omitted from the feedback sent back to the model.

Pass the attempt seed to the model API only if the installed adapter supports
it. These OpenAI adapters support a best-effort seed; these Anthropic adapters
have no sampling-seed parameter. Claude sees the seed in its prompt, but that
does **not** make its sampling reproducible. Even OpenAI's seed cannot guarantee
identical output; see its [reproducibility guidance](https://developers.openai.com/api/docs/guides/advanced-usage).
Generated code could also override the seed or use another entropy source.
Thus fixed seeds identify comparable repeats and stabilize ordinary local
randomness; they do not guarantee byte-identical live reruns. Save the exact
responses, code and candidates for inspection and offline replay. Public
verification fixtures stay identical across repeats so scores remain comparable.

## What happens in an attempt

1. Build a fresh prompt containing the task and hardware rules, helper code,
   baseline layout, best certified generator, latest generator and feedback,
   a compact history, and the most recently returned notebook.
2. Save the exact model request, then request one response:
   `{"idea": "...", "code": "...", "notes": "..."}`.
3. Save the response and proposal. Execute `code` inside Docker. Its `build()`
   must return an ordinary `candidate-v1` dictionary. `candidate_tools.baseline()`
   supplies a fresh original candidate, and helpers construct instructions.
4. Save the candidate. Check its workload/configuration, then simulate every
   public fixture with full traces. If they pass, run symbolic certification,
   generate its Lean proof and check it in the kernel.
5. Score accepted candidates through the existing Lean `evaluateObjective` API.
   Keep a strict improvement; on a tie, keep the earlier incumbent. Save feedback
   and begin the next attempt.

For example, the smallest valid generator is:

```python
from candidate_tools import baseline

def build():
    return baseline()
```

The model can change arithmetic, register use, memory layout and schedule. It
cannot modify the task, machine, checker or objective. Python loops generate
static schedules; they do not add runtime branching to the modeled hardware.
The generator sees only its source, helpers and baseline. Its container is
non-root, has no network, no host credentials, no writable host mount, a read-only
root filesystem, 256 MiB of memory, one CPU, a PID cap and a 16 MiB temporary area.
Candidate output is limited to 8 MiB. The host verifier never imports that code.

The public fixtures are fixed at startup and saved as actual input vectors.
Polynomial search does not receive the held-out Horner counterexamples.
Concrete failures, conservative analysis and exhausted resources retain their
own categories. Uncertified observed cycles are feedback only, not accepted
scores. A simulation failure skips certification and records the reason.

The notebook is clipped to `notes_bytes`; latest feedback is bounded; history
keeps short idea/status/score rows. Old history entries are dropped first when
the prompt is too large, followed by the notebook. Best/latest code is kept
whole. If that still cannot fit, the run stops with an explicit error. None of
this truncates the source archive. A malformed response does not erase the last
notebook. Model notes are fallible advice, not verified facts.

## Everything available for later analysis

```text
run/
  manifest.json           config, source hashes, revision, Python/adapter versions, image ID
  source/                 snapshot of harness, Lean sources and build configuration
  working-tree.patch      tracked differences from the recorded revision
  events.jsonl            durable chronological events
  baseline.json           public inputs and baseline metadata
  baseline/...            exported candidate, baseline evaluations and scores
  startup/...             Docker inspection commands and results
  attempts/0001/
    request.json          full prompt and model parameters, saved before calling
    randomness.json       run/attempt seeds, API seed support and sent seed
    provider-*.json       provider request/response data exposed by SDK callbacks
    response.json         full normalized response, usage, metadata and cost estimate
    model-stdout.txt      SDK output (stderr saved separately)
    proposal.json         full returned idea, code and notes
    generator.py          exact accepted generator source
    generation/           container ID/name, inputs, commands, output and cleanup
    candidate.json        exact generated output bytes
    simulation/...        input vectors, command logs and complete traces
    simulations.json      all public fixture outcomes
    certification/        candidate snapshot, generated Lean source, full logs and result
    score.json            full accepted score and execution record, when certified
    feedback.json         outcome used to construct later prompts
    error.json            failure and traceback, when a stage raises an exception
  best.json               incumbent and relative artifact directory
  summary.json            all attempt outcomes and incumbent
  summary.csv             convenient tabular attempt outcomes
```

Later stages are absent when earlier stages fail. API errors have a separate
`api-error.json`; skipped certification has an explicit reason file. Every
subprocess record includes its arguments, limits, exit status, elapsed time and
full stdout/stderr produced before completion or termination. Traces are saved
both as JSON and gzip. A generated `Certificate.lean` is a proof candidate until
the saved result says it was accepted; its mere presence proves nothing.

The archive includes provider-exposed reasoning or other response fields when
returned, but cannot include private model reasoning the provider withholds.
Keys, authorization headers and known environment secret values are redacted.
Token usage and cost estimates are retained when available; cost estimates are
not billing receipts. Models absent from the installed SDK's rate table get a
null estimate, rather than a misleading zero. Archives stay local; prompts go to the chosen model
provider. Keep the run
directory if you want to retain the records; traces and proofs can use substantial
disk space. Provider inference and cost estimates may change over time despite
identical configuration.

## Resume and offline replay

```sh
.venv/bin/python scripts/search.py --output runs/first --resume
```

Resume uses the saved configuration. Completed attempts are preserved; an
unfinished attempt is marked interrupted, keeps its files, consumes its slot,
and is not sent again. Remaining slots continue. This deliberately prefers a
missing answer over an accidental duplicate paid call. A lock prevents two
processes from using the same run. Three consecutive API errors stop the run;
explicit resume can try the remaining slots. Check `summary.json` and
`events.jsonl` for completed count and stop reason.

Resume rejects changed source hashes, Python version, recorded SDK dependency
versions or Docker image ID. Restore that environment or start a separate run.
The source snapshot and versions aid reproduction, but are not a complete OS
or transitive-dependency environment lock.

For an offline end-to-end test, `--replay replies.json` replaces API calls with
a JSON list of proposal objects or raw response strings. It still runs the
actual Docker generator and Lean verifier. It does not require LiteLLM:

```sh
python3 scripts/search.py --config /tmp/search.json --replay /tmp/replies.json --output runs/replay
python3 scripts/check-search.py
python3 scripts/check-search-batch.py
python3 scripts/check-search.py --integration
.venv/bin/python scripts/check-search-providers.py
```

The ordinary tests use deterministic doubles for a fast 100-attempt check.
Integration tests use real Docker and Lean. Provider tests use the installed
SDK with mocked HTTP; none of these tests makes paid model calls.
