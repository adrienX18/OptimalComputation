import OptimalComputation.Certification.Catalog
import OptimalComputation.CLI

/-! Untrusted transport for the certificate driver. A compiled successful check
only emits a proof obligation; the driver must check it with Lean's kernel. -/
namespace OptimalComputation.Certification
open Lean Hardware Candidates

def failureJson (category message : String) (details : Json := Json.null) : Json := Json.mkObj [
  ("accepted", Lean.toJson false), ("status", Lean.toJson "not-certified"),
  ("category", Lean.toJson category), ("message", Lean.toJson message), ("details", details)]

private def arithmeticJson (error : ArithmeticFailure) (cycle lane : Option Nat := none) : Json :=
  let location := [("cycle", Lean.toJson cycle), ("lane", Lean.toJson lane)]
  match error with
  | .expressionBudget terms => failureJson "expression-budget"
      "Polynomial expansion exceeds the term budget; certification is inconclusive."
      (Json.mkObj (location ++ [("terms", Lean.toJson terms)]))
  | .degreeBudget degree => failureJson "degree-budget"
      "A monomial exceeds the maximum degree of 64; certification is inconclusive."
      (Json.mkObj (location ++ [("degree", Lean.toJson degree)]))
  | .rangeNotProved operand bits interval => failureJson "range-not-proved"
      s!"Cannot prove that the {operand} fits signed {bits} bits: derived range [{interval.lo}, {interval.hi}]."
      (Json.mkObj (location ++ [("operand", Lean.toJson operand), ("bits", Lean.toJson bits),
        ("lowerBound", Lean.toJson interval.lo), ("upperBound", Lean.toJson interval.hi)]))

private def termJson (term : Term) : Json := Json.mkObj [
  ("variables", Lean.toJson term.1), ("coefficient", Lean.toJson term.2)]

private def differenceJson (index : Nat) (expected actual : Option Term) : Json :=
  Json.mkObj [("termIndex", Lean.toJson index),
    ("expected", expected.map termJson |>.getD Json.null),
    ("actual", actual.map termJson |>.getD Json.null)]

private def firstDifference (index : Nat) : Polynomial → Polynomial → Json
  | [], [] => Json.null
  | [], a :: _ => differenceJson index none (some a)
  | e :: _, [] => differenceJson index (some e) none
  | e :: es, a :: rest =>
      if e == a then firstDifference (index+1) es rest
      else differenceJson index (some e) (some a)

def Diagnostic.toJson : Diagnostic → Json
  | .machine error => failureJson "machine-rule" (reprStr error)
      (Evaluation.failureDetails (Evaluation.machineFailure error))
  | .arithmetic cycle lane error => arithmeticJson error (some cycle) (some lane)
  | .inputBounds error => arithmeticJson error
  | .outputCount expected actual => failureJson "output-count" "The output count does not match the reference."
      (Json.mkObj [("expected", Lean.toJson expected), ("actual", Lean.toJson actual)])
  | .exhausted boundary => failureJson "boundary-budget" "The boundary budget ran out; certification is inconclusive."
      (Json.mkObj [("nextBoundary", Lean.toJson boundary)])
  | .missingOutput index address => failureJson "missing-output" s!"Output {index} at address {address} was never written."
      (Json.mkObj [("outputIndex", Lean.toJson index), ("address", Lean.toJson address)])
  | .outputNotProved index expected actual => failureJson "output-not-proved"
      s!"Output {index} has a different polynomial from the reference. No all-input certificate was produced."
      (Json.mkObj [("outputIndex", Lean.toJson index), ("expectedTerms", Lean.toJson expected.length),
        ("actualTerms", Lean.toJson actual.length), ("firstDifference", firstDifference 0 expected actual)])

private def instructionSource : RawInstruction → String
  | .load d a => s!".load {d} {a}"
  | .store s a => s!".store {s} {a}"
  | .add d l r => s!".add {d} {l} {r}"
  | .multiply d l r => s!".multiply {d} {l} {r}"
  | .multiplyAdd d l r a => s!".multiplyAdd {d} {l} {r} {a}"

/-- Called only after the strict CLI parser has checked all string fields.
Every scalar, configuration, layout and instruction is copied literally. -/
def rawSource (raw : RawCandidate) : String :=
  "{\n" ++
  s!"  identifier := \"{raw.identifier}\"\n" ++
  s!"  workloadIdentifier := \"{raw.workloadIdentifier}\"\n" ++
  s!"  modelVersion := \"{raw.modelVersion}\"\n" ++
  s!"  formatVersion := \"{raw.formatVersion}\"\n" ++
  s!"  configuration := ⟨{raw.configuration.lanes}, {raw.configuration.banks}⟩\n" ++
  s!"  layout := ⟨{raw.layout.inputs}, {raw.layout.outputs}, {raw.layout.scratch}⟩\n" ++
  "  schedule := [\n" ++ String.intercalate ",\n" (raw.schedule.map fun s =>
    s!"    ⟨{s.cycle}, {s.lane}, {instructionSource s.instruction}⟩") ++ "]\n}"

private def boundedInstructionSource : RawInstruction → String × String
  | .load d a => (s!".load d{d} a{a}", s!"load{a}")
  | .store r a => (s!".store r{r} a{a}", s!"store{a}")
  | .add d l r => (s!".add d{d} r{l} r{r}", "True.intro")
  | .multiply d l r => (s!".multiply d{d} r{l} r{r}", "True.intro")
  | .multiplyAdd d l r a => (s!".multiplyAdd d{d} r{l} r{r} r{a}", "True.intro")

/-- Emit shared, bounded values directly. Re-expanding `validateCandidate` at
every use of a large schedule costs the kernel far more than checking these
small structural obligations once. `exactBinding` below still checks every
submitted field, so this formatter is not trusted. -/
private def candidateSource (raw : RawCandidate) : String := Id.run do
  let declared := raw.layout.inputs ++ raw.layout.outputs ++ raw.layout.scratch
  let writable := raw.layout.outputs ++ raw.layout.scratch
  let mut source := "def cfg : ValidConfig := ⟨raw.configuration, by decide⟩\n"
  for r in List.range registersPerLane do
    source := source ++ s!"def r{r} : Register := ⟨{r}, by decide⟩\n"
    if r > 0 then
      source := source ++ s!"def d{r} : WritableRegister := ⟨r{r}, by decide⟩\n"
  for l in List.range raw.configuration.lanes do
    source := source ++ s!"def l{l} : Lane cfg := ⟨{l}, by decide⟩\n"
  for a in declared do
    source := source ++ s!"def a{a} : Address := ⟨{a}, by decide⟩\n"
  source := source ++ "def lay : Layout entry.adapter.shape := {\n"
  for (name, addresses) in [("inputs", raw.layout.inputs), ("outputs", raw.layout.outputs),
      ("scratch", raw.layout.scratch)] do
    source := source ++ name ++ " := [" ++ String.intercalate ", " (addresses.map (s!"a{·}")) ++ "]\n"
  source := source ++ "inputCount := by decide\noutputCount := by decide\n" ++
    "separate := (distinctAddresses_iff _).mp (by decide +kernel)\n}\n"
  for (a, index) in declared.zipIdx do
    source := source ++ s!"theorem load{a} : a{a} ∈ lay.declared := by " ++
      s!"exact List.getElem_mem (l := lay.declared) (n := {index}) (by decide)\n"
  for (a, index) in writable.zipIdx do
    source := source ++ s!"theorem store{a} : a{a} ∈ lay.writable := by " ++
      s!"exact List.getElem_mem (l := lay.writable) (n := {index}) (by decide)\n"
  source := source ++ "def candidate : Candidate entry.adapter.shape := {\n" ++
    "identifier := raw.identifier\nidentifier_nonempty := by decide\n" ++
    "configuration := cfg\nlayout := lay\nschedule := [\n" ++
    String.intercalate ",\n" (raw.schedule.map fun s =>
      let (instruction, proof) := boundedInstructionSource s.instruction
      s!"⟨{s.cycle}, l{s.lane}, {instruction}, {proof}⟩") ++ "]\n}\n\n"
  return source

/-- The generated term inhabits the existing VerifiedArtifact API. No status
string, hash or runtime result is used as a proof premise. -/
def certificateSource (entryName : String) (raw : RawCandidate) (boundaries maxTerms cycles : Nat) : String :=
  "import OptimalComputation.Certification.Catalog\n\n" ++
  "namespace GeneratedCertificate\n" ++
  "open OptimalComputation OptimalComputation.Hardware OptimalComputation.Candidates OptimalComputation.Certification\n" ++
  "set_option maxRecDepth 100000\nset_option maxHeartbeats 20000000\n\n" ++
  s!"def entry := {entryName}\n" ++
  "def raw : RawCandidate := " ++ rawSource raw ++ "\n\n" ++
  candidateSource raw ++
  s!"theorem checked : (check entry.problem candidate {boundaries} {maxTerms}).toOption = some {cycles} := by decide +kernel\n\n" ++
  s!"def artifact := entry.artifact candidate {boundaries} {maxTerms} {cycles} checked\n\n" ++
  "theorem exactBinding : artifact.verified.candidate.toRaw = raw := by decide +kernel\n\n" ++
  "#print axioms checked\n#print axioms artifact\n#print axioms exactBinding\n" ++
  "end GeneratedCertificate\n"

/-- Internal compiled precheck. Only the external kernel pass can grant acceptance. -/
def prepareFile (contents : String) (boundaries maxTerms : Nat) : Json :=
  match CLI.parseCandidate contents with
  | .error e => failureJson e.category e.message e.details
  | .ok raw =>
    match Catalog.find? raw.workloadIdentifier with
    | none => failureJson "unknown-workload" s!"No proved reference for {raw.workloadIdentifier}."
    | some (name, entry) =>
      match validateCandidate entry.adapter.shape raw with
      | .error e => failureJson "invalid-candidate" (reprStr e) (Evaluation.candidateErrorJson e)
      | .ok candidate =>
        match check entry.problem candidate boundaries maxTerms with
        | .error e => e.toJson
        | .ok cycles =>
          -- A successful execution needs no more than its completion boundary
          -- plus the final drained-state check. The kernel checks this smaller
          -- sufficient budget directly; the caller's search cap stays intact.
          let proofBoundaries := min boundaries (cycles + 2)
          Json.mkObj [
            ("accepted", Lean.toJson false), ("status", Lean.toJson "requires-kernel-check"),
            ("candidateIdentifier", Lean.toJson raw.identifier), ("workloadIdentifier", Lean.toJson raw.workloadIdentifier),
            ("modelVersion", Lean.toJson raw.modelVersion), ("candidateFormatVersion", Lean.toJson raw.formatVersion),
            ("cycles", Lean.toJson cycles), ("boundaryBudget", Lean.toJson boundaries), ("termBudget", Lean.toJson maxTerms),
            ("certificateBoundaryBudget", Lean.toJson proofBoundaries),
            ("source", Lean.toJson (certificateSource name raw proofBoundaries maxTerms cycles))]
end OptimalComputation.Certification
