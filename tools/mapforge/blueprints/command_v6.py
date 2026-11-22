"""Command for the v6 station plan (plan/station_plan.py), drawn by hand tile by tile (forge/proc/drawing.py).

    python tools/mapforge/plan/canvas.py
    python tools/mapforge/blueprints/command_v6.py
    python tools/mapforge/mapforge.py build blueprints/command_v6.py

Two pieces. The core sits inside the hall ring, the station's centre. The north wing sits between the north-west
arterial and arm N.

How it plays (Meta's bridge and command wing):
  - The bridge fills the core's north half, its doors on ring N and glass onto it: the consoles in a row on the far
    wall, the captain's chair in the middle. The vault (self-destruct, the ore silo every ORM draws on, the gold)
    and the AI upload (turreted) flank it, each opening off the bridge.
  - South of the bridge: the HoP serves the queue on ring W over a desk windoor, the conference room, the captain's
    office (off the bridge) and his quarters behind it.
  - The north wing: EVA's suits and jetpacks on the arterial, the teleporter and tech storage on arm N.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge.proc import drawing  # noqa: E402
from forge.proc.shell import door, glass  # noqa: E402
from assets import command_v6 as assets  # noqa: E402

NAME = "command_v6"
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
BASE_MAP = os.path.join(ROOT, "data", "mapforge", "canvas_v6.dmm")
X0, Y0 = 70, 34
DRAWING = """\
##################
#EEEEEEE#TTTTTTTT#
#EEEEEEE#TTTTTTTT#
#EEEEEEE#TTTTTTTT#
#EEEEEEE#TTTTTTTT#
#EEEEEEE##########
#EEEEEEEE#SSSS#ZZ#
#EEEEEEEE#SSSS#ZZ#
#EEEEEEEE#SSSS#ZZ#
#EEEEEEEE#SSSS#ZZ#
#EEEEEEEE#SSSS#ZZ#
##################

























          ####################
          #VVV#BBBBBBBBBB#UUU#
          #VVV#BBBBBBBBBB#UUU#
          #VVV#BBBBBBBBBB#UUU#
          #VVV#BBBBBBBBBB#UUU#
          #VVV#BBBBBBBBBB#UUU#
          #VVV#BBBBBBBBBB#UUU#
          #VVV#BBBBBBBBBB#UUU#
          #VVV#BBBBBBBBBB#UUU#
          ####################
          #HHHHH#CCCC#OOOOOOO#
          #HHHHH#CCCC#OOOOOOO#
          #HHHHH#CCCC#OOOOOOO#
          #HHHHH#CCCC#########
          #HHHHH#CCCC#QQQQ#bb#
          #HHHHH#CCCC#QQQQ#bb#
          #HHHHH#CCCC#QQQQ#bb#
          ####################
"""
CHARS = {"b": "bath", "Z": "securetech", "E": "eva", "T": "teleporter", "S": "techstorage", "V": "vault", "B": "bridge", "U": "upload", "H": "hop",
         "C": "conference", "O": "captain", "Q": "quarters"}

GREY, DARK, BLUE = "/turf/open/floor/plasteel", "/turf/open/floor/plasteel/dark", "/turf/open/floor/plasteel"
WOODF, CARPET = "/turf/open/floor/wood", "/turf/open/floor/carpet"
ROOM_TABLE = {
    "bridge": dict(area="/area/bridge", floor=DARK, name="Bridge", label="BRIDGE"),
    "vault": dict(area="/area/ai_monitored/nuke_storage", floor="/turf/open/floor/circuit", name="Vault", camera="Vault",
                  label="VAULT"),
    "upload": dict(area="/area/ai_monitored/turret_protected/ai_upload", floor="/turf/open/floor/circuit/green",
                   name="AI Upload Chamber", label="UPLOAD"),
    "hop": dict(area="/area/crew_quarters/heads/hop", floor=GREY, name="Head of Personnel's Office", label="HOP"),
    "conference": dict(area="/area/bridge/meeting_room", floor=WOODF, name="Conference Room", label="CONF"),
    "captain": dict(area="/area/crew_quarters/heads/captain", floor=WOODF, name="Captain's Office", label="CAPTAIN"),
    "quarters": dict(area="/area/crew_quarters/heads/captain/private", floor=CARPET, name="Captain's Quarters",
                     camera=False, label="QUARTERS"),
    "eva": dict(area="/area/ai_monitored/storage/eva", floor=DARK, name="EVA Storage", label="EVA"),
    "teleporter": dict(area="/area/teleporter", floor=DARK, name="Teleporter Room", label="TELEPORT"),
    "bath": dict(area="/area/crew_quarters/heads/captain/private", floor="/turf/open/floor/plasteel/freezer",
                 name="Captain's Bathroom", main=False, camera=False, label="BATH"),
    "securetech": dict(area="/area/storage/tech", floor=DARK, name="Secure Tech Storage", main=False, label="SECTECH"),
    "techstorage": dict(area="/area/storage/tech", floor=DARK, name="Tech Storage", label="TECH"),
}


def in_zone(a):
    return a.startswith("/area/bridge")


CMD = dict(kind="command")
LINKS = [
    # the core: the bridge doors on ring N, glass onto it; vault and upload off the bridge
    door("bridge", "hall", wide=2, name="Bridge", access="19", glass=True, **CMD),
    glass("bridge", "hall", inset=1),
    door("vault", "bridge", name="Vault", access="53", kind="vault"),
    door("upload", "bridge", name="AI Upload", access="16", kind="highsecurity"),
    # south of the bridge
    door("hop", "hall", type="brigdesk", name="Head of Personnel's Desk", access="57", id="hopqueue"),
    door("hop", "bridge", name="Head of Personnel", access="57", **CMD),
    glass("hop", "hall", runs="door", inset=2, shutter="hopqueue"),
    door("conference", "bridge", name="Conference Room", access="19", glass=True, **CMD),
    door("captain", "bridge", name="Captain's Office", access="20", **CMD),
    door("quarters", "captain", name="Captain's Quarters", access="20", **CMD),
    door("bath", "quarters", name="Captain's Bathroom", access="20", kind="public"),
    # the north wing
    door("eva", "hall", wide=2, name="EVA Storage", access="18", **CMD),
    door("eva", "maint", at=("x", 80), name="EVA Maintenance", access="18", kind="maintenance"),
    door("teleporter", "hall", name="Teleporter", access="17", **CMD),
    door("techstorage", "hall", name="Tech Storage", access="23", kind="engineering"),
    door("securetech", "techstorage", name="Secure Tech Storage", access="19", kind="highsecurity"),
]

_graph, _geo, _bp = drawing.department(NAME, BASE_MAP, DRAWING, CHARS, X0, Y0, ROOM_TABLE, LINKS, assets.ASSETS,
                                       in_zone)
globals().update(_bp)

if __name__ == "__main__":
    drawing.report(_graph, _geo, ROOT)
