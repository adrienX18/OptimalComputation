import OptimalComputation.Evaluation.ObjectiveRegistry
import OptimalComputation.Evaluation.Results
import OptimalComputation.Examples.MatVecBaseline

namespace OptimalComputation.Examples.ObjectiveResults
open Evaluation

/-- Execute once and score that very same certified record under both objectives. -/
def both (identifier inputIdentifier : String) (values : List Int) (boundaries : Nat) : IO (List Lean.Json) := do
  let some raw := selectArtifact objectiveCatalog identifier
    | throw <| IO.userError s!"Unknown certified artifact: {identifier}"
  let .accepted accepted := evaluateObjective objectiveCatalog raw values boundaries inputIdentifier latency
    | throw <| IO.userError s!"Certified objective evaluation failed: {identifier}"
  return [accepted.toJson, (accepted.rescore energy).toJson]

def reproduceMatVec : IO Unit := do
  let results ← both "matvec-naive-v1" "generated-23"
    (Workloads.MatVec.scalarInput (MatVecNaive.generated 23)).toList 2144
  IO.println (Lean.toJson results).pretty

def reproduceProductPair : IO Unit := do
  let serial ← both "product-pair-serial-v1" "mixed-signs-four-operands" [-7, 6, 5, -3] 13
  let parallel ← both "product-pair-parallel-v1" "mixed-signs-four-operands" [-7, 6, 5, -3] 7
  IO.println (Lean.toJson (serial ++ parallel)).pretty

end OptimalComputation.Examples.ObjectiveResults
