"""Which departments sit next to which, and where each sits in the station, over every human map in
parse.humans(). The generator's department placement scores against these numbers.

    python tools/mapforge/studies/dept_adjacency.py               # tables, data/mapforge/gen_targets/
    python tools/mapforge/studies/dept_adjacency.py --map data/mapforge/station_v6.dmm   # a build against them
    python tools/mapforge/studies/dept_adjacency.py --fresh

Per map:
  contact[a|b] tiles of wall between the two departments: a floor tile of a and one of b on either side of a single
               wall, door or window tile, in a straight line (both orders counted once per wall tile).
  door[a|b]    doors (airlocks, windoors) joining a region of a to a region of b, plus open seams (floor of a
               touching floor of b).
  adjacent     contact >= 3 or a door.
  radial[g]    the department's floor centroid from the station centroid, over the station radius (the farthest
               station floor tile).
  checkpoint   /area/security/checkpoint* (department security posts) is its own group, so the brig's neighbours
               aren't mixed up with the posts inside other departments.
  fronts[g]    where the department's outer doors lead: hall, maint, another department (shares of its doors).
  maint_skin[g] share of the department's wall contact that is with maint.

Report, over families (a family counts once; its value is the share of its maps):
  P(adj)  the share of families where the pair is adjacent (both present).
  P(door) the share where a door joins them directly.
  lift    P(adj) / the mean P(adj) of all pairs: above 1 means humans put them together more than chance.
"""
import argparse
import math
import os
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import corpus_common as CC  # noqa: E402

STUDY = "dept_adjacency"
VERSION = 2
DEPTS = ("command", "security", "medical", "science", "engineering", "atmos", "cargo", "service", "civic", "dorms",
         "ai")
OPEN = ("hall", "arrivals", "escape")
ALL = DEPTS + OPEN + ("maint", "checkpoint")
CHECKPOINT = ("/area/security/checkpoint",)


def _grp(area, group):
    """Department posts (/area/security/checkpoint*) count apart from the brig: they sit inside other departments."""
    return "checkpoint" if area and area.startswith(CHECKPOINT) else group


def _key(a, b):
    return "|".join(sorted((a, b)))


def measure(sm):
    st = sm.station_tiles()
    if not st:
        return None
    cx = sum(p[0] for p in st) / float(len(st))
    cy = sum(p[1] for p in st) / float(len(st))
    radius = max(math.hypot(p[0] - cx, p[1] - cy) for p in st)
    g = {p: _grp(sm.area.get(p), sm.group.get(p)) for p in st}
    contact = Counter()
    seen = set()
    for p, ga in g.items():
        if ga not in ALL:
            continue
        for dx, dy in ((1, 0), (0, 1), (-1, 0), (0, -1)):
            w = (p[0] + dx, p[1] + dy)
            if sm.cls.get(w) not in ("W", "D"):
                continue
            q = (p[0] + 2 * dx, p[1] + 2 * dy)
            gb = g.get(q)
            if gb is None or gb == ga or gb not in ALL:
                continue
            k = (w, _key(ga, gb))
            if k in seen:
                continue
            seen.add(k)
            contact[_key(ga, gb)] += 1
    door = Counter()
    fronts = defaultdict(Counter)
    for d, rs in sm.doors.items():
        gs = {_grp(sm.regions[r].area, sm.regions[r].group) for r in rs}
        gs = {x for x in gs if x in ALL}
        if len(gs) == 2:
            a, b = sorted(gs)
            door[_key(a, b)] += 1
            for x, y in ((a, b), (b, a)):
                if x in DEPTS:
                    fronts[x]["hall" if y in OPEN else "maint" if y == "maint" else "dept"] += 1
    for r in sm.regions.values():  # open seams
        for o in r.links:
            ro = sm.regions[o]
            ga, gb = _grp(r.area, r.group), _grp(ro.area, ro.group)
            if ga != gb and ga in ALL and gb in ALL and r.id < o:
                if any((p[0] + dx, p[1] + dy) in set(ro.tiles) for p in r.tiles[:400]
                       for dx, dy in ((1, 0), (0, 1), (-1, 0), (0, -1))):
                    door[_key(ga, gb)] += 1
    radial, tiles = {}, Counter(g.values())
    for d in DEPTS + OPEN:
        ts = [p for p, x in g.items() if x == d]
        if ts:
            mx = sum(p[0] for p in ts) / float(len(ts))
            my = sum(p[1] for p in ts) / float(len(ts))
            radial[d] = round(math.hypot(mx - cx, my - cy) / radius, 3)
    skin = {}
    for d in DEPTS:
        tot = sum(v for k, v in contact.items() if d in k.split("|"))
        if tot:
            skin[d] = round(contact.get(_key(d, "maint"), 0) / float(tot), 3)
    return dict(contact=dict(contact), door=dict(door), radial=radial, tiles={k: tiles[k] for k in ALL if tiles[k]},
                fronts={k: dict(v) for k, v in fronts.items()}, maint_skin=skin)


def analyse(res):
    fam = dict(CC.maps())
    res = {k: v for k, v in res.items() if v}
    pairs = {}
    for i, a in enumerate(ALL):
        for b in ALL[i + 1:]:
            k = _key(a, b)
            both = {n: v for n, v in res.items() if v["tiles"].get(a) and v["tiles"].get(b)}
            if len(both) < 5:
                continue
            adj = CC.family_values(both, lambda v, k=k: 1.0 if v["contact"].get(k, 0) >= 3 or v["door"].get(k) else 0.0)
            dr = CC.family_values(both, lambda v, k=k: 1.0 if v["door"].get(k) else 0.0)
            ct = CC.family_values(both, lambda v, k=k: v["contact"].get(k, 0))
            pairs[k] = dict(p_adj=sum(adj.values()) / len(adj), p_door=sum(dr.values()) / len(dr),
                            contact_med=CC.median(list(ct.values())), families=len(adj))
    dept_pairs = [v["p_adj"] for k, v in pairs.items() if all(x in DEPTS for x in k.split("|"))]
    base = sum(dept_pairs) / len(dept_pairs) if dept_pairs else 1.0
    for k, v in pairs.items():
        v["lift"] = v["p_adj"] / base if base else None
    radial = {d: CC.band(res, lambda v, d=d: v["radial"].get(d)) for d in DEPTS + OPEN}
    fronts = {}
    for d in DEPTS:
        fr = {}
        for kind in ("hall", "maint", "dept"):
            fr[kind] = CC.band(res, lambda v, d=d, kind=kind: (v["fronts"].get(d, {}).get(kind, 0) /
                                                              float(sum(v["fronts"].get(d, {}).values())))
                               if v["fronts"].get(d) else None)
        fronts[d] = fr
    skin = {d: CC.band(res, lambda v, d=d: v["maint_skin"].get(d)) for d in DEPTS}
    nfam = len(set(fam.get(n, n) for n in res))
    return dict(pairs=pairs, base=base, radial=radial, fronts=fronts, maint_skin=skin, families=nfam)


def text(out):
    L = ["Department pairs, dept-dept mean P(adj) = %.2f over %d families. Sorted by lift." % (out["base"],
                                                                                              out["families"])]
    L.append("%-22s %6s %6s %6s %8s" % ("pair", "P(adj)", "P(door)", "lift", "contact"))
    rows = sorted(((k, v) for k, v in out["pairs"].items() if all(x in DEPTS for x in k.split("|"))),
                  key=lambda kv: -kv[1]["p_adj"])
    for k, v in rows:
        L.append("%-22s %6.2f %6.2f %6.2f %8s" % (k, v["p_adj"], v["p_door"], v["lift"], CC.fmt(v["contact_med"], 0)))
    L.append("")
    L.append("Each department's neighbours: P(adj) with arrivals/escape/hall/maint")
    for d in DEPTS:
        cells = []
        for o in OPEN + ("maint", "checkpoint"):
            v = out["pairs"].get(_key(d, o))
            if v:
                cells.append("%s %.2f" % (o, v["p_adj"]))
        L.append("  %-12s %s" % (d, "  ".join(cells)))
    L.append("")
    L.append("Radial position (centroid / radius, p10 med p90), outer doors (median shares), maint skin (med):")
    for d in DEPTS + OPEN:
        lo, med, hi, n = out["radial"][d]
        fr = out["fronts"].get(d)
        frs = "  ".join("%s %s" % (k, CC.fmt(fr[k][1], 2)) for k in ("hall", "maint", "dept")) if fr else ""
        sk = out["maint_skin"].get(d)
        L.append("  %-12s %5s %5s %5s   %-40s %s" % (d, CC.fmt(lo, 2), CC.fmt(med, 2), CC.fmt(hi, 2), frs,
                                                   "skin %s" % CC.fmt(sk[1], 2) if sk else ""))
    return "\n".join(L)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--fresh", action="store_true")
    ap.add_argument("--map")
    a = ap.parse_args(argv)
    res = CC.measure_all(STUDY, measure, fresh=a.fresh, version=VERSION)
    out = analyse(res)
    if a.map:
        v = CC.measure_one(a.map, measure)
        print("%s: pairs humans usually join (P(adj) >= 0.5) and the build doesn't, and pairs humans rarely join "
              "(P(adj) <= 0.15) that the build does:" % a.map)
        for k, h in sorted(out["pairs"].items(), key=lambda kv: -kv[1]["p_adj"]):
            if not all(x in DEPTS for x in k.split("|")):
                continue
            here = v["contact"].get(k, 0) >= 3 or bool(v["door"].get(k))
            if h["p_adj"] >= 0.5 and not here:
                print("  MISSING  %-22s P(adj) %.2f" % (k, h["p_adj"]))
            if h["p_adj"] <= 0.15 and here:
                print("  RARE     %-22s P(adj) %.2f  contact %d" % (k, h["p_adj"], v["contact"].get(k, 0)))
        for d in DEPTS:
            r = v["radial"].get(d)
            lo, med, hi, _ = out["radial"][d]
            if r is not None and lo is not None and not lo <= r <= hi:
                print("  RADIAL   %-12s %.2f  human %.2f..%.2f" % (d, r, lo, hi))
        return
    t = text(out)
    print(t)
    p = CC.save(STUDY, out)
    open(os.path.join(CC.OUT, STUDY + ".txt"), "w").write(t + "\n")
    print("\nwrote", p)


if __name__ == "__main__":
    main(sys.argv[1:])
