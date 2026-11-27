"""Room size and shape variety: what the stock maps have, and what a generated map or a department plan has.

The user 2026-11-26: "I notice you don't go creative with room size and shape, why is that? ... Yes, do it then, fix
it." Measured then: stock maps 140-200 rooms, sizes p10/median/p90 6 / 20-22 / 60-81, spread (stdev / mean) 0.95-1.28;
ours 96 rooms, 9 / 28 / 63, 0.74; and only three shapes (rectangle, L from a wall jog, a rectangle with a corner
closet cut out).

Shape classes of a room's floor (its cells against its bounding box):
    rect    fills its box
    L       one corner of the box missing (one rectangle)
    notch   a bite out of one side, not at a corner (a U / C: the room wraps a closet, a booth, a pillar)
    T       two corners missing on the same side
    Z       two corners missing, opposite
    other   three or more pieces missing, or ragged

    python tools/mapforge/gen/learn/variety.py                       # the stock maps
    python tools/mapforge/gen/learn/variety.py <dmm> [...]           # generated maps
    python tools/mapforge/gen/learn/variety.py --plans [n seeds]     # department plans (gen/learn/floorplan.py)
    from gen.learn import variety; variety.shape(F); variety.model() -> learned mixes (data/mapforge/learn/variety.json)
"""
import json
import os
import statistics
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(HERE, "..", "..", "studies"))
from forge import corpus as CO, dmm  # noqa: E402

OUT = os.path.join(CO.ROOT, "data", "mapforge", "learn", "variety.json")
VERSION = 1
N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
CLASSES = ("rect", "L", "notch", "T", "Z", "other")
SIZE_CLASSES = ((6, "6-11"), (12, "12-23"), (24, "24-47"), (48, "48+"))


def size_class(n):
    k = None
    for lo, name in SIZE_CLASSES:
        if n >= lo:
            k = name
    return k


def shape(F):
    """The shape class of a set of cells."""
    xs = [c[0] for c in F]
    ys = [c[1] for c in F]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    miss = {(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)} - set(F)
    if not miss:
        return "rect"
    comps = []
    left = set(miss)
    while left:
        s = left.pop()
        comp, q = {s}, [s]
        while q:
            p = q.pop()
            for dx, dy in N4:
                n = (p[0] + dx, p[1] + dy)
                if n in left:
                    left.discard(n)
                    comp.add(n)
                    q.append(n)
        comps.append(comp)
    if len(comps) > 2:
        return "other"
    kinds = []
    for comp in comps:
        cx = [c[0] for c in comp]
        cy = [c[1] for c in comp]
        if len(comp) != (max(cx) - min(cx) + 1) * (max(cy) - min(cy) + 1):
            return "other"
        edges = (min(cx) == x0, max(cx) == x1, min(cy) == y0, max(cy) == y1)
        n_e = sum(edges)
        if n_e >= 3:
            return "other"
        if n_e == 2 and not ((edges[0] and edges[1]) or (edges[2] and edges[3])):
            kinds.append(("corner", (edges[0], edges[2])))       # (west?, south?)
        elif n_e == 1:
            kinds.append(("side", None))
        else:
            return "other"
    if len(kinds) == 1:
        return "L" if kinds[0][0] == "corner" else "notch"
    if all(k[0] == "corner" for k in kinds):
        (w0, s0), (w1, s1) = kinds[0][1], kinds[1][1]
        return "Z" if (w0 != w1 and s0 != s1) else "T"
    return "other"


def _rooms_of_map(m):
    import placestudy as PS
    return [(a, F) for a, F in PS.pieces_of(m) if a not in PS.CORRIDOR_AREAS]


def measure(rooms):
    """rooms: [(area, cells)] -> dict of the variety numbers."""
    sizes = sorted(len(F) for _, F in rooms)
    if not sizes:
        return {}
    q = lambda f: sizes[int(f * (len(sizes) - 1))]  # noqa: E731
    sh = Counter(shape(F) for _, F in rooms)
    n = float(len(rooms))
    asp = []
    for _, F in rooms:
        xs = [c[0] for c in F]
        ys = [c[1] for c in F]
        w, h = max(xs) - min(xs) + 1, max(ys) - min(ys) + 1
        asp.append(max(w, h) / float(min(w, h)))
    return dict(rooms=len(rooms), p10=q(0.1), p25=q(0.25), p50=q(0.5), p75=q(0.75), p90=q(0.9), max=sizes[-1],
                cv=round(statistics.pstdev(sizes) / statistics.mean(sizes), 2),
                shapes={k: round(sh[k] / n, 2) for k in CLASSES},
                long=round(sum(1 for a in asp if a >= 2.5) / n, 2))


def build():
    """Learn from the stock maps: per size class the shape mix; per room type its main-room sizes and its shapes."""
    import roomdb
    by_size = defaultdict(Counter)
    by_type = defaultdict(Counter)
    maps = {}
    for rel in CO.MAPS:
        p = os.path.join(CO.ROOT, "_maps", "map_files", rel)
        if not os.path.exists(p):
            continue
        rooms = _rooms_of_map(dmm.read(p))
        maps[os.path.basename(p)] = measure(rooms)
        for a, F in rooms:
            s = shape(F)
            by_size[size_class(len(F))][s] += 1
            by_type[a][s] += 1
    sizes = defaultdict(list)
    for r in roomdb.rooms():
        if r.get("main"):
            sizes[r["area"]].append(r["tiles"])
    out = dict(version=VERSION, maps=maps,
               by_size={k: dict(c) for k, c in by_size.items()},
               by_type={a: dict(c) for a, c in by_type.items() if sum(c.values()) >= 4},
               sizes={a: sorted(v) for a, v in sizes.items() if len(v) >= 3})
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump(out, open(OUT, "w"))
    return out


_M = None


def model():
    global _M
    if _M is None:
        if os.path.exists(OUT):
            d = json.load(open(OUT))
            if d.get("version") == VERSION:
                _M = d
        if _M is None:
            _M = build()
    return _M


def shape_mix(area, n):
    """The stock shape mix for a room of this type and size: its type's own when it has 8+ stock rooms, blended half
    and half with its size class's; else the size class's."""
    M = model()
    sc = M["by_size"].get(size_class(n) or "6-11", {})
    tot = float(sum(sc.values())) or 1.0
    mix = {k: sc.get(k, 0) / tot for k in CLASSES}
    t = M["by_type"].get(area)
    if t and sum(t.values()) >= 8:
        tt = float(sum(t.values()))
        mix = {k: 0.5 * mix[k] + 0.5 * t.get(k, 0) / tt for k in CLASSES}
    return mix


def plans(n_seeds=4, target=None):
    """Variety over department plans (rooms of all departments of n_seeds plans each, as one station would have)."""
    import floorplan as FP
    rooms = []
    for d, tgt, W in (("medical", 1100, 45), ("security", 1100, 45), ("science", 1100, 45), ("engineering", 900, 40),
                      ("cargo", 700, 36), ("service", 600, 34), ("civic", 700, 36), ("command", 800, 38),
                      ("dorms", 300, 24)):
        for sd in range(1, n_seeds + 1):
            P = FP.plan(d, target or tgt, W, 36, "var|%d" % sd)
            if P is not None:
                rooms += [(rm["area"], rm["F"]) for rm in P.rooms if len(rm["F"]) >= 6]
    return rooms


def _line(name, d):
    return "%-22s rooms %3d  size p10/25/50/75/90/max %2d/%2d/%2d/%2d/%3d/%3d  cv %.2f  %s  long %.2f" % (
        name[:22], d["rooms"], d["p10"], d["p25"], d["p50"], d["p75"], d["p90"], d["max"], d["cv"],
        " ".join("%s %.2f" % (k, d["shapes"][k]) for k in CLASSES), d["long"])


if __name__ == "__main__":
    args = sys.argv[1:]
    if args and args[0] == "--plans":
        n = int(args[1]) if len(args) > 1 else 4
        d = measure(plans(n))
        d["rooms"] = d["rooms"] // n
        print(_line("plans (per station)", d))
    elif args:
        for p in args:
            print(_line(os.path.basename(p), measure(_rooms_of_map(dmm.read(p)))))
    else:
        M = build()
        for k, d in M["maps"].items():
            print(_line(k, d))
        print("by size class:")
        for k, c in sorted(M["by_size"].items()):
            t = float(sum(c.values()))
            print("  %-6s n %4d  %s" % (k, t, " ".join("%s %.2f" % (s, c.get(s, 0) / t) for s in CLASSES)))
