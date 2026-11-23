import OptimalComputation.Workloads.Specification

/-! Logical scalar counts for binding a candidate layout to an expected workload.
These are independent of physical addresses. The caller supplies the expected
shape; a candidate cannot choose its own interpretation of a known workload ID.
Later semantic verification must also bind the specification and scalar encoding. -/

namespace OptimalComputation.Workloads

structure Shape where
  identifier : String
  inputCount : Nat
  outputCount : Nat
  deriving Repr, DecidableEq, BEq

end OptimalComputation.Workloads
