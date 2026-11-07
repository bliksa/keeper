#!/usr/bin/env bash
# Exports the game to build/web (playable in a browser; no special headers needed).
#   tools/export_web.sh && python3 -m http.server -d build/web 8000
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="$("$ROOT/tools/setup_godot.sh")"
mkdir -p "$ROOT/build/web"
cd "$ROOT/godot"
"$GODOT" --headless --import >/dev/null 2>&1 || true
# Build info (shown while loading and on the first screen): version, commit, date.
VER="$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)"
SHA="$(git -C "$ROOT" rev-parse --short=7 HEAD 2>/dev/null || echo dev)"
WHEN="$(git -C "$ROOT" log -1 --format=%cd --date=format:'%Y-%m-%d %H:%M' 2>/dev/null || date -u '+%Y-%m-%d %H:%M')"
printf '{"version": "%s", "sha": "%s", "date": "%s"}\n' "$VER" "$SHA" "$WHEN" > data/build.json
"$GODOT" --headless --export-release "Web" "$ROOT/build/web/index.html"
# The version on the loading screen (inside Godot's status overlay, gone once the game runs).
LABEL="v$VER · build $SHA · $WHEN"
sed -i "s|<div id=\"status\">|<div id=\"status\"><div style=\"position:absolute;right:14px;bottom:10px;color:#6b7280;font:13px sans-serif;z-index:5\">$LABEL</div>|" "$ROOT/build/web/index.html"
grep -q "build $SHA" "$ROOT/build/web/index.html"
ls -la "$ROOT/build/web"
