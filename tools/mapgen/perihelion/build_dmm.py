"""Build _maps/map_files/Perihelion/perihelion.dmm from layout.py.

    python tools/mapgen/perihelion/build_dmm.py

Model: room, hall and walkway rects are wall lines (walls on x0, x1, y0, y1,
floor inside; neighbours share a wall). Maint tunnels are painted tiles.
Every module has a maint ring one tile outside its rect and a hull outside
that. Coordinates here are layout tiles (y down); write() converts to DM.
"""
import heapq
import json
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import dmmlib as D  # noqa: E402
import layout as L  # noqa: E402
import render as R  # noqa: E402
import furnish  # noqa: E402
import rooms_data as RD  # noqa: E402

OX, OY = L.OFFSET
W = L.WORLD
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))

SPACE = "/turf/open/space/basic"
A_SPACE = "/area/space"
A_NEAR = "/area/space/nearstation"
WALL = "/turf/closed/wall"
RWALL = "/turf/closed/wall/r_wall"
PLATING = "/turf/open/floor/plating"
PLASTEEL = "/turf/open/floor/plasteel"
WINDOW = "/obj/effect/spawner/structure/window/reinforced"
CABLE = "/obj/structure/cable"

N, S, E, Wd = 1, 2, 4, 8
STEP = {N: (0, -1), S: (0, 1), E: (1, 0), Wd: (-1, 0)}
OPP = {N: S, S: N, E: Wd, Wd: E}
DIRNAME = {N: "north", S: "south", E: "east", Wd: "west"}


class Tile:
    __slots__ = ("turf", "area", "objs", "kind", "owner", "indoor", "dense", "mounts", "pipe_ok")

    def __init__(self):
        self.turf = SPACE
        self.area = A_SPACE
        self.objs = []
        self.kind = "space"     # space floor wall window door exterior
        self.owner = None       # ("room"|"hall"|"walkway"|"maint"|"tunnel", name)
        self.indoor = False
        self.dense = False      # something dense stands here (furniture placement)
        self.mounts = set()     # wall-mount dirs used (lights, APCs, alarms)


class Grid:
    def __init__(self):
        self.t = {}
        self.xmin, self.xmax = 1 - OX, W - OX
        self.ymin, self.ymax = -OY, W - OY - 1

    def inb(self, x, y):
        return self.xmin <= x <= self.xmax and self.ymin <= y <= self.ymax

    def __getitem__(self, p):
        t = self.t.get(p)
        if t is None:
            t = self.t[p] = Tile()
        return t

    def floor(self, x, y, turf, area, owner, indoor=True):
        t = self[x, y]
        t.turf, t.area, t.kind, t.owner, t.indoor = turf, area, "floor", owner, indoor
        t.objs = [o for o in t.objs if not o.startswith(WINDOW)]
        return t

    def wall(self, x, y, turf, area, owner):
        t = self[x, y]
        if t.kind == "wall" and t.turf == RWALL:
            turf = RWALL
        t.turf, t.area, t.kind, t.owner = turf, area, "wall", owner
        t.objs = []
        return t


def lines(r):
    x0, y0, x1, y1 = r
    for x in range(x0, x1 + 1):
        for y in range(y0, y1 + 1):
            yield x, y, (x in (x0, x1) or y in (y0, y1))


def interior(r):
    x0, y0, x1, y1 = r
    for y in range(y0 + 1, y1):
        for x in range(x0 + 1, x1):
            yield x, y


def door_tile(o, fixed, mid):
    return (fixed, mid) if o == "v" else (mid, fixed)


# ---------------------------------------------------------------- shell
def build_shell(g, problems):
    rooms = {r[0]: r for r in L.ROOMS}
    halls = {h[0]: h for h in L.HALLS}
    walks = {w[0]: w for w in L.WALKWAYS}

    # modules: everything from ring inwards starts as maint plating
    mod_rect = {}
    for name, dept, r in L.MODULES:
        mod_rect[name] = r
        x0, y0, x1, y1 = r
        for x in range(x0 - 1, x1 + 2):
            for y in range(y0 - 1, y1 + 2):
                g.floor(x, y, PLATING, RD.MODULE_MAINT[name], ("maint", name))

    # interiors first, then walls on lines
    def paint(r, turf, area, owner):
        for x, y in interior(r):
            g.floor(x, y, turf, area, owner)

    for name, own, r in L.HALLS:
        paint(r, RD.HALL_FLOOR.get(name, PLASTEEL), RD.HALL_AREA[name], ("hall", name))
    for name, r, kind in L.WALKWAYS:
        paint(r, RD.WALK_FLOOR.get(kind, PLASTEEL), RD.WALK_AREA[name], ("walkway", name))
    for name, dept, r, flags in L.ROOMS:
        paint(r, RD.room_floor(name, dept), RD.ROOM_AREA[name], ("room", name))

    def in_module_shell(x, y):
        for r in mod_rect.values():
            if r[0] - 2 <= x <= r[2] + 2 and r[1] - 2 <= y <= r[3] + 2:
                return True
        return False

    def wall_lines(r, turf, area, owner, glass=False):
        for x, y, edge in lines(r):
            if not edge:
                continue
            t = g[x, y]
            if t.kind == "floor" and t.owner and t.owner[0] in ("room", "hall", "walkway"):
                continue  # interior of a neighbour (shouldn't happen)
            if glass and not in_module_shell(x, y):
                g.floor(x, y, PLATING, area, owner)
                t.kind = "window"
                t.objs = [WINDOW]
            else:
                g.wall(x, y, turf, area, owner)

    for name, dept, r, flags in L.ROOMS:
        wall_lines(r, RWALL if ("secure" in flags or "pod" in flags) else WALL, RD.ROOM_AREA[name], ("room", name))
    for name, own, r in L.HALLS:
        wall_lines(r, WALL, RD.HALL_AREA[name], ("hall", name))
    for name, r, kind in L.WALKWAYS:
        horiz = (r[2] - r[0]) > (r[3] - r[1])
        # the ends sit on the halls' wall lines: leave those to the openings
        x0, y0, x1, y1 = r
        for x, y, edge in lines(r):
            if not edge:
                continue
            if horiz and x in (x0, x1) and y0 < y < y1:
                continue
            if not horiz and y in (y0, y1) and x0 < x < x1:
                continue
            t = g[x, y]
            if t.kind == "floor" and t.owner and t.owner[0] in ("room", "hall"):
                continue
            if kind == "glass" and not in_module_shell(x, y):
                g.floor(x, y, PLATING, RD.WALK_AREA[name], ("walkway", name))
                g[x, y].kind = "window"
                g[x, y].objs = [WINDOW]
            elif t.kind != "wall":
                g.wall(x, y, RWALL if kind == "tunnel" else WALL, RD.WALK_AREA[name], ("walkway", name))

    # maint tunnels (painted tiles): only over space or maint
    for name, r in L.MAINT:
        x0, y0, x1, y1 = r
        for x in range(x0, x1):
            for y in range(y0, y1):
                t = g[x, y]
                if t.kind == "space" or (t.kind == "floor" and t.owner and t.owner[0] == "maint"):
                    if t.kind == "space":
                        g.floor(x, y, PLATING, RD.TUNNEL_AREA, ("tunnel", name))

    # doors from the plan
    plan_problems = []
    doors, pub = R.compute(plan_problems, verbose=False)
    problems += plan_problems
    door_tiles = {}
    for o, fixed, mid, kind, a, b in doors:
        place_plan_door(g, o, fixed, mid, kind, a, b, rooms, halls, walks, door_tiles, problems)

    # glass between chosen rooms and the hall their door opens on
    nwin = 0
    for o, fixed, mid, kind, a, b in doors:
        if kind not in ("", "access", "locked"):
            continue
        room = a if a in RD.WINDOW_ROOMS else (b if b in RD.WINDOW_ROOMS else None)
        other = b if room == a else a
        if room is None or not (other in halls or other in walks):
            continue
        e = R.shared_edge(rooms[room][2], halls[other][2] if other in halls else walks[other][1])
        if not e:
            continue
        o2, f2, lo, hi = e
        for k in range(lo + 1, hi):
            if abs(k - mid) <= 1:
                continue
            x, y = door_tile(o2, f2, k)
            t = g[x, y]
            if t.kind == "wall" and t.turf == WALL and (x, y) not in door_tiles:
                # a window only where there's floor on both sides
                sides = ((x - 1, y), (x + 1, y)) if o2 == "v" else ((x, y - 1), (x, y + 1))
                if all(g[q].kind == "floor" for q in sides):
                    g.floor(x, y, PLATING, t.area, t.owner)
                    t.kind = "window"
                    t.objs = [WINDOW]
                    nwin += 1
    print("windows onto halls:", nwin)

    # openings: same-owner halls, walkways into public halls
    parts = [(h[0], h[1], h[2], "hall") for h in L.HALLS] + [(w[0], "public", w[1], "walkway") for w in L.WALKWAYS]
    for i in range(len(parts)):
        for j in range(i + 1, len(parts)):
            a, b = parts[i], parts[j]
            if a[1] != b[1]:
                continue
            e = R.shared_edge(a[2], b[2])
            if not e:
                continue
            o, fixed, lo, hi = e
            wk = a if a[3] == "walkway" else (b if b[3] == "walkway" else None)
            for k in range(lo + 1, hi):
                x, y = door_tile(o, fixed, k)
                src = wk or a
                area = RD.WALK_AREA[src[0]] if wk else RD.HALL_AREA[src[0]]
                g.floor(x, y, PLASTEEL, area, (src[3], src[0]))
                if wk and walks[wk[0]][2] == "glass":
                    g[x, y].objs = ["/obj/machinery/door/firedoor"]
    return doors, door_tiles


def access_attr(acc):
    if not acc:
        return ""
    if ";" in acc:
        return 'req_one_access_txt = "%s"' % acc
    return 'req_access_txt = "%s"' % acc


def airlock(path, name=None, acc=None, extra=None):
    parts = []
    if name:
        parts.append('name = "%s"' % name)
    if acc:
        parts.append(access_attr(acc))
    if extra:
        parts.append(extra)
    return path + ("{%s}" % "; ".join(parts) if parts else "")


def place_plan_door(g, o, fixed, mid, kind, a, b, rooms, halls, walks, door_tiles, problems):
    x, y = door_tile(o, fixed, mid)
    # which side is the "inner" one (the room/hall the door belongs to)
    def side_info(n):
        if n in rooms:
            return "room", rooms[n]
        if n in halls:
            return "hall", halls[n]
        if n in walks:
            return "walk", walks[n]
        return None, None
    ka, ra = side_info(a)
    kb, rb = side_info(b)

    def is_public(n, k, r):
        if k == "room":
            return "public" in r[3]
        if k == "hall":
            return r[1] == "public"
        return True
    inner, outer = (a, b)
    if is_public(a, ka, ra) and not is_public(b, kb, rb):
        inner, outer = b, a
    ki, ri = side_info(inner)
    if ki == "room":
        dept, area = ri[1], RD.ROOM_AREA[inner]
    elif ki == "hall":
        dept, area = (ri[1] if ri[1] != "public" else "arr"), RD.HALL_AREA[inner]
    else:
        dept, area = "arr", RD.WALK_AREA[inner]

    t = g[x, y]
    if kind == "open":
        e = R.shared_edge((ra or rb)[2] if ka == "room" else ra[2], rb[2] if kb == "room" else rb[2])
        o2, f2, lo, hi = e
        for k in range(lo + 1, hi):
            xx, yy = door_tile(o2, f2, k)
            g.floor(xx, yy, RD.room_floor(inner, dept), area, ("room", inner))
        return
    turf = RD.room_floor(inner, dept) if ki == "room" else PLASTEEL
    g.floor(x, y, turf, area, ("door", inner))
    t.kind = "door"
    acc = RD.door_access(inner, outer, kind)
    name = RD.door_name(inner)
    if kind == "desk":
        # counter: table + windoor facing the department side
        dept_side = inner
        dx, dy = side_toward(g, x, y, o, dept_side, rooms, halls)
        d = {(0, -1): "north", (0, 1): "south", (1, 0): "east", (-1, 0): "west"}[(dx, dy)]
        if inner in ("Kitchen", "Hydroponics") or outer in ("Kitchen", "Hydroponics"):
            # a food counter: a bare table, so the cook can put dishes out and the crew can take them
            t.objs = ["/obj/structure/table/reinforced"]
        else:
            t.objs = ["/obj/structure/table/reinforced",
                      "/obj/machinery/door/window/%sleft{name = \"%s Desk\"; %s}" % (d, name, access_attr(acc) or 'req_access_txt = "0"')]
        t.kind = "window"  # blocks walking; air-tight enough for a desk
        t.dense = True
    else:
        path = RD.door_path(inner, dept, kind, ki)
        t.objs = [airlock(path, name, acc)]
    door_tiles[(x, y)] = (inner, outer, kind)


def side_toward(g, x, y, o, name, rooms, halls):
    """Unit step from a door tile on a line toward the named side."""
    cands = [(1, 0), (-1, 0)] if o == "v" else [(0, 1), (0, -1)]
    for dx, dy in cands:
        t = g[x + dx, y + dy]
        if t.owner and t.owner[1] == name:
            return dx, dy
    return cands[0]


# ---------------------------------------------------------------- maint doors
def maint_doors(g, door_tiles):
    """Each hall that lies on its module's boundary gets a maint door out to the ring."""
    for mname, dept, mr in L.MODULES:
        x0, y0, x1, y1 = mr
        for name, own, r in L.HALLS:
            hx0, hy0, hx1, hy1 = r
            if not (x0 <= hx0 and hx1 <= x1 and y0 <= hy0 and hy1 <= y1):
                continue
            cands = []
            if hx0 == x0:
                cands.append(("v", hx0, hy0, hy1, -1))
            if hx1 == x1:
                cands.append(("v", hx1, hy0, hy1, 1))
            if hy0 == y0:
                cands.append(("h", hy0, hx0, hx1, -1))
            if hy1 == y1:
                cands.append(("h", hy1, hx0, hx1, 1))
            for o, fixed, lo, hi, sgn in cands:
                # longest run of plain wall with hall inside and maint outside
                best, run = None, []
                for k in range(lo + 1, hi):
                    xx, yy = door_tile(o, fixed, k)
                    ox, oy = (xx + sgn, yy) if o == "v" else (xx, yy + sgn)
                    ix, iy = (xx - sgn, yy) if o == "v" else (xx, yy - sgn)
                    ok = (g[xx, yy].kind == "wall" and g[ox, oy].kind == "floor" and g[ox, oy].owner[0] in ("maint", "tunnel")
                          and g[ix, iy].kind == "floor" and g[ix, iy].owner == ("hall", name))
                    if ok:
                        run.append((xx, yy))
                    else:
                        if run and (best is None or len(run) > len(best)):
                            best = run
                        run = []
                if run and (best is None or len(run) > len(best)):
                    best = run
                if best and len(best) >= 3:
                    xx, yy = best[len(best) // 2]
                    t = g.floor(xx, yy, PLATING, RD.HALL_AREA[name], ("door", name))
                    t.kind = "door"
                    if own == "public":
                        t.objs = [airlock("/obj/machinery/door/airlock/maintenance", "Maintenance Access", "12")]
                    else:  # a department hall: the department's own access, as tg's department maint doors
                        t.objs = [airlock("/obj/machinery/door/airlock/maintenance", RD.door_name(name) + " Maintenance", RD.GATE_ACCESS[name])]
                    door_tiles[(xx, yy)] = (name, "maint", "maint")


ENGINE_AREA_MAP = {
    "/area/maintenance/port/aft": "/area/maintenance/aft",
}
ENGINE_DROP = ("/obj/machinery/power/apc", "/obj/effect/landmark", "/obj/docking_port", "/obj/effect/mapping_helpers/airlock/cyclelink")


_HIP = None


def hippie_map():
    global _HIP
    if _HIP is None:
        _HIP = D.read(os.path.join(ROOT, "_maps", "map_files", "HippieStation", "hippiestation.dmm"))
    return _HIP


def paste_engine(g, problems):
    """Copy Hippie's supermatter room in tile for tile: the crystal, chamber, filters, pumps,
    emitters, collectors, the heat exchangers out in space and its own walls. Hippie's bots
    already know how to start this exact engine. Returns the set of pasted tiles."""
    return paste_block(g, problems, L.ENGINE_SRC, L.ENGINE_AT, "engine", ENGINE_AREA_MAP)


def paste_block(g, problems, src, at, owner, area_map, keep_area=None):
    hip = hippie_map()
    sx0, sy0, sx1, sy1 = src
    ax, ay = at
    tiles = set()
    for hy in range(sy1, sy0 - 1, -1):
        for hx in range(sx0, sx1 + 1):
            atoms = hip.get(hx, hy)
            x, y = ax + (hx - sx0), ay + (sy1 - hy)
            area = atoms[-1].split("{")[0]
            area = area_map.get(area, area)
            if keep_area and not area.startswith("/area/space") and area != keep_area:
                area = keep_area
            turf = atoms[-2]
            objs = [a for a in atoms[:-2] if not a.startswith(ENGINE_DROP)]
            t = g[x, y]
            t.turf, t.area, t.objs = turf, area, objs
            t.owner = ("chunk", owner)
            j = " ".join(objs)
            if turf.startswith("/turf/closed"):
                t.kind, t.indoor = "wall", True
            elif turf.startswith("/turf/open/space") or "airless" in turf:
                t.kind, t.indoor = "exterior", False
            elif "/obj/machinery/door/airlock" in j or "/obj/machinery/door/poddoor" in j:
                t.kind, t.indoor = "door", True
            elif "/obj/effect/spawner/structure/window" in j or "/obj/structure/window" in j or "/obj/structure/grille" in j:
                t.kind, t.indoor = "window", True
            else:
                t.kind, t.indoor = "floor", True
            t.dense = True
            tiles.add((x, y))
    # wall off our side wherever it now touches open space from the block
    sealed = 0
    for (x, y) in list(tiles):
        if g[x, y].kind != "exterior":
            continue
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                q = (x + dx, y + dy)
                if q in tiles:
                    continue
                t = g.t.get(q)
                if t is not None and t.kind in ("floor", "door") and t.indoor:
                    t.turf, t.kind, t.objs = RWALL, "wall", [o for o in t.objs if not o.startswith("/obj/machinery/door")]
                    sealed += 1
    return tiles, sealed


def engine_doors(g, problems):
    # the door down from Engine Airlock
    dx_, dy_ = L.ENGINE_DOOR
    below = g[dx_, dy_ + 1]
    if below.kind not in ("floor", "door"):
        problems.append("engine door at %s opens onto %s" % (L.ENGINE_DOOR, below.kind))
    t = g[dx_, dy_]
    t.turf, t.kind, t.indoor = PLASTEEL, "door", True
    t.objs = [airlock("/obj/machinery/door/airlock/engineering/glass", "Engine Room", "10")]
    if L.ENGINE == "sm":
        # Hippie's spare-emitter nook was reached from outside the block: open it to the gravity room
        t = g[105, 162]
        t.turf, t.kind, t.indoor = PLASTEEL, "door", True
        t.objs = [airlock("/obj/machinery/door/airlock/engineering", "Engine Storage", "10")]
    else:
        # the tesla room's APC was outside the block: put one on a tile its own grid (layer 2) runs under
        ax, ay = L.ENGINE_AT
        sx0, sy0, sx1, sy1 = L.ENGINE_SRC
        best = None
        for x in range(ax, ax + sx1 - sx0 + 1):
            for y in range(ay, ay + sy1 - sy0 + 1):
                t = g[x, y]
                if t.kind != "floor" or "/obj/structure/cable" not in t.objs or t.area != "/area/engine/port_engineering":
                    continue
                for d, (ddx, ddy) in ((1, (0, -1)), (2, (0, 1)), (4, (1, 0)), (8, (-1, 0))):
                    if g[x + ddx, y + ddy].kind == "wall":
                        if best is None or y < best[1]:
                            best = (x, y, d)
        if best:
            x, y, d = best
            g[x, y].objs.append("/obj/machinery/power/apc/highcap/fifteen_k{dir = %d; name = \"Engine Room APC\"; areastring = \"/area/engine/port_engineering\"; pixel_%s = %d}"
                                % (d, "y" if d in (1, 2) else "x", {1: 25, 2: -25, 4: 24, 8: -25}[d]))
            g[x, y].mounts.add(d)
        else:
            problems.append("tesla room: no spot for its APC")


def paste_xeno(g, problems):
    tiles, sealed = paste_block(g, problems, L.XENO_SRC, L.XENO_AT, "xeno", {}, keep_area="/area/science/xenobiology")
    # doors of Hippie's that led out of the block now open on space: wall them
    walled = 0
    for (x, y) in tiles:
        t = g[x, y]
        if t.kind != "door":
            continue
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + dx, y + dy)
            if q not in tiles and g[q].kind in ("space", "exterior") and (x, y) != (L.XENO_DOOR[0] + 1, L.XENO_DOOR[1]):
                t.turf, t.kind, t.objs = RWALL, "wall", []
                walled += 1
                break
    x, y = L.XENO_DOOR
    t = g[x, y]
    t.turf, t.kind, t.indoor = "/turf/open/floor/plasteel/white", "door", True
    t.objs = [airlock("/obj/machinery/door/airlock/research", "Xenobiology", "55")]
    inside = g[x + 1, y]
    if inside.kind != "door":
        problems.append("xeno: expected Hippie's door at %s, found %s" % ((x + 1, y), inside.kind))
    return tiles, walled


def connect_maint(g, door_tiles, problems):
    """Every stretch of maintenance must open onto a hall somewhere.

    Walkways cut the module rings into arcs; an arc with no tunnel or maint door is
    unreachable. Find each connected stretch; tiny pockets are walled up, the rest
    get a maintenance door through a wall onto a public hall or walkway (a
    department hall or ordinary room if nothing better is next to it).
    """
    def is_maint(p):
        t = g.t.get(p)
        return t is not None and t.kind == "floor" and t.owner and t.owner[0] in ("maint", "tunnel")
    seen = set()
    comps = []
    for p in list(g.t):
        if p in seen or not is_maint(p):
            continue
        comp, todo = [p], [p]
        seen.add(p)
        while todo:
            x, y = todo.pop()
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                q = (x + dx, y + dy)
                if q not in seen and is_maint(q):
                    seen.add(q)
                    comp.append(q)
                    todo.append(q)
        comps.append(comp)
    secure_rooms = {r[0] for r in L.ROOMS if "secure" in r[3] or "pod" in r[3]}
    public_names = {h[0] for h in L.HALLS if h[1] == "public"} | {w[0] for w in L.WALKWAYS if w[0] != "T1"}
    added = walled = 0
    for comp in comps:
        cset = set(comp)
        linked = False
        for (x, y) in comp:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                d = door_tiles.get((x + dx, y + dy))
                if d is not None and d[2] == "maint" and (d[0] in public_names):
                    linked = True
        if linked:
            continue
        if len(comp) < 4:
            for p in comp:
                g[p].turf, g[p].kind, g[p].objs = WALL, "wall", []
            walled += 1
            continue
        best = None
        for (x, y) in comp:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                w = (x + dx, y + dy)
                o = (x + 2 * dx, y + 2 * dy)
                tw, to = g.t.get(w), g.t.get(o)
                if tw is None or to is None or tw.kind != "wall" or tw.turf != WALL and tw.turf != RWALL:
                    continue
                if to.kind != "floor" or not to.owner:
                    continue
                kind, name = to.owner
                if name == "T1" or name in secure_rooms:
                    continue
                if any((w[0] + ex, w[1] + ey) in door_tiles for ex in (-1, 0, 1) for ey in (-1, 0, 1)):
                    continue
                if kind == "walkway" or (kind == "hall" and dict((h[0], h[1]) for h in L.HALLS)[name] == "public"):
                    pri = 0
                elif kind == "hall":
                    pri = 1
                elif kind == "room":
                    pri = 2
                else:
                    continue
                if best is None or pri < best[0]:
                    best = (pri, w, to)
        if best is None:
            problems.append("maint stretch of %d tiles at %s has no way in" % (len(comp), comp[0]))
            continue
        pri, w, to = best
        t = g[w]
        t.turf, t.kind, t.area = PLATING, "door", to.area
        t.indoor = True
        nm = to.owner[1]
        acc = "12" if pri == 0 else (RD.GATE_ACCESS.get(nm) or RD.ROOMS.get(nm, (None, None, "12"))[2] or "12")
        t.objs = [airlock("/obj/machinery/door/airlock/maintenance", "Maintenance Access", acc)]
        door_tiles[w] = (to.owner[1], "maint", "maint")
        added += 1
    return added, walled


# ---------------------------------------------------------------- hull + outside
def hull(g):
    tiles = list(g.t.items())
    for (x, y), t in tiles:
        if t.kind in ("floor", "door") and t.indoor:
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    n = g[x + dx, y + dy]
                    if n.kind == "space":
                        n.turf, n.kind, n.area = RWALL, "wall", t.area if t.owner and t.owner[0] != "room" else n.area
                        if n.area == A_SPACE:
                            n.area = t.area


def ext_airlock(g, x, y, acc=None, name="External Airlock"):
    t = g[x, y]
    t.turf, t.kind = PLATING, "door"
    t.indoor = True
    t.objs = [airlock("/obj/machinery/door/airlock/external", name, acc)]
    return t


def docks(g, problems):
    """Docking ports and their airlocks (geometry copied from Hippie's docks)."""
    P = []

    def port(x, y, body):
        t = g[x, y]
        if t.kind != "space":
            problems.append("docking port on non-space tile %s,%s" % (x, y))
        t.objs.append("/obj/docking_port/stationary{%s}" % body)
        P.append((x, y))

    def through(xh, y, xin, acc, name, sgn=1):
        """Hull airlock at xh, ring floor between, inner airlock at xin (horizontal line)."""
        ext_airlock(g, xh, y, acc, name)
        for xx in range(min(xh, xin) + 1, max(xh, xin)):
            g[xx, y].kind = "floor"
        ext_airlock(g, xin, y, acc, name)

    def through_v(x, yh, yin, acc, name):
        ext_airlock(g, x, yh, acc, name)
        for yy in range(min(yh, yin) + 1, max(yh, yin)):
            g[x, yy].kind = "floor"
        ext_airlock(g, x, yin, acc, name)

    # arrivals: slot between the two dock corridors
    port(65, 17, 'name = "arrivals"; width = 7; height = 15; id = "arrivals_stationary"; dwidth = 3; '
                 'roundstart_template = /datum/map_template/shuttle/arrival/box')
    for (x, y) in ((61, 15), (61, 8), (69, 15), (69, 8)):
        ext_airlock(g, x, y, None, "Arrivals Airlock")
    # escape
    port(205, 88, 'name = "Perihelion emergency evac bay"; dir = 4; width = 32; height = 18; id = "emergency_home"')
    for y in (88, 94, 96):
        ext_airlock(g, 204, y, None, "Escape Airlock")
    # cargo
    port(11, 126, 'name = "Cargo Bay"; dir = 8; width = 12; height = 7; id = "supply_home"; dwidth = 5')
    for y in (126, 124):
        through(12, y, 14, "31", "Supply Dock Airlock")
    # mining
    port(11, 155, 'name = "mining shuttle bay"; dir = 8; width = 7; height = 5; id = "mining_home"; dwidth = 3; '
                  'roundstart_template = /datum/map_template/shuttle/mining/box')
    through(12, 155, 14, "48", "Mining Dock Airlock")
    # labour camp
    port(11, 74, 'name = "fore bay 1"; dir = 8; width = 9; height = 5; id = "laborcamp_home"; dwidth = 2; '
                 'roundstart_template = /datum/map_template/shuttle/labour/box')
    for y in (74, 70):
        through(12, y, 14, "2", "Labor Shuttle Airlock")
    # escape pods
    port(190, 19, 'name = "escape pod loader"; width = 3; height = 4; dwidth = 1; '
                  'roundstart_template = /datum/map_template/shuttle/escape_pod/default')
    through_v(190, 20, 22, None, "Escape Pod Airlock")
    port(203, 125, 'name = "escape pod loader"; dir = 4; width = 3; height = 4; dwidth = 1; '
                   'roundstart_template = /datum/map_template/shuttle/escape_pod/default')
    through(202, 125, 200, None, "Escape Pod Airlock")
    for i, (x, y, d) in enumerate(((196, 10, 1), (214, 128, 4), (176, 10, 1), (214, 140, 4))):
        g[x, y].objs.append('/obj/docking_port/stationary/random{name = "lavaland"; dir = %d; id = "pod_lavaland%d"}' % (d, i + 1))
    # other external airlocks
    through(134, 48, 132, "18", "EVA Airlock")
    ext_airlock(g, 136, 180, "10;13", "Engineering External Access")
    ext_airlock(g, 76, 178, "24;13", "Atmospherics External Access")
    return P


def outside(g):
    rnd = random.Random(11)
    # solar fields: panels on solar floor, catwalk lanes, all cabled
    for (name, r), cw in zip(L.SOLARS, L.CATWALKS):
        x0, y0, x1, y1 = r
        horiz = (x1 - x0) >= (y1 - y0)
        area = RD.SOLAR_AREA[name]
        mid = (y0 + y1) // 2 if horiz else (x0 + x1) // 2
        for x in range(x0, x1):
            for y in range(y0, y1):
                t = g[x, y]
                spine = (y == mid) if horiz else (x == mid)
                # the catwalk from the control room carries on into the field up to the spine
                if horiz and cw[0] <= x < cw[2] and (y - mid) * (cw[1] - mid) >= 0:
                    spine = True
                if not horiz and cw[1] <= y < cw[3] and (x - mid) * (cw[0] - mid) >= 0:
                    spine = True
                lane = ((x - x0) % 4 == 3) if horiz else ((y - y0) % 4 == 3)
                t.area, t.kind, t.indoor = area, "exterior", False
                if spine or lane:
                    t.turf = SPACE
                    t.objs = ["/obj/structure/lattice/catwalk", CABLE]
                else:
                    t.turf = "/turf/open/floor/plasteel/airless/solarpanel"
                    t.objs = ['/obj/machinery/power/solar{id = "%s"; name = "%s"}' % (RD.SOLAR_ID[name], name.replace("array", "Solar Array")), CABLE]
        cx, cy = ((x0 + x1) // 2, mid) if horiz else (mid, (y0 + y1) // 2)
        # tracker at the far end of the spine
        tx, ty = (x1 - 1, mid) if horiz else (mid, y1 - 1)
        if name.startswith("NE") or name.startswith("SE"):
            tx, ty = (x1 - 1, mid) if horiz else (mid, y0)
        g[tx, ty].turf = "/turf/open/floor/plasteel/airless/solarpanel"
        g[tx, ty].objs = ["/obj/machinery/power/tracker", CABLE]
    for r in L.CATWALKS:
        for x in range(r[0], r[2]):
            for y in range(r[1], r[3]):
                t = g[x, y]
                if t.kind == "space":
                    t.objs = ["/obj/structure/lattice/catwalk", CABLE]
                    t.area, t.kind = A_NEAR, "exterior"
    # asteroids
    for cx, cy, rr in L.ASTEROIDS:
        for x in range(cx - rr - 1, cx + rr + 2):
            for y in range(cy - rr - 1, cy + rr + 2):
                d2 = (x - cx) ** 2 + (y - cy) ** 2
                lim = (rr + rnd.uniform(-1.2, 0.4)) ** 2
                if d2 <= lim and g[x, y].kind == "space" and g.inb(x, y):
                    t = g[x, y]
                    t.turf, t.kind = "/turf/closed/mineral/random/low_chance", "rock"
    # derelict: a gutted room, broken walls, loose lattice
    for name, r in L.DERELICTS:
        x0, y0, x1, y1 = r
        for x in range(x0, x1):
            for y in range(y0, y1):
                t = g[x, y]
                edge = x in (x0, x1 - 1) or y in (y0, y1 - 1)
                if edge:
                    if rnd.random() < 0.75:
                        t.turf, t.kind = "/turf/closed/wall/r_wall/rust", "wall"
                    else:
                        t.objs = ["/obj/structure/lattice"]
                elif rnd.random() < 0.85:
                    t.turf, t.kind = "/turf/open/floor/plating/airless", "exterior"
                    if rnd.random() < 0.06:
                        t.objs = [rnd.choice(["/obj/structure/girder", "/obj/item/stack/rods",
                                              "/obj/structure/grille/broken", "/obj/item/shard"])]
                t.area = A_NEAR
        for _ in range(22):
            x = rnd.randrange(x0 - 6, x1 + 6)
            y = rnd.randrange(y0 - 5, y1 + 5)
            if g[x, y].kind == "space":
                g[x, y].objs = ["/obj/structure/lattice"]
                g[x, y].area = A_NEAR


# ---------------------------------------------------------------- write
def write(g, path):
    mp = D.Map(W, W)
    for dmx in range(1, W + 1):
        for dmy in range(1, W + 1):
            lx, ly = dmx - OX, W - dmy - OY
            t = g.t.get((lx, ly))
            if t is None:
                mp.tiles[(dmx, dmy)] = [SPACE, A_SPACE]
            else:
                mp.tiles[(dmx, dmy)] = list(t.objs) + [t.turf, t.area]
    return D.write(mp, path)


STATS_WALK = {}
ACC_RE = __import__("re").compile(r'req_(one_)?access_txt = "([^"]*)"')


def walk_check(g, problems, access=None, label="all access"):
    """Walk the tiles from Arrivals with an access set (None = everything).
    Returns the rooms and maint tiles that can't be reached."""
    start = next(p for p, t in g.t.items() if t.owner == ("room", "Arrivals") and t.kind == "floor")

    def passable(p):
        t = g.t.get(p)
        if t is None:
            return False
        if t.kind == "floor":
            return t.indoor and not t.dense or (t.indoor and t.kind == "floor")
        if t.kind != "door":
            return False
        for o in t.objs:
            if "/obj/machinery/door/window" in o:
                return False
            m = ACC_RE.search(o)
            if m and access is not None and m.group(2) not in ("", "0"):
                need = [x.strip() for x in m.group(2).split(";") if x.strip()]
                if m.group(1):
                    if not any(n in access for n in need):
                        return False
                elif not all(n in access for n in need):
                    return False
        return True
    seen = {start}
    todo = [start]
    while todo:
        x, y = todo.pop()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + dx, y + dy)
            if q not in seen and passable(q):
                seen.add(q)
                todo.append(q)
    missed_rooms = set()
    missed_maint = 0
    for p, t in g.t.items():
        if t.kind == "floor" and t.indoor and p not in seen and t.owner:
            if t.owner[0] == "chunk":
                STATS_WALK[label] = STATS_WALK.get(label, 0) + 1  # Hippie's own sealed pockets
            elif t.owner[0] in ("maint", "tunnel"):
                missed_maint += 1
            else:
                missed_rooms.add(t.owner[1])
    return missed_rooms, missed_maint


def airtight(g, problems):
    """Flood from the map edge through anything air passes; report indoor tiles reached."""
    seen = set()
    start = [(g.xmin, g.ymin)]
    todo = list(start)
    seen.update(start)
    leaks = []
    while todo:
        x, y = todo.pop()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if not g.inb(nx, ny) or (nx, ny) in seen:
                continue
            t = g.t.get((nx, ny))
            if t is not None and t.kind in ("wall", "window", "door", "rock"):
                continue
            seen.add((nx, ny))
            if t is not None and t.indoor and t.kind == "floor":
                leaks.append((nx, ny, t.area))
                continue
            todo.append((nx, ny))
    for x, y, a in leaks[:20]:
        problems.append("air leak at %d,%d (%s)" % (x, y, a))
    return len(leaks)


def main():
    problems = []
    g = Grid()
    doors, door_tiles = build_shell(g, problems)
    maint_doors(g, door_tiles)
    hull(g)
    ports = docks(g, problems)
    engine_tiles, sealed = paste_engine(g, problems)
    engine_doors(g, problems)
    print("engine: %d tiles pasted from Hippie, %d of our tiles walled against its space" % (len(engine_tiles), sealed))
    xeno_tiles, xwalled = paste_xeno(g, problems)
    door_tiles[L.XENO_DOOR] = ("Xeno Airlock", "xeno", "")
    hull(g)  # anything of the lab's that faces open space gets a wall
    print("xenobiology: %d tiles pasted from Hippie, %d outside doors walled" % (len(xeno_tiles), xwalled))
    door_tiles[L.ENGINE_DOOR] = ("Engine Airlock", "engine", "")
    added, walled = connect_maint(g, door_tiles, problems)
    print("maint: %d doors added to cut-off stretches, %d pockets walled up" % (added, walled))
    outside(g)
    furnish.infrastructure(g, door_tiles, problems)
    furnish.contents(g, door_tiles, problems)
    leaks = airtight(g, problems)
    rooms_missed, maint_missed = walk_check(g, problems)
    if rooms_missed or maint_missed:
        problems.append("with all access, can't reach rooms %s and %d maint tiles" % (sorted(rooms_missed), maint_missed))
    eng = {"10", "11", "23", "12", "13", "32", "64"}
    rm, mm = walk_check(g, problems, eng, "engineer")
    print("engineer access can't reach:", sorted(rm), "and", mm, "maint tiles")
    out_dir = os.path.join(ROOT, "_maps", "map_files", "Perihelion")
    os.makedirs(out_dir, exist_ok=True)
    keys, klen = write(g, os.path.join(out_dir, "perihelion.dmm"))
    with open(os.path.join(ROOT, "_maps", "perihelion.json"), "w", newline="\n") as f:
        json.dump({
            "map_name": "Perihelion Station",
            "map_path": "map_files/Perihelion",
            "map_file": "perihelion.dmm",
            "shuttles": {"emergency": "emergency_box", "ferry": "ferry_fancy",
                         "cargo": "cargo_box", "whiteship": "whiteship_meta"},
        }, f, indent=4)
        f.write("\n")
    print("wrote perihelion.dmm: %d tile kinds, key length %d, %d ports, %d air leaks" % (keys, klen, len(ports), leaks))
    print("stats:", furnish.STATS, "engine tiles nobody can walk to:", STATS_WALK.get("all access", 0))
    for p in problems:
        print("PROBLEM:", p)
    return g


if __name__ == "__main__":
    main()
