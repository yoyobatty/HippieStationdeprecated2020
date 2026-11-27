"""Security, Command and the station as a whole: function checks and fixes on a finished station.

The user 2026-11-26: "double check every room and hallway one by one, make sure it's sensical, functional like an ss13
map with good human like pathing, design and function ... check how rooms and hallways and departments fit and join
together holistically". Spec and stock numbers: tools/mapforge/studies/dept_specs/security_command_station.md (rules
S1-S15, C1-C7, H1-H3; the stock study is studies/dept_specs/security_command_work/study.py).

check(m) -> [(x, y, text)]: each text starts with its rule id ("S1 ...").
fix(m, seed=1, log=print) -> int, what a finished layout allows without moving walls:
  fix_cells      S1: the brig's one-door pieces become timed cells: a cell windoor whose dir points into the cell (the
                 security bots flood the cell from it: goals/security_patrol.dm bot_get_cell_interior), a door timer
                 on a bare wall outside within 3 tiles, a flasher, a brig locker with the cell's id, a bed; waiting-room
                 chairs and tables out; spare brig lockers with copied stock ids tidied. No timer: the Warden and the
                 security bots (security_custody.dm find_free_brig_cell) can't sentence anyone.
  fix_doors      S4/S12: a door between two kinds of room no stock map joins (the armory into the law office, the vault
                 into EVA, a hall into the education chamber) is walled up when every piece of both rooms stays reached
                 from the halls; public sides first, then the armory/vault/prison, then the courtroom and law office.
  fix_add_doors  C3b/S5/S8/S9/S14/H1: the doors stock gives these rooms (the HoP's hall airlock in the HoP's own area,
                 the courtroom's public door, the detective's hall door, maint back doors up to Security 3, Command 1),
                 styled by gen/learn/doordb.py, through a straight plain wall (hung pieces shifted along it).
  fix_desks      S3/C3: Brig Control's and the HoP's desks through gen/learn/desks.py (chance 1); fix_front_desk S7b.
  fix_hop_queue  C3: the HoP queue (delivery decal and flasher on the customer's tile, three queue tiles, the button).
  fix_gear       S3b: the warden's locker, prisoner management, camera and records consoles in Brig Control; a small
                 Brig Control's officers' lockers go to the Security Office.
  fix_lawyer     S15: the doors on the lawyer's way take ACCESS_SEC_DOORS (63) as the stock brig front door does.
Never a dense piece on a door's front, never a piece boxed in, every room piece kept reached.

    python tools/mapforge/gen/learn/fn_security_command.py <in.dmm> <out.dmm>      # check before, fix, check after
    python tools/mapforge/gen/learn/fn_security_command.py <in.dmm>                # check only
"""
import os
import random
import sys
from collections import Counter, defaultdict, deque

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(HERE, "..", "..", "studies"))
from forge import corpus as CO, dmm, function as FN  # noqa: E402

N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
DIRV = {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0)}
VDIR = {v: k for k, v in DIRV.items()}
DNAME = {1: "north", 2: "south", 4: "east", 8: "west"}
AIRLOCK = "/obj/machinery/door/airlock"
WINDOOR = "/obj/machinery/door/window"
WINDOWS = ("/obj/effect/spawner/structure/window", "/obj/structure/window", "/obj/structure/grille")

# role -> area paths: an entry ending in "/" takes the subtree, else the exact area
ROLES = (
    ("armory", ("/area/ai_monitored/security/armory/",)),
    ("warden", ("/area/security/warden/",)),
    ("hos", ("/area/crew_quarters/heads/hos/",)),
    ("main", ("/area/security/main/",)),
    ("brig", ("/area/security/brig/",)),
    ("prison", ("/area/security/prison/",)),
    ("courtroom", ("/area/security/courtroom/",)),
    ("detective", ("/area/security/detectives_office/",)),
    ("lawoffice", ("/area/lawoffice/",)),
    ("labor", ("/area/security/processing/",)),
    ("transfer", ("/area/security/execution/transfer/",)),
    ("education", ("/area/security/execution/education/",)),
    ("range", ("/area/security/range/",)),
    ("sec_vault", ("/area/security/nuke_storage/",)),
    ("customs", ("/area/security/checkpoint/customs/",)),
    ("post_escape", ("/area/security/checkpoint/escape/",)),
    ("post_medical", ("/area/security/checkpoint/medical/",)),
    ("post_science", ("/area/security/checkpoint/science/",)),
    ("post_engineering", ("/area/security/checkpoint/engineering/",)),
    ("post_supply", ("/area/security/checkpoint/supply/",)),
    ("post_other", ("/area/security/checkpoint/",)),
    ("sec_corr", ("/area/security",)),
    ("sec_other", ("/area/security/",)),
    ("bridge", ("/area/bridge",)),
    ("meeting", ("/area/bridge/meeting_room/",)),
    ("showroom", ("/area/bridge/showroom/",)),
    ("captain_bed", ("/area/crew_quarters/heads/captain/private/",)),
    ("captain", ("/area/crew_quarters/heads/captain",)),
    ("hop", ("/area/crew_quarters/heads/hop/",)),
    ("cmd_corr", ("/area/crew_quarters/heads", "/area/hallway/secondary/command/")),
    ("vault", ("/area/ai_monitored/nuke_storage/",)),
    ("eva", ("/area/ai_monitored/storage/eva/",)),
    ("teleporter", ("/area/teleporter/",)),
    ("gateway", ("/area/gateway/",)),
    ("upload", ("/area/ai_monitored/turret_protected/ai_upload/",)),
    ("tcomms_ctrl", ("/area/tcommsat/computer/",)),
)
SEC = ("armory", "warden", "hos", "main", "brig", "prison", "courtroom", "detective", "labor", "transfer", "education",
       "range", "sec_corr", "sec_other")
POSTS = ("customs", "post_escape", "post_medical", "post_science", "post_engineering", "post_supply", "post_other")
CMD = ("bridge", "meeting", "showroom", "captain_bed", "captain", "hop", "cmd_corr", "vault", "eva", "teleporter",
       "gateway", "upload", "tcomms_ctrl")
# a department post's own department (stations.group_of)
POST_DEPT = {"post_medical": "medical", "post_science": "science", "post_engineering": "engineering",
             "post_supply": "cargo"}


def role_of(area):
    if not area:
        return None
    for role, ps in ROLES:
        for p in ps:
            if p.endswith("/"):
                if area == p[:-1] or area.startswith(p):
                    return role
            elif area == p:
                return role
    return None


def group_of(area):
    import stations as ST
    return ST.group_of(area)


def is_hall(area):
    return area.startswith("/area/hallway") and not area.startswith("/area/hallway/secondary/command")


def _walk(t):
    return t is not None and t.tpath.startswith("/turf/open") and not t.tpath.startswith("/turf/open/space") \
        and not CO.solid(t)


def _floor(t):
    """Open floor a person stands on: walkable, no door on it."""
    return _walk(t) and not t.has("/obj/machinery/door") or (
        _walk(t) and t.has("/obj/machinery/door/firedoor") and not any(
            o.path.startswith("/obj/machinery/door") and not o.path.startswith("/obj/machinery/door/firedoor")
            for o in t.objs))


def _doorish(t):
    return t is not None and any(o.path.startswith("/obj/machinery/door") and not o.path.startswith(
        "/obj/machinery/door/firedoor") for o in t.objs)


def _wallish(t):
    return t is None or t.tpath.startswith("/turf/closed") or CO.solid(t) or _doorish(t) or any(
        o.path.startswith(WINDOWS) for o in t.objs)


def kind_of(t):
    """What joins two places through tile t: desk (a table and a windoor), airlock, windoor, shutter, window."""
    if t is None:
        return None
    if t.has(WINDOOR) and t.has("/obj/structure/table"):
        return "desk"
    if t.has(AIRLOCK):
        return "airlock"
    if t.has(WINDOOR):
        return "windoor"
    if t.has("/obj/machinery/door/poddoor"):
        return "shutter"
    if any(o.path.startswith(WINDOWS) for o in t.objs):
        return "window"
    return None


def floors(m):
    """{area: set of floor tiles} on z 1."""
    out = defaultdict(set)
    for (x, y, z), t in m.tiles.items():
        if z == 1 and _floor(t):
            out[t.apath].add((x, y))
    return out


def sides(m, x, y, skip=3):
    """The two floor places a door/window/desk tile joins: [(area, (x, y)), (area, (x, y))] along the axis whose
    cross neighbours are wall-like (else either open axis), past up to `skip` door/window tiles; or None."""
    best = None
    for ax in ((1, 0), (0, 1)):
        cross = (ax[1], ax[0])
        out = []
        for s in (1, -1):
            p = (x + ax[0] * s, y + ax[1] * s)
            k = 0
            while kind_of(m.get(*p)) and k < skip:
                p = (p[0] + ax[0] * s, p[1] + ax[1] * s)
                k += 1
            t = m.get(*p)
            if not _walk(t):
                break
            out.append((t.apath, p))
        if len(out) != 2:
            continue
        walled = all(_wallish(m.get(x + cross[0] * s, y + cross[1] * s)) for s in (1, -1))
        if walled:
            return out
        if best is None:
            best = out
    return best


def joins(m):
    """[(kind, (x, y), area a, area b)] every door, desk, windoor, shutter and window tile between two places, and
    'wall' for a wall tile between two different areas' floors (each wall tile once)."""
    out = []
    for (x, y, z), t in m.tiles.items():
        if z != 1:
            continue
        k = kind_of(t)
        if k:
            s = sides(m, x, y)
            if s:
                out.append((k, (x, y), s[0][0], s[1][0]))
            continue
        if t.tpath.startswith("/turf/closed"):
            for ax in ((1, 0), (0, 1)):
                a, b = m.get(x + ax[0], y + ax[1]), m.get(x - ax[0], y - ax[1])
                if _floor(a) and _floor(b) and a.apath != b.apath:
                    out.append(("wall", (x, y), a.apath, b.apath))
                    break
    return out


RANK = {"airlock": 5, "desk": 4, "windoor": 3, "shutter": 2, "window": 1, "wall": 0}


def links(J):
    """{(area a, area b): best kind} both ways round."""
    out = {}
    for k, p, a, b in J:
        if a == b:
            continue
        for key in ((a, b), (b, a)):
            if key not in out or RANK[k] > RANK[out[key]]:
                out[key] = k
    return out


def role_links(J):
    """{role or 'hall'/'maint'/group: {other: best kind}} by role (areas without a role go by their group)."""
    out = defaultdict(dict)
    for (a, b), k in links(J).items():
        ra, rb = _tag(a), _tag(b)
        if ra == rb:
            continue
        if rb not in out[ra] or RANK[k] > RANK[out[ra][rb]]:
            out[ra][rb] = k
    return out


def _tag(area):
    r = role_of(area)
    if r:
        return r
    if is_hall(area):
        return "hall"
    if area.startswith("/area/maintenance"):
        return "maint"
    return "g:%s" % group_of(area)


def pieces(tiles):
    left, out = set(tiles), []
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


def piece_doors(m, piece):
    """[(door tile, kind, (area, pos) beyond)] the doors and desks round a floor piece."""
    out, seen = [], set()
    for p in piece:
        for dx, dy in N4:
            w = (p[0] + dx, p[1] + dy)
            if w in seen:
                continue
            k = kind_of(m.get(*w))
            if k in ("airlock", "windoor", "desk", "shutter"):
                seen.add(w)
                s = sides(m, *w)
                if not s:
                    continue
                far = s[0] if s[1][1] in piece or s[1][1] == p else s[1]
                if far[1] in piece:
                    far = s[1] if far is s[0] else s[0]
                out.append((w, k, far))
    return out


# ---------------------------------------------------------------- the brig's cells

def cells(m):
    """[dict] one a door timer: id, pos, linked cell windoors, interior tiles (from the windoor's dir, as the bots
    read it), a brig locker, a bed, a flasher in it."""
    timers, cdoors, lockers, flashers = [], [], [], []
    for (x, y, z), t in m.tiles.items():
        if z != 1:
            continue
        for o in t.objs:
            if o.path.startswith("/obj/machinery/door_timer"):
                timers.append(((x, y), o))
            elif o.path.startswith("/obj/machinery/door/window/brigdoor"):
                cdoors.append(((x, y), o))
            elif o.path.startswith("/obj/structure/closet/secure_closet/brig"):
                lockers.append(((x, y), o))
            elif o.path.startswith("/obj/machinery/flasher") and not o.path.startswith("/obj/machinery/flasher/portable"):
                flashers.append(((x, y), o))
    out = []
    for p, o in timers:
        i = o.get("id")
        near = lambda q: max(abs(q[0] - p[0]), abs(q[1] - p[1])) <= 20  # noqa: E731
        ds = [(q, d) for q, d in cdoors if i and d.get("id") == i and near(q)]
        inner = set()
        for q, d in ds:
            inner |= cell_interior(m, q, _dir(d))
        out.append(dict(id=i, pos=p, doors=[q for q, d in ds], interior=inner,
                        locker=any(lp in inner or lo.get("id") == i for lp, lo in lockers if i and lo.get("id") == i),
                        bed=any(m.get(*q).has("/obj/structure/bed") for q in inner),
                        flasher=any(f.get("id") == i for fp, f in flashers),
                        dist=min([max(abs(q[0] - p[0]), abs(q[1] - p[1])) for q, d in ds] or [99])))
    return out


def _dir(o):
    d = o.get("dir")
    if d is not None:
        try:
            return int(d)
        except ValueError:
            pass
    for k, v in DNAME.items():
        if "/" + v in o.path:
            return k
    return 2


def cell_interior(m, door, d):
    """The flood fill the security bots make from a cell windoor (bot_get_cell_interior): from the tile its dir
    points to, through open tiles with no door, window or grille, at most 4 from the seed, 30 tiles."""
    v = DIRV.get(d, (0, -1))
    seed = (door[0] + v[0], door[1] + v[1])
    out, q, seen = set(), deque([seed]), {seed}
    while q and len(out) < 30:
        c = q.popleft()
        t = m.get(*c)
        if c == door or not _walk(t) or t.has("/obj/machinery/door") or any(o.path.startswith(WINDOWS) for o in t.objs):
            continue
        if max(abs(c[0] - seed[0]), abs(c[1] - seed[1])) > 4:
            continue
        out.add(c)
        for dx, dy in N4:
            n = (c[0] + dx, c[1] + dy)
            if n not in seen:
                seen.add(n)
                q.append(n)
    return out


def cell_pieces(m, F=None):
    """[(piece, [doors])] small brig/prison pieces with one door and a bed (or 4-12 tiles): the cells."""
    F = F or floors(m)
    out = []
    for a, tiles in F.items():
        if role_of(a) not in ("brig", "prison"):
            continue
        for pc in pieces(tiles):
            if len(pc) > 12:
                continue
            ds = piece_doors(m, pc)
            if len(ds) != 1:
                continue
            out.append((pc, ds))
    return out


# ---------------------------------------------------------------- the kit

LOCKER_SEC = "/obj/structure/closet/secure_closet/security"


def kit(m, F=None):
    """{role: Counter(path)} the pieces on each role's floor (wall-hung ones included)."""
    F = F or floors(m)
    out = defaultdict(Counter)
    for a, tiles in F.items():
        r = role_of(a) or _tag(a)
        for p in tiles:
            for o in m.get(*p).objs:
                if o.path.startswith(("/obj/structure/cable", "/obj/machinery/atmospherics/pipe", "/obj/structure/disposalpipe",
                                      "/obj/effect/turf_decal", "/obj/effect/landmark")):
                    continue
                out[r][o.path] += 1
    return out


def has(c, prefix, exact=False):
    return sum(n for p, n in c.items() if (p == prefix if exact else p == prefix or p.startswith(prefix + "/")))


# ---------------------------------------------------------------- the station's routes

PUBLIC_GROUPS = ("hall", "arrivals", "escape")


def routes(m, J=None):
    """{'arrivals': {tag: steps}, 'escape': {tag: steps}, 'radius': r}: the shortest walk over the halls (hall,
    arrivals and escape areas, the doors in them) from the arrivals hall / the escape hall to the first floor of each
    department group (security posts left out: 'post') and each role, and the station's radius (sqrt(floor / pi))."""
    import math
    F = floors(m)
    n = sum(len(v) for a, v in F.items() if not a.startswith(("/area/space", "/area/solar", "/area/shuttle")))
    arr = [p for a, v in F.items() if a.startswith("/area/hallway/secondary/entry") for p in v]
    esc = [p for a, v in F.items() if a.startswith("/area/hallway/secondary/exit") for p in v]
    out = {"radius": math.sqrt(n / math.pi)}
    gcache = {}

    def grp(a):
        if a not in gcache:
            gcache[a] = group_of(a) or "other"
        return gcache[a]
    for name, st in (("arrivals", arr), ("escape", esc)):
        dist = {s: 0 for s in st}
        q = deque(st)
        res = {}
        while q:
            p = q.popleft()
            for dx, dy in N4:
                nb_ = (p[0] + dx, p[1] + dy)
                if nb_ in dist:
                    continue
                t = m.get(*nb_)
                if not _walk(t):
                    continue
                g = grp(t.apath)
                dist[nb_] = dist[p] + 1
                if g in PUBLIC_GROUPS:
                    q.append(nb_)
                    continue
                if _doorish(t):
                    # a door out of the hall: what's past it
                    s = sides(m, *nb_)
                    if not s:
                        continue
                    far = s[0] if s[0][1] != p else s[1]
                    a = far[0]
                else:
                    a = t.apath
                g = grp(a)
                r = role_of(a)
                key = "post" if r in POSTS else g
                res.setdefault(key, dist[nb_])
                if r:
                    res.setdefault(r, dist[nb_])
        out[name] = res
    return out


# ---------------------------------------------------------------- the rules

# Doors between two of these places on the stock maps (Meta, Box, Delta, Pubby, Donut, Endo, Hippie: families with
# such a door; studies/dept_specs/security_command_work/door_pairs.txt). The generator's own corridors read as their
# stock kin: the security corridor as the brig's hall, the command corridor as Meta's command hall.
STOCK_DOOR_PAIRS = {
    ("armory", "brig"): 2, ("armory", "main"): 2, ("armory", "warden"): 7, ("bridge", "captain"): 6,
    ("bridge", "captain_bed"): 2, ("bridge", "cmd_corr"): 1, ("bridge", "hop"): 4, ("bridge", "meeting"): 3,
    ("bridge", "tcomms_ctrl"): 1, ("bridge", "upload"): 3, ("brig", "courtroom"): 4, ("brig", "detective"): 1,
    ("brig", "labor"): 3, ("brig", "main"): 7, ("brig", "prison"): 5, ("brig", "range"): 1, ("brig", "transfer"): 1,
    ("brig", "warden"): 7, ("captain", "captain_bed"): 2, ("captain_bed", "cmd_corr"): 1, ("captain_bed", "teleporter"): 1,
    ("cmd_corr", "eva"): 2, ("cmd_corr", "gateway"): 2, ("cmd_corr", "hop"): 2, ("cmd_corr", "showroom"): 2,
    ("cmd_corr", "teleporter"): 2, ("courtroom", "lawoffice"): 2, ("education", "prison"): 2, ("hop", "meeting"): 3,
    ("hos", "main"): 7, ("labor", "prison"): 1, ("labor", "transfer"): 1, ("main", "prison"): 1, ("main", "range"): 1,
    ("main", "warden"): 5, ("prison", "transfer"): 4,
    # to the halls and maint
    ("bridge", "hall"): 6, ("bridge", "maint"): 2, ("brig", "hall"): 6, ("brig", "maint"): 3, ("captain", "maint"): 3,
    ("captain_bed", "maint"): 1, ("cmd_corr", "hall"): 2, ("cmd_corr", "maint"): 1, ("courtroom", "hall"): 5,
    ("courtroom", "maint"): 4, ("customs", "hall"): 4, ("customs", "maint"): 3, ("detective", "hall"): 6,
    ("detective", "maint"): 5, ("eva", "hall"): 4, ("eva", "maint"): 2, ("gateway", "hall"): 5, ("gateway", "maint"): 3,
    ("hall", "hop"): 6, ("hall", "labor"): 2, ("hall", "lawoffice"): 6, ("hall", "post_escape"): 2,
    ("hall", "post_other"): 5, ("hall", "showroom"): 2, ("hall", "tcomms_ctrl"): 2, ("hall", "teleporter"): 5,
    ("hall", "transfer"): 1, ("hall", "vault"): 3, ("labor", "maint"): 4, ("lawoffice", "maint"): 6, ("main", "maint"): 5,
    ("maint", "range"): 2, ("maint", "teleporter"): 2, ("maint", "upload"): 1, ("maint", "vault"): 1,
    ("cmd_corr", "vault"): 0, ("hall", "post_engineering"): 1, ("hall", "post_medical"): 1, ("hall", "post_science"): 1,
    ("maint", "post_other"): 2, ("maint", "post_science"): 1, ("maint", "prison"): 1,
    ("courtroom", "g:dorms"): 1, ("g:dorms", "lawoffice"): 1,
    # Meta's captain area (captain/private) is his office and bedroom in one: its doors stand for the office's
    ("captain", "cmd_corr"): 1,
    # a post's back door to maint (Box, Delta, Endo: posts of every kind)
    ("maint", "post_supply"): 1, ("maint", "post_medical"): 1, ("maint", "post_engineering"): 1,
}
KIN = {"sec_corr": "brig", "sec_other": "brig"}
MINE = set(SEC + POSTS + CMD + ("lawoffice",))


def _pair(a, b):
    ta, tb = _tag(a), _tag(b)
    ta, tb = KIN.get(ta, ta), KIN.get(tb, tb)
    return tuple(sorted((ta, tb)))


def stock_pair(a, b):
    """True when the stock maps have a door between these two places' kinds (or neither is one of ours)."""
    p = _pair(a, b)
    if p[0] == p[1] or not (p[0] in MINE or p[1] in MINE):
        return True
    if any(x.startswith("g:") for x in p) and any(x.startswith("post_") for x in p):
        return True            # a post into its department: S11 judges it
    if any(x.startswith("g:") for x in p):
        return p in (("g:ai", "tcomms_ctrl"), ("g:ai", "upload"), ("cmd_corr", "g:ai")) or p in STOCK_DOOR_PAIRS
    return p in STOCK_DOOR_PAIRS


def measure(m):
    """Everything check() and the stock study read, in one pass."""
    F = floors(m)
    J = joins(m)
    RL = role_links(J)
    K = kit(m, F)
    present = Counter()
    for a, tiles in F.items():
        r = role_of(a)
        if r:
            present[r] += len(tiles)
    return dict(F=F, J=J, RL=RL, K=K, present=present, cells=cells(m), cellp=cell_pieces(m, F))


def _first(F, role):
    for a, tiles in sorted(F.items()):
        if role_of(a) == role and tiles:
            return min(tiles)
    return (0, 0)


def _doors_of(J, role, kinds=("airlock", "windoor")):
    """[(pos, other area)] the doors of a role's rooms."""
    out = []
    for k, p, a, b in J:
        if k not in kinds:
            continue
        ra, rb = role_of(a), role_of(b)
        if ra == role and rb != role:
            out.append((p, b))
        elif rb == role and ra != role:
            out.append((p, a))
    return out


def _link(RL, role, others, kinds=("airlock", "windoor", "desk")):
    return any(RL.get(role, {}).get(o) in kinds for o in others)


def check(m, M=None):
    """[(x, y, 'RULE text')] the spec's rules (stock counts over the 7 stock families in the text)."""
    M = M or measure(m)
    F, J, RL, K, present = M["F"], M["J"], M["RL"], M["K"], M["present"]
    out = []

    def bad(role, text, at=None):
        x, y = at or _first(F, role)
        out.append((x, y, text))

    brigs = ("brig", "sec_corr")
    # S1 timed cells, each with a bed, a flasher and a brig locker
    timed = [c for c in M["cells"] if c["doors"] and len(c["interior"]) >= 2]
    if len(timed) < 3:
        bad("brig", "S1 %d timed brig cells (stock 3-4 in the brig, 7/7; a door timer outside, its cell windoor): "
                    "the Warden and the security bots can't sentence anyone" % len(timed))
    for c in timed:
        if role_of(m.get(*c["pos"]).apath) not in SEC:
            continue            # a post's holding cell (Delta) has no bed or flasher
        miss = [w for w, ok in (("brig locker", c["locker"]), ("bed", c["bed"]), ("flasher", c["flasher"])) if not ok]
        if miss:
            bad("brig", "S1b cell %s lacks %s (stock 7/7 cells have all three)" % (c["id"], ", ".join(miss)), c["pos"])
        if c["dist"] > 3:
            bad("brig", "S1c cell %s's timer %d tiles from its door (stock 1-2)" % (c["id"], c["dist"]), c["pos"])
    # S2/S3 Brig Control: on the brig's hall with a desk, beside the armory, its own kit
    if present["warden"]:
        if not _link(RL, "warden", brigs):
            bad("warden", "S2 Brig Control has no door onto the brig or its hall (stock 7/7)")
        if not any(k == "desk" for (a, b), k in links(J).items() if role_of(a) == "warden") and not any(
                k_ == "desk" and "warden" in (role_of(a_), role_of(b_)) for k_, p_, a_, b_ in J):
            bad("warden", "S3 Brig Control has no desk (table + windoor) onto the brig/hall (stock 7/7 look onto "
                          "the brig: desk, windoor or window)")
        for name, pre, ex in (("warden locker", "/obj/structure/closet/secure_closet/warden", False),
                              ("prisoner management console", "/obj/machinery/computer/prisoner", False),
                              ("security camera console", "/obj/machinery/computer/security", True),
                              ("security records console", "/obj/machinery/computer/secure_data", False)):
            if not has(K["warden"], pre, ex):
                bad("warden", "S3b Brig Control has no %s (stock 7/7)" % name)
    # S4 the armory: off Brig Control, never off a room outside Security
    if present["armory"]:
        for p, other in _doors_of(J, "armory"):
            if role_of(other) not in SEC:
                bad("armory", "S4 armory door into %s (stock: only Brig Control 7/7, the brig/office 4/7)" % other, p)
        if RL["warden"].get("armory") not in ("airlock", "windoor", "desk"):
            bad("armory", "S4b the armory isn't off Brig Control (stock 7/7)")
    # S5 the HoS off the Security Office
    if present["hos"] and RL["hos"].get("main") not in ("airlock", "windoor"):
        bad("hos", "S5 the HoS office isn't off the Security Office (stock 7/7)")
    # S6 the officers' gear
    lockers = sum(has(K[r], LOCKER_SEC + "/sec") + has(K[r], LOCKER_SEC, exact=True) for r in SEC)
    if lockers < 4:
        bad("main", "S6 %d officers' lockers in Security (stock 6-8)" % lockers)
    if not any(has(K[r], "/obj/machinery/vending/security") for r in ("main", "warden", "brig", "sec_corr", "sec_other")):
        bad("main", "S6b no SecTech vendor in the office, Brig Control or the brig (stock 7/7)")
    # S7 the front door onto a hall, and a front desk
    if not any(RL[r].get("hall") in ("airlock", "windoor", "desk") for r in brigs + ("main",)):
        bad("brig", "S7 Security has no front door onto a hall (stock 7/7)")
    if not any(k == "desk" and {_tag(a), _tag(b)} & {"brig", "sec_corr"} and (is_hall(a) or is_hall(b))
               for k, p, a, b in J):
        bad("sec_corr", "S7b no front desk from the brig onto the hall (stock 5/7)")
    # S8 the courtroom: the public's door
    if present["courtroom"] and RL["courtroom"].get("hall") != "airlock":
        bad("courtroom", "S8 the courtroom has no public door onto a hall (stock 5/6 courtrooms)")
    # S9/S14 the detective and the lawyer: a door from the hall or maint
    for r, rule, n in (("detective", "S9", "6/7 hall, 5/7 maint"), ("lawoffice", "S14", "6/7 hall, 6/7 maint")):
        if present[r] and not any(RL[r].get(o) == "airlock" for o in ("hall", "maint")):
            bad(r, "%s the %s opens only inside Security (stock %s)" % (rule, r, n))
    # S10 customs at arrivals
    if not present["customs"]:
        bad("brig", "S10 no arrivals customs post (stock 4/7 families)")
    # S11 department posts open into their department
    for r, g in POST_DEPT.items():
        if present[r] and RL[r].get("g:%s" % g) not in ("airlock", "windoor", "desk"):
            bad(r, "S11 the %s post has no door into %s (stock 5-7/7)" % (r.split("_")[1], g))
    # S12 doors between kinds of room the stock maps never join (the armory into the law office ...)
    for k, p, a, b in J:
        if k in ("airlock", "windoor") and not stock_pair(a, b) and not set(_pair(a, b)) & {"upload", "tcomms_ctrl"}:
            out.append((p[0], p[1], "S12 door %s <-> %s: no stock map joins these" % _pair(a, b)))
    # S15 the lawyer reaches the law office and the courtroom (lawyer.dm access: 38, 42, 63)
    for r in ("lawoffice", "courtroom"):
        if present[r] and not _job_reaches(m, LAWYER, r):
            bad(r, "S15 the lawyer can't reach the %s with a lawyer's access (stock 7/7)" % r)
    # S13 labor camp dock
    if not any(o.path.startswith("/obj/docking_port/stationary") and (o.get("id") or "").strip('"') == "laborcamp_home"
               for t in m.tiles.values() for o in t.objs):
        bad("labor" if present["labor"] else "brig", "S13 no labor shuttle dock (laborcamp_home: stock 7/7)")
    # C1 the bridge
    if present["bridge"] and not any(RL["bridge"].get(r) == "airlock" for r in ("hall", "cmd_corr")):
        bad("bridge", "C1 the bridge has no door onto a hall or the command hall (stock 7/7)")
    # C2 the captain's office off the bridge, his bedroom off the office or bridge
    if present["captain"] and not any(RL["captain"].get(r) in ("airlock", "windoor") for r in ("bridge",)):
        bad("captain", "C2 the captain's office isn't off the bridge (stock 6/6)")
    if present["captain_bed"] and not any(RL["captain_bed"].get(r) == "airlock" for r in ("captain", "bridge", "cmd_corr")):
        bad("captain_bed", "C2b the captain's bedroom isn't off his office, the bridge or the command hall (stock 4/4)")
    # C3 the HoP: a desk onto a hall with its queue, and an airlock the bots find
    if present["hop"]:
        if not _hop_desk_hall(m, J):
            bad("hop", "C3 the HoP's desk doesn't face a public hall (stock 7/7): no queue, no service")
        if not _hop_airlock_on_hall(m):
            bad("hop", "C3b no HoP airlock (in the HoP's area) with a hall tile in front: bot_hopping.dm "
                       "department_doorstep finds no HoP (stock 6/7)")
    # C4 the vault: one door, from a hall, maint or the command hall
    if present["vault"]:
        ds = _doors_of(J, "vault", ("airlock",))
        if len(ds) > 1:
            bad("vault", "C4 the vault has %d doors (stock 1)" % len(ds))
        np_ = len([pc for a, v in F.items() if role_of(a) == "vault" for pc in pieces(v) if len(pc) >= 4])
        if np_ > 1:
            bad("vault", "C4c the vault is %d separate rooms (stock 1; Hippie 2)" % np_)
        if present["vault"] > 43:
            bad("vault", "C4b the vault is %d tiles (stock 20-43)" % present["vault"])
    # C5 EVA, teleporter, gateway off a hall or the command hall
    for r, rule in (("eva", "C5"), ("teleporter", "C6"), ("gateway", "C7")):
        if present[r] and not any(RL[r].get(o) in ("airlock", "shutter") for o in ("hall", "cmd_corr")):
            bad(r, "%s %s has no door to a hall or the command hall (stock 7/7)" % (rule, r))
    # H1-H3 the station: maint backs, routes
    back = Counter()
    for k, p, a, b in J:
        if k == "airlock":
            for x, y in ((a, b), (b, a)):
                if y.startswith("/area/maintenance") and not x.startswith(("/area/maintenance", "/area/hallway")):
                    back[group_of(x) or "other"] += 1
    for g, lo, txt in (("security", 3, "3-9"), ("command", 1, "1-3")):
        if back[g] < lo:
            bad("main" if g == "security" else "bridge", "H1 %s has %d maint back doors (stock %s; 7/7 and 6/7 have the minimum)" % (g, back[g], txt))
    R = routes(m, J)
    rad = R["radius"]
    arr = R["arrivals"]
    if arr:
        c = arr.get("command")
        if c is None or c / rad > 1.0:
            bad("bridge", "H2 arrivals to command's nearest door %s radii (stock 0.33-0.93)" % (
                "-" if c is None else "%.2f" % (c / rad)))
        near = [arr[g] / rad for g in ("civic", "service", "dorms") if g in arr]
        if not near or min(near) > 0.35:
            bad("bridge", "H3 arrivals to the nearest civic/service/dorms door %s radii (stock 0.02-0.22)" % (
                "-" if not near else "%.2f" % min(near)))
        s = arr.get("security")
        if s is None or s / rad > 1.5:
            bad("brig", "H2b arrivals to Security's front %s radii (stock 0.67-1.43)" % ("-" if s is None else "%.2f" % (s / rad)))
    return out


def _hop_desk_hall(m, J):
    for k, p, a, b in J:
        if k == "desk" and ((role_of(a) == "hop" and is_hall(b)) or (role_of(b) == "hop" and is_hall(a))
                            or (role_of(a) == "hop" and b.startswith("/area/hallway")) or
                            (role_of(b) == "hop" and a.startswith("/area/hallway"))):
            return True
    return False


def _hop_airlock_on_hall(m):
    """bot_hopping.dm department_doorstep: an airlock on a HoP-area tile with a hallway tile beside it."""
    for (x, y, z), t in m.tiles.items():
        if z == 1 and t.has(AIRLOCK) and role_of(t.apath) == "hop" and not t.has(AIRLOCK + "/external"):
            for dx, dy in N4:
                n = m.get(x + dx, y + dy)
                if _walk(n) and n.apath.startswith("/area/hallway"):
                    return True
    return False


LAWYER = {38, 42, 63}


def _opens(t, acc):
    """A door tile whoever holds access set `acc` walks through (airlocks by their access; windoors and shutters no)."""
    if t.has(WINDOOR) or t.has("/obj/machinery/door/poddoor"):
        return False
    a = next((o for o in t.objs if o.path.startswith(AIRLOCK)), None)
    if a is None:
        return True
    ra = (a.get("req_access_txt") or "").strip('"')
    ro = (a.get("req_one_access_txt") or "").strip('"')
    need = [int(v) for v in ra.replace(" ", "").split(";") if v.strip().isdigit() and int(v) != 0]
    one = [int(v) for v in ro.replace(" ", "").split(";") if v.strip().isdigit() and int(v) != 0]
    return all(n in acc for n in need) and (not one or any(n in acc for n in one))


def _job_path(m, acc, role):
    """BFS from the halls through doors `acc` opens (acc None: any door) to a floor tile of the role's rooms: the
    path's door tiles, or None when it can't get there."""
    halls = [(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and t.apath.startswith("/area/hallway") and _walk(t)]
    prev = {h: None for h in halls}
    q = deque(halls)
    while q:
        p = q.popleft()
        t = m.get(*p)
        if role_of(t.apath) == role and not _doorish(t):
            out = []
            while p is not None:
                if _doorish(m.get(*p)):
                    out.append(p)
                p = prev[p]
            return out
        for dx, dy in N4:
            n = (p[0] + dx, p[1] + dy)
            if n in prev:
                continue
            tn = m.get(*n)
            if not _walk(tn):
                continue
            if _doorish(tn) and acc is not None and not _opens(tn, acc):
                continue
            if _doorish(tn) and acc is None and (tn.has(WINDOOR) or tn.has("/obj/machinery/door/poddoor")):
                continue
            prev[n] = p
            q.append(n)
    return None


def _job_reaches(m, acc, role):
    return _job_path(m, acc, role) is not None


# ---------------------------------------------------------------- fixes

def fix(m, seed=1, log=print):
    r = random.Random("fn_security_command|%s" % seed)
    n = 0
    n += fix_cells(m, r, log)
    n += fix_doors(m, log)
    n += fix_add_doors(m, log)
    n += fix_desks(m, seed, log)
    n += fix_front_desk(m, r, log)
    n += fix_hop_queue(m, log)
    n += fix_gear(m, r, log)
    n += fix_lawyer(m, log)
    log("fn_security_command: %d changes" % n)
    return n


def _mount(o, side):
    """A wall piece hung on its tile's `side` wall (1 n, 2 s, 4 e, 8 w)."""
    v = DIRV[side]
    o.vars = [(k, val) for k, val in o.vars if k not in ("pixel_x", "pixel_y")]
    if v[0]:
        o.vars.append(("pixel_x", str(32 * v[0])))
    if v[1]:
        o.vars.append(("pixel_y", str(32 * v[1])))
    return o


def _hung_on(m, w):
    """Pieces hung on wall tile w (from any of its floor neighbours)."""
    out = []
    for dx, dy in N4:
        p = (w[0] - dx, w[1] - dy)
        t = m.get(*p)
        if t is None:
            continue
        for o in t.objs:
            if CO.mounted(o) and DIRV.get(CO.mount_side(o)) == (dx, dy):
                out.append((p, o))
    return out


def _free_wall_spot(m, tiles, near, avoid=()):
    """(floor tile, side) in `tiles` with a bare wall on that side, nearest `near`: for a wall piece."""
    best = None
    for p in tiles:
        t = m.get(*p)
        if not _floor(t):
            continue
        for dx, dy in N4:
            w = (p[0] + dx, p[1] + dy)
            tw = m.get(*w)
            if tw is None or not tw.tpath.startswith("/turf/closed/wall") or w in avoid:
                continue
            if _hung_on(m, w):
                continue
            d = abs(p[0] - near[0]) + abs(p[1] - near[1])
            if best is None or (d, p) < best[:2]:
                best = (d, p, VDIR[(dx, dy)])
    return None if best is None else (best[1], best[2])


def _reached(m, piece, doors):
    """Floor of the piece reached from its door tiles, walking round dense pieces."""
    starts = [q for d in doors for q in ((d[0] + dx, d[1] + dy) for dx, dy in N4) if q in piece]
    seen, st = set(), list(starts)
    while st:
        p = st.pop()
        if p in seen or p not in piece:
            continue
        t = m.get(*p)
        if any(FN.is_dense(o) for o in t.objs):
            continue
        seen.add(p)
        for dx, dy in N4:
            st.append((p[0] + dx, p[1] + dy))
    return seen


def _dense_ok(m, piece, doors, p):
    """A dense piece on p keeps every other reached floor tile reached (and p isn't a door's front)."""
    if any((p[0] + dx, p[1] + dy) in doors for dx, dy in N4):
        return False
    base = _reached(m, piece, doors)
    t = m.get(*p)
    probe = dmm.Atom("/obj/structure/closet")
    t.objs.append(probe)
    after = _reached(m, piece, doors)
    t.objs.remove(probe)
    if len(after) < len(base - {p}):
        return False
    # every dense piece someone could stand at keeps a reached tile beside it (a locker boxed in by a console)
    for q in piece:
        if q == p or not any(FN.is_dense(o) for o in m.get(*q).objs):
            continue
        nb_ = [(q[0] + dx, q[1] + dy) for dx, dy in N4]
        if any(n in base for n in nb_) and not any(n in after for n in nb_):
            return False
    return True


def _place_piece(m, piece, doors, path, vars_=(), wall=True, avoid=(), near=None):
    """Put a dense floor piece in a room on a free tile (against a wall when `wall`) that keeps the rest reached,
    nearest `near` when given; the Atom, or None."""
    def score(q):
        walls = sum(1 for dx, dy in N4 if _wallish(m.get(q[0] + dx, q[1] + dy)))
        return ((abs(q[0] - near[0]) + abs(q[1] - near[1])) if near else 0, -walls, q)
    for p in sorted(piece, key=score):
        t = m.get(*p)
        if p in avoid or any(FN.is_dense(o) for o in t.objs) or t.has("/obj/structure/bed") or \
                t.has("/obj/structure/chair") or _doorish(t) or t.has("/obj/machinery/holopad"):
            continue
        if wall and not any(_wallish(m.get(p[0] + dx, p[1] + dy)) and not _doorish(m.get(p[0] + dx, p[1] + dy))
                            for dx, dy in N4):
            continue
        if not _dense_ok(m, piece, doors, p):
            continue
        o = dmm.Atom(path, list(vars_))
        t.objs.append(o)
        return o
    return None


def _face_into(m, p, piece):
    """The dir a console on p should face: toward the room (away from its wall or window)."""
    for dx, dy in N4:
        q = m.get(p[0] + dx, p[1] + dy)
        if _wallish(q) and not _doorish(q) and (p[0] - dx, p[1] - dy) in piece:
            return VDIR[(-dx, -dy)]
    return 2


def fix_cells(m, r, log):
    """S1: the brig's one-door cells made timed cells (stock 3-4 a map)."""
    M_cells = cells(m)
    have = [c for c in M_cells if c["doors"] and len(c["interior"]) >= 2]
    if len(have) >= 3:
        return 0
    cp = [(pc, ds) for pc, ds in cell_pieces(m) if role_of(m.get(*next(iter(pc))).apath) == "brig"
          and ds[0][1] == "airlock"]
    cp.sort(key=lambda c: (-min(c[0])[1], min(c[0])[0]))
    ids = {c["id"] for c in M_cells}
    made, k = 0, 1
    for pc, ds in cp:
        if len(have) + made >= 4:
            break
        door, kind, (far_area, far_pos) = ds[0]
        v = (door[0] - far_pos[0], door[1] - far_pos[1])
        v = (max(-1, min(1, v[0])), max(-1, min(1, v[1])))
        if v not in VDIR or not _walk(m.get(*far_pos)):
            continue
        inward = VDIR[v]
        along = (v[1], v[0])
        # the timer's wall: beside the door on the outside, a bare wall tile with floor in front of it
        tspot = None
        for s in (1, -1, 2, -2):
            w = (door[0] + along[0] * s, door[1] + along[1] * s)
            stand = (far_pos[0] + along[0] * s, far_pos[1] + along[1] * s)
            tw, ts = m.get(*w), m.get(*stand)
            if tw is None or not tw.tpath.startswith("/turf/closed/wall") or not _floor(ts) or _hung_on(m, w):
                continue
            tspot = stand
            break
        tside = VDIR[v]
        if tspot is None:
            # any bare wall face of the outside floor within 3 of the door (stock timers stand 1-2 from their
            # door, Endo's 3 and 6)
            near = {(door[0] + ex, door[1] + ey) for ex in range(-3, 4) for ey in range(-3, 4)}
            lobby = next((x for x in pieces({q for q in floors(m).get(far_area, ())}) if far_pos in x), {far_pos})
            cand = {q for q in near if q in lobby}
            got = _free_wall_spot(m, cand, far_pos, avoid={door})
            if got is None:
                log("fn_security_command: cell at %d,%d: no bare wall near its door for a timer" % door)
                continue
            tspot, tside = got
        while '"Cell %d"' % k in ids:
            k += 1
        cid = '"Cell %d"' % k
        ids.add(cid)
        tdoor = m.get(*door)
        keep = [o for o in tdoor.objs if o.path.startswith(("/obj/structure/cable", "/obj/machinery/atmospherics/pipe",
                                                             "/obj/structure/disposalpipe", "/obj/machinery/door/firedoor",
                                                             "/obj/effect/turf_decal"))]
        tdoor.objs = keep + [dmm.Atom("/obj/machinery/door/window/brigdoor/security/cell/%s%s" % (
            DNAME[inward], r.choice(("left", "right"))), [("id", cid), ("name", cid)])]
        tdoor.area = dmm.Atom(far_area)
        m.get(*tspot).objs.append(_mount(dmm.Atom("/obj/machinery/door_timer", [("id", cid), ("name", cid)]), tside))
        inner = cell_interior(m, door, inward) or pc
        # a cell holds a bed, its locker and maybe a toilet: the waiting-room chairs and tables a carved piece got go
        for q in inner:
            tq = m.get(*q)
            if tq.has("/obj/structure/table"):
                tq.objs = [o for o in tq.objs if not (o.path.startswith("/obj/structure/table") or
                                                      (o.path.startswith("/obj/item") and not CO.mounted(o)))]
            tq.objs = [o for o in tq.objs if not o.path.startswith(("/obj/structure/chair", "/obj/machinery/computer"))]
        spot = _free_wall_spot(m, inner, (door[0] + 3 * v[0], door[1] + 3 * v[1]))
        if spot:
            m.get(*spot[0]).objs.append(_mount(dmm.Atom("/obj/machinery/flasher", [("id", cid)]), spot[1]))
        loc = next(((p, o) for p in inner for o in m.get(*p).objs if o.path.startswith(
            "/obj/structure/closet/secure_closet/brig")), None)
        if loc:
            loc[1].vars = [(k_, v_) for k_, v_ in loc[1].vars if k_ != "id"] + [("id", cid)]
        else:
            cl = next(((p, o) for p in inner for o in m.get(*p).objs if o.path in (
                "/obj/structure/closet", "/obj/structure/closet/secure_closet", "/obj/structure/closet/crate")), None)
            if cl:
                cl[1].path = "/obj/structure/closet/secure_closet/brig"
                cl[1].vars = [("id", cid)]
            else:
                o = _place_piece(m, inner, [door], "/obj/structure/closet/secure_closet/brig", [("id", cid)],
                                 near=(door[0] + 3 * v[0], door[1] + 3 * v[1]))
                # a spare brig locker outside the cells goes (the audit's per-map count: 3-4, one a cell)
                spare = next(((q, x) for q in sorted(floors(m).get(far_area, ())) for x in m.get(*q).objs
                              if o is not None and x.path == "/obj/structure/closet/secure_closet/brig"
                              and x.get("id") is None and q not in inner), None)
                if spare:
                    m.get(*spare[0]).objs = [x for x in m.get(*spare[0]).objs if x is not spare[1]]
        if not any(m.get(*p).has("/obj/structure/bed") for p in inner):
            free = [p for p in sorted(inner) if not any(FN.is_dense(o) for o in m.get(*p).objs)
                    and not any((p[0] + dx, p[1] + dy) == door for dx, dy in N4)]
            if free:
                m.get(*free[-1]).objs.append(dmm.Atom("/obj/structure/bed"))
        made += 1
        k += 1
        log("fn_security_command: %s at %d,%d timed (timer %d,%d)" % (cid, door[0], door[1], tspot[0], tspot[1]))
    if made:
        _tidy_brig_lockers(m, log)
    return made


def _tidy_brig_lockers(m, log):
    """Brig lockers synth copied with a stock cell's id ("Cell 4", "engcell") outside any timed cell: a spare in the
    brig goes (one a cell is the stock count), any other loses the id (a timer would lock it from 20 tiles)."""
    inside = {}
    for c in cells(m):
        for q in c["interior"]:
            inside[q] = c["id"]
    lock = [((x, y), o) for (x, y, z), t in m.tiles.items() if z == 1 for o in t.objs
            if o.path == "/obj/structure/closet/secure_closet/brig"]
    for q, o in lock:
        if q in inside and o.get("id") == inside[q]:
            continue
        if role_of(m.get(*q).apath) in ("brig", "sec_corr") and q not in inside:
            m.get(*q).objs = [x for x in m.get(*q).objs if x is not o]
            log("fn_security_command: spare brig locker at %d,%d taken out (each cell has its own)" % q)
        elif o.get("id") is not None:
            o.vars = [(k_, v_) for k_, v_ in o.vars if k_ != "id"]


def _reach_any(m, starts, maint=True):
    """Tiles walked to from starts. maint False: never over maintenance floor (a room reached only that way has no
    proper way in: the gate's "ways in")."""
    seen, q = set(starts), list(starts)
    while q:
        p = q.pop()
        for dx, dy in N4:
            n = (p[0] + dx, p[1] + dy)
            t = m.get(*n)
            if n not in seen and _walk(t) and (maint or not t.apath.startswith("/area/maintenance")):
                seen.add(n)
                q.append(n)
    return seen


def _all_reached(m, areas):
    halls = [(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and t.apath.startswith("/area/hallway") and _walk(t)]
    # (not through maint: with the brig's door walled the HoS's office was left its maint door alone, and that door
    # then "kept" as the only way in, f39: /area/crew_quarters/heads/hos, education and processing failed "ways in")
    seen = _reach_any(m, halls, maint=False)
    F = floors(m)
    # every piece of each area (an L-shaped vault is two pieces joined by its doors): one reached tile each
    return all(any(p in seen for p in pc) for a in areas if F.get(a) for pc in pieces(F[a]) if len(pc) >= 2)


UNDER = ("/obj/structure/cable", "/obj/machinery/atmospherics/pipe", "/obj/structure/disposalpipe")


def _wall_up(m, p, wall="/turf/closed/wall"):
    t = m.get(*p)
    old = (t.turf, t.objs)
    t.turf = dmm.Atom(wall)
    t.objs = [o for o in t.objs if o.path.startswith(UNDER)]
    return old


def fix_doors(m, log):
    """S4/S12: doors between kinds of room no stock map joins, walled up when both rooms stay reached from the halls
    (access aside); public-side doors first (a hall into the education chamber, a courtroom into the range)."""
    J = joins(m)
    todo = []
    for k, p, a, b in J:
        if k in ("airlock", "windoor") and not stock_pair(a, b):
            pr = _pair(a, b)
            if set(pr) & {"upload", "tcomms_ctrl"}:
                continue            # the composed AI block's own doors (the AI pass judges them)
            # the public side first, then the armory, vault and prison, then the rooms the public walks into
            first = 0 if "hall" in pr else (1 if set(pr) & {"armory", "vault", "prison"} else (
                2 if set(pr) & {"courtroom", "lawoffice"} else 3))
            todo.append((first, p, a, b))
    made = 0
    for first, p, a, b in sorted(todo):
        t = m.get(*p)
        nb = [m.get(p[0] + dx, p[1] + dy) for dx, dy in N4]
        wall = "/turf/closed/wall/r_wall" if any(q is not None and q.tpath.startswith("/turf/closed/wall/r_wall") for q in nb) \
            else "/turf/closed/wall"
        old = _wall_up(m, p, wall)
        if _all_reached(m, [x for x in (a, b) if not is_hall(x)]):
            made += 1
            log("fn_security_command: walled up the door %s <-> %s at %d,%d" % (_pair(a, b) + p))
        else:
            t.turf, t.objs = old
            log("fn_security_command: kept the door %s <-> %s at %d,%d (a room's only way in: layout)" % (_pair(a, b) + p))
    return made


# doors to add: (role, toward, rule) in order; toward 'hall', 'maint' or a role
ADD = (("hop", "hall", "C3b"), ("courtroom", "hall", "S8"), ("detective", "hall", "S9"), ("lawoffice", "hall", "S14"), ("hos", "main", "S5"),
       ("detective", "maint", "S9"), ("lawoffice", "maint", "S14"), ("main", "maint", "H1"), ("labor", "maint", "H1"),
       ("courtroom", "maint", "H1"), ("range", "maint", "H1"), ("captain", "maint", "H1"), ("gateway", "maint", "H1"),
       ("eva", "maint", "H1"), ("teleporter", "maint", "H1"), ("bridge", "maint", "H1"))
MAINT_MIN = {"security": 3, "command": 1}


def _target_ok(area, toward):
    if toward == "hall":
        return is_hall(area)
    if toward == "maint":
        return area.startswith("/area/maintenance")
    return role_of(area) == toward


def _door_spots(m, tiles, toward, doors):
    """[(wall tile, room tile, far tile)] straight plain wall (or a window run's tile) between the room and the
    target, both sides free floor, no door within 2, nothing hung on either face."""
    out = []
    for p in tiles:
        for dx, dy in N4:
            w, q = (p[0] + dx, p[1] + dy), (p[0] + 2 * dx, p[1] + 2 * dy)
            tw, tq = m.get(*w), m.get(*q)
            if tw is None or tq is None or not _floor(tq) or not _target_ok(tq.apath, toward):
                continue
            wallish = tw.tpath.startswith("/turf/closed/wall") and not tw.tpath.startswith("/turf/closed/wall/r_wall")
            glass = tw.tpath.startswith("/turf/open") and any(o.path.startswith(WINDOWS) for o in tw.objs)
            if not (wallish or glass) or any(not o.path.startswith(UNDER + WINDOWS + ("/obj/effect",)) for o in tw.objs):
                continue
            along = (dy, dx)
            if not all(_wallish(m.get(w[0] + s * along[0], w[1] + s * along[1])) for s in (1, -1)):
                continue
            if any(abs(w[0] - d[0]) + abs(w[1] - d[1]) <= 2 for d in doors):
                continue
            if any(FN.is_dense(o) for o in m.get(*p).objs) or any(FN.is_dense(o) for o in tq.objs):
                continue
            out.append((w, p, q))
    return out


def fix_add_doors(m, log):
    """S5, S8, S9, S14, H1: the doors the stock maps give these rooms where a plain wall allows one."""
    import doordb as DD
    made = 0
    F = floors(m)
    doors = {(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and _doorish(t)}
    J = joins(m)
    RL = role_links(J)
    back = Counter()
    for k, p, a, b in J:
        if k == "airlock":
            for x, y in ((a, b), (b, a)):
                if y.startswith("/area/maintenance") and not x.startswith(("/area/maintenance", "/area/hallway")):
                    back[group_of(x) or "other"] += 1
    for role, toward, rule in ADD:
        areas = [a for a in F if role_of(a) == role]
        if not areas:
            continue
        g = group_of(areas[0])
        if toward == "maint":
            if back[g] >= MAINT_MIN.get(g, 0) or RL[role].get("maint") == "airlock":
                continue
        elif RL[role].get(toward) == "airlock":
            continue
        if toward == "hall" and RL[role].get("hall") == "airlock":
            continue
        tiles = [p for a in areas for p in F[a]]
        sp = _door_spots(m, tiles, toward, doors)
        if not sp:
            continue
        cx = sum(p[0] for p in tiles) / float(len(tiles))
        cy = sum(p[1] for p in tiles) / float(len(tiles))
        # bare walls first, then the middle of the shared wall; what hangs on a wall moves along it (desks._shift)
        sp.sort(key=lambda s: (len(_hung_on(m, s[0])), abs(s[0][0] - cx) + abs(s[0][1] - cy), s[0]))
        import desks as D
        hung = D._hung(m)
        dset = {(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and t.has("/obj/machinery/door")}
        got = None
        for w, p, q in sp:
            if w in hung and not D._shift(m, w, hung, ((w[1] - p[1]) and 1 or 0, (w[0] - p[0]) and 1 or 0), dset):
                continue
            got = (w, p, q)
            break
        if got is None:
            continue
        w, p, q = got
        inner = m.get(*p).apath
        outer = "hall" if toward == "hall" else ("maint" if toward == "maint" else "room")
        st = DD.lookup(inner, outer).most_common(1)[0][0]
        path = st[0]
        if toward == "maint" and not path.startswith(AIRLOCK + "/maintenance"):
            path = AIRLOCK + "/maintenance"
        vars_ = [("name", '"%s"' % DD.name_for(inner, outer).strip('"'))]
        if st[1]:
            vars_.append((st[1], st[2]))
        tw = m.get(*w)
        tw.turf = dmm.Atom("/turf/open/floor/plating" if toward == "maint" else m.get(*p).tpath)
        tw.area = dmm.Atom(inner)
        tw.objs = [o for o in tw.objs if o.path.startswith(UNDER)] + [dmm.Atom(path, vars_),
                                                                        dmm.Atom("/obj/machinery/door/firedoor")]
        doors.add(w)
        if toward == "maint":
            back[g] += 1
        made += 1
        log("fn_security_command: %s %s door %s -> %s at %d,%d" % (rule, path.split("/")[-1], role, toward, w[0], w[1]))
    return made


def fix_desks(m, seed, log):
    """S3, C3: Brig Control's and the HoP's desks through desks.py's counter code (chance 1)."""
    import desks as D
    want = []
    J = joins(m)
    if any(role_of(a) == "warden" for a in floors(m)) and not any(
            k == "desk" and "warden" in (role_of(a), role_of(b)) for k, p, a, b in J):
        want.append("/area/security/warden")
    if any(role_of(a) == "hop" for a in floors(m)) and not _hop_desk_hall(m, J):
        want.append("/area/crew_quarters/heads/hop")
    if not want:
        return 0
    old = D.COUNTERS
    try:
        D.COUNTERS = [tuple(c[:3]) + (1.0,) + tuple(c[4:]) for c in old if c[0] in want]
        made = D.fix(m, seed, log)
    finally:
        D.COUNTERS = old
    return made


def fix_front_desk(m, r, log):
    """S7b: a front desk from the brig's hall (the security corridor) onto the public hall beside the front doors
    (stock 5/7: a windoor counter where the public reports a crime)."""
    import desks as D
    J = joins(m)
    if any(k == "desk" and {_tag(a), _tag(b)} & {"brig", "sec_corr"} and (is_hall(a) or is_hall(b)) for k, p, a, b in J):
        return 0
    F = floors(m)
    for owner in ("/area/security", "/area/security/brig"):
        if owner not in F:
            continue
        doors = {(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and t.has("/obj/machinery/door")}
        hung = D._hung(m)
        sp = D.spots(m, F[owner], owner, D.HALL, hung, doors)
        sp = [s for s in sp if not s[3]]
        if not sp:
            continue
        # nearest the front doors
        fr = [p for k, p, a, b in J if k == "airlock" and owner in (a, b) and (is_hall(a) or is_hall(b))]
        sp.sort(key=lambda s: (min([abs(s[0][0] - f[0]) + abs(s[0][1] - f[1]) for f in fr] or [0]), s[0]))
        w, step, along, block = sp[0]
        if w in hung and not D._shift(m, w, hung, along, doors):
            continue
        inner = m.get(w[0] + step[0], w[1] + step[1])
        t = m.get(*w)
        t.turf = dmm.Atom(inner.tpath)
        t.area = dmm.Atom(owner)
        t.objs = [o for o in t.objs if o.path.startswith(D.UNDER)] + D.counter_objs("secure", step, "Security Desk", "63", r)
        log("fn_security_command: S7b security front desk at %d,%d" % w)
        return 1
    return 0


def fix_hop_queue(m, log):
    """C3: the queue in front of the HoP's desk, as Meta, Box, Delta, Pubby mark it: the customer's tile (delivery
    decal, the HoP's flasher), three queue tiles along the wall (bot decals), the loading-area decal on the desk."""
    J = joins(m)
    made = 0
    for k, p, a, b in J:
        if k != "desk" or not ((role_of(a) == "hop" and b.startswith("/area/hallway")) or
                               (role_of(b) == "hop" and a.startswith("/area/hallway"))):
            continue
        s = sides(m, *p)
        hall = s[0] if s[0][0].startswith("/area/hallway") else s[1]
        front = hall[1]
        v = (front[0] - p[0], front[1] - p[1])
        along = (v[1], v[0])
        ft = m.get(*front)
        if ft.has("/obj/effect/turf_decal/delivery"):
            continue
        ft.objs.append(dmm.Atom("/obj/effect/turf_decal/delivery"))
        ids = {(o.path.split("/")[3], o.get("id")) for t_ in m.tiles.values() for o in t_.objs
               if o.path.startswith(("/obj/machinery/flasher", "/obj/machinery/button"))}
        flash = ("flasher", '"hopflash"') not in ids
        if flash:
            ft.objs.append(dmm.Atom("/obj/machinery/flasher", [("id", '"hopflash"'), ("pixel_y", "0")]))
        dt = m.get(*p)
        if not dt.has("/obj/effect/turf_decal/loading_area"):
            dt.objs.append(dmm.Atom("/obj/effect/turf_decal/loading_area", [("dir", str(VDIR[(-v[0], -v[1])]))]))
        # the queue: along the wall on the side with free hall floor
        for sgn in (1, -1):
            line = [(front[0] + along[0] * sgn * i, front[1] + along[1] * sgn * i) for i in (1, 2, 3)]
            if all(_floor(m.get(*q)) and m.get(*q).apath.startswith("/area/hallway") and
                   not any(FN.is_dense(o) for o in m.get(*q).objs) for q in line):
                for q in line:
                    m.get(*q).objs.append(dmm.Atom("/obj/effect/turf_decal/bot"))
                break
        # the flasher's button inside, beside the desk
        inner = s[0] if s[0] is not hall else s[1]
        if flash and ("button", '"hopflash"') not in ids:
            it = m.get(*inner[1])
            it.objs.append(dmm.Atom("/obj/machinery/button/flasher", [("id", '"hopflash"'),
                                                                       ("pixel_x", str(24 if along[0] else 0)),
                                                                       ("pixel_y", str(24 if along[1] else 0))]))
        made += 1
        log("fn_security_command: C3 HoP queue in front of the desk at %d,%d" % p)
    return made


def fix_gear(m, r, log):
    """S3b, S6: Brig Control's own kit (the warden's locker, the prisoner management and camera consoles) and the
    officers' lockers in Security."""
    F = floors(m)
    made = 0
    K = kit(m, F)
    wa = [a for a in F if role_of(a) == "warden"]
    if wa:
        pc = max(pieces(F[wa[0]]), key=len)
        doors = [d for d, k, far in piece_doors(m, pc)]
        if not has(K["warden"], "/obj/structure/closet/secure_closet/warden"):
            sec = next(((p, o) for p in sorted(pc) for o in m.get(*p).objs if o.path in (LOCKER_SEC + "/sec", LOCKER_SEC)), None)
            if sec and sum(has(K[x], LOCKER_SEC + "/sec") for x in SEC) > 4:
                sec[1].path = "/obj/structure/closet/secure_closet/warden"
                sec[1].vars = []
            else:
                _place_piece(m, pc, doors, "/obj/structure/closet/secure_closet/warden")
            made += 1
            log("fn_security_command: S3b warden's locker in Brig Control")
        # a small Brig Control (stock 44-107 tiles when it holds the officers' lockers: Meta, Endo) hands its
        # officers' lockers on to the Security Office (Box, Donut, Hippie, Pubby keep them there)
        ma = [a for a in F if role_of(a) == "main"]
        if ma and len(pc) < 40:
            mpc = max(pieces(F[ma[0]]), key=len)
            mdoors = [d for d, k, far in piece_doors(m, mpc)]
            sl = [(p, x) for p in sorted(pc) for x in m.get(*p).objs if x.path == LOCKER_SEC + "/sec"]
            moved = 0
            for p, x in sl[1:]:
                if _place_piece(m, mpc, mdoors, LOCKER_SEC + "/sec") is None:
                    break
                m.get(*p).objs = [y for y in m.get(*p).objs if y is not x]
                moved += 1
            if moved:
                made += moved
                log("fn_security_command: S3b %d officers' lockers moved from Brig Control (%d tiles) to the Security "
                    "Office" % (moved, len(pc)))
        for name, path, pre, ex in (("prisoner management console", "/obj/machinery/computer/prisoner",
                                     "/obj/machinery/computer/prisoner", False),
                                    ("security camera console", "/obj/machinery/computer/security",
                                     "/obj/machinery/computer/security", True),
                                    ("security records console", "/obj/machinery/computer/secure_data",
                                     "/obj/machinery/computer/secure_data", False)):
            if has(kit(m, F)["warden"], pre, ex):
                continue
            # a spare security locker or the extra vendor gives way first in a crammed office
            o = _place_piece(m, pc, doors, path)
            if o is None:
                # a spare piece against a wall gives its tile: a plain closet, the wardrobe vendor, an officers'
                # locker while Security keeps 6+ (stock 6-8)
                nsec = sum(has(kit(m, F)[x], LOCKER_SEC + "/sec") for x in SEC)
                order = ("/obj/structure/closet", "/obj/machinery/vending/wardrobe/sec_wardrobe", LOCKER_SEC + "/sec")
                spare = sorted(((order.index(x.path), p, x) for p in pc for x in m.get(*p).objs if x.path in order
                                and (x.path != LOCKER_SEC + "/sec" or nsec > 6)
                                and any(_wallish(m.get(p[0] + dx, p[1] + dy)) and not _doorish(m.get(p[0] + dx, p[1] + dy))
                                        for dx, dy in N4)), key=lambda e: (e[0], e[1]))
                if spare:
                    _, sp_, sx = spare[0]
                    m.get(*sp_).objs = [x for x in m.get(*sp_).objs if x is not sx] + (
                        [] if sx.path != "/obj/structure/closet" else [])
                    o = dmm.Atom(path)
                    m.get(*sp_).objs.append(o)
                    log("fn_security_command: %s gave its place in Brig Control to the %s" % (sx.path.split("/")[-1], name))
            if o is not None:
                at = next(p for p in pc if any(x is o for x in m.get(*p).objs))
                o.vars = [("dir", str(_face_into(m, at, pc)))]
                made += 1
                log("fn_security_command: S3b %s in Brig Control at %d,%d" % ((name,) + at))
    return made


def fix_lawyer(m, log):
    """S15: the doors on the lawyer's way to the law office and courtroom take the brig's outer-door access too (63,
    ACCESS_SEC_DOORS: the stock brig's front door asks for it, the lawyer holds it)."""
    made = 0
    for r in ("lawoffice", "courtroom"):
        if not any(role_of(a) == r for a in floors(m)) or _job_reaches(m, LAWYER, r):
            continue
        path = _job_path(m, None, r)
        if not path:
            continue
        for p in path:
            t = m.get(*p)
            a = next((o for o in t.objs if o.path.startswith(AIRLOCK)), None)
            if a is None or _opens(t, LAWYER):
                continue
            ra = (a.get("req_access_txt") or "").strip('"')
            ro = (a.get("req_one_access_txt") or "").strip('"')
            if ra and ";" in ra:
                continue                # needs all of several: left alone
            vals = [v for v in (ro.split(";") if ro else []) + ([ra] if ra else []) if v]
            if "63" in vals:
                continue
            a.vars = [(k, v) for k, v in a.vars if k not in ("req_access_txt", "req_one_access_txt")] + [
                ("req_one_access_txt", '"%s"' % ";".join(vals + ["38" if r == "lawoffice" and ra == "38" else "63"]))]
            made += 1
            log("fn_security_command: S15 door at %d,%d opens for the lawyer too (%s)" % (p[0], p[1], ";".join(vals + ["63"])))
    return made


def main(argv):
    m = dmm.read(argv[0])
    before = check(m)
    print("check before: %d" % len(before))
    for x, y, t in before:
        print("  %3d,%3d  %s" % (x, y, t))
    if len(argv) > 1:
        fix(m, 1)
        after = check(m)
        print("check after: %d" % len(after))
        for x, y, t in after:
            print("  %3d,%3d  %s" % (x, y, t))
        dmm.write(m, argv[1])


if __name__ == "__main__":
    main(sys.argv[1:])
