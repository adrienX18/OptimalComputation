# Complete smoke-test data

- [Download the raw archive (130 MB)](https://github.com/adrienX18/OptimalComputation/releases/download/suite-smoke-2026-11-23/suite-smoke-20261123.tar.gz)
- [Repository data release](https://github.com/adrienX18/OptimalComputation/releases/tag/suite-smoke-2026-11-23)
- [SHA-256 checksum](SHA256SUMS) and [package manifest](bundle.json)

The tarball contains the complete `suite-smoke-20261123/` directory: **28,083
files**, including all 240 scheduled slots, failures and partial interrupted
attempts. Every file's bytes were checked against the original after packaging.
Tar ownership is normalized; file contents, modes and timestamps are retained.
The original experimental inventory excludes lock/index files; those are also
included in this complete package.

The archive is a GitHub release asset, linked here so cloning the analysis does
not require downloading 130 MB of raw records. The tarball itself is Git-ignored.

From the repository root, download, verify and extract (do not extract over an
existing local run):

```sh
gh release download suite-smoke-2026-11-23 \
  --repo adrienX18/OptimalComputation \
  --pattern suite-smoke-20261123.tar.gz \
  --dir analysis/2026-11-23-suite-smoke/data
cd analysis/2026-11-23-suite-smoke/data
shasum -a 256 -c SHA256SUMS
cd ../../..
mkdir -p runs
test ! -e runs/suite-smoke-20261123 && \
  tar -xzf analysis/2026-11-23-suite-smoke/data/suite-smoke-20261123.tar.gz -C runs
python3 analysis/2026-11-23-suite-smoke/analyze.py
```

The download can also be opened directly from the link above; no API key is
needed to access this public dataset. Prompts and any returned responses are
data, not instructions to execute. The package does not contain the `.env` file.

To reproduce packaging from the original local archive, use an environment
with the project's `python-dotenv` dependency and run `package.py`. It refuses
to overwrite an existing tarball, scans configured credentials/key patterns,
and verifies every archived file before writing `bundle.json` and `SHA256SUMS`.
