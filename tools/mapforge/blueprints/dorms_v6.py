"""Dorms for the v6 station plan (plan/station_plan.py), drawn by hand tile by tile (forge/proc/drawing.py).

    python tools/mapforge/plan/canvas.py
    python tools/mapforge/blueprints/dorms_v6.py
    python tools/mapforge/mapforge.py build blueprints/dorms_v6.py

The block sits east of Service across a maint seam, its front on arm E, its back on maint north and west, space east.

How it plays (Meta's dormitories): the crew come off arm E into the lounge; the dorm hall runs north from it with the
cabins either side, each with a bolt button inside its door; the restrooms and the locker room with the washing
machines off the hall; the fitness room fills the east lobe. The hall's north end is a maint door.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge.proc import drawing  # noqa: E402
from forge.proc.shell import door, glass  # noqa: E402
from assets import dorms_v6 as assets  # noqa: E402

NAME = "dorms_v6"
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
BASE_MAP = os.path.join(ROOT, "data", "mapforge", "canvas_v6.dmm")
X0, Y0 = 115, 52
DRAWING = """\
##############
#1111#HH#5555#
#1111#HH#5555#
#1111#HH#5555#
######HH###########
#2222#HH#KKKKKKKKK#
#2222#HH#KKKKKKKKK#
#2222#HH#KKKKKKKKK#
######HH###########
#3333#HH#FFFFFFFFF#
#3333#HH#FFFFFFFFF#
#3333#HH#FFFFFFFFF#
######HH#FFFFFFFFF#
#4444#HH#FFFFFFFFF#
#4444#HH#FFFFFFFFF#
#4444#HH#FFFFFFFFF#
######HH#FFFFFFFFF#
#s#tt#HH###########
######HH#6666#
#RRRR#HH#6666#
#RRRR#HH#6666#
######HH######
#LLLLLLLLLLLL#
#LLLLLLLLLLLL#
#LLLLLLLLLLLL#
##############
"""
CHARS = {"s": "stall1", "t": "stall2", "H": "dormhall", "1": "dorm1", "2": "dorm2", "3": "dorm3", "4": "dorm4", "5": "dorm5", "6": "dorm6",
         "R": "restroom", "K": "lockers", "F": "fitness", "L": "lounge"}

DQ = "/area/crew_quarters"
GREY, CARPET = "/turf/open/floor/plasteel", "/turf/open/floor/carpet"
ROOM_TABLE = {
    "dormhall": dict(area=DQ + "/dorms", floor=GREY, name="Dormitories", hall=True, label="HALL"),
    "lounge": dict(area=DQ + "/dorms", floor=GREY, name="Dormitory Lounge", newscaster=True, label="LOUNGE"),
    "restroom": dict(area=DQ + "/toilet", floor="/turf/open/floor/plasteel/freezer", name="Restrooms",
                     label="RESTROOM"),
    "lockers": dict(area=DQ + "/locker", floor=GREY, name="Locker Room", label="LOCKERS"),
    "stall1": dict(area=DQ + "/toilet", floor="/turf/open/floor/plasteel/freezer", name="Toilet", main=False,
                   camera=False, label="WC"),
    "stall2": dict(area=DQ + "/toilet", floor="/turf/open/floor/plasteel/freezer", name="Toilet", main=False,
                   camera=False, label="WC"),
    "fitness": dict(area=DQ + "/fitness", floor="/turf/open/floor/plasteel/dark", name="Fitness Room",
                    label="FITNESS"),
}
for _i in range(1, 7):
    ROOM_TABLE["dorm%d" % _i] = dict(area=DQ + "/dorms", floor=CARPET, name="Dorm %d" % _i, main=False,
                                     camera=False, plant=False, label="D%d" % _i)


def in_zone(a):
    return a.startswith(DQ + "/dorms")


PUB = dict(kind="public", glass=True)
LINKS = [
    door("lounge", "hall", wide=2, name="Dormitories", **PUB),
    glass("lounge", "hall", inset=2),
    door("dormhall", "maint", name="Dormitories Maintenance", kind="maintenance", access="12"),
    door("restroom", "dormhall", name="Restrooms", kind="public"),
    door("stall1", "restroom", name="Toilet", kind="public", vars={"id_tag": "stall1"}),
    door("stall2", "restroom", name="Toilet", kind="public", vars={"id_tag": "stall2"}),
    door("lockers", "dormhall", name="Locker Room", **PUB),
    door("fitness", "dormhall", name="Fitness Room", **PUB),
    door("fitness", "lockers", name="Fitness Room", **PUB),
    glass("fitness", "dormhall", inset=1),
    glass("fitness", "space", span=(0.25, 0.75)),
    glass("dorm5", "space", span=(0.34, 0.67)),
    glass("dorm6", "space", span=(0.34, 0.67)),
] + [door("dorm%d" % i, "dormhall", name="Dorm %d" % i, kind="public", vars={"id_tag": "Dorm%d" % i})
     for i in range(1, 7)]

_graph, _geo, _bp = drawing.department(NAME, BASE_MAP, DRAWING, CHARS, X0, Y0, ROOM_TABLE, LINKS, assets.ASSETS,
                                       in_zone)
globals().update(_bp)

if __name__ == "__main__":
    drawing.report(_graph, _geo, ROOT)
