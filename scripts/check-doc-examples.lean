import OptimalComputation

/-! Compile/run the concrete public API examples from docs/extensions.md. -/
namespace DocumentationExamples
open OptimalComputation OptimalComputation.Evaluation OptimalComputation.Workloads

def loadCount : Objective := {
  identifier := "load-count-example-v1"
  unit := "loads"
  breakdown := fun r => [⟨"loads", r.counters.loads, 1⟩]
}

def packageProvedCandidate (spec : Specification) (adapter : ScalarAdapter spec)
    (domain : ∀ x, Decidable (spec.AllowedInput x))
    (proof : VerifiedCandidate adapter) : VerifiedArtifact :=
  ⟨spec, adapter, domain, proof⟩

def matvecArtifact : VerifiedArtifact :=
  packageProvedCandidate MatVec.specification MatVec.adapter inferInstance
    Examples.MatVecNaive.verified

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

#eval rescoreExample
end DocumentationExamples
