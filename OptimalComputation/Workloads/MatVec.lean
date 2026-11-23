import OptimalComputation.Workloads.Matrix
import OptimalComputation.Workloads.Shape

namespace OptimalComputation.Workloads.MatVec

structure Input where
  matrix : Matrix16
  vector : Vector16

def AllowedInput (input : Input) : Prop :=
  Matrix16.Allowed input.matrix ∧ Vector16.Allowed input.vector

instance (input : Input) : Decidable (AllowedInput input) :=
  inferInstanceAs (Decidable (Matrix16.Allowed input.matrix ∧ Vector16.Allowed input.vector))

/-- Pure row-wise mathematical matrix-vector product; all entries are runtime inputs. -/
def reference (input : Input) : Vector16 := fun i => dot (input.matrix i) input.vector

def specification : Specification := {
  identifier := "matvec-16x16-signed16-v1"
  Input := Input
  AllowedInput := AllowedInput
  Output := Vector16
  reference := reference
}

/-- Catalog evaluation decides the domain through the specification's own fields. -/
instance (x : specification.Input) : Decidable (specification.AllowedInput x) := by
  unfold specification at x ⊢; infer_instance

def inputScalarCount : Nat := 16 * 16 + 16
def outputScalarCount : Nat := 16

def shape : Shape := ⟨specification.identifier, inputScalarCount, outputScalarCount⟩

theorem reference_fits_signed48 (input : Input) (h : AllowedInput input) (i : Index16) :
    Hardware.InSigned48 (reference input i) :=
  dot_fits_signed48 (input.matrix i) input.vector (h.1 i) h.2 (by decide)

theorem prefix_fits_signed48 (input : Input) (h : AllowedInput input) (i : Index16)
    (count : Nat) (hcount : count ≤ 16) :
    Hardware.InSigned48 (dotPrefix (input.matrix i) input.vector count hcount) :=
  dotPrefix_fits_signed48 (input.matrix i) input.vector (h.1 i) h.2 count hcount hcount

end OptimalComputation.Workloads.MatVec
