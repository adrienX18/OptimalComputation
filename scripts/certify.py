#!/usr/bin/env python3
"""Certify one candidate, without searching or changing its schedule.

The compiled checker emits a closed Lean obligation. Only a successful kernel
check and standard-axiom audit produce acceptance. No third-party Python packages.
"""
import argparse
from contextlib import contextmanager, nullcontext
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
CHECKER = ROOT / '.lake/build/bin/certification_check'
ALLOWED_AXIOMS = {'propext', 'Quot.sound', 'Classical.choice'}
MAX_FILE_BYTES = 8 * 1024 * 1024


@contextmanager
def kernel_slot(archive=None):
    """One memory-heavy kernel process per checkout; model calls stay parallel.

    OS file locks work across both batch processes and integration-test threads,
    and release automatically if a worker dies. Queue time is recorded separately
    from the active checking budget.
    """
    from harness.archive import write_json
    started = time.time()
    with (ROOT / '.lake/certification-kernel.lock').open('a') as lock:
        if archive is not None:
            write_json(archive / 'kernel-queue.json', dict(started=started, status='waiting'))
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            if archive is not None:
                write_json(archive / 'kernel-queue.json',
                           dict(started=started, status='acquired', acquired=time.time(),
                                waitSeconds=time.time()-started))
            yield
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


def failure(category, message, **details):
    return dict(recordVersion='certification-result-v1', accepted=False,
                status='not-certified', category=category, message=message, details=details)


def audit_kernel_output(output, namespace="GeneratedCertificate"):
    """Require all three declarations, not just absence of a forbidden axiom."""
    matches = re.findall(
        rf"'{re.escape(namespace)}\.(checked|artifact|exactBinding)' "
        r"(does not depend on any axioms|depends on axioms:\s*\[([^]]*)\])", output, re.S)
    if len(matches) != 3 or {m[0] for m in matches} != {'checked', 'artifact', 'exactBinding'}:
        return False
    return all(not m[2] or set(re.sub(r'\s+', '', m[2]).split(',')) <= ALLOWED_AXIOMS
               for m in matches)


def run_process(args, timeout, archive=None):
    if archive is not None:
        from harness.archive import command, output
        result = command(args, archive, cwd=ROOT, timeout=timeout)
        if result["status"] != "completed":
            if result["status"] == "timeout":
                raise subprocess.TimeoutExpired(args, timeout)
            raise OSError(f"Process stopped: {result['status']}")
        return subprocess.CompletedProcess(args, result["exitCode"], output(archive), output(archive, "stderr"))
    # Lake can launch Lean as a child. A timeout must stop the whole checking phase.
    with subprocess.Popen(args, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True, start_new_session=(os.name == 'posix')) as process:
        try:
            stdout, stderr = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            if os.name == 'posix':
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            else:
                process.kill()
            process.communicate()
            raise
        return subprocess.CompletedProcess(args, process.returncode, stdout, stderr)


def certify(path, *, boundaries=1000000, terms=4096, timeout=120, output=None,
            archive=None, objective=None, fixture='generated-23'):
    """Optionally retain every intermediate and score a fresh artifact in Lean."""
    from harness.archive import write_json
    if archive is not None:
        archive = Path(archive).resolve()
        archive.mkdir(parents=True, exist_ok=False)
    result = _certify(path, boundaries=boundaries, terms=terms, timeout=timeout, output=output,
                      archive=archive, objective=objective, fixture=fixture)
    if archive is not None:
        write_json(archive / 'result.json', result)
    return result


def _certify(path, *, boundaries, terms, timeout, output, archive, objective, fixture):
    """Return an auditable result. Rejection never yields a proof artifact."""
    if boundaries < 0 or terms < 0 or not math.isfinite(timeout) or timeout <= 0:
        return failure('invalid-arguments', 'Budgets must be nonnegative and timeout positive.')
    if objective not in (None, 'latency-v1', 'energy-proxy-v1'):
        return failure('invalid-arguments', 'Unknown objective.')
    if not re.fullmatch(r'[A-Za-z0-9_.-]{1,64}', fixture):
        return failure('invalid-arguments', 'Invalid fixture name.')
    if not CHECKER.is_file():
        return failure('not-built', 'Run lake build before certification.')
    try:
        with Path(path).open('rb') as stream:
            snapshot = stream.read(MAX_FILE_BYTES + 1)
        if len(snapshot) > MAX_FILE_BYTES:
            return failure('file-budget', 'Candidate exceeds the 8 MiB transport limit.')
        snapshot.decode('utf-8')
    except (OSError, UnicodeError) as exc:
        return failure('candidate-io', str(exc))
    if output is not None and Path(output).resolve() == Path(path).resolve():
        return failure('invalid-arguments', 'The certificate output must differ from the candidate input.')
    binding = dict(candidateSha256=hashlib.sha256(snapshot).hexdigest(),
                   checkerVersion='symbolic-certifier-v1')
    started = time.monotonic()
    context = nullcontext(archive) if archive is not None else tempfile.TemporaryDirectory(prefix='optimal-certify-')
    with context as directory:
        temp = Path(directory)
        candidate = temp / 'candidate.json'
        candidate.write_bytes(snapshot)
        try:
            precheck = run_process([str(CHECKER), str(candidate), str(boundaries), str(terms)], timeout, archive / 'precheck' if archive else None)
            if precheck.returncode:
                return failure('checker-process', 'The symbolic checker did not complete.', **binding,
                               exitCode=precheck.returncode, log=precheck.stderr[-4000:])
            report = json.loads(precheck.stdout)
        except subprocess.TimeoutExpired:
            return failure('checker-timeout', 'The symbolic checker exceeded its time budget.', **binding)
        except (OSError, ValueError) as exc:
            return failure('checker-process', str(exc), **binding)
        report.update(binding)
        report['recordVersion'] = 'certification-result-v1'
        if report.get('status') != 'requires-kernel-check':
            return report
        source = report.pop('source')
        namespace = 'Certificate_' + hashlib.sha256((source + (objective or '') + (fixture if objective else '')).encode('utf-8')).hexdigest()
        source = source.replace('namespace GeneratedCertificate\n', f'namespace {namespace}\n')
        source = source.replace('end GeneratedCertificate\n', f'end {namespace}\n')
        if objective:
            source = 'import OptimalComputation.Certification.Scoring\n' + source
            source += f'\n#eval OptimalComputation.Certification.printScore {namespace}.artifact "{objective}" "{fixture}"\n'
        lean_file = temp / 'Certificate.lean'
        lean_file.write_text(source, encoding='utf-8')
        try:
            with kernel_slot(archive):
                proof_started = time.monotonic()
                kernel = run_process(['lake', 'env', 'lean', str(lean_file)], timeout, archive / 'kernel' if archive else None)
        except subprocess.TimeoutExpired:
            return failure('kernel-timeout', 'Kernel checking exceeded its time budget; no certificate was accepted.', **binding)
        except OSError as exc:
            return failure('kernel-process', str(exc), **binding)
        log = kernel.stdout + kernel.stderr
        if kernel.returncode or not audit_kernel_output(log, namespace):
            return failure('kernel-check', 'The generated certificate failed kernel checking or its axiom audit.',
                           **binding, exitCode=kernel.returncode, log=log[-6000:])
        score = None
        if objective:
            lines = [line.removeprefix('CERTIFIED_SCORE ') for line in kernel.stdout.splitlines()
                     if line.startswith('CERTIFIED_SCORE ')]
            try:
                score = json.loads(lines[0]) if len(lines) == 1 else None
            except ValueError:
                pass
            if not isinstance(score, dict) or score.get('verificationStatus') != 'all-input-certified':
                return failure('scoring-failed', 'Certified scoring did not return an accepted result.',
                               **binding, score=score)
        report.update(accepted=True, status='correct',
                      message='Safe and correct for every allowed input on the specified machine model.',
                      proof='Lean kernel; standard axioms only',
                      certificateSha256=hashlib.sha256(source.encode('utf-8')).hexdigest(),
                      certificateDeclaration=namespace + '.artifact',
                      kernelSeconds=round(time.monotonic() - proof_started, 3),
                      totalSeconds=round(time.monotonic() - started, 3))
        if score is not None:
            report['score'] = score
        if output is not None:
            destination = Path(output).resolve()
            staging = None
            try:
                # Write atomically only after verification. Failed runs leave no new artifact.
                with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=destination.parent,
                                                 prefix='.certificate-', delete=False) as stream:
                    staging = Path(stream.name)
                    stream.write(source)
                os.replace(staging, destination)
            except OSError as exc:
                return failure('certificate-io', str(exc), **binding)
            finally:
                if staging is not None:
                    staging.unlink(missing_ok=True)
            report['certificatePath'] = str(destination)
        return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('candidate', type=Path)
    parser.add_argument('--boundaries', type=int, default=1000000)
    parser.add_argument('--terms', type=int, default=4096)
    parser.add_argument('--timeout', type=float, default=120, help='seconds per checking phase')
    parser.add_argument('--output', type=Path, help='save the reusable Lean certificate after acceptance')
    parser.add_argument('--archive', type=Path, help='retain all intermediate files and full process logs in a new directory')
    parser.add_argument('--objective', choices=['latency-v1', 'energy-proxy-v1'])
    parser.add_argument('--fixture', default='generated-23')
    parser.add_argument('--json', action='store_true')
    args = parser.parse_args()
    result = certify(args.candidate, boundaries=args.boundaries, terms=args.terms,
                     timeout=args.timeout, output=args.output, archive=args.archive,
                     objective=args.objective, fixture=args.fixture)
    if args.json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
    elif result['accepted']:
        print(f"Correct: {result['candidateIdentifier']} ({result['cycles']} cycles).")
        print(result['message'])
        if 'certificatePath' in result:
            print(f"Certificate: {result['certificatePath']}")
    else:
        print(f"Not certified [{result['category']}]: {result['message']}")
        if result.get('details'):
            print(json.dumps(result['details'], ensure_ascii=False))
    return 0 if result['accepted'] else 1


if __name__ == '__main__':
    sys.exit(main())
