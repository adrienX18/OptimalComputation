import OptimalComputation.Examples.ProductPair
import OptimalComputation.Evaluation.Path

namespace OptimalComputation.Examples.ProductPair
open Hardware Workloads Candidates Evaluation
set_option backward.isDefEq.respectTransparency false
set_option maxRecDepth 20000
set_option maxHeartbeats 500000
set_option linter.unusedSimpArgs false
set_option linter.unusedVariables false


-- Closed index normalization keeps simp from unfolding vector implementation proofs.
@[simp] private theorem val_8_0 : (0 : Fin 8).val = 0 := rfl
@[simp] private theorem val_8_1 : (1 : Fin 8).val = 1 := rfl
@[simp] private theorem val_8_2 : (2 : Fin 8).val = 2 := rfl
@[simp] private theorem val_8_3 : (3 : Fin 8).val = 3 := rfl
@[simp] private theorem val_8_4 : (4 : Fin 8).val = 4 := rfl
@[simp] private theorem val_8_5 : (5 : Fin 8).val = 5 := rfl
@[simp] private theorem val_8_6 : (6 : Fin 8).val = 6 := rfl
@[simp] private theorem val_8_7 : (7 : Fin 8).val = 7 := rfl
@[simp] private theorem val_16_0 : (0 : Fin 16).val = 0 := rfl
@[simp] private theorem val_16_1 : (1 : Fin 16).val = 1 := rfl
@[simp] private theorem val_16_2 : (2 : Fin 16).val = 2 := rfl
@[simp] private theorem val_16_3 : (3 : Fin 16).val = 3 := rfl
@[simp] private theorem val_4096_0 : (0 : Fin 4096).val = 0 := rfl
@[simp] private theorem val_4096_1 : (1 : Fin 4096).val = 1 := rfl
@[simp] private theorem val_4096_2 : (2 : Fin 4096).val = 2 := rfl
@[simp] private theorem val_4096_3 : (3 : Fin 4096).val = 3 := rfl
@[simp] private theorem val_4096_4 : (4 : Fin 4096).val = 4 := rfl
@[simp] private theorem val_4096_5 : (5 : Fin 4096).val = 5 := rfl

private def registers (a b c : Option Signed48) : Vector (Option Signed48) registersPerLane :=
  (((Vector.replicate registersPerLane none).set 1 a).set 2 b).set 3 c

private def memory (a b c d : Signed48) : Vector (Option Slot64) localMemorySlots :=
  (((Vector.replicate localMemorySlots none).set 0 (some (encodeSlot a))).set 1 (some (encodeSlot b))).set 2
    (some (encodeSlot c)) |>.set 3 (some (encodeSlot d))

private def serialState (mem : Vector (Option Slot64) localMemorySlots) (a b c d ab cd : Signed48) (t : Nat) : State (configuration false) := {
  registers := #v[registers (if t < 2 then none else if t < 8 then some a else some c)
    (if t < 3 then none else if t < 9 then some b else some d)
    (if t < 6 then none else if t < 12 then some ab else some cd)]
  memory := let m := mem
    let m := if t < 7 then m else m.set 4 (some (encodeSlot ab))
    if t < 13 then m else m.set 5 (some (encodeSlot cd))
  pending := #v[match t with
    | 1 => [⟨1, .register r1 a⟩]
    | 2 => [⟨2, .register r2 b⟩]
    | 3 | 4 | 5 => [⟨5, .register r3 ab⟩]
    | 6 => [⟨6, .memory (address 4) (encodeSlot ab)⟩]
    | 7 => [⟨7, .register r1 c⟩]
    | 8 => [⟨8, .register r2 d⟩]
    | 9 | 10 | 11 => [⟨11, .register r3 cd⟩]
    | 12 => [⟨12, .memory (address 5) (encodeSlot cd)⟩]
    | _ => []]
}

private def parallelState (mem : Vector (Option Slot64) localMemorySlots) (a b c d ab cd : Signed48) (t : Nat) : State (configuration true) := {
  registers := #v[
    registers (if t < 2 then none else some a) (if t < 3 then none else some b) (if t < 6 then none else some ab),
    registers (if t < 2 then none else some c) (if t < 3 then none else some d) (if t < 6 then none else some cd),
    registers none none none, registers none none none, registers none none none,
    registers none none none, registers none none none, registers none none none]
  memory := let m := mem
    if t < 7 then m else (m.set 4 (some (encodeSlot ab))).set 5 (some (encodeSlot cd))
  pending := #v[
    (match t with
    | 1 => [⟨1, .register r1 a⟩]
    | 2 => [⟨2, .register r2 b⟩]
    | 3 | 4 | 5 => [⟨5, .register r3 ab⟩]
    | 6 => [⟨6, .memory (address 4) (encodeSlot ab)⟩]
    | _ => []),
    (match t with
    | 1 => [⟨1, .register r1 c⟩]
    | 2 => [⟨2, .register r2 d⟩]
    | 3 | 4 | 5 => [⟨5, .register r3 cd⟩]
    | 6 => [⟨6, .memory (address 5) (encodeSlot cd)⟩]
    | _ => []), [], [], [], [], [], []]
}

private def proofState : (p : Bool) → Vector (Option Slot64) localMemorySlots → Signed48 → Signed48 → Signed48 → Signed48 → Signed48 → Signed48 → Nat → State (configuration p)
  | false => serialState
  | true => parallelState

private def queue (p : Bool) (t : Nat) : List (TimedAction (configuration p)) :=
  (program (candidate p)).filter (fun a => t ≤ a.cycle)
private def batch : (p : Bool) → Nat → List (TimedAction (configuration p))
  | false, 0 => [⟨0, ⟨lane0 false, .load r1 (address 0)⟩⟩]
  | false, 1 => [⟨1, ⟨lane0 false, .load r2 (address 1)⟩⟩]
  | false, 2 => [⟨2, ⟨lane0 false, .multiply r3 r1.val r2.val⟩⟩]
  | false, 5 => [⟨5, ⟨lane0 false, .store r3.val (address 4)⟩⟩]
  | false, 6 => [⟨6, ⟨lane0 false, .load r1 (address 2)⟩⟩]
  | false, 7 => [⟨7, ⟨lane0 false, .load r2 (address 3)⟩⟩]
  | false, 8 => [⟨8, ⟨lane0 false, .multiply r3 r1.val r2.val⟩⟩]
  | false, 11 => [⟨11, ⟨lane0 false, .store r3.val (address 5)⟩⟩]
  | true, 0 => [⟨0, ⟨lane0 true, .load r1 (address 0)⟩⟩, ⟨0, ⟨laneSecond true, .load r1 (address 2)⟩⟩]
  | true, 1 => [⟨1, ⟨lane0 true, .load r2 (address 1)⟩⟩, ⟨1, ⟨laneSecond true, .load r2 (address 3)⟩⟩]
  | true, 2 => [⟨2, ⟨lane0 true, .multiply r3 r1.val r2.val⟩⟩, ⟨2, ⟨laneSecond true, .multiply r3 r1.val r2.val⟩⟩]
  | true, 5 => [⟨5, ⟨lane0 true, .store r3.val (address 4)⟩⟩, ⟨5, ⟨laneSecond true, .store r3.val (address 5)⟩⟩]
  | false, _ => []
  | true, _ => []

def boundaries (p : Bool) : Nat := if p then 7 else 13

private def StepAt (p : Bool) (mem : Vector (Option Slot64) localMemorySlots) (a b c d ab cd : Signed48) (i : Nat) : Prop :=
  ∃ events, step i ((batch p i).map TimedAction.action) (proofState p mem a b c d ab cd i) =
    .ok (proofState p mem a b c d ab cd (i + 1), events)

local macro "prove_pair_step" h0:ident h1:ident h2:ident h3:ident ha:ident hb:ident hc:ident hd:ident : tactic =>
  `(tactic| (simp +instances -implicitDefEqProofs [step, localMemorySlots, registersPerLane, Register, WritableRegister, Lane, Address, commit, canonicalActions,
    checkBatch, prepare, checkReservation, readReady, registerPending,
    enqueue, applyEffect, latency, State.setPending, State.writeRegister, State.writeMemory,
    State.readRegister, State.readMemory, Effect.destination, Instruction.destination,
    Instruction.memoryAccess, configuration, defaultConfig, lane0, laneSecond, address, r1, r2, r3,
    TinyMultiply.r1, TinyMultiply.r2, TinyMultiply.r3, List.finRange, Fin.instOfNat, Fin.ofNat, Fin.val_ofNat,
    List.mergeSort, Vector.toList, List.forIn_cons, List.forIn_nil, List.mapM,
    List.mapM.loop, List.foldl, bankOf, bankPorts, instructionsPerLanePerCycle,
    pendingInstructionsPerLane, resultWritesPerLanePerCycle, Except.mapError,
    bind, pure, Except.bind, Except.pure, ($h0), ($h1), ($h2), ($h3),
    checkedMul_accepts $ha $hb, checkedMul_accepts $hc $hd]
  <;> (try simp_all +instances -implicitDefEqProofs [List.foldl, bind, pure, Except.bind, Except.pure, Vector.toList, localMemorySlots, registersPerLane, Register, WritableRegister, Lane, Address, configuration, defaultConfig, Fin.instOfNat, Fin.ofNat, Fin.val_ofNat, List.forIn_cons, List.forIn_nil]) <;> (first | exact ⟨rfl, rfl⟩ | exact ⟨_, rfl⟩ | rfl)))

private theorem step_false_0 (a b c d : Signed48) (mem : Vector (Option Slot64) localMemorySlots)
    (hm0 : mem[0] = some (encodeSlot a)) (hm1 : mem[1] = some (encodeSlot b))
    (hm2 : mem[2] = some (encodeSlot c)) (hm3 : mem[3] = some (encodeSlot d))
    (ha : InSigned16 a.val) (hb : InSigned16 b.val) (hc : InSigned16 c.val) (hd : InSigned16 d.val) :
    StepAt false mem a b c d ⟨a.val * b.val, signed16_product_fits ha hb⟩
      ⟨c.val * d.val, signed16_product_fits hc hd⟩ 0 := by
  change ∃ events, step 0 [⟨lane0 false, .load r1 (address 0)⟩]
    (⟨#v[(Vector.replicate registersPerLane none)], mem, #v[[]]⟩ : State (configuration false)) =
    .ok (⟨#v[(Vector.replicate registersPerLane none)], mem, #v[[⟨1, .register r1 a⟩]]⟩, events)
  prove_pair_step hm0 hm1 hm2 hm3 ha hb hc hd

private theorem step_false_1 (a b c d : Signed48) (mem : Vector (Option Slot64) localMemorySlots)
    (hm0 : mem[0] = some (encodeSlot a)) (hm1 : mem[1] = some (encodeSlot b))
    (hm2 : mem[2] = some (encodeSlot c)) (hm3 : mem[3] = some (encodeSlot d))
    (ha : InSigned16 a.val) (hb : InSigned16 b.val) (hc : InSigned16 c.val) (hd : InSigned16 d.val) :
    StepAt false mem a b c d ⟨a.val * b.val, signed16_product_fits ha hb⟩
      ⟨c.val * d.val, signed16_product_fits hc hd⟩ 1 := by
  change ∃ events, step 1 [⟨lane0 false, .load r2 (address 1)⟩]
    (⟨#v[(Vector.replicate registersPerLane none)], mem, #v[[⟨1, .register r1 a⟩]]⟩ : State (configuration false)) =
    .ok (⟨#v[((Vector.replicate registersPerLane none).set 1 (some a))], mem, #v[[⟨2, .register r2 b⟩]]⟩, events)
  prove_pair_step hm0 hm1 hm2 hm3 ha hb hc hd

private theorem step_false_2 (a b c d : Signed48) (mem : Vector (Option Slot64) localMemorySlots)
    (hm0 : mem[0] = some (encodeSlot a)) (hm1 : mem[1] = some (encodeSlot b))
    (hm2 : mem[2] = some (encodeSlot c)) (hm3 : mem[3] = some (encodeSlot d))
    (ha : InSigned16 a.val) (hb : InSigned16 b.val) (hc : InSigned16 c.val) (hd : InSigned16 d.val) :
    StepAt false mem a b c d ⟨a.val * b.val, signed16_product_fits ha hb⟩
      ⟨c.val * d.val, signed16_product_fits hc hd⟩ 2 := by
  change ∃ events, step 2 [⟨lane0 false, .multiply r3 r1.val r2.val⟩]
    (⟨#v[((Vector.replicate registersPerLane none).set 1 (some a))], mem, #v[[⟨2, .register r2 b⟩]]⟩ : State (configuration false)) =
    .ok (⟨#v[(((Vector.replicate registersPerLane none).set 1 (some a)).set 2 (some b))], mem, #v[[⟨5, .register r3 (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)⟩]]⟩, events)
  prove_pair_step hm0 hm1 hm2 hm3 ha hb hc hd

private theorem step_false_3 (a b c d : Signed48) (mem : Vector (Option Slot64) localMemorySlots)
    (hm0 : mem[0] = some (encodeSlot a)) (hm1 : mem[1] = some (encodeSlot b))
    (hm2 : mem[2] = some (encodeSlot c)) (hm3 : mem[3] = some (encodeSlot d))
    (ha : InSigned16 a.val) (hb : InSigned16 b.val) (hc : InSigned16 c.val) (hd : InSigned16 d.val) :
    StepAt false mem a b c d ⟨a.val * b.val, signed16_product_fits ha hb⟩
      ⟨c.val * d.val, signed16_product_fits hc hd⟩ 3 := by
  change ∃ events, step 3 []
    (⟨#v[(((Vector.replicate registersPerLane none).set 1 (some a)).set 2 (some b))], mem, #v[[⟨5, .register r3 (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)⟩]]⟩ : State (configuration false)) =
    .ok (⟨#v[(((Vector.replicate registersPerLane none).set 1 (some a)).set 2 (some b))], mem, #v[[⟨5, .register r3 (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)⟩]]⟩, events)
  prove_pair_step hm0 hm1 hm2 hm3 ha hb hc hd

private theorem step_false_4 (a b c d : Signed48) (mem : Vector (Option Slot64) localMemorySlots)
    (hm0 : mem[0] = some (encodeSlot a)) (hm1 : mem[1] = some (encodeSlot b))
    (hm2 : mem[2] = some (encodeSlot c)) (hm3 : mem[3] = some (encodeSlot d))
    (ha : InSigned16 a.val) (hb : InSigned16 b.val) (hc : InSigned16 c.val) (hd : InSigned16 d.val) :
    StepAt false mem a b c d ⟨a.val * b.val, signed16_product_fits ha hb⟩
      ⟨c.val * d.val, signed16_product_fits hc hd⟩ 4 := by
  change ∃ events, step 4 []
    (⟨#v[(((Vector.replicate registersPerLane none).set 1 (some a)).set 2 (some b))], mem, #v[[⟨5, .register r3 (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)⟩]]⟩ : State (configuration false)) =
    .ok (⟨#v[(((Vector.replicate registersPerLane none).set 1 (some a)).set 2 (some b))], mem, #v[[⟨5, .register r3 (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)⟩]]⟩, events)
  prove_pair_step hm0 hm1 hm2 hm3 ha hb hc hd

private theorem step_false_5 (a b c d : Signed48) (mem : Vector (Option Slot64) localMemorySlots)
    (hm0 : mem[0] = some (encodeSlot a)) (hm1 : mem[1] = some (encodeSlot b))
    (hm2 : mem[2] = some (encodeSlot c)) (hm3 : mem[3] = some (encodeSlot d))
    (ha : InSigned16 a.val) (hb : InSigned16 b.val) (hc : InSigned16 c.val) (hd : InSigned16 d.val) :
    StepAt false mem a b c d ⟨a.val * b.val, signed16_product_fits ha hb⟩
      ⟨c.val * d.val, signed16_product_fits hc hd⟩ 5 := by
  change ∃ events, step 5 [⟨lane0 false, .store r3.val (address 4)⟩]
    (⟨#v[(((Vector.replicate registersPerLane none).set 1 (some a)).set 2 (some b))], mem, #v[[⟨5, .register r3 (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)⟩]]⟩ : State (configuration false)) =
    .ok (⟨#v[((((Vector.replicate registersPerLane none).set 1 (some a)).set 2 (some b)).set 3 (some (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)))], mem, #v[[⟨6, .memory (address 4) (encodeSlot (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48))⟩]]⟩, events)
  prove_pair_step hm0 hm1 hm2 hm3 ha hb hc hd

private theorem step_false_6 (a b c d : Signed48) (mem : Vector (Option Slot64) localMemorySlots)
    (hm0 : mem[0] = some (encodeSlot a)) (hm1 : mem[1] = some (encodeSlot b))
    (hm2 : mem[2] = some (encodeSlot c)) (hm3 : mem[3] = some (encodeSlot d))
    (ha : InSigned16 a.val) (hb : InSigned16 b.val) (hc : InSigned16 c.val) (hd : InSigned16 d.val) :
    StepAt false mem a b c d ⟨a.val * b.val, signed16_product_fits ha hb⟩
      ⟨c.val * d.val, signed16_product_fits hc hd⟩ 6 := by
  change ∃ events, step 6 [⟨lane0 false, .load r1 (address 2)⟩]
    (⟨#v[((((Vector.replicate registersPerLane none).set 1 (some a)).set 2 (some b)).set 3 (some (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)))], mem, #v[[⟨6, .memory (address 4) (encodeSlot (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48))⟩]]⟩ : State (configuration false)) =
    .ok (⟨#v[((((Vector.replicate registersPerLane none).set 1 (some a)).set 2 (some b)).set 3 (some (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)))], (mem.set 4 (some (encodeSlot (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)))), #v[[⟨7, .register r1 c⟩]]⟩, events)
  prove_pair_step hm0 hm1 hm2 hm3 ha hb hc hd

private theorem step_false_7 (a b c d : Signed48) (mem : Vector (Option Slot64) localMemorySlots)
    (hm0 : mem[0] = some (encodeSlot a)) (hm1 : mem[1] = some (encodeSlot b))
    (hm2 : mem[2] = some (encodeSlot c)) (hm3 : mem[3] = some (encodeSlot d))
    (ha : InSigned16 a.val) (hb : InSigned16 b.val) (hc : InSigned16 c.val) (hd : InSigned16 d.val) :
    StepAt false mem a b c d ⟨a.val * b.val, signed16_product_fits ha hb⟩
      ⟨c.val * d.val, signed16_product_fits hc hd⟩ 7 := by
  change ∃ events, step 7 [⟨lane0 false, .load r2 (address 3)⟩]
    (⟨#v[((((Vector.replicate registersPerLane none).set 1 (some a)).set 2 (some b)).set 3 (some (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)))], (mem.set 4 (some (encodeSlot (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)))), #v[[⟨7, .register r1 c⟩]]⟩ : State (configuration false)) =
    .ok (⟨#v[((((Vector.replicate registersPerLane none).set 1 (some c)).set 2 (some b)).set 3 (some (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)))], (mem.set 4 (some (encodeSlot (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)))), #v[[⟨8, .register r2 d⟩]]⟩, events)
  prove_pair_step hm0 hm1 hm2 hm3 ha hb hc hd

private theorem step_false_8 (a b c d : Signed48) (mem : Vector (Option Slot64) localMemorySlots)
    (hm0 : mem[0] = some (encodeSlot a)) (hm1 : mem[1] = some (encodeSlot b))
    (hm2 : mem[2] = some (encodeSlot c)) (hm3 : mem[3] = some (encodeSlot d))
    (ha : InSigned16 a.val) (hb : InSigned16 b.val) (hc : InSigned16 c.val) (hd : InSigned16 d.val) :
    StepAt false mem a b c d ⟨a.val * b.val, signed16_product_fits ha hb⟩
      ⟨c.val * d.val, signed16_product_fits hc hd⟩ 8 := by
  change ∃ events, step 8 [⟨lane0 false, .multiply r3 r1.val r2.val⟩]
    (⟨#v[((((Vector.replicate registersPerLane none).set 1 (some c)).set 2 (some b)).set 3 (some (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)))], (mem.set 4 (some (encodeSlot (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)))), #v[[⟨8, .register r2 d⟩]]⟩ : State (configuration false)) =
    .ok (⟨#v[((((Vector.replicate registersPerLane none).set 1 (some c)).set 2 (some d)).set 3 (some (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)))], (mem.set 4 (some (encodeSlot (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)))), #v[[⟨11, .register r3 (⟨c.val * d.val, signed16_product_fits hc hd⟩ : Signed48)⟩]]⟩, events)
  prove_pair_step hm0 hm1 hm2 hm3 ha hb hc hd

private theorem step_false_9 (a b c d : Signed48) (mem : Vector (Option Slot64) localMemorySlots)
    (hm0 : mem[0] = some (encodeSlot a)) (hm1 : mem[1] = some (encodeSlot b))
    (hm2 : mem[2] = some (encodeSlot c)) (hm3 : mem[3] = some (encodeSlot d))
    (ha : InSigned16 a.val) (hb : InSigned16 b.val) (hc : InSigned16 c.val) (hd : InSigned16 d.val) :
    StepAt false mem a b c d ⟨a.val * b.val, signed16_product_fits ha hb⟩
      ⟨c.val * d.val, signed16_product_fits hc hd⟩ 9 := by
  change ∃ events, step 9 []
    (⟨#v[((((Vector.replicate registersPerLane none).set 1 (some c)).set 2 (some d)).set 3 (some (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)))], (mem.set 4 (some (encodeSlot (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)))), #v[[⟨11, .register r3 (⟨c.val * d.val, signed16_product_fits hc hd⟩ : Signed48)⟩]]⟩ : State (configuration false)) =
    .ok (⟨#v[((((Vector.replicate registersPerLane none).set 1 (some c)).set 2 (some d)).set 3 (some (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)))], (mem.set 4 (some (encodeSlot (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)))), #v[[⟨11, .register r3 (⟨c.val * d.val, signed16_product_fits hc hd⟩ : Signed48)⟩]]⟩, events)
  prove_pair_step hm0 hm1 hm2 hm3 ha hb hc hd

private theorem step_false_10 (a b c d : Signed48) (mem : Vector (Option Slot64) localMemorySlots)
    (hm0 : mem[0] = some (encodeSlot a)) (hm1 : mem[1] = some (encodeSlot b))
    (hm2 : mem[2] = some (encodeSlot c)) (hm3 : mem[3] = some (encodeSlot d))
    (ha : InSigned16 a.val) (hb : InSigned16 b.val) (hc : InSigned16 c.val) (hd : InSigned16 d.val) :
    StepAt false mem a b c d ⟨a.val * b.val, signed16_product_fits ha hb⟩
      ⟨c.val * d.val, signed16_product_fits hc hd⟩ 10 := by
  change ∃ events, step 10 []
    (⟨#v[((((Vector.replicate registersPerLane none).set 1 (some c)).set 2 (some d)).set 3 (some (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)))], (mem.set 4 (some (encodeSlot (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)))), #v[[⟨11, .register r3 (⟨c.val * d.val, signed16_product_fits hc hd⟩ : Signed48)⟩]]⟩ : State (configuration false)) =
    .ok (⟨#v[((((Vector.replicate registersPerLane none).set 1 (some c)).set 2 (some d)).set 3 (some (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)))], (mem.set 4 (some (encodeSlot (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)))), #v[[⟨11, .register r3 (⟨c.val * d.val, signed16_product_fits hc hd⟩ : Signed48)⟩]]⟩, events)
  prove_pair_step hm0 hm1 hm2 hm3 ha hb hc hd

private theorem step_false_11 (a b c d : Signed48) (mem : Vector (Option Slot64) localMemorySlots)
    (hm0 : mem[0] = some (encodeSlot a)) (hm1 : mem[1] = some (encodeSlot b))
    (hm2 : mem[2] = some (encodeSlot c)) (hm3 : mem[3] = some (encodeSlot d))
    (ha : InSigned16 a.val) (hb : InSigned16 b.val) (hc : InSigned16 c.val) (hd : InSigned16 d.val) :
    StepAt false mem a b c d ⟨a.val * b.val, signed16_product_fits ha hb⟩
      ⟨c.val * d.val, signed16_product_fits hc hd⟩ 11 := by
  change ∃ events, step 11 [⟨lane0 false, .store r3.val (address 5)⟩]
    (⟨#v[((((Vector.replicate registersPerLane none).set 1 (some c)).set 2 (some d)).set 3 (some (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)))], (mem.set 4 (some (encodeSlot (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)))), #v[[⟨11, .register r3 (⟨c.val * d.val, signed16_product_fits hc hd⟩ : Signed48)⟩]]⟩ : State (configuration false)) =
    .ok (⟨#v[((((Vector.replicate registersPerLane none).set 1 (some c)).set 2 (some d)).set 3 (some (⟨c.val * d.val, signed16_product_fits hc hd⟩ : Signed48)))], (mem.set 4 (some (encodeSlot (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)))), #v[[⟨12, .memory (address 5) (encodeSlot (⟨c.val * d.val, signed16_product_fits hc hd⟩ : Signed48))⟩]]⟩, events)
  prove_pair_step hm0 hm1 hm2 hm3 ha hb hc hd

private theorem step_false_12 (a b c d : Signed48) (mem : Vector (Option Slot64) localMemorySlots)
    (hm0 : mem[0] = some (encodeSlot a)) (hm1 : mem[1] = some (encodeSlot b))
    (hm2 : mem[2] = some (encodeSlot c)) (hm3 : mem[3] = some (encodeSlot d))
    (ha : InSigned16 a.val) (hb : InSigned16 b.val) (hc : InSigned16 c.val) (hd : InSigned16 d.val) :
    StepAt false mem a b c d ⟨a.val * b.val, signed16_product_fits ha hb⟩
      ⟨c.val * d.val, signed16_product_fits hc hd⟩ 12 := by
  change ∃ events, step 12 []
    (⟨#v[((((Vector.replicate registersPerLane none).set 1 (some c)).set 2 (some d)).set 3 (some (⟨c.val * d.val, signed16_product_fits hc hd⟩ : Signed48)))], (mem.set 4 (some (encodeSlot (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)))), #v[[⟨12, .memory (address 5) (encodeSlot (⟨c.val * d.val, signed16_product_fits hc hd⟩ : Signed48))⟩]]⟩ : State (configuration false)) =
    .ok (⟨#v[((((Vector.replicate registersPerLane none).set 1 (some c)).set 2 (some d)).set 3 (some (⟨c.val * d.val, signed16_product_fits hc hd⟩ : Signed48)))], ((mem.set 4 (some (encodeSlot (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)))).set 5 (some (encodeSlot (⟨c.val * d.val, signed16_product_fits hc hd⟩ : Signed48)))), #v[[]]⟩, events)
  prove_pair_step hm0 hm1 hm2 hm3 ha hb hc hd

private theorem step_true_0 (a b c d : Signed48) (mem : Vector (Option Slot64) localMemorySlots)
    (hm0 : mem[0] = some (encodeSlot a)) (hm1 : mem[1] = some (encodeSlot b))
    (hm2 : mem[2] = some (encodeSlot c)) (hm3 : mem[3] = some (encodeSlot d))
    (ha : InSigned16 a.val) (hb : InSigned16 b.val) (hc : InSigned16 c.val) (hd : InSigned16 d.val) :
    StepAt true mem a b c d ⟨a.val * b.val, signed16_product_fits ha hb⟩
      ⟨c.val * d.val, signed16_product_fits hc hd⟩ 0 := by
  change ∃ events, step 0 [⟨lane0 true, .load r1 (address 0)⟩, ⟨laneSecond true, .load r1 (address 2)⟩]
    (⟨(Vector.replicate 8 (Vector.replicate registersPerLane none)), mem, (Vector.replicate 8 [])⟩ : State (configuration true)) =
    .ok (⟨(Vector.replicate 8 (Vector.replicate registersPerLane none)), mem, (((Vector.replicate 8 []).set 0 [⟨1, .register r1 a⟩]).set 1 [⟨1, .register r1 c⟩])⟩, events)
  prove_pair_step hm0 hm1 hm2 hm3 ha hb hc hd

private theorem step_true_1 (a b c d : Signed48) (mem : Vector (Option Slot64) localMemorySlots)
    (hm0 : mem[0] = some (encodeSlot a)) (hm1 : mem[1] = some (encodeSlot b))
    (hm2 : mem[2] = some (encodeSlot c)) (hm3 : mem[3] = some (encodeSlot d))
    (ha : InSigned16 a.val) (hb : InSigned16 b.val) (hc : InSigned16 c.val) (hd : InSigned16 d.val) :
    StepAt true mem a b c d ⟨a.val * b.val, signed16_product_fits ha hb⟩
      ⟨c.val * d.val, signed16_product_fits hc hd⟩ 1 := by
  change ∃ events, step 1 [⟨lane0 true, .load r2 (address 1)⟩, ⟨laneSecond true, .load r2 (address 3)⟩]
    (⟨(Vector.replicate 8 (Vector.replicate registersPerLane none)), mem, (((Vector.replicate 8 []).set 0 [⟨1, .register r1 a⟩]).set 1 [⟨1, .register r1 c⟩])⟩ : State (configuration true)) =
    .ok (⟨(((Vector.replicate 8 (Vector.replicate registersPerLane none)).set 0 ((Vector.replicate registersPerLane none).set 1 (some a))).set 1 ((Vector.replicate registersPerLane none).set 1 (some c))), mem, (((Vector.replicate 8 []).set 0 [⟨2, .register r2 b⟩]).set 1 [⟨2, .register r2 d⟩])⟩, events)
  prove_pair_step hm0 hm1 hm2 hm3 ha hb hc hd

private theorem step_true_2 (a b c d : Signed48) (mem : Vector (Option Slot64) localMemorySlots)
    (hm0 : mem[0] = some (encodeSlot a)) (hm1 : mem[1] = some (encodeSlot b))
    (hm2 : mem[2] = some (encodeSlot c)) (hm3 : mem[3] = some (encodeSlot d))
    (ha : InSigned16 a.val) (hb : InSigned16 b.val) (hc : InSigned16 c.val) (hd : InSigned16 d.val) :
    StepAt true mem a b c d ⟨a.val * b.val, signed16_product_fits ha hb⟩
      ⟨c.val * d.val, signed16_product_fits hc hd⟩ 2 := by
  change ∃ events, step 2 [⟨lane0 true, .multiply r3 r1.val r2.val⟩, ⟨laneSecond true, .multiply r3 r1.val r2.val⟩]
    (⟨(((Vector.replicate 8 (Vector.replicate registersPerLane none)).set 0 ((Vector.replicate registersPerLane none).set 1 (some a))).set 1 ((Vector.replicate registersPerLane none).set 1 (some c))), mem, (((Vector.replicate 8 []).set 0 [⟨2, .register r2 b⟩]).set 1 [⟨2, .register r2 d⟩])⟩ : State (configuration true)) =
    .ok (⟨(((Vector.replicate 8 (Vector.replicate registersPerLane none)).set 0 (((Vector.replicate registersPerLane none).set 1 (some a)).set 2 (some b))).set 1 (((Vector.replicate registersPerLane none).set 1 (some c)).set 2 (some d))), mem, (((Vector.replicate 8 []).set 0 [⟨5, .register r3 (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)⟩]).set 1 [⟨5, .register r3 (⟨c.val * d.val, signed16_product_fits hc hd⟩ : Signed48)⟩])⟩, events)
  prove_pair_step hm0 hm1 hm2 hm3 ha hb hc hd

private theorem step_true_3 (a b c d : Signed48) (mem : Vector (Option Slot64) localMemorySlots)
    (hm0 : mem[0] = some (encodeSlot a)) (hm1 : mem[1] = some (encodeSlot b))
    (hm2 : mem[2] = some (encodeSlot c)) (hm3 : mem[3] = some (encodeSlot d))
    (ha : InSigned16 a.val) (hb : InSigned16 b.val) (hc : InSigned16 c.val) (hd : InSigned16 d.val) :
    StepAt true mem a b c d ⟨a.val * b.val, signed16_product_fits ha hb⟩
      ⟨c.val * d.val, signed16_product_fits hc hd⟩ 3 := by
  change ∃ events, step 3 []
    (⟨(((Vector.replicate 8 (Vector.replicate registersPerLane none)).set 0 (((Vector.replicate registersPerLane none).set 1 (some a)).set 2 (some b))).set 1 (((Vector.replicate registersPerLane none).set 1 (some c)).set 2 (some d))), mem, (((Vector.replicate 8 []).set 0 [⟨5, .register r3 (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)⟩]).set 1 [⟨5, .register r3 (⟨c.val * d.val, signed16_product_fits hc hd⟩ : Signed48)⟩])⟩ : State (configuration true)) =
    .ok (⟨(((Vector.replicate 8 (Vector.replicate registersPerLane none)).set 0 (((Vector.replicate registersPerLane none).set 1 (some a)).set 2 (some b))).set 1 (((Vector.replicate registersPerLane none).set 1 (some c)).set 2 (some d))), mem, (((Vector.replicate 8 []).set 0 [⟨5, .register r3 (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)⟩]).set 1 [⟨5, .register r3 (⟨c.val * d.val, signed16_product_fits hc hd⟩ : Signed48)⟩])⟩, events)
  prove_pair_step hm0 hm1 hm2 hm3 ha hb hc hd

private theorem step_true_4 (a b c d : Signed48) (mem : Vector (Option Slot64) localMemorySlots)
    (hm0 : mem[0] = some (encodeSlot a)) (hm1 : mem[1] = some (encodeSlot b))
    (hm2 : mem[2] = some (encodeSlot c)) (hm3 : mem[3] = some (encodeSlot d))
    (ha : InSigned16 a.val) (hb : InSigned16 b.val) (hc : InSigned16 c.val) (hd : InSigned16 d.val) :
    StepAt true mem a b c d ⟨a.val * b.val, signed16_product_fits ha hb⟩
      ⟨c.val * d.val, signed16_product_fits hc hd⟩ 4 := by
  change ∃ events, step 4 []
    (⟨(((Vector.replicate 8 (Vector.replicate registersPerLane none)).set 0 (((Vector.replicate registersPerLane none).set 1 (some a)).set 2 (some b))).set 1 (((Vector.replicate registersPerLane none).set 1 (some c)).set 2 (some d))), mem, (((Vector.replicate 8 []).set 0 [⟨5, .register r3 (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)⟩]).set 1 [⟨5, .register r3 (⟨c.val * d.val, signed16_product_fits hc hd⟩ : Signed48)⟩])⟩ : State (configuration true)) =
    .ok (⟨(((Vector.replicate 8 (Vector.replicate registersPerLane none)).set 0 (((Vector.replicate registersPerLane none).set 1 (some a)).set 2 (some b))).set 1 (((Vector.replicate registersPerLane none).set 1 (some c)).set 2 (some d))), mem, (((Vector.replicate 8 []).set 0 [⟨5, .register r3 (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)⟩]).set 1 [⟨5, .register r3 (⟨c.val * d.val, signed16_product_fits hc hd⟩ : Signed48)⟩])⟩, events)
  prove_pair_step hm0 hm1 hm2 hm3 ha hb hc hd

private theorem step_true_5 (a b c d : Signed48) (mem : Vector (Option Slot64) localMemorySlots)
    (hm0 : mem[0] = some (encodeSlot a)) (hm1 : mem[1] = some (encodeSlot b))
    (hm2 : mem[2] = some (encodeSlot c)) (hm3 : mem[3] = some (encodeSlot d))
    (ha : InSigned16 a.val) (hb : InSigned16 b.val) (hc : InSigned16 c.val) (hd : InSigned16 d.val) :
    StepAt true mem a b c d ⟨a.val * b.val, signed16_product_fits ha hb⟩
      ⟨c.val * d.val, signed16_product_fits hc hd⟩ 5 := by
  change ∃ events, step 5 [⟨lane0 true, .store r3.val (address 4)⟩, ⟨laneSecond true, .store r3.val (address 5)⟩]
    (⟨(((Vector.replicate 8 (Vector.replicate registersPerLane none)).set 0 (((Vector.replicate registersPerLane none).set 1 (some a)).set 2 (some b))).set 1 (((Vector.replicate registersPerLane none).set 1 (some c)).set 2 (some d))), mem, (((Vector.replicate 8 []).set 0 [⟨5, .register r3 (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)⟩]).set 1 [⟨5, .register r3 (⟨c.val * d.val, signed16_product_fits hc hd⟩ : Signed48)⟩])⟩ : State (configuration true)) =
    .ok (⟨(((Vector.replicate 8 (Vector.replicate registersPerLane none)).set 0 ((((Vector.replicate registersPerLane none).set 1 (some a)).set 2 (some b)).set 3 (some (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)))).set 1 ((((Vector.replicate registersPerLane none).set 1 (some c)).set 2 (some d)).set 3 (some (⟨c.val * d.val, signed16_product_fits hc hd⟩ : Signed48)))), mem, (((Vector.replicate 8 []).set 0 [⟨6, .memory (address 4) (encodeSlot (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48))⟩]).set 1 [⟨6, .memory (address 5) (encodeSlot (⟨c.val * d.val, signed16_product_fits hc hd⟩ : Signed48))⟩])⟩, events)
  prove_pair_step hm0 hm1 hm2 hm3 ha hb hc hd

private theorem step_true_6 (a b c d : Signed48) (mem : Vector (Option Slot64) localMemorySlots)
    (hm0 : mem[0] = some (encodeSlot a)) (hm1 : mem[1] = some (encodeSlot b))
    (hm2 : mem[2] = some (encodeSlot c)) (hm3 : mem[3] = some (encodeSlot d))
    (ha : InSigned16 a.val) (hb : InSigned16 b.val) (hc : InSigned16 c.val) (hd : InSigned16 d.val) :
    StepAt true mem a b c d ⟨a.val * b.val, signed16_product_fits ha hb⟩
      ⟨c.val * d.val, signed16_product_fits hc hd⟩ 6 := by
  change ∃ events, step 6 []
    (⟨(((Vector.replicate 8 (Vector.replicate registersPerLane none)).set 0 ((((Vector.replicate registersPerLane none).set 1 (some a)).set 2 (some b)).set 3 (some (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)))).set 1 ((((Vector.replicate registersPerLane none).set 1 (some c)).set 2 (some d)).set 3 (some (⟨c.val * d.val, signed16_product_fits hc hd⟩ : Signed48)))), mem, (((Vector.replicate 8 []).set 0 [⟨6, .memory (address 4) (encodeSlot (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48))⟩]).set 1 [⟨6, .memory (address 5) (encodeSlot (⟨c.val * d.val, signed16_product_fits hc hd⟩ : Signed48))⟩])⟩ : State (configuration true)) =
    .ok (⟨(((Vector.replicate 8 (Vector.replicate registersPerLane none)).set 0 ((((Vector.replicate registersPerLane none).set 1 (some a)).set 2 (some b)).set 3 (some (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)))).set 1 ((((Vector.replicate registersPerLane none).set 1 (some c)).set 2 (some d)).set 3 (some (⟨c.val * d.val, signed16_product_fits hc hd⟩ : Signed48)))), ((mem.set 4 (some (encodeSlot (⟨a.val * b.val, signed16_product_fits ha hb⟩ : Signed48)))).set 5 (some (encodeSlot (⟨c.val * d.val, signed16_product_fits hc hd⟩ : Signed48)))), (Vector.replicate 8 [])⟩, events)
  prove_pair_step hm0 hm1 hm2 hm3 ha hb hc hd

private theorem state_step (a b c d : Signed48) (mem : Vector (Option Slot64) localMemorySlots)
    (hm0 : mem[0] = some (encodeSlot a)) (hm1 : mem[1] = some (encodeSlot b))
    (hm2 : mem[2] = some (encodeSlot c)) (hm3 : mem[3] = some (encodeSlot d))
    (ha : InSigned16 a.val) (hb : InSigned16 b.val) (hc : InSigned16 c.val) (hd : InSigned16 d.val) (p : Bool) (i : Fin (boundaries p)) :
    StepAt p mem a b c d ⟨a.val * b.val, signed16_product_fits ha hb⟩
      ⟨c.val * d.val, signed16_product_fits hc hd⟩ i.val := by
  cases p
  · have hi : i.val < 13 := i.isLt
    have hcases : i.val = 0 ∨ i.val = 1 ∨ i.val = 2 ∨ i.val = 3 ∨ i.val = 4 ∨ i.val = 5 ∨ i.val = 6 ∨ i.val = 7 ∨ i.val = 8 ∨ i.val = 9 ∨ i.val = 10 ∨ i.val = 11 ∨ i.val = 12 := by omega
    rcases hcases with h | h | h | h | h | h | h | h | h | h | h | h | h
    · simpa only [h] using step_false_0 a b c d mem hm0 hm1 hm2 hm3 ha hb hc hd
    · simpa only [h] using step_false_1 a b c d mem hm0 hm1 hm2 hm3 ha hb hc hd
    · simpa only [h] using step_false_2 a b c d mem hm0 hm1 hm2 hm3 ha hb hc hd
    · simpa only [h] using step_false_3 a b c d mem hm0 hm1 hm2 hm3 ha hb hc hd
    · simpa only [h] using step_false_4 a b c d mem hm0 hm1 hm2 hm3 ha hb hc hd
    · simpa only [h] using step_false_5 a b c d mem hm0 hm1 hm2 hm3 ha hb hc hd
    · simpa only [h] using step_false_6 a b c d mem hm0 hm1 hm2 hm3 ha hb hc hd
    · simpa only [h] using step_false_7 a b c d mem hm0 hm1 hm2 hm3 ha hb hc hd
    · simpa only [h] using step_false_8 a b c d mem hm0 hm1 hm2 hm3 ha hb hc hd
    · simpa only [h] using step_false_9 a b c d mem hm0 hm1 hm2 hm3 ha hb hc hd
    · simpa only [h] using step_false_10 a b c d mem hm0 hm1 hm2 hm3 ha hb hc hd
    · simpa only [h] using step_false_11 a b c d mem hm0 hm1 hm2 hm3 ha hb hc hd
    · simpa only [h] using step_false_12 a b c d mem hm0 hm1 hm2 hm3 ha hb hc hd
  · have hi : i.val < 7 := i.isLt
    have hcases : i.val = 0 ∨ i.val = 1 ∨ i.val = 2 ∨ i.val = 3 ∨ i.val = 4 ∨ i.val = 5 ∨ i.val = 6 := by omega
    rcases hcases with h | h | h | h | h | h | h
    · simpa only [h] using step_true_0 a b c d mem hm0 hm1 hm2 hm3 ha hb hc hd
    · simpa only [h] using step_true_1 a b c d mem hm0 hm1 hm2 hm3 ha hb hc hd
    · simpa only [h] using step_true_2 a b c d mem hm0 hm1 hm2 hm3 ha hb hc hd
    · simpa only [h] using step_true_3 a b c d mem hm0 hm1 hm2 hm3 ha hb hc hd
    · simpa only [h] using step_true_4 a b c d mem hm0 hm1 hm2 hm3 ha hb hc hd
    · simpa only [h] using step_true_5 a b c d mem hm0 hm1 hm2 hm3 ha hb hc hd
    · simpa only [h] using step_true_6 a b c d mem hm0 hm1 hm2 hm3 ha hb hc hd

private theorem queue_span (p : Bool) (i : Fin (boundaries p)) :
    (queue p i.val).span (fun a => a.cycle == i.val) = (batch p i.val, queue p (i.val + 1)) := by
  cases p <;> (have hi := i.isLt; simp only [boundaries, Bool.false_eq_true, Bool.true_eq, ↓reduceIte] at hi)
  all_goals have hcases : i.val = 0 ∨ i.val = 1 ∨ i.val = 2 ∨ i.val = 3 ∨ i.val = 4 ∨ i.val = 5 ∨
      i.val = 6 ∨ i.val = 7 ∨ i.val = 8 ∨ i.val = 9 ∨ i.val = 10 ∨ i.val = 11 ∨ i.val = 12 := by omega
  all_goals rcases hcases with h | h | h | h | h | h | h | h | h | h | h | h | h
  all_goals simp +instances -implicitDefEqProofs [h, queue, batch, program, candidate, List.mergeSort, List.span, List.span.loop, lane0, laneSecond]

private theorem not_finished (p : Bool) (mem : Vector (Option Slot64) localMemorySlots) (a b c d ab cd : Signed48) (i : Fin (boundaries p)) :
    ((queue p i.val).isEmpty && (proofState p mem a b c d ab cd i.val).drained) = false := by
  cases p
  · rcases i with ⟨i, hi⟩
    change i < 13 at hi
    have hcases : i = 0 ∨ i = 1 ∨ i = 2 ∨ i = 3 ∨ i = 4 ∨ i = 5 ∨ i = 6 ∨ i = 7 ∨ i = 8 ∨ i = 9 ∨ i = 10 ∨ i = 11 ∨ i = 12 := by omega
    rcases hcases with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
      dsimp only [State.drained, proofState, serialState, parallelState]
    all_goals simp +instances -implicitDefEqProofs [queue, program, candidate, List.mergeSort, Vector.toList]
  · rcases i with ⟨i, hi⟩
    change i < 7 at hi
    have hcases : i = 0 ∨ i = 1 ∨ i = 2 ∨ i = 3 ∨ i = 4 ∨ i = 5 ∨ i = 6 := by omega
    rcases hcases with rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
      dsimp only [State.drained, proofState, serialState, parallelState]
    all_goals simp +instances -implicitDefEqProofs [queue, program, candidate, List.mergeSort, Vector.toList]

private theorem finish_correct (p : Bool) (mem : Vector (Option Slot64) localMemorySlots)
    (a b c d ab cd : Signed48) (counts : Counters) :
    ∃ record, finish (candidate p) ⟨boundaries p - 1,
      proofState p mem a b c d ab cd (boundaries p), counts, []⟩ = .success record ∧
      record.outputs = [ab.val, cd.val] ∧ record.cycles = (if p then 6 else 12) := by
  cases p <;>
    dsimp only [finish, candidate, layout, collectOutputs, State.readMemory, proofState, serialState, parallelState]
  all_goals simp +instances -implicitDefEqProofs [address, boundaries]

/-- All-input safety and correctness of both actual machine programs. Symbolic
states are used solely as step witnesses; the runtime executes the same runner. -/
theorem execution_correct (p : Bool) (a b c d : Int) (ha : InSigned16 a) (hb : InSigned16 b)
    (hc : InSigned16 c) (hd : InSigned16 d) :
    ∃ record, executeValues (candidate p) (inputs a b c d ha hb hc hd) (boundaries p) false = .success record ∧
      record.outputs = [a * b, c * d] ∧ record.cycles = (if p then 6 else 12) := by
  let av : Signed48 := ⟨a, signed16_fits_signed48 ha⟩
  let bv : Signed48 := ⟨b, signed16_fits_signed48 hb⟩
  let cv : Signed48 := ⟨c, signed16_fits_signed48 hc⟩
  let dv : Signed48 := ⟨d, signed16_fits_signed48 hd⟩
  let ab : Signed48 := ⟨a * b, signed16_product_fits ha hb⟩
  let cd : Signed48 := ⟨c * d, signed16_product_fits hc hd⟩
  let mem := memory av bv cv dv
  have hm0 : mem[0] = some (encodeSlot av) := by simp [mem, memory]
  have hm1 : mem[1] = some (encodeSlot bv) := by simp [mem, memory]
  have hm2 : mem[2] = some (encodeSlot cv) := by simp [mem, memory]
  have hm3 : mem[3] = some (encodeSlot dv) := by simp [mem, memory]
  let states := proofState p mem av bv cv dv ab cd
  have hinit : initialState (candidate p).configuration (candidate p).layout (inputs a b c d ha hb hc hd) = states 0 := by
    cases p <;> rfl
  have hqueue : program (candidate p) = queue p 0 := by
    symm
    apply List.filter_eq_self.mpr
    intro a _
    simp
  have hendq : queue p (boundaries p) = [] := by
    cases p <;> simp [queue, boundaries, program, candidate, List.mergeSort]
  have hends : (states (boundaries p)).drained = true := by
    cases p <;> rfl
  obtain ⟨counts, hrun⟩ := run_path (boundaries p) states (queue p) (batch p)
    (fun i hi => not_finished p mem av bv cv dv ab cd ⟨i, hi⟩)
    (fun i hi => queue_span p ⟨i, hi⟩)
    (fun i hi => state_step av bv cv dv mem hm0 hm1 hm2 hm3 ha hb hc hd p ⟨i, hi⟩)
    hendq hends (boundaries p) 0 (by omega) (Counters.empty (candidate p).configuration)
  unfold executeValues
  rw [hinit, hqueue, hrun]
  exact finish_correct p mem av bv cv dv ab cd counts

def verified (p : Bool) : VerifiedCandidate adapter where
  candidate := candidate p
  sufficientBoundaries := boundaries p
  safety := by
    intro x hx
    obtain ⟨record, he, _, _⟩ := execution_correct p x.1.1 x.1.2 x.2.1 x.2.2 hx.1 hx.2.1 hx.2.2.1 hx.2.2.2
    exact ⟨record, by rw [adapter_encode]; exact he⟩
  correctness := by
    intro x hx record he
    rw [adapter_encode] at he
    obtain ⟨expected, hh, ho, _⟩ := execution_correct p x.1.1 x.1.2 x.2.1 x.2.2 hx.1 hx.2.1 hx.2.2.1 hx.2.2.2
    have hr : expected = record := ExecutionOutcome.success.inj (hh.symm.trans he)
    subst record
    exact ho

end OptimalComputation.Examples.ProductPair
