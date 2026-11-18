"""Semantic parser: a .dmm read as a mapper reads it. Human and generated maps go through the same code, so every
measurement and judge treats them alike.

    python tools/mapforge/forge/parse.py MetaStation      # summary of one map (name from MAPS, or a .dmm path)

SemanticMap (one z-level, the station level):
    cls[p]      'S' space, 'W' wall (glass too), 'D' door, 'F' floor
    glass       wall tiles that are windows/grilles
    area[p]     area path, group[p] department group (studies/stations.py GROUPS) or None
    region[p]   region id of a floor tile: 4-connected floor of one area, not crossing walls or doors
    regions     id -> Region(kind 'room'|'hall'|'maint'|'other', area, group, tiles, doors, links)
    doors       door tile -> set of region ids it joins
    dense       floor tiles with a dense object; furn = tiles with furniture anchors
    hung        (floor tile, side) -> wall pieces hung on that face (side 1 N, 2 S, 4 E, 8 W)
    count       per-type counts on floor tiles: light, vent, scrubber, airalarm, firealarm, apc, decal, tile_decal, item
    crew        roundstart job slots (start landmarks, not AI/cyborg/assistant)
"""
import os
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", "studies"))
from forge import dmm, kit, corpus  # noqa: E402
import stations as ST  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
MAPS = {
    "MetaStation": "MetaStation/MetaStation.dmm",
    "DeltaStation": "Deltastation/DeltaStation2.dmm",
    "BoxStation": "BoxStation/BoxStation.dmm",
    "PubbyStation": "PubbyStation/PubbyStation.dmm",
    "DonutStation": "Donutstation/Donutstation.dmm",
    "HippieStation": "HippieStation/hippiestation.dmm",
    "MiniStation": "MiniStation/ministation.dmm",
    "EndoStation": "EndoStation/EndoStation.dmm",
    "MetaLake": "MetaLake/MetaLake.dmm",
}
DIRS = ((1, 0), (-1, 0), (0, 1), (0, -1))
SIDE = {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0)}
AIRLOCK = ("/obj/machinery/door/airlock",)
EDGE_DOOR = ("/obj/machinery/door/window", "/obj/machinery/door/poddoor/shutters")
GLASS = ("/obj/effect/spawner/structure/window", "/obj/structure/grille", "/obj/structure/window/reinforced/fulltile",
         "/obj/structure/window/fulltile", "/obj/structure/window/plasma/reinforced/fulltile",
         "/obj/structure/window/plasma/fulltile", "/obj/structure/window/shuttle")
SPACE = ("/turf/open/space", "/turf/open/openspace", "/turf/open/chasm", "/turf/open/lava")
HALLS = ("hall", "arrivals", "escape")
COUNT = {
    "light": "/obj/machinery/light", "vent": "/obj/machinery/atmospherics/components/unary/vent_pump",
    "scrubber": "/obj/machinery/atmospherics/components/unary/vent_scrubber", "airalarm": "/obj/machinery/airalarm",
    "firealarm": "/obj/machinery/firealarm", "apc": "/obj/machinery/power/apc", "tile_decal": "/obj/effect/turf_decal/tile",
    "decal": "/obj/effect/turf_decal", "grime": "/obj/effect/decal/cleanable", "item": "/obj/item",
    "sign": "/obj/structure/sign", "camera": "/obj/machinery/camera",
}
NOT_HUNG = ("/obj/structure/sign/barsign", "/obj/machinery/light/floor", "/obj/machinery/atmospherics", "/obj/structure/cable", "/obj/structure/disposalpipe", "/obj/effect",
            "/obj/item/", "/obj/machinery/door")
HUNG_ALWAYS = ("/obj/machinery/light", "/obj/machinery/power/apc", "/obj/machinery/airalarm", "/obj/machinery/firealarm",
               "/obj/machinery/camera", "/obj/machinery/light_switch", "/obj/structure/extinguisher_cabinet",
               "/obj/machinery/newscaster", "/obj/item/radio/intercom", "/obj/structure/sign", "/obj/machinery/status_display",
               "/obj/machinery/requests_console", "/obj/structure/noticeboard", "/obj/structure/mirror",
               "/obj/machinery/button", "/obj/machinery/computer/security/telescreen", "/obj/machinery/vending/wallmed",
               "/obj/machinery/defibrillator_mount", "/obj/structure/fireaxecabinet", "/obj/machinery/flasher",
               "/obj/machinery/firealarm", "/obj/machinery/keycard_auth", "/obj/structure/sink")


def _has(t, prefixes):
    return any(o.path.startswith(prefixes) for o in t.objs)


def map_path(name):
    if name in MAPS:
        return os.path.join(ROOT, "_maps", "map_files", MAPS[name])
    if os.path.exists(name):
        return name
    g = os.path.join(ROOT, "_maps", "map_files", "Generated", name + ".dmm")
    return g if os.path.exists(g) else name


class Region:
    __slots__ = ("id", "kind", "area", "group", "tiles", "doors", "links")

    def __init__(self, rid, area, group):
        self.id, self.area, self.group = rid, area, group
        self.kind = ("hall" if group in HALLS else "maint" if group == "maint"
                     else "other" if group in (None, "shuttle", "solar") else "room")
        self.tiles, self.doors, self.links = [], set(), set()


def _hang_side(a, floor_dirs):
    """Wall side a mounted piece hangs on, or 0. Pixel offsets win; else lights/cameras go by dir."""
    px, py = a.num("pixel_x"), a.num("pixel_y")
    if abs(px) >= 16 or abs(py) >= 16:
        if abs(py) >= abs(px):
            return 1 if py > 0 else 2
        return 4 if px > 0 else 8
    if a.path.startswith("/obj/machinery/light") and not a.path.startswith("/obj/machinery/light_switch"):
        d = a.num("dir", 2)
        return d if d in SIDE else 0
    return 0


class SemanticMap:
    def __init__(self, m, name="", z=1):
        self.name, self.m, self.z = name, m, z
        self.cls, self.glass, self.area, self.group = {}, set(), {}, {}
        self.dense, self.furn, self.items = set(), set(), Counter()
        self.hung = defaultdict(list)
        self.count = Counter()
        self.decals = defaultdict(list)
        starts = Counter()
        for (x, y, zz), t in m.tiles.items():
            if zz != z:
                continue
            p = (x, y)
            tp = t.tpath or ""
            ap = t.apath or ""
            self.area[p] = ap
            self.group[p] = ST.group_of(ap)
            if _has(t, AIRLOCK):
                c = "D"
            elif tp.startswith("/turf/closed") or _has(t, GLASS):
                c = "W"
                if not tp.startswith("/turf/closed"):
                    self.glass.add(p)
            elif _has(t, EDGE_DOOR) and not _has(t, ("/obj/structure/table",)):
                c = "D"
            elif (tp.startswith(SPACE) or not tp) and not _has(t, ("/obj/structure/lattice/catwalk",)):
                c = "S"  # a catwalk over space or an open deck is walked like floor (Catwalk Station, engine rings)
            else:
                c = "F"
            self.cls[p] = c
            if c != "F":
                continue
            for a in t.objs:
                path = a.path
                if path.startswith("/obj/effect/landmark/start/"):
                    starts[path.rsplit("/", 1)[1]] += 1
                if self.group[p] not in (None, "shuttle", "solar"):
                    for k, pre in COUNT.items():
                        if path.startswith(pre):
                            self.count[k] += 1
                if path.startswith("/obj/effect/turf_decal"):
                    self.decals[p].append(a)
                if path.startswith("/obj/item") and not corpus.mounted(a):
                    self.items[p] += 1
                if not path.startswith(NOT_HUNG[:2]) and (path.startswith(HUNG_ALWAYS) or
                                                          (corpus.mounted(a) and not path.startswith(NOT_HUNG))):
                    s = _hang_side(a, None)
                    if s:
                        self.hung[(p, s)].append(path)
                        continue
                if kit.is_dense_atom(a) and not path.startswith(("/obj/structure/window", "/obj/machinery/door")):
                    self.dense.add(p)
            anchors, _ = corpus.furniture(t)
            if anchors:
                self.furn.add(p)
        self.crew = sum(v for k, v in starts.items() if k not in ("ai", "cyborg", "assistant"))
        self._regions()

    def _regions(self):
        self.region, self.regions = {}, {}
        rid = 0
        for p, c in self.cls.items():
            if c != "F" or p in self.region:
                continue
            ap = self.area[p]
            r = Region(rid, ap, self.group[p])
            self.regions[rid] = r
            stack = [p]
            self.region[p] = rid
            while stack:
                a = stack.pop()
                r.tiles.append(a)
                for dx, dy in DIRS:
                    b = (a[0] + dx, a[1] + dy)
                    if b not in self.region and self.cls.get(b) == "F" and self.area.get(b) == ap:
                        self.region[b] = rid
                        stack.append(b)
            rid += 1
        self.doors = {}
        for p, c in self.cls.items():
            if c != "D":
                continue
            js = set()
            for (dx, dy) in ((1, 0), (0, 1)):
                a, b = (p[0] + dx, p[1] + dy), (p[0] - dx, p[1] - dy)
                ra, rb = self.region.get(a), self.region.get(b)
                if ra is not None and rb is not None:
                    js.update((ra, rb))
            # airlock chains (double doors, cycling locks): look one door further
            if len(js) < 2:
                for (dx, dy) in DIRS:
                    q = (p[0] + dx, p[1] + dy)
                    if self.cls.get(q) == "D":
                        r2 = self.region.get((q[0] + dx, q[1] + dy))
                        r1 = self.region.get((p[0] - dx, p[1] - dy))
                        if r1 is not None and r2 is not None:
                            js.update((r1, r2))
            self.doors[p] = js
            for r in js:
                self.regions[r].doors.add(p)
                self.regions[r].links.update(js - {r})
        # open seams: floor of two areas touching edge to edge
        for p, r in self.region.items():
            for dx, dy in ((1, 0), (0, 1)):
                r2 = self.region.get((p[0] + dx, p[1] + dy))
                if r2 is not None and r2 != r:
                    self.regions[r].links.add(r2)
                    self.regions[r2].links.add(r)

    # ---- helpers used by fingerprint/judges ----
    def station_tiles(self):
        """Floor of the station proper: grouped, not shuttle/solar/space-only areas."""
        return [p for p, c in self.cls.items() if c == "F" and self.group.get(p) not in (None, "shuttle", "solar")]

    def rooms(self, min_tiles=4):
        return [r for r in self.regions.values() if r.kind == "room" and len(r.tiles) >= min_tiles]

    def bbox(self, tiles):
        xs, ys = [p[0] for p in tiles], [p[1] for p in tiles]
        return min(xs), min(ys), max(xs), max(ys)


def corners(tiles):
    """Outline corners of a tile set (a rectangle has 4); a diagonal pair counts 2."""
    s = set(tiles)
    seen = set()
    n = 0
    for (x, y) in s:
        for cx in (x - 1, x):
            for cy in (y - 1, y):
                if (cx, cy) in seen:
                    continue
                seen.add((cx, cy))
                w = [(cx, cy) in s, (cx + 1, cy) in s, (cx, cy + 1) in s, (cx + 1, cy + 1) in s]
                k = sum(w)
                if k in (1, 3):
                    n += 1
                elif k == 2 and w[0] == w[3]:
                    n += 2
    return n


_CACHE = {}


_CORPUS = None


def corpus_maps():
    """Human maps from other codebases (forge/corpus_index.py): name -> dict(path, z, source)."""
    global _CORPUS
    if _CORPUS is None:
        import json
        p = os.path.join(ROOT, "data", "mapforge", "corpus", "index.json")
        _CORPUS = {k: v for k, v in json.load(open(p)).items() if v.get("keep")} if os.path.exists(p) else {}
    return _CORPUS


def humans():
    """Every human map: the 9 in MAPS, then the corpus from other codebases."""
    return list(MAPS) + list(corpus_maps())


def load(name, z=1):
    label = None
    cm = corpus_maps().get(name)
    if cm:
        path, z, label = cm["path"], cm["z"], name
    else:
        path = map_path(name)
    key = (path, z)
    if key not in _CACHE:
        if label is None:
            label = os.path.splitext(os.path.basename(path))[0] if name not in MAPS else name
        m = dmm.read(path)
        from forge import alias
        if cm or alias.needs(m):
            alias.apply(m)
        _CACHE[key] = SemanticMap(m, label, z)
    return _CACHE[key]


if __name__ == "__main__":
    import time
    t0 = time.time()
    sm = load(sys.argv[1] if len(sys.argv) > 1 else "MetaStation")
    kinds = Counter(r.kind for r in sm.regions.values())
    print("%s: %d tiles, %d station floor, crew %d, regions %s, doors %d, dense %d, hung faces %d (%.1fs)" % (
        sm.name, len(sm.cls), len(sm.station_tiles()), sm.crew, dict(kinds), len(sm.doors), len(sm.dense),
        len(sm.hung), time.time() - t0))
    print(dict(sm.count))
