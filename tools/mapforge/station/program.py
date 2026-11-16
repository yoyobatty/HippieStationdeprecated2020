"""What a station holds, scaled to its crew.

Room sizes are the medians of the eight human stations (studies/stations.py -> data/mapforge/room_study.json). Those
stations hold 70-140 crew start points on 9-14.5k open tiles; MiniStation holds 32 on 2.75k. A room scales with the
crew a little slower than linearly (a bar for 30 is not a third of a bar for 90), and rooms a small crew never uses
drop out below their `need`.

Each department lists its rooms in tiers, front to back: tier 0 faces the ring hall, the last tier backs onto maint
or space. `front` says what a room needs a door onto:
    ring    the main hall everyone walks (a counter or a public door)
    dept    the department's own hall, behind its lobby's access door
    back    the hull: a dock, an engine's space side, an airlock out
    hall    (core only) the ring or the core's cross halls
A room with front=() is only reached through its `links` (the armory through the Warden's office).
"""
import random

REF_CREW = 80
FILL = 0.8


class Rm:
    def __init__(self, rid, area, tier=0, front=("dept",), min=(3, 3), links=(), need=0, label=None, secure=False,
                 public=False, maint=False, corridor=False, near=(), dock=None):
        self.id, self.area, self.tier, self.front, self.min = rid, area, tier, front, min
        self.links, self.need, self.label = links, need, label or rid
        self.secure = secure        # walls toward maint/halls are reinforced, doors are secure doors
        self.public = public        # anyone may walk in (bar, library, lobbies)
        self.maint = maint          # wants a maint door
        self.corridor = corridor
        self.near = near
        self.dock = dock            # "arrivals" / "escape" / "cargo" / "mining": a shuttle docks on its back wall


class Dept:
    def __init__(self, name, colour, rooms, where="outer", lobby=None, spine=2, need=0, public_spine=False,
                 label=None):
        self.name, self.colour, self.rooms, self.where = name, colour, rooms, where
        self.lobby = lobby          # Rm for the public front at the spine's mouth, or None
        self.spine = spine          # width of the department's own hall
        self.need = need
        self.public_spine = public_spine
        self.label = label or name


# MetaStation-ish department colours (floor trim), for the plan pictures
C = dict(security=(196, 64, 64), medical=(92, 160, 214), science=(150, 98, 196), engineering=(222, 168, 52),
         atmos=(70, 180, 170), cargo=(176, 130, 76), command=(64, 96, 180), service=(98, 168, 84),
         civic=(186, 170, 130), dorms=(170, 130, 170), arrivals=(150, 150, 160), escape=(150, 150, 160),
         ai=(70, 120, 120))


def departments():
    R = Rm
    return [
        Dept("security", C["security"], [
            R("cells", 60, 0, ("dept",), (3, 6), label="cells"),
            R("detective", 32, 0, ("dept",), label="det"),
            R("lawyer", 26, 0, ("ring",), public=True, label="law", need=30),
            R("court", 85, 0, ("ring",), (6, 8), public=True, need=45, label="court"),
            R("processing", 40, 1, ("dept",), label="proc", need=35),
            R("office", 110, 1, ("dept",), (6, 8), label="briefing"),
            R("warden", 45, 1, ("dept",), links=("armory",), label="warden"),
            R("armory", 45, 1, (), secure=True, label="armory"),
            R("hos", 40, 1, ("dept",), label="HoS"),
            R("interro", 25, 1, ("dept",), label="interro", need=45),
            R("gear", 30, 1, ("dept",), label="gear"),
            R("evidence", 18, 1, ("dept",), label="evid", need=50),
            R("perma", 180, 2, ("dept",), (7, 10), secure=True, label="perma", need=30),
            R("transfer", 38, 2, ("dept",), maint=True, label="transfer", need=50),
        ], lobby=R("sec_lobby", 24, front=("ring",), public=True, label="front desk")),
        Dept("medical", C["medical"], [
            R("treatment", 150, 0, ("dept",), (7, 9), label="treatment"),
            R("chem", 50, 0, ("ring",), label="chem"),
            R("cryo", 28, 0, ("dept",), label="cryo"),
            R("surgery", 65, 1, ("dept",), (5, 7), label="surgery"),
            R("medstore", 38, 1, ("dept",), label="storage"),
            R("cmo", 32, 1, ("dept",), label="CMO"),
            R("genetics", 65, 1, ("dept",), label="genetics", need=30),
            R("cloning", 32, 1, ("dept",), label="cloning", need=30, near=("genetics",)),
            R("morgue", 37, 2, ("dept",), maint=True, label="morgue"),
            R("virology", 110, 2, ("dept",), (6, 8), secure=True, label="virology", need=45),
            R("paramedic", 24, 2, ("dept",), maint=True, label="para", need=55),
        ], lobby=R("med_lobby", 50, front=("ring",), public=True, label="reception")),
        Dept("science", C["science"], [
            R("rnd", 55, 0, ("ring",), label="R&D"),
            R("robotics", 80, 0, ("ring",), (6, 7), links=("mechbay",), label="robotics"),
            R("mechbay", 33, 0, ("dept",), label="mechbay"),
            R("rd", 36, 1, ("dept",), links=("server",), label="RD"),
            R("server", 19, 1, (), secure=True, label="server"),
            R("explab", 55, 1, ("dept",), label="explab"),
            R("nanite", 45, 1, ("dept",), label="nanite", need=50),
            R("testlab", 55, 1, ("dept",), label="testing", need=50),
            R("toxins", 95, 2, ("dept",), (6, 8), links=("toxstore",), label="toxins"),
            R("toxstore", 27, 2, (), label="tox store"),
            R("range", 43, 2, ("dept", "back"), label="range", need=50),
            R("xeno", 250, 2, ("dept",), (10, 12), secure=True, label="xenobio", need=30),
        ], lobby=R("sci_lobby", 30, front=("ring",), public=True, label="sci desk")),
        Dept("engineering", C["engineering"], [
            R("eng_check", 20, 0, ("ring",), label="post", need=55),
            R("techstore", 55, 0, ("dept",), secure=True, label="tech"),
            R("workshop", 90, 0, ("dept",), (6, 7), label="workshop"),
            R("ce", 32, 1, ("dept",), label="CE"),
            R("smes", 50, 1, ("dept",), label="SMES"),
            R("grav", 50, 1, ("dept",), secure=True, label="grav"),
            R("engbreak", 40, 1, ("dept",), label="break", need=50),
            R("engine", 320, 2, ("dept", "back"), (14, 16), label="ENGINE"),
        ], lobby=R("eng_lobby", 20, front=("ring",), public=True, label="eng desk")),
        Dept("atmos", C["atmos"], [
            R("atmos", 260, 0, ("dept",), (10, 12), label="atmos"),
            R("atmos_store", 30, 0, ("dept",), label="store"),
            R("tanks", 150, 1, ("dept", "back"), (6, 12), label="gas tanks"),
        ], lobby=R("atm_lobby", 18, front=("ring",), public=True, label="atmos desk")),
        Dept("cargo", C["cargo"], [
            R("cargo_office", 70, 0, ("ring",), label="office"),
            R("cargo_check", 22, 0, ("dept",), label="post", need=55),
            R("qm", 28, 1, ("dept",), label="QM"),
            R("sorting", 43, 1, ("dept",), label="sorting"),
            R("warehouse", 30, 1, ("dept",), label="wares", need=50),
            R("bay", 170, 2, ("dept", "back"), (8, 12), label="cargo bay", dock="cargo"),
            R("mining", 70, 2, ("dept", "back"), (5, 8), label="mining", dock="mining"),
        ], lobby=R("cargo_lobby", 30, front=("ring",), public=True, label="cargo lobby")),
        Dept("dorms", C["dorms"], [
            R("cabins", 110, 0, ("dept",), (5, 10), public=True, label="cabins"),
            R("lockers", 95, 0, ("ring",), public=True, label="lockers"),
            R("restroom", 46, 1, ("dept",), public=True, label="restroom"),
            R("gym", 130, 1, ("dept",), (7, 9), public=True, label="gym", need=50),
            R("cryodorm", 30, 1, ("dept",), public=True, label="cryo", need=25),
        ], public_spine=True, label="dorms"),
        Dept("civic", C["civic"], [
            R("library", 150, 0, ("ring",), (8, 9), public=True, label="library"),
            R("toolstore", 75, 0, ("ring",), public=True, label="tools"),
            R("art", 12, 0, ("dept",), public=True, label="art", need=30),
            R("chapel", 135, 1, ("dept",), (8, 10), public=True, links=("chap_office",), label="chapel"),
            R("chap_office", 50, 1, ("dept",), label="chap office"),
            R("vacant", 50, 1, ("dept",), public=True, label="vacant", need=60),
        ], public_spine=True, label="civic"),
        Dept("arrivals", C["arrivals"], [
            R("arr_lounge", 100, 0, ("dept",), public=True, label="arrivals"),
            R("customs", 24, 0, ("ring",), label="customs", need=45),
            R("arr_store", 20, 0, ("dept",), maint=True, label="storage"),
        ], public_spine=True, spine=3, label="arrivals"),
        Dept("escape", C["escape"], [
            R("departures", 160, 0, ("dept",), (7, 10), public=True, label="departures"),
            R("esc_check", 22, 0, ("dept",), label="post", need=35),
        ], public_spine=True, spine=3, label="escape"),
        # ---- the core, inside the ring
        Dept("command", C["command"], [
            R("bridge", 170, 0, ("hall",), (8, 10), label="BRIDGE"),
            R("captain", 70, 0, ("hall",), links=("cap_bed",), label="captain"),
            R("cap_bed", 30, 0, (), label="cap bed", need=45),
            R("hop", 43, 0, ("hall",), label="HoP"),
            R("eva", 68, 0, ("hall",), label="EVA"),
            R("teleporter", 29, 0, ("hall",), label="tele"),
            R("gateway", 43, 0, ("hall",), label="gateway", need=50),
            R("vault", 30, 0, ("hall",), secure=True, label="vault"),
            R("upload", 44, 0, ("hall",), secure=True, label="upload"),
        ], where="core"),
        Dept("service", C["service"], [
            R("bar", 150, 0, ("hall",), (8, 9), public=True, links=("kitchen", "theatre"), label="bar"),
            R("kitchen", 76, 0, (), links=("cold",), label="kitchen"),
            R("cold", 26, 0, (), label="cold"),
            R("theatre", 44, 0, (), label="theatre", need=30),
            R("hydro", 107, 0, ("hall",), (6, 8), label="hydro"),
            R("garden", 50, 0, ("hall",), public=True, label="garden", need=50),
            R("janitor", 24, 0, ("hall",), label="jani"),
        ], where="core"),
    ]


AI_SAT = [Rm("ai_core", 70, label="AI"), Rm("tcomms", 60, label="tcomms"), Rm("tc_control", 46, label="tc ctrl"),
          Rm("sat_foyer", 25, label="foyer"), Rm("sat_service", 17, label="service")]


def scale(crew):
    """Room size factor for a crew: 1.0 at REF_CREW."""
    # study: full stations ~130 floor tiles a crew slot, MiniStation (32) ~86: close to linear, a floor for rooms
    # steeper below the reference: halls, arms and docks are a fixed cost a small station still pays
    f = max(0.38, crew / float(REF_CREW))
    return f ** (0.95 if f >= 1 else 1.15)


def program(crew=80, seed=1, fill=FILL):
    """The departments for this crew: rooms dropped below their need, areas scaled, a little seeded jitter so two
    seeds' Medbays are not cut from the same cloth."""
    rnd = random.Random("program|%s|%s" % (crew, seed))
    s = scale(crew)
    # below the reference crew the smallest workable room shrinks too (an engine room for 40 is not 14x16)
    mf = min(1.0, max(0.7, s ** 0.5))
    out = []
    for d in departments():
        if crew < d.need:
            continue
        rooms = []
        for r in d.rooms:
            if crew < r.need:
                continue
            r.min = (max(3, int(round(r.min[0] * mf))), max(3, int(round(r.min[1] * mf))))
            # FILL: the solver grows rooms to fill their block, about a quarter past what they ask for
            r.area = max(r.min[0] * r.min[1], int(round(r.area * s * fill * rnd.uniform(0.88, 1.15))))
            rooms.append(r)
        names = {r.id for r in rooms}
        for r in rooms:
            r.links = tuple(k for k in r.links if k in names)
        d.rooms = rooms
        if d.lobby:
            d.lobby.area = max(12, int(d.lobby.area * s))
        out.append(d)
    return out
