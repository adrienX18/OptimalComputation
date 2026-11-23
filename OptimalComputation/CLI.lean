import OptimalComputation
import Lean.Data.Json.Parser

/-! Small public interface. Certificates and scoring stay in Evaluation;
fixtures and serialization here confer no verification authority. -/
namespace OptimalComputation.CLI
open Lean Evaluation Hardware Candidates Workloads

def help : String := "Optimal Computation: certified execution on arty-model-v1\n\
Usage: optimal_computation [--help | --version | --check]\n\
       optimal_computation list-workloads [--json]\n\
       optimal_computation list-candidates [--json]\n\
       optimal_computation list-objectives [--json]\n\
       optimal_computation evaluate ID [--objective ID] [--fixture NAME | --input FILE]\n\
         [--budget BOUNDARIES] [--trace FILE] [--json]\n\
       optimal_computation simulate CANDIDATE_FILE [--fixture NAME | --input FILE]\n\
         [--budget BOUNDARIES] [--trace FILE] [--json]\n\
       optimal_computation export-candidate ID [--json]\n\
Defaults: latency-v1; generated-23 for matrices, mixed-signs for tiny/pair; certified budget.\n\
Input files contain a JSON array of integers. --trace exports an observational simulation.\n\
simulate runs a JSON candidate file unverified and unscored; export-candidate prints one.\n\
See docs/usage.md for scalar order, failure codes, and the proof boundary."

structure Error where
  category : String
  message : String
  details : Json := Json.null
  exitCode : UInt32 := 1

def Error.toJson (e : Error) : Json := Json.mkObj [
  ("recordVersion", Lean.toJson "cli-error-v1"),
  ("status", Lean.toJson (if e.exitCode == 3 then "resource-exhausted" else "failure")),
  ("category", Lean.toJson e.category), ("message", Lean.toJson e.message), ("details", e.details)]

private def invalidArguments (message : String) : Error :=
  ⟨"invalid-arguments", message, Json.null, 2⟩

structure Options where
  /-- `none` means the default for `evaluate`; `simulate` rejects any objective. -/
  objective : Option String := none
  fixture : Option String := none
  input : Option String := none
  budget : Option Nat := none
  trace : Option String := none
  deriving Repr

def parseOptions (args : List String) (options : Options := {})
    (seen : List String := []) : Except Error Options := do
  match args with
  | [] =>
      if options.fixture.isSome && options.input.isSome then
        throw (invalidArguments "Choose either --fixture or --input.")
      return options
  | "--json" :: rest =>
      if seen.contains "--json" then throw (invalidArguments "Duplicate --json.")
      parseOptions rest options ("--json" :: seen)
  | flag :: value :: rest =>
      if seen.contains flag then throw (invalidArguments s!"Duplicate option {flag}.")
      if value.startsWith "--" then throw (invalidArguments s!"Missing value for {flag}.")
      let options ← match flag with
        | "--objective" => pure {options with objective := some value}
        | "--fixture" => pure {options with fixture := some value}
        | "--input" => pure {options with input := some value}
        | "--trace" => pure {options with trace := some value}
        | "--budget" =>
            match value.toNat? with
            | some n => pure {options with budget := some n}
            | none => throw (invalidArguments "--budget must be a nonnegative integer.")
        | _ => throw (invalidArguments s!"Unknown option {flag}.")
      parseOptions rest options (flag :: seen)
  | [flag] => throw (invalidArguments s!"Unknown option or missing value: {flag}.")

def objectives : List Objective := [Evaluation.latency, energy]

def defaultFixture (workload : String) : String :=
  if workload == MatVec.specification.identifier || workload == MatMul.specification.identifier
  then "generated-23" else "mixed-signs"

/-- Fixture convenience only; all values still pass the certified input parser. -/
def fixtureValues (workload name : String) : Except Error (List Int) := do
  if workload == MatVec.specification.identifier then
    if let some (_, input, _) := Examples.MatVecNaive.fixtures.find? (fun f => f.1 == name) then
      return (MatVec.scalarInput input).toList
  else if workload == MatMul.specification.identifier then
    if let some (_, input, _) := Examples.MatMulNaive.fixtures.find? (fun f => f.1 == name) then
      return (MatMul.scalarInput input).toList
  else if workload == Examples.TinyMultiply.specification.identifier then
    if name == "mixed-signs" then return [-7, 6]
    if name == "zeros" then return [0, 0]
  else if workload == Examples.ProductPair.specification.identifier then
    if name == "mixed-signs" then return [-7, 6, 5, -3]
    if name == "zeros" then return [0, 0, 0, 0]
  throw ⟨"unknown-fixture", s!"Unknown fixture {name} for {workload}.", Json.null, 1⟩

private def invalidInputFile (message : String) : Error :=
  ⟨"invalid-input-file", message, Json.null, 1⟩

/-- Bound numeric work before Lean's JSON parser expands positive exponents.
Only a flat numeric array is needed here; rejecting nested values also keeps
untrusted input out of the general parser's recursive array/object paths.
These are transport limits, not changes to the workload or machine domains. -/
private def preflightInputs (contents : String) : Except Error Unit := do
  let input := contents.trimAscii
  unless input.startsWith '[' && input.endsWith ']' do
    throw (invalidInputFile "Expected a JSON array of integers.")
  let body := (input.drop 1).dropEnd 1
  for part in body.toString.splitOn "," do
    let token := part.trimAscii.toString
    if token.length > 4096 then
      throw (invalidInputFile "Numeric input tokens must contain at most 4096 characters.")
    let chars := token.toList
    unless chars.all (fun c => c.isDigit || c.isWhitespace ||
        c == '-' || c == '+' || c == '.' || c == 'e' || c == 'E') do
      throw (invalidInputFile "Expected a flat JSON array of integers.")
    let mantissa := chars.takeWhile (fun c => c != 'e' && c != 'E')
    let exponent := (chars.drop mantissa.length).drop 1
    unless exponent.head? == some '-' do
      let digits := (if exponent.head? == some '+' then exponent.drop 1 else exponent)
        |>.takeWhile Char.isDigit
      let decimals := ((mantissa.dropWhile (· != '.')).drop 1).takeWhile Char.isDigit
      let limit := decimals.length + 4096
      -- Saturate rather than constructing an arbitrarily large exponent value.
      let value := digits.foldl (fun n c => min (limit + 1) (10 * n + c.toNat - '0'.toNat)) 0
      if value > limit then
        throw (invalidInputFile "Positive exponents may expand a numeric input by at most 4096 decimal places.")

def parseInputs (contents : String) : Except Error (List Int) := do
  preflightInputs contents
  let json ← (Json.parse contents).mapError fun e =>
    invalidInputFile s!"Invalid JSON: {e}"
  (fromJson? json : Except String (List Int)).mapError fun e =>
    invalidInputFile s!"Expected a JSON array of integers: {e}"

private def invalidCandidateFile (message : String) : Error :=
  ⟨"invalid-candidate-file", message, Json.null, 1⟩

/-- A candidate file needs only strings, objects, arrays and plain integers, and
four levels of nesting. Rejecting fractions, exponents, long numerals and
nesting beyond eight levels before parsing keeps untrusted files away from
exponent expansion and deep recursion in Lean's general JSON parser. -/
private def preflightCandidate (contents : String) : Except Error Unit := do
  let mut inString := false
  let mut escaped := false
  let mut depth := 0
  let mut digits := 0
  for c in contents.toList do
    if inString then
      if escaped then escaped := false
      else if c == '\\' then escaped := true
      else if c == '"' then inString := false
    else if c.isDigit then
      digits := digits + 1
      if digits > 4096 then
        throw (invalidCandidateFile "Numbers must contain at most 4096 digits.")
    else
      if digits > 0 && (c == '.' || c == 'e' || c == 'E') then
        throw (invalidCandidateFile "Numbers must be plain integers, without fractions or exponents.")
      digits := 0
      if c == '"' then inString := true
      else if c == '[' || c == '{' then
        depth := depth + 1
        if depth > 8 then throw (invalidCandidateFile "JSON nesting must be at most 8 levels deep.")
      else if c == ']' || c == '}' then depth := depth - 1

def parseCandidate (contents : String) : Except Error RawCandidate := do
  preflightCandidate contents
  let json ← (Json.parse contents).mapError fun e => invalidCandidateFile s!"Invalid JSON: {e}"
  (RawCandidate.fromJson? json).mapError invalidCandidateFile

def failureError (failure : Failure) : Error :=
  let category := match failure with
    | .invalidInput _ => "invalid-input"
    | .inadmissibleConfiguration _ => "inadmissible-configuration"
    | .malformedLayout _ => "malformed-layout"
    | .malformedCandidate _ | .structuralBindingMismatch => "malformed-candidate"
    | .malformedInstruction _ => "malformed-instruction"
    | .illegalSchedule _ => "illegal-schedule"
    | .arithmeticFailure _ => "arithmetic-failure"
    | .incompleteOutput _ _ => "incomplete-output"
    | .unverifiedCandidate _ => "unverified-candidate"
  let details := match failure with
    | .invalidInput (.transport (.wrongScalarCount expected actual)) =>
        Json.mkObj [("expectedScalars", toJson expected), ("actualScalars", toJson actual)]
    | .invalidInput (.transport (.scalarOutOfRange index value)) =>
        Json.mkObj [("index", toJson index), ("value", toJson value)]
    | .invalidInput (.outsideDomain workload) => Json.mkObj [("workloadIdentifier", toJson workload)]
    | .illegalSchedule e | .arithmeticFailure e => Json.mkObj [
        ("cycle", toJson e.cycle), ("lane", toJson e.lane), ("rule", toJson (reprStr e.rule))]
    | .incompleteOutput boundary addresses =>
        Json.mkObj [("boundary", toJson boundary), ("addresses", toJson addresses)]
    | _ => Json.null
  ⟨category, reprStr failure, details, 1⟩

def exhaustionError (e : Exhaustion) : Error :=
  ⟨"resource-exhausted", "Boundary budget exhausted; evaluation is inconclusive.",
    Json.mkObj [("nextBoundary", toJson e.nextBoundary),
      ("issuedInstructions", toJson e.issuedInstructions),
      ("remainingInstructions", toJson e.remainingInstructions),
      ("pendingEffects", toJson e.pendingEffects)], 3⟩

private def eventJson : Event → Json
  | .issued cycle lane instruction due => Json.mkObj [
      ("kind", toJson "issued"), ("cycle", toJson cycle), ("lane", toJson lane),
      ("instruction", instructionToJson instruction), ("due", toJson due)]
  | .active cycle lane => Json.mkObj [
      ("kind", toJson "active"), ("cycle", toJson cycle), ("lane", toJson lane)]
  | .committed cycle lane effect =>
      let target := match effect with
        | .register register value => Json.mkObj [("kind", toJson "register"),
            ("register", toJson register.val.val), ("value", toJson value.val)]
        | .memory address value => Json.mkObj [("kind", toJson "memory"),
            ("address", toJson address.val), ("value", toJson (decodeSlot value).val)]
      Json.mkObj [("kind", toJson "committed"), ("cycle", toJson cycle),
        ("lane", toJson lane), ("effect", target)]

private def boundariesJson (trace : List BoundaryTrace) : Json :=
  toJson (trace.map fun b => Json.mkObj [
    ("cycle", toJson b.cycle), ("events", toJson (b.events.map eventJson))])

/-- Compare the complete record, removing only trace fields on both sides. -/
def sameNontraceRecord (a b : ExecutionRecord) : Bool :=
  {a with trace := []} == {b with trace := []}

/-- This is an observed second execution, not a new certificate or accepted score. -/
def observationalTrace (accepted : AcceptedScore raw values) : Except Error Json := do
  let e := accepted.execution
  match executeValues accepted.artifact.verified.candidate
      (accepted.artifact.adapter.encode e.input e.allowed) e.boundaries true with
  | .failure reason => throw ⟨"trace-execution-failed", reprStr reason, Json.null, 1⟩
  | .resourceExhausted details => throw ⟨"trace-exhausted", reprStr details, Json.null, 1⟩
  | .success traced =>
      if !sameNontraceRecord traced e.record then
        throw ⟨"trace-record-mismatch", "Observed trace execution differs from the accepted record.", Json.null, 1⟩
      return Json.mkObj [
        ("recordVersion", toJson "observational-trace-v1"),
        ("verificationStatus", toJson "observational-simulation"),
        ("binding", toJson "same candidate, input and effective budget; all nontrace record fields compared equal"),
        ("effectiveBoundaries", toJson e.boundaries),
        ("acceptedResult", accepted.toJson),
        ("boundaries", boundariesJson traced.trace)]

structure Response where
  json : Json
  human : String

private def catalogResponse (kind : String) : Response := Id.run do
  let mut rows : List (Json × String) := []
  let mut seen : List String := []
  if kind == "objectives" then
    for objective in objectives do
      rows := rows ++ [(Json.mkObj [("identifier", toJson objective.identifier),
        ("unit", toJson objective.unit), ("direction", toJson "minimize")],
        s!"{objective.identifier}: minimize {objective.unit}")]
  else
    for a in objectiveCatalog do
      let c := a.verified.candidate
      if kind == "workloads" then
        if !seen.contains a.specification.identifier then
          seen := a.specification.identifier :: seen
          rows := rows ++ [(Json.mkObj [("identifier", toJson a.specification.identifier),
            ("inputScalars", toJson a.adapter.shape.inputCount),
            ("outputScalars", toJson a.adapter.shape.outputCount),
            ("defaultFixture", toJson (defaultFixture a.specification.identifier))],
            s!"{a.specification.identifier}: {a.adapter.shape.inputCount} inputs, {a.adapter.shape.outputCount} outputs")]
      else
        rows := rows ++ [(Json.mkObj [("identifier", toJson c.identifier),
          ("workloadIdentifier", toJson a.specification.identifier),
          ("lanes", toJson c.configuration.val.lanes), ("banks", toJson c.configuration.val.banks),
          ("sufficientBoundaries", toJson a.verified.sufficientBoundaries)],
          s!"{c.identifier}: {a.specification.identifier}; lanes={c.configuration.val.lanes}, banks={c.configuration.val.banks}; budget={a.verified.sufficientBoundaries}")]
  return ⟨Json.mkObj [("recordVersion", toJson "cli-catalog-v1"), (kind, toJson (rows.map Prod.fst))],
    String.intercalate "\n" (rows.map Prod.snd)⟩

/-- Shared by evaluate and simulate: an explicit input file, else a named or
default fixture. The returned label identifies the input in results. -/
private def loadInputs (workload : String) (options : Options) :
    IO (String × Except Error (List Int)) := do
  match options.input with
  | some file =>
      try
        let contents ← IO.FS.readFile file
        pure (file, parseInputs contents)
      catch e => pure (file, .error ⟨"input-io", s!"Cannot read {file}: {e}", Json.null, 1⟩)
  | none =>
      let name := options.fixture.getD (defaultFixture workload)
      pure (name, fixtureValues workload name)

private def evaluateCommand (identifier : String) (options : Options) : IO (Except Error Response) := do
  let some raw := selectArtifact objectiveCatalog identifier
    | return .error (failureError (.unverifiedCandidate identifier))
  let some artifact := lookupArtifact objectiveCatalog raw
    | return .error (failureError (.unverifiedCandidate identifier))
  let objectiveId := options.objective.getD Versions.latency
  let some objective := objectives.find? (fun o => o.identifier == objectiveId)
    | return .error ⟨"unknown-objective", s!"Unknown objective {objectiveId}.", Json.null, 1⟩
  let (inputId, inputs) ← loadInputs artifact.val.specification.identifier options
  let .ok values := inputs | return inputs.map fun _ => ⟨Json.null, ""⟩
  let budget := options.budget.getD artifact.val.verified.sufficientBoundaries
  match evaluateObjective objectiveCatalog raw values budget inputId objective with
  | .failure reason => return .error (failureError reason)
  | .resourceExhausted details => return .error (exhaustionError details)
  | .accepted accepted =>
      if let some path := options.trace then
        match observationalTrace accepted with
        | .error error => return .error error
        | .ok json =>
            try IO.FS.writeFile path (json.pretty ++ "\n")
            catch e => return .error ⟨"trace-io", s!"Cannot write {path}: {e}", Json.null, 1⟩
      let record := accepted.execution.record
      let score := accepted.result
      let traceNote := options.trace.map (fun path => s!"\nObservational trace: {path}") |>.getD ""
      return .ok ⟨accepted.toJson,
        s!"{identifier}: all-input-certified; {score.objectiveIdentifier} = {score.value} {score.unit} (minimize)\n\
        {record.cycles} cycles; {record.scheduleSize} instructions; {record.outputs.length} outputs; {record.storage.declaredBytes} declared bytes{traceNote}"⟩

/-- Default cap on simulation boundaries (under a second of evaluation), so a huge
`cycle` in an untrusted file cannot stall the evaluator. `--budget` overrides it. -/
def simulationBoundaryCap : Nat := 1000000

def simulationBudget (raw : RawCandidate) (options : Options) : Nat :=
  options.budget.getD (min (sufficientSimulationBoundaries raw) simulationBoundaryCap)

/-- Result of an unverified run. It carries no objective or score, and its
reference check covers only the one input that was executed. -/
private def simulationJson (record : ExecutionRecord) (inputId : String) (values : List Int)
    (budget : Nat) (traceCaptured : Bool) (referenceCheck : Json) : Json := Json.mkObj [
  ("recordVersion", toJson "simulation-result-v1"),
  ("verificationStatus", toJson "unverified-simulation"),
  ("modelVersion", toJson record.modelVersion),
  ("candidateFormatVersion", toJson record.candidateFormatVersion),
  ("workloadIdentifier", toJson record.workloadIdentifier),
  ("candidateIdentifier", toJson record.candidateIdentifier),
  ("inputIdentifier", toJson inputId), ("inputScalars", toJson values),
  ("boundaryBudget", toJson budget),
  ("configuration", configurationJson record.resources),
  ("execution", executionJson record traceCaptured),
  ("referenceCheck", referenceCheck)]

/-- The workload's own codec and domain check, as used by certified evaluation. -/
private def parseArtifactInput (artifact : VerifiedArtifact) (values : List Int) :
    Except Failure {x : artifact.specification.Input // artifact.specification.AllowedInput x} :=
  letI := artifact.domainDecidable
  parseInput artifact.adapter values

private def readCandidate (file : String) : IO (Except Error RawCandidate) := do
  try return parseCandidate (← IO.FS.readFile file)
  catch e => return .error ⟨"candidate-io", s!"Cannot read {file}: {e}", Json.null, 1⟩

/-- Run a candidate file on the fixed machine. The workload's shape, input
domain and reference come from the trusted catalog, never from the file. The
outcome is never certified and never scored, whatever the file contains. -/
private def simulateCommand (file : String) (options : Options) : IO (Except Error Response) := do
  if options.objective.isSome then
    return .error (invalidArguments "simulate takes no --objective: unverified candidates are never scored.")
  let raw ← match ← readCandidate file with
    | .ok raw => pure raw
    | .error e => return .error e
  let some artifact := objectiveCatalog.find? (·.specification.identifier == raw.workloadIdentifier)
    | return .error ⟨"unknown-workload",
        s!"Unknown workload {raw.workloadIdentifier}; see list-workloads.", Json.null, 1⟩
  let (inputId, inputs) ← loadInputs artifact.specification.identifier options
  let values ← match inputs with
    | .ok values => pure values
    | .error e => return .error e
  let input ← match parseArtifactInput artifact values with
    | .ok input => pure input
    | .error reason => return .error (failureError reason)
  let budget := simulationBudget raw options
  match simulate artifact.adapter.shape raw values budget options.trace.isSome with
  | .failure reason => return .error (failureError reason)
  | .resourceExhausted details => return .error (exhaustionError details)
  | .simulated record =>
      let expected := (artifact.adapter.outputScalars (artifact.specification.reference input.val)).toList
      let outputsMatch := record.outputs == expected
      let scope := toJson "this input only; not an all-input proof"
      let referenceCheck := if outputsMatch
        then Json.mkObj [("status", toJson "match"), ("scope", scope)]
        else Json.mkObj [("status", toJson "mismatch"), ("scope", scope),
          ("expectedOutputs", toJson expected)]
      let result := simulationJson record inputId values budget options.trace.isSome referenceCheck
      -- A trace is most useful when outputs are wrong, so write it either way.
      if let some path := options.trace then
        let trace := Json.mkObj [
          ("recordVersion", toJson "simulation-trace-v1"),
          ("verificationStatus", toJson "unverified-simulation"),
          ("effectiveBoundaries", toJson budget),
          ("simulationResult", result),
          ("boundaries", boundariesJson record.trace)]
        try IO.FS.writeFile path (trace.pretty ++ "\n")
        catch e => return .error ⟨"trace-io", s!"Cannot write {path}: {e}", Json.null, 1⟩
      if !outputsMatch then
        let wrong := ((record.outputs.zip expected).zipIdx.filter fun ((a, b), _) => a != b).map (·.2)
        return .error ⟨"output-mismatch",
          s!"Outputs differ from the reference for input {inputId} at {wrong.length} of {expected.length} positions (first: index {wrong.headD 0}).",
          Json.mkObj [("inputIdentifier", toJson inputId), ("cycles", toJson record.cycles),
            ("mismatchedIndices", toJson wrong), ("expectedOutputs", toJson expected),
            ("actualOutputs", toJson record.outputs)], 1⟩
      let traceNote := options.trace.map (fun path => s!"\nUnverified trace: {path}") |>.getD ""
      return .ok ⟨result,
        s!"{raw.identifier}: unverified simulation (not certified, not scored)\n\
        {record.cycles} cycles; {record.scheduleSize} instructions; outputs match the reference for input {inputId} (this input only){traceNote}"⟩

/-- A registered candidate in the `simulate` file format: a valid starting point. -/
private def exportCommand (identifier : String) : Except Error Response :=
  match selectArtifact objectiveCatalog identifier with
  | none => .error (failureError (.unverifiedCandidate identifier))
  | some raw => .ok ⟨raw.toJson, raw.toJson.pretty⟩

/-- IO boundary with no printing; tests exercise the same dispatch as main. -/
def dispatch (args : List String) : IO (Except Error Response) := do
  match args with
  | [] | ["--help"] => return .ok ⟨toJson help, help⟩
  | "evaluate" :: identifier :: rest =>
      if identifier.startsWith "--" then
        return .error (invalidArguments "Missing candidate identifier. Use --help.")
      match parseOptions rest with
      | .error e => return .error e
      | .ok options => evaluateCommand identifier options
  | "simulate" :: file :: rest =>
      if file.startsWith "--" then
        return .error (invalidArguments "Missing candidate file. Use --help.")
      match parseOptions rest with
      | .error e => return .error e
      | .ok options => simulateCommand file options
  | "export-candidate" :: identifier :: rest =>
      if identifier.startsWith "--" then
        return .error (invalidArguments "Missing candidate identifier. Use --help.")
      if rest != [] && rest != ["--json"] then
        return .error (invalidArguments "Unexpected arguments. Use --help.")
      return exportCommand identifier
  | command :: rest =>
      if rest != [] && rest != ["--json"] then
        return .error (invalidArguments "Unexpected arguments. Use --help.")
      match command with
      | "list-workloads" => return .ok (catalogResponse "workloads")
      | "list-candidates" => return .ok (catalogResponse "candidates")
      | "list-objectives" => return .ok (catalogResponse "objectives")
      | _ => return .error (invalidArguments "Unknown command or missing candidate. Use --help.")

def run (args : List String) : IO UInt32 := do
  match ← dispatch args with
  | .ok response =>
      IO.println (if args.contains "--json" then response.json.pretty else response.human)
      return 0
  | .error error =>
      if args.contains "--json" then IO.println error.toJson.pretty
      else (← IO.getStderr).putStrLn s!"{error.category}: {error.message}"
      return error.exitCode

end OptimalComputation.CLI
