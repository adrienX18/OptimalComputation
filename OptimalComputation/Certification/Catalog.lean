import OptimalComputation.Evaluation.CertifiedExecution
import OptimalComputation.Certification.WorkloadInstances
import OptimalComputation.Certification.SmallWorkloads

namespace OptimalComputation.Certification
open Hardware Candidates Workloads

/-- Adding a workload requires a domain, scalar adapter and one reference proof.
Candidate identifiers, algorithms and schedules are never registered here. -/
structure Entry where
  specification : Specification
  adapter : ScalarAdapter specification
  domainDecidable : ∀ x, Decidable (specification.AllowedInput x)
  problem : Problem adapter

def Entry.artifact (entry : Entry) (candidate : Candidate entry.adapter.shape)
    (boundaries maxTerms cycles : Nat)
    (h : (check entry.problem candidate boundaries maxTerms).toOption = some cycles) : Evaluation.VerifiedArtifact :=
  ⟨entry.specification, entry.adapter, entry.domainDecidable,
    certificate entry.problem candidate boundaries maxTerms cycles
      (check_of_toOption entry.problem candidate boundaries maxTerms cycles h)⟩

namespace Catalog

def tiny : Entry := ⟨Examples.TinyMultiply.specification, Examples.TinyMultiply.adapter,
  inferInstance, TinyProblem.problem⟩
def pair : Entry := ⟨Examples.ProductPair.specification, Examples.ProductPair.adapter,
  inferInstance, PairProblem.problem⟩
def matvec : Entry := ⟨MatVec.specification, MatVec.adapter, inferInstance, MatVecProblem.problem⟩
def matmul : Entry := ⟨MatMul.specification, MatMul.adapter, inferInstance, MatMulProblem.problem⟩
def polynomial : Entry := ⟨Workloads.Polynomial.workload.specification, Workloads.Polynomial.workload.adapter,
  Workloads.Polynomial.workload.domainDecidable, PolynomialProblem.problem⟩
def gram : Entry := ⟨Gram.workload.specification, Gram.workload.adapter,
  Gram.workload.domainDecidable, GramProblem.problem⟩
def twoStage : Entry := ⟨TwoStage.workload.specification, TwoStage.workload.adapter,
  TwoStage.workload.domainDecidable, TwoStageProblem.problem⟩

/-- Names here are trusted Lean identifiers used by the source emitter. -/
def entries : List (String × Entry) := [
  ("Catalog.tiny", tiny), ("Catalog.pair", pair), ("Catalog.matvec", matvec),
  ("Catalog.matmul", matmul), ("Catalog.polynomial", polynomial),
  ("Catalog.gram", gram), ("Catalog.twoStage", twoStage)]

def find? (workload : String) : Option (String × Entry) :=
  entries.find? (fun (_, e) => e.specification.identifier == workload)
end Catalog
end OptimalComputation.Certification
