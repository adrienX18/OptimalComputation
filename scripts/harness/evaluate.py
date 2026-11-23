"""Sandbox generation and the existing Lean verification/scoring pipeline."""
import gzip
import json
from pathlib import Path
import shutil
import uuid

import certify
from .archive import command, output, read_json, write_json

ROOT = Path(__file__).resolve().parents[2]
TOOLS = Path(__file__).parent
BINARY = ROOT / '.lake/build/bin/optimal_computation'
TASKS = {
    'tiny': ('scalar-multiply-signed16-v1', 'tiny-multiply-v1',
             'Inputs a,b are signed16; output a*b.', ['zeros', 'mixed-signs']),
    'pair': ('product-pair-signed16-v1', 'product-pair-serial-v1',
             'Inputs a,b,c,d are signed16; outputs a*b,c*d.', ['zeros', 'mixed-signs']),
    'matvec': ('matvec-16x16-signed16-v1', 'matvec-naive-v2',
               'Inputs: row-major A[16,16] then x[16], all signed16. Outputs A*x in row order.',
               ['zeros', 'mixed-signs', 'negative-endpoints', 'positive-endpoints', 'generated-23']),
    'matmul': ('matmul-16x16-signed16-v1', 'matmul-naive-v2',
               'Inputs: row-major A[16,16] then B[16,16], all signed16. Outputs A*B row-major.',
               ['zeros', 'mixed-signs', 'negative-endpoints', 'positive-endpoints', 'generated-23']),
    'polynomial': ('polynomial-degree7-points16-v1', 'polynomial-naive-v1',
                   'Inputs c[0..7] in [-8,7], then 16 points x in [-4,3]. Output sum(c[k]*x^k,k=0..7) per point.',
                   ['zeros', 'mixed-signs', 'negative-endpoints', 'positive-endpoints', 'generated-23']),
    'gram': ('gram-16x16-signed16-v1', 'gram-naive-v1',
             'Input row-major A[16,16], all signed16. Output A*A^T row-major.',
             ['zeros', 'mixed-signs', 'negative-endpoints', 'positive-endpoints', 'generated-23']),
    'two-stage': ('two-stage-linear-16-signed16-v1', 'two-stage-naive-v1',
                  'Inputs row-major A[16,16], x[16], row-major B[16,16]. A,x in [-45,45], B signed16. Output B*(A*x).',
                  ['zeros', 'mixed-signs', 'negative-endpoints', 'positive-endpoints', 'generated-23']),
}
STARTER = 'from candidate_tools import baseline\n\ndef build():\n    return baseline()\n'


def strict_json(text):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f'Duplicate key: {key}')
            result[key] = value
        return result
    def invalid(value):
        raise ValueError(f'Invalid number: {value}')
    return json.loads(text, object_pairs_hook=unique, parse_constant=invalid)


def cli(args, directory, timeout=120):
    result = command([str(BINARY), *map(str, args), '--json'], directory, cwd=ROOT, timeout=timeout)
    report = None
    try:
        report = strict_json(output(directory))
    except ValueError:
        pass
    return result, report


def initialize(config, directory):
    """Use the already certified baseline; public input vectors are frozen here."""
    directory = Path(directory)
    directory.mkdir()
    task = TASKS[config['task']]
    cfg = ','.join(map(str, config['configuration']))
    result, raw = cli(['export-candidate', task[1], '--configuration', cfg], directory / 'export')
    if result['exitCode'] != 0 or not isinstance(raw, dict):
        raise ValueError(f'Cannot export the selected baseline: {raw}')
    write_json(directory / 'candidate.json', raw)
    (directory / 'generator.py').write_text(STARTER)
    fixtures = {}
    for name in task[3]:
        result, report = cli(['evaluate', task[1], '--configuration', cfg,
                              '--fixture', name, '--objective', config['objective']], directory / name)
        if result['exitCode'] != 0 or not report or report.get('verificationStatus') != 'all-input-certified':
            raise ValueError(f'Cannot evaluate baseline fixture {name}: {report}')
        fixtures[name] = report['inputScalars']
        write_json(directory / name / 'input.json', report['inputScalars'])
    score_fixture = 'generated-23' if 'generated-23' in fixtures else 'mixed-signs'
    score = read_json(directory / score_fixture / 'stdout.txt')
    write_json(directory / 'score.json', score)
    return dict(fixtures=fixtures, scoreFixture=score_fixture, score=score['objective']['score'],
                unit=score['objective']['unit'], raw=raw)


def resolve_image(image, directory):
    result = command(['docker', 'image', 'inspect', image, '--format', '{{.Id}}'],
                     directory, cwd=ROOT, timeout=30)
    value = output(directory).strip()
    if result['status'] != 'completed' or result['exitCode'] != 0 or not value.startswith('sha256:'):
        raise RuntimeError(f'Docker image unavailable. Pull {image} before starting a run.')
    return value


def generate(code, baseline, directory, image, timeout=30):
    directory = Path(directory)
    inputs = directory / 'input'
    inputs.mkdir(parents=True)
    inputs.chmod(0o755)
    (inputs / 'generator.py').write_text(code)
    write_json(inputs / 'baseline.json', baseline)
    for name in ['candidate_tools.py', 'container_entry.py']:
        shutil.copyfile(TOOLS / name, inputs / name)
    for path in inputs.iterdir():
        path.chmod(0o644)
    name = 'optimal-generator-' + uuid.uuid4().hex
    write_json(directory / 'container.json', dict(name=name, image=image))
    args = ['docker', 'run', '--rm', '--name', name, '--pull=never', '--init',
            '--network=none', '--read-only', '--cap-drop=ALL', '--security-opt=no-new-privileges',
            '--pids-limit=64', '--memory=256m', '--cpus=1', '--user=65534:65534',
            '--tmpfs', '/tmp:rw,nosuid,nodev,size=16777216', '--workdir', '/tmp',
            '--mount', f'type=bind,src={inputs.resolve()},dst=/input,readonly',
            image, 'python', '-I', '-B', '/input/container_entry.py']
    try:
        result = command(args, directory / 'process', cwd=ROOT, timeout=timeout,
                         output_limit=certify.MAX_FILE_BYTES)
    finally:
        # Killing the Docker client alone does not necessarily stop its container.
        command(['docker', 'rm', '-f', name], directory / 'cleanup', cwd=ROOT, timeout=30)
    if result['status'] != 'completed' or result['exitCode'] != 0:
        return dict(accepted=False, category='generator-failed', process=result,
                    message=output(directory / 'process', 'stderr')[-2000:])
    payload = (directory / 'process/stdout.txt').read_bytes()
    (directory.parent / 'candidate.json').write_bytes(payload)
    return None


def evaluate(config, baseline, directory):
    directory = Path(directory)
    path = directory / 'candidate.json'
    try:
        if path.stat().st_size > certify.MAX_FILE_BYTES:
            raise ValueError('Candidate exceeds the 8 MiB limit.')
        raw = strict_json(path.read_text())
        if not isinstance(raw, dict):
            raise ValueError('Candidate must be an object.')
    except (ValueError, OSError) as exc:
        return dict(accepted=False, category='invalid-candidate-file', message=str(exc))
    if raw.get('workloadIdentifier') != TASKS[config['task']][0]:
        return dict(accepted=False, category='wrong-workload', message='Workload must stay fixed.')
    if config['objective'] == 'latency-v1' and raw.get('configuration') != dict(zip(['lanes', 'banks'], config['configuration'])):
        return dict(accepted=False, category='wrong-configuration', message='Latency configuration must stay fixed.')
    checks = []
    for name in baseline['fixtures']:
        work = directory / 'simulation' / name
        work.mkdir(parents=True)
        write_json(work / 'input.json', baseline['fixtures'][name])
        result, report = cli(['simulate', path.resolve(), '--input', (work / 'input.json').resolve(),
                              '--budget', config['boundaries'], '--trace', (work / 'trace.json').resolve()],
                             work / 'process', config['check_timeout'])
        if (work / 'trace.json').exists():
            # Keep the original and a compressed archive; no trace is truncated.
            with (work / 'trace.json').open('rb') as src, gzip.open(work / 'trace.json.gz', 'wb') as dst:
                shutil.copyfileobj(src, dst)
        passed = result['status'] == 'completed' and result['exitCode'] == 0 and report is not None
        checks.append(dict(fixture=name, passed=passed, process=result, report=report))
    write_json(directory / 'simulations.json', checks)
    if not all(item['passed'] for item in checks):
        failed = next(item for item in checks if not item['passed'])
        write_json(directory / 'certification-skipped.json', dict(reason='A public simulation did not pass.'))
        return dict(accepted=False, category='simulation-failed', message='A public fixture failed.', failure=failed)
    observed = checks[0]['report']['execution']
    result = certify.certify(path, boundaries=config['boundaries'], terms=config['terms'],
                             timeout=config['check_timeout'], archive=directory / 'certification',
                             objective=config['objective'], fixture=baseline['scoreFixture'])
    if not result['accepted']:
        return dict(accepted=False, category=result['category'], message=result['message'],
                    details=result.get('details'), observedCycles=observed['cycles'])
    score = result['score']
    write_json(directory / 'score.json', score)
    return dict(accepted=True, category='certified', score=score['objective']['score'],
                unit=score['objective']['unit'], cycles=score['execution']['cycles'],
                certificate=result['certificateDeclaration'])
