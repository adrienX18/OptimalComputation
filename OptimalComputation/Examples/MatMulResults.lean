import OptimalComputation.Examples.ObjectiveResults
import OptimalComputation.Examples.MatMulBaseline

namespace OptimalComputation.Examples.MatMulNaive

/-- Both objectives score the same proof-carrying execution. -/
def reproduceObjectives : IO Unit := do
  let results ← ObjectiveResults.both "matmul-naive-v1" "generated-23"
    (Workloads.MatMul.scalarInput (generated 23)).toList 34304
  IO.println (Lean.toJson results).pretty

def reproduceObjectivesV2 : IO Unit := do
  let results ← ObjectiveResults.both "matmul-naive-v2" "generated-23"
    (Workloads.MatMul.scalarInput (generated 23)).toList 21505
  IO.println (Lean.toJson results).pretty

end OptimalComputation.Examples.MatMulNaive
