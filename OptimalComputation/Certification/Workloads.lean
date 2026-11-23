import OptimalComputation.Certification.Checker
import OptimalComputation.Workloads.ExperimentWorkloads

namespace OptimalComputation.Certification
open Hardware Workloads
set_option maxRecDepth 10000
set_option maxHeartbeats 400000
set_option linter.unusedSimpArgs false

namespace Polynomial

def dotPrefix {n : Nat} (a b : Fin n → Polynomial) : (k : Nat) → k ≤ n → Polynomial
  | 0, _ => []
  | k+1, h => (dotPrefix a b k (by omega)).add ((a ⟨k, by omega⟩).mul (b ⟨k, by omega⟩))
def dot {n : Nat} (a b : Fin n → Polynomial) : Polynomial := dotPrefix a b n (Nat.le_refl n)

theorem eval_dotPrefix {n : Nat} (a b : Fin n → Polynomial) (k : Nat) (hk : k ≤ n) (x : Nat → Int) :
    (dotPrefix a b k hk).eval x = Workloads.dotPrefix (fun i => (a i).eval x) (fun i => (b i).eval x) k hk := by
  induction k with
  | zero => rfl
  | succ k ih => simp [dotPrefix, eval_add, eval_mul, Workloads.dotPrefix, ih]

theorem eval_dot {n : Nat} (a b : Fin n → Polynomial) (x : Nat → Int) :
    (dot a b).eval x = Workloads.dot (fun i => (a i).eval x) (fun i => (b i).eval x) :=
  eval_dotPrefix a b n (Nat.le_refl n) x
theorem eval_outputs {n : Nat} (polys : Fin n → Polynomial) (result : Fin n → Int) (x : Nat → Int)
    (h : ∀ i, (polys i).eval x = result i) :
    (List.ofFn polys).map (Polynomial.eval x) = (Vector.ofFn result).toList := by
  rw [List.map_ofFn, Vector.toList_ofFn]
  exact congrArg List.ofFn (funext h)

end Polynomial

def scalarBox (a : ScalarAdapter spec) (bounds : Fin a.shape.inputCount → Interval) : Box := List.ofFn bounds

theorem scalarBox_sound (a : ScalarAdapter spec) (bounds : Fin a.shape.inputCount → Interval)
    (x : spec.Input) (h : ∀ i : Fin a.shape.inputCount, (bounds i).Contains ((a.inputScalars x)[i.val])) :
    (scalarBox a bounds).Allowed (environment a x) := by
  intro i
  by_cases hi : i < a.shape.inputCount
  · simpa [scalarBox, Box.at, environment, hi] using h ⟨i, hi⟩
  · simp [scalarBox, Box.at, environment, hi, Interval.Contains, Interval.point]

def signed16Interval : Interval := ⟨signed16Min, signed16Max⟩

theorem signed16Interval_contains {x : Int} (h : InSigned16 x) : signed16Interval.Contains x := h

namespace MatVecProblem

def entry (i : Index16) : Polynomial :=
  Polynomial.dot (fun k : Index16 => Polynomial.input (i.val*16+k.val))
    (fun k => Polynomial.input (256+k.val))

theorem env_matrix (x : MatVec.Input) (i j : Index16) :
    environment MatVec.adapter x (i.val*16+j.val) = x.matrix i j := by
  have hi : i.val*16+j.val < 256 := by omega
  unfold environment
  rw [dite_eq_left (show i.val*16+j.val < MatVec.adapter.shape.inputCount from by change i.val*16+j.val < 272; omega)]
  change (matrixScalars x.matrix ++ vectorScalars x.vector)[i.val*16+j.val] = _
  rw [Vector.getElem_append_left hi]
  exact matrixScalars_at _ i j

theorem env_vector (x : MatVec.Input) (i : Index16) :
    environment MatVec.adapter x (256+i.val) = x.vector i := by
  unfold environment
  rw [dite_eq_left (show 256+i.val < MatVec.adapter.shape.inputCount from by change 256+i.val < 272; omega)]
  change (matrixScalars x.matrix ++ vectorScalars x.vector)[256+i.val] = _
  rw [Vector.getElem_append_right (by omega) (by omega)]
  simp [vectorScalars]

theorem input_bound (x : MatVec.Input) (hx : MatVec.AllowedInput x) (i : Fin MatVec.shape.inputCount) :
    signed16Interval.Contains (MatVec.scalarInput x)[i.val] := by
  change InSigned16 ((matrixScalars x.matrix ++ vectorScalars x.vector)[i.val])
  by_cases hi : i.val < 256
  · rw [Vector.getElem_append_left hi]
    simp only [matrixScalars, Vector.getElem_ofFn]
    exact hx.1 _ _
  · rw [Vector.getElem_append_right (by change i.val < 272; exact i.isLt) (by omega)]
    simp only [vectorScalars, Vector.getElem_ofFn]
    exact hx.2 _

theorem entry_sound (x : MatVec.Input) (i : Index16) :
    (entry i).eval (environment MatVec.adapter x) = MatVec.reference x i := by
  simp only [entry, Polynomial.eval_dot, Polynomial.eval_variable, env_matrix, env_vector, MatVec.reference]

def problem : Problem MatVec.adapter where
  box := scalarBox MatVec.adapter (fun _ => signed16Interval)
  input_sound := fun x hx => scalarBox_sound MatVec.adapter _ x (input_bound x hx)
  outputs := List.ofFn entry
  output_sound := fun x _ => Polynomial.eval_outputs entry (MatVec.reference x)
    (environment MatVec.adapter x) (entry_sound x)

end MatVecProblem

end OptimalComputation.Certification
