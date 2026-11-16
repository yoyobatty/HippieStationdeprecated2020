"""mapforge builder: turns a blueprint (hand-drawn ASCII layout + room/legend tables) into finished map tiles.

The designer draws the rooms and the furniture. The builder does what a careful human mapper does after that:
areas, turfs, windows, airlocks with firelocks on area borders, chairs facing their tables, machines facing the
room, one APC per area near the power line, air and fire alarms by the doors, light switches, lights laid out to
cover the floor, vents and scrubbers spread over each room with pipe trees routed under the floor to the station's
networks at the zone edge, and cable from every APC to the grid. Disposals inside the zone are carried over.

Blueprint module attributes (see blueprints/*.py):
    NAME, ORIGIN=(x, y) of the layout's bottom-left char, LAYOUT, ROOMS (same size), ROOMDEFS, LEGEND,
    optional BASE (map path), CARRY (object path prefixes copied over from the old zone tiles), DECALS, NOTES.
"""
import heapq
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from forge import dmm  # noqa: E402
from forge import kit  # noqa: E402
from forge.kit import N, S, E, W, CARD, DELTA, OPP  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))

BUILTIN = {
    "#": {"turf": "wall"},
    "R": {"turf": "rwall"},
    "=": {"turf": "window"},
    "%": {"turf": "rwindow"},
    ".": {},
}


def grid_lines(text):
    lines = text.strip("\n").split("\n")
    w = max(len(l) for l in lines)
    return [l.ljust(w, "~") for l in lines]


class Problem(Exception):
    pass


class Builder:
    def __init__(self, bp, base=None):
        self.bp = bp
        self.base_path = base or getattr(bp, "BASE", os.path.join(ROOT, "_maps", "map_files", "HippieStation", "hippiestation.dmm"))
        if self.base_path == "blank":
            lay0 = grid_lines(bp.LAYOUT)
            self.m = blank_map(bp.ORIGIN[0] + len(lay0[0]) + 1, bp.ORIGIN[1] + len(lay0) + 1)
        else:
            self.m = dmm.read(self.base_path)
        self.orig = {}  # zone pos -> original tile copy
        self.notes = []
        self.warn = []
        self.faces = set()  # (x, y, side) wall faces used by mounts
        self.outside_edits = []  # kept tiles we had to touch (dead stubs trimmed)
        self.keep_infra = getattr(bp, "INFRA", "build") == "keep"  # remodel: keep pipes, power, lights, wall pieces
        self.template_tiles = set()  # tiles a whole human-made room was fitted onto: they bring their own floor style
        self.trimmed = []
        self.legend = dict(BUILTIN)
        self.legend.update(getattr(bp, "LEGEND", {}))
        self.roomdefs = bp.ROOMDEFS
        lay = grid_lines(bp.LAYOUT)
        rooms = grid_lines(bp.ROOMS)
        if len(lay) != len(rooms) or len(lay[0]) != len(rooms[0]):
            raise Problem("LAYOUT is %dx%d but ROOMS is %dx%d" % (len(lay[0]), len(lay), len(rooms[0]), len(rooms)))
        self.h, self.w = len(lay), len(lay[0])
        ox, oy = bp.ORIGIN
        self.ch = {}
        self.room = {}
        for r, (line, rline) in enumerate(zip(lay, rooms)):
            y = oy + self.h - 1 - r
            for c, chr_ in enumerate(line):
                x = ox + c
                if chr_ == "~":
                    continue
                rc_ = rooms[r][c]
                rl_ = self.roomdefs.get(rc_, {}).get("legend", {})
                if chr_ not in self.legend and chr_ not in rl_:
                    raise Problem("unknown layout char %r at %d,%d" % (chr_, x, y))
                self.ch[(x, y)] = chr_
                rc = rline[c]
                if rc in self.roomdefs:
                    self.room[(x, y)] = rc
        self.zone = set(self.ch)
        if getattr(bp, "THIN_WALLS", True):
            self.thin_walls()
            self.close_diagonals()

    def close_diagonals(self):
        """Walls join edge to edge: where two wall pieces touch only at a corner, one of the two open tiles between
        them becomes wall (a plain layout floor tile, the one with fewer open neighbours: the corner of a room)."""
        def solid(p):
            k = self.legend_kind(p) if p in self.ch else None
            if k is not None:
                if k == "wall":
                    return True
                if k == "barrier":
                    objs = []
                    rc = self.room.get(p)
                    sp = (self.roomdefs[rc].get("legend") or {}).get(self.ch[p]) if rc else None
                    sp = sp if sp is not None else self.legend.get(self.ch[p], {})
                    objs = [e if isinstance(e, str) else e[0] for e in sp.get("obj", [])]
                    return not any(o.startswith("/obj/machinery/door/window") for o in objs)
                return False
            t = self.m.get(*p)
            return t is not None and (t.tpath.startswith("/turf/closed") or t.has("/obj/effect/spawner/structure/window")
                                      or t.has("/obj/machinery/door/airlock"))

        def plain(p):
            return p in self.ch and self.ch[p] == "."

        def open_n(p):
            return sum(1 for d in CARD if not solid(self.nb(p, d)))
        for _ in range(3):
            fixed = False
            for p in sorted(self.ch):
                if not solid(p):
                    continue
                for dx, dy in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
                    q = (p[0] + dx, p[1] + dy)
                    a, c = (p[0] + dx, p[1]), (p[0], p[1] + dy)
                    if solid(q) and not solid(a) and not solid(c):
                        def doubles(x):
                            # would walling x make floor, wall, wall, floor in a line?
                            for d in CARD:
                                n1, n2 = self.nb(x, d), self.nb(self.nb(x, d), d)
                                back = self.nb(x, OPP[d])
                                if solid(n1) and not solid(n2) and not solid(back):
                                    return True
                            return False
                        cands = [x for x in (a, c) if plain(x) and not doubles(x)]
                        if not cands:
                            self.warn.append("walls at %d,%d and %d,%d meet only at a corner" % (p[0], p[1], q[0], q[1]))
                        if cands:
                            x = min(cands, key=open_n)
                            self.ch[x] = "#"
                            self.room.pop(x, None)
                            fixed = True
            if not fixed:
                break

    def thin_walls(self):
        """No doubled walls: where floor, wall, wall, floor run in a line and one of the two walls is a plain wall
        drawn in this layout, it becomes floor of the room beside it (a room stopped one tile short)."""
        def k(p):
            if p in self.ch:
                return self.legend_kind(p)
            t = self.m.get(*p)
            if t is None or t.tpath.startswith("/turf/open/space"):
                return "space"
            if t.has("/obj/machinery/door") or t.has("/obj/effect/spawner/structure/window") or t.has("/obj/structure/grille"):
                return "barrier"
            return "wall" if t.tpath.startswith("/turf/closed") else "floor"
        changed = True
        while changed:
            changed = False
            for p in sorted(self.ch):
                if self.ch[p] != "#":
                    continue
                for d in CARD:
                    a, w2, b2 = self.nb(p, OPP[d]), self.nb(p, d), self.nb(self.nb(p, d), d)
                    if k(a) == "floor" and k(w2) == "wall" and k(b2) == "floor" and a in self.room:
                        # never a one-tile dent: the room must widen along the wall (a floor beside p, or a
                        # neighbouring doubled wall that thins too), or the walls round the dent meet at corners
                        side = [self.nb(p, s) for s in CARD if s not in (d, OPP[d])]
                        if not any(k(q) == "floor" or (self.ch.get(q) == "#" and k(self.nb(q, d)) == "wall"
                                                      and k(self.nb(self.nb(q, d), d)) == "floor"
                                                      and k(self.nb(q, OPP[d])) == "floor") for q in side):
                            continue
                        # nor two walls left touching only at a corner (p's two wall neighbours round an open
                        # diagonal)
                        if any(k((p[0] + dx, p[1])) == "wall" and k((p[0], p[1] + dy)) == "wall"
                               and k((p[0] + dx, p[1] + dy)) not in ("wall", "space") for dx in (-1, 1) for dy in (-1, 1)):
                            continue
                        self.ch[p] = "."
                        self.room[p] = self.room[a]
                        changed = True
                        break

    def legend_kind(self, p):
        rc = self.room.get(p)
        spec = None
        if rc:
            rl = self.roomdefs[rc].get("legend")
            if rl and self.ch[p] in rl:
                spec = rl[self.ch[p]]
        spec = spec if spec is not None else self.legend.get(self.ch[p], {})
        objs = [e if isinstance(e, str) else e[0] for e in spec.get("obj", [])]
        if any(o.startswith("/obj/machinery/door") for o in objs):
            return "barrier"
        t = spec.get("turf", "floor")
        return {"wall": "wall", "rwall": "wall", "window": "barrier", "rwindow": "barrier"}.get(t, "floor")

    # ------------------------------------------------------------------ helpers
    def t(self, x, y):
        return self.m.get(x, y)

    def spec(self, p):
        rc = self.room.get(p)
        if rc:
            rl = self.roomdefs[rc].get("legend")
            if rl and self.ch[p] in rl:
                return rl[self.ch[p]]
        return self.legend[self.ch[p]]

    def kind(self, p):
        """wall / rwall / window / rwindow / floor for zone tiles; from the map outside."""
        if p in self.ch:
            s = self.spec(p)
            return s.get("turf", "floor")
        t = self.t(*p)
        if t is None:
            return "void"
        if t.tpath.startswith("/turf/closed"):
            return "wall"
        if t.has("/obj/effect/spawner/structure/window") or t.has("/obj/structure/grille"):
            return "window"
        if t.tpath.startswith("/turf/open/space"):
            return "space"
        return "floor"

    def solid(self, p):
        return self.kind(p) in ("wall", "rwall")

    def is_floor(self, p):
        return self.kind(p) == "floor"

    def area_of(self, p):
        rc = self.room.get(p)
        return self.roomdefs[rc]["area"] if rc else None

    def nb(self, p, d=None):
        if d is None:  # nb((tile, dir))
            p, d = p
        dx, dy = DELTA[d]
        return (p[0] + dx, p[1] + dy)

    def room_tiles(self, area):
        return [p for p in self.zone if self.area_of(p) == area]

    def floors_of(self, area):
        return [p for p in self.room_tiles(area) if self.is_floor(p)]

    # ------------------------------------------------------------------ passes
    def run(self):
        self.capture()
        self.find_ports()
        self.wipe()
        self.structure()
        self.furniture()
        self.furnished = set()
        self.auto_furnish()
        self.mirror_rooms()
        self.place_kept_items()
        from forge import orient
        for q, what, gone in orient.keep_front_clear(self, self.furnished):
            self.notes.append("cleared %d,%d in front of %s (%s)" % (q[0], q[1], what.rsplit("/", 1)[-1],
                                                                     ", ".join(g.rsplit("/", 1)[-1] for g in gone)))
        self.doors()
        self.mounts_explicit()
        self.decor_mounts(functional=True)
        if getattr(self.bp, "DISPOSALS", "carry") == "route":
            self.route_disposals()
        if not self.keep_infra:
            for area in self.areas():
                self.mounts_area(area)
            for area in self.areas():
                self.lights(area)
        self.decor_mounts(functional=False)
        if getattr(self.bp, "REHANG", True):
            self.rehang_wall_pieces()
        if getattr(self.bp, "ATMOS", True) and not self.keep_infra:
            self.atmos()
        else:
            self.vents = {"supply": [], "scrubbers": []}
            self.pipe_tiles = {}
        if getattr(self.bp, "POWER", True) and not self.keep_infra:
            self.power()
        if self.keep_infra:
            self.settle_landmarks()
        self.decals()
        if getattr(self.bp, "STYLE", None) == "meta":
            from forge import dress
            self.notes += dress.dress(self, seed=getattr(self.bp, "SEED", 1))
        self.validate_types()
        return self

    def validate_types(self):
        from forge import typeindex
        bad = set()
        for p in self.zone:
            t = self.t(*p)
            for a in t.objs + [t.turf, t.area]:
                if a is not None and not typeindex.known(a.path):
                    bad.add(a.path)
        for b in sorted(bad):
            self.warn.append("unknown type %s" % b)

    def areas(self):
        seen = []
        for rc, rd in self.roomdefs.items():
            if rd["area"] not in seen and self.floors_of(rd["area"]):
                seen.append(rd["area"])
        return seen

    def roomdef_for_area(self, area):
        for rc, rd in self.roomdefs.items():
            if rd["area"] == area and rd.get("main", True):
                return rd
        for rc, rd in self.roomdefs.items():
            if rd["area"] == area:
                return rd

    def capture(self):
        for p in self.zone:
            self.orig[p] = self.t(*p).copy()

    def find_ports(self):
        """Station networks that cross into the zone: (class) -> list of (zone tile, side toward outside)."""
        self.ports = {"supply": [], "scrubbers": [], "cable": []}
        for p in self.zone:
            for d in CARD:
                q = self.nb(p, d)
                if q in self.zone:
                    continue
                kt = self.t(*q)
                if kt is None:
                    continue
                for a in kt.objs:
                    cls = kit.pipe_class(a.path)
                    if cls and "/pipe/" in a.path and kit.pipe_mask(a) & OPP[d]:
                        self.ports[cls].append((p, d))
                if any(kit.is_cable(o) for o in kt.objs) and any(kit.is_cable(o) for o in self.orig[p].objs):
                    self.ports["cable"].append((p, d))
        # kept cables next to the zone that did NOT connect in: new cable must not touch them
        self.cable_fence = set()
        for p in self.zone:
            for d in CARD:
                q = self.nb(p, d)
                if q not in self.zone and self.t(*q) and any(kit.is_cable(o) for o in self.t(*q).objs) and (p, d) not in self.ports["cable"]:
                    self.cable_fence.add(p)
        for cls, ps in self.ports.items():
            self.notes.append("ports %s: %s" % (cls, ", ".join("%d,%d%s" % (p[0], p[1], kit.NAME[d][0]) for p, d in ps)))

    def wipe(self):
        carry = tuple(getattr(self.bp, "CARRY", kit.DISPOSAL_PREFIX))
        if getattr(self.bp, "DISPOSALS", "carry") == "route":
            carry = tuple(c for c in carry if not c.startswith(kit.DISPOSAL_PREFIX)) or ("/nothing",)
        for p in self.zone:
            o = self.orig[p]
            nt = dmm.Tile()
            nt.objs = [a.copy() for a in o.objs if a.path.startswith(carry)]
            if self.keep_infra:
                nt.objs += [a.copy() for a in o.objs if not a.path.startswith(carry) and (
                    a.path.startswith(KEEP_INFRA) or abs(a.num("pixel_x")) >= 16 or abs(a.num("pixel_y")) >= 16)]
                nt.turf = o.turf.copy() if o.turf else None
            # a wall that stays a wall keeps its signs and displays (rehang_wall_pieces moves them in front of it)
            if o.tpath.startswith("/turf/closed") and self.kind(p) in ("wall", "rwall"):
                nt.objs += [a.copy() for a in o.objs if a.path.startswith(self.WALL_PIECES)]
            area = self.area_of(p) or self.wall_area(p) or o.apath
            nt.area = dmm.Atom(area)
            self.m.set(p[0], p[1], nt)

    def route_disposals(self):
        """Blueprint DISPOSALS = "route": bins (legend dest=...) and outlets (legend outlet=key, throw=dir) get lines
        of their own; the station loop's through tiles stay (forge/disposal_route.py)."""
        from forge import disposal_route
        self.orig_map = dmm.read(self.base_path)
        outlets, reqs = {}, []
        for p in sorted(self.zone):
            sp = self.spec(p)
            if sp.get("outlet"):
                outlets[sp["outlet"]] = (p, sp.get("throw", 2))
        for p in sorted(self.zone):
            sp = self.spec(p)
            objs = [e if isinstance(e, str) else e[0] for e in sp.get("obj", [])]
            if any(o.startswith("/obj/machinery/disposal/bin") for o in objs):
                dest = sp.get("dest", "station")
                if isinstance(dest, tuple) and dest[0] == "outlet":
                    o = outlets.get(dest[1])
                    if not o:
                        self.warn.append("disposals: bin at %d,%d wants outlet %r, none in the layout" % (p[0], p[1], dest[1]))
                        continue
                    dest = ("outlet", o[0], o[1])
                reqs.append((p, dest))
        notes, probs = disposal_route.route(self, reqs)
        self.notes += notes
        self.warn += probs

    def place_kept_items(self):
        """keep_items=[atom text] on a room: one-of-a-kind items and pets go back into the same room, on a free table
        if there is one (items) or free floor."""
        placed = 0
        for rc, rd in self.roomdefs.items():
            for text in rd.get("keep_items", ()):
                a = dmm.Atom.parse(text)
                tiles = sorted(p for p in self.zone if self.room.get(p) == rc and self.is_floor(p))
                tables = [p for p in tiles if self.t(*p).has("/obj/structure/table")
                          and not any(o.path.startswith("/obj/item") for o in self.t(*p).objs)]
                free = [p for p in tiles if not kit.dense(self.t(*p).objs) and not self.t(*p).has("/obj/machinery/door")]
                spot = tables[0] if (tables and a.path.startswith("/obj/item")) else (free[len(free) // 2] if free else None)
                if not spot:
                    self.warn.append("%s: nowhere to put %s" % (rd.get("name", rc), a.path))
                    continue
                self.t(*spot).objs.append(a)
                placed += 1
        if placed:
            self.notes.append("put back %d one-of-a-kind items" % placed)

    def settle_landmarks(self):
        """Kept landmarks (job starts, event spawns) that new furniture now covers move to the nearest free floor of
        the same room: nobody should spawn on a table."""
        moved = 0
        for p in sorted(self.zone):
            t = self.t(*p)
            lms = [o for o in t.objs if o.path.startswith("/obj/effect/landmark")]
            if not lms or not kit.dense(t.objs):
                continue
            room = [q for q in self.zone if self.room.get(q) == self.room.get(p) and self.is_floor(q)
                    and not kit.dense(self.t(*q).objs) and not self.t(*q).has("/obj/machinery/door")]
            if not room:
                continue
            q = min(room, key=lambda q: (abs(q[0] - p[0]) + abs(q[1] - p[1]), q))
            for o in lms:
                t.objs.remove(o)
                self.t(*q).objs.append(o)
            moved += 1
        if moved:
            self.notes.append("moved %d landmarks off new furniture" % moved)

    def wall_area(self, p):
        counts = {}
        for d in CARD:
            a = self.area_of(self.nb(p, d))
            if a:
                counts[a] = counts.get(a, 0) + 1
        if counts:
            return max(counts, key=counts.get)
        o = self.orig[p]
        return o.apath

    def structure(self):
        for p in self.zone:
            t = self.t(*p)
            k = self.kind(p)
            s = self.spec(p)
            if k == "wall":
                t.turf = dmm.Atom(kit.WALL)
            elif k == "rwall":
                t.turf = dmm.Atom(kit.RWALL)
            elif k in ("window", "rwindow"):
                t.turf = dmm.Atom(kit.PLATING)
                t.objs.append(dmm.Atom(kit.RWINDOW if k == "rwindow" else kit.WINDOW))
            else:
                rc = self.room.get(p)
                # a remodelled room gets one even floor (its main one): old patches were laid out for old furniture
                if self.keep_infra and t.turf is not None and t.turf.path.startswith("/turf/open") and not s.get("floor"):
                    if rc and t.turf.path.startswith("/turf/open/floor/plasteel") and self.roomdefs[rc]["floor"].startswith("/turf/open/floor/plasteel"):
                        t.turf = dmm.Atom(self.roomdefs[rc]["floor"])
                    continue
                floor = s.get("floor") or (self.roomdefs[rc]["floor"] if rc else kit.PLATING)
                t.turf = dmm.Atom(floor) if isinstance(floor, str) else dmm.Atom(floor[0], floor[1])

    def auto_furnish(self):
        """Rooms with furnish=dict(kind=..., seed=...) get real clusters from the corpus on their free floor."""
        from forge import furnish
        doors = set()
        for p in self.zone:
            objs = [e if isinstance(e, str) else e[0] for e in self.spec(p).get("obj", [])]
            if any(o.startswith("/obj/machinery/door") for o in objs):
                doors.add(p)
        for p in self.zone:
            for d in CARD:
                q = self.nb(p, d)
                if q not in self.zone and self.t(*q) is not None and self.t(*q).has("/obj/machinery/door"):
                    doors.add(q)
        self.furnish_log = []
        for rc, rd in self.roomdefs.items():
            f = rd.get("furnish")
            if rd.get("mirror_of"):
                continue  # done after its twin
            if not f:
                continue
            floor = {p for p in self.zone if self.room.get(p) == rc and self.is_floor(p) and self.ch[p] == "."
                     and not kit.dense(self.t(*p).objs)}
            touching = {d for d in doors if any(self.nb(d, dd) in floor for dd in CARD)}
            log = []
            if f.get("mode") == "template" and self.template_room(rc, rd, floor):
                continue
            present = {o.path for q in self.zone if self.room.get(q) == rc for o in self.t(*q).objs}
            # a corridor (most tiles have walls close on both sides) gets only its required pieces, nothing decorative
            wide = sum(1 for q in floor if sum(1 for d in CARD if self.nb(q, d) in floor) >= 3)
            bw = max(q[0] for q in floor) - min(q[0] for q in floor) + 1 if floor else 1
            bh = max(q[1] for q in floor) - min(q[1] for q in floor) + 1 if floor else 1
            # corridors: walls close on both sides, or a network filling little of its bounding box
            corridor = len(floor) >= 12 and (wide < 0.45 * len(floor) or len(floor) < 0.35 * bw * bh)
            # the use tile in front of every hand-placed piece stays free (the side away from its wall, or its facing)
            reserved = set()
            for q in self.zone:
                if self.room.get(q) != rc or not kit.dense(self.t(*q).objs):
                    continue
                walls = [d for d in CARD if self.solid(self.nb(q, d))]
                for o in self.t(*q).objs:
                    dd = o.num("dir", 0)
                    if dd in kit.OPP and o.get("dir") is not None:
                        reserved.add(self.nb(q, dd))
                if len(walls) == 1:
                    reserved.add(self.nb(q, kit.OPP[walls[0]]))
                elif walls:
                    reserved |= {self.nb(q, d) for d in CARD if d not in walls}
            got = furnish.furnish(floor, lambda q: self.kind(q) in ("wall", "rwall", "window", "rwindow", "void")
                                  or (q not in floor and q not in self.zone and self.kind(q) != "floor"), touching, f["kind"], seed=f.get("seed", 1),
                                  require=f.get("require", ()), exclude=f.get("exclude", ()), log=log,
                                  density=0.0 if corridor else f.get("density"),
                                  present=present, reserved=reserved,
                                  glass=lambda q: self.kind(q) in ("window", "rwindow"))
            for p, atoms in got.items():
                for a in atoms:
                    at = dmm.Atom.parse(a)
                    if abs(at.num("pixel_x")) >= 16 or abs(at.num("pixel_y")) >= 16:
                        from forge.corpus import mount_side
                        side = mount_side(at)
                        # a carried wall piece needs a real wall here (its source may have had wall where we have glass)
                        if not self.solid(self.nb(p, side)) or (p[0], p[1], side) in self.faces:
                            continue
                        self.faces.add((p[0], p[1], side))  # it holds that face
                    self.t(*p).objs.append(at)
                self.furnished.add(p)
            from forge import orient
            turned = orient.fix_facing(self, set(got))
            turned += orient.mirror_pairs(self, floor)
            self.notes.append("%s: furnished %d of %d tiles from %d corpus clusters, %d turned to face like real maps"
                              % (rd.get("name", rc), len(got), len(floor), len(log), len(turned)))
            self.furnish_log += ["  " + l for l in log]
            for l in log:
                if l.startswith("COULD NOT"):
                    self.warn.append("%s: %s" % (rd.get("name", rc), l.lower()))

    def template_room(self, rc, rd, floor):
        """Fit a whole human-made room of this type onto the room (forge/rooms.py); the first fit that passes the
        rules wins. Missing required machines are then added by the furnisher. False if nothing fits."""
        from forge import rooms, furnish
        f = rd["furnish"]
        edges = {}
        for p in floor:
            for d in CARD:
                q = self.nb(p, d)
                if q in floor:
                    continue
                qt = self.t(*q)
                if qt is None or self.kind(q) in ("wall", "rwall"):
                    edges[(p, d)] = "wall"
                else:
                    edges[(p, d)] = rooms.edge_kind(qt)
        need = []
        for r in f.get("require", ()):
            need.append((r, 1) if isinstance(r, str) else (r[0], r[1]))
        x0 = min(p[0] for p in floor)
        y0 = min(p[1] for p in floor)
        # the old room as (position, furniture) pairs: a twin has the same things in the same places
        own = {(p[0] - x0, p[1] - y0, o.path) for p in floor for o in self.orig.get(p, dmm.Tile()).objs
               if o.path.startswith(("/obj/structure", "/obj/machinery")) and not o.path.startswith(rooms.SKIP)}
        base_name = os.path.basename(self.base_path)

        def skip(r):
            # the room itself (or its twin on a map that shares it, like Box for Hippie) is not a remodel
            if r["map"] == base_name:
                return True
            sig = set()
            for key, objs in r["cells"].items():
                x, y = map(int, key.split(","))
                for o in objs[1:]:
                    pth = o.split("{")[0]
                    if pth.startswith(("/obj/structure", "/obj/machinery")):
                        sig.add((x, y, pth))
            return len(sig) > 3 and len(sig & own) > 0.6 * len(sig)
        cands = rooms.fit(floor, edges, f["kind"], required=need, skip=skip, limit=400)
        dense = lambda o: kit.is_dense_atom(dmm.Atom.parse(o))  # noqa: E731
        room_doors = {self.nb(p, d) for (p, d), k in edges.items() if k == "door"}
        tried = 0
        for score, place, src, lost in cands:
            ok, why = rooms.valid(place, floor, edges, dense)
            if not ok:
                continue
            tried += 1
            if tried > 25:
                break
            # apply on a snapshot so a candidate that fails after its top-up can be undone
            snap = {p: self.t(*p).copy() for p in floor}
            faces0, furnished0, warn0 = set(self.faces), set(self.furnished), list(self.warn)
            for p, objs in place.items():
                t = self.t(*p)
                t.turf = dmm.Atom.parse(objs[0]) if objs[0].startswith("/turf/open") else t.turf
                t.objs = [o for o in t.objs if not o.path.startswith("/obj/effect/turf_decal")]
                self.add_atoms(p, objs[1:])
                self.furnished.add(p)
            if lost:
                free = {p for p in floor if not kit.dense(self.t(*p).objs)}
                present = {o.path for p in floor for o in self.t(*p).objs}
                log = []
                got = furnish.furnish(free, lambda q: self.kind(q) in ("wall", "rwall", "window", "rwindow", "void")
                                      or (q not in floor and self.kind(q) != "floor"),
                                      room_doors, f["kind"], density=0.0, require=[(k, v) for k, v in lost.items()],
                                      log=log, present=present, glass=lambda q: self.kind(q) in ("window", "rwindow"))
                for p, atoms in got.items():
                    self.add_atoms(p, atoms)
                    self.furnished.add(p)
                for l in log:
                    if l.startswith("COULD NOT"):
                        self.warn.append("%s: %s" % (rd.get("name", rc), l.lower()))
            # the finished room must pass the same rules, else undo it and try the next template
            final = {p: [self.t(*p).turf.path] + [o.text() for o in self.t(*p).objs] for p in floor}
            ok, why = rooms.valid(final, floor, edges, dense)
            if not ok:
                for p, tcopy in snap.items():
                    self.m.set(p[0], p[1], tcopy)
                self.faces, self.furnished, self.warn = faces0, furnished0, warn0
                continue
            self.notes.append("%s: whole room from %s (score %.0f)" % (rd.get("name", rc), src, score))
            self.template_tiles |= set(floor)
            return True
        self.notes.append("%s: no whole-room template fits, falling back to clusters" % rd.get("name", rc))
        return False

    def add_atoms(self, p, texts):
        """Put atoms on a tile; a wall piece among them goes up only if this tile really has wall on that side."""
        from forge.corpus import mount_side
        for o in texts:
            at = dmm.Atom.parse(o)
            if abs(at.num("pixel_x")) >= 16 or abs(at.num("pixel_y")) >= 16:
                side = mount_side(at)
                if not self.solid(self.nb(p, side)) or (p[0], p[1], side) in self.faces:
                    continue
                self.faces.add((p[0], p[1], side))
            self.t(*p).objs.append(at)

    def mirror_rooms(self):
        """A room with mirror_of=<letter> gets its twin's furniture reflected across the line between them, the way
        side-by-side operating theatres or cells are drawn as mirror copies."""
        def flip_atom(a, horizontal):
            vs = []
            for k, v in a.vars:
                if k == "dir" and v.strip().lstrip("-").isdigit():
                    d = int(v)
                    if horizontal:
                        d = (d & ~12) | (8 if d & 4 else 0) | (4 if d & 8 else 0)
                    else:
                        d = (d & ~3) | (2 if d & 1 else 0) | (1 if d & 2 else 0)
                    v = str(d)
                elif k == ("pixel_x" if horizontal else "pixel_y") and v.strip().lstrip("-").isdigit():
                    v = str(-int(v))
                vs.append((k, v))
            if not a.get("dir") and a.path.startswith(("/obj/structure/chair", "/obj/machinery/computer")) and not horizontal:
                vs.append(("dir", "1"))
            return dmm.Atom(a.path, vs)
        for rc, rd in self.roomdefs.items():
            twin = rd.get("mirror_of")
            if not twin:
                continue
            src = [p for p in self.zone if self.room.get(p) == twin and self.is_floor(p)]
            dst = {p for p in self.zone if self.room.get(p) == rc and self.is_floor(p) and self.ch[p] == "."}
            sx = (min(p[0] for p in src), max(p[0] for p in src))
            sy = (min(p[1] for p in src), max(p[1] for p in src))
            dx_ = (min(p[0] for p in dst), max(p[0] for p in dst))
            horizontal = sy == (min(p[1] for p in dst), max(p[1] for p in dst)) or dx_[0] > sx[1] or dx_[1] < sx[0]
            copied = 0
            for p in src:
                q = (sx[0] + dx_[1] - p[0], p[1]) if horizontal else (p[0], sy[0] + max(p[1] for p in dst) - p[1])
                if q not in dst or p not in self.furnished:
                    continue
                for a in self.t(*p).objs:
                    if a.path.startswith(("/obj/structure/cable", "/obj/machinery/atmospherics", "/obj/structure/disposal",
                                          "/obj/machinery/disposal", "/obj/effect", "/obj/machinery/light", "/obj/machinery/door")):
                        continue
                    if a.path.startswith(("/obj/machinery/power/apc", "/obj/machinery/airalarm", "/obj/machinery/firealarm",
                                          "/obj/machinery/camera", "/obj/machinery/light_switch")):
                        continue
                    na = flip_atom(a, horizontal)
                    self.t(*q).objs.append(na)
                    if abs(na.num("pixel_x")) >= 16 or abs(na.num("pixel_y")) >= 16:
                        from forge.corpus import mount_side
                        self.faces.add((q[0], q[1], mount_side(na)))
                self.furnished.add(q)
                copied += 1
            self.notes.append("%s: mirror copy of %s, %d tiles" % (rd.get("name", rc), self.roomdefs[twin].get("name", twin), copied))

    def furniture(self):
        for p in sorted(self.zone, key=lambda q: (-q[1], q[0])):
            s = self.spec(p)
            for i, entry in enumerate(s.get("obj", [])):
                path, vs = (entry, []) if isinstance(entry, str) else (entry[0], list(entry[1].items()) if isinstance(entry[1], dict) else entry[1])
                vs = [(k, dmm.fmt(v) if not isinstance(v, str) or not v.startswith(("\"", "/", "list(")) and not v.lstrip("-").isdigit() else v) for k, v in vs]
                face = s.get("face")
                if face is not None and i in s.get("face_obj", [0]):
                    d = self.face_dir(p, face)
                    vs = [(k, v) for k, v in vs if k != "dir"]
                    if d is not None and d != 2:
                        vs = [("dir", str(d))] + vs
                self.t(*p).objs.append(dmm.Atom(path, vs))

    def furniture_kind(self, p):
        if p not in self.zone:
            t = self.t(*p)
            return "dense" if t and kit.dense(t.objs) else self.kind(p)
        objs = [e if isinstance(e, str) else e[0] for e in self.spec(p).get("obj", [])]
        if any(o.startswith("/obj/structure/table") for o in objs):
            return "table"
        if any(o.startswith(("/obj/machinery/computer", "/obj/machinery/computer/arcade", "/obj/machinery/computer/slot_machine")) for o in objs):
            return "table"
        if any(o.startswith(kit.DENSE_HINTS) for o in objs):
            return "dense"
        return self.kind(p)

    def face_dir(self, p, face):
        if isinstance(face, int):
            return face
        if face in kit.NAME.values():
            return {v: k for k, v in kit.NAME.items()}[face]
        if face == "table":
            for d in (N, S, E, W):
                if self.furniture_kind(self.nb(p, d)) == "table":
                    return d
            face = "open"
        if face == "open":
            # toward the side with the most open floor beyond it; walls behind
            best, bd = -1, S
            for d in (S, N, E, W):
                q = self.nb(p, d)
                if self.furniture_kind(q) != "floor":
                    continue
                score = 1
                if self.solid(self.nb(p, OPP[d])):
                    score += 2
                q2 = self.nb(q, d)
                if self.furniture_kind(q2) == "floor":
                    score += 1
                if score > best:
                    best, bd = score, d
            return bd
        if face == "wall":
            for d in (N, S, E, W):
                if self.solid(self.nb(p, d)):
                    return d
        return None

    def doors(self):
        for p in self.zone:
            s = self.spec(p)
            objs = [e if isinstance(e, str) else e[0] for e in s.get("obj", [])]
            if not any(o.startswith("/obj/machinery/door/airlock") for o in objs):
                continue
            if s.get("firedoor", True) is False:
                continue
            sides = [self.area_of(self.nb(p, d)) or (self.t(*self.nb(p, d)).apath if self.t(*self.nb(p, d)) else None)
                     for d in CARD if not self.solid(self.nb(p, d))]
            if len(set(a for a in sides if a)) > 1 or s.get("firedoor"):
                self.t(*p).objs.append(dmm.Atom(kit.FIREDOOR))

    # ------------------------------------------------------------------ wall mounts
    def wall_sides(self, p):
        return [d for d in (N, W, E, S) if self.solid(self.nb(p, d)) and (self.nb(p, d) in self.zone or True)]

    def free_faces(self, area, avoid_doors=True):
        out = []
        for p in self.floors_of(area):
            if avoid_doors and self.t(*p).has("/obj/machinery/door"):
                continue
            for d in self.wall_sides(p):
                if (p[0], p[1], d) not in self.faces:
                    out.append((p, d))
        return out

    def mount(self, p, d, kind, path=None, extra=()):
        d0, px, py = kit.MOUNT[kind][d]
        vs = list(extra)
        if d0 is not None:
            vs.append(("dir", str(d0)))
        if px is not None:
            vs.append(("pixel_x", str(px)))
        if py is not None:
            vs.append(("pixel_y", str(py)))
        self.t(*p).objs.append(dmm.Atom(path or kit.MOUNT_PATHS[kind], vs))
        self.faces.add((p[0], p[1], d))

    def mounts_explicit(self):
        for p in self.zone:
            for m in self.spec(p).get("mount", []):
                kind, path, extra = m[0], m[1], list(m[2].items()) if len(m) > 2 else []
                extra = [(k, dmm.fmt(v)) for k, v in extra]
                sides = [d for d in self.wall_sides(p) if (p[0], p[1], d) not in self.faces]
                want = self.spec(p).get("mount_side")
                if want:
                    sides = [{v: k for k, v in kit.NAME.items()}[want]]
                if not sides:
                    self.warn.append("no wall for %s at %d,%d" % (kind, p[0], p[1]))
                    continue
                self.mount(p, sides[0], kind, path, extra)
        # one-off touches by coordinate: EXTRA = [(x, y, path, {vars})], MOUNTS = [(x, y, side|None, kind, path, {vars})]
        for x, y, path, vs in getattr(self.bp, "EXTRA", []):
            self.t(x, y).objs.append(dmm.Atom(path, [(k, dmm.fmt(v)) for k, v in vs.items()]))

    WALL_PIECES = ("/obj/structure/sign", "/obj/machinery/status_display", "/obj/machinery/firealarm", "/obj/machinery/airalarm",
                   "/obj/machinery/light_switch", "/obj/structure/extinguisher_cabinet", "/obj/machinery/newscaster",
                   "/obj/item/radio/intercom", "/obj/structure/noticeboard", "/obj/machinery/requests_console")

    def rehang_wall_pieces(self):
        """Hippie's way: a wall piece stands on the floor tile in front of the wall and is shifted onto it, so it can be
        reached and used. Old pieces sitting on the wall turf itself (in the zone or its shell) are moved that way."""
        cand = set(self.zone)
        for p in self.zone:
            for d in CARD:
                cand.add(self.nb(p, d))
        moved = 0
        for p in sorted(cand):
            t = self.t(*p)
            if t is None or not t.tpath.startswith("/turf/closed"):
                continue
            for o in [o for o in t.objs if o.path.startswith(self.WALL_PIECES) and "barsign" not in o.path]:
                # alarms, switches and cabinets the rooms on either side already got from the builder: drop the old one
                if o.path.startswith(("/obj/machinery/firealarm", "/obj/machinery/airalarm", "/obj/machinery/light_switch",
                                      "/obj/structure/extinguisher_cabinet", "/obj/machinery/newscaster")):
                    sides_areas = {self.t(*self.nb(p, d)).apath for d in CARD if self.t(*self.nb(p, d)) is not None}
                    if any(a.path.startswith(o.path) for r in self.zone if self.t(*r).apath in sides_areas
                           for a in self.t(*r).objs if a is not o and not self.t(*r).tpath.startswith("/turf/closed")):
                        t.objs.remove(o)
                        if p not in self.zone:
                            self.outside_edits.append(p)
                        continue
                public = o.path.startswith(("/obj/structure/sign/departments", "/obj/structure/sign/warning",
                                            "/obj/structure/sign/directions", "/obj/structure/sign/map"))
                best = None
                for d in CARD:
                    q = self.nb(p, d)
                    qt = self.t(*q)
                    if qt is None or not qt.tpath.startswith("/turf/open") or qt.tpath.startswith("/turf/open/space"):
                        continue
                    if qt.has("/obj/machinery/door") or (q[0], q[1], kit.OPP[d]) in self.faces:
                        continue
                    score = (2 if public and qt.apath.startswith("/area/hallway") else 0) + (1 if q in self.zone else 0)
                    if best is None or score > best[0]:
                        best = (score, q, kit.OPP[d])
                if not best:
                    t.objs.remove(o)  # nowhere in front of this wall: an old sign on an outer wall goes
                    if p not in self.zone:
                        self.outside_edits.append(p)
                    continue
                _, q, side = best
                kinds = {"/obj/machinery/firealarm": "firealarm", "/obj/machinery/airalarm": "airalarm",
                         "/obj/machinery/light_switch": "light_switch", "/obj/structure/extinguisher_cabinet": "extinguisher",
                         "/obj/machinery/newscaster": "newscaster", "/obj/item/radio/intercom": "intercom",
                         "/obj/structure/noticeboard": "noticeboard", "/obj/machinery/requests_console": "requests_console",
                         "/obj/machinery/status_display": "status_display"}
                kind = next((k for pre, k in kinds.items() if o.path.startswith(pre)), "sign")
                if kind in ("firealarm", "airalarm", "light_switch", "extinguisher", "newscaster"):
                    area = self.t(*q).apath
                    if any(a.path.startswith(o.path) for r in self.zone if self.t(*r).apath == area for a in self.t(*r).objs if a is not o):
                        t.objs.remove(o)  # the room already got its own from the builder
                        if p not in self.zone:
                            self.outside_edits.append(p)
                        continue
                d0, px, py = kit.MOUNT[kind][side]
                o.vars = [(k, v) for k, v in o.vars if k not in ("pixel_x", "pixel_y", "dir")]
                if d0 is not None and kind != "sign":
                    o.vars.append(("dir", str(d0)))
                if px is not None:
                    o.vars.append(("pixel_x", str(px)))
                if py is not None:
                    o.vars.append(("pixel_y", str(py)))
                t.objs.remove(o)
                self.t(*q).objs.append(o)
                self.faces.add((q[0], q[1], side))
                if p not in self.zone:
                    self.outside_edits.append(p)
                if q not in self.zone:
                    self.outside_edits.append(q)
                moved += 1
        if moved:
            self.notes.append("rehung %d old wall pieces onto the floor in front of their wall" % moved)

    FUNCTIONAL = ("button", "requests_console")

    def decor_mounts(self, functional=False):
        """MOUNTS = [(x, y, side|None, kind, path, {vars})]: one-off wall pieces. Functional ones (buttons, request
        consoles) go up before the room's lights; decor after, on wall that's left. A taken or missing spot slides
        along the same wall up to 3 tiles, inside the same area, the way a mapper nudges a poster past a light."""
        for x, y, side, kind, path, vs in getattr(self.bp, "MOUNTS", []):
            if (kind in self.FUNCTIONAL) != functional:
                continue
            p = (x, y)
            area = self.area_of(p) or self.t(*p).apath
            want = [{v: k for k, v in kit.NAME.items()}[side]] if side else list(CARD)
            spot = None
            for dist in range(0, 4):
                for d in want:
                    run = [x for x in CARD if x not in (d, kit.OPP[d])]
                    cands = [p] if dist == 0 else [(p[0] + kit.DELTA[r][0] * dist, p[1] + kit.DELTA[r][1] * dist) for r in run]
                    for q in cands:
                        if q not in self.zone or (self.area_of(q) or self.t(*q).apath) != area or not self.is_floor(q):
                            continue
                        if self.solid(self.nb(q, d)) and (q[0], q[1], d) not in self.faces:
                            spot = (q, d)
                            break
                    if spot:
                        break
                if spot:
                    break
            if not spot:
                self.warn.append("%s at %d,%d: no free wall within 3 tiles, not mounted" % (kind, x, y))
                continue
            if spot[0] != p:
                self.notes.append("%s moved from %d,%d to %d,%d (free wall)" % (kind, x, y, spot[0][0], spot[0][1]))
            self.mount(spot[0], spot[1], kind, path, [(k, dmm.fmt(v)) for k, v in vs.items()])

    def doors_into(self, area):
        """Door tiles leading into this area: (door tile, inside tile, wall-run direction)."""
        out = []
        for p in self.zone:
            if not self.t(*p).has("/obj/machinery/door/airlock"):
                continue
            for d in CARD:
                q = self.nb(p, d)
                if self.area_of(q) == area and self.is_floor(q) and not self.t(*q).has("/obj/machinery/door"):
                    out.append((p, q, d))
        return out

    def mounts_area(self, area):
        rd = self.roomdef_for_area(area)
        if rd.get("bare"):
            return  # a sealed chamber (burn chamber, slime pen...): its own fittings are placed by hand
        name = rd.get("name", area.rsplit("/", 1)[-1].title())
        floors = self.floors_of(area)
        doors = self.doors_into(area)
        door_in = [q for _, q, _ in doors]
        cx = sum(p[0] for p in floors) / len(floors)
        cy = sum(p[1] for p in floors) / len(floors)

        def near_door(face):
            return min((abs(face[0][0] - q[0]) + abs(face[0][1] - q[1]) for q in door_in), default=20)

        # APC: near the power line if there is one in the zone, else beside the staff door
        faces = self.free_faces(area)
        if not faces:
            self.warn.append("%s: no wall faces for mounts" % name)
            return
        cable_ports = [p for p, _ in self.ports["cable"]]

        def apc_score(f):
            p = f[0]
            dc = min((abs(p[0] - q[0]) + abs(p[1] - q[1]) for q in cable_ports), default=0)
            return dc + 0.3 * near_door(f) + (5 if self.t(*p).has("/obj/machinery/disposal") else 0)
        remote = self.remote_apc(area)
        if remote:
            self.notes.append("%s: powered by the existing APC at %d,%d (kept)" % (name, remote[0], remote[1]))
        if rd.get("apc", True) and not remote:
            f = min(faces, key=apc_score)
            self.mount(f[0], f[1], "apc", extra=[("name", '"%s APC"' % name)])
            self.apc_tiles = getattr(self, "apc_tiles", []) + [f[0]]
        # fire alarm beside each door (inside), light switch on the other side of the first door
        for i, (dp, q, d) in enumerate(doors[:3]):
            run = [x for x in CARD if x not in (d, OPP[d])]
            placed = False
            for side_dir in run:
                cand = self.nb(q, side_dir)
                wall_side = OPP[d]
                if self.area_of(cand) == area and self.is_floor(cand) and self.solid(self.nb(cand, wall_side)) \
                        and (cand[0], cand[1], wall_side) not in self.faces:
                    if not placed:
                        self.mount(cand, wall_side, "firealarm")
                        placed = True
                    elif i == 0 and rd.get("light_switch", True):
                        self.mount(cand, wall_side, "light_switch")
                        break
        if doors and not any(o.isa("/obj/machinery/firealarm") for p in floors for o in self.t(*p).objs):
            # no wall right beside the door (windows there): nearest free wall face to a door instead
            faces = self.free_faces(area)
            if faces:
                f = min(faces, key=near_door)
                self.mount(f[0], f[1], "firealarm")
        faces = self.free_faces(area)
        if not faces:
            return
        # air alarm: a long wall away from the APC, near the middle of the room
        apc = self.apc_tiles[-1] if (rd.get("apc", True) and not remote and getattr(self, "apc_tiles", None)) else (remote or (cx, cy))

        def aa_score(f):
            p = f[0]
            return -min(6, abs(p[0] - apc[0]) + abs(p[1] - apc[1])) + 0.25 * math.hypot(p[0] - cx, p[1] - cy)
        f = min(faces, key=aa_score)
        self.mount(f[0], f[1], "airalarm")
        if len(floors) > 30 and rd.get("extinguisher", True):
            faces = self.free_faces(area)
            if faces:
                f = min(faces, key=lambda f: (near_door(f) - 2) ** 2 + 0.1 * math.hypot(f[0][0] - cx, f[0][1] - cy))
                self.mount(f[0], f[1], "extinguisher")
        if rd.get("newscaster"):
            faces = self.free_faces(area)
            if faces:
                f = min(faces, key=lambda f: math.hypot(f[0][0] - cx, f[0][1] - cy))
                self.mount(f[0], f[1], "newscaster")
        if rd.get("camera", True):
            faces = [f for f in self.free_faces(area) if len(self.wall_sides(f[0])) >= 2] or self.free_faces(area)
            if faces:
                # a corner that sees the most of the room
                f = max(faces, key=lambda f: math.hypot(f[0][0] - cx, f[0][1] - cy))
                tag = rd.get("camera") if isinstance(rd.get("camera"), str) else name
                self.mount(f[0], f[1], "camera", extra=[("c_tag", '"%s"' % tag)])

    def remote_apc(self, area):
        """An APC outside the zone that powers this area (Hippie mounts many in maintenance with areastring)."""
        if not hasattr(self, "_apcs"):
            self._apcs = []
            for (x, y, z), t in self.m.tiles.items():
                if (x, y) in self.zone:
                    continue
                for o in t.find("/obj/machinery/power/apc"):
                    a = (o.get("areastring") or "").strip('"') or t.apath
                    self._apcs.append(((x, y), a))
        for pos, a in self._apcs:
            if a == area:
                return pos
        return None

    def walk_reach(self, start, tiles, radius):
        """Tiles of `tiles` within `radius` (euclidean) AND reachable from start without leaving `tiles` (light doesn't
        pass walls; a tube in the bar doesn't light the storeroom behind it)."""
        seen, q, out = {start}, [start], set()
        while q:
            p = q.pop()
            if math.hypot(p[0] - start[0], p[1] - start[1]) > radius:
                continue
            out.add(p)
            for d in CARD:
                n = self.nb(p, d)
                if n in tiles and n not in seen:
                    seen.add(n)
                    q.append(n)
        return out

    def lights(self, area):
        rd = self.roomdef_for_area(area)
        if rd.get("bare") or rd.get("lights") is False:
            return
        floors = self.floors_of(area)
        # light each room of the area on its own: rooms are the open floor regions walls split the area into
        floors = [p for p in floors if not self.t(*p).has("/obj/machinery/door")]
        groups, left = [], set(floors)
        while left:
            s0 = left.pop()
            g, q = {s0}, [s0]
            while q:
                p = q.pop()
                for d in CARD:
                    n = self.nb(p, d)
                    if n in left and not self.t(*n).has("/obj/machinery/door"):
                        left.discard(n)
                        g.add(n)
                        q.append(n)
            groups.append(g)
        total_placed, total_uncovered = 0, 0
        for g in groups:
            small = rd.get("lights") == "small" or len(g) < 10
            radius = 3.2 if small else 4.6
            path = "/obj/machinery/light/small" if small else "/obj/machinery/light"
            uncovered = set(g)
            placed = []
            cands = [(p, d) for p, d in self.free_faces(area) if p in g and
                     not kit.dense([a for a in self.t(*p).objs if a.path.startswith("/obj/machinery/vending")])]
            reach = {}
            while uncovered:
                best, bestgain = None, 0
                for p, d in cands:
                    if (p[0], p[1], d) in self.faces:
                        continue
                    if any(math.hypot(p[0] - q[0], p[1] - q[1]) < (2.5 if small else 3.5) for q in placed):
                        continue
                    if p not in reach:
                        reach[p] = self.walk_reach(p, g, radius)
                    gain = len(reach[p] & uncovered)
                    gain += 0.4 * (len(self.wall_sides(p)) == 1)  # the middle of a wall run
                    if gain > bestgain:
                        best, bestgain = (p, d), gain
                if not best or bestgain < (1 if len(g) < 6 else 2):
                    break
                p, d = best
                self.mount(p, d, "light", path=path)
                placed.append(p)
                uncovered -= reach[p]
            total_placed += len(placed)
            total_uncovered += len(uncovered)
            if len(g) >= 4 and not placed:
                self.warn.append("%s: a %d-tile room at %d,%d got no light" % (rd.get("name", area), len(g), *min(g)))
        cov = 1 - total_uncovered / max(1, len(floors))
        self.notes.append("%s: %d lights over %d rooms, %.0f%% of floor lit" % (rd.get("name", area), total_placed, len(groups), cov * 100))

    # ------------------------------------------------------------------ atmos
    def vent_sites(self, area, n, avoid=()):
        floors = [p for p in self.floors_of(area) if not kit.dense(self.t(*p).objs) and p not in avoid
                  and not self.t(*p).has("/obj/machinery/door") and not self.t(*p).has("/obj/machinery/atmospherics")
                  and not self.spec(p).get("no_vent")]
        allf = self.floors_of(area)
        if not floors:
            self.warn.append("%s: nowhere for a vent" % area)
            return []
        # k-means over the whole floor, snap each centre to the nearest open tile
        cents = [allf[int(i * len(allf) / n)] for i in range(n)]
        cents = [(float(c[0]), float(c[1])) for c in cents]
        for _ in range(12):
            groups = [[] for _ in cents]
            for p in allf:
                i = min(range(len(cents)), key=lambda i: (p[0] - cents[i][0]) ** 2 + (p[1] - cents[i][1]) ** 2)
                groups[i].append(p)
            cents = [(sum(p[0] for p in g) / len(g), sum(p[1] for p in g) / len(g)) if g else c for g, c in zip(groups, cents)]
        out = []
        for c in cents:
            site = min((p for p in floors if p not in out), key=lambda p: (p[0] - c[0]) ** 2 + (p[1] - c[1]) ** 2, default=None)
            if site:
                out.append(site)
        return out

    def atmos(self):
        self.vents = {"supply": [], "scrubbers": []}
        for area in self.areas():
            rd = self.roomdef_for_area(area)
            if rd.get("bare") or rd.get("vents") == 0:
                continue
            n = rd.get("vents") or max(1, round(len(self.floors_of(area)) / 45))
            vs = self.vent_sites(area, n)
            self.vents["supply"] += vs
            # scrubbers: same spread, two to three tiles off each vent
            sc = []
            for v in vs:
                opts = [p for p in self.floors_of(area) if p not in vs and p not in sc and not kit.dense(self.t(*p).objs)
                        and not self.t(*p).has("/obj/machinery/door") and not self.spec(p).get("no_vent")
                        and not self.t(*p).has("/obj/machinery/atmospherics")]
                if opts:
                    sc.append(min(opts, key=lambda p: abs(math.hypot(p[0] - v[0], p[1] - v[1]) - 2.5) + 0.2 * (p[1] != v[1] and p[0] != v[0])))
            self.vents["scrubbers"] += sc
        self.pipe_tiles = {}
        for cls in ("supply", "scrubbers"):
            self.route_pipes(cls)

    def steiner(self, cls, terminals, ports, cost_fn):
        """Greedy Steiner tree with a turn penalty. Returns {tile: mask}."""
        mask = {}
        tree = set()
        pending = list(terminals)
        if ports:
            first = ports[0]
            tree.add(first[0])
            mask[first[0]] = first[1]
            for p, d in ports[1:]:
                pending.insert(0, (p, d))
        elif pending:
            t0 = pending.pop(0)
            tree.add(t0[0])
        else:
            return mask
        port_dirs = {p: d for p, d in ports}
        unary = {t[0] for t in terminals if t[1] is None}
        while pending:
            # multi-source dijkstra from the tree; state (tile, incoming dir)
            dist = {}
            prev = {}
            heap = []
            for p in tree:
                if p in unary or bin(mask.get(p, 0)).count("1") >= 4:
                    continue
                dist[(p, 0)] = 0
                heapq.heappush(heap, (0, p, 0))
            targets = {t[0] for t in pending}
            found = None
            while heap:
                c, p, din = heapq.heappop(heap)
                if dist.get((p, din), 1e9) < c:
                    continue
                if p in targets and p not in tree:
                    found = (p, din)
                    break
                for d in CARD:
                    q = self.nb(p, d)
                    if q in tree:
                        continue
                    step = cost_fn(q, p, d)
                    if step is None:
                        continue
                    if din and d != din:
                        step += 2.5
                    nc = c + step
                    if nc < dist.get((q, d), 1e9):
                        dist[(q, d)] = nc
                        prev[(q, d)] = (p, din)
                        heapq.heappush(heap, (nc, q, d))
            if not found:
                # a part of the zone the tree can't reach (a room behind kept walls): start another tree there,
                # rooted at one of its own ports
                roots = [t for t in pending if t[0] in port_dirs]
                if not roots:
                    left = ", ".join("%d,%d" % t[0] for t in pending)
                    self.warn.append("%s: could not reach %s" % (cls, left))
                    break
                r0 = roots[0]
                tree.add(r0[0])
                mask[r0[0]] = mask.get(r0[0], 0) | port_dirs[r0[0]]
                pending = [t for t in pending if t[0] not in tree]
                continue
            node = found
            path = [node[0]]
            while node in prev:
                p, din = prev[node]
                d = node[1]
                mask[node[0]] = mask.get(node[0], 0) | OPP[d]
                mask[p] = mask.get(p, 0) | d
                path.append(p)
                node = (p, din)
            tree.update(path)
            fp = found[0]
            if fp in port_dirs:
                mask[fp] = mask.get(fp, 0) | port_dirs[fp]
            pending = [t for t in pending if t[0] not in tree]
        return mask

    # ---------------------------------------------------------------- network routing (pipes and cable)
    def net_links(self, cls, tile):
        """Directions a tile's pipe/cable of this class links to, from the CURRENT map."""
        t = self.t(*tile)
        if t is None:
            return 0
        if cls == "cable":
            if not any(kit.is_cable(o) for o in t.objs):
                return 0
            mk = 0
            for d in CARD:
                nt = self.t(*self.nb(tile, d))
                if nt is not None and any(kit.is_cable(o) for o in nt.objs):
                    mk |= d
            return mk
        mk = 0
        for o in t.objs:
            if kit.pipe_class(o.path) == cls:
                mk |= kit.pipe_mask(o)
        return mk

    def outside_component(self, cls, start, cache):
        """Id of the outside network a kept tile belongs to (flood fill that never enters the zone)."""
        if start in cache:
            return cache[start]
        cid = len(set(cache.values())) + 1
        q = [start]
        cache[start] = cid
        while q:
            p = q.pop()
            mk = self.net_links(cls, p)
            for d in CARD:
                if mk & d:
                    n = self.nb(p, d)
                    if n in self.zone or n in cache:
                        continue
                    if cls != "cable" and not (self.net_links(cls, n) & OPP[d]):
                        continue
                    cache[n] = cid
                    q.append(n)
        return cid

    def inside_groups(self, cls, ports):
        """Ports that the OLD zone joined together (so the new zone must keep them joined)."""
        def links(p):
            t = self.orig[p]
            if cls == "cable":
                if not any(kit.is_cable(o) for o in t.objs):
                    return 0
                return sum(d for d in CARD if self.nb(p, d) in self.orig
                           and any(kit.is_cable(o) for o in self.orig[self.nb(p, d)].objs))
            mk = 0
            for o in t.objs:
                if kit.pipe_class(o.path) == cls:
                    mk |= kit.pipe_mask(o)
            return mk
        group = {}
        for i, (z, d) in enumerate(ports):
            if z in group:
                continue
            q = [z]
            group[z] = i
            while q:
                p = q.pop()
                mk = links(p)
                for dd in CARD:
                    n = self.nb(p, dd)
                    if mk & dd and n in self.orig and n not in group and links(n) & OPP[dd]:
                        group[n] = i
                        q.append(n)
        return [group.get(z) for z, d in ports]

    def dijkstra(self, sources, targets, cost_fn, unary=()):
        """Cheapest path from any source tile to any target tile, with a turn penalty."""
        dist, prev, heap = {}, {}, []
        for p, d0 in sources.items():
            dist[(p, d0)] = 0
            heapq.heappush(heap, (0, p, d0))
        while heap:
            c, p, din = heapq.heappop(heap)
            if dist.get((p, din), 1e9) < c:
                continue
            if p in targets:
                path = [p]
                node = (p, din)
                while node in prev:
                    node = prev[node]
                    path.append(node[0])
                return path[::-1], c
            if p in unary and p not in sources:
                continue
            for d in CARD:
                q = self.nb(p, d)
                if q in sources:
                    continue
                step = cost_fn(q, p, d)
                if step is None:
                    continue
                if din and d != din:
                    step += 2.5
                nc = c + step
                if nc < dist.get((q, d), 1e9):
                    dist[(q, d)] = nc
                    prev[(q, d)] = (p, din)
                    heapq.heappush(heap, (nc, q, d))
        return None, None

    def forest(self, cls, terminals, cost_fn):
        """Route a network the way a mapper would: keep through-lines that crossed the zone joined, then feed each
        terminal (vent, APC) from the nearest stub or the nearest part already laid. Unused stubs are trimmed."""
        ports = self.ports[cls]
        cache = {}
        comp = [self.outside_component(cls, self.nb(z, d), cache) for z, d in ports]
        grp = self.inside_groups(cls, ports)
        mask = {}
        used = set()
        unary = set(terminals) if cls != "cable" else set()

        def lay(path):
            for a, b in zip(path, path[1:]):
                d = next(dd for dd in CARD if self.nb(a, dd) == b)
                mask[a] = mask.get(a, 0) | d
                mask[b] = mask.get(b, 0) | OPP[d]
            for p in path:
                for i, (z, d) in enumerate(ports):
                    if z == p and i not in used:
                        used.add(i)
                        mask[z] = mask.get(z, 0) | d
            if len(path) == 1:
                mask.setdefault(path[0], 0)

        def growable(p):
            return p not in unary and bin(mask.get(p, 0)).count("1") < (4 if cls != "cable" else 5)

        # 1. bridges: outside networks the old zone joined must stay joined
        need = {}
        for i, g in enumerate(grp):
            need.setdefault(g, set()).add(comp[i])
        for g, comps in need.items():
            if len(comps) < 2:
                continue
            members = [i for i in range(len(ports)) if grp[i] == g]
            first = members[0]
            lay([ports[first][0]])
            joined = {comp[first]}
            while joined != comps:
                src = {p: 0 for p in mask if growable(p)}
                tgt = {ports[i][0] for i in members if comp[i] not in joined}
                path, c = self.dijkstra(src, tgt, cost_fn, unary)
                if not path:
                    self.warn.append("%s: could not keep the through-line joined (%s)" % (cls, ", ".join("%d,%d" % t for t in tgt)))
                    break
                lay(path)
                joined |= {comp[i] for i in members if ports[i][0] == path[-1]}
            self.notes.append("%s: kept a through-line joining %d outside networks" % (cls, len(comps)))
        # 2. terminals, nearest first
        left = list(terminals)
        while left:
            src = {p: 0 for p in mask if growable(p)}
            for i, (z, d) in enumerate(ports):
                if z not in src and growable(z):
                    src[z] = 0
            path, c = self.dijkstra(src, set(left), cost_fn, unary)
            if not path:
                self.warn.append("%s: could not reach %s" % (cls, ", ".join("%d,%d" % t for t in left)))
                break
            lay(path)
            left = [t for t in left if t not in mask]
        # 3. kept tiles that only bridge zone tiles (a pipe under a kept wall or shutter): all or nothing
        tiles_of = {}
        for t, cid in cache.items():
            tiles_of.setdefault(cid, []).append(t)
        for cid, tl in tiles_of.items():
            idx = [i for i in range(len(ports)) if comp[i] == cid]
            if not idx:
                continue
            bridge_only = all(all((not (self.net_links(cls, t) & dd)) or self.nb(t, dd) in self.zone or self.nb(t, dd) in tl
                                  for dd in CARD) for t in tl)
            if not bridge_only:
                continue
            u = [i for i in idx if i in used]
            if u and len(u) < len(idx):
                for i in idx:
                    if i in used:
                        continue
                    src = {p: 0 for p in mask if growable(p)}
                    path, c = self.dijkstra(src, {ports[i][0]}, cost_fn, unary)
                    if path:
                        lay(path)
                    else:
                        self.warn.append("%s: could not rejoin the kept bridge at %d,%d" % (cls, *self.nb(*ports[i])))
            elif not u:
                for t in tl:
                    tt = self.t(*t)
                    before = len(tt.objs)
                    tt.objs = [o for o in tt.objs if not (kit.pipe_class(o.path) == cls if cls != "cable" else kit.is_cable(o))]
                    if len(tt.objs) != before:
                        self.outside_edits.append(t)
                        self.trimmed.append((cls, t))
                used.update(idx)
        # 4. trim stubs nobody uses
        for i, (z, d) in enumerate(ports):
            if i not in used:
                self.trim_stub(cls, self.nb(z, d), OPP[d])
        return mask

    def trim_stub(self, cls, start, toward_zone):
        """Remove a dead pipe/cable stub outside the zone back to the junction it hangs off."""
        cur, gone = start, toward_zone
        for _ in range(40):
            if cur in self.zone:
                break
            t = self.t(*cur)
            # a run that also leads back into the zone (through a kept wall) is still in use: only close the dead side
            if any((self.net_links(cls, cur) & d) and self.nb(cur, d) in self.zone for d in CARD if d != gone):
                if cls != "cable":
                    atoms = [o for o in t.objs if kit.pipe_class(o.path) == cls and "/pipe/" in o.path]
                    if len(atoms) == 1:
                        mk = kit.pipe_mask(atoms[0]) & ~gone
                        if bin(mk).count("1") >= 2:
                            t.objs.remove(atoms[0])
                            path, vs = kit.pipe_atom(cls, mk)
                            t.objs.append(dmm.Atom(path, vs))
                            self.outside_edits.append(cur)
                            self.trimmed.append((cls, cur))
                break
            if cls == "cable":
                cab = [o for o in t.objs if kit.is_cable(o)]
                self.trimmed.append((cls, cur))
                links = self.net_links("cable", cur) & ~gone
                if not cab or bin(links).count("1") != 1 or t.has("/obj/machinery/power"):
                    break
                t.objs = [o for o in t.objs if not kit.is_cable(o)]
                self.outside_edits.append(cur)
                cur, gone = self.nb(cur, links), OPP[links]
                continue
            atoms = [o for o in t.objs if kit.pipe_class(o.path) == cls]
            if len(atoms) != 1 or "/pipe/" not in atoms[0].path:
                break
            a = atoms[0]
            mk = kit.pipe_mask(a) & ~gone
            t.objs.remove(a)
            self.outside_edits.append(cur)
            self.trimmed.append((cls, cur))
            if bin(mk).count("1") >= 2:
                path, vs = kit.pipe_atom(cls, mk)
                t.objs.append(dmm.Atom(path, vs))
                break
            if not mk:
                break
            cur, gone = self.nb(cur, mk), OPP[mk]

    def pipe_cost(self, cls):
        taps = {p for p, d in getattr(self.bp, "TAPS", {}).get(cls, ())}
        other = "scrubbers" if cls == "supply" else "supply"
        vents = set(self.vents[cls])
        block = set(self.vents[other])

        def cost(q, p, d):
            if q not in self.zone:
                return None
            k = self.kind(q)
            if k in ("window", "rwindow") or q in block:
                return None
            # never share a tile with another loop on our layer (it would join or block it)
            from forge import atmos
            mine = 1 if cls == "supply" else 2
            if q not in taps and any(atmos.layer(o) == mine and atmos.kind(o) not in (cls,) for o in atmos.atoms(self.t(*q))):
                return None
            if q in vents:
                return 1
            c = 1.0
            if k in ("wall", "rwall"):
                beyond = self.nb(q, d)
                ap = self.area_of(p) or self.wall_area(p)
                aq = self.area_of(beyond) or (self.wall_area(beyond) if beyond in self.zone else None)
                c += 14 if ap != aq else 5
            t = self.t(*q)
            if t.has("/obj/machinery/door"):
                c += 0.8
            if kit.dense(t.objs):
                c += 0.4
            if any(self.solid(self.nb(q, dd)) for dd in CARD):
                c -= 0.25
            if q in self.pipe_tiles:
                c -= 0.3
            return c
        return cost

    def route_pipes(self, cls):
        vents = self.vents[cls]
        # taps: the network must reach a tile and point one extra side at a device there (a dp vent airlock...)
        taps = list(getattr(self.bp, "TAPS", {}).get(cls, ()))
        mask = self.forest(cls, vents + [p for p, d in taps], self.pipe_cost(cls))
        for p, d in taps:
            if p in mask:
                mask[p] |= d
            else:
                self.warn.append("%s: could not reach the tap at %d,%d" % (cls, p[0], p[1]))
        simple, manifold, four, vent = kit.PIPES[cls]
        for p, mk in mask.items():
            t = self.t(*p)
            if p in vents:
                d = mk
                if bin(d).count("1") != 1:
                    self.warn.append("%s vent at %d,%d has mask %d" % (cls, p[0], p[1], d))
                    d = next((x for x in CARD if x & d), S)
                t.objs.append(dmm.Atom(vent, [("dir", str(d))] if d != 2 else []))
            else:
                path, vs = kit.pipe_atom(cls, mk)
                t.objs.append(dmm.Atom(path, vs))
            self.pipe_tiles[p] = self.pipe_tiles.get(p, 0) | mk
        for v in vents:
            if v not in mask:
                self.t(*v).objs.append(dmm.Atom(vent))
                self.warn.append("%s vent at %d,%d not connected" % (cls, v[0], v[1]))
        self.notes.append("%s: %d vents, %d pipe tiles" % (cls, len(vents), len(mask) - len(vents)))

    # ------------------------------------------------------------------ power
    def power(self):
        apcs = getattr(self, "apc_tiles", [])

        def cost(q, p, d):
            if q not in self.zone:
                return None
            k = self.kind(q)
            if k in ("window", "rwindow") or q in self.cable_fence:
                return None
            c = 1.0
            if k in ("wall", "rwall"):
                c += 0.6
            if any(self.solid(self.nb(q, dd)) for dd in CARD):
                c -= 0.3
            if self.t(*q).has("/obj/machinery/door"):
                c += 1.5
            return c
        mask = self.forest("cable", apcs, cost)
        for p in mask:
            self.t(*p).objs.append(dmm.Atom(kit.CABLE))
        for a in apcs:
            if a not in mask:
                self.t(*a).objs.append(dmm.Atom(kit.CABLE))
        self.notes.append("cable: %d tiles for %d APCs" % (len(mask), len(apcs)))

    # ------------------------------------------------------------------ decals
    def decals(self):
        styles = getattr(self.bp, "DECALS", {})
        for p in self.zone:
            rc = self.room.get(p)
            if not rc or not self.is_floor(p):
                continue
            s = self.spec(p)
            for e in s.get("decal", []):
                self.t(*p).objs.insert(0, dmm.Atom(e) if isinstance(e, str) else dmm.Atom(e[0], list(e[1].items())))
            style = self.roomdefs[rc].get("trim")
            if not style:
                continue
            # tile trim along the walls: the quarter decals that face the wall
            color = style
            for d in CARD:
                if self.kind(self.nb(p, d)) != "floor" or self.area_of(self.nb(p, d)) != self.area_of(p):
                    for qd in TRIM_QUARTERS[d]:
                        a = dmm.Atom("/obj/effect/turf_decal/tile/%s" % color, [("dir", str(qd))] if qd != 2 else [])
                        if not any(o.text() == a.text() for o in self.t(*p).objs):
                            self.t(*p).objs.insert(0, a)

    # ------------------------------------------------------------------ output
    def save(self, path):
        if self.base_path == "blank":
            dmm.write(self.m, path)
            return path
        dmm.merge_write(self.m, path)
        return path

    def bounds(self, pad=1):
        xs = [p[0] for p in self.zone]
        ys = [p[1] for p in self.zone]
        return (min(xs) - pad, min(ys) - pad, max(xs) + pad, max(ys) + pad)


# tile_corner decal dirs that paint the half of a tile toward each side (2020 tg: dir picks the quarter)
TRIM_QUARTERS = {N: (1, 4), S: (2, 8), E: (4, 2), W: (8, 1)}


# what a remodel keeps in a room besides its walls: networks, lighting, wall pieces, landmarks, doors' helpers
KEEP_INFRA = ("/obj/machinery/atmospherics", "/obj/structure/cable", "/obj/machinery/light", "/obj/machinery/power/apc",
              "/obj/machinery/power/terminal", "/obj/machinery/airalarm", "/obj/machinery/firealarm", "/obj/machinery/camera",
              "/obj/effect/landmark", "/obj/effect/mapping_helpers", "/obj/machinery/navbeacon", "/obj/machinery/holopad",
              "/obj/machinery/door", "/obj/effect/spawner/structure/window", "/obj/structure/grille", "/obj/structure/window",
              "/obj/structure/plasticflaps", "/obj/machinery/light_switch", "/obj/machinery/firealarm")


def blank_map(w, h):
    m = dmm.Map(w, h, 1)
    m.crlf = False
    for x in range(1, w + 1):
        for y in range(1, h + 1):
            m.set(x, y, dmm.Tile([], dmm.Atom("/turf/open/space/basic"), dmm.Atom("/area/space")))
    return m


def load_blueprint(path):
    import importlib.util
    spec = importlib.util.spec_from_file_location("bp_" + os.path.basename(path)[:-3], path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod
