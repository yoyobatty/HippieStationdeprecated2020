"""Trace a zone of an existing map into a blueprint skeleton to design over.

    python tools/mapforge/forge/trace.py x1 y1 x2 y2 /area/a,/area/b [--pad-walls]

Prints LAYOUT (shell: # wall, R r-wall, = window, % r-window, D door, . floor, ~ outside the zone), ROOMS (a letter
per area) and a DISPOSALS overlay (B bin, + pipe) so the design can keep to the carried-over disposals line.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from forge import dmm  # noqa: E402
from forge.survey import HIPPIE  # noqa: E402


def main():
    x1, y1, x2, y2 = map(int, sys.argv[1:5])
    areas = sys.argv[5].split(",")
    m = dmm.read(HIPPIE)
    letters = "abcdefghijklmnop"
    amap = {a: letters[i] for i, a in enumerate(areas)}
    lay, rooms, disp = [], [], []
    for y in range(y2, y1 - 1, -1):
        a_, b_, c_ = [], [], []
        for x in range(x1, x2 + 1):
            t = m.get(x, y)
            if t.apath not in amap:
                a_.append("~"), b_.append("~"), c_.append("~")
                continue
            tp = t.tpath
            if t.has("/obj/machinery/door"):
                ch = "D"
            elif t.has("/obj/effect/spawner/structure/window/reinforced"):
                ch = "%"
            elif t.has("/obj/effect/spawner/structure/window") or t.has("/obj/structure/grille"):
                ch = "="
            elif tp.startswith("/turf/closed/wall/r_wall"):
                ch = "R"
            elif tp.startswith("/turf/closed"):
                ch = "#"
            else:
                ch = "."
            a_.append(ch)
            b_.append(amap[t.apath])
            c_.append("B" if t.has("/obj/machinery/disposal") else "+" if t.has("/obj/structure/disposalpipe") else ch if ch in "#R" else ".")
        lay.append("".join(a_)), rooms.append("".join(b_)), disp.append("".join(c_))
    print("ORIGIN = (%d, %d)" % (x1, y1))
    for name, g in (("LAYOUT", lay), ("ROOMS", rooms), ("DISPOSALS", disp)):
        print('%s = """' % name)
        print("\n".join(g))
        print('"""')
    for a, l in amap.items():
        print(l, a)


if __name__ == "__main__":
    main()
