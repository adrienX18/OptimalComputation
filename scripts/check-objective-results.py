"""Check saved M8 result arithmetic and same-execution rescoring independently."""
import json
from pathlib import Path

if not __debug__:
    raise SystemExit("Validation requires Python assertions. Unset PYTHONOPTIMIZE and omit -O/-OO.")

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "docs" / "results"
COEFFICIENTS = {
    "base_per_cycle": 1, "lane_per_cycle": 1, "bram_per_cycle": 1,
    "load": 4, "store": 4, "addition": 1, "multiplication": 8,
    "multiply_add": 9, "register_read": 1, "register_write": 1,
}
EXPECTED = {
    "matvec-naive-v1": (2143, 59607, 8, 8, 16),
    "product-pair-serial-v1": (12, 172, 1, 1, 8),
    "product-pair-parallel-v1": (6, 202, 8, 8, 16),
}
records = []
for filename in ("matvec-naive-v1-objectives.json", "product-pair-v1-objectives.json"):
    records.extend(json.loads((RESULTS / filename).read_text()))
assert len(records) == 6
for candidate, (cycles, energy, lanes, banks, bram) in EXPECTED.items():
    pair = [r for r in records if r["candidateIdentifier"] == candidate]
    assert len(pair) == 2
    latency, power = pair
    assert {k: v for k, v in latency.items() if k != "objective"} == {
        k: v for k, v in power.items() if k != "objective"
    }
    for record in pair:
        assert record["verificationStatus"] == "all-input-certified"
        assert record["recordVersion"] == "accepted-objective-result-v1"
        assert record["modelVersion"] == "arty-model-v1"
        assert record["candidateFormatVersion"] == "candidate-v1"
        assert record["configuration"] == {"lanes": lanes, "banks": banks}
        execution = record["execution"]
        assert execution["cycles"] == cycles
        assert execution["resources"]["bram36Blocks"] == bram
        assert execution["traceCaptured"] is False
        objective = record["objective"]
        assert objective["direction"] == "minimize"
        assert all(t["cost"] == t["quantity"] * t["coefficient"] for t in objective["breakdown"])
        assert sum(t["cost"] for t in objective["breakdown"]) == objective["score"]
    assert latency["objective"] == {
        "identifier": "latency-v1", "unit": "cycles", "direction": "minimize",
        "score": cycles, "coefficients": None,
        "breakdown": [{"label": "elapsed cycles", "quantity": cycles, "coefficient": 1, "cost": cycles}],
    }
    objective = power["objective"]
    assert objective["identifier"] == "energy-proxy-v1"
    assert objective["unit"] == "abstract energy units"
    assert objective["coefficients"] == {"identifier": "energy-coefficients-v1", "values": COEFFICIENTS}
    counts = power["execution"]["counters"]
    formula = cycles * (1 + lanes + bram) + 4 * counts["loads"] + 4 * counts["stores"]
    formula += counts["additions"] + 8 * counts["multiplications"] + 9 * counts["multiplyAdds"]
    formula += counts["registerReads"] + counts["registerWrites"]
    assert objective["score"] == energy == formula
    if candidate.startswith("product-pair"):
        assert power["inputScalars"] == [-7, 6, 5, -3]
        assert power["execution"]["outputs"] == [-42, -15]
        assert [counts[k] for k in ("loads", "stores", "additions", "multiplications", "multiplyAdds", "registerReads", "registerWrites")] == [4, 2, 0, 2, 0, 6, 6]
    else:
        original = json.loads((RESULTS / "matvec-naive-v1.json").read_text())
        assert power["execution"]["outputs"] == original["outputs"]
        assert power["execution"]["cycles"] == original["cycles"]
        assert power["execution"]["scheduleSize"] == original["scheduleSize"]
        for key, value in counts.items():
            assert value == original[key]
        assert len(power["inputScalars"]) == 272
assert 6 < 12 and 172 < 202
print("PASS: six objective reports, exact costs/coefficients, identical execution under rescoring, and frozen baseline summary")
