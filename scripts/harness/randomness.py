"""Stable search seeds, independent of process order and Python's hash seed."""
import hashlib


def attempt_seed(run_seed, attempt):
    payload = f'naive-search-seed-v1:{run_seed}:{attempt}'.encode('ascii')
    return int.from_bytes(hashlib.sha256(payload).digest()[:4], 'big') & 0x7fffffff
