"""Security for the v6 station plan (plan/station_plan.py), drawn by hand tile by tile.

    python tools/mapforge/plan/canvas.py                       # the plan as a bare map (once, or after plan edits)
    python tools/mapforge/blueprints/security_v6.py            # run the graph, one picture per node
    python tools/mapforge/mapforge.py build blueprints/security_v6.py

The block is the NW wedge against the hall ring: the north-west arterial along its north side, arm N and plaza N on
its east, the ring's north-west corner (command beyond it) on its south-east, arm W along its south, maint on the
west. Pass 2 (2026-11-21) grew it over the maint rooms and vending nook to its west and redrew it by hand.

How it plays (studies/mapping_practice.md stage 5, Meta's brig read with studies/dept_rooms.py):
  - The public enter from the ring, facing command: the brig lobby, the front desk serving it over a desk, the
    holding cell behind the desk. The lobby's inner airlock (the desk cycles it) leads into the brig hall.
  - The brig hall runs east-west behind the holding cell and three cells. The cells look out onto arm W through
    shuttered windows (the warden's "Cell Shutters" button) and each has its timer on the hall wall by its door.
  - Off the hall's north side: the prison wing door, interrogation (the warden watches it through his glass), the
    warden behind his desk window, the officers' hall. The armory is behind the warden, evidence and the brig
    infirmary up the column behind that.
  - The officers' hall runs north to the arterial, the staff entrance: gear and briefing off it, the HoS in the
    north-east corner and the detective (his own door onto arm N) off briefing.
  - The courtroom faces command across the ring: the gallery has doors onto the ring and plaza N, a railing of
    glass with a gate between it and the bench, the court cell behind the bench off the officers' hall.
  - The perma wing is the west side on maint, away from every public hall: the prison hall runs north from the brig
    hall past the execution room, the sanitarium and three long-term cells whose shutters open onto the common room
    and the garden.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge.proc import geo as G  # noqa: E402
from forge.proc import shell, furnish, emit  # noqa: E402
from assets import security_v6 as assets  # noqa: E402
from forge.proc.shell import door, glass  # noqa: E402

NAME = "security_v6"
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
BASE_MAP = os.path.join(ROOT, "data", "mapforge", "canvas_v6.dmm")
BBOX = (54, 86, 95, 119)

# The block as drawn, in plan coordinates (x 50-87 left to right, plan rows 48-77 top to bottom; the map's x is the
# plan's + 6, its y is 165 minus the plan row). "#" is wall (the outline ring or a wall between rooms), a space is
# outside the block, every other character is a room (CHARS).
DRAWING = """\
        ##############################
        #YYYY#FFFFF#SS#GGGGGG#QQQQQQQ#
#########YYYY#FFFFF#SS#GGGGGG#QQQQQQQ#
#PP#444#YYYYY#FFFFF#SS#GGGGGG#QQQQQQQ#
#PP#444#YYYYY#######SS#GGGGGG#QQQQQQQ#
#PP###########EEEEE#SS#GGGGGG#QQQQQQQ#
#PP#555#MMMMM#EEEEE#SS################
#PP#555#MMMMM#EEEEE#SS#RRRRRRRR#KKKKK#
#PP#####MMMMM#######SS#RRRRRRRR#KKKKK#
#PP#666#MMMMM#AAAAA#SS#RRRRRRRR#KKKKK#
#PP#666#MMMMM#AAAAA#SS#RRRRRRRR#KKKKK#
#PP#####MMMMM#AAAAA#SS#RRRRRRRR#KKKKK#
#PP#NNN#MMMMM#AAAAA#SS##########KKKKK#
#PP#NNN#MMMMM#AAAAA#SS#CCCCCC#V####KK#
#PP#################SS#CCCCCC#VVVV####
#PP#XXXX#IIII#WWWWW#SS#CCCCCC#VVVV#
#PP#XXXX#IIII#WWWWW#SS#CCCCCC#VVVV#
#PP######IIII#WWWWW#SS####CCC#VVVV#
####xxxx#IIII#WWWWW#SS#ZZ#CCC#VVVV#
#ee#xxxx#IIII#WWWWW#SS#ZZ##########
###########################
#BBBBBBBBBBBBBBBBBBBB#LLLL#
#BBBBBBBBBBBBBBBBBBBB#LLLL#
#BBBBBBBBBBBBBBBBBBBB#LLLL#
######################LLLL#
#111#222#333#HHH#DDDD#LLLL#
#111#222#333#HHH#DDDD#LLLL#
#111#222#333#HHH#DDDD######
#111#222#333#HHH#DDDD#
######################
"""
CHARS = {"L": "lobby", "D": "frontdesk", "H": "holding", "B": "brighall", "1": "cell1", "2": "cell2", "3": "cell3",
         "W": "warden", "A": "armory", "E": "evidence", "F": "infirm", "I": "interro", "S": "sechall", "G": "gear",
         "Q": "hos", "R": "briefing", "K": "detective", "C": "court", "V": "gallery", "Z": "courtcell",
         "P": "prisonhall", "4": "lt1", "5": "lt2", "6": "lt3", "N": "sanit", "M": "permacommon", "Y": "garden",
         "X": "exec", "x": "justice", "e": "permaentry"}
PLAN_X0, PLAN_Y0 = 50, 48


def in_zone(a):
    return a.startswith("/area/security")


PARAMS = dict(seed=1)

BRIG, MAIN, PRISON = "/area/security/brig", "/area/security/main", "/area/security/prison"
COURT, EXEC = "/area/security/courtroom", "/area/security/execution/education"
GREY, DARK, WHITE = "/turf/open/floor/plasteel", "/turf/open/floor/plasteel/dark", "/turf/open/floor/plasteel/white"
WOODF = "/turf/open/floor/wood"
ROOM_TABLE = {
    "lobby": dict(area=BRIG, floor=GREY, name="Brig Lobby", newscaster=True, label="LOBBY"),
    "frontdesk": dict(area=BRIG, floor=DARK, name="Brig Front Desk", label="DESK"),
    "holding": dict(area=BRIG, floor=GREY, name="Holding Cell", main=False, camera=False, label="HOLD"),
    "brighall": dict(area=BRIG, floor=GREY, name="Brig", hall=True, label="BRIG"),
    "cell1": dict(area=BRIG, floor=GREY, name="Cell 1", main=False, camera=False, label="C1"),
    "cell2": dict(area=BRIG, floor=GREY, name="Cell 2", main=False, camera=False, label="C2"),
    "cell3": dict(area=BRIG, floor=GREY, name="Cell 3", main=False, camera=False, label="C3"),
    "infirm": dict(area=BRIG, floor=WHITE, name="Brig Infirmary", label="INFIRM"),
    "warden": dict(area="/area/security/warden", floor=DARK, name="Brig Control", label="WARDEN"),
    "armory": dict(area="/area/ai_monitored/security/armory", floor=DARK, name="Armory", label="ARMORY"),
    "evidence": dict(area="/area/security/warden", floor=DARK, name="Evidence Storage", label="EVIDENCE"),
    "interro": dict(area=MAIN, floor=DARK, name="Interrogation", label="INTERRO"),
    "sechall": dict(area=MAIN, floor=GREY, name="Security Hall", hall=True, label="HALL"),
    "gear": dict(area=MAIN, floor=GREY, name="Gear Room", label="GEAR"),
    "briefing": dict(area=MAIN, floor=GREY, name="Security Office", label="BRIEFING"),
    "hos": dict(area="/area/crew_quarters/heads/hos", floor=DARK, name="Head of Security's Office", label="HOS"),
    "detective": dict(area="/area/security/detectives_office", floor="/turf/open/floor/plasteel/grimy",
                      name="Detective's Office", label="DETECTIVE"),
    "court": dict(area=COURT, floor=WOODF, name="Courtroom", label="COURT"),
    "gallery": dict(area=COURT, floor=GREY, name="Courtroom Gallery", main=False, label="GALLERY"),
    "courtcell": dict(area=COURT, floor=DARK, name="Court Cell", main=False, camera=False, label="CC"),
    "prisonhall": dict(area=PRISON, floor=GREY, name="Prison Wing", hall=True, label="PRISON"),
    "permaentry": dict(area=PRISON, floor="/turf/open/floor/plasteel/dark", name="Prison Wing Entry", main=False,
                       label="IN"),
    "lt1": dict(area=PRISON, floor=GREY, name="Long-Term Cell 1", main=False, label="LT1"),
    "lt2": dict(area=PRISON, floor=GREY, name="Long-Term Cell 2", main=False, label="LT2"),
    "lt3": dict(area=PRISON, floor=GREY, name="Long-Term Cell 3", main=False, label="LT3"),
    "sanit": dict(area=PRISON, floor=WHITE, name="Prison Sanitarium", main=False, label="SAN"),
    "permacommon": dict(area=PRISON, floor=GREY, name="Prison Common Room", label="COMMON"),
    "garden": dict(area=PRISON, floor=GREY, name="Prison Garden", main=False, label="GARDEN"),
    "exec": dict(area=EXEC, floor=DARK, name="Prisoner Education Chamber", label="EXEC"),
    "justice": dict(area=EXEC, floor=DARK, name="Justice Chamber", main=False, camera=False, label="CHAMBER"),
}


def to_map(px, py):
    return px + 6, 165 - py


def plans(P):
    """The drawing as one-tile plan rects: the slicer lays each room tile where it is drawn, and every block tile
    left undrawn ("#") becomes wall."""
    out = []
    for row, line in enumerate(DRAWING.splitlines()):
        for col, ch in enumerate(line):
            if ch in CHARS:
                x, y = to_map(PLAN_X0 + col, PLAN_Y0 + row)
                out.append(((x, y, x, y), CHARS[ch]))
    return out


def check_drawing(geo, P):
    """The drawing against the outline: a drawn room tile on the ring or outside the block is a misplaced line."""
    drawn = {r[0][:2] for r in plans(P)}
    for p in sorted(drawn):
        if p not in geo.zone or geo.kind.get(p) != "free":
            geo.problem("drawing: room tile %d,%d is on the outline ring or outside the block" % p)
    geo.notes.append("drawing: %d room tiles, %d free tiles left as wall" % (
        len(drawn), sum(1 for q in geo.zone if geo.kind.get(q) == "free" and q not in drawn)))


SEC = dict(kind="security")
LINKS = [
    # the public front on the ring: the lobby, the desk, the inner airlock; windows onto plaza W
    door("lobby", "hall", wide=2, at=("y", 93.5), name="Brig", glass=True, vars={"id_tag": "outerbrig"}, **SEC),
    glass("lobby", "hall", inset=1),
    door("frontdesk", "lobby", type="brigdesk", name="Brig Front Desk", access="63", id="briggate"),
    door("lobby", "brighall", name="Brig", access="63", glass=True, vars={"id_tag": "innerbrig"}, **SEC),
    door("frontdesk", "brighall", name="Brig Front Desk", access="63", **SEC),
    # the holding cell behind the desk: the desk officer lets people in and out, its timed door onto the hall
    door("holding", "frontdesk", name="Holding Cell", access="63", glass=True, **SEC),
    door("holding", "brighall", type="cell", name="Holding Cell", id="Holding Cell"),
    # the cells: secure windoors their timers work, shuttered windows onto arm W
    door("cell1", "brighall", type="cell", name="Cell 1", id="Cell 1"),
    door("cell2", "brighall", type="cell", name="Cell 2", id="Cell 2"),
    door("cell3", "brighall", type="cell", name="Cell 3", id="Cell 3"),
    glass("cell1", "hall", shutter="Secure Gate"), glass("cell2", "hall", shutter="Secure Gate"),
    glass("cell3", "hall", shutter="Secure Gate"), glass("holding", "hall", shutter="Secure Gate"),
    # the warden over the hall: desk window, the armory behind, interrogation through his glass
    door("warden", "brighall", type="brigdesk", name="Brig Control", access="3", id="wardenshutter"),
    glass("warden", "brighall", runs="door"),
    door("warden", "sechall", name="Brig Control", access="3", glass=True, **SEC),
    door("armory", "warden", name="Armory", access="3", **SEC),
    door("interro", "brighall", name="Interrogation", access="63", **SEC),
    glass("interro", "warden", inset=1),
    # the officers' hall: the staff entrance on the arterial, the brig at its foot
    door("sechall", "hall", wide=2, name="Security", access="63", glass=True, firedoor=True, **SEC),
    door("sechall", "brighall", name="Brig", access="63", glass=True, **SEC),
    door("evidence", "sechall", name="Evidence Storage", one_access="1;4", **SEC),
    door("infirm", "sechall", name="Brig Infirmary", access="63", glass=True, **SEC),
    glass("infirm", "hall", inset=1),
    door("gear", "sechall", name="Gear Room", one_access="1;4", glass=True, **SEC),
    door("briefing", "sechall", name="Security Office", one_access="1;4", glass=True, **SEC),
    glass("briefing", "sechall", inset=1),
    door("gear", "briefing", name="Gear Room", one_access="1;4", glass=True, **SEC),
    door("hos", "briefing", name="Head of Security's Office", access="58", kind="command", glass=True),
    glass("hos", "hall", inset=1),
    door("detective", "briefing", name="Detective's Office", access="4", **SEC),
    door("detective", "hall", name="Detective's Office", access="4", **SEC),
    glass("detective", "hall", inset=1),
    # the courtroom: the public into the gallery from the ring and plaza N, the railing and its gate, the bench's
    # staff door and the court cell off the officers' hall
    door("gallery", "hall", at=("y", 98), name="Courtroom", glass=True, kind="public"),
    door("gallery", "hall", at=("x", 90), name="Courtroom", glass=True, kind="public"),
    door("court", "gallery", type="windoor", name="Courtroom Gate"),
    glass("gallery", "court"),
    door("court", "sechall", name="Courtroom", one_access="42;63", **SEC),
    door("courtcell", "sechall", name="Court Cell", access="63", **SEC),
    door("courtcell", "court", type="windoor", name="Court Cell", access="63"),
    glass("court", "hall", inset=1),
    # the perma wing
    # the perma sally port: two airlock pairs with the entry tiles between
    door("permaentry", "brighall", wide=2, name="Prison Wing", access="2", glass=True, **SEC),
    door("prisonhall", "permaentry", wide=2, name="Prison Wing", access="2", glass=True, **SEC),
    door("lt1", "prisonhall", name="Long-Term Cell 1", access="2", glass=True, **SEC),
    door("lt2", "prisonhall", name="Long-Term Cell 2", access="2", glass=True, **SEC),
    door("lt3", "prisonhall", name="Long-Term Cell 3", access="2", glass=True, **SEC),
    door("lt1", "garden", type="shutter", id="permacell1", name="Cell Shutters"),
    door("lt2", "permacommon", type="shutter", id="permacell2", name="Cell Shutters"),
    door("lt3", "permacommon", type="shutter", id="permacell3", name="Cell Shutters"),
    door("sanit", "prisonhall", name="Prison Sanitarium", access="2", glass=True, **SEC),
    door("sanit", "permacommon", name="Prison Common Room", access="2", glass=True, **SEC),
    door("garden", "permacommon", name="Prison Garden", glass=True, kind="public"),
    glass("garden", "permacommon", inset=1),
    door("exec", "prisonhall", name="Prisoner Education Chamber", access="3",
         vars={"id_tag": "prisonereducation"}, **SEC),
    door("justice", "exec", type="windoor", name="Justice Chamber", access="3"),
    glass("justice", "exec"),
]


def graph(**over):
    P = dict(PARAMS)
    P.update(over)
    g = G.Graph(NAME, **P)
    g.add("outline", shell.outline, view="kind", base=BASE_MAP, bbox=BBOX, in_zone=in_zone)
    g.add("check", check_drawing, view="kind")
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
    G.draw(geo, "items", os.path.join(out, NAME + "_furnish_big.png"), tile=24, title="furnish")
    for n in geo.notes:
        print(n)
    for p in geo.problems:
        print("PROBLEM", p)
    print("pictures:", os.path.relpath(os.path.join(out, NAME + "_nodes.png"), ROOT))


if __name__ == "__main__":
    main()
