"""A station's block plan from a seed and a crew count.

The shape comes from the human stations (studies/stations.py): six of eight put Command and Service in the middle
of a main hall loop, the departments in a band around it at 0.4-0.6 of the radius, the docks at the edge and the AI
satellite out in space. So:

    core      inside the ring: four quadrants between two cross halls, one department each (Command, Service,
              the civic rooms, the dorms), every quadrant fronted by halls on all four sides
    ring      the main hall loop, three wide: every department has two routes in, one each way round
    band      the outer departments, one segment each, in a seeded order that keeps workflows together (Engineering
              beside Atmospherics, Cargo beside Arrivals, Medbay near Science, the docks apart)
    segment   a department's own hall (the spine) runs outward from its lobby; cross halls split it into tiers,
              front (public counters on the ring) to back (perma, virology, the engine, the cargo bay on the hull)
    maint     a tile-wide passage between segments and behind each one, joined round the corners
    space     docks on the hull (arrivals, escape, cargo, mining), solar arrays in the corner notches, the AI satellite
              at the end of a tunnel in the notch farthest from Arrivals

Rooms inside each block of floor are cut by forge/proc/solve.py (the same solver the department blueprints use).
"""
import itertools
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge.proc import solve  # noqa: E402
from station import program as P  # noqa: E402

HALL = 3            # ring and core cross halls
WALLS = 1.18        # floor a block loses to the wall lines between its rooms, roughly
MINB = 4            # narrowest block of rooms beside a spine


class Plan:
    def __init__(self, seed, crew):
        self.seed, self.crew = seed, crew
        self.floor = {}         # tile -> room id
        self.rooms = {}         # room id -> dict(dept, label, kind, public, secure, colour, front)
        self.doors = {}         # tile -> type: public / access / secure / maint / link / open
        self.glass = set()
        self.walls = set()
        self.hull = set()
        self.rwall = set()
        self.docks = []         # (rect, label, kind)
        self.solars = []        # (rect, label) of each panel array
        self.solar = {}         # tile -> panel / cable / lattice / tracker (out in space: no floor, no walls)
        self.notes = []
        self.problems = []
        self.order = []
        self.sides = {}

    def add_rect(self, rect, rid, **meta):
        x0, y0, x1, y1 = rect
        if rid not in self.rooms:
            self.rooms[rid] = dict(meta)
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                if (x, y) in self.floor and self.floor[(x, y)] != rid:
                    self.problems.append("overlap %s/%s at %d,%d" % (self.floor[(x, y)], rid, x, y))
                self.floor[(x, y)] = rid

    def tiles(self, rid):
        return [p for p, r in self.floor.items() if r == rid]


# ===================================================================================================== segments
class Local:
    """A department laid out in its own frame: u along the ring (left to right, standing in the ring looking out),
    v outward from the ring wall."""

    def __init__(self, dept, w):
        self.dept, self.w = dept, w
        self.rects = []         # (rect, rid, meta)
        self.depth = 0
        self.spine = None
        self.cross = []
        self.broken = []


def _wants(rooms, lobby):
    out = []
    for r in rooms:
        out.append(solve.Want(r.id, r.area, min=r.min, front=tuple(k for k in r.front), near=r.near,
                              corridor=r.corridor))
    if lobby is not None:
        out.append(solve.Want(lobby.id, lobby.area, min=(3, 4), front=("ring", "dept")))
    return out


def _groups(rooms):
    """Rooms joined by links must share a block."""
    ids = {r.id: r for r in rooms}
    parent = {r.id: r.id for r in rooms}

    def find(a):
        while parent[a] != a:
            a = parent[a]
        return a
    for r in rooms:
        for k in r.links:
            if k in ids:
                parent[find(k)] = find(r.id)
    out = {}
    for r in rooms:
        out.setdefault(find(r.id), []).append(r)
    return list(out.values())


def lay_dept(d, w, seed, left_front=None):
    """left_front: the kind of hall that runs along the segment's u=0 side ("ring" for a strip beside an arm)."""
    rnd = random.Random("dept|%s|%s|%d" % (seed, d.name, w))
    L = Local(d, w)
    sw = d.spine
    tiers = max(r.tier for r in d.rooms) + 1
    by_tier = [[r for r in d.rooms if r.tier == t] for t in range(tiers)]
    lobby = d.lobby
    two = w >= sw + 2 + 2 * MINB
    if two:
        lw = (w - sw - 2) // 2
        if w > 18:
            lw += rnd.choice((-1, 0, 1))
        blocks_u = [(0, lw - 1), (lw + sw + 2, w - 1)]
        s0 = lw + 1
    else:
        left = rnd.random() < 0.5
        s0 = 0 if left else w - sw
        blocks_u = [(sw + 1, w - 1)] if left else [(0, w - sw - 2)]
    bw = sum(b[1] - b[0] + 1 for b in blocks_u)
    cw = 2
    bands, v = [], 0
    for t in range(tiers):
        rooms = by_tier[t] + ([lobby] if (t == 0 and lobby) else [])
        area = sum(r.area for r in rooms) * WALLS
        need_short = max([r.min[0] for r in rooms] + [3])
        dep = max(need_short, int(math.ceil(area / bw)), 4)
        bands.append((v, v + dep - 1))
        v += dep + (cw + 2 if t < tiers - 1 else 0)
    L.depth = v
    # a back tier with one room (the engine, the gas tanks) takes the whole width; the spine stops short of it
    wide = set()
    if tiers > 1 and len(_groups(by_tier[-1])) == 1 and d.name not in ("arrivals", "escape"):
        wide.add(tiers - 1)
    spine_end = bands[-2][1] + 2 + cw - 1 if wide else L.depth - 1
    L.spine = (s0, 0, s0 + sw - 1, spine_end)
    L.rects.append((L.spine, d.name + "_spine", dict(kind="hall", public=d.public_spine)))
    for t in range(tiers - 1):
        c0 = bands[t][1] + 2
        rect = (0, c0, w - 1, c0 + cw - 1)
        L.cross.append(rect)
        # the cross hall runs either side of the spine (the spine owns the crossing)
        for piece in ((0, c0, s0 - 1, c0 + cw - 1), (s0 + sw, c0, w - 1, c0 + cw - 1)):
            if piece[2] >= piece[0]:
                L.rects.append((piece, "%s_cross%d" % (d.name, t), dict(kind="hall", public=d.public_spine)))
    # rooms into blocks, tier by tier
    for t in range(tiers):
        rooms = by_tier[t]
        v0, v1 = bands[t]
        blocks = []
        for i, (a, b) in enumerate([(0, w - 1)] if t in wide else blocks_u):
            fr = {}
            fr["s"] = ("ring", a, b) if t == 0 else ("dept", a, b)
            fr["n"] = ("back", a, b) if t == tiers - 1 else ("dept", a, b)
            if t in wide:
                fr["e"] = fr["w"] = ("maint", v0, v1)
            else:
                spine_side = "e" if b < s0 else "w"
                fr[spine_side] = ("dept", v0, v1)
                fr["w" if spine_side == "e" else "e"] = ("maint", v0, v1)
            if a == 0 and left_front:
                fr["w"] = (left_front, v0, v1)
            blocks.append(solve.Block("%s%d%s" % (d.name[:3], t, "LR"[i]), (a, v0, b, v1), fr))
        groups = _groups(rooms)
        extra = [lobby] if (t == 0 and lobby) else []
        options = []
        for pick in itertools.product(range(len(blocks)), repeat=len(groups)):
            sets = [[] for _ in blocks]
            for g, k in zip(groups, pick):
                sets[k] += g
            if extra:
                # the lobby goes on the side with less in it
                pass
            if any(len(s) > 5 for s in sets):
                continue
            if any(not s for s in sets) and len(rooms) >= len(blocks):
                continue
            cost = 0.0
            for s, blk in zip(sets, blocks):
                a = sum(r.area for r in s)
                cost += abs(a - blk.area / WALLS) / max(1.0, blk.area)
            cost += 0.15 * rnd.random()
            options.append((cost, pick, sets))
        options.sort(key=lambda o: o[0])
        best = None
        for cost, pick, sets in options[:6]:
            sets = [list(s) for s in sets]
            if extra:
                k = min(range(len(sets)), key=lambda i: sum(r.area for r in sets[i]) / float(blocks[i].area))
                if len(sets[k]) >= 5:
                    k = 1 - k if len(sets) == 2 else k
                sets[k] = sets[k] + extra
            total, placed, broken = 0.0, {}, []
            for s, blk in zip(sets, blocks):
                if not s:
                    continue
                links = [(r.id, k) for r in s for k in r.links]
                c, tree, pl, br = solve.solve_block(blk, _wants([r for r in s if r is not lobby],
                                                                lobby if lobby in s else None),
                                                    links, seed="%s.%s" % (seed, d.name), fill=True)
                total += c
                placed.update(pl)
                broken += br
            if best is None or (len(broken), total) < (len(best[2]), best[0]):
                best = (total, placed, broken)
            if not broken:
                break
        if best is None:
            L.broken.append("%s tier %d: no way to split %d rooms into %d blocks" % (d.name, t, len(rooms),
                                                                                    len(blocks)))
            continue
        L.broken += best[2]
        for rid, rect in best[1].items():
            r = lobby if (lobby and rid == lobby.id) else next(x for x in rooms if x.id == rid)
            L.rects.append((rect, rid, dict(kind="room", public=r.public, secure=r.secure, front=r.front,
                                            label=r.label, links=r.links, maint=r.maint, dock=r.dock,
                                            lobby=r is lobby)))
    # unused block floor (a block whose rooms could not fill it) stays wall: the solver fills blocks (fill=True)
    return L


# ===================================================================================================== order
def adjacent_pairs(order):
    n = len(order)
    return [(order[i], order[(i + 1) % n]) for i in range(n)]


LIKES = {("engineering", "atmos"): 60, ("cargo", "arrivals"): 18, ("medical", "science"): 14,
         ("security", "escape"): 10, ("medical", "escape"): 4, ("science", "engineering"): 6}
DISLIKES = {("arrivals", "escape"): 30, ("security", "arrivals"): 4, ("science", "arrivals"): 6}


def order_score(order, rnd_noise):
    s = 0.0
    pairs = {tuple(sorted(p)) for p in adjacent_pairs(order)}
    for (a, b), v in LIKES.items():
        if tuple(sorted((a, b))) in pairs:
            s += v
    for (a, b), v in DISLIKES.items():
        if tuple(sorted((a, b))) in pairs:
            s -= v
    # the docks as far apart as the loop allows
    if "arrivals" in order and "escape" in order:
        i, j = order.index("arrivals"), order.index("escape")
        gap = min(abs(i - j), len(order) - abs(i - j))
        s += 5 * gap
    return s + rnd_noise


def choose_order(names, seed):
    rnd = random.Random("order|%s" % seed)
    first, rest = names[0], names[1:]
    best = None
    for perm in itertools.permutations(rest):
        order = [first] + list(perm)
        sc = order_score(order, 22 * rnd.random())
        if best is None or sc > best[0]:
            best = (sc, order)
    return best[1]


def footprint(d):
    a = sum(r.area for r in d.rooms) + (d.lobby.area if d.lobby else 0)
    tiers = max(r.tier for r in d.rooms) + 1
    return a * WALLS * 1.15 + tiers * 6


def split_sides(order, widths, seed):
    """Cut the loop into four runs (north, east, south, west) whose lengths suit a rectangle."""
    rnd = random.Random("sides|%s" % seed)
    n = len(order)
    best = None
    for rot in range(n):
        seq = order[rot:] + order[:rot]
        ws = [widths[k] for k in seq]
        for a, b, c in itertools.combinations(range(1, n), 3):
            runs = [seq[:a], seq[a:b], seq[b:c], seq[c:]]
            lens = [sum(widths[k] for k in r) + 3 * (len(r) - 1) for r in runs]
            # opposite sides alike, and near square
            cost = abs(lens[0] - lens[2]) + abs(lens[1] - lens[3])
            cost += 0.6 * abs((lens[0] + lens[2]) - (lens[1] + lens[3]))
            cost += 8 * rnd.random()
            if best is None or cost < best[0]:
                best = (cost, runs, lens)
    return best[1], best[2]


def fit_widths(run, nominal, length, d_by):
    """Integer widths for a side's departments that fill `length` with 3-tile maint gaps between them."""
    usable = length - 3 * (len(run) - 1)
    tot = float(sum(nominal[k] for k in run))
    ws = [max(9, int(nominal[k] * usable / tot)) for k in run]
    i = 0
    while sum(ws) < usable:
        ws[i % len(ws)] += 1
        i += 1
    while sum(ws) > usable:
        j = max(range(len(ws)), key=lambda k: ws[k])
        ws[j] -= 1
    return ws


# ===================================================================================================== station
def generate(seed=1, crew=80):
    rnd = random.Random("station|%s|%s" % (seed, crew))
    plan = Plan(seed, crew)
    depts = P.program(crew, seed)
    by = {d.name: d for d in depts}
    outer = [d.name for d in depts if d.where == "outer" and d.name not in ("dorms", "civic")]
    core = [d.name for d in depts if d.where == "core"] + [n for n in ("civic", "dorms") if n in by]
    order = choose_order(outer, seed)
    plan.order = order

    aspect = {n: rnd.uniform(1.15, 1.75) for n in outer}
    nominal = {n: max(10, int(round(math.sqrt(footprint(by[n]) / aspect[n])))) for n in outer}
    for n in ("arrivals", "escape"):
        if n in nominal:
            nominal[n] = max(11, nominal[n])
    runs, lens = split_sides(order, nominal, seed)

    # the core: four quadrants plus two cross halls must hold the core departments
    core_need = sum(footprint(by[n]) for n in core) + 2 * HALL * 40
    Wr = max(lens[0], lens[2])
    Hr = max(lens[1], lens[3])
    for _ in range(60):
        cw, ch = Wr - 2 * HALL - 2, Hr - 2 * HALL - 2
        if cw * ch >= core_need * 1.02:
            break
        if cw / float(ch) < 1.15:
            Wr += 1
        else:
            Hr += 1
    RX0, RY0 = 0, 0
    RX1, RY1 = RX0 + Wr - 1, RY0 + Hr - 1
    plan.notes.append("order: " + " > ".join(order))
    plan.notes.append("ring %dx%d, core %dx%d (needs %d tiles, has %d)" % (Wr, Hr, Wr - 2 * HALL - 2,
                                                                         Hr - 2 * HALL - 2, core_need,
                                                                         (Wr - 2 * HALL - 2) * (Hr - 2 * HALL - 2)))

    # ---- ring hall
    for rect in ((RX0, RY1 - HALL + 1, RX1, RY1), (RX0, RY0, RX1, RY0 + HALL - 1),
                 (RX0, RY0, RX0 + HALL - 1, RY1), (RX1 - HALL + 1, RY0, RX1, RY1)):
        plan.add_rect(rect, "ring", kind="hall", public=True, label="", dept="hall")

    # ---- core
    lay_core(plan, by, core, (RX0 + HALL + 1, RY0 + HALL + 1, RX1 - HALL - 1, RY1 - HALL - 1), seed)

    # ---- band
    sides = ["n", "e", "s", "w"]
    segs = []
    for side, run, length in zip(sides, runs, (Wr, Hr, Wr, Hr)):
        ws = fit_widths(run, nominal, length, by)
        u = 0
        for name, w in zip(run, ws):
            loc = lay_dept(by[name], w, seed)
            plan.problems += ["%s: %s" % (name, b) for b in loc.broken]
            segs.append((side, name, u, w, loc))
            u += w + 3
    plan.sides = {s: [x[1] for x in segs if x[0] == s] for s in sides}

    def tf(side, u, v):
        if side == "n":
            return (RX0 + u, RY1 + 2 + v)
        if side == "e":
            return (RX1 + 2 + v, RY1 - u)
        if side == "s":
            return (RX1 - u, RY0 - 2 - v)
        return (RX0 - 2 - v, RY0 + u)

    def tf_rect(side, rect, u0):
        a = tf(side, u0 + rect[0], rect[1])
        b = tf(side, u0 + rect[2], rect[3])
        return (min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1]))

    for side, name, u0, w, loc in segs:
        d = by[name]
        for rect, rid, meta in loc.rects:
            meta = dict(meta)
            meta.setdefault("label", "")
            plan.add_rect(tf_rect(side, rect, u0), rid, dept=name, colour=d.colour, side=side, **meta)

    # ---- maint: between segments, behind them, round the corners
    maint_rects = []
    for side in sides:
        row = [x for x in segs if x[0] == side]
        for i, (s, name, u0, w, loc) in enumerate(row):
            # behind the segment, except where a room needs the hull (dock, engine, tanks) or the spine docks
            behind = []
            dock_u = set()
            for rect, rid, meta in loc.rects:
                if rect[3] == loc.depth - 1 and ("back" in meta.get("front", ()) or meta.get("dock")):
                    dock_u |= set(range(rect[0] - 1, rect[2] + 2))
            if name in ("arrivals", "escape"):
                dock_u |= set(range(loc.spine[0] - 1, loc.spine[2] + 2))
            for u in range(-1, w + 1):
                if u not in dock_u:
                    behind.append(u)
            for u in behind:
                maint_rects.append((side, u0 + u, loc.depth + 1, u0 + u, loc.depth + 1))
            if i + 1 < len(row):
                nxt = row[i + 1]
                top = max(loc.depth, nxt[4].depth) + 1
                maint_rects.append((side, u0 + w + 1, 0, u0 + w + 1, top))
        # corner after this side: a column up the last segment's side and a row along the next side's first one
    for side, a, b, c, dd in maint_rects:
        r = tf_rect(side, (a, b, c, dd), 0)
        for x in range(r[0], r[2] + 1):
            for y in range(r[1], r[3] + 1):
                if (x, y) not in plan.floor:
                    plan.floor[(x, y)] = "maint"
    plan.rooms["maint"] = dict(kind="maint", dept="maint", label="", public=False)
    corners(plan, segs, (RX0, RY0, RX1, RY1))

    # ---- AI satellite and solars in the corner notches
    space_features(plan, segs, (RX0, RY0, RX1, RY1), seed)

    # ---- walls, doors, glass, docks
    finish(plan, segs, by, tf, (RX0, RY0, RX1, RY1))
    return plan


def corners(plan, segs, ring):
    RX0, RY0, RX1, RY1 = ring
    depth = {}
    for side, name, u0, w, loc in segs:
        depth.setdefault(side, []).append((u0, w, loc.depth))
    # corner junction and the two maint legs to the neighbouring sides' back maint
    def first(side):
        return depth[side][0][2] if depth.get(side) else 0

    def last(side):
        return depth[side][-1][2] if depth.get(side) else 0
    legs = []
    # NE: north side's last segment (east end), east side's first segment (north end)
    legs.append(((RX1 + 2, RY1 + 2), (0, 1), last("n") + 1, (1, 0), first("e") + 1))
    # SE: east side's last (south end), south side's first (east end)
    legs.append(((RX1 + 2, RY0 - 2), (1, 0), last("e") + 1, (0, -1), first("s") + 1))
    # SW: south side's last (west end), west side's first (south end)
    legs.append(((RX0 - 2, RY0 - 2), (0, -1), last("s") + 1, (-1, 0), first("w") + 1))
    # NW: west side's last (north end), north side's first (west end)
    legs.append(((RX0 - 2, RY1 + 2), (-1, 0), last("w") + 1, (0, 1), first("n") + 1))
    plan.corner_legs = legs
    for (cx, cy), d1, n1, d2, n2 in legs:
        for k in range(0, n1 + 1):
            plan.floor.setdefault((cx + d1[0] * k, cy + d1[1] * k), "maint")
        for k in range(0, n2 + 1):
            plan.floor.setdefault((cx + d2[0] * k, cy + d2[1] * k), "maint")


def space_features(plan, segs, ring, seed):
    rnd = random.Random("space|%s" % seed)
    RX0, RY0, RX1, RY1 = ring
    legs = plan.corner_legs
    arr = [s for s in segs if s[1] == "arrivals"]
    names = ["NE", "SE", "SW", "NW"]
    diag = {"NE": (1, 1), "SE": (1, -1), "SW": (-1, -1), "NW": (-1, 1)}
    # the satellite goes off the corner farthest from arrivals
    if arr:
        side = arr[0][0]
        far = {"n": ["SE", "SW"], "s": ["NE", "NW"], "e": ["SW", "NW"], "w": ["NE", "SE"]}[side]
    else:
        far = names
    sat = rnd.choice(far)
    plan.sat_corner = sat
    for i, ((cx, cy), d1, n1, d2, n2) in enumerate(legs):
        name = names[i]
        dx, dy = diag[name]
        reach = max(n1, n2)
        if name == sat:
            # a secure tunnel out on the diagonal, then the satellite
            k = 5
            p = (cx, cy)
            path = []
            for j in range(1, k + 1):
                p = (p[0] + dx, p[1])
                path.append(p)
                p = (p[0], p[1] + dy)
                path.append(p)
            for t in path:
                if t not in plan.floor:
                    plan.floor[t] = "sat_tunnel"
            plan.rooms["sat_tunnel"] = dict(kind="hall", dept="ai", label="", public=False, secure=True,
                                            colour=P.C["ai"])
            sx, sy = p
            for j in (1, 2):
                plan.floor.setdefault((sx + dx * j, sy), "sat_tunnel")
            # the satellite: a hall round the AI core, its near corner at the tunnel's end, tcomms beyond it
            cx0 = sx + dx * 3
            xs = sorted((cx0, cx0 + dx * 10))
            ys = sorted((sy, sy + dy * 10))
            ring_r = (xs[0], ys[0], xs[1], ys[1])
            for x in range(ring_r[0], ring_r[2] + 1):
                for y in range(ring_r[1], ring_r[3] + 1):
                    if x in (ring_r[0], ring_r[2]) or y in (ring_r[1], ring_r[3]):
                        plan.floor[(x, y)] = "sat_hall"
            plan.rooms["sat_hall"] = dict(kind="hall", dept="ai", label="", public=False, secure=True,
                                          colour=P.C["ai"])
            core = (ring_r[0] + 2, ring_r[1] + 2, ring_r[2] - 2, ring_r[3] - 2)
            plan.add_rect(core, "ai_core", kind="room", dept="ai", label="AI", secure=True, colour=P.C["ai"])
            tc_x0 = ring_r[2] + 2 if dx > 0 else ring_r[0] - 8
            plan.add_rect((tc_x0, ring_r[1], tc_x0 + 6, ring_r[1] + 5), "tcomms", kind="room", dept="ai",
                          label="tcomms", secure=True, colour=P.C["ai"])
            plan.add_rect((tc_x0, ring_r[1] + 7, tc_x0 + 6, ring_r[3]), "tc_control", kind="room", dept="ai",
                          label="tc ctrl", colour=P.C["ai"])
            plan.sat = dict(ring=ring_r, core=core, tunnel_end=(sx, sy))
        else:
            # a solar array: rows of panels on a catwalk, out on the diagonal
            k = 4
            p = (cx, cy)
            for j in range(k):
                p = (p[0] + dx, p[1] + dy)
                plan.floor.setdefault(p, "catwalk")
                plan.floor.setdefault((p[0] - dx, p[1]), "catwalk")
            plan.rooms["catwalk"] = dict(kind="maint", dept="solar", label="", public=False)
            ax, ay = p[0] + dx, p[1] + dy
            rect = (min(ax, ax + dx * 12), min(ay, ay + dy * 12), max(ax, ax + dx * 12), max(ay, ay + dy * 12))
            plan.solars.append((rect, name))


# ===================================================================================================== core
def lay_core(plan, by, core, rect, seed):
    rnd = random.Random("core|%s" % seed)
    X0, Y0, X1, Y1 = rect
    W, H = X1 - X0 + 1, Y1 - Y0 + 1
    names = [n for n in core if n in by]
    while len(names) < 4:
        names.append(None)
    # which department takes which quadrant (NW, NE, SW, SE): seeded, command not in the same spot every time
    quads = ["NW", "NE", "SW", "SE"]
    rnd.shuffle(names)
    area = {n: footprint(by[n]) if n else 40 for n in names}
    a = dict(zip(quads, names))
    west = area[a["NW"]] + area[a["SW"]]
    north_w = area[a["NW"]] + area[a["NE"]]
    tot = float(sum(area.values()))
    vx = X0 + int(round((W - HALL) * west / tot))
    hy = Y1 - int(round((H - HALL) * north_w / tot)) - HALL + 1
    vx = max(X0 + 8, min(X1 - HALL - 8, vx))
    hy = max(Y0 + 8, min(Y1 - HALL - 8, hy))
    # the cross halls run wall to wall and open onto the ring at both ends
    plan.add_rect((vx, Y0 - 1, vx + HALL - 1, Y1 + 1), "core_v", kind="hall", public=True, label="", dept="hall")
    for piece in ((X0 - 1, hy, vx - 1, hy + HALL - 1), (vx + HALL, hy, X1 + 1, hy + HALL - 1)):
        plan.add_rect(piece, "core_h", kind="hall", public=True, label="", dept="hall")
    qrect = {"NW": (X0, hy + HALL + 1, vx - 2, Y1), "NE": (vx + HALL + 1, hy + HALL + 1, X1, Y1),
             "SW": (X0, Y0, vx - 2, hy - 2), "SE": (vx + HALL + 1, Y0, X1, hy - 2)}
    plan.core_quads = {}
    for q, name in a.items():
        if name is None:
            continue
        d = by[name]
        qx0, qy0, qx1, qy1 = qrect[q]
        plan.core_quads[q] = name
        rooms = d.rooms
        # split the quadrant in two blocks if it holds more than five rooms
        blocks = []
        if len(rooms) <= 5:
            blocks.append((qrect[q], rooms))
        else:
            groups = _groups(rooms)
            best = None
            for pick in itertools.product((0, 1), repeat=len(groups)):
                s = [[], []]
                for g, k in zip(groups, pick):
                    s[k] += g
                if not s[0] or not s[1] or len(s[0]) > 5 or len(s[1]) > 5:
                    continue
                c = abs(sum(r.area for r in s[0]) - sum(r.area for r in s[1])) + 30 * rnd.random()
                if best is None or c < best[0]:
                    best = (c, s)
            s = best[1]
            share = sum(r.area for r in s[0]) / float(sum(r.area for r in rooms))
            if qx1 - qx0 >= qy1 - qy0:
                cut = qx0 + int(round((qx1 - qx0 - 1) * share))
                blocks = [((qx0, qy0, cut, qy1), s[0]), ((cut + 2, qy0, qx1, qy1), s[1])]
            else:
                cut = qy1 - int(round((qy1 - qy0 - 1) * share))
                blocks = [((qx0, cut, qx1, qy1), s[0]), ((qx0, qy0, qx1, cut - 2), s[1])]
        for i, (br, rs) in enumerate(blocks):
            fr = {}
            bx0, by0, bx1, by1 = br
            for side, lo, hi in (("n", bx0, bx1), ("s", bx0, bx1), ("e", by0, by1), ("w", by0, by1)):
                edge = {"n": by1 == qy1, "s": by0 == qy0, "e": bx1 == qx1, "w": bx0 == qx0}[side]
                if edge:
                    fr[side] = ("hall", lo, hi)
            blk = solve.Block("%s%d" % (q, i), br, fr)
            # in the core every hall is "hall": the ring and the cross halls
            fronts = {r.id: tuple(sorted({"hall" if k in ("ring", "dept") else k for k in r.front})) for r in rs}
            wants = [solve.Want(r.id, r.area, min=r.min, front=fronts[r.id], near=r.near) for r in rs]
            links = [(r.id, k) for r in rs for k in r.links]
            c, tree, placed, broken = solve.solve_block(blk, wants, links, seed="%s.%s" % (seed, q), fill=True)
            plan.problems += ["%s: %s" % (name, b) for b in broken]
            for rid, rr in placed.items():
                r = next(x for x in rs if x.id == rid)
                plan.add_rect(rr, rid, kind="room", dept=name, colour=d.colour, label=r.label, public=r.public,
                              secure=r.secure, front=fronts[rid], links=r.links, maint=r.maint)


# ===================================================================================================== finish
DIRS = ((1, 0), (-1, 0), (0, 1), (0, -1))


def shared_wall(plan, a, b):
    """Wall tiles with room a on one side and room b straight across."""
    out = []
    for p in plan.tiles(a):
        for dx, dy in DIRS:
            q = (p[0] + dx, p[1] + dy)
            r = (p[0] + 2 * dx, p[1] + 2 * dy)
            if q not in plan.floor and plan.floor.get(r) == b:
                out.append(q)
    return sorted(set(out))


def _mid(ws):
    """The middle of the longest straight run of wall tiles."""
    if not ws:
        return None
    runs, cur = [], [ws[0]]
    for p in ws[1:]:
        q = cur[-1]
        if (p[0] == q[0] and p[1] == q[1] + 1) or (p[1] == q[1] and p[0] == q[0] + 1):
            cur.append(p)
        else:
            runs.append(cur)
            cur = [p]
    runs.append(cur)
    best = max(runs, key=len)
    return best[len(best) // 2]


def link_maint(plan):
    """Maint pieces joined by maint doors make a network; a network whose only ways in are through departments (a
    greytider could not get in from a hall) gets a maint door onto a main hall it runs beside, else onto a network
    that has one. Repeated until every network is reached from a hall."""
    MT = ("maint", "catwalk")

    def main_hall(r):
        m = plan.rooms.get(r, {})
        return m.get("kind") == "hall" and m.get("dept") == "hall"
    for _ in range(40):
        seen = {}
        nets = []
        for s0 in [p for p, r in plan.floor.items() if r in MT]:
            if s0 in seen:
                continue
            k = len(nets)
            net, stack = {s0}, [s0]
            seen[s0] = k
            while stack:
                a = stack.pop()
                for dx, dy in DIRS:
                    n = (a[0] + dx, a[1] + dy)
                    if n in seen:
                        continue
                    if plan.floor.get(n) in MT or (a in plan.floor and plan.doors.get(n) == "maint"):
                        seen[n] = k
                        net.add(n)
                        stack.append(n)
            nets.append(net)
        open_ = set()
        for k, net in enumerate(nets):
            if any(plan.doors.get(p) == "maint" and any(main_hall(plan.floor.get((p[0] + dx, p[1] + dy)))
                                                        for dx, dy in DIRS) for p in net):
                open_.add(k)
        shut = [k for k in range(len(nets)) if k not in open_ and len(nets[k]) >= 6]
        if not shut:
            return
        added = False
        for k in shut:
            best = []
            for a in nets[k]:
                if a not in plan.floor:
                    continue
                for dx, dy in DIRS:
                    q = (a[0] + dx, a[1] + dy)
                    s = (a[0] + 2 * dx, a[1] + 2 * dy)
                    if q in plan.floor or q in plan.doors or q in plan.walls and plan.floor.get(s) is None:
                        continue
                    if any(plan.doors.get((q[0] + ex, q[1] + ey)) for ex in (-1, 0, 1) for ey in (-1, 0, 1)):
                        continue
                    r = plan.floor.get(s)
                    if main_hall(r):
                        best.append((0, q))
                    elif r in MT and seen.get(s) in open_:
                        best.append((1, q))
            if best:
                best.sort()
                top = [b for b in best if b[0] == best[0][0]]
                plan.doors[top[len(top) // 2][1]] = "maint"
                plan.walls.discard(top[len(top) // 2][1])
                added = True
        if not added:
            return


# rooms that never get a door onto maint: a brig cell's back door lets the prisoner walk out
NO_BACK_DOOR = ("cells",)
WANTS_BACK_DOOR = ("restroom",)


def open_dead_ends(plan, back=4):
    """A maint corridor that stops short against a wall is a trap on stock maps only by accident: each dead end
    gets a maint door out, within a few tiles of its end, onto a hall beside it (else a room that isn't secure)."""
    fl = plan.floor

    def mt(p):
        return fl.get(p) in ("maint", "catwalk")

    def ways(p):
        return [(p[0] + dx, p[1] + dy) for dx, dy in DIRS
                if (p[0] + dx, p[1] + dy) in fl or (p[0] + dx, p[1] + dy) in plan.doors]

    added = 0
    for p in sorted(p for p in fl if fl[p] == "maint"):
        w = ways(p)
        if len(w) != 1 or not mt(w[0]):
            continue
        # walk back up the corridor a few tiles; the first wall with a hall (else a room) straight across gets a door
        path, prev, cur = [p], None, p
        for _ in range(back):
            nxt = [n for n in ways(cur) if n != prev and mt(n)]
            if len(nxt) != 1:
                break
            prev, cur = cur, nxt[0]
            path.append(cur)
        if any((a[0] + dx, a[1] + dy) in plan.doors for a in path[:2] for dx, dy in DIRS):
            continue
        best = None
        for i, a in enumerate(path):
            for dx, dy in DIRS:
                q, r = (a[0] + dx, a[1] + dy), fl.get((a[0] + 2 * dx, a[1] + 2 * dy))
                if q in fl or q in plan.doors or q in plan.glass or not r or r in ("maint", "catwalk"):
                    continue
                m = plan.rooms.get(r, {})
                if m.get("secure") or m.get("dept") in ("maint", "solar", "ai") or r.startswith(NO_BACK_DOOR):
                    continue
                score = (0 if m.get("kind") == "hall" else 1, i)
                if best is None or score < best[0]:
                    best = (score, q)
        if best:
            plan.doors[best[1]] = "maint"
            plan.walls.discard(best[1])
            added += 1
    if added:
        plan.notes.append("%d maint dead ends opened" % added)


def close_gaps(plan):
    """Two rooms a two-tile gap apart get two walls back to back (floor, wall, wall, floor): stock maps share one
    wall. Where the gap's near row runs the whole length of a room's side, that row joins the room (it stays a
    rectangle); rooms before maint, maint before halls."""
    fl = plan.floor
    taken = set(plan.doors) | plan.glass | set(plan.solar)

    def pref(rid):
        k = plan.rooms.get(rid, {}).get("kind")
        return 0 if k == "room" else 1 if k == "maint" else 2

    grew = 0
    for axis in (0, 1):
        def P(u, v):
            return (u, v) if axis == 0 else (v, u)
        rows = {}
        for p in list(fl):
            u, v = (p[0], p[1]) if axis == 0 else (p[1], p[0])
            g1, g2, far = P(u + 1, v), P(u + 2, v), P(u + 3, v)
            if g1 in fl or g2 in fl or g1 in taken or g2 in taken or far not in fl:
                continue
            rows.setdefault((u, fl[p], fl[far]), []).append(v)
        for (u, a, b), vs in rows.items():
            vs.sort()
            runs, cur = [], [vs[0]]
            for v in vs[1:]:
                if v == cur[-1] + 1:
                    cur.append(v)
                else:
                    runs.append(cur)
                    cur = [v]
            runs.append(cur)
            for run in runs:
                v0, v1 = run[0], run[-1]
                opts = []
                for side_u, rid, gu in ((u, a, u + 1), (u + 3, b, u + 2)):
                    if rid in ("catwalk",) or plan.rooms.get(rid, {}).get("dept") in ("solar", "ai"):
                        continue
                    # the room's side here is exactly the run (else the new row would make a jog)
                    if fl.get(P(side_u, v0 - 1)) == rid or fl.get(P(side_u, v1 + 1)) == rid:
                        continue
                    # nothing at the strip's ends would meet it floor to floor
                    ends = [P(gu, v0 - 1), P(gu, v1 + 1)]
                    if any(e in fl or e in taken for e in ends):
                        continue
                    if any(P(gu, v) in fl or P(gu, v) in taken for v in run):
                        continue
                    opts.append((pref(rid), -len(run), gu, rid))
                if not opts:
                    continue
                _, _, gu, rid = min(opts)
                for v in run:
                    fl[P(gu, v)] = rid
                    grew += 1
    if grew:
        plan.notes.append("closed %d tiles of double wall" % grew)


def open_pinches(plan):
    """Two hall (or maint) tiles that meet only at a corner, walls on the other two: a squeeze no one can walk
    through. Fill one of the corner tiles in as floor of the same way."""
    def way(p):
        r = plan.floor.get(p)
        if r is None:
            return None
        return "maint" if r == "maint" else "hall" if plan.rooms.get(r, {}).get("kind") == "hall" else None
    opened = 0
    for p in sorted(plan.floor):
        for dx in (1, -1):
            q = (p[0] + dx, p[1] + 1)
            if way(p) is None or way(p) != way(q):
                continue
            c1, c2 = (q[0], p[1]), (p[0], q[1])
            if c1 in plan.floor or c2 in plan.floor:
                continue
            # the walls either side of the opened tile still have to join: the room behind gives up its corner
            # tile (d, diagonal from c away from the halls), unless that is wall already
            best = None
            for c, own in ((c1, p), (c2, q)):
                others = [(c[0] + ex, c[1] + ey) for ex, ey in DIRS]
                others = [o for o in others if o not in (p, q)]
                if any(o in plan.floor for o in others) or c in plan.doors:
                    continue
                d = (others[0][0] + others[1][0] - c[0], others[0][1] + others[1][1] - c[1])
                r = plan.floor.get(d)
                if r is None:
                    cost = 0
                else:
                    tiles = [t for t, x in plan.floor.items() if x == r]
                    near_door = any((d[0] + ex, d[1] + ey) in plan.doors for ex, ey in DIRS)
                    if way(d) or len(tiles) < 16 or near_door or plan.rooms.get(r, {}).get("kind") in ("solar", "ai"):
                        continue
                    cost = 1
                if best is None or cost < best[0]:
                    best = (cost, c, own, d)
            if best:
                _, c, own, d = best
                plan.floor[c] = plan.floor[own]
                plan.floor.pop(d, None)
                opened += 1
    if opened:
        plan.notes.append("opened %d corner-only squeezes" % opened)


def finish(plan, segs, by, tf, ring):
    close_gaps(plan)
    open_pinches(plan)
    halls_of = {}
    for rid, m in plan.rooms.items():
        if m.get("kind") == "hall" and m.get("dept") not in ("hall", "ai"):
            halls_of.setdefault(m["dept"], []).append(rid)
    neighbours = {}
    # room -> its doors
    for rid, m in list(plan.rooms.items()):
        if m.get("kind") != "room" or m.get("dept") == "ai":
            continue
        dept = m.get("dept")
        front = m.get("front", ())
        targets = []
        if "ring" in front:
            targets.append(("ring", "public" if m.get("public") else "access"))
        if "dept" in front:
            hs = sorted(halls_of.get(dept, []), key=lambda h: -len(shared_wall(plan, rid, h)))
            if hs:
                targets.append((hs[0], "public" if (m.get("public") and plan.rooms[hs[0]].get("public"))
                                else "access"))
        if "hall" in front:
            hs = sorted(["ring", "core_v", "core_h"], key=lambda h: -len(shared_wall(plan, rid, h)))
            targets.append((hs[0], "public" if m.get("public") else "access"))
        # the front desk is the way in: a staff door from it onto the department's own hall
        if m.get("lobby") and "dept" not in front:
            hs = [h for h in halls_of.get(dept, []) if shared_wall(plan, rid, h)]
            if hs:
                targets.append((max(hs, key=lambda h: len(shared_wall(plan, rid, h))), "access"))
        for tgt, kind in targets:
            if m.get("secure"):
                kind = "secure"
            ws = shared_wall(plan, rid, tgt)
            t = _mid(ws)
            if t is None:
                plan.problems.append("%s has no wall on %s" % (rid, tgt))
                continue
            plan.doors[t] = kind
            # counters: a public front room shows glass along the ring
            if tgt == "ring" and (m.get("public") or m.get("lobby")) and len(ws) >= 5:
                for g in ws[1:-1]:
                    if abs(g[0] - t[0]) + abs(g[1] - t[1]) >= 2:
                        plan.glass.add(g)
        for k in m.get("links", ()):
            t = _mid(shared_wall(plan, rid, k))
            if t is None:
                plan.problems.append("%s and %s share no wall" % (rid, k))
            else:
                plan.doors[t] = "secure" if (m.get("secure") or plan.rooms.get(k, {}).get("secure")) else "link"
        # restrooms always have a back way into maint on the stock maps
        back = m.get("maint") or rid.startswith(WANTS_BACK_DOOR) or m.get("label") in WANTS_BACK_DOOR
        if (back or m.get("lobby") is False and not m.get("public")) and not rid.startswith(NO_BACK_DOOR):
            t = _mid(shared_wall(plan, rid, "maint"))
            if t is not None and (back or random.Random(rid).random() < 0.35) and not m.get("secure"):
                plan.doors[t] = "maint"
    # spines: public ones open onto the ring, staff ones only through the lobby
    for side, name, u0, w, loc in segs:
        d = by[name]
        sp = name + "_spine"
        ws = shared_wall(plan, sp, "ring")
        # only the mouth (a spine can run beside a side street for its whole length)
        if ws and hasattr(loc, "spine") and loc.spine:
            sx0, sy0, sx1, sy1 = loc.spine
            mouth = [tf(side, u0 + x, -1) for x in range(sx0, sx1 + 1)]
            ws = [t for t in ws if t in mouth] or ws[:sx1 - sx0 + 1]
        if d.public_spine or not d.lobby:
            for t in ws:
                plan.doors[t] = "open" if d.public_spine else "access"
        # cross halls that end on a main hall open onto it
        for t_ in range(len(loc.cross)):
            ws = shared_wall(plan, "%s_cross%d" % (name, t_), "ring")
            if ws:
                plan.doors[_mid(ws)] = "open" if d.public_spine else "access"
        # cross halls and spine ends to maint
        for h in [sp] + ["%s_cross%d" % (name, t) for t in range(len(loc.cross))]:
            ws = shared_wall(plan, h, "maint")
            if ws:
                # one door per end
                ends = {}
                for t in ws:
                    key = (t[0] < sum(q[0] for q in ws) / float(len(ws)), t[1] < sum(q[1] for q in ws) / float(len(ws)))
                    ends.setdefault(key, t)
                for t in list(ends.values())[:2]:
                    plan.doors[t] = "maint"
        # docks at the spine end (arrivals, escape) and on dock rooms' back walls
        if name in ("arrivals", "escape"):
            sx0, sy0, sx1, sy1 = loc.spine
            mid = (sx0 + sx1) // 2
            p = tf(side, u0 + mid, loc.depth)
            q = tf(side, u0 + mid, loc.depth + 1)
            plan.doors[p] = "dock"
            plan.docks.append((p, (q[0] - p[0], q[1] - p[1]), name, (14, 24) if name == "escape" else (7, 12)))
        for rect, rid, meta in loc.rects:
            if meta.get("dock"):
                mid = (rect[0] + rect[2]) // 2
                p = tf(side, u0 + mid, loc.depth)
                q = tf(side, u0 + mid, loc.depth + 1)
                if rect[3] == loc.depth - 1:
                    plan.doors[p] = "dock"
                    plan.docks.append((p, (q[0] - p[0], q[1] - p[1]), meta["dock"],
                                       (9, 11) if meta["dock"] == "cargo" else (5, 7)))
                else:
                    plan.problems.append("%s cannot reach the hull for its dock" % rid)
    # the ring to each maint gap, a maint door every 10+ tiles at most
    cand = set()
    for p, r in list(plan.floor.items()):
        if r != "maint":
            continue
        for dx, dy in DIRS:
            q = (p[0] + dx, p[1] + dy)
            s = (p[0] + 2 * dx, p[1] + 2 * dy)
            if q not in plan.floor and q not in plan.doors and plan.floor.get(s) == "ring":
                cand.add(q)
    chosen = [t for t, k in plan.doors.items() if k == "maint"]
    for q in sorted(cand):
        if all(abs(q[0] - c[0]) + abs(q[1] - c[1]) >= 10 for c in chosen):
            plan.doors[q] = "maint"
            chosen.append(q)
    # tunnel into the satellite and the corner maint
    if hasattr(plan, "sat"):
        for a, b, kind in (("ai_core", "sat_hall", "secure"), ("tcomms", "sat_hall", "secure"),
                           ("tc_control", "sat_hall", "access"), ("tc_control", "tcomms", "link")):
            t = _mid(shared_wall(plan, a, b))
            if t is None:
                plan.problems.append("satellite: %s has no wall on %s" % (a, b))
            else:
                plan.doors[t] = kind
        # where the tunnel leaves the corner maint: a secure door
        cx, cy = None, None
        for p, r in plan.floor.items():
            if r == "sat_tunnel":
                for dx, dy in DIRS:
                    if plan.floor.get((p[0] + dx, p[1] + dy)) == "maint":
                        cx, cy = p
        if cx is not None:
            plan.floor.pop((cx, cy))
            plan.doors[(cx, cy)] = "secure"
    # every piece of maint gets a way in: a maint door onto a hall it runs beside, else onto the nearest room
    maint = {p for p, r in plan.floor.items() if r in ("maint", "catwalk")}
    left = set(maint)
    while left:
        s0 = left.pop()
        comp, stack = {s0}, [s0]
        while stack:
            a = stack.pop()
            for dx, dy in DIRS:
                n = (a[0] + dx, a[1] + dy)
                if n in left:
                    left.discard(n)
                    comp.add(n)
                    stack.append(n)
        has = False
        best = []
        for a in comp:
            for dx, dy in DIRS:
                q = (a[0] + dx, a[1] + dy)
                r = plan.floor.get((a[0] + 2 * dx, a[1] + 2 * dy))
                # a door into an abandoned room is no way in: that room is only reached from here
                inner = r and plan.rooms.get(r, {}).get("dept") == "maint"
                if plan.doors.get(q) == "maint" and not inner:
                    has = True
                if q not in plan.floor and r and r not in ("maint", "catwalk") and not inner:
                    m = plan.rooms.get(r, {})
                    if m.get("secure") or r.startswith(NO_BACK_DOOR):
                        continue
                    best.append((0 if m.get("kind") == "hall" else 1, q))
        if not has and best:
            best.sort()
            plan.doors[best[len([b for b in best if b[0] == best[0][0]]) // 2][1]] = "maint"
        elif not has and len(comp) <= 40 and not any(plan.doors.get((a[0] + dx, a[1] + dy)) for a in comp
                                                     for dx, dy in DIRS):
            # a scrap boxed in by secure rooms: solid wall
            for a in comp:
                plan.floor.pop(a, None)
        elif not has:
            plan.problems.append("maint piece of %d tiles with no way in" % len(comp))
    link_maint(plan)
    open_dead_ends(plan)

    # walls: every tile beside floor that is not floor; hull where it also meets space
    for p in list(plan.floor):
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                q = (p[0] + dx, p[1] + dy)
                if q not in plan.floor:
                    plan.walls.add(q)
    for q in plan.walls:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                s = (q[0] + dx, q[1] + dy)
                if s not in plan.floor and s not in plan.walls:
                    plan.hull.add(q)
                    break
    for q in plan.walls:
        for dx, dy in DIRS:
            r = plan.floor.get((q[0] + dx, q[1] + dy))
            if r and plan.rooms.get(r, {}).get("secure"):
                plan.rwall.add(q)
    for t in list(plan.doors):
        plan.walls.discard(t)
        plan.glass.discard(t)
