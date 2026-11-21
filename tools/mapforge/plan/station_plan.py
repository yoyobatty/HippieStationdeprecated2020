"""Station master plan, drawn by hand (studies/mapping_practice.md stages 1-4: program, bubbles, parti, block plan).

    python tools/mapforge/plan/station_plan.py        # data/previews/mapforge/plan/station_plan.png + numbers

Parti (v6): a 3-wide hall ring round the command core, four 3-wide arms out of it (arrivals west, escape south,
the AI bridge east, the chapel and library north), plazas where the arms meet the ring, and 2-wide arterials
branching off the arms. Departments are wedges between the arms with stepped outlines (stock departments are never
plain boxes). Each has its front on a hall and its back on maint. Maint is thin 2-wide corridors weaving between the
departments plus a few maint rooms, and solars sit out on catwalks at the four corners.

Coordinates: x right, y DOWN (as drawn). A block shape is either a rect (x0, y0, x1, y1), inclusive, or a list of
polygon corners [(x, y), ...] on tile edges: the tile (x, y) is inside when its centre (x + .5, y + .5) is. A
department block includes its own outer walls; halls and maint are floor only (their walls belong to the blocks
beside them or to the hull). "public" blocks are small rooms off the halls (restrooms, vending, lounges, vacant
offices) that belong to no department.
"""
import os
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(ROOT, "data", "previews", "mapforge", "plan")

# stage 1: program, floor tiles per department (median of six stock stations, mapping_practice.md)
PROGRAM = {"command": 387, "security": 777, "medical": 555, "science": 872, "cargo": 296, "service": 413,
           "dorms": 315, "civic": 586, "engineering": 929, "ai": 200}

# stage 2: links the plan must have (bubble diagram)
LINKS = [("security", "arrivals"), ("security", "command"), ("cargo", "arrivals"), ("medical", "science"),
         ("medical", "escape"), ("dorms", "service"), ("civic", "escape"), ("engineering", "command"),
         ("ai", "command")]

HALLS = {
    # the ring round the command core
    "ring N": (77, 68, 102, 70), "ring S": (77, 89, 102, 91), "ring W": (77, 68, 79, 91), "ring E": (100, 68, 102, 91),
    # primary arms, 3 wide
    "arm W": (38, 78, 76, 80), "arm E": (103, 78, 140, 80), "arm N": (88, 30, 90, 67), "arm S": (88, 92, 90, 135),
    "AI bridge": (141, 79, 165, 79),
    # plazas where the arms meet the ring, and lobbies at the arm ends
    "plaza N": (85, 63, 93, 67), "plaza S": (85, 92, 93, 96), "plaza W": (72, 76, 76, 82), "plaza E": (103, 76, 107, 82),
    "north plaza": (84, 26, 94, 30), "arrivals lobby": (26, 74, 37, 84), "escape lobby": (82, 136, 96, 145),
    # arterials, 2 wide
    "art NW": (38, 46, 87, 47), "art NE": (91, 46, 126, 47), "art SW": (44, 108, 87, 109),
    "art SE": (91, 111, 136, 112),
}
BLOCKS = {
    "command": [(80, 71, 99, 88),                                                       # bridge, captain, HoP
                [(70, 34), (88, 34), (88, 46), (70, 46)]],                              # EVA, teleporter, tech storage
    # security took the two maint rooms between it and cargo and the vending nook off arm W (2026-11-21): the
    # courtroom, the execution room and a third long-term cell needed the room
    "security": [[(58, 48), (88, 48), (88, 68), (77, 68), (77, 78), (50, 78), (50, 50), (58, 50)]],
    "cargo": [[(36, 50), (48, 50), (48, 78), (30, 78), (30, 61), (34, 61), (34, 57), (36, 57)]],
    "service": [[(91, 48), (113, 48), (113, 78), (103, 78), (103, 68), (91, 68)]],
    "dorms": [[(115, 52), (129, 52), (129, 56), (134, 56), (134, 70), (129, 70), (129, 78), (115, 78)]],
    "civic": [[(91, 28), (99, 28), (99, 19), (111, 19), (111, 28), (120, 28), (120, 32), (124, 32), (124, 46),
               (91, 46)]],
    # engineering took the maint east of it (2026-11-21): the supermatter stamp needs a hull wall with the coil in
    # open space behind it, so the block's east side is the station's hull from row 86 down
    "engineering": [[(103, 81), (139, 81), (139, 86), (141, 86), (141, 111), (103, 111)],
                    # atmos: one column west and one row north (2026-11-21) so it fronts arm S and the arterial
                    [(91, 113), (113, 113), (113, 126), (108, 126), (108, 131), (91, 131)]],
    "ai": [[(166, 71), (179, 71), (179, 74), (183, 74), (183, 85), (179, 85), (179, 89), (166, 89)]],
    "medical": [[(56, 81), (77, 81), (77, 92), (88, 92), (88, 108), (62, 108), (62, 100), (56, 100)]],
    # science took the escape-side lounge (2026-11-18): the toxins tail needed a square base for xenobiology
    "science": [[(44, 110), (88, 110), (88, 136), (79, 136), (79, 148), (67, 148), (67, 130), (52, 130), (52, 124),
                 (44, 124)]],
    "public": [(40, 81, 53, 84),                    # arrivals lounge and restrooms
               (91, 92, 102, 100)],                 # south lounge
}
# maint corridors, 2 wide, weaving between the departments
MAINT = [
    (36, 32, 87, 33), (36, 34, 37, 49), (36, 48, 57, 49), (48, 50, 49, 77), (53, 34, 54, 45), (68, 34, 69, 45),
    (120, 28, 125, 31), (124, 32, 125, 45), (113, 48, 114, 77), (115, 48, 128, 51),
    (91, 101, 102, 102), (101, 103, 102, 110), (113, 113, 114, 132),
    (92, 131, 112, 132),
    (30, 85, 55, 86), (54, 87, 55, 107), (30, 87, 31, 131), (44, 87, 45, 105), (32, 106, 53, 107),
    (32, 108, 43, 109), (32, 126, 51, 127), (32, 128, 66, 131),
]
# maint rooms: the abandoned or odd rooms that signpost each maint stretch
MAINT_ROOMS = [
    (38, 34, 52, 45), (55, 34, 67, 45),             # behind the EVA wing
    (91, 103, 100, 110),                            # behind the south lounge
    (32, 87, 43, 105), (46, 87, 53, 105),           # below arrivals
    (32, 110, 51, 125), (108, 126, 112, 130),                             # beside science
    (56, 100, 61, 107),                             # medical's back corner
]
DOCKS = {"arrivals": (18, 76, 25, 82), "supply": (24, 62, 29, 68), "escape": (84, 146, 94, 152),
         "solars NW": (14, 14, 22, 22), "solars NE": (150, 10, 158, 18), "solars SE": (150, 118, 158, 126),
         "solars SW": (14, 138, 22, 146)}
CATWALKS = [(137, 111, 137, 111), (23, 18, 35, 18), (35, 19, 35, 31), (125, 14, 149, 14), (125, 15, 125, 27), (139, 122, 149, 122),
            (138, 111, 138, 121), (23, 142, 29, 142), (29, 132, 29, 141)]

COL = {"command": (70, 110, 200), "security": (200, 60, 60), "medical": (90, 190, 220), "science": (170, 90, 210),
       "engineering": (230, 170, 40), "cargo": (180, 130, 60), "service": (90, 180, 90), "dorms": (150, 150, 110),
       "civic": (130, 160, 150), "ai": (110, 110, 130), "hall": (215, 215, 205), "maint": (110, 85, 60),
       "dock": (240, 240, 240), "public": (235, 205, 160), "maint room": (80, 62, 44)}


def tiles_of(shape):
    """The tiles of one block shape: an inclusive rect or a rectilinear polygon (see the module docstring)."""
    if isinstance(shape, tuple):
        x0, y0, x1, y1 = shape
        return [(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)]
    ys = [p[1] for p in shape]
    edges = list(zip(shape, shape[1:] + shape[:1]))
    out = []
    for y in range(min(ys), max(ys)):
        cy = y + 0.5
        # crossings of the row's centre line with the polygon's vertical edges
        cross = sorted(a[0] for a, b in edges if a[0] == b[0] and min(a[1], b[1]) < cy < max(a[1], b[1]))
        for i in range(0, len(cross) - 1, 2):
            out.extend((x, y) for x in range(cross[i], cross[i + 1]))
    return out


def grid():
    g = {}
    for name, shapes in BLOCKS.items():
        for s in shapes:
            for p in tiles_of(s):
                g[p] = name
    for r in MAINT:
        for p in tiles_of(r):
            g.setdefault(p, "maint")
    for r in MAINT_ROOMS:
        for p in tiles_of(r):
            g.setdefault(p, "maint room")
    for r in HALLS.values():
        for p in tiles_of(r):
            g[p] = "hall"
    for r in list(DOCKS.values()) + CATWALKS:
        for p in tiles_of(r):
            g.setdefault(p, "dock")
    return g


def numbers(g):
    out = []
    cnt = Counter(g.values())
    cnt["maint"] += cnt["maint room"]
    D4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
    for name, target in PROGRAM.items():
        tiles = [p for p, v in g.items() if v == name]
        # floor estimate: block tiles minus its outer wall ring
        edge = sum(1 for p in tiles if any(g.get((p[0] + dx, p[1] + dy)) != name for dx, dy in D4))
        floor = len(tiles) - edge
        front = any(g.get((p[0] + dx, p[1] + dy)) == "hall" for p in tiles for dx, dy in D4)
        back = any(g.get((p[0] + dx, p[1] + dy)) in ("maint", "maint room") for p in tiles for dx, dy in D4)
        out.append("%-12s floor ~%4d (program %4d, %+4d%%)  front on hall: %-3s  back on maint: %s" % (
            name, floor, target, round(100.0 * (floor - target) / target), "yes" if front else "NO",
            "yes" if back else "NO"))
    xs = [p[0] for p in g]
    ys = [p[1] for p in g]
    box = (max(xs) - min(xs) + 1) * (max(ys) - min(ys) + 1)
    total = len(g)
    out.append("total %d tiles (stock 8500-9400 floor), halls %d (%.0f%%, stock 15%%), maint %d (%.0f%%, stock 18-20%%), "
               "public %d, fill of bounding box %.2f (stock 0.45)" % (
                   total, cnt["hall"], 100.0 * cnt["hall"] / total, cnt["maint"], 100.0 * cnt["maint"] / total,
                   cnt["public"], total / float(box)))
    # pieces: every kind should be one connected piece (a detached bit of a department is a plan fault)
    for name in list(PROGRAM) + ["hall"]:
        left = {p for p, v in g.items() if v == name}
        parts = 0
        while left:
            parts += 1
            st = [left.pop()]
            while st:
                p = st.pop()
                for dx, dy in D4:
                    q = (p[0] + dx, p[1] + dy)
                    if q in left:
                        left.discard(q)
                        st.append(q)
        if parts > 1:
            out.append("  %s is in %d pieces" % (name, parts))
    return out


def render(g, path, T=7, labels=True):
    from PIL import Image, ImageDraw
    xs = [p[0] for p in g]
    ys = [p[1] for p in g]
    x0, y0 = min(xs) - 3, min(ys) - 3
    W, H = max(xs) - x0 + 4, max(ys) - y0 + 4
    img = Image.new("RGB", (W * T, H * T), (12, 14, 22))
    d = ImageDraw.Draw(img)
    for (x, y), v in g.items():
        c = COL.get(v, (200, 200, 200))
        d.rectangle([(x - x0) * T, (y - y0) * T, (x - x0 + 1) * T - 1, (y - y0 + 1) * T - 1], fill=c)
    # block outlines: a dark line wherever the kind changes
    for (x, y), v in g.items():
        for dx, dy in ((1, 0), (0, 1)):
            if g.get((x + dx, y + dy)) != v:
                X, Y = (x - x0 + 1) * T, (y - y0 + 1) * T
                if dx:
                    d.line([X - 1, (y - y0) * T, X - 1, Y - 1], fill=(20, 20, 26), width=2)
                else:
                    d.line([(x - x0) * T, Y - 1, X - 1, Y - 1], fill=(20, 20, 26), width=2)
    if labels:
        for name in BLOCKS:
            if name == "public":
                continue
            ts = [p for p, v in g.items() if v == name]
            if not ts:
                continue
            cx = sum(p[0] for p in ts) / float(len(ts))
            cy = sum(p[1] for p in ts) / float(len(ts))
            d.text(((cx - x0) * T - 20, (cy - y0) * T - 5), name.upper(), fill=(10, 10, 10))
        for name, r in DOCKS.items():
            d.text(((r[0] - x0) * T, (r[1] - y0) * T - 12), name, fill=(230, 230, 230))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    return img.size


if __name__ == "__main__":
    g = grid()
    for line in numbers(g):
        print(line)
    print(render(g, os.path.join(OUT, "station_plan.png")))
