import OptimalComputation.Certification.Workloads
import OptimalComputation.Examples.ProductPair

namespace OptimalComputation.Certification
open Hardware Workloads
set_option linter.unusedSimpArgs false

namespace TinyProblem
open Examples.TinyMultiply

def problem : Problem adapter where
  box := scalarBox adapter (fun _ => signed16Interval)
  input_sound := by
    intro x hx
    apply scalarBox_sound
    intro i
    have hi : i.val = 0 ∨ i.val = 1 := by have := i.isLt; change i.val < 2 at this; omega
    rcases hi with hi | hi
    · have he : i = (⟨0, by decide⟩ : Fin 2) := Fin.ext hi
      subst i
      exact hx.1
    · have he : i = (⟨1, by decide⟩ : Fin 2) := Fin.ext hi
      subst i
      exact hx.2
  outputs := [(Polynomial.input 0).mul (Polynomial.input 1)]
  output_sound := by
    intro x _
    simp [Polynomial.eval_mul, environment, adapter, shape, specification]
end TinyProblem

namespace PairProblem
open Examples.ProductPair

def problem : Problem adapter where
  box := scalarBox adapter (fun _ => signed16Interval)
  input_sound := by
    intro x hx
    apply scalarBox_sound
    intro i
    have hi : i.val = 0 ∨ i.val = 1 ∨ i.val = 2 ∨ i.val = 3 := by
      have := i.isLt; change i.val < 4 at this; omega
    rcases hi with hi | hi | hi | hi
    · have he : i = (⟨0, by decide⟩ : Fin 4) := Fin.ext hi
      subst i
      exact hx.1
    · have he : i = (⟨1, by decide⟩ : Fin 4) := Fin.ext hi
      subst i
      exact hx.2.1
    · have he : i = (⟨2, by decide⟩ : Fin 4) := Fin.ext hi
      subst i
      exact hx.2.2.1
    · have he : i = (⟨3, by decide⟩ : Fin 4) := Fin.ext hi
      subst i
      exact hx.2.2.2
  outputs := [(Polynomial.input 0).mul (Polynomial.input 1), (Polynomial.input 2).mul (Polynomial.input 3)]
  output_sound := by
    intro x _
    simp [Polynomial.eval_mul, environment, adapter, shape, specification]
end PairProblem
end OptimalComputation.Certification
