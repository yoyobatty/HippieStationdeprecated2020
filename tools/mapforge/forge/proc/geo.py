"""The geometry a node graph works on, the graph runner, and the schematic drawing of a node's output."""
import copy
import os

N, S, E, W = 1, 2, 4, 8
CARD = (N, S, E, W)
DELTA = {N: (0, 1), S: (0, -1), E: (1, 0), W: (-1, 0)}
OPP = {N: S, S: N, E: W, W: E}
CW = {N: E, E: S, S: W, W: N}
CCW = {v: k for k, v in CW.items()}
NAME = {N: "north", S: "south", E: "east", W: "west"}
DIAG = ((1, 1), (1, -1), (-1, 1), (-1, -1))

SOLID = ("wall", "ring", "raw")     # zone tile kinds nobody walks through (raw: a stamped module's own tile)
BARRIER = SOLID + ("glass", "door", "keep_door", "raw")


def step(p, d, n=1):
    dx, dy = DELTA[d]
    return (p[0] + dx * n, p[1] + dy * n)


def nb4(p):
    return [step(p, d) for d in CARD]


def nb8(p):
    return [(p[0] + dx, p[1] + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy]


class Room:
    def __init__(self, rid, **attrs):
        self.id = rid
        self.tiles = set()
        self.attrs = attrs

    def __repr__(self):
        return "Room(%s, %d tiles)" % (self.id, len(self.tiles))


class Geo:
    """Tiles with attributes. `kind` says what a zone tile is; `room` whose floor it is; `attr[name]` holds the fields
    nodes compute; `cells` the pieces placed on a tile; `taken` why a floor tile is not free."""

    def __init__(self):
        self.base = None        # the map the outline was read from (shared, never copied)
        self.zone = set()
        self.kind = {}          # ring / keep_door / keep_open / free, then wall / floor / door / glass
        self.room = {}          # floor tile -> room id
        self.rooms = {}         # room id -> Room
        self.attr = {}          # field name -> {tile: value}
        self.doors = {}         # door tile -> dict(rooms=(a, b), spec=..., keep=bool)
        self.raw = {}           # stamped tile -> (room id, spec, backing): a prefab module's walls, locks, floors
        self.cells = {}         # tile -> [spec dict, ...] (obj / decal / floor / mount)
        self.taken = {}         # floor tile -> "obj" | "open" | "use"
        self.placed = []        # (kit name, room id, origin, wall dir, mirrored, [tiles])
        self.notes = []
        self.problems = []
        self._out = {}

    def clone(self):
        base, self.base = self.base, None
        out_cache, self._out = self._out, {}
        g = copy.deepcopy(self)
        self.base = g.base = base
        self._out = g._out = out_cache
        return g

    # ---- what lies outside the zone
    def outside(self, p):
        """hall / maint / space / wall / door / glass for a tile that is not ours."""
        if p in self._out:
            return self._out[p]
        t = self.base.get(*p) if self.base is not None else None
        if t is None or t.tpath.startswith("/turf/closed"):
            r = "wall"
        elif t.has("/obj/machinery/door"):
            r = "door"
        elif t.has("/obj/effect/spawner/structure/window") or t.has("/obj/structure/grille") or t.has("/obj/structure/window"):
            r = "glass"
        elif t.tpath.startswith("/turf/open/space"):
            r = "space"
        elif "maintenance" in t.apath:
            r = "maint"
        else:
            r = "hall"
        self._out[p] = r
        return r

    def what(self, p):
        """Kind of any tile: ours by `kind`, others by outside()."""
        return self.kind[p] if p in self.zone else self.outside(p)

    def solid(self, p):
        w = self.what(p)
        return w in SOLID if p in self.zone else w == "wall"

    def blocked(self, p):
        """Wall, glass or door: something a wall line can join onto."""
        w = self.what(p)
        return w in BARRIER if p in self.zone else w in ("wall", "glass", "door")

    def walk(self, p):
        """Open to walk on: our floor, or open ground outside."""
        if p in self.zone:
            return self.kind[p] in ("floor", "keep_open")
        return self.outside(p) in ("hall", "maint", "space")

    def beyond(self, p):
        """What a wall tile stands between is read from here: the room id of a floor tile, or the outside class."""
        if p in self.zone:
            if self.kind[p] == "keep_open":
                return "keep"
            return self.room.get(p) if self.kind[p] == "floor" else None
        o = self.outside(p)
        return o if o in ("hall", "maint", "space") else None

    def field(self, name):
        return self.attr.setdefault(name, {})

    def bounds(self, pad=0):
        xs = [p[0] for p in self.zone]
        ys = [p[1] for p in self.zone]
        return min(xs) - pad, min(ys) - pad, max(xs) + pad, max(ys) + pad

    def problem(self, text):
        if text not in self.problems:
            self.problems.append(text)


class Graph:
    """An ordered chain of nodes. run() keeps every node's output so each can be drawn."""

    def __init__(self, name, **params):
        self.name = name
        self.P = params
        self.nodes = []
        self.snap = {}

    def add(self, name, fn, view="rooms", **kw):
        self.nodes.append((name, fn, view, kw))
        return self

    def run(self):
        geo = Geo()
        for name, fn, view, kw in self.nodes:
            geo = geo.clone()
            fn(geo, self.P, **kw)
            self.snap[name] = geo
        self.geo = geo
        return geo

    def pictures(self, outdir, tile=16):
        os.makedirs(outdir, exist_ok=True)
        paths = []
        for i, (name, fn, view, kw) in enumerate(self.nodes):
            path = os.path.join(outdir, "%s_%d_%s.png" % (self.name, i + 1, name))
            draw(self.snap[name], view, path, tile=tile, title="%d. %s" % (i + 1, name))
            paths.append(path)
        return paths


# ---------------------------------------------------------------------------------------------------- drawing
OUT_COL = {"hall": (196, 198, 204), "maint": (112, 104, 96), "space": (12, 12, 24), "wall": (58, 58, 64),
           "door": (150, 112, 60), "glass": (86, 130, 160)}
KIND_COL = {"ring": (34, 34, 42), "keep_door": (236, 150, 36), "keep_open": (232, 206, 130), "free": (238, 238, 238),
            "wall": (74, 74, 86), "raw": (150, 70, 70), "door": (246, 138, 26), "glass": (112, 204, 238), "floor": (220, 220, 220)}
PALETTE = [(244, 196, 196), (196, 222, 244), (204, 240, 200), (248, 232, 180), (226, 204, 244), (184, 236, 228),
           (250, 212, 170), (212, 216, 252), (236, 246, 180), (248, 200, 226), (200, 232, 208), (222, 222, 196)]
HALL_COL = (236, 236, 240)


def room_colour(geo, rid):
    r = geo.rooms.get(rid)
    if r is not None and r.attrs.get("hall"):
        return HALL_COL
    ids = sorted(k for k, v in geo.rooms.items() if not v.attrs.get("hall"))
    return PALETTE[ids.index(rid) % len(PALETTE)] if rid in ids else (220, 220, 220)


def draw(geo, view, path, tile=16, title=None, pad=3):
    from PIL import Image, ImageDraw, ImageFont
    x0, y0, x1, y1 = geo.bounds(pad)
    T = tile
    head = 22 if title else 0
    img = Image.new("RGB", ((x1 - x0 + 1) * T, (y1 - y0 + 1) * T + head), (24, 24, 28))
    d = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("arialbd.ttf", max(9, T * 2 // 3))
        small = ImageFont.truetype("arial.ttf", max(8, T // 2 + 1))
    except OSError:
        font = small = ImageFont.load_default()

    def box(p):
        left, top = (p[0] - x0) * T, (y1 - p[1]) * T + head
        return [left, top, left + T - 1, top + T - 1]

    for x in range(x0, x1 + 1):
        for y in range(y0, y1 + 1):
            p = (x, y)
            if p in geo.zone:
                k = geo.kind[p]
                col = KIND_COL.get(k, (255, 0, 255))
                if k == "floor" and view != "kind":
                    col = room_colour(geo, geo.room.get(p))
            else:
                col = tuple(c * 6 // 10 for c in OUT_COL[geo.outside(p)])
            d.rectangle(box(p), fill=col)
            if p in geo.zone and geo.kind[p] in ("floor", "free", "keep_open"):
                d.rectangle(box(p), outline=tuple(max(0, c - 22) for c in col))

    if view == "fields":
        lane, front, alc = geo.field("lane"), geo.field("front"), geo.field("alcove")
        back = geo.field("back")
        for p in geo.zone:
            b = box(p)
            if p in lane:
                d.rectangle([b[0] + T // 3, b[1] + T // 3, b[2] - T // 3, b[3] - T // 3], fill=(60, 110, 230))
            if p in front:
                d.rectangle([b[0] + 2, b[1] + 2, b[2] - 2, b[3] - 2], outline=(240, 170, 0), width=2)
            if p in alc:
                d.rectangle([b[0] + 2, b[1] + 2, b[2] - 2, b[3] - 2], outline=(220, 40, 200), width=2)
            for dr, how in back.get(p, {}).items():
                col = {"wall": (40, 40, 40), "glass": (0, 150, 210), "door": (240, 130, 20)}[how]
                if dr == N:
                    d.line([b[0] + 3, b[1] + 1, b[2] - 3, b[1] + 1], fill=col, width=2)
                elif dr == S:
                    d.line([b[0] + 3, b[3] - 1, b[2] - 3, b[3] - 1], fill=col, width=2)
                elif dr == E:
                    d.line([b[2] - 1, b[1] + 3, b[2] - 1, b[3] - 3], fill=col, width=2)
                else:
                    d.line([b[0] + 1, b[1] + 3, b[0] + 1, b[3] - 3], fill=col, width=2)

    if view == "items":
        for p, why in geo.taken.items():
            b = box(p)
            if why == "use":
                d.ellipse([b[0] + T // 3, b[1] + T // 3, b[2] - T // 3, b[3] - T // 3], fill=(30, 160, 60))
            elif why == "open":
                d.rectangle([b[0] + 2, b[1] + 2, b[2] - 2, b[3] - 2], outline=(200, 150, 0), width=2)
        for p, cells in geo.cells.items():
            b = box(p)
            tint = None
            for c in cells:
                if c.get("floor"):
                    tint = (150, 150, 158) if "dark" in str(c["floor"]) else (176, 170, 150) if "engine" in str(c["floor"]) \
                        else (196, 150, 150) if "carpet" in str(c["floor"]) else None
            if tint:
                d.rectangle(box(p), fill=tint, outline=tuple(c - 20 for c in tint))
            if any(c.get("decal") for c in cells):
                d.rectangle([b[0] + 1, b[1] + 1, b[2] - 1, b[3] - 1], outline=(214, 170, 0))
            label = None
            for c in cells:
                if c.get("label") and (c.get("obj") or not label):
                    label = c["label"]
            if label and geo.taken.get(p) == "obj":
                d.rectangle([b[0] + 1, b[1] + 1, b[2] - 1, b[3] - 1], fill=(52, 60, 84))
                d.text((b[0] + 2, b[1] + 1), label[:2], fill=(255, 255, 255), font=small)
            elif label:
                d.text((b[0] + 2, b[1] + 1), label[:2], fill=(40, 40, 40), font=small)
        for p in geo.field("lane"):
            if p not in geo.taken:
                b = box(p)
                d.rectangle([b[0] + T * 2 // 5, b[1] + T * 2 // 5, b[2] - T * 2 // 5, b[3] - T * 2 // 5], fill=(120, 150, 240))

    if view != "kind":
        for rid, r in geo.rooms.items():
            if not r.tiles:
                continue
            cx = sum(p[0] for p in r.tiles) / len(r.tiles)
            cy = sum(p[1] for p in r.tiles) / len(r.tiles)
            c = min(r.tiles, key=lambda p: (p[0] - cx) ** 2 + (p[1] - cy) ** 2)
            b = box(c)
            if view in ("rooms", "fields"):
                text = r.attrs.get("label", rid)
                d.text((b[0] - len(text) * T // 6, b[1]), text, fill=(20, 20, 30), font=font)
    if title:
        d.rectangle([0, 0, img.width, head - 1], fill=(24, 24, 28))
        d.text((6, 2), title, fill=(255, 255, 255), font=font)
    img.save(path)
    return path


def sheet(paths, out, cols=3):
    from PIL import Image
    ims = [Image.open(p) for p in paths]
    w, h = max(i.width for i in ims), max(i.height for i in ims)
    rows = (len(ims) + cols - 1) // cols
    big = Image.new("RGB", (cols * w + (cols + 1) * 8, rows * h + (rows + 1) * 8), (12, 12, 14))
    for i, im in enumerate(ims):
        big.paste(im, (8 + (i % cols) * (w + 8), 8 + (i // cols) * (h + 8)))
    big.save(out)
    return out
