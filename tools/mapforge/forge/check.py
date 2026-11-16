"""Static checks on a build: what a reviewer of a map PR would look for.

- every area has one APC, an air alarm, a vent and a scrubber, and a fire alarm by its doors
- every vent and scrubber is piped back to the station network; every APC is cabled to the grid
- every floor tile can be walked to from outside the zone (doors count as passable), every machine is reachable
- no two dense objects share a tile; nothing dense sits on a carried-over disposal bin
- tiles only change inside the old footprint
- inventory: gameplay objects of the old rooms that the new rooms lack (and new ones they gained)
"""
from collections import Counter, deque

from forge import kit
from forge.kit import CARD, DELTA, OPP

DENSE_EXTRA = ("/obj/machinery/disposal/bin",)
IGNORE_INV = ("/obj/machinery/atmospherics", "/obj/structure/cable", "/obj/effect/turf_decal", "/obj/machinery/light",
              "/obj/machinery/door/firedoor", "/obj/machinery/airalarm", "/obj/machinery/firealarm", "/obj/machinery/power/apc",
              "/obj/machinery/light_switch", "/obj/machinery/camera", "/obj/structure/disposalpipe", "/obj/structure/extinguisher_cabinet",
              "/obj/machinery/newscaster", "/obj/effect/spawner/structure/window", "/obj/structure/window", "/obj/structure/table",
              "/obj/structure/chair", "/obj/effect/decal", "/obj/structure/grille", "/obj/item/radio/intercom",
              "/obj/item/twohanded/required/kirbyplants", "/obj/structure/railing")


def is_dense(a):
    if kit.dense_types() is not None:
        return kit.is_dense_atom(a)
    return _is_dense_hint(a)


def _is_dense_hint(a):
    if a.path.startswith(("/obj/machinery/door/firedoor", "/obj/machinery/door/window", "/obj/machinery/door/poddoor/preopen",
                          "/obj/machinery/door/poddoor/shutters/preopen")):
        return False
    if a.path.startswith("/obj/machinery/door"):
        return False
    if a.path.startswith(("/obj/machinery/holopad", "/obj/structure/railing", "/obj/structure/bed/dogbed",
                          "/obj/machinery/computer/security/telescreen")):
        return False
    return a.path.startswith(kit.DENSE_HINTS + DENSE_EXTRA) or a.path.startswith("/obj/structure/chair/sofa")


class _Empty:
    objs = []


dmm_empty = _Empty()


def run(b):
    probs, info = [], []
    m = b.m
    zone = b.zone

    # --- per-area essentials (a remodel keeps the rooms' own infrastructure as it was)
    for area in ([] if getattr(b, "keep_infra", False) else [a for a in b.areas() if not b.roomdef_for_area(a).get("bare")]):
        tiles = [p for p in zone if m.get(*p).apath == area]
        objs = [o for p in tiles for o in m.get(*p).objs]
        n = lambda pre: sum(1 for o in objs if o.isa(pre))
        name = b.roomdef_for_area(area).get("name", area)
        if n("/obj/machinery/power/apc") + (1 if b.remote_apc(area) else 0) != 1 and b.roomdef_for_area(area).get("apc", True):
            probs.append("%s: %d APCs" % (name, n("/obj/machinery/power/apc")))
        for pre, what in (("/obj/machinery/airalarm", "air alarm"), ("/obj/machinery/atmospherics/components/unary/vent_pump", "vent"),
                          ("/obj/machinery/atmospherics/components/unary/vent_scrubber", "scrubber"), ("/obj/machinery/light", "light")):
            if what in ("vent", "scrubber") and (not getattr(b.bp, "ATMOS", True) or b.roomdef_for_area(area).get("vents") == 0):
                continue
            if n(pre) == 0:
                probs.append("%s: no %s" % (name, what))
        if b.doors_into(area) and n("/obj/machinery/firealarm") == 0:
            probs.append("%s: no fire alarm" % name)

    # --- pipe networks: each vent must reach a port through matching masks
    for cls in ("supply", "scrubbers"):
        masks = {}
        bare = {p for p in zone if b.room.get(p) and b.roomdefs[b.room[p]].get("bare")}
        for p in zone:
            if p in bare:
                continue
            for o in m.get(*p).objs:
                if kit.pipe_class(o.path) == cls:
                    masks[p] = masks.get(p, 0) | kit.pipe_mask(o)
        ports = {p for p, d in b.ports[cls]}
        seen, q = set(), deque(p for p in ports if p in masks)
        seen.update(q)
        while q:
            p = q.popleft()
            for d in CARD:
                if masks[p] & d:
                    nx = (p[0] + DELTA[d][0], p[1] + DELTA[d][1])
                    if nx in masks and masks[nx] & OPP[d] and nx not in seen:
                        seen.add(nx)
                        q.append(nx)
        orphans = [p for p in masks if p not in seen]
        if orphans:
            probs.append("%s: %d pipe tiles not joined to the station (e.g. %d,%d)" % (cls, len(orphans), *orphans[0]))
        from forge import atmos as _atm
        # dangling ends: every class atom's sides must meet a partner that really joins it (any device or layer
        # manifold on the same layer counts), inside the zone and across its edge
        for p in masks:
            for a in [o for o in m.get(*p).objs if kit.pipe_class(o.path) == cls]:
                for d in CARD:
                    if not _atm.mask(a) & d:
                        continue
                    q = (p[0] + DELTA[d][0], p[1] + DELTA[d][1])
                    if not any(_atm.joins(a, o, d) for o in _atm.atoms(m.get(*q))):
                        probs.append("%s: open pipe end at %d,%d facing %s" % (cls, p[0], p[1], kit.NAME[d]))
        for p in zone:
            if p in bare:
                continue
            for d in CARD:
                q = (p[0] + DELTA[d][0], p[1] + DELTA[d][1])
                if q in zone:
                    continue
                for o in _atm.atoms(m.get(*q)):
                    if kit.pipe_class(o.path) == cls and _atm.mask(o) & OPP[d] and                             not any(_atm.joins(o, a, OPP[d]) for a in _atm.atoms(m.get(*p))):
                        probs.append("%s: outside pipe at %d,%d points into the zone at a tile with no pipe" % (cls, q[0], q[1]))
    # --- every other pipe loop (toxins, servers, xenobiology...): no open ends, no leaks into the scrubbers
    from forge import atmos
    def untouched(p, a):
        return any(o.text() == a.text() for o in b.orig.get(p, dmm_empty).objs)
    for pr in atmos.check(m, zone, ignore=untouched):
        if pr.startswith("open supply") or pr.startswith("open scrubbers"):
            continue  # reported above with the station networks
        probs.append(pr)

    # --- cables: every APC tile connected to a cable port
    cab = {p for p in zone if m.get(*p).has(kit.CABLE)}
    ports = {p for p, d in b.ports["cable"]}
    seen, q = set(p for p in ports if p in cab), deque(p for p in ports if p in cab)
    while q:
        p = q.popleft()
        for d in CARD:
            nx = (p[0] + DELTA[d][0], p[1] + DELTA[d][1])
            if nx in cab and nx not in seen:
                seen.add(nx)
                q.append(nx)
    for a in (getattr(b, "apc_tiles", []) if getattr(b.bp, "POWER", True) else []):
        if a not in seen:
            probs.append("APC at %d,%d not cabled to the grid" % a)

    # --- walking
    def walkable(p):
        t = m.get(*p)
        if t is None or t.tpath.startswith("/turf/closed") or t.tpath.startswith("/turf/open/space"):
            return False
        if t.has("/obj/effect/spawner/structure/window") or t.has("/obj/structure/grille"):
            return False
        return not any(is_dense(o) for o in t.objs)
    def walkable_tile(t):
        if t.tpath.startswith("/turf/closed") or t.tpath.startswith("/turf/open/space"):
            return False
        if t.has("/obj/effect/spawner/structure/window") or t.has("/obj/structure/grille"):
            return False
        return not any(is_dense(o) for o in t.objs)

    def dense_name(t):
        d = [o for o in t.objs if is_dense(o)]
        return d[0].path.rsplit("/", 1)[-1] if d else "wall"
    starts = [p for p in zone for d in CARD
              if (p[0] + DELTA[d][0], p[1] + DELTA[d][1]) not in zone and walkable((p[0] + DELTA[d][0], p[1] + DELTA[d][1]))
              and walkable(p)]
    if not starts:  # a standalone build: walk in from its halls
        starts = [p for p in zone if m.get(*p).apath.startswith("/area/hallway") and walkable(p)]
    # entrances through kept doors: outside tiles next to the zone count as reachable
    reach = set(starts)
    q = deque(starts)
    while q:
        p = q.popleft()
        for d in CARD:
            nx = (p[0] + DELTA[d][0], p[1] + DELTA[d][1])
            if nx in reach:
                continue
            if nx in zone and walkable(nx):
                reach.add(nx)
                q.append(nx)
            elif nx not in zone and walkable(nx):
                # step through a kept tile (shell door) back into the zone
                for d2 in CARD:
                    n2 = (nx[0] + DELTA[d2][0], nx[1] + DELTA[d2][1])
                    if n2 in zone and n2 not in reach and walkable(n2):
                        reach.add(n2)
                        q.append(n2)
    floors = [p for p in zone if walkable(p)]
    # squeezes: two open tiles touching corners where both tiles between them are blocked (a machine diagonal to a
    # tray, say). You can't step between them, so a person walks round; flag it when that walk is long.
    fset = set(floors)

    def walk_dist(a, b, cap=40):
        seen, q = {a: 0}, deque([a])
        while q:
            p = q.popleft()
            if p == b:
                return seen[p]
            if seen[p] >= cap:
                continue
            for d in CARD:
                n = (p[0] + DELTA[d][0], p[1] + DELTA[d][1])
                if n not in seen and (n in fset or (n not in zone and walkable(n))):
                    seen[n] = seen[p] + 1
                    q.append(n)
        return None
    seen_pairs = set()
    for p in floors:
        for dx, dy in ((1, 1), (1, -1)):
            q = (p[0] + dx, p[1] + dy)
            if q not in fset or (p, q) in seen_pairs:
                continue
            a, c = (p[0] + dx, p[1]), (p[0], p[1] + dy)
            ta, tc = m.get(*a), m.get(*c)
            blocked = lambda t: t is None or not walkable_tile(t)
            if blocked(ta) and blocked(tc) and any(is_dense(o) for o in ta.objs) and any(is_dense(o) for o in tc.objs):
                seen_pairs.add((p, q))
                dist = walk_dist(p, q)
                if dist is None or dist > 6:
                    probs.append("squeeze at %d,%d / %d,%d: %s and %s touch corners, the way round is %s steps" % (
                        p[0], p[1], q[0], q[1], dense_name(ta), dense_name(tc), dist if dist else "40+"))
    stuck = [p for p in floors if p not in reach]
    if stuck:
        probs.append("%d floor tiles can't be walked to: %s" % (len(stuck), " ".join("%d,%d" % p for p in sorted(stuck)[:12])))
    for p in zone:
        t = m.get(*p)
        dense = [o for o in t.objs if is_dense(o)]
        if dense and not any((p[0] + dx, p[1] + dy) in reach for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy):
            probs.append("unreachable %s at %d,%d" % (dense[0].path.rsplit("/", 1)[-1], *p))
        if len(dense) > 1 and not any(o.path.startswith("/obj/structure/table") for o in dense) and not all(o.path.startswith(("/obj/structure/table", "/obj/machinery/door")) or
                                      o.path.startswith(("/obj/machinery/microwave", "/obj/machinery/reagentgrinder"))
                                      for o in dense[1:]):
            probs.append("stacked dense %s at %d,%d" % (",".join(o.path.rsplit("/", 1)[-1] for o in dense), *p))
        if t.tpath.startswith("/turf/closed") and any(o.path.startswith(("/obj/machinery/disposal/bin",)) for o in t.objs):
            probs.append("disposal bin under a wall at %d,%d" % p)

    # --- every airlock (in the zone or on its edge) has clear floor on both sides of its passage
    door_tiles = set()
    for p in zone:
        for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (p[0] + dx, p[1] + dy)
            qt = m.get(*q)
            if qt is not None and qt.has("/obj/machinery/door/airlock"):
                door_tiles.add(q)
    for dpos in sorted(door_tiles):
        # the passage runs across the wall the door sits in
        closed = {d for d in CARD if (m.get(dpos[0] + DELTA[d][0], dpos[1] + DELTA[d][1]) is None
                                      or m.get(dpos[0] + DELTA[d][0], dpos[1] + DELTA[d][1]).tpath.startswith("/turf/closed"))}
        if closed & {1, 2}:
            axis = (4, 8)
        elif closed & {4, 8}:
            axis = (1, 2)
        else:
            axis = CARD
        for d in axis:
            n = (dpos[0] + DELTA[d][0], dpos[1] + DELTA[d][1])
            nt = m.get(*n)
            if n not in zone or nt is None or nt.tpath.startswith("/turf/closed"):
                continue
            block = [o for o in nt.objs if is_dense(o)]
            if block:
                probs.append("%s at %d,%d stands in the doorway of the airlock at %d,%d"
                             % (block[0].path.rsplit("/", 1)[-1], n[0], n[1], dpos[0], dpos[1]))

    # --- tall furniture stands against a wall, not glass (human maps: vendors 7%, lockers 11%, bookcases 3% on glass)
    from forge.furnish import TALL, WALL_BOUND
    def tkind(q):
        qt = m.get(*q)
        if qt is None:
            return "void"
        if qt.has("/obj/machinery/door"):
            return "door"
        if qt.has("/obj/effect/spawner/structure/window") or qt.has("/obj/structure/grille") or qt.has("/obj/structure/window"):
            return "glass"
        if qt.tpath.startswith("/turf/closed"):
            return "wall"
        return "floor"
    for p in zone:
        t = m.get(*p)
        tall = [o for o in t.objs if o.path.startswith(TALL) and abs(o.num("pixel_x")) < 16 and abs(o.num("pixel_y")) < 16]
        if not tall:
            continue
        ks = {d: tkind((p[0] + DELTA[d][0], p[1] + DELTA[d][1])) for d in CARD}
        # vendors, lockers, suit storage, tanks, lathes stand loose in a room 0-4% of the time on human maps
        if tall[0].path.startswith(WALL_BOUND) and not ({"wall", "glass"} & set(ks.values())):
            probs.append("%s at %d,%d stands loose in the room, not against a wall" % (tall[0].path.rsplit("/", 1)[-1], p[0], p[1]))
        if "glass" in ks.values() and "wall" not in ks.values():
            gd = next(d for d, k in ks.items() if k == "glass")
            probs.append("%s at %d,%d stands against glass (%s), not a wall" % (tall[0].path.rsplit("/", 1)[-1], p[0], p[1], kit.NAME[gd]))

    # --- an R&D console links the analyzer/lathes/imprinter/experimentor it can see within 3 tiles (2020 tg)
    from forge.furnish import RND_MACHINE, RND_CONSOLE
    consoles = [(p, m.get(*p).apath) for p in zone if any(o.path.startswith(RND_CONSOLE) for o in m.get(*p).objs)]
    for p in zone:
        t = m.get(*p)
        for o in t.objs:
            if o.path.startswith(RND_MACHINE) and not o.path.endswith("/department") and "/department/" not in o.path:
                if not any(a == t.apath and max(abs(p[0] - q[0]), abs(p[1] - q[1])) <= 3 for q, a in consoles):
                    probs.append("%s at %d,%d is more than 3 tiles from an R&D console in its room (won't link)"
                                 % (o.path.rsplit("/", 1)[-1], p[0], p[1]))

    # --- wall pieces stand on the floor in front of their wall, never on the wall turf itself
    for p in zone:
        t = m.get(*p)
        if t.tpath.startswith("/turf/closed"):
            for o in t.objs:
                if o.path.startswith(("/obj/structure/sign", "/obj/machinery/status_display", "/obj/machinery/firealarm",
                                      "/obj/machinery/airalarm", "/obj/machinery/light_switch", "/obj/structure/extinguisher_cabinet",
                                      "/obj/machinery/newscaster", "/obj/item/radio/intercom", "/obj/structure/noticeboard",
                                      "/obj/structure/mirror", "/obj/machinery/power/apc")) and "barsign" not in o.path:
                    probs.append("%s at %d,%d sits on the wall tile itself (should stand in front of it, shifted onto it)"
                                 % (o.path.rsplit("/", 1)[-1], p[0], p[1]))

    # --- wall pieces need a wall behind them (not a door, window or floor)
    from forge.corpus import mount_side
    for p in zone:
        t = m.get(*p)
        for o in t.objs:
            if abs(o.num("pixel_x")) < 16 and abs(o.num("pixel_y")) < 16:
                continue
            if o.path.startswith(("/obj/effect", "/obj/item/twohanded")):
                continue
            if o.path.startswith("/obj/machinery/door"):
                continue
            if any(a.text() == o.text() for a in b.orig.get(p, dmm_empty).objs):
                continue  # was there before, untouched
            d = mount_side(o)
            q = (p[0] + DELTA[d][0], p[1] + DELTA[d][1])
            qt = m.get(*q)
            if qt is None or not qt.tpath.startswith("/turf/closed") or qt.has("/obj/machinery/door"):
                if qt is not None and qt.has("/obj/machinery/door"):
                    what = "door"
                elif qt is not None and (qt.has("/obj/structure/grille") or qt.has("/obj/effect/spawner/structure/window")):
                    what = "window"
                else:
                    what = "open floor"
                probs.append("floating %s at %d,%d: hangs on a %s to the %s" % (o.path.rsplit("/", 1)[-1], p[0], p[1], what, kit.NAME[d]))

    # --- everything the blueprint placed by hand is still there at the end (no later pass ate it)
    lost_bp = []
    for p in zone:
        try:
            sp = b.spec(p)
        except Exception:
            continue
        want = [e if isinstance(e, str) else e[0] for e in sp.get("obj", [])]
        have = {o.path for o in m.get(*p).objs}
        for w in want:
            if w.startswith(("/obj/effect/landmark", "/obj/machinery/door/firedoor")):
                continue
            if w not in have:
                lost_bp.append("%s at %d,%d" % (w.rsplit("/", 1)[-1], p[0], p[1]))
    if lost_bp:
        probs.append("%d hand-placed objects went missing: %s" % (len(lost_bp), ", ".join(lost_bp[:8])))

    # --- no doubled walls: floor, wall, wall, floor in a line (a room stopped a tile short of an existing wall)
    def wk(q):
        t = m.get(*q)
        if t is None or t.tpath.startswith("/turf/open/space"):
            return " "
        if t.has("/obj/machinery/door") or t.has("/obj/effect/spawner/structure/window") or t.has("/obj/structure/grille"):
            return "="
        return "#" if t.tpath.startswith("/turf/closed") else "."
    dbl = set()
    for p in zone:
        for dx, dy in ((1, 0), (0, 1)):
            line_ = [wk((p[0] + i * dx, p[1] + i * dy)) for i in (-1, 0, 1, 2)]
            if line_ == [".", "#", "#", "."]:
                q = (p[0] + dx, p[1] + dy)
                ow = lambda r: (b.orig[r] if r in b.orig else m.get(*r))
                if all(ow(r) is not None and ow(r).tpath.startswith("/turf/closed") for r in (p, q)):
                    continue  # the outline's own thickness, as the original map has it
                dbl.add(p)
    if dbl:
        probs.append("%d doubled wall spots, e.g. %s" % (len(dbl), " ".join("%d,%d" % q for q in sorted(dbl)[:6])))

    # --- two different areas meeting floor to floor with no wall, door or glass between: a room left open
    leaks = set()
    for p in zone:
        tp = m.get(*p)
        if tp is None or not tp.tpath.startswith("/turf/open") or tp.has("/obj/machinery/door") or tp.has("/obj/effect/spawner/structure/window"):
            continue
        for d in (1, 4):
            q = (p[0] + DELTA[d][0], p[1] + DELTA[d][1])
            tq = m.get(*q)
            if tq is None or not tq.tpath.startswith("/turf/open") or tq.tpath.startswith("/turf/open/space") or                     tq.has("/obj/machinery/door") or tq.has("/obj/effect/spawner/structure/window"):
                continue
            ok_pairs = {frozenset(x) for x in getattr(b.bp, "OPEN_SEAMS", [])}
            if tp.apath != tq.apath and not tp.apath.startswith("/area/space") and not tq.apath.startswith("/area/space")                     and frozenset((tp.apath, tq.apath)) not in ok_pairs:
                leaks.add((p, q, tp.apath.rsplit("/", 1)[-1], tq.apath.rsplit("/", 1)[-1]))
    if leaks:
        probs.append("%d open seams between different rooms, e.g. %s" % (len(leaks), "; ".join(
            "%d,%d %s / %d,%d %s" % (a[0], a[1], na, c[0], c[1], nc) for a, c, na, nc in sorted(leaks)[:4])))

    # --- an airlock sits in a wall line: wall (or glass/door) on two opposite sides, open floor on the other two
    def solidish(q):
        t = m.get(*q)
        return t is None or t.tpath.startswith("/turf/closed") or t.has("/obj/effect/spawner/structure/window")             or t.has("/obj/structure/grille") or t.has("/obj/machinery/door/airlock") or t.has("/obj/machinery/door/poddoor")
    for p in zone:
        t = m.get(*p)
        if not t.has("/obj/machinery/door/airlock"):
            continue
        ns = solidish((p[0], p[1] + 1)) and solidish((p[0], p[1] - 1))
        ew = solidish((p[0] + 1, p[1])) and solidish((p[0] - 1, p[1]))
        if not (ns or ew):
            probs.append("airlock at %d,%d isn't set in a wall: floor around it" % p)

    # --- walls join edge to edge: two wall pieces touching only at a corner float (the user: never diagonal gaps)
    def wallish(q):
        t = m.get(*q)
        return t is not None and (t.tpath.startswith("/turf/closed") or t.has("/obj/effect/spawner/structure/window")
                                  or t.has("/obj/structure/grille") or t.has("/obj/machinery/door/airlock"))
    diag = set()
    for p in zone:
        if not wallish(p):
            continue
        for dx, dy in ((1, 1), (1, -1)):
            q = (p[0] + dx, p[1] + dy)
            if wallish(q) and not wallish((p[0] + dx, p[1])) and not wallish((p[0], p[1] + dy)):
                was = lambda r: b.orig[r] if r in b.orig else m.get(*r)
                def owall(r):
                    t = was(r)
                    return t is not None and (t.tpath.startswith("/turf/closed") or t.has("/obj/effect/spawner/structure/window")
                                              or t.has("/obj/machinery/door/airlock"))
                if q not in zone and all(owall(r) == wallish(r) for r in (p, q, (p[0] + dx, p[1]), (p[0], p[1] + dy))):
                    continue
                diag.add((p, q))
    if diag:
        probs.append("%d wall corners joined only diagonally, e.g. %s" % (len(diag), "; ".join(
            "%d,%d-%d,%d" % (a[0], a[1], c[0], c[1]) for a, c in sorted(diag)[:5])))
    # --- tables that start on a wall run along walls; a run never sticks out into the room
    tables = {p for p in zone if m.get(*p).has("/obj/structure/table")}
    seen_t = set()
    jut = []
    for p in sorted(tables):
        if p in seen_t:
            continue
        grp, q2 = {p}, [p]
        seen_t.add(p)
        while q2:
            c = q2.pop()
            for d in CARD:
                n = (c[0] + DELTA[d][0], c[1] + DELTA[d][1])
                if n in tables and n not in seen_t:
                    seen_t.add(n)
                    grp.add(n)
                    q2.append(n)
        touching = {c for c in grp if any(wallish((c[0] + DELTA[d][0], c[1] + DELTA[d][1])) for d in CARD)}
        counter = any(m.get(c[0] + DELTA[d][0], c[1] + DELTA[d][1]) is not None and
                      m.get(c[0] + DELTA[d][0], c[1] + DELTA[d][1]).has("/obj/machinery/door/window") for c in grp for d in CARD)             or any(m.get(*c).has("/obj/machinery/door/window") for c in grp)
        if touching and len(grp) > 1 and not counter:
            jut += [c for c in grp if c not in touching]
    if jut:
        probs.append("%d wall-run table tiles stick out into the room, e.g. %s" % (len(jut), " ".join("%d,%d" % c for c in sorted(jut)[:6])))

    # --- footprint
    areas = {rd["area"] for rd in b.roomdefs.values()} | set(getattr(b.bp, "FOOTPRINT", ()))
    out = [p for p in zone if b.orig[p].apath not in areas and b.base_path != "blank"]
    if out:
        probs.append("%d tiles changed outside the old footprint, e.g. %d,%d (%s)" % (len(out), *out[0], b.orig[out[0]].apath))

    # --- inventory
    def inv(tiles):
        c = Counter()
        for t in tiles:
            for o in t.objs:
                if not o.path.startswith(IGNORE_INV):
                    c[o.path] += 1
        return c
    old = inv(b.orig.values())
    new = inv(m.get(*p) for p in zone)
    lost = {k: v - new.get(k, 0) for k, v in old.items() if v > new.get(k, 0)}
    gained = {k: v - old.get(k, 0) for k, v in new.items() if v > old.get(k, 0)}
    if lost:
        info.append("inventory lost:   " + ", ".join("%s x%d" % (k.replace("/obj/", "").replace("/mob/living/", ""), v) for k, v in sorted(lost.items())))
    if gained:
        info.append("inventory gained: " + ", ".join("%s x%d" % (k.replace("/obj/", "").replace("/mob/living/", ""), v) for k, v in sorted(gained.items())))
    info.append("checks: %d problems" % len(probs))
    return {"problems": probs, "info": info}
