import OptimalComputation.Evaluation.Execution

/-! Read-back facts for the shared initializer, independent of workloads. -/
namespace OptimalComputation.Evaluation
open Hardware Candidates Workloads

def writeValues (s : State c) (pairs : List (Address × Signed48)) : State c :=
  pairs.foldl (fun s (a, v) => s.writeMemory a (encodeSlot v)) s

theorem writeValues_preserve (pairs : List (Address × Signed48)) (s : State c)
    (a : Address) (v : Signed48)
    (hs : s.readMemory a = some (encodeSlot v))
    (hp : ∀ p ∈ pairs, p.1 = a → p.2 = v) :
    (writeValues s pairs).readMemory a = some (encodeSlot v) := by
  induction pairs generalizing s with
  | nil => exact hs
  | cons p ps ih =>
    apply ih (s.writeMemory p.1 (encodeSlot p.2))
    · by_cases he : p.1 = a
      · rw [hp p (by simp) he, he]; exact State.readMemory_write_same _ _ _
      · rw [State.readMemory_write_other _ _ _ _ he]; exact hs
    · intro q hq; exact hp q (by simp [hq])

theorem writeValues_read (pairs : List (Address × Signed48)) (s : State c)
    (a : Address) (v : Signed48)
    (hm : (a, v) ∈ pairs) (hp : ∀ p ∈ pairs, p.1 = a → p.2 = v) :
    (writeValues s pairs).readMemory a = some (encodeSlot v) := by
  induction pairs generalizing s with
  | nil => simp at hm
  | cons p ps ih =>
    change (writeValues (s.writeMemory p.1 (encodeSlot p.2)) ps).readMemory a = _
    rcases List.mem_cons.mp hm with he | hm
    · subst p
      exact writeValues_preserve ps _ a v (State.readMemory_write_same _ _ _)
        (fun q hq => hp q (by simp [hq]))
    · exact ih _ hm (fun q hq => hp q (by simp [hq]))

theorem writeValues_pending (pairs : List (Address × Signed48)) (s : State c) :
    (writeValues s pairs).pending = s.pending := by
  induction pairs generalizing s with
  | nil => rfl
  | cons p ps ih => exact ih (s.writeMemory p.1 (encodeSlot p.2))

end OptimalComputation.Evaluation
