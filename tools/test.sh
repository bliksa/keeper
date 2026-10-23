#!/usr/bin/env bash
# Imports the project and runs the headless end-to-end test (tests/test_runner.gd).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="$("$ROOT/tools/setup_godot.sh")"
cd "$ROOT/godot"
"$GODOT" --headless --import >/dev/null 2>&1 || true
# Fail on script errors reported during import.
if "$GODOT" --headless --import 2>&1 | grep -E "SCRIPT ERROR|Parse Error"; then
  echo "Script errors found" >&2
  exit 1
fi
"$GODOT" --headless --fixed-fps 60 --quit-after 30000 --path . res://tests/test_runner.tscn 2>&1 \
  | grep -v "ObjectDB instances leaked\|resources still in use\|at: cleanup\|at: clear"
exit "${PIPESTATUS[0]}"
