import OptimalComputation.CLI

namespace OptimalComputation.Tests
open Lean Evaluation CLI

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

def cli : IO Unit := do
  for input in ["not-json", "{}", "[true]", "[\"1\"]", "[1.5]", "[null]"] do
    checkCLI "noninteger input rejected" (parseInputs input).toOption.isNone
  checkCLI "signed input JSON" ((parseInputs "[-32768,0,32767]").toOption == some [-32768, 0, 32767])
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
  checkCLI "five candidates" (((candidates.getObjValAs? (Array Json) "candidates").toOption.map Array.size) == some 5)
  let objectives ← response ["list-objectives", "--json"]
  checkCLI "two objectives" (((objectives.getObjValAs? (Array Json) "objectives").toOption.map Array.size) == some 2)
  for (id, cycles, energyCost) in [("tiny-multiply-v1", 6, 86), ("matvec-naive-v1", 2143, 59607),
      ("matmul-naive-v1", 34303, 954087), ("product-pair-serial-v1", 12, 172),
      ("product-pair-parallel-v1", 6, 202)] do
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
  IO.println "PASS: CLI catalogs, parsing, failures, five candidates, both objectives and complete trace binding"

end OptimalComputation.Tests
