"""Hippie Station Science, redesigned from how it plays (tools/mapforge/studies/science.md, program approved
2026-11-15). Same outer outline; every interior wall, room and core is new. The maintenance that runs through the
original (the x198 artery and the science maint room between toxins and the launch room) stays as it is.

Grid helpers carve rooms into a solid block; the furnishing is placed by hand per room below.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from forge import dmm  # noqa: E402

NAME = "science_v2"
STYLE = "meta"
DISPOSALS = "route"
X0, Y0, X1, Y1 = 162, 82, 208, 128
ORIGIN = (X0, Y0)
W, H = X1 - X0 + 1, Y1 - Y0 + 1
BASE_MAP = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "_maps", "map_files",
                        "HippieStation", "hippiestation.dmm")

# ------------------------------------------------------------------ the outline
_m = dmm.read(BASE_MAP)


def _sci(a):
    return a.startswith(("/area/science", "/area/crew_quarters/heads/hor", "/area/security/checkpoint/science",
                         )) and a != "/area/science/test_area"


ZONE = {(x, y) for x in range(X0, X1 + 1) for y in range(Y0, Y1 + 1) if _sci(_m.get(x, y).apath)}
# the science maint room's west wall beside toxins: toxins gets its door there (bombs walk through the maint room to
# the launch room, as on the original)
ZONE.add((197, 103))
# outline tiles that stay exactly as they are: the mech bay launch shutters and its maint door, the genetics door,
# the testing lab's maint door, the delivery chute, the launch bay door and its airless run to space, the space
# notch the burn chamber vents into
KEEP = {(166, 127), (167, 127), (168, 127), (169, 127), (164, 126), (165, 115), (180, 87),
        (189, 121), (190, 121), (191, 121), (205, 104), (206, 104), (207, 104)}

lay = {}
room = {}
for p in ZONE:
    if p in KEEP:
        continue
    lay[p] = "#"


def _barrier(t):
    return t is None or t.tpath.startswith("/turf/closed") or t.has("/obj/machinery/door")         or t.has("/obj/effect/spawner/structure/window") or t.has("/obj/structure/grille")


# the outline's own wall ring: a zone tile must stay a wall only where something outside it is open (a hall, maint
# floor, space). Where the neighbour outside is already a wall, the room may come right up to it - otherwise every
# outer wall would be doubled and every room shrunk by a tile
EDGE = {p for p in ZONE if any((p[0] + dx, p[1] + dy) not in ZONE and not _barrier(_m.get(p[0] + dx, p[1] + dy))
                               for dx in (-1, 0, 1) for dy in (-1, 0, 1))}


def carve(x1, y1, x2, y2, r, ch="."):
    """Floor inside the outline; the outline's own wall ring stays (doors in it are placed on purpose)."""
    for x in range(x1, x2 + 1):
        for y in range(y1, y2 + 1):
            if (x, y) in lay and (x, y) not in EDGE:
                lay[(x, y)] = ch
                room[(x, y)] = r


def put(x, y, ch, r=None):
    if (x, y) not in lay:
        raise ValueError("%d,%d is outside the outline" % (x, y))
    lay[(x, y)] = ch
    if r:
        room[(x, y)] = r


def line(x1, y1, x2, y2, ch, r=None):
    for x in range(x1, x2 + 1):
        for y in range(y1, y2 + 1):
            put(x, y, ch, r)


LEGEND = {}
_pool = [chr(c) for c in range(0x100, 0x2000)]  # one private legend char per placed spec
_specs = {}


_tile_spec = {}


def spec(x, y, sp, r=None):
    """Put a legend spec (dict: obj, turf, mount, face...) on a tile; reuses a char for identical specs. A second
    spec on the same tile adds to the first (a button on the wall above a table keeps the table)."""
    if (x, y) in _tile_spec and lay.get((x, y)) not in ("#", "%", "."):
        old = dict(_tile_spec[(x, y)])
        for k, v in sp.items():
            if k in ("obj", "decal", "mount"):
                old[k] = list(old.get(k, [])) + list(v)
            else:
                old[k] = v
        sp = old
    _tile_spec[(x, y)] = sp
    key = repr(sp)
    if key not in _specs:
        _specs[key] = _pool.pop(0)
        LEGEND[_specs[key]] = sp
    put(x, y, _specs[key], r)


def objs(*o, **kw):
    d = dict(kw)
    d["obj"] = list(o)
    return d


def airlock(x, y, name, access=None, kind="research", glass=False, r=None, extra=()):
    vs = {"name": name}
    if access:
        vs["req_access_txt"] = access
    path = "/obj/machinery/door/airlock/%s%s" % (kind, "/glass" if glass else "")
    spec(x, y, objs((path, vs), *extra), r)


def window(x, y, r=None):
    put(x, y, "%", r)


# ------------------------------------------------------------------ rooms (interior floor)
# north band: on the main hall
carve(165, 117, 169, 126, "B")      # mech bay
carve(171, 117, 178, 125, "R")      # robotics (surgery bay rows 117-118 behind glass)
carve(180, 117, 182, 125, "F")      # foyer
carve(184, 117, 188, 125, "L")      # R&D
# research spine (east-west) and south spine
carve(166, 113, 188, 115, "s")
carve(179, 88, 181, 112, "s")
# middle band
carve(165, 106, 168, 111, "V")      # servers
carve(170, 106, 177, 111, "H")      # RD office
carve(183, 109, 185, 111, "K")      # security post at the crossroads
carve(187, 106, 195, 111, "N")      # nanites
carve(190, 113, 196, 119, "E")      # experimentation: work room (row 112: wall to the nanite lab)
carve(194, 113, 196, 115, "e")      # experimentation: blast chamber (the experimentor), walled off in the SE corner
# south
carve(165, 85, 177, 104, "X")       # xenobiology
carve(183, 95, 195, 103, "T")       # toxins mixing lab, canister bay on its east side
carve(185, 101, 189, 103, "C")      # burn chamber (vents west into the space notch at x183)
carve(202, 104, 206, 108, "D")      # launch room (driver on row 104), east of the science maint room
carve(183, 88, 194, 93, "M")        # testing lab
# no doubled walls: rooms run right up to a wall that's already there
carve(171, 126, 173, 126, "R")
window(174, 126)      # robotics up to the hall wall
carve(186, 126, 188, 126, "L")      # R&D up to the hall wall
carve(187, 105, 195, 105, "N")      # nanites down to the toxins/chamber roof
carve(196, 105, 196, 111, "N")      # nanites east to the outline
carve(196, 95, 196, 103, "T")       # toxins east to the outline (its maint door at 197,103)
carve(188, 85, 188, 87, "M")        # magnet range east
carve(186, 85, 187, 87, "M")        # its magnet range (x185 stays the wall to the maint nook with the air tanks)
# the room east of the RD office / west of the crossroads is the south spine; walls everywhere else

ROOMDEFS = {
    "B": dict(area="/area/science/robotics/mechbay", floor="/turf/open/floor/plasteel/dark", name="Mech Bay"),
    "R": dict(area="/area/science/robotics/lab", floor="/turf/open/floor/plasteel/white", name="Robotics Lab"),
    "F": dict(area="/area/science/research", floor="/turf/open/floor/plasteel/white", name="Research Foyer"),
    "L": dict(area="/area/science/lab", floor="/turf/open/floor/plasteel/white", name="Research and Development"),
    "s": dict(area="/area/science/research", floor="/turf/open/floor/plasteel/white", name="Research Division"),
    "V": dict(area="/area/science/server", floor="/turf/open/floor/plasteel/dark/telecomms", name="Server Room", vents=0),
    "H": dict(area="/area/crew_quarters/heads/hor", floor="/turf/open/floor/plasteel/cafeteria", name="Research Director's Office"),
    "K": dict(area="/area/security/checkpoint/science/research", floor="/turf/open/floor/plasteel/dark", name="Security Post - Science"),
    "N": dict(area="/area/science/nanite", floor="/turf/open/floor/plasteel/white", name="Nanite Lab"),
    "E": dict(area="/area/science/explab", floor="/turf/open/floor/plasteel/white", name="Experimentation Lab"),
    "e": dict(area="/area/science/explab", floor="/turf/open/floor/engine", name="Experimentation Chamber", main=False),
    "X": dict(area="/area/science/xenobiology", floor="/turf/open/floor/plasteel/white", name="Xenobiology Lab"),
    "T": dict(area="/area/science/mixing", floor="/turf/open/floor/plasteel/white", name="Toxins Mixing Lab"),
    "C": dict(area="/area/science/mixing/chamber", floor="/turf/open/floor/engine", name="Toxins Mixing Chamber", apc=False,
              bare=True, dress=False),
    "D": dict(area="/area/science/mixing", floor="/turf/open/floor/plasteel", name="Toxins Launch Room", main=False),
    "M": dict(area="/area/science/misc_lab", floor="/turf/open/floor/plasteel/white", name="Testing Lab"),
}
LEGEND.update({"%": {"turf": "rwindow"}})

# ------------------------------------------------------------------ doors, glass and openings
SHUT = "/obj/machinery/door/poddoor/shutters/preopen"
BIO = "/obj/machinery/door/poddoor/preopen/biohazard"
FD = "/obj/machinery/door/firedoor"
# mech bay <-> robotics: a wide shutter so a finished mech drives straight onto the charging pads
for y in (121, 122, 123):
    spec(170, y, objs((SHUT, {"name": "mech bay shutters", "id": "robo_mechbay"}), FD), "R")
# robotics: public desk on the hall, glass onto the foyer, surgery bay behind glass, staff door to the spine
spec(176, 126, objs("/obj/structure/table/reinforced",
                    ("/obj/machinery/door/window/southleft", {"name": "Robotics Desk", "req_access_txt": "29", "dir": 1}),
                    (SHUT, {"name": "robotics desk shutters", "id": "robotics_desk"})), "R")
window(175, 126)
window(177, 126)
for y in (120, 121, 122, 123, 124):
    window(179, y)
for x in (171, 172, 174, 175, 176, 177, 178):
    window(x, 119)
airlock(173, 119, "Robotics Surgery", "29", glass=True, r="R")
airlock(176, 116, "Robotics Lab", "29", r="R")
# foyer: the public airlock from the hall, lockdown shutters onto the spine
airlock(181, 126, "Research Division", None, glass=True, r="F", extra=(FD,))
window(180, 126)
window(182, 126)
for x in (180, 181, 182):
    spec(x, 116, objs((BIO, {"id": "Biohazard"}), "/obj/machinery/door/firedoor/heavy"), "F")
# R&D: public desk, glass onto the foyer, delivery chute on the east, staff door to the spine
spec(185, 126, objs("/obj/structure/table/reinforced",
                    ("/obj/machinery/door/window/southright", {"name": "Research and Development Desk",
                                                               "req_one_access_txt": "7;29", "dir": 1}),
                    (SHUT, {"name": "research lab shutters", "id": "rnd"})), "L")
window(184, 126)
for y in (119, 120, 121, 122, 123, 124):
    window(183, y)
airlock(186, 116, "Research and Development Lab", "7", r="L")
# RD office: glass onto the spine and the south spine, door to the spine, the servers behind it
airlock(174, 112, "Research Director's Office", "30", kind="command", glass=True, r="H")
for x in (171, 172, 173, 175, 176, 177):
    window(x, 112)
for y in (107, 108, 109, 110):
    window(178, y)
airlock(169, 109, "Server Room", "30", kind="command", r="V")
# security post at the crossroads: glass both ways
airlock(182, 110, "Security Post - Science", "63", kind="security", glass=True, r="K")
for y in (109, 111):
    window(182, y)
for x in (183, 184, 185):
    window(x, 112)
# nanites, experimentation
airlock(188, 112, "Nanite Lab", "7", glass=True, r="N")
airlock(189, 114, "Experimentation Lab", "7", r="E")
for y in (113, 115):
    window(193, y)
line(193, 116, 196, 116, "#")
for x in (194, 195):
    window(x, 116)
spec(193, 114, objs(("/obj/machinery/door/airlock/research/glass", {"name": "Test Chamber", "req_access_txt": "7"}),
                    ("/obj/machinery/door/poddoor/preopen", {"name": "test chamber blast door", "id": "telelab"})), "e")
# south: xenobiology, toxins, launch room, testing lab
airlock(178, 103, "Xenobiology Lab", "55", r="X")
put(165, 102, ".", "X")
airlock(182, 98, "Toxins Lab", "7", r="T")
airlock(197, 103, "Toxins Lab Maintenance", "8", r="T")
airlock(201, 106, "Toxins Launch Room", "8", r="D")
airlock(182, 90, "Testing Lab", "47", r="M")
for y in (101, 102, 103):
    spec(184, y, objs("/obj/machinery/door/poddoor/incinerator_toxmix"), "C")

put(195, 95, "#")
# fixed walls (a spec, so wall thinning leaves them): corners must meet edge to edge even where that keeps the
# original's two-thick wall
for p_ in ((165, 110),):
    spec(p_[0], p_[1], {"turf": "wall"})

# ------------------------------------------------------------------ the rooms' working layouts
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import science_v2_rooms  # noqa: E402
science_v2_rooms.furnish(dict(spec=spec, objs=objs, put=put, window=window, line=line, carve=carve))
science_v2_rooms.enrich(dict(spec=spec, put=put, lay=lay))
DISPOSAL_ENDS = {"deathsposal": (179, 71)}
FOOTPRINT = sorted({_m.get(*p).apath for p in ZONE})
TAPS = {"supply": [((188, 104), 2)], "scrubbers": [((188, 101), 1)]}  # the burn chamber airlock's fill and drain

# ------------------------------------------------------------------ out to text
LAYOUT = "\n".join("".join(lay.get((x, y), "~") for x in range(X0, X1 + 1)) for y in range(Y1, Y0 - 1, -1))
ROOMS = "\n".join("".join(room.get((x, y), "~") for x in range(X0, X1 + 1)) for y in range(Y1, Y0 - 1, -1))
