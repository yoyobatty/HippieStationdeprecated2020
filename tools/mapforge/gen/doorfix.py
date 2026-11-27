"""Airlocks a player can't use: a door into a wall, a door at a corner (its two open sides at right angles), a door
whose front is blocked by a machine or furniture, and the fix for each.

    python tools/mapforge/gen/doorfix.py data/mapforge/gen_learn/gen_hub_c100_s7_final.dmm      # list them
    from gen import doorfix; doorfix.dead(m) -> [(x, y, why)]; doorfix.fix(m, log) -> fixed count

The user 2026-11-26: "The generator missed a few airlocks having no path to them". Crew 100 seed 7 had 6 doors into
walls or at corners. fix(): a door with a blocked front moves the blocker to the nearest free tile of its room; a door
into a double wall gets the wall between opened; a door into a wall or at a corner becomes the wall its neighbours are (gen/walkfix.py, run after, gives any room this cuts
off a working door).
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import corpus as CO, dmm, kit  # noqa: E402

N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
DOOR = ("/obj/machinery/door/airlock", "/obj/machinery/door/window", "/obj/machinery/door/poddoor")


def _door(t):
    return t is not None and any(o.path.startswith(DOOR) for o in t.objs)


def _open(t):
    """Floor a player stands on (another door counts: cycling airlocks stand in pairs)."""
    if t is None or not t.tpath.startswith("/turf/open") or CO.solid(t):
        return False
    return _door(t) or not kit.dense(t.objs)


def _floorish(t):
    return t is not None and t.tpath.startswith("/turf/open") and not CO.solid(t)


def dead(m):
    """[(x, y, why)]: why is 'wall' (no axis with floor both ways), 'blocked' (floor both ways on an axis but furniture
    or a machine on a side)."""
    out = []
    for (x, y, z), t in m.tiles.items():
        if z != 1 or not any(o.path.startswith("/obj/machinery/door/airlock") for o in t.objs):
            continue
        ok, floorish = False, False
        for ax in ((1, 0), (0, 1)):
            a, b = m.get(x + ax[0], y + ax[1]), m.get(x - ax[0], y - ax[1])
            if _open(a) and _open(b):
                ok = True
            if _floorish(a) and _floorish(b):
                floorish = True
        if not ok:
            out.append((x, y, "blocked" if floorish else "wall"))
    return out


def _wall_like(m, x, y):
    """The wall turf the door's neighbours have (reinforced where they are)."""
    for dx, dy in N4:
        t = m.get(x + dx, y + dy)
        if t is not None and t.tpath.startswith("/turf/closed/wall"):
            return t.tpath
    return "/turf/closed/wall"


UNDER = ("/obj/structure/cable", "/obj/machinery/atmospherics/pipe", "/obj/structure/disposalpipe", "/obj/effect/turf_decal")


def pockets(m, log=print):
    """A door onto a pocket: one or two floor tiles past it, nothing on them, no other door, window or way on. The
    door and the pocket become wall (a maint hatch from the vacant office onto one tile at a hall corner, f40: the
    tile's corner met the hall's wall only diagonally and failed "function: wall joins"). Returns how many."""
    n = 0
    for (x, y, z), t in sorted(m.tiles.items()):
        if z != 1 or not any(o.path.startswith("/obj/machinery/door/airlock") for o in t.objs)                 or any(o.path.startswith("/obj/machinery/door/airlock/external") for o in t.objs):
            continue
        for dx, dy in N4:
            p = (x + dx, y + dy)
            tp = m.get(*p)
            if not _floorish(tp) or tp.tpath.startswith("/turf/open/space") or _door(tp):
                continue
            reg, q, way_on = {p}, [p], False
            while q and len(reg) <= 2 and not way_on:
                c = q.pop()
                for ex, ey in N4:
                    nb = (c[0] + ex, c[1] + ey)
                    if nb == (x, y) or nb in reg:
                        continue
                    tn = m.get(*nb)
                    if tn is None or tn.tpath.startswith("/turf/closed"):
                        if tn is not None and tn.objs:
                            way_on = True       # something hangs on or stands in that wall (a window frame)
                        continue
                    if tn.tpath.startswith("/turf/open/space") or tn.objs and any(
                            not o.path.startswith(UNDER) for o in tn.objs):
                        way_on = True           # a door, a window, a machine, space: the pocket leads on or is used
                        continue
                    reg.add(nb)
                    q.append(nb)
            if way_on or len(reg) > 2 or any(not o.path.startswith(UNDER) for c in reg for o in m.get(*c).objs):
                continue
            wall = _wall_like(m, x, y)
            for c in reg | {(x, y)}:
                tc = m.get(*c)
                keep = [o for o in tc.objs if o.path.startswith(UNDER[:3])]
                m.set(c[0], c[1], dmm.Tile(keep, dmm.Atom(wall), tc.area))
            n += 1
            break
    if n:
        log("doorfix: %d doors onto empty one- or two-tile pockets walled up with them" % n)
    return n


def fix(m, log=print):
    n_wall = n_moved = n_carved = 0
    pockets(m, log)
    for x, y, why in dead(m):
        t = m.get(x, y)
        if why == "blocked":
            # move what stands in the door's way to the nearest free floor of that side's room
            for ax in ((1, 0), (0, 1)):
                sides = [(x + ax[0], y + ax[1]), (x - ax[0], y - ax[1])]
                if not all(_floorish(m.get(*p)) for p in sides):
                    continue
                for p in sides:
                    pt = m.get(*p)
                    if _open(pt):
                        continue
                    dense = [o for o in pt.objs if kit.is_dense_atom(o)]
                    spot = _free_near(m, p, pt.apath, avoid={(x, y)} | set(sides))
                    if spot is None:
                        continue
                    pt.objs = [o for o in pt.objs if o not in dense]
                    m.get(*spot).objs.extend(dense)
                    n_moved += 1
                break
            continue
        # a door into a double wall (floor two tiles past it): the wall between opens, the door works (walled up, a
        # maint corridor ending at it became a dead end the gate counts)
        carved = False
        for ax in ((1, 0), (0, 1), (-1, 0), (0, -1)):
            a, w, b = m.get(x - ax[0], y - ax[1]), m.get(x + ax[0], y + ax[1]), m.get(x + 2 * ax[0], y + 2 * ax[1])
            if _open(a) and w is not None and w.tpath.startswith("/turf/closed/wall") and not w.objs                     and _open(b) and not b.apath.startswith(("/area/space", "/area/solar", "/area/engine/supermatter"))                     and not t.apath.startswith("/area/engine/supermatter"):
                floor = b.tpath if b.apath == t.apath else a.tpath
                m.set(x + ax[0], y + ax[1], dmm.Tile([], dmm.Atom(floor), b.area if b.apath == t.apath else t.area))
                carved = True
                n_carved += 1
                break
        if carved:
            continue
        # a door into a wall or at a corner: wall it up
        keep = [o for o in t.objs if o.path.startswith(("/obj/structure/cable", "/obj/machinery/atmospherics",
                                                         "/obj/structure/disposalpipe"))]
        m.set(x, y, dmm.Tile(keep, dmm.Atom(_wall_like(m, x, y)), t.area))
        n_wall += 1
    log("doorfix: %d dead airlocks walled up, %d opened through a double wall, %d blocked door fronts cleared" % (
        n_wall, n_carved, n_moved))
    return n_wall + n_carved + n_moved


def door_areas(m, log=print):
    """A door tile in space's area has no power (space is always unpowered): the arrivals' two airlocks stood in
    /area/space on crew 100 seed 7 (2026-11-26). Each takes the area of the station side it opens to."""
    n = 0
    for (x, y, z), t in m.tiles.items():
        if z != 1 or not t.apath.startswith("/area/space") or not _door(t):
            continue
        for dx, dy in N4:
            q = m.get(x + dx, y + dy)
            if q is not None and _floorish(q) and not q.apath.startswith(("/area/space", "/area/solar", "/area/shuttle")):
                t.area = dmm.Atom(q.apath)
                n += 1
                break
    log("doorfix: %d doors in space's area given their station side's area (power)" % n)
    return n


def _free_near(m, p, area, avoid, reach=6):
    best = None
    for dx in range(-reach, reach + 1):
        for dy in range(-reach, reach + 1):
            q = (p[0] + dx, p[1] + dy)
            t = m.get(*q)
            if q in avoid or t is None or t.apath != area or not _open(t) or _door(t):
                continue
            if any(_door(m.get(q[0] + a, q[1] + b)) for a, b in N4):
                continue
            if any(o.path.startswith(("/obj/item", "/obj/structure", "/obj/machinery", "/mob")) and not CO.mounted(o)
                   for o in t.objs):
                continue
            d = abs(dx) + abs(dy)
            if best is None or d < best[0]:
                best = (d, q)
    return best[1] if best else None


if __name__ == "__main__":
    m = dmm.read(sys.argv[1])
    for x, y, why in dead(m):
        t = m.get(x, y)
        print("%d,%d %-8s %s" % (x, y, why, t.apath))
