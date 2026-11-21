"""Dump a box of a built department map, tile by tile: x y area turf | objects (with key vars).

    python studies/tile_dump.py dorms_v6 120 88 139 113 [--grep sink,mirror] [--ascii]

Reads data/mapforge/<name>.dmm. --grep keeps tiles holding an object whose path contains any of the words.
--ascii draws the box instead: # wall, . floor, : window, + door, s space, letters for the first object's type.
Used by the v6 review loop to answer reviewer findings with exact tiles before patching assets.
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import dmm  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
KEYS = ("dir", "pixel_x", "pixel_y", "id", "id_tag", "name")


def short(o):
    vs = [(k, v) for k, v in o.vars if k in KEYS]
    tail = "/".join(o.path.split("/")[-2:])
    return tail + ("{%s}" % ",".join("%s=%s" % kv for kv in vs) if vs else "")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("name")
    ap.add_argument("box", nargs=4, type=int)
    ap.add_argument("--grep", default="")
    ap.add_argument("--ascii", action="store_true")
    a = ap.parse_args()
    m = dmm.read(os.path.join(ROOT, "data", "mapforge", a.name + ".dmm"))
    x0, y0, x1, y1 = a.box
    words = [w for w in a.grep.split(",") if w]
    if a.ascii:
        print("    " + "".join(str(x % 10) for x in range(x0, x1 + 1)))
        for y in range(y1, y0 - 1, -1):
            row = ""
            for x in range(x0, x1 + 1):
                t = m.get(x, y)
                if t is None:
                    row += " "
                elif t.tpath.startswith("/turf/closed"):
                    row += "#"
                elif t.tpath.startswith("/turf/open/space"):
                    row += "s"
                elif t.has("/obj/machinery/door"):
                    row += "+"
                elif t.has("/obj/effect/spawner/structure/window") or t.has("/obj/structure/grille"):
                    row += ":"
                else:
                    big = [o for o in t.objs if not o.path.startswith(("/obj/effect", "/obj/machinery/atmospherics",
                                                                        "/obj/structure/cable", "/obj/machinery/light"))]
                    row += big[0].path.split("/")[-1][0] if big else "."
            print("%3d %s" % (y, row))
        return
    for y in range(y1, y0 - 1, -1):
        for x in range(x0, x1 + 1):
            t = m.get(x, y)
            if t is None:
                continue
            objs = [o for o in t.objs if not o.path.startswith(("/obj/machinery/atmospherics/pipe", "/obj/structure/cable",
                                                                 "/obj/effect/turf_decal"))]
            if words and not any(w in o.path for o in objs for w in words):
                continue
            print(x, y, t.apath.split("/")[-1], t.tpath.split("/")[-1], "|", "; ".join(short(o) for o in objs))


if __name__ == "__main__":
    main()
