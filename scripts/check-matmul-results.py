"""Independently check M9 scalar results, executed counts, and both scores."""
import json
from pathlib import Path

if not __debug__:
    raise SystemExit("Validation requires Python assertions. Unset PYTHONOPTIMIZE and omit -O/-OO.")

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "docs" / "results"
SEED = 23
A = [[(17 * i + 31 * j + SEED) % 101 - 50 for j in range(16)] for i in range(16)]
B = [[(19 * i + 11 * j + 7 * SEED) % 61 - 30 for j in range(16)] for i in range(16)]
INPUTS = [v for row in A + B for v in row]
OUTPUTS = [sum(A[i][k] * B[k][j] for k in range(16)) for i in range(16) for j in range(16)]
CYCLES = 256 * (4 + 16 * (2 + 2 + 4) + 2) - 1
SCHEDULE_SIZE = 256 * (1 + 16 * 3 + 1)
LAYOUT = {
    "order": "row-major", "leftMatrixSlots": [0, 255],
    "rightMatrixSlots": [256, 511], "outputSlots": [512, 767], "scratchSlots": [],
}
COEFFICIENTS = {
    "base_per_cycle": 1, "lane_per_cycle": 1, "bram_per_cycle": 1,
    "load": 4, "store": 4, "addition": 1, "multiplication": 8,
    "multiply_add": 9, "register_read": 1, "register_write": 1,
}


def counters(lanes, banks):
    bank_accesses = [0] * banks
    for i in range(16):
        for j in range(16):
            for k in range(16):
                bank_accesses[(16 * i + k) % banks] += 1
                bank_accesses[(256 + 16 * k + j) % banks] += 1
            bank_accesses[(512 + 16 * i + j) % banks] += 1
    assert bank_accesses == [8448 // banks] * banks
    return {
        "loads": 256 * 16 * 2, "stores": 256, "additions": 256,
        "multiplications": 0, "multiplyAdds": 256 * 16,
        "registerReads": 256 * (2 + 16 * 3 + 1),
        "registerWrites": 256 * (1 + 16 * 3), "bankAccesses": bank_accesses,
        "laneIssues": [SCHEDULE_SIZE] + [0] * (lanes - 1),
        "laneCompletions": [SCHEDULE_SIZE] + [0] * (lanes - 1),
        "laneActiveCycles": [256 * (3 + 16 * (1 + 1 + 3) + 1)] + [0] * (lanes - 1),
    }


def identity(record):
    assert record["modelVersion"] == "arty-model-v1"
    assert record["candidateFormatVersion"] == "candidate-v1"
    assert record["workloadIdentifier"] == "matmul-16x16-signed16-v1"
    assert record["candidateIdentifier"] == "matmul-naive-v1"


def baseline(record, status):
    identity(record)
    assert record["recordVersion"] == "matmul-baseline-record-v1"
    assert record["verificationStatus"] == status
    assert record["fixture"] == "generated-23"
    assert record["layout"] == LAYOUT
    assert record["outputs"] == OUTPUTS
    assert record["cycles"] == CYCLES == 34303
    assert record["scheduleSize"] == SCHEDULE_SIZE == 12800
    assert record["declaredBytes"] == 6144
    expected = counters(**record["configuration"])
    assert {key: record[key] for key in expected} == expected


primary = json.loads((RESULTS / "matmul-naive-v1.json").read_text())
configurations = json.loads((RESULTS / "matmul-naive-v1-configurations.json").read_text())
latency, energy = json.loads((RESULTS / "matmul-naive-v1-objectives.json").read_text())
baseline(primary, "all-input-certified")
assert primary["configuration"] == {"lanes": 8, "banks": 8}
assert len(configurations) == 16
assert {(r["configuration"]["lanes"], r["configuration"]["banks"]) for r in configurations} == {
    (lanes, banks) for lanes in (1, 2, 4, 8) for banks in (1, 2, 4, 8)
}
for config in configurations:
    baseline(config, "conformance-simulation")
assert {k: v for k, v in latency.items() if k != "objective"} == {
    k: v for k, v in energy.items() if k != "objective"
}
for record in (latency, energy):
    identity(record)
    assert record["recordVersion"] == "accepted-objective-result-v1"
    assert record["verificationStatus"] == "all-input-certified"
    assert record["inputIdentifier"] == "generated-23"
    assert record["inputScalars"] == INPUTS
    assert record["configuration"] == {"lanes": 8, "banks": 8}
    execution = record["execution"]
    assert execution["outputs"] == OUTPUTS
    assert execution["cycles"] == CYCLES
    assert execution["scheduleSize"] == SCHEDULE_SIZE
    assert execution["counters"] == counters(8, 8)
    assert execution["traceCaptured"] is False
    assert execution["storage"] == {
        "inputSlots": 512, "outputSlots": 256, "scratchSlots": 0,
        "declaredSlots": 768, "declaredBytes": 6144,
    }
    assert execution["resources"] == {
        "dspSlices": 8, "bram36Blocks": 16, "logicalMemoryBits": 262144,
        "slotsPerBank": 512, "generalPurposePortsPerBank": 2,
        "writableArchitecturalRegisterBits": 8 * 15 * 48, "pendingInstructionSlots": 24,
        "controlArea": None, "connectionArea": None, "pipelineArea": None,
        "totalLogicArea": None, "logicAreaStatus": "uncalibrated",
    }
    objective = record["objective"]
    assert objective["direction"] == "minimize"
    assert all(term["cost"] == term["quantity"] * term["coefficient"] for term in objective["breakdown"])
    assert sum(term["cost"] for term in objective["breakdown"]) == objective["score"]
assert latency["objective"] == {
    "identifier": "latency-v1", "unit": "cycles", "direction": "minimize",
    "coefficients": None, "score": CYCLES,
    "breakdown": [{"label": "elapsed cycles", "quantity": CYCLES, "coefficient": 1, "cost": CYCLES}],
}
objective = energy["objective"]
assert objective["identifier"] == "energy-proxy-v1"
assert objective["unit"] == "abstract energy units"
assert objective["coefficients"] == {"identifier": "energy-coefficients-v1", "values": COEFFICIENTS}
counts = counters(8, 8)
quantities = [CYCLES, CYCLES * 8, CYCLES * 16] + [counts[key] for key in (
    "loads", "stores", "additions", "multiplications", "multiplyAdds", "registerReads", "registerWrites"
)]
assert [term["quantity"] for term in objective["breakdown"]] == quantities
assert [term["coefficient"] for term in objective["breakdown"]] == list(COEFFICIENTS.values())
expected_score = sum(q * c for q, c in zip(quantities, COEFFICIENTS.values()))
assert objective["score"] == expected_score == 954087
print("PASS: 19 matmul reports, independent runtime inputs/products, all counters/configurations, and 34303/954087 scores")
