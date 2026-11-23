import OptimalComputation.CLI
import OptimalComputation.Certification.Catalog

namespace OptimalComputation.Certification
open Lean Evaluation

/-- Score a newly constructed proof-bearing artifact through the existing API.
The driver only accepts this output after the entire file passes kernel checking. -/
def printScore (artifact : VerifiedArtifact) (objectiveId fixture : String) : IO Unit := do
  let result : Json := match CLI.objectives.find? (·.identifier == objectiveId) with
    | none => (CLI.Error.mk "unknown-objective" objectiveId Json.null 1).toJson
    | some objective => match CLI.fixtureValues artifact.specification.identifier fixture with
      | .error e => e.toJson
      | .ok values =>
        match evaluateObjective [artifact] artifact.verified.candidate.toRaw values
            artifact.verified.sufficientBoundaries fixture objective with
        | .accepted score => score.toJson
        | .failure reason => (CLI.failureError reason).toJson
        | .resourceExhausted details => (CLI.exhaustionError details).toJson
  IO.println ("CERTIFIED_SCORE " ++ result.compress)

end OptimalComputation.Certification
