"""Enclosed space inside the station (a pocket of space walled in on every side by halls and departments) made into
the vacant and abandoned rooms human maps keep in such gaps: cut into rooms of 12-40 tiles, each with a door to the
hall or maint beside it, furnished by the learned synthesizer (gen/learn/synth.py) as a vacant office, a commissary,
a construction site, an emergency store.

    python tools/mapforge/gen/voids.py data/mapforge/gen_learn/f7_c100_s7.dmm [out.dmm]   # measure (and fill)
    from gen import voids; voids.fill(m, seed, log)        # build.py: after the docks and solars, before dressing

The user 2026-11-26 asked for a real-looking, working station; crew 100 seed 7 had a 21 x 24 block of space walled in
beside command (the learned departments use less floor than their slots: the slots' rest stayed space). Enclosed
space was 5.8% of the floor (Meta 5.3%, Box and Delta 3%), but in a few big rectangles a player walks round.
"""
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "learn"))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import corpus as CO, dmm  # noqa: E402

N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
MIN_VOID = 30       # pockets under this stay space (a station has small light wells too)
ROOM_MAX = 36       # a room cut from a pocket at most this big ...
ROOM_MIN = 12       # ... and at least this (smaller cuts stay one room)
# the human maps' vacant and abandoned room types (roomdb), the first ones once each, then the stores
TYPES = ("/area/vacant_room", "/area/vacant_room/commissary", "/area/construction", "/area/vacant_room/office",
         "/area/crew_quarters/abandoned_gambling_den", "/area/library/abandoned", "/area/storage/tools",
         "/area/storage/art")
REPEAT = ("/area/storage/emergency/port", "/area/storage/emergency/starboard")
TURF = {"/area/vacant_room/office": "/turf/open/floor/wood", "/area/crew_quarters/abandoned_gambling_den":
        "/turf/open/floor/wood", "/area/library/abandoned": "/turf/open/floor/wood"}


_MED = {}


def _med(area):
    """The median size of the type's human rooms (roomdb)."""
    if area not in _MED:
        import roomdb
        v = sorted(r["tiles"] for r in roomdb.rooms() if r["area"] == area) or [20]
        _MED[area] = v[len(v) // 2]
    return _MED[area]


def _engine_side(m, comp):
    """The pocket is the supermatter annex's space (by the crystal's room, the lattice round its coil, or the
    emitters' engineering floor): it stays space (crew 100 seed 7's 3-wide strip beside the engine was a pocket)."""
    for c in comp:
        for dx in range(-3, 4):
            for dy in range(-3, 4):
                t = m.get(c[0] + dx, c[1] + dy)
                if t is not None and t.apath.startswith(("/area/engine/supermatter", "/area/space/nearstation",
                                                         "/area/engine/engineering", "/area/solar")):
                    return True
    return False


def _keep_space(m, comp):
    """The pocket's tiles within 2 of a lattice stay space: a waste injector or a pipe out to space ends there (the
    atmos waste line of crew 100 seed 7 vents into its biggest pocket)."""
    lat = {(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and t.has("/obj/structure/lattice")}
    return {c for c in comp if any((c[0] + dx, c[1] + dy) in lat for dx in range(-2, 3) for dy in range(-2, 3))}


def _maint_area(m, rm):
    """The maint area nearest the room's way out (the run its door opens to), else the station's biggest maint."""
    from collections import Counter
    for w in rm["outs"]:
        for dx, dy in N4:
            t = m.get(w[0] + dx, w[1] + dy)
            if t is not None and _walk(t) and t.apath.startswith("/area/maintenance")                     and not t.apath.startswith(("/area/maintenance/solars", "/area/maintenance/department")):
                return t.apath
    c = Counter(t.apath for t in m.tiles.values() if t.apath.startswith("/area/maintenance/")
                and not t.apath.startswith(("/area/maintenance/solars", "/area/maintenance/department")))
    return c.most_common(1)[0][0] if c else "/area/maintenance/fore"


def _space(t):
    return t is not None and t.tpath.startswith("/turf/open/space") and t.apath.startswith("/area/space") and not t.objs


def _walk(t):
    return t is not None and t.tpath.startswith("/turf/open") and not t.tpath.startswith("/turf/open/space") \
        and not CO.solid(t)


def pockets(m):
    """Enclosed space: [set of tiles] not reached from the map's edge through space."""
    W, H = m.maxx, m.maxy
    seen, q = set(), []
    for x in range(1, W + 1):
        for y in range(1, H + 1):
            if (x in (1, W) or y in (1, H)) and _space(m.get(x, y)):
                seen.add((x, y))
                q.append((x, y))
    while q:
        p = q.pop()
        for dx, dy in N4:
            n = (p[0] + dx, p[1] + dy)
            if n not in seen and _space(m.get(*n)):
                seen.add(n)
                q.append(n)
    left = {(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and _space(t) and (x, y) not in seen}
    out = []
    while left:
        s = left.pop()
        comp, q = {s}, [s]
        while q:
            p = q.pop()
            for dx, dy in N4:
                n = (p[0] + dx, p[1] + dy)
                if n in left:
                    left.discard(n)
                    comp.add(n)
                    q.append(n)
        out.append(comp)
    return out


def _cut(cells, r):
    """Guillotine cuts across the longer side until each piece is at most ROOM_MAX: [(cells of a room)], walls."""
    pieces, walls = [set(cells)], set()
    for _ in range(40):
        big = [p for p in pieces if len(p) > ROOM_MAX]
        if not big:
            break
        p = max(big, key=len)
        xs, ys = [c[0] for c in p], [c[1] for c in p]
        ax = 0 if (max(xs) - min(xs)) >= (max(ys) - min(ys)) else 1
        lo, hi = (min(xs), max(xs)) if ax == 0 else (min(ys), max(ys))
        if hi - lo < 2 * 3:
            break
        k = r.randint(lo + 3, hi - 3)
        line = {c for c in p if c[ax] == k}
        a = {c for c in p if c[ax] < k}
        b = {c for c in p if c[ax] > k}
        if len(a) < ROOM_MIN or len(b) < ROOM_MIN:
            break
        pieces.remove(p)
        pieces += [a, b]
        walls |= line
    return pieces, walls


def fill(m, seed=1, log=print):
    """Make the station's big enclosed pockets of space into rooms. Returns how many rooms were made."""
    import synth
    r = random.Random("voids|%s" % seed)
    used = {t.apath for t in m.tiles.values()}
    pool = [a for a in TYPES if a not in used]
    r.shuffle(pool)
    made, pockets_ = 0, 0
    for comp in sorted(pockets(m), key=lambda c: -len(c)):
        if len(comp) < MIN_VOID or _engine_side(m, comp):
            continue
        keep = _keep_space(m, comp)
        if keep:
            # the rest, its biggest connected part, still a pocket worth rooms; the kept space walled off from it
            rest = comp - keep
            parts = []
            while rest:
                s0 = rest.pop()
                part, q = {s0}, [s0]
                while q:
                    p_ = q.pop()
                    for dx, dy in N4:
                        n_ = (p_[0] + dx, p_[1] + dy)
                        if n_ in rest:
                            rest.discard(n_)
                            part.add(n_)
                            q.append(n_)
                parts.append(part)
            if not parts:
                continue
            big = max(parts, key=len)
            if len(big) < MIN_VOID:
                continue
            # a wall between the rooms and the space kept round the lattice
            rim = {c for c in big if any((c[0] + dx, c[1] + dy) in keep for dx, dy in N4)}
            for c in rim:
                m.set(c[0], c[1], dmm.Tile([], dmm.Atom("/turf/closed/wall"), dmm.Atom("/area/space")))
            comp = big - rim
            if len(comp) < MIN_VOID:
                continue
        pieces, walls = _cut(comp, r)
        # each room's way in: a wall tile of the pocket's edge with hall or maint floor straight past it
        rooms = []
        for p in pieces:
            outs = []
            for c in p:
                for dx, dy in N4:
                    w, b = (c[0] + dx, c[1] + dy), (c[0] + 2 * dx, c[1] + 2 * dy)
                    tw, tb = m.get(*w), m.get(*b)
                    if w in comp or tw is None or not tw.tpath.startswith("/turf/closed/wall") or tw.objs:
                        continue
                    if _walk(tb) and tb.apath.startswith(("/area/hallway", "/area/maintenance")) \
                            and not tb.apath.startswith("/area/maintenance/solars"):
                        outs.append(w)
            rooms.append(dict(F=p, outs=outs, door=None))
        # rooms with no way out of their own open into a neighbour that has one (through the cut wall)
        reached = [rm for rm in rooms if rm["outs"]]
        if not reached:
            continue
        inner_doors = []
        for _ in range(len(rooms)):
            for rm in rooms:
                if rm in reached:
                    continue
                for c in sorted(rm["F"]):
                    hit = None
                    for dx, dy in N4:
                        w, b = (c[0] + dx, c[1] + dy), (c[0] + 2 * dx, c[1] + 2 * dy)
                        if w in walls and any(b in q["F"] for q in reached):
                            hit = w
                            break
                    if hit:
                        inner_doors.append((hit, rm))
                        reached.append(rm)
                        break
        cx = lambda rm: (sum(c[0] for c in rm["F"]) / float(len(rm["F"])), sum(c[1] for c in rm["F"]) / float(len(rm["F"])))  # noqa: E731
        for rm in sorted(rooms, key=lambda q: -len(q["F"])):
            if rm not in reached:
                continue            # stays space: no way in
            # the vacant type whose human rooms are nearest its size (a 40-tile emergency store stood empty)
            n = len(rm["F"])
            cands = pool + list(REPEAT)
            area = min(cands, key=lambda a: (abs(math.log(n / float(_med(a)))), r.random()))
            if area in pool:
                pool.remove(area)
            # furnished as that type, in maint's area (abandoned rooms are maint's on the human maps; as civic rooms
            # they took civic's share out of its band and moved the room-size bands, crew 100 seed 7, 2026-11-26)
            rm["kind"] = area
            area = _maint_area(m, rm)
            rm["area"] = area
            turf = TURF.get(rm["kind"], "/turf/open/floor/plasteel" if len(rm["F"]) > 16 else "/turf/open/floor/plating")
            for c in rm["F"]:
                m.set(c[0], c[1], dmm.Tile([], dmm.Atom(turf), dmm.Atom(area)))
            if rm["outs"]:
                c0 = cx(rm)
                w = min(rm["outs"], key=lambda w: ((w[0] - c0[0]) ** 2 + (w[1] - c0[1]) ** 2, w))
                m.set(w[0], w[1], dmm.Tile([dmm.Atom("/obj/machinery/door/airlock/maintenance")],
                                           dmm.Atom("/turf/open/floor/plating"), dmm.Atom(area)))
                rm["door"] = w
        for w in walls:
            nb_ = [m.get(w[0] + dx, w[1] + dy) for dx, dy in N4]
            a_ = next((t.apath for t in nb_ if t is not None and t.tpath.startswith("/turf/open")
                       and not t.apath.startswith("/area/space")), "/area/space")
            m.set(w[0], w[1], dmm.Tile([], dmm.Atom("/turf/closed/wall"), dmm.Atom(a_)))
        for w, rm in inner_doors:
            # the door belongs to the room it opens (its APC powers it)
            m.set(w[0], w[1], dmm.Tile([dmm.Atom("/obj/machinery/door/airlock/maintenance")],
                                       dmm.Atom("/turf/open/floor/plating"), dmm.Atom(rm.get("area", "/area/vacant_room"))))
        # furnished by the synthesizer from the type's human rooms
        for rm in rooms:
            if "area" not in rm:
                continue
            floor = set(rm["F"])
            doors = {(c[0] + dx, c[1] + dy) for c in floor for dx, dy in N4
                     if m.get(c[0] + dx, c[1] + dy) is not None and m.get(c[0] + dx, c[1] + dy).has("/obj/machinery/door")}
            solid = lambda p: CO.solid(m.get(*p)) and p not in doors  # noqa: E731
            try:
                out, rep = synth.furnish(floor, solid, doors, set(), rm["kind"], seed=made + 1)
            except Exception as e:                  # noqa: BLE001 - an unfurnished room is still a room
                log("voids: furnishing %s failed: %s" % (rm["area"], str(e)[:80]))
                out = {}
            for p, atoms in out.items():
                t = m.get(*p)
                if t is not None:
                    # the maint area's own APC and alarms serve it: the exemplar's (named for its vacant room) go
                    t.objs.extend(dmm.Atom.parse(a) for a in atoms if not a.startswith(
                        ("/obj/machinery/power/apc", "/obj/machinery/airalarm", "/obj/machinery/firealarm")))
            if len(floor) > 2 * _med(rm["kind"]):
                # a store bigger than its kind: crates, racks and lockers in its open middle, as maint stores are
                # (a 30-tile emergency store stood near empty)
                import floorplan as FP
                FP.clutter(m, floor, doors, random.Random("voidclutter|%s|%d" % (seed, made)))
            made += 1
        pockets_ += 1
    log("voids: %d enclosed pockets of space made into %d rooms" % (pockets_, made))
    return made


if __name__ == "__main__":
    m = dmm.read(sys.argv[1])
    ps = pockets(m)
    print("enclosed pockets: %s" % sorted((len(p) for p in ps), reverse=True)[:12])
    if len(sys.argv) > 2:
        fill(m, 1)
        dmm.write(m, sys.argv[2])
        print("written", sys.argv[2])
