"""Room budget for the v6 station (v6_station.py calls rooms() right after maint_rooms): space the station spends
where the stock stations don't goes to the rooms they have and v6 lacks. Every number comes from
forge/size_budget.py against Meta, Delta, Omega and Hippie (the user's ruling 2026-11-22: "rooms that are
inappropriately oversized should be shrunk and that new room should be naturally absorbed into the station's size
budget ... objective data with iterations").

What size_budget found on the paused v6 (2026-11-22): halls 20.5% of the floor against the stock 9-13%, half of it
in plazas 7+ tiles wide; the arrivals and escape lobbies drawn as central hall (arrivals 1.8%, escape 0%, stock
2.1-5.7% and 1.3-3.0%); three abandoned maint rooms 2-6x the stock size of their type; 11 room types that 3-4 of the
stock maps have and v6 has nowhere.

Steps:
  lobbies   the arrivals lobby and the escape lobby become the arrivals and escape hall areas
  reclaim   free tiles: the plazas off the arms and the ring, the two public lounges, and the oversized maint rooms
            (v6_station.MAINT_ROOMS entries whose type size_budget finds above every stock room, OVERSIZED below);
            a tile in front of a door stays as it is
  pack      each missing type, biggest first, is a stock room copied whole (forge/room_stamp.py) from Meta, Delta or
            Hippie: every source, every orientation, every position whose floor lies on free tiles and whose outline
            lies on free tiles or on walls already there. Score: the source's size off the stock median (relative),
            plus its distance from its own department (or from a hall, for public rooms) over 40; a placement needs
            a door onto a hall, maint or its own department, and the halls must stay one piece.
  leftover  free tiles no room took keep what they were (hall stays hall, maint plating stays maint)

Not placed here (they need space outside the hull, not floor inside): the aux base and the bomb test range.
"""
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import dmm, kit, parse, room_stats as RS, room_stamp, size_budget  # noqa: E402


def _plan_package():
    """tools/mapforge/plan as the package `plan`: run as a script, v6_station.py has station/ first on sys.path,
    where station/plan.py would shadow it (plan/canvas.py imports `from plan import station_plan` itself)."""
    # plan/ has no __init__.py: a namespace package loses to any plain plan.py on sys.path, so build it by hand
    import importlib.util
    import types
    d = os.path.join(HERE, "..", "plan")
    old = sys.modules.get("plan")
    pkg = types.ModuleType("plan")
    pkg.__path__ = [d]
    sys.modules["plan"] = pkg
    mods = []
    try:
        for name in ("station_plan", "canvas"):
            spec = importlib.util.spec_from_file_location("plan." + name, os.path.join(d, name + ".py"))
            mod = importlib.util.module_from_spec(spec)
            sys.modules["plan." + name] = mod
            setattr(pkg, name, mod)
            spec.loader.exec_module(mod)
            mods.append(mod)
    finally:
        if old is not None:
            sys.modules["plan"] = old
    return mods


P, C = _plan_package()

SOURCES = ("MetaStation", "DeltaStation", "HippieStation")      # our codebase's own maps: no path aliasing
OUTSIDE = ("/area/construction/mining/aux_base", "/area/science/test_area")
OVERSIZED = ("/area/hydroponics/garden/abandoned", "/area/storage/tools", "/area/crew_quarters/theatre/abandoned")
REPLACE = {"/area/storage/tools": "/area/storage/tools"}       # an oversized maint room whose type comes back, stock size
PUBLIC = ("civic", "dorms", None)
# where a room belongs when its area path files it elsewhere: a checkpoint guards the department it stands in (stock
# maps: inside or at the door of cargo and medbay); telecomms control sits by its server room
# rooms the stock maps lay side by side, copied as one piece when both are wanted (each keeps its own area)
PAIRS = {"/area/tcommsat/server": "/area/tcommsat/computer"}
NEAR = {"/area/security/checkpoint/supply": "cargo", "/area/security/checkpoint/medical": "medical",
        "/area/tcommsat/computer": "@/area/tcommsat/server"}
WALK_AREAS = ("/area/hallway", "/area/maintenance")
D4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
HALL_AREAS = ("/area/hallway",)


def _walk(t):
    return t is not None and t.tpath.startswith("/turf/open") and not any(
        o.path.startswith(("/obj/structure/window", "/obj/effect/spawner/structure/window", "/obj/structure/grille"))
        for o in t.objs)


def _is_door(t):
    return t is not None and t.has("/obj/machinery/door/airlock")


def _wall(t):
    return t is not None and t.tpath.startswith("/turf/closed") and not _is_door(t)


# the lobbies cut to the stock width (size_budget 2026-11-22: hall floor 7+ wide 33%, stock at most 19%; stock
# arrivals and escape halls are 3-6 wide): the band of each kept, plan rows/columns, the rest goes to closets
LOBBY_KEEP = {"arrivals lobby": ("y", 76, 81), "escape lobby": ("x", 87, 91)}   # arrivals: the rows its doors are on


# stock escape areas take in the corridor to the dock (Meta's escape hallway): arm S's south stretch, plan rows
ESCAPE_ARM = (115, 135)


def escape_hall(m, log):
    n = 0
    for p in P.tiles_of(P.HALLS["arm S"]):
        if ESCAPE_ARM[0] <= p[1] <= ESCAPE_ARM[1]:
            t = m.get(*C.to_map(p))
            if t is not None and t.apath == "/area/hallway/primary/central":
                t.area = dmm.Atom("/area/hallway/secondary/exit")
                n += 1
    log("rooms: escape hall: %d tiles of arm S" % n)


def lobby_bands(m):
    out = set()
    for key, (axis, lo, hi) in LOBBY_KEEP.items():
        for p in P.tiles_of(P.HALLS[key]):
            v = p[1] if axis == "y" else p[0]
            if not lo <= v <= hi:
                q = C.to_map(p)
                if _walk(m.get(*q)):
                    out.add(q)
    return out


def arterials(m, log, sm):
    """Hall over the stock share and maint under it (size_budget 2026-11-22): the 2-wide arterials become maint
    corridors, the one with the fewest public doors first, until the hall share is inside the stock range. Each
    keeps its doors (the departments' back doors onto maint, as stock maps have them); where it meets a hall, one
    tile of its mouth becomes a maint door and the other wall."""
    station = float(len(sm.station_tiles()))
    hall = sum(1 for p in sm.station_tiles() if sm.group.get(p) == "hall")
    # 5% under the stock max: the passes after this one (docks, solars, glazing) move the share a little
    stock_max = 0.95 * max(size_budget.group_shares(parse.load(n))[0].get("hall", 0) for n in RS.REFS)
    cands = []
    for k, r in P.HALLS.items():
        if not k.startswith("art"):
            continue
        ts = {C.to_map(p) for p in P.tiles_of(r)}
        ts = {q for q in ts if m.get(*q) is not None and _walk(m.get(*q)) and m.get(*q).apath.startswith(HALL_AREAS)}
        public = 0
        for (x, y, z), t in m.tiles.items():
            if _is_door(t) and any((x + dx, y + dy) in ts for dx, dy in D4):
                if not any(m.get(x - dx, y - dy) is not None and m.get(x - dx, y - dy).apath.startswith("/area/maintenance")
                           for dx, dy in D4 if (x + dx, y + dy) in ts):
                    public += 1
        cands.append((public, len(ts), k, ts))
    cands.sort(key=lambda c: (c[0], -c[1]))
    done = []
    for public, n, k, ts in cands:
        if hall / station <= stock_max:
            break
        # each public door on the run keeps the shortest corridor from it to the rest of the halls (the user
        # 2026-11-22: atmos' front door opened onto maint once art SE went; a department's way in stays a hall)
        keep = set()
        for (x, y, z), t in m.tiles.items():
            if not _is_door(t):
                continue
            starts = [(x + dx, y + dy) for dx, dy in D4 if (x + dx, y + dy) in ts]
            if not starts or any(m.get(x - dx, y - dy) is not None and m.get(x - dx, y - dy).apath.startswith("/area/maintenance")
                                 for dx, dy in D4 if (x + dx, y + dy) in ts):
                continue
            prev, q, seen, hit = {}, list(starts), set(starts), None
            while q and hit is None:
                nq = []
                for c in q:
                    if any((c[0] + dx, c[1] + dy) not in ts and m.get(c[0] + dx, c[1] + dy) is not None and
                           _walk(m.get(c[0] + dx, c[1] + dy)) and m.get(c[0] + dx, c[1] + dy).apath.startswith(HALL_AREAS)
                           for dx, dy in D4):
                        hit = c
                        break
                    for dx, dy in D4:
                        b = (c[0] + dx, c[1] + dy)
                        if b in ts and b not in seen:
                            seen.add(b)
                            prev[b] = c
                            nq.append(b)
                q = nq
            while hit is not None:
                keep.add(hit)
                hit = prev.get(hit)
        # the arterial's whole width over the kept stretch, so what goes to maint meets it at one mouth (a one-row
        # corridor left the other row a line of maint doors)
        if keep:
            xs, ys = [q[0] for q in ts], [q[1] for q in ts]
            along = 0 if max(xs) - min(xs) >= max(ys) - min(ys) else 1
            span = {q[along] for q in keep}
            keep = {q for q in ts if min(span) <= q[along] <= max(span)}
        ts = ts - keep
        n = len(ts)
        if not ts:
            continue
        maint = [(x, y, t.apath) for (x, y, z), t in m.tiles.items() if t.apath.startswith("/area/maintenance") and _walk(t)]
        cx, cy = next(iter(ts))
        area = min(maint, key=lambda q: abs(q[0] - cx) + abs(q[1] - cy))[2]
        for q in ts:
            t = m.get(*q)
            m.set(q[0], q[1], dmm.Tile([o for o in t.objs if not o.path.startswith("/obj/effect/turf_decal")],
                                       dmm.Atom("/turf/open/floor/plating"), dmm.Atom(area)))
        # the mouths: arterial tiles beside hall floor
        mouth = sorted(q for q in ts if any(m.get(q[0] + dx, q[1] + dy) is not None and
                                            m.get(q[0] + dx, q[1] + dy).apath.startswith(HALL_AREAS) and
                                            _walk(m.get(q[0] + dx, q[1] + dy)) for dx, dy in D4))
        for i, q in enumerate(mouth):
            if i % 2 == 0:
                m.set(q[0], q[1], dmm.Tile([dmm.Atom("/obj/machinery/door/airlock/maintenance", [("req_one_access_txt", '"12"')])],
                                           dmm.Atom("/turf/open/floor/plating"), dmm.Atom(area)))
            else:
                m.set(q[0], q[1], dmm.Tile([], dmm.Atom("/turf/closed/wall"), dmm.Atom(area)))
        hall -= n
        done.append("%s (%d tiles, %d public doors, %d kept as their way in)" % (k, n, public, len(keep)))
    log("rooms: arterials to maint: %s; hall share now %.1f%% (stock max %.1f%%)" % (
        ", ".join(done) or "none", 100 * hall / station, 100 * stock_max))


def reclaimable(m):
    keep = set()
    for k, r in P.HALLS.items():
        if k.startswith(("ring", "arm", "AI", "art")):
            keep |= set(P.tiles_of(r))
    free = set()
    for k in ("plaza N", "plaza S", "plaza W", "plaza E", "north plaza"):
        free |= {C.to_map(p) for p in P.tiles_of(P.HALLS[k]) if p not in keep}
    for r in P.BLOCKS["public"]:
        free |= {C.to_map(p) for p in P.tiles_of(r)}
    return {p for p in free if _walk(m.get(*p)) and m.get(*p).apath.startswith(HALL_AREAS)}


def budget_skips(m, maint_rooms, log):
    """The abandoned maint rooms are flavour: each takes a department's area (the abandoned research lab is
    /area/science/research/abandoned), so it counts toward that department's share. One that would push its
    department past 93% of the most any stock map gives it is not built, and its tiles go to the room budget
    (size_budget 2026-11-22: science 10.9% and civic 7.0% against stock maxima 10.3% and 6.8%, the abandoned
    research lab 136 tiles and library 112)."""
    sm = parse.SemanticMap(m, "v6")
    station = float(len(sm.station_tiles()))
    have = Counter(sm.group.get(p) for p in sm.station_tiles())
    stock_max = {}
    for n in RS.REFS:
        for g, v in size_budget.group_shares(parse.load(n))[0].items():
            stock_max[g] = max(stock_max.get(g, 0.0), v)
    out = set(OVERSIZED)
    for (x0, y0, x1, y1), name, area, _, _ in maint_rooms:
        if area in out:
            continue
        g = parse.ST.group_of(area)
        if g in (None, "maint") or g.startswith("other"):
            continue
        n = (x1 - x0 - 1) * (y1 - y0 - 1)
        if (have[g] + n) / station > 0.93 * stock_max.get(g, 1.0):
            out.add(area)
            log("rooms: %s not built: %s would be %.1f%% of the floor (stock max %.1f%%)" % (
                name, g, 100 * (have[g] + n) / station, 100 * stock_max.get(g, 1.0)))
        else:
            have[g] += n
    return out


def over_budget_rooms(m, maint_rooms, forced):
    """After a whole build: the abandoned maint rooms of each department still over the stock maximum share, the
    biggest one per department (the next round drops it)."""
    sm = parse.SemanticMap(m, "v6")
    station = float(len(sm.station_tiles()))
    have = Counter(sm.group.get(p) for p in sm.station_tiles())
    stock_max = {}
    for n in RS.REFS:
        for g, v in size_budget.group_shares(parse.load(n))[0].items():
            stock_max[g] = max(stock_max.get(g, 0.0), v)
    areas = set(sm.area.values())
    out = set()
    by_group = {}
    for (x0, y0, x1, y1), name, area, _, _ in maint_rooms:
        if area in forced or area in OVERSIZED or area not in areas:
            continue
        g = parse.ST.group_of(area)
        if g and have[g] / station > stock_max.get(g, 1.0):
            n = (x1 - x0 - 1) * (y1 - y0 - 1)
            if g not in by_group or n > by_group[g][0]:
                by_group[g] = (n, area)
    return {a for n, a in by_group.values()}


def lobbies(m, log):
    n = Counter()
    for key, area in (("arrivals lobby", "/area/hallway/secondary/entry"), ("escape lobby", "/area/hallway/secondary/exit")):
        for p in P.tiles_of(P.HALLS[key]):
            t = m.get(*C.to_map(p))
            if t is not None and t.apath == "/area/hallway/primary/central":
                t.area = dmm.Atom(area)
                n[key] += 1
    log("rooms: lobbies relabelled: %s" % ", ".join("%s %d tiles" % kv for kv in sorted(n.items())))


def hall_pieces(m, blocked):
    """Connected pieces of the walkable hall and maint floor, not counting `blocked` tiles (a door joins both sides)."""
    hall = {(x, y) for (x, y, z), t in m.tiles.items() if (t.apath.startswith(WALK_AREAS) and _walk(t)) or
            (_is_door(t) and (t.apath.startswith(WALK_AREAS)))} - blocked
    seen, n = set(), 0
    for s in hall:
        if s in seen:
            continue
        n += 1
        q = [s]
        seen.add(s)
        while q:
            c = q.pop()
            for dx, dy in D4:
                b = (c[0] + dx, c[1] + dy)
                if b in hall and b not in seen:
                    seen.add(b)
                    q.append(b)
    return n


_FAULTS = {}


def src_faults(src):
    """Wall-piece faults a stock room brings with it (studies/piece_audit.py's rules on its own floor: a piece over
    furniture, two pieces on one tile). The rulings come before the stock habit: of the stock examples of a type, the
    room with the fewest is copied (the gate 2026-11-22: copied rooms brought 64 pieces over furniture that tidy had
    no clean wall face for)."""
    k = (src.map, src.area, min(src.floor))
    if k not in _FAULTS:
        sys.path.insert(0, os.path.join(HERE, "..", "studies"))
        import piece_audit as PA
        n = 0
        for p in src.floor:
            t = src.sm.m.get(p[0], p[1], src.sm.z)
            if t is None:
                continue
            hs = PA.hung(t)
            if not hs:
                continue
            real = [h for h, _ in hs if not h.path.startswith(PA.PAIRS)]
            if any(o.path.startswith(PA.FURN) or (kit_dense(o) and not o.path.startswith("/obj/machinery/door"))
                   for o in t.objs if all(o is not h for h, _ in hs)):
                n += len(real)
            elif len(real) >= 2:
                n += len(real) - 1
        _FAULTS[k] = n
    return _FAULTS[k]


def kit_dense(o):
    from forge import kit
    return kit.dense([o])


def backdoor_needs(m):
    """The maint tiles each room's back door could open onto (v6_station.layout's rule, which runs after this pass):
    a copied room must leave each such room at least one (the gate 2026-11-22: the copied virology took the maint
    run west of genetics, and genetics lost its back door)."""
    import importlib
    V = sys.modules.get("__main__") if hasattr(sys.modules.get("__main__"), "layout") else importlib.import_module("v6_station")
    needs = []
    for g in V.regions(m):
        t0 = m.get(*next(iter(g)))
        if len(g) < 6 or t0.apath.startswith(V.BACKDOOR_NOT):
            continue
        ways = [(p, d) for p in g for d in V.CARD if m.get(*V.nb(p, d)) is not None and m.get(*V.nb(p, d)).has("/obj/machinery/door")]
        if len(ways) not in (1, 2) or (len(ways) == 2 and len(g) < 16):
            continue
        beyond = set()
        for p in g:
            for d in V.CARD:
                w, b = V.nb(p, d), V.nb(V.nb(p, d), d)
                tw, tb = m.get(*w), m.get(*b)
                if tw and tw.tpath.startswith("/turf/closed/wall") and not tw.objs and tb and V.is_floor(tb)                         and tb.apath.startswith("/area/maintenance"):
                    beyond.add(b)
        if beyond:
            needs.append(beyond)
    return needs


def _takes_backdoor(needs, tiles):
    return any(nd and nd <= tiles for nd in needs)


def rooms(m, log, slots=()):
    """slots: map tiles of maint rooms left unbuilt for this pass (v6_station drops the oversized ones)."""
    lobbies(m, log)
    free = reclaimable(m) | set(slots) | lobby_bands(m)
    # maint corridor within 2 tiles of a slot may go too (a room as big as a stock virology needs the width); the
    # connectivity check below keeps every hall and maint run joined
    near = {(x + dx, y + dy) for (x, y) in slots for dx in range(-2, 3) for dy in range(-2, 3)}
    free |= {p for p in near if m.get(*p) is not None and _walk(m.get(*p)) and m.get(*p).apath.startswith("/area/maintenance")}
    # a tile in front of a door stays as it is (the door must still open onto something)
    for (x, y, z), t in list(m.tiles.items()):
        if _is_door(t):
            for dx, dy in D4:
                free.discard((x + dx, y + dy))
    # only hall and maint tiles are free (a department's wall may still be a copied room's outline): a department's
    # door inside a slot's box was stamped over (the gate 2026-11-22: genetics lost its maint door at 62,67); and a
    # hall tile touching a room's own floor (a hand-out counter, chemistry's at 91,70) stays open
    def own_floor(q):
        tq = m.get(*q)
        return tq is not None and _walk(tq) and not tq.apath.startswith(WALK_AREAS + ("/area/space",))
    free = {p for p in free if m.get(*p) is not None and not _is_door(m.get(*p))
            and m.get(*p).apath.startswith(WALK_AREAS)
            and not any(own_floor((p[0] + dx, p[1] + dy)) for dx, dy in D4)}
    sm = parse.SemanticMap(m, "v6")
    want = [r for r in size_budget.missing(sm) if r["area"] not in OUTSIDE]
    for area in OVERSIZED:
        if area in REPLACE:
            peers = RS.peers(area)
            want.append(dict(area=REPLACE[area], tiles=sorted(p.stats["tiles"] for p in peers)[len(peers) // 2],
                             group=parse.ST.group_of(area)))
    seen_a = set()
    want = [w for w in sorted(want, key=lambda r: -r["tiles"]) if not (w["area"] in seen_a or seen_a.add(w["area"]))]
    by_area = {w["area"]: w for w in want}
    for a, b in PAIRS.items():
        if a in by_area and b in by_area:
            by_area[a]["pair"] = b
            by_area[a]["tiles"] += by_area[b]["tiles"]
            want.remove(by_area[b])
    where = {}
    group_floor = {}
    for p, g in sm.group.items():
        if sm.cls.get(p) == "F":
            group_floor.setdefault(g, []).append(p)
    halls_before = hall_pieces(m, set())
    needs = backdoor_needs(m)
    # department budgets: a room must not push its department's share of the station floor past the most any stock
    # map gives it (size_budget's group shares), when a smaller stock version of the room would fit instead
    station = float(len(sm.station_tiles()))
    room_floor = Counter(sm.group.get(p) for p in sm.station_tiles())
    stock_max = {}
    for name in RS.REFS:
        shares, _ = size_budget.group_shares(parse.load(name))
        for g, v in shares.items():
            stock_max[g] = max(stock_max.get(g, 0.0), v)
    placed, skipped = [], []
    for w in want:
        srcs = []
        for name in SOURCES:
            for r in RS.ref_rooms().get(w["area"], []):
                if r.map != name:
                    continue
                extra = ()
                if w.get("pair"):
                    # the pair only from a map that has the second room touching the first (one wall between)
                    near_r = [r2 for r2 in RS.ref_rooms().get(w["pair"], []) if r2.map == name and any(
                        abs(a[0] - b[0]) + abs(a[1] - b[1]) <= 2 for a in r.tiles for b in r2.tiles)]
                    if not near_r:
                        continue
                    extra = near_r[:1]
                srcs.append(room_stamp.Source(name, w["area"], r, extra))
        near_to = NEAR.get(w["area"], w["group"])
        if near_to.startswith("@"):
            tx = where.get(near_to[1:], [])
        else:
            tx = group_floor.get(near_to if near_to not in PUBLIC else "hall") or []
        cands = []
        for src in srcs:
            size = abs(src.tiles - w["tiles"]) / float(w["tiles"])
            for k in range(8):
                F, R, D = src.footprint(k)
                f0 = min(F)
                for a in sorted(free):
                    o = (a[0] - f0[0], a[1] - f0[1])
                    Fm = {(o[0] + p[0], o[1] + p[1]) for p in F}
                    if not Fm <= free:
                        continue
                    Rm = {(o[0] + p[0], o[1] + p[1]) for p in R}
                    inner = {(o[0] + x, o[1] + y) for (x, y) in (src.rel(q, k) for q in src.inner)}
                    if not all(q in free or _wall(m.get(*q)) for q in Rm - inner) or not inner <= free:
                        continue
                    if _takes_backdoor(needs, Fm | Rm):
                        continue
                    # door candidates: outline tiles (not corners) with walkable floor outside the new room
                    doors = []
                    for q in Rm - inner:
                        for dx, dy in D4:
                            i, o2 = (q[0] - dx, q[1] - dy), (q[0] + dx, q[1] + dy)
                            if i in Fm and o2 not in Fm and o2 not in Rm and _walk(m.get(*o2)) and o2 not in free:
                                t2 = m.get(*o2)
                                kind = "hall" if t2.apath.startswith(HALL_AREAS) else "maint" if t2.apath.startswith("/area/maintenance") \
                                    else "dept" if parse.ST.group_of(t2.apath) in (w["group"], near_to) else None
                                if kind:
                                    own = (q[0] - o[0], q[1] - o[1]) in D
                                    doors.append((0 if own else 1, kind, q))
                    if not doors:
                        continue
                    cx = sum(p[0] for p in Fm) / len(Fm)
                    cy = sum(p[1] for p in Fm) / len(Fm)
                    dist = min((abs(cx - p[0]) + abs(cy - p[1]) for p in tx), default=40)
                    # 7% under the stock max: later steps (closets, trimmed lobbies) shrink the station a little
                    over = max(0.0, (room_floor[w["group"]] + len(Fm)) / station - 0.93 * stock_max.get(w["group"], 1.0))
                    # over the stock share is a gate failure (station/v6_gate.py): it loses to any placement that isn't
                    score = size + dist / 40.0 + (0.3 if min(doors)[0] else 0) + (10 + 1000 * over if over else 0)
                    cands.append((score, len(cands), src, k, o, Fm, Rm, doors))
        cands.sort(key=lambda c: (src_faults(c[2]), c[0], c[1]))
        best = None
        for c in cands[:60]:      # the best placement that keeps every hall and maint run joined
            if hall_pieces(m, c[5] | c[6]) == halls_before:
                best = c
                break
        if best is None:
            skipped.append(w["area"] + (" (every place cuts a hall or maint run)" if cands else " (no place fits)"))
            continue
        score, _, src, k, o, Fm, Rm, doors = best
        # doors: the source's own where they land on a way out; else one, onto a hall for public rooms
        own = [q for f, kind, q in doors if f == 0]
        pick = set(own) or {min(doors, key=lambda d: (d[1] != ("hall" if w["group"] in PUBLIC else "dept"), d[1] != "hall", d[2]))[2]}
        name = w["area"].rsplit("/", 1)[-1].replace("_", " ").title()
        room_stamp.apply(m, src, k, o, pick, door_atom=dmm.Atom("/obj/machinery/door/airlock", [("name", '"%s"' % name)]))
        fit_in(m, Fm)
        room_floor[w["group"]] += len(Fm)
        free -= Fm | Rm
        needs = [nd - (Fm | Rm) for nd in needs]
        where[w["area"]] = sorted(Fm)
        if w.get("pair"):
            where[w["pair"]] = sorted(Fm)
        placed.append((w["area"], src.map, src.tiles, k, o, len(pick), round(score, 2)))
        log("rooms: %-40s from %-13s %3d tiles, turn %d, at %d,%d, %d door(s), score %.2f" % (
            w["area"], src.map, src.tiles, k, o[0], o[1], len(pick), score))
    for s in skipped:
        log("rooms: NOT PLACED %s" % s)
    # the user's ruling beats the stock habit: one piece per wall face (stock rooms stack a light under an APC)
    import to_dmm as T
    # a mirror over a sink is a pair the stock maps make on purpose (piece_audit counts it so): those tiles stay
    zone = {p for ps in where.values() for p in ps
            if not (m.get(*p).has("/obj/structure/sink") or m.get(*p).has("/obj/structure/mirror"))}
    note = T.one_per_wall_face(m, zone)
    if note:
        log("rooms: %s" % (note if isinstance(note, str) else "; ".join(note)))
    # leftover slot space: real stock maint rooms first (the user, 2026-11-22: "empty pointless maint rooms ... huge
    # ones too"); what none fits, and the hall pockets, become wall, keeping only the corridors something needs
    # V6_POCKETS picks what a leftover pocket becomes (station/v6_ablate.py builds each and the gate judges):
    #   wall   solid wall (rejected by the user 2026-11-22: "you filled in space with a shit ton of walls")
    #   maint  maint floor behind a wall and a maint door; polish dresses it to the stock maint density
    #   stock  (default: fewest gate regressions, 52 vs maint 53, wall 50 + 255 tiles of filler) stock maint rooms
    #          copied into the hall pockets too, then the rest as maint
    mode = os.environ.get("V6_POCKETS", "stock")
    left_slots = {p for p in free if p in set(slots) and _walk(m.get(*p))}
    hall_left = {p for p in free if m.get(*p).apath.startswith(HALL_AREAS) and _walk(m.get(*p))}
    fill_maint(m, log, left_slots | (hall_left if mode == "stock" else set()), hall_pieces(m, set()))
    left_slots = {p for p in left_slots if _walk(m.get(*p)) and m.get(*p).apath.startswith("/area/maintenance")
                  and not any(o.path.startswith(("/obj/structure", "/obj/machinery")) for o in m.get(*p).objs)}
    hall_left = {p for p in hall_left if m.get(*p).apath.startswith(HALL_AREAS) and _walk(m.get(*p))}
    if mode == "wall":
        closets(m, log, hall_left | left_slots, hall_pieces(m, set()))
    else:
        # slot space already maint floor stays maint (polish dresses it); hall pockets become maint behind a wall
        maint_pockets(m, log, hall_left, hall_pieces(m, set()))
        carve_open_maint(m, log)
    escape_hall(m, log)
    arterials(m, log, parse.SemanticMap(m, "v6"))
    return placed


def open_maint(m):
    """(maint floor tiles, the ones whose whole 3x3 is maint floor): the open fields of maint."""
    maint = {(x, y) for (x, y, z), t in m.tiles.items() if t.apath.startswith("/area/maintenance") and _walk(t)
             and not t.apath.startswith("/area/maintenance/solars")}
    opn = {p for p in maint if all((p[0] + dx, p[1] + dy) in maint for dx in (-1, 0, 1) for dy in (-1, 0, 1))}
    return maint, opn


def stock_open_share():
    """The median, over the stock maps, of their open maint (3x3 maint floor) as a share of their maint floor:
    Meta 0.087, Hippie 0.094, Omega 0.113, Delta 0.144."""
    vs = []
    for name in RS.REFS:
        sm = parse.load(name)
        mt = {p for p, g in sm.group.items() if g == "maint" and sm.cls.get(p) == "F"}
        op = {p for p in mt if all((p[0] + dx, p[1] + dy) in mt for dx in (-1, 0, 1) for dy in (-1, 0, 1))}
        vs.append(len(op) / float(max(1, len(mt))))
    vs.sort()
    return vs[len(vs) // 2]


def carve_open_maint(m, log):
    """Open fields of maint (the user 2026-11-22: "this corner of the map still huge empty, pointless maint rooms, they
    either need to be shrunken or given purpose and furnish (or add tiny small rooms like meta/hippie/omega)"): stock
    maint is corridors and small rooms, its open 3x3 floor 0.09-0.14 of the maint, v6's was 0.22. Stock maint rooms
    are copied into the open fields, biggest first, each with its door, the halls and maint kept one piece, until the
    open share is down to the stock median."""
    target = stock_open_share()
    maint, opn = open_maint(m)
    before = len(opn) / float(max(1, len(maint)))

    def done():
        mt, op = open_maint(m)
        return len(op) / float(max(1, len(mt))) <= target
    free = {(p[0] + dx, p[1] + dy) for p in opn for dx in (-1, 0, 1) for dy in (-1, 0, 1)}
    free = {p for p in free if p in maint and not any(o.path.startswith(("/obj/structure", "/obj/machinery"))
                                                       for o in m.get(*p).objs)}
    for (x, y, z), t in list(m.tiles.items()):
        if _is_door(t):
            for dx, dy in D4:
                free.discard((x + dx, y + dy))
    if before > target:
        fill_maint(m, log, free, hall_pieces(m, set()), until=done, door_in_free=True)
    mt, op = open_maint(m)
    log("rooms: open maint %.3f -> %.3f of the maint floor (stock median %.3f)" % (
        before, len(op) / float(max(1, len(mt))), target))


def fit_in(m, tiles):
    """A copied room joins the station's networks: its supply vents go on the station's supply layer (the air pass
    lays pipe to layer-1 vents only: kit.pipe_class), and each of its areas gets an APC and an air alarm if the
    source room had them on a wall outside the copy."""
    from forge import kit
    vent = kit.PIPES["supply"][3]
    by_area = {}
    for p in tiles:
        t = m.get(*p)
        for i, o in enumerate(t.objs):
            if o.path.startswith("/obj/machinery/atmospherics/components/unary/vent_pump") and o.path != vent:
                t.objs[i] = dmm.Atom(vent)
        by_area.setdefault(t.apath, []).append(p)
    for area, ts in by_area.items():
        name = area.rsplit("/", 1)[-1].replace("_", " ").title()
        for kind, path, extra in (("apc", "/obj/machinery/power/apc", [("name", '"%s APC"' % name)]),
                                  ("airalarm", "/obj/machinery/airalarm", [])):
            if any(m.get(*p).has(path) for p in ts):
                continue
            faces, over = [], []
            sys.path.insert(0, os.path.join(HERE, "..", "studies"))
            import piece_audit as PA
            for p in sorted(ts):
                t = m.get(*p)
                if t.has("/obj/machinery/door") or any(abs(o.num("pixel_x")) >= 16 or abs(o.num("pixel_y")) >= 16 or
                                                       o.path.startswith(("/obj/machinery/light", "/obj/machinery/camera"))
                                                       for o in t.objs):
                    continue
                # over bare floor first, not over the copied room's furniture (the gate 2026-11-22: APCs over a mech
                # fabricator, tables and wardrobes, alarms over closets); over furniture only when nothing else is
                # left (the copied telecomms control room had no bare face and lost its APC)
                busy = any(o.path.startswith(PA.FURN) or (kit.dense([o]) and not o.path.startswith("/obj/machinery/door"))
                           for o in t.objs)
                for d, (dx, dy) in kit.DELTA.items():
                    q = m.get(p[0] + dx, p[1] + dy)
                    if q is not None and q.tpath.startswith("/turf/closed"):
                        (over if busy else faces).append((p, d))
            faces = faces or over
            if faces:
                cx = sum(p[0] for p in ts) / float(len(ts))
                cy = sum(p[1] for p in ts) / float(len(ts))
                p, d = min(faces, key=lambda f: ((f[0][0] - cx) ** 2 + (f[0][1] - cy) ** 2, f))
                m.get(*p).objs.append(dmm.Atom(path, kit.mount_vars(kind, d) + extra))


def fill_maint(m, log, left, halls_before, until=None, door_in_free=False):
    """Stock maint rooms (size_budget.maint_pockets of Meta, Delta and Hippie with at least the stock median
    furniture, 12-120 tiles) copied into leftover slot space, biggest placement first, each with a door onto maint
    or a hall, the halls and maint kept one piece. They join the maint area they stand in."""
    srcs = []
    for name in SOURCES:
        sm = parse.load(name)
        ps = size_budget.maint_pockets(sm)
        fr = sorted(p[1] for p in ps)
        med = fr[len(fr) // 2] if fr else 1.0
        for n, f, box, area, r in ps:
            if 12 <= n <= 120 and f >= med:
                srcs.append(room_stamp.Source(name, area, RS.Room(sm.name, area, list(r.tiles))))
    placed = 0
    free = set(left)
    needs = backdoor_needs(m)
    while True:
        if until is not None and until():
            break
        cands = []
        for src in srcs:
            for k in range(8):
                F, R, D = src.footprint(k)
                f0 = min(F)
                for a in sorted(free):
                    o = (a[0] - f0[0], a[1] - f0[1])
                    Fm = {(o[0] + p[0], o[1] + p[1]) for p in F}
                    if not Fm <= free:
                        continue
                    Rm = {(o[0] + p[0], o[1] + p[1]) for p in R}
                    inner = {(o[0] + x, o[1] + y) for (x, y) in (src.rel(q, k) for q in src.inner)}
                    if not all(q in free or _wall(m.get(*q)) for q in Rm - inner) or not inner <= free:
                        continue
                    if _takes_backdoor(needs, Fm | Rm):
                        continue
                    doors = []
                    for q in Rm - inner:
                        for dx, dy in D4:
                            i, o2 = (q[0] - dx, q[1] - dy), (q[0] + dx, q[1] + dy)
                            if i in Fm and o2 not in Fm and o2 not in Rm and (door_in_free or o2 not in free) and _walk(m.get(*o2))                                     and m.get(*o2).apath.startswith(WALK_AREAS):
                                doors.append(((q[0] - o[0], q[1] - o[1]) not in D, q))
                    if doors:
                        cands.append((-len(Fm), min(doors)[0], len(cands), src, k, o, Fm, Rm, doors))
        if not cands:
            break
        cands.sort(key=lambda c: (src_faults(c[3]),) + c[:3])
        done = False
        # up to 600 tries: in an open field the biggest candidates are one room shifted a tile at a time, every one of
        # them cutting the same run (the first 40 had all failed and ended the fill after one room, 2026-11-22)
        for c in cands[:600]:
            _, _, _, src, k, o, Fm, Rm, doors = c
            if hall_pieces(m, Fm | Rm) != halls_before:
                continue
            own = {q for f, q in doors if not f}
            pick = own or {min(doors)[1]}
            maint = [(x, y, t.apath) for (x, y, z), t in m.tiles.items() if t.apath.startswith("/area/maintenance") and _walk(t)]
            cx, cy = next(iter(Fm))
            area = min(maint, key=lambda q: abs(q[0] - cx) + abs(q[1] - cy))[2]
            import copy as _copy
            saved = {q: _copy.deepcopy(m.get(*q)) for q in Fm | Rm if m.get(*q) is not None}
            room_stamp.apply(m, src, k, o, pick, door_atom=dmm.Atom("/obj/machinery/door/airlock/maintenance",
                             [("req_one_access_txt", '"12"')]), area=area)
            # a copy walked into only across furniture (a serving hatch's counter as its one way in, 2026-11-22: a
            # kitchen in maint nobody could enter) is taken back: every bare floor tile of it must be reached from a
            # door over bare floor
            bare = {q for q in Fm if _walk(m.get(*q)) and not kit.dense(m.get(*q).objs)}
            starts = [q for q in Rm if _is_door(m.get(*q))]
            seen, stack = set(starts), list(starts)
            while stack:
                a = stack.pop()
                for dx, dy in D4:
                    b = (a[0] + dx, a[1] + dy)
                    if b in bare and b not in seen:
                        seen.add(b)
                        stack.append(b)
            if not starts or bare - seen:
                for q, t in saved.items():
                    m.set(q[0], q[1], t)
                continue
            # stock maint floor is bare of tile colour (Meta 0.00, Hippie 0.00, Omega 0.05 a tile; Delta's 0.89 is the
            # odd one out): a Delta room copied in keeps its junk, not its paint (the gate 2026-11-22: tile decals)
            for q in Fm:
                tq = m.get(*q)
                tq.objs = [ob for ob in tq.objs if not ob.path.startswith("/obj/effect/turf_decal/tile")]
            fit_in(m, Fm)
            # a copied APC keeps the source map's name and areastring ("Mime's Office APC", /area/hippie/mime, an area
            # this map lacks: a stack trace at roundstart, 2026-11-22): it takes the area it stands in
            for q in Fm | Rm:
                for ob in m.get(*q).objs:
                    if ob.path.startswith("/obj/machinery/power/apc"):
                        ob.vars = [(k, v) for k, v in ob.vars if k not in ("areastring", "name")]
            free -= Fm | Rm
            for q in pick:          # the tile before each door stays open floor
                for dx, dy in D4:
                    free.discard((q[0] + dx, q[1] + dy))
            needs = [nd - (Fm | Rm) for nd in needs]
            placed += 1
            log("rooms: maint room from %s (%d tiles) at %d,%d" % (src.map, len(Fm), o[0], o[1]))
            done = True
            break
        if not done:
            break
    log("rooms: %d stock maint rooms copied into leftover space" % placed)


def closets(m, log, left, halls_before):
    """Reclaimed hall no room took (plaza flanks, a lounge) becomes maint closets off the hall: halls were over the
    stock share and maint under it (size_budget 2026-11-22: 15.8% against 9-13%, 12.8% against 15-21%). A pocket's
    edge next to the hall becomes wall, its inside plating in the nearest maint area, with one maint door onto the
    hall; a pocket too thin for floor becomes wall. The halls must stay one piece."""
    def comps(ts):
        ts, out = set(ts), []
        while ts:
            s = ts.pop()
            c, q = {s}, [s]
            while q:
                a = q.pop()
                for dx, dy in D4:
                    b = (a[0] + dx, a[1] + dy)
                    if b in ts:
                        ts.discard(b)
                        c.add(b)
                        q.append(b)
            out.append(c)
        return out
    maint = [(x, y, t.apath) for (x, y, z), t in m.tiles.items() if t.apath.startswith("/area/maintenance") and _walk(t)]
    made = Counter()
    queue = comps(left)
    corridors = 0
    while queue:
        c = queue.pop(0)
        # a pocket that is the only way to some hall or door beyond it keeps the shortest corridor through it
        # as hall; the rest of it is split off again and tried as closets
        cut = _stranded(m, c)
        if cut:
            keep = _corridor(m, c, cut)
            if keep and keep != c:
                corridors += 1
                queue.extend(comps(c - keep))
                continue
        def outside(p):
            q = m.get(*p)
            return p not in c and q is not None and (_walk(q) or _is_door(q))
        floor = {p for p in c if not any(outside((p[0] + dx, p[1] + dy)) for dx, dy in room_stamp.N8)}
        ring = c - floor
        door = None
        if False and len(floor) >= 2:      # an empty closet is a pointless room (the user, 2026-11-22): wall it
            # the door: a ring tile between the closet floor and hall floor, the most central one
            cands = [p for p in ring if any((p[0] + dx, p[1] + dy) in floor for dx, dy in D4)
                     and any(outside((p[0] + dx, p[1] + dy)) and m.get(p[0] + dx, p[1] + dy).apath.startswith(HALL_AREAS)
                             for dx, dy in D4)
                     and sum(1 for dx, dy in D4 if (p[0] + dx, p[1] + dy) in floor or outside((p[0] + dx, p[1] + dy))) == 2]
            if cands:
                cx = sum(p[0] for p in c) / float(len(c))
                cy = sum(p[1] for p in c) / float(len(c))
                door = min(cands, key=lambda p: (abs(p[0] - cx) + abs(p[1] - cy), p))
        if door is None:
            floor, ring = set(), set(c)
        if hall_pieces(m, ring - {door}) != halls_before:
            xs, ys = [p[0] for p in c], [p[1] for p in c]
            log("rooms: leftover pocket %d,%d-%d,%d (%d tiles) kept as hall: walling it would cut the halls" % (
                min(xs), min(ys), max(xs), max(ys), len(c)))
            continue
        cx, cy = next(iter(c))
        area = min(maint, key=lambda t: abs(t[0] - cx) + abs(t[1] - cy))[2] if maint else "/area/maintenance/port"
        for p in ring:
            if p == door:
                m.set(p[0], p[1], dmm.Tile([dmm.Atom("/obj/machinery/door/airlock/maintenance", [("req_one_access_txt", '"12"')])],
                                           dmm.Atom("/turf/open/floor/plating"), dmm.Atom(area)))
            else:
                m.set(p[0], p[1], dmm.Tile([], dmm.Atom("/turf/closed/wall"), dmm.Atom(m.get(*p).apath)))
        for p in floor:
            m.set(p[0], p[1], dmm.Tile([], dmm.Atom("/turf/open/floor/plating"), dmm.Atom(area)))
        made["closets" if floor else "walled"] += 1
        made["tiles"] += len(c)
    log("rooms: leftover hall: %d maint closets, %d pockets walled, %d tiles, %d corridors kept through pockets" % (
        made["closets"], made["walled"], made["tiles"], corridors))


def _comps(ts):
    ts, out = set(ts), []
    while ts:
        s = ts.pop()
        c, q = {s}, [s]
        while q:
            a = q.pop()
            for dx, dy in D4:
                b = (a[0] + dx, a[1] + dy)
                if b in ts:
                    ts.discard(b)
                    c.add(b)
                    q.append(b)
        out.append(c)
    return out


def maint_pockets(m, log, left, halls_before):
    """Reclaimed hall no room took becomes maint (V6_POCKETS=maint or stock): a pocket's tiles that touch the
    hall it was cut from become its wall, with one maint door where a wall line runs either side; the rest is maint
    plating in the nearest maint area, which polish dresses like any maint. A pocket that is the only way to
    something keeps the shortest corridor through it as hall. A pocket one tile thin (nothing left behind its wall)
    stays hall: walling it would be wall filler, and a nook of hall is what a stock hall has there."""
    maint = [(x, y, t.apath) for (x, y, z), t in m.tiles.items() if t.apath.startswith("/area/maintenance") and _walk(t)]
    made = Counter()
    queue = _comps(left)
    while queue:
        c = queue.pop(0)
        cut = _stranded(m, c)
        if cut:
            keep = _corridor(m, c, cut)
            if keep and keep != c:
                made["corridors"] += 1
                queue.extend(_comps(c - keep))
                continue

        def outside(p):
            q = m.get(*p)
            return p not in c and q is not None and (_walk(q) or _is_door(q))
        edge = {p for p in c if any(outside((p[0] + dx, p[1] + dy)) for dx, dy in D4)}
        inner = c - edge
        if not inner:
            made["thin kept as hall"] += 1
            continue
        # the door: an edge tile between inner floor and outside floor, walled (or edge) on both other sides
        cands = []
        for p in edge:
            for dx, dy in D4:
                a, b = (p[0] - dx, p[1] - dy), (p[0] + dx, p[1] + dy)
                s1, s2 = (p[0] + dy, p[1] + dx), (p[0] - dy, p[1] - dx)
                if a in inner and outside(b) and all(s in edge or _wall(m.get(*s)) for s in (s1, s2)):
                    cands.append(p)
        if not cands:
            made["no door, kept as hall"] += 1
            continue
        cx = sum(p[0] for p in c) / float(len(c))
        cy = sum(p[1] for p in c) / float(len(c))
        door = min(cands, key=lambda p: (abs(p[0] - cx) + abs(p[1] - cy), p))
        if hall_pieces(m, edge - {door}) != halls_before:
            made["kept as hall (would cut the halls)"] += 1
            continue
        px, py = next(iter(c))
        area = min(maint, key=lambda t: abs(t[0] - px) + abs(t[1] - py))[2] if maint else "/area/maintenance/port"
        for p in edge:
            if p == door:
                m.set(p[0], p[1], dmm.Tile([dmm.Atom("/obj/machinery/door/airlock/maintenance", [("req_one_access_txt", '"12"')])],
                                           dmm.Atom("/turf/open/floor/plating"), dmm.Atom(area)))
            else:
                m.set(p[0], p[1], dmm.Tile([], dmm.Atom("/turf/closed/wall"), dmm.Atom(m.get(*p).apath)))
        for p in inner:
            m.set(p[0], p[1], dmm.Tile([], dmm.Atom("/turf/open/floor/plating"), dmm.Atom(area)))
        made["maint pockets"] += 1
        made["maint tiles"] += len(inner)
        made["wall tiles"] += len(edge) - 1
    log("rooms: leftover hall to maint: %s" % ", ".join("%s %d" % kv for kv in sorted(made.items())))


def _walk_graph(m):
    return {(x, y) for (x, y, z), t in m.tiles.items()
            if (t.apath.startswith(WALK_AREAS) and _walk(t)) or (_is_door(t) and t.apath.startswith(WALK_AREAS))}


def _pieces(tiles):
    left, out = set(tiles), []
    while left:
        s0 = left.pop()
        cc, q = {s0}, [s0]
        while q:
            a = q.pop()
            for dx, dy in D4:
                b = (a[0] + dx, a[1] + dy)
                if b in left:
                    left.discard(b)
                    cc.add(b)
                    q.append(b)
        out.append(cc)
    return sorted(out, key=len, reverse=True)


def _stranded(m, c):
    """Hall and maint tiles outside pocket c that only connect to the rest through it (or doors next to it)."""
    g = _walk_graph(m)
    before = len(_pieces(g))
    ps = _pieces(g - c)
    if len(ps) <= before:
        return set()
    return set().union(*ps[1:]) - c


def _corridor(m, c, cut):
    """The tiles of c on the shortest paths from each stranded piece (and each door opening onto c) to the main
    hall, through c."""
    g = _walk_graph(m)
    main = _pieces(g - c)[0]
    targets = set(cut)
    for p in c:
        for dx, dy in D4:
            q = (p[0] + dx, p[1] + dy)
            if _is_door(m.get(*q)) if m.get(*q) is not None else False:
                targets.add(p)
    keep = set()
    for t in sorted(targets):
        # BFS from t through c (and cut) to any main tile
        prev, q, seen, hit = {}, [t], {t}, None
        while q and hit is None:
            nq = []
            for a in q:
                for dx, dy in D4:
                    b = (a[0] + dx, a[1] + dy)
                    if b in seen:
                        continue
                    if b in main:
                        hit = a
                        break
                    if b in c or b in cut:
                        seen.add(b)
                        prev[b] = a
                        nq.append(b)
                if hit is not None:
                    break
            q = nq
        a = hit
        while a is not None:
            if a in c:
                keep.add(a)
            a = prev.get(a)
    return keep
