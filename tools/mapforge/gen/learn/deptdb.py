"""L0 department model: what the human departments show about their rooms, for the floorplanner (gen/learn/
floorplan.py). Learned from the tg-family maps (forge/corpus.MAPS) through forge/parse.

    python tools/mapforge/gen/learn/deptdb.py          # build data/mapforge/learn/depts.json, print it
    from gen.learn import deptdb; d = deptdb.model()

  turf[type]       the floor turf most of a room type's floor has (its look: white medbay, wood office, ...)
  front[type]      how near the department's hall doors a room type sits: the share of its rooms with a door
                   straight onto a hall or the department's corridor (1: always off the walkway, 0: always behind
                   another room)
  door[(a, b)]     how often rooms of types a and b that touch share a door, over the times they touch
  corridor[dept]   the department corridor's turf and its share of the department's floor
"""
import json
import os
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import corpus as CO, parse  # noqa: E402

OUT = os.path.join(CO.ROOT, "data", "mapforge", "learn", "depts.json")
VERSION = 2
NAMES = ("MetaStation", "BoxStation", "DeltaStation", "PubbyStation", "DonutStation", "HippieStation", "MetaLake")


def build():
    import rooms as RM
    corr_areas = set(RM.CORRIDOR_AREA.values())
    turf = defaultdict(Counter)
    front = defaultdict(lambda: [0, 0])
    touch, door = Counter(), Counter()
    nb_touch, nb_both = Counter(), Counter()     # maps where two room types touch / maps where both are
    corr_turf, corr_share = defaultdict(Counter), defaultdict(list)
    for name in NAMES:
        try:
            sm = parse.load(name)
        except Exception:                    # noqa: BLE001 - a map that won't load is skipped
            continue
        regs = sm.regions
        here = {r.area for r in regs.values() if r.kind == "room"}
        touched = set()
        for r in regs.values():
            if r.kind != "room":
                continue
            for p in r.tiles:
                t = sm.m.get(p[0], p[1], sm.z)
                if t is not None:
                    turf[r.area][t.tpath] += 1
            # off the walkway: a door or open seam to a hall, or to the department's own corridor area
            walk = any(regs[o].kind == "hall" or regs[o].area in corr_areas or regs[o].area.endswith(("/central", "/lobby"))
                       for o in r.links)
            front[r.area][0] += 1 if walk else 0
            front[r.area][1] += 1
        # touching pairs: regions of rooms one wall apart
        tile_reg = sm.region
        for p, c in sm.cls.items():
            if c not in ("W", "D"):
                continue
            for dx, dy in ((1, 0), (0, 1)):
                a, b = tile_reg.get((p[0] - dx, p[1] - dy)), tile_reg.get((p[0] + dx, p[1] + dy))
                if a is None or b is None or a == b:
                    continue
                ra, rb = regs[a], regs[b]
                if ra.kind != "room" or rb.kind != "room" or ra.group != rb.group:
                    continue
                k = tuple(sorted((ra.area, rb.area)))
                touch[k] += 1
                touched.add(k)
                if c == "D":
                    door[k] += 1
        for k in touched:
            nb_touch[k] += 1
        hs = sorted(here)
        for i, a in enumerate(hs):
            for b in hs[i + 1:]:
                nb_both[(a, b)] += 1
        for g in set(r.group for r in regs.values() if r.group):
            fl = [r for r in regs.values() if r.group == g and r.kind == "room"]
            tot = sum(len(r.tiles) for r in fl)
            cor = [r for r in fl if r.area in corr_areas or r.area.endswith(("/central", "/lobby", "/hallway"))]
            if tot:
                corr_share[g].append(sum(len(r.tiles) for r in cor) / float(tot))
            for r in cor:
                for p in r.tiles:
                    t = sm.m.get(p[0], p[1], sm.z)
                    if t is not None:
                        corr_turf[g][t.tpath] += 1
    out = dict(version=VERSION,
               turf={a: c.most_common(1)[0][0] for a, c in turf.items()},
               front={a: round(v[0] / float(v[1]), 2) for a, v in front.items() if v[1]},
               door={"%s|%s" % k: round(door[k] / float(touch[k]), 2) for k in touch if touch[k] >= 2},
               # how often two room types are neighbours on the maps that have both (a kitchen and its cold room)
               nb={"%s|%s" % k: round(nb_touch[k] / float(nb_both[k]), 2) for k in nb_touch
                   if k[0] != k[1] and nb_both[k] >= 3},
               corridor={g: dict(turf=corr_turf[g].most_common(1)[0][0] if corr_turf[g] else "/turf/open/floor/plasteel",
                                 share=round(sorted(corr_share[g])[len(corr_share[g]) // 2], 3) if corr_share[g] else 0.18)
                         for g in corr_share})
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump(out, open(OUT, "w"), indent=1)
    return out


_M = None


def model():
    global _M
    if _M is None:
        if os.path.exists(OUT):
            d = json.load(open(OUT))
            if d.get("version") == VERSION:
                _M = d
        if _M is None:
            _M = build()
    return _M


if __name__ == "__main__":
    d = build()
    print("turfs %d, fronts %d, door pairs %d" % (len(d["turf"]), len(d["front"]), len(d["door"])))
    for g, v in sorted(d["corridor"].items()):
        print("  corridor %-12s %s share %.2f" % (g, v["turf"], v["share"]))
    for a in ("/area/medical/medbay/central", "/area/medical/surgery", "/area/medical/chemistry", "/area/medical/storage",
              "/area/medical/morgue", "/area/science/lab", "/area/science/server"):
        print("  %-36s turf %-40s front %s" % (a, d["turf"].get(a), d["front"].get(a)))
