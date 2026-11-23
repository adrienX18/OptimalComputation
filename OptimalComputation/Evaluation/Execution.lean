import OptimalComputation.Hardware.Machine
import OptimalComputation.Hardware.Resources
import OptimalComputation.Candidates.Program

/-! Objective-free execution. The only machine transition is `Hardware.step`.
Scalar input validation checks transport width/count, not a workload's allowed
input predicate or correctness; those belong to the later verification layer. -/

namespace OptimalComputation.Evaluation

open Hardware Candidates Workloads

structure Counters where
  loads : Nat := 0
  stores : Nat := 0
  additions : Nat := 0
  multiplications : Nat := 0
  multiplyAdds : Nat := 0
  registerReads : Nat := 0
  registerWrites : Nat := 0
  bankAccesses : List Nat
  laneIssues : List Nat
  laneCompletions : List Nat
  laneActiveCycles : List Nat
  deriving Repr, DecidableEq, BEq

def Counters.empty (c : ValidConfig) : Counters := {
  bankAccesses := List.replicate c.val.banks 0
  laneIssues := List.replicate c.val.lanes 0
  laneCompletions := List.replicate c.val.lanes 0
  laneActiveCycles := List.replicate c.val.lanes 0
}

def incrementAt (counts : List Nat) (index : Nat) : List Nat :=
  counts.zipIdx.map (fun (count, i) => if i = index then count + 1 else count)

/-- Register r0 reads are charged, including repeated operands. A MAC is one
MAC event, never also an addition/multiplication. Stores have no register write. -/
def Counters.record (c : ValidConfig) (counts : Counters) : Event → Counters
  | .issued _ lane instruction _ =>
      let counts := { counts with
        registerReads := counts.registerReads + instruction.reads.length
        laneIssues := incrementAt counts.laneIssues lane }
      let counts := match instruction.memoryAccess with
        | none => counts
        | some (_, address) =>
            { counts with bankAccesses := incrementAt counts.bankAccesses (address % c.val.banks) }
      match instruction with
      | .load _ _ => { counts with loads := counts.loads + 1 }
      | .store _ _ => { counts with stores := counts.stores + 1 }
      | .add _ _ _ => { counts with additions := counts.additions + 1 }
      | .multiply _ _ _ => { counts with multiplications := counts.multiplications + 1 }
      | .multiplyAdd _ _ _ _ => { counts with multiplyAdds := counts.multiplyAdds + 1 }
  | .committed _ lane effect =>
      { counts with
        registerWrites := counts.registerWrites + (if effect.destination.isSome then 1 else 0)
        laneCompletions := incrementAt counts.laneCompletions lane }
  | .active _ lane => { counts with laneActiveCycles := incrementAt counts.laneActiveCycles lane }

def Counters.ofEvents (c : ValidConfig) (events : List Event) : Counters :=
  events.foldl (Counters.record c) (Counters.empty c)

structure TimedAction (c : ValidConfig) where
  cycle : Nat
  action : Action c
  deriving Repr

/-- Sort once, then consume each instruction once. Equal-cycle list order is
irrelevant: `step` canonicalizes the complete boundary batch before inspection. -/
def program (candidate : Candidate shape) : List (TimedAction candidate.configuration) :=
  (candidate.schedule.map (fun i => ⟨i.cycle, ⟨i.lane, i.instruction⟩⟩)).mergeSort
    (fun a b => a.cycle ≤ b.cycle)

/-- Inputs alone are initialized. Each is encoded into its full canonical slot.
The vector length is tied to the trusted layout's scalar count. -/
def initialState (config : ValidConfig) (layout : Layout shape)
    (inputs : Vector Signed48 shape.inputCount) : State config :=
  (layout.inputs.zip inputs.toList).foldl
    (fun state (address, value) => state.writeMemory address (encodeSlot value)) (State.empty config)

structure BoundaryTrace where
  cycle : Nat
  events : List Event
  deriving Repr, DecidableEq, BEq

structure Exhaustion where
  nextBoundary : Nat
  issuedInstructions : Nat
  remainingInstructions : Nat
  pendingEffects : Nat
  deriving Repr, DecidableEq, BEq

structure RunResult (c : ValidConfig) where
  elapsedCycles : Nat
  state : State c
  counters : Counters
  /-- Empty when tracing was disabled; counters are always collected. -/
  trace : List BoundaryTrace
  deriving Repr

inductive RunOutcome (c : ValidConfig) where
  | finished (result : RunResult c)
  | failed (error : MachineError)
  | exhausted (details : Exhaustion)
  deriving Repr

/-- Fuel counts processed boundaries, including boundary zero. Exhaustion is
inconclusive, never schedule invalidity. Finishing checks precede fuel checks,
so an empty zero-output program can finish with zero fuel at elapsed cycle zero.

This structural recursion and the public `step`/state updates are shared proof
surfaces; there is no second, proof-only machine. A valid queue is `program p`
or one of its suffixes; the evaluator does not skip idle boundaries. -/
def run (captureTrace : Bool) :
    Nat → Nat → List (TimedAction c) → State c → Counters → List BoundaryTrace → RunOutcome c
  | fuel, boundary, queue, state, counters, reversedTrace =>
      if queue.isEmpty && state.drained then
        .finished ⟨boundary - 1, state, counters, reversedTrace.reverse⟩
      else match fuel with
      | 0 => .exhausted ⟨boundary, counters.laneIssues.foldl (· + ·) 0,
          queue.length, state.pendingCount⟩
      | fuel + 1 =>
          let (batch, rest) := queue.span (fun i => i.cycle == boundary)
          match step boundary (batch.map TimedAction.action) state with
          | .error error => .failed error
          | .ok (next, events) =>
              run captureTrace fuel (boundary + 1) rest next
                (events.foldl (Counters.record c) counters)
                (if captureTrace then ⟨boundary, events⟩ :: reversedTrace else reversedTrace)

/-- A compositional equation for the actual runner: proofs can establish one
boundary using `step` and then reuse any theorem about the remaining run. -/
theorem run_step (captureTrace : Bool) (fuel boundary : Nat)
    (queue batch rest : List (TimedAction c)) (state next : State c)
    (counters : Counters) (reversedTrace : List BoundaryTrace) (events : List Event)
    (hn : (queue.isEmpty && state.drained) = false)
    (hq : queue.span (fun i => i.cycle == boundary) = (batch, rest))
    (hs : step boundary (batch.map TimedAction.action) state = .ok (next, events)) :
    run captureTrace (fuel + 1) boundary queue state counters reversedTrace =
      run captureTrace fuel (boundary + 1) rest next
        (events.foldl (Counters.record c) counters)
        (if captureTrace then ⟨boundary, events⟩ :: reversedTrace else reversedTrace) := by
  simp [run, hn, hq, hs]

/-- Completion includes draining all effects, even when outputs were written
before the final scheduled instruction. No fuel is needed once drained. -/
theorem run_finished (captureTrace : Bool) (fuel boundary : Nat) (state : State c)
    (counters : Counters) (reversedTrace : List BoundaryTrace) (hs : state.drained = true) :
    run captureTrace fuel boundary [] state counters reversedTrace =
      .finished ⟨boundary - 1, state, counters, reversedTrace.reverse⟩ := by
  cases fuel <;> simp [run, hs]

inductive InputError where
  | wrongScalarCount (expected actual : Nat)
  | scalarOutOfRange (index : Nat) (value : Int)
  deriving Repr, DecidableEq, BEq

def validateInputs (count : Nat) (values : List Int) : Except InputError (Vector Signed48 count) := do
  if values.length ≠ count then throw (.wrongScalarCount count values.length)
  let bounded ← values.zipIdx.mapM (fun (value, index) =>
    if h : InSigned48 value then pure (⟨value, h⟩ : Signed48)
    else throw (.scalarOutOfRange index value))
  if h : bounded.length = count then
    return ⟨bounded.toArray, by simpa using h⟩
  else throw (.wrongScalarCount count bounded.length)

structure StorageReport where
  inputSlots : Nat
  outputSlots : Nat
  scratchSlots : Nat
  declaredSlots : Nat
  declaredBytes : Nat
  deriving Repr, DecidableEq, BEq

structure ExecutionRecord where
  modelVersion : String
  candidateFormatVersion : String
  workloadIdentifier : String
  candidateIdentifier : String
  cycles : Nat
  outputs : List Int
  counters : Counters
  resources : ResourceReport
  storage : StorageReport
  scheduleSize : Nat
  trace : List BoundaryTrace
  deriving Repr, DecidableEq, BEq

inductive ExecutionError where
  | invalidInput (reason : InputError)
  | machine (reason : MachineError)
  | incompleteOutputs (boundary : Nat) (addresses : List Nat)
  deriving Repr, DecidableEq, BEq

/-- Success means this concrete run completed. It asserts neither all-input
correctness nor verification status and supplies no optimization score. -/
inductive ExecutionOutcome where
  | success (record : ExecutionRecord)
  | failure (reason : ExecutionError)
  | resourceExhausted (details : Exhaustion)
  deriving Repr, DecidableEq, BEq

def collectOutputs (addresses : List Address) (state : State c) : List Int :=
  addresses.filterMap (fun address => (state.readMemory address).map (fun v => (decodeSlot v).val))

def finish (candidate : Candidate shape) (result : RunResult candidate.configuration) :
    ExecutionOutcome :=
  let missing := candidate.layout.outputs.filter (fun a => (result.state.readMemory a).isNone)
  if missing.isEmpty then
    .success {
      modelVersion := Versions.model
      candidateFormatVersion := Versions.candidate
      workloadIdentifier := shape.identifier
      candidateIdentifier := candidate.identifier
      cycles := result.elapsedCycles
      outputs := collectOutputs candidate.layout.outputs result.state
      counters := result.counters
      resources := resourceReport candidate.configuration
      storage := {
        inputSlots := candidate.layout.inputs.length
        outputSlots := candidate.layout.outputs.length
        scratchSlots := candidate.layout.scratch.length
        declaredSlots := candidate.layout.declared.length
        declaredBytes := candidate.layout.declared.length * 8
      }
      scheduleSize := candidate.schedule.length
      trace := result.trace
    }
  else .failure (.incompleteOutputs result.elapsedCycles (missing.map Fin.val))

/-- The typed-input entry point is convenient for all-input proofs. The caller
supplies a boundary budget explicitly; no execution is silently truncated. -/
def executeValues (candidate : Candidate shape) (inputs : Vector Signed48 shape.inputCount)
    (maxBoundaries : Nat) (captureTrace : Bool := true) : ExecutionOutcome :=
  match run captureTrace maxBoundaries 0 (program candidate)
      (initialState candidate.configuration candidate.layout inputs)
      (Counters.empty candidate.configuration) [] with
  | .finished result => finish candidate result
  | .failed error => .failure (.machine error)
  | .exhausted details => .resourceExhausted details

def execute (candidate : Candidate shape) (inputs : List Int) (maxBoundaries : Nat)
    (captureTrace : Bool := true) : ExecutionOutcome :=
  match validateInputs shape.inputCount inputs with
  | .error error => .failure (.invalidInput error)
  | .ok inputs => executeValues candidate inputs maxBoundaries captureTrace

end OptimalComputation.Evaluation
