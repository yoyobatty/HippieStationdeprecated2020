"""Rooms a walker can get into: reach measured the way a crew member (or a bot's path search) walks, past furniture and
shut firedoors, and fixed where it fails.

    from gen import walkfix
    walkfix.fix(m, log)              # after dress and connect: edits the dmm.Map in place
    walkfix.measure(m)               # {area: (reached floor, floor)} from the primary halls
    python tools/mapforge/gen/walkfix.py gen_c80_s1      # report on data/mapforge/<name>.dmm

The gate's walk checks (forge/walk.py) go by walls and doors only. On crew 80 seed 1 (2026-11-25) that passed while 40
areas were under 60% walkable (the accepted v6 build: 7): Hydroponics' door opened onto a tray and its backroom doors
carried firedoors copied shut (`density = 1`, 50 on the map), and the bridge, chapel office, EVA and the rest were sealed
the same ways. The Bot Shift's botanist found no path into the bay all shift.

Fixes, in rounds until nothing changes:
  1. every firedoor starts open (a copied `density` var is dropped), as the game spawns them;
  2. a door whose floor on either side holds something dense: the dense things move to the nearest free floor of the
     same area that isn't in front of a door (or go, if there is none);
  3. a walkable piece of floor no walk from the halls reaches: one door through a single plain wall to reached floor,
     its own area first, then its department, then a hall, then maint (connect.py's ranks).
"""
import os
import sys
from collections import deque

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import dmm, kit, parse  # noqa: E402

N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
FIREDOOR = "/obj/machinery/door/firedoor"
# floor no crew member is meant to walk into
SKIP_AREAS = ("/area/space", "/area/solar", "/area/science/test_area", "/area/engine/supermatter", "/area/shuttle")
LOW = 0.6           # an area under this share of its floor reached counts as cut off (measure's report)


def _door(t):
    return any(o.path.startswith("/obj/machinery/door") and not o.path.startswith(FIREDOOR) for o in t.objs)


def _shut_fire(t):
    return any(o.path.startswith(FIREDOOR) and (o.get("density") or "0").strip() not in ("0", "FALSE") for o in t.objs)


def _open_floor(t):
    return t is not None and t.tpath.startswith("/turf/open") and not t.tpath.startswith("/turf/open/space")


def _blocked(t):
    return kit.dense([o for o in t.objs if not o.path.startswith("/obj/machinery/door")])


def _glass(t):
    # a full-tile window is a wall to a walker; window spawners aren't dense themselves, so kit.dense misses them
    return any(o.path.startswith(parse.GLASS) for o in t.objs)


def walkable(t):
    if not _open_floor(t) or _shut_fire(t) or _glass(t):
        return False
    # a door is walked through, but not one standing on a table (a counter's windoor: chemistry's only way in on crew
    # 80 seed 1 was an airlock onto one)
    return not _blocked(t)


DIR = {(0, 1): 1, (0, -1): 2, (1, 0): 4, (-1, 0): 8}
OPP = {1: 2, 2: 1, 4: 8, 8: 4}
EDGE = ("/obj/structure/window", "/obj/structure/railing")


def _edge(t, d):
    """Something on tile t closes its edge toward d: a directional window or railing (a windoor is a door there)."""
    return any(o.path.startswith(EDGE) and not o.path.startswith(parse.GLASS) and o.num("dir", 2) == d for o in t.objs)


def step_ok(m, a, b):
    d = DIR[(b[0] - a[0], b[1] - a[1])]
    return walkable(m.get(*b)) and not _edge(m.get(*a), d) and not _edge(m.get(*b), OPP[d])


def _station(t):
    # not gas chambers (engine-floor subtypes) nor airless floor out past the hull (the engine's waste injector)
    return (_open_floor(t) and not t.apath.startswith(SKIP_AREAS) and not t.tpath.startswith("/turf/open/floor/engine/")
            and not t.tpath.endswith("/airless"))


def reach(m):
    start = [(x, y) for (x, y, z), t in m.tiles.items() if t.apath.startswith("/area/hallway/primary") and walkable(t)]
    seen = set(start)
    q = deque(start)
    while q:
        p = q.popleft()
        for dx, dy in N4:
            n = (p[0] + dx, p[1] + dy)
            if n not in seen and step_ok(m, p, n):
                seen.add(n)
                q.append(n)
    return seen


def measure(m, seen=None):
    """{area: (walkable floor reached from the primary halls, walkable floor)}."""
    seen = reach(m) if seen is None else seen
    out = {}
    for (x, y, z), t in m.tiles.items():
        if _station(t) and walkable(t):       # floor under a table or a machine is nobody's to walk on
            r, n = out.get(t.apath, (0, 0))
            out[t.apath] = (r + ((x, y) in seen), n + 1)
    return out


# reached by other ways than a walk from the halls on the stock maps too (the AI satellite: teleporter, transit tube)
NOT_WALKED = ("/area/ai_monitored/turret_protected", "/area/aisat", "/area/ai_monitored/storage/satellite")
# the stock maps' own count of cut-off areas (outside NOT_WALKED, by this module's walk): Meta 4, Box 0, Hippie 5,
# Delta 12 (abandoned rooms); the build's check allows CUT_OFF_MAX
CUT_OFF_MAX = 4


def cut_off(m, seen=None, low=LOW, least=6):
    """Areas of `least` floor tiles or more with under `low` of their floor reached (not NOT_WALKED)."""
    return sorted(a for a, (r, n) in measure(m, seen).items() if n >= least and r < low * n
                  and not a.startswith(NOT_WALKED))


def _group(area):
    return parse.group_of(area) if hasattr(parse, "group_of") else area.split("/")[2] if area.count("/") >= 2 else area


def _move_dense(m, p, area, avoid):
    """The dense things on p go to the nearest free floor of `area` not in `avoid` (door fronts); gone if none."""
    t = m.get(*p)
    dense = [o for o in t.objs if kit.is_dense_atom(o) and not o.path.startswith("/obj/machinery/door")]
    if not dense:
        return 0
    t.objs = [o for o in t.objs if o not in dense]
    best = None
    for x, y in [(p[0] + i, p[1] + j) for i in range(-8, 9) for j in range(-8, 9)]:
        u = m.get(x, y)
        if u is None or u.apath != area or (x, y) in avoid or (x, y) == p or not _open_floor(u) or _door(u) or kit.dense(u.objs) \
                or any(not o.path.startswith(("/obj/effect", "/obj/machinery/atmospherics", "/obj/structure/cable",
                                              "/obj/structure/disposalpipe", "/obj/item")) for o in u.objs):
            continue
        d = abs(x - p[0]) + abs(y - p[1])
        if best is None or d < best[0]:
            best = (d, (x, y))
    if best:
        m.get(*best[1]).objs.extend(dense)
    return len(dense)


def fix(m, log=print, rounds=6):
    opened = 0
    for t in m.tiles.values():
        for i, o in enumerate(t.objs):
            if o.path.startswith(FIREDOOR) and o.get("density") is not None:
                t.objs[i] = dmm.Atom(o.path, [(k, v) for k, v in o.vars if k != "density"])
                opened += 1
    moved = cut = 0
    for _ in range(rounds):
        seen = reach(m)
        before = len(seen)
        # 2. door fronts
        doors = [(x, y) for (x, y, z), t in m.tiles.items() if _door(t) and _open_floor(t)]
        fronts = {(d[0] + dx, d[1] + dy) for d in doors for dx, dy in N4}
        n_moved = 0
        for d in doors:
            for dx, dy in N4:
                a, b = (d[0] + dx, d[1] + dy), (d[0] - dx, d[1] - dy)
                ta, tb = m.get(*a), m.get(*b)
                if not (_open_floor(ta) and _open_floor(tb)):
                    continue            # the door's own axis has floor both sides; the other axis is its frame
                for p, tp in ((a, ta), (b, tb)):
                    if _blocked(tp) and not _door(tp):
                        n_moved += _move_dense(m, p, tp.apath, fronts)
        seen = reach(m) if n_moved else seen
        # 2b. furniture plugs: a blocked floor tile with reached floor on one side and unreached walkable floor on
        # another (EVA on crew 80 seed 1: the tile past its door led only to suit racks)
        plugs = 0
        for (x, y, z), t in list(m.tiles.items()):
            if not _station(t) or not _blocked(t) or _door(t) or _shut_fire(t):
                continue
            nbs = [(x + dx, y + dy) for dx, dy in N4]
            if any(n in seen for n in nbs) and any(n not in seen and _station(m.get(*n)) and walkable(m.get(*n))
                                                   for n in nbs):
                plugs += _move_dense(m, (x, y), t.apath, fronts | set(nbs))
                seen = reach(m)
        n_moved += plugs
        moved += n_moved
        # 3. cut off pieces: a door through one plain wall
        un = {(x, y) for (x, y, z), t in m.tiles.items() if _station(t) and walkable(t) and (x, y) not in seen}
        n_cut = 0
        done = set()
        for p0 in sorted(un):
            if p0 in done:
                continue
            comp, st = {p0}, [p0]
            while st:
                a = st.pop()
                for dx, dy in N4:
                    b = (a[0] + dx, a[1] + dy)
                    if b in un and b not in comp:
                        comp.add(b)
                        st.append(b)
            done |= comp
            area0 = m.get(*p0).apath
            best = None
            for p in comp:
                for dx, dy in N4:
                    w, q = (p[0] + dx, p[1] + dy), (p[0] + 2 * dx, p[1] + 2 * dy)
                    tw, tq = m.get(*w), m.get(*q)
                    if tw is None or tq is None or q not in seen or not tw.tpath.startswith("/turf/closed/wall") \
                            or tw.objs:
                        continue
                    side = [m.get(w[0] + dy, w[1] + dx), m.get(w[0] - dy, w[1] - dx)]
                    if not all(s is not None and s.tpath.startswith("/turf/closed") for s in side):
                        continue
                    g = tq.apath
                    rank = 0 if g == area0 else 1 if _group(g) == _group(area0) else 2 if g.startswith("/area/hallway") \
                        else 3 if g.startswith("/area/maintenance") else 4
                    sc = (rank + (2 if "r_wall" in tw.tpath else 0), w)
                    if best is None or sc < best[0]:
                        best = (sc, w, area0, g)
            if best:
                _, w, a0, g = best
                maint = g.startswith("/area/maintenance") or a0.startswith("/area/maintenance")
                m.set(w[0], w[1], dmm.Tile([dmm.Atom("/obj/machinery/door/airlock/maintenance" if maint
                                                     else "/obj/machinery/door/airlock")],
                                           dmm.Atom("/turf/open/floor/plating" if maint else "/turf/open/floor/plasteel"),
                                           dmm.Atom(a0)))
                n_cut += 1
                seen = reach(m)
        cut += n_cut
        if not n_moved and not n_cut:
            break
        if len(reach(m)) <= before and not n_cut:
            break
    low = cut_off(m)
    log("walkfix: %d firedoors opened, %d dense things moved off door fronts, %d doors cut; %d areas under %d%% "
        "walkable: %s" % (opened, moved, cut, len(low), LOW * 100, ", ".join(a.replace("/area/", "") for a in low[:12])))
    return low


if __name__ == "__main__":
    m_ = dmm.read(os.path.join(parse.ROOT, "data", "mapforge", sys.argv[1] + ".dmm"))
    for a, (r, n) in sorted(measure(m_).items(), key=lambda kv: kv[1][0] / float(kv[1][1])):
        if r < LOW * n and n >= 6:
            print("%.2f %s %d/%d" % (r / float(n), a, r, n))
