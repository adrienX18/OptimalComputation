/-! A workload supplies pure mathematics. It knows no configuration, physical
address, instruction, schedule, evaluator, or objective. -/

namespace OptimalComputation.Workloads

structure Specification where
  identifier : String
  Input : Type
  AllowedInput : Input → Prop
  Output : Type
  reference : Input → Output

end OptimalComputation.Workloads
