"""Disposal pipes the way the game sees them (code/modules/recycling/disposal/pipe.dm).

dpdir(atom): the connection bitmask of a disposal pipe atom:
    segment            dir | flip(dir)            (a diagonal dir is a bend: both bits already)
    junction           dir | right(dir) | flip    junction/flip: dir | left | flip; junction/yjunction: left | right
    sorting/*          like junction (and /flip like junction/flip)
    trunk              dir
Flow: a holder keeps its direction along segments; at a junction it leaves by the primary dir unless it came in
through the primary side (then a random secondary). A trunk under a bin starts items in the trunk's dir.

trace(m, start) walks a network from a tile; route(...) lays a tree of pipes (see build.Builder.route_disposals).
"""
from forge import dmm

N, S, E, W = 1, 2, 4, 8
DELTA = {N: (0, 1), S: (0, -1), E: (1, 0), W: (-1, 0)}
OPP = {N: S, S: N, E: W, W: E}
CW = {N: E, E: S, S: W, W: N}   # turn(dir, -90): clockwise
CCW = {N: W, W: S, S: E, E: N}  # turn(dir, 90)

PIPE = "/obj/structure/disposalpipe"


def is_disposal(a):
    return a.path.startswith(PIPE)


def dpdir(a):
    p = a.path
    d = a.num("dir", 2)
    if not p.startswith(PIPE) or "/broken" in p:
        return 0
    if p.startswith(PIPE + "/trunk"):
        return d
    if p.startswith(PIPE + "/segment"):
        if d in (N, S, E, W):
            return d | OPP[d]
        return d  # bent
    if p.startswith(PIPE + "/junction/yjunction"):
        return CCW[d] | CW[d]
    flip = p.endswith("/flip") or "/flip" in p
    if p.startswith(PIPE + "/junction") or p.startswith(PIPE + "/sorting"):
        if d not in (N, S, E, W):
            return 0
        return d | (CCW[d] if flip else CW[d]) | OPP[d]
    return 0


def mask_at(t):
    return sum(dpdir(a) for a in t.objs if is_disposal(a)) if t else 0


def neighbours(m, p):
    """Tiles p's disposal pipe connects to (both sides must point at each other)."""
    t = m.get(*p)
    mk = mask_at(t)
    out = []
    for d, (dx, dy) in DELTA.items():
        if mk & d:
            q = (p[0] + dx, p[1] + dy)
            if mask_at(m.get(*q)) & OPP[d]:
                out.append((q, d))
    return out


def component(m, start, limit=4000):
    seen, q = {start}, [start]
    while q and len(seen) < limit:
        p = q.pop()
        for n, d in neighbours(m, p):
            if n not in seen:
                seen.add(n)
                q.append(n)
    return seen


def segment_atom(mask):
    """Pipe atom text joining exactly the sides in mask (2 sides)."""
    if mask in (N | S,):
        return "/obj/structure/disposalpipe/segment"
    if mask == E | W:
        return "/obj/structure/disposalpipe/segment{dir = 4}"
    return "/obj/structure/disposalpipe/segment{dir = %d}" % mask  # bend: dir is the two bits


def junction_atom(primary, other):
    """A junction whose primary (outflow) side is `primary`, its flip side opposite, and a branch on `other`."""
    if other == CW[primary]:
        return "/obj/structure/disposalpipe/junction" + ("{dir = %d}" % primary if primary != S else "")
    if other == CCW[primary]:
        return "/obj/structure/disposalpipe/junction/flip" + ("{dir = %d}" % primary if primary != S else "")
    return None


def trunk_atom(d):
    return "/obj/structure/disposalpipe/trunk" + ("{dir = %d}" % d if d != S else "")


def piece(t, entering=None):
    """The pipe on a tile; with `entering` (the side a holder comes in by), the one that accepts it (two pipes
    can cross on one tile)."""
    for a in t.objs if t else []:
        if is_disposal(a) and dpdir(a) and (entering is None or dpdir(a) & entering):
            return a
    return None


def next_dir(a, hdir):
    """The game's nextdir for a holder moving in hdir that has just entered pipe a. None = stops here."""
    p = a.path
    mk = dpdir(a)
    back = OPP.get(hdir, 0)
    if p.startswith(PIPE + "/trunk"):
        return None
    if p.startswith(PIPE + "/sorting"):
        return a.num("dir", 2)  # untagged trash goes with the flow
    if p.startswith(PIPE + "/junction"):
        d = a.num("dir", 2)
        if back != d:
            return d
        return [x for x in (N, E, S, W) if mk & x and x != d][0]  # one of the secondaries (random in game)
    rest = mk & ~back
    return rest if rest in (N, S, E, W) else None


def flow(m, start_tile, start_dir, limit=3000):
    """Follow a holder from start_tile moving start_dir; returns [(tile, dir it leaves by)] until it stops."""
    out = []
    p, h = start_tile, start_dir
    for _ in range(limit):
        out.append((p, h))
        q = (p[0] + DELTA[h][0], p[1] + DELTA[h][1])
        a = piece(m.get(*q), OPP[h])
        if a is None:
            out.append((q, None))
            return out
        nd = next_dir(a, h)
        if nd is None:
            out.append((q, None))
            return out
        p, h = q, nd
    return out
