#!/usr/bin/env python3
"""Makes KeeperDyslexic-*.otf from OpenDyslexic-*.otf, a tighter OpenDyslexic:
every letter loses SIDE units of space on each side (OpenDyslexic is wide-set;
before, a -3 px glyph spacing squeezed every glyph alike and ran dots together),
and . , ! ? : ; … also move PUNCT units towards the letter before them, so they
no longer look detached. The gap after punctuation stays as it was.

The OFL reserves the name "OpenDyslexic", so the modified font gets its own
family name (KeeperDyslexic); the licence (OFL-OpenDyslexic.txt) still applies.

  pip install fonttools && tools/tighten_punctuation.py
"""
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.pens.t2CharStringPen import T2CharStringPen
from fontTools.pens.transformPen import TransformPen

FONTS = Path(__file__).resolve().parent.parent / "godot" / "assets" / "fonts"
PUNCT = ".,!?:;…"
SIDE = 80
SHIFT = {"Regular": 60, "Bold": 55}
# Per glyph (style -> char -> units; negative = more room before it): Bold's "!"
# has a wide wedge-shaped dot that reaches left under the letter before it, so
# it gets clearly more room than a letter gap (≈ 220 units of air before its ink).
OVERRIDE = {"Bold": {"!": -135}, "Regular": {"!": 0, "?": 30}}


def move(top, cff, gs, hmtx, g, dx, shrink):
    adv, lsb = hmtx[g]
    pen = T2CharStringPen(adv - shrink, gs)
    gs[g].draw(TransformPen(pen, (1, 0, 0, 1, dx, 0)))
    top.CharStrings[g] = pen.getCharString(private=top.Private, globalSubrs=cff.GlobalSubrs)
    hmtx[g] = (adv - shrink, lsb + dx)


for style, shift in SHIFT.items():
    font = TTFont(FONTS / f"OpenDyslexic-{style}.otf")
    cmap = font.getBestCmap()
    gs = font.getGlyphSet()
    cff = font["CFF "].cff
    top = cff.topDictIndex[0]
    hmtx = font["hmtx"]
    from fontTools.pens.boundsPen import BoundsPen
    punct = {cmap[ord(c)] for c in PUNCT if ord(c) in cmap}
    for g in font.getGlyphOrder():
        adv, lsb = hmtx[g]
        bp = BoundsPen(gs)
        gs[g].draw(bp)
        if bp.bounds is None or adv <= 2 * SIDE:
            continue  # spaces, marks
        if g in punct:
            ch = next(c for c in PUNCT if cmap.get(ord(c)) == g)
            sh = OVERRIDE.get(style, {}).get(ch, shift)
            move(top, cff, gs, hmtx, g, -sh, sh)
        else:
            move(top, cff, gs, hmtx, g, -SIDE, 2 * SIDE)
    # Own name (Reserved Font Name).
    for rec in font["name"].names:
        s = rec.toUnicode()
        if "OpenDyslexic" in s:
            rec.string = s.replace("OpenDyslexic", "KeeperDyslexic")
    cff.fontNames = [n.replace("OpenDyslexic", "KeeperDyslexic") for n in cff.fontNames]
    out = FONTS / f"KeeperDyslexic-{style}.otf"
    font.save(out)
    print("wrote", out)
