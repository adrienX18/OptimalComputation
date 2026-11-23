import OptimalComputation.Candidates.Layout
import OptimalComputation.Versions

/-! Structural validation is intentionally distinct from successful execution.
No register/memory values or initial runtime state are supplied by a candidate. -/

namespace OptimalComputation.Candidates

open Hardware Workloads

structure RawScheduledInstruction where
  cycle : Nat
  lane : Nat
  instruction : RawInstruction
  deriving Repr, DecidableEq, BEq

def MemoryAllowed (layout : Layout shape) : BoundedInstruction → Prop
  | .load _ a => a ∈ layout.declared
  | .store _ a => a ∈ layout.writable
  | .add _ _ _ | .multiply _ _ _ | .multiplyAdd _ _ _ _ => True

instance (layout : Layout shape) (i : BoundedInstruction) : Decidable (MemoryAllowed layout i) := by
  cases i <;> simp only [MemoryAllowed] <;> infer_instance

/-- Registers are lane-local because an instruction has exactly one lane and
contains only local register indices. No operand can name a different lane. -/
structure ScheduledInstruction (config : ValidConfig) (layout : Layout shape) where
  cycle : Nat
  lane : Lane config
  instruction : BoundedInstruction
  memoryAllowed : MemoryAllowed layout instruction
  deriving Repr

theorem ScheduledInstruction.store_not_input
    (s : ScheduledInstruction config layout) {r : Register} {a : Address}
    (h : s.instruction = .store r a) : a ∉ layout.inputs := by
  apply layout.writable_not_input
  simpa [h, MemoryAllowed] using s.memoryAllowed

theorem ScheduledInstruction.load_declared
    (s : ScheduledInstruction config layout) {r : WritableRegister} {a : Address}
    (h : s.instruction = .load r a) : a ∈ layout.declared := by
  simpa [h, MemoryAllowed] using s.memoryAllowed

inductive ScheduleRule where
  | laneOutOfBounds (lane laneCount : Nat)
  | invalidInstruction (reason : InstructionError)
  | undeclaredRead (address : Nat)
  | undeclaredWrite (address : Nat)
  | writeToInput (address : Nat)
  deriving Repr, DecidableEq, BEq

structure ScheduleError where
  index : Nat
  cycle : Nat
  lane : Nat
  rule : ScheduleRule
  deriving Repr, DecidableEq, BEq

private def validateMemory (layout : Layout shape) (i : BoundedInstruction) :
    Except ScheduleRule { i : BoundedInstruction // MemoryAllowed layout i } :=
  match i with
  | .load r a =>
      if h : a ∈ layout.declared then .ok ⟨.load r a, h⟩
      else .error (.undeclaredRead a.val)
  | .store r a =>
      if h : a ∈ layout.writable then .ok ⟨.store r a, h⟩
      else if a ∈ layout.inputs then .error (.writeToInput a.val)
      else .error (.undeclaredWrite a.val)
  | .add d l r => .ok ⟨.add d l r, True.intro⟩
  | .multiply d l r => .ok ⟨.multiply d l r, True.intro⟩
  | .multiplyAdd d l r a => .ok ⟨.multiplyAdd d l r a, True.intro⟩

def validateScheduled (config : ValidConfig) (layout : Layout shape)
    (index : Nat) (raw : RawScheduledInstruction) :
    Except ScheduleError (ScheduledInstruction config layout) := do
  let failure := fun rule => ScheduleError.mk index raw.cycle raw.lane rule
  if hl : raw.lane < config.val.lanes then
    let instruction ← (validateInstruction raw.instruction).mapError
      (fun e => failure (.invalidInstruction e))
    let checked ← (validateMemory layout instruction).mapError failure
    return ⟨raw.cycle, ⟨raw.lane, hl⟩, checked.val, checked.property⟩
  else throw (failure (.laneOutOfBounds raw.lane config.val.lanes))

def ScheduledInstruction.toRaw (s : ScheduledInstruction config layout) : RawScheduledInstruction :=
  ⟨s.cycle, s.lane.val, s.instruction.toRaw⟩

private theorem validateMemory_roundtrip (layout : Layout shape) (i : BoundedInstruction)
    (h : MemoryAllowed layout i) : validateMemory layout i = .ok ⟨i, h⟩ := by
  cases i <;> simp only [MemoryAllowed] at h <;> simp [validateMemory, h]

theorem validateScheduled_roundtrip (s : ScheduledInstruction config layout) (index : Nat) :
    validateScheduled config layout index s.toRaw = .ok s := by
  simp [validateScheduled, ScheduledInstruction.toRaw, s.lane.isLt,
    validateInstruction_roundtrip, validateMemory_roundtrip layout s.instruction s.memoryAllowed,
    Except.mapError, bind, Except.bind, pure, Except.pure]

def validateSchedule (config : ValidConfig) (layout : Layout shape) :
    Nat → List RawScheduledInstruction →
      Except ScheduleError (List (ScheduledInstruction config layout))
  | _, [] => .ok []
  | index, i :: rest => do
      let checked ← validateScheduled config layout index i
      return checked :: (← validateSchedule config layout (index + 1) rest)

theorem validateSchedule_roundtrip (schedule : List (ScheduledInstruction config layout))
    (index : Nat) :
    validateSchedule config layout index (schedule.map ScheduledInstruction.toRaw) =
      .ok schedule := by
  induction schedule generalizing index with
  | nil => rfl
  | cons s rest ih =>
      simp [validateSchedule, validateScheduled_roundtrip, ih,
        bind, Except.bind, pure, Except.pure]

structure RawCandidate where
  identifier : String
  workloadIdentifier : String
  modelVersion : String := Versions.model
  formatVersion : String := Versions.candidate
  configuration : Config
  layout : RawLayout
  schedule : List RawScheduledInstruction
  deriving Repr, DecidableEq, BEq

/-- Every field required by future execution is bound in this value. This type
proves structural validity only, never all-input safety or correctness. -/
structure Candidate (shape : Shape) where
  identifier : String
  identifier_nonempty : identifier ≠ ""
  configuration : ValidConfig
  layout : Layout shape
  schedule : List (ScheduledInstruction configuration layout)
  deriving Repr

def Candidate.modelVersion (_ : Candidate shape) : String := Versions.model
def Candidate.formatVersion (_ : Candidate shape) : String := Versions.candidate
def Candidate.workloadIdentifier (_ : Candidate shape) : String := shape.identifier

inductive CandidateError where
  | emptyIdentifier
  | wrongModelVersion (expected actual : String)
  | wrongFormatVersion (expected actual : String)
  | wrongWorkloadIdentifier (expected actual : String)
  | configuration (reason : ConfigError)
  | layout (reason : LayoutError)
  | schedule (reason : ScheduleError)
  deriving Repr, DecidableEq, BEq

/-- Check against a trusted expected shape, not counts supplied by a candidate.
Instruction order is preserved; issue cycles carry all timing information.
Hazards, initialization, bank limits and completion are execution obligations. -/
def validateCandidate (shape : Shape) (raw : RawCandidate) :
    Except CandidateError (Candidate shape) := do
  if hi : raw.identifier ≠ "" then
    if raw.modelVersion ≠ Versions.model then
      throw (.wrongModelVersion Versions.model raw.modelVersion)
    if raw.formatVersion ≠ Versions.candidate then
      throw (.wrongFormatVersion Versions.candidate raw.formatVersion)
    if raw.workloadIdentifier ≠ shape.identifier then
      throw (.wrongWorkloadIdentifier shape.identifier raw.workloadIdentifier)
    let configuration ← (validateConfig raw.configuration).mapError .configuration
    let layout ← (validateLayout shape raw.layout).mapError .layout
    let schedule ← (validateSchedule configuration layout 0 raw.schedule).mapError .schedule
    return ⟨raw.identifier, hi, configuration, layout, schedule⟩
  else throw .emptyIdentifier

def Candidate.toRaw (candidate : Candidate shape) : RawCandidate := {
  identifier := candidate.identifier
  workloadIdentifier := shape.identifier
  configuration := candidate.configuration.val
  layout := candidate.layout.toRaw
  schedule := candidate.schedule.map ScheduledInstruction.toRaw
}

/-- Proof-bearing candidates can be serialized and revalidated unchanged.
This theorem does not assert execution safety or correctness. -/
theorem validateCandidate_roundtrip (candidate : Candidate shape) :
    validateCandidate shape candidate.toRaw = .ok candidate := by
  simp [validateCandidate, Candidate.toRaw, candidate.identifier_nonempty,
    validateConfig_accepts _ candidate.configuration.property,
    validateLayout_roundtrip, validateSchedule_roundtrip,
    Except.mapError, bind, Except.bind, pure, Except.pure]

end OptimalComputation.Candidates
