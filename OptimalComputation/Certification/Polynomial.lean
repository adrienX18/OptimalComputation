import OptimalComputation.Hardware.Arithmetic
import OptimalComputation.Certification.Sort

/-! Sparse integer polynomials used by certification, never by machine execution.
Every normalization operation has an evaluation theorem; equality of resulting
syntax is sufficient evidence, not a claim of completeness over bounded inputs. -/
namespace OptimalComputation.Certification

abbrev Monomial := List Nat
abbrev Term := Monomial × Int
abbrev Polynomial := List Term

namespace Monomial

def eval (x : Nat → Int) : Monomial → Int
  | [] => 1
  | i :: rest => x i * eval x rest

theorem eval_append (x : Nat → Int) (a b : Monomial) :
    eval x (a ++ b) = eval x a * eval x b := by
  induction a with
  | nil => simp [eval]
  | cons i a ih => simp [eval, ih, Int.mul_assoc]

theorem eval_perm (x : Nat → Int) {a b : Monomial} (h : a.Perm b) : eval x a = eval x b := by
  induction h with
  | nil => rfl
  | cons i h ih => simp [eval, ih]
  | swap i j a => simp only [eval]; ac_rfl
  | trans _ _ ih₁ ih₂ => exact ih₁.trans ih₂

def mul (a b : Monomial) : Monomial := sortByNat (a ++ b) id

theorem eval_mul (x : Nat → Int) (a b : Monomial) :
    eval x (mul a b) = eval x a * eval x b :=
  by
    unfold mul
    rw [sortByNat_eq]
    exact (eval_perm x (List.mergeSort_perm _ _)).trans (eval_append x a b)
end Monomial

namespace Polynomial

def eval (x : Nat → Int) : Polynomial → Int
  | [] => 0
  | (m, c) :: rest => c * m.eval x + eval x rest

def term (m : Monomial) (c : Int) : Polynomial := if c = 0 then [] else [(m, c)]

def insert (m : Monomial) (c : Int) : Polynomial → Polynomial
  | [] => term m c
  | (n, d) :: rest =>
      if c = 0 then (n, d) :: rest
      else if m = n then
        if c + d = 0 then rest else (m, c + d) :: rest
      else if compare m n == .lt then (m, c) :: (n, d) :: rest
      else (n, d) :: insert m c rest

/-- Merge canonical term lists in one pass. The fallback preserves evaluation
even with insufficient fuel; `add` always supplies enough to consume both lists. -/
def addWithFuel : Nat → Polynomial → Polynomial → Polynomial
  | 0, p, q => p ++ q
  | _+1, [], q => q
  | _+1, p, [] => p
  | fuel+1, (m,c)::p, (n,d)::q =>
      if m = n then
        if c+d = 0 then addWithFuel fuel p q
        else (m,c+d) :: addWithFuel fuel p q
      else if compare m n == .lt then (m,c) :: addWithFuel fuel p ((n,d)::q)
      else (n,d) :: addWithFuel fuel ((m,c)::p) q

def add (p q : Polynomial) : Polynomial := addWithFuel (p.length+q.length) p q

def scaleTerm (m : Monomial) (c : Int) : Polynomial → Polynomial
  | [] => []
  | (n, d) :: rest => insert (m.mul n) (c * d) (scaleTerm m c rest)

def mul : Polynomial → Polynomial → Polynomial
  | [], _ => []
  | (m, c) :: rest, q => add (scaleTerm m c q) (mul rest q)

def constant (c : Int) : Polynomial := term [] c
def input (i : Nat) : Polynomial := [([i], 1)]
def pow (p : Polynomial) : Nat → Polynomial
  | 0 => constant 1
  | n + 1 => mul (pow p n) p

theorem eval_term (x : Nat → Int) (m : Monomial) (c : Int) :
    eval x (term m c) = c * m.eval x := by
  unfold term
  split <;> simp_all [eval]

theorem eval_insert (x : Nat → Int) (m : Monomial) (c : Int) (q : Polynomial) :
    eval x (insert m c q) = c * m.eval x + eval x q := by
  induction q with
  | nil => simp [insert, eval_term, eval]
  | cons t rest ih =>
    obtain ⟨n, d⟩ := t
    simp only [insert]
    split
    · simp_all [eval]
    · split
      · subst n
        split
        · rename_i hz
          simp only [eval]
          have : c * m.eval x + d * m.eval x = 0 := by rw [← Int.add_mul, hz]; simp
          omega
        · simp only [eval, Int.add_mul]; omega
      · split
        · rfl
        · simp only [eval, ih]; omega

theorem eval_append (x : Nat → Int) (p q : Polynomial) :
    eval x (p ++ q) = eval x p + eval x q := by
  induction p generalizing q with
  | nil => simp [eval]
  | cons t rest ih =>
    obtain ⟨m, c⟩ := t
    simp only [List.cons_append, eval, ih]
    omega

theorem eval_addWithFuel (x : Nat → Int) (fuel : Nat) (p q : Polynomial) :
    eval x (addWithFuel fuel p q) = eval x p + eval x q := by
  induction fuel generalizing p q with
  | zero => exact eval_append x p q
  | succ fuel ih =>
    cases p with
    | nil => simp [addWithFuel, eval]
    | cons t p =>
      cases q with
      | nil => simp [addWithFuel, eval]
      | cons u q =>
        obtain ⟨m,c⟩ := t
        obtain ⟨n,d⟩ := u
        simp only [addWithFuel]
        split
        · rename_i he
          subst n
          split
          · rename_i hz
            simp only [ih, eval]
            have hzero : c * m.eval x + d * m.eval x = 0 := by rw [← Int.add_mul, hz]; simp
            omega
          · simp only [eval, ih, Int.add_mul]; omega
        · split <;> simp only [eval, ih] <;> omega

theorem eval_add (x : Nat → Int) (p q : Polynomial) :
    eval x (add p q) = eval x p + eval x q := eval_addWithFuel x _ p q

theorem eval_scaleTerm (x : Nat → Int) (m : Monomial) (c : Int) (q : Polynomial) :
    eval x (scaleTerm m c q) = (c * m.eval x) * eval x q := by
  induction q with
  | nil => simp [scaleTerm, eval]
  | cons t rest ih =>
    obtain ⟨n, d⟩ := t
    simp only [scaleTerm, eval_insert, Monomial.eval_mul, ih, eval, Int.mul_add]
    ac_rfl

theorem eval_mul (x : Nat → Int) (p q : Polynomial) :
    eval x (mul p q) = eval x p * eval x q := by
  induction p with
  | nil => simp [mul, eval]
  | cons t rest ih =>
    obtain ⟨m, c⟩ := t
    simp only [mul, eval_add, eval_scaleTerm, ih, eval, Int.add_mul]

@[simp] theorem eval_constant (x : Nat → Int) (c : Int) : eval x (constant c) = c := by
  simp [constant, eval_term, Monomial.eval]
@[simp] theorem eval_variable (x : Nat → Int) (i : Nat) : eval x (input i) = x i := by
  simp [input, eval, Monomial.eval]

theorem eval_pow (x : Nat → Int) (p : Polynomial) (n : Nat) :
    eval x (pow p n) = eval x p ^ n := by
  induction n with
  | zero => simp [pow]
  | succ n ih => simp [pow, eval_mul, ih, Int.pow_succ]
end Polynomial

structure Interval where
  lo : Int
  hi : Int
  deriving Repr, DecidableEq, BEq

namespace Interval

def Contains (r : Interval) (v : Int) : Prop := r.lo ≤ v ∧ v ≤ r.hi
instance (r : Interval) (v : Int) : Decidable (r.Contains v) := inferInstanceAs (Decidable (_ ∧ _))
def point (v : Int) : Interval := ⟨v, v⟩
def add (a b : Interval) : Interval := ⟨a.lo + b.lo, a.hi + b.hi⟩
def mul (a b : Interval) : Interval :=
  ⟨min (min (a.lo*b.lo) (a.lo*b.hi)) (min (a.hi*b.lo) (a.hi*b.hi)),
   max (max (a.lo*b.lo) (a.lo*b.hi)) (max (a.hi*b.lo) (a.hi*b.hi))⟩
def square (a : Interval) : Interval := ⟨0, (mul a a).hi⟩
def fits16 (r : Interval) : Bool := decide (Hardware.signed16Min ≤ r.lo ∧ r.hi ≤ Hardware.signed16Max)
def fits48 (r : Interval) : Bool := decide (Hardware.signed48Min ≤ r.lo ∧ r.hi ≤ Hardware.signed48Max)

theorem contains_point (v : Int) : (point v).Contains v := ⟨Int.le_refl _, Int.le_refl _⟩
theorem contains_add {a b : Interval} {u v : Int} (hu : a.Contains u) (hv : b.Contains v) :
    (add a b).Contains (u+v) := by unfold Contains add at *; dsimp at *; omega

theorem contains_mul {a b : Interval} {u v : Int} (hu : a.Contains u) (hv : b.Contains v) :
    (mul a b).Contains (u*v) := by
  obtain ⟨hul, huh⟩ := hu
  obtain ⟨hvl, hvh⟩ := hv
  unfold Contains mul
  dsimp
  have low : min (a.lo*v) (a.hi*v) ≤ u*v := by
    by_cases h : 0 ≤ v
    · have := Int.mul_le_mul_of_nonneg_right hul h; omega
    · have hv0 : v ≤ 0 := by omega
      have := Int.mul_le_mul_of_nonpos_right huh hv0; omega
  have high : u*v ≤ max (a.lo*v) (a.hi*v) := by
    by_cases h : 0 ≤ v
    · have := Int.mul_le_mul_of_nonneg_right huh h; omega
    · have hv0 : v ≤ 0 := by omega
      have := Int.mul_le_mul_of_nonpos_right hul hv0; omega
  have edge (z : Int) : min (z*b.lo) (z*b.hi) ≤ z*v ∧ z*v ≤ max (z*b.lo) (z*b.hi) := by
    by_cases h : 0 ≤ z
    · have := Int.mul_le_mul_of_nonneg_left hvl h
      have := Int.mul_le_mul_of_nonneg_left hvh h
      omega
    · have hz0 : z ≤ 0 := by omega
      have := Int.mul_le_mul_of_nonpos_left hz0 hvl
      have := Int.mul_le_mul_of_nonpos_left hz0 hvh
      omega
  have := edge a.lo
  have := edge a.hi
  omega

theorem contains_square {a : Interval} {v : Int} (h : a.Contains v) :
    (square a).Contains (v*v) := by
  refine ⟨?_, (contains_mul h h).2⟩
  by_cases hv : 0 ≤ v
  · exact Int.mul_nonneg hv hv
  · exact Int.mul_nonneg_of_nonpos_of_nonpos (by omega) (by omega)

theorem signed16 {r : Interval} {v : Int} (h : r.Contains v) (hf : r.fits16 = true) :
    Hardware.InSigned16 v := by
  simp only [fits16, decide_eq_true_eq] at hf
  unfold Hardware.InSigned16; unfold Contains at h; omega

theorem signed48 {r : Interval} {v : Int} (h : r.Contains v) (hf : r.fits48 = true) :
    Hardware.InSigned48 v := by
  simp only [fits48, decide_eq_true_eq] at hf
  unfold Hardware.InSigned48; unfold Contains at h; omega
end Interval

end OptimalComputation.Certification
