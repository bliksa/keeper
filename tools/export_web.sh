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
# Update check: version.json next to the page; a script that compares it with
# this build, chimes and reloads (tools/web_update_check.js).
# version.json also lists the recent commits (newest first), so an older page
# can say in a few words what is new since its own build.
python3 - "$ROOT" "$SHA" "$WHEN" "$ROOT/build/web/version.json" <<'PY'
import json, subprocess, sys
root, sha, when, out = sys.argv[1:]
try:
    log = subprocess.run(["git", "-C", root, "log", "-40", "--format=%h%x09%s"], capture_output=True, text=True).stdout
except Exception:
    log = ""
changes = []
for line in log.splitlines():
    h, _, subj = line.partition("\t")
    subj = subj.strip()
    if len(subj) > 90:
        subj = subj[:87].rstrip(" ,;:(") + "…"
    changes.append({"sha": h[:7], "s": subj})
json.dump({"sha": sha, "date": when, "changes": changes}, open(out, "w"), ensure_ascii=False)
PY
# The log of all those descriptions: changelog.html next to the page (by day).
python3 - "$ROOT" "$ROOT/build/web/changelog.html" <<'PY'
import html, subprocess, sys
root, out = sys.argv[1:]
log = subprocess.run(["git", "-C", root, "log", "-400", "--date=format:%Y-%m-%d", "--format=%h%x09%ad%x09%s"], capture_output=True, text=True).stdout
days = {}
order = []
for line in log.splitlines():
    parts = line.split("\t", 2)
    if len(parts) < 3:
        continue
    h, d, subj = parts
    if d not in days:
        days[d] = []
        order.append(d)
    days[d].append((h, subj))
body = []
for d in order:
    body.append("<h2>%s</h2><ul>" % d)
    for h, subj in days[d]:
        body.append("<li><code>%s</code> %s</li>" % (h, html.escape(subj)))
    body.append("</ul>")
page = """<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Keeper of the Cycle · changes</title><style>
@font-face{font-family:KeeperComfortaa;src:url(Comfortaa.ttf);font-weight:300 700}
:root{color-scheme:light}body{margin:0;background:#f0eee9;color:#0f3d34;font:15px/1.5 KeeperComfortaa,sans-serif}
main{max-width:760px;margin:0 auto;padding:24px 16px 48px}h1{font-size:24px;margin:0 0 4px}a{color:#16a34a}
h2{font-size:15px;color:#64748b;margin:22px 0 4px;border-bottom:1px solid #d6d3cc;padding-bottom:4px}
ul{margin:0;padding-left:18px}li{margin:3px 0}code{color:#94a3b8;font-size:12px;margin-right:4px}
</style></head><body><main><h1>Keeper of the Cycle · changes</h1><p><a href="./">← back to the game</a></p>%s</main></body></html>
""" % "".join(body)
open(out, "w").write(page)
PY
python3 - "$ROOT/build/web/index.html" "$ROOT/tools/web_update_check.js" "$SHA" <<'PY'
import sys
page, js, sha = sys.argv[1:]
s = open(page).read()
code = open(js).read().replace("BUILD_SHA", sha)
assert "</body>" in s
s = s.replace("</body>", "<script>" + code + "</script></body>", 1)
open(page, "w").write(s)
PY
grep -q "keeperState" "$ROOT/build/web/index.html"
ls -la "$ROOT/build/web"
