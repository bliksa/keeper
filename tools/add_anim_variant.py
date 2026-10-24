#!/usr/bin/env python3
"""Add a batch of PNG frames as a new animation variant for the animation lab.

  tools/add_anim_variant.py run  "v2 longer stride" frames/*.png
  tools/add_anim_variant.py jump "v2" jump*.png fall*.png ...

run:  frames play in natural file-name order (run1, run2, … run10).
jump: files are sorted into poses by name prefix: jump, sidejump, doublejump,
      fall (e.g. sidejump_01.png). Files without a known prefix become "jump".
      Poses not supplied fall back to the original art in the game.
Copies files to godot/assets/anim_test/<anim>/<variant-slug>/ and updates
godot/data/anim_variants.json.
"""
import json, re, shutil, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "godot"
MANIFEST = ROOT / "data" / "anim_variants.json"
POSES = ["doublejump", "sidejump", "jump", "fall"]  # longest prefix first


def natural(p: Path):
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r"(\d+)", p.name)]


def main():
    if len(sys.argv) < 4 or sys.argv[1] not in ("run", "jump"):
        print(__doc__)
        sys.exit(1)
    anim, name, files = sys.argv[1], sys.argv[2], sorted((Path(f) for f in sys.argv[3:]), key=natural)
    slug = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-") or "variant"
    dest = ROOT / "assets" / "anim_test" / anim / slug
    dest.mkdir(parents=True, exist_ok=True)
    paths = []
    for f in files:
        shutil.copy(f, dest / f.name)
        paths.append(f"res://assets/anim_test/{anim}/{slug}/{f.name}")
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if anim == "run":
        data["run"][name] = paths
    else:
        poses = {}
        for p in paths:
            base = p.rsplit("/", 1)[1].lower()
            pose = next((x for x in POSES if base.startswith(x)), "jump")
            poses.setdefault(pose, []).append(p)
        data["jump"][name] = poses
    MANIFEST.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"added {anim} variant '{name}' with {len(paths)} frame(s) -> {dest}")


main()
