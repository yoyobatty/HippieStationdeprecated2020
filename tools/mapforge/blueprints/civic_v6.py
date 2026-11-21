"""Civic for the v6 station plan (plan/station_plan.py), drawn by hand tile by tile (forge/proc/drawing.py).

    python tools/mapforge/plan/canvas.py
    python tools/mapforge/blueprints/civic_v6.py
    python tools/mapforge/mapforge.py build blueprints/civic_v6.py

The block sits north of the north-east arterial and east of arm N, with a tower running north into space.

How it plays: the public come off the arterial into the foyer, which runs north to the chapel's doors. The chapel
fills the tower, the altar at its north end under the stars, the chaplain's office and the crematorium (maint
door for bodies) east of its foot, the confession booth west. The library is the big west room with its own door onto
arm N, the librarian's back room in its corner; the art gallery and the game room east of the foyer, the meeting room
and the lawyer's office (its own door onto the arterial) south of them.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge.proc import drawing  # noqa: E402
from forge.proc.shell import door, glass  # noqa: E402
from assets import civic_v6 as assets  # noqa: E402

NAME = "civic_v6"
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
BASE_MAP = os.path.join(ROOT, "data", "mapforge", "canvas_v6.dmm")
X0, Y0 = 91, 19
DRAWING = """\
        ############
        #HHHHHHHH#D#
        #HHHHHHHH###
        #HHHHHHHHHH#
        #HHHHHHHHHH#
        #HHHHHHHHHH#
        #HHHHHHHHHH#
        #HHHHHHHHHH#
        #HHHHHHHHHH#
    #####HHHHHHHHHH##########
    #XXX#HHHHHHHHHH#OOOO#KKK#
    #####HHHHHHHHHH#OOOO#KKK#
#####YYY#HHHHHHHHHH#OOOO#KKK#
#BBB#############################
#BBBBB#LLLLLL#FF#GGGGGGG#AAAAAAA#
#BBBBB#LLLLLL#FF#GGGGGGG#AAAAAAA#
#BBBBB#LLLLLL#FF#GGGGGGG#AAAAAAA#
#BBBBB#LLLLLL#FF#GGGGGGG#AAAAAAA#
#######LLLLLL#FF#GGGGGGG#AAAAAAA#
#LLLLLLLLLLLL#FF#GGGGGGG#AAAAAAA#
#LLLLLLLLLLLL#FF#################
#LLLLLLLLLLLL#FF#MMMMMMM#WWWWWWW#
#LLLLLLLLLLLL#FF#MMMMMMM#WWWWWWW#
#LLLLLLLLLLLL#FF#MMMMMMM#WWWWWWW#
#LLLLLLLLLLLL#FF#MMMMMMM#WWWWWWW#
#LLLLLLLLLLLL#FF#MMMMMMM#WWWWWWW#
#################################
"""
CHARS = {"D": "launch", "H": "chapel", "X": "confess1", "Y": "confess2", "O": "chapeloffice", "K": "crematorium", "L": "library", "B": "libback",
         "F": "foyer", "G": "gallery", "A": "gameroom", "M": "meeting", "W": "lawyer"}

GREY, DARK, WOODF = "/turf/open/floor/plasteel", "/turf/open/floor/plasteel/dark", "/turf/open/floor/wood"
CARPET = "/turf/open/floor/carpet"
ROOM_TABLE = {
    "chapel": dict(area="/area/chapel/main", floor=DARK, name="Chapel", label="CHAPEL"),
    "confess1": dict(area="/area/chapel/main", floor=DARK, name="Confessional", main=False, camera=False,
                     label="CONF"),
    "confess2": dict(area="/area/chapel/main", floor=DARK, name="Confessional", main=False, camera=False,
                     label="CONF"),
    "chapeloffice": dict(area="/area/chapel/office", floor=DARK, name="Chapel Office", label="OFFICE"),
    "launch": dict(area="/area/chapel/main", floor=DARK, name="Mass Driver", main=False, camera=False, dress=False,
                   plant=False, lights="small", label="DRV"),
    "crematorium": dict(area="/area/chapel/office", floor=DARK, name="Crematorium", main=False, label="CREM"),
    "library": dict(area="/area/library", floor=WOODF, name="Library", label="LIBRARY"),
    "libback": dict(area="/area/library", floor=WOODF, name="Library Back Room", main=False, label="BACK"),
    "foyer": dict(area="/area/library/lounge", floor=GREY, name="Civic Hall", hall=True, label="HALL"),
    "gallery": dict(area="/area/library/lounge", floor=WOODF, name="Art Gallery", label="GALLERY"),
    "gameroom": dict(area="/area/crew_quarters/lounge", floor=CARPET, name="Game Room", label="GAMES"),
    "meeting": dict(area="/area/library/lounge", floor=CARPET, name="Meeting Room", label="MEETING"),
    "lawyer": dict(area="/area/lawoffice", floor=WOODF, name="Law Office", label="LAWYER"),
}
AREAS = ("/area/chapel", "/area/library", "/area/lawoffice", "/area/crew_quarters/lounge")


def in_zone(a):
    return a.startswith(AREAS)


PUB = dict(kind="public", glass=True)
LINKS = [
    door("foyer", "hall", wide=2, name="Civic Hall", **PUB),
    door("chapel", "foyer", wide=2, name="Chapel", kind="public"),
    # the mass driver sends coffins out of the chapel's east wall (Meta's)
    door("launch", "space", at=("tile", (116, 145)), type="driver", id="chapelgun", name="Chapel Launcher Door"),
    door("launch", "chapel", at=("tile", (114, 145)), type="windoor", name="Mass Driver", access="22"),
    glass("chapel", "space", inset=1),
    door("confess1", "chapel", name="Confessional", kind="public"),
    door("confess2", "chapel", name="Confessional", kind="public"),
    door("chapeloffice", "chapel", name="Chapel Office", access="22", kind="public"),
    door("crematorium", "chapeloffice", name="Crematorium", access="27", kind="public"),
    door("crematorium", "maint", name="Chapel Maintenance", access="27", kind="maintenance"),
    door("library", "hall", wide=2, name="Library", **PUB),
    door("library", "foyer", name="Library", **PUB),
    glass("library", "hall", inset=1),
    door("libback", "library", name="Library Back Room", access="37", kind="public"),
    door("gallery", "foyer", name="Art Gallery", **PUB),
    glass("gallery", "foyer", inset=1),
    door("gameroom", "gallery", name="Game Room", **PUB),
    door("gameroom", "maint", name="Game Room Maintenance", access="12", kind="maintenance"),
    door("meeting", "foyer", name="Meeting Room", **PUB),
    door("lawyer", "hall", name="Law Office", access="38", kind="public", glass=True),
    glass("lawyer", "hall", inset=1),
]

_graph, _geo, _bp = drawing.department(NAME, BASE_MAP, DRAWING, CHARS, X0, Y0, ROOM_TABLE, LINKS, assets.ASSETS,
                                       in_zone)
globals().update(_bp)

if __name__ == "__main__":
    drawing.report(_graph, _geo, ROOT)
