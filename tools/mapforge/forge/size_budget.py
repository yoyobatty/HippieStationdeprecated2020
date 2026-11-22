"""Size budget: where a map spends its floor, against Meta, Delta, Omega and Hippie. It answers three questions with
numbers only: which rooms are too big for their type, which room types the stock stations have that this map
lacks, and whether a department's share of the station is in the stock range. The resize pass
(station/v6_resize.py) works from its plan; rerun it after every build to see what is left.

    python tools/mapforge/forge/size_budget.py data/mapforge/station_v6.dmm [--json out.json]

oversized  a room bigger than every stock room of its type (3+ stock rooms), or than 1.25x the biggest when
           only 2 stock rooms have the type. target = the stock median; excess = tiles - target.
undersized a room smaller than every stock room of its type (same rule), for the record.
missing    an area type (exact path) that 3 or 4 of the four stock maps have and this map has nowhere. Its size
           is the stock median; its group is the department it belongs to (studies/stations.py GROUPS).
groups     each department's share of the station floor (station tiles: no space, shuttles, solars), with the
           stock min..max; floor tiles per crew slot for the whole station.
budget     per group: tiles freed by shrinking oversized rooms, tiles the missing room types of that group would
           take, and what is left over (negative: the group would grow).
halls      hall floor by width (the shorter of the tile's row and column runs through hall floor; 9 = 9 or more),
           against the stock maps; --picture draws the map with halls green (3 wide or less), yellow (4-6) and
           red (7+) to data/previews/mapforge/size_budget_<map>.png.
"""
import argparse
import json
import os
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import parse, room_stats as RS  # noqa: E402

MIN_PEERS = 3


def _med(vs):
    vs = sorted(vs)
    return vs[len(vs) // 2] if vs else 0


def group_shares(sm):
    st = sm.station_tiles()
    c = Counter(sm.group.get(p) for p in st)
    n = float(len(st))
    return {g: c[g] / n for g in c}, len(st)


HALL_GROUPS = ("hall", "arrivals", "escape")


def hall_widths(sm):
    """hall tile -> width (capped at 9)."""
    hall = {p for p, c in sm.cls.items() if c == "F" and sm.group.get(p) in HALL_GROUPS}

    def run(p, dx, dy):
        n, q = 1, (p[0] + dx, p[1] + dy)
        while q in hall:
            n, q = n + 1, (q[0] + dx, q[1] + dy)
        q = (p[0] - dx, p[1] - dy)
        while q in hall:
            n, q = n + 1, (q[0] - dx, q[1] - dy)
        return n
    return {p: min(run(p, 1, 0), run(p, 0, 1), 9) for p in hall}


def width_shares(sm):
    w = hall_widths(sm)
    n = float(max(1, len(w)))
    return dict(narrow=sum(1 for v in w.values() if v <= 3) / n, mid=sum(1 for v in w.values() if 4 <= v <= 6) / n,
                wide=sum(1 for v in w.values() if v >= 7) / n)


def picture(sm, out, scale=5):
    from PIL import Image
    w = hall_widths(sm)
    W, H = sm.m.maxx, sm.m.maxy
    im = Image.new("RGB", (W, H), (12, 12, 14))
    px = im.load()
    for p, c in sm.cls.items():
        col = {"W": (70, 70, 75), "D": (190, 170, 90), "F": (120, 120, 125)}.get(c, (12, 12, 14))
        if p in w:
            col = (60, 160, 90) if w[p] <= 3 else (220, 180, 40) if w[p] <= 6 else (220, 60, 40)
        px[p[0] - 1, H - p[1]] = col
    im.resize((W * scale, H * scale), Image.NEAREST).save(out)


def maint_pockets(sm):
    """Enclosed maint spaces wider than a corridor (a maint region with at least one tile whose whole 3x3 block is
    its floor): [(tiles, furniture per tile, box, area, region)]. Stock maps keep these as junk rooms."""
    out = []
    for r in sm.regions.values():
        if r.kind != "maint":
            continue
        ts = set(r.tiles)
        if not any(all((p[0] + dx, p[1] + dy) in ts for dx in (-1, 0, 1) for dy in (-1, 0, 1)) for p in ts):
            continue
        out.append((len(ts), sum(1 for p in ts if p in sm.furn) / float(len(ts)), sm.bbox(r.tiles), r.area, r))
    return out


def stock_pocket_band():
    """(the emptiest fill any stock map tolerates: its 10th percentile, lowest of the four; the biggest pocket)."""
    p10s, big = [], 0
    for n in RS.REFS:
        ps = maint_pockets(parse.load(n))
        fr = sorted(p[1] for p in ps)
        if fr:
            p10s.append(fr[len(fr) // 10])
        big = max([big] + [p[0] for p in ps])
    return min(p10s), big


def missing(sm, rooms=None):
    """Area types (exact paths) in 3+ of the 4 stock maps that the map has nowhere (not even under a parent)."""
    rooms = RS.rooms(sm) if rooms is None else rooms
    have = {r.area for r in rooms} | set(sm.area.values())
    per_type = defaultdict(dict)
    for name in RS.REFS:
        for r in RS.rooms(parse.load(name)):
            per_type[r.area][name] = r.stats["tiles"]
    out = []
    for area, by in sorted(per_type.items()):
        if len(by) < 3 or any(h == area or h.startswith(area + "/") for h in have):
            continue
        out.append(dict(area=area, maps=sorted(RS.SHORT[k] for k in by), tiles=int(_med(list(by.values()))),
                        group=parse.ST.group_of(area)))
    return out


def plan(path):
    sm = parse.load(path)
    rooms = RS.rooms(sm)
    out = dict(oversized=[], undersized=[], missing=[], groups={}, budget={})
    for rm in rooms:
        kind = RS.type_of(rm.area)
        if not kind:
            continue
        peers = RS.peers(kind)
        sizes = [p.stats["tiles"] for p in peers]
        if len(peers) < 2:
            continue
        hi = max(sizes) * (1.0 if len(peers) >= MIN_PEERS else 1.25)
        lo = min(sizes) * (1.0 if len(peers) >= MIN_PEERS else 0.8)
        g = Counter(sm.group.get(p) for p in rm.tiles).most_common(1)[0][0]
        row = dict(area=rm.area, type=kind, group=g, tiles=int(rm.stats["tiles"]), box=rm.box,
                   stock=sorted(int(s) for s in sizes), target=int(_med(sizes)), peers=len(peers))
        if rm.stats["tiles"] > hi:
            row["excess"] = row["tiles"] - row["target"]
            out["oversized"].append(row)
        elif rm.stats["tiles"] < lo:
            out["undersized"].append(row)
    out["missing"] = missing(sm, rooms)
    # department shares
    mine, n = group_shares(sm)
    stock = {name: group_shares(parse.load(name)) for name in RS.REFS}
    for g in sorted(set(mine) | {g for s, _ in stock.values() for g in s}):
        if g in (None, "shuttle", "solar") or (g or "").startswith("other"):
            continue
        vs = [s.get(g, 0.0) for s, _ in stock.values()]
        out["groups"][g] = dict(share=round(mine.get(g, 0.0), 4), stock_min=round(min(vs), 4), stock_max=round(max(vs), 4),
                                tiles=int(mine.get(g, 0.0) * n))
    crew_stock = []
    for name in RS.REFS:
        s = parse.load(name)
        if s.crew:
            crew_stock.append(len(s.station_tiles()) / float(s.crew))
    out["station"] = dict(tiles=n, crew=sm.crew, per_crew=round(n / max(1, sm.crew), 1),
                          stock_per_crew=[round(v, 1) for v in sorted(crew_stock)])
    out["halls"] = dict(map=width_shares(sm), stock={RS.SHORT[k]: width_shares(parse.load(k)) for k in RS.REFS})
    for g in out["groups"]:
        freed = sum(r["excess"] for r in out["oversized"] if r["group"] == g)
        need = sum(r["tiles"] for r in out["missing"] if r["group"] == g)
        out["budget"][g] = dict(freed=freed, missing=need, left=freed - need)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("map")
    ap.add_argument("--json", default="")
    ap.add_argument("--picture", action="store_true")
    a = ap.parse_args()
    path = a.map
    if not os.path.exists(path) and os.path.exists(os.path.join(parse.ROOT, "data", "mapforge", path)):
        path = os.path.join(parse.ROOT, "data", "mapforge", path)
    p = plan(path)
    s = p["station"]
    print("station: %d floor tiles, %d crew slots, %.1f tiles per slot (stock %s)" % (
        s["tiles"], s["crew"], s["per_crew"], ", ".join(map(str, s["stock_per_crew"]))))
    print("\noversized (%d rooms, %d excess tiles):" % (len(p["oversized"]), sum(r["excess"] for r in p["oversized"])))
    for r in sorted(p["oversized"], key=lambda r: -r["excess"]):
        print("  %-12s %-44s %4d tiles, stock %s -> target %d (excess %d)" % (
            r["group"], r["area"][:44], r["tiles"], r["stock"], r["target"], r["excess"]))
    print("\nundersized (%d rooms):" % len(p["undersized"]))
    for r in p["undersized"]:
        print("  %-12s %-44s %4d tiles, stock %s" % (r["group"], r["area"][:44], r["tiles"], r["stock"]))
    print("\nmissing room types (in 3+ of the 4 stock maps):")
    for r in sorted(p["missing"], key=lambda r: (r["group"] or "", r["area"])):
        print("  %-12s %-44s ~%d tiles (%s)" % (r["group"], r["area"][:44], r["tiles"], " ".join(r["maps"])))
    print("\ndepartment share of station floor (stock min..max):")
    for g, v in sorted(p["groups"].items(), key=lambda kv: -kv[1]["share"]):
        flag = " HIGH" if v["share"] > v["stock_max"] else " LOW" if v["share"] < v["stock_min"] else ""
        b = p["budget"].get(g, {})
        print("  %-12s %5.1f%%  (%4.1f..%4.1f)%-5s  freed %4d, missing rooms %4d, left %+5d" % (
            g, 100 * v["share"], 100 * v["stock_min"], 100 * v["stock_max"], flag, b.get("freed", 0), b.get("missing", 0), b.get("left", 0)))
    h = p["halls"]
    print("\nhall floor by width (<=3 / 4-6 / 7+):")
    for k, v in [("this map", h["map"])] + sorted(h["stock"].items()):
        print("  %-10s %3.0f%% / %3.0f%% / %3.0f%%" % (k, 100 * v["narrow"], 100 * v["mid"], 100 * v["wide"]))
    if a.picture:
        out = os.path.join(parse.ROOT, "data", "previews", "mapforge", "size_budget_%s.png" % os.path.splitext(os.path.basename(path))[0])
        picture(parse.load(path), out)
        print("->", os.path.relpath(out, parse.ROOT))
    if a.json:
        json.dump(p, open(a.json, "w"), indent=1)


if __name__ == "__main__":
    main()
