import OptimalComputation.Examples.TinyCertificate

/-! Two hand-written schedules of the same runtime computation. These fixtures
validate objective trade-offs; they are not a search procedure or optimality claim. -/
namespace OptimalComputation.Examples.ProductPair
open Hardware Workloads Candidates Evaluation

set_option backward.isDefEq.respectTransparency false
set_option maxRecDepth 20000
set_option maxHeartbeats 200000
set_option linter.unusedSimpArgs false

def specification : Specification := {
  identifier := "product-pair-signed16-v1"
  Input := (Int × Int) × (Int × Int)
  AllowedInput := fun ((a, b), (c, d)) => InSigned16 a ∧ InSigned16 b ∧ InSigned16 c ∧ InSigned16 d
  Output := Int × Int
  reference := fun ((a, b), (c, d)) => (a * b, c * d)
}

def shape : Shape := ⟨specification.identifier, 4, 2⟩
def configuration (parallel : Bool) : ValidConfig :=
  if parallel then defaultConfig else ⟨⟨1, 1⟩, by decide⟩
def address (n : Nat) (h : n < 4096 := by decide) : Address := ⟨n, h⟩
def layout : Layout shape := {
  inputs := [address 0, address 1, address 2, address 3]
  outputs := [address 4, address 5]
  scratch := []
  inputCount := by decide
  outputCount := by decide
  separate := by decide
}
def lane0 (p : Bool) : Lane (configuration p) := ⟨0, by cases p <;> decide⟩
def laneSecond (p : Bool) : Lane (configuration p) := ⟨if p then 1 else 0, by cases p <;> decide⟩
def r1 : WritableRegister := TinyMultiply.r1
def r2 : WritableRegister := TinyMultiply.r2
def r3 : WritableRegister := TinyMultiply.r3

def candidate (p : Bool) : Candidate shape := {
  identifier := if p then "product-pair-parallel-v1" else "product-pair-serial-v1"
  identifier_nonempty := by cases p <;> decide
  configuration := configuration p
  layout := layout
  schedule := [
    ⟨0, lane0 p, .load r1 (address 0), by decide⟩,
    ⟨1, lane0 p, .load r2 (address 1), by decide⟩,
    ⟨2, lane0 p, .multiply r3 r1.val r2.val, trivial⟩,
    ⟨5, lane0 p, .store r3.val (address 4), by decide⟩,
    ⟨if p then 0 else 6, laneSecond p, .load r1 (address 2), by decide⟩,
    ⟨if p then 1 else 7, laneSecond p, .load r2 (address 3), by decide⟩,
    ⟨if p then 2 else 8, laneSecond p, .multiply r3 r1.val r2.val, trivial⟩,
    ⟨if p then 5 else 11, laneSecond p, .store r3.val (address 5), by decide⟩
  ]
}

def inputs (a b c d : Int) (ha : InSigned16 a) (hb : InSigned16 b)
    (hc : InSigned16 c) (hd : InSigned16 d) : Vector Signed48 4 :=
  #v[⟨a, signed16_fits_signed48 ha⟩, ⟨b, signed16_fits_signed48 hb⟩,
     ⟨c, signed16_fits_signed48 hc⟩, ⟨d, signed16_fits_signed48 hd⟩]

instance (x : specification.Input) : Decidable (specification.AllowedInput x) :=
  inferInstanceAs (Decidable (InSigned16 x.1.1 ∧ InSigned16 x.1.2 ∧ InSigned16 x.2.1 ∧ InSigned16 x.2.2))

def adapter : ScalarAdapter specification where
  shape := shape
  identifier := rfl
  inputScalars := fun x => #v[x.1.1, x.1.2, x.2.1, x.2.2]
  decodeInput := fun v => ((v[0], v[1]), (v[2], v[3]))
  input_roundtrip := by intro x; rfl
  input_fits := by
    intro x hx i
    have hi : i.val = 0 ∨ i.val = 1 ∨ i.val = 2 ∨ i.val = 3 := by
      have := i.isLt; change i.val < 4 at this; omega
    rcases hi with hi | hi | hi | hi
    · simpa +instances [shape, specification, hi] using signed16_fits_signed48 hx.1
    · simpa +instances [shape, specification, hi] using signed16_fits_signed48 hx.2.1
    · simpa +instances [shape, specification, hi] using signed16_fits_signed48 hx.2.2.1
    · simpa +instances [shape, specification, hi] using signed16_fits_signed48 hx.2.2.2
  outputScalars := fun y => #v[y.1, y.2]
  decodeOutput := fun v => (v[0], v[1])
  output_roundtrip := by intro y; rfl

theorem adapter_encode (x : specification.Input) (hx : specification.AllowedInput x) :
    adapter.encode x hx = inputs x.1.1 x.1.2 x.2.1 x.2.2 hx.1 hx.2.1 hx.2.2.1 hx.2.2.2 := by
  apply Vector.ext
  intro i hi
  have hii : i = 0 ∨ i = 1 ∨ i = 2 ∨ i = 3 := by change i < 4 at hi; omega
  rcases hii with rfl | rfl | rfl | rfl <;>
    simp +instances [ScalarAdapter.encode, adapter, inputs, shape, specification]

end OptimalComputation.Examples.ProductPair
