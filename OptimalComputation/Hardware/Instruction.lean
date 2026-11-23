import OptimalComputation.Hardware.Config

/-! The five fixed primitives, with no workload-specific operation. Operands are
local to the issuing lane. This file describes syntax, not execution or timing. -/

namespace OptimalComputation.Hardware

abbrev Register := Fin registersPerLane
abbrev WritableRegister := { r : Register // r.val ≠ 0 }
abbrev Lane (c : ValidConfig) := Fin c.val.lanes

/-- Sharing the syntax between unchecked and bounded forms prevents extra raw
opcodes or hidden operations from entering the format. -/
inductive Instruction (reg dst addr : Type) where
  | load (destination : dst) (address : addr)
  | store (source : reg) (address : addr)
  | add (destination : dst) (left right : reg)
  | multiply (destination : dst) (left right : reg)
  | multiplyAdd (destination : dst) (left right accumulator : reg)
  deriving Repr, DecidableEq, BEq

abbrev RawInstruction := Instruction Nat Nat Nat
abbrev BoundedInstruction := Instruction Register WritableRegister Address

def Instruction.reads : Instruction reg dst addr → List reg
  | .load _ _ => []
  | .store source _ => [source]
  | .add _ left right | .multiply _ left right => [left, right]
  | .multiplyAdd _ left right accumulator => [left, right, accumulator]

def Instruction.destination : Instruction reg dst addr → Option dst
  | .store _ _ => none
  | .load d _ | .add d _ _ | .multiply d _ _ | .multiplyAdd d _ _ _ => some d

inductive AccessKind where
  | read | write
  deriving Repr, DecidableEq, BEq

def Instruction.memoryAccess : Instruction reg dst addr → Option (AccessKind × addr)
  | .load _ a => some (.read, a)
  | .store _ a => some (.write, a)
  | .add _ _ _ | .multiply _ _ _ | .multiplyAdd _ _ _ _ => none

theorem Instruction.reads_le_three (i : Instruction reg dst addr) :
    i.reads.length ≤ operandReadsPerLanePerCycle := by
  cases i <;> simp [Instruction.reads, operandReadsPerLanePerCycle]

theorem destination_ne_zero (i : BoundedInstruction) (r : WritableRegister)
    (_h : i.destination = some r) : r.val.val ≠ 0 := r.property

inductive InstructionError where
  | registerOutOfBounds (register : Nat)
  | zeroRegisterDestination
  | addressOutOfBounds (address : Nat)
  deriving Repr, DecidableEq, BEq

def validateRegister (n : Nat) : Except InstructionError Register :=
  if h : n < registersPerLane then .ok ⟨n, h⟩
  else .error (.registerOutOfBounds n)

def validateDestination (n : Nat) : Except InstructionError WritableRegister := do
  let r ← validateRegister n
  if h : r.val ≠ 0 then .ok ⟨r, h⟩
  else .error .zeroRegisterDestination

def validateAddress (n : Nat) : Except InstructionError Address :=
  if h : n < localMemorySlots then .ok ⟨n, h⟩
  else .error (.addressOutOfBounds n)

def validateInstruction : RawInstruction → Except InstructionError BoundedInstruction
  | .load d a => return .load (← validateDestination d) (← validateAddress a)
  | .store s a => return .store (← validateRegister s) (← validateAddress a)
  | .add d l r => return .add (← validateDestination d) (← validateRegister l) (← validateRegister r)
  | .multiply d l r =>
      return .multiply (← validateDestination d) (← validateRegister l) (← validateRegister r)
  | .multiplyAdd d l r a =>
      return .multiplyAdd (← validateDestination d) (← validateRegister l)
        (← validateRegister r) (← validateRegister a)

def BoundedInstruction.toRaw : BoundedInstruction → RawInstruction
  | .load d a => .load d.val.val a.val
  | .store s a => .store s.val a.val
  | .add d l r => .add d.val.val l.val r.val
  | .multiply d l r => .multiply d.val.val l.val r.val
  | .multiplyAdd d l r a => .multiplyAdd d.val.val l.val r.val a.val

@[simp] theorem validateRegister_accepts (r : Register) : validateRegister r.val = .ok r := by
  simp [validateRegister, r.isLt]

@[simp] theorem validateDestination_accepts (r : WritableRegister) :
    validateDestination r.val.val = .ok r := by
  simp [validateDestination, bind, Except.bind, r.property]

@[simp] theorem validateAddress_accepts (a : Address) : validateAddress a.val = .ok a := by
  simp [validateAddress, a.isLt]

theorem validateInstruction_roundtrip (i : BoundedInstruction) :
    validateInstruction i.toRaw = .ok i := by
  cases i <;> simp [BoundedInstruction.toRaw, validateInstruction, bind,
    Except.bind, pure, Except.pure]

end OptimalComputation.Hardware
