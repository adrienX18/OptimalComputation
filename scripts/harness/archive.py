"""Durable files and fully captured subprocesses; no model or scoring logic."""
import json
import gzip
import hashlib
from contextlib import suppress
import os
from pathlib import Path
import signal
import subprocess
import time


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.tmp')
    with temporary.open('w', encoding='utf-8') as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2, allow_nan=False)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)


def read_json(path):
    return json.loads(Path(path).read_text())


def compress_trace(path):
    """Keep a lossless, verified gzip trace instead of two large copies."""
    path = Path(path)
    packed = path.with_suffix(path.suffix + '.gz')
    temporary = packed.with_suffix(packed.suffix + '.tmp')
    digest = hashlib.sha256()
    size = 0
    with path.open('rb') as source, temporary.open('wb') as target:
        with gzip.GzipFile(fileobj=target, mode='wb', filename='', mtime=0) as gz:
            for chunk in iter(lambda: source.read(1024*1024), b''):
                gz.write(chunk)
                digest.update(chunk)
                size += len(chunk)
        target.flush()
        os.fsync(target.fileno())
    restored = hashlib.sha256()
    restored_size = 0
    with gzip.open(temporary, 'rb') as source:
        for chunk in iter(lambda: source.read(1024*1024), b''):
            restored.update(chunk)
            restored_size += len(chunk)
    if restored_size != size or restored.digest() != digest.digest():
        raise OSError('Trace compression failed its round-trip integrity check.')
    os.replace(temporary, packed)
    write_json(path.with_suffix('.metadata.json'), dict(format='gzip', file=packed.name,
               originalBytes=size, originalSha256=digest.hexdigest()))
    path.unlink()  # Only after verified compression and durable metadata.


def event(root, kind, **values):
    with (Path(root) / 'events.jsonl').open('a', encoding='utf-8') as stream:
        stream.write(json.dumps(dict(time=time.time(), event=kind, **values), ensure_ascii=False) + '\n')
        stream.flush()
        os.fsync(stream.fileno())


def command(args, directory, *, cwd, timeout=120, output_limit=64 * 1024 * 1024, env=None, cancel=None):
    """Keep the complete output produced before completion or an explicit limit.

    Each invocation gets a new directory, including failed/interrupting invocations.
    Limits terminate the process group; reaching one is recorded, never hidden.
    """
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=False)
    started = time.time()
    write_json(directory / 'request.json', dict(args=list(map(str, args)), cwd=str(cwd),
               timeout=timeout, outputLimitBytes=output_limit, started=started))
    status, code = 'completed', None
    process = None
    try:
        with (directory / 'stdout.txt').open('wb') as stdout, (directory / 'stderr.txt').open('wb') as stderr:
            process = subprocess.Popen(list(map(str, args)), cwd=cwd, env=env,
                                       stdout=stdout, stderr=stderr, start_new_session=True)
            deadline = time.monotonic() + timeout
            while process.poll() is None:
                if cancel is not None and cancel.is_set():
                    status = 'interrupted'
                    with suppress(ProcessLookupError):
                        os.killpg(process.pid, signal.SIGINT)
                    with suppress(subprocess.TimeoutExpired):
                        process.wait(timeout=5)
                    break
                if time.monotonic() >= deadline:
                    status = 'timeout'
                    break
                if os.fstat(stdout.fileno()).st_size + os.fstat(stderr.fileno()).st_size > output_limit:
                    status = 'output-limit'
                    break
                time.sleep(.02)
            if status != 'completed':
                with suppress(ProcessLookupError):
                    os.killpg(process.pid, signal.SIGKILL)
            code = process.wait()
            # A fast process can exceed the limit between polls.
            if os.fstat(stdout.fileno()).st_size + os.fstat(stderr.fileno()).st_size > output_limit:
                status = 'output-limit'
    except OSError as exc:
        status = 'launch-error'
        write_json(directory / 'error.json', dict(type=type(exc).__name__, message=str(exc)))
    except BaseException:
        status = 'interrupted'
        raise
    finally:
        if process is not None and process.poll() is None:
            with suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGKILL)
            code = process.wait()
        result = dict(status=status, exitCode=code, seconds=time.time()-started)
        write_json(directory / 'result.json', result)
    return result


def output(directory, stream='stdout'):
    return (Path(directory) / f'{stream}.txt').read_text(encoding='utf-8', errors='replace')
