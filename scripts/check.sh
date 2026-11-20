#!/bin/sh
# Lints and tests every addon, plus the release tooling.
# Runs inside the tools/docker image (see scripts/check.ps1 for Windows).
set -eu
cd "$(dirname "$0")/.."

echo "== luacheck"
luacheck addons spec

echo "== busted"
busted

echo "== release tooling"
python3 -m pytest -q tools/tests

echo "== addon metadata"
for toc in addons/*/*.toc; do
	python3 tools/release.py check "$(basename "$(dirname "$toc")")"
done
