import OptimalComputation.Evaluation.Verification

/-! Compositional execution facts for deliberately serialized schedules. The
proofs below use the public cycle transition and runner for every admissible
configuration; they introduce no alternative executor. An instruction owns its issue through completion boundary. -/
set_option linter.unusedSimpArgs false
set_option backward.isDefEq.respectTransparency false
namespace OptimalComputation.Evaluation.Serial
open Hardware Candidates Workloads

abbrev C := defaultConfig

variable {c : ValidConfig}

def lane : Lane c := ⟨0, allowedCount_positive c.property.1⟩
def r0 : Register := ⟨0, by decide⟩
def r1 : WritableRegister := ⟨⟨1, by decide⟩, by decide⟩
def r2 : WritableRegister := ⟨⟨2, by decide⟩, by decide⟩
def acc : WritableRegister := ⟨⟨3, by decide⟩, by decide⟩

def Quiet (s : State c) : Prop := s.pending = Vector.replicate c.val.lanes []

def waitState (s : State c) (due : Nat) (e : Effect) : State c :=
  s.setPending lane [⟨due, e⟩]

@[simp] theorem quiet_empty : Quiet (State.empty c) := rfl
@[simp] theorem quiet_writeMemory (s : State c) (a : Address) (v : Slot64) :
    Quiet (s.writeMemory a v) ↔ Quiet s := Iff.rfl
@[simp] theorem quiet_writeRegister (s : State c) (r : WritableRegister) (v : Signed48) :
    Quiet (s.writeRegister lane r v) ↔ Quiet s := Iff.rfl
@[simp] theorem quiet_effect (s : State c) (e : Effect) :
    Quiet (applyEffect s lane e) ↔ Quiet s := by cases e <;> rfl

theorem quiet_drained {s : State c} (h : Quiet s) : s.drained = true := by
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
theorem commit_quiet (t : Nat) (s : State c) (h : Quiet s) :
    commit t s = .ok (s, []) := by
  rcases c with ⟨⟨ln, bn⟩, hc⟩
  have hl := hc.1
  have hb := hc.2
  simp only [AllowedCount, supportedCounts, List.mem_cons, List.not_mem_nil, or_false] at hl hb
  rcases hl with rfl | rfl | rfl | rfl <;> rcases hb with rfl | rfl | rfl | rfl
  all_goals
    rcases s with ⟨rs, mem, pending⟩
    change pending = _ at h
    subst pending
    simp +instances [commit, State.setPending, defaultConfig, List.finRange, Fin.ofNat,
      List.forIn_cons, List.forIn_nil, bind, pure, Except.bind, Except.pure,
      resultWritesPerLanePerCycle, setPending_unchanged]

set_option maxRecDepth 10000 in
set_option maxHeartbeats 2000000 in
theorem commit_wait_before (t due : Nat) (s : State c) (h : Quiet s) (e : Effect)
    (ht : t < due) : commit t (waitState s due e) = .ok (waitState s due e, []) := by
  rcases c with ⟨⟨ln, bn⟩, hc⟩
  have hl := hc.1
  have hb := hc.2
  simp only [AllowedCount, supportedCounts, List.mem_cons, List.not_mem_nil, or_false] at hl hb
  rcases hl with rfl | rfl | rfl | rfl <;> rcases hb with rfl | rfl | rfl | rfl
  all_goals
    rcases s with ⟨rs, mem, pending⟩
    change pending = _ at h
    subst pending
    have hne : due ≠ t := by omega
    have hnot : ¬due < t := by omega
    simp +instances [commit, waitState, State.setPending, lane, defaultConfig,
      List.finRange, Fin.ofNat, List.forIn_cons, List.forIn_nil, bind, pure, Except.bind, Except.pure,
      resultWritesPerLanePerCycle, hne, hnot] <;> rfl

set_option maxRecDepth 10000 in
set_option maxHeartbeats 2000000 in
theorem commit_wait_due (due : Nat) (s : State c) (h : Quiet s) (e : Effect) :
    commit due (waitState s due e) = .ok (applyEffect s lane e, [.committed due 0 e]) := by
  rcases c with ⟨⟨ln, bn⟩, hc⟩
  have hl := hc.1
  have hb := hc.2
  simp only [AllowedCount, supportedCounts, List.mem_cons, List.not_mem_nil, or_false] at hl hb
  rcases hl with rfl | rfl | rfl | rfl <;> rcases hb with rfl | rfl | rfl | rfl
  all_goals
    rcases s with ⟨rs, mem, pending⟩
    change pending = _ at h
    subst pending
    cases e <;>
      simp +instances [commit, waitState, State.setPending, State.writeRegister,
        State.writeMemory, applyEffect, lane, defaultConfig, Effect.destination,
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
    checkBatch (c := c) t [⟨lane, i⟩] = .ok () := by
  rcases c with ⟨⟨ln, bn⟩, hc⟩
  have hl := hc.1
  have hb := hc.2
  simp only [AllowedCount, supportedCounts, List.mem_cons, List.not_mem_nil, or_false] at hl hb
  rcases hl with rfl | rfl | rfl | rfl <;> rcases hb with rfl | rfl | rfl | rfl
  all_goals
    cases i <;>
      simp +instances [checkBatch, lane, defaultConfig, List.finRange, Fin.ofNat,
        List.forIn_cons, List.forIn_nil, bind, pure, Except.bind, Except.pure,
        instructionsPerLanePerCycle, bankPorts, Instruction.memoryAccess, bankOf]


set_option maxHeartbeats 2000000 in
theorem checkBatch_empty (t : Nat) : checkBatch (c := c) t [] = .ok () := by
  rcases c with ⟨⟨ln, bn⟩, hc⟩
  have hl := hc.1
  have hb := hc.2
  simp only [AllowedCount, supportedCounts, List.mem_cons, List.not_mem_nil, or_false] at hl hb
  rcases hl with rfl | rfl | rfl | rfl <;> rcases hb with rfl | rfl | rfl | rfl
  all_goals
    simp +instances [checkBatch, lane, defaultConfig, List.finRange, Fin.ofNat,
        List.forIn_cons, List.forIn_nil, bind, pure, Except.bind, Except.pure,
        instructionsPerLanePerCycle, bankPorts]


theorem activity_quiet (s : State c) (h : Quiet s) (t : Nat) :
    (List.finRange c.val.lanes).filterMap (fun l =>
      if (s.pending[l.val]).isEmpty then none else some (Event.active t l.val)) = [] := by
  change s.pending = _ at h
  simp +instances [h, defaultConfig, List.finRange, Fin.ofNat]

theorem activity_wait (s : State c) (h : Quiet s) (t due : Nat) (e : Effect) :
    (List.finRange c.val.lanes).filterMap (fun l =>
      if ((waitState s due e).pending[l.val]).isEmpty then none else some (Event.active t l.val)) =
      [.active t 0] := by
  rcases c with ⟨⟨ln, bn⟩, hc⟩
  have hl := hc.1
  have hb := hc.2
  simp only [AllowedCount, supportedCounts, List.mem_cons, List.not_mem_nil, or_false] at hl hb
  rcases hl with rfl | rfl | rfl | rfl <;> rcases hb with rfl | rfl | rfl | rfl
  all_goals
    change s.pending = _ at h
    simp +instances [waitState, State.setPending, h, lane, defaultConfig, List.finRange, Fin.ofNat] <;>
      first | rfl | exact ⟨rfl, rfl, rfl, rfl, rfl⟩

theorem step_issue (s : State c) (h : Quiet s) (t : Nat) (i : BoundedInstruction) (e : Effect)
    (hp : prepare t s ⟨lane, i⟩ = .ok ⟨t + latency i, e⟩) :
    step t [⟨lane, i⟩] s = .ok (waitState s (t + latency i) e,
      [.issued t 0 i.toRaw (t + latency i), .active t 0]) := by
  have he : enqueue s [(⟨lane, i⟩, ⟨t + latency i, e⟩)] = waitState s (t + latency i) e := by
    change s.pending = _ at h
    simp +instances [defaultConfig, enqueue, List.foldl_cons, List.foldl_nil, waitState, h, lane]
  simp only [step, commit_quiet t s h, canonicalActions, List.mergeSort_singleton, checkBatch_single, hp,
    List.mapM_cons, List.mapM_nil, bind, pure, Except.bind, Except.pure, he, List.map_cons, List.map_nil, List.nil_append, List.cons_append, activity_wait s h]
  rfl

theorem step_wait_before (s : State c) (h : Quiet s) (t due : Nat) (e : Effect) (ht : t < due) :
    step t [] (waitState s due e) = .ok (waitState s due e, [.active t 0]) := by
  simp only [step, commit_wait_before t due s h e ht, canonicalActions, List.mergeSort_nil, checkBatch_empty,
    List.mapM_nil, bind, pure, Except.bind, Except.pure, enqueue, List.foldl_nil, List.map_nil, List.nil_append]
  rw [activity_wait s h]

theorem step_wait_due (s : State c) (h : Quiet s) (due : Nat) (e : Effect) :
    step due [] (waitState s due e) = .ok (applyEffect s lane e, [.committed due 0 e]) := by
  simp only [step, commit_wait_due due s h e, canonicalActions, List.mergeSort_nil, checkBatch_empty,
    List.mapM_nil, bind, pure, Except.bind, Except.pure, enqueue,
    List.foldl_nil, List.map_nil]
  rw [activity_quiet _ ((quiet_effect s e).mpr h), List.append_nil, List.append_nil]

theorem prepare_load (t : Nat) (s : State c) (h : Quiet s) (d : WritableRegister)
    (a : Address) (v : Signed48) (hv : s.readMemory a = some (encodeSlot v)) :
    prepare t s ⟨lane, .load d a⟩ = .ok ⟨t + 1, .register d v⟩ := by
  change s.pending = _ at h
  have hl : (Vector.replicate c.val.lanes ([] : List PendingEffect))[(lane (c := c)).val] = [] := by simp
  simp +instances [defaultConfig, prepare, hl, checkReservation, registerPending, h, hv, latency,
    Instruction.destination, pendingInstructionsPerLane, bind, pure, Except.bind, Except.pure]

theorem prepare_store (t : Nat) (s : State c) (h : Quiet s) (r : Register)
    (a : Address) (v : Signed48) (hv : s.readRegister lane r = some v) :
    prepare t s ⟨lane, .store r a⟩ = .ok ⟨t + 1, .memory a (encodeSlot v)⟩ := by
  change s.pending = _ at h
  have hl : (Vector.replicate c.val.lanes ([] : List PendingEffect))[(lane (c := c)).val] = [] := by simp
  simp +instances [defaultConfig, prepare, hl, checkReservation, readReady, registerPending, h, hv, latency,
    Instruction.destination, pendingInstructionsPerLane, bind, pure, Except.bind, Except.pure]

theorem prepare_reset (t : Nat) (s : State c) (h : Quiet s) :
    prepare t s ⟨lane, .add acc r0 r0⟩ = .ok ⟨t + 3, .register acc zero48⟩ := by
  change s.pending = _ at h
  have hl : (Vector.replicate c.val.lanes ([] : List PendingEffect))[(lane (c := c)).val] = [] := by simp
  simp +instances [defaultConfig, prepare, hl, checkReservation, readReady, registerPending, h, lane, latency,
    Instruction.destination, pendingInstructionsPerLane, bind, pure, Except.bind, Except.pure,
    r0, zero48, checkedAdd, checkedResult, State.readRegister, InSigned48, signed48Min, signed48Max,
    Except.mapError]

theorem prepare_mac (t : Nat) (s : State c) (h : Quiet s) (a b v next : Signed48)
    (ha : s.readRegister lane r1.val = some a) (hb : s.readRegister lane r2.val = some b)
    (hv : s.readRegister lane acc.val = some v)
    (hc : checkedMac a.val b.val v.val = .ok next) :
    prepare t s ⟨lane, .multiplyAdd acc r1.val r2.val acc.val⟩ =
      .ok ⟨t + 3, .register acc next⟩ := by
  change s.pending = _ at h
  have hl : (Vector.replicate c.val.lanes ([] : List PendingEffect))[(lane (c := c)).val] = [] := by simp
  simp +instances [defaultConfig, prepare, hl, checkReservation, readReady, registerPending, h, ha, hb, hv, hc, latency,
    Instruction.destination, pendingInstructionsPerLane, bind, pure, Except.bind, Except.pure,
    Except.mapError]


def After (t : Nat) (q : List (TimedAction c)) : Prop := ∀ a ∈ q, t ≤ a.cycle

theorem span_after {t b : Nat} {q : List (TimedAction c)} (h : After t q) (hb : b < t) :
    q.span (fun a => a.cycle == b) = ([], q) := by
  cases q with
  | nil => rfl
  | cons a q =>
    have ha := h a (by simp)
    have hn : a.cycle ≠ b := by omega
    have he : (a.cycle == b) = false := beq_eq_false_iff_ne.mpr hn
    simp [List.span, List.span.loop, he]

theorem span_head {t : Nat} {q : List (TimedAction c)} (a : Action c)
    (h : After (t + 1) q) :
    ((⟨t, a⟩ : TimedAction c) :: q).span (fun a => a.cycle == t) = ([⟨t, a⟩], q) := by
  have hs := span_after h (by omega : t < t + 1)
  cases q with
  | nil => simp [List.span, List.span.loop]
  | cons b q =>
    have hb := h b (by simp)
    have hn : b.cycle ≠ t := by omega
    have he : (b.cycle == t) = false := beq_eq_false_iff_ne.mpr hn
    simp [List.span, List.span.loop, he]

theorem wait_not_drained (s : State c) (h : Quiet s) (due : Nat) (e : Effect) :
    (waitState s due e).drained = false := by
  rcases c with ⟨⟨ln, bn⟩, hc⟩
  have hl := hc.1
  have hb := hc.2
  simp only [AllowedCount, supportedCounts, List.mem_cons, List.not_mem_nil, or_false] at hl hb
  rcases hl with rfl | rfl | rfl | rfl <;> rcases hb with rfl | rfl | rfl | rfl
  all_goals
    change s.pending = _ at h
    simp +instances [State.drained, waitState, State.setPending, lane, h,
      defaultConfig, Vector.toList]

theorem run_primitive (t fuel : Nat) (q : List (TimedAction c)) (s : State c)
    (h : Quiet s) (i : BoundedInstruction) (e : Effect) (counts : Counters)
    (hp : prepare t s ⟨lane, i⟩ = .ok ⟨t + latency i, e⟩)
    (hq : After (t + latency i + 1) q) :
    ∃ counts',
      run false (latency i + 1 + fuel) t (⟨t, ⟨lane, i⟩⟩ :: q) s counts [] =
      run false fuel (t + latency i + 1) q (applyEffect s lane e) counts' [] := by
  have hl : latency i = 1 ∨ latency i = 3 := by cases i <;> simp [latency]
  have hs := step_issue s h t i e hp
  have hi : After (t + 1) q := by intro a ha; have := hq a ha; omega
  have hn : ((⟨t, ⟨lane, i⟩⟩ :: q : List (TimedAction c)).isEmpty && s.drained) = false := rfl
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
      .committed (t + 1) 0 e].foldl (Counters.record c) counts, ?_⟩
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
      .active (t + 2) 0, .committed (t + 3) 0 e].foldl (Counters.record c) counts, ?_⟩
    simp only [hl, Nat.add_assoc]
    rfl

/-- A proof relation for serial instruction lists. Each head premise is a fact
about the actual issue-time checker, with its actual captured effect. -/
inductive Executes : List BoundedInstruction → State c → State c → Prop
  | nil (s : State c) (quiet : Quiet s) : Executes [] s s
  | cons (i : BoundedInstruction) (is : List BoundedInstruction) (s final : State c) (e : Effect)
      (quiet : Quiet s)
      (prepare_ok : ∀ t, prepare t s ⟨lane, i⟩ = .ok ⟨t + latency i, e⟩)
      (tail : Executes is (applyEffect s lane e) final) : Executes (i :: is) s final

def duration : List BoundedInstruction → Nat
  | [] => 0
  | i :: is => latency i + 1 + duration is

def timed (t : Nat) : List BoundedInstruction → List (TimedAction c)
  | [] => []
  | i :: is => ⟨t, ⟨lane, i⟩⟩ :: timed (t + latency i + 1) is

theorem timed_after (t : Nat) (is : List BoundedInstruction) : After (c := c) t (timed t is) := by
  induction is generalizing t with
  | nil => simp [After, timed]
  | cons i is ih =>
    intro a ha
    simp only [timed, List.mem_cons] at ha
    rcases ha with rfl | ha
    · exact Nat.le_refl _
    · have := ih (t + latency i + 1) a ha; omega

theorem executes_quiet {is : List BoundedInstruction} {s final : State c}
    (h : Executes is s final) : Quiet final := by
  induction h with
  | nil _ h => exact h
  | cons _ _ _ _ _ _ _ _ ih => exact ih

theorem run_serial {is : List BoundedInstruction} {s final : State c}
    (hex : Executes is s final) (t fuel : Nat) (q : List (TimedAction c))
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


theorem executes_append {xs ys : List BoundedInstruction} {s middle final : State c}
    (hx : Executes xs s middle) (hy : Executes ys middle final) : Executes (xs ++ ys) s final := by
  induction hx with
  | nil _ _ => exact hy
  | cons i is s middle e h hp tail ih => exact .cons i _ s final e h hp (ih hy)

theorem duration_append (xs ys : List BoundedInstruction) :
    duration (xs ++ ys) = duration xs + duration ys := by
  induction xs with
  | nil => simp [duration]
  | cons i is ih => simp [duration, ih, Nat.add_assoc]

/-! ### Tight serial timing (`*-naive-v2` baselines)

Each instruction issues on its predecessor's completion boundary: that boundary
first commits the old effect, then issues the next instruction, exactly as the
machine's timing convention allows. Only one instruction is ever in flight, so
the timing-independent `Executes` relation is reused unchanged. -/

/-- Lane-zero schedule for any layout: issue at the previous completion boundary. -/
def tightSchedule {shape : Shape} (c : ValidConfig) (layout : Layout shape) (t : Nat)
    (is : List BoundedInstruction) (allowed : ∀ i ∈ is, MemoryAllowed layout i) :
    List (ScheduledInstruction c layout) :=
  match is with
  | [] => []
  | i :: is =>
      ⟨t, ⟨0, allowedCount_positive c.property.1⟩, i, allowed i (by simp)⟩ ::
        tightSchedule c layout (t + latency i) is (fun j hj => allowed j (by simp [hj]))

def tightTimed (t : Nat) : List BoundedInstruction → List (TimedAction c)
  | [] => []
  | i :: is => ⟨t, ⟨lane, i⟩⟩ :: tightTimed (t + latency i) is

def tightDuration : List BoundedInstruction → Nat
  | [] => 0
  | i :: is => latency i + tightDuration is

theorem latency_pos (i : BoundedInstruction) : 0 < latency i := by
  cases i <;> simp [latency]

theorem tightSchedule_timed {shape : Shape} (layout : Layout shape) (t : Nat)
    (is : List BoundedInstruction) (h : ∀ i ∈ is, MemoryAllowed layout i) :
    (tightSchedule c layout t is h).map
      (fun i => (⟨i.cycle, ⟨i.lane, i.instruction⟩⟩ : TimedAction c)) = tightTimed t is := by
  induction is generalizing t with
  | nil => rfl
  | cons i is ih => simp [tightSchedule, tightTimed, ih, lane]

theorem tightTimed_after (t : Nat) (is : List BoundedInstruction) : After (c := c) t (tightTimed t is) := by
  induction is generalizing t with
  | nil => simp [After, tightTimed]
  | cons i is ih =>
    intro a ha
    simp only [tightTimed, List.mem_cons] at ha
    rcases ha with rfl | ha
    · exact Nat.le_refl _
    · have := ih (t + latency i) a ha; omega

theorem tightTimed_sorted (t : Nat) (is : List BoundedInstruction) :
    (tightTimed (c := c) t is).Pairwise (fun a b => decide (a.cycle ≤ b.cycle) = true) := by
  induction is generalizing t with
  | nil => simp [tightTimed]
  | cons i is ih =>
    apply List.pairwise_cons.mpr
    constructor
    · intro b hb
      have := tightTimed_after (t + latency i) is b hb
      simp only [decide_eq_true_eq]
      omega
    · exact ih _

theorem tightDuration_append (xs ys : List BoundedInstruction) :
    tightDuration (xs ++ ys) = tightDuration xs + tightDuration ys := by
  induction xs with
  | nil => simp [tightDuration]
  | cons i is ih => simp [tightDuration, ih, Nat.add_assoc]

theorem enqueue_quiet (s : State c) (h : Quiet s) (i : BoundedInstruction) (due : Nat) (e : Effect) :
    enqueue s [(⟨lane, i⟩, ⟨due, e⟩)] = waitState s due e := by
  change s.pending = _ at h
  simp +instances [defaultConfig, enqueue, List.foldl_cons, List.foldl_nil, waitState, h, lane]

/-- One boundary that commits the previous effect and then issues the next
instruction against the post-commit state. -/
theorem step_commit_issue (p : State c) (hp : Quiet p) (t : Nat) (e : Effect)
    (i : BoundedInstruction) (e' : Effect)
    (hprep : prepare t (applyEffect p lane e) ⟨lane, i⟩ = .ok ⟨t + latency i, e'⟩) :
    step t [⟨lane, i⟩] (waitState p t e) =
      .ok (waitState (applyEffect p lane e) (t + latency i) e',
        [.committed t 0 e, .issued t 0 i.toRaw (t + latency i), .active t 0]) := by
  have hs : Quiet (applyEffect p lane e) := (quiet_effect p e).mpr hp
  have he := enqueue_quiet (applyEffect p lane e) hs i (t + latency i) e'
  simp only [step, commit_wait_due t p hp e, canonicalActions, List.mergeSort_singleton,
    checkBatch_single, hprep, List.mapM_cons, List.mapM_nil, bind, pure, Except.bind, Except.pure,
    he, List.map_cons, List.map_nil, List.nil_append, List.cons_append,
    activity_wait (applyEffect p lane e) hs]
  rfl

/-- The idle boundaries strictly between an issue and its completion. -/
theorem run_wait (t fuel : Nat) (q : List (TimedAction c)) (s : State c) (h : Quiet s)
    (i : BoundedInstruction) (e : Effect) (counts : Counters) (hq : After (t + latency i) q) :
    ∃ counts', run false (latency i - 1 + fuel) (t + 1) q (waitState s (t + latency i) e) counts [] =
      run false fuel (t + latency i) q (waitState s (t + latency i) e) counts' [] := by
  have hl : latency i = 1 ∨ latency i = 3 := by cases i <;> simp [latency]
  rcases hl with hl | hl
  · exact ⟨counts, by simp only [hl, Nat.sub_self, Nat.zero_add]⟩
  · have hw : (q.isEmpty && (waitState s (t + latency i) e).drained) = false := by
      rw [wait_not_drained s h]; simp
    have hsp1 := span_after hq (by omega : t + 1 < t + latency i)
    have hsp2 := span_after hq (by omega : t + 1 + 1 < t + latency i)
    rw [show latency i - 1 + fuel = (fuel + 1) + 1 by omega,
      run_step false (fuel + 1) (t + 1) q [] q _ _ _ [] _ hw hsp1
        (step_wait_before s h _ _ e (by omega))]
    simp only [Bool.false_eq_true, ↓reduceIte]
    rw [run_step false fuel (t + 1 + 1) q [] q _ _ _ [] _ hw hsp2
      (step_wait_before s h _ _ e (by omega))]
    simp only [Bool.false_eq_true, ↓reduceIte]
    rw [hl]
    exact ⟨_, rfl⟩

/-- From a boundary where the previous instruction's effect `e` is due, run the
rest of a tight serial program through its final commit. -/
theorem run_tight_pending {is : List BoundedInstruction} {s final : State c}
    (hex : Executes is s final) (p : State c) (hp : Quiet p) (e : Effect)
    (he : applyEffect p lane e = s) (t fuel : Nat) (counts : Counters) :
    ∃ counts', run false (tightDuration is + 1 + fuel) t (tightTimed t is) (waitState p t e) counts [] =
      run false fuel (t + tightDuration is + 1) [] final counts' [] := by
  induction hex generalizing p e t counts with
  | nil s quiet =>
    have hn : (([] : List (TimedAction c)).isEmpty && (waitState p t e).drained) = false := by
      rw [wait_not_drained p hp]; simp
    refine ⟨[Event.committed t 0 e].foldl (Counters.record c) counts, ?_⟩
    rw [show tightDuration ([] : List BoundedInstruction) + 1 + fuel = fuel + 1 by
      simp only [tightDuration]; omega]
    simp only [tightTimed]
    rw [run_step false fuel t [] [] [] _ _ counts [] _ hn rfl (step_wait_due p hp t e)]
    simp only [Bool.false_eq_true, ↓reduceIte, he, tightDuration, Nat.add_zero]
  | cons i is s final e' quiet hprep tail ih =>
    have hrest := tightTimed_after (c := c) (t + latency i) is
    have hi : After (c := c) (t + 1) (tightTimed (t + latency i) is) := by
      intro a ha; have := hrest a ha; have := latency_pos i; omega
    have hstep := step_commit_issue p hp t e i e' (by rw [he]; exact hprep t)
    rw [he] at hstep
    have hn : ((⟨t, ⟨lane, i⟩⟩ :: tightTimed (t + latency i) is : List (TimedAction c)).isEmpty &&
        (waitState p t e).drained) = false := rfl
    obtain ⟨c1, hw⟩ := run_wait t (tightDuration is + 1 + fuel) (tightTimed (t + latency i) is) s quiet i e'
      ([Event.committed t 0 e, .issued t 0 i.toRaw (t + latency i), .active t 0].foldl
        (Counters.record c) counts) hrest
    obtain ⟨c2, hih⟩ := ih s quiet e' rfl (t + latency i) c1
    refine ⟨c2, ?_⟩
    rw [show tightDuration (i :: is) + 1 + fuel = (latency i - 1 + (tightDuration is + 1 + fuel)) + 1 by
      simp only [tightDuration]; have := latency_pos i; omega]
    simp only [tightTimed]
    rw [run_step false _ t _ [⟨t, ⟨lane, i⟩⟩] _ _ _ counts [] _ hn (span_head _ hi) hstep]
    simp only [Bool.false_eq_true, ↓reduceIte]
    rw [hw, hih]
    simp only [tightDuration, Nat.add_assoc]

/-- A nonempty tight serial program, from a quiet state through its final commit. -/
theorem run_tight {is : List BoundedInstruction} {s final : State c}
    (hex : Executes is s final) (hne : is ≠ []) (t fuel : Nat) (counts : Counters) :
    ∃ counts', run false (tightDuration is + 1 + fuel) t (tightTimed t is) s counts [] =
      run false fuel (t + tightDuration is + 1) [] final counts' [] := by
  cases hex with
  | nil _ _ => exact absurd rfl hne
  | cons i is s final e quiet hprep tail =>
    have hrest := tightTimed_after (c := c) (t + latency i) is
    have hi : After (c := c) (t + 1) (tightTimed (t + latency i) is) := by
      intro a ha; have := hrest a ha; have := latency_pos i; omega
    have hn : ((⟨t, ⟨lane, i⟩⟩ :: tightTimed (t + latency i) is : List (TimedAction c)).isEmpty &&
        s.drained) = false := rfl
    obtain ⟨c1, hw⟩ := run_wait t (tightDuration is + 1 + fuel) (tightTimed (t + latency i) is) s quiet i e
      ([Event.issued t 0 i.toRaw (t + latency i), .active t 0].foldl (Counters.record c) counts) hrest
    obtain ⟨c2, hp⟩ := run_tight_pending tail s quiet e rfl (t + latency i) fuel c1
    refine ⟨c2, ?_⟩
    rw [show tightDuration (i :: is) + 1 + fuel = (latency i - 1 + (tightDuration is + 1 + fuel)) + 1 by
      simp only [tightDuration]; have := latency_pos i; omega]
    simp only [tightTimed]
    rw [run_step false _ t _ [⟨t, ⟨lane, i⟩⟩] _ _ _ counts [] _ hn (span_head _ hi)
      (step_issue s quiet t i e (hprep t))]
    simp only [Bool.false_eq_true, ↓reduceIte]
    rw [hw, hp]
    simp only [tightDuration, Nat.add_assoc]

/-- A whole tight program from boundary zero. The final effect commits at
boundary `ticks`, which is therefore the elapsed cycle count. -/
theorem run_tight_complete {instructions : List BoundedInstruction} {s final : State c}
    (hex : Executes instructions s final) (ticks : Nat) (ht : tightDuration instructions = ticks)
    (hpos : 0 < ticks) :
    ∃ counts, run false (ticks + 1) 0 (tightTimed 0 instructions) s (Counters.empty c) [] =
      .finished ⟨ticks, final, counts, []⟩ := by
  have hne : instructions ≠ [] := by
    intro h; subst h; simp [tightDuration] at ht; omega
  obtain ⟨counts, hr⟩ := run_tight hex hne 0 0 (Counters.empty c)
  refine ⟨counts, ?_⟩
  rw [ht] at hr
  simp only [Nat.add_zero, Nat.zero_add] at hr
  rw [hr, run_finished false 0 (ticks + 1) final counts [] (quiet_drained (executes_quiet hex))]
  rfl

end OptimalComputation.Evaluation.Serial
