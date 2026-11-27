"""L1 room synthesis: furnish a room's shape from what human rooms of its type show (plan:
studies/learned_generator_plan.md, section 3).

    from gen.learn import synth
    out = synth.furnish(floor, solid, doors, windows, kind, seed, exclude=())   # {tile: [atom text]}, report

How (Fisher et al. 2012 / Yu et al. 2011 in miniature, on 38-map data):
1. Exemplar: a human room of the same type (roomdb; the type's parent when it has no rooms), near the size and door
   count, picked by the seed; `exclude` keeps map families out (held-out tests).
2. Motifs: the exemplar's furniture groups, rigid (a cloning pod, its scanner and console are one group in every
   human cloning room, so they stay one here). Groups that stood within MERGE tiles of each other are merged first
   (a desk and its chair across a gap), so their spacing is kept as the human made it.
3. Each group is placed, largest and most machine-heavy first, in any of its 8 turns, where:
   - every cell is free floor, nothing lands in front of a door, every use tile (the floor a player stood on to use
     it) is free floor;
   - the cells that stood against a wall stand against a wall here on the same sides (soft, weighted);
   - its distance to the nearest door, as a share of the room's size, is near the exemplar's (soft);
   - the free floor stays in one piece with every door and use tile in it (hard).
   A greedy pass with seeded noise, RESTARTS times; the best total score wins. A group that fits nowhere is left out
   and reported.
4. Wall pieces: each of the exemplar's (APC, alarms, intercom, signs, screens, extinguisher) on a plain wall face of
   the new room (never a door, never glass) at the share-of-size distance to a door nearest the exemplar's; lights
   spread over the walls, the exemplar's count scaled by size.
"""
import math
import os
import random
import sys
from collections import deque

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
from forge import dmm, furnish as FU  # noqa: E402
import roomdb  # noqa: E402

N4 = ((0, 1), (0, -1), (1, 0), (-1, 0))
SIDE = {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0)}
CONNECT = 0.98       # share of the free floor that must stay one piece (human rooms keep small pockets behind
                     # counters)
MERGE = -1           # groups this many free tiles apart or closer move as one (-1: none; dense rooms merged into one
                     # block that fit nowhere, 2026-11-25: Meta's kitchen and chemistry came out empty)
RESTARTS = 24
W_WALL = 5.0         # per motif cell whose wall side isn't a wall here
W_BAND = 12.0        # per unit of a piece's depth outside its type's stock band (door to back)
W_DOOR = 4.0         # per unit of door-distance share off the exemplar's
W_HUG = 0.0          # per placed cell touching no wall (human furniture: 74% of it against a wall)
W_FAR = 0.0          # per unit of a group's centre distance to the room centre share off the exemplar's
# tuning from the environment (gen/learn/tune.py --set NAME=value ...), read at import so pool workers get it too
for _kv in filter(None, os.environ.get("SYNTH_SET", "").split(";")):
    _k, _v = _kv.split("=", 1)
    globals()[_k] = type(globals().get(_k, 0.0))(float(_v))
LIGHT = "/obj/machinery/light"
LINKED = ("/obj/machinery/button", "/obj/machinery/embedded_controller", "/obj/machinery/doorButtons",
          "/obj/machinery/door_timer", "/obj/machinery/airlock_sensor", "/obj/machinery/igniter",
          "/obj/machinery/sparker", "/obj/machinery/computer/security/telescreen/toxins")
LIGHT_TILES = 16     # floor tiles per light fixture when the exemplar shows none (human rooms: 15.6)
INFRA_MOUNT = ("/obj/machinery/power/apc", "/obj/machinery/airalarm", "/obj/machinery/firealarm",
               "/obj/machinery/light_switch")


def _rot_mask(m, k):
    return FU.rot_mask(m, k)


def _xf(k, x, y):
    """The 8 turns: 0-3 rotations, 4-7 the same mirrored in x first."""
    if k >= 4:
        x = -x
    return FU.rot_xy(x, y, k % 4)


def _xf_mask(k, m):
    if k >= 4:
        m = (m & 3) | (8 if m & 4 else 0) | (4 if m & 8 else 0)
    return FU.rot_mask(m, k % 4)


def _xf_atom(k, text):
    a = dmm.Atom.parse(text)
    if k >= 4:
        vs = []
        for n, v in a.vars:
            if n == "dir" and v.strip().isdigit():
                d = int(v)
                d = (d & 3) | (8 if d & 4 else 0) | (4 if d & 8 else 0)
                v = str(d)
            if n == "pixel_x":
                v = str(-int(v)) if v.strip().lstrip("-").isdigit() else v
            vs.append((n, v))
        a = dmm.Atom(a.path, vs)
    return FU.rot_atom(a.text(), k % 4) if k % 4 else a.text()


def _bfs(start, ok):
    seen, q = set(start), deque(start)
    while q:
        p = q.popleft()
        for dx, dy in N4:
            n = (p[0] + dx, p[1] + dy)
            if n not in seen and ok(n):
                seen.add(n)
                q.append(n)
    return seen


def pick_exemplar(kind, tiles, ndoors, seed, exclude=(), back=False):
    """A human room of the type to copy groups from, near the size; a main room (the largest of its area on its map)
    for a main room, a back room for a back room (floorplan.corner_closets), either when none of that kind is left."""
    rs = [r for r in roomdb.rooms() if r["area"] == kind and r["family"] not in exclude and r["motifs"]]
    pick = [r for r in rs if r.get("main", True) != back]
    if pick:
        rs = pick
    if not rs:
        parent = kind.rsplit("/", 1)[0]
        rs = [r for r in roomdb.rooms() if (r["area"] == parent or r["area"].startswith(parent + "/"))
              and r["family"] not in exclude and r["motifs"]]
    if not rs:
        return None
    rnd = random.Random("ex|%s|%s" % (kind, seed))
    # a bigger exemplar's groups may not fit; a smaller one's do, with room to spare
    rs.sort(key=lambda r: abs(math.log(r["tiles"] / float(max(1, tiles)))) + 0.1 * abs(len(r["doors"]) - ndoors)
            + 0.3 * rnd.random())
    return rs[0]


def _groups(ex):
    """The exemplar's motifs, merged where they stood within MERGE free tiles of each other."""
    ms = []
    for mo in ex["motifs"]:
        cells = {(mo["at"][0] + c[0], mo["at"][1] + c[1]): (c[2], c[3]) for c in mo["cells"]}
        use = {(mo["at"][0] + u[0], mo["at"][1] + u[1]) for u in mo["use"]}
        ms.append([cells, use])
    merged = MERGE >= 0
    while merged:
        merged = False
        for i in range(len(ms)):
            for j in range(i + 1, len(ms)):
                a, b = ms[i][0], ms[j][0]
                if any(abs(p[0] - q[0]) <= MERGE + 1 and abs(p[1] - q[1]) <= MERGE + 1 for p in a for q in b):
                    # the free tiles between them become part of the group (kept free, as use tiles)
                    gap = {(x, y) for p in a for q in b if abs(p[0] - q[0]) <= MERGE + 1 and abs(p[1] - q[1]) <= MERGE + 1
                           for x in range(min(p[0], q[0]), max(p[0], q[0]) + 1)
                           for y in range(min(p[1], q[1]), max(p[1], q[1]) + 1)} - set(a) - set(b)
                    merged_cells = dict(a)
                    merged_cells.update(b)
                    ms[i] = [merged_cells, ms[i][1] | ms[j][1] | gap]
                    del ms[j]
                    merged = True
                    break
            if merged:
                break
    out = []
    for cells, use in ms:
        use -= set(cells)
        out.append(dict(cells=cells, use=use))
    return out


def _prep(g):
    """A group's turns from its cells (rel {(x, y): (atoms, wall mask)}) and use tiles."""
    g["turns"] = []
    for k in range(8):
        cells = {_xf(k, *c): (v, _xf_mask(k, v[1])) for c, v in g["rel"].items()}
        use = {_xf(k, *u) for u in g["relu"]}
        g["turns"].append((k, cells, use))
    return g


def _split(g):
    """A group that fits nowhere, cut in two across its longer side (each half keeps its cells' own spacing), or
    None for a single tile."""
    if len(g["rel"]) < 2:
        return None
    xs = [c[0] for c in g["rel"]]
    ys = [c[1] for c in g["rel"]]
    axis = 0 if max(xs) - min(xs) >= max(ys) - min(ys) else 1
    vals = sorted(c[axis] for c in g["rel"])
    cut = vals[len(vals) // 2]
    if cut == vals[0]:
        cut = vals[0] + 1
    out = []
    for side in (lambda c: c[axis] < cut, lambda c: c[axis] >= cut):
        rel = {c: v for c, v in g["rel"].items() if side(c)}
        if not rel:
            continue
        x0 = min(c[0] for c in rel)
        y0 = min(c[1] for c in rel)
        h = dict(g, rel={(c[0] - x0, c[1] - y0): v for c, v in rel.items()},
                 relu={(u[0] - x0, u[1] - y0) for u in g["relu"] if any(abs(u[0] - c[0]) + abs(u[1] - c[1]) == 1 for c in rel)})
        out.append(_prep(h))
    return out if len(out) == 2 else None


# one of a kind in a room: a second pod, console or op table from the top-up would read as a copy error
UNIQUE = ("/obj/machinery/clonepod", "/obj/machinery/computer", "/obj/machinery/dna_scannernew", "/obj/structure/table/optable",
          "/obj/machinery/chem_dispenser", "/obj/machinery/chem_master", "/obj/machinery/rnd", "/obj/machinery/vending",
          "/obj/machinery/smartfridge", "/obj/machinery/atmospherics/components/unary/cryo_cell")
_POOL = {}
try:
    from forge.function import UNIQUE as FN_UNIQUE
except Exception:                            # noqa: BLE001
    FN_UNIQUE = ("/mob/living/simple_animal/pet",)


def _density(kind, exclude):
    """The median share of a type's floor that human rooms furnish."""
    rs = [r for r in roomdb.rooms() if r["area"] == kind and r["family"] not in exclude] or         [r for r in roomdb.rooms() if r["area"].startswith(kind.rsplit("/", 1)[0]) and r["family"] not in exclude]
    vals = sorted(sum(len(mo["cells"]) for mo in r["motifs"]) / float(r["tiles"]) for r in rs)
    return vals[len(vals) // 2] if vals else 0.25


def _pool(kind, exclude, ex):
    """Every motif of the type's other human rooms (not the exemplar's, not held-out families) as a group, with how
    many rooms have one like it."""
    key = (kind, tuple(sorted(exclude)))
    if key not in _POOL:
        from collections import Counter
        sig, groups = Counter(), {}
        for r in roomdb.rooms():
            if r["area"] != kind or r["family"] in exclude:
                continue
            for mo in r["motifs"]:
                rel = {(c[0], c[1]): (c[2], c[3]) for c in mo["cells"]}
                k_ = repr(sorted((c, tuple(v[0])) for c, v in rel.items()))
                sig[k_] += 1
                if k_ not in groups:
                    groups[k_] = dict(rel=rel, relu={(u[0], u[1]) for u in mo["use"]}, door=0, centre=0, machines=0,
                                      src=r["map"])
        out = []
        for k_, g in groups.items():
            g["count"] = sig[k_]
            out.append(_prep(g))
        _POOL[key] = out
    return [g for g in _POOL[key] if g.get("src") != ex["map"]]


def _kit(kind):
    try:
        sys.path.insert(0, os.path.join(HERE, ".."))
        import essentials
        return [k["family"] for k in essentials.table().get(kind, {}).get("kit", []) if not k["path"].startswith("/obj/item")]
    except Exception:                        # noqa: BLE001 - no kit table: top up by count only
        return []


def _face(text, wm, p, solid):
    """An atom of a piece placed on its own (flex): one that stood with a wall on side s and faced away from it
    turns to face away from the wall it has here."""
    a = dmm.Atom.parse(text)
    d = a.get("dir")
    if d is None or not wm:
        return text
    old = next(s for s in (1, 2, 4, 8) if wm & s)
    new = next((s for s in (1, 2, 4, 8) if solid((p[0] + SIDE[s][0], p[1] + SIDE[s][1]))), None)
    if new is None or new == old:
        return text
    turn = {1: 0, 4: 1, 2: 2, 8: 3}
    k = (turn[new] - turn[old]) % 4
    return FU.rot_atom(text, k)


def _door_dist(cells, doors):
    if not doors:
        return 0.0
    return min(abs(p[0] - d[0]) + abs(p[1] - d[1]) for p in cells for d in doors)


_FILL = {}


def fill_band(kind):
    """(least, most) share of a room's floor under dense pieces, from the stock rooms of the type (gen/learn/
    placestudy.py: 1 - free at their 95th and 5th percentile; all rooms when the type has under 5)."""
    if kind not in _FILL:
        try:
            import placestudy as PS
            S = PS.study()["rooms"]
            v = S.get(kind) or []
            if len(v) < 5:
                v = [x for vv in S.values() for x in vv]
            fr = sorted(x[0] for x in v)
            _FILL[kind] = (1 - fr[int(0.95 * (len(fr) - 1))], 1 - fr[int(0.05 * (len(fr) - 1))])
        except Exception:                      # noqa: BLE001
            _FILL[kind] = (0.0, 1.0)
    return _FILL[kind]


def _dense_cells(cells_values):
    from forge import function as FN
    return sum(1 for v in cells_values if any(FN.is_dense(dmm.Atom.parse(a)) for a in v[0]))


def _fams(cells_values):
    """Machine families (roomdb.family) of a group's cells, counted."""
    from collections import Counter
    c = Counter()
    for v in cells_values:
        for a in v[0]:
            f = roomdb.family(a)
            if f:
                c[f] += 1
    return c


def furnish(floor, solid, doors, windows, kind, seed=1, exclude=(), exemplar=None, back=False, budget=None,
            station=None):
    """floor: set of the room's floor tiles; solid(p): wall or glass; doors: door tiles beside the room; windows: glass
    tiles of its ring. budget: {machine family: how many more this room type may have on this station} (shared by
    the type's rooms, spent here); a machine is also never more often in the room than in any human room of its type
    (roomdb.caps). Returns ({tile: [atom text]}, report dict)."""
    floor = set(floor)
    doors = set(doors)
    cap = {f: v[0] for f, v in roomdb.caps().get(kind, {}).items()}
    if budget is not None:
        for f, v in roomdb.caps().get(kind, {}).items():
            budget.setdefault(f, v[1])
            cap[f] = min(cap[f], budget[f])
    if station is not None:
        # the whole station: no more gulag teleporters or clone pods than the human station with the most
        if not station:
            station.update(roomdb.station_caps())
        for f, n in station.items():
            cap[f] = min(cap.get(f, n), n)

    def fits(have, add):
        return all(have[f] + n <= cap[f] for f, n in add.items() if f in cap)
    fmin, fmax = fill_band(kind)
    ex = exemplar or pick_exemplar(kind, len(floor), len(doors), seed, exclude, back)
    rep = dict(kind=kind, exemplar=None, placed=0, left_out=0, mounts=0)
    if ex is None:
        return {}, rep
    rep["exemplar"] = "%s %s %d tiles" % (ex["map"], ex["area"], ex["tiles"])
    exfloor = {(f[0], f[1]) for f in ex["floor"]}
    exdoors = [(d[0], d[1]) for d in ex["doors"]]
    ex_scale = math.sqrt(len(exfloor))
    scale = math.sqrt(len(floor))
    excx = sum(p[0] for p in exfloor) / float(len(exfloor))
    excy = sum(p[1] for p in exfloor) / float(len(exfloor))
    cx = sum(p[0] for p in floor) / float(len(floor))
    cy = sum(p[1] for p in floor) / float(len(floor))
    groups = _groups(ex)
    for g in groups:
        g["door"] = _door_dist(g["cells"], exdoors) / ex_scale
        gx = sum(p[0] for p in g["cells"]) / float(len(g["cells"]))
        gy = sum(p[1] for p in g["cells"]) / float(len(g["cells"]))
        g["centre"] = math.hypot(gx - excx, gy - excy) / ex_scale
        g["machines"] = sum(1 for v in g["cells"].values() for a in v[0] if a.startswith("/obj/machinery"))
        # relative to the group's own corner
        x0 = min(p[0] for p in g["cells"])
        y0 = min(p[1] for p in g["cells"])
        g["rel"] = {(p[0] - x0, p[1] - y0): v for p, v in g["cells"].items()}
        g["relu"] = {(p[0] - x0, p[1] - y0) for p in g["use"]}
    groups.sort(key=lambda g: (-g["machines"], -len(g["rel"])))
    fronts = {(d[0] + dx, d[1] + dy) for d in doors for dx, dy in N4} & floor
    # the turns of each group, precomputed
    for g in groups:
        _prep(g)
    rnd = random.Random("synth|%s|%s" % (kind, seed))
    cand_origins = sorted(floor)
    # where the stock rooms of the type keep each piece between the door and the back (gen/learn/placestudy.py
    # "where", when they agree): crew 100 seed 7 put the bar's dispenser at the back, the prison's beds by the door
    bands = {}
    try:
        import placestudy as PS_
        for key, v in PS_.study().get("where", {}).items():
            a_, f_ = key.split("|", 1)
            if a_ == kind and f_ not in ("/obj/structure/table", "/obj/structure/chair"):
                lo_, hi_ = PS_._q(v, 0.1), PS_._q(v, 0.9)
                if hi_ - lo_ <= 0.4:
                    bands[f_] = (lo_, hi_)
    except Exception:                            # noqa: BLE001
        bands = {}
    span_ = max(1, (max(p[0] for p in floor) - min(p[0] for p in floor)) + (max(p[1] for p in floor) - min(p[1] for p in floor)))

    def band_cost(cells, o):
        if not bands or not doors:
            return 0.0
        import placestudy as PS_
        c_ = 0.0
        for c, (v, m_) in cells.items():
            for a in v[0]:
                b_ = bands.get(PS_.family(a))
                if b_:
                    q = (o[0] + c[0], o[1] + c[1])
                    dq = min(abs(q[0] - d[0]) + abs(q[1] - d[1]) for d in doors) / float(span_)
                    c_ += max(0.0, b_[0] - dq, dq - b_[1])
        return c_

    def place(g, st, noise, targets=True):
        """The best spot for group g that keeps the free floor in one piece with every door front and use tile in it:
        candidates ranked by score, tried in order. Returns (score, k, o, cs, us, cells) or None."""
        occ, keep_free = st
        cands = []
        for k, cells, use in g["turns"]:
            for o in cand_origins:
                cs = [(o[0] + c[0], o[1] + c[1]) for c in cells]
                if any(c not in floor or c in occ or c in keep_free for c in cs):
                    continue
                us = [(o[0] + u[0], o[1] + u[1]) for u in use]
                if any(u not in floor or u in occ for u in us):
                    continue
                sc = 0.0
                for c, (v, m) in cells.items():
                    p = (o[0] + c[0], o[1] + c[1])
                    for s_, (dx, dy) in SIDE.items():
                        if m & s_ and not solid((p[0] + dx, p[1] + dy)):
                            sc += W_WALL
                    if W_HUG and not any(solid((p[0] + dx, p[1] + dy)) for dx, dy in N4):
                        sc += W_HUG
                sc += W_BAND * band_cost(cells, o)
                if targets:
                    sc += W_DOOR * abs(_door_dist(cs, doors) / scale - g["door"])
                    gx = sum(c[0] for c in cs) / float(len(cs))
                    gy = sum(c[1] for c in cs) / float(len(cs))
                    sc += W_FAR * abs(math.hypot(gx - cx, gy - cy) / scale - g["centre"])
                sc += noise * rnd.random()
                cands.append((sc, k, o, cs, us, cells))
        cands.sort(key=lambda c: c[0])
        for cand in cands[:60]:
            sc, k, o, cs, us, cells = cand
            free = floor - occ - set(cs)
            need = set(us) | (fronts & free) | keep_free & free
            if need:
                reach = _bfs([next(iter(need))], lambda n: n in free)
                if not need <= reach or len(reach) < len(free) * CONNECT:
                    continue
            return cand
        return None

    def flex(g, st, noise):
        """Group g placed piece by piece where it fits nowhere whole: every pair of its cells that touched (N/S/E/W)
        still touches, a cell that stood against a wall stands against one, each cell keeps as many free sides as
        it had (its fronts), and the free floor stays in one piece. Returns (score, cells {tile: atoms}) or None."""
        occ, keep_free = st
        rel = g["rel"]
        nodes = list(rel)
        adj = {c: [d for d in nodes if abs(d[0] - c[0]) + abs(d[1] - c[1]) == 1] for c in nodes}
        mach = lambda c: sum(1 for a in rel[c][0] if a.startswith("/obj/machinery"))  # noqa: E731
        start = max(nodes, key=lambda c: (mach(c), len(adj[c])))
        order, seen = [start], {start}
        while len(order) < len(nodes):
            nxt = [d for c in order for d in adj[c] if d not in seen] or [d for d in nodes if d not in seen]
            d = max(nxt, key=lambda d: (sum(1 for e in adj[d] if e in seen), mach(d)))
            order.append(d)
            seen.add(d)
        for attempt_ in range(6):
            at, taken, sc = {}, set(occ), 0.0
            ok = True
            for c in order:
                v, wm = rel[c]
                need_free = sum(1 for s_, (dx, dy) in SIDE.items() if not wm & s_ and (c[0] + dx, c[1] + dy) not in rel)
                placed_nb = [at[e] for e in adj[c] if e in at]
                if placed_nb:
                    pool_ = {(q[0] + dx, q[1] + dy) for q in placed_nb[:1] for dx, dy in N4}
                    pool_ = {t for t in pool_ if all(abs(t[0] - q[0]) + abs(t[1] - q[1]) == 1 for q in placed_nb)} or pool_
                else:
                    pool_ = set(floor)
                best_t = None
                for t in pool_:
                    if t not in floor or t in taken or t in keep_free or t in fronts:
                        continue
                    walls_here = sum(1 for dx, dy in N4 if solid((t[0] + dx, t[1] + dy)))
                    frees = sum(1 for dx, dy in N4 if (t[0] + dx, t[1] + dy) in floor and (t[0] + dx, t[1] + dy) not in taken)
                    sct = (W_WALL if (wm and not walls_here) else 0.0) + (0.5 * W_WALL if (not wm and walls_here) else 0.0)
                    sct += 1.5 * max(0, min(need_free, 2) - frees)
                    # same relative direction to the first placed neighbour as in the human group: a small bonus
                    for e in adj[c]:
                        if e in at:
                            if (t[0] - at[e][0], t[1] - at[e][1]) == (c[0] - e[0], c[1] - e[1]):
                                sct -= 0.3
                    sct += noise * rnd.random() + (0.5 * rnd.random() if attempt_ else 0)
                    if best_t is None or sct < best_t[0]:
                        best_t = (sct, t)
                if best_t is None:
                    ok = False
                    break
                at[c] = best_t[1]
                taken.add(best_t[1])
                sc += best_t[0]
            if not ok:
                continue
            free = floor - taken
            need = (fronts & free) | (keep_free & free)
            if need:
                reach = _bfs([next(iter(need))], lambda n: n in free)
                if not need <= reach or len(reach) < len(free) * CONNECT:
                    continue
            return sc, {at[c]: rel[c] for c in nodes}
        return None

    from collections import Counter
    best = None
    for attempt in range(RESTARTS):
        occ, keep_free, placed, total, left = set(), set(fronts), [], 0.0, 0
        mach = Counter()
        dense_n = 0
        queue = list(groups)
        while queue:
            g = queue.pop(0)
            add = _fams(g["rel"].values())
            dn = _dense_cells(g["rel"].values())
            if not g["machines"] and dn and (dense_n + dn) > fmax * len(floor):
                continue        # past the type's most crammed stock room (a 2-row HoP office, a library at 33% free)
            if not fits(mach, add):
                # more of a machine than its type ever has here (a fifth SMES by the gravity generator): its halves,
                # or left out
                halves = _split(g)
                if halves:
                    queue[0:0] = halves
                continue
            choice = place(g, (occ, keep_free), 0.8 if attempt else 0.0)
            if choice is None and len(g["rel"]) > 1:
                fx = flex(g, (occ, keep_free), 0.4 if attempt else 0.0)
                if fx is not None:
                    sc, at_cells = fx
                    occ |= set(at_cells)
                    placed.append(("flex", at_cells, None))
                    mach.update(add)
                    dense_n += dn
                    total += sc + 1.0
                    continue
            if choice is None:
                halves = _split(g)
                if halves:
                    queue[0:0] = halves      # try its halves next, in place of the whole
                else:
                    left += 1
                continue
            sc, k, o, cs, us, cells = choice
            occ |= set(cs)
            keep_free |= set(us)
            placed.append((k, o, cells))
            mach.update(add)
            dense_n += dn
            total += sc
        total += 12.0 * left
        if best is None or total < best[0]:
            best = (total, placed, left, occ, keep_free, mach, dense_n)
    total, placed, left, occ, keep_free, mach, dense_n = best
    # top-up: the type's usual share of furnished floor, from the other human rooms of the type, the room kit's
    # missing families first (gen/essentials.py)
    want = max(_density(kind, exclude), sum(len(mo["cells"]) for mo in ex["motifs"]) / float(ex["tiles"]))
    pool = _pool(kind, exclude, ex)
    have = set()
    for k_, o_, cells in placed:
        if k_ == "flex":
            have |= {a for atoms, m in o_.values() for a in atoms}
        else:
            have |= {a for v, m in cells.values() for a in v[0]}
    kit = _kit(kind)
    pool.sort(key=lambda g: (-sum(1 for f in kit if f not in have and any(a.startswith(f) for v in g["rel"].values() for a in v[0])),
                             -g["count"], rnd.random()))
    added = 0
    rep["fill_before"] = round(len(occ) / float(len(floor)), 2)
    rep["fill_want"] = round(want, 2)
    for g in pool:
        if (len(occ) >= want * len(floor) and dense_n >= fmin * len(floor)) or added >= 32:
            break
        dn = _dense_cells(g["rel"].values())
        if dn and dense_n + dn > fmax * len(floor):
            continue
        fams = {a for v in g["rel"].values() for a in v[0]}
        if any(a.startswith(UNIQUE) and any(h.startswith(a) for h in have) for a in fams):
            continue
        add = _fams(g["rel"].values())
        if not fits(mach, add):
            continue
        # one-of-a-kind things of the whole station (forge/function.py UNIQUE: pets, the captain's and heads' gear)
        # never come from the top-up: the exemplar's own are enough
        if any(a.startswith(FN_UNIQUE) for a in fams):
            continue
        choice = place(g, (occ, keep_free), 0.3, targets=False)
        if choice is None:
            continue
        sc, k, o, cs, us, cells = choice
        occ |= set(cs)
        keep_free |= set(us)
        placed.append((k, o, cells))
        have |= fams
        mach.update(add)
        dense_n += dn
        added += 1
    if budget is not None:
        for f, n in mach.items():
            if f in budget:
                budget[f] -= n
    if station is not None:
        for f, n in mach.items():
            if f in station:
                station[f] -= n
    rep["topped_up"] = added
    out = {}
    for k, o, cells in placed:
        if k == "flex":
            for p, (atoms, m) in o.items():
                out.setdefault(p, []).extend(_face(a, m, p, solid) for a in atoms)
            continue
        for c, (v, m) in cells.items():
            p = (o[0] + c[0], o[1] + c[1])
            out.setdefault(p, []).extend(_xf_atom(k, a) for a in v[0])
    rep["placed"], rep["left_out"], rep["score"] = len(placed), left, round(total, 1)
    rep["mounts"] = _mounts(out, ex, floor, solid, doors, windows, scale, ex_scale, rnd)
    return out, rep


def _faces(floor, solid, doors, windows):
    out = []
    for p in floor:
        for s, (dx, dy) in SIDE.items():
            q = (p[0] + dx, p[1] + dy)
            if q not in floor and solid(q) and q not in doors and q not in windows:
                out.append((p, s))
    return out


def _mounts(out, ex, floor, solid, doors, windows, scale, ex_scale, rnd):
    faces = _faces(floor, solid, doors, windows)
    used = set()
    exdoors = [(d[0], d[1]) for d in ex["doors"]]
    n = 0
    lights = [mt for mt in ex["mounts"] if _lamp(mt[3])]
    # linked pieces work only with partners of their own id on their own map: a door button with no shutters, a mass
    # driver button with no driver, the toxins burn chamber's controller with no chamber (crew 100 seed 7, 2026-11-26)
    others = [mt for mt in ex["mounts"] if not _lamp(mt[3]) and not mt[3].startswith(LINKED)]
    if lights:
        nl = max(1, int(round(len(lights) * (scale / ex_scale) ** 2)))
        # within the human spread (a tube per 8-30 tiles): a stage's footlights in a 63-tile theatre gave 11
        nl = max(int(round(len(floor) / 30.0)), min(nl, int(math.ceil(len(floor) / 8.0))), 1)
    else:
        # an exemplar with no fixture of its own: the human density (a tube per LIGHT_TILES of floor)
        nl = max(1, int(round(len(floor) / LIGHT_TILES)))
        lights = [(0, 0, 2, "/obj/machinery/light" if len(floor) > 12 else "/obj/machinery/light/small")]
    chosen = []
    for _ in range(nl):
        opts = [f for f in faces if f not in used and not any(f[0] == u[0] for u in used)]
        if not opts:
            break
        f = max(opts, key=lambda f: (min([abs(f[0][0] - c[0][0]) + abs(f[0][1] - c[0][1]) for c in chosen] or [99]),
                                     rnd.random()))
        chosen.append(f)
        used.add(f)
        out.setdefault(f[0], []).append(_hang_lamp(lights[0][3], f[1]))
        n += 1
    # then the other wall pieces (lights went first: a small office's APC, alarms, intercom, newscaster and requests
    # console took every wall face and left the HoP's office dark, crew 100 seed 7, 2026-11-26)
    for x, y, side, text in others:
        want = _door_dist([(x, y)], exdoors) / ex_scale
        opts = [f for f in faces if (f[0], f[1]) not in used and not any(f[0] == u[0] for u in used)]
        if not opts:
            break
        f = min(opts, key=lambda f: (abs(_door_dist([f[0]], doors) / scale - want) + 0.05 * rnd.random()))
        used.add(f)
        out.setdefault(f[0], []).append(_hang(text, side, f[1]))
        n += 1
    return n


def _lamp(text):
    return text.startswith(LIGHT) and not text.startswith("/obj/machinery/light_switch")


def _hang_lamp(text, side):
    """A light fixture on another wall: it faces by dir (the wall it is on), never by pixel offset."""
    a = dmm.Atom.parse(text)
    vs = [(k, v) for k, v in a.vars if k not in ("pixel_x", "pixel_y", "dir")]
    if side != 2:
        vs.append(("dir", str(side)))
    return dmm.Atom(a.path, vs).text()


def _hang(text, old_side, new_side):
    """A wall piece moved from one wall side to another: its dir and pixel offset turned to match."""
    a = dmm.Atom.parse(text)
    px, py = a.num("pixel_x"), a.num("pixel_y")
    mag = max(abs(px), abs(py)) or 26
    off = {1: (0, mag), 2: (0, -mag), 4: (mag, 0), 8: (-mag, 0)}[new_side]
    vs = [(k, v) for k, v in a.vars if k not in ("pixel_x", "pixel_y", "dir")]
    if off[0]:
        vs.append(("pixel_x", str(off[0])))
    if off[1]:
        vs.append(("pixel_y", str(off[1])))
    d = a.get("dir")
    if d is not None and old_side:
        # pieces that face away from their wall (lights, alarms) turn with it
        turn = {1: 0, 4: 1, 2: 2, 8: 3}
        k = (turn[new_side] - turn[old_side]) % 4
        vs.append(("dir", str(FU.rot_dir(int(d), k))))
    return dmm.Atom(a.path, vs).text()
