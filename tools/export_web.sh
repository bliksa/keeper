#!/usr/bin/env bash
# Exports the game to build/web (playable in a browser; no special headers needed).
#   tools/export_web.sh && python3 -m http.server -d build/web 8000
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="$("$ROOT/tools/setup_godot.sh")"
mkdir -p "$ROOT/build/web"
cd "$ROOT/godot"
"$GODOT" --headless --import >/dev/null 2>&1 || true
"$GODOT" --headless --export-release "Web" "$ROOT/build/web/index.html"
ls -la "$ROOT/build/web"
