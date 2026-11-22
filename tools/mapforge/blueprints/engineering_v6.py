"""Engineering for the v6 station plan (plan/station_plan.py), drawn by hand tile by tile (forge/proc/drawing.py).

    python tools/mapforge/plan/canvas.py                    # lays the engine's cooling coil out in space too
    python tools/mapforge/blueprints/engineering_v6.py
    python tools/mapforge/mapforge.py build blueprints/engineering_v6.py

Two pieces. The main block lies south of arm E with its east side on the hull. Atmos sits south of the SE arterial,
west on arm S.

How it plays (Meta's engineering and atmos):
  - The public come off arm E into the break room; the checkpoint watches it through glass, the SMES room
    beside it.
  - The engineers' corridor runs south from the break room. West of it are the CE's office, the workshop and
    secure storage. East of it are the gravity generator, engine control and the lockers.
  - At its foot, the door into the engine room: Meta's supermatter block, turned so its hull wall is the
    station's east hull and its coil lies in space beyond.
  - Atmos: the front desk serves arm S and the arterial over a windoor, the main floor holds the canisters, pumps
    and scrubbers, the four gas chambers stand along its south side.
The station's pipes, cable and disposals join in the station-wide pass, as for every v6 department.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge.proc import drawing  # noqa: E402
from forge.proc.shell import door, glass  # noqa: E402
from assets import engineering_v6 as assets  # noqa: E402

NAME = "engineering_v6"
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
BASE_MAP = os.path.join(ROOT, "data", "mapforge", "canvas_v6.dmm")
X0, Y0 = 91, 81
DRAWING = """\
                 ###############################
                 #LLLLLLLLLL#KKKKK#PPPPPPPPPPPP#
            ######LLLLLLLLLL#KKKKK#PPPPPPPPPPPP#
            #LLLLLLLLLLLLLLL#KKKKK#PPPPPPPPPPPP#
            #LLLLLLLLLLLLLLL#KKKKK#PPPPPPPPPPPP#
            ########################PPPPPPPPPPP###
            #OOOOOOO#HH#gggg#GGGGGG#PPPPPPPPPPP###
            #OOOOOOO#HH#gggg#GGGGGG###############
            #OOOOOOO#HH#gggg#GGGGGG###############
            #OOOOOOO#HH######GGGGGG###############
            #OOOOOOO#HH#eeee#GGGGGG###############
            #OOOOOOO#HH#eeee######################
            #########HH#eeeeeeeeeeee##############
            #WWWWWWW#HH#eeeeeeeeeeee##############
            #WWWWWWW#HH###########################
            #WWWWWWW#HH#CCCCCCCC##################
            #WWWWWWW#HH#CCCCCCCC##################
            #WWWWWWW#HH#CCCCCCCC##################
            #WWWWWWW#HH#CCCCCCCC##################
            #WWWWWWW#HH#CCCCCCCC##################
            #########HH###########################
            #SSSSSSS#HH#FFFFFFFFFFF###############
            #SSSSSSS#HH#FFFFFFFFFFF###############
            #SSSSSSS#HH#FFFFFFFFFFF###############
            #SSSSSSS#HH###########################
            #SSSSSSS#HH#XXXXXXXXXXXXXXXXXXXXXXXXX#
            #SSSSSSS#HH#XXXXXXXXXXXXXXXXXXXXXXXXX#
            #SSSSSSS#HH#XXXXXXXXXXXXXXXXXXXXXXXXX#
            #SSSSSSS#HH#XXXXXXXXXXXXXXXXXXXXXXXXX#
            ######################################


######################
#AAAAA#MMMMMMMMMM#kkk#
#AAAAA#MMMMMMMMMM#kkk#
#AAAAA#MMMMMMMMMM#kkk#
#AAAAA#MMMMMMMMMM#kkk#
#AAAAA#MMMMMMMMMM#####
#######MMMMMMMMMMMMMM#
#MMMMM#MMMMMMMMMMMMMM#
#MMMMM#MMMMMMMMMMMMMM#
#MMMMM#MMMMMMMMMMMMMM#
#MMMMM#MMMMMMMMMMMMMM#
#MMMMM#MMMMMMMMMMMMMM#
######################
#ZZZZZZZZZZZZZZZZZZZZ#
#ZZZZZZZZZZZZZZZZZZZZ#
#ZZZZZZZZZZZZZZZZZZZZ#
#ZZZZZZZZZZZZZZZZZZZZ#
######################
#QQQ#BBB#NNN#222#DDDD#
#QQQ#BBB#NNN#222#DDDD#
#QQQ#BBB#NNN#222#DDDD#
#QQQ#BBB#NNN#222#DDDD#
######################
"""
CHARS = {"L": "break", "K": "checkpoint", "P": "smes", "H": "enghall", "O": "ce", "W": "workshop", "S": "storage",
         "G": "gravgen", "g": "gravante", "C": "control", "F": "lockers", "X": "engine", "A": "atmosdesk", "Y": "atmoslockers",
         "M": "atmos", "N": "n2", "2": "o2", "D": "airmix", "Q": "plasma",
         "Z": "gasstore", "B": "co2", "e": "shared", "k": "atmaint"}

ENG, ATM = "/area/engine/engineering", "/area/engine/atmos"
GREY, DARK, ENGF = "/turf/open/floor/plasteel", "/turf/open/floor/plasteel/dark", "/turf/open/floor/engine"
ROOM_TABLE = {
    "break": dict(area="/area/engine/break_room", floor=GREY, name="Engineering Foyer", newscaster=True, label="BREAK"),
    "checkpoint": dict(area="/area/security/checkpoint/engineering", floor=DARK, name="Security Post - Engineering",
                       label="POST"),
    "smes": dict(area="/area/engine/engine_smes", floor=DARK, name="Engineering SMES", label="SMES"),
    "enghall": dict(area=ENG, floor=GREY, name="Engineering", hall=True, label="HALL"),
    "ce": dict(area="/area/crew_quarters/heads/chief", floor=GREY, name="Chief Engineer's Office", label="CE"),
    "workshop": dict(area=ENG, floor=GREY, name="Engineering Workshop", label="WORKSHOP"),
    "storage": dict(area="/area/engine/storage", floor=DARK, name="Engineering Secure Storage", label="STORAGE"),
    # the stock pattern (size_budget 2026-11-22: v6's was 79 tiles, stock 35-60): the generator in its own chamber,
    # an antechamber off the corridor with the rad gear, 50 tiles in all
    "gravgen": dict(area="/area/engine/gravity_generator", floor=DARK, name="Gravity Generator", label="GRAV"),
    "gravante": dict(area="/area/engine/gravity_generator", floor=GREY, name="Gravity Generator Foyer", main=False,
                     label="FOYER"),
    "control": dict(area=ENG, floor=DARK, name="Engine Control", label="CONTROL"),
    # the stock shared storage (Meta 17 tiles, Delta 41) where the old gravity chamber's rows were left solid wall
    # (the user 2026-11-22: no wall filler; the gate: 12 tiles of 3x3 solid wall)
    # a maint room off the port run in the main floor's far corner (the gate 2026-11-22: atmos fill 0.80 against the
    # accepted 0.77 and the stock 0.43-0.59, the redraw had made the block one rectangle); polish dresses it as maint
    "atmaint": dict(area="/area/maintenance/port", floor="/turf/open/floor/plating", name="Atmospherics Maintenance",
                    label="MAINT"),
    "shared": dict(area="/area/engine/storage_shared", floor=GREY, name="Shared Engineering Storage", label="SHARED"),
    "lockers": dict(area=ENG, floor=GREY, name="Engineering Lockers", label="LOCKERS"),
    "engine": dict(area=ENG, floor=ENGF, name="Engine Room", label="ENGINE"),
    "smcore": dict(area="/area/engine/supermatter", floor=ENGF, name="Supermatter Chamber", apc=False, bare=True,
                   dress=False, module=True, camera=False, label=""),
    "atmosdesk": dict(area=ATM, floor=GREY, name="Atmospherics Front Desk", label="DESK"),
    "atmoslockers": dict(area=ATM, floor=GREY, name="Atmospherics Lockers", label="LOCKERS"),
    "atmos": dict(area=ATM, floor=GREY, name="Atmospherics", label="ATMOS"),
    "n2": dict(area=ATM, floor="/turf/open/floor/engine/n2", name="Nitrogen Chamber", main=False, bare=True,
               dress=False, vents=0, camera=False, module=True, label="N2"),
    "o2": dict(area=ATM, floor="/turf/open/floor/engine/o2", name="Oxygen Chamber", main=False, bare=True,
               dress=False, vents=0, camera=False, module=True, label="O2"),
    "airmix": dict(area=ATM, floor="/turf/open/floor/engine/air", name="Air Mix Chamber", main=False, bare=True,
                dress=False, vents=0, camera=False, module=True, label="CO2"),
    "plasma": dict(area=ATM, floor="/turf/open/floor/engine/plasma", name="Plasma Chamber", main=False, bare=True,
                   dress=False, vents=0, camera=False, module=True, label="PL"),
    # the stock pattern (2026-11-22): canisters and the tank consoles in their own room between the main floor and
    # the chambers, the waste filter bank along it (v6_station.chambers); a CO2 tank as every stock atmos has
    "gasstore": dict(area=ATM, floor=GREY, name="Atmospherics Gas Storage", main=False, label="GAS"),
    "co2": dict(area=ATM, floor="/turf/open/floor/engine/co2", name="Carbon Dioxide Chamber", main=False, bare=True,
                dress=False, vents=0, camera=False, module=True, label="CO2"),
}


def in_zone(a):
    return a.startswith("/area/engine")


ENGK = dict(kind="engineering")
LINKS = [
    # the front on arm E
    door("break", "hall", wide=2, name="Engineering Foyer", glass=True, kind="engineering"),
    glass("break", "hall", inset=1),
    door("checkpoint", "break", name="Security Post - Engineering", access="63", kind="security", glass=True),
    glass("checkpoint", "break", inset=0),
    door("smes", "hall", name="Engineering SMES", access="10", **ENGK),
    door("enghall", "break", wide=2, name="Engineering", access="10", glass=True, **ENGK),
    # off the engineers' corridor
    door("ce", "enghall", name="Chief Engineer's Office", access="56", kind="command", glass=True),
    glass("ce", "enghall", inset=1, shutter="ceprivacy"),
    door("workshop", "enghall", name="Engineering Workshop", access="10", **ENGK),
    door("storage", "enghall", name="Engineering Secure Storage", access="11", **ENGK),
    door("gravante", "enghall", name="Gravity Generator", access="19", kind="command"),
    door("gravgen", "gravante", name="Gravity Generator Chamber", access="19", kind="command"),
    # the foyer one row short (its last row and the wall under it go to Engine Control, which also took the solid
    # wall left under the old chamber) and a window from the foyer, as the stock chambers have (the gate 2026-11-22:
    # fill 0.91 against the stock 0.63-0.77, glass 0.00 against 0.09-0.22, 12 tiles of 3x3 solid wall)
    glass("gravgen", "gravante"),
    door("control", "enghall", name="Engine Control", access="10", glass=True, **ENGK),
    door("shared", "enghall", name="Shared Engineering Storage", access="10", **ENGK),
    # a window from the hall (engineering's glass 0.14 with the shared room's walls, accepted 0.15, stock 0.18-0.41)
    glass("shared", "enghall"),
    door("atmaint", "maint", name="Maintenance", access="12", kind="maintenance"),
    door("lockers", "enghall", name="Engineering Lockers", access="10", **ENGK),
    door("engine", "enghall", wide=2, name="Engine Room", access="10", **ENGK),
    door("enghall", "hall", name="Engineering", access="10", glass=True, **ENGK),
    # atmos
    door("atmosdesk", "hall", type="brigdesk", name="Atmospherics Desk", access="24", id="atmosdesk"),
    door("atmosdesk", "hall", name="Atmospherics", access="24", kind="atmos", glass=True),
    door("atmos", "atmosdesk", name="Atmospherics", access="24", kind="atmos"),
    door("atmos", "maint", name="Atmospherics Maintenance", access="24", kind="maintenance"),
    door("gasstore", "atmos", wide=2, name="Atmospherics Gas Storage", access="24", kind="atmos", glass=True),
    glass("gasstore", "atmos", inset=2),
] + [glass(g, "gasstore") for g in ("n2", "o2", "airmix", "plasma", "co2")]


def stamps():
    a = assets.ENGINE_ANCHOR
    return [("engine block", lambda geo: a, "engine", assets.engine_prefab(False)),
            ("supermatter", lambda geo: a, "smcore", assets.engine_prefab(True))]


_graph, _geo, _bp = drawing.department(NAME, BASE_MAP, DRAWING, CHARS, X0, Y0, ROOM_TABLE, LINKS, assets.ASSETS,
                                       in_zone, stamps=stamps())
globals().update(_bp)
# Meta's chamber air alarm sits on a supermatter-area tile in front of the chamber wall, so the alarm reads the chamber
OPEN_SEAMS = [(ENG, "/area/engine/supermatter")]

if __name__ == "__main__":
    drawing.report(_graph, _geo, ROOT)
