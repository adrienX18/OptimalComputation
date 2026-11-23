import OptimalComputation.Examples.SerialDot
import OptimalComputation.Workloads.MatrixAdapters

/-! The fixed naive matrix-vector baseline. All operands are explicit memory
loads; only lane zero and writable registers 1, 2, 3 are used. Each primitive
waits through its completion boundary before the next instruction issues. -/
namespace OptimalComputation.Examples.MatVecNaive
open Hardware Workloads Candidates Evaluation Evaluation.Serial
set_option backward.isDefEq.respectTransparency false
set_option maxRecDepth 10000

def inputAddress (i : Fin 272) : Address := ⟨i.val, by have := i.isLt; unfold localMemorySlots; omega⟩
def matrixAddress (i j : Index16) : Address := inputAddress ⟨i.val * 16 + j.val, by omega⟩
def vectorAddress (j : Index16) : Address := inputAddress ⟨256 + j.val, by omega⟩
def outputAddress (i : Index16) : Address := ⟨272 + i.val, by have := i.isLt; unfold localMemorySlots; omega⟩

set_option maxRecDepth 10000 in
set_option maxHeartbeats 2000000 in
def layout : Layout MatVec.shape := {
  inputs := List.ofFn inputAddress
  outputs := List.ofFn outputAddress
  scratch := []
  inputCount := by rfl
  outputCount := by rfl
  separate := by decide
}

def rowCode (i : Index16) : List BoundedInstruction :=
  [.add acc r0 r0] ++ SerialDot.code (matrixAddress i) vectorAddress 16 (by omega) ++
    [.store acc.val (outputAddress i)]

def rowsCode : (n : Nat) → n ≤ 16 → List BoundedInstruction
  | 0, _ => []
  | n + 1, h => rowsCode n (by omega) ++ rowCode ⟨n, by omega⟩

theorem input_declared (i : Fin 272) : inputAddress i ∈ layout.declared := by
  change inputAddress i ∈ (List.ofFn inputAddress ++ List.ofFn outputAddress ++ [])
  exact List.mem_append_left _ (List.mem_append_left _ (List.mem_ofFn.mpr ⟨i, rfl⟩))

theorem output_writable (i : Index16) : outputAddress i ∈ layout.writable := by
  change outputAddress i ∈ (List.ofFn outputAddress ++ [])
  exact List.mem_append_left _ (List.mem_ofFn.mpr ⟨i, rfl⟩)

theorem dot_allowed (i : Index16) (n : Nat) (hn : n ≤ 16) :
    ∀ instruction ∈ SerialDot.code (matrixAddress i) vectorAddress n hn,
      MemoryAllowed layout instruction := by
  induction n with
  | zero => simp [SerialDot.code]
  | succ n ih =>
    intro instruction hm
    simp only [SerialDot.code, List.mem_append] at hm
    rcases hm with hm | hm
    · exact ih (by omega) _ hm
    · simp only [SerialDot.block, List.mem_cons, List.not_mem_nil, or_false] at hm
      rcases hm with rfl | rfl | rfl
      · exact input_declared _
      · exact input_declared _
      · trivial

theorem row_allowed (i : Index16) : ∀ instruction ∈ rowCode i, MemoryAllowed layout instruction := by
  intro instruction hm
  simp only [rowCode, List.mem_append, List.mem_singleton] at hm
  rcases hm with (rfl | hm) | rfl
  · trivial
  · exact dot_allowed i 16 (by omega) _ hm
  · exact output_writable i

theorem rows_allowed (n : Nat) (hn : n ≤ 16) :
    ∀ instruction ∈ rowsCode n hn, MemoryAllowed layout instruction := by
  induction n with
  | zero => simp [rowsCode]
  | succ n ih =>
    intro instruction hm
    rcases List.mem_append.mp hm with hm | hm
    · exact ih (by omega) _ hm
    · exact row_allowed _ _ hm

/-- The generator fixes the same naive instruction order on every admissible
configuration; the configuration only changes available hardware resources. -/
def schedule (c : ValidConfig) (t : Nat) (is : List BoundedInstruction)
    (allowed : ∀ i ∈ is, MemoryAllowed layout i) : List (ScheduledInstruction c layout) :=
  match is with
  | [] => []
  | i :: is =>
      ⟨t, ⟨0, allowedCount_positive c.property.1⟩, i, allowed i (by simp)⟩ ::
        schedule c (t + latency i + 1) is (fun j hj => allowed j (by simp [hj]))

def candidateFor (c : ValidConfig) : Candidate MatVec.shape := {
  identifier := "matvec-naive-v1"
  identifier_nonempty := by decide
  configuration := c
  layout := layout
  schedule := schedule c 0 (rowsCode 16 (by omega)) (rows_allowed 16 (by omega))
}

def candidate : Candidate MatVec.shape := candidateFor defaultConfig

theorem schedule_timed (t : Nat) (is : List BoundedInstruction)
    (h : ∀ i ∈ is, MemoryAllowed layout i) :
    (schedule C t is h).map (fun i => (⟨i.cycle, ⟨i.lane, i.instruction⟩⟩ : TimedAction C)) = timed t is := by
  induction is generalizing t with
  | nil => rfl
  | cons i is ih => simp [schedule, timed, ih, lane]

theorem timed_sorted (t : Nat) (is : List BoundedInstruction) :
    (timed (c := C) t is).Pairwise (fun a b => decide (a.cycle ≤ b.cycle) = true) := by
  induction is generalizing t with
  | nil => simp [timed]
  | cons i is ih =>
    apply List.pairwise_cons.mpr
    constructor
    · intro b hb
      have := timed_after (t + latency i + 1) is b hb
      simp only [decide_eq_true_eq]
      omega
    · exact ih _

theorem candidate_program : program candidate = timed 0 (rowsCode 16 (by omega)) := by
  unfold program candidate candidateFor
  rw [schedule_timed]
  exact List.mergeSort_of_pairwise (timed_sorted _ _)

theorem row_duration (i : Index16) : duration (rowCode i) = 134 := by
  simp [rowCode, duration_append, SerialDot.code_duration, duration, latency]

theorem rows_duration (n : Nat) (hn : n ≤ 16) : duration (rowsCode n hn) = 134 * n := by
  induction n with
  | zero => rfl
  | succ n ih => simp [rowsCode, duration_append, row_duration, ih]; omega

theorem structural_validity (c : ValidConfig) :
    validateCandidate MatVec.shape (candidateFor c).toRaw = .ok (candidateFor c) :=
  validateCandidate_roundtrip _

/-! ### `matvec-naive-v2`

The same instructions, layout and order as `matvec-naive-v1`, but each issues on
its predecessor's completion boundary rather than one boundary later. The v1 idle
boundary was a proof convenience, not a machine rule; v1 stays frozen. -/

def candidateV2For (c : ValidConfig) : Candidate MatVec.shape := {
  identifier := "matvec-naive-v2"
  identifier_nonempty := by decide
  configuration := c
  layout := layout
  schedule := tightSchedule c layout 0 (rowsCode 16 (by omega)) (rows_allowed 16 (by omega))
}

def candidateV2 : Candidate MatVec.shape := candidateV2For defaultConfig

theorem candidateV2_program : program candidateV2 = tightTimed 0 (rowsCode 16 (by omega)) := by
  unfold program candidateV2 candidateV2For
  rw [tightSchedule_timed]
  exact List.mergeSort_of_pairwise (tightTimed_sorted _ _)

theorem row_tightDuration (i : Index16) : tightDuration (rowCode i) = 84 := by
  simp [rowCode, tightDuration_append, SerialDot.code_tightDuration, tightDuration, latency]

theorem rows_tightDuration (n : Nat) (hn : n ≤ 16) : tightDuration (rowsCode n hn) = 84 * n := by
  induction n with
  | zero => rfl
  | succ n ih => simp [rowsCode, tightDuration_append, row_tightDuration, ih]; omega

theorem structural_validity_v2 (c : ValidConfig) :
    validateCandidate MatVec.shape (candidateV2For c).toRaw = .ok (candidateV2For c) :=
  validateCandidate_roundtrip _

end OptimalComputation.Examples.MatVecNaive
