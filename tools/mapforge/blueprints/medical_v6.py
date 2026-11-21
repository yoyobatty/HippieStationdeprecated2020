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
  - The ward (sleepers, cryo) sits at the front west: the first room off the lobby.
  - Chemistry hands medicine out over a desk onto arm S; genetics and cloning sit off the hall's west end, the
    store at the street's foot, the CMO across the street from the store, near command.
  - The morgue sits off the street beside genetics, with a door straight into it, so a body reaches the cloner in
    a few steps; the rear entrance (medical or morgue access) brings bodies in from the arterial. The store opens
    off the scrub room, behind the theatre. The back door is the hall's west end into the maint seam.
Coordinates are the canvas map's (y up). The plan's x, y map to x + 6, 165 - y.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge.proc import drawing  # noqa: E402
from assets import medical_v6 as assets  # noqa: E402
from forge.proc.shell import door, desk, glass  # noqa: E402

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
    "medhall": dict(area=MED + "/medbay/central", floor=WHITE, name="Medbay", hall=True, plant=False, label="MEDBAY"),
    "recovery": dict(area=MED + "/sleeper", floor=WHITE, name="Medbay Ward", label="WARD"),
    "genetics": dict(area=MED + "/genetics", floor=WHITE, name="Genetics and Cloning", label="GENETICS"),
    "chemistry": dict(area=MED + "/chemistry", floor=WHITE, name="Chemistry", label="CHEM"),
    "scrub": dict(area=MED + "/medbay/aft", floor=WHITE, name="Surgical Scrub", plant=False, label="SCRUB"),
    "theatre": dict(area=MED + "/surgery", floor=WHITE, name="Operating Theatre", label="THEATRE"),
    "medstore": dict(area=MED + "/storage", floor=WHITE, name="Medbay Storage", label="STORE"),
    "exam": dict(area=MED + "/exam_room", floor=WHITE, name="Exam Room", label="EXAM"),
    "roomA": dict(area=MED + "/patients_rooms/room_a", floor=WHITE, name="Patient Room A", camera=False, label="A"),
    "roomB": dict(area=MED + "/patients_rooms/room_b", floor=WHITE, name="Patient Room B", camera=False, label="B"),
    "cmo": dict(area="/area/crew_quarters/heads/cmo", floor="/turf/open/floor/plasteel/cafeteria",
                name="Chief Medical Officer's Office", label="CMO"),
    "morgue": dict(area=MED + "/morgue", floor="/turf/open/floor/plasteel/dark", name="Morgue", label="MORGUE"),
}


# Review 1 (2026-11-21) moved the block onto a hand drawing (plan coordinates, '#' wall, CHARS per room): the
# morgue sits by genetics and the street so a body reaches the cloner in a few steps, the store took the morgue's
# old east slot behind the theatre, the street is 2 wide, reception shrank for an exam room, the lobby's dead-end
# corner and the cross hall's bare tail are gone.
X0, Y0 = 56, 81
DRAWING = """\
################
#IIIIIIII#XXX###
#IIIIIIII#XXX########
#IIIIIIII#XXX#DDDDDD#
#IIIIIIII#####DDDDDD#
#IIIIIIII#HHH#DDDDDD#
#IIIIIIII#HHH#DDDDDD#
#IIIIIIII#HHH#DDDDDD#
#IIIIIIII#HHH#DDDDDD#
#####################
#EEEEEEEEEEEEEEEEEEE#
#EEEEEEEEEEEEEEEEEEE#########
#EEEEEEEEEEEEEEEEEEEEEEE#AAA#
#############EE##########AAA#
#CCCCCCC#JJJ#EE#BBBBBBBB#AAA#
#CCCCCCC#JJJ#EE#BBBBBBBB#AAA#
#CCCCCCC#####EE#BBBBBBBB#AAA####
#CCCCCCC#KKK#EE#BBBBBBBB#AAAAAA#
#######C#KKK#EE##########AAAAAA#
      #######EE#LLLLLLLL#AAAAAA#
      #GGGGG#EE#LLLLLLLL#AAAAAA#
      #GGGGG#EE#################
      #GGGGG#EE#MMMMMM#FFFFFFFF#
      #GGGGG#EE#MMMMMM#FFFFFFFF#
      #GGGGG#EE#MMMMMM#FFFFFFFF#
      #GGGGG#EE#MMMMMM#FFFFFFFF#
      ##########################
"""
CHARS = {"I": "recovery", "H": "reception", "X": "exam", "D": "lobby", "E": "medhall", "C": "genetics",
         "J": "roomA", "K": "roomB", "G": "morgue", "B": "cmo", "A": "chemistry", "L": "scrub", "M": "theatre",
         "F": "medstore"}


LINKS = [
    # the public front: plaza W and the ring both lead into the lobby; the desk; glass doors on into the hall
    door("lobby", "hall", wide=2, at=("x", 79.5), name="Medbay", access="", kind="medical", glass=True),
    door("lobby", "hall", at=("y", 78), name="Medbay", access="", kind="medical", glass=True),
    desk("reception", "lobby", name="Medbay Reception", access="5", id="med_reception"),
    door("reception", "medhall", name="Medbay Reception", access="5", kind="medical"),
    door("lobby", "medhall", wide=2, name="Medbay", access="5", kind="medical", glass=True),
    door("exam", "lobby", name="Exam Room", access="5", kind="medical", glass=True),
    glass("lobby", "medhall", runs="door"),
    # the ward: off the hall, a window onto arm W and onto the hall
    door("recovery", "medhall", at=0.7, name="Medbay Ward", access="5", kind="medical", glass=True),
    glass("recovery", "medhall", inset=1),
    # genetics and the patient rooms off the hall's west end
    door("genetics", "medhall", name="Genetics and Cloning", access="5", kind="medical"),
    glass("genetics", "medhall", inset=2),
    door("roomA", "medhall", name="Patient Room A", access="5", kind="medical"),
    door("roomB", "medhall", name="Patient Room B", access="5", kind="medical"),
    # the street: the store at its foot, the CMO and the surgical wing across it
    door("medstore", "scrub", name="Medbay Storage", access="5", kind="medical"),
    door("medstore", "chemistry", name="Medbay Storage", access="5", kind="medical"),
    door("cmo", "medhall", name="Chief Medical Officer", access="40", kind="command", glass=True),
    glass("cmo", "medhall", inset=1),
    door("scrub", "medhall", name="Surgical Wing", access="5", kind="medical", glass=True),
    door("theatre", "scrub", name="Operating Theatre", access="45", kind="medical"),
    glass("theatre", "scrub", inset=1),
    # chemistry: staff door off the hall, a hand-out desk onto arm S with a window either side of it
    door("chemistry", "medhall", name="Chemistry", access="33", kind="medical"),
    desk("chemistry", "hall", name="Chemistry Desk", access="33", id="chem_desk"),
    glass("chemistry", "hall", inset=1),
    # the morgue: off the street, with a door straight into genetics for the cloner
    door("morgue", "medhall", name="Morgue", access="6", kind="medical"),
    door("morgue", "genetics", name="Morgue", access="6", kind="medical"),
    # the street's foot: the staff and stretcher entrance onto the arterial, so the street is no dead end
    door("medhall", "hall", at=("x", 76), name="Medbay Rear Entrance", one_access="5;6", kind="medical",
         glass=True),
    # the back door into maint
    door("medhall", "maint", name="Medbay Maintenance", access="5", kind="maintenance"),
]


_graph, _geo, _bp = drawing.department(NAME, BASE_MAP, DRAWING, CHARS, X0, Y0, ROOM_TABLE, LINKS, assets.ASSETS,
                                       in_zone, extra=dict(DRESS_HALL_FRONT=True))
globals().update(_bp)


if __name__ == "__main__":
    drawing.report(_graph, _geo, ROOT)
