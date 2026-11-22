"""Copy a stock room into another map: its floor, its inner walls, doors and windows, everything on its floor
(machines, furniture, decals, wall pieces), turned or mirrored any of the 8 ways. A missing room type is then a real
human-made room, not a guess (size_budget.py lists the missing types; station/v6_rooms.py places them).

    from forge import room_stamp
    src = room_stamp.Source("MetaStation", "/area/tcommsat/server")
    for k in range(8): src.footprint(k)          # floor and ring tiles relative to the origin, per orientation
    room_stamp.apply(m, src, k, origin, doors)    # write into a dmm.Map

What is copied, per source tile:
    floor     turf, area, every object except pipes, cables, disposal pipes and atmos machines bolted to pipes
              (the station's own power, air and disposals passes lay those again to what the room has: APC,
              vents, scrubbers, bins); dirs and pixel offsets turned with the room
    inner     a wall, door or window between two of the room's floor tiles, as it is
    outer     the room's outline: plain wall, except where apply() is told to cut a door (the caller decides,
              from what lies outside in the target map)

Orientation k: k % 4 quarter turns anticlockwise, then a mirror in x when k >= 4 (forge/tensor.py's order).
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import dmm, parse, room_stats as RS  # noqa: E402

DROP = ("/obj/machinery/atmospherics/pipe", "/obj/structure/cable", "/obj/structure/disposalpipe",
        "/obj/machinery/atmospherics/components/binary", "/obj/machinery/atmospherics/components/trinary",
        "/obj/machinery/meter", "/obj/effect/landmark/start", "/obj/machinery/atmospherics/components/unary/portables_connector",
        "/obj/machinery/atmospherics/components/unary/thermomachine", "/obj/machinery/atmospherics/components/unary/tank",
        "/obj/machinery/atmospherics/components/unary/outlet_injector", "/obj/machinery/atmospherics/components/unary/heat_exchanger",
        "/obj/machinery/atmospherics/components/unary/vent_pump/high_volume", "/obj/machinery/atmospherics/components/unary/vent_pump/siphon")
N8 = [(dx, dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy]
# a dir turned a quarter anticlockwise: N->W, W->S, S->E, E->N (and the diagonals with them)
TURN = {1: 8, 8: 2, 2: 4, 4: 1, 5: 9, 9: 10, 10: 6, 6: 5}
MIRROR = {4: 8, 8: 4, 5: 9, 9: 5, 6: 10, 10: 6, 1: 1, 2: 2}


def xform(k, x, y):
    for _ in range(k % 4):
        x, y = -y, x
    if k >= 4:
        x = -x
    return x, y


def xdir(k, d):
    for _ in range(k % 4):
        d = TURN.get(d, d)
    if k >= 4:
        d = MIRROR.get(d, d)
    return d


def xatom(k, a):
    if k == 0:
        return dmm.Atom(a.path, list(a.vars))
    vs = dict(a.vars)
    px, py = a.num("pixel_x"), a.num("pixel_y")
    if px or py:
        nx, ny = xform(k, px, py)
        vs.pop("pixel_x", None)
        vs.pop("pixel_y", None)
        if nx:
            vs["pixel_x"] = str(nx)
        if ny:
            vs["pixel_y"] = str(ny)
    d = a.num("dir", 0) if a.get("dir") is not None else None
    if d is None and k % 4:
        # objects that draw facing south by default turn too (chairs, computers, vents, lights by their wall)
        d = 2
        if not a.path.startswith(("/obj/structure/chair", "/obj/machinery/computer", "/obj/machinery/light",
                                  "/obj/machinery/atmospherics", "/obj/machinery/door/window", "/obj/effect/turf_decal",
                                  "/obj/structure/window", "/obj/machinery/camera", "/obj/structure/bed")):
            d = None
    if d is not None:
        nd = xdir(k, d)
        if nd != 2 or "dir" in vs:
            vs["dir"] = str(nd)
    return dmm.Atom(a.path, list(vs.items()))


class Source:
    """One stock room: the largest piece of its area on the station level."""

    def __init__(self, mapname, area, piece=None, extra=()):
        """extra: more room_stats rooms of the same map copied with it, each keeping its own area (a telecomms
        server room with its control room beside it)."""
        sm = parse.load(mapname)
        self.map, self.area, self.sm = mapname, area, sm
        rm = piece or max((r for r in RS.rooms(sm) if r.area == area), key=lambda r: len(r.tiles))
        self.floor = set(rm.tiles)
        self.areas = {p: rm.area for p in rm.tiles}
        for r in extra:
            self.floor |= set(r.tiles)
            self.areas.update({p: r.area for p in r.tiles})
        self.o = (min(p[0] for p in self.floor), min(p[1] for p in self.floor))
        self.ring = {(p[0] + dx, p[1] + dy) for p in self.floor for dx, dy in N8} - self.floor
        # inner: ring tiles with room floor on two opposite sides (inner walls, doors, windows)
        self.inner = {q for q in self.ring if any((q[0] + dx, q[1] + dy) in self.floor and (q[0] - dx, q[1] - dy) in self.floor
                                                  for dx, dy in ((1, 0), (0, 1)))}
        self.doors = {q for q in self.ring - self.inner if sm.cls.get(q) == "D"}
        self.tiles = len(self.floor)

    def rel(self, p, k):
        return xform(k, p[0] - self.o[0], p[1] - self.o[1])

    def footprint(self, k):
        """(floor, ring, outer doors) as sets of tiles relative to the origin, in orientation k."""
        return ({self.rel(p, k) for p in self.floor}, {self.rel(p, k) for p in self.ring},
                {self.rel(p, k) for p in self.doors})


def apply(m, src, k, origin, cut_doors, door_atom=None, wall="/turf/closed/wall", area=None):
    """Write the room into dmm.Map m with its origin at `origin`; cut_doors: outer ring tiles (map coords) that become
    doors (the source's own door there when it had one, else door_atom); area: one area for all of it (a stock
    maint room joins the maint area it is put in)."""
    ox, oy = origin
    sm = src.sm
    z = sm.z
    for p in src.floor | src.ring:
        rx, ry = src.rel(p, k)
        q = (ox + rx, oy + ry)
        t = sm.m.get(p[0], p[1], z)
        if p in src.floor:
            objs = [xatom(k, a) for a in t.objs if not a.path.startswith(DROP)]
            # airless floor belonged to a vent-to-space corner whose pipes stay behind: it is plain floor here
            turf = t.tpath[:-len("/airless")] if t.tpath.endswith("/airless") else t.tpath
            m.set(q[0], q[1], dmm.Tile(objs, dmm.Atom(turf), dmm.Atom(area or src.areas[p])))
        elif p in src.inner:
            objs = [xatom(k, a) for a in t.objs if not a.path.startswith(DROP)]
            side = next((src.areas[(p[0] + dx, p[1] + dy)] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))
                         if (p[0] + dx, p[1] + dy) in src.areas), src.area)
            m.set(q[0], q[1], dmm.Tile(objs, dmm.Atom(t.tpath), dmm.Atom(area or side)))
        else:
            cur = m.get(*q)
            if q in cut_doors:
                own = [a for a in t.objs if a.path.startswith("/obj/machinery/door/airlock")] if p in src.doors else []
                d = [xatom(k, a) for a in own] or [door_atom or dmm.Atom("/obj/machinery/door/airlock")]
                m.set(q[0], q[1], dmm.Tile(d, dmm.Atom("/turf/open/floor/plasteel"), dmm.Atom(area or src.area)))
            elif cur is None or not cur.tpath.startswith("/turf/closed"):
                m.set(q[0], q[1], dmm.Tile([], dmm.Atom(wall), dmm.Atom(cur.apath if cur else "/area/space")))
