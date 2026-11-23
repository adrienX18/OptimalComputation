import OptimalComputation.Evaluation.Registry
import OptimalComputation.Workloads.MatrixAdapters

namespace OptimalComputation.Tests
open Hardware Candidates Workloads Evaluation

private def checkVerification (label : String) (condition : Bool) : IO Unit := do
  unless condition do throw <| IO.userError s!"Verification check failed: {label}"

private def expectVerifiedFailure (raw : RawCandidate) (values : List Int) (reason : Failure) : IO Unit :=
  checkVerification s!"expected {repr reason}" (evaluateRegistered raw values 7 == .failure reason)

private def expectSimulated (raw : RawCandidate) (values output : List Int) : IO Unit := do
  match Evaluation.simulate Examples.TinyMultiply.shape raw values 10 false with
  | .simulated record => checkVerification "simulated output, not verified" (record.outputs == output)
  | other => throw <| IO.userError s!"Expected simulation, got {repr other}"

def verification : IO Unit := do
  let raw := Examples.TinyMultiply.raw
  for a in [-32768, -7, 0, 32767] do
    for b in [-32768, 1, 6, 32767] do
      match evaluateRegistered raw [a, b] 7 with
      | .verified record =>
        checkVerification "certified signed16 product and completion" <|
          record.outputs == [a * b] && record.cycles == 6 && record.trace.isEmpty &&
          record.modelVersion == Versions.model && record.candidateIdentifier == raw.identifier
      | other => throw <| IO.userError s!"Expected verified record, got {repr other}"
  checkVerification "larger budget preserves exact certified record" <|
    evaluateRegistered raw [-7, 6] 100 == evaluateRegistered raw [-7, 6] 7
  checkVerification "smaller budget is inconclusive with actual runner details" <|
    evaluateRegistered raw [-7, 6] 6 == .resourceExhausted ⟨6, 4, 0, 1⟩
  expectVerifiedFailure raw [1] (.invalidInput (.transport (.wrongScalarCount 2 1)))
  expectVerifiedFailure raw [32768, 1] (.invalidInput (.outsideDomain raw.workloadIdentifier))
  expectVerifiedFailure raw [1, -32769] (.invalidInput (.outsideDomain raw.workloadIdentifier))
  expectVerifiedFailure {raw with configuration := ⟨3, 1⟩} [1, 1]
    (.inadmissibleConfiguration (.unsupportedLanes 3))
  expectVerifiedFailure {raw with layout := ⟨[0, 1], [1], []⟩} [1, 1]
    (.malformedLayout .aliasedStorage)
  expectVerifiedFailure {raw with modelVersion := "untrusted-model"} [1, 1]
    (.malformedCandidate (.wrongModelVersion Versions.model "untrusted-model"))
  let duplicate := {raw with schedule := ⟨0, 0, .load 2 1⟩ :: raw.schedule}
  expectVerifiedFailure duplicate [1, 1] (.illegalSchedule ⟨0, some 0, .issueCollision⟩)
  expectVerifiedFailure {raw with identifier := "renamed"} [1, 1] (.unverifiedCandidate "renamed")
  expectVerifiedFailure {raw with workloadIdentifier := "unknown-workload"} [1, 1]
    (.unverifiedCandidate raw.identifier)
  let r0 := {raw with schedule := [⟨0, 0, .load 0 0⟩]}
  match evaluateRegistered r0 [1, 1] 7 with
  | .failure (.malformedInstruction _) => pure ()
  | other => throw <| IO.userError s!"Expected malformed instruction, got {repr other}"
  expectSimulated raw [-7, 6] [-42]
  let oneInputOnly := {raw with schedule := [⟨0, 0, .load 1 0⟩, ⟨1, 0, .store 1 2⟩]}
  expectSimulated oneInputOnly [7, 1] [7]
  expectSimulated oneInputOnly [7, 2] [7]
  expectVerifiedFailure oneInputOnly [7, 1] (.unverifiedCandidate raw.identifier)
  checkVerification "arithmetic failure retains cycle/lane/operand" <|
    Evaluation.simulate Examples.TinyMultiply.shape raw [32768, 1] 7 false ==
      .failure (.arithmeticFailure ⟨2, some 0,
        .arithmetic (.operandOutOfRange .left 16 32768)⟩)
  checkVerification "missing output remains separate from unsafe schedule" <|
    Evaluation.simulate Examples.TinyMultiply.shape {raw with schedule := []} [1, 1] 7 false ==
      .failure (.incompleteOutput 0 [2])
  checkVerification "uninitialized read has structured location" <|
    Evaluation.simulate Examples.TinyMultiply.shape
      {raw with schedule := [⟨0, 0, .store 1 2⟩]} [1, 1] 7 false ==
        .failure (.illegalSchedule ⟨0, some 0, .uninitializedRegister 1⟩)
  let mv : MatVec.Input := ⟨fun i j => Int.ofNat (100 * i.val + j.val), fun i => -Int.ofNat i.val⟩
  let scalars := MatVec.adapter.inputScalars mv
  checkVerification "matrix-vector row-major codec boundaries" <|
    scalars[0] == 0 && scalars[255] == 1515 && scalars[256] == 0 && scalars[271] == -15
  let mm : MatMul.Input := ⟨mv.matrix, fun i j => -Int.ofNat (100 * i.val + j.val)⟩
  let scalars := MatMul.adapter.inputScalars mm
  checkVerification "matrix-matrix distinct input regions" <|
    scalars[255] == 1515 && scalars[256] == 0 && scalars[511] == -1515
  IO.println "PASS: proof-bound registration, domain/budget/failure handling, scalar codecs, and unverified simulations"

end OptimalComputation.Tests
