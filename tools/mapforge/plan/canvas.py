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
FLOOR = {"maint": "/turf/open/floor/plating", "maint room": "/turf/open/floor/plating", "dock": "/turf/open/floor/plating"}


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
    # the hull: space beside anything built becomes wall (departments carry their own outer walls)
    built = {to_map(p) for p in g}
    for (x, y) in list(built):
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
