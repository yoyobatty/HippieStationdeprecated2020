"""Pieces settled where the stock maps put them (gen/learn/placestudy.py): a piece of a family that stands against a
wall 90%+ of the time on the stock maps and stands off it here, or one no one can reach, moves to the nearest free
spot of its room against a wall, off the doors' fronts, with a free tile to use it from, where the room's doors still
reach as much of its free floor as before. What lies on it (a table's papers, a bed's sheet) moves with it.

    python tools/mapforge/gen/learn/settle.py <dmm> [out.dmm]
    from gen.learn import settle; settle.settle(m, log)        # build.py: before the networks (bins get their pipes)

crew 100 seed 7 f11: 33 pieces off the wall per 1000 against the stock maps' 4-9, 16.5 unreachable against 5-11.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", ".."))
from forge import corpus as CO, dmm, function as FN  # noqa: E402
import placestudy as PS  # noqa: E402

N4 = PS.N4
WALL_SHARE = 0.9
REACH_SHARE = 0.95
# what never moves: machines tied to their neighbours or their own build (forge/function.py LINKS partners, the
# gravity generator, telecomms arrays, the engine's, pipes' machines)
FIXED = ("/obj/machinery/clonepod", "/obj/machinery/computer/cloning", "/obj/machinery/dna_scannernew",
         "/obj/machinery/computer/scan_consolenew", "/obj/machinery/computer/operating", "/obj/structure/table/optable",
         "/obj/machinery/nanite", "/obj/machinery/computer/nanite", "/obj/machinery/teleport", "/obj/machinery/computer/teleporter",
         "/obj/machinery/gravity_generator", "/obj/machinery/telecomms", "/obj/machinery/power", "/obj/machinery/atmospherics",
         "/obj/machinery/portable_atmospherics", "/obj/machinery/field", "/obj/machinery/the_singularitygen",
         "/obj/machinery/mech_bay_recharge_port", "/obj/machinery/computer/mech_bay_power_console",
         "/obj/machinery/gateway", "/obj/structure/transit_tube", "/obj/machinery/rnd/server", "/obj/machinery/shieldgen",
         "/obj/machinery/nuclearbomb",
         # partners found in range, not beside: the experimentor links to its console within 3 tiles (settle moved them
         # 4 apart and every experiment failed, Bot Shift f14)
         "/obj/machinery/rnd/experimentor", "/obj/machinery/computer/rdconsole/experiment",
         "/obj/machinery/computer/rdconsole/core", "/obj/machinery/rnd/destructive_analyzer",
         "/obj/machinery/rnd/production", "/obj/machinery/computer/rdservercontrol", "/obj/machinery/doppler_array",
         "/obj/machinery/computer/mecha", "/obj/machinery/computer/camera_advanced", "/obj/machinery/monkey_recycler",
         "/obj/machinery/processor/slime", "/obj/machinery/smartfridge/extract")


RESERVED = set()     # tiles a multi-tile machine fills at runtime (the gravity generator's 3x3): never a spot


def reserve(m):
    """RESERVED from the map: each gravity generator's footprint (gen/audit.py BIG)."""
    RESERVED.clear()
    for (x, y, z), t in m.tiles.items():
        if any(o.path.startswith("/obj/machinery/gravity_generator/main") for o in t.objs):
            RESERVED.update((x + dx, y + dy) for dx in (-1, 0, 1) for dy in (0, 1, 2))


def _free_tile(t, q=None):
    if q is not None and q in RESERVED:
        return False
    return t is not None and t.tpath.startswith("/turf/open") and not CO.solid(t) and not PS._door(t) and not any(
        o.path.startswith(("/obj/structure", "/obj/machinery", "/obj/item", "/mob")) and not CO.mounted(o)
        and not o.path.startswith(PS.SKIP_OBJ) for o in t.objs)


def _reach(m, F, doors):
    """Free floor of the room reached from its doors' fronts."""
    fronts = {p for p in F for dx, dy in N4 if (p[0] + dx, p[1] + dy) in doors}
    free = {p for p in F if not PS._dense(m.get(*p))}
    seen = set(fronts & free)
    q = list(seen)
    while q:
        p = q.pop()
        for dx, dy in N4:
            n = (p[0] + dx, p[1] + dy)
            if n in free and n not in seen:
                seen.add(n)
                q.append(n)
    return seen, free, fronts


def settle(m, log=print):
    reserve(m)
    ST_ = PS.study()
    S = ST_["fam"]
    W = ST_.get("where", {})
    moved = 0
    hd = PS.hall_dist(m)
    for area, F in PS.pieces_of(m):
        doors = {(p[0] + dx, p[1] + dy) for p in F for dx, dy in N4 if PS._door(m.get(p[0] + dx, p[1] + dy))}
        if not doors:
            continue
        xs, ys = [p[0] for p in F], [p[1] for p in F]
        span = max(1, (max(xs) - min(xs)) + (max(ys) - min(ys)))

        front = PS.front_doors(m, F, doors, hd)

        def depth(q, doors=front, span=span):
            return min(abs(q[0] - d[0]) + abs(q[1] - d[1]) for d in doors) / float(span)
        for _ in range(3):
            seen, free, fronts = _reach(m, F, doors)
            bad = []
            for p in sorted(F):
                t = m.get(*p)
                for o in t.objs:
                    if not o.path.startswith(("/obj/structure", "/obj/machinery")) or o.path.startswith(PS.SKIP_OBJ) \
                            or o.path.startswith(FIXED) or CO.mounted(o):
                        continue
                    c = S.get(PS.family(o.path))
                    if not c or c["n"] < 15:
                        continue
                    walls = sum(1 for dx, dy in N4 if PS._solid(m.get(p[0] + dx, p[1] + dy)) and (p[0] + dx, p[1] + dy) not in doors)
                    reach = p in seen or any((p[0] + dx, p[1] + dy) in seen for dx, dy in N4)
                    # where the stock rooms of the type keep it (front by the door, back), when they agree
                    band = None
                    w = W.get("%s|%s" % (area, PS.family(o.path)))
                    if w and PS.family(o.path) not in ("/obj/structure/table", "/obj/structure/chair"):
                        lo, hi = PS._q(w, 0.1), PS._q(w, 0.9)
                        if hi - lo <= 0.4:
                            band = (lo, hi)
                    off_band = band is not None and (depth(p) < band[0] - 0.25 or depth(p) > band[1] + 0.25)
                    if (walls == 0 and c["wall"] / float(c["n"]) >= WALL_SHARE) or \
                            (not reach and c["reach"] / float(c["n"]) >= REACH_SHARE) or off_band:
                        bad.append((p, o, band))
            if not bad:
                break
            for p, o, band in bad:
                spot = _spot(m, F, doors, p, o, band, depth)
                if spot is None:
                    continue
                t = m.get(*p)
                # the piece, and what lies on it if it holds things (a table's or a rack's load, a bed's sheet)
                carry = [o] + ([i for i in t.objs if i.path.startswith("/obj/item") and not CO.mounted(i)]
                               if o.path.startswith(("/obj/structure/table", "/obj/structure/rack", "/obj/structure/bed"))
                               else [])
                t.objs = [i for i in t.objs if not any(i is c_ for c_ in carry)]
                m.get(*spot).objs.extend(carry)
                moved += 1
        # a piece still no one reaches (a console boxed in a corner by a filing cabinet and another console, f19's
        # bridge; a fixed piece never moves itself): a dense neighbour of it moves away when that opens it up
        seen, free, fronts = _reach(m, F, doors)
        for p in sorted(F):
            t = m.get(*p)
            want = [o for o in t.objs if o.path.startswith(("/obj/structure", "/obj/machinery")) and not CO.mounted(o)
                    and not o.path.startswith(PS.SKIP_OBJ) and (S.get(PS.family(o.path)) or {}).get("n", 0) >= 15
                    and S[PS.family(o.path)]["reach"] / float(S[PS.family(o.path)]["n"]) >= REACH_SHARE]
            if not want or p in seen or any((p[0] + dx, p[1] + dy) in seen for dx, dy in N4):
                continue
            for dx, dy in N4:
                b = (p[0] + dx, p[1] + dy)
                if b not in F or b in free:
                    continue
                tb = m.get(*b)
                blk = [o for o in tb.objs if FN.is_dense(o) and not o.path.startswith(FIXED) and not CO.mounted(o)
                       and not o.path.startswith(PS.SKIP_OBJ)]
                if len(blk) != 1 or not any((b[0] + ex, b[1] + ey) in seen for ex, ey in N4):
                    continue
                o = blk[0]
                spot = _spot(m, F, doors, b, o)
                if spot is None:
                    continue
                carry = [o] + ([i for i in tb.objs if i.path.startswith("/obj/item") and not CO.mounted(i)]
                               if o.path.startswith(("/obj/structure/table", "/obj/structure/rack")) else [])
                tb.objs = [i for i in tb.objs if not any(i is c_ for c_ in carry)]
                m.get(*spot).objs.extend(carry)
                moved += 1
                seen, free, fronts = _reach(m, F, doors)
                break
        # pockets: free floor the doors don't reach (behind a desk, in a corner past a locker; the stock rooms of most
        # types have none): the piece sealing one off moves elsewhere in the room
        for _ in range(3):
            seen, free, fronts = _reach(m, F, doors)
            pocket = free - seen
            if not pocket:
                break
            opened = False
            for q in sorted(pocket):
                for dx, dy in N4:
                    b = (q[0] + dx, q[1] + dy)
                    if b not in F or b in free:
                        continue
                    if not any((b[0] + ex, b[1] + ey) in seen for ex, ey in N4):
                        continue
                    t = m.get(*b)
                    for o in list(t.objs):
                        if not FN.is_dense(o) or o.path.startswith(FIXED) or CO.mounted(o) or o.path.startswith(PS.SKIP_OBJ):
                            continue
                        spot = _spot(m, F, doors, b, o)
                        if spot is None:
                            continue
                        carry = [o] + ([i for i in t.objs if i.path.startswith("/obj/item") and not CO.mounted(i)]
                                       if o.path.startswith(("/obj/structure/table", "/obj/structure/rack")) else [])
                        t.objs = [i for i in t.objs if not any(i is c_ for c_ in carry)]
                        m.get(*spot).objs.extend(carry)
                        moved += 1
                        opened = True
                        break
                    if opened:
                        break
                if opened:
                    break
            if not opened:
                break
    log("settle: %d pieces moved against a wall or within reach, as the stock maps place them" % moved)
    return moved


def _spot(m, F, doors, p, o, band=None, depth=None):
    """The nearest free spot of the room against a wall, off the door fronts, beside free floor, that keeps the room's
    reached floor at least as big (the piece taken off p first); with a depth band (the stock rooms' spread of where
    the piece stands from the door), spots nearer the band first, and only a move that gets it nearer."""
    t = m.get(*p)
    t.objs = [i for i in t.objs if i is not o]
    try:
        seen0, free0, fronts = _reach(m, F, doors)
        cands = []
        for q in F:
            if q == p or q in fronts or not _free_tile(m.get(*q), q):
                continue
            walls = [d for d in N4 if PS._solid(m.get(q[0] + d[0], q[1] + d[1])) and (q[0] + d[0], q[1] + d[1]) not in doors]
            if not walls:
                continue
            use = [(q[0] + dx, q[1] + dy) for dx, dy in N4 if (q[0] + dx, q[1] + dy) in seen0]
            if not use:
                continue
            off = 0
            if band is not None:
                dq = depth(q)
                off = round(20 * max(0.0, band[0] - dq, dq - band[1]))
            cands.append((off, abs(q[0] - p[0]) + abs(q[1] - p[1]), q))
        cands.sort()
        if band is not None:
            cur = round(20 * max(0.0, band[0] - depth(p), depth(p) - band[1]))
            if cur > 5:
                cands = [c for c in cands if c[0] < cur]
        dense = FN.is_dense(o)
        # the room's other pieces someone reaches now (a free tile beside them reached)
        used0 = {q for q in F if q not in free0 and any((q[0] + dx, q[1] + dy) in seen0 for dx, dy in N4)}
        for _, _, q in cands[:40]:
            if not dense:
                return q
            m.get(*q).objs.append(o)
            seen1, free1, _ = _reach(m, F, doors)
            m.get(*q).objs.remove(o)
            # no free tile left unreached that was reached before (a looser test cut 11% of rooms against 5%), and no
            # piece boxed in that was reached (settle's moves boxed three of f19's bridge consoles into corners)
            if (free1 - seen1) - (free0 - seen0):
                continue
            if any(not any((u[0] + dx, u[1] + dy) in seen1 for dx, dy in N4) for u in used0 if u != q):
                continue
            return q
        return None
    finally:
        t.objs.append(o)


if __name__ == "__main__":
    m = dmm.read(sys.argv[1])
    print("before", PS.summary(PS.check(m)))
    settle(m)
    print("after ", PS.summary(PS.check(m)))
    if len(sys.argv) > 2:
        dmm.write(m, sys.argv[2])
