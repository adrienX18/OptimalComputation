import OptimalComputation.Evaluation.Verification

/-! Compositional execution facts for deliberately serialized schedules. The
proofs below use the public cycle transition and runner; they introduce no
alternative executor. An instruction owns its issue through completion boundary. -/
set_option linter.unusedSimpArgs false
set_option backward.isDefEq.respectTransparency false
namespace OptimalComputation.Evaluation.Serial
open Hardware Candidates Workloads

abbrev C := defaultConfig

def lane : Lane C := ⟨0, by decide⟩
def r0 : Register := ⟨0, by decide⟩
def r1 : WritableRegister := ⟨⟨1, by decide⟩, by decide⟩
def r2 : WritableRegister := ⟨⟨2, by decide⟩, by decide⟩
def acc : WritableRegister := ⟨⟨3, by decide⟩, by decide⟩

def Quiet (s : State C) : Prop := s.pending = Vector.replicate 8 []

def waitState (s : State C) (due : Nat) (e : Effect) : State C :=
  s.setPending lane [⟨due, e⟩]

@[simp] theorem quiet_empty : Quiet (State.empty C) := rfl
@[simp] theorem quiet_writeMemory (s : State C) (a : Address) (v : Slot64) :
    Quiet (s.writeMemory a v) ↔ Quiet s := Iff.rfl
@[simp] theorem quiet_writeRegister (s : State C) (r : WritableRegister) (v : Signed48) :
    Quiet (s.writeRegister lane r v) ↔ Quiet s := Iff.rfl
@[simp] theorem quiet_effect (s : State C) (e : Effect) :
    Quiet (applyEffect s lane e) ↔ Quiet s := by cases e <;> rfl

theorem quiet_drained {s : State C} (h : Quiet s) : s.drained = true := by
  change s.pending = _ at h
  simp +instances [State.drained, h, Vector.toList]

theorem setPending_unchanged (s : State c) (l : Lane c)
    (ps : List PendingEffect) (h : s.pending[l.val] = ps) : s.setPending l ps = s := by
  have hv : s.pending.set l.val ps l.isLt = s.pending := by
    apply Vector.ext
    intro i hi
    by_cases he : i = l.val
    · subst i; simp [h]
    · simp [he, Ne.symm he]
  cases s
  simp_all [State.setPending]

set_option maxRecDepth 10000 in
set_option maxHeartbeats 2000000 in
theorem commit_quiet (t : Nat) (s : State C) (h : Quiet s) :
    commit t s = .ok (s, []) := by
  rcases s with ⟨rs, mem, pending⟩
  change pending = _ at h
  subst pending
  simp +instances [commit, State.setPending, C, defaultConfig, List.finRange, Fin.ofNat,
    List.forIn_cons, List.forIn_nil, bind, pure, Except.bind, Except.pure,
    resultWritesPerLanePerCycle, setPending_unchanged]

set_option maxRecDepth 10000 in
set_option maxHeartbeats 2000000 in
theorem commit_wait_before (t due : Nat) (s : State C) (h : Quiet s) (e : Effect)
    (ht : t < due) : commit t (waitState s due e) = .ok (waitState s due e, []) := by
  rcases s with ⟨rs, mem, pending⟩
  change pending = _ at h
  subst pending
  have hne : due ≠ t := by omega
  have hnot : ¬due < t := by omega
  simp +instances [commit, waitState, State.setPending, lane, C, defaultConfig,
    List.finRange, Fin.ofNat, List.forIn_cons, List.forIn_nil, bind, pure, Except.bind, Except.pure,
    resultWritesPerLanePerCycle, hne, hnot]
  rfl

set_option maxRecDepth 10000 in
set_option maxHeartbeats 2000000 in
theorem commit_wait_due (due : Nat) (s : State C) (h : Quiet s) (e : Effect) :
    commit due (waitState s due e) = .ok (applyEffect s lane e, [.committed due 0 e]) := by
  rcases s with ⟨rs, mem, pending⟩
  change pending = _ at h
  subst pending
  cases e <;>
    simp +instances [commit, waitState, State.setPending, State.writeRegister,
      State.writeMemory, applyEffect, lane, C, defaultConfig, Effect.destination,
      List.finRange, Fin.ofNat, List.forIn_cons, List.forIn_nil, bind, pure, Except.bind, Except.pure,
      resultWritesPerLanePerCycle] <;> rfl

@[simp] theorem filter_singleton_not_gt_one (p : α → Bool) (x : α) :
    ¬1 < ([x].filter p).length := by
  have := List.length_filter_le p [x]
  simp only [List.length_singleton] at this
  omega

@[simp] theorem filter_singleton_not_gt_two (p : α → Bool) (x : α) :
    ¬2 < ([x].filter p).length := by
  have := List.length_filter_le p [x]
  simp only [List.length_singleton] at this
  omega

set_option maxHeartbeats 2000000 in
theorem checkBatch_single (t : Nat) (i : BoundedInstruction) :
    checkBatch t [⟨lane, i⟩] = .ok () := by
  cases i <;>
    simp +instances [checkBatch, lane, C, defaultConfig, List.finRange, Fin.ofNat,
      List.forIn_cons, List.forIn_nil, bind, pure, Except.bind, Except.pure,
      instructionsPerLanePerCycle, bankPorts, Instruction.memoryAccess, bankOf]


set_option maxHeartbeats 2000000 in
theorem checkBatch_empty (t : Nat) : checkBatch (c := C) t [] = .ok () := by
  simp +instances [checkBatch, lane, C, defaultConfig, List.finRange, Fin.ofNat,
      List.forIn_cons, List.forIn_nil, bind, pure, Except.bind, Except.pure,
      instructionsPerLanePerCycle, bankPorts]


theorem activity_quiet (s : State C) (h : Quiet s) (t : Nat) :
    (List.finRange C.val.lanes).filterMap (fun l =>
      if (s.pending[l.val]).isEmpty then none else some (Event.active t l.val)) = [] := by
  change s.pending = _ at h
  simp +instances [h, C, defaultConfig, List.finRange, Fin.ofNat]

theorem activity_wait (s : State C) (h : Quiet s) (t due : Nat) (e : Effect) :
    (List.finRange C.val.lanes).filterMap (fun l =>
      if ((waitState s due e).pending[l.val]).isEmpty then none else some (Event.active t l.val)) =
      [.active t 0] := by
  change s.pending = _ at h
  simp +instances [waitState, State.setPending, h, lane, C, defaultConfig, List.finRange, Fin.ofNat]
  exact ⟨rfl, rfl, rfl, rfl, rfl⟩

theorem step_issue (s : State C) (h : Quiet s) (t : Nat) (i : BoundedInstruction) (e : Effect)
    (hp : prepare t s ⟨lane, i⟩ = .ok ⟨t + latency i, e⟩) :
    step t [⟨lane, i⟩] s = .ok (waitState s (t + latency i) e,
      [.issued t 0 i.toRaw (t + latency i), .active t 0]) := by
  have he : enqueue s [(⟨lane, i⟩, ⟨t + latency i, e⟩)] = waitState s (t + latency i) e := by
    change s.pending = _ at h
    simp +instances [C, defaultConfig, enqueue, List.foldl_cons, List.foldl_nil, waitState, h, lane]
  simp only [step, commit_quiet t s h, canonicalActions, List.mergeSort_singleton, checkBatch_single, hp,
    List.mapM_cons, List.mapM_nil, bind, pure, Except.bind, Except.pure, he, List.map_cons, List.map_nil, List.nil_append, List.cons_append, activity_wait s h]
  rfl

theorem step_wait_before (s : State C) (h : Quiet s) (t due : Nat) (e : Effect) (ht : t < due) :
    step t [] (waitState s due e) = .ok (waitState s due e, [.active t 0]) := by
  simp only [step, commit_wait_before t due s h e ht, canonicalActions, List.mergeSort_nil, checkBatch_empty,
    List.mapM_nil, bind, pure, Except.bind, Except.pure, enqueue, List.foldl_nil, List.map_nil, List.nil_append]
  rw [activity_wait s h]

theorem step_wait_due (s : State C) (h : Quiet s) (due : Nat) (e : Effect) :
    step due [] (waitState s due e) = .ok (applyEffect s lane e, [.committed due 0 e]) := by
  simp only [step, commit_wait_due due s h e, canonicalActions, List.mergeSort_nil, checkBatch_empty,
    List.mapM_nil, bind, pure, Except.bind, Except.pure, enqueue,
    List.foldl_nil, List.map_nil]
  rw [activity_quiet _ ((quiet_effect s e).mpr h), List.append_nil, List.append_nil]

theorem prepare_load (t : Nat) (s : State C) (h : Quiet s) (d : WritableRegister)
    (a : Address) (v : Signed48) (hv : s.readMemory a = some (encodeSlot v)) :
    prepare t s ⟨lane, .load d a⟩ = .ok ⟨t + 1, .register d v⟩ := by
  change s.pending = _ at h
  have hl : (Vector.replicate 8 ([] : List PendingEffect))[lane.val] = [] := rfl
  simp +instances [C, defaultConfig, prepare, hl, checkReservation, registerPending, h, hv, latency,
    Instruction.destination, pendingInstructionsPerLane, bind, pure, Except.bind, Except.pure]

theorem prepare_store (t : Nat) (s : State C) (h : Quiet s) (r : Register)
    (a : Address) (v : Signed48) (hv : s.readRegister lane r = some v) :
    prepare t s ⟨lane, .store r a⟩ = .ok ⟨t + 1, .memory a (encodeSlot v)⟩ := by
  change s.pending = _ at h
  have hl : (Vector.replicate 8 ([] : List PendingEffect))[lane.val] = [] := rfl
  simp +instances [C, defaultConfig, prepare, hl, checkReservation, readReady, registerPending, h, hv, latency,
    Instruction.destination, pendingInstructionsPerLane, bind, pure, Except.bind, Except.pure]

theorem prepare_reset (t : Nat) (s : State C) (h : Quiet s) :
    prepare t s ⟨lane, .add acc r0 r0⟩ = .ok ⟨t + 3, .register acc zero48⟩ := by
  change s.pending = _ at h
  have hl : (Vector.replicate 8 ([] : List PendingEffect))[lane.val] = [] := rfl
  simp +instances [C, defaultConfig, prepare, hl, checkReservation, readReady, registerPending, h, lane, latency,
    Instruction.destination, pendingInstructionsPerLane, bind, pure, Except.bind, Except.pure,
    r0, zero48, checkedAdd, checkedResult, State.readRegister, InSigned48, signed48Min, signed48Max,
    Except.mapError]

theorem prepare_mac (t : Nat) (s : State C) (h : Quiet s) (a b v next : Signed48)
    (ha : s.readRegister lane r1.val = some a) (hb : s.readRegister lane r2.val = some b)
    (hv : s.readRegister lane acc.val = some v)
    (hc : checkedMac a.val b.val v.val = .ok next) :
    prepare t s ⟨lane, .multiplyAdd acc r1.val r2.val acc.val⟩ =
      .ok ⟨t + 3, .register acc next⟩ := by
  change s.pending = _ at h
  have hl : (Vector.replicate 8 ([] : List PendingEffect))[lane.val] = [] := rfl
  simp +instances [C, defaultConfig, prepare, hl, checkReservation, readReady, registerPending, h, ha, hb, hv, hc, latency,
    Instruction.destination, pendingInstructionsPerLane, bind, pure, Except.bind, Except.pure,
    Except.mapError]


def After (t : Nat) (q : List (TimedAction C)) : Prop := ∀ a ∈ q, t ≤ a.cycle

theorem span_after {t b : Nat} {q : List (TimedAction C)} (h : After t q) (hb : b < t) :
    q.span (fun a => a.cycle == b) = ([], q) := by
  cases q with
  | nil => rfl
  | cons a q =>
    have ha := h a (by simp)
    have hn : a.cycle ≠ b := by omega
    have he : (a.cycle == b) = false := beq_eq_false_iff_ne.mpr hn
    simp [List.span, List.span.loop, he]

theorem span_head {t : Nat} {q : List (TimedAction C)} (a : Action C)
    (h : After (t + 1) q) :
    ((⟨t, a⟩ : TimedAction C) :: q).span (fun a => a.cycle == t) = ([⟨t, a⟩], q) := by
  have hs := span_after h (by omega : t < t + 1)
  cases q with
  | nil => simp [List.span, List.span.loop]
  | cons b q =>
    have hb := h b (by simp)
    have hn : b.cycle ≠ t := by omega
    have he : (b.cycle == t) = false := beq_eq_false_iff_ne.mpr hn
    simp [List.span, List.span.loop, he]

theorem wait_not_drained (s : State C) (h : Quiet s) (due : Nat) (e : Effect) :
    (waitState s due e).drained = false := by
  change s.pending = _ at h
  simp +instances [State.drained, waitState, State.setPending, lane, h,
    C, defaultConfig, Vector.toList]

theorem run_primitive (t fuel : Nat) (q : List (TimedAction C)) (s : State C)
    (h : Quiet s) (i : BoundedInstruction) (e : Effect) (counts : Counters)
    (hp : prepare t s ⟨lane, i⟩ = .ok ⟨t + latency i, e⟩)
    (hq : After (t + latency i + 1) q) :
    ∃ counts',
      run false (latency i + 1 + fuel) t (⟨t, ⟨lane, i⟩⟩ :: q) s counts [] =
      run false fuel (t + latency i + 1) q (applyEffect s lane e) counts' [] := by
  have hl : latency i = 1 ∨ latency i = 3 := by cases i <;> simp [latency]
  have hs := step_issue s h t i e hp
  have hi : After (t + 1) q := by intro a ha; have := hq a ha; omega
  have hn : ((⟨t, ⟨lane, i⟩⟩ :: q : List (TimedAction C)).isEmpty && s.drained) = false := rfl
  have hw : (q.isEmpty && (waitState s (t + latency i) e).drained) = false := by
    rw [wait_not_drained s h]; simp
  rcases hl with hl | hl
  · have hsp := span_after hq (by omega : t + 1 < t + latency i + 1)
    have hd := step_wait_due s h (t + 1) e
    rw [show latency i + 1 + fuel = (fuel + 1) + 1 by omega,
      run_step false (fuel + 1) t _ [⟨t, ⟨lane, i⟩⟩] q s _ counts [] _ hn
        (span_head _ hi) hs]
    simp only [Bool.false_eq_true, ↓reduceIte]
    rw [run_step false fuel (t + 1) q [] q _ _ _ [] _ hw
      hsp (by simpa [hl] using hd)]
    simp only [Bool.false_eq_true, ↓reduceIte]
    refine ⟨[Event.issued t 0 i.toRaw (t + 1), .active t 0,
      .committed (t + 1) 0 e].foldl (Counters.record C) counts, ?_⟩
    simp only [hl]
    rfl
  · have hsp1 := span_after hq (by omega : t + 1 < t + latency i + 1)
    have hsp2 := span_after hq (by omega : t + 1 + 1 < t + latency i + 1)
    have hsp3 := span_after hq (by omega : t + 1 + 1 + 1 < t + latency i + 1)
    rw [show latency i + 1 + fuel = ((fuel + 1) + 1 + 1) + 1 by omega,
      run_step false (fuel + 1 + 1 + 1) t _ [⟨t, ⟨lane, i⟩⟩] q s _ counts [] _ hn
        (span_head _ hi) hs]
    simp only [Bool.false_eq_true, ↓reduceIte]
    rw [run_step false (fuel + 1 + 1) (t + 1) q [] q _ _ _ [] _ hw hsp1
      (step_wait_before s h _ _ e (by omega))]
    simp only [Bool.false_eq_true, ↓reduceIte]
    rw [run_step false (fuel + 1) (t + 1 + 1) q [] q _ _ _ [] _ hw hsp2
      (step_wait_before s h _ _ e (by omega))]
    simp only [Bool.false_eq_true, ↓reduceIte]
    rw [run_step false fuel (t + 1 + 1 + 1) q [] q _ _ _ [] _ hw hsp3
      (by simpa [hl, Nat.add_assoc] using step_wait_due s h (t + 3) e)]
    simp only [Bool.false_eq_true, ↓reduceIte]
    refine ⟨[Event.issued t 0 i.toRaw (t + 3), .active t 0, .active (t + 1) 0,
      .active (t + 2) 0, .committed (t + 3) 0 e].foldl (Counters.record C) counts, ?_⟩
    simp only [hl, Nat.add_assoc]
    rfl

/-- A proof relation for serial instruction lists. Each head premise is a fact
about the actual issue-time checker, with its actual captured effect. -/
inductive Executes : List BoundedInstruction → State C → State C → Prop
  | nil (s : State C) (quiet : Quiet s) : Executes [] s s
  | cons (i : BoundedInstruction) (is : List BoundedInstruction) (s final : State C) (e : Effect)
      (quiet : Quiet s)
      (prepare_ok : ∀ t, prepare t s ⟨lane, i⟩ = .ok ⟨t + latency i, e⟩)
      (tail : Executes is (applyEffect s lane e) final) : Executes (i :: is) s final

def duration : List BoundedInstruction → Nat
  | [] => 0
  | i :: is => latency i + 1 + duration is

def timed (t : Nat) : List BoundedInstruction → List (TimedAction C)
  | [] => []
  | i :: is => ⟨t, ⟨lane, i⟩⟩ :: timed (t + latency i + 1) is

theorem timed_after (t : Nat) (is : List BoundedInstruction) : After t (timed t is) := by
  induction is generalizing t with
  | nil => simp [After, timed]
  | cons i is ih =>
    intro a ha
    simp only [timed, List.mem_cons] at ha
    rcases ha with rfl | ha
    · exact Nat.le_refl _
    · have := ih (t + latency i + 1) a ha; omega

theorem executes_quiet {is : List BoundedInstruction} {s final : State C}
    (h : Executes is s final) : Quiet final := by
  induction h with
  | nil _ h => exact h
  | cons _ _ _ _ _ _ _ _ ih => exact ih

theorem run_serial {is : List BoundedInstruction} {s final : State C}
    (hex : Executes is s final) (t fuel : Nat) (q : List (TimedAction C))
    (hq : After (t + duration is) q) (counts : Counters) :
    ∃ counts', run false (duration is + fuel) t (timed t is ++ q) s counts [] =
      run false fuel (t + duration is) q final counts' [] := by
  induction hex generalizing t counts with
  | nil s h => exact ⟨counts, by simp [duration, timed]⟩
  | cons i is s final e quiet hp tail ih =>
    have hq' : After (t + latency i + 1 + duration is) q := by
      simpa [duration, Nat.add_assoc] using hq
    have hb : After (t + latency i + 1) (timed (t + latency i + 1) is ++ q) := by
      intro a ha
      rcases List.mem_append.mp ha with ha | ha
      · exact timed_after _ _ a ha
      · have := hq' a ha; omega
    obtain ⟨middle, hm⟩ := run_primitive t (duration is + fuel) _ s quiet i e counts (hp t) hb
    obtain ⟨last, hh⟩ := ih (t + latency i + 1) hq' middle
    refine ⟨last, ?_⟩
    simpa [duration, timed, Nat.add_assoc] using hm.trans hh


theorem executes_append {xs ys : List BoundedInstruction} {s middle final : State C}
    (hx : Executes xs s middle) (hy : Executes ys middle final) : Executes (xs ++ ys) s final := by
  induction hx with
  | nil _ _ => exact hy
  | cons i is s middle e h hp tail ih => exact .cons i _ s final e h hp (ih hy)

theorem duration_append (xs ys : List BoundedInstruction) :
    duration (xs ++ ys) = duration xs + duration ys := by
  induction xs with
  | nil => simp [duration]
  | cons i is ih => simp [duration, ih, Nat.add_assoc]

end OptimalComputation.Evaluation.Serial
