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
# The version under the loading bar, where the first screen shows it too (same
# place, size, colour and font: Comfortaa, copied next to the page).
cp "$ROOT/godot/assets/fonts/Comfortaa.ttf" "$ROOT/build/web/Comfortaa.ttf"
LABEL="v$VER · build $SHA · $WHEN"
STYLE="position:fixed;--s:min(calc(100vw / 1066),calc(100vh / 600));left:calc(50vw - 200 * var(--s));width:calc(400 * var(--s));top:calc(50vh - 60 * var(--s));text-align:center;color:#6b7280;font-family:KeeperComfortaa,sans-serif;font-weight:500;font-size:calc(12 * var(--s));z-index:5"
sed -i "s|<div id=\"status\">|<style>@font-face{font-family:KeeperComfortaa;src:url(Comfortaa.ttf);font-weight:300 700}</style><div id=\"status\"><div id=\"kc-build\" style=\"$STYLE\">$LABEL</div>|" "$ROOT/build/web/index.html"
grep -q "build $SHA" "$ROOT/build/web/index.html"
ls -la "$ROOT/build/web"
