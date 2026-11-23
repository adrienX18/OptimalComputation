import OptimalComputation.Hardware.Arithmetic

/-! Numeric memory is one full 64-bit slot per value. The canonical predicate
rejects any bit pattern that is not a sign extension of a signed 48-bit value. -/

namespace OptimalComputation.Hardware

abbrev RawSlot64 := BitVec 64
def CanonicalSlot (bits : RawSlot64) : Prop := InSigned48 bits.toInt
instance (bits : RawSlot64) : Decidable (CanonicalSlot bits) :=
  inferInstanceAs (Decidable (InSigned48 bits.toInt))
abbrev Slot64 := { bits : RawSlot64 // CanonicalSlot bits }

private theorem encode48_toInt (value : Signed48) :
    (BitVec.ofInt 64 value.val).toInt = value.val := by
  have h := value.property
  simp [InSigned48, signed48Min, signed48Max] at h
  apply BitVec.toInt_ofInt_eq_self (by decide) <;> omega

/-- `ofInt` is used only after a range proof, so encoding cannot wrap. -/
def encodeSlot (value : Signed48) : Slot64 :=
  ⟨BitVec.ofInt 64 value.val, by
    unfold CanonicalSlot
    rw [encode48_toInt]
    exact value.property⟩

def decodeSlot (slot : Slot64) : Signed48 := ⟨slot.val.toInt, slot.property⟩

@[simp] theorem decode_encode_slot (value : Signed48) :
    decodeSlot (encodeSlot value) = value := by
  apply Subtype.ext
  exact encode48_toInt value

@[simp] theorem encode_decode_slot (slot : Slot64) :
    encodeSlot (decodeSlot slot) = slot := by
  apply Subtype.ext
  exact BitVec.ofInt_toInt

/-- An explicit bit-level characterization: keep 48 bits then sign extend. -/
theorem canonical_iff_sign_extension (bits : RawSlot64) :
    CanonicalSlot bits ↔ (bits.signExtend 48).signExtend 64 = bits := by
  constructor
  · intro h
    have bounds := h
    simp [CanonicalSlot, InSigned48, signed48Min, signed48Max] at bounds
    have truncated : (bits.signExtend 48).toInt = bits.toInt := by
      unfold BitVec.signExtend
      apply BitVec.toInt_ofInt_eq_self (by decide) <;> omega
    apply BitVec.toInt_inj.mp
    rw [BitVec.toInt_signExtend_of_le (by decide), truncated]
  · intro h
    have same := congrArg BitVec.toInt h
    rw [BitVec.toInt_signExtend_of_le (by decide)] at same
    have lo := BitVec.le_toInt (bits.signExtend 48)
    have hi := BitVec.toInt_lt (x := bits.signExtend 48)
    simp [CanonicalSlot, InSigned48, signed48Min, signed48Max]
    omega

inductive StorageError where
  | noncanonicalSlot (bits : RawSlot64)
  deriving Repr, DecidableEq, BEq

def validateSlot (bits : RawSlot64) : Except StorageError Slot64 :=
  if h : CanonicalSlot bits then .ok ⟨bits, h⟩ else .error (.noncanonicalSlot bits)

theorem validateSlot_accepts (bits : RawSlot64) (h : CanonicalSlot bits) :
    validateSlot bits = .ok ⟨bits, h⟩ := by simp [validateSlot, h]

theorem validateSlot_rejects (bits : RawSlot64) (h : ¬ CanonicalSlot bits) :
    validateSlot bits = .error (.noncanonicalSlot bits) := by simp [validateSlot, h]

end OptimalComputation.Hardware
