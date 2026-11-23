import OptimalComputation.Certification.Value
import Std.Data.TreeMap.Lemmas

namespace OptimalComputation.Certification
open Hardware
set_option linter.unusedSimpArgs false

inductive Effect (box : Box) where
  | register (destination : WritableRegister) (value : Value box)
  | memory (address : Address) (value : Value box)

structure Pending (box : Box) where
  due : Nat
  effect : Effect box

def Effect.destination : Effect box → Option WritableRegister
  | .register r _ => some r
  | .memory _ _ => none

def Effect.eval (x : Nat → Int) (hx : box.Allowed x) : Effect box → Hardware.Effect
  | .register r v => .register r (v.eval x hx)
  | .memory a v => .memory a (encodeSlot (v.eval x hx))

def Pending.eval (x : Nat → Int) (hx : box.Allowed x) (p : Pending box) : PendingEffect :=
  ⟨p.due, p.effect.eval x hx⟩

@[simp] theorem Effect.eval_destination (e : Effect box) (x : Nat → Int) (hx : box.Allowed x) :
    (e.eval x hx).destination = e.destination := by cases e <;> rfl
@[simp] theorem Pending.eval_due (p : Pending box) (x : Nat → Int) (hx : box.Allowed x) :
    (p.eval x hx).due = p.due := rfl
@[simp] theorem Pending.eval_destination (p : Pending box) (x : Nat → Int) (hx : box.Allowed x) :
    (p.eval x hx).effect.destination = p.effect.destination := Effect.eval_destination _ _ _

/-- Sparse memory avoids allocating 4,096 symbolic slots or scanning a growing
chain of prior stores. Its interpretation is the bounded hardware state,
including full-slot encoding at each store. -/
structure State (box : Box) (c : ValidConfig) where
  registerTable : Vector (Vector (Option (Value box)) registersPerLane) c.val.lanes
  memoryTable : Std.TreeMap Nat (Value box)
  pendingTable : Vector (List (Pending box)) c.val.lanes

def State.registers (s : State box c) (l : Lane c) (r : Register) : Option (Value box) :=
  s.registerTable[l.val][r.val]

def State.pending (s : State box c) (l : Lane c) : List (Pending box) :=
  s.pendingTable[l.val]

def State.memory (s : State box c) (a : Address) : Option (Value box) :=
  s.memoryTable[a.val]?

def State.empty (box : Box) (c : ValidConfig) : State box c :=
  ⟨Vector.replicate _ (Vector.replicate _ none), ∅, Vector.replicate _ []⟩

def State.eval (s : State box c) (x : Nat → Int) (hx : box.Allowed x) : Hardware.State c := {
  registers := Vector.ofFn fun lane => Vector.ofFn fun r => (s.registers lane r).map (·.eval x hx)
  memory := Vector.ofFn fun a => (s.memory a).map fun v => encodeSlot (v.eval x hx)
  pending := Vector.ofFn fun lane => (s.pending lane).map (·.eval x hx)
}

def State.readRegister (s : State box c) (l : Lane c) (r : Register) : Option (Value box) :=
  if r.val = 0 then some (Value.zero box) else s.registers l r

def State.writeRegister (s : State box c) (l : Lane c) (r : WritableRegister) (v : Value box) : State box c :=
  {s with registerTable := s.registerTable.set l.val (s.registerTable[l.val].set r.val.val (some v) r.val.isLt) l.isLt}

def State.writeMemory (s : State box c) (a : Address) (v : Value box) : State box c :=
  {s with memoryTable := s.memoryTable.insert a.val v}

def State.setPending (s : State box c) (l : Lane c) (ps : List (Pending box)) : State box c :=
  {s with pendingTable := s.pendingTable.set l.val ps l.isLt}

/-- Expose each field before continuing a long closed reduction. This avoids
carrying chains of projections through unrelated record updates. -/
def State.materialize (s : State box c) : State box c :=
  match s.registerTable, s.memoryTable, s.pendingTable with
  | ⟨rs, hr⟩, ⟨⟨mem, hm⟩⟩, ⟨ps, hp⟩ => ⟨⟨rs, hr⟩, ⟨⟨mem, hm⟩⟩, ⟨ps, hp⟩⟩

@[simp] theorem State.materialize_eq (s : State box c) : s.materialize = s := by
  cases s with
  | mk rs mem ps => cases rs; cases mem with
    | mk mem => cases mem; cases ps; rfl

def State.drained (s : State box c) : Bool := (List.finRange c.val.lanes).all fun l => (s.pending l).isEmpty

private theorem hardwareState_ext (s t : Hardware.State c)
    (hr : s.registers = t.registers) (hm : s.memory = t.memory) (hp : s.pending = t.pending) : s = t := by
  cases s; cases t; cases hr; cases hm; cases hp; rfl

theorem State.eval_empty (box : Box) (c : ValidConfig) (x : Nat → Int) (hx : box.Allowed x) :
    (empty box c).eval x hx = Hardware.State.empty c := by
  apply hardwareState_ext
  · apply Vector.ext; intro i hi
    apply Vector.ext; intro j hj
    simp [eval, empty, registers, Hardware.State.empty]
  · apply Vector.ext; intro i hi
    simp [eval, empty, memory, Hardware.State.empty]
  · apply Vector.ext; intro i hi
    simp [eval, empty, pending, Hardware.State.empty]

@[simp] theorem State.eval_readRegister (s : State box c) (x : Nat → Int) (hx : box.Allowed x)
    (l : Lane c) (r : Register) :
    (s.eval x hx).readRegister l r = (s.readRegister l r).map (·.eval x hx) := by
  simp [Hardware.State.readRegister, eval, readRegister]
  split <;> simp_all

@[simp] theorem State.eval_readMemory (s : State box c) (x : Nat → Int) (hx : box.Allowed x) (a : Address) :
    (s.eval x hx).readMemory a = (s.memory a).map (fun v => encodeSlot (v.eval x hx)) := by
  simp [Hardware.State.readMemory, eval]

@[simp] theorem State.eval_pending (s : State box c) (x : Nat → Int) (hx : box.Allowed x) (l : Lane c) :
    (s.eval x hx).pending[l.val] = (s.pending l).map (·.eval x hx) := by simp [eval]

theorem State.eval_writeRegister (s : State box c) (x : Nat → Int) (hx : box.Allowed x)
    (l : Lane c) (r : WritableRegister) (v : Value box) :
    (s.writeRegister l r v).eval x hx = (s.eval x hx).writeRegister l r (v.eval x hx) := by
  apply hardwareState_ext
  · apply Vector.ext; intro i hi
    apply Vector.ext; intro j hj
    by_cases hl : l.val = i <;> by_cases hr : r.val.val = j <;>
      simp [eval, writeRegister, registers, Hardware.State.writeRegister, Vector.getElem_set, hl, hr]
  · rfl
  · rfl

theorem State.eval_writeMemory (s : State box c) (x : Nat → Int) (hx : box.Allowed x)
    (a : Address) (v : Value box) :
    (s.writeMemory a v).eval x hx = (s.eval x hx).writeMemory a (encodeSlot (v.eval x hx)) := by
  apply hardwareState_ext
  · rfl
  · apply Vector.ext; intro i hi
    simp [eval, writeMemory, memory, Hardware.State.writeMemory, Fin.ext_iff,
      Std.TreeMap.getElem?_insert]
    split <;> simp_all
  · rfl

theorem State.eval_setPending (s : State box c) (x : Nat → Int) (hx : box.Allowed x)
    (l : Lane c) (ps : List (Pending box)) :
    (s.setPending l ps).eval x hx = (s.eval x hx).setPending l (ps.map (·.eval x hx)) := by
  apply hardwareState_ext
  · rfl
  · rfl
  · apply Vector.ext; intro i hi
    by_cases hl : l.val = i <;>
      simp [eval, setPending, pending, Hardware.State.setPending, Vector.getElem_set, hl]

@[simp] theorem State.eval_drained (s : State box c) (x : Nat → Int) (hx : box.Allowed x) :
    (s.eval x hx).drained = s.drained := by
  apply Bool.eq_iff_iff.mpr
  simp [Hardware.State.drained, eval, drained, Vector.toList_ofFn, List.all_eq_true, List.mem_ofFn]

def applyEffect (s : State box c) (l : Lane c) : Effect box → State box c
  | .register r v => s.writeRegister l r v
  | .memory a v => s.writeMemory a v

theorem eval_applyEffect (s : State box c) (l : Lane c) (e : Effect box)
    (x : Nat → Int) (hx : box.Allowed x) :
    (applyEffect s l e).eval x hx = Hardware.applyEffect (s.eval x hx) l (e.eval x hx) := by
  cases e with
  | register r v => exact State.eval_writeRegister _ _ _ _ _ _
  | memory a v => exact State.eval_writeMemory _ _ _ _ _

end OptimalComputation.Certification
