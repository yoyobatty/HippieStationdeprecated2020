"""Does the station work? A function audit of a built station, room by room, each finding a count to drive to 0 (or
to the stock maps' own level):

    python tools/mapforge/gen/audit.py data/mapforge/gen_learn/gen_hub_c100_s7.dmm          # the counts
    python tools/mapforge/gen/audit.py <dmm> --list                                         # every finding
    python tools/mapforge/gen/audit.py <dmm> --rooms [engine]                               # room cards
    python tools/mapforge/gen/audit.py --stock                                              # the stock maps' counts
    from gen import audit; audit.audit(m) -> {finding: [(x, y, text)]}

The user 2026-11-26: "Focus on function. The generator missed a few airlocks having no path to them, wrong airlock
colour or type. Engineering has so many SMES that don't fit a purpose. ... ask what the purpose of each room and
placement of stuff does and iterate until it functionally makes sense."

Findings:
  dead_door    an airlock into a wall, at a corner or with its front blocked (gen/doorfix.py)
  plain_door   a nameless plain airlock left in a room's wall (gen/learn/doordb.py styles them)
  odd_door     an airlock of a style the human maps never give that room toward that side (a medical door into the
               armoury); maintenance hatches between two rooms
  unreached    a room no one reaches from the halls, access or not
  closed       a room the public uses on the human maps (lobby, bar, chapel, library, dorms) that needs access
  over_room    more of a machine in one room than any human room of its type has (roomdb.caps)
  over_type    more of a machine in all the rooms of a type than the typical human map has (5 SMES by the gravity
               generator)
  no_terminal  an SMES with no terminal facing it (stores nothing)
  no_apc       a room area with no APC (no power: dead machines, no light) or with two
  no_power_door an airlock on a tile of an area with no APC: it won't open (space's area is never powered)
  dark         a room (connected piece of an area, 6+ tiles) with no light fixture
  big          a multi-tile machine (the gravity generator's 3x3) over a door, a wall or a dense thing, or cutting
               its room's doors off from each other
  missing_room a room type every human station family has (all but one): telecomms' server room, the bridge...
  job_reach    a department's room its own jobs can't reach from the halls with their access (job_types access)
  orphan       a button, door timer or airlock controller whose id no other machine carries (does nothing)
  missing_kit  a room without the machines or lockers its type has in most human rooms (gen/essentials.py)
  missing_items the same for loose items (a box of contracts, a hand labeler): flavour, not counted as broken
  use          forge/function.py: a console facing a wall, a machine nobody can stand at, a scanner without its
               console, a chair for nothing
"""
import argparse
import os
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "learn"))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import corpus as CO, dmm  # noqa: E402

N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
OPP = {1: 2, 2: 1, 4: 8, 8: 4}
DIRV = {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0)}
STOCK = ("MetaStation/MetaStation.dmm", "BoxStation/BoxStation.dmm", "Deltastation/DeltaStation2.dmm",
         "HippieStation/hippiestation.dmm")
NOT_ROOM = ("/area/space", "/area/solar", "/area/shuttle", "/area/maintenance", "/area/hallway", "/area/centcom",
            "/area/lavaland", "/area/mine", "/area/ruin", "/area/holodeck")


def rooms_of(m):
    """{area: [floor tiles]} of the station's rooms (z 1)."""
    out = defaultdict(list)
    for (x, y, z), t in m.tiles.items():
        if z == 1 and t.tpath.startswith("/turf/open") and not t.tpath.startswith("/turf/open/space") \
                and not t.apath.startswith(NOT_ROOM) and not CO.solid(t):
            out[t.apath].append((x, y))
    return out


def audit(m, generated=True):
    import doorfix as DF
    import doordb as DD
    import roomdb as RDB
    out = defaultdict(list)
    for x, y, why in DF.dead(m):
        out["dead_door"].append((x, y, "%s %s" % (why, m.get(x, y).apath)))
    size = Counter(t.apath for t in m.tiles.values() if t.tpath.startswith("/turf/open"))
    for (x, y, z), t in m.tiles.items():
        a = next((o for o in t.objs if o.path.startswith(DD.AIRLOCK)), None)
        if z != 1 or a is None:
            continue
        s = DD.sides(m, x, y)
        if s is None:
            continue
        inner, ok, oa = DD.inner_outer(s[0], s[1], own=None if generated else t.apath, size=size if generated else None)
        if ok == "space" or DD.kind(inner) != "room":
            continue
        if a.path == DD.AIRLOCK and a.get("name") is None:
            out["plain_door"].append((x, y, "%s <-> %s" % (inner, oa)))
            continue
        if a.get("name") is not None and not generated:
            pass
        c = DD.lookup(inner, ok)
        c = Counter({st: n for st, n in c.items() if not DD.owned_elsewhere(st[0], inner)}) or c
        tot = sum(c.values())
        styles = {p for (p, k, v), n in c.items() if n >= DD.RARE * tot} or {c.most_common(1)[0][0][0]}
        if ok == "room":
            styles.add(DD._room_path(inner, ok)[0])     # a room's door to a room where humans only show maint doors
        if DD.owned_elsewhere(a.path, inner):
            out["odd_door"].append((x, y, "%s belongs to %s, not %s" % (a.path.replace(DD.AIRLOCK, ""),
                                                                      DD.model()["owner"][a.path], inner)))
            continue
        hatch = "/maintenance" in a.path
        if generated and DD.odd_style(m, x, y, a, s):
            # a style no human door between these two groups has (a medical "Cloning" door between art storage and an
            # emergency closet, f20/f21)
            out["odd_door"].append((x, y, "%s between %s and %s (no human door joins %s)" % (
                a.path.replace(DD.AIRLOCK, "") or "/", inner, oa, " | ".join(DD.door_pair(s)))))
            continue
        if hatch and ok == "room":
            out["odd_door"].append((x, y, "maint hatch between rooms %s | %s" % (inner, oa)))
        elif a.path not in styles and not hatch and not a.path.startswith(DD.ODD) and a.get("name") is not None \
                and not any(a.path.split("/glass")[0] == p.split("/glass")[0] for p in styles):
            out["odd_door"].append((x, y, "%s into %s from %s (human: %s)" % (
                a.path.replace(DD.AIRLOCK, "") or "/", inner, ok,
                ", ".join(sorted(p.replace(DD.AIRLOCK, "") or "/" for p in styles)))))
    # two plain walls meeting only at a corner, floor on the other diagonal (the user 2026-11-26: "walls need to join
    # without this stupid diagonal"); glass and doors at the corner are the stock maps' kind and not counted
    def _closed(t_):
        return t_ is not None and t_.tpath.startswith("/turf/closed")

    def _flr(t_):
        return t_ is not None and t_.tpath.startswith("/turf/open") and not t_.tpath.startswith("/turf/open/space") \
            and not t_.has("/obj/effect/spawner/structure/window") and not t_.has("/obj/structure/grille") \
            and not t_.has("/obj/machinery/door")
    for (x, y, z), t in m.tiles.items():
        if z != 1:
            continue
        sq = [t, m.get(x + 1, y), m.get(x, y - 1), m.get(x + 1, y - 1)]
        if None in sq:
            continue
        if (_closed(sq[0]) and _closed(sq[3]) and _flr(sq[1]) and _flr(sq[2])) or \
                (_closed(sq[1]) and _closed(sq[2]) and _flr(sq[0]) and _flr(sq[3])):
            out["diagonal"].append((x, y, "two walls meet only at a corner"))
    # the disposal exit throws out into space: its line past the blast door open (seal_hull walled it, f46)
    from forge import function as FN
    dv_ = {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0)}
    for (x, y, z), t in m.tiles.items():
        for o in t.objs:
            if z == 1 and o.path.startswith("/obj/machinery/mass_driver"):
                d_ = dv_.get(o.num("dir", 2), (0, -1))
                ahead = [m.get(x + d_[0] * k, y + d_[1] * k) for k in (1, 2, 3)]
                if any(q is None or q.tpath.startswith("/turf/closed") or any(
                        FN.is_dense(a) and not a.path.startswith("/obj/machinery/door") for a in q.objs) for q in ahead):
                    out["blocked_driver"].append((x, y, "%s: its throw line is walled or blocked" % (o.get("id") or "a mass driver")))
    # wall mounts on a wall: an APC, alarm, light or sign hangs on a side of its tile that is a wall (the user
    # 2026-11-26: "floating apc")
    import mounts as MO_
    for (x, y, o, s_) in MO_.floating(m):
        out["floating_mount"].append((x, y, "%s at %d,%d hangs on no wall" % (o.path, x, y)))
    # windows nobody looks through: no floor or door round them (the user 2026-11-26: "random windows ... in space")
    import walls as WL_
    for (x, y) in WL_.stray_glass(m):
        out["stray_window"].append((x, y, "a window with no floor or door round it"))
    # reach
    halls = [(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and t.apath.startswith("/area/hallway")
             and DD._walk(t)]
    free = DD.free_reach(m, halls)
    anyway = _reach_all(m, halls)
    R = rooms_of(m)
    for area, tiles in sorted(R.items()):
        if not any(p in anyway for p in tiles):
            out["unreached"].append(tiles[0] + ("%s (%d tiles)" % (area, len(tiles)),))
        elif DD.public(area) and not any(p in free for p in tiles):
            out["closed"].append(tiles[0] + ("%s needs access" % area,))
    # machines against the human caps: per room (connected piece of the area) and per type
    caps = RDB.caps()
    for area, tiles in sorted(R.items()):
        cp = caps.get(area, {})
        if not cp:
            continue
        tot = Counter()
        for piece in _pieces(tiles):
            c = Counter()
            for p in piece:
                for o in m.get(*p).objs:
                    f = RDB.family(o.path) if not CO.mounted(o) else None
                    if f:
                        c[f] += 1
            for f, n in c.items():
                if f in cp and n > cp[f][0]:
                    out["over_room"].append(piece[0] + ("%s: %d %s (human room at most %d)" % (
                        area, n, f.rsplit("/", 1)[-1], cp[f][0]),))
            tot.update(c)
        for f, n in tot.items():
            if f in cp and n > cp[f][1]:
                out["over_type"].append(tiles[0] + ("%s: %d %s in all (typical human map %d)" % (
                    area, n, f.rsplit("/", 1)[-1], cp[f][1]),))
    # power and light: an area with no APC has no power (its machines dead, its lights out); two APCs fight; a room
    # piece of 6+ tiles with no light fixture is dark
    apcs = Counter()
    for (x, y, z), t in m.tiles.items():
        if z == 1:
            apcs[t.apath] += sum(1 for o in t.objs if o.path.startswith("/obj/machinery/power/apc"))
    for area, tiles in sorted(R.items()):
        if apcs[area] == 0 and len(tiles) >= 4:
            out["no_apc"].append(tiles[0] + ("%s (%d tiles)" % (area, len(tiles)),))
        elif apcs[area] > 1:
            out["no_apc"].append(tiles[0] + ("%s has %d APCs" % (area, apcs[area]),))
        for piece in _pieces(tiles):
            if len(piece) >= 6 and not any(DD_lamp(o) for p in piece for o in m.get(*p).objs):
                out["dark"].append(piece[0] + ("%s piece of %d tiles, no light" % (area, len(piece)),))
    # airlocks with no power: on a tile of an area with no APC (space's area is never powered)
    for (x, y, z), t in m.tiles.items():
        if z == 1 and any(o.path.startswith("/obj/machinery/door/airlock") for o in t.objs) and apcs[t.apath] == 0                 and not t.apath.startswith(("/area/shuttle", "/area/engine/supermatter")):
            out["no_power_door"].append((x, y, "airlock in %s (no APC)" % t.apath))
    # linked pieces with no partner: a button, timer or controller whose id nothing else on the map carries
    ids = defaultdict(list)
    for (x, y, z), t in m.tiles.items():
        for o in t.objs:
            for k in ("id", "id_tag", "idSelf", "idDoor"):
                v = o.get(k)
                if v is not None and o.path.startswith("/obj/machinery"):
                    ids[v].append((x, y, o.path))
    for v, users in ids.items():
        if len(users) == 1 and users[0][2].startswith(("/obj/machinery/button", "/obj/machinery/door_timer",
                                                        "/obj/machinery/embedded_controller", "/obj/machinery/doorButtons")):
            x, y, path = users[0]
            out["orphan"].append((x, y, "%s id %s: nothing else has it" % (path.replace("/obj/machinery/", ""), v)))
    # SMES that store nothing
    for (x, y, z), t in m.tiles.items():
        if z == 1 and t.has("/obj/machinery/power/smes"):
            if not any(any(o.path.startswith("/obj/machinery/power/terminal") and o.num("dir", 2) == OPP[d]
                           for o in (m.get(x + v[0], y + v[1]).objs if m.get(x + v[0], y + v[1]) else ()))
                       for d, v in DIRV.items()):
                out["no_terminal"].append((x, y, t.apath))
    # kit
    try:
        import essentials as ES
        RS = ES.RS
        E = ES.table()
        for area, tiles in sorted(R.items()):
            if area not in E:
                continue
            have = {RS._family(o.path) for p in tiles for o in m.get(*p).objs}
            miss = [k["path"] for k in E[area]["kit"] if k["family"] not in have]
            # the work's machines and lockers apart from its loose items (a lawyer's box of contracts)
            mk = [p.rsplit("/", 1)[-1] for p in miss if not p.startswith("/obj/item")]
            mi = [p.rsplit("/", 1)[-1] for p in miss if p.startswith("/obj/item")]
            if mk:
                out["missing_kit"].append(tiles[0] + ("%s: %s" % (area, ", ".join(mk[:5])),))
            if mi:
                out["missing_items"].append(tiles[0] + ("%s: %s" % (area, ", ".join(mi[:5])),))
    except Exception as e:                     # noqa: BLE001 - no kit table: skip the finding
        out["missing_kit"].append((0, 0, "kit table failed: %s" % str(e)[:80]))
    from forge import function as FN
    for rule, p, text in FN.review(m):
        out["use"].append(p + ("%s: %s" % (rule, text),))
    for x, y, path, why in big_spots(m):
        out["big"].append((x, y, "%s %s" % (path.rsplit("/", 1)[-1], why)))
    # machines that find their partner within a range (the experimentor its console, oview 3)
    for a, b, rng in RANGE_LINKS:
        As = [(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and t.has(a)]
        Bs = [(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and t.has(b)]
        for p in As:
            if not any(max(abs(p[0] - q[0]), abs(p[1] - q[1])) <= rng for q in Bs):
                out["big"].append(p + ("%s with no %s within %d tiles" % (a.rsplit("/", 1)[-1], b.rsplit("/", 1)[-1], rng),))
    out["job_reach"] = job_reach(m, R)
    for a in must_have():
        if a not in R:
            out["missing_room"].append((0, 0, a))
    return out


def function_checks(out):
    """The audit's findings a working station can't have, as gate checks (kind hard): must-have rooms (less the ones
    no department plan builds), dead and unpowered airlocks, multi-tile machines over doors, public rooms shut."""
    import floorplan as FP
    miss = [x[2] for x in out.get("missing_room", []) if not any(w in x[2] for w in FP.NOT_MUST)
            or x[2] in ("/area/tcommsat/server", "/area/ai_monitored/turret_protected/ai")]
    rows = [("function: rooms", miss), ("function: doors", [x[2] for x in out.get("dead_door", [])]
                                         + [x[2] for x in out.get("no_power_door", [])]),
            ("function: big machines", [x[2] for x in out.get("big", [])] + [x[2] for x in out.get("blocked_driver", [])]),
            ("function: public rooms", [x[2] for x in out.get("closed", [])]),
            ("function: wall joins", ["%d,%d" % (x[0], x[1]) for x in out.get("diagonal", [])]
                                     + ["window %d,%d" % (x[0], x[1]) for x in out.get("stray_window", [])]),
            ("function: wall mounts", [x[2] for x in out.get("floating_mount", [])])]
    return [dict(kind="hard", name=n, ok=not v, value=len(v), detail="; ".join(v[:6]) or "none") for n, v in rows]


_MUST = None


def must_have():
    """The room types every human station family has but one (roomdb): telecomms' server room, the bridge, the
    brig, chemistry... (crew 100 seed 7 lost its telecomms server room and no request went through, 2026-11-26)."""
    global _MUST
    if _MUST is None:
        import roomdb as RDB
        fams, allf = defaultdict(set), set()
        for r in RDB.rooms():
            fams[r["area"]].add(r["family"])
            allf.add(r["family"])
        _MUST = sorted(a for a, f in fams.items() if len(f) >= len(allf) - 1)
    return _MUST


# lockers and vendors only: dispensers are work (trimming engineering's second tank dispenser took the engine block's
# plasma one and the engineers never started the supermatter, Bot Shift f7, 2026-11-26)
TRIM = ("/obj/structure/closet", "/obj/machinery/vending")


def trim(m, learned=(), log=print):
    """Lockers, vendors and dispensers past what a typical human map has of them in a room type (roomdb.caps), taken
    off the tiles the dressing passes furnished first (the learned rooms' own last): the engine room's walkway got
    radiation and fire closets on top of the learned engine room's (6 and 5 against 3, crew 100 seed 7, 2026-11-26).
    Disposal bins stay (their pipes are laid)."""
    import roomdb as RDB
    caps = RDB.caps()
    learned = set(learned)
    gone = Counter()
    have = defaultdict(list)
    for (x, y, z), t in m.tiles.items():
        if z != 1:
            continue
        for o in t.objs:
            if o.path.startswith(TRIM) and not CO.mounted(o):
                f = RDB.family(o.path)
                if f:
                    have[(t.apath, f)].append(((x, y) in learned, (x, y), o))
    for (area, f), lst in have.items():
        cap = caps.get(area, {}).get(f)
        if not cap or len(lst) <= cap[1]:
            continue
        lst.sort(key=lambda e: (e[0], e[1]))          # dressing's first
        for _, p, o in lst[:len(lst) - cap[1]]:
            t = m.get(*p)
            if o in t.objs:
                t.objs.remove(o)
                gone[f.rsplit("/", 1)[-1]] += 1
    log("trim: %d lockers, vendors and dispensers past their room type's typical count taken out (%s)" % (
        sum(gone.values()), ", ".join("%s %d" % kv for kv in gone.most_common(8))))
    return sum(gone.values())


# machines bigger than their tile: the gravity generator's main part spawns its 3x3 at runtime, x-1..x+1, y..y+2
# (code/modules/power/gravitygenerator.dm setup_parts); crew 100 seed 7's stood in a 4x4 room over the storage door and
# sealed Engineering Storage (its suit storage and the plasma the supermatter needs), Bot Shift f7, 2026-11-26
BIG = {"/obj/machinery/gravity_generator/main": [(dx, dy) for dx in (-1, 0, 1) for dy in (0, 1, 2)]}
RANGE_LINKS = (("/obj/machinery/rnd/experimentor", "/obj/machinery/computer/rdconsole/experiment", 3),)


def _blocked(t):
    from forge import function as FN
    return t is None or not t.tpath.startswith("/turf/open") or CO.solid(t) or         any(FN.is_dense(o) for o in t.objs if not o.path.startswith("/obj/machinery/door"))


def big_spots(m):
    """[(x, y, path, why)] for multi-tile machines whose runtime footprint covers a door, a wall or a dense thing, or
    cuts the room's doors off from each other."""
    out = []
    for (x, y, z), t in m.tiles.items():
        for o in t.objs:
            fp = next((v for k, v in BIG.items() if o.path.startswith(k)), None)
            if fp is None:
                continue
            why = _footprint_bad(m, (x, y), fp, t.apath, ignore=o)
            if why:
                out.append((x, y, o.path, why))
    return out


def _footprint_bad(m, at, fp, area, ignore=None):
    from forge import function as FN
    cells = [(at[0] + dx, at[1] + dy) for dx, dy in fp]
    for c in cells:
        t = m.get(*c)
        if t is None or t.apath != area or not t.tpath.startswith("/turf/open") or CO.solid(t):
            return "outside its room at %d,%d" % c
        if t.has("/obj/machinery/door"):
            return "over the door at %d,%d" % c
        if any(FN.is_dense(o) and o is not ignore for o in t.objs):
            return "over a dense thing at %d,%d" % c
    # every door of the room still reaches the others round it
    room = _flood_area(m, at, area)
    doors = {(c[0] + dx, c[1] + dy) for c in room for dx, dy in N4
             if m.get(c[0] + dx, c[1] + dy) is not None and m.get(c[0] + dx, c[1] + dy).has("/obj/machinery/door/airlock")}
    free = {c for c in room if c not in cells and not _blocked(m.get(*c))}
    fronts = [[c for c in free if abs(c[0] - d[0]) + abs(c[1] - d[1]) == 1] for d in doors]
    if any(not f for f in fronts):
        return "a door with no free floor before it"
    if fronts:
        seen, q = {fronts[0][0]}, [fronts[0][0]]
        while q:
            c = q.pop()
            for dx, dy in N4:
                n = (c[0] + dx, c[1] + dy)
                if n in free and n not in seen:
                    seen.add(n)
                    q.append(n)
        if any(not (set(f) & seen) for f in fronts):
            return "its room's doors cut off from each other"
    return None


def _flood_area(m, at, area):
    seen, q = {at}, [at]
    while q:
        c = q.pop()
        for dx, dy in N4:
            n = (c[0] + dx, c[1] + dy)
            t = m.get(*n)
            if n not in seen and t is not None and t.apath == area and t.tpath.startswith("/turf/open")                     and not CO.solid(t) and not t.has("/obj/machinery/door"):
                seen.add(n)
                q.append(n)
    return seen


def seat_big(m, log=print):
    """Each multi-tile machine on a spot of its room where its footprint is clear floor and the room's doors still
    reach each other: moved there, or the furniture on the best spot moved off it (tables, chairs, closets go to free
    floor of the room). Returns how many were moved."""
    from forge import function as FN
    moved = 0
    for x, y, path, why in big_spots(m):
        t = m.get(x, y)
        o = next(a for a in t.objs if a.path == path)
        fp = next(v for k, v in BIG.items() if path.startswith(k))
        # its own piece first, then the area's other pieces (a gravity generator's 4x4 room can't hold its 3x3 and a
        # way past it; the area's bigger piece can)
        own = _flood_area(m, (x, y), t.apath)
        others = {(a, b) for (a, b, z), tt in m.tiles.items() if z == 1 and tt.apath == t.apath
                  and tt.tpath.startswith("/turf/open") and not CO.solid(tt) and not tt.has("/obj/machinery/door")} - own
        room = sorted(own) + sorted(others, key=lambda c: abs(c[0] - x) + abs(c[1] - y))
        t.objs.remove(o)
        spot = next((c for c in room if not _footprint_bad(m, c, fp, t.apath)), None)
        if spot is None:
            # clear the spot nearest the room's middle: what stands on the footprint goes to free floor elsewhere
            big_piece = max([own] + _pieces_of(others), key=len)
            cx = sum(c[0] for c in big_piece) / float(len(big_piece))
            cy = sum(c[1] for c in big_piece) / float(len(big_piece))
            for c in sorted(big_piece, key=lambda c: (c[0] - cx) ** 2 + (c[1] - cy) ** 2):
                cells = [(c[0] + dx, c[1] + dy) for dx, dy in fp]
                if any(m.get(*q) is None or m.get(*q).apath != t.apath or not m.get(*q).tpath.startswith("/turf/open")
                       or m.get(*q).has("/obj/machinery/door") for q in cells):
                    continue
                spare = [q for q in big_piece if q not in cells and not _blocked(m.get(*q))]
                for q in cells:
                    for a in [a for a in m.get(*q).objs if FN.is_dense(a)]:
                        if spare:
                            m.get(*q).objs.remove(a)
                            m.get(*spare.pop()).objs.append(a)
                if not _footprint_bad(m, c, fp, t.apath):
                    spot = c
                    break
        if spot is None:
            t.objs.append(o)
            log("seat: no spot for %s in %s" % (path.rsplit("/", 1)[-1], t.apath))
            continue
        m.get(*spot).objs.append(o)
        moved += 1
        log("seat: %s moved %d,%d -> %d,%d (%s)" % (path.rsplit("/", 1)[-1], x, y, spot[0], spot[1], why))
    return moved


def pair_up(m, log=print):
    """A machine whose partner must be within range (RANGE_LINKS) and isn't: the partner moves to the nearest free
    floor of the machine's room within range, against a wall where it can."""
    moved = 0
    for a, b, rng in RANGE_LINKS:
        As = [(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and t.has(a)]
        Bs = [(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and t.has(b)]
        for p in As:
            if any(max(abs(p[0] - q[0]), abs(p[1] - q[1])) <= rng for q in Bs) or not Bs:
                continue
            q0 = min(Bs, key=lambda q: abs(q[0] - p[0]) + abs(q[1] - p[1]))
            area = m.get(*p).apath
            spots = []
            for dx in range(-rng, rng + 1):
                for dy in range(-rng, rng + 1):
                    c = (p[0] + dx, p[1] + dy)
                    t = m.get(*c)
                    if c == p or t is None or t.apath != area or not t.tpath.startswith("/turf/open") or CO.solid(t)                             or t.has("/obj/machinery/door") or any(o.path.startswith(("/obj/structure", "/obj/machinery"))
                                                                   and not CO.mounted(o) and not o.path.startswith(
                                ("/obj/structure/cable", "/obj/machinery/atmospherics", "/obj/structure/disposalpipe"))
                                                                   for o in t.objs):
                        continue
                    walls = sum(1 for ex, ey in N4 if _blocked(m.get(c[0] + ex, c[1] + ey)))
                    if walls >= 3:
                        continue
                    spots.append((-min(walls, 1), abs(dx) + abs(dy), c))
            if not spots:
                continue
            spots.sort()
            c = spots[0][2]
            tq = m.get(*q0)
            o = next(o for o in tq.objs if o.path.startswith(b))
            tq.objs.remove(o)
            m.get(*c).objs.append(o)
            moved += 1
    if moved:
        log("pair_up: %d machines moved within reach of their partners" % moved)
    return moved


def _pieces_of(cells):
    return [set(p) for p in _pieces(cells)] if cells else []


def mend(m, log=print, rounds=2):
    """The last pass of a build: forge/function.py's fixes over every room (a console turned off a wall, a chem
    master moved where a chemist can stand at it, a chair for nothing taken away), door fronts kept clear. The
    learned rooms were mended when furnished; the passes after (dressing, kit, connect, the wall merge, walkfix)
    moved walls and added things. Returns what review() still finds."""
    from forge import function as FN
    R = rooms_of(m)
    zone = {p for ts in R.values() for p in ts}
    doors = {(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and t.has("/obj/machinery/door")}
    fronts = {(d[0] + dx, d[1] + dy) for d in doors for dx, dy in N4}
    n = 0
    for _ in range(rounds):
        notes = FN.fix(m, zone, protect=fronts) or []
        n += len(notes)
        if not notes:
            break
    left = FN.review(m)
    log("mend: %d function fixes over the rooms, %d problems left (%s)" % (
        n, len(left), ", ".join("%s %d" % kv for kv in Counter(r[0] for r in left).most_common())))
    return left


def DD_lamp(o):
    return o.path.startswith("/obj/machinery/light") and not o.path.startswith("/obj/machinery/light_switch")


DEPT_JOBS = {"medical": ("medical_doctor", "chemist", "geneticist", "virologist", "chief_medical_officer"),
             "science": ("scientist", "roboticist", "research_director"),
             "security": ("security_officer", "warden", "detective", "head_of_security"),
             "engineering": ("station_engineer", "chief_engineer"), "atmos": ("atmospheric_technician", "chief_engineer"),
             "cargo": ("cargo_technician", "quartermaster", "shaft_miner"),
             "service": ("bartender", "cook", "botanist", "janitor", "clown", "mime"),
             "civic": ("chaplain", "curator", "lawyer", "assistant"), "dorms": ("assistant",),
             "command": ("head_of_personnel",)}
_JOBACC = None


def job_access():
    """{job file name: set of access numbers} from code/modules/jobs/job_types (access = list(ACCESS_...)), the
    defines from code/__DEFINES/access.dm."""
    global _JOBACC
    if _JOBACC is None:
        import re
        root = CO.ROOT
        defs = {}
        for ln in open(os.path.join(root, "code", "__DEFINES", "access.dm"), encoding="utf-8", errors="replace"):
            mm = re.match(r"\s*#define\s+(ACCESS_\w+)\s+(\d+)", ln)
            if mm:
                defs[mm.group(1)] = int(mm.group(2))
        _JOBACC = {}
        jd = os.path.join(root, "code", "modules", "jobs", "job_types")
        for f in os.listdir(jd):
            txt = open(os.path.join(jd, f), encoding="utf-8", errors="replace").read()
            mm = re.search(r"\n\s*access = list\(([^)]*)\)", txt)
            if mm:
                _JOBACC[f[:-3]] = {defs[w] for w in re.findall(r"ACCESS_\w+", mm.group(1)) if w in defs}
    return _JOBACC


def _door_ok(t, acc):
    """A door tile its holder of access set `acc` opens (no access asked, or one it has)."""
    import doordb as DD
    a = next((o for o in t.objs if o.path.startswith(DD.AIRLOCK)), None)
    if a is None:
        return True
    ra = (a.get("req_access_txt") or "").strip('"')
    ro = (a.get("req_one_access_txt") or "").strip('"')
    need = [int(v) for v in ra.replace(" ", "").split(";") if v.strip().isdigit() and int(v) != 0]
    one = [int(v) for v in ro.replace(" ", "").split(";") if v.strip().isdigit() and int(v) != 0]
    return all(n in acc for n in need) and (not one or any(n in acc for n in one))


def job_reach(m, R=None):
    """[(x, y, text)]: rooms of a department its own jobs can't reach from the halls through doors their access
    opens (an engineer shut out of Engineering Storage, a scientist out of the lab)."""
    sys.path.insert(0, os.path.join(HERE, "..", "studies"))
    import stations as ST
    import doordb as DD
    R = R or rooms_of(m)
    JA = job_access()
    halls = [(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and t.apath.startswith("/area/hallway") and DD._walk(t)]
    out = []
    cache = {}
    for area, tiles in sorted(R.items()):
        g = ST.group_of(area)
        jobs = DEPT_JOBS.get(g)
        if not jobs or area.startswith(("/area/science/test_area", "/area/ai_monitored/turret_protected")):
            continue
        # the jobs meant to go in: those whose access opens the area's own learned door (research's 47: scientist,
        # roboticist, RD; the RD's office's 30: the RD alone); each piece of the area (4+ tiles) must be reached by
        # the one with the least access among them. Pooled, the department's access hid a piece of the research
        # corridor behind the RD's 30 that the scientist never got into (f50/f51: no upgrades, no experiments)
        meant = _meant_jobs(area, jobs, JA)

        def reach(acc):
            key = frozenset(acc)
            if key not in cache:
                seen, q = set(halls), list(halls)
                while q:
                    p = q.pop()
                    for dx, dy in N4:
                        n = (p[0] + dx, p[1] + dy)
                        t = m.get(*n)
                        if n in seen or not DD._walk(t) or DD._shut(t) or not _door_ok(t, acc):
                            continue
                        seen.add(n)
                        if through_ok(t):
                            q.append(n)
                cache[key] = seen
            return cache[key]
        if meant:
            j0 = min(meant, key=lambda j: (len(JA.get(j, set())), j))
            seen = reach(JA.get(j0, set()))
            pcs = _pieces(tiles)
            for pc in pcs:
                if len(pc) < 4 or any(p in seen for p in pc):
                    continue
                # a piece with no airlock of its own is shut on purpose (a gas chamber behind its windows, a slime
                # pen behind its windoor and blast door): only a piece walked into by an airlock is judged, and the
                # area's main piece always
                if pc is not max(pcs, key=len) and not any(
                        (m.get(p[0] + dx, p[1] + dy) is not None and m.get(p[0] + dx, p[1] + dy).has("/obj/machinery/door/airlock"))
                        for p in pc for dx, dy in N4):
                    continue
                out.append(pc[0] + ("%s: none of %s gets in" % (area, j0),))
            continue
        acc = set()
        for j in jobs:
            acc |= JA.get(j, set())
        if not any(p in reach(acc) for p in tiles):
            out.append(tiles[0] + ("%s: none of %s gets in" % (area, "/".join(jobs)),))
    return out


# rooms a way in may end in but never pass through: their air turns (an R&D server heats its room over a shift and
# the bots' door rules turn back from bad air; f52's research corridor piece was reached only through the server
# room and the scientist never got in), or no one walks there (the burn chamber, the crystal's)
NO_THROUGH = ("/area/science/server", "/area/tcommsat/server", "/area/science/mixing/chamber", "/area/engine/supermatter")


def through_ok(t):
    return t is None or not t.apath.startswith(NO_THROUGH)


def _meant_jobs(area, jobs, JA):
    """The department's jobs whose access opens the area's own learned door (doordb, a door into it from a room),
    or [] when the learned door wants none of theirs."""
    import doordb as DD
    try:
        (lp, lk, lv), _ = DD.lookup(area, "room").most_common(1)[0]
    except (ValueError, IndexError):
        return []
    own = {int(v) for v in lv.strip('"').replace(" ", "").split(";") if v.isdigit() and int(v)}
    if not own:
        return []
    return [j for j in jobs if JA.get(j) and (own <= JA[j] if lk == "req_access_txt" else own & JA[j])]


def _pieces(tiles):
    left, out = set(tiles), []
    while left:
        s = left.pop()
        comp, q = [s], [s]
        while q:
            p = q.pop()
            for dx, dy in N4:
                n = (p[0] + dx, p[1] + dy)
                if n in left:
                    left.discard(n)
                    comp.append(n)
                    q.append(n)
        out.append(sorted(comp))
    return out


def _reach_all(m, halls):
    import doordb as DD
    seen, q = set(halls), list(halls)
    while q:
        p = q.pop()
        for dx, dy in N4:
            n = (p[0] + dx, p[1] + dy)
            if n not in seen and DD._walk(m.get(*n)):
                seen.add(n)
                q.append(n)
    return seen


def cards(m, want=None):
    """One line a room: its area, size, doors (style, access, what's beyond) and its machines."""
    import doordb as DD
    R = rooms_of(m)
    for area, tiles in sorted(R.items()):
        if want and want not in area:
            continue
        ts = set(tiles)
        doors = []
        for p in tiles:
            for dx, dy in N4:
                q = (p[0] + dx, p[1] + dy)
                t = m.get(*q)
                a = next((o for o in t.objs if o.path.startswith(DD.AIRLOCK)), None) if t is not None else None
                if a is not None:
                    s = DD.sides(m, *q)
                    beyond = [x[0] for x in s if x[0] != area] if s else ["?"]
                    acc = (a.get("req_access_txt") or a.get("req_one_access_txt") or "").strip('"')
                    doors.append("%s%s>%s" % (a.path.replace(DD.AIRLOCK, "") or "/", "[%s]" % acc if acc else "",
                                              (beyond[0] if beyond else area).replace("/area/", "")))
        c = Counter()
        for p in tiles:
            for o in m.get(*p).objs:
                if o.path.startswith(("/obj/machinery", "/obj/structure")) and not o.path.startswith(
                        ("/obj/machinery/light", "/obj/machinery/door", "/obj/machinery/atmospherics", "/obj/structure/cable",
                         "/obj/machinery/power/apc", "/obj/machinery/airalarm", "/obj/machinery/firealarm",
                         "/obj/structure/disposalpipe", "/obj/machinery/camera", "/obj/structure/sign",
                         "/obj/machinery/light_switch", "/obj/structure/window", "/obj/structure/grille")):
                    c[o.path.replace("/obj/machinery/", "m:").replace("/obj/structure/", "s:")] += 1
        print("%-44s %4d  doors %s" % (area, len(ts), " ".join(sorted(set(doors)))))
        print("      " + ", ".join("%s%s" % (k, " x%d" % n if n > 1 else "") for k, n in c.most_common(30)))


def summary(out):
    return {k: len(out.get(k, [])) for k in ("dead_door", "plain_door", "odd_door", "unreached", "closed", "diagonal", "stray_window", "blocked_driver", "floating_mount", "over_room",
                                              "over_type", "no_terminal", "no_apc", "no_power_door", "dark", "orphan", "big", "job_reach", "missing_room", "missing_kit", "missing_items",
                                              "use")}


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("path", nargs="?")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--rooms", nargs="?", const="")
    ap.add_argument("--stock", action="store_true")
    a = ap.parse_args()
    if a.stock:
        for rel in STOCK:
            m = dmm.read(os.path.join(CO.ROOT, "_maps", "map_files", rel))
            print("%-34s %s" % (rel.split("/")[-1], summary(audit(m, generated=False))), flush=True)
    if a.path:
        m = dmm.read(a.path)
        if a.rooms is not None:
            cards(m, a.rooms or None)
        out = audit(m)
        print("%-34s %s" % (os.path.basename(a.path), summary(out)))
        if a.list:
            for k, v in out.items():
                for x, y, text in v:
                    print("  %-11s %3d,%3d  %s" % (k, x, y, text))
