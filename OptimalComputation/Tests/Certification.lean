import OptimalComputation.Certification.Catalog
import OptimalComputation.Evaluation.ObjectiveRegistry

namespace OptimalComputation.Tests
open Hardware Candidates Certification
set_option maxRecDepth 20000

private theorem tiny_check :
    (Certification.check TinyProblem.problem Examples.TinyMultiply.candidate 7 64).toOption = some 6 := by decide

/-- A new checker-produced artifact, through the same API as the hand proof. -/
def checkedTiny : Evaluation.VerifiedArtifact :=
  Catalog.tiny.artifact Examples.TinyMultiply.candidate 7 64 6 tiny_check

private def require (label : String) (condition : Bool) : IO Unit := do
  unless condition do throw (IO.userError s!"Certification regression: {label}")

private def checkTinyRaw (raw : RawCandidate) (boundaries : Nat := 20) : Except String (Except Diagnostic Nat) := do
  let candidate ← (validateCandidate Examples.TinyMultiply.shape raw).mapError reprStr
  return Certification.check TinyProblem.problem candidate boundaries 64

private def expectTinyFailure (raw : RawCandidate) (expected : Diagnostic) : IO Unit := do
  match checkTinyRaw raw with
  | .ok (.error e) => require "wrong diagnostic" (e == expected)
  | other => throw (IO.userError s!"Expected symbolic rejection: {repr other}")

private def singleBox (interval : Interval) : Box :=
  fun i => if i = 0 then interval else Interval.point 0

def certification : IO Unit := do
  require "degree cap" (!(Value.ofPolynomial (singleBox ⟨-1,1⟩) [(List.replicate 65 0,1)] 64).isOk)
  let x := Polynomial.input 0
  let y := Polynomial.input 1
  require "commuting multiplication" (x.mul y == y.mul x)
  require "cancellation before interval analysis"
    (((x.mul x).add ((Polynomial.constant (-1)).mul (x.mul x))) == [])
  let p := (x.add y).pow 4
  let q := ((x.mul x).add y).pow 3
  let r := (x.add (Polynomial.constant 2)).pow 2
  require "canonical merge commutes and associates"
    (p.add q == q.add p && (p.add q).add r == p.add (q.add r))
  require "canonical merge cancels a larger polynomial"
    (p.add ((Polynomial.constant (-1)).mul p) == [])
  require "nonnegative square" (((x.mul x).bound (singleBox ⟨-4,3⟩)) == ⟨0,16⟩)
  require "range refusal is not success"
    (!(Value.ofPolynomial (singleBox ⟨-140737488355328,140737488355327⟩) (x.add x) 64).isOk)
  require "term cap" (!(Value.ofPolynomial (singleBox ⟨-4,3⟩) x 0).isOk)
  require "sort agrees including equal keys" (sort [(2,1),(1,2),(2,3)] (fun a b => a.1 ≤ b.1) == [(1,2),(2,1),(2,3)])
  match Evaluation.evaluateObjective [checkedTiny] Examples.TinyMultiply.raw [-7,6] 7 "regression" Evaluation.latency with
  | .accepted score => require "checker artifact uses existing scorer" (score.result.value == 6)
  | _ => throw (IO.userError "Checker-produced artifact was not accepted for scoring")
  let raw := Examples.TinyMultiply.raw
  match checkTinyRaw {raw with identifier := "new-unregistered-name", schedule := raw.schedule.reverse} with
  | .ok (.ok cycles) => require "arbitrary name and unsorted schedule" (cycles == 6)
  | _ => throw (IO.userError "Reversed renamed candidate failed")
  expectTinyFailure {raw with schedule := [⟨0,0,.load 1 0⟩,⟨1,0,.load 2 1⟩,
      ⟨2,0,.multiply 3 1 2⟩,⟨3,0,.store 3 2⟩]}
    (.machine ⟨3,some 0,.pendingRead 3⟩)
  expectTinyFailure {raw with schedule := [⟨0,0,.store 1 2⟩]}
    (.machine ⟨0,some 0,.uninitializedRegister 1⟩)
  expectTinyFailure {raw with schedule := []} (.missingOutput 0 2)
  match checkTinyRaw raw 6 with
  | .ok (.error (.exhausted 6)) => pure ()
  | _ => throw (IO.userError "Boundary exhaustion was not reported")
  let mut count := 0
  for artifact in Evaluation.objectiveCatalog do
    let raw := artifact.verified.candidate.toRaw
    let some (_, entry) := Catalog.find? raw.workloadIdentifier
      | throw (IO.userError s!"Missing symbolic reference for {raw.workloadIdentifier}")
    let candidate ← match validateCandidate entry.adapter.shape raw with
      | .ok c => pure c
      | .error e => throw (IO.userError (reprStr e))
    match Certification.check entry.problem candidate artifact.verified.sufficientBoundaries 4096 with
    | .ok _ => count := count + 1
    | .error e => throw (IO.userError s!"Existing artifact {raw.identifier} failed: {repr e}")
  IO.println s!"PASS: symbolic arithmetic, diagnostics, independent kernel certificate, and {count} existing artifacts"
end OptimalComputation.Tests
