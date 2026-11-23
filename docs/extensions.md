# Extending the foundation

The public boundary is a fixed mathematical specification, a finite candidate,
the shared machine, a proof-carrying execution, and an independent objective.
Read the [machine contract](machine-contract.md) before changing any of these.
The examples below compile in `scripts/check-doc-examples.lean`:

```sh
lake env lean scripts/check-doc-examples.lean
```

## Add a workload and its baseline

1. Define a `Workloads.Specification`: a stable versioned `identifier`, `Input`
   and `Output` types, `AllowedInput : Input → Prop`, and pure `reference`.
   Supply decidability for the input predicate. The reference contains no physical
   addresses or calls to the simulator. See `Workloads/MatVec.lean` and `MatMul.lean`.
2. Define a `ScalarAdapter specification` with a `Shape`, matching identifier,
   `inputScalars`, `decodeInput`, `outputScalars`, and `decodeOutput`. Prove
   `input_roundtrip`, `output_roundtrip`, and `input_fits` for every allowed input.
   The output decoder only receives output scalars. See `Workloads/MatrixAdapters.lean`.
3. Supply the required naive executable baseline using ordinary algorithm order,
   one active lane, row-major storage where applicable, explicit operand loads,
   signed48 accumulation and output stores. Its primary configuration is the
   shared default `(8,8)`. Account for scratch and intermediate storage; the
   reference function must never supply candidate computations or memory.
4. Prove all-input execution safety and functional correctness against the actual
   machine, then register the exact artifact as described below. A computation is
   incomplete until its naive baseline and proofs exist.
5. Add independent fixtures, negative cases, hand-derived schedule/counter checks,
   and versioned results under every available objective. Record configuration,
   layout and runtime inputs. Configuration variants need their own certificates
   for accepted scoring; otherwise label their records as simulations. Re-run
   earlier baselines to establish that adding the workload changed no semantics.

`Examples/MatMulNaive.lean`, `MatMulProof.lean`, `MatMulBaseline.lean`, and
`MatMulResults.lean` demonstrate the complete path, with reusable dot-product
reasoning. It added one catalog entry without changing the interpreter or scoring
functions. The CLI can immediately list and evaluate a new registered artifact
using `--input`; add fixture convenience in `CLI.fixtureValues` separately.

## Construct and prove a candidate

Start with `Candidates.RawCandidate`: model/format/workload versions, identifier,
configuration, explicit input/output/scratch slot lists, and a finite schedule of
cycle/lane/instruction entries. `inspect adapter.shape raw` produces a typed
`Candidate adapter.shape` and an exact serialization equality, or structured
failure. `checkStatic candidate` checks static batch rules using `Hardware.checkBatch`.
Neither step certifies numeric safety, readiness, termination or correctness.
`simulate` can expose a concrete failure; successful simulations remain unverified.

For the seven supported workloads, [automatic certification](certification.md)
can now construct this proof from a candidate JSON file. A new workload can
supply a one-time `Certification.Problem` and catalog entry to use the same
checker. Hand-written proofs remain supported through the original interface.

Construct a `VerifiedCandidate adapter` with these fields:

```text
candidate            : Candidate adapter.shape
sufficientBoundaries : Nat
safety               : ExecutionSafety adapter candidate sufficientBoundaries
correctness          : FunctionalCorrectness adapter candidate sufficientBoundaries
```

`safety` quantifies over every allowed logical input and proves that
`executeValues candidate (adapter.encode input allowed) sufficientBoundaries false`
returns an actual success record. This establishes finite legal execution,
initialized reads, valid intermediate widths, drained pipelines and written outputs.
`correctness` quantifies over each successful record of that execution and equates
its outputs to `adapter.outputScalars (specification.reference input)`.

Useful proof surfaces are `Hardware.step`, `Evaluation.run_step`,
`Evaluation.Serial.run_serial`, `Examples.SerialDot.executes_prefix`, and
`Evaluation.run_path`. The tiny proof uses direct machine reduction; matrix
baselines compose instruction/dot-product proofs; the manual pair uses explicit
step paths. These all refer to the executable transition, not a second model.
Keep proof roots in the reproducible axiom audits: dependencies are limited to
standard `propext`, `Quot.sound` and `Classical.choice`, with no admitted proofs,
custom axioms or native-decision proof shortcuts.

Package only a completed certificate, for example:

```lean
import OptimalComputation
open OptimalComputation OptimalComputation.Evaluation OptimalComputation.Workloads

def packageProvedCandidate (spec : Specification) (adapter : ScalarAdapter spec)
    (domain : ∀ x, Decidable (spec.AllowedInput x))
    (proof : VerifiedCandidate adapter) : VerifiedArtifact :=
  ⟨spec, adapter, domain, proof⟩

def matvecArtifact : VerifiedArtifact :=
  packageProvedCandidate MatVec.specification MatVec.adapter inferInstance
    Examples.MatVecNaive.verified
```

Add the artifact to `Evaluation.objectiveCatalog`, using a unique stable candidate
identifier. The catalog is trusted source code: reviewers must check the intended
specification, codec and certificate, not just its label. `lookupArtifact` checks
full raw equality including configuration, layout, schedule and versions before
scoring. Changing any of those fields invalidates lookup for that catalog entry.
Reusing an identifier for a different specification is not an acceptable extension.

The catalog is the only registry and `evaluateObjective` the only acceptance
path; an artifact that is not exactly registered returns `unverifiedCandidate`.
Use `inspect`, `checkStatic` and `simulate` to diagnose such an artifact. Never
accept JSON correctness labels or status strings as certificate authority. Only
`CertifiedExecution` supplies the actual-run and input equalities needed by
`AcceptedScore`.

Adding a catalog entry changes the catalog sizes asserted in
`OptimalComputation/Tests/CLI.lean` and `scripts/check-cli.py`; update those
counts, add the new proof roots to an audit script, and adjust its declaration
count in `scripts/validate.py`.

## Add an independent objective

An objective declares a unique identifier, unit, direction (currently `minimize`),
optional fixed `CoefficientProfile`, and pure record-to-`ScoreTerm` breakdown.
For example:

```lean
def loadCount : Objective := {
  identifier := "load-count-example-v1"
  unit := "loads"
  breakdown := fun r => [⟨"loads", r.counters.loads, 1⟩]
}
```

`Score.value` sums the displayed quantity × coefficient terms. Prove the intended
formula and add independently calculated test results; `scoreRecord` alone does
not establish execution validity. Add the new objective to `CLI.objectives` if it
should be selectable by CLI. No workload, program, interpreter or admissibility
change is required. Keep each coefficient profile fixed within an experiment;
changing it requires a new objective/profile identifier and new saved results.

The core usage is:

```lean
def rescoreExample : IO Unit := do
  let some raw := selectArtifact objectiveCatalog "tiny-multiply-v1"
    | throw <| IO.userError "Missing artifact"
  let .accepted accepted := evaluateObjective objectiveCatalog raw [-7, 6] 7 "example" latency
    | throw <| IO.userError "Evaluation did not succeed"
  let energyResult := accepted.rescore energy
  let loadsResult := accepted.rescore loadCount
  unless energyResult.result.value == 86 && loadsResult.result.value == 2 &&
      energyResult.execution.record == accepted.execution.record do
    throw <| IO.userError "Rescoring example disagrees"
  IO.println "PASS: documented same-record rescoring and custom objective"
```

`AcceptedScore.rescore_preserves_record` proves record identity; `AcceptedScore.correct`
derives output correctness. These guarantees come from the Lean value and its
proofs, not from its JSON export. Trace-derived statistics require additional
evidence: current accepted certificates use trace-disabled execution, so the CLI's
observational trace export cannot silently become a certified trace objective.

## Boundary for future strategies

A future strategy may construct finite raw candidates, call `inspect`, `checkStatic`
and `simulate`, read structured failures and exhaustion, and retain its own history.
A strategy outside Lean can do the same through the CLI: `export-candidate` provides
a starting file and `simulate` returns cycles, counters, structured failures and a
single-input reference check ([usage](usage.md#simulate-an-unverified-candidate-file)).
To obtain an accepted score, it must supply a checked all-input certificate through
the trusted artifact registration boundary and call `evaluateObjective`. It can
read independent objective results or rescore an existing certified execution.

The strategy has no authority to change hardware semantics, admissible configuration
rules, numeric widths, input domains, workload references, fixed objective profiles,
or the definition of acceptance. Inputs, model versions and comparison profiles
must stay explicit in its history. Exhaustion is inconclusive, and a passing test
cannot replace a proof. Model corrections require an explicitly new version and
rerun results, not a rule change that makes a failing proposal pass.

No strategy implementation is included: there is no scheduler choosing improvements,
search loop, LLM client, policy framework or strategy benchmark. The ordinary
baseline generators and fixed configuration tests only implement known schedules.
