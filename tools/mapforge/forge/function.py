"""Does each piece work where it stands? Machines that link to a partner (cloning console, scanner and pod; DNA
console; operating computer and table; nanite chamber; teleporter; mech bay), the tile a player stands on to use a
machine, potted plants, chairs, wet fixtures, and one-of-a-kind things (pets, the captain's gear).

The rules come from the game's own code (2020 tg: each console finds its partner with get_step over the cardinals)
and from how people mapped the stock stations: run it on them to see what it flags there.

    python tools/mapforge/forge/function.py <dmm> [...]     # review: problems by rule

review(m, zone=None) -> [(rule, (x, y), text)]; fix(m, zone, ...) moves or removes pieces and returns notes.
"""
import os
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from forge import dmm, kit  # noqa: E402

D4 = {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0)}
OPP = {1: 2, 2: 1, 4: 8, 8: 4}

# piece -> partners it finds on a cardinal neighbour (any one of each group)
LINKS = [
    ("/obj/machinery/computer/cloning", [("/obj/machinery/dna_scannernew",), ("/obj/machinery/clonepod",)]),
    ("/obj/machinery/computer/scan_consolenew", [("/obj/machinery/dna_scannernew",)]),
    ("/obj/machinery/clonepod", [("/obj/machinery/computer/cloning",)]),
    ("/obj/machinery/dna_scannernew", [("/obj/machinery/computer/cloning", "/obj/machinery/computer/scan_consolenew")]),
    ("/obj/machinery/computer/operating", [("/obj/structure/table/optable",)]),
    ("/obj/structure/table/optable", [("/obj/machinery/computer/operating",)]),
    ("/obj/machinery/computer/nanite_chamber_control", [("/obj/machinery/nanite_chamber",)]),
    ("/obj/machinery/nanite_chamber", [("/obj/machinery/computer/nanite_chamber_control",)]),
    ("/obj/machinery/computer/teleporter", [("/obj/machinery/teleport/station",)]),
    ("/obj/machinery/teleport/station", [("/obj/machinery/teleport/hub",), ("/obj/machinery/computer/teleporter",)]),
    ("/obj/machinery/teleport/hub", [("/obj/machinery/teleport/station",)]),
]

# pieces a player uses from the tile in front (the dir they face)
FRONT_USE = ("/obj/machinery/computer", "/obj/machinery/modular_computer/console")
NOT_FRONT = ("/obj/machinery/computer/security/telescreen", "/obj/machinery/computer/cryopod", "/obj/machinery/computer/arcade",
             "/obj/machinery/computer/slot_machine", "/obj/machinery/computer/security/wooden_tv")
# pieces a player uses from any side
SIDE_USE = ("/obj/machinery/vending", "/obj/machinery/chem", "/obj/machinery/rnd", "/obj/machinery/autolathe", "/obj/machinery/mecha_part_fabricator",
            "/obj/machinery/smartfridge", "/obj/machinery/hydroponics", "/obj/machinery/biogenerator",
            "/obj/machinery/seed_extractor", "/obj/machinery/plantgenes", "/obj/machinery/microwave", "/obj/machinery/deepfryer",
            "/obj/machinery/grill", "/obj/machinery/processor", "/obj/machinery/gibber", "/obj/machinery/icecream_vat",
            "/obj/machinery/clonepod", "/obj/machinery/dna_scannernew", "/obj/machinery/sleeper", "/obj/machinery/suit_storage_unit",
            "/obj/machinery/disposal/bin", "/obj/structure/closet", "/obj/structure/table", "/obj/structure/rack",
            "/obj/machinery/recharge_station", "/obj/machinery/atmospherics/components/unary/cryo_cell",
            "/obj/machinery/atmospherics/components/unary/thermomachine", "/obj/machinery/ore_silo", "/obj/machinery/mineral",
            "/obj/structure/reagent_dispensers", "/obj/machinery/washing_machine", "/obj/structure/bookcase",
            "/obj/machinery/nanite_program_hub", "/obj/machinery/nanite_programmer", "/obj/machinery/public_nanite_chamber",
            "/obj/machinery/limbgrower", "/obj/machinery/harvester", "/obj/machinery/computer/cryopod", "/obj/structure/dresser",
            "/obj/machinery/photocopier", "/obj/structure/filingcabinet", "/obj/machinery/libraryscanner",
            "/obj/machinery/bookbinder", "/obj/machinery/smoke_machine", "/obj/machinery/oven", "/obj/machinery/griddle",
            "/obj/machinery/telecomms", "/obj/machinery/mech_bay_recharge_port", "/obj/machinery/cell_charger")
WALLISH = ("/obj/effect/spawner/structure/window", "/obj/structure/grille", "/obj/structure/window")
PLANT = "/obj/item/twohanded/required/kirbyplants"
CHAIR = "/obj/structure/chair"
SEAT_AREAS = ("/area/hallway", "/area/chapel", "/area/medical/medbay/lobby", "/area/security/courtroom",
              "/area/crew_quarters/theatre", "/area/crew_quarters/bar", "/area/crew_quarters/cafeteria",
              "/area/crew_quarters/lounge", "/area/crew_quarters/fitness", "/area/library", "/area/security/brig",
              "/area/security/prison", "/area/hippie/pool", "/area/security/checkpoint", "/area/quartermaster/office",
              "/area/teleporter", "/area/crew_quarters/abandoned_gambling_den", "/area/medical/medbay/central")
WET = ("/obj/machinery/shower", "/obj/structure/sink", "/obj/structure/toilet", "/obj/structure/urinal")
# one of each on a station
UNIQUE = ("/mob/living/simple_animal/pet", "/mob/living/simple_animal/sloth", "/mob/living/simple_animal/parrot/Poly",
          "/mob/living/simple_animal/hostile/retaliate/bat/secbat", "/mob/living/simple_animal/hostile/lizard/wags_his_tail",
          "/mob/living/carbon/monkey/punpun", "/mob/living/simple_animal/chicken/rabbit", "/mob/living/simple_animal/cow/betsy",
          "/mob/living/simple_animal/hostile/retaliate/goat/pete", "/mob/living/simple_animal/hostile/retaliate/poison/snake",
          "/obj/item/disk/nuclear", "/obj/item/card/id/captains_spare", "/obj/item/areaeditor/blueprints",
          "/obj/item/gun/energy/e_gun/hos", "/obj/item/gun/energy/laser/captain", "/obj/item/reagent_containers/hypospray/CMO",
          "/obj/item/clothing/suit/armor/reactive", "/obj/item/pinpointer/nuke",
          "/obj/item/clothing/shoes/magboots/advance", "/obj/item/tank/jetpack/oxygen/captain", "/obj/item/clothing/accessory/medal/gold/captain",
          "/obj/machinery/computer/upload/ai", "/obj/machinery/computer/upload/borg", "/obj/machinery/nuclearbomb/selfdestruct",
          "/obj/machinery/ore_silo", "/obj/machinery/computer/bank_machine",
          "/obj/machinery/gravity_generator/main", "/obj/item/storage/secure/safe/HoS",
          "/obj/item/clothing/head/crown",
          "/obj/item/bedsheet/captain", "/obj/item/bedsheet/hos", "/obj/item/bedsheet/cmo", "/obj/item/bedsheet/rd",
          "/obj/item/bedsheet/ce", "/obj/item/bedsheet/qm", "/obj/item/bedsheet/hop", "/obj/item/toy/figure/captain",
          "/obj/item/clothing/mask/gas/sechailer/swat", "/obj/item/radio/intercom/private")


def objs(m, p):
    t = m.get(p[0], p[1])
    return t.objs if t else []


def find(m, p, prefixes):
    return [o for o in objs(m, p) if o.path.startswith(prefixes)]


def on_floor(o):
    return abs(o.num("pixel_x")) < 16 and abs(o.num("pixel_y")) < 16


def is_dense(o):
    if o.path.startswith(("/obj/item", "/obj/effect", "/mob", "/obj/structure/cable", "/obj/machinery/atmospherics/pipe",
                          "/obj/machinery/door/firedoor", "/obj/structure/disposalpipe", "/obj/machinery/navbeacon",
                          "/obj/structure/lattice", "/obj/structure/chair", "/obj/structure/bed")) or not on_floor(o):
        return False
    return kit.is_dense_atom(o)


def nb(p, d, k=1):
    return (p[0] + D4[d][0] * k, p[1] + D4[d][1] * k)


class View:
    """What a tile is, for people walking about."""

    def __init__(self, m, zone=None):
        self.m = m
        self.zone = zone

    def t(self, p):
        return self.m.get(p[0], p[1])

    def area(self, p):
        t = self.t(p)
        return t.area.path if t and t.area else ""

    def wallish(self, p):
        t = self.t(p)
        if t is None:
            return False
        return t.turf.path.startswith("/turf/closed") or t.has(WALLISH[0]) or t.has(WALLISH[1]) or \
            any(o.path.startswith("/obj/structure/window") and o.num("dir", 2) == 5 for o in t.objs)

    def walk(self, p):
        """A tile a person can stand on (doors count: you can stand in a doorway)."""
        t = self.t(p)
        if t is None or not t.turf.path.startswith("/turf/open") or t.turf.path.startswith("/turf/open/space"):
            return False
        if t.has(WALLISH[0]) or t.has(WALLISH[1]):
            return False
        if any(o.path.startswith("/obj/machinery/door") and not o.path.startswith("/obj/machinery/door/firedoor")
               for o in t.objs):
            return True
        return not any(is_dense(o) for o in t.objs)

    def door(self, p):
        t = self.t(p)
        return t is not None and any(o.path.startswith("/obj/machinery/door/airlock") for o in t.objs)

    def stand(self, p):
        """A tile a person can stand on to use something: walkable, not a doorway, nothing in the way."""
        return self.walk(p) and not self.door(p)


def front_dir(o):
    return o.num("dir", 2) or 2


def front_ok(v, p, o):
    """A console is worked from the tile it faces; a desk or its partner there is fine if a tile beside it is free
    (people use it from the side, as with an operating computer facing its table)."""
    f = nb(p, front_dir(o))
    if v.stand(f):
        return True
    if v.wallish(f) or v.door(f):
        return False
    return any(v.stand((p[0] + dx, p[1] + dy)) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy)


def chair_purpose(v, p, o):
    """Why a chair is where it is, or None. (Same tests as the stock-map survey.)"""
    d = o.num("dir", 2) or 2
    m = v.m

    def k(q):
        if v.wallish(q):
            return "wall"
        os_ = objs(m, q)
        if any(a.path.startswith("/obj/structure/table") for a in os_):
            return "table"
        if any(a.path.startswith(("/obj/machinery/computer", "/obj/machinery/modular_computer")) and on_floor(a) for a in os_):
            return "computer"
        if any(a.path.startswith(("/obj/structure/chair", "/obj/structure/bed")) for a in os_):
            return "seat"
        if any(a.path.startswith(("/obj/machinery/vending", "/obj/machinery/chem", "/obj/machinery/rnd",
                                  "/obj/structure/piano", "/obj/machinery/computer", "/obj/machinery/holopad",
                                  "/obj/structure/fireplace", "/obj/machinery/computer/arcade", "/obj/structure/displaycase",
                                  "/obj/machinery/smartfridge", "/obj/machinery/microwave", "/obj/structure/table"))
               for a in os_):
            return "machine"
        return "floor"
    front, back = k(nb(p, d)), k(nb(p, OPP[d]))
    if front in ("table", "computer"):
        return "at a " + front
    if "/office" in o.path:
        # an office chair is for a desk or a console, two steps away at most
        if k(nb(p, d, 2)) in ("table", "computer"):
            return "desk ahead"
        return None
    if front in ("seat", "machine"):
        return "facing a " + front
    if k(nb(p, d, 2)) in ("table", "computer", "seat"):
        return "table ahead"
    seat_room = v.area(p).startswith(SEAT_AREAS)
    sides = [s for s in D4 if s not in (d, OPP[d])]
    row = 1
    for s in sides:
        q = nb(p, s)
        while any(a.path.startswith(CHAIR) and (a.num("dir", 2) or 2) == d for a in objs(m, q)) and row < 20:
            row += 1
            q = nb(q, s)
    if back == "wall" and seat_room:
        return "against the wall"
    if row >= 3 and seat_room:
        return "a row of seats"
    if back == "wall" and row >= 2:
        return "a bench by the wall"
    return None


def review(m, zone=None, maint_ok=True):
    """[(rule, tile, text)] for the station level."""
    v = View(m, zone)
    out = []
    tiles = zone if zone is not None else [(x, y) for (x, y, z) in m.tiles if z == 1]
    by_path = defaultdict(list)
    for p in tiles:
        t = m.get(p[0], p[1])
        if t is None:
            continue
        a = v.area(p)
        if a.startswith(("/area/space", "/area/solar", "/area/shuttle", "/area/centcom", "/area/lavaland", "/area/ruin",
                         "/area/mine", "/area/awaymission", "/area/holodeck")):
            continue
        maint = a.startswith("/area/maintenance") or "abandoned" in a
        for o in t.objs:
            path = o.path
            if path.startswith(UNIQUE):
                by_path[path].append(p)
            # links
            for piece, groups in LINKS:
                if path == piece or path.startswith(piece + "/"):
                    for g in groups:
                        if not any(find(m, nb(p, d), g) for d in D4):
                            out.append(("link", p, "%s has no %s beside it" % (short(path), "/".join(short(x) for x in g))))
                    break
            if not on_floor(o):
                continue
            # use tiles
            if path.startswith(FRONT_USE) and not path.startswith(NOT_FRONT):
                f = nb(p, front_dir(o))
                if not front_ok(v, p, o):
                    out.append(("front", p, "%s faces %s: nowhere to stand" % (short(path), what(v, f))))
            elif path.startswith(SIDE_USE) and is_dense(o):
                if not any(v.walk((p[0] + dx, p[1] + dy)) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy):
                    out.append(("reach", p, "%s: no tile to stand at" % short(path)))
            # plants
            if path.startswith(PLANT) and not maint:
                if not any(v.wallish(nb(p, d)) for d in D4):
                    out.append(("plant", p, "plant in the open floor"))
                for d in D4:
                    q = nb(p, d)
                    for a2 in objs(m, q):
                        if a2.path.startswith(FRONT_USE) and not a2.path.startswith(NOT_FRONT) and on_floor(a2) and \
                                nb(q, front_dir(a2)) == p:
                            out.append(("plant", p, "plant where you stand at %s" % short(a2.path)))
                    if find(m, q, (CHAIR,)) and any(nb(q, front_dir(c)) == p for c in find(m, q, (CHAIR,))):
                        out.append(("plant", p, "plant in front of a chair"))
            # chairs
            if path.startswith(CHAIR) and not maint and "/stool" not in path and \
                    "/sofa" not in path and "/pew" not in path:
                if chair_purpose(v, p, o) is None:
                    out.append(("chair", p, "%s for nothing" % short(path)))
            # wet fixtures
            if path.startswith(WET) and not maint:
                if t.has("/obj/structure/cable"):
                    out.append(("wet", p, "%s on live cable" % short(path)))
                if t.turf.path == "/turf/open/floor/plating" and path.startswith("/obj/machinery/shower"):
                    out.append(("wet", p, "shower on bare plating"))
            # wall fixtures: on a wall that's there, the way stock maps hang them
            how = fixture_ways(path)
            if how and not t.has("/obj/structure/table"):
                side = wall_side_of(o)
                q = nb(p, side) if side else None
                if side not in how or not hangable(v, q):
                    out.append(("fixture", p, "%s hangs on no wall it can (side %s)" % (short(path), side)))
    for path, ps in by_path.items():
        if len(ps) > 1:
            out.append(("unique", ps[1], "%d of %s (first %d,%d)" % (len(ps), short(path), ps[0][0], ps[0][1])))
    return out


def short(path):
    return path.split("{")[0].replace("/obj/machinery/", "").replace("/obj/structure/", "").replace("/obj/item/", "")


def what(v, p):
    t = v.t(p)
    if t is None:
        return "nothing"
    if v.wallish(p):
        return "a wall"
    if v.door(p):
        return "a doorway"
    d = [o for o in t.objs if is_dense(o)]
    return short(d[0].path) if d else "floor"


# ---------------------------------------------------------------------------------------------------- fixing
def fix(m, zone, protect=(), log=None):
    """Mend what review() finds, on the tiles in zone. protect: tiles never to put things on (doorways, mounts' tiles).
    Returns notes."""
    v = View(m, zone)
    zone = set(zone)
    protect = set(protect)
    notes = []

    def free_for(p):
        """Can a floor piece go on p without blocking anything?"""
        if p not in zone or p in protect or not v.stand(p):
            return False
        t = v.t(p)
        if any(o.path.startswith(("/obj/structure/chair", "/obj/structure/bed", PLANT, "/obj/effect/landmark/start",
                                  "/obj/machinery/holopad", "/obj/machinery/atmospherics/components/unary")) for o in t.objs):
            return False
        # not where someone stands to use a neighbour, and not in front of a door
        for d in D4:
            q = nb(p, d)
            if v.door(q):
                return False
            for a in objs(m, q):
                if not on_floor(a):
                    continue
                if a.path.startswith(FRONT_USE) and not a.path.startswith(NOT_FRONT) and nb(q, front_dir(a)) == p:
                    return False
                if a.path.startswith(CHAIR) and nb(q, a.num("dir", 2) or 2) == p:
                    return False
                if a.path.startswith(SIDE_USE) and is_dense(a):
                    others = [nb(q, e) for e in D4 if nb(q, e) != p and v.walk(nb(q, e))]
                    if not others:
                        return False
        return True

    def keeps_flow(p):
        """Putting a solid piece on p leaves the room's floor in one piece and no squeeze."""
        ns = [nb(p, d) for d in D4 if v.walk(nb(p, d))]
        if len(ns) <= 1:
            return True
        # the walkable neighbours must still meet round p (within the 8 tiles about it)
        ring = [(p[0] + dx, p[1] + dy) for dx, dy in ((-1, -1), (0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0))]
        seen, q = {ns[0]}, [ns[0]]
        ring_set = {r for r in ring if v.walk(r)}
        while q:
            c = q.pop()
            for d in D4:
                n2 = nb(c, d)
                if n2 in ring_set and n2 not in seen:
                    seen.add(n2)
                    q.append(n2)
        return all(n2 in seen for n2 in ns)

    def room_of(p):
        a = v.area(p)
        out, q, seen = [], [p], {p}
        while q and len(out) < 400:
            c = q.pop()
            out.append(c)
            for d in D4:
                n2 = nb(c, d)
                if n2 in zone and n2 not in seen and v.area(n2) == a and v.t(n2) and \
                        v.t(n2).turf.path.startswith("/turf/open") and not v.wallish(n2):
                    seen.add(n2)
                    q.append(n2)
        return out

    def move(p, atom, to, why):
        objs(m, p).remove(atom)
        objs(m, to).append(atom)
        notes.append("%s %d,%d -> %d,%d (%s)" % (short(atom.path), p[0], p[1], to[0], to[1], why))

    def drop(p, atom, why):
        objs(m, p).remove(atom)
        notes.append("removed %s at %d,%d (%s)" % (short(atom.path), p[0], p[1], why))

    # 1. one of each unique thing
    seen = {}
    for p in sorted(zone):
        for o in list(objs(m, p)):
            if o.path.startswith(UNIQUE):
                key = o.path
                if key in seen:
                    drop(p, o, "second one; first at %d,%d" % seen[key])
                else:
                    seen[key] = p

    # 2. links: a console moves to a free cardinal tile of its partner; a lone optable gets its computer or goes
    def partner_ok(p, path):
        for piece, groups in LINKS:
            if path == piece or path.startswith(piece + "/"):
                return all(any(find(m, nb(p, d), g) for d in D4) for g in groups)
        return True

    # consoles move to their partners first; only then does a partner left alone get a console of its own
    LONE = ("/obj/machinery/dna_scannernew", "/obj/machinery/clonepod", "/obj/machinery/nanite_chamber")
    for p, o in [(p, o) for phase in (0, 1) for p in sorted(zone) for o in list(objs(m, p))
                 if o.path.startswith(LONE) == bool(phase)]:
        if o not in objs(m, p):
            continue
        if True:
            if partner_ok(p, o.path):
                continue
            path = o.path
            if path.startswith("/obj/structure/table/optable"):
                # put an operating computer on a cardinal tile against a wall, facing the table's side
                spot = None
                for d in D4:
                    q = nb(p, d)
                    if free_for(q) and keeps_flow(q) and any(v.wallish(nb(q, e)) for e in D4):
                        spot = (q, d)
                        break
                if spot:
                    q, d = spot
                    # it faces away from the table? no: an operating computer faces the surgeon; face along the wall
                    face = next((e for e in D4 if e not in (d, OPP[d]) and v.stand(nb(q, e))), OPP[d])
                    objs(m, q).append(dmm.Atom("/obj/machinery/computer/operating", [("dir", str(face))] if face != 2 else []))
                    notes.append("operating computer at %d,%d for the table at %d,%d" % (q[0], q[1], p[0], p[1]))
                else:
                    drop(p, o, "operating table with no room for its computer")
                continue
            if path.startswith(("/obj/machinery/computer/cloning", "/obj/machinery/computer/scan_consolenew",
                                "/obj/machinery/computer/operating", "/obj/machinery/computer/nanite_chamber_control",
                                "/obj/machinery/computer/teleporter")):
                groups = next(g for pc, g in LINKS if path == pc or path.startswith(pc + "/"))
                # tiles next to every group's piece in this room
                room = room_of(p)
                best = None
                for q in room:
                    if q != p and not free_for(q):
                        continue
                    if all(any(find(m, nb(q, d), g) for d in D4) for g in groups):
                        dist = abs(q[0] - p[0]) + abs(q[1] - p[1])
                        if best is None or dist < best[0]:
                            best = (dist, q)
                if best:
                    q = best[1]
                    # face a standing tile, not the partner
                    f = front_dir(o)
                    if not v.stand(nb(q, f)) or nb(q, f) == p:
                        f = next((e for e in D4 if v.stand(nb(q, e)) and nb(q, e) != p), f)
                    o.vars = [kv for kv in o.vars if kv[0] != "dir"] + ([("dir", str(f))] if f != 2 else [])
                    move(p, o, q, "beside its %s" % "/".join(short(g[0]) for g in groups))
                    continue
            if path.startswith(("/obj/machinery/dna_scannernew", "/obj/machinery/clonepod", "/obj/machinery/nanite_chamber")):
                # a scanner, pod or chamber alone gets its own console beside it (on a wall, out of the way), else goes
                console = {"/obj/machinery/dna_scannernew": "/obj/machinery/computer/scan_consolenew",
                           "/obj/machinery/nanite_chamber": "/obj/machinery/computer/nanite_chamber_control",
                           "/obj/machinery/clonepod": None}[next(k for k in ("/obj/machinery/dna_scannernew", "/obj/machinery/clonepod",
                                                                             "/obj/machinery/nanite_chamber") if path.startswith(k))]
                spot = None
                for d in D4:
                    q = nb(p, d)
                    if console and free_for(q) and keeps_flow(q) and any(v.wallish(nb(q, e)) for e in D4):
                        spot = q
                        break
                if spot:
                    face = next((e for e in D4 if v.stand(nb(spot, e))), 2)
                    objs(m, spot).append(dmm.Atom(console, [("dir", str(face))] if face != 2 else []))
                    notes.append("%s at %d,%d for the %s at %d,%d" % (short(console), spot[0], spot[1], short(path), p[0], p[1]))
                else:
                    drop(p, o, "no console for it")
                continue

    # 3. computers and vendors with nowhere to stand in front: turn to a side with floor, else move along the wall
    for p in sorted(zone):
        for o in list(objs(m, p)):
            if not (o.path.startswith(FRONT_USE) and not o.path.startswith(NOT_FRONT) and on_floor(o)):
                continue
            if front_ok(v, p, o):
                continue
            if o.path.startswith("/obj/machinery/computer") and not partner_ok(p, o.path):
                continue
            back = [e for e in D4 if v.wallish(nb(p, e))]
            turn = [e for e in D4 if v.stand(nb(p, e)) and (not back or e == OPP[back[0]] or e not in back)]
            if turn:
                e = max(turn, key=lambda e: (OPP[e] in back, e))
                o.vars = [kv for kv in o.vars if kv[0] != "dir"] + ([("dir", str(e))] if e != 2 else [])
                notes.append("turned %s at %d,%d to face %s" % (short(o.path), p[0], p[1], {1: "N", 2: "S", 4: "E", 8: "W"}[e]))

    # 4. plants: against a wall, out of anyone's way; else gone
    for p in sorted(zone):
        for o in list(objs(m, p)):
            if not o.path.startswith(PLANT):
                continue
            a = v.area(p)
            if a.startswith("/area/maintenance"):
                continue
            ok = any(v.wallish(nb(p, d)) for d in D4)
            if ok:
                for d in D4:
                    q = nb(p, d)
                    if any(a2.path.startswith(FRONT_USE) and not a2.path.startswith(NOT_FRONT) and on_floor(a2) and
                           nb(q, front_dir(a2)) == p for a2 in objs(m, q)):
                        ok = False
                    if any(a2.path.startswith(CHAIR) and nb(q, a2.num("dir", 2) or 2) == p for a2 in objs(m, q)):
                        ok = False
                    if v.door(q):
                        ok = False
            if ok:
                continue
            objs(m, p).remove(o)
            # the nearest corner of the room (two walls), then any wall tile, out of the way
            room = room_of(p)
            cands = [q for q in room if q != p and free_for(q) and keeps_flow(q)]
            corner = [q for q in cands if sum(v.wallish(nb(q, d)) for d in D4) >= 2]
            wall = [q for q in cands if sum(v.wallish(nb(q, d)) for d in D4) == 1]
            pick = corner or wall
            if pick:
                q = min(pick, key=lambda q: abs(q[0] - p[0]) + abs(q[1] - p[1]))
                objs(m, q).append(o)
                notes.append("plant %d,%d -> %d,%d (%s)" % (p[0], p[1], q[0], q[1], "corner" if corner else "wall"))
            else:
                notes.append("removed plant at %d,%d (no wall spot)" % p)

    # 5. chairs for nothing: gone
    for p in sorted(zone):
        if v.area(p).startswith("/area/maintenance"):
            continue
        for o in list(objs(m, p)):
            if o.path.startswith(CHAIR) and "/stool" not in o.path and "/sofa" not in o.path \
                    and "/pew" not in o.path and chair_purpose(v, p, o) is None:
                drop(p, o, "a chair for nothing")
                for lm in [a for a in objs(m, p) if a.path.startswith("/obj/effect/landmark/start")]:
                    pass
    # chairs that lost their purpose when their neighbours went (rows broken up): one more round
    for p in sorted(zone):
        if v.area(p).startswith("/area/maintenance"):
            continue
        for o in list(objs(m, p)):
            if o.path.startswith(CHAIR) and "/stool" not in o.path and "/sofa" not in o.path \
                    and "/pew" not in o.path and chair_purpose(v, p, o) is None:
                drop(p, o, "a chair for nothing")

    # 6. morgue trays: the icon only faces east and the tray slides east onto a free tile; a tray that can't is
    # moved to a free west wall of its room (trays kept clear of each other), else taken out
    MORGUE = "/obj/structure/bodycontainer/morgue"
    trays = set()
    stuck = []
    for p in sorted(zone):
        for o in list(objs(m, p)):
            if not o.path.startswith(MORGUE):
                continue
            o.vars = [kv for kv in o.vars if kv[0] != "dir"]
            e = nb(p, 4)
            if v.stand(e) and e not in trays and not find(m, e, (MORGUE,)):
                trays.add(e)
            else:
                stuck.append((p, o))
    for p, o in stuck:
        objs(m, p).remove(o)
    for p, o in stuck:
        room = room_of(p)
        spots = [q for q in room if v.wallish(nb(q, 8)) and free_for(q) and keeps_flow(q) and v.stand(nb(q, 4))
                 and nb(q, 4) not in trays and not find(m, nb(q, 4), (MORGUE,)) and q not in trays]
        if spots:
            q = min(spots, key=lambda q: abs(q[0] - p[0]) + abs(q[1] - p[1]))
            objs(m, q).append(o)
            trays.add(nb(q, 4))
            notes.append("morgue %d,%d -> %d,%d (its tray had nowhere to go)" % (p[0], p[1], q[0], q[1]))
        else:
            notes.append("removed morgue at %d,%d (no west wall with room for its tray)" % p)

    # 7. nothing left lying on an operating table: onto the nearest table in the room
    for p in sorted(zone):
        if not find(m, p, ("/obj/structure/table/optable",)):
            continue
        items = [o for o in objs(m, p) if o.path.startswith("/obj/item")]
        if not items:
            continue
        tables = [q for q in room_of(p) if q != p and find(m, q, ("/obj/structure/table",))
                  and not find(m, q, ("/obj/structure/table/optable",))]
        for o in items:
            objs(m, p).remove(o)
            if tables:
                q = min(tables, key=lambda q: abs(q[0] - p[0]) + abs(q[1] - p[1]))
                objs(m, q).append(o)
                notes.append("%s off the operating table at %d,%d onto %d,%d" % (short(o.path), p[0], p[1], q[0], q[1]))
            else:
                notes.append("removed %s from the operating table at %d,%d" % (short(o.path), p[0], p[1]))

    # 8. one wall, two rooms' pieces hung on it from both sides: they'd draw over each other on the one wall tile.
    # The working piece (APC, alarms) stays; decoration from the other side goes.
    WORK = ("/obj/machinery/power/apc", "/obj/machinery/airalarm", "/obj/machinery/firealarm", "/obj/machinery/button",
            "/obj/machinery/door_timer", "/obj/machinery/requests_console")
    on_wall = defaultdict(list)
    for p in sorted(zone):
        for o in objs(m, p):
            px, py = o.num("pixel_x"), o.num("pixel_y")
            if (abs(px) >= 20 or abs(py) >= 20) and o.path.startswith(("/obj/machinery", "/obj/structure/sign", "/obj/structure/noticeboard",
                                                                       "/obj/structure/extinguisher_cabinet", "/obj/item/radio/intercom")):
                w = (p[0] + (1 if px >= 20 else -1 if px <= -20 else 0), p[1] + (1 if py >= 20 else -1 if py <= -20 else 0))
                on_wall[w].append((p, o))
    for w, hung in on_wall.items():
        sides = {p for p, _ in hung}
        if len(sides) < 2:
            continue
        keep = max(sides, key=lambda s: (sum(1 for p, o in hung if p == s and o.path.startswith(WORK)), -s[0], -s[1]))
        for p, o in hung:
            if p != keep and not o.path.startswith(WORK):
                objs(m, p).remove(o)
                notes.append("took %s at %d,%d off the wall %d,%d (the other side uses it)" % (short(o.path), p[0], p[1], w[0], w[1]))

    # 9. wet fixtures: a proper floor under a shower
    for p in sorted(zone):
        t = v.t(p)
        if t and t.has("/obj/machinery/shower") and t.turf.path == "/turf/open/floor/plating" and \
                not v.area(p).startswith("/area/maintenance"):
            t.turf = dmm.Atom("/turf/open/floor/plasteel/freezer")
            notes.append("shower floor at %d,%d" % p)
    # 10. no water over live cable: a shower (sink, toilet) on a cabled tile moves to a dry wall spot of its room
    # facing the same way, else goes
    WET_DIR = {2: 1, 1: 2, 4: 8, 8: 4}       # facing -> the wall it hangs on
    for p in sorted(zone):
        if not find(m, p, ("/obj/structure/cable", "/obj/machinery/power")):
            continue
        for o in list(objs(m, p)):
            if not o.path.startswith(WET):
                continue
            face = o.num("dir", 2) or 2
            back = WET_DIR.get(face, 1)
            objs(m, p).remove(o)
            spots = [q for q in room_of(p) if q != p and v.wallish(nb(q, back)) and free_for(q) and keeps_flow(q)
                     and not find(m, q, ("/obj/structure/cable", "/obj/machinery/power", "/obj/machinery/shower",
                                         "/obj/structure/sink", "/obj/structure/toilet", "/obj/structure/urinal"))]
            if spots:
                q = min(spots, key=lambda q: abs(q[0] - p[0]) + abs(q[1] - p[1]))
                objs(m, q).append(o)
                notes.append("%s %d,%d -> %d,%d (off the cable)" % (short(o.path), p[0], p[1], q[0], q[1]))
            else:
                notes.append("removed %s at %d,%d (on cable, no dry wall)" % (short(o.path), p[0], p[1]))
    # 11. vermin live in maintenance and abandoned rooms only
    for p in sorted(zone):
        a = v.area(p)
        if a.startswith("/area/maintenance") or "abandoned" in a:
            continue
        for o in list(objs(m, p)):
            if o.path.startswith(("/mob/living/simple_animal/cockroach", "/mob/living/simple_animal/mouse")):
                drop(p, o, "vermin out of maint")

    # 12. loose solid things (closets, canisters, pumps, vendors, racks) no one can get to, or that pinch a gap
    # shut (two solids touching only at the corner with the way round long): to a free wall spot of the room,
    # else gone
    MOVABLE = ("/obj/structure/closet", "/obj/machinery/portable_atmospherics", "/obj/structure/reagent_dispensers",
               "/obj/machinery/vending", "/obj/structure/rack", "/obj/structure/filingcabinet", "/obj/structure/dresser",
               "/obj/structure/statue", "/obj/structure/displaycase", "/obj/machinery/space_heater")

    def solids(p):
        t = v.t(p)
        if t is None:
            return []
        s = [o for o in t.objs if is_dense(o) and on_floor(o)]
        if any(o.path.startswith("/obj/structure/closet") for o in s):
            s = [o for o in s if o.path.startswith("/obj/structure/closet")][:1]
        return s

    def rehome(p, why):
        moved = False
        for o in [o for o in objs(m, p) if o.path.startswith(MOVABLE) and is_dense(o)]:
            objs(m, p).remove(o)
            inside = [i for i in objs(m, p) if i.path.startswith("/obj/item")] \
                if o.path.startswith("/obj/structure/closet") else []     # what starts inside it
            for i in inside:
                objs(m, p).remove(i)
            def seals(q):
                """Would a solid on q shut a neighbouring floor tile in (its only way out was q)?"""
                return any(v.walk(n_) and not any(v.walk(nb(n_, e)) for e in D4 if nb(n_, e) not in (q, p))
                           for n_ in (nb(q, d) for d in D4))
            cands = [q for q in room_of(p) if q != p and free_for(q) and keeps_flow(q)
                     and any(v.wallish(nb(q, d)) for d in D4) and not solids(q) and not seals(q)]
            if cands:
                q = min(cands, key=lambda q: abs(q[0] - p[0]) + abs(q[1] - p[1]))
                objs(m, q).append(o)
                objs(m, q).extend(inside)
                notes.append("%s %d,%d -> %d,%d (%s)" % (short(o.path), p[0], p[1], q[0], q[1], why))
            else:
                notes.append("removed %s at %d,%d (%s)" % (short(o.path), p[0], p[1], why))
            moved = True
        return moved

    def walk_round(p, q, limit=7):
        seen, frontier = {p: 0}, [p]
        while frontier:
            nxt = []
            for c in frontier:
                if c == q:
                    return seen[c]
                if seen[c] >= limit:
                    continue
                for d in D4:
                    n2 = nb(c, d)
                    if n2 not in seen and v.walk(n2):
                        seen[n2] = seen[c] + 1
                        nxt.append(n2)
            frontier = nxt
        return None

    def walk_parts():
        """Walkable tiles of the zone in 4-way pieces, biggest first."""
        left = {p for p in zone if v.walk(p)}
        parts = []
        while left:
            s = left.pop()
            comp, q = {s}, [s]
            while q:
                c = q.pop()
                for d in D4:
                    n2 = nb(c, d)
                    if n2 in left:
                        left.discard(n2)
                        comp.add(n2)
                        q.append(n2)
            parts.append(comp)
        parts.sort(key=len, reverse=True)
        return parts

    for _round in range(3):
        # a few floor tiles boxed in by loose solids (pumps stacked two deep in a corner): the solids round the
        # pocket go back to the wall until it opens
        parts = walk_parts()
        big = set().union(*[c for c in parts if len(c) > 6]) if parts else set()
        for pocket in parts:
            if len(pocket) > 6:
                continue        # a room of its own (a sealed chamber, a satellite), not a pocket
            for c in sorted(pocket):
                for d in D4:
                    n2 = nb(c, d)
                    if n2 in zone and solids(n2) and not v.walk(n2):
                        rehome(n2, "boxed in floor at %d,%d" % c)
        big = set().union(*[c for c in walk_parts() if len(c) > 6]) if zone else set()
        for p in sorted(zone):
            if not solids(p):
                continue
            if any((p[0] + dx, p[1] + dy) in big for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy):
                continue
            rehome(p, "no one could reach it")
        for p in sorted(zone):
            if not v.walk(p):
                continue
            for dx, dy in ((1, 1), (1, -1)):
                q = (p[0] + dx, p[1] + dy)
                if q not in zone or not v.walk(q):
                    continue
                a, c = (q[0], p[1]), (p[0], q[1])
                if v.walk(a) or v.walk(c) or not solids(a) or not solids(c):
                    continue
                if walk_round(p, q) is not None:
                    continue
                if not rehome(a, "pinched a gap shut"):
                    rehome(c, "pinched a gap shut")

    # 13. transit tubes: a run of tube with fewer than two stations on it leads nowhere (a stock room's leftovers)
    TUBE = "/obj/structure/transit_tube"
    tubed = {p for p in zone if any(o.path.startswith(TUBE) for o in objs(m, p))}
    seen_t = set()
    for s in sorted(tubed):
        if s in seen_t:
            continue
        comp, q = [s], [s]
        seen_t.add(s)
        while q:
            c = q.pop()
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    n2 = (c[0] + dx, c[1] + dy)
                    if n2 in tubed and n2 not in seen_t:
                        seen_t.add(n2)
                        comp.append(n2)
                        q.append(n2)
        stations = sum(1 for p in comp for o in objs(m, p) if o.path.startswith(TUBE + "/station"))
        if stations >= 2:
            continue
        for p in comp:
            for o in [o for o in objs(m, p) if o.path.startswith(TUBE)]:
                drop(p, o, "a transit tube to nowhere")

    # 14. tall pieces (bookcases, lockers, vendors, racks) back onto a wall, never only onto a window
    from forge.furnish import TALL

    def glassy(q):
        t = v.t(q)
        return t is not None and not t.turf.path.startswith("/turf/closed") and any(
            o.path.startswith(("/obj/effect/spawner/structure/window", "/obj/structure/grille", "/obj/structure/window"))
            for o in t.objs)

    def solid_wall(q):
        t = v.t(q)
        return t is not None and t.turf.path.startswith("/turf/closed")

    for p in sorted(zone):
        tall = [o for o in objs(m, p) if o.path.startswith(TALL) and on_floor(o)]
        if not tall:
            continue
        if not any(glassy(nb(p, d)) for d in D4) or any(solid_wall(nb(p, d)) for d in D4):
            continue
        if any(o.path.startswith("/obj/structure/closet") for o in tall):
            tall += [o for o in objs(m, p) if o.path.startswith("/obj/item")]     # what starts inside it
        for o in tall:
            objs(m, p).remove(o)
        cands = [q for q in room_of(p) if q != p and free_for(q) and keeps_flow(q) and not solids(q)
                 and any(solid_wall(nb(q, d)) for d in D4)]
        if cands:
            q = min(cands, key=lambda q: abs(q[0] - p[0]) + abs(q[1] - p[1]))
            objs(m, q).extend(tall)
            notes.append("%s %d,%d -> %d,%d (off the window)" % (short(tall[0].path), p[0], p[1], q[0], q[1]))
        else:
            notes.append("removed %s at %d,%d (against a window, no wall free)" % (short(tall[0].path), p[0], p[1]))

    # 15. wall fixtures hang the way the stock maps hang them, on a wall that is there: a rotated template turned
    # urinals onto side walls (their sprite only faces south) and left sinks floating mid-room
    for p in sorted(zone):
        for o in list(objs(m, p)):
            how = fixture_ways(o.path)
            if not how or not on_floor_tile(v, p):
                continue
            if o.path.startswith(("/obj/structure/sink", "/obj/structure/urinal")) and find(m, p, ("/obj/structure/table",)):
                continue            # a sink set in a counter
            want = wall_side_of(o)
            sides = [w for w in how if hangable(v, nb(p, w))]
            pick = want if want in sides else (sides[0] if sides else None)
            if pick is not None:
                if hang(o, how[pick]):
                    notes.append("%s at %d,%d hung on its %s wall" % (short(o.path), p[0], p[1], {1: "N", 2: "S", 4: "E", 8: "W"}[pick]))
                continue
            objs(m, p).remove(o)
            cands = []
            for q in room_of(p):
                if q == p or not free_for(q) or find(m, q, WET + ("/obj/structure/mirror",)):
                    continue
                if o.path.startswith(WET) and find(m, q, ("/obj/structure/cable", "/obj/machinery/power")):
                    continue        # no water over live cable (step 10)
                ws = [w for w in how if hangable(v, nb(q, w))]
                if ws and (o.path.startswith("/obj/structure/mirror") or keeps_flow(q)):
                    cands.append((abs(q[0] - p[0]) + abs(q[1] - p[1]), q, ws[0]))
            if cands:
                _, q, w = min(cands)
                hang(o, how[w])
                objs(m, q).append(o)
                notes.append("%s %d,%d -> %d,%d (onto a wall it can hang on)" % (short(o.path), p[0], p[1], q[0], q[1]))
            else:
                notes.append("removed %s at %d,%d (no wall it can hang on)" % (short(o.path), p[0], p[1]))
    # 16. a chair whose desk or partner a later step moved: last sweep
    for p in sorted(zone):
        for o in list(objs(m, p)):
            if o.path.startswith(CHAIR) and "/stool" not in o.path and "/sofa" not in o.path \
                    and "/pew" not in o.path and not v.area(p).startswith("/area/maintenance") \
                    and chair_purpose(v, p, o) is None:
                drop(p, o, "a chair for nothing (after the moves)")
    return notes


# wall fixtures: the wall side -> (dir, pixel_x, pixel_y), as the stock maps hang them (dir None: the default)
FIXTURES = [
    ("/obj/structure/sink/kitchen", {1: (None, 0, 28)}),
    ("/obj/structure/sink", {8: (8, -12, 0), 4: (4, 11, 0), 1: (None, 0, 28)}),
    ("/obj/structure/urinal", {1: (None, 0, 29)}),
    ("/obj/structure/toilet", {1: (None, 0, 8), 8: (4, 0, 0), 4: (8, 0, 0), 2: (1, 0, 0)}),
    ("/obj/structure/mirror", {1: (None, 0, 28), 8: (None, -28, 0), 4: (None, 28, 0)}),
]


def fixture_ways(path):
    for pre, how in FIXTURES:
        if path == pre or path.startswith(pre + "/"):
            return how
    return None


def hangable(v, q):
    """A wall or a full window: stock maps hang sinks and mirrors on either."""
    t = v.t(q) if q else None
    return t is not None and (t.turf.path.startswith("/turf/closed") or any(
        o.path.startswith(("/obj/effect/spawner/structure/window", "/obj/structure/grille")) for o in t.objs))


def on_floor_tile(v, p):
    t = v.t(p)
    return t is not None and t.turf.path.startswith("/turf/open")


def wall_side_of(o):
    """Which wall a fixture means to hang on, by its pixel offset, else by which way it faces."""
    px, py = o.num("pixel_x"), o.num("pixel_y")
    if abs(px) >= 6 and abs(px) >= abs(py):
        return 4 if px > 0 else 8
    if abs(py) >= 6:
        return 1 if py > 0 else 2
    if o.path.startswith("/obj/structure/toilet"):
        return {2: 1, 1: 2, 4: 8, 8: 4}.get(o.num("dir", 2) or 2)
    return None


def hang(o, spec):
    """Set a fixture's dir and pixel offsets; True if anything changed."""
    d, px, py = spec
    old = list(o.vars)
    o.vars = [kv for kv in o.vars if kv[0] not in ("dir", "pixel_x", "pixel_y")]
    if d is not None and d != 2:
        o.vars.append(("dir", str(d)))
    if px:
        o.vars.append(("pixel_x", str(px)))
    if py:
        o.vars.append(("pixel_y", str(py)))
    return sorted(old) != sorted(o.vars)


# ---------------------------------------------------------------------------------------------------- cryo
# MetaStation's cryo bay, from the wall out: freezer and two oxygen connectors on the wall, two rows of visible pipe
# you walk over, the two cells facing the room. (col, row) -> [(kind, mask or dir)] in wall-relative terms:
# U = away from the wall, D = toward it, L/R along it.
CRYO = {
    (0, 0): [("freezer", "U")], (1, 0): [("connector", "U"), ("o2", None)], (2, 0): [("connector", "U"), ("o2", None)],
    (0, 1): [("manifold", "L")], (1, 1): [("manifold", "U")], (2, 1): [("simple", "DL")],
    (0, 2): [("simple", "DR")], (1, 2): [("manifold", "D")], (2, 2): [("simple", "UL")],
    (1, 3): [("cell", "D")], (2, 3): [("cell", "D")],
}
CRYO_PATHS = {"freezer": "/obj/machinery/atmospherics/components/unary/thermomachine/freezer",
              "connector": "/obj/machinery/atmospherics/components/unary/portables_connector/visible",
              "o2": "/obj/machinery/portable_atmospherics/canister/oxygen",
              "manifold": "/obj/machinery/atmospherics/pipe/manifold/general/visible",
              "simple": "/obj/machinery/atmospherics/pipe/simple/general/visible",
              "cell": "/obj/machinery/atmospherics/components/unary/cryo_cell"}


def place_cryo(b, area):
    """Put a cryo bay in the room of that area (on the Builder b, before its pipes are routed). Returns a note."""
    floors = set(b.floors_of(area))
    if not floors:
        return "no %s room for cryo" % area
    v = View(b.m, b.zone)
    best = None
    for wall in D4:                         # the wall behind the freezer row
        up = OPP[wall]
        for side in (1, -1):               # which way the columns run along it
            lr = [d for d in D4 if d not in (wall, up)]
            right = lr[0] if side == 1 else lr[1]
            left = OPP[right]
            rel = {"U": up, "D": wall, "L": left, "R": right}
            for c0 in floors:
                tiles = {}
                for (col, row) in [(c, r) for c in range(3) for r in range(4)]:
                    p = (c0[0] + D4[right][0] * col + D4[up][0] * row, c0[1] + D4[right][1] * col + D4[up][1] * row)
                    tiles[(col, row)] = p
                if not all(p in floors for p in tiles.values()):
                    continue
                if not all(v.wallish(nb(tiles[(c, 0)], wall)) for c in range(3)):
                    continue
                front = [nb(tiles[(c, 3)], up) for c in (1, 2)]
                if not all(q in floors and v.walk(q) for q in front):
                    continue
                if any(v.door(nb(p, d)) or b.t(*nb(p, d)).has("/obj/machinery/door") for p in tiles.values() for d in D4):
                    continue
                # what stands there now (dense pieces lost, items moved off)
                lost = sum(1 for p in tiles.values() for o in b.t(*p).objs if is_dense(o))
                # the room stays one piece with the cells and the wall row solid
                solid = {tiles[k] for k in CRYO if k[1] in (0, 3)}
                rest = {p for p in floors if p not in solid and (v.walk(p) or p in tiles.values())}
                start = next(iter(rest))
                seen, q = {start}, [start]
                while q:
                    c = q.pop()
                    for d in D4:
                        n2 = nb(c, d)
                        if n2 in rest and n2 not in seen:
                            seen.add(n2)
                            q.append(n2)
                if len(seen) != len(rest):
                    continue
                score = lost * 3 + (0 if v.wallish(nb(tiles[(0, 0)], left)) else 1)
                if best is None or score < best[0]:
                    best = (score, tiles, rel)
    if best is None:
        return "no wall in %s fits a cryo bay" % area
    _, tiles, rel = best
    for k, p in tiles.items():
        t = b.t(*p)
        t.objs = [o for o in t.objs if not is_dense(o) and not o.path.startswith(("/obj/item", "/obj/structure/chair",
                                                                                  "/obj/machinery/atmospherics"))]
        for kind, spec in CRYO.get(k, []):
            path = CRYO_PATHS[kind]
            vs = []
            if kind in ("freezer", "connector", "cell"):
                d = rel[spec]
                vs = [("dir", str(d))] if d != 2 else []
            elif kind == "manifold":
                d = rel[spec]
                vs = [("dir", str(d))] if d != 2 else []
            elif kind == "simple":
                mask = rel[spec[0]] | rel[spec[1]]
                vs = [("dir", str(mask))] if mask not in (1 | 2,) else []
                if mask == 4 | 8:
                    vs = [("dir", "4")]
            if kind == "connector":
                vs.append(("name", '"Connector Port (Air Supply)"'))
            t.objs.append(dmm.Atom(path, vs))
    return "cryo bay at %d,%d" % tiles[(0, 0)]


if __name__ == "__main__":
    for path in sys.argv[1:]:
        m = dmm.read(path)
        probs = review(m)
        c = Counter(r for r, _, _ in probs)
        print("== %s: %d %s" % (os.path.basename(path), len(probs), dict(c)))
        for r, p, txt in probs[:400 if len(sys.argv) == 2 else 12]:
            print("   %-6s %3d,%3d  %s" % (r, p[0], p[1], txt))
