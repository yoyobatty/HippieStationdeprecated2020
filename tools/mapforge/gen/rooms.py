"""Stage S3, rooms by stock copies first: fill each department block of a block plan (gen/blocks.py) with real human
rooms from all 38 maps (gen/stamps.py), copied whole by forge/room_stamp.py.

    from gen import rooms
    placed = rooms.furnish(L, m)          # L: blocks.Layout after paint(), m: its dmm.Map; edits m in place

Per department:
  program   the room types 8+ of the 32 families have for that department (studies/stamp_supply.py), most
            common first: a type half the families have is always wanted, a rarer one with its prevalence (seeded).
            The checkpoints, the test range and AI-satellite-only rooms are left out (they are placed elsewhere).
  sources   for each type, the copyable stock rooms (gen/stamps.py, unknown paths resolved), the cleanest first
            (fewest stacked wall pieces), then by size: the copy whose size best fits what is left of the block.
  packing   skyline style: a room's floor box goes at a free corner of the block (a cell with no free cell to its
            left or below), in any of 8 orientations; its floor must lie inside the block's inner cells, its wall
            ring inside the block, neither on another room's floor (rooms share walls). Of the fits, the one whose
            ring lies most on the block's outline and other rooms' rings (tight packing), then nearest the block's
            hall front for public types.
  corridor  the block's inner cells no room took are the department's own corridor (its block area).
  doors     each room gets a door from its ring to the corridor, a hall, maint or a placed room already reached
            (the source's own door where it lands on one); a room nothing reaches is taken out again (its floor
            joins the corridor).
"""
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", "studies"))
sys.path.insert(0, HERE)
import corpus_common as CC  # noqa: E402
import stamps as STP  # noqa: E402
from forge import dmm, room_stamp  # noqa: E402

N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
N8 = [(dx, dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy]
MIN_FAM = 8
SKIP = ("/area/security/checkpoint", "/area/science/test_area", "/area/construction/mining/aux_base",
        "/area/engine/supermatter",
        "/area/science/mixing/chamber", "/area/solar", "/area/maintenance", "/area/hallway")
PUBLIC = ("lobby", "bar", "kitchen", "chapel/main", "library", "hydroponics", "storage/primary", "theatre",
          "courtroom", "quartermaster/office", "medbay/central", "research", "dorms", "locker", "fitness", "hop",
          "lawoffice", "janitor", "vacant_room")
_TYPES = None


def program_types():
    """{group: [(families, area, median size)]} for room types 8+ families have, most common first."""
    global _TYPES
    if _TYPES is None:
        import json
        d = json.load(open(os.path.join(CC.OUT, "stamp_supply_targets.json")))
        lib = STP.library()
        out = {}
        for a, t in d["types"].items():
            if t["families"] < MIN_FAM or a.startswith(SKIP) or a not in lib:
                continue
            out.setdefault(t["group"], []).append((t["families"], a, t["size"][1]))
        for g in out:
            out[g].sort(key=lambda x: (-x[0], x[1]))
        _TYPES = out
    return _TYPES


_SRC = {}


def source(entry):
    k = (entry["map"], entry["area"])
    if k not in _SRC:
        _SRC[k] = room_stamp.Source(entry["map"], entry["area"])
    return _SRC[k]


def _footprints(src):
    out = []
    for k in range(8):
        F, R, D = src.footprint(k)
        x0 = min(p[0] for p in F)
        y0 = min(p[1] for p in F)
        F = [(p[0] - x0, p[1] - y0) for p in F]
        R = [(p[0] - x0, p[1] - y0) for p in R]
        D = {(p[0] - x0, p[1] - y0) for p in D}
        inner = {(lambda q: (q[0] - x0, q[1] - y0))(src.rel(q, k)) for q in src.inner}
        out.append((k, F, R, D, inner, (x0, y0)))
    return out


class Block:
    def __init__(self, dept, cells, own, shared=()):
        """shared: departments this block shares one wall with, where that wall is theirs (blocks.Layout.paint
        gives a touching pair's wall to the lower-numbered block): the cells beside them stay inner."""
        self.dept = dept
        self.cells = set(cells)
        self.outline = {c for c in self.cells
                        if any((c[0] + dx, c[1] + dy) not in self.cells and own.get((c[0] + dx, c[1] + dy)) not in shared
                               for dx, dy in N8)}
        self.inner = self.cells - self.outline
        self.own = own
        self.floor, self.ring = set(), set()
        front = set()
        for c in self.outline:
            for dx, dy in N4:
                if own.get((c[0] + dx, c[1] + dy)) in ("hall", "arrivals", "escape"):
                    front.add(c)
        self.front = front

    def fits(self, F, R, o):
        Fm = [(o[0] + p[0], o[1] + p[1]) for p in F]
        for c in Fm:
            if c not in self.inner or c in self.floor or c in self.ring:
                return None
        Rm = [(o[0] + p[0], o[1] + p[1]) for p in R]
        for c in Rm:
            if c not in self.cells or c in self.floor:
                return None
        return Fm, Rm

    def anchors(self):
        """Free corners of the block's free space, each with the corner of a footprint's box that goes there:
        (cell, sx, sy), sx/sy = +1 when the box grows right/up from the cell."""
        free = self.inner - self.floor - self.ring
        out = []
        for c in free:
            for sx in (1, -1):
                for sy in (1, -1):
                    if (c[0] - sx, c[1]) not in free and (c[0], c[1] - sy) not in free:
                        out.append((c, sx, sy))
        return out


CORRIDOR = 0.22          # share of a block's inner floor left as its own corridor


def _rank(e, target):
    """Copies the room stage tries first: no stacked wall pieces, nothing rewritten (resolve), from the 9 maps of
    this codebase's own era, then nearest the wanted size."""
    from forge import parse
    return (e["faults"] > 0, e.get("fixed", 0) > 0, e["map"] not in parse.MAPS,
            abs(e["tiles"] - target) / float(max(1, target)), e["map"])


_LOOK = {}


def look_max(area):
    """The biggest a copy of a type may be: the biggest look-map room of it (the gate's oversized check), 1.25x that
    when only 2 look rooms have it, no cap with fewer."""
    if area not in _LOOK:
        from forge import room_stats as RS
        kind = RS.type_of(area)
        sizes = [p.stats["tiles"] for p in RS.peers(kind)] if kind else []
        _LOOK[area] = (max(sizes) if len(sizes) >= 3 else max(sizes) * 1.25 if len(sizes) == 2 else 10 ** 6)
    return _LOOK[area]


def _place(B, lib, area, size, left, r):
    """The best fit of a copy of `area` into block B with at most `left` floor tiles, or None."""
    cap = look_max(area)
    ents = [e for e in lib[area] if e["tiles"] <= left * 1.05 and e["tiles"] <= cap]
    if not ents:
        return None
    target = min(size, left) if size else min(e["tiles"] for e in ents)
    ents.sort(key=lambda e: _rank(e, target))
    pool = ents[:4]
    pub = any(x in area for x in PUBLIC)
    anchors = B.anchors()
    for e in pool[:3]:
        try:
            src = source(e)
        except Exception:
            continue
        best = None
        for k, F, R, D, inner, _ in _footprints(src):
            fw = max(p[0] for p in F)
            fh = max(p[1] for p in F)
            for c, sx, sy in anchors:
                a = (c[0] if sx > 0 else c[0] - fw, c[1] if sy > 0 else c[1] - fh)
                got = B.fits(F, R, a)
                if not got:
                    continue
                Fm, Rm = got
                tight = sum(1 for q in Rm if q in B.outline or q in B.ring) / float(len(Rm))
                fr = sum(1 for q in Rm if q in B.front) / float(len(Rm))
                sc = tight + (0.6 * fr if pub else -0.2 * fr) + 0.01 * r.random()
                if best is None or sc > best[0]:
                    best = (sc, e, src, k, a, Fm, Rm, {(a[0] + p[0], a[1] + p[1]) for p in D},
                            {(a[0] + p[0], a[1] + p[1]) for p in inner})
        if best is not None:
            return best[1:]
    return None


def furnish(L, m, log=print):
    r = random.Random("rooms|%s|%d|%d|%d" % (L.p["shape"], L.p["crew"], L.p["seed"], L.info.get("sub", 0)))
    lib = STP.library()
    types = program_types()
    ox, oy = L.offset
    placed = []
    from blocks import RING
    for dept in ("command",) + RING:
        cells = [c for c, o in L.own.items() if o == dept]
        if len(cells) < 20:
            continue
        from blocks import RING as _R, pkey as _pk
        ids = {d: i for i, d in enumerate(("command",) + _R + ("testsite",))}
        shared = {e for e in ids if e != dept and _pk(dept, e) in L.touch and ids[e] < ids[dept]}
        B = Block(dept, cells, L.own, shared)
        budget = len(B.inner) * 0.85
        want = []
        for fam, area, size in types.get(dept, []):
            if area == CORRIDOR_AREA.get(dept):
                continue
            p = fam / 32.0
            if p >= 0.5 or r.random() < p:
                want.append((fam, area, size))
        rooms = []
        used = 0
        # pass 1: the program, most common types first; pass 2: the department's types again, smallest copies,
        # into what is still open, until the corridor is down to CORRIDOR of the block's inner floor
        second = sorted([t for t in types.get(dept, []) if t[1] != CORRIDOR_AREA.get(dept)], key=lambda t: t[2])
        for pass_, items in ((1, want), (2, second * 2)):
            for fam, area, size in items:
                left = budget - used if pass_ == 1 else len(B.inner - B.floor - B.ring) - CORRIDOR * len(B.inner)
                if left < 6:
                    if pass_ == 1:
                        break
                    continue
                got = _place(B, lib, area, size if pass_ == 1 else 0, left, r)
                if got is None:
                    continue
                e, src, k, a, Fm, Rm, D, inner = got
                B.floor.update(Fm)
                B.ring.update(Rm)
                used += len(Fm)
                rooms.append(dict(area=area, entry=e, src=src, k=k, a=a, F=set(Fm), R=set(Rm), D=D, inner=inner))
        ch = _chambers(B, r) if dept == "atmos" else []
        rooms = _size_to_band(dept, rooms, B)
        corridor = B.inner - B.floor - B.ring
        doors = _doors(B, rooms, corridor, L.own, r)
        _second_doors(B, rooms, corridor, L.own, doors, r)
        kept = [rm for rm in rooms if rm.get("door")]
        for rm in rooms:
            if not rm.get("door"):
                corridor |= rm["F"]
        corridor, pocket, pwall, pdoors = _split_corridor(B, corridor, doors, r)
        _paint_block(m, L, B, kept, corridor, doors, ox, oy)
        _paint_pockets(m, L, pocket, pwall, pdoors, ox, oy)
        if ch:
            _paint_chambers(m, ch, CORRIDOR_AREA["atmos"], ox, oy)
        for rm in kept:
            placed.append((dept, rm["area"], rm["entry"]["map"], len(rm["F"])))
        log("rooms: %-12s %2d rooms (%d dropped unreached), corridor %d of %d inner" % (
            dept, len(kept), len(rooms) - len(kept), len(corridor), len(B.inner)))
    touch_doors(m, L, log)
    return placed


def _doors(B, rooms, corridor, own, r):
    """Give each room a door so every room is reached from outside the block: BFS over rooms from the corridor,
    halls and maint. A door is a ring cell (not an inner wall of the copy) with the room's floor on one side and
    a reached place on the other."""
    outside = ("hall", "arrivals", "escape", "maint")
    reached_cells = set(corridor)
    # corridor pieces count as reached only if they touch the block's outline next to a hall or maint (a front
    # door is cut there) or a room reached later
    doors = []
    front_ok = set()
    for c in B.outline:
        for dx, dy in N4:
            a, b = (c[0] + dx, c[1] + dy), (c[0] - dx, c[1] - dy)
            if a in corridor and own.get(b) in outside:
                front_ok.add(c)
    reached_cells = set()
    comps = _comps(corridor)
    for comp in comps:
        fronts = [c for c in front_ok if any((c[0] + dx, c[1] + dy) in comp for dx, dy in N4)]
        if fronts:
            d = r.choice(sorted(fronts))
            doors.append(d)
            reached_cells |= comp
    pending = list(rooms)
    changed = True
    while changed and pending:
        changed = False
        for rm in list(pending):
            opts = []
            for c in rm["R"] - rm["inner"]:
                for dx, dy in N4:
                    a, b = (c[0] + dx, c[1] + dy), (c[0] - dx, c[1] - dy)
                    if a in rm["F"] and (b in reached_cells or (b not in B.cells and own.get(b) in outside)):
                        opts.append((0 if c in rm["D"] else 1, c, b))
            if opts:
                opts.sort()
                c, b = opts[0][1], opts[0][2]
                rm["door"] = c
                doors.append(c)
                reached_cells |= rm["F"]
                # a corridor piece reached only through this room is reached now
                for comp in comps:
                    if not (comp & reached_cells) and any(((x[0] + dx, x[1] + dy) in rm["F"])
                                                          for x in comp for dx, dy in N8):
                        opts2 = [w for w in rm["R"] - rm["inner"]
                                 if any((w[0] + dx, w[1] + dy) in comp for dx, dy in N4)
                                 and any((w[0] + dx, w[1] + dy) in rm["F"] for dx, dy in N4)]
                        if opts2:
                            doors.append(sorted(opts2)[0])
                            reached_cells |= comp
                pending.remove(rm)
                changed = True
    return doors


ONE_DOOR = 0.40          # human median share of rooms with one way in (space_sizes.py)


def _second_doors(B, rooms, corridor, own, doors, r):
    """Rooms with one door get a second, onto the corridor, a hall, maint or a neighbouring room of the block,
    until the block's one-door share is down to the human median."""
    outside = ("hall", "arrivals", "escape", "maint")
    floor_of = {}
    for i, rm in enumerate(rooms):
        if rm.get("door"):
            for c in rm["F"]:
                floor_of[c] = i
    kept = [rm for rm in rooms if rm.get("door")]
    if not kept:
        return
    order = list(range(len(rooms)))
    r.shuffle(order)
    ds = set(doors)
    for i in order:
        rm = rooms[i]
        if not rm.get("door"):
            continue
        one = sum(1 for x in kept if len(x.get("doors2", ())) == 0) / float(len(kept))
        if one <= ONE_DOOR:
            break
        opts = []
        for c in rm["R"] - rm["inner"]:
            if c in ds or any((c[0] + dx, c[1] + dy) in ds for dx, dy in N8):
                continue
            for dx, dy in N4:
                a, b = (c[0] + dx, c[1] + dy), (c[0] - dx, c[1] - dy)
                if a in rm["F"] and (b in corridor or floor_of.get(b, i) != i or
                                     (b not in B.cells and own.get(b) in outside)):
                    opts.append(c)
        if opts:
            c = r.choice(sorted(opts))
            doors.append(c)
            ds.add(c)
            rm["doors2"] = [c]


def _size_to_band(dept, rooms, B):
    """The gate checks the median room size per department (space_sizes.py room_size_<dept>, band from the corpus
    and the look maps). Below the band, the smallest copies are taken out (their floor joins the corridor) until
    the median is in it."""
    import gate as G
    band = G.bands()[0].get("space.room_size_" + dept)
    if not band or len(rooms) < 3:
        return rooms
    lo = band[0]
    rooms = sorted(rooms, key=lambda rm: len(rm["F"]))
    while len(rooms) > 2 and CC.median([len(rm["F"]) for rm in rooms]) < lo:
        rm = rooms.pop(0)
        B.floor -= rm["F"]
        B.ring -= rm["R"] - set().union(*[x["R"] for x in rooms])
    return rooms


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


CORRIDOR_MAX = 120      # a department corridor piece at most this big (and under its area type's look-map max)
# a department's own corridor gets an area no copied room uses, so room_stats never joins it to a copy of the same
# area: the department's parent area where that exists here and its look-map peers run 130+ tiles, else a type the
# program then leaves out (atmos, dorms) or the heads' area (command)
CORRIDOR_AREA = {"command": "/area/crew_quarters/heads", "security": "/area/security", "medical": "/area/medical/medbay",
                 "science": "/area/science", "engineering": "/area/engine", "atmos": "/area/engine/atmos",
                 "cargo": "/area/quartermaster", "service": "/area/crew_quarters", "civic": "/area/chapel",
                 "dorms": "/area/crew_quarters/dorms", "ai": "/area/ai_monitored/turret_protected"}


def _split_corridor(B, corridor, doors, r):
    cmax = min(CORRIDOR_MAX, int(look_max(CORRIDOR_AREA.get(B.dept, "")) * 0.9)) if B.dept in CORRIDOR_AREA \
        else CORRIDOR_MAX
    if B.dept == "atmos":       # atmos's main floor is one big room on every stock map (321-490 tiles)
        cmax = int(look_max(CORRIDOR_AREA["atmos"]) * 0.85)
    """A corridor piece over CORRIDOR_MAX keeps the cells nearest its doors; the rest becomes a maint pocket (human
    maint is 30-68% open 3x3 fields, 1.8-5.9 pockets a 1000 tiles), walled off from the corridor with one
    maintenance door. Returns (corridor, pocket cells, pocket wall cells, pocket doors)."""
    keep, pocket, pwall, pdoors = set(), set(), set(), []
    dset = set(doors)
    left = cmax            # for the whole block: room_stats joins same-area pieces within 2 tiles into one room
    for comp in sorted(_comps(corridor), key=lambda c: -len(c)):
        if len(comp) <= left:
            keep |= comp
            left -= len(comp)
            continue
        if left < 6:
            # no corridor budget left: the whole piece becomes maint pockets (cut to POCKET_MAX); the room doors
            # that open on it already lead in
            walls, ds = _cut_pocket(comp, r)
            pocket |= comp - walls - set(ds)
            pwall |= walls
            pdoors.extend(ds)
            continue
        cmax_here = left
        seeds = [c for c in comp if any((c[0] + dx, c[1] + dy) in dset for dx, dy in N4)] or [min(comp)]
        order, seen = [], set(seeds)
        q = list(seeds)
        while q:
            a = q.pop(0)
            order.append(a)
            for dx, dy in N4:
                b = (a[0] + dx, a[1] + dy)
                if b in comp and b not in seen:
                    seen.add(b)
                    q.append(b)
        k = set(order[:cmax_here])
        left -= len(k)
        rest = comp - k
        # the line between them: rest cells touching the kept corridor become wall
        line = {c for c in rest if any((c[0] + dx, c[1] + dy) in k for dx, dy in N8)}
        rest -= line
        for pc in _comps(rest):
            if len(pc) < 6:
                line |= pc
                continue
            cuts = _cut_pocket(pc, r)
            pc -= cuts[0]
            line |= cuts[0]
            pdoors.extend(cuts[1])
            cand = sorted(c for c in line if any((c[0] + dx, c[1] + dy) in pc for dx, dy in N4)
                          and any((c[0] + dx, c[1] + dy) in k for dx, dy in N4))
            if cand:
                pdoors.append(r.choice(cand))
                pocket |= pc
            else:
                k |= pc            # no way in from the corridor: it stays corridor
        keep |= k
        pwall |= line - set(pdoors)
    return keep, pocket, pwall, pdoors


POCKET_MAX = 50          # human maint pockets: median 21 tiles, 15..54 over families (space_sizes.py)


def _cut_pocket(pc, r):
    """Cut a maint pocket over POCKET_MAX with straight walls (one door each) until every piece is under it.
    Returns (wall cells, door cells)."""
    walls, doors = set(), []
    stack = [set(pc)]
    while stack:
        cs = stack.pop()
        if len(cs) <= POCKET_MAX:
            continue
        xs = [c[0] for c in cs]
        ys = [c[1] for c in cs]
        vert = (max(xs) - min(xs)) >= (max(ys) - min(ys))
        lo, hi = (min(xs), max(xs)) if vert else (min(ys), max(ys))
        if hi - lo < 4:
            continue
        cut = (lo + hi) // 2 + r.randint(-1, 1)
        line = {c for c in cs if (c[0] if vert else c[1]) == cut}
        a = {c for c in cs if (c[0] if vert else c[1]) < cut}
        b = {c for c in cs if (c[0] if vert else c[1]) > cut}
        ok = sorted(c for c in line if ((c[0] - 1, c[1]) in a and (c[0] + 1, c[1]) in b) or
                    ((c[0], c[1] - 1) in a and (c[0], c[1] + 1) in b))
        if not ok:
            continue
        d = ok[len(ok) // 2]
        walls |= line - {d}
        doors.append(d)
        stack += [a, b]
    return walls, doors


GASES = ("n2", "o2", "plasma", "co2", "air")


def _chambers(B, r):
    """Atmos's gas chambers, as every stock atmos has them: 3x3 rooms of the gas's own engine floor against the
    block's back wall (away from the hall), up to five, in a row along one outline side. Returns
    [(gas, floor cells, ring cells)] and marks them taken in B."""
    out = []
    back = [c for c in B.outline if c not in B.front]
    back.sort()
    r.shuffle(back)
    for gas in GASES:
        best = None
        for c in back:
            for dx, dy in N4:
                # the chamber's ring sits on the outline: floor is the 3x3 one in from c
                cx, cy = c[0] - 2 * dx, c[1] - 2 * dy
                F = {(cx + i, cy + j) for i in (-1, 0, 1) for j in (-1, 0, 1)}
                R = {(cx + i, cy + j) for i in (-2, -1, 0, 1, 2) for j in (-2, -1, 0, 1, 2)} - F
                if not all(f in B.inner and f not in B.floor and f not in B.ring for f in F):
                    continue
                if not all(q in B.cells and q not in B.floor for q in R):
                    continue
                score = sum(1 for q in R if q in B.outline or q in B.ring)
                if best is None or score > best[0]:
                    best = (score, F, R)
            if best and best[0] >= 9:
                break
        if best is None:
            break
        _, F, R = best
        B.floor |= F
        B.ring |= R
        out.append((gas, F, R))
    return out


def touch_doors(m, L, log=print):
    """A door between each touching pair that humans join by a door nearly always (atmos and engineering, P(door)
    0.90): through one wall where their floors face each other, else through the fewest walls (up to 4) in a
    straight line (up to 8), the walls past the door becoming a short passage."""
    from forge import parse
    sm = parse.SemanticMap(m, "tmp", 1)
    for k in ("atmos|engineering",):
        if k not in L.touch:
            continue
        a, b = k.split("|")
        done = False
        for steps in range(1, 9):
            for p, c in sm.cls.items():
                if c != "F" or sm.group.get(p) != a:
                    continue
                for dx, dy in N4:
                    ws = [(p[0] + dx * i, p[1] + dy * i) for i in range(1, steps + 1)]
                    q = (p[0] + dx * (steps + 1), p[1] + dy * (steps + 1))
                    if all(sm.cls.get(w) == "W" and w not in sm.glass for w in ws) and sm.cls.get(q) == "F" \
                            and sm.group.get(q) == b:
                        t = m.get(*ws[0])
                        t.objs = [dmm.Atom("/obj/machinery/door/airlock")]
                        t.turf = dmm.Atom("/turf/open/floor/plasteel")
                        for w in ws[1:]:          # the walls past the door become a short passage
                            t2 = m.get(*w)
                            t2.objs = []
                            t2.turf = dmm.Atom("/turf/open/floor/plasteel")
                            t2.area = dmm.Atom(sm.area.get(q))
                        done = True
                        break
                if done:
                    break
            if done:
                break
        log("rooms: %s door %s" % (k, "cut" if done else "NOT FOUND"))


def _paint_chambers(m, ch, area, ox, oy):
    for gas, F, R in ch:
        for c in F:
            m.set(c[0] + ox, c[1] + oy, dmm.Tile([], dmm.Atom("/turf/open/floor/engine/" + gas), dmm.Atom(area)))
        for c in R:
            m.set(c[0] + ox, c[1] + oy, dmm.Tile([], dmm.Atom("/turf/closed/wall/r_wall"), dmm.Atom(area)))


def _paint_pockets(m, L, pocket, pwall, pdoors, ox, oy):
    for c in pocket | pwall | set(pdoors):
        x, y = c[0] + ox, c[1] + oy
        area = L._area(c, "maint")
        if c in pocket:
            t = dmm.Tile([], dmm.Atom("/turf/open/floor/plating"), dmm.Atom(area))
        elif c in pdoors:
            t = dmm.Tile([dmm.Atom("/obj/machinery/door/airlock/maintenance")], dmm.Atom("/turf/open/floor/plating"),
                         dmm.Atom(area))
        else:
            continue
        m.set(x, y, t)


def _paint_block(m, L, B, rooms, corridor, doors, ox, oy):
    from blocks import AREA
    area = CORRIDOR_AREA.get(B.dept) or AREA.get(B.dept, "/area/space")
    wall = "/turf/closed/wall"
    for c in B.cells:
        x, y = c[0] + ox, c[1] + oy
        if c in corridor:
            t = dmm.Tile([], dmm.Atom("/turf/open/floor/plasteel"), dmm.Atom(area))
        else:
            t = dmm.Tile([], dmm.Atom(wall), dmm.Atom(area))
        m.set(x, y, t)
    for rm in rooms:
        o = (rm["a"][0] + ox, rm["a"][1] + oy)
        src, k = rm["src"], rm["k"]
        # apply() places the source's floor origin at `origin`; our footprint was shifted to its box corner
        F0, _, _ = src.footprint(k)
        x0 = min(p[0] for p in F0)
        y0 = min(p[1] for p in F0)
        origin = (o[0] - x0, o[1] - y0)
        cut = {(d[0] + ox, d[1] + oy) for d in doors if d in rm["R"]}
        room_stamp.apply(m, src, k, origin, cut, door_atom=dmm.Atom("/obj/machinery/door/airlock"))
        for c in rm["F"] | rm["R"]:
            t = m.get(c[0] + ox, c[1] + oy)
            if t is None:
                continue
            objs = []
            for a in t.objs:
                p = STP.resolve(a.path)
                if p:
                    if p != a.path:
                        a = dmm.Atom(p, list(a.vars))
                    objs.append(a)
            t.objs = objs
            if t.area is not None and STP.resolve(t.area.path) != t.area.path:
                t.area = dmm.Atom(area)
            if t.turf is not None:
                tp = STP.resolve(t.turf.path)
                if tp and tp != t.turf.path:
                    t.turf = dmm.Atom(tp, list(t.turf.vars))
    # doors onto halls, maint and corridor pieces (cut in the block outline or between corridor and room)
    for d in doors:
        t = m.get(d[0] + ox, d[1] + oy)
        if t is not None and not t.has("/obj/machinery/door"):
            t.objs = [dmm.Atom("/obj/machinery/door/airlock")]
            t.turf = dmm.Atom("/turf/open/floor/plasteel")
