import OptimalComputation.Certification.Soundness
import OptimalComputation.Evaluation.Verification

namespace OptimalComputation.Certification
open Hardware Candidates Workloads
set_option linter.unusedSimpArgs false
set_option maxRecDepth 10000

structure RunResult (box : Box) (c : ValidConfig) where
  cycles : Nat
  state : State box c

def run (maxTerms : Nat) : Nat → Nat → List (Evaluation.TimedAction c) → State box c →
    Except Diagnostic (RunResult box c)
  | fuel, boundary, queue, state =>
      if queue.isEmpty && state.drained then .ok ⟨boundary - 1, state⟩
      else match fuel with
      | 0 => .error (.exhausted boundary)
      | fuel + 1 => do
          let (batch, rest) := queue.span (fun i => i.cycle == boundary)
          let next ← step maxTerms boundary (batch.map Evaluation.TimedAction.action) state
          run maxTerms fuel (boundary+1) rest next.materialize

theorem run_sound (maxTerms fuel boundary : Nat) (queue : List (Evaluation.TimedAction c))
    (state : State box c) (result : RunResult box c) (h : run maxTerms fuel boundary queue state = .ok result)
    (x : Nat → Int) (hx : box.Allowed x) (counts : Evaluation.Counters) :
    ∃ counts', Evaluation.run false fuel boundary queue (state.eval x hx) counts [] =
      .finished ⟨result.cycles, result.state.eval x hx, counts', []⟩ := by
  induction fuel generalizing boundary queue state counts with
  | zero =>
      unfold run at h
      split at h
      · cases h
        refine ⟨counts, ?_⟩
        simp [Evaluation.run, State.eval_drained, ‹(queue.isEmpty && state.drained) = true›]
      · contradiction
  | succ fuel ih =>
      by_cases hd : (queue.isEmpty && state.drained) = true
      · simp only [run, hd, ↓reduceIte, Except.ok.injEq] at h
        subst result
        refine ⟨counts, ?_⟩
        simp [Evaluation.run, State.eval_drained, hd]
      · have hn : (queue.isEmpty && state.drained) = false := Bool.eq_false_iff.mpr hd
        obtain ⟨batch, rest, hq⟩ : ∃ batch rest,
            queue.span (fun i => i.cycle == boundary) = (batch, rest) := ⟨_, _, rfl⟩
        simp only [run, hn, Bool.false_eq_true, ↓reduceIte, hq, State.materialize_eq] at h
        cases hs : step maxTerms boundary (batch.map Evaluation.TimedAction.action) state with
        | error e => simp [hs, bind, Except.bind] at h
        | ok next =>
            simp only [hs, bind, Except.bind] at h
            obtain ⟨events, he⟩ := step_sound state next maxTerms boundary _ x hx hs
            have hc : (queue.isEmpty && (state.eval x hx).drained) = false := by simpa using hn
            rw [Evaluation.run_step false fuel boundary queue batch rest (state.eval x hx)
              (next.eval x hx) counts [] events hc hq he]
            exact ih (boundary+1) rest next h _

def makeInputs (box : Box) (n maxTerms : Nat) : Except ArithmeticFailure (List (Value box)) :=
  (List.finRange n).mapM (fun i => Value.ofPolynomial box (Polynomial.input i.val) maxTerms)

theorem makeInputs_sound (box : Box) (n maxTerms : Nat) (values : List (Value box))
    (h : makeInputs box n maxTerms = .ok values) (inputs : Vector Signed48 n)
    (x : Nat → Int) (hx : box.Allowed x) (henv : ∀ i : Fin n, x i.val = inputs[i.val].val) :
    values.map (·.eval x hx) = inputs.toList := by
  have hh := mapM_refines
    (fun i : Fin n => Value.ofPolynomial box (Polynomial.input i.val) maxTerms)
    (fun i : Fin n => (Except.ok inputs[i.val] : Except Unit Signed48))
    (fun v : Value box => v.eval x hx) (List.finRange n) (by
      intro i hi v hv
      have hp := Value.ofPolynomial_eq hv
      have he : inputs[i.val] = v.eval x hx := by
        apply Subtype.ext
        simp only [Value.eval, hp, Polynomial.eval_variable]
        exact (henv i).symm
      rw [he]) values h
  have he : (List.finRange n).mapM (fun i : Fin n => (Except.ok inputs[i.val] : Except Unit Signed48)) =
      .ok inputs.toList := by
    calc
      _ = .ok ((List.finRange n).map (fun i => inputs[i.val])) := List.mapM_pure
      _ = _ := by
        congr 1
        rw [List.finRange, List.map_ofFn]
        change List.ofFn (fun i : Fin n => inputs[i.val]) = inputs.toList
        rw [← Vector.toList_ofFn, Vector.ofFn_getElem]
  rw [he] at hh
  exact (Except.ok.inj hh).symm

def writeInputs (addresses : List Address) (values : List (Value box)) (s : State box c) : State box c :=
  (addresses.zip values).foldl (fun state (a, v) => state.writeMemory a v) s

theorem writeInputs_eval (addresses : List Address) (values : List (Value box)) (s : State box c)
    (x : Nat → Int) (hx : box.Allowed x) :
    (writeInputs addresses values s).eval x hx =
      (addresses.zip (values.map (·.eval x hx))).foldl
        (fun state (a,v) => Hardware.State.writeMemory state a (encodeSlot v)) (s.eval x hx) := by
  induction addresses generalizing values s with
  | nil => rfl
  | cons a addresses ih =>
    cases values with
    | nil => rfl
    | cons v values =>
      simpa only [writeInputs, List.zip_cons_cons, List.foldl_cons, List.map_cons, State.eval_writeMemory]
        using ih values (s.writeMemory a v)

end OptimalComputation.Certification
