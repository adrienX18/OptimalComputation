import OptimalComputation.Workloads.MatVec
import OptimalComputation.Workloads.MatMul
import OptimalComputation.Hardware.Config

namespace OptimalComputation.Tests

open Hardware Workloads

private def checkWorkload (label : String) (condition : Bool) : IO Unit := do
  unless condition do throw <| IO.userError s!"Workload check failed: {label}"

private def checkMatVec (label : String) (input : MatVec.Input) (expected : Vector16) : IO Unit := do
  checkWorkload s!"{label}: allowed input" (decide (MatVec.AllowedInput input))
  for i in List.finRange 16 do
    checkWorkload s!"{label}: row {i.val}" (MatVec.reference input i == expected i)

private def checkMatMul (label : String) (input : MatMul.Input) (expected : Matrix16) : IO Unit := do
  checkWorkload s!"{label}: allowed input" (decide (MatMul.AllowedInput input))
  for i in List.finRange 16 do
    for j in List.finRange 16 do
      checkWorkload s!"{label}: entry ({i.val}, {j.val})" (MatMul.reference input i j == expected i j)

private def zeroVector : Vector16 := fun _ => 0
private def zeroMatrix : Matrix16 := fun _ _ => 0
private def identity : Matrix16 := fun i j => if i == j then 1 else 0

private def smallA : Matrix16 := fun i j =>
  match i.val, j.val with
  | 0, 0 => 1 | 0, 1 => -2 | 0, 2 => 3
  | 1, 0 => -4 | 1, 1 => 5 | 1, 2 => -6
  | 2, 0 => 7 | 2, 1 => -8 | 2, 2 => 9
  | _, _ => 0

private def smallB : Matrix16 := fun i j =>
  match i.val, j.val with
  | 0, 0 => -1 | 0, 1 => 2 | 0, 2 => -3
  | 1, 0 => 4 | 1, 1 => -5 | 1, 2 => 6
  | 2, 0 => -7 | 2, 1 => 8 | 2, 2 => -9
  | _, _ => 0

private def smallProduct : Matrix16 := fun i j =>
  match i.val, j.val with
  | 0, 0 => -30 | 0, 1 => 36 | 0, 2 => -42
  | 1, 0 => 66 | 1, 1 => -81 | 1, 2 => 96
  | 2, 0 => -102 | 2, 1 => 126 | 2, 2 => -150
  | _, _ => 0

def workloads : IO Unit := do
  checkWorkload "matvec identifier" (MatVec.specification.identifier == "matvec-16x16-signed16-v1")
  checkWorkload "matmul identifier" (MatMul.specification.identifier == "matmul-16x16-signed16-v1")
  checkMatVec "matvec zero" ⟨zeroMatrix, zeroVector⟩ zeroVector
  checkMatMul "matmul zero" ⟨zeroMatrix, zeroMatrix⟩ zeroMatrix
  let vector : Vector16 := fun i => 3 * (i.val : Int) - 20
  let matrix : Matrix16 := fun i j => 16 * (i.val : Int) + (j.val : Int) - 128
  checkMatVec "matvec identity" ⟨identity, vector⟩ vector
  checkMatMul "matmul left identity" ⟨identity, matrix⟩ matrix
  checkMatMul "matmul right identity" ⟨matrix, identity⟩ matrix
  checkMatVec "matvec hand-worked signs" ⟨smallA, fun i => match i.val with
      | 0 => -2 | 1 => 3 | 2 => -4 | _ => 0⟩
    (fun i => match i.val with | 0 => -20 | 1 => 47 | 2 => -74 | _ => 0)
  checkMatMul "matmul hand-worked signs" ⟨smallA, smallB⟩ smallProduct
  -- Dense generated data; closed-form expected answers use Σk = 120, Σk² = 1240.
  let a : Matrix16 := fun i k => (i.val : Int) - (k.val : Int)
  checkMatVec "matvec dense formula" ⟨a, fun k => (k.val : Int) - 8⟩
    (fun i => -8 * (i.val : Int) - 280)
  checkMatMul "matmul dense formula" ⟨a, fun k j => 2 * (k.val : Int) + (j.val : Int) - 15⟩
    (fun i j => 16 * (i.val : Int) * (j.val : Int) - 120 * (j.val : Int) - 680)
  -- Full-length extremal dot products, not just small embedded examples.
  for (left, right, expected) in [(-32768, -32768, 17179869184),
      (32767, 32767, 17178820624), (-32768, 32767, -17179344896)] do
    checkMatVec "matvec extrema" ⟨fun _ _ => left, fun _ => right⟩ (fun _ => expected)
    checkMatMul "matmul extrema" ⟨fun _ _ => left, fun _ _ => right⟩ (fun _ _ => expected)
  for count in List.finRange 17 do
    checkWorkload s!"prefix at length {count.val}"
      (dotPrefix (fun (_ : Index16) => -32768) (fun _ => -32768) count.val (by omega) ==
        (count.val : Int) * 1073741824)
  let invalidMatrix : Matrix16 := fun i j => if i.val == 15 && j.val == 15 then 32768 else 0
  let invalidVector : Vector16 := fun i => if i.val == 15 then -32769 else 0
  checkWorkload "reject final matrix input" (!decide (MatVec.AllowedInput ⟨invalidMatrix, zeroVector⟩))
  checkWorkload "reject final vector input" (!decide (MatVec.AllowedInput ⟨zeroMatrix, invalidVector⟩))
  checkWorkload "reject final left matrix input" (!decide (MatMul.AllowedInput ⟨invalidMatrix, zeroMatrix⟩))
  checkWorkload "reject final right matrix input" (!decide (MatMul.AllowedInput ⟨zeroMatrix, invalidMatrix⟩))
  let matvecSlots := MatVec.inputScalarCount + MatVec.outputScalarCount
  let matmulSlots := MatMul.inputScalarCount + MatMul.outputScalarCount
  checkWorkload "matvec 288 whole slots occupy 2304 bytes and fit"
    (matvecSlots == 288 && matvecSlots * (memorySlotBits / 8) == 2304 && matvecSlots ≤ localMemorySlots)
  checkWorkload "matmul 768 whole slots occupy 6144 bytes and fit"
    (matmulSlots == 768 && matmulSlots * (memorySlotBits / 8) == 6144 && matmulSlots ≤ localMemorySlots)
  IO.println "PASS: workload checks (7 matvec and 8 matmul fixtures, all 17 prefixes, input rejection, full-slot footprints)"

end OptimalComputation.Tests
