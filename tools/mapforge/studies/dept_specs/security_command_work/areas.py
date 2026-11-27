"""Scratch: list a map's areas (z 1) with group, tiles, bbox; optional ASCII group map.

    python areas.py <dmm> [--ascii out.txt] [--groups security,command]
"""
import argparse
import os
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
MF = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, MF)
sys.path.insert(0, os.path.join(MF, "studies"))
from forge import dmm  # noqa: E402
import stations as ST  # noqa: E402

CH = {"security": "S", "command": "C", "medical": "M", "science": "R", "engineering": "E", "atmos": "A", "cargo": "Q",
      "service": "V", "civic": "L", "dorms": "D", "ai": "I", "hall": "+", "maint": ".", "escape": "X", "arrivals": "Y"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dmm")
    ap.add_argument("--ascii")
    ap.add_argument("--groups", default="")
    a = ap.parse_args()
    m = dmm.read(a.dmm)
    by = defaultdict(list)
    for (x, y, z), t in m.tiles.items():
        if z != 1:
            continue
        by[t.apath].append((x, y))
    gs = set(a.groups.split(",")) if a.groups else None
    for ar in sorted(by):
        g = ST.group_of(ar)
        if gs and g not in gs:
            continue
        ts = by[ar]
        fl = [p for p in ts if m.get(*p).tpath.startswith("/turf/open") and not m.get(*p).tpath.startswith("/turf/open/space")]
        xs = [p[0] for p in ts]
        ys = [p[1] for p in ts]
        print("%-12s %-55s %4d fl %4d  x%d-%d y%d-%d" % (g, ar, len(ts), len(fl), min(xs), max(xs), min(ys), max(ys)))
    if a.ascii:
        W = max(x for (x, y, z) in m.tiles if z == 1)
        H = max(y for (x, y, z) in m.tiles if z == 1)
        rows = []
        for y in range(H, 0, -1):
            row = []
            for x in range(1, W + 1):
                t = m.tiles.get((x, y, 1))
                if t is None or t.apath.startswith("/area/space") and not t.tpath.startswith("/turf/closed"):
                    row.append(" ")
                    continue
                if t.tpath.startswith("/turf/closed"):
                    row.append("#")
                    continue
                if any(o.path.startswith("/obj/machinery/door/airlock") for o in t.objs):
                    row.append("D")
                    continue
                g = ST.group_of(t.apath)
                c = CH.get(g, "?")
                row.append(c.lower() if c.isalpha() else c)
            rows.append("%3d " % y + "".join(row))
        with open(a.ascii, "w", newline="") as f:
            f.write("\n".join(rows) + "\n")


if __name__ == "__main__":
    main()
