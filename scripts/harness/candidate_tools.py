"""Tiny helpers available to generators. These build data, not proofs."""
import json
from pathlib import Path


def baseline():
    """Return a fresh copy of this run's original certified candidate."""
    return json.loads(Path('/input/baseline.json').read_text())


def load(destination, address):
    return dict(kind='load', destination=destination, address=address)


def store(source, address):
    return dict(kind='store', source=source, address=address)


def add(destination, left, right):
    return dict(kind='add', destination=destination, left=left, right=right)


def mul(destination, left, right):
    return dict(kind='multiply', destination=destination, left=left, right=right)


def mac(destination, left, right, accumulator):
    return dict(kind='multiplyAdd', destination=destination, left=left, right=right, accumulator=accumulator)


def issue(cycle, lane, instruction):
    return dict(cycle=cycle, lane=lane, instruction=instruction)


def serial(instructions, lane=0, start=0):
    """Issue each instruction at its predecessor's completion boundary."""
    schedule = []
    for instruction in instructions:
        schedule.append(issue(start, lane, instruction))
        start += 1 if instruction['kind'] in ('load', 'store') else 3
    return schedule
