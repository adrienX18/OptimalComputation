import OptimalComputation.Hardware.Instruction
import OptimalComputation.Hardware.Storage

/-! The pure executable transition for `arty-model-v1`. This module knows no
workload, candidate, reference implementation, objective, or evaluator budget.
Every issue samples one common post-commit state. Vectors bound physical storage;
checked reservations bound the pending payload list to three entries per lane. -/

namespace OptimalComputation.Hardware

inductive Effect where
  | register (destination : WritableRegister) (value : Signed48)
  | memory (address : Address) (value : Slot64)
  deriving Repr, DecidableEq, BEq

def Effect.destination : Effect → Option WritableRegister
  | .register r _ => some r
  | .memory _ _ => none

structure PendingEffect where
  due : Nat
  effect : Effect
  deriving Repr, DecidableEq, BEq

structure Action (c : ValidConfig) where
  lane : Lane c
  instruction : BoundedInstruction
  deriving Repr, DecidableEq, BEq

structure State (c : ValidConfig) where
  registers : Vector (Vector (Option Signed48) registersPerLane) c.val.lanes
  memory : Vector (Option Slot64) localMemorySlots
  pending : Vector (List PendingEffect) c.val.lanes
  deriving Repr

def zero48 : Signed48 := ⟨0, by decide⟩

def State.empty (c : ValidConfig) : State c := {
  registers := Vector.replicate _ (Vector.replicate _ none)
  memory := Vector.replicate _ none
  pending := Vector.replicate _ []
}

def State.readRegister (s : State c) (lane : Lane c) (r : Register) : Option Signed48 :=
  if r.val = 0 then some zero48 else s.registers[lane.val][r.val]

def State.readMemory (s : State c) (address : Address) : Option Slot64 :=
  s.memory[address.val]

def State.writeRegister (s : State c) (lane : Lane c)
    (r : WritableRegister) (value : Signed48) : State c :=
  { s with registers := s.registers.set lane.val (s.registers[lane.val].set r.val.val (some value) r.val.isLt) lane.isLt }

def State.writeMemory (s : State c) (address : Address) (value : Slot64) : State c :=
  { s with memory := s.memory.set address.val (some value) address.isLt }

def State.setPending (s : State c) (lane : Lane c) (pending : List PendingEffect) : State c :=
  { s with pending := s.pending.set lane.val pending lane.isLt }

def State.pendingCount (s : State c) : Nat :=
  (s.pending.toList.map List.length).foldl (· + ·) 0

def State.drained (s : State c) : Bool := s.pending.toList.all List.isEmpty

@[simp] theorem State.pending_set_same (s : State c) (l : Lane c)
    (pending : List PendingEffect) : (s.setPending l pending).pending[l.val] = pending := by
  simp [setPending]

@[simp] theorem State.pending_set_other (s : State c) (l other : Lane c)
    (pending : List PendingEffect) (h : l ≠ other) :
    (s.setPending l pending).pending[other.val] = s.pending[other.val] := by
  have h' : l.val ≠ other.val := fun e => h (Fin.ext e)
  simp [setPending, h']

@[simp] theorem State.readMemory_write_same (s : State c) (a : Address) (v : Slot64) :
    (s.writeMemory a v).readMemory a = some v := by
  simp [readMemory, writeMemory]

@[simp] theorem State.readMemory_write_other (s : State c) (a b : Address) (v : Slot64)
    (h : a ≠ b) : (s.writeMemory a v).readMemory b = s.readMemory b := by
  have h' : a.val ≠ b.val := fun e => h (Fin.ext e)
  simp [readMemory, writeMemory, h']

@[simp] theorem State.readRegister_write_same (s : State c) (l : Lane c)
    (r : WritableRegister) (v : Signed48) :
    (s.writeRegister l r v).readRegister l r.val = some v := by
  simp [readRegister, writeRegister, r.property]

@[simp] theorem State.readRegister_zero (s : State c) (l : Lane c) :
    s.readRegister l ⟨0, by decide⟩ = some zero48 := by
  rfl

@[simp] theorem State.readRegister_write_other_register (s : State c) (l : Lane c)
    (r : WritableRegister) (other : Register) (v : Signed48) (h : r.val ≠ other) :
    (s.writeRegister l r v).readRegister l other = s.readRegister l other := by
  have h' : r.val.val ≠ other.val := fun e => h (Fin.ext e)
  simp [readRegister, writeRegister, h']

@[simp] theorem State.readRegister_write_other_lane (s : State c) (l other : Lane c)
    (r : WritableRegister) (read : Register) (v : Signed48) (h : l ≠ other) :
    (s.writeRegister l r v).readRegister other read = s.readRegister other read := by
  have h' : l.val ≠ other.val := fun e => h (Fin.ext e)
  simp [readRegister, writeRegister, h']

@[simp] theorem State.readRegister_write_memory (s : State c) (l : Lane c) (r : Register)
    (a : Address) (v : Slot64) :
    (s.writeMemory a v).readRegister l r = s.readRegister l r := rfl

@[simp] theorem State.readMemory_write_register (s : State c) (l : Lane c)
    (r : WritableRegister) (a : Address) (v : Signed48) :
    (s.writeRegister l r v).readMemory a = s.readMemory a := rfl

@[simp] theorem State.readRegister_setPending (s : State c) (l other : Lane c)
    (r : Register) (pending : List PendingEffect) :
    (s.setPending l pending).readRegister other r = s.readRegister other r := rfl

@[simp] theorem State.readMemory_setPending (s : State c) (l : Lane c)
    (a : Address) (pending : List PendingEffect) :
    (s.setPending l pending).readMemory a = s.readMemory a := rfl

@[simp] theorem State.empty_readMemory (c : ValidConfig) (a : Address) :
    (State.empty c).readMemory a = none := by simp [readMemory, empty]

@[simp] theorem State.empty_readRegister (c : ValidConfig) (l : Lane c) (r : Register) :
    (State.empty c).readRegister l r = if r.val = 0 then some zero48 else none := by
  simp [readRegister, empty]

inductive MachineRule where
  | issueCollision
  | bankCapacity (bank accesses : Nat)
  | addressConflict (address : Nat)
  | pendingRead (register : Nat)
  | pendingWrite (register : Nat)
  | writebackCollision (due : Nat)
  | pendingCapacity (outstanding : Nat)
  | uninitializedRegister (register : Nat)
  | uninitializedMemory (address : Nat)
  | arithmetic (reason : ArithmeticError)
  /-- These diagnose hand-built states passed directly to `step`; normal
  execution starts empty and reserves every completion before enqueueing it. -/
  | overdueCompletion (due : Nat)
  deriving Repr, DecidableEq, BEq

structure MachineError where
  cycle : Nat
  lane : Option Nat
  rule : MachineRule
  deriving Repr, DecidableEq, BEq

inductive Event where
  | issued (cycle lane : Nat) (instruction : RawInstruction) (due : Nat)
  | committed (cycle lane : Nat) (effect : Effect)
  /-- Lane occupied during [cycle, cycle+1), after this boundary's issue. -/
  | active (cycle lane : Nat)
  deriving Repr, DecidableEq, BEq

/-- The version-one latency rule, shared by reservation, traces and execution. -/
def latency : BoundedInstruction → Nat
  | .load _ _ | .store _ _ => 1
  | .add _ _ _ | .multiply _ _ _ | .multiplyAdd _ _ _ _ => 3

def registerPending (s : State c) (lane : Lane c) (r : Register) : Bool :=
  (s.pending[lane.val]).any fun p => p.effect.destination.any (fun d => d.val == r)

def readReady (t : Nat) (s : State c) (lane : Lane c) (r : Register) :
    Except MachineError Signed48 := do
  if registerPending s lane r then throw ⟨t, some lane.val, .pendingRead r.val⟩
  match s.readRegister lane r with
  | some value => return value
  | none => throw ⟨t, some lane.val, .uninitializedRegister r.val⟩

/-- Reserve before sampling; a destination can also be an old-value source. -/
def checkReservation (t : Nat) (s : State c) (a : Action c) : Except MachineError Unit := do
  let pending := s.pending[a.lane.val]
  if pending.length ≥ pendingInstructionsPerLane then
    throw ⟨t, some a.lane.val, .pendingCapacity pending.length⟩
  if let some r := a.instruction.destination then
    if registerPending s a.lane r.val then
      throw ⟨t, some a.lane.val, .pendingWrite r.val.val⟩
    if pending.any (fun p => p.due == t + latency a.instruction && p.effect.destination.isSome) then
      throw ⟨t, some a.lane.val, .writebackCollision (t + latency a.instruction)⟩

/-- Capture an instruction's entire payload at issue; no deferred operand read
and no reference computation can contribute a value at completion. -/
def prepare (t : Nat) (s : State c) (a : Action c) : Except MachineError PendingEffect := do
  checkReservation t s a
  let read := readReady t s a.lane
  let arithmetic := fun result => result.mapError (fun e =>
    MachineError.mk t (some a.lane.val) (.arithmetic e))
  let effect ← match a.instruction with
    | .load d address =>
        match s.readMemory address with
        | some value => pure (Effect.register d (decodeSlot value))
        | none => throw ⟨t, some a.lane.val, .uninitializedMemory address.val⟩
    | .store r address => do
        let value ← read r
        pure (.memory address (encodeSlot value))
    | .add d l r => do
        let left ← read l
        let right ← read r
        pure (.register d (← arithmetic (checkedAdd left.val right.val)))
    | .multiply d l r => do
        let left ← read l
        let right ← read r
        pure (.register d (← arithmetic (checkedMul left.val right.val)))
    | .multiplyAdd d l r acc => do
        let left ← read l
        let right ← read r
        let accumulator ← read acc
        pure (.register d (← arithmetic (checkedMac left.val right.val accumulator.val)))
  return ⟨t + latency a.instruction, effect⟩

/-- Canonical lane order makes both traces and failure selection independent of
list order. Duplicate lanes fail before any per-instruction inspection. -/
def canonicalActions (actions : List (Action c)) : List (Action c) :=
  actions.mergeSort (fun a b => a.lane.val ≤ b.lane.val)

def checkBatch (t : Nat) (actions : List (Action c)) : Except MachineError Unit := do
  for lane in List.finRange c.val.lanes do
    if (actions.filter (fun a => a.lane == lane)).length > instructionsPerLanePerCycle then
      throw ⟨t, some lane.val, .issueCollision⟩
  let accesses := actions.filterMap (fun a => a.instruction.memoryAccess)
  for bank in List.finRange c.val.banks do
    let count := (accesses.filter (fun (_, address) => bankOf c address == bank)).length
    if count > bankPorts then throw ⟨t, none, .bankCapacity bank.val count⟩
  for (kind, address) in accesses do
    if kind == .write && (accesses.filter (fun (_, b) => b == address)).length > 1 then
      throw ⟨t, none, .addressConflict address.val⟩

def applyEffect (s : State c) (lane : Lane c) : Effect → State c
  | .register r value => s.writeRegister lane r value
  | .memory address value => s.writeMemory address value

/-- Commit in lane order. Legal reservations guarantee disjoint register writes;
same-address stores cannot share a due boundary because memory latency is one. -/
def commit (t : Nat) (s : State c) : Except MachineError (State c × List Event) := do
  let mut state := s
  let mut events := []
  for lane in List.finRange c.val.lanes do
    let pending := s.pending[lane.val]
    if let some p := pending.find? (fun p => p.due < t) then
      throw ⟨t, some lane.val, .overdueCompletion p.due⟩
    let due := pending.filter (fun p => p.due == t)
    if (due.filter (fun p => p.effect.destination.isSome)).length > resultWritesPerLanePerCycle then
      throw ⟨t, some lane.val, .writebackCollision t⟩
    state := state.setPending lane (pending.filter (fun p => p.due != t))
    for p in due do
      state := applyEffect state lane p.effect
      events := events ++ [.committed t lane.val p.effect]
  return (state, events)

/-- Enqueue only after *all* simultaneous instructions have been checked and
sampled against the same state. This also makes a failing boundary atomic. -/
def enqueue (s : State c) (prepared : List (Action c × PendingEffect)) : State c :=
  prepared.foldl (fun state (action, p) =>
    state.setPending action.lane (state.pending[action.lane.val] ++ [p])) s

/-- One boundary: completion, simultaneous issue, then interval activity.
Empty actions are explicit waiting and still commit pending operations. -/
def step (t : Nat) (actions : List (Action c)) (s : State c) :
    Except MachineError (State c × List Event) := do
  let (committed, completionEvents) ← commit t s
  let actions := canonicalActions actions
  checkBatch t actions
  let prepared ← actions.mapM (fun a => do return (a, ← prepare t committed a))
  let next := enqueue committed prepared
  let issueEvents := prepared.map (fun (a, p) => Event.issued t a.lane.val a.instruction.toRaw p.due)
  let activeEvents := (List.finRange c.val.lanes).filterMap (fun lane =>
    if (next.pending[lane.val]).isEmpty then none else some (Event.active t lane.val))
  return (next, completionEvents ++ issueEvents ++ activeEvents)

end OptimalComputation.Hardware
