import Std

/-! Exact numeric rules for `arty-model-v1`. Arithmetic checks mathematical
integers before constructing bounded values; no operation wraps or saturates. -/

namespace OptimalComputation.Hardware

def signed16Min : Int := -32768
def signed16Max : Int := 32767
def signed48Min : Int := -140737488355328
def signed48Max : Int := 140737488355327

def InSigned16 (x : Int) : Prop := signed16Min ≤ x ∧ x ≤ signed16Max
def InSigned48 (x : Int) : Prop := signed48Min ≤ x ∧ x ≤ signed48Max

instance (x : Int) : Decidable (InSigned16 x) :=
  inferInstanceAs (Decidable (signed16Min ≤ x ∧ x ≤ signed16Max))
instance (x : Int) : Decidable (InSigned48 x) :=
  inferInstanceAs (Decidable (signed48Min ≤ x ∧ x ≤ signed48Max))

abbrev Signed16 := { x : Int // InSigned16 x }
abbrev Signed48 := { x : Int // InSigned48 x }

theorem signed16_endpoints : signed16Min = -(2^15) ∧ signed16Max = 2^15 - 1 := by decide
theorem signed48_endpoints : signed48Min = -(2^47) ∧ signed48Max = 2^47 - 1 := by decide

theorem signed16_fits_signed48 {x : Int} (h : InSigned16 x) : InSigned48 x := by
  simp [InSigned16, signed16Min, signed16Max] at h
  simp [InSigned48, signed48Min, signed48Max]
  omega

/-- A conservative product bound, including the asymmetric negative endpoint. -/
theorem signed16_product_bounds {a b : Int} (ha : InSigned16 a) (hb : InSigned16 b) :
    -1073741824 ≤ a * b ∧ a * b ≤ 1073741824 := by
  simp [InSigned16, signed16Min, signed16Max] at ha hb
  by_cases h : 0 ≤ b
  · have lo := Int.mul_le_mul_of_nonneg_right ha.1 h
    have hi := Int.mul_le_mul_of_nonneg_right ha.2 h
    omega
  · have h' : b ≤ 0 := by omega
    have lo := Int.mul_le_mul_of_nonpos_right ha.2 h'
    have hi := Int.mul_le_mul_of_nonpos_right ha.1 h'
    omega

theorem signed16_product_fits {a b : Int} (ha : InSigned16 a) (hb : InSigned16 b) :
    InSigned48 (a * b) := by
  have := signed16_product_bounds ha hb
  simp [InSigned48, signed48Min, signed48Max]
  omega

inductive ArithmeticOperand where
  | left | right | accumulator
  deriving Repr, DecidableEq, BEq

inductive ArithmeticError where
  | operandOutOfRange (operand : ArithmeticOperand) (bits : Nat) (value : Int)
  | resultOutOfRange (value : Int)
  deriving Repr, DecidableEq, BEq

/-- Only signed 48-bit results can enter a register or a numeric memory slot. -/
def checkedResult (value : Int) : Except ArithmeticError Signed48 :=
  if h : InSigned48 value then .ok ⟨value, h⟩ else .error (.resultOutOfRange value)

def checkedAdd (a b : Int) : Except ArithmeticError Signed48 :=
  if InSigned48 a then
    if InSigned48 b then checkedResult (a + b)
    else .error (.operandOutOfRange .right 48 b)
  else .error (.operandOutOfRange .left 48 a)

def checkedMul (a b : Int) : Except ArithmeticError Signed48 :=
  if InSigned16 a then
    if InSigned16 b then checkedResult (a * b)
    else .error (.operandOutOfRange .right 16 b)
  else .error (.operandOutOfRange .left 16 a)

/-- Check multiplicands left-to-right, then accumulator, then exact result. -/
def checkedMac (a b accumulator : Int) : Except ArithmeticError Signed48 :=
  if InSigned16 a then
    if InSigned16 b then
      if InSigned48 accumulator then checkedResult (accumulator + a * b)
      else .error (.operandOutOfRange .accumulator 48 accumulator)
    else .error (.operandOutOfRange .right 16 b)
  else .error (.operandOutOfRange .left 16 a)

@[simp] theorem checkedResult_accepts (x : Int) (h : InSigned48 x) :
    checkedResult x = .ok ⟨x, h⟩ := by simp [checkedResult, h]

theorem checkedResult_rejects (x : Int) (h : ¬ InSigned48 x) :
    checkedResult x = .error (.resultOutOfRange x) := by simp [checkedResult, h]

theorem checkedAdd_accepts {a b : Int} (ha : InSigned48 a) (hb : InSigned48 b)
    (hresult : InSigned48 (a + b)) :
    checkedAdd a b = .ok ⟨a + b, hresult⟩ := by
  simp [checkedAdd, ha, hb, hresult]

theorem checkedMul_accepts {a b : Int} (ha : InSigned16 a) (hb : InSigned16 b) :
    checkedMul a b = .ok ⟨a * b, signed16_product_fits ha hb⟩ := by
  simp [checkedMul, ha, hb, signed16_product_fits ha hb]

theorem checkedMac_accepts {a b accumulator : Int}
    (ha : InSigned16 a) (hb : InSigned16 b) (hc : InSigned48 accumulator)
    (hresult : InSigned48 (accumulator + a * b)) :
    checkedMac a b accumulator = .ok ⟨accumulator + a * b, hresult⟩ := by
  simp [checkedMac, ha, hb, hc, hresult]

/-- Successful checked operations compute precisely the indicated integer value. -/
theorem checkedAdd_value {a b : Int} {r : Signed48} (h : checkedAdd a b = .ok r) :
    r.val = a + b := by
  unfold checkedAdd checkedResult at h
  split at h <;> (try split at h) <;> (try split at h) <;> simp_all
  all_goals exact (congrArg Subtype.val h).symm

theorem checkedMul_value {a b : Int} {r : Signed48} (h : checkedMul a b = .ok r) :
    r.val = a * b := by
  unfold checkedMul checkedResult at h
  split at h <;> (try split at h) <;> (try split at h) <;> simp_all
  all_goals exact (congrArg Subtype.val h).symm

theorem checkedMac_value {a b accumulator : Int} {r : Signed48}
    (h : checkedMac a b accumulator = .ok r) : r.val = accumulator + a * b := by
  unfold checkedMac checkedResult at h
  split at h <;> (try split at h) <;> (try split at h) <;> (try split at h) <;> simp_all
  all_goals exact (congrArg Subtype.val h).symm

end OptimalComputation.Hardware
