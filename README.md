# Optimal Computation

This project explores whether AI can make a calculation run faster or cheaper while proving that it still gives the right answer.

The project centers on a **model of how hardware behaves**: what work it can do, how long operations take, and what computing and memory resources are available. This model gives us a way to compare different approaches and explore trade-offs between latency and cost.

The aim is to use AI to find better ways to carry out a computation within those limits. **Lean**, a tool for checking mathematical proofs, will help verify that proposed solutions respect the model and produce the correct result for every allowed input.

We will start with small mathematical computations in software. Testing on physical hardware would come later.

## Run the experiment

The foundation now has verified naive matrix-vector and matrix-matrix baselines,
a fixed hardware model, and independent latency and abstract-energy objectives.
This release implements no search strategy or AI loop. [STATUS.md](STATUS.md)
records milestone review; [PLAN.md](PLAN.md) defines the scope.

Install [elan](https://github.com/leanprover/elan), then run from this directory:

```sh
lake build
lake test
lake exe optimal_computation list-candidates
lake exe optimal_computation evaluate matvec-naive-v1 --fixture generated-23 --objective latency-v1
lake exe optimal_computation evaluate matmul-naive-v1 --fixture generated-23 --objective energy-proxy-v1 --json
```

[lean-toolchain](lean-toolchain) pins Lean 4.35.0 and its bundled Lake. There are no
external Lean dependencies or FPGA tools. A fresh machine needs that toolchain;
Python 3 is used only for the independent validation scripts.

| Certified candidate | Latency (cycles) | Abstract energy units |
| --- | ---: | ---: |
| `tiny-multiply-v1` | 6 | 86 |
| `matvec-naive-v1` | 2,143 | 59,607 |
| `matmul-naive-v1` | 34,303 | 954,087 |
| `product-pair-serial-v1` | 12 | 172 |
| `product-pair-parallel-v1` | 6 | 202 |

These are model results. Energy coefficients are hypothetical; physical timing,
routing and power are uncalibrated. Every accepted candidate has safety and
correctness proofs for all allowed inputs. Saved JSON is a report, not a proof
certificate. Optional exported traces are explicitly observational simulations.

- [CLI usage, custom inputs, failures and traces](docs/usage.md)
- [API and proof boundary](docs/api.md) · [Adding workloads, candidates and objectives](docs/extensions.md)
- [Machine contract](docs/machine-contract.md) · [Assumptions](docs/assumptions.md)
- [Objectives](docs/objectives.md) · [Saved results](docs/results/README.md)
- [Reproducible validation and clean-checkout evidence](docs/validation.md)
