"""Connectivity for a furnished build (M3): every station floor tile reachable from the halls, and rooms reached
only through maint given a way in from a hall or a department corridor, the two walk checks of the gate
(forge/walk.py reach: unreached floor at most the stock max; maint-only rooms only where a stock map has them so).

    from gen import connect
    connect.connect(m, log)        # edits the dmm.Map in place

Each round measures reach the way the gate does (walk.reach on parse.SemanticMap), then for every unreached floor
piece cuts one door through a single plain wall (not glass, not hull to space) whose other side is reached floor,
choosing a hall first, then a department corridor or room, then maint; a maintenance airlock when either side is
maint. It stops when everything is reached or a round adds nothing. Then each area reached only through maint
(bar the abandoned rooms and those a stock map keeps so) gets a door to a hall or non-maint floor through one wall.
Also strips copied APCs' name and areastring (a stock room's APC names the area of the map it came from).
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import dmm, parse, walk  # noqa: E402

N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
RANK = {"hall": 0, "arrivals": 0, "escape": 0}


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


def _cut(m, sm, w, a, b):
    t = m.get(*w)
    maint = "maint" in (sm.group.get(a), sm.group.get(b))
    t.objs = [dmm.Atom("/obj/machinery/door/airlock/maintenance" if maint else "/obj/machinery/door/airlock")]
    t.turf = dmm.Atom("/turf/open/floor/plating" if maint else "/turf/open/floor/plasteel")


def _reached(sm):
    walkable = {p for p, c in sm.cls.items() if c in ("F", "D")}
    halls = [p for p in walkable if sm.group.get(p) == "hall"]
    return walk._bfs(halls, lambda n: n in walkable)


def connect(m, log=print, rounds=12):
    strip_apcs(m, log)
    total = 0
    for rnd in range(rounds):
        sm = parse.SemanticMap(m, "gen", 1)
        un, only = walk.reach(sm)
        if not un:
            break
        reached = _reached(sm)
        made = 0
        for comp in _comps(un):
            best = None
            mine = next(iter(comp))
            maint_piece = sm.group.get(mine) == "maint"
            dept = sm.group.get(mine)
            for p in comp:
                for dx, dy in N4:
                    w = (p[0] + dx, p[1] + dy)
                    q = (p[0] + 2 * dx, p[1] + 2 * dy)
                    if sm.cls.get(w) != "W" or w in sm.glass or q not in reached or sm.cls.get(q) != "F":
                        continue
                    t = m.get(*w)
                    if t is None or t.tpath.startswith("/turf/closed/wall/r_wall"):
                        # reinforced: the hull, or a vault; only when nothing else is left
                        pen = 5
                    else:
                        pen = 0
                    g = sm.group.get(q)
                    # a maint piece opens onto a hall or other maint, a room only if nothing else is in reach (a
                    # door into a room gives it a second way in: trace.py 2026-11-22, one-door share 0.34 -> 0.22);
                    # a department piece onto a hall, then its own department, then maint
                    if maint_piece:
                        rank = 0 if g in RANK else 1 if g == "maint" else 3
                    else:
                        rank = 0 if g in RANK else 1 if g == dept else 2 if g == "maint" else 3
                    sc = (rank + pen, w)
                    if best is None or sc < best[0]:
                        best = (sc, w, p, q)
            if best:
                _cut(m, sm, best[1], best[2], best[3])
                made += 1
        total += made
        log("connect: round %d, %d unreached tiles, %d doors cut" % (rnd, len(un), made))
        if not made:
            break
    # rooms reached only through maint: a door to a hall or non-maint floor through one wall
    sm = parse.SemanticMap(m, "gen", 1)
    un, only = walk.reach(sm)
    st = walk.stock()
    allowed = {a for v in st.values() for a in v["maint_only"]}
    fixed = 0
    for area in sorted(only):
        if area in allowed or "abandoned" in area:
            continue
        tiles = [p for p, a in sm.area.items() if a == area and sm.cls.get(p) == "F"]
        best = None
        for p in tiles:
            for dx, dy in N4:
                w = (p[0] + dx, p[1] + dy)
                q = (p[0] + 2 * dx, p[1] + 2 * dy)
                w2 = None
                if sm.cls.get(w) == "W" and sm.cls.get(q) == "W" and q not in sm.glass:
                    # two walls thick (a room's wall and the corridor's): a door and a step of floor
                    w2, q = q, (p[0] + 3 * dx, p[1] + 3 * dy)
                if sm.cls.get(w) != "W" or w in sm.glass or sm.cls.get(q) != "F":
                    continue
                g = sm.group.get(q)
                if g == "maint" or sm.area.get(q) == area or g is None:
                    continue
                t = m.get(*w)
                if t is None or t.tpath.startswith("/turf/closed/wall/r_wall"):
                    continue
                sc = (RANK.get(g, 1) + (0.5 if w2 else 0), w)
                if best is None or sc < best[0]:
                    best = (sc, w, p, q, w2)
        if best:
            _cut(m, sm, best[1], best[2], best[3])
            if best[4]:
                t2 = m.get(*best[4])
                t2.objs = []
                t2.turf = dmm.Atom("/turf/open/floor/plasteel")
                t2.area = dmm.Atom(sm.area.get(best[3]))
            fixed += 1
    # department-corridor scraps under 15 tiles still reached only through maint are packing leftovers, not rooms:
    # walled in (the gate's "ways in" names any maint-only area; v6_rooms walls its leftover pockets the same way)
    import rooms as RM
    sm = parse.SemanticMap(m, "gen", 1)
    walkable = {p for p, c in sm.cls.items() if c in ("F", "D")}
    halls = [p for p in walkable if sm.group.get(p) == "hall"]
    nom = walk._bfs(halls, lambda n: n in walkable and sm.group.get(n) != "maint")
    corr = set(RM.CORRIDOR_AREA.values())
    scraps = {p for p, c in sm.cls.items() if c == "F" and sm.area.get(p) in corr and p not in nom}
    walled = 0
    for comp in _comps(scraps):
        if len(comp) < 15:
            for p in comp:
                t = m.get(*p)
                t.objs = []
                t.turf = dmm.Atom("/turf/closed/wall")
            walled += len(comp)
    log("connect: %d doors in all; %d maint-only rooms given a front door; %d corridor scrap tiles walled" % (
        total, fixed, walled))
    prune_stubs(m, log)
    return total, fixed


def prune_stubs(m, log=print, rounds=80):
    """Dead ends (forge/walk.py stubs: 1-wide maint or hall runs that stop against a wall, no door; stock max 2.93 a
    1000 corridor tiles, longest 5): their tip tiles are walled back, one tile a round, until no stub tip is left.
    A tile beside a door stays (the run leads somewhere)."""
    n = 0
    for _ in range(rounds):
        sm = parse.SemanticMap(m, "gen", 1)
        walkable = {p for p, c in sm.cls.items() if c in ("F", "D")}
        tips = []
        for p, c in sm.cls.items():
            if c != "F" or sm.group.get(p) not in ("maint", "hall"):
                continue
            nbs = [(p[0] + dx, p[1] + dy) for dx, dy in N4 if (p[0] + dx, p[1] + dy) in walkable]
            if len(nbs) == 1 and sm.cls.get(nbs[0]) != "D":
                tips.append(p)
        if not tips:
            break
        for p in tips:
            t = m.get(*p)
            t.objs = []
            t.turf = dmm.Atom("/turf/closed/wall")
        n += len(tips)
    # walls with no floor or door beside them (8 ways) are left over from walled stubs: space, not solid filler
    # (the gate's wall-filler check: stock max 23 tiles of 3x3 solid wall)
    gone = 0
    for _ in range(3):
        sm = parse.SemanticMap(m, "gen", 1)
        orphan = [p for p, c in sm.cls.items() if c == "W" and p not in sm.glass and not any(
            sm.cls.get((p[0] + dx, p[1] + dy)) in ("F", "D") for dx in (-1, 0, 1) for dy in (-1, 0, 1))]
        if not orphan:
            break
        for p in orphan:
            t = m.get(*p)
            t.objs = []
            t.turf = dmm.Atom("/turf/open/space/basic")
            t.area = dmm.Atom("/area/space")
        gone += len(orphan)
    log("connect: %d dead-end tiles walled back, %d orphan wall tiles to space" % (n, gone))
    return n


def strip_apcs(m, log=print):
    n = 0
    for t in m.tiles.values():
        for i, o in enumerate(t.objs):
            if o.path.startswith("/obj/machinery/power/apc") and (o.get("areastring") or o.get("name")):
                t.objs[i] = dmm.Atom(o.path, [(k, v) for k, v in o.vars if k not in ("areastring", "name")])
                n += 1
    if n:
        log("connect: %d copied APCs lose their old area's name" % n)
    return n
