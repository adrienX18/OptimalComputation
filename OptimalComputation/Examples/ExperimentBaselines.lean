import OptimalComputation.Examples.SerialNetwork

namespace OptimalComputation.Examples.ExperimentBaselines
open Hardware Workloads SerialNetwork
set_option backward.isDefEq.respectTransparency false
set_option maxRecDepth 10000
set_option maxHeartbeats 2000000
set_option linter.unusedSimpArgs false

def row (i : Fin 256) : Index16 := ⟨i.val / 16, by omega⟩
def column (i : Fin 256) : Index16 := ⟨i.val % 16, Nat.mod_lt _ (by decide)⟩

def gramNetwork {n : Nat} (hn : 512 + n ≤ localMemorySlots)
    (pairs : Vector (Index16 × Index16) n) (out : Fin 256 → Fin n)
    (covers : ∀ i, pairs[(out i).val] = (row i, column i) ∨ pairs[(out i).val] = (column i, row i)) :
    Network Gram.workload where
  count := n
  fits := hn
  node := fun j => {
    terms := 16
    short := by decide
    left := fun k => .inl (matrixIndex pairs[j.val].1 k)
    right := fun k => .inl (matrixIndex pairs[j.val].2 k)
  }
  output := out
  value := fun x j => Gram.atEntry x pairs[j.val].1 pairs[j.val].2
  seedEarlier := by intro j s h; cases h
  leftEarlier := by intros; trivial
  rightEarlier := by intros; trivial
  seedFits := by intro x h j s he; cases he
  leftFits := by intro x h j k; exact h _
  rightFits := by intro x h j k; exact h _
  equation := by intros; simp [Gram.atEntry, Gram.entry, sourceValue, Function.comp_def]; rfl
  result := by
    intro x h i
    change Gram.atEntry x pairs[(out i).val].1 pairs[(out i).val].2 = (Gram.reference x)[i.val]
    rcases covers i with hi | hi
    · simp [hi, Gram.reference, matrixScalars, row, column]
    · simp only [hi]
      rw [Gram.symmetric]
      simp [Gram.reference, matrixScalars, row, column]

def gramNaive : Network Gram.workload := gramNetwork (by decide)
  (Vector.ofFn fun i => (row i, column i)) id (fun _ => Or.inl (by simp))

/-- Each unordered pair occurs once, in row-major upper-triangular order. -/
def upperPairs : Vector (Index16 × Index16) 136 := ⟨#[
  (0, 0), (0, 1), (0, 2), (0, 3), (0, 4), (0, 5), (0, 6), (0, 7), (0, 8), (0, 9), (0, 10), (0, 11), (0, 12), (0, 13), (0, 14), (0, 15),
  (1, 1), (1, 2), (1, 3), (1, 4), (1, 5), (1, 6), (1, 7), (1, 8), (1, 9), (1, 10), (1, 11), (1, 12), (1, 13), (1, 14), (1, 15),
  (2, 2), (2, 3), (2, 4), (2, 5), (2, 6), (2, 7), (2, 8), (2, 9), (2, 10), (2, 11), (2, 12), (2, 13), (2, 14), (2, 15),
  (3, 3), (3, 4), (3, 5), (3, 6), (3, 7), (3, 8), (3, 9), (3, 10), (3, 11), (3, 12), (3, 13), (3, 14), (3, 15),
  (4, 4), (4, 5), (4, 6), (4, 7), (4, 8), (4, 9), (4, 10), (4, 11), (4, 12), (4, 13), (4, 14), (4, 15),
  (5, 5), (5, 6), (5, 7), (5, 8), (5, 9), (5, 10), (5, 11), (5, 12), (5, 13), (5, 14), (5, 15),
  (6, 6), (6, 7), (6, 8), (6, 9), (6, 10), (6, 11), (6, 12), (6, 13), (6, 14), (6, 15),
  (7, 7), (7, 8), (7, 9), (7, 10), (7, 11), (7, 12), (7, 13), (7, 14), (7, 15),
  (8, 8), (8, 9), (8, 10), (8, 11), (8, 12), (8, 13), (8, 14), (8, 15),
  (9, 9), (9, 10), (9, 11), (9, 12), (9, 13), (9, 14), (9, 15),
  (10, 10), (10, 11), (10, 12), (10, 13), (10, 14), (10, 15),
  (11, 11), (11, 12), (11, 13), (11, 14), (11, 15),
  (12, 12), (12, 13), (12, 14), (12, 15),
  (13, 13), (13, 14), (13, 15),
  (14, 14), (14, 15),
  (15, 15)
], by decide⟩

def upperIndex (i j : Index16) : Nat :=
  let a := min i.val j.val
  let b := max i.val j.val
  a * (33 - a) / 2 + b - a

theorem upperIndex_bound : ∀ i j : Index16, upperIndex i j < 136 := by decide

def symmetricOutput (i : Fin 256) : Fin 136 :=
  ⟨upperIndex (row i) (column i), upperIndex_bound _ _⟩

theorem upperPairs_cover : ∀ i : Fin 256,
    upperPairs[(symmetricOutput i).val] = (row i, column i) ∨
    upperPairs[(symmetricOutput i).val] = (column i, row i) := by decide

def gramSymmetric : Network Gram.workload :=
  gramNetwork (by decide) upperPairs symmetricOutput upperPairs_cover

def stageNode (j : Fin 32) : Node 528 32 where
  terms := 16
  short := by decide
  left := fun k => if h : j.val < 16 then .inl ⟨j.val * 16 + k.val, by omega⟩
    else .inl ⟨272 + ((j.val - 16) * 16 + k.val), by omega⟩
  right := fun k => if j.val < 16 then .inl ⟨256 + k.val, by omega⟩ else .inr ⟨k.val, by omega⟩

def stageValue (x : TwoStage.Input) (j : Fin 32) : Int :=
  if h : j.val < 16 then TwoStage.intermediate x ⟨j.val, h⟩
  else dot (TwoStage.b x ⟨j.val - 16, by omega⟩) (TwoStage.intermediate x)

theorem small_fits {v : Int} (h : -45 ≤ v ∧ v ≤ 45) : InSigned16 v := by
  simp only [InSigned16, signed16Min, signed16Max]; omega

def twoStage : Network TwoStage.workload where
  count := 32
  fits := by decide
  node := stageNode
  output := fun i => ⟨16 + i.val, by have hi : i.val < 16 := i.isLt; omega⟩
  value := stageValue
  seedEarlier := by intro j s h; cases h
  leftEarlier := by intro j k; dsimp [stageNode]; split <;> trivial
  rightEarlier := by
    intro j k
    dsimp [stageNode]
    split
    · trivial
    · dsimp [earlier]; omega
  seedFits := by intro x h j s he; cases he
  leftFits := by
    intro x h j k
    have hk : k.val < 16 := k.isLt
    dsimp [stageNode]
    split
    · exact small_fits (h.1 ⟨j.val * 16 + k.val, by omega⟩)
    · exact h.2 ⟨(j.val - 16) * 16 + k.val, by omega⟩
  rightFits := by
    intro x h j k
    have hk : k.val < 16 := k.isLt
    dsimp [stageNode]
    split
    · exact small_fits (h.1 ⟨256 + k.val, by omega⟩)
    · simp only [sourceValue, stageValue, hk, ↓reduceDIte]
      exact TwoStage.intermediate_fits x h k
  equation := by
    intro x h j
    by_cases hj : j.val < 16
    · simp [stageNode, stageValue, hj, sourceValue, TwoStage.intermediate, TwoStage.a, TwoStage.vector, matrixIndex, Function.comp_def, Nat.add_assoc]
      rfl
    · simp [stageNode, stageValue, hj, sourceValue, TwoStage.b, matrixIndex, Function.comp_def, Nat.add_assoc]
      rfl
  result := by
    intro x h i
    have hn : ¬16 + i.val < 16 := by omega
    simp [stageValue, TwoStage.workload, TwoStage.reference, hn]

/-- Default-configuration serial certificates. Configuration variants retain the
same instruction order and are separately reported by the experiment runner. -/
def gramNaiveVerified := SerialNetwork.verified gramNaive "gram-naive-v1" (by decide)
  (code_positive _ (by decide))
def gramSymmetricVerified := SerialNetwork.verified gramSymmetric "gram-symmetric-v1" (by decide)
  (code_positive _ (by decide))
def twoStageVerified := SerialNetwork.verified twoStage "two-stage-naive-v1" (by decide)
  (code_positive _ (by decide))

end OptimalComputation.Examples.ExperimentBaselines
