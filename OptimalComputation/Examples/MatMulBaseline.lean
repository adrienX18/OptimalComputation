import OptimalComputation.Evaluation.Registry

/-! Reproducible fixtures and objective-free reports for the frozen baseline.
Expected values are used only after machine execution, never to initialize or
execute a candidate. Conformance configurations are a fixed enumeration. -/
namespace OptimalComputation.Examples.MatMulNaive
open Hardware Workloads Candidates Evaluation

def zeros : MatMul.Input := ⟨fun _ _ => 0, fun _ _ => 0⟩
def sampleMatrix : Matrix16 := fun i j => (16 * i.val + j.val : Nat) - (128 : Int)
def unitMatrix : Matrix16 := fun i j => if i = j then 1 else 0
def leftIdentity : MatMul.Input := ⟨unitMatrix, sampleMatrix⟩
def rightIdentity : MatMul.Input := ⟨sampleMatrix, unitMatrix⟩
def mixed : MatMul.Input := ⟨fun i k => ((i.val : Int) - 8) * ((k.val : Int) - 7),
  fun k j => ((k.val : Int) - 8) * ((j.val : Int) - 6)⟩
def constant (a b : Int) : MatMul.Input := ⟨fun _ _ => a, fun _ _ => b⟩
def generated (seed : Nat) : MatMul.Input :=
  ⟨fun i j => ((17 * i.val + 31 * j.val + seed) % 101 : Nat) - (50 : Int),
   fun i j => ((19 * i.val + 11 * j.val + 7 * seed) % 61 : Nat) - (30 : Int)⟩

/-- Independent direct summation for the deterministic generated fixture. -/
def directExpected (x : MatMul.Input) : List Int :=
  (List.finRange 16).flatMap fun i => (List.finRange 16).map fun j =>
    (List.finRange 16).foldl (fun sum k => sum + x.left i k * x.right k j) 0

def fixtures : List (String × MatMul.Input × List Int) := [
  ("zeros", zeros, List.replicate 256 0),
  ("left-identity", leftIdentity, (matrixScalars sampleMatrix).toList),
  ("right-identity", rightIdentity, (matrixScalars sampleMatrix).toList),
  ("mixed-signs", mixed, (matrixScalars fun i j => 336 * ((i.val : Int) - 8) * ((j.val : Int) - 6)).toList),
  ("negative-endpoints", constant (-32768) (-32768), List.replicate 256 17179869184),
  ("positive-endpoints", constant 32767 32767, List.replicate 256 17178820624),
  ("opposite-endpoints", constant (-32768) 32767, List.replicate 256 (-17179344896)),
  ("generated-23", generated 23, directExpected (generated 23))
]

/-- A record exporter, not an objective or score. The event totals come from
execution; the independent expected formulas live in tests and documentation. -/
def summaryJson (config : Config) (status : String) (record : ExecutionRecord) : String :=
  "{\n" ++
  s!"  \"recordVersion\": \"matmul-baseline-record-v1\",\n" ++
  s!"  \"modelVersion\": \"{record.modelVersion}\",\n" ++
  s!"  \"candidateFormatVersion\": \"{record.candidateFormatVersion}\",\n" ++
  s!"  \"workloadIdentifier\": \"{record.workloadIdentifier}\",\n" ++
  s!"  \"candidateIdentifier\": \"{record.candidateIdentifier}\",\n" ++
  s!"  \"verificationStatus\": \"{status}\",\n" ++
  s!"  \"fixture\": \"generated-23\",\n" ++
  "  \"configuration\": {\"lanes\": " ++ toString config.lanes ++ ", \"banks\": " ++ toString config.banks ++ "},\n" ++
  "  \"layout\": {\"order\": \"row-major\", \"leftMatrixSlots\": [0, 255], \"rightMatrixSlots\": [256, 511], \"outputSlots\": [512, 767], \"scratchSlots\": []},\n" ++
  s!"  \"cycles\": {record.cycles}, \"scheduleSize\": {record.scheduleSize}, \"declaredBytes\": {record.storage.declaredBytes},\n" ++
  s!"  \"outputs\": {reprStr record.outputs},\n" ++
  s!"  \"loads\": {record.counters.loads}, \"stores\": {record.counters.stores}, \"additions\": {record.counters.additions}, \"multiplications\": {record.counters.multiplications}, \"multiplyAdds\": {record.counters.multiplyAdds},\n" ++
  s!"  \"registerReads\": {record.counters.registerReads}, \"registerWrites\": {record.counters.registerWrites},\n" ++
  s!"  \"bankAccesses\": {reprStr record.counters.bankAccesses},\n" ++
  s!"  \"laneIssues\": {reprStr record.counters.laneIssues},\n" ++
  s!"  \"laneCompletions\": {reprStr record.counters.laneCompletions},\n" ++
  s!"  \"laneActiveCycles\": {reprStr record.counters.laneActiveCycles}\n" ++ "}"

def reproduce : IO Unit := do
  let some raw := selectCandidate "matmul-naive-v1" | throw <| IO.userError "Missing baseline"
  let inputs := (MatMul.scalarInput (generated 23)).toList
  let .verified record := evaluateRegistered raw inputs 34304
    | throw <| IO.userError "Certified baseline did not finish"
  IO.println (summaryJson defaultConfig.val "all-input-certified" record)

def reproduceConfigurations : IO Unit := do
  let inputs := (MatMul.scalarInput (generated 23)).toList
  let mut reports := []
  for config in allConfigs do
    let .ok config := validateConfig config | throw <| IO.userError "Invalid conformance config"
    let .success record := execute (candidateFor config) inputs 34304 false
      | throw <| IO.userError "Conformance baseline did not finish"
    reports := reports ++ [summaryJson config.val "conformance-simulation" record]
  IO.println ("[\n" ++ String.intercalate ",\n" reports ++ "\n]")

end OptimalComputation.Examples.MatMulNaive
