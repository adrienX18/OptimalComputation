import OptimalComputation.Evaluation.Objectives
import OptimalComputation.Examples.MatVecProof
import OptimalComputation.Examples.MatMulProof
import OptimalComputation.Examples.ProductPairProof
import OptimalComputation.Examples.PolynomialBaseline

namespace OptimalComputation.Evaluation

/-- The same serial algorithms are certified on all sixteen configurations.
Other schedules can obtain reusable artifacts through Certification.Catalog. -/
def configurationArtifacts (c : Hardware.ValidConfig) : List VerifiedArtifact := [
  ⟨Workloads.MatMul.specification, Workloads.MatMul.adapter,
    inferInstance, Examples.MatMulNaive.verifiedV2For c⟩,
  ⟨Workloads.Gram.workload.specification, Workloads.Gram.workload.adapter,
    Workloads.Gram.workload.domainDecidable,
    Examples.SerialNetwork.verifiedFor c Examples.ExperimentBaselines.gramNaive "gram-naive-v1" (by decide)
      (Examples.SerialNetwork.code_positive _ (by decide))⟩,
  ⟨Workloads.TwoStage.workload.specification, Workloads.TwoStage.workload.adapter,
    Workloads.TwoStage.workload.domainDecidable,
    Examples.SerialNetwork.verifiedFor c Examples.ExperimentBaselines.twoStage "two-stage-naive-v1" (by decide)
      (Examples.SerialNetwork.code_positive _ (by decide))⟩,
  ⟨Workloads.Polynomial.workload.specification, Workloads.Polynomial.workload.adapter,
    Workloads.Polynomial.workload.domainDecidable,
    Examples.SerialNetwork.verifiedFor c Examples.ExperimentBaselines.polynomial "polynomial-naive-v1" (by decide)
      (Examples.SerialNetwork.code_positive _ (by decide))⟩]

def otherConfigurations : List Hardware.ValidConfig :=
  Hardware.allConfigs.filterMap fun c =>
    if c == Hardware.defaultConfig.val then none else (Hardware.validateConfig c).toOption

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
    inferInstance, Examples.MatMulNaive.verifiedV2⟩,
  ⟨Workloads.Gram.workload.specification, Workloads.Gram.workload.adapter,
    Workloads.Gram.workload.domainDecidable, Examples.ExperimentBaselines.gramNaiveVerified⟩,
  ⟨Workloads.Gram.workload.specification, Workloads.Gram.workload.adapter,
    Workloads.Gram.workload.domainDecidable, Examples.ExperimentBaselines.gramSymmetricVerified⟩,
  ⟨Workloads.TwoStage.workload.specification, Workloads.TwoStage.workload.adapter,
    Workloads.TwoStage.workload.domainDecidable, Examples.ExperimentBaselines.twoStageVerified⟩,
  ⟨Workloads.Polynomial.workload.specification, Workloads.Polynomial.workload.adapter,
    Workloads.Polynomial.workload.domainDecidable, Examples.ExperimentBaselines.polynomialVerified⟩] ++ otherConfigurations.flatMap configurationArtifacts

end OptimalComputation.Evaluation
