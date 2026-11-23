import OptimalComputation.Examples.MatVecNaive
import OptimalComputation.Evaluation.Initialization

namespace OptimalComputation.Examples.MatVecNaive
open Hardware Workloads Candidates Evaluation Evaluation.Serial
set_option backward.isDefEq.respectTransparency false
set_option maxRecDepth 10000

/-- Memory invariant at row boundaries: all runtime inputs remain unchanged. -/
def Inputs (x : MatVec.Input) (hx : MatVec.AllowedInput x) (s : State C) : Prop :=
  (∀ i j, s.readMemory (matrixAddress i j) =
    some (encodeSlot ⟨x.matrix i j, signed16_fits_signed48 (hx.1 i j)⟩)) ∧
  (∀ j, s.readMemory (vectorAddress j) =
    some (encodeSlot ⟨x.vector j, signed16_fits_signed48 (hx.2 j)⟩))

def resultValue (x : MatVec.Input) (hx : MatVec.AllowedInput x) (i : Index16) : Signed48 :=
  ⟨MatVec.reference x i, MatVec.reference_fits_signed48 x hx i⟩

theorem row_executes (x : MatVec.Input) (hx : MatVec.AllowedInput x)
    (i : Index16) (s : State C) (hs : Quiet s) (hi : Inputs x hx s) :
    ∃ final, Executes (rowCode i) s final ∧
      final.memory = (s.writeMemory (outputAddress i) (encodeSlot (resultValue x hx i))).memory := by
  let reset := s.writeRegister lane acc zero48
  have hr : Executes [.add acc r0 r0] s reset :=
    .cons _ _ _ _ (.register acc zero48) hs (fun t => prepare_reset t s hs) (.nil reset hs)
  have hm : Inputs x hx reset := hi
  obtain ⟨middle, hd, hmem, hv⟩ := SerialDot.executes_prefix (x.matrix i) x.vector (hx.1 i) hx.2
    (matrixAddress i) vectorAddress reset hs (hm.1 i) hm.2
    (State.readRegister_write_same s lane acc zero48) 16 (by omega) (by omega)
  have hv' : middle.readRegister lane acc.val = some (resultValue x hx i) := hv
  let final := middle.writeMemory (outputAddress i) (encodeSlot (resultValue x hx i))
  have hq := executes_quiet hd
  have he : Executes [.store acc.val (outputAddress i)] middle final :=
    .cons _ _ _ _ (.memory (outputAddress i) (encodeSlot (resultValue x hx i))) hq
      (fun t => prepare_store t middle hq acc.val (outputAddress i) _ hv') (.nil final hq)
  refine ⟨final, executes_append (executes_append hr hd) he, ?_⟩
  simp only [final, State.writeMemory, hmem]
  rfl

theorem output_ne_input (i : Index16) (j : Fin 272) : outputAddress i ≠ inputAddress j := by
  intro h
  have he := congrArg Fin.val h
  simp only [outputAddress, inputAddress] at he
  have := j.isLt
  omega

theorem output_injective (i j : Index16) : outputAddress i = outputAddress j ↔ i = j := by
  constructor
  · intro h; apply Fin.ext; have := congrArg Fin.val h; simp only [outputAddress] at this; omega
  · intro h; subst j; rfl

theorem row_inputs (x : MatVec.Input) (hx : MatVec.AllowedInput x) (i : Index16)
    (s final : State C) (hi : Inputs x hx s)
    (hm : final.memory = (s.writeMemory (outputAddress i) (encodeSlot (resultValue x hx i))).memory) :
    Inputs x hx final := by
  constructor
  · intro r k
    change final.memory[_] = _
    rw [hm]
    change (s.writeMemory _ _).readMemory (matrixAddress r k) = _
    rw [State.readMemory_write_other s _ (matrixAddress r k) _ (output_ne_input i _)]
    exact hi.1 r k
  · intro k
    change final.memory[_] = _
    rw [hm]
    change (s.writeMemory _ _).readMemory (vectorAddress k) = _
    rw [State.readMemory_write_other s _ (vectorAddress k) _ (output_ne_input i _)]
    exact hi.2 k

/-- Row induction composes the same dot-product theorem sixteen times. Output
slots before the current row are preserved, and every input remains read-only. -/
theorem rows_executes (x : MatVec.Input) (hx : MatVec.AllowedInput x)
    (s : State C) (hs : Quiet s) (hi : Inputs x hx s) (n : Nat) (hn : n ≤ 16) :
    ∃ final, Executes (rowsCode n hn) s final ∧ Inputs x hx final ∧
      ∀ i : Index16, i.val < n →
        final.readMemory (outputAddress i) = some (encodeSlot (resultValue x hx i)) := by
  induction n with
  | zero => exact ⟨s, .nil s hs, hi, by intro i h; omega⟩
  | succ n ih =>
    obtain ⟨middle, he, hi, ho⟩ := ih (by omega)
    let i : Index16 := ⟨n, by omega⟩
    obtain ⟨final, hr, hm⟩ := row_executes x hx i middle (executes_quiet he) hi
    refine ⟨final, executes_append he hr, row_inputs x hx i middle final hi hm, ?_⟩
    intro j hj
    change final.memory[_] = _
    rw [hm]
    change (middle.writeMemory _ _).readMemory (outputAddress j) = _
    by_cases hjn : j = i
    · subst j; exact State.readMemory_write_same _ _ _
    · rw [State.readMemory_write_other _ _ _ _ (by
        intro h; exact hjn ((output_injective i j).mp h).symm)]
      apply ho
      have : j.val ≠ n := by intro h; exact hjn (Fin.ext h)
      omega


theorem initialization_pairs (values : Vector Signed48 272) :
    layout.inputs.zip values.toList = List.ofFn (fun i : Fin 272 => (inputAddress i, values[i.val])) := by
  change (List.ofFn inputAddress).zip values.toList = _
  apply List.ext_getElem
  · simp only [List.length_zip, List.length_ofFn, Vector.length_toList, Nat.min_self]
  · intro k hk hk'
    simp only [List.getElem_zip, List.getElem_ofFn, Vector.getElem_toList]

theorem initial_read (values : Vector Signed48 272) (i : Fin 272) :
    (initialState C layout values).readMemory (inputAddress i) = some (encodeSlot values[i.val]) := by
  change (writeValues (State.empty C) (layout.inputs.zip values.toList)).readMemory _ = _
  rw [initialization_pairs]
  apply writeValues_read
  · exact List.mem_ofFn.mpr ⟨i, rfl⟩
  · intro p hp he
    obtain ⟨j, rfl⟩ := List.mem_ofFn.mp hp
    have hij : j = i := Fin.ext (congrArg (fun a : Address => a.val) he)
    subst j
    rfl

theorem initial_quiet (values : Vector Signed48 272) : Quiet (initialState C layout values) := by
  change (writeValues (State.empty C) (layout.inputs.zip values.toList)).pending = _
  rw [writeValues_pending]
  rfl

theorem encode_matrix (x : MatVec.Input) (hx : MatVec.AllowedInput x) (i j : Index16) :
    (MatVec.adapter.encode x hx)[i.val * 16 + j.val]'(by change _ < 272; omega) =
      (⟨x.matrix i j, signed16_fits_signed48 (hx.1 i j)⟩ : Signed48) := by
  apply Subtype.ext
  simp only [ScalarAdapter.encode, Vector.getElem_ofFn, MatVec.adapter, MatVec.scalarInput]
  change ((matrixScalars x.matrix) ++ (vectorScalars x.vector))[(matrixIndex i j).val] = _
  rw [Vector.getElem_append_left (by have := (matrixIndex i j).isLt; exact this)]
  exact matrixScalars_at x.matrix i j

theorem encode_vector (x : MatVec.Input) (hx : MatVec.AllowedInput x) (j : Index16) :
    (MatVec.adapter.encode x hx)[256 + j.val]'(by change _ < 272; omega) =
      (⟨x.vector j, signed16_fits_signed48 (hx.2 j)⟩ : Signed48) := by
  apply Subtype.ext
  simp only [ScalarAdapter.encode, Vector.getElem_ofFn, MatVec.adapter, MatVec.scalarInput]
  change ((matrixScalars x.matrix) ++ (vectorScalars x.vector))[256 + j.val] = _
  rw [Vector.getElem_append_right (by omega) (by omega)]
  simp only [Nat.add_sub_cancel_left, vectorScalars, Vector.getElem_ofFn]

theorem initial_inputs (x : MatVec.Input) (hx : MatVec.AllowedInput x) :
    Inputs x hx (initialState C layout (MatVec.adapter.encode x hx)) := by
  constructor
  · intro i j
    change (initialState C layout _).readMemory (inputAddress _) = _
    rw [initial_read]
    exact congrArg (fun v => some (encodeSlot v)) (encode_matrix x hx i j)
  · intro j
    change (initialState C layout _).readMemory (inputAddress _) = _
    rw [initial_read]
    exact congrArg (fun v => some (encodeSlot v)) (encode_vector x hx j)


theorem filterMap_ofFn {n : Nat} (f : Fin n → α) (g : α → Option β) (v : Fin n → β)
    (h : ∀ i, g (f i) = some (v i)) : (List.ofFn f).filterMap g = List.ofFn v := by
  have hf : List.ofFn f = (List.finRange n).map f := by
    simp only [List.finRange, List.map_ofFn, Function.comp_def]
  rw [hf, List.filterMap_map]
  simp only [Function.comp_def, h, List.filterMap_eq_map', List.finRange, List.map_ofFn]

theorem finish_correct (x : MatVec.Input) (hx : MatVec.AllowedInput x) (s : State C)
    (counts : Counters)
    (ho : ∀ i, s.readMemory (outputAddress i) = some (encodeSlot (resultValue x hx i))) :
    ∃ record, finish candidate ⟨2143, s, counts, []⟩ = .success record ∧
      record.outputs = (MatVec.adapter.outputScalars (MatVec.reference x)).toList ∧
      record.cycles = 2143 := by
  have hl : candidate.layout = layout := rfl
  have hm : (layout.outputs.filter (fun a => (s.readMemory a).isNone)) = [] := by
    apply List.filter_eq_nil_iff.mpr
    intro a ha
    obtain ⟨i, rfl⟩ := List.mem_ofFn.mp ha
    simp only [ho, Option.isNone_some, Bool.false_eq_true, not_false_eq_true]
  have hout : collectOutputs layout.outputs s =
      (MatVec.adapter.outputScalars (MatVec.reference x)).toList := by
    change (List.ofFn outputAddress).filterMap (fun a => (s.readMemory a).map (fun v => (decodeSlot v).val)) =
      (vectorScalars (MatVec.reference x)).toList
    rw [filterMap_ofFn outputAddress _ (MatVec.reference x)]
    · simp only [vectorScalars, Vector.toList_ofFn]
    · intro i
      simp only [ho, Option.map_some, decode_encode_slot, resultValue]
  unfold finish
  simp only [hl, hm, List.isEmpty_nil, ↓reduceIte]
  exact ⟨_, rfl, hout, rfl⟩

/-- All-input execution of the exact serialized candidate, through the common
initializer, program sorting, runner, transition, and output collector. -/
theorem execution_correct (x : MatVec.Input) (hx : MatVec.AllowedInput x) :
    ∃ record, executeValues candidate (MatVec.adapter.encode x hx) 2144 false = .success record ∧
      record.outputs = (MatVec.adapter.outputScalars (MatVec.reference x)).toList ∧
      record.cycles = 2143 := by
  let initial := initialState C layout (MatVec.adapter.encode x hx)
  obtain ⟨final, hex, _, ho⟩ := rows_executes x hx initial (initial_quiet _) (initial_inputs x hx) 16 (by omega)
  obtain ⟨counts, hr⟩ := run_serial hex 0 0 [] (by intro a ha; cases ha) (Counters.empty C)
  have hrun : run false 2144 0 (program candidate) initial (Counters.empty C) [] =
      .finished ⟨2143, final, counts, []⟩ := by
    rw [candidate_program]
    have hr' : run false 2144 0 (timed 0 (rowsCode 16 (by omega))) initial (Counters.empty C) [] =
        run false 0 2144 [] final counts [] := by
      simpa only [rows_duration, Nat.mul_succ, Nat.mul_zero, Nat.zero_add, Nat.add_zero, List.append_nil] using hr
    rw [hr', run_finished false 0 2144 final counts [] (quiet_drained (executes_quiet hex))]
    rfl
  obtain ⟨record, hf, hout, ht⟩ := finish_correct x hx final counts (fun i => ho i i.isLt)
  refine ⟨record, ?_, hout, ht⟩
  unfold executeValues
  erw [hrun]
  exact hf

/-- The primary default-configuration certificate binds the exact artifact.
Other configurations are exercised as conformance simulations. -/
def verified : VerifiedCandidate MatVec.adapter where
  candidate := candidate
  sufficientBoundaries := 2144
  safety := by
    intro x hx
    obtain ⟨record, he, _, _⟩ := execution_correct x hx
    exact ⟨record, he⟩
  correctness := by
    intro x hx record he
    obtain ⟨expected, hh, ho, _⟩ := execution_correct x hx
    have hr : expected = record := ExecutionOutcome.success.inj (hh.symm.trans he)
    subst record
    exact ho

/-! ### `matvec-naive-v2` certificate

The row and initialization proofs above are timing-independent (`Executes`);
only the runner composition changes, to `Serial.run_tight_complete`. -/

theorem finish_correct_v2 (x : MatVec.Input) (hx : MatVec.AllowedInput x) (s : State C)
    (counts : Counters) (cycles : Nat)
    (ho : ∀ i, s.readMemory (outputAddress i) = some (encodeSlot (resultValue x hx i))) :
    ∃ record, finish candidateV2 ⟨cycles, s, counts, []⟩ = .success record ∧
      record.outputs = (MatVec.adapter.outputScalars (MatVec.reference x)).toList ∧
      record.cycles = cycles := by
  have hl : candidateV2.layout = layout := rfl
  have hm : (layout.outputs.filter (fun a => (s.readMemory a).isNone)) = [] := by
    apply List.filter_eq_nil_iff.mpr
    intro a ha
    obtain ⟨i, rfl⟩ := List.mem_ofFn.mp ha
    simp only [ho, Option.isNone_some, Bool.false_eq_true, not_false_eq_true]
  have hout : collectOutputs layout.outputs s =
      (MatVec.adapter.outputScalars (MatVec.reference x)).toList := by
    change (List.ofFn outputAddress).filterMap (fun a => (s.readMemory a).map (fun v => (decodeSlot v).val)) =
      (vectorScalars (MatVec.reference x)).toList
    rw [filterMap_ofFn outputAddress _ (MatVec.reference x)]
    · simp only [vectorScalars, Vector.toList_ofFn]
    · intro i
      simp only [ho, Option.map_some, decode_encode_slot, resultValue]
  unfold finish
  simp only [hl, hm, List.isEmpty_nil, ↓reduceIte]
  exact ⟨_, rfl, hout, rfl⟩

/-- All-input execution of the exact v2 artifact: 1,344 elapsed cycles. -/
theorem execution_correct_v2 (x : MatVec.Input) (hx : MatVec.AllowedInput x) :
    ∃ record, executeValues candidateV2 (MatVec.adapter.encode x hx) 1345 false = .success record ∧
      record.outputs = (MatVec.adapter.outputScalars (MatVec.reference x)).toList ∧
      record.cycles = 1344 := by
  let initial := initialState C layout (MatVec.adapter.encode x hx)
  obtain ⟨final, hex, _, ho⟩ := rows_executes x hx initial (initial_quiet _) (initial_inputs x hx) 16 (by omega)
  obtain ⟨counts, hr⟩ := run_tight_complete hex 1344 (rows_tightDuration 16 (by omega)) (by decide)
  have hrun : run false 1345 0 (program candidateV2) initial (Counters.empty C) [] =
      .finished ⟨1344, final, counts, []⟩ := by
    rw [candidateV2_program]
    exact hr
  obtain ⟨record, hf, hout, ht⟩ := finish_correct_v2 x hx final counts 1344 (fun i => ho i i.isLt)
  refine ⟨record, ?_, hout, ht⟩
  unfold executeValues
  erw [hrun]
  exact hf

def verifiedV2 : VerifiedCandidate MatVec.adapter where
  candidate := candidateV2
  sufficientBoundaries := 1345
  safety := by
    intro x hx
    obtain ⟨record, he, _, _⟩ := execution_correct_v2 x hx
    exact ⟨record, he⟩
  correctness := by
    intro x hx record he
    obtain ⟨expected, hh, ho, _⟩ := execution_correct_v2 x hx
    have hr : expected = record := ExecutionOutcome.success.inj (hh.symm.trans he)
    subst record
    exact ho

end OptimalComputation.Examples.MatVecNaive
