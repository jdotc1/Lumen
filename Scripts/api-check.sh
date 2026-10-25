#!/bin/bash
# Fails when the public API breaks against the last release tag and CHANGELOG's newest entry doesn't
# describe it under "### Breaking". Run before tagging; the manual CI workflow also runs it.
#
#   Scripts/api-check.sh [baseline-tag]
set -euo pipefail
cd "$(dirname "$0")/.."
# The last release before this commit: when HEAD is itself the release tag, the one before it.
if [[ -n "${1:-}" ]]; then baseline="$1"
elif git describe --tags --exact-match HEAD >/dev/null 2>&1; then baseline=$(git describe --tags --abbrev=0 HEAD^)
else baseline=$(git describe --tags --abbrev=0); fi
scratch="${LUMEN_SCRATCH:-${TMPDIR:-/tmp}/lumen-api-check}"
manifest=$(git show "$baseline:Package.swift")
products=()
for product in LumenTokens LumenUI LumenIntents LumenConformance; do
  # Only products the baseline already had can break.
  grep -q "name: \"$product\"" <<<"$manifest" && products+=("$product")
done
if [[ ${#products[@]} -eq 0 ]]; then
  echo "error: no supported library products found in $baseline:Package.swift" >&2
  exit 1
fi
echo "API check against $baseline: ${products[*]}"
log=$(mktemp)
if swift package --scratch-path "$scratch" diagnose-api-breaking-changes "$baseline" --products "${products[@]}" 2>&1 | tee "$log" | grep -E "breaking|API breakage|💔" ; then :; fi
if grep -q "API breakage" "$log"; then
  newest=$(awk '/^## /{n++} n==1' CHANGELOG.md)
  if grep -q "^### Breaking" <<<"$newest"; then
    echo "Breaking changes found; CHANGELOG's newest entry lists them under Breaking."
  else
    echo "error: breaking API changes since $baseline, and CHANGELOG's newest entry has no ### Breaking section." >&2
    exit 1
  fi
fi
