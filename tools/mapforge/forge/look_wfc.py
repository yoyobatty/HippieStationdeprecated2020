"""The floor look by wave function collapse, learned from MetaStation.

    python tools/mapforge/forge/look_wfc.py              # (re)train, print what it learned
    python tools/mapforge/forge/look_wfc.py --area /area/maintenance   # the commonest looks of one area family

What it decides is the LOOK of a floor tile: the colour quarters (turf_decal/tile), the grime (dirt, cobwebs, old
blood, cig butts, the maint loot spawner, trash) and contraband posters. It never decides structure: walls, doors,
furniture, turfs and the functional decals (hazard stripes, bot boxes, delivery squares, loading arrows) are set by
the rule passes before it runs and are context it reads.

Training. Every open tile of the example map gives one example per symmetry of the square (4 turns x mirror, decal
dirs and pixel offsets turned with it). An example is
  - the tile's context: its area family, its turf, and the classes of it and its 8 neighbours
    (W wall/window, O outside, D door, T table, P other furniture, Z work floor (stripes or a zone turf),
     F floor of the same area, H floor of another area)
  - its look in two layers: colour (the tile quarters, the area's own department colour written C so medbay's blue
    and science's purple teach each other) and grime (everything else it decides)
  - the looks of its 4 neighbours, for the adjacency table (which look may sit beside which, in which direction)

Generation, one layer after the other (colour, then grime with the colour fixed):
  1  each target tile's domain = the looks seen in the most specific context that has enough examples
     (area family + turf + 8-neighbour classes, then 4 neighbours, then the coarse family, then classes alone)
  2  collapse the tile with the least entropy: pick a look by its weight times how often it sat beside the looks
     already chosen next to it
  3  propagate: a neighbour loses every look the adjacency table never saw beside any look still possible here
     (colour layer only: grime adjacency is too sparse to be a hard rule); a tile left with nothing gets its whole
     domain back (counted as a contradiction; no backtracking)
"""
import math
import os
import pickle
import random
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from forge import dmm, kit  # noqa: E402
from forge.dress import dept_colour  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
CACHE = os.path.join(ROOT, "data", "mapforge", "look_wfc.pkl")
MAPS = ["MetaStation/MetaStation.dmm"]
VERSION = 5

TILE = "/obj/effect/turf_decal/tile/"
COLOUR = (TILE,)
GRIME = ("/obj/effect/decal/cleanable", "/obj/item/cigbutt", "/obj/item/trash", "/obj/effect/spawner/lootdrop/maintenance",
         "/obj/structure/sign/poster/contraband", "/obj/structure/sign/poster/random", "/obj/structure/sign/poster/official/random")
GRIME_SKIP = ("/obj/effect/decal/cleanable/blood/gibs", "/obj/effect/decal/cleanable/xenoblood",
              "/obj/effect/decal/cleanable/robot_debris", "/obj/effect/decal/cleanable/crayon")
FUNCTIONAL = ("/obj/effect/turf_decal/stripes", "/obj/effect/turf_decal/bot", "/obj/effect/turf_decal/delivery",
              "/obj/effect/turf_decal/loading_area", "/obj/effect/turf_decal/box", "/obj/effect/turf_decal/caution",
              "/obj/effect/turf_decal/arrows")
CORNER_CODED = (TILE, "/obj/effect/turf_decal/stripes/corner")
CORNER_VEC = {1: (-1, 1), 4: (1, 1), 2: (1, -1), 8: (-1, -1)}
DIR_VEC = {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0), 5: (1, 1), 6: (1, -1), 9: (-1, 1), 10: (-1, -1)}
COBWEB = {"/obj/effect/decal/cleanable/cobweb": (-1, 1), "/obj/effect/decal/cleanable/cobweb/cobweb2": (1, 1)}
CARD_V = {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0)}
RING = [(0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1)]
SYMS = [(a, b, c, d) for a, b, c, d in ((1, 0, 0, 1), (0, 1, -1, 0), (-1, 0, 0, -1), (0, -1, 1, 0),
                                        (-1, 0, 0, 1), (0, -1, -1, 0), (1, 0, 0, -1), (0, 1, 1, 0))]
MIN_N = 24      # examples (after the x8 symmetry) a context needs before its domain is trusted


def tf(T, v):
    a, b, c, d = T
    return (a * v[0] + b * v[1], c * v[0] + d * v[1])


def inv(T):
    a, b, c, d = T          # orthogonal: the inverse is the transpose
    return (a, c, b, d)


def vec_dir(v, table):
    for k, w in table.items():
        if w == v:
            return k
    return None


def turn_atom(o, T):
    """The atom as it looks in the turned world, or None when it has no turned form (a cobweb in a lower corner)."""
    if o.path in COBWEB:
        v = tf(T, COBWEB[o.path])
        p = next((k for k, w in COBWEB.items() if w == v), None)
        if p is None:
            return None
        return dmm.Atom(p, [kv for kv in o.vars if kv[0] != "dir"])
    vs = []
    px, py = o.num("pixel_x"), o.num("pixel_y")
    if px or py:
        px, py = tf(T, (px, py))
    for k, v in o.vars:
        if k in ("pixel_x", "pixel_y"):
            continue
        if k == "dir":
            continue
        vs.append((k, v))
    has_dir = o.get("dir") is not None or o.path.startswith(CORNER_CODED)
    if has_dir:
        d = o.num("dir", 2) or 2
        table = CORNER_VEC if o.path.startswith(CORNER_CODED) else DIR_VEC
        if d in table:
            d = vec_dir(tf(T, table[d]), table)
        if d != 2:
            vs.append(("dir", str(d)))
    if px:
        vs.append(("pixel_x", str(px)))
    if py:
        vs.append(("pixel_y", str(py)))
    vs.sort(key=lambda kv: {"dir": 0, "pixel_x": 1, "pixel_y": 2}.get(kv[0], 3))
    return dmm.Atom(o.path, vs)


def layer_of(o):
    if o.path.startswith(COLOUR):
        return 0
    if o.path.startswith(GRIME) and not o.path.startswith(GRIME_SKIP):
        return 1
    return None


def norm_colour(path, area):
    if path.startswith(TILE):
        col = path[len(TILE):]
        if col == dept_colour(area):
            return TILE + "C"
    return path


def tokens(t, T=(1, 0, 0, 1)):
    """(colour token, grime token) of a tile in the world turned by T."""
    out = ([], [])
    for o in t.objs:
        L = layer_of(o)
        if L is None:
            continue
        a = turn_atom(o, T)
        if a is None:
            continue
        a = dmm.Atom(norm_colour(a.path, t.apath), a.vars)
        out[L].append(a.text())
    return tuple(sorted(set(out[0]))), tuple(sorted(out[1]))


def family(area):
    parts = area.split("/")
    if len(parts) > 2 and parts[2] in ("hallway", "maintenance"):
        return "/".join(parts[:3])
    return "/".join(parts[:4]) if len(parts) > 3 else area


def group(area):
    parts = area.split("/")
    if len(parts) > 2 and parts[2] in ("hallway", "maintenance", "solar", "space"):
        return parts[2]
    return "room"


def turfc(t):
    p = t.tpath
    return p[len("/turf/open/floor/"):] if p.startswith("/turf/open/floor/") else p


def piece(o):
    return kit.is_dense_atom(o) and not o.path.startswith(("/obj/structure/window", "/obj/structure/grille")) and \
        abs(o.num("pixel_x")) < 16 and abs(o.num("pixel_y")) < 16


def klass(t, area):
    if t is None:
        return "W"
    p = t.tpath
    if p.startswith("/turf/open/space") or t.apath.startswith(("/area/space", "/area/solar")):
        return "O"
    if p.startswith("/turf/closed") or t.has("/obj/structure/grille") or t.has("/obj/effect/spawner/structure/window") or \
            any(o.path.startswith("/obj/structure/window") and ("fulltile" in o.path) for o in t.objs):
        return "W"
    if not p.startswith("/turf/open"):
        return "W"
    if t.has("/obj/machinery/door"):
        return "D"
    if any(piece(o) for o in t.objs):
        return "T" if t.has("/obj/structure/table") else "P"
    if any(o.path.startswith(FUNCTIONAL) for o in t.objs):
        return "Z"
    return "F" if t.apath == area else "H"


class Model:
    def __init__(self):
        # unary[layer][key] -> Counter(token); keys: ("8", fam, turf, sig9) ("4", fam, turf, sig5) ("g", grp, turf, sig5)
        # ("c", grp, sig5)
        self.unary = (defaultdict(Counter), defaultdict(Counter))
        # pair[layer][grp] -> Counter((tokA, dir, tokB)); seen[layer][grp] -> Counter(tok)
        self.pair = (defaultdict(Counter), defaultdict(Counter))
        # room style -> how many example rooms of a family (or group) were trimmed (T) or bare (B)
        self.styles = defaultdict(Counter)
        self.version = VERSION

    def keys(self, area, tc, sig, style="*"):
        """Contexts from the most specific down. style: the room's trimmed/bare roll (colour layer), "*" for grime."""
        fam, grp = family(area), group(area)
        s5 = sig[0] + sig[1] + sig[3] + sig[5] + sig[7]
        return [("8", style, fam, tc, sig), ("4", style, fam, tc, s5), ("g", style, grp, tc, s5),
                ("c", style, grp, s5), ("x", style, grp, sig[0])]

    def domain(self, L, area, tc, sig, style="*"):
        for k in self.keys(area, tc, sig, style if L == 0 else "*"):
            if L == 0 and k[0] in ("c", "x"):
                break       # colour is only drawn where the context is known well: a guessed quarter reads as a stray
            c = self.unary[L].get(k)
            if c and sum(c.values()) >= MIN_N:
                return c, k[0]
        return Counter({(): 1}), "-"

    def roll_style(self, area, rnd):
        c = self.styles.get(family(area)) or self.styles.get(group(area)) or Counter({"B": 1})
        r = rnd.random() * sum(c.values())
        for k, n in sorted(c.items()):
            r -= n
            if r <= 0:
                return k
        return "B"


def rooms_of(m, tiles):
    """Connected parts (4-way) of each area among tiles: [(area, [tiles])]."""
    left, out = set(tiles), []
    for s in sorted(tiles):
        if s not in left:
            continue
        a = m.get(*s).apath
        left.discard(s)
        part, st = [s], [s]
        while st:
            q = st.pop()
            for v in CARD_V.values():
                r = (q[0] + v[0], q[1] + v[1])
                if r in left and m.get(*r).apath == a:
                    left.discard(r)
                    part.append(r)
                    st.append(r)
        out.append((a, part))
    return out


TRIMMED = 0.12      # a room with colour on this share of its floor counts as trimmed


def sig_at(m, p, area, T=(1, 0, 0, 1)):
    Ti = inv(T)
    s = [klass(m.get(*p), area)]
    for v in RING:
        w = tf(Ti, v)
        s.append(klass(m.get(p[0] + w[0], p[1] + w[1]), area))
    return "".join(s)


def train(maps=MAPS):
    md = Model()
    for rel in maps:
        m = dmm.read(os.path.join(ROOT, "_maps", "map_files", rel))
        open_ = [(x, y) for x in range(1, m.maxx + 1) for y in range(1, m.maxy + 1)
                 if m.get(x, y) is not None and m.get(x, y).tpath.startswith("/turf/open/floor")
                 and klass(m.get(x, y), m.get(x, y).apath) != "O"]
        style = {}
        for area, part in rooms_of(m, open_):
            st = "T" if sum(1 for p in part if tokens(m.get(*p))[0]) >= TRIMMED * len(part) else "B"
            md.styles[family(area)][st] += 1
            md.styles[group(area)][st] += 1
            for p in part:
                style[p] = st
        for T in SYMS:
            Ti = inv(T)
            tok = {p: tokens(m.get(*p), T) for p in open_}
            for p in open_:
                t = m.get(*p)
                area = t.apath
                sig = sig_at(m, p, area, T)
                tc = turfc(t)
                grp = group(area)
                for k in md.keys(area, tc, sig, style[p]):
                    md.unary[0][k][tok[p][0]] += 1
                for k in md.keys(area, tc, sig):
                    md.unary[1][k][tok[p][1]] += 1
                for d, v in CARD_V.items():
                    w = tf(Ti, v)
                    q = (p[0] + w[0], p[1] + w[1])
                    if q in tok and m.get(*q).apath == area:
                        for L in (0, 1):
                            md.pair[L][grp][(tok[p][L], d, tok[q][L])] += 1
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    md.unary = tuple(dict(u) for u in md.unary)
    md.pair = tuple(dict(u) for u in md.pair)
    with open(CACHE, "wb") as f:
        pickle.dump({"version": VERSION, "unary": md.unary, "pair": md.pair, "styles": dict(md.styles)}, f)
    return md


def load():
    src = max(os.path.getmtime(os.path.join(ROOT, "_maps", "map_files", r)) for r in MAPS)
    here = os.path.getmtime(os.path.abspath(__file__))
    if os.path.exists(CACHE) and os.path.getmtime(CACHE) > max(src, here):
        with open(CACHE, "rb") as f:
            d = pickle.load(f)
        if d.get("version") == VERSION:
            md = Model()
            md.unary, md.pair, md.styles = d["unary"], d["pair"], d["styles"]
            return md
    return train()


def solve(cells, dom, nbr_tok, pairs, rnd, hard, beta=0.6):
    """cells: positions to decide; dom[p]: Counter token->weight; nbr_tok(p): token of a decided tile outside the
    cells (or None); pairs: Counter((a, dir, b)). Returns ({p: token}, contradictions)."""
    cellset = set(cells)
    poss = {p: set(dom[p]) for p in cells}
    out = {}
    bad = 0
    seen_with = defaultdict(set)        # (a, dir) -> tokens b seen beside it
    left_n, right_n = Counter(), Counter()
    for (a, d, b), n in pairs.items():
        seen_with[(a, d)].add(b)
        left_n[(a, d)] += n
        right_n[(d, b)] += n
    total = float(sum(pairs.values())) or 1.0

    def ok(a, d, b):
        return a == () or b == () or b in seen_with.get((a, d), ())

    def known(q):
        if q in out:
            return out[q]
        if q in cellset:
            return None
        return nbr_tok(q)

    def score(p, t):
        s = math.log(dom[p][t])
        for d, v in CARD_V.items():
            nb = known((p[0] + v[0], p[1] + v[1]))
            if nb is not None:
                # how much likelier this pair is than chance (pointwise mutual information, smoothed): the unary
                # weight already carries how common each look is, so the pair term must not count it again
                exp_n = left_n.get((t, d), 0) * right_n.get((d, nb), 0) / total
                s += beta * math.log((pairs.get((t, d, nb), 0) + 1.0) / (exp_n + 1.0))
        return s

    def entropy(p):
        ws = [dom[p][t] for t in poss[p]]
        tot = float(sum(ws))
        return -sum(w / tot * math.log(w / tot) for w in ws) if len(ws) > 1 else 0.0

    def propagate(stack):
        nonlocal bad
        while stack:
            p = stack.pop()
            for d, v in CARD_V.items():
                q = (p[0] + v[0], p[1] + v[1])
                if q not in poss or q in out:
                    continue
                keep = {b for b in poss[q] if any(ok(a, d, b) for a in poss[p])}
                if keep == poss[q]:
                    continue
                if not keep:
                    bad += 1
                    continue        # left as it was: no backtracking, the score settles it
                poss[q] = keep
                stack.append(q)

    if hard:
        # the decided tiles round the cells cut their neighbours' domains first
        st = []
        for p in cells:
            for d, v in CARD_V.items():
                nb = known((p[0] + v[0], p[1] + v[1]))
                if nb is None:
                    continue
                keep = {t for t in poss[p] if ok(t, d, nb)}
                if keep and keep != poss[p]:
                    poss[p] = keep
                    st.append(p)
        propagate(st)
    left = set(cells)
    noise = {p: rnd.random() * 1e-3 for p in cells}
    while left:
        p = min(left, key=lambda q: (entropy(q) + noise[q], q))
        left.discard(p)
        cand = sorted(poss[p])
        sc = [score(p, t) for t in cand]
        top = max(sc)
        ws = [math.exp(s - top) for s in sc]
        r = rnd.random() * sum(ws)
        for t, w in zip(cand, ws):
            r -= w
            if r <= 0:
                break
        out[p] = t
        poss[p] = {t}
        if hard:
            propagate([p])
    return out, bad


def apply(m, tiles, seed, md=None):
    """Repaint the look of the given floor tiles. Returns report lines."""
    md = md or load()
    rnd = random.Random("look|%d" % seed)
    tiles = sorted(p for p in tiles if m.get(*p) is not None and m.get(*p).tpath.startswith("/turf/open/floor")
                   and klass(m.get(*p), m.get(*p).apath) != "O")
    tset = set(tiles)
    # the structure is read before the old look comes off (the look is no part of it)
    ctx = {}
    for p in tiles:
        t = m.get(*p)
        ctx[p] = (t.apath, turfc(t), sig_at(m, p, t.apath))
    # each room rolls trimmed or bare once, as Meta's rooms of its kind are
    style = {}
    rolled = Counter()
    for area, part in rooms_of(m, tiles):
        st = md.roll_style(area, rnd)
        rolled[st] += 1
        for p in part:
            style[p] = st
    for p in tiles:
        t = m.get(*p)
        t.objs = [o for o in t.objs if layer_of(o) is None]
    levels = Counter()
    notes = []
    chosen_all = [{}, {}]
    for L in (0, 1):
        by_grp = defaultdict(list)
        dom = {}
        for p in tiles:
            area, tc, sig = ctx[p]
            c, lev = md.domain(L, area, tc, sig, style[p])
            if sig[0] == "D":
                # a door stands in the wall line: no colour or grime drawn into it
                c, lev = Counter({(): 1}), "door"
            colour = dept_colour(area)
            if L == 0 and colour in (None,):
                c = Counter({k: n for k, n in c.items() if not any(TILE + "C" in s for s in k)}) or Counter({(): 1})
            dom[p] = c
            levels[(L, lev)] += 1
            by_grp[group(area)].append(p)

        def nbr_tok(q, L=L):
            if q in tset:
                return None
            t = m.get(*q)
            if t is None or not t.tpath.startswith("/turf/open/floor"):
                return None
            return tokens(t)[L]
        bad_total = 0
        for grp, cells in sorted(by_grp.items()):
            # one solve per area so the adjacency is read inside rooms the way it was learned
            by_area = defaultdict(list)
            for p in cells:
                by_area[ctx[p][0]].append(p)
            for area, cs in sorted(by_area.items()):
                res, bad = solve(cs, dom, nbr_tok, md.pair[L].get(grp, Counter()), rnd, hard=(L == 0))
                bad_total += bad
                chosen_all[L].update(res)
        notes.append("look %s: %d tiles, %d contradictions, context levels %s" % (
            ("colour", "grime")[L], len(tiles), bad_total,
            {k[1]: n for k, n in sorted(levels.items()) if k[0] == L}))
    def hangs_on(q, o):
        px, py = o.num("pixel_x"), o.num("pixel_y")
        if abs(px) < 20 and abs(py) < 20:
            return None
        return (q[0] + (1 if px >= 20 else -1 if px <= -20 else 0), q[1] + (1 if py >= 20 else -1 if py <= -20 else 0))

    def wall_free(w, mine):
        tw = m.get(*w)
        if tw is None or not tw.tpath.startswith("/turf/closed/wall"):
            return False
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                q = (w[0] + dx, w[1] + dy)
                tq = m.get(*q)
                if q == mine or tq is None:
                    continue
                if any(hangs_on(q, o) == w for o in tq.objs):
                    return False
        return True
    painted = Counter()
    dropped = 0
    for p in tiles:
        t = m.get(*p)
        area = ctx[p][0]
        colour = dept_colour(area)
        new = []
        for L in (0, 1):
            for s in chosen_all[L].get(p, ()):
                a = dmm.Atom.parse(s)
                if a.path == TILE + "C":
                    if not colour:
                        continue
                    a = dmm.Atom(TILE + colour, a.vars)
                if a.path.startswith("/obj/structure/sign"):
                    w = hangs_on(p, a)
                    if w is None or not wall_free(w, p):
                        dropped += 1
                        continue
                new.append(a)
                painted[("colour", "grime")[L]] += 1
        # look atoms go under what stands on the tile (decals first, as the maps write them)
        t.objs = [a for a in new if a.path.startswith("/obj/effect")] + t.objs + \
            [a for a in new if not a.path.startswith("/obj/effect")]
    notes.append("look rooms: %d trimmed, %d bare" % (rolled["T"], rolled["B"]))
    notes.append("look painted: %d colour quarters, %d grime pieces (%d posters dropped: wall taken)" % (
        painted["colour"], painted["grime"], dropped))
    return notes


def main():
    md = train()
    area = sys.argv[sys.argv.index("--area") + 1] if "--area" in sys.argv else None
    for L, name in ((0, "colour"), (1, "grime")):
        n = sum(len(c) for c in md.unary[L].values())
        print("%s: %d contexts, %d (context, look) pairs, adjacency %s" % (
            name, len(md.unary[L]), n, {g: len(c) for g, c in md.pair[L].items()}))
        if area:
            tot = Counter()
            for k, c in md.unary[L].items():
                if k[0] == "4" and k[1] == family(area):
                    tot.update(c)
            for tok, n in tot.most_common(15):
                print("   %6d  %s" % (n // 8, " + ".join(s.replace("/obj/effect/", "") for s in tok) or "(plain)"))


if __name__ == "__main__":
    main()
