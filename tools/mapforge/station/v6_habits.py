"""The stock maps' room habits, laid into the v6 station (v6_station.py calls habits() after fixtures, before power).

forge/style_bands.py on station_v6 (2026-11-22) found the rooms emptier than their stock peers of the same type
(furniture x0.69, items x0.36, wall pieces x0.68) and short of what most stock rooms of a type have: light switches
(68% of stock rooms, 5 of 77 v6 rooms), holopads, status displays, newscasters, paper bins, office chairs. Plain
grey chairs stand where stock rooms use office chairs and stools.

Everything here is read off the room's stock peers (forge/room_stats.peers: Meta, Delta, Omega, Hippie rooms of the
same area type) and copied from their own atoms (vars too: a requests console keeps its department), never from a
list written here. Per room with 3+ stock peers:

  wall      a wall piece most peers hang (light switch, status display, requests console, extinguisher,
            newscaster, noticeboard, wall medkit, telescreen) and the room lacks goes on a free wall face; a
            light switch by a door, as the stock maps hang them. One piece per wall tile, both faces counted.
  holopad   when most peers have one: a free tile near the room's middle
  chairs    a plain /obj/structure/chair becomes the chair the peers use most (office, stool, comfy...), dir kept
  furniture while the room's furniture per tile is under 85% of the peers' median: a piece of furniture the
            peers have more of than the room (closets, racks, filing cabinets, tables, bookcases, vending,
            photocopiers, plants, dressers, water tanks), against a wall, off door aprons, never under a wall
            piece, and only where every door and every free tile of the room stays reachable
  items     while loose items per tile are under 80% of the peers' median: the peers' own items (paper bins,
            pens, manuals, folders, tools...) on the room's tables and racks, three to a tile at most, at the
            peers' pixel offsets

Not touched: halls, maint, the abandoned maint rooms (their own pass), the engine, gas chambers, cells, the AI core.
"""
import os
import random
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import dmm, kit, parse, room_stats as RS, typeindex  # noqa: E402
from forge.kit import CARD  # noqa: E402

MIN_PEERS = 3
WALL = {   # family -> kit.MOUNT kind
    "/obj/machinery/light_switch": "light_switch",
    "/obj/machinery/status_display/evac": "status_display",
    "/obj/machinery/status_display/ai": "status_display",
    "/obj/machinery/requests_console": "requests_console",
    "/obj/structure/extinguisher_cabinet": "extinguisher",
    "/obj/machinery/newscaster": "newscaster",
    "/obj/structure/noticeboard": "noticeboard",
    "/obj/machinery/vending/wallmed": "wallmed",
    "/obj/machinery/computer/security/telescreen": "telescreen",
}
FURNITURE = ("/obj/structure/closet", "/obj/structure/rack", "/obj/structure/filingcabinet", "/obj/structure/table",
             "/obj/structure/bookcase", "/obj/machinery/vending", "/obj/machinery/photocopier", "/obj/structure/dresser",
             "/obj/item/twohanded/required/kirbyplants", "/obj/structure/reagent_dispensers")
NOT_FURNITURE = ("/obj/machinery/vending/wallmed", "/obj/structure/table/reinforced", "/obj/structure/table/glass",
                 "/obj/structure/closet/crate/rcd","/obj/structure/closet/crate/secure/loot", "/obj/structure/table/optable",
                 "/obj/structure/reagent_dispensers/fueltank", "/obj/structure/closet/secure_closet/brig")
NO_ITEMS = ("/obj/item/gun", "/obj/item/grenade", "/obj/item/card", "/obj/item/disk", "/obj/item/melee", "/obj/item/grown",
            "/obj/item/reagent_containers/food/snacks/grown", "/obj/item/bombcore", "/obj/item/transfer_valve",
            "/obj/item/tank/internals/plasma", "/obj/item/aiModule", "/obj/item/assembly/signaler", "/obj/item/storage/backpack",
            "/obj/item/organ", "/obj/item/bodypart", "/obj/item/clothing/head/helmet/space", "/obj/item/mmi", "/obj/item/radio/intercom",
            "/obj/item/twohanded", "/obj/item/stack/sheet/mineral", "/obj/item/stack/spacecash", "/obj/item/coin", "/obj/item/key",
            "/obj/item/pinpointer", "/obj/item/hand_tele", "/obj/item/areaeditor/blueprints", "/obj/item/clothing/suit/armor",
            "/obj/item/storage/secure/briefcase", "/obj/item/storage/lockbox", "/obj/item/implant", "/obj/item/storage/box/syndie",
            "/obj/item/paper/fluff", "/obj/item/paper/guides", "/obj/item/paper/monitorkey", "/obj/item/photo")
SKIP_AREAS = ("/area/engine/supermatter", "/area/science/mixing/chamber", "/area/security/prison/cell",
              "/area/ai_monitored/turret_protected/ai", "/area/tcommsat/server", "/area/ai_monitored/nuke_storage",
              "/area/hallway", "/area/maintenance", "/area/solar", "/area/shuttle", "/area/space")
CHAIR_PLAIN = "/obj/structure/chair"
_ACC = []


def ACCEPTED_AREAS():
    """Areas of the accepted build (station/v6_tidy.accepted_areas), cached: the over-band guard is for copied rooms."""
    if not _ACC:
        from station.v6_tidy import accepted_areas
        _ACC.append(accepted_areas())
    return _ACC[0]


UNDERFLOOR = ("/obj/structure/cable", "/obj/machinery/atmospherics/pipe", "/obj/structure/disposalpipe")
POS = ("dir", "pixel_x", "pixel_y")


def _peer_atoms(peer):
    """family -> [atoms] in a stock room (atoms on its floor tiles)."""
    m = parse.load(peer.map).m
    out = defaultdict(list)
    for p in peer.tiles:
        t = m.get(p[0], p[1], 1)
        for a in t.objs:
            out[RS._family(a.path)].append(a)
    return out


_PA = {}
_LOOSE = {}


def loose_share(peers, fam):
    """The share of a family's pieces that stand off the wall in its stock rooms (no wall on any side of the tile):
    racks in tech storage, tables in a kitchen. The furniture step stands that share of what it adds in the room."""
    k = (tuple(sorted((p.map, p.area, p.box) for p in peers)), fam)
    if k not in _LOOSE:
        n = loose = 0
        for pr in peers:
            sm = parse.load(pr.map)
            for p in pr.tiles:
                t = sm.m.get(p[0], p[1], sm.z)
                if t is None or not any(RS._family(a.path) == fam for a in t.objs):
                    continue
                n += 1
                if not any(sm.cls.get((p[0] + dx, p[1] + dy)) == "W" for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                    loose += 1
        _LOOSE[k] = loose / float(n) if n else 0.0
    return _LOOSE[k]


def peer_atoms(peer):
    k = (peer.map, peer.area, peer.box)
    if k not in _PA:
        _PA[k] = _peer_atoms(peer)
    return _PA[k]


def _median(vs):
    vs = sorted(vs)
    return vs[len(vs) // 2] if vs else 0.0


def _mount_atom(src, kind, side):
    vs = [(k, v) for k, v in src.vars if k not in POS]
    return dmm.Atom(src.path, kit.mount_vars(kind, side) + vs)


class Room:
    def __init__(self, m, rm):
        self.m, self.rm = m, rm
        self.tiles = set(rm.tiles)
        self.doors = {q for p in rm.tiles for d in CARD for q in [(p[0] + kit.DELTA[d][0], p[1] + kit.DELTA[d][1])]
                      if self.t(q) is not None and self.t(q).has("/obj/machinery/door")}

    def t(self, p):
        return self.m.get(p[0], p[1])

    def free(self, p):
        """Nothing standing on the tile but decals, items, landmarks and what lies under the floor (cable, pipe,
        disposal pipe: habits runs after power and air, and counting those as taken left rooms whose free floor they
        cross with no furniture; stock furniture stands on them)."""
        if (self.t(p).tpath or "").startswith("/turf/open/floor/engine/"):
            return False        # a gas chamber's floor (atmos is furnished since 2026-11-22: furn 0.11, stock 0.22-0.26)
        return not any(o.path.startswith(("/obj/structure", "/obj/machinery", "/obj/item/twohanded/required/kirbyplants"))
                       and not o.path.startswith(UNDERFLOOR) for o in self.t(p).objs)

    def hung(self, p):
        """A wall piece hangs from the tile already (pixel-shifted, or a light/camera by its dir)."""
        return any(abs(o.num("pixel_x")) >= 16 or abs(o.num("pixel_y")) >= 16 or
                   (o.path.startswith(("/obj/machinery/light", "/obj/machinery/camera")) and not o.path.startswith("/obj/machinery/light/floor"))
                   for o in self.t(p).objs)

    def walkable(self, p):
        return not kit.dense(self.t(p).objs)

    def apron(self, p, r=1):
        return any(abs(p[0] - d[0]) + abs(p[1] - d[1]) <= r for d in self.doors)

    def wall_sides(self, p):
        out = []
        for d in CARD:
            q = self.t((p[0] + kit.DELTA[d][0], p[1] + kit.DELTA[d][1]))
            if q is not None and q.tpath.startswith("/turf/closed") and not q.has("/obj/machinery/door"):
                out.append(d)
        return out

    def _pieces(self, block):
        walk = {p for p in self.tiles if p != block and self.walkable(p)}
        seen, n = set(), 0
        for s0 in walk:
            if s0 in seen:
                continue
            n += 1
            seen.add(s0)
            q = [s0]
            while q:
                c = q.pop()
                for d in CARD:
                    nn = (c[0] + kit.DELTA[d][0], c[1] + kit.DELTA[d][1])
                    if nn in walk and nn not in seen:
                        seen.add(nn)
                        q.append(nn)
        doors = sum(1 for dr in self.doors if any((dr[0] + kit.DELTA[d][0], dr[1] + kit.DELTA[d][1]) in walk for d in CARD))
        return n, doors

    def connected_without(self, block):
        """With `block` made dense, the room's walkable floor stays in as many pieces as it is now and every door
        that opens onto walkable floor still does. A room the stock-room measure joins across a wall (pieces within 2
        tiles are one room) is already in several pieces; asking for one piece had kept engineering, atmos and the
        library lounge from getting any furniture (the gate 2026-11-22)."""
        if not hasattr(self, "_base"):
            self._base = self._pieces(None)
        if block not in self.tiles or not self.walkable(block):
            return self._pieces(block) == self._base
        return self._pieces(block) == self._base


def _used_walls(m):
    """Wall tiles that already carry a piece on either face (one piece per wall tile, rule R16)."""
    used = set()
    for (x, y, z), t in m.tiles.items():
        for o in t.objs:
            px, py = o.num("pixel_x"), o.num("pixel_y")
            if abs(px) >= 16 or abs(py) >= 16:
                used.add((x + (1 if px >= 16 else -1 if px <= -16 else 0), y + (1 if py >= 16 else -1 if py <= -16 else 0)))
            elif o.path.startswith(("/obj/machinery/light", "/obj/machinery/camera")) and not o.path.startswith(
                    ("/obj/machinery/light_switch", "/obj/machinery/light/floor")):
                d = o.num("dir", 2)
                if o.path.startswith("/obj/machinery/camera"):
                    d = kit.OPP.get(d, d)     # a camera looks away from its wall (kit.MOUNT camera: N wall -> dir 2)
                if d in kit.DELTA:
                    used.add((x + kit.DELTA[d][0], y + kit.DELTA[d][1]))
    return used


def habits(m, log, skip_exact=()):
    rnd = random.Random(1122)
    sm = parse.SemanticMap(m, "v6")
    used = _used_walls(m)
    made = Counter()
    # lights first: they need a bare wall face, which the furniture step below would otherwise fill (the locker
    # room's walls were all furniture when lights came last)
    made["light"] += lights_to_band(m, sm, used)
    for rm in sorted(RS.rooms(sm), key=lambda r: r.area):
        # skip_exact: areas that are corridors here (gen/learn's department corridors carry a room type's area: the
        # science corridor was lined with bio closets, 2026-11-26)
        if rm.area.startswith(SKIP_AREAS) or rm.area.endswith("abandoned") or "abandoned" in rm.area                 or rm.area in skip_exact:
            continue
        kind = RS.type_of(rm.area)
        peers = RS.peers(kind) if kind else []
        if len(peers) < MIN_PEERS:
            continue
        R = Room(m, rm)
        rnd = random.Random("habits|" + rm.area)     # per room: a shared stream let one room's change move them all
        pa = [peer_atoms(p) for p in peers]
        share = Counter()
        for a in pa:
            share.update(set(a))
        n = float(len(peers))
        have = set(rm.paths)

        # ---- wall pieces
        for fam, wk in WALL.items():
            if share[fam] / n < 0.5 or fam in have:
                continue
            src = next(a[fam][0] for a in pa if a.get(fam))
            if not typeindex.known(src.path):
                continue
            # never past the most wall pieces per face any stock room of the type has (the gate 2026-11-22)
            npieces, nfaces = RS.map_pieces(m, rm.tiles)
            if rm.area not in ACCEPTED_AREAS() and (npieces + 1) / float(max(1, nfaces)) > max(p.stats["pieces"] for p in peers):
                break
            faces = []
            for p in rm.tiles:
                if R.t(p).has("/obj/machinery/door") or not R.free(p) or R.hung(p):
                    continue
                for d in R.wall_sides(p):
                    w = (p[0] + kit.DELTA[d][0], p[1] + kit.DELTA[d][1])
                    if w not in used:
                        faces.append((p, d, w))
            if not faces:
                continue
            if wk == "light_switch":      # beside a door, inside, as the stock maps hang them
                faces.sort(key=lambda f: (min((abs(f[0][0] - d[0]) + abs(f[0][1] - d[1]) for d in R.doors), default=99), f[:2]))
                f = faces[0]
            else:
                f = rnd.choice(sorted(faces))
            p, d, w = f
            R.t(p).objs.append(_mount_atom(src, wk, d))
            used.add(w)
            made[wk] += 1

        # ---- holopad
        hp = max(("/obj/machinery/holopad", "/obj/machinery/holopad/secure"), key=lambda f: share[f])
        if (share["/obj/machinery/holopad"] + share["/obj/machinery/holopad/secure"]) / n >= 0.5 and \
                not any(f.startswith("/obj/machinery/holopad") for f in have) and len(rm.tiles) >= 9:
            cx, cy = rm.centre()
            spots = [p for p in rm.tiles if R.free(p) and R.walkable(p) and not R.apron(p) and
                     not R.t(p).has("/obj/effect/landmark") and not R.t(p).has("/obj/item")]
            if spots:
                p = min(spots, key=lambda q: ((q[0] - cx) ** 2 + (q[1] - cy) ** 2, q))
                R.t(p).objs.append(dmm.Atom(hp))
                made["holopad"] += 1

        # ---- chairs
        chairs = Counter()
        for a in pa:
            for fam, atoms in a.items():
                if fam.startswith("/obj/structure/chair/") and not fam.startswith(("/obj/structure/chair/e_chair", "/obj/structure/chair/pew")):
                    chairs.update(x.path for x in atoms)
        chairs = Counter({k: v for k, v in chairs.items() if typeindex.known(k)})
        if chairs:
            best = chairs.most_common(1)[0][0]
            for p in rm.tiles:
                for i, o in enumerate(R.t(p).objs):
                    if o.path == CHAIR_PLAIN:
                        R.t(p).objs[i] = dmm.Atom(best, [(k, v) for k, v in o.vars])
                        made["chair"] += 1

        # ---- furniture
        sn = parse.SemanticMap  # noqa: F841 (furn counted as room_stats does: corpus anchors)
        from forge import corpus
        def furn_count():
            return sum(1 for p in rm.tiles if corpus.furniture(R.t(p))[0])
        target = 0.85 * _median([p.stats["furn"] for p in peers]) * len(rm.tiles)
        if len(rm.tiles) >= 9:
            per_peer = Counter()
            for a in pa:
                for fam, atoms in a.items():
                    if fam.startswith(FURNITURE) and not fam.startswith(NOT_FURNITURE):
                        per_peer[fam] += len(atoms)
            mine = Counter(RS._family(o.path) for p in rm.tiles for o in R.t(p).objs)
            # what the peers have more of, per tile, than this room
            want = sorted(((per_peer[f] / n / max(1, sum(len(p.tiles) for p in peers) / n) * len(rm.tiles) - mine[f], f)
                           for f in per_peer), reverse=True)
            want = [f for gap, f in want if gap > 0.3]
            tries = 0
            added_loose = Counter()
            added_all = Counter()
            # never past the most dense floor any stock room of the type has (the gate 2026-11-22: security's main
            # room went to 0.28 against the stock 0.21-0.25 once the furniture step could place freely)
            dense_cap = max(p.stats["dense"] for p in peers) * len(rm.tiles)

            def dense_count():
                return sum(1 for p in rm.tiles if kit.dense(R.t(p).objs))
            while furn_count() < target and want and tries < 4 * len(rm.tiles) and dense_count() + 1 <= dense_cap:
                tries += 1
                fam = want[0]
                atoms = [x for a in pa for x in a.get(fam, ()) if typeindex.known(x.path)]
                if not atoms:
                    want.pop(0)
                    continue
                src = Counter(x.path for x in atoms).most_common(1)[0][0]
                # off the wall while this room's added share of the family is under the stock rooms' loose share
                loose = added_loose[fam] < loose_share(peers, fam) * (added_all[fam] + 1)
                spots = [p for p in sorted(rm.tiles) if R.free(p) and R.walkable(p) and (not R.wall_sides(p) if loose else R.wall_sides(p))
                         and not R.apron(p) and not any(o.path.startswith("/obj/effect/landmark") for o in R.t(p).objs)
                         and not R.hung(p)
                         and not any(R.t((p[0] + kit.DELTA[d][0], p[1] + kit.DELTA[d][1])) is not None and
                                     R.t((p[0] + kit.DELTA[d][0], p[1] + kit.DELTA[d][1])).has("/obj/machinery/computer")
                                     for d in CARD)]
                rnd.shuffle(spots)
                if loose:
                    # in rows: beside its own kind first, then nearest the room's middle
                    cx, cy = rm.centre()
                    spots.sort(key=lambda q: (-sum(1 for d in CARD if R.t((q[0] + kit.DELTA[d][0], q[1] + kit.DELTA[d][1])) is not None
                                                   and any(RS._family(o.path) == fam for o in R.t((q[0] + kit.DELTA[d][0], q[1] + kit.DELTA[d][1])).objs)),
                                              abs(q[0] - cx) + abs(q[1] - cy)))
                spot = next((p for p in spots if R.connected_without(p)), None)
                if spot is None:
                    if loose:
                        added_loose[fam] += 10 ** 6       # no loose spot left: the rest of it goes on the wall
                        continue
                    break
                R.t(spot).objs.append(dmm.Atom(src))
                added_all[fam] += 1
                added_loose[fam] += 1 if loose else 0
                made["furniture"] += 1
                want.append(want.pop(0))   # round-robin over what's short
                if fam.startswith(("/obj/machinery/vending", "/obj/machinery/photocopier")):
                    want.remove(fam)       # one each is plenty

        # ---- items on tables and racks
        target = 0.8 * _median([p.stats["items"] for p in peers]) * len(rm.tiles)
        pool = Counter()
        offs = defaultdict(list)
        for a in pa:
            for fam, atoms in a.items():
                for x in atoms:
                    if x.path.startswith("/obj/item") and not x.path.startswith(NO_ITEMS) and not corpus.mounted(x) \
                            and typeindex.known(x.path):
                        pool[x.path] += 1
                        offs[x.path].append((x.num("pixel_x"), x.num("pixel_y")))
        if pool:
            items = sum(sm.items.get(p, 0) for p in rm.tiles)
            surf = [p for p in sorted(rm.tiles) if (R.t(p).has("/obj/structure/table") or R.t(p).has("/obj/structure/rack"))
                    and not R.t(p).has("/obj/machinery")]
            rnd.shuffle(surf)
            paths, weights = zip(*sorted(pool.items()))
            for p in surf * 3:
                if items >= target:
                    break
                if sum(1 for o in R.t(p).objs if o.path.startswith("/obj/item")) >= 3:
                    continue
                path = rnd.choices(paths, weights)[0]
                px, py = rnd.choice(offs[path])
                vs = ([("pixel_x", str(px))] if px and abs(px) < 16 else []) + ([("pixel_y", str(py))] if py and abs(py) < 16 else [])
                R.t(p).objs.append(dmm.Atom(path, vs))
                items += 1
                made["item"] += 1
    log("habits: " + ", ".join("%d %s" % (v, k) for k, v in sorted(made.items())))


LIGHT_SKIP = ("/area/engine/supermatter", "/area/science/mixing/chamber", "/area/hallway", "/area/maintenance",
              "/area/solar", "/area/shuttle", "/area/space")


def lights_to_band(m, sm, used):
    """Lights per 10 tiles up to the least any stock room of the type has (forge/room_stats "lights"): the gate
    2026-11-22 found dorms, atmos, the gravity generator and tech storage below it after their redraws. Each new light
    is the type its stock peers use most, on a bare wall face as far from the room's other lights as it can be."""
    n_made = 0
    for rm in sorted(RS.rooms(sm), key=lambda r: r.area):
        if rm.area.startswith(LIGHT_SKIP) or "abandoned" in rm.area:
            continue
        kind = RS.type_of(rm.area)
        peers = RS.peers(kind) if kind else []
        if len(peers) < MIN_PEERS:
            continue
        lo = min(p.stats["lights"] for p in peers)
        R = Room(m, rm)
        n = float(len(rm.tiles))

        def is_light(o):
            return o.path.startswith("/obj/machinery/light") and not o.path.startswith("/obj/machinery/light_switch")
        have = [p for p in rm.tiles for o in R.t(p).objs if is_light(o)]
        paths = Counter(path for pr in peers for path, c in pr.paths.items() if path in ("/obj/machinery/light",
                        "/obj/machinery/light/small") for _ in range(c))
        path = paths.most_common(1)[0][0] if paths else "/obj/machinery/light"
        while 10.0 * len(have) / n < lo:
            faces = []
            for p in rm.tiles:
                if R.t(p).has("/obj/machinery/door") or not R.free(p) or R.hung(p) or R.apron(p):
                    continue
                for d in R.wall_sides(p):
                    w = (p[0] + kit.DELTA[d][0], p[1] + kit.DELTA[d][1])
                    if w not in used:
                        faces.append((p, d, w))
            if not faces:
                break
            p, d, w = max(faces, key=lambda f: (min((abs(f[0][0] - q[0]) + abs(f[0][1] - q[1]) for q in have), default=99), f[:2]))
            R.t(p).objs.append(dmm.Atom(path, kit.mount_vars("light", d)))
            used.add(w)
            have.append(p)
            n_made += 1
    return n_made
