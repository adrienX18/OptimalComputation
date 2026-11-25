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


def marked_table(text, name):
    marker = f'<!-- derived-table {name} -->\n'
    require(text.count(marker) == 1, f'Missing/duplicate derived table: {name}')
    return text.split(marker, 1)[1].split('\n\n', 1)[0]


def check_failure_walkthrough(text):
    values = saved('docs/results/section9-v1/held-out-polynomial.json')
    coefficients, points = values[:8], values[8:]
    require(points == [-4] * 16, 'Changed Horner counterexample')
    accumulator = coefficients[-1]
    rows = marked_table(text, 'horner-values')
    tick = chr(96)
    for step, k in enumerate(range(6, -1, -1)):
        result = accumulator * points[0] + coefficients[k]
        row = f'| {tick}c{k} = {coefficients[k]}{tick} | {3+3*step} | {accumulator:,} | {result:,} |'
        require(row in rows, f'Horner calculation differs: {row}')
        if k > 0:
            require(-32768 <= accumulator <= 32767, 'Earlier Horner multiplicand is invalid')
        else:
            require(accumulator == -42596, 'Final Horner counterexample differs')
        accumulator = result
    powers = [x**5+x**6 for x in range(-4, 4)]
    exact = [c * v for c in range(-8, 8) for v in powers]
    require(powers == [3072, 486, 32, 0, 0, 2, 96, 972], 'Power table differs')
    require((min(exact), max(exact)) == (-24576, 21504), 'Exact safe range differs')
    require('[3072,486,32,0,0,2,96,972]' in text and '[-24576,21504]' in text,
            'Guide exact-range explanation differs')
    def multiply(a, b):
        endpoints = [x*y for x in a for y in b]
        return min(endpoints), max(endpoints)
    first = multiply((-8, 7), (-1024, 768))
    second = multiply((-8, 7), (0, 4096))
    bound = (first[0]+second[0], first[1]+second[1])
    require(bound == (-39936, 36864) and '[-39936,36864]' in text, 'Conservative range differs')
    rows = marked_table(text, 'conservative-suffix')
    operations = [('r1 ← load c0', 'c0'), ('r2 ← load x0', 'x0'),
                  ('r3 ← r2*r2', 'x0²'), ('r4 ← r3*r3', 'x0⁴'),
                  ('r5 ← r4*r2', 'x0⁵'), ('r6 ← r4*r3', 'x0⁶'),
                  ('r7 ← r5+r6', 'x0⁵+x0⁶'), ('r8 ← r1*r7', 'c0*(x0⁵+x0⁶)'),
                  ('r9 ← r8*r0', '0')]
    for i, (operation, value) in enumerate(operations):
        require(f'| {40+4*i} | {tick}{operation}{tick} | {tick}{value}{tick} |' in rows,
                f'Conservative suffix row differs: {i}')


def check_energy_walkthrough(text):
    records = saved('docs/results/product-pair-v1-objectives.json')
    energy = [r for r in records if r['objective']['identifier'] == 'energy-proxy-v1']
    require(len(energy) == 2, 'Missing pair energy records')
    results = []
    for record in energy:
        execution, config = record['execution'], record['configuration']
        counters, resources = execution['counters'], execution['resources']
        terms = [execution['cycles'], execution['cycles']*config['lanes'],
                 execution['cycles']*resources['bram36Blocks'], 4*counters['loads'],
                 4*counters['stores'], 8*counters['multiplications'],
                 counters['registerReads'], counters['registerWrites']]
        require(counters['additions'] == counters['multiplyAdds'] == 0, 'Unexpected pair operations')
        require(sum(terms) == record['objective']['score'], 'Pair energy formula differs')
        require(execution['outputs'] == [-42, -15], 'Pair outputs differ')
        results.append(terms)
    require(results == [[12,12,96,16,8,16,6,6], [6,48,96,16,8,16,6,6]], 'Pair breakdown differs')
    rows = marked_table(text, 'pair-energy')
    for row in ['| Base duration | `12*1 = 12` | `6*1 = 6` |',
                '| Provisioned lane duration | `12*1 = 12` | `6*8 = 48` |',
                '| Allocated BRAM36 duration | `12*8 = 96` | `6*16 = 96` |',
                '| Four loads | 16 | 16 |', '| Two stores | 8 | 8 |',
                '| Two multiplies | 16 | 16 |', '| Six register reads | 6 | 6 |',
                '| Six register writes | 6 | 6 |', '| **Total energy proxy** | **172** | **202** |',
                '| **Latency** | **12 cycles** | **6 cycles** |']:
        require(row in rows, f'Pair energy table differs: {row}')
    rows = marked_table(text, 'polynomial-energy')
    runs = [r for r in table('analysis/2026-11-23-suite-smoke/runs.csv')
            if r['task'] == 'polynomial' and r['objective'] == 'energy-proxy-v1']
    require(len(runs) == 5, 'Unexpected polynomial energy loops')
    for run in runs:
        row = f"| {run['model']} | {run['winner_lanes']} | {run['winner_banks']} | {int(run['best_score']):,} |"
        require(row in rows, f'Smoke energy row differs: {row}')


def check_scheduler_walkthrough(text):
    raw = saved('analysis/2026-11-23-five-model-search/walkthrough/winner/candidate.json')
    nodes = [('load', ()) for _ in range(8)]
    def node(kind, *deps):
        index = len(nodes)
        nodes.append((kind, deps))
        return index
    input_nodes = dict(enumerate(range(8)))
    outputs = {}
    for logical in (0, 8):
        x = node('load')
        input_nodes[8+logical] = x
        q = 7
        for k in range(6, 1, -1):
            q = node('multiplyAdd', q, x, k)
        square = node('multiply', x, x)
        low = node('multiplyAdd', 1, x, 0)
        outputs[logical] = node('multiplyAdd', q, square, low)
    uses = Counter(dep for _, deps in nodes for dep in deps)
    uses.update(outputs.values())
    registers, node_registers, ready, found = {}, {}, {}, {}
    free = set(range(1, 16))
    for entry in raw['schedule']:
        if entry['lane'] != 0:
            continue
        t, op = entry['cycle'], entry['instruction']
        if op['kind'] == 'store':
            logical = raw['layout']['outputs'].index(op['address'])
            value = registers[op['source']]
            require(value == outputs[logical] and ready[value] <= t, 'Output node/store differs')
            uses[value] -= 1
            found[t] = ('store', logical, op['source'], op['address'])
            continue
        if op['kind'] == 'load':
            logical = raw['layout']['inputs'].index(op['address'])
            current = input_nodes[logical]
            deps = ()
        else:
            operands = [op['left'], op['right']]
            if op['kind'] == 'multiplyAdd':
                operands.append(op['accumulator'])
            deps = tuple(registers[r] for r in operands)
            matches = [i for i, n in enumerate(nodes) if n == (op['kind'], deps)]
            require(len(matches) == 1, 'Ambiguous/missing graph node')
            current = matches[0]
        require(current not in ready, 'Node emitted more than once')
        for dependency in deps:
            require(ready[dependency] <= t, 'Scheduler explanation reads a pending node')
            uses[dependency] -= 1
            if uses[dependency] == 0:
                free.add(node_registers[dependency])
        destination = op['destination']
        require(destination == min(free), 'Last-use register allocation differs')
        free.remove(destination)
        registers[destination] = current
        node_registers[current] = destination
        ready[current] = t + (1 if op['kind'] == 'load' else 3)
        found[t] = (current, destination, ready[current])
    require(len(ready) == 26 and not any(uses.values()), 'Graph/last-use coverage differs')
    early = marked_table(text, 'scheduler-early')
    descriptions = {4:'r5 ← load x8', 5:'r6 ← c7*x8+c6', 6:'r7 ← load x0',
                    7:'r1 ← c7*x0+c6', 8:'r4 ← load c3', 9:'r6 ← r6*x8+c5'}
    tick = chr(96)
    for t, description in descriptions.items():
        current, _, due = found[t]
        require(f'| {t} | {current} | {tick}{description}{tick} | {due} |' in early,
                f'Scheduler early row differs: {t}')
    require({t:found[t] for t in (20,21,22,23,25,26,28,29)} == {
        20:(15,4,23), 21:(22,6,24), 22:(13,1,25), 23:(24,2,26),
        25:(16,1,28), 26:(25,2,29), 28:('store',0,1,24), 29:('store',8,2,32)},
        'Tail dependencies/registers differ')
    tail = marked_table(text, 'scheduler-tail')
    tail_ops = {20:'`r4 ← c1*x0+c0`',
                21:'`r6 ← q8*x8+c2` (finishes the short Horner chain)',
                22:'`r1 ← q0*x0+c2` (finishes the short Horner chain)',
                23:'`r2 ← c1*x8+c0`', 25:'`r1 ← r1*x0²+r4`',
                26:'`r2 ← r6*x8²+r2`', 28:'`mem[24] ← r1` (`y0`)',
                29:'`mem[32] ← r2` (`y8`)'}
    for t, description in tail_ops.items():
        due = t+(1 if t >= 28 else 3)
        require(f'| {t} | {description} | {due} |' in tail, f'Scheduler tail row differs: {t}')
    rows = marked_table(text, 'coefficient-pairs')
    for lane in range(0, 8, 2):
        loads = [e for e in raw['schedule'] if e['lane'] in (lane,lane+1)
                 and e['instruction']['kind'] == 'load' and e['instruction']['address'] == 7]
        require(len(loads) == 2 and loads[0]['cycle'] == loads[1]['cycle'], 'Coefficient pair differs')
        require(f"| {lane} and {lane+1} | {loads[0]['cycle']} | `7 / 7` | 2 |" in rows,
                'Coefficient-pair table differs')
    for t in (28,29):
        stores = [e for e in raw['schedule'] if e['cycle'] == t and e['instruction']['kind'] == 'store']
        require(sorted(e['instruction']['address'] % 8 for e in stores) == list(range(8)),
                'Final stores do not use each bank once')


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
    check_failure_walkthrough(text)
    check_energy_walkthrough(text)
    check_scheduler_walkthrough(text)
    print(f"PASS: {counts['source-excerpt']} exact source excerpts and {counts['json-string']} decoded JSON strings")
    print(f"PASS: {links} links and complete coverage of {core} core source/config/root files")
    print("PASS: four frozen walkthroughs, response/code/hash/count bindings, lane 0 table, and both aggregate studies")
    print("PASS: failure calculations, energy breakdowns, and scheduler node/register explanations")
    print("This is an offline documentation/data check, not a new Lean certificate or full raw-archive audit.")


if __name__ == "__main__":
    main()
