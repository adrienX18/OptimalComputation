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

end OptimalComputation.Certification
