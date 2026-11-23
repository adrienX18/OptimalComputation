import OptimalComputation.Evaluation.Serial
import OptimalComputation.Workloads.DotProduct

/-! A reusable dot-product execution lemma for arbitrary memory addresses and
arbitrary signed16 operands. Only the load/load/MAC block is proved directly;
all prefixes are obtained by induction and actual-run composition. -/
namespace OptimalComputation.Examples.SerialDot
open Hardware Evaluation Evaluation.Serial Workloads
set_option backward.isDefEq.respectTransparency false

def block (a b : Address) : List BoundedInstruction :=
  [.load r1 a, .load r2 b, .multiplyAdd acc r1.val r2.val acc.val]

def code {n : Nat} (a b : Fin n → Address) : (k : Nat) → k ≤ n → List BoundedInstruction
  | 0, _ => []
  | k + 1, h => code a b k (by omega) ++ block (a ⟨k, by omega⟩) (b ⟨k, by omega⟩)

theorem block_executes (s : State C) (hs : Quiet s) (a b : Address)
    (av bv v next : Signed48)
    (ha : s.readMemory a = some (encodeSlot av)) (hb : s.readMemory b = some (encodeSlot bv))
    (hv : s.readRegister lane acc.val = some v)
    (hc : checkedMac av.val bv.val v.val = .ok next) :
    Executes (block a b) s (((s.writeRegister lane r1 av).writeRegister lane r2 bv).writeRegister lane acc next) := by
  apply Executes.cons (.load r1 a) _ s _ (.register r1 av) hs
  · intro t; exact prepare_load t s hs r1 a av ha
  apply Executes.cons (.load r2 b) _ (s.writeRegister lane r1 av) _ (.register r2 bv) hs
  · intro t; exact prepare_load t (s.writeRegister lane r1 av) hs r2 b bv hb
  apply Executes.cons (.multiplyAdd acc r1.val r2.val acc.val) _ ((s.writeRegister lane r1 av).writeRegister lane r2 bv) _ (.register acc next) hs
  · intro t
    apply prepare_mac t ((s.writeRegister lane r1 av).writeRegister lane r2 bv) hs av bv v next
    · rw [State.readRegister_write_other_register _ _ r2 r1.val _ (by decide)]
      exact State.readRegister_write_same _ _ _ _
    · exact State.readRegister_write_same _ _ _ _
    · rw [State.readRegister_write_other_register _ _ r2 acc.val _ (by decide),
        State.readRegister_write_other_register _ _ r1 acc.val _ (by decide)]
      exact hv
    · exact hc
  exact .nil (((s.writeRegister lane r1 av).writeRegister lane r2 bv).writeRegister lane acc next) hs

def value {n : Nat} (a b : Fin n → Int) (ha : ∀ i, InSigned16 (a i))
    (hb : ∀ i, InSigned16 (b i)) (k : Nat) (hk : k ≤ n) (h16 : k ≤ 16) : Signed48 :=
  ⟨dotPrefix a b k hk, dotPrefix_fits_signed48 a b ha hb k hk h16⟩

/-- Every dot prefix executes with the exact signed48 accumulator value, while
preserving the entire memory. The starting registers other than acc are arbitrary. -/
theorem executes_prefix {n : Nat} (a b : Fin n → Int)
    (ha : ∀ i, InSigned16 (a i)) (hb : ∀ i, InSigned16 (b i))
    (aa ba : Fin n → Address) (s : State C) (hs : Quiet s)
    (hma : ∀ i, s.readMemory (aa i) = some (encodeSlot ⟨a i, signed16_fits_signed48 (ha i)⟩))
    (hmb : ∀ i, s.readMemory (ba i) = some (encodeSlot ⟨b i, signed16_fits_signed48 (hb i)⟩))
    (hz : s.readRegister lane acc.val = some zero48)
    (k : Nat) (hk : k ≤ n) (h16 : k ≤ 16) :
    ∃ final, Executes (code aa ba k hk) s final ∧ final.memory = s.memory ∧
      final.readRegister lane acc.val = some (value a b ha hb k hk h16) := by
  induction k with
  | zero => exact ⟨s, .nil s hs, rfl, hz⟩
  | succ k ih =>
    obtain ⟨middle, hex, hm, hv⟩ := ih (by omega) (by omega)
    let i : Fin n := ⟨k, by omega⟩
    let av : Signed48 := ⟨a i, signed16_fits_signed48 (ha i)⟩
    let bv : Signed48 := ⟨b i, signed16_fits_signed48 (hb i)⟩
    let next := value a b ha hb (k + 1) hk h16
    have hma' : middle.readMemory (aa i) = some (encodeSlot av) := by
      simpa [State.readMemory, hm, av] using hma i
    have hmb' : middle.readMemory (ba i) = some (encodeSlot bv) := by
      simpa [State.readMemory, hm, bv] using hmb i
    have he := block_executes middle (executes_quiet hex) (aa i) (ba i) av bv
      (value a b ha hb k (by omega) (by omega)) next hma' hmb' hv
      (dotPrefix_checkedMac a b ha hb hk h16)
    refine ⟨_, executes_append hex he, hm, ?_⟩
    simp [next]

theorem code_duration {n : Nat} (a b : Fin n → Address) (k : Nat) (hk : k ≤ n) :
    duration (code a b k hk) = 8 * k := by
  induction k with
  | zero => rfl
  | succ k ih =>
    simp [code, duration_append, block, duration, latency, ih]
    omega

/-- Tight timing: load (1) + load (1) + MAC (3) cycles per term. -/
theorem code_tightDuration {n : Nat} (a b : Fin n → Address) (k : Nat) (hk : k ≤ n) :
    tightDuration (code a b k hk) = 5 * k := by
  induction k with
  | zero => rfl
  | succ k ih =>
    simp [code, tightDuration_append, block, tightDuration, latency, ih]
    omega

end OptimalComputation.Examples.SerialDot
