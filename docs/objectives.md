# Objectives and accepted results

`latency-v1` and `energy-proxy-v1` are pure functions of the same objective-free
`ExecutionRecord`. Both minimize their score. The simulator, workload reference,
program, configuration, and timing rules do not depend on the objective.

Latency is elapsed cycles through the last completion boundary. It has no implied
clock frequency or conversion to seconds. The frozen `energy-coefficients-v1`
profile gives the following hypothetical cost:

```text
cycles * (1 + lanes + allocated_BRAM36)
+ 4 * loads + 4 * stores + additions
+ 8 * multiplications + 9 * multiply_adds
+ register_reads + register_writes
```

The unit is **abstract energy units**, not joules or watt-hours. All coefficients
are positive. Provisioned lanes and allocated BRAM36 blocks are charged for the
whole duration, including idle resources. A MAC receives only its own charge of
nine; it is not counted again as an addition or multiplication. Issued operand
reads include repeated operands and the constant-zero register. Successful
register arrivals are writes; stores do not write a register. Pending pipeline
costs are abstracted into the coefficients. Control/routing/pipeline logic area
remains uncalibrated.

`scoreRecord objective record` is an arithmetic helper, not verification evidence.
An arbitrary record, JSON label, or manually constructed `Outcome.verified` has
no authority to produce an accepted optimization result. `CertifiedExecution`
contains the exact `executeValues` success equality, allowed logical input, raw
scalar input equality, and budget bound for a `VerifiedCandidate`. The candidate
carries separate all-input safety and correctness proofs. `AcceptedScore` also
binds that artifact to the complete raw candidate. Its score and breakdown are
computed, not caller-supplied fields.

`evaluateObjective objectiveCatalog raw values maxBoundaries inputIdentifier
objective` looks up a complete artifact by equality, parses the workload input,
and executes the certified trace-disabled path. The compiled catalog is the
trusted specification/certificate registry. A matching name alone is insufficient.
Unregistered artifacts return `unverifiedCandidate`; invalid inputs and exhaustion
remain failures/outcomes without an accepted score. The earlier `evaluateRegistered`
API retains its existing detailed structural/static diagnostics and behavior.
Trace-enabled runs remain simulations; no equivalence certificate is claimed.

`accepted.rescore objective` preserves the exact original execution and proof.
`AcceptedScore.rescore_preserves_record` proves this identity. `energy_formula`
and `latency_formula` prove the implemented arithmetic, and every reported score
is the sum of its displayed quantity × coefficient terms. The generic result
serializer includes verification status, model/workload/candidate identifiers,
configuration, input label and complete input scalars, outputs, event counts,
storage/resources, objective/unit/direction, coefficients, and breakdown.
Serialized results are reproducible reports, not transportable proof certificates.

## Baseline and manual comparison

The certified default `(8,8)` matrix-vector baseline costs:

```text
2143 * (1 + 8 + 16) + 4*512 + 4*16 + 16 + 8*0 + 9*256 + 816 + 784
= 59607 abstract energy units
```

The matrix-matrix baseline costs 34,303 cycles and 954,087 abstract energy units:
`34303*(1+8+16) + 4*8192 + 4*256 + 256 + 9*4096 + 13056 + 12544`.

The `-v2` baselines execute the same events in fewer cycles, so only the duration
terms change: `1344*(1+8+16) + 6032 = 39632` for matrix-vector and
`21504*(1+8+16) + 96512 = 634112` for matrix-matrix, where 6,032 and 96,512 are
the unchanged activity terms above.

The manual workload computes `(a*b, c*d)` for four arbitrary signed16 inputs.
Both candidates execute four loads, two multiplies, two stores, six register
reads, and six register writes. Inputs occupy slots 0–3 and outputs slots 4–5.
Each multiply uses load/load/multiply/store at relative cycles 0/1/2/5.

| Candidate | Configuration | Active lanes | Cycles | Energy |
| --- | --- | --- | --- | --- |
| `product-pair-serial-v1` | `(1,1)` | 0 | 12 | `12*(1+1+8)+52 = 172` |
| `product-pair-parallel-v1` | `(8,8)` | 0, 1 | 6 | `6*(1+8+16)+52 = 202` |

The serial candidate starts its second sequence at cycle 6. The parallel candidate
starts both at cycle 0. Each has a kernel-checked all-input certificate built from
actual `Hardware.step` equalities and `Evaluation.run_path`, with exact initializer,
program, output and codec bindings. The schedules demonstrate objective preference
reversal; neither is claimed optimal. They are hand-written fixtures, not a search.

The saved records and reproduction commands are in [results](results/README.md).

## Extension points

Add a computation with its independent specification, scalar adapter, candidate,
and actual-execution safety/correctness certificate, then add a `VerifiedArtifact`
to the catalog. Every new computation also needs its naive baseline and equivalent
records under the available objectives. No simulator or objective branches are
needed. Add an objective with stable identifier, unit, direction and a pure
record-to-breakdown function. A changed energy coefficient set requires a new
profile and objective version. See the [extension guide](extensions.md) for
checked API examples and the future strategy boundary. Both matrix baselines and
the small [CLI](usage.md) use these same interfaces; no search strategy or physical
calibration is implemented.
