import OptimalComputation.Workloads.MatrixAdapters

/-! Additional experiment domains. Indices describe logical row-major data,
never physical memory. References use mathematical integers. -/
namespace OptimalComputation.Workloads
open Hardware
set_option maxRecDepth 10000
set_option linter.unusedSimpArgs false

structure FlatWorkload where
  identifier : String
  inputs : Nat
  outputs : Nat
  allowed : Vector Int inputs → Prop
  domainDecidable : ∀ x, Decidable (allowed x)
  inputFits : ∀ x, allowed x → ∀ i : Fin inputs, InSigned48 x[i.val]
  reference : Vector Int inputs → Vector Int outputs

def FlatWorkload.specification (w : FlatWorkload) : Specification :=
  ⟨w.identifier, Vector Int w.inputs, w.allowed, Vector Int w.outputs, w.reference⟩

def FlatWorkload.adapter (w : FlatWorkload) : ScalarAdapter w.specification where
  shape := ⟨w.identifier, w.inputs, w.outputs⟩
  identifier := rfl
  inputScalars := id
  decodeInput := id
  input_roundtrip := fun _ => rfl
  input_fits := w.inputFits
  outputScalars := id
  decodeOutput := id
  output_roundtrip := fun _ => rfl

namespace Polynomial
abbrev Input := Vector Int 24
def Allowed (x : Input) : Prop :=
  (∀ k : Fin 8, -8 ≤ x[k.val] ∧ x[k.val] ≤ 7) ∧
  (∀ i : Fin 16, -4 ≤ x[8 + i.val] ∧ x[8 + i.val] ≤ 3)
instance (x : Input) : Decidable (Allowed x) := inferInstanceAs (Decidable (_ ∧ _))
def coefficient (x : Input) (k : Fin 8) : Int := x[k.val]
def point (x : Input) (i : Fin 16) : Int := x[8 + i.val]
/-- Explicit powers, including the constant term. -/
def atPoint (x : Input) (i : Fin 16) : Int :=
  coefficient x 0 + dot (fun k : Fin 7 => coefficient x ⟨k.val + 1, by omega⟩)
    (fun k => point x i ^ (k.val + 1))
def reference (x : Input) : Vector Int 16 := Vector.ofFn (atPoint x)

theorem power_fits {v : Int} (hv : -4 ≤ v ∧ v ≤ 3) (n : Nat) (hn : n ≤ 7) :
    InSigned16 (v ^ n) := by
  have hcases : v = -4 ∨ v = -3 ∨ v = -2 ∨ v = -1 ∨ v = 0 ∨ v = 1 ∨ v = 2 ∨ v = 3 := by omega
  have ncases : n = 0 ∨ n = 1 ∨ n = 2 ∨ n = 3 ∨ n = 4 ∨ n = 5 ∨ n = 6 ∨ n = 7 := by omega
  rcases hcases with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
    rcases ncases with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;> decide

theorem coefficient_fits (x : Input) (h : Allowed x) (k : Fin 8) :
    InSigned16 (coefficient x k) := by
  have := h.1 k
  simp only [coefficient, InSigned16, signed16Min, signed16Max]
  omega

/-- Tight uniform absolute bound; it is attained by alternating coefficients at -4. -/
theorem reference_bounds (x : Input) (h : Allowed x) (i : Fin 16) :
    -170391 ≤ atPoint x i ∧ atPoint x i ≤ 170391 := by
  have h0 : -8 ≤ x[0] ∧ x[0] ≤ 7 := h.1 ⟨0, by decide⟩
  have h1 : -8 ≤ x[1] ∧ x[1] ≤ 7 := h.1 ⟨1, by decide⟩
  have h2 : -8 ≤ x[2] ∧ x[2] ≤ 7 := h.1 ⟨2, by decide⟩
  have h3 : -8 ≤ x[3] ∧ x[3] ≤ 7 := h.1 ⟨3, by decide⟩
  have h4 : -8 ≤ x[4] ∧ x[4] ≤ 7 := h.1 ⟨4, by decide⟩
  have h5 : -8 ≤ x[5] ∧ x[5] ≤ 7 := h.1 ⟨5, by decide⟩
  have h6 : -8 ≤ x[6] ∧ x[6] ≤ 7 := h.1 ⟨6, by decide⟩
  have h7 : -8 ≤ x[7] ∧ x[7] ≤ 7 := h.1 ⟨7, by decide⟩
  have hp := h.2 i
  have cases : point x i = -4 ∨ point x i = -3 ∨ point x i = -2 ∨ point x i = -1 ∨
      point x i = 0 ∨ point x i = 1 ∨ point x i = 2 ∨ point x i = 3 := by
    unfold point; omega
  rcases cases with hp | hp | hp | hp | hp | hp | hp | hp <;>
    simp [atPoint, dot, dotPrefix, coefficient, hp] <;> omega

def workload : FlatWorkload where
  identifier := "polynomial-degree7-points16-v1"
  inputs := 24
  outputs := 16
  allowed := Allowed
  domainDecidable := inferInstance
  inputFits := by
    intro x h i
    apply signed16_fits_signed48
    by_cases hi : i.val < 8
    · exact coefficient_fits x h ⟨i.val, hi⟩
    · have hp := h.2 ⟨i.val - 8, by omega⟩
      simp only [InSigned16, signed16Min, signed16Max]
      have he : 8 + (i.val - 8) = i.val := by omega
      simp only [he] at hp
      omega
  reference := reference
end Polynomial

namespace Gram
abbrev Input := Vector Int 256
def Allowed (x : Input) : Prop := ∀ k : Fin 256, InSigned16 x[k.val]
instance (x : Input) : Decidable (Allowed x) :=
  @Nat.decidableForallFin 256 (fun k => InSigned16 x[k.val]) (fun _ => inferInstance)
def entry (x : Input) (i j : Index16) : Int := x[(matrixIndex i j).val]
def atEntry (x : Input) (i j : Index16) : Int := dot (entry x i) (entry x j)
def reference (x : Input) : Vector Int 256 := matrixScalars (atEntry x)
theorem dot_comm {n : Nat} (a b : Fin n → Int) : dot a b = dot b a := by
  suffices ∀ k (hk : k ≤ n), dotPrefix a b k hk = dotPrefix b a k hk from this n (by omega)
  intro k hk
  induction k with
  | zero => rfl
  | succ k ih => simp only [dotPrefix, ih (by omega), Int.mul_comm]
theorem symmetric (x : Input) (i j : Index16) : atEntry x i j = atEntry x j i := dot_comm _ _
def workload : FlatWorkload where
  identifier := "gram-16x16-signed16-v1"
  inputs := 256
  outputs := 256
  allowed := Allowed
  domainDecidable := inferInstance
  inputFits := fun _ h i => signed16_fits_signed48 (h i)
  reference := reference
end Gram

namespace TwoStage
abbrev Input := Vector Int 528
def Allowed (x : Input) : Prop :=
  (∀ k : Fin 272, -45 ≤ x[k.val] ∧ x[k.val] ≤ 45) ∧
  (∀ k : Fin 256, InSigned16 x[272 + k.val])
instance (x : Input) : Decidable (Allowed x) := inferInstanceAs (Decidable (_ ∧ _))
def a (x : Input) (i k : Index16) : Int := x[(matrixIndex i k).val]
def vector (x : Input) (k : Index16) : Int := x[256 + k.val]
def b (x : Input) (i k : Index16) : Int := x[272 + (matrixIndex i k).val]
def intermediate (x : Input) (i : Index16) : Int := dot (a x i) (vector x)
def reference (x : Input) : Vector Int 16 := Vector.ofFn fun i => dot (b x i) (intermediate x)

theorem small_product {a b : Int} (ha : -45 ≤ a ∧ a ≤ 45) (hb : -45 ≤ b ∧ b ≤ 45) :
    -2025 ≤ a * b ∧ a * b ≤ 2025 := by
  by_cases h : 0 ≤ b
  · have := Int.mul_le_mul_of_nonneg_right ha.1 h
    have := Int.mul_le_mul_of_nonneg_right ha.2 h
    omega
  · have h' : b ≤ 0 := by omega
    have := Int.mul_le_mul_of_nonpos_right ha.1 h'
    have := Int.mul_le_mul_of_nonpos_right ha.2 h'
    omega

theorem intermediate_fits (x : Input) (h : Allowed x) (i : Index16) :
    InSigned16 (intermediate x i) := by
  have bound (n : Nat) (hn : n ≤ 16) :
      -(n : Int) * 2025 ≤ dotPrefix (a x i) (vector x) n hn ∧
      dotPrefix (a x i) (vector x) n hn ≤ (n : Int) * 2025 := by
    induction n with
    | zero => simp [dotPrefix]
    | succ n ih =>
      have prev := ih (by omega)
      have ha := h.1 ⟨i.val * 16 + n, by omega⟩
      have hb := h.1 ⟨256 + n, by omega⟩
      have prod := small_product ha hb
      simp only [Fin.val_mk] at prod
      simp only [dotPrefix, a, vector, matrixIndex]
      omega
  have := bound 16 (by omega)
  simp only [InSigned16, signed16Min, signed16Max, intermediate, dot]
  omega

def workload : FlatWorkload where
  identifier := "two-stage-linear-16-signed16-v1"
  inputs := 528
  outputs := 16
  allowed := Allowed
  domainDecidable := inferInstance
  inputFits := by
    intro x h i
    apply signed16_fits_signed48
    by_cases hi : i.val < 272
    · have hh := h.1 ⟨i.val, hi⟩
      simp only [Fin.val_mk] at hh
      simp only [InSigned16, signed16Min, signed16Max]
      omega
    · have hb := h.2 ⟨i.val - 272, by omega⟩
      have he : 272 + (i.val - 272) = i.val := by omega
      simpa only [he] using hb
  reference := reference
end TwoStage
end OptimalComputation.Workloads
