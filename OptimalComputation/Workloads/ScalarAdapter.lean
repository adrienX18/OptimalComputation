import OptimalComputation.Workloads.Shape
import OptimalComputation.Hardware.Arithmetic

namespace OptimalComputation.Workloads
open Hardware

/-- A workload-owned scalar convention, independent of addresses and programs.
Both codecs have a left inverse: an adapter cannot omit any logical input or
output. Output decoding has no access to the input or the reference function. -/
structure ScalarAdapter (spec : Specification) where
  shape : Shape
  identifier : shape.identifier = spec.identifier
  inputScalars : spec.Input → Vector Int shape.inputCount
  decodeInput : Vector Int shape.inputCount → spec.Input
  input_roundtrip : ∀ x, decodeInput (inputScalars x) = x
  input_fits : ∀ x, spec.AllowedInput x → ∀ i : Fin shape.inputCount,
    InSigned48 (inputScalars x)[i.val]
  outputScalars : spec.Output → Vector Int shape.outputCount
  decodeOutput : Vector Int shape.outputCount → spec.Output
  output_roundtrip : ∀ y, decodeOutput (outputScalars y) = y

namespace ScalarAdapter

def encode (a : ScalarAdapter spec) (x : spec.Input) (h : spec.AllowedInput x) :
    Vector Signed48 a.shape.inputCount :=
  Vector.ofFn (fun i => ⟨(a.inputScalars x)[i.val], a.input_fits x h i⟩)

def readOutput (a : ScalarAdapter spec) (scalars : List Int) : Option spec.Output :=
  if h : scalars.length = a.shape.outputCount then
    some (a.decodeOutput ⟨scalars.toArray, by simpa using h⟩)
  else none

theorem input_injective (a : ScalarAdapter spec) {x y : spec.Input}
    (h : a.inputScalars x = a.inputScalars y) : x = y := by
  rw [← a.input_roundtrip x, ← a.input_roundtrip y, h]

theorem output_injective (a : ScalarAdapter spec) {x y : spec.Output}
    (h : a.outputScalars x = a.outputScalars y) : x = y := by
  rw [← a.output_roundtrip x, ← a.output_roundtrip y, h]

theorem readOutput_roundtrip (a : ScalarAdapter spec) (y : spec.Output) :
    a.readOutput (a.outputScalars y).toList = some y := by
  simp [readOutput, Vector.toList, a.output_roundtrip]

end ScalarAdapter
end OptimalComputation.Workloads
