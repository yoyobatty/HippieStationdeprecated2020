"""The station plan (station_plan.py) as a bare .dmm canvas the department blueprints are cut into.

    python tools/mapforge/plan/canvas.py      # data/mapforge/canvas_v6.dmm

What the canvas holds, so forge/proc/shell.outline reads the right things around a department:
  halls, plazas, lobbies, public rooms   plasteel floor, a hallway area (outline sees "hall")
  maint corridors and maint rooms        plating, a maintenance area (outline sees "maint")
  docks and catwalks                     plating, an entry/solar area
  a department block                     plasteel floor in that department's area, so its outline can be read;
                                         every other department reads as solid wall from it
  the hull                               wall on every space tile beside something built
Plan coordinates are y-down; the canvas is BYOND's y-up. to_map() converts.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import dmm  # noqa: E402
from plan import station_plan as plan  # noqa: E402

ROOT = plan.ROOT
OUT = os.path.join(ROOT, "data", "mapforge", "canvas_v6.dmm")
W, H = 200, 170
OX, OY = 6, 165             # map x = plan x + OX, map y = OY - plan y

AREA = {
    "hall": "/area/hallway/primary/central", "public": "/area/hallway/secondary/service",
    "maint": "/area/maintenance/port", "maint room": "/area/maintenance/port/aft", "dock": "/area/hallway/secondary/entry",
    "command": "/area/bridge", "security": "/area/security/main", "medical": "/area/medical/medbay/central",
    "science": "/area/science/research", "engineering": "/area/engine/engineering", "cargo": "/area/quartermaster/storage",
    "service": "/area/crew_quarters/bar", "dorms": "/area/crew_quarters/dorms", "civic": "/area/library",
    "ai": "/area/ai_monitored/turret_protected/ai",
}
# hull tiles left open to space, in plan coordinates: science's burn chamber vents through (66, 140-142) and the
# toxins mass driver fires out through (78, 148)
HOLES = [(66, 140), (66, 141), (66, 142), (78, 148)]
# hull tiles glazed instead of walled, in plan coordinates: the toxins launch room looks south over the bomb range
# through three viewing sections of two, the monitor and the range camera on the piers between them
HULL_WINDOWS = [(x, 148) for x in (68, 69, 71, 72, 74, 75)]
# external airlocks through the hull, in plan coordinates: EVA's way out to space over the maint north of it
HULL_AIRLOCKS = [((74, 31), "EVA External Airlock")]
FLOOR = {"maint": "/turf/open/floor/plating", "maint room": "/turf/open/floor/plating", "dock": "/turf/open/floor/plating"}
HULL_DEPTS = ("science",)       # departments that still get an outer hull line beside their own walls
# shuttle docks: the docking port sits on the space tile outside the station's external airlock, and the shuttle's
# whole footprint stays open space (no hull, no dock plating). A west-facing port at (x, y) covers map x - (height
# - 1) .. x and y - dwidth .. y + width - 1 - dwidth (docking_port/return_coords). Plan coordinates, Meta's sizes.
PORTS = [
    # cargo (2026-11-21): the supply shuttle at the bay's west airlock, the mining shuttle off the mining office
    ((29, 65), dict(dir=8, dwidth=5, height=7, width=12, id="supply_home", name="Cargo Bay")),
    ((35, 53), dict(dir=8, dwidth=3, height=5, width=7, id="mining_home", name="mining shuttle bay",
                    roundstart_template="/datum/map_template/shuttle/mining/box")),
]


def port_footprint(p, v):
    x, y = to_map(p)
    assert v["dir"] == 8, "only west-facing ports so far"
    return [(a, b) for a in range(x - (v["height"] - 1), x + 1)
            for b in range(y - v["dwidth"], y + v["width"] - v["dwidth"])]


def to_map(p):
    return (p[0] + OX, OY - p[1])


def to_plan(p):
    return (p[0] - OX, OY - p[1])


def build(open_depts=None):
    """The canvas map. open_depts: the departments laid as floor (all of them by default); the rest are wall."""
    g = plan.grid()
    m = dmm.Map(W, H, 1)
    m.crlf = False
    for x in range(1, W + 1):
        for y in range(1, H + 1):
            m.set(x, y, dmm.Tile([], dmm.Atom("/turf/open/space/basic"), dmm.Atom("/area/space")))
    for p, v in g.items():
        x, y = to_map(p)
        dept = v in plan.PROGRAM
        if dept and open_depts is not None and v not in open_depts:
            turf = "/turf/closed/wall"
        else:
            turf = FLOOR.get(v, "/turf/open/floor/plasteel")
        m.set(x, y, dmm.Tile([], dmm.Atom(turf), dmm.Atom(AREA.get(v, "/area/hallway/primary/central"))))
    # the hull: space beside anything built becomes wall. A department's outline ring is its own hull, so space
    # beside a department gets no second wall (that doubled the wall), except Science, approved on the old canvas
    # with its launch room's viewing sections and vent holes cut into this outer hull line.
    built = {to_map(p) for p in g}
    hulled = {to_map(p) for p, v in g.items() if v not in plan.PROGRAM or v in HULL_DEPTS}
    for (x, y) in list(hulled):
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                q = (x + dx, y + dy)
                if q in built or not (1 <= q[0] <= W and 1 <= q[1] <= H):
                    continue
                t = m.get(*q)
                if t.tpath.startswith("/turf/open/space"):
                    m.set(q[0], q[1], dmm.Tile([], dmm.Atom("/turf/closed/wall"), dmm.Atom("/area/space")))
    for p in HOLES:
        x, y = to_map(p)
        m.set(x, y, dmm.Tile([], dmm.Atom("/turf/open/space/basic"), dmm.Atom("/area/space")))
    # space sealed inside the station (a pocket between a block and maint) is filled with wall: only space that
    # reaches the map edge stays space (Medical review, 2026-11-21: a 1x4 starfield in the ward's wall)
    seen, todo = set(), [(x, y) for x in (1, W) for y in range(1, H + 1)] + [(x, y) for y in (1, H) for x in range(1, W + 1)]
    while todo:
        q = todo.pop()
        if q in seen or not (1 <= q[0] <= W and 1 <= q[1] <= H) or not m.get(*q).tpath.startswith("/turf/open/space"):
            continue
        seen.add(q)
        todo += [(q[0] + 1, q[1]), (q[0] - 1, q[1]), (q[0], q[1] + 1), (q[0], q[1] - 1)]
    holes = {to_map(p) for p in HOLES}
    for x in range(1, W + 1):
        for y in range(1, H + 1):
            if (x, y) not in seen and (x, y) not in holes and m.get(x, y).tpath.startswith("/turf/open/space"):
                m.set(x, y, dmm.Tile([], dmm.Atom("/turf/closed/wall"), dmm.Atom("/area/space")))
    # the supermatter's cooling coil out in space beyond Engineering's east hull (Meta's block, turned to suit;
    # assets/engineering_v6.py ENGINE_ANCHOR: map x = anchor x - v, map y = anchor y + u)
    from assets import engineering_v6 as eng
    sys.path.insert(0, os.path.join(HERE, "..", "station"))
    import to_dmm as T
    ax, ay = eng.ENGINE_ANCHOR
    for (u, v), (turf, area, objs) in T.engine_block().items():
        if v >= 0:
            continue
        x, y = ax - v, ay + u
        m.set(x, y, dmm.Tile([T.rot_engine_atom(o, eng.ENGINE_TURNS) for o in objs], turf.copy(),
                             dmm.Atom("/area/space/nearstation")))
    for p, v in PORTS:
        for q in port_footprint(p, v):
            if q not in built or g.get(to_plan(q)) == "dock":
                m.set(q[0], q[1], dmm.Tile([], dmm.Atom("/turf/open/space/basic"), dmm.Atom("/area/space")))
        x, y = to_map(p)
        m.get(x, y).objs.append(dmm.Atom("/obj/docking_port/stationary", v))
    # a cycling external airlock: the inner door on the hull line, a one-tile plating chamber walled either side, the
    # outer door beyond it, linked by cyclelink helpers (Command review 3, 2026-11-21: one door vented maint)
    for p, name in HULL_AIRLOCKS:
        x, y = to_map(p)
        out = next(((dx, dy) for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0))
                    if m.get(x + dx, y + dy) is not None and m.get(x + dx, y + dy).tpath.startswith("/turf/open/space")),
                   (0, 1))
        dir_out = {(0, 1): 1, (0, -1): 2, (1, 0): 4, (-1, 0): 8}[out]
        side = (out[1], out[0])
        for k, cyc in ((0, dir_out), (2, {1: 2, 2: 1, 4: 8, 8: 4}[dir_out])):
            q = (x + out[0] * k, y + out[1] * k)
            m.set(q[0], q[1], dmm.Tile([dmm.Atom("/obj/machinery/door/airlock/external", {"name": name, "req_access_txt": "18"}),
                                        dmm.Atom("/obj/effect/mapping_helpers/airlock/cyclelink_helper", {"dir": cyc})],
                                       dmm.Atom("/turf/open/floor/plating"), dmm.Atom("/area/maintenance/port")))
        c = (x + out[0], y + out[1])
        m.set(c[0], c[1], dmm.Tile([], dmm.Atom("/turf/open/floor/plating"), dmm.Atom("/area/maintenance/port")))
        for k in (1, 2):
            for sgn in (1, -1):
                q = (x + out[0] * k + side[0] * sgn, y + out[1] * k + side[1] * sgn)
                m.set(q[0], q[1], dmm.Tile([], dmm.Atom("/turf/closed/wall/r_wall"), dmm.Atom("/area/space")))
    for p in HULL_WINDOWS:
        x, y = to_map(p)
        m.set(x, y, dmm.Tile([dmm.Atom("/obj/effect/spawner/structure/window/reinforced")],
                             dmm.Atom("/turf/open/floor/plating"), dmm.Atom("/area/space")))
    return m


if __name__ == "__main__":
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    m = build()
    dmm.write(m, OUT)
    print(os.path.relpath(OUT, ROOT), "%dx%d" % (W, H))
