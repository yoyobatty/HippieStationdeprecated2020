"""Service/civilian survey of a map: each service room's size, kit and how it joins its neighbours.

    python tools/mapforge/studies/dept_specs/service_work/survey.py <dmm or stock name> [--only kitchen] [--joins]
    python tools/mapforge/studies/dept_specs/service_work/survey.py --stock [--only kitchen]   # every corpus map

Prints per area: open tiles, box, the kit (families, infrastructure left out), then every join to another area:
door (airlock), windoor counter (table + windoor), shutters, glass (window between floors), open (floor touches
floor). Ends with the produce smartfridges (exact /obj/machinery/smartfridge): where each stands, the areas round
it, and the tray to fridge distance (Chebyshev, the bot's 30-tile reach).
"""
import os
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
MF = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, MF)
from forge import corpus as CO, dmm  # noqa: E402

ROOT = os.path.normpath(os.path.join(MF, "..", ".."))
SCOPE = ("/area/crew_quarters/kitchen", "/area/crew_quarters/bar", "/area/crew_quarters/cafeteria",
         "/area/crew_quarters/lounge", "/area/hydroponics", "/area/janitor", "/area/library", "/area/chapel",
         "/area/crew_quarters/theatre", "/area/lawoffice", "/area/crew_quarters/dorms", "/area/crew_quarters/toilet",
         "/area/crew_quarters/fitness", "/area/crew_quarters/locker", "/area/storage/primary", "/area/storage/art",
         "/area/storage/emergency", "/area/vacant_room", "/area/crew_quarters/cryopod", "/area/storage/tools")
SKIP = ("/obj/machinery/light", "/obj/machinery/power/apc", "/obj/machinery/airalarm", "/obj/machinery/firealarm",
        "/obj/item/radio/intercom", "/obj/machinery/newscaster", "/obj/machinery/camera", "/obj/structure/cable",
        "/obj/machinery/atmospherics", "/obj/structure/disposalpipe", "/obj/effect", "/obj/machinery/door/firedoor",
        "/obj/machinery/light_switch", "/obj/machinery/status_display", "/obj/machinery/ai_status_display",
        "/obj/machinery/navbeacon", "/obj/structure/grille", "/obj/structure/window", "/obj/machinery/holopad",
        "/obj/structure/lattice", "/obj/machinery/power/terminal", "/obj/docking_port")
N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))


def load(name):
    if os.path.exists(name):
        return dmm.read(name)
    for rel in CO.MAPS:
        if name.lower() in rel.lower():
            return dmm.read(os.path.join(ROOT, "_maps", "map_files", rel))
    raise SystemExit("no map " + name)


def floor(t):
    return t is not None and t.tpath.startswith("/turf/open") and not t.tpath.startswith("/turf/open/space")


def fam(p):
    parts = p.split("/")
    return "/".join(parts[:5]) if len(parts) > 5 else p


def kind(t):
    """What a tile between two floors is: door, counter, shutters, glass, open or None (wall)."""
    if t is None:
        return None
    if t.has("/obj/machinery/door/airlock"):
        return "door"
    if t.has("/obj/machinery/door/window") and t.has("/obj/structure/table"):
        return "counter"
    if t.has("/obj/machinery/door/window"):
        return "windoor"
    if t.has("/obj/structure/table") and (t.has("/obj/machinery/door/poddoor/shutters") or t.has("/obj/machinery/door/firedoor")):
        return "hatch"
    if t.has("/obj/machinery/smartfridge"):
        return "fridge-in-wall"
    if t.has("/obj/machinery/door/poddoor/shutters"):
        return "shutters"
    if t.has("/obj/structure/window") or t.has("/obj/effect/spawner/structure/window"):
        return "glass"
    if t.tpath.startswith("/turf/closed"):
        return None
    return "open"


def in_scope(a):
    return a.startswith(SCOPE)


def survey(m, only=None, joins=True, out=print):
    by_area = defaultdict(list)
    for (x, y, z), t in m.tiles.items():
        if z == 1 and floor(t):
            by_area[t.apath].append((x, y))
    areas = sorted(a for a in by_area if in_scope(a) and (not only or only in a))
    for a in areas:
        ts = by_area[a]
        xs, ys = [p[0] for p in ts], [p[1] for p in ts]
        kitc = Counter()
        for p in ts:
            for o in m.get(*p).objs:
                if not o.path.startswith(SKIP):
                    kitc[fam(o.path)] += 1
        out("%s  %d tiles  box (%d,%d)-(%d,%d)" % (a, len(ts), min(xs), min(ys), max(xs), max(ys)))
        out("   kit: " + ", ".join("%s%s" % (k.replace("/obj/", ""), " x%d" % n if n > 1 else "")
                                  for k, n in sorted(kitc.items())))
        if not joins:
            continue
        j = defaultdict(list)
        tset = set(ts)
        for p in ts:
            for dx, dy in N4:
                q = (p[0] + dx, p[1] + dy)
                tq = m.get(*q)
                if tq is None:
                    continue
                if floor(tq) and tq.apath != a and not tq.has("/obj/machinery/door") and q not in tset:
                    j[(tq.apath, "open")].append(q)
                    continue
                k = kind(tq)
                if k is None or k == "open":
                    continue
                r = (q[0] + dx, q[1] + dy)
                tr = m.get(*r)
                if floor(tr) and tr.apath != a:
                    j[(tr.apath, k)].append(q)
                elif k in ("door", "counter", "windoor", "hatch") and tq.apath != a and floor(tq):
                    j[(tq.apath, k + "(own tile)")].append(q)
        for (b, k), qs in sorted(j.items()):
            qs = sorted(set(qs))
            out("   %-9s -> %s  x%d at %s" % (k, b, len(qs), " ".join("%d,%d" % q for q in qs[:6])))
    return by_area


def fridges(m, out=print):
    trays = [(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and t.has("/obj/machinery/hydroponics")
             and not t.has("/obj/machinery/hydroponics/soil") and t.apath.startswith("/area/hydroponics")
             and not t.apath.startswith("/area/hydroponics/garden")]
    fr = [(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and any(o.path == "/obj/machinery/smartfridge" for o in t.objs)]
    out("trays (workplace) %d; produce smartfridges %d" % (len(trays), len(fr)))
    for f in fr:
        t = m.get(*f)
        round_ = sorted({m.get(f[0] + dx, f[1] + dy).apath for dx, dy in N4 if floor(m.get(f[0] + dx, f[1] + dy))})
        reach = [max(abs(f[0] - tr[0]), abs(f[1] - tr[1])) for tr in trays]
        out("  fridge %d,%d in %s turf %s; floor round it: %s; trays within 30: %d/%d (nearest %s)" % (
            f[0], f[1], t.apath, t.tpath.split("/")[-1], ", ".join(round_), sum(1 for d in reach if d <= 30), len(trays),
            min(reach) if reach else "-"))
    return trays, fr


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    only = None
    if "--only" in sys.argv:
        only = sys.argv[sys.argv.index("--only") + 1]
        args = [a for a in args if a != only]
    names = CO.MAPS if "--stock" in sys.argv else args
    for n in names:
        print("=" * 20, n)
        m = load(n)
        survey(m, only, joins="--nojoins" not in sys.argv)
        fridges(m)
