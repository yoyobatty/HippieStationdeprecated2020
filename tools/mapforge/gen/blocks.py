"""Stages S1 (skeleton) and S2 (department blocks): a program (gen/program.py) -> a block plan painted as a .dmm
(walls, rough partitions, doors, one area per department), which the gate's block stage measures with the same
studies as the human maps.

    from gen import blocks
    m, info = blocks.layout(prog, params, sub)       # a dmm.Map and what was placed

S1, the hall skeleton (hub shape; skeleton_types.py's numbers for hub maps):
  core      command's block at the centre, sized to command's budget, inside a hall loop 3-4 wide.
  spokes    2-4 halls out of the loop sides (the program's draw), 3-5 wide (the hall width mix), reaching
            0.45-0.62 of the station radius, sometimes with a dogleg. Every spoke ends in a junction, never a long
            dead end (human arms are 6-20 tiles from their last junction): arrivals and escape lobbies on two of
            them, a T bar on the rest, now and then a side stub.
S2, the departments:
  order     the ring order round the core: of many shuffles, the ones whose neighbours humans put together most
            (sum of log P(adj), dept_adjacency.py), atmos beside engineering always; the seed picks among the best.
  seeds     each department's seed at its median radial place (dept_adjacency.py) at its angle.
  growth    one heap over all departments: a cell costs its distance from the department's seed (over the square
            root of its quota, so big departments reach further) plus smooth noise (ragged outlines). A department
            stops at its quota (floor budget / 0.62, the floor share of human department blocks). Two departments
            keep a gap of 1-3 cells (the maint width mix) unless the pair is allowed to touch (atmos-engineering
            always; dorms-service, civic-service, civic-dorms, AI-command, command-security, civic-security with
            their P(adj)).
  maint     gaps between blocks (cells with owners on both sides of an axis within 3 cells), plus outer runs along
            some blocks (ring_p), joined to the halls by maintenance airlocks.
Painting: a block's outline is wall (one shared wall between departments allowed to touch), its inside is cut into
rooms of the department's median room size by straight partitions with a door each; one or two front doors onto
a hall, doors onto maint; space next to floor becomes hull wall.
"""
import heapq
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import dmm  # noqa: E402

N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
N8 = [(dx, dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy]
RING = ("security", "medical", "science", "engineering", "atmos", "cargo", "service", "civic", "dorms", "ai")
AREA = {
    "command": "/area/bridge", "security": "/area/security/main", "medical": "/area/medical/medbay/central",
    "science": "/area/science/research", "engineering": "/area/engine/engineering", "atmos": "/area/engine/atmos",
    "cargo": "/area/quartermaster/storage", "service": "/area/crew_quarters/bar", "civic": "/area/chapel/main",
    "dorms": "/area/crew_quarters/dorms", "ai": "/area/ai_monitored/turret_protected/ai",
    "arrivals": "/area/hallway/secondary/entry", "escape": "/area/hallway/secondary/exit",
    "testsite": "/area/science/test_area",
}
HALL_AREA = {"loop": "/area/hallway/primary/central", "N": "/area/hallway/primary/fore",
             "S": "/area/hallway/primary/aft", "W": "/area/hallway/primary/port",
             "E": "/area/hallway/primary/starboard"}
MAINT_AREA = {"N": "/area/maintenance/fore", "S": "/area/maintenance/aft", "W": "/area/maintenance/port",
              "E": "/area/maintenance/starboard"}
DIR = {"N": (0, 1), "S": (0, -1), "E": (1, 0), "W": (-1, 0)}
# pairs allowed to share a wall, with the chance (their P(adj) over families, dept_adjacency.py); atmos-engineering
# is the one "must touch" pair of the gate
TOUCH = {"atmos|engineering": 1.0, "dorms|service": 0.79, "civic|service": 0.76, "civic|dorms": 0.63,
         "ai|command": 0.50, "command|security": 0.44, "civic|security": 0.44}
# P(door) / P(adj) for those pairs: how often a touching pair also has a door between them
TOUCH_DOOR = {"atmos|engineering": 1.0, "dorms|service": 0.94, "civic|service": 0.32, "civic|dorms": 0.59,
              "ai|command": 0.54, "command|security": 0.57, "civic|security": 0.48}
GAP_W = ((1, 0.17), (2, 0.23), (3, 0.24))     # maint width mix, w1..w3 (space_sizes.py)
SPOKE_W = ((3, 0.50), (4, 0.30), (5, 0.20))     # human hall floor: w3 44%, w4 13%, w5 9% (space_sizes.py)
FLOOR_RATIO = 0.62                              # floor / footprint of human department blocks (Meta .59-.63 ...)
TURF_FLOOR, TURF_WALL, TURF_RWALL, TURF_SPACE = ("/turf/open/floor/plasteel", "/turf/closed/wall",
                                                 "/turf/closed/wall/r_wall", "/turf/open/space/basic")
DOOR, MDOOR = "/obj/machinery/door/airlock", "/obj/machinery/door/airlock/maintenance"


def pkey(a, b):
    return "|".join(sorted((a, b)))


def wchoice(r, pairs):
    t = r.random() * sum(w for _, w in pairs)
    for v, w in pairs:
        t -= w
        if t <= 0:
            return v
    return pairs[-1][0]


class Noise:
    """Smooth value noise on a 7-cell lattice, 0..1."""

    def __init__(self, r, scale=7.0):
        self.salt = r.random()
        self.s = scale

    def _h(self, i, j):
        return random.Random(hash((i, j, self.salt))).random()

    def __call__(self, x, y):
        fx, fy = x / self.s, y / self.s
        i, j = math.floor(fx), math.floor(fy)
        u, v = fx - i, fy - j
        u, v = u * u * (3 - 2 * u), v * v * (3 - 2 * v)
        a, b, c, d = self._h(i, j), self._h(i + 1, j), self._h(i, j + 1), self._h(i + 1, j + 1)
        return a + (b - a) * u + (c - a) * v + (a - b - c + d) * u * v


DEFAULT_PARAMS = dict(spread=1.0, reach=1.0, hall_dw=0, ring_p=0.35, radial_shift={}, lobby=1.0, lobe=0.5,
                      depth=1.0, qmul={}, outpost=1.3, sw=(0.5, 0.3, 0.2), lw=(2, 1), tails=1.0, pockets=0.7,
                      runw=(0.45, 0.25))
# the toxins test range: a 5x5 floor out in space past science (/area/science/test_area). On Meta, Delta, Omega,
# Hippie and Box it is 12-25 tiles at 0.86-0.98 of the station radius: often the station's farthest floor, so it
# sets the radius every radial place is measured against.
TEST_SIDE = 5
INNER_R = 0.35
# a spoke side's second block goes in a second row behind the first (further off the spoke) when, in line, the
# spoke would run past this many cells: human spoke walks are 38 at the median, 62 at most (skeleton_types)
STACK_WALK = 42
QUAD = {("N", 1): "NE", ("N", -1): "NW", ("S", 1): "SE", ("S", -1): "SW", ("E", 1): "NE", ("E", -1): "SE",
        ("W", 1): "NW", ("W", -1): "SW"}          # departments whose median radial place is inside this sit on the core loop


class Layout:
    def __init__(self, prog, params, sub, P, radial, room_size, rband=None):
        self.p, self.q = prog, dict(DEFAULT_PARAMS, **params)
        self.rband = rband or {}
        self.r = random.Random("blocks|%s|%d|%d|%d" % (prog["shape"], prog["crew"], prog["seed"], sub))
        self.P, self.radial, self.room_size = P, radial, room_size
        self.own = {}            # cell -> owner: a department, "hall", "arrivals", "escape", "maint"
        self.harea = {}          # hall cell -> area path
        self.info = dict(sub=sub)
        F = prog["floor"]
        foot = F / 0.615
        side = math.sqrt(foot / 0.45)
        self.R = self.q["spread"] * side / 2.0

    # ---------------------------------------------------------------- S1
    def core(self):
        b = self.p["budgets"]
        area = b["command"] / FLOOR_RATIO * self.q["qmul"].get("command", 1.0)
        asp = self.r.uniform(1.0, 1.5)
        cw = max(7, int(round(math.sqrt(area * asp))))
        ch = max(7, int(math.ceil(area / cw)))
        x0, y0 = -(cw // 2), -(ch // 2)
        self.core_box = (x0, y0, x0 + cw - 1, y0 + ch - 1)
        for x in range(x0, x0 + cw):
            for y in range(y0, y0 + ch):
                self.own[(x, y)] = "command"
        wl = wchoice(self.r, ((3, self.q["lw"][0]), (4, self.q["lw"][1])))
        self.loop_w = wl
        for x in range(x0 - wl, x0 + cw + wl):
            for y in range(y0 - wl, y0 + ch + wl):
                if (x, y) not in self.own:
                    self.own[(x, y)] = "hall"
                    self.harea[(x, y)] = HALL_AREA["loop"]
        self.loop_box = (x0 - wl, y0 - wl, x0 + cw + wl - 1, y0 + ch + wl - 1)

    def _rect(self, x0, y0, x1, y1, owner, area=None, overwrite=False):
        for x in range(min(x0, x1), max(x0, x1) + 1):
            for y in range(min(y0, y1), max(y0, y1) + 1):
                if overwrite or (x, y) not in self.own:
                    self.own[(x, y)] = owner
                    if area:
                        self.harea[(x, y)] = area

    def _strip(self, start, d, length, w, area, owner="hall"):
        """A hall strip w wide from start (the centre of its first row) along d for length cells. Returns the end
        centre."""
        dx, dy = d
        px, py = -dy, dx
        sx, sy = start
        for t in range(length):
            for k in range(-(w // 2), w - w // 2):
                c = (sx + dx * t + px * k, sy + dy * t + py * k)
                if c not in self.own:
                    self.own[c] = owner
                    self.harea[c] = area
        return (sx + dx * (length - 1), sy + dy * (length - 1))

    # ---------------------------------------------------------------- S1 + S2: spokes and department slots
    def spoke_plan(self):
        """Spoke sides, positions and widths (lengths come after the departments are placed along them)."""
        n = self.p["spokes"]
        sides = ["N", "E", "S", "W"]
        if n == 2 and self.r.random() < 0.6:
            a = self.r.choice(sides)
            chosen = [a, {"N": "S", "S": "N", "E": "W", "W": "E"}[a]]
        else:
            chosen = self.r.sample(sides, n)
        lx0, ly0, lx1, ly1 = self.loop_box
        self.spoke_list = []
        for side in sorted(chosen, key=sides.index):
            sw = self.q["sw"]
            w = max(3, wchoice(self.r, ((3, sw[0]), (4, sw[1]), (5, sw[2]))) + self.q["hall_dw"])
            if side in ("N", "S"):
                lo, hi = lx0 + w // 2 + 2, lx1 - (w - w // 2) - 1
                c = self.r.randint(lo, hi) if lo <= hi else (lx0 + lx1) // 2
                start = (c, ly1 + 1) if side == "N" else (c, ly0 - 1)
            else:
                lo, hi = ly0 + w // 2 + 2, ly1 - (w - w // 2) - 1
                c = self.r.randint(lo, hi) if lo <= hi else (ly0 + ly1) // 2
                start = (lx1 + 1, c) if side == "E" else (lx0 - 1, c)
            self.spoke_list.append(dict(side=side, d=DIR[side], c=c, w=w, start=start, area=HALL_AREA[side],
                                        lo=c - w // 2, hi=c + (w - w // 2) - 1, L=0, depts={1: [], -1: []}))
        self.reserved = set()
        for e in self.spoke_list:
            for t in range(int(self.R * 1.4)):
                for k in range(e["lo"], e["hi"] + 1):
                    self.reserved.add(self._spoke_cell(e, t, k))

    def _spoke_cell(self, e, t, k):
        """Cell t along spoke e (from its start) at cross coordinate k (x for N/S spokes, y for E/W)."""
        sx, sy = e["start"]
        dx, dy = e["d"]
        if e["side"] in ("N", "S"):
            return (k, sy + dy * t)
        return (sx + dx * t, k)

    def assign(self):
        """Departments to slots. Inner departments (median radial place <= INNER_R) take the four loop corners;
        the others line the spokes, nearest first by radial place; arrivals and escape end two spokes, the AI a
        third. Of many shuffles, the seed picks among the six best by: the sum of log P(adj) over the neighbours the
        slots imply (atmos always beside engineering), even loads on the spokes, and every department's predicted
        radial place (block centroid over the predicted station radius) inside the gate's band."""
        # corner candidates: departments whose radial band reaches in to 0.2 of the radius (service, civic,
        # dorms, medical, engineering on this corpus)
        # (not engineering: atmos must touch it, which two blocks in a row on one spoke side guarantee and a
        # corner of varying depth beside a spoke block does not)
        elig = sorted([d for d in RING if d not in ("ai", "engineering") and self.rband.get(d, (1, 1))[0] <= 0.2])
        # and only departments a corner can hold without pushing the spoke blocks far out: about 18 rows over the
        # corner's width (spoke edge to 10 past the loop's corner); bigger ones line a spoke instead
        lx0, ly0, lx1, ly1 = self.loop_box
        cap = ((lx1 - lx0) / 2.0 + 10) * 18
        elig = [d for d in elig if self.p["budgets"][d] / FLOOR_RATIO * 1.06 <= cap]
        n = len(self.spoke_list)
        sides = [(i, k) for i in range(n) for k in (1, -1)]
        corners = ["NE", "NW", "SE", "SW"]
        cands = []
        for _ in range(1500):
            ins = list(elig)
            self.r.shuffle(ins)
            ins = ins[:4]
            ai_slot = self.r.random() < 0.5          # the AI along a spoke like the others, or past a tip
            outer = sorted(d for d in RING if d not in ins and (d != "ai" or ai_slot))
            cmap = dict(zip(corners, ins + [None] * (4 - len(ins))))
            smap = {s: [] for s in sides}
            for d in sorted(outer, key=lambda d: self.radial.get(d, 0.4) + self.r.uniform(-0.04, 0.04)):
                smap[self.r.choice(sides)].append(d)
            if max(len(v) for v in smap.values()) > 2:
                continue
            nb = self._neighbours(cmap, smap)
            if not any(set(p) == {"atmos", "engineering"} for p in nb):
                continue
            ends = list(range(n))
            self.r.shuffle(ends)
            lob = ends[:2]
            ai = ends[2] if n > 2 and not ai_slot else None
            sc = sum(math.log(min(0.98, max(0.02, self.P.get(pkey(a, b), 0.16)))) for a, b in nb)
            load = [max(sum(self.p["budgets"][d] for d in smap[(i, k)]) for k in (1, -1)) for i in range(n)]
            tot = float(sum(self.p["budgets"][d] for d in outer) or 1)
            # no load balancing: human hubs are lopsided (the hall's centroid sits 0.05-0.13 of the radius off the
            # station's); the predicted spoke walks and places below keep the spokes in bounds
            sc -= 8.0 * self._radial_miss(cmap, smap, lob, ai)
            cands.append((sc, self.r.random(), cmap, smap, lob, ai))
        cands.sort(key=lambda c: (-c[0], c[1]))
        self.cands = cands[:10]
        sc, _, cmap, smap, lob, ai = self.cands[0]
        self.cmap, self.smap, self.lob, self.ai_at = cmap, smap, lob, ai
        self.info["corners"] = cmap
        self.info["spokes"] = {"%s%+d" % (self.spoke_list[i]["side"], k): v for (i, k), v in smap.items() if v}

    def _radial_miss(self, cmap, smap, lob, ai):
        """Sum over departments of how far the predicted radial place falls outside the gate's band (in band
        widths), plus the predicted offset of the loop from the station's centroid. Prediction in 2D: blocks
        sqrt(q / 1.6) deep along their spoke side one after another, corner blocks beside the loop, lobbies and the
        AI past their spoke tips; the centroid weights each by its floor; the radius is the farthest block corner
        from the centroid (as dept_adjacency measures it)."""
        b = self.p["budgets"]
        lx0, ly0, lx1, ly1 = self.loop_box
        pts, corners, tips = [], [], []

        def add(name, cx, cy, wx, wy, q):
            pts.append((name, cx, cy, q))
            corners.extend([(cx - wx / 2.0, cy - wy / 2.0), (cx + wx / 2.0, cy + wy / 2.0),
                            (cx - wx / 2.0, cy + wy / 2.0), (cx + wx / 2.0, cy - wy / 2.0)])
        add("command", (lx0 + lx1) / 2.0, (ly0 + ly1) / 2.0, lx1 - lx0, ly1 - ly0, b["command"])
        for i, e in enumerate(self.spoke_list):
            sx, sy = e["start"]
            dx, dy = e["d"]
            ns = e["side"] in ("N", "S")
            L = 14
            for k in (1, -1):
                # a corner block in this side's quadrant holds the first ~13 cells along the spoke
                a = 13 if cmap.get(QUAD[(e["side"], k)]) else 1
                prev = None
                for d in smap[(i, k)]:
                    q = b[d] / FLOOR_RATIO
                    h = max(8, min(36, math.sqrt(q / 0.75) * self.q["depth"]))
                    ln = q / h
                    off = 0.0
                    if prev and a + ln > STACK_WALK:          # second row, behind the first
                        a, off = prev[0], prev[2] + 1.5
                    cross = (e["hi"] + off + h / 2.0) if k > 0 else (e["lo"] - off - h / 2.0)
                    al = a + ln / 2.0
                    if ns:
                        add(d, cross, sy + dy * al, h, ln, b[d])
                    else:
                        add(d, sx + dx * al, cross, ln, h, b[d])
                    prev = (a, ln, h + off)
                    a += ln + 1.5
                L = max(L, a + 2)
            tx, ty = sx + dx * L, sy + dy * L
            corners.append((tx, ty))
            ext = (5 + math.sqrt(b["arrivals"] / 0.9 / 1.2)) if i in lob else 4 if i == ai else 0
            run = L + ext
            tips.append((tx + dx * ext, ty + dy * ext, run))     # the spoke's farthest hall: past its lobby
            if i in lob:
                kind = ("arrivals", "escape")[lob.index(i)]
                dep = math.sqrt(b[kind] / 0.9 / 1.2)
                add(kind, tx + dx * dep / 2.0, ty + dy * dep / 2.0, 7.5, dep, b[kind])
            if i == ai:
                dep = math.sqrt(b["ai"] / FLOOR_RATIO)
                add("ai", tx + dx * (2 + dep / 2.0), ty + dy * (2 + dep / 2.0), dep, dep, b["ai"])
        hx, hy = (lx1 - lx0) / 2.0, (ly1 - ly0) / 2.0
        for cn, d in cmap.items():
            if d:
                sxn = 1 if cn[1] == "E" else -1
                syn = 1 if cn[0] == "N" else -1
                q = b[d] / FLOOR_RATIO
                add(d, sxn * hx * 0.7, (ly1 + 5) if syn > 0 else (ly0 - 5), hx * 1.4, 10, b[d])
        W = float(sum(q for _, _, _, q in pts))
        cx = sum(x * q for _, x, _, q in pts) / W
        cy = sum(y * q for _, _, y, q in pts) / W
        R = max(math.hypot(x - cx, y - cy) for x, y in corners) * self.q["outpost"]
        # the loop sits off the station's centroid by 0.08..0.17 of the radius on human hubs (radial.command's
        # floor, skel.core_dist's ceiling): command's band below covers the floor, this the ceiling
        miss = max(0.0, math.hypot(cx, cy) / R - 0.16) / 0.05
        # spokes: a walk from the loop of at most ~58 (skel.spoke_len 62 max) and a reach of at most ~0.63
        for tx, ty, run in tips:
            miss += max(0.0, run - 50) / 12.0 + max(0.0, math.hypot(tx - cx, ty - cy) / R - 0.62) / 0.08
        # the hall's centroid (loop and spokes, by length) sits 0.05..0.13 of the radius off the station's
        hw = [((lx0 + lx1) / 2.0, (ly0 + ly1) / 2.0, 2.0 * ((lx1 - lx0) + (ly1 - ly0)))]
        for e, (tx, ty, run) in zip(self.spoke_list, tips):
            sx0, sy0 = e["start"]
            hw.append(((sx0 + tx) / 2.0, (sy0 + ty) / 2.0, run))
        hW = sum(w for _, _, w in hw)
        hx_ = sum(x * w for x, _, w in hw) / hW
        hy_ = sum(y * w for _, y, w in hw) / hW
        pts.append(("hall", hx_, hy_, 0.0))
        for d, x, y, q in pts:
            band = self.rband.get(d)
            if not band:
                continue
            lo, hi = band
            v = math.hypot(x - cx, y - cy) / R
            miss += max(0.0, lo - v, v - hi) / max(0.05, hi - lo)
        return miss

    def _neighbours(self, cmap, smap):
        """Pairs the slots put side by side: consecutive departments on one spoke side; a corner department and
        the first department on the spoke sides of its quadrant."""
        out = []
        for v in smap.values():
            for a, b in zip(v, v[1:]):
                out.append((a, b))
        q = {"NE": (("N", 1), ("E", 1)), "NW": (("N", -1), ("W", 1)), "SE": (("S", 1), ("E", -1)),
             "SW": (("S", -1), ("W", -1))}
        for cn, d in cmap.items():
            if not d:
                continue
            for i, e in enumerate(self.spoke_list):
                for side, k in q[cn]:
                    if e["side"] == side and smap.get((i, k)):
                        out.append((d, smap[(i, k)][0]))
        return out

    def _free(self, c, d):
        if c in self.own or c in self.reserved:
            return False
        for e, g in self._gap_of[d].items():
            for dx in range(-g, g + 1):
                for dy in range(-g, g + 1):
                    if self.own.get((c[0] + dx, c[1] + dy)) == e:
                        return False
        return True

    def _gaps(self):
        self.touch = {k for k, p in TOUCH.items() if self.r.random() < p}
        names = RING + ("command",)
        self._gap_of = {d: {} for d in names}
        for i, a in enumerate(names):
            for b in names[i + 1:]:
                k = pkey(a, b)
                g = 0 if k in self.touch else wchoice(self.r, GAP_W)
                if g:
                    self._gap_of[a][b] = g
                    self._gap_of[b][a] = g

    def _claim(self, cells, d):
        for c in cells:
            self.own[c] = d

    def _ragged(self, cells, far, along, d):
        """Notch the far edge of a block (the edge away from its hall): runs of 3-7 cells pulled in 0-2 cells, and
        now and then a corner cut, so blocks don't read as boxes."""
        cells = set(cells)
        if not cells:
            return cells
        fx, fy = far
        ax, ay = along
        # far edge cells: no block cell beyond them in the far direction
        edge = sorted([c for c in cells if (c[0] + fx, c[1] + fy) not in cells], key=lambda c: c[0] * ax + c[1] * ay)
        i = 0
        while i < len(edge):
            run = self.r.randint(3, 7)
            cut = self.r.choice((0, 0, 1, 1, 2))
            for c in edge[i:i + run]:
                for t in range(cut):
                    q = (c[0] - fx * t, c[1] - fy * t)
                    cells.discard(q)
            i += run
        return cells

    def _corner(self, cn, d, area, by_side):
        """An inner department as an L wrapping loop corner cn, fronting the loop (and the spoke it borders)."""
        lx0, ly0, lx1, ly1 = self.loop_box
        sy = 1 if cn[0] == "N" else -1
        sx = 1 if cn[1] == "E" else -1
        vs = by_side.get("N" if sy > 0 else "S")
        x0 = (vs["hi"] + 1 if sx > 0 else vs["lo"] - 1) if vs else (lx0 + lx1) // 2 + (1 if sx > 0 else 0)
        y0 = ly1 + 1 if sy > 0 else ly0 - 1
        h = self.r.randint(8, 12)
        hs = by_side.get("E" if sx > 0 else "W")
        # the top run reaches past the loop's corner by the block's depth, then the L turns down the side
        edge = lx1 if sx > 0 else lx0
        ln = min(max(6, int(round(area / h))), abs(edge - x0) + 1 + h)
        cells = []
        for t in range(ln):
            for p in range(h):
                c = (x0 + sx * t, y0 + sy * p)
                if len(cells) >= area:
                    break
                if self._free(c, d):
                    cells.append(c)
        if len(cells) < area * 0.85:          # the L's leg down the loop's side, toward the side spoke
            xs = lx1 + 1 if sx > 0 else lx0 - 1
            ystop = (hs["hi"] + 1 if sy > 0 else hs["lo"] - 1) if hs else (ly0 + ly1) // 2
            y = y0 - sy
            while (y - ystop) * sy >= 0 and len(cells) < area:
                for p in range(h):
                    c = (xs + sx * p, y)
                    if self._free(c, d):
                        cells.append(c)
                y -= sy
        p = h
        while len(cells) < area * 0.95 and p < max(h + 20, self._deep.get(cn, 0)):     # more rows outward
            for t in range(ln):
                c = (x0 + sx * t, y0 + sy * p)
                if self._free(c, d):
                    cells.append(c)
            p += 1
        cells = self._ragged(cells, (0, sy), (1, 0), d)
        self._claim(cells, d)

    def _corner_pick(self, quota):
        """Which inner department takes which loop corner, decided once the spoke blocks stand: the station's
        centroid is then known, and the departments humans put nearest the centre (service 0.20, civic 0.24 ...)
        take the corners nearest it. Every permutation that keeps the slot neighbours' musts (atmos beside
        engineering) is scored by its predicted radial misses."""
        import itertools
        cells = list(self.own)
        cx = sum(c[0] for c in cells) / float(len(cells))
        cy = sum(c[1] for c in cells) / float(len(cells))
        R = max(math.hypot(c[0] - cx, c[1] - cy) for c in cells) * self.q["outpost"] * 1.05
        lx0, ly0, lx1, ly1 = self.loop_box
        pos = {}
        for cn in self.cmap:
            sy = 1 if cn[0] == "N" else -1
            sx = 1 if cn[1] == "E" else -1
            pos[cn] = ((lx1 if sx > 0 else lx0) - sx * 4, (ly1 if sy > 0 else ly0) + sy * 6)
        corners = [cn for cn, d in self.cmap.items() if d]
        ds = [self.cmap[cn] for cn in corners]
        must = any(set(p) == {"atmos", "engineering"} for p in self._neighbours(self.cmap, self.smap))
        best = None
        for perm in itertools.permutations(ds):
            cmap = dict(self.cmap)
            cmap.update(zip(corners, perm))
            if must and not any(set(p) == {"atmos", "engineering"} for p in self._neighbours(cmap, self.smap)):
                continue
            miss = 0.0
            for cn, d in zip(corners, perm):
                v = math.hypot(pos[cn][0] - cx, pos[cn][1] - cy) / R
                lo, hi = self.rband.get(d, (0.0, 1.0))
                mid = 0.5 * (lo + hi)
                miss += max(0.0, lo - v, v - hi) / max(0.05, hi - lo) + 0.2 * abs(v - mid)
            if best is None or miss < best[0]:
                best = (miss, cmap)
        if best:
            self.cmap = best[1]

    def place(self):
        b = self.p["budgets"]
        quota = {d: b[d] / FLOOR_RATIO * 1.06 * self.q["qmul"].get(d, 1.0) for d in RING}
        by_side = {e["side"]: e for e in self.spoke_list}
        # outer departments along the spokes first, nearest first, each sliding out until it fits; a quadrant
        # whose loop corner takes an inner department keeps its first 13 cells along the spoke for it
        # how deep a corner block runs out along a N/S spoke: the biggest inner quota over the corner's width
        # (from the spoke to past the loop's corner)
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
        for (i, k), ds in self.smap.items():
            e = self.spoke_list[i]
            cn = QUAD[(e["side"], k)]
            a = (deep[cn] if e["side"] in ("N", "S") else 13) if self.cmap.get(cn) else 1
            prev = None
            for j, d in enumerate(ds):
                asp = self.r.uniform(0.45, 1.1)         # length along the spoke over depth: deep, short blocks
                h = max(8, min(36, int(round(math.sqrt(quota[d] / asp) * self.q["depth"]))))
                ln = max(6, int(round(quota[d] / h)))
                off = 0
                if prev and a + ln > STACK_WALK:
                    # second row: behind the previous block, a maint gap (or one wall, for a pair that touches)
                    a = prev[0]
                    off = prev[2] + self._gap_of[prev[3]].get(d, 0)
                while a < self.R * 1.3:
                    cells = [self._spoke_cell(e, t, (e["hi"] + off + p if k > 0 else e["lo"] - off - p))
                             for t in range(a, a + ln) for p in range(1, h + 1)]
                    if all(self._free(c, d) for c in cells):
                        break
                    a += 1
                else:
                    continue
                prev = (a, ln, off + h, d)
                far = (k, 0) if e["side"] in ("N", "S") else (0, k)
                cells = self._ragged(cells, far, e["d"], d)
                self._claim(cells, d)
                e["depts"][k].append((d, a, a + ln))
                nxt = ds[j + 1] if j + 1 < len(ds) else None
                a += ln + (self._gap_of[d].get(nxt, 0) if nxt else 1)
                if off:
                    a = max(a, prev[0] + prev[1] + 1)
        self._corner_pick(quota)
        for cn, d in self.cmap.items():
            if d:
                self._corner(cn, d, quota[d], by_side)
        # spoke lengths: past the last block on either side
        for e in self.spoke_list:
            ends = [hi for k in (1, -1) for _, _, hi in e["depts"][k]]
            e["L"] = max([14] + ends) + self.r.randint(1, 3)
        self.reserved = set()

    def spokes(self):
        """Draw the spokes at their lengths, then their ends: lobbies on two (opposite when there are), the AI past
        a third, T bars on the rest, now and then a side stub."""
        for e in self.spoke_list:
            e["end"] = self._strip(e["start"], e["d"], e["L"], e["w"], e["area"])
        lob, ai_at = self.lob, self.ai_at
        kinds = ["arrivals", "escape"]
        for i, e in enumerate(self.spoke_list):
            # every spoke ends in a junction just past its last block (human arms end within 6-20 tiles of their
            # last junction); a lobby or the AI goes a few cells on from it
            self._tbar(e, keep_both=i in lob or i == ai_at)
            if i in lob:
                # the lobby's neck: 4-5 wide, its own area (human arrivals and escape open through a hall before
                # the wide part; the wide part alone would push the 9+ wide hall share past the human 22%)
                kind = kinds[lob.index(i)]
                k = self.r.randint(4, 8)
                e["end"] = self._strip((e["end"][0] + e["d"][0], e["end"][1] + e["d"][1]), e["d"], k,
                                       self.r.choice((4, 5)), AREA[kind], owner=kind)
            elif i == ai_at:
                k = self.r.randint(3, 6)
                e["end"] = self._strip((e["end"][0] + e["d"][0], e["end"][1] + e["d"][1]), e["d"], k, e["w"],
                                       e["area"])
            if i in lob:
                self._lobby(e, kinds[lob.index(i)])
            elif i == ai_at:
                self._ai(e)
        if ai_at is None and not any("ai" in v for v in self.smap.values()):
            self._ai_side()
        self._test_site()

    def _test_site(self):
        """The test range, out past science: from the station's floor centroid along the line to science's
        centroid, outpost x the farthest block corner's distance."""
        cells = [c for c, o in self.own.items()]
        cx = sum(c[0] for c in cells) / float(len(cells))
        cy = sum(c[1] for c in cells) / float(len(cells))
        far = max(math.hypot(c[0] - cx, c[1] - cy) for c in cells)
        sci = [c for c, o in self.own.items() if o == "science"] or cells
        sx = sum(c[0] for c in sci) / float(len(sci)) - cx
        sy = sum(c[1] for c in sci) / float(len(sci)) - cy
        dist = far * self.q["outpost"] - TEST_SIDE / 2.0
        xs, ys = [c[0] for c in cells], [c[1] for c in cells]
        # of the 8 compass directions, the nearest to science's whose box stays near square (human stations'
        # aspect is 0.76-0.96)
        best = None
        for k in range(8):
            a = k * math.pi / 4
            ux, uy = math.cos(a), math.sin(a)
            px, py = cx + ux * dist, cy + uy * dist
            w = max(max(xs), px) - min(min(xs), px)
            h = max(max(ys), py) - min(min(ys), py)
            asp = min(w, h) / max(w, h)
            sc = -(ux * sx + uy * sy) / (math.hypot(sx, sy) or 1.0) + (4.0 if asp < 0.78 else 0.0) - asp
            if best is None or sc < best[0]:
                best = (sc, px, py)
        ox, oy = int(round(best[1])), int(round(best[2]))
        for x in range(ox - TEST_SIDE // 2 - 1, ox + TEST_SIDE // 2 + 2):     # walls round a 5x5 floor
            for y in range(oy - TEST_SIDE // 2 - 1, oy + TEST_SIDE // 2 + 2):
                if (x, y) not in self.own:
                    self.own[(x, y)] = "testsite"
        self.info["test_site"] = (ox, oy)

    def _ai(self, e):
        q = self.p["budgets"]["ai"] / FLOOR_RATIO * 1.06
        wide = max(7, int(round(math.sqrt(q * 1.2))))
        deep = max(6, int(round(q / wide)))
        dx, dy = e["d"]
        ex, ey = e["end"]
        px, py = -dy, dx
        gap = self.r.randint(0, 4)
        if gap:
            self._strip((ex + dx, ey + dy), e["d"], gap, 3, e["area"])
        cells = []
        for t in range(gap + 1, gap + 1 + deep):
            for k in range(-(wide // 2), wide - wide // 2):
                c = (ex + dx * t + px * k, ey + dy * t + py * k)
                if c not in self.own:
                    cells.append(c)
        self._claim(cells, "ai")
        e["tip"] = (ex + dx * (gap + deep), ey + dy * (gap + deep))

    def _ai_side(self):
        """No spoke left for the AI: it goes past the far end of the longest spoke side."""
        e = max(self.spoke_list, key=lambda e: e["L"])
        q = self.p["budgets"]["ai"] / FLOOR_RATIO * 1.06
        h = 9
        ln = max(6, int(round(q / h)))
        k = self.r.choice((1, -1))
        a = e["L"] - ln // 2
        cells = [self._spoke_cell(e, t, (e["hi"] + p if k > 0 else e["lo"] - p))
                 for t in range(a, a + ln) for p in range(1, h + 1)]
        self._claim([c for c in cells if c not in self.own], "ai")

    def _lobby(self, e, kind):
        b = self.p["budgets"][kind] * self.q["lobby"] / 0.9 * 0.75     # a quarter of it went to the neck
        wide = max(7, min(11, int(round(math.sqrt(b * 1.2)))))      # near square: no long dead-end arm in it
        deep = max(4, int(round(b / wide)))
        dx, dy = e["d"]
        ex, ey = e["end"]
        px, py = -dy, dx
        for t in range(1, deep + 1):
            for k in range(-(wide // 2), wide - wide // 2):
                c = (ex + dx * t + px * k, ey + dy * t + py * k)
                self.own[c] = kind
                self.harea[c] = AREA[kind]
        e["lobby"] = kind
        e["tip"] = (ex + dx * deep, ey + dy * deep)

    def _tbar(self, e, keep_both=False):
        """A cross hall at the spoke's tip (3 wide, arms 4-7). When a block stands in the way of both arms the spoke
        goes on 2 cells and tries again (up to 12 cells): a spoke must end in a junction, or the branch from the
        loop to its lobby reads as one long dead-end arm (human arms: 6-20 tiles)."""
        dx, dy = e["d"]
        px, py = -dy, dx
        w = e["w"]
        sides = [sgn for sgn in (1, -1) if keep_both or self.r.random() >= 0.25] or [1]
        arms = {sgn: self.r.randint(4, 7) for sgn in sides}
        aw = {sgn: self.r.choice((2, 3, 3)) for sgn in sides}        # human halls: w2 5%, w1 2.5%
        tail = {sgn: int(round(self.r.choice((0, 2, 3)) * self.q["tails"])) for sgn in sides}
        for _ in range(7):
            ex, ey = e["end"]
            made = 0
            for sgn in sides:
                cells = []
                for t in range(arms[sgn] + tail[sgn]):
                    for k in range(aw[sgn] if t < arms[sgn] else 1):
                        c = (ex - dx * k + px * sgn * (w // 2 + 1 + t), ey - dy * k + py * sgn * (w // 2 + 1 + t))
                        cells.append(c)
                if all(c not in self.own for c in cells[:6]):
                    for c in cells:
                        if c not in self.own:
                            self.own[c] = "hall"
                            self.harea[c] = e["area"]
                    made += 1
            if made:
                break
            e["end"] = self._strip((ex + dx, ey + dy), e["d"], 2, w, e["area"])
            e["L"] += 2
        e["tip"] = e["end"]

    def _stub(self, e):
        dx, dy = e["d"]
        sx, sy = e["start"]
        t = int(e["L"] * self.r.uniform(0.3, 0.6))
        sgn = self.r.choice((1, -1))
        px, py = -dy * sgn, dx * sgn
        w = 3
        start = (sx + dx * t + px * (e["w"] // 2 + 1), sy + dy * t + py * (e["w"] // 2 + 1))
        self._strip(start, (px, py), self.r.randint(6, 9), w, e["area"])

    def maint(self):
        K = 3
        owners = self.own
        free_near = set()
        for c, o in list(owners.items()):
            for dx in range(-K - 1, K + 2):
                for dy in range(-K - 1, K + 2):
                    q = (c[0] + dx, c[1] + dy)
                    if q not in owners:
                        free_near.add(q)
        add = set()
        give = {}
        for c in free_near:
            for (dx, dy) in ((1, 0), (0, 1)):
                hits = []
                for sgn in (1, -1):
                    for t in range(1, K + 1):
                        q = (c[0] + dx * sgn * t, c[1] + dy * sgn * t)
                        if q in owners:
                            hits.append(owners[q])
                            break
                if len(hits) == 2:
                    a, b = hits
                    # a notch between one department's own cells, or between a pair allowed to touch (a ragged
                    # edge under a stacked block), goes back to the department: no maint run between them
                    if a in RING + ("command",) and (a == b or pkey(a, b) in self.touch):
                        give[c] = a
                    else:
                        add.add(c)
                    break
        for c, d in give.items():
            if c not in add:
                owners[c] = d
        # outer runs round blocks, one department at a time in a seeded order, until the maint budget is met
        # (the program's maint share; about 0.85 of a run stays floor once it meets halls and hull)
        want = self.p["budgets"]["maint"] * self.q["qmul"].get("maint", 1.0) / 0.85
        order = list(RING + ("command",))
        self.r.shuffle(order)
        for d in order:
            if len(add) >= want:
                break
            u = self.r.random()
            width = 3 if u < self.q["runw"][1] else 2 if u < self.q["runw"][0] + self.q["runw"][1] else 1
            cells = [c for c, o in owners.items() if o == d]
            for c in cells:
                for dx, dy in N4:
                    for t in range(1, width + 1):
                        q = (c[0] + t * dx, c[1] + t * dy)
                        if q in owners:
                            break
                        add.add(q)
        # still short: widen the runs a layer at a time (human maint is 3+ wide in 59% of its floor)
        hallish = ("hall", "arrivals", "escape")
        for _ in range(4):
            if len(add) >= want:
                break
            grow = set()
            for c in add:
                for dx, dy in N4:
                    q = (c[0] + dx, c[1] + dy)
                    if q in owners or q in add:
                        continue
                    if any(owners.get((q[0] + ex, q[1] + ey)) in hallish for ex, ey in N8):
                        continue
                    grow.add(q)
            grow = sorted(grow)
            self.r.shuffle(grow)
            add.update(grow[:int(want - len(add)) + 1])
        # maint pockets: open junk rooms off the runs (human maint: 1.8-5.9 pockets a 1000 tiles, median 21 tiles,
        # 30-68% of maint floor in open 3x3 fields), grown into space beside a run
        want_p = int(round(3.9 * self.p["floor"] / 1000.0 * self.q.get("pockets", 0.7)))
        runs = sorted(add)
        self.r.shuffle(runs)
        made = 0
        for c in runs:
            if made >= want_p:
                break
            w, h = self.r.randint(4, 7), self.r.randint(4, 7)
            for dx, dy in N4:
                if (c[0] + dx, c[1] + dy) in owners or (c[0] + dx, c[1] + dy) in add:
                    continue
                x0 = c[0] + dx if dx >= 0 else c[0] - w
                y0 = c[1] + dy if dy >= 0 else c[1] - h
                if dx == 0:
                    x0 = c[0] - w // 2
                if dy == 0:
                    y0 = c[1] - h // 2
                cells = [(x, y) for x in range(x0, x0 + w) for y in range(y0, y0 + h)]
                ring = {(x + ex, y + ey) for (x, y) in cells for ex, ey in N8} - set(cells)
                if any(q in owners or q in add for q in cells):
                    continue
                if any(owners.get(q) in ("hall", "arrivals", "escape", "mpocket") for q in ring):
                    continue
                for q in cells:
                    owners[q] = "mpocket"
                made += 1
                break
        self.info["maint_pockets"] = made
        # drop maint scraps
        seen = set()
        for c in add:
            if c in seen:
                continue
            comp, st = [], [c]
            seen.add(c)
            while st:
                a = st.pop()
                comp.append(a)
                for dx, dy in N4:
                    q = (a[0] + dx, a[1] + dy)
                    if q in add and q not in seen:
                        seen.add(q)
                        st.append(q)
            if len(comp) >= 6:
                for a in comp:
                    owners[a] = "maint"

    # ---------------------------------------------------------------- paint
    def paint(self):
        own = self.own
        ids = {d: i for i, d in enumerate(("command",) + RING + ("testsite", "mpocket"))}
        depts = set(ids)
        wall = set()
        for c, o in own.items():
            if o not in depts:
                continue
            for dx, dy in N8:
                q = (c[0] + dx, c[1] + dy)
                e = own.get(q)
                if e == o:
                    continue
                if e in depts and pkey(o, e) in self.touch and ids[e] < ids[o]:
                    continue
                wall.add(c)
                break
        # maint meets hall: a wall between, a maintenance airlock per contact run
        hallish = {"hall", "arrivals", "escape"}
        mdoors = set()
        contact = [c for c, o in own.items() if o == "maint" and any(own.get((c[0] + dx, c[1] + dy)) in hallish
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
                    q = (a[0] + dx, a[1] + dy)
                    if q in cs and q not in seen:
                        seen.add(q)
                        st.append(q)
            run.sort()
            door = run[len(run) // 2]
            for a in run:
                if a == door and any(own.get((a[0] + dx, a[1] + dy)) == "maint" and (a[0] + dx, a[1] + dy) not in cs
                                     for dx, dy in N4):
                    mdoors.add(a)
                else:
                    wall.add(a)
        floor = {c for c, o in own.items() if c not in wall}
        # partitions inside department blocks
        doors = set(mdoors)
        for d in ids:
            cells = {c for c in floor if own[c] == d}
            if not cells or d == "mpocket":
                continue
            self._partition(cells, self.room_size.get(d, 20), wall, doors)
        floor = {c for c, o in own.items() if c not in wall}
        # front doors: department outline wall between its floor and a hall / maint / a touching department
        for d in ids:
            outline = [c for c in wall if own.get(c) == d]
            fronts = {"hall": [], "maint": [], "dept": []}
            for c in outline:
                for dx, dy in ((1, 0), (0, 1)):
                    a, b = (c[0] + dx, c[1] + dy), (c[0] - dx, c[1] - dy)
                    for x, y in ((a, b), (b, a)):
                        if x in floor and own.get(x) == d and y in floor and own.get(y) != d:
                            o = own.get(y)
                            k = "hall" if o in hallish else "maint" if o == "maint" else "dept"
                            if k == "dept" and (pkey(d, o) not in self.touch or
                                                self.r.random() > TOUCH_DOOR.get(pkey(d, o), 0)):
                                continue
                            fronts[k].append((c, o))
            for k, n in (("hall", 1 + (self.r.random() < 0.5)), ("maint", 2), ("dept", 1)):
                cand = fronts[k]
                self.r.shuffle(cand)
                used = set()
                for c, o in cand:
                    if n <= 0:
                        break
                    if k == "dept" and o in used:
                        continue
                    if any((c[0] + dx, c[1] + dy) in doors for dx, dy in N8):
                        continue
                    doors.add(c)
                    used.add(o)
                    n -= 1
        for c in doors:
            wall.discard(c)
        # hull: space next to floor
        hull = set()
        for c in list(floor) + list(doors):
            for dx, dy in N8:
                q = (c[0] + dx, c[1] + dy)
                if q not in own:
                    hull.add(q)
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
                t = dmm.Tile([], dmm.Atom(TURF_SPACE), sp_area)
                o = own.get(c)
                if o is not None:
                    t.area = dmm.Atom(self._area(c, o))
                    if c in doors:
                        t.turf = dmm.Atom(TURF_FLOOR)
                        t.objs.append(dmm.Atom(MDOOR if c in mdoors or o == "maint" else DOOR))
                    elif c in wall:
                        t.turf = dmm.Atom(TURF_WALL)
                    else:
                        t.turf = dmm.Atom(TURF_FLOOR)
                elif c in hull:
                    t.turf = dmm.Atom(TURF_RWALL)
                m.set(x, y, t)
        self.offset = (ox, oy)
        self.info.update(size=(W, H), doors=len(doors), touch=sorted(self.touch))
        return m

    def _area(self, c, o):
        if o in AREA:
            return AREA[o]
        if o == "hall":
            return self.harea.get(c, HALL_AREA["loop"])
        if o in ("maint", "mpocket"):
            x, y = c
            if abs(y) >= abs(x):
                return MAINT_AREA["N" if y > 0 else "S"]
            return MAINT_AREA["E" if x > 0 else "W"]
        return AREA.get(o, "/area/space")

    def _partition(self, cells, target, wall, doors):
        """Cut a block's floor into rooms near target tiles with straight 1-wide walls, a door in each."""
        stack = [cells]
        while stack:
            cs = stack.pop()
            if len(cs) <= target * 1.6:
                continue
            xs = [c[0] for c in cs]
            ys = [c[1] for c in cs]
            w, h = max(xs) - min(xs) + 1, max(ys) - min(ys) + 1
            if w < 5 and h < 5:
                continue
            vertical = w >= h
            lo, hi = (min(xs), max(xs)) if vertical else (min(ys), max(ys))
            if hi - lo < 4:
                continue
            cut = self.r.randint(lo + 2, hi - 2) if hi - lo >= 6 else (lo + hi) // 2
            line = [c for c in cs if (c[0] if vertical else c[1]) == cut]
            a = {c for c in cs if (c[0] if vertical else c[1]) < cut}
            b = {c for c in cs if (c[0] if vertical else c[1]) > cut}
            if len(a) < 4 or len(b) < 4:
                continue
            wall.update(line)
            # a door per contiguous run of the cut where both sides are floor
            okd = [c for c in line if ((c[0] - 1, c[1]) in a and (c[0] + 1, c[1]) in b) or
                   ((c[0], c[1] - 1) in a and (c[0], c[1] + 1) in b)]
            okd.sort()
            runs, cur = [], []
            for c in okd:
                if cur and abs(c[0] - cur[-1][0]) + abs(c[1] - cur[-1][1]) == 1:
                    cur.append(c)
                else:
                    if cur:
                        runs.append(cur)
                    cur = [c]
            if cur:
                runs.append(cur)
            for run in runs:
                doors.add(run[len(run) // 2])
            stack.append(a)
            stack.append(b)


def placed_miss(L):
    """The block-stage numbers that placement alone decides, measured on the placed cells (no painting): each
    department's radial place against its band, the loop's offset, the spokes' walk and reach. Walls are not yet
    drawn, so a block's centroid is its cells'; close to what the gate measures, at a hundredth of the cost."""
    own = L.own
    cells = [c for c, o in own.items() if o != "testsite"] + [c for c, o in own.items() if o == "testsite"]
    cx = sum(c[0] for c in cells) / float(len(cells))
    cy = sum(c[1] for c in cells) / float(len(cells))
    R = max(math.hypot(c[0] - cx, c[1] - cy) for c in cells)
    groups = {}
    for c, o in own.items():
        g = "hall" if o == "hall" else o
        groups.setdefault(g, []).append(c)
    miss = 0.0
    for g, cs in groups.items():
        band = L.rband.get(g)
        if not band:
            continue
        gx = sum(c[0] for c in cs) / float(len(cs))
        gy = sum(c[1] for c in cs) / float(len(cs))
        v = math.hypot(gx - cx, gy - cy) / R
        lo, hi = band
        miss += max(0.0, lo - v, v - hi) / max(0.05, hi - lo)
    for e in L.spoke_list:
        tip = e.get("tip", e["end"])
        run = e["L"] + (math.hypot(tip[0] - e["end"][0], tip[1] - e["end"][1]) if "lobby" in e else 0)
        miss += max(0.0, run - 52) / 10.0
        miss += max(0.0, math.hypot(tip[0] - cx, tip[1] - cy) / R - 0.62) / 0.06
    xs, ys = [c[0] for c in cells], [c[1] for c in cells]
    w, h = max(xs) - min(xs) + 1, max(ys) - min(ys) + 1
    asp = min(w, h) / float(max(w, h))
    miss += max(0.0, 0.78 - asp) / 0.05
    return miss


def layout(prog, params, sub, P, radial, room_size, rband=None, force=None):
    """Build a block plan. Of the slot search's top candidates, each is placed for real (cheap, no painting) and
    the one whose placed numbers miss the gate's bands least is kept. force: (cmap, smap, lob, ai) to build that
    assignment instead (the repair step's moves)."""
    import copy
    L = Layout(prog, params, sub, P, radial, room_size, rband)
    L.core()
    L.spoke_plan()
    L._gaps()
    L.assign()
    if force is not None:
        L.cands = [(0.0, 0.0) + tuple(force)]
    base_own, base_harea = dict(L.own), dict(L.harea)
    base_spokes = copy.deepcopy(L.spoke_list)
    state = L.r.getstate()
    best = None
    for idx, (sc, _, cmap, smap, lob, ai) in enumerate(L.cands):
        L.own, L.harea, L.spoke_list = dict(base_own), dict(base_harea), copy.deepcopy(base_spokes)
        L.r.setstate(state)
        L.cmap, L.smap, L.lob, L.ai_at = cmap, smap, lob, ai
        L.place()
        L.spokes()
        mi = placed_miss(L)
        if best is None or mi < best[0] - 1e-9:
            best = (mi, idx)
    mi, idx = best
    sc, _, cmap, smap, lob, ai = L.cands[idx]
    L.own, L.harea, L.spoke_list = dict(base_own), dict(base_harea), copy.deepcopy(base_spokes)
    L.r.setstate(state)
    L.cmap, L.smap, L.lob, L.ai_at = cmap, smap, lob, ai
    L.info["corners"] = cmap      # before the corner pick; updated after place()
    L.info["spokes"] = {"%s%+d" % (L.spoke_list[i]["side"], k): v for (i, k), v in smap.items() if v}
    L.info["placed_miss"] = round(mi, 3)
    L.place()
    L.info["corners"] = dict(L.cmap)
    L.spokes()
    L.maint()
    m = L.paint()
    L.info["R"] = round(L.R, 1)
    return m, L
