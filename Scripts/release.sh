#!/bin/bash
# maintainer script; pushes tags
# Tags a Lumen release only after everything that could make it a bad one has passed: the API check
# against the previous release (with the changelog owning up to any break), a strict build, and the
# whole test suite with goldens. Theme changes stop for changelog review; otherwise it tags and pushes.
#
#   Scripts/release.sh 0.12.0
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:?usage: Scripts/release.sh <version>}"
tag="v$version"
scratch="${LUMEN_SCRATCH:-${TMPDIR:-/tmp}/lumen-release}"
git diff --quiet && git diff --cached --quiet || { echo "error: commit your changes first" >&2; exit 1; }
# An untracked file the build can see (a source, a resource, a golden) would be tested but not tagged.
untracked=$(git ls-files --others --exclude-standard -- Package.swift Package.resolved Sources Tests Examples Scripts)
[[ -z "$untracked" ]] || { printf 'error: untracked files the build or tests would use; commit or remove them:\n%s\n' "$untracked" >&2; exit 1; }
# The release gate compares goldens whatever the caller's shell says.
[[ -z "${LUMEN_SKIP_GOLDENS:-}" && -z "${LUMEN_RECORD_SNAPSHOTS:-}" && -z "${LUMEN_GOLDENS_DIR:-}" ]] \
  || { echo "error: unset LUMEN_SKIP_GOLDENS, LUMEN_RECORD_SNAPSHOTS and LUMEN_GOLDENS_DIR; a release compares every golden" >&2; exit 1; }
git rev-parse -q --verify "refs/tags/$tag" >/dev/null && { echo "error: $tag already exists" >&2; exit 1; }
grep -q "^## $version " CHANGELOG.md || { echo "error: CHANGELOG.md has no '## $version' entry" >&2; exit 1; }
# Keep the linked library version in the tested and tagged source, with one version declaration.
python3 - "$version" <<'PYVERSION'
from pathlib import Path
import re
import sys
version = sys.argv[1]
if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?", version):
    raise SystemExit("error: invalid release version")
path = Path("Sources/LumenUI/LumenAboutPanel.swift")
source, count = re.subn(r'public static let version = "[^"]+"',
                        f'public static let version = "{version}"', path.read_text())
if count != 1:
    raise SystemExit("error: expected one LumenLibrary.version declaration")
path.write_text(source)
PYVERSION
if ! git diff --quiet -- Sources/LumenUI/LumenAboutPanel.swift; then
  git add -- Sources/LumenUI/LumenAboutPanel.swift
  git -c user.name=jdotc1 -c user.email=138259519+jdotc1@users.noreply.github.com commit -m "Bump LumenUI version to $version" -- Sources/LumenUI/LumenAboutPanel.swift
fi
previous=$(git describe --tags --abbrev=0)
echo "== API check against $previous"
Scripts/api-check.sh "$previous"
echo "== Strict build"
swift build --scratch-path "$scratch" --build-tests -Xswiftc -warnings-as-errors
# Before the suite, so a stop doesn't waste a full run. The helper exits 3 when theme values changed and
# the changelog lacked the report: it writes the report for review and nothing is tagged. Commit the
# reviewed changelog and run again; a changelog that already carries the report continues.
theme_report="$scratch/release-theme-values"
mkdir -p "$theme_report/current"
"$scratch/debug/lumen-theme" export "$theme_report/current" >/dev/null
git show "$previous:Docs/reference/builtin-themes.json" > "$theme_report/previous.json"
python3 Scripts/release-theme-values.py "$scratch/debug/lumen-theme" \
  "$theme_report/previous.json" "$theme_report/current/builtin-themes.json" CHANGELOG.md "$version"
echo "== Tests (goldens included)"
swift test --scratch-path "$scratch" --skip-build
echo "== Tagging $tag"
git tag -a "$tag" -m "Lumen $version"
git push --quiet origin HEAD --follow-tags
echo "Released $tag ($(git rev-parse --short HEAD))"
