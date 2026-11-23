import OptimalComputation.CLI

namespace OptimalComputation.Tests
open Lean Evaluation CLI Candidates

private def checkCLI (label : String) (ok : Bool) : IO Unit := do
  unless ok do throw <| IO.userError s!"CLI check failed: {label}"

private def response (args : List String) : IO Json := do
  match ← dispatch args with
  | .ok r => return r.json
  | .error e => throw <| IO.userError s!"CLI unexpectedly failed: {e.message}"

private def rejects (args : List String) (category : String) : IO Unit := do
  match ← dispatch args with
  | .ok _ => throw <| IO.userError "CLI unexpectedly accepted bad arguments"
  | .error e =>
      checkCLI "failure category" (e.category == category)
      checkCLI "failure has no score" ((e.toJson.getObjVal? "objective").toOption.isNone)

/-- A minimal well-formed candidate file; `entry` is its single schedule entry. -/
private def candidateText (entry : String := "{\"cycle\":0,\"lane\":0,\"instruction\":{\"kind\":\"load\",\"destination\":1,\"address\":0}}")
    (extra : String := "") (identifier : String := "t") : String :=
  "{\"identifier\":\"" ++ identifier ++ "\",\"workloadIdentifier\":\"w\",\"modelVersion\":\"m\"," ++
  "\"formatVersion\":\"f\",\"configuration\":{\"lanes\":1,\"banks\":1}," ++
  "\"layout\":{\"inputs\":[0],\"outputs\":[1],\"scratch\":[]},\"schedule\":[" ++ entry ++ "]" ++
  extra ++ "}"

/-- The JSON transport for unverified candidate files: exact round trips for
every registered artifact, strict field sets, and bounded parsing. -/
private def candidateFiles : IO Unit := do
  for artifact in objectiveCatalog do
    let raw := artifact.verified.candidate.toRaw
    checkCLI "candidate JSON value round trip" ((RawCandidate.fromJson? raw.toJson).toOption == some raw)
    checkCLI "candidate file round trip" ((parseCandidate raw.toJson.compress).toOption == some raw)
    checkCLI "pretty candidate file round trip" ((parseCandidate raw.toJson.pretty).toOption == some raw)
    let exported ← response ["export-candidate", raw.identifier]
    checkCLI "export prints the registered candidate" ((RawCandidate.fromJson? exported).toOption == some raw)
  checkCLI "minimal candidate file accepted" (parseCandidate candidateText).toOption.isSome
  checkCLI "digits and exponent letters inside strings accepted"
    ((parseCandidate (candidateText (identifier := "v1.2e5"))).toOption.map (·.identifier) == some "v1.2e5")
  let load := "\"instruction\":{\"kind\":\"load\",\"destination\":1,\"address\":0}"
  -- Each case names the message fragment it must produce, so a rejection for
  -- an unrelated reason (for example an unknown field) cannot satisfy it.
  for (text, reason) in [
      (candidateText (extra := ",\"verified\":true"), "unknown field \"verified\""),
      ("{\"identifier\":\"t\"}", "missing field"),
      (candidateText "{\"cycle\":0,\"lane\":0,\"instruction\":{\"kind\":\"divide\",\"destination\":1,\"address\":0}}",
        "unknown instruction kind \"divide\""),
      (candidateText "{\"cycle\":0,\"lane\":0,\"instruction\":{\"kind\":\"load\",\"destination\":1,\"address\":0,\"left\":2}}",
        "unknown field \"left\""),
      (candidateText "{\"cycle\":0,\"lane\":0,\"instruction\":{\"kind\":\"store\",\"source\":1}}",
        "missing field \"address\""),
      (candidateText ("{\"cycle\":0,\"lane\":0,\"due\":3," ++ load ++ "}"), "unknown field \"due\""),
      (candidateText ("{\"cycle\":-1,\"lane\":0," ++ load ++ "}"), "schedule[0].cycle: expected a nonnegative integer"),
      (candidateText ("{\"cycle\":0,\"lane\":\"0\"," ++ load ++ "}"), "schedule[0].lane: expected a nonnegative integer"),
      (candidateText ("{\"cycle\":1.0,\"lane\":0," ++ load ++ "}"), "plain integers"),
      (candidateText ("{\"cycle\":1e3,\"lane\":0," ++ load ++ "}"), "plain integers"),
      (candidateText (extra := ",\"x\":" ++ String.ofList (List.replicate 20 '[') ++
        String.ofList (List.replicate 20 ']')), "nesting"),
      (candidateText ("{\"cycle\":" ++ String.ofList (List.replicate 4097 '1') ++ ",\"lane\":0," ++ load ++ "}"),
        "4096 digits"),
      ("[1,2]", "expected an object"), ("{\"identifier\":", "Invalid JSON")] do
    match parseCandidate text with
    | .ok _ => throw <| IO.userError s!"CLI check failed: candidate file accepted ({reason})"
    | .error e =>
        checkCLI s!"candidate file rejected for: {reason}"
          (e.category == "invalid-candidate-file" && (e.message.splitOn reason).length > 1)
  let tiny := Examples.TinyMultiply.candidate.toRaw
  checkCLI "default simulation budget covers the last completion" (sufficientSimulationBoundaries tiny == 9)
  checkCLI "empty schedule budget" (sufficientSimulationBoundaries {tiny with schedule := []} == 4)
  let late := {tiny with schedule := [⟨5000000, 0, .load 1 0⟩]}
  checkCLI "default simulation budget is capped" (simulationBudget late {} == simulationBoundaryCap)
  checkCLI "explicit budget overrides the cap" (simulationBudget late {budget := some 7} == 7)
  rejects ["simulate", "--json"] "invalid-arguments"
  rejects ["simulate", "candidate.json", "--objective", "latency-v1"] "invalid-arguments"
  rejects ["export-candidate", "missing"] "unverified-candidate"
  rejects ["export-candidate", "tiny-multiply-v1", "extra"] "invalid-arguments"

def cli : IO Unit := do
  for input in ["not-json", "{}", "[true]", "[\"1\"]", "[1.5]", "[null]"] do
    checkCLI "noninteger input rejected" (parseInputs input).toOption.isNone
  checkCLI "signed input JSON" ((parseInputs "[-32768,0,32767]").toOption == some [-32768, 0, 32767])
  checkCLI "scientific integer JSON" ((parseInputs "[-2e+1,1.2e1,3e0]").toOption == some [-20, 12, 3])
  checkCLI "positive exponent expansion boundary"
    ((parseInputs "[0e4096,0.0e4097]").toOption == some [0, 0])
  -- Extreme exponent regressions run in check-cli.py under a process timeout.
  for input in ["[0e4097,2]", "[0.0e4098,2]",
      "[[1],2]", "[{\"a\":1},2]", "[01,2]", "[1e,2]", "[1,2,]",
      "[" ++ String.ofList (List.replicate 4097 '1') ++ ",2]"] do
    checkCLI "unsafe or malformed input rejected" (parseInputs input).toOption.isNone
  for args in [["evaluate"], ["bad"], ["list-candidates", "extra"],
      ["evaluate", "tiny-multiply-v1", "--budget", "-1"],
      ["evaluate", "tiny-multiply-v1", "--budget", "1.5"],
      ["evaluate", "tiny-multiply-v1", "--budget"],
      ["evaluate", "tiny-multiply-v1", "--input", "--json"],
      ["evaluate", "tiny-multiply-v1", "--json", "--json"],
      ["evaluate", "tiny-multiply-v1", "--objective", "latency-v1", "--objective", "energy-proxy-v1"],
      ["evaluate", "tiny-multiply-v1", "--fixture", "zeros", "--input", "file"]] do
    rejects args "invalid-arguments"
  rejects ["evaluate", "missing"] "unverified-candidate"
  rejects ["evaluate", "tiny-multiply-v1", "--objective", "missing"] "unknown-objective"
  rejects ["evaluate", "tiny-multiply-v1", "--fixture", "missing"] "unknown-fixture"
  rejects ["evaluate", "tiny-multiply-v1", "--budget", "6"] "resource-exhausted"
  let workloads ← response ["list-workloads", "--json"]
  checkCLI "four workloads" (((workloads.getObjValAs? (Array Json) "workloads").toOption.map Array.size) == some 4)
  let candidates ← response ["list-candidates", "--json"]
  checkCLI "seven candidates" (((candidates.getObjValAs? (Array Json) "candidates").toOption.map Array.size) == some 7)
  let objectives ← response ["list-objectives", "--json"]
  checkCLI "two objectives" (((objectives.getObjValAs? (Array Json) "objectives").toOption.map Array.size) == some 2)
  for (id, cycles, energyCost) in [("tiny-multiply-v1", 6, 86), ("matvec-naive-v1", 2143, 59607),
      ("matmul-naive-v1", 34303, 954087), ("product-pair-serial-v1", 12, 172),
      ("product-pair-parallel-v1", 6, 202), ("matvec-naive-v2", 1344, 39632),
      ("matmul-naive-v2", 21504, 634112)] do
    let lat ← response ["evaluate", id]
    let eng ← response ["evaluate", id, "--objective", "energy-proxy-v1"]
    checkCLI "independent objective execution" ((lat.getObjVal? "execution").toOption == (eng.getObjVal? "execution").toOption)
    checkCLI "latency score" ((lat.getObjVal? "objective" >>= fun j => j.getObjValAs? Nat "score").toOption == some cycles)
    checkCLI "energy score" ((eng.getObjVal? "objective" >>= fun j => j.getObjValAs? Nat "score").toOption == some energyCost)
  let some raw := selectArtifact objectiveCatalog "tiny-multiply-v1"
    | throw <| IO.userError "Missing tiny artifact"
  let .accepted accepted := evaluateObjective objectiveCatalog raw [-7, 6] 7 "mixed-signs" Evaluation.latency
    | throw <| IO.userError "Missing tiny acceptance"
  let r := accepted.execution.record
  let changes : List ExecutionRecord := [
    {r with modelVersion := "changed"}, {r with candidateFormatVersion := "changed"},
    {r with workloadIdentifier := "changed"}, {r with candidateIdentifier := "changed"},
    {r with cycles := r.cycles + 1}, {r with outputs := [0]},
    {r with counters := {r.counters with loads := 99}},
    {r with resources := {r.resources with dspSlices := 99}},
    {r with storage := {r.storage with declaredBytes := 99}}, {r with scheduleSize := 99}]
  for changed in changes do checkCLI "trace binding checks every record field" (!sameNontraceRecord r changed)
  checkCLI "trace is the only ignored field" (sameNontraceRecord r {r with trace := [⟨99, []⟩]})
  let .ok trace := observationalTrace accepted | throw <| IO.userError "Trace export failed"
  checkCLI "trace bound to exact accepted JSON" ((trace.getObjVal? "acceptedResult").toOption == some accepted.toJson)
  checkCLI "seven traced boundaries" (((trace.getObjValAs? (Array Json) "boundaries").toOption.map Array.size) == some 7)
  let .failure badInput := evaluateObjective objectiveCatalog raw [32768, 1] 7 "bad" Evaluation.latency
    | throw <| IO.userError "Invalid workload input accepted"
  checkCLI "workload domain reported" ((failureError badInput).category == "invalid-input")
  candidateFiles
  IO.println "PASS: CLI catalogs, parsing, failures, seven candidates, both objectives, complete trace binding and candidate files"

end OptimalComputation.Tests
