import Init.Data.List.Sort.Lemmas

namespace OptimalComputation.Certification
set_option linter.unusedSimpArgs false

/-- Fuel-bounded structural recursion avoids reducing accessibility proofs during
closed kernel evaluation. The fallback is unreachable when fuel is sufficient. -/
def merge (le : α → α → Bool) : Nat → List α → List α → List α
  | 0, xs, ys => xs ++ ys
  | _+1, [], ys => ys
  | _+1, xs, [] => xs
  | n+1, x::xs, y::ys =>
      if le x y then x :: merge le n xs (y::ys) else y :: merge le n (x::xs) ys

theorem merge_eq (le : α → α → Bool) (fuel : Nat) (xs ys : List α)
    (h : xs.length + ys.length ≤ fuel) : merge le fuel xs ys = List.merge xs ys le := by
  induction fuel generalizing xs ys with
  | zero =>
      have hx : xs = [] := List.length_eq_zero_iff.mp (by omega)
      have hy : ys = [] := List.length_eq_zero_iff.mp (by omega)
      subst xs; subst ys; simp [merge, List.merge]
  | succ fuel ih =>
      cases xs with
      | nil => simp [merge, List.merge]
      | cons x xs =>
        cases ys with
        | nil => simp [merge, List.merge]
        | cons y ys =>
          simp only [merge, List.merge]
          split <;> rw [ih _ _ (by simp only [List.length_cons] at h ⊢; omega)]

def sortWithFuel (le : α → α → Bool) : Nat → List α → List α
  | 0, xs => xs
  | _+1, [] => []
  | _+1, [x] => [x]
  | fuel+1, x::y::xs =>
      let all := x::y::xs
      let half := (all.length+1)/2
      let left := sortWithFuel le fuel (all.take half)
      let right := sortWithFuel le fuel (all.drop half)
      merge le (left.length+right.length) left right

theorem sortWithFuel_eq (le : α → α → Bool) (fuel : Nat) (xs : List α)
    (h : xs.length ≤ fuel) : sortWithFuel le fuel xs = xs.mergeSort le := by
  induction fuel generalizing xs with
  | zero =>
      have hx : xs = [] := List.length_eq_zero_iff.mp (by omega)
      subst xs; simp [sortWithFuel, List.mergeSort]
  | succ fuel ih =>
    cases xs with
    | nil => simp [sortWithFuel, List.mergeSort]
    | cons x xs =>
      cases xs with
      | nil => simp [sortWithFuel, List.mergeSort]
      | cons y xs =>
        rw [sortWithFuel, merge_eq _ _ _ _ (by omega)]
        rw [ih _ (by simp only [List.length_take, List.length_drop, List.length_cons] at h ⊢; omega), ih _ (by simp only [List.length_take, List.length_drop, List.length_cons] at h ⊢; omega)]
        rw [List.mergeSort]
        simp [List.MergeSort.Internal.splitInTwo, List.splitAt_eq]

def sort (xs : List α) (le : α → α → Bool) : List α := sortWithFuel le xs.length xs

theorem sort_eq (xs : List α) (le : α → α → Bool) : sort xs le = xs.mergeSort le :=
  sortWithFuel_eq le xs.length xs (by omega)

private def orderedFrom (key : α → Nat) (a : α) : List α → Bool
  | [] => true
  | b :: rest => decide (key a ≤ key b) && orderedFrom key b rest

private theorem orderedFrom_sound (key : α → Nat) (a : α) (rest : List α)
    (h : orderedFrom key a rest = true) :
    rest.Pairwise (fun a b => key a ≤ key b) ∧ ∀ b ∈ rest, key a ≤ key b := by
  induction rest generalizing a with
  | nil => simp
  | cons b rest ih =>
    simp only [orderedFrom, Bool.and_eq_true, decide_eq_true_eq] at h
    have hab : key a ≤ key b := h.1
    obtain ⟨hp, hb⟩ := ih b h.2
    refine ⟨List.pairwise_cons.mpr ⟨hb, hp⟩, ?_⟩
    intro c hc
    rcases List.mem_cons.mp hc with he | hm
    · subst c; exact hab
    · exact Nat.le_trans hab (hb c hm)

/-- Already ordered schedules and monomials need only a linear scan. The
fallback preserves stable merge-sort behavior for arbitrary input order. -/
def sortByNat (xs : List α) (key : α → Nat) : List α :=
  match xs with
  | [] => []
  | a :: rest => if orderedFrom key a rest then xs else sort xs (fun a b => key a ≤ key b)

theorem sortByNat_eq (xs : List α) (key : α → Nat) :
    sortByNat xs key = xs.mergeSort (fun a b => key a ≤ key b) := by
  cases xs with
  | nil => simp [sortByNat]
  | cons a rest =>
    simp only [sortByNat]
    split
    · rename_i h
      obtain ⟨hp, ha⟩ := orderedFrom_sound key a rest h
      have hs : (a :: rest).Pairwise (fun a b => decide (key a ≤ key b) = true) := by
        simpa using List.pairwise_cons.mpr ⟨ha, hp⟩
      exact (List.mergeSort_of_pairwise hs).symm
    · exact sort_eq _ _

end OptimalComputation.Certification
