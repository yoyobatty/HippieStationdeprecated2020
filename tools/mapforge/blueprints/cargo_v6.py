"""Cargo for the v6 station plan (plan/station_plan.py), drawn by hand tile by tile (forge/proc/drawing.py).

    python tools/mapforge/plan/canvas.py                    # the plan as a bare map, docking ports included
    python tools/mapforge/blueprints/cargo_v6.py            # run the graph, one picture per node
    python tools/mapforge/mapforge.py build blueprints/cargo_v6.py

The block sits west of Security across a maint seam: arm W and the arrivals lobby on its south, the supply shuttle's
dock on its west, open space north-west (the mining shuttle), maint north and east.

How it plays (Meta's cargo read with studies/dept_rooms.py: bay, office, QM, mining office, warehouse, sorting):
  - The crew come off arm W or out of arrivals into the cargo lobby and order over the office desk.
  - The office runs behind the desk and along the bay's south wall: supply and bounty consoles, the fabricators,
    the ore redemption machine. The warehouse is the bay's south-west corner.
  - The bay is the middle: the supply shuttle docks at its west airlock (supply_home, plan/canvas.py PORTS), MULEs
    park on the far wall, the QM looks down on it through glass from the north.
  - North of the bay: the QM's office, the sorting room (the way through to mining) and the mining office with its
    own dock airlock on the west hull (mining_home), and a maint door north.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge.proc import drawing  # noqa: E402
from forge.proc.shell import door, glass  # noqa: E402
from assets import cargo_v6 as assets  # noqa: E402

NAME = "cargo_v6"
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
BASE_MAP = os.path.join(ROOT, "data", "mapforge", "canvas_v6.dmm")
X0, Y0 = 30, 50                 # the drawing's top-left tile in plan coordinates
DRAWING = """\
      ############
      #MMMMMMMMMM#
      #MMMMMMMMMM#
      #MMMMMMMMMM#
      #MMMMMMMMMM#
      ############
      #SSSS#QQQQQ#
    ###SSSS#QQQQQ#
    #SSSSSS#QQQQQ#
    #SSSSSS#QQQQQ#
    #SSSSSS#QQQQQ#
##################
#BBBBBBBBBBBBBBBB#
#BBBBBBBBBBBBBBBB#
#BBBBBBBBBBBBBBBB#
#BBBBBBBBBBBBBBBB#
#BBBBBBBBBBBBBBBB#
#BBBBBBBBBBBBBBBB#
#BB######BBBBBBBB#
#BB#WWWW#BBBBBBBB#
#BB#WWWW##########
#BB#WWWW#OOOOOOOO#
#BB#WWWW#OOOOOOOO#
##############OOO#
        #LLLL#OOO#
        #LLLL#OOO#
        #LLLL#OOO#
        ##########
"""
CHARS = {"M": "mining", "S": "sorting", "Q": "qm", "B": "bay", "W": "warehouse", "O": "office", "L": "lobby"}

QM = "/area/quartermaster"
GREY, DARK = "/turf/open/floor/plasteel", "/turf/open/floor/plasteel/dark"
ROOM_TABLE = {
    "lobby": dict(area=QM + "/office", floor=GREY, name="Cargo Lobby", newscaster=True, label="LOBBY"),
    "office": dict(area=QM + "/office", floor=GREY, name="Cargo Office", label="OFFICE"),
    "bay": dict(area=QM + "/storage", floor=GREY, name="Cargo Bay", label="BAY"),
    "warehouse": dict(area=QM + "/warehouse", floor=GREY, name="Cargo Warehouse", label="WAREHOUSE"),
    "qm": dict(area=QM + "/qm", floor=DARK, name="Quartermaster's Office", label="QM"),
    "sorting": dict(area=QM + "/sorting", floor=GREY, name="Delivery Office", label="SORTING"),
    "mining": dict(area=QM + "/miningoffice", floor=GREY, name="Mining Office", label="MINING"),
}


def in_zone(a):
    return a.startswith(QM)


CARGO = dict(kind="mining")
LINKS = [
    # the public front: arm W and arrivals into the lobby, the office desk
    door("lobby", "hall", at=("x", 47), name="Cargo Lobby", glass=True, kind="mining"),
    door("lobby", "hall", at=("x", 44), name="Cargo Lobby", glass=True, kind="mining"),
    glass("lobby", "hall", inset=1),
    door("office", "lobby", type="desk", at=("x", 49), name="Cargo Desk", access="31", id="cargodesk"),
    door("office", "lobby", at=("y", 92), name="Cargo Office", access="31", **CARGO),
    # the office and the warehouse off the bay; the crate lane out to arrivals for MULEs and carts
    door("office", "bay", name="Cargo Office", access="31", glass=True, **CARGO),
    door("warehouse", "bay", name="Cargo Warehouse", access="31", **CARGO),
    door("bay", "hall", wide=2, at=("y", 92), name="Cargo Bay", one_access="31;48", glass=True, **CARGO),
    # the supply shuttle dock (Meta's): two walk airlocks where the shuttle's doors land, a belt in above them and a
    # belt out below, each through a blast door and flaps (supply_home at plan 29,65 in plan/canvas.py)
    door("bay", "space", at=("y", 102), name="Supply Dock Airlock", access="31", kind="external"),
    door("bay", "space", at=("y", 100), name="Supply Dock Airlock", access="31", kind="external"),
    door("bay", "space", at=("y", 103), type="flaps", flow="in", id="QMLoaddoor", belt="QMLoad",
         name="Supply Dock Loading Door"),
    door("bay", "space", at=("y", 99), type="flaps", flow="out", id="QMLoaddoor2", belt="QMLoad2",
         name="Supply Dock Loading Door"),
    # north of the bay: the QM over it, sorting through to mining (miners keep their way to the ORM and back)
    door("qm", "bay", name="Quartermaster", access="41", kind="command", glass=True),
    glass("qm", "bay", inset=1),
    # Meta's ORM is set into the wall: ore goes in from sorting (its north side), sheets come out into the bay
    door("sorting", "bay", at=("x", 42), type="orm"),
    door("sorting", "bay", name="Delivery Office", one_access="31;48;50", glass=True, **CARGO),
    door("mining", "sorting", name="Mining Office", one_access="48;31;41", glass=True, **CARGO),
    door("mining", "space", at=("y", 112), name="Mining Dock Airlock", access="48", kind="external"),
    # maint
    door("mining", "maint", name="Mining Maintenance", access="48", kind="maintenance"),
    door("bay", "maint", name="Cargo Bay Maintenance", access="31", kind="maintenance"),
]

_graph, _geo, _bp = drawing.department(NAME, BASE_MAP, DRAWING, CHARS, X0, Y0, ROOM_TABLE, LINKS, assets.ASSETS,
                                       in_zone)
globals().update(_bp)

if __name__ == "__main__":
    drawing.report(_graph, _geo, ROOT)
