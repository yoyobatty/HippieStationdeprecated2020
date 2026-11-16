"""How stock maps build their solar arrays: each array drawn as text, its control room listed.

    python tools/mapforge/studies/solars.py [map ...]      # default meta box delta pubby

Legend: S panel, T tracker, = cable on lattice/catwalk, + lattice/catwalk with no cable, A airlock, c control console,
M SMES, t terminal, P APC, . floor, # wall, w window, space ' '. Panels per array, array size, distance from hull.
"""
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, HERE)
from forge import dmm  # noqa: E402
import stations as S  # noqa: E402


def glyph(t):
    if t is None:
        return " "
    if t.has("/obj/machinery/power/tracker"):
        return "T"
    if t.has("/obj/machinery/power/solar_control"):
        return "c"
    if t.has("/obj/machinery/power/solar"):
        return "S"
    if t.has("/obj/machinery/power/smes"):
        return "M"
    if t.has("/obj/machinery/power/terminal"):
        return "t"
    if t.has("/obj/machinery/power/apc"):
        return "P"
    if t.has("/obj/machinery/door/airlock"):
        return "A"
    lat = t.has("/obj/structure/lattice") or "catwalk" in t.tpath
    if lat:
        return "=" if t.has("/obj/structure/cable") else "+"
    tp = t.tpath
    if tp.startswith("/turf/open/space") or tp == "":
        return " "
    if "wall" in tp:
        return "#"
    if t.has("/obj/structure/window") or t.has("/obj/effect/spawner/structure/window"):
        return "w"
    return "."


def arrays(m):
    panels = [(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and
              (t.has("/obj/machinery/power/solar") or t.has("/obj/machinery/power/tracker"))
              and not t.has("/obj/machinery/power/solar_control")]
    left = set(panels)
    out = []
    while left:
        s0 = left.pop()
        comp, st = {s0}, [s0]
        while st:
            a = st.pop()
            for dx in range(-3, 4):
                for dy in range(-3, 4):
                    n = (a[0] + dx, a[1] + dy)
                    if n in left:
                        left.discard(n)
                        comp.add(n)
                        st.append(n)
        out.append(comp)
    return out


def main():
    names = sys.argv[1:] or ["meta", "box", "delta", "pubby"]
    for name in names:
        m = dmm.read(os.path.join(S.ROOT, "_maps", "map_files", S.MAPS[name]))
        print("=" * 30, name)
        for comp in sorted(arrays(m), key=lambda c: min(c)):
            xs, ys = [p[0] for p in comp], [p[1] for p in comp]
            x0, y0, x1, y1 = min(xs), min(ys), max(xs), max(ys)
            n = sum(1 for p in comp if not m.get(*p).has("/obj/machinery/power/tracker"))
            print("array at %d,%d-%d,%d  %dx%d  panels %d" % (x0, y0, x1, y1, x1 - x0 + 1, y1 - y0 + 1, n))
            for y in range(y1 + 6, y0 - 7, -1):
                print("  " + "".join(glyph(m.get(x, y)) for x in range(x0 - 8, x1 + 9)))
        rooms = Counter()
        for (x, y, z), t in m.tiles.items():
            if z == 1 and "solar" in t.apath and "maintenance" in t.apath:
                for o in t.objs:
                    if o.path.startswith("/obj/machinery") or o.path.startswith("/obj/structure"):
                        rooms[o.path] += 1
        print("solar maint areas hold:")
        for p, k in rooms.most_common(25):
            print("   %3d %s" % (k, p))


if __name__ == "__main__":
    main()
