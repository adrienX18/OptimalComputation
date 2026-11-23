import OptimalComputation.Examples.ExperimentBaselines

namespace OptimalComputation.Examples.ExperimentBaselines
open Hardware Workloads SerialNetwork
set_option backward.isDefEq.respectTransparency false
set_option maxRecDepth 10000
set_option maxHeartbeats 2000000
set_option linter.unusedSimpArgs false

def polyPoint (j : Fin 128) : Fin 16 := ⟨j.val / 8, by omega⟩
def polyPhase (j : Fin 128) : Nat := j.val % 8

def powerIndex (i : Fin 16) (k : Fin 7) : Fin 128 := ⟨8 * i.val + k.val, by omega⟩
def polyResultIndex (i : Fin 16) : Fin 128 := ⟨8 * i.val + 7, by omega⟩
def pointSource (i : Fin 16) : Source 24 128 := .inl ⟨8 + i.val, by omega⟩

def polyValue (x : Polynomial.Input) (j : Fin 128) : Int :=
  if polyPhase j < 7 then Polynomial.point x (polyPoint j) ^ (polyPhase j + 1)
  else Polynomial.atPoint x (polyPoint j)

theorem power_value (x : Polynomial.Input) (i : Fin 16) (k : Fin 7) :
    polyValue x (powerIndex i k) = Polynomial.point x i ^ (k.val + 1) := by
  have hr : polyPoint (powerIndex i k) = i := by apply Fin.ext; simp only [polyPoint, powerIndex]; omega
  have hk : polyPhase (powerIndex i k) = k.val := by simp only [polyPhase, powerIndex]; omega
  simp only [polyValue, hr, hk, k.isLt, ↓reduceIte]

theorem result_value (x : Polynomial.Input) (i : Fin 16) :
    polyValue x (polyResultIndex i) = Polynomial.atPoint x i := by
  have hr : polyPoint (polyResultIndex i) = i := by apply Fin.ext; simp only [polyPoint, polyResultIndex]; omega
  have hk : polyPhase (polyResultIndex i) = 7 := by simp only [polyPhase, polyResultIndex]; omega
  simp [polyValue, hr, hk]

def previousPower (j : Fin 128) (h : polyPhase j < 7) : Fin 128 :=
  powerIndex (polyPoint j) ⟨polyPhase j - 1, by omega⟩

theorem previous_earlier (j : Fin 128) (h : polyPhase j < 7) (h0 : polyPhase j ≠ 0) :
    (previousPower j h).val < j.val := by
  simp only [previousPower, powerIndex, polyPoint, polyPhase] at *
  omega

def polyCopy (j : Fin 128) : Node 24 128 := {
  seed := some (pointSource (polyPoint j))
  terms := 0
  short := by decide
  left := Fin.elim0
  right := Fin.elim0
}
def polyPower (j : Fin 128) (h : polyPhase j < 7) : Node 24 128 := {
  terms := 1
  short := by decide
  left := fun _ => .inr (previousPower j h)
  right := fun _ => pointSource (polyPoint j)
}
def polySum (j : Fin 128) : Node 24 128 := {
  seed := some (.inl 0)
  terms := 7
  short := by decide
  left := fun k => .inl ⟨k.val + 1, by omega⟩
  right := fun k => .inr (powerIndex (polyPoint j) k)
}
def polyNode (j : Fin 128) : Node 24 128 :=
  if polyPhase j = 0 then polyCopy j
  else if h : polyPhase j < 7 then polyPower j h else polySum j

theorem node_cases (j : Fin 128) (P : Node 24 128 → Prop)
    (hc : polyPhase j = 0 → P (polyCopy j))
    (hp : polyPhase j ≠ 0 → ∀ h : polyPhase j < 7, P (polyPower j h))
    (hs : ¬polyPhase j < 7 → P (polySum j)) : P (polyNode j) := by
  unfold polyNode
  split
  · exact hc (by assumption)
  · split
    · exact hp (by assumption) (by assumption)
    · exact hs (by assumption)

theorem poly_point_fits (x : Polynomial.Input) (hx : Polynomial.Allowed x) (j : Fin 128) :
    InSigned16 (sourceValue x (polyValue x) (pointSource (polyPoint j))) := by
  have hp := hx.2 (polyPoint j)
  change InSigned16 (Polynomial.point x (polyPoint j))
  simp only [Polynomial.point, InSigned16, signed16Min, signed16Max]
  omega

def polynomial : Network Polynomial.workload where
  count := 128
  fits := by decide
  node := polyNode
  output := polyResultIndex
  value := polyValue
  seedEarlier := by
    intro j
    apply node_cases j (fun d => ∀ s, d.seed = some s → earlier j.val s)
    · intro h s he; cases he; trivial
    · intro h0 h s he; cases he
    · intro h s he; cases he; trivial
  leftEarlier := by
    intro j
    apply node_cases j (fun d => ∀ k, earlier j.val (d.left k))
    · intro h k; exact Fin.elim0 k
    · intro h0 h k; exact previous_earlier j h h0
    · intro h k; trivial
  rightEarlier := by
    intro j
    apply node_cases j (fun d => ∀ k, earlier j.val (d.right k))
    · intro h k; exact Fin.elim0 k
    · intro h0 h k; trivial
    · intro h k
      change 8 * (j.val / 8) + k.val < j.val
      have hk : k.val < 7 := k.isLt
      simp only [polyPhase] at h
      omega
  seedFits := by
    intro x hx j
    apply node_cases j (fun d => ∀ s, d.seed = some s → InSigned16 (sourceValue x (polyValue x) s))
    · intro h s he; cases he; exact poly_point_fits x hx j
    · intro h0 h s he; cases he
    · intro h s he; cases he; exact Polynomial.coefficient_fits x hx 0
  leftFits := by
    intro x hx j
    apply node_cases j (fun d => ∀ k, InSigned16 (sourceValue x (polyValue x) (d.left k)))
    · intro h k; exact Fin.elim0 k
    · intro h0 h k
      change InSigned16 (polyValue x (previousPower j h))
      simp only [previousPower, power_value]
      exact Polynomial.power_fits (hx.2 (polyPoint j)) _ (by omega)
    · intro h k
      exact Polynomial.coefficient_fits x hx ⟨k.val + 1, by have hk : k.val < 7 := k.isLt; omega⟩
  rightFits := by
    intro x hx j
    apply node_cases j (fun d => ∀ k, InSigned16 (sourceValue x (polyValue x) (d.right k)))
    · intro h k; exact Fin.elim0 k
    · intro h0 h k; exact poly_point_fits x hx j
    · intro h k
      change InSigned16 (polyValue x (powerIndex (polyPoint j) k))
      rw [power_value]
      exact Polynomial.power_fits (hx.2 (polyPoint j)) _ (by omega)
  equation := by
    intro x hx j
    apply node_cases j (fun d => polyValue x j =
      (d.seed.map (sourceValue x (polyValue x))).getD 0 +
      dot (sourceValue x (polyValue x) ∘ d.left) (sourceValue x (polyValue x) ∘ d.right))
    · intro h
      simp [polyCopy, polyValue, h, sourceValue, pointSource, Polynomial.point, dot, dotPrefix, Int.pow_one]
      rfl
    · intro h0 h
      have he : polyPhase j - 1 + 1 = polyPhase j := by omega
      change polyValue x j = 0 + (0 + polyValue x (previousPower j h) * Polynomial.point x (polyPoint j))
      rw [show polyValue x j = Polynomial.point x (polyPoint j) ^ (polyPhase j + 1) by simp [polyValue, h]]
      simp only [previousPower, power_value, he, Int.zero_add, Int.pow_succ]
    · intro h
      simp only [polySum, Option.map_some, Option.getD_some, Function.comp_def, sourceValue, power_value]
      change polyValue x j = Polynomial.atPoint x (polyPoint j)
      simp [polyValue, h]
  result := by
    intro x hx i
    rw [result_value]
    simp [Polynomial.workload, Polynomial.reference]

def polynomialVerified := SerialNetwork.verified polynomial "polynomial-naive-v1" (by decide)
  (code_positive _ (by decide))

end OptimalComputation.Examples.ExperimentBaselines
