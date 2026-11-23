import OptimalComputation.Workloads.DotProduct
import OptimalComputation.Workloads.Specification

namespace OptimalComputation.Workloads

abbrev Index16 := Fin 16
abbrev Vector16 := Index16 → Int
abbrev Matrix16 := Index16 → Index16 → Int

def Vector16.Allowed (x : Vector16) : Prop := ∀ i, Hardware.InSigned16 (x i)
def Matrix16.Allowed (a : Matrix16) : Prop := ∀ i j, Hardware.InSigned16 (a i j)

instance (x : Vector16) : Decidable (Vector16.Allowed x) :=
  @Nat.decidableForallFin 16 (fun i => Hardware.InSigned16 (x i)) (fun _ => inferInstance)
instance (a : Matrix16) : Decidable (Matrix16.Allowed a) :=
  @Nat.decidableForallFin 16 (fun i => ∀ j, Hardware.InSigned16 (a i j))
    (fun i => @Nat.decidableForallFin 16 (fun j => Hardware.InSigned16 (a i j))
      (fun _ => inferInstance))

end OptimalComputation.Workloads
