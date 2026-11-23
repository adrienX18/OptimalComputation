#!/usr/bin/env python3
"""Full local validation; optional argument is a frozen relative-path SHA-256 map."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

if not __debug__:
    raise SystemExit("Validation requires Python assertions. Unset PYTHONOPTIMIZE and omit -O/-OO.")

ROOT = Path(__file__).resolve().parents[1]


def command(*args, capture=False):
    print("RUN:", " ".join(args), flush=True)
    return subprocess.run(args, cwd=ROOT, check=True, capture_output=capture).stdout


command("lake", "build")
command("lake", "test")
command("python3", "scripts/check-cli.py")
command("python3", "scripts/check-experiments.py")
command("python3", "scripts/check-section9-results.py")
command("lake", "env", "lean", "scripts/check-doc-examples.lean")

for name, count in [("verification", 48), ("matvec", 65), ("objectives", 26), ("matmul", 34),
                    ("naive-v2", 32), ("section9", 14)]:
    output = command("lake", "env", "lean", f"scripts/audit-{name}.lean", capture=True).decode()
    declarations = re.findall(r"'[^']+' (?:does not depend on any axioms|depends on axioms:)", output)
    assert len(declarations) == count, (name, len(declarations), output)
    for group in re.findall(r"depends on axioms:\s*\[([^]]*)\]", output, re.S):
        assert set(group.replace("\n", " ").replace(" ", "").split(",")) <= {
            "propext", "Quot.sound", "Classical.choice"}, (name, group)
    assert "sorryAx" not in output, output
    print(f"PASS: {name} audit, {count} declarations, standard axioms only", flush=True)

for script, result in [
    ("matvec", "matvec-naive-v1.json"),
    ("matvec-configurations", "matvec-naive-v1-configurations.json"),
    ("serial-dot-trace", "serial-dot-two-term-v1.txt"),
    ("matvec-objectives", "matvec-naive-v1-objectives.json"),
    ("product-pair-objectives", "product-pair-v1-objectives.json"),
    ("matmul", "matmul-naive-v1.json"),
    ("matmul-configurations", "matmul-naive-v1-configurations.json"),
    ("matmul-objectives", "matmul-naive-v1-objectives.json"),
    ("matvec-v2-objectives", "matvec-naive-v2-objectives.json"),
    ("matmul-v2-objectives", "matmul-naive-v2-objectives.json"),
]:
    output = command("lake", "env", "lean", f"scripts/reproduce-{script}.lean", capture=True)
    assert output == (ROOT / "docs/results" / result).read_bytes(), result
    print(f"PASS: byte-identical {result}", flush=True)

command("python3", "scripts/check-objective-results.py")
command("python3", "scripts/check-matmul-results.py")
command("git", "diff", "--check")
files = command("git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", capture=True)
text_count = 0
for relative in sorted(set(files.decode().split("\0")) - {""}):
    path = ROOT / relative
    data = path.read_bytes()
    if b"\0" in data:
        continue
    text = data.decode("utf-8")
    assert not data or data.endswith(b"\n"), f"Missing final newline: {relative}"
    assert "\t" not in text, f"Tab: {relative}"
    assert all(line == line.rstrip() for line in text.splitlines()), f"Trailing whitespace: {relative}"
    if path.suffix == ".lean":
        forbidden = (r"\b(sorry|admit|native_decide)\b|^\s*(?:private\s+)?(?:axiom|unsafe)\b|"
                     r"@\[.*(?:implemented_by|extern)|set_option\s+(?:debug\.|kernel\.)")
        assert not re.search(forbidden, text, re.M), f"Forbidden proof/source shortcut: {relative}"
    text_count += 1
print(f"PASS: {text_count} tracked/untracked text files, whitespace and Lean source checks", flush=True)

if len(sys.argv) > 1:
    frozen = json.loads(Path(sys.argv[1]).read_text())
    for relative, expected in frozen.items():
        assert hashlib.sha256((ROOT / relative).read_bytes()).hexdigest() == expected, relative
    print(f"PASS: {len(frozen)} frozen source/artifact hashes", flush=True)
print("PASS: full validation", flush=True)
