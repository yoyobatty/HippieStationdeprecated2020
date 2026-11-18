"""Fingerprint: about 40 numbers that describe how a station is built, at station, department, room, wall and tile
scale. Human maps give the range; a generated map is judged by where it falls in it.

    python tools/mapforge/forge/fingerprint.py                      # all human maps + _maps/map_files/Generated
    python tools/mapforge/forge/fingerprint.py data/x.dmm gen_spine_c80_s2   # also these maps

Writes data/mapforge/fingerprint/report.txt + report.json, and the chart
data/previews/mapforge/fingerprint/fingerprint.png (one row per feature: human range as a bar, human maps as grey
dots, generated maps as coloured dots). Each feature also keeps the tiles that make it (spots), so the worst places
can be cropped (crops.py).
"""
import glob
import json
import math
import os
import sys
from collections import Counter, defaultdict, deque

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import parse  # noqa: E402
from forge.parse import DIRS  # noqa: E402

ROOT = parse.ROOT
OUT = os.path.join(ROOT, "data", "mapforge", "fingerprint")
PICS = os.path.join(ROOT, "data", "previews", "mapforge", "fingerprint")
DEPTS = ("security", "medical", "science", "engineering", "cargo", "service", "command")
HUMAN = tuple(parse.humans())
N8 = [(dx, dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy]

# feature -> (scale, what it means); order is the report order
FEATURES = [
    ("floor_per_start", "station", "station floor tiles per job start landmark (humans place spares)"),
    ("hall_share", "station", "share of station floor that is public hall"),
    ("maint_share", "station", "share of station floor that is maintenance"),
    ("loops_per_1k", "station", "independent loops in the walkable region graph per 1000 floor tiles"),
    ("depth_mean", "station", "mean door steps from Arrivals to a room"),
    ("depth_max", "station", "most door steps from Arrivals to a room"),
    ("hull_rough", "station", "hull wall tiles per sqrt(floor): ragged hulls score higher"),
    ("hull_glass", "station", "share of hull wall that is window"),
    ("dept_fill", "department", "department outline / its bounding box, median (1 = plain rectangle)"),
    ("dept_corners", "department", "outline corners per 100 department tiles, median"),
    ("rooms_per_1k", "room", "rooms per 1000 station floor tiles"),
    ("room_area_med", "room", "median room area"),
    ("room_area_p90", "room", "90th percentile room area"),
    ("room_aspect_med", "room", "median long/short side of a room's box"),
    ("odd_share", "room", "share of rooms that are not rectangles (area/box < 0.9)"),
    ("room_corners_med", "room", "median corners of a room's outline (rectangle 4)"),
    ("doors_per_room", "room", "mean doors per room"),
    ("dead_end_share", "room", "share of rooms with one way in"),
    ("fill_med", "room", "median share of a room's floor under dense objects"),
    ("open_core_med", "room", "median share of a room's floor in its largest piece of free floor"),
    ("core_fill", "room", "share of room-centre floor (2+ tiles from the room edge) with furniture or machines"),
    ("wall_hug", "room", "share of furniture tiles touching a wall"),
    ("light_per_100", "fixture", "lights per 100 floor tiles"),
    ("vent_per_100", "fixture", "vents per 100 floor tiles"),
    ("scrubber_per_100", "fixture", "scrubbers per 100 floor tiles"),
    ("camera_per_100", "fixture", "cameras per 100 floor tiles"),
    ("sign_per_100", "fixture", "signs per 100 floor tiles"),
    ("wall_per_floor", "wall", "wall tiles touching floor per floor tile"),
    ("glass_share", "wall", "share of inner walls (both sides floor) that are glass"),
    ("doubled_per_1k", "wall", "floor-wall-wall-floor between two rooms, per 1000 floor"),
    ("corner_join_per_1k", "wall", "walls joined only by a corner, per 1000 floor"),
    ("slab_per_1k", "wall", "wall tiles buried in wall on all 8 sides, per 1000 floor"),
    ("overlap_per_1k", "tile", "wall faces carrying 2+ hung pieces, per 1000 floor"),
    ("decal_per_floor", "tile", "turf decals per floor tile"),
    ("tile_decal_per_floor", "tile", "colour tile decals per floor tile"),
    ("grime_per_floor", "tile", "dirt/grime per floor tile"),
    ("items_per_floor", "tile", "loose items per floor tile"),
    ("struct3_js", "tile", "3x3 structure patterns: Jensen-Shannon distance to the other human maps (0 same)"),
    ("furn3_js", "tile", "3x3 furniture-in-room patterns: JS distance to the other human maps"),
]
ORDER = [f[0] for f in FEATURES]
# features where a user ruling deliberately differs from the human maps: shown, never counted as a miss
RULED = {"overlap_per_1k": "one piece per wall face (ruling 2026-11-16); humans hang a light under signs/alarms"}


def _q(vals, q):
    if not vals:
        return 0.0
    s = sorted(vals)
    i = (len(s) - 1) * q
    lo, hi = int(math.floor(i)), int(math.ceil(i))
    return s[lo] + (s[hi] - s[lo]) * (i - lo)


def _canon(grid):
    """Smallest of the 8 symmetries of a 3x3 tuple (row-major)."""
    g = [grid[0:3], grid[3:6], grid[6:9]]
    best = None
    for _ in range(4):
        g = [list(r) for r in zip(*g[::-1])]
        for h in (g, [r[::-1] for r in g]):
            t = tuple(c for r in h for c in r)
            if best is None or t < best:
                best = t
    return "".join(best)


def measure(sm):
    st = set(sm.station_tiles())
    N = max(1, len(st))
    f, spots = {}, defaultdict(list)
    reg = sm.regions
    kinds = Counter(reg[sm.region[p]].kind for p in st)
    f["floor_per_start"] = N / float(sm.crew) if sm.crew else float("nan")
    f["hall_share"] = kinds["hall"] / float(N)
    f["maint_share"] = kinds["maint"] / float(N)

    # region graph over the station
    live = {r.id for r in reg.values() if r.kind != "other" and any(p in st for p in r.tiles[:1])}
    edges = set()
    for r in live:
        for b in reg[r].links:
            if b in live:
                edges.add((min(r, b), max(r, b)))
    comps, seen = 0, set()
    for r in live:
        if r in seen:
            continue
        comps += 1
        q = [r]
        seen.add(r)
        while q:
            a = q.pop()
            for b in reg[a].links:
                if b in live and b not in seen:
                    seen.add(b)
                    q.append(b)
    f["loops_per_1k"] = (len(edges) - len(live) + comps) * 1000.0 / N
    starts = [r for r in live if reg[r].group == "arrivals"]
    dist = {r: 0 for r in starts}
    dq = deque(starts)
    while dq:
        a = dq.popleft()
        for b in reg[a].links:
            if b in live and b not in dist:
                # walking along a hall or through an open seam costs nothing; a door costs one step
                dist[b] = dist[a] + (0 if reg[b].kind == "hall" and reg[a].kind == "hall" else 1)
                dq.append(b)
    rooms = [r for r in sm.rooms() if r.id in live]
    ds = [dist[r.id] for r in rooms if r.id in dist]
    f["depth_mean"] = sum(ds) / float(len(ds)) if ds else float("nan")
    f["depth_max"] = max(ds) if ds else float("nan")

    # hull
    hull = []
    for p, c in sm.cls.items():
        if c == "W" and any(sm.cls.get((p[0] + dx, p[1] + dy)) == "S" for dx, dy in DIRS) and \
                any((p[0] + dx, p[1] + dy) in st for dx, dy in N8):
            hull.append(p)
    f["hull_rough"] = len(hull) / math.sqrt(N)
    f["hull_glass"] = sum(1 for p in hull if p in sm.glass) / float(max(1, len(hull)))

    # departments
    fills, cors = [], []
    for d in DEPTS:
        main = [p for p in st if sm.group.get(p) == d]
        if len(main) < 60:
            continue
        # largest connected piece (walls/doors with 2+ department neighbours close it)
        mset = set(main)
        body = set(mset)
        for p, c in sm.cls.items():
            if c in "WD" and sum(1 for dx, dy in DIRS if (p[0] + dx, p[1] + dy) in mset) >= 2:
                body.add(p)
        pieces = _comps(body)
        b = pieces[0]
        x0, y0, x1, y1 = sm.bbox(b)
        fills.append(len(b) / float((x1 - x0 + 1) * (y1 - y0 + 1)))
        cors.append(parse.corners(b) * 100.0 / len(b))
    f["dept_fill"] = _q(fills, 0.5)
    f["dept_corners"] = _q(cors, 0.5)

    # rooms
    areas, aspects, cornersl, odd, doors, dead, fill, core, hug_n, hug_d = [], [], [], 0, [], 0, [], [], 0, 0
    for r in rooms:
        x0, y0, x1, y1 = sm.bbox(r.tiles)
        w, h = x1 - x0 + 1, y1 - y0 + 1
        a = len(r.tiles)
        areas.append(a)
        aspects.append(max(w, h) / float(min(w, h)))
        cornersl.append(parse.corners(r.tiles))
        if a / float(w * h) < 0.9:
            odd += 1
            spots["odd_share"].append(r.tiles[0])
        doors.append(len(r.doors))
        if len(r.links) <= 1:
            dead += 1
        dn = sum(1 for p in r.tiles if p in sm.dense)
        fill.append(dn / float(a))
        free = [p for p in r.tiles if p not in sm.dense and p not in sm.furn]
        core.append(len(_comps(free)[0]) / float(a) if free else 0.0)
        for p in r.tiles:
            if p in sm.furn:
                hug_d += 1
                if any(sm.cls.get((p[0] + dx, p[1] + dy)) == "W" for dx, dy in DIRS):
                    hug_n += 1
    n = max(1, len(rooms))
    f["rooms_per_1k"] = len(rooms) * 1000.0 / N
    f["room_area_med"] = _q(areas, 0.5)
    f["room_area_p90"] = _q(areas, 0.9)
    f["room_aspect_med"] = _q(aspects, 0.5)
    f["odd_share"] = odd / float(n)
    f["room_corners_med"] = _q(cornersl, 0.5)
    f["doors_per_room"] = sum(doors) / float(n)
    f["dead_end_share"] = dead / float(n)
    f["fill_med"] = _q(fill, 0.5)
    f["open_core_med"] = _q(core, 0.5)
    f["wall_hug"] = hug_n / float(max(1, hug_d))

    for k in ("light", "vent", "scrubber", "camera", "sign"):
        f[k + "_per_100"] = sm.count[k] * 100.0 / N

    # walls
    walls = [p for p, c in sm.cls.items() if c == "W" and any((p[0] + dx, p[1] + dy) in st for dx, dy in DIRS)]
    f["wall_per_floor"] = len(walls) / float(N)
    inner = [p for p in walls if sum(1 for dx, dy in DIRS if (p[0] + dx, p[1] + dy) in st) >= 2 and
             (((p[0] + 1, p[1]) in st and (p[0] - 1, p[1]) in st) or ((p[0], p[1] + 1) in st and (p[0], p[1] - 1) in st))]
    f["glass_share"] = sum(1 for p in inner if p in sm.glass) / float(max(1, len(inner)))
    dbl = 0
    for p in st:
        for dx, dy in ((1, 0), (0, 1)):
            a, b, c = (p[0] + dx, p[1] + dy), (p[0] + 2 * dx, p[1] + 2 * dy), (p[0] + 3 * dx, p[1] + 3 * dy)
            if sm.cls.get(a) == "W" and sm.cls.get(b) == "W" and c in st and a not in sm.glass and b not in sm.glass \
                    and sm.region.get(c) != sm.region.get(p):
                dbl += 1
                spots["doubled_per_1k"].append(a)
    f["doubled_per_1k"] = dbl * 1000.0 / N
    cj = 0
    xs = [p[0] for p in st]
    ys = [p[1] for p in st]
    for x in range(min(xs) - 1, max(xs) + 1):
        for y in range(min(ys) - 1, max(ys) + 1):
            a, b, c, d = sm.cls.get((x, y)), sm.cls.get((x + 1, y + 1)), sm.cls.get((x + 1, y)), sm.cls.get((x, y + 1))
            if a == "W" and b == "W" and c == "F" and d == "F" and ((x + 1, y) in st or (x, y + 1) in st):
                cj += 1
                spots["corner_join_per_1k"].append((x, y))
            elif c == "W" and d == "W" and a == "F" and b == "F" and ((x, y) in st or (x + 1, y + 1) in st):
                cj += 1
                spots["corner_join_per_1k"].append((x + 1, y))
    f["corner_join_per_1k"] = cj * 1000.0 / N
    slab = 0
    for p, c in sm.cls.items():
        if c == "W" and min(xs) <= p[0] <= max(xs) and min(ys) <= p[1] <= max(ys) and \
                all(sm.cls.get((p[0] + dx, p[1] + dy)) == "W" for dx, dy in N8):
            slab += 1
            spots["slab_per_1k"].append(p)
    f["slab_per_1k"] = slab * 1000.0 / N

    # tile look
    ov = [k for k, v in sm.hung.items() if k[0] in st and len(set(v)) >= 2 and not _pair_ok(v)]
    f["overlap_per_1k"] = len(ov) * 1000.0 / N
    spots["overlap_per_1k"] = [k[0] for k in ov]
    f["decal_per_floor"] = sm.count["decal"] / float(N)
    f["tile_decal_per_floor"] = sm.count["tile_decal"] / float(N)
    f["grime_per_floor"] = sm.count["grime"] / float(N)
    f["items_per_floor"] = sum(v for p, v in sm.items.items() if p in st) / float(N)

    # 3x3 pattern histograms (the JS distance is filled in against the other maps in report())
    s3, f3 = Counter(), Counter()
    for p in st:
        g = []
        g2 = []
        for dy in (1, 0, -1):
            for dx in (-1, 0, 1):
                q = (p[0] + dx, p[1] + dy)
                c = sm.cls.get(q, "S")
                g.append("G" if q in sm.glass else c)
                if c == "F":
                    g2.append("x" if q in sm.dense else "f" if q in sm.furn else ".")
                else:
                    g2.append(c)
        s3[_canon(tuple(g))] += 1
        if sm.region.get(p) is not None and reg[sm.region[p]].kind == "room":
            f3[_canon(tuple(g2))] += 1
    # room centres: tiles with the room all round them for 2 tiles; generated rooms push everything to the walls
    inner = full = 0
    for r in sm.rooms(20):
        rs = set(r.tiles)
        core = [p for p in rs if all((p[0] + dx, p[1] + dy) in rs for dx in range(-2, 3) for dy in range(-2, 3))]
        if len(core) < 4:
            continue
        k = [p for p in core if p in sm.dense or p in sm.furn]
        inner += len(core)
        full += len(k)
        if not k:
            spots["core_fill"].append(_mid_of(core))
    f["core_fill"] = full / float(inner) if inner else float("nan")
    return f, spots, {"struct3": s3, "furn3": f3}


def _mid_of(ts):
    xs, ys = sorted(p[0] for p in ts), sorted(p[1] for p in ts)
    c = (xs[len(xs) // 2], ys[len(ys) // 2])
    return min(ts, key=lambda p: abs(p[0] - c[0]) + abs(p[1] - c[1]))


PAIRS = ({"/obj/structure/sink", "/obj/structure/mirror"},)


def _pair_ok(v):
    kinds = set(v)
    return any(kinds <= set(pr) | {x for x in kinds if any(x.startswith(y) for y in pr)} and len(kinds) == 2
               for pr in PAIRS) and all(any(x.startswith(y) for y in PAIRS[0]) for x in kinds)


def _comps(tiles):
    left, out = set(tiles), []
    while left:
        s = left.pop()
        c, q = [s], [s]
        while q:
            a = q.pop()
            for dx, dy in DIRS:
                b = (a[0] + dx, a[1] + dy)
                if b in left:
                    left.discard(b)
                    c.append(b)
                    q.append(b)
        out.append(c)
    out.sort(key=len, reverse=True)
    return out or [[]]


def js(a, b):
    ta, tb = float(sum(a.values())) or 1.0, float(sum(b.values())) or 1.0
    d = 0.0
    for k in set(a) | set(b):
        pa, pb = a.get(k, 0) / ta, b.get(k, 0) / tb
        m = (pa + pb) / 2
        if pa:
            d += 0.5 * pa * math.log(pa / m, 2)
        if pb:
            d += 0.5 * pb * math.log(pb / m, 2)
    return math.sqrt(max(0.0, d))


def run(names):
    res = {}
    for n in names:
        sm = parse.load(n)
        f, spots, hist = measure(sm)
        label = sm.name
        if os.path.exists(n) and os.path.dirname(os.path.abspath(n)) != os.path.join(ROOT, "_maps", "map_files", "Generated"):
            label = "new:" + sm.name.replace("gen_", "").replace("_c80", "")
        res[label] = dict(f=f, spots=spots, hist=hist, human=n in HUMAN, path=parse.map_path(n))
    humans = [k for k, v in res.items() if v["human"]]
    for k, v in res.items():
        for h in ("struct3", "furn3"):
            pool = Counter()
            for o in humans:
                if o != k:
                    pool.update(res[o]["hist"][h])
            v["f"][h + "_js"] = js(v["hist"][h], pool)
    return res


def table(res):
    humans = [k for k, v in res.items() if v["human"]]
    gens = [k for k, v in res.items() if not v["human"]]
    lines = []
    w = max(len(g) for g in gens) if gens else 8
    lines.append("%-22s %-10s %8s %8s %8s  %s" % ("feature", "scale", "h.min", "h.med", "h.max",
                                                   "  ".join("%*s" % (w, g) for g in gens)))
    out_of = Counter()
    rng = {}
    for name, scale, _ in FEATURES:
        hv = [res[h]["f"][name] for h in humans if not math.isnan(res[h]["f"][name])]
        lo, med, hi = min(hv), _q(hv, 0.5), max(hv)
        if len(hv) >= 20:  # with the whole corpus, one odd map shouldn't set the range: 10th-90th percentile
            lo, hi = _q(hv, 0.1), _q(hv, 0.9)
        rng[name] = (lo, med, hi)
        cells = []
        for g in gens:
            v = res[g]["f"][name]
            flag = " "
            if name in RULED:
                flag = "r"
            elif not math.isnan(v) and (v < lo or v > hi):
                flag = "<" if v < lo else ">"
                out_of[g] += 1
            cells.append("%*s" % (w, "%.3g%s" % (v, flag)))
        lines.append("%-22s %-10s %8.3g %8.3g %8.3g  %s" % (name, scale, lo, med, hi, "  ".join(cells)))
    lines.append("")
    lines.append("outside the human range (< below, > above; r = ruling, not counted): " +
                 ", ".join("%s %d/%d" % (g, out_of[g], len(FEATURES) - len(RULED)) for g in gens))
    for k, why in RULED.items():
        lines.append("  ruling %s: %s" % (k, why))
    return "\n".join(lines), rng, out_of


def chart(res, rng, png):
    from PIL import Image, ImageDraw
    from forge.render import _font
    humans = [k for k, v in res.items() if v["human"]]
    gens = [k for k, v in res.items() if not v["human"]]
    pal = [(230, 90, 70), (70, 160, 230), (240, 190, 60), (150, 220, 110), (210, 120, 230), (90, 220, 210)]
    RW, LW, BW, RH = 1100, 300, 680, 26
    img = Image.new("RGB", (RW, 70 + RH * len(FEATURES) + 30), (22, 24, 30))
    d = ImageDraw.Draw(img)
    ft, fs = _font(16), _font(12)
    d.text((12, 10), "Fingerprint: human range (bar), human maps (grey), generated maps (colour)", fill=(240, 240, 240), font=ft)
    for i, g in enumerate(gens):
        d.rectangle([12 + i * 180, 38, 22 + i * 180, 48], fill=pal[i % len(pal)])
        d.text((28 + i * 180, 35), g, fill=(220, 220, 220), font=fs)
    y = 64
    lastscale = None
    for name, scale, _ in FEATURES:
        lo, med, hi = rng[name]
        vals = [res[k]["f"][name] for k in res if not math.isnan(res[k]["f"][name])]
        span = (hi - lo) or abs(hi) or 1.0
        a, b = min(vals + [lo - 0.25 * span]), max(vals + [hi + 0.25 * span])
        X = lambda v: LW + int((v - a) / ((b - a) or 1.0) * BW)  # noqa: E731
        if scale != lastscale:
            d.line([(10, y - 2), (RW - 10, y - 2)], fill=(60, 64, 72))
            lastscale = scale
        d.text((12, y + 4), "%s  (%s)%s" % (name, scale, "  [ruling]" if name in RULED else ""),
               fill=(150, 150, 150) if name in RULED else (210, 210, 210), font=fs)
        d.rectangle([X(lo), y + 8, X(hi), y + 16], fill=(70, 76, 88))
        d.line([(X(med), y + 5), (X(med), y + 19)], fill=(200, 200, 200))
        for h in humans:
            v = res[h]["f"][name]
            if not math.isnan(v):
                d.ellipse([X(v) - 3, y + 9, X(v) + 3, y + 15], fill=(150, 150, 150))
        for i, g in enumerate(gens):
            v = res[g]["f"][name]
            if math.isnan(v):
                continue
            out = (v < lo or v > hi) and name not in RULED
            r = 6 if out else 4
            d.ellipse([X(v) - r, y + 12 - r, X(v) + r, y + 12 + r], fill=pal[i % len(pal)],
                      outline=(255, 255, 255) if out else None)
        d.text((LW + BW + 12, y + 4), "%.3g .. %.3g" % (lo, hi), fill=(150, 150, 150), font=fs)
        y += RH
    os.makedirs(os.path.dirname(png), exist_ok=True)
    img.save(png)


def main(extra):
    gens = []
    if "--fresh" in extra:   # only the maps named (trial builds), not the committed Generated ones
        extra = [e for e in extra if e != "--fresh"]
    else:
        gens = sorted(os.path.splitext(os.path.basename(p))[0]
                      for p in glob.glob(os.path.join(ROOT, "_maps", "map_files", "Generated", "*.dmm")))
    res = run(list(HUMAN) + gens + extra)
    txt, rng, _ = table(res)
    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(OUT, "report.txt"), "w").write(txt + "\n")
    json.dump({k: dict(f=v["f"], human=v["human"], path=v["path"], spots={s: v["spots"][s][:400] for s in v["spots"]})
               for k, v in res.items()}, open(os.path.join(OUT, "report.json"), "w"))
    chart(res, rng, os.path.join(PICS, "fingerprint.png"))
    print(txt)
    return res


if __name__ == "__main__":
    main(sys.argv[1:])
