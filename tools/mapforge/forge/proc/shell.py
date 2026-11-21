"""Structure nodes: outline -> slice -> tidy -> openings -> fields.

outline   reads the department's footprint from the map: which tiles are ours, which must stay wall (something open
          lies outside them), which are kept as they are (launch shutters, chutes), which doors outside lead in.
slice     cuts the free tiles into rooms with a slicing tree. Every cut is a one-tile wall line and every free tile
          ends up in a room or a wall line, so there are no doubled walls and no solid chunks by construction.
tidy      drops scraps, fills one-tile dents (or keeps them as alcoves where filling would double a wall), and
          reports wall faults at the node that made them.
openings  doors, desks and glass, each set by rule on the wall two rooms share.
fields    per-tile attributes the room assets read: what backs a tile, door aprons, walking lanes, alcoves.
"""
import heapq

from .geo import N, S, E, W, CARD, OPP, CW, DIAG, Room, step, nb4, nb8


# ---------------------------------------------------------------------------------------------------- outline
def outline(geo, P, base, bbox, in_zone, add=(), keep=(), gates=(), inside=()):
    """keep: tiles left exactly as they are and sealed off (a chute, a launch run): what touches them stays wall.
    gates: kept tiles people walk through (a door, an open public entrance): floor may come right up to them.
    inside: kept tiles that are part of the department's own floor (a cryo bay with its coolant loop): rooms may
    open onto them with no wall between."""
    from forge import dmm
    m = dmm.read(base)
    geo.base = m
    x0, y0, x1, y1 = bbox
    geo.zone = {(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)
                if m.get(x, y) is not None and in_zone(m.get(x, y).apath)} | set(add)
    gates, inside = set(gates), set(inside)
    keep = set(keep) | gates | inside
    for p in geo.zone:
        if p in keep:
            t = m.get(*p)
            shut = t.tpath.startswith("/turf/closed") or t.has("/obj/effect/spawner/structure/window")
            if p in inside or (shut and p not in gates):
                geo.kind[p] = "keep_wall" if shut else "keep_floor"
            else:
                geo.kind[p] = "keep_door" if (p in gates or t.has("/obj/machinery/door")) else "keep_open"
    for p in geo.zone:
        if p in keep:
            continue
        ring = False
        for q in nb8(p):
            if q in geo.zone:
                ring = ring or geo.kind.get(q) == "keep_open"
            else:
                ring = ring or geo.outside(q) in ("hall", "maint", "space")
        geo.kind[p] = "ring" if ring else "free"
    # doors outside the zone that open onto one of our tiles: the tile in front stays floor
    front = geo.field("front")
    for p in sorted(geo.zone):
        if p in keep or m.get(*p).tpath.startswith("/turf/closed"):
            continue
        for d in CARD:
            q = step(p, d)
            if q in geo.zone or geo.outside(q) != "door" or not m.get(*q).has("/obj/machinery/door/airlock"):
                continue
            far = step(q, d)
            if far in geo.zone or m.get(*far) is None or m.get(*far).tpath.startswith(("/turf/closed", "/turf/open/space")):
                continue        # the door has to lead somewhere: a hall, maintenance, a neighbour's room
            geo.kind[p] = "free"
            front[p] = True
            geo.doors[q] = dict(ext=True, dir=OPP[d], sides={}, front=p, outside=geo.outside(far))
    # the station's disposal line passes under the department: no bin may stand on it
    from forge import disposal_route
    trunk = geo.field("trunk")
    for p in disposal_route.backbone(m, geo.zone) | set(disposal_route.survey(m, geo.zone)[0]):
        trunk[p] = True
    geo.notes.append("outline: %d tiles, %d ring, %d kept, %d doors leading in from outside" % (
        len(geo.zone), sum(1 for k in geo.kind.values() if k == "ring"), len(keep),
        sum(1 for v in geo.doors.values() if v.get("ext"))))


# ---------------------------------------------------------------------------------------------------- slice
def X(*kids, wall=1):
    """Cut left to right. Each kid is (size, node): size an int (tiles) or a float (share of what is left); node a
    room id, another cut, or "-" for tiles no room takes. wall=0 cuts with no wall line (an open-plan seam)."""
    return ("x", list(kids), wall)


def Y(*kids, wall=1):
    """Cut top to bottom (north to south)."""
    return ("y", list(kids), wall)


def slice_rooms(geo, P, plans, rooms):
    def lay(rect, node):
        x0, y0, x1, y1 = rect
        if node == "-":
            return
        if isinstance(node, str):
            for x in range(x0, x1 + 1):
                for y in range(y0, y1 + 1):
                    if geo.kind.get((x, y)) == "free":
                        geo.kind[(x, y)] = "floor"
                        geo.room[(x, y)] = node
            return
        axis, kids, gap = node
        length = (x1 - x0 + 1) if axis == "x" else (y1 - y0 + 1)
        avail = length - gap * (len(kids) - 1)
        fixed = sum(s for s, _ in kids if isinstance(s, int))
        shares = [s for s, _ in kids if not isinstance(s, int)]
        left = avail - fixed
        sizes, acc, given = [], 0.0, 0
        for s, _ in kids:
            if isinstance(s, int):
                sizes.append(s)
            else:
                acc += s / sum(shares) * left
                sizes.append(int(round(acc)) - given)
                given += sizes[-1]
        if min(sizes) < 1 or sum(sizes) != avail:
            geo.problem("slice: %s cut of %d tiles cannot hold sizes %s" % (axis, length, sizes))
        pos = 0
        for i, ((_, kid), sz) in enumerate(zip(kids, sizes)):
            if axis == "x":
                lay((x0 + pos, y0, x0 + pos + sz - 1, y1), kid)
            else:
                lay((x0, y1 - pos - sz + 1, x1, y1 - pos), kid)
            pos += sz
            if i < len(kids) - 1 and gap:
                for t in range((y0 if axis == "x" else x0), (y1 if axis == "x" else x1) + 1):
                    w = (x0 + pos, t) if axis == "x" else (t, y1 - pos)
                    if geo.kind.get(w) == "free":
                        geo.kind[w] = "wall"
                pos += 1

    for rect, tree in plans:
        lay(rect, tree)
    spare = [p for p in geo.zone if geo.kind[p] == "free"]
    for p in spare:
        geo.kind[p] = "wall"
    if spare:
        geo.notes.append("slice: %d free tiles outside every plan became wall" % len(spare))
    # a cut between two pieces of the same room is no wall
    changed = True
    while changed:
        changed = False
        for p in sorted(geo.zone):
            if geo.kind[p] != "wall":
                continue
            for d in (N, E):
                a, b = geo.room.get(step(p, d)), geo.room.get(step(p, OPP[d]))
                if a and a == b:
                    geo.kind[p] = "floor"
                    geo.room[p] = a
                    changed = True
                    break
    for rid in sorted(set(geo.room.values())):
        r = Room(rid, **rooms.get(rid, {}))
        r.tiles = {p for p, v in geo.room.items() if v == rid}
        geo.rooms[rid] = r
        if rid not in rooms:
            geo.problem("slice: room %s has no entry in the room table" % rid)
    geo.notes.append("slice: %d rooms, %d wall-line tiles" % (len(geo.rooms), sum(1 for k in geo.kind.values() if k == "wall")))


# ---------------------------------------------------------------------------------------------------- stamp
def stamp(geo, P, stamps, rooms):
    """Prefab modules: plumbing-bound machines whose every tile is fixed against the others (a burn chamber with its
    airlock, injector and vent doors). A prefab is {(dx, dy): dict(...)} from its anchor tile:
      raw=spec, back="wall"|"door"   the module's own tile (wall, lock, chamber floor): nothing else goes there
      cell=spec, take="obj"|"open"   a piece on the floor of the room the module stands in
      front=True                     keep clear (in front of the module's door)
    """
    front = geo.field("front")
    for name, anchor, room, prefab in stamps:
        if callable(anchor):
            anchor = anchor(geo)
        if anchor is None:
            geo.problem("stamp: no anchor for %s" % name)
            continue
        geo.attr.setdefault("_anchor", {})[name] = anchor
        for (dx, dy), e in sorted(prefab.items()):
            p = (anchor[0] + dx, anchor[1] + dy)
            if p not in geo.zone:
                geo.problem("stamp: %d,%d is outside the outline" % p)
                continue
            if "raw" in e:
                rid = geo.room.pop(p, None)
                if rid in geo.rooms:
                    geo.rooms[rid].tiles.discard(p)
                geo.kind[p] = "raw"
                geo.raw[p] = (room, e["raw"], e.get("back", "wall"))
                # the module's own wall pieces (a vacuum sign) hold their wall tile: rooms beside it hang elsewhere
                for o in e["raw"].get("obj", []):
                    vs = o[1] if isinstance(o, tuple) else {}
                    px, py = int(vs.get("pixel_x", 0)), int(vs.get("pixel_y", 0))
                    if abs(px) >= 20 or abs(py) >= 20:
                        w = (p[0] + (1 if px >= 20 else -1 if px <= -20 else 0), p[1] + (1 if py >= 20 else -1 if py <= -20 else 0))
                        geo.attr.setdefault("_hung", {})[w] = name
            else:
                if geo.kind[p] != "floor":
                    geo.problem("stamp: %d,%d should be floor for a module piece" % p)
                    continue
                if e.get("cell"):
                    geo.cells.setdefault(p, []).append(e["cell"])
                if e.get("take"):
                    geo.taken[p] = e["take"]
                if e.get("front"):
                    front[p] = True
        if room not in geo.rooms:
            geo.rooms[room] = Room(room, **rooms.get(room, {}))
    geo.notes.append("stamp: %d module tiles" % len(geo.raw))


# ---------------------------------------------------------------------------------------------------- tidy
def _to_wall(geo, p):
    rid = geo.room.pop(p, None)
    geo.kind[p] = "wall"
    if rid in geo.rooms:
        geo.rooms[rid].tiles.discard(p)


def check_walls(geo, where):
    """Doubled walls (floor, wall, wall, floor in a line with a wall of ours in it) and walls joined only by a
    corner. Reported, never patched here: the cure is a better cut."""
    for p in sorted(geo.zone):
        if geo.kind[p] not in ("wall", "ring"):
            continue
        for d in (N, E):
            q = step(p, d)
            if not geo.solid(q) or not geo.walk(step(p, OPP[d])) or not geo.walk(step(q, d)):
                continue
            ours = geo.kind[p] == "wall" or (q in geo.zone and geo.kind[q] == "wall")
            if ours:
                geo.problem("%s: doubled wall at %d,%d / %d,%d" % (where, p[0], p[1], q[0], q[1]))
        for dx, dy in DIAG:
            q = (p[0] + dx, p[1] + dy)
            if q < p or not geo.blocked(q):
                continue
            a, c = (p[0] + dx, p[1]), (p[0], p[1] + dy)
            if not geo.blocked(a) and not geo.blocked(c):
                if geo.kind[p] == "wall" or (q in geo.zone and geo.kind[q] == "wall"):
                    geo.problem("%s: walls %d,%d and %d,%d touch only at a corner" % (where, p[0], p[1], q[0], q[1]))


def tidy(geo, P, min_room=4):
    front = geo.field("front")
    alcove = geo.field("alcove")
    # scraps: a room keeps its biggest piece
    for rid, r in geo.rooms.items():
        r.tiles = {p for p in r.tiles if geo.kind[p] == "floor"}
        left, parts = set(r.tiles), []
        while left:
            seed = left.pop()
            comp, todo = {seed}, [seed]
            while todo:
                for q in nb4(todo.pop()):
                    if q in left:
                        left.discard(q)
                        comp.add(q)
                        todo.append(q)
            parts.append(comp)
        parts.sort(key=len, reverse=True)
        for comp in parts[1:]:
            if len(comp) < min_room:
                for p in comp:
                    _to_wall(geo, p)
                geo.notes.append("tidy: %s lost a %d-tile scrap at %d,%d" % ((rid, len(comp)) + min(comp)))
            else:
                geo.problem("tidy: room %s is in two pieces (%d tiles apart at %d,%d)" % ((rid, len(comp)) + min(comp)))
    # dents: a floor tile closed on three sides, off a bigger space
    changed = True
    while changed:
        changed = False
        for p in sorted(geo.zone):
            if geo.kind[p] != "floor" or p in front or p in alcove:
                continue
            open_sides = [d for d in CARD if not geo.solid(step(p, d))]
            if len(open_sides) != 1:
                continue
            q = step(p, open_sides[0])
            if q not in geo.zone or geo.kind[q] != "floor" or sum(1 for n in nb4(q) if geo.walk(n)) < 3:
                continue  # the end of a one-wide run, not a dent
            behind = step(p, OPP[open_sides[0]], 2)
            if geo.walk(behind):
                alcove[p] = True     # filling it would double the wall behind: keep it, an asset gives it a use
                continue
            _to_wall(geo, p)
            geo.notes.append("tidy: filled a dent at %d,%d" % p)
            changed = True
    for rid in [k for k, r in geo.rooms.items() if not r.tiles and not r.attrs.get("module")]:
        geo.problem("tidy: room %s got no tiles" % rid)
    check_walls(geo, "tidy")


# ---------------------------------------------------------------------------------------------------- openings
def door(a, b, at="mid", wide=1, **spec):
    return dict(op="door", a=a, b=b, at=at, wide=wide, spec=spec)


def desk(a, b, at="mid", **spec):
    spec["type"] = "desk"
    return dict(op="door", a=a, b=b, at=at, wide=1, spec=spec)


def glass(a, b, span=None, inset=0, runs="all", along=None, shutter=None):
    """along=("x", 60) or ("y", 88): only the wall runs lying on that column or row (a corner cell's hall side).
    shutter="id": shutters over the panes that a button with that id shuts (brig cells' street windows)."""
    return dict(op="glass", a=a, b=b, span=span, inset=inset, runs=runs, along=along, shutter=shutter)


def keep(p, a, b=None):
    return dict(op="keep", p=p, a=a, b=b)


def wall_runs(geo, a, b):
    """The wall two neighbours share, as straight runs of (tile, direction toward a)."""
    hits = []
    for p in sorted(geo.zone):
        if geo.kind[p] not in ("wall", "ring", "glass", "door"):
            continue
        for d in CARD:
            if geo.beyond(step(p, d)) == a and geo.beyond(step(p, OPP[d])) == b:
                hits.append((p, d))
    runs = []
    # a wall faced north or south runs east-west: order by row, then along x; the other way for east and west
    for p, d in sorted(hits, key=lambda h: (h[1], (h[0][1], h[0][0]) if h[1] in (N, S) else h[0])):
        last = runs[-1][-1] if runs else None
        along = (1, 0) if d in (N, S) else (0, 1)
        if last and last[1] == d and (last[0][0] + along[0], last[0][1] + along[1]) == p:
            runs[-1].append((p, d))
        else:
            runs.append([(p, d)])
    runs.sort(key=lambda r: (-len(r), r[0][0]))
    return runs


def _in_line(geo, p, d):
    """A door or pane at p (passage along d) has wall, glass or door on both sides."""
    return geo.blocked(step(p, CW[d])) and geo.blocked(step(p, OPP[CW[d]]))


def _centroid(geo, rid):
    t = geo.rooms[rid].tiles
    return (sum(p[0] for p in t) / len(t), sum(p[1] for p in t) / len(t))


def openings(geo, P, links):
    front = geo.field("front")
    for ln in links:
        a, b = ln["a"], ln.get("b")
        if ln["op"] == "keep":
            p = ln["p"]
            sides = {}
            for d in CARD:
                r = geo.beyond(step(p, d))
                if r in (a, b) and r in geo.rooms:
                    sides[r] = step(p, d)
            if a not in sides:
                geo.problem("openings: kept door %d,%d does not open onto %s" % (p[0], p[1], a))
            geo.doors[p] = dict(keep=True, sides=sides, spec={})
            continue
        runs = wall_runs(geo, a, b)
        if not runs:
            geo.problem("openings: %s and %s share no wall" % (a, b))
            continue
        if ln["op"] == "glass":
            pick = runs
            if ln["runs"] == "door":      # only the stretch of wall the two rooms' door (or desk) sits in
                pick = [r for r in runs if any(geo.kind[p] == "door" for p, _ in r)]
            elif ln["runs"] == "first":
                pick = runs[:1]
            if ln.get("along"):
                k = 0 if ln["along"][0] == "x" else 1
                pick = [r for r in pick if all(p[k] == ln["along"][1] for p, _ in r)]
            for run in pick:
                tiles = [p for p, d in run if geo.kind[p] in ("wall", "ring")]
                n = len(tiles)
                lo, hi = (0, n) if ln["span"] is None else (int(round(ln["span"][0] * n)), int(round(ln["span"][1] * n)))
                lo, hi = lo + ln["inset"], hi - ln["inset"]
                for p in tiles[lo:hi]:
                    geo.kind[p] = "glass"
                    if ln.get("shutter"):
                        geo.attr.setdefault("_shutter", {})[p] = ln["shutter"]
            continue
        wide, at = ln["wide"], ln["at"]
        cands = []
        for run in runs:
            for i in range(len(run) - wide + 1):
                part = run[i:i + wide]
                d = part[0][1]
                if any(geo.kind[p] != "wall" and geo.kind[p] != "ring" for p, _ in part):
                    continue
                side = CW[d]
                first, last = part[0][0], part[-1][0]
                ends = [step(first, side), step(first, OPP[side]), step(last, side), step(last, OPP[side])]
                outer = [q for q in ends if q not in [p for p, _ in part]]
                if not all(geo.blocked(q) for q in outer):
                    continue
                mid = ((first[0] + last[0]) / 2.0, (first[1] + last[1]) / 2.0)
                cands.append((part, mid, run))
        if not cands:
            geo.problem("openings: no place for a door between %s and %s" % (a, b))
            continue

        def score(c):
            part, mid, run = c
            if at == "mid" or isinstance(at, float):
                f = 0.5 if at == "mid" else at
                lo, hi = run[0][0], run[-1][0]
                want = (lo[0] + (hi[0] - lo[0]) * f, lo[1] + (hi[1] - lo[1]) * f)
                return (-len(run), abs(mid[0] - want[0]) + abs(mid[1] - want[1]))
            if at[0] == "x":
                return (abs(mid[0] - at[1]), 0)
            if at[0] == "y":
                return (abs(mid[1] - at[1]), 0)
            if at[0] == "near":
                want = _centroid(geo, at[1]) if isinstance(at[1], str) else at[1]
                return (abs(mid[0] - want[0]) + abs(mid[1] - want[1]), 0)
            if at[0] == "tile":
                return (abs(mid[0] - at[1][0]) + abs(mid[1] - at[1][1]), 0)
            raise ValueError("unknown door rule %r" % (at,))
        part, mid, run = min(cands, key=lambda c: score(c) + (c[1],))
        for i, (p, d) in enumerate(part):
            geo.kind[p] = "door"
            sides = {}
            if a in geo.rooms:
                sides[a] = step(p, d)
            if b in geo.rooms:
                sides[b] = step(p, OPP[d])
            geo.doors[p] = dict(sides=sides, dir=d, spec=dict(ln["spec"]), part=i, wide=wide, a=a, b=b)
    for p, dr in geo.doors.items():
        for rid, q in dr["sides"].items():
            front[q] = True
        if dr.get("ext"):
            rid = geo.room.get(dr["front"])
            if rid:
                dr["sides"][rid] = dr["front"]
    for p, dr in geo.doors.items():
        if dr.get("ext") or dr.get("keep"):
            continue
        if not _in_line(geo, p, dr["dir"]):
            geo.problem("openings: door %d,%d is not in a wall line" % p)
    for p in sorted(geo.zone):
        if geo.kind[p] != "glass":
            continue
        ns = geo.blocked(step(p, N)) and geo.blocked(step(p, S))
        ew = geo.blocked(step(p, E)) and geo.blocked(step(p, W))
        if not ns and not ew:
            geo.problem("openings: glass %d,%d is not in a wall line" % p)
    check_walls(geo, "openings")
    # every room can be walked into
    for rid, r in geo.rooms.items():
        if r.attrs.get("module"):
            continue
        if not any(rid in dr["sides"] for dr in geo.doors.values()):
            geo.problem("openings: room %s has no door" % rid)
    geo.notes.append("openings: %d doors, %d glass" % (sum(1 for k in geo.kind.values() if k == "door"),
                                                         sum(1 for k in geo.kind.values() if k == "glass")))


# ---------------------------------------------------------------------------------------------------- fields
def room_doors(geo, rid):
    """[(door tile, tile just inside this room)]"""
    return sorted((p, dr["sides"][rid]) for p, dr in geo.doors.items() if rid in dr["sides"])


def backing(geo, p, d):
    q = step(p, d)
    w = geo.what(q)
    if w == "raw":
        return geo.raw[q][2]
    if q in geo.zone:
        if w == "keep_wall" and geo.base is not None:     # a kept window (with or without a blast door over it)
            t = geo.base.get(*q)
            if t.has("/obj/machinery/door"):
                return "door"
            if not t.tpath.startswith("/turf/closed"):
                return "glass"
        return {"wall": "wall", "ring": "wall", "keep_wall": "wall", "glass": "glass", "door": "door",
                "keep_door": "door"}.get(w)
    return {"wall": "wall", "glass": "glass", "door": "door"}.get(w)


def lane_path(geo, tiles, back, src, dst):
    """Walk from src to dst inside a room: straight where it can, off the walls so they stay free for furniture."""
    dist = {(src, 0): 0.0}
    prev = {}
    heap = [(0.0, src, 0)]
    done = set()
    while heap:
        c, p, d0 = heapq.heappop(heap)
        if (p, d0) in done:
            continue
        done.add((p, d0))
        if p == dst:
            out, key = [p], (p, d0)
            while key in prev:
                key = prev[key]
                out.append(key[0])
            return out
        for d in CARD:
            q = step(p, d)
            if q not in tiles or (q, d) in done:
                continue
            cost = 1.0 + (0.6 if any(v == "wall" for v in back.get(q, {}).values()) and q != dst else 0.0)
            cost += 0.35 if d0 and d != d0 else 0.0
            if c + cost < dist.get((q, d), 1e9):
                dist[(q, d)] = c + cost
                prev[(q, d)] = (p, d0)
                heapq.heappush(heap, (c + cost, q, d))
    return []


def fields(geo, P):
    back, lane, corner, alcove = geo.field("back"), geo.field("lane"), geo.field("corner"), geo.field("alcove")
    dwall, depth = geo.field("dwall"), geo.field("depth")
    for p in geo.zone:
        if geo.kind[p] != "floor":
            continue
        b = {d: backing(geo, p, d) for d in CARD}
        b = {d: v for d, v in b.items() if v}
        if b:
            back[p] = b
        walls = [d for d, v in b.items() if v == "wall"]
        if any(CW[d] in walls for d in walls):
            corner[p] = True
        if len(b) >= 3:
            alcove[p] = True
    for rid, r in geo.rooms.items():
        if not r.tiles:
            continue
        # distance to the nearest wall
        ring = [p for p in r.tiles if p in back]
        dist = {p: 0 for p in ring}
        todo = list(ring)
        while todo:
            nxt = []
            for p in todo:
                for q in nb4(p):
                    if q in r.tiles and q not in dist:
                        dist[q] = dist[p] + 1
                        nxt.append(q)
            todo = nxt
        dwall.update(dist)
        doors = room_doors(geo, rid)
        ins = sorted({q for _, q in doors})
        cx = sum(p[0] for p in r.tiles) / len(r.tiles)
        cy = sum(p[1] for p in r.tiles) / len(r.tiles)
        heart = max(r.tiles, key=lambda p: (dist.get(p, 0), -abs(p[0] - cx) - abs(p[1] - cy), p))
        r.attrs["heart"] = heart
        if r.attrs.get("hall"):
            for p in r.tiles:
                lane[p] = True
            continue
        if not ins:
            continue
        # depth: steps from the room's first door (public first)
        d0 = {ins[0]: 0}
        todo = [ins[0]]
        while todo:
            nxt = []
            for p in todo:
                for q in nb4(p):
                    if q in r.tiles and q not in d0:
                        d0[q] = d0[p] + 1
                        nxt.append(q)
            todo = nxt
        depth.update(d0)
        pairs = [(ins[i], ins[j]) for i in range(len(ins)) for j in range(i + 1, len(ins))] or [(ins[0], heart)]
        for a, b2 in pairs:
            for p in lane_path(geo, r.tiles, back, a, b2):
                lane[p] = True
    # necks: a stretch of room two tiles wide or less that people walk through. Furniture there turns a passage
    # into a squeeze, so it stays clear. Small rooms are exempt (all of a closet is narrow).
    neck = geo.field("neck")
    for rid, r in geo.rooms.items():
        if r.attrs.get("hall") or len(r.tiles) < 12:
            continue
        for p in r.tiles:
            for d in (N, E):
                run, q = [p], step(p, d)
                while q in r.tiles:
                    run.append(q)
                    q = step(q, d)
                q = step(p, OPP[d])
                while q in r.tiles:
                    run.append(q)
                    q = step(q, OPP[d])
                if len(run) <= 2 and any(t in lane for t in run):
                    neck[p] = True
    geo.notes.append("fields: %d lane tiles, %d alcoves, %d neck tiles" % (len(lane), len(alcove), len(neck)))
