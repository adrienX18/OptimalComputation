import OptimalComputation.Examples.TinyVerified
import OptimalComputation.Evaluation.Checked

namespace OptimalComputation.Examples.TinyMultiply
open Hardware Workloads Candidates Evaluation

instance (x : specification.Input) : Decidable (specification.AllowedInput x) :=
  inferInstanceAs (Decidable (InSigned16 x.1 ∧ InSigned16 x.2))

def adapter : ScalarAdapter specification where
  shape := shape
  identifier := rfl
  inputScalars := fun x => #v[x.1, x.2]
  decodeInput := fun v => (v[0], v[1])
  input_roundtrip := by intro x; rfl
  input_fits := by
    intro x hx i
    have hi : i.val = 0 ∨ i.val = 1 := by have := i.isLt; change i.val < 2 at this; omega
    rcases hi with hi | hi
    · simpa +instances [shape, specification, hi] using signed16_fits_signed48 hx.1
    · simpa +instances [shape, specification, hi] using signed16_fits_signed48 hx.2
  outputScalars := fun y => #v[y]
  decodeOutput := fun v => v[0]
  output_roundtrip := by intro y; rfl

theorem adapter_encode (x : specification.Input) (hx : specification.AllowedInput x) :
    adapter.encode x hx = inputs x.1 x.2 hx.1 hx.2 := by
  apply Vector.ext
  intro i hi
  have hii : i = 0 ∨ i = 1 := by change i < 2 at hi; omega
  rcases hii with rfl | rfl <;> simp +instances [ScalarAdapter.encode, adapter, inputs, shape, specification]

/-- A registered proof for every signed16 pair; the six-cycle result was derived
from Hardware.step and Evaluation.run, not from an alternative reference runner. -/
def verified : VerifiedCandidate adapter where
  candidate := candidate
  sufficientBoundaries := 7
  safety := by
    intro x hx
    obtain ⟨record, he, _, _⟩ := execution_correct x.1 x.2 hx.1 hx.2
    refine ⟨record, ?_⟩
    rw [adapter_encode]
    exact he
  correctness := by
    intro x hx record he
    rw [adapter_encode] at he
    obtain ⟨expected, hh, ho, _⟩ := execution_correct x.1 x.2 hx.1 hx.2
    have hr : expected = record := ExecutionOutcome.success.inj (hh.symm.trans he)
    subst record
    exact ho

end OptimalComputation.Examples.TinyMultiply
