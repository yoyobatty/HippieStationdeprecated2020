"""Kits and the placer.

A kit is an authored group of pieces that only works together: a fabricator, its belt and the pickup tile; an R&D
console and the machines it links; an operating table and its computer. It is written once in its own frame
(u along the wall, v out into the room) with the tiles a person stands on to use it. The placer sets it on a wall
(or free in the room) where the fields allow, and never where it would close a door, wall off floor, or leave a
piece nobody can reach.

Direction words inside a kit: IN (into the room), OUT (at the wall), A+ / A- (along the wall).
"""
import random

from .geo import S, CARD, DELTA, OPP, CW, CCW, NAME, step, nb4, nb8
from .shell import room_doors


class Kit:
    def __init__(self, name, cells, use=(), back="wall", mirror=True, tight=False):
        self.name = name
        self.cells = cells      # [(u, v, spec)]: spec keys obj, decal, floor, mount, open (walkable), label
        self.use = list(use)    # [(u, v)] tiles a person stands on; stay clear
        self.back = back        # "wall": solid wall behind every v=0 cell; "any": wall or glass; None: free-standing
        self.mirror = mirror
        self.tight = tight      # may stand right beside another kit's standing tiles (rows that share an aisle)


def cell(u, v, *obj, **kw):
    sp = dict(kw)
    sp["obj"] = list(obj)
    return (u, v, sp)


class Placement:
    def __init__(self, kit, origin, wall, mirrored):
        self.kit, self.origin, self.wall, self.mirrored = kit, origin, wall, mirrored
        self.n = OPP[wall]
        self.a = CCW[self.n] if mirrored else CW[self.n]

    def at(self, u, v):
        return step(step(self.origin, self.a, u), self.n, v)

    def dirword(self, w):
        return {"IN": self.n, "OUT": self.wall, "A+": self.a, "A-": OPP[self.a]}.get(w, w)

    @property
    def tiles(self):
        return [self.at(u, v) for u, v, _ in self.kit.cells]

    @property
    def uses(self):
        return [self.at(u, v) for u, v in self.kit.use]


JITTER = 2.5


def dist(p, q):
    return abs(p[0] - q[0]) + abs(p[1] - q[1])


class Ctx:
    """One room, as its asset sees it."""

    def __init__(self, geo, rid, P):
        self.geo, self.rid, self.P = geo, rid, P
        self.seed = P.get("seed", 1)        # 1 is the authored layout; any other seed nudges every choice
        self.room = geo.rooms[rid]
        self.tiles = self.room.tiles
        self.back = geo.field("back")
        self.lane = geo.field("lane")
        self.front = geo.field("front")
        self.trunk = geo.field("trunk")
        self.neck = geo.field("neck")
        self.counter = geo.attr.setdefault("_counter", {})
        self.faces = geo.attr.setdefault("_faces", {})    # (tile, wall side) a wall piece already hangs on
        self.hung = geo.attr.setdefault("_hung", {})      # wall tile a piece is drawn on, from whichever room

    # ---- reading the room
    def side(self, target):
        """The wall direction that faces a neighbour (a room id, or hall / maint / space)."""
        votes = {}
        for p in self.tiles:
            for d in CARD:
                q = step(p, d)
                if q in self.tiles:
                    continue
                if self.geo.beyond(step(q, d)) == target:
                    votes[d] = votes.get(d, 0) + 1
        return max(votes, key=lambda d: (votes[d], -d)) if votes else None

    def doors(self, target=None):
        """Tiles just inside this room's doors (to one neighbour, or all)."""
        out = []
        for p, q in room_doors(self.geo, self.rid):
            d = [k for k in CARD if step(q, k) == p][0]
            if target is None or self.geo.beyond(step(p, d)) == target:
                out.append(q)
        return sorted(out)

    def free(self, p):
        return p in self.tiles and p not in self.geo.taken

    def rect(self, x0, y0, x1, y1):
        return [(x, y) for x in range(min(x0, x1), max(x0, x1) + 1) for y in range(min(y0, y1), max(y0, y1) + 1)
                if (x, y) in self.tiles]

    def apron(self, target, depth, grow=0):
        """The floor in front of a (wide) door to a neighbour: `depth` tiles into the room, `grow` wider each side."""
        ins = self.doors(target)
        if not ins:
            return []
        d = OPP[self.side(target)]
        out = set()
        for q in ins:
            for k in range(depth):
                c = step(q, d, k)
                for g in range(-grow, grow + 1):
                    t = step(c, CW[d], g) if g >= 0 else step(c, CCW[d], -g)
                    if t in self.tiles:
                        out.add(t)
        return sorted(out)

    # ---- changing it
    def put(self, p, why, **spec):
        if why:
            self.geo.taken[p] = why
        if spec:
            self.geo.cells.setdefault(p, []).append(spec)

    def reserve(self, tiles, why="open"):
        for p in tiles:
            if self.geo.taken.get(p) != "obj":
                self.geo.taken[p] = why

    def zone(self, tiles, floor=None, edge=None):
        """A work zone: its own floor, and a striped edge where it meets the rest of the room."""
        tiles = set(tiles)
        for p in sorted(tiles):
            spec = {}
            if floor:
                spec["floor"] = floor
            if edge:
                dec = [(edge, {"dir": d}) if d != S else edge for d in CARD
                       if step(p, d) not in tiles and step(p, d) in self.tiles]
                if dec:
                    spec["decal"] = dec
            if spec:
                self.geo.cells.setdefault(p, []).append(spec)

    def mark(self, p, *obj, **kw):
        """A loose piece on one tile that blocks nothing (landmark, holopad, decal)."""
        sp = dict(kw)
        sp["obj"] = list(obj)
        self.geo.cells.setdefault(p, []).append(sp)

    # ---- the placer
    def _walk_ok(self, dense, uses):
        """With these tiles blocked: every door, use tile and free tile still joined, every piece reachable."""
        open_ = {p for p in self.tiles if p not in dense}
        need = set(self.doors()) | set(uses) | {p for p, w in self.geo.taken.items() if w == "use" and p in self.tiles}
        if not need <= open_:
            return False
        if not open_:
            return True
        seed = next(iter(need)) if need else next(iter(open_))
        seen, todo = {seed}, [seed]
        while todo:
            for q in nb4(todo.pop()):
                if q in open_ and q not in seen:
                    seen.add(q)
                    todo.append(q)
        if seen != open_:
            return False
        return all(any(q in open_ for q in nb4(p)) for p in dense)

    def _pinches(self, dense, new):
        """A new piece that leaves two open tiles touching only at a corner, with the piece and another blocked tile
        between them: nobody can step through that diagonal, so the aisle is shut though the map says it is open."""
        def shut(p):
            if p in self.tiles:
                return p in dense
            return not self.geo.walk(p) and self.geo.what(p) not in ("door", "keep_door")

        def open_(p):
            return (p in self.tiles and p not in dense) or (p not in self.tiles and self.geo.walk(p))
        for t in new:
            for dx in (-1, 1):
                for dy in (-1, 1):
                    c = (t[0] + dx, t[1] + dy)
                    if shut(c) and open_((t[0] + dx, t[1])) and open_((t[0], t[1] + dy)):
                        return True
        return False

    def _last_face(self, t, w):
        """True when hanging on (t, w) would leave the room fewer than three free faces of solid wall: the builder
        still hangs a fire alarm, an air alarm and a light there, and glass and doors carry none of them."""
        if self.back.get(t, {}).get(w) != "wall":
            return False
        left = 0
        for q in self.tiles:
            for d, b in self.back.get(q, {}).items():
                if b == "wall" and (q, d) != (t, w) and (q, d) not in self.faces and step(q, d) not in self.hung:
                    left += 1
                    if left >= 3:
                        return False
        return True

    def candidates(self, kit, side=None, on=None):
        sides = [side] if isinstance(side, int) else list(side) if side else list(CARD)
        dense_now = {p for p in self.tiles if self.geo.taken.get(p) == "obj"}
        for o in sorted(self.tiles):
            if on is not None and o not in on:
                continue
            for w in sides:
                if kit.back and self.back.get(o, {}).get(w) is None:
                    continue
                for mir in ((False, True) if kit.mirror else (False,)):
                    pl = Placement(kit, o, w, mir)
                    ok, dense = True, set()
                    for u, v, sp in kit.cells:
                        t = pl.at(u, v)
                        if t not in self.tiles:
                            ok = False
                            break
                        if v == 0 and kit.back:
                            b = self.back.get(t, {}).get(w)
                            if b is None or b == "door" or (kit.back == "wall" and b != "wall"):
                                ok = False
                                break
                        if sp.get("mount") and ((t, w) in self.faces or step(t, w) in self.hung):
                            ok = False
                            break
                        # one wall piece per floor tile, and none over furniture (v6 reviews, 2026-11-21): a tile
                        # carries an alarm or a button, not two, and never one behind a vendor or closet
                        if sp.get("mount") and not getattr(self, "_relax", False) and (
                                any((t, d) in self.faces for d in CARD) or self.geo.taken.get(t) == "obj"):
                            ok = False
                            break
                        if sp.get("mount") and self._last_face(t, w):
                            ok = False              # the builder hangs the room's light on the last solid face
                            break
                        if sp.get("free"):
                            continue
                        if t in self.trunk and any("/disposal/bin" in (o if isinstance(o, str) else o[0])
                                                   for o in sp.get("obj", [])):
                            ok = False                              # a bin can't stand on the station's line
                            break
                        if sp.get("seat") and t in self.front:      # nobody sits in a doorway
                            ok = False
                            break
                        if self.geo.taken.get(t) == "obj":
                            ok = False
                            break
                        if sp.get("open"):
                            continue
                        if t in self.geo.taken or t in self.front or t in self.neck:
                            ok = False              # taken, a door apron, or a passage two tiles wide or less
                            break
                        if any((t, d) in self.faces for d in CARD):
                            ok = False              # a wall piece already hangs here: furniture would hide it
                            break
                        if kit.back is None and not kit.tight and any(self.geo.taken.get(q) == "use" for q in nb8(t)):
                            ok = False              # an island never crowds the tiles another kit is used from
                            break
                        dense.add(t)
                    if not ok:
                        continue
                    uses = pl.uses
                    if any(t not in self.tiles or t in dense or self.geo.taken.get(t) == "obj" for t in uses):
                        continue
                    if not self._walk_ok(dense_now | dense, uses):
                        continue
                    if self._pinches(dense_now | dense, dense):
                        continue
                    yield pl, dense

    FUNCTIONAL = ("button", "requests_console", "intercom", "telescreen")

    def place(self, kit, side=None, near=None, far=None, on=None, need=None, score=None, must=True, zone=None, **fmt):
        best = None
        for pl, dense in self.candidates(kit, side, on):
            if need and not need(pl):
                continue
            ref = pl.uses[0] if pl.uses else pl.origin
            s = 0.0
            if near is not None:
                s += dist(ref, near)
            if far is not None:
                s -= 0.5 * dist(ref, far)
            s += 4.0 * sum(1 for t in dense if t in self.lane)
            if score:
                s += score(pl)
            if self.seed != 1:
                # a seeded nudge of up to JITTER tiles: spots that score about the same trade places between seeds,
                # while a clearly better spot (nearer its door, off the lane) still wins
                s += JITTER * random.Random("%s|%s|%s|%s|%s|%s" % (self.seed, self.rid, kit.name, pl.origin, pl.wall,
                                                                    pl.mirrored)).random()
            key = (round(s, 3), pl.origin, pl.wall, pl.mirrored)
            if best is None or key < best[0]:
                best = (key, pl, dense)
        if best is None:
            # a working piece (a button, an RC, an intercom) still goes up in a crowded room: over furniture or
            # beside another piece rather than not at all (Science review 3: the biohazard and mech bay buttons and
            # the intercoms went missing under the one-piece rule)
            if not getattr(self, "_relax", False) and any(
                    m[0] in self.FUNCTIONAL for _, _, sp in kit.cells for m in sp.get("mount", [])):
                self._relax = True
                try:
                    return self.place(kit, side=side, near=near, far=far, on=on, need=need, score=score, must=must,
                                      zone=zone, **fmt)
                finally:
                    self._relax = False
            if must:
                self.geo.problem("%s: no place for %s" % (self.rid, kit.name))
            return None
        _, pl, dense = best
        self.last_score = best[0][0]
        n = self.counter[kit.name] = self.counter.get(kit.name, 0) + 1
        fmt = dict(fmt, n=n)
        for u, v, sp in kit.cells:
            t = pl.at(u, v)
            out = {k: val for k, val in sp.items() if k not in ("open", "free", "seat")}
            out["obj"] = [_resolve(o, pl, fmt) for o in sp.get("obj", [])]
            if "decal" in sp:
                out["decal"] = [_resolve(o, pl, fmt) for o in sp["decal"]]
            if "mount" in sp:
                out["mount"] = [(m[0], m[1], dict(_resolve((m[1], m[2] if len(m) > 2 else {}), pl, fmt)[1])) for m in sp["mount"]]
                out["mount_side"] = NAME[pl.dirword(sp.get("mount_side", "OUT"))]
                self.faces[(t, pl.wall)] = kit.name
                self.hung[step(t, pl.wall)] = kit.name
            self.geo.cells.setdefault(t, []).append(out)
            if sp.get("free"):
                continue
            if not sp.get("open"):
                self.geo.taken[t] = "obj"
            elif self.geo.taken.get(t) != "obj":
                self.geo.taken[t] = "open"
        for t in pl.uses:
            if self.geo.taken.get(t) != "obj":
                self.geo.taken[t] = "use"
        self.geo.placed.append((kit.name, self.rid, pl.origin, pl.wall, pl.mirrored, sorted(dense)))
        if zone:        # (floor, edge): the kit and the tiles it is used from become one marked work zone
            self.zone(pl.tiles + pl.uses, floor=zone[0], edge=zone[1])
        return pl

    def _snap(self):
        g = self.geo
        return (dict(g.taken), {k: list(v) for k, v in g.cells.items()}, list(g.placed), dict(self.faces),
                dict(self.counter), list(g.notes), list(g.problems), dict(self.hung))

    def _restore(self, s):
        g = self.geo
        for live, old in ((g.taken, s[0]), (g.cells, s[1]), (self.faces, s[3]), (self.counter, s[4]), (self.hung, s[7])):
            live.clear()
            live.update(old)
        g.placed[:], g.notes[:], g.problems[:] = s[2], s[5], s[6]

    def box(self, tiles):
        """The room's tiles inside the rectangle around some tiles (a kit's whole footprint, gaps included)."""
        xs, ys = [p[0] for p in tiles], [p[1] for p in tiles]
        return self.rect(min(xs), min(ys), max(xs), max(ys))

    def run(self, kits, side=None, near=None, **kw):
        """Kits one after another along a wall, each beside the last."""
        out, prev, wall = [], near, side
        if side is None and len(kits) > 1 and all(k.back for k in kits):
            # try each wall and undo: the run goes where the most of it fits, then where it sits closest
            best = None
            for w in CARD:
                snap = self._snap()
                n, cost, p0 = 0, 0.0, near
                for k in kits:
                    pl = self.place(k, side=w, near=p0, must=False, **kw)
                    if pl is None:
                        break
                    n, cost, p0 = n + 1, cost + self.last_score, pl.origin
                self._restore(snap)
                if n and (best is None or (-n, cost, w) < best[0]):
                    best = ((-n, cost, w), w)
            if best:
                wall = best[1]
        for k in kits:
            pl = self.place(k, side=wall, near=prev, must=False, **kw)
            if pl is None and wall != side:      # that wall is full: carry on round the corner
                pl = self.place(k, side=side, near=prev, must=False, **kw)
            if pl is not None and k.back:
                wall = pl.wall                   # a run stays on the wall it started on
            if pl is None:
                self.geo.notes.append("%s: no room left for %s" % (self.rid, k.name))
                continue
            out.append(pl)
            prev = pl.origin
        return out


def _resolve(o, pl, fmt):
    """Direction words and {id} names in a piece's vars."""
    if isinstance(o, str):
        return o
    path, vs = o
    out = {}
    for k, v in vs.items():
        if k == "dir" and isinstance(v, str):
            v = pl.dirword(v)
        elif k == "dir" and isinstance(v, tuple):      # a bend: two direction words
            v = pl.dirword(v[0]) | pl.dirword(v[1])
        elif k == "pixel_wall":                        # shifted onto the wall behind the kit by v pixels
            dx, dy = DELTA[pl.wall]
            if dx:
                out["pixel_x"] = dx * v
            if dy:
                out["pixel_y"] = dy * v
            continue
        elif isinstance(v, str) and "{" in v:
            v = v.format(**fmt)
        out[k] = v
    return (path, out)
