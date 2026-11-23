import OptimalComputation.Evaluation.Objectives
import Lean.Data.Json.Basic
import Lean.Data.Json.FromToJson.Basic

namespace OptimalComputation.Evaluation
open Lean

private def number (n : Nat) : Json := toJson n
private def numbers (ns : List Nat) : Json := toJson ns
private def text (s : String) : Json := toJson s
private def object := Json.mkObj

/-- Shared by accepted and simulated results so both report one schema. -/
def configurationJson (resources : Hardware.ResourceReport) : Json :=
  object [("lanes", number resources.configuration.lanes),
    ("banks", number resources.configuration.banks)]

/-- The objective-free execution record. Accepted results always pass
`traceCaptured := false` because their certified run disables tracing. -/
def executionJson (r : ExecutionRecord) (traceCaptured : Bool) : Json :=
  let c := r.counters
  let resources := r.resources
  object [
    ("cycles", number r.cycles), ("outputs", Lean.toJson r.outputs),
    ("scheduleSize", number r.scheduleSize), ("traceCaptured", Lean.toJson traceCaptured),
    ("counters", object [
      ("loads", number c.loads), ("stores", number c.stores),
      ("additions", number c.additions), ("multiplications", number c.multiplications),
      ("multiplyAdds", number c.multiplyAdds), ("registerReads", number c.registerReads),
      ("registerWrites", number c.registerWrites), ("bankAccesses", numbers c.bankAccesses),
      ("laneIssues", numbers c.laneIssues), ("laneCompletions", numbers c.laneCompletions),
      ("laneActiveCycles", numbers c.laneActiveCycles)]),
    ("storage", object [("inputSlots", number r.storage.inputSlots),
      ("outputSlots", number r.storage.outputSlots), ("scratchSlots", number r.storage.scratchSlots),
      ("declaredSlots", number r.storage.declaredSlots), ("declaredBytes", number r.storage.declaredBytes)]),
    ("resources", object [("dspSlices", number resources.dspSlices),
      ("bram36Blocks", number resources.bram36Blocks), ("logicalMemoryBits", number resources.logicalMemoryBits),
      ("slotsPerBank", number resources.slotsPerBank), ("generalPurposePortsPerBank", number resources.generalPurposePortsPerBank),
      ("writableArchitecturalRegisterBits", number resources.writableArchitecturalRegisterBits),
      ("pendingInstructionSlots", number resources.pendingInstructionSlots),
      ("controlArea", Json.null), ("connectionArea", Json.null),
      ("pipelineArea", Json.null), ("totalLogicArea", Json.null),
      ("logicAreaStatus", text "uncalibrated")])]

/-- A general serializer for accepted results. The input identifier is a label;
the exact raw scalar input is also saved. It is never treated as a certificate. -/
def AcceptedScore.toJson (accepted : AcceptedScore raw values) : Json := Id.run do
  let r := accepted.execution.record
  let score := accepted.result
  let coefficients := match score.coefficients with
    | none => Json.null
    | some profile => object [("identifier", text profile.identifier),
        ("values", object (profile.coefficients.map fun (name, value) => (name, number value)))]
  return object [
    ("recordVersion", text "accepted-objective-result-v1"),
    ("verificationStatus", text "all-input-certified"),
    ("executionBinding", text "exact artifact and runtime input; executeValues; trace disabled"),
    ("modelVersion", text r.modelVersion),
    ("candidateFormatVersion", text r.candidateFormatVersion),
    ("workloadIdentifier", text r.workloadIdentifier),
    ("candidateIdentifier", text r.candidateIdentifier),
    ("inputIdentifier", text accepted.inputIdentifier),
    ("inputScalars", Lean.toJson values),
    ("configuration", configurationJson r.resources),
    ("execution", executionJson r false),
    ("objective", object [("identifier", text score.objectiveIdentifier),
      ("direction", text "minimize"), ("unit", text score.unit),
      ("coefficients", coefficients), ("score", number score.value),
      ("breakdown", Lean.toJson (score.breakdown.map fun term => object [
        ("label", text term.label), ("quantity", number term.quantity),
        ("coefficient", number term.coefficient), ("cost", number term.cost)]))])]

end OptimalComputation.Evaluation
