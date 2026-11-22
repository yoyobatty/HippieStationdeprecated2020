"""Fast walker play judge (plan C4): walks the trips a crew makes in a shift, tile by tile, on human and generated maps
alike, and says where the generated ones walk worse. Seconds per map; the bot-shift judge is the slow, real one.

    python tools/mapforge/forge/trip_walk.py                 # human maps + _maps/map_files/Generated
    python tools/mapforge/forge/trip_walk.py a.dmm b.dmm     # human maps + these maps
    python tools/mapforge/forge/trip_walk.py --heat          # also traffic pictures, data/previews/mapforge/walk/

Walkable: floor and door tiles without a dense object (tables, machines, closets block; doors don't). Trips go from
the middle of one area to the nearest tile of another (TRIPS below: commutes, deliveries, patients, arrests, chem
runs, food, escape), shortest path, 4-way steps, as a player walks it. Measures:
    detour       walked tiles / straight-line (Manhattan) tiles, median over trips
    trip_len     median walked tiles / sqrt(station floor): trip length with map size taken out
    fail         trips that can't be walked at all
    through_dept share of walked tiles inside a department neither end belongs to (access stops it in play)
    maint_walk   share of walked tiles in maintenance (shortest path takes maint over halls)
    narrow       share of traffic on floor 1 tile wide (doors not counted)
    hot1         share of all traffic on the busiest 1% of walked tiles (one corridor carries everything)
    doors        doors passed per trip, median
    blocked_doors  airlocks with no walkable tile on one side (a machine or table parked in the doorway)
Output: data/mapforge/walk/report.txt, report.json (per-trip lengths, worst trips, spots).
"""
import json
import math
import os
import sys
from collections import Counter, defaultdict, deque

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import parse, space  # noqa: E402

ROOT = parse.ROOT
OUT = os.path.join(ROOT, "data", "mapforge", "walk")
PICS = os.path.join(ROOT, "data", "previews", "mapforge", "walk")

# area prefixes; the first one a map has is used
A = {
    "arrivals": ("/area/hallway/secondary/entry",),
    "escape": ("/area/hallway/secondary/exit",),
    "dorms": ("/area/crew_quarters/dorms", "/area/crew_quarters/locker"),
    "hop": ("/area/crew_quarters/heads/hop",),
    "bridge": ("/area/bridge",),
    "captain": ("/area/crew_quarters/heads/captain",),
    "bar": ("/area/crew_quarters/bar",),
    "kitchen": ("/area/crew_quarters/kitchen",),
    "hydro": ("/area/hydroponics",),
    "janitor": ("/area/janitor",),
    "chapel": ("/area/chapel/main", "/area/chapel"),
    "library": ("/area/library",),
    "medbay": ("/area/medical/medbay/central", "/area/medical/medbay", "/area/medical/sleeper"),
    "chem": ("/area/medical/chemistry",),
    "surgery": ("/area/medical/surgery",),
    "morgue": ("/area/medical/morgue",),
    "genetics": ("/area/medical/genetics",),
    "virology": ("/area/medical/virology",),
    "cmo": ("/area/crew_quarters/heads/cmo",),
    "secmain": ("/area/security/main",),
    "brig": ("/area/security/brig",),
    "prison": ("/area/security/prison",),
    "armory": ("/area/ai_monitored/security/armory",),
    "detective": ("/area/security/detectives_office",),
    "hos": ("/area/crew_quarters/heads/hos",),
    "research": ("/area/science/research", "/area/science/lab"),
    "rndlab": ("/area/science/lab",),
    "robotics": ("/area/science/robotics/lab", "/area/science/robotics"),
    "mechbay": ("/area/science/robotics/mechbay",),
    "xeno": ("/area/science/xenobiology",),
    "toxins": ("/area/science/mixing", "/area/science/storage"),
    "rd": ("/area/crew_quarters/heads/hor",),
    "engine": ("/area/engine/engineering",),
    "atmos": ("/area/engine/atmos", "/area/atmos"),
    "tech": ("/area/storage/tech",),
    "ce": ("/area/crew_quarters/heads/chief",),
    "cargo": ("/area/quartermaster/storage",),
    "cargooffice": ("/area/quartermaster/office", "/area/quartermaster/sorting"),
    "mining": ("/area/quartermaster/miningdock", "/area/quartermaster/miningoffice"),
    "qm": ("/area/quartermaster/qm",),
    "tools": ("/area/storage/primary", "/area/storage/tools"),
    "eva": ("/area/ai_monitored/storage/eva",),
    "upload": ("/area/ai_monitored/turret_protected/ai_upload",),
    "vault": ("/area/ai_monitored/nuke_storage", "/area/security/nuke_storage"),
}
DEPT_HOME = {"medbay": "medical", "chem": "medical", "surgery": "medical", "morgue": "medical", "genetics": "medical",
             "virology": "medical", "cmo": "medical", "secmain": "security", "brig": "security", "prison": "security",
             "armory": "security", "detective": "security", "hos": "security", "research": "science",
             "rndlab": "science", "robotics": "science", "mechbay": "science", "xeno": "science", "toxins": "science",
             "rd": "science", "engine": "engineering", "atmos": "atmos", "tech": "engineering", "ce": "engineering",
             "cargo": "cargo", "cargooffice": "cargo", "mining": "cargo", "qm": "cargo", "hop": "command",
             "bridge": "command", "captain": "command", "eva": "command", "vault": "command", "upload": "ai",
             "bar": "service", "kitchen": "service", "hydro": "service", "janitor": "service", "dorms": "dorms",
             "chapel": "civic", "library": "civic", "tools": "civic"}
DEPT_MAIN = ("medbay", "secmain", "research", "engine", "cargooffice", "bar", "bridge")
TRIPS = (
    # arriving crew and the shift commute
    [("arrivals", "hop"), ("arrivals", "bar"), ("arrivals", "medbay"), ("arrivals", "tools")] +
    [("dorms", d) for d in DEPT_MAIN + ("atmos", "hydro", "chem", "robotics", "janitor", "cargo")] +
    # inside departments
    [("chem", "medbay"), ("medbay", "surgery"), ("surgery", "morgue"), ("medbay", "genetics"), ("medbay", "virology"),
     ("cmo", "medbay"), ("secmain", "brig"), ("brig", "prison"), ("secmain", "armory"), ("hos", "secmain"),
     ("detective", "secmain"), ("research", "robotics"), ("robotics", "mechbay"), ("research", "xeno"),
     ("research", "toxins"), ("rd", "research"), ("engine", "atmos"), ("engine", "tech"), ("ce", "engine"),
     ("cargooffice", "cargo"), ("cargo", "mining"), ("qm", "cargo"), ("bridge", "captain"), ("bridge", "hop"),
     ("bridge", "eva"), ("bridge", "upload"), ("bridge", "vault"), ("hydro", "kitchen"), ("kitchen", "bar")] +
    # across the station: deliveries, patients, arrests, repairs, chem runs, food, the chaplain's bodies
    [("cargo", d) for d in ("medbay", "research", "engine", "kitchen", "secmain", "bar", "hydro")] +
    [(d, "medbay") for d in ("engine", "research", "cargo", "secmain", "bar", "arrivals", "atmos")] +
    [("secmain", d) for d in ("medbay", "research", "engine", "cargooffice", "bar", "bridge", "arrivals", "escape")] +
    [("engine", d) for d in ("bridge", "medbay", "research", "secmain", "cargo")] +
    [("chem", "research"), ("chem", "bar"), ("robotics", "medbay"), ("morgue", "chapel"), ("janitor", "escape"),
     ("janitor", "medbay"), ("library", "bar"), ("hydro", "bar")] +
    # end of shift
    [(d, "escape") for d in DEPT_MAIN + ("dorms", "hydro", "atmos", "xeno", "prison")]
)

FEATURES = [
    ("detour", "ratio", "walked / straight-line tiles, median over trips"),
    ("detour_p90", "ratio", "walked / straight-line tiles, 90th percentile (the worst trips)"),
    ("trip_len", "x sqrtA", "median walked tiles / sqrt(station floor)"),
    ("fail", "share", "trips that can't be walked"),
    ("through_dept", "share", "walked tiles inside a department neither end belongs to (a shortcut access stops in play)"),
    ("maint_walk", "share", "walked tiles in maintenance"),
    ("narrow", "share", "traffic on floor 1 tile wide (doors not counted)"),
    ("hot1", "share", "traffic on the busiest 1% of walked tiles"),
    ("doors", "count", "doors passed per trip, median"),
    ("blocked_doors", "per 100", "airlocks with no walkable tile on one side, per 100 doors"),
]


def walkable(sm):
    return {p for p, c in sm.cls.items() if (c == "F" and p not in sm.dense) or c == "D"}


def area_tiles(sm, walk):
    """trip place -> walkable tiles of the first matching area prefix, station level only."""
    by = defaultdict(list)
    for p in walk:
        a = sm.area.get(p)
        if a:
            by[a].append(p)
    out = {}
    for key, pres in A.items():
        for pre in pres:
            ts = [p for a, v in by.items() if a == pre or a.startswith(pre + "/") for p in v
                  if sm.cls[p] == "F"]
            if len(ts) >= 4:
                out[key] = ts
                break
    return out


def piece(ts, walk):
    """The largest 4-connected walkable piece of a place: a trip starts there, not in a desk cluster."""
    left, best = set(ts), []
    while left:
        s = left.pop()
        comp, q = [s], deque([s])
        while q:
            a = q.popleft()
            for dx, dy in parse.DIRS:
                b = (a[0] + dx, a[1] + dy)
                if b in left:
                    left.discard(b)
                    comp.append(b)
                    q.append(b)
        if len(comp) > len(best):
            best = comp
    return best


def middle(ts):
    xs = sorted(p[0] for p in ts)
    ys = sorted(p[1] for p in ts)
    c = (xs[len(xs) // 2], ys[len(ys) // 2])
    return min(ts, key=lambda p: abs(p[0] - c[0]) + abs(p[1] - c[1]))




def width(walk, sm, p):
    """Cross-section of the walkable floor at p: the narrower of its horizontal and vertical runs."""
    def run(dx, dy):
        n = 1
        for s in (1, -1):
            q = (p[0] + s * dx, p[1] + s * dy)
            while q in walk and sm.cls[q] == "F":
                n += 1
                q = (q[0] + s * dx, q[1] + s * dy)
        return n
    return min(run(1, 0), run(0, 1))


def measure(sm):
    walk = walkable(sm)
    places = area_tiles(sm, walk)
    floor = len(sm.station_tiles())
    traffic = Counter()
    trips, fails, spots = [], [], defaultdict(list)
    for a, b in TRIPS:
        if a not in places or b not in places:
            continue
        src = middle(piece(places[a], walk))
        path = path_to(walk, src, set(places[b]))
        if path is None:
            fails.append((a, b))
            continue
        best = path[-1]
        L = len(path) - 1
        M = abs(src[0] - best[0]) + abs(src[1] - best[1])
        ha, hb = DEPT_HOME.get(a), DEPT_HOME.get(b)
        tres = mw = 0
        nd = 0
        for p in path:
            traffic[p] += 1
            g = sm.group.get(p)
            if sm.cls[p] == "D":
                nd += 1
            if g == "maint":
                mw += 1
            elif g and g not in (ha, hb) and g not in ("hall", "arrivals", "escape", "maint") and \
                    not g.startswith("other:"):
                tres += 1
        trips.append(dict(a=a, b=b, src=src, dst=best, L=L, M=M, detour=L / max(1, M), tres=tres, mw=mw, doors=nd))
    f = {}
    n = len(trips) + len(fails)
    if not trips:
        return {k: float("nan") for k, _, _ in FEATURES}, {}, {}
    dets = sorted(t["detour"] for t in trips)
    lens = sorted(t["L"] for t in trips)
    f["detour"] = dets[len(dets) // 2]
    f["detour_p90"] = dets[int(0.9 * (len(dets) - 1))]
    f["trip_len"] = lens[len(lens) // 2] / math.sqrt(max(1, floor))
    f["fail"] = len(fails) / float(max(1, n))
    walked = sum(t["L"] + 1 for t in trips)
    f["through_dept"] = sum(t["tres"] for t in trips) / float(walked)
    f["maint_walk"] = sum(t["mw"] for t in trips) / float(walked)
    tot = sum(traffic.values())
    narrow = 0
    for p, c in traffic.items():
        if sm.cls[p] == "F" and width(walk, sm, p) == 1:
            narrow += c
            if c >= 3:
                spots["narrow"].append(p)
    f["narrow"] = narrow / float(tot)
    top = sorted(traffic.values(), reverse=True)
    k = max(1, len(top) // 100)
    f["hot1"] = sum(top[:k]) / float(tot)
    ds = sorted(t["doors"] for t in trips)
    f["doors"] = ds[len(ds) // 2]
    blocked = 0
    for d in sm.doors:
        if sm.group.get(d) in (None, "shuttle", "solar") or not parse._has(sm.m.get(d[0], d[1], sm.z), parse.AIRLOCK):
            continue
        sides = 0
        for (dx, dy) in ((1, 0), (0, 1)):
            x, y = (d[0] + dx, d[1] + dy), (d[0] - dx, d[1] - dy)
            if sm.cls.get(x) in ("F", "D") and sm.cls.get(y) in ("F", "D"):
                sides += 1
                if x not in walk or y not in walk:
                    blocked += 1
                    spots["blocked_doors"].append(d)
    f["blocked_doors"] = 100.0 * blocked / max(1, len(sm.doors))
    for t in sorted(trips, key=lambda t: -t["detour"])[:8]:
        spots["worst_trips"].append([t["a"], t["b"], round(t["detour"], 2), t["L"], t["src"], t["dst"]])
    for a, b in fails:
        spots["fail"].append([a, b])
    for t in sorted(trips, key=lambda t: -t["tres"])[:5]:
        if t["tres"]:
            spots["through_dept"].append([t["a"], t["b"], t["tres"]])
    return f, dict(spots), dict(traffic=traffic, trips=trips, walk=walk)


def path_to(walk, src, goal):
    """Shortest 4-way path from src to the nearest goal tile, or None."""
    par = {src: None}
    q = deque([src])
    end = src if src in goal else None
    while q and end is None:
        a = q.popleft()
        for dx, dy in parse.DIRS:
            b = (a[0] + dx, a[1] + dy)
            if b in walk and b not in par:
                par[b] = a
                if b in goal:
                    end = b
                    break
                q.append(b)
    if end is None:
        return None
    out = []
    while end is not None:
        out.append(end)
        end = par[end]
    return out[::-1]


def heat(res, out_dir):
    """Traffic picture per map: walls dark, floor grey, walked tiles yellow to red by traffic, doors blue."""
    from PIL import Image
    from forge import gallery
    os.makedirs(out_dir, exist_ok=True)
    ims, caps = [], []
    for lab, v in res.items():
        sm = parse.load(v["path"])
        tr = v["extra"]["traffic"]
        walk = v["extra"]["walk"]
        xs = [p[0] for p in sm.cls]
        ys = [p[1] for p in sm.cls]
        x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
        # crop to the station floor
        st = sm.station_tiles()
        sx0, sy0, sx1, sy1 = sm.bbox(st)
        x0, y0, x1, y1 = max(x0, sx0 - 3), max(y0, sy0 - 3), min(x1, sx1 + 3), min(y1, sy1 + 3)
        img = Image.new("RGB", (x1 - x0 + 1, y1 - y0 + 1), (12, 13, 18))
        px = img.load()
        mx = max(tr.values()) if tr else 1
        for p, c in sm.cls.items():
            if not (x0 <= p[0] <= x1 and y0 <= p[1] <= y1):
                continue
            X, Y = p[0] - x0, y1 - p[1]
            if c == "W":
                col = (70, 74, 86)
            elif c == "D":
                col = (60, 110, 200)
            elif c == "F":
                g = sm.group.get(p)
                col = (34, 36, 44) if g == "maint" else (48, 50, 58) if p not in walk else (92, 94, 102)
            else:
                continue
            t = tr.get(p)
            if t:
                k = math.sqrt(t / float(mx))
                col = (255, int(230 - 200 * k), int(60 - 60 * k))
            px[X, Y] = col
        img = img.resize((img.width * 4, img.height * 4), Image.NEAREST)
        f = v["f"]
        ims.append(img)
        caps.append("%s  detour %.2f  narrow %.2f  hot1 %.3f" % (lab, f["detour"], f["narrow"], f["hot1"]))
    gallery._rows_sheet([(ims, caps)], os.path.join(out_dir, "traffic.png"),
                        "Walker traffic on %d trips (yellow little, red most; blue doors, dark maint)" % len(TRIPS),
                        H=520, maxw=3200)
    return os.path.join(out_dir, "traffic.png")


def main(argv):
    import time
    t0 = time.time()
    pics = "--heat" in argv
    argv = [a for a in argv if a != "--heat"]
    res = space.run_all(space.names_from(argv), measure)
    txt = space.range_table(res, FEATURES, "Walker play judge (plan C4): %d trips per map against %d human maps"
                            % (len(TRIPS), len(space.HUMAN)))
    lines = [txt, "", "worst trips (from, to, detour, tiles) and failures:"]
    for lab, v in res.items():
        if v["human"]:
            continue
        s = v["spots"]
        lines.append("  %s: worst %s" % (lab, "; ".join("%s>%s %.2f/%d" % tuple(w[:4]) for w in s.get("worst_trips", [])[:5])))
        if s.get("fail"):
            lines.append("    fail: %s" % ", ".join("%s>%s" % tuple(x) for x in s["fail"]))
        if s.get("through_dept"):
            lines.append("    through dept: %s" % ", ".join("%s>%s %d" % tuple(x) for x in s["through_dept"]))
        if s.get("blocked_doors"):
            lines.append("    blocked doors: %s" % " ".join("%d,%d" % tuple(d) for d in s["blocked_doors"][:12]))
    txt = "\n".join(lines)
    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(OUT, "report.txt"), "w").write(txt + "\n")
    json.dump({k: dict(f=v["f"], spots=v["spots"], path=v["path"], human=v["human"],
                       trips=[{kk: t[kk] for kk in ("a", "b", "L", "M", "detour", "tres", "mw", "doors")}
                              for t in v["extra"].get("trips", [])]) for k, v in res.items()},
              open(os.path.join(OUT, "report.json"), "w"), indent=1, default=list)
    print(txt)
    if pics:
        print("traffic picture:", heat(res, PICS))
    print("\n(%.1fs) %s" % (time.time() - t0, os.path.join(OUT, "report.txt")))


if __name__ == "__main__":
    main(sys.argv[1:])
