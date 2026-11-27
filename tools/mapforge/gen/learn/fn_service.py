"""Service and civilian function pass: checks and fixes for the rooms the Cook, Botanist, Bartender, Janitor, Curator,
Chaplain, Lawyer, Clown/Mime and the crew off duty work in (kitchen, cold room, bar, hydroponics, janitor's closet,
theatre, chapel, library, law office, dorms, restrooms, tool storage).

Spec: tools/mapforge/studies/dept_specs/service.md (the stock study, each rule's stock frequency, the generator changes).

    python tools/mapforge/gen/learn/fn_service.py <in.dmm> <out.dmm>      # check, fix, check again, write
    python tools/mapforge/gen/learn/fn_service.py <in.dmm>                # check only
    python tools/mapforge/gen/learn/fn_service.py --stock                 # every rule on the 8 stock maps
    from gen.learn import fn_service; fn_service.check(m); fn_service.fix(m, seed, log)

Each rule's stock count (8 maps: Hippie, Meta, Box, Delta, Pubby, Donut, Endo, MetaLake) is in RULES. "Public" is the
floor a crew member with no access walks to from the primary hallways (airlocks with no access, never a windoor or a
table); a room's "staff side" is its floor outside that.

fix() never puts a dense piece on a door's front, keeps every room reached from its doors and never makes a public room
private (a door is given access only when everything public before stays public). What it does:

- the produce smartfridge (Bot Shift f5-f21: "botany: harvest stocked in the fridge" failed every run; the generated
  maps had no plain /obj/machinery/smartfridge at all: the stock one stands ON THE WALL between hydroponics and the
  kitchen (7 of 8 maps), which the floor-based room copies never carry) set into the wall hydroponics shares with the
  kitchen, else into hydroponics' wall onto the corridor the kitchen opens on (Delta, Endo), within the Botanist bot's
  30 tiles (goals/tend_hydroponics.dm find_produce_fridge(): exact type, powered, 30 tiles)
- the kitchen's serving hatch (the user: "kitchen needs a serving window") onto the bar, cafeteria or a public hall,
  when gen/learn/desks.py made none
- hydroponics' public desk onto a hall, when there is none
- kitchen, cold room, hydroponics and theatre airlocks the public walks through get their staff access (28, 35, 46)
- the bar's staff side: a counter of reinforced tables from a corner, the Booze-O-Mat and both dispensers on the back
  wall behind it, a "Bar Door" windoor (25;28); patron machines in its way moved to the patrons' side
- the janitor's closet gets its own door onto the corridor, hall or maintenance; its doors into other rooms are walled
- a cold room door onto anything but the kitchen (or maintenance) and a law office door into the armory, brig or
  warden's office are walled up, when every room stays reached
- no crew restroom: the one-door dorm cabin with the most wall room becomes it (2 showers, 2 toilets, a sink)
- the chapel's crematorium: one, with its ignition button (synth drops linked pieces: f22 had two crematoria and no
  button, so nothing could be cremated)
- kitchen counts to stock: one gibber, one CondiMaster, two microwaves
- missing work kit: the JaniDrobe (galoshes, goals/janitor.dm), a mop bucket, the kitchen's own fridge (eggs and milk,
  goals/cook.dm), the hydroponics machines a Botanist uses

crew 100 seed 7 f22 (2026-11-26): 23 findings before, 4 after (hydroponics desk: no clear wall; the janitor's second
piece behind the theatre; theatre not by the bar; law office inside security): layout problems for the generator.
"""
import os
import random
import sys
from collections import Counter, defaultdict, deque

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", ".."))
from forge import corpus as CO, dmm, function as FN  # noqa: E402

ROOT = os.path.normpath(os.path.join(HERE, "..", "..", "..", ".."))
N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
KITCHEN = "/area/crew_quarters/kitchen"
COLD = "/area/crew_quarters/kitchen/coldroom"
BAR = "/area/crew_quarters/bar"
HYDRO = "/area/hydroponics"
FRIDGE = "/obj/machinery/smartfridge"
BOT_REACH = 30                      # goals/tend_hydroponics.dm BOT_BOTANY_SUPPLY_REACH
COOK_STEPS = 30                     # the Cook bot looks for the fridge as far (find_produce_fridge() from cook.dm)
COOK_ACCESS = {"28", "6", "62"}     # the Cook's minimal access (code/modules/jobs/job_types/cook.dm)
SECURE = ("/area/ai_monitored/security/armory", "/area/security/brig", "/area/security/warden", "/area/security/prison",
          "/area/security/execution", "/area/ai_monitored/security")
PUBLIC_DOOR_OK = ("/obj/machinery/door/firedoor", "/obj/machinery/door/poddoor/shutters/preopen",
                  "/obj/machinery/door/poddoor/preopen")


def fam(a):
    """The service room family of an area path, or None."""
    if not a or "abandoned" in a:
        return None
    if a.startswith(COLD):
        return "coldroom"
    if a == KITCHEN or a.startswith(KITCHEN + "/"):
        return "kitchen"
    if a in (BAR, BAR + "/atrium", BAR + "/lounge"):
        return "bar"
    if a == HYDRO:
        return "hydro"
    if a.startswith(HYDRO + "/garden"):
        return "garden"
    if a.startswith("/area/janitor"):
        return "janitor"
    if a == "/area/crew_quarters/theatre":
        return "theatre"
    if a.startswith("/area/chapel/main"):
        return "chapel"
    if a.startswith("/area/chapel/office"):
        return "chapel_office"
    if a == "/area/library" or a.startswith("/area/library/"):
        return "library"
    if a.startswith("/area/lawoffice"):
        return "law"
    if a.startswith("/area/crew_quarters/dorms"):
        return "dorms"
    if a.startswith("/area/crew_quarters/toilet"):
        return "toilet"
    if a.startswith("/area/crew_quarters/locker"):
        return "locker"
    if a.startswith("/area/crew_quarters/fitness"):
        return "fitness"
    if a == "/area/storage/primary":
        return "tools"
    return None


def _floor(t):
    return t is not None and t.tpath.startswith("/turf/open") and not t.tpath.startswith("/turf/open/space")


def _access(o):
    s = set()
    for k in ("req_access_txt", "req_one_access_txt"):
        v = (o.get(k) or "").strip('"')
        s |= {x for x in v.split(";") if x.strip() and x.strip() != "0"}
    return s


class Ctx:
    """One map's walkable floor, doors, service rooms and public floor (z 1)."""

    def __init__(self, m):
        self.m = m
        self.area = {}
        self.walk = set()
        self.doors = {}                 # p -> airlock atom
        self.windoor = set()
        self.tiles = defaultdict(list)  # family -> floor tiles
        self.alltiles = defaultdict(list)   # family -> every tile of its areas (walls too: in-wall fridges, vendors)
        for (x, y, z), t in m.tiles.items():
            if z != 1:
                continue
            p = (x, y)
            self.area[p] = t.apath
            if fam(t.apath):
                self.alltiles[fam(t.apath)].append(p)
            if not _floor(t) or CO.solid(t):
                continue
            f = fam(t.apath)
            air = t.find("/obj/machinery/door/airlock")
            win = t.find("/obj/machinery/door/window")
            if f and not air:
                self.tiles[f].append(p)
            blocked = any(FN.is_dense(o) for o in t.objs if not o.path.startswith("/obj/machinery/door"))
            blocked |= any(o.path.startswith("/obj/machinery/door/poddoor") and not o.path.startswith(PUBLIC_DOOR_OK)
                           for o in t.objs)
            if air:
                self.doors[p] = air[0]
            if win:
                self.windoor.add(p)
            if not blocked:
                self.walk.add(p)
        self.public = self._public()

    def fam_at(self, p):
        return fam(self.area.get(p, ""))

    def _public(self):
        seen = {p for p in self.walk if self.area[p].startswith("/area/hallway/primary") and p not in self.doors}
        q = deque(seen)
        while q:
            p = q.popleft()
            for dx, dy in N4:
                n = (p[0] + dx, p[1] + dy)
                if n in seen or n not in self.walk or n in self.windoor:
                    continue
                if n in self.doors and _access(self.doors[n]):
                    continue
                seen.add(n)
                q.append(n)
        return seen

    def reach(self, starts, access=frozenset(), limit=10 ** 6):
        """Walking distance from starts through doors that need nothing or one of access (windoors: theirs too)."""
        dist = {p: 0 for p in starts if p in self.walk}
        q = deque(dist)
        while q:
            p = q.popleft()
            if dist[p] >= limit:
                continue
            for dx, dy in N4:
                n = (p[0] + dx, p[1] + dy)
                if n in dist or n not in self.walk:
                    continue
                if n in self.doors and _access(self.doors[n]) and not (_access(self.doors[n]) & access):
                    continue
                if n in self.windoor:
                    w = self.m.get(*n).find("/obj/machinery/door/window")[0]
                    if _access(w) and not (_access(w) & access):
                        continue
                dist[n] = dist[p] + 1
                q.append(n)
        return dist

    def has(self, f, prefix, exact=False):
        return [p for p in self.alltiles.get(f, ()) for o in self.m.get(*p).objs
                if (o.path == prefix if exact else o.isa(prefix))]

    def joins(self, f):
        """[(door tile, area beyond)] for every airlock beside the family's floor."""
        own = set(self.tiles.get(f, ()))
        out = []
        for d in self.doors:
            nb = [(d[0] + dx, d[1] + dy) for dx, dy in N4]
            if not any(n in own for n in nb):
                continue
            for n in nb:
                if n not in own and n in self.walk and n not in self.doors and self.fam_at(n) != f:
                    out.append((d, self.area[n]))
        return out


def center(ps):
    ps = list(ps)
    if not ps:
        return (0, 0)
    return (sum(p[0] for p in ps) // len(ps), sum(p[1] for p in ps) // len(ps))


# ---------------------------------------------------------------------------------------------------------------------
# rules: (id, stock "fails/maps where it applies" over the 8 stock maps, text); the checks yield findings
# ---------------------------------------------------------------------------------------------------------------------
RULES = {}


def rule(rid, text):
    def deco(fn):
        RULES[rid] = (text, fn)
        return fn
    return deco


def produce_fridges(c):
    return [p for (x, y, z), t in c.m.tiles.items() if z == 1 for p in [(x, y)]
            if any(o.path == FRIDGE for o in t.objs)]


def workplace_trays(c):
    return [p for p in c.tiles.get("hydro", ()) if c.m.get(*p).has("/obj/machinery/hydroponics")
            and not c.m.get(*p).has("/obj/machinery/hydroponics/soil")]


def fridge_ok(c, f, trays, kreach):
    """Why a produce fridge at f fails the Botanist or the Cook, or None."""
    sides = [(f[0] + dx, f[1] + dy) for dx, dy in N4]
    hyd = [s for s in sides if c.fam_at(s) == "hydro" and s in c.walk]
    if not hyd:
        return "no hydroponics floor beside it"
    if trays and max(max(abs(f[0] - t[0]), abs(f[1] - t[1])) for t in trays) > BOT_REACH:
        return "trays over %d tiles away" % BOT_REACH
    if not any(s in kreach for s in sides if s in c.walk):
        return "the Cook can't reach it (%d steps from the kitchen)" % COOK_STEPS
    return None


@rule("produce_fridge", "a produce smartfridge (exact type) beside hydroponics floor, every tray within 30, the Cook "
      "reaches it within 30 steps (the Cook bot looks 30 tiles out)")
def r_fridge(c):
    if not c.tiles.get("hydro"):
        return
    trays = workplace_trays(c)
    kreach = c.reach(c.tiles.get("kitchen", ()), COOK_ACCESS, limit=COOK_STEPS)
    fr = produce_fridges(c)
    if not fr:
        yield center(c.tiles["hydro"]) + ("no produce smartfridge on the station (Botanist and Cook have nowhere to "
                                          "share the harvest)",)
        return
    why = [fridge_ok(c, f, trays, kreach) for f in fr]
    if all(why):
        yield fr[0] + ("produce smartfridge: %s" % why[0],)


@rule("kitchen_counter", "the kitchen serves through a counter (a table on kitchen ground) onto public floor")
def r_counter(c):
    k = set(c.tiles.get("kitchen", ()))
    if not k:
        return
    if not serving_counters(c):
        yield center(k) + ("kitchen has no serving counter onto public floor (bar, cafeteria, hall)",)


def serving_counters(c, fams=("kitchen",)):
    out = []
    for (x, y, z), t in c.m.tiles.items():
        if z != 1 or fam(t.apath) not in fams or not t.has("/obj/structure/table"):
            continue
        for dx, dy in N4:
            n = (x + dx, y + dy)
            if n in c.public and c.fam_at(n) not in fams:
                out.append(((x, y), c.area[n]))
                break
    return out


@rule("kitchen_staff", "no public floor in the kitchen or the cold room (their airlocks need 28)")
def r_kitchen_staff(c):
    for f in ("kitchen", "coldroom"):
        pub = [p for p in c.tiles.get(f, ()) if p in c.public]
        if pub:
            d = [dp for dp, a in c.joins(f) if dp in c.public]
            yield (d[0] if d else pub[0]) + ("%s open to the public%s" % (f, " (door)" if d else ""),)


@rule("coldroom_joins", "the cold room opens only into the kitchen (or a staff/maintenance way)")
def r_cold(c):
    for d, a in c.joins("coldroom"):
        if fam(a) not in ("kitchen", "coldroom") and not a.startswith(("/area/maintenance", "/area/hallway/secondary/service")):
            yield d + ("cold room door onto %s" % a,)


@rule("hydro_staff", "no public floor in hydroponics (its airlocks need 35)")
def r_hydro_staff(c):
    pub = [p for p in c.tiles.get("hydro", ()) if p in c.public]
    if pub:
        d = [dp for dp, a in c.joins("hydro") if dp in c.public]
        yield (d[0] if d else pub[0]) + ("hydroponics open to the public",)


@rule("hydro_desk", "hydroponics has a desk (table on its ground) onto public floor")
def r_hydro_desk(c):
    if c.tiles.get("hydro") and not serving_counters(c, ("hydro",)):
        yield center(c.tiles["hydro"]) + ("hydroponics has no public desk",)


HYDRO_KIT = [("/obj/machinery/vending/hydroseeds", "seed vendor"), ("/obj/machinery/vending/hydronutrients", "nutrient vendor"),
             ("/obj/machinery/seed_extractor", "seed extractor"), ("/obj/machinery/biogenerator", "biogenerator"),
             ("/obj/machinery/plantgenes", "plant DNA manipulator")]


@rule("hydro_kit", "hydroponics: 8+ trays, seed and nutrient vendors, seed extractor, biogenerator, DNA manipulator, a "
      "water tank or sink")
def r_hydro_kit(c):
    h = c.tiles.get("hydro")
    if not h:
        return
    if len(workplace_trays(c)) < 8:
        yield center(h) + ("hydroponics: %d trays" % len(workplace_trays(c)),)
    for path, name in HYDRO_KIT:
        if not c.has("hydro", path):
            yield center(h) + ("hydroponics: no %s" % name,)
    if not c.has("hydro", "/obj/structure/reagent_dispensers/watertank") and not c.has("hydro", "/obj/structure/sink"):
        yield center(h) + ("hydroponics: no water tank or sink",)


BAR_SERVE = ("/obj/machinery/vending/boozeomat", "/obj/machinery/chem_dispenser/drinks")


@rule("bar_staff_side", "the bar's booze-o-mat and drink dispensers stand behind the counter (no public tile in "
      "front of them)")
def r_bar_side(c):
    for p in c.tiles.get("bar", ()):
        for o in c.m.get(*p).objs:
            if o.isa(BAR_SERVE[0]) or o.isa(BAR_SERVE[1]):
                fr = [(p[0] + dx, p[1] + dy) for dx, dy in N4 if (p[0] + dx, p[1] + dy) in c.public]
                if fr:
                    yield p + ("%s on the public side of the bar" % o.path.split("/")[-1],)


@rule("bar_kit", "bar: soda dispenser, booze dispenser, Booze-O-Mat (glasses)")
def r_bar_kit(c):
    b = c.tiles.get("bar")
    if not b:
        return
    for path, name in (("/obj/machinery/chem_dispenser/drinks", "soda dispenser"),
                       ("/obj/machinery/chem_dispenser/drinks/beer", "booze dispenser"),
                       ("/obj/machinery/vending/boozeomat", "Booze-O-Mat")):
        if not c.has("bar", path, exact=True):
            yield center(b) + ("bar: no %s" % name,)


@rule("bar_public", "the public walks into the bar")
def r_bar_public(c):
    b = c.tiles.get("bar")
    if b and not any(p in c.public for p in b):
        yield center(b) + ("bar not reached by the public",)


KITCHEN_KIT = [("/obj/machinery/microwave", "microwave"), ("/obj/machinery/processor", "food processor"),
               ("/obj/machinery/deepfryer", "deep fryer"), ("/obj/structure/sink/kitchen", "kitchen sink"),
               ("/obj/structure/closet/secure_closet/freezer/fridge", "fridge (eggs, milk)"),
               ("/obj/machinery/vending/dinnerware", "dinnerware vendor")]
MEAT_KIT = [("/obj/machinery/gibber", "gibber"), ("/obj/structure/kitchenspike", "meat spike"),
            ("/obj/structure/closet/secure_closet/freezer/meat", "meat freezer")]


@rule("kitchen_kit", "kitchen: microwave, processor, fryer, sink, egg/milk fridge, dinnerware; meat freezer, gibber, "
      "spike in it or its cold room")
def r_kitchen_kit(c):
    k = c.tiles.get("kitchen")
    if not k:
        return
    for path, name in KITCHEN_KIT:
        if not c.has("kitchen", path) and not c.has("coldroom", path):
            yield center(k) + ("kitchen: no %s" % name,)
    for path, name in MEAT_KIT:
        if not c.has("kitchen", path) and not c.has("coldroom", path):
            yield center(k) + ("kitchen: no %s" % name,)


KITCHEN_COUNT = [("/obj/machinery/gibber", 1, 1), ("/obj/machinery/chem_master/condimaster", 1, 1),
                 ("/obj/machinery/microwave", 2, 2)]       # (path, stock low, stock high): 7-8 of 8 maps exactly


@rule("kitchen_counts", "kitchen and cold room: one gibber, one CondiMaster, two microwaves (stock 7-8 of 8)")
def r_kitchen_counts(c):
    k = c.tiles.get("kitchen")
    if not k:
        return
    for path, lo, hi in KITCHEN_COUNT:
        have = c.has("kitchen", path) + c.has("coldroom", path)
        if not lo <= len(have) <= hi:
            yield (have[-1] if have else center(k)) + ("kitchen: %d %s (stock %d)" % (len(have), path.split("/")[-1], hi),)


def fix_kitchen_counts(m, c, log):
    """Extra gibbers and CondiMasters out (the cold room keeps its gibber, the kitchen its CondiMaster); a second
    microwave on a bare kitchen table that isn't the serving counter."""
    n = 0
    for path, lo, hi, keep_in in (("/obj/machinery/gibber", 1, 1, "coldroom"),
                                  ("/obj/machinery/chem_master/condimaster", 1, 1, "kitchen")):
        have = c.has(keep_in, path) + c.has("kitchen" if keep_in == "coldroom" else "coldroom", path)
        for p in have[hi:]:
            t = m.get(*p)
            o = next(x for x in t.objs if x.isa(path))
            t.objs.remove(o)
            n += 1
            log("fn_service: extra %s at %d,%d taken out" % (path.split("/")[-1], p[0], p[1]))
    c = Ctx(m)
    serving = {p for p, _ in serving_counters(c)}
    have = c.has("kitchen", "/obj/machinery/microwave") + c.has("coldroom", "/obj/machinery/microwave")
    if len(have) < 2:
        near = have[0] if have else center(c.tiles["kitchen"])
        tables = sorted((p for p in c.tiles["kitchen"] if m.get(*p).has("/obj/structure/table") and p not in serving
                         and not m.get(*p).has("/obj/machinery") and not m.get(*p).has("/obj/item/storage")
                         and (p[0], p[1] - 1) in c.walk and c.fam_at((p[0], p[1] - 1)) == "kitchen"),
                        # the cook stands south of it (an appliance's front is drawn south, forge/function.py)
                        key=lambda p: (abs(p[0] - near[0]) + abs(p[1] - near[1]), p))
        for p in tables[:2 - len(have)]:
            m.get(*p).objs.append(dmm.Atom("/obj/machinery/microwave", [("pixel_y", "6")]))
            n += 1
            log("fn_service: second microwave on the kitchen table at %d,%d" % p)
    return n


def _is_way(a):
    return a.startswith(("/area/hallway", "/area/maintenance")) or a == "/area/crew_quarters"


@rule("janitor_door", "the janitor's closet has its own airlock onto a hall, corridor or maintenance (never only "
      "through another room)")
def r_jan_door(c):
    # each walled piece of the closet (f22's was two, one behind the theatre)
    for comp, ds in _pieces(c, "janitor"):
        if len(comp) < 4:
            continue
        beyond = {c.area[(d[0] + dx, d[1] + dy)] for d in ds for dx, dy in N4 if (d[0] + dx, d[1] + dy) in c.walk
                  and (d[0] + dx, d[1] + dy) not in comp and (d[0] + dx, d[1] + dy) not in c.doors}
        if not any(_is_way(a) for a in beyond):
            yield center(comp) + ("janitor's closet (%d tiles) reached only through %s" % (
                len(comp), ", ".join(sorted(a.split("/")[-1] for a in beyond)) or "nothing"),)


@rule("janitor_kit", "janitor's closet: mop bucket or cart, JaniDrobe (galoshes), sink or water tank")
def r_jan_kit(c):
    j = c.tiles.get("janitor")
    if not j:
        return
    if not c.has("janitor", "/obj/structure/mopbucket") and not c.has("janitor", "/obj/structure/janitorialcart"):
        yield center(j) + ("janitor: no mop bucket or cart",)
    if not c.has("janitor", "/obj/machinery/vending/wardrobe/jani_wardrobe"):
        yield center(j) + ("janitor: no JaniDrobe (galoshes)",)
    if not c.has("janitor", "/obj/structure/sink") and not c.has("janitor", "/obj/structure/reagent_dispensers/watertank"):
        yield center(j) + ("janitor: no sink or water tank",)


@rule("theatre_staff", "the theatre is backstage: no public floor (its airlocks need 46)")
def r_theatre_staff(c):
    pub = [p for p in c.tiles.get("theatre", ()) if p in c.public]
    if pub:
        d = [dp for dp, a in c.joins("theatre") if dp in c.public]
        yield (d[0] if d else pub[0]) + ("theatre open to the public",)


@rule("theatre_bar", "the theatre adjoins the bar (stage window, windoor or door), backstage behind it")
def r_theatre(c):
    t = c.tiles.get("theatre")
    b = set(c.tiles.get("bar", ()))
    if not t or not b:
        return
    for p in t:
        for dx, dy in N4:
            for k in (1, 2):
                if (p[0] + dx * k, p[1] + dy * k) in b:
                    return
    yield center(t) + ("theatre does not adjoin the bar",)


@rule("restroom", "crew restrooms: 2+ showers, 2+ toilets and a sink in the crew quarters (restroom, dorms, locker "
      "room, fitness), within 25 steps of the dorms")
def r_restroom(c):
    d = c.tiles.get("dorms")
    if not d:
        return
    crew = ("toilet", "dorms", "locker", "fitness")
    near = c.reach(d, limit=25)
    for path, name, k in (("/obj/machinery/shower", "showers", 2), ("/obj/structure/toilet", "toilets", 2),
                          ("/obj/structure/sink", "sink", 1)):
        have = [p for f in crew for p in c.has(f, path)]
        if len(have) < k:
            yield center(c.tiles.get("toilet") or d) + ("crew quarters: %d %s" % (len(have), name),)
        elif not any((p[0] + dx, p[1] + dy) in near for p in have for dx, dy in ((0, 0),) + N4):
            yield have[0] + ("%s over 25 steps from the dorms" % name,)


@rule("dorm_beds", "dorms: 4+ beds")
def r_dorms(c):
    d = c.tiles.get("dorms")
    if d and len(c.has("dorms", "/obj/structure/bed")) < 4:
        yield center(d) + ("dorms: %d beds" % len(c.has("dorms", "/obj/structure/bed")),)


@rule("chapel", "chapel: 6+ seats and a front table; one crematorium with its button (same id) in the chapel's "
      "office or crematorium")
def r_chapel(c):
    ch = c.tiles.get("chapel")
    if not ch:
        return
    if len(c.has("chapel", "/obj/structure/chair")) < 6:
        yield center(ch) + ("chapel: %d seats" % len(c.has("chapel", "/obj/structure/chair")),)
    if not c.has("chapel", "/obj/structure/table"):
        yield center(ch) + ("chapel: no altar table",)
    crem = [p for p, a in _all(c, "/obj/structure/bodycontainer/crematorium")]
    if not crem:
        yield center(ch) + ("no crematorium",)
        return
    if len(crem) > 1:
        yield crem[1] + ("%d crematoria" % len(crem),)
    ids = {(a.get("id") or "1").strip('"') for p, a in _all(c, "/obj/structure/bodycontainer/crematorium")}
    btn = [(p, a) for p, a in _all(c, "/obj/machinery/button/crematorium") if (a.get("id") or "1").strip('"') in ids]
    if not btn:
        yield crem[0] + ("crematorium has no button",)


def _all(c, path):
    return [((x, y), o) for (x, y, z), t in c.m.tiles.items() if z == 1 for o in t.objs if o.isa(path)]


@rule("library", "library: 3+ bookcases, library console, scanner, binder; the public walks in")
def r_library(c):
    lib = c.tiles.get("library")
    if not lib:
        return
    if len(c.has("library", "/obj/structure/bookcase")) < 3:
        yield center(lib) + ("library: %d bookcases" % len(c.has("library", "/obj/structure/bookcase")),)
    for path, name in (("/obj/machinery/computer/libraryconsole", "library console"),
                       ("/obj/machinery/libraryscanner", "scanner"), ("/obj/machinery/bookbinder", "binder")):
        if not c.has("library", path):
            yield center(lib) + ("library: no %s" % name,)
    if not any(p in c.public for p in lib):
        yield center(lib) + ("library not reached by the public",)


@rule("law_office", "the law office opens on a hall or the court/security front, never into the armory, brig or "
      "warden's office")
def r_law(c):
    law = c.tiles.get("law")
    if not law:
        return
    for d, a in c.joins("law"):
        if a.startswith(SECURE):
            yield d + ("law office door into %s" % a,)
    dist = c.reach([p for p in c.public], {"38", "42", "63"}, limit=10 ** 6) if law else {}
    if not any(p in dist for p in law):
        yield center(law) + ("the Lawyer can't walk in from the halls",)


@rule("tool_storage", "primary tool storage: the public walks in; tool and assistant vendors")
def r_tools(c):
    t = c.tiles.get("tools")
    if not t:
        return
    if not any(p in c.public for p in t):
        yield center(t) + ("tool storage not reached by the public",)
    if not c.has("tools", "/obj/machinery/vending/tool") and not c.has("tools", "/obj/machinery/vending/assist"):
        yield center(t) + ("tool storage: no YouTool / Vendomat",)


def check(m, only=None):
    """[(x, y, text)] for every rule broken (text starts with the rule id)."""
    c = Ctx(m)
    out = []
    for rid, (text, fn) in RULES.items():
        if only and rid not in only:
            continue
        for f in fn(c):
            out.append((f[0], f[1], "%s: %s" % (rid, f[2])))
    return out


# ---------------------------------------------------------------------------------------------------------------------
# fixes
# ---------------------------------------------------------------------------------------------------------------------
def _wall(t):
    return t is not None and t.tpath.startswith("/turf/closed/wall") and not t.tpath.startswith("/turf/closed/wall/r_wall/rust") \
        and all(o.path.startswith(("/obj/structure/cable", "/obj/machinery/atmospherics/pipe", "/obj/structure/disposalpipe"))
                for o in t.objs)


def _free(m, p):
    t = m.get(*p)
    return _floor(t) and not CO.solid(t) and not any(FN.is_dense(o) for o in t.objs) and not t.has("/obj/machinery/door")


def _fronts(c):
    return {(d[0] + dx, d[1] + dy) for d in list(c.doors) + list(c.windoor) for dx, dy in N4}


def _hung_on(m, w):
    """Mounted pieces on the floor round wall tile w that hang on it."""
    out = []
    for dx, dy in N4:
        p = (w[0] + dx, w[1] + dy)
        t = m.get(*p)
        if t is None:
            continue
        for o in t.objs:
            if CO.mounted(o):
                v = FN.D4.get(CO.mount_side(o)) if hasattr(FN, "D4") else None
                v = v or {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0)}[CO.mount_side(o)]
                if (p[0] + v[0], p[1] + v[1]) == w:
                    out.append((p, o))
    return out


def fix_fridge(m, c, log):
    """Set a produce smartfridge into the wall hydroponics shares with the kitchen (stock 6 of 7), else into
    hydroponics' wall onto the corridor or hall the Cook reaches (Delta, Endo). Returns 1 if placed."""
    trays = workplace_trays(c)
    hyd = set(c.tiles.get("hydro", ()))
    if not hyd or any(fridge_ok(c, f, trays, c.reach(c.tiles.get("kitchen", ()), COOK_ACCESS, limit=COOK_STEPS)) is None
                      for f in produce_fridges(c)):
        return 0
    kreach = c.reach(c.tiles.get("kitchen", ()), COOK_ACCESS, limit=COOK_STEPS)
    hreach = c.reach([p for p in hyd if p in c.walk], {"35"})
    fronts = _fronts(c)
    cands = []
    for p in hyd:
        if p not in hreach or not _free(m, p) or p in fronts:
            continue
        for dx, dy in N4:
            w = (p[0] + dx, p[1] + dy)
            q = (w[0] + dx, w[1] + dy)
            tw = m.get(*w)
            if not _wall(tw) or w in c.doors or q not in c.walk or q in fronts or not _free(m, q) \
                    or _leans_unmounted(m, w):
                continue
            along = (dy, dx)
            if not all(CO.solid(m.get(w[0] + s * along[0], w[1] + s * along[1])) for s in (1, -1)):
                continue        # in a straight wall, not a corner
            if trays and max(max(abs(w[0] - t[0]), abs(w[1] - t[1])) for t in trays) > BOT_REACH:
                continue
            side = c.fam_at(q)
            if side == "kitchen":
                score = 0
            elif q in kreach:
                # a staff or service corridor before a public primary hall (stock: the kitchen, else Delta's and
                # Endo's service hall)
                score = 10 + kreach[q] + (30 if c.area[q].startswith("/area/hallway/primary") else 0)
            else:
                continue
            score += 3 * len(_hung_on(m, w)) + 0.01 * (abs(w[0] - center(hyd)[0]) + abs(w[1] - center(hyd)[1]))
            cands.append((score, w, p, q, along))
    import desks as DK
    for _, w, p, q, along in sorted(cands):
        # a poster or light hung on that wall moves along it (desks._shift), else the next wall
        if _hung_on(m, w) and not DK._shift(m, w, DK._hung(m), along, set(c.doors) | c.windoor):
            continue
        break
    else:
        # no wall the Cook reaches: a free-standing one in hydroponics against a wall, so the Botanist still stocks it
        # (the bot wants the exact type, powered, 30 tiles out); the layout needs the kitchen beside hydroponics
        log("fn_service: no wall for the produce smartfridge (hydroponics shares none with the kitchen or a corridor "
            "the Cook reaches): one stands inside hydroponics")
        if _place_kit(m, c, "hydro", FRIDGE, log):
            return 1
        # no free spot either (f26's kept round: no fridge at all, harvest stocked 0): a spare piece of hydroponics
        # against a wall (a table, rack, plant, crate) gives up its tile, what lay on it going with it to the floor
        spare = ("/obj/structure/table", "/obj/structure/rack", "/obj/item/twohanded/required/kirbyplants",
                 "/obj/structure/flora", "/obj/structure/closet/crate", "/obj/structure/closet/cardboard")
        for p in sorted(hyd):
            t = m.get(*p)
            o = next((x for x in t.objs if x.path.startswith(spare) and not CO.mounted(x)), None)
            # never a counter (a table under a windoor or shutters: the hydroponics desk itself, f26)
            if o is None or t.has("/obj/machinery/door") or not any(CO.solid(m.get(p[0] + dx, p[1] + dy)) for dx, dy in N4):
                continue
            t.objs = [x for x in t.objs if x is not o]
            t.objs.append(dmm.Atom(FRIDGE))
            log("fn_service: produce smartfridge in place of a %s at %d,%d" % (o.path.split("/")[-1], p[0], p[1]))
            return 1
        return 0
    t = m.get(*w)
    # the fridge stands on the wall turf, area hydroponics (powered by its APC), as on the stock maps
    t.area = dmm.Atom(HYDRO)
    t.objs.append(dmm.Atom(FRIDGE))
    log("fn_service: produce smartfridge set into the wall at %d,%d (hydroponics %d,%d / %s %d,%d)" % (
        w[0], w[1], p[0], p[1], c.area[q], q[0], q[1]))
    return 1


def _leans_on(m, w):
    """A piece on a floor tile beside wall tile w drawn shifted 8+ px toward it (a sink, a mirror, a wall machine)."""
    for dx, dy in N4:
        t = m.get(w[0] + dx, w[1] + dy)
        if t is None:
            continue
        for o in t.objs:
            px, py = o.num("pixel_x"), o.num("pixel_y")
            if (dx and -dx * px >= 8) or (dy and -dy * py >= 8):
                return True
    return False


def _leans_unmounted(m, w):
    """_leans_on, by a piece desks._shift can't move along the wall (under 16 px: a sink)."""
    for dx, dy in N4:
        t = m.get(w[0] + dx, w[1] + dy)
        for o in (t.objs if t else ()):
            px, py = o.num("pixel_x"), o.num("pixel_y")
            if ((dx and -dx * px >= 8) or (dy and -dy * py >= 8)) and not CO.mounted(o):
                return True
    return False


def _cut_counters(m, c, owner_fam, wants, style, acc, name, n_range, seed, log):
    """A counter run cut by gen/learn/desks.py's own pieces (spots, _clear, counter_objs) for an owner family."""
    import desks as DK
    r = random.Random("fn_service|%s|%s" % (owner_fam, seed))
    areas = sorted({c.area[p] for p in c.tiles.get(owner_fam, ())})
    by_area = defaultdict(set)
    for p in c.tiles.get(owner_fam, ()):
        by_area[c.area[p]].add(p)
    doors = {(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and t.has("/obj/machinery/door")}
    hung = DK._hung(m)
    for want in wants:
        for oa in areas:
            sp = DK.spots(m, by_area[oa], oa, want, hung, doors)
            # public floor on the far side only; and no sink, mirror or other offset piece leaning on that wall from
            # either side (desks' hung test takes 16 px and up; f22's hydroponics sink hung at 11)
            sp = [s for s in sp if (s[0][0] - s[1][0], s[0][1] - s[1][1]) in c.public and not _leans_unmounted(m, s[0])]
            if not sp:
                continue
            cx = sum(s[0][0] for s in sp) / float(len(sp))
            cy = sum(s[0][1] for s in sp) / float(len(sp))
            sp.sort(key=lambda s: (len(s[3]) + (1 if s[0] in hung else 0), abs(s[0][0] - cx) + abs(s[0][1] - cy), s[0]))
            n = r.randint(*n_range)
            placed = []
            for w, step, along, block in sp:
                if len(placed) >= n:
                    break
                if placed and not any(abs(w[0] - q[0]) + abs(w[1] - q[1]) == 1 for q in placed):
                    continue
                block = [(p_, o_) for p_, o_ in block if any(o_ is x for x in m.get(*p_).objs)]
                moved = DK._clear(m, block) if block else []
                if moved is None:
                    continue
                if w in hung and not DK._shift(m, w, hung, along, doors):
                    for p_, spot_, carry_ in reversed(moved):
                        ts_ = m.get(*spot_)
                        ts_.objs = [i for i in ts_.objs if not any(i is k for k in carry_)]
                        m.get(*p_).objs.extend(carry_)
                    continue
                inner = m.get(w[0] + step[0], w[1] + step[1])
                t = m.get(*w)
                t.turf = dmm.Atom(inner.tpath)
                t.area = dmm.Atom(oa)
                t.objs = [o for o in t.objs if o.path.startswith(DK.UNDER)] + DK.counter_objs(style, step, name, acc, r)
                doors.add(w)
                placed.append(w)
            if placed:
                log("fn_service: %s %s onto %s at %s" % (name, style, want if want != DK.HALL else "the hall",
                                                         " ".join("%d,%d" % w for w in placed)))
                return len(placed)
    return 0


def fix_counters(m, c, seed, log):
    import desks as DK
    n = 0
    if c.tiles.get("kitchen") and not serving_counters(c):
        # the bar's or cafeteria's floor first (Meta, Delta), else a public hall or corridor (Box, Delta's second)
        n += bool(_cut_counters(m, c, "kitchen", ("/area/crew_quarters/bar", "/area/crew_quarters/bar/atrium",
                                                  "/area/crew_quarters/cafeteria", DK.HALL, "/area/crew_quarters"),
                                "hatch", "28", "Serving Hatch", (2, 3), seed, log))
        c = Ctx(m)
    if c.tiles.get("hydro") and not serving_counters(c, ("hydro",)):
        n += bool(_cut_counters(m, c, "hydro", (DK.HALL, "/area/crew_quarters"), "desk", "35", "Hydroponics Desk",
                                (1, 2), seed, log))
    return n


def fix_access(m, c, log):
    """Public airlocks into the kitchen, cold room or hydroponics get the staff access, when nothing else public is
    cut off by it (a room behind them)."""
    n = 0
    for f, acc, name in (("kitchen", "28", "Kitchen"), ("coldroom", "28", "Kitchen Cold Room"), ("hydro", "35", "Hydroponics"),
                         ("theatre", "46", "Theatre Backstage")):
        for d, a in c.joins(f):
            o = c.doors[d]
            if _access(o) or d not in c.public:
                continue
            before = {p for p in c.public if fam(c.area[p]) not in ("kitchen", "coldroom", "hydro", "theatre")
                      and p not in c.doors}
            old = list(o.vars)
            o.vars = [(k, v) for k, v in o.vars if k not in ("req_access_txt", "req_one_access_txt", "name")] + \
                [("name", '"%s"' % name), ("req_access_txt", '"%s"' % acc)]
            c2 = Ctx(m)
            if before - c2.public:
                o.vars = old
                continue
            n += 1
            c = c2
            log("fn_service: %s door %d,%d given access %s (was public)" % (name, d[0], d[1], acc))
    return n


def fix_crematorium(m, c, log):
    crem = _all(c, "/obj/structure/bodycontainer/crematorium")
    n = 0
    for p, o in crem[1:]:
        t = m.get(*p)
        t.objs = [x for x in t.objs if x is not o]
        n += 1
        log("fn_service: second crematorium at %d,%d taken out" % p)
    if not crem:
        return n
    p, o = crem[0]
    cid = (o.get("id") or '"crematoriumChapel"')
    if not o.get("id"):
        o.vars.append(("id", cid))
    if any((b.get("id") or "1") == cid for _, b in _all(c, "/obj/machinery/button/crematorium")):
        return n
    # a free floor tile within 2 of it, in its area, with a wall to hang the button on (stock: beside the crematorium)
    area = c.area.get(p)
    fronts = _fronts(c)
    for k in (1, 2, 3):
        for dx in range(-k, k + 1):
            for dy in range(-k, k + 1):
                q = (p[0] + dx, p[1] + dy)
                if max(abs(dx), abs(dy)) != k or c.area.get(q) != area or not _floor(m.get(*q)) or q in fronts:
                    continue
                for side, (wx, wy), px in ((8, (-1, 0), ("pixel_x", "-26")), (4, (1, 0), ("pixel_x", "26")),
                                           (1, (0, 1), ("pixel_y", "26")), (2, (0, -1), ("pixel_y", "-26"))):
                    w = (q[0] + wx, q[1] + wy)
                    if not CO.solid(m.get(*w)) or w in c.doors or _hung_on(m, w):
                        continue
                    m.get(*q).objs.append(dmm.Atom("/obj/machinery/button/crematorium",
                                                   [("id", cid), px, ("req_access_txt", '"27"')]))
                    log("fn_service: crematorium button at %d,%d (crematorium %d,%d)" % (q[0], q[1], p[0], p[1]))
                    return n + 1
    return n


def _place_kit(m, c, f, path, log, vars=None):
    """A machine or structure on a free floor tile of the family against a wall, off door fronts, that keeps the
    room's free floor joined (gen/learn/settle._spot)."""
    import placestudy as PS
    import settle as ST
    tiles = c.tiles.get(f)
    if not tiles:
        return 0
    o = dmm.Atom(path, vars or [])
    for area in sorted({c.area[p] for p in tiles}, key=lambda a: -sum(1 for p in tiles if c.area[p] == a)):
        F = next((F_ for a_, F_ in PS.pieces_of(m) if a_ == area), None)
        if not F:
            continue
        doors = {(q[0] + dx, q[1] + dy) for q in F for dx, dy in N4 if PS._door(m.get(q[0] + dx, q[1] + dy))}
        start = sorted(F)[0]
        m.get(*start).objs.append(o)
        spot = ST._spot(m, F, doors, start, o)
        m.get(*start).objs = [x for x in m.get(*start).objs if x is not o]   # _spot puts it back where it was
        if spot is None:
            continue
        m.get(*spot).objs.append(o)
        log("fn_service: %s added in %s at %d,%d" % (path.split("/")[-1], area, spot[0], spot[1]))
        return 1
    return 0


KIT_FIX = [("janitor", "/obj/machinery/vending/wardrobe/jani_wardrobe", ("/obj/machinery/vending/wardrobe/jani_wardrobe",)),
           ("janitor", "/obj/structure/mopbucket", ("/obj/structure/mopbucket", "/obj/structure/janitorialcart")),
           ("kitchen", "/obj/structure/closet/secure_closet/freezer/fridge", ("/obj/structure/closet/secure_closet/freezer/fridge",)),
           ("hydro", "/obj/machinery/seed_extractor", ("/obj/machinery/seed_extractor",)),
           ("hydro", "/obj/machinery/vending/hydroseeds", ("/obj/machinery/vending/hydroseeds",)),
           ("hydro", "/obj/machinery/vending/hydronutrients", ("/obj/machinery/vending/hydronutrients",)),
           ("hydro", "/obj/structure/reagent_dispensers/watertank/high", ("/obj/structure/reagent_dispensers/watertank", "/obj/structure/sink"))]


def fix_kit(m, c, log):
    n = 0
    for f, path, have in KIT_FIX:
        if c.tiles.get(f) and not any(c.has(f, h) for h in have) and not (f == "kitchen" and c.has("coldroom", have[0])):
            n += _place_kit(m, c, f, path, log)
            c = Ctx(m)
    return n


def _staff_reach(c):
    """Floor reached from the primary halls with every access there is (who can get where at all)."""
    starts = [p for p in c.walk if c.area[p].startswith("/area/hallway/primary")]
    allacc = {a for o in c.doors.values() for a in _access(o)}
    for p in c.windoor:
        for w in c.m.get(*p).find("/obj/machinery/door/window"):
            allacc |= _access(w)
    return set(c.reach(starts, allacc))


def fix_law(m, c, log):
    """A law office door into the armory, brig or warden's office is walled up when the office keeps another door
    and every room stays reached (f22: the Lawyer's 38 opened the armory from the office)."""
    n = 0
    for d, a in c.joins("law"):
        if not a.startswith(SECURE) or not [x for x, b in c.joins("law") if x != d]:
            continue
        areas0 = {c.area[p] for p in _staff_reach(c)}
        t = m.get(*d)
        old = (list(t.objs), t.turf)
        walls = [m.get(d[0] + dx, d[1] + dy).tpath for dx, dy in N4 if m.get(d[0] + dx, d[1] + dy) is not None
                 and m.get(d[0] + dx, d[1] + dy).tpath.startswith("/turf/closed/wall")]
        t.objs = [o for o in t.objs if o.path.startswith(("/obj/structure/cable", "/obj/machinery/atmospherics/pipe",
                                                          "/obj/structure/disposalpipe"))]
        t.turf = dmm.Atom(walls[0] if walls else "/turf/closed/wall")
        c2 = Ctx(m)
        if areas0 - {c2.area[p] for p in _staff_reach(c2)}:
            t.objs, t.turf = old
            continue
        c = c2
        n += 1
        log("fn_service: law office door %d,%d into %s walled up" % (d[0], d[1], a))
    return n


UNDER = ("/obj/structure/cable", "/obj/machinery/atmospherics/pipe", "/obj/structure/disposalpipe")


def _try_wall(m, c, d, why, log):
    """Wall up airlock d if every area reached before (with every access) still is. Returns the new Ctx or None."""
    areas0 = {c.area[p] for p in _staff_reach(c)}
    t = m.get(*d)
    old = (list(t.objs), t.turf)
    walls = [m.get(d[0] + dx, d[1] + dy).tpath for dx, dy in N4 if m.get(d[0] + dx, d[1] + dy) is not None
             and m.get(d[0] + dx, d[1] + dy).tpath.startswith("/turf/closed/wall")]
    t.objs = [o for o in t.objs if o.path.startswith(UNDER)]
    t.turf = dmm.Atom(walls[0] if walls else "/turf/closed/wall")
    c2 = Ctx(m)
    if areas0 - {c2.area[p] for p in _staff_reach(c2)}:
        t.objs, t.turf = old
        return None
    log("fn_service: door %d,%d walled up (%s)" % (d[0], d[1], why))
    return c2


def _way(a):
    return a.startswith(("/area/hallway", "/area/maintenance")) or a == "/area/crew_quarters"


def fix_janitor(m, c, log):
    """Each piece of the janitor's closet gets its own airlock onto the hall, corridor or maintenance through a single
    wall (stock 8 of 8: the closet opens on a hall or maintenance, the cart rolls straight out), then its doors into
    other rooms (f22: the theatre and the garden) are walled up. Returns the changes."""
    n = 0
    for comp, ds in _pieces(c, "janitor"):
        way = [d for d in ds for dx, dy in N4 if (d[0] + dx, d[1] + dy) in c.walk and _way(c.area.get((d[0] + dx, d[1] + dy), ""))
               and (d[0] + dx, d[1] + dy) not in comp]
        if not way:
            fronts = _fronts(c)
            best = None
            for p in comp:
                if p not in c.walk or p in fronts:
                    continue
                for dx, dy in N4:
                    w, q = (p[0] + dx, p[1] + dy), (p[0] + 2 * dx, p[1] + 2 * dy)
                    if not _wall(m.get(*w)) or q not in c.walk or q in fronts or not _way(c.area.get(q, "")) \
                            or _leans_unmounted(m, w):
                        continue
                    along = (dy, dx)
                    if not all(CO.solid(m.get(w[0] + s * along[0], w[1] + s * along[1])) for s in (1, -1)):
                        continue
                    maint = c.area[q].startswith("/area/maintenance")
                    score = (1 if maint else 0, len(_hung_on(m, w)), w)
                    if best is None or score < best[0]:
                        best = (score, w, p, q, maint, along)
            if best is None:
                continue
            _, w, p, q, maint, along = best
            if _hung_on(m, w):
                # a light or alarm on that wall moves along it (gen/learn/desks.py _shift)
                import desks as DK
                if not DK._shift(m, w, DK._hung(m), along, set(c.doors) | c.windoor):
                    continue
            t = m.get(*w)
            t.turf = dmm.Atom(m.get(*p).tpath)
            t.area = dmm.Atom(c.area[p])
            t.objs = [o for o in t.objs if o.path.startswith(UNDER)] + [
                dmm.Atom("/obj/machinery/door/airlock/maintenance" if maint else "/obj/machinery/door/airlock",
                         [("name", '"Custodial Maintenance"' if maint else '"Custodial Closet"'), ("req_access_txt", '"26"')]),
                dmm.Atom("/obj/machinery/door/firedoor")]
            n += 1
            log("fn_service: janitor's closet door cut at %d,%d onto %s" % (w[0], w[1], c.area[q]))
            c = Ctx(m)
        # doors into other rooms (not halls, maintenance or another janitor piece) are walled up
        for d in sorted(ds):
            beyond = [c.area[(d[0] + dx, d[1] + dy)] for dx, dy in N4 if (d[0] + dx, d[1] + dy) in c.walk
                      and (d[0] + dx, d[1] + dy) not in comp and (d[0] + dx, d[1] + dy) not in c.doors]
            if not beyond or any(_way(a) or fam(a) == "janitor" for a in beyond):
                continue
            c2 = _try_wall(m, c, d, "janitor's closet into %s" % beyond[0], log)
            if c2:
                c = c2
                n += 1
    return n


def fix_coldroom(m, c, log):
    """A cold room door onto anything but the kitchen or a staff way is walled up (stock 0 such of 4 cold rooms;
    f22's opened the cold room onto the bar)."""
    n = 0
    for d, a in list(c.joins("coldroom")):
        if fam(a) in ("kitchen", "coldroom") or a.startswith(("/area/maintenance", "/area/hallway/secondary/service")):
            continue
        if not [x for x, b in c.joins("coldroom") if x != d]:
            continue
        c2 = _try_wall(m, c, d, "cold room onto %s" % a, log)
        if c2:
            c = c2
            n += 1
    return n


CLEARABLE = ("/obj/structure/chair", "/obj/structure/table", "/obj/item", "/obj/machinery/vending/boozeomat",
             "/obj/machinery/chem_dispenser/drinks", "/obj/effect/decal", "/obj/structure/bed")
PATRON_VEND = ("/obj/machinery/vending/cigarette", "/obj/machinery/vending/snack", "/obj/machinery/vending/cola",
               "/obj/machinery/vending/coffee", "/obj/machinery/computer/arcade", "/obj/machinery/computer/slot_machine")
FIXTURE = UNDER + ("/obj/machinery/light", "/obj/machinery/power/apc", "/obj/machinery/airalarm", "/obj/machinery/firealarm",
                   "/obj/machinery/light_switch", "/obj/item/radio/intercom", "/obj/machinery/newscaster",
                   "/obj/machinery/camera", "/obj/structure/sign", "/obj/machinery/status_display",
                   "/obj/structure/extinguisher_cabinet", "/obj/effect/landmark", "/obj/machinery/door/firedoor",
                   "/obj/machinery/navbeacon", "/obj/machinery/requests_console", "/obj/machinery/computer/security/telescreen")
DIRN = {(0, 1): "north", (0, -1): "south", (1, 0): "east", (-1, 0): "west"}
SMALL_STAFF = ("/obj/machinery/reagentgrinder",)     # a table-top machine that moves with the loose things


def _bar_bands(m, c, tiles, doors_all):
    """Candidate staff sides: a back row against a wall from a corner, the bartender's walk row, the counter row and
    the patrons' row in front, L columns, the last column closed with tables."""
    tset = set(tiles)
    fronts = {(d[0] + dx, d[1] + dy) for d in doors_all for dx, dy in N4}
    out = []
    for v in N4:
        for a in ((abs(v[1]), abs(v[0])), (-abs(v[1]), -abs(v[0]))):
            for p0 in tiles:
                if not CO.solid(m.get(p0[0] + v[0], p0[1] + v[1])):
                    continue
                if not all(CO.solid(m.get(p0[0] - a[0] - k * v[0], p0[1] - a[1] - k * v[1])) for k in (0, 1, 2)):
                    continue        # a corner: the band's start is closed by the side wall
                for L in (6, 5, 4):
                    cols = []
                    ok = True
                    for i in range(L):
                        R = (p0[0] + i * a[0], p0[1] + i * a[1])
                        W = (R[0] - v[0], R[1] - v[1])
                        C = (R[0] - 2 * v[0], R[1] - 2 * v[1])
                        P = (R[0] - 3 * v[0], R[1] - 3 * v[1])
                        if not all(x in tset for x in (R, W, C)) or not CO.solid(m.get(R[0] + v[0], R[1] + v[1])) \
                                or (R[0] + v[0], R[1] + v[1]) in doors_all:
                            ok = False
                            break
                        if any(x in fronts or x in doors_all for x in (R, W, C)):
                            ok = False
                            break
                        for x in (W, C):
                            if any(not o.path.startswith(CLEARABLE + FIXTURE + PATRON_VEND) and FN.is_dense(o) for o in m.get(*x).objs):
                                ok = False
                        cols.append((R, W, C, P))
                    if not ok:
                        continue
                    # the patrons' row is the bar's floor, the windoor's way out free
                    if sum(1 for col in cols if col[3] in tset) < L - 1 or cols[0][3] not in tset \
                            or cols[0][3] in doors_all or any(FN.is_dense(o) for o in m.get(*cols[0][3]).objs):
                        continue
                    # a back-row tile for a machine: nothing dense but what moves, no other machine on it
                    slots = [col[0] for col in cols[:-1]
                             if not any((FN.is_dense(o) and not o.path.startswith(CLEARABLE + PATRON_VEND))
                                        or (o.path.startswith("/obj/machinery") and not o.path.startswith(
                                            CLEARABLE + PATRON_VEND + FIXTURE + SMALL_STAFF) and not CO.mounted(o))
                                        for o in m.get(*col[0]).objs)]
                    if len(slots) < 3:
                        continue
                    busy = sum(1 for col in cols for x in col[:3] for o in m.get(*x).objs
                               if FN.is_dense(o) and not o.path.startswith(FIXTURE))
                    out.append((busy, -L, p0, v, a, cols, slots))
                    break
    out.sort(key=lambda k: (k[0], k[1], k[2], k[3]))
    return out


def fix_bar(m, c, log):
    """The bar's staff side (stock 8 of 8: the Booze-O-Mat and both drink dispensers behind a counter of reinforced
    tables, the bartender in through a "Bar Door" windoor (25;28); f22's bar had them on the patrons' floor): a band
    from a corner of the bar, back row on the wall (the machines), walk row, counter row, last column closed. Tried
    band by band; one is kept only if every public tile of the bar stays public and the dispensers end up staff-side."""
    tiles = c.tiles.get("bar")
    if not tiles or not list(r_bar_side(c)):
        return 0
    area = Counter(c.area[p] for p in tiles).most_common(1)[0][0]
    tiles = [p for p in tiles if c.area[p] == area]
    doors_all = set(c.doors) | c.windoor
    pub0 = {p for p in tiles if p in c.public}
    snap = {p: m.get(*p).copy() for p in tiles}
    for busy, _, p0, v, a, cols, slots in _bar_bands(m, c, tiles, doors_all)[:12]:
        serve = []
        for p in tiles:
            t = m.get(*p)
            for o in list(t.objs):
                if o.isa("/obj/machinery/vending/boozeomat") or o.isa("/obj/machinery/chem_dispenser/drinks"):
                    serve.append(o)
                    t.objs.remove(o)
        loose = []
        band = [x for col in cols for x in col[:3]]
        moved_out = []
        for x in band:
            t = m.get(*x)
            keep = []
            for o in t.objs:
                if o.path.startswith(FIXTURE) or CO.mounted(o):
                    keep.append(o)
                elif x in slots or x in [col[1] for col in cols] or x in [col[2] for col in cols]:
                    if o.path.startswith(("/obj/item",) + SMALL_STAFF):
                        loose.append(o)
                    elif o.path.startswith(PATRON_VEND):
                        moved_out.append(o)
                    elif not o.path.startswith(CLEARABLE):
                        keep.append(o)
                else:
                    keep.append(o)
            t.objs = keep
        face = str(FACE[v])
        # machines in the back row: the Booze-O-Mat, the soda and the booze dispenser on tables
        soda = next((o for o in serve if o.path == "/obj/machinery/chem_dispenser/drinks"), dmm.Atom("/obj/machinery/chem_dispenser/drinks"))
        beer = next((o for o in serve if o.path == "/obj/machinery/chem_dispenser/drinks/beer"), dmm.Atom("/obj/machinery/chem_dispenser/drinks/beer"))
        booze = next((o for o in serve if o.isa("/obj/machinery/vending/boozeomat")), dmm.Atom("/obj/machinery/vending/boozeomat"))
        for o in (soda, beer):
            o.vars = [(k_, v_) for k_, v_ in o.vars if k_ != "dir"] + [("dir", face)]
        for slot, pieces in zip(slots, ([booze], [dmm.Atom("/obj/structure/table/reinforced"), soda],
                                        [dmm.Atom("/obj/structure/table/reinforced"), beer])):
            m.get(*slot).objs.extend(pieces)
        for slot in slots[3:]:
            m.get(*slot).objs.append(dmm.Atom("/obj/structure/table/reinforced"))
        last = cols[-1]
        for x in last[:3]:
            if not any(FN.is_dense(o) for o in m.get(*x).objs):
                m.get(*x).objs.append(dmm.Atom("/obj/structure/table/reinforced"))
        out_dir = DIRN[(v[0], v[1])]           # the windoor stands on the staff side's edge of its tile
        for i, (R, W, C, P) in enumerate(cols[:-1]):
            t = m.get(*C)
            if i == 0:
                t.objs.append(dmm.Atom("/obj/machinery/door/window/%sright" % out_dir,
                                       [("name", '"Bar Door"'), ("req_one_access_txt", '"25;28"')]))
            else:
                t.objs.append(dmm.Atom("/obj/structure/table/reinforced"))
        # what was in the band's way goes to free wall spots on the patrons' side (gen/learn/settle._spot)
        import placestudy as PS
        import settle as ST
        lost_vend = 0
        for o in moved_out:
            F = next((F_ for a_, F_ in PS.pieces_of(m) if a_ == area), None)
            F = [p for p in (F or ()) if p not in band]
            if not F:
                lost_vend += 1
                continue
            start = sorted(F)[0]
            m.get(*start).objs.append(o)
            dset = {(q[0] + dx, q[1] + dy) for q in F for dx, dy in N4 if PS._door(m.get(q[0] + dx, q[1] + dy))}
            spot = ST._spot(m, F, dset, start, o)
            m.get(*start).objs = [x for x in m.get(*start).objs if x is not o]   # _spot puts it back where it was
            if spot is None:
                lost_vend += 1
            else:
                m.get(*spot).objs.append(o)
        # the loose things (bottles, the shotgun, the cash, the grinder) on the staff side's tables only: the back row
        # and the closing column, never the counter
        tables = [x for col in cols for x in (col[0],) if m.get(*x).has("/obj/structure/table")
                  and not m.get(*x).has("/obj/machinery/chem_dispenser")] + \
            [x for x in cols[-1][:2] if m.get(*x).has("/obj/structure/table")]
        for i, o in enumerate(loose):
            if tables:
                m.get(*tables[i % len(tables)]).objs.append(o)
        c2 = Ctx(m)
        staff = c2.reach(list(c2.public), {"25"})
        lost = {p for p in pub0 if p not in band} - c2.public
        if not list(r_bar_side(c2)) and not lost and not lost_vend and all(col[1] in staff for col in cols[:-1]):
            log("fn_service: bar counter built from %d,%d along %s, back to the %s wall (%d columns, Bar Door at %d,%d%s)" % (
                p0[0], p0[1], DIRN[a], DIRN[v], len(cols), cols[0][2][0], cols[0][2][1],
                ", %d patron machines moved out" % len(moved_out) if moved_out else ""))
            return 1
        for p, t in snap.items():
            m.set(p[0], p[1], t.copy())
    log("fn_service: no band in the bar for a staff side")
    return 0


KEEP = ("/obj/structure/cable", "/obj/machinery/atmospherics", "/obj/structure/disposalpipe", "/obj/machinery/light",
        "/obj/machinery/power/apc", "/obj/machinery/airalarm", "/obj/machinery/firealarm", "/obj/machinery/light_switch",
        "/obj/item/radio/intercom", "/obj/machinery/newscaster", "/obj/machinery/camera", "/obj/effect/landmark",
        "/obj/structure/sign", "/obj/machinery/status_display", "/obj/structure/extinguisher_cabinet",
        "/obj/machinery/door", "/obj/machinery/navbeacon")
# wall direction from the tile -> the dir a shower or toilet faces (away from the wall), a sink's offset onto it
FACE = {(-1, 0): 4, (1, 0): 8, (0, 1): 2, (0, -1): 1}
SINK_OFF = {(-1, 0): ("pixel_x", "-12"), (1, 0): ("pixel_x", "12"), (0, 1): ("pixel_y", "28"), (0, -1): ("pixel_y", "-4")}


def _pieces(c, f):
    """Walk-joined floor pieces of a family, not crossing airlocks: [(tiles, airlocks beside)]."""
    own = set(c.tiles.get(f, ()))
    seen, out = set(), []
    for s in sorted(own):
        if s in seen:
            continue
        comp, q, ds = {s}, [s], set()
        seen.add(s)
        while q:
            p = q.pop()
            for dx, dy in N4:
                n = (p[0] + dx, p[1] + dy)
                if n in c.doors:
                    ds.add(n)
                elif n in own and n not in seen:
                    seen.add(n)
                    comp.add(n)
                    q.append(n)
        out.append((comp, ds))
    return out


def fix_restroom(m, c, log):
    """No crew restroom (f22: no crew toilet or shower anywhere; every stock map has 5-28 showers and 2-9 toilets in
    its crew quarters): the one-door dorm cabin with the most wall room becomes the unisex restroom (2 showers, 2
    toilets, a sink), keeping the dorms area as Endo keeps its showers in the dorms. At least 4 beds stay."""
    if not c.tiles.get("dorms") or not list(r_restroom(c)):
        return 0
    beds = set(c.has("dorms", "/obj/structure/bed"))
    cands = []
    for comp, ds in _pieces(c, "dorms"):
        if len(ds) != 1 or not 6 <= len(comp) <= 24:
            continue
        nb = len(beds & comp)
        if not nb or len(beds) - nb < 4:
            continue
        d = next(iter(ds))
        fronts = {(d[0] + dx, d[1] + dy) for dx, dy in N4}
        walls = [(p, v) for p in comp if p not in fronts for v in FACE
                 if CO.solid(m.get(p[0] + v[0], p[1] + v[1])) and (p[0] + v[0], p[1] + v[1]) not in c.doors]
        cands.append((-len({p for p, _ in walls}), -len(comp), sorted(comp)[0], comp, d, walls))
    if not cands:
        log("fn_service: no dorm cabin to make the restroom")
        return 0
    cands.sort(key=lambda k: k[:3])
    comp, d, walls = cands[0][3:]
    for p in comp:
        t = m.get(*p)
        t.objs = [o for o in t.objs if o.path.startswith(KEEP) or (CO.mounted(o) and not o.path.startswith("/obj/structure/closet"))]
        t.turf = dmm.Atom("/turf/open/floor/plasteel/freezer")
    # deepest from the door first; one piece a tile
    walls.sort(key=lambda pv: (-(abs(pv[0][0] - d[0]) + abs(pv[0][1] - d[1])), pv))
    used, placed = set(), Counter()
    for path, k in (("/obj/machinery/shower", 2), ("/obj/structure/toilet", 2), ("/obj/structure/sink", 1)):
        for p, v in walls:
            if placed[path] >= k:
                break
            if p in used:
                continue
            vars_ = [("dir", str(FACE[v]))] + ([SINK_OFF[v]] if path == "/obj/structure/sink" else [])
            m.get(*p).objs.append(dmm.Atom(path, vars_))
            used.add(p)
            placed[path] += 1
    door = c.doors[d]
    door.vars = [(k_, v_) for k_, v_ in door.vars if k_ not in ("name", "req_access_txt", "req_one_access_txt", "id_tag")] + \
        [("name", '"Unisex Restrooms"')]
    log("fn_service: dorm cabin by door %d,%d (%d tiles) made the restroom: %s" % (
        d[0], d[1], len(comp), ", ".join("%s x%d" % (k_.split("/")[-1], v_) for k_, v_ in placed.items())))
    return 1


def fix(m, seed=1, log=print):
    """Fix what a finished layout can: see the module docstring. Returns the number of changes."""
    n = 0
    c = Ctx(m)
    n += fix_access(m, c, log)
    c = Ctx(m)
    n += fix_fridge(m, c, log)
    c = Ctx(m)
    n += fix_counters(m, c, seed, log)
    c = Ctx(m)
    n += fix_law(m, c, log)
    c = Ctx(m)
    n += fix_restroom(m, c, log)
    c = Ctx(m)
    n += fix_janitor(m, c, log)
    c = Ctx(m)
    n += fix_coldroom(m, c, log)
    c = Ctx(m)
    n += fix_bar(m, c, log)
    c = Ctx(m)
    n += fix_kitchen_counts(m, c, log)
    c = Ctx(m)
    n += fix_crematorium(m, c, log)
    c = Ctx(m)
    n += fix_kit(m, c, log)
    return n


def summary(fs):
    return dict(Counter(t.split(":")[0] for _, _, t in fs))


def stock(out=print):
    """Each rule on the 8 stock maps: which maps break it."""
    per = defaultdict(list)
    for rel in CO.MAPS:
        m = dmm.read(os.path.join(ROOT, "_maps", "map_files", rel))
        fs = check(m)
        name = rel.split("/")[0]
        out("%-14s %s" % (name, summary(fs)))
        for x, y, t in fs:
            out("    %d,%d %s" % (x, y, t))
            per[t.split(":")[0]].append(name)
    out("")
    for rid in RULES:
        out("%-16s fails on %d of 8: %s" % (rid, len(set(per[rid])), ", ".join(sorted(set(per[rid])))))


if __name__ == "__main__":
    if "--stock" in sys.argv:
        stock()
        sys.exit(0)
    m = dmm.read(sys.argv[1])
    before = check(m)
    print("before: %d %s" % (len(before), summary(before)))
    for x, y, t in before:
        print("  %d,%d %s" % (x, y, t))
    if len(sys.argv) > 2:
        n = fix(m, 1)
        after = check(m)
        print("fix: %d changes" % n)
        print("after: %d %s" % (len(after), summary(after)))
        for x, y, t in after:
            print("  %d,%d %s" % (x, y, t))
        dmm.write(m, sys.argv[2])
