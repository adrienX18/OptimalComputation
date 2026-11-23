import OptimalComputation.Examples.TinyMultiply
import OptimalComputation.Workloads.MatVec
import OptimalComputation.Workloads.MatMul

namespace OptimalComputation.Tests

open Hardware Workloads Candidates

private def check (label : String) (condition : Bool) : IO Unit := do
  unless condition do
    throw <| IO.userError s!"Candidate check failed: {label}"

private def expectAccepted (shape : Shape) (raw : RawCandidate) : IO Unit := do
  match validateCandidate shape raw with
  | .ok candidate =>
      check "accepted candidate preserves every raw field" (candidate.toRaw == raw)
  | .error error => throw <| IO.userError s!"Unexpected structural rejection: {repr error}"

private def expectRejected (shape : Shape) (raw : RawCandidate) (expected : CandidateError) : IO Unit := do
  match validateCandidate shape raw with
  | .ok _ => throw <| IO.userError s!"Unexpected structural acceptance: {repr raw}"
  | .error actual => check s!"expected {repr expected}, got {repr actual}" (actual == expected)

private def tiny := Examples.TinyMultiply.raw
private def tinyShape := Examples.TinyMultiply.shape

private def rejectLayout (layout : RawLayout) (error : LayoutError) : IO Unit :=
  expectRejected tinyShape { tiny with layout := layout } (.layout error)

private def rejectInstruction (instruction : RawInstruction) (error : ScheduleRule) : IO Unit :=
  -- Keep one valid prefix so the error's zero-based position is also checked.
  expectRejected tinyShape
    { tiny with schedule := [⟨0, 0, .load 1 0⟩, ⟨7, 0, instruction⟩] }
    (.schedule ⟨1, 7, 0, error⟩)

private def checkLayouts : IO Unit := do
  rejectLayout ⟨[0], [2], []⟩ (.wrongInputCount 2 1)
  rejectLayout ⟨[0, 1, 3], [2], []⟩ (.wrongInputCount 2 3)
  rejectLayout ⟨[0, 1], [], []⟩ (.wrongOutputCount 1 0)
  rejectLayout ⟨[0, 1], [2, 3], []⟩ (.wrongOutputCount 1 2)
  rejectLayout ⟨[0, 4096], [2], []⟩ (.addressOutOfBounds .input 1 4096)
  rejectLayout ⟨[0, 1], [1000000], []⟩ (.addressOutOfBounds .output 0 1000000)
  rejectLayout ⟨[0, 1], [2], [3, 4096]⟩ (.addressOutOfBounds .scratch 1 4096)
  rejectLayout ⟨[0, 0], [2], []⟩ .aliasedStorage
  rejectLayout ⟨[0, 1], [2], [3, 3]⟩ .aliasedStorage
  rejectLayout ⟨[0, 1], [0], []⟩ .aliasedStorage
  rejectLayout ⟨[0, 1], [2], [1]⟩ .aliasedStorage
  rejectLayout ⟨[0, 1], [2], [2]⟩ .aliasedStorage
  let twoOutputs := { tinyShape with outputCount := 2 }
  expectRejected twoOutputs { tiny with layout := ⟨[0, 1], [2, 2], []⟩ }
    (.layout .aliasedStorage)
  expectAccepted tinyShape { tiny with
    layout := ⟨[4095, 1], [2], [0, 3]⟩
    schedule := [⟨0, 0, .load 15 4095⟩, ⟨1, 0, .store 0 0⟩] }
  -- A zero-sized general workload is representable, with no invented values.
  let empty : Shape := ⟨"empty-fixture-v1", 0, 0⟩
  expectAccepted empty { tiny with
    workloadIdentifier := empty.identifier
    layout := ⟨[], [], []⟩
    schedule := [] }

private def checkInstructions : IO Unit := do
  for instruction in [(Instruction.load 0 0 : RawInstruction), .add 0 1 2,
      .multiply 0 1 2, .multiplyAdd 0 1 2 3] do
    rejectInstruction instruction (.invalidInstruction .zeroRegisterDestination)
  for instruction in [(Instruction.load 16 0 : RawInstruction), .add 16 1 2,
      .multiply 16 1 2, .multiplyAdd 16 1 2 3, .store 16 2,
      .add 1 16 2, .add 1 2 16, .multiply 1 16 2, .multiply 1 2 16,
      .multiplyAdd 1 16 2 3, .multiplyAdd 1 2 16 3, .multiplyAdd 1 2 3 16] do
    rejectInstruction instruction (.invalidInstruction (.registerOutOfBounds 16))
  rejectInstruction (.load 1 4096) (.invalidInstruction (.addressOutOfBounds 4096))
  rejectInstruction (.store 1 4096) (.invalidInstruction (.addressOutOfBounds 4096))
  rejectInstruction (.load 1 3) (.undeclaredRead 3)
  rejectInstruction (.store 1 3) (.undeclaredWrite 3)
  rejectInstruction (.store 0 0) (.writeToInput 0)
  rejectInstruction (.store 15 1) (.writeToInput 1)
  -- Probe every primitive, all legal boundary indices, source r0, and old-value
  -- destination/source aliasing. These probes assert syntax, not initialization.
  for instruction in [(Instruction.load 15 2 : RawInstruction), .store 0 2, .add 1 1 0,
      .multiply 15 0 15, .multiplyAdd 15 1 2 15] do
    expectAccepted tinyShape { tiny with schedule := [⟨0, 0, instruction⟩] }
  expectAccepted tinyShape { tiny with
    layout := ⟨[0, 1], [2], [3]⟩
    schedule := [⟨0, 0, .store 0 3⟩, ⟨1, 0, .load 1 3⟩] }
  expectRejected tinyShape { tiny with schedule := [⟨9, 1, .load 1 0⟩] }
    (.schedule ⟨0, 9, 1, .laneOutOfBounds 1 1⟩)
  expectAccepted tinyShape { tiny with
    configuration := ⟨8, 8⟩
    schedule := [⟨0, 7, .load 1 0⟩] }
  expectRejected tinyShape { tiny with
    configuration := ⟨8, 8⟩
    schedule := [⟨9, 8, .load 1 0⟩] }
    (.schedule ⟨0, 9, 8, .laneOutOfBounds 8 8⟩)
  -- Structural validation neither inserts waits nor orders/executes the schedule.
  expectAccepted tinyShape { tiny with schedule := tiny.schedule.reverse }
  expectAccepted tinyShape { tiny with schedule := [⟨0, 0, .load 1 0⟩, ⟨0, 0, .load 2 1⟩] }

private def checkIdentityAndShapes : IO Unit := do
  expectRejected tinyShape { tiny with identifier := "" } .emptyIdentifier
  expectRejected tinyShape { tiny with modelVersion := "arty-model-v2" }
    (.wrongModelVersion "arty-model-v1" "arty-model-v2")
  expectRejected tinyShape { tiny with formatVersion := "candidate-v2" }
    (.wrongFormatVersion "candidate-v1" "candidate-v2")
  expectRejected tinyShape { tiny with workloadIdentifier := "unknown-v1" }
    (.wrongWorkloadIdentifier "scalar-multiply-signed16-v1" "unknown-v1")
  expectRejected tinyShape { tiny with configuration := ⟨3, 1⟩ }
    (.configuration (.unsupportedLanes 3))
  expectRejected tinyShape { tiny with configuration := ⟨1, 3⟩ }
    (.configuration (.unsupportedBanks 3))
  for (shape, inputs, outputs) in [(MatVec.shape, 272, 16), (MatMul.shape, 512, 256)] do
    check "workload shape agrees with independent scalar counts"
      (shape.inputCount == inputs && shape.outputCount == outputs)
    let raw : RawCandidate := { tiny with
      workloadIdentifier := shape.identifier
      layout := ⟨List.range inputs, (List.range outputs).map (inputs + ·), []⟩
      schedule := [] }
    expectAccepted shape raw
    expectRejected shape { raw with layout := tiny.layout }
      (.layout (.wrongInputCount inputs 2))
  expectRejected MatVec.shape { tiny with workloadIdentifier := MatMul.shape.identifier }
    (.wrongWorkloadIdentifier MatVec.shape.identifier MatMul.shape.identifier)

def candidates : IO Unit := do
  expectAccepted tinyShape tiny
  check "fixture has exactly two explicit loads, multiply, store and explicit waiting"
    (tiny.schedule == [⟨0, 0, .load 1 0⟩, ⟨1, 0, .load 2 1⟩,
      ⟨2, 0, .multiply 3 1 2⟩, ⟨5, 0, .store 3 2⟩])
  check "bounded fixture and raw fixture agree" (Examples.TinyMultiply.candidate.toRaw == tiny)
  checkLayouts
  checkInstructions
  checkIdentityAndShapes
  IO.println "PASS: candidate structure (tiny fixture, all five primitives, bounds, aliases, read-only inputs, versions, workload shapes; no execution claims)"

end OptimalComputation.Tests
