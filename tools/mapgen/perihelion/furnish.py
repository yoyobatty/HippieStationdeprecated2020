"""Infrastructure (lights, APCs, power, air, landmarks) and room contents for Perihelion."""
import heapq
import os
import random
import re

import dmmlib as D
import layout as L
import rooms_data as RD

N, S, E, Wd = 1, 2, 4, 8
STEP = {N: (0, -1), S: (0, 1), E: (1, 0), Wd: (-1, 0)}
OPP = {N: S, S: N, E: Wd, Wd: E}
DIRNAME = {N: "north", S: "south", E: "east", Wd: "west"}
CABLE = "/obj/structure/cable"
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
rnd = random.Random(7)

STATS = {}


def interior(r):
    x0, y0, x1, y1 = r
    return [(x, y) for y in range(y0 + 1, y1) for x in range(x0 + 1, x1)]


def spaces():
    """(kind, name, area, rect) for every wall-line space with a floor."""
    out = []
    for name, dept, r, flags in L.ROOMS:
        out.append(("room", name, RD.ROOM_AREA[name], r))
    for name, own, r in L.HALLS:
        out.append(("hall", name, RD.HALL_AREA[name], r))
    for name, r, kind in L.WALKWAYS:
        out.append(("walkway", name, RD.WALK_AREA[name], r))
    return out


def door_fronts(g, door_tiles):
    res = set()
    for (x, y) in door_tiles:
        for d, (dx, dy) in STEP.items():
            res.add((x + dx, y + dy))
    return res


def wall_dirs(g, x, y):
    out = []
    for d, (dx, dy) in STEP.items():
        t = g.t.get((x + dx, y + dy))
        if t is not None and t.kind == "wall":
            out.append(d)
    return out


# ---------------------------------------------------------------- lights
def lights(g, door_tiles, problems):
    n = 0
    for kind, name, area, r in spaces():
        x0, y0, x1, y1 = r
        iw, ih = x1 - x0 - 1, y1 - y0 - 1
        horiz = iw >= ih
        length = iw if horiz else ih
        count = max(1, round(length / 7))
        rows = [(N, y0 + 1), (S, y1 - 1)] if horiz else [(Wd, x0 + 1), (E, x1 - 1)]
        if (ih if horiz else iw) <= 4 or kind != "room":
            rows = rows[:1] if kind == "room" else rows
        for i in range(count):
            d, line = rows[i % len(rows)]
            pos = int((i + 0.5) * length / count)
            for shift in (0, 1, -1, 2, -2):
                p = pos + shift
                if horiz:
                    x, y = x0 + 1 + p, line
                else:
                    x, y = line, y0 + 1 + p
                if not (x0 < x < x1 and y0 < y < y1):
                    continue
                t = g[x, y]
                dx, dy = STEP[d]
                if t.kind == "floor" and g[x + dx, y + dy].kind == "wall" and d not in t.mounts:
                    t.objs.append("/obj/machinery/light{dir = %d}" % d)
                    t.mounts.add(d)
                    n += 1
                    break
    # maint: small lights every ninth tile that has a wall beside it
    for (x, y), t in list(g.t.items()):
        if t.kind == "floor" and t.owner and t.owner[0] in ("maint", "tunnel") and (x * 3 + y) % 11 == 0:
            ds = [d for d in wall_dirs(g, x, y) if d not in t.mounts]
            if ds:
                t.objs.append("/obj/machinery/light/small{dir = %d}" % ds[0])
                t.mounts.add(ds[0])
                n += 1
    STATS["lights"] = n


# ---------------------------------------------------------------- APCs
def apcs(g, problems, avoid=()):
    by_area = {}
    for (x, y), t in g.t.items():
        if t.kind == "floor" and t.indoor and t.area.startswith("/area/") and not t.area.startswith("/area/space") \
                and not t.area.startswith("/area/solar") and not (t.owner and t.owner[0] == "chunk"):
            by_area.setdefault(t.area, []).append((x, y))
    placed = {}
    for area, tiles in sorted(by_area.items()):
        cx = sum(p[0] for p in tiles) / len(tiles)
        cy = sum(p[1] for p in tiles) / len(tiles)
        best = None
        for (x, y) in tiles:
            t = g[x, y]
            if any((x + dx, y + dy) in avoid for dx in (-1, 0, 1) for dy in (-1, 0, 1)):
                continue
            for d in wall_dirs(g, x, y):
                if d in t.mounts:
                    continue
                score = (x - cx) ** 2 + (y - cy) ** 2
                if t.owner and t.owner[0] in ("maint", "tunnel"):
                    score += 20
                if best is None or score < best[0]:
                    best = (score, x, y, d)
        if not best:
            problems.append("no APC spot in " + area)
            continue
        _, x, y, d = best
        g[x, y].objs.append("/obj/machinery/power/apc/auto_name/%s" % DIRNAME[d])
        g[x, y].mounts.add(d)
        placed[area] = (x, y)
    STATS["apcs"] = len(placed)
    return placed


# ---------------------------------------------------------------- routing
def route(g, targets, tree, cost, forbid, name, problems, edges=None, leaves=False):
    """Grow a tree: connect each target to the nearest tree tile. Returns (tiles, edges).

    leaves=True: targets are devices with a single connection (vents), so nothing may
    branch off them later: they stay out of the tree and out of every later path.
    """
    tree = set(tree)
    done_leaves = set()
    edges = set() if edges is None else edges
    tset = set(targets)
    for tgt in targets:
        if tgt in tree:
            continue
        dist = {tgt: 0}
        prev = {}
        pq = [(0, tgt)]
        hit = None
        while pq:
            dcur, p = heapq.heappop(pq)
            if p in tree:
                hit = p
                break
            if dcur > dist.get(p, 1e18):
                continue
            x, y = p
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                q = (x + dx, y + dy)
                if q in forbid and q not in tree:
                    continue
                if q in tset and q != tgt and (leaves or q not in tree):
                    continue  # don't run through other endpoints
                c = cost(q)
                if c is None:
                    continue
                nd = dcur + c
                if nd < dist.get(q, 1e18):
                    dist[q] = nd
                    prev[q] = p
                    heapq.heappush(pq, (nd, q))
        if hit is None:
            problems.append("%s: can't reach %s" % (name, tgt))
            continue
        p = hit
        while p != tgt:
            q = prev[p]
            edges.add(frozenset((p, q)))
            if not (leaves and q == tgt):
                tree.add(q)
            p = q
        if leaves:
            done_leaves.add(tgt)
        else:
            tree.add(tgt)
    return tree | done_leaves, edges


def mask_of(p, edges_by_tile):
    m = 0
    for q in edges_by_tile.get(p, ()):
        dx, dy = q[0] - p[0], q[1] - p[1]
        for d, s in STEP.items():
            if s == (dx, dy):
                m |= d
    return m


def by_tile(edges):
    out = {}
    for e in edges:
        a, b = tuple(e)
        out.setdefault(a, []).append(b)
        out.setdefault(b, []).append(a)
    return out


# ---------------------------------------------------------------- power
def solar_pods(g, problems):
    """Main SMES bank and the four solar rooms. Returns (solar-side tiles, SMES tiles)."""
    solar_side = set()
    smes_tiles = []
    # main SMES bank
    for x in (125, 128, 131):
        g[x, 152].objs.append("/obj/machinery/power/smes{charge = 5e+06; output_level = 90000; input_level = 150000}")
        g[x, 152].dense = True
        # engine side is cable layer 1, as on Hippie: terminal + bridge + layer-1 cable
        g[x, 153].objs += ["/obj/machinery/power/terminal{dir = 1}", "/obj/structure/cable_bridge", "/obj/structure/cable/layer1"]
        smes_tiles.append((x, 152))
        solar_side.add((x, 153))
    for x in range(125, 132):  # engine input bus (the engine joins this later)
        solar_side.add((x, 154))
    # solar control rooms: panels -> terminal -> SMES -> station grid
    pods = {"NW array": "NW Solars", "NE array": "NE Solars", "SW array": "SW Solars", "SE array": "SE Solars"}
    rooms = {r[0]: r for r in L.ROOMS}
    for (sname, sr), cw in zip(L.SOLARS, L.CATWALKS):
        pod = rooms[pods[sname]][2]
        x0, y0, x1, y1 = pod
        # external airlock where the catwalk meets the pod wall
        Ex = None
        for cx in range(cw[0], cw[2]):
            for cy in range(cw[1], cw[3]):
                if g[cx, cy].kind == "wall":
                    continue  # catwalk rect overlaps the pod's wall line here
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    wx, wy = cx + dx, cy + dy
                    on_line = (wx in (x0, x1) and y0 < wy < y1) or (wy in (y0, y1) and x0 < wx < x1)
                    if on_line and Ex is None:
                        Ex = (wx, wy, -dx, -dy)
        if Ex is None:
            problems.append("solar pod %s: no catwalk contact" % sname)
            continue
        ex, ey, ox, oy = Ex  # (ox, oy) points outward, toward the catwalk
        vx, vy = -ox, -oy
        t = g[ex, ey]
        t.turf, t.kind = "/turf/open/floor/plating", "door"
        t.objs = ['/obj/machinery/door/airlock/external{name = "Solar Maintenance"; req_one_access_txt = "10;13"}', CABLE]
        e1 = (ex + vx, ey + vy)
        term = (ex + 2 * vx, ey + 2 * vy)
        smes = (ex + 3 * vx, ey + 3 * vy)
        px_, py_ = (vy, vx) if vx == 0 else (vy, vx)
        cons = (e1[0] + px_, e1[1] + py_)
        sid = RD.SOLAR_ID[sname]
        g[e1].objs.append(CABLE)
        g[term].objs += ["/obj/machinery/power/terminal{dir = %d}" % dir_of(vx, vy), CABLE]
        g[smes].objs.append("/obj/machinery/power/smes{charge = 1e+06; output_level = 60000; input_level = 150000}")
        g[smes].dense = True
        g[cons].objs += ['/obj/machinery/power/solar_control{id = "%s"; name = "%s Control"; track = 2}' % (sid, sname.replace("array", "Solar")), CABLE]
        g[cons].dense = True
        for p in ((ex, ey), e1, term, cons):
            solar_side.add(p)
        smes_tiles.append(smes)
    # field cables (already on the tiles) count as solar side for separation
    for name, r in L.SOLARS:
        for x in range(r[0] - 1, r[2] + 1):
            for y in range(r[1] - 1, r[3] + 1):
                solar_side.add((x, y))
    for cw in L.CATWALKS:
        for x in range(cw[0], cw[2]):
            for y in range(cw[1], cw[3]):
                solar_side.add((x, y))
    return solar_side, smes_tiles


def power(g, apc_tiles, solar_side, smes_tiles, problems):
    forbid = set()
    engine_stubs = set()
    for (x, y) in solar_side:
        forbid.add((x, y))
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            forbid.add((x + dx, y + dy))
    for p in smes_tiles:
        forbid.discard(p)

    def cost(p):
        t = g.t.get(p)
        if t is None or (t.owner and t.owner[0] == "chunk" and p not in engine_stubs):
            return None
        if t.kind == "floor":
            if not t.indoor:
                return None
            # mice chew cable on bare plating: keep the grid under floor tiles and in walls
            return 2.5 if t.turf.startswith("/turf/open/floor/plating") else 1.0
        if t.kind == "wall":
            return 1.2
        if t.kind in ("door", "window"):
            return 3.0
        return None

    main = smes_tiles[:3]
    ax, ay = L.ENGINE_AT
    sx0, sy0, sx1, sy1 = L.ENGINE_SRC
    eng = L.ENGINES[L.ENGINE]
    emitter_stub = (ax + (eng["l2"][0] - sx0), ay + (sy1 - eng["l2"][1]))   # where the emitters' layer-2 cable leaves the block
    collector_stub = (ax + (eng["l1"][0] - sx0), ay + (sy1 - eng["l1"][1]))  # where the generator side's layer-1 cable leaves it
    engine_stubs.update((emitter_stub, collector_stub))
    if CABLE not in g[emitter_stub].objs:
        problems.append("engine layer-2 stub %s has no cable" % (emitter_stub,))
    if "/obj/structure/cable/layer1" not in g[collector_stub].objs:
        problems.append("engine layer-1 stub %s has no layer-1 cable" % (collector_stub,))
    targets = sorted(set(list(apc_tiles.values()) + smes_tiles[3:] + [emitter_stub]),
                     key=lambda p: abs(p[0] - 128) + abs(p[1] - 152))
    tree, edges = route(g, targets, main, cost, forbid, "power", problems)
    # main SMES are joined to each other by the tree only if a path passes; join them explicitly
    for a, b in ((125, 128), (128, 131)):
        for x in range(a, b + 1):
            tree.add((x, 151))
    tree.update(main)
    n = 0
    for p in tree:
        if CABLE not in g[p].objs:
            g[p].objs.append(CABLE)
            n += 1
    for x in range(125, 132):
        g[x, 154].objs.append("/obj/structure/cable/layer1")
    STATS["cable tiles"] = n
    # engine side: the collectors' layer-1 network to the SMES input bus. Layer 1 never joins the
    # station's layer-2 grid, so it may run beside it; it only has to keep off the SMES and the solar rooms.
    bus = {(x, 154) for x in range(125, 132)}
    eforbid = {p for p in smes_tiles} | {p for p in solar_side if not (125 <= p[0] <= 131 and 153 <= p[1] <= 154)}
    eforbid -= bus
    eforbid.discard(collector_stub)
    etree, eedges = route(g, [collector_stub], bus, cost, eforbid, "engine input", problems)
    k = 0
    for p in etree:
        if p not in bus and "/obj/structure/cable/layer1" not in g[p].objs:
            g[p].objs.append("/obj/structure/cable/layer1")
            k += 1
    STATS["engine input cable"] = k


def dir_of(dx, dy):
    for d, s in STEP.items():
        if s == (dx, dy):
            return d
    return S


# ---------------------------------------------------------------- air
SUP = "/obj/machinery/atmospherics/pipe/%s/supply/hidden/layer1"
SCR = "/obj/machinery/atmospherics/pipe/%s/scrubbers/hidden"


def air(g, door_tiles, problems):
    fronts = door_fronts(g, door_tiles)
    vents, scrubs = [], []
    for kind, name, area, r in spaces():
        if kind == "room" and name in ("Burn Chamber",):
            continue
        x0, y0, x1, y1 = r
        iw, ih = x1 - x0 - 1, y1 - y0 - 1
        horiz = iw >= ih
        length = iw if horiz else ih
        pairs = 1 if kind != "hall" else max(1, length // 14)
        for i in range(pairs):
            f = (i + 0.5) / pairs
            if horiz:
                cy = y0 + 1 + ih // 2
                a = (x0 + 1 + max(0, int(length * f) - 1), cy)
                b = (min(x1 - 1, a[0] + 2), cy)
            else:
                cx = x0 + 1 + iw // 2
                a = (cx, y0 + 1 + max(0, int(length * f) - 1))
                b = (cx, min(y1 - 1, a[1] + 2))
            if iw <= 1 or ih <= 1:
                continue
            for lst, p in ((vents, a), (scrubs, b)):
                if p in fronts or g[p].kind != "floor":
                    continue
                lst.append(p)
    devices = set(vents) | set(scrubs)
    # supply source: air tanks in Atmos Tanks
    tanks = [(80, 182), (81, 182), (82, 182), (83, 182), (84, 182)]
    sup_root = [(x, 181) for x, _ in tanks]
    sup_edges = set(frozenset(((x, 181), (x + 1, 181))) for x, _ in tanks[:-1])
    for x, y in tanks:
        sup_edges.add(frozenset(((x, 181), (x, 182))))
        g[x, y].objs.append("/obj/machinery/atmospherics/components/unary/tank/air{dir = 1; piping_layer = 1}")
        g[x, y].dense = True
    # scrubber sink: an injector into space beside Atmos Tanks
    inj = (75, 175)
    scr_root = [(76, 175)]
    scr_edges = {frozenset(((76, 175), inj))}
    g[inj].objs.append("/obj/machinery/atmospherics/components/unary/outlet_injector/on{dir = 4}")
    forbid = devices | set(tanks) | {inj}

    def cost(p):
        t = g.t.get(p)
        if t is None or (t.owner and t.owner[0] == "chunk"):
            return None
        if t.kind == "floor":
            if not t.indoor:
                return None
            return 0.6 if t.owner and t.owner[0] in ("maint", "tunnel") else 1.0
        if t.kind == "wall":
            return 1.8
        if t.kind in ("door", "window"):
            return 3.0
        return None

    vents.sort(key=lambda p: abs(p[0] - 82) + abs(p[1] - 181))
    scrubs.sort(key=lambda p: abs(p[0] - 76) + abs(p[1] - 175))
    sup_tree, sup_edges = route(g, vents, sup_root, cost, forbid - set(vents), "supply", problems, sup_edges, leaves=True)
    scr_tree, scr_edges = route(g, scrubs, scr_root, cost, forbid - set(scrubs), "scrubbers", problems, scr_edges, leaves=True)
    # every device must end up with exactly one pipe
    for lst, edges, nm in ((vents, sup_edges, "vent"), (scrubs, scr_edges, "scrubber")):
        bt = by_tile(edges)
        for p in lst:
            k = len(bt.get(p, ()))
            if k != 1:
                problems.append("%s at %s has %d pipes" % (nm, p, k))
    lay_pipes(g, sup_edges, set(vents) | set(tanks), SUP,
              "/obj/machinery/atmospherics/components/unary/vent_pump/on/layer1", set(vents))
    lay_pipes(g, scr_edges, set(scrubs) | {inj}, SCR,
              "/obj/machinery/atmospherics/components/unary/vent_scrubber/on", set(scrubs))
    STATS["vents"] = len(vents)
    STATS["scrubbers"] = len(scrubs)


def lay_pipes(g, edges, device_tiles, fmt, device_path, place_devices):
    bt = by_tile(edges)
    for p, nbrs in bt.items():
        m = mask_of(p, bt)
        if p in device_tiles:
            if p in place_devices:
                g[p].objs.append("%s{dir = %d}" % (device_path, m))
            continue
        bits = bin(m).count("1")
        if bits == 4:
            g[p].objs.append(fmt % "manifold4w")
        elif bits == 3:
            g[p].objs.append("%s{dir = %d}" % (fmt % "manifold", 15 - m))
        elif bits == 2:
            if m in (N | S,):
                d = 1
            elif m == (E | Wd):
                d = 4
            else:
                d = m
            g[p].objs.append("%s{dir = %d}" % (fmt % "simple", d))
        # a lone end pipe would be a leak: devices are the only leaves


# ---------------------------------------------------------------- landmarks
def free_tiles(g, r, fronts, need_free=True):
    out = []
    for p in interior(r):
        t = g[p]
        if t.kind == "floor" and p not in fronts and not t.dense:
            out.append(p)
    return out


def landmarks(g, door_tiles, problems):
    fronts = door_fronts(g, door_tiles)
    rooms = {r[0]: r for r in L.ROOMS}
    n = 0
    reserved = set()
    for room, jobs in RD.STARTS.items():
        tiles = free_tiles(g, rooms[room][2], fronts)
        rnd.shuffle(tiles)
        for job, count in jobs:
            for _ in range(count):
                if not tiles:
                    problems.append("no room for %s start in %s" % (job, room))
                    break
                p = tiles.pop()
                g[p].objs.append("/obj/effect/landmark/start/%s" % job)
                reserved.add(p)
                n += 1
    for room, dep in RD.DEPSEC.items():
        tiles = free_tiles(g, rooms[room][2], fronts)
        if tiles:
            p = rnd.choice(tiles)
            g[p].objs.append("/obj/effect/landmark/start/depsec/%s" % dep)
            reserved.add(p)
    sl = free_tiles(g, rooms["Sci Lobby"][2], fronts)
    g[sl[len(sl) // 2]].objs.append("/obj/effect/landmark/observer_start")
    for room in ("Sec Office", "Sec Office"):
        tiles = free_tiles(g, rooms[room][2], fronts)
        g[rnd.choice(tiles)].objs.append("/obj/effect/landmark/secequipment")
    maint = [p for p, t in g.t.items() if t.kind == "floor" and t.owner and t.owner[0] in ("maint", "tunnel")]
    maint.sort()
    rnd.shuffle(maint)
    for p in maint[:8]:
        g[p].objs.append("/obj/effect/landmark/blobstart")
    for p in maint[8:20]:
        g[p].objs.append("/obj/effect/landmark/xeno_spawn")
    halls = [p for p, t in g.t.items() if t.kind == "floor" and t.owner and t.owner[0] in ("hall", "walkway")]
    halls.sort()
    rnd.shuffle(halls)
    for p in halls[:24]:
        g[p].objs.append("/obj/effect/landmark/event_spawn")
    for p in ((30, 0), (200, 0), (230, 100), (-10, 100), (120, 205), (10, 200)):
        if g.inb(*p) and g[p].kind == "space":
            g[p].objs.append("/obj/effect/landmark/carpspawn")
    STATS["job starts"] = n
    return reserved


def gravity(g):
    x, y = 106, 160
    g[x, y].objs.append("/obj/machinery/gravity_generator/main/station")
    for dx in (-1, 0, 1):
        for dy in (0, -1, -2):
            g[x + dx, y + dy].dense = True


def teleporter(g):
    r = {r[0]: r for r in L.ROOMS}["Teleporter"][2]
    x = (r[0] + r[2]) // 2
    y = r[1] + 3
    g[x, y].objs.append("/obj/machinery/computer/teleporter{dir = 2}")
    g[x, y + 1].objs.append("/obj/machinery/teleport/station")
    g[x, y + 2].objs.append("/obj/machinery/teleport/hub")
    for k in range(3):
        g[x, y + k].dense = True


def infrastructure(g, door_tiles, problems):
    gravity(g)
    teleporter(g)
    lights(g, door_tiles, problems)
    solar_side, smes_tiles = solar_pods(g, problems)
    placed = apcs(g, problems, solar_side | set(smes_tiles))
    power(g, placed, solar_side, smes_tiles, problems)
    air(g, door_tiles, problems)
    landmarks(g, door_tiles, problems)


# ---------------------------------------------------------------- contents
DROP = re.compile(r"^/(turf|area)/|^/obj/structure/cable|^/obj/machinery/atmospherics/(pipe|components/unary/(vent|portables|outlet|passive|heat)|components/binary|components/trinary)"
                  r"|^/obj/machinery/power/(apc|terminal|smes|solar|tracker)|^/obj/machinery/light|^/obj/machinery/(airalarm|firealarm|light_switch|button|door|door_timer|flasher|conveyor|navbeacon|camera|newscaster|status_display|requests_console|ai_status_display|turretid|disposal|keycard_auth|holopad/secure|computer/teleporter|teleport|gravity_generator|doorButtons|embedded_controller|igniter|sparker)"
                  r"|^/obj/structure/(window|grille|disposal|sign|extinguisher_cabinet|fireaxecabinet|noticeboard|fans|plasticflaps|lattice|girder|falsewall)"
                  r"|^/obj/effect/(spawner/structure|landmark|mapping_helpers|turf_decal|decal|forcefield)|^/obj/docking_port|^/obj/item/radio/intercom|^/obj/machinery/atmospherics/miner|^/obj/machinery/power/emitter|^/obj/machinery/field|^/obj/machinery/the_singularitygen|^/obj/machinery/power/rad_collector|^/obj/machinery/power/supermatter|^/obj/machinery/shieldwallgen|^/obj/machinery/mass_driver|^/obj/machinery/pdapainter/.*pixel")
DENSE = re.compile(r"^/obj/machinery/(?!holopad|atmospherics/components/unary/vent|recharger)|^/obj/structure/(table|closet|rack|bookcase|reagent_dispensers|displaycase|statue|filingcabinet|safe|dresser|showcase|AIcore|frame|piano|musician|toilet|urinal|sink|mirror|shower|bed/.*dense|guncase|tank_dispenser|ore_box|kitchenspike|mopbucket|janitorialcart)")
PIXEL = re.compile(r"pixel_([xy]) = (-?\d+)")

_HIPPIE = None


def hippie():
    global _HIPPIE
    if _HIPPIE is None:
        m = D.read(os.path.join(ROOT, "_maps", "map_files", "HippieStation", "hippiestation.dmm"))
        by = {}
        for (x, y), atoms in m.tiles.items():
            area = atoms[-1].split("{")[0]
            keep = []
            for a in atoms[:-1]:
                if DROP.search(a):
                    continue
                px = [abs(int(v)) for _, v in PIXEL.findall(a)]
                if px and max(px) >= 16:
                    continue
                keep.append(a)
            if keep:
                by.setdefault(area, []).append((x, m.maxy - y, keep))  # y down like the layout
        _HIPPIE = by
    return _HIPPIE


def bundle_dense(objs):
    return any(DENSE.search(o) for o in objs)


def rot_dir(a, quarter):
    """Rotate a 'dir = N' in an atom by quarter turns clockwise."""
    m = re.search(r"dir = (\d+)", a)
    if not m or quarter == 0:
        return a
    d = int(m.group(1))
    order = [1, 5, 4, 6, 2, 10, 8, 9]
    if d not in order:
        return a
    nd = order[(order.index(d) + 2 * quarter) % 8]
    return a[:m.start(1)] + str(nd) + a[m.end(1):]


def contents(g, door_tiles, problems):
    hp = hippie()
    fronts = door_fronts(g, door_tiles)
    placed_total = dropped_total = 0
    for name, dept, r, flags in L.ROOMS:
        srcs = RD.HARVEST.get(name, [])
        bundles = []
        for a in srcs:
            bundles += hp.get(a, [])
        if not bundles:
            continue
        free = [p for p in interior(r) if g[p].kind == "floor" and p not in fronts]
        if not free:
            continue
        freeset = set(free)
        iw, ih = r[2] - r[0] - 1, r[3] - r[1] - 1
        xs = [b[0] for b in bundles]
        ys = [b[1] for b in bundles]
        bw, bh = max(xs) - min(xs) + 1, max(ys) - min(ys) + 1
        layout = None
        if len(srcs) == 1 or True:
            for quarter in (0, 1):
                w_, h_ = (bw, bh) if quarter == 0 else (bh, bw)
                if w_ <= iw and h_ <= ih:
                    ox = r[0] + 1 + (iw - w_) // 2
                    oy = r[1] + 1 + (ih - h_) // 2
                    layout = []
                    for (x, y, objs) in bundles:
                        rx, ry = x - min(xs), y - min(ys)
                        if quarter:
                            rx, ry = bh - 1 - ry, rx
                        layout.append(((ox + rx, oy + ry), [rot_dir(o, quarter) for o in objs]))
                    break
        if layout is None:
            # pack: dense bundles round the walls, the rest anywhere
            perim = [p for p in free if wall_dirs(g, *p)]
            inner = [p for p in free if p not in perim]
            dense_b = [b for b in bundles if bundle_dense(b[2])]
            light_b = [b for b in bundles if not bundle_dense(b[2])]
            cap_d = int(len(perim) * 0.7)
            cap_l = max(0, int(len(free) * 0.45) - min(cap_d, len(dense_b)))
            layout = []
            for p, b in zip(perim[:cap_d], dense_b):
                layout.append((p, b[2]))
            spots = [p for p in inner + perim[len(dense_b):] if p not in {q for q, _ in layout}]
            for p, b in zip(spots[:cap_l], light_b):
                layout.append((p, b[2]))
            dropped_total += max(0, len(dense_b) - cap_d) + max(0, len(light_b) - cap_l)
        # place, keeping the room walkable from its doors
        for p, objs in layout:
            if p not in freeset or g[p].dense:
                dropped_total += 1
                continue
            dense = bundle_dense(objs)
            if dense:
                g[p].dense = True
                if not walkable(g, r, fronts):
                    g[p].dense = False
                    dropped_total += 1
                    continue
            g[p].objs += objs
            placed_total += 1
    # extra furniture for rooms Hippie can't fill
    extra_placed = 0
    rooms = {r[0]: r for r in L.ROOMS}
    for name, items in RD.EXTRA.items():
        r = rooms[name][2]
        free = [p for p in interior(r) if g[p].kind == "floor" and p not in fronts and not g[p].dense
                and not any(o.startswith("/obj/structure/chair") or o.startswith("/obj/structure/closet") for o in g[p].objs)]
        perim = [p for p in free if wall_dirs(g, *p)]
        inner = [p for p in free if p not in perim]
        for item in items:
            objs = item if isinstance(item, list) else [item]
            dense = bundle_dense(objs)
            spots = perim if dense else (inner or perim)
            while spots:
                p = spots.pop(0)
                if g[p].dense:
                    continue
                if dense:
                    g[p].dense = True
                    if not walkable(g, r, fronts):
                        g[p].dense = False
                        continue
                g[p].objs += objs
                extra_placed += 1
                if p in perim and spots is not perim:
                    perim.remove(p)
                break
    STATS["content tiles"] = placed_total
    STATS["extra furniture"] = extra_placed
    STATS["wall mounts"] = wall_mounts(g, fronts, problems)
    STATS["pews"] = pews(g, fronts)
    STATS.update(alarms_and_cameras(g, fronts))
    STATS["content dropped"] = dropped_total


def walkable(g, r, fronts):
    """The room's free floor is all one piece, and every dense thing in it has a free tile beside it
    (a microwave boxed in by tables passes the first test and nobody can use it)."""
    tiles = [p for p in interior(r) if g[p].kind == "floor" and not g[p].dense]
    if not tiles:
        return False
    tset = set(tiles)
    for p in interior(r):
        if g[p].kind == "floor" and g[p].dense:
            x, y = p
            if not any((x + dx, y + dy) in tset for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                return False
    start = next((p for p in tiles if p in fronts), tiles[0])
    seen = {start}
    todo = [start]
    while todo:
        x, y = todo.pop()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + dx, y + dy)
            if q in tset and q not in seen:
                seen.add(q)
                todo.append(q)
    return len(seen) == len(tset)


def wall_mounts(g, fronts, problems):
    """Requests consoles and sinks on real walls, offset the way Hippie offsets them."""
    rooms = {r[0]: r for r in L.ROOMS}
    n = 0
    for name, items in RD.WALL_MOUNTS.items():
        r = rooms[name][2]
        cands = []
        for p in interior(r):
            t = g[p]
            if t.kind != "floor" or p in fronts:
                continue
            for d in wall_dirs(g, *p):
                if d not in t.mounts:
                    cands.append((0 if d == N else 1, p, d))
        cands.sort()
        for item in items:
            placed = False
            for k, (pri, p, d) in enumerate(cands):
                t = g[p]
                if d in t.mounts:
                    continue
                if item == "shower":
                    atom = "/obj/machinery/shower{dir = %d}" % OPP[d]
                elif item == "sink":
                    if d == S:
                        continue
                    atom = {N: "/obj/structure/sink{pixel_y = 30}", E: "/obj/structure/sink{dir = 4; pixel_x = 11}",
                            Wd: "/obj/structure/sink{dir = 8; pixel_x = -12; pixel_y = 2}"}[d]
                    if name == "Kitchen" and d == N:
                        atom = "/obj/structure/sink/kitchen{pixel_y = 28}"
                else:
                    off = {N: "pixel_y = 30", S: "pixel_y = -30", E: "pixel_x = 30", Wd: "pixel_x = -30"}[d]
                    atom = item[:-1] + "; " + off + "}"
                t.objs.append(atom)
                t.mounts.add(d)
                placed = True
                n += 1
                break
            if not placed:
                problems.append("no wall spot for %s in %s" % (item.split("{")[0], name))
    return n


def pews(g, fronts):
    """Rows of pews down the chapel facing its north end, with an aisle up the middle."""
    r = {x[0]: x for x in L.ROOMS}["Chapel"][2]
    x0, y0, x1, y1 = r
    mid = (x0 + x1) // 2
    n = 0
    for y in range(y0 + 6, y1 - 2, 2):
        for x in range(x0 + 3, x1 - 2):
            if abs(x - mid) <= 1 or (x, y) in fronts:
                continue
            t = g[x, y]
            if t.kind != "floor" or t.dense or any(o.startswith("/obj/structure") or o.startswith("/obj/machinery") for o in t.objs):
                continue
            t.objs.append("/obj/structure/chair/pew{dir = 1}")
            n += 1
    return n


HALL_TAGS = {
    "sec-P": "Security Concourse", "sup-P": "Cargo Concourse", "sec-D": "Brig Hall", "cmd-P": "Command Concourse",
    "cmd-P2": "Science Spoke", "cmd-Dn": "Bridge Hall", "cmd-Dw": "Secure Hall", "cmd-De": "Command Hall",
    "srv-P": "Service Concourse", "srv-P2": "Service Concourse South", "srv-D": "Service Back Hall",
    "med-P": "Medical Concourse", "med-P2": "Medical Concourse West", "med-D": "Medbay Hall", "eng-P": "Engineering Concourse",
    "eng-D": "Engineering Hall", "sup-D": "Cargo Hall", "sci-D": "Research Hall", "sci-D2": "Research Hall West",
    "sci-D3": "Research Hall East",
}


def alarms_and_cameras(g, fronts):
    """An air alarm, a fire alarm and a camera in every room; alarms in every hall and a camera every 14 tiles of it.
    Each faces away from its wall, offset onto it the way Hippie's are."""
    OFF = {N: ("pixel_y", 1), S: ("pixel_y", -1), E: ("pixel_x", 1), Wd: ("pixel_x", -1)}

    def mount_atom(kind, d, tag=None):
        face = OPP[d]
        axis, sign = OFF[d]
        if kind == "camera":
            return '/obj/machinery/camera{dir = %d; c_tag = "%s"}' % (face, tag)
        dist = 23 if kind == "airalarm" else 24
        return "/obj/machinery/%s{dir = %d; %s = %d}" % (kind, face, axis, sign * dist)

    def spots(r):
        out = []
        for p in interior(r):
            t = g[p]
            if t.kind != "floor" or p in fronts:
                continue
            for d in wall_dirs(g, *p):
                if d not in t.mounts:
                    out.append((p, d))
        return out

    n = {"air alarms": 0, "fire alarms": 0, "cameras": 0}
    skip = {"Burn Chamber"}
    for kind, name, area, r in spaces():
        if kind == "walkway" or name in skip:
            continue
        cand = spots(r)
        if not cand:
            continue
        x0, y0, x1, y1 = r
        length = max(x1 - x0, y1 - y0)
        tag = name if kind == "room" else HALL_TAGS.get(name, name)
        wanted = ["airalarm", "firealarm"]
        cams = 1 if kind == "room" else max(1, length // 14)
        used_tiles = set()
        for k in wanted:
            for p, d in cand:
                if p in used_tiles or d in g[p].mounts:
                    continue
                g[p].objs.append(mount_atom(k, d))
                g[p].mounts.add(d)
                used_tiles.add(p)
                n["air alarms" if k == "airalarm" else "fire alarms"] += 1
                break
        # cameras spread along the space
        cand.sort(key=lambda pd: (pd[0][0] + pd[0][1]))
        step = max(1, len(cand) // cams)
        for i in range(cams):
            for p, d in cand[i * step:] + cand[:i * step]:
                if p in used_tiles or d in g[p].mounts:
                    continue
                g[p].objs.append(mount_atom("camera", d, tag if cams == 1 else "%s %d" % (tag, i + 1)))
                g[p].mounts.add(d)
                used_tiles.add(p)
                n["cameras"] += 1
                break
    return n
