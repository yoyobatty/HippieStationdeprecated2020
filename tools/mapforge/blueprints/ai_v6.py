"""The AI satellite for the v6 station plan (plan/station_plan.py), drawn by hand (forge/proc/drawing.py).

    python tools/mapforge/plan/canvas.py
    python tools/mapforge/blueprints/ai_v6.py
    python tools/mapforge/mapforge.py build blueprints/ai_v6.py

The satellite stands out in space east of the station at the end of the AI bridge, which reaches its west wall at
plan row 79. How it plays (Meta's satellite): the bridge leads into a turreted foyer, the foyer into the satellite
hall running north-south, the hall to the atmos and borg service rooms, two stores and, through a high-security
door, the core chamber in the east lobe where the AI sits behind its turrets.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge.proc import drawing  # noqa: E402
from forge.proc.shell import door, glass  # noqa: E402
from assets import ai_v6 as assets  # noqa: E402

NAME = "ai_v6"
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
BASE_MAP = os.path.join(ROOT, "data", "mapforge", "canvas_v6.dmm")
X0, Y0 = 166, 71
DRAWING = """\
#############
#AAAA#HH#PPP#
#AAAA#HH#PPP#
#AAAA#HH#########
#AAAA#HH#CCCCCCC#
######HH#CCCCCCC#
#FFFF#HH#CCCCCCC#
#FFFF#HH#CCCCCCC#
#FFFF#HH#CCCCCCC#
#FFFF#HH#CCCCCCC#
#FFFF#HH#CCCCCCC#
######HH#CCCCCCC#
#SSSS#HH#CCCCCCC#
#SSSS#HH#########
#SSSS#HH#WWW#
#SSSS#HH#WWW#
#SSSS#HH#WWW#
#############
"""
CHARS = {"F": "foyer", "A": "atmos", "S": "service", "H": "sathall", "C": "core", "P": "power", "W": "stores"}

AI = "/area/ai_monitored/turret_protected"
DARK, CIRC = "/turf/open/floor/plasteel/dark", "/turf/open/floor/circuit"
ROOM_TABLE = {
    "foyer": dict(area=AI + "/aisat/foyer", floor=DARK, name="AI Satellite Foyer", label="FOYER"),
    "sathall": dict(area=AI + "/aisat/hallway", floor=DARK, name="AI Satellite Hallway", hall=True, camera=False,
                    label="HALL"),
    "atmos": dict(area=AI + "/aisat/atmos", floor=DARK, name="AI Satellite Atmospherics", label="ATMOS"),
    "service": dict(area=AI + "/aisat/service", floor=DARK, name="AI Satellite Service", label="SERVICE"),
    "core": dict(area=AI + "/ai", floor=CIRC, name="AI Chamber", label="CORE"),
    "power": dict(area=AI + "/aisat_interior", floor=DARK, name="AI Satellite Storage", main=False, label="STORE"),
    "stores": dict(area=AI + "/aisat_interior", floor=DARK, name="AI Satellite Storage", label="STORE"),
}


def in_zone(a):
    return a.startswith(AI)


LINKS = [
    door("foyer", "hall", name="AI Satellite", access="65", kind="highsecurity"),
    door("sathall", "foyer", name="AI Satellite", access="65", kind="highsecurity"),
    door("atmos", "sathall", name="AI Satellite Atmospherics", access="65", kind="atmos"),
    door("service", "sathall", name="AI Satellite Service", access="65", kind="command"),
    door("power", "sathall", name="AI Satellite Storage", access="65", kind="command"),
    door("stores", "sathall", name="AI Satellite Storage", access="65", kind="command"),
    door("core", "sathall", at=("y", 90), name="AI Chamber", access="16", kind="highsecurity"),
    glass("core", "space", along=("x", 188), span=(0.385, 0.54)),     # 85-86; N and S panes cut by core3
]

_graph, _geo, _bp = drawing.department(NAME, BASE_MAP, DRAWING, CHARS, X0, Y0, ROOM_TABLE, LINKS, assets.ASSETS,
                                       in_zone, extra=dict(RWALL=True))
globals().update(_bp)

if __name__ == "__main__":
    drawing.report(_graph, _geo, ROOT)
