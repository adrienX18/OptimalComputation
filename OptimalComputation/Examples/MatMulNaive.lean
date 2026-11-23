import OptimalComputation.Examples.SerialDot
import OptimalComputation.Workloads.MatrixAdapters

/-! The fixed naive matrix-matrix baseline. All operands are explicit memory
loads; only lane zero and writable registers 1, 2, 3 are used. Each primitive
waits through its completion boundary before the next instruction issues. -/
namespace OptimalComputation.Examples.MatMulNaive
open Hardware Workloads Candidates Evaluation Evaluation.Serial
set_option backward.isDefEq.respectTransparency false
set_option maxRecDepth 10000

def inputAddress (i : Fin 512) : Address := ⟨i.val, by have := i.isLt; unfold localMemorySlots; omega⟩
def leftAddress (i j : Index16) : Address := inputAddress ⟨i.val * 16 + j.val, by omega⟩
def rightAddress (i j : Index16) : Address := inputAddress ⟨256 + i.val * 16 + j.val, by omega⟩

/-- Flattened i,j order: j varies fastest; k varies within each dot product. -/
def entryRow (q : Fin 256) : Index16 := ⟨q.val / 16, by omega⟩
def entryColumn (q : Fin 256) : Index16 := ⟨q.val % 16, Nat.mod_lt _ (by decide)⟩
def outputAddress (i : Fin 256) : Address := ⟨512 + i.val, by have := i.isLt; unfold localMemorySlots; omega⟩

def layout : Layout MatMul.shape := {
  inputs := List.ofFn inputAddress
  outputs := List.ofFn outputAddress
  scratch := []
  inputCount := by rfl
  outputCount := by rfl
  separate := by
    simp only [List.append_nil, List.nodup_append]
    refine ⟨?_, ?_, ?_⟩
    · apply List.nodup_iff_eq_of_getElem_eq.mpr
      intro i j hi hj he
      simp only [List.getElem_ofFn] at he
      exact congrArg Fin.val he
    · apply List.nodup_iff_eq_of_getElem_eq.mpr
      intro i j hi hj he
      simp only [List.getElem_ofFn] at he
      have := congrArg Fin.val he
      simp only [outputAddress] at this
      omega
    · intro a ha b hb he
      obtain ⟨i, rfl⟩ := List.mem_ofFn.mp ha
      obtain ⟨j, rfl⟩ := List.mem_ofFn.mp hb
      have := congrArg Fin.val he
      simp only [inputAddress, outputAddress] at this
      have := i.isLt
      omega
}

def entryCode (i : Fin 256) : List BoundedInstruction :=
  [.add acc r0 r0] ++ SerialDot.code (leftAddress (entryRow i)) (fun k => rightAddress k (entryColumn i)) 16 (by omega) ++
    [.store acc.val (outputAddress i)]

def entriesCode : (n : Nat) → n ≤ 256 → List BoundedInstruction
  | 0, _ => []
  | n + 1, h => entriesCode n (by omega) ++ entryCode ⟨n, by omega⟩

theorem input_declared (i : Fin 512) : inputAddress i ∈ layout.declared := by
  change inputAddress i ∈ (List.ofFn inputAddress ++ List.ofFn outputAddress ++ [])
  exact List.mem_append_left _ (List.mem_append_left _ (List.mem_ofFn.mpr ⟨i, rfl⟩))

theorem output_writable (i : Fin 256) : outputAddress i ∈ layout.writable := by
  change outputAddress i ∈ (List.ofFn outputAddress ++ [])
  exact List.mem_append_left _ (List.mem_ofFn.mpr ⟨i, rfl⟩)

theorem dot_allowed (i : Fin 256) (n : Nat) (hn : n ≤ 16) :
    ∀ instruction ∈ SerialDot.code (leftAddress (entryRow i)) (fun k => rightAddress k (entryColumn i)) n hn,
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

theorem entry_allowed (i : Fin 256) : ∀ instruction ∈ entryCode i, MemoryAllowed layout instruction := by
  intro instruction hm
  simp only [entryCode, List.mem_append, List.mem_singleton] at hm
  rcases hm with (rfl | hm) | rfl
  · trivial
  · exact dot_allowed i 16 (by omega) _ hm
  · exact output_writable i

theorem entries_allowed (n : Nat) (hn : n ≤ 256) :
    ∀ instruction ∈ entriesCode n hn, MemoryAllowed layout instruction := by
  induction n with
  | zero => simp [entriesCode]
  | succ n ih =>
    intro instruction hm
    rcases List.mem_append.mp hm with hm | hm
    · exact ih (by omega) _ hm
    · exact entry_allowed _ _ hm

/-- The generator fixes the same naive instruction order on every admissible
configuration; the configuration only changes available hardware resources. -/
def schedule (c : ValidConfig) (t : Nat) (is : List BoundedInstruction)
    (allowed : ∀ i ∈ is, MemoryAllowed layout i) : List (ScheduledInstruction c layout) :=
  match is with
  | [] => []
  | i :: is =>
      ⟨t, ⟨0, allowedCount_positive c.property.1⟩, i, allowed i (by simp)⟩ ::
        schedule c (t + latency i + 1) is (fun j hj => allowed j (by simp [hj]))

def candidateFor (c : ValidConfig) : Candidate MatMul.shape := {
  identifier := "matmul-naive-v1"
  identifier_nonempty := by decide
  configuration := c
  layout := layout
  schedule := schedule c 0 (entriesCode 256 (by omega)) (entries_allowed 256 (by omega))
}

def candidate : Candidate MatMul.shape := candidateFor defaultConfig

theorem schedule_timed (t : Nat) (is : List BoundedInstruction)
    (h : ∀ i ∈ is, MemoryAllowed layout i) :
    (schedule C t is h).map (fun i => (⟨i.cycle, ⟨i.lane, i.instruction⟩⟩ : TimedAction C)) = timed t is := by
  induction is generalizing t with
  | nil => rfl
  | cons i is ih => simp [schedule, timed, ih, lane]

theorem timed_sorted (t : Nat) (is : List BoundedInstruction) :
    (timed t is).Pairwise (fun a b => decide (a.cycle ≤ b.cycle) = true) := by
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

theorem candidate_program : program candidate = timed 0 (entriesCode 256 (by omega)) := by
  unfold program candidate candidateFor
  rw [schedule_timed]
  exact List.mergeSort_of_pairwise (timed_sorted _ _)

theorem entry_duration (i : Fin 256) : duration (entryCode i) = 134 := by
  simp [entryCode, duration_append, SerialDot.code_duration, duration, latency]

theorem entries_duration (n : Nat) (hn : n ≤ 256) : duration (entriesCode n hn) = 134 * n := by
  induction n with
  | zero => rfl
  | succ n ih => simp [entriesCode, duration_append, entry_duration, ih]; omega

theorem structural_validity (c : ValidConfig) :
    validateCandidate MatMul.shape (candidateFor c).toRaw = .ok (candidateFor c) :=
  validateCandidate_roundtrip _

/-! ### `matmul-naive-v2`

The same instructions, layout and i,j,k order as `matmul-naive-v1`, but each
issues on its predecessor's completion boundary rather than one boundary later.
The v1 idle boundary was a proof convenience, not a machine rule; v1 stays frozen. -/

def candidateV2For (c : ValidConfig) : Candidate MatMul.shape := {
  identifier := "matmul-naive-v2"
  identifier_nonempty := by decide
  configuration := c
  layout := layout
  schedule := tightSchedule c layout 0 (entriesCode 256 (by omega)) (entries_allowed 256 (by omega))
}

def candidateV2 : Candidate MatMul.shape := candidateV2For defaultConfig

theorem candidateV2_program : program candidateV2 = tightTimed 0 (entriesCode 256 (by omega)) := by
  unfold program candidateV2 candidateV2For
  rw [tightSchedule_timed]
  exact List.mergeSort_of_pairwise (tightTimed_sorted _ _)

theorem entry_tightDuration (i : Fin 256) : tightDuration (entryCode i) = 84 := by
  simp [entryCode, tightDuration_append, SerialDot.code_tightDuration, tightDuration, latency]

theorem entries_tightDuration (n : Nat) (hn : n ≤ 256) :
    tightDuration (entriesCode n hn) = 84 * n := by
  induction n with
  | zero => rfl
  | succ n ih => simp [entriesCode, tightDuration_append, entry_tightDuration, ih]; omega

theorem structural_validity_v2 (c : ValidConfig) :
    validateCandidate MatMul.shape (candidateV2For c).toRaw = .ok (candidateV2For c) :=
  validateCandidate_roundtrip _

end OptimalComputation.Examples.MatMulNaive
