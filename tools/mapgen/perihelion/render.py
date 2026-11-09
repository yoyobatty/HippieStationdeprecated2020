"""Draw the Perihelion block plan to a PNG and sanity-check it.

    python tools/mapgen/perihelion/render.py [out.png]

Checks: overlaps between rooms, halls, walkways and tunnels; outside things
(solars, docks, pods, rocks) hitting each other or a hull; anything too near
the z-level edge; rooms with no door; secure rooms with an ordinary door.
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import layout as L  # noqa: E402

S = 5  # pixels per tile
OX, OY = L.OFFSET

C_SPACE = (12, 14, 26)
C_HULL = (88, 92, 104)
C_RWALL = (120, 70, 70)
C_MAINT = (58, 52, 46)
C_HALL = (196, 198, 204)
C_GLASS = (205, 225, 238)
C_GLASS_EDGE = (120, 190, 230)
C_TUNNEL = (150, 150, 160)
C_DOOR = (250, 210, 60)
C_SDOOR = (240, 90, 60)
C_ACCESS = (80, 150, 255)
C_DESK = (225, 225, 230)
C_BLAST = (230, 60, 50)
C_DOCK = (200, 200, 120)
C_EXT = (90, 230, 230)


def px(x, y):
    return ((x + OX) * S, (y + OY) * S)


def box(r, grow=0):
    x0, y0, x1, y1 = r
    a = px(x0 - grow, y0 - grow)
    b = px(x1 + grow, y1 + grow)
    return [a[0], a[1], b[0] - 1, b[1] - 1]


def grow(r, g):
    return (r[0] - g, r[1] - g, r[2] + g, r[3] + g)


def overlap(a, b):
    return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


def shared_edge(a, b):
    """(orientation, fixed, lo, hi) of the edge a and b share, or None."""
    ax0, ay0, ax1, ay1 = a
    bx0, by0, bx1, by1 = b
    for fixed, cond in ((ax1, ax1 == bx0), (ax0, ax0 == bx1)):
        if cond:
            lo, hi = max(ay0, by0), min(ay1, by1)
            if hi - lo >= 1:
                return ("v", fixed, lo, hi)
    for fixed, cond in ((ay1, ay1 == by0), (ay0, ay0 == by1)):
        if cond:
            lo, hi = max(ax0, bx0), min(ax1, bx1)
            if hi - lo >= 1:
                return ("h", fixed, lo, hi)
    return None


def font(size):
    for f in ("C:/Windows/Fonts/segoeui.ttf", "C:/Windows/Fonts/arial.ttf"):
        if os.path.exists(f):
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


def check(problems):
    rooms = L.ROOMS
    inner = [("room " + r[0], r[2]) for r in rooms]
    inner += [("hall " + h[0], h[2]) for h in L.HALLS]
    inner += [("walkway " + w[0], w[1]) for w in L.WALKWAYS]
    inner += [("tunnel " + m[0], m[1]) for m in L.MAINT]
    for i in range(len(inner)):
        for j in range(i + 1, len(inner)):
            a, b = inner[i], inner[j]
            if a[0].startswith("tunnel") and b[0].startswith("tunnel"):
                continue  # tunnels join each other on purpose
            if overlap(a[1], b[1]):
                problems.append("overlap: %s / %s" % (a[0], b[0]))
    # outside things: footprint incl. their hull/clearance
    outside = [("dock " + d[0], d[1]) for d in L.DOCKS]
    outside += [("solars " + s[0], grow(s[1], 1)) for s in L.SOLARS]
    outside += [(r[0], grow(r[1], 1)) for r in L.RADIATORS]
    outside += [("rock", (x - r, y - r, x + r + 1, y + r + 1)) for x, y, r in L.ASTEROIDS]
    outside += [(d[0], d[1]) for d in L.DERELICTS]
    hulls = [("module " + m[0], (m[2][0] - 2, m[2][1] - 2, m[2][2] + 3, m[2][3] + 3)) for m in L.MODULES]
    pods = [("pod " + r[0], (r[2][0], r[2][1], r[2][2] + 1, r[2][3] + 1)) for r in rooms if "pod" in r[3]]
    tun = [("tunnel " + m[0], grow(m[1], 1)) for m in L.MAINT]
    for i in range(len(outside)):
        for j in range(i + 1, len(outside)):
            if overlap(outside[i][1], outside[j][1]):
                problems.append("overlap: %s / %s" % (outside[i][0], outside[j][0]))
        for name, r in hulls + pods + tun:
            if overlap(outside[i][1], r):
                problems.append("overlap: %s / %s" % (outside[i][0], name))
    every = inner + outside + hulls + pods
    for name, r in every:
        x0, y0, x1, y1 = r
        if x0 + OX < L.EDGE or y0 + OY < L.EDGE or x1 + OX > L.WORLD - L.EDGE or y1 + OY > L.WORLD - L.EDGE:
            problems.append("too near the edge: " + name)


def compute(problems, verbose=True):
    """Work out every door from the plan and walk it. Returns (doors, public set).

    Each door is (o, fixed, mid, kind, a, b): orientation of the shared line
    ("v" = vertical line x=fixed, "h" = horizontal line y=fixed), the middle
    of the shared span, the door kind and the two things it joins. Kind
    "open" is a plain opening (no door).
    """
    named = {r[0]: r[2] for r in L.ROOMS}
    named.update({w[0]: w[1] for w in L.WALKWAYS})
    named.update({h[0]: h[2] for h in L.HALLS})
    flags_of = {r[0]: r[3] for r in L.ROOMS}
    public_passages = [(h[0], h[2]) for h in L.HALLS if h[1] == "public"]
    public_passages += [(w[0], w[1]) for w in L.WALKWAYS]
    dept_halls = [(h[0], h[1], h[2]) for h in L.HALLS if h[1] != "public"]
    tunnels = [(m[0], m[1]) for m in L.MAINT]

    doors = []  # (o, fixed, mid, kind) for drawing
    edges = []  # (a, b, kind) for the walk
    has_door = set()

    def add_door(a, b, e, kind):
        doors.append((e[0], e[1], (e[2] + e[3]) // 2, kind, a, b))
        edges.append((a, b, kind))
        has_door.update((a, b))

    for name, dept, r, flags in L.ROOMS:
        if "noauto" in flags:
            continue
        if "public" in flags or "locked" in flags:
            cands = public_passages
        elif "pod" in flags and dept in ("mnt", "eng"):
            cands = tunnels  # maint rooms and solar controls
        else:
            cands = [(n, rr) for n, o, rr in dept_halls if o == dept]
        best = None
        for n, p in cands:
            e = shared_edge(r, p)
            if e and (best is None or e[3] - e[2] > best[1][3] - best[1][2]):
                best = (n, e)
        if best:
            add_door(name, best[0], best[1], "locked" if "locked" in flags else "")
            if "secure" in flags:
                problems.append("secure room with an ordinary hall door: " + name)
    # halls with the same owner join openly; walkways join public halls
    open_parts = [(h[0], h[1], h[2]) for h in L.HALLS] + [(w[0], "public", w[1]) for w in L.WALKWAYS]
    for i in range(len(open_parts)):
        for j in range(i + 1, len(open_parts)):
            a, b = open_parts[i], open_parts[j]
            if a[1] == b[1] and shared_edge(a[2], b[2]):
                edges.append((a[0], b[0], "open"))
    for a, b in L.GATES:
        e = shared_edge(named[a], named[b])
        if e:
            add_door(a, b, e, "access")
        else:
            problems.append("gate not adjacent: %s / %s" % (a, b))
    for a, b, kind in L.MANUAL_DOORS:
        e = shared_edge(named[a], named[b])
        if e:
            add_door(a, b, e, kind)
        else:
            problems.append("manual door not adjacent: %s / %s" % (a, b))

    # walk the plan: as the public (ordinary doors only), then with all access
    def walk(kinds):
        seen, todo = {"Arrivals"}, ["Arrivals"]
        while todo:
            n = todo.pop()
            for a, b, k in edges:
                if k in kinds:
                    for x, y in ((a, b), (b, a)):
                        if x == n and y not in seen:
                            seen.add(y)
                            todo.append(y)
        return seen
    pub = walk(("", "open"))
    for n in sorted(pub):
        if n in flags_of and "public" not in flags_of[n]:
            problems.append("public can walk into: " + n)
        if any(h[0] == n and h[1] != "public" for h in L.HALLS):
            problems.append("public can walk into department hall: " + n)
    full = walk(("", "open", "access", "locked", "secure"))
    for name, dept, r, flags in L.ROOMS:
        on_tunnel = "pod" in flags and dept in ("mnt", "eng")
        if name not in full and not on_tunnel:
            problems.append("can't be reached from Arrivals: " + name)
    pub_rooms = sorted(n for n in pub if n in flags_of)
    if verbose:
        print("public reaches %d rooms: %s" % (len(pub_rooms), ", ".join(pub_rooms)))
    for name, dept, r, flags in L.ROOMS:
        if name not in has_door:
            problems.append("no door: " + name)
        if "secure" in flags:
            for wname, wr, kind in L.WALKWAYS:
                if kind == "glass" and shared_edge(r, wr):
                    problems.append("secure room on a glass walkway: " + name)
            for mname, mr in L.MAINT:
                if overlap(grow(r, 1), mr):
                    problems.append("secure room next to maint tunnel %s: %s" % (mname, name))
    return doors, pub


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "data/previews/perihelion_plan.png"
    problems = []
    check(problems)
    doors, pub = compute(problems)

    # --- draw
    W = L.WORLD * S
    img = Image.new("RGB", (W, W + 80), C_SPACE)
    d = ImageDraw.Draw(img)
    rnd = random.Random(4)
    for _ in range(600):
        d.point((rnd.randrange(W), rnd.randrange(W)), fill=(70, 72, 95))
    # z-level edge margin
    e0, e1 = L.EDGE * S, (L.WORLD - L.EDGE) * S
    d.rectangle([e0, e0, e1, e1], outline=(34, 36, 52))

    # asteroids: lumpy polygons
    for x, y, r in L.ASTEROIDS:
        cx, cy = px(x + 0.5, y + 0.5)
        pts = []
        for k in range(14):
            a = k / 14 * 2 * math.pi
            rr = (r + rnd.uniform(-1.6, 0.6)) * S
            pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
        d.polygon(pts, fill=(92, 76, 62), outline=(120, 100, 82))
        for _ in range(r * 2):
            a, rr = rnd.uniform(0, 6.3), rnd.uniform(0, r - 2) * S
            d.ellipse([cx + math.cos(a) * rr - 3, cy + math.sin(a) * rr - 3,
                       cx + math.cos(a) * rr + 3, cy + math.sin(a) * rr + 3], fill=(74, 62, 52))
    # derelict: a broken hull with missing chunks and scattered lattice
    for name, r in L.DERELICTS:
        d.rectangle(box(r), fill=(70, 72, 80))
        d.rectangle(box(grow(r, -1)), fill=(46, 44, 42))
        for _ in range(9):
            hx = rnd.randrange(r[0], r[2] - 2)
            hy = rnd.randrange(r[1], r[3] - 2)
            d.rectangle(box((hx, hy, hx + rnd.randint(2, 4), hy + rnd.randint(2, 3))), fill=C_SPACE)
        for _ in range(14):
            lx = rnd.randrange(r[0] - 6, r[2] + 6)
            ly = rnd.randrange(r[1] - 4, r[3] + 4)
            if not overlap((lx, ly, lx + 1, ly + 1), r):
                b = box((lx, ly, lx + 1, ly + 1))
                d.line([b[0], b[1], b[2], b[3]], fill=(90, 92, 100))
                d.line([b[0], b[3], b[2], b[1]], fill=(90, 92, 100))
    # solar arrays: catwalk frame, panel rows with a catwalk every third row
    for name, r in L.SOLARS:
        d.rectangle(box(r), outline=(90, 92, 100))
        x0, y0, x1, y1 = r
        horiz = (x1 - x0) >= (y1 - y0)
        for ty in range(y0, y1):
            for tx in range(x0, x1):
                lane = (ty - y0) % 3 == 1 if horiz else (tx - x0) % 3 == 1
                b = box((tx, ty, tx + 1, ty + 1))
                if lane:
                    d.rectangle(b, fill=(66, 68, 76))
                else:
                    d.rectangle([b[0] + 1, b[1] + 1, b[2] - 1, b[3] - 1], fill=(40, 70, 150))
    for r in L.CATWALKS:
        for ty in range(r[1], r[3]):
            for tx in range(r[0], r[2]):
                b = box((tx, ty, tx + 1, ty + 1))
                d.rectangle(b, fill=(66, 68, 76), outline=(96, 98, 108))
    for name, r in L.RADIATORS:
        x0, y0, x1, y1 = r
        d.rectangle(box(r), outline=(90, 92, 100))
        for tx in range(x0, x1, 2):
            a = px(tx + 0.5, y0)
            b = px(tx + 0.5, y1)
            d.line([a, b], fill=(200, 110, 60), width=2)

    # hulls and maint
    for name, dept, r in L.MODULES:
        d.rectangle(box(r, 2), fill=C_HULL)
    for name, r in L.MAINT:
        d.rectangle(box(r, 1), fill=C_HULL)
    for name, dept, r, flags in L.ROOMS:
        if "pod" in flags:
            d.rectangle(box(r, 1), fill=C_HULL)
    for name, dept, r in L.MODULES:
        d.rectangle(box(r, 1), fill=C_MAINT)
    for name, r in L.MAINT:
        d.rectangle(box(r), fill=C_MAINT)
    # secure rooms wall off the maint ring around them
    for name, dept, r, flags in L.ROOMS:
        if "secure" in flags:
            d.rectangle(box(r, 1), fill=C_RWALL)
    # walkway shells
    for name, r, kind in L.WALKWAYS:
        x0, y0, x1, y1 = r
        shell = (x0, y0 - 1, x1, y1 + 1) if x1 - x0 > y1 - y0 else (x0 - 1, y0, x1 + 1, y1)
        d.rectangle(box(shell), fill=C_GLASS_EDGE if kind == "glass" else C_RWALL)
    # docks (dashed)
    for name, r in L.DOCKS:
        b = box(r)
        for k in range(b[0], b[2], 8):
            d.line([(k, b[1]), (min(k + 4, b[2]), b[1])], fill=C_DOCK)
            d.line([(k, b[3]), (min(k + 4, b[2]), b[3])], fill=C_DOCK)
        for k in range(b[1], b[3], 8):
            d.line([(b[0], k), (b[0], min(k + 4, b[3]))], fill=C_DOCK)
            d.line([(b[2], k), (b[2], min(k + 4, b[3]))], fill=C_DOCK)
    for name, own, r in L.HALLS:
        if own == "public":
            fill = C_HALL
        else:
            c = L.DEPTS[own]
            fill = tuple(int(c[k] * 0.45 + C_HALL[k] * 0.55) for k in range(3))
        d.rectangle(box(r), fill=fill)
    for name, r, kind in L.WALKWAYS:
        d.rectangle(box(r), fill=C_GLASS if kind == "glass" else C_TUNNEL)
    # a wall wherever a department hall meets public space
    parts = [(h[1], h[2]) for h in L.HALLS] + [("public", w[1]) for w in L.WALKWAYS]
    for i in range(len(parts)):
        for j in range(i + 1, len(parts)):
            if parts[i][0] != parts[j][0]:
                e = shared_edge(parts[i][1], parts[j][1])
                if e:
                    o, fixed, lo, hi = e
                    a, b = (px(fixed, lo), px(fixed, hi)) if o == "v" else (px(lo, fixed), px(hi, fixed))
                    d.line([a, b], fill=(28, 28, 34), width=3)
    # rooms
    for name, dept, r, flags in L.ROOMS:
        c = L.DEPTS[dept]
        fill = tuple(int(v * 0.55 + 255 * 0.12) for v in c)
        outline, width = (28, 28, 34), 2
        if "secure" in flags:
            outline, width = C_RWALL, 3
        d.rectangle(box(r), fill=fill, outline=outline, width=width)
        if "turrets" in flags:
            b = box(r)
            for cx, cy in ((b[0] + 6, b[1] + 6), (b[2] - 6, b[1] + 6), (b[0] + 6, b[3] - 6), (b[2] - 6, b[3] - 6)):
                d.ellipse([cx - 3, cy - 3, cx + 3, cy + 3], fill=(220, 60, 60), outline=(40, 10, 10))
        if "post" in flags:
            b = box(r)
            x, y = b[2] - 9, b[1] + 3
            d.polygon([(x - 6, y), (x + 6, y), (x + 6, y + 7), (x, y + 12), (x - 6, y + 7)],
                      fill=L.DEPTS["sec"], outline=(250, 220, 120))
    if hasattr(L, "XENO_RECT"):
        xr = L.XENO_RECT
        d.rectangle(box(xr), fill=tuple(int(v * 0.55 + 255 * 0.12) for v in L.DEPTS["sci"]), outline=(28, 28, 34), width=2)
        b = box(xr)
        d.text(((b[0] + b[2]) / 2, (b[1] + b[3]) / 2), "Xenobiology\n(Hippie's lab)", font=font(11),
               fill=(240, 240, 240), anchor="mm", align="center")
    if hasattr(L, "ENGINE_RECT"):
        er = L.ENGINE_RECT
        d.rectangle(box(er), fill=(70, 52, 30), outline=(214, 150, 40), width=3)
        b = box(er)
        d.text(((b[0] + b[2]) / 2, (b[1] + b[3]) / 2), L.ENGINES[L.ENGINE]["label"], font=font(13),
               fill=(250, 210, 120), anchor="mm", align="center")
    # blast doors at walkway ends
    for name, r, kind in L.WALKWAYS:
        x0, y0, x1, y1 = r
        if x1 - x0 > y1 - y0:
            ends = [((x0, y0), (x0, y1)), ((x1, y0), (x1, y1))]
        else:
            ends = [((x0, y0), (x1, y0)), ((x0, y1), (x1, y1))]
        for a, b in ends:
            d.line([px(*a), px(*b)], fill=C_BLAST, width=4)
    # doors
    for o, fixed, mid, kind, _a, _b in doors:
        if kind == "open":
            continue
        c = {"secure": C_SDOOR, "access": C_ACCESS, "locked": C_ACCESS, "desk": C_DESK}.get(kind, C_DOOR)
        ln = 8 if kind == "desk" else 5
        if o == "v":
            x, y = px(fixed, mid)
            d.rectangle([x - 2, y - ln, x + 2, y + ln], fill=c, outline=(20, 20, 30) if kind else None)
        else:
            x, y = px(mid, fixed)
            d.rectangle([x - ln, y - 2, x + ln, y + 2], fill=c, outline=(20, 20, 30) if kind else None)
    for x, y in L.EXT_AIRLOCKS:
        d.rectangle(box((x, y, x + 1, y + 1)), fill=C_EXT)

    # labels
    f_room, f_small, f_mod = font(11), font(8), font(17)
    for name, dept, r, flags in L.ROOMS:
        b = box(r)
        cx, cy = (b[0] + b[2]) / 2, (b[1] + b[3]) / 2
        words = name.split(" ")
        maxw = b[2] - b[0] - 6
        fr = f_room
        if max(d.textlength(w, font=f_room) for w in words) > maxw:
            fr = f_small
        lines, cur = [], ""
        for w in words:
            t = (cur + " " + w).strip()
            if d.textlength(t, font=fr) <= maxw or not cur:
                cur = t
            else:
                lines.append(cur)
                cur = w
        lines.append(cur)
        lh = 12 if fr is f_room else 9
        y = cy - lh * len(lines) / 2
        for ln in lines:
            d.text((cx, y + lh / 2), ln, font=fr, fill=(240, 240, 240), anchor="mm")
            y += lh
    for name, dept, r in L.MODULES:
        b = box(r, 2)
        d.text((b[0] + 2, b[1] - 4), name.upper(), font=f_mod, fill=L.DEPTS[dept], anchor="ls")
    sat = [r[2] for r in L.ROOMS if r[1] == "ai"]
    sx0 = min(r[0] for r in sat)
    sy0 = min(r[1] for r in sat)
    b = box((sx0, sy0, sx0 + 1, sy0 + 1), 1)
    d.text((b[0] + 2, b[1] - 4), "AI SATELLITE", font=f_mod, fill=L.DEPTS["ai"], anchor="ls")
    for name, r in L.DOCKS:
        b = box(r)
        d.text(((b[0] + b[2]) / 2, (b[1] + b[3]) / 2), name.replace(" shuttle", "\nshuttle"),
               font=f_room, fill=C_DOCK, anchor="mm", align="center")
    for name, r in L.SOLARS:
        b = box(r)
        d.text(((b[0] + b[2]) / 2, (b[1] + b[3]) / 2), "solars", font=f_room,
               fill=(230, 230, 240), anchor="mm", stroke_width=2, stroke_fill=(20, 24, 50))
    for name, r in L.DERELICTS:
        b = box(r)
        d.text(((b[0] + b[2]) / 2, b[3] + 8), "derelict", font=f_room, fill=(150, 150, 160), anchor="mm")
    for name, r in L.RADIATORS:
        b = box(r)
        d.text(((b[0] + b[2]) / 2, b[3] + 8), "radiators", font=f_small, fill=(200, 140, 100), anchor="mm")

    # legend
    ly = W + 10
    sec_hall = tuple(int(L.DEPTS["sec"][k] * 0.45 + C_HALL[k] * 0.55) for k in range(3))
    items = [(C_HALL, "public hall"), (sec_hall, "department hall (tinted)"), (C_GLASS, "glass walkway"),
             (C_TUNNEL, "secure tunnel"), (C_MAINT, "maintenance"), (C_RWALL, "reinforced wall"),
             (C_EXT, "external airlock"),
             (C_DOOR, "door"), (C_ACCESS, "access door"), (C_DESK, "desk"), (C_SDOOR, "secure door"),
             (C_BLAST, "blast doors"), ((220, 60, 60), "turrets"), (L.DEPTS["sec"], "Security post")]
    x = 14
    f_leg = font(13)
    for c, t in items:
        wdt = 34 + int(d.textlength(t, font=f_leg))
        if x + wdt > W - 10:
            x, ly = 14, ly + 24
        d.rectangle([x, ly, x + 16, ly + 16], fill=c)
        d.text((x + 22, ly + 8), t, font=f_leg, fill=(220, 220, 220), anchor="lm")
        x += wdt
    d.text((14, ly + 36), "Perihelion Station - block plan, 1 tile = %d px, 255x255 z-level" % S,
           font=f_leg, fill=(160, 160, 170), anchor="lm")

    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out)
    print("wrote", out, "rooms:", len(L.ROOMS), "doors:", len(doors), "tunnels:", len(L.MAINT))
    for p in problems:
        print("PROBLEM:", p)
    if not problems:
        print("no problems")


if __name__ == "__main__":
    main()
