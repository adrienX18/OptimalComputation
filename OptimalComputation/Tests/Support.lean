import OptimalComputation.Evaluation.ObjectiveRegistry

/-! Shared helper for tests of the certified catalog path. -/
namespace OptimalComputation.Tests
open Candidates Evaluation

/-- Proof-free view of a catalog evaluation, so tests can compare outcomes with
`==`. An `accepted` value here is a test observation, never a certificate. -/
inductive CatalogResult where
  | accepted (record : ExecutionRecord)
  | failure (reason : Failure)
  | exhausted (details : Exhaustion)
  deriving Repr, BEq

/-- Evaluate a raw artifact through the single acceptance path. -/
def certify (raw : RawCandidate) (values : List Int) (budget : Nat) : CatalogResult :=
  match evaluateObjective objectiveCatalog raw values budget "test" Evaluation.latency with
  | .accepted accepted => .accepted accepted.execution.record
  | .failure reason => .failure reason
  | .resourceExhausted details => .exhausted details

end OptimalComputation.Tests
