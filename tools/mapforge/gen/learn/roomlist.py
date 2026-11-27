"""Room sizes of a built station as the gate sees them (parse.SemanticMap rooms, space_sizes.measure), per group, next to
the human band: finds which departments push the station's room quantiles out of band when the floorplans alone
(planstats.py) are in it.

    python tools/mapforge/gen/learn/roomlist.py data/mapforge/gen_learn/gen_hub_c80_s1.dmm
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", ".."))
from forge import dmm, parse  # noqa: E402
import gate as G  # noqa: E402


def q(v, f):
    v = sorted(v)
    return v[min(len(v) - 1, int(f * len(v)))] if v else 0


def main(path):
    m = dmm.read(path)
    sm = parse.SemanticMap(m)
    rooms = sm.rooms()
    b = G.bands()[0]
    by = {}
    for r in rooms:
        by.setdefault(r.group, []).append(r)
    sizes = [len(r.tiles) for r in rooms]
    print("rooms %d  q10/25/50/75/90: %s" % (len(rooms), " ".join(str(q(sizes, f)) for f in (.1, .25, .5, .75, .9))))
    for f in ("0.1", "0.25", "0.5", "0.75", "0.9"):
        k = "space.room_q" + f
        if k in b:
            print("  %-16s band %.1f..%.1f" % (k, b[k][0], b[k][1]))
    for g, rs in sorted(by.items(), key=lambda kv: -len(kv[1])):
        v = sorted(len(r.tiles) for r in rs)
        k = "space.room_size_" + g
        band = ("band %.0f..%.0f" % (b[k][0], b[k][1])) if k in b else ""
        areas = {}
        for r in rs:
            a = getattr(r, "area", None) or "?"
            areas.setdefault(a.split("/")[-1], []).append(len(r.tiles))
        print("%-12s n=%-3d med %-4d %-14s %s" % (g, len(v), q(v, .5), band, v))
        for a, s in sorted(areas.items(), key=lambda kv: -sum(kv[1]))[:8]:
            print("    %-28s %s" % (a, sorted(s)))


def oversized(path):
    """The gate's "oversized rooms" (gen/gate.py hard_values): rooms bigger than every human room of their type."""
    from forge import room_stats as RS
    sm = parse.load(path)
    for rm in RS.rooms(sm):
        kind = RS.type_of(rm.area)
        if not kind:
            continue
        sizes = [p.stats["tiles"] for p in RS.peers(kind)]
        if len(sizes) >= 3 and rm.stats["tiles"] > max(sizes):
            print("oversized %-40s %4d tiles, human max %d (%d rooms)" % (rm.area, rm.stats["tiles"], max(sizes),
                                                                          len(sizes)))


if __name__ == "__main__":
    main(sys.argv[1])
    oversized(sys.argv[1])
