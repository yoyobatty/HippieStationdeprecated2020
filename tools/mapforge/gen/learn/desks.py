"""Desks and hatches: a wall tile a working room shares with what it serves becomes a counter (reinforced table,
firelock, the owner's windoor on its side, by style shutters), as the stock maps serve the crew through their walls:
the kitchen's hatch onto the bar, the chemistry desk onto Medbay, the R&D desk, Robotics, the HoP, cargo's desks,
Atmospherics, Brig Control, the checkpoints.

crew 100 seed 7 f21: 7 counters, of them 2 against a wall, 3 inside one room; the stock maps 37-45 (about 15 of them
front desks between two places). The user 2026-11-26: "check how rooms and hallways and departments fit and join
together ... so we don't get patterns like chemistry tables opening into walls/useless rooms that players can't get".

Table from station/to_dmm.py COUNTERS (measured on 38 human stations, 2026-11-18), keyed by area here.

    python tools/mapforge/gen/learn/desks.py <dmm> [out.dmm]
    from gen.learn import desks; desks.fix(m, seed, log)     # build.py: after settle/density, before fixtures and nets
"""
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", ".."))
from forge import corpus as CO, dmm, function as FN  # noqa: E402

N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
DIR_NAME = {(0, 1): "north", (0, -1): "south", (1, 0): "east", (-1, 0): "west"}
HALL = "HALL"
# (owner area, what it may face in order: HALL, an area path (that area or below it), style, chance, tiles, access,
# name). DHALL of to_dmm.py is the department's corridor area here.
COUNTERS = [
    # (dept agents 2026-11-26, studies/dept_specs/*.md: the kitchen hatch and the hydroponics desk always, also onto the
    # service corridor; chemistry 8/8, Brig Control 7/7, the HoP 7/7; R&D onto a hall 8/8; department checkpoints get
    # glass onto their lobby, not a desk: only customs serves the hall)
    ("/area/crew_quarters/kitchen", ("/area/crew_quarters/bar", "/area/crew_quarters/cafeteria", HALL,
                                     "/area/crew_quarters"), "hatch", 1.0, (2, 4), "28", "Serving Hatch"),
    ("/area/hydroponics", (HALL, "/area/crew_quarters", "/area/crew_quarters/bar"), "desk", 1.0, (1, 2), "35",
     "Hydroponics Desk"),
    ("/area/hydroponics", ("/area/crew_quarters/kitchen",), "pass", 0.4, (1, 1), "35", "Hydroponics Window"),
    ("/area/medical/chemistry", ("/area/medical/medbay/lobby", "/area/medical/medbay/central", "/area/medical/medbay",
                                 HALL), "desk", 1.0, (2, 3), "33", "Chemistry Desk"),
    ("/area/security/warden", ("/area/security/brig", "/area/security", HALL), "secure", 1.0, (1, 2), "3",
     "Brig Control Desk"),
    ("/area/crew_quarters/heads/hop", (HALL,), "hop", 1.0, (1, 1), "57", "Head of Personnel's Desk"),
    ("/area/science/lab", (HALL, "/area/science", "/area/science/research"), "desk", 0.95, (1, 2), "7",
     "Research and Development Desk"),
    ("/area/science/robotics/lab", (HALL, "/area/science", "/area/science/research"), "desk", 0.75, (1, 2), "29",
     "Robotics Desk"),
    ("/area/medical/genetics", (HALL, "/area/medical/medbay/lobby", "/area/medical/medbay"), "desk", 0.35, (1, 1), "9",
     "Genetics Desk"),
    ("/area/quartermaster/office", (HALL, "/area/quartermaster"), "desk", 0.9, (1, 2), "31", "Cargo Desk"),
    ("/area/quartermaster/sorting", (HALL, "/area/quartermaster"), "desk", 0.75, (1, 1), "50", "Mail Desk"),
    ("/area/engine/atmos", (HALL,), "desk", 0.65, (1, 1), "24", "Atmospherics Desk"),
    ("/area/security/checkpoint/customs", (HALL,), "secure", 0.8, (1, 1), "63", "Customs Desk"),
    ("/area/security/checkpoint", (HALL,), "secure", 0.5, (1, 1), "63", "Security Checkpoint"),
]
WALL = ("/turf/closed/wall",)
PREFIX_OWNERS = ()


def _floor(t):
    return t is not None and t.tpath.startswith("/turf/open") and not t.tpath.startswith("/turf/open/space") \
        and not CO.solid(t) and not t.has("/obj/machinery/door")


def _wallish(t):
    return t is None or t.tpath.startswith("/turf/closed") or CO.solid(t)


def _matches(area, want, owner):
    if want == HALL:
        return area.startswith("/area/hallway/primary") or area.startswith("/area/hallway/secondary")
    if area == owner:
        return False
    # an area path: that area, or a room below it that isn't the owner's own kind (the department corridor
    # /area/medical/medbay is matched exactly, its rooms below it by their own entries)
    return area == want


UNDER = ("/obj/structure/cable", "/obj/machinery/atmospherics/pipe", "/obj/structure/disposalpipe")
SIDE_V = {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0)}


def _hung(m):
    """wall tile -> [(floor tile, piece)] hung on it (a mounted piece on the floor beside it facing it)."""
    out = {}
    for (x, y, z), t in m.tiles.items():
        for o in t.objs:
            if CO.mounted(o):
                v = SIDE_V.get(CO.mount_side(o))
                if v:
                    out.setdefault((x + v[0], y + v[1]), []).append(((x, y), o))
    return out


def _shift(m, w, hung, along, doors):
    """Move what hangs on wall tile w one or two tiles along its wall (same facing, same offsets), each to a floor
    tile of its own area whose wall has nothing hung on it and isn't a door. True if w is left bare."""
    moves = []
    taken = set()
    for p, o in hung.get(w, []):
        v = (w[0] - p[0], w[1] - p[1])
        ok = None
        for k in (1, -1, 2, -2):
            q = (p[0] + k * along[0], p[1] + k * along[1])
            wq = (q[0] + v[0], q[1] + v[1])
            tq, twq = m.get(*q), m.get(*wq)
            if tq is None or twq is None or tq.apath != m.get(*p).apath or not _floor(tq) or wq in hung or wq in taken                     or not twq.tpath.startswith(WALL) or wq in doors or q in doors                     or any(CO.mounted(x) and SIDE_V.get(CO.mount_side(x)) == v for x in tq.objs):
                continue
            ok = (q, wq)
            break
        if ok is None:
            return False
        moves.append((p, o, ok[0], ok[1]))
        taken.add(ok[1])
    for p, o, q, wq in moves:
        m.get(*p).objs = [x for x in m.get(*p).objs if x is not o]
        m.get(*q).objs.append(o)
        hung.setdefault(wq, []).append((q, o))
    hung.pop(w, None)
    return True


def spots(m, owner_tiles, owner, want, hung, doors):
    """[(wall tile, step toward the owner, along)] where a counter can go between the owner and a `want` place."""
    out = []
    seen = set()
    for p in owner_tiles:
        for dx, dy in N4:
            w = (p[0] + dx, p[1] + dy)
            if w in seen:
                continue
            tw = m.get(*w)
            if tw is None or not tw.tpath.startswith(WALL) or any(not o.path.startswith(UNDER) for o in tw.objs):
                continue
            q = (w[0] + dx, w[1] + dy)
            tq = m.get(*q)
            if not _floor(tq) or not _matches(tq.apath, want, owner):
                continue
            along = (dy, dx)
            if not all(_wallish(m.get(w[0] + s * along[0], w[1] + s * along[1])) for s in (1, -1)):
                continue
            if any((w[0] + ex, w[1] + ey) in doors for ex in (-1, 0, 1) for ey in (-1, 0, 1)):
                continue
            # someone stands on each side, neither a door's front; a dense piece on either side is counted (it is
            # moved elsewhere in its room when the counter goes there: the kitchen-bar wall was lined with the
            # kitchen's fridge and tables and the bar's vending machines, f21)
            if any((r[0] + ex, r[1] + ey) in doors for r in (p, q) for ex, ey in N4):
                continue
            block = [(r, o) for r in (p, q) for o in m.get(*r).objs if FN.is_dense(o)]
            if len(block) > 2:
                continue
            seen.add(w)
            out.append((w, (-dx, -dy), along, block))
    return out


def _clear(m, block, log=None):
    """Move each (tile, piece) to a spot in its own room (gen/learn/settle._spot: against a wall, walkable, reach
    kept). Returns the moves made, or None (and nothing moved) when one has nowhere to go."""
    import placestudy as PS
    import settle as ST
    moves = []
    for p, o in block:
        if o.path.startswith(ST.FIXED):
            break
        area = m.get(*p).apath
        F = next((F_ for a_, F_ in PS.pieces_of(m) if a_ == area and p in F_), None)
        if F is None:
            break
        doors = {(q[0] + dx, q[1] + dy) for q in F for dx, dy in N4 if PS._door(m.get(q[0] + dx, q[1] + dy))}
        spot = ST._spot(m, F, doors, p, o)
        if spot is None or spot == p:
            break
        t = m.get(*p)
        carry = [o] + ([i for i in t.objs if i.path.startswith("/obj/item") and not CO.mounted(i)]
                       if o.path.startswith(("/obj/structure/table", "/obj/structure/rack")) else [])
        t.objs = [i for i in t.objs if not any(i is c for c in carry)]
        m.get(*spot).objs.extend(carry)
        moves.append((p, spot, carry))
    else:
        return moves
    for p, spot, carry in reversed(moves):
        ts = m.get(*spot)
        ts.objs = [i for i in ts.objs if not any(i is c for c in carry)]
        m.get(*p).objs.extend(carry)
    return None


def counter_objs(style, step, name, acc, r):
    inn, out = DIR_NAME[step], DIR_NAME[(-step[0], -step[1])]
    objs = [dmm.Atom("/obj/structure/table/reinforced"), dmm.Atom("/obj/machinery/door/firedoor")]
    if style == "hatch":
        objs.append(dmm.Atom("/obj/machinery/door/poddoor/shutters/preopen", [("name", '"%s"' % name)]))
    elif style == "pass":
        objs.append(dmm.Atom("/obj/machinery/door/window/%sleft" % inn, [("name", '"%s"' % name), ("req_access_txt", '"%s"' % acc)]))
        objs.append(dmm.Atom("/obj/machinery/door/window/%sleft" % out, [("name", '"Kitchen Window"'), ("req_access_txt", '"28"')]))
    elif style in ("secure", "hop"):
        objs.append(dmm.Atom("/obj/machinery/door/window/brigdoor/%sleft" % inn, [("name", '"%s"' % name), ("req_access_txt", '"%s"' % acc)]))
        # the public side's window (the HoP's reception window, Brig Control's: stock 7/7), the HoP's privacy shutters
        objs.append(dmm.Atom("/obj/machinery/door/window/%sleft" % out, [("name", '"Reception Window"')]))
        if style == "hop":
            objs.append(dmm.Atom("/obj/machinery/door/poddoor/preopen", [("name", '"privacy shutters"')]))
    else:
        objs.append(dmm.Atom("/obj/machinery/door/window/%s%s" % (inn, r.choice(("left", "right"))),
                             [("name", '"%s"' % name), ("req_access_txt", '"%s"' % acc)]))
        if r.random() < 0.5:
            objs.append(dmm.Atom("/obj/machinery/door/poddoor/shutters/preopen", [("name", '"%s shutters"' % name.lower())]))
    if style == "hatch":
        if r.random() < 0.35:
            objs.append(dmm.Atom(r.choice(("/obj/item/reagent_containers/food/condiment/saltshaker",
                                           "/obj/item/storage/fancy/donut_box"))))
    elif r.random() < 0.45:
        objs.append(dmm.Atom(r.choice(("/obj/item/folder", "/obj/item/pen", "/obj/item/paper_bin", "/obj/item/folder/white"))))
    return objs


def fix(m, seed=1, log=print):
    r = random.Random("desks|%s" % seed)
    by_area = {}
    for (x, y, z), t in m.tiles.items():
        if z == 1 and _floor(t):
            by_area.setdefault(t.apath, set()).add((x, y))
    doors = {(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and t.has("/obj/machinery/door")}
    hung = _hung(m)
    made = []
    done_owner = set()
    for owner, faces, style, chance, (n_lo, n_hi), acc, name in COUNTERS:
        # the owner's own area (the kitchen's cold room and genetics' cloning lab took desks by prefix, f21); the
        # checkpoints are a family (customs, the department ones)
        owners = [a for a in by_area if a == owner or (owner in PREFIX_OWNERS and a.startswith(owner + "/"))]
        if not owners or r.random() > chance:
            continue
        for oa in owners:
            if (oa, faces) in done_owner:
                continue
            have = any(m.get(w[0] + dx, w[1] + dy) is not None and m.get(w[0] + dx, w[1] + dy).has("/obj/structure/table")
                       and m.get(w[0] + dx, w[1] + dy).has("/obj/machinery/door/window") and m.get(w[0] + dx, w[1] + dy).apath == oa
                       for w in by_area[oa] for dx, dy in N4)
            if have and style != "hatch":
                continue                # its desk is already there (a learned room's own)
            got = None
            for want in faces:
                sp = spots(m, by_area[oa], oa, want, hung, doors)
                if sp:
                    got = (want, sp)
                    break
            if not got:
                continue
            want, sp = got
            cx = sum(s[0][0] for s in sp) / float(len(sp))
            cy = sum(s[0][1] for s in sp) / float(len(sp))
            # the fewest pieces in the way, then the middle of the shared wall (a counter in a corner has no room)
            sp.sort(key=lambda s: (len(s[3]) + (1 if s[0] in hung else 0), abs(s[0][0] - cx) + abs(s[0][1] - cy), s[0]))
            n = r.randint(n_lo, n_hi)
            placed = []
            for w, step, along, block in sp:
                if len(placed) >= n:
                    break
                # a run, or apart: never a tile beside one of another run's ends that isn't this run's
                if placed and not any(abs(w[0] - q[0]) + abs(w[1] - q[1]) == 1 for q in placed):
                    continue
                block = [(p_, o_) for p_, o_ in block if any(o_ is x for x in m.get(*p_).objs)]
                moved = _clear(m, block) if block else []
                if moved is None:
                    continue            # a piece in the way with nowhere else in its room to go
                if w in hung and not _shift(m, w, hung, along, doors):
                    for p_, spot_, carry_ in reversed(moved):
                        ts_ = m.get(*spot_)
                        ts_.objs = [i for i in ts_.objs if not any(i is c for c in carry_)]
                        m.get(*p_).objs.extend(carry_)
                    continue            # a light or alarm on that wall with nowhere along it to go
                inner = m.get(w[0] + step[0], w[1] + step[1])
                t = m.get(*w)
                t.turf = dmm.Atom(inner.tpath)
                t.area = dmm.Atom(oa)
                t.objs = [o for o in t.objs if o.path.startswith(UNDER)] + counter_objs(style, step, name, acc, r)
                doors.add(w)
                placed.append(w)
            if placed:
                done_owner.add((oa, faces))
                made.append("%s->%s x%d" % (oa.split("/")[-1], want.split("/")[-1] if want != HALL else "hall", len(placed)))
    log("desks: %d counters (%s)" % (len(made), ", ".join(made)))
    return len(made)


if __name__ == "__main__":
    m = dmm.read(sys.argv[1])
    fix(m, 1)
    if len(sys.argv) > 2:
        dmm.write(m, sys.argv[2])
