import OptimalComputation
import OptimalComputation.Tests.Smoke
import OptimalComputation.Tests.Hardware
import OptimalComputation.Tests.Arithmetic
import OptimalComputation.Tests.Workloads
import OptimalComputation.Tests.Candidates
import OptimalComputation.Tests.Execution
import OptimalComputation.Tests.Verification

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
      return 0
  | ["--version"] =>
      printVersions
      return 0
  | [] | ["--help"] =>
      IO.println "Optimal Computation: Lean hardware model foundation"
      IO.println "Usage: lake exe optimal_computation [--help | --version | --check]"
      return 0
  | _ =>
      let stderr ← IO.getStderr
      stderr.putStrLn "Unknown arguments. Use --help, --version, or --check."
      return 1
