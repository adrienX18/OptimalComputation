import OptimalComputation.Hardware.Arithmetic

namespace OptimalComputation.Workloads

open Hardware

/-- Increasing-index accumulation of the first `count` terms. The proof bounds
indices only; it imposes no restriction on the mathematical integer values. -/
def dotPrefix {n : Nat} (a b : Fin n → Int) : (count : Nat) → count ≤ n → Int
  | 0, _ => 0
  | count + 1, h =>
      dotPrefix a b count (by omega) + a ⟨count, by omega⟩ * b ⟨count, by omega⟩

def dot {n : Nat} (a b : Fin n → Int) : Int := dotPrefix a b n (Nat.le_refl n)

@[simp] theorem dotPrefix_zero {n : Nat} (a b : Fin n → Int) (h : 0 ≤ n) :
    dotPrefix a b 0 h = 0 := rfl

theorem dotPrefix_succ {n count : Nat} (a b : Fin n → Int) (h : count + 1 ≤ n) :
    dotPrefix a b (count + 1) h =
      dotPrefix a b count (by omega) + a ⟨count, by omega⟩ * b ⟨count, by omega⟩ := rfl

/-- A reusable all-input bound for every prefix, not just the final answer. -/
theorem dotPrefix_bounds {n : Nat} (a b : Fin n → Int)
    (ha : ∀ i, InSigned16 (a i)) (hb : ∀ i, InSigned16 (b i))
    (count : Nat) (h : count ≤ n) :
    -(count : Int) * 1073741824 ≤ dotPrefix a b count h ∧
      dotPrefix a b count h ≤ (count : Int) * 1073741824 := by
  induction count with
  | zero => simp [dotPrefix]
  | succ count ih =>
      have previous := ih (by omega)
      have product := signed16_product_bounds (ha ⟨count, by omega⟩) (hb ⟨count, by omega⟩)
      rw [dotPrefix_succ]
      omega

/-- At most 16 terms lie within ±2^34, far inside signed 48-bit range. -/
theorem dotPrefix_fits_signed48 {n : Nat} (a b : Fin n → Int)
    (ha : ∀ i, InSigned16 (a i)) (hb : ∀ i, InSigned16 (b i))
    (count : Nat) (h : count ≤ n) (h16 : count ≤ 16) :
    InSigned48 (dotPrefix a b count h) := by
  have bounds := dotPrefix_bounds a b ha hb count h
  simp [InSigned48, signed48Min, signed48Max]
  omega

theorem dot_fits_signed48 {n : Nat} (a b : Fin n → Int)
    (ha : ∀ i, InSigned16 (a i)) (hb : ∀ i, InSigned16 (b i)) (hn : n ≤ 16) :
    InSigned48 (dot a b) := dotPrefix_fits_signed48 a b ha hb n (Nat.le_refl n) hn

/-- Each ordinary next-prefix MAC succeeds with exactly the reference prefix.
This is arithmetic evidence for later candidates, not machine execution safety. -/
theorem dotPrefix_checkedMac {n count : Nat} (a b : Fin n → Int)
    (ha : ∀ i, InSigned16 (a i)) (hb : ∀ i, InSigned16 (b i))
    (h : count + 1 ≤ n) (h16 : count + 1 ≤ 16) :
    checkedMac (a ⟨count, by omega⟩) (b ⟨count, by omega⟩)
      (dotPrefix a b count (by omega)) =
        .ok ⟨dotPrefix a b (count + 1) h, dotPrefix_fits_signed48 a b ha hb _ h h16⟩ := by
  apply checkedMac_accepts (ha _) (hb _)
  exact dotPrefix_fits_signed48 a b ha hb count (by omega) (by omega)

end OptimalComputation.Workloads
