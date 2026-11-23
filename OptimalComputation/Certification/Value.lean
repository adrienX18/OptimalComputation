import OptimalComputation.Certification.Polynomial
import OptimalComputation.Hardware.Machine

namespace OptimalComputation.Certification
open Hardware
set_option linter.unusedSimpArgs false

abbrev Box := List Interval

def Box.at (box : Box) (i : Nat) : Interval := (box[i]?).getD (Interval.point 0)
def Box.Allowed (box : Box) (x : Nat → Int) : Prop := ∀ i, (box.at i).Contains (x i)

def Monomial.bound (box : Box) : Monomial → Interval
  | [] => Interval.point 1
  | [i] => box.at i
  | i :: j :: rest =>
      if i = j then (box.at i).square.mul (bound box rest)
      else (box.at i).mul (bound box (j :: rest))

theorem Monomial.bound_sound (box : Box) (x : Nat → Int) (hx : box.Allowed x) (m : Monomial) :
    (m.bound box).Contains (m.eval x) := by
  induction m using Monomial.bound.induct with
  | case1 => exact Interval.contains_point 1
  | case2 i => simpa [Monomial.bound, Monomial.eval] using hx i
  | case3 i rest ih =>
      simpa [Monomial.bound, Monomial.eval, Int.mul_assoc] using
        Interval.contains_mul (Interval.contains_square (hx i)) ih
  | case4 i j rest h ih =>
      simpa [Monomial.bound, h, Monomial.eval] using Interval.contains_mul (hx i) ih

def Polynomial.bound (box : Box) : Polynomial → Interval
  | [] => Interval.point 0
  | (m, c) :: rest => ((Interval.point c).mul (m.bound box)).add (bound box rest)

theorem Polynomial.bound_sound (box : Box) (x : Nat → Int) (hx : box.Allowed x) (p : Polynomial) :
    (p.bound box).Contains (p.eval x) := by
  induction p with
  | nil => exact Interval.contains_point 0
  | cons t rest ih =>
    obtain ⟨m, c⟩ := t
    exact Interval.contains_add
      (Interval.contains_mul (Interval.contains_point c) (m.bound_sound box x hx)) ih

/-- An abstract value is accompanied by a range proof for the whole input box.
Proof fields erase at runtime; the kernel checks their construction once. -/
structure Value (box : Box) where
  polynomial : Polynomial
  interval : Interval
  sound : ∀ x, box.Allowed x → interval.Contains (polynomial.eval x)
  fits : interval.fits48 = true

def Value.eval (v : Value box) (x : Nat → Int) (hx : box.Allowed x) : Signed48 :=
  ⟨v.polynomial.eval x, Interval.signed48 (v.sound x hx) v.fits⟩

inductive ArithmeticFailure where
  | rangeNotProved (operand : String) (bits : Nat) (interval : Interval)
  | expressionBudget (terms : Nat)
  | degreeBudget (degree : Nat)
  deriving Repr, DecidableEq, BEq

/-- Degree and term caps make polynomial growth an explicit inconclusive result. -/
def maxDegree : Nat := 64

def Value.ofPolynomial (box : Box) (p : Polynomial) (maxTerms : Nat) : Except ArithmeticFailure (Value box) :=
  if p.length > maxTerms then .error (.expressionBudget p.length)
  else if let some term := p.find? (fun t => t.1.length > maxDegree) then
    .error (.degreeBudget term.1.length)
  else
    let interval := p.bound box
    if h : interval.fits48 = true then
      .ok ⟨p, interval, p.bound_sound box, h⟩
    else .error (.rangeNotProved "result" 48 interval)

def Value.zero (box : Box) : Value box :=
  ⟨[], Interval.point 0, fun _ _ => Interval.contains_point 0, by decide⟩

@[simp] theorem Value.eval_zero (box : Box) (x : Nat → Int) (hx : box.Allowed x) :
    (zero box).eval x hx = zero48 := rfl

def Value.require16 (v : Value box) (operand : String) : Except ArithmeticFailure Unit :=
  if v.interval.fits16 then .ok () else .error (.rangeNotProved operand 16 v.interval)

def Value.add (maxTerms : Nat) (a b : Value box) : Except ArithmeticFailure (Value box) :=
  ofPolynomial box (a.polynomial.add b.polynomial) maxTerms

def Value.mul (maxTerms : Nat) (a b : Value box) : Except ArithmeticFailure (Value box) := do
  a.require16 "left"
  b.require16 "right"
  if a.polynomial.length * b.polynomial.length > maxTerms then
    throw (.expressionBudget (a.polynomial.length * b.polynomial.length))
  ofPolynomial box (a.polynomial.mul b.polynomial) maxTerms

def Value.mac (maxTerms : Nat) (a b acc : Value box) : Except ArithmeticFailure (Value box) := do
  a.require16 "left"
  b.require16 "right"
  if a.polynomial.length * b.polynomial.length > maxTerms then
    throw (.expressionBudget (a.polynomial.length * b.polynomial.length))
  ofPolynomial box (acc.polynomial.add (a.polynomial.mul b.polynomial)) maxTerms

theorem Value.ofPolynomial_eq {box : Box} {p : Polynomial} {maxTerms : Nat} {v : Value box}
    (h : ofPolynomial box p maxTerms = .ok v) : v.polynomial = p := by
  unfold ofPolynomial at h
  split at h
  · contradiction
  · split at h
    · contradiction
    · dsimp only at h
      split at h
      · cases h; rfl
      · contradiction

theorem Value.require16_sound (v : Value box) (operand : String) (x : Nat → Int)
    (hx : box.Allowed x) (h : v.require16 operand = .ok ()) : InSigned16 (v.eval x hx).val := by
  unfold require16 at h
  split at h
  · exact Interval.signed16 (v.sound x hx) (by assumption)
  · contradiction

theorem Value.add_sound (a b v : Value box) (maxTerms : Nat) (h : a.add maxTerms b = .ok v)
    (x : Nat → Int) (hx : box.Allowed x) :
    checkedAdd (a.eval x hx).val (b.eval x hx).val = .ok (v.eval x hx) := by
  have he := ofPolynomial_eq h
  have hv : (v.eval x hx).val = (a.eval x hx).val + (b.eval x hx).val := by
    simp only [Value.eval, he, Polynomial.eval_add]
  have hb := (v.eval x hx).property
  rw [hv] at hb
  have hh := checkedAdd_accepts (a.eval x hx).property (b.eval x hx).property hb
  simpa only [← hv] using hh

theorem Value.mul_sound (a b v : Value box) (maxTerms : Nat) (h : a.mul maxTerms b = .ok v)
    (x : Nat → Int) (hx : box.Allowed x) :
    checkedMul (a.eval x hx).val (b.eval x hx).val = .ok (v.eval x hx) := by
  unfold mul at h
  cases ha : a.require16 "left" <;> simp only [ha, bind, Except.bind] at h
  · contradiction
  cases hb : b.require16 "right" <;> simp only [hb, bind, Except.bind] at h
  · contradiction
  split at h
  · simp [throw] at h
  · have he := ofPolynomial_eq h
    have hv : (v.eval x hx).val = (a.eval x hx).val * (b.eval x hx).val := by
      simp only [Value.eval, he, Polynomial.eval_mul]
    have ha' := require16_sound a "left" x hx (by simpa using ha)
    have hb' := require16_sound b "right" x hx (by simpa using hb)
    have hh := checkedMul_accepts ha' hb'
    simpa only [← hv] using hh

theorem Value.mac_sound (a b acc v : Value box) (maxTerms : Nat)
    (h : a.mac maxTerms b acc = .ok v) (x : Nat → Int) (hx : box.Allowed x) :
    checkedMac (a.eval x hx).val (b.eval x hx).val (acc.eval x hx).val = .ok (v.eval x hx) := by
  unfold mac at h
  cases ha : a.require16 "left" <;> simp only [ha, bind, Except.bind] at h
  · contradiction
  cases hb : b.require16 "right" <;> simp only [hb, bind, Except.bind] at h
  · contradiction
  split at h
  · simp [throw] at h
  · have he := ofPolynomial_eq h
    have hv : (v.eval x hx).val = (acc.eval x hx).val + (a.eval x hx).val * (b.eval x hx).val := by
      simp only [Value.eval, he, Polynomial.eval_add, Polynomial.eval_mul]
    have hr := (v.eval x hx).property
    rw [hv] at hr
    have hh := checkedMac_accepts (require16_sound a "left" x hx (by simpa using ha))
      (require16_sound b "right" x hx (by simpa using hb)) (acc.eval x hx).property hr
    simpa only [← hv] using hh

end OptimalComputation.Certification
