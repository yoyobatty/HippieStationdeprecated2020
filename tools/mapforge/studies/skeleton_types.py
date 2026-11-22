"""Skeleton types of the human stations: how the public halls are shaped (a core loop with spokes, a wide donut
loop, a spine, separate islands, a tree), measured on every map in parse.humans(), so the generator picks and sizes
its skeleton from data.

    python tools/mapforge/studies/skeleton_types.py               # table + bands, data/mapforge/gen_targets/
    python tools/mapforge/studies/skeleton_types.py --picture     # contact sheet of every map's skeleton
    python tools/mapforge/studies/skeleton_types.py --map data/mapforge/station_v6.dmm   # one build against the bands
    python tools/mapforge/studies/skeleton_types.py --fresh       # measure again (ignore the cache)

What it measures, per map (hall = floor of /area/hallway, arrivals and escape; an airlock between two hall tiles
counts as hall; maint = /area/maintenance):
  hall_share  hall floor / station floor. Under 0.04 the map doesn't tag its halls as /area/hallway (Nebula):
              flagged "untagged" and left out of the bands.
  loops       blocks the halls close round: pockets of non-hall that the outside can't reach, 30+ tiles. A hall
              loop round a block is one loop; a pillar in a wide hall is not.
  core        station floor inside the core loop (the loop holding the station's centre, else the nearest) / all
              station floor. core_dist: that loop's centroid from the station centroid, over the station radius.
  core_groups departments inside the core loop, as shares of its floor.
  spokes      hall pieces of 30+ tiles that leave the core loop's rim (the loop's hall, 3 tiles deep): the arms of a
              hub. spoke_len = median of each spoke's farthest walk from the rim; spoke_reach = median of each
              spoke's farthest tile from the station centre, over the station radius.
  arms        hall branches 10+ tiles long from a junction to a dead end (on the thinned hall centre line);
              arm_len their median length.
  spine       longest shortest walk along the hall centre line / the station's long side.
  on_loop     share of hall floor within 3 tiles of a loop's block (the rest hangs off as spokes and spurs).
  walk_loops  loops of hall + maint together (maint is the second network: how many loops it adds).
  aspect      station box short side / long side; fill = station floor / station box.
  main        share of hall floor in the biggest 4-connected piece.

Type, from those numbers (the contact sheet, --picture, shows each map's halls, centre line and loop blocks):
  hub        a loop within 0.25 of the radius from the centre: a core loop with spokes out to the edge
             (Meta, Delta, Box, Hippie, Pubby...). hub-donut when that loop holds 10%+ of the floor (Donut, Omega,
             Cere: the departments ring a wide round loop).
  spine      no central loop, and the hall centre line runs 0.75+ of the station's long side.
  islands    under 60% of the hall floor in one piece: separate halls joined by maint, a tram or catwalks.
  tree       the rest: branching halls, no loop.
"""
import argparse
import math
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import corpus_common as CC  # noqa: E402
from forge import parse  # noqa: E402

STUDY = "skeleton"
VERSION = 4
MIN_HOLE = 30
ARM_MIN = 10
HALL = ("hall", "arrivals", "escape")
N8 = [(dx, dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy]
N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))


def hall_set(sm, groups=HALL):
    H = {p for p, c in sm.cls.items() if c == "F" and sm.group.get(p) in groups}
    for p, c in sm.cls.items():  # an airlock between two tiles of the set joins them
        if c != "D":
            continue
        for dx, dy in ((1, 0), (0, 1)):
            if (p[0] + dx, p[1] + dy) in H and (p[0] - dx, p[1] - dy) in H:
                H.add(p)
                break
    return H


def holes(S, bbox):
    """4-connected components of the complement of S inside bbox+1 that don't reach the border: [set]."""
    x0, y0, x1, y1 = bbox
    x0, y0, x1, y1 = x0 - 1, y0 - 1, x1 + 1, y1 + 1
    seen = set()
    out = []
    for x in range(x0, x1 + 1):
        for y in range(y0, y1 + 1):
            p = (x, y)
            if p in S or p in seen:
                continue
            comp, stack, edge = [], [p], False
            seen.add(p)
            while stack:
                a = stack.pop()
                comp.append(a)
                if a[0] in (x0, x1) or a[1] in (y0, y1):
                    edge = True
                for dx, dy in N4:
                    b = (a[0] + dx, a[1] + dy)
                    if b in seen or b in S or not (x0 <= b[0] <= x1 and y0 <= b[1] <= y1):
                        continue
                    seen.add(b)
                    stack.append(b)
            if not edge:
                out.append(set(comp))
    return out


def thin(S):
    """Zhang-Suen thinning of a tile set: the hall's centre lines."""
    S = set(S)

    def nb(p):
        x, y = p
        return [(x, y + 1) in S, (x + 1, y + 1) in S, (x + 1, y) in S, (x + 1, y - 1) in S,
                (x, y - 1) in S, (x - 1, y - 1) in S, (x - 1, y) in S, (x - 1, y + 1) in S]

    changed = True
    while changed:
        changed = False
        for step in (0, 1):
            drop = []
            for p in S:
                n = nb(p)
                b = sum(n)
                if b < 2 or b > 6:
                    continue
                if sum(1 for i in range(8) if not n[i] and n[(i + 1) % 8]) != 1:
                    continue
                P2, P4, P6, P8 = n[0], n[2], n[4], n[6]
                if step == 0 and (P2 and P4 and P6 or P4 and P6 and P8):
                    continue
                if step == 1 and (P2 and P4 and P8 or P2 and P6 and P8):
                    continue
                drop.append(p)
            if drop:
                S.difference_update(drop)
                changed = True
    return S


def _deg(K, p):
    return sum(1 for dx, dy in N8 if (p[0] + dx, p[1] + dy) in K)


def arms(K):
    """Branch lengths from each centre-line end (degree 1) to the first junction (degree 3+)."""
    out = []
    for p in K:
        if _deg(K, p) != 1:
            continue
        prev, cur, n = None, p, 1
        while n < 2000:
            nxt = [(cur[0] + dx, cur[1] + dy) for dx, dy in N8 if (cur[0] + dx, cur[1] + dy) in K]
            nxt = [q for q in nxt if q != prev]
            if len(nxt) != 1 or _deg(K, cur) >= 3:
                break
            prev, cur = cur, nxt[0]
            n += 1
        out.append(n)
    return out


def _bfs(K, s, nbrs=N8):
    dist = {s: 0}
    q = [s]
    i = 0
    while i < len(q):
        a = q[i]
        i += 1
        for dx, dy in nbrs:
            b = (a[0] + dx, a[1] + dy)
            if b in K and b not in dist:
                dist[b] = dist[a] + 1
                q.append(b)
    return dist


def diameter(K):
    """Longest shortest path over each centre-line piece (two sweeps), the biggest."""
    best = 0
    left = set(K)
    while left:
        s = next(iter(left))
        d = _bfs(K, s)
        left.difference_update(d)
        if len(d) < 10:
            continue
        far = max(d, key=d.get)
        best = max(best, max(_bfs(K, far).values()))
    return best


def comps4(S):
    seen, out = set(), []
    for p in S:
        if p in seen:
            continue
        comp, st = [], [p]
        seen.add(p)
        while st:
            a = st.pop()
            comp.append(a)
            for dx, dy in N4:
                b = (a[0] + dx, a[1] + dy)
                if b in S and b not in seen:
                    seen.add(b)
                    st.append(b)
        out.append(comp)
    return sorted(out, key=len, reverse=True)


def _layer(H, seed, deep):
    on, frontier = set(seed), set(seed)
    for _ in range(deep):
        nxt = set()
        for p in frontier:
            for dx, dy in N4:
                q = (p[0] + dx, p[1] + dy)
                if q in H and q not in on:
                    nxt.add(q)
        on |= nxt
        frontier = nxt
    return on


def _rim(h, H):
    return {(p[0] + dx, p[1] + dy) for p in h for dx, dy in N8 if (p[0] + dx, p[1] + dy) in H}


def spokes(H, core_zone, cx, cy, radius):
    """[(tiles, walk from the rim, reach)] of hall pieces (30+ tiles) touching the core zone once it is taken out."""
    out = []
    for comp in comps4(H - core_zone):
        if len(comp) < 30:
            continue
        cs = set(comp)
        touch = [a for a in comp if any((a[0] + dx, a[1] + dy) in core_zone for dx, dy in N4)]
        if not touch:
            continue
        dist = {a: 0 for a in touch}
        q = list(touch)
        i = 0
        while i < len(q):
            a = q[i]
            i += 1
            for dx, dy in N4:
                b = (a[0] + dx, a[1] + dy)
                if b in cs and b not in dist:
                    dist[b] = dist[a] + 1
                    q.append(b)
        reach = max(math.hypot(a[0] - cx, a[1] - cy) for a in comp) / radius
        out.append((len(comp), max(dist.values()), reach))
    return out


def classify(v):
    if v["hall_share"] < 0.04:
        return "untagged"
    if v["main"] < 0.6:
        return "islands"
    if v["core_dist"] is not None and v["core_dist"] <= 0.25:
        return "hub-donut" if v["core"] >= 0.10 else "hub"
    if v["spine"] >= 0.75:
        return "spine"
    return "tree"


def measure(sm, keep=False):
    st = set(sm.station_tiles())
    if not st:
        return None
    bb = sm.bbox(st)
    W, Hh = bb[2] - bb[0] + 1, bb[3] - bb[1] + 1
    cx = sum(p[0] for p in st) / float(len(st))
    cy = sum(p[1] for p in st) / float(len(st))
    radius = max(math.hypot(p[0] - cx, p[1] - cy) for p in st)
    H = hall_set(sm)
    hs = [h for h in holes(H, bb) if len(h) >= MIN_HOLE]
    inside = [len(h & st) for h in hs]
    core, cdist, core_h = 0.0, None, None
    for h, n in zip(hs, inside):  # the core loop: the one holding the centre, else the nearest to it
        hx = sum(p[0] for p in h) / float(len(h))
        hy = sum(p[1] for p in h) / float(len(h))
        d = 0.0 if (int(round(cx)), int(round(cy))) in h else math.hypot(hx - cx, hy - cy) / radius
        if cdist is None or d < cdist:
            cdist, core_h, core = d, h, n / float(len(st))
    on = _layer(H, set().union(*[_rim(h, H) for h in hs]) if hs else set(), 3)
    core_zone = _layer(H, _rim(core_h, H), 3) if core_h else set()
    sp = spokes(H, core_zone, cx, cy, radius) if core_h else []
    K = thin(H)
    long_arms = sorted(a for a in arms(K) if a >= ARM_MIN)
    walk = hall_set(sm, HALL + ("maint",))
    whs = [h for h in holes(walk, bb) if len(h) >= MIN_HOLE]
    cs = comps4(H)
    cg = Counter(sm.group.get(p) for p in core_h & st) if core_h else Counter()
    tot = float(sum(cg.values()) or 1)
    v = dict(
        floor=len(st), crew=CC.crew(sm), hall=len(H), hall_share=round(len(H & st) / float(len(st)), 3),
        loops=len(hs), core=round(core, 3), core_dist=None if cdist is None else round(cdist, 3),
        spokes=len(sp), spoke_len=CC.median([s[1] for s in sp]) if sp else 0,
        spoke_reach=round(CC.median([s[2] for s in sp]), 3) if sp else 0,
        arms=len(long_arms), arm_len=CC.median(long_arms) if long_arms else 0,
        spine=round(diameter(K) / float(max(W, Hh)), 3),
        on_loop=round(len(on) / float(max(1, len(H))), 3), walk_loops=len(whs),
        aspect=round(min(W, Hh) / float(max(W, Hh)), 3), fill=round(len(st) / float(W * Hh), 3),
        main=round(len(cs[0]) / float(len(H)), 3) if cs else 0,
        core_groups={k: round(n / tot, 3) for k, n in cg.most_common(6)},
    )
    v["type"] = classify(v)
    if keep:
        v["_H"], v["_K"], v["_holes"], v["_bb"] = H, K, hs, bb
    return v


FEATURES = ("floor", "crew", "hall_share", "loops", "core", "core_dist", "spokes", "spoke_len", "spoke_reach", "arms",
            "arm_len", "spine", "on_loop", "walk_loops", "aspect", "fill", "main")


def picture(names, out):
    from PIL import Image, ImageDraw
    tiles = []
    for n in names:
        sm = parse.load(n)
        v = measure(sm, keep=True)
        if not v:
            continue
        x0, y0, x1, y1 = v["_bb"]
        W, Hh = x1 - x0 + 1, y1 - y0 + 1
        im = Image.new("RGB", (W, Hh), (10, 10, 14))
        px = im.load()
        st = set(sm.station_tiles())
        for p in st:
            px[p[0] - x0, y1 - p[1]] = (60, 60, 66) if sm.group.get(p) != "maint" else (45, 38, 30)
        for h in v["_holes"]:
            for p in h:
                if p in st:
                    px[p[0] - x0, y1 - p[1]] = (40, 70, 110)
        for p in v["_H"]:
            if x0 <= p[0] <= x1 and y0 <= p[1] <= y1:
                px[p[0] - x0, y1 - p[1]] = (150, 150, 150)
        for p in v["_K"]:
            if x0 <= p[0] <= x1 and y0 <= p[1] <= y1:
                px[p[0] - x0, y1 - p[1]] = (230, 70, 50)
        s = 3
        im = im.resize((W * s, Hh * s), Image.NEAREST)
        d = ImageDraw.Draw(im)
        d.rectangle((0, 0, im.width, 26), fill=(0, 0, 0))
        d.text((4, 2), "%s  %s" % (sm.name, v["type"]), fill=(255, 255, 255))
        d.text((4, 13), "loops %d core %.2f spokes %d spine %.2f" % (v["loops"], v["core"], v["spokes"], v["spine"]),
               fill=(200, 200, 200))
        tiles.append(im)
    cols = 6
    cw = max(t.width for t in tiles)
    ch = max(t.height for t in tiles)
    sc = min(1.0, 520.0 / cw)
    cw, ch = int(cw * sc), int(ch * sc)
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cw, rows * ch), (0, 0, 0))
    for i, t in enumerate(tiles):
        t = t.resize((int(t.width * sc), int(t.height * sc)), Image.NEAREST)
        sheet.paste(t, ((i % cols) * cw, (i // cols) * ch))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    sheet.save(out)
    return out


def report(res):
    fam = dict(CC.maps())
    res = {n: dict(v, type=classify(v)) for n, v in res.items() if v}
    lines = ["%-26s %-9s " % ("map", "type") + " ".join("%7s" % f[:7] for f in FEATURES)]
    for n in sorted(res, key=lambda k: (res[k]["type"], -res[k]["floor"])):
        v = res[n]
        lines.append("%-26s %-9s " % (n[:26], v["type"]) + " ".join("%7s" % CC.fmt(v[f], 2) for f in FEATURES))
    seen = {}
    for n, v in res.items():
        seen.setdefault(fam.get(n, n), Counter())[v["type"]] += 1
    types = Counter(c.most_common(1)[0][0] for c in seen.values())
    lines.append("")
    lines.append("types by family (%d families): %s" % (len(seen), dict(types.most_common())))
    res = {n: v for n, v in res.items() if v["type"] != "untagged"}
    bands = {}
    lines.append("bands over families, untagged maps left out (p10 / median / p90):")
    for f in FEATURES:
        lo, med, hi, nf = CC.band(res, lambda v, f=f: v.get(f))
        bands[f] = dict(lo=lo, med=med, hi=hi, n=nf)
        lines.append("  %-12s %9s %9s %9s" % (f, CC.fmt(lo, 3), CC.fmt(med, 3), CC.fmt(hi, 3)))
    by_type = {}
    lines.append("")
    lines.append("per type (median over its maps):")
    for t in [t for t, _ in types.most_common() if t != "untagged"]:
        sub = {n: v for n, v in res.items() if v["type"] == t}
        d = {f: CC.band(sub, lambda v, f=f: v.get(f))[:3] for f in FEATURES}
        d["maps"] = sorted(sub)
        by_type[t] = d
        lines.append("  %-9s n=%2d floor %s crew %s hall %s loops %s core %s spokes %s spoke_len %s reach %s spine %s "
                     "aspect %s" % (t, len(sub), CC.fmt(d["floor"][1], 0), CC.fmt(d["crew"][1], 0),
                                    CC.fmt(d["hall_share"][1], 3), CC.fmt(d["loops"][1], 1), CC.fmt(d["core"][1], 3),
                                    CC.fmt(d["spokes"][1], 1), CC.fmt(d["spoke_len"][1], 1),
                                    CC.fmt(d["spoke_reach"][1], 2), CC.fmt(d["spine"][1], 2),
                                    CC.fmt(d["aspect"][1], 2)))
    cgs = Counter()
    hubs = [v for v in res.values() if v["type"].startswith("hub")]
    for v in hubs:
        for g, sh in v["core_groups"].items():
            if sh >= 0.1:
                cgs[g] += 1
    lines.append("")
    lines.append("inside the core loop, %d hub maps (maps where the department holds 10%%+ of the loop's floor): %s" % (
        len(hubs), dict(cgs.most_common())))
    return "\n".join(lines), dict(bands=bands, types=dict(types), by_type=by_type, core_groups=dict(cgs),
                                  hubs=len(hubs), per_map=res)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--fresh", action="store_true")
    ap.add_argument("--picture", action="store_true")
    ap.add_argument("--map")
    a = ap.parse_args(argv)
    res = CC.measure_all(STUDY, measure, fresh=a.fresh, version=VERSION)
    if a.map:
        v = CC.measure_one(a.map, measure)
        ok = {n: r for n, r in res.items() if r and r["type"] != "untagged"}
        print("%s: type %s" % (a.map, v["type"]))
        for f in FEATURES:
            lo, med, hi, _ = CC.band(ok, lambda r, f=f: r.get(f))
            flag = "" if lo is None or v[f] is None or lo <= v[f] <= hi else "  OUT"
            print("  %-12s %9s   human %s .. %s .. %s%s" % (f, CC.fmt(v[f]), CC.fmt(lo), CC.fmt(med), CC.fmt(hi),
                                                          flag))
        return
    txt, data = report(res)
    print(txt)
    p = CC.save(STUDY, data)
    open(os.path.join(CC.OUT, STUDY + ".txt"), "w").write(txt + "\n")
    print("\nwrote", p)
    if a.picture:
        out = os.path.join(parse.ROOT, "data", "previews", "mapforge", "gen_targets", "skeletons.png")
        print("picture", picture([n for n, _ in CC.maps()], out))


if __name__ == "__main__":
    main(sys.argv[1:])
