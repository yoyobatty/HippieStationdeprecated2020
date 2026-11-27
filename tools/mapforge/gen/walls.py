"""Double walls merged into one: where a room's whole side stands against another wall (floor | wall | wall | floor,
the room's own wall beside a hall's or a neighbour's), the room takes its wall line as floor and keeps the
neighbour's wall as its own. The room's edge row moves out one tile with everything on it (furniture stays against
its wall, wall pieces stay on their wall), so the room stays a rectangle one row bigger.

The user 2026-11-25: "I still [see] inappropriate double walls". gen/mapinspect.py measured 22.2 double-wall tiles
per 1000 floor tiles on crew 100 seed 7 against the stock maps' 8-13: department blocks bring their outer walls and
the halls theirs.

    from gen import walls; walls.merge_doubles(m, log)     # after connect, before the networks are laid

Only whole sides (the run ends at the room's corners, no door in it), only rooms (not halls, maint, space, sealed
chambers, the AI's or the engine's rooms), never a side that has glass or a door in either wall.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import dmm  # noqa: E402

NOT_ROOM = ("/area/hallway", "/area/maintenance", "/area/space", "/area/solar", "/area/shuttle", "/area/engine/atmos",
            "/area/engine/supermatter", "/area/ai_monitored", "/area/science/mixing/chamber", "/area/tcommsat",
            "/area/science/test_area", "/area/science/server", "/area/aisat")
KEEP = ("/obj/effect/turf_decal",)       # stays on its tile (floor markings)


def _wall(t):
    return t is not None and t.tpath.startswith("/turf/closed") and not t.objs


def _floor(t):
    return t is not None and t.tpath.startswith("/turf/open") and not t.tpath.startswith("/turf/open/space") \
        and not t.has("/obj/machinery/door") and not t.has("/obj/structure/window") and not t.has("/obj/structure/grille") \
        and not t.has("/obj/effect/spawner/structure/window")


def _sealed(t):
    return t.tpath.startswith("/turf/open/floor/engine") or "airless" in t.tpath


def merge_doubles(m, log=print, min_run=2):
    """Returns how many wall tiles became room floor."""
    done = 0
    rows = 0
    for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        perp = (d[1], d[0])
        pairs = set()
        for (x, y, z), t in list(m.tiles.items()):
            if not _wall(t):
                continue
            a = m.get(x - d[0], y - d[1])          # the room's floor
            w2 = m.get(x + d[0], y + d[1])         # the neighbour's wall
            b = m.get(x + 2 * d[0], y + 2 * d[1])  # the neighbour's floor
            if not (_floor(a) and _wall(w2) and _floor(b)):
                continue
            if a.apath.startswith(NOT_ROOM) or _sealed(a) or a.apath == b.apath:
                continue
            pairs.add((x, y))
        seen = set()
        for p in sorted(pairs):
            if p in seen:
                continue
            # the run along perp through p
            run = [p]
            q = (p[0] - perp[0], p[1] - perp[1])
            while q in pairs:
                run.insert(0, q)
                q = (q[0] - perp[0], q[1] - perp[1])
            q = (p[0] + perp[0], p[1] + perp[1])
            while q in pairs:
                run.append(q)
                q = (q[0] + perp[0], q[1] + perp[1])
            seen |= set(run)
            if len(run) < min_run:
                continue
            row = [(w[0] - d[0], w[1] - d[1]) for w in run]
            area = m.get(*row[0]).apath
            if any(m.get(*c).apath != area for c in row):
                continue
            # the whole side: past both ends of the row the room's own walls (its corners), and past both ends of the
            # wall line walls too, so the new row is closed at its ends
            ends = [(row[0][0] - perp[0], row[0][1] - perp[1]), (row[-1][0] + perp[0], row[-1][1] + perp[1])]
            wends = [(run[0][0] - perp[0], run[0][1] - perp[1]), (run[-1][0] + perp[0], run[-1][1] + perp[1])]
            if not all(m.get(*e) is not None and m.get(*e).tpath.startswith("/turf/closed") and not m.get(*e).has(
                    "/obj/machinery/door") for e in ends + wends):
                continue
            # the row moves out onto the wall line; the old row keeps its floor and markings
            for w, c in zip(run, row):
                tc = m.get(*c)
                tw = m.get(*w)
                moving = [o for o in tc.objs if not o.path.startswith(KEEP)]
                staying = [o for o in tc.objs if o.path.startswith(KEEP)]
                m.set(w[0], w[1], dmm.Tile(moving, tc.turf, tc.area))
                tc.objs = staying
                done += 1
            rows += 1
    # what's left facing a hall or maint: the hall's own wall line becomes a niche of the hall (one tile deep, the
    # run's length; stock halls have such niches), the room's wall standing as the shared one
    niches = 0
    for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        perp = (d[1], d[0])
        pairs = set()
        for (x, y, z), t in list(m.tiles.items()):
            if not _wall(t):
                continue
            a = m.get(x - d[0], y - d[1])          # the hall's floor
            w2 = m.get(x + d[0], y + d[1])
            b = m.get(x + 2 * d[0], y + 2 * d[1])
            if _floor(a) and _wall(w2) and _floor(b) and a.apath.startswith(HALLS) and a.apath != b.apath                     and not a.apath.startswith("/area/maintenance/solars"):
                pairs.add((x, y))
        # a niche tile's sides along the wall line stay closed: wall, another niche tile, or the hall's own floor
        # (a room grown into a gap beside it was left open to maint through the niche, f29)
        changed = True
        while changed:
            changed = False
            for (x, y) in sorted(pairs):
                a_ = m.get(x - d[0], y - d[1])
                for s_ in (1, -1):
                    e = (x + s_ * perp[0], y + s_ * perp[1])
                    te = m.get(*e)
                    if e in pairs or te is None or te.tpath.startswith("/turf/closed") or _wallish(te):
                        continue
                    if _floor(te) and te.apath == a_.apath:
                        continue
                    pairs.discard((x, y))
                    changed = True
                    break
        for (x, y) in sorted(pairs):
            # a run of two or more: a lone pair is a pillar or a corner
            if (x + perp[0], y + perp[1]) not in pairs and (x - perp[0], y - perp[1]) not in pairs:
                continue
            a = m.get(x - d[0], y - d[1])
            # the hall no wider than 6 with its niche (gen/gate.py "halls 7+ wide")
            wd, q = 0, (x - d[0], y - d[1])
            while wd < 8 and m.get(*q) is not None and m.get(*q).apath == a.apath and _floor(m.get(*q)):
                wd += 1
                q = (q[0] - d[0], q[1] - d[1])
            if a.apath.startswith("/area/hallway") and wd + 1 >= 7:
                continue
            # what hung on the old wall from the hall side hangs on the room's wall now, from the niche
            hung = [o for o in a.objs if _hangs_toward(o, d)]
            a.objs = [o for o in a.objs if o not in hung]
            m.set(x, y, dmm.Tile(hung, a.turf, a.area))
            niches += 1
    log("walls: %d double-wall tiles merged into %d rooms' sides, %d into hall niches" % (done, rows, niches))
    return done + niches


HALLS = ("/area/hallway", "/area/maintenance")
SIDE_OF = {(0, 1): 1, (0, -1): 2, (1, 0): 4, (-1, 0): 8}


def _hangs_toward(o, d):
    """A wall piece on a floor tile hanging on the wall in direction d: by pixel offset, or a light, camera or sign
    by its dir."""
    px, py = o.num("pixel_x"), o.num("pixel_y")
    if abs(px) >= 16 or abs(py) >= 16:
        side = (1 if py > 0 else 2) if abs(py) >= abs(px) else (4 if px > 0 else 8)
        return side == SIDE_OF[d]
    if o.path.startswith(("/obj/machinery/light", "/obj/machinery/camera")) and not o.path.startswith(
            "/obj/machinery/light_switch"):
        return o.num("dir", 2) == SIDE_OF[d]
    return False


OPEN_OK = ("/area/space", "/area/solar", "/area/shuttle", "/area/engine/supermatter", "/area/science/test_area")


def seal_hull(m, log=print):
    """The last word on the hull: a space tile beside station floor becomes reinforced wall. Station floor is open
    turf of a station area (not space, solars, shuttles, the crystal's room, the test range), not airless plating or
    an engine floor, with no door on it. Crew 100 seed 7 lost its halls' air through a maint corridor with space on
    one side (a pass after the wall merge took its outer wall), 2026-11-25."""
    sealed = 0
    # a mass driver's throw line out to space stays open (the disposal exit: walled at the tile past its blast door,
    # trash hit the wall, f46); the floor beside the line is walled instead, when it is plain floor
    DIRV_ = {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0)}
    line = set()
    for (x, y, z), t in m.tiles.items():
        for o in t.objs:
            if o.path.startswith("/obj/machinery/mass_driver"):
                d = DIRV_.get(o.num("dir", 2), (0, -1))
                for k in range(1, 6):
                    line.add((x + d[0] * k, y + d[1] * k))
    moved = 0
    for (x, y, z), t in list(m.tiles.items()):
        if not t.tpath.startswith("/turf/open") or t.tpath.startswith("/turf/open/space") or "airless" in t.tpath                 or t.tpath.startswith("/turf/open/floor/engine") or t.apath.startswith(OPEN_OK)                 or t.has("/obj/machinery/door") or t.has("/obj/structure/lattice") or t.has("/obj/structure/window")                 or t.has("/obj/structure/grille") or t.has("/obj/effect/spawner/structure/window"):
            continue
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = m.get(x + dx, y + dy)
            if n is not None and n.tpath.startswith("/turf/open/space") and not n.has("/obj/structure/lattice"):
                if (x + dx, y + dy) in line and (x, y) not in line:
                    from forge import function as FN_
                    if not any(FN_.is_dense(o) for o in t.objs):
                        keep = [o for o in t.objs if o.path.startswith(("/obj/structure/cable", "/obj/machinery/atmospherics",
                                                                         "/obj/structure/disposalpipe"))]
                        m.set(x, y, dmm.Tile(keep, dmm.Atom("/turf/closed/wall/r_wall"), t.area))
                        moved += 1
                        break
                m.set(x + dx, y + dy, dmm.Tile(list(n.objs), dmm.Atom("/turf/closed/wall/r_wall"), t.area))
                sealed += 1
    log("walls: hull sealed at %d space tiles beside station floor%s" % (
        sealed, (", %d floor tiles beside a disposal exit's throw line walled instead" % moved) if moved else ""))
    return sealed


if __name__ == "__main__":
    path = sys.argv[1]
    m = dmm.read(path)
    merge_doubles(m)
    if len(sys.argv) > 2:
        dmm.write(m, sys.argv[2])


# ------------------------------------------------------------------------------------------------ corner joins
def _wallish(t):
    """Wall, glass or a door: what a wall line is made of."""
    return t is not None and (t.tpath.startswith("/turf/closed") or any(o.path.startswith((
        "/obj/effect/spawner/structure/window", "/obj/structure/window", "/obj/structure/grille", "/obj/machinery/door"))
        for o in t.objs))


def _door(t):
    return t is not None and t.has("/obj/machinery/door")


def corner_joins(m):
    """[(wall a, wall b, (floor c, floor d))]: 2x2 squares where two walls touch only at a corner and the other
    diagonal is floor (the wall between two rooms steps a row and its two runs never meet: medbay and surgery,
    crew 100 seed 7 f21, the user 2026-11-26 "some walls don't join together where they should ... this awkward
    diagonal")."""
    out = []
    for (x, y, z), t in m.tiles.items():
        if z != 1:
            continue
        A, B, C, D = t, m.get(x + 1, y), m.get(x, y - 1), m.get(x + 1, y - 1)
        if None in (B, C, D) or any(q.tpath.startswith("/turf/open/space") for q in (A, B, C, D)):
            continue
        a, b, c, d = (_wallish(q) for q in (A, B, C, D))
        if a and d and not b and not c:
            out.append(((x, y), (x + 1, y - 1), ((x + 1, y), (x, y - 1))))
        elif b and c and not a and not d:
            out.append(((x + 1, y), (x, y - 1), ((x, y), (x + 1, y - 1))))
    return out


def _piece(m, p, cap=4000):
    """The floor tiles of p's area joined to p (doors stop it)."""
    area = m.get(*p).apath
    seen, todo = {p}, [p]
    while todo and len(seen) < cap:
        q = todo.pop()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (q[0] + dx, q[1] + dy)
            t = m.get(*n)
            # halls and maint walk as one floor whatever their area names (a 2-tile nook of maint-area floor on a
            # hall's edge counted as a 2-tile room and its corner join was left, f36)
            if n in seen or t is None or not _floor(t) or not (t.apath == area or (
                    area.startswith(HALLS) and t.apath.startswith(HALLS))):
                continue
            seen.add(n)
            todo.append(n)
    return seen


def _joined(tiles):
    if not tiles:
        return True
    s = next(iter(tiles))
    seen, todo = {s}, [s]
    while todo:
        q = todo.pop()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (q[0] + dx, q[1] + dy)
            if n in tiles and n not in seen:
                seen.add(n)
                todo.append(n)
    return len(seen) == len(tiles)


CLUTTER = ("/obj/structure/closet/crate", "/obj/structure/rack", "/obj/item", "/obj/effect/spawner/lootdrop",
           "/obj/effect/decal", "/obj/machinery/light/small", "/obj/structure/girder", "/obj/structure/chair", "/obj/structure/table",
           "/obj/structure/reagent_dispensers", "/obj/machinery/space_heater", "/obj/structure/closet/cardboard",
           "/obj/structure/closet/emcloset", "/obj/structure/closet/firecloset", "/obj/effect/spawner")


UNDER_WALL = ("/obj/machinery/atmospherics/pipe", "/obj/structure/cable", "/obj/structure/disposalpipe")


def _clear_for_wall(m, floors):
    """One of the floor tiles cleared by moving its one standing piece to another spot of its room. Returns the tile,
    or None."""
    import sys as _sys
    _sys.path.insert(0, os.path.join(HERE, "learn"))
    import placestudy as PS
    import settle as ST
    from forge import corpus as CO, function as FN
    for p in floors:
        t = m.get(*p)
        if not _floor(t) or _sealed(t):
            continue
        if any(_door(m.get(p[0] + dx, p[1] + dy)) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
            continue
        objs = [o for o in t.objs if not o.path.startswith(KEEP)]
        dense = [o for o in objs if FN.is_dense(o)]
        if len(dense) != 1 or dense[0].path.startswith(ST.FIXED) or any(CO.mounted(o) for o in objs) \
                or any(o.path.startswith(("/obj/structure/cable", "/obj/machinery/atmospherics", "/obj/structure/disposalpipe",
                                          "/obj/machinery/light")) for o in objs):
            continue
        o = dense[0]
        F = _piece(m, p)
        rest = F - {p}
        if len(rest) < 6 or not _joined(rest):
            continue
        doors = {(q[0] + dx, q[1] + dy) for q in F for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                 if PS._door(m.get(q[0] + dx, q[1] + dy))}
        if not doors:
            continue
        spot = ST._spot(m, rest | {p}, doors, p, o)
        if spot is None or spot == p:
            continue
        carry = [x for x in objs]
        t.objs = [x for x in t.objs if x.path.startswith(KEEP)]
        m.get(*spot).objs.extend(carry)
        return p
    return None


def join_corners(m, log=print):
    """Each corner-only join closed with one wall tile on one of its two floor tiles: a bare one (nothing on it but
    floor markings), not a door's front, whose room stays in one piece without it and keeps at least 6 tiles; the
    bigger room's tile first (it misses the tile least). The wall is the touching walls' own turf. Joins of the stock
    maps' kind stay (a pillar, a window run on the diagonal, glass or doors at the corner: Meta 15, Box 7)."""
    made = 0
    for _ in range(3):
        n0 = made
        for wa, wb, floors in corner_joins(m):
            ta, tb = m.get(*wa), m.get(*wb)
            if not (ta.tpath.startswith("/turf/closed") and tb.tpath.startswith("/turf/closed")):
                continue            # glass or a door at the corner: a window run or a doorway, as the stock maps have
            cands = []
            for p in floors:
                t = m.get(*p)
                # bare, or maint floor with only loose clutter on it (a crate or a rack in a maint corner kept two
                # walls corner to corner: f29 183,39 and 183,50)
                # (pipes and cables run on under the new wall, as they do under any wall)
                loose = t is not None and t.apath.startswith("/area/maintenance") and all(
                    o.path.startswith(KEEP + CLUTTER + UNDER_WALL) for o in t.objs)
                if not _floor(t) or (any(not o.path.startswith(KEEP + UNDER_WALL) for o in t.objs) and not loose) or _sealed(t):
                    continue
                if any(_door(m.get(p[0] + dx, p[1] + dy)) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                    continue
                piece = _piece(m, p)
                rest = piece - {p}
                if len(rest) < 6 or not _joined(rest):
                    continue
                cands.append((-len(piece), p))
            if not cands:
                # no bare tile: the piece standing on one of them moves elsewhere in its room (gen/learn/settle._spot:
                # against a wall, reach kept), then that tile is walled (a chapel corner with a table on it, f31)
                p = _clear_for_wall(m, floors)
                if p is None:
                    continue
                cands = [(0, p)]
            p = min(cands)[1]
            t = m.get(*p)
            t.turf = dmm.Atom(ta.tpath if ta.tpath == tb.tpath else "/turf/closed/wall")
            t.objs = [o for o in t.objs if o.path.startswith(UNDER_WALL)]
            made += 1
        if made == n0:
            break
    left = len(corner_joins(m))
    log("join_corners: %d wall tiles where two walls met only at a corner (%d corner joins left, glass/doors/stock kind)"
        % (made, left))
    return made


# ------------------------------------------------------------------------------------------------ sealed slivers
SLIVER_MAX = 8       # a sealed pocket of space this small is no light well: it is closed up


def fill_slivers(m, log=print):
    """Small pockets of space sealed inside the station (a 1-wide gap left between two blocks' walls) become wall,
    and a window that looked onto one becomes wall too. Bigger pockets are gen/voids.py's (rooms) or stay light
    wells. crew 100 seed 7 f29: a 1x2 pocket between the engine block's windows and Atmospherics (the user: "this
    area here looks weird")."""
    def space(t):
        return t is not None and t.tpath.startswith("/turf/open/space")
    cells = {(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and space(t)}
    # open space: reached from the map's edge
    seen = set()
    todo = [c for c in cells if c[0] in (1, m.maxx) or c[1] in (1, m.maxy)]
    seen.update(todo)
    while todo:
        p = todo.pop()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (p[0] + dx, p[1] + dy)
            if n in cells and n not in seen:
                seen.add(n)
                todo.append(n)
    left = cells - seen
    filled = windows = 0
    while left:
        s0 = left.pop()
        comp, q = {s0}, [s0]
        while q:
            p = q.pop()
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = (p[0] + dx, p[1] + dy)
                if n in left:
                    left.discard(n)
                    comp.add(n)
                    q.append(n)
        if len(comp) > SLIVER_MAX or any(m.get(*c).objs for c in comp):
            continue
        area = None
        for c in comp:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                t = m.get(c[0] + dx, c[1] + dy)
                if t is not None and not space(t) and t.apath and not t.apath.startswith("/area/space"):
                    area = area or t.apath
        for c in comp:
            m.set(c[0], c[1], dmm.Tile([], dmm.Atom("/turf/closed/wall"), dmm.Atom(area or "/area/maintenance/central")))
            filled += 1
        # windows round the closed pocket that now look at wall (no axis with something to see on both sides)
        def glass(t):
            return t is not None and t.objs and all(o.path.startswith((
                "/obj/effect/spawner/structure/window", "/obj/structure/grille", "/obj/structure/window")) for o in t.objs)

        def shut(t):
            return t is None or t.tpath.startswith("/turf/closed") or glass(t)
        near = {(c[0] + dx, c[1] + dy) for c in comp for dx in (-2, -1, 0, 1, 2) for dy in (-2, -1, 0, 1, 2)}
        for _ in range(2):
            for w in sorted(near):
                t = m.get(*w)
                if not glass(t):
                    continue
                if (shut(m.get(w[0] - 1, w[1])) or shut(m.get(w[0] + 1, w[1]))) and                         (shut(m.get(w[0], w[1] - 1)) or shut(m.get(w[0], w[1] + 1))):
                    m.set(w[0], w[1], dmm.Tile([], dmm.Atom("/turf/closed/wall"), t.area.copy() if t.area else dmm.Atom(area)))
                    windows += 1
    log("fill_slivers: %d tiles of sealed space closed up, %d windows onto them walled" % (filled, windows))
    return filled


def hull_corners(m, log=print):
    """The hull's outer corners closed: where two hull walls meet only corner to corner round station floor (the
    corner tile itself left as space), that tile becomes wall. The user 2026-11-26: "this corner has an empty wall,
    leaving a diagonal". Stock maps: 0 (gen/gate.py "hull corners")."""
    def space(t):
        return t is not None and t.tpath.startswith("/turf/open/space") and not t.objs

    def floor(t):
        return t is not None and t.tpath.startswith("/turf/open") and not t.tpath.startswith("/turf/open/space")
    made = 0
    for _ in range(3):
        n0 = made
        for (x, y, z), t in list(m.tiles.items()):
            if z != 1:
                continue
            sq = [(x, y), (x + 1, y), (x, y - 1), (x + 1, y - 1)]
            ts = [m.get(*q) for q in sq]
            if None in ts:
                continue
            for a, d, b, c in ((0, 3, 1, 2), (1, 2, 0, 3)):
                if not (_wallish(ts[a]) and _wallish(ts[d])):
                    continue
                for f_, s_ in ((b, c), (c, b)):
                    if floor(ts[f_]) and not _wallish(ts[f_]) and space(ts[s_]):
                        q = sq[s_]
                        wall = ts[a].tpath if ts[a].tpath.startswith("/turf/closed") else (
                            ts[d].tpath if ts[d].tpath.startswith("/turf/closed") else "/turf/closed/wall")
                        m.set(q[0], q[1], dmm.Tile([], dmm.Atom(wall), ts[f_].area.copy()))
                        ts[s_] = m.get(*q)
                        made += 1
        if made == n0:
            break
    log("hull_corners: %d corner tiles of the hull closed" % made)
    return made


# ------------------------------------------------------------------------------------------------ gaps absorbed
def _enclosed_space(m):
    """Components of space not reached from the map's edge."""
    def space(t):
        return t is not None and t.tpath.startswith("/turf/open/space")
    cells = {(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and space(t)}
    seen = set()
    todo = [c for c in cells if c[0] in (1, m.maxx) or c[1] in (1, m.maxy)]
    seen.update(todo)
    while todo:
        p = todo.pop()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (p[0] + dx, p[1] + dy)
            if n in cells and n not in seen:
                seen.add(n)
                todo.append(n)
    left = cells - seen
    out = []
    while left:
        s0 = left.pop()
        comp, q = {s0}, [s0]
        while q:
            p = q.pop()
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = (p[0] + dx, p[1] + dy)
                if n in left:
                    left.discard(n)
                    comp.add(n)
                    q.append(n)
        out.append(comp)
    return out


def _open(t):
    """Floor someone stands on (not space, not wall, not glass)."""
    return t is not None and t.tpath.startswith("/turf/open") and not t.tpath.startswith("/turf/open/space") \
        and not t.has("/obj/effect/spawner/structure/window") and not t.has("/obj/structure/grille") \
        and not t.has("/obj/structure/window")


def bad_joins(m, cells):
    """Faults round the given cells: [(kind, cell)] with kind "diagonal" (a 2x2 square with wall or glass on one
    diagonal and floor or space on the other: two walls meeting only at a corner) or "open" (floor of two different
    areas side by side with no wall or door between, halls and maint among themselves aside)."""
    out = []
    seen = set()
    for c in cells:
        for ox, oy in ((0, 0), (-1, 0), (0, 1), (-1, 1)):
            a = (c[0] + ox, c[1] + oy)
            if a in seen:
                continue
            seen.add(a)
            sq = [a, (a[0] + 1, a[1]), (a[0], a[1] - 1), (a[0] + 1, a[1] - 1)]
            ts = [m.get(*q) for q in sq]
            if None in ts:
                continue
            w = [_wallish(t) and not t.has("/obj/machinery/door") for t in ts]
            o = [not _wallish(t) for t in ts]
            if (w[0] and w[3] and o[1] and o[2] and (_open(ts[1]) or _open(ts[2]))) or \
                    (w[1] and w[2] and o[0] and o[3] and (_open(ts[0]) or _open(ts[3]))):
                out.append(("diagonal", a))
        t = m.get(*c)
        if _open(t) and not t.has("/obj/machinery/door"):
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = m.get(c[0] + dx, c[1] + dy)
                if _open(n) and not n.has("/obj/machinery/door") and n.apath != t.apath and not (
                        t.apath.startswith(HALLS) and n.apath.startswith(HALLS)):
                    out.append(("open", c))
    return out


def _corner_fix(m, cells):
    """Close the corner-only joins round `cells` by turning one bare floor tile of each into wall (a room's own
    corner tile: nothing on it, no door beside it, two of its own floor tiles and the one between them beside it).
    True when none is left."""
    for _ in range(4):
        diags = [a for k, a in bad_joins(m, cells) if k == "diagonal"]
        if not diags:
            return True
        fixed = False
        for a in diags:
            sq = [a, (a[0] + 1, a[1]), (a[0], a[1] - 1), (a[0] + 1, a[1] - 1)]
            for q in sq:
                t = m.get(*q)
                if not _open(t) or any(not o.path.startswith(KEEP) for o in t.objs):
                    continue
                if any(m.get(q[0] + dx, q[1] + dy) is not None and m.get(q[0] + dx, q[1] + dy).has("/obj/machinery/door")
                       for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                    continue
                # its own corner: floor of its area on two sides at right angles, and the tile between those
                ok = False
                for dx, dy in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
                    n1, n2, n3 = m.get(q[0] + dx, q[1]), m.get(q[0], q[1] + dy), m.get(q[0] + dx, q[1] + dy)
                    if all(_open(n) and n.apath == t.apath for n in (n1, n2, n3)):
                        ok = True
                if not ok:
                    continue
                m.set(q[0], q[1], dmm.Tile([], dmm.Atom("/turf/closed/wall"), t.area.copy()))
                cells.add(q)
                fixed = True
                break
        if not fixed:
            return False
    return not [1 for k, a in bad_joins(m, cells) if k == "diagonal"]


def absorb_gaps(m, log=print):
    """A small pocket of space sealed between two walls is taken over by the rooms beside it, not walled up into a
    block three walls thick. Across the gap (floor | wall | gap | wall | floor), tried in this order for the whole
    pocket: each side grows one tile onto its own wall line and the gap becomes the one wall between them; one side
    grows two and the other's wall is the shared one; one side grows one and the gap is walled; the gap is walled.
    The grown side's edge row moves out with everything on it (furniture stays against its wall, what hangs on the
    wall still hangs on it). An option is kept only if it leaves no floor of two areas open to each other and no two
    walls meeting only at a corner (a bare corner tile may be walled to join them). Sides that can't grow: sealed
    chambers, a door on the edge. Run before merge_doubles and the networks.

    The user 2026-11-26, on the walled-up pocket beside the engine: "now we have double walls, so the departments
    could just carve them out and have props move into them properly"; and on the first try, which left the grown
    alcove open to maint with two walls corner to corner: "walls need to join without this stupid diagonal"."""
    def glass(t):
        return t is not None and t.objs and all(o.path.startswith(("/obj/effect/spawner/structure/window",
                                                                   "/obj/structure/grille", "/obj/structure/window"))
                                                for o in t.objs)

    def line(t):
        return _wall(t) or glass(t)

    def can(a, w):
        ta, tw = m.get(*a), m.get(*w)
        if not _floor(ta) or not line(tw) or _sealed(ta) or ta.apath.startswith(("/area/space", "/area/solar",
                                                                                 "/area/engine/supermatter")):
            return False
        return not ta.has("/obj/machinery/door")

    def grow(a, cs):
        ta = m.get(*a)
        moving = [o for o in ta.objs if not o.path.startswith(KEEP)]
        ta.objs = [o for o in ta.objs if o.path.startswith(KEEP)]
        for i, c in enumerate(cs):
            m.set(c[0], c[1], dmm.Tile(moving if i == len(cs) - 1 else [], dmm.Atom(ta.turf.path, list(ta.turf.vars)),
                                       ta.area.copy()))

    def wall_up(c, area):
        m.set(c[0], c[1], dmm.Tile([], dmm.Atom("/turf/closed/wall"), dmm.Atom(area)))
    grown = walled = pockets = 0
    touched = set()
    for comp in _enclosed_space(m):
        if len(comp) > SLIVER_MAX or any(m.get(*c).objs for c in comp):
            continue
        pockets += 1
        area0 = next((m.get(c[0] + dx, c[1] + dy).apath for c in sorted(comp) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                      if m.get(c[0] + dx, c[1] + dy) is not None and m.get(c[0] + dx, c[1] + dy).apath
                      and not m.get(c[0] + dx, c[1] + dy).apath.startswith("/area/space")), "/area/maintenance/central")
        best = None
        for d in ((1, 0), (0, 1)):
            for opt in ("both", "left2", "right2", "left1", "right1"):
                # every tile of the pocket the same way, or the option is out
                plan = []
                for p in sorted(comp):
                    wl, al = (p[0] - d[0], p[1] - d[1]), (p[0] - 2 * d[0], p[1] - 2 * d[1])
                    wr, ar = (p[0] + d[0], p[1] + d[1]), (p[0] + 2 * d[0], p[1] + 2 * d[1])
                    okl, okr = can(al, wl), can(ar, wr)
                    if opt == "both" and okl and okr:
                        plan.append(([(al, [wl]), (ar, [wr])], p))
                    elif opt == "left2" and okl:
                        plan.append(([(al, [wl, p])], None))
                    elif opt == "right2" and okr:
                        plan.append(([(ar, [wr, p])], None))
                    elif opt == "left1" and okl:
                        plan.append(([(al, [wl])], p))
                    elif opt == "right1" and okr:
                        plan.append(([(ar, [wr])], p))
                    else:
                        plan = None
                        break
                if not plan:
                    continue
                cells = set(comp)
                for takes, wp in plan:
                    for a, cs in takes:
                        cells.add(a)
                        cells.update(cs)
                ring = {(c[0] + dx, c[1] + dy) for c in cells for dx in (-2, -1, 0, 1, 2) for dy in (-2, -1, 0, 1, 2)}
                snap = {c: m.get(*c).copy() for c in ring if m.get(*c) is not None}
                before = set(bad_joins(m, ring))
                for takes, wp in plan:
                    for a, cs in takes:
                        grow(a, cs)
                    if wp is not None:
                        wall_up(wp, area0)
                work = set(ring)
                _corner_fix(m, work)
                blind_windows(m, cells)
                after = set(bad_joins(m, work))

                def touches(kind, a_):
                    if kind == "open":
                        return a_ in cells
                    return bool({a_, (a_[0] + 1, a_[1]), (a_[0], a_[1] - 1), (a_[0] + 1, a_[1] - 1)} & cells)
                # nothing new anywhere near, and no fault at all left on the tiles this changed (a corner-only join
                # that was there with the gap must not stay with floor in the gap's place)
                if not (after - before) and not any(touches(*f) for f in after):
                    best = (opt, sum(len(cs) for takes, _ in plan for _, cs in takes), sum(1 for _, wp in plan if wp is not None))
                    break
                for c, t in snap.items():           # this option leaves a fault: put everything back
                    m.set(c[0], c[1], t)
            if best:
                break
        if best:
            grown += best[1]
            walled += best[2]
        else:
            for p in comp:
                wall_up(p, area0)
            blind_windows(m, comp)
            walled += len(comp)
        touched |= comp
    log("absorb_gaps: %d sealed gaps: %d tiles taken into the rooms beside them, %d walled" % (pockets, grown, walled))
    return grown


GLASS = ("/obj/effect/spawner/structure/window", "/obj/structure/window", "/obj/structure/grille")
N8_ = ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1))


def _pane(t):
    """A window tile of the station (not a grille on lattice out in space)."""
    return t is not None and not t.tpath.startswith("/turf/open/space") and not t.tpath.startswith("/turf/closed") \
        and any(o.path.startswith(GLASS) for o in t.objs)


def _seen_from(t):
    """Floor someone stands on, or a door: what makes a window a window."""
    if t is None or t.tpath.startswith("/turf/closed") or t.tpath.startswith("/turf/open/space"):
        return False
    return any(o.path.startswith("/obj/machinery/door") for o in t.objs) or not any(o.path.startswith(GLASS)
                                                                                     for o in t.objs)


def stray_glass(m, cells=None):
    """[(x, y)] of windows with no floor or door round them (8 ways): nobody looks through them. They are what is left
    of a wall line whose walls went: connect.prune_stubs turns walls with no floor round them to space and kept the
    windows, so an old outer wall stood as single panes off the hull every other tile (the user 2026-11-26: "random
    windows that spawn on their own turf in space, looks weird"). cells: only these."""
    out = []
    for (x, y, z), t in m.tiles.items():
        if z != 1 or (cells is not None and (x, y) not in cells) or not _pane(t):
            continue
        if not any(_seen_from(m.get(x + dx, y + dy)) for dx, dy in N8_):
            out.append((x, y))
    return out


def clear_stray_glass(m, log=print):
    """stray_glass() to space where it touches space, else to wall (a pane between two walls), until none is left.
    Returns how many."""
    n = 0
    for _ in range(4):
        st = stray_glass(m)
        if not st:
            break
        for (x, y) in st:
            t = m.get(x, y)
            keep = [o for o in t.objs if o.path.startswith(("/obj/structure/cable", "/obj/machinery/atmospherics",
                                                             "/obj/structure/disposalpipe"))]
            out_ = any(m.get(x + dx, y + dy) is None or m.get(x + dx, y + dy).tpath.startswith("/turf/open/space")
                       for dx, dy in N8_[:4])
            if out_ and not keep:
                m.set(x, y, dmm.Tile([], dmm.Atom("/turf/open/space/basic"), dmm.Atom("/area/space")))
            else:
                m.set(x, y, dmm.Tile(keep, dmm.Atom("/turf/closed/wall"), t.area))
            n += 1
    if n:
        log("walls: %d stray window tiles cleared (no floor or door round them)" % n)
    return n


def blind_windows(m, near_cells):
    """Windows within 2 tiles of near_cells with nothing to look at (on neither axis open on both sides) become
    wall. Returns how many."""
    def glass(t):
        return t is not None and t.objs and all(o.path.startswith(("/obj/effect/spawner/structure/window",
                                                                   "/obj/structure/grille", "/obj/structure/window"))
                                                for o in t.objs)

    def shut(t):
        return t is None or t.tpath.startswith("/turf/closed") or glass(t)
    near = {(c[0] + dx, c[1] + dy) for c in near_cells for dx in (-2, -1, 0, 1, 2) for dy in (-2, -1, 0, 1, 2)}
    n = 0
    for _ in range(2):
        for w in sorted(near):
            t = m.get(*w)
            if glass(t) and (shut(m.get(w[0] - 1, w[1])) or shut(m.get(w[0] + 1, w[1]))) and                     (shut(m.get(w[0], w[1] - 1)) or shut(m.get(w[0], w[1] + 1))):
                m.set(w[0], w[1], dmm.Tile([], dmm.Atom("/turf/closed/wall"), t.area.copy()))
                n += 1
    return n
