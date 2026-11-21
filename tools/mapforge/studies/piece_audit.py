"""Audit wall pieces in built department maps: the three faults the v6 reviewers kept flagging.

    python studies/piece_audit.py                 # every data/mapforge/*_v6.dmm, counts per map
    python studies/piece_audit.py civic_v6 -v     # one map, every hit listed

  over furniture   a hung piece (pixel-shifted 20+ onto a wall) on a floor tile that holds furniture
  stacked          two hung pieces on one floor tile (not counting a button/sink/mirror pair an asset made on purpose)
  both faces       one wall tile drawn on from both sides (a hall light and a room's alarm on the same wall)

Map-wide, so it also counts pieces outside the department zone that sit in the same box; read it as a trend.
"""
import argparse
import glob
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import dmm, kit  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
FURN = ("/obj/structure/chair", "/obj/structure/table", "/obj/structure/bed", "/obj/structure/displaycase",
        "/obj/structure/statue", "/obj/structure/filingcabinet", "/obj/structure/easel", "/obj/structure/flora",
        "/obj/item/twohanded/required/kirbyplants", "/obj/machinery/disposal", "/obj/structure/rack",
        "/obj/machinery/computer", "/obj/structure/closet", "/obj/machinery/vending", "/obj/structure/bookcase",
        "/obj/structure/dresser", "/obj/machinery/suit_storage_unit", "/obj/structure/reagent_dispensers",
        "/obj/machinery/washing_machine")
PAIRS = ("/obj/machinery/button", "/obj/structure/sink", "/obj/structure/mirror")


def hung(t):
    out = []
    for o in t.objs:
        px, py = o.num("pixel_x"), o.num("pixel_y")
        if abs(px) >= 20 or abs(py) >= 20:
            out.append((o, (1 if px >= 20 else -1 if px <= -20 else 0, 1 if py >= 20 else -1 if py <= -20 else 0)))
        elif o.path.startswith("/obj/machinery/light") or o.path.startswith("/obj/machinery/camera"):
            d = o.num("dir", 2)
            # a light or camera hangs on the wall its dir points away from (a light dir 1 is on the north wall)
            off = {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0)}.get(d if o.path.startswith("/obj/machinery/light")
                                                                     else {1: 2, 2: 1, 4: 8, 8: 4}.get(d, 1), (0, -1))
            out.append((o, off))
    return out


def audit(path, verbose):
    m = dmm.read(path)
    over, stacked, both = [], [], []
    walls = {}
    for (x, y, z), t in m.tiles.items():
        if not t.tpath.startswith("/turf/open") or t.tpath.startswith("/turf/open/space"):
            continue
        hs = hung(t)
        if not hs:
            continue
        if any(o.path.startswith(FURN) or (kit.dense([o]) and not o.path.startswith("/obj/machinery/door"))
               for o in t.objs if (o, None) not in hs and all(o is not h for h, _ in hs)):
            over.append((x, y, [h.path.rsplit("/", 1)[-1] for h, _ in hs]))
        real = [h for h, _ in hs if not h.path.startswith(PAIRS)]
        if len(real) >= 2:
            stacked.append((x, y, [h.path.rsplit("/", 1)[-1] for h in real]))
        for h, (dx, dy) in hs:
            w = (x + dx, y + dy)
            walls.setdefault(w, set()).add((x, y))
    for w, froms in walls.items():
        if len(froms) >= 2:
            both.append((w[0], w[1], sorted(froms)))
    name = os.path.basename(path)[:-4]
    print("%-16s over furniture %3d   stacked %3d   both faces %3d" % (name, len(over), len(stacked), len(both)))
    if verbose:
        for x, y, what in over:
            print("  over  %d,%d %s" % (x, y, ", ".join(what)))
        for x, y, what in stacked:
            print("  stack %d,%d %s" % (x, y, ", ".join(what)))
        for x, y, froms in both:
            print("  both  wall %d,%d from %s" % (x, y, " ".join("%d,%d" % f for f in froms)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="*")
    ap.add_argument("-v", action="store_true")
    a = ap.parse_args()
    paths = [os.path.join(ROOT, "data", "mapforge", n + ".dmm") for n in a.names] or \
        sorted(glob.glob(os.path.join(ROOT, "data", "mapforge", "*_v6.dmm")))
    for p in paths:
        audit(p, a.v)


if __name__ == "__main__":
    main()
