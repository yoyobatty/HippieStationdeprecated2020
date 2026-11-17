"""Mapping conventions for this codebase: typepaths, wall-mount offsets, pipe and cable forms.

Wall-mount offsets are the majority values mined from hippiestation.dmm + MetaStation.dmm (see corpus notes in
README.md): for a floor tile whose wall is on side W, MOUNT[kind][W] gives (dir, pixel_x, pixel_y).
"""
N, S, E, W = 1, 2, 4, 8
CARD = (N, S, E, W)
DELTA = {N: (0, 1), S: (0, -1), E: (1, 0), W: (-1, 0)}
OPP = {N: S, S: N, E: W, W: E}
NAME = {N: "north", S: "south", E: "east", W: "west"}

WALL = "/turf/closed/wall"
RWALL = "/turf/closed/wall/r_wall"
PLATING = "/turf/open/floor/plating"
WINDOW = "/obj/effect/spawner/structure/window"
RWINDOW = "/obj/effect/spawner/structure/window/reinforced"
FIREDOOR = "/obj/machinery/door/firedoor"

# kind -> wall side -> (dir, pixel_x, pixel_y); None = leave the var out
MOUNT = {
    "apc": {N: (1, None, 23), S: (None, None, -23), E: (4, 24, None), W: (8, -25, None)},
    "airalarm": {N: (None, None, 23), S: (1, None, -22), E: (8, 24, None), W: (4, -22, None)},
    "firealarm": {N: (None, None, 24), S: (1, None, -24), E: (8, 24, None), W: (4, -24, None)},
    "light_switch": {N: (None, None, 28), S: (None, None, -25), E: (None, 27, None), W: (None, -23, None)},
    "extinguisher": {N: (None, None, 30), S: (None, None, -30), E: (None, 27, None), W: (None, -27, None)},
    "newscaster": {N: (None, None, 32), S: (None, None, -32), E: (None, 30, None), W: (None, -30, None)},
    "intercom": {N: (None, None, 21), S: (None, None, -29), E: (None, 29, None), W: (None, -30, None)},
    "requests_console": {N: (None, None, 30), S: (None, None, -30), E: (None, 30, None), W: (None, -30, None)},
    "status_display": {N: (None, None, 32), S: (None, None, -32), E: (None, 32, None), W: (None, -32, None)},
    "noticeboard": {N: (None, None, 32), S: (1, None, -27), E: (8, 27, None), W: (4, -27, None)},
    "mirror": {N: (None, None, 28), S: (None, None, -28), E: (None, 28, None), W: (None, -28, None)},
    "camera": {N: (2, None, None), S: (1, None, None), E: (8, None, None), W: (4, None, None)},
    "light": {N: (1, None, None), S: (None, None, None), E: (4, None, None), W: (8, None, None)},
    "sign": {N: (None, None, 32), S: (None, None, -32), E: (None, 32, None), W: (None, -32, None)},
    "button": {N: (None, None, 25), S: (None, None, -24), E: (None, 25, None), W: (None, -25, None)},
    "sink": {N: (None, None, 30), S: (1, None, -8), E: (4, 12, None), W: (8, -12, None)},
    "telescreen": {N: (None, None, 32), S: (None, None, -32), E: (None, 32, None), W: (None, -31, None)},
    "wallmed": {N: (None, None, 32), S: (None, None, -32), E: (None, 27, None), W: (None, -27, None)},
}

MOUNT_PATHS = {
    "apc": "/obj/machinery/power/apc",
    "airalarm": "/obj/machinery/airalarm",
    "firealarm": "/obj/machinery/firealarm",
    "light_switch": "/obj/machinery/light_switch",
    "extinguisher": "/obj/structure/extinguisher_cabinet",
    "newscaster": "/obj/machinery/newscaster",
    "intercom": "/obj/item/radio/intercom",
    "camera": "/obj/machinery/camera",
    "light": "/obj/machinery/light",
    "requests_console": "/obj/machinery/requests_console",
}


def mount_vars(kind, side, extra=None):
    d, px, py = MOUNT[kind][side]
    vs = []
    if d is not None:
        vs.append(("dir", str(d)))
    if px is not None:
        vs.append(("pixel_x", str(px)))
    if py is not None:
        vs.append(("pixel_y", str(py)))
    if extra:
        vs = [(k, v) for k, v in extra] + vs if isinstance(extra, list) else vs
    return vs


# pipes: class -> (simple, manifold, manifold4w, vent)
PIPES = {
    "supply": ("/obj/machinery/atmospherics/pipe/simple/supply/hidden/layer1",
               "/obj/machinery/atmospherics/pipe/manifold/supply/hidden/layer1",
               "/obj/machinery/atmospherics/pipe/manifold4w/supply/hidden/layer1",
               "/obj/machinery/atmospherics/components/unary/vent_pump/on/layer1"),
    "scrubbers": ("/obj/machinery/atmospherics/pipe/simple/scrubbers/hidden",
                  "/obj/machinery/atmospherics/pipe/manifold/scrubbers/hidden",
                  "/obj/machinery/atmospherics/pipe/manifold4w/scrubbers/hidden",
                  "/obj/machinery/atmospherics/components/unary/vent_scrubber/on"),
}


def pipe_class(path):
    """Network class of a pipe-ish atom, or None."""
    if "/atmospherics/" not in path:
        return None
    if "vent_pump" in path and "layer1" in path:
        return "supply"
    if "vent_scrubber" in path:
        return "scrubbers"
    if "/pipe/" in path and "/supply/" in path and "layer1" in path:
        return "supply"
    if "/pipe/" in path and "/scrubbers/" in path and "layer" not in path.rsplit("/", 1)[-1]:
        return "scrubbers"
    return None


def pipe_mask(atom):
    """Connection bitmask of a pipe atom (simple/manifold/4w/unary)."""
    p = atom.path
    d = atom.num("dir", 2)
    if "/manifold4w/" in p:
        return 15
    if "/manifold/" in p:
        return 15 & ~d
    if "/pipe/simple/" in p or "/heat_exchanging/simple" in p:
        if d in (1, 2):
            return N | S
        if d in (4, 8):
            return E | W
        return d
    if "/components/unary/" in p:
        return d
    return 0


def pipe_atom(cls, mask):
    simple, manifold, four, _ = PIPES[cls]
    bits = bin(mask).count("1")
    if bits == 4:
        return (four, [])
    if bits == 3:
        d = 15 & ~mask
        return (manifold, [("dir", str(d))] if d != 2 else [])
    if mask == N | S:
        return (simple, [])
    if mask == E | W:
        return (simple, [("dir", "4")])
    if bits == 2:
        return (simple, [("dir", str(mask))])
    # dead end: a straight stub pointing that way
    if mask in (N, S):
        return (simple, [])
    return (simple, [("dir", "4")])


CABLE = "/obj/structure/cable"


def is_cable(atom):
    """Layer-2 station cable (layer1/layer3 cables are separate networks)."""
    return atom.path == CABLE
DISPOSAL_PREFIX = ("/obj/structure/disposalpipe", "/obj/machinery/disposal")

# objects that block walking (furniture placement / vent placement avoid these)
DENSE_HINTS = ("/obj/structure/table", "/obj/machinery/vending", "/obj/structure/closet", "/obj/machinery/hydroponics",
               "/obj/machinery/computer", "/obj/machinery/chem", "/obj/machinery/disposal/bin", "/obj/structure/piano",
               "/obj/machinery/smartfridge", "/obj/machinery/biogenerator", "/obj/machinery/seed_extractor",
               "/obj/machinery/plantgenes", "/obj/structure/reagent_dispensers", "/obj/machinery/deepfryer",
               "/obj/machinery/grill", "/obj/machinery/processor", "/obj/machinery/gibber", "/obj/machinery/icecream_vat",
               "/obj/structure/kitchenspike", "/obj/structure/dresser", "/obj/machinery/food_cart", "/obj/structure/bookcase",
               "/obj/machinery/microwave", "/obj/structure/window", "/obj/machinery/rnd", "/obj/structure/beebox",
               "/obj/machinery/oven", "/obj/structure/flora", "/obj/machinery/griddle", "/obj/structure/rack",
               "/obj/machinery/door", "/obj/structure/plasticflaps", "/obj/machinery/holopad")


NOT_DENSE = ("/obj/machinery/computer/security/telescreen",)


_DENSE = None


def dense_types():
    """Every /obj/structure and /obj/machinery type that starts dense in the game (smooth_dump.sh), or None."""
    global _DENSE
    if _DENSE is None:
        import os
        p = os.path.join(os.path.dirname(__file__), "..", "..", "..", "data", "mapforge", "smoothing.txt")
        _DENSE = set()
        if os.path.exists(p):
            for line in open(p, encoding="utf-8", errors="replace"):
                if line.startswith("D\t"):
                    _DENSE.add(line.rstrip("\n").split("\t")[1])
    return _DENSE or None


def is_dense_atom(a):
    if a.path.startswith(NOT_DENSE + ("/obj/structure/railing", "/obj/machinery/door")):
        return False
    # the gateway frame's bottom row is open (Initialize() drops density facing S, SE, SW): you walk in from there
    if a.path == "/obj/machinery/gateway" and a.num("dir", 2) in (2, 6, 10):
        return False
    d = a.get("density")
    if d is not None:
        return d.strip() not in ("0", "FALSE")
    types = dense_types()
    if types is not None:
        return a.path in types
    return a.path.startswith(DENSE_HINTS)


def dense(atoms):
    return any(is_dense_atom(a) for a in atoms)
