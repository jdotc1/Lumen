#!/bin/bash
# Compile without installing; retain diagnostics and native previews in a new folder.
# usage: Scripts/icon-check.sh path.icon [name] --preview-dir folder
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$ROOT/Design/icon-check.py" "$@"
