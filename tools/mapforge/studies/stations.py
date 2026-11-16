"""Study the human-made stations: how big each department is, how that scales with the crew, where departments sit
and which ones border which. Feeds the station generator's program (tools/mapforge/station/).

    python tools/mapforge/studies/stations.py            # table + data/mapforge/station_study.json
"""
import json
import math
import os
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import dmm  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
MAPS = {
    "box": "BoxStation/BoxStation.dmm",
    "meta": "MetaStation/MetaStation.dmm",
    "delta": "Deltastation/DeltaStation2.dmm",
    "pubby": "PubbyStation/PubbyStation.dmm",
    "donut": "Donutstation/Donutstation.dmm",
    "hippie": "HippieStation/hippiestation.dmm",
    "mini": "MiniStation/ministation.dmm",
    "endo": "EndoStation/EndoStation.dmm",
}

# area prefix -> group, most specific first
GROUPS = [
    ("/area/crew_quarters/heads/captain", "command"), ("/area/crew_quarters/heads/hop", "command"),
    ("/area/crew_quarters/heads/hos", "security"), ("/area/crew_quarters/heads/cmo", "medical"),
    ("/area/crew_quarters/heads/chief", "engineering"), ("/area/crew_quarters/heads/hor", "science"),
    ("/area/crew_quarters/heads", "command"),
    ("/area/crew_quarters/dorms", "dorms"), ("/area/crew_quarters/toilet", "dorms"),
    ("/area/crew_quarters/locker", "dorms"), ("/area/crew_quarters/fitness", "dorms"),
    ("/area/crew_quarters/cryopod", "dorms"),
    ("/area/crew_quarters/bar", "service"), ("/area/crew_quarters/kitchen", "service"),
    ("/area/crew_quarters/cafeteria", "service"), ("/area/crew_quarters/theatre", "service"),
    ("/area/crew_quarters/lounge", "service"), ("/area/hydroponics", "service"), ("/area/janitor", "service"),
    ("/area/crew_quarters", "service"),
    ("/area/bridge", "command"), ("/area/teleporter", "command"), ("/area/gateway", "command"),
    ("/area/ai_monitored/turret_protected", "ai"), ("/area/ai_monitored/security", "security"),
    ("/area/ai_monitored/storage/eva", "command"), ("/area/ai_monitored/nuke_storage", "command"),
    ("/area/ai_monitored", "ai"), ("/area/tcommsat", "ai"), ("/area/comms", "ai"), ("/area/server", "ai"),
    ("/area/security", "security"), ("/area/lawoffice", "security"),
    ("/area/medical", "medical"),
    ("/area/science", "science"), ("/area/toxins", "science"),
    ("/area/engine/atmos", "atmos"), ("/area/atmos", "atmos"),
    ("/area/engine/gravity_generator", "engineering"), ("/area/engine", "engineering"),
    ("/area/engineering", "engineering"), ("/area/storage/tech", "engineering"), ("/area/tcomms", "ai"),
    ("/area/quartermaster", "cargo"), ("/area/mining", "cargo"),
    ("/area/chapel", "civic"), ("/area/library", "civic"), ("/area/storage", "civic"),
    ("/area/vacant_room", "civic"), ("/area/clerk", "civic"), ("/area/holodeck", "civic"),
    ("/area/hallway/secondary/entry", "arrivals"), ("/area/hallway/secondary/exit", "escape"),
    ("/area/hallway", "hall"),
    ("/area/maintenance", "maint"),
    ("/area/solar", "solar"),
    ("/area/shuttle", "shuttle"),
    ("/area/construction", "civic"),
]
SKIP = ("/area/space", "/area/start", "/area/lavaland", "/area/mine", "/area/ruin", "/area/asteroid",
        "/area/centcom", "/area/holodeck/rec_center", "/area/icemoon", "/area/awaymission")


def group_of(a):
    if a.startswith(SKIP):
        return None
    for pre, g in GROUPS:
        if a == pre or a.startswith(pre + "/") or a.startswith(pre + "_"):
            return g
    return "other:" + a


def study(name, rel):
    m = dmm.read(os.path.join(ROOT, "_maps", "map_files", rel))
    tiles = Counter()
    areas = defaultdict(set)
    where = defaultdict(list)
    starts = Counter()
    doors = []
    other = Counter()
    pos = {}
    for y in range(1, m.maxy + 1):
        for x in range(1, m.maxx + 1):
            t = m.get(x, y)
            if t is None:
                continue
            g = group_of(t.apath)
            if g is None:
                continue
            if g.startswith("other:"):
                other[g[6:]] += 1
                continue
            pos[(x, y)] = g
            if t.tpath.startswith("/turf/open"):
                tiles[g] += 1
                areas[g].add(t.apath)
                where[g].append((x, y))
            for o in t.objs:
                if o.path.startswith("/obj/effect/landmark/start/"):
                    starts[o.path.rsplit("/", 1)[1]] += 1
            if t.has("/obj/machinery/door/airlock") or t.has("/obj/machinery/door/window") \
                    or t.has("/obj/machinery/door/poddoor/shutters"):
                doors.append((x, y))
    # borders: a door joins the groups on its two sides
    joins = Counter()
    for (x, y) in doors:
        for a, b in (((x - 1, y), (x + 1, y)), ((x, y - 1), (x, y + 1))):
            ga, gb = pos.get(a), pos.get(b)
            if ga and gb and ga != gb:
                joins[tuple(sorted((ga, gb)))] += 1
    station = [p for p, g in pos.items() if g not in ("shuttle", "solar")]
    xs = [p[0] for p in station]
    ys = [p[1] for p in station]
    cx, cy = sum(xs) / len(xs), sum(ys) / len(ys)
    place = {}
    for g, ps in where.items():
        gx = sum(p[0] for p in ps) / len(ps)
        gy = sum(p[1] for p in ps) / len(ps)
        place[g] = dict(angle=round(math.degrees(math.atan2(gy - cy, gx - cx))),
                        dist=round(math.hypot(gx - cx, gy - cy)))
    crew = sum(v for k, v in starts.items() if k not in ("ai", "cyborg", "assistant"))
    return dict(name=name, size=(m.maxx, m.maxy), bbox=(min(xs), min(ys), max(xs), max(ys)),
                open=sum(tiles.values()), tiles=dict(tiles), rooms={g: len(a) for g, a in areas.items()},
                starts=dict(starts), crew=crew, joins={"%s|%s" % k: v for k, v in joins.items()},
                place=place, other=dict(other.most_common(12)))


def main():
    out = {}
    for name, rel in MAPS.items():
        out[name] = s = study(name, rel)
        print("%-7s crew %3d  open %6d  bbox %s" % (name, s["crew"], s["open"], s["bbox"]))
    path = os.path.join(ROOT, "data", "mapforge", "station_study.json")
    with open(path, "w") as f:
        json.dump(out, f, indent=1)
    groups = sorted({g for s in out.values() for g in s["tiles"]})
    print("\ntiles per group")
    print("%-12s" % "" + "".join("%8s" % n for n in out))
    for g in groups:
        print("%-12s" % g + "".join("%8d" % out[n]["tiles"].get(g, 0) for n in out))
    print("%-12s" % "rooms(med)" + "".join("%8d" % out[n]["rooms"].get("medical", 0) for n in out))
    print("\ntop door joins per map")
    for n, s in out.items():
        top = sorted(s["joins"].items(), key=lambda kv: -kv[1])[:14]
        print(n, ", ".join("%s %d" % kv for kv in top))
    print("\nunclassified areas")
    for n, s in out.items():
        print(n, s["other"])


if __name__ == "__main__":
    main()
