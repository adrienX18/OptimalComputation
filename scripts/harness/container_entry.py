"""Executed only inside the generator container."""
import contextlib
import json
import runpy
import sys

sys.path.insert(0, '/input')
with contextlib.redirect_stdout(sys.stderr):
    module = runpy.run_path('/input/generator.py')
    candidate = module['build']()
json.dump(candidate, sys.stdout, allow_nan=False)
sys.stdout.write('\n')
