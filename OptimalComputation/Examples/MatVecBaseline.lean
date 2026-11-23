import OptimalComputation.Evaluation.ObjectiveRegistry

/-! Reproducible fixtures and objective-free reports for the frozen baseline.
Expected values are used only after machine execution, never to initialize or
execute a candidate. Conformance configurations are a fixed enumeration. -/
namespace OptimalComputation.Examples.MatVecNaive
open Hardware Workloads Candidates Evaluation

def zeros : MatVec.Input := ⟨fun _ _ => 0, fun _ => 0⟩
def identity : MatVec.Input := ⟨fun i j => if i = j then 1 else 0, fun i => (i.val : Int) - 8⟩
def mixed : MatVec.Input := ⟨fun i j => ((i.val : Int) - 8) * ((j.val : Int) - 7),
  fun j => (j.val : Int) - 8⟩
def constant (a b : Int) : MatVec.Input := ⟨fun _ _ => a, fun _ => b⟩
def generated (seed : Nat) : MatVec.Input :=
  ⟨fun i j => ((17 * i.val + 31 * j.val + seed) % 101 : Nat) - (50 : Int),
   fun j => ((13 * j.val + 7 * seed) % 61 : Nat) - (30 : Int)⟩

/-- Independent direct summation for the deterministic generated fixture. -/
def directExpected (x : MatVec.Input) : List Int :=
  (List.finRange 16).map fun i =>
    (List.finRange 16).foldl (fun sum k => sum + x.matrix i k * x.vector k) 0

def fixtures : List (String × MatVec.Input × List Int) := [
  ("zeros", zeros, List.replicate 16 0),
  ("identity", identity, (List.range 16).map fun (i : Nat) => (i : Int) - 8),
  ("mixed-signs", mixed, (List.range 16).map fun (i : Nat) => 336 * ((i : Int) - 8)),
  ("negative-endpoints", constant (-32768) (-32768), List.replicate 16 17179869184),
  ("positive-endpoints", constant 32767 32767, List.replicate 16 17178820624),
  ("opposite-endpoints", constant (-32768) 32767, List.replicate 16 (-17179344896)),
  ("generated-23", generated 23, directExpected (generated 23))
]

/-- Two terms using the same serial reset/load/load/MAC/store pattern. The
inspectable trace is a simulation fixture, independent of the full certificate. -/
def smallRaw : RawCandidate := {
  identifier := "serial-dot-two-term-v1"
  workloadIdentifier := "serial-dot-two-term-fixture-v1"
  configuration := defaultConfig.val
  layout := ⟨[0, 1, 2, 3], [4], []⟩
  schedule := [⟨0, 0, .add 3 0 0⟩,
    ⟨4, 0, .load 1 0⟩, ⟨6, 0, .load 2 1⟩, ⟨8, 0, .multiplyAdd 3 1 2 3⟩,
    ⟨12, 0, .load 1 2⟩, ⟨14, 0, .load 2 3⟩, ⟨16, 0, .multiplyAdd 3 1 2 3⟩,
    ⟨20, 0, .store 3 4⟩]
}

def smallShape : Shape := ⟨smallRaw.workloadIdentifier, 4, 1⟩

def eventText : Event → String
  | .issued t l i due => s!"{t}: lane {l} issue {reprStr i}, due {due}"
  | .active t l => s!"{t}: lane {l} active"
  | .committed t l (.register r v) => s!"{t}: lane {l} write r{r.val.val} = {v.val}"
  | .committed t l (.memory a v) => s!"{t}: lane {l} store [{a.val}] = {(decodeSlot v).val}"

/-- A record exporter, not an objective or score. The event totals come from
execution; the independent expected formulas live in tests and documentation. -/
def summaryJson (config : Config) (status : String) (record : ExecutionRecord) : String :=
  "{\n" ++
  s!"  \"recordVersion\": \"matvec-baseline-record-v1\",\n" ++
  s!"  \"modelVersion\": \"{record.modelVersion}\",\n" ++
  s!"  \"candidateFormatVersion\": \"{record.candidateFormatVersion}\",\n" ++
  s!"  \"workloadIdentifier\": \"{record.workloadIdentifier}\",\n" ++
  s!"  \"candidateIdentifier\": \"{record.candidateIdentifier}\",\n" ++
  s!"  \"verificationStatus\": \"{status}\",\n" ++
  s!"  \"fixture\": \"generated-23\",\n" ++
  "  \"configuration\": {\"lanes\": " ++ toString config.lanes ++ ", \"banks\": " ++ toString config.banks ++ "},\n" ++
  "  \"layout\": {\"order\": \"row-major\", \"matrixSlots\": [0, 255], \"vectorSlots\": [256, 271], \"outputSlots\": [272, 287], \"scratchSlots\": []},\n" ++
  s!"  \"cycles\": {record.cycles}, \"scheduleSize\": {record.scheduleSize}, \"declaredBytes\": {record.storage.declaredBytes},\n" ++
  s!"  \"outputs\": {reprStr record.outputs},\n" ++
  s!"  \"loads\": {record.counters.loads}, \"stores\": {record.counters.stores}, \"additions\": {record.counters.additions}, \"multiplications\": {record.counters.multiplications}, \"multiplyAdds\": {record.counters.multiplyAdds},\n" ++
  s!"  \"registerReads\": {record.counters.registerReads}, \"registerWrites\": {record.counters.registerWrites},\n" ++
  s!"  \"bankAccesses\": {reprStr record.counters.bankAccesses},\n" ++
  s!"  \"laneIssues\": {reprStr record.counters.laneIssues},\n" ++
  s!"  \"laneCompletions\": {reprStr record.counters.laneCompletions},\n" ++
  s!"  \"laneActiveCycles\": {reprStr record.counters.laneActiveCycles}\n" ++ "}"

def reproduce : IO Unit := do
  let some raw := selectArtifact objectiveCatalog "matvec-naive-v1"
    | throw <| IO.userError "Missing baseline"
  let inputs := (MatVec.scalarInput (generated 23)).toList
  let .accepted accepted := evaluateObjective objectiveCatalog raw inputs 2144 "generated-23" latency
    | throw <| IO.userError "Certified baseline did not finish"
  IO.println (summaryJson defaultConfig.val "all-input-certified" accepted.execution.record)

def reproduceConfigurations : IO Unit := do
  let inputs := (MatVec.scalarInput (generated 23)).toList
  let mut reports := []
  for config in allConfigs do
    let .ok config := validateConfig config | throw <| IO.userError "Invalid conformance config"
    let .success record := execute (candidateFor config) inputs 2144 false
      | throw <| IO.userError "Conformance baseline did not finish"
    reports := reports ++ [summaryJson config.val "conformance-simulation" record]
  IO.println ("[\n" ++ String.intercalate ",\n" reports ++ "\n]")

def reproduceTrace : IO Unit := do
  let .simulated record := simulate smallShape smallRaw [-7, 6, 5, -3] 22 true
    | throw <| IO.userError "Small trace did not finish"
  IO.println "serial-dot-two-term-v1; simulation; inputs [-7, 6, 5, -3]; output [-57]"
  for boundary in record.trace do
    if boundary.events.isEmpty then IO.println s!"{boundary.cycle}: idle"
    else for event in boundary.events do IO.println (eventText event)
  IO.println s!"cycles={record.cycles}; instructions={record.scheduleSize}; active={reprStr record.counters.laneActiveCycles}"

end OptimalComputation.Examples.MatVecNaive
