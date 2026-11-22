"""Science for the v6 station plan (plan/station_plan.py), designed by hand through the node graph like Medical v6.

    python tools/mapforge/plan/canvas.py                       # the plan as a bare map (once, or after plan edits)
    python tools/mapforge/blueprints/science_v6.py             # run the graph, one picture per node
    python tools/mapforge/mapforge.py build blueprints/science_v6.py

The block is south of the south-west arterial (art SW) and west of arm S: a wide front band on the arterial, the
research street under it, and a tail running south into space with toxins at its end.

How it plays (studies/mapping_practice.md stage 5, the Science v3 program):
  - The public come to the arterial front: robotics and R&D serve over their desks, the foyer between them leads in
    past the security post's glass. Biohazard shutters close the foyer off the street.
  - The research street runs the band's length: the maint door at its west end, a staff door onto arm S at its east.
    Robotics, R&D and the RD office open onto it from the north; nanites and experimentation from the south.
  - Mechs leave the mech bay by its launch shutters onto the arterial; robotics feeds the bay through its own
    shutters, surgery in robotics' corner.
  - Xenobiology is the deep east room off the toxins corridor, its pens along the hull beyond a biohazard door.
  - The toxins corridor runs south down the tail to toxins, the burn chamber venting through the west hull, and the
    launch room at the very end firing bombs out through the south hull.
Coordinates are the canvas map's (y up). The plan's x, y map to x + 6, 165 - y.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge.proc import geo as G  # noqa: E402
from forge.proc import shell, furnish, emit  # noqa: E402
from assets import science_v6 as assets  # noqa: E402
from forge.proc.shell import X, Y, door, desk, glass  # noqa: E402

NAME = "science_v6"
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
BASE_MAP = os.path.join(ROOT, "data", "mapforge", "canvas_v6.dmm")
BBOX = (46, 14, 98, 58)
SERVERS = (90, 52)              # the server chamber's glazed wall, bottom tile: the chamber is x 91-92, y 52-54
BURN = (73, 22)                 # the burn chamber's anchor: its vent doors at x 73, y 23-25, open to the hull holes


def in_zone(a):
    return a.startswith("/area/science")


PARAMS = dict(seed=1)

SCI, XENO, MIX = "/area/science", "/area/science/xenobiology", "/area/science/mixing"
WHITE, GREY, DARK, ENG = ("/turf/open/floor/plasteel/white", "/turf/open/floor/plasteel",
                          "/turf/open/floor/plasteel/dark", "/turf/open/floor/engine")
ROOM_TABLE = {
    "spine": dict(area=SCI + "/research", floor=WHITE, name="Research Division", hall=True, label="STREET"),
    "foyer": dict(area=SCI + "/research", floor=WHITE, name="Research Foyer", hall=True, label="FOYER"),
    "toxhall": dict(area=SCI + "/research", floor=WHITE, name="Toxins Corridor", hall=True, label="TOX HALL"),
    "mechbay": dict(area=SCI + "/robotics/mechbay", floor=DARK, name="Mech Bay", label="MECH BAY"),
    "robotics": dict(area=SCI + "/robotics/lab", floor=WHITE, name="Robotics Lab", label="ROBOTICS"),
    "surgery": dict(area=SCI + "/robotics/lab", floor=WHITE, name="Robotics Surgery", main=False, label="SURG"),
    "rnd": dict(area=SCI + "/lab", floor=WHITE, name="Research and Development", label="R&D"),
    "explab": dict(area=SCI + "/explab", floor=GREY, name="Experimentation Lab", label="EXPERIMENT"),
    "chamber": dict(area=SCI + "/explab", floor=ENG, name="Experimentation Chamber", main=False, label="EXP"),
    "server": dict(area=SCI + "/server", floor=DARK, name="Server Room", vents=0, label="SERVER"),
    "servercore": dict(area=SCI + "/server", floor="/turf/open/floor/circuit/telecomms/server", name="Server Room",
                       apc=False, bare=True, dress=False, module=True, label=""),
    "rdoffice": dict(area="/area/crew_quarters/heads/hor", floor="/turf/open/floor/plasteel/cafeteria",
                     name="Research Director's Office", label="RD OFFICE"),
    "secpost": dict(area="/area/security/checkpoint/science/research", floor=DARK, name="Security Post - Science",
                    label="POST"),
    "cell": dict(area="/area/security/checkpoint/science/research", floor="/turf/open/floor/plasteel/grimy",
                 name="Science Holding Cell", main=False, label="CELL"),
    "nanite": dict(area=SCI + "/nanite", floor=WHITE, name="Nanite Lab", label="NANITES"),
    "xeno": dict(area=XENO, floor=WHITE, name="Xenobiology Lab", label="XENOBIOLOGY"),
    "pens": dict(area=XENO, floor=DARK, name="Xenobiology Pens", main=False, label="PENS"),
    "toxins": dict(area=MIX, floor=GREY, name="Toxins Mixing Lab", label="TOXINS"),
    "burn": dict(area=MIX + "/chamber", floor=ENG, name="Toxins Mixing Chamber", apc=False, bare=True, dress=False,
                 module=True, label=""),
    "launch": dict(area=MIX, floor=GREY, name="Toxins Launch Room", main=False, label="LAUNCH"),
    "launchrun": dict(area=MIX, floor=GREY, name="Mass Driver", main=False, bare=True, label=""),
}
PENS = ["pen1", "pen2", "pen3", "pen4"]
for _i, _p in enumerate(PENS):
    ROOM_TABLE[_p] = dict(area=XENO, floor=ENG, name="Containment Pen", main=False, label="P%d" % (_i + 1),
                          asset="pen", pen=_i + 1, camera=False, dress=False, plant=False)


def plans(P):
    """Three slicing plans. Sizes count tiles from each rect's west or north edge; walls go between.
      front band (x 51-92, y 43-54): mech bay, robotics, foyer, the post, R&D, the RD's suite; the street under it
      south (x 59-92, y 30-41): nanites, experimentation, the toxins corridor, xenobiology over its pens
      tail (x 73-84, y 18-28): toxins over the launch room"""
    robotics = Y((1.0, "robotics"), (2, X((1.0, "robotics"), (4, "surgery"))))
    secsuite = Y((3, "cell"), (1.0, "secpost"))      # the post on the research street, its cell behind it
    # 2026-11-22 size_budget: R&D 65 tiles and the servers 21 against stock 27-48 and 12-15; R&D gives two
    # columns to the foyer, and the foyer two more so the RD's suite is 5 wide: the servers 5x3 (the 3x3 server
    # chamber module stays at its east end), the RD's office 5x5
    rdsuite = Y((3, "server"), (1.0, "rdoffice"))
    # R&D beside the foyer, the post beside the RD's suite, and R&D's west column takes the foyer's top three rows: an
    # L as the stock labs are (the gate 2026-11-22: R&D a 5x8 box, fill 0.91 against the accepted 0.90 and the stock
    # 0.65-0.77; the foyer, 9 wide and bare since the 11-22 shrink, gives the tiles)
    front = X((6, "mechbay"), (8, robotics), (7, "foyer"), (1, Y((3, "rnd"), (1.0, "foyer"))), (5, "rnd"),
              (3, secsuite), (1.0, rdsuite))
    explab = X((1.0, "explab"), (3, Y((1, "explab"), (1.0, "chamber"))))
    pens = X((3, "pen1"), (3, "pen2"), (3, "pen3"), (1.0, "pen4"))
    xeno = Y((4, "xeno"), (3, "pens"), (1.0, pens))
    south = X((6, "nanite"), (7, explab), (3, "toxhall"), (1.0, xeno))
    tail = Y((1.0, "toxins"), (2, X((1.0, "launch"), (1, "launchrun"))))
    return [((51, 43, 92, 54), Y((8, front), (1.0, "spine"))),
            ((59, 30, 92, 41), south),
            ((73, 18, 84, 28), tail)]


LINKS = [
    # the public front on the arterial
    door("foyer", "hall", wide=2, name="Research Division", glass=True, firedoor=True),
    # the walls either side of the glass doors carry the division signs
    door("foyer", "spine", wide=2, type="blast", id="Biohazard", name="Research Division", one_access="47;29;7",
         kind="research"),
    desk("robotics", "hall", name="Robotics Desk", access="29", id="robotics_desk"),
    glass("robotics", "hall", runs="door"),
    desk("rnd", "hall", name="Research and Development Desk", one_access="7;29", id="rnd"),
    glass("rnd", "hall", runs="door"),
    # the post watches the foyer and the arterial; its cell behind
    door("secpost", "spine", name="Security Post - Science", access="63", kind="security", glass=True),
    glass("secpost", "spine", runs="door"),
    door("cell", "secpost", type="windoor", name="Holding Cell", access="63"),
    glass("cell", "secpost"),
    # robotics and the mech bay
    door("mechbay", "hall", wide=3, type="shutter", id="Skynet_launch", name="Mech Bay"),
    door("mechbay", "robotics", wide=3, at=("y", 52), type="shutter", id="robo_mechbay", name="mech bay shutters"),
    door("mechbay", "maint", name="Mech Bay Maintenance", access="29", kind="maintenance"),
    door("robotics", "spine", name="Robotics Lab", access="29"),
    door("surgery", "robotics", name="Robotics Surgery", access="29", glass=True),
    glass("surgery", "robotics", runs="all"),
    door("rnd", "spine", name="Research and Development Lab", access="7"),
    # the RD's suite: the office on the street and onto arm S, the servers behind it
    door("rdoffice", "spine", name="Research Director's Office", access="30", kind="command", glass=True),
    glass("rdoffice", "spine", inset=1),
    glass("rdoffice", "hall", inset=1),
    door("server", "rdoffice", name="Server Room", access="30", kind="command"),
    # the street's ends
    door("spine", "maint", name="Research Maintenance", access="47", kind="maintenance"),
    door("spine", "hall", name="Research Division", access="47", glass=True),
    # south of the street
    door("nanite", "spine", name="Nanite Lab", access="7", glass=True),
    glass("nanite", "spine", inset=1),
    door("explab", "spine", name="Experimentation Lab", access="7"),
    door("chamber", "explab", type="blast", id="telelab", name="Test Chamber", access="7"),
    glass("chamber", "explab"),
    door("toxhall", "spine", wide=2, name="Toxins Wing", access="7", glass=True),
    # xenobiology off the toxins corridor, the pens beyond its containment shutters
    door("xeno", "toxhall", name="Xenobiology Lab", access="55"),
    door("pens", "xeno", wide=3, type="biohazard", id="xeno_containment"),
] + [ln for i, p in enumerate(PENS) for ln in (
    door(p, "pens", type="pen", id="xenobio%d" % (i + 1), name="Containment Pen", access="55"),
    glass(p, "pens"))] + [
    # toxins at the tail's end, the launch room past it, the driver's door in the hull
    door("toxins", "toxhall", name="Toxins Lab", access="7"),
    door("launch", "toxins", name="Toxins Launch Room", access="8"),
    door("launch", "launchrun", type="windoor", name="Mass Driver Door", access="7"),
    glass("launch", "launchrun"),
    door("launchrun", "space", type="driver", id="toxinsdriver", name="Mass Driver Door"),
]


def graph(**over):
    P = dict(PARAMS)
    P.update(over)
    g = G.Graph(NAME, **P)
    g.add("outline", shell.outline, view="kind", base=BASE_MAP, bbox=BBOX, in_zone=in_zone)
    g.add("slice", shell.slice_rooms, view="rooms", plans=plans(P), rooms=ROOM_TABLE)
    g.add("stamp", shell.stamp, view="rooms", stamps=[("burn", lambda geo: BURN, "burn", assets.burn_chamber_closed()),
                                                     ("servercore", lambda geo: SERVERS, "servercore", assets.server_core())], rooms=ROOM_TABLE)
    g.add("tidy", shell.tidy, view="rooms")
    g.add("openings", shell.openings, view="rooms", links=LINKS)
    g.add("fields", shell.fields, view="fields")
    g.add("furnish", furnish.furnish, view="items", assets=assets.ASSETS)
    return g


_graph = graph()
_geo = _graph.run()
_burn = _geo.attr.get("_anchor", {}).get("burn", (0, 0))
globals().update(emit.blueprint(_geo, NAME, extra=dict(
    STYLE="meta", DISPOSALS="route", BASE=BASE_MAP,
    # the burn chamber airlock's fill and drain join the station's air and waste lines
    TAPS={"supply": [((_burn[0] + 4, _burn[1] + 4), 2)], "scrubbers": [((_burn[0] + 4, _burn[1] + 1), 1)]})))


def main():
    g, geo = _graph, _geo
    out = os.path.join(ROOT, "data", "previews", "mapforge", "proc")
    paths = g.pictures(out, tile=20)
    G.sheet(paths, os.path.join(out, NAME + "_nodes.png"), cols=3)
    G.draw(geo, "items", os.path.join(out, NAME + "_furnish_big.png"), tile=24, title="furnish")
    for n in geo.notes:
        print(n)
    for p in geo.problems:
        print("PROBLEM", p)
    print("pictures:", os.path.relpath(os.path.join(out, NAME + "_nodes.png"), ROOT))


if __name__ == "__main__":
    main()
