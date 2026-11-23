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
| `max_tokens` | Provider output-token limit, default 4096 |
| `prompt_bytes` | Maximum UTF-8 bytes of serialized messages, default 32000 |
| `code_bytes` / `notes_bytes` | Maximum accepted generator size / notebook shown next time, default 8000 / 2000 |
| `request_timeout` | Provider request timeout in seconds, default 120 |
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
python3 scripts/check-search.py --integration
.venv/bin/python scripts/check-search-providers.py
```

The ordinary tests use deterministic doubles for a fast 100-attempt check.
Integration tests use real Docker and Lean. Provider tests use the installed
SDK with mocked HTTP; none of these tests makes paid model calls.
