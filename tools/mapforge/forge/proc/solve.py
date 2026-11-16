"""The plan solver: a room list in, slicing trees out.

Fixed streets and halls cut a department into blocks. The solver decides which rooms go in which block and how each
block is cut. Per block it tries every ordering of its rooms and every way to cut them (a beam keeps the best few of
each part), and scores the whole:

    frontage   a room that needs a street, the public hall or a ward must have a wall on one, wide enough for a
               door: a block edge of that kind, or a room of the plan that provides it (a hall piece)
    links      rooms with a door between them share a wall
    anchors    a room tied to something the outline fixes (launch shutters, a chute, a vent pocket) must contain it
    size       close to its target area, no thinner than its minimum, not a corridor-shaped sliver
    friends    rooms that work together share a wall (a bonus, not a rule)

A seed adds a little noise to every finished block plan, so plans that score about the same trade places between
seeds while a plan that breaks a rule never wins. seed=None is the plain best.

It knows nothing about furniture. It hands back trees for shell.slice_rooms; the rest of the graph judges them
(an asset that cannot fit its kits says so).
"""
import copy
import itertools
import random

from .shell import X, Y

RULE = 1000.0       # a broken rule: frontage, a link, an anchor
NOISE = 45.0        # the most a seed adds to a block plan


class Want:
    """One room of the program."""

    def __init__(self, rid, area, min=(3, 3), front=("street",), anchors=(), near=(), expand=None, fixed=None,
                 provides=(), node=None, corridor=False):
        self.id = rid
        self.area = area            # target floor tiles
        self.min = min              # smallest (short side, long side) it works in
        self.front = front          # the kinds of frontage it needs a door onto: "street", "hall", ...
        self.anchors = anchors      # tiles it must contain
        self.near = near            # rooms it wants to share a wall with
        self.expand = expand        # fn(w, h) -> subtree, for a room that carries sub-rooms of its own
        self.fixed = fixed          # {"w": n} / {"h": n}: a side the outline dictates
        self.provides = provides    # frontage kinds this room gives the rooms beside it (a hall piece: "hall")
        self.node = node or rid     # the room id it lays down (hall pieces of one hall share it)
        self.corridor = corridor    # long and thin is right for it


class Block:
    """A rectangle of free floor between fixed halls. fronts: {side: (kind, lo, hi)} or {side: [(kind, lo, hi), ...]}
    with side in "nsew" and lo..hi the stretch of that side (x for n/s, y for e/w) that really borders it."""

    def __init__(self, name, rect, fronts):
        self.name, self.rect = name, rect
        self.fronts = {s: (v if isinstance(v, list) else [v]) for s, v in fronts.items()}

    @property
    def area(self):
        x0, y0, x1, y1 = self.rect
        return (x1 - x0 + 1) * (y1 - y0 + 1)

    def kinds(self):
        return {k for v in self.fronts.values() for k, _, _ in v}


def _edge_kinds(block, rect):
    """Frontage kinds this rect gets from the block's own edges (two tiles of wall at least, for a door)."""
    x0, y0, x1, y1 = rect
    bx0, by0, bx1, by1 = block.rect
    out = set()
    for side, spans in block.fronts.items():
        for k, lo, hi in spans:
            if side == "n" and y1 == by1 or side == "s" and y0 == by0:
                if min(x1, hi) - max(x0, lo) + 1 >= 1:
                    out.add(k)
            if side == "e" and x1 == bx1 or side == "w" and x0 == bx0:
                if min(y1, hi) - max(y0, lo) + 1 >= 1:
                    out.add(k)
    return out


def _leaf_cost(want, rect):
    x0, y0, x1, y1 = rect
    w, h = x1 - x0 + 1, y1 - y0 + 1
    cost = 0.0
    short, long_ = min(w, h), max(w, h)
    if short < want.min[0]:
        cost += 300 * (want.min[0] - short)
    if long_ < want.min[1]:
        cost += 300 * (want.min[1] - long_)
    cost += 60.0 * abs(w * h - want.area) / want.area
    if not want.corridor:
        cost += 8.0 * max(0.0, long_ / float(short) - 2.2)
    for ax, ay in want.anchors:
        if not (x0 <= ax <= x1 and y0 <= ay <= y1):
            cost += RULE
    if want.fixed:
        if "w" in want.fixed and w != want.fixed["w"]:
            cost += 150 * abs(w - want.fixed["w"])
        if "h" in want.fixed and h != want.fixed["h"]:
            cost += 150 * abs(h - want.fixed["h"])
    return cost


def touch(a, b, need=3):
    """Two rects with one wall line between them share at least `need` tiles of it."""
    ax0, ay0, ax1, ay1 = a
    bx0, by0, bx1, by1 = b
    if ax1 + 2 == bx0 or bx1 + 2 == ax0:
        return min(ay1, by1) - max(ay0, by0) + 1 >= need
    if ay1 + 2 == by0 or by1 + 2 == ay0:
        return min(ax1, bx1) - max(ax0, bx0) + 1 >= need
    return False


def _cuts(block, wants, rect, beam, memo):
    """Ways to slice rect for these rooms in this order, best first: [(cost, tree, {id: rect})]."""
    key = (tuple(w.id for w in wants), rect)
    if key in memo:
        return memo[key]
    x0, y0, x1, y1 = rect
    if len(wants) == 1:
        w = wants[0]
        node = w.expand(x1 - x0 + 1, y1 - y0 + 1) if w.expand else w.node
        out = [(_leaf_cost(w, rect), node, {w.id: rect})]
        memo[key] = out
        return out
    out = []
    for k in range(1, len(wants)):
        a, b = wants[:k], wants[k:]
        share = sum(w.area for w in a) / float(sum(w.area for w in wants))
        for axis in "xy":
            length = (x1 - x0 + 1) if axis == "x" else (y1 - y0 + 1)
            ideal = share * (length - 1)
            sizes = {int(ideal), int(ideal) + 1}
            # a room whose side the outline dictates gets that cut too, whatever its share says
            dim = "w" if axis == "x" else "h"
            if len(a) == 1 and a[0].fixed and dim in a[0].fixed:
                sizes.add(a[0].fixed[dim])
            if len(b) == 1 and b[0].fixed and dim in b[0].fixed:
                sizes.add(length - 1 - b[0].fixed[dim])
            for size in sorted(sizes):
                if size < 2 or length - 1 - size < 2:
                    continue
                if axis == "x":
                    ra, rb = (x0, y0, x0 + size - 1, y1), (x0 + size + 1, y0, x1, y1)
                else:           # y cuts run top to bottom, like shell.Y
                    ra, rb = (x0, y1 - size + 1, x1, y1), (x0, y0, x1, y1 - size - 1)
                for ca, ta, pa in _cuts(block, a, ra, beam, memo)[:beam]:
                    for cb, tb, pb in _cuts(block, b, rb, beam, memo)[:beam]:
                        placed = dict(pa)
                        placed.update(pb)
                        out.append((ca + cb, (X if axis == "x" else Y)((size, ta), (1.0, tb)), placed))
    out.sort(key=lambda c: c[0])
    out = out[:beam * 4] or [(1e6, wants[0].id, {})]
    memo[key] = out
    return out


def judge(block, wants, placed, links=()):
    """Cost of the rules that need the whole block: frontage, links, friends. Returns (cost, [broken rules])."""
    by = {w.id: w for w in wants}
    cost, broken = 0.0, []
    for w in wants:
        if w.id not in placed:
            continue
        have = _edge_kinds(block, placed[w.id])
        for o in wants:
            if o is not w and o.provides and o.id in placed and touch(placed[w.id], placed[o.id], 2):
                have |= set(o.provides)
        for kind in w.front:
            if kind not in have:
                cost += RULE
                broken.append("%s has no wall on %s" % (w.id, kind))
        for other in w.near:
            if other in placed and touch(placed[w.id], placed[other]):
                cost -= 25
    for a, b in links:
        if a in by and b in by and a in placed and b in placed and not touch(placed[a], placed[b], 2):
            cost += RULE
            broken.append("%s and %s share no wall" % (a, b))
    return cost, broken


def _noise(seed, *parts):
    if seed is None:
        return 0.0
    return NOISE * random.Random("|".join(str(p) for p in (seed,) + parts)).random()


def _grown(block, wants):
    """The rooms' targets grown to fill the block's floor, so a hall piece does not soak up what is left over.
    Corridors keep their size; nothing shrinks."""
    rooms = [w for w in wants if not w.corridor]
    if not rooms:
        return wants
    usable = block.area - (len(wants) - 1) * block.area ** 0.5        # a wall line per cut, roughly
    scale = (usable - sum(w.area for w in wants if w.corridor)) / float(sum(w.area for w in rooms))
    if scale <= 1.0:
        return wants
    out = []
    for w in wants:
        if not w.corridor:
            w = copy.copy(w)
            w.area = w.area * scale
        out.append(w)
    return out


def solve_block(block, wants, links=(), seed=None, beam=10, fill=False):
    """Every ordering of the rooms, every way to cut (beam-limited): the cheapest, give or take the seed's noise.
    fill: grow the rooms' targets to the block's floor (see _grown)."""
    best, memo = None, {}
    if fill:
        wants = _grown(block, wants)
    for order in itertools.permutations(wants):
        for c, tree, placed in _cuts(block, list(order), block.rect, beam, memo)[:beam]:
            g, broken = judge(block, wants, placed, links)
            total = c + g + _noise(seed, block.name, repr(tree))
            if best is None or total < best[0]:
                best = (total, tree, placed, broken)
    return best


def solve(blocks, wants, links=(), seed=None, fixed=None, ratio=(0.6, 1.5), fill=False):
    """Assign rooms to blocks and cut each block. fixed: {room id: block name} for rooms that cannot move; ratio: how
    much floor a block may hold against what its rooms ask for. Rooms with a door between them (links) share a block.
    Returns ({block name: tree}, {room id: rect}, report lines)."""
    names = [b.name for b in blocks]
    fixed = fixed or {}
    choices = []
    for w in wants:
        if w.id in fixed:
            choices.append([fixed[w.id]])
            continue
        # a room with an anchor can only live in the block that holds it; a room that needs frontage only where a
        # block has that kind of edge, or where a room that provides it can stand
        fit = [b.name for b in blocks if all(b.rect[0] <= ax <= b.rect[2] and b.rect[1] <= ay <= b.rect[3]
                                             for ax, ay in w.anchors)]
        provided = {k for o in wants for k in o.provides}
        fit = [n for n in fit if not w.front or all(k in blocks[names.index(n)].kinds() or k in provided for k in w.front)]
        choices.append(fit or names)
    best, tried, memo = None, 0, {}
    for pick in itertools.product(*choices):
        groups = {n: [] for n in names}
        for w, n in zip(wants, pick):
            groups[n].append(w)
        if any(not g or len(g) > 5 for g in groups.values()):
            continue
        # a block cannot hold much more or much less floor than its rooms ask for
        if any(not ratio[0] <= sum(w.area for w in groups[b.name]) / float(b.area) <= ratio[1] for b in blocks):
            continue
        where = dict(zip([w.id for w in wants], pick))
        if any(a in where and b in where and where[a] != where[b] for a, b in links):
            continue
        total, trees, rects, broken = 0.0, {}, {}, []
        for b in blocks:
            key = (b.name, tuple(sorted(w.id for w in groups[b.name])))
            if key not in memo:
                memo[key] = solve_block(b, groups[b.name], links, seed, fill=fill)
            c, t, p, br = memo[key]
            total += c
            trees[b.name] = t
            rects.update(p)
            broken += br
        tried += 1
        total += _noise(seed, "pick", pick)
        if best is None or total < best[0]:
            best = (total, trees, rects, dict(zip([w.id for w in wants], pick)), broken)
    if best is None:
        return None, None, ["solve: no assignment of rooms to blocks fits"]
    total, trees, rects, pick, broken = best
    report = ["solve: %d assignments tried, best cost %.0f%s" % (tried, total, "" if seed is None else " (seed %s)" % seed)]
    for b in blocks:
        report.append("solve: %-3s %s" % (b.name, ", ".join(
            "%s %dx%d" % (rid, rects[rid][2] - rects[rid][0] + 1, rects[rid][3] - rects[rid][1] + 1)
            for rid in rects if pick.get(rid) == b.name)))
    for line in broken:
        report.append("solve: BROKEN %s" % line)
    return trees, rects, report
