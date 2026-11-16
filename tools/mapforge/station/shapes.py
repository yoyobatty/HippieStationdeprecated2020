"""Station shapes besides the pinwheel. Each lays halls first, then grows departments into blocks that front them
(pinwheel.place_strips / trace_maint do the blocks: strips side by side, side streets, plazas, maint traced round the
outlines, side rooms off the halls), then the hall ends (arrivals, escape, the AI satellite, EVA) and solars.

    spine     one long main hall with doglegs, crossed by two ribs that run the station's full depth; Command and
              Service face each other across the middle, two departments per block in the four blocks outside the ribs;
              arrivals and escape off the spine's ends, the satellite and an EVA lock off rib ends (Kilo, Donut's long
              halls)
    ring      a hall loop with Command, Service, civic and dorms inside (two halves, a cross hall between them on
              bigger stations); the other departments face it from outside in a pinwheel, each loop side running on
              past its corner as a stub that is the next block's side hall and ends at arrivals, escape, the satellite
              or EVA (Box, Pubby)
"""
import itertools
import math
import random

from station import program as P
from station.layout import Plan, footprint, finish, HALL
from station.grow import grow_dept
from station import pinwheel as PW
from station.pinwheel import _add, _vec, LIKE_SAME, LIKE_NEAR, CORE_RING


def _ready(by):
    """Fronts for growing in a block: Command/Service rooms that want the main hall get it, the rest face their own
    halls; dorms and civic face the main hall where they asked for a hall."""
    for n in ("command", "service"):
        if n in by:
            for r in by[n].rooms:
                r.front = tuple(("ring" if r.id in CORE_RING else "dept") if k == "hall" else k for k in r.front)
    for n in ("dorms", "civic"):
        if n in by:
            by[n].where = "outer"
            for r in by[n].rooms:
                r.front = tuple("ring" if k == "hall" else k for k in r.front)


def grow_block(plan, by, strips, key, frame, ds, rnd, seed, left=True):
    """Departments ds grown and laid side by side in one block (not traced yet). -> the block's info."""
    locs, off, mw = grow_locs(by, key, ds, rnd, seed, left)
    return PW.place_strips(plan, by, strips, frame, key, locs, mw, seed, off, hall_left=left, trace=False)


def measure(by, key, block, seed, left=True):
    """A block's width and depth (W + mw, H + mw) before it is placed: a dry run on a scratch plan (place_strips draws
    from its own seeded random, so the real run lays it out the same)."""
    locs, off, mw = block
    scratch = Plan(0, 80)
    scratch.quads = {}
    i = PW.place_strips(scratch, by, [],((0, 0), (1, 0), (0, 1)), key, locs, mw, seed, off, hall_left=left,
                        trace=False)
    return i["W"] + mw, i["H"] + mw


def grow_locs(by, key, ds, rnd, seed, left=True):
    """-> (locs, off, mw): the departments grown for a block, the setback from its side hall, its maint width."""
    locs = []
    off = rnd.choice((0, 0, 0, 5, 8)) if left else 0
    for k, n in enumerate(ds):
        area = footprint(by[n]) / (0.72 if n in ("command", "service") else 0.6)
        asp_ = rnd.uniform(0.75, 1.3)
        Dm = max(14, int(round(math.sqrt(area * asp_))))
        w = max(14, int(round(area / Dm)))
        for attempt in range(10):
            loc = grow_dept(by[n], w, Dm, "%s.%s.%d" % (seed, key, attempt),
                            left_front="ring" if k == 0 and left and not off else None)
            if not loc.broken:
                break
            w += 4
            Dm += 3
        locs.append((n, w, loc))
    return locs, off, rnd.choice((1, 1, 2))


def _hall(plan, x0, y0, x1, y1):
    for x in range(min(x0, x1), max(x0, x1) + 1):
        for y in range(min(y0, y1), max(y0, y1) + 1):
            plan.floor.setdefault((x, y), "ring")
    plan.rooms.setdefault("ring", dict(kind="hall", public=True, label="", dept="hall"))


def _ends_and_solars(plan, by, strips, seed, rnd, ends, solar_blocks):
    """Solars off the named blocks' far corners, then each end: (what, start, out, perp) -> a tail and its feature."""
    keep_out = set()
    for key in solar_blocks:
        PW.corner_solar(plan, plan.quads[key], key, keep_out)
    laid = []
    for what, start, out, perp in ends:
        laid.append((what,) + PW.arm_tail(plan, start, out, perp, what, keep_out, rnd))
    for e in laid:
        PW.lay_end(plan, by, strips, seed, *e)


# ------------------------------------------------------------------------------------------------------------ spine
SPINE_LOTS = ("WN", "WS", "EN", "ES")


def spine_assign(names, rnd):
    """Eight departments into the four outer blocks (two each: index 0 by the rib, 1 out at the end) and which end
    arrivals is at."""
    slots = [(lot, k) for lot in SPINE_LOTS for k in range(2)]
    best = None
    perms = list(itertools.permutations(names))
    rnd.shuffle(perms)
    for perm in perms[:6000]:
        where = dict(zip(perm, slots))
        for ar in "WE":
            es = "E" if ar == "W" else "W"
            s = 0.0
            for (a, b), v in LIKE_SAME.items():
                if a in where and b in where and where[a][0] == where[b][0]:
                    s += v
            for (a, b), v in LIKE_NEAR.items():
                if a in where and b in where and where[a][0][0] == where[b][0][0]:
                    s += v
            if "cargo" in where and where["cargo"][0][0] == ar:
                s += 18 + 4 * where["cargo"][1]
            if "security" in where and where["security"][0][0] == es:
                s += 10
            if "science" in where and where["science"][0][0] == ar:
                s -= 8
            if "medical" in where and where["medical"][0][0] == es:
                s += 4
            for n in ("dorms", "civic", "security"):
                if n in where and where[n][1] == 0:
                    s += 6
            s += 25 * rnd.random()
            if best is None or s > best[0]:
                best = (s, dict(where), ar)
    return best[1], best[2]


def generate_spine(seed=1, crew=80):
    rnd = random.Random("spine|%s|%s" % (seed, crew))
    plan = Plan(seed, crew)
    plan.quads = {}
    depts = P.program(crew, seed, fill=0.88)
    by = {d.name: d for d in depts}
    _ready(by)
    names = [n for n in ("security", "medical", "science", "engineering", "atmos", "cargo", "dorms", "civic")
             if n in by]
    where, ar = spine_assign(names, rnd)
    es = "E" if ar == "W" else "W"
    lots = {lot: [n for n in sorted(names, key=lambda n: where[n][1]) if where[n][0] == lot] for lot in SPINE_LOTS}
    mid = {"MN": [n for n in ("command",) if n in by], "MS": [n for n in ("service",) if n in by]}
    if rnd.random() < 0.5:
        mid = {"MN": mid["MS"], "MS": mid["MN"]}
    plan.order = ["%s:%s" % (k, ",".join(v)) for k, v in list(lots.items()) + list(mid.items())]
    plan.notes.append("spine  " + "  ".join(plan.order) + "  arrivals %s end" % ar)
    strips = []
    # the main hall's rows in each stretch: a dogleg at each rib
    yW, yE = rnd.choice((0, 0, -4, 4, -6, 6)), rnd.choice((0, 0, -4, 4, -6, 6))
    R1 = 0
    # middle blocks first (their width sets where the second rib goes)
    info = {}
    info["MN"] = grow_block(plan, by, strips, "MN", ((R1 + 4, 4), (1, 0), (0, 1)), mid["MN"], rnd, seed)
    info["MS"] = grow_block(plan, by, strips, "MS", ((R1 + 4, -2), (1, 0), (0, -1)), mid["MS"], rnd, seed)
    Wmid = max(i["W"] + i["mw"] for i in (info["MN"], info["MS"])) + rnd.choice((0, 0, 3))
    for k in ("MN", "MS"):
        info[k]["Wfix"] = Wmid
    R2 = R1 + 4 + Wmid + 2
    frames = {"WN": ((R1 - 2, yW + 4), (-1, 0), (0, 1)), "WS": ((R1 - 2, yW - 2), (-1, 0), (0, -1)),
              "EN": ((R2 + 4, yE + 4), (1, 0), (0, 1)), "ES": ((R2 + 4, yE - 2), (1, 0), (0, -1))}
    for lot in SPINE_LOTS:
        if lots[lot]:
            info[lot] = grow_block(plan, by, strips, lot, frames[lot], lots[lot], rnd, seed)
    def dept_reach(i, lo, hi):
        """Farthest department tile from the main hall in the block's columns lo..hi, as an absolute y."""
        v = max([v + s_ for n, i0, w, d, f, loc, s_ in i["strips"] for (u, v) in loc.tiles if lo <= i0 + u <= hi]
                or [0])
        return i["c"][1] + i["b"][1] * v
    # each rib runs as far as the departments beside it (not into the bare ends of their blocks)
    sides = {1: [("WN", 0, 6, "left"), ("MN", 0, 6, "left")], 2: [("EN", 0, 6, "left"), ("MN", None, None, "right")]}
    south = {1: [("WS", 0, 6, "left"), ("MS", 0, 6, "left")], 2: [("ES", 0, 6, "left"), ("MS", None, None, "right")]}
    tops, bots = {}, {}
    for rib in (1, 2):
        for tab, sgn, out in ((sides, 1, tops), (south, -1, bots)):
            ys = []
            for k, lo, hi, _ in tab[rib]:
                if k not in info:
                    continue
                if lo is None:
                    lo, hi = info[k]["Wfix"] - 6, info[k]["Wfix"]
                ys.append(dept_reach(info[k], lo, hi))
            y = (max(ys) + 2) if sgn > 0 else (min(ys) - 2) if ys else (5 if sgn > 0 else -3)
            out[rib] = y
            for k, lo, hi, which in tab[rib]:
                if k in info:
                    info[k][which + "_len"] = abs(y - info[k]["c"][1]) - 2
    for k, i in info.items():
        PW.trace_maint(plan, i, seed, k)

    # halls: the spine's three stretches, the two ribs
    wext = max([info[k]["Wf"] for k in ("WN", "WS") if k in info] or [0])
    eext = max([info[k]["Wf"] for k in ("EN", "ES") if k in info] or [0])
    xw, xe = R1 - 2 - wext - 2, R2 + 4 + eext + 2
    _hall(plan, xw, yW, R1 + 2, yW + 2)
    _hall(plan, R1, 0, R2 + 2, 2)
    _hall(plan, R2, yE, xe, yE + 2)
    for k, x in ((1, R1), (2, R2)):
        _hall(plan, x, bots[k], x + 2, tops[k])
    # ends: arrivals/escape off the spine's ends; satellite and EVA off two of the four rib ends
    west = ((xw - 1, yW), (-1, 0), (0, 1))
    east = ((xe + 1, yE), (1, 0), (0, 1))
    ribs = [((R1, tops[1] + 1), (0, 1), (1, 0)), ((R2, tops[2] + 1), (0, 1), (1, 0)),
            ((R1, bots[1] - 1), (0, -1), (1, 0)), ((R2, bots[2] - 1), (0, -1), (1, 0))]
    rnd.shuffle(ribs)
    ends = [("arrivals",) + (west if ar == "W" else east), ("escape",) + (east if ar == "W" else west),
            ("sat",) + ribs[0], ("eva",) + ribs[1]]
    _ends_and_solars(plan, by, strips, seed, rnd, ends, [k for k in SPINE_LOTS if k in info])
    finish(plan, strips, by, lambda f, u, v: f(u, v), None)
    PW.windows(plan, seed)
    PW.orient(plan, random.Random("orient|%s" % seed))
    return plan


# ------------------------------------------------------------------------------------------------------------- ring
# clockwise: each outside block starts at one corner of the ring and runs along its side, past the next corner if it
# is longer than the side; that side's hall runs on past the corner as a stub, which is also the next block's side hall
RING_SIDES = ("N", "E", "S", "W")
NEXT = {"N": "E", "E": "S", "S": "W", "W": "N"}
OPP = {"N": "S", "S": "N", "E": "W", "W": "E"}


def ring_assign(names, rnd):
    """Six departments onto the ring's outside (two on N and S, one on E and W) and which stub arrivals leaves from
    (escape from the opposite one). A stub is beside its own block's far end and runs along the next block's side."""
    slots = [("N", 0), ("N", 1), ("S", 0), ("S", 1), ("E", 0), ("W", 0)]
    best = None
    perms = list(itertools.permutations(names))
    rnd.shuffle(perms)
    for perm in perms[:4000]:
        where = dict(zip(perm, slots))
        for ar in RING_SIDES:
            es = OPP[ar]
            s = 0.0
            for (a, b), v in LIKE_SAME.items():
                if a in where and b in where and where[a][0] == where[b][0]:
                    s += v
            for (a, b), v in LIKE_NEAR.items():
                if a in where and b in where and NEXT[where[a][0]] == where[b][0] or \
                        a in where and b in where and NEXT[where[b][0]] == where[a][0]:
                    s += v
            if "cargo" in where and where["cargo"][0] in (ar, NEXT[ar]):
                s += 18
            if "security" in where and where["security"][0] in (es, NEXT[es]):
                s += 8
            if "science" in where and where["science"][0] in (ar, NEXT[ar]):
                s -= 8
            s += 25 * rnd.random()
            if best is None or s > best[0]:
                best = (s, dict(where), ar)
    return best[1], best[2]


def generate_ring(seed=1, crew=80):
    """Box / Pubby style: a hall loop with Command, Service, civic and dorms inside it, the other departments facing it
    from outside in a pinwheel; the hall's sides run on past the corners as stubs that end at arrivals, escape, the
    satellite and an EVA lock."""
    rnd = random.Random("ring|%s|%s" % (seed, crew))
    plan = Plan(seed, crew)
    plan.quads = {}
    depts = P.program(crew, seed, fill=0.88)
    by = {d.name: d for d in depts}
    _ready(by)
    inner = [n for n in ("command", "service", "civic", "dorms") if n in by]
    names = [n for n in ("security", "medical", "science", "engineering", "atmos", "cargo") if n in by]
    where, ar = ring_assign(names, rnd)
    es = OPP[ar]
    side = {k: [n for n in sorted(names, key=lambda n: where[n][1]) if where[n][0] == k] for k in RING_SIDES}
    # inside: Command in one half, Service in the other, civic and dorms beside them
    halves = {"IN": [], "IS": []}
    cs = ["command", "service"]
    rnd.shuffle(cs)
    for n, k in zip(cs, ("IN", "IS")):
        if n in inner:
            halves[k].append(n)
    for n in inner:
        if n not in cs:
            (halves["IN"] if len(halves["IN"]) <= len(halves["IS"]) else halves["IS"]).append(n)
    for k in halves:
        rnd.shuffle(halves[k])
    plan.order = ["%s:%s" % (k, ",".join(v)) for k, v in list(side.items()) + list(halves.items())]
    plan.notes.append("ring  " + "  ".join(plan.order) + "  arrivals off the %s stub" % ar)
    strips = []
    # grow everything and measure it; the ring is sized to the inside, the outside overhangs as it needs
    blocks = {}
    for k, ds in list(side.items()) + list(halves.items()):
        if ds:
            blocks[k] = grow_locs(by, k, ds, rnd, seed, left=True)
    size = {k: measure(by, k, b, seed) for k, b in blocks.items()}
    ins = [size[k] for k in ("IN", "IS") if k in size]
    X = max([w + 9 for w, h in ins] + [30]) + rnd.choice((0, 0, 2, 3))
    # a cross hall between the two halves (W side to E side) half the time, always when there is room for it anyway
    need = sum(h + 1 for w, h in ins) + 8
    # (not on a small station: each hall is one a small crew has to walk past)
    cross = len(ins) == 2 and rnd.random() < 0.5 * min(1.0, max(0.0, (crew - 40) / 40.0))
    Y = max(need + (5 if cross else 0), 26) + rnd.choice((0, 0, 2, 3))
    if len(ins) == 2 and Y - need >= 7:
        cross = True
    LX0, LY0, LX1, LY1 = 0, 0, X - 1, Y - 1
    _hall(plan, LX0, LY1 - 2, LX1, LY1)
    _hall(plan, LX0, LY0, LX1, LY0 + 2)
    _hall(plan, LX0, LY0, LX0 + 2, LY1)
    _hall(plan, LX1 - 2, LY0, LX1, LY1)
    info = {}
    # inside halves: fronting the ring's inner edges, its W side down their left, its E side past their right
    rows = Y - 8
    fr = {"IN": ((LX0 + 4, LY1 - 4), (1, 0), (0, -1)), "IS": ((LX0 + 4, LY0 + 4), (1, 0), (0, 1))}
    for k in ("IN", "IS"):
        if k in blocks:
            locs, off, mw = blocks[k]
            info[k] = PW.place_strips(plan, by, strips, fr[k], k, locs, mw, seed, off, trace=False)
            info[k]["Wfix"] = X - 9
            info[k]["closed"] = True
    if "IN" in info and "IS" in info and cross:
        spare = rows - (size["IS"][1] + 1) - (size["IN"][1] + 1) - 5
        hs = size["IS"][1] + rnd.randint(0, spare)
        y0 = LY0 + 4 + hs + 2
        _hall(plan, LX0 + 3, y0, LX1 - 3, y0 + 2)
        info["IS"]["Hfix"] = hs
        info["IN"]["Hfix"] = (LY1 - 4) - (y0 + 4)
        info["IS"]["back_hall"] = info["IN"]["back_hall"] = True
        plan.notes.append("cross hall")
    elif "IN" in info and "IS" in info:
        info["IN"]["Hfix"] = rows - size["IS"][1] - 2
    else:
        for k in info:
            info[k]["Hfix"] = rows - 1
    # outside, clockwise
    frame = {"N": ((LX0 + 4, LY1 + 2), (1, 0), (0, 1)), "E": ((LX1 + 2, LY1 - 4), (0, -1), (1, 0)),
             "S": ((LX1 - 4, LY0 - 2), (-1, 0), (0, -1)), "W": ((LX0 - 2, LY0 + 4), (0, 1), (-1, 0))}
    side_len = {"N": X, "S": X, "E": Y, "W": Y}
    stub = {}
    for k in RING_SIDES:
        w = size[k][0] if k in size else 0
        nx = NEXT[k]
        d = size[nx][1] if nx in size else 0
        stub[k] = max(w + 4 - side_len[k], d + 2, 2) + rnd.choice((2, 2, 3, 5))
    # each stub: the side's hall on past its far corner; the exit at its end
    exits = {}
    L = stub["N"]
    _hall(plan, LX1 + 1, LY1 - 2, LX1 + L, LY1)
    exits["N"] = ((LX1 + L + 1, LY1 - 2), (1, 0), (0, 1))
    L = stub["E"]
    _hall(plan, LX1 - 2, LY0 - L, LX1, LY0 - 1)
    exits["E"] = ((LX1 - 2, LY0 - L - 1), (0, -1), (1, 0))
    L = stub["S"]
    _hall(plan, LX0 - L, LY0, LX0 - 1, LY0 + 2)
    exits["S"] = ((LX0 - L - 1, LY0), (-1, 0), (0, 1))
    L = stub["W"]
    _hall(plan, LX0, LY1 + 1, LX0 + 2, LY1 + L)
    exits["W"] = ((LX0, LY1 + L + 1), (0, 1), (1, 0))
    for k in RING_SIDES:
        if k in blocks:
            locs, off, mw = blocks[k]
            info[k] = PW.place_strips(plan, by, strips, frame[k], k, locs, mw, seed, off, trace=False)
    for k, i in info.items():
        PW.trace_maint(plan, i, seed, k)
    rest = [k for k in RING_SIDES if k not in (ar, es)]
    rnd.shuffle(rest)
    ends = [("arrivals",) + exits[ar], ("escape",) + exits[es], ("sat",) + exits[rest[0]], ("eva",) + exits[rest[1]]]
    _ends_and_solars(plan, by, strips, seed, rnd, ends, [k for k in RING_SIDES if k in info])
    finish(plan, strips, by, lambda f, u, v: f(u, v), None)
    PW.windows(plan, seed)
    PW.orient(plan, random.Random("orient|%s" % seed))
    return plan


LAYOUTS = {"pinwheel": PW.generate, "spine": generate_spine, "ring": generate_ring}


def generate(seed=1, crew=80, layout="mix"):
    if layout == "mix":
        names = sorted(LAYOUTS)
        layout = names[random.Random("layout|%s" % seed).randrange(len(names))]
    plan = LAYOUTS[layout](seed, crew)
    plan.notes.insert(0, "layout " + layout)
    return plan
