"""Departments grown the way the human maps build them (studies/dept_shapes.py).

The human departments are not a rectangle cut into rooms. A department hall runs in from the lobby; rooms of their
own sizes hang off it, front rooms near the door, labs and stores deeper; where the rooms run out of hall the hall
branches (a T, an L, a side passage), and the rooms that want to be apart (xenobiology, virology, perma, the range)
sit at the end of a long narrow passage of their own. Cells and cabins are rows of small rooms. The outline steps in
and out, about 0.6 of its bounding box, with 100+ corners against a rectangle's 4; the gaps are maint and wall.

So the grower works on a grid in the department's own frame (u across, v out from the main hall, region W x Dm):
    1  the spine: department hall from the entrance at v=0, 2-3 wide, part way in
    2  rooms in order (lobby, then tier by tier, biggest first): every placement that touches what the room needs
       (the ring for counters, a department hall for its door, the hull for docks and the engine, its linked room),
       scored for tier depth, packing against neighbours, sparing hall frontage, staying near the entrance
    3  no placement: grow a hall (extend one past its end, or branch off its side) toward the most free space, retry
    4  wings: a long 1-2 wide branch first, then the room at its end
    5  L ears on some big rooms; hall stubs nothing uses are cut back
"""
import math
import random

from station.layout import Local

D4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
WING = {"xeno": 0.7, "virology": 0.6, "perma": 0.55, "range": 0.4}
ROWS = {"cells": ("cell", 12, (3, 4)), "cabins": ("cabin", 14, (3, 4))}


class Grower:
    def __init__(self, d, W, Dm, seed, left_front=None, right_front=None):
        self.d, self.W, self.Dm, self.lf, self.rf = d, W, Dm, left_front, right_front
        self.rnd = random.Random("grow|%s|%s|%d|%d" % (seed, d.name, W, Dm))
        self.own = {}           # tile -> id
        self.kind = {}          # id -> hall / room
        self.rooms = []         # (rect, id, meta)
        self.halls = []         # dict(id, rect, axis, sgn): axis 1 runs along v
        self.broken = []
        self.ncross = 0
        self.links = {}
        self.inner = set()      # rooms laid inside their host's block (no door of their own)
        self.behind = set()     # kept clear behind rooms that need the hull

    # ---------------------------------------------------------------- grid
    def room_free(self, rect, ok=()):
        x0, y0, x1, y1 = rect
        if x0 < 0 or y0 < 0 or x1 >= self.W or y1 >= self.Dm:
            return False
        own, behind = self.own, self.behind
        for x in range(x0 - 1, x1 + 2):
            for y in range(y0 - 1, y1 + 2):
                r = own.get((x, y))
                if r is not None and r not in ok:
                    return False
                if (x, y) in behind and x0 <= x <= x1 and y0 <= y <= y1:
                    return False
        return True

    def hall_free(self, rect):
        x0, y0, x1, y1 = rect
        if x0 < 0 or y0 < 0 or x1 >= self.W or y1 >= self.Dm:
            return False
        own, kind = self.own, self.kind
        for x in range(x0 - 1, x1 + 2):
            for y in range(y0 - 1, y1 + 2):
                r = own.get((x, y))
                if r is None:
                    continue
                inside = x0 <= x <= x1 and y0 <= y <= y1
                if inside or kind[r] != "hall":
                    return False
        if any((x, y) in self.behind for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)):
            return False
        return True

    def put(self, rect, rid, kind, meta):
        x0, y0, x1, y1 = rect
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                self.own[(x, y)] = rid
        self.kind[rid] = kind
        if kind == "room":
            self.rooms.append((rect, rid, meta))
            # open space behind a room that needs the hull: nothing goes there after it
            if "back" in (meta.get("front") or ()):
                for x in range(x0 - 1, x1 + 2):
                    for y in range(y1 + 1, self.Dm):
                        self.behind.add((x, y))

    def contacts(self, rect):
        """Ids across one wall line from the rect, with how many tiles of wall they share."""
        x0, y0, x1, y1 = rect
        own = self.own
        c = {}

        def see(w, b):
            if w in own:
                return
            r = own.get(b)
            if r is not None:
                c[r] = c.get(r, 0) + 1
        for x in range(x0, x1 + 1):
            see((x, y0 - 1), (x, y0 - 2))
            see((x, y1 + 1), (x, y1 + 2))
        for y in range(y0, y1 + 1):
            see((x0 - 1, y), (x0 - 2, y))
            see((x1 + 1, y), (x1 + 2, y))
        return c

    # ---------------------------------------------------------------- halls
    def add_hall(self, rect, hid, axis, sgn):
        self.put(rect, hid, "hall", None)
        self.halls.append(dict(id=hid, rect=rect, axis=axis, sgn=sgn))

    def hall_options(self, width=None, long=False):
        """Ways to grow the halls: past an end, or off a side. (value, rect, id, axis, sgn)."""
        out = []
        rnd = self.rnd
        for h in self.halls:
            x0, y0, x1, y1 = h["rect"]
            cw = width or (h["rect"][2] - h["rect"][0] + 1 if h["axis"] == 1 else h["rect"][3] - h["rect"][1] + 1)
            cw = max(1, min(cw, 3))
            lo, hi = (6, 14) if long else (4, 10)
            k = rnd.randint(lo, hi)
            # past the end
            if h["axis"] == 1:
                ends = [((x0, y1 + 1, x1, y1 + k), 1, 1)] if h["sgn"] > 0 else [((x0, y0 - k, x1, y0 - 1), 1, -1)]
            else:
                ends = [((x1 + 1, y0, x1 + k, y1), 0, 1)] if h["sgn"] > 0 else [((x0 - k, y0, x0 - 1, y1), 0, -1)]
            for rect, axis, sgn in ends:
                out.append((rect, h["id"], axis, sgn))
            # off a side, at a few points along it
            if h["axis"] == 1:
                pts = list(range(y0, y1 - cw + 2))
                rnd.shuffle(pts)
                for p in pts[:5]:
                    out.append(((x1 + 1, p, x1 + k, p + cw - 1), None, 0, 1))
                    out.append(((x0 - k, p, x0 - 1, p + cw - 1), None, 0, -1))
            else:
                pts = list(range(x0, x1 - cw + 2))
                rnd.shuffle(pts)
                for p in pts[:5]:
                    out.append(((p, y1 + 1, p + cw - 1, y1 + k), None, 1, 1))
                    out.append(((p, y0 - k, p + cw - 1, y0 - 1), None, 1, -1))
        res = []
        for rect, hid, axis, sgn in out:
            # shorten until it fits, keep it if 3+ long
            while True:
                x0, y0, x1, y1 = rect
                n = (y1 - y0 + 1) if axis == 1 else (x1 - x0 + 1)
                if n < 3:
                    rect = None
                    break
                if self.hall_free(rect):
                    break
                if axis == 1:
                    rect = (x0, y0, x1, y1 - 1) if sgn > 0 else (x0, y0 + 1, x1, y1)
                else:
                    rect = (x0, y0, x1 - 1, y1) if sgn > 0 else (x0 + 1, y0, x1, y1)
            if rect is None:
                continue
            res.append((self.opens(rect, axis) + 6 * rnd.random(), rect, hid, axis, sgn))
        res.sort(key=lambda o: -o[0])
        return res

    def opens(self, rect, axis):
        """Free floor a new hall would front: tiles 2-6 out either side that nothing owns."""
        x0, y0, x1, y1 = rect
        n = 0
        own = self.own
        if axis == 1:
            for y in range(y0, y1 + 1):
                for dx in list(range(2, 7)) + list(range(-6, -1)):
                    x = (x1 + dx) if dx > 0 else (x0 + dx)
                    if 0 <= x < self.W and (x, y) not in own:
                        n += 1
        else:
            for x in range(x0, x1 + 1):
                for dy in list(range(2, 7)) + list(range(-6, -1)):
                    y = (y1 + dy) if dy > 0 else (y0 + dy)
                    if 0 <= y < self.Dm and (x, y) not in own:
                        n += 1
        return n

    def undo_hall(self, h):
        x0, y0, x1, y1 = h["rect"]
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                self.own.pop((x, y), None)
        self.halls.remove(h)

    def grow_for(self, r, tv):
        """Try the likeliest ways to grow the halls until one lets the room in; keep that one."""
        opts = self.hall_options()
        for val, rect, hid, axis, sgn in opts[:14]:
            new = hid is None
            if new:
                hid = "%s_cross%d" % (self.d.name, self.ncross)
            self.add_hall(rect, hid, axis, sgn)
            got = self.place(r, tv)
            if got:
                if new:
                    self.ncross += 1
                return got
            self.undo_hall(self.halls[-1])
            if new:
                self.kind.pop(hid, None)
        return None

    def grow(self, width=None, long=False):
        opts = self.hall_options(width, long)
        if not opts:
            return None
        val, rect, hid, axis, sgn = opts[0]
        if hid is None:
            hid = "%s_cross%d" % (self.d.name, self.ncross)
            self.ncross += 1
        self.add_hall(rect, hid, axis, sgn)
        return hid

    # ---------------------------------------------------------------- rooms
    def dims(self, r, area=None):
        a = area or r.area
        s0, s1 = sorted(r.min)
        out = set()
        for asp in (1.0, 1.35, 1.8, 2.3):
            short = max(s0, int(round(math.sqrt(a / asp))))
            lng = max(s1, int(round(a / float(short))))
            if lng < short:
                short, lng = lng, short
            if short < s0 or lng < s1:
                continue
            out.add((short, lng))
            out.add((lng, short))
        return sorted(out)

    def anchors(self, r, dims, prefer):
        fr = set(r.front)
        placed_partners = [k for k in self.links.get(r.id, ()) if k in self.kind]
        own, kind = self.own, self.kind
        if prefer:
            src = [t for t, k in own.items() if k == prefer]
        elif "dept" in fr:
            src = [t for t, k in own.items() if kind[k] == "hall"]
        elif placed_partners:
            src = [t for t, k in own.items() if k in placed_partners]
        elif "ring" in fr:
            src = [(x, -2) for x in range(self.W)] + ([(-2, y) for y in range(self.Dm)] if self.lf else []) + \
                ([(self.W + 1, y) for y in range(self.Dm)] if self.rf else [])
        elif "back" in fr:
            src = [(x, self.Dm + 1) for x in range(self.W)]
        else:
            src = [t for t, k in own.items() if kind[k] == "hall"]
        rects = set()
        for sx, sy in src:
            for dx, dy in D4:
                w = (sx + dx, sy + dy)
                e = (sx + 2 * dx, sy + 2 * dy)
                if w in own or e in own:
                    continue
                ex, ey = e
                for a, b in dims:
                    if dx == 1:
                        rects.update((ex, y, ex + a - 1, y + b - 1) for y in range(ey - b + 1, ey + 1))
                    elif dx == -1:
                        rects.update((ex - a + 1, y, ex, y + b - 1) for y in range(ey - b + 1, ey + 1))
                    elif dy == 1:
                        rects.update((x, ey, x + a - 1, ey + b - 1) for x in range(ex - a + 1, ex + 1))
                    else:
                        rects.update((x, ey - b + 1, x + a - 1, ey) for x in range(ex - a + 1, ex + 1))
        return rects

    def fits(self, r, rect, c):
        fr = set(r.front)
        if "ring" in fr and not (rect[1] == 0 or (self.lf and rect[0] == 0) or (self.rf and rect[2] == self.W - 1)):
            return False
        if "back" in fr:
            # docks need the region's back edge; the rest (range, engine) only nothing of ours behind them
            if r.dock:
                if rect[3] != self.Dm - 1:
                    return False
            elif any((x, y) in self.own for x in range(rect[0] - 1, rect[2] + 2) for y in range(rect[3] + 1, self.Dm)):
                return False
        if ("dept" in fr or r is self.d.lobby) and not any(self.kind.get(k) == "hall" for k in c):
            return False
        partners = [k for k in self.links.get(r.id, ()) if k in self.kind]
        if not fr and partners and not any(k in c for k in partners):
            return False
        for k in self.links.get(r.id, ()):
            if k in self.kind and k not in c and k not in self.inner:
                return False
        return True

    def place(self, r, tv, prefer=None, shrink=1.0):
        best = None
        dims = self.dims(r, int(r.area * shrink))
        rnd = self.rnd
        for rect in self.anchors(r, dims, prefer):
            if not self.room_free(rect):
                continue
            c = self.contacts(rect)
            if not self.fits(r, rect, c):
                continue
            if prefer and prefer not in c:
                continue
            x0, y0, x1, y1 = rect
            cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
            hall = sum(n for k, n in c.items() if self.kind[k] == "hall")
            room = sum(n for k, n in c.items() if self.kind[k] == "room")
            s = abs(cy - tv) * 0.6
            s += max(0, hall - 4) * 0.35
            s -= min(room, 14) * 0.22
            # stay near the entrance; counters on the main hall most of all (or they wander off down the arm)
            pull = 0.3 if "ring" in r.front else 0.08
            s += pull * (abs(cx - self.ex) + cy)
            w, h = x1 - x0 + 1, y1 - y0 + 1
            s += 1.5 * max(0.0, max(w, h) / float(min(w, h)) - 2.0)
            for k in r.near:
                ts = [p for p, q in self.own.items() if q == k]
                if ts:
                    # 0.25 lost to the pull toward the entrance: hydroponics stayed three rooms from the kitchen
                    s += 0.7 * min(abs(p[0] - cx) + abs(p[1] - cy) for p in ts)
            s += rnd.random() * 2.2
            if best is None or s < best[0]:
                best = (s, rect)
        return best[1] if best else None

    def ear(self, rect, rid):
        """An L: a shallow block off one side of the room that faces no hall."""
        x0, y0, x1, y1 = rect
        w, h = x1 - x0 + 1, y1 - y0 + 1
        rnd = self.rnd
        sides = ["n", "s", "e", "w"]
        rnd.shuffle(sides)
        for sd in sides:
            dep = rnd.randint(2, 3)
            if sd in ("n", "s"):
                span = max(3, int(w * rnd.uniform(0.4, 0.7)))
                if span >= w:
                    continue
                a = x0 if rnd.random() < 0.5 else x1 - span + 1
                er = (a, y1 + 1, a + span - 1, y1 + dep) if sd == "n" else (a, y0 - dep, a + span - 1, y0 - 1)
            else:
                span = max(3, int(h * rnd.uniform(0.4, 0.7)))
                if span >= h:
                    continue
                a = y0 if rnd.random() < 0.5 else y1 - span + 1
                er = (x1 + 1, a, x1 + dep, a + span - 1) if sd == "e" else (x0 - dep, a, x0 - 1, a + span - 1)
            if not self.room_free(er, ok=(rid,)):
                continue
            # not against a hall (it would eat frontage other rooms need), and not cutting a wall line in two
            if any(self.kind.get(k) == "hall" for k in self.contacts(er)):
                continue
            return er
        return None

    # ---------------------------------------------------------------- the department
    def run(self):
        d, rnd = self.d, self.rnd
        rooms = []
        for r in d.rooms:
            if r.id in ROWS and r.area >= 20:
                lab, unit, mn = ROWS[r.id]
                n = max(2, int(round(r.area / float(unit))))
                for i in range(n):
                    u = _copy(r, "%s_%d" % (r.id, i), max(mn[0] * mn[1], r.area // n), mn, lab if i else r.label)
                    u.near = ("%s_%d" % (r.id, i - 1),) if i else ()
                    rooms.append(u)
            else:
                rooms.append(r)
        for r in rooms:
            for k in r.links:
                self.links.setdefault(r.id, set()).add(k)
                self.links.setdefault(k, set()).add(r.id)
        tiers = max(r.tier for r in rooms) + 1
        ids = {r.id: r for r in rooms}
        self.hosted = {}
        for r in rooms:
            if r.front:
                continue
            host = next((ids[k] for k in self.links.get(r.id, ()) if k in ids and ids[k].front), None)
            if host is not None:
                self.hosted.setdefault(host.id, []).append(r)
                self.inner.add(r.id)
        # the spine
        sw = d.spine
        self.ex = rnd.randint(max(0, int(self.W * 0.25)), max(0, int(self.W * 0.75) - sw))
        if self.lf and rnd.random() < 0.3:
            self.ex = rnd.randint(4, max(4, self.W // 3))
        L0 = max(4, int(self.Dm * rnd.uniform(0.4, 0.7)))
        self.add_hall((self.ex, 0, self.ex + sw - 1, L0 - 1), d.name + "_spine", 1, 1)
        # the hall skeleton before any room: rooms packed along a hall leave no gap for a branch to start in, so
        # branch now until the halls front about what the rooms need (both sides of a hall take doors)
        need = 0.6 * sum(max(3, int(math.sqrt(r.area))) + 1 for r in rooms
                         if "dept" in r.front and r.id not in WING)
        have = L0
        for _ in range(4):
            if have >= need:
                break
            hid = self.grow(long=True)
            if not hid:
                break
            h = self.halls[-1]["rect"]
            have += max(h[2] - h[0], h[3] - h[1]) + 1
        order = []
        if d.lobby:
            order.append(d.lobby)
        for t in range(tiers):
            tier = sorted([r for r in rooms if r.tier == t], key=lambda r: -r.area)
            # linked rooms with no door of their own follow their partner
            done = set()
            for r in tier:
                if r.id in done:
                    continue
                if not r.front and any(k in {x.id for x in tier} for k in self.links.get(r.id, ())):
                    continue
                order.append(r)
                done.add(r.id)
                for k in self.links.get(r.id, ()):
                    p = next((x for x in tier if x.id == k and not x.front), None)
                    if p and p.id not in done:
                        order.append(p)
                        done.add(p.id)
            for r in tier:
                if r.id not in done:
                    order.append(r)
        span = max(4.0, self.Dm * 0.8)
        order = [r for r in order if r.id not in self.inner]
        pending = []
        queue = list(order)
        while queue or pending:
            if pending:
                r = pending.pop(0)
            else:
                r = queue.pop(0)
            tv = 0.0 if r is d.lobby else (r.tier + 0.5) / tiers * span
            guests = self.hosted.get(r.id, [])
            if guests:
                if self.place_hosted(r, guests, tv):
                    continue
                for g in guests:
                    self.inner.discard(g.id)
                    pending.append(g)
            meta = dict(kind="room", public=r.public, secure=r.secure, front=r.front, label=r.label,
                        links=tuple(r.links), maint=r.maint, dock=r.dock, lobby=r is d.lobby)
            rect = None
            if r.id in WING and rnd.random() < WING[r.id] and self.d.name not in ("arrivals", "escape"):
                hid = self.grow(width=rnd.choice((1, 2, 2)), long=True)
                if hid:
                    rect = self.place(r, tv, prefer=hid)
            tries = 0
            while rect is None and tries < 5:
                rect = self.place(r, tv) or self.grow_for(r, tv) or \
                    (self.place(r, tv, shrink=0.8) if tries >= 1 else None)
                if rect is None:
                    if not self.grow():
                        break
                    tries += 1
            if rect is None:
                self.broken.append("%s: no room for %s" % (d.name, r.id))
                continue
            self.put(rect, r.id, "room", meta)
            # human rooms are mostly not rectangles (77% odd-shaped in the study): many get an L
            if r.area >= 24 and not r.dock and rnd.random() < 0.6:
                er = self.ear(rect, r.id)
                if er:
                    self.put(er, r.id, "room", meta)
        self.trim()
        self.notch()
        return self

    def place_hosted(self, r, guests, tv):
        """A room and the rooms reached only through it, as one block: the host keeps the side on the hall, the
        guests share a strip along the back."""
        from station.program import Rm
        ga = sum(g.area for g in guests)
        # deep enough for a host 4+ deep, the wall and a guest strip 3+ deep: a 7-deep block left the captain's office
        # and bedroom two 3x15 corridors side by side (2026-11-16 quad review, every seed)
        big = Rm(r.id, r.area + ga + int(math.sqrt(r.area + ga)), r.tier, r.front,
                 (max(8, max(r.min)), max(8, min(r.min) + 5)),
                 (), 0, r.label, r.secure, r.public, r.maint, r.corridor, r.near, r.dock)
        for shrink in (1.0, 0.85):
            rect = self.place(big, tv, shrink=shrink)
            if rect is None:
                continue
            x0, y0, x1, y1 = rect
            # which side is on a hall (or the ring, for counters)
            score = {}
            for sd, tiles in (("s", [((x, y0 - 1), (x, y0 - 2)) for x in range(x0, x1 + 1)]),
                              ("n", [((x, y1 + 1), (x, y1 + 2)) for x in range(x0, x1 + 1)]),
                              ("w", [((x0 - 1, y), (x0 - 2, y)) for y in range(y0, y1 + 1)]),
                              ("e", [((x1 + 1, y), (x1 + 2, y)) for y in range(y0, y1 + 1)])):
                n = sum(1 for w, b in tiles if w not in self.own and self.kind.get(self.own.get(b)) == "hall")
                if "ring" in r.front and ((sd == "s" and y0 == 0) or (sd == "w" and x0 == 0 and self.lf) or
                                          (sd == "e" and x1 == self.W - 1 and self.rf)):
                    n += 50
                score[sd] = n
            front = max(score, key=lambda k: score[k])
            back = {"s": "n", "n": "s", "w": "e", "e": "w"}[front]
            length = (x1 - x0 + 1) if back in ("n", "s") else (y1 - y0 + 1)
            depth = (y1 - y0 + 1) if back in ("n", "s") else (x1 - x0 + 1)
            # a room you live or perform in is 4+ deep: a 3-deep strip left the captain's bedroom 3x10 and the
            # theatre 3x9 (closets like the server room may stay 3)
            t = max(4 if max(g.area for g in guests) >= 24 else 3, int(math.ceil(ga / float(length))))
            if depth - t - 1 < 3 or length < 3 * len(guests) + len(guests) - 1:
                continue
            # no corridor-shaped rooms: the host and each guest at most 3:1
            host_d = depth - t - 1
            # (a guest's share of the strip is its length; too narrow is a corridor too: theatre 3 along a 9-deep strip).
            # The shares are the widths the guests really get: the strip less a wall between each two, a living room
            # 4+ wide (the share before this left the wall out and the kitchen's rounding took the theatre to 3)
            shares = self.split_strip(length, guests)
            if host_d < 4 or length > 3 * host_d or not shares or \
                    any(s < (4 if g.area >= 24 else 3) or max(s, t) > 3 * min(s, t) for s, g in zip(shares, guests)):
                continue
            meta = self.meta_of(r)
            if back == "n":
                host, strip = (x0, y0, x1, y1 - t - 1), (x0, y1 - t + 1, x1, y1)
            elif back == "s":
                host, strip = (x0, y0 + t + 1, x1, y1), (x0, y0, x1, y0 + t - 1)
            elif back == "e":
                host, strip = (x0, y0, x1 - t - 1, y1), (x1 - t + 1, y0, x1, y1)
            else:
                host, strip = (x0 + t + 1, y0, x1, y1), (x0, y0, x0 + t - 1, y1)
            self.put(host, r.id, "room", meta)
            # guests along the strip, split by length in proportion to area
            sx0, sy0, sx1, sy1 = strip
            along_x = back in ("n", "s")
            a0, a1 = (sx0, sx1) if along_x else (sy0, sy1)
            pos = a0
            for g, s in zip(guests, shares):
                end = pos + s - 1
                gr = (pos, sy0, end, sy1) if along_x else (sx0, pos, sx1, end)
                self.put(gr, g.id, "room", self.meta_of(g))
                pos = end + 2
            return True
        return False

    @staticmethod
    def split_strip(length, guests):
        """Widths of the guests along a strip of this length, a wall tile between each two, in proportion to area
        (largest remainders), each 3+; None when they don't fit."""
        usable = length - (len(guests) - 1)
        ga = float(sum(g.area for g in guests))
        raw = [usable * g.area / ga for g in guests]
        out = [max(3, int(x)) for x in raw]
        left = usable - sum(out)
        for i in sorted(range(len(guests)), key=lambda i: int(raw[i]) - raw[i]):
            if left <= 0:
                break
            out[i] += 1
            left -= 1
        while left < 0:
            i = max(range(len(out)), key=lambda i: out[i] - raw[i])
            if out[i] <= 3:
                return None
            out[i] -= 1
            left += 1
        return out

    def meta_of(self, r):
        return dict(kind="room", public=r.public, secure=r.secure, front=r.front, label=r.label,
                    links=tuple(r.links), maint=r.maint, dock=r.dock, lobby=r is self.d.lobby)

    def notch(self):
        """Human rooms interlock: some rooms lose a corner, either to open space (it goes to maint) or to the room
        next door (that room gets an L). Each room keeps 3 tiles each way, and nothing changes within 2 tiles of a hall
        so every door still has its wall."""
        rnd = self.rnd
        rects = {}
        metas = {}
        order = []
        for rect, rid, meta in self.rooms:
            if rid not in rects:
                order.append(rid)
                rects[rid] = []
                metas[rid] = meta
            rects[rid].append(rect)
        own, kind = self.own, self.kind
        touched = set()

        def near_hall(pts):
            for t in pts:
                for dx in (-2, -1, 0, 1, 2):
                    for dy in (-2, -1, 0, 1, 2):
                        r = own.get((t[0] + dx, t[1] + dy))
                        if r is not None and kind.get(r) == "hall":
                            return True
            return False

        def bb(pts):
            xs, ys = [t[0] for t in pts], [t[1] for t in pts]
            return (min(xs), min(ys), max(xs), max(ys))

        def walls(x):
            """Linked rooms x shares a wall with (a door's worth)."""
            ks = self.links.get(x, ())
            got = set()
            for t, r in own.items():
                if r != x:
                    continue
                for dx, dy in D4:
                    if own.get((t[0] + dx, t[1] + dy)) is None:
                        k = own.get((t[0] + 2 * dx, t[1] + 2 * dy))
                        if k in ks:
                            got.add(k)
            return got

        for rid in order:
            if rid in touched or len(rects[rid]) > 1 or rid in self.inner:
                continue
            x0, y0, x1, y1 = rects[rid][0]
            w, h = x1 - x0 + 1, y1 - y0 + 1
            # rooms on the hull (docks, labs that vent) keep their box
            if w * h < 20 or min(w, h) < 4 or "back" in (metas[rid].get("front") or ()) or rnd.random() >= 0.8:
                continue
            sides = [("E", lambda i, j: (x1 - i, j), w, y0, y1), ("W", lambda i, j: (x0 + i, j), w, y0, y1),
                     ("N", lambda i, j: (j, y1 - i), h, x0, x1), ("S", lambda i, j: (j, y0 + i), h, x0, x1)]
            rnd.shuffle(sides)
            for name, P, depth_len, a0, a1 in sides:
                along_len = a1 - a0 + 1
                if depth_len < 5 or along_len < 5:
                    continue
                nx = rnd.randint(2, min(4, depth_len - 3))
                ny = rnd.randint(min(2, along_len - 4), min(4, along_len - 4))
                if rnd.random() < 0.5:
                    js, extra = list(range(a0, a0 + ny)), a0 + ny
                else:
                    js, extra = list(range(a1 - ny + 1, a1 + 1)), a1 - ny
                cut = [P(i, j) for i in range(nx) for j in js + [extra]]
                if near_hall(cut):
                    continue
                keep = {x: walls(x) for x in {rid} | {own.get(P(-2, j)) for j in js} if x is not None}
                saved = dict(own)
                nbr = {own.get(P(-2, j)) for j in js}
                gap = all(own.get(P(-1, j)) is None for j in js)
                if not gap:
                    continue
                if nbr == {None}:
                    # open space beyond: the corner goes to maint (only the cut rows, no wall row needed)
                    if any(own.get(P(-k, j)) is not None for j in js for k in (2, 3)):
                        continue
                    for j in js:
                        for i in range(nx):
                            own.pop(P(i, j), None)
                    lost = [P(i, j) for i in range(nx) for j in js]
                    to = None
                elif len(nbr) == 1:
                    to = nbr.pop()
                    if to is None or to == rid or kind.get(to) != "room" or to in self.inner or to not in rects or                             "back" in (metas[to].get("front") or ()):
                        continue
                    for t in cut:
                        own.pop(t, None)
                    gain = [P(i, j) for i in range(-1, nx - 1) for j in js]
                    for t in gain:
                        own[t] = to
                    lost = cut
                else:
                    continue
                # a linked pair that lost its shared wall: put it all back
                if any(not keep[x] <= walls(x) for x in keep):
                    own.clear()
                    own.update(saved)
                    continue
                if to is not None:
                    rects[to].append(bb(gain))
                    touched.add(to)
                # what is left of this room: the full-length part past the cut's depth, and the rest of the cut's
                # depth along the side
                lost_set = set(lost)
                deep = [P(i, j) for i in range(nx, depth_len) for j in range(a0, a1 + 1)]
                shallow = [P(i, j) for i in range(nx) for j in range(a0, a1 + 1) if P(i, j) not in lost_set]
                rects[rid] = [bb(deep), bb(shallow)]
                touched.add(rid)
                break
        self.rooms = [(r, rid, metas[rid]) for rid in order for r in rects[rid]]

    def trim(self):
        """Cut hall ends that no room opens onto and no other hall joins."""
        own, kind = self.own, self.kind

        def useful(t, rid, rect):
            for dx, dy in D4:
                n = (t[0] + dx, t[1] + dy)
                q = own.get(n)
                inside = rect[0] <= n[0] <= rect[2] and rect[1] <= n[1] <= rect[3]
                if q is not None and kind[q] == "hall" and (q != rid or not inside):
                    return True
                if q is None:
                    b = own.get((t[0] + 2 * dx, t[1] + 2 * dy))
                    if b is not None and kind[b] == "room":
                        return True
            return False
        for h in reversed(self.halls):
            while True:
                x0, y0, x1, y1 = h["rect"]
                if h["axis"] == 1:
                    if y1 - y0 < 1 and h is self.halls[0]:
                        break
                    row = [(x, y1 if h["sgn"] > 0 else y0) for x in range(x0, x1 + 1)]
                else:
                    row = [(x1 if h["sgn"] > 0 else x0, y) for y in range(y0, y1 + 1)]
                if not row or any(useful(t, h["id"], h["rect"]) for t in row):
                    break
                # the spine keeps its mouth
                if h is self.halls[0] and (y1 - y0) <= 1:
                    break
                for t in row:
                    own.pop(t, None)
                if h["axis"] == 1:
                    h["rect"] = (x0, y0, x1, y1 - 1) if h["sgn"] > 0 else (x0, y0 + 1, x1, y1)
                else:
                    h["rect"] = (x0, y0, x1 - 1, y1) if h["sgn"] > 0 else (x0 + 1, y0, x1, y1)
                if (h["rect"][2] < h["rect"][0]) or (h["rect"][3] < h["rect"][1]):
                    break

    def local(self):
        L = Local(self.d, self.W)
        L.depth = self.Dm
        L.broken = self.broken
        for h in self.halls:
            r = h["rect"]
            if r[2] >= r[0] and r[3] >= r[1]:
                L.rects.append((r, h["id"], dict(kind="hall", public=self.d.public_spine)))
        L.spine = self.halls[0]["rect"]
        L.cross = list(range(self.ncross))
        L.rects += self.rooms
        L.tiles = set(self.own)
        return L


def _copy(r, rid, area, mn, label):
    from station.program import Rm
    return Rm(rid, area, r.tier, r.front, mn, (), 0, label, r.secure, r.public, r.maint, r.corridor, (), r.dock)


def grow_dept(d, W, Dm, seed, left_front=None, right_front=None):
    return Grower(d, W, Dm, seed, left_front, right_front).run().local()
