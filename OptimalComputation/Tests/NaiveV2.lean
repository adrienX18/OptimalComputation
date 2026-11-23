import OptimalComputation.Examples.MatVecBaseline
import OptimalComputation.Examples.MatMulResults

/-! `matvec-naive-v2` and `matmul-naive-v2`: the v1 instruction lists retimed to
issue on each completion boundary. Expected schedules, cycles, counters and
scores below are independent formulas, not the candidates' generators. -/
namespace OptimalComputation.Tests
open Hardware Workloads Candidates Evaluation Examples

private def checkV2 (label : String) (ok : Bool) : IO Unit := do
  unless ok do throw <| IO.userError s!"Naive v2 baseline check failed: {label}"

/-- One tight serial dot product starting at `base`: reset (3 cycles), then
load/load/MAC (1 + 1 + 3) per term, then the output store (1). 84 cycles. -/
private def tightDot (base : Nat) (left right : Nat → Nat) (output : Nat) :
    List RawScheduledInstruction :=
  [⟨base, 0, .add 3 0 0⟩] ++
  (List.range 16).flatMap (fun k =>
    [⟨base + 3 + 5 * k, 0, .load 1 (left k)⟩,
     ⟨base + 4 + 5 * k, 0, .load 2 (right k)⟩,
     ⟨base + 5 + 5 * k, 0, .multiplyAdd 3 1 2 3⟩]) ++
  [⟨base + 83, 0, .store 3 output⟩]

private def matvecSchedule : List RawScheduledInstruction :=
  (List.range 16).flatMap fun row => tightDot (84 * row) (16 * row + ·) (256 + ·) (272 + row)

private def matmulSchedule : List RawScheduledInstruction :=
  (List.range 16).flatMap fun i => (List.range 16).flatMap fun j =>
    tightDot (84 * (16 * i + j)) (16 * i + ·) (256 + 16 * · + j) (512 + 16 * i + j)

/-- Same events as v1; lane zero now has a pending effect at every boundary
before completion, so its active cycles equal the elapsed cycles. -/
private def counters (dots instructions bankTotal cycles : Nat) : Counters := {
  loads := dots * 16 * 2
  stores := dots
  additions := dots
  multiplications := 0
  multiplyAdds := dots * 16
  registerReads := dots * (2 + 16 * 3 + 1)
  registerWrites := dots * (1 + 16 * 3)
  bankAccesses := List.replicate 8 (bankTotal / 8)
  laneIssues := instructions :: List.replicate 7 0
  laneCompletions := instructions :: List.replicate 7 0
  laneActiveCycles := cycles :: List.replicate 7 0
}

/-- `energy-proxy-v1` by hand: 8 lanes and 16 BRAM36 blocks on the default configuration. -/
private def energyOf (c : Counters) (cycles : Nat) : Nat :=
  cycles * (1 + 8 + 16) + 4 * c.loads + 4 * c.stores + c.additions + 8 * c.multiplications +
    9 * c.multiplyAdds + c.registerReads + c.registerWrites

private def checkWorkload (v1 v2 : String) (fixtures : List (String × List Int × List Int))
    (schedule : List RawScheduledInstruction) (expectedCounters : Counters) (cycles : Nat) : IO Unit := do
  let some raw := selectArtifact objectiveCatalog v2 | throw <| IO.userError s!"Missing {v2}"
  let some original := selectArtifact objectiveCatalog v1 | throw <| IO.userError s!"Missing {v1}"
  checkV2 s!"{v2}: independent tight schedule" (raw.schedule == schedule)
  checkV2 s!"{v2}: same instructions, layout, configuration and workload as {v1}" <|
    raw.schedule.map (·.instruction) == original.schedule.map (·.instruction) &&
    raw.layout == original.layout && raw.configuration == original.configuration &&
    raw.workloadIdentifier == original.workloadIdentifier
  let size := schedule.length
  for (label, scalars, expected) in fixtures do
    let .accepted accepted := evaluateObjective objectiveCatalog raw scalars (cycles + 1) label latency
      | throw <| IO.userError s!"{v2} {label}: certified evaluation failed"
    let record := accepted.execution.record
    checkV2 s!"{v2} {label}: exact outputs" (record.outputs == expected)
    checkV2 s!"{v2} {label}: cycles, size and every counter" <|
      record.cycles == cycles && record.scheduleSize == size && record.counters == expectedCounters &&
      record.candidateIdentifier == v2 && record.trace.isEmpty
    checkV2 s!"{v2} {label}: both objectives on one execution" <|
      accepted.result.value == cycles &&
      (accepted.rescore energy).result.value == energyOf expectedCounters cycles
  let some (_, scalars, _) := fixtures.head? | throw <| IO.userError "Missing fixture"
  match evaluateObjective objectiveCatalog raw scalars cycles "short" latency with
  | .resourceExhausted details =>
      checkV2 s!"{v2}: final store must commit before success" (details == ⟨cycles, size, 0, 1⟩)
  | _ => throw <| IO.userError s!"{v2}: one boundary short was not exhausted"
  for changed in [{raw with identifier := "renamed"}, {raw with schedule := original.schedule},
      {raw with schedule := raw.schedule.take (size - 1)}] do
    match evaluateObjective objectiveCatalog changed scalars (cycles + 1) "mutation" latency with
    | .failure (.unverifiedCandidate _) => pure ()
    | _ => throw <| IO.userError s!"{v2}: changed artifact received an accepted score"

def naiveV2 : IO Unit := do
  let matvecFixtures := MatVecNaive.fixtures.map fun (label, input, expected) =>
    (label, (MatVec.scalarInput input).toList, expected)
  checkWorkload "matvec-naive-v1" "matvec-naive-v2" matvecFixtures matvecSchedule
    (counters 16 800 528 1344) 1344
  let matmulFixtures := MatMulNaive.fixtures.map fun (label, input, expected) =>
    (label, (MatMul.scalarInput input).toList, expected)
  checkWorkload "matmul-naive-v1" "matmul-naive-v2" matmulFixtures matmulSchedule
    (counters 256 12800 8448 21504) 21504
  checkV2 "independent energy scores" <|
    energyOf (counters 16 800 528 1344) 1344 == 39632 &&
    energyOf (counters 256 12800 8448 21504) 21504 == 634112
  -- The same generators on every admissible configuration: conformance only.
  let matvecScalars := (MatVec.scalarInput (MatVecNaive.generated 23)).toList
  let matmulScalars := (MatMul.scalarInput (MatMulNaive.generated 23)).toList
  for config in allConfigs do
    let .ok c := validateConfig config | throw <| IO.userError "Invalid intended configuration"
    let mv := MatVecNaive.candidateV2For c
    let mm := MatMulNaive.candidateV2For c
    checkV2 "all-config structural binding" <|
      (validateCandidate MatVec.shape mv.toRaw).toOption.map (·.toRaw) == some mv.toRaw &&
      (validateCandidate MatMul.shape mm.toRaw).toOption.map (·.toRaw) == some mm.toRaw
    let .success r1 := execute mv matvecScalars 1345 false
      | throw <| IO.userError s!"matvec-naive-v2 {repr config} conformance failed"
    let .success r2 := execute mm matmulScalars 21505 false
      | throw <| IO.userError s!"matmul-naive-v2 {repr config} conformance failed"
    checkV2 "all-config outputs and cycles" <|
      r1.outputs == MatVecNaive.directExpected (MatVecNaive.generated 23) && r1.cycles == 1344 &&
      r2.outputs == MatMulNaive.directExpected (MatMulNaive.generated 23) && r2.cycles == 21504
  IO.println "PASS: matvec-naive-v2 and matmul-naive-v2, 15 certified fixtures, 32 configuration simulations, independent tight schedules, 1344/21504 cycles and 39632/634112-unit energy"

end OptimalComputation.Tests
