import OptimalComputation.Examples.MatVecBaseline
import OptimalComputation.Tests.Support

namespace OptimalComputation.Tests
open Hardware Workloads Candidates Evaluation
open Examples.MatVecNaive

private def checkBaseline (label : String) (ok : Bool) : IO Unit := do
  unless ok do throw <| IO.userError s!"Matrix-vector baseline check failed: {label}"

/-- Independent schedule formula: no use of the candidate's serial generator. -/
private def expectedSchedule : List RawScheduledInstruction :=
  (List.range 16).flatMap fun row =>
    let base := 134 * row
    [⟨base, 0, .add 3 0 0⟩] ++
    (List.range 16).flatMap (fun col =>
      [⟨base + 4 + 8 * col, 0, .load 1 (16 * row + col)⟩,
       ⟨base + 6 + 8 * col, 0, .load 2 (256 + col)⟩,
       ⟨base + 8 + 8 * col, 0, .multiplyAdd 3 1 2 3⟩]) ++
    [⟨base + 132, 0, .store 3 (272 + row)⟩]

private def expectedCounters (c : Config) : Counters := {
  loads := 16 * 16 * 2
  stores := 16
  additions := 16
  multiplications := 0
  multiplyAdds := 16 * 16
  registerReads := 16 * (2 + 16 * 3 + 1)
  registerWrites := 16 * (1 + 16 * 3)
  bankAccesses := List.replicate c.banks (528 / c.banks)
  laneIssues := 800 :: List.replicate (c.lanes - 1) 0
  laneCompletions := 800 :: List.replicate (c.lanes - 1) 0
  laneActiveCycles := 16 * (3 + 16 * (1 + 1 + 3) + 1) :: List.replicate (c.lanes - 1) 0
}

private def checkRecord (c : ValidConfig) (label : String) (expected : List Int)
    (record : ExecutionRecord) : IO Unit := do
  checkBaseline s!"{label}: exact independent outputs" (record.outputs == expected)
  checkBaseline s!"{label}: independent elapsed cycles and schedule length" <|
    record.cycles == 16 * (4 + 16 * 8 + 2) - 1 && record.scheduleSize == 16 * (1 + 16 * 3 + 1)
  checkBaseline s!"{label}: every event counter" (record.counters == expectedCounters c.val)
  checkBaseline s!"{label}: resources and full-slot storage" <|
    record.resources == resourceReport c && record.storage == ⟨272, 16, 0, 288, 2304⟩
  checkBaseline s!"{label}: identity and trace suppression" <|
    record.candidateIdentifier == "matvec-naive-v1" && record.workloadIdentifier == MatVec.specification.identifier &&
    record.modelVersion == Versions.model && record.candidateFormatVersion == Versions.candidate && record.trace.isEmpty

private def checkSmallTrace : IO Unit := do
  let .simulated record := simulate smallShape smallRaw [-7, 6, 5, -3] 22 true
    | throw <| IO.userError "Small serial dot trace failed"
  let events := record.trace.flatMap (·.events)
  checkBaseline "small trace result and all boundaries" <|
    record.outputs == [-57] && record.cycles == 21 && record.scheduleSize == 8 &&
    record.trace.map (·.cycle) == List.range 22
  checkBaseline "small trace exact issue cycles" <|
    events.filterMap (fun | .issued t _ _ _ => some t | _ => none) == [0, 4, 6, 8, 12, 14, 16, 20]
  checkBaseline "small trace exact completion cycles" <|
    events.filterMap (fun | .committed t _ _ => some t | _ => none) == [3, 5, 7, 11, 13, 15, 19, 21]
  checkBaseline "small trace exact arithmetic and transfer values" <|
    events.filterMap (fun | .committed _ _ (.register r v) => some (r.val.val, v.val) | _ => none) ==
      [(3, 0), (1, -7), (2, 6), (3, -42), (1, 5), (2, -3), (3, -57)] &&
    events.filterMap (fun | .committed _ _ (.memory a v) => some (a.val, (decodeSlot v).val) | _ => none) == [(4, -57)]
  checkBaseline "small trace exact active intervals and event accounting" <|
    events.filterMap (fun | .active t _ => some t | _ => none) ==
      [0, 1, 2, 4, 6, 8, 9, 10, 12, 14, 16, 17, 18, 20] &&
    events.length == 30 && record.counters == Counters.ofEvents defaultConfig events &&
    record.counters.loads == 4 && record.counters.stores == 1 && record.counters.additions == 1 &&
    record.counters.multiplyAdds == 2 && record.counters.registerReads == 9 && record.counters.registerWrites == 7

def matvecBaseline : IO Unit := do
  let some raw := selectArtifact objectiveCatalog "matvec-naive-v1"
    | throw <| IO.userError "Missing baseline registration"
  checkBaseline "selection binds exact primary artifact" (raw == candidate.toRaw)
  checkBaseline "unknown identifier is not selectable" <|
    (selectArtifact objectiveCatalog "matvec-naive-v0").isNone
  checkBaseline "independent complete schedule" (raw.schedule == expectedSchedule)
  checkBaseline "row-major complete layout" <|
    raw.layout == ⟨List.range 272, (List.range 16).map (272 + ·), []⟩
  for (label, input, expected) in fixtures do
    checkBaseline s!"{label}: allowed input" (decide (MatVec.AllowedInput input))
    checkBaseline s!"{label}: independent mathematical reference" <|
      (vectorScalars (MatVec.reference input)).toList == expected
    let scalars := (MatVec.scalarInput input).toList
    let .accepted accepted := certify raw scalars 2144
      | throw <| IO.userError s!"{label}: certified evaluation failed"
    checkRecord defaultConfig label expected accepted
    for config in allConfigs do
      let .ok c := validateConfig config | throw <| IO.userError "Invalid intended configuration"
      let p := candidateFor c
      checkBaseline "all-config identical serial schedule" (p.toRaw.schedule == expectedSchedule)
      match validateCandidate MatVec.shape p.toRaw with
      | .ok checked => checkBaseline "all-config structural binding" (checked.toRaw == p.toRaw)
      | .error _ => throw <| IO.userError "Baseline structural failure"
      let .success record := execute p scalars 2144 false
        | throw <| IO.userError s!"{label}: {repr config} conformance failed"
      checkRecord c label expected record
      if config == defaultConfig.val then
        checkBaseline "accepted record is actual common execution" (record == accepted)
  let scalars := (MatVec.scalarInput (generated 23)).toList
  checkBaseline "larger certified budget preserves record" <|
    certify raw scalars 5000 == certify raw scalars 2144
  checkBaseline "final store must drain before acceptance" <|
    certify raw scalars 2143 == .exhausted ⟨2143, 800, 0, 1⟩
  checkBaseline "domain rejection" <|
    certify raw (32768 :: scalars.drop 1) 2144 ==
      .failure (.invalidInput (.outsideDomain MatVec.specification.identifier))
  checkBaseline "input count rejection" <|
    certify raw [] 2144 == .failure (.invalidInput (.transport (.wrongScalarCount 272 0)))
  checkBaseline "renamed exact program is not certified" <|
    certify {raw with identifier := "renamed"} scalars 2144 == .failure (.unverifiedCandidate "renamed")
  checkBaseline "same-name changed schedule is not certified" <|
    certify {raw with schedule := raw.schedule.take 799} scalars 2144 ==
      .failure (.unverifiedCandidate raw.identifier)
  checkBaseline "same-name changed configuration is not certified" <|
    certify {raw with configuration := ⟨1, 1⟩} scalars 2144 ==
      .failure (.unverifiedCandidate raw.identifier)
  checkSmallTrace
  IO.println "PASS: matvec-naive-v1, 7 certified fixtures, 112 all-config conformance runs, independent schedule/counters, and 22-boundary trace"

end OptimalComputation.Tests
