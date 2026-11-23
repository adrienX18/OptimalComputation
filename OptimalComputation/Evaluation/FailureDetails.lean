import OptimalComputation.Evaluation.Checked
import Lean.Data.Json.Basic
import Lean.Data.Json.FromToJson.Basic

/-! Machine-readable failure details. Every violated rule becomes an object with
a short `name` and named arguments, so a tool can repair a candidate without
parsing Lean debug output. Presentation only: nothing here decides legality. -/
namespace OptimalComputation.Evaluation
open Lean Hardware Candidates

private def violation (name : String) (arguments : List (String × Json) := []) : Json :=
  Json.mkObj (("name", toJson name) :: arguments)

def arithmeticErrorJson : ArithmeticError → Json
  | .operandOutOfRange operand bits value =>
      let operand := match operand with
        | .left => "left" | .right => "right" | .accumulator => "accumulator"
      violation "operandOutOfRange"
        [("operand", toJson operand), ("bits", toJson bits), ("value", toJson value)]
  | .resultOutOfRange value =>
      violation "resultOutOfRange" [("bits", toJson registerBits), ("value", toJson value)]

def machineRuleJson : MachineRule → Json
  | .issueCollision => violation "issueCollision"
  | .bankCapacity bank accesses =>
      violation "bankCapacity" [("bank", toJson bank), ("accesses", toJson accesses)]
  | .addressConflict address => violation "addressConflict" [("address", toJson address)]
  | .pendingRead register => violation "pendingRead" [("register", toJson register)]
  | .pendingWrite register => violation "pendingWrite" [("register", toJson register)]
  | .writebackCollision due => violation "writebackCollision" [("due", toJson due)]
  | .pendingCapacity outstanding =>
      violation "pendingCapacity" [("outstanding", toJson outstanding)]
  | .uninitializedRegister register =>
      violation "uninitializedRegister" [("register", toJson register)]
  | .uninitializedMemory address => violation "uninitializedMemory" [("address", toJson address)]
  | .arithmetic reason => arithmeticErrorJson reason
  | .overdueCompletion due => violation "overdueCompletion" [("due", toJson due)]

def configErrorJson : ConfigError → Json
  | .unsupportedLanes actual =>
      violation "unsupportedLanes" [("actual", toJson actual), ("allowed", toJson supportedCounts)]
  | .unsupportedBanks actual =>
      violation "unsupportedBanks" [("actual", toJson actual), ("allowed", toJson supportedCounts)]

def layoutErrorJson : LayoutError → Json
  | .wrongInputCount expected actual =>
      violation "wrongInputCount" [("expected", toJson expected), ("actual", toJson actual)]
  | .wrongOutputCount expected actual =>
      violation "wrongOutputCount" [("expected", toJson expected), ("actual", toJson actual)]
  | .addressOutOfBounds region index address =>
      let region := match region with
        | .input => "inputs" | .output => "outputs" | .scratch => "scratch"
      violation "addressOutOfBounds"
        [("region", toJson region), ("index", toJson index), ("address", toJson address)]
  | .aliasedStorage => violation "aliasedStorage"

def instructionErrorJson : InstructionError → Json
  | .registerOutOfBounds register =>
      violation "registerOutOfBounds" [("register", toJson register)]
  | .zeroRegisterDestination => violation "zeroRegisterDestination"
  | .addressOutOfBounds address => violation "addressOutOfBounds" [("address", toJson address)]

def scheduleRuleJson : ScheduleRule → Json
  | .laneOutOfBounds lane laneCount =>
      violation "laneOutOfBounds" [("lane", toJson lane), ("laneCount", toJson laneCount)]
  | .invalidInstruction reason => instructionErrorJson reason
  | .undeclaredRead address => violation "undeclaredRead" [("address", toJson address)]
  | .undeclaredWrite address => violation "undeclaredWrite" [("address", toJson address)]
  | .writeToInput address => violation "writeToInput" [("address", toJson address)]

def candidateErrorJson : CandidateError → Json
  | .emptyIdentifier => violation "emptyIdentifier"
  | .wrongModelVersion expected actual =>
      violation "wrongModelVersion" [("expected", toJson expected), ("actual", toJson actual)]
  | .wrongFormatVersion expected actual =>
      violation "wrongFormatVersion" [("expected", toJson expected), ("actual", toJson actual)]
  | .wrongWorkloadIdentifier expected actual =>
      violation "wrongWorkloadIdentifier" [("expected", toJson expected), ("actual", toJson actual)]
  | .configuration reason => configErrorJson reason
  | .layout reason => layoutErrorJson reason
  | .schedule reason => scheduleRuleJson reason.rule

/-- The `details` object of a reported failure: where it happened and, for
structural and machine failures, the violated rule as a `violation` object.
Machine failures also keep the rule's Lean text under `rule`. -/
def failureDetails : Failure → Json
  | .invalidInput (.transport (.wrongScalarCount expected actual)) =>
      Json.mkObj [("expectedScalars", toJson expected), ("actualScalars", toJson actual)]
  | .invalidInput (.transport (.scalarOutOfRange index value)) =>
      Json.mkObj [("index", toJson index), ("value", toJson value)]
  | .invalidInput (.outsideDomain workload) => Json.mkObj [("workloadIdentifier", toJson workload)]
  | .invalidInput .noncanonicalScalars => Json.null
  | .inadmissibleConfiguration reason => Json.mkObj [("violation", configErrorJson reason)]
  | .malformedLayout reason => Json.mkObj [("violation", layoutErrorJson reason)]
  | .malformedCandidate reason => Json.mkObj [("violation", candidateErrorJson reason)]
  | .structuralBindingMismatch => Json.null
  | .malformedInstruction e => Json.mkObj [("index", toJson e.index), ("cycle", toJson e.cycle),
      ("lane", toJson e.lane), ("violation", scheduleRuleJson e.rule)]
  | .illegalSchedule e | .arithmeticFailure e => Json.mkObj [("cycle", toJson e.cycle),
      ("lane", toJson e.lane), ("rule", toJson (reprStr e.rule)), ("violation", machineRuleJson e.rule)]
  | .incompleteOutput boundary addresses =>
      Json.mkObj [("boundary", toJson boundary), ("addresses", toJson addresses)]
  | .unverifiedCandidate _ => Json.null

end OptimalComputation.Evaluation
