#!/usr/bin/env python3
"""Process-level CLI regression. Run after lake build; Python standard library only."""
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
assert len(run("list-candidates")["candidates"]) == 5
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
                                  ("product-pair-parallel-v1", 6, 202)]:
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

print("PASS: CLI process JSON/human output, exact saved baselines, objectives, inputs, exit codes and trace export")
