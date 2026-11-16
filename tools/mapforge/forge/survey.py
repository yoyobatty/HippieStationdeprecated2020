"""ASCII survey of a map region: structure, areas, and where pipes/cables cross the region edge.

    python tools/mapforge/forge/survey.py x1 y1 x2 y2 [map.dmm]
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from forge import dmm  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
HIPPIE = os.path.join(ROOT, "_maps", "map_files", "HippieStation", "hippiestation.dmm")


def struct_char(t):
    tp = t.tpath
    if t.has("/obj/machinery/door/airlock") or t.has("/obj/machinery/door/window") or t.has("/obj/machinery/door/poddoor"):
        return "D"
    if t.has("/obj/effect/spawner/structure/window") or t.has("/obj/structure/window"):
        return "="
    if tp.startswith("/turf/closed/wall/r_wall"):
        return "R"
    if tp.startswith("/turf/closed"):
        return "#"
    if tp.startswith("/turf/open/space"):
        return " "
    if t.has("/obj/structure/table"):
        return "t"
    if t.has("/obj/machinery") or t.has("/obj/structure"):
        return "o"
    return "."


def pipes(t):
    s = ""
    if any("supply" in o.path and "atmospherics" in o.path for o in t.objs):
        s += "s"
    if any("scrubber" in o.path and "atmospherics" in o.path for o in t.objs):
        s += "c"
    if t.has("/obj/structure/cable"):
        s += "w"
    return s


def main():
    x1, y1, x2, y2 = map(int, sys.argv[1:5])
    m = dmm.read(sys.argv[5] if len(sys.argv) > 5 else HIPPIE)
    areas = {}
    letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    print("structure (y top->bottom)            areas")
    for y in range(y2, y1 - 1, -1):
        row, arow = [], []
        for x in range(x1, x2 + 1):
            t = m.get(x, y)
            row.append(struct_char(t))
            a = t.apath
            if a not in areas:
                areas[a] = letters[len(areas) % len(letters)]
            arow.append(areas[a])
        print("%3d %s   %s" % (y, "".join(row), "".join(arow)))
    print("    " + "".join(str(x % 10) for x in range(x1, x2 + 1)))
    for a, l in areas.items():
        print(l, a)
    print("edge crossings (s=supply c=scrubbers w=cable):")
    for x in range(x1, x2 + 1):
        for y in (y1, y2):
            p = pipes(m.get(x, y))
            if p:
                print("  %d,%d %s" % (x, y, p))
    for y in range(y1, y2 + 1):
        for x in (x1, x2):
            p = pipes(m.get(x, y))
            if p:
                print("  %d,%d %s" % (x, y, p))


if __name__ == "__main__":
    main()
