#!/usr/bin/env python3
# Usage: tools/gen_forest_run.py godot/data/levels/forest_run.txt  (overwrites the map; edits made
# in the level editor are lost, so only use it for a fresh default map)
# Forest run map, version 2: more weaving between the paths, fewer jumps.
#   Most obstacles block one or two paths (branches H = tall: go round them),
#   slaloms make her change path again and again, drops trace the way through.
#   Full-width roots (jump) are rare. Stage 3 adds flying notifications, stage 4
#   side traps (plus random ones in the game).
import random, re, sys
rng = random.Random(11)
rows = []
L = {-1: 1, 0: 2, 1: 3}
LANES = [-1, 0, 1]

def blank(n=1):
    for _ in range(n): rows.append(list("....."))

def put(r, col, ch):
    while len(rows) <= r: blank()
    if rows[r][col] == ".":
        rows[r][col] = ch

def gate(r, free, tall=True):
    """Blocks every path but `free` (H tall branches, or R roots)."""
    for x in LANES:
        if x != free:
            put(r, L[x], "H" if tall else "R")

def trail(r0, r1, l0, l1):
    """Drops leading from path l0 (row r0) to l1 (row r1)."""
    n = max(1, r1 - r0)
    for k in range(0, n + 1, 2):
        x = round(l0 + (l1 - l0) * k / n)
        put(r0 + k, L[x], "D")

def stage(n_rows, level, n_sun=3, notes=False, traps=False, marker=True, dialog=None):
    start = len(rows)
    blank(n_rows)
    if marker: put(start, 0, "A")
    if dialog: put(start + 2, 4, dialog)
    r = start + 6
    end = start + n_rows - 6
    free = 0
    gaps = {1: (7, 9), 2: (6, 8), 3: (5, 7), 4: (5, 6)}[level]
    pats = ["gate", "gate", "slalom", "one", "two_low", "weave"]
    if level == 1: pats += ["root", "one"]
    if notes: pats += ["note_lane", "note_gate"]
    if traps: pats += ["trap_gate", "squeeze"]
    gates = []  # (row, free lane) for sun placement
    while r < end:
        pat = rng.choice(pats)
        if pat == "gate":
            nf = rng.choice([x for x in LANES if x != free])
            trail(r - 5, r - 1, free, nf)
            gate(r, nf)
            gates.append((r, nf)); free = nf
            r += 1
        elif pat == "slalom":
            n = 3 if level < 3 else 4
            for i in range(n):
                nf = rng.choice([x for x in LANES if x != free])
                trail(r - 3, r - 1, free, nf)
                gate(r, nf)
                gates.append((r, nf)); free = nf
                r += 4 if level < 4 else 3
        elif pat == "one":
            l = rng.choice(LANES)
            put(r, L[l], "H")
            if l == free: free = rng.choice([x for x in LANES if x != l])
            put(r, L[free], "D")
        elif pat == "two_low":
            # Two roots and a free path: jump them or go round.
            nf = rng.choice(LANES)
            gate(r, nf, tall=False)
            gates.append((r, nf)); free = nf
        elif pat == "weave":
            l = free
            for k in range(6):
                l = max(-1, min(1, l + rng.choice([-1, 1])))
                put(r + k * 2, L[l], "D")
            free = l
            r += 10
        elif pat == "root":
            for x in LANES: put(r, L[x], "R")
            put(r + 2, L[free], "D")
        elif pat == "note_lane":
            # A notification over the free path: dodge sideways (or stay low).
            nf = rng.choice([x for x in LANES if x != free])
            gate(r, free, tall=True) if False else None
            put(r, L[free], "V")
            trail(r - 4, r - 1, free, nf)
            free = nf
        elif pat == "note_gate":
            nf = rng.choice([x for x in LANES if x != free])
            trail(r - 4, r - 1, free, nf)
            gate(r, nf)
            gates.append((r, nf))
            put(r + 3, L[nf], "V")
            free = rng.choice([x for x in LANES if x != nf])
            trail(r + 1, r + 3, nf, free)
        elif pat == "trap_gate":
            side = rng.choice([-1, 1])
            put(r, 0 if side < 0 else 4, "<" if side < 0 else ">")
            nf = rng.choice([x for x in LANES if x != side])
            put(r + 3, L[side], "H"); put(r + 3, L[-nf if nf else -side], "H") if False else None
            trail(r - 4, r - 1, free, nf)
            free = nf
        elif pat == "squeeze":
            # Traps on both sides: the middle path only.
            put(r, 0, "<"); put(r, 4, ">")
            trail(r - 4, r - 1, free, 0)
            free = 0
        r += rng.randint(*gaps)
    # Sun pieces: in the free path right behind a gate (you have to weave to get them).
    picks = sorted(gates, key=lambda g: g[0])
    want = [start + int(n_rows * f) for f in ([0.25, 0.55, 0.85] if n_sun == 3 else [0.5])]
    for w in want:
        cand = [g for g in picks if g[0] >= w - 10]
        gr, gl = cand[0] if cand else (w, 0)
        rr = gr + 2
        while rr < len(rows) and rows[rr][L[gl]] not in ".D":
            rr += 1
        rows[rr][L[gl]] = "+"

stage(150, 1, marker=False)
stage(165, 2)
stage(180, 3, notes=True, dialog="b")
stage(195, 4, notes=True, traps=True, dialog="c")
blank(6)
gd = open(__import__("pathlib").Path(__file__).resolve().parent.parent / "godot/scripts/screens/forest_runner.gd").read()
out = re.search(r'const MAP_HEADER := """(.*?)"""', gd, re.S).group(1).rstrip("\n").split("\n")
for r in reversed(rows):
    out.append("".join(r))
open(sys.argv[1], "w").write("\n".join(out) + "\n")
txt = "".join("".join(r) for r in rows)
print(len(rows), "rows;", {c: txt.count(c) for c in "RHVD+<>A"})
