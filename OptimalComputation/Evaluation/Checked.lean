import OptimalComputation.Evaluation.Verification

namespace OptimalComputation.Evaluation
open Hardware Candidates Workloads

inductive WorkloadInputError where
  | transport (reason : InputError)
  | outsideDomain (workload : String)
  | noncanonicalScalars
  deriving Repr, DecidableEq, BEq

/-- One diagnostic vocabulary shared by inspection, simulation and verification.
Resource exhaustion is deliberately an outcome, never an invalidity diagnosis. -/
inductive Failure where
  | invalidInput (reason : WorkloadInputError)
  | inadmissibleConfiguration (reason : ConfigError)
  | malformedLayout (reason : LayoutError)
  | malformedCandidate (reason : CandidateError)
  | structuralBindingMismatch
  | malformedInstruction (reason : ScheduleError)
  | illegalSchedule (reason : MachineError)
  | arithmeticFailure (reason : MachineError)
  | incompleteOutput (boundary : Nat) (addresses : List Nat)
  | unverifiedCandidate (identifier : String)
  deriving Repr, DecidableEq, BEq

def structuralFailure : CandidateError → Failure
  | .configuration reason => .inadmissibleConfiguration reason
  | .layout reason => .malformedLayout reason
  | .schedule reason => .malformedInstruction reason
  | reason => .malformedCandidate reason

def machineFailure (reason : MachineError) : Failure :=
  match reason.rule with
  | .arithmetic _ => .arithmeticFailure reason
  | _ => .illegalSchedule reason

def executionFailure : ExecutionError → Failure
  | .invalidInput reason => .invalidInput (.transport reason)
  | .machine reason => machineFailure reason
  | .incompleteOutputs boundary addresses => .incompleteOutput boundary addresses

/-- Inspection proves exact serialization binding as well as the structural
invariants carried by Candidate. No proof of execution or correctness is inferred. -/
def inspect (shape : Shape) (raw : RawCandidate) :
    Except Failure { candidate : Candidate shape // candidate.toRaw = raw } := do
  let candidate ← (validateCandidate shape raw).mapError structuralFailure
  if h : candidate.toRaw = raw then return ⟨candidate, h⟩
  else throw .structuralBindingMismatch

theorem inspect_roundtrip (candidate : Candidate shape) :
    inspect shape candidate.toRaw = .ok ⟨candidate, rfl⟩ := by
  simp [inspect, validateCandidate_roundtrip, Except.mapError, bind, Except.bind, pure, Except.pure]

/-- These predicates state the accepted raw file's configuration and exact
layout/schedule binding, using the same typed representation as execution. -/
def StructurallyValid (shape : Shape) (raw : RawCandidate) : Prop :=
  ∃ candidate : Candidate shape, candidate.toRaw = raw

theorem inspect_sound {checked : { candidate : Candidate shape // candidate.toRaw = raw }}
    (_ : inspect shape raw = .ok checked) : StructurallyValid shape raw :=
  ⟨checked.val, checked.property⟩

def actionsAt (candidate : Candidate shape) (t : Nat) : List (Action candidate.configuration) :=
  (candidate.schedule.filter (fun i => i.cycle == t)).map (fun i => ⟨i.lane, i.instruction⟩)

def StaticScheduleLegal (candidate : Candidate shape) : Prop :=
  ∀ i ∈ candidate.schedule, BatchLegal (actionsAt candidate i.cycle)

/-- Sorting changes diagnostic selection, not the declarative batch rules. -/
private theorem batchLegal_of_canonical {actions : List (Action c)}
    (h : BatchLegal (canonicalActions actions)) : BatchLegal actions := by
  have p := List.mergeSort_perm actions (fun a b => a.lane.val ≤ b.lane.val)
  change List.Perm (canonicalActions actions) actions at p
  have pm := p.filterMap (fun a => a.instruction.memoryAccess)
  refine ⟨?_, ?_, ?_⟩
  · intro lane
    simpa only [(p.filter (fun a => a.lane == lane)).length_eq] using h.1 lane
  · intro bank
    simpa only [(pm.filter (fun (_, address) => bankOf c address == bank)).length_eq]
      using h.2.1 bank
  · intro kind address hm hw
    have bound := h.2.2 kind address (pm.mem_iff.mpr hm) hw
    simpa only [(pm.filter (fun (_, b) => b == address)).length_eq] using bound

/-- Check boundaries in increasing cycle order and actions in lane order, so
permuting a schedule does not choose a different first static violation.
Hardware.checkBatch still determines rule priority and legality. Readiness,
initialization, widths and termination remain execution obligations. -/
def checkStatic (candidate : Candidate shape) : Except MachineError Unit := do
  for i in candidate.schedule.mergeSort (fun a b => a.cycle ≤ b.cycle) do
    checkBatch i.cycle (canonicalActions (actionsAt candidate i.cycle))

theorem checkStatic_sound {candidate : Candidate shape}
    (h : checkStatic candidate = .ok ()) : StaticScheduleLegal candidate := by
  unfold checkStatic at h
  simp only [bind, Except.bind, pure, Except.pure] at h
  split at h
  · contradiction
  · rename_i result hr
    have all := forIn_yield_all _ _ (fun i => BatchLegal (actionsAt candidate i.cycle)) ?_ hr
    · intro i hi
      exact all i (List.mem_mergeSort.mpr hi)
    intro i _ current next hn
    cases hc : checkBatch i.cycle (canonicalActions (actionsAt candidate i.cycle)) with
    | error e => simp [hc] at hn
    | ok u =>
      cases u
      simp only [hc, Except.ok.injEq] at hn
      exact ⟨_, hn.symm, batchLegal_of_canonical (checkBatch_sound hc)⟩

/-- Parsing uses the workload codec and checks its domain before any execution.
The roundtrip check prevents a permissive decoder from discarding raw scalars. -/
def parseInput (adapter : ScalarAdapter spec) [∀ x, Decidable (spec.AllowedInput x)]
    (values : List Int) : Except Failure {x : spec.Input // spec.AllowedInput x} := do
  if h : values.length = adapter.shape.inputCount then
    let vector : Vector Int adapter.shape.inputCount := ⟨values.toArray, by simpa using h⟩
    let x := adapter.decodeInput vector
    if hx : spec.AllowedInput x then
      if adapter.inputScalars x = vector then return ⟨x, hx⟩
      else throw (.invalidInput .noncanonicalScalars)
    else throw (.invalidInput (.outsideDomain spec.identifier))
  else throw (.invalidInput (.transport (.wrongScalarCount adapter.shape.inputCount values.length)))

/-- Result of running an unverified candidate. There is deliberately no
verified case: certified results exist only as `CertifiedExecution` evidence. -/
inductive Outcome where
  | simulated (record : ExecutionRecord)
  | failure (reason : Failure)
  | resourceExhausted (details : Exhaustion)
  deriving Repr, DecidableEq, BEq

/-- Arbitrary serialized candidates remain simulated, regardless of how many
inputs succeed. No field supplied by the candidate controls verification status. -/
def simulate (shape : Shape) (raw : RawCandidate) (inputs : List Int)
    (boundaries : Nat) (captureTrace : Bool := true) : Outcome :=
  match inspect shape raw with
  | .error e => .failure e
  | .ok checked =>
    match execute checked.val inputs boundaries captureTrace with
    | .success record => .simulated record
    | .failure reason => .failure (executionFailure reason)
    | .resourceExhausted details => .resourceExhausted details

/-- Every completion is due at most three boundaries after issue
(`Hardware.latency_le_three`), so boundaries `0 … lastIssueCycle + 3` let any
run that does not fail finish. Idle boundaries still cost evaluation time, so
callers facing untrusted cycle values should cap this budget. -/
def sufficientSimulationBoundaries (raw : RawCandidate) : Nat :=
  raw.schedule.foldl (fun last entry => max last entry.cycle) 0 + 4

theorem parseInput_values (adapter : ScalarAdapter spec) [∀ x, Decidable (spec.AllowedInput x)]
    {values : List Int} {input : {x : spec.Input // spec.AllowedInput x}}
    (h : parseInput adapter values = .ok input) : (adapter.inputScalars input.val).toList = values := by
  unfold parseInput at h
  split at h
  · dsimp only at h
    split at h
    · split at h
      · rename_i he
        simp only [pure, Except.pure, Except.ok.injEq] at h
        cases h
        rw [he]
        simp [Vector.toList]
      · contradiction
    · contradiction
  · contradiction

end OptimalComputation.Evaluation
