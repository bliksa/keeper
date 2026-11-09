#!/usr/bin/env python3
# Usage: tools/gen_forest_run.py godot/data/levels/forest_run.txt  (overwrites the map; edits made
# in the level editor are lost, so only use it for a fresh default map)
# Forest run map, version 3: fluid. Every gate is reached with time to react at the
#   stage's speed (REACT seconds), the free path moves at most one path over from
#   the last one (two only with a long run-up), and nothing comes right after a gate.
#   Most obstacles block one or two paths (branches H = tall: go round them),
#   slaloms make her change path again and again, drops trace the way through.
#   Full-width roots (jump) are rare. Stage 3 adds flying notifications, stage 4
#   side traps (plus random ones in the game).
import random, re, sys
rng = random.Random(11)
rows = []
# Paths 0–3 (left to right) are columns 1–4; columns 0 and 5 are the sides.
L = {0: 1, 1: 2, 2: 3, 3: 4}
LANES = [0, 1, 2, 3]

def blank(n=1):
    for _ in range(n): rows.append(list("......"))

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

SPEED = {1: 9.0, 2: 11.0, 3: 12.5, 4: 14.5}   # ForestRunner.STAGE_SPEED
ROW_M = 2.0
REACT = 1.1   # seconds between two things to steer round

def min_gap(level, lanes=1):
    # Rows she needs between two obstacles: reaction time at the stage speed, plus
    # time to move over `lanes` paths (LANE 1.7 m at LANE_SPEED 11 m/s).
    t = REACT + max(0, lanes - 1) * 0.16
    return int(-(-(SPEED[level] * t) // ROW_M))

def near(free):
    # The next free path: one over (now and then the same one).
    return rng.choice([x for x in LANES if abs(x - free) == 1])

def stage(n_rows, level, n_sun=3, notes=False, traps=False, marker=True, dialog=None):
    start = len(rows)
    blank(n_rows)
    if marker: put(start, 0, "A")
    if dialog: put(start + 2, 5, dialog)
    r = start + 6
    end = start + n_rows - 6
    free = 1
    gaps = {1: (7, 9), 2: (6, 8), 3: (5, 7), 4: (5, 6)}[level]
    pats = ["gate", "gate", "slalom", "one", "two_low", "weave"]
    if level == 1: pats += ["root", "one"]
    if notes: pats += ["note_lane", "note_gate"] * 3
    if traps: pats += ["trap_gate", "squeeze"] * 2
    gates = []  # (row, free lane) for sun placement
    done = 0
    while r < end:
        pat = rng.choice(pats)
        if pat == "gate":
            nf = near(free)
            trail(r - 5, r - 1, free, nf)
            gate(r, nf)
            gates.append((r, nf)); free = nf
            r += 1
        elif pat == "slalom":
            n = 3
            for i in range(n):
                nf = near(free)
                trail(r - 3, r - 1, free, nf)
                gate(r, nf)
                gates.append((r, nf)); free = nf
                r += min_gap(level)
        elif pat == "one":
            l = rng.choice(LANES)
            put(r, L[l], "H")
            if l == free: free = near(l)
            put(r, L[free], "D")
        elif pat == "two_low":
            # Two roots and a free path: jump them or go round.
            nf = rng.choice(LANES)
            gate(r, nf, tall=False)
            gates.append((r, nf)); free = nf
        elif pat == "weave":
            l = free
            for k in range(6):
                l = max(0, min(3, l + rng.choice([-1, 1])))
                put(r + k * 2, L[l], "D")
            free = l
            r += 10
        elif pat == "root":
            for x in LANES: put(r, L[x], "R")
            put(r + 2, L[free], "D")
        elif pat == "note_lane":
            # A notification over the free path: dodge sideways (or stay low).
            nf = near(free)
            put(r, L[free], "V")
            trail(r - 4, r - 1, free, nf)
            free = nf
        elif pat == "note_gate":
            nf = near(free)
            trail(r - 4, r - 1, free, nf)
            gate(r, nf)
            gates.append((r, nf))
            g = min_gap(level)
            put(r + g, L[nf], "V")
            free = near(nf)
            trail(r + 1, r + g - 1, nf, free)
            r += g
        elif pat == "trap_gate":
            side = rng.choice([0, 3])
            put(r, 0 if side == 0 else 5, "<" if side == 0 else ">")
            nf = near(free) if abs(free - side) <= 0 else free
            trail(r - 4, r - 1, free, nf)
            free = nf
        elif pat == "squeeze":
            # Traps on both sides: the two middle paths only.
            put(r, 0, "<"); put(r, 5, ">")
            nf = 1 if free <= 1 else 2
            trail(r - 4, r - 1, free, nf)
            free = nf
        r += max(min_gap(level), rng.randint(*gaps))
        # Now and then a calm stretch: just running and a few drops.
        done += 1
        if done % 3 == 0 and r < end - 30:
            calm = rng.randint(14, 22)
            l = free
            for k in range(2, calm - 2, 3):
                put(r + k, L[l], "D")
            r += calm
    # Sun pieces: in the free path right behind a gate (you have to weave to get them).
    picks = sorted(gates, key=lambda g: g[0])
    want = [start + int(n_rows * f) for f in ([0.25, 0.55, 0.85] if n_sun == 3 else [0.5])]
    for w in want:
        cand = [g for g in picks if g[0] >= w - 10]
        gr, gl = cand[0] if cand else (w, 1)
        rr = gr + 2
        while rr < len(rows) and rows[rr][L[gl]] not in ".D":
            rr += 1
        rows[rr][L[gl]] = "+"

stage(240, 1, marker=False)
stage(260, 2)
stage(280, 3, notes=True, dialog="b")
stage(300, 4, notes=True, traps=True, dialog="c")
blank(6)
gd = open(__import__("pathlib").Path(__file__).resolve().parent.parent / "godot/scripts/screens/forest_runner.gd").read()
out = re.search(r'const MAP_HEADER := """(.*?)"""', gd, re.S).group(1).rstrip("\n").split("\n")
for r in reversed(rows):
    out.append("".join(r))
open(sys.argv[1], "w").write("\n".join(out) + "\n")
txt = "".join("".join(r) for r in rows)
print(len(rows), "rows;", {c: txt.count(c) for c in "RHVD+<>A"})

# Check: between any two rows with obstacles on the paths there is time to react
# (the stage's minimum gap), so no spot asks for the impossible.
bounds = []
for i, r in enumerate(rows):
    if r[0] == "A":
        bounds.append(i)
def level_at(i):
    return 1 + sum(1 for b in bounds if b <= i)
last = None
for i, r in enumerate(rows):
    if any(c in "RHV" for c in r[1:5]):
        if last is not None and i - last < min_gap(level_at(i)):
            raise SystemExit("too tight at row %d (stage %d): %d rows after the last obstacle" % (i, level_at(i), i - last))
        last = i
print("ok: every obstacle has room to react")
