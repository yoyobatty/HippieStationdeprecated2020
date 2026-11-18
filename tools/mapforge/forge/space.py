"""Space syntax judge (plan B2): how the rooms of a map hang together, read off the graph of regions.

    python tools/mapforge/forge/space.py                 # human maps + _maps/map_files/Generated
    python tools/mapforge/forge/space.py a.dmm b.dmm     # human maps + these maps

Nodes are parse.py regions (one area's 4-connected floor) of kind room, hall or maint; edges are doors and open
seams. Measures (Hillier's space syntax, steps counted in rooms passed, not tiles walked):
    mean depth      average steps from a node to every other node
    integration     1 / RRA: how central a node is, normalised for graph size (Hillier's diamond value)
    intelligibility Pearson r of a node's links against its integration: high when what you see next to you tells
                    you where you are in the whole, as on a station with a clear hall spine
    hall depth      steps from a room to the nearest hall without walking through maintenance
    cut share       floor cut off from the halls if one node goes (a burnt-out corridor, a bolted door)

Output: data/mapforge/space/report.txt and report.json.
"""
import json
import math
import os
import sys
from collections import Counter, defaultdict, deque

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import parse  # noqa: E402

ROOT = parse.ROOT
OUT = os.path.join(ROOT, "data", "mapforge", "space")
HUMAN = tuple(parse.humans())
GEN_DIR = os.path.join(ROOT, "_maps", "map_files", "Generated")

FEATURES = [
    ("nodes_per_1k", "count", "regions per 1000 station floor tiles"),
    ("mean_depth", "steps", "mean depth over all nodes (graph size normalised away by integration)"),
    ("integration", "1/RRA", "mean integration of all nodes"),
    ("hall_core", "ratio", "mean integration of halls / mean integration of rooms (>1: halls are the core)"),
    ("intelligibility", "r", "Pearson r, links vs integration"),
    ("hall_depth", "steps", "mean steps from a room to the nearest hall, maintenance not walked"),
    ("deep_rooms", "share", "rooms 3+ steps from a hall"),
    ("maint_only", "share", "rooms that reach a hall only through maintenance"),
    ("dead_ends", "share", "rooms with one link"),
    ("looped_rooms", "share", "rooms on a loop (another way round if one link goes)"),
    ("cut_max", "share", "most station floor one hall/room node cuts off from the rest, maint walked"),
    ("cut_nodes", "per 10", "nodes cutting off 5%+ of the floor, per 10 rooms"),
    ("maint_links", "share", "rooms with a door straight into maintenance"),
]


def diamond(k):
    """Hillier's D value: RA of the diamond-shaped graph of k nodes, to normalise RA across graph sizes."""
    if k < 4:
        return 1.0
    return 2.0 * (k * (math.log2((k + 2) / 3.0) - 1) + 1) / ((k - 1) * (k - 2))


def bfs(adj, src, skip=None):
    d = {src: 0}
    q = deque([src])
    while q:
        a = q.popleft()
        for b in adj[a]:
            if b not in d and b != skip:
                d[b] = d[a] + 1
                q.append(b)
    return d


def pearson(xs, ys):
    n = len(xs)
    if n < 3:
        return float("nan")
    mx, my = sum(xs) / n, sum(ys) / n
    sx = math.sqrt(sum((x - mx) ** 2 for x in xs))
    sy = math.sqrt(sum((y - my) ** 2 for y in ys))
    if not sx or not sy:
        return float("nan")
    return sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / (sx * sy)


def articulation(adj):
    """Cut vertices of an undirected graph (iterative Tarjan)."""
    disc, low, cuts = {}, {}, set()
    t = 0
    for root in adj:
        if root in disc:
            continue
        disc[root] = low[root] = t
        t += 1
        kids = 0
        stack = [(root, None, iter(adj[root]))]
        while stack:
            v, parent, it = stack[-1]
            for w in it:
                if w == parent:
                    continue
                if w in disc:
                    low[v] = min(low[v], disc[w])
                else:
                    disc[w] = low[w] = t
                    t += 1
                    if v == root:
                        kids += 1
                    stack.append((w, v, iter(adj[w])))
                    break
            else:
                stack.pop()
                if parent is not None:
                    low[parent] = min(low[parent], low[v])
                    if parent != root and low[v] >= disc[parent]:
                        cuts.add(parent)
        if kids > 1:
            cuts.add(root)
    return cuts


def graph(sm):
    keep = {i: r for i, r in sm.regions.items() if r.kind in ("room", "hall", "maint")}
    adj = {i: set(j for j in r.links if j in keep) for i, r in keep.items()}
    # the station proper: the largest connected piece (drops shuttles' stray bits, sealed vaults stay as their own)
    seen, best = set(), set()
    for i in adj:
        if i in seen:
            continue
        comp = set(bfs(adj, i))
        seen |= comp
        if sum(len(keep[j].tiles) for j in comp) > sum(len(keep[j].tiles) for j in best):
            best = comp
    adj = {i: adj[i] & best for i in best}
    return keep, adj


def measure(sm):
    regs, adj = graph(sm)
    nodes = list(adj)
    k = len(nodes)
    floor = len(sm.station_tiles())
    f, spots = {}, defaultdict(list)
    f["nodes_per_1k"] = 1000.0 * k / max(1, floor)
    md, integ = {}, {}
    dv = diamond(k)
    for n in nodes:
        d = bfs(adj, n)
        md[n] = sum(d.values()) / max(1, k - 1)
        ra = 2.0 * (md[n] - 1) / max(1, k - 2)
        integ[n] = 1.0 / max(1e-6, ra / dv)
    f["mean_depth"] = sum(md.values()) / k
    f["integration"] = sum(integ.values()) / k
    halls = [n for n in nodes if regs[n].kind == "hall"]
    rooms = [n for n in nodes if regs[n].kind == "room" and len(regs[n].tiles) >= 4]
    hi = sum(integ[n] for n in halls) / max(1, len(halls))
    ri = sum(integ[n] for n in rooms) / max(1, len(rooms))
    f["hall_core"] = hi / ri if ri else float("nan")
    f["intelligibility"] = pearson([len(adj[n]) for n in nodes], [integ[n] for n in nodes])
    # depth from the halls without maintenance: multi-source BFS over halls and rooms
    pub = {n: set(m for m in adj[n] if regs[m].kind != "maint") for n in nodes if regs[n].kind != "maint"}
    hd = {}
    q = deque()
    for h in halls:
        hd[h] = 0
        q.append(h)
    while q:
        a = q.popleft()
        for b in pub[a]:
            if b not in hd:
                hd[b] = hd[a] + 1
                q.append(b)
    reach = [hd[n] for n in rooms if n in hd]
    f["hall_depth"] = sum(reach) / max(1, len(reach))
    f["deep_rooms"] = sum(1 for v in reach if v >= 3) / max(1, len(rooms))
    mo = [n for n in rooms if n not in hd]
    f["maint_only"] = len(mo) / max(1, len(rooms))
    for n in mo:
        spots["maint_only"].append(_mid(regs[n]))
    for n in rooms:
        if hd.get(n, 0) >= 3:
            spots["deep_rooms"].append(_mid(regs[n]))
    de = [n for n in rooms if len(adj[n]) == 1]
    f["dead_ends"] = len(de) / max(1, len(rooms))
    cuts = articulation(adj)
    f["looped_rooms"] = sum(1 for n in rooms if len(adj[n]) >= 2 and not _bridged(adj, n)) / max(1, len(rooms))
    # floor cut off by losing one node: everything not in the piece that holds most of the floor
    total = sum(len(regs[n].tiles) for n in nodes)
    worst, big = 0.0, 0
    for c in cuts:
        if regs[c].kind == "maint":
            continue
        seen, pieces = {c}, []
        for s in adj[c]:
            if s in seen:
                continue
            comp = bfs(adj, s, skip=c)
            seen |= set(comp)
            pieces.append(sum(len(regs[j].tiles) for j in comp))
        if len(pieces) < 2:
            continue
        lost = (sum(pieces) - max(pieces)) / float(total)
        if lost >= 0.05:
            big += 1
            spots["cut_nodes"].append(_mid(regs[c]))
        worst = max(worst, lost)
    f["cut_max"] = worst
    f["cut_nodes"] = 10.0 * big / max(1, len(rooms))
    f["maint_links"] = sum(1 for n in rooms if any(regs[m].kind == "maint" for m in adj[n])) / max(1, len(rooms))
    per_node = {n: dict(kind=regs[n].kind, area=regs[n].area, tiles=len(regs[n].tiles), mid=_mid(regs[n]),
                        integ=integ[n], links=len(adj[n]), hall_depth=hd.get(n)) for n in nodes}
    return f, dict(spots), per_node


def _bridged(adj, n):
    """True when every link of n is a bridge (no way round): n is on no loop."""
    for m in adj[n]:
        seen = {n}
        q = deque(x for x in adj[n] if x != m)
        seen.update(q)
        while q:
            a = q.popleft()
            if a == m:
                return False
            for b in adj[a]:
                if b not in seen:
                    seen.add(b)
                    q.append(b)
    return True


def _mid(r):
    xs = sorted(p[0] for p in r.tiles)
    ys = sorted(p[1] for p in r.tiles)
    c = (xs[len(xs) // 2], ys[len(ys) // 2])
    return min(r.tiles, key=lambda p: abs(p[0] - c[0]) + abs(p[1] - c[1]))


# ---- human-range table, shared with walk.py ----
def label_for(n, sm):
    if n in HUMAN:
        return n
    if os.path.exists(n) and os.path.dirname(os.path.abspath(n)) != GEN_DIR:
        return "new:" + sm.name.replace("gen_", "").replace("_c80", "")
    return sm.name


def range_table(res, features, title):
    humans = [k for k, v in res.items() if v["human"]]
    gens = [k for k, v in res.items() if not v["human"]]
    w = max([len(g) for g in gens] + [10])
    lo_n, hi_n = ("h.p10", "h.p90") if len(humans) >= 20 else ("h.min", "h.max")
    lines = [title, "", "%-16s %-7s %7s %7s %7s  %s" % ("feature", "scale", lo_n, "h.med", hi_n,
                                                         "  ".join("%*s" % (w, g) for g in gens))]
    out = Counter()
    for name, scale, _ in features:
        hv = sorted(res[h]["f"][name] for h in humans if not math.isnan(res[h]["f"][name]))
        lo, hi = hv[0], hv[-1]
        if len(hv) >= 20:  # with the whole corpus, one odd map shouldn't set the range: 10th-90th percentile
            lo, hi = hv[int(0.1 * (len(hv) - 1))], hv[int(math.ceil(0.9 * (len(hv) - 1)))]
        med = hv[len(hv) // 2] if len(hv) % 2 else (hv[len(hv) // 2 - 1] + hv[len(hv) // 2]) / 2
        cells = []
        for g in gens:
            v = res[g]["f"][name]
            flag = " "
            if not math.isnan(v) and (v < lo - 1e-9 or v > hi + 1e-9):
                flag = "<" if v < lo else ">"
                out[g] += 1
            cells.append("%*s" % (w, "%.3g%s" % (v, flag)))
        lines.append("%-16s %-7s %7.3g %7.3g %7.3g  %s" % (name, scale, lo, med, hi, "  ".join(cells)))
    lines.append("")
    lines.append("outside the human range: " + ", ".join("%s %d/%d" % (g, out[g], len(features)) for g in gens))
    lines.append("")
    for name, scale, why in features:
        lines.append("  %-16s %s" % (name, why))
    lines.append("")
    lines.append("human values:")
    for h in humans[:12]:
        lines.append("  %-14s " % h + " ".join("%s=%.3g" % (n, res[h]["f"][n]) for n, _, _ in features))
    return "\n".join(lines)


def run_all(names, measure_fn):
    res = {}
    for n in names:
        sm = parse.load(n)
        f, spots, extra = measure_fn(sm)
        res[label_for(n, sm)] = dict(f=f, spots=spots, extra=extra, human=n in HUMAN, path=parse.map_path(n))
    return res


def names_from(argv):
    import glob
    gens = argv or sorted(glob.glob(os.path.join(GEN_DIR, "*.dmm")))
    return list(HUMAN) + gens


def main(argv):
    import time
    t0 = time.time()
    res = run_all(names_from(argv), measure)
    txt = range_table(res, FEATURES, "Space syntax (plan B2): region graph of each map against %d human maps" % len(HUMAN))
    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(OUT, "report.txt"), "w").write(txt + "\n")
    json.dump({k: dict(f=v["f"], spots=v["spots"], path=v["path"], human=v["human"]) for k, v in res.items()},
              open(os.path.join(OUT, "report.json"), "w"), indent=1)
    print(txt)
    print("\n(%.1fs) %s" % (time.time() - t0, os.path.join(OUT, "report.txt")))


if __name__ == "__main__":
    main(sys.argv[1:])
