import OptimalComputation.Examples.ObjectiveResults
import Lean.Data.Json.Parser

namespace OptimalComputation.Tests
open Hardware Candidates Evaluation Workloads

private def checkObjective (label : String) (ok : Bool) : IO Unit := do
  unless ok do throw <| IO.userError s!"Objective check failed: {label}"

private def fixture (identifier : String) (values expected : List Int)
    (boundaries cycles energyCost : Nat) : IO Unit := do
  let some raw := selectArtifact objectiveCatalog identifier
    | throw <| IO.userError "Missing objective artifact"
  let .accepted accepted := evaluateObjective objectiveCatalog raw values boundaries "runtime-fixture" latency
    | throw <| IO.userError "Certified scoring failed"
  let rescore := accepted.rescore energy
  let record := accepted.execution.record
  checkObjective "actual outputs and elapsed cycles" (record.outputs == expected && record.cycles == cycles)
  checkObjective "latency score and metadata" <|
    accepted.result.value == cycles && accepted.result.objectiveIdentifier == "latency-v1" &&
    accepted.result.unit == "cycles" && accepted.result.direction == .minimize && accepted.result.coefficients.isNone
  checkObjective "energy score and metadata" <|
    rescore.result.value == energyCost && rescore.result.objectiveIdentifier == "energy-proxy-v1" &&
    rescore.result.unit == "abstract energy units" && rescore.result.direction == .minimize &&
    rescore.result.coefficients == some energyCoefficients
  checkObjective "rescoring retains complete record" (rescore.execution.record == record)
  checkObjective "independent energy expression" <|
    energyCost == record.cycles * (1 + record.resources.configuration.lanes + record.resources.bram36Blocks) +
      4 * record.counters.loads + 4 * record.counters.stores + record.counters.additions +
      8 * record.counters.multiplications + 9 * record.counters.multiplyAdds +
      record.counters.registerReads + record.counters.registerWrites
  checkObjective "breakdown sums and every quantity" <|
    (rescore.result.breakdown.map (·.cost)).sum == energyCost &&
    rescore.result.breakdown.map (·.quantity) == [cycles, cycles * record.resources.configuration.lanes,
      cycles * record.resources.bram36Blocks, record.counters.loads, record.counters.stores,
      record.counters.additions, record.counters.multiplications, record.counters.multiplyAdds,
      record.counters.registerReads, record.counters.registerWrites] &&
    rescore.result.breakdown.map (·.coefficient) == [1, 1, 1, 4, 4, 1, 8, 9, 1, 1]
  let .success direct := execute accepted.artifact.verified.candidate values boundaries false
    | throw <| IO.userError "Direct execution failed"
  checkObjective "certified execution equals common simulator" (direct == record)
  let .accepted larger := evaluateObjective objectiveCatalog raw values (boundaries + 10) "runtime-fixture" energy
    | throw <| IO.userError "Larger budget failed"
  checkObjective "larger budget preserves execution and score" <|
    larger.execution.record == record && larger.result == rescore.result
  match evaluateObjective objectiveCatalog raw values (boundaries - 1) "runtime-fixture" energy with
  | .resourceExhausted _ => pure ()
  | _ => throw <| IO.userError "Exhausted run received an accepted score"
  if identifier.startsWith "product-pair" then
    checkObjective "manual pair event counts" <|
      record.scheduleSize == 8 && record.counters.loads == 4 && record.counters.stores == 2 &&
      record.counters.multiplications == 2 && record.counters.additions == 0 &&
      record.counters.multiplyAdds == 0 && record.counters.registerReads == 6 && record.counters.registerWrites == 6

private def rejects (raw : RawCandidate) (values : List Int) (expected : Failure) : IO Unit := do
  match evaluateObjective objectiveCatalog raw values 3000 "rejected-fixture" energy with
  | .failure reason => checkObjective "exact scoring rejection" (reason == expected)
  | _ => throw <| IO.userError "Invalid or unverified artifact received a score"

def objectives : IO Unit := do
  checkObjective "frozen coefficient identifiers and exact positive values" <|
    energyCoefficients.identifier == "energy-coefficients-v1" &&
    energyCoefficients.coefficients == [("base_per_cycle", 1), ("lane_per_cycle", 1), ("bram_per_cycle", 1),
      ("load", 4), ("store", 4), ("addition", 1), ("multiplication", 8),
      ("multiply_add", 9), ("register_read", 1), ("register_write", 1)] &&
    energyCoefficients.coefficients.all (fun e => e.2 > 0)
  for values in [[-7, 6, 5, -3], [0, 0, 0, 0], [-32768, -32768, 32767, 32767],
      [-32768, 32767, 32767, -32768], [1, -1, -1, 1]] do
    let expected := [values[0]! * values[1]!, values[2]! * values[3]!]
    fixture "product-pair-serial-v1" values expected 13 12 172
    fixture "product-pair-parallel-v1" values expected 7 6 202
  fixture "tiny-multiply-v1" [-7, 6] [-42] 7 6 86
  let x := Examples.MatVecNaive.generated 23
  fixture "matvec-naive-v1" (MatVec.scalarInput x).toList (Examples.MatVecNaive.directExpected x) 2144 2143 59607
  let serial := (Examples.ProductPair.candidate false).toRaw
  let parallel := (Examples.ProductPair.candidate true).toRaw
  let values := [-7, 6, 5, -3]
  let .accepted a := evaluateObjective objectiveCatalog serial values 13 "comparison" latency
    | throw <| IO.userError "Serial comparison failed"
  let .accepted b := evaluateObjective objectiveCatalog parallel values 7 "comparison" latency
    | throw <| IO.userError "Parallel comparison failed"
  checkObjective "strict objective preference reversal" <|
    b.result.value < a.result.value && (a.rescore energy).result.value < (b.rescore energy).result.value
  rejects serial [] (.invalidInput (.transport (.wrongScalarCount 4 0)))
  rejects serial [32768, 1, 2, 3] (.invalidInput (.outsideDomain "product-pair-signed16-v1"))
  rejects {serial with identifier := "renamed"} values (.unverifiedCandidate "renamed")
  rejects {serial with configuration := ⟨8, 8⟩} values (.unverifiedCandidate serial.identifier)
  rejects {serial with layout := ⟨[0, 1, 3, 2], [4, 5], []⟩} values (.unverifiedCandidate serial.identifier)
  rejects {serial with schedule := serial.schedule.take 7} values (.unverifiedCandidate serial.identifier)
  rejects {serial with modelVersion := "forged-model"} values (.unverifiedCandidate serial.identifier)
  let altered := {serial with schedule := serial.schedule.reverse}
  let .simulated simulation := simulate Examples.ProductPair.shape altered values 13 true
    | throw <| IO.userError "Unregistered successful simulation failed"
  checkObjective "unregistered simulation happens to be correct" (simulation.outputs == [-42, -15])
  rejects altered values (.unverifiedCandidate serial.identifier)
  let raw := Examples.MatVecNaive.candidate.toRaw
  let .accepted baseline := evaluateObjective objectiveCatalog raw (MatVec.scalarInput x).toList 2144 "generated-23" energy
    | throw <| IO.userError "Baseline energy failed"
  checkObjective "MAC only charged once; zero register operands counted" <|
    baseline.result.breakdown.map (·.cost) == [2143, 17144, 34288, 2048, 64, 16, 0, 2304, 816, 784]
  -- A new objective is merely a record function and uses the existing execution.
  let instructions : Objective := ⟨"instruction-count-test", "instructions", .minimize, none,
    fun r => [⟨"issued instructions", r.counters.laneIssues.sum, 1⟩]⟩
  checkObjective "independent objective extension" <|
    (baseline.rescore instructions).result.value == 800 &&
    (baseline.rescore instructions).execution.record == baseline.execution.record
  checkObjective "escaped input labels serialize as JSON" <|
    (Lean.Json.parse {a with inputIdentifier := "quoted \"label\"\n"}.toJson.compress).isOk
  IO.println "PASS: proof-bound objectives, fixed coefficients/breakdowns, all-input manual pair fixtures, preference reversal, and 59607-unit matrix-vector baseline"

end OptimalComputation.Tests
