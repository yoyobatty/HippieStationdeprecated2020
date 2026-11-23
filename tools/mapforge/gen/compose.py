"""Departments built bottom-up (studies/full_generator_plan.md section 7, "Next: departments built bottom-up"): the
room stage that replaces top-down packing (gen/rooms.py cut rooms into pre-made department blocks, then patched the
leftovers).

    import compose as CP
    m, L = CP.layout(prog, params, sub, P, radial, room_size, rband)   # a furnished map, like blocks.layout + furnish
    CP.finish(L, m, log)                                               # atmos-engineering door, second doors

1. A department is a structure. Its stock-room copies (gen/stamps.py, forge/room_stamp.py) are attached one at a time
   to a corridor that grows with them: a stem from the hall front, branches across its top, the stem going on past
   them. Every room is placed with a door cell of its own wall on the corridor's wall (the copy's own door where one
   lands there). The corridor is then cut back to the last door on each run. The footprint is the union of the rooms,
   the corridor and its walls: nothing left over, every room reached from the hall front.
2. The station is the root. Each department is composed in its own frame (x along its hall front, y away from it)
   and placed at its slot of the existing skeleton and slot search (blocks.Layout: core, spokes, assign()), turned
   to face its hall: spoke sides, loop corners, past a spoke tip (the AI). A second-row department (behind the first
   one on a spoke side) gets a side hall off the spoke along the first one's end, and faces it.
3. The space between departments is filled by a multi-source search from the halls and department edges: a free
   cell within 1-3 tiles (the maint width mix) of two different departments, or of a department and a hall, is
   maint. Each maint piece is then joined to its nearest hall by the shortest path through free space. Short of the
   program's maint budget, runs grow round department backs in order of distance; farther out stays space.
4. Second doors: a room with one way in is measured as parse.SemanticMap does (regions and their links), and rooms are
   given a door to a neighbouring room of their department, the hall or maint until the share of rooms with one way
   in is the human median (space_sizes.py one_door, band 0.335-0.448).
"""
import math
import os
import random
import sys
from collections import deque

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, HERE)
import blocks as BL  # noqa: E402
import rooms as RM  # noqa: E402
import stamps as STP  # noqa: E402
from forge import dmm, room_stamp  # noqa: E402

N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
N8 = [(dx, dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy]
HALLISH = ("hall", "arrivals", "escape")
DEPTS = ("command",) + BL.RING
ONE_DOOR = 0.39          # the human median share of rooms with one way in (space_sizes.py; band 0.335-0.448)
DMAX = 60


# ------------------------------------------------------------------------------------------------ frames
def kt_of(a, n):
    """The orientation k (room_stamp.xform) taking local x to a and local y to n."""
    for k in range(8):
        if room_stamp.xform(k, 1, 0) == tuple(a) and room_stamp.xform(k, 0, 1) == tuple(n):
            return k
    raise ValueError((a, n))


def kcompose(t, k):
    """k2 with xform(k2, p) == xform(t, xform(k, p))."""
    for k2 in range(8):
        if all(room_stamp.xform(k2, *p) == room_stamp.xform(t, *room_stamp.xform(k, *p)) for p in ((1, 0), (0, 1))):
            return k2
    raise ValueError((t, k))


class Frame:
    """local (x, y) -> station B + x a + y n."""

    def __init__(self, B, a, n):
        self.B, self.a, self.n = tuple(B), tuple(a), tuple(n)
        self.k = kt_of(a, n)

    def __call__(self, c):
        return (self.B[0] + c[0] * self.a[0] + c[1] * self.n[0], self.B[1] + c[0] * self.a[1] + c[1] * self.n[1])


# ------------------------------------------------------------------------------------------------ composition
_FP = {}


def footprints(src):
    """Per orientation: (k, F, R, inner, fp offset, {u: [ring cells r with r+u room floor, r-u outside]}, doors)."""
    key = (src.map, src.area)
    if key in _FP:
        return _FP[key]
    out = []
    for k, F, R, D, inner, off in RM._footprints(src):
        F, R = set(F), set(R)
        opts = {}
        for r in R - inner:
            for u in N4:
                a = (r[0] + u[0], r[1] + u[1])
                b = (r[0] - u[0], r[1] - u[1])
                if a not in F or b in F or b in R:
                    continue
                p1 = (r[0] + u[1], r[1] + u[0])
                p2 = (r[0] - u[1], r[1] - u[0])
                if p1 in R and p2 in R and p1 not in F and p2 not in F:
                    opts.setdefault(u, []).append(r)
        for u in opts:
            rs = sorted(opts[u])
            ds = [r for r in rs if r in D]
            rest = [r for r in rs if r not in D]
            step = max(1, len(rest) // 5)
            opts[u] = ds + rest[::step][:6]
        out.append((k, F, R, inner, off, opts, D))
    _FP[key] = out
    return out


_GFP = {}


def grid_fps(src, W):
    """footprints() with each orientation's floor and wall as offsets into a grid W wide, and their wall's box."""
    key = (src.map, src.area, W)
    if key not in _GFP:
        out = []
        for k, F, R, inner, off, opts, D in footprints(src):
            Fo = [p[1] * W + p[0] for p in F]
            Ro = [p[1] * W + p[0] for p in R]
            bb = (min(p[0] for p in R), min(p[1] for p in R), max(p[0] for p in R), max(p[1] for p in R))
            out.append((k, F, R, inner, off, opts, D, Fo, Ro, bb))
        _GFP[key] = out
    return _GFP[key]


class Comp:
    """A department being composed in its own frame: x in [0, W), 0 <= y <= Dmax, y = 0 its hall front wall. Cells
    live in a bytearray grid: 0 free, 1 room floor, 2 room wall, 3 corridor floor, 4 corridor wall (planned)."""

    def __init__(self, dept, W, Dmax, cw, r):
        self.dept, self.W, self.Dmax, self.r, self.cw = dept, W, Dmax, r, cw
        self.H = Dmax + 1
        self.occ = bytearray(W * self.H)
        self.floor, self.ring, self.corr = set(), set(), set()
        self.seg_of = {}            # corridor cell -> segment index
        self.segs = []
        self.rooms = []
        self.doors = set()
        self.front = set()
        self.dist = {}
        self.wall_list = []
        # the corridor's area is a room to room_stats: no bigger than 0.85 of its type's biggest look-map room (the
        # gate's oversized check: command's corridor ran to 118 against 74, security's to 259 against 207)
        self.cap = int(RM.look_max(RM.CORRIDOR_AREA.get(dept, "")) * 0.85) if dept in RM.CORRIDOR_AREA else 10 ** 6
        self.maxd = 10 ** 6

    def inb(self, c):
        return 0 <= c[0] < self.W and 0 <= c[1] <= self.Dmax

    def _cells(self, axis, d, start, cross, n):
        out = []
        for t in range(n):
            al = start + d * t
            for cr in range(cross[0], cross[1] + 1):
                out.append((cr, al) if axis == "y" else (al, cr))
        return out

    def _seg(self, axis, d, start, cross, n, parent, jt):
        if n <= 0:
            return False
        cells = self._cells(axis, d, start, cross, n)
        if not all(1 <= c[0] <= self.W - 2 and 1 <= c[1] <= self.Dmax - 1 for c in cells):
            return False
        i = len(self.segs)
        self.segs.append(dict(axis=axis, d=d, start=start, cross=cross, n=n, parent=parent, jt=jt))
        for c in cells:
            self.corr.add(c)
            self.seg_of.setdefault(c, i)
        return True

    def plan(self, sx, stem_n, branches):
        """The whole corridor, before any room: a stem from the front (stem_n long) and branches across it at the
        rows `branches`, both ways to the frame's edge. Rooms may not cover it; trim() cuts back what no door uses."""
        cw = self.cw
        self._seg("y", 1, 1, (sx, sx + cw - 1), stem_n, None, None)
        for yb in branches:
            jt = yb + cw - 1 - 1
            if jt >= stem_n:
                continue
            rows = (yb, yb + cw - 1)
            self._seg("x", -1, sx - 1, rows, sx - 1, 0, jt)
            self._seg("x", 1, sx + cw, rows, self.W - 2 - (sx + cw) + 1, 0, jt)
        mid = [sx + cw // 2] if cw % 2 else [sx + cw // 2 - 1, sx + cw // 2]
        self.front = {(x, 0) for x in mid}
        W = self.W
        for c in self.corr:
            self.occ[c[1] * W + c[0]] = 3
        for c in self.corr:
            for dx, dy in N8:
                q = (c[0] + dx, c[1] + dy)
                if self.inb(q) and self.occ[q[1] * W + q[0]] == 0:
                    self.occ[q[1] * W + q[0]] = 4
        # corridor distance from the front, for "nearest the front first"
        q = deque()
        for c in self.corr:
            if c[1] == 1 and sx <= c[0] < sx + cw:
                self.dist[c] = 0
                q.append(c)
        while q:
            c = q.popleft()
            for dx, dy in N4:
                n = (c[0] + dx, c[1] + dy)
                if n in self.corr and n not in self.dist:
                    self.dist[n] = self.dist[c] + 1
                    q.append(n)
        for c in self.corr:
            for u in N4:
                w = (c[0] + u[0], c[1] + u[1])
                if self.inb(w) and w[1] >= 1 and self.occ[w[1] * W + w[0]] == 4:
                    self.wall_list.append((self.dist.get(c, 999), w, u))
        self.wall_list.sort()
        n = 0
        for dd in sorted(self.dist.values()):
            n += 1
            if n > self.cap:
                self.maxd = dd - 2
                break

    def near_door(self, w):
        return any((w[0] + dx, w[1] + dy) in self.doors or (w[0] + dx, w[1] + dy) in self.front for dx, dy in N8)

    def attach(self, ents, pub, avoid=None):
        """The best placement of one of the copies `ents` (tried in order) with a door cell of its own wall on the
        corridor's wall: among the corridor walls nearest the front that take it, the tightest fit."""
        W, H, occ = self.W, self.H, self.occ
        walls = [(dd, w, u) for dd, w, u in self.wall_list if dd <= self.maxd and occ[w[1] * W + w[0]] == 4
                 and not self.near_door(w)]
        if not walls:
            return None
        for e in ents[:3]:
            try:
                src = RM.source(e)
            except Exception:           # noqa: BLE001 - a copy that won't load is skipped
                continue
            fps = grid_fps(src, W)
            best = None
            for dd, w, u in walls:
                if best is not None and dd > best[1] + 3:
                    break
                for (k, F, R, inner, off, opts, D, Fo, Ro, bb) in fps:
                    for rr in opts.get(u, ()):
                        ox, oy = w[0] - rr[0], w[1] - rr[1]
                        if ox + bb[0] < 0 or ox + bb[2] >= W or oy + bb[1] < 0 or oy + bb[3] >= H:
                            continue
                        base = oy * W + ox
                        ok = True
                        for f in Fo:
                            if occ[base + f]:
                                ok = False
                                break
                        if not ok:
                            continue
                        if avoid and any((p[0] + ox, p[1] + oy) in avoid for p in F):
                            continue
                        tight = 0
                        for f in Ro:
                            v = occ[base + f]
                            if v == 1 or v == 3:
                                ok = False
                                break
                            if v:
                                tight += 1
                        if not ok:
                            continue
                        edge = (ox + bb[0] == 0) + (ox + bb[2] == W - 1) + (oy + bb[1] == 0)
                        # the bay a room leaves behind it, between its back wall and the frame's edge (or the
                        # front): empty space inside the department's box, which the station's fill pays for
                        if u[0] > 0:
                            bay = W - 1 - (ox + bb[2])
                        elif u[0] < 0:
                            bay = ox + bb[0]
                        elif u[1] < 0:
                            bay = oy + bb[1]
                        else:
                            bay = 0
                        sc = tight / float(len(Ro)) + 0.05 * edge - BAY_W * bay - \
                            0.03 * dd * (1.5 if pub else 1.0) + (0.25 if rr in D else 0.0) + 0.01 * self.r.random()
                        if best is None or sc > best[0]:
                            best = (sc, dd, e, src, k, (ox, oy), off, F, R, inner, w)
            if best is not None:
                return best[2:]
        return None

    def put(self, got, area):
        e, src, k, o, off, F, R, inner, w = got
        W = self.W
        Fm = {(p[0] + o[0], p[1] + o[1]) for p in F}
        Rm = {(p[0] + o[0], p[1] + o[1]) for p in R}
        for c in Fm:
            self.occ[c[1] * W + c[0]] = 1
        for c in Rm:
            self.occ[c[1] * W + c[0]] = 2
        self.floor |= Fm
        self.ring |= Rm
        self.doors.add(w)
        self.rooms.append(dict(area=area, entry=e, src=src, k=k, A=o, off=off, F=Fm, R=Rm,
                               inner={(p[0] + o[0], p[1] + o[1]) for p in inner}, door=w))

    def trim(self):
        """Cut each corridor run back to its last door (or its last kept branch): no corridor is left over."""
        need = {}
        for d in self.doors | self.front:
            for u in N4:
                c = (d[0] + u[0], d[1] + u[1])
                if c in self.corr:
                    i = self.seg_of[c]
                    s = self.segs[i]
                    al = c[1] if s["axis"] == "y" else c[0]
                    t = (al - s["start"]) * s["d"]
                    need[i] = max(need.get(i, -1), t)
        keep = {}
        for i in range(len(self.segs) - 1, -1, -1):
            s = self.segs[i]
            t = need.get(i, -1)
            for j, c in keep.items():
                if self.segs[j]["parent"] == i and c > 0:
                    t = max(t, self.segs[j]["jt"])
            keep[i] = t + 1
        corr, seg_of = set(), {}
        for i, s in enumerate(self.segs):
            if keep[i] <= 0:
                continue
            s["n"] = keep[i]
            for c in self._cells(s["axis"], s["d"], s["start"], s["cross"], keep[i]):
                corr.add(c)
                seg_of.setdefault(c, i)
        self.corr, self.seg_of = corr, seg_of

    def footprint(self):
        cw = {(c[0] + dx, c[1] + dy) for c in self.corr for dx, dy in N8} - self.corr - self.floor
        cells = self.floor | self.ring | self.corr | cw | self.front
        # cells the footprint encloses (a closed pocket between rooms) become wall
        xs = [c[0] for c in cells]
        ys = [c[1] for c in cells]
        x0, x1, y0, y1 = min(xs) - 1, max(xs) + 1, min(ys) - 1, max(ys) + 1
        seen = set()
        st = [(x0, y0)]
        while st:
            a = st.pop()
            if a in seen or a in cells or not (x0 <= a[0] <= x1 and y0 <= a[1] <= y1):
                continue
            seen.add(a)
            st.extend((a[0] + dx, a[1] + dy) for dx, dy in N4)
        voids = {(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)} - seen - cells
        # a closed pocket beside a corridor wall opens into the corridor (an alcove); a pocket of 3 or fewer is
        # wall; a bigger one stays space (as wall it was solid filler: 59 3x3 wall tiles on crew 80 seed 4)
        keep = set()
        for comp in _comps(voids):
            opening = None
            for c in sorted(comp):
                for dx, dy in N4:
                    w = (c[0] + dx, c[1] + dy)
                    if w in cells and w not in self.ring and w not in self.corr and w not in self.front and                             w not in self.doors and any((w[0] + ex, w[1] + ey) in self.corr for ex, ey in N4):
                        opening = w
                        break
                if opening:
                    break
            if opening and len(self.corr) + len(comp) + 1 <= self.cap:
                self.corr |= comp | {opening}
                keep |= comp
            elif len(comp) <= 3:
                keep |= comp
        self.cells = cells | keep
        self.voids = voids
        self.wall = self.cells - self.floor - self.corr - self.doors - self.front


def room_items(dept, target, r):
    """The room program for a department (rooms.furnish's): the types half the families have, the rarer ones by
    their prevalence, then every type again smallest first. [(pass, area, wanted size)]"""
    types = RM.program_types()
    corr_area = RM.CORRIDOR_AREA.get(dept)
    want = []
    for fam, area, size in types.get(dept, []):
        if area == corr_area:
            continue
        p = fam / 32.0
        if p >= 0.5 or r.random() < p:
            want.append((1, area, size))
    second = sorted([t for t in types.get(dept, []) if t[1] != corr_area], key=lambda t: t[2])
    return want + [(2, a, s) for _, a, s in second]


CORR_SHARE = 0.18          # the corridor's share of a composed department's floor, for the room budget


def compose(dept, target, W, key, Dmax=DMAX, stem=None):
    """Compose department `dept` with about `target` floor tiles in a frame W wide and at most Dmax deep. stem: (lo,
    hi), the range for the stem's first column. Returns a Comp with footprint() done."""
    r = random.Random("compose|%s|%s" % (dept, key))
    W = max(W, MIN_W)
    cw = 3 if target >= 450 else 2
    lo, hi = stem if stem else (1, W - cw - 1)
    lo, hi = max(1, lo), min(W - cw - 1, hi)
    if hi < lo:
        lo = hi = max(1, min(W - cw - 1, (W - cw) // 2))
    mid = (W - cw) // 2
    sx = max(lo, min(hi, mid + r.randint(-max(1, W // 8), max(1, W // 8))))
    if dept == "atmos":
        C = Comp(dept, W, Dmax, cw, r)
        C.plan(sx, 1, ())
        return _atmos(C, target, r)
    # three stems (the seed's, at the low end, at the high end: one deep side for a big room); the most floor wins,
    # then the smallest footprint
    best = None
    for x in sorted({sx, lo, hi}, key=lambda v: (v != sx, v)):
        C = _compose_at(dept, target, W, Dmax, cw, x, random.Random("compose|%s|%s|%d" % (dept, key, x)))
        fl = len(C.floor) + len(C.corr)
        xs = [c[0] for c in C.cells]
        ys = [c[1] for c in C.cells]
        box = (max(xs) - min(xs) + 1) * (max(ys) - min(ys) + 1)
        # floor, less a share of the box it takes: a long one-sided department fills its box half as well (skel.fill)
        sc = (min(fl, target * 1.05) - BOX_W * box, -len(C.cells))
        if best is None or sc > best[0]:
            best = (sc, C)
    return best[1]


def _compose_at(dept, target, W, Dmax, cw, sx, r):
    C = Comp(dept, W, Dmax, cw, r)
    if Dmax < 30:
        # shallow (a loop corner): a short stem and one branch across at mid depth
        yb = max(4, (Dmax - cw) // 2)
        C.plan(sx, yb + cw - 1, (yb,))
    elif W >= COMB_W:
        y, bs = r.randint(8, 11), []
        while y + cw < Dmax - 4:
            bs.append(y)
            y += r.randint(16, 20)
        C.plan(sx, Dmax - 1, bs)
    else:
        C.plan(sx, Dmax - 1, ())
    lib = STP.library()
    budget = target * (1.0 - CORR_SHARE)
    target_n = RM.room_count(dept, target / 0.8)
    used = 0
    have = set()
    for pass_, area, size in room_items(dept, target, r):
        if area not in lib:
            continue
        if pass_ == 2 and (area in have or (used >= budget * 0.97 and len(C.rooms) >= target_n)):
            continue
        left = budget - used
        if pass_ == 2 and len(C.rooms) < target_n:
            left = max(left, 30)
        if left < 8:
            continue
        cap = RM.look_max(area)
        ents = [e for e in lib[area] if e["tiles"] <= max(left * 1.1, 10) and e["tiles"] <= cap]
        if not ents:
            continue
        want = min(size, left) if pass_ == 1 else min(e["tiles"] for e in ents)
        ents.sort(key=lambda e: RM._rank(e, want))
        got = C.attach(ents, any(x in area for x in RM.PUBLIC))
        if got is None:
            continue
        C.put(got, area)
        used += len(C.rooms[-1]["F"])
        have.add(area)
    _small_rooms(C, dept, target, lib)
    C.trim()
    C.footprint()
    C.chambers = []
    return C


BAY_W = 0.04        # score lost per cell of bay behind a room (see Comp.attach)
BOX_W = 0.2         # floor a stem variant gives up per cell of its bounding box (compose)
MIN_W = 17         # a stem with a room either side: about 7 cells each


def _small_rooms(C, dept, target, lib):
    """The gate checks each department's median room size (space_sizes.py room_size_<dept>). The program's big
    copies fill the floor budget first, and the median came out over the band on 4 of 5 trace seeds (service 49-68
    against 36). Small copies of the department's types (a second copy too, never within 3 tiles of one of its own
    type) go on while the median is over the band and the floor under 1.2x the target."""
    import gate as G
    band = G.bands()[0].get("space.room_size_" + dept)
    if not band or not C.rooms:
        return
    hi = band[1]
    types = sorted([t for t in RM.program_types().get(dept, []) if t[1] != RM.CORRIDOR_AREA.get(dept)],
                   key=lambda t: t[2])
    for _ in range(12):
        sizes = sorted(len(rm["F"]) for rm in C.rooms)
        if sizes[len(sizes) // 2] <= hi * 0.95 or sum(sizes) + len(C.corr) * 0.5 > 1.2 * target:
            return
        placed = False
        for fam, area, size in types:
            if area not in lib:
                continue
            ents = sorted([e for e in lib[area] if 6 <= e["tiles"] <= hi], key=lambda e: RM._rank(e, hi * 0.6))
            if not ents:
                continue
            near = {(c[0] + dx, c[1] + dy) for rm in C.rooms if rm["area"] == area for c in rm["F"]
                    for dx in range(-3, 4) for dy in range(-3, 4)}
            got = C.attach(ents, False, avoid=near)
            if got:
                C.put(got, area)
                placed = True
                break
        if not placed:
            return
COMB_W = 32         # wider than this, branches cross the stem every 16-20 rows


GASES = ("n2", "o2", "plasma", "co2", "air")


def _atmos(C, target, r):
    """Atmos as every stock atmos has it: one big main floor (its corridor area) and the gas chambers, 3x3 rooms of the
    gas's own engine floor against the back wall."""
    W = C.W
    n_ch = len(GASES)
    D = max(8, int(math.ceil((target - 9 * n_ch) / float(max(1, W - 2)))))
    C.corr = {(x, y) for x in range(1, W - 1) for y in range(1, D + 1)}
    C.seg_of = {c: 0 for c in C.corr}
    C.chambers = []
    # chambers along the back wall (ring bottom row = the main floor's back wall), 4 apart (shared walls)
    x = 0
    for gas in GASES:
        if x + 4 > W - 1:
            break
        F = {(x + 1 + i, D + 2 + j) for i in range(3) for j in range(3)}
        R = {(x + i, D + 1 + j) for i in range(5) for j in range(5)} - F
        C.chambers.append((gas, F, R))
        x += 4
    C.rooms = []
    cw = {(c[0] + dx, c[1] + dy) for c in C.corr for dx, dy in N8} - C.corr
    ch = set().union(*[F | R for _, F, R in C.chambers]) if C.chambers else set()
    C.cells = C.corr | cw | ch | C.front
    C.floor = set().union(*[F for _, F, _ in C.chambers]) if C.chambers else set()
    C.ring = set().union(*[R for _, _, R in C.chambers]) if C.chambers else set()
    C.voids = set()
    C.wall = C.cells - C.corr - C.floor - C.front
    return C


_CACHE = {}
# a second-row department on a side hall of its own: off. Measured 2026-11-22 (crew 80 seed 4): the side halls ran
# 50-64 tiles, the human arm is 19.5 at most (skel.arm_len), and spokes ran to 80 (skel.spoke_len, max 62)
SIDE_HALLS = False


def get(dept, target, W, salt, Dmax=DMAX, stem=None):
    """compose(), cached: the slot search places the same department many times."""
    tb = int(round(math.log(max(20.0, target)) / math.log(1.04)))
    key = (dept, tb, int(W), salt, Dmax, stem)
    if key not in _CACHE:
        if len(_CACHE) > 3000:
            _CACHE.clear()
        _CACHE[key] = compose(dept, 1.04 ** tb, int(W), "%s|%d|%d|%s|%s" % (salt, tb, W, Dmax, stem), Dmax, stem)
    return _CACHE[key]


DEPTH = 1.4         # a spoke department may run this many times its slot's depth before it is widened instead
DEPTH_CAP = 10 ** 6
ASPECT_LO, FILL_LO = 0.762, 0.234   # skel.aspect and skel.fill band floors (gen/gate.py --bands)
FLOOR_OF_OWN = 0.71  # station floor per claimed cell (walls are claimed too): 0.183 / 0.259 on crew 80 seed 4


def fit(dept, target, W, h, salt, stem=None):
    """A composition near its slot's depth h: at most DEPTH x h deep, widened 20% at a time while it holds under 90%
    of its floor. (Deeper before wider, 1.8 h, was tried on crew 80 seed 4: the spoke walk passed but radial places,
    maint and fill failed, 6 checks against 2.)"""
    Dm = max(18, min(DEPTH_CAP, int(round(h * DEPTH))))
    best = None
    for _ in range(5):
        C = get(dept, target, W, salt, Dmax=Dm, stem=stem)
        fl = len(C.floor) + len(C.corr)
        if best is not None and fl <= best[0] * 1.03:
            break                   # wider gains nothing: the department's room types ran out, not its room
        if best is None or fl > best[0]:
            best = (fl, C)
        if fl >= 0.9 * target:
            break
        W = int(W * 1.2) + 1
    return best[1]


# ------------------------------------------------------------------------------------------------ the station
class BU(BL.Layout):
    """blocks.Layout with composed departments: the skeleton, gaps and slot search are blocks.Layout's."""

    def __init__(self, *a, **k):
        BL.Layout.__init__(self, *a, **k)
        self.placed = {}        # dept -> (Comp, Frame)
        self.salt = "%s|%d|%d" % (self.p["shape"], self.p["crew"], self.p["seed"])

    def target(self, d):
        return self.p["budgets"][d] * self.q["qmul"].get(d, 1.0)

    # ---------------------------------------------------------------- S1: the core is command, composed
    def core(self):
        b = self.p["budgets"]
        area = b["command"] / BL.FLOOR_RATIO * self.q["qmul"].get("command", 1.0)
        asp = self.r.uniform(1.0, 1.5)
        cw = max(9, int(round(math.sqrt(area * asp))))
        C = get("command", self.target("command"), cw, self.salt)
        xs = [c[0] for c in C.cells]
        ys = [c[1] for c in C.cells]
        w, h = max(xs) + 1, max(ys) + 1
        x0, y0 = -(w // 2), -(h // 2)
        fr = Frame((x0, y0), (1, 0), (0, 1))
        self.core_box = (x0, y0, x0 + w - 1, y0 + h - 1)
        box = {(x, y) for x in range(x0, x0 + w) for y in range(y0, y0 + h)}
        cells = {fr(c) for c in C.cells}
        for c in box:
            self.own[c] = "command" if c in cells else "_void"
        wl = 3
        self.loop_w = wl
        for x in range(x0 - wl, x0 + w + wl):
            for y in range(y0 - wl, y0 + h + wl):
                if (x, y) not in self.own:
                    self.own[(x, y)] = "hall"
                    self.harea[(x, y)] = BL.HALL_AREA["loop"]
        for c in box - cells:
            del self.own[c]
        self.loop_box = (x0 - wl, y0 - wl, x0 + w + wl - 1, y0 + h + wl - 1)
        self.placed["command"] = (C, fr)

    def _strip(self, start, d, length, w, area, owner="hall"):
        """blocks.Layout._strip, with an even width's cells on the same side for either direction: a spoke covers
        exactly its lo..hi (blocks.Layout's N and W spokes came out one cell over, so a department composed against
        lo-1 fronted onto nothing)."""
        dx, dy = d
        px, py = -dy, dx
        ks = list(range(-(w // 2), w - w // 2))
        if px + py < 0:
            ks = [-k for k in ks]
        sx, sy = start
        for t in range(length):
            for k in ks:
                c = (sx + dx * t + px * k, sy + dy * t + py * k)
                if c not in self.own:
                    self.own[c] = owner
                    self.harea[c] = area
        return (sx + dx * (length - 1), sy + dy * (length - 1))

    def _test_site(self):
        """The test range at blocks.Layout's distance (outpost x the farthest floor from the centroid), in the
        direction of 32 that grows the station's box least, science's side preferred a little; the box stays near
        square (human aspect 0.76-0.96). blocks.Layout took the compass point nearest science: with composed
        departments that grew the box 1.6-2x on 2 of 4 seeds, and skel.fill (floor / box) fell to 0.15-0.2."""
        cells = list(self.own)
        cx = sum(c[0] for c in cells) / float(len(cells))
        cy = sum(c[1] for c in cells) / float(len(cells))
        far = max(math.hypot(c[0] - cx, c[1] - cy) for c in cells)
        sci = [c for c, o in self.own.items() if o == "science"] or cells
        sx = sum(c[0] for c in sci) / float(len(sci)) - cx
        sy = sum(c[1] for c in sci) / float(len(sci)) - cy
        sn = math.hypot(sx, sy) or 1.0
        dist = far * self.q["outpost"] - BL.TEST_SIDE / 2.0
        xs, ys = [c[0] for c in cells], [c[1] for c in cells]
        x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
        area0 = float((x1 - x0 + 1) * (y1 - y0 + 1))
        half = BL.TEST_SIDE // 2 + 1
        best = None
        for k in range(32):
            a = k * math.pi / 16
            ux, uy = math.cos(a), math.sin(a)
            px, py = cx + ux * dist, cy + uy * dist
            w = max(x1, px + half) - min(x0, px - half) + 1
            h = max(y1, py + half) - min(y0, py - half) + 1
            asp = min(w, h) / max(w, h)
            fill = FLOOR_OF_OWN * len(cells) / float(w * h)
            # out of the gate's bands, in band widths: skel.aspect 0.762.., skel.fill 0.234.. (the gate's numbers)
            miss = max(0.0, ASPECT_LO + 0.01 - asp) / 0.2 + max(0.0, FILL_LO + 0.01 - fill) / 0.12
            sc = miss + 0.05 * (w * h / area0) + 0.03 * (1.0 - (ux * sx + uy * sy) / sn)
            if best is None or sc < best[0]:
                best = (sc, px, py)
        ox, oy = int(round(best[1])), int(round(best[2]))
        for x in range(ox - BL.TEST_SIDE // 2 - 1, ox + BL.TEST_SIDE // 2 + 2):
            for y in range(oy - BL.TEST_SIDE // 2 - 1, oy + BL.TEST_SIDE // 2 + 2):
                if (x, y) not in self.own:
                    self.own[(x, y)] = "testsite"
        self.info["test_site"] = (ox, oy)

    # ---------------------------------------------------------------- S2: placement
    def _fits(self, cells, d):
        return all(self._free(c, d) for c in cells)

    def _put(self, d, C, fr):
        cells = [fr(c) for c in C.cells]
        self._claim(cells, d)
        self.placed[d] = (C, fr)
        return cells

    def place(self):
        self.placed = {k: v for k, v in self.placed.items() if k == "command"}
        b = self.p["budgets"]
        quota = {d: b[d] / BL.FLOOR_RATIO * 1.06 * self.q["qmul"].get(d, 1.0) for d in BL.RING}
        by_side = {e["side"]: e for e in self.spoke_list}
        lx0, ly0, lx1, ly1 = self.loop_box
        inner_q = max([quota[d] for d in self.cmap.values() if d] or [0])
        deep = {}
        for cn in ("NE", "NW", "SE", "SW"):
            vs = by_side.get("N" if cn[0] == "N" else "S")
            sx = 1 if cn[1] == "E" else -1
            x0 = (vs["hi"] + 1 if sx > 0 else vs["lo"] - 1) if vs else (lx0 + lx1) // 2
            width = abs((lx1 if sx > 0 else lx0) - x0) + 1 + 10
            deep[cn] = int(min(22, max(12, inner_q / float(width) * 1.1))) + 2
        self._deep = deep
        self.side_halls = []
        for (i, k), ds in self.smap.items():
            e = self.spoke_list[i]
            cn = BL.QUAD[(e["side"], k)]
            a = (deep[cn] if e["side"] in ("N", "S") else 13) if self.cmap.get(cn) else 1
            prev = None
            for j, d in enumerate(ds):
                asp = self.r.uniform(0.45, 1.1)
                h = max(8, min(36, int(round(math.sqrt(quota[d] / asp) * self.q["depth"]))))
                ln = max(9, int(round(quota[d] / h)))
                if d == "atmos":
                    ln = max(ln, 22)
                nxt = ds[j + 1] if j + 1 < len(ds) else None
                if SIDE_HALLS and prev and a + ln > BL.STACK_WALK:
                    got = self._second_row(e, k, prev, d, ln)
                    if got:
                        a = max(a, got + self._gap_of[d].get(nxt, 1) if nxt else got + 1)
                        prev = None
                        continue
                C = fit(d, self.target(d), ln, h, self.salt)
                cross = (lambda kk: (e["hi"] + 1) if kk > 0 else (e["lo"] - 1))(k)
                nvec = ((k, 0) if e["side"] in ("N", "S") else (0, k))
                placed = False
                while a < self.R * 1.3:
                    fr = Frame(self._spoke_cell(e, a, cross), e["d"], nvec)
                    if self._fits([fr(c) for c in C.cells], d):
                        placed = True
                        break
                    a += 1
                if not placed:
                    continue
                self._put(d, C, fr)
                ext = max(c[0] for c in C.cells) + 1
                dep = max(c[1] for c in C.cells) + 1
                e["depts"][k].append((d, a, a + ext))
                prev = (a, ext, dep, d, nvec, cross)
                a += ext + (self._gap_of[d].get(nxt, 0) if nxt else 1)
        self._corner_pick(quota)
        for cn, d in self.cmap.items():
            if d:
                self._corner(cn, d, quota[d], by_side)
        for e in self.spoke_list:
            ends = [hi for k in (1, -1) for _, _, hi in e["depts"][k]]
            e["L"] = max([14] + ends) + self.r.randint(1, 3)
        self.reserved = set()

    def _second_row(self, e, k, prev, d, ln):
        """d behind the department `prev` on spoke side k: a side hall 3 wide off the spoke just past prev's end,
        and d faces it. Returns the along position after the side hall, or None."""
        pa, pext, pdep, pd, nvec, cross = prev
        g = self._gap_of[pd].get(d, 1) or 1
        C = get(d, self.target(d), max(9, int(round(ln * 0.8))), self.salt + "|row2")
        Wd = max(c[0] for c in C.cells) + 1
        reach = pdep + g + Wd
        for s in range(pa + pext, pa + pext + 14):
            # side hall cells: along s..s+2, from the spoke edge out to `reach`
            hall = []
            for t in range(s, s + 3):
                for p in range(reach):
                    q = self._spoke_cell(e, t, (e["hi"] + 1 + p) if k > 0 else (e["lo"] - 1 - p))
                    hall.append(q)
            if any(q in self.own or q in self.reserved for q in hall):
                continue
            bx = (e["hi"] + 1 + pdep + g) if k > 0 else (e["lo"] - 1 - pdep - g)
            fr = Frame(self._spoke_cell(e, s - 1, bx), nvec, (-e["d"][0], -e["d"][1]))
            cells = [fr(c) for c in C.cells]
            if not self._fits(cells, d) or set(cells) & set(hall):
                continue
            for q in hall:
                self.own[q] = "hall"
                self.harea[q] = e["area"]
            self._put(d, C, fr)
            dep = max(c[1] for c in C.cells) + 1
            e["depts"][k].append((d, s - dep, s + 3))
            self.side_halls.append(hall)
            return s + 3
        return None

    def _corner(self, cn, d, area, by_side):
        lx0, ly0, lx1, ly1 = self.loop_box
        sy = 1 if cn[0] == "N" else -1
        sx = 1 if cn[1] == "E" else -1
        vs = by_side.get("N" if sy > 0 else "S")
        x0 = (vs["hi"] + 1 if sx > 0 else vs["lo"] - 1) if vs else (lx0 + lx1) // 2 + (1 if sx > 0 else 0)
        y0 = ly1 + 1 if sy > 0 else ly0 - 1
        edge = lx1 if sx > 0 else lx0
        front = abs(edge - x0) + 1
        W = front + 10
        Dm = self._deep.get(cn, 20) - 2
        for tries in range(5):
            C = get(d, self.target(d), W, self.salt + "|" + cn, Dmax=Dm, stem=(1, front - 4))
            fr = Frame((x0, y0), (sx, 0), (0, sy))
            if self._fits([fr(c) for c in C.cells], d):
                self._put(d, C, fr)
                return
            Dm -= 2
            W -= 2

    def _ai(self, e):
        q = self.p["budgets"]["ai"] / BL.FLOOR_RATIO * 1.06
        wide = max(9, int(round(math.sqrt(q * 1.2))))
        C = get("ai", self.target("ai"), wide, self.salt + "|tip", stem=(wide // 2 - 1, wide // 2 - 1))
        dx, dy = e["d"]
        ex, ey = e["end"]
        px, py = -dy, dx
        g0 = self.r.randint(0, 4)
        for gap in list(range(g0, 9)) + list(range(0, g0)):
            B = (ex + dx * (gap + 1) - px * (C.W // 2), ey + dy * (gap + 1) - py * (C.W // 2))
            fr = Frame(B, (px, py), (dx, dy))
            cells = [fr(c) for c in C.cells]
            strip = [(ex + dx * t + px * kk, ey + dy * t + py * kk) for t in range(1, gap + 1) for kk in (-1, 0, 1)]
            if self._fits(cells, "ai") and not any(c in self.own for c in strip):
                if gap:
                    self._strip((ex + dx, ey + dy), e["d"], gap, 3, e["area"])
                self._put("ai", C, fr)
                dep = max(c[1] for c in C.cells) + 1
                e["tip"] = (ex + dx * (gap + dep), ey + dy * (gap + dep))
                return
        self._ai_side()

    def _ai_side(self):
        for e in sorted(self.spoke_list, key=lambda e: -e["L"]):
            q = self.p["budgets"]["ai"] / BL.FLOOR_RATIO * 1.06
            ln = max(9, int(round(q / 9)))
            C = get("ai", self.target("ai"), ln, self.salt + "|side")
            for k in (1, -1):
                cross = (e["hi"] + 1) if k > 0 else (e["lo"] - 1)
                nvec = ((k, 0) if e["side"] in ("N", "S") else (0, k))
                for a in range(max(1, e["L"] - ln), 0, -1):
                    fr = Frame(self._spoke_cell(e, a, cross), e["d"], nvec)
                    if self._fits([fr(c) for c in C.cells], "ai"):
                        self._put("ai", C, fr)
                        return

    # ---------------------------------------------------------------- S4: the fill between departments
    def maint(self):
        own = self.own
        depts = set(DEPTS)

        def lab(o):
            return o if o in depts else "hall" if o in HALLISH else None
        K = 3
        labels = {}             # free cell -> {label: dist}, two labels at most
        q = deque()
        for c, o in own.items():
            l_ = lab(o)
            if l_ is None:
                continue
            for dx, dy in N4:
                n = (c[0] + dx, c[1] + dy)
                if n not in own:
                    q.append((n, l_, 1))
        while q:
            c, l_, dist = q.popleft()
            got = labels.setdefault(c, {})
            if l_ in got or len(got) >= 2:
                continue
            got[l_] = dist
            if dist < K:
                for dx, dy in N4:
                    n = (c[0] + dx, c[1] + dy)
                    if n not in own:
                        q.append((n, l_, dist + 1))
        add = set()
        for c, got in labels.items():
            if len(got) == 2 and "hall" not in got and sum(got.values()) - 1 <= K:
                add.add(c)
        # dept-to-hall gaps of one or two (between a department's side and a T bar or a lobby)
        for c, got in labels.items():
            if len(got) == 2 and "hall" in got and sum(got.values()) - 1 <= 2:
                add.add(c)
        # short of the program's maint budget: runs round department backs, nearest the existing maint first
        want = self.p["budgets"]["maint"] * self.q["qmul"].get("maint", 1.0) / 0.85
        order = list(BL.RING + ("command",))
        self.r.shuffle(order)
        for d in order:
            if len(add) >= want:
                break
            u = self.r.random()
            width = 3 if u < self.q["runw"][1] else 2 if u < self.q["runw"][0] + self.q["runw"][1] else 1
            for c in [c for c, o in own.items() if o == d]:
                for dx, dy in N4:
                    for t in range(1, width + 1):
                        n = (c[0] + t * dx, c[1] + t * dy)
                        if n in own:
                            break
                        if any(own.get((n[0] + ex, n[1] + ey)) in HALLISH for ex, ey in N8):
                            break
                        add.add(n)
        # pieces: scraps under 6 go; every other piece is joined to its nearest hall through free space
        for comp in _comps(add):
            if len(comp) < 6:
                add -= comp
        for comp in _comps(add):
            if any(own.get((c[0] + dx, c[1] + dy)) in HALLISH for c in comp for dx, dy in N4):
                continue
            path = self._to_hall(comp, add)
            if path is None:
                add -= comp
            else:
                add |= set(path)
        # maint pockets, as blocks.Layout.maint: open junk rooms grown into space beside a run
        want_p = int(round(3.9 * self.p["floor"] / 1000.0 * self.q.get("pockets", 0.7)))
        runs = sorted(add)
        self.r.shuffle(runs)
        made = 0
        for c in runs:
            if made >= want_p:
                break
            w, h = self.r.randint(4, 8), self.r.randint(4, 8)
            for dx, dy in N4:
                if (c[0] + dx, c[1] + dy) in own or (c[0] + dx, c[1] + dy) in add:
                    continue
                x0 = c[0] + dx if dx >= 0 else c[0] - w
                y0 = c[1] + dy if dy >= 0 else c[1] - h
                if dx == 0:
                    x0 = c[0] - w // 2
                if dy == 0:
                    y0 = c[1] - h // 2
                cells = [(x, y) for x in range(x0, x0 + w) for y in range(y0, y0 + h)]
                ring = {(x + ex, y + ey) for (x, y) in cells for ex, ey in N8} - set(cells)
                if any(p in own or p in add for p in cells):
                    continue
                if any(own.get(p) in HALLISH + ("mpocket",) for p in ring):
                    continue
                for p in cells:
                    own[p] = "mpocket"
                made += 1
                break
        self.info["maint_pockets"] = made
        for c in add:
            own[c] = "maint"
        self.info["maint_cells"] = len(add)

    def _to_hall(self, comp, add, limit=40):
        """The shortest path of free cells from a maint piece to a free cell beside a hall (BFS)."""
        own = self.own
        prev = {c: None for c in comp}
        q = deque((c, 0) for c in comp)
        while q:
            c, dist = q.popleft()
            if c not in comp and any(own.get((c[0] + dx, c[1] + dy)) in HALLISH for dx, dy in N4):
                path = []
                while c is not None and c not in comp:
                    path.append(c)
                    c = prev[c]
                return path
            if dist >= limit:
                continue
            for dx, dy in N4:
                n = (c[0] + dx, c[1] + dy)
                if n in prev or n in own:
                    continue
                # keep off other pieces' cells only as passing through (they are free too)
                prev[n] = c
                q.append((n, dist + 1))
        return None

    # ---------------------------------------------------------------- paint
    def paint(self):
        own = self.own
        wall, doors, mdoors = set(), set(), set()
        # test site and maint pockets: their outline is wall
        for c, o in own.items():
            if o in ("testsite", "mpocket"):
                if any(own.get((c[0] + dx, c[1] + dy)) != o for dx, dy in N8):
                    wall.add(c)
        # maint meets hall: a wall between, a maintenance airlock per contact run (blocks.Layout.paint)
        contact = [c for c, o in own.items() if o == "maint" and any(own.get((c[0] + dx, c[1] + dy)) in HALLISH
                                                                      for dx, dy in N4)]
        cs = set(contact)
        seen = set()
        for c in contact:
            if c in seen:
                continue
            run, st = [], [c]
            seen.add(c)
            while st:
                a = st.pop()
                run.append(a)
                for dx, dy in N8:
                    n = (a[0] + dx, a[1] + dy)
                    if n in cs and n not in seen:
                        seen.add(n)
                        st.append(n)
            run.sort()
            inner = [a for a in run if any(own.get((a[0] + dx, a[1] + dy)) == "maint" and (a[0] + dx, a[1] + dy)
                                           not in cs for dx, dy in N4)]
            door = inner[len(inner) // 2] if inner else None
            for a in run:
                if a == door:
                    mdoors.add(a)
                else:
                    wall.add(a)
        # maint pockets: a door or two onto maint
        for comp in _comps({c for c, o in own.items() if o == "mpocket"}):
            cand = []
            for c in comp:
                if c not in wall:
                    continue
                for dx, dy in N4:
                    a, b = (c[0] + dx, c[1] + dy), (c[0] - dx, c[1] - dy)
                    if own.get(a) == "mpocket" and a not in wall and own.get(b) == "maint" and b not in wall:
                        cand.append(c)
            cand.sort()
            self.r.shuffle(cand)
            n = 0
            for c in cand:
                if n >= 2:
                    break
                if any((c[0] + dx, c[1] + dy) in mdoors for dx, dy in N8):
                    continue
                mdoors.add(c)
                wall.discard(c)
                n += 1
        # maint floor no walk from a hall reaches (a strip whose every cell met a hall and became wall around it):
        # space, or wall beside walkable floor
        walk = {c for c, o in own.items() if (o in HALLISH or o in ("maint", "mpocket")) and c not in wall} | mdoors
        seen = {c for c, o in own.items() if o in HALLISH}
        st = list(seen)
        while st:
            a = st.pop()
            for dx, dy in N4:
                n = (a[0] + dx, a[1] + dy)
                if n in walk and n not in seen:
                    seen.add(n)
                    st.append(n)
        lost = [c for c in walk if c not in seen and own.get(c) in ("maint", "mpocket")]
        for c in lost:
            if any(own.get((c[0] + dx, c[1] + dy)) in HALLISH for dx, dy in N8):
                wall.add(c)
            else:
                del own[c]
        self.info["maint_lost"] = len(lost)
        dfloor = set()
        for d, (C, fr) in self.placed.items():
            dfloor |= {fr(c) for c in C.corr | C.floor | C.doors | C.front}
        floor = {c for c, o in own.items() if c not in wall and (o not in DEPTS or c in dfloor)}
        hull = set()
        for c in floor:
            for dx, dy in N8:
                n = (c[0] + dx, c[1] + dy)
                if n not in own:
                    hull.add(n)
        allc = set(own) | hull
        xs = [c[0] for c in allc]
        ys = [c[1] for c in allc]
        ox, oy = 10 - min(xs), 10 - min(ys)
        W, H = max(xs) - min(xs) + 21, max(ys) - min(ys) + 21
        m = dmm.Map(W, H, 1)
        sp_area = dmm.Atom("/area/space")
        for x in range(1, W + 1):
            for y in range(1, H + 1):
                c = (x - ox, y - oy)
                t = dmm.Tile([], dmm.Atom(BL.TURF_SPACE), sp_area)
                o = own.get(c)
                if o is not None and o not in DEPTS:
                    t.area = dmm.Atom(self._area(c, o))
                    if c in mdoors:
                        t.turf = dmm.Atom(BL.TURF_FLOOR)
                        t.objs.append(dmm.Atom(BL.MDOOR))
                    elif c in wall:
                        t.turf = dmm.Atom(BL.TURF_WALL)
                    else:
                        t.turf = dmm.Atom(BL.TURF_FLOOR)
                elif c in hull:
                    t.turf = dmm.Atom(BL.TURF_RWALL)
                m.set(x, y, t)
        self.offset = (ox, oy)
        nd = 0
        for d, (C, fr) in self.placed.items():
            nd += paint_dept(m, self, d, C, fr, ox, oy)
        self.info.update(size=(W, H), doors=nd + len(mdoors), touch=sorted(self.touch),
                         composed={d: dict(rooms=len(C.rooms), corridor=len(C.corr), W=C.W,
                                           floor=len(C.corr) + len(C.floor), voids=len(C.voids))
                                   for d, (C, fr) in self.placed.items()})
        return m


def _comps(cells):
    seen, out = set(), []
    for c in cells:
        if c in seen:
            continue
        comp, st = set(), [c]
        seen.add(c)
        while st:
            a = st.pop()
            comp.add(a)
            for dx, dy in N4:
                b = (a[0] + dx, a[1] + dy)
                if b in cells and b not in seen:
                    seen.add(b)
                    st.append(b)
        out.append(comp)
    return out


def paint_dept(m, L, d, C, fr, ox, oy):
    """Write a composed department: walls with its corridor area, the corridor floor, each stock copy turned with
    the frame, the doors, atmos's chambers."""
    area = RM.CORRIDOR_AREA.get(d) or BL.AREA.get(d, "/area/space")
    S = lambda c: (fr(c)[0] + ox, fr(c)[1] + oy)  # noqa: E731
    for c in C.cells:
        m.set(*S(c), dmm.Tile([], dmm.Atom(BL.TURF_WALL), dmm.Atom(area)))
    for c in C.corr:
        m.set(*S(c), dmm.Tile([], dmm.Atom(BL.TURF_FLOOR), dmm.Atom(area)))
    for rm in C.rooms:
        src, k = rm["src"], rm["k"]
        k2 = kcompose(fr.k, k)
        F0, _, _ = src.footprint(k)
        x0 = min(p[0] for p in F0)
        y0 = min(p[1] for p in F0)
        # room_stamp puts source floor p at xform(k, p - o) + origin; locally that is the box corner A minus the
        # footprint's own offset
        lo = (rm["A"][0] - x0, rm["A"][1] - y0)
        t = room_stamp.xform(fr.k, *lo)
        origin = (fr.B[0] + t[0] + ox, fr.B[1] + t[1] + oy)
        cut = {S(dd) for dd in C.doors if dd in rm["R"]}
        room_stamp.apply(m, src, k2, origin, cut, door_atom=dmm.Atom("/obj/machinery/door/airlock"))
        for c in rm["F"] | rm["R"]:
            tl = m.get(*S(c))
            if tl is None:
                continue
            objs = []
            for a in tl.objs:
                p = STP.resolve(a.path)
                if p:
                    if p != a.path:
                        a = dmm.Atom(p, list(a.vars))
                    objs.append(a)
            tl.objs = objs
            if tl.area is not None and STP.resolve(tl.area.path) != tl.area.path:
                tl.area = dmm.Atom(area)
            if tl.turf is not None:
                tp = STP.resolve(tl.turf.path)
                if tp and tp != tl.turf.path:
                    tl.turf = dmm.Atom(tp, list(tl.turf.vars))
    n = 0
    for dd in C.doors | C.front:
        tl = m.get(*S(dd))
        if tl is not None and not tl.has("/obj/machinery/door"):
            tl.objs = [dmm.Atom("/obj/machinery/door/airlock")]
            tl.turf = dmm.Atom(BL.TURF_FLOOR)
        n += 1
    for gas, F, R in getattr(C, "chambers", []):
        for c in F:
            m.set(*S(c), dmm.Tile([], dmm.Atom("/turf/open/floor/engine/" + gas), dmm.Atom(area)))
        for c in R:
            m.set(*S(c), dmm.Tile([], dmm.Atom("/turf/closed/wall/r_wall"), dmm.Atom(area)))
    return n


def layout(prog, params, sub, P, radial, room_size, rband=None, force=None):
    """blocks.layout with composed departments (same slot search, same candidates)."""
    import copy
    L = BU(prog, params, sub, P, radial, room_size, rband)
    L.core()
    L.spoke_plan()
    L._gaps()
    L.assign()
    if force is not None:
        L.cands = [(0.0, 0.0) + tuple(force)]
    base_own, base_harea = dict(L.own), dict(L.harea)
    base_blocked = {d: set(v) for d, v in L._blocked.items()}
    base_spokes = copy.deepcopy(L.spoke_list)
    base_placed = dict(L.placed)
    state = L.r.getstate()
    best = None
    for idx, (sc, _, cmap, smap, lob, ai) in enumerate(L.cands):
        L.own, L.harea, L.spoke_list = dict(base_own), dict(base_harea), copy.deepcopy(base_spokes)
        L._blocked = {d: set(v) for d, v in base_blocked.items()}
        L.placed = dict(base_placed)
        L.r.setstate(state)
        L.cmap, L.smap, L.lob, L.ai_at = cmap, smap, lob, ai
        L.place()
        L.spokes()
        mi = BL.placed_miss(L) + 3.0 * sum(1 for d in BL.RING if d not in L.placed)
        if best is None or mi < best[0] - 1e-9:
            best = (mi, idx)
    mi, idx = best
    sc, _, cmap, smap, lob, ai = L.cands[idx]
    L.own, L.harea, L.spoke_list = dict(base_own), dict(base_harea), copy.deepcopy(base_spokes)
    L._blocked = base_blocked
    L.placed = dict(base_placed)
    L.r.setstate(state)
    L.cmap, L.smap, L.lob, L.ai_at = cmap, smap, lob, ai
    L.info["corners"] = cmap
    L.info["spokes"] = {"%s%+d" % (L.spoke_list[i]["side"], k): v for (i, k), v in smap.items() if v}
    L.info["placed_miss"] = round(mi, 3)
    L.place()
    L.info["corners"] = dict(L.cmap)
    L.spokes()
    L.maint()
    m = L.paint()
    L.info["R"] = round(L.R, 1)
    L.info["missing_depts"] = [d for d in BL.RING if d not in L.placed]
    RM.touch_doors(m, L, log=lambda s: None)
    return m, L


# ------------------------------------------------------------------------------------------------ second doors
def one_door_share(sm):
    rooms = sm.rooms()
    return sum(1 for r in rooms if len(r.links) <= 1) / float(max(1, len(rooms)))


def second_doors(m, seed, log=print, target=ONE_DOOR):
    """Doors for rooms with one way in, until their share is `target`: through one plain wall (not glass, not
    reinforced, nothing hung on it, no door beside it) to floor of another region it doesn't link yet: a room of its
    own department first, then a hall, then maint. Measured on parse.SemanticMap regions, as space_sizes.py does."""
    from forge import parse
    r = random.Random("doors|%s" % seed)
    sm = parse.SemanticMap(m, "gen", 1)
    rooms = sm.rooms()
    if not rooms:
        return 0
    links = {rg.id: set(rg.links) for rg in sm.regions.values()}
    is_room = {rg.id for rg in rooms}
    one = {rg.id for rg in rooms if len(rg.links) <= 1}
    doors = {p for p, c in sm.cls.items() if c == "D"}
    hungw = set()
    for (p, side), v in sm.hung.items():
        dx, dy = {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0)}.get(side, (0, 0))
        hungw.add((p[0] + dx, p[1] + dy))
    from forge import walk
    walkable = {p for p, c in sm.cls.items() if c in ("F", "D")}
    halls = [p for p in walkable if sm.group.get(p) == "hall"]
    nomaint = walk._bfs(halls, lambda n: n in walkable and sm.group.get(n) != "maint")
    order = sorted(one)
    r.shuffle(order)
    made = 0
    for rid in order:
        if len(one) / float(len(rooms)) <= target:
            break
        if rid not in one:
            continue
        rg = sm.regions[rid]
        best = None
        for p in rg.tiles:
            for dx, dy in N4:
                w = (p[0] + dx, p[1] + dy)
                q = (p[0] + 2 * dx, p[1] + 2 * dy)
                if sm.cls.get(w) != "W" or w in sm.glass or w in hungw or sm.cls.get(q) != "F":
                    continue
                r2 = sm.region.get(q)
                if r2 is None or r2 == rid or r2 in links[rid]:
                    continue
                t = m.get(w[0], w[1], 1)
                if t is None or t.tpath != BL.TURF_WALL or t.objs:
                    continue
                # a straight wall: walls on both sides across the door's way
                if sm.cls.get((w[0] + dy, w[1] + dx)) != "W" or sm.cls.get((w[0] - dy, w[1] - dx)) != "W":
                    continue
                if any((w[0] + ex, w[1] + ey) in doors for ex, ey in N8):
                    continue
                g2 = sm.group.get(q)
                if g2 == rg.group:
                    rank = 0 if r2 in one else 1
                elif g2 == "hall":
                    rank = 2
                elif g2 == "maint" and p in nomaint:
                    rank = 3            # never a room's only way in (the gate's "ways in")
                else:
                    continue
                sc = (rank, r.random())
                if best is None or sc < best[0]:
                    best = (sc, w, r2, g2)
        if best is None:
            continue
        _, w, r2, g2 = best
        t = m.get(w[0], w[1], 1)
        maint = g2 == "maint"
        t.objs = [dmm.Atom(BL.MDOOR if maint else BL.DOOR)]
        t.turf = dmm.Atom("/turf/open/floor/plating" if maint else BL.TURF_FLOOR)
        doors.add(w)
        links[rid].add(r2)
        links[r2].add(rid)
        for x in (rid, r2):
            if x in is_room and len(links[x]) > 1:
                one.discard(x)
        made += 1
    log("compose: %d second doors; one-door share %.3f of %d rooms" % (made, len(one) / float(len(rooms)), len(rooms)))
    return made


def finish(L, m, log=print):
    """After layout(): the second doors (the atmos-engineering door is cut in layout)."""
    for d, (C, fr) in sorted(L.placed.items()):
        log("compose: %-12s %2d rooms, corridor %d, floor %d of %d wanted, W %d, voids %d" % (
            d, len(C.rooms), len(C.corr), len(C.corr) + len(C.floor), L.target(d), C.W, len(C.voids)))
    if L.info.get("missing_depts"):
        log("compose: NOT PLACED %s" % L.info["missing_depts"])
    reach_doors(m, log)
    second_doors(m, "%s|%s" % (L.salt, L.info.get("sub", 0)), log)


def _door_ok(m, sm, w, dx, dy, doors, hungw, plain=True):
    """plain: only /turf/closed/wall itself (second doors); else any wall but reinforced (a stock copy's own walls
    come in other kinds: a surgery booth sealed behind /turf/closed/wall/... on crew 80 seed 1)."""
    if sm.cls.get(w) != "W" or w in sm.glass or w in hungw:
        return False
    t = m.get(w[0], w[1], 1)
    if t is None or t.objs:
        return False
    if (t.tpath != BL.TURF_WALL) if plain else (not t.tpath.startswith(BL.TURF_WALL) or "r_wall" in t.tpath):
        return False
    if sm.cls.get((w[0] + dy, w[1] + dx)) != "W" or sm.cls.get((w[0] - dy, w[1] - dx)) != "W":
        return False
    return not any((w[0] + ex, w[1] + ey) in doors for ex, ey in N8)


def reach_doors(m, log=print):
    """Room pieces no walk reaches (a stock copy's side room whose own door was on a wall the copy didn't keep): a
    door through one plain wall to floor of the same department reached without maint, or to a hall. Never maint:
    connect.py's rescue would give them a maint door and the gate's "ways in" would name them. Gas chambers and the
    test range stay sealed, as on stock maps."""
    from forge import parse, walk
    made = walled = 0
    for _ in range(4):
        sm = parse.SemanticMap(m, "gen", 1)
        walkable = {p for p, c in sm.cls.items() if c in ("F", "D")}
        halls = [p for p in walkable if sm.group.get(p) == "hall"]
        nomaint = walk._bfs(halls, lambda n: n in walkable and sm.group.get(n) != "maint")
        doors = {p for p, c in sm.cls.items() if c == "D"}
        hungw = set()
        for (p, side), v in sm.hung.items():
            dx, dy = {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0)}.get(side, (0, 0))
            hungw.add((p[0] + dx, p[1] + dy))
        allr = walk._bfs(halls, lambda n: n in walkable)
        un = [p for p in walkable if p not in allr and sm.cls[p] == "F" and sm.group.get(p) not in (None, "maint", "hall")
              and "test_area" not in sm.area.get(p, "")
              and not (sm.m.get(p[0], p[1], 1).tpath or "").startswith("/turf/open/floor/engine")]
        done = 0
        seen = set()
        for p0 in sorted(un):
            rid = sm.region.get(p0)
            if rid is None or rid in seen:
                continue
            seen.add(rid)
            best = None
            for p in sm.regions[rid].tiles:
                for dx, dy in N4:
                    w = (p[0] + dx, p[1] + dy)
                    for thick in (1, 2):        # one wall, or two (the copy's wall and the corridor's): door + step
                        q = (p[0] + (thick + 1) * dx, p[1] + (thick + 1) * dy)
                        w2 = (p[0] + 2 * dx, p[1] + 2 * dy) if thick == 2 else None
                        if q not in nomaint or sm.cls.get(q) != "F":
                            continue
                        g = sm.group.get(q)
                        if g != sm.group.get(p) and g != "hall":
                            continue
                        glass = False
                        if not _door_ok(m, sm, w, dx, dy, doors, hungw, plain=False):
                            # last resort, one thick only: a window between them becomes the door (a stock
                            # observation booth whose own door the copy didn't keep: surgery, crew 80 seed 1)
                            if thick != 1 or w not in sm.glass or any((w[0] + ex, w[1] + ey) in doors for ex, ey in N8):
                                continue
                            glass = True
                        if w2 and (sm.cls.get(w2) != "W" or w2 in sm.glass or "r_wall" in m.get(w2[0], w2[1], 1).tpath
                                   or m.get(w2[0], w2[1], 1).objs):
                            continue
                        sc = (thick + 3 * glass, 0 if sm.area.get(q) == sm.area.get(p) else 1, w)
                        if best is None or sc < best[0]:
                            best = (sc, w, w2, sm.area.get(p))
            if best:
                t = m.get(best[1][0], best[1][1], 1)
                t.objs = [dmm.Atom(BL.DOOR)]
                t.turf = dmm.Atom(BL.TURF_FLOOR)
                if best[2]:
                    t2 = m.get(best[2][0], best[2][1], 1)
                    t2.objs = []
                    t2.turf = dmm.Atom(BL.TURF_FLOOR)
                    t2.area = dmm.Atom(best[3])
                doors.add(best[1])
                done += 1
            elif len(sm.regions[rid].tiles) < 4:
                # a closet of 1-3 tiles with no wall to its own department: wall, as connect walls corridor scraps
                for p in sm.regions[rid].tiles:
                    t = m.get(p[0], p[1], 1)
                    t.objs = []
                    t.turf = dmm.Atom(BL.TURF_WALL)
                walled += len(sm.regions[rid].tiles)
        made += done
        if not done:
            break
    log("compose: %d doors into room pieces no walk reached, %d closet tiles walled" % (made, walled))
    return made
