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
        if "/simple" in p:
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
    return [o for o in (t.objs if t else []) if o.path.startswith(PREFIX) and mask(o)]


def joins(a, b, d):
    """a at some tile, b at its neighbour in direction d."""
    if not (mask(a) & d and mask(b) & OPP[d]):
        return False
    if ("heat_exchanging" in a.path) != ("heat_exchanging" in b.path):
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
