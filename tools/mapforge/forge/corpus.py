"""Furniture corpus mined from human-made station maps.

    python tools/mapforge/forge/corpus.py            # (re)build data/mapforge/corpus.json
    python tools/mapforge/forge/corpus.py /area/crew_quarters/kitchen   # what the corpus knows about a room type

For every room (connected tiles of one area) on each map, furniture tiles are grouped into clusters (8-connected).
A cluster keeps each tile's furniture and the items on it, which sides of each tile were wall, and which
neighbouring tiles were left open (the access a person needs). The furnisher drops these real clusters, rotated
as needed, into new rooms. Per room type the corpus also keeps how often each object appears (core objects) and
how much of the floor is furnished.
"""
import json
import os
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from forge import dmm  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
CACHE = os.path.join(ROOT, "data", "mapforge", "corpus.json")
MAPS = [
    "HippieStation/hippiestation.dmm", "MetaStation/MetaStation.dmm", "BoxStation/BoxStation.dmm",
    "Deltastation/DeltaStation2.dmm", "PubbyStation/PubbyStation.dmm", "Donutstation/Donutstation.dmm",
    "EndoStation/EndoStation.dmm", "MetaLake/MetaLake.dmm",
]
INFRA = ("/obj/machinery/atmospherics", "/obj/structure/cable", "/obj/machinery/light", "/obj/effect", "/obj/machinery/door",
         "/obj/structure/window", "/obj/structure/grille", "/obj/structure/disposalpipe", "/obj/machinery/navbeacon",
         "/obj/machinery/power/apc", "/obj/machinery/airalarm", "/obj/machinery/firealarm", "/obj/machinery/light_switch",
         "/obj/machinery/camera", "/obj/structure/lattice", "/obj/machinery/power/terminal", "/obj/structure/plasticflaps",
         "/obj/machinery/atmospherics", "/obj/structure/cable_bridge", "/obj/machinery/holopad", "/obj/machinery/firealarm",
         "/obj/docking_port", "/obj/machinery/power/smes", "/obj/structure/disposaloutlet", "/obj/machinery/disposal",
         "/obj/item/radio/intercom", "/obj/machinery/newscaster", "/obj/structure/extinguisher_cabinet", "/obj/structure/sign",
         "/obj/machinery/status_display", "/obj/machinery/requests_console", "/obj/machinery/button", "/obj/structure/noticeboard",
         "/obj/machinery/computer/security/telescreen", "/obj/structure/fireaxecabinet", "/obj/machinery/porta_turret",
         "/obj/machinery/turretid", "/obj/machinery/flasher", "/obj/machinery/doorButtons", "/obj/machinery/embedded_controller",
         "/obj/structure/closet/emcloset", "/obj/structure/closet/firecloset", "/obj/machinery/vending/wallmed",
         "/obj/machinery/defibrillator_mount", "/obj/structure/mirror", "/obj/machinery/keycard_auth", "/obj/machinery/ai_slipper",
         # leftovers and wreckage from abandoned rooms: never furnish with them
         "/obj/structure/light_construct", "/obj/structure/girder", "/obj/structure/barricade", "/obj/structure/table_frame",
         "/obj/item/stack/rods", "/obj/item/shard", "/obj/structure/spider", "/obj/structure/alien",
         # linked machinery: works only with its own ids/partners on its own map, never copy it
         "/obj/machinery/conveyor", "/obj/machinery/conveyor_switch", "/obj/machinery/mass_driver",
         "/obj/machinery/button", "/obj/machinery/magnetic_module", "/obj/machinery/magnetic_controller",
         "/obj/machinery/sparker", "/obj/machinery/igniter", "/obj/machinery/door_timer")
ANCHOR = ("/obj/structure", "/obj/machinery", "/mob/living/simple_animal", "/obj/item/twohanded/required/kirbyplants")


def mounted(a):
    return abs(a.num("pixel_x")) >= 16 or abs(a.num("pixel_y")) >= 16


# wall pieces that belong to the furniture under them and travel with it (a mirror over a sink, a flasher over a
# cell bed, a wall medkit over a bed); the room's own infrastructure (APC, alarms, lights...) is placed by the builder
COMPANIONS = ("/obj/structure/mirror", "/obj/machinery/vending/wallmed", "/obj/machinery/defibrillator_mount",
              "/obj/structure/sign", "/obj/structure/noticeboard", "/obj/machinery/computer/security/telescreen",
              "/obj/item/radio/intercom", "/obj/machinery/flasher", "/obj/structure/fireaxecabinet")


def mount_side(o):
    px, py = o.num("pixel_x"), o.num("pixel_y")
    if abs(py) >= abs(px):
        return 1 if py > 0 else 2
    return 4 if px > 0 else 8


def companions(t, wm):
    """Companion wall pieces on tile t that hang on one of its walls (wm = wall mask)."""
    return [o for o in t.objs if mounted(o) and o.path.startswith(COMPANIONS) and wm & mount_side(o)]


def furniture(t):
    """(anchors, items) on a tile: anchors are the structures/machines a cluster is made of."""
    anchors, items = [], []
    for a in t.objs:
        if a.path.startswith(INFRA) or mounted(a) or a.path.startswith("/obj/effect"):
            continue
        if a.path.startswith(ANCHOR):
            anchors.append(a)
        elif a.path.startswith("/obj/item"):
            items.append(a)
    return anchors, items


def solid(t):
    if t is None:
        return True
    return t.tpath.startswith("/turf/closed") or t.has("/obj/effect/spawner/structure/window") or t.has("/obj/structure/grille") \
        or t.has("/obj/structure/window/reinforced/fulltile") or t.has("/obj/structure/window/fulltile")


D4 = {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0)}


def mine_map(path, out_clusters, stats):
    m = dmm.read(path)
    z = 1
    name = os.path.basename(path)
    seen = set()
    for (x, y, zz), t in m.tiles.items():
        if zz != z or (x, y) in seen or not t.tpath.startswith("/turf/open") or t.tpath.startswith("/turf/open/space"):
            continue
        area = t.apath
        if not area or area.startswith(("/area/space", "/area/maintenance", "/area/hallway", "/area/solar", "/area/shuttle",
                                         "/area/lavaland", "/area/mine", "/area/ruin")):
            continue
        # room = connected open tiles of this area
        room, q = set(), [(x, y)]
        seen.add((x, y))
        while q:
            p = q.pop()
            room.add(p)
            for dx, dy in D4.values():
                n = (p[0] + dx, p[1] + dy)
                nt = m.get(n[0], n[1], z)
                if n not in seen and nt is not None and nt.apath == area and nt.tpath.startswith("/turf/open") \
                        and not nt.tpath.startswith("/turf/open/space"):
                    seen.add(n)
                    q.append(n)
        if len(room) < 6:
            continue
        floors = [p for p in room if not solid(m.get(p[0], p[1], z))]
        furn = {}
        objs = Counter()
        for p in floors:
            an, it = furniture(m.get(p[0], p[1], z))
            for a in an:
                objs[a.path] += 1
            if an:
                furn[p] = (an, it)
        st = stats[area]
        st["rooms"] += 1
        st["floor"] += len(floors)
        st["furn"] += len(furn)
        for k in objs:
            st["has"][k] += 1
        # clusters
        left = set(furn)
        while left:
            s = left.pop()
            comp, q = [s], [s]
            while q:
                p = q.pop()
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        n = (p[0] + dx, p[1] + dy)
                        if n in left:
                            left.discard(n)
                            comp.append(n)
                            q.append(n)
            # every tile also as a single piece (fallback for required items and wall fill)
            for p in comp:
                an, it = furn[p]
                wm = 0
                clear1 = []
                for d, (dx, dy) in D4.items():
                    n = (p[0] + dx, p[1] + dy)
                    nt = m.get(n[0], n[1], z)
                    if solid(nt) or (nt is not None and nt.apath != area and not nt.has("/obj/machinery/door")):
                        wm |= d
                    elif n not in furn and n in room:
                        clear1.append((dx, dy))
                cells1 = [[0, 0, [a.text() for a in an] + [a.text() for a in it]
                           + [o.text() for o in companions(m.get(p[0], p[1], z), wm)], wm]]
                out_clusters.append({"area": area, "map": name, "at": [p[0], p[1]], "cells": cells1,
                                     "clear": sorted(clear1)[:1], "sig": "single" + json.dumps(cells1), "single": True})
            if len(comp) > 16:
                continue
            x0 = min(p[0] for p in comp)
            y0 = min(p[1] for p in comp)
            cells, walls, clear = {}, {}, set()
            for p in comp:
                an, it = furn[p]
                key = (p[0] - x0, p[1] - y0)
                cells[key] = [a.text() for a in an] + [a.text() for a in it]
                wm = 0
                for d, (dx, dy) in D4.items():
                    n = (p[0] + dx, p[1] + dy)
                    nt = m.get(n[0], n[1], z)
                    if solid(nt) or (nt is not None and nt.apath != area and not nt.has("/obj/machinery/door")):
                        wm |= d
                    elif n not in furn and n in room:
                        clear.add((n[0] - x0, n[1] - y0))
                walls[key] = wm
                cells[key] += [o.text() for o in companions(m.get(p[0], p[1], z), wm)]
            sig = json.dumps(sorted((k, v) for k, v in cells.items()))
            out_clusters.append({"area": area, "map": name, "at": [x0, y0],
                                 "cells": [[k[0], k[1], v, walls[k]] for k, v in cells.items()],
                                 "clear": sorted(clear), "sig": sig})


def build():
    clusters = []
    stats = defaultdict(lambda: {"rooms": 0, "floor": 0, "furn": 0, "has": Counter()})
    for rel in MAPS:
        p = os.path.join(ROOT, "_maps", "map_files", rel)
        if os.path.exists(p):
            mine_map(p, clusters, stats)
    # dedupe clusters, counting how often each exact one occurs
    uniq = {}
    for c in clusters:
        k = (c["area"], c["sig"])
        if k in uniq:
            uniq[k]["count"] += 1
            uniq[k]["maps"] = sorted(set(uniq[k]["maps"]) | {c["map"]})
        else:
            c["count"] = 1
            c["maps"] = [c["map"]]
            uniq[k] = c
    out = {"clusters": [dict(c, sig=None) for c in uniq.values()],
           "areas": {a: {"rooms": s["rooms"], "floor": s["floor"], "furn": s["furn"], "has": dict(s["has"])}
                     for a, s in stats.items()}}
    for c in out["clusters"]:
        del c["sig"]
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    json.dump(out, open(CACHE, "w"))
    return out


_C = None


def load():
    global _C
    if _C is None:
        _C = json.load(open(CACHE)) if os.path.exists(CACHE) else build()
    return _C


def kinds(area):
    """Area keys matching a room type, most specific first (exact, then siblings under the parent path)."""
    c = load()
    if area in c["areas"]:
        exact = [area]
    else:
        exact = []
    parent = area.rsplit("/", 1)[0]
    sib = [a for a in c["areas"] if a.startswith(area + "/")]
    if not exact and not sib:
        sib = [a for a in c["areas"] if a.startswith(parent + "/")]
    return exact + sib


def summary(area):
    c = load()
    ks = kinds(area)
    rooms = sum(c["areas"][k]["rooms"] for k in ks)
    floor = sum(c["areas"][k]["floor"] for k in ks)
    furn = sum(c["areas"][k]["furn"] for k in ks)
    has = Counter()
    for k in ks:
        has.update(c["areas"][k]["has"])
    core = [p for p, n in has.most_common() if rooms and n / rooms >= 0.5]
    cl = [x for x in c["clusters"] if x["area"] in ks]
    return {"keys": ks, "rooms": rooms, "density": furn / floor if floor else 0, "core": core, "clusters": cl, "has": has}


if __name__ == "__main__":
    if len(sys.argv) == 1:
        out = build()
        print("%d clusters from %d room types" % (len(out["clusters"]), len(out["areas"])))
    else:
        s = summary(sys.argv[1])
        print("keys:", s["keys"])
        print("rooms %d, furnished %.0f%% of floor, %d clusters" % (s["rooms"], s["density"] * 100, len(s["clusters"])))
        print("core:", ", ".join(p.rsplit("/", 2)[-2] + "/" + p.rsplit("/", 1)[-1] for p in s["core"]))
        for c in sorted(s["clusters"], key=lambda c: -c["count"])[:8]:
            print(" x%d %s %d tiles: %s" % (c["count"], ",".join(c["maps"]), len(c["cells"]),
                                            "; ".join("+".join(a.split("{")[0].rsplit("/", 1)[-1] for a in cell[2]) for cell in c["cells"][:4])))
