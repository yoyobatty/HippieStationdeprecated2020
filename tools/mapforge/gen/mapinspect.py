"""Inspection numbers for what a player sees wrong in a generated station, each against the stock maps.

    python tools/mapforge/gen/mapinspect.py gen_c80_s1              # data/mapforge/<name>.dmm
    python tools/mapforge/gen/mapinspect.py --stock                 # the look maps' numbers (the bands)
    python tools/mapforge/gen/mapinspect.py gen_c80_s1 --where double   # list the spots of one finding
    from gen import mapinspect; mapinspect.measure(m) -> {name: value}, mapinspect.spots(m) -> {name: [(x, y)]}

Findings (the user's, 2026-11-25: "inappropriate double walls ... no awkward rooms, no random crowbars in that big
open floor"):
  double     two walls side by side between two floors of the station (floor, wall, wall, floor in a line), runs of 2+
             tiles, per 1000 wall tiles. Hull and glass don't count; a door in it doesn't either.
  thick      three or more walls between two floors, per 1000 wall tiles.
  loose      items lying on bare floor (no table, rack, closet, crate or machine under them) away from any wall, per
             1000 floor tiles; maint and its litter not counted.
  open_loose the same, on the open middle of a room of 60+ tiles (two tiles or more from its walls): the crowbar in
             the middle of Atmospherics.
  bare_big   rooms of 60+ tiles with under 4% of their floor under furniture or machines.
"""
import argparse
import os
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import dmm, kit, parse  # noqa: E402

N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
STOCK = ("MetaStation", "DeltaStation", "BoxStation", "HippieStation")
UNDER = ("/obj/structure/table", "/obj/structure/rack", "/obj/structure/closet", "/obj/machinery",
         "/obj/structure/bed", "/obj/structure/chair", "/obj/structure/displaycase", "/obj/structure/safe",
         "/obj/structure/filingcabinet", "/obj/structure/dresser", "/obj/structure/bookcase")


def _floor(t):
    return t is not None and t.tpath.startswith("/turf/open") and not t.tpath.startswith("/turf/open/space")


def _wall(t):
    return t is not None and t.tpath.startswith("/turf/closed") and not t.has("/obj/machinery/door")


def _station(t):
    return _floor(t) and not t.apath.startswith(("/area/space", "/area/solar", "/area/shuttle"))


def _glass(t):
    return any(o.path.startswith(parse.GLASS) for o in t.objs)


def spots(m):
    out = defaultdict(list)
    walls = [(x, y) for (x, y, z), t in m.tiles.items() if _wall(t)]
    seen2 = set()
    for (x, y) in walls:
        for dx, dy in ((1, 0), (0, 1)):
            # count a wall pair once, from its low end: floor, wall, wall, floor
            a, w2, b = (x - dx, y - dy), (x + dx, y + dy), (x + 2 * dx, y + 2 * dy)
            ta, t2, tb = m.get(*a), m.get(*w2), m.get(*b)
            if _station(ta) and _wall(t2) and _station(tb) and not _glass(m.get(x, y)) and not _glass(t2):
                out["double"].append((x, y))
                seen2 |= {(x, y), w2}
            elif _station(ta) and _wall(t2):
                # three or more
                k, run = 2, [(x, y), w2]
                while k < 6:
                    q = (x + k * dx, y + k * dy)
                    tq = m.get(*q)
                    if _wall(tq):
                        run.append(q)
                        k += 1
                        continue
                    if _station(tq) and k >= 3:
                        out["thick"].append((x, y))
                    break
    # a double wall counts where 2+ such pairs run side by side (one pair is a pillar or a corner)
    dset = set(out["double"])
    out["double"] = [p for p in out["double"] if any((p[0] + dx, p[1] + dy) in dset for dx, dy in N4)]
    # loose items
    by_room = defaultdict(list)
    for (x, y, z), t in m.tiles.items():
        if not _station(t) or t.apath.startswith("/area/maintenance"):
            continue
        by_room[t.apath].append((x, y))
        items = [o for o in t.objs if o.path.startswith("/obj/item") and not o.path.startswith(
            ("/obj/item/radio/intercom", "/obj/item/twohanded/required/kirbyplants", "/obj/item/kirbyplants",
             "/obj/item/beacon", "/obj/item/storage/secure/safe"))
                 and abs(o.num("pixel_x")) < 16 and abs(o.num("pixel_y")) < 16]
        if not items or any(o.path.startswith(UNDER) for o in t.objs):
            continue
        near_wall = any(_wall(m.get(x + dx, y + dy)) for dx in (-1, 0, 1) for dy in (-1, 0, 1))
        if not near_wall:
            out["loose"].append((x, y))
    sizes = {a: len(ts) for a, ts in by_room.items()}
    for p in out["loose"]:
        t = m.get(*p)
        if sizes.get(t.apath, 0) >= 60 and not any(_wall(m.get(p[0] + dx, p[1] + dy))
                                                   for dx in range(-2, 3) for dy in range(-2, 3)):
            out["open_loose"].append(p)
    for a, ts in by_room.items():
        if len(ts) < 60 or a.startswith(("/area/hallway", "/area/engine/atmos")) and False:
            continue
        furn = sum(1 for p in ts if any(o.path.startswith(UNDER) or kit.is_dense_atom(o) for o in m.get(*p).objs))
        if furn < 0.04 * len(ts) and not a.startswith("/area/hallway"):
            out["bare_big"].append(ts[len(ts) // 2])
    out["_walls"] = walls
    out["_floor"] = [(x, y) for (x, y, z), t in m.tiles.items() if _station(t)]
    return out


def measure(m):
    s = spots(m)
    nw = float(max(1, len(s["_walls"])))
    nf = float(max(1, len(s["_floor"])))
    return dict(double=round(1000 * len(s["double"]) / nw, 1), thick=round(1000 * len(s["thick"]) / nw, 1),
                loose=round(1000 * len(s["loose"]) / nf, 2), open_loose=len(s["open_loose"]),
                bare_big=len(s["bare_big"]))


def stock():
    out = {}
    for name in STOCK:
        m = dmm.read(parse.map_path(name)) if hasattr(parse, "map_path") else None
        out[name] = measure(m)
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("name", nargs="?")
    ap.add_argument("--stock", action="store_true")
    ap.add_argument("--where")
    a = ap.parse_args()
    if a.stock:
        for k, v in stock().items():
            print("%-14s %s" % (k, v))
    if a.name:
        m = dmm.read(os.path.join(parse.ROOT, "data", "mapforge", a.name + ".dmm"))
        print("%-14s %s" % (a.name, measure(m)))
        if a.where:
            pts = spots(m)[a.where]
            print("%d spots: %s" % (len(pts), " ".join("%d,%d" % p for p in pts[:80])))
