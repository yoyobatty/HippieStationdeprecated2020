"""Scratch: a text picture of a map region, for reading layouts without a render.

    python asciimap.py <dmm> x0 y0 x1 y1

Floor tiles show their area's letter (legend below; lower case = first letter of a new area), and on top:
  #  wall        %  window (spawner/grille/fulltile)   D  airlock   w  windoor   =  table+windoor (desk)
  B  blast door/shutters   c  conveyor   f  plastic flaps   t  table   M  machinery (dense)   O  structure (dense)
  .  space     :  lattice/catwalk   C  camera    m  mass driver   S  slime
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MF = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, MF)
from forge import corpus as CO, dmm, function as FN  # noqa: E402

LETTERS = "abcdefghijklmnopqrstuvwxyzABEFGHIJKLNPQRTUVXYZ0123456789"


def ch(t, legend):
    if t is None:
        return " "
    if t.tpath.startswith("/turf/open/space"):
        return ":" if t.has("/obj/structure/lattice") else "."
    if t.tpath.startswith("/turf/closed"):
        return "#"
    if t.has("/obj/machinery/door/poddoor"):
        return "B"
    if t.has("/obj/machinery/door/window") and t.has("/obj/structure/table"):
        return "="
    if t.has("/obj/machinery/door/window"):
        return "w"
    if t.has("/obj/machinery/door/airlock") or t.has("/obj/machinery/door/unpowered"):
        return "D"
    if CO.solid(t) or t.has("/obj/structure/window"):
        return "%"
    if t.has("/obj/machinery/mass_driver"):
        return "m"
    if t.has("/obj/machinery/conveyor"):
        return "c"
    if t.has("/obj/structure/plasticflaps"):
        return "f"
    if t.has("/mob/living/simple_animal/slime"):
        return "S"
    if t.has("/obj/structure/table"):
        return "t"
    dense = [o for o in t.objs if FN.is_dense(o)]
    if dense:
        return "M" if dense[0].path.startswith("/obj/machinery") else "O"
    if any(o.path.startswith("/obj/machinery/camera") for o in t.objs):
        return "C"
    a = t.apath
    if a not in legend:
        legend[a] = LETTERS[len(legend) % len(LETTERS)]
    return legend[a]


def main():
    m = dmm.read(sys.argv[1])
    x0, y0, x1, y1 = map(int, sys.argv[2:6])
    legend = {}
    rows = []
    for y in range(y1, y0 - 1, -1):
        rows.append("%4d " % y + "".join(ch(m.get(x, y), legend) for x in range(x0, x1 + 1)))
    head = "     " + "".join(str(x // 10 % 10) if x % 10 == 0 else " " for x in range(x0, x1 + 1))
    head2 = "     " + "".join(str(x % 10) for x in range(x0, x1 + 1))
    print(head)
    print(head2)
    print("\n".join(rows))
    for a, c in legend.items():
        print("  %s %s" % (c, a))


if __name__ == "__main__":
    main()
