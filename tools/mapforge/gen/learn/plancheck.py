"""Structure check of department floor plans (gen/learn/floorplan.plan) before anything is painted: fast (a plan
takes well under a second), so a layout change is checked over many seeds without a station build.

  python tools/mapforge/gen/learn/plancheck.py                 every department, 6 seeds each
  python tools/mapforge/gen/learn/plancheck.py --dept cargo    one department, more frames and seeds, its hub figures
  python tools/mapforge/gen/learn/plancheck.py --dept cargo -v each failing plan
  python tools/mapforge/gen/learn/plancheck.py --dump cargo 341 20 "x|c"    one plan as text

Faults counted per plan (0 wanted of each):
  overlap, split room, rooms touch (no wall between two rooms), room open to corridor, no wall ring (floor on the
  block's edge), door into wall, room lost its door, diagonal walls (a 2x2 with wall on one diagonal and floor on the
  other: the user's wall-join ruling), P.floor out of sync, big machine room under 5x5 (the gravity generator), room reached only through maint.
Hub figures (--dept, departments in floorplan.HUB): the hub room's size, whether it is on the block's back wall,
second rooms of its type, the smallest room of each HUB_SIDE type.
"""
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", ".."))
import floorplan as FP      # noqa: E402
import reshape as RS        # noqa: E402

N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
N8 = N4 + ((1, 1), (1, -1), (-1, 1), (-1, -1))
FRAMES = (("medical", 1100, 45), ("security", 1100, 45), ("science", 1100, 45), ("engineering", 900, 40),
          ("cargo", 700, 36), ("service", 600, 34), ("civic", 700, 36), ("command", 800, 38), ("dorms", 300, 24),
          ("medical", 600, 30), ("science", 600, 30), ("cargo", 341, 14), ("cargo", 341, 20), ("cargo", 341, 26))
DEPT_FRAMES = ((250, 14), (250, 20), (341, 14), (341, 17), (341, 20), (341, 26), (500, 20), (500, 30), (700, 36))


def check(P):
    bad = Counter()
    owner = {}
    for rm in P.rooms:
        for c in rm["F"]:
            if c in owner:
                bad["overlap"] += 1
            owner[c] = rm["id"]
        if not RS._connected(rm["F"]):
            bad["split room"] += 1
    doors = set(P.doors) | set(P.front)
    walk = set(owner) | set(P.corr) | doors
    for c, rid in owner.items():
        for dx, dy in N4:
            n = (c[0] + dx, c[1] + dy)
            if n in owner and owner[n] != rid:
                bad["rooms touch"] += 1
            if n in P.corr:
                bad["room open to corridor"] += 1
        for dx, dy in N8:
            if (c[0] + dx, c[1] + dy) not in P.cells:
                bad["no wall ring"] += 1
    for c in P.corr:
        for dx, dy in N8:
            n = (c[0] + dx, c[1] + dy)
            if n not in P.cells and n[1] >= 0:
                bad["corridor no wall ring"] += 1
    for d in P.doors:
        sides = [(d[0] + dx, d[1] + dy) in walk for dx, dy in N4]
        if not ((sides[0] and sides[1]) or (sides[2] and sides[3])):
            bad["door into wall"] += 1
    for rm in P.rooms:
        d = rm.get("door")
        if d is not None and not any((d[0] + dx, d[1] + dy) in rm["F"] for dx, dy in N4):
            bad["room lost its door"] += 1
    for c in P.cells:
        q4 = (c, (c[0] + 1, c[1]), (c[0], c[1] - 1), (c[0] + 1, c[1] - 1))
        w = [q in P.cells and q not in walk and q not in P.space for q in q4]
        f = [q in walk for q in q4]
        if (w[0] and w[3] and f[1] and f[2]) or (w[1] and w[2] and f[0] and f[3]):
            bad["diagonal walls"] += 1
    if P.floor != set(owner):
        bad["P.floor out of sync"] += 1
    # every room reached from the front without walking through the department's maint rooms (the CE's back room
    # opened onto a maint store and the gate failed "ways in", f45)
    maint_ = {c for rm in P.rooms if rm["area"].startswith("/area/maintenance") for c in rm["F"]}
    ok_ = (set(owner) | set(P.corr) | doors) - maint_
    seen_ = set(P.front)
    todo_ = list(P.front)
    while todo_:
        c = todo_.pop()
        for dx, dy in N4:
            n = (c[0] + dx, c[1] + dy)
            if n in ok_ and n not in seen_:
                seen_.add(n)
                todo_.append(n)
    for rm in P.rooms:
        if not rm["area"].startswith("/area/maintenance") and rm["F"] and not rm["F"] & seen_                 and rm["area"] not in FP.maint_only_ok():      # (the janitor's closet is so on stock maps)
            bad["room reached only through maint"] += 1
    # a room with a machine bigger than its tile (the gravity generator's 3x3) holds a 5 x 5 rectangle
    for rm in P.rooms:
        if FP._big_kit(rm["area"]) and not rm.get("piece") and not rm.get("back"):
            x0, y0, x1, y1 = FP._max_rect(rm["F"])
            if min(x1 - x0, y1 - y0) + 1 < 5:
                bad["big machine room under 5x5"] += 1
    return bad


def hub_stats(P):
    """{figure: value} of a hub plan (floorplan.HUB)."""
    ha = FP.HUB.get(P.dept)
    if not ha:
        return {}
    rooms = [rm for rm in P.rooms if rm["area"] == ha]
    ymax = max(c[1] for c in P.cells)
    hub = max(rooms, key=lambda rm: len(rm["F"]), default=None)
    out = {"hub": len(hub["F"]) if hub else 0, "hubs": len(rooms),
           "on back wall": bool(hub) and any(c[1] == ymax - 1 for c in hub["F"]),
           "hub doors": sum(1 for d in P.doors if hub and any((d[0] + dx, d[1] + dy) in hub["F"] for dx, dy in N4))}
    for a in FP.HUB_SIDE.get(P.dept, ()):
        v = [len(rm["F"]) for rm in P.rooms if rm["area"] == a]
        out[a.rsplit("/", 1)[1]] = max(v) if v else 0
        out[a.rsplit("/", 1)[1] + " back"] = any(rm["area"] == a and any(c[1] == ymax - 1 for c in rm["F"])
                                                 for rm in P.rooms)
    return out


def dump(P):
    owner, names = {}, {}
    for i, rm in enumerate(P.rooms):
        ch = "abcdefghijklmnopqrstuvwxyzABCEFGHIJKLMNOPQRSTUVWXYZ0123456789"[i % 60]
        names[ch] = (rm["area"].replace("/area/", ""), len(rm["F"]), rm.get("door"))
        for c in rm["F"]:
            owner[c] = ch
    xs = [c[0] for c in P.cells]
    ys = [c[1] for c in P.cells]
    for y in range(max(ys), min(ys) - 1, -1):
        row = ""
        for x in range(min(xs), max(xs) + 1):
            c = (x, y)
            row += "+" if c in P.doors or c in P.front else owner.get(c) or ("." if c in P.corr else
                                                                              "~" if c in P.space else
                                                                              "#" if c in P.cells else " ")
        print("%2d %s" % (y, row))
    for ch, v in names.items():
        print(ch, v)


def main():
    a = sys.argv[1:]
    if "--dump" in a:
        i = a.index("--dump")
        dump(FP.plan(a[i + 1], int(a[i + 2]), int(a[i + 3]), 36, a[i + 4]))
        return
    verbose = "-v" in a
    dept = a[a.index("--dept") + 1] if "--dept" in a else None
    frames = [(dept, t, w) for t, w in DEPT_FRAMES] if dept else FRAMES
    seeds = range(1, 9) if dept else range(1, 7)
    tot, n = Counter(), 0
    for d, tgt, W in frames:
        hs = []
        for sd in seeds:
            P = FP.plan(d, tgt, W, 36, "chk|%d" % sd)
            if P is None:
                continue
            n += 1
            b = check(P)
            tot.update(b)
            hs.append(hub_stats(P))
            if b and verbose:
                print(d, tgt, W, sd, dict(b))
        if dept and hs and hs[0]:
            line = []
            for k in hs[0]:
                v = [h[k] for h in hs]
                line.append("%s %s" % (k, ("%d/%d" % (sum(v), len(v))) if isinstance(v[0], bool) else
                                       "%d-%d" % (min(v), max(v))))
            print("target %4d W %2d: %s" % (tgt, W, ", ".join(line)))
    print(n, "plans;", dict(tot) or "no faults")


if __name__ == "__main__":
    main()
