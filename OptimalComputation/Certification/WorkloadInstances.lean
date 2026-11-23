import OptimalComputation.Certification.Workloads

namespace OptimalComputation.Certification
open Hardware Workloads
set_option maxRecDepth 10000
set_option maxHeartbeats 400000
set_option linter.unusedSimpArgs false

namespace MatMulProblem

def entry (i j : Index16) : Polynomial :=
  Polynomial.dot (fun k : Index16 => Polynomial.input (i.val*16+k.val))
    (fun k => Polynomial.input (256+k.val*16+j.val))

theorem env_left (x : MatMul.Input) (i j : Index16) :
    environment MatMul.adapter x (i.val*16+j.val) = x.left i j := by
  have hi : i.val*16+j.val < 256 := by omega
  unfold environment
  rw [dite_eq_left (show i.val*16+j.val < MatMul.adapter.shape.inputCount from by change i.val*16+j.val < 512; omega)]
  change (matrixScalars x.left ++ matrixScalars x.right)[i.val*16+j.val] = _
  rw [Vector.getElem_append_left hi]
  exact matrixScalars_at _ i j

theorem env_right (x : MatMul.Input) (i j : Index16) :
    environment MatMul.adapter x (256+i.val*16+j.val) = x.right i j := by
  have hi : i.val*16+j.val < 256 := by omega
  unfold environment
  rw [dite_eq_left (show 256+i.val*16+j.val < MatMul.adapter.shape.inputCount from by change 256+i.val*16+j.val < 512; omega)]
  change (matrixScalars x.left ++ matrixScalars x.right)[256+i.val*16+j.val] = _
  rw [Vector.getElem_append_right (by omega) (by omega)]
  have he : 256+i.val*16+j.val-256 = i.val*16+j.val := by omega
  simp only [he]
  exact matrixScalars_at _ i j

theorem input_bound (x : MatMul.Input) (hx : MatMul.AllowedInput x) (i : Fin MatMul.shape.inputCount) :
    signed16Interval.Contains (MatMul.scalarInput x)[i.val] := by
  change InSigned16 ((matrixScalars x.left ++ matrixScalars x.right)[i.val])
  by_cases hi : i.val < 256
  · rw [Vector.getElem_append_left hi]
    simp only [matrixScalars, Vector.getElem_ofFn]
    exact hx.1 _ _
  · rw [Vector.getElem_append_right (by change i.val < 512; exact i.isLt) (by omega)]
    simp only [matrixScalars, Vector.getElem_ofFn]
    exact hx.2 _ _

theorem entry_sound (x : MatMul.Input) (i j : Index16) :
    (entry i j).eval (environment MatMul.adapter x) = MatMul.reference x i j := by
  simp only [entry, Polynomial.eval_dot, Polynomial.eval_variable, env_left, env_right, MatMul.reference]

def problem : Problem MatMul.adapter where
  box := scalarBox MatMul.adapter (fun _ => signed16Interval)
  input_sound := fun x hx => scalarBox_sound MatMul.adapter _ x (input_bound x hx)
  outputs := List.ofFn fun i : Fin 256 => entry ⟨i.val/16, by omega⟩ ⟨i.val%16, Nat.mod_lt _ (by decide)⟩
  output_sound := fun x _ => Polynomial.eval_outputs _ _ (environment MatMul.adapter x)
    (fun i : Fin 256 => entry_sound x ⟨i.val/16, by omega⟩ ⟨i.val%16, Nat.mod_lt _ (by decide)⟩)
end MatMulProblem

theorem flat_environment (w : FlatWorkload) (x : Vector Int w.inputs) (i : Nat) (hi : i < w.inputs) :
    environment w.adapter x i = x[i] := by
  unfold environment
  exact dite_eq_left hi

namespace GramProblem

def entry (i j : Index16) : Polynomial :=
  Polynomial.dot (fun k : Index16 => Polynomial.input (i.val*16+k.val))
    (fun k => Polynomial.input (j.val*16+k.val))

theorem env_entry (x : Gram.Input) (i j : Index16) :
    environment Gram.workload.adapter x (i.val*16+j.val) = Gram.entry x i j :=
  flat_environment Gram.workload x _ (by change i.val*16+j.val < 256; omega)

theorem entry_sound (x : Gram.Input) (i j : Index16) :
    (entry i j).eval (environment Gram.workload.adapter x) = Gram.atEntry x i j := by
  simp only [entry, Polynomial.eval_dot, Polynomial.eval_variable, env_entry, Gram.atEntry]

def problem : Problem Gram.workload.adapter where
  box := scalarBox Gram.workload.adapter (fun _ => signed16Interval)
  input_sound := fun x hx => scalarBox_sound Gram.workload.adapter _ x hx
  outputs := List.ofFn fun i : Fin 256 => entry ⟨i.val/16, by omega⟩ ⟨i.val%16, Nat.mod_lt _ (by decide)⟩
  output_sound := fun x _ => Polynomial.eval_outputs _ _ (environment Gram.workload.adapter x)
    (fun i : Fin 256 => entry_sound x ⟨i.val/16, by omega⟩ ⟨i.val%16, Nat.mod_lt _ (by decide)⟩)
end GramProblem

namespace PolynomialProblem

def entry (i : Index16) : Polynomial :=
  (Polynomial.input 0).add (Polynomial.dot
    (fun k : Fin 7 => Polynomial.input (k.val+1))
    (fun k => (Polynomial.input (8+i.val)).pow (k.val+1)))

def bounds (i : Fin 24) : Interval := if i.val < 8 then ⟨-8,7⟩ else ⟨-4,3⟩

theorem input_bound (x : Workloads.Polynomial.Input) (hx : Workloads.Polynomial.Allowed x) (i : Fin 24) :
    (bounds i).Contains x[i.val] := by
  unfold bounds
  split
  · exact hx.1 ⟨i.val, by assumption⟩
  · have h := hx.2 ⟨i.val-8, by omega⟩
    have he : 8+(i.val-8) = i.val := by omega
    simpa only [he, Interval.Contains, signed16Interval, InSigned16] using h

theorem entry_sound (x : Workloads.Polynomial.Input) (i : Index16) :
    (entry i).eval (environment Workloads.Polynomial.workload.adapter x) = Workloads.Polynomial.atPoint x i := by
  simp only [entry, Polynomial.eval_add, Polynomial.eval_dot, Polynomial.eval_variable, Polynomial.eval_pow]
  have h0 := flat_environment Workloads.Polynomial.workload x 0 (by decide)
  have hc (k : Fin 7) := flat_environment Workloads.Polynomial.workload x (k.val+1) (by change k.val+1 < 24; omega)
  have hx := flat_environment Workloads.Polynomial.workload x (8+i.val) (by change 8+i.val < 24; omega)
  simp only [h0, hc, hx, Workloads.Polynomial.atPoint, Workloads.Polynomial.coefficient, Workloads.Polynomial.point]
  rfl

def problem : Problem Workloads.Polynomial.workload.adapter where
  box := scalarBox Workloads.Polynomial.workload.adapter bounds
  input_sound := fun x hx => scalarBox_sound Workloads.Polynomial.workload.adapter _ x (input_bound x hx)
  outputs := List.ofFn entry
  output_sound := fun x _ => Polynomial.eval_outputs _ _ (environment Workloads.Polynomial.workload.adapter x) (entry_sound x)
end PolynomialProblem

namespace TwoStageProblem

def intermediate (i : Index16) : Polynomial :=
  Polynomial.dot (fun k : Index16 => Polynomial.input (i.val*16+k.val))
    (fun k => Polynomial.input (256+k.val))
def entry (i : Index16) : Polynomial :=
  Polynomial.dot (fun k : Index16 => Polynomial.input (272+i.val*16+k.val)) intermediate

def bounds (i : Fin 528) : Interval := if i.val < 272 then ⟨-45,45⟩ else signed16Interval

theorem input_bound (x : TwoStage.Input) (hx : TwoStage.Allowed x) (i : Fin 528) :
    (bounds i).Contains x[i.val] := by
  unfold bounds
  split
  · exact hx.1 ⟨i.val, by assumption⟩
  · have h := hx.2 ⟨i.val-272, by omega⟩
    have he : 272+(i.val-272) = i.val := by omega
    simpa only [he, Interval.Contains, signed16Interval, InSigned16] using h

theorem intermediate_sound (x : TwoStage.Input) (i : Index16) :
    (intermediate i).eval (environment TwoStage.workload.adapter x) = TwoStage.intermediate x i := by
  have ha (k : Index16) := flat_environment TwoStage.workload x (i.val*16+k.val) (by change i.val*16+k.val < 528; omega)
  have hv (k : Index16) := flat_environment TwoStage.workload x (256+k.val) (by change 256+k.val < 528; omega)
  simp only [intermediate, Polynomial.eval_dot, Polynomial.eval_variable, ha, hv,
    TwoStage.intermediate, TwoStage.a, TwoStage.vector, matrixIndex]
  rfl

theorem entry_sound (x : TwoStage.Input) (i : Index16) :
    (entry i).eval (environment TwoStage.workload.adapter x) = dot (TwoStage.b x i) (TwoStage.intermediate x) := by
  have hb (k : Index16) := flat_environment TwoStage.workload x (272+i.val*16+k.val)
    (by change 272+i.val*16+k.val < 528; omega)
  simp only [entry, Polynomial.eval_dot, Polynomial.eval_variable, hb, intermediate_sound, TwoStage.b, matrixIndex]
  simp only [Nat.add_assoc]
  rfl

def problem : Problem TwoStage.workload.adapter where
  box := scalarBox TwoStage.workload.adapter bounds
  input_sound := fun x hx => scalarBox_sound TwoStage.workload.adapter _ x (input_bound x hx)
  outputs := List.ofFn entry
  output_sound := fun x _ => Polynomial.eval_outputs _ _ (environment TwoStage.workload.adapter x) (entry_sound x)
end TwoStageProblem

end OptimalComputation.Certification
