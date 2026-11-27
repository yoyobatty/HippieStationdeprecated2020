"""Airlocks learned from the human maps: which airlock a room gets (medical, research, security, engineering,
maintenance hatch, glass or not), the access it asks for and its name, by the room it leads into and what lies on
its other side. A styling pass gives a generated station's plain doors the same.

    python tools/mapforge/gen/learn/doordb.py                  # build data/mapforge/learn/doors.json, print a summary
    python tools/mapforge/gen/learn/doordb.py surgery          # what the model says for areas matching "surgery"
    from gen.learn import doordb; doordb.style(m, seed, log)    # restyle a built station's plain airlocks

The user 2026-11-26: "a few airlocks ... wrong airlock colour or type". 228 of 256 airlocks on crew 100 seed 7 were
the plain grey civilian airlock with no access: the learned floorplans and the connect pass put
/obj/machinery/door/airlock everywhere, so the armoury, the AI upload's foyer and the CMO's office opened for anyone.

A door record: the room it leads into ("inner"), the kind of place on its other side (hall, maint, space, room, same
room), that place's area, the airlock's path, its access var and its name. The inner room: the room side when the
other is hall, maint or space; the door tile's own area when both sides are rooms (on the human maps a door tile
belongs to the room it opens), the smaller room on a generated map (door tiles there carry the corridor's area).

Styling keeps every airlock that has a name (copied rooms, the engine, docks, solars, the AI satellite): only the
nameless plain and maintenance airlocks the generator made are restyled. Afterwards every room the human maps keep
public (most of their hall doors ask for no access: lobby, bar, chapel, library, dorms) is made reachable from the
halls without access, clearing the access of the doors on the cheapest way in (corridors before rooms).
"""
import json
import os
import random
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", ".."))
from forge import corpus as CO, dmm  # noqa: E402

OUT = os.path.join(CO.ROOT, "data", "mapforge", "learn", "doors.json")
VERSION = 2
AIRLOCK = "/obj/machinery/door/airlock"
N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
ACCESS = ("req_access_txt", "req_one_access_txt")
# a generated department's corridor stands for the human room that plays its part (its doors are that room's doors):
# the command block's corridor (/area/crew_quarters/heads) is not the captain's office, the security block's
# (/area/security) not the armoury
CORR_AS = {"/area/crew_quarters/heads": "/area/bridge", "/area/security": "/area/security/main",
           "/area/medical/medbay": "/area/medical/medbay/central", "/area/science": "/area/science/research",
           "/area/engine": "/area/engine/engineering", "/area/quartermaster": "/area/quartermaster/office",
           "/area/crew_quarters": "/area/hallway/primary/central", "/area/chapel": "/area/hallway/primary/central",
           "/area/crew_quarters/dorms": "/area/crew_quarters/dorms", "/area/engine/atmos": "/area/engine/atmos",
           "/area/ai_monitored/turret_protected": "/area/ai_monitored/turret_protected/aisat_interior"}
# departments of their own below another's area: their doors don't teach the parent's fallback (Atmospherics' doors
# are not engineering's, the heads' offices not the service block's)
SPLIT = ("/area/engine/atmos", "/area/crew_quarters/heads", "/area/crew_quarters/dorms",
         "/area/ai_monitored/turret_protected", "/area/medical/virology")
PUBLIC = 0.5        # a room is public when the public reaches at least this share of its floor on the human maps
RARE = 0.15         # a style under this share of its key's doors is never picked (one map's oddity)
# airlocks that belong to one place only: never a generated room's door (an /external door in medbay)
#   (material doors stay: the vault's vault door, the cold room's freezer door, the library's wood door are learned for
#   those rooms, and RARE drops one map's whim)
ODD = tuple(AIRLOCK + s for s in ("/external", "/centcom", "/abductor", "/shuttle", "/cult", "/survival", "/titanium",
                                  "/glass_large", "/hatch/syndicate"))


def kind(area, turf=""):
    if turf.startswith("/turf/open/space") or area.startswith(("/area/space", "/area/solar", "/area/shuttle")):
        return "space"
    if area.startswith("/area/hallway"):
        return "hall"
    if area.startswith("/area/maintenance"):
        return "maint"
    return "room"


def _open(t):
    return t is not None and t.tpath.startswith("/turf/open") and not CO.solid(t)


def _door(t):
    return t is not None and any(o.path.startswith("/obj/machinery/door") and not o.path.startswith(
        "/obj/machinery/door/firedoor") for o in t.objs)


def sides(m, x, y):
    """The two places a door at x, y joins: [(area, turf, (x, y)) past any doors in the way] along the axis whose both
    ends are open, or None (a door into a wall)."""
    for ax in ((1, 0), (0, 1)):
        out = []
        for s in (1, -1):
            d = (ax[0] * s, ax[1] * s)
            p = (x + d[0], y + d[1])
            k = 0
            while _door(m.get(*p)) and k < 3:
                p = (p[0] + d[0], p[1] + d[1])
                k += 1
            t = m.get(*p)
            if not _open(t) and not (t is not None and t.tpath.startswith("/turf/open/space")):
                break
            out.append((t.apath, t.tpath, p))
        if len(out) == 2:
            return out
    return None


def inner_outer(a, b, own=None, size=None):
    """(inner area, outer kind, outer area) of a door between places a and b ((area, turf, pos) each). own: the door
    tile's area (human maps); size: area -> tiles (generated maps: the smaller room is the inner one)."""
    ka, kb = kind(a[0], a[1]), kind(b[0], b[1])
    rank = {"room": 3, "maint": 2, "hall": 1, "space": 0}
    if ka == kb == "room":
        if a[0] == b[0]:
            return a[0], "same", a[0]
        if own in (a[0], b[0]):
            i = a if own == a[0] else b
        elif size is not None:
            i = a if size.get(a[0], 0) <= size.get(b[0], 0) else b
        else:
            i = a
        o = b if i is a else a
        return i[0], "room", o[0]
    i, o = (a, b) if rank[ka] >= rank[kb] else (b, a)
    return i[0], kind(o[0], o[1]), o[0]


def _acc(o):
    for k in ACCESS:
        v = o.get(k)
        if v is not None and v.strip('"'):
            return (k, v)
    return ("", "")


def free_reach(m, halls):
    """The open floor reached from the given hall tiles through airlocks that ask for no access."""
    seen, q = set(halls), list(halls)
    while q:
        p = q.pop()
        for dx, dy in N4:
            n = (p[0] + dx, p[1] + dy)
            t = m.get(*n)
            if n in seen or not _walk(t) or _locked(t) or _shut(t):
                continue
            seen.add(n)
            q.append(n)
    return seen


def _shut(t):
    """A door no one opens by walking into it: blast doors, shutters, windoors (they ask for access of their own)."""
    return any(o.path.startswith(("/obj/machinery/door/poddoor", "/obj/machinery/door/window")) for o in t.objs)


def mine(path):
    m = dmm.read(path)
    out = []
    # how much of each area the public reaches from the halls without access (a lobby, the bar's front, the chapel)
    halls = [(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and t.apath.startswith("/area/hallway") and _walk(t)]
    reach = free_reach(m, halls)
    tot, got = Counter(), Counter()
    for (x, y, z), t in m.tiles.items():
        if z == 1 and _walk(t) and kind(t.apath) == "room" and not _door(t):
            tot[t.apath] += 1
            got[t.apath] += (x, y) in reach
    out.append(["#reach", {a: [got[a], n] for a, n in tot.items()}])
    for (x, y, z), t in m.tiles.items():
        if z != 1:
            continue
        a = next((o for o in t.objs if o.path.startswith(AIRLOCK)), None)
        if a is None:
            continue
        s = sides(m, x, y)
        if s is None:
            continue
        inner, ok, oa = inner_outer(s[0], s[1], own=t.apath)
        k, v = _acc(a)
        out.append([inner, ok, oa, a.path, k, v, (a.get("name") or "").strip('"')])
    return out


def build():
    recs = []
    for rel in CO.MAPS:
        p = os.path.join(CO.ROOT, "_maps", "map_files", rel)
        if os.path.exists(p):
            recs += mine(p)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump(dict(version=VERSION, doors=recs), open(OUT, "w"))
    return recs


_M = None


def _ancestors(area):
    parts = area.split("/")
    return ["/".join(parts[:i]) for i in range(len(parts), 2, -1)]


def model():
    """exact[(inner, outer kind)] and tree[(ancestor of inner, outer kind)]: Counters of (path, access var, access);
    names[(inner, outer kind)]: Counter of names; public[area or ancestor]: [floor tiles the public reaches from the
    halls without access, floor tiles] over the human maps."""
    global _M
    if _M is None:
        recs = None
        if os.path.exists(OUT):
            d = json.load(open(OUT))
            if d.get("version") == VERSION:
                recs = d["doors"]
        if recs is None:
            recs = build()
        exact, tree, names, public = defaultdict(Counter), defaultdict(Counter), defaultdict(Counter), defaultdict(lambda: [0, 0])
        for rec in recs:
            if rec[0] == "#reach":
                for a, (g, n) in rec[1].items():
                    for an in _ancestors(a):
                        public[an][0] += g
                        public[an][1] += n
                continue
            inner, ok, oa, path, k, v, name = rec
            if path.startswith(ODD) and ok != "space":
                continue
            st = (path, k, v)
            exact[(inner, ok)][st] += 1
            exact[(inner, "*")][st] += 1
            for an in _ancestors(inner):
                if any(inner.startswith(sp) and len(sp) > len(an) for sp in SPLIT):
                    continue
                tree[(an, ok)][st] += 1
                tree[(an, "*")][st] += 1
            if name:
                names[(inner, ok)][name] += 1
                names[(inner, "*")][name] += 1
        # a style one place owns: 80%+ of its human doors lead into one area below a department (the atmos door into
        # Atmospherics, the virology door, the vault door); never given to a room outside it (an atmos door on
        # engineering's storage came from the engine family's fallback)
        uses, total = defaultdict(Counter), Counter()
        for rec in recs:
            if rec[0] != "#reach" and not rec[3].startswith(ODD):
                total[rec[3]] += 1
                for an in _ancestors(rec[0]):
                    uses[rec[3]][an] += 1
        owner = {}
        for path, c in uses.items():
            tot = total[path]
            best = [an for an, n in c.items() if n >= 0.8 * tot and len(an.split("/")) >= 4]
            if best and tot >= 3:
                owner[path] = max(best, key=lambda a: (c[a], -len(a)))
        _M = dict(exact=exact, tree=tree, names=names, public=public, owner=owner, n=len(recs), recs=recs)
    return _M


FIT_MIN = 0.03      # a styled airlock fits a door when one side's station group has this share of its human doors' sides


def _groups():
    """Airlock path -> Counter of the station groups (studies/stations.group_of) its human doors join, both sides."""
    M = model()
    if "groups" not in M:
        sys.path.insert(0, os.path.join(HERE, "..", "..", "studies"))
        import stations as ST
        g, pairs, names_p = defaultdict(Counter), defaultdict(set), defaultdict(Counter)
        for rec in M["recs"]:
            if rec[0] == "#reach":
                continue
            inner, ok, oa, path = rec[0], rec[1], rec[2], rec[3]
            gi, go = ST.group_of(inner) or "", (ST.group_of(oa) if oa else ok) or ""
            g[path][gi] += 1
            g[path][go] += 1
            pr = tuple(sorted((gi, go)))
            pairs[path].add(pr)
            if rec[6]:
                names_p[(inner, ok, pr)][rec[6]] += 1
        M["groups"], M["pairs"], M["names_p"] = g, pairs, names_p
    return M["groups"]


def odd_style(m, x, y, a, s):
    """An airlock styled before its rooms settled (a stock copy's or an exemplar's door, a room retyped later) that fits
    neither side: a department's colour where neither side is that department on any human map (crew 100 seed 7 f21:
    a medical "Cloning" door between art storage and an emergency closet), an external airlock with no space near."""
    if a.path in (AIRLOCK, AIRLOCK + "/glass") or a.path.startswith(AIRLOCK + "/maintenance"):
        return False
    if s[0][0] == s[1][0]:
        return False            # a door inside one area (the human maps' own: a security door in maint, a mining base)
    sys.path.insert(0, os.path.join(HERE, "..", "..", "studies"))
    import stations as ST
    _groups()
    if tuple(sorted(ST.group_of(q[0]) or "" for q in s)) in model()["pairs"].get(a.path, ()):
        return False            # a human door of this style joins the same two groups (the CMO's command door)
    if a.path.startswith(AIRLOCK + "/external"):
        # space beyond it, or a small airlock room with another external door (the cycling pair); f21 had one between
        # an emergency closet and a vacant office
        if any(kind(q[0], q[1]) == "space" for q in s):
            return False
        for q in s:
            seen, todo = {q[2]}, [q[2]]
            while todo and len(seen) <= 16:
                p_ = todo.pop()
                for dx, dy in N4:
                    n_ = (p_[0] + dx, p_[1] + dy)
                    t_ = m.get(*n_)
                    if n_ in seen or n_ == (x, y) or t_ is None:
                        continue
                    if _door(t_):
                        if any(o.path.startswith(AIRLOCK + "/external") for o in t_.objs):
                            return False
                        continue
                    if _open(t_) and t_.apath == q[0]:
                        seen.add(n_)
                        todo.append(n_)
        return True
    if a.path.startswith(ODD):
        return False
    sys.path.insert(0, os.path.join(HERE, "..", "..", "studies"))
    import stations as ST
    c = _groups().get(a.path)
    if not c or sum(c.values()) < 10:
        return False
    tot = float(sum(c.values()))
    return max(c[ST.group_of(q[0]) or ""] / tot for q in s) < FIT_MIN


def owned_elsewhere(path, inner):
    """The style belongs to another place (owner not inner or an ancestor of it)."""
    o = model()["owner"].get(path)
    inner = CORR_AS.get(inner, inner)
    return o is not None and not (inner == o or inner.startswith(o + "/"))


def lookup(inner, outer):
    """The learned Counter of airlock styles for a door into inner with outer beyond, most specific first."""
    M = model()
    inner = CORR_AS.get(inner, inner)
    for key in ((inner, outer),):
        if sum(M["exact"][key].values()) >= 2:
            return M["exact"][key]
    for an in _ancestors(inner):
        for ok in (outer, "*"):
            c = M["tree"].get((an, ok))
            if c and sum(c.values()) >= 2:
                return c
    return Counter({(AIRLOCK, "", ""): 1})


def public(area):
    area = CORR_AS.get(area, area)
    if area.startswith("/area/hallway"):
        return True
    M = model()
    for an in _ancestors(area):
        n0, n = M["public"].get(an, (0, 0))
        if n >= 4:
            return n0 >= PUBLIC * n
    return False


_PAIRS = None


def _near(area):
    """The area and its parent below the top level (/area/security/armory, /area/crew_quarters/heads/hos and
    /area/crew_quarters/heads; never /area/security or /area/crew_quarters alone)."""
    a = CORR_AS.get(area, area)
    out = [a]
    parts = a.split("/")
    if len(parts) >= 5:
        out.append("/".join(parts[:-1]))
    return out


def pair_seen(a, b):
    """A door between areas a and b (or their parents) exists on a human map; halls, maint, space and the same area
    always pass. Doors between kinds of room no stock map joins came from compose.second_doors and doorcount (crew 100
    seed 7 f22: 13, the armory into the law office, the vault into EVA, the captain's office only through the
    teleporter; gen/learn/fn_security_command.py S12)."""
    global _PAIRS
    if a == b or kind(a) != "room" or kind(b) != "room":
        return True
    if _PAIRS is None:
        _PAIRS = set()
        for rec in model()["recs"]:
            if rec[0] == "#reach" or not rec[2]:
                continue
            for x in _near(rec[0]):
                for y in _near(rec[2]):
                    _PAIRS.add((x, y))
                    _PAIRS.add((y, x))
    return any((x, y) in _PAIRS for x in _near(a) for y in _near(b))


def door_pair(s):
    """The sorted pair of station groups a door joins (sides() output)."""
    sys.path.insert(0, os.path.join(HERE, "..", "..", "studies"))
    import stations as ST
    return tuple(sorted(ST.group_of(q[0]) or "" for q in s))


def fits_pair(path, pair):
    """A human door of this style joins this pair of groups (or the style is too rare to say)."""
    _groups()
    c = model()["groups"].get(path)
    if not c or sum(c.values()) < 10:
        return True
    return pair in model()["pairs"].get(path, ())


def name_for(area, ok="*", pair=None):
    M = model()
    a = CORR_AS.get(area, area)
    if pair is not None:
        # the name human doors of this room have toward this kind of neighbour (port emergency storage's one human
        # room door is genetics' "Cloning": not a name for its door to art storage)
        _groups()
        c = M["names_p"].get((a, ok, pair))
        if c:
            return c.most_common(1)[0][0]
        keys = ((a, "*"),)
    else:
        keys = ((a, ok), (a, "*"))
    for key in keys:
        c = M["names"].get(key)
        if c:
            return c.most_common(1)[0][0]
    return a.rsplit("/", 1)[-1].replace("_", " ").title()


def _restyle(o):
    """A generated airlock: nameless plain or maintenance airlock."""
    return o.path in (AIRLOCK, AIRLOCK + "/maintenance", AIRLOCK + "/glass") and o.get("name") is None


def style(m, seed=1, log=print):
    """Restyle the generator's plain airlocks by the learned model, then open the public rooms' way in. Returns how
    many were restyled."""
    size = Counter(t.apath for t in m.tiles.values() if t.tpath.startswith("/turf/open"))
    picks = {}
    n, kinds, odd = 0, Counter(), 0
    for (x, y, z), t in sorted(m.tiles.items()):
        a = next((o for o in t.objs if o.path.startswith(AIRLOCK)), None)
        if a is None:
            continue
        s = sides(m, x, y)
        if s is None:
            continue
        if not _restyle(a):
            if not odd_style(m, x, y, a, s):
                continue
            odd += 1
        if any(kind(q[0], q[1]) == "space" for q in s):
            continue
        inner, ok, oa = inner_outer(s[0], s[1], size=size)
        pair = door_pair(s)
        key = (inner, ok, pair)
        if key not in picks:
            c = lookup(inner, ok)
            r = random.Random("door|%s|%s|%s" % (seed, inner, ok))
            c = Counter({st: v for st, v in c.items() if not owned_elsewhere(st[0], inner)}) or                 Counter({_room_path(inner, ok, pair): 1})
            # only styles a human door between these two groups has (f20/f21: a medical "Cloning" door between art
            # storage and an emergency closet, from the one human emergency storage that opens on genetics)
            fit = Counter({st: v for st, v in c.items() if fits_pair(st[0], pair)})
            if not fit:
                # nothing the room's own doors have fits: its wider learned lists, else a plain airlock
                M_ = model()
                a_ = CORR_AS.get(inner, inner)
                for c2 in [M_["exact"].get((a_, "*"))] + [M_["tree"].get((an, k_)) for an in _ancestors(a_)
                                                          for k_ in (ok, "*")]:
                    fit = Counter({st: v for st, v in (c2 or {}).items() if fits_pair(st[0], pair)
                                   and not owned_elsewhere(st[0], inner) and "/maintenance" not in st[0]})
                    if fit:
                        break
            c = fit or Counter({(AIRLOCK, "", ""): 1})
            tot = sum(c.values())
            items = sorted((st, v) for st, v in c.items() if v >= RARE * tot) or [c.most_common(1)[0]]
            tot = sum(v for _, v in items)
            u, acc = r.random() * tot, 0
            for st, v in items:
                acc += v
                if u <= acc:
                    picks[key] = st
                    break
        path, k, v = picks[key]
        # a maintenance hatch only where maint is behind it; a room-to-room door never a maint hatch
        if ("/maintenance" in path) != (ok == "maint" or kind(inner) == "maint"):
            path = AIRLOCK + "/maintenance" if ok == "maint" or kind(inner) == "maint" else _room_path(inner, ok, pair)[0]
        vs = [("name", '"%s"' % name_for(inner, ok, pair))]
        if k:
            vs.append((k, v))
        t.objs[t.objs.index(a)] = dmm.Atom(path, vs)
        n += 1
        kinds[path.replace(AIRLOCK, "") or "/"] += 1
    opened = open_public(m, size, log)
    let_in = open_jobs(m, log)
    log("doors: %d airlocks restyled (%s; %d styled ones that fit neither side), %d doors opened for public rooms, "
        "%d for a department's own jobs" % (n, ", ".join("%s %d" % kv for kv in kinds.most_common(8)), odd, opened,
                                            let_in))
    return n


def open_jobs(m, log=print):
    """Every room of a department reached by its own jobs (gen/audit.py job_reach): a door on the cheapest way in
    that none of them opens also takes the access all of them share (security's 63, medical's 5), its own kept as
    the alternative. Crew 100 seed 7's Security Main was reached only through the courtroom, whose door wanted a
    lawyer's 38 (2026-11-26)."""
    import heapq
    sys.path.insert(0, os.path.join(HERE, ".."))
    sys.path.insert(0, os.path.join(HERE, "..", "..", "studies"))
    import audit as AU
    import stations as ST
    JA = AU.job_access()
    halls = [(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and t.apath.startswith("/area/hallway") and _walk(t)]
    fixed = 0
    for x, y, text in AU.job_reach(m):
        area = text.split(":", 1)[0]
        # the jobs the audit tested (one job for a piece the jobs meant to go in miss)
        jobs = tuple(text.split("none of ", 1)[1].split(" gets in", 1)[0].split("/")) if "none of " in text \
            else AU.DEPT_JOBS.get(ST.group_of(area), ())
        sets = [JA.get(j, set()) for j in jobs if JA.get(j)]
        if not sets:
            continue
        acc = set().union(*sets)
        # only a room the department's jobs are meant to enter: its own learned door access is theirs (the captain's
        # bedroom wants the captain's 20, a head of personnel's isn't enough; the armory's 3 is the warden's)
        (lp, lk, lv), _ = lookup(area, "room").most_common(1)[0]
        own = [int(v) for v in lv.strip('"').replace(" ", "").split(";") if v.isdigit() and int(v)]
        if own and not (set(own) <= acc if lk == "req_access_txt" else set(own) & acc):
            continue
        common = set.intersection(*sets) - {12}
        key = min(set(own) & acc) if set(own) & acc else (min(common) if common else 0)
        if not key:
            continue
        # the piece the audit named (the whole area's tiles reached a piece already in, and the door into the piece
        # that was shut out stayed as it was)
        area_tiles = {(a, b) for (a, b, z), t in m.tiles.items() if t.apath == area and _walk(t) and not _door(t)}
        goal = next((set(pc) for pc in AU._pieces(area_tiles) if (x, y) in pc), area_tiles)
        dist, prev = {h: 0 for h in halls}, {}
        pq = [(0, h) for h in halls]
        heapq.heapify(pq)
        end = None
        while pq:
            d, p = heapq.heappop(pq)
            if d > dist.get(p, 1e9):
                continue
            if p in goal:
                end = p
                break
            if not AU.through_ok(m.get(*p)):
                continue                # a server room or chamber ends a way, never carries it on
            for dx, dy in N4:
                n = (p[0] + dx, p[1] + dy)
                t = m.get(*n)
                if not _walk(t) or _shut(t):
                    continue
                c = 1 if AU._door_ok(t, acc) else 30
                if d + c < dist.get(n, 1e9):
                    dist[n] = d + c
                    prev[n] = p
                    heapq.heappush(pq, (d + c, n))
        p = end
        while p in prev:
            t = m.get(*p)
            if not AU._door_ok(t, acc):
                a = next(o for o in t.objs if o.path.startswith(AIRLOCK))
                old = [v.strip('"') for k, v in a.vars if k in ACCESS and v.strip('"')]
                nums = [v for o_ in old for v in o_.replace(" ", "").split(";") if v]
                a.vars = [(k, v) for k, v in a.vars if k not in ACCESS] + [
                    ("req_one_access_txt", '"%s"' % ";".join(sorted(set(nums) | {str(key)}, key=int)))]
                # the last door, into the room itself, in the room's own learned style and name (f52: a blue command
                # airlock named "Xenobiology Lab" into the research corridor)
                if prev.get(p) is not None and m.get(*prev[p]).apath != area and any(
                        m.get(p[0] + dx, p[1] + dy) is not None and m.get(p[0] + dx, p[1] + dy).apath == area
                        for dx, dy in N4) and "/maintenance" not in a.path and own:
                    a.path = lp if lp.startswith(AIRLOCK) else a.path
                    a.vars = [("name", '"%s"' % name_for(area))] + [(k, v) for k, v in a.vars if k != "name"]
                fixed += 1
            p = prev[p]
    return fixed


def _room_path(inner, ok, pair=None):
    """The most common room door style (no maint hatch, none another place owns, one that fits the door's pair of
    groups when given) for inner, from its own doors up through its ancestors' (the cryo room's human doors all lead
    to maint: medical's room doors)."""
    M = model()
    a = CORR_AS.get(inner, inner)
    cs = [M["exact"].get((a, ok)), M["exact"].get((a, "*"))]
    for an in _ancestors(a):
        cs += [M["tree"].get((an, ok)), M["tree"].get((an, "*"))]
    for c in cs:
        for (path, k, v), _ in (c.most_common() if c else ()):
            if "/maintenance" not in path and not owned_elsewhere(path, inner) and                     (pair is None or fits_pair(path, pair)):
                return (path, k, v)
    return (AIRLOCK, "", "")


def _walk(t):
    return t is not None and t.tpath.startswith("/turf/open") and not t.tpath.startswith("/turf/open/space") \
        and not CO.solid(t)


def _locked(t):
    a = next((o for o in t.objs if o.path.startswith(AIRLOCK)), None)
    return a is not None and any(a.get(k) is not None and a.get(k).strip('"') for k in ACCESS)


def open_public(m, size, log=print):
    """Every public room reached from the halls through doors that ask for no access: the doors on the cheapest way in
    lose their access (a locked door costs 20, a tile of another room 6, a corridor or hall tile 1)."""
    import heapq
    halls = [(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and t.apath.startswith("/area/hallway") and _walk(t)]
    if not halls:
        return 0
    corr = set(CORR_AS)
    reach = free_reach(m, halls)
    rooms = defaultdict(list)
    for (x, y, z), t in m.tiles.items():
        if z == 1 and _walk(t) and kind(t.apath) == "room" and not _door(t):
            rooms[t.apath].append((x, y))
    opened = 0
    for area, tiles in sorted(rooms.items()):
        if not public(area) or any(p in reach for p in tiles):
            continue
        goal = set(tiles)
        dist, prev = {}, {}
        pq = [(0, h) for h in halls]
        for h in halls:
            dist[h] = 0
        heapq.heapify(pq)
        end = None
        while pq:
            d, p = heapq.heappop(pq)
            if d > dist.get(p, 1e9):
                continue
            if p in goal:
                end = p
                break
            for dx, dy in N4:
                n = (p[0] + dx, p[1] + dy)
                t = m.get(*n)
                # a counter (a table under a windoor: gen/learn/desks.py) is no way in; routed through the cargo desk,
                # the office's own hall door kept its access (f23: "function: public rooms")
                if not _walk(t) or t.has("/obj/structure/table"):
                    continue
                c = 20 if _locked(t) else 1 if (t.apath in corr or kind(t.apath) != "room" or t.apath == area
                                                or _door(t)) else 6
                if d + c < dist.get(n, 1e9):
                    dist[n] = d + c
                    prev[n] = p
                    heapq.heappush(pq, (d + c, n))
        if end is None:
            continue
        p = end
        while p in prev:
            t = m.get(*p)
            if _locked(t):
                a = next(o for o in t.objs if o.path.startswith(AIRLOCK))
                a.vars = [(k, v) for k, v in a.vars if k not in ACCESS]
                opened += 1
            p = prev[p]
        reach = free_reach(m, halls)
    return opened


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--rebuild":
        build()
        sys.argv.pop(1)
    M = model()
    print("%d human airlocks" % M["n"])
    want = sys.argv[1] if len(sys.argv) > 1 else None
    keys = sorted(M["exact"]) if want else []
    for key in keys:
        if want in key[0] and key[1] != "*":
            c = M["exact"][key]
            print("%-44s %-6s %s" % (key[0], key[1], ", ".join("%s %s%s x%d" % (p.replace(AIRLOCK, "") or "/", k[4:7], v, n)
                                                               for (p, k, v), n in c.most_common(4))))
    if want:
        for a in sorted({k[0] for k in keys if want in k[0]}):
            print("  %-42s public %s  name %s" % (a, public(a), name_for(a)))
