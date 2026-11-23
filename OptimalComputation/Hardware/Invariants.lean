import OptimalComputation.Hardware.Machine

namespace OptimalComputation.Hardware

/-- The executable list traversal stops on the first error. -/
theorem forIn_preserves {α β ε : Type} (xs : List α) (f : α → β → Except ε (ForInStep β))
    (P : β → Prop) (initial final : β) (hi : P initial)
    (hf : ∀ a ∈ xs, ∀ b, P b → ∀ next, f a b = .ok next →
      match next with | .done value | .yield value => P value)
    (h : forIn xs initial f = .ok final) : P final := by
  induction xs generalizing initial with
  | nil =>
    have he : initial = final := by simpa only [List.forIn_nil, pure, Except.pure, Except.ok.injEq] using h
    exact he ▸ hi
  | cons a xs ih =>
    rw [List.forIn_cons] at h
    cases he : f a initial with
    | error e => simp [he, bind, Except.bind] at h
    | ok next =>
      have hn := hf a (by simp) initial hi next he
      cases next with
      | done b =>
        have heq : b = final := by simpa [he, bind, Except.bind, pure, Except.pure] using h
        exact heq ▸ hn
      | yield b =>
        simp only [he, bind, Except.bind] at h
        exact ih b hn (fun a ha => hf a (by simp [ha])) h

def PendingBounded (s : State c) : Prop :=
  ∀ lane : Lane c, (s.pending[lane.val]).length ≤ pendingInstructionsPerLane

theorem empty_pending_bounded (c : ValidConfig) : PendingBounded (State.empty c) := by
  intro lane
  simp [State.empty, pendingInstructionsPerLane]

theorem writeMemory_pending_bounded {s : State c} (h : PendingBounded s)
    (a : Address) (v : Slot64) : PendingBounded (s.writeMemory a v) := h

theorem applyEffect_pending (s : State c) (lane : Lane c) (e : Effect) :
    (applyEffect s lane e).pending = s.pending := by cases e <;> rfl

theorem setPending_bounded {s : State c} (h : PendingBounded s) (lane : Lane c)
    (ps : List PendingEffect) (hp : ps.length ≤ pendingInstructionsPerLane) :
    PendingBounded (s.setPending lane ps) := by
  intro other
  by_cases he : lane = other
  · subst other; simpa using hp
  · simpa [State.pending_set_other _ _ _ _ he] using h other

theorem commit_pending_bounded {s next : State c} {events : List Event} {t : Nat}
    (hb : PendingBounded s) (h : commit t s = .ok (next, events)) : PendingBounded next := by
  unfold commit at h
  simp only [bind, Except.bind, pure, Except.pure] at h
  split at h
  · contradiction
  · rename_i result hrun
    cases h
    apply forIn_preserves _ _ (fun result => PendingBounded result.1) _ _ hb ?_ hrun
    intro lane _ current hc result hr
    split at hr
    · simp [throw] at hr
    · split at hr
      · simp [throw] at hr
      · have hset : PendingBounded
            (current.1.setPending lane (s.pending[lane.val].filter (fun p => p.due != t))) :=
          setPending_bounded hc lane _ (Nat.le_trans (List.length_filter_le _ _) (hb lane))
        split at hr
        · contradiction
        · rename_i pair hinner
          cases hr
          apply forIn_preserves _ _ (fun result => PendingBounded result.1) _ _ hset ?_ hinner
          intro p _ current hc result hr
          simp only [Except.ok.injEq] at hr
          subst result
          simpa only [PendingBounded, applyEffect_pending] using hc



/-- A traversal whose successful callbacks always continue checked every member. -/
theorem forIn_yield_all {α β ε : Type} (xs : List α)
    (f : α → β → Except ε (ForInStep β)) (P : α → Prop)
    (hf : ∀ a ∈ xs, ∀ b next, f a b = .ok next → ∃ value, next = .yield value ∧ P a)
    {initial final : β} (h : forIn xs initial f = .ok final) : ∀ a ∈ xs, P a := by
  induction xs generalizing initial with
  | nil => simp
  | cons a xs ih =>
    rw [List.forIn_cons] at h
    cases he : f a initial with
    | error e => simp [he, bind, Except.bind] at h
    | ok next =>
      obtain ⟨value, rfl, hp⟩ := hf a (by simp) initial next he
      simp only [he, bind, Except.bind] at h
      have ht := ih (fun a ha => hf a (by simp [ha])) h
      intro x hx
      rcases List.mem_cons.mp hx with rfl | hx
      · exact hp
      · exact ht x hx

def IssueLegal (actions : List (Action c)) : Prop :=
  ∀ lane : Lane c, (actions.filter (fun a => a.lane == lane)).length ≤ instructionsPerLanePerCycle

def BankLegal (actions : List (Action c)) : Prop :=
  ∀ bank : Fin c.val.banks,
    ((actions.filterMap (fun a => a.instruction.memoryAccess)).filter
      (fun (_, address) => bankOf c address == bank)).length ≤ bankPorts

def AddressLegal (actions : List (Action c)) : Prop :=
  ∀ kind address, (kind, address) ∈ actions.filterMap (fun a => a.instruction.memoryAccess) →
    kind = .write →
      ((actions.filterMap (fun a => a.instruction.memoryAccess)).filter
        (fun (_, b) => b == address)).length ≤ 1

def BatchLegal (actions : List (Action c)) : Prop :=
  IssueLegal actions ∧ BankLegal actions ∧ AddressLegal actions

theorem checkBatch_sound {actions : List (Action c)} {t : Nat}
    (h : checkBatch t actions = .ok ()) : BatchLegal actions := by
  unfold checkBatch at h
  simp only [bind, Except.bind, pure, Except.pure] at h
  split at h
  · contradiction
  · rename_i u hl
    cases u
    split at h
    · contradiction
    · rename_i u hb
      cases u
      split at h
      · contradiction
      · rename_i u ha
        have hi := forIn_yield_all _ _
          (fun lane => (actions.filter (fun a => a.lane == lane)).length ≤ instructionsPerLanePerCycle)
          (by
            intro lane _ _ next hn
            split at hn
            · simp [throw] at hn
            · rename_i hnot
              simp only [Except.ok.injEq] at hn
              exact ⟨_, hn.symm, Nat.le_of_not_gt hnot⟩) hl
        have hb' := forIn_yield_all _ _
          (fun bank => ((actions.filterMap (fun a => a.instruction.memoryAccess)).filter
            (fun (_, address) => bankOf c address == bank)).length ≤ bankPorts)
          (by
            intro bank _ _ next hn
            split at hn
            · simp [throw] at hn
            · rename_i hnot
              simp only [Except.ok.injEq] at hn
              exact ⟨_, hn.symm, Nat.le_of_not_gt hnot⟩) hb
        have ha' := forIn_yield_all _ _
          (fun access => access.1 = AccessKind.write →
            ((actions.filterMap (fun a => a.instruction.memoryAccess)).filter
              (fun (_, b) => b == access.2)).length ≤ 1)
          (by
            intro access _ _ next hn
            split at hn
            · simp [throw] at hn
            · rename_i hnot
              simp only [Except.ok.injEq] at hn
              refine ⟨_, hn.symm, ?_⟩
              intro hw
              have hww : (AccessKind.write == AccessKind.write) = true := rfl
              simpa [hw, hww] using hnot) ha
        exact ⟨fun l => hi l (List.mem_finRange l),
          (fun b => hb' b (List.mem_finRange b)), fun k a hm => ha' (k, a) hm⟩



theorem checkReservation_capacity {s : State c} {a : Action c} {t : Nat}
    (h : checkReservation t s a = .ok ()) :
    (s.pending[a.lane.val]).length < pendingInstructionsPerLane := by
  by_cases hp : (s.pending[a.lane.val]).length ≥ pendingInstructionsPerLane
  · simp [checkReservation, hp, bind, Except.bind, throw, throwThe] at h
  · omega

theorem prepare_reservation {s : State c} {a : Action c} {t : Nat} {p : PendingEffect}
    (h : prepare t s a = .ok p) : checkReservation t s a = .ok () := by
  unfold prepare at h
  cases hr : checkReservation t s a with
  | error e => simp [hr, bind, Except.bind] at h
  | ok u => cases u; rfl

/-- Extract exactly the payloads produced by the real issue-time checker. -/
theorem mapM_pairs_ok {α β ε : Type} (f : α → Except ε β) {xs : List α} {ps : List (α × β)}
    (h : xs.mapM (fun a => do return (a, ← f a)) = .ok ps) :
    ps.map Prod.fst = xs ∧ ∀ a b, (a, b) ∈ ps → f a = .ok b := by
  induction xs generalizing ps with
  | nil =>
    simp only [List.mapM_nil, pure, Except.pure, Except.ok.injEq] at h
    subst ps
    simp
  | cons a xs ih =>
    rw [List.mapM_cons] at h
    cases hf : f a with
    | error e => simp [hf, bind, Except.bind] at h
    | ok b =>
      cases ht : xs.mapM (fun a => do return (a, ← f a)) with
      | error e =>
        simp only [bind, Except.bind, pure, Except.pure] at ht
        simp [hf, ht, bind, Except.bind, pure, Except.pure] at h
      | ok tail =>
        have htOriginal := ht
        simp only [bind, Except.bind, pure, Except.pure] at ht
        simp only [hf, ht, bind, Except.bind, pure, Except.pure, Except.ok.injEq] at h
        subst ps
        obtain ⟨hm, hv⟩ := ih htOriginal
        refine ⟨by simpa using hm, ?_⟩
        intro x y hxy
        rcases List.mem_cons.mp hxy with he | he
        · cases he; exact hf
        · exact hv _ _ he

theorem enqueue_length (s : State c) (ps : List (Action c × PendingEffect)) (lane : Lane c) :
    ((enqueue s ps).pending[lane.val]).length =
      (s.pending[lane.val]).length + (ps.filter (fun p => p.1.lane == lane)).length := by
  induction ps generalizing s with
  | nil => simp [enqueue]
  | cons p ps ih =>
    change ((enqueue (s.setPending p.1.lane (s.pending[p.1.lane.val] ++ [p.2])) ps).pending[lane.val]).length = _
    rw [ih]
    by_cases he : p.1.lane = lane
    · simp [he]
      omega
    · simp [State.pending_set_other _ _ _ _ he, he]

theorem enqueue_bounded {s : State c} {ps : List (Action c × PendingEffect)}
    (hb : PendingBounded s)
    (hi : ∀ lane : Lane c, (ps.filter (fun p => p.1.lane == lane)).length ≤ 1)
    (hr : ∀ a p, (a, p) ∈ ps → (s.pending[a.lane.val]).length < pendingInstructionsPerLane) :
    PendingBounded (enqueue s ps) := by
  intro lane
  rw [enqueue_length]
  by_cases he : (ps.filter (fun p => p.1.lane == lane)) = []
  · simp [he, hb lane]
  · obtain ⟨p, hp⟩ := List.exists_mem_of_ne_nil _ he
    obtain ⟨hm, hl⟩ := List.mem_filter.mp hp
    have heq : p.1.lane = lane := by simpa using hl
    have hc := hr p.1 p.2 hm
    have hc' : (s.pending[lane.val]).length < pendingInstructionsPerLane := by simpa only [heq] using hc
    have hn := hi lane
    omega

theorem step_pending_bounded {s next : State c} {t : Nat} {actions : List (Action c)}
    {events : List Event} (hb : PendingBounded s)
    (h : step t actions s = .ok (next, events)) : PendingBounded next := by
  unfold step at h
  simp only [bind, Except.bind, pure, Except.pure] at h
  split at h
  · contradiction
  · rename_i committed hc
    split at h
    · contradiction
    · rename_i u hcheck
      split at h
      · contradiction
      · rename_i prepared hprep
        cases h
        have hi := (checkBatch_sound hcheck).1
        have hp := mapM_pairs_ok (prepare t committed.1) hprep
        apply enqueue_bounded (commit_pending_bounded hb hc)
        · intro lane
          have hh := congrArg (fun xs => (xs.filter (fun a => a.lane == lane)).length) hp.1
          simp only [List.filter_map, List.length_map] at hh
          exact hh ▸ hi lane
        · intro a p hm
          exact checkReservation_capacity (prepare_reservation (hp.2 a p hm))



/-- These are precisely the register effects committed by `commit` at this
boundary. The limit holds even for hand-built input states if commit succeeds. -/
theorem commit_writeback_limit {s next : State c} {events : List Event} {t : Nat}
    (h : commit t s = .ok (next, events)) :
    ∀ lane : Lane c,
      (((s.pending[lane.val]).filter (fun p => p.due == t)).filter
        (fun p => p.effect.destination.isSome)).length ≤ resultWritesPerLanePerCycle := by
  unfold commit at h
  simp only [bind, Except.bind, pure, Except.pure] at h
  split at h
  · contradiction
  · rename_i result hrun
    have hall := forIn_yield_all _ _
      (fun lane : Lane c => (((s.pending[lane.val]).filter (fun p => p.due == t)).filter
        (fun p => p.effect.destination.isSome)).length ≤ resultWritesPerLanePerCycle)
      (by
        intro lane _ current result hr
        split at hr
        · simp [throw] at hr
        · split at hr
          · simp [throw] at hr
          · rename_i hnot
            split at hr
            · contradiction
            · simp only [Except.ok.injEq] at hr
              exact ⟨_, hr.symm, Nat.le_of_not_gt hnot⟩) hrun
    exact fun lane => hall lane (List.mem_finRange lane)

/-- Reachability uses only the public transition, with arbitrary legal batches;
no reference or alternate evaluator appears in the relation. -/
inductive Reachable (initial : State c) : State c → Prop where
  | initial : Reachable initial initial
  | step {s next : State c} (prior : Reachable initial s) (t : Nat)
      (actions : List (Action c)) (events : List Event)
      (transition : Hardware.step t actions s = .ok (next, events)) : Reachable initial next

theorem reachable_pending_bounded {initial s : State c} (hi : PendingBounded initial)
    (h : Reachable initial s) : PendingBounded s := by
  induction h with
  | initial => exact hi
  | step _ _ _ _ hs ih => exact step_pending_bounded ih hs

/-- A successful boundary obeys the same batch checker and completion checker
used by execution. The canonical action list preserves multiset membership. -/
theorem step_limits {s next : State c} {t : Nat} {actions : List (Action c)}
    {events : List Event} (h : step t actions s = .ok (next, events)) :
    BatchLegal (canonicalActions actions) ∧
      (∀ lane : Lane c, (((s.pending[lane.val]).filter (fun p => p.due == t)).filter
        (fun p => p.effect.destination.isSome)).length ≤ resultWritesPerLanePerCycle) := by
  unfold step at h
  simp only [bind, Except.bind, pure, Except.pure] at h
  split at h
  · contradiction
  · rename_i committed hc
    split at h
    · contradiction
    · rename_i u hcheck
      exact ⟨checkBatch_sound hcheck, commit_writeback_limit hc⟩

theorem Reachable.trans {initial middle final : State c}
    (first : Reachable initial middle) (second : Reachable middle final) : Reachable initial final := by
  induction second with
  | initial => exact first
  | step _ t actions events hs ih => exact .step ih t actions events hs

end OptimalComputation.Hardware
