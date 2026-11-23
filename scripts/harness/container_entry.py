"""Executed only inside the generator container."""
import contextlib
import json
from pathlib import Path
import random
import runpy
import sys

sys.path.insert(0, '/input')
random.seed(json.loads(Path('/input/randomness.json').read_text())['attemptSeed'])
with contextlib.redirect_stdout(sys.stderr):
    module = runpy.run_path('/input/generator.py')
    candidate = module['build']()
json.dump(candidate, sys.stdout, allow_nan=False)
sys.stdout.write('\n')
