import OptimalComputation.Examples.TinyCertificate
import OptimalComputation.Examples.MatVecProof
import OptimalComputation.Examples.MatMulProof

namespace OptimalComputation.Evaluation
open Hardware Candidates Workloads

instance (x : MatVec.specification.Input) : Decidable (MatVec.specification.AllowedInput x) :=
  by unfold MatVec.specification at x ⊢; infer_instance

instance (x : MatMul.specification.Input) : Decidable (MatMul.specification.AllowedInput x) :=
  by unfold MatMul.specification at x ⊢; infer_instance

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
def evaluateTinyRegistered (raw : RawCandidate) (inputs : List Int) (maxBoundaries : Nat) : Outcome :=
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

theorem tiny_registered_sound {raw : RawCandidate} {values : List Int} {fuel : Nat}
    {record : ExecutionRecord} (h : evaluateTinyRegistered raw values fuel = .verified record) :
    raw = Examples.TinyMultiply.candidate.toRaw ∧
      ∃ a b : Int, InSigned16 a ∧ InSigned16 b ∧ values = [a, b] ∧ record.outputs = [a * b] := by
  unfold evaluateTinyRegistered at h
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


/-- Only exact equality to the complete primary artifact yields its certificate. -/
def lookupMatVec (raw : RawCandidate) : Option (VerifiedCandidate MatVec.adapter) :=
  if raw = Examples.MatVecNaive.verified.candidate.toRaw then some Examples.MatVecNaive.verified else none

theorem lookupMatVec_exact {raw : RawCandidate} {certificate : VerifiedCandidate MatVec.adapter}
    (h : lookupMatVec raw = some certificate) :
    raw = Examples.MatVecNaive.verified.candidate.toRaw ∧ certificate = Examples.MatVecNaive.verified := by
  unfold lookupMatVec at h
  split at h
  · rename_i he; cases h; exact ⟨he, rfl⟩
  · contradiction

def evaluateMatVecRegistered (raw : RawCandidate) (inputs : List Int) (maxBoundaries : Nat) : Outcome :=
  match inspect MatVec.shape raw with
  | .error reason => .failure reason
  | .ok checked =>
    match checkStatic checked.val with
    | .error reason => .failure (machineFailure reason)
    | .ok () =>
      match lookupMatVec raw with
      | some certificate => evaluate certificate inputs maxBoundaries
      | none => .failure (.unverifiedCandidate raw.identifier)

theorem matvec_registered_sound {raw : RawCandidate} {values : List Int} {fuel : Nat}
    {record : ExecutionRecord} (h : evaluateMatVecRegistered raw values fuel = .verified record) :
    raw = Examples.MatVecNaive.candidate.toRaw ∧
      ∃ x : MatVec.Input, MatVec.AllowedInput x ∧ values = (MatVec.scalarInput x).toList ∧
        record.outputs = (vectorScalars (MatVec.reference x)).toList := by
  unfold evaluateMatVecRegistered at h
  split at h
  · contradiction
  · split at h
    · contradiction
    · split at h
      · rename_i certificate hc
        obtain ⟨he, rfl⟩ := lookupMatVec_exact hc
        obtain ⟨x, hx, hi, ho, _⟩ := evaluate_sound Examples.MatVecNaive.verified h
        exact ⟨he, x, hx, hi.symm, ho⟩
      · contradiction

/-- Only exact equality to the complete primary artifact yields its certificate. -/
def lookupMatMul (raw : RawCandidate) : Option (VerifiedCandidate MatMul.adapter) :=
  if raw = Examples.MatMulNaive.verified.candidate.toRaw then some Examples.MatMulNaive.verified else none

theorem lookupMatMul_exact {raw : RawCandidate} {certificate : VerifiedCandidate MatMul.adapter}
    (h : lookupMatMul raw = some certificate) :
    raw = Examples.MatMulNaive.verified.candidate.toRaw ∧ certificate = Examples.MatMulNaive.verified := by
  unfold lookupMatMul at h
  split at h
  · rename_i he; cases h; exact ⟨he, rfl⟩
  · contradiction

def evaluateMatMulRegistered (raw : RawCandidate) (inputs : List Int) (maxBoundaries : Nat) : Outcome :=
  match inspect MatMul.shape raw with
  | .error reason => .failure reason
  | .ok checked =>
    match checkStatic checked.val with
    | .error reason => .failure (machineFailure reason)
    | .ok () =>
      match lookupMatMul raw with
      | some certificate => evaluate certificate inputs maxBoundaries
      | none => .failure (.unverifiedCandidate raw.identifier)

theorem matmul_registered_sound {raw : RawCandidate} {values : List Int} {fuel : Nat}
    {record : ExecutionRecord} (h : evaluateMatMulRegistered raw values fuel = .verified record) :
    raw = Examples.MatMulNaive.candidate.toRaw ∧
      ∃ x : MatMul.Input, MatMul.AllowedInput x ∧ values = (MatMul.scalarInput x).toList ∧
        record.outputs = (matrixScalars (MatMul.reference x)).toList := by
  unfold evaluateMatMulRegistered at h
  split at h
  · contradiction
  · split at h
    · contradiction
    · split at h
      · rename_i certificate hc
        obtain ⟨he, rfl⟩ := lookupMatMul_exact hc
        obtain ⟨x, hx, hi, ho, _⟩ := evaluate_sound Examples.MatMulNaive.verified h
        exact ⟨he, x, hx, hi.symm, ho⟩
      · contradiction

/-- Extensible workload dispatch preserves the existing tiny diagnostics and
keeps matrix acceptance on the exact certificate-covered path. -/
def evaluateRegistered (raw : RawCandidate) (inputs : List Int) (maxBoundaries : Nat) : Outcome :=
  if raw.workloadIdentifier = MatVec.specification.identifier then
    evaluateMatVecRegistered raw inputs maxBoundaries
  else if raw.workloadIdentifier = MatMul.specification.identifier then
    evaluateMatMulRegistered raw inputs maxBoundaries
  else evaluateTinyRegistered raw inputs maxBoundaries

theorem registered_sound {raw : RawCandidate} {values : List Int} {fuel : Nat}
    {record : ExecutionRecord} (h : evaluateRegistered raw values fuel = .verified record) :
    (raw = Examples.TinyMultiply.candidate.toRaw ∧
      ∃ a b : Int, InSigned16 a ∧ InSigned16 b ∧ values = [a, b] ∧ record.outputs = [a * b]) ∨
    (raw = Examples.MatVecNaive.candidate.toRaw ∧
      ∃ x : MatVec.Input, MatVec.AllowedInput x ∧ values = (MatVec.scalarInput x).toList ∧
        record.outputs = (vectorScalars (MatVec.reference x)).toList) ∨
    (raw = Examples.MatMulNaive.candidate.toRaw ∧
      ∃ x : MatMul.Input, MatMul.AllowedInput x ∧ values = (MatMul.scalarInput x).toList ∧
        record.outputs = (matrixScalars (MatMul.reference x)).toList) := by
  unfold evaluateRegistered at h
  split at h
  · exact Or.inr (Or.inl (matvec_registered_sound h))
  · split at h
    · exact Or.inr (Or.inr (matmul_registered_sound h))
    · exact Or.inl (tiny_registered_sound h)

/-- Stable identifier selection returns the stored raw artifact. Evaluation
still checks complete artifact equality; identifiers alone confer no trust. -/
def selectCandidate (identifier : String) : Option RawCandidate :=
  if identifier = "tiny-multiply-v1" then some Examples.TinyMultiply.candidate.toRaw
  else if identifier = "matvec-naive-v1" then some Examples.MatVecNaive.candidate.toRaw
  else if identifier = "matmul-naive-v1" then some Examples.MatMulNaive.candidate.toRaw
  else none

end OptimalComputation.Evaluation
