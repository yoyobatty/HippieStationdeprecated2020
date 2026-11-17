"""The station as the human maps build it: a small hall loop round the core, four arms out to the hull, departments
in the quadrants between the arms, maint filling every gap.

What the whole-map study found (studies/stations_draw.py, Box/Meta/Delta/Pubby/Donut/Hippie/Endo):
    halls     12-16% of the floor, nearly all 3 wide; one or two big loops (round Command), long arms to the edge;
              arrivals and escape at the ends of arms, 90-140 steps apart
    maint     16-23% of the floor: a mesh between every department and round the hull, 1-4 wide, with abandoned
              rooms in it; every department has maint doors as well as hall doors
    edges     outer rooms and halls are lined with windows; solars off the corners; the AI satellite out on its own

The arms leave the loop at its corners, pinwheel fashion, so each quadrant is a clean rectangle: one arm (hall B)
runs along its inner side and the loop/next arm (hall A) along the other. A quadrant holds two departments in strips
side by side, both fronting hall B and backing onto the hull; the strip next to hall A also opens onto it. Whatever a
strip leaves over behind it is maint, or a small abandoned room when there is space for one.

    loop      core inside: Command and Service in two halves either side of one cross hall
    arms      N, E, S, W from the loop's corners; arrivals at the end of one, escape at the end of the opposite one,
              the AI satellite's tunnel off a third, an EVA airlock on the fourth
"""
import itertools
import math
import re
import random

from forge.proc import solve
from station import program as P
from station.layout import Plan, lay_dept, footprint, finish, _groups, HALL, DIRS
from station.grow import grow_dept

QUADS = ("NE", "SE", "SW", "NW")
ARMS = ("N", "E", "S", "W")
# quadrant q: hall A = arm q (beside strip 0), hall B = arm q+1 (every strip fronts it)
LIKE_SAME = {("engineering", "atmos"): 70, ("medical", "science"): 10, ("security", "civic"): 6,
             ("cargo", "dorms"): 4}
LIKE_NEAR = {("medical", "science"): 10, ("engineering", "science"): 5, ("security", "command"): 0}


def arms_of(q):
    return {q, (q + 1) % 4}


def assign(names, seed):
    """Departments into (quadrant, strip) slots and which arm ends at arrivals."""
    rnd = random.Random("assign|%s" % seed)
    slots = [(q, k) for q in range(4) for k in range(2)]
    best = None
    fp = {}
    for n in names:
        fp[n] = 1.0
    perms = list(itertools.permutations(names))
    rnd.shuffle(perms)
    for perm in perms[:12000]:
        where = dict(zip(perm, slots))
        quad = {n: where[n][0] for n in names}
        for ar in range(4):
            es = (ar + 2) % 4
            s = 0.0
            for (a, b), v in LIKE_SAME.items():
                if a in quad and b in quad and quad[a] == quad[b]:
                    s += v
            for (a, b), v in LIKE_NEAR.items():
                if a in quad and b in quad and abs(quad[a] - quad[b]) % 2 == 1:
                    s += v
            if "cargo" in quad and ar in arms_of(quad["cargo"]):
                s += 18
            if "security" in quad and es in arms_of(quad["security"]):
                s += 10
            if "science" in quad and ar in arms_of(quad["science"]):
                s -= 8
            if "medical" in quad and es in arms_of(quad["medical"]):
                s += 4
            for n in ("dorms", "civic"):
                if n in where and where[n][1] == 0:
                    s += 8
            s += 25 * rnd.random()
            if best is None or s > best[0]:
                best = (s, dict(where), ar)
    return best[1], best[2]


class Strip:
    def __init__(self, name, loc, f, out):
        self.name, self.loc, self.f, self.out = name, loc, f, out


def _vec(a, k):
    return (a[0] * k, a[1] * k)


def _add(*ps):
    return (sum(p[0] for p in ps), sum(p[1] for p in ps))


def generate(seed=1, crew=80, grown=True):
    rnd = random.Random("pinwheel|%s|%s" % (seed, crew))
    plan = Plan(seed, crew)
    # grown rooms come out about an eighth over their ask (dims round up, rows, ears); rooms cut from filled blocks run
    # a quarter over, so both ask for less
    depts = P.program(crew, seed, fill=0.88 if grown else P.FILL)
    by = {d.name: d for d in depts}
    names = [n for n in ("security", "medical", "science", "engineering", "atmos", "cargo", "dorms", "civic")
             if n in by]
    for n in ("dorms", "civic"):
        if n in by:
            by[n].where = "outer"
            for r in by[n].rooms:
                r.front = tuple("ring" if k == "hall" else k for k in r.front)
    where, ar = assign(names, seed)
    es = (ar + 2) % 4
    plan.order = ["%s:%s" % (QUADS[q], ",".join(n for n in names if where[n][0] == q)) for q in range(4)]
    plan.notes.append("quadrants " + "  ".join(plan.order) + "  arrivals arm %s, escape arm %s" % (ARMS[ar], ARMS[es]))

    # ---- the loop and the core inside it
    core = [n for n in ("command", "service") if n in by]
    strips = []
    LX0, LY0 = 0, 0
    if grown:
        LX1, LY1 = grow_core(plan, by, core, strips, rnd, seed)
    else:
        need = sum(footprint(by[n]) for n in core) + HALL * 30 + 2 * 40
        ratio = rnd.uniform(1.15, 1.5)
        cw = int(math.ceil(math.sqrt(need * ratio)))
        ch = int(math.ceil(need / float(cw)))
        LX1, LY1 = cw + 2 * HALL + 1, ch + 2 * HALL + 1
    for rect in ((LX0, LY1 - HALL + 1, LX1, LY1), (LX0, LY0, LX1, LY0 + HALL - 1),
                 (LX0, LY0, LX0 + HALL - 1, LY1), (LX1 - HALL + 1, LY0, LX1, LY1)):
        plan.add_rect(rect, "ring", kind="hall", public=True, label="", dept="hall")
    if not grown:
        lay_halves(plan, by, core, (LX0 + HALL + 1, LY0 + HALL + 1, LX1 - HALL - 1, LY1 - HALL - 1), seed)

    # ---- quadrants
    frames = {0: ((LX0 + 4, LY1 + 2), (1, 0), (0, 1)), 1: ((LX1 + 2, LY1 - 4), (0, -1), (1, 0)),
              2: ((LX1 - 4, LY0 - 2), (-1, 0), (0, -1)), 3: ((LX0 - 2, LY0 + 4), (0, 1), (-1, 0))}
    plan.quads = {}
    for q in range(4):
        c, a, b = frames[q]
        ds = [n for n in sorted(names, key=lambda n: where[n][1]) if where[n][0] == q]
        if not ds:
            continue
        if grown:
            locs = []
            off = rnd.choice((0, 0, 0, 5, 8))
            for k, n in enumerate(ds):
                # a region about 1/0.62 of what the rooms need (human departments fill 0.6 of their box)
                area = footprint(by[n]) / 0.6
                asp_ = rnd.uniform(0.75, 1.3)
                Dm = max(14, int(round(math.sqrt(area * asp_))))
                w = max(14, int(round(area / Dm)))
                for attempt in range(8):
                    loc = grow_dept(by[n], w, Dm, "%s.%d" % (seed, attempt),
                                    left_front="ring" if k == 0 and not off else None)
                    if not loc.broken:
                        break
                    w += 4
                    Dm += 3
                locs.append((n, w, loc))
            place_strips(plan, by, strips, frames[q], q, locs, rnd.choice((1, 1, 2)), seed, off)
            continue
        # one depth for the quadrant: each strip's width set so its rooms fill about that depth
        asp = {n: rnd.uniform(1.0, 1.45) for n in ds}
        D0 = max(math.sqrt(footprint(by[n]) * asp[n]) for n in ds)
        deep = max(ds, key=lambda n: footprint(by[n]))
        locs = []
        for k, n in enumerate(ds):
            # the biggest department sets the quadrant's depth; the other runs shallower and wider, leaving room
            # behind it for maint and abandoned rooms, so the hull steps
            D = D0 if n == deep else D0 * rnd.uniform(0.6, 0.9)
            w = max(12, int(round(footprint(by[n]) / D)))
            loc = lay_dept(by[n], w, seed, left_front="ring" if k == 0 else None)
            # narrower if it ran much deeper than the quadrant wants, wider if much shallower
            for _ in range(4):
                if loc.depth > D * 1.25 and w < 60:
                    w += 3
                elif loc.depth < D * 0.7 and w > 14:
                    w -= 2
                else:
                    break
                loc = lay_dept(by[n], w, seed, left_front="ring" if k == 0 else None)
            locs.append((n, w, loc))
        H = max(loc.depth for _, _, loc in locs)
        mw = rnd.choice((2, 2, 3))
        i0 = 0
        qinfo = dict(c=c, a=a, b=b, H=H, mw=mw, strips=[])
        for k, (n, w, loc) in enumerate(locs):
            def f(u, v, i0=i0, c=c, a=a, b=b):
                return _add(c, _vec(a, i0 + u), _vec(b, v))
            plan.problems += ["%s: %s" % (n, x) for x in loc.broken]
            for rect, rid, meta in loc.rects:
                meta = dict(meta)
                meta.setdefault("label", "")
                p0, p1 = f(rect[0], rect[1]), f(rect[2], rect[3])
                plan.add_rect((min(p0[0], p1[0]), min(p0[1], p1[1]), max(p0[0], p1[0]), max(p0[1], p1[1])), rid,
                              dept=n, colour=by[n].colour, **meta)
            strips.append((f, n, 0, w, loc))
            qinfo["strips"].append((n, i0, w, loc.depth, f))
            i0 += w + 2 + mw
        qinfo["W"] = i0 - 2 - mw
        plan.quads[q] = qinfo
        maint_and_filler(plan, qinfo, seed, q)

    # ---- arms: from the loop's corners out past both quadrants beside them
    lanes = {0: ((LX0, LY1 + 1), (0, 1), (1, 0)), 1: ((LX1 + 1, LY1 - 2), (1, 0), (0, 1)),
             2: ((LX1 - 2, LY0 - 1), (0, -1), (1, 0)), 3: ((LX0 - 1, LY0), (-1, 0), (0, 1))}
    others = [x for x in range(4) if x not in (ar, es)]
    sat_arm = max(others, key=lambda x: (abs(x - ar) % 2, rnd.random()))
    ends = {}
    for arm in range(4):
        start, out, perp = lanes[arm]
        ext = 0
        for q in (arm, (arm - 1) % 4):
            for p, r in plan.floor.items():
                if plan.rooms.get(r, {}).get("dept") in ("hall", "solar") or r in ("ring",):
                    continue
                if _in_quad(plan, q, p):
                    ext = max(ext, (p[0] - start[0]) * out[0] + (p[1] - start[1]) * out[1])
        length = ext + 2
        for k in range(length):
            for j in range(HALL):
                plan.floor.setdefault(_add(start, _vec(out, k), _vec(perp, j)), "ring")
        what = "arrivals" if arm == ar else "escape" if arm == es else "sat" if arm == sat_arm else "eva"
        ends[arm] = (what, _add(start, _vec(out, length)), out, perp)

    # ---- solars off the quadrants' outer corners, clear of the arm halls and the space their ends will take; the
    # tails then keep clear of the fields
    keep_out = solars_clear_of(plan, [(QUADS[q], info) for q, info in plan.quads.items()], ends.values())
    for arm in range(4):
        what, st, out, perp = ends[arm]
        ends[arm] = (what,) + arm_tail(plan, st, out, perp, what, keep_out, rnd)

    # ---- arm ends: arrivals, escape, the satellite, an EVA airlock
    for arm in range(4):
        lay_end(plan, by, strips, seed, *ends[arm])

    finish(plan, strips, by, lambda f, u, v: f(u, v), None)
    windows(plan, seed)
    orient(plan, random.Random("orient|%s" % seed))
    return plan


# side rooms by size (tiles up to): (label, weight)
SIDE_ROOMS = ((12, (("vending", 3), ("e-closet", 3), ("fire closet", 2), ("substation", 2), ("closet", 2))),
              (24, (("restroom", 3), ("aux storage", 2), ("office", 2), ("substation", 1), ("photo", 1),
                    ("barber", 1), ("e-closet", 1), ("vending", 1))),
              (64, (("lounge", 3), ("vacant", 2), ("office", 2), ("game room", 1), ("aux storage", 1),
                    ("barber", 1), ("restroom", 1))),
              # where a hall runs past a big pocket: somewhere to spend a shift (Meta's park, Box's holodeck)
              (999, (("park", 3), ("arcade", 2), ("holodeck", 2), ("pool", 1), ("gallery", 1), ("lounge", 1))))
# most of each a station has (others: no cap)
SIDE_CAP = {"vending": 3, "restroom": 2, "lounge": 2, "game room": 1, "barber": 1, "photo": 1, "substation": 4,
            "office": 4, "vacant": 3, "park": 1, "arcade": 1, "holodeck": 1, "pool": 1, "gallery": 1}
PUBLIC_SIDE = {"vending", "restroom", "lounge", "game room", "barber", "photo", "park", "arcade", "holodeck", "pool",
               "gallery"}
CORE_RING = {"bridge", "hop", "eva", "bar", "hydro", "garden", "janitor"}


def place_strips(plan, by, strips, frame, q, locs, mw, seed, off=0, hall_left=True, trace=True):
    """Grown departments side by side in a quadrant, then maint traced round their outlines. Between two departments
    sometimes a side street instead of maint, back toward the hull; in front of some a plaza (the hall widens before
    the department's door)."""
    rnd = random.Random("strips|%s|%s" % (seed, q))
    c, a, b = frame
    info = dict(c=c, a=a, b=b, mw=mw, strips=[], streets=[], plazas=[], hall_left=hall_left)
    i0 = off
    H = 0
    for k, (n, w, loc) in enumerate(locs):
        s = 3 if rnd.random() < 0.25 else 0

        def f(u, v, i0=i0, s=s, c=c, a=a, b=b):
            return _add(c, _vec(a, i0 + u), _vec(b, v + s))
        plan.problems += ["%s: %s" % (n, x) for x in loc.broken]
        for rect, rid, meta in loc.rects:
            meta = dict(meta)
            meta.setdefault("label", "")
            p0, p1 = f(rect[0], rect[1]), f(rect[2], rect[3])
            plan.add_rect((min(p0[0], p1[0]), min(p0[1], p1[1]), max(p0[0], p1[0]), max(p0[1], p1[1])), rid,
                          dept=n, colour=by[n].colour, **meta)
        strips.append((f, n, 0, w, loc))
        info["strips"].append((n, i0, w, loc.depth, f, loc, s))
        if s:
            info["plazas"].append((i0, w, s))
        H = max(H, loc.depth + s)
        # a small station has fewer streets: each is hall a small crew still has to walk past
        if k + 1 < len(locs) and rnd.random() < 0.45 * min(1.0, plan.crew / 80.0):
            hw = rnd.choice((2, 3))
            info["streets"].append((i0 + w + 1, hw))
            i0 += w + 2 + hw
        else:
            i0 += w + 2 + mw
    info["H"] = H
    info["W"] = i0 - 2 - mw
    plan.quads[q] = info
    if trace:
        trace_maint(plan, info, seed, q)
    return info


def _side_features(block_from, area, lines, rnd):
    """Where a hall runs past free floor: a small room off it (door on the hall), an alcove (the hall widens), or
    nothing (it stays maint). lines: (tiles of the first row past the hall's wall, in order; step away from the hall).
    Returns [(kind, tiles)]; an alcove's tiles include the wall it opens."""
    block = set()
    for t in block_from:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                block.add((t[0] + dx, t[1] + dy))

    def free(t):
        return t in area and t not in block
    feats = []
    for row, out_ in lines:
        # each hall line has its own mood: bare wall, a room here and there, or busy
        busy = rnd.choice((0.1, 0.3, 0.3, 0.5))
        k = 0
        while k < len(row):
            if not free(row[k]):
                k += 1
                continue
            j = k
            while j < len(row) and free(row[j]):
                j += 1
            run = row[k:j]
            p = rnd.randint(0, 2)
            # a big pocket behind the hall: sometimes one big public room
            if len(run) - p >= 10:
                piece = run[p:p + 10]
                dbig = 0
                while dbig < 13 and all(free(_add(t, _vec(out_, dbig))) for t in piece):
                    dbig += 1
                if dbig >= 8 and rnd.random() < 0.7:
                    L = rnd.randint(10, min(15, len(run) - p))
                    piece = run[p:p + L]
                    d = dbig
                    while d > 7 and not all(free(_add(t, _vec(out_, d - 1))) for t in piece):
                        d -= 1
                    if d >= 8 and all(free(_add(t, _vec(out_, i))) for t in piece for i in range(d)):
                        d = rnd.randint(8, d)
                        tiles = [_add(t, _vec(out_, i)) for t in piece for i in range(d)]
                        feats.append(("room", tiles))
                        for t in tiles:
                            for dx in (-1, 0, 1):
                                for dy in (-1, 0, 1):
                                    block.add((t[0] + dx, t[1] + dy))
                        p += L + 1 + rnd.randint(0, 3)
            while len(run) - p >= 3:
                L = min(len(run) - p, rnd.randint(3, 7))
                piece = run[p:p + L]
                dmax = 0
                while dmax < 6 and all(free(_add(t, _vec(out_, dmax))) for t in piece):
                    dmax += 1
                roll = rnd.random()
                tiles = None
                if dmax >= 3 and roll < busy:
                    d = rnd.randint(3, dmax)
                    tiles = [_add(t, _vec(out_, i)) for t in piece for i in range(d)]
                    feats.append(("room", tiles))
                elif dmax >= 1 and roll < busy + 0.25 and L <= 5:
                    d = rnd.randint(1, min(2, dmax))
                    tiles = [_add(t, _vec(out_, i)) for t in piece for i in range(-1, d)]
                    feats.append(("alcove", tiles))
                if tiles:
                    for t in tiles:
                        for dx in (-1, 0, 1):
                            for dy in (-1, 0, 1):
                                block.add((t[0] + dx, t[1] + dy))
                p += L + 1 + rnd.randint(0, 3)
            k = j
    return feats


def _put_features(plan, feats, at, rnd, tag):
    """Side rooms and alcoves into the plan; -> (room tiles, alcove tiles) in the caller's coords."""
    rooms, halls = set(), set()
    n = 0
    used = plan.__dict__.setdefault("side_used", {})
    last = None
    for kind, tiles in feats:
        if kind == "alcove":
            for t in tiles:
                plan.floor.setdefault(at(*t), "ring")
            halls |= set(tiles)
            continue
        n += 1
        rid = "side_%s_%d" % (tag, n)
        opts = [(lab, w) for lab, w in next(ls for top, ls in SIDE_ROOMS if len(tiles) <= top)
                if lab != last and used.get(lab, 0) < SIDE_CAP.get(lab, 99)] or \
            [("vacant" if len(tiles) > 24 else "closet", 1)]
        label = rnd.choices([o[0] for o in opts], [o[1] for o in opts])[0]
        used[label] = used.get(label, 0) + 1
        last = label
        pts = [at(*t) for t in tiles]
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        pub = label in PUBLIC_SIDE
        plan.add_rect((min(xs), min(ys), max(xs), max(ys)), rid, kind="room", dept="side", label=label, public=pub,
                      front=("ring",), links=(), maint=not pub,
                      colour=(176, 172, 158) if pub else (150, 140, 120))
        rooms |= set(tiles)
    return rooms, halls


def _gaps(dep, area, mw, rnd, outer):
    """Maint 1-mw wide round dep inside area; pockets it closes in become abandoned rooms (or wall where too small
    for one), pockets outer() calls open stay empty. -> maint, solid, aband rects."""
    dist = {t: 0 for t in dep}
    frontier = list(dep)
    for k in range(1, 2 + mw):
        nxt = []
        for t in frontier:
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    s_ = (t[0] + dx, t[1] + dy)
                    if s_ not in dist and s_ in area:
                        dist[s_] = k
                        nxt.append(s_)
        frontier = nxt
    maint = {t for t, k in dist.items() if k >= 2}
    void = {t for t in area if t not in dist}
    solid = set()
    aband = []
    extra = set()
    ring = frozenset(maint)
    left = set(void)
    # pocket tiles a passage may be dug through (wall left over, and the gaps between abandoned rooms)
    diggable = set()
    while left:
        s0 = left.pop()
        comp, st = {s0}, [s0]
        while st:
            t = st.pop()
            for dx, dy in DIRS:
                n_ = (t[0] + dx, t[1] + dy)
                if n_ in left:
                    left.discard(n_)
                    comp.add(n_)
                    st.append(n_)
        if outer(comp):
            continue
        if len(comp) < 14:
            solid |= comp
            continue
        rest = set(comp)
        diggable |= comp
        # as many rooms as the pocket holds (a big pocket left as solid wall reads as dead space)
        # (the ring's core pockets stopped at 8 and left 200-tile blocks of wall, 2026-11-16)
        for _ in range(40):
            core = {t for t in rest if all((t[0] + dx, t[1] + dy) in rest for dx in (-1, 0, 1) for dy in (-1, 0, 1))}
            r = _biggest_rect(core)
            if not r or (r[2] - r[0] + 1) < 3 or (r[3] - r[1] + 1) < 3 or (r[2] - r[0] + 1) * (r[3] - r[1] + 1) < 12:
                break
            # no hall-sized rooms: clip to 9 a side
            x0, y0, x1, y1 = r
            if x1 - x0 + 1 > 9:
                x0 = rnd.randint(x0, x1 - 8)
                x1 = x0 + 8
            if y1 - y0 + 1 > 9:
                y0 = rnd.randint(y0, y1 - 8)
                y1 = y0 + 8
            aband.append((x0, y0, x1, y1))
            rest -= {(x, y) for x in range(x0 - 1, x1 + 2) for y in range(y0 - 1, y1 + 2)}
        inner = {(x, y) for x0, y0, x1, y1 in aband for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)}
        for t in rest:
            # what is left: maint where it touches maint; maint too where a wall still stands between it and every
            # room (a strip between packed rooms left as wall was a 20x5 block of solid wall in the ring's core);
            # else wall
            n8 = [(t[0] + dx, t[1] + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy]
            if any((t[0] + dx, t[1] + dy) in ring for dx, dy in DIRS):
                maint.add(t)
            elif all(n in comp or n in ring for n in n8) and not any(n in inner for n in n8):
                extra.add(t)
            else:
                solid.add(t)
    # leftover maint shut in among the rooms: a passage to the maint ring, else wall again
    left = set(extra)
    while left:
        s0 = left.pop()
        piece, st = {s0}, [s0]
        while st:
            t = st.pop()
            for dx, dy in DIRS:
                n_ = (t[0] + dx, t[1] + dy)
                if n_ in left:
                    left.discard(n_)
                    piece.add(n_)
                    st.append(n_)
        if any((t[0] + dx, t[1] + dy) in maint for t in piece for dx, dy in DIRS):
            maint |= piece
            continue
        if len(piece) < 6:
            solid |= piece
            continue
        inner = {(x, y) for x0, y0, x1, y1 in aband for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)}
        dig = {t for t in solid if not any((t[0] + dx, t[1] + dy) in inner for dx, dy in DIRS)}
        prev = {s_: None for s_ in piece}
        todo, k, hit = list(piece), 0, None
        while k < len(todo):
            t = todo[k]
            k += 1
            if t not in piece and any((t[0] + dx, t[1] + dy) in maint for dx, dy in DIRS):
                hit = t
                break
            for dx, dy in DIRS:
                n_ = (t[0] + dx, t[1] + dy)
                if n_ in dig and n_ not in prev:
                    prev[n_] = t
                    todo.append(n_)
        if hit is None:
            solid |= piece
            continue
        maint |= piece
        while hit is not None and hit not in piece:
            solid.discard(hit)
            maint.add(hit)
            hit = prev[hit]
    # a room deep in its pocket has wall all round: dig a passage through it to the nearest maint
    for x0, y0, x1, y1 in aband:
        sides = [(x, y0 - 1, 0, -1) for x in range(x0, x1 + 1)] + [(x, y1 + 1, 0, 1) for x in range(x0, x1 + 1)] + \
                [(x0 - 1, y, -1, 0) for y in range(y0, y1 + 1)] + [(x1 + 1, y, 1, 0) for y in range(y0, y1 + 1)]
        if any((wx + dx, wy + dy) in maint for wx, wy, dx, dy in sides):
            continue
        inside = {(x, y) for a0, b0, a1, b1 in aband for x in range(a0 - 1, a1 + 2) for y in range(b0 - 1, b1 + 2)}
        dig = (solid | diggable) - inside - maint
        start = [(wx + dx, wy + dy) for wx, wy, dx, dy in sides if (wx + dx, wy + dy) in dig]
        prev = {s_: None for s_ in start}
        todo, k, hit = list(start), 0, None
        while k < len(todo):
            t = todo[k]
            k += 1
            if any((t[0] + dx, t[1] + dy) in maint for dx, dy in DIRS):
                hit = t
                break
            for dx, dy in DIRS:
                n_ = (t[0] + dx, t[1] + dy)
                if n_ in dig and n_ not in prev:
                    prev[n_] = t
                    todo.append(n_)
        while hit is not None:
            solid.discard(hit)
            maint.add(hit)
            hit = prev[hit]
    # one still walled in (packed among others with no gap to dig): wall
    keep = []
    for x0, y0, x1, y1 in aband:
        ring_ = [(x, y0 - 2) for x in range(x0, x1 + 1)] + [(x, y1 + 2) for x in range(x0, x1 + 1)] + \
                [(x0 - 2, y) for y in range(y0, y1 + 1)] + [(x1 + 2, y) for y in range(y0, y1 + 1)]
        if any(t in maint for t in ring_):
            keep.append((x0, y0, x1, y1))
        else:
            solid |= {(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)}
    return maint, solid, keep


def _gaps_to_plan(plan, at, maint, solid, aband, tag):
    for t in maint:
        plan.floor.setdefault(at(*t), "maint")
    plan.rooms["maint"] = dict(kind="maint", dept="maint", label="", public=False)
    for k, (x0, y0, x1, y1) in enumerate(aband):
        rid = "aband_%s_%d" % (tag, k)
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                plan.floor[at(x, y)] = rid
        plan.rooms[rid] = dict(kind="room", dept="maint", label="", public=False, maint=True,
                               colour=(120, 110, 96), front=(), links=())
    for t in solid:
        plan.walls.add(at(*t))


def trace_maint(plan, info, seed, q):
    """Side rooms and alcoves off the halls past the departments, then maint 1-2 wide round every outline; pockets
    it closes in become abandoned rooms (or wall where too small for one); pockets open to the outside stay space, so
    the hull follows the departments."""
    rnd = random.Random("trace|%s|%s" % (seed, q))
    c, a, b, H, mw = info["c"], info["a"], info["b"], info["H"], info["mw"]
    # Wfix: the block runs to a hall past its right side (that hall's wall at Wfix + 1)
    Wq = info.get("Wfix") or info["W"] + mw
    # Hfix: a block closed in behind too (inside a ring), down to the wall before the next block
    Hq = info.get("Hfix") or H + mw

    def at(i, j):
        return _add(c, _vec(a, i), _vec(b, j))
    dep = set()
    out = set()
    for n, i0, w, d, f, loc, s in info["strips"]:
        for (u, v) in loc.tiles:
            dep.add((i0 + u, v + s))
        # nothing behind a room that needs the hull (docks, the engine's space side, the range)
        for rect, rid, meta in loc.rects:
            if "back" in (meta.get("front") or ()):
                for i in range(i0 + rect[0] - 1, i0 + rect[2] + 2):
                    for j in range(rect[3] + s + 1, Hq + 1):
                        out.add((i, j))
    hall = set()
    for i0, w, s in info["plazas"]:
        for i in range(i0, i0 + w):
            for j in range(-1, s - 1):
                hall.add((i, j))
    # the main hall along the front, the arm down the left
    lines = [([(i, 0) for i in range(0, Wq + 1)], (0, 1))]
    # the halls down the sides run as far as left_len / right_len (when given), so side rooms stop where they do
    if info.get("hall_left", True):
        lines.append(([(0, j) for j in range(0, min(Hq, info.get("left_len", Hq)) + 1)], (1, 0)))
    if info.get("Wfix"):
        lines.append(([(Wq, j) for j in range(0, min(Hq, info.get("right_len", Hq)) + 1)], (-1, 0)))
    # a hall past the back too (a ring's cross hall)
    if info.get("back_hall"):
        lines.append(([(i, Hq) for i in range(0, Wq + 1)], (0, -1)))
    for s0, hw in info["streets"]:
        Ls = rnd.randint(max(4, H // 2), max(4, H - 2))
        for i in range(s0, s0 + hw):
            for j in range(-1, Ls):
                hall.add((i, j))
        lines.append(([(s0 - 2, j) for j in range(0, Ls)], (-1, 0)))
        lines.append(([(s0 + hw + 1, j) for j in range(0, Ls)], (1, 0)))
        lines.append(([(i, Ls + 1) for i in range(s0 - 1, s0 + hw + 1)], (0, 1)))
    area = {(i, j) for i in range(0, Wq + 1) for j in range(0, Hq + 1)} - out
    rnd.shuffle(lines)
    # a block closed in by another block behind it: side rooms keep off the last row, so two blocks' rooms never meet
    # without a wall
    fa = area - {(i, Hq) for i in range(0, Wq + 1)} if info.get("closed") and not info.get("back_hall") else area
    feats = _side_features(dep | hall, fa, lines, rnd)
    rooms, alc = _put_features(plan, feats, at, rnd, str(q))
    for t in hall:
        plan.floor.setdefault(at(*t), "ring")

    right_open = not info.get("Wfix")

    def outer(comp):
        if info.get("closed"):
            return False
        return any((right_open and t[0] >= Wq) or t[1] >= Hq or any((t[0] + dx, t[1] + dy) in out for dx, dy in DIRS)
                   for t in comp)
    maint, solid, aband = _gaps(dep | hall | rooms | alc, area, mw, rnd, outer)
    _gaps_to_plan(plan, at, maint, solid, aband, str(q))
    info["Wf"] = Wq
    info["E"] = Hq
    far = max(maint, key=lambda t: (t[0] + t[1], t[1])) if maint else (Wq, Hq)
    info["corner"] = far


def grow_core(plan, by, core, strips, rnd, seed):
    """Command and Service grown back to back inside the loop, each from its own side of it (and the loop's ends);
    what they leave between them is maint, side rooms off the loop, and abandoned rooms where it opens out.
    -> the loop's far corner (LX1, LY1)."""
    for n in core:
        for r in by[n].rooms:
            r.front = tuple(("ring" if r.id in CORE_RING else "dept") if k == "hall" else k for k in r.front)
    area = {n: footprint(by[n]) / 0.72 for n in core}
    W = max(20, int(round(math.sqrt(sum(area.values()) * rnd.uniform(1.1, 1.6)))))
    D = {n: max(10, int(round(area[n] / W))) for n in core}
    locs = {}
    for attempt in range(12):
        for n in core:
            if n not in locs or locs[n].broken:
                locs[n] = grow_dept(by[n], W, D[n], "%s.c%d" % (seed, attempt), left_front="ring", right_front="ring")
        bad = [n for n in core if locs[n].broken]
        if not bad:
            break
        # every second miss widens the core (both halves are regrown to the new width), else deepens the half
        if attempt % 2:
            W += 3
            locs = {}
        for n in bad:
            D[n] += 2
    # crop to what the halves use, so the loop closes round them
    W = max(max(u for u, v in locs[n].tiles) + 1 for n in core)
    for n in core:
        D[n] = max(v for u, v in locs[n].tiles) + 1
    gap = 3
    order = list(core)
    rnd.shuffle(order)
    ch = sum(D[n] for n in order) + gap * (len(order) - 1)
    X0, Y0 = HALL + 1, HALL + 1
    X1, Y1 = X0 + W - 1, Y0 + ch - 1
    frames = [((X0, Y0), (1, 0), (0, 1)), ((X0, Y1), (1, 0), (0, -1))]
    for n, (c, a, b) in zip(order, frames):
        loc = locs[n]

        def f(u, v, c=c, a=a, b=b):
            return _add(c, _vec(a, u), _vec(b, v))
        plan.problems += ["%s: %s" % (n, x) for x in loc.broken]
        for rect, rid, meta in loc.rects:
            meta = dict(meta)
            meta.setdefault("label", "")
            p0, p1 = f(rect[0], rect[1]), f(rect[2], rect[3])
            plan.add_rect((min(p0[0], p1[0]), min(p0[1], p1[1]), max(p0[0], p1[0]), max(p0[1], p1[1])), rid,
                          dept=n, colour=by[n].colour, **meta)
        strips.append((f, n, 0, W, loc))
    region = {(x, y) for x in range(X0, X1 + 1) for y in range(Y0, Y1 + 1)}
    dep = {p for p in region if p in plan.floor}
    lines = [([(x, Y0) for x in range(X0, X1 + 1)], (0, 1)), ([(x, Y1) for x in range(X0, X1 + 1)], (0, -1)),
             ([(X0, y) for y in range(Y0, Y1 + 1)], (1, 0)), ([(X1, y) for y in range(Y0, Y1 + 1)], (-1, 0))]
    rnd.shuffle(lines)
    feats = _side_features(dep, region, lines, rnd)
    rooms, alc = _put_features(plan, feats, lambda x, y: (x, y), rnd, "c")
    maint, solid, aband = _gaps(dep | rooms | alc, region, 1, rnd, lambda comp: False)
    _gaps_to_plan(plan, lambda x, y: (x, y), maint, solid, aband, "c")
    return X1 + HALL + 1, Y1 + HALL + 1


def _biggest_rect(tiles):
    if not tiles:
        return None
    xs = [t[0] for t in tiles]
    ys = [t[1] for t in tiles]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    hgt = [0] * (x1 - x0 + 1)
    best = None
    for y in range(y0, y1 + 1):
        for i, x in enumerate(range(x0, x1 + 1)):
            hgt[i] = hgt[i] + 1 if (x, y) in tiles else 0
        st = []
        for i in range(len(hgt) + 1):
            h = hgt[i] if i < len(hgt) else 0
            start = i
            while st and st[-1][1] >= h:
                si, sh = st.pop()
                area = sh * (i - si)
                if sh and (best is None or area > best[0]):
                    best = (area, (x0 + si, y - sh + 1, x0 + i - 1, y))
                start = si
            st.append((start, h))
    return best[1] if best else None


def _in_quad(plan, q, p):
    info = plan.quads.get(q)
    if not info:
        return False
    c, a, b = info["c"], info["a"], info["b"]
    i = (p[0] - c[0]) * a[0] + (p[1] - c[1]) * a[1]
    j = (p[0] - c[0]) * b[0] + (p[1] - c[1]) * b[1]
    return -1 <= i <= info["Wf"] + 1 and -1 <= j <= info["E"] + 1


def maint_and_filler(plan, info, seed, q):
    """Maint between the strips and down the far side, and behind each strip at its own depth so the hull steps;
    behind some shallower strips a row of abandoned rooms past the maint."""
    rnd = random.Random("fill|%s|%d" % (seed, q))
    c, a, b, H, mw = info["c"], info["a"], info["b"], info["H"], info["mw"]
    strips = info["strips"]

    def at(i, j):
        return _add(c, _vec(a, i), _vec(b, j))
    # how far out each strip's back reaches (last floor row)
    ext = []
    for k, (n, i0, w, d, f) in enumerate(strips):
        e = d + mw
        room = H + mw - (d + mw + 1)
        if room >= 5 and w >= 8 and rnd.random() < 0.7:
            fd = rnd.randint(4, min(8, room))
            i = i0
            while i < i0 + w:
                rw = min(rnd.randint(4, 8), i0 + w - i)
                if i0 + w - (i + rw) < 4:
                    rw = i0 + w - i
                rid = "aband_%d_%d_%d" % (q, k, i)
                rows = fd if rnd.random() < 0.75 else max(3, fd - rnd.randint(1, 3))
                for x in range(i, i + rw):
                    for y in range(e + 2, e + 2 + rows):
                        plan.floor[at(x, y)] = rid
                plan.rooms[rid] = dict(kind="room", dept="maint", label="", public=False, maint=True,
                                       colour=(120, 110, 96), front=(), links=())
                i += rw + 1
            e += 1 + fd
        ext.append(e)
        # the maint right behind the strip, through its side walls into the gaps either side
        lo = i0 - 1 if k else i0
        for i in range(lo, i0 + w + 1):
            for j in range(d + 1, d + 1 + mw):
                plan.floor.setdefault(at(i, j), "maint")
    for k, (n, i0, w, d, f) in enumerate(strips):
        top = max(ext[k], ext[k + 1] if k + 1 < len(strips) else 0)
        for i in range(i0 + w + 1, i0 + w + 1 + mw):
            for j in range(0, top + 1):
                plan.floor.setdefault(at(i, j), "maint")
    info["E"] = max(ext)
    info["Ef"] = ext[-1]
    info["Wf"] = info["W"] + mw
    plan.rooms["maint"] = dict(kind="maint", dept="maint", label="", public=False)


# a stock array (Box, Meta), in its own frame: s across (-8..8, the spine at 0), o out from the array's near edge
SOLAR_W, SOLAR_PAIRS = 8, 3


def solar_field(pairs=SOLAR_PAIRS):
    """-> {(s, o): kind}: a lattice frame; pairs of 5-panel rows each side of the spine with a cable row between each
    pair; spacer rows of lattice struts; the tracker in a lattice cap at the far end; the spine's cable from the near
    edge to the first panel row and from the last to the tracker."""
    W = SOLAR_W
    out = {}
    for s_ in range(-W, W + 1):
        out[(s_, 0)] = "lattice"
    out[(0, 0)] = "cable"
    for s_ in (-W, 0, W):
        out[(s_, 1)] = "lattice"
    out[(0, 1)] = "cable"
    o = 2
    for k in range(pairs):
        for row in (o, o + 2):
            for s_ in (-W, -W + 1, W - 1, W):
                out[(s_, row)] = "lattice"
            out[(0, row)] = "cable"     # the spine runs the field's length: every row's cable joins it
            for s_ in list(range(-6, -1)) + list(range(2, 7)):
                out[(s_, row)] = "panel"
        out[(-W, o + 1)] = out[(W, o + 1)] = "lattice"
        for s_ in range(-6, 7):
            out[(s_, o + 1)] = "cable"
        if k + 1 < pairs:
            for s_ in (-W, -4, 4, W):
                out[(s_, o + 3)] = "lattice"
            out[(0, o + 3)] = "cable"
        o += 4
    # past the last panel row: a strut row, the frame, the tracker cap
    o -= 1
    for s_ in (-W, -5, 5, W):
        out[(s_, o)] = "lattice"
    out[(0, o)] = "cable"
    for s_ in range(-W, W + 1):
        out[(s_, o + 1)] = "lattice"
    out[(0, o + 1)] = "cable"
    for s_ in range(-2, 3):
        out[(s_, o + 2)] = "lattice"
        out[(s_, o + 4)] = "lattice"
    out[(0, o + 2)] = "tracker"
    out[(-2, o + 3)] = out[(2, o + 3)] = "lattice"
    return out


SOLAR_FIELD = solar_field()
SOLAR_DEPTH = max(o for s_, o in SOLAR_FIELD) + 1
# hull side to the field: wall, control room (3 deep), wall + inner airlock, the lock, outer airlock, 2 of catwalk
SOLAR_LEAD = 10


def solars_clear_of(plan, blocks, ends):
    """Lay each block's array, keeping off the space past each arm end that its tail and end room will want; a block
    with no room for one hands its array to the best hull spot anywhere on the station, away from the arrays already
    laid. -> the fields' keep-out set (without that reserve) for the tails."""
    reserve = set()
    for what, st, out, perp in ends:
        ea, eb, eo = END_ROOM[what]
        for k in range(0, min(eo, 20) + 8):
            for j in range(-ea - 3, 4 + eb + 3):
                reserve.add(_add(st, _vec(out, k), _vec(perp, j)))
    keep = set(reserve)
    left = [label for label, info in blocks if not corner_solar(plan, info, label, keep)]
    for label in left:
        if not any_solar(plan, label, keep):
            plan.notes.append("solar %s: no room for an array" % label)
    return keep - reserve


SOLAR_TOTAL = SOLAR_LEAD + SOLAR_DEPTH + 2


def _dock_tiles(plan):
    return [t for t, r in plan.floor.items() if plan.rooms.get(r, {}).get("dock")
            or r in ("arrivals_spine", "escape_spine")]


def _solar_fits(plan, m, d, perp, gap, keep_out, dock_tiles):
    """Is the lane out of maint tile m (d out, perp across) clear for a control room, the lead and the field?"""
    if _add(m, d) in plan.floor:
        return False
    lane = [_add(m, _vec(d, o), _vec(perp, s_)) for o in range(1, SOLAR_TOTAL) for s_ in range(-SOLAR_W - 2, SOLAR_W + 3)]
    if any(t in plan.floor or t in plan.walls or t in keep_out or t in plan.solar for t in lane):
        return False
    # the room's wall must sit on a hull run: maint (or nothing) either side of m along the hull, not a room
    if not all(plan.floor.get(_add(m, _vec(perp, s_))) in (None, "maint") for s_ in (-2, -1, 1, 2)):
        return False
    xs = [t[0] for t in lane]
    ys = [t[1] for t in lane]
    return not any(min(xs) - gap <= t[0] <= max(xs) + gap and min(ys) - gap <= t[1] <= max(ys) + gap
                   for t in dock_tiles)


def corner_solar(plan, info, label, keep_out, rnd=None):
    """A stock solar array off a block's outside, as near its far corner as it fits: a control room (console, SMES,
    APC) built out from the hull maint, a double airlock, a cable catwalk, then the field. The field and its lead
    stay off the floor plan (no walls round lattice); their footprint and a margin go into keep_out. -> laid?"""
    c, a, b, mw = info["c"], info["a"], info["b"], info["mw"]
    Wq, Hq = info.get("Wf", info["W"] + mw), info.get("E", info["H"] + mw)

    def at(i, j):
        return _add(c, _vec(a, i), _vec(b, j))
    dock_tiles = _dock_tiles(plan)
    cands = []
    for i in range(0, Wq + 1):
        for j in range(0, Hq + 1):
            t = at(i, j)
            if plan.floor.get(t) != "maint":
                continue
            # out the back (b) or out past the far end (a), whichever way is open space; back past the near end (-a)
            # only when neither fits
            na = (-a[0], -a[1])
            for d, perp, score, tier in ((b, a, i + 1.2 * j, 0), (a, b, 1.2 * i + j, 0), (na, b, j - i, 1)):
                cands.append((tier, -score, t, d, perp))
    cands.sort(key=lambda x: x[:2])
    # well clear of the docks first (shuttles swing wide), then nearer
    pick = next(((m, d, perp) for gap, tiers in ((16, (0,)), (6, (0, 1)), (3, (0, 1))) for tier, _, m, d, perp in cands
                 if tier in tiers and _solar_fits(plan, m, d, perp, gap, keep_out, dock_tiles)), None)
    if not pick:
        return False
    _lay_solar(plan, *pick, label, keep_out)
    return True


def any_solar(plan, label, keep_out):
    """The array of a block with no room off its own hull: any hull maint tile on the station, out whichever way is
    open, as far from the arrays already laid and from the docks as it can. -> laid?"""
    dock_tiles = _dock_tiles(plan)
    laid = [((r[0] + r[2]) / 2.0, (r[1] + r[3]) / 2.0) for r, _ in plan.solars]
    xs = [t[0] for t in plan.floor]
    ys = [t[1] for t in plan.floor]
    mid = ((min(xs) + max(xs)) / 2.0, (min(ys) + max(ys)) / 2.0)
    cands = []
    for m, r in plan.floor.items():
        if r != "maint":
            continue
        for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            if _add(m, d) in plan.floor:
                continue
            far = _add(m, _vec(d, SOLAR_TOTAL // 2))
            spread = min([abs(far[0] - p[0]) + abs(far[1] - p[1]) for p in laid] or [999])
            cands.append((-min(spread, 80), -(abs(far[0] - mid[0]) + abs(far[1] - mid[1])), m, d, (d[1], d[0])))
    cands.sort(key=lambda x: x[:2])
    pick = next(((m, d, perp) for gap in (16, 6, 3) for _, _, m, d, perp in cands
                 if _solar_fits(plan, m, d, perp, gap, keep_out, dock_tiles)), None)
    if not pick:
        return False
    _lay_solar(plan, *pick, label, keep_out)
    return True


def _lay_solar(plan, m, d, perp, label, keep_out):
    def f(s_, o):
        return _add(m, _vec(d, o), _vec(perp, s_))
    rid = "solar_%s" % label
    for o in range(2, 5):
        for s_ in (-1, 0, 1):
            plan.floor[f(s_, o)] = rid
    plan.rooms[rid] = dict(kind="room", dept="solar", label="solars", public=False, maint=True, front=(), links=(),
                           colour=(212, 178, 92))
    lock = "solar_lock_%s" % label
    plan.floor[f(0, 6)] = lock
    plan.rooms[lock] = dict(kind="hall", dept="solar", label="", public=False, colour=(212, 178, 92))
    plan.doors[f(0, 5)] = "external"
    plan.doors[f(0, 7)] = "external"
    plan.doors[f(0, 1)] = "maint"
    for o in (8, 9):
        plan.solar[f(0, o)] = "cable"
    for (s_, o), kind in SOLAR_FIELD.items():
        plan.solar[f(s_, SOLAR_LEAD + o)] = kind
    pts = [f(s_, SOLAR_LEAD + o) for (s_, o) in SOLAR_FIELD]
    xs, ys = [t[0] for t in pts], [t[1] for t in pts]
    plan.solars.append(((min(xs), min(ys), max(xs), max(ys)), label))
    for o in range(1, SOLAR_TOTAL + 2):
        for s_ in range(-SOLAR_W - 3, SOLAR_W + 4):
            keep_out.add(f(s_, o))


def lay_end(plan, by, strips, seed, what, base, out, perp, hw):
    """What ends a hall at the hull: arrivals or escape (laid as departments), the AI satellite, or an EVA lock."""
    if what in ("arrivals", "escape"):
        name = what
        if name not in by:
            return
        d = by[name]
        for r in d.rooms:
            r.front = tuple("dept" if k == "ring" else k for k in r.front)
        w = 15 if name == "arrivals" else 19
        loc = lay_dept(d, w, seed)
        s0 = loc.spine[0]

        def f(u, v, base=base, out=out, perp=perp, s0=s0):
            return _add(base, _vec(out, v), _vec(perp, u - s0))
        plan.problems += ["%s: %s" % (name, x) for x in loc.broken]
        for rect, rid, meta in loc.rects:
            meta = dict(meta)
            meta.setdefault("label", "")
            p0, p1 = f(rect[0], rect[1]), f(rect[2], rect[3])
            plan.add_rect((min(p0[0], p1[0]), min(p0[1], p1[1]), max(p0[0], p1[0]), max(p0[1], p1[1])), rid,
                          dept=name, colour=d.colour, **meta)
        strips.append((f, name, 0, w, loc))
    elif what == "sat":
        satellite(plan, _add(base, _vec(perp, hw // 2 - 1)), out, perp)
    elif what == "eva":
        # EVA: a short lock out of the hall's end
        mid = _add(base, _vec(perp, hw // 2))
        plan.doors[mid] = "dock"
        plan.docks.append((mid, out, "EVA", (3, 2)))


# room an arm-end needs past the hall's end: (across from -a to +b, out), in the end's own frame
END_ROOM = {"arrivals": (8, 10, 30), "escape": (10, 12, 46), "sat": (6, 6, 27), "eva": (2, 4, 5)}


def _lane(start, out, perp, n, hw):
    return [_add(start, _vec(out, k), _vec(perp, j)) for k in range(n) for j in range(hw)]


def arm_tail(plan, start, out, perp, what, keep_out, rnd):
    """The arm past the departments: straight on, a dogleg, or an L into open space, 2-4 wide, then whatever ends it.
    Tried in a random order; the first that clears everything built (and the solar fields) is laid.
    -> (base, out, perp, width) for the end."""
    shapes = ["straight", "jog", "jog", "ell", "ell"]
    rnd.shuffle(shapes)
    # last resort: straight on, further each time, until the end is clear of everything
    shapes += ["long%d" % k for k in range(4, 44, 4)]
    for shape in shapes:
        hw = rnd.choice((2, 3, 3, 4)) if shape != "straight" else 3
        tiles = []
        st, o, pp = start, out, perp
        if shape == "jog":
            sign = rnd.choice((1, -1))
            for L, sg in ((rnd.randint(1, 4), sign), (rnd.randint(hw + 2, hw + 5), 1)):
                tiles += _lane(st, o, pp, L + hw, hw)
                st = _add(st, _vec(o, L), _vec(pp, hw)) if sg > 0 else _add(st, _vec(o, L), _vec(pp, -1))
                o, pp = _vec(pp, sg), o
            n = rnd.randint(2, 5)
            tiles += _lane(st, o, pp, n, hw)
            st = _add(st, _vec(o, n))
        elif shape == "ell":
            sign = rnd.choice((1, -1))
            L = rnd.randint(1, 5)
            tiles += _lane(st, o, pp, L + hw, hw)
            st = _add(st, _vec(o, L), _vec(pp, hw)) if sign > 0 else _add(st, _vec(o, L), _vec(pp, -1))
            o, pp = _vec(pp, sign), o
            n = rnd.randint(4, 10) if what != "eva" else rnd.randint(2, 5)
            tiles += _lane(st, o, pp, n, hw)
            st = _add(st, _vec(o, n))
        else:
            n = rnd.randint(0, 3) if shape == "straight" else int(shape[4:])
            tiles += _lane(st, o, pp, n, hw)
            st = _add(st, _vec(o, n))
        # the end's room, in its frame (across pp from the lane's first tile, out o)
        ea, eb, eo = END_ROOM[what]
        room = [_add(st, _vec(o, k), _vec(pp, j)) for k in range(eo) for j in range(-ea, hw + eb)]
        clear = set()
        for t in tiles[hw * 2:] + room:
            for dx in (-2, -1, 0, 1, 2):
                for dy in (-2, -1, 0, 1, 2):
                    clear.add((t[0] + dx, t[1] + dy))
        own = set(tiles)
        if any((t in plan.floor and plan.floor[t] != "ring" and t not in own) or
               t in plan.walls or t in keep_out for t in clear):
            continue
        for t in tiles:
            plan.floor.setdefault(t, "ring")
        return st, o, pp, hw
    return start, out, perp, 3


def satellite(plan, base, out, perp):
    """A secure tunnel out of the arm's end, then the satellite: a hall round the AI core, tcomms beside it."""
    mid = _add(base, _vec(perp, 1))
    plan.doors[mid] = "secure"
    p = mid
    for k in range(1, 7):
        p = _add(mid, _vec(out, k))
        plan.floor[p] = "sat_tunnel"
    plan.rooms["sat_tunnel"] = dict(kind="hall", dept="ai", label="", public=False, secure=True, colour=P.C["ai"])
    # the satellite: an 11x11 hall ring, its near side centred on the tunnel
    c0 = _add(p, out)
    pts = []
    for v in range(11):
        for u in range(-5, 6):
            pts.append(((u, v), _add(c0, _vec(out, v), _vec(perp, u))))
    for (u, v), t in pts:
        if u in (-5, 5) or v in (0, 10):
            plan.floor[t] = "sat_hall"
    plan.rooms["sat_hall"] = dict(kind="hall", dept="ai", label="", public=False, secure=True, colour=P.C["ai"])
    core = [t for (u, v), t in pts if -3 <= u <= 3 and 2 <= v <= 8]
    xs, ys = [t[0] for t in core], [t[1] for t in core]
    plan.add_rect((min(xs), min(ys), max(xs), max(ys)), "ai_core", kind="room", dept="ai", label="AI", secure=True,
                  colour=P.C["ai"])
    # tcomms beyond the ring's far side
    far = []
    for v in range(12, 19):
        for u in range(-5, 6):
            far.append(((u, v), _add(c0, _vec(out, v), _vec(perp, u))))
    a = [t for (u, v), t in far if u <= -1]
    bq = [t for (u, v), t in far if u >= 1]
    for ts, rid, lab, sec in ((a, "tcomms", "tcomms", True), (bq, "tc_control", "tc ctrl", False)):
        xs, ys = [t[0] for t in ts], [t[1] for t in ts]
        plan.add_rect((min(xs), min(ys), max(xs), max(ys)), rid, kind="room", dept="ai", label=lab, secure=sec,
                      colour=P.C["ai"])
    plan.sat = True


def lay_halves(plan, by, core, rect, seed):
    """Command and Service either side of one cross hall across the core's long side."""
    rnd = random.Random("halves|%s" % seed)
    X0, Y0, X1, Y1 = rect
    W, H = X1 - X0 + 1, Y1 - Y0 + 1
    names = list(core)
    rnd.shuffle(names)
    area = {n: footprint(by[n]) for n in names}
    tot = float(sum(area.values()))
    halves = {}
    if W >= H:
        cx = X0 + int(round((W - HALL) * area[names[0]] / tot))
        plan.add_rect((cx, Y0 - 1, cx + HALL - 1, Y1 + 1), "ring", kind="hall", public=True, label="", dept="hall")
        halves[names[0]] = (X0, Y0, cx - 2, Y1)
        if len(names) > 1:
            halves[names[1]] = (cx + HALL + 1, Y0, X1, Y1)
    else:
        cy = Y1 - int(round((H - HALL) * area[names[0]] / tot)) - HALL + 1
        plan.add_rect((X0 - 1, cy, X1 + 1, cy + HALL - 1), "ring", kind="hall", public=True, label="", dept="hall")
        halves[names[0]] = (X0, cy + HALL + 1, X1, Y1)
        if len(names) > 1:
            halves[names[1]] = (X0, Y0, X1, cy - 2)
    for name, (qx0, qy0, qx1, qy1) in halves.items():
        d = by[name]
        rooms = d.rooms
        groups = _groups(rooms)
        best = None
        for pick in itertools.product((0, 1), repeat=len(groups)):
            s = [[], []]
            for g, k in zip(groups, pick):
                s[k] += g
            if len(s[0]) > 5 or len(s[1]) > 5 or (len(rooms) > 5 and (not s[0] or not s[1])):
                continue
            if len(rooms) <= 5 and s[1]:
                continue
            c = abs(sum(r.area for r in s[0]) - sum(r.area for r in s[1])) + 30 * rnd.random()
            if best is None or c < best[0]:
                best = (c, s)
        s = best[1]
        ml = rnd.choice((1, 2))
        if not s[1]:
            blocks = [((qx0, qy0, qx1, qy1), s[0])]
        else:
            share = sum(r.area for r in s[0]) / float(sum(r.area for r in rooms))
            if qx1 - qx0 >= qy1 - qy0:
                cut = qx0 + int(round((qx1 - qx0 - 1 - ml - 1) * share))
                blocks = [((qx0, qy0, cut, qy1), s[0]), ((cut + 3 + ml, qy0, qx1, qy1), s[1])]
                lane = (cut + 2, qy0, cut + 1 + ml, qy1)
            else:
                cut = qy1 - int(round((qy1 - qy0 - 1 - ml - 1) * share))
                blocks = [((qx0, cut, qx1, qy1), s[0]), ((qx0, qy0, qx1, cut - 3 - ml), s[1])]
                lane = (qx0, cut - 1 - ml, qx1, cut - 2)
            for x in range(lane[0], lane[2] + 1):
                for y in range(lane[1], lane[3] + 1):
                    plan.floor[(x, y)] = "maint"
            plan.rooms["maint"] = dict(kind="maint", dept="maint", label="", public=False)
        for i, (br, rs) in enumerate(blocks):
            fr = {}
            bx0, by0, bx1, by1 = br
            for side, lo, hi in (("n", bx0, bx1), ("s", bx0, bx1), ("e", by0, by1), ("w", by0, by1)):
                if {"n": by1 == qy1, "s": by0 == qy0, "e": bx1 == qx1, "w": bx0 == qx0}[side]:
                    fr[side] = ("hall", lo, hi)
            blk = solve.Block("%s%d" % (name[:3], i), br, fr)
            fronts = {r.id: tuple(sorted({"hall" if k in ("ring", "dept") else k for k in r.front})) for r in rs}
            wants = [solve.Want(r.id, r.area, min=r.min, front=fronts[r.id], near=r.near) for r in rs]
            links = [(r.id, k) for r in rs for k in r.links]
            c, tree, placed, broken = solve.solve_block(blk, wants, links, seed="%s.%s" % (seed, name), fill=True)
            plan.problems += ["%s: %s" % (name, x) for x in broken]
            for rid, rr in placed.items():
                r = next(x for x in rs if x.id == rid)
                plan.add_rect(rr, rid, kind="room", dept=name, colour=d.colour, label=r.label, public=r.public,
                              secure=r.secure, front=fronts[rid], links=r.links, maint=r.maint)


# glazing a run of hull can take: (name, weight) by what is behind it
GLAZE = {"hall": (("bays", 40), ("full", 12), ("sparse", 20), ("none", 28)),
         "show": (("full", 35), ("bays", 40), ("sparse", 10), ("none", 15)),
         "staff": (("none", 45), ("bays", 25), ("sparse", 20), ("full", 10))}
SHOW = {"bar", "library", "chapel", "garden", "hydro", "departures", "arr_lounge", "bridge", "gym"}


def windows(plan, seed):
    """Glass on straight runs of hull in front of halls and rooms that are not secure or maint. Each run (a long hall
    run in pieces of 6-16) takes its own pattern: full glass, bays of 2-4 panes, single panes, or plain wall."""
    rnd = random.Random("windows|%s" % seed)
    cand = {}
    for q in plan.hull:
        if q in plan.doors or q in plan.rwall:
            continue
        for dx, dy in DIRS:
            r = plan.floor.get((q[0] + dx, q[1] + dy))
            back = (q[0] - dx, q[1] - dy)
            if not r or back in plan.floor or back in plan.walls:
                continue
            m = plan.rooms.get(r, {})
            if m.get("kind") == "maint" or m.get("secure") or m.get("dept") in ("maint",):
                continue
            # a straight run: the walls either side along the hull are walls too
            side = [(q[0] + dy, q[1] + dx), (q[0] - dy, q[1] - dx)]
            if not all(t in plan.walls for t in side):
                continue
            if any(plan.floor.get((t[0] + dx, t[1] + dy)) != r for t in side):
                continue
            cand.setdefault((r, dx, dy), set()).add(q)
    for (r, dx, dy), ts in sorted(cand.items(), key=lambda kv: (str(kv[0][0]), kv[0][1], kv[0][2])):
        m = plan.rooms.get(r, {})
        kind = "hall" if m.get("kind") == "hall" else "show" if (r in SHOW or m.get("public")) else "staff"
        # contiguous runs along the wall
        along = (abs(dy), abs(dx))
        order = sorted(ts, key=lambda t: (t[0] * along[1] + t[1] * along[0], t[0] * along[0] + t[1] * along[1]))
        runs, cur = [], []
        for t in order:
            if cur and (t[0] - cur[-1][0], t[1] - cur[-1][1]) != along:
                runs.append(cur)
                cur = []
            cur.append(t)
        if cur:
            runs.append(cur)
        for run in runs:
            pieces = [run]
            if kind == "hall" and len(run) > 16:
                pieces, k = [], 0
                while k < len(run):
                    n = rnd.randint(6, 16)
                    pieces.append(run[k:k + n])
                    k += n
            for piece in pieces:
                names, weights = zip(*GLAZE[kind])
                pat = rnd.choices(names, weights)[0]
                if pat == "full":
                    plan.glass.update(piece)
                elif pat == "bays":
                    k = rnd.randint(0, 2)
                    while k < len(piece):
                        n = rnd.randint(2, 4)
                        plan.glass.update(piece[k:k + n])
                        k += n + rnd.randint(2, 4)
                elif pat == "sparse":
                    step = rnd.randint(3, 5)
                    plan.glass.update(piece[rnd.randint(0, step - 1)::step])


COMPASS = {"N": (0, 1), "E": (1, 0), "S": (0, -1), "W": (-1, 0)}


def orient(plan, rnd):
    """Turn the whole station a quarter turn 0-3 times and maybe mirror it, so no two seeds face the same way."""
    k = rnd.randrange(8)
    if not k:
        return

    def m(t):
        x, y = t
        if k & 4:
            x = -x
        for _ in range(k & 3):
            x, y = y, -x
        return (x, y)
    plan.floor = {m(t): r for t, r in plan.floor.items()}
    plan.doors = {m(t): d for t, d in plan.doors.items()}
    for name in ("glass", "walls", "hull", "rwall"):
        setattr(plan, name, {m(t) for t in getattr(plan, name)})
    plan.docks = [(m(t), m(side),) + tuple(rest) for t, side, *rest in plan.docks]
    sol = []
    for rect, lab in plan.solars:
        a, b = m(rect[:2]), m(rect[2:])
        sol.append(((min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1])), lab))
    plan.solars = sol
    plan.solar = {m(t): k_ for t, k_ in plan.solar.items()}
    back = {v: c for c, v in COMPASS.items()}

    def turn(word):
        return "".join(sorted((back[m(COMPASS[c])] for c in word), key=lambda c: c not in "NS"))

    def fix(note):
        note = re.sub(r"\b([NESW]{1,2}):", lambda g: turn(g.group(1)) + ":", note)
        return re.sub(r"arm ([NESW])\b", lambda g: "arm " + turn(g.group(1)), note)
    plan.notes = [fix(n) if n.startswith("quadrants ") else n for n in plan.notes]
    plan.notes.append("turned %d, %s" % (90 * (k & 3), "mirrored" if k & 4 else "not mirrored"))
