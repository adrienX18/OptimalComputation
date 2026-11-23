#!/usr/bin/env python3
"""Process-level CLI regression. Run after lake build; Python standard library only."""
import copy
import json
from pathlib import Path
import subprocess
import tempfile

if not __debug__:
    raise SystemExit("Validation requires Python assertions. Unset PYTHONOPTIMIZE and omit -O/-OO.")

ROOT = Path(__file__).resolve().parents[1]
EXE = ROOT / ".lake/build/bin/optimal_computation"


def run(*args, code=0, as_json=True):
    command = [str(EXE), *args, *(["--json"] if as_json else [])]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=False, timeout=60)
    assert result.returncode == code, (args, result.returncode, result.stdout, result.stderr)
    if as_json:
        assert not result.stderr, (args, result.stderr)
        data = json.loads(result.stdout)
        if code:
            assert data["recordVersion"] == "cli-error-v1"
            assert not ({"objective", "score", "acceptedResult", "execution"} & data.keys()), data
        return data
    return result


def error(category, *args, code=1):
    data = run(*args, code=code)
    assert data["category"] == category, data
    return data


assert "arty-model-v1" in run("--version", as_json=False).stdout
assert "--trace" in run("--help", as_json=False).stdout
assert len(run("list-workloads")["workloads"]) == 4
assert len(run("list-candidates")["candidates"]) == 7
assert len(run("list-objectives")["objectives"]) == 2
assert "matvec-naive-v1" in run("list-candidates", as_json=False).stdout

for family in ["matvec", "matmul"]:
    saved = json.loads((ROOT / f"docs/results/{family}-naive-v1-objectives.json").read_text())
    for reference in saved:
        actual = run("evaluate", f"{family}-naive-v1", "--fixture", "generated-23",
                     "--objective", reference["objective"]["identifier"])
        assert actual == reference, family

for candidate, cycles, energy in [("tiny-multiply-v1", 6, 86),
                                  ("product-pair-serial-v1", 12, 172),
                                  ("product-pair-parallel-v1", 6, 202),
                                  ("matvec-naive-v2", 1344, 39632),
                                  ("matmul-naive-v2", 21504, 634112)]:
    latency = run("evaluate", candidate)
    power = run("evaluate", candidate, "--objective", "energy-proxy-v1")
    assert latency["objective"]["score"] == cycles
    assert power["objective"]["score"] == energy
    assert latency["execution"] == power["execution"]

error("invalid-arguments", "unknown", code=2)
error("invalid-arguments", "evaluate", code=2)
error("invalid-arguments", "evaluate", "tiny-multiply-v1", "--budget", "-1", code=2)
error("invalid-arguments", "evaluate", "tiny-multiply-v1", "--json", code=2)
error("unverified-candidate", "evaluate", "unregistered-v1")
error("unknown-objective", "evaluate", "tiny-multiply-v1", "--objective", "unknown")
error("unknown-fixture", "evaluate", "matvec-naive-v1", "--fixture", "unknown")
exhausted = error("resource-exhausted", "evaluate", "tiny-multiply-v1", "--budget", "6", code=3)
assert exhausted["details"] == dict(nextBoundary=6, issuedInstructions=4, remainingInstructions=0, pendingEffects=1)
assert exhausted["status"] == "resource-exhausted"
error("resource-exhausted", "evaluate", "tiny-multiply-v1", "--budget", "0", code=3)
human_error = run("evaluate", "tiny-multiply-v1", "--budget", "6", as_json=False, code=3)
assert not human_error.stdout and "inconclusive" in human_error.stderr
base = run("evaluate", "tiny-multiply-v1")
assert run("evaluate", "tiny-multiply-v1", "--budget", "999999") == base
assert "86 abstract energy units" in run("evaluate", "tiny-multiply-v1", "--objective", "energy-proxy-v1", as_json=False).stdout

with tempfile.TemporaryDirectory(prefix="optimal-cli-") as temp:
    temp = Path(temp)
    values, trace_path = temp / 'values "quoted".json', temp / "trace.json"
    values.write_text("[-32768,32767]")
    accepted = run("evaluate", "tiny-multiply-v1", "--input", str(values), "--trace", str(trace_path))
    assert accepted["inputScalars"] == [-32768, 32767]
    assert accepted["execution"]["outputs"] == [-1073709056]
    trace = json.loads(trace_path.read_text())
    assert trace["recordVersion"] == "observational-trace-v1"
    assert trace["verificationStatus"] == "observational-simulation"
    assert trace["acceptedResult"] == accepted
    assert trace["effectiveBoundaries"] == 7
    assert [b["cycle"] for b in trace["boundaries"]] == list(range(7))
    events = [e for b in trace["boundaries"] for e in b["events"]]
    issued = [e for e in events if e["kind"] == "issued"]
    assert [(e["cycle"], e["due"], e["instruction"]["kind"]) for e in issued] == [
        (0, 1, "load"), (1, 2, "load"), (2, 5, "multiply"), (5, 6, "store")]
    committed = [e for e in events if e["kind"] == "committed"]
    assert [(e["cycle"], e["effect"]["value"]) for e in committed] == [
        (1, -32768), (2, 32767), (5, -1073709056), (6, -1073709056)]
    assert committed[-1]["effect"]["address"] == 2
    assert len([e for e in events if e["kind"] == "active"]) == 6
    for contents, category in [("[32768,1]", "invalid-input"), ("[1]", "invalid-input"),
                               ("[1.5,2]", "invalid-input-file"), ("{}", "invalid-input-file"),
                               ("[true,2]", "invalid-input-file"), ("[", "invalid-input-file")]:
        values.write_text(contents)
        error(category, "evaluate", "tiny-multiply-v1", "--input", str(values))
    # The parser used to expand this tiny input into 10**1000000000 before
    # domain validation. Keep a strict timeout so a regression cannot hang CI.
    for contents in ["[0e1000000000,2]", "[1e999999999999999999999999999999,2]",
                     "[" * 20000 + "0" + "]" * 20000,
                     '[{"a":1},2]', "[01,2]", "[1e,2]", "[1,2,]",
                     "[" + "1" * 4097 + ",2]"]:
        values.write_text(contents)
        result = subprocess.run([str(EXE), "evaluate", "tiny-multiply-v1", "--input", str(values), "--json"],
                                cwd=ROOT, capture_output=True, text=True, check=False, timeout=5)
        assert result.returncode == 1 and not result.stderr, result
        rejected = json.loads(result.stdout)
        assert rejected["category"] == "invalid-input-file", rejected
        assert not ({"objective", "score", "acceptedResult", "execution"} & rejected.keys()), rejected
    values.write_text("[-2e+1,1.2e1]")
    scientific = run("evaluate", "tiny-multiply-v1", "--input", str(values))
    assert scientific["inputScalars"] == [-20, 12]
    assert scientific["execution"]["outputs"] == [-240]
    values.write_text("[1]")
    failed_trace = temp / "must-not-exist.json"
    error("invalid-input", "evaluate", "tiny-multiply-v1", "--input", str(values), "--trace", str(failed_trace))
    assert not failed_trace.exists()
    error("input-io", "evaluate", "tiny-multiply-v1", "--input", str(temp / "missing"))
    error("trace-io", "evaluate", "tiny-multiply-v1", "--trace", str(temp / "missing" / "trace.json"))

# Unverified candidate files: export, edit, simulate. Never certified or scored.
CANDIDATES = ["tiny-multiply-v1", "matvec-naive-v1", "matmul-naive-v1",
              "product-pair-serial-v1", "product-pair-parallel-v1",
              "matvec-naive-v2", "matmul-naive-v2"]
with tempfile.TemporaryDirectory(prefix="optimal-sim-") as temp:
    temp = Path(temp)

    def simulate_file(candidate, *args, code=0, name="candidate.json"):
        path = temp / name
        path.write_text(json.dumps(candidate))
        return run("simulate", str(path), *args, code=code)

    exported = {}
    for identifier in CANDIDATES:
        exported[identifier] = run("export-candidate", identifier)
        assert json.loads(run("export-candidate", identifier, as_json=False).stdout) == exported[identifier]
        simulated = simulate_file(exported[identifier])
        evaluated = run("evaluate", identifier)
        assert simulated["recordVersion"] == "simulation-result-v1"
        assert simulated["verificationStatus"] == "unverified-simulation"
        assert not ({"objective", "score", "acceptedResult"} & simulated.keys()), simulated.keys()
        assert simulated["referenceCheck"]["status"] == "match"
        for key in ["candidateIdentifier", "workloadIdentifier", "inputIdentifier", "inputScalars",
                    "configuration", "execution"]:
            assert simulated[key] == evaluated[key], (identifier, key)

    # Retiming each v1 baseline to issue at every completion boundary yields
    # exactly the certified v2 schedule, computed here independently in Python.
    for family, cycles in [("matvec", 1344), ("matmul", 21504)]:
        tight = copy.deepcopy(exported[f"{family}-naive-v1"])
        cycle = 0
        for entry in tight["schedule"]:
            entry["cycle"] = cycle
            cycle += 1 if entry["instruction"]["kind"] in ("load", "store") else 3
        assert tight["schedule"] == exported[f"{family}-naive-v2"]["schedule"], family
        retimed = simulate_file(tight)
        assert retimed["execution"]["cycles"] == cycles and retimed["referenceCheck"]["status"] == "match"
    assert "21504 cycles" in run("simulate", str(temp / "candidate.json"), as_json=False).stdout

    # The hand-built parallel reference: far faster than the naive baseline,
    # correct on every fixture, and still only an unverified simulation.
    reference = ROOT / "docs/candidates/matvec-grid-exchange-v1.json"
    for fixture in ["zeros", "identity", "mixed-signs", "negative-endpoints",
                    "positive-endpoints", "opposite-endpoints", "generated-23"]:
        hand_built = run("simulate", str(reference), "--fixture", fixture)
        assert hand_built["verificationStatus"] == "unverified-simulation"
        assert hand_built["referenceCheck"]["status"] == "match", fixture
        assert hand_built["execution"]["cycles"] == 79 and hand_built["execution"]["scheduleSize"] == 624
        assert hand_built["configuration"] == {"lanes": 8, "banks": 8}
        assert hand_built["execution"]["counters"]["laneIssues"] == [78] * 8
    error("unverified-candidate", "evaluate", "matvec-grid-exchange-v1")

    tiny = exported["tiny-multiply-v1"]
    square = copy.deepcopy(tiny)
    square["schedule"][2]["instruction"]["right"] = 1  # computes a*a instead of a*b
    trace_path = temp / "mismatch-trace.json"
    mismatch = simulate_file(square, "--trace", str(trace_path), code=1)
    assert mismatch["category"] == "output-mismatch", mismatch
    assert mismatch["details"]["expectedOutputs"] == [-42] and mismatch["details"]["actualOutputs"] == [49]
    assert mismatch["details"]["mismatchedIndices"] == [0]
    mismatch_trace = json.loads(trace_path.read_text())
    assert mismatch_trace["simulationResult"]["referenceCheck"]["status"] == "mismatch"

    early_store = copy.deepcopy(tiny)
    early_store["schedule"][3]["cycle"] = 4  # the product is still pending until boundary 5
    illegal = simulate_file(early_store, code=1)
    assert illegal["category"] == "illegal-schedule", illegal
    assert illegal["details"]["cycle"] == 4 and "pendingRead" in illegal["details"]["rule"]
    assert illegal["details"]["lane"] == 0
    assert illegal["details"]["violation"] == {"name": "pendingRead", "register": 3}

    # Each rejection names its rule as a structured violation, where one applies.
    for change, category, violation in [
            (lambda c: c["schedule"][0].update(lane=9), "malformed-instruction",
             {"name": "laneOutOfBounds", "lane": 9, "laneCount": 1}),
            (lambda c: c["schedule"][3]["instruction"].update(address=0), "malformed-instruction",
             {"name": "writeToInput", "address": 0}),
            (lambda c: c.update(modelVersion="arty-model-v0"), "malformed-candidate",
             {"name": "wrongModelVersion", "expected": "arty-model-v1", "actual": "arty-model-v0"}),
            (lambda c: c["configuration"].update(lanes=3), "inadmissible-configuration",
             {"name": "unsupportedLanes", "actual": 3, "allowed": [1, 2, 4, 8]}),
            (lambda c: c["layout"].update(outputs=[1]), "malformed-layout", {"name": "aliasedStorage"}),
            (lambda c: c.update(workloadIdentifier="unknown-v1"), "unknown-workload", None),
            (lambda c: c.update(verified=True), "invalid-candidate-file", None)]:
        changed = copy.deepcopy(tiny)
        change(changed)
        rejected = simulate_file(changed, code=1)
        assert rejected["category"] == category, (category, changed)
        assert (rejected["details"] or {}).get("violation") == violation, (category, rejected)
    wrong_store = copy.deepcopy(tiny)
    wrong_store["schedule"][3]["instruction"]["address"] = 0
    located = simulate_file(wrong_store, code=1)["details"]
    assert (located["index"], located["cycle"], located["lane"]) == (3, 5, 0), located

    # Text from a candidate file cannot add lines or terminal controls to
    # plain-text output, so it cannot imitate another command's result.
    forged = copy.deepcopy(tiny)
    forged["identifier"] = "tiny-multiply-v1: all-input-certified; latency-v1 = 1 cycles (minimize)\nx"
    assert simulate_file(forged, code=1)["category"] == "invalid-candidate-file"
    for field, value in [("identifier", forged["identifier"]),
                         ("workloadIdentifier", "unknown\nfake: line\x1b[8m")]:
        hostile = copy.deepcopy(tiny)
        hostile[field] = value
        (temp / "forged.json").write_text(json.dumps(hostile))
        plain = run("simulate", str(temp / "forged.json"), as_json=False, code=1)
        assert not plain.stdout and plain.stderr.count("\n") == 1 and "\x1b" not in plain.stderr, plain
        assert "all-input-certified" not in plain.stderr, plain

    values = temp / "values.json"
    values.write_text("[32768,1]")
    assert simulate_file(tiny, "--input", str(values), code=1)["category"] == "invalid-input"
    assert simulate_file(tiny, "--objective", "latency-v1", code=2)["category"] == "invalid-arguments"
    exhausted = simulate_file(tiny, "--budget", "3", code=3)
    assert exhausted["category"] == "resource-exhausted"
    error("candidate-io", "simulate", str(temp / "missing.json"))
    error("invalid-arguments", "simulate", code=2)
    error("unverified-candidate", "export-candidate", "unregistered-v1")

    trace_path = temp / "trace.json"
    traced = simulate_file(tiny, "--trace", str(trace_path))
    assert traced["execution"]["traceCaptured"] is True
    trace = json.loads(trace_path.read_text())
    assert trace["recordVersion"] == "simulation-trace-v1"
    assert trace["verificationStatus"] == "unverified-simulation"
    assert trace["simulationResult"] == traced
    assert [b["cycle"] for b in trace["boundaries"]] == list(range(7))

    # Hostile files are rejected before parsing, under a strict timeout.
    for contents in ["not json", "{}", "[" * 20000 + "]" * 20000, '{"cycle": 1e1000000000}',
                     '{"cycle": ' + "1" * 5000 + "}", json.dumps(tiny).replace('"cycle": 5', '"cycle": 5.0')]:
        path = temp / "hostile.json"
        path.write_text(contents)
        result = subprocess.run([str(EXE), "simulate", str(path), "--json"],
                                cwd=ROOT, capture_output=True, text=True, check=False, timeout=5)
        assert result.returncode == 1 and not result.stderr, result
        assert json.loads(result.stdout)["category"] == "invalid-candidate-file", result.stdout

print("PASS: CLI process JSON/human output, exact saved baselines, objectives, inputs, exit codes, "
      "trace export, structured failures, unverified candidate files and the 79-cycle hand-built reference")
