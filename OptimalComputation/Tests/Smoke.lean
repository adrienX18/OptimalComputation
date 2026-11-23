import OptimalComputation

namespace OptimalComputation.Tests

private def checkIdentifier (label actual expected : String) : IO Unit := do
  unless actual == expected do
    throw <| IO.userError s!"{label}: expected {expected}, got {actual}"

/-- A deliberately small executable regression for the Milestone 1 package. -/
def smoke : IO Unit := do
  checkIdentifier "model" Versions.model "arty-model-v1"
  checkIdentifier "candidate format" Versions.candidate "candidate-v1"
  checkIdentifier "latency objective" Versions.latency "latency-v1"
  checkIdentifier "energy objective" Versions.energy "energy-proxy-v1"
  checkIdentifier "energy coefficients" Versions.energyCoefficients "energy-coefficients-v1"
  IO.println "PASS: 5 contract identifier checks"

end OptimalComputation.Tests
