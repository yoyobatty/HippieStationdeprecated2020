"""Stage S5 (plan M3): what a generated station needs to run, on a built map, the v6 passes lifted with their
coordinates found instead of fixed:

    from gen import net
    net.engine(m, L, log)        # after compose.finish, before dress: MetaStation's supermatter block against
                                 # engineering's outer wall (the room stage copies no engine)
    net.outside(m, L, log)       # then the docks (escape, arrivals, cargo, mining) and four solar arrays
    net.networks(m, log)         # after dress and connect: power, air (chambers + the atmos works), disposals

The v6 passes (station/v6_station.py) are used read-only; where one needs a place (the SMES row, the gas chambers'
side), this module works it out from the map and hands it over.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", "station"))
from forge import dmm, furnish  # noqa: E402

N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
N8 = [(dx, dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy]
SPACE = "/turf/open/space"
ENG_AREA = "/area/engine/engineering"
RWALL = "/turf/closed/wall/r_wall"
# what the last engine/outside/networks run managed, for the build's checks (net_checks)
REPORT = {}
PAD = 32            # map margin while placing things out in space (the engine's coil reaches 25 past engineering)
MARGIN = 10         # the margin a finished map keeps round its outermost non-space tile (blocks.Layout.paint's)


def _engine_rooms(m, k, o, walk, rd, uw, L, log):
    """The rooms on the far side of the engine's main floor: an inner wall line at u -walk-1 with their doors, the
    strip u uw+1..-walk-2 cut in three along v 1..17 (their order and lengths by the layout's seed). Returns the
    door fronts on the main floor (kept clear)."""
    import random
    r = random.Random("engine rooms|%s" % getattr(L, "salt", ""))
    ui = -walk - 1                                   # the inner wall line
    at = lambda u, v: _at(o, k, u, v)                # noqa: E731
    ar = ENG_AREA

    def put(u, v, path, vs=()):
        a = dmm.Atom(path, list(vs))
        _rot_atom(a, k)
        m.get(*at(u, v)).objs.append(a)

    def tile(u, v, objs, turf):
        q = at(u, v)
        # the waste line and cables already laid through here stay under the new wall or door
        under = [x for x in m.get(*q).objs if x.path.startswith(("/obj/machinery/atmospherics/pipe", "/obj/structure/cable"))]
        m.set(q[0], q[1], dmm.Tile(under + objs, dmm.Atom(turf), dmm.Atom(ar)))
    lens = r.choice(((5, 6, 4), (4, 7, 4), (4, 6, 5)))
    kinds = ["monitor", "secure", "gas"]
    lens = dict(zip(kinds, lens))
    r.shuffle(kinds)
    for v in range(1, 18):
        tile(ui, v, [], "/turf/closed/wall")
    fronts = set()
    v0 = 1
    made = []
    for i, kind in enumerate(kinds):
        ln = lens[kind] if i < 2 else 17 - v0 + 1
        v1 = v0 + ln - 1
        if i < 2:
            for u in range(uw + 1, ui):
                tile(u, v1 + 1, [], "/turf/closed/wall")
        vd = (v0 + v1) // 2
        cells = [(u, v) for u in range(uw + 1, ui) for v in range(v0, v1 + 1)]
        fronts.add(at(ui + 1, vd))
        order = sorted((c for c in cells if c[1] != vd), key=lambda c: (c[0], abs(c[1] - vd), c[1]))
        if kind == "secure":
            for u, v in cells:
                m.get(*at(u, v)).turf = dmm.Atom("/turf/open/floor/plasteel/dark")
            tile(ui, vd, [dmm.Atom("/obj/machinery/door/poddoor", [("id", '"engsecure"'), ("name", '"Secure Storage"')])],
                 "/turf/open/floor/plasteel/dark")
            put(ui + 1, vd + 1, "/obj/machinery/button/door", [("id", '"engsecure"'), ("name", '"Engineering Secure Storage"'),
                                                               ("req_access_txt", '"11"'), ("pixel_x", "-24")])
            # packed in rows from the outer wall, the row in from the blast door left as the aisle (Meta, Box, Delta)
            queue = ["/obj/machinery/power/emitter"] * 4 + ["/obj/machinery/field/generator"] * 5 + [
                "/obj/machinery/shieldgen"] * 4 + ["/obj/machinery/power/port_gen/pacman"]
            for (u, v), path in zip(order, queue):
                put(u, v, path, [("dir", "4")] if path.endswith("emitter") else [])
        elif kind == "monitor":
            tile(ui, vd, [dmm.Atom("/obj/machinery/door/firedoor"), dmm.Atom(
                "/obj/machinery/door/airlock/engineering/glass", [("name", '"Engine Monitoring"'), ("req_access_txt", '"10"')])],
                "/turf/open/floor/plasteel")
            for v in range(v0, v1 + 1):
                if v != vd:                         # it looks onto the floor and the core through glass
                    tile(ui, v, [dmm.Atom("/obj/effect/spawner/structure/window/reinforced")], "/turf/open/floor/plating")
            cons = ["/obj/machinery/computer/station_alert", "/obj/machinery/computer/monitor", "/obj/machinery/computer/atmos_alert"]
            for v, path in zip(range(v0, v1 + 1), cons):
                put(uw + 1, v, path, [("dir", "4")])
                put(uw + 2, v, "/obj/structure/chair/office/light", [("dir", "8")])
            put(ui - 1, v1, "/obj/structure/table")
            put(ui - 1, v1, "/obj/item/geiger_counter")
            put(ui - 1, v1, "/obj/item/clothing/glasses/meson/engine")
            put(uw + 1, v1, "/obj/structure/filingcabinet/chestdrawer")
        else:
            tile(ui, vd, [dmm.Atom("/obj/machinery/door/firedoor"), dmm.Atom(
                "/obj/machinery/door/airlock/engineering", [("name", '"Engine Gas Storage"'), ("req_access_txt", '"10"')])],
                "/turf/open/floor/plasteel")
            for u, v in cells:
                m.get(*at(u, v)).turf = dmm.Atom("/turf/open/floor/plasteel/dark")
            cans = ["/obj/machinery/portable_atmospherics/canister/nitrogen"] * 3 + [
                "/obj/machinery/portable_atmospherics/canister/carbon_dioxide",
                "/obj/machinery/portable_atmospherics/canister/toxins", "/obj/machinery/portable_atmospherics/pump",
                "/obj/machinery/portable_atmospherics/scrubber"]
            for (u, v), path in zip(order, cans):
                put(u, v, path)
        made.append("%s %dx%d" % (kind, rd, ln))
        v0 = v1 + 2
    log("engine: rooms on the main floor's far side: %s" % ", ".join(made))
    return fronts


def _engine_floor(m, k, o, uw, log, fronts=()):
    """Meta's engineering floor down the core's side (u -4..-1, v 1..14 of to_dmm.META_ENGINE): the core's three
    airlocks open on it there, as they do here now. Its standing pieces and what lies on them come along, turned with
    the block (tables with mesons, insulated gloves, belts and pipe dispensers, cones, the PACMAN, the cell charger, the
    engineers' start points); its lights, alarms, vents and wall pieces are the builder's. Meta's doors on its far side
    (SMES room, secure storage) are this room's wall."""
    import to_dmm as T
    x0, y0 = T.META_ENGINE
    meta = _meta()
    took = 0
    for u in range(uw + 1, 0):
        for v in range(1, 15):
            src = meta.tiles.get((x0 + u, y0 + v, 1))
            dst = m.get(*_at(o, k, u, v))
            if src is None or dst is None or not src.tpath.startswith("/turf/open") or src.tpath.startswith("/turf/open/space"):
                continue
            objs = [a.copy() for a in src.objs if a.path.startswith(FLOOR_KEEP)
                    and not a.path.startswith(FLOOR_SKIP)]
            if not objs or _at(o, k, u, v) in fronts:
                continue
            for a in objs:
                _rot_atom(a, k)
            dst.objs.extend(objs)
            took += len(objs)
    log("engine: Meta's engineering floor down the core's side, %d wide, %d pieces" % (-uw - 1, took))


FLOOR_KEEP = ("/obj/structure/table", "/obj/item", "/obj/structure/closet", "/obj/machinery/vending",
              "/obj/machinery/power/port_gen", "/obj/machinery/cell_charger", "/obj/effect/landmark/start",
              "/obj/structure/rack", "/obj/item/twohanded/required/kirbyplants", "/obj/structure/reagent_dispensers")
FLOOR_SKIP = ("/obj/item/radio/intercom",)
_META = None


def _meta():
    global _META
    if _META is None:
        _META = dmm.read(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "_maps", "map_files",
                                      "MetaStation", "MetaStation.dmm"))
    return _META


def is_space(t):
    return t is None or (t.tpath.startswith(SPACE) and not t.objs)


# ------------------------------------------------------------------------------------------------ map margin
def pad(m, n, L=None):
    """n tiles of space added on every side (tiles shift by n; L.offset follows)."""
    tiles = {}
    for (x, y, z), t in m.tiles.items():
        tiles[(x + n, y + n, z)] = t
    m.tiles = tiles
    m.maxx += 2 * n
    m.maxy += 2 * n
    for x in range(1, m.maxx + 1):
        for y in range(1, m.maxy + 1):
            if (x, y, 1) not in m.tiles:
                m.tiles[(x, y, 1)] = dmm.Tile([], dmm.Atom("/turf/open/space/basic"), dmm.Atom("/area/space"))
    if L is not None and getattr(L, "offset", None):
        L.offset = (L.offset[0] + n, L.offset[1] + n)
    import v6_station as V6
    V6.SOLAR_NET = {(x + n, y + n) for (x, y) in V6.SOLAR_NET}


def crop(m, margin=MARGIN, L=None):
    """Back to `margin` tiles of space round everything that is not bare space."""
    used = [(x, y) for (x, y, z), t in m.tiles.items() if not (t.tpath.startswith(SPACE) and not t.objs
                                                               and t.apath in ("/area/space", ""))]
    x0, y0 = min(p[0] for p in used) - margin, min(p[1] for p in used) - margin
    x1, y1 = max(p[0] for p in used) + margin, max(p[1] for p in used) + margin
    tiles = {}
    for x in range(x0, x1 + 1):
        for y in range(y0, y1 + 1):
            t = m.tiles.get((x, y, 1)) or dmm.Tile([], dmm.Atom("/turf/open/space/basic"), dmm.Atom("/area/space"))
            tiles[(x - x0 + 1, y - y0 + 1, 1)] = t
    m.tiles = tiles
    m.maxx, m.maxy = x1 - x0 + 1, y1 - y0 + 1
    if L is not None and getattr(L, "offset", None):
        L.offset = (L.offset[0] - x0 + 1, L.offset[1] - y0 + 1)
    # tiles a pass remembered between calls move with the map (v6's SOLAR_NET: the solar rooms' cable, which power()
    # keeps; stale, it let power() strip the rooms' cable and every console lost its array, 2026-11-25)
    import v6_station as V6
    V6.SOLAR_NET = {(x - x0 + 1, y - y0 + 1) for (x, y) in V6.SOLAR_NET}
    return (1 - x0, 1 - y0)


# ------------------------------------------------------------------------------------------------ the engine
def _at(o, k, u, v):
    du, dv = furnish.rot_xy(u, v, k)
    return (o[0] + du, o[1] + dv)


def _eng_floor(m):
    """Engineering's floor (not atmos), by area: the tiles a door from the engine room may open onto."""
    out = set()
    for (x, y, z), t in m.tiles.items():
        a = t.apath
        if a.startswith("/area/engine") and not a.startswith(("/area/engine/atmos", "/area/engine/supermatter")) \
                and not t.tpath.startswith(("/turf/closed", SPACE)) and not t.has("/obj/machinery/door"):
            out.add((x, y))
    return out


def engine(m, L=None, log=print):
    """The block with Meta's engineering floor down the core's side (CTRL_W wide) and working rooms on that floor's far
    side (ROOM_D deep); else the floor alone; else the old 1-wide walkway."""
    for w, rd in ((CTRL_W, ROOM_D), (CTRL_W - 1, ROOM_D), (CTRL_W, 0), (1, 0)):
        r = _engine(m, L, log, w, rd)
        if r is not None or w == 1:
            return r
    return None


# Meta's engineering floor down the core's side, 4 wide: its three core airlocks open on it (the user 2026-11-26:
# "that walk way is a 1 by 1 which looks horrible ... the 3 airlocks have purpose in meta, the room it opens into has
# purpose, this is just a dead end hallway"); else the old 1-wide walkway
CTRL_W = 4
# and on that floor's far side the rooms that hold the engine inside the department, as Meta has its SMES room, secure
# storage and a store there (the user 2026-11-26: "it's still a little bit of a pointless hallway, many departments
# and areas of a map feel like they contribute to the structure of the space station itself"): Engine Monitoring,
# secure storage behind blast doors, the engine's gas store
ROOM_D = 3      # 3 deep: 5 needed a wider reserve than the layout search takes well (f33, f34)


def _engine(m, L=None, log=print, walk=1, rd=0):
    """MetaStation's supermatter block (station/to_dmm.engine_block: the crystal's chamber, the gas loop, the emitter
    room, the coil out in space) built against engineering's outer wall, in a room of its own:

        v 0         the hull wall the block brings (the coil lies in space past it, v -6..-1)
        v 1..14     the block's core; u -1 a walkway beside it, u -2 and 18 the side walls
        v 15..17    three rows in front (the freezers' loop closed in two of them, to_dmm's nook)
        v 18        engineering's own outer wall: one door through it from the walkway rows

    The site: every tile up to row 17 and the coil is space now and keeps a tile of space round it; row 18 is
    engineering's wall wherever a door can go. Of the sites, the one that grows the station's box least, then the one
    nearest engineering's SMES. Then the waste line (to_dmm.route_engine_waste) to the nearest hull and the paste
    (to_dmm.paste_engine). Returns the block's True, or None when no site was found."""
    import to_dmm as T
    cells = T.engine_block()
    pad(m, PAD, L)
    eng = _eng_floor(m)
    if not eng:
        log("engine: no engineering floor")
        crop(m, L=L)
        return None
    smes = [(x, y) for (x, y, z), t in m.tiles.items() if t.has("/obj/machinery/power/smes")
            and t.apath.startswith("/area/engine")] or sorted(eng)
    used = [(x, y) for (x, y, z), t in m.tiles.items() if not t.tpath.startswith(SPACE)]
    bx0, by0 = min(p[0] for p in used), min(p[1] for p in used)
    bx1, by1 = max(p[0] for p in used), max(p[1] for p in used)
    uw = -1 - walk - ((rd + 1) if rd else 0)     # the block's side wall beyond the floor (and the rooms past it)
    room_uv = [(u, v) for u in range(uw, 19) for v in range(0, 18)]
    back_uv = [(u, 18) for u in range(uw, 19)]
    coil_uv = [uv for uv in cells if uv[1] < 0]
    inner_uv = set(room_uv) | set(coil_uv)
    # candidate origins: put row 18 on each engineering wall tile that has engineering floor right behind it
    walls = set()
    for p in eng:
        for dx, dy in N4:
            w = (p[0] + dx, p[1] + dy)
            t = m.get(*w)
            if t is not None and t.tpath.startswith("/turf/closed") and not t.objs:
                walls.add((w, (-dx, -dy)))
    best = None
    tried = set()
    for (w, out) in sorted(walls):
        for k in range(4):
            # the v axis must point from the engine to engineering (row 18 the wall, row 19 the floor behind it)
            vx, vy = furnish.rot_xy(0, 1, k)
            if (vx, vy) != out:
                continue
            for u_door in range(uw + 1, 18):
                o = _at((0, 0), k, -u_door, -18)
                o = (w[0] + o[0], w[1] + o[1])
                if (o, k) in tried:
                    continue
                tried.add((o, k))
                at = {uv: _at(o, k, *uv) for uv in room_uv + back_uv + coil_uv}
                ok = True
                for uv in room_uv + coil_uv:
                    p = at[uv]
                    t = m.get(*p)
                    if t is None or not t.tpath.startswith(SPACE) or t.objs:
                        ok = False
                        break
                    if uv[1] <= 16:
                        # round the room: space, or a wall it can stand against (never floor, a door or glass)
                        for dx, dy in N8:
                            q = (p[0] + dx, p[1] + dy)
                            if q in at.values():
                                continue
                            tq = m.get(*q)
                            # maint running along the room's side walls is fine (the room brings its own walls at
                            # u -2 and 18; a 21-wide annex with maint both sides had NO SITE, 2026-11-25); the coil's
                            # ring stays space
                            maint_ok = uv[1] >= 0 and tq is not None and tq.apath.startswith("/area/maintenance")                                 and not tq.has("/obj/machinery/door") and not tq.tpath.startswith(SPACE)
                            if tq is None or not (tq.tpath.startswith(SPACE) or maint_ok or (
                                    tq.tpath.startswith("/turf/closed") and not tq.objs)):
                                ok = False
                                break
                    if not ok:
                        break
                if not ok:
                    continue
                if not all((m.get(*at[uv]) is not None and (m.get(*at[uv]).tpath.startswith(SPACE) or
                            (m.get(*at[uv]).tpath.startswith("/turf/closed") and not m.get(*at[uv]).has("/obj/machinery/door"))))
                           for uv in back_uv):
                    continue
                # (never into a side room: the door opens on the main floor or the rows in front of the core)
                doors = [uv for uv in back_uv if (-walk if rd else uw + 1) <= uv[0] <= 17 and m.get(*at[uv]).tpath.startswith("/turf/closed")
                         and _at(o, k, uv[0], 19) in eng]
                if not doors:
                    continue
                pts = [at[uv] for uv in room_uv + back_uv]
                nx0, ny0 = min([bx0] + [p[0] for p in pts]), min([by0] + [p[1] for p in pts])
                nx1, ny1 = max([bx1] + [p[0] for p in pts]), max([by1] + [p[1] for p in pts])
                grow = (nx1 - nx0 + 1) * (ny1 - ny0 + 1) / float((bx1 - bx0 + 1) * (by1 - by0 + 1))
                d0 = at[doors[len(doors) // 2]]
                near = min(abs(d0[0] - s[0]) + abs(d0[1] - s[1]) for s in smes)
                # no 1-wide gap of space left between the block's side walls and what stands beside it (f29: a 1x2
                # pocket of space sealed between the block's windows and Atmospherics' wall; the user: "this area
                # here looks weird"): the block abuts its neighbour or stands clear of it
                sliver = 0
                for v_ in range(0, 18):
                    for u1, u2 in ((uw - 1, uw - 2), (19, 20)):
                        t1, t2 = m.get(*_at(o, k, u1, v_)), m.get(*_at(o, k, u2, v_))
                        if t1 is not None and t1.tpath.startswith(SPACE) and t2 is not None and not t2.tpath.startswith(SPACE):
                            sliver += 1
                sc = (sliver, round(grow, 2), near)
                if best is None or sc < best[0]:
                    best = (sc, k, o, at, doors)
    REPORT["engine"] = False
    if best is None:
        log("engine: NO SITE against engineering's outer wall")
        crop(m, L=L)
        return None
    sc, k, o, at, doors = best
    # the room round the block: walls, the walkway and the rows in front, engineering's area
    ar = ENG_AREA
    for uv in room_uv + back_uv:
        p = at[uv]
        u, v = uv
        if uv in cells:
            continue
        if u in (uw, 18) or v in (0, 18):
            if v == 18 and m.get(*p).tpath.startswith("/turf/closed"):
                continue            # engineering's own wall stays as it is
            m.set(p[0], p[1], dmm.Tile([], dmm.Atom(RWALL), dmm.Atom(ar)))
        else:
            m.set(p[0], p[1], dmm.Tile([], dmm.Atom("/turf/open/floor/plasteel"), dmm.Atom(ar)))
    # one door: the middle one of the walkway rows' contacts, an engineering airlock
    du = sorted(doors, key=lambda uv: (abs(uv[0] - 8), uv))[0]
    dp = at[du]
    m.set(dp[0], dp[1], dmm.Tile([dmm.Atom("/obj/machinery/door/airlock/engineering", [("name", '"Supermatter Engine"')])],
                                 dmm.Atom("/turf/open/floor/plasteel"), dmm.Atom(ar)))
    room = [at[(u, v)] for u in range(uw + 1, 18) for v in range(1, 18)]
    wl = {at[uv] for uv in room_uv + back_uv if uv[0] in (uw, 18) or uv[1] in (0, 18)} - {dp}
    taken = {(x, y) for (x, y, z), t in m.tiles.items() if not t.tpath.startswith(SPACE)} - set(room) - wl
    place = (k, o, {uv: _at(o, k, *uv) for uv in list(cells) + [(u_, v) for u_ in range(uw + 1, 0) for v in range(18)] +
                    [(u, 17) for u in range(-1, 18)] + [(u, v) for u in range(-1, 18) for v in range(15, 18)]})
    waste = T.route_engine_waste(place, room, wl, {dp}, taken)
    if not waste:
        log("engine: no way out for the waste line")
        crop(m, L=L)
        return None
    for ln in T.paste_engine(m, place, waste, ar):
        log(ln)
    if walk > 1:
        fronts = _engine_rooms(m, k, o, walk, rd, uw, L, log) if rd else set()
        _engine_floor(m, k, o, -1 - walk, log, fronts)
    log("engine: room against engineering, door at %d,%d; box grows x%.2f, door %d tiles from an SMES%s" % (
        dp[0], dp[1], sc[1], sc[2], "; %d gap tiles beside it" % sc[0] if sc[0] else ""))
    REPORT["engine"] = True
    crop(m, L=L)
    return True


def _floor(t):
    return t is not None and t.tpath.startswith("/turf/open") and not t.tpath.startswith(SPACE)


def dedupe_apcs(m, log=print):
    """One APC an area, as on the stock maps: copied rooms of one area type each bring theirs (crew 80 seed 1: 14 areas
    with 2-4, 18 extra). The one nearest the area's middle stays."""
    by = {}
    for (x, y, z), t in m.tiles.items():
        if t.has("/obj/machinery/power/apc"):
            by.setdefault(t.apath, []).append((x, y))
    gone = 0
    for area, ps in by.items():
        if len(ps) < 2:
            continue
        tiles = [(x, y) for (x, y, z), t in m.tiles.items() if t.apath == area]
        cx = sum(p[0] for p in tiles) / float(len(tiles))
        cy = sum(p[1] for p in tiles) / float(len(tiles))
        ps.sort(key=lambda p: ((p[0] - cx) ** 2 + (p[1] - cy) ** 2, p))
        for p in ps[1:]:
            t = m.get(*p)
            t.objs = [o for o in t.objs if not o.path.startswith("/obj/machinery/power/apc")]
            gone += 1
    log("apc: %d extra APCs taken out (one an area)" % gone)
    return gone


def ensure_apc(m, area, log=print):
    """An APC for `area` when none of its tiles has one: on the wall face of a free floor tile, nearest the area's
    middle (the copied rooms bring their own; the engine room's area may have none)."""
    import v6_station as V6
    tiles = [(x, y) for (x, y, z), t in m.tiles.items() if t.apath == area and _floor(t)]
    if not tiles or any(m.get(*p).has("/obj/machinery/power/apc") for p in tiles):
        return False
    cx = sum(p[0] for p in tiles) / float(len(tiles))
    cy = sum(p[1] for p in tiles) / float(len(tiles))
    from forge import corpus as CO

    def hung(t):
        return any(CO.mounted(o) or (o.path.startswith("/obj/machinery/light") and not o.path.startswith(
            "/obj/machinery/light_switch")) or o.path.startswith(("/obj/machinery/door", "/obj/structure/window",
                                                                   "/obj/structure/grille")) for o in t.objs)
    faces = []
    # an empty tile's wall first; else any tile with nothing hung on it (a storage room full of racks had no empty
    # tile against a wall and no APC: dark and unpowered, 2026-11-25)
    for strict in (True, False):
        for p in tiles:
            t = m.get(*p)
            if (t.objs if strict else hung(t)):
                continue
            for d, (dx, dy) in ((1, (0, 1)), (2, (0, -1)), (4, (1, 0)), (8, (-1, 0))):
                w = m.get(p[0] + dx, p[1] + dy)
                if w is not None and w.tpath.startswith("/turf/closed") and not w.objs:
                    faces.append(((p[0] - cx) ** 2 + (p[1] - cy) ** 2, p, d))
        if faces:
            break
    if not faces:
        return False
    _, p, d = min(faces)
    V6.mount(m, p, d, "apc")
    log("apc: %s given one at %d,%d" % (area, p[0], p[1]))
    return True


# ------------------------------------------------------------------------------------------------ docks
# (name, the area the dock opens from, the airlock's name); ports and sizes are to_dmm.PORTS (Box's, so stock shuttle
# templates fit). Arrivals docks side-on (to_dmm.side_dock), the rest head-on with an arm (v6_station.docks' escape).
# Areas are tried in order, exact: a generated cargo may have no bay room (crew 80 seed 1: its corridor area is the
# biggest floor it has), so the corridor area takes the supply dock then.
DOCKS = (("escape", ("/area/hallway/secondary/exit",), "Escape Airlock", "emergency evac bay"),
         ("cargo", ("/area/quartermaster/storage", "/area/quartermaster", "/area/quartermaster/warehouse"),
          "Supply Dock Airlock", "Cargo Bay"),
         ("mining", ("/area/quartermaster/miningdock", "/area/quartermaster/miningoffice", "/area/quartermaster"),
          "Mining Dock Airlock", "mining shuttle bay"))
NEAR_DOCK = 15      # how far (Manhattan) from its department's rooms a cargo or mining dock may open off maint or a hall
ARM = 6             # the longest walled gangway out to a port: within 3 the shuttle rect met the station's ragged outline
                    # on every cargo and mining wall of crew 80 seed 1 (2026-11-25)
DIRN = {(0, 1): 1, (0, -1): 2, (1, 0): 4, (-1, 0): 8}


def _rect_tiles(q, dirn, w, dw, h):
    import to_dmm as T
    xa, ya, xb, yb = T.port_rect(q, dirn, w, dw, h)
    return {(x, y) for x in range(min(xa, xb), max(xa, xb) + 1) for y in range(min(ya, yb), max(ya, yb) + 1)}


GLASS = ("/obj/effect/spawner/structure/window", "/obj/structure/grille", "/obj/structure/window")


def _hullish(t):
    """A tile of the hull line: bare wall, or a window (the maint behind a department is glazed every other tile; with
    wall alone counted, the cargo bay of f43 found no run of hull behind it and its dock crossed maint)."""
    if t is None:
        return False
    if t.tpath.startswith("/turf/closed"):
        return not t.objs
    return bool(t.objs) and all(o.path.startswith(GLASS) for o in t.objs)


def _hull_cands(m, box, through=False, near=None):
    """Hull walls of an area: (wall, out, inner floor, the area's own wall or None), the wall in a straight wall run
    with space in front. through: the hull wall is maint's, across 1-3 tiles of maint from the area's own wall (a
    department maint fences on every side: cargo on crew 80 seed 1 had only wall, maint, wall, space)."""
    from forge import kit
    out = []
    for (x, y) in sorted(box):
        for sdv in N4:
            own = None
            wl = (x + sdv[0], y + sdv[1])
            if through:
                t1 = m.get(*wl)
                if t1 is None or not t1.tpath.startswith("/turf/closed") or t1.objs:
                    continue
                side1 = [(wl[0] + sdv[1], wl[1] + sdv[0]), (wl[0] - sdv[1], wl[1] - sdv[0])]
                if not all(m.get(*s_) is not None and m.get(*s_).tpath.startswith("/turf/closed") for s_ in side1):
                    continue
                own, ok = wl, False
                for i in range(1, 4):
                    q = (wl[0] + sdv[0] * i, wl[1] + sdv[1] * i)
                    tq = m.get(*q)
                    if not (_floor(tq) and tq.apath.startswith("/area/maintenance") and not tq.has("/obj/machinery/door")
                            and not kit.dense(tq.objs)):
                        break
                    nxt = (q[0] + sdv[0], q[1] + sdv[1])
                    tn = m.get(*nxt)
                    if _hullish(tn):
                        wl, ok = nxt, True
                        break
                if not ok:
                    continue
            fr = (wl[0] + sdv[0], wl[1] + sdv[1])
            tw, tf = m.get(*wl), m.get(*fr)
            if tf is None or not _hullish(tw):
                continue
            if not tf.tpath.startswith(SPACE) or tf.objs:
                continue
            side = [(wl[0] + sdv[1], wl[1] + sdv[0]), (wl[0] - sdv[1], wl[1] - sdv[0])]
            if not all(_hullish(m.get(*s)) or (m.get(*s) is not None and m.get(*s).tpath.startswith("/turf/closed"))
                       for s in side):
                continue
            out.append((wl, sdv, (x, y), own))
    if not out:
        return out
    cx, cy = near if near else (sum(p[0] for p in box) / float(len(box)), sum(p[1] for p in box) / float(len(box)))
    out.sort(key=lambda c: (abs(c[0][0] - cx) + abs(c[0][1] - cy), c[0]))
    return out


def head_dock(m, box, key, door_name, port_name, claimed, near=None, ways=(False, True)):
    """A head-on dock out of `box`: a hull wall of it with space in front, an arm of 0-ARM tiles out over space
    (walled both sides), the airlock at its end and the stationary port past that, its whole rect clear space and no
    station floor or other port's rect beside it (a wall beside it is fine). Shortest arm first, then the wall
    nearest the area's middle."""
    import to_dmm as T
    pid, w, dw, h, extra = T.PORTS[key]
    cands = [(c, k) for through in ways for k in range(0, ARM + 1) for c in _hull_cands(m, box, through, near)]
    for (dp, sdv, _, own), k in cands:
        if True:
            dirn = DIRN[sdv]
            arm = [(dp[0] + i * sdv[0], dp[1] + i * sdv[1]) for i in range(1, k + 1)]
            q = (dp[0] + (k + 1) * sdv[0], dp[1] + (k + 1) * sdv[1])
            if not all(m.get(*a) is not None and m.get(*a).tpath.startswith(SPACE) and not m.get(*a).objs for a in arm):
                continue
            # the arm's walls must land on space or wall, never on floor
            if any(_floor(m.get(a[0] + s_ * sdv[1], a[1] + s_ * sdv[0])) for a in arm for s_ in (1, -1)):
                continue
            rect = _rect_tiles(q, dirn, w, dw, h)
            ring = {(x + dx, y + dy) for (x, y) in rect for dx, dy in N8} - rect
            if any(m.get(*c) is None or not m.get(*c).tpath.startswith(SPACE) or m.get(*c).objs or c in claimed
                   for c in rect) or any(c in claimed or _floor(m.get(*c)) for c in ring - set(arm) - {dp}):
                continue
            inner = m.get(dp[0] - sdv[0], dp[1] - sdv[1])
            door_at = arm[-1] if arm else dp
            for a in [dp] + arm:
                m.set(a[0], a[1], dmm.Tile([], dmm.Atom(inner.turf.path, list(inner.turf.vars)), inner.area.copy()))
                for s_ in (1, -1):
                    f = (a[0] + s_ * sdv[1], a[1] + s_ * sdv[0])
                    if a != dp and m.get(*f) is not None and m.get(*f).tpath.startswith(SPACE):
                        m.set(f[0], f[1], dmm.Tile([], dmm.Atom(RWALL), inner.area.copy()))
            m.get(*door_at).objs = [dmm.Atom("/obj/machinery/door/airlock/external", [("name", '"%s"' % door_name)])]
            if own is not None:
                # across maint: the area's own wall takes a door onto the maint crossing
                ta = m.get(own[0] - sdv[0], own[1] - sdv[1])
                m.set(own[0], own[1], dmm.Tile([dmm.Atom("/obj/machinery/door/airlock/maintenance")],
                                               dmm.Atom("/turf/open/floor/plating"), ta.area.copy()))
            vs = [("dir", str(dirn)), ("dwidth", str(dw)), ("height", str(h)), ("id", '"%s"' % pid),
                  ("name", '"%s"' % port_name), ("width", str(w))]
            if extra:
                k_, v_ = extra.split(" = ", 1)
                vs.append((k_, v_))
            m.get(*q).objs.append(dmm.Atom("/obj/docking_port/stationary", vs))
            claimed |= rect | ring
            return "%s dock: airlock at %d,%d, port at %d,%d dir %d%s%s" % (
                key, door_at[0], door_at[1], q[0], q[1], dirn, (", %d-tile arm" % k) if k else "",
                ", across maint from %d,%d" % own if own else "")
    return None


# Box's supply dock (BoxStation.dmm x 69-78, y 114-120; the port at 68,116 faces west), in block coordinates: u in
# from the outer airlocks (0 the outer doors, 1 the lock chambers, 2 the bay's hull wall line with the inner doors,
# 3+ the bay), v along the wall from the port's row. Rows -1 and 3 are the conveyor lanes (blast door, plastic flaps,
# blast door), rows 0 and 2 the two cycling airlocks, windows between and at both ends. Every stock bay has it (8 maps
# of 8: 11-17 belts, 2 flaps, studies/dept_specs/science_cargo.md); the generator's dock was one airlock in the wall.
STRIP_AT = (69, 116)
STRIP_V = (-2, 4)
STRIP_LANE = 7          # belts of the lane into the bay (u 3-9 on Box), fewer in a shallower bay
STRIP_IN = ("/obj/machinery/conveyor", "/obj/machinery/button/door")      # what the bay's own tiles take from Box
STRIP_K = {(-1, 0): 0, (0, 1): 1, (1, 0): 2, (0, -1): 3}      # out of the hull -> quarter turns clockwise of Box's
_STRIP = None


def _supply_strip():
    """{(u, v): Tile} of the strip's own tiles (u 0-2) and {(u, v): [atoms]} of what the bay's tiles take."""
    global _STRIP
    if _STRIP is None:
        from forge import corpus as CO_
        bm = dmm.read(os.path.join(CO_.ROOT, "_maps", "map_files", "BoxStation", "BoxStation.dmm"))
        own, bay = {}, {}
        for u in range(0, 3 + STRIP_LANE):
            for v in range(STRIP_V[0], STRIP_V[1] + 1):
                t = bm.get(STRIP_AT[0] + u, STRIP_AT[1] + v)
                if u <= 2:
                    t = t.copy()
                    t.objs = [o for o in t.objs if not o.path.startswith((
                        "/obj/structure/cable", "/obj/machinery/atmospherics", "/obj/structure/disposalpipe",
                        "/obj/effect/turf_decal", "/obj/machinery/light", "/obj/machinery/status_display"))]
                    own[(u, v)] = t
                else:
                    objs = [o for o in t.objs if o.path.startswith(STRIP_IN)]
                    if objs:
                        bay[(u, v)] = objs
        _STRIP = (own, bay)
    return _STRIP


TO_HULL_MIN = 9         # tiles of bay wall with maint and the hull behind them, at least (the dock strip's 7 and an end each)
TO_HULL_MAINT = 3       # the maint corridor between is at most this wide
TO_HULL_ROOM = 5        # a room with a head-on dock: 3 tiles of its wall and an end each


def bay_to_hull(m, box, log=print, least=TO_HULL_MIN, what="cargo bay", accept=None):
    """The cargo bay out to the hull where only a maint corridor lies between its wall and the hull wall: the wall and
    the corridor's tiles behind it become the bay's floor, and the corridor is shut at both ends with a maintenance
    airlock into the bay (stock bays: maint doors on 6 maps of 8, the supply dock through maint on none; maint fenced
    cargo's far side on crew 100 seed 7 and the shuttle docked across it, f38 round 0). The longest such run of wall
    is taken. accept: called once the tiles are changed; a falsy answer puts them back and the next longest run is
    tried (the mining dock room took the wall its shuttle had no room at, f39 round 0). Returns the tiles the bay
    gained."""
    from forge import corpus as CO_, function as FN

    def wall(t):
        return t is not None and t.tpath.startswith("/turf/closed")

    def maint(t):
        return _floor(t) and t.apath.startswith("/area/maintenance") and not t.has("/obj/machinery/door")

    def depth(c, sdv):
        """How many maint tiles lie behind the bay's wall at floor tile c (then the hull wall, then space), or 0."""
        if c not in box:
            return 0
        w1 = (c[0] + sdv[0], c[1] + sdv[1])
        if not wall(m.get(*w1)):
            return 0
        for k in range(1, TO_HULL_MAINT + 2):
            q = (w1[0] + sdv[0] * k, w1[1] + sdv[1] * k)
            tq = m.get(*q)
            if maint(tq):
                continue
            o = m.get(q[0] + sdv[0], q[1] + sdv[1])
            if k > 1 and _hullish(tq) and o is not None and o.tpath.startswith(SPACE):
                return k - 1
            return 0
        return 0
    runs = []
    for sdv in N4:
        al = (abs(sdv[1]), abs(sdv[0]))
        done = set()
        for c in sorted(box):
            k = depth(c, sdv)
            if not k or c in done:
                continue
            run = [c]
            for sg in (1, -1):
                q = (c[0] + sg * al[0], c[1] + sg * al[1])
                while depth(q, sdv) == k:
                    run.append(q)
                    q = (q[0] + sg * al[0], q[1] + sg * al[1])
            run.sort()
            done |= set(run)
            if len(run) >= least:
                runs.append((run, sdv, k))
    runs.sort(key=lambda t: (-len(t[0]), t[0][0], t[1]))
    for run, sdv, k in runs:
        old = {}
        for c in run:
            for j in range(0, k + 2):
                q = (c[0] + sdv[0] * j, c[1] + sdv[1] * j)
                tq = m.get(*q)
                old[q] = dmm.Tile(list(tq.objs), tq.turf, tq.area)
        gained = _to_hull_run(m, run, sdv, k, maint)
        if accept is None or accept():
            log("docks: the %s out to the hull over %d tiles of maint (%d of wall, the corridor %d wide), a maint "
                "airlock at each end" % (what, len(gained), len(run) - 2, k))
            return gained
        for q, tq in old.items():
            m.set(q[0], q[1], tq)
    return set()


def _to_hull_run(m, run, sdv, k, maint):
    """bay_to_hull's change for one run of wall. Returns the tiles gained."""
    from forge import corpus as CO_, function as FN
    al = (abs(sdv[1]), abs(sdv[0]))
    inner = m.get(*run[len(run) // 2])
    gained = set()
    for i, c in enumerate(run):
        behind = [(c[0] + sdv[0] * j, c[1] + sdv[1] * j) for j in range(1, k + 2)]      # the bay's wall, the maint
        if 0 < i < len(run) - 1:
            # what hung on the wall that goes (lights, alarms: the fixtures pass hangs the room's again)
            tc = m.get(*c)
            tc.objs = [o for o in tc.objs if not CO_.mounted(o)]
            for q in behind:
                tq = m.get(*q)
                keep = [o for o in tq.objs if o.path.startswith(("/obj/structure/cable", "/obj/machinery/atmospherics",
                                                                 "/obj/structure/disposalpipe"))]
                m.set(q[0], q[1], dmm.Tile(keep, dmm.Atom(inner.turf.path, list(inner.turf.vars)), inner.area.copy()))
                gained.add(q)
            continue
        # an end of the run: the corridor shut, a maintenance airlock where it goes on past the end
        sg = -1 if i == 0 else 1
        cells = behind[1:]
        door = cells[len(cells) // 2]
        past = m.get(door[0] + sg * al[0], door[1] + sg * al[1])
        for q in cells:
            tq = m.get(*q)
            keep = [o for o in tq.objs if o.path.startswith(("/obj/structure/cable", "/obj/machinery/atmospherics",
                                                             "/obj/structure/disposalpipe"))]
            if q == door and maint(past):
                m.set(q[0], q[1], dmm.Tile(keep + [dmm.Atom("/obj/machinery/door/airlock/maintenance")],
                                           dmm.Atom("/turf/open/floor/plating"), inner.area.copy()))
            else:
                m.set(q[0], q[1], dmm.Tile(keep, dmm.Atom("/turf/closed/wall"), tq.area.copy()))
    # nothing of the bay's left standing in the old wall line's way
    for q in gained:
        tq = m.get(*q)
        tq.objs = [o for o in tq.objs if not FN.is_dense(o)]
    return gained


class _Shadow(object):
    """A map that reads through to m and keeps its writes to itself: head_dock on it is a dry run. Tiles it hands out
    are copies, so changes to their objs stay here too. Its `tiles` is its own dict (m's, then its writes), so a pass
    that lists tiles (_tiles_of) sees what it changed."""

    def __init__(self, m, snap):
        self.m, self.snap = m, snap
        self.tiles = dict(m.tiles)
        for (x, y), t in snap.items():
            self.tiles[(x, y, 1)] = t

    def get(self, x, y, z=1):
        if (x, y) in self.snap:
            return self.snap[(x, y)]
        t = self.tiles.get((x, y, z))
        if t is None:
            return None
        c = dmm.Tile(list(t.objs), t.turf, t.area)
        self.snap[(x, y)] = c
        self.tiles[(x, y, z)] = c
        return c

    def set(self, x, y, t, z=1):
        self.snap[(x, y)] = t
        self.tiles[(x, y, z)] = t


def strip_fits(m):
    """True when Box's supply dock strip goes on the cargo bay as the map stands (its own hull wall, or after the bay
    takes the maint behind it), False when it doesn't, None with no bay. A dry run: m is not changed. The block
    search (gen/build.py measure) asks it so the layout leaves the bay's outside clear: on crew 100 seed 7 f47-f49
    another department stood at the bay's corner and the shuttle's 12 x 7 rect missed by one tile."""
    bay = "/area/quartermaster/storage"
    box = _tiles_of(m, bay, exact=True)
    if not box:
        return None
    if supply_dock(_Shadow(m, {}), box, "Supply Dock Airlock", "Cargo Bay", set()) is not None:
        return True
    m2 = _Shadow(m, {})

    def ok():
        return supply_dock(_Shadow(m2, dict(m2.snap)), _tiles_of(m2, bay, exact=True), "Supply Dock Airlock",
                           "Cargo Bay", set()) is not None
    return bool(bay_to_hull(m2, box, lambda s_: None, accept=ok))


def supply_dock(m, box, door_name, port_name, claimed):
    """Box's supply dock on a hull wall of the cargo bay `box`: 7 tiles of straight wall with space in front and the
    bay's floor behind, the two lock chambers out over space, the port past them with its rect clear. The belts of
    the lane into the bay stop a tile short of what stands in their way (wall or the bay's end). Returns the log
    note, or None when no wall of the bay takes it."""
    import to_dmm as T
    from forge import furnish, function as FN
    pid, w_, dw, h, extra = T.PORTS["cargo"]
    own, bay = _supply_strip()
    v0, v1 = STRIP_V
    for wl, sdv, _, _ in _hull_cands(m, box):
        k = STRIP_K[sdv]

        def at(u, v):
            rx, ry = furnish.rot_xy(u - 2, v, k)
            return (wl[0] + rx, wl[1] + ry)
        ok = True
        for v in range(v0, v1 + 1):
            if not _hullish(m.get(*at(2, v))):
                ok = False
            for u in (0, 1):
                ts = m.get(*at(u, v))
                if ts is None or not ts.tpath.startswith(SPACE) or ts.objs or at(u, v) in claimed:
                    ok = False
        if not ok or any(at(3, v) not in box for v in range(v0 + 1, v1)):
            continue
        strip = {at(u, v) for u in (0, 1, 2) for v in range(v0, v1 + 1)}
        q = at(-1, 0)
        dirn = DIRN[sdv]
        rect = _rect_tiles(q, dirn, w_, dw, h)
        ring = {(x + dx, y + dy) for (x, y) in rect for dx, dy in N8} - rect
        if any(m.get(*c) is None or not m.get(*c).tpath.startswith(SPACE) or m.get(*c).objs or c in claimed
               for c in rect) or any(c in claimed or _floor(m.get(*c)) for c in ring - strip):
            continue
        # the lane into the bay: belts while the bay's floor runs on
        lane = 0
        while lane < STRIP_LANE and at(3 + lane + 1, -1) in box:
            lane += 1
        if lane < 2:
            continue
        inner = m.get(*at(3, 0))
        for (u, v), t in own.items():
            c = at(u, v)
            nt = t.copy()
            nt.objs = [T.rot_engine_atom(o, k) for o in nt.objs]
            for o in nt.objs:
                if o.path.startswith("/obj/machinery/door/airlock/external"):
                    o.vars = [(n_, v_) for n_, v_ in o.vars if n_ != "name"] + [("name", '"%s"' % door_name)]
            nt.area = inner.area.copy()
            m.set(c[0], c[1], nt)
        for (u, v), objs in bay.items():
            if v == -1 and u - 3 >= lane:
                continue
            c = at(u, v)
            if c not in box:
                continue
            tb = m.get(*c)
            # the bay's own pieces off the lanes and the buttons' tile (pipes, cables and wall mounts stay)
            tb.objs = [o for o in tb.objs if not FN.is_dense(o)]
            tb.objs.extend(T.rot_engine_atom(o, k) for o in objs)
        for v in (0, 2):
            tb = m.get(*at(3, v))               # the floor before each inner airlock
            tb.objs = [o for o in tb.objs if not FN.is_dense(o)]
        vs = [("dir", str(dirn)), ("dwidth", str(dw)), ("height", str(h)), ("id", '"%s"' % pid),
              ("name", '"%s"' % port_name), ("width", str(w_))]
        m.get(*q).objs.append(dmm.Atom("/obj/docking_port/stationary", vs))
        claimed |= rect | ring
        return "cargo dock: Box's dock strip on the bay's hull wall at %d,%d, port at %d,%d dir %d, %d belts in" % (
            wl[0], wl[1], q[0], q[1], dirn, lane)
    return None


def docks(m, log=print):
    """Arrivals (side-on, the donut shuttle), escape, cargo and mining. Returns the tiles the ports' rects claim."""
    import to_dmm as T
    claimed = set()
    entry = _tiles_of(m, "/area/hallway/secondary/entry")
    note = None
    if entry:
        pid, w, dw, h, extra = T.PORTS["arrivals"]
        for dp, sdv, _, _ in _hull_cands(m, entry):
            t = m.get(*dp)
            saved = (t.turf, list(t.objs), t.area)
            t.turf = dmm.Atom("/turf/open/floor/plating")
            t.objs = [dmm.Atom("/obj/machinery/door/airlock/external", [("name", '"Arrival Airlock"')])]
            note = T.side_dock(m, dp, sdv, pid, w, dw, h, extra)
            if note:
                break
            t.turf, t.objs, t.area = saved
    log("docks: %s" % (note or "arrivals: NO room for the shuttle"))
    REPORT["docks_missing"] = [] if note else ["arrivals"]
    for (x, y, z), t in m.tiles.items():
        for o in t.objs:
            if o.path == "/obj/docking_port/stationary" and o.get("id") == '"arrivals_stationary"':
                rect = _rect_tiles((x, y), int(o.get("dir")), int(o.get("width")), int(o.get("dwidth")),
                                   int(o.get("height")))
                claimed |= rect | {(a + dx, b + dy) for (a, b) in rect for dx, dy in N8}
    for key, areas, door, pname in DOCKS:
        note = None
        if key == "cargo":
            box = _tiles_of(m, areas[0], exact=True)
            note = supply_dock(m, box, door, pname, claimed) if box else None
            if box and not note:
                # no wall of the bay takes the strip: the bay out to the hull along the run of wall the strip fits
                # past; else, with no hull wall at all, along the longest (a head-on dock into the bay at least)
                def strip_fits():
                    return supply_dock(_Shadow(m, {}), _tiles_of(m, areas[0], exact=True), door, pname,
                                       set(claimed)) is not None
                if bay_to_hull(m, box, log, accept=strip_fits) or (not _hull_cands(m, box) and bay_to_hull(m, box, log)):
                    box = _tiles_of(m, areas[0], exact=True)
                    note = supply_dock(m, box, door, pname, claimed)
                else:
                    log("docks: the cargo bay has no hull wall for the dock strip and no maint behind it to take")
        if key == "mining":
            # the mining shuttle's room likewise (stock: into the dock room on 8 maps of 8, never across maint)
            for area in areas[:2]:
                box = _tiles_of(m, area, exact=True)
                if not box:
                    continue

                def fits(area=area):
                    # a dry run: the shuttle docks head-on out of the room as it is now, not across maint
                    return head_dock(_Shadow(m, {}), _tiles_of(m, area, exact=True), key, door, pname, set(claimed),
                                     ways=(False,)) is not None
                # (a hull wall of its own is not enough: f48's mining dock room had one the shuttle had no room at,
                # and the dock went across maint from the corridor; "C2 mining: opens into nothing")
                if fits() or bay_to_hull(m, box, log, TO_HULL_ROOM, "mining dock room", accept=fits):
                    break
        for area in areas:
            if note:
                break
            box = _tiles_of(m, area, exact=True)
            note = head_dock(m, box, key, door, pname, claimed) if box else None
            if note:
                note += " (%s)" % area
                break
        if not note:
            # the department in a notch of the outline (every gangway out ran into other station floor on crew 80
            # seed 1): its other rooms, then the maint and halls round it, nearest its own rooms first
            own = set().union(*[_tiles_of(m, a, exact=True) for a in areas])
            if own:
                near = (sum(p[0] for p in own) / float(len(own)), sum(p[1] for p in own) / float(len(own)))
                group = _tiles_of(m, areas[0].rsplit("/", 1)[0]) | own
                round_ = {(x, y) for (x, y, z), t in m.tiles.items() if _floor(t) and t.apath.startswith(
                    ("/area/maintenance", "/area/hallway")) and not t.apath.startswith("/area/maintenance/solars")
                    and not t.has("/obj/machinery/door")
                    and min(abs(x - p[0]) + abs(y - p[1]) for p in own) <= NEAR_DOCK} if len(own) < 2000 else set()
                for label, box in (("its department", group), ("maint and halls near it", round_)):
                    note = head_dock(m, box, key, door, pname, claimed, near) if box else None
                    if note:
                        note += " (%s)" % label
                        break
        log("docks: %s" % (note or "%s: NO room for the shuttle (%s)" % (key, ", ".join(areas))))
        if not note:
            REPORT["docks_missing"].append(key)
    return claimed


def _tiles_of(m, prefix, exact=False):
    return {(x, y) for (x, y, z), t in m.tiles.items() if (t.apath == prefix if exact else t.apath.startswith(prefix))
            and _floor(t) and not t.has("/obj/machinery/door")}


# ------------------------------------------------------------------------------------------------ solars
SOLAR_SUB = {"NW": "port/fore", "NE": "starboard/fore", "SE": "starboard/aft", "SW": "port/aft"}
SOLAR_WORD = {"NW": "fore", "NE": "starboard", "SE": "aft", "SW": "port"}
FIELD = 9           # the array: 9x9 (v6's), panels in rows of 9 between catwalk rows, the tracker in the middle


def solars(m, log=print, claimed=frozenset()):
    """A solar array per corner of the station's box, as v6_station.solars builds them (the stock pattern): a solar
    maint room on the hull (v6_station._solar_room: SMES, terminal, console, APC, a door into maint, a cycling airlock
    pair), an open catwalk over space to a 9x9 field. The room goes by the maint tile nearest the corner that takes
    one; the field at the nearest clear spot out past the room's airlocks."""
    import v6_station as V6
    V6.SOLAR_NET.clear()
    used = [(x, y) for (x, y, z), t in m.tiles.items() if not (t.tpath.startswith(SPACE) and not t.objs)]
    bx0, by0 = min(p[0] for p in used), min(p[1] for p in used)
    bx1, by1 = max(p[0] for p in used), max(p[1] for p in used)
    maint = [(x, y) for (x, y, z), t in m.tiles.items() if t.apath.startswith("/area/maintenance") and _floor(t)
             and "/solars" not in t.apath and not t.has("/obj/machinery/door")]
    claimed = set(claimed)
    built = 0
    for key in ("NW", "NE", "SE", "SW"):
        corner = (bx0 if key[1] == "W" else bx1, by1 if key[0] == "N" else by0)
        diag = (-1 if key[1] == "W" else 1, 1 if key[0] == "N" else -1)
        far = (corner[0] + 12 * diag[0], corner[1] + 12 * diag[1])
        P, field, any_room = None, None, False
        for c in sorted(maint, key=lambda p: (abs(p[0] - corner[0]) + abs(p[1] - corner[1]), p))[:60]:
            P = V6._solar_room(m, [c], [far], claimed)
            if not P:
                continue
            any_room = True
            # the nearest field a catwalk reaches from this room's airlock; else the next room spot
            field = next((f for f in _field_site(m, P, claimed, every=True) if _catwalk(m, P, f, claimed)), None)
            if field is not None:
                break
            P = None
        if P is None:
            log("solars %s: %s" % (key, "no field a catwalk reaches from any room spot" if any_room
                                   else "no room spot by the maint near the corner"))
            continue
        _build_solar(m, key, P, field, claimed, log)
        built += 1
    log("solars: %d arrays" % built)
    REPORT["solars"] = built
    return built


def _field_site(m, P, claimed, every=False):
    """The field's corner (x0, y0): out past the outer airlock (P["c0"]) along the room's way out, then sideways,
    nearest first; the field and two tiles round it clear space, never claimed. every: all such corners, nearest
    first (solars() takes the first a catwalk reaches)."""
    import v6_station as V6
    out = {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0)}[P["out"]]
    perp = (out[1], out[0])
    c0 = P["c0"]
    room = set(P["inner"]) | set(P["ring"]) | set(P["flank"]) | {P["a1"], P["v"], P["a2"]}
    found = []
    for t in range(3, 22):
        for s in range(-8, 9):
            cx, cy = c0[0] + out[0] * (t + FIELD // 2) + perp[0] * s, c0[1] + out[1] * (t + FIELD // 2) + perp[1] * s
            x0, y0 = cx - FIELD // 2, cy - FIELD // 2
            box = [(x, y) for x in range(x0 - 2, x0 + FIELD + 2) for y in range(y0 - 2, y0 + FIELD + 2)]
            if all(m.get(*c) is not None and m.get(*c).tpath.startswith(SPACE) and not m.get(*c).objs
                   and c not in claimed and c not in room for c in box):
                found.append(((t + abs(s), t, s), (x0, y0)))
        if found and not every:
            break
    found.sort()
    if every:
        return [f for _, f in found]
    return found[0][1] if found else None


def _catwalk(m, P, field0, claimed):
    """The catwalk's tiles from the outer airlock to the field's ring (shortest run over open space), or None when
    nothing reaches it (crew 100 seed 7's NW array: built with no catwalk, its 81 tiles cut off, 2026-11-26)."""
    import v6_station as V6
    from forge.kit import CARD
    nb = V6.nb
    x0, y0 = field0
    x1, y1 = x0 + FIELD - 1, y0 + FIELD - 1
    field = {(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)}
    ring = [(x, y) for x in range(x0 - 1, x1 + 2) for y in (y0 - 1, y1 + 1)] +            [(x, y) for y in range(y0, y1 + 1) for x in (x0 - 1, x1 + 1)]
    blocked = set(P["inner"]) | set(P["ring"]) | set(P["flank"]) | {P["a1"], P["v"], P["a2"]} | set(claimed)
    ringset = set(ring) - {(x0 - 1, y0 - 1), (x1 + 1, y0 - 1), (x0 - 1, y1 + 1), (x1 + 1, y1 + 1)}

    def free(c):
        t = m.get(*c)
        return t is not None and (t.tpath.startswith(SPACE) and (not t.objs or c in ringset)) and c not in blocked             and c not in field
    prev_, q, goal = {P["c0"]: None}, [P["c0"]], None
    while q and goal is None:
        nq = []
        for c in q:
            if c in ringset:
                goal = c
                break
            for d in CARD:
                n = nb(c, d)
                if n not in prev_ and free(n):
                    prev_[n] = c
                    nq.append(n)
        q = nq
    if goal is None:
        return None
    path, c = [], goal
    while c is not None:
        path.append(c)
        c = prev_[c]
    return path


def _build_solar(m, key, P, field0, claimed, log):
    """v6_station.solars' build, on a found room and field."""
    import v6_station as V6
    from forge import kit
    from forge.kit import CARD, OPP
    nb = V6.nb
    sub, word = SOLAR_SUB[key], SOLAR_WORD[key]
    x0, y0 = field0
    x1, y1 = x0 + FIELD - 1, y0 + FIELD - 1
    field = [(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)]
    ring = [(x, y) for x in range(x0 - 1, x1 + 2) for y in (y0 - 1, y1 + 1)] + \
           [(x, y) for y in range(y0, y1 + 1) for x in (x0 - 1, x1 + 1)]
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    area = dmm.Atom("/area/solar/%s" % sub)
    for p in ring:
        m.set(p[0], p[1], dmm.Tile([dmm.Atom("/obj/structure/lattice")], dmm.Atom("/turf/open/space/basic"),
                                   dmm.Atom("/area/space/nearstation")))
    for (x, y) in field:
        catwalk = (y - y0) % 3 == 1 or x == cx
        if (x, y) == (cx, cy):
            objs, turf = [dmm.Atom("/obj/machinery/power/tracker"), dmm.Atom(kit.CABLE)], "/turf/open/floor/plating/airless"
        elif catwalk:
            objs, turf = [dmm.Atom("/obj/structure/lattice/catwalk"), dmm.Atom(kit.CABLE)], "/turf/open/floor/plating/airless"
        else:
            objs = [dmm.Atom("/obj/machinery/power/solar", [("id", '"%s"' % word)]), dmm.Atom(kit.CABLE)]
            turf = "/turf/open/floor/plasteel/airless/solarpanel"
        m.set(x, y, dmm.Tile(objs, dmm.Atom(turf), area.copy()))
    ra = dmm.Atom("/area/maintenance/solars/%s" % sub)
    for c in P["inner"]:
        m.set(c[0], c[1], dmm.Tile([], dmm.Atom("/turf/open/floor/plating"), ra.copy()))
    for c in P["ring"] + P["flank"]:
        if not m.get(*c).tpath.startswith("/turf/closed"):
            m.set(c[0], c[1], dmm.Tile([], dmm.Atom(RWALL), ra.copy()))
    name = "%s Solar" % sub.replace("/", " ").title().replace("Fore", "Bow").replace("Aft", "Quarter")
    m.set(P["door"][0], P["door"][1], dmm.Tile(
        [dmm.Atom("/obj/machinery/door/airlock/engineering", [("name", '"%s Access"' % name), ("req_access_txt", '"10"')])],
        dmm.Atom("/turf/open/floor/plating"), ra.copy()))
    o_ = P["out"]

    def ext(toward):
        return [dmm.Atom("/obj/machinery/door/airlock/external", [("name", '"Solar Maintenance"'), ("req_access_txt", '"13"')]),
                dmm.Atom("/obj/effect/mapping_helpers/airlock/cyclelink_helper", [("dir", str(toward))]),
                dmm.Atom(kit.CABLE)]
    m.set(P["a1"][0], P["a1"][1], dmm.Tile(ext(o_), dmm.Atom("/turf/open/floor/plating"), ra.copy()))
    m.set(P["v"][0], P["v"][1], dmm.Tile([dmm.Atom(kit.CABLE)], dmm.Atom("/turf/open/floor/plating"), ra.copy()))
    m.set(P["a2"][0], P["a2"][1], dmm.Tile(ext(OPP[o_]), dmm.Atom("/turf/open/floor/plating"), ra.copy()))
    m.get(*P["entry"]).objs.append(dmm.Atom(kit.CABLE))
    for c_ in P["cabs"]:
        m.get(*c_).objs.append(dmm.Atom(kit.CABLE))
    m.get(*P["term"]).objs += [dmm.Atom("/obj/machinery/power/terminal", [("dir", str(OPP[o_]))]), dmm.Atom(kit.CABLE)]
    m.get(*P["smes"]).objs.append(dmm.Atom("/obj/machinery/power/smes", [("name", '"%s Storage"' % name)]))
    cdir = next(d for d in CARD if nb(P["console"], d) == P["entry"])
    m.get(*P["console"]).objs += [dmm.Atom("/obj/machinery/power/solar_control",
                                           [("id", '"%s"' % word), ("name", '"%s Control"' % name), ("dir", str(OPP[cdir]))]),
                                  dmm.Atom(kit.CABLE)]
    V6.SOLAR_NET.update({P["a1"], P["v"], P["a2"], P["entry"], P["term"], P["console"]} | set(P["cabs"]))
    faces = [(c, d) for c in P["inner"] for d in CARD if nb(c, d) in P["ring"] and nb(c, d) != P["door"]
             and nb(c, d) != P["a1"] and c not in P["fenced"] and c != P["smes"]]
    faces.sort(key=lambda f: (abs(f[0][0] - P["door"][0]) + abs(f[0][1] - P["door"][1]), f))
    if faces:
        V6.mount(m, faces[0][0], faces[0][1], "apc", [("name", '"%s APC"' % name)])
        lf = [f for f in faces[1:] if f[0] != faces[0][0]]
        if lf:
            m.get(*lf[-1][0]).objs.append(dmm.Atom("/obj/machinery/light/small", [("dir", str(lf[-1][1]))]))
    # the catwalk: the shortest run over open space from the outer airlock to the field's edge
    blocked = set(P["inner"]) | set(P["ring"]) | set(P["flank"]) | {P["a1"], P["v"], P["a2"]} | set(claimed)
    ringset = set(ring) - {(x0 - 1, y0 - 1), (x1 + 1, y0 - 1), (x0 - 1, y1 + 1), (x1 + 1, y1 + 1)}

    def free(c):
        t = m.get(*c)
        return t is not None and (t.tpath.startswith(SPACE) and (not t.objs or c in ringset)) and c not in blocked \
            and c not in field
    prev_, q, goal = {P["c0"]: None}, [P["c0"]], None
    while q and goal is None:
        nq = []
        for c in q:
            if c in ringset:
                goal = c
                break
            for d in CARD:
                n = nb(c, d)
                if n not in prev_ and free(n):
                    prev_[n] = c
                    nq.append(n)
        q = nq
    path, c = [], goal
    while c is not None:
        path.append(c)
        c = prev_[c]
    for c in path:
        m.set(c[0], c[1], dmm.Tile([dmm.Atom("/obj/structure/lattice/catwalk"), dmm.Atom(kit.CABLE)],
                                   dmm.Atom("/turf/open/space/basic"), area.copy()))
    claimed |= set(field) | set(ring) | set(path) | blocked
    log("solars %s: field at %d,%d, room door %d,%d, SMES %d,%d, catwalk %d tiles%s" % (
        key, x0, y0, P["door"][0], P["door"][1], P["smes"][0], P["smes"][1], len(path),
        "" if goal else " NOT REACHING THE ARRAY"))


def outside(m, L=None, log=print):
    """Docks, then solars (they keep off the docks' shuttle rects), on a padded map cropped back after."""
    pad(m, PAD, L)
    claimed = docks(m, log)
    solars(m, log, claimed)
    dedupe_apcs(m, log)
    n = 0
    for area in sorted({t.apath for t in m.tiles.values() if t.apath and not t.apath.startswith(NO_APC)}):
        n += ensure_apc(m, area, lambda s: None)
    log("apc: %d areas given one (the copied rooms bring their own; these had none)" % n)
    crop(m, L=L)


# areas that take no APC: space, the arrays, the crystal's chamber (Meta's has none), the test range, shuttles
NO_APC = ("/area/space", "/area/solar", "/area/engine/supermatter", "/area/science/test_area", "/area/shuttle",
          "/area/hallway", "/area/maintenance")


# ------------------------------------------------------------------------------------------------ power
def power(m, log=print):
    """v6_station.power with the places found: the main SMES are engineering's (any SMES in an /area/engine room), their
    terminals the ones beside them that face them; the engine block's cables (the only cables on a built map besides
    the solar nets: copied rooms bring none) are kept and joined as v6 does (input net on layer 1 from the terminals to
    the collector ring, the grid from the SMES to every APC, machine, terminal and the emitters' net)."""
    import v6_station as V6
    from forge import kit
    from forge.kit import CARD, OPP
    nb = V6.nb
    smes = set()
    for (x, y, z), t in m.tiles.items():
        if t.has("/obj/machinery/power/smes") and t.apath.startswith("/area/engine") and "/solars" not in t.apath:
            smes.add((x, y))
    terms, boxed = [], []
    for s in sorted(smes):
        for d in CARD:
            q = nb(s, d)
            t = m.get(*q)
            if t is not None and any(o.path.startswith("/obj/machinery/power/terminal") and o.num("dir", 2) == OPP[d]
                                     for o in t.objs):
                terms.append(q)
                break
        else:
            for d in CARD:
                q = nb(s, d)
                t = m.get(*q)
                if V6.is_floor(t) and not kit.dense(t.objs) and q not in smes:
                    t.objs.append(dmm.Atom("/obj/machinery/power/terminal", [("dir", str(OPP[d]))] if OPP[d] != 2 else []))
                    terms.append(q)
                    break
            else:
                # boxed in (SMES and furniture on every side): no terminal can face it, it would store nothing
                ts_ = m.get(*s)
                ts_.objs = [o for o in ts_.objs if not o.path.startswith("/obj/machinery/power/smes")]
                boxed.append(s)
    smes -= set(boxed)
    if boxed:
        log("power: %d engineering SMES boxed in with no room for a terminal taken out" % len(boxed))
    # an SMES nowhere power is made or kept (a copied telecomms room's pair, crew 100 seed 7) has no terminal and no
    # net: it stores nothing and serves no one. Taken out, its floor left (the user 2026-11-26: "so many SMES that
    # don't fit a purpose")
    gone = 0
    for (x, y, z), t in m.tiles.items():
        # telecomms keeps its charged pair: they are its power (removed, the requests consoles' messages never went
        # through, Bot Shift f5 and f7, 2026-11-26)
        if not t.has("/obj/machinery/power/smes") or t.apath.startswith(
                ("/area/engine", "/area/solar", "/area/maintenance/solars", "/area/ai_monitored", "/area/tcommsat")):
            continue
        if not any(any(o.path.startswith("/obj/machinery/power/terminal") and o.num("dir", 2) == OPP[d]
                       for o in (m.get(*nb((x, y), d)).objs if m.get(*nb((x, y), d)) is not None else ()))
                   for d in CARD):
            t.objs = [o for o in t.objs if not o.path.startswith("/obj/machinery/power/smes")]
            gone += 1
    if gone:
        log("power: %d SMES with no terminal outside engineering, the arrays and the satellite taken out" % gone)
    if not smes:
        log("power: NO engineering SMES")
        return None
    kept = set()
    for (x, y, z), t in m.tiles.items():
        cab = [o for o in t.objs if kit.is_cable(o)]
        if not cab:
            continue
        if t.apath.startswith("/area/solar") or (x, y) in V6.SOLAR_NET:
            continue
        if t.apath.startswith(("/area/engine/engineering", "/area/engine/supermatter", "/area/space")):
            kept.add((x, y))
        else:
            for o in cab:
                t.objs.remove(o)
    apcs = [(x, y) for (x, y, z), t in m.tiles.items() if t.has("/obj/machinery/power/apc")]
    machines = [(x, y) for (x, y, z), t in m.tiles.items()
                if (t.has("/obj/machinery/power/smes") or t.has("/obj/machinery/power/port_gen")) and (x, y) not in smes]
    engine_out_ = [None]

    def cost(q, p, d):
        t = m.get(*q)
        if t is None or t.tpath.startswith(SPACE) or t.apath.startswith("/area/engine/supermatter") or \
                (q in kept and q != engine_out_[0]):
            return None
        c = 1.0
        if t.tpath.startswith("/turf/closed"):
            c += 0.6
        if t.has("/obj/machinery/door"):
            c += 1.5
        if V6.is_window(t):
            c += 3.0
        if any(o.path.startswith(("/obj/machinery/shower", "/obj/structure/sink", "/obj/structure/toilet")) for o in t.objs):
            c += 40
        if any(V6.solid(m.get(*nb(q, dd))) for dd in CARD):
            c -= 0.3
        return c
    comps, left_k = [], set(kept)
    while left_k:
        s0 = left_k.pop()
        g, q = {s0}, [s0]
        while q:
            c = q.pop()
            for d in CARD:
                n = nb(c, d)
                if n in left_k:
                    left_k.discard(n)
                    g.add(n)
                    q.append(n)
        comps.append(g)

    def holds(g, pre):
        return any(m.get(*p).has(pre) for p in g)
    coll = next((g for g in comps if holds(g, "/obj/machinery/power/rad_collector")), set())
    emit = next((g for g in comps if holds(g, "/obj/machinery/power/emitter")), set())

    def near(g, to):
        return min(g, key=lambda q: (min(abs(q[0] - t[0]) + abs(q[1] - t[1]) for t in to), q)) if g else None
    coll_join = near({q for q in coll if not m.get(*q).apath.startswith("/area/engine/supermatter")}, terms)

    def cost_in(q, p, d):
        t = m.get(*q)
        if t is None or t.tpath.startswith(SPACE) or t.apath.startswith("/area/engine/supermatter") or q in smes:
            return None
        return 1.0 + (0.6 if t.tpath.startswith("/turf/closed") else 0)
    # one tree from the first terminal to the others and the collector ring (v6's terminals stood in a row and joined
    # by adjacency; copied SMES rooms stand apart, and a tree per terminal left all but one SMES uncharged)
    ts = sorted(terms)
    inmask, inleft = V6.forest(m, ts[:1], ts[1:] + ([coll_join] if coll_join else []), cost_in)
    for p in inmask:
        m.get(*p).objs.append(dmm.Atom("/obj/structure/cable/layer1"))
    for p in list(terms) + ([coll_join] if coll_join else []):
        m.get(*p).objs.append(dmm.Atom("/obj/structure/cable_bridge"))

    def in_sat(t):
        return t.apath == "/area/ai_monitored/turret_protected/ai" or t.apath.startswith("/area/ai_monitored/turret_protected/aisat") \
            or t.apath.startswith("/area/ai_monitored/storage/satellite")
    sat_smes = [(x, y) for (x, y, z), t in m.tiles.items() if t.has("/obj/machinery/power/smes") and in_sat(t)]
    other_term = []
    for sp in [p for p in machines if m.get(*p).has("/obj/machinery/power/smes")]:
        for d in CARD:
            q = nb(sp, d)
            if any(o.path.startswith("/obj/machinery/power/terminal") and o.num("dir", 2) == OPP[d] for o in m.get(*q).objs):
                other_term.append(q)
    sat_term = [q for q in other_term if any(nb(q, d) in sat_smes for d in CARD)]
    sat_apcs = [a for a in apcs if in_sat(m.get(*a))] if sat_smes else []

    def cost_sat(q, p, d):
        t = m.get(*q)
        if t is None or not in_sat(t) or q in sat_term or q in inmask:
            return None
        return cost(q, p, d)
    satmask, satleft = V6.forest(m, sorted(sat_smes), sat_apcs, cost_sat) if sat_smes else ({}, set())
    for p in satmask:
        m.get(*p).objs.append(dmm.Atom("/obj/structure/cable/layer1"))
    for p in list(sat_smes) + [a for a in sat_apcs if a in satmask]:
        m.get(*p).objs.append(dmm.Atom("/obj/structure/cable_bridge"))
    sat_apcs = [a for a in sat_apcs if a in satmask]
    emit_join = near(emit, smes)
    on_emit = [a for a in apcs if a in emit]
    fence = set(coll) | {nb(q, d) for q in coll for d in CARD}
    fence |= set(terms) | ({coll_join} if coll_join else set()) | set(sat_smes) | set(sat_apcs)
    fence |= set(emit) - {emit_join}
    solar_net = {(x, y) for (x, y, z), t in m.tiles.items()
                 if (t.apath.startswith("/area/solar") and any(kit.is_cable(o) for o in t.objs)) or (x, y) in V6.SOLAR_NET}
    fence |= solar_net | {nb(q, d) for q in solar_net for d in CARD}
    fence -= set(machines)
    fence -= smes
    fence -= set(other_term)
    engine_out_[0] = emit_join

    def cost_grid(q, p, d):
        return None if q in fence else cost(q, p, d)
    targets = [a for a in apcs if a not in sat_apcs and a not in on_emit] + \
        [p for p in machines if p not in sat_smes] + list(other_term) + ([emit_join] if emit_join else [])
    # one grid: from the first main SMES, the others among its targets (a tree per SMES made three separate nets on
    # crew 80 seed 1, 2026-11-25)
    ss = sorted(smes)
    mask, left = V6.forest(m, ss[:1], ss[1:] + targets, cost_grid)
    for p in mask:
        m.get(*p).objs.append(dmm.Atom(kit.CABLE))
    log("power: %d main SMES, %d APCs; grid %d cable tiles (emitters joined at %s); input net %d layer-1 tiles to the "
        "collector ring at %s; AI sat net %d tiles, %d APCs%s%s%s" % (
            len(smes), len(apcs), len(mask), "%d,%d" % emit_join if emit_join else "-", len(inmask),
            "%d,%d" % coll_join if coll_join else "-", len(satmask), len(sat_apcs),
            (", UNREACHED %d: %s" % (len(left), " ".join("%d,%d" % p for p in sorted(left)[:8]))) if left else "",
            ", COLLECTORS NOT JOINED" if inleft else "", (", SAT UNREACHED %d" % len(satleft)) if satleft else ""))
    return left


# ------------------------------------------------------------------------------------------------ air
GAS_TURF = "/turf/open/floor/engine/"


PLAIN = ("/obj/structure/cable", "/obj/structure/lattice", "/obj/effect/spawner", "/obj/effect/landmark", "/obj/item",
         "/turf/")
_ADDED = set()      # (id(atom), var) that rotate() added; the turn back takes them off again when they come to 2 / 0


def _rot_atom(o, k):
    """Turn one atom k quarter turns in place: its dir (one it has, or the south it faces by default unless it is a
    plain thing that doesn't face) and its pixel offsets."""
    d = o.get("dir")
    if d is not None or not o.path.startswith(PLAIN):
        nd = furnish.rot_dir(int(d) if d is not None else 2, k)
        if d is None:
            if nd != 2:
                o.vars.append(("dir", str(nd)))
                _ADDED.add((id(o), "dir"))
        elif nd == 2 and (id(o), "dir") in _ADDED:
            o.vars = [(n, v) for n, v in o.vars if n != "dir"]
            _ADDED.discard((id(o), "dir"))
        else:
            o.vars = [(n, str(nd) if n == "dir" else v) for n, v in o.vars]
    px, py = o.num("pixel_x"), o.num("pixel_y")
    if px or py:
        nx, ny = furnish.rot_xy(px, py, k)
        for name, val in (("pixel_x", nx), ("pixel_y", ny)):
            if o.get(name) is not None:
                if val == 0 and (id(o), name) in _ADDED:
                    o.vars = [(n, v) for n, v in o.vars if n != name]
                    _ADDED.discard((id(o), name))
                else:
                    o.vars = [(n, str(val) if n == name else v) for n, v in o.vars]
            elif val:
                o.vars.append((name, str(val)))
                _ADDED.add((id(o), name))


def rotate(m, k, L=None):
    """The whole map turned k quarter turns clockwise (furnish.rot_xy), atoms turned in place (_rot_atom).
    rotate(m, 4 - k) undoes it exactly: a dir or offset the turn added comes off again on the way back."""
    k %= 4
    if not k:
        return
    tiles = {}
    for (x, y, z), t in m.tiles.items():
        nx, ny = furnish.rot_xy(x, y, k)
        for o in t.objs:
            _rot_atom(o, k)
        if t.turf is not None and t.turf.get("dir") is not None:
            _rot_atom(t.turf, k)
        tiles[(nx, ny, z)] = t
    xs = [p[0] for p in tiles]
    ys = [p[1] for p in tiles]
    dx, dy = 1 - min(xs), 1 - min(ys)
    m.tiles = {(x + dx, y + dy, z): t for (x, y, z), t in tiles.items()}
    m.maxx, m.maxy = max(xs) - min(xs) + 1, max(ys) - min(ys) + 1


def _on_loop(m, p, o):
    """A vent joined to a pipe beside it: part of a copied room's own loop (room_stamp keep_local), left on it."""
    from forge import atmos as A
    for d, (dx, dy) in A.DELTA.items():
        tq = m.get(p[0] + dx, p[1] + dy)
        if tq is not None and any(A.joins(o, b, d) for b in A.atoms(tq)):
            return True
    return False


def atmos_turn(m):
    """The quarter turns that put Atmospherics' room north of its chambers (the panes of the plasma chamber face the
    room), or None when there are no chambers with panes."""
    tiles = [(x, y) for (x, y, z), t in m.tiles.items() if t.tpath.startswith(GAS_TURF + "plasma")]
    if not tiles:
        return None
    cx = round(sum(p[0] for p in tiles) / float(len(tiles)))
    cy = round(sum(p[1] for p in tiles) / float(len(tiles)))
    for k in range(4):
        dx, dy = furnish.rot_xy(0, 1, 4 - k)        # the direction that becomes north after k turns
        t = m.get(cx + 2 * dx, cy + 2 * dy)
        if t is not None and t.has("/obj/effect/spawner/structure/window"):
            return k
    return None


def air(m, log=print):
    """v6_station.air (the gas chambers' machines, the atmos works on three layers, supply and scrubber trees from them
    to every vent) on the map turned so the room is north of the chambers, as the v6 blueprint has it; turned back
    after. The engine's waste goes out by its own injector (to_dmm.paste_engine), so no tap into the scrubbers."""
    import v6_station as V6
    k = atmos_turn(m)
    if k is None:
        log("air: no gas chambers with panes")
        return None
    V6.ENGINE_WASTE_TAPS = []
    V6.LEFT_OUT.clear()
    # copied stock rooms bring layer-2 vents (/vent_pump/on): the station supply is on layer 1 here (v6's), so they sat
    # on no network (117 of 508 on crew 80 seed 1). They join the supply; a server room's vent loses its
    # unbounded-pressure settings (its stock cooling loop is not copied)
    moved = 0
    for (x, y, z), t in m.tiles.items():
        if t.apath.startswith("/area/engine/supermatter"):
            continue
        for i, o in enumerate(t.objs):
            if o.path in ("/obj/machinery/atmospherics/components/unary/vent_pump/on",
                          "/obj/machinery/atmospherics/components/unary/vent_pump") and not _on_loop(m, (x, y), o):
                t.objs[i] = dmm.Atom("/obj/machinery/atmospherics/components/unary/vent_pump/on/layer1",
                                     [(n, v) for n, v in o.vars if n in ("dir",)])
                moved += 1
    log("air: %d copied layer-2 vents moved onto the supply (layer 1)" % moved)
    rotate(m, k)
    try:
        left = V6.air(m, log)
    finally:
        rotate(m, 4 - k)
    log("air: done with the map turned %d" % (90 * k))
    return left


BIN_CLEAR = 7       # the disposals exit keeps this far (Manhattan) from every bin


def disposal_exit(m, near):
    """v6_station.disposal_exit, kept BIN_CLEAR from every bin: v6's tree never branches off its first three trunk
    tiles, so a bin that close to the exit became the whole tree (crew 80 seed 1, 2026-11-25: 1 bin of 57 reached)."""
    import v6_station as V6
    from forge import kit
    from forge.kit import CARD, OPP
    nb, is_floor, solid = V6.nb, V6.is_floor, V6.solid
    bins = [(x, y) for (x, y, z), t in m.tiles.items() if t.has("/obj/machinery/disposal/bin")]
    best = None
    for (x, y, z), t in m.tiles.items():
        if not is_floor(t) or not t.apath.startswith("/area/maintenance") or kit.dense(t.objs):
            continue
        if any(abs(x - b[0]) + abs(y - b[1]) < BIN_CLEAR for b in bins):
            continue
        for d in CARD:
            drv, wall, sp = nb((x, y), d), nb(nb((x, y), d), d), nb(nb(nb((x, y), d), d), d)
            td, tw, ts = m.get(*drv), m.get(*wall), m.get(*sp)
            if not (is_floor(td) and td.apath.startswith("/area/maintenance") and not kit.dense(td.objs)
                    and not td.has("/obj/machinery/door") and tw is not None and tw.tpath.startswith("/turf/closed")
                    and ts is not None and ts.tpath.startswith(SPACE)):
                continue
            if not all(solid(m.get(*nb(wall, s))) for s in CARD if s not in (d, OPP[d])):
                continue
            q, clear = sp, True
            while m.get(*q) is not None:
                if not m.get(*q).tpath.startswith(SPACE):
                    clear = False
                    break
                q = nb(q, d)
            if not clear:
                continue
            k = (abs(x - near[0]) + abs(y - near[1]), x, y, d)
            if best is None or k < best[0]:
                best = (k, (x, y), d)
    return (best[1], best[2]) if best else None


def networks(m, log=print):
    """Power, air, disposals, in v6's order (disposals last: they reach the bins under whatever stands there)."""
    import v6_station as V6
    out = {}
    out["power"] = power(m, log)
    REPORT["power_unreached"] = len(out["power"]) if out["power"] is not None else -1
    out["air"] = air(m, log)
    REPORT["air"] = out["air"] is not None
    orig = V6.disposal_exit
    V6.disposal_exit = lambda m_, near: disposal_exit(m_, near) or orig(m_, near)
    try:
        V6.disposals(m, log)
    except Exception as e:                       # noqa: BLE001 - logged, the build goes on
        log("disposals: failed: %s" % str(e)[:200])
    finally:
        V6.disposal_exit = orig
    return out


def net_checks():
    """The build's checks on what gen/net.py laid (hard: a station without its engine, a dock, a working grid or its
    atmos works does not run). From REPORT, filled by the last engine/outside/networks run."""
    r = REPORT
    miss = r.get("docks_missing", ["?"])
    return [
        dict(kind="hard", name="engine placed", ok=bool(r.get("engine")), value=int(bool(r.get("engine"))),
             detail="the supermatter block against engineering"),
        dict(kind="hard", name="docks", ok=not miss, value=len(miss), detail="missing: %s" % (", ".join(miss) or "none")),
        dict(kind="hard", name="solar arrays", ok=r.get("solars", 0) >= 4, value=r.get("solars", 0), detail="of 4"),
        dict(kind="hard", name="grid reach", ok=0 <= r.get("power_unreached", -1) <= 1,
             value=r.get("power_unreached", -1), detail="APCs, machines and terminals the grid left out (at most 1)"),
        dict(kind="hard", name="atmos works", ok=bool(r.get("air")), value=int(bool(r.get("air"))),
             detail="chambers found and the trees laid"),
        dict(kind="hard", name="walkable rooms", ok=len(r.get("cut_off", ["?"] * 9)) <= 4,
             value=len(r.get("cut_off", ["?"] * 9)),
             detail="areas under 60%% walkable from the halls after gen/walkfix.py (at most 4; the accepted v6 build 0, "
                    "Meta 4, Hippie 5): %s"
             % ", ".join(r.get("cut_off", ["?"])[:6])),
    ]
