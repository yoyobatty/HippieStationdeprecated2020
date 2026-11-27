"""L2 department floorplans (plan: studies/learned_generator_plan.md): a department's block cut into rooms that share
their walls, around a corridor spine from its hall door, each room furnished by the learned synthesizer.

    from gen.learn import floorplan
    C = floorplan.plan("medical", target, W, Dmax, salt)     # a Comp-like department for gen/compose.py
    python tools/mapforge/gen/learn/floorplan.py medical 450 24     # print one plan as text

The block (frame: x along the hall front, y away from it; y 0 the front wall):
- a corridor spine from the front door: straight to the back ("I"), or a stem and a crossbar ("T") in a block wide
  and deep enough; 2 wide, 3 in a big department;
- the floor either side of it cut into rooms in strips across the corridor, one shared wall between neighbours; a
  strip deeper than DEEP splits into a front room on the corridor and a back room behind it, with a door between;
- rooms are the department's learned program (gen/rooms.py program_types: the types half the human departments
  have, the rarer by their share), sized by their stock sizes; the types humans put on the walkway (deptdb front)
  take the front slots nearest the door, the ones humans keep behind (surgery, servers, storage) the back slots;
- floors by type (deptdb turf: white medbay, dark server room), the corridor in the department's own floor;
- every room furnished by gen/learn/synth.py at paint time, in the station's coordinates.
Double walls and voids can't happen: every cell of the block is a room, the corridor or one wall line.
"""
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(HERE, "..", "..", "station"))
import deptdb  # noqa: E402

DEEP = 9             # a strip deeper than this splits into a front room and a back room
MIN_ROOM = 3         # a room's shortest side
ROOM_SHARE = 0.8     # room floor per cell of the room columns (the rest: wall lines between rooms and rows)


def _program(dept, target, r):
    """[(area, size)]: the department's room types (compose.room_items' pass 1 and 2), sized, to fill `target`."""
    import compose as CP
    import rooms as RM
    corr = RM.CORRIDOR_AREA.get(dept)
    items = CP.room_items(dept, target, r)
    # the department's room types every human station has, in the first pass whatever the draw (virology was left
    # out of 4 medical plans in 6, the chapel office out of 3 civic ones in 6, 2026-11-26)
    firsts = {a for p_, a, _ in items if p_ == 1}
    items = [(1, a, sz) for _, a, sz in RM.program_types().get(dept, []) if a in _must() and a not in firsts
             and a != corr and "checkpoint" not in a and "chamber" not in a] + list(items)
    # a security checkpoint at the department's door, as human maps keep one in medical, engineering, cargo and
    # science (5-10 of the 7 families; small one-door rooms the departments lacked: the one-door share and the 25th
    # percentile room ran out of band, 2026-11-26)
    cp = CHECKPOINT.get(dept)
    if cp:
        import roomdb
        v = sorted(r["tiles"] for r in roomdb.rooms() if r["area"] == cp)
        if v:
            items = [(1, cp, float(v[len(v) // 2]))] + list(items)
    # and the must-haves the program's types don't list for it (the chapel's office): the human median size
    sys.path.insert(0, os.path.join(HERE, "..", "..", "studies"))
    import stations as ST
    import roomdb
    listed = {a for _, a, _ in items}
    for a in sorted(_must()):
        if a in listed or a == corr or ST.group_of(a) != dept or any(w in a for w in NOT_MUST):
            continue
        v = sorted(r["tiles"] for r in roomdb.rooms() if r["area"] == a and r.get("main"))
        if v:
            items.insert(0, (1, a, float(v[len(v) // 2])))
    if corr in pieces() and not any(a == corr for _, a, _ in items):
        sz = next((t[2] for t in RM.program_types().get(dept, []) if t[1] == corr), 40)
        items = [(1, corr, sz)] + list(items)
    out, used, have = [], 0.0, set()
    budget = target * 0.8
    # each room's size drawn from its type's own spread on the stock maps (gen/learn/variety.py sizes: a bar is 28 to
    # 144 tiles there, a kitchen 40 to 64), not the type's median every time; and the department's biggest room may
    # be a hall past BIG, as about one stock room in ten is (stock p90 60-81, max 149-380; ours 63 with every
    # room at its median: the user 2026-11-26, "you don't go creative with room size and shape")
    import variety as VR
    spread = VR.model()["sizes"]
    hall = max((a for _, a, _ in items if a != corr and a not in pieces()),
               key=lambda a: max(sz for _, a_, sz in items if a_ == a), default=None)
    drawn = {}
    for pass_, area, size in items:
        if area == corr and area not in pieces():
            continue                # the corridor is that area (a pieces type, dorms' bedrooms, stays a room)
        if pass_ == 2 and (area in have or used >= budget):
            continue
        if area not in drawn:
            v = spread.get(area)
            if v:
                drawn[area] = v[r.randint(0, len(v) - 1)] / float(v[len(v) // 2])
            else:
                drawn[area] = r.choice((0.7, 0.85, 1.0, 1.0, 1.2, 1.45))
            drawn[area] = max(SIZE_LO, min(SIZE_HI, drawn[area]))
        # (the draw alone took the station's rooms up a size class: f30 quartiles 9/14/51 against the bands' 8/12/47;
        # every room but the hall a little under its draw, the floor freed goes to more small rooms)
        size = float(size) * drawn[area] * (1.0 if area == hall else SIZE_SCALE)
        size = max(9, min(float(size), RM.look_max(area) * 0.85 if RM.look_max(area) else size))
        pt = pieces().get(area)
        if pt:
            size += min(pt[0], PIECES_MOST) * (pt[1] + 3)
            if RM.look_max(area):
                # the gate measures the area whole (room and pieces): under the biggest human one (a 150-tile
                # bridge against the human 144 failed "oversized rooms", 2026-11-25)
                size = min(size, RM.look_max(area) * 0.85)
        else:
            # the human 90% room is 47-89 tiles; a type's stock (largest piece) size above that is one big hall,
            # and the department has many more rooms than its program lists: the department's one hall keeps its
            # size up to HALL, the rest stay under BIG
            size = min(size, HALL if area == hall else BIG)
        out.append((area, size))
        used += size
        have.add(area)
    return _fit_band(dept, out, target, r)


CLOSET_OVER = 1.05      # closets are added while the program stays under this share of its budget
# floor taken off a department's budget before its rooms are sized. Empty: tried for engineering (200, the engine
# block behind it) on f41 and the rooms came out bigger, not fewer: with fewer rooms in the program compose widened
# the block to reach its floor and the strips' depth sized the rooms (median 39 against the band's 33.75)
PLAN_LESS = {}


def _fit_band(dept, prog, target, r):
    """The program against the human department: its median room size into the band the gate learned from the human
    maps (space.room_size_<dept>: the big types scaled down, never under 9 tiles), and the department's small rooms
    (closets) added up to its learned room count (rooms.room_count) while floor is left. The stock sizes are each
    type's largest piece; human departments have many more small rooms (2026-11-25: medians 32-65 against 14-36)."""
    import gate as G
    import rooms as RM
    band = G.bands()[0].get("space.room_size_%s" % dept)
    if not prog:
        return prog
    count = RM.room_count(dept, target / 0.8)
    closets = _closets_for(dept, prog)
    used = sum(sz for _, sz in prog)
    budget = target * 0.82

    def med():
        v = sorted(sz for _, sz in prog)
        return v[len(v) // 2]
    # small rooms first: up to the learned count, and while the median is over the band (the big working rooms keep
    # their size: engineering's engine room scaled to 30 tiles lost the department its floor)
    while closets and used + CLOSET <= budget * CLOSET_OVER and (len(prog) < count or (band and med() > band[1])):
        a_ = r.choice(closets)
        if band and len(prog) >= 4 and sorted([sz for _, sz in prog] + [_closet_size(a_)])[(len(prog) + 1) // 2] < band[0]:
            break               # a closet more would take the median under the human band (civic: 13.5 vs 19-46)
        # closets of 4 to 10 tiles, not 8 every time (stock p10 6)
        csz = max(4.0, min(float(_cap(a_) or 99), _closet_size(a_) * r.choice((0.55, 0.75, 1.0, 1.0, 1.25))))
        prog.append((a_, csz))
        used += csz
        closets = _closets_for(dept, prog)
    used = sum(sz for _, sz in prog)
    if used < GROW_AT * budget and band:
        # far short of the floor the slot wants (crew 100: medical 498 of 1199): the rooms grow toward their human
        # biggest, the median held under the band's top
        k = min(GROW_MAX, GROW_AT * budget / max(1.0, used))
        cl = set(_closets(dept))
        # a room grows no bigger than its type's biggest stock main room (engineering's SMES room grew to 65 tiles
        # against the stock 18-48, tech storage to 51, and the department's median room read 51 against the band's
        # 13-34, f32)
        import variety as VR_
        top = {a: 1.05 * max(v) for a, v in VR_.model()["sizes"].items()}

        def grow(k_):
            return [(a, min(sz * k_, (_cap(a) or sz * k_) * 0.9, max(sz, top.get(a, sz * k_))) if a not in cl else sz)
                    for a, sz in prog]
        grown = grow(k)
        while k > 1.02 and sorted(sz for _, sz in grown)[len(grown) // 2] > band[1]:
            k = 1 + (k - 1) * 0.7
            grown = grow(k)
        prog = grown
    if band and med() > band[1]:
        # still over: the rooms over the band's middle come down toward it, the biggest (a working hall) kept
        mid = (band[0] + band[1]) / 2.0
        k = max(0.55, mid / float(med()))
        big = max(sz for _, sz in prog)
        prog = [(a, max(9.0, sz * k) if mid < sz < big else sz) for a, sz in prog]
    # a working room never under the size its work takes on the human maps (work_size): a 12-tile nanite lab held a
    # programmer and no chamber, a 15-tile mech bay no recharge port (crew 100 seed 7, 2026-11-26; the user: "focus on
    # function")
    cl = set(_closets(dept))
    prog = [(a, sz if a in cl else max(sz, float(work_size(a)))) for a, sz in prog]
    return prog


_WORK = None


def work_size(area):
    """The floor a room type's work takes: the smallest of its human main rooms (the biggest room of the area
    on each map), capped by BIG and under the gate's biggest room of the type; 0 when unknown."""
    global _WORK
    if _WORK is None:
        import roomdb
        from collections import defaultdict
        ms = defaultdict(list)
        for r in roomdb.rooms():
            if r.get("main"):
                ms[r["area"]].append(r["tiles"])
        _WORK = {a: min(v) for a, v in ms.items()}
    import rooms as RM
    # what its machines take: a tile each, a tile to stand at each, a walkway (4 tiles a machine, 6 more), never more
    # than its smallest human main room; a room with no machine in its kit has no floor of its own (an office or a
    # store shrinks with the band)
    n = len(_kit_machines(area))
    if not n:
        return 0
    w = min(_WORK.get(area, 0), 4 * n + 6)
    if RM.look_max(area):
        w = min(w, RM.look_max(area) * 0.85)
    return min(w, BIG)


CHECKPOINT = {"medical": "/area/security/checkpoint/medical", "engineering": "/area/security/checkpoint/engineering",
              "cargo": "/area/security/checkpoint/supply", "science": "/area/security/checkpoint/science/research"}
_MUSTS = None
# must-haves built elsewhere or not at all by a department plan: the crystal's room (net.engine), the burn chamber,
# the checkpoints (other departments' doors), the mining base and the holodeck (off-station or map-specific)
NOT_MUST = ("supermatter", "chamber", "checkpoint", "aux_base", "holodeck", "turret_protected", "tcommsat")


def _must():
    """gen/audit.py must_have(): the room types on every human station family but one."""
    global _MUSTS
    if _MUSTS is None:
        sys.path.insert(0, os.path.join(HERE, ".."))
        import audit
        _MUSTS = set(audit.must_have())
    return _MUSTS


def _big_kit(area):
    """The type's kit has a machine bigger than its tile (gen/audit.py BIG: the gravity generator)."""
    return any(p.startswith("/obj/machinery/gravity_generator") for p in _kit_machines(area))


def _kit_machines(area):
    """The floor machines of a room type's kit (gen/essentials.py, 70%+ of its human rooms): the nanite lab's
    chamber, console, hub and programmer."""
    try:
        sys.path.insert(0, os.path.join(HERE, ".."))
        import essentials as ES
        from forge import corpus as CO
        kit = ES.table().get(area, {}).get("kit", [])
    except Exception:                        # noqa: BLE001
        return []
    from forge import dmm as DM, kit as KT
    # machines and the dense pieces of the work (a head's locker, a suit storage, a display case): the CE's office
    # held its console and suit storage and no locker at 15 tiles (crew 100 seed 7, 2026-11-26)
    return [k["path"] for k in kit if k["share"] >= 0.7 and not k["path"].startswith(CO.INFRA)
            and not k["path"].startswith(("/obj/machinery/keycard_auth", "/obj/machinery/computer/security/telescreen",
                                          "/obj/item"))
            and (k["path"].startswith("/obj/machinery") or KT.is_dense_atom(DM.Atom(k["path"])))]


class Plan:
    """What compose.BU and paint_dept need of a department."""

    def __init__(self, dept, W, D):
        self.dept, self.W, self.Dmax = dept, W, D
        self.cells = {(x, y) for x in range(W) for y in range(D + 1)}
        self.floor, self.corr, self.doors, self.front = set(), set(), set(), set()
        self.rooms = []
        self.voids, self.chambers, self.panes = set(), [], set()
        self.ring = set()
        self.space = set()          # claimed but left as space (engineering's engine annex)
        self.learned = True

    def finish(self):
        self.wall = self.cells - self.floor - self.corr - self.doors - self.front - self.space


def _cut(length, sizes, depth):
    """Widths along a strip of `length` cells for rooms wanting `sizes` tiles at `depth` deep: one wall between each;
    the last takes what's left (or the leftover joins the last room when it's under MIN_ROOM)."""
    ws, left = [], length
    for s in sizes:
        w = max(MIN_ROOM, int(round(s / float(depth))))
        if left - w < MIN_ROOM + 1:
            ws.append(left)
            return ws
        ws.append(w)
        left -= w + 1
    if ws and left > 0:
        ws[-1] += left + 1      # nothing left to place: the last room takes the rest
    return ws


# The room a department is built round, across the far end of its block (the hull side): the stem is a short lobby
# that ends at its door, the rooms either side of the stem are its front, and rooms that fit beside it open off it.
# Stock cargo, 8 maps of 8: the bay on the hull with the supply dock into it, the office, QM and warehouse round it
# (studies/dept_specs/science_cargo.md). As one more room in a strip the bay came out 29-64 tiles, inside the block,
# and the supply shuttle docked onto the mining office (f37) or a 3-wide room (f35: no crate unloaded).
HUB = {"cargo": "/area/quartermaster/storage"}
HUB_SIDE = {"cargo": ("/area/quartermaster/miningdock", "/area/quartermaster/warehouse")}  # beside it, on the hull too
# room types that stand against the hub and open onto it (the QM's office: bay door and windows on 8 stock maps of 8;
# placed in turn it was beside the bay in 9 plans of 60)
HUB_BESIDE = {"cargo": ("/area/quartermaster/qm",)}
HUB_SHARE = (0.3, 0.4)  # of the department's floor (stock: 157 of about 440)
HUB_MIN, HUB_MAX = 60, 170      # (stock 75-249, median 141)
HUB_DEEP = (5, 11)      # rows of it, back from its door
HUB_ASPECT = 1.4        # as wide as this times its depth when the block allows
HUB_FRONT = 6           # rows of stem and rooms kept in front of it


def _hub_box(size, W, sx, cw):
    """(x0, x1, depth) of a hub room of `size` across the far end of a block W wide whose stem is at sx (cw wide):
    over the stem, near HUB_ASPECT, flush to a side wall where the cells left there are too few for a room."""
    inner = W - 2
    d = max(HUB_DEEP[0], min(HUB_DEEP[1], int(round(math.sqrt(size / HUB_ASPECT)))))
    w = max(cw + 2, int(round(size / float(d))))
    if inner - w < MIN_ROOM + 2:
        w = inner
    flank = max(MIN_ROOM, int(math.ceil(d / ASPECT_MAX)))       # a room beside it is at least this wide
    x0 = max(1, min(W - 1 - w, sx + cw // 2 - w // 2))
    if x0 - 2 < flank:
        x0 = 1
    x1 = x0 + w - 1
    if (W - 2) - (x1 + 2) + 1 < flank:
        x1 = W - 2
        if x0 > 1:
            x0 = x1 - w + 1
            if x0 - 2 < flank:
                x0 = 1
    w = x1 - x0 + 1
    d = max(HUB_DEEP[0], min(HUB_DEEP[1], int(round(size / float(w)))))
    return x0, x1, d


# departments planned again deeper when rooms of their program are left over (see plan()): all of them. At f37's
# budgets, 8 seeds each, medical left out surgery 4 times and cryo 4, security the range 5, command the meeting room 3
# and the vault 2, science its checkpoint 8, and floor reached 0.68-0.91 of budget; deeper, nothing is left out and
# floor reaches 0.81-1.12 (2026-11-26)
# Not engineering: its block is as wide as the engine behind it whatever its program, so deeper only added floor
# (share.engineering 0.113 against the band's 0.104 and a median room of 34.5-39 against 33.75, f40 and f41).
DEEPEN = ("cargo", "medical", "security", "science", "service", "civic", "command", "dorms")


def plan(dept, target, W, Dmax, salt, stem=None, _drop=(), _shrink=(), _deep=0):
    r = random.Random("floorplan|%s|%s" % (dept, salt))
    M = deptdb.model()
    prog = _program(dept, target - PLAN_LESS.get(dept, 0), r)
    if not prog:
        return None
    if _drop:
        prog = [it for i, it in enumerate(prog) if i not in _drop]
    if _shrink:
        # a must-have that didn't fit: its smaller form (half its pieces: three isolation cells, not six)
        prog = [(a, max(work_size(a) or 9, sz * 0.55) if a in _shrink else sz) for a, sz in prog]
    W = max(W, 11)
    # no wider than the program needs: a slot of 54 for 500 tiles of rooms left back rows with nothing to hold, and
    # the rooms in front ran their whole depth (4 x 25, crew 100 seed 7, 2026-11-25); the slot's rest stays free
    need_w = int(math.ceil(W_FIT * math.sqrt(sum(sz for _, sz in prog) / ROOM_SHARE)))
    if dept == "engineering":
        need_w = max(need_w, ANNEX_BLOCK_W + 1)
    W = min(W, max(17, need_w))
    cw = 3 if target >= 500 else 2
    inner_w = W - 2
    # deep enough for the program's rooms: each row across gives the room columns either side of the corridor,
    # less the wall lines between rooms and rows (ROOM_SHARE of the cells)
    # the corridor: stem from the front, T when the block is wide and deep
    lo, hi = stem if stem else (1, W - cw - 1)
    lo, hi = max(1, lo), min(W - cw - 1, hi)
    mid = (W - cw) // 2
    sx = max(lo, min(hi, mid + r.randint(-2, 2)))
    # each side of the stem is a room strip at least MIN_ROOM wide, or none at all (against the outer wall)
    if 1 < sx < MIN_ROOM + 2:
        sx = 1
    if W - 1 - (sx + cw) < MIN_ROOM + 1 and sx + cw < W - 1:
        sx = W - 1 - cw
    # the room the department is built round (HUB): out of the strips' program, across the block's far end
    hub = max((it for it in prog if it[0] == HUB.get(dept)), key=lambda it: it[1], default=None)
    hub_rows = 0
    total = sum(sz for _, sz in prog)
    cols = max(MIN_ROOM, inner_w - cw - 2)
    if hub is not None:
        hub_size = min(HUB_MAX, max(HUB_MIN, HUB_SHARE[0] * target, min(hub[1], HUB_SHARE[1] * target)))
        hx0, hx1, hub_d = _hub_box(hub_size, W, sx, cw)
        total -= sum(sz for a, sz in prog if a == hub[0])
        hub_rows = hub_d + 1
    D = int(math.ceil(total / (cols * ROOM_SHARE))) + 1 + hub_rows + _deep
    D = max(10, min(D, max(10, int(Dmax))))
    if hub is not None and D - 1 - hub_rows < HUB_FRONT:
        # a shallow slot: the hub gives rows up to the rooms in front of it, down to its least depth
        hub_d = max(HUB_DEEP[0], D - 2 - HUB_FRONT)
        hub_rows = hub_d + 1
        if D - 1 - hub_rows < MIN_ROOM + 1:
            hub, hub_rows = None, 0
    P = Plan(dept, W, D)
    P.hub = hub[0] if hub is not None else None
    shape = "I"         # T plans (a crossbar) wait for the crop below to learn their top strip
    yb = None
    if shape == "T":
        yb = max(7, min(D - MIN_ROOM - cw - 2, int(D * r.uniform(0.45, 0.65))))
        stem_end = yb - 1
    else:
        stem_end = D - 1 - hub_rows
    for x in range(sx, sx + cw):
        for y in range(1, stem_end + 1):
            P.corr.add((x, y))
        P.front.add((x, 0))
    if yb is not None:
        for x in range(1, W - 1):
            for y in range(yb, yb + cw):
                P.corr.add((x, y))
    # room strips: (rect x0, y0, x1, y1, side of the corridor: 'E'/'W' (corridor east/west of it), 'S'/'N')
    strips = []
    top = (yb - 2) if yb is not None else D - 1 - hub_rows
    if sx - 2 >= 1:
        strips.append(((1, 1, sx - 2, top), "E"))
    if sx + cw + 1 <= W - 2:
        strips.append(((sx + cw + 1, 1, W - 2, top), "W"))
    if yb is not None and yb + cw + 1 <= D - 1:
        strips.append(((1, yb + cw + 1, W - 2, D - 1), "S"))
    # slots: per strip, its length runs along the corridor; front rooms touch it, back rooms behind when deep
    front_val = lambda a: M["front"].get(a, 0.7)  # noqa: E731

    def door_p(a, b):
        return M["door"].get("|".join(sorted((a, b))), 0.05)

    def nb_p(a, b):
        """How often the two room types are neighbours on the human maps that have both (deptdb nb)."""
        return M.get("nb", {}).get("|".join(sorted((a, b))), 0.0)
    # the room types every human station has go first: placed last, virology was left out when the strips filled
    # (crew 100 seed 7 f10 and crew 90 seed 31 had none, 2026-11-26)
    must = _must()
    walkway = sorted(prog, key=lambda it: (it[0] not in must, -front_val(it[0])))
    if hub is not None:
        walkway = [it for it in walkway if it[0] != hub[0]]     # one of it, and not in a strip
    behind = [it for it in walkway if front_val(it[0]) < 0.5]
    walkway = [it for it in walkway if front_val(it[0]) >= 0.5]
    # rooms beside the hub, across the rest of the block's far end, each opening off it: a type the human maps join
    # to it and near the size of the cells there (the mining dock first: its shuttle wants the hull as well)
    hub_flanks = []
    if hub is not None:
        for fx0, fx1, door_x in ((1, hx0 - 2, hx0 - 1), (hx1 + 2, W - 2, hx1 + 1)):
            fw = fx1 - fx0 + 1
            if fw < MIN_ROOM:
                continue
            fa = fw * hub_d
            q_ = [it for it in walkway + behind if not pieces().get(it[0]) and not _big_kit(it[0])
                  and _pair_ok(hub[0], it[0]) and 0.5 * fa <= it[1] <= 1.8 * fa]
            pick = None
            if q_:
                side_ = HUB_SIDE.get(dept, ())
                pick = min(q_, key=lambda it: (side_.index(it[0]) if it[0] in side_ else len(side_),
                                               abs(math.log(it[1] / float(fa)))))
                (walkway if pick in walkway else behind).remove(pick)
            hub_flanks.append((fx0, fx1, door_x, pick))
    rid = 0

    def add_room(area, cells, door_cells):
        nonlocal rid
        P.floor |= cells
        P.doors |= door_cells
        P.rooms.append(dict(area=area, F=set(cells), R=set(), gen=True, id=rid, door=next(iter(door_cells), None)))
        if _big_kit(area):
            # a room with a machine bigger than its tile keeps the rectangle it was placed with: no jog, cut or
            # shape shift (the gravity generator's room came out 7x3, 9x3 or cut in two in 39 engineering plans of
            # 60, gen/learn/plancheck.py "big machine room under 5x5"; f42 had no seat for its 3x3)
            P.rooms[-1]["whole"] = True
        rid += 1

    def rect(side, x0, y0, x1, y1, a0, a1, b0, b1):
        """Cells of a strip's sub-rectangle: a along the corridor [a0, a1], b away from it [b0, b1] (0 = next to the
        corridor's wall line)."""
        if side == "E":     # corridor east: b runs west from x1
            return {(x, y) for y in range(y0 + a0, y0 + a1 + 1) for x in range(x1 - b1, x1 - b0 + 1)}
        if side == "W":
            return {(x, y) for y in range(y0 + a0, y0 + a1 + 1) for x in range(x0 + b0, x0 + b1 + 1)}
        # along x: "S" the corridor south of the strip, "N" north of it; "Sr"/"Nr" the along running west from x1
        # (a spur's rooms fill from the stem outward)
        xs = range(x0 + a0, x0 + a1 + 1) if side in ("S", "N") else range(x1 - a1, x1 - a0 + 1)
        ys = range(y0 + b0, y0 + b1 + 1) if side in ("S", "Sr") else range(y1 - b1, y1 - b0 + 1)
        return {(x, y) for x in xs for y in ys}

    def wall_cell(side, x0, y0, x1, y1, a, b):
        """The wall cell at along-position a, b away from the corridor (b = -1: the corridor's own wall line)."""
        if side == "E":
            return (x1 - b, y0 + a)
        if side == "W":
            return (x0 + b, y0 + a)
        return ((x0 + a) if side in ("S", "N") else (x1 - a), (y0 + b) if side in ("S", "Sr") else (y1 - b))

    # strip states; each room goes to the strip whose next free spot is nearest the entrance (both sides of the
    # corridor fill from the front back, as human departments do)
    st = []
    for (x0, y0, x1, y1), side in strips:
        along_x = side in ("S", "N")
        length = (x1 - x0 + 1) if along_x else (y1 - y0 + 1)
        depth = (y1 - y0 + 1) if along_x else (x1 - x0 + 1)
        if length < MIN_ROOM or depth < MIN_ROOM:
            continue
        # how far the strip's start is from the front door, in corridor tiles
        base = (yb + cw) if side in ("S", "N") else y0
        st.append(dict(g=(x0, y0, x1, y1), side=side, length=length, depth=depth, pos=0, last=None, base=base))

    closets = _closets_for(dept, [it for it in prog if it[0] not in _closets(dept)])
    tails = []      # (strip, its length before its tail room was cut off): the block is never cropped past it

    def place_room(S_, area, size):
        x0, y0, x1, y1 = S_["g"]
        side, length, depth, pos = S_["side"], S_["length"], S_["depth"], S_["pos"]
        # near square from its size (human rooms: median aspect 0.67-0.75); the strip's depth left behind it is a
        # back row when there's room for one (a room that ran the strip's whole depth came out long and thin, and
        # twice the human size, 2026-11-25)
        side_ = math.sqrt(size) * r.uniform(0.9, 1.15)
        d = max(MIN_ROOM, min(depth, int(round(side_))))
        if _big_kit(area) and depth >= 5:
            d = max(d, 5)       # a 3x3 machine and a way round it (the gravity generator sealed its 4x4 room)
        if _need(area) <= depth:
            d = max(d, _need(area))     # a pens/cells room deep enough for its row and the hall before it
        if depth - d - 1 < MIN_ROOM:
            d = depth
        w = max(MIN_ROOM, int(round(size / float(d) * r.uniform(0.9, 1.1))))
        if _need(area):
            # a pens/cells room is at least as wide as it is deep for its row (an 11 x 3 surgery kept no
            # operating rooms, 2026-11-25)
            w = max(w, min(length - pos, _need(area) + 2))
        # no bars: at most ASPECT_MAX times as long as deep (a narrow slot gave science 3 x 15 rooms, crew 100 seed
        # 7; human rooms' median aspect is 0.67-0.75)
        w = min(w, max(MIN_ROOM, int(ASPECT_MAX * d)))
        if _big_kit(area):
            w = max(w, min(length - pos, 5))
        if length - pos - w - 1 < MIN_ROOM + 1 and length - pos <= ASPECT_MAX * d + MIN_ROOM + 1:
            w = length - pos
        back = depth - d - 1 if d < depth else 0
        cells = rect(side, x0, y0, x1, y1, pos, pos + w - 1, 0, d - 1)
        da = pos + (r.randint(0, w - 1) if w > 2 else 0)
        add_room(area, cells, {wall_cell(side, x0, y0, x1, y1, da, -1)})
        front_room = P.rooms[-1]
        bk = None
        if back:
            # the back row behind this front room, filled left to right with rooms that go behind (each its own
            # size, a door to the front room); what's left of the row joins the front room (an L)
            a = pos
            while a <= pos + w - 1:
                # only rooms that fit the row's span whole (the bar went behind a kitchen as a 17-tile room, 2026-11-26)
                # and only rooms a human map opens onto this front room (surgery went behind medical storage, its
                # one door through the store, f21c)
                # (a room for a machine bigger than its tile only where the row gives it 5 by 5: behind a 4-row
                # tech storage the gravity generator's room was 7 x 4, f42)
                pool_ = [it for it in (behind or walkway[-3:]) if _need(it[0]) <= back
                         and (pos + w - a) * back >= 0.7 * it[1] and _pair_ok(area, it[0])
                         and (not _big_kit(it[0]) or (pos + w - a >= 5 and back >= 5))]
                span = pos + w - a
                if span < 2:
                    break
                if pool_:
                    pick = max(pool_, key=lambda it: (max(door_p(area, it[0]), nb_p(area, it[0])), -it[1]))
                    (behind if pick in behind else walkway).remove(pick)
                else:
                    # nothing of the program left to go behind: one of the department's closets (human departments
                    # keep many small rooms: their 10% room is 4-8 tiles, 2026-11-25 we had 10.5), each type a
                    # bounded number of times, else a type the department lacks; else the row joins the front room
                    # (a 22 x 6 brig, 2026-11-25)
                    cl_ = [c_ for c_ in _closets_for(dept, [(q["area"], 0) for q in P.rooms]) if _pair_ok(area, c_)]
                    if cl_ and _median_ok(P, dept, CLOSET):
                        a_ = r.choice(cl_)
                        pick = (a_, _closet_size(a_))
                    else:
                        f_ = _filler(dept, P, max(CLOSET, 3 * back), next_to=area)
                        if not f_:
                            break
                        pick = (f_, float(max(CLOSET, 3 * back)))
                        # a type the program still has to place is placed here, once, at its program size: struck from
                        # the queue (science got two R&D labs when the program's own lab came up after the filler's,
                        # f23; skipping pending types lost cargo its mining dock in 7 plans of 15; at the filler's
                        # size the R&D lab came out 17 tiles and the server room empty, f25). Only where it fits.
                        for q_ in (walkway, behind):
                            it_ = next((it_ for it_ in q_ if it_[0] == f_), None)
                            if it_ is not None:
                                if span * back < 0.7 * it_[1]:
                                    pick = None
                                else:
                                    q_.remove(it_)
                                    pick = (f_, it_[1])
                                break
                        if pick is None:
                            break
                bw = max(2, min(span, int(round(pick[1] / float(back))), max(MIN_ROOM, int(ASPECT_MAX * back))))
                if _big_kit(pick[0]):
                    bw = min(span, max(bw, 5))
                if span - bw - 1 < 2:
                    bw = span
                bcells = rect(side, x0, y0, x1, y1, a, a + bw - 1, d + 1, depth - 1)
                add_room(pick[0], bcells, {wall_cell(side, x0, y0, x1, y1, a + bw // 2, d)})
                bk = P.rooms[-1]
                a += bw + 1
            if a <= pos + w - 1:
                if bk is not None and pos + w - a <= MIN_ROOM:
                    # a few cells past the last back room: its own (as the front room's they were a leg one or two
                    # wide, and from the wall line on they left the two rooms open to each other: gen/learn/
                    # plancheck.py "rooms touch", 208 in 84 plans, 2026-11-26)
                    extra = rect(side, x0, y0, x1, y1, a - 1, pos + w - 1, d + 1, depth - 1)
                    bk["F"] |= extra
                else:
                    extra = rect(side, x0, y0, x1, y1, a, pos + w - 1, d, depth - 1)
                    front_room["F"] |= extra
                P.floor |= extra
                if bk is None:
                    d = depth
        S_["last"] = (front_room, bk, d)
        S_["pos"] = pos + w + 1

    # a must-have back room with a row of pieces (virology and its isolation cells) at a strip's far end before the
    # strips fill from the front: placed in turn it came up with a strip's last 5 tiles and kept no cells (medical
    # plans 0 pieces in both seeds, the human virology 136 tiles with 3-6 cells, 2026-11-26)
    for it in [it for it in behind if it[0] in must and pieces().get(it[0])]:
        pt = pieces()[it[0]]
        need = int(round(pt[1] / max(2.0, round(math.sqrt(pt[1]))))) + 1 + MIN_ROOM
        deep_ = [S_ for S_ in st if S_["depth"] >= need and S_["pos"] == 0]
        if not deep_:
            continue
        S_ = max(deep_, key=lambda S_: (S_["depth"], S_["length"]))
        w_ = max(MIN_ROOM, int(math.ceil(it[1] / float(S_["depth"]))))
        w_ = min(w_, int(ASPECT_MAX * S_["depth"]))
        if S_["length"] - w_ - 1 < 2 * MIN_ROOM + 2:
            continue
        S_["pos"] = S_["length"] - w_
        place_room(S_, it[0], it[1])
        behind.remove(it)
        tails.append((S_, S_["length"]))
        S_["length"] -= w_ + 1
        S_["pos"] = 0
        S_["last"] = None
    def open_bay(S_):
        """A side corridor off the stem through strip S_ at its next free spot: two rows of rooms front it, one each
        side (sub-strips added to st), and now and then a room closes its far end. Human departments branch (a wing
        of labs off the main hall, the corridor down to a head's office); one stem with a strip each side made every
        department the same comb (the user 2026-11-26: "you don't go creative with room size and shape")."""
        x0, y0, x1, y1 = S_["g"]
        side, pos, depth = S_["side"], S_["pos"], S_["depth"]
        cs = 2
        wb, wa = r.randint(BAY_ROOM[0], BAY_ROOM[1]), r.randint(BAY_ROOM[0], BAY_ROOM[1])
        Lb = wb + cs + wa + 2
        if S_["length"] - pos - Lb - 1 < MIN_ROOM + 1:
            return False
        ya = y0 + pos
        rows = range(ya + wb + 1, ya + wb + 1 + cs)
        # a room across the far end, when one of the next rooms is the size for it
        ec = 0
        cap_it = None
        if depth >= 12 and r.random() < BAY_CAP_P:
            ec = r.randint(3, 5)
            q_ = [it for it in walkway + behind if not pieces().get(it[0]) and not _big_kit(it[0])
                  and 0.6 * Lb * ec <= it[1] <= 1.5 * Lb * ec]
            cap_it = q_[0] if q_ else None
            if cap_it is None:
                ec = 0
        gap = (ec + 1) if ec else 0
        if side == "E":         # the stem east of the strip: the spur runs west from it
            xb0, xb1 = x0 + gap, x1
            spur = {(x, y) for x in range(xb0, x1 + 2) for y in rows}
            subs = ("Nr", "Sr")
            cap = {(x, y) for x in range(x0, x0 + ec) for y in range(ya, ya + Lb)}
            cap_door = (x0 + ec, rows[0])
        else:
            xb0, xb1 = x0, x1 - gap
            spur = {(x, y) for x in range(x0 - 1, xb1 + 1) for y in rows}
            subs = ("N", "S")
            cap = {(x, y) for x in range(x1 - ec + 1, x1 + 1) for y in range(ya, ya + Lb)}
            cap_door = (x1 - ec, rows[0])
        if xb1 - xb0 + 1 < 2 * MIN_ROOM + 1:
            return False
        P.corr |= spur
        base = S_["base"] + pos + wb + 1
        st.append(dict(g=(xb0, ya, xb1, ya + wb - 1), side=subs[0], length=xb1 - xb0 + 1, depth=wb, pos=0, last=None,
                       base=base, sub=True))
        st.append(dict(g=(xb0, ya + wb + cs + 2, xb1, ya + Lb - 1), side=subs[1], length=xb1 - xb0 + 1, depth=wa, pos=0,
                       last=None, base=base, sub=True))
        if cap_it is not None:
            (walkway if cap_it in walkway else behind).remove(cap_it)
            add_room(cap_it[0], cap, {cap_door})
        S_["pos"] = pos + Lb + 1
        S_["last"] = None
        S_["bays"] = S_.get("bays", 0) + 1
        return True

    while walkway or behind:
        open_ = [S_ for S_ in st if S_["length"] - S_["pos"] >= MIN_ROOM]
        if not open_:
            break
        # a bay where the next room would go, when the strip is deep enough for a spur and rooms are left for it
        near_ = min(open_, key=lambda S_: S_["base"] + S_["pos"])
        if not near_.get("sub") and near_["side"] in ("E", "W") and near_["depth"] >= BAY_DEPTH and near_["pos"] > 0 \
                and near_.get("bays", 0) < BAY_MOST and near_.get("bay_at") != near_["pos"] \
                and sum(1 for it in walkway + behind if not pieces().get(it[0])) >= 4:
            near_["bay_at"] = near_["pos"]
            if r.random() < BAY_P and open_bay(near_):
                continue
        # a must-have type before the rest, wherever it was sorted (virology goes behind and the strips filled
        # before it came up)
        nxt = next((it for it in walkway if it[0] in must), None) or next((it for it in behind if it[0] in must), None)
        if nxt is not None:
            (walkway if nxt in walkway else behind).remove(nxt)
            area, size = nxt
        else:
            area, size = walkway.pop(0) if walkway else behind.pop(0)
        if _big_kit(area):
            # 5 by 5 at least, along the strip as well as across it: in a strip's last 4 rows the gravity generator's
            # room was 6 x 4 and its 3x3 had no seat (f42, all four rounds: "function: big machines"). No strip with
            # the rows left: the plan again, deeper (any department: the machine has to stand)
            big_ = [S_ for S_ in open_ if S_["depth"] >= 5 and S_["length"] - S_["pos"] >= 5]
            if not big_ and _deep < 3 * 8 and D < int(Dmax):
                return plan(dept, target, W, Dmax, salt, stem, _drop, _shrink, _deep + 5)
            open_ = big_ or [S_ for S_ in open_ if S_["depth"] >= 5] or open_
        pt = pieces().get(area)
        if pt:
            # a room with a row of pieces wants a strip deep enough for them and a room in front of them
            need = int(round(pt[1] / max(2.0, round(math.sqrt(pt[1]))))) + 1 + MIN_ROOM
            deep_ = [S_ for S_ in open_ if S_["depth"] >= need]
            # ... and long enough left: the row and the room in front fit one way or the other (a prison in a strip's
            # last 4 rows was 12 x 4 and kept no cells, 6 plans of 12; stock 3 cells a map, 2026-11-26)
            long_ = [S_ for S_ in deep_ if S_["length"] - S_["pos"] >= need - 1]
            if not long_ and dept in DEEPEN and _deep < 3 * 8 and D < int(Dmax):
                return plan(dept, target, W, Dmax, salt, stem, _drop, _shrink, _deep + need)
            open_ = long_ or deep_ or open_
        # a strip with room left for it whole, nearest the entrance; else the one with most left (the bar went into a
        # strip's last 17 tiles, 2026-11-26)
        roomy = [S_ for S_ in open_ if (S_["length"] - S_["pos"]) * S_["depth"] >= 0.8 * size]
        if roomy:
            S_ = min(roomy, key=lambda S_: (S_["base"] + S_["pos"], r.random()))
        else:
            S_ = max(open_, key=lambda S_: ((S_["length"] - S_["pos"]) * S_["depth"], r.random()))
        at_ = S_["base"] + S_["pos"]
        place_room(S_, area, size)
        # its partner next to it, in the same strip or straight across the corridor: the room type the human maps put
        # beside it (a kitchen's cold room, the robotics lab's mech bay, the chapel's office); the cold room came out
        # across the department from the kitchen (crew 100 seed 7, 2026-11-26)
        rest = [it for it in walkway + behind if it[0] != area]
        if rest:
            y_ = max(rest, key=lambda it: (nb_p(area, it[0]), -it[1]))
            if nb_p(area, y_[0]) >= PAIR and not pieces().get(y_[0]):
                # only where it fits whole (squeezed into a strip's end, a bar came out 12 tiles)
                fits = [T_ for T_ in st if (T_["length"] - T_["pos"]) * T_["depth"] >= 1.2 * y_[1]
                        and T_["length"] - T_["pos"] >= MIN_ROOM
                        and (T_ is S_ or abs(T_["base"] + T_["pos"] - at_) <= 6)]
                if fits:
                    T_ = S_ if S_ in fits else min(fits, key=lambda T_: abs(T_["base"] + T_["pos"] - at_))
                    (walkway if y_ in walkway else behind).remove(y_)
                    place_room(T_, y_[0], y_[1])
    # rooms of the program left over when the strips filled, and the slot has depth to spare: the plan again, deeper by
    # the rows they take (rooms come out bigger than their program size where a strip's depth rounds them up, so the
    # strips fill before the program does: cargo's mining dock was left out of 9 plans in 72 and came back as a
    # 9-tile room cut off the checkpoint, gen/learn/plancheck.py 2026-11-26)
    left_prog = [it for it in walkway + behind if it[0] not in _closets(dept) and it[1] >= 9]
    if left_prog and dept in DEEPEN and _deep < 3 * 8 and D < int(Dmax):
        rows = int(math.ceil(sum(sz for _, sz in left_prog) / (cols * ROOM_SHARE))) + 1
        return plan(dept, target, W, Dmax, salt, stem, _drop, _shrink, _deep + min(8, max(3, rows)))
    # a must-have type left over when the strips filled: the plan again without the biggest optional rooms (crew 100
    # seed 7's medical had no virology: 136 tiles, sorted behind, came up after the strips were full, 2026-11-26)
    left_must = [it for it in walkway + behind if it[0] in must]
    if left_must and not _shrink:
        return plan(dept, target, W, Dmax, salt, stem, _drop, tuple(a for a, _ in left_must), _deep)
    if left_must and len(_drop) < 4:
        need_ = sum(sz for _, sz in left_must)
        import rooms as RM_
        prev = {a: f for f, a, _ in RM_.program_types().get(dept, [])}
        # the rarest types on the human maps first (a surgery went before a second storage, 2026-11-26), repeats of a
        # type before its first, then the biggest
        prog0 = _program(dept, target - PLAN_LESS.get(dept, 0), random.Random("floorplan|%s|%s" % (dept, salt)))
        seen_a = set()
        rank = []
        for i, (a, sz) in enumerate(prog0):
            rank.append((a in seen_a, prev.get(a, 0), sz, i, a))
            seen_a.add(a)
        opt = sorted(((not rep, pv, -sz, i) for rep, pv, sz, i, a in rank if a not in must and i not in _drop))
        drop, got = list(_drop), 0.0
        for _, _, negsz, i in opt:
            sz = -negsz
            if got >= need_:
                break
            drop.append(i)
            got += sz
        if len(drop) > len(_drop):
            return plan(dept, target, W, Dmax, salt, stem, tuple(drop), _shrink, _deep)
    # the block ends where its longest strip's rooms end: rows past that go (the corridor and walls with them),
    # so a strip's leftover is only what its side lacks against the other
    # (a tail room ends at its strip's old length: as a room placed in turn, pos - 1 after it)
    used = max([S_["pos"] - 1 for S_ in st if S_["pos"] > 0 and not S_.get("sub")] + [end_ for _, end_ in tails] or [0])
    hub_rm = None
    if hub is not None:
        # the strips end where their rooms end, the hub right past them: a wall row with its door at the stem's end,
        # its rows, the block's back wall
        ds = used if 0 < used < D - 1 - hub_rows else D - 1 - hub_rows
        newD = ds + hub_d + 2
        P.corr = {c for c in P.corr if c[1] <= ds}
        P.cells = {c for c in P.cells if c[1] <= newD}
        P.Dmax = newD
        D = newD
        for S_ in st:
            if not S_.get("sub"):
                S_["length"] = min(S_["length"], ds)
        y0h, y1h = ds + 2, ds + 1 + hub_d
        for fx0, fx1, door_x, pick in hub_flanks:
            if pick is not None:
                add_room(pick[0], {(x, y) for x in range(fx0, fx1 + 1) for y in range(y0h, y1h + 1)},
                         {(door_x, y0h + hub_d // 2)})
                P.rooms[-1]["hub_side"] = True
            elif (hx1 - hx0 + 1) + (fx1 - fx0 + 2) <= ASPECT_MAX * hub_d \
                    and ((hx1 - hx0 + 1) + (fx1 - fx0 + 2)) * hub_d <= 1.5 * hub_size:
                hx0, hx1 = min(hx0, fx0), max(hx1, fx1)     # no room for the cells beside it: the hub's own
            # else the cells are given up (reshape.trim): the block's outline steps in at its far corner
        add_room(hub[0], {(x, y) for x in range(hx0, hx1 + 1) for y in range(y0h, y1h + 1)},
                 {(sx + r.randint(0, cw - 1), ds + 1)})
        hub_rm = P.rooms[-1]
        hub_rm["hub"] = True
    elif used > 0 and used < D - 1:
        newD = used + 1             # the back wall's row
        P.corr = {c for c in P.corr if c[1] < newD}
        P.cells = {c for c in P.cells if c[1] <= newD}
        P.Dmax = newD
        D = newD
        for S_ in st:
            if not S_.get("sub"):
                S_["length"] = min(S_["length"], used)
    if os.environ.get("FP_DEBUG"):
        print("strips", [(S_["side"], S_["length"], S_["depth"], S_["pos"]) for S_ in st], "D", D, "store", _storage(dept, prog))
    store = _storage(dept, prog)
    import gate as G
    band_ = G.bands()[0].get("space.room_size_%s" % dept)
    # a stem strip that ends short of the block's end by a few tiles may stop there: the block's outline steps in
    # (reshape.trim gives the cells up) instead of every department ending square
    longest = max([S_["pos"] for S_ in st if not S_.get("sub")] or [0])
    for S_ in st:
        left_ = S_["length"] - S_["pos"]
        if not S_.get("sub") and dept != "engineering" and hub is None and S_["pos"] > 0 and S_["pos"] < longest \
                and MIN_ROOM <= left_ <= UNEVEN_MAX and r.random() < UNEVEN_P:
            S_["length"] = S_["pos"] - 1
    for S_ in st:
        # a strip end a room long or more: the department's storage room (human departments keep their stores at
        # the back), not a neighbour stretched over it
        while S_["length"] - S_["pos"] >= MIN_ROOM + 1:
            # closet-sized rooms, not one store the size of what's left (seven storage rooms of 18-51 tiles in one
            # science, 2026-11-25); each closet type at most REPEAT_MAX times, then a type the department lacks
            cl_ = _closets_for(dept, [(rm["area"], 0) for rm in P.rooms])
            left_ = (S_["length"] - S_["pos"]) * S_["depth"]
            sizes_ = sorted(len(q["F"]) for q in P.rooms)
            if cl_ and not _median_ok(P, dept, CLOSET):
                cl_ = []        # one closet more takes the median under the human band: a room the size of what's left
            if cl_:
                pick = r.choice(cl_)
                place_room(S_, pick, min(2 * CLOSET, _cap(pick) or 2 * CLOSET))
                continue
            pick = _filler(dept, P, left_) or store
            if not pick:
                break
            place_room(S_, pick, min(left_, _cap(pick) or left_))
    for S_ in st:
        x0, y0, x1, y1 = S_["g"]
        side, length, depth, pos = S_["side"], S_["length"], S_["depth"], S_["pos"]
        if 0 < pos < length and S_["last"] is not None:
            # the strip's end no room took: the last rooms grow to it, over the wall line that would have closed them
            fr_, bk_, d_ = S_["last"]
            extra = rect(side, x0, y0, x1, y1, pos - 1, length - 1, 0, d_ - 1 if bk_ else depth - 1)
            fr_["F"] |= extra
            P.floor |= extra
            if bk_:
                extra = rect(side, x0, y0, x1, y1, pos - 1, length - 1, d_ + 1, depth - 1)
                bk_["F"] |= extra
                P.floor |= extra
        elif pos == 0:
            # a strip no room reached: it is not the department's (the block's box shrinks to what's used later)
            pass
    if hub_rm is not None:
        # a HUB_BESIDE type not against the hub trades places with the room that is, the one nearest its size (not
        # a front room, a pieces room or a machine's)
        def against(q_):
            return any(y == ds and (x, ds + 2) in hub_rm["F"] for (x, y) in q_["F"])
        for want_ in HUB_BESIDE.get(dept, ()):
            mine_ = [q_ for q_ in P.rooms if q_["area"] == want_ and not q_.get("piece")]
            if not mine_ or any(against(q_) for q_ in mine_):
                continue
            q0 = max(mine_, key=lambda q_: len(q_["F"]))
            cands_ = [q_ for q_ in P.rooms if q_ is not hub_rm and not q_.get("hub_side") and not q_.get("piece")
                      and not q_.get("whole") and against(q_) and q_["area"] not in pieces()
                      and q_["area"] not in HUB_BESIDE.get(dept, ()) and front_val(q_["area"]) < 0.5
                      and 0.45 <= len(q_["F"]) / float(len(q0["F"])) <= 2.4]
            if cands_:
                q1 = min(cands_, key=lambda q_: abs(math.log(len(q_["F"]) / float(len(q0["F"])))))
                q0["area"], q1["area"] = q1["area"], q0["area"]
        # the rooms that end against the hub open onto it, where the human maps put the two side by side (the QM's
        # office and the cargo office onto the bay, 8 and 7 maps of 8)
        for rm_ in P.rooms:
            if rm_ is hub_rm or rm_.get("hub_side") or not _pair_ok(rm_["area"], hub[0]) \
                    or nb_p(rm_["area"], hub[0]) < PAIR:
                continue
            xs_ = sorted(x for (x, y) in rm_["F"] if y == ds and (x, ds + 2) in hub_rm["F"]
                         and (x - 1, ds) in rm_["F"] and (x + 1, ds) in rm_["F"])
            if xs_:
                P.doors.add((xs_[len(xs_) // 2], ds + 1))
    cm = M["corridor"].get(dept, {})
    # a department whose human maps have no corridor area of its own (its walkway is the hall) walks on its rooms'
    # floor: white science, white medbay
    P.corr_turf = cm["turf"] if cm.get("share", 0) >= 0.05 else _dept_turf(dept, prog, M)
    carve(P, r)
    corner_closets(P, r, closets)
    cap_rooms(P, r, dept)
    jogs(P, r)
    # shapes to the stock mix for each room's type and size, then the block cut back to what its floor touches
    # (gen/learn/reshape.py; the user 2026-11-26: "you don't go creative with room size and shape")
    import reshape as RS
    P.reshaped = RS.reshape(P, r)
    # no room left over its type's biggest stock room (a 54-tile janitor's closet against the stock 24, f30)
    for rm_ in P.rooms:
        rm_.pop("piece_cap_skip", None)
    cap_rooms(P, r, dept)
    RS.separate(P)
    P.diagonals = RS.fix_diagonals(P)
    RS.trim(P)
    if os.environ.get("FP_DEBUG"):
        for a_, grp_, k_ in area_groups(P):
            c_ = _cap(a_)
            if c_ and k_ > 1.3 * c_ and a_ not in pieces():
                print("plan: OVERSIZE %s %d (cap %.0f) dept %s target %s W %s Dmax %s salt %s" % (
                    a_, k_, c_, dept, target, W, Dmax, salt))
    _corridor_area(P, dept)
    reach_rooms(P)
    if dept == "engineering":
        engine_annex(P)
    P.finish()
    return P


_MAINT_OK = None


def maint_only_ok():
    """Room types a stock map reaches only through maint (forge/walk.py stock "maint_only", the gate's "ways in"
    allows them): the janitor's closet, tech storage, the detective's office."""
    global _MAINT_OK
    if _MAINT_OK is None:
        from forge import walk
        _MAINT_OK = frozenset(a for v in walk.stock().values() for a in v["maint_only"])
    return _MAINT_OK


def reach_rooms(P):
    """Every room reached from the department's front without walking through its maint rooms: a room whose way in
    is a maint store (cap_rooms makes the rest of a cut room one, and back rooms and closets open onto it) gets a door
    of its own through a straight wall to the corridor, else to a reached room a human map joins it to; else the maint
    store becomes the department's storage room. gen/learn/plancheck.py "room reached only through maint": 18 in 84
    plans; on f45 the CE's back room was reached only through such a store (the gate's "ways in"). Returns the doors
    added."""
    N4_ = ((1, 0), (-1, 0), (0, 1), (0, -1))
    made = 0
    for _ in range(12):
        owner = {c: rm for rm in P.rooms for c in rm["F"]}
        doors = set(P.doors) | set(P.front)
        maint = {c for rm in P.rooms if rm["area"].startswith("/area/maintenance") for c in rm["F"]}
        ok = (set(owner) | set(P.corr) | doors) - maint
        seen, todo = set(P.front), list(P.front)
        while todo:
            c = todo.pop()
            for dx, dy in N4_:
                n = (c[0] + dx, c[1] + dy)
                if n in ok and n not in seen:
                    seen.add(n)
                    todo.append(n)
        cut = [rm for rm in P.rooms if not rm["area"].startswith("/area/maintenance") and rm["F"]
               and not rm["F"] & seen and rm["area"] not in maint_only_ok()]
        if not cut:
            return made
        rm = max(cut, key=lambda q: len(q["F"]))
        walk = set(owner) | set(P.corr) | doors
        best = None
        for c in rm["F"]:
            for dx, dy in N4_:
                w = (c[0] + dx, c[1] + dy)
                b = (c[0] + 2 * dx, c[1] + 2 * dy)
                if w in walk or w not in P.cells or w in P.space or b not in seen or b in doors:
                    continue
                side = [(w[0] + dy, w[1] + dx), (w[0] - dy, w[1] - dx)]
                if any(q in walk for q in side):
                    continue            # a straight wall line only, never a corner
                if any((w[0] + ex, w[1] + ey) in doors for ex, ey in N4_):
                    continue
                other = owner.get(b)
                if other is not None and (other.get("piece") or not _pair_ok(rm["area"], other["area"])):
                    continue
                key = (0 if b in P.corr else 1, abs(w[0] - c[0]) + abs(w[1] - c[1]), w)
                if best is None or key < best[0]:
                    best = (key, w)
        if best is not None:
            P.doors.add(best[1])
            made += 1
            continue
        # no wall to cut: the maint store its door opens onto becomes the department's store
        d = rm.get("door")
        via = [owner.get((d[0] + dx, d[1] + dy)) for dx, dy in N4_] if d else []
        via = [q for q in via if q is not None and q is not rm and q["area"].startswith("/area/maintenance")]
        if not via:
            return made
        import rooms as RM
        store = _storage(P.dept, [(q["area"], 0) for q in P.rooms]) or next(
            (a for a in _closets(P.dept) if a.endswith(REPEATABLE)), None) or next(
            (a for _, a, _ in RM.program_types().get(P.dept, []) if a != getattr(P, "hub", None)
             and any(w in a for w in ("storage", "warehouse", "equipment"))), None)
        if store is None or via[0].get("tried"):
            if len(rm["F"]) <= CLOSET and rm.get("back"):
                # a closet-sized back room with no way but the store: the store's own (a 4-tile transfer-centre
                # back room off security's maint store, 1 plan in 252)
                rm["area"] = via[0]["area"]
                rm["furnish_as"] = via[0].get("furnish_as", MAINT_STORE)
                continue
            return made
        via[0]["area"] = store
        via[0]["tried"] = True
        via[0].pop("furnish_as", None)
    return made


def _pair_ok(a, b):
    """A human map has a door between rooms of these two types (gen/learn/doordb.pair_seen)."""
    import doordb as DD
    return DD.pair_seen(a, b)


def _median_ok(P, dept, size):
    """Would one more room of this size keep the department's median room at or over its human band's floor?"""
    import gate as G
    band = G.bands()[0].get("space.room_size_%s" % dept)
    v = sorted([len(q["F"]) for q in P.rooms if len(q["F"]) >= 4] + [size])
    return not band or len(v) < 5 or v[len(v) // 2] >= band[0]


def _closet_size(a):
    """A closet's size: CLOSET, or less for a type humans keep smaller (patient rooms: 7 at most)."""
    c = _cap(a)
    return float(max(4, min(CLOSET, int(c)))) if c else float(CLOSET)


GROW_AT = 0.8       # a program under this share of its budget grows ...
GROW_MAX = 1.35      # ... by at most this factor a room
CAP = 0.95          # a room at most this share of the biggest human room of its type (the gate's "oversized rooms")


def _cap(area):
    import rooms as RM
    lm = RM.look_max(area)
    return lm * CAP if lm < 10 ** 5 else None


def _filler(dept, P, size, next_to=None):
    """A type for floor split off an oversized room: one of the department's types it doesn't have yet (the
    program's budget left them out), else a store or closet that repeats, else the type with the most room; each
    preferring a cap that takes the whole piece and a human median near its size. next_to: the room it opens into;
    only types a human map gives a door to that room (None when there is none)."""
    import rooms as RM
    have = {rm["area"] for rm in P.rooms}
    # (the hub is one room, at the block's far end; a room for a machine bigger than its tile is placed from the
    # program at its size, never fitted to a leftover: the gravity generator's came out 8 x 4 in a strip's last rows)
    types = [(a, med) for _, a, med in RM.program_types().get(dept, []) if a not in pieces()
             and a != getattr(P, "hub", None) and not _big_kit(a)]
    if not types:
        return None

    from collections import Counter
    n = Counter(rm["area"] for rm in P.rooms)

    def taken(a):
        return n[a] >= (REPEAT_MAX if a.endswith(REPEATABLE) else 1)
    types = [t for t in types if not taken(t[0])]
    if next_to is not None:
        types = [t for t in types if _pair_ok(next_to, t[0])]
    if not types:
        return None             # a second courtroom reads as a copy error: the caller keeps the floor its own

    def key(t):
        a, med = t
        cap = _cap(a) or 10 ** 6
        return (cap < size, abs(math.log(max(1.0, med) / max(1.0, size))))
    return min(types, key=key)[0]


MAINT_OF = {"security": "/area/maintenance/department/security", "science": "/area/maintenance/department/science",
            "medical": "/area/maintenance/department/medical", "engineering": "/area/maintenance/department/engine",
            "cargo": "/area/maintenance/department/cargo", "service": "/area/maintenance/department/crew_quarters/bar",
            "dorms": "/area/maintenance/department/crew_quarters/dorms", "civic": "/area/maintenance/department/chapel",
            "command": "/area/maintenance/department/bridge"}
MAINT_STORE = "/area/quartermaster/warehouse"     # a maint store is furnished like a warehouse (crates, racks)


CORR_ALT = {"dorms": "/area/crew_quarters/fitness"}


def _corridor_area(P, dept):
    """The corridor is painted in the department's corridor area (compose.paint_dept). Where that is also a room
    type of the plan (dorms: the hall and the cabins are both /area/crew_quarters/dorms) and hall and rooms together
    pass the type's cap, the hall takes the department's other area (the gate measured 129-148 dorms against the
    human 113, 2026-11-25)."""
    import rooms as RM
    area = RM.CORRIDOR_AREA.get(dept)
    cap = _cap(area) if area else None
    if not cap or dept not in CORR_ALT or not any(rm["area"] == area for rm in P.rooms):
        return
    probe = Plan.__new__(Plan)
    probe.rooms = P.rooms + [dict(area=area, F=set(P.corr))]
    if any(a == area and n > cap for a, _, n in area_groups(probe)):
        P.corr_area = CORR_ALT[dept]


def area_groups(P):
    """[(area, [rooms], tiles)]: rooms of one area within 2 tiles of each other, as the gate measures a room
    (forge/room_stats.py _pieces_of: two storage rooms of 35 and 37 tiles either side of one wall are one 72-tile
    room, 2026-11-25)."""
    by = {}
    for rm in P.rooms:
        by.setdefault(rm["area"], []).append(rm)
    out = []
    for area, rms in by.items():
        left = list(rms)
        while left:
            grp = [left.pop()]
            cells = set(grp[0]["F"])
            grown = True
            while grown:
                grown = False
                near = {(x + dx, y + dy) for (x, y) in cells for dx in range(-2, 3) for dy in range(-2, 3)}
                for q in list(left):
                    if q["F"] & near:
                        grp.append(q)
                        cells |= q["F"]
                        left.remove(q)
                        grown = True
            out.append((area, grp, len(cells)))
    return out


def _regroup(P, dept):
    """Same-area rooms that together pass their cap: the smallest of them becomes a type the department lacks (or one
    of its stores that fits). Returns True when one changed."""
    for area, grp, n in area_groups(P):
        cap = _cap(area)
        if len(grp) < 2 or not cap or n <= cap:
            continue
        for rm in sorted(grp, key=lambda q: len(q["F"])):
            if rm.get("piece") and rm["area"] in pieces():
                continue
            alt = _filler(dept, P, len(rm["F"]))
            if alt and alt != area and (_cap(alt) or 10 ** 6) >= len(rm["F"]):
                rm["area"] = alt
                rm.pop("back", None)
                return True
            if not alt and MAINT_OF.get(dept) and not rm.get("piece"):
                rm["area"] = MAINT_OF[dept]       # the department's maint store, as cap_rooms does with a rest
                rm["furnish_as"] = MAINT_STORE
                rm.pop("back", None)
                return True
    return False


def cap_rooms(P, r, dept):
    """Rooms bigger than every human room of their type (strip ends and back rows grow the last rooms) are cut:
    the part by the room's door keeps its cap, a wall line across the long side, the rest a room of another of the
    department's types (_filler) with a door through the new wall. Repeats while a cut piece is still over its cap.
    2026-11-25: 47 oversized areas in 54 plans (patient rooms of 60 tiles against the human 7, a 72-tile server
    room against 15)."""
    for _ in range(4 * len(P.rooms) + 8):
        over = None
        for area, grp, n in area_groups(P):
            cap = _cap(area)
            if not cap or n <= cap:
                continue
            # the group's biggest room gives up the excess (its back rooms and pieces count with it, as the gate
            # measures them)
            cands = [q for q in grp if not q.get("piece") and not q.get("piece_cap_skip") and not q.get("whole")]
            if not cands:
                continue
            rm = max(cands, key=lambda q: len(q["F"]))
            over = (rm, len(rm["F"]) - (n - cap))
            break
        if over is None:
            if _regroup(P, dept):
                continue
            return
        rm, cap = over
        F = rm["F"]
        xs = [c[0] for c in F]
        ys = [c[1] for c in F]
        x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
        door = rm.get("door") or (x0, y0)
        ax = 0 if (x1 - x0) >= (y1 - y0) else 1          # cut across the long side
        lo, hi = (x0, x1) if ax == 0 else (y0, y1)
        near_lo = abs(door[ax] - lo) <= abs(door[ax] - hi)
        best = None
        # the cut never lands in front of a door (the room's, a back room's, a neighbour's second door), and the
        # room's own door stays with the part kept; no wall corner left meeting another only diagonally
        # (gen/learn/plancheck.py: 10 doors into walls and 6 rooms off their doors in 84 plans, 2026-11-26)
        n4_ = ((1, 0), (-1, 0), (0, 1), (0, -1))
        doors_ = P.doors | P.front
        fronts = {(d_[0] + dx, d_[1] + dy) for d_ in doors_ for dx, dy in n4_} & F
        own = {(door[0] + dx, door[1] + dy) for dx, dy in n4_} & F
        walk_ = set(P.corr) | doors_
        for q_ in P.rooms:
            walk_ |= q_["F"]

        def clean(line_):
            for c in line_:
                for ox, oy in ((0, 0), (-1, 0), (0, 1), (-1, 1)):
                    a_ = (c[0] + ox, c[1] + oy)
                    w_ = [q in walk_ and q not in line_ for q in (a_, (a_[0] + 1, a_[1]), (a_[0], a_[1] - 1),
                                                                 (a_[0] + 1, a_[1] - 1))]
                    if (w_[0] and w_[3] and not w_[1] and not w_[2]) or (w_[1] and w_[2] and not w_[0] and not w_[3]):
                        return False
            return True
        for k in range(lo + 2, hi - 1):
            keep = {c for c in F if (c[ax] < k) == near_lo and c[ax] != k}
            if any(c[ax] == k for c in fronts) or (own and not own <= keep):
                continue
            if not clean({c for c in F if c[ax] == k}):
                continue
            if len(keep) <= cap and len(keep) >= max(4, min(MIN_ROOM * 2, int(cap * 0.6))):
                rest_n = len(F) - len(keep) - sum(1 for c in F if c[ax] == k)
                # the biggest part kept, a rest of a closet's size or more preferred (rests of 6 tiles took civic's
                # median under its band)
                key = (rest_n >= CLOSET + 1, len(keep))
                if best is None or key > best[1]:
                    best = (k, key)
        def retype():
            # no cut leaves a part the right size (a 7-tile cap in a 4-wide room): the room becomes a type it fits
            import rooms as RM
            alt = _filler(dept, P, len(F))
            if not alt or (_cap(alt) or 10 ** 6) < len(F):
                # every type taken: a store of the department's that fits (stores repeat on human maps)
                alt = next((a for _, a, _ in RM.program_types().get(dept, []) if a.endswith(REPEATABLE)
                            and a != getattr(P, "hub", None) and (_cap(a) or 10 ** 6) >= len(F)), None)
            if alt and alt != rm["area"] and (_cap(alt) or 10 ** 6) >= len(F):
                rm["area"] = alt
            else:
                rm["piece_cap_skip"] = True
        if best is None:
            retype()
            continue
        k = best[0]
        line = {c for c in F if c[ax] == k}
        keep = {c for c in F if (c[ax] < k) == near_lo and c[ax] != k}
        rest = F - keep - line
        # the rest in one piece, its door through the line where it meets the kept part
        gates = sorted(c for c in line if any(((c[0] + d[0], c[1] + d[1]) in keep) for d in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                       and any(((c[0] + d[0], c[1] + d[1]) in rest) for d in ((1, 0), (-1, 0), (0, 1), (0, -1))))
        if not rest or not _connected(rest) or not _connected(keep) or not gates:
            retype()
            continue
        dr = gates[len(gates) // 2]
        rm["F"] = keep
        P.floor -= line
        P.floor.add(dr)
        P.floor.discard(dr)
        P.doors.add(dr)
        area = _filler(dept, P, len(rest), next_to=rm["area"])
        extra = {}
        if not area and MAINT_OF.get(dept):
            # every type of the department placed: the rest is the department's maintenance store (crates, as
            # human departments keep a maint room behind them), not a room stretched past its type
            area = MAINT_OF[dept]
            extra = dict(furnish_as=MAINT_STORE)
        if not area:
            # nothing to make of the rest: the room stays whole (the same area either side of the cut wall would
            # count as one room again)
            rm["F"] = F
            P.floor |= line
            P.doors.discard(dr)
            rm["piece_cap_skip"] = True
            continue
        P.rooms.append(dict(area=area, F=set(rest), R=set(), gen=True, id=len(P.rooms) + 500, door=dr, **extra))


def _max_rect(F):
    """(x0, y0, x1, y1) of the biggest axis-aligned rectangle inside the cell set (histogram method by rows)."""
    xs = [c[0] for c in F]
    ys = [c[1] for c in F]
    X0, X1, Y0, Y1 = min(xs), max(xs), min(ys), max(ys)
    h = {x: 0 for x in range(X0, X1 + 1)}
    best = (0, (X0, Y0, X0, Y0))
    for y in range(Y0, Y1 + 1):
        for x in range(X0, X1 + 1):
            h[x] = h[x] + 1 if (x, y) in F else 0
        stack = []
        for x in list(range(X0, X1 + 1)) + [X1 + 1]:
            hx = h.get(x, 0) if x <= X1 else 0
            start = x
            while stack and stack[-1][1] >= hx:
                sx, sh = stack.pop()
                area = sh * (x - sx)
                if area > best[0]:
                    best = (area, (sx, y - sh + 1, x - 1, y))
                start = sx
            stack.append((start, hx))
    return best[1]


def _connected(cells):
    cells = set(cells)
    if not cells:
        return False
    start = next(iter(cells))
    seen, todo = {start}, [start]
    while todo:
        x, y = todo.pop()
        for q in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if q in cells and q not in seen:
                seen.add(q)
                todo.append(q)
    return len(seen) == len(cells)


# the supermatter room (21 x 18 behind engineering's back wall) and its coil (6 more), with a ring of space round them
# (gen/net.py engine wants space or plain wall round the room: maint ran along a 21-wide annex, NO SITE, 2026-11-25)
ANNEX_W, ANNEX_D = 31, 28      # the core and its coil (21), its main floor (4), the rooms past it (3 + 2 walls): gen/net.py ROOM_D
# (a reserve of 34 for rooms 5 deep upset the layout search whether the block was forced as wide or the reserve
# overhung it: gate fails 5 -> 14 and 11-20, f33 and f34; the rooms are 3 deep and the whole fits the 31)
ANNEX_BLOCK_W = 31


def engine_annex(P):
    """Engineering keeps the floor behind its back wall for the supermatter (gen/net.py engine: MetaStation's block
    and coil): claimed in the layout so no department or maint takes it, painted as space, so the engine always finds
    its site against engineering (two rounds of crew 80 seed 1 had none, 2026-11-25)."""
    if P.W < ANNEX_BLOCK_W:
        return
    aw = min(P.W, ANNEX_W + 2)        # a tile of margin each side when the department is wide enough
    x0 = (P.W - aw) // 2
    D = P.Dmax
    P.space = {(x, y) for x in range(x0, x0 + aw) for y in range(D + 1, D + 2 + ANNEX_D)}
    P.cells |= P.space
    P.Dmax = D + ANNEX_D


JOG_P = 0.15        # how often two rooms that share a straight wall interlock (both become L-shaped)
MIN_KEEP = 6        # a room keeps at least this much floor after giving a jog away


def jogs(P, r):
    """Neighbouring rooms interlock as human rooms do: where two rooms share a straight wall line 4+ long, the half
    of it away from both rooms' doors moves one tile into the second room (the first gains that strip, the second
    gives a strip and the corner cell that closes the step). Both become L-shaped; no room is added (corner closets
    add a rectangle for each L they make, and the rect share stayed at 0.87 against the human 0.39-0.65)."""
    owner = {}
    for rm in P.rooms:
        for c in rm["F"]:
            owner[c] = rm["id"]
    by_id = {rm["id"]: rm for rm in P.rooms}
    done = set()
    walls = sorted(c for c in P.cells if c not in owner and c not in P.corr and c not in P.doors and c not in P.front
                   and c not in P.space)
    for axis in ((1, 0), (0, 1)):
        # straight shared wall lines: cells with room a on one side and room b on the other, along the line
        lines = {}
        for w in walls:
            a = owner.get((w[0] - axis[0], w[1] - axis[1]))
            b = owner.get((w[0] + axis[0], w[1] + axis[1]))
            if a is None or b is None or a == b:
                continue
            ra, rb = by_id[a], by_id[b]
            if ra.get("piece") or rb.get("piece") or ra.get("whole") or rb.get("whole"):
                continue
            lines.setdefault((a, b, w[0] if axis == (1, 0) else w[1]), []).append(w)
        for (a, b, k), cells in sorted(lines.items(), key=lambda kv: kv[0]):
            if (a, b) in done or (b, a) in done or len(cells) < 4 or r.random() > JOG_P:
                continue
            along = 1 if axis == (1, 0) else 0       # the coordinate that runs along the wall line
            cells.sort(key=lambda c: c[along])
            if any(cells[i + 1][along] - cells[i][along] != 1 for i in range(len(cells) - 1)):
                continue
            doors = [d for d in P.doors | P.front]
            half_lo, half_hi = cells[:len(cells) // 2], cells[len(cells) // 2:]

            def door_near(part):
                return min(abs(d[0] - c[0]) + abs(d[1] - c[1]) for d in doors for c in part) if doors else 99
            part = half_lo if door_near(half_lo) > door_near(half_hi) else half_hi
            if door_near(part) <= 1:
                continue
            ra, rb = by_id[a], by_id[b]
            # into the smaller room's side? no: from a into b, b must stay big enough
            shift = [(c[0] + axis[0], c[1] + axis[1]) for c in part]
            # the cell that closes the step, at the end of the moved part nearer the rest of the line
            rest_end = part[0] if part is half_hi else part[-1]
            step = (rest_end[0] + axis[0] + (-1 if part is half_hi else 1) * (axis[1]),
                    rest_end[1] + axis[1] + (-1 if part is half_hi else 1) * (axis[0]))
            lose = set(shift) | {step}
            if not lose <= rb["F"] or len(rb["F"]) - len(lose) < MIN_KEEP:
                continue
            if _cap(ra["area"]) and len(ra["F"]) + len(part) > _cap(ra["area"]):
                continue                    # no jog grows a room past its type's human biggest
            if any((c[0] + dx, c[1] + dy) in P.doors for c in lose for dx in (-1, 0, 1) for dy in (-1, 0, 1)):
                continue
            rb["F"] -= lose
            P.floor -= lose
            ra["F"] |= set(part)
            P.floor |= set(part)
            done.add((a, b))
            for c in part:
                owner[c] = a
            for c in lose:
                owner.pop(c, None)


CORNER_P = 0.3     # and any room of 24+ tiles does so this often (human rooms: 35-60% not rectangles)
CORNER_OVER = 1.7    # a room this many times its type's human median size gives up a corner as a closet


def corner_closets(P, r, closets):  # noqa: C901
    """Rooms give up corners, away from their doors, as small rooms with a door into them:
    - back rooms of their own type, as many as the stock rooms of the type keep (backrooms(): the bar's backroom,
      research's server closet; backcount(): engineering's main room 3, the gravity generator 2, medbay 2), each at
      the stock share;
    - a closet of the department's when the room is much bigger than its type's human median, or now and then.
    The big room becomes an L or more (human rooms: rect share 0.39-0.65; ours was 0.83). A department with no closet
    types still gets its back rooms (service had none: the pass returned before the bar's backroom, 2026-11-26)."""
    import rooms as RM
    med = {a: s for d_ in RM.program_types().values() for _, a, s in d_}
    backs = backrooms()
    counts = backcount()
    doors_all = P.doors | P.front
    for rm in list(P.rooms):
        if rm.get("piece") or len(rm["F"]) < 20 or rm["area"] in pieces():
            continue
        if _big_kit(rm["area"]):
            continue            # the gravity generator's 3x3 wants its room whole (a corner cut left it no seat, f35)
        n0 = len(rm["F"])
        back = SECURE_BACK.get(rm["area"]) or backs.get(rm["area"])
        k_own = 0
        if back is not None:
            for _ in range(min(BACK_MOST, counts.get(rm["area"], 1))):
                if r.random() < back[0]:
                    k_own += 1
        if rm["area"] in SECURE_BACK:
            SECURE_BACK_DONE.add(id(P))
            k_own = max(k_own, 1)
            if sum(1 for q in P.rooms if q["area"] == rm["area"] and q.get("back")) >= 1:
                k_own = 0
        over = rm["area"] in med and n0 >= CORNER_OVER * med[rm["area"]]
        want_closet = bool(closets) and (over or r.random() <= CORNER_P) and (over or _median_ok(P, P.dept, 6))
        jobs = [True] * k_own + ([False] if want_closet else [])
        used = set()
        for own in jobs:
            F = rm["F"]
            xs = [c[0] for c in F]
            ys = [c[1] for c in F]
            x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
            if x1 - x0 < 5 or y1 - y0 < 5:
                break
            door = rm.get("door") or (x0, y0)
            if own:
                # the first of engineering's is its secure storage (SECURE_BACK's size), the rest the stock size
                size_ = back[1] if (rm["area"] not in SECURE_BACK or not used) else backs.get(rm["area"], back)[1]
                side = max(2, int(round(math.sqrt(size_))))
                cw_ = max(2, min(side + r.randint(-1, 1), x1 - x0 - 3))
                ch_ = max(2, min(int(round(size_ / float(cw_))), y1 - y0 - 3))
            else:
                cw_, ch_ = r.randint(2, 3), r.randint(2, 3)
                capc = min(_cap(a) or 99 for a in closets)
                while cw_ * ch_ > capc and max(cw_, ch_) > 2:
                    if cw_ >= ch_:
                        cw_ -= 1
                    else:
                        ch_ -= 1
            avail = None
            if not own:
                from collections import Counter
                n_ = Counter(q["area"] for q in P.rooms)
                avail = [a for a in closets if n_[a] < (REPEAT_MAX if a.endswith(REPEATABLE) else 1)
                         and _pair_ok(rm["area"], a)]
                if not avail:
                    continue
            corners = [(x0, y0, 1, 1), (x1, y0, -1, 1), (x0, y1, 1, -1), (x1, y1, -1, -1)]
            corners.sort(key=lambda c: -(abs(c[0] - door[0]) + abs(c[1] - door[1])))
            done = False
            for cx, cy, sx, sy in corners[:3]:          # never the corner nearest the door
                if (cx, cy) in used:
                    continue
                cl = {(cx + sx * i, cy + sy * j) for i in range(cw_) for j in range(ch_)}
                wall = {(cx + sx * i, cy + sy * ch_) for i in range(cw_ + 1)} | {(cx + sx * cw_, cy + sy * j) for j in range(ch_ + 1)}
                rest = F - cl - wall
                if not (cl | wall) <= F or len(rest) < max(12, int(0.55 * n0)) or not _connected(rest):
                    continue
                # no door's front taken or walled (the room's own, another back room's)
                if any((d_[0] + dx, d_[1] + dy) in (cl | wall) for d_ in doors_all for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                    continue
                # its own door opens on the room: the host's floor right past it (a 6-tile medbay back room was
                # reached only through maint, f35)
                dr_ = (cx + sx * (cw_ // 2), cy + sy * ch_)
                if (dr_[0], dr_[1] + sy) not in rest or (dr_[0], dr_[1] - sy) not in cl:
                    continue
                rm["F"] = rest
                P.floor -= wall
                dr = (cx + sx * (cw_ // 2), cy + sy * ch_)
                P.doors.add(dr)
                doors_all = P.doors | P.front
                P.rooms.append(dict(area=rm["area"] if own else r.choice(avail), F=set(cl), R=set(), gen=True,
                                    id=len(P.rooms) + 300, door=dr, back=own))
                used.add((cx, cy))
                done = True
                break
            if not done and own:
                break


_BCOUNT = None
BACK_MOST = 3       # own back rooms a room at most


def backcount():
    """{room type: how many small pieces of its own area (4-16 tiles) a stock room of the type keeps beside its main
    room, the median over the maps that have it} (engineering 3, the gravity generator 2, medbay 2, most 1)."""
    global _BCOUNT
    if _BCOUNT is None:
        import roomdb
        from collections import defaultdict
        by = defaultdict(list)
        for rr in roomdb.rooms():
            by[(rr["map"], rr["area"])].append(rr["tiles"])
        cnt = defaultdict(list)
        for (_, a), v in by.items():
            v = sorted(v, reverse=True)
            if v[0] >= 20:
                cnt[a].append(sum(1 for t in v[1:] if 4 <= t <= 16))
        _BCOUNT = {a: max(1, sorted(v)[len(v) // 2]) for a, v in cnt.items() if len(v) >= 4}
    return _BCOUNT


_BACKS = None


def backrooms():
    """{room type: (share, size)}: how often a human map gives the type a small back room of the same area (a
    second region of 16 tiles or less next to a main one of 20+: the bar's backroom, the library's study, the
    chapel's crematorium) and that back room's median size. Types seen on 4+ maps."""
    global _BACKS
    if _BACKS is None:
        import roomdb
        from collections import defaultdict
        by = defaultdict(list)
        for rr in roomdb.rooms():
            by[(rr["map"], rr["area"])].append(rr["tiles"])
        st = defaultdict(lambda: [0, 0, []])
        for (_, a), v in by.items():
            v = sorted(v, reverse=True)
            st[a][1] += 1
            small = [t for t in v[1:] if 4 <= t <= 16]
            if v[0] >= 20 and small:
                st[a][0] += 1
                st[a][2] += small
        _BACKS = {a: (k / float(n), sorted(sz)[len(sz) // 2]) for a, (k, n, sz) in st.items() if n >= 4 and k}
    return _BACKS


# engineering's secure storage: a piece of its own area behind the main room (emitters, field and shield generators
# behind blast doors, stock 7/7, 16-36 tiles; gen/learn/fn_engineering.py _fix_secure furnishes it): always, 22 tiles
SECURE_BACK = {"/area/engine/engineering": (1.0, 22)}
SECURE_BACK_DONE = set()
CLOSET = 8          # a closet's size (tiles)
BIG = 90            # no room of the program bigger than this (pieces types and the department's hall aside)
HALL = 150          # the department's one big hall at most this (stock maps' biggest rooms 149-380)
SIZE_LO, SIZE_HI = 0.6, 1.7     # a drawn size against its type's median
SIZE_SCALE = 0.85               # and every drawn room but the hall this much of it
# side corridors (bays): a stem strip this deep may open one, at most BAY_MOST a strip, its rooms BAY_ROOM deep
BAY_P, BAY_DEPTH, BAY_MOST, BAY_ROOM, BAY_CAP_P = 0.7, 10, 1, (4, 6), 0.5
UNEVEN_P, UNEVEN_MAX = 0.6, 9   # a stem strip stops short of the block's end this often, by at most this many tiles


_CLOSETS = None


def _closets(dept):
    """The department's own small rooms on the human maps (rooms of 12 tiles or less, by department group, not the
    pieces types that carve their own): patient rooms in medical, toilets in dorms, the chapel office and art storage
    in civic, tech storage in engineering, checkpoints in security. The most common few, by how many maps have one."""
    global _CLOSETS
    if _CLOSETS is None:
        import roomdb
        from collections import Counter, defaultdict
        sys.path.insert(0, os.path.join(HERE, "..", "..", "studies"))
        import stations as ST
        c = defaultdict(Counter)
        sizes = defaultdict(list)
        for r in roomdb.rooms():
            sizes[r["area"]].append(r["tiles"])
        med = {a: sorted(v)[len(v) // 2] for a, v in sizes.items()}
        seen_ = set()
        for r in roomdb.rooms():
            # a type humans keep small (its median room), not a working room that is sometimes small: the central
            # medbay, the captain's office and toxins mixing came out as "closets" and departments got copies
            # (four canister rooms in science, 2026-11-25). And a small room with something in it: a bare 9-tile
            # "atmospherics engine" piece of pipes was a closet type in engineering (crew 100 seed 7, 2026-11-26)
            # (counted once a map: Delta's atmos engine alone had three small furnished pieces)
            # (and no work of its own: the quartermaster's office was a 6-tile closet with no locker or console)
            if r["tiles"] <= 12 and med[r["area"]] <= CLOSET_MED and r["motifs"] and (r["area"], r["family"]) not in seen_                     and len(_kit_machines(r["area"])) < 2:
                seen_.add((r["area"], r["family"]))
                c[ST.group_of(r["area"])][r["area"]] += 1
        # not small pieces of special rooms (a burn chamber, another department's checkpoint, a transit tube)
        odd = ("chamber", "checkpoint", "transit", "external", "AIsat", "aisat", "solar", "tcom")
        # (nor a room for a machine bigger than its tile: a second, 20-tile "gravity generator" came out as a closet)
        _CLOSETS = {g: [a for a, n in cc.most_common(10) if a not in pieces() and n >= 2 and not any(w in a for w in odd)
                        and not _big_kit(a)][:4]
                    for g, cc in c.items()}
        import rooms as RM
        for g, types in RM.program_types().items():
            st_ = [a for _, a, _ in types if (a.endswith("/storage") or a.endswith("/equipment"))
                   and med.get(a, 99) <= CLOSET_MED]
            if st_:
                _CLOSETS[g] = st_[:1] + [a for a in _CLOSETS.get(g, []) if a not in st_]
    return _CLOSETS.get(dept, [])


def _closets_for(dept, prog):
    """_closets less the types the department already has (a second captain's office or library reads as a copy
    error), its storage types kept even when it has one (human departments have several closets)."""
    from collections import Counter
    n = Counter(a for a, _ in prog)
    return [a for a in _closets(dept) if n[a] == 0 or (a.endswith(REPEATABLE) and n[a] < REPEAT_MAX)]


CLOSET_MED = 16     # a closet type's median human room size at most this


REPEATABLE = ("/storage", "/equipment", "/toilet", "/restrooms", "/locker", "/janitor", "/tech")
REPEAT_MAX = 2      # a closet type at most this many times in a department (five art storages in one civic)


def _storage(dept, prog):
    """The department's storage room type: one of its program types named for storing that it doesn't have yet, or
    None (a second locker room read as a copy error; the strip's last room grows instead)."""
    import rooms as RM
    have = {a for a, _ in prog}
    for fam, area, size in RM.program_types().get(dept, []):
        if area not in have and any(w in area for w in ("storage", "closet", "warehouse", "equipment")):
            return area
    return None


def _dept_turf(dept, prog, M):
    from collections import Counter
    c = Counter(M["turf"].get(a, "/turf/open/floor/plasteel") for a, _ in prog)
    return c.most_common(1)[0][0] if c else "/turf/open/floor/plasteel"


_PIECES = None


def pieces():
    """{room type: (extra pieces, piece size, piece glass share)} for the types whose human rooms are a main room
    with a row of small pieces of the same area off it (xenobiology's pens, the brig's cells, dorm bedrooms): the
    median over maps of how many, how big, and how much of their walls is glass (roomdb)."""
    global _PIECES
    if _PIECES is None:
        import roomdb
        from collections import defaultdict
        by = defaultdict(lambda: defaultdict(list))
        for r in roomdb.rooms():
            by[r["area"]][r["map"]].append(r)
        _PIECES = {}
        for a, maps in by.items():
            if len(maps) < 3:
                continue
            extra, sizes, glass = [], [], []
            for rs in maps.values():
                rs = sorted(rs, key=lambda r: -r["tiles"])
                extra.append(len(rs) - 1)
                for r in rs[1:]:
                    sizes.append(r["tiles"])
                    ring = sum(bin(f[2]).count("1") for f in r["floor"])
                    glass.append(len(r["windows"]) / float(max(1, ring)))
            e = sorted(extra)[len(extra) // 2]
            if e >= 2 and sizes:
                sz = sorted(sizes)[len(sizes) // 2]
                if sz <= PIECE_MAX:
                    _PIECES[a] = (e, sz, sorted(glass)[len(glass) // 2])
        # a room with a machine bigger than its tile stays whole: carved into 3-4 wide pieces, the gravity
        # generator's 3x3 and a way past it fit nowhere (crew 100 seed 7 f14)
        _PIECES.pop("/area/engine/gravity_generator", None)
    return _PIECES


PIECE_MAX = 12      # pieces bigger than this are rooms of their own, not cells or pens
PIECES_MOST = 6     # pieces one room carves at most


PAIR = 0.8          # a room type this often beside another on the human maps (deptdb nb) is placed next to it
W_FIT = 1.3         # a plan's width at most this times the side of a square of its program's floor
ASPECT_MAX = 2.4     # a room at most this many times as long as it is deep


HALL_PIECES = ("/area/security/brig", "/area/security/prison", "/area/crew_quarters/dorms")   # a cell/cabin hall


def _need(area):
    """The depth a pieces type's room needs: its pieces' depth, their wall, a room of MIN_ROOM before them (0 for others)."""
    pt = pieces().get(area)
    if not pt:
        return 0
    pw = max(2, int(round(math.sqrt(pt[1]))))
    return min(pw, max(2, int(round(pt[1] / float(pw))))) + 1 + MIN_ROOM


def carve(P, r):
    """Each room of a pieces() type: a row of its pieces along its back wall (the side away from its door), one wall
    between pieces and one between them and the room, each with a door into the room (a windoor-glass front where
    humans glaze them). The pieces are rooms of the same area, furnished like the human ones."""
    table = pieces()
    for rm in list(P.rooms):
        if rm["area"] not in table or rm.get("piece"):
            continue
        n, size, glass = table[rm["area"]]
        n = min(n, PIECES_MOST)
        # up to two rows (on two sides away from the door) till the type's number of pieces is in: one row held 3-4
        # brig cells against the human 7 and 3-4 slime pens against 10 (crew 100 seed 7, 2026-11-26)
        used_sides = set()
        for row_i in range(2):
            got = _carve_row(P, rm, n, size, glass, used_sides)
            if not got:
                break
            n -= got
            if n < 2:
                break


def _carve_row(P, rm, n, size, glass, used_sides):
    """One row of up to n pieces along the room's longest free side away from its door (not one of used_sides); the
    next longest when the row doesn't fit there (a back room's door on that wall, a notch: the prison kept no cells in
    6 plans of 12 and the brig in 3, against the stock 3 and 4 a map, 2026-11-26). Returns how many were carved."""
    if True:
        F = rm["F"]
        # the room's biggest rectangle takes the row (an L-shaped brig of 143 tiles kept no cells, 2026-11-25)
        x0, y0, x1, y1 = _max_rect(F)
        if (x1 - x0 + 1) * (y1 - y0 + 1) < 0.55 * len(F):
            return 0
        door = rm.get("door")
        # the back side: the one farthest from the room's door
        sides = {"N": abs((y1 + 1) - door[1]) if door else 0, "S": abs((y0 - 1) - door[1]) if door else 0,
                 "E": abs((x1 + 1) - door[0]) if door else 0, "W": abs((x0 - 1) - door[0]) if door else 0}
        # the longest side without the room's door (more pieces fit), the farther one on a tie
        length_ = {"N": x1 - x0 + 1, "S": x1 - x0 + 1, "E": y1 - y0 + 1, "W": y1 - y0 + 1}
        with_door = {k for k, v in sides.items() if v <= 1}
        for back in sorted((k for k in sides if k not in with_door and k not in used_sides),
                           key=lambda k: (-length_[k], -sides[k], k)):
            got = _carve_side(P, rm, n, size, glass, used_sides, back, (x0, y0, x1, y1))
            if got:
                return got
        return 0


def _carve_side(P, rm, n, size, glass, used_sides, back, box):
    """_carve_row on one side of the room's biggest rectangle `box`: the pieces as their size gives them, then turned
    (3 wide and 2 deep for 2 by 3: in a room 7 deep the wall before a 3-deep row fell on the middle row, where the
    room's door and its back room's stood, and a 63-tile brig kept no cells, 2026-11-26)."""
    return _carve_side1(P, rm, n, size, glass, used_sides, back, box, False)         or _carve_side1(P, rm, n, size, glass, used_sides, back, box, True)


def _carve_side1(P, rm, n, size, glass, used_sides, back, box, turn):
    if True:
        F = rm["F"]
        x0, y0, x1, y1 = box
        pw = max(2, int(round(math.sqrt(size))))
        pd = max(2, int(round(size / float(pw))))
        if turn:
            if pw == pd:
                return 0
            pw, pd = pd, pw
        along = (x1 - x0 + 1) if back in ("N", "S") else (y1 - y0 + 1)
        deep = (y1 - y0 + 1) if back in ("N", "S") else (x1 - x0 + 1)
        # the hall left in front of the pieces: MIN_ROOM, or 2 when the row is long (a brig's cell hall)
        hall = 2 if along >= 3 * (min(pw, pd) + 1) and rm["area"] in HALL_PIECES else MIN_ROOM
        if deep - pd - 1 < hall and deep - pw - 1 >= hall:
            pw, pd = pd, pw             # shallow room: the pieces turn (3 wide, 2 deep)
        if deep - pd - 1 < hall:
            return 0
        k = min(n, (along + 1) // (pw + 1))
        if k < 2:
            return 0
        cells_all = []
        for i in range(k):
            a0 = i * (pw + 1)
            a1 = a0 + pw - 1 if i < k - 1 else along - 1     # the last piece takes the row's end
            if back == "N":
                pc = {(x0 + a, y) for a in range(a0, a1 + 1) for y in range(y1 - pd + 1, y1 + 1)}
                dr = (x0 + (a0 + a1) // 2, y1 - pd)
            elif back == "S":
                pc = {(x0 + a, y) for a in range(a0, a1 + 1) for y in range(y0, y0 + pd)}
                dr = (x0 + (a0 + a1) // 2, y0 + pd)
            elif back == "E":
                pc = {(x, y0 + a) for a in range(a0, a1 + 1) for x in range(x1 - pd + 1, x1 + 1)}
                dr = (x1 - pd, y0 + (a0 + a1) // 2)
            else:
                pc = {(x, y0 + a) for a in range(a0, a1 + 1) for x in range(x0, x0 + pd)}
                dr = (x0 + pd, y0 + (a0 + a1) // 2)
            cells_all.append((pc, dr))
        # the whole band behind the wall line: the pieces and the wall cells between them
        if back == "N":
            row = {(x, y) for x in range(x0, x1 + 1) for y in range(y1 - pd + 1, y1 + 1)}
        elif back == "S":
            row = {(x, y) for x in range(x0, x1 + 1) for y in range(y0, y0 + pd)}
        elif back == "E":
            row = {(x, y) for y in range(y0, y1 + 1) for x in range(x1 - pd + 1, x1 + 1)}
        else:
            row = {(x, y) for y in range(y0, y1 + 1) for x in range(x0, x0 + pd)}
        if back in ("N", "S"):
            wall_line = {(x, (y1 - pd) if back == "N" else (y0 + pd)) for x in range(x0, x1 + 1)}
        else:
            wall_line = {((x1 - pd) if back == "E" else (x0 + pd), y) for y in range(y0, y1 + 1)}
        if not (row | wall_line) <= F:
            return 0                    # a notch of the room is in the way of the row
        if not _connected(F - row - wall_line):
            return 0                    # the row would cut the room in two
        # never over a door's front: the room's own door, or a back room's into it (a second row of slime pens took
        # the row xenobiology's door opened on, and the lab was entered through a pen, 2026-11-26)
        taken_ = row | wall_line
        if any((d_[0] + dx, d_[1] + dy) in taken_ for d_ in (P.doors | P.front) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
            return 0
        F -= row | wall_line
        P.floor -= wall_line | (row - set().union(*[pc for pc, _ in cells_all]))   # wall line and walls between
        for pc, dr in cells_all:
            P.doors.add(dr)
            P.rooms.append(dict(area=rm["area"], F=set(pc), R=set(), gen=True, id=len(P.rooms) + 100, door=dr,
                                piece=True, glass=glass))
        # walls between pieces stay out of every room's floor
        gaps = row - set().union(*[pc for pc, _ in cells_all])
        P.floor -= gaps
        used_sides.add(back)
        return k


_GLASS = None


def glass_share():
    """{room type: median share of its wall sides that are glass} on the human tg maps (roomdb)."""
    global _GLASS
    if _GLASS is None:
        import roomdb
        from collections import defaultdict
        g = defaultdict(list)
        for r in roomdb.rooms():
            ring = sum(bin(f[2]).count("1") for f in r["floor"])
            if ring:
                g[r["area"]].append(len(r["windows"]) / float(ring))
        _GLASS = {a: sorted(v)[len(v) // 2] for a, v in g.items() if len(v) >= 3}
    return _GLASS


PANE = "/obj/effect/spawner/structure/window/reinforced"


def glaze(m, P, S):
    """Windows onto the corridor for the room types humans glaze (glass_share): that share of a room's wall sides,
    as one run in the middle of its longest corridor-facing wall, never beside a door or at a wall's end."""
    from forge import dmm
    share = glass_share()
    n = 0
    doors = {S(c) for c in P.doors | P.front}
    corr = {S(c) for c in P.corr}
    for rm in P.rooms:
        sh = share.get(rm["area"], 0.0)
        if sh < 0.05:
            continue
        floor = {S(c) for c in rm["F"]}
        cand = set()
        for p in floor:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                w = (p[0] + dx, p[1] + dy)
                q = (p[0] + 2 * dx, p[1] + 2 * dy)
                t = m.get(*w)
                if q in corr and t is not None and t.tpath.startswith("/turf/closed") and not t.objs                         and not any((w[0] + ex, w[1] + ey) in doors for ex in (-1, 0, 1) for ey in (-1, 0, 1)):
                    cand.add(w)
        if not cand:
            continue
        ring = sum(1 for p in floor for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) if (p[0] + dx, p[1] + dy) not in floor)
        want = max(2, int(round(sh * ring)))
        # the longest straight run of candidates, then its middle `want` cells
        runs = []
        for c in sorted(cand):
            for axis in ((1, 0), (0, 1)):
                if (c[0] - axis[0], c[1] - axis[1]) in cand:
                    continue
                run = [c]
                while (run[-1][0] + axis[0], run[-1][1] + axis[1]) in cand:
                    run.append((run[-1][0] + axis[0], run[-1][1] + axis[1]))
                runs.append(run)
        run = max(runs, key=len)
        if len(run) < 3:
            continue
        inner = run[1:-1]
        k = min(want, len(inner))
        start = (len(inner) - k) // 2
        for w in inner[start:start + k]:
            t = m.get(*w)
            m.set(w[0], w[1], dmm.Tile([dmm.Atom(PANE)], dmm.Atom("/turf/open/floor/plating"), t.area.copy()))
            n += 1
    # a room with a door onto the department's hub looks onto it as well (the QM's office onto the cargo bay: door
    # and windows on 8 stock maps of 8): two panes in the wall between, clear of the door and the wall's ends
    hub = next((rm for rm in P.rooms if rm.get("hub")), None)
    if hub is not None:
        hfloor = {S(c) for c in hub["F"]}
        for rm in P.rooms:
            if rm is hub or share.get(rm["area"], 0.0) < 0.05:
                continue
            floor = {S(c) for c in rm["F"]}
            between = set()
            for q in floor:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    if (q[0] + 2 * dx, q[1] + 2 * dy) in hfloor:
                        between.add((q[0] + dx, q[1] + dy))
            if not between & doors:
                continue
            cand = sorted(w for w in between if m.get(*w) is not None and m.get(*w).tpath.startswith("/turf/closed")
                          and not m.get(*w).objs
                          and not any((w[0] + ex, w[1] + ey) in doors for ex in (-1, 0, 1) for ey in (-1, 0, 1))
                          and sum(1 for ex, ey in ((1, 0), (-1, 0), (0, 1), (0, -1)) if (w[0] + ex, w[1] + ey) in between) == 2)
            for w in cand[:2]:
                t = m.get(*w)
                m.set(w[0], w[1], dmm.Tile([dmm.Atom(PANE)], dmm.Atom("/turf/open/floor/plating"), t.area.copy()))
                n += 1
    return n


def trim(m, P, S):
    """The corridor's edge trim in the department's colour (v6_station.DEPT_TRIM by the department's areas): one
    quarter decal on each wall side of an edge tile, as Meta's department walkways. Departments with no colour there
    (dorms, civic, service) keep a bare walkway, as theirs mostly do."""
    import v6_station as V6
    from forge import dmm
    areas = [rm["area"] for rm in P.rooms]
    col = None
    for a in areas:
        col = next((c for pre, c in V6.DEPT_TRIM if a.startswith(pre)), None)
        if col:
            break
    if not col:
        return 0
    n = 0
    for c in P.corr:
        p = S(c)
        t = m.get(*p)
        if t is None or t.has("/obj/machinery/door") or t.has("/obj/effect/turf_decal/tile"):
            continue
        sides = [d for d, (dx, dy) in ((1, (0, 1)), (2, (0, -1)), (4, (1, 0)), (8, (-1, 0)))
                 if m.get(p[0] + dx, p[1] + dy) is not None and m.get(p[0] + dx, p[1] + dy).tpath.startswith("/turf/closed")]
        for d in sides:
            qd = V6.QUARTERS[d][0]
            t.objs.insert(0, dmm.Atom("/obj/effect/turf_decal/tile/%s" % col, [("dir", str(qd))] if qd != 2 else []))
        n += bool(sides)
    return n


STATION = {}        # machine family -> how many more the whole station may have (compose.finish clears it per build)
BUDGETS = {}        # room type -> its budget; cleared with STATION


def furnish(m, P, S, log=print):
    """Furnish every room of a painted plan (S: frame cell -> map tile) with the learned synthesizer."""
    import synth
    from forge import corpus as CO, dmm
    n = 0
    budgets = BUDGETS  # room type -> {machine family: how many more} (synth.furnish: no more than a human map has)
    # main rooms first: the gravity generator's own room gets the machine, not its antechamber
    import roomdb as RDB_
    for rm in sorted(P.rooms, key=lambda r: (bool(r.get("back") or r.get("piece")) != RDB_.back_first(
            r.get("furnish_as") or r["area"]), -len(r["F"]))):
        floor = {S(c) for c in rm["F"]}
        doors = {(p[0] + dx, p[1] + dy) for p in floor for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                 if m.get(p[0] + dx, p[1] + dy) is not None and m.get(p[0] + dx, p[1] + dy).has("/obj/machinery/door")}
        solid = lambda p: CO.solid(m.get(*p)) and p not in doors  # noqa: E731
        kind_ = rm.get("furnish_as") or rm["area"]
        out, rep = synth.furnish(floor, solid, doors, set(), kind_, seed=rm["id"] + 1,
                                 back=bool(rm.get("back") or rm.get("piece")), budget=budgets.setdefault(kind_, {}),
                                 station=STATION)
        for p, atoms in out.items():
            t = m.get(*p)
            if t is not None:
                t.objs.extend(dmm.Atom.parse(a) for a in atoms)
                n += 1
        # the game's own partner and use rules (forge/function.py: consoles by their machines, chairs at something,
        # pieces on a wall they can hang on), door fronts kept clear
        from forge import function as FN
        fronts = {(d[0] + dx, d[1] + dy) for d in doors for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))}
        try:
            FN.fix(m, floor, protect=fronts)
            unstrand(m, floor, synth._kit(rm.get("furnish_as") or rm["area"]))
            if rm.get("furnish_as") == MAINT_STORE:
                clutter(m, floor, doors, random.Random("clutter|%d" % rm["id"]))
        except Exception as e:             # noqa: BLE001 - a fix that fails leaves the room as synthesized
            log("floorplan: function fix failed in %s: %s" % (rm["area"], str(e)[:100]))
    # xenobiology starts with slimes in its pens (a lab furnished from empty human pens had none: "slimes tended"
    # failed in Bot Shift, crew 100 seed 7, 2026-11-25)
    pens = [rm for rm in P.rooms if rm["area"] == "/area/science/xenobiology" and rm.get("piece")]
    has = any(o.path.startswith("/mob/living/simple_animal/slime") for rm in pens for c in rm["F"]
              for o in (m.get(*S(c)).objs if m.get(*S(c)) is not None else ()))
    if pens and not has:
        from forge import function as FN
        for rm in pens[:2]:
            free = [S(c) for c in sorted(rm["F"]) if m.get(*S(c)) is not None
                    and not any(FN.is_dense(o) for o in m.get(*S(c)).objs)]
            if free:
                m.get(*free[len(free) // 2]).objs.append(dmm.Atom("/mob/living/simple_animal/slime"))
    # one of each unique thing in the department (a captain's office and its back room each had the nuke disk)
    from forge import function as FN
    seen = set()
    for rm in P.rooms:
        for c in sorted(rm["F"]):
            t = m.get(*S(c))
            if t is None:
                continue
            for o in list(t.objs):
                if o.path.startswith(FN.UNIQUE):
                    if o.path in seen:
                        t.objs.remove(o)
                    seen.add(o.path)
    return n


CLUTTER = ("/obj/structure/closet/crate", "/obj/structure/rack", "/obj/structure/closet/crate/internals",
           "/obj/structure/closet/emcloset", "/obj/structure/closet/firecloset", "/obj/structure/closet/crate/engineering",
           "/obj/structure/reagent_dispensers/watertank", "/obj/structure/reagent_dispensers/fueltank")


def clutter(m, floor, doors, r):
    """A maint store has no open 3x3 of floor (gen/gate.py "open maint": stock maint is corridors and small cluttered
    rooms): the middle of each open field gets a crate, rack or closet, while the store's floor stays one walkable
    piece and its door fronts clear."""
    from forge import dmm, function as FN

    def walk(p):
        t = m.get(*p)
        return t is not None and p in floor and not any(FN.is_dense(o) for o in t.objs)
    fronts = {(d[0] + dx, d[1] + dy) for d in doors for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))}
    for p in sorted(floor):
        if p in fronts or not all(walk((p[0] + dx, p[1] + dy)) for dx in (-1, 0, 1) for dy in (-1, 0, 1)):
            continue
        t = m.get(*p)
        t.objs.append(dmm.Atom(r.choice(CLUTTER)))
        rest = {q for q in floor if walk(q)}
        if not _connected(rest) or any(f in floor and not walk(f) for f in fronts):
            t.objs.pop()


def unstrand(m, floor, kit, rounds=3):
    """What the function pass left with nowhere to stand at (forge/function.py review "reach" and "front": a table
    walled in by tables, a console facing a machine): a piece in its way goes, else the stranded piece itself; never a
    piece of the type's kit (the microwave stays, a table goes). 7 such in one engineering preview, 2026-11-25."""
    from forge import function as FN
    kit = tuple(kit or ())

    def dense_spare(p):
        return [o for o in m.get(*p).objs if FN.is_dense(o) and FN.on_floor(o) and not o.path.startswith(kit)
                and not o.path.startswith(("/obj/machinery/door", "/obj/machinery/atmospherics", "/obj/structure/cable",
                                           "/obj/machinery/power/apc", "/obj/structure/window", "/obj/structure/grille"))]
    for _ in range(rounds):
        probs = [pr for pr in FN.review(m, floor) if pr[0] in ("reach", "front")]
        if not probs:
            return
        for rule, p, _text in probs:
            t = m.get(*p)
            if t is None:
                continue
            # a neighbour in the way first (a spare dense piece on a floor tile beside it)
            def clear(q):
                tq = m.get(*q)
                for o in dense_spare(q):
                    tq.objs.remove(o)
                if not any(FN.is_dense(o) for o in tq.objs):
                    # what stood on a table that went goes with it (no loose crowbars on the floor)
                    tq.objs = [o for o in tq.objs if not o.path.startswith("/obj/item")]
            done = False
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                q = (p[0] + dx, p[1] + dy)
                if q in floor and dense_spare(q):
                    clear(q)
                    done = True
                    break
            if not done:
                clear(p)


if __name__ == "__main__":
    dept = sys.argv[1] if len(sys.argv) > 1 else "medical"
    target = float(sys.argv[2]) if len(sys.argv) > 2 else 450
    W = int(sys.argv[3]) if len(sys.argv) > 3 else 24
    P = plan(dept, target, W, 40, "cli")
    ids = {}
    for rm in P.rooms:
        for c in rm["F"]:
            ids[c] = chr(ord("a") + rm["id"] % 26)
    for y in range(P.Dmax, -1, -1):
        print("".join("D" if (x, y) in P.doors or (x, y) in P.front else "." if (x, y) in P.corr else ids.get((x, y), "#")
                      for x in range(P.W)))
    for rm in P.rooms:
        print(chr(ord("a") + rm["id"] % 26), rm["area"], len(rm["F"]))
