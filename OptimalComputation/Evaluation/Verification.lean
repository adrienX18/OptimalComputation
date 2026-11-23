import OptimalComputation.Evaluation.Execution
import OptimalComputation.Hardware.Invariants
import OptimalComputation.Workloads.ScalarAdapter

namespace OptimalComputation.Evaluation
open Hardware Candidates Workloads

theorem initialState_pending_bounded (config : ValidConfig) (layout : Layout shape)
    (inputs : Vector Signed48 shape.inputCount) : PendingBounded (initialState config layout inputs) := by
  unfold initialState
  generalize layout.inputs.zip inputs.toList = pairs
  have go : ∀ (pairs : List (Address × Signed48)) (s : State config), PendingBounded s →
      PendingBounded (pairs.foldl (fun state (address, value) =>
        state.writeMemory address (encodeSlot value)) s) := by
    intro pairs
    induction pairs with
    | nil => intro s hs; exact hs
    | cons pair rest ih =>
      intro s hs
      exact ih _ (writeMemory_pending_bounded hs _ _)
  exact go pairs _ (empty_pending_bounded config)

theorem execution_reachable_pending_bounded (candidate : Candidate shape)
    (inputs : Vector Signed48 shape.inputCount) {state : State candidate.configuration}
    (h : Reachable (initialState candidate.configuration candidate.layout inputs) state) :
    PendingBounded state :=
  reachable_pending_bounded (initialState_pending_bounded _ _ _) h

/-- Every finished run is a chain of the actual successful machine steps.
Combined with execution_reachable_pending_bounded this covers all its states. -/
theorem run_finished_reachable (captureTrace : Bool) (fuel boundary : Nat)
    (queue : List (TimedAction c)) (state : State c) (counts : Counters)
    (trace : List BoundaryTrace) (result : RunResult c)
    (h : run captureTrace fuel boundary queue state counts trace = .finished result) :
    Reachable state result.state := by
  induction fuel generalizing boundary queue state counts trace with
  | zero =>
    rw [run] at h
    split at h
    · cases h; exact .initial
    · contradiction
  | succ fuel ih =>
    by_cases hd : (queue.isEmpty && state.drained) = true
    · rw [run] at h
      simp only [hd, ↓reduceIte] at h
      cases h
      exact .initial
    · have hn : (queue.isEmpty && state.drained) = false := Bool.eq_false_iff.mpr hd
      obtain ⟨batch, rest, hq⟩ : ∃ batch rest,
          queue.span (fun i => i.cycle == boundary) = (batch, rest) := ⟨_, _, rfl⟩
      cases hs : step boundary (batch.map TimedAction.action) state with
      | error e =>
        simp only [run, hn, hq, hs, Bool.false_eq_true, ↓reduceIte] at h
        contradiction
      | ok pair =>
        obtain ⟨next, events⟩ := pair
        rw [run_step captureTrace fuel boundary queue batch rest state next counts trace events hn hq hs] at h
        exact Reachable.trans (.step .initial boundary _ events hs) (ih _ _ _ _ _ h)

/-- More evaluator fuel cannot change a completed execution or its event record. -/
theorem run_monotone (captureTrace : Bool) (fuel extra boundary : Nat)
    (queue : List (TimedAction c)) (state : State c) (counts : Counters)
    (trace : List BoundaryTrace) (result : RunResult c)
    (h : run captureTrace fuel boundary queue state counts trace = .finished result) :
    run captureTrace (fuel + extra) boundary queue state counts trace = .finished result := by
  induction fuel generalizing boundary queue state counts trace with
  | zero =>
    rw [run] at h
    split at h
    · rename_i hd
      rw [run.eq_def]
      simpa only [Nat.zero_add, hd, ↓reduceIte] using h
    · contradiction
  | succ fuel ih =>
    by_cases hd : (queue.isEmpty && state.drained) = true
    · rw [run] at h
      rw [run.eq_def]
      simpa only [hd, ↓reduceIte] using h
    · have hn : (queue.isEmpty && state.drained) = false := Bool.eq_false_iff.mpr hd
      obtain ⟨batch, rest, hq⟩ : ∃ batch rest,
          queue.span (fun i => i.cycle == boundary) = (batch, rest) :=
        ⟨_, _, rfl⟩
      cases hs : step boundary (batch.map TimedAction.action) state with
      | error e =>
        simp only [run, hn, hq, hs, Bool.false_eq_true, ↓reduceIte] at h
        contradiction
      | ok pair =>
        obtain ⟨next, events⟩ := pair
        rw [run_step captureTrace fuel boundary queue batch rest state next counts trace events hn hq hs] at h
        rw [show fuel + 1 + extra = (fuel + extra) + 1 by omega,
          run_step captureTrace (fuel + extra) boundary queue batch rest state next counts trace events hn hq hs]
        exact ih _ _ _ _ _ h

theorem executeValues_monotone (candidate : Candidate shape)
    (inputs : Vector Signed48 shape.inputCount) (fuel extra : Nat) (captureTrace : Bool)
    (record : ExecutionRecord)
    (h : executeValues candidate inputs fuel captureTrace = .success record) :
    executeValues candidate inputs (fuel + extra) captureTrace = .success record := by
  unfold executeValues at h ⊢
  split at h
  · rename_i result hr
    rw [run_monotone captureTrace fuel extra _ _ _ _ _ result hr]
    exact h
  · contradiction
  · contradiction

/-- Safety means successful finite execution of the actual machine, including
all checked operand/intermediate widths, drained pipelines and written outputs. -/
def ExecutionSafety (adapter : ScalarAdapter spec) (candidate : Candidate adapter.shape)
    (boundaries : Nat) : Prop :=
  ∀ x (h : spec.AllowedInput x), ∃ record,
    executeValues candidate (adapter.encode x h) boundaries false = .success record

/-- Functional correctness is separate from safety; it speaks only about actual
successful records and compares every output scalar in the workload codec. -/
def FunctionalCorrectness (adapter : ScalarAdapter spec) (candidate : Candidate adapter.shape)
    (boundaries : Nat) : Prop :=
  ∀ x (h : spec.AllowedInput x) record,
    executeValues candidate (adapter.encode x h) boundaries false = .success record →
      record.outputs = (adapter.outputScalars (spec.reference x)).toList

/-- A certificate binds the specification and scalar codecs, the complete
candidate (configuration, layout, schedule), and the fixed model semantics
called by executeValues. Neither an identifier nor a Boolean is a certificate. -/
structure VerifiedCandidate (adapter : ScalarAdapter spec) where
  candidate : Candidate adapter.shape
  sufficientBoundaries : Nat
  safety : ExecutionSafety adapter candidate sufficientBoundaries
  correctness : FunctionalCorrectness adapter candidate sufficientBoundaries

theorem VerifiedCandidate.success_correct {spec : Specification} {adapter : ScalarAdapter spec} (verified : VerifiedCandidate adapter)
    (x : spec.Input) (hx : spec.AllowedInput x) (fuel : Nat)
    (hfuel : fuel ≤ verified.sufficientBoundaries) (record : ExecutionRecord)
    (h : executeValues verified.candidate (adapter.encode x hx) fuel false = .success record) :
    record.outputs = (adapter.outputScalars (spec.reference x)).toList := by
  have hm := executeValues_monotone verified.candidate (adapter.encode x hx)
    fuel (verified.sufficientBoundaries - fuel) false record h
  rw [Nat.add_sub_of_le hfuel] at hm
  exact verified.correctness x hx record hm

theorem VerifiedCandidate.decoded_correct {spec : Specification} {adapter : ScalarAdapter spec} (verified : VerifiedCandidate adapter)
    (x : spec.Input) (hx : spec.AllowedInput x) (record : ExecutionRecord)
    (h : executeValues verified.candidate (adapter.encode x hx)
      verified.sufficientBoundaries false = .success record) :
    adapter.readOutput record.outputs = some (spec.reference x) := by
  rw [verified.correctness x hx record h]
  exact adapter.readOutput_roundtrip _

end OptimalComputation.Evaluation
