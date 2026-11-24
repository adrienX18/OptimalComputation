#!/usr/bin/env python3
"""Package every raw file, scan credentials, and verify every tar member byte."""
import argparse
import fcntl
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import tarfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def digest(stream):
    h = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024*1024), b''):
        h.update(chunk)
    return h.hexdigest()


def package(source):
    from dotenv import dotenv_values
    credentials = dict(dotenv_values(ROOT/'.env')) | dict(os.environ)
    secrets = [v.encode() for k,v in credentials.items() if v and
               k.upper().endswith(('_API_KEY', '_TOKEN', '_SECRET', '_PASSWORD'))]
    pattern = re.compile(rb'\b(?:sk-ant-[A-Za-z0-9_-]{24,}|sk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{32,}|gh[pousr]_[A-Za-z0-9]{24,}|github_pat_[A-Za-z0-9_]{24,})')
    overlap = max([512] + [len(v) for v in secrets])

    def scan(stream, path):
        tail = b''
        for chunk in iter(lambda: stream.read(1024*1024), b''):
            data = tail + chunk
            if pattern.search(data) or any(v in data for v in secrets):
                raise RuntimeError(f'Possible credential in {path}; nothing has been uploaded.')
            tail = data[-overlap:]

    assert json.loads((source/'summary.json').read_text())['status'] == 'complete'
    paths = sorted(source.rglob('*'))
    assert not any(p.is_symlink() for p in paths), 'Do not follow archive symlinks.'
    files = [p for p in paths if p.is_file()]
    expected = {}
    for path in files:
        with path.open('rb') as stream:
            scan(stream, path.relative_to(source))
        if path.suffix == '.gz':
            with gzip.open(path, 'rb') as stream:
                scan(stream, path.relative_to(source))
        with path.open('rb') as stream:
            expected[str(Path(source.name)/path.relative_to(source))] = (path.stat().st_size, digest(stream))
    data = HERE/'data'
    data.mkdir(exist_ok=True)
    output = data/(source.name+'.tar.gz')
    if output.exists():
        raise FileExistsError(output)
    with (source/'.lock').open('rb') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        with output.with_suffix('.partial').open('wb') as raw:
            with gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=0, compresslevel=6) as zipped:
                with tarfile.open(fileobj=zipped, mode='w', format=tarfile.PAX_FORMAT) as archive:
                    for path in [source] + paths:
                        name = Path(source.name)/path.relative_to(source)
                        info = archive.gettarinfo(str(path), arcname=str(name))
                        info.uid = info.gid = 0
                        info.uname = info.gname = ''
                        if path.is_file():
                            with path.open('rb') as stream:
                                archive.addfile(info, stream)
                        else:
                            archive.addfile(info)
            raw.flush()
            os.fsync(raw.fileno())
    seen = set()
    with tarfile.open(output.with_suffix('.partial'), 'r|gz') as archive:
        for member in archive:
            if member.isfile():
                assert member.name in expected and member.name not in seen
                size, sha = expected[member.name]
                assert member.size == size and digest(archive.extractfile(member)) == sha, member.name
                seen.add(member.name)
            else:
                assert member.isdir(), member.name
    assert seen == set(expected)
    output.with_suffix('.partial').rename(output)
    with output.open('rb') as stream:
        sha = digest(stream)
    release = 'https://github.com/adrienX18/OptimalComputation/releases'
    info = dict(version='smoke-archive-bundle-v1', archive=output.name, bytes=output.stat().st_size,
        sha256=sha, source_directory=source.name, files=len(files),
        uncompressed_file_bytes=sum(v[0] for v in expected.values()),
        includes='Every raw run file, including source snapshots, partial attempts, logs, locks and the original inventory. File bytes and timestamps are preserved; tar ownership is normalized.',
        source_inventory_sha256=expected[source.name+'/inventory.json'][1],
        all_member_bytes_verified=True, configured_and_pattern_credential_scan='passed',
        release_url=release+'/tag/suite-smoke-2026-11-23',
        download_url=release+'/download/suite-smoke-2026-11-23/'+output.name)
    (data/'bundle.json').write_text(json.dumps(info, indent=2)+'\n')
    (data/'SHA256SUMS').write_text(sha+'  '+output.name+'\n')
    print(json.dumps(info, indent=2))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, default=ROOT/'runs/suite-smoke-20261123')
    package(parser.parse_args().archive.resolve())
