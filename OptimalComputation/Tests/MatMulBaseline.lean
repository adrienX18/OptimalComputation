import OptimalComputation.Examples.MatMulResults

namespace OptimalComputation.Tests
open Hardware Workloads Candidates Evaluation
open Examples.MatMulNaive

private def checkMatMul (label : String) (ok : Bool) : IO Unit := do
  unless ok do throw <| IO.userError s!"Matrix-matrix baseline check failed: {label}"

/-- Conventional i,j,k loop formula, independent of the flattened generator. -/
private def expectedSchedule : List RawScheduledInstruction :=
  (List.range 16).flatMap fun i => (List.range 16).flatMap fun j =>
    let base := 134 * (16 * i + j)
    [⟨base, 0, .add 3 0 0⟩] ++
    (List.range 16).flatMap (fun k =>
      [⟨base + 4 + 8 * k, 0, .load 1 (16 * i + k)⟩,
       ⟨base + 6 + 8 * k, 0, .load 2 (256 + 16 * k + j)⟩,
       ⟨base + 8 + 8 * k, 0, .multiplyAdd 3 1 2 3⟩]) ++
    [⟨base + 132, 0, .store 3 (512 + 16 * i + j)⟩]

private def expectedCounters (c : Config) : Counters := {
  loads := 256 * 16 * 2
  stores := 256
  additions := 256
  multiplications := 0
  multiplyAdds := 256 * 16
  registerReads := 256 * (2 + 16 * 3 + 1)
  registerWrites := 256 * (1 + 16 * 3)
  bankAccesses := List.replicate c.banks (8448 / c.banks)
  laneIssues := 12800 :: List.replicate (c.lanes - 1) 0
  laneCompletions := 12800 :: List.replicate (c.lanes - 1) 0
  laneActiveCycles := 256 * (3 + 16 * (1 + 1 + 3) + 1) :: List.replicate (c.lanes - 1) 0
}

private def checkRecord (c : ValidConfig) (label : String) (expected : List Int)
    (record : ExecutionRecord) : IO Unit := do
  checkMatMul s!"{label}: exact independent outputs" (record.outputs == expected)
  checkMatMul s!"{label}: independent cycles and schedule length" <|
    record.cycles == 256 * (4 + 16 * 8 + 2) - 1 && record.scheduleSize == 256 * (1 + 16 * 3 + 1)
  checkMatMul s!"{label}: every event counter" (record.counters == expectedCounters c.val)
  checkMatMul s!"{label}: resources and full-slot storage" <|
    record.resources == resourceReport c && record.storage == ⟨512, 256, 0, 768, 6144⟩
  checkMatMul s!"{label}: identity and trace suppression" <|
    record.candidateIdentifier == "matmul-naive-v1" && record.workloadIdentifier == MatMul.specification.identifier &&
    record.modelVersion == Versions.model && record.candidateFormatVersion == Versions.candidate && record.trace.isEmpty

private def rejectsScore (raw : RawCandidate) (values : List Int) : IO Unit := do
  match evaluateObjective objectiveCatalog raw values 34304 "binding-mutation" energy with
  | .failure (.unverifiedCandidate identifier) => checkMatMul "rejected identifier" (identifier == raw.identifier)
  | _ => throw <| IO.userError "Changed artifact received an accepted score"

def matmulBaseline : IO Unit := do
  let some raw := selectCandidate "matmul-naive-v1" | throw <| IO.userError "Missing matmul registration"
  checkMatMul "selection binds complete artifact in both registries" <|
    raw == candidate.toRaw && selectArtifact objectiveCatalog "matmul-naive-v1" == some raw
  checkMatMul "unknown identifier is not selectable" ((selectCandidate "matmul-naive-v0").isNone)
  checkMatMul "independent entire i,j,k schedule" (raw.schedule == expectedSchedule)
  checkMatMul "row-major complete layout" <|
    raw.layout == ⟨List.range 512, (List.range 256).map (512 + ·), []⟩
  for (label, input, expected) in fixtures do
    checkMatMul s!"{label}: allowed input" (decide (MatMul.AllowedInput input))
    checkMatMul s!"{label}: independent mathematical reference" <|
      (matrixScalars (MatMul.reference input)).toList == expected
    let .verified record := evaluateRegistered raw (MatMul.scalarInput input).toList 34304
      | throw <| IO.userError s!"{label}: registered evaluation failed"
    checkRecord defaultConfig label expected record
  let input := generated 23
  let scalars := (MatMul.scalarInput input).toList
  let expected := directExpected input
  let .accepted accepted := evaluateObjective objectiveCatalog raw scalars 34304 "generated-23" latency
    | throw <| IO.userError "Certified matmul scoring failed"
  let record := accepted.execution.record
  let scored := accepted.rescore energy
  checkRecord defaultConfig "proof-carrying execution" expected record
  checkMatMul "exact certified record agrees with diagnostic registry" <|
    evaluateRegistered raw scalars 34304 == .verified record
  checkMatMul "latency and energy use same execution" <|
    accepted.result.value == 34303 && scored.result.value == 954087 && scored.execution.record == record
  checkMatMul "exact energy terms and separate units" <|
    scored.result.breakdown.map (·.cost) ==
      [34303, 274424, 548848, 32768, 1024, 256, 0, 36864, 13056, 12544] &&
    accepted.result.unit == "cycles" && scored.result.unit == "abstract energy units" &&
    scored.result.coefficients == some energyCoefficients
  for config in allConfigs do
    let .ok c := validateConfig config | throw <| IO.userError "Invalid intended configuration"
    let p := candidateFor c
    checkMatMul "all-config identical naive schedule" (p.toRaw.schedule == expectedSchedule)
    match validateCandidate MatMul.shape p.toRaw with
    | .ok checked => checkMatMul "all-config structural binding" (checked.toRaw == p.toRaw)
    | .error _ => throw <| IO.userError "Matmul structural failure"
    let .success actual := execute p scalars 34304 false
      | throw <| IO.userError "Matmul configuration simulation failed"
    checkRecord c "configuration simulation" expected actual
    if config == defaultConfig.val then
      checkMatMul "accepted record is the actual common execution" (actual == record)
  let .success traced := execute candidate scalars 34304 true
    | throw <| IO.userError "Matmul observational trace failed"
  checkMatMul "trace is observational and includes every boundary" <|
    {traced with trace := []} == record && traced.trace.map (·.cycle) == List.range 34304
  let events := traced.trace.flatMap (·.events)
  checkMatMul "every actual final store, value, lane and completion cycle" <|
    events.filterMap (fun | .committed t lane (.memory a v) => some (t, lane, a.val, (decodeSlot v).val) | _ => none) ==
      expected.zipIdx.map (fun (v, q) => (134 * q + 133, 0, 512 + q, v))
  checkMatMul "full trace reconciles event counters" (Counters.ofEvents defaultConfig events == record.counters)
  checkMatMul "larger budget preserves record" <|
    evaluateRegistered raw scalars 35000 == .verified record
  checkMatMul "last store must commit before success" <|
    evaluateRegistered raw scalars 34303 == .resourceExhausted ⟨34303, 12800, 0, 1⟩
  match evaluateObjective objectiveCatalog raw scalars 34303 "exhaustion" energy with
  | .resourceExhausted details => checkMatMul "exhaustion cannot score" (details == ⟨34303, 12800, 0, 1⟩)
  | _ => throw <| IO.userError "Exhausted matmul received a score"
  checkMatMul "left input domain rejection" <|
    evaluateRegistered raw (32768 :: scalars.drop 1) 34304 ==
      .failure (.invalidInput (.outsideDomain MatMul.specification.identifier))
  checkMatMul "last right input domain rejection" <|
    evaluateRegistered raw (scalars.take 511 ++ [-32769]) 34304 ==
      .failure (.invalidInput (.outsideDomain MatMul.specification.identifier))
  checkMatMul "input count rejection" <|
    evaluateRegistered raw [] 34304 == .failure (.invalidInput (.transport (.wrongScalarCount 512 0)))
  for changed in [{raw with identifier := "renamed"},
      {raw with configuration := ⟨1, 1⟩},
      {raw with schedule := raw.schedule.take 12799},
      {raw with layout := {raw.layout with outputs := raw.layout.outputs.reverse}}] do
    checkMatMul "diagnostic registry rejects binding mutations" <|
      evaluateRegistered changed scalars 34304 == .failure (.unverifiedCandidate changed.identifier)
    rejectsScore changed scalars
  rejectsScore {raw with modelVersion := "changed-model"} scalars
  rejectsScore {raw with formatVersion := "changed-format"} scalars
  IO.println "PASS: matmul-naive-v1, 8 certified fixtures, 16 configuration simulations, complete i,j,k schedule, actual stores/counters, and 954087-unit energy"

end OptimalComputation.Tests
