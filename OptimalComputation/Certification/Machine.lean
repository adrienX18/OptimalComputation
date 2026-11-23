import OptimalComputation.Certification.State
import OptimalComputation.Certification.Refinement

namespace OptimalComputation.Certification
open Hardware
set_option linter.unusedSimpArgs false
set_option maxRecDepth 4000

inductive Diagnostic where
  | machine (error : MachineError)
  | arithmetic (cycle lane : Nat) (error : ArithmeticFailure)
  | inputBounds (error : ArithmeticFailure)
  | outputCount (expected actual : Nat)
  | exhausted (boundary : Nat)
  | missingOutput (index address : Nat)
  | outputNotProved (index : Nat) (expected actual : Polynomial)
  deriving Repr, DecidableEq, BEq

def registerPending (s : State box c) (l : Lane c) (r : Register) : Bool :=
  (s.pending l).any fun p => p.effect.destination.any (fun d => d.val == r)

def readReady (t : Nat) (s : State box c) (l : Lane c) (r : Register) : Except MachineError (Value box) := do
  if registerPending s l r then throw ⟨t, some l.val, .pendingRead r.val⟩
  match s.readRegister l r with
  | some v => return v
  | none => throw ⟨t, some l.val, .uninitializedRegister r.val⟩

def checkReservation (t : Nat) (s : State box c) (a : Action c) : Except MachineError Unit := do
  let pending := s.pending a.lane
  if pending.length ≥ pendingInstructionsPerLane then
    throw ⟨t, some a.lane.val, .pendingCapacity pending.length⟩
  if let some r := a.instruction.destination then
    if registerPending s a.lane r.val then
      throw ⟨t, some a.lane.val, .pendingWrite r.val.val⟩
    if pending.any (fun p => p.due == t + latency a.instruction && p.effect.destination.isSome) then
      throw ⟨t, some a.lane.val, .writebackCollision (t + latency a.instruction)⟩

def prepare (maxTerms t : Nat) (s : State box c) (a : Action c) : Except Diagnostic (Pending box) := do
  (checkReservation t s a).mapError Diagnostic.machine
  let read := fun r => (readReady t s a.lane r).mapError Diagnostic.machine
  let arithmetic := fun result => result.mapError (Diagnostic.arithmetic t a.lane.val)
  let effect ← match a.instruction with
    | .load d address =>
        match s.memory address with
        | some v => pure (Effect.register d v)
        | none => throw (.machine ⟨t, some a.lane.val, .uninitializedMemory address.val⟩)
    | .store r address => do
        let v ← read r
        pure (.memory address v)
    | .add d l r => do
        let left ← read l
        let right ← read r
        pure (.register d (← arithmetic (left.add maxTerms right)))
    | .multiply d l r => do
        let left ← read l
        let right ← read r
        pure (.register d (← arithmetic (left.mul maxTerms right)))
    | .multiplyAdd d l r acc => do
        let left ← read l
        let right ← read r
        let accumulator ← read acc
        pure (.register d (← arithmetic (left.mac maxTerms right accumulator)))
  return ⟨t + latency a.instruction, effect⟩

@[simp] theorem registerPending_eval (s : State box c) (x : Nat → Int) (hx : box.Allowed x)
    (l : Lane c) (r : Register) :
    Hardware.registerPending (s.eval x hx) l r = registerPending s l r := by
  simp [Hardware.registerPending, registerPending, List.any_map, Function.comp_def]

@[simp] theorem checkReservation_eval (s : State box c) (x : Nat → Int) (hx : box.Allowed x)
    (t : Nat) (a : Action c) :
    Hardware.checkReservation t (s.eval x hx) a = checkReservation t s a := by
  simp only [Hardware.checkReservation, checkReservation, State.eval_pending, List.length_map,
    registerPending_eval, List.any_map, Function.comp_def, Pending.eval_due, Pending.eval_destination]
  rfl

theorem readReady_sound (s : State box c) (x : Nat → Int) (hx : box.Allowed x)
    (t : Nat) (l : Lane c) (r : Register) (v : Value box) (h : readReady t s l r = .ok v) :
    Hardware.readReady t (s.eval x hx) l r = .ok (v.eval x hx) := by
  simp only [readReady, Hardware.readReady, registerPending_eval, State.eval_readRegister] at h ⊢
  split at h
  · simp [throw, bind, Except.bind] at h
  · rename_i hn
    simp only [hn, ↓reduceIte, pure, Except.pure, bind, Except.bind] at h ⊢
    cases hr : s.readRegister l r <;> simp [hr, throw] at h ⊢
    subst v; rfl

/-- A successful symbolic issue is the exact concrete issue for every input
inside the box, including multiplicand and result-width checks. -/
theorem prepare_sound (s : State box c) (x : Nat → Int) (hx : box.Allowed x)
    (maxTerms t : Nat) (a : Action c) (p : Pending box)
    (h : prepare maxTerms t s a = .ok p) :
    Hardware.prepare t (s.eval x hx) a = .ok (p.eval x hx) := by
  simp only [prepare, Hardware.prepare, checkReservation_eval] at h ⊢
  cases hr : checkReservation t s a with
  | error e => simp [hr, Except.mapError, bind, Except.bind] at h
  | ok u =>
    cases u
    simp only [hr, Except.mapError, bind, Except.bind] at h ⊢
    cases hi : a.instruction with
    | load d address =>
      cases hm : s.memory address with
      | none => simp [hi, hm, throw, bind, Except.bind] at h
      | some v =>
        simp only [hi, hm, pure, Except.pure, bind, Except.bind, Except.ok.injEq] at h
        subst p
        simp [State.eval_readMemory, hm, hi, Pending.eval, Effect.eval, decode_encode_slot, pure, Except.pure]
    | store r address =>
      cases hv : readReady t s a.lane r with
      | error e => simp [hi, hv, Except.mapError, bind, Except.bind] at h
      | ok v =>
        simp only [hi, hv, Except.mapError, bind, Except.bind, pure, Except.pure, Except.ok.injEq] at h
        subst p
        simp [hi, readReady_sound s x hx t a.lane r v hv, Pending.eval, Effect.eval, pure, Except.pure]
    | add d l r =>
      cases hl : readReady t s a.lane l with
      | error e => simp [hi, hl, Except.mapError, bind, Except.bind] at h
      | ok left =>
        cases hr : readReady t s a.lane r with
        | error e => simp [hi, hl, hr, Except.mapError, bind, Except.bind] at h
        | ok right =>
          cases hv : left.add maxTerms right with
          | error e => simp [hi, hl, hr, hv, Except.mapError, bind, Except.bind] at h
          | ok v =>
            simp only [hi, hl, hr, hv, Except.mapError, bind, Except.bind, pure, Except.pure, Except.ok.injEq] at h
            subst p
            simp [hi, readReady_sound s x hx t a.lane l left hl,
              readReady_sound s x hx t a.lane r right hr, Value.add_sound left right v maxTerms hv x hx,
              Pending.eval, Effect.eval, Except.mapError, pure, Except.pure]
    | multiply d l r =>
      cases hl : readReady t s a.lane l with
      | error e => simp [hi, hl, Except.mapError, bind, Except.bind] at h
      | ok left =>
        cases hr : readReady t s a.lane r with
        | error e => simp [hi, hl, hr, Except.mapError, bind, Except.bind] at h
        | ok right =>
          cases hv : left.mul maxTerms right with
          | error e => simp [hi, hl, hr, hv, Except.mapError, bind, Except.bind] at h
          | ok v =>
            simp only [hi, hl, hr, hv, Except.mapError, bind, Except.bind, pure, Except.pure, Except.ok.injEq] at h
            subst p
            simp [hi, readReady_sound s x hx t a.lane l left hl,
              readReady_sound s x hx t a.lane r right hr, Value.mul_sound left right v maxTerms hv x hx,
              Pending.eval, Effect.eval, Except.mapError, pure, Except.pure]
    | multiplyAdd d l r acc =>
      cases hl : readReady t s a.lane l with
      | error e => simp [hi, hl, Except.mapError, bind, Except.bind] at h
      | ok left =>
        cases hr : readReady t s a.lane r with
        | error e => simp [hi, hl, hr, Except.mapError, bind, Except.bind] at h
        | ok right =>
          cases ha : readReady t s a.lane acc with
          | error e => simp [hi, hl, hr, ha, Except.mapError, bind, Except.bind] at h
          | ok accumulator =>
            cases hv : left.mac maxTerms right accumulator with
            | error e => simp [hi, hl, hr, ha, hv, Except.mapError, bind, Except.bind] at h
            | ok v =>
              simp only [hi, hl, hr, ha, hv, Except.mapError, bind, Except.bind, pure, Except.pure, Except.ok.injEq] at h
              subst p
              simp [hi, readReady_sound s x hx t a.lane l left hl,
                readReady_sound s x hx t a.lane r right hr, readReady_sound s x hx t a.lane acc accumulator ha,
                Value.mac_sound left right accumulator v maxTerms hv x hx, Pending.eval, Effect.eval, Except.mapError, pure, Except.pure]

  all_goals rfl

def commitLane (t : Nat) (original : State box c) (l : Lane c) (s : State box c) : Except Diagnostic (State box c) := do
  let pending := original.pending l
  if let some p := pending.find? (fun p => p.due < t) then
    throw (.machine ⟨t, some l.val, .overdueCompletion p.due⟩)
  let due := pending.filter (fun p => p.due == t)
  if (due.filter (fun p => p.effect.destination.isSome)).length > resultWritesPerLanePerCycle then
    throw (.machine ⟨t, some l.val, .writebackCollision t⟩)
  let next := s.setPending l (pending.filter (fun p => p.due != t))
  return due.foldl (fun state p => applyEffect state l p.effect) next

def commit (t : Nat) (s : State box c) : Except Diagnostic (State box c) :=
  foldM (commitLane t s) (List.finRange c.val.lanes) s

def enqueue (s : State box c) (prepared : List (Action c × Pending box)) : State box c :=
  prepared.foldl (fun state (action, p) =>
    state.setPending action.lane (state.pending action.lane ++ [p])) s

def step (maxTerms t : Nat) (actions : List (Action c)) (s : State box c) : Except Diagnostic (State box c) := do
  let committed ← commit t s
  let actions := sort actions (fun a b => a.lane.val ≤ b.lane.val)
  (checkBatch t actions).mapError Diagnostic.machine
  let prepared ← actions.mapM (fun a => do return (a, ← prepare maxTerms t committed a))
  return enqueue committed prepared

end OptimalComputation.Certification
