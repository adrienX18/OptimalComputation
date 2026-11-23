import OptimalComputation.Evaluation.CertifiedExecution

/-! Pure, interchangeable objectives over the unchanged objective-free record.
Arithmetic scoring of an arbitrary record conveys no verification claim. Only
AcceptedScore contains the evidence required for an optimization result. -/
namespace OptimalComputation.Evaluation
open Hardware Candidates Workloads

inductive Direction where
  | minimize
  deriving Repr, DecidableEq, BEq

structure ScoreTerm where
  label : String
  quantity : Nat
  coefficient : Nat
  deriving Repr, DecidableEq, BEq

def ScoreTerm.cost (term : ScoreTerm) : Nat := term.quantity * term.coefficient

structure CoefficientProfile where
  identifier : String
  coefficients : List (String × Nat)
  deriving Repr, DecidableEq, BEq

/-- New objectives supply metadata and terms; no machine or workload changes
are needed. The score always sums the displayed terms. -/
structure Objective where
  identifier : String
  unit : String
  direction : Direction := .minimize
  coefficients : Option CoefficientProfile := none
  breakdown : ExecutionRecord → List ScoreTerm

structure Score where
  objectiveIdentifier : String
  unit : String
  direction : Direction
  coefficients : Option CoefficientProfile
  breakdown : List ScoreTerm
  deriving Repr, DecidableEq, BEq

def Score.value (score : Score) : Nat := (score.breakdown.map ScoreTerm.cost).sum

/-- Pure arithmetic helper: this result alone is not an accepted score. -/
def scoreRecord (objective : Objective) (record : ExecutionRecord) : Score :=
  ⟨objective.identifier, objective.unit, objective.direction, objective.coefficients,
    objective.breakdown record⟩

def latency : Objective := {
  identifier := Versions.latency
  unit := "cycles"
  breakdown := fun r => [⟨"elapsed cycles", r.cycles, 1⟩]
}

/-- Frozen hypothetical coefficients. Changing these requires a distinct
profile and objective version; these numbers have no physical energy unit. -/
def energyCoefficients : CoefficientProfile := {
  identifier := Versions.energyCoefficients
  coefficients := [("base_per_cycle", 1), ("lane_per_cycle", 1), ("bram_per_cycle", 1),
    ("load", 4), ("store", 4), ("addition", 1), ("multiplication", 8),
    ("multiply_add", 9), ("register_read", 1), ("register_write", 1)]
}

theorem energyCoefficients_positive :
    ∀ entry ∈ energyCoefficients.coefficients, 0 < entry.2 := by decide

def energy : Objective := {
  identifier := Versions.energy
  unit := "abstract energy units"
  coefficients := some energyCoefficients
  breakdown := fun r => [
    ⟨"base duration", r.cycles, 1⟩,
    ⟨"provisioned lane duration", r.cycles * r.resources.configuration.lanes, 1⟩,
    ⟨"allocated BRAM36 duration", r.cycles * r.resources.bram36Blocks, 1⟩,
    ⟨"loads", r.counters.loads, 4⟩,
    ⟨"stores", r.counters.stores, 4⟩,
    ⟨"additions", r.counters.additions, 1⟩,
    ⟨"multiplications", r.counters.multiplications, 8⟩,
    ⟨"multiply-adds", r.counters.multiplyAdds, 9⟩,
    ⟨"register reads (including r0)", r.counters.registerReads, 1⟩,
    ⟨"register writes", r.counters.registerWrites, 1⟩]
}

theorem latency_formula (r : ExecutionRecord) : (scoreRecord latency r).value = r.cycles := by
  simp [scoreRecord, latency, Score.value, ScoreTerm.cost]

theorem energy_formula (r : ExecutionRecord) :
    (scoreRecord energy r).value =
      r.cycles * (1 + r.resources.configuration.lanes + r.resources.bram36Blocks) +
      4 * r.counters.loads + 4 * r.counters.stores + r.counters.additions +
      8 * r.counters.multiplications + 9 * r.counters.multiplyAdds +
      r.counters.registerReads + r.counters.registerWrites := by
  simp [scoreRecord, energy, Score.value, ScoreTerm.cost, Nat.mul_add,
    Nat.mul_comm, Nat.add_assoc, Nat.add_comm, Nat.add_left_comm]

/-- Accepted results bind the raw program and exact runtime scalars to proof of
an actual successful execution. Strings, status tags and caller-supplied
ExecutionRecords cannot substitute for this evidence. Score fields are computed. -/
structure AcceptedScore (raw : RawCandidate) (values : List Int) where
  artifact : VerifiedArtifact
  exactArtifact : artifact.verified.candidate.toRaw = raw
  execution : CertifiedExecution artifact values
  inputIdentifier : String
  objective : Objective

def AcceptedScore.result (accepted : AcceptedScore raw values) : Score :=
  scoreRecord accepted.objective accepted.execution.record

def AcceptedScore.rescore (accepted : AcceptedScore raw values) (objective : Objective) :
    AcceptedScore raw values := {accepted with objective := objective}

theorem AcceptedScore.rescore_preserves_record (accepted : AcceptedScore raw values) (objective : Objective) :
    (accepted.rescore objective).execution.record = accepted.execution.record := rfl

theorem AcceptedScore.correct (accepted : AcceptedScore raw values) :
    accepted.execution.record.outputs = (accepted.artifact.adapter.outputScalars
      (accepted.artifact.specification.reference accepted.execution.input)).toList :=
  accepted.execution.correct

inductive ScoringOutcome (raw : RawCandidate) (values : List Int) where
  | accepted (score : AcceptedScore raw values)
  | failure (reason : Failure)
  | resourceExhausted (details : Exhaustion)

/-- This entry point executes the exact registered proof-bearing artifact.
It never promotes a status tag or an arbitrary record to acceptance. -/
def evaluateObjective (catalog : List VerifiedArtifact) (raw : RawCandidate) (values : List Int)
    (maxBoundaries : Nat) (inputIdentifier : String) (objective : Objective) : ScoringOutcome raw values :=
  match lookupArtifact catalog raw with
  | none => .failure (.unverifiedCandidate raw.identifier)
  | some found =>
    match executeCertified found.val values maxBoundaries with
    | .success execution => .accepted ⟨found.val, found.property, execution, inputIdentifier, objective⟩
    | .failure reason => .failure reason
    | .resourceExhausted details => .resourceExhausted details

/-- Every accepted result from catalog evaluation came from an exact registered
artifact. The carried execution separately proves the exact input/run binding. -/
theorem evaluateObjective_registered {catalog : List VerifiedArtifact} {raw : RawCandidate}
    {values : List Int} {fuel : Nat} {inputIdentifier : String} {objective : Objective}
    {accepted : AcceptedScore raw values}
    (h : evaluateObjective catalog raw values fuel inputIdentifier objective = .accepted accepted) :
    accepted.artifact ∈ catalog ∧ accepted.artifact.verified.candidate.toRaw = raw := by
  unfold evaluateObjective at h
  split at h
  · contradiction
  · rename_i found hf
    split at h
    · cases h
      exact ⟨lookupArtifact_member hf, found.property⟩
    · contradiction
    · contradiction

end OptimalComputation.Evaluation
