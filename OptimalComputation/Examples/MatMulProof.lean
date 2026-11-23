import OptimalComputation.Examples.MatMulNaive
import OptimalComputation.Evaluation.Initialization

namespace OptimalComputation.Examples.MatMulNaive
open Hardware Workloads Candidates Evaluation Evaluation.Serial
set_option backward.isDefEq.respectTransparency false
set_option maxRecDepth 10000
variable {c : ValidConfig}

/-- Memory invariant at output-entry boundaries: all runtime inputs remain unchanged. -/
def Inputs (x : MatMul.Input) (hx : MatMul.AllowedInput x) (s : State c) : Prop :=
  (∀ i j, s.readMemory (leftAddress i j) =
    some (encodeSlot ⟨x.left i j, signed16_fits_signed48 (hx.1 i j)⟩)) ∧
  (∀ i j, s.readMemory (rightAddress i j) =
    some (encodeSlot ⟨x.right i j, signed16_fits_signed48 (hx.2 i j)⟩))

def resultValue (x : MatMul.Input) (hx : MatMul.AllowedInput x) (i : Fin 256) : Signed48 :=
  ⟨MatMul.reference x (entryRow i) (entryColumn i), MatMul.reference_fits_signed48 x hx (entryRow i) (entryColumn i)⟩

theorem entry_executes (x : MatMul.Input) (hx : MatMul.AllowedInput x)
    (i : Fin 256) (s : State c) (hs : Quiet s) (hi : Inputs x hx s) :
    ∃ final, Executes (entryCode i) s final ∧
      final.memory = (s.writeMemory (outputAddress i) (encodeSlot (resultValue x hx i))).memory := by
  let reset := s.writeRegister lane acc zero48
  have hr : Executes [.add acc r0 r0] s reset :=
    .cons _ _ _ _ (.register acc zero48) hs (fun t => prepare_reset t s hs) (.nil reset hs)
  have hm : Inputs x hx reset := hi
  obtain ⟨middle, hd, hmem, hv⟩ := SerialDot.executes_prefix (x.left (entryRow i)) (fun k => x.right k (entryColumn i))
    (hx.1 (entryRow i)) (fun k => hx.2 k (entryColumn i))
    (leftAddress (entryRow i)) (fun k => rightAddress k (entryColumn i)) reset hs
    (hm.1 (entryRow i)) (fun k => hm.2 k (entryColumn i))
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

theorem output_ne_input (i : Fin 256) (j : Fin 512) : outputAddress i ≠ inputAddress j := by
  intro h
  have he := congrArg Fin.val h
  simp only [outputAddress, inputAddress] at he
  have := j.isLt
  omega

theorem output_injective (i j : Fin 256) : outputAddress i = outputAddress j ↔ i = j := by
  constructor
  · intro h; apply Fin.ext; have := congrArg Fin.val h; simp only [outputAddress] at this; omega
  · intro h; subst j; rfl

theorem entry_inputs (x : MatMul.Input) (hx : MatMul.AllowedInput x) (i : Fin 256)
    (s final : State c) (hi : Inputs x hx s)
    (hm : final.memory = (s.writeMemory (outputAddress i) (encodeSlot (resultValue x hx i))).memory) :
    Inputs x hx final := by
  constructor
  · intro r k
    change final.memory[_] = _
    rw [hm]
    change (s.writeMemory _ _).readMemory (leftAddress r k) = _
    rw [State.readMemory_write_other s _ (leftAddress r k) _ (output_ne_input i _)]
    exact hi.1 r k
  · intro r k
    change final.memory[_] = _
    rw [hm]
    change (s.writeMemory _ _).readMemory (rightAddress r k) = _
    rw [State.readMemory_write_other s _ (rightAddress r k) _ (output_ne_input i _)]
    exact hi.2 r k

/-- Entry induction composes the same dot-product theorem 256 times. Output
slots before the current entry are preserved, and every input remains read-only. -/
theorem entries_executes (x : MatMul.Input) (hx : MatMul.AllowedInput x)
    (s : State c) (hs : Quiet s) (hi : Inputs x hx s) (n : Nat) (hn : n ≤ 256) :
    ∃ final, Executes (entriesCode n hn) s final ∧ Inputs x hx final ∧
      ∀ i : Fin 256, i.val < n →
        final.readMemory (outputAddress i) = some (encodeSlot (resultValue x hx i)) := by
  induction n with
  | zero => exact ⟨s, .nil s hs, hi, by intro i h; omega⟩
  | succ n ih =>
    obtain ⟨middle, he, hi, ho⟩ := ih (by omega)
    let i : Fin 256 := ⟨n, by omega⟩
    obtain ⟨final, hr, hm⟩ := entry_executes x hx i middle (executes_quiet he) hi
    refine ⟨final, executes_append he hr, entry_inputs x hx i middle final hi hm, ?_⟩
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


theorem initialization_pairs (values : Vector Signed48 512) :
    layout.inputs.zip values.toList = List.ofFn (fun i : Fin 512 => (inputAddress i, values[i.val])) := by
  change (List.ofFn inputAddress).zip values.toList = _
  apply List.ext_getElem
  · simp only [List.length_zip, List.length_ofFn, Vector.length_toList, Nat.min_self]
  · intro k hk hk'
    simp only [List.getElem_zip, List.getElem_ofFn, Vector.getElem_toList]

theorem initial_read (values : Vector Signed48 512) (i : Fin 512) :
    (initialState c layout values).readMemory (inputAddress i) = some (encodeSlot values[i.val]) := by
  change (writeValues (State.empty c) (layout.inputs.zip values.toList)).readMemory _ = _
  rw [initialization_pairs]
  apply writeValues_read
  · exact List.mem_ofFn.mpr ⟨i, rfl⟩
  · intro p hp he
    obtain ⟨j, rfl⟩ := List.mem_ofFn.mp hp
    have hij : j = i := Fin.ext (congrArg (fun a : Address => a.val) he)
    subst j
    rfl

theorem initial_quiet (values : Vector Signed48 512) : Quiet (initialState c layout values) := by
  change (writeValues (State.empty c) (layout.inputs.zip values.toList)).pending = _
  rw [writeValues_pending]
  rfl

theorem encode_left (x : MatMul.Input) (hx : MatMul.AllowedInput x) (i j : Index16) :
    (MatMul.adapter.encode x hx)[i.val * 16 + j.val]'(by change _ < 512; omega) =
      (⟨x.left i j, signed16_fits_signed48 (hx.1 i j)⟩ : Signed48) := by
  apply Subtype.ext
  simp only [ScalarAdapter.encode, Vector.getElem_ofFn, MatMul.adapter, MatMul.scalarInput]
  change ((matrixScalars x.left) ++ (matrixScalars x.right))[(matrixIndex i j).val] = _
  rw [Vector.getElem_append_left (by have := (matrixIndex i j).isLt; exact this)]
  exact matrixScalars_at x.left i j

theorem encode_right (x : MatMul.Input) (hx : MatMul.AllowedInput x) (i j : Index16) :
    (MatMul.adapter.encode x hx)[256 + i.val * 16 + j.val]'(by change _ < 512; omega) =
      (⟨x.right i j, signed16_fits_signed48 (hx.2 i j)⟩ : Signed48) := by
  apply Subtype.ext
  simp only [ScalarAdapter.encode, Vector.getElem_ofFn, MatMul.adapter, MatMul.scalarInput]
  change ((matrixScalars x.left) ++ (matrixScalars x.right))[256 + i.val * 16 + j.val] = _
  rw [Vector.getElem_append_right (by omega) (by omega)]
  have h : 256 + i.val * 16 + j.val - 256 = (matrixIndex i j).val := by
    simp only [matrixIndex]; omega
  simpa only [h] using matrixScalars_at x.right i j

theorem initial_inputs (x : MatMul.Input) (hx : MatMul.AllowedInput x) :
    Inputs x hx (initialState c layout (MatMul.adapter.encode x hx)) := by
  constructor
  · intro i j
    change (initialState c layout _).readMemory (inputAddress _) = _
    rw [initial_read]
    exact congrArg (fun v => some (encodeSlot v)) (encode_left x hx i j)
  · intro i j
    change (initialState c layout _).readMemory (inputAddress _) = _
    rw [initial_read]
    exact congrArg (fun v => some (encodeSlot v)) (encode_right x hx i j)


theorem filterMap_ofFn {n : Nat} (f : Fin n → α) (g : α → Option β) (v : Fin n → β)
    (h : ∀ i, g (f i) = some (v i)) : (List.ofFn f).filterMap g = List.ofFn v := by
  have hf : List.ofFn f = (List.finRange n).map f := by
    simp only [List.finRange, List.map_ofFn, Function.comp_def]
  rw [hf, List.filterMap_map]
  simp only [Function.comp_def, h, List.filterMap_eq_map', List.finRange, List.map_ofFn]

theorem finish_correct (x : MatMul.Input) (hx : MatMul.AllowedInput x) (s : State C)
    (counts : Counters)
    (ho : ∀ i, s.readMemory (outputAddress i) = some (encodeSlot (resultValue x hx i))) :
    ∃ record, finish candidate ⟨34303, s, counts, []⟩ = .success record ∧
      record.outputs = (MatMul.adapter.outputScalars (MatMul.reference x)).toList ∧
      record.cycles = 34303 := by
  have hl : candidate.layout = layout := rfl
  have hm : (layout.outputs.filter (fun a => (s.readMemory a).isNone)) = [] := by
    apply List.filter_eq_nil_iff.mpr
    intro a ha
    obtain ⟨i, rfl⟩ := List.mem_ofFn.mp ha
    simp only [ho, Option.isNone_some, Bool.false_eq_true, not_false_eq_true]
  have hout : collectOutputs layout.outputs s =
      (MatMul.adapter.outputScalars (MatMul.reference x)).toList := by
    change (List.ofFn outputAddress).filterMap (fun a => (s.readMemory a).map (fun v => (decodeSlot v).val)) =
      (matrixScalars (MatMul.reference x)).toList
    rw [filterMap_ofFn outputAddress _ (fun i => MatMul.reference x (entryRow i) (entryColumn i))]
    · simp only [matrixScalars, Vector.toList_ofFn, entryRow, entryColumn]
    · intro i
      simp only [ho, Option.map_some, decode_encode_slot, resultValue]
  unfold finish
  simp only [hl, hm, List.isEmpty_nil, ↓reduceIte]
  exact ⟨_, rfl, hout, rfl⟩

/-- Abstract the finite program before composing the runner. This keeps the
kernel proof independent of the size of the expanded matrix schedule. -/
theorem run_complete {instructions : List BoundedInstruction} {s final : State c}
    (hex : Executes instructions s final) (ticks : Nat) (ht : duration instructions = ticks) :
    ∃ counts, run false ticks 0 (timed 0 instructions) s (Counters.empty c) [] =
      .finished ⟨ticks - 1, final, counts, []⟩ := by
  obtain ⟨counts, hr⟩ := run_serial hex 0 0 [] (by intro a ha; cases ha) (Counters.empty c)
  refine ⟨counts, ?_⟩
  have hr' : run false ticks 0 (timed 0 instructions) s (Counters.empty c) [] =
      run false 0 ticks [] final counts [] := by
    simpa only [ht, Nat.zero_add, Nat.add_zero, List.append_nil] using hr
  rw [hr', run_finished false 0 ticks final counts [] (quiet_drained (executes_quiet hex))]
  rfl

theorem execute_of_finished (p : Candidate shape) (values : Vector Signed48 shape.inputCount)
    (fuel : Nat) (result : RunResult p.configuration) (record : ExecutionRecord)
    (hr : run false fuel 0 (program p) (initialState p.configuration p.layout values)
      (Counters.empty p.configuration) [] = .finished result)
    (hf : finish p result = .success record) :
    executeValues p values fuel false = .success record := by
  unfold executeValues
  rw [hr]
  exact hf

/-- All-input execution of the exact serialized candidate, through the common
initializer, program sorting, runner, transition, and output collector. -/
theorem execution_correct (x : MatMul.Input) (hx : MatMul.AllowedInput x) :
    ∃ record, executeValues candidate (MatMul.adapter.encode x hx) 34304 false = .success record ∧
      record.outputs = (MatMul.adapter.outputScalars (MatMul.reference x)).toList ∧
      record.cycles = 34303 := by
  let initial := initialState C layout (MatMul.adapter.encode x hx)
  obtain ⟨final, hex, _, ho⟩ := entries_executes x hx initial (initial_quiet _) (initial_inputs x hx) 256 (by omega)
  obtain ⟨counts, hr⟩ := run_complete hex 34304 (entries_duration 256 (by omega))
  have hrun : run false 34304 0 (program candidate) initial (Counters.empty C) [] =
      .finished ⟨34303, final, counts, []⟩ := by
    rw [candidate_program]
    exact hr
  obtain ⟨record, hf, hout, ht⟩ := finish_correct x hx final counts (fun i => ho i i.isLt)
  refine ⟨record, ?_, hout, ht⟩
  exact execute_of_finished candidate _ _ _ _ hrun hf

/-- The primary default-configuration certificate binds the exact artifact.
Other configurations are exercised as conformance simulations. -/
def verified : VerifiedCandidate MatMul.adapter where
  candidate := candidate
  sufficientBoundaries := 34304
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

/-! ### `matmul-naive-v2` certificate

The entry and initialization proofs above are timing-independent (`Executes`);
only the runner composition changes, to `Serial.run_tight_complete`. -/

theorem finish_correct_v2_for (c : ValidConfig) (x : MatMul.Input) (hx : MatMul.AllowedInput x) (s : State c)
    (counts : Counters) (cycles : Nat)
    (ho : ∀ i, s.readMemory (outputAddress i) = some (encodeSlot (resultValue x hx i))) :
    ∃ record, finish (candidateV2For c) ⟨cycles, s, counts, []⟩ = .success record ∧
      record.outputs = (MatMul.adapter.outputScalars (MatMul.reference x)).toList ∧
      record.cycles = cycles := by
  have hl : (candidateV2For c).layout = layout := rfl
  have hm : (layout.outputs.filter (fun a => (s.readMemory a).isNone)) = [] := by
    apply List.filter_eq_nil_iff.mpr
    intro a ha
    obtain ⟨i, rfl⟩ := List.mem_ofFn.mp ha
    simp only [ho, Option.isNone_some, Bool.false_eq_true, not_false_eq_true]
  have hout : collectOutputs layout.outputs s =
      (MatMul.adapter.outputScalars (MatMul.reference x)).toList := by
    change (List.ofFn outputAddress).filterMap (fun a => (s.readMemory a).map (fun v => (decodeSlot v).val)) =
      (matrixScalars (MatMul.reference x)).toList
    rw [filterMap_ofFn outputAddress _ (fun i => MatMul.reference x (entryRow i) (entryColumn i))]
    · simp only [matrixScalars, Vector.toList_ofFn, entryRow, entryColumn]
    · intro i
      simp only [ho, Option.map_some, decode_encode_slot, resultValue]
  unfold finish
  simp only [hl, hm, List.isEmpty_nil, ↓reduceIte]
  exact ⟨_, rfl, hout, rfl⟩

/-- All-input execution of the exact v2 artifact: 21,504 elapsed cycles. -/
theorem execution_correct_v2_for (c : ValidConfig) (x : MatMul.Input) (hx : MatMul.AllowedInput x) :
    ∃ record, executeValues (candidateV2For c) (MatMul.adapter.encode x hx) 21505 false = .success record ∧
      record.outputs = (MatMul.adapter.outputScalars (MatMul.reference x)).toList ∧
      record.cycles = 21504 := by
  let initial := initialState c layout (MatMul.adapter.encode x hx)
  obtain ⟨final, hex, _, ho⟩ := entries_executes x hx initial (initial_quiet _) (initial_inputs x hx) 256 (by omega)
  obtain ⟨counts, hr⟩ := run_tight_complete hex 21504 (entries_tightDuration 256 (by omega)) (by decide)
  have hrun : run false 21505 0 (program (candidateV2For c)) initial (Counters.empty c) [] =
      .finished ⟨21504, final, counts, []⟩ := by
    rw [candidateV2For_program]
    exact hr
  obtain ⟨record, hf, hout, ht⟩ := finish_correct_v2_for c x hx final counts 21504 (fun i => ho i i.isLt)
  refine ⟨record, ?_, hout, ht⟩
  exact execute_of_finished (candidateV2For c) _ _ _ _ hrun hf

theorem finish_correct_v2 (x : MatMul.Input) (hx : MatMul.AllowedInput x) (s : State C)
    (counts : Counters) (cycles : Nat)
    (ho : ∀ i, s.readMemory (outputAddress i) = some (encodeSlot (resultValue x hx i))) :
    ∃ record, finish candidateV2 ⟨cycles, s, counts, []⟩ = .success record ∧
      record.outputs = (MatMul.adapter.outputScalars (MatMul.reference x)).toList ∧
      record.cycles = cycles :=
  finish_correct_v2_for C x hx s counts cycles ho

theorem execution_correct_v2 (x : MatMul.Input) (hx : MatMul.AllowedInput x) :
    ∃ record, executeValues candidateV2 (MatMul.adapter.encode x hx) 21505 false = .success record ∧
      record.outputs = (MatMul.adapter.outputScalars (MatMul.reference x)).toList ∧
      record.cycles = 21504 :=
  execution_correct_v2_for C x hx

def verifiedV2 : VerifiedCandidate MatMul.adapter where
  candidate := candidateV2
  sufficientBoundaries := 21505
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

def verifiedV2For (c : ValidConfig) : VerifiedCandidate MatMul.adapter where
  candidate := candidateV2For c
  sufficientBoundaries := 21505
  safety := by
    intro x hx
    obtain ⟨record, he, _, _⟩ := execution_correct_v2_for c x hx
    exact ⟨record, he⟩
  correctness := by
    intro x hx record he
    obtain ⟨expected, hh, ho, _⟩ := execution_correct_v2_for c x hx
    have hr : expected = record := ExecutionOutcome.success.inj (hh.symm.trans he)
    subst record
    exact ho

end OptimalComputation.Examples.MatMulNaive
