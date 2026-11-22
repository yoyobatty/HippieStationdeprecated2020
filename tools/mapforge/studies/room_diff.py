"""One room (an area) in two builds, side by side: its stats against the stock band, its floor gained and lost, and
the objects gained and lost by family. Answers "what moved this room's number" for a gate regression
(station/v6_gate.py, station/v6_ablate.py) with the tiles and objects, not a guess.

    python tools/mapforge/studies/room_diff.py crew_quarters/dorms [--a data/mapforge/station_v6_accepted.dmm]
                                               [--b data/mapforge/station_v6.dmm] [--tiles]

The area is matched by suffix (crew_quarters/dorms matches /area/crew_quarters/dorms only, not its children).
--tiles also prints each gained or lost floor tile and every tile whose objects changed.
"""
import argparse
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import parse, room_stats as RS  # noqa: E402

ROOT = parse.ROOT
SKIP = ("/obj/machinery/atmospherics", "/obj/structure/cable", "/obj/structure/disposalpipe")


def room(sm, area):
    for rm in RS.rooms(sm):
        if rm.area == area:
            return rm
    return None


def objs(sm, tiles):
    c = Counter()
    per = {}
    for p in tiles:
        t = sm.m.tiles.get((p[0], p[1], sm.z))
        if t is None:
            continue
        ks = Counter(RS._family(o.path) for o in t.objs if not o.path.startswith(SKIP))
        per[p] = ks
        c.update(ks)
    return c, per


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("area")
    ap.add_argument("--a", default=os.path.join(ROOT, "data", "mapforge", "station_v6_accepted.dmm"))
    ap.add_argument("--b", default=os.path.join(ROOT, "data", "mapforge", "station_v6.dmm"))
    ap.add_argument("--tiles", action="store_true")
    a = ap.parse_args()
    area = a.area if a.area.startswith("/area/") else "/area/" + a.area
    sa, sb = parse.load(a.a), parse.load(a.b)
    ra, rb = room(sa, area), room(sb, area)
    kind = RS.type_of(area)
    peers = RS.peers(kind) if kind else []
    print("%s  (type %s, %d stock rooms)" % (area, kind, len(peers)))
    print("%-10s %8s %8s   %s" % ("stat", "A", "B", "stock band"))
    for k in RS.STATS:
        va = ra.stats[k] if ra else float("nan")
        vb = rb.stats[k] if rb else float("nan")
        band = "%.2f..%.2f" % (min(p.stats[k] for p in peers), max(p.stats[k] for p in peers)) if peers else ""
        flag = ""
        if peers and ra and rb:
            lo, hi = min(p.stats[k] for p in peers), max(p.stats[k] for p in peers)
            da = max(0, lo - va, va - hi)
            db = max(0, lo - vb, vb - hi)
            flag = "  WORSE" if db > da + 1e-6 else "  better" if db < da - 1e-6 else ""
        print("%-10s %8.2f %8.2f   %s%s" % (k, va, vb, band, flag))
    ta, tb = set(ra.tiles) if ra else set(), set(rb.tiles) if rb else set()
    print("floor: A %d, B %d, gained %d, lost %d; box A %s, B %s" % (
        len(ta), len(tb), len(tb - ta), len(ta - tb), ra.box if ra else None, rb.box if rb else None))
    ca, pa = objs(sa, ta)
    cb, pb = objs(sb, tb)
    gained = cb - ca
    lost = ca - cb
    if gained:
        print("objects gained: " + ", ".join("%s x%d" % (k.replace("/obj/", ""), v) for k, v in gained.most_common()))
    if lost:
        print("objects lost:   " + ", ".join("%s x%d" % (k.replace("/obj/", ""), v) for k, v in lost.most_common()))
    if a.tiles:
        for p in sorted(tb - ta):
            print("  + floor %d,%d" % p)
        for p in sorted(ta - tb):
            print("  - floor %d,%d" % p)
        for p in sorted(ta & tb):
            if pa.get(p) != pb.get(p):
                d1 = pa.get(p, Counter()) - pb.get(p, Counter())
                d2 = pb.get(p, Counter()) - pa.get(p, Counter())
                print("  %d,%d  -%s  +%s" % (p[0], p[1], dict(d1), dict(d2)))


if __name__ == "__main__":
    main()
