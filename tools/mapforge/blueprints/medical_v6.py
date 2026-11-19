"""Medical for the v6 station plan (plan/station_plan.py), designed by hand through the node graph like Science v3.

    python tools/mapforge/plan/canvas.py                       # the plan as a bare map (once, or after plan edits)
    python tools/mapforge/blueprints/medical_v6.py             # run the graph, one picture per node
    python tools/mapforge/mapforge.py build blueprints/medical_v6.py

The block is the SW wedge against the hall ring: arm W along its north side, the ring and plaza W on its north-east
corner, arm S and plaza S on its east side, the south-west arterial below, a maint seam and maint room to the west.

How it plays (studies/mapping_practice.md stage 5):
  - Patients arrive from the ring corner: the lobby opens north onto plaza W and east onto the ring, the reception
    desk beside it. Glass double doors lead on into the medbay hall.
  - The medbay hall is a T: a cross hall under the front rooms, and a street running south from it. Every staff
    room opens off one of the two, so a doctor never walks through one room to reach another, except the theatre
    (through its scrub room) and the morgue (through the theatre, bodies leaving surgery).
  - The ward (sleepers, cryo) sits at the front west, with a window onto arm W: the first room off the lobby.
  - Chemistry hands medicine out over a desk onto arm S; genetics and cloning sit off the hall's west end, the
    store at the street's foot, the CMO across the street from the store, near command.
  - The back door is the hall's west end into the maint seam; the morgue has its own door onto the arterial, for
    the chaplain and for bodies brought in from outside.
Coordinates are the canvas map's (y up). The plan's x, y map to x + 6, 165 - y.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge.proc import geo as G  # noqa: E402
from forge.proc import shell, furnish, emit  # noqa: E402
from assets import medical_v6 as assets  # noqa: E402
from forge.proc.shell import X, Y, door, desk, glass  # noqa: E402

NAME = "medical_v6"
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
BASE_MAP = os.path.join(ROOT, "data", "mapforge", "canvas_v6.dmm")
BBOX = (60, 56, 96, 86)


def in_zone(a):
    return a.startswith("/area/medical")


PARAMS = dict(seed=1)

MED = "/area/medical"
WHITE = "/turf/open/floor/plasteel/white"
ROOM_TABLE = {
    "lobby": dict(area=MED + "/medbay/lobby", floor=WHITE, name="Medbay Lobby", newscaster=True, label="LOBBY"),
    "reception": dict(area=MED + "/medbay/lobby", floor=WHITE, name="Medbay Reception", main=False, label="DESK"),
    "medhall": dict(area=MED + "/medbay/central", floor=WHITE, name="Medbay", hall=True, label="MEDBAY"),
    "recovery": dict(area=MED + "/sleeper", floor=WHITE, name="Medbay Ward", label="WARD"),
    "genetics": dict(area=MED + "/genetics", floor=WHITE, name="Genetics and Cloning", label="GENETICS"),
    "chemistry": dict(area=MED + "/chemistry", floor=WHITE, name="Chemistry", label="CHEM"),
    "scrub": dict(area=MED + "/medbay/aft", floor=WHITE, name="Surgical Scrub", label="SCRUB"),
    "theatre": dict(area=MED + "/surgery", floor=WHITE, name="Operating Theatre", label="THEATRE"),
    "medstore": dict(area=MED + "/storage", floor=WHITE, name="Medbay Storage", label="STORE"),
    "roomA": dict(area=MED + "/patients_rooms/room_a", floor=WHITE, name="Patient Room A", camera=False, label="A"),
    "roomB": dict(area=MED + "/patients_rooms/room_b", floor=WHITE, name="Patient Room B", camera=False, label="B"),
    "cmo": dict(area="/area/crew_quarters/heads/cmo", floor="/turf/open/floor/plasteel/cafeteria",
                name="Chief Medical Officer's Office", label="CMO"),
    "morgue": dict(area=MED + "/morgue", floor="/turf/open/floor/plasteel/dark", name="Morgue", label="MORGUE"),
}


def plans(P):
    """One slicing plan over the whole block (x 62-92, y 59-83; outline ring tiles are skipped by the cuts).
    North to south: the front rooms, the cross hall, then the back: genetics and two patient rooms over the store,
    the street, the CMO over scrub and theatre, chemistry over the morgue."""
    front = X((9, "recovery"), (3, "reception"), (1.0, "lobby"))
    west = Y((5, X((1.0, "genetics"), (3, Y((1.0, "roomA"), (1.0, "roomB"))))), (1.0, "medstore"))
    mid = Y((4, "cmo"), (2, "scrub"), (1.0, "theatre"))
    east = Y((7, "chemistry"), (1.0, "morgue"))
    back = X((12, west), (3, "medhall"), (7, mid), (1.0, east))
    return [((62, 59, 92, 83), Y((8, front), (3, "medhall"), (1.0, back)))]


LINKS = [
    # the public front: plaza W and the ring both lead into the lobby; the desk; glass doors on into the hall
    door("lobby", "hall", wide=2, at=("x", 79.5), name="Medbay", access="", kind="medical", glass=True),
    door("lobby", "hall", at=("y", 78), name="Medbay", access="", kind="medical", glass=True),
    desk("reception", "lobby", name="Medbay Reception", access="5", id="med_reception"),
    door("reception", "medhall", name="Medbay Reception", access="5", kind="medical"),
    door("lobby", "medhall", wide=2, name="Medbay", access="5", kind="medical", glass=True),
    glass("lobby", "medhall", runs="door"),
    # the ward: off the hall, a window onto arm W and onto the hall
    door("recovery", "medhall", at=0.7, name="Medbay Ward", access="5", kind="medical", glass=True),
    glass("recovery", "medhall", inset=1),
    glass("recovery", "hall", inset=2),
    # genetics and the patient rooms off the hall's west end
    door("genetics", "medhall", name="Genetics and Cloning", access="5", kind="medical"),
    glass("genetics", "medhall", inset=2),
    door("roomA", "medhall", name="Patient Room A", access="5", kind="medical"),
    door("roomB", "medhall", name="Patient Room B", access="5", kind="medical"),
    # the street: the store at its foot, the CMO and the surgical wing across it
    door("medstore", "medhall", name="Medbay Storage", access="5", kind="medical"),
    door("cmo", "medhall", name="Chief Medical Officer", access="40", kind="command", glass=True),
    glass("cmo", "medhall", inset=1),
    door("scrub", "medhall", name="Surgical Wing", access="5", kind="medical", glass=True),
    door("theatre", "scrub", name="Operating Theatre", access="45", kind="medical"),
    glass("theatre", "scrub", inset=1),
    # chemistry: staff door off the hall, a hand-out desk onto arm S with a window either side of it
    door("chemistry", "medhall", name="Chemistry", access="33", kind="medical"),
    desk("chemistry", "hall", name="Chemistry Desk", access="33", id="chem_desk"),
    glass("chemistry", "hall", inset=1),
    # the morgue: bodies from surgery, and its own door onto the arterial at the east end, clear of the trays
    door("morgue", "theatre", at=("y", 62), name="Morgue", access="6", kind="medical"),
    door("morgue", "hall", at=("x", 92), name="Morgue", access="6", kind="medical"),
    # the street's foot: the staff and stretcher entrance onto the arterial, so the street is no dead end
    door("medhall", "hall", at=("x", 76), name="Medbay Rear Entrance", access="5", kind="medical", glass=True),
    # the cross hall's east tail past chemistry: a staff door onto plaza S, so it leads somewhere
    door("medhall", "hall", at=("y", 72), name="Medbay", access="5", kind="medical", glass=True),
    # the back door into maint
    door("medhall", "maint", name="Medbay Maintenance", access="5", kind="maintenance"),
]


def graph(**over):
    P = dict(PARAMS)
    P.update(over)
    g = G.Graph(NAME, **P)
    g.add("outline", shell.outline, view="kind", base=BASE_MAP, bbox=BBOX, in_zone=in_zone)
    g.add("slice", shell.slice_rooms, view="rooms", plans=plans(P), rooms=ROOM_TABLE)
    g.add("tidy", shell.tidy, view="rooms")
    g.add("openings", shell.openings, view="rooms", links=LINKS)
    g.add("fields", shell.fields, view="fields")
    g.add("furnish", furnish.furnish, view="items", assets=assets.ASSETS)
    return g


_graph = graph()
_geo = _graph.run()
globals().update(emit.blueprint(_geo, NAME, extra=dict(STYLE="meta", DISPOSALS="route", DRESS_HALL_FRONT=True,
                                                       BASE=BASE_MAP)))


def main():
    g, geo = _graph, _geo
    out = os.path.join(ROOT, "data", "previews", "mapforge", "proc")
    paths = g.pictures(out, tile=20)
    G.sheet(paths, os.path.join(out, NAME + "_nodes.png"), cols=3)
    G.draw(geo, "items", os.path.join(out, NAME + "_furnish_big.png"), tile=30, title="furnish")
    for n in geo.notes:
        print(n)
    for p in geo.problems:
        print("PROBLEM", p)
    print("pictures:", os.path.relpath(os.path.join(out, NAME + "_nodes.png"), ROOT))


if __name__ == "__main__":
    main()
