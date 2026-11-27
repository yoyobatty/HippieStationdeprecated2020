"""Room shapes as the stock maps have them: each room of a department plan draws a target shape class from the stock
mix for its type and size (gen/learn/variety.py: small rooms are rectangles 93% of the time, rooms of 48+ tiles are
complex shapes 70% of the time) and gets there by shifting stretches of its walls:

    transfer   a stretch of the wall it shares with a neighbour moves k tiles into it: it gets a step (at the wall's
               end) or a notch (mid wall), the neighbour a bump; one tile of wall closes each open end
    alcove     the same toward the corridor: the hall gains a nook
    release    on the block's outer side the room's edge steps in and the cells past it are given up (the plan's
               outline stops being a box; gen/learn/floorplan.py trims what no floor touches)

Never: a door or a door's front moved, a room cut in two or left with a 1-wide part, a room under its work size or
70% of what it had, a neighbour over its type's cap, a cell or pen (floorplan pieces) or a room under 12 tiles
touched as a neighbour.

The user 2026-11-26: "I notice you don't go creative with room size and shape ... Yes, do it then, fix it."
Before: rect 0.60, L 0.26, other 0.05 (stock rect 0.42-0.63, L 0.04-0.11, T 0.05-0.12, other 0.18-0.32).

    from gen.learn import reshape; reshape.reshape(P, r)      # floorplan.plan(), after jogs
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
N8 = N4 + ((1, 1), (1, -1), (-1, 1), (-1, -1))
RANK = {"rect": 0, "L": 1, "notch": 1, "T": 2, "Z": 2, "other": 3}
MIN_TILES = 12          # rooms under this stay as they are (stock 6-11: rect 0.93)
KEEP = 0.7              # a room keeps at least this share of its floor
HUB_KEEP = 0.88
TRIES = 60
LEAN = {"L": 0.5, "T": 1.5, "notch": 1.6, "other": 1.45}
L_ON = 0.5
ALCOVE_P = 0.7          # how often a corridor-side shift is taken when drawn
SIDES = {"N": ((0, 1), (1, 0)), "S": ((0, -1), (1, 0)), "E": ((1, 0), (0, 1)), "W": ((-1, 0), (0, 1))}


def _connected(cells):
    if not cells:
        return False
    s = next(iter(cells))
    seen, q = {s}, [s]
    while q:
        p = q.pop()
        for dx, dy in N4:
            n = (p[0] + dx, p[1] + dy)
            if n in cells and n not in seen:
                seen.add(n)
                q.append(n)
    return len(seen) == len(cells)


def _wide(cells):
    """No 1-wide part: every cell has a neighbour across and a neighbour along."""
    for (x, y) in cells:
        if ((x - 1, y) not in cells and (x + 1, y) not in cells) or ((x, y - 1) not in cells and (x, y + 1) not in cells):
            return False
    return True


def _thin(cells):
    """How many cells sit in a 1-wide part."""
    return sum(1 for (x, y) in cells if ((x - 1, y) not in cells and (x + 1, y) not in cells)
               or ((x, y - 1) not in cells and (x, y + 1) not in cells))


def _pick(mix, r):
    u, acc = r.random(), 0.0
    for k, v in mix.items():
        acc += v
        if u <= acc:
            return k
    return "rect"


def _runs(F, side):
    """The stretches of the room's floor along its bounding box's edge on `side`: [(fixed coordinate, a0, a1)] in the
    along coordinate (x for N/S, y for E/W)."""
    xs = [c[0] for c in F]
    ys = [c[1] for c in F]
    if side in ("N", "S"):
        fy = max(ys) if side == "N" else min(ys)
        al = sorted(c[0] for c in F if c[1] == fy)
    else:
        fx = max(xs) if side == "E" else min(xs)
        al = sorted(c[1] for c in F if c[0] == fx)
        fy = fx
    runs, a0 = [], None
    prev = None
    for a in al:
        if prev is None or a != prev + 1:
            if a0 is not None:
                runs.append((fy, a0, prev))
            a0 = a
        prev = a
    if a0 is not None:
        runs.append((fy, a0, prev))
    return runs


def _cell(side, fixed, a, depth):
    """The cell at along-coordinate a, `depth` rows in from the edge (0 = the edge row; -1 = the wall line past it;
    -2 = beyond the wall)."""
    (nx, ny), _ = SIDES[side]
    if side in ("N", "S"):
        return (a, fixed - ny * depth)
    return (fixed - nx * depth, a)


class _Ctx:
    def __init__(self, P):
        import floorplan as FP
        self.P = P
        self.FP = FP
        self.owner = {}
        for rm in P.rooms:
            for c in rm["F"]:
                self.owner[c] = rm
        self.doors = set(P.doors) | set(P.front)
        self.piece_types = set(FP.pieces())
        self.work = {}

    def wall(self, c):
        P = self.P
        return c in P.cells and c not in self.owner and c not in P.corr and c not in self.doors and c not in P.space

    def near_door(self, c):
        return c in self.doors or any((c[0] + dx, c[1] + dy) in self.doors for dx, dy in N4)

    def ok_room(self, rm):
        return not rm.get("piece") and rm["area"] not in self.piece_types and len(rm["F"]) >= MIN_TILES \
            and not rm["area"].startswith("/area/maintenance") and not rm.get("whole")

    def floor_min(self, rm, n0):
        w = self.work.get(rm["area"])
        if w is None:
            w = self.work[rm["area"]] = self.FP.work_size(rm["area"]) or 0
        # (a hub room keeps its floor: the cargo bay is the department's working hall, floorplan.HUB)
        return max(9, w, int((HUB_KEEP if rm.get("hub") else KEEP) * n0))


def _no_diagonal(C, to_wall, to_floor):
    """After these cells turn to wall / to floor, no 2x2 square round them has floor on one diagonal and wall on the
    other."""
    P = C.P

    def walk(c):
        if c in to_floor:
            return True
        if c in to_wall:
            return False
        return c in C.owner or c in P.corr or c in C.doors
    for c in to_wall | to_floor:
        for ox, oy in ((0, 0), (-1, 0), (0, 1), (-1, 1)):
            a = (c[0] + ox, c[1] + oy)
            w = [walk(q) for q in (a, (a[0] + 1, a[1]), (a[0], a[1] - 1), (a[0] + 1, a[1] - 1))]
            if (w[0] and w[3] and not w[1] and not w[2]) or (w[1] and w[2] and not w[0] and not w[3]):
                return False
    return True


def _try(C, rm, r, side, where, n0):
    """One wall shift on `side` of the room: where = "lo" / "hi" (an end of the edge run: a step) or "mid" (a notch).
    Returns True when applied."""
    P, F = C.P, rm["F"]
    runs = _runs(F, side)
    if not runs:
        return False
    fixed, a0, a1 = max(runs, key=lambda t: t[2] - t[1])
    run = a1 - a0 + 1
    xs = [c[0] for c in F]
    ys = [c[1] for c in F]
    perp = (max(ys) - min(ys) + 1) if side in ("N", "S") else (max(xs) - min(xs) + 1)
    if run < 4 or perp < 3:
        return False
    k = min(r.choice((1, 1, 1, 2, 2, 3)), perp - 2)
    if k < 1:
        return False
    (nx, ny), _ = SIDES[side]
    front = (nx, ny) == (0, -1) and fixed <= 1          # the front wall faces the hall: no pocket there

    def key(a):
        """Who takes the cells at along-coordinate a: ("room", id), ("corr",), ("out",) or None (no shift there)."""
        sc = _cell(side, fixed, a, -1)
        if C.near_door(sc) or not (C.wall(sc) or sc not in P.cells) or any(
                C.near_door(_cell(side, fixed, a, d)) or _cell(side, fixed, a, d) not in F for d in range(k)):
            return None
        b = _cell(side, fixed, a, -2)
        if b in C.owner:
            B = C.owner[b]
            return ("room", id(B)) if (B is not rm and C.ok_room(B) and C.wall(sc)) else None
        if b in P.corr:
            return ("corr",) if (C.wall(sc) and k <= 2) else None
        far = _cell(side, fixed, a, -3)
        if P.dept != "engineering" and not front and all((c not in P.cells or C.wall(c)) and c not in P.space
                                                         for c in (sc, b, far)):
            return ("out",)                 # engineering's back wall carries the engine: its block stays a box
        return None
    spans, s0, prev, pk = [], None, None, None
    for a in range(a0, a1 + 1):
        ka = key(a)
        if ka is None or ka != pk or prev is None or a != prev + 1:
            if s0 is not None and pk is not None:
                spans.append((s0, prev, pk))
            s0 = a if ka is not None else None
        pk = ka
        prev = a
    if s0 is not None and pk is not None:
        spans.append((s0, prev, pk))
    # a bump into a room or the hall wants 2 tiles of width after its closing walls
    need = lambda kind, ends: 2 if kind == "out" else 2 + ends  # noqa: E731
    if where == "mid":
        cands = [(max(f0, a0 + 2), min(f1, a1 - 2), kk) for f0, f1, kk in spans]
        cands = [c for c in cands if c[1] - c[0] + 1 >= need(c[2][0], 2)]
        if not cands:
            return False
        f0, f1, kk = r.choice(cands)
        ln = r.randint(need(kk[0], 2), max(need(kk[0], 2), min(f1 - f0 + 1, 2 + run // 3)))
        b0 = r.randint(f0, f1 - ln + 1)
        b1 = b0 + ln - 1
    else:
        cands = [sp for sp in spans if (sp[0] == a0 if where == "lo" else sp[1] == a1)]
        if not cands:
            return False
        f0, f1, kk = cands[0]
        top = min(f1 - f0 + 1, run - 2, max(need(kk[0], 1), run // 2))
        if top < need(kk[0], 1):
            return False
        ln = r.randint(need(kk[0], 1), top)
        b0, b1 = (a0, a0 + ln - 1) if where == "lo" else (a1 - ln + 1, a1)
    if kk[0] == "corr" and r.random() > ALCOVE_P:
        return False
    T = {_cell(side, fixed, a, d) for a in range(b0, b1 + 1) for d in range(k)}
    A2 = F - T
    if len(A2) < C.floor_min(rm, n0) or not _connected(A2) or not _wide(A2):
        return False
    # the ends where the room goes on beside the stretch need a tile of wall to close the bump
    close = set()
    if _cell(side, fixed, b0 - 1, 0) in A2:
        close.add(b0)
    if _cell(side, fixed, b1 + 1, 0) in A2:
        close.add(b1)
    cols = [a for a in range(b0, b1 + 1) if a not in close]
    gain = {_cell(side, fixed, a, -1) for a in cols} | {_cell(side, fixed, a, d) for a in cols for d in range(k - 1)}
    if kk[0] == "out":
        gain = set()
    if not _no_diagonal(C, T - gain, gain - T):
        return False                # two walls would meet only at a corner (the user: "this awkward diagonal")
    if kk[0] == "room":
        B = C.owner[_cell(side, fixed, b0, -2)]
        cap = C.FP._cap(B["area"])
        if len(cols) < 2 or (cap and len(B["F"]) + len(gain) > cap) or not _wide(B["F"] | gain):
            return False
        rm["F"] = A2
        B["F"] |= gain
        for c in T:
            C.owner.pop(c, None)
        for c in gain:
            C.owner[c] = B
        P.floor -= T
        P.floor |= gain
        return True
    if kk[0] == "corr":
        if len(cols) < 2:
            return False
        rm["F"] = A2
        for c in T:
            C.owner.pop(c, None)
        P.floor -= T
        P.corr |= gain
        return True
    rm["F"] = A2
    for c in T:
        C.owner.pop(c, None)
    P.floor -= T
    return True


def reshape(P, r):
    """Shape the plan's rooms to the stock mix; returns the number of wall shifts made."""
    import variety as VR
    C = _Ctx(P)
    made = 0
    order = sorted((rm for rm in P.rooms if C.ok_room(rm)), key=lambda rm: (-len(rm["F"]), rm["id"]))
    for rm in order:
        n0 = len(rm["F"])
        # the stock mix, leaned away from the plain L (the planner's back rows and corner closets make L's of
        # their own: 0.18 of rooms before this pass against the stock 0.04-0.13) toward the classes it never makes
        mix = VR.shape_mix(rm["area"], n0)
        mix = dict(mix, L=mix["L"] * LEAN["L"], T=mix["T"] * LEAN["T"], notch=mix["notch"] * LEAN["notch"],
                   other=mix["other"] * LEAN["other"], Z=mix["Z"])
        tot_ = sum(v for k_, v in mix.items() if k_ != "rect")
        if tot_ > 0.92:
            mix = {k_: (v * 0.92 / tot_ if k_ != "rect" else v) for k_, v in mix.items()}
            tot_ = 0.92
        mix["rect"] = 1.0 - tot_
        target = _pick(mix, r)
        cur = VR.shape(rm["F"])
        if cur == "L" and target in ("rect", "L") and r.random() < L_ON:
            target = "other" if r.random() < 0.6 else "T"      # an L goes on to a fuller shape half the time
        if RANK[target] <= RANK[cur]:
            continue
        sides = list("NSEW")
        r.shuffle(sides)
        if target == "L":
            plan = [(sides[0], r.choice(("lo", "hi")))]
        elif target == "notch":
            plan = [(sides[0], "mid")]
        elif target == "T":
            plan = [(sides[0], "lo"), (sides[0], "hi")]
        elif target == "Z":
            a, b = ("N", "S") if sides[0] in "NS" else ("E", "W")
            lo = r.choice(("lo", "hi"))
            plan = [(a, lo), (b, "hi" if lo == "lo" else "lo")]
        else:
            plan = None
        tries = 0
        if plan is not None:
            # the planned shifts, each tried on its side, then on the others
            for side, where in plan:
                done = False
                for s2 in [side] + [s for s in sides if s != side]:
                    for _ in range(6):
                        tries += 1
                        if _try(C, rm, r, s2, where, n0):
                            made += 1
                            done = True
                            break
                    if done or target in ("T", "Z"):
                        break
        else:
            # a complex outline: shifts on different sides until the shape is past the simple classes
            while tries < TRIES and VR.shape(rm["F"]) != "other":
                tries += 1
                if _try(C, rm, r, r.choice(sides), r.choice(("lo", "hi", "mid", "mid")), n0):
                    made += 1
    return made


def trim(P):
    """The block keeps only the cells its floor touches: floor, corridor, doors and one ring of wall round them
    (what a release gave up, a strip no room reached). No solid blocks of wall left inside or behind the rooms."""
    keep = set(P.floor) | set(P.corr) | set(P.doors) | set(P.front)
    ring = {(c[0] + dx, c[1] + dy) for c in keep for dx, dy in N8}
    P.cells = (P.cells & (keep | ring)) | (keep & P.cells) | set(P.space)


def separate(P):
    """A wall between every two rooms, and between a room and the corridor: where the planner's steps together left
    floor of two rooms side by side (a jog's moved wall past a corner closet a later cut made: 2 in 168 plans,
    gen/learn/plancheck.py "rooms touch"), the cell of the bigger room turns to wall when its room stays whole, else
    the other's. Returns how many cells turned."""
    n = 0
    doors = set(P.doors) | set(P.front)
    for _ in range(60):
        owner = {c: rm for rm in P.rooms for c in rm["F"]}
        pair = None
        for c, rm in owner.items():
            for dx, dy in N4:
                q = (c[0] + dx, c[1] + dy)
                if q in P.corr or (q in owner and owner[q] is not rm):
                    pair = (c, q)
                    break
            if pair:
                break
        if pair is None:
            return n
        cands = sorted((q for q in pair if q in owner), key=lambda q: (bool(owner[q].get("whole")), -len(owner[q]["F"])))
        for c in cands:
            rm = owner[c]
            F2 = rm["F"] - {c}
            if len(F2) >= 4 and _connected(F2) and not any((c[0] + dx, c[1] + dy) in doors for dx, dy in N4):
                rm["F"] = F2
                P.floor.discard(c)
                n += 1
                break
        else:
            return n
    return n


def fix_diagonals(P):
    """Two walls meeting only at a corner (floor on the other diagonal of a 2x2 square) closed in the plan, before
    anything is furnished: one of the two floor cells becomes wall when it is a room's cell, no door beside it, and
    its room stays whole, 2 wide and 6+ cells. The planner's back rows, jogs and corner closets left 20-30 such
    squares in 66 plans. Returns how many are left."""
    owner = {}
    for rm in P.rooms:
        for c in rm["F"]:
            owner[c] = rm
    doors = set(P.doors) | set(P.front)

    def walk(c):
        return c in owner or c in P.corr or c in doors

    def squares():
        out = []
        for c in list(owner) + list(P.corr):
            for ox, oy in ((0, 0), (-1, 0), (0, 1), (-1, 1)):
                a = (c[0] + ox, c[1] + oy)
                sq = (a, (a[0] + 1, a[1]), (a[0], a[1] - 1), (a[0] + 1, a[1] - 1))
                w = [walk(q) for q in sq]
                if w[0] and w[3] and not w[1] and not w[2]:
                    out.append((sq[0], sq[3]))
                elif w[1] and w[2] and not w[0] and not w[3]:
                    out.append((sq[1], sq[2]))
        return out
    for _ in range(40):
        sqs = squares()
        if not sqs:
            return 0
        done = False
        for pair in sqs:
            for c in pair:
                rm = owner.get(c)
                if rm is None or rm.get("piece") or rm.get("whole") \
                        or any((c[0] + dx, c[1] + dy) in doors for dx, dy in N4):
                    continue
                # the cell goes, with the 1-wide stub it would leave (a 2-cell alcove whose one cell closed the
                # square left the other a nook); no more 1-wide floor than the room had (a room with a nook already
                # was refused every cell, so its squares stayed: 20 in 84 plans, 2026-11-26)
                F2 = rm["F"] - {c}
                for _k in range(3):
                    stub = {q for q in F2 if ((q[0] - 1, q[1]) not in F2 and (q[0] + 1, q[1]) not in F2)
                            or ((q[0], q[1] - 1) not in F2 and (q[0], q[1] + 1) not in F2)}
                    stub = {q for q in stub if abs(q[0] - c[0]) + abs(q[1] - c[1]) <= 2
                            and not any((q[0] + dx, q[1] + dy) in doors for dx, dy in N4)}
                    if not stub or _thin(F2) <= _thin(rm["F"]):
                        break
                    F2 = F2 - stub
                if len(F2) < 6 or len(F2) < 0.8 * len(rm["F"]) or not _connected(F2) or _thin(F2) > _thin(rm["F"]):
                    continue
                for q in rm["F"] - F2:
                    owner.pop(q)
                    P.floor.discard(q)
                rm["F"] = F2
                done = True
                break
            if done:
                break
            # else one of the two wall cells joins the room beside it, when nothing else walkable touches it (no
            # second room, corridor or door opened) and it lies inside the block
            a, b = pair
            for c in ((a[0], b[1]), (b[0], a[1])):
                if c not in P.cells or c in P.space or walk(c):
                    continue
                nb = [(c[0] + dx, c[1] + dy) for dx, dy in N4]
                rooms_ = {id(owner[q]): owner[q] for q in nb if q in owner}
                if len(rooms_) != 1 or any(q in P.corr or q in doors for q in nb):
                    continue
                rm = next(iter(rooms_.values()))
                if rm.get("piece") or any((c[0] + dx, c[1] + dy) in doors for dx, dy in N8):
                    continue
                # the block keeps a wall past it
                if any((c[0] + dx, c[1] + dy) not in P.cells for dx, dy in N8):
                    continue
                rm["F"] = rm["F"] | {c}
                owner[c] = rm
                P.floor.add(c)
                done = True
                break
            if done:
                break
        if not done:
            return len(set(sqs))
    return len(set(squares()))
