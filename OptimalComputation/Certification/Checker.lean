import OptimalComputation.Certification.Runner

namespace OptimalComputation.Certification
open Hardware Candidates Workloads
set_option linter.unusedSimpArgs false
set_option maxRecDepth 10000
variable {spec : Specification} {a : ScalarAdapter spec}

def environment (a : ScalarAdapter spec) (x : spec.Input) (i : Nat) : Int :=
  if h : i < a.shape.inputCount then (a.inputScalars x)[i] else 0

/-- A workload connects its existing mathematical specification to an input
box and symbolic outputs once. No program, scheduler or objective is involved. -/
structure Problem (a : ScalarAdapter spec) where
  box : Box
  input_sound : ∀ x, spec.AllowedInput x → box.Allowed (environment a x)
  outputs : List Polynomial
  output_sound : ∀ x, spec.AllowedInput x →
    outputs.map (Polynomial.eval (environment a x)) = (a.outputScalars (spec.reference x)).toList

def checkOutputs (s : State box c) : Nat → List Address → List Polynomial → Except Diagnostic Unit
  | _, [], [] => .ok ()
  | index, a :: addresses, p :: expected =>
      match s.memory a with
      | none => .error (.missingOutput index a.val)
      | some v =>
          if v.polynomial = p then checkOutputs s (index+1) addresses expected
          else .error (.outputNotProved index p v.polynomial)
  | _, addresses, expected => .error (.outputCount expected.length addresses.length)

theorem checkOutputs_sound (s : State box c) (index : Nat) (addresses : List Address) (expected : List Polynomial)
    (h : checkOutputs s index addresses expected = .ok ()) (x : Nat → Int) (hx : box.Allowed x) :
    (addresses.filter (fun a => ((s.eval x hx).readMemory a).isNone)) = [] ∧
    Evaluation.collectOutputs addresses (s.eval x hx) = expected.map (Polynomial.eval x) := by
  induction addresses generalizing index expected with
  | nil =>
      cases expected with
      | nil => exact ⟨rfl, rfl⟩
      | cons p ps => simp [checkOutputs] at h
  | cons a addresses ih =>
    cases expected with
    | nil => simp [checkOutputs] at h
    | cons p expected =>
      cases hm : s.memory a with
      | none => simp [checkOutputs, hm] at h
      | some v =>
        simp only [checkOutputs, hm] at h
        split at h
        · rename_i hp
          obtain ⟨hn, ho⟩ := ih (index+1) expected h
          constructor
          · simpa [hm] using hn
          · simpa [Evaluation.collectOutputs, hm, decode_encode_slot, Value.eval, hp] using
              congrArg (fun rest => Polynomial.eval x p :: rest) ho
        · contradiction

def program (candidate : Candidate shape) : List (Evaluation.TimedAction candidate.configuration) :=
  sort (candidate.schedule.map (fun s => ⟨s.cycle, ⟨s.lane, s.instruction⟩⟩)) (fun a b => a.cycle ≤ b.cycle)

theorem program_eq (candidate : Candidate shape) : program candidate = Evaluation.program candidate := by
  unfold program Evaluation.program
  rw [sort_eq]

/-- The checker produces diagnostics or completion cycles. Success has a
single soundness theorem against the existing machine and workload. -/
def check (p : Problem a) (candidate : Candidate a.shape) (boundaries maxTerms : Nat) : Except Diagnostic Nat := do
  let values ← (makeInputs p.box a.shape.inputCount maxTerms).mapError Diagnostic.inputBounds
  let initial := writeInputs candidate.layout.inputs values (State.empty p.box candidate.configuration)
  let result ← run maxTerms boundaries 0 (program candidate) initial
  checkOutputs result.state 0 candidate.layout.outputs p.outputs
  return result.cycles

theorem check_sound (p : Problem a) (candidate : Candidate a.shape) (boundaries maxTerms cycles : Nat)
    (h : check p candidate boundaries maxTerms = .ok cycles) (x : spec.Input) (hx : spec.AllowedInput x) :
    ∃ record, Evaluation.executeValues candidate (a.encode x hx) boundaries false = .success record ∧
      record.outputs = (a.outputScalars (spec.reference x)).toList := by
  unfold check at h
  rw [program_eq] at h
  cases hv : makeInputs p.box a.shape.inputCount maxTerms with
  | error e => simp [hv, Except.mapError, bind, Except.bind] at h
  | ok values =>
    simp only [hv, Except.mapError, bind, Except.bind] at h
    let initial := writeInputs candidate.layout.inputs values (State.empty p.box candidate.configuration)
    cases hr : run maxTerms boundaries 0 (Evaluation.program candidate) initial with
    | error e => simp [initial, hr, bind, Except.bind] at h
    | ok result =>
      change (do let result ← run maxTerms boundaries 0 (Evaluation.program candidate) initial
                 checkOutputs result.state 0 candidate.layout.outputs p.outputs
                 pure result.cycles) = .ok cycles at h
      simp only [hr, bind, Except.bind] at h
      cases ho : checkOutputs result.state 0 candidate.layout.outputs p.outputs with
      | error e => simp [ho, bind, Except.bind] at h
      | ok u =>
        cases u
        have hbox := p.input_sound x hx
        have hi : initial.eval (environment a x) hbox = Evaluation.initialState candidate.configuration
            candidate.layout (a.encode x hx) := by
          have hvalues := makeInputs_sound p.box a.shape.inputCount maxTerms values hv (a.encode x hx)
            (environment a x) hbox (fun i => by simp [environment, ScalarAdapter.encode, i.isLt])
          simp only [initial, writeInputs_eval, State.eval_empty, hvalues, Evaluation.initialState]
        obtain ⟨counts, hrun⟩ := run_sound maxTerms boundaries 0 (Evaluation.program candidate) initial result hr
          (environment a x) hbox (Evaluation.Counters.empty candidate.configuration)
        rw [hi] at hrun
        obtain ⟨hn, hout⟩ := checkOutputs_sound result.state 0 candidate.layout.outputs p.outputs ho
          (environment a x) hbox
        rw [p.output_sound x hx] at hout
        unfold Evaluation.executeValues
        rw [hrun]
        unfold Evaluation.finish
        simp only [hn, List.isEmpty_nil, ↓reduceIte]
        exact ⟨_, rfl, hout⟩

/-- A small reflected proposition avoids requiring equality of error payloads. -/
theorem check_of_toOption (p : Problem a) (candidate : Candidate a.shape) (boundaries maxTerms cycles : Nat)
    (h : (check p candidate boundaries maxTerms).toOption = some cycles) :
    check p candidate boundaries maxTerms = .ok cycles := by
  cases he : check p candidate boundaries maxTerms with
  | error e => simp [he, Except.toOption] at h
  | ok n => simpa [he, Except.toOption] using h

/-- Construct the existing proof-bearing artifact from a successful check.
Clients may obtain the premise by kernel evaluation of a closed candidate. -/
def certificate (p : Problem a) (candidate : Candidate a.shape) (boundaries maxTerms cycles : Nat)
    (h : check p candidate boundaries maxTerms = .ok cycles) : Evaluation.VerifiedCandidate a where
  candidate := candidate
  sufficientBoundaries := boundaries
  safety := by
    intro x hx
    obtain ⟨record, he, _⟩ := check_sound p candidate boundaries maxTerms cycles h x hx
    exact ⟨record, he⟩
  correctness := by
    intro x hx record he
    obtain ⟨record', he', hout⟩ := check_sound p candidate boundaries maxTerms cycles h x hx
    have hr := Evaluation.ExecutionOutcome.success.inj (he'.symm.trans he)
    subst record
    exact hout

end OptimalComputation.Certification
