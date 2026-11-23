import OptimalComputation
import OptimalComputation.Tests.Smoke
import OptimalComputation.Tests.Hardware
import OptimalComputation.Tests.Arithmetic
import OptimalComputation.Tests.Workloads
import OptimalComputation.Tests.Candidates
import OptimalComputation.Tests.Execution
import OptimalComputation.Tests.Verification
import OptimalComputation.Tests.MatVecBaseline
import OptimalComputation.Tests.Objectives
import OptimalComputation.Tests.MatMulBaseline
import OptimalComputation.Tests.NaiveV2
import OptimalComputation.CLI
import OptimalComputation.Tests.Certification
import OptimalComputation.Tests.CLI

private def printVersions : IO Unit := do
  IO.println s!"model: {OptimalComputation.Versions.model}"
  IO.println s!"candidate format: {OptimalComputation.Versions.candidate}"
  IO.println s!"latency objective: {OptimalComputation.Versions.latency}"
  IO.println s!"energy objective: {OptimalComputation.Versions.energy}"
  IO.println s!"energy coefficients: {OptimalComputation.Versions.energyCoefficients}"

def main (args : List String) : IO UInt32 := do
  match args with
  | ["--check"] =>
      OptimalComputation.Tests.smoke
      OptimalComputation.Tests.hardware
      OptimalComputation.Tests.arithmetic
      OptimalComputation.Tests.storage
      OptimalComputation.Tests.workloads
      OptimalComputation.Tests.candidates
      OptimalComputation.Tests.execution
      OptimalComputation.Tests.verification
      OptimalComputation.Tests.matvecBaseline
      OptimalComputation.Tests.objectives
      OptimalComputation.Tests.matmulBaseline
      OptimalComputation.Tests.naiveV2
      OptimalComputation.Tests.certification
      OptimalComputation.Tests.cli
      return 0
  | ["--version"] =>
      printVersions
      return 0
  | _ => OptimalComputation.CLI.run args
