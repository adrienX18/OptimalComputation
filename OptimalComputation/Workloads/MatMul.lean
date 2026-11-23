import OptimalComputation.Workloads.Matrix
import OptimalComputation.Workloads.Shape

namespace OptimalComputation.Workloads.MatMul

structure Input where
  left : Matrix16
  right : Matrix16

def AllowedInput (input : Input) : Prop :=
  Matrix16.Allowed input.left ∧ Matrix16.Allowed input.right

instance (input : Input) : Decidable (AllowedInput input) :=
  inferInstanceAs (Decidable (Matrix16.Allowed input.left ∧ Matrix16.Allowed input.right))

/-- Pure mathematical matrix product: row `i` of A against column `j` of B. -/
def reference (input : Input) : Matrix16 :=
  fun i j => dot (input.left i) (fun k => input.right k j)

def specification : Specification := {
  identifier := "matmul-16x16-signed16-v1"
  Input := Input
  AllowedInput := AllowedInput
  Output := Matrix16
  reference := reference
}

/-- Catalog evaluation decides the domain through the specification's own fields. -/
instance (x : specification.Input) : Decidable (specification.AllowedInput x) := by
  unfold specification at x ⊢; infer_instance

def inputScalarCount : Nat := 2 * 16 * 16
def outputScalarCount : Nat := 16 * 16

def shape : Shape := ⟨specification.identifier, inputScalarCount, outputScalarCount⟩

theorem reference_fits_signed48 (input : Input) (h : AllowedInput input) (i j : Index16) :
    Hardware.InSigned48 (reference input i j) :=
  dot_fits_signed48 (input.left i) (fun k => input.right k j)
    (h.1 i) (fun k => h.2 k j) (by decide)

theorem prefix_fits_signed48 (input : Input) (h : AllowedInput input) (i j : Index16)
    (count : Nat) (hcount : count ≤ 16) :
    Hardware.InSigned48 (dotPrefix (input.left i) (fun k => input.right k j) count hcount) :=
  dotPrefix_fits_signed48 (input.left i) (fun k => input.right k j)
    (h.1 i) (fun k => h.2 k j) count hcount hcount

end OptimalComputation.Workloads.MatMul
