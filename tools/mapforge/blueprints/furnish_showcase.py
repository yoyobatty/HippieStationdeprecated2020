"""Auto-furnishing showcase: twelve identical empty rooms (9x7 inside, door on the hall side), each given only a
room type. Everything inside comes from mapforge's corpus of real map clusters."""
NAME = "furnish_showcase"
BASE = "blank"
ORIGIN = (2, 2)
ATMOS = False
POWER = False

ROW1 = [("/area/crew_quarters/kitchen", "/turf/open/floor/plasteel/cafeteria", "Kitchen"),
        ("/area/medical/medbay/central", "/turf/open/floor/plasteel/white", "Medbay"),
        ("/area/crew_quarters/heads/captain", "/turf/open/floor/wood", "Captain's Office"),
        ("/area/science/lab", "/turf/open/floor/plasteel/white", "Research Lab"),
        ("/area/library", "/turf/open/floor/wood", "Library"),
        ("/area/medical/chemistry", "/turf/open/floor/plasteel/white", "Chemistry")]
ROW2 = [("/area/crew_quarters/dorms", "/turf/open/floor/carpet", "Dorms"),
        ("/area/security/main", "/turf/open/floor/plasteel/dark", "Security Office"),
        ("/area/crew_quarters/bar", "/turf/open/floor/wood", "Bar"),
        ("/area/hydroponics", "/turf/open/floor/plasteel", "Hydroponics"),
        ("/area/science/robotics/lab", "/turf/open/floor/plasteel/white", "Robotics"),
        ("/area/chapel/office", "/turf/open/floor/plasteel/grimy", "Chapel Office")]
W, H = 9, 7
LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWX"


def row_rows(n, letters, door_side):
    """Return (layout rows, room rows) for one row of n rooms, top row first."""
    wall = "#" * (n * (W + 1) + 1)
    lay, rooms = [], []
    inner_l, inner_r = "", ""
    for r in range(H):
        a, b = "#", "~"
        for i in range(n):
            a += "." * W + "#"
            b += letters[i] * W + "~"
        lay.append(a)
        rooms.append(b)
    door = "#"
    droom = "~"
    for i in range(n):
        door += "#" * (W // 2) + "D" + "#" * (W // 2) + "#"
        droom += "~" * (W // 2) + letters[i] + "~" * (W // 2) + "~"
    if door_side == "bottom":
        return [wall] + lay + [door], ["~" * len(wall)] + rooms + [droom]
    return [door] + lay + [wall], [droom] + rooms + ["~" * len(wall)]


l1, r1 = row_rows(6, LETTERS[:6], "bottom")
l2, r2 = row_rows(6, LETTERS[6:12], "top")
hall = "." * len(l1[0])
LAYOUT = "\n".join(l1 + [hall, hall] + l2)
ROOMS = "\n".join(r1 + ["h" * len(hall)] * 2 + r2)

LEGEND = {"D": {"obj": ["/obj/machinery/door/airlock/public/glass"]}}
ROOMDEFS = {"h": dict(area="/area/hallway/primary/central", floor="/turf/open/floor/plasteel", name="Hall", camera=False)}
for i, (area, floor, name) in enumerate(ROW1 + ROW2):
    ROOMDEFS[LETTERS[i]] = dict(area=area, floor=floor, name=name, furnish=dict(kind=area, seed=1))
