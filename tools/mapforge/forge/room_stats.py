"""Per-room numbers, the same for human and generated maps, so a room can be held against rooms of its type on the
stock maps. Shared by room_twin.py (side-by-side twins), style_bands.py (bands per room type) and disc_rooms.py.

    python tools/mapforge/forge/room_stats.py MetaStation [area-substring]     # print the rooms of one map

A room here is one area's floor on the station level (parse.SemanticMap regions of kind "room" with that area),
the largest piece of it when it lies in several places (pieces within 2 tiles of each other count as one: a door or
a counter between them). Its type is the area path; type_of() falls back to the parent path when the exact path
has too few rooms on the stock maps.

STATS (each a float; per-tile numbers are per floor tile of the room):
    tiles        floor tiles
    fill         tiles / bounding-box area (1.0 = a rectangle)
    corners      outline corners (4 = a rectangle)
    doors        door tiles touching the room
    furn         tiles with furniture anchors, per tile
    dense        tiles with something dense, per tile
    decal        turf decals, per tile (tile colour, trims, stripes, boxes)
    trim         colour-tile decals (/obj/effect/turf_decal/tile), per tile
    items        loose items, per tile
    grime        cleanables (dirt, blood, cobwebs), per tile
    pieces       wall pieces hung on the room's wall faces, per wall face
    glass        share of the room's wall tiles that are windows
    lights       lights per 10 tiles
    turfs        distinct floor turf types
    turf_top     share of the commonest floor turf
"""
import os
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import parse  # noqa: E402

STATS = ("tiles", "fill", "corners", "doors", "furn", "dense", "decal", "trim", "items", "grime", "pieces", "glass",
         "lights", "turfs", "turf_top")
# the stock maps the user named as the look to match (2026-11-22: "meta/delta/omega/hippie")
REFS = ("MetaStation", "DeltaStation", "citadel:OmegaStation", "HippieStation")
SHORT = {"MetaStation": "Meta", "DeltaStation": "Delta", "citadel:OmegaStation": "Omega", "HippieStation": "Hippie"}
DIRS8 = [(dx, dy) for dx in (-2, -1, 0, 1, 2) for dy in (-2, -1, 0, 1, 2) if (dx, dy) != (0, 0)]


class Room:
    __slots__ = ("map", "area", "tiles", "box", "stats", "paths")

    def __init__(self, mapname, area, tiles):
        self.map, self.area, self.tiles = mapname, area, tiles
        xs, ys = [p[0] for p in tiles], [p[1] for p in tiles]
        self.box = (min(xs), min(ys), max(xs), max(ys))
        self.stats, self.paths = {}, Counter()

    @property
    def name(self):
        return self.area.rsplit("/", 1)[-1]

    def centre(self):
        x0, y0, x1, y1 = self.box
        return (x0 + x1) // 2, (y0 + y1) // 2


def _pieces_of(tiles):
    """Pieces within 2 tiles of each other, largest first."""
    left, out = set(tiles), []
    while left:
        s = left.pop()
        c, q = [s], [s]
        while q:
            a = q.pop()
            for dx, dy in DIRS8:
                b = (a[0] + dx, a[1] + dy)
                if b in left:
                    left.discard(b)
                    c.append(b)
                    q.append(b)
        out.append(c)
    out.sort(key=len, reverse=True)
    return out


def _family(path):
    """A path cut to its family, for "which kinds of things stand in this room": four segments of an /obj path
    (/obj/machinery/vending/cola -> /obj/machinery/vending/cola, /obj/structure/table/wood/fancy -> .../table/wood)."""
    parts = path.split("/")
    return "/".join(parts[:5]) if len(parts) > 5 else path


def rooms(sm, min_tiles=4):
    """Every room of a SemanticMap with its stats and the object families in it."""
    by_area = defaultdict(list)
    for r in sm.regions.values():
        if r.kind == "room":
            by_area[r.area].extend(r.tiles)
    out = []
    z = sm.z
    for area, ts in by_area.items():
        piece = _pieces_of(ts)[0]
        if len(piece) < min_tiles:
            continue
        rm = Room(sm.name, area, piece)
        out.append(rm)
        tset = set(piece)
        n = float(len(piece))
        x0, y0, x1, y1 = rm.box
        walls, glass, faces, doors = set(), 0, 0, set()
        pieces = 0
        for p in piece:
            for s, (dx, dy) in parse.SIDE.items():
                q = (p[0] + dx, p[1] + dy)
                c = sm.cls.get(q)
                if c == "W":
                    walls.add(q)
                    faces += 1
                    pieces += len(sm.hung.get((p, s), ()))
                elif c == "D":
                    doors.add(q)
        glass = sum(1 for w in walls if w in sm.glass)
        turfs = Counter()
        decal = trim = items = grime = lights = 0
        for p in piece:
            t = sm.m.tiles.get((p[0], p[1], z))
            if t is None:
                continue
            turfs[t.tpath or ""] += 1
            for a in t.objs:
                path = a.path
                if path.startswith("/obj/effect/turf_decal"):
                    decal += 1
                    if path.startswith("/obj/effect/turf_decal/tile"):
                        trim += 1
                elif path.startswith("/obj/effect/decal/cleanable"):
                    grime += 1
                elif path.startswith("/obj/machinery/light") and not path.startswith("/obj/machinery/light_switch"):
                    lights += 1
                if path.startswith(("/obj/machinery", "/obj/structure", "/obj/item")) and not path.startswith(
                        ("/obj/machinery/atmospherics", "/obj/structure/cable", "/obj/structure/disposalpipe",
                         "/obj/machinery/door/firedoor")):
                    rm.paths[_family(path)] += 1
            items += sm.items.get(p, 0)
        rm.stats = dict(
            tiles=n, fill=n / ((x1 - x0 + 1) * (y1 - y0 + 1)), corners=float(parse.corners(piece)),
            doors=float(len(doors)), furn=len(tset & sm.furn) / n, dense=len(tset & sm.dense) / n,
            decal=decal / n, trim=trim / n, items=items / n, grime=grime / n,
            pieces=pieces / max(1, faces), glass=glass / max(1, len(walls)), lights=10 * lights / n,
            turfs=float(len([k for k in turfs if k])), turf_top=max(turfs.values()) / n if turfs else 0.0)
    return out


def map_pieces(m, tiles):
    """(wall pieces, wall faces) of tiles on a dmm.Map, counted as rooms() counts "pieces" (parse's hang rules and
    wall classes), for the builders that place pieces before there is a SemanticMap (station/v6_station.py,
    station/v6_habits.py)."""
    def is_w(t):
        if t is None:
            return False
        if any(o.path.startswith(parse.AIRLOCK) for o in t.objs):
            return False
        return (t.tpath or "").startswith("/turf/closed") or any(o.path.startswith(parse.GLASS) for o in t.objs)
    pieces = faces = 0
    for p in tiles:
        t = m.get(p[0], p[1])
        sides = {s for s, (dx, dy) in parse.SIDE.items() if is_w(m.get(p[0] + dx, p[1] + dy))}
        faces += len(sides)
        if t is None:
            continue
        for a in t.objs:
            path = a.path
            if not path.startswith(parse.NOT_HUNG[:2]) and (path.startswith(parse.HUNG_ALWAYS) or (
                    parse.corpus.mounted(a) and not path.startswith(parse.NOT_HUNG))):
                if parse._hang_side(a, None) in sides:
                    pieces += 1
    return pieces, faces


_REF = None


def ref_rooms():
    """Rooms of the four stock maps, by area path."""
    global _REF
    if _REF is None:
        _REF = defaultdict(list)
        for name in REFS:
            for rm in rooms(parse.load(name)):
                _REF[rm.area].append(rm)
    return _REF


def type_of(area, need=2):
    """The area path to compare by: the exact path when the stock maps have `need` rooms of it, else the nearest
    parent path that has (/area/medical/patients_rooms/room_b -> /area/medical/patients_rooms), else None."""
    ref = ref_rooms()
    a = area
    while a.count("/") >= 2:
        n = sum(len(v) for k, v in ref.items() if k == a or k.startswith(a + "/"))
        if n >= need:
            return a
        a = a.rsplit("/", 1)[0]
    return None


def peers(kind):
    """Stock rooms of a type (the path and every path under it)."""
    return [rm for k, v in ref_rooms().items() if k == kind or k.startswith(kind + "/") for rm in v]


def fmt(v, stat):
    if stat in ("tiles", "corners", "doors", "turfs"):
        return "%d" % round(v)
    return "%.2f" % v


if __name__ == "__main__":
    sm = parse.load(sys.argv[1] if len(sys.argv) > 1 else "MetaStation")
    want = sys.argv[2] if len(sys.argv) > 2 else ""
    for rm in sorted(rooms(sm), key=lambda r: r.area):
        if want in rm.area:
            print("%-48s %s" % (rm.area[:48], " ".join("%s=%s" % (k, fmt(rm.stats[k], k)) for k in STATS)))
