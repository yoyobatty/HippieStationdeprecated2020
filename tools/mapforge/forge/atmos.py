"""Atmospherics connections the way the 2020 game makes them, for any pipe or device (not just distro/scrubbers).

Two neighbouring atoms join when both point at each other and share a piping layer (1, 2 default, 3); a
layer_manifold joins all layers along its axis. Heat exchange pipes only join heat exchange pipes.

check(m, tiles) -> problems: open ends, and networks that mix the station's scrubbers with another loop (a
scrubber pipe on layer 2 touching a toxins loop would drain it into the station's waste).
"""
N, S, E, W = 1, 2, 4, 8
DELTA = {N: (0, 1), S: (0, -1), E: (1, 0), W: (-1, 0)}
OPP = {N: S, S: N, E: W, W: E}
TRINARY = {N: E | N | S, S: S | W | N, E: E | W | S, W: W | N | E}
PREFIX = "/obj/machinery/atmospherics"


def layer(a):
    v = a.get("piping_layer")
    if v is not None and v.strip().isdigit():
        return int(v)
    if "/layer1" in a.path:
        return 1
    if "/layer3" in a.path:
        return 3
    return 2


def mask(a):
    p = a.path
    if not p.startswith(PREFIX):
        return 0
    d = a.num("dir", 2)
    if "/layer_manifold" in p:
        return (N | S) if d in (N, S) else (E | W)
    if "/pipe/" in p:
        if "/manifold4w" in p:
            return 15
        if "/manifold" in p:
            return 15 & ~d
        if "/simple" in p or "/junction" in p:
            if d in (N, S):
                return N | S
            if d in (E, W):
                return E | W
            return d
        return 0
    if "/components/unary" in p:
        return d
    if "/components/binary" in p:
        return (N | S) if d in (N, S) else (E | W)
    if "/components/trinary" in p:
        return TRINARY.get(d, 0)
    return 0


def kind(a):
    """Network family: 'he' (heat exchange), 'scrubbers', 'supply', or 'other' (any other loop)."""
    p = a.path
    if "heat_exchanging" in p:
        return "he"
    if "scrubber" in p:
        return "scrubbers"
    if "/supply/" in p or "vent_pump" in p and "/layer1" in p:
        return "supply"
    return "other"


def atoms(t):
    # machines (not pipes) mapped on a crate's tile start packed inside it (a TEG kit), not laid
    packed = bool(t) and any(o.path.startswith("/obj/structure/closet/crate") for o in t.objs)
    return [o for o in (t.objs if t else []) if o.path.startswith(PREFIX) and mask(o)
            and not (packed and "/components/" in o.path)]


def joins(a, b, d):
    """a at some tile, b at its neighbour in direction d."""
    if not (mask(a) & d and mask(b) & OPP[d]):
        return False
    def he_side(x, toward):
        # a junction is heat exchange on the side it faces and plain pipe behind it (junction.dm isConnectable)
        if "/heat_exchanging/junction" in x.path:
            return toward == x.num("dir", 2)
        return "heat_exchanging" in x.path
    if he_side(a, d) != he_side(b, OPP[d]):
        return False
    la = "/layer_manifold" in a.path
    lb = "/layer_manifold" in b.path
    return la or lb or layer(a) == layer(b)


def check(m, tiles, ignore=lambda p, a: False):
    probs = []
    nodes = {}
    for p in tiles:
        for i, a in enumerate(atoms(m.get(*p))):
            nodes[(p, i)] = a
    parent = {k: k for k in nodes}

    def find(k):
        while parent[k] != k:
            parent[k] = parent[parent[k]]
            k = parent[k]
        return k
    for (p, i), a in nodes.items():
        for d, (dx, dy) in DELTA.items():
            if not mask(a) & d:
                continue
            q = (p[0] + dx, p[1] + dy)
            partners = [(j, b) for j, b in enumerate(atoms(m.get(*q))) if joins(a, b, d)]
            if not partners:
                if not ignore(p, a):
                    probs.append("open %s end at %d,%d facing %s (%s)" % (kind(a), p[0], p[1],
                                                                          {1: "north", 2: "south", 4: "east", 8: "west"}[d],
                                                                          a.path.rsplit("/", 1)[-1]))
                continue
            for j, b in partners:
                if (q, j) in parent:
                    parent[find((p, i))] = find((q, j))
                # plain pipe to plain pipe between the station scrubbers and another loop: a leak, not a design
                # (a pump or valve between them is how a loop is meant to dump waste into the scrubbers)
                ka, kb = kind(a), kind(b)
                if {ka, kb} == {"scrubbers", "other"} and "/pipe/" in a.path and "/pipe/" in b.path and p < q:
                    probs.append("station scrubbers pipe joins another loop directly at %d,%d / %d,%d" % (p[0], p[1], q[0], q[1]))
    return probs


# ------------------------------------------------------------------------------------------------ render pre-pass
# The game draws a device's pipe stubs at runtime (components_base.dm update_icon: a "pipe_intact" underlay from
# binary_devices.dmi toward each node it joined, coloured like that node's pipe, "pipe_exposed" toward a side with
# nothing) and shifts a layer-1/3 device 5 px (PIPING_LAYER_SHIFT). dmm-tools draws only the map's static sprites, so
# a picture showed every device cut off from its pipes (the user 2026-11-22: "gaps in the renderer, showing pipes and
# things that should connect as not joined"). render_prep() writes those stubs and shifts into a copy of the map
# before forge/render.py renders it, with the same join rules as check(): what the picture shows joined is joined.
PIPE_COLORS = {"yellow": "#ffc600", "cyan": "#00fff9", "green": "#1eff00", "orange": "#ff8119", "purple": "#8000b6",
               "dark": "#454545", "brown": "#b26438", "violet": "#400080", "scrubbers": "#ff0000", "supply": "#0000ff",
               "supplymain": "#822bff"}
STUB_ICON = "'icons/obj/atmospherics/components/binary_devices.dmi'"
LEVEL1 = ("/vent_pump", "/vent_scrubber", "/outlet_injector", "/dp_vent_pump")     # level = 1 in their .dm files


def pipe_color(a):
    if "/pipe/" not in a.path:
        return None
    parts = a.path.split("/")
    for c in PIPE_COLORS:
        if c in parts:
            return PIPE_COLORS[c]
    return None


def render_prep(m):
    """Stubs and layer shifts for every atmos component on the map (in place); returns how many stubs were drawn."""
    from forge import dmm
    n = 0
    for (x, y, z), t in list(m.tiles.items()):
        # components_base.dm update_icon: stubs only when the device is level 2 or its turf isn't intact (plating,
        # space); vents, scrubbers and injectors are level 1, so on a floor tile they show none (the user 2026-11-22:
        # "the vents show the stubs above the floor")
        intact = t.tpath.startswith("/turf/open/floor") and not t.tpath.startswith("/turf/open/floor/plating")
        for a in [o for o in t.objs if o.path.startswith(PREFIX + "/components/") and mask(o)]:
            lvl = a.num("level", 1 if any(k in a.path for k in LEVEL1) else 2)
            if lvl == 1 and intact:
                continue
            d0 = a.num("dir", 2)
            lay = layer(a)
            px = py = 0
            if lay != 2:
                if d0 & (N | S):
                    px = (lay - 2) * 5
                if d0 & (E | W):
                    py = (lay - 2) * 5
                a.vars = [(k, v) for k, v in a.vars if k not in ("pixel_x", "pixel_y")] + \
                    ([("pixel_x", str(px))] if px else []) + ([("pixel_y", str(py))] if py else [])
            for d, (dx, dy) in DELTA.items():
                if not mask(a) & d:
                    continue
                nt = m.get(x + dx, y + dy, z)
                partner = next((b for b in atoms(nt) if joins(a, b, d)), None) if nt else None
                vs = [("icon", STUB_ICON), ("icon_state", '"%s"' % ("pipe_intact" if partner else "pipe_exposed")),
                      ("dir", str(d)), ("layer", "2.4"), ("name", '"pipe stub"')]
                col = pipe_color(partner) if partner else None
                if col:
                    vs.append(("color", '"%s"' % col))
                if px:
                    vs.append(("pixel_x", str(px)))
                if py:
                    vs.append(("pixel_y", str(py)))
                t.objs.insert(0, dmm.Atom("/obj/effect/overlay", vs))
                n += 1
    return n


def hidden_breaks(m, z=1):
    """Joins where a pipe shown on the map meets one hidden under an intact floor tile: a visible line that seems to
    stop dead (the user 2026-11-22: "the sudden hidden pipes look weird, make sure that's not a pattern"). A pipe
    (or layer manifold) is hidden when its level is 1 (hidden types; pipes.dm level = 1, the /visible ones 2) and its
    turf is intact floor; devices always show. Going into a wall is fine: the line ends at the wall."""
    def intact(t):
        return t is not None and t.tpath.startswith("/turf/open/floor") and not t.tpath.startswith("/turf/open/floor/plating")

    def shown(a, t):
        if "/pipe/" not in a.path:
            # devices draw their stubs when level 2 (pumps, filters, connectors); vents and injectors are level 1 and
            # show none on a floor tile (components_base.dm)
            return not (any(k in a.path for k in LEVEL1) and a.num("level", 1) == 1 and intact(t))
        lvl = a.num("level", 2 if "/visible" in a.path else 1)
        return lvl == 2 or not intact(t)
    out = []
    for (x, y, zz), t in m.tiles.items():
        if zz != z:
            continue
        for a in atoms(t):
            # the line that stops: a visible pipe or a level-2 device (a hidden pipe seen on plating going under a
            # floor tile is every maint doorway on every stock map)
            if not shown(a, t) or ("/pipe/" in a.path and a.num("level", 2 if "/visible" in a.path else 1) != 2)                     or ("/pipe/" not in a.path and any(k in a.path for k in LEVEL1)):
                continue
            for d, (dx, dy) in DELTA.items():
                nt = m.get(x + dx, y + dy, z)
                for b in atoms(nt) if nt else []:
                    # a door tile is a threshold, as a wall is: the line may end at it
                    if "/pipe/" in b.path and joins(a, b, d) and not shown(b, nt) and intact(nt)                             and not nt.has("/obj/machinery/door"):
                        out.append(((x, y), (x + dx, y + dy), b.path.rsplit("/", 2)[-2] + "/" + b.path.rsplit("/", 1)[-1]))
    return out
