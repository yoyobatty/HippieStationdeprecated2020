"""Auto-furnishing from the corpus: fill an empty room with real furniture clusters taken from human-made maps.

furnish(floor, solid, doors, kind, seed) -> {tile: [atom text, ...]}

- floor: set of free floor tiles of the room; solid(tile) -> True for walls/windows; doors: door tiles touching it
- kind: an area path (e.g. "/area/medical/medbay/central"); the corpus supplies clusters, core objects and density

Rules, from how people lay rooms out:
- clusters keep their wall contacts (a cluster that stood against a wall goes against a wall, rotated to suit)
- the tiles a cluster left open (where you stand to use it) stay open
- one free tile between clusters, nothing in front of a door, the room's free floor stays in one piece
- core objects for the room type first (what >=50% of such rooms have), then the most common clusters, until the
  room is about as full as the real ones are
"""
import random

from forge import corpus, dmm

D4 = {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0)}
CW = {1: 4, 4: 2, 2: 8, 8: 1}
DIRECTIONAL = ("/obj/structure/chair", "/obj/machinery/computer", "/obj/machinery/modular_computer", "/obj/structure/bed/roller")


def rot_mask(m, k):
    for _ in range(k):
        m = sum(CW[d] for d in (1, 2, 4, 8) if m & d)
    return m


def rot_dir(d, k):
    if d in (1, 2, 4, 8):
        for _ in range(k):
            d = CW[d]
        return d
    return rot_mask(d, k)  # diagonals rotate bitwise


def rot_xy(x, y, k):
    for _ in range(k):
        x, y = y, -x
    return x, y


def rot_atom(text, k):
    if k == 0:
        return text
    a = dmm.Atom.parse(text)
    d = a.get("dir")
    vs = [(n, v) for n, v in a.vars if n not in ("dir", "pixel_x", "pixel_y")]
    if d is not None or a.path.startswith(DIRECTIONAL):
        nd = rot_dir(int(d) if d is not None and d.lstrip("-").isdigit() else 2, k)
        if nd != 2:
            vs.append(("dir", str(nd)))
    px, py = a.num("pixel_x"), a.num("pixel_y")
    if px or py:
        px, py = rot_xy(px, py, k)
        if px:
            vs.append(("pixel_x", str(px)))
        if py:
            vs.append(("pixel_y", str(py)))
    return dmm.Atom(a.path, vs).text()


def variants(cl):
    """The cluster in 4 rotations: (cells [(dx,dy,atoms,wallmask)], clear [(dx,dy)])."""
    out = []
    for k in range(4):
        cells = []
        for x, y, atoms, wm in cl["cells"]:
            rx, ry = rot_xy(x, y, k)
            cells.append((rx, ry, [rot_atom(t, k) for t in atoms], rot_mask(wm, k)))
        clear = [rot_xy(x, y, k) for x, y in cl["clear"]]
        mx = min(c[0] for c in cells)
        my = min(c[1] for c in cells)
        cells = [(x - mx, y - my, a, w) for x, y, a, w in cells]
        clear = [(x - mx, y - my) for x, y in clear]
        out.append((cells, clear))
    return out


def paths_of(cl):
    return {t.split("{")[0] for c in cl["cells"] for t in c[2]}


def components(free):
    seen, n = set(), 0
    for s0 in free:
        if s0 in seen:
            continue
        n += 1
        q = [s0]
        seen.add(s0)
        while q:
            p = q.pop()
            for dx, dy in D4.values():
                nb = (p[0] + dx, p[1] + dy)
                if nb in free and nb not in seen:
                    seen.add(nb)
                    q.append(nb)
    return n


def connected(free, must):
    if not free:
        return not must
    start = next(iter(must)) if must else next(iter(free))
    if start not in free:
        return False
    seen, q = {start}, [start]
    while q:
        p = q.pop()
        for dx, dy in D4.values():
            n = (p[0] + dx, p[1] + dy)
            if n in free and n not in seen:
                seen.add(n)
                q.append(n)
    return len(seen) == len(free)


def walk(free, a, b, cap=12):
    seen, q = {a: 0}, [a]
    while q:
        p = q.pop(0)
        if p == b:
            return seen[p]
        if seen[p] >= cap:
            continue
        for dx, dy in D4.values():
            n = (p[0] + dx, p[1] + dy)
            if n in free and n not in seen:
                seen[n] = seen[p] + 1
                q.append(n)
    return None


def squeezes(free, new_occ):
    """True if new furniture leaves two open tiles touching only at a corner (both tiles between them blocked, one
    of them by what we just placed) with a long way round: a person can't slip between, so they'd walk the loop."""
    for c in new_occ:
        for dx, dy in ((1, 1), (1, -1), (-1, 1), (-1, -1)):
            # c is one of the two blockers; the pair is the other diagonal of the 2x2 square
            other = (c[0] + dx, c[1] + dy)
            # the open pair is (c's row, other's column) & (other's row, c's column)
            o1, o2 = (other[0], c[1]), (c[0], other[1])
            if o1 in free and o2 in free and other not in free:
                d = walk(free, o1, o2)
                if d is None or d > 6:
                    return True
    return False


# tall furniture human maps almost never back onto glass (7-11% of the time, against 27-37% for consoles and chairs)
TALL = ("/obj/machinery/vending", "/obj/structure/closet", "/obj/structure/bookcase", "/obj/machinery/rnd",
        "/obj/machinery/suit_storage_unit", "/obj/structure/reagent_dispensers", "/obj/structure/rack",
        "/obj/machinery/autolathe", "/obj/machinery/smartfridge")


# these stand against a wall on human maps (loose 0-4% of the time): never place one with no wall behind it
WALL_BOUND = ("/obj/machinery/vending", "/obj/structure/closet", "/obj/machinery/suit_storage_unit",
              "/obj/structure/reagent_dispensers", "/obj/machinery/autolathe")


TABLETOP = ("/obj/machinery/cell_charger", "/obj/machinery/microwave", "/obj/machinery/reagentgrinder",
            "/obj/machinery/recharger", "/obj/machinery/computer/med_data/laptop")
RND_MACHINE = ("/obj/machinery/rnd/destructive_analyzer", "/obj/machinery/rnd/production/protolathe",
               "/obj/machinery/rnd/production/circuit_imprinter", "/obj/machinery/rnd/experimentor")
RND_CONSOLE = ("/obj/machinery/computer/rdconsole",)


def table_juts(occ):
    """True if a table run that touches a wall has a tile off the wall (it should wrap along walls instead)."""
    tabs = {p for p, atoms in occ.items() if atoms and any(a.startswith("/obj/structure/table") for a in atoms)}
    seen = set()
    for p in tabs:
        if p in seen:
            continue
        grp, q = {p}, [p]
        seen.add(p)
        while q:
            c = q.pop()
            for dx, dy in D4.values():
                n = (c[0] + dx, c[1] + dy)
                if n in tabs and n not in seen:
                    seen.add(n)
                    grp.add(n)
                    q.append(n)
        on_wall = {c for c in grp if any(_solid((c[0] + dx, c[1] + dy)) for dx, dy in D4.values())}
        if on_wall and len(grp) > 1 and on_wall != grp:
            return True
    return False


_solid = lambda p: False  # noqa: E731  (set per furnish call)


def cell_count(cl, path):
    return sum(1 for c in cl["cells"] if any(t.split("{")[0] == path for t in c[2]))


# machines a room has one of (a second techfab or console beside the first reads as a mistake)
REPEATABLE = ("/obj/machinery/vending/wallmed", "/obj/machinery/iv_drip", "/obj/machinery/hydroponics",
              "/obj/machinery/portable_atmospherics", "/obj/machinery/light", "/obj/machinery/holopad", "/obj/machinery/conveyor",
              "/obj/machinery/space_heater", "/obj/machinery/shower", "/obj/machinery/deepfryer")


def unique_machines(cl):
    return {p for p in paths_of(cl) if p.startswith("/obj/machinery") and not p.startswith(REPEATABLE)}


def furnish(floor, solid, doors, kind, seed=1, density=None, require=(), exclude=(), max_cluster=9, log=None, present=(), reserved=(), glass=lambda t: False):
    rng = random.Random(seed)
    global _solid
    _solid = solid
    S = corpus.summary(kind)
    allc = [c for c in S["clusters"] if not any(p.startswith(tuple(exclude)) for p in paths_of(c))]
    pool = [c for c in allc if len(c["cells"]) <= max_cluster and not c.get("single")]
    singles = [c for c in allc if c.get("single")]
    wall_singles = [c for c in singles if c["cells"][0][3]]
    if not pool:
        return {}
    # real rooms of this type are this full; small rooms run fuller (less walkway to keep)
    base = S["density"] if density is None else density
    target = min(0.55, max(0.25, base * (1.4 if len(floor) < 40 else 1.15))) if density is None else density
    want = int(round(target * len(floor)))
    floor = set(floor)
    door_front = {(d[0] + dx, d[1] + dy) for d in doors for dx, dy in D4.values()} & floor
    from forge import orient
    cx = (min(p[0] for p in floor) + max(p[0] for p in floor)) / 2.0
    cy = (min(p[1] for p in floor) + max(p[1] for p in floor)) / 2.0
    placed_at = {}  # anchor path -> tiles it already stands on in this room

    def context_score(abs_cells):
        """Where real maps put this kind of thing (corner/wall/open, near/far from the door), and mirror pairs."""
        sc = 0.0
        for p, atoms, wm in abs_cells:
            if not atoms:
                continue
            path = atoms[0].split("{")[0]
            nwalls = sum(1 for dx, dy in D4.values() if solid((p[0] + dx, p[1] + dy)))
            loc = "corner" if nwalls >= 2 else "wall" if nwalls else "open"
            near = any(abs(p[0] - d[0]) + abs(p[1] - d[1]) <= 3 for d in doors)
            sc += 0.8 * orient.placement_bonus(path, loc, near)
            # an R&D console links the machines it can see within 3 tiles: keep them together
            if path.startswith(RND_MACHINE) or path.startswith(RND_CONSOLE):
                other = RND_CONSOLE if path.startswith(RND_MACHINE) else RND_MACHINE
                for q_path, qs in placed_at.items():
                    if q_path.startswith(other):
                        dmin = min(max(abs(p[0] - q[0]), abs(p[1] - q[1])) for q in qs)
                        sc += 4.0 if dmin <= 3 else -6.0
            for q in placed_at.get(path, ()):
                if (abs((cx - p[0]) - (q[0] - cx)) < 0.6 and p[1] == q[1]) or (abs((cy - p[1]) - (q[1] - cy)) < 0.6 and p[0] == q[0]):
                    sc += 6.0  # the mirror spot of one already placed: rooms read as designed when pairs match
        return sc
    occupied = {}

    deferred = []

    def force_spot(path, relaxed=False):
        """A free floor tile against a real wall (not glass for tall things), not in front of a door or another
        piece, that doesn't split the room or make a squeeze; table-top machines go on a free table instead."""
        if path.startswith(TABLETOP):
            for t, atoms in sorted(occupied.items()):
                if atoms and atoms[0].startswith("/obj/structure/table") and not any(a.startswith(TABLETOP) for a in atoms):
                    return t
            return None
        base = components(floor - set(occupied))
        for t in sorted(floor):
            if t in occupied or (t in keep_open and not relaxed) or (relaxed and t in door_front):
                continue
            walls = [d for d, (dx, dy) in D4.items() if solid((t[0] + dx, t[1] + dy))]
            free_standing = not path.startswith(TALL + WALL_BOUND)  # canisters, machines: rows away from walls are fine
            if (not walls and not free_standing) or (walls and path.startswith(TALL) and all(glass((t[0] + D4[d][0], t[1] + D4[d][1])) for d in walls)):
                continue
            free_after = floor - set(occupied) - {t}
            if components(free_after) > base or squeezes(free_after, {t}):
                continue
            # it and everything beside it must still have free floor to stand on next to them (diagonals count)
            def usable(c):
                return any((c[0] + dx, c[1] + dy) in free_after for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy)
            if not usable(t) or not all(usable(c) for c in occupied
                                        if abs(c[0] - t[0]) <= 1 and abs(c[1] - t[1]) <= 1):
                continue
            # keep the side away from the wall open (its front)
            if walls:
                front = (t[0] - D4[walls[0]][0], t[1] - D4[walls[0]][1])
                if front in occupied:
                    continue
                keep_open.add(front)
            return t
        return None
    keep_open = set(door_front) | (set(reserved) & set(floor))
    halo = set()  # tiles next to placed clusters (the one-tile gap)
    backed = {}  # placed tile -> stood against a wall in its source map
    # require entries: "path" (at least one) or ("path", n)
    need = {}
    for r in require:
        path_, n_ = (r, 1) if isinstance(r, str) else (r[0], r[1])
        need[path_] = max(need.get(path_, 0), n_)
    require = list(need)
    if sum(need.values()) >= 0.4 * len(floor):
        want = 0  # a store room: what it stores, nothing else
    uncovered = [p for p in list(require) + S["core"] if not p.startswith(tuple(exclude))]
    tries = 0
    placed = []
    stuck_cover = stuck_fill = False
    while tries < 40:
        tries += 1
        cover = [p for p in uncovered if sum(cell_count(c, p) for c in placed) < need.get(p, 1)]
        # what the blueprint requires goes in first, while the room is still empty; core extras after
        must = [p for p in cover if p in require]
        if must:
            cover = must
        if not cover and len(occupied) >= want:
            break
        if cover:
            cands = [c for c in pool if paths_of(c) & set(cover)]
            if not cands or stuck_cover:
                cands = [c for c in singles if paths_of(c) & set(cover)]
            elif any(placed_at.get(p) for p in cover):
                # a second copy of something already here: the piece on its own can take the mirror spot
                cands = cands + [c for c in singles if paths_of(c) & set(cover)]
            if not cands:
                uncovered = [p for p in uncovered if p not in cover]
                continue
        else:
            cands = pool if not stuck_fill else wall_singles
            if not cands:
                break
        have = set(present) | {p for c in placed for p in unique_machines(c)}
        cands = [c for c in cands if not ((unique_machines(c) & have) - {p for p in need if sum(cell_count(x, p) for x in placed) < need[p]})]
        if not cands:
            if cover:
                uncovered = [p for p in uncovered if p not in cover]
            else:
                break
            continue
        weights = [c["count"] * (1 + 0.5 * len(c["maps"])) * (1 + len(paths_of(c) & set(cover))) for c in cands]
        sample = rng.choices(cands, weights=weights, k=min(40, len(cands)))
        best = None
        found = []
        for cl in sample:
            for cells, clear in variants(cl):
                w = max(c[0] for c in cells) + 1
                h = max(c[1] for c in cells) + 1
                for ax, ay in floor:
                    ok = True
                    score = 0.0
                    abs_cells = []
                    for x, y, atoms, wm in cells:
                        if not wm and atoms and atoms[0].startswith(WALL_BOUND):
                            ok = False
                            break
                        p = (ax + x, ay + y)
                        if p not in floor or p in occupied or p in keep_open:
                            ok = False
                            break
                        if p in halo:
                            # wall-backed pieces may stand shoulder to shoulder along a wall (lockers, morgue trays,
                            # counters); anything freestanding keeps a one-tile gap
                            if not wm or any(not backed.get((p[0] + dx, p[1] + dy), True)
                                             for dx in (-1, 0, 1) for dy in (-1, 0, 1) if (p[0] + dx, p[1] + dy) in occupied):
                                ok = False
                                break
                        for d, (dx, dy) in D4.items():
                            n = (p[0] + dx, p[1] + dy)
                            if wm & d:
                                if not solid(n):
                                    ok = False
                                    break
                                if glass(n) and atoms and atoms[0].startswith(TALL):
                                    ok = False  # lockers, vendors, bookcases stand against walls, not windows
                                    break
                                score += 1
                        if not ok:
                            break
                        abs_cells.append((p, atoms, wm))
                    if not ok:
                        continue
                    # access: every piece that was used from an open tile keeps one open tile beside it,
                    # preferably one already kept open (shared walkways, like a person would leave)
                    mine = {c[0] for c in abs_cells}
                    access = []
                    for x, y, atoms, wm in cells:
                        adj = [(ax + cx, ay + cy) for cx, cy in clear if abs(cx - x) + abs(cy - y) == 1]
                        if not adj:
                            continue
                        good = [q for q in adj if q in floor and q not in occupied and q not in mine]
                        if not good:
                            ok = False
                            break
                        shared = [q for q in good if q in keep_open]
                        access.append(shared[0] if shared else good[0])
                        score += 0.5 if shared else 0
                    if not ok:
                        continue
                    score += 3 * len(paths_of(cl) & set(cover)) + 0.6 * len(cells) + rng.random() * 1.5
                    score += context_score(abs_cells)
                    found.append((score, id(cl), cl, abs_cells, access))
        found.sort(key=lambda f: -f[0])
        base_parts = components(floor - set(occupied))
        for f in found[:60]:
            new_occ = {c[0] for c in f[3]}
            free_after = floor - set(occupied) - new_occ
            # a placement may not split the free floor further (rooms can start split: a chute tile past a windoor)
            if components(free_after) <= base_parts and not squeezes(free_after, new_occ)                     and not table_juts({**occupied, **{c[0]: c[1] for c in f[3]}}):
                best = (f[0], f[2], f[3], f[4])
                break
        if best is None:
            if cover and not stuck_cover:
                stuck_cover = True  # whole clusters don't fit: try the item on its own
            elif cover:
                # no corpus piece fits: a required item still goes in, on its own against a free stretch of wall
                # (or on a table if it's a table-top machine), keeping every rule; only then give up
                if cover[0] in require:
                    while sum(cell_count(c, cover[0]) for c in placed) < need.get(cover[0], 1):
                        spot = force_spot(cover[0]) or (None if cover[0].startswith(TABLETOP) else force_spot(cover[0], relaxed=True))
                        if not spot:
                            break
                        occupied.setdefault(spot, [])
                        occupied[spot] = occupied[spot] + [cover[0]]
                        backed[spot] = True
                        for dx in (-1, 0, 1):
                            for dy in (-1, 0, 1):
                                halo.add((spot[0] + dx, spot[1] + dy))
                        placed.append({"cells": [[0, 0, [cover[0]], 1]], "area": kind, "map": "forced", "count": 1, "maps": []})
                        placed_at.setdefault(cover[0], []).append(spot)
                    if sum(cell_count(c, cover[0]) for c in placed) < need.get(cover[0], 1):
                        deferred.append(cover[0])  # try again once the room is furnished (tables exist then)
                uncovered = [p for p in uncovered if p != cover[0]]
                stuck_cover = False
                tries = max(0, tries - 1)
            elif not stuck_fill:
                stuck_fill = True  # no more whole clusters fit: fill along the walls with single pieces
            continue
        stuck_cover = False
        _, cl, abs_cells, clear_abs = best
        new_occ = {c[0] for c in abs_cells}
        for p, atoms, wm in abs_cells:
            occupied[p] = atoms
            if atoms:
                placed_at.setdefault(atoms[0].split("{")[0], []).append(p)
            backed[p] = bool(wm)
        keep_open |= set(clear_abs)
        for p in new_occ:
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    n = (p[0] + dx, p[1] + dy)
                    if n not in new_occ:
                        halo.add(n)
        placed.append(cl)
        tries = 0 if len(occupied) < want or cover else tries
        if log is not None:
            log.append("placed %s from %s (%d tiles)" % (cl["area"].rsplit("/", 1)[-1], cl["map"], len(cl["cells"])))
    # second chance for required pieces that didn't fit, now that tables exist; only doorways and fronts protected
    for path in deferred:
        while sum(cell_count(c, path) for c in placed) < need.get(path, 1):
            spot = force_spot(path, relaxed=True)
            if not spot:
                if log is not None:
                    log.append("COULD NOT PLACE required %s" % path)
                break
            occupied[spot] = occupied.get(spot, []) + [path]
            placed.append({"cells": [[0, 0, [path], 1]], "area": kind, "map": "forced", "count": 1, "maps": []})
    return occupied
