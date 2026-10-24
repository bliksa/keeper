#!/usr/bin/env python3
"""Add PNG frames as a new variant of one character animation.

  tools/add_anim_variant.py run "v2 longer stride" frames/*.png [--in-game]

Animations: idle walk run jump sidejump doublejump fall lookdown sit pain dead hang.
Frames play in natural file-name order (run1, run2, … run10). Copies files to
godot/assets/anim_test/<anim>/<variant-slug>/ and updates
godot/data/anim_variants.json; --in-game also makes the game use it.
(The animation lab can do the same from the browser with "Save to repo".)
"""
import json, re, shutil, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "godot"
MANIFEST = ROOT / "data" / "anim_variants.json"
ANIMS = "idle walk run jump sidejump doublejump fall lookdown sit pain dead hang".split()


def natural(p: Path):
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r"(\d+)", p.name)]


def main():
    args = [a for a in sys.argv[1:] if a != "--in-game"]
    if len(args) < 3 or args[0] not in ANIMS:
        print(__doc__)
        sys.exit(1)
    anim, name, files = args[0], args[1], sorted((Path(f) for f in args[2:]), key=natural)
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "variant"
    dest = ROOT / "assets" / "anim_test" / anim / slug
    dest.mkdir(parents=True, exist_ok=True)
    paths = []
    for f in files:
        shutil.copy(f, dest / f.name)
        paths.append(f"res://assets/anim_test/{anim}/{slug}/{f.name}")
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    data.setdefault("anims", {}).setdefault(anim, {})[name] = paths
    if "--in-game" in sys.argv:
        data.setdefault("in_game", {})[anim] = name
    MANIFEST.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"added {anim} variant '{name}' with {len(paths)} frame(s) -> {dest}")


main()
