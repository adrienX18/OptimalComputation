import OptimalComputation.Evaluation.Checked

/-! Proof-carrying concrete executions. Display tags (including Outcome.verified)
are intentionally not inputs to this API. Every record has an actual-run equality
for its exact candidate, allowed input and budget. -/
namespace OptimalComputation.Evaluation
open Hardware Candidates Workloads

/-- A heterogeneous package for extending a catalog without workload-specific
branches in execution or scoring. The certificate supplies all-input proofs. -/
structure VerifiedArtifact where
  specification : Specification
  adapter : ScalarAdapter specification
  domainDecidable : ∀ x, Decidable (specification.AllowedInput x)
  verified : VerifiedCandidate adapter

/-- This evidence cannot be constructed from a record's labels. The execution
equality binds every output, event counter and resource field to the machine. -/
structure CertifiedExecution (artifact : VerifiedArtifact) (values : List Int) where
  input : artifact.specification.Input
  allowed : artifact.specification.AllowedInput input
  inputBinding : (artifact.adapter.inputScalars input).toList = values
  boundaries : Nat
  withinCertificate : boundaries ≤ artifact.verified.sufficientBoundaries
  record : ExecutionRecord
  executed : executeValues artifact.verified.candidate (artifact.adapter.encode input allowed)
    boundaries false = .success record

theorem CertifiedExecution.correct (execution : CertifiedExecution artifact values) :
    execution.record.outputs =
      (artifact.adapter.outputScalars (artifact.specification.reference execution.input)).toList :=
  artifact.verified.success_correct execution.input execution.allowed execution.boundaries
    execution.withinCertificate execution.record execution.executed

theorem CertifiedExecution.decoded_correct (execution : CertifiedExecution artifact values) :
    artifact.adapter.readOutput execution.record.outputs =
      some (artifact.specification.reference execution.input) := by
  rw [execution.correct]
  exact artifact.adapter.readOutput_roundtrip _

inductive CertifiedOutcome (artifact : VerifiedArtifact) (values : List Int) where
  | success (execution : CertifiedExecution artifact values)
  | failure (reason : Failure)
  | resourceExhausted (details : Exhaustion)

/-- Run the same parser and machine as evaluate, retaining their exact evidence.
The supplied budget can cause exhaustion but cannot bypass the certificate. -/
def executeCertified (artifact : VerifiedArtifact) (values : List Int) (maxBoundaries : Nat) :
    CertifiedOutcome artifact values :=
  letI := artifact.domainDecidable
  match hi : parseInput artifact.adapter values with
  | .error e => .failure e
  | .ok input =>
    match he : executeValues artifact.verified.candidate (artifact.adapter.encode input.val input.property)
        (min maxBoundaries artifact.verified.sufficientBoundaries) false with
    | .success record => .success {
        input := input.val
        allowed := input.property
        inputBinding := parseInput_values artifact.adapter hi
        boundaries := min maxBoundaries artifact.verified.sufficientBoundaries
        withinCertificate := Nat.min_le_right _ _
        record := record
        executed := he
      }
    | .failure reason => .failure (executionFailure reason)
    | .resourceExhausted details => .resourceExhausted details

/-- Lookup carries exact raw-artifact equality, not just a matching identifier. -/
def lookupArtifact (catalog : List VerifiedArtifact) (raw : RawCandidate) :
    Option { artifact : VerifiedArtifact // artifact.verified.candidate.toRaw = raw } :=
  match catalog with
  | [] => none
  | artifact :: rest =>
    if h : artifact.verified.candidate.toRaw = raw then some ⟨artifact, h⟩
    else lookupArtifact rest raw

theorem lookupArtifact_member {catalog : List VerifiedArtifact} {raw : RawCandidate}
    {found : { artifact : VerifiedArtifact // artifact.verified.candidate.toRaw = raw }}
    (h : lookupArtifact catalog raw = some found) : found.val ∈ catalog := by
  induction catalog with
  | nil => simp [lookupArtifact] at h
  | cons artifact rest ih =>
    unfold lookupArtifact at h
    split at h
    · cases h; exact List.mem_cons_self
    · exact List.mem_cons_of_mem _ (ih h)

/-- Stable identifier selection is only convenience; lookup still checks all
serialized fields before executing any artifact. -/
def selectArtifact (catalog : List VerifiedArtifact) (identifier : String) : Option RawCandidate :=
  (catalog.find? fun a => a.verified.candidate.identifier == identifier).map
    (fun a => a.verified.candidate.toRaw)

end OptimalComputation.Evaluation
