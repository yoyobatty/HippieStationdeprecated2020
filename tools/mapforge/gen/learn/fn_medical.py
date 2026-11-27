"""Medical department function pass: the checkable rules of tools/mapforge/studies/dept_specs/medical.md and the fixes
a finished layout allows. Rooms are typed by what they hold, not their area name (an operating table makes a surgery:
Box and Hippie keep theirs in /area/medical/sleeper), so the rules hold on the stock maps as on ours.

    python tools/mapforge/gen/learn/fn_medical.py <in.dmm> [out.dmm] [--seed 1]   # check() before, fix, check() after
    from gen.learn import fn_medical
    fn_medical.check(m) -> [(x, y, "med.<rule>: text")]
    fn_medical.fix(m, seed=1, log=print) -> number of changes

Stock counts (8 maps of forge.corpus.MAPS: Hippie, Meta, Box, Delta, Pubby, Donut, Endo, MetaLake) are in each rule's
text. The fixes, in order: a missing operating room takes a room off the medbay walkway (its old use moves to a dead-end
room behind it, the morgue gets its maintenance door); the cryo bay (freezer, connectors, two cells: synth never copies
/obj/machinery/atmospherics); the chemistry smartfridge in the chemistry wall and its desk; NanoMed; morgue trays;
genetics' own door when its jobs can't get in (and the door through the security post walled up); the cloning machines
re-seated so each has a tile to stand on; virology's monkeys, its outer doors to virology access; the checkpoint's
locker and windows, the CMO's windows; patient lockers; seats where the public waits; door names that name another
room; the morgue's doors to morgue access. Every placement keeps a room's free floor in one piece, door fronts free
and every dense piece a free tile beside it. Run it after gen/learn/desks.py, before fixtures and gen/net.py.

The user 2026-11-26: "Think exactly what each department does ... we don't get patterns like chemistry tables opening
into walls / useless rooms that players can't get to."
"""
import argparse
import os
import random
import re
import sys
from collections import Counter, defaultdict, deque

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", ".."))
from forge import corpus as CO, dmm, function as FN  # noqa: E402

N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
DIRV = {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0)}
VDIR = {v: k for k, v in DIRV.items()}
OPP = {1: 2, 2: 1, 4: 8, 8: 4}
MED = ("/area/medical", "/area/crew_quarters/heads/cmo", "/area/security/checkpoint/medical")
UNDER = ("/obj/structure/cable", "/obj/machinery/atmospherics/pipe", "/obj/structure/disposalpipe")
# what a room keeps when its use changes: its wiring, air, power, alarms, lights, wall pieces, landmarks, bins
KEEP = ("/obj/structure/cable", "/obj/machinery/atmospherics/pipe", "/obj/machinery/atmospherics/components/unary/vent",
        "/obj/structure/disposalpipe", "/obj/machinery/disposal", "/obj/machinery/power/apc", "/obj/machinery/airalarm",
        "/obj/machinery/firealarm", "/obj/machinery/light", "/obj/structure/extinguisher_cabinet", "/obj/item/radio/intercom",
        "/obj/machinery/camera", "/obj/machinery/door", "/obj/effect", "/obj/machinery/newscaster", "/obj/structure/sign",
        "/obj/machinery/requests_console", "/obj/machinery/status_display", "/obj/machinery/holopad",
        "/obj/machinery/navbeacon", "/obj/machinery/power/terminal", "/obj/structure/lattice", "/mob/living/simple_animal")
# what may share a tile with a placed piece: wiring, pipes, vents, decals, landmarks (and wall-mounted pieces)
BARE_OK = ("/obj/structure/cable", "/obj/machinery/atmospherics/pipe", "/obj/machinery/atmospherics/components/unary/vent",
           "/obj/structure/disposalpipe", "/obj/effect/turf_decal", "/obj/effect/landmark", "/obj/machinery/navbeacon")

KIT = {
    "sleeper": ("/obj/machinery/sleeper",), "stasis": ("/obj/machinery/stasis",),
    "cryo": ("/obj/machinery/atmospherics/components/unary/cryo_cell",),
    "freezer": ("/obj/machinery/atmospherics/components/unary/thermomachine/freezer",),
    "medvend": ("/obj/machinery/vending/medical",), "medlocker": ("/obj/structure/closet/secure_closet/medical",),
    "cmo_locker": ("/obj/structure/closet/secure_closet/CMO",), "optable": ("/obj/structure/table/optable",),
    "op_computer": ("/obj/machinery/computer/operating",), "shower": ("/obj/machinery/shower",),
    "chem_dispenser": ("/obj/machinery/chem_dispenser",), "chem_master": ("/obj/machinery/chem_master",),
    "chem_heater": ("/obj/machinery/chem_heater",), "dna_scanner": ("/obj/machinery/dna_scannernew",),
    "dna_console": ("/obj/machinery/computer/scan_consolenew",), "monkey": ("/mob/living/carbon/monkey",),
    "monkey_cubes": ("/obj/item/storage/box/monkeycubes",), "clonepod": ("/obj/machinery/clonepod",),
    "clone_console": ("/obj/machinery/computer/cloning",), "morgue": ("/obj/structure/bodycontainer/morgue",),
    "pandemic": ("/obj/machinery/computer/pandemic",), "bio_closet": ("/obj/structure/closet/l3closet",),
    "crew_monitor": ("/obj/machinery/computer/crew",), "med_records": ("/obj/machinery/computer/med_data",),
    "keycard": ("/obj/machinery/keycard_auth",), "requests": ("/obj/machinery/requests_console",),
    "bed": ("/obj/structure/bed",), "iv_drip": ("/obj/machinery/iv_drip",), "chair": ("/obj/structure/chair",),
    "firstaid": ("/obj/item/storage/firstaid",), "glass_cab": ("/obj/structure/closet/secure_closet/personal/patient",),
    "wallmed": ("/obj/machinery/vending/wallmed",), "sec_locker": ("/obj/structure/closet/secure_closet/security",),
    "seccomp": ("/obj/machinery/computer/secure_data", "/obj/machinery/computer/security"),
    "roller": ("/obj/structure/bed/roller",),
}
WALKWAY = ("medhall", "lobby", "reception")
CHEM_SHOWER = 20    # walking tiles from the nearer chem dispenser to a shower (stock min 4-26: 7 of 8 within 20)
# job access (code/modules/jobs/job_types/*.dm `access`, code/__DEFINES/access.dm numbers)
JOBS = {
    "doctor": {5, 6, 45, 69, 33, 9, 68, 39, 301, 64},
    "chemist": {5, 6, 45, 33, 69, 39, 9, 68, 301, 64},
    "geneticist": {5, 6, 33, 9, 68, 301, 47, 55, 29, 64, 23},
    "virologist": {5, 6, 45, 33, 39, 301, 9, 68, 64},
    "cmo": {5, 6, 9, 68, 69, 19, 64, 33, 39, 40, 45, 48, 301, 62, 63, 12},
}
WORK_OF = {"surgery": "doctor", "treatment": "doctor", "cryo": "doctor", "storage": "doctor", "morgue": "doctor",
           "chemistry": "chemist", "genetics": "geneticist", "cloning": "geneticist", "viro_lab": "virologist",
           "cmo": "cmo"}
# door names and the room types they name (a "Chemistry Lab" door between the corridor and virology names neither side)
NAME_TYPES = (("chemistry", ("chemistry",)), ("morgue", ("morgue",)), ("storage", ("storage",)),
              ("cloning", ("cloning", "genetics")), ("genetics", ("genetics", "cloning", "genetics_other")),
              ("virology", ("viro_lab", "viro_airlock", "viro_cell", "viro_pen", "viro_other")),
              ("surgery", ("surgery", "surgery_obs", "surgery_prep")), ("operating", ("surgery", "surgery_obs")),
              ("cryo", ("cryo",)), ("security", ("checkpoint",)), ("chief medical", ("cmo",)),
              ("patient", ("patient_room", "treatment")), ("maintenance", ("MAINT",)))
# a room's door name, style and access by its type (stock door names: studies/dept_specs/medical.md, "Doors")
DOOR_OF = {
    "surgery": ("Operating Theatre", "/obj/machinery/door/airlock/medical", "45"),
    "morgue": ("Morgue", "/obj/machinery/door/airlock/medical", "6"),
    "cryo": ("Cryogenics", "/obj/machinery/door/airlock/medical/glass", "5"),
    "treatment": ("Treatment Center", "/obj/machinery/door/airlock/medical/glass", "5"),
    "storage": ("Medbay Storage", "/obj/machinery/door/airlock/medical/glass", "5"),
    "chemistry": ("Chemistry Lab", "/obj/machinery/door/airlock/medical/glass", "5; 33"),
    "genetics": ("Genetics Lab", "/obj/machinery/door/airlock/research", "9"),
    "cloning": ("Cloning Lab", "/obj/machinery/door/airlock/medical/glass", "5"),
    "viro_lab": ("Virology Exterior Airlock", "/obj/machinery/door/airlock/virology/glass", "39"),
    "viro_airlock": ("Virology Exterior Airlock", "/obj/machinery/door/airlock/virology", "39"),
    "cmo": ("Chief Medical Officer's Office", "/obj/machinery/door/airlock/command", "40"),
    "checkpoint": ("Medbay Security Post", "/obj/machinery/door/airlock/security/glass", "63"),
    "patient_room": ("Patient Room", "/obj/machinery/door/airlock/medical", "5"),
}
INNER_ORDER = ("viro_lab", "viro_airlock", "viro_pen", "viro_cell", "viro_other", "surgery", "cryo", "morgue", "cloning",
               "genetics", "chemistry", "storage", "cmo", "checkpoint", "patient_room", "treatment")
# a sink on its wall as the stock maps hang it (Meta, Box: dir toward the wall and a pixel shift)
SINK = {4: [("dir", "4"), ("pixel_x", "11")], 8: [("dir", "8"), ("pixel_x", "-12"), ("pixel_y", "2")], 1: [("pixel_y", "28")]}
SURGERY_TOOLS = ("/obj/item/scalpel", "/obj/item/hemostat", "/obj/item/retractor", "/obj/item/cautery",
                 "/obj/item/circular_saw", "/obj/item/surgicaldrill", "/obj/item/surgical_drapes", "/obj/item/razor",
                 "/obj/item/clothing/gloves/color/latex", "/obj/item/clothing/mask/surgical",
                 "/obj/item/clothing/suit/apron/surgical", "/obj/item/book/manual/wiki/surgery")


# ---------------------------------------------------------------------------------------------------- reading
def _is_med(a):
    return a is not None and a.startswith(MED) and not a.startswith("/area/medical/abandoned")


def _room_floor(t):
    """A tile of a room's floor: open, not space, not glass, not a doorway or a desk."""
    return t is not None and t.turf is not None and t.tpath.startswith("/turf/open") \
        and not t.tpath.startswith("/turf/open/space") and not CO.solid(t) and not t.has("/obj/machinery/door/airlock") \
        and not t.has("/obj/machinery/door/firedoor") \
        and not (t.has("/obj/machinery/door/window") and t.has("/obj/structure/table"))


def _dense(t):
    return any(FN.is_dense(o) for o in t.objs)


def _free(t):
    return _room_floor(t) and not _dense(t)


def _bare(t):
    """Free floor with nothing on it but wiring, pipes, vents, decals and wall-mounted pieces."""
    return _free(t) and all(o.path.startswith(BARE_OK) or CO.mounted(o) for o in t.objs)


def _wallish(t):
    return t is None or t.turf is None or t.tpath.startswith("/turf/closed") or CO.solid(t)


def _plain_wall(t):
    return t is not None and t.turf is not None and t.tpath.startswith("/turf/closed/wall") \
        and all(o.path.startswith(UNDER) for o in t.objs)


def _acc(o):
    def nums(k):
        v = (o.get(k) or "").strip('"')
        return {int(x) for x in re.split(r"[^0-9]+", v) if x and int(x)}
    return nums("req_access_txt"), nums("req_one_access_txt")


def _opens(o, acc):
    if acc is None:
        return True
    al, an = _acc(o)
    return al <= acc and (not an or bool(an & acc))


def _outside(a):
    if a is None:
        return "wall"
    for pre, lab in (("/area/hallway", "HALL"), ("/area/maintenance", "MAINT"), ("/area/space", "SPACE"),
                     ("/area/chapel", "CHAPEL")):
        if a.startswith(pre):
            return lab
    return "OUT:" + "/".join(a.split("/")[2:4])


def classify(area, tiles, kit):
    """A medical room piece's function type from its area and what it holds (studies/dept_specs/medical_work/study.py)."""
    k = kit.get
    if area.startswith("/area/crew_quarters/heads/cmo"):
        return "cmo"
    if area.startswith("/area/security/checkpoint"):
        return "checkpoint"
    if k("optable") and not area.startswith("/area/medical/morgue"):
        return "surgery"
    if k("cryo"):
        return "cryo"
    if k("chem_dispenser") or k("chem_master"):
        return "chemistry"
    if k("pandemic"):
        return "viro_lab"
    if k("dna_console"):
        return "genetics"
    if k("clonepod") or k("clone_console"):
        return "cloning"
    if (k("morgue") or 0) >= 3:
        return "morgue"
    if area.startswith("/area/medical/virology"):
        if (k("bio_closet") or 0) >= 2 or (k("shower") and k("bio_closet")):
            return "viro_airlock"
        if k("monkey"):
            return "viro_pen"
        if tiles <= 12 and (k("bed") or k("iv_drip")):
            return "viro_cell"
        return "viro_other"
    if k("sleeper") or k("stasis"):
        return "treatment"
    if (k("firstaid") or 0) >= 4 or ((k("medlocker") or 0) >= 2 and tiles <= 40):
        return "storage"
    if area.startswith("/area/medical/patients_rooms") or (tiles <= 15 and k("bed") and (k("glass_cab") or k("wallmed"))):
        return "patient_room"
    if area.startswith("/area/medical/morgue"):
        return "morgue"
    if area.startswith("/area/medical/cryo"):
        return "cryo"
    if area.startswith("/area/medical/surgery"):
        return "surgery_obs" if (k("bed") or k("iv_drip")) else "surgery_prep"
    if area.startswith("/area/medical/medbay/lobby"):
        return "lobby"
    if area.startswith(("/area/medical/medbay", "/area/medical/sleeper", "/area/medical/exam_room")):
        if (k("crew_monitor") or k("med_records")) and tiles <= 20:
            return "reception"
        return "medhall"
    if area.startswith("/area/medical/genetics"):
        return "genetics_other"
    if area.startswith("/area/medical/storage"):
        return "storage"
    if area.startswith("/area/medical/chemistry"):
        return "chemistry"
    return "other"


def _comps(ts):
    left, out = set(ts), []
    while left:
        s = left.pop()
        comp, q = {s}, [s]
        while q:
            p = q.pop()
            for dx, dy in N4:
                n = (p[0] + dx, p[1] + dy)
                if n in left:
                    left.discard(n)
                    comp.add(n)
                    q.append(n)
        out.append(comp)
    return out


class Dept:
    """The medical department of a map: room pieces typed by function, their doors, openings, desks and windows,
    and who reaches what from the halls."""

    def __init__(self, m):
        self.m = m
        by = defaultdict(set)
        for (x, y, z), t in m.tiles.items():
            if z == 1 and t.area is not None and _is_med(t.apath) and _room_floor(t):
                by[t.apath].add((x, y))
        self.pieces, self.pid = [], {}
        for area, ts in sorted(by.items()):
            for comp in sorted(_comps(ts), key=lambda c: min(c)):
                kit = Counter()
                for p in comp:
                    for o in m.get(*p).objs:
                        for k, pre in KIT.items():
                            if o.path.startswith(pre):
                                kit[k] += 1
                i = len(self.pieces)
                self.pieces.append(dict(i=i, area=area, tiles=comp, kit=kit, type=None))
                for p in comp:
                    self.pid[p] = i
        for P in self.pieces:
            P["type"] = classify(P["area"], len(P["tiles"]), P["kit"]) if len(P["tiles"]) >= 4 or sum(P["kit"].values()) \
                else "scrap"
        self._links()
        self._reach = {}
        pub = self.reach(set())
        for P in self.pieces:
            if P["type"] in WALKWAY and P["i"] in pub and any(s == ("X", "HALL") for s, _, _ in self.links[P["i"]]):
                P["type"] = "lobby"
        # a "lobby" by area that neither the hall nor a front hall reaches is a spare room (f22: behind the morgue)
        front = {P["i"] for P in self.pieces if any(s == ("X", "HALL") for s, _, _ in self.links[P["i"]])}
        for P in self.pieces:
            if P["type"] == "lobby" and P["i"] not in front and not any(
                    s[0] == "P" and s[1] in front and self.pieces[s[1]]["type"] in WALKWAY for s, _, _ in self.links[P["i"]]):
                P["type"] = "other"

    def side(self, p, step):
        for _ in range(4):
            if p in self.pid:
                return ("P", self.pid[p])
            t = self.m.get(*p)
            if t is None or t.turf is None:
                return ("X", "wall")
            if (t.has("/obj/machinery/door/airlock") or t.has("/obj/machinery/door/firedoor")) and step \
                    and not t.has("/obj/structure/table") and t.tpath.startswith("/turf/open"):
                p = (p[0] + step[0], p[1] + step[1])
                continue
            if not t.tpath.startswith("/turf/open") or CO.solid(t):
                return ("X", "wall")
            return ("X", _outside(t.apath))
        return ("X", "wall")

    def _links(self):
        m = self.m
        self.links = defaultdict(list)      # piece -> [(other side, kind, door tile)]
        self.doors = {}                     # door tile -> (atom, side a, side b)
        self.desks, self.wins = [], []
        for P in self.pieces:
            i = P["i"]
            for p in P["tiles"]:
                for dx, dy in N4:
                    w = (p[0] + dx, p[1] + dy)
                    tw = m.get(*w)
                    if tw is None or tw.turf is None or w in P["tiles"]:
                        continue
                    if tw.has("/obj/machinery/door/airlock"):
                        if w in self.doors:
                            continue
                        a, b = self.side((w[0] + dx, w[1] + dy), (dx, dy)), ("P", i)
                        if a[1] == "wall":
                            continue
                        o = tw.find("/obj/machinery/door/airlock")[0]
                        self.doors[w] = (o, b, a)
                        self.links[i].append((a, "door", w))
                        if a[0] == "P":
                            self.links[a[1]].append((b, "door", w))
                    elif tw.has("/obj/machinery/door/firedoor") and not tw.has("/obj/structure/table") \
                            and tw.tpath.startswith("/turf/open") and not CO.solid(tw):
                        a = self.side((w[0] + dx, w[1] + dy), (dx, dy))
                        if a[1] != "wall" and a != ("P", i) and not any(s == a and k == "open" for s, k, _ in self.links[i]):
                            self.links[i].append((a, "open", w))
                            if a[0] == "P":
                                self.links[a[1]].append((("P", i), "open", w))
                    elif tw.has("/obj/machinery/door/window") and tw.has("/obj/structure/table"):
                        a = self.side((w[0] + dx, w[1] + dy), None)
                        self.desks.append((w, ("P", i), a))
                    elif CO.solid(tw) and not tw.tpath.startswith("/turf/closed"):
                        a = self.side((w[0] + dx, w[1] + dy), None)
                        if a[1] != "wall" and a != ("P", i):
                            self.wins.append((w, ("P", i), a))
                    elif _room_floor(tw):
                        a = self.side(w, None)
                        if a[1] != "wall" and a != ("P", i) and not any(s == a and k == "open" for s, k, _ in self.links[i]):
                            self.links[i].append((a, "open", w))
                            if a[0] == "P":
                                self.links[a[1]].append((("P", i), "open", w))

    def name(self, s):
        return self.pieces[s[1]]["type"] if s[0] == "P" else s[1]

    def of(self, *types):
        return [P for P in self.pieces if P["type"] in types]

    def center(self, P):
        ts = P["tiles"]
        cx = sum(p[0] for p in ts) / float(len(ts))
        cy = sum(p[1] for p in ts) / float(len(ts))
        return min(ts, key=lambda p: ((p[0] - cx) ** 2 + (p[1] - cy) ** 2, p))

    def reach(self, acc):
        """Pieces reached from the halls through doors `acc` opens (None: any door), walking halls and medical only."""
        key = None if acc is None else frozenset(acc)
        if key in self._reach:
            return self._reach[key]
        m = self.m

        def ok(t):
            if t is None or t.turf is None or not t.tpath.startswith("/turf/open") or t.tpath.startswith("/turf/open/space") \
                    or CO.solid(t):
                return False
            if t.has("/obj/machinery/door/window") and t.has("/obj/structure/table"):
                return False
            for o in t.objs:
                if o.path.startswith(("/obj/machinery/door/airlock", "/obj/machinery/door/window")) and not _opens(o, acc):
                    return False
            return True
        start = [(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and t.area is not None
                 and t.apath.startswith("/area/hallway") and ok(t)]
        seen = set(start)
        q = deque(start)
        got = set()
        while q:
            p = q.popleft()
            for dx, dy in N4:
                n = (p[0] + dx, p[1] + dy)
                if n in seen:
                    continue
                tn = m.get(*n)
                if not ok(tn) or not (tn.apath.startswith(("/area/hallway", "/area/chapel", "/area/maintenance"))
                                      or _is_med(tn.apath) or tn.has("/obj/machinery/door/airlock")):
                    continue
                seen.add(n)
                q.append(n)
                if n in self.pid:
                    got.add(self.pid[n])
        self._reach[key] = got
        return got

    def fronts(self):
        """Tiles in front of every airlock (kept free)."""
        out = set()
        for (x, y, z), t in self.m.tiles.items():
            if z == 1 and (t.has("/obj/machinery/door/airlock") or t.has("/obj/machinery/door/firedoor")):
                for dx, dy in N4:
                    out.add((x + dx, y + dy))
        return out


# ---------------------------------------------------------------------------------------------------- the rules
def _walk_dist(m, start, goal_test, limit=60):
    q = deque([(start, 0)])
    seen = {start}
    while q:
        p, k = q.popleft()
        if goal_test(p):
            return k
        if k >= limit:
            continue
        for dx, dy in N4:
            n = (p[0] + dx, p[1] + dy)
            if n in seen:
                continue
            t = m.get(*n)
            if t is None or t.turf is None or not t.tpath.startswith("/turf/open") or CO.solid(t):
                if not goal_test(n):
                    continue
            seen.add(n)
            q.append((n, k + 1))
    return None


def _tiles_with(m, tiles, pre):
    return [p for p in tiles if any(o.path.startswith(pre) for o in m.get(*p).objs)]


def _stand(m, p, room=None):
    """A free tile beside p a person can stand on."""
    for dx, dy in N4:
        n = (p[0] + dx, p[1] + dy)
        t = m.get(*n)
        if (room is None or n in room) and _free(t):
            return n
    return None


def check(m, D=None):
    D = D or Dept(m)
    out = []
    if not D.pieces:
        return [(0, 0, "med.none: no medical department")]
    allm = set(D.pid)
    c0 = D.center(max(D.pieces, key=lambda P: len(P["tiles"])))

    def add(p, rule, txt):
        out.append((p[0], p[1], "med.%s: %s" % (rule, txt)))
    # surgery: table, computer beside it, tools within reach (stock 8/8; bot goals/surgery.dm wants tools in range 4)
    opt = [p for p in _tiles_with(m, allm, "/obj/structure/table/optable") if not m.get(*p).apath.startswith("/area/medical/morgue")]
    if not opt:
        add(c0, "surgery", "no operating table in medical (stock 8/8 have an operating room, 25 tiles)")
    for p in opt:
        if not any(m.get(p[0] + dx, p[1] + dy) and m.get(p[0] + dx, p[1] + dy).has("/obj/machinery/computer/operating")
                   for dx, dy in N4):
            add(p, "surgery", "no operating computer beside the operating table (8/8)")
        tools = sum(1 for q in allm if abs(q[0] - p[0]) <= 4 and abs(q[1] - p[1]) <= 4
                    for o in m.get(*q).objs if o.path.startswith(SURGERY_TOOLS[:4]))
        if tools < 4:
            add(p, "surgery", "scalpel, hemostat, retractor, cautery not all within 4 tiles of the table (8/8)")
    for P in D.of("surgery"):
        nb = {D.name(s) for s, _, _ in D.links[P["i"]]}
        if not nb & {"medhall", "lobby", "reception", "treatment", "surgery_obs", "surgery_prep", "patient_room", "HALL"}:
            add(D.center(P), "surgery_path", "the operating room is reached only through %s (stock: from the medbay "
                "walkway, observation, prep or the ward, 8/8)" % ", ".join(sorted(nb)))
    # cryo (8/8: 2 cells, a freezer)
    cells = _tiles_with(m, allm, "/obj/machinery/atmospherics/components/unary/cryo_cell")
    if len(cells) < 2:
        P = (D.of("cryo") or [None])[0]
        add(D.center(P) if P else c0, "cryo", "%d cryo cells (stock 8/8 have 2-3 and a freezer)" % len(cells))
    elif not _tiles_with(m, allm, "/obj/machinery/atmospherics/components/unary/thermomachine/freezer"):
        add(cells[0], "cryo", "cryo cells without a freezer (8/8)")
    if not D.of("treatment"):
        add(c0, "treatment", "no sleepers or stasis beds (stock 8/8)")
    # chemistry: machines (8/8), its smartfridge set in its wall (8/8), a desk onto the walkway or hall (8/8)
    chem = D.of("chemistry")
    if not chem:
        add(c0, "chemistry", "no chemistry lab (8/8)")
    if chem:
        k = Counter()
        for P in chem:
            k.update(P["kit"])
        if not k["chem_dispenser"] or not k["chem_master"] or not k["chem_heater"]:
            add(D.center(chem[0]), "chem_kit", "chemistry lacks a dispenser, ChemMaster or heater (8/8 have 2, 2, 2)")
    if chem:
        ring = {(p[0] + dx, p[1] + dy) for P in chem for p in P["tiles"] for dx, dy in N4} | {p for P in chem for p in P["tiles"]}
        if not any(o.path.startswith("/obj/machinery/smartfridge/chemistry") and "virology" not in o.path
                   for q in ring for o in m.get(*q).objs):
            add(D.center(chem[0]), "chem_fridge", "no medicine smartfridge in the chemistry wall (8/8)")
        if not any(D.name(a) in WALKWAY + ("HALL", "treatment", "storage") for P in chem for w, s, a in D.desks if s == ("P", P["i"])):
            add(D.center(chem[0]), "chem_desk", "no chemistry desk (table + windoor) onto the medbay walkway or "
                "the hall (8/8 onto the lobby/walkway, 3/8 also the hall)")
        disp = [p for P in chem for p in _tiles_with(m, P["tiles"], "/obj/machinery/chem_dispenser")]
        if disp:
            ds = [_walk_dist(m, q0, lambda q: m.get(*q) is not None and m.get(*q).has("/obj/machinery/shower"), 30)
                  for q0 in disp[:2]]
            d = min([x for x in ds if x is not None] or [None]) if any(x is not None for x in ds) else None
            if d is None or d > CHEM_SHOWER:
                add(disp[0], "chem_shower", "nearest emergency shower %s tiles from the dispensers (stock 4-26, "
                    "median 13, 7/8 within %d; Hippie and Endo keep one in chemistry)" % (d if d is not None else "30+", CHEM_SHOWER))
    # NanoMed (8/8)
    if not _tiles_with(m, allm, "/obj/machinery/vending/medical"):
        add(c0, "medvend", "no NanoMed Plus vendor in medical (8/8)")
    # morgue: 8-13 trays (8/8), a door to maintenance, the hall or the chapel (8/8), never public (0/8)
    morg = D.of("morgue")
    if not morg:
        add(c0, "morgue", "no morgue (8/8)")
    pub = D.reach(set())
    if morg:
        n = sum(P["kit"]["morgue"] or 0 for P in morg)
        big = max(morg, key=lambda P: (P["kit"]["morgue"] or 0, len(P["tiles"])))
        if n < 8:
            add(D.center(big), "morgue_trays", "%d morgue trays (stock 8-13)" % n)
        if not any(D.name(s) in ("MAINT", "HALL", "CHAPEL") for P in morg for s, _, _ in D.links[P["i"]]):
            add(D.center(big), "morgue_exit", "no door to maintenance or the hall: bodies leave through medbay "
                "(stock 8/8: maintenance 7, hall 6)")
        if any(P["i"] in pub for P in morg):
            add(D.center(big), "morgue_public", "the public walks into the morgue (stock 0/8: morgue access 6)")
    # rooms a walkway must serve: one of each such type has a door or opening onto a walkway or the hall
    for t in ("lobby", "chemistry", "storage", "checkpoint", "cmo", "morgue", "treatment"):
        ps = D.of(t)
        ok_ = WALKWAY + ("HALL", "treatment", "cryo") + (("CHAPEL",) if t == "morgue" else ())
        if ps and not any(D.name(s) in ok_ for P in ps for s, _, _ in D.links[P["i"]]):
            via = sorted({D.name(s) for P in ps for s, _, _ in D.links[P["i"]]})
            add(D.center(ps[0]), "through", "%s reached only through %s (stock: off the walkway 8/8)" % (t, ", ".join(via)))
    # each working room reached by its own job from the halls
    for t, job in WORK_OF.items():
        ps = D.of(t)
        if ps and not any(P["i"] in D.reach(JOBS[job]) for P in ps):
            add(D.center(ps[0]), "job_reach", "%s: the %s can't get in from the halls with their access" % (t, job))
    # cloning: pod, scanner and console beside each other (the console finds both by adjacency), each usable
    for P in D.of("cloning"):
        for pre in ("/obj/machinery/clonepod", "/obj/machinery/dna_scannernew", "/obj/machinery/computer/cloning"):
            for p in _tiles_with(m, P["tiles"], pre):
                if not _stand(m, p, P["tiles"]):
                    add(p, "clone_use", "%s has no free tile beside it to use it from" % pre.split("/")[-1])
        if len(P["tiles"]) < 16:
            add(D.center(P), "clone_size", "cloning room %d tiles (stock 16-39)" % len(P["tiles"]))
    gen, clo = D.of("genetics"), D.of("cloning")
    if gen and clo:
        joined = any(D.name(s) in ("genetics", "cloning") for P in gen + clo for s, _, _ in D.links[P["i"]]
                     if s[0] == "P" and s[1] != P["i"])
        dist = min(abs(a[0] - b[0]) + abs(a[1] - b[1]) for a in (D.center(P) for P in gen) for b in (D.center(P) for P in clo))
        if not joined and dist > 10:
            add(D.center(clo[0]), "clone_genetics", "cloning %d tiles from genetics, no door between (stock 7/8 "
                "a door, nb 1.0)" % dist)
    # virology: entered through its airlock room (8/8), outer doors need virology access (8/8), cells, monkeys
    vir = [P for P in D.pieces if P["type"].startswith("viro") or P["area"].startswith("/area/medical/virology")]
    if not D.of("viro_lab"):
        add(c0, "virology", "no virology lab (8/8)")
    vset = {P["i"] for P in vir}
    for w, (o, a, b) in D.doors.items():
        ins = [s for s in (a, b) if s[0] == "P" and s[1] in vset]
        outs = [s for s in (a, b) if not (s[0] == "P" and s[1] in vset)]
        if ins and outs:
            if 39 not in _acc(o)[0] | _acc(o)[1]:
                add(w, "viro_access", "door into virology from %s opens without virology access 39 (stock 8/8)"
                    % D.name(outs[0]))
            if D.name(ins[0]) not in ("viro_airlock",):
                add(w, "viro_airlock", "virology's %s opens straight onto %s: no airlock room with biosuits and a "
                    "shower between (stock 8/8)" % (D.name(ins[0]), D.name(outs[0])))
    if vir and len(D.of("viro_cell")) < 2:
        add(D.center(vir[0]), "viro_cells", "%d isolation cells (stock 8/8 2-4)" % len(D.of("viro_cell")))
    if vir and not any(P["kit"]["monkey"] for P in vir):
        add(D.center(vir[0]), "viro_monkeys", "no monkeys in virology (stock 7/8, 3-6 in a pen)")
    # CMO: one office with locker, keycard, records, requests console (8/8), windows onto medbay (8/8)
    cmo = D.of("cmo")
    if cmo:
        k = Counter()
        for P in cmo:
            k.update(P["kit"])
        for need in ("cmo_locker", "keycard", "med_records"):
            if not k[need]:
                add(D.center(cmo[0]), "cmo_kit", "CMO office has no %s (8/8)" % need)
        if len(cmo) > 1 and not any(s[0] == "P" and D.pieces[s[1]]["type"] == "cmo" for P in cmo for s, _, _ in D.links[P["i"]]):
            add(D.center(cmo[1]), "cmo_split", "the CMO's office is %d rooms with no door between (%s tiles)"
                % (len(cmo), "+".join(str(len(P["tiles"])) for P in cmo)))
        if not any(D.name(a) in WALKWAY + ("treatment", "cryo", "HALL") for w, s, a in D.wins
                   if s[0] == "P" and D.pieces[s[1]]["type"] == "cmo"):
            add(D.center(cmo[0]), "cmo_window", "the CMO's office has no window onto medbay (stock 8/8)")
    # checkpoint: locker and records/security console (8/8), windows onto the walkway or hall (8/8)
    for P in D.of("checkpoint"):
        if not P["kit"]["sec_locker"]:
            add(D.center(P), "checkpoint_kit", "medbay security post has no security locker (8/8)")
        if not any(D.name(a) in WALKWAY + ("HALL",) for w, s, a in D.wins + D.desks if s == ("P", P["i"])):
            add(D.center(P), "checkpoint_window", "medbay security post can't see the walkway or hall (8/8 windows)")
    for P in D.of("storage"):
        if not P["kit"]["medlocker"] and (P["kit"]["firstaid"] or 0) < 4:
            add(D.center(P), "storage_kit", "storage with no medicine locker and under 4 first-aid kits (8/8)")
    for P in D.of("patient_room"):
        if not P["kit"]["glass_cab"]:
            add(D.center(P), "patient_locker", "patient room without its patient locker (stock 9/10 rooms)")
    # the public front: a public room on the hall (8/8) with seats (stock lobbies and front halls 8/8)
    front = [P for P in D.pieces if P["i"] in pub and P["type"] in WALKWAY]
    if not front:
        add(c0, "lobby", "the public reaches no waiting room from the hall (8/8)")
    elif not any(P["kit"]["chair"] for P in front):
        add(D.center(front[0]), "lobby_seats", "no seats where the public waits (8/8)")
    for P in D.pieces:
        if P["i"] in pub and P["type"] in ("surgery", "storage", "chemistry", "cmo", "genetics", "cloning", "viro_lab",
                                           "viro_airlock", "viro_cell", "viro_pen", "other") and len(P["tiles"]) >= 6:
            add(D.center(P), "public", "the public walks into %s (stock: lobby, walkway, ward only)" % P["type"])
    # showers: an emergency shower on the walkway or in treatment (7/8)
    if not any(P["kit"]["shower"] for P in D.pieces if P["type"] in WALKWAY + ("treatment", "cryo", "chemistry")):
        add(c0, "shower", "no emergency shower in the medbay halls, treatment or chemistry (stock 7/8)")
    # doors named for a room on neither side
    for w, (o, a, b) in D.doors.items():
        nm = (o.get("name") or "").strip('"').lower()
        sides = {D.name(a), D.name(b)}
        if "access" in nm:
            continue
        areas = " ".join(D.pieces[x[1]]["area"] for x in (a, b) if x[0] == "P")
        keys = [(key, types) for key, types in NAME_TYPES if key in nm]
        if keys and not any(sides & set(types) or key in areas for key, types in keys):
            add(w, "door_name", '"%s" between %s' % (nm, " and ".join(sorted(sides))))
    return out


# ---------------------------------------------------------------------------------------------------- fixing helpers
def _hung(m):
    """wall tile -> [(floor tile, piece)] of mounted pieces hung on it."""
    out = defaultdict(list)
    for (x, y, z), t in m.tiles.items():
        if z != 1:
            continue
        for o in t.objs:
            v = None
            if o.path.startswith("/obj/machinery/light") and not o.path.startswith("/obj/machinery/light_switch"):
                v = DIRV.get(o.num("dir", 2) or 2)
            elif CO.mounted(o):
                v = DIRV.get(CO.mount_side(o))
            if v:
                out[(x + v[0], y + v[1])].append(((x, y), o))
    return out


PINNED = ("/obj/machinery/power/apc", "/obj/machinery/airalarm", "/obj/machinery/firealarm", "/obj/machinery/power/terminal")


def _rehang(m, w, hung, exclude=()):
    """Move what hangs on wall tile w to another bare wall face of the same room within 6 tiles (the same facing
    first; turned, its pixel shift or a light's dir follow); APCs and alarms stay. True if w is left bare."""
    moves, taken = [], set()
    for f, o in hung.get(w, []):
        if o.path.startswith(PINNED):
            return False
        v = (w[0] - f[0], w[1] - f[1])
        area = m.get(*f).apath
        best = None
        for dx in range(-6, 7):
            for dy in range(-6, 7):
                q = (f[0] + dx, f[1] + dy)
                tq = m.get(*q)
                if abs(dx) + abs(dy) > 6 or tq is None or tq.area is None or tq.apath != area or not _room_floor(tq):
                    continue
                for d, u in DIRV.items():
                    wq = (q[0] + u[0], q[1] + u[1])
                    if wq == w or wq in hung or wq in taken or wq in exclude or not _plain_wall(m.get(*wq)):
                        continue
                    key = (u != v, abs(dx) + abs(dy), q, d)
                    if best is None or key < best[0]:
                        best = (key, q, wq, d)
        if best is None:
            return False
        moves.append((f, o, best[1], best[2], best[3]))
        taken.add(best[2])
    for f, o, q, wq, d in moves:
        m.get(*f).objs = [x for x in m.get(*f).objs if x is not o]
        if o.path.startswith("/obj/machinery/light"):
            o.vars = [(k, v_) for k, v_ in o.vars if k != "dir"] + ([("dir", str(d))] if d != 2 else [])
        else:
            mag = max(abs(o.num("pixel_x")), abs(o.num("pixel_y"))) or 30
            u = DIRV[d]
            o.vars = [(k, v_) for k, v_ in o.vars if k not in ("pixel_x", "pixel_y")] + \
                [(k, str(mag * c)) for k, c in (("pixel_x", u[0]), ("pixel_y", u[1])) if c]
        m.get(*q).objs.append(o)
        hung[wq].append((q, o))
    hung.pop(w, None)
    return True


_BASE = {}      # (map, room) -> its state before fn_medical placed anything in it


def _state(m, room):
    """(free tiles cut off from the room's doors, dense pieces with no reached free tile beside them)."""
    free = {p for p in room if _free(m.get(*p))}
    comps = _comps(free)

    def doorway(q):
        t = m.get(*q)
        return t is not None and (t.has("/obj/machinery/door/airlock") or t.has("/obj/machinery/door/firedoor"))
    at_door = [c for c in comps if any(doorway((p[0] + dx, p[1] + dy)) for p in c for dx, dy in N4)]
    main = set().union(*at_door) if at_door else (max(comps, key=len) if comps else set())
    boxed = {p for p in room if p not in free and any(FN.is_dense(o) for o in m.get(*p).objs)
             and not any((p[0] + dx, p[1] + dy) in main for dx, dy in N4)}
    return len(free - main), boxed, bool(main)


def _base(m, room):
    key = (id(m), frozenset(room))
    if key not in _BASE:
        _BASE[key] = _state(m, room)
    return _BASE[key]


def _ok(m, room, keep_free=()):
    """The room works no worse than before fn_medical touched it: no free floor newly cut off from its doors, no dense
    piece newly boxed in, every door front and kept tile free (_base(m, room) must be taken before the change)."""
    for p in keep_free:
        if p in room and not _free(m.get(*p)):
            return False
    b = _BASE.get((id(m), frozenset(room)), (0, set(), True))
    stranded, boxed, has = _state(m, room)
    return has and stranded <= b[0] and boxed <= b[1]


def _walls(m, p):
    return [d for d, v in DIRV.items() if _wallish(m.get(p[0] + v[0], p[1] + v[1]))]


def _place(m, room, fronts, objs, want=None, prefer=None, keep_free=(), dir_from_wall=None, avoid=()):
    """Put objs (atoms; a dense piece first) on a free tile of the room that isn't a door front; want(p) filters,
    prefer(p) sorts (low first). dir_from_wall: set the first atom's dir to face away from (1) or toward (-1) its wall.
    Returns the tile or None. Never breaks the room (see _ok)."""
    _base(m, room)
    cands = [p for p in room if _bare(m.get(*p)) and p not in fronts and p not in avoid and (want is None or want(p))]
    cands.sort(key=lambda p: (prefer(p) if prefer else 0, p))
    for p in cands:
        t = m.get(*p)
        new = [o.copy() for o in objs]
        if dir_from_wall is not None:
            ws = _walls(m, p)
            if not ws:
                continue
            d = ws[0] if dir_from_wall < 0 else OPP[ws[0]]
            new[0].vars = [(k, v) for k, v in new[0].vars if k != "dir"] + ([("dir", str(d))] if d != 2 else [])
        t.objs.extend(new)
        if _ok(m, room, set(keep_free) | (fronts & room)):
            return p
        for o in new:
            t.objs.remove(o)
    return None


def _clear(m, room):
    """Take out a room's furniture, machines, items and mobs (its wiring, air, alarms, lights and wall pieces stay)."""
    gone = []
    for p in room:
        t = m.get(*p)
        keep = [o for o in t.objs if o.path.startswith(KEEP) or CO.mounted(o)]
        gone += [o for o in t.objs if o not in keep]
        t.objs = keep
    return gone


# a retyped room's floor (gen/learn/deptdb turf: the floor most human rooms of the type have)
TURF_OF = {"/area/medical/surgery": "/turf/open/floor/plasteel/white", "/area/medical/morgue": "/turf/open/floor/plasteel/dark"}


def _retype(m, room, area):
    for p in room:
        t = m.get(*p)
        t.area = dmm.Atom(area)
        if area in TURF_OF and t.tpath.startswith("/turf/open/floor/plasteel"):
            t.turf = dmm.Atom(TURF_OF[area])


def _set_door(o, name=None, path=None, acc=None):
    if path:
        o.path = path
    if name is not None:
        o.vars = [(k, v) for k, v in o.vars if k != "name"] + [("name", '"%s"' % name)]
    if acc is not None:
        o.vars = [(k, v) for k, v in o.vars if k not in ("req_access_txt", "req_one_access_txt")]
        if acc:
            o.vars.append(("req_access_txt", '"%s"' % acc))


def _cut_door(m, inner, outer, path, name, acc, area):
    """A door through the one wall tile between floor tiles inner and outer (in line). Returns the tile or None."""
    w = ((inner[0] + outer[0]) // 2, (inner[1] + outer[1]) // 2)
    tw = m.get(*w)
    if not _plain_wall(tw):
        return None
    along = (abs(outer[1] - inner[1]) // 2, abs(outer[0] - inner[0]) // 2)
    if not all(_wallish(m.get(w[0] + s * along[0], w[1] + s * along[1])) for s in (1, -1)):
        return None
    tin = m.get(*inner)
    tw.turf = dmm.Atom(tin.tpath if tin.tpath.startswith("/turf/open/floor") else "/turf/open/floor/plasteel")
    tw.area = dmm.Atom(area)
    vs = [("name", '"%s"' % name)] + ([("req_access_txt", '"%s"' % acc)] if acc else [])
    tw.objs = [o for o in tw.objs if o.path.startswith(UNDER)] + [dmm.Atom(path, vs)]
    return w


def _glass(t):
    """A window tile (grille and glass on an open turf)."""
    return t is not None and t.turf is not None and t.tpath.startswith("/turf/open") and CO.solid(t)         and not t.has("/obj/machinery/door")


def _wall_runs(m, D, P, want_types, hung, allow_hung=False, by_door=False, glass=False):
    """Wall tiles between piece P and a place of want_types (in line: P floor, wall, their floor), none hung (or, with
    allow_hung, none holding an APC or alarm); with glass, window tiles too."""
    out = []
    for p in sorted(P["tiles"]):
        for dx, dy in N4:
            w = (p[0] + dx, p[1] + dy)
            q = (w[0] + dx, w[1] + dy)
            tw, tq = m.get(*w), m.get(*q)
            if not (_plain_wall(tw) or (glass and _glass(tw))) or not _room_floor(tq):
                continue
            if w in hung and (not allow_hung or any(o.path.startswith(PINNED) for _, o in hung[w])):
                continue
            s = D.side(q, None)
            if D.name(s) not in want_types or s == ("P", P["i"]):
                continue
            along = (dy, dx)
            if not all(_wallish(m.get(w[0] + k * along[0], w[1] + k * along[1])) or
                       (by_door and m.get(w[0] + k * along[0], w[1] + k * along[1]).has("/obj/machinery/door"))
                       for k in (1, -1)):
                continue
            out.append((w, (dx, dy), p, q))
    return out


def _glaze(m, D, P, want_types, hung, n=2, log=print, what=""):
    """Up to n wall tiles between P and a want_types place become reinforced windows (in a run)."""
    allr = _wall_runs(m, D, P, want_types, hung, allow_hung=True, by_door=True)
    if not allr:
        return 0
    rank = {t: i for i, t in enumerate(want_types)}
    done = []
    for level in sorted({rank.get(D.name(D.side(r[3], None)), 99) for r in allr}):
        if done:
            break
        runs = [r for r in allr if rank.get(D.name(D.side(r[3], None)), 99) == level]
        cx = sum(r[0][0] for r in runs) / float(len(runs))
        cy = sum(r[0][1] for r in runs) / float(len(runs))
        runs.sort(key=lambda r: (r[0] in hung, abs(r[0][0] - cx) + abs(r[0][1] - cy), r[0]))
        _glaze_run(m, runs, hung, n, done)
    if done:
        log("  fn_medical: %s windows %s" % (what, " ".join("%d,%d" % w for w in done)))
    return len(done)


def _glaze_run(m, runs, hung, n, done):
    for w, step, p, q in runs:
        if len(done) >= n:
            break
        if done and not any(abs(w[0] - d[0]) + abs(w[1] - d[1]) == 1 for d in done):
            continue
        if w in hung and not _rehang(m, w, hung, exclude={r[0] for r in runs}):
            continue
        tw = m.get(*w)
        tw.turf = dmm.Atom("/turf/open/floor/plating")
        tw.objs = [o for o in tw.objs if o.path.startswith("/obj/structure/cable")] + \
            [dmm.Atom("/obj/effect/spawner/structure/window/reinforced")]
        done.append(w)


# ---------------------------------------------------------------------------------------------------- the fixes
def _furnish_surgery(m, room, fronts, r):
    """Meta/Box's operating room: the table in the middle, its computer beside it facing it, tool tables on the walls
    within 3 tiles, the anesthetic closet and the blood freezer in corners, a sink on a wall."""
    _base(m, room)
    cx = sum(p[0] for p in room) / float(len(room))
    cy = sum(p[1] for p in room) / float(len(room))
    inner = [p for p in room if not _walls(m, p) and p not in fronts]
    table = _place(m, room, fronts, [dmm.Atom("/obj/structure/table/optable")],
                   want=lambda p: p in inner and sum(1 for dx, dy in N4 if _free(m.get(p[0] + dx, p[1] + dy))) >= 3,
                   prefer=lambda p: (p[0] - cx) ** 2 + (p[1] - cy) ** 2)
    if table is None:
        return None
    comp = None
    for d in sorted(DIRV, key=lambda d: (d != 2, d)):
        v = DIRV[d]
        c = (table[0] + v[0], table[1] + v[1])
        if c in room and _free(m.get(*c)) and c not in fronts:
            face = OPP[d]
            vs = [("dir", str(face))] if face != 2 else []
            o = dmm.Atom("/obj/machinery/computer/operating", vs)
            m.get(*c).objs.append(o)
            if _ok(m, room, fronts & room):
                comp = c
                break
            m.get(*c).objs.remove(o)
    if comp is None:
        m.get(*table).objs = [o for o in m.get(*table).objs if not o.path.startswith("/obj/structure/table/optable")]
        return None
    first = None
    for put in (SURGERY_TOOLS[:8], SURGERY_TOOLS[8:]):
        p = _place(m, room, fronts, [dmm.Atom("/obj/structure/table")] + [dmm.Atom(x) for x in put],
                   want=lambda p: _walls(m, p) and max(abs(p[0] - table[0]), abs(p[1] - table[1])) <= 3,
                   prefer=lambda p: abs(p[0] - table[0]) + abs(p[1] - table[1]))
        if p is None:
            p = _place(m, room, fronts, [dmm.Atom("/obj/structure/table")] + [dmm.Atom(x) for x in put],
                       want=lambda p: max(abs(p[0] - table[0]), abs(p[1] - table[1])) <= 3)
        if p is None:
            # no table spot left: on the first tool table, else on the floor by the operating table
            q = first or _stand(m, table, room)
            if q:
                m.get(*q).objs.extend(dmm.Atom(x) for x in put)
        first = first or p
    corner = lambda p: len(_walls(m, p)) >= 2  # noqa: E731
    _place(m, room, fronts, [dmm.Atom("/obj/structure/closet/secure_closet/medical2")], want=corner)
    _place(m, room, fronts, [dmm.Atom("/obj/structure/closet/crate/freezer/blood")], want=corner)
    _put_sink(m, room, fronts)
    return table


def _put_sink(m, room, fronts):
    """A sink on a wall of the room, hung as the stock maps hang it (SINK). Returns its tile or None."""
    _base(m, room)
    for p in sorted(room, key=lambda p: (-len(_walls(m, p)), p)):
        ws = [d for d in _walls(m, p) if d in SINK]
        if ws and _bare(m.get(*p)) and p not in fronts:
            m.get(*p).objs.append(dmm.Atom("/obj/structure/sink", SINK[ws[0]]))
            if _ok(m, room, fronts & room):
                return p
            m.get(*p).objs.pop()
    return None


def _furnish_morgue(m, room, fronts, want_n=8):
    """Morgue trays on the walls, each facing out with its front tile kept free (the tray slides out onto it)."""
    _base(m, room)
    keep = set()
    n = 0
    for _ in range(want_n + 4):
        if n >= want_n:
            break
        best = None
        for p in sorted(room):
            t = m.get(*p)
            if not _free(t) or p in fronts or p in keep:
                continue
            for d in _walls(m, p):
                out = OPP[d]
                f = (p[0] + DIRV[out][0], p[1] + DIRV[out][1])
                if f not in room or not _free(m.get(*f)) or f in keep:
                    continue
                best = (p, out, f)
                break
            if best:
                o = dmm.Atom("/obj/structure/bodycontainer/morgue", [("dir", str(best[1]))] if best[1] != 4 else [])
                t.objs.append(o)
                if _ok(m, room, keep | {best[2]} | (fronts & room)):
                    keep.add(best[2])
                    n += 1
                    break
                t.objs.remove(o)
                best = None
        if best is None:
            break
    return n


def fix_surgery(m, D, r, log):
    """No operating room: one takes a room off the medbay walkway, 16-40 tiles. A spare room (a second storage or CMO
    piece, a lobby no hall reaches) is taken as it is; a morgue or storage there moves into a dead-end room behind it
    (reached only through it, or a misplaced lobby), the morgue then given its maintenance door."""
    opt = [p for p in _tiles_with(m, set(D.pid), "/obj/structure/table/optable")
           if not m.get(*p).apath.startswith("/area/medical/morgue")]
    if opt:
        # the bot surgeon wants scalpel, hemostat, retractor and cautery within 4 tiles of the table (goals/surgery.dm)
        n = 0
        for p in opt:
            near = sum(1 for q in D.pid if abs(q[0] - p[0]) <= 4 and abs(q[1] - p[1]) <= 4
                       for o in m.get(*q).objs if o.path.startswith(SURGERY_TOOLS[:4]))
            if near >= 4:
                continue
            room = D.pieces[D.pid[p]]["tiles"]
            q = _place(m, room, D.fronts(), [dmm.Atom("/obj/structure/table")] + [dmm.Atom(x) for x in SURGERY_TOOLS[:4]],
                       want=lambda x: bool(_walls(m, x)) and max(abs(x[0] - p[0]), abs(x[1] - p[1])) <= 3,
                       prefer=lambda x: abs(x[0] - p[0]) + abs(x[1] - p[1]))
            if q:
                log("  fn_medical: surgery tool table at %d,%d by the operating table" % q)
                n += 1
        return n
    pub = D.reach(set())
    count = Counter(P["type"] for P in D.pieces)

    def on_walk(P):
        return any(D.name(s) in WALKWAY + ("HALL",) and k == "door" for s, k, _ in D.links[P["i"]])

    def spare(P):
        t = P["type"]
        return (t in ("storage", "cmo", "treatment", "reception") and count[t] > 1) or \
            (t == "lobby" and P["i"] not in pub) or t == "other"
    cands = []
    for P in D.pieces:
        if not (16 <= len(P["tiles"]) <= 40) or not on_walk(P):
            continue
        if spare(P):
            cands.append((0, abs(len(P["tiles"]) - 25), P, None))
        elif P["type"] in ("morgue", "storage", "lobby"):
            # a home for its use behind it: a room whose only doors lead into P (or a spare room)
            for s, k, w in D.links[P["i"]]:
                if s[0] != "P":
                    continue
                H = D.pieces[s[1]]
                others = [x for x, _, _ in D.links[H["i"]] if x != ("P", P["i"])]
                if len(H["tiles"]) >= 12 and (spare(H) or not any(D.name(x) in WALKWAY + ("HALL",) for x in others)) \
                        and H["type"] not in ("surgery", "chemistry", "genetics", "cloning", "cryo", "viro_lab", "cmo",
                                              "checkpoint", "treatment"):
                    cands.append((1, abs(len(P["tiles"]) - 25), P, H))
    if not cands:
        log("  fn_medical: no operating room and no room off the walkway to make one in")
        return 0
    cands.sort(key=lambda c: (c[0], c[1], min(c[2]["tiles"])))
    _, _, P, H = cands[0]
    fronts = D.fronts()
    old = P["type"]
    if H is not None:
        _clear(m, H["tiles"])
        _retype(m, H["tiles"], P["area"])
        if old == "morgue":
            n = _furnish_morgue(m, H["tiles"], fronts, 10)
            things = [o for p in P["tiles"] for o in m.get(*p).objs if o.path.startswith(
                ("/obj/item/storage/box/bodybags", "/obj/item/bodybag", "/obj/item/clothing/under/burial",
                 "/obj/item/reagent_containers/food/snacks/grown/poppy")) and not CO.mounted(o)]
            things = things or [dmm.Atom("/obj/item/storage/box/bodybags")]
            if not _place(m, H["tiles"], fronts, [dmm.Atom("/obj/structure/table")] + things,
                          want=lambda p: len(_walls(m, p)) >= 1):
                q = next((q for q in sorted(H["tiles"]) if _bare(m.get(*q)) and q not in fronts), None)
                if q:
                    m.get(*q).objs.extend(things)
            log("  fn_medical: morgue moved to %s (was %s, %d tiles): %d trays" % ("%d,%d" % min(H["tiles"]), H["type"],
                                                                                 len(H["tiles"]), n))
        else:
            moved = [o for o in _clear(m, P["tiles"]) if FN.is_dense(o) or o.path.startswith("/obj/item")]
            for o in moved:
                if FN.is_dense(o):
                    _place(m, H["tiles"], fronts, [o], want=lambda p: len(_walls(m, p)) >= 1)
                else:
                    _place(m, H["tiles"], fronts, [o])
            log("  fn_medical: %s moved to the room behind it at %d,%d" % (old, *min(H["tiles"])))
    _clear(m, P["tiles"])
    _retype(m, P["tiles"], "/area/medical/surgery")
    table = _furnish_surgery(m, P["tiles"], fronts, r)
    log("  fn_medical: operating room in the %s at %d,%d (%d tiles), table %s" % (
        old, *min(P["tiles"]), len(P["tiles"]), table))
    D2 = Dept(m)
    # its doors: the theatre's, the morgue's (and the morgue out to maintenance)
    for w, (o, a, b) in D2.doors.items():
        names = {D2.name(a), D2.name(b)}
        if "surgery" in names and names & set(WALKWAY):
            _set_door(o, "Operating Theatre", "/obj/machinery/door/airlock/medical", "45")
        elif "surgery" in names and "morgue" in names:
            _set_door(o, "Morgue", "/obj/machinery/door/airlock/medical", "6")
    if old == "morgue":
        fix_morgue_exit(m, D2, log)
    return 1


def fix_morgue_exit(m, D, log):
    n = 0
    hung = _hung(m)
    for P in D.of("morgue"):
        if any(D.name(s) in ("MAINT", "HALL", "CHAPEL") for s, _, _ in D.links[P["i"]]):
            continue
        for want, path, name in (("MAINT", "/obj/machinery/door/airlock/maintenance", "Morgue Maintenance"),
                                 ("HALL", "/obj/machinery/door/airlock/grunge", "Morgue")):
            runs = []
            for p in sorted(P["tiles"]):
                for dx, dy in N4:
                    w, q = (p[0] + dx, p[1] + dy), (p[0] + 2 * dx, p[1] + 2 * dy)
                    tq = m.get(*q)
                    if w in hung or not _free(tq) or _outside(tq.apath) != want or not _free(m.get(*p)):
                        continue
                    runs.append((p, q))
            fronts = D.fronts()
            for p, q in runs:
                if p in fronts or q in fronts:
                    continue
                w = _cut_door(m, p, q, path, name, "6", P["area"])
                if w:
                    log("  fn_medical: morgue door to %s at %d,%d" % (want.lower(), *w))
                    n += 1
                    break
            if n:
                break
    return n


def _cryo_block(m, room, fronts):
    """Where the cryo bay fits (forge/function.py CRYO: Meta's bay, from the wall out), or None."""
    best = None
    for wall in DIRV:
        up = OPP[wall]
        for side in (1, -1):
            lr = [d for d in DIRV if d not in (wall, up)]
            right = lr[0] if side == 1 else lr[1]
            left = OPP[right]
            rel = {"U": up, "D": wall, "L": left, "R": right}
            for c0 in sorted(room):
                tiles = {}
                for col in range(3):
                    for row in range(4):
                        tiles[(col, row)] = (c0[0] + DIRV[right][0] * col + DIRV[up][0] * row,
                                             c0[1] + DIRV[right][1] * col + DIRV[up][1] * row)
                if not all(p in room for p in tiles.values()):
                    continue
                if not all(_wallish(m.get(tiles[(c, 0)][0] + DIRV[wall][0], tiles[(c, 0)][1] + DIRV[wall][1])) for c in range(3)):
                    continue
                front = [(tiles[(c, 3)][0] + DIRV[up][0], tiles[(c, 3)][1] + DIRV[up][1]) for c in (1, 2)]
                if not all(q in room and _room_floor(m.get(*q)) for q in front):
                    continue
                if any(p in fronts for p in tiles.values()):
                    continue
                # pipes of the station on the cryo loop's layer (the default one) would join it
                if any(o.path.startswith("/obj/machinery/atmospherics") and "/layer" not in o.path
                       for p in tiles.values() for o in m.get(*p).objs):
                    continue
                lost = sum(1 for p in tiles.values() for o in m.get(*p).objs if FN.is_dense(o))
                score = lost * 3 + (0 if _wallish(m.get(tiles[(0, 0)][0] + DIRV[left][0], tiles[(0, 0)][1] + DIRV[left][1])) else 1)
                if best is None or score < best[0]:
                    best = (score, tiles, rel, front)
    return best


def fix_cryo(m, D, log):
    """The cryo bay (two cells, freezer, oxygen on connectors, the loop between) in the cryo room, else treatment."""
    allm = set(D.pid)
    if len(_tiles_with(m, allm, "/obj/machinery/atmospherics/components/unary/cryo_cell")) >= 2:
        return 0
    rooms = sorted(D.of("cryo"), key=lambda P: -len(P["tiles"])) + sorted(D.of("treatment"), key=lambda P: -len(P["tiles"]))
    fronts = D.fronts()
    for P in rooms:
        room = P["tiles"]
        b = _cryo_block(m, room, fronts)
        if b is None:
            continue
        _, tiles, rel, front = b
        _base(m, room)
        snap = {p: list(m.get(*p).objs) for p in room}
        lost, units = [], []
        # every movable piece of the room comes up (a table by the door cut Meta's bay off in f21c); the room's loose
        # canisters go (the bay brings its own two on the connectors); the rest goes back once the bay is in
        for p in sorted(room):
            t = m.get(*p)
            mov = [o for o in t.objs if not CO.mounted(o) and not o.path.startswith(KEEP) and (
                FN.is_dense(o) or (p in tiles.values() or p in front) and o.path.startswith(("/obj/item", "/obj/structure/chair")))]
            if not mov:
                continue
            items = [o for o in t.objs if o.path.startswith("/obj/item") and not CO.mounted(o) and o not in mov]
            t.objs = [o for o in t.objs if o not in mov and o not in items]
            dense = [o for o in mov if FN.is_dense(o) and not o.path.startswith("/obj/machinery/portable_atmospherics")]
            lost += mov + items
            units.append((dense, [o for o in mov if not FN.is_dense(o)] + items))
        for k, p in tiles.items():
            for kind, spec in FN.CRYO.get(k, []):
                vs = []
                if kind in ("freezer", "connector", "cell", "manifold"):
                    d = rel[spec]
                    vs = [("dir", str(d))] if d != 2 else []
                elif kind == "simple":
                    mask = rel[spec[0]] | rel[spec[1]]
                    vs = [("dir", str(mask))] if mask != 3 else []
                    if mask == 12:
                        vs = [("dir", "4")]
                if kind == "connector":
                    vs.append(("name", '"Connector Port (Air Supply)"'))
                m.get(*p).objs.append(dmm.Atom(FN.CRYO_PATHS[kind], vs))
        if not _ok(m, room, set(front) | (fronts & room)):
            for p, objs in snap.items():
                m.get(*p).objs = objs
            continue
        # what stood there goes back where it leaves the bay reached (a table with its beakers on a wall), else its
        # loose things on the floor outside the bay
        for dense, loose in units:
            if not dense and not loose:
                continue
            p = None
            if dense:
                p = _place(m, room, fronts, dense + loose, want=lambda p: bool(_walls(m, p)), keep_free=front,
                           avoid=set(tiles.values()))
            if p is None and loose:
                q = next((q for q in sorted(room) if _bare(m.get(*q)) and q not in fronts and q not in tiles.values()),
                         None) or next((q for q in sorted(room) if _bare(m.get(*q))), None)
                if q:
                    m.get(*q).objs.extend(o for o in loose if o.path.startswith("/obj/item"))
        log("  fn_medical: cryo bay in %s at %d,%d (freezer %d,%d), %d pieces moved out" % (
            P["area"].split("/")[-1], *min(room), *tiles[(0, 0)], len(lost)))
        return 1
    log("  fn_medical: no room fits a cryo bay")
    return 0


def fix_chemistry(m, D, log):
    n = 0
    chem = D.of("chemistry")
    if not chem:
        return 0
    P = max(chem, key=lambda P: len(P["tiles"]))
    hung = _hung(m)
    ring = {(p[0] + dx, p[1] + dy) for p in P["tiles"] for dx, dy in N4} | set(P["tiles"])
    desk_tiles = {w for w, s, a in D.desks}
    near_door = lambda w: any((w[0] + dx, w[1] + dy) in D.doors or (w[0] + dx, w[1] + dy) in desk_tiles  # noqa: E731
                              for dx in (-1, 0, 1) for dy in (-1, 0, 1))
    pub = WALKWAY + ("HALL", "treatment")
    # its desk (8/8): the windoor on the served side (8 of 11 stock desk tiles), access 33
    if not any(D.name(a) in pub + ("storage",) for w, s, a in D.desks if s == ("P", P["i"])):
        fronts = D.fronts()

        def movable(p):
            """The chemist's side of a desk: free, or one piece (a table with its things, a heater) that can move to
            another wall spot of the room."""
            t = m.get(*p)
            if _free(t):
                return True
            dense = [o for o in t.objs if FN.is_dense(o)]
            return len(dense) == 1 and not dense[0].path.startswith(KEEP) and not CO.mounted(dense[0])
        runs = [r for r in _wall_runs(m, D, P, pub, hung, allow_hung=True, by_door=True, glass=True)
                if not near_door(r[0]) and movable(r[2]) and _free(m.get(*r[3])) and r[2] not in fronts and r[3] not in fronts]
        # a wall first, a window of the room (stock desks stand in its glass front) next, the hall side last
        runs.sort(key=lambda r: (D.name(D.side(r[3], None)) == "HALL", not _free(m.get(*r[2])), _glass(m.get(*r[0])),
                                 r[0] in hung, r[0]))
        made = []
        for w, step, p, q in runs:
            if len(made) >= 2:
                break
            if made and not any(abs(w[0] - d[0]) + abs(w[1] - d[1]) == 1 for d in made):
                continue
            if w in hung and not _rehang(m, w, hung, exclude={r[0] for r in runs}):
                continue
            if not _free(m.get(*p)):
                t = m.get(*p)
                moving = [o for o in t.objs if not CO.mounted(o) and not o.path.startswith(KEEP)
                          and (FN.is_dense(o) or o.path.startswith(("/obj/item", "/obj/structure")))]
                t.objs = [o for o in t.objs if o not in moving]
                tab = [o for o in moving if FN.is_dense(o)]
                if not _place(m, P["tiles"], fronts, tab + [o for o in moving if o not in tab],
                              want=lambda x: bool(_walls(m, x)), avoid={r[2] for r in runs}):
                    t.objs.extend(moving)
                    continue
            out = VDIR[step]
            tw = m.get(*w)
            tw.turf = dmm.Atom(m.get(*p).tpath)
            tw.area = dmm.Atom(P["area"])
            names = {1: "north", 2: "south", 4: "east", 8: "west"}
            tw.objs = [o for o in tw.objs if o.path.startswith(UNDER)] + [
                dmm.Atom("/obj/structure/table/reinforced"), dmm.Atom("/obj/machinery/door/firedoor"),
                dmm.Atom("/obj/machinery/door/window/%sright" % names[out], [("name", '"Chemistry Desk"'),
                                                                            ("req_access_txt", '"33"')]),
                dmm.Atom("/obj/machinery/door/poddoor/shutters/preopen", [("name", '"chemistry shutters"')])]
            made.append(w)
        if made:
            log("  fn_medical: chemistry desk %s" % " ".join("%d,%d" % w for w in made))
            n += 1
            D = Dept(m)
            P = max(D.of("chemistry"), key=lambda P: len(P["tiles"]))
            desk_tiles = {w for w, s, a in D.desks}
            hung = _hung(m)
    # its medicine smartfridge set in the wall onto the served side (8/8)
    if not any(o.path.startswith("/obj/machinery/smartfridge/chemistry") and "virology" not in o.path
               for q in ring for o in m.get(*q).objs):
        # beside its desk is fine (Meta), beside a door is not
        near_lock = lambda w: any((w[0] + dx, w[1] + dy) in D.doors for dx in (-1, 0, 1) for dy in (-1, 0, 1))  # noqa: E731
        runs = [r for r in _wall_runs(m, D, P, pub + ("storage", "cryo"), hung, allow_hung=True, by_door=True)
                if not near_lock(r[0])]
        desks_ = {w for w, s, a in D.desks}
        runs.sort(key=lambda r: (r[0] in hung, -sum(1 for dx, dy in N4 if (r[0][0] + dx, r[0][1] + dy) in desks_), r[0]))
        for w, step, p, q in runs:
            if w in hung and not _rehang(m, w, hung):
                continue
            m.get(*w).objs.append(dmm.Atom("/obj/machinery/smartfridge/chemistry/preloaded"))
            log("  fn_medical: chemistry smartfridge in the wall at %d,%d" % w)
            n += 1
            break
        else:
            # no wall to set it in: against a chemistry wall, nearest its desk or door
            serve = [w for w, s, a in D.desks if s == ("P", P["i"])] or [w for w in D.doors if any(
                (w[0] + dx, w[1] + dy) in P["tiles"] for dx, dy in N4)]
            p = _place(m, P["tiles"], D.fronts(), [dmm.Atom("/obj/machinery/smartfridge/chemistry/preloaded")],
                       want=lambda p: bool(_walls(m, p)),
                       prefer=lambda p: min([abs(p[0] - w[0]) + abs(p[1] - w[1]) for w in serve] or [0]))
            if p:
                log("  fn_medical: chemistry smartfridge against the wall at %d,%d" % p)
                n += 1
    # an emergency shower in reach of the dispensers
    disp = _tiles_with(m, P["tiles"], "/obj/machinery/chem_dispenser")
    if disp:
        d = _walk_dist(m, disp[0], lambda q: m.get(*q) is not None and m.get(*q).has("/obj/machinery/shower"), 30)
        if d is None or d > CHEM_SHOWER:
            fronts = D.fronts()
            p = _place(m, P["tiles"], fronts, [dmm.Atom("/obj/machinery/shower")],
                       want=lambda p: len(_walls(m, p)) >= 1, dir_from_wall=1,
                       prefer=lambda p: abs(p[0] - disp[0][0]) + abs(p[1] - disp[0][1]))
            if p:
                log("  fn_medical: emergency shower in chemistry at %d,%d" % p)
                n += 1
    return n


def fix_medvend(m, D, log):
    if _tiles_with(m, set(D.pid), "/obj/machinery/vending/medical"):
        return 0
    doc = D.reach(JOBS["doctor"])
    fronts = D.fronts()
    rooms = [P for P in D.of("storage") if P["i"] in doc and any(D.name(s) in WALKWAY for s, _, _ in D.links[P["i"]])]
    rooms += sorted([P for P in D.pieces if P["type"] in WALKWAY + ("treatment",) and P["i"] in doc],
                    key=lambda P: (P["area"] == "/area/medical/medbay", -len(P["tiles"])))
    for P in rooms:
        p = _place(m, P["tiles"], fronts, [dmm.Atom("/obj/machinery/vending/medical")],
                   want=lambda p: len(_walls(m, p)) >= 1, prefer=lambda p: -len(_walls(m, p)))
        if p:
            log("  fn_medical: NanoMed Plus in %s at %d,%d" % (P["type"], *p))
            return 1
    return 0


def fix_morgue(m, D, log):
    n = 0
    fronts = D.fronts()
    for P in D.of("morgue"):
        have = P["kit"]["morgue"] or 0
        if have < 8:
            got = _furnish_morgue(m, P["tiles"], fronts, 8 - have)
            if got:
                log("  fn_medical: %d morgue trays added (%d -> %d)" % (got, have, have + got))
                n += 1
    D = Dept(m)
    n += fix_morgue_exit(m, D, log)
    D = Dept(m)
    # the morgue is staff only: its doors from the walkway or the hall want morgue access
    for w, (o, a, b) in D.doors.items():
        names = {D.name(a), D.name(b)}
        if "morgue" in names and not (_acc(o)[0] | _acc(o)[1]):
            _set_door(o, acc="6")
            log("  fn_medical: morgue door %d,%d to morgue access" % w)
            n += 1
    return n


def fix_genetics(m, D, log):
    """Genetics its jobs can't get into: a door of its own to the hall or the walkway (stock 4/8 the hall, "Genetics
    Lab", research, access 9); a door to it through the security post walled up."""
    n = 0
    for P in D.of("genetics", "cloning"):
        if P["i"] in D.reach(JOBS["geneticist"]):
            continue
        fronts = D.fronts()
        hung = _hung(m)
        runs = [r for r in _wall_runs(m, D, P, WALKWAY + ("HALL",), hung, allow_hung=True) if _free(m.get(*r[2]))
                and _free(m.get(*r[3])) and r[2] not in fronts and r[3] not in fronts]
        runs.sort(key=lambda r: (D.name(D.side(r[3], None)) != "HALL", r[0] in hung, r[0]))
        for w, step, p, q in runs:
            name, path, acc = DOOR_OF[P["type"]]
            if w in hung and not _rehang(m, w, hung):
                continue
            if _cut_door(m, p, q, path, name, acc, P["area"]):
                log("  fn_medical: %s door %d,%d onto the %s" % (P["type"], *w, D.name(D.side(q, None)).lower()))
                n += 1
                break
        D = Dept(m)
    # a door between the security post and genetics/cloning (stock 0/8): walled up when both stay reached
    for w, (o, a, b) in list(D.doors.items()):
        names = {D.name(a), D.name(b)}
        if "checkpoint" in names and names & {"genetics", "cloning"}:
            t = m.get(*w)
            snap = (t.turf, list(t.objs))
            t.turf = dmm.Atom("/turf/closed/wall")
            t.objs = [x for x in t.objs if x.path.startswith(UNDER)]
            D2 = Dept(m)
            if all(any(P["i"] in D2.reach(None) for P in D2.of(k)) for k in ("checkpoint", "genetics")) and \
                    all(P["i"] in D2.reach(JOBS["geneticist"]) for P in D2.of("genetics")):
                log("  fn_medical: security post door into %s at %d,%d walled up" % ("/".join(sorted(names)), *w))
                n += 1
                D = D2
            else:
                t.turf, t.objs = snap
    return n


def fix_cloning(m, D, log):
    """Pod, scanner and console re-seated so the console touches both (it finds them by adjacency) and each has a tile
    to stand on; other furniture of the room moved aside or out."""
    n = 0
    fronts = D.fronts()
    for P in D.of("cloning"):
        room = P["tiles"]
        machines = {}
        for pre in ("/obj/machinery/computer/cloning", "/obj/machinery/clonepod", "/obj/machinery/dna_scannernew"):
            ps = _tiles_with(m, room, pre)
            if ps:
                machines[pre] = (ps[0], next(o for o in m.get(*ps[0]).objs if o.path.startswith(pre)))
        if len(machines) < 3:
            continue
        if all(_stand(m, p, room) for p, _ in machines.values()):
            continue
        _base(m, room)
        snap = {p: list(m.get(*p).objs) for p in room}
        others = []
        for p in room:
            t = m.get(*p)
            for o in list(t.objs):
                if any(o is mo for _, mo in machines.values()):
                    t.objs.remove(o)
                elif (FN.is_dense(o) or o.path.startswith("/obj/structure")) and not o.path.startswith(KEEP)                         and not CO.mounted(o):
                    t.objs.remove(o)
                    others.append(o)
        con, pod, scn = (machines[k][1] for k in ("/obj/machinery/computer/cloning", "/obj/machinery/clonepod",
                                                  "/obj/machinery/dna_scannernew"))
        done = None
        for c in sorted(room):
            if c in fronts or not _bare(m.get(*c)):
                continue
            nbs = [(c[0] + dx, c[1] + dy) for dx, dy in N4]
            nbs = [q for q in nbs if q in room and _bare(m.get(*q)) and q not in fronts]
            for a in nbs:
                for b in nbs:
                    if a == b:
                        continue
                    for q, o in ((c, con), (a, pod), (b, scn)):
                        m.get(*q).objs.append(o)
                    if _ok(m, room, fronts & room) and all(_stand(m, q, room) for q in (c, a, b)):
                        done = (c, a, b)
                        break
                    for q, o in ((c, con), (a, pod), (b, scn)):
                        m.get(*q).objs.remove(o)
                if done:
                    break
            if done:
                break
        if not done:
            for p, objs in snap.items():
                m.get(*p).objs = objs
            continue
        # the console faces its free side
        c = done[0]
        free_d = next((d for d, v in DIRV.items() if (c[0] + v[0], c[1] + v[1]) in room and _free(m.get(c[0] + v[0], c[1] + v[1]))), 2)
        con.vars = [(k, v) for k, v in con.vars if k != "dir"] + ([("dir", str(free_d))] if free_d != 2 else [])
        kept = 0
        for o in others:
            if o.path.startswith("/obj/structure/sink"):
                kept += bool(_put_sink(m, room, fronts))
            elif _place(m, room, fronts, [o], want=lambda p: bool(_walls(m, p))):
                kept += 1
        log("  fn_medical: cloning re-seated: console %d,%d, pod %d,%d, scanner %d,%d (%d of %d other pieces kept)" % (
            *done[0], *done[1], *done[2], kept, len(others)))
        n += 1
    return n


def fix_virology(m, D, log):
    n = 0
    vir = [P for P in D.pieces if P["type"].startswith("viro")]
    if not vir:
        return 0
    vset = {P["i"] for P in vir}
    for w, (o, a, b) in D.doors.items():
        ins = [s for s in (a, b) if s[0] == "P" and s[1] in vset]
        outs = [s for s in (a, b) if not (s[0] == "P" and s[1] in vset)]
        if ins and outs and 39 not in (_acc(o)[0] | _acc(o)[1]):
            kind = "viro_airlock" if D.name(ins[0]) == "viro_airlock" else "viro_lab"
            name, path, acc = DOOR_OF[kind]
            _set_door(o, name, path, acc)
            log("  fn_medical: virology outer door %d,%d to virology access" % w)
            n += 1
    if not any(P["kit"]["monkey"] for P in vir):
        cells = sorted(D.of("viro_cell"), key=lambda P: (sum(1 for p in P["tiles"] for o in m.get(*p).objs
                                                             if o.path.startswith("/obj/machinery/computer")),
                                                         -len(P["tiles"]), min(P["tiles"])))
        fronts = D.fronts()
        if len(cells) >= 3:
            P = cells[0]
            for p in P["tiles"]:
                t = m.get(*p)
                t.objs = [o for o in t.objs if not o.path.startswith(("/obj/structure/bed", "/obj/machinery/iv_drip",
                                                                      "/obj/structure/closet/secure_closet/personal"))]
            spots = [p for p in sorted(P["tiles"]) if _bare(m.get(*p)) and p not in fronts]
            for p in spots[:4]:
                m.get(*p).objs.append(dmm.Atom("/mob/living/carbon/monkey"))
            log("  fn_medical: isolation cell at %d,%d made the monkey pen (%d monkeys)" % (*min(P["tiles"]), len(spots[:4])))
        else:
            P = max(D.of("viro_lab") or vir, key=lambda P: len(P["tiles"]))
            spots = [p for p in sorted(P["tiles"]) if _free(m.get(*p)) and p not in fronts]
            for p in spots[-2:]:
                m.get(*p).objs.append(dmm.Atom("/mob/living/carbon/monkey"))
            log("  fn_medical: 2 monkeys in the virology lab")
        n += 1
    return n


def fix_posts(m, D, log):
    """The security post's locker and windows, the CMO's windows onto medbay."""
    n = 0
    fronts = D.fronts()
    for P in D.of("checkpoint"):
        if not P["kit"]["sec_locker"]:
            lock = dmm.Atom("/obj/structure/closet/secure_closet/security/med")
            if _place(m, P["tiles"], fronts, [lock], want=lambda p: len(_walls(m, p)) >= 1, prefer=lambda p: -len(_walls(m, p))):
                log("  fn_medical: security locker in the medbay post")
                n += 1
            else:
                # no spot: it takes the place of a wardrobe or filing cabinet (stock posts: locker 8/8, wardrobe 2/8)
                for p in sorted(P["tiles"]):
                    t = m.get(*p)
                    old = [o for o in t.objs if o.path.startswith(("/obj/structure/closet/wardrobe", "/obj/structure/filingcabinet"))]
                    if old:
                        t.objs = [o for o in t.objs if o is not old[0]] + [lock]
                        log("  fn_medical: security locker in the medbay post in place of its %s" % old[0].path.split("/")[-1])
                        n += 1
                        break
    D = Dept(m)
    hung = _hung(m)
    for P in D.of("checkpoint"):
        if not any(D.name(a) in WALKWAY + ("HALL",) for w, s, a in D.wins + D.desks if s == ("P", P["i"])):
            n += bool(_glaze(m, D, P, WALKWAY + ("HALL",), hung, 2, log, "security post"))
    D = Dept(m)
    hung = _hung(m)
    cmo = D.of("cmo")
    if cmo and not any(D.name(a) in WALKWAY + ("treatment", "cryo", "HALL") for w, s, a in D.wins
                       if s[0] == "P" and D.pieces[s[1]]["type"] == "cmo"):
        for P in sorted(cmo, key=lambda P: -sum(1 for s, _, _ in D.links[P["i"]] if D.name(s) in WALKWAY)):
            if _glaze(m, D, P, WALKWAY + ("treatment",), hung, 2, log, "CMO office"):
                n += 1
                break
    return n


def fix_small(m, D, log):
    """Patient lockers; seats where the public waits; emergency shower on the walkway."""
    n = 0
    fronts = D.fronts()
    for P in D.of("patient_room"):
        if not P["kit"]["glass_cab"]:
            if _place(m, P["tiles"], fronts, [dmm.Atom("/obj/structure/closet/secure_closet/personal/patient")],
                      want=lambda p: len(_walls(m, p)) >= 1, prefer=lambda p: -len(_walls(m, p))):
                n += 1
    if n:
        log("  fn_medical: %d patient lockers" % n)
    for P in D.of("storage"):
        if not P["kit"]["medlocker"] and (P["kit"]["firstaid"] or 0) < 4:
            if _place(m, P["tiles"], fronts, [dmm.Atom("/obj/structure/closet/secure_closet/medical1")],
                      want=lambda p: len(_walls(m, p)) >= 1, prefer=lambda p: -len(_walls(m, p))):
                log("  fn_medical: medicine closet in the storage at %d,%d" % min(P["tiles"]))
                n += 1
    pub = D.reach(set())
    front = [P for P in D.pieces if P["i"] in pub and P["type"] in WALKWAY]
    if front and not any(P["kit"]["chair"] for P in front):
        P = max(front, key=lambda P: (P["type"] == "lobby", len(P["tiles"])))
        hall_doors = [w for s, k, w in D.links[P["i"]] if s == ("X", "HALL")]
        near = lambda p: min(abs(p[0] - w[0]) + abs(p[1] - w[1]) for w in hall_doors) if hall_doors else 0  # noqa: E731
        got = []
        for _ in range(3):
            p = _place(m, P["tiles"], fronts, [dmm.Atom("/obj/structure/chair")],
                       want=lambda p: len(_walls(m, p)) == 1 and 2 <= near(p) <= 8 and (not got or (
                           any(abs(p[0] - g[0]) + abs(p[1] - g[1]) == 1 for g in got) and _walls(m, p) == _walls(m, got[0]))),
                       dir_from_wall=1, prefer=near)
            if p:
                got.append(p)
        got = len(got)
        if got:
            log("  fn_medical: %d waiting seats in the %s by the hall door" % (got, P["type"]))
            n += 1
    return n


def fix_names(m, D, log):
    """Doors whose name names a room on neither side get the inner room's name (doordb names by group pair)."""
    n = 0
    for w, (o, a, b) in D.doors.items():
        nm = (o.get("name") or "").strip('"').lower()
        sides = {D.name(a), D.name(b)}
        areas = " ".join(D.pieces[x[1]]["area"] for x in (a, b) if x[0] == "P")
        keys = [(key, types) for key, types in NAME_TYPES if key in nm]
        if "access" in nm or not keys or any(sides & set(types) or key in areas for key, types in keys):
            continue
        inner = next((t for t in INNER_ORDER if t in sides), None)
        if inner in DOOR_OF:
            new = DOOR_OF[inner][0]
            if inner == "viro_lab" and not sides & {"medhall", "lobby", "HALL", "MAINT"}:
                new = "Virology Interior Airlock"
        elif sides & set(WALKWAY):
            new = "Medbay"
        else:
            continue
        _set_door(o, new)
        log('  fn_medical: door %d,%d "%s" -> "%s"' % (w[0], w[1], nm, new))
        n += 1
    return n


def fix(m, seed=1, log=print):
    r = random.Random("fn_medical|%s" % seed)
    _BASE.clear()
    n = 0
    for step in (lambda D: fix_surgery(m, D, r, log), lambda D: fix_cryo(m, D, log), lambda D: fix_chemistry(m, D, log),
                 lambda D: fix_medvend(m, D, log), lambda D: fix_morgue(m, D, log), lambda D: fix_genetics(m, D, log),
                 lambda D: fix_cloning(m, D, log), lambda D: fix_virology(m, D, log), lambda D: fix_posts(m, D, log),
                 lambda D: fix_small(m, D, log), lambda D: fix_names(m, D, log)):
        D = Dept(m)
        if not D.pieces:
            return 0
        n += step(D) or 0
    log("fn_medical: %d fixes" % n)
    return n


def _summary(found):
    c = Counter(t.split(":")[0] for _, _, t in found)
    return "%d (%s)" % (len(found), ", ".join("%s %d" % kv for kv in sorted(c.items())))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("dmm")
    ap.add_argument("out", nargs="?")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()
    m = dmm.read(a.dmm)
    before = check(m)
    print("check before: %s" % _summary(before))
    if not a.quiet:
        for x, y, t in before:
            print("  %3d,%3d  %s" % (x, y, t))
    if a.out:
        fix(m, a.seed)
        after = check(m)
        print("check after: %s" % _summary(after))
        if not a.quiet:
            for x, y, t in after:
                print("  %3d,%3d  %s" % (x, y, t))
        dmm.write(m, a.out)
