"""Each room's free floor inside what its type has on the stock maps (gen/learn/placestudy.py: 5th-95th percentile of
the share of floor under no dense piece): a crammed room sheds its optional furniture (never its type's kit or a
machine), the piece furthest into the room's middle first; a bare room gets its type's commonest standing pieces
(the stock rooms' own: racks and canisters for a science storage, lockers for a locker room) on free wall spots
that keep the room walkable.

    python tools/mapforge/gen/learn/density.py <dmm> [out.dmm]
    from gen.learn import density; density.fix(m, log)      # build.py: with settle, before the networks

crew 100 seed 7 f14: 6-7.5% of rooms crammed (stock 1-3%), 4-4.5% bare (stock 0-1.4%).
"""
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", ".."))
from forge import corpus as CO, dmm, function as FN  # noqa: E402
import placestudy as PS  # noqa: E402
import settle as ST  # noqa: E402

N4 = PS.N4
OPTIONAL = ("/obj/structure/table", "/obj/structure/rack", "/obj/structure/closet/crate", "/obj/structure/closet/cardboard",
            "/obj/structure/chair", "/obj/item/twohanded/required/kirbyplants", "/obj/structure/flora",
            "/obj/structure/bookcase", "/obj/structure/filingcabinet", "/obj/structure/displaycase",
            "/obj/structure/closet/emcloset", "/obj/structure/closet/firecloset")


def _band(S, area):
    v = S["rooms"].get(area) or []
    if len(v) < 5:
        v = [x for vv in S["rooms"].values() for x in vv]
    fr = [x[0] for x in v]
    return PS._q(fr, 0.05), PS._q(fr, 0.95)


def _kit(area):
    try:
        sys.path.insert(0, os.path.join(HERE, ".."))
        import essentials as ES
        return tuple(k["path"] for k in ES.table().get(area, {}).get("kit", []))
    except Exception:                          # noqa: BLE001
        return ()


_COMMON = {}


def _common(area):
    """The standing pieces the type's stock rooms have most (single atoms of their motifs), commonest first."""
    if area not in _COMMON:
        import roomdb
        c = Counter()
        for r in roomdb.rooms():
            if r["area"] != area:
                continue
            for mo in r["motifs"]:
                for cell in mo["cells"]:
                    for a in cell[2]:
                        p = a.split("{")[0].strip()
                        if p.startswith(("/obj/structure", "/obj/machinery/portable_atmospherics")) and \
                                not p.startswith(("/obj/structure/table", "/obj/structure/chair", "/obj/structure/window",
                                                  "/obj/structure/grille", "/obj/structure/cable", "/obj/structure/disposal",
                                                  "/obj/structure/sign")):
                            c[p] += 1
        _COMMON[area] = [p for p, n in c.most_common(6) if n >= 2]
    return _COMMON[area]


def fix(m, log=print):
    S = PS.study()
    ST.reserve(m)
    shed = added = 0
    for area, F in PS.pieces_of(m):
        if area in PS.CORRIDOR_AREAS:
            continue
        lo, hi = _band(S, area)
        doors = {(p[0] + dx, p[1] + dy) for p in F for dx, dy in N4 if PS._door(m.get(p[0] + dx, p[1] + dy))}
        if not doors:
            continue
        free = sum(1 for p in F if not PS._dense(m.get(*p)))
        share = free / float(len(F))
        if share < lo:
            kit = _kit(area)
            cx = sum(p[0] for p in F) / float(len(F))
            cy = sum(p[1] for p in F) / float(len(F))
            cands = []
            for p in F:
                for o in m.get(*p).objs:
                    if o.path.startswith(OPTIONAL) and FN.is_dense(o) and not CO.mounted(o) \
                            and not any(o.path.startswith(k) for k in kit):
                        cands.append(((p[0] - cx) ** 2 + (p[1] - cy) ** 2, p, o))
            cands.sort(key=lambda c: -c[0])
            # the middle first: pieces furthest in toward the room's centre go (the sort is by distance from it, so
            # take the nearest)
            cands.reverse()
            for _, p, o in cands:
                if free / float(len(F)) >= lo + 0.02:
                    break
                t = m.get(*p)
                if o not in t.objs:
                    continue
                t.objs.remove(o)
                if o.path.startswith(("/obj/structure/table", "/obj/structure/rack")):
                    t.objs = [i for i in t.objs if not i.path.startswith("/obj/item")]
                free += 1
                shed += 1
        elif share > hi:
            for path in _common(area):
                if free / float(len(F)) <= hi - 0.02:
                    break
                for _ in range(4):
                    if free / float(len(F)) <= hi - 0.02:
                        break
                    o = dmm.Atom(path)
                    spot = None
                    seen0, free0, fronts = ST._reach(m, F, doors)
                    for q in sorted(F, key=lambda q: -sum(1 for dx, dy in N4 if PS._solid(m.get(q[0] + dx, q[1] + dy)))):
                        if q in fronts or not ST._free_tile(m.get(*q), q):
                            continue
                        if not any(PS._solid(m.get(q[0] + dx, q[1] + dy)) and (q[0] + dx, q[1] + dy) not in doors
                                   for dx, dy in N4):
                            continue
                        if not any((q[0] + dx, q[1] + dy) in seen0 for dx, dy in N4):
                            continue
                        m.get(*q).objs.append(o)
                        seen1, free1, _ = ST._reach(m, F, doors)
                        if (free1 - seen1) - (free0 - seen0):
                            m.get(*q).objs.remove(o)
                            continue
                        spot = q
                        break
                    if spot is None:
                        break
                    if FN.is_dense(o):
                        free -= 1
                    added += 1
    log("density: %d optional pieces taken out of crammed rooms, %d stock pieces added to bare ones" % (shed, added))
    return shed + added


if __name__ == "__main__":
    m = dmm.read(sys.argv[1])
    print("before", PS.summary(PS.check(m)))
    fix(m)
    print("after ", PS.summary(PS.check(m)))
    if len(sys.argv) > 2:
        dmm.write(m, sys.argv[2])
