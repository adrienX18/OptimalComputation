import OptimalComputation.Examples.TinyCertificate

namespace OptimalComputation.Evaluation
open Hardware Candidates Workloads

/-- Version-one registry: definitions with kernel-checked certificates only.
Matching the identifier alone never returns a certificate. -/
def lookupTiny (raw : RawCandidate) : Option (VerifiedCandidate Examples.TinyMultiply.adapter) :=
  if raw = Examples.TinyMultiply.verified.candidate.toRaw then some Examples.TinyMultiply.verified else none

theorem lookupTiny_exact {raw : RawCandidate} {certificate : VerifiedCandidate Examples.TinyMultiply.adapter}
    (h : lookupTiny raw = some certificate) :
    raw = Examples.TinyMultiply.verified.candidate.toRaw ∧ certificate = Examples.TinyMultiply.verified := by
  unfold lookupTiny at h
  split at h
  · rename_i he
    cases h
    exact ⟨he, rfl⟩
  · contradiction

/-- Registered evaluation accepts exactly the complete certified artifact.
Malformed known-workload artifacts still receive their concrete structural or
batch-rule diagnosis before being reported as unverified. -/
def evaluateRegistered (raw : RawCandidate) (inputs : List Int) (maxBoundaries : Nat) : Outcome :=
  if raw.workloadIdentifier ≠ Examples.TinyMultiply.specification.identifier then
    .failure (.unverifiedCandidate raw.identifier)
  else match inspect Examples.TinyMultiply.shape raw with
  | .error reason => .failure reason
  | .ok checked =>
    match checkStatic checked.val with
    | .error reason => .failure (machineFailure reason)
    | .ok () =>
      match lookupTiny raw with
      | some certificate => evaluate certificate inputs maxBoundaries
      | none => .failure (.unverifiedCandidate raw.identifier)

theorem registered_sound {raw : RawCandidate} {values : List Int} {fuel : Nat}
    {record : ExecutionRecord} (h : evaluateRegistered raw values fuel = .verified record) :
    raw = Examples.TinyMultiply.candidate.toRaw ∧
      ∃ a b : Int, InSigned16 a ∧ InSigned16 b ∧ values = [a, b] ∧ record.outputs = [a * b] := by
  unfold evaluateRegistered at h
  split at h
  · contradiction
  · split at h
    · contradiction
    · split at h
      · contradiction
      · split at h
        · rename_i certificate hc
          obtain ⟨he, rfl⟩ := lookupTiny_exact hc
          obtain ⟨x, hx, hi, ho, _⟩ := evaluate_sound Examples.TinyMultiply.verified h
          exact ⟨he, x.1, x.2, hx.1, hx.2, hi.symm, ho⟩
        · contradiction

end OptimalComputation.Evaluation
