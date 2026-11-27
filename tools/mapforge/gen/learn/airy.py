"""Rooms kept airy: no 1-tile squeezes between pieces where the stock maps keep their walkways open.

The user 2026-11-26: "it could be a bit more airy, some of the structures block walking and only give 1 tile paths,
bigger departments should shy away from claustrophobic item placement".

A pinch is a free floor tile of a room blocked on both sides along one axis (wall, glass or a dense piece left and
right, or above and below): a 1-wide passage. Share of free floor in pinches, by room size:

    room tiles   stock (Meta, Box, Delta, Hippie, Pubby)   ours (f23b, f26b)
    12-39        0.14-0.21                                 0.26-0.28
    40-79        0.12-0.14                                 0.17-0.22
    80+          0.03-0.06                                 0.13-0.15

For each room over its class's stock level (TARGET), the pieces beside pinch tiles move, one at a time, to the free
spot of the room that lowers its pinch count most (against a wall, off door fronts, every free tile and every piece
still reached from the doors: gen/learn/settle.py's tests); a spare piece (density.OPTIONAL) that can't move goes.

    python tools/mapforge/gen/learn/airy.py <dmm> [out.dmm]
    from gen.learn import airy; airy.fix(m, log)        # build.py: after settle/density, and again after the passes
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", ".."))
from forge import corpus as CO, dmm, function as FN  # noqa: E402
import placestudy as PS  # noqa: E402
import settle as ST  # noqa: E402

N4 = PS.N4
# the stock maps' pinch share by room size (medians of the five maps' class shares, rounded down a little)
TARGET = ((12, 0.18), (40, 0.13), (80, 0.05))
MIN_TILES = 12
ROUNDS = 40
# never moved here: what's tied to pipes, cables, partners or its own build (settle.FIXED), and disposal bins (their
# pipe is laid by then on the late run)
KEEP = ST.FIXED + ("/obj/machinery/disposal", "/obj/structure/disposalpipe", "/obj/machinery/door",
                   "/obj/structure/window", "/obj/structure/grille", "/obj/machinery/hydroponics",
                   "/obj/machinery/smartfridge", "/obj/structure/closet/crate/bin")


WORKS = ("/obj/machinery/power/supermatter_crystal", "/obj/machinery/power/rad_collector", "/obj/machinery/power/emitter",
         "/obj/machinery/atmospherics/components/binary", "/obj/machinery/atmospherics/components/trinary",
         "/obj/machinery/the_singularitygen", "/obj/machinery/field/generator")


def _target(n):
    t = None
    for lo, v in TARGET:
        if n >= lo:
            t = v
    return t


def _blocked(m, p, F):
    t = m.get(*p)
    return t is None or PS._solid(t) or PS._dense(t) or (p not in F and not PS._door(t))


def pinches(m, F):
    """The room's free tiles that are 1-wide passages."""
    out = set()
    for p in F:
        if PS._dense(m.get(*p)):
            continue
        if (_blocked(m, (p[0] - 1, p[1]), F) and _blocked(m, (p[0] + 1, p[1]), F)) or \
                (_blocked(m, (p[0], p[1] - 1), F) and _blocked(m, (p[0], p[1] + 1), F)):
            out.add(p)
    return out


def _reach_ok(m, F, doors, free0, seen0, used0):
    """No free tile newly cut off, no piece newly boxed in (settle's rules)."""
    seen1, free1, _ = ST._reach(m, F, doors)
    if (free1 - seen1) - (free0 - seen0):
        return False
    for u in used0:
        if u in free1:
            continue
        if not any((u[0] + dx, u[1] + dy) in seen1 for dx, dy in N4):
            return False
    return True


def _movable(o, kit):
    return FN.is_dense(o) and not CO.mounted(o) and not o.path.startswith(KEEP) and not o.path.startswith(PS.SKIP_OBJ) \
        and o.path.startswith(("/obj/structure", "/obj/machinery"))


def room(m, F, doors, kit=(), log=None, area=None):
    """Open one room up; returns (moved, removed)."""
    import density as DN
    n = len(F)
    tgt = _target(n)
    if tgt is None:
        return 0, 0
    moved = removed = 0
    hi = DN._band(PS.study(), area)[1] if area else 1.0
    for _ in range(ROUNDS):
        pin = pinches(m, F)
        free_n = sum(1 for p in F if not PS._dense(m.get(*p)))
        if not free_n or len(pin) / float(free_n) <= tgt:
            break
        seen0, free0, fronts = ST._reach(m, F, doors)
        used0 = {q for q in F if q not in free0 and any((q[0] + dx, q[1] + dy) in seen0 for dx, dy in N4)}
        # the pieces beside pinch tiles, the ones that make the most first
        cands = {}
        for p in pin:
            for dx, dy in N4:
                q = (p[0] + dx, p[1] + dy)
                if q not in F:
                    continue
                for o in m.get(*q).objs:
                    if _movable(o, kit):
                        cands.setdefault((q, id(o)), [q, o, 0])[2] += 1
        best = None
        for q, o, k in sorted(cands.values(), key=lambda c: (-c[2], c[0])):
            t = m.get(*q)
            carry = [o] + ([i for i in t.objs if i.path.startswith("/obj/item") and not CO.mounted(i)]
                           if o.path.startswith(("/obj/structure/table", "/obj/structure/rack", "/obj/structure/bed")) else [])
            t.objs = [i for i in t.objs if not any(i is c for c in carry)]
            try:
                base = len(pinches(m, F))
                for s in F:
                    if s == q or s in fronts or s in doors or not ST._free_tile(m.get(*s), s):
                        continue
                    if not any(PS._solid(m.get(s[0] + dx, s[1] + dy)) and (s[0] + dx, s[1] + dy) not in doors
                               for dx, dy in N4):
                        continue        # against a wall, as the stock maps stand their pieces
                    m.get(*s).objs.append(o)
                    try:
                        after = len(pinches(m, F))
                        # the fewest pinches, then the spot nearest where synth put it (its depth band)
                        key = (after, abs(s[0] - q[0]) + abs(s[1] - q[1]))
                        if after < len(pin) and (best is None or key < best[0]) and \
                                _reach_ok(m, F, doors, free0 | {q}, seen0, used0 - {q}):
                            best = (key, q, s, carry)
                    finally:
                        m.get(*s).objs.remove(o)
                if best is None and o.path.startswith(DN.OPTIONAL) and not any(o.path.startswith(k_) for k_ in kit):
                    # a spare piece with nowhere better: it goes, if that opens the room and leaves it no barer than
                    # its type's stock rooms (95th percentile of free floor)
                    if base < len(pin) and (free_n + 1) / float(n) <= hi:
                        best = ((base, 0), q, None, carry)
            finally:
                t.objs.extend(carry)
            if best is not None:
                break
        if best is None:
            break
        _, q, s, carry = best
        t = m.get(*q)
        t.objs = [i for i in t.objs if not any(i is c for c in carry)]
        if s is None:
            removed += 1
        else:
            m.get(*s).objs.extend(carry)
            moved += 1
    return moved, removed


def fix(m, log=print, late=False):
    import density as DN
    ST.reserve(m)
    before = after = rooms = 0
    moved = removed = 0
    for area, F in PS.pieces_of(m):
        if area in PS.CORRIDOR_AREAS or len(F) < MIN_TILES:
            continue
        doors = {(p[0] + dx, p[1] + dy) for p in F for dx, dy in N4 if PS._door(m.get(p[0] + dx, p[1] + dy))}
        if not doors:
            continue
        # stamped works stay as built: the engine room (a stock block), Atmospherics' floor, rooms on pipes
        if any(o.path.startswith(WORKS) for p in F for o in m.get(*p).objs):
            continue
        b = len(pinches(m, F))
        mv, rm = room(m, F, doors, DN._kit(area), area=area)
        a = len(pinches(m, F))
        before += b
        after += a
        moved += mv
        removed += rm
        rooms += 1 if (mv or rm) else 0
    log("airy: %d rooms opened up, %d pieces moved, %d spare ones taken out; pinch tiles %d -> %d%s" % (
        rooms, moved, removed, before, after, " (late)" if late else ""))
    return moved + removed


def shares(m):
    """{size class: (pinch share, rooms)} as in the docstring's table."""
    from collections import defaultdict
    cls = defaultdict(lambda: [0, 0, 0])
    for area, F in PS.pieces_of(m):
        if area in PS.CORRIDOR_AREAS or len(F) < MIN_TILES:
            continue
        k = "12-39" if len(F) < 40 else ("40-79" if len(F) < 80 else "80+")
        pin = pinches(m, F)
        fr = sum(1 for p in F if not PS._dense(m.get(*p)))
        cls[k][0] += len(pin)
        cls[k][1] += fr
        cls[k][2] += 1
    return {k: (round(v[0] / float(max(1, v[1])), 3), v[2]) for k, v in sorted(cls.items())}


if __name__ == "__main__":
    m = dmm.read(sys.argv[1])
    print("before", shares(m))
    fix(m)
    print("after ", shares(m))
    print(PS.summary(PS.check(m)))
    if len(sys.argv) > 2:
        dmm.write(m, sys.argv[2])
