import OptimalComputation.Candidates.Program
import OptimalComputation.Hardware.Arithmetic

/-! The smallest transfer/arithmetic fixture. Values are runtime inputs. Only
its representation and structural validity are established here. `Tests.Execution`
checks its six-cycle execution; `TinyVerified` proves all-input execution and
`TinyCertificate` binds that proof to the mathematical specification. -/

namespace OptimalComputation.Examples.TinyMultiply

open Hardware Workloads Candidates

def specification : Specification := {
  identifier := "scalar-multiply-signed16-v1"
  Input := Int × Int
  AllowedInput := fun (a, b) => InSigned16 a ∧ InSigned16 b
  Output := Int
  reference := fun (a, b) => a * b
}

def shape : Shape := ⟨specification.identifier, 2, 1⟩

def configuration : ValidConfig := ⟨⟨1, 1⟩, by decide⟩

def a0 : Address := ⟨0, by decide⟩
def a1 : Address := ⟨1, by decide⟩
def a2 : Address := ⟨2, by decide⟩
def lane0 : Lane configuration := ⟨0, by decide⟩

def layout : Layout shape := {
  inputs := [a0, a1]
  outputs := [a2]
  scratch := []
  inputCount := by decide
  outputCount := by decide
  separate := by decide
}

def r1 : WritableRegister := ⟨⟨1, by decide⟩, by decide⟩
def r2 : WritableRegister := ⟨⟨2, by decide⟩, by decide⟩
def r3 : WritableRegister := ⟨⟨3, by decide⟩, by decide⟩

/-- Loads at 0 and 1, multiplication at 2, store at 5. Cycles 3 and 4
contain no issued instruction. The output store commits at boundary six. -/
def candidate : Candidate shape := {
  identifier := "tiny-multiply-v1"
  identifier_nonempty := by decide
  configuration := configuration
  layout := layout
  schedule := [
    ⟨0, lane0, .load r1 a0, by decide⟩,
    ⟨1, lane0, .load r2 a1, by decide⟩,
    ⟨2, lane0, .multiply r3 r1.val r2.val, trivial⟩,
    ⟨5, lane0, .store r3.val a2, by decide⟩
  ]
}

def raw : RawCandidate := {
  identifier := "tiny-multiply-v1"
  workloadIdentifier := "scalar-multiply-signed16-v1"
  configuration := ⟨1, 1⟩
  layout := ⟨[0, 1], [2], []⟩
  schedule := [⟨0, 0, .load 1 0⟩, ⟨1, 0, .load 2 1⟩,
    ⟨2, 0, .multiply 3 1 2⟩, ⟨5, 0, .store 3 2⟩]
}

theorem raw_matches : candidate.toRaw = raw := rfl

theorem structurally_valid : validateCandidate shape raw = .ok candidate := by
  rw [← raw_matches]
  exact validateCandidate_roundtrip candidate

end OptimalComputation.Examples.TinyMultiply
