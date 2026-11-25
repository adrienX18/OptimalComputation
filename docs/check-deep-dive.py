#!/usr/bin/env python3
"""Check DEEP_DIVE quotations, links, coverage and frozen evidence, offline.

This checks documentation against Git objects and saved data. It does not run
generated Python, call a model, or substitute for checking a Lean certificate.
Kept in docs/ so adding this check does not change the search source fingerprint.
"""
from collections import Counter
import csv
from functools import lru_cache
import hashlib
import io
import json
from pathlib import Path
import re
import statistics
import subprocess
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]
REVISION = "71c608a2b573c322993264945dbb2be8a9e5006f"
REPOSITORY = "adrienX18/OptimalComputation"
GUIDE = ROOT / "DEEP_DIVE.md"


def require(condition, message):
    if not condition:
        raise ValueError(message)


@lru_cache(maxsize=None)
def blob(revision, path):
    require(re.fullmatch(r"[0-9a-f]{40}", revision), f"Unpinned revision: {revision}")
    require(not path.startswith("/") and ".." not in Path(path).parts, f"Invalid path: {path}")
    return subprocess.check_output(["git", "show", f"{revision}:{path}"], cwd=ROOT)


def saved(path):
    return json.loads(blob(REVISION, path))


def table(path):
    return list(csv.DictReader(io.StringIO(blob(REVISION, path).decode())))


def sha(data):
    return hashlib.sha256(data).hexdigest()


def check_excerpts(text):
    pattern = re.compile(
        r"<!-- (source-excerpt|json-string) (\{[^\n]+\}) -->\n"
        r"```[^\n]*\n(.*?)\n```", re.S)
    counts = Counter()
    for match in pattern.finditer(text):
        kind, encoded, actual = match.groups()
        meta = json.loads(encoded)
        require(meta["commit"] == REVISION, f"Unexpected excerpt revision: {meta}")
        raw = blob(meta["commit"], meta["path"])
        if kind == "source-excerpt":
            lines = raw.decode().splitlines(keepends=True)
            require(1 <= meta["start"] <= meta["end"] <= len(lines), f"Invalid range: {meta}")
            expected = "".join(lines[meta["start"] - 1:meta["end"]])
            # The closing fence needs a separator newline even if the source's
            # final line has no newline. No indentation/content is normalized.
            if expected.endswith("\n"):
                expected = expected[:-1]
            prefix = text[:match.start()].rstrip("\n").rsplit("\n\n", 1)[-1]
            target = (f"https://github.com/{REPOSITORY}/blob/{REVISION}/"
                      f"{meta['path']}#L{meta['start']}")
            if meta["end"] != meta["start"]:
                target += f"-L{meta['end']}"
            require(f"]({target})" in prefix, f"Excerpt Source link differs from metadata: {meta}")
        else:
            expected = json.loads(raw)
            if "decodePointer" in meta:
                for component in meta["decodePointer"].strip("/").split("/"):
                    expected = expected[int(component)] if isinstance(expected, list) else expected[component]
                expected = json.loads(expected)
            for component in meta["pointer"].strip("/").split("/"):
                key = component.replace("~1", "/").replace("~0", "~")
                expected = expected[int(key)] if isinstance(expected, list) else expected[key]
            require(isinstance(expected, str), f"JSON pointer is not a string: {meta}")
            if expected.endswith("\n"):
                expected = expected[:-1]
        require(actual == expected, f"Changed {kind}: {meta}")
        counts[kind] += 1
    for kind in ("source-excerpt", "json-string"):
        require(counts[kind] == text.count(f"<!-- {kind} "), f"Unparsed {kind} block")
    require(counts["source-excerpt"] > 0, "No checked source quotations found")
    return counts


def check_links_and_coverage(text):
    # Strip fenced content: a copied program/prompt is not document navigation.
    prose = re.sub(r"^```[^\n]*\n.*?^```[ \t]*$", "", text, flags=re.M | re.S)
    targets = re.findall(r"!?\[[^\]\n]*\]\(([^)\n]+)\)", prose)
    anchors = set(re.findall(r'<a id="([^"]+)"', prose))
    tracked = set(subprocess.check_output(
        ["git", "ls-tree", "-r", "--name-only", REVISION], cwd=ROOT, text=True).splitlines())
    covered = set()
    for target in targets:
        url = urlsplit(target)
        if url.scheme:
            require(url.scheme == "https", f"Unexpected URL scheme: {target}")
            require(url.netloc == "github.com", f"Unexpected external link: {target}")
            prefix = f"/{REPOSITORY}/"
            require(url.path.startswith(prefix), f"Different repository: {target}")
            parts = url.path[len(prefix):].split("/", 2)
            require(len(parts) >= 2 and parts[0] in ("blob", "tree"), f"Unverified URL: {target}")
            kind, revision = parts[:2]
            path = unquote(parts[2]).rstrip("/") if len(parts) == 3 else ""
            require(revision == REVISION, f"Moving or unexpected link revision: {target}")
            if kind == "tree":
                require(not path or any(p.startswith(path + "/") for p in tracked), f"Missing tree: {target}")
            else:
                require(path in tracked, f"Missing pinned file: {target}")
                covered.add(path)
                if url.fragment:
                    match = re.fullmatch(r"L(\d+)(?:-L(\d+))?", url.fragment)
                    require(match is not None, f"Unrecognized line anchor: {target}")
                    start, end = int(match[1]), int(match[2] or match[1])
                    require(1 <= start <= end <= len(blob(revision, path).splitlines()),
                            f"Line anchor out of bounds: {target}")
        elif not url.path:
            require(url.fragment in anchors, f"Missing local anchor: {target}")
        else:
            require((ROOT / unquote(url.path)).is_file(), f"Missing local file/image: {target}")
    core = {p for p in tracked if p.startswith(("OptimalComputation/", "scripts/", "configs/"))}
    core |= {p for p in tracked if "/" not in p}
    require(core <= covered, f"Core files missing from atlas/links: {sorted(core - covered)}")
    require(prose.count("<details>") == prose.count("</details>"), "Unbalanced details blocks")
    require(len(re.findall(r"^```", text, re.M)) % 2 == 0, "Unbalanced code fences")
    # Syntax-check Python recipes without executing generators or any commands.
    for index, code in enumerate(re.findall(r"<<'PY'\n(.*?)^PY$", text, re.M | re.S), 1):
        compile(code, f"DEEP_DIVE Python recipe {index}", "exec")
    return len(targets), len(core)


def check_walkthrough(path, text):
    provenance = saved(path + "/provenance.json")
    for row in provenance["files"]:
        data = blob(REVISION, path + "/" + row["file"])
        require(len(data) == row["bytes"] and sha(data) == row["sha256"], f"Provenance mismatch: {path}/{row['file']}")
    proposal = saved(path + "/winner/proposal.json")
    response = saved(path + "/winner/response.json")
    content = response["choices"][0]["message"]["content"].strip()
    if content.startswith("```json\n") and content.endswith("```"):
        content = content[8:-3]
    require(json.loads(content) == proposal, f"Response/proposal mismatch: {path}")
    require(proposal["code"].encode() == blob(REVISION, path + "/winner/generator.py"), f"Generator differs from response: {path}")
    architecture = saved(path + "/architecture.json")
    for which in ("baseline", "winner"):
        raw = saved(path + f"/{which}/candidate.json")
        score = saved(path + f"/{which}/score.json")
        counts = Counter(i["instruction"]["kind"] for i in raw["schedule"])
        lanes = Counter(i["lane"] for i in raw["schedule"])
        cycles = max(i["cycle"] + (1 if i["instruction"]["kind"] in ("load", "store") else 3)
                     for i in raw["schedule"])
        recorded = architecture[which]
        require(dict(counts) == recorded["counts"], f"Opcode counts differ: {path}/{which}")
        require(len(raw["schedule"]) == recorded["instructions"] == score["execution"]["scheduleSize"],
                f"Instruction count differs: {path}/{which}")
        require(cycles == recorded["cycles"] == score["execution"]["cycles"] == score["objective"]["score"],
                f"Completion/latency differs: {path}/{which}")
        require(score["objective"]["identifier"] == "latency-v1", f"Unexpected objective: {path}")
        require([lanes[i] for i in range(raw["configuration"]["lanes"])] == recorded["lane_issues"],
                f"Lane counts differ: {path}/{which}")
        require(len(raw["layout"]["scratch"]) == recorded["scratch_slots"], f"Scratch count differs: {path}")
        for opcode, counter in (("load", "loads"), ("store", "stores"), ("add", "additions"),
                                ("multiply", "multiplications"), ("multiplyAdd", "multiplyAdds")):
            require(counts[opcode] == score["execution"]["counters"][counter], f"Counter differs: {path}/{counter}")
    certificate = saved(path + "/winner/certification/result.json")
    require(certificate["accepted"], f"Certificate record rejected: {path}")
    require(certificate["candidateSha256"] == sha(blob(REVISION, path + "/winner/candidate.json")),
            f"Candidate binding differs: {path}")
    require(saved(path + "/winner/certification/kernel/result.json")["exitCode"] == 0,
            f"Recorded kernel exit failed: {path}")
    require(certificate["score"] == saved(path + "/winner/score.json"), f"Score binding differs: {path}")
    if "five-model" not in path:
        b, w = architecture["baseline"], architecture["winner"]
        for label, left, right in [("Cycles", b["cycles"], w["cycles"]),
                                   ("Instructions", b["instructions"], w["instructions"]),
                                   ("Loads", b["counts"].get("load", 0), w["counts"].get("load", 0)),
                                   ("Stores", b["counts"].get("store", 0), w["counts"].get("store", 0)),
                                   ("Multiplies", b["counts"].get("multiply", 0), w["counts"].get("multiply", 0)),
                                   ("Multiply-adds", b["counts"].get("multiplyAdd", 0), w["counts"].get("multiplyAdd", 0)),
                                   ("Adds", b["counts"].get("add", 0), w["counts"].get("add", 0)),
                                   ("Scratch slots", b["scratch_slots"], w["scratch_slots"])]:
            require(f"| {label} | {left:,} | {right:,} |" in text, f"Guide comparison table differs: {path}/{label}")


def check_aggregates(text):
    poly = "analysis/2026-11-23-five-model-search/"
    metrics, runs, attempts = saved(poly + "metrics.json"), table(poly + "runs.csv"), table(poly + "attempts.csv")
    require(len(runs) == metrics["runs"] == 25 and len(attempts) == metrics["attempts"] == 1250, "Polynomial study size differs")
    require(Counter(a["category"] for a in attempts) == metrics["categories"], "Polynomial outcomes differ")
    require(sum(int(r["bestFirstAttempt"]) <= 10 for r in runs) == metrics["runsBestBy10"] == 23, "Early-best count differs")
    for model, values in metrics["models"].items():
        selected = sorted((r for r in runs if r["model"] == model), key=lambda r: int(r["seed"]))
        scores = [int(r["bestCycles"]) for r in selected]
        require(scores == values["finalBests"] and statistics.median(scores) == values["medianBest"], f"Final bests differ: {model}")
        require(f"| {model} | {', '.join(map(str, scores))} | {values['medianBest']} |" in text, f"Guide final-best table differs: {model}")
    smoke = "analysis/2026-11-23-suite-smoke/"
    metrics, runs, attempts = saved(smoke + "metrics.json"), table(smoke + "runs.csv"), table(smoke + "attempts.csv")
    require(len(runs) == 80 and len(attempts) == 240, "Smoke study size differs")
    require(Counter(a["category"] for a in attempts) == metrics["audit"]["categories"], "Smoke categories differ")
    require(Counter(a["outcome"] for a in attempts) == metrics["outcomes"], "Smoke outcomes differ")
    require(sum(int(r["best_score"]) < int(r["baseline"]) for r in runs) == metrics["improved_loops"] == 77, "Improved loops differ")
    require(sum(int(r["first_final_best"]) == 3 for r in runs) == metrics["last_slot_improved_loops"] == 35, "Last-slot count differs")
    for name, expected in metrics["source_tables"].items():
        require(sha(blob(REVISION, smoke + name)) == expected, f"Smoke table hash differs: {name}")


def check_lane_table(text):
    path = "analysis/2026-11-23-five-model-search/walkthrough/winner/candidate.json"
    section = text.split("### 8.5 ", 1)[1].split("### 8.6 ", 1)[0]
    rows = re.findall(r"^\| \[(\d+)\]\([^)]+\) \| (\d+) \| `([^`]+)` \| (\d+|—) \|$", section, re.M)
    entries = [entry for entry in saved(path)["schedule"] if entry["lane"] == 0]
    require(len(rows) == len(entries), "Lane 0 table omits or adds instructions")
    for row, entry in zip(rows, entries):
        cycle, due, expression, bank = row
        op = entry["instruction"]
        kind = op["kind"]
        latency = 1 if kind in ("load", "store") else 3
        require(int(cycle) == entry["cycle"] and int(due) == entry["cycle"] + latency,
                f"Lane 0 issue/completion differs: {row}")
        require(bank == (str(op["address"] % 8) if "address" in op else "—"), f"Lane 0 bank differs: {row}")
        if kind == "load":
            expected = f"r{op['destination']} ← mem[{op['address']}]"
        elif kind == "store":
            expected = f"mem[{op['address']}] ← r{op['source']}"
        elif kind == "multiplyAdd":
            expected = f"r{op['destination']} ← r{op['accumulator']} + r{op['left']} × r{op['right']}"
        else:
            operator = "×" if kind == "multiply" else "+"
            expected = f"r{op['destination']} ← r{op['left']} {operator} r{op['right']}"
        require(expression == expected, f"Lane 0 operands differ: {row}")


def main():
    text = GUIDE.read_text()
    counts = check_excerpts(text)
    links, core = check_links_and_coverage(text)
    for path in ("analysis/2026-11-23-five-model-search/walkthrough",
                 "analysis/2026-11-23-suite-smoke/walkthrough",
                 "analysis/2026-11-23-suite-smoke/architectures/matmul",
                 "analysis/2026-11-23-suite-smoke/architectures/two-stage"):
        check_walkthrough(path, text)
    check_aggregates(text)
    check_lane_table(text)
    print(f"PASS: {counts['source-excerpt']} exact source excerpts and {counts['json-string']} decoded JSON strings")
    print(f"PASS: {links} links and complete coverage of {core} core source/config/root files")
    print("PASS: four frozen walkthroughs, response/code/hash/count bindings, lane 0 table, and both aggregate studies")
    print("This is an offline documentation/data check, not a new Lean certificate or full raw-archive audit.")


if __name__ == "__main__":
    main()
