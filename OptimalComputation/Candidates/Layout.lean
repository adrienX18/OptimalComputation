import OptimalComputation.Hardware.Instruction
import OptimalComputation.Workloads.Shape

namespace OptimalComputation.Candidates

open Hardware Workloads

/-- Position in each list is the logical scalar index. Scratch has no initial
payload: it declares storage, never precomputed constants or intermediate values. -/
structure RawLayout where
  inputs : List Nat
  outputs : List Nat
  scratch : List Nat := []
  deriving Repr, DecidableEq, BEq

structure Layout (shape : Shape) where
  inputs : List Address
  outputs : List Address
  scratch : List Address
  inputCount : inputs.length = shape.inputCount
  outputCount : outputs.length = shape.outputCount
  separate : (inputs ++ outputs ++ scratch).Nodup
  deriving Repr

def Layout.declared (layout : Layout shape) : List Address :=
  layout.inputs ++ layout.outputs ++ layout.scratch

def Layout.writable (layout : Layout shape) : List Address := layout.outputs ++ layout.scratch

def Layout.inputAddress (layout : Layout shape) (i : Fin shape.inputCount) : Address :=
  layout.inputs.get ⟨i.val, by simp [layout.inputCount]⟩

def Layout.outputAddress (layout : Layout shape) (i : Fin shape.outputCount) : Address :=
  layout.outputs.get ⟨i.val, by simp [layout.outputCount]⟩

theorem Layout.inputs_nodup (layout : Layout shape) : layout.inputs.Nodup := by
  have h := layout.separate
  simp only [List.nodup_append] at h
  exact h.1.1

theorem Layout.outputs_nodup (layout : Layout shape) : layout.outputs.Nodup := by
  have h := layout.separate
  simp only [List.nodup_append] at h
  exact h.1.2.1

theorem Layout.scratch_nodup (layout : Layout shape) : layout.scratch.Nodup := by
  have h := layout.separate
  simp only [List.nodup_append] at h
  exact h.2.1

theorem Layout.inputAddress_injective (layout : Layout shape)
    {i j : Fin shape.inputCount} (h : layout.inputAddress i = layout.inputAddress j) : i = j := by
  exact Fin.ext (layout.inputs_nodup.getElem_inj.mp h)

theorem Layout.outputAddress_injective (layout : Layout shape)
    {i j : Fin shape.outputCount} (h : layout.outputAddress i = layout.outputAddress j) : i = j := by
  exact Fin.ext (layout.outputs_nodup.getElem_inj.mp h)

theorem Layout.writable_not_input (layout : Layout shape) {a : Address}
    (hw : a ∈ layout.writable) : a ∉ layout.inputs := by
  have h := layout.separate
  rw [List.append_assoc] at h
  have hd := (List.nodup_append.mp h).2.2
  exact fun hi => hd a hi a hw rfl

theorem Layout.output_not_scratch (layout : Layout shape) {a : Address}
    (ho : a ∈ layout.outputs) : a ∉ layout.scratch := by
  have h := layout.separate
  rw [List.append_assoc] at h
  have hd := (List.nodup_append.mp (List.nodup_append.mp h).2.1).2.2
  exact fun hs => hd a ho a hs rfl

inductive Region where
  | input | output | scratch
  deriving Repr, DecidableEq, BEq

inductive LayoutError where
  | wrongInputCount (expected actual : Nat)
  | wrongOutputCount (expected actual : Nat)
  | addressOutOfBounds (region : Region) (index address : Nat)
  | aliasedStorage
  deriving Repr, DecidableEq, BEq

private def boundAddresses (region : Region) :
    Nat → List Nat → Except LayoutError (List Address)
  | _, [] => .ok []
  | index, a :: rest => do
      if h : a < localMemorySlots then
        return ⟨a, h⟩ :: (← boundAddresses region (index + 1) rest)
      else .error (.addressOutOfBounds region index a)

/-- Compute only Booleans while reflecting distinctness. Constructing the
quadratic `Decidable Pairwise` proof during reduction makes large layouts slow. -/
private def distinctSlow : List Address → Bool
  | [] => true
  | a :: rest => !rest.contains a && distinctSlow rest

private theorem distinctSlow_iff (addresses : List Address) :
    distinctSlow addresses = true ↔ addresses.Nodup := by
  induction addresses with
  | nil => simp [distinctSlow]
  | cons a rest ih => simp [distinctSlow, ih, List.nodup_cons]

private def increasingFrom (a : Address) : List Address → Bool
  | [] => true
  | b :: rest => decide (a.val < b.val) && increasingFrom b rest

private theorem increasingFrom_sound (a : Address) (rest : List Address)
    (h : increasingFrom a rest = true) :
    rest.Nodup ∧ ∀ b ∈ rest, a.val < b.val := by
  induction rest generalizing a with
  | nil => simp
  | cons b rest ih =>
    simp only [increasingFrom, Bool.and_eq_true, decide_eq_true_eq] at h
    obtain ⟨hn, hall⟩ := ih b h.2
    constructor
    · apply List.nodup_cons.mpr
      exact ⟨fun hm => (Nat.lt_irrefl b.val) (hall b hm), hn⟩
    · intro c hc
      rcases List.mem_cons.mp hc with he | hm
      · subst c; exact h.1
      · exact Nat.lt_trans h.1 (hall c hm)

/-- Sorted regions are the common case and need only one linear pass. The
Boolean fallback handles every permutation without changing admission rules. -/
def distinctAddresses : List Address → Bool
  | [] => true
  | a :: rest => increasingFrom a rest || distinctSlow (a :: rest)

@[simp] theorem distinctAddresses_iff (addresses : List Address) :
    distinctAddresses addresses = true ↔ addresses.Nodup := by
  cases addresses with
  | nil => simp [distinctAddresses]
  | cons a rest =>
    simp only [distinctAddresses, Bool.or_eq_true, distinctSlow_iff]
    constructor
    · intro h
      rcases h with hi | hn
      · obtain ⟨hn, hall⟩ := increasingFrom_sound a rest hi
        exact List.nodup_cons.mpr ⟨fun hm => (Nat.lt_irrefl a.val) (hall a hm), hn⟩
      · exact hn
    · exact Or.inr

/-- Counts, then bounds in input/output/scratch order, then global non-aliasing.
The combined Nodup check establishes all three injection and disjointness rules. -/
def validateLayout (shape : Shape) (raw : RawLayout) : Except LayoutError (Layout shape) := do
  if raw.inputs.length ≠ shape.inputCount then
    throw (.wrongInputCount shape.inputCount raw.inputs.length)
  if raw.outputs.length ≠ shape.outputCount then
    throw (.wrongOutputCount shape.outputCount raw.outputs.length)
  let inputs ← boundAddresses .input 0 raw.inputs
  let outputs ← boundAddresses .output 0 raw.outputs
  let scratch ← boundAddresses .scratch 0 raw.scratch
  if hi : inputs.length = shape.inputCount then
    if ho : outputs.length = shape.outputCount then
      if hs : distinctAddresses (inputs ++ outputs ++ scratch) = true then
        return ⟨inputs, outputs, scratch, hi, ho, distinctAddresses_iff _ |>.mp hs⟩
      else throw .aliasedStorage
    else throw (.wrongOutputCount shape.outputCount outputs.length)
  else throw (.wrongInputCount shape.inputCount inputs.length)

def Layout.toRaw (layout : Layout shape) : RawLayout :=
  ⟨layout.inputs.map Fin.val, layout.outputs.map Fin.val, layout.scratch.map Fin.val⟩

private theorem boundAddresses_roundtrip (region : Region) (addresses : List Address)
    (index : Nat) :
    boundAddresses region index (addresses.map Fin.val) = .ok addresses := by
  induction addresses generalizing index with
  | nil => rfl
  | cons a rest ih =>
      simp [boundAddresses, a.isLt, ih, bind, Except.bind, pure, Except.pure]

theorem validateLayout_roundtrip (layout : Layout shape) :
    validateLayout shape layout.toRaw = .ok layout := by
  have hs : (layout.inputs ++ (layout.outputs ++ layout.scratch)).Nodup := by
    simpa only [List.append_assoc] using layout.separate
  simp [validateLayout, Layout.toRaw, layout.inputCount, layout.outputCount,
    boundAddresses_roundtrip, hs, bind, Except.bind, pure, Except.pure]

end OptimalComputation.Candidates
