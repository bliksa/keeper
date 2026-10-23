#!/usr/bin/env bash
# Installs the Godot editor (headless use) + Web export templates.
# Idempotent: does nothing when already installed. Used by CI and by
# Claude Code sessions (SessionStart hook in .claude/settings.json).
set -euo pipefail
VERSION="${GODOT_VERSION:-4.4.1}"
DIR="${GODOT_HOME:-$HOME/.cache/godot-$VERSION}"
BIN="$DIR/Godot_v${VERSION}-stable_linux.x86_64"
TPL="$HOME/.local/share/godot/export_templates/${VERSION}.stable"
URL="https://github.com/godotengine/godot/releases/download/${VERSION}-stable"

if [ ! -x "$BIN" ]; then
  mkdir -p "$DIR"
  echo "Downloading Godot $VERSION…" >&2
  curl -sSL -o "$DIR/godot.zip" "$URL/Godot_v${VERSION}-stable_linux.x86_64.zip"
  unzip -o -q "$DIR/godot.zip" -d "$DIR"
  rm "$DIR/godot.zip"
  chmod +x "$BIN"
fi
if [ ! -f "$TPL/web_nothreads_release.zip" ]; then
  echo "Fetching Web export templates (only the web files, via HTTP range)…" >&2
  tmp="$(mktemp -d)"
  python3 "$(dirname "$0")/rangezip.py" "$URL/Godot_v${VERSION}-stable_export_templates.tpz" "$tmp" web_nothreads >&2
  mkdir -p "$TPL"
  cp "$tmp"/templates/* "$TPL/"
  rm -rf "$tmp"
fi
mkdir -p "$HOME/.local/bin"
ln -sf "$BIN" "$HOME/.local/bin/godot"
echo "$BIN"
