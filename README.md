# Optimal Computation

This project explores whether AI can make a calculation run faster or cheaper while proving that it still gives the right answer.

The project centers on a **model of how hardware behaves**: what work it can do, how long operations take, and what computing and memory resources are available. This model gives us a way to compare different approaches and explore trade-offs between latency and cost.

The aim is to use AI to find better ways to carry out a computation within those limits. **Lean**, a tool for checking mathematical proofs, will help verify that proposed solutions respect the model and produce the correct result for every allowed input.

We will start with small mathematical computations in software. Testing on physical hardware would come later.

Read [report.md](report.md) for the research results and [DEEP_DIVE.md](DEEP_DIVE.md)
to inspect the critical source, proof obligations, model exchanges, and evidence
through exact excerpts and pinned file/line links.

## Run the experiment

The foundation now has verified naive matrix-vector and matrix-matrix baselines,
a fixed hardware model, and independent latency and abstract-energy objectives.
Section 9 adds certified polynomial, symmetric-product and two-stage baselines,
a deterministic scheduling heuristic, and reproducible experiment records. A
minimal LLM loop now proposes up to 100 designs, learns from feedback, and saves
every attempt. [PLAN.md](PLAN.md) defines the scope;
[docs/decisions.md](docs/decisions.md) records the resolved design choices.

Install [elan](https://github.com/leanprover/elan), then run from this directory:

```sh
lake build
lake test
lake exe optimal_computation list-candidates
lake exe optimal_computation evaluate matvec-naive-v1 --fixture generated-23 --objective latency-v1
lake exe optimal_computation evaluate matmul-naive-v1 --fixture generated-23 --objective energy-proxy-v1 --json
.lake/build/bin/optimal_computation export-candidate matvec-naive-v1 > /tmp/candidate.json
lake exe optimal_computation simulate /tmp/candidate.json  # unverified and unscored
```

[lean-toolchain](lean-toolchain) pins Lean 4.35.0 and its bundled Lake. There are no
external Lean dependencies or FPGA tools. A fresh machine needs that toolchain;
Python 3 supplies the certification driver and independent validation scripts.

| Certified candidate | Latency (cycles) | Abstract energy units |
| --- | ---: | ---: |
| `tiny-multiply-v1` | 6 | 86 |
| `matvec-naive-v1` | 2,143 | 59,607 |
| `matmul-naive-v1` | 34,303 | 954,087 |
| `product-pair-serial-v1` | 12 | 172 |
| `product-pair-parallel-v1` | 6 | 202 |
| `matvec-naive-v2` | 1,344 | 39,632 |
| `matmul-naive-v2` | 21,504 | 634,112 |

The `-v2` baselines run exactly the v1 instructions, but issue each on its
predecessor's completion boundary instead of one idle cycle later. Use them as
the naive comparison point; v1 stays frozen for reproducibility.

A hand-built eight-lane schedule,
[`docs/candidates/matvec-grid-exchange-v1.json`](docs/candidates/matvec-grid-exchange-v1.json),
now has an all-input kernel certificate for its 79-cycle execution. The reusable
checker supports all seven workloads and arbitrary candidate identifiers:

```sh
python3 scripts/certify.py docs/candidates/matvec-grid-exchange-v1.json --output /tmp/GridCertificate.lean
```

It reports `Correct` after kernel verification or `Not certified` with a reason.
See [automatic certification](docs/certification.md) for the proof artifact,
error categories, resource limits and use with the existing scoring API.

## Run an LLM search

Choose a provider and model in [configs/search.example.json](configs/search.example.json),
put its API key in a local `.env` file (copy `.env.example`), then use the
sequential search harness:

```sh
python3 -m venv .venv
.venv/bin/pip install -r requirements-search.txt
docker pull python:3.12-slim-bookworm
.venv/bin/python scripts/search.py --config configs/search.example.json --output runs/first
```

Run `lake build` first and keep Docker running. Each attempt generates a candidate
inside Docker, receives simulation and proof feedback, and can replace the best
design only after certification. Fresh bounded prompts carry the best design,
latest feedback, compact history and a short notebook. The complete records stay
on disk. See [the search guide](docs/search.md) for configuration, provider selection,
resume, archive contents and limitations.

For a fixed five-model experiment, [configs/search.batch.json](configs/search.batch.json)
defines five seeds and 50 attempts per model/seed, with at most five loops running
at once. `scripts/search_batch.py --smoke` tests two attempts per model;
`--prepare-only` saves the full plan without launching it. See the
[batch commands and seed limitations](docs/search.md#five-model-batch).

The [first five-model experiment analysis](analysis/2026-11-23-five-model-search/report.md)
reports convergence, certified results, failures and resource use across 1,250 attempts.

The [full workload suite](docs/search.md#full-workload-suite) uses
[`configs/search.suite.json`](configs/search.suite.json): all four workloads,
three latency configurations and one energy case each. Its 16 cases expand to
400 loops / 20,000 attempts. Use `--smoke --smoke-attempts 3` for the 240-attempt
test, or `--prepare-only` to save the full plan without launching it.
See the [readiness checks and archive audits](docs/results/full-suite-readiness-v1/README.md).

## Earlier experiments

[Section 9 usage, algorithms, proof status, and measurements](docs/experiments.md)
explain the new workloads and configuration-specific certificates. For example:

```sh
lake exe optimal_computation evaluate polynomial-naive-v1 --configuration 8,1
python3 scripts/experiment.py --task polynomial --output /tmp/polynomial-experiment
```

These are model results. Energy coefficients are hypothetical; physical timing,
routing and power are uncalibrated. Every accepted candidate has safety and
correctness proofs for all allowed inputs. Saved JSON is a report, not a proof
certificate. Optional exported traces are explicitly observational simulations.

- [CLI usage, custom inputs, failures, traces and candidate files](docs/usage.md)
- [API and proof boundary](docs/api.md) · [Adding workloads, candidates and objectives](docs/extensions.md)
- [Machine contract](docs/machine-contract.md) · [Assumptions](docs/assumptions.md)
- [Objectives](docs/objectives.md) · [Saved results](docs/results/README.md)
- [Reproducible validation and clean-checkout evidence](docs/validation.md)
