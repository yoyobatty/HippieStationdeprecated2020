"""Scratch: list each area under given prefixes with bounds, tile count and object counts (minus pipes/cables).

    python dump_areas.py <dmm> /area/science /area/quartermaster ...
"""
import os
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
MF = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, MF)
from forge import dmm  # noqa: E402

SKIP = ("/obj/structure/cable", "/obj/machinery/atmospherics/pipe", "/obj/structure/disposalpipe",
        "/obj/effect/turf_decal", "/obj/effect/landmark/event_spawn", "/obj/machinery/door/firedoor")


def main():
    path = sys.argv[1]
    prefixes = sys.argv[2:]
    m = dmm.read(path)
    by = defaultdict(list)
    for (x, y, z), t in m.tiles.items():
        if z != 1:
            continue
        a = t.apath
        if any(a == p or a.startswith(p + "/") or a.startswith(p) for p in prefixes):
            by[a].append((x, y, t))
    for a in sorted(by):
        tiles = by[a]
        xs = [p[0] for p in tiles]
        ys = [p[1] for p in tiles]
        c = Counter()
        for x, y, t in tiles:
            for o in t.objs:
                if o.path.startswith(SKIP):
                    continue
                c[o.path] += 1
        floors = sum(1 for x, y, t in tiles if t.tpath.startswith("/turf/open"))
        print("== %s  tiles %d floor %d  x %d-%d y %d-%d" % (a, len(tiles), floors, min(xs), max(xs), min(ys), max(ys)))
        for p, n in sorted(c.items()):
            print("   %3d %s" % (n, p))


if __name__ == "__main__":
    main()
