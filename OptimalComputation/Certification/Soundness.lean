import OptimalComputation.Certification.Machine

namespace OptimalComputation.Certification
open Hardware
set_option linter.unusedSimpArgs false
set_option maxRecDepth 4000

/-- An unfolding helper for the existing concrete loop; no new semantics. -/
private def concreteCommitLane (t : Nat) (original : Hardware.State c) (l : Lane c)
    (pair : Hardware.State c × List Event) : Except MachineError (ForInStep (Hardware.State c × List Event)) := do
  let pending := original.pending[l.val]
  if let some p := pending.find? (fun p => p.due < t) then
    throw ⟨t, some l.val, .overdueCompletion p.due⟩
  let due := pending.filter (fun p => p.due == t)
  if (due.filter (fun p => p.effect.destination.isSome)).length > resultWritesPerLanePerCycle then
    throw ⟨t, some l.val, .writebackCollision t⟩
  let mut state := pair.1.setPending l (pending.filter (fun p => p.due != t))
  let mut events := pair.2
  for p in due do
    state := Hardware.applyEffect state l p.effect
    events := events ++ [.committed t l.val p.effect]
  return .yield (state, events)

private theorem commit_unfold (t : Nat) (s : Hardware.State c) :
    Hardware.commit t s = (do
      let pair ← forIn (List.finRange c.val.lanes) (s, []) (concreteCommitLane t s)
      pure (pair.1, pair.2)) := rfl

private theorem commitLane_sound (t : Nat) (original s next : State box c) (l : Lane c)
    (x : Nat → Int) (hx : box.Allowed x) (events : List Event)
    (h : commitLane t original l s = .ok next) :
    ∃ events', concreteCommitLane t (original.eval x hx) l (s.eval x hx, events) =
      .ok (.yield (next.eval x hx, events')) := by
  unfold commitLane at h
  unfold concreteCommitLane
  simp only [State.eval_pending, List.find?_map, List.filter_map, Function.comp_def,
    Pending.eval, Effect.eval_destination, List.length_map]
  cases hold : (original.pending l).find? (fun p => decide (p.due < t)) with
  | some p => simp [hold, throw, bind, Except.bind] at h
  | none =>
    simp only [hold, Option.map_none] at h ⊢
    split at h
    · simp [throw, bind, Except.bind] at h
    · rename_i hcount
      simp only [hcount, ↓reduceIte] at h ⊢
      simp only [pure, Except.pure, Except.ok.injEq] at h
      subst next
      have hset := State.eval_setPending s x hx l ((original.pending l).filter (fun p => p.due != t))
      dsimp only [Pending.eval] at hset
      rw [← hset]
      simp only [List.forIn_map]
      let due := (original.pending l).filter (fun p => p.due == t)
      let start := s.setPending l ((original.pending l).filter (fun p => p.due != t))
      obtain ⟨result, hr, he⟩ := pure_forIn
        (fun (a : State box c) (b : Hardware.State c × List Event) => b.1 = a.eval x hx)
        (fun (p : Pending box) a => applyEffect a l p.effect)
        (fun p (pair : Hardware.State c × List Event) =>
          pure (.yield (Hardware.applyEffect pair.1 l (p.eval x hx).effect,
            pair.2 ++ [.committed t l.val (p.eval x hx).effect])))
        due (by
          intro p hp a b hab
          refine ⟨_, rfl, ?_⟩
          rw [hab]
          exact (eval_applyEffect a l p.effect x hx).symm)
        start (start.eval x hx, events) rfl
      refine ⟨result.2, ?_⟩
      simp only [due, start, Pending.eval] at hr he
      rw [hr]
      simp only [bind, Except.bind, pure, Except.pure]
      rw [he]

theorem commit_sound (t : Nat) (s next : State box c) (x : Nat → Int) (hx : box.Allowed x)
    (h : commit t s = .ok next) :
    ∃ events, Hardware.commit t (s.eval x hx) = .ok (next.eval x hx, events) := by
  obtain ⟨result, hr, he⟩ := foldM_forIn
    (fun (a : State box c) (b : Hardware.State c × List Event) => b.1 = a.eval x hx)
    (commitLane t s) (concreteCommitLane t (s.eval x hx)) (List.finRange c.val.lanes)
    (by
      intro l hl a b hab a' ha
      obtain ⟨state, events⟩ := b
      dsimp at hab
      subst state
      obtain ⟨events', he⟩ := commitLane_sound t s a a' l x hx events ha
      exact ⟨(a'.eval x hx, events'), he, rfl⟩)
    s (s.eval x hx, []) rfl next h
  refine ⟨result.2, ?_⟩
  rw [commit_unfold, hr]
  try simp only [bind, Except.bind, pure, Except.pure]
  have hp : result = (next.eval x hx, result.2) := Prod.ext he rfl
  rw [hp]

def evalPrepared (x : Nat → Int) (hx : box.Allowed x) (p : Action c × Pending box) :
    Action c × PendingEffect := (p.1, p.2.eval x hx)

theorem enqueue_eval (s : State box c) (ps : List (Action c × Pending box))
    (x : Nat → Int) (hx : box.Allowed x) :
    (enqueue s ps).eval x hx = Hardware.enqueue (s.eval x hx) (ps.map (evalPrepared x hx)) := by
  induction ps generalizing s with
  | nil => rfl
  | cons p ps ih =>
    obtain ⟨a, p⟩ := p
    let next := s.setPending a.lane (s.pending a.lane ++ [p])
    have he : next.eval x hx = (s.eval x hx).setPending a.lane
        ((s.eval x hx).pending[a.lane.val] ++ [p.eval x hx]) := by
      simp [next, State.eval_setPending]
    simpa only [enqueue, Hardware.enqueue, List.foldl_cons, List.map_cons, evalPrepared, he]
      using ih next

theorem step_sound (s next : State box c) (maxTerms t : Nat) (actions : List (Action c))
    (x : Nat → Int) (hx : box.Allowed x) (h : step maxTerms t actions s = .ok next) :
    ∃ events, Hardware.step t actions (s.eval x hx) = .ok (next.eval x hx, events) := by
  unfold step at h
  have hs : sort actions (fun a b => a.lane.val ≤ b.lane.val) = canonicalActions actions := sort_eq _ _
  rw [hs] at h
  cases hc : commit t s with
  | error e => simp [hc, bind, Except.bind] at h
  | ok committed =>
    simp only [hc, bind, Except.bind] at h
    cases hb : checkBatch t (canonicalActions actions) with
    | error e => simp [hb, Except.mapError, bind, Except.bind] at h
    | ok u =>
      cases u
      simp only [hb, Except.mapError, bind, Except.bind] at h
      let f := fun a : Action c => do
        let p ← prepare maxTerms t committed a
        pure (a, p)
      change (do let ps ← (canonicalActions actions).mapM f; pure (enqueue committed ps)) = .ok next at h
      cases hp : (canonicalActions actions).mapM f with
      | error e => simp [hp, bind, Except.bind] at h
      | ok ps =>
        change (do let ps ← (canonicalActions actions).mapM f; pure (enqueue committed ps)) = .ok next at h
        simp only [hp, bind, Except.bind, pure, Except.pure, Except.ok.injEq] at h
        subst next
        have hprepared := mapM_refines f
          (fun a : Action c => do
            let p ← Hardware.prepare t (committed.eval x hx) a
            pure (a, p))
          (evalPrepared x hx) (canonicalActions actions) (by
            intro a ha p he
            cases hv : prepare maxTerms t committed a with
            | error e => simp [f, hv, bind, Except.bind] at he
            | ok v =>
              simp only [f, hv, bind, Except.bind, pure, Except.pure, Except.ok.injEq] at he
              subst p
              simp [prepare_sound committed x hx maxTerms t a v hv, evalPrepared, bind, Except.bind, pure, Except.pure])
          ps hp
        obtain ⟨cevents, hcommit⟩ := commit_sound t s committed x hx hc
        unfold Hardware.step
        rw [hcommit]
        simp only [bind, Except.bind, hb]
        simp only [bind, Except.bind] at hprepared
        rw [hprepared]
        simp only [bind, Except.bind, pure, Except.pure]
        rw [enqueue_eval]
        exact ⟨_, rfl⟩

end OptimalComputation.Certification
