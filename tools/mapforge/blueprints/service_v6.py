"""Service for the v6 station plan (plan/station_plan.py), drawn by hand tile by tile (forge/proc/drawing.py).

    python tools/mapforge/plan/canvas.py
    python tools/mapforge/blueprints/service_v6.py            # run the graph, one picture per node
    python tools/mapforge/mapforge.py build blueprints/service_v6.py

The block sits east of arm N: the north-east arterial on its north, arm N and plaza N on its west, the ring on its
south, a maint seam and Dorms on its east, and a tail running south down the ring's east side.

How it plays (Meta's bar, kitchen, hydroponics, cafeteria and theatre):
  - The bar is the north-west corner, open to the arterial and arm N: the counter along the back wall, tables out
    front. Its south doors lead into the dining hall, which opens onto plaza N and the ring.
  - The kitchen sits east of the dining hall and serves it over the hatch; the cold room is behind it, the bar's
    staff door beside it. Hydroponics is north of the kitchen behind the smartfridge window (the hydro-kitchen-bar
    cluster the night walk asked for), with its own door onto the arterial.
  - The janitor's closet backs onto the maint seam; the theatre is the tail on the ring, stage at its far end.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge.proc import drawing  # noqa: E402
from forge.proc.shell import door, glass  # noqa: E402
from assets import service_v6 as assets  # noqa: E402

NAME = "service_v6"
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
BASE_MAP = os.path.join(ROOT, "data", "mapforge", "canvas_v6.dmm")
X0, Y0 = 91, 48
DRAWING = """\
######################
#BBBBBBBBBB#HHHHHHHHH#
#BBBBBBBBBB#HHHHHHHHH#
#BBBBBBBBBB#HHHHHHHHH#
#BBBBBBBBBB#HHHHHHHHH#
#BBBBBBBBBB#HHHHHHHHH#
#BBBBBBBBBB#HHHHHHHHH#
#BBBBBBBBBB###########
#BBBBBBBBBB#KKKKKKKKK#
#BBBBBBBBBB#KKKKKKKKK#
############KKKKKKKKK#
#DDDDDDDDDD#KKKKKKKKK#
#DDDDDDDDDD#KKKKKKKKK#
#DDDDDDDDDD#KKKKKKKKK#
####DDDDDDD#KKKKKKKKK#
   #DDDDDDD###########
   #DDDDDDD#FFFF#JJJJ#
   #DDDDDDD#FFFF#JJJJ#
   #DDDDDDD#FFFF#JJJJ#
   ###################
            #TTTTTTTT#
            #TTTTTTTT#
            #TTTTTTTT#
            #TTTTTTTT#
            #TTTTTTTT#
            #TTTTTTTT#
            #TTTTTTTT#
            ######TTT#
                 #TTT#
                 #####
"""
CHARS = {"B": "bar", "D": "dining", "H": "hydro", "K": "kitchen", "F": "cold", "J": "janitor", "T": "theatre"}

GREY, DARK, WHITE = "/turf/open/floor/plasteel", "/turf/open/floor/plasteel/dark", "/turf/open/floor/plasteel/white"
ROOM_TABLE = {
    "bar": dict(area="/area/crew_quarters/bar", floor=GREY, name="Bar", label="BAR"),
    "dining": dict(area="/area/crew_quarters/cafeteria", floor="/turf/open/floor/plasteel/cafeteria",
                   name="Cafeteria", label="DINING"),
    "kitchen": dict(area="/area/crew_quarters/kitchen", floor="/turf/open/floor/plasteel/cafeteria",
                    name="Kitchen", label="KITCHEN"),
    "cold": dict(area="/area/crew_quarters/kitchen", floor="/turf/open/floor/plasteel/showroomfloor",
                 name="Kitchen Cold Room", main=False, label="COLD"),
    "hydro": dict(area="/area/hydroponics", floor=GREY, name="Hydroponics", label="HYDRO"),
    "janitor": dict(area="/area/janitor", floor=GREY, name="Custodial Closet", label="JANITOR"),
    "theatre": dict(area="/area/crew_quarters/theatre", floor=DARK, name="Theatre", label="THEATRE"),
}
AREAS = ("/area/crew_quarters/bar", "/area/crew_quarters/cafeteria", "/area/crew_quarters/kitchen",
         "/area/hydroponics", "/area/janitor", "/area/crew_quarters/theatre")


def in_zone(a):
    return a.startswith(AREAS)


PUB = dict(kind="public", glass=True)
LINKS = [
    # the bar: open to the arterial and arm N, double doors through to dining
    door("bar", "hall", wide=2, at=("y", 117), name="Bar", **PUB),
    door("bar", "hall", wide=2, at=("x", 97.5), name="Bar", **PUB),
    glass("bar", "hall", inset=1),
    door("bar", "dining", wide=2, name="Cafeteria", **PUB),
    # dining: onto plaza N and the ring
    door("dining", "hall", at=("x", 97), name="Cafeteria", **PUB),
    door("dining", "hall", wide=2, at=("y", 98), name="Cafeteria", **PUB),
    glass("dining", "hall", inset=1),
    # the kitchen: the hatch onto dining, the bar's staff door, the cold room, hydroponics through the fridge window
    door("kitchen", "dining", type="desk", at=("y", 104), name="Kitchen Hatch", access="28", id="kitchen"),
    door("kitchen", "dining", type="desk", at=("y", 103), name="Kitchen Hatch", access="28", id="kitchen"),
    door("kitchen", "dining", type="desk", at=("y", 105), name="Kitchen Hatch", access="28", id="kitchen"),
    door("kitchen", "bar", name="Kitchen", access="28", kind="public"),
    door("cold", "kitchen", name="Kitchen Cold Room", access="28", kind="public"),
    door("hydro", "kitchen", at=("x", 114), type="smartfridge"),
    door("hydro", "kitchen", name="Hydroponics", access="35", kind="public", glass=True),
    door("hydro", "hall", name="Hydroponics", access="35", kind="public", glass=True),
    glass("hydro", "hall", inset=1),
    door("hydro", "maint", name="Hydroponics Maintenance", access="35", kind="maintenance"),
    # janitor and theatre
    door("janitor", "maint", name="Custodial Closet", access="26", kind="maintenance"),
    door("theatre", "hall", wide=2, name="Theatre", **PUB),
    door("theatre", "maint", at=("y", 90), name="Theatre Backstage", access="46", kind="maintenance"),
]

_graph, _geo, _bp = drawing.department(NAME, BASE_MAP, DRAWING, CHARS, X0, Y0, ROOM_TABLE, LINKS, assets.ASSETS,
                                       in_zone)
globals().update(_bp)

if __name__ == "__main__":
    drawing.report(_graph, _geo, ROOT)
