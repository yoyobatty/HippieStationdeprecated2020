"""Engineering's function pass on a finished station: the checks of studies/dept_specs/engineering.md (each with its
stock count) and the fixes a finished layout allows. Engineering is the user's top priority (2026-11-26: "I think we
should work engineering properly. Get it right"; "engineering needs safety, showers, equipment").

    python tools/mapforge/gen/learn/fn_engineering.py <in.dmm> [out.dmm]     # check() before and after fix()
    from gen.learn import fn_engineering as FE
    FE.check(m) -> [(x, y, text)]
    FE.fix(m, seed=1, log=print) -> number of changes

What it checks and fixes. Stock counts are over the 7 stock families (Meta, Box, Delta, Hippie, Pubby, Donut, Endo;
MetaLake is Meta); check() on them: Meta, Box, Hippie 0 findings, Delta 5, Pubby 3, Donut 6, Endo 3 (their minority
cases), on f22 (crew 100 seed 7) 45 before, 4 after (the atmos disposal bin and 3 layout findings).
  way_in      the walk from the department's front (its hall airlocks, tech storage's left out) to the crystal's
              chamber door passes, before the engine's own door, a shower (5/7), a radiation closet (6/7) and a fire
              closet (5/7) within 2 steps: the "Engine Room" vestibule (6-12 tiles, two showers facing across a
              1-tile aisle, 1-2 radiation and fire closets, cycling airlocks). Fix: two facing showers, two radiation
              closets and a fire closet beside the walk on the department side of the engine door, off its path
  rad_sign    a radiation/secure-area sign along the last 12 steps of the walk in (5/6 where the walk is found) and
              at the gravity generator (5/7). Fix: radiation sign on the wall beside the door
  corridor    the department corridor (/area/engine) meets the engine only through glass (the engine block's wall
              row took the stem's end): the window becomes the "Engine Room" airlock (access 10)
  engine_door an airlock into the engine with no access (stock 7/7: 10, or 24;10): access 10
  store       the walk in goes through a store (SMES bank, engineering storage, gravity generator, CE's office,
              tech storage; stock 6/6: foyer, vestibule, main room): its door into the engine walled up while a
              way in from the corridor or a main room stays and every room stays reached
  grav        two radiation closets in the gravity generator's rooms or by their doors (6/7, in its foyer)
  terminal    no power terminal without an SMES facing it (6/7; Delta has one)
  ce_office   every airlock takes the CE's access 56 (7/7); one onto the station (6/7; Delta's second is the CE's
              own quarters: a door to a room reached only through the office is allowed); glass onto the
              department (7/7) with privacy shutters (5/7) and their button. Fix: the extra door becomes a shuttered
              window (or wall), after the office's furniture is moved off the CE's own door's way (_unbox)
  checkpoint  the security post opens on a hall or the department's floor (6/6 posts), not through a store: an
              airlock onto the hall, the old door walled up
  tech        tech storage opens on a hall (7/7, access 23), its inner door named for it; the secure room opens
              into tech storage only, one door (6/6); the nine circuit board spawners, six in tech storage and
              AI/command/RnD_secure in the secure room (7/7 exactly; ours had none on the station). Fix: hall door
              (a table in the way moved), racks cleared off the store's far side, the secure room's second door
              walled, the suit storage unit out, spawners on racks
  foyer       the break room / foyer opens on a hall for engineers and atmospheric technicians (6/7, 32;19)
  atmos_door  the door between engineering and Atmospherics is an atmos airlock named for it, access 24 (6/6)
  atmos       Atmospherics' hall airlocks need access 24 (7/7), its front desk onto the hall (7/7), and its kit:
              two atmos lockers (they hold the fire suits, backpack water tanks and advanced extinguishers: the
              firefighting gear), wardrobe, atmos suit storage, fire axe cabinet, two extinguisher cabinets, pipe
              dispenser (6/7), portable pumps and scrubbers (6/7), tank dispenser, alert console, requests console,
              fuel and high-capacity water tanks (6/7), spare canisters (7/7 each unless said)
Checks only (layout, see the spec's generator changes): secure storage behind blast doors (emitters, field and
shield generators, 7/7), an external airlock (6/7), tank dispensers at most 2 (7/7), a disposal bin in Atmospherics
(needs gen/net.py's disposal network).

Run it last, after gen/audit.py trim and mend (trim would take the vestibule's closets as a corridor's surplus, and
doordb.style would rename the doors it makes).
"""
import os
import random
import sys
from collections import deque

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(HERE, "..", "..", "station"))
sys.path.insert(0, os.path.join(HERE, "..", "..", "studies"))
from forge import corpus as CO, dmm, function as FN, kit as KT  # noqa: E402

N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
DIRV = {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0)}
SIDE = {(0, 1): 1, (0, -1): 2, (1, 0): 4, (-1, 0): 8}
OPP = {1: 2, 2: 1, 4: 8, 8: 4}
DOORISH = ("/obj/machinery/door/airlock", "/obj/machinery/door/poddoor", "/obj/machinery/door/window",
           "/obj/machinery/door/password")
UNDER = ("/obj/structure/cable", "/obj/machinery/atmospherics/pipe", "/obj/structure/disposalpipe")
WINDOWISH = ("/obj/effect/spawner/structure/window", "/obj/structure/window", "/obj/structure/grille")

CORR = "/area/engine"                       # gen/rooms.py CORRIDOR_AREA["engineering"]
CE = "/area/crew_quarters/heads/chief"
CHECKPOINT = "/area/security/checkpoint/engineering"
TECH = "/area/storage/tech"
BREAK = "/area/engine/break_room"
GRAV = "/area/engine/gravity_generator"
STORAGE = ("/area/engine/storage", "/area/engine/storage_shared")

SHOWER = "/obj/machinery/shower"
RAD = "/obj/structure/closet/radiation"
FIRE = "/obj/structure/closet/firecloset"
CRYSTAL = "/obj/machinery/power/supermatter_crystal"
RAD_SIGN = "/obj/structure/sign/warning/radiation/rad_area"
SIGNS = ("/obj/structure/sign/warning/radiation", "/obj/structure/sign/warning/securearea")
BOARDS = "/obj/effect/spawner/lootdrop/techstorage/"
TECH_BOARDS = ("service", "rnd", "security", "engineering", "tcomms", "medical")
SECURE_BOARDS = ("AI", "command", "RnD_secure")
ENGINE_R = 12        # an engine room lies wholly within this many tiles of the crystal (the stamped block and stock)
SIGN_SPAN = 12       # a warning sign along the last steps of the walk in (stock: by the vestibule or engine doors)
NEAR_WAY = 2         # the safety gear stands this close to the walk in (stock: 1 step on 5 of 6 maps)
GRAV_NEAR = 6        # radiation closets by the gravity generator's door (stock foyers: 1-3 steps)

# Atmospherics' kit: (what to count, how many, atoms to add), 7/7 stock maps hold each (studies/dept_specs/engineering.md)
ATMOS_KIT = [
    ("/obj/structure/closet/secure_closet/atmospherics", 2, ["/obj/structure/closet/secure_closet/atmospherics"]),
    ("/obj/machinery/vending/wardrobe/atmos_wardrobe", 1, ["/obj/machinery/vending/wardrobe/atmos_wardrobe"]),
    ("/obj/machinery/suit_storage_unit/atmos", 1, ["/obj/machinery/suit_storage_unit/atmos"]),
    ("/obj/machinery/pipedispenser", 1, ["/obj/machinery/pipedispenser"]),
    ("/obj/machinery/portable_atmospherics/pump", 2, ["/obj/machinery/portable_atmospherics/pump"]),
    ("/obj/machinery/portable_atmospherics/scrubber", 2, ["/obj/machinery/portable_atmospherics/scrubber"]),
    ("/obj/structure/tank_dispenser", 1, ["/obj/structure/tank_dispenser"]),
    ("/obj/machinery/computer/atmos_alert", 1, ["/obj/machinery/computer/atmos_alert"]),
    ("/obj/structure/reagent_dispensers/fueltank", 1, ["/obj/structure/reagent_dispensers/fueltank"]),
    ("/obj/structure/reagent_dispensers/watertank", 1, ["/obj/structure/reagent_dispensers/watertank/high"]),
    ("/obj/machinery/disposal/bin", 1, None),               # needs a pipe: counted, not added
]
# spare canisters by the front (stock: 8-12 in the monitoring room, 11-18 in all; the block's own sit on its ports)
SPARE_CANS = ["/obj/machinery/portable_atmospherics/canister/air", "/obj/machinery/portable_atmospherics/canister/oxygen",
              "/obj/machinery/portable_atmospherics/canister/nitrogen",
              "/obj/machinery/portable_atmospherics/canister/carbon_dioxide",
              "/obj/machinery/portable_atmospherics/canister/nitrous_oxide",
              "/obj/machinery/portable_atmospherics/canister"]
SPARE_CANS_MIN = 6
ATMOS_MOUNTS = [("/obj/structure/fireaxecabinet", 1, "sign", []),
                ("/obj/structure/extinguisher_cabinet", 2, "extinguisher", []),
                ("/obj/machinery/requests_console", 1, "requests_console",
                 [("department", '"Atmospherics"'), ("departmentType", "3"), ("name", '"Atmos RC"')])]


# ------------------------------------------------------------------------------------------------ map reading
def group(area):
    import stations as STN
    if not area:
        return None
    if area.startswith(CHECKPOINT):
        return "engineering"
    return STN.group_of(area)


def is_door(t):
    return t is not None and any(o.path.startswith(DOORISH) for o in t.objs)


def airlock(t):
    if t is None:
        return None
    return next((o for o in t.objs if o.path.startswith("/obj/machinery/door/airlock")), None)


def floor(t):
    return t is not None and t.tpath.startswith("/turf/open") and not t.tpath.startswith("/turf/open/space") \
        and not CO.solid(t) and not is_door(t)


def dense(t):
    return any(FN.is_dense(o) for o in t.objs)


def walkable(t):
    if t is None or not t.tpath.startswith("/turf/open") or t.tpath.startswith("/turf/open/space"):
        return False
    if is_door(t):
        # an airlock or open blast door; a shutter over a window or a windoor on a desk is no way through
        return not CO.solid(t) and not t.has("/obj/structure/table")
    return not CO.solid(t) and not dense(t)


def has(t, pre):
    return t is not None and any(o.path.startswith(pre) for o in t.objs)


def access(a):
    v = set()
    for k, val in a.vars:
        if k in ("req_access_txt", "req_one_access_txt"):
            v |= {s.strip() for s in val.strip('"').split(";") if s.strip() not in ("", "0")}
    return v


def set_access(a, one=None, req=None):
    a.vars = [(k, v) for k, v in a.vars if k not in ("req_access_txt", "req_one_access_txt", "req_access", "req_one_access")]
    if req:
        a.vars.append(("req_access_txt", '"%s"' % req))
    if one:
        a.vars.append(("req_one_access_txt", '"%s"' % one))


def set_var(a, k, v):
    a.vars = [(k_, v_) for k_, v_ in a.vars if k_ != k] + [(k, v)]


def pieces(m, pred):
    """[(area, tiles)]: connected floor of one area, doors apart, for areas pred(area) accepts."""
    seen, out = set(), []
    for (x, y, z), t in sorted(m.tiles.items()):
        if z != 1 or (x, y) in seen or not floor(t) or not pred(t.apath):
            continue
        a = t.apath
        comp, q = {(x, y)}, [(x, y)]
        seen.add((x, y))
        while q:
            p = q.pop()
            for dx, dy in N4:
                n = (p[0] + dx, p[1] + dy)
                if n in seen:
                    continue
                tn = m.get(*n)
                if floor(tn) and tn.apath == a:
                    seen.add(n)
                    comp.add(n)
                    q.append(n)
        out.append((a, comp))
    return out


def doors_of(m, tiles):
    """[(door tile, inside tile, across tile)] for the airlocks (and windoors) round a piece."""
    out = []
    for p in tiles:
        for dx, dy in N4:
            d = (p[0] + dx, p[1] + dy)
            t = m.get(*d)
            if not is_door(t):
                continue
            q = (d[0] + dx, d[1] + dy)
            while is_door(m.get(*q)) and abs(q[0] - d[0]) + abs(q[1] - d[1]) < 3:
                q = (q[0] + dx, q[1] + dy)          # a double door (cycling airlocks, a firelock line)
            out.append((d, p, q))
    return out


def hall(t):
    return t is not None and t.apath.startswith("/area/hallway")


def reached_from_halls(m):
    """Walking reach (doors open to all, furniture blocks) from every hall tile."""
    starts = [(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and hall(t) and walkable(t)]
    return bfs(m, starts)


def bfs(m, starts, limit=None, keep=None):
    dist = {s: 0 for s in starts}
    q = deque(starts)
    while q:
        p = q.popleft()
        if limit is not None and dist[p] >= limit:
            continue
        for dx, dy in N4:
            n = (p[0] + dx, p[1] + dy)
            if n in dist:
                continue
            tn = m.get(*n)
            if not walkable(tn) or (keep is not None and n not in keep and not is_door(tn)):
                continue
            dist[n] = dist[p] + 1
            q.append(n)
    return dist


def passable(t):
    """The building's ways, furniture ignored (the walk in must not move when a closet is put beside it): floor and
    doors, not walls, windows, shutters over windows or desks."""
    if t is None or not t.tpath.startswith("/turf/open") or t.tpath.startswith("/turf/open/space"):
        return False
    if is_door(t):
        return not CO.solid(t) and not t.has("/obj/structure/table")
    return not CO.solid(t)


def walk_path(m, starts, goals, ok=None):
    """Shortest walk from starts to goals (ties broken the same way each time), over tiles ok() accepts."""
    ok = ok or walkable
    starts = sorted(starts)
    prev = {s: None for s in starts}
    q = deque(starts)
    while q:
        p = q.popleft()
        if p in goals:
            out = []
            while p is not None:
                out.append(p)
                p = prev[p]
            return out[::-1]
        for dx, dy in N4:
            n = (p[0] + dx, p[1] + dy)
            if n in prev or not ok(m.get(*n)):
                continue
            prev[n] = p
            q.append(n)
    return None


def near(m, tiles, pre, limit, avoid=frozenset()):
    """Fewest steps from any of tiles to a tile holding pre (a dense one counts once beside it); None past limit.
    Tiles in avoid (the engine zone) are neither walked nor counted."""
    tiles = [p for p in tiles if p not in avoid]
    dist = {p: 0 for p in tiles}
    q = deque(tiles)
    while q:
        p = q.popleft()
        if has(m.get(*p), pre):
            return dist[p]
        if dist[p] >= limit:
            continue
        for dx, dy in N4:
            n = (p[0] + dx, p[1] + dy)
            if n in dist or n in avoid:
                continue
            tn = m.get(*n)
            if tn is None:
                continue
            if has(tn, pre):
                return dist[p] + 1
            if walkable(tn):
                dist[n] = dist[p] + 1
                q.append(n)
    return None


def count_near(m, starts, pre, limit, avoid=frozenset()):
    """Tiles holding pre that stand on or beside floor walked to within `limit` steps of starts (a closet is dense:
    it is used from the tile beside it); tiles in avoid neither walked nor counted."""
    starts = [p for p in starts if p not in avoid]
    dist = {s_: 0 for s_ in starts}
    q = deque(starts)
    while q:
        p = q.popleft()
        if dist[p] >= limit:
            continue
        for dx, dy in N4:
            n = (p[0] + dx, p[1] + dy)
            if n in dist or n in avoid or not walkable(m.get(*n)):
                continue
            dist[n] = dist[p] + 1
            q.append(n)
    out = set()
    for p in dist:
        for dx, dy in ((0, 0),) + N4:
            r_ = (p[0] + dx, p[1] + dy)
            if r_ not in avoid and has(m.get(*r_), pre):
                out.add(r_)
    return out


# ------------------------------------------------------------------------------------------------ the department
class Dept:
    """Engineering as found on a map: its pieces, the engine zone round the crystal, the fronts and the way in."""

    def __init__(self, m):
        self.m = m
        self.eng = pieces(m, lambda a: group(a) == "engineering")
        self.atmos = pieces(m, lambda a: group(a) == "atmos")
        self.crystals = [(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and has(t, CRYSTAL)]
        self.ez = set()
        for a, F in self.eng:
            if self.crystals and all(min(max(abs(p[0] - c[0]), abs(p[1] - c[1])) for c in self.crystals) <= ENGINE_R
                                     for p in F) and not self._vestibule(F):
                self.ez |= F
        for a, F in pieces(m, lambda a: a.startswith("/area/engine/supermatter")):
            self.ez |= F
        self.chamber = {(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and (
            any(o.path.startswith("/obj/machinery/door/airlock") and o.path.endswith("/critical") for o in t.objs)
            or (t.apath.startswith("/area/engine/supermatter") and airlock(t)))}
        # engine-ward doors: an airlock with the engine zone on one side and the rest of engineering on the other
        self.entrances = []
        for a, F in self.eng:
            if F & self.ez:
                continue
            for d, p, q in doors_of(m, F):
                if q in self.ez and airlock(m.get(*d)) and d not in self.chamber:
                    self.entrances.append((d, p, q, a))
        self.fronts = []
        for a, F in self.eng:
            if a.startswith((TECH, CHECKPOINT)):
                continue
            for d, p, q in doors_of(m, F):
                if airlock(m.get(*d)) and hall(m.get(*q)):
                    self.fronts.append(d)

    def _vestibule(self, F):
        """A small room of 2+ airlocks holding showers or radiation closets: the way in, never the engine (Delta's
        "Atmospherics Engine Access" stands 9 tiles from its crystal)."""
        m = self.m
        return len(F) <= 16 and sum(1 for d, p, q in doors_of(m, F) if airlock(m.get(*d))) >= 2 and any(
            has(m.get(*p), (SHOWER, RAD)) for p in F)

    def piece(self, pre):
        return [(a, F) for a, F in self.eng + self.atmos if a == pre or a.startswith(pre + "/")]

    def way_in(self):
        if not self.fronts or not self.chamber:
            return None
        # the building's way (furniture ignored), then one a person can walk if furniture blocks that one
        p = walk_path(self.m, self.fronts, self.chamber, passable)
        if p and all(walkable(self.m.get(*q)) for q in p):
            return p
        return walk_path(self.m, self.fronts, self.chamber) or p

    def way_to_door(self, path=None):
        """The walk in up to (not into) the engine zone: where engineers suit up and wash off."""
        path = path or self.way_in()
        if not path:
            return None
        out = []
        for q in path:
            if q in self.ez:
                break
            out.append(q)
        return out

    def main_entrance(self):
        """(door, department-side tile, engine-side tile, area) where the walk in enters the engine zone."""
        p = self.way_in()
        if p:
            for i, q in enumerate(p):
                if q in self.ez and i >= 2 and airlock(self.m.get(*p[i - 1])):
                    d, inside = p[i - 1], p[i - 2]
                    a = self.m.get(*inside).apath
                    return d, inside, q, a
        if self.entrances:
            d, p_, q, a = self.entrances[0]
            return d, p_, q, a
        return None


# ------------------------------------------------------------------------------------------------ checks
def check(m):
    D = Dept(m)
    out = []
    if not D.eng:
        return [(0, 0, "no engineering on this map")]
    # the way in and its safety gear
    if not D.crystals:
        out.append((0, 0, "way_in: no supermatter crystal"))
    path = D.way_in()
    ent = D.main_entrance()
    if D.crystals and not path:
        out.append((0, 0, "way_in: no walk from the department's front (%d hall doors) to the crystal's door" % len(D.fronts)))
    if path:
        x, y = ent[0] if ent else path[0]
        pre_path = D.way_to_door(path)
        for pre, what, share in ((SHOWER, "shower", "5/7"), (RAD, "radiation closet", "6/7"), (FIRE, "fire closet", "5/7")):
            n = near(m, pre_path, pre, 12, avoid=D.ez)
            if n is None or n > NEAR_WAY:
                out.append((x, y, "way_in: the walk to the engine (%d steps) passes no %s within %d steps before its door "
                                  "(%s; stock %s: 1 step, the Engine Room vestibule)" % (len(path), what, NEAR_WAY, n, share)))
    if path and not _signed(m, D.way_to_door(path)[-SIGN_SPAN:], D.ez):
        x, y = ent[0] if ent else path[0]
        out.append((x, y, "rad_sign: no radiation/secure-area sign along the last %d steps of the walk in (stock 5/6 "
                          "where found)" % SIGN_SPAN))
    for d, p, q, a in D.entrances:
        if not access(airlock(m.get(*d))):
            out.append((d[0], d[1], "engine_door: %s into the engine opens for anyone (stock 7/7: access 10, or 24;10)"
                        % airlock(m.get(*d)).get("name")))
    if ent and path and _store(m, ent[1], D):
        out.append((ent[0][0], ent[0][1], "store: the walk into the engine goes through %s (stock 6/6: through the "
                                          "foyer, vestibule and main room; stores are dead ends)" % m.get(*ent[1]).apath))
    # the corridor ends at a window onto the engine
    for a, F in D.piece(CORR):
        if a != CORR:
            continue
        if any(q in D.ez for d, p, q in doors_of(m, F) if airlock(m.get(*d))):
            continue
        w = _corridor_windows(m, F, D.ez)
        if w:
            out.append((w[0][0][0], w[0][0][1], "corridor: the engineering corridor meets the engine only through glass"))
    # gravity generator
    suite, gmain, outer = _grav_suite(m, D)
    if gmain:
        n = len({p for p in suite if has(m.get(*p), RAD)} | count_near(m, [d for d, p, q in outer], RAD, GRAV_NEAR // 2))
        g = outer[0][0] if outer else gmain
        if n < 2:
            out.append((g[0], g[1], "grav: %d radiation closets in the gravity generator's rooms or by their doors (stock "
                                    "6/7: 2, in its foyer)" % n))
        if not _signed(m, list(suite) + [d for d, p, q in outer]):
            out.append((g[0], g[1], "rad_sign: no radiation sign at the gravity generator (stock 5/7)"))
    # power terminals
    for x, y, why in orphan_terminals(m):
        out.append((x, y, "terminal: " + why))
    # CE office
    for a, F in D.piece(CE):
        locks = [(d, q) for d, p, q in doors_of(m, F) if airlock(m.get(*d))]
        for d, q in locks:
            if "56" not in access(airlock(m.get(*d))):
                out.append((d[0], d[1], "ce_office: an airlock the CE's access (56) doesn't guard: %s %s (stock 7/7: all 56)"
                            % (airlock(m.get(*d)).get("name", ""), sorted(access(airlock(m.get(*d)))))))
        if len(locks) > 1:
            own = _private_doors(m, F, locks)
            if len(locks) - len(own) > 1:
                out.append((locks[0][0][0], locks[0][0][1], "ce_office: %d airlocks onto the station (stock 6/7: 1; Delta's "
                                                            "second is the CE's own quarters)" % (len(locks) - len(own))))
        glass = _glass_of(m, F, lambda t: group(t.apath) == "engineering" and t.apath != CE)
        if not glass:
            out.append((min(F)[0], min(F)[1], "ce_office: no window onto the department (stock 7/7)"))
        elif not any(has(m.get(*w), "/obj/machinery/door/poddoor") for w in glass):
            out.append((glass[0][0], glass[0][1], "ce_office: windows without privacy shutters (stock 5/7)"))
    # checkpoint
    for a, F in sorted(D.piece(CHECKPOINT), key=lambda af: -len(af[1]))[:1]:       # the post (cells are pieces too)
        locks = [(d, q) for d, p, q in doors_of(m, F) if airlock(m.get(*d))]
        if not any(_front_ok(m, q) for d, q in locks):
            d = locks[0][0] if locks else min(F)
            out.append((d[0], d[1], "checkpoint: no airlock onto a hall or the department's floor (stock 6/6 posts); it opens on %s"
                        % ", ".join(sorted({m.get(*q).apath.replace("/area/", "") for d, q in locks if m.get(*q)}))))
    # tech storage
    tech = D.piece(TECH)
    if tech:
        main = max(tech, key=lambda af: len(af[1]))
        locks = [(d, q) for d, p, q in doors_of(m, main[1]) if airlock(m.get(*d))]
        if not any(hall(m.get(*q)) for d, q in locks):
            out.append((min(main[1])[0], min(main[1])[1], "tech: tech storage has no airlock onto a hall (stock 7/7, access 23)"))
        for d, q in locks:
            a_ = airlock(m.get(*d))
            tq = m.get(*q)
            if tq is not None and tq.apath in (CORR, "/area/engine/engineering", BREAK) and "Tech" not in (a_.get("name") or ""):
                out.append((d[0], d[1], "tech: tech storage's door is named %s" % a_.get("name")))
        mainF, secs = _secure_pieces(m, tech)
        loose = _secure_pieces(m, tech, strict=False)[1]
        for kind, F, want in (("tech storage", main[1], TECH_BOARDS),
                              ("secure tech storage", set().union(*secs) if secs else set(), SECURE_BOARDS)):
            have = {o.path[len(BOARDS):] for p in F for o in m.get(*p).objs if o.path.startswith(BOARDS)}
            miss = [b for b in want if b not in have]
            if miss and F:
                out.append((min(F)[0], min(F)[1], "tech: %s lacks the circuit board spawners %s (stock 7/7)" % (kind, ", ".join(miss))))
            elif miss and not F and kind.startswith("secure"):
                out.append((min(main[1])[0], min(main[1])[1], "tech: no secure tech storage (stock 6/7) and no %s boards" % ", ".join(miss)))
        for a, F in tech:
            if F is main[1]:
                continue
            if not any(F is x for x in secs) and not any(F is x for x in loose):
                out.append((min(F)[0], min(F)[1], "tech: a tech storage room of %d tiles opening on %s (no secure room: "
                                                  "the secure room opens into tech storage only)" % (len(F), ", ".join(sorted(
                                                      {m.get(*q).apath for d, p, q in doors_of(m, F) if m.get(*q)})))))
                continue
            locks2 = [d for d, p, q in doors_of(m, F) if airlock(m.get(*d))]
            if len(locks2) > 1:
                out.append((locks2[0][0], locks2[0][1], "tech: the secure room has %d airlocks (stock 6/6: 1)" % len(locks2)))
            for p in F:
                for o in m.get(*p).objs:
                    if o.path.startswith("/obj/machinery/suit_storage_unit"):
                        out.append((p[0], p[1], "tech: a suit storage unit in secure tech storage"))
    # foyer
    br = D.piece(BREAK)
    if br and not any(hall(m.get(*q)) for a, F in br for d, p, q in doors_of(m, F) if airlock(m.get(*d))):
        F = max(br, key=lambda af: len(af[1]))[1]
        out.append((min(F)[0], min(F)[1], "foyer: the break room / foyer has no airlock onto a hall (stock 6/7, 32;19)"))
    # engineering <-> atmos
    for d, why in _atmos_doors(m):
        out.append((d[0], d[1], "atmos_door: " + why))
    # atmospherics
    out += _atmos_check(m, D)
    # layout-level (generator changes)
    if not _secure_storage(m, D):
        out.append((0, 0, "layout: no secure storage of emitters, field and shield generators behind blast doors (stock 7/7)"))
    ext = sum(1 for a, F in D.eng for d, p, q in doors_of(m, F)
              if airlock(m.get(*d)) and "external" in airlock(m.get(*d)).path)
    if not ext:
        out.append((0, 0, "layout: no external airlock from engineering (stock 6/7)"))
    td = [p for a, F in D.eng for p in F if has(m.get(*p), "/obj/structure/tank_dispenser")]
    if len(td) > 2:
        out.append((td[0][0], td[0][1], "layout: %d tank dispensers in engineering (stock 1-2)" % len(td)))
    return out


def _signed(m, tiles, avoid=frozenset()):
    """A radiation/secure-area sign on or beside (2 tiles) any of tiles, on a wall or hung from a floor tile."""
    for p in tiles:
        for ex in (-2, -1, 0, 1, 2):
            for ey in (-2, -1, 0, 1, 2):
                if has(m.get(p[0] + ex, p[1] + ey), SIGNS):
                    return True
    return False


def _grav_suite(m, D):
    """The gravity generator's rooms (all pieces of its area), the airlocks out of them, its main tile."""
    suite = set()
    for a, F in D.piece(GRAV):
        suite |= F
    main = next((p for p in suite if has(m.get(*p), "/obj/machinery/gravity_generator/main")), None)
    outer = []
    for p in suite:
        for dx, dy in N4:
            d = (p[0] + dx, p[1] + dy)
            if airlock(m.get(*d)):
                q = (d[0] + dx, d[1] + dy)
                while is_door(m.get(*q)):
                    q = (q[0] + dx, q[1] + dy)
                if q not in suite:
                    outer.append((d, p, q))
    return suite, main, outer


def _secure_pieces(m, tech, strict=True):
    """(main piece, [secure pieces]): the secure room opens into tech storage and nowhere else (stock 6/6); a tech
    storage piece with doors elsewhere (to a checkpoint, an SMES room: f21c) is no secure room. strict=False: the
    small pieces (12 tiles or less) with a door into tech storage, whatever else they open on (the fix walls the rest)."""
    if not tech:
        return None, []
    main = max(tech, key=lambda af: len(af[1]))[1]
    out = []
    for a, F in tech:
        if F is main:
            continue
        locks = [q for d, p, q in doors_of(m, F) if airlock(m.get(*d))]
        if strict and locks and all(q in main for q in locks):
            out.append(F)
        elif not strict and len(F) <= 12 and any(q in main for q in locks):
            out.append(F)
    return main, out


def _store(m, p, D):
    """The piece holding p is a store, not a way: the SMES bank (2+ SMES), engineering storage, the gravity
    generator's rooms, the CE's office, tech storage."""
    t = m.get(*p)
    if t is None:
        return False
    if t.apath.startswith(("/area/engine/storage", GRAV, CE, TECH, "/area/engine/engine_smes")):
        return True
    return _smes_bank(m, p, D)


def _smes_bank(m, p, D):
    """The piece holding p is a room of 2+ SMES (the department's bank)."""
    F = next((Fp for a, Fp in D.eng if p in Fp), None)
    return F is not None and sum(1 for q in F if has(m.get(*q), "/obj/machinery/power/smes")) >= 2


STORES = (TECH, GRAV, CE, "/area/engine/storage", "/area/engine/engine_smes", "/area/engine/supermatter")


def _private_doors(m, F, locks):
    """Doors of a room leading to rooms reached only through it (the CE's quarters, a gravity generator behind the
    office): walling one off would cut the room beyond off from the halls."""
    out = []
    before = reached_from_halls(m)
    for d, q in locks:
        save = m.get(*d).copy()
        _make_wall(m, d, "/turf/closed/wall")
        after = reached_from_halls(m)
        m.set(d[0], d[1], save)
        if q in before and q not in after:
            out.append(d)
    return out


def _front_ok(m, q):
    """Where a post may open: a hall or the department's own floor (foyer, corridor, main room: Delta's post opens on
    its engineering floor), never a store, an office or the engine."""
    t = m.get(*q)
    return t is not None and floor(t) and (hall(t) or (group(t.apath) == "engineering" and not t.apath.startswith(STORES)
                                                        and not t.apath.startswith(CHECKPOINT)))


def _glass_of(m, F, pred):
    out = []
    for p in F:
        for dx, dy in N4:
            w = (p[0] + dx, p[1] + dy)
            tw = m.get(*w)
            if tw is None or tw.tpath.startswith("/turf/closed") or not any(o.path.startswith(WINDOWISH) for o in tw.objs):
                continue
            for k in (1, 2):
                tq = m.get(w[0] + dx * k, w[1] + dy * k)
                if floor(tq):
                    if pred(tq) and w not in out:
                        out.append(w)
                    break
    return out


def _corridor_windows(m, F, ez):
    """[(window tile, corridor tile, engine tile)] the corridor sees the engine through, middle of the corridor first."""
    out = []
    for p in F:
        for dx, dy in N4:
            w = (p[0] + dx, p[1] + dy)
            tw = m.get(*w)
            if tw is None or not any(o.path.startswith(WINDOWISH) for o in tw.objs) or is_door(tw):
                continue
            q = (w[0] + dx, w[1] + dy)
            if q in ez and walkable(m.get(*q)):
                inner = sum(1 for ex, ey in N4 if (p[0] + ex, p[1] + ey) in F)
                out.append((-inner, w, p, q))
    out.sort()
    return [(w, p, q) for _, w, p, q in out]


def orphan_terminals(m):
    out = []
    for (x, y, z), t in m.tiles.items():
        if z != 1:
            continue
        for o in t.objs:
            if o.path == "/obj/machinery/power/terminal":
                v = DIRV.get(o.num("dir", 2), (0, -1))
                if not has(m.get(x + v[0], y + v[1]), ("/obj/machinery/power/smes", "/obj/machinery/power/apc")):
                    out.append((x, y, "a power terminal with no SMES on its side (stock 6/7: none)"))
    return out


def _atmos_doors(m):
    out = []
    for (x, y, z), t in m.tiles.items():
        a = airlock(t) if z == 1 else None
        if a is None:
            continue
        if "/external" in a.path or "/maintenance" in a.path:
            continue
        for dx, dy in ((1, 0), (0, 1)):
            t1, t2 = m.get(x - dx, y - dy), m.get(x + dx, y + dy)
            if not (floor(t1) and floor(t2)):
                continue
            g1, g2 = group(t1.apath), group(t2.apath)
            if {g1, g2} == {"engineering", "atmos"}:
                if a.path.endswith("/critical") or "Atmos" not in (a.get("name") or "") or not a.path.startswith(
                        "/obj/machinery/door/airlock/atmos"):
                    out.append(((x, y), "%s %s between engineering and Atmospherics (stock: an atmos airlock named "
                                        "Atmospherics, access 24, 6/6)" % (a.path.replace("/obj/machinery/door/", ""), a.get("name"))))
    return out


def _atmos_main(D):
    return max(D.atmos, key=lambda af: len(af[1]), default=None)


def _atmos_check(m, D):
    out = []
    if not D.atmos:
        return out
    for a, F in D.atmos:
        for d, p, q in doors_of(m, F):
            al = airlock(m.get(*d))
            if al and hall(m.get(*q)) and not access(al):
                out.append((d[0], d[1], "atmos: a hall airlock anyone opens (stock 7/7: access 24)"))
    main = _atmos_main(D)
    desk = any(has(m.get(*d), "/obj/machinery/door/window") and has(m.get(*d), "/obj/structure/table") and hall(m.get(*q))
               for a, F in D.atmos for d, p, q in doors_of(m, F))
    if not desk:
        out.append((min(main[1])[0], min(main[1])[1], "atmos: no front desk onto a hall (stock 7/7)"))
    alltiles = set().union(*[F for a, F in D.atmos])
    for pre, n, _ in ATMOS_KIT:
        have = sum(1 for p in alltiles for o in m.get(*p).objs if o.path.startswith(pre))
        if have < n:
            out.append((min(main[1])[0], min(main[1])[1], "atmos: %d of %s (stock 7/7: %d+)" % (have, pre.split("/")[-1], n)))
    for pre, n, kind, _ in ATMOS_MOUNTS:
        have = sum(1 for p in alltiles for o in m.get(*p).objs if o.path.startswith(pre))
        if have < n:
            out.append((min(main[1])[0], min(main[1])[1], "atmos: %d of %s (stock 7/7: %d+)" % (have, pre.split("/")[-1], n)))
    cans = sum(1 for p in alltiles for o in m.get(*p).objs if o.path.startswith("/obj/machinery/portable_atmospherics/canister")
               and not has(m.get(*p), "/obj/machinery/atmospherics/components/unary/portables_connector"))
    if cans < SPARE_CANS_MIN:
        out.append((min(main[1])[0], min(main[1])[1], "atmos: %d spare canisters (stock 8-12 in the monitoring room)" % cans))
    return out


def _secure_storage(m, D):
    for a, F in D.eng:
        if any(has(m.get(*p), ("/obj/machinery/field/generator", "/obj/machinery/shieldgen")) for p in F):
            return True
    return False


SECURE_KIT = [("/obj/machinery/power/emitter", 4), ("/obj/machinery/field/generator", 5), ("/obj/machinery/shieldgen", 4),
              ("/obj/machinery/power/port_gen/pacman", 1)]
SECURE_OPTIONAL = ("/obj/structure/table", "/obj/structure/rack", "/obj/structure/chair", "/obj/structure/closet",
                   "/obj/machinery/vending", "/obj/item/twohanded/required/kirbyplants", "/obj/structure/reagent_dispensers",
                   "/obj/machinery/suit_storage_unit", "/obj/structure/filingcabinet", "/obj/machinery/cell_charger")


def _fix_secure(m, D, note):
    """Secure storage (stock 7/7): engineering's main room's own back room (gen/learn/floorplan.py SECURE_BACK, a
    piece of /area/engine/engineering of 12-40 tiles with one airlock into the main room) holds the emitters, field
    and shield generators and a portable generator behind blast doors, opened by a button (access 11) on the main
    room's side; what the room was furnished with goes."""
    import fixtures as FX
    import settle as SL
    if _secure_storage(m, D):
        return 0
    main = max((F for a, F in D.eng if a == "/area/engine/engineering" and not F & D.ez), key=len, default=None)
    if not main:
        return 0
    cands = []
    for a, F in D.eng:
        if a != "/area/engine/engineering" or F is main or F & D.ez or not 12 <= len(F) <= 40:
            continue
        ds = doors_of(m, F)
        locks = [(d, p, q) for d, p, q in ds if airlock(m.get(*d))]
        into = [l_ for l_ in locks if l_[2] in main]
        # one way in from the main room; a second door doorcount gave it is walled up (f27: 27 tiles, 2 doors)
        if not into or len(ds) > 2 or len(locks) != len(ds):
            continue
        cands.append((abs(len(F) - 24), F, into[0], [l_ for l_ in locks if l_ is not into[0]]))
    if not cands:
        return 0
    _, F, (d, p, q), extra = min(cands, key=lambda c: c[0])
    for d2, p2, q2 in extra:
        m.set(d2[0], d2[1], dmm.Tile([], dmm.Atom("/turf/closed/wall"), dmm.Atom("/area/engine/engineering")))
    # the room cleared of what synth gave it: the working pieces (a tank dispenser, suit storage, lockers, vendors)
    # move out to the main room, spare furniture goes. Left inside, engineering's one plasma tank dispenser stood
    # behind the closed blast door and the supermatter was never started (Bot Shift f30: setup_supermatter failed
    # on "the tank dispenser" 12 times); a piece that can't move out and isn't spare leaves the room as it was
    stay = []
    for c in sorted(F):
        t = m.get(*c)
        for o in list(t.objs):
            if CO.mounted(o) or not FN.is_dense(o) or o.path.startswith(SECURE_OPTIONAL[:3]):
                continue
            if o.path.startswith(("/obj/machinery/atmospherics", "/obj/machinery/power/terminal", "/obj/machinery/power/smes")):
                return 0            # a wired or piped piece: not the room for it
            t.objs = [x for x in t.objs if x is not o]
            if _place(m, main, q, [o]) is None:
                if o.path.startswith(SECURE_OPTIONAL):
                    continue        # spare: it goes
                t.objs.append(o)
                stay.append(o)
    if stay:
        return 0
    for c in F:
        t = m.get(*c)
        t.objs = [o for o in t.objs if not o.path.startswith(SECURE_OPTIONAL) and not (o.path.startswith("/obj/item")
                                                                                       and not CO.mounted(o))]
    # packed as the stock stores are (Meta, Box, Delta: dark floor, the machines in tight rows by kind from the back
    # wall, one aisle straight in from the blast door, hazard stripes at the door; the user 2026-11-26: "secure
    # storage doesn't look right" when they stood scattered along the walls)
    for c in F:
        m.get(*c).turf = dmm.Atom("/turf/open/floor/plasteel/dark")
    step = (p[0] - d[0], p[1] - d[1])                   # from the door into the room
    side = (step[1], step[0])
    aisle = set()
    a = p
    while a in F:
        aisle.add(a)
        a = (a[0] + step[0], a[1] + step[1])
    m.get(*p).objs.append(dmm.Atom("/obj/effect/turf_decal/stripes/line", [("dir", str({(0, 1): 2, (0, -1): 1, (1, 0): 8, (-1, 0): 4}[step]))]))
    # the back first: depth from the door, then across from the aisle outward
    order = sorted((c for c in F if c not in aisle and not (abs(c[0] - p[0]) + abs(c[1] - p[1]) == 1 and
                    (c[0] - p[0], c[1] - p[1]) in (side, (-side[0], -side[1])))),
                   key=lambda c: (-((c[0] - d[0]) * step[0] + (c[1] - d[1]) * step[1]),
                                  abs((c[0] - p[0]) * side[0] + (c[1] - p[1]) * side[1]), c))
    toward = {(0, 1): 2, (0, -1): 1, (1, 0): 8, (-1, 0): 4}[step]     # the emitters face the door
    queue = []
    for path, k in SECURE_KIT:
        queue += [path] * k
    placed = 0
    for c in order:
        if not queue:
            break
        t = m.get(*c)
        if any(FN.is_dense(o) for o in t.objs) or c in SL.RESERVED:
            continue
        path = queue.pop(0)
        t.objs.append(dmm.Atom(path, [("dir", str(toward))] if path.endswith("emitter") else []))
        placed += 1
    td = m.get(*d)
    td.objs = [o for o in td.objs if not o.path.startswith("/obj/machinery/door/airlock")] + [
        dmm.Atom("/obj/machinery/door/poddoor", [("id", '"engsecure"'), ("name", '"Secure Storage"')])]
    # the button on the main room's side, on a free wall face near the door
    faces = [f for f in FX._faces(m, main, {d}) if abs(f[0][0] - q[0]) + abs(f[0][1] - q[1]) <= 4]
    if faces:
        fp, fd = min(faces, key=lambda f: (abs(f[0][0] - q[0]) + abs(f[0][1] - q[1]), f[0]))
        from forge import kit as KT
        dd, px, py = KT.MOUNT["button"][fd]
        vs = [(k_, str(v_)) for k_, v_ in (("dir", dd), ("pixel_x", px), ("pixel_y", py)) if v_ is not None]
        m.get(*fp).objs.append(dmm.Atom("/obj/machinery/button/door", vs + [
            ("id", '"engsecure"'), ("name", '"Engineering Secure Storage"'), ("req_access_txt", '"11"')]))
    note("secure storage at %d,%d (%d tiles): blast doors, button, %d machines (stock 7/7)" % (d[0], d[1], len(F), placed))
    return 1 + placed


# ------------------------------------------------------------------------------------------------ fixing helpers
def _place(m, F, near_tile, atoms, avoid=()):
    """Put a dense piece (atoms[0], with the rest on its tile) on the free wall-side tile of piece F nearest near_tile
    that keeps the room's reach (gen/learn/settle._spot: off door fronts, beside reached floor, nothing boxed in).
    The gravity generator's runtime 3x3 counts as dense while it looks (gen/audit.py "big"); avoid: tiles not to use."""
    import settle as SL
    import placestudy as PS
    o = atoms[0]
    doors = {(p[0] + dx, p[1] + dy) for p in F for dx, dy in N4 if PS._door(m.get(p[0] + dx, p[1] + dy))}
    stubs = []
    for p in set(F) & (SL.RESERVED | set(avoid)):
        a = dmm.Atom("/obj/structure/rack")
        m.get(*p).objs.append(a)
        stubs.append((p, a))
    t = m.get(*near_tile)
    t.objs.append(o)
    try:
        q = SL._spot(m, F, doors, near_tile, o)
    finally:
        t.objs = [i for i in t.objs if i is not o]
        for p, a in stubs:
            m.get(*p).objs = [i for i in m.get(*p).objs if i is not a]
    if q is None:
        return None
    m.get(*q).objs.extend(atoms)
    return q


def _wall_side(m, q):
    """Sides (1,2,4,8) of q that are wall or window (not a door)."""
    return [SIDE[(dx, dy)] for dx, dy in N4 if CO.solid(m.get(q[0] + dx, q[1] + dy)) and not is_door(m.get(q[0] + dx, q[1] + dy))]


def _face_dir(m, q):
    """A computer or a shower against a wall faces away from it (stock: wall N -> 2, S -> 1, E -> 8, W -> 4)."""
    ws = _wall_side(m, q)
    for s in (2, 1, 8, 4):
        if s in ws:
            return OPP[s]
    return 2


def _hang(m, F, kind, path, extra, near_tile):
    """A wall piece on a free wall face of F nearest near_tile (gen/learn/fixtures._faces), offsets from forge/kit."""
    import fixtures as FX
    doors = {(p[0] + dx, p[1] + dy) for p in F for dx, dy in N4 if is_door(m.get(p[0] + dx, p[1] + dy))}
    faces = FX._faces(m, F, doors)
    if not faces:
        return None
    p, d = min(faces, key=lambda f: (abs(f[0][0] - near_tile[0]) + abs(f[0][1] - near_tile[1]), f))
    dd, px, py = KT.MOUNT[kind][d]
    vs = list(extra)
    if path.startswith("/obj/machinery/requests_console") or path.startswith("/obj/structure/fireaxecabinet") \
            or path.startswith("/obj/structure/extinguisher_cabinet"):
        dd = None
    if dd is not None:
        vs.append(("dir", str(dd)))
    if px is not None:
        vs.append(("pixel_x", str(px)))
    if py is not None:
        vs.append(("pixel_y", str(py)))
    m.get(*p).objs.append(dmm.Atom(path, vs))
    return p


def _wall_ok(m, w, hung):
    tw = m.get(*w)
    return tw is not None and tw.tpath.startswith("/turf/closed/wall") and all(o.path.startswith(UNDER) for o in tw.objs) \
        and w not in hung


def _hung(m):
    import desks as DK
    return DK._hung(m)


def _make_door(m, w, inside, path, name, req=None, one=None):
    t = m.get(*w)
    keep = [o for o in t.objs if o.path.startswith(UNDER)]
    vs = [("name", '"%s"' % name)]
    if req:
        vs.append(("req_access_txt", '"%s"' % req))
    if one:
        vs.append(("req_one_access_txt", '"%s"' % one))
    t.objs = keep + [dmm.Atom("/obj/machinery/door/firedoor"), dmm.Atom(path, vs)]
    t.turf = dmm.Atom("/turf/open/floor/plasteel")
    t.area = m.get(*inside).area.copy()


def _make_wall(m, d, like):
    t = m.get(*d)
    keep = [o for o in t.objs if o.path.startswith(UNDER)]
    t.objs = keep
    t.turf = dmm.Atom(like or "/turf/closed/wall")


def _make_window(m, d, shutter_id=None):
    t = m.get(*d)
    keep = [o for o in t.objs if o.path.startswith(UNDER)]
    t.objs = keep + [dmm.Atom("/obj/effect/spawner/structure/window/reinforced")]
    if shutter_id:
        t.objs.append(dmm.Atom("/obj/machinery/door/poddoor/preopen", [("id", '"%s"' % shutter_id),
                                                                       ("name", '"privacy shutter"')]))
    t.turf = dmm.Atom("/turf/open/floor/plating")


def _door_spot(m, F, want, hung, avoid=()):
    """_wall_door_spot, else one with a piece on its inside tile moved to a wall spot of the room that keeps it joined
    (tech storage's hall wall was lined with tables, f21c). -> (wall, inside, outside) or None; the move is made."""
    cands = _wall_door_spot(m, F, want, hung, avoid)
    if cands:
        cx = sum(p[0] for p in F) / float(len(F))
        cy = sum(p[1] for p in F) / float(len(F))
        return min(cands, key=lambda c: (abs(c[0][0] - cx) + abs(c[0][1] - cy), c[0]))
    cands = _wall_door_spot(m, F, want, hung, avoid, blocked=True)
    cx = sum(p[0] for p in F) / float(len(F))
    cy = sum(p[1] for p in F) / float(len(F))
    for w, p, q in sorted(cands, key=lambda c: (abs(c[0][0] - cx) + abs(c[0][1] - cy), c[0])):
        if not _movable(m, p):
            continue
        t = m.get(*p)
        carry = [o for o in t.objs if FN.is_dense(o)]
        if any(o.path.startswith(("/obj/structure/table", "/obj/structure/rack")) for o in carry):
            carry += [o for o in t.objs if o.path.startswith("/obj/item") and not CO.mounted(o)]
        t.objs = [o for o in t.objs if not any(o is c_ for c_ in carry)]
        dest = _place(m, F, p, carry, avoid={p})
        if dest is not None:
            return w, p, q
        if all(o.path.startswith(("/obj/structure/table", "/obj/structure/rack", "/obj/item")) for o in carry):
            other = sorted((x for x in F if x != p and has(m.get(*x), ("/obj/structure/table", "/obj/structure/rack"))),
                           key=lambda x: abs(x[0] - p[0]) + abs(x[1] - p[1]))
            items = [o for o in carry if o.path.startswith("/obj/item")]
            if other or not items:
                if items:
                    m.get(*other[0]).objs.extend(items)
                return w, p, q
        t.objs.extend(carry)
    return None


def _wall_door_spot(m, F, want, hung, avoid=(), blocked=False):
    """[(wall tile, inside tile, outside tile)] in F's walls where a new airlock can go: a plain wall between a free
    tile of F and a free tile want() accepts, walls either side along it, no door within a tile, nothing hung on it.
    blocked: the inside tile holds one dense piece (to be moved)."""
    out = []
    for p in sorted(F):
        if dense(m.get(*p)) != blocked or has(m.get(*p), "/obj/machinery/gravity_generator"):
            continue
        for dx, dy in N4:
            w = (p[0] + dx, p[1] + dy)
            q = (w[0] + dx, w[1] + dy)
            if w in avoid or not _wall_ok(m, w, hung):
                continue
            tq = m.get(*q)
            if not floor(tq) or dense(tq) or not want(tq):
                continue
            along = (dy, dx)
            if not all(CO.solid(m.get(w[0] + s * along[0], w[1] + s * along[1])) and not is_door(
                    m.get(w[0] + s * along[0], w[1] + s * along[1])) for s in (1, -1)):
                continue
            if any(is_door(m.get(w[0] + ex, w[1] + ey)) for ex in (-2, -1, 0, 1, 2) for ey in (-2, -1, 0, 1, 2)
                   if abs(ex) + abs(ey) <= 2):
                continue
            # neither side's step through the new door is a door front of something else / a mount's tile is fine
            out.append((w, p, q))
    return out


def _reach_ok(m, before, tiles):
    """Every tile of `tiles` reached from the halls before is still reached."""
    after = reached_from_halls(m)
    return all(p in after for p in tiles if p in before)


# ------------------------------------------------------------------------------------------------ fixes
def fix(m, seed=1, log=print):
    import settle as SL
    r = random.Random("fn_engineering|%s" % seed)
    SL.reserve(m)
    n = 0
    notes = []

    def note(s):
        notes.append(s)

    D = Dept(m)
    if not D.eng:
        log("fn_engineering: no engineering")
        return 0
    n += _fix_corridor(m, D, note)
    n += _fix_engine_doors(m, Dept(m), note)
    D = Dept(m)
    n += _fix_ce(m, D, note)
    n += _fix_checkpoint(m, Dept(m), note)
    n += _fix_tech(m, Dept(m), note)
    n += _fix_foyer(m, Dept(m), note)
    n += _fix_atmos_door(m, note)
    n += _fix_atmos(m, Dept(m), r, note)
    n += _fix_terminals(m, note)
    n += _fix_way_in(m, Dept(m), note)
    n += _fix_grav(m, Dept(m), note)
    n += _fix_secure(m, Dept(m), note)
    SL.RESERVED.clear()
    for s in notes:
        log("fn_engineering: " + s)
    log("fn_engineering: %d changes" % n)
    return n


def _fix_corridor(m, D, note):
    n = 0
    for a, F in D.piece(CORR):
        if a != CORR or any(q in D.ez for d, p, q in doors_of(m, F) if airlock(m.get(*d))):
            continue
        for w, p, q in _corridor_windows(m, F, D.ez):
            along = (w[1] - p[1], w[0] - p[0])
            if not all(CO.solid(m.get(w[0] + s * along[0], w[1] + s * along[1])) for s in (1, -1)):
                continue
            if dense(m.get(*p)) or dense(m.get(*q)):
                continue
            _make_door(m, w, p, "/obj/machinery/door/airlock/engineering/glass", "Engine Room", req="10")
            note("corridor %s: the window onto the engine is the Engine Room airlock now" % (w,))
            n += 1
            break
    return n


def _fix_engine_doors(m, D, note):
    """Airlocks into the engine: access 10 where they had none; the SMES room's own way in walled up when another
    way in stays (stock SMES rooms are dead ends; ours was the shortest way to the crystal, past the batteries)."""
    n = 0
    for d, p, q, a in D.entrances:
        al = airlock(m.get(*d))
        if not access(al):
            set_access(al, req="10")
            note("engine_door %s: %s takes access 10" % (d, al.get("name")))
            n += 1
    # every store's door into the engine, while a way in from the corridor or a main room stays
    for d, p, q, a in sorted(Dept(m).entrances):
        D2 = Dept(m)
        if not any(e[0] == d for e in D2.entrances) or not _store(m, p, D2):
            continue
        if not any(not _store(m, e[1], D2) for e in D2.entrances):
            break
        F = next(Fp for ap, Fp in D2.eng if p in Fp)
        if sum(1 for d2, p2, q2 in doors_of(m, F) if airlock(m.get(*d2))) < 2:
            continue
        before = reached_from_halls(m)
        save = m.get(*d).copy()
        _make_wall(m, d, "/turf/closed/wall/r_wall")
        D3 = Dept(m)
        # and the engine is still walked into from the halls (gen/audit.py _reach_all: with the engine's side rooms
        # counted as ways in, the engine's one door was walled and 317 tiles of engine room sealed off, f36)
        import audit as AU_
        import doordb as DD_
        halls_ = [(x_, y_) for (x_, y_, z_), t_ in m.tiles.items() if z_ == 1 and t_.apath.startswith("/area/hallway")
                  and DD_._walk(t_)]
        if _reach_ok(m, before, list(F) + [q]) and D3.way_in() and q in AU_._reach_all(m, halls_):
            note("store %s: the %s's door into the engine walled up (the way in is %s's now)" % (
                d, a.split("/")[-1], D3.main_entrance()[3] if D3.main_entrance() else "?"))
            n += 1
        else:
            m.set(d[0], d[1], save)
    return n


def _fix_ce(m, D, note):
    n = 0
    hung = _hung(m)
    for a, F in D.piece(CE):
        locks = [(d, p, q) for d, p, q in doors_of(m, F) if airlock(m.get(*d))]
        sid = "ceprivacy"
        used = {o.get("id") for t in m.tiles.values() for o in t.objs if o.get("id")}
        if '"%s"' % sid in used and not any(has(m.get(*w), "/obj/machinery/door/poddoor") for w in
                                              _glass_of(m, F, lambda t: True)):
            sid = "ceprivacy_eng"
        # an airlock into the office that the CE's access doesn't guard: glass (a view), or the CE's lock
        for d, p, q in locks:
            al = airlock(m.get(*d))
            if "56" in access(al):
                continue
            if len(locks) <= 1:
                set_access(al, req="56")
                set_var(al, "name", '"Chief Engineer\'s Office"')
                note("ce_office %s: its door takes the CE's access" % (d,))
                n += 1
                continue
            # the office reached from the CE's own door first (its furniture had cut that door off: the office was
            # entered through the shared storage, f22)
            n += _unbox(m, F, {d}, note, "ce_office")
            if not _all_reached(m, F, {d}):
                set_access(al, req="56")
                set_var(al, "name", '"Chief Engineer\'s Office"')
                note("ce_office %s: its other door takes the CE's access" % (d,))
                n += 1
                continue
            before = reached_from_halls(m)
            keep_tiles = [q]
            save = m.get(*d).copy()
            _make_window(m, d, sid)
            if _reach_ok(m, before, keep_tiles + [p]):
                note("ce_office %s: the %s door (access %s) into the CE's office is a shuttered window now" % (
                    d, al.get("name"), sorted(access(al))))
                n += 1
                locks = [x for x in locks if x[0] != d]
                continue
            m.set(d[0], d[1], save)
            set_access(al, req="56")
            set_var(al, "name", '"Chief Engineer\'s Office"')
            note("ce_office %s: its other door takes the CE's access" % (d,))
            n += 1
        # more than one airlock (all the CE's): the one onto the department's floor stays, the others go (f21c: a
        # second door from the office into the gravity generator's room)
        locks = [(d, p, q) for d, p, q in doors_of(m, F) if airlock(m.get(*d))]
        if len(locks) > 1:
            floorish = lambda q: m.get(*q) is not None and (m.get(*q).apath in (CORR, BREAK, "/area/engine/engineering")
                                                           or hall(m.get(*q)))
            keep = sorted(locks, key=lambda x: (not floorish(x[2]), x[0]))[0]
            for d, p, q in locks:
                if d == keep[0]:
                    continue
                n += _unbox(m, F, {d}, note, "ce_office")
                if not _all_reached(m, F, {d}):
                    continue
                before = reached_from_halls(m)
                save = m.get(*d).copy()
                to_dept = group(getattr(m.get(*q), "apath", "")) == "engineering"
                if to_dept:
                    _make_window(m, d, sid)
                else:
                    _make_wall(m, d, "/turf/closed/wall")
                if _reach_ok(m, before, [q, p]):
                    note("ce_office %s: the office's second door (into %s) is %s now" % (
                        d, m.get(*q).apath, "a shuttered window" if to_dept else "wall"))
                    n += 1
                else:
                    m.set(d[0], d[1], save)
        glass = _glass_of(m, F, lambda t: group(t.apath) == "engineering" and t.apath != CE)
        if not glass:
            # a window onto the department's floor (break room, corridor, main room): two tiles if they fit
            cands = _wall_door_spot(m, F, lambda t: group(t.apath) == "engineering" and t.apath != CE, hung)
            pref = {BREAK: 0, CORR: 1, "/area/engine/engineering": 2}
            cands.sort(key=lambda c: (pref.get(m.get(*c[2]).apath, 3), c[0]))
            made = []
            for w, p, q in cands:
                if len(made) >= 2:
                    break
                if made and not any(abs(w[0] - x[0]) + abs(w[1] - x[1]) == 1 for x in made):
                    continue
                if made and m.get(*q).apath != m.get(*made_q).apath:
                    continue
                _make_window(m, w, sid)
                made.append(w)
                made_q = q
            if made:
                note("ce_office: %d window(s) onto %s with privacy shutters" % (len(made), m.get(*made_q).apath))
                n += len(made)
            glass = made
        for w in glass:
            if not has(m.get(*w), "/obj/machinery/door/poddoor"):
                m.get(*w).objs.append(dmm.Atom("/obj/machinery/door/poddoor/preopen", [("id", '"%s"' % sid),
                                                                                       ("name", '"privacy shutter"')]))
                n += 1
        ids = {o.get("id", "").strip('"') for w in glass for o in m.get(*w).objs if o.path.startswith("/obj/machinery/door/poddoor")}
        for i in sorted(ids):
            if any(o.path.startswith("/obj/machinery/button/door") and o.get("id", "").strip('"') == i
                   for p in F for o in m.get(*p).objs):
                continue
            ctr = (sum(p[0] for p in F) // len(F), sum(p[1] for p in F) // len(F))
            if _hang(m, F, "button", "/obj/machinery/button/door", [("id", '"%s"' % i), ("name", '"Privacy Shutters Control"')], ctr):
                note("ce_office: the privacy shutters' button")
                n += 1
    return n


def _fix_checkpoint(m, D, note):
    n = 0
    hung = _hung(m)
    for a, F in sorted(D.piece(CHECKPOINT), key=lambda af: -len(af[1]))[:1]:       # the post (cells are pieces too)
        locks = [(d, p, q) for d, p, q in doors_of(m, F) if airlock(m.get(*d))]
        if any(_front_ok(m, q) for d, p, q in locks):
            continue
        got = _door_spot(m, F, hall, hung) or _door_spot(m, F, lambda t: t.apath in (BREAK, CORR), hung)
        if not got:
            continue
        w, p, q = got
        _make_door(m, w, p, "/obj/machinery/door/airlock/security/glass", "Engineering Security Post", req="63")
        note("checkpoint %s: an airlock onto %s" % (w, m.get(*q).apath))
        n += 1
        # the old way in through a store goes (the store keeps its own doors)
        for d, p2, q2 in locks:
            tq = m.get(*q2)
            if tq is None or _front_ok(m, q2):
                continue
            before = reached_from_halls(m)
            save = m.get(*d).copy()
            _make_wall(m, d, "/turf/closed/wall")
            if _reach_ok(m, before, [q2, p2]):
                note("checkpoint %s: its door into %s walled up" % (d, tq.apath))
                n += 1
            else:
                m.set(d[0], d[1], save)
    return n


def _fix_tech(m, D, note):
    n = 0
    tech = D.piece(TECH)
    if not tech:
        return 0
    hung = _hung(m)
    main = max(tech, key=lambda af: len(af[1]))
    F = main[1]
    locks = [(d, p, q) for d, p, q in doors_of(m, F) if airlock(m.get(*d))]
    if not any(hall(m.get(*q)) for d, p, q in locks):
        got = _door_spot(m, F, hall, hung)
        if got:
            w, p, q = got
            _make_door(m, w, p, "/obj/machinery/door/airlock/engineering", "Tech Storage", req="23")
            note("tech %s: tech storage's airlock onto the hall" % (w,))
            n += 1
    secure = _secure_pieces(m, tech, strict=False)[1]
    sec_tiles = set().union(*secure) if secure else set()
    for d, p, q in doors_of(m, F):
        al = airlock(m.get(*d))
        if al is None or q in sec_tiles or getattr(m.get(*q), "apath", "") not in (CORR, "/area/engine/engineering", BREAK):
            continue
        if (al.get("name") or "").strip('"') != "Tech Storage" or access(al) != {"23"}:
            set_var(al, "name", '"Tech Storage"')
            set_access(al, req="23")
            if "/highsecurity" in al.path:          # the store's own door is an engineering one (7/7)
                t_ = m.get(*d)
                na = dmm.Atom("/obj/machinery/door/airlock/engineering", al.vars)
                t_.objs = [o if o is not al else na for o in t_.objs]
            note("tech %s: the inner door is Tech Storage, access 23" % (d,))
            n += 1
    # the store reached from its own doors, not through the secure room (racks had cut off its far side, f22)
    sec_doors = {d for Fs in secure for d, p, q in doors_of(m, Fs)}
    n += _unbox(m, F, sec_doors, note, "tech storage")
    # the secure room: one door, no suits, its three racks of boards
    for Fs in secure:
        sl = [(d, p, q) for d, p, q in doors_of(m, Fs) if airlock(m.get(*d))]
        if len(sl) > 1:
            keep = min(sl, key=lambda x: (x[2] not in F, m.get(*x[0]).apath != m.get(*x[1]).apath, x[0]))
            for d, p, q in sl:
                if d == keep[0]:
                    continue
                before = reached_from_halls(m)
                save = m.get(*d).copy()
                _make_wall(m, d, "/turf/closed/wall/r_wall")
                if _reach_ok(m, before, list(Fs) + [q]):
                    note("tech %s: the secure room's second door walled up" % (d,))
                    n += 1
                else:
                    m.set(d[0], d[1], save)
        for p in sorted(Fs):
            t = m.get(*p)
            for o in list(t.objs):
                if o.path.startswith("/obj/machinery/suit_storage_unit"):
                    t.objs.remove(o)
                    dest = None
                    # engineering's own suits are in its storage (stock 2-4); this one goes there only if none are
                    if not any(has(m.get(*q), "/obj/machinery/suit_storage_unit/engine") for a2, F2 in D.eng for q in F2):
                        for a2, F2 in sorted(D.piece("/area/engine/storage"), key=lambda af: -len(af[1])):
                            dest = _place(m, F2, min(F2), [o])
                            if dest:
                                break
                    note("tech %s: the suit storage unit out of secure tech storage%s" % (
                        p, (" to %s" % (dest,)) if dest else " (engineering storage has its own)"))
                    n += 1
    n += _boards(m, F, TECH_BOARDS, note, "tech storage")
    for Fs in _secure_pieces(m, Dept(m).piece(TECH))[1]:
        n += _boards(m, Fs, SECURE_BOARDS, note, "secure tech storage")
    return n


def _movable(m, p):
    """A dense piece the pass may move: not wired, piped or linked (settle.FIXED: power, atmospherics, cloning...),
    not a disposal bin on its trunk."""
    import settle as SL
    t = m.get(*p)
    return not any(o.path.startswith(SL.FIXED + ("/obj/machinery/disposal",)) for o in t.objs if FN.is_dense(o))


def _unbox(m, F, skip_doors, note, what):
    """Join a room's free floor cut off from its doors (other than skip_doors) by its own furniture: a dense piece
    between the reached and the cut-off floor moves to a wall spot of the room that keeps it joined (a bare table or
    rack with nowhere to go is taken out)."""
    n = 0

    def state():
        doors = {d for d, p, q in doors_of(m, F) if airlock(m.get(*d)) and d not in skip_doors}
        fronts = {p for d, p, q in doors_of(m, F) if d in doors}
        free = {p for p in F if not dense(m.get(*p))}
        seen = bfs(m, [p for p in fronts if p in free], keep=free)
        seen = {p for p in seen if p in free}
        return seen, free - seen
    tried = set()
    for _ in range(8):
        seen, cut = state()
        if not cut or not seen:
            return n
        cands = [c for c in sorted(F) if dense(m.get(*c)) and c not in tried and _movable(m, c)
                 and any((c[0] + dx, c[1] + dy) in seen for dx, dy in N4)
                 and any((c[0] + dx, c[1] + dy) in cut for dx, dy in N4)]
        if not cands:
            return n
        best = cands[0]
        tried.add(best)
        t = m.get(*best)
        carry = [o for o in t.objs if FN.is_dense(o)]
        if any(o.path.startswith(("/obj/structure/table", "/obj/structure/rack")) for o in carry):
            carry += [o for o in t.objs if o.path.startswith("/obj/item") and not CO.mounted(o)]
        t.objs = [o for o in t.objs if not any(o is c_ for c_ in carry)]
        # the spot must keep the floor it opened joined: never the tile it left
        ref = min(seen, key=lambda p: abs(p[0] - best[0]) + abs(p[1] - best[1]))
        dest = _place(m, F, ref, carry, avoid={best})
        if dest is not None and len(state()[1]) >= len(cut):
            m.get(*dest).objs = [o for o in m.get(*dest).objs if not any(o is c_ for c_ in carry)]
            dest = None
        if dest is None:
            if all(o.path.startswith(("/obj/structure/table", "/obj/structure/rack", "/obj/item")) for o in carry)                     and len(state()[1]) < len(cut):
                note("%s %s: a %s cutting the room in two taken out" % (what, best, carry[0].path.split("/")[-1]))
                n += 1
                continue
            t.objs.extend(carry)
            continue
        if carry[0].path.startswith(("/obj/machinery/computer", "/obj/machinery/modular_computer")):
            # its back to a wall: the facing it had if the new spot allows, else away from the wall there
            d0 = carry[0].num("dir", 2)
            if OPP[d0] not in _wall_side(m, dest):
                carry[0].vars = [(k, v) for k, v in carry[0].vars if k != "dir"]
                d_ = _face_dir(m, dest)
                if d_ != 2:
                    carry[0].vars.append(("dir", str(d_)))
        note("%s %s: the %s cutting the room in two moved to %s" % (what, best, carry[0].path.split("/")[-1], dest))
        n += 1
    return n


def _all_reached(m, F, skip_doors):
    """Every free tile of F is reached from its airlocks other than skip_doors."""
    fronts = {p for d, p, q in doors_of(m, F) if airlock(m.get(*d)) and d not in skip_doors}
    free = {p for p in F if not dense(m.get(*p))}
    seen = bfs(m, [p for p in fronts if p in free], keep=free)
    return not (free - set(seen))


def _boards(m, F, want, note, what):
    have = {o.path[len(BOARDS):] for p in F for o in m.get(*p).objs if o.path.startswith(BOARDS)}
    miss = [b for b in want if b not in have]
    if not miss:
        return 0
    n = 0
    racks = sorted([p for p in F if has(m.get(*p), "/obj/structure/rack")],
                   key=lambda p: (has(m.get(*p), BOARDS), sum(1 for o in m.get(*p).objs if o.path.startswith("/obj/item")), p))
    door = next((d for d, p, q in doors_of(m, F) if airlock(m.get(*d))), min(F))
    for b in miss:
        free = [p for p in racks if not has(m.get(*p), BOARDS)]
        if not free:
            q = _place(m, F, door, [dmm.Atom("/obj/structure/rack")])
            if q:
                racks.append(q)
                free = [q]
        spot = free[0] if free else (racks[0] if racks else None)
        if spot is None:
            continue
        m.get(*spot).objs.append(dmm.Atom(BOARDS + b))
        n += 1
    note("tech: %s given its circuit board spawners %s" % (what, ", ".join(miss)))
    return n


def _fix_foyer(m, D, note):
    n = 0
    hung = _hung(m)
    br = D.piece(BREAK)
    if any(hall(m.get(*q)) for a, F in br for d, p, q in doors_of(m, F) if airlock(m.get(*d))):
        return 0
    for a, F in sorted(br, key=lambda af: -len(af[1]))[:1]:
        got = _door_spot(m, F, hall, hung)
        if not got:
            continue
        w, p, q = got
        _make_door(m, w, p, "/obj/machinery/door/airlock/engineering/glass", "Engineering Foyer", one="32;19")
        note("foyer %s: the break room's airlock onto the hall (32;19)" % (w,))
        n += 1
    return n


def _fix_atmos_door(m, note):
    n = 0
    for d, why in _atmos_doors(m):
        t = m.get(*d)
        al = airlock(t)
        new = "/obj/machinery/door/airlock/atmos/glass" if "/glass" in al.path else "/obj/machinery/door/airlock/atmos"
        acc = access(al)
        na = dmm.Atom(new, [(k, v) for k, v in al.vars if k != "name"] + [("name", '"Atmospherics Access"')])
        if "24" not in acc:
            set_access(na, one=";".join(sorted(acc | {"24"})))
        t.objs = [o if o is not al else na for o in t.objs]
        for dx, dy in N4:
            tn = m.get(d[0] + dx, d[1] + dy)
            if tn is not None and group(tn.apath) == "atmos" and floor(tn):
                t.area = tn.area.copy()         # an atmos door stands in Atmospherics' area (audit odd_door)
                break
        note("atmos_door %s: %s is the Atmospherics Access airlock" % (d, al.path.replace("/obj/machinery/door/", "")))
        n += 1
    return n


def _fix_atmos(m, D, r, note):
    import desks as DK
    n = 0
    if not D.atmos:
        return 0
    main = _atmos_main(D)
    F = main[1]
    for a, Fa in D.atmos:
        for d, p, q in doors_of(m, Fa):
            al = airlock(m.get(*d))
            if al and hall(m.get(*q)) and not access(al):
                set_access(al, req="24")
                note("atmos %s: the hall airlock takes access 24" % (d,))
                n += 1
    # the front desk onto the hall (gen/learn/desks.py's counter, one tile)
    desk = any(has(m.get(*d), "/obj/machinery/door/window") and has(m.get(*d), "/obj/structure/table") and hall(m.get(*q))
               for a, Fa in D.atmos for d, p, q in doors_of(m, Fa))
    if not desk:
        doors = {(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and t.has("/obj/machinery/door")}
        hung = DK._hung(m)
        sp = DK.spots(m, F, main[0], DK.HALL, hung, doors)
        sp = [s for s in sp if not s[3] and s[0] not in hung]
        if sp:
            fronts = [p for d, p, q in doors_of(m, F) if airlock(m.get(*d)) and hall(m.get(*q))]
            ref = fronts[0] if fronts else min(F)
            w, step, along, block = min(sp, key=lambda s: (abs(s[0][0] - ref[0]) + abs(s[0][1] - ref[1]), s[0]))
            t = m.get(*w)
            keep = [o for o in t.objs if o.path.startswith(UNDER)]
            t.objs = keep + DK.counter_objs("desk", step, "Atmospherics Desk", "24", r)
            t.turf = dmm.Atom("/turf/open/floor/plasteel")
            t.area = dmm.Atom(main[0])
            note("atmos %s: the Atmospherics Desk onto the hall" % (w,))
            n += 1
    # kit by the front: lockers, suit, wardrobe, pipe dispenser, pumps, scrubbers, tanks, the alert console
    fronts = [p for d, p, q in doors_of(m, F) if airlock(m.get(*d)) and (hall(m.get(*q)) or group(
        getattr(m.get(*q), "apath", "")) == "engineering")]
    ref = fronts[0] if fronts else min(F)
    alltiles = set().union(*[Fa for a, Fa in D.atmos])
    added = []
    for pre, want, atoms in ATMOS_KIT:
        if not atoms:
            continue
        have = sum(1 for p in alltiles for o in m.get(*p).objs if o.path.startswith(pre))
        for _ in range(max(0, want - have)):
            objs = [dmm.Atom(x) for x in atoms]
            q = _place(m, F, ref, objs)
            if q is None:
                break
            if atoms[0].startswith("/obj/machinery/computer"):
                d_ = _face_dir(m, q)
                if d_ != 2:
                    objs[0].vars.append(("dir", str(d_)))
            added.append(atoms[0].split("/")[-1])
            n += 1
    cans = sum(1 for p in alltiles for o in m.get(*p).objs if o.path.startswith("/obj/machinery/portable_atmospherics/canister")
               and not has(m.get(*p), "/obj/machinery/atmospherics/components/unary/portables_connector"))
    for path in SPARE_CANS[:max(0, SPARE_CANS_MIN - cans)]:
        if _place(m, F, ref, [dmm.Atom(path)]) is None:
            break
        added.append(path.split("/")[-1])
        n += 1
    for pre, want, kind, extra in ATMOS_MOUNTS:
        have = sum(1 for p in alltiles for o in m.get(*p).objs if o.path.startswith(pre))
        for _ in range(max(0, want - have)):
            if _hang(m, F, kind, pre, extra, ref) is None:
                break
            added.append(pre.split("/")[-1])
            n += 1
    if added:
        note("atmos: added %s" % ", ".join(added))
    return n


def _fix_terminals(m, note):
    n = 0
    for x, y, why in orphan_terminals(m):
        t = m.get(x, y)
        for o in list(t.objs):
            if o.path == "/obj/machinery/power/terminal":
                v = DIRV.get(o.num("dir", 2), (0, -1))
                if not has(m.get(x + v[0], y + v[1]), ("/obj/machinery/power/smes", "/obj/machinery/power/apc")):
                    t.objs.remove(o)
                    n += 1
    if n:
        note("terminal: %d power terminals with no SMES taken out" % n)
    return n


def _shower_spots(m, F, ref, path, limit=8):
    """Free tiles of F within `limit` steps of ref and NEAR_WAY of the walk, a wall at their side, off door fronts;
    facing pairs (across a 1-tile aisle) first."""
    import settle as SL
    doors = {(p[0] + dx, p[1] + dy) for p in F for dx, dy in N4 if is_door(m.get(p[0] + dx, p[1] + dy))}
    fronts = {p for p in F for dx, dy in N4 if (p[0] + dx, p[1] + dy) in doors}
    dist = bfs(m, [ref], limit, keep=F)
    pw = bfs(m, list(path), NEAR_WAY)
    cand = []
    for q, dq in dist.items():
        if q not in F or q in fronts or not SL._free_tile(m.get(*q), q) or has(m.get(*q), SHOWER) or q not in pw                 or has(m.get(*q), "/obj/structure/cable"):
            continue
        ws = [s for s in _wall_side(m, q) if s in (4, 8)] or _wall_side(m, q)
        if not ws:
            continue
        cand.append((dq, q, OPP[ws[0]]))
    cand.sort()
    pairs = []
    for i, (d1, q1, f1) in enumerate(cand):
        for d2, q2, f2 in cand[i + 1:]:
            facing = (q1[1] == q2[1] and abs(q1[0] - q2[0]) == 2 and {f1, f2} == {4, 8}) or \
                     (q1[0] == q2[0] and abs(q1[1] - q2[1]) == 2 and {f1, f2} == {1, 2})
            if facing:
                pairs.append((d1 + d2, q1, f1, q2, f2))
    if pairs:
        _, q1, f1, q2, f2 = min(pairs)
        return [(q1, f1), (q2, f2)]
    return [(q, f) for _, q, f in cand[:2]]


def _fix_way_in(m, D, note):
    n = 0
    path = D.way_in()
    ent = D.main_entrance()
    if not path or not ent:
        return 0
    d, inside, q, a = ent
    F = next((Fp for ap, Fp in D.eng if inside in Fp), None)
    if F is None:
        return 0
    added = []
    path = D.way_to_door(path)
    if (near(m, path, SHOWER, 12, avoid=D.ez) or 99) > NEAR_WAY:
        for s, f in _shower_spots(m, F, inside, path):
            vs = [("dir", str(f))] if f != 2 else []
            m.get(*s).objs.append(dmm.Atom(SHOWER, vs))
            added.append("shower %s" % (s,))
            n += 1
    for pre, want in ((RAD, 2), (FIRE, 1)):
        # dense closets stand beside the walk: used from a tile at most NEAR_WAY - 1 off it
        have = len(count_near(m, path, pre, NEAR_WAY - 1, avoid=D.ez))
        for _ in range(max(0, want - have)):
            spot = _place_near_way(m, F, inside, path, pre)
            if spot is None:
                break
            added.append("%s %s" % (pre.split("/")[-1], spot))
            n += 1
    if added:
        note("way_in: by the %s door %s (department side, %s): %s" % (
            airlock(m.get(*d)).get("name"), d, a, ", ".join(added)))
    if not _signed(m, path[-SIGN_SPAN:], D.ez):
        n += _rad_signs(m, [(d, inside, q)], note, "the engine")
    return n


def _place_near_way(m, F, ref, path, pre):
    """A closet on a wall-side tile of F within NEAR_WAY of the walk in, nearest ref, keeping the room's reach."""
    import settle as SL
    import placestudy as PS
    pw = bfs(m, list(path), NEAR_WAY)
    on_path = set(path)                 # beside the walk, never on it
    o = dmm.Atom(pre)
    doors = {(p[0] + dx, p[1] + dy) for p in F for dx, dy in N4 if PS._door(m.get(p[0] + dx, p[1] + dy))}
    # _spot sorts by distance to its anchor; try the anchors along the walk nearest the door first
    t = m.get(*ref)
    t.objs.append(o)
    try:
        cands = []
        seen0, free0, fronts = SL._reach(m, F, doors)
        for q in sorted(F, key=lambda q: abs(q[0] - ref[0]) + abs(q[1] - ref[1])):
            if q not in pw or q in on_path or q in fronts or not SL._free_tile(m.get(*q), q) or has(m.get(*q), SHOWER):
                continue
            if not _wall_side(m, q):
                continue
            cands.append(q)
        for q in cands[:12]:
            m.get(*q).objs.append(o)
            seen1, free1, _ = SL._reach(m, F, doors)
            used0 = {u for u in F if u not in free0 and any((u[0] + dx, u[1] + dy) in seen0 for dx, dy in N4)}
            ok = not ((free1 - seen1) - (free0 - seen0) - {q}) and all(
                any((u[0] + dx, u[1] + dy) in seen1 for dx, dy in N4) for u in used0 if u != q) and any(
                (q[0] + dx, q[1] + dy) in seen1 for dx, dy in N4)
            # the walk still goes through (the piece's doors still joined)
            if ok:
                return q
            m.get(*q).objs.remove(o)
        return None
    finally:
        t.objs = [i for i in t.objs if i is not o]


def _rad_signs(m, doors, note, what):
    n = 0
    for e in doors:
        d = e[0]
        p, q = e[1], e[2]
        axis = (q[0] - d[0], q[1] - d[1])
        along = (axis[1], axis[0])
        for s in (1, -1):
            w = (d[0] + s * along[0], d[1] + s * along[1])
            tw = m.get(*w)
            if tw is not None and tw.tpath.startswith("/turf/closed/wall") and all(o.path.startswith(UNDER) for o in tw.objs):
                tw.objs.append(dmm.Atom(RAD_SIGN))
                note("rad_sign %s: by the way into %s" % (w, what))
                n += 1
                break
    return n


def _fix_grav(m, D, note):
    """Two radiation closets in the gravity generator's rooms (deep in, off its 3x3) and a sign by its outer door."""
    import settle as SL
    n = 0
    suite, gmain, outer = _grav_suite(m, D)
    if not gmain or not outer:
        return 0
    have = {p for p in suite if has(m.get(*p), RAD)} | count_near(m, [d for d, p, q in outer], RAD, GRAV_NEAR // 2)
    # the room nearest the way in (stock: the foyer) when the suite has several, else the generator's own
    pieces_ = [(a, F) for a, F in D.piece(GRAV)]
    first = next((F for a, F in pieces_ if outer[0][1] in F), pieces_[0][1])
    dd = [bfs(m, [p], 30, keep=first) for d, p, q in outer if p in first] or [bfs(m, [outer[0][1]], 30, keep=first)]
    ok = [p for p in first if p not in SL.RESERVED and all(p in x for x in dd) and min(x[p] for x in dd) < GRAV_NEAR]
    deep = max(ok, key=lambda p: (min(x[p] for x in dd), p), default=outer[0][1])
    for _ in range(max(0, 2 - len(have))):
        spot = _place(m, first, deep, [dmm.Atom(RAD)])
        if spot is None:
            break
        note("grav: a radiation closet in the gravity generator's room at %s" % (spot,))
        n += 1
    if not _signed(m, list(suite) + [d for d, p, q in outer]):
        n += _rad_signs(m, [(d, q, p) for d, p, q in outer][:1], note, "the gravity generator")
    return n


# ------------------------------------------------------------------------------------------------ command line
def _summary(found):
    from collections import Counter
    c = Counter(t.split(":")[0] for x, y, t in found)
    return ", ".join("%s %d" % kv for kv in sorted(c.items()))


def main():
    m = dmm.read(sys.argv[1])
    before = check(m)
    print("check before: %d  (%s)" % (len(before), _summary(before)))
    for x, y, t in before:
        print("  %3d,%3d  %s" % (x, y, t))
    fix(m, log=print)
    after = check(m)
    print("check after: %d  (%s)" % (len(after), _summary(after)))
    for x, y, t in after:
        print("  %3d,%3d  %s" % (x, y, t))
    if len(sys.argv) > 2:
        dmm.write(m, sys.argv[2])
        print("wrote", sys.argv[2])


if __name__ == "__main__":
    main()
