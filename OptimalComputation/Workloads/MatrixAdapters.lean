import OptimalComputation.Workloads.ScalarAdapter
import OptimalComputation.Workloads.MatVec
import OptimalComputation.Workloads.MatMul

namespace OptimalComputation.Workloads
open Hardware

/-- Fixed row-major scalarization. These codecs move values; they perform no
workload arithmetic and provide no intermediate or reference values to programs. -/
def vectorScalars (v : Vector16) : Vector Int 16 := Vector.ofFn v

def matrixScalars (m : Matrix16) : Vector Int 256 :=
  Vector.ofFn fun k => m ⟨k.val / 16, by omega⟩ ⟨k.val % 16, Nat.mod_lt _ (by decide)⟩

def decodeVector (v : Vector Int 16) : Vector16 := fun i => v[i.val]

def matrixIndex (i j : Index16) : Fin 256 := ⟨i.val * 16 + j.val, by omega⟩

def decodeMatrix (v : Vector Int 256) : Matrix16 := fun i j => v[(matrixIndex i j).val]

@[simp] theorem decodeVector_vectorScalars (v : Vector16) : decodeVector (vectorScalars v) = v := by
  funext i
  simp [decodeVector, vectorScalars]

@[simp] theorem matrixScalars_at (m : Matrix16) (i j : Index16) :
    (matrixScalars m)[(matrixIndex i j).val] = m i j := by
  simp only [matrixScalars, Vector.getElem_ofFn, matrixIndex]
  congr 1 <;> apply Fin.ext <;> simp only
  · omega
  · omega

@[simp] theorem decodeMatrix_matrixScalars (m : Matrix16) : decodeMatrix (matrixScalars m) = m := by
  funext i j
  exact matrixScalars_at m i j

theorem append_fits {n m : Nat} (xs : Vector Int n) (ys : Vector Int m)
    (hx : ∀ i : Fin n, InSigned48 xs[i.val])
    (hy : ∀ i : Fin m, InSigned48 ys[i.val]) (i : Fin (n + m)) :
    InSigned48 (xs ++ ys)[i.val] := by
  rw [Vector.getElem_append]
  split
  · exact hx ⟨i.val, by assumption⟩
  · exact hy ⟨i.val - n, by have := i.isLt; omega⟩

theorem matrixScalars_fits (x : Matrix16) (h : Matrix16.Allowed x) (i : Fin 256) :
    InSigned48 (matrixScalars x)[i.val] := by
  simp only [matrixScalars, Vector.getElem_ofFn]
  exact signed16_fits_signed48 (h _ _)

theorem vectorScalars_fits (x : Vector16) (h : Vector16.Allowed x) (i : Fin 16) :
    InSigned48 (vectorScalars x)[i.val] := by
  simp only [vectorScalars, Vector.getElem_ofFn]
  exact signed16_fits_signed48 (h _)

namespace MatVec

def scalarInput (x : Input) : Vector Int (256 + 16) :=
  (matrixScalars x.matrix).append (vectorScalars x.vector)

def scalarDecodeInput (v : Vector Int (256 + 16)) : Input := {
  matrix := fun i j => v[(matrixIndex i j).val]'(by have := (matrixIndex i j).isLt; omega)
  vector := fun i => v[256 + i.val]'(by omega)
}

theorem input_ext {x y : Input} (hm : x.matrix = y.matrix) (hv : x.vector = y.vector) : x = y := by
  cases x; cases y; simp_all

theorem scalarInput_roundtrip (x : Input) : scalarDecodeInput (scalarInput x) = x := by
  apply input_ext
  · funext i j
    change ((matrixScalars x.matrix) ++ (vectorScalars x.vector))[(matrixIndex i j).val] = x.matrix i j
    rw [Vector.getElem_append_left (matrixIndex i j).isLt]
    exact matrixScalars_at _ _ _
  · funext i
    change ((matrixScalars x.matrix) ++ (vectorScalars x.vector))[256 + i.val] = x.vector i
    rw [Vector.getElem_append_right (by omega) (by omega)]
    simp only [Nat.add_sub_cancel_left, vectorScalars, Vector.getElem_ofFn]

def adapter : ScalarAdapter specification where
  shape := shape
  identifier := rfl
  inputScalars := scalarInput
  decodeInput := scalarDecodeInput
  input_roundtrip := scalarInput_roundtrip
  input_fits := by
    intro x hx i
    exact append_fits _ _ (matrixScalars_fits _ hx.1) (vectorScalars_fits _ hx.2) i
  outputScalars := vectorScalars
  decodeOutput := decodeVector
  output_roundtrip := decodeVector_vectorScalars

end MatVec

namespace MatMul

def scalarInput (x : Input) : Vector Int (256 + 256) :=
  (matrixScalars x.left).append (matrixScalars x.right)

def scalarDecodeInput (v : Vector Int (256 + 256)) : Input := {
  left := fun i j => v[(matrixIndex i j).val]'(by have := (matrixIndex i j).isLt; omega)
  right := fun i j => v[256 + (matrixIndex i j).val]'(by have := (matrixIndex i j).isLt; omega)
}

theorem input_ext {x y : Input} (hl : x.left = y.left) (hr : x.right = y.right) : x = y := by
  cases x; cases y; simp_all

theorem scalarInput_roundtrip (x : Input) : scalarDecodeInput (scalarInput x) = x := by
  apply input_ext
  · funext i j
    change ((matrixScalars x.left) ++ (matrixScalars x.right))[(matrixIndex i j).val] = x.left i j
    rw [Vector.getElem_append_left (matrixIndex i j).isLt]
    exact matrixScalars_at _ _ _
  · funext i j
    change ((matrixScalars x.left) ++ (matrixScalars x.right))[256 + (matrixIndex i j).val] = x.right i j
    rw [Vector.getElem_append_right (by have := (matrixIndex i j).isLt; omega) (by omega)]
    simp only [Nat.add_sub_cancel_left]
    exact matrixScalars_at _ _ _

def adapter : ScalarAdapter specification where
  shape := shape
  identifier := rfl
  inputScalars := scalarInput
  decodeInput := scalarDecodeInput
  input_roundtrip := scalarInput_roundtrip
  input_fits := by
    intro x hx i
    exact append_fits _ _ (matrixScalars_fits _ hx.1) (matrixScalars_fits _ hx.2) i
  outputScalars := matrixScalars
  decodeOutput := decodeMatrix
  output_roundtrip := decodeMatrix_matrixScalars

end MatMul
end OptimalComputation.Workloads
