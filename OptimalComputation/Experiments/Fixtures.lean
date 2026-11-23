import OptimalComputation.Workloads.ExperimentWorkloads

namespace OptimalComputation.Experiments
open Workloads

/-- Training fixtures for the polynomial deliberately keep every Horner
multiplicand legal. Held-out values are supplied only by the validation runner. -/
def fixtures (workload : String) : List (String × List Int) := Id.run do
  if workload == Polynomial.workload.identifier then
    return [
      ("zeros", List.replicate 24 0),
      ("negative-endpoints", List.replicate 8 (-8) ++ List.replicate 16 (-4)),
      ("positive-endpoints", List.replicate 8 7 ++ List.replicate 16 3),
      ("mixed-signs", [7,-8,7,-8,7,-8,7,-8] ++ List.replicate 16 3),
      ("generated-23", (List.range 8).map (fun k => ((11*k+23)%16 : Nat) - (8 : Int)) ++
        (List.range 16).map (fun i => ((3*i+23)%7 : Nat) - (3 : Int)))]
  if workload == Gram.workload.identifier then
    return [
      ("zeros", List.replicate 256 0),
      ("identity", (List.range 256).map fun q => if q / 16 == q % 16 then 1 else 0),
      ("negative-endpoints", List.replicate 256 (-32768)),
      ("positive-endpoints", List.replicate 256 32767),
      ("mixed-signs", (List.range 256).map fun q => if q % 2 == 0 then -32768 else 32767),
      ("generated-23", (List.range 256).map fun q => ((17*q+23)%101 : Nat) - (50 : Int))]
  if workload == TwoStage.workload.identifier then
    return [
      ("zeros", List.replicate 528 0),
      ("negative-endpoints", List.replicate 272 (-45) ++ List.replicate 256 (-32768)),
      ("positive-endpoints", List.replicate 272 45 ++ List.replicate 256 32767),
      ("mixed-signs", (List.range 272).map (fun q => if q % 2 == 0 then -45 else 45) ++
        (List.range 256).map (fun q => if q % 2 == 0 then -32768 else 32767)),
      ("generated-23", (List.range 272).map (fun q => ((17*q+23)%91 : Nat) - (45 : Int)) ++
        (List.range 256).map (fun q => ((31*q+23)%65536 : Nat) - (32768 : Int)))]
  return []

end OptimalComputation.Experiments
