"""ASCII plan of a map region: one letter per area (legend printed), # wall, = window, D airlock, d windoor desk,
f firelock-only floor, digits/marks for key kit. For reading a department's joins tile by tile.

    python tools/mapforge/studies/dept_specs/medical_work/ascii.py <dmm> x0 y0 x1 y1
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.abspath(os.path.join(HERE, "..", "..", "..")))
from forge import corpus as CO, dmm, function as FN  # noqa: E402

MARK = [("/obj/structure/table/optable", "O"), ("/obj/machinery/atmospherics/components/unary/cryo_cell", "C"),
        ("/obj/machinery/sleeper", "S"), ("/obj/machinery/stasis", "s"), ("/obj/machinery/chem_dispenser", "X"),
        ("/obj/machinery/chem_master", "M"), ("/obj/machinery/dna_scannernew", "N"), ("/obj/machinery/clonepod", "P"),
        ("/obj/machinery/computer", "c"), ("/obj/structure/bodycontainer/morgue", "m"), ("/obj/machinery/shower", "w"),
        ("/obj/structure/closet", "L"), ("/obj/machinery/vending", "V"), ("/obj/structure/bed", "b"),
        ("/obj/machinery/smartfridge", "F"), ("/obj/machinery/atmospherics/components/unary/thermomachine", "Z"),
        ("/obj/structure/table", "t"), ("/obj/structure/sink", "k"), ("/mob/living/carbon/monkey", "y")]


def plan(m, x0, y0, x1, y1):
    letters = {}
    nxt = iter("abcdeghijklnopqruvxz" + "ABEGHIJKQRTUWY0123456789")
    rows = []
    for y in range(y1, y0 - 1, -1):
        row = "%3d " % y
        for x in range(x0, x1 + 1):
            t = m.get(x, y)
            if t is None:
                row += " "
                continue
            if t.has("/obj/machinery/door/airlock"):
                row += "D"
                continue
            if t.has("/obj/machinery/door/window") and t.has("/obj/structure/table"):
                row += "d"
                continue
            if t.tpath.startswith("/turf/closed"):
                row += "#"
                continue
            if CO.solid(t):
                row += "="
                continue
            if t.tpath.startswith("/turf/open/space"):
                row += "."
                continue
            ch = None
            for pre, c in MARK:
                if t.has(pre):
                    ch = c
                    break
            if ch is None:
                a = t.apath
                if a not in letters:
                    letters[a] = next(nxt)
                ch = letters[a].lower() if False else letters[a]
                ch = "_" if a.startswith("/area/hallway") else ("~" if a.startswith("/area/maintenance") else ch)
            row += ch
        rows.append(row)
    head = "    " + "".join(str(x % 10) for x in range(x0, x1 + 1))
    return "\n".join([head] + rows + [head]) + "\n" + "\n".join("  %s %s" % (v, k) for k, v in letters.items())


if __name__ == "__main__":
    m = dmm.read(sys.argv[1])
    print(plan(m, *[int(a) for a in sys.argv[2:6]]))
