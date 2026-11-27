"""Each room's number of doors inside what its type has on the stock maps (gen/learn/placestudy.py: the 5th-95th
percentile of the type's rooms): a door added where a room has too few (to the hall, the department's corridor, maint
or the neighbour its type shares doors with most on the human maps), a door taken out where it has too many and the
rooms on both sides are still reached without it.

    python tools/mapforge/gen/learn/doorcount.py <dmm> [out.dmm]
    from gen.learn import doorcount; doorcount.fix(m, log)     # build.py: after the wall merge, before doorfix/walkfix

crew 100 seed 7 f12: 20% of rooms outside their type's door count (stock maps 0-1.7%): a kitchen and genetics with
one door (stock 2+), the HoS office with three (stock 1-2).
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", ".."))
from forge import corpus as CO, dmm  # noqa: E402
import placestudy as PS  # noqa: E402

N4 = PS.N4
AIRLOCK = "/obj/machinery/door/airlock"
# the learned departments' corridor areas: many doors by design (every room opens on them)
CORRIDORS = PS.CORRIDOR_AREAS
ONE_DOOR_MIN = 0.37


def _band(S, area):
    v = S["rooms"].get(area) or []
    dc = [x[2] for x in v if len(x) > 2]
    if len(dc) < 5:
        return None
    return PS._q(dc, 0.05), PS._q(dc, 0.95)


def _walk(t):
    return t is not None and t.tpath.startswith("/turf/open") and not t.tpath.startswith("/turf/open/space") \
        and not CO.solid(t)


def _hung(t):
    return any(CO.mounted(o) or o.path.startswith(("/obj/machinery/light", "/obj/machinery/power/apc",
                                                    "/obj/machinery/airalarm", "/obj/machinery/firealarm"))
               for o in t.objs)


def _reached(m):
    halls = [(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and t.apath.startswith("/area/hallway") and _walk(t)]
    seen, q = set(halls), list(halls)
    while q:
        p = q.pop()
        for dx, dy in N4:
            n = (p[0] + dx, p[1] + dy)
            if n not in seen and _walk(m.get(*n)):
                seen.add(n)
                q.append(n)
    return seen


def fix(m, log=print):
    import deptdb
    S = PS.study()
    M = deptdb.model()
    added = removed = 0
    # the gate's share of rooms with one way in (space.one_door, human band 0.335-0.448): second doors only while the
    # one-door share stays above ONE_DOOR_MIN (adding to every type under its 5th percentile took it to 0.24, f14)
    allp = PS.pieces_of(m)
    ndoor = {i: len({(p[0] + dx, p[1] + dy) for p in F for dx, dy in N4 if PS._door(m.get(p[0] + dx, p[1] + dy))})
             for i, (a, F) in enumerate(allp)}
    one = sum(1 for v in ndoor.values() if v == 1)
    tot = max(1, sum(1 for v in ndoor.values() if v >= 1))
    # a back room (a small piece of an area beside its main room) keeps the doors its plan gave it: counted as a room
    # of the type, the CE's 13-tile back room was given a maint door for the type's second door, and the office then
    # lost "one door too many": the door between the two. The back room was reached only through maint (f45 "ways in")
    biggest = {}
    for a_, F_ in allp:
        biggest[a_] = max(biggest.get(a_, 0), len(F_))
    for idx, (area, F) in enumerate(allp):
        if area in CORRIDORS or len(F) < 0.5 * biggest[area]:
            continue
        # a room with a machine bigger than its tile keeps its doors: one more took the gravity generator's last
        # clear 3x3 (crew 100 seed 7 f14)
        if any(o.path.startswith("/obj/machinery/gravity_generator") for p in F for o in m.get(*p).objs):
            continue
        band = _band(S, area)
        if band is None:
            continue
        doors = sorted({(p[0] + dx, p[1] + dy) for p in F for dx, dy in N4 if PS._door(m.get(p[0] + dx, p[1] + dy))})
        if len(doors) < band[0]:
            if len(doors) == 1 and (one - 1) / float(tot) < ONE_DOOR_MIN:
                continue
            if len(doors) == 1:
                one -= 1
            for _ in range(int(band[0]) - len(doors)):
                w = _new_door(m, F, area, doors, M)
                if w is None:
                    break
                doors.append(w)
                added += 1
        elif len(doors) > band[1]:
            for d in sorted(doors, key=lambda d: _keep_rank(m, d, area)):
                if len(doors) <= band[1]:
                    break
                # the room's last door that isn't onto maint stays (the mining dock room got two maint airlocks
                # where it took the maint behind it, and lost its door to the QM's office: reached only through
                # maint, f39 "ways in")
                if _keep_rank(m, d, area) != 1 and all(_keep_rank(m, q, area) == 1 for q in doors if q != d):
                    continue
                if _keep_rank(m, d, area) >= 3:
                    continue            # the door to its own back room
                t = m.get(*d)
                old = t
                wall = next((m.get(d[0] + dx, d[1] + dy).tpath for dx, dy in N4
                             if m.get(d[0] + dx, d[1] + dy) is not None
                             and m.get(d[0] + dx, d[1] + dy).tpath.startswith("/turf/closed/wall")), "/turf/closed/wall")
                before = _reached(m)
                keep = [o for o in t.objs if o.path.startswith(("/obj/structure/cable", "/obj/machinery/atmospherics",
                                                                 "/obj/structure/disposalpipe"))]
                m.set(d[0], d[1], dmm.Tile(keep, dmm.Atom(wall), t.area))
                after = _reached(m)
                if len(after) < len(before) - 1:
                    m.set(d[0], d[1], old)          # it was a way in: it stays
                    continue
                doors.remove(d)
                removed += 1
    log("doorcount: %d doors added, %d taken out (rooms to their type's stock door count)" % (added, removed))
    return added + removed


def _keep_rank(m, d, area):
    """Doors to take out first: to another room, then to maint; a door to the hall or the corridor last. A door to a
    room the human maps put beside this one and join to it (the QM's office onto the cargo bay, 8 maps of 8) goes
    after the maint doors: the bay took two maint airlocks where it reached the hull and lost the QM's door for
    them (f44)."""
    s = [m.get(d[0] + dx, d[1] + dy) for dx, dy in N4]
    other = [t.apath for t in s if t is not None and _walk(t) and t.apath != area]
    if not other and sum(1 for t in s if t is not None and _walk(t) and t.apath == area) >= 2:
        return 3            # between two pieces of the area itself: a back room's door, never taken out
    if any(a.startswith("/area/hallway") or a in CORRIDORS for a in other):
        return 2
    if any(a.startswith("/area/maintenance") for a in other):
        return 1
    import deptdb
    import doordb
    nb = deptdb.model().get("nb", {})
    if any(nb.get("|".join(sorted((area, a))), 0.0) >= 0.8 and doordb.pair_seen(area, a) for a in other):
        return 1.5
    return 0


def _new_door(m, F, area, doors, M):
    """A wall tile of the room's edge with floor of somewhere else straight past it: the hall or the corridor first,
    then the neighbour its type shares doors with most on the human maps, then maint; never at a corner, beside
    another door or where something hangs on either face."""
    best = None
    for p in F:
        for dx, dy in N4:
            w, b = (p[0] + dx, p[1] + dy), (p[0] + 2 * dx, p[1] + 2 * dy)
            tw, tb = m.get(*w), m.get(*b)
            if tw is None or not tw.tpath.startswith("/turf/closed/wall") or tw.tpath.startswith("/turf/closed/wall/r_wall") \
                    or tw.objs or not _walk(tb) or tb.apath == area or PS._dense(tb) or PS._dense(m.get(*p)):
                continue
            if tb.apath.startswith(("/area/space", "/area/solar", "/area/engine/supermatter", "/area/ai_monitored/turret_protected/ai")):
                continue
            # a straight wall (both sides along it are wall), no door beside, nothing hung on either face
            side = [(w[0] + dy, w[1] + dx), (w[0] - dy, w[1] - dx)]
            if not all(m.get(*q) is not None and m.get(*q).tpath.startswith("/turf/closed") for q in side):
                continue
            if any(abs(w[0] - d[0]) + abs(w[1] - d[1]) <= 2 for d in doors):
                continue
            if _hung(m.get(*p)) and any(CO.mount_side(o) == {(0, 1): 1, (0, -1): 2, (1, 0): 4, (-1, 0): 8}[(dx, dy)]
                                        for o in m.get(*p).objs if CO.mounted(o)):
                continue
            a = tb.apath
            if a.startswith("/area/hallway") or a in CORRIDORS:
                score = 0
            elif a.startswith("/area/maintenance"):
                score = 2
            else:
                import doordb as DD
                if not DD.pair_seen(area, a):
                    continue        # no human map has a door between these two kinds of room (f22 S12)
                score = 1 - M["door"].get("|".join(sorted((area, a))), 0.0)
            if best is None or score < best[0]:
                best = (score, w)
    if best is None:
        return None
    w = best[1]
    t = m.get(*w)
    m.set(w[0], w[1], dmm.Tile([dmm.Atom(AIRLOCK + "/maintenance" if best[0] == 2 else AIRLOCK)],
                               dmm.Atom("/turf/open/floor/plasteel"), dmm.Atom(area)))
    return w


if __name__ == "__main__":
    m = dmm.read(sys.argv[1])
    print("before", PS.summary(PS.check(m)))
    fix(m)
    print("after ", PS.summary(PS.check(m)))
    if len(sys.argv) > 2:
        dmm.write(m, sys.argv[2])
