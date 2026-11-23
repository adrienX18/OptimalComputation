import OptimalComputation.Evaluation.Objectives
import OptimalComputation.Examples.MatVecProof
import OptimalComputation.Examples.MatMulProof
import OptimalComputation.Examples.ProductPairProof

namespace OptimalComputation.Evaluation

/-- The only registry of certified candidates: data, not dispatch logic. Adding
a computation requires its adapter/certificate and an entry, with no
scoring/machine changes. `evaluateObjective` is the single acceptance path. -/
def objectiveCatalog : List VerifiedArtifact := [
  ⟨Examples.TinyMultiply.specification, Examples.TinyMultiply.adapter,
    inferInstance, Examples.TinyMultiply.verified⟩,
  ⟨Workloads.MatVec.specification, Workloads.MatVec.adapter,
    inferInstance, Examples.MatVecNaive.verified⟩,
  ⟨Workloads.MatMul.specification, Workloads.MatMul.adapter,
    inferInstance, Examples.MatMulNaive.verified⟩,
  ⟨Examples.ProductPair.specification, Examples.ProductPair.adapter,
    inferInstance, Examples.ProductPair.verified false⟩,
  ⟨Examples.ProductPair.specification, Examples.ProductPair.adapter,
    inferInstance, Examples.ProductPair.verified true⟩,
  ⟨Workloads.MatVec.specification, Workloads.MatVec.adapter,
    inferInstance, Examples.MatVecNaive.verifiedV2⟩,
  ⟨Workloads.MatMul.specification, Workloads.MatMul.adapter,
    inferInstance, Examples.MatMulNaive.verifiedV2⟩]

end OptimalComputation.Evaluation
