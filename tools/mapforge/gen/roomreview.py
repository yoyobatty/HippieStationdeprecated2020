"""Room-by-room review sheets of a generated station: one picture per room piece and per hall segment, the room
outlined in the game's own sprites, with its card printed under it (its doors with style, name, access and what lies
beyond each, what stands in it, and the audit's and the placement study's findings for it). For reading a station
one place at a time, as the user asked 2026-11-26: "double check every room and hallway one by one, make sure it's
sensical, functional like an ss13 map with good human like pathing, design and function".

    python tools/mapforge/gen/roomreview.py <dmm> [--out DIR] [--scale 0.75] [--only security]
    -> DIR/index.txt (one line a place: number, area, tiles, picture) and DIR/NNN_<area>.png

The whole map is rendered once (forge/render.py, dmm-tools) and cut per place; halls longer than SEG tiles are cut
into segments along their length; maintenance is left out unless --maint.
"""
import argparse
import os
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "learn"))
from forge import corpus as CO, dmm, function as FN, parse, render  # noqa: E402

OUT = os.path.join(parse.ROOT, "data", "previews", "mapforge")
N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
SKIP = ("/area/space", "/area/solar", "/area/shuttle", "/area/centcom", "/area/lavaland", "/area/mine", "/area/ruin")
SEG = 28            # a hall piece longer than this is cut into segments this long
MARGIN = 2
MIN_TILES = 4
NOT_LISTED = ("/obj/structure/cable", "/obj/machinery/atmospherics/pipe", "/obj/structure/disposalpipe", "/obj/effect",
              "/obj/machinery/light", "/obj/machinery/door/firedoor", "/obj/structure/lattice", "/obj/item/stack/cable")


def _floor(t):
    return t is not None and t.tpath.startswith("/turf/open") and not t.tpath.startswith("/turf/open/space") \
        and not CO.solid(t) and not t.has("/obj/machinery/door")


def places(m, maint=False, only=None):
    """[(area, tiles)] room pieces and hall segments, departments together (sorted by area, then position)."""
    by = defaultdict(set)
    for (x, y, z), t in m.tiles.items():
        if z != 1 or not _floor(t) or t.apath.startswith(SKIP):
            continue
        if t.apath.startswith("/area/maintenance") and not maint:
            continue
        if only and only not in t.apath:
            continue
        by[t.apath].add((x, y))
    out = []
    for area, tiles in sorted(by.items()):
        left = set(tiles)
        comps = []
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
            if len(comp) >= MIN_TILES:
                comps.append(comp)
        for comp in sorted(comps, key=lambda c: (min(p[1] for p in c), min(p[0] for p in c))):
            xs, ys = [p[0] for p in comp], [p[1] for p in comp]
            w, h = max(xs) - min(xs) + 1, max(ys) - min(ys) + 1
            if area.startswith(("/area/hallway", "/area/maintenance")) and max(w, h) > SEG:
                ax = 0 if w >= h else 1
                lo = min(p[ax] for p in comp)
                hi = max(p[ax] for p in comp)
                for a in range(lo, hi + 1, SEG):
                    seg = {p for p in comp if a <= p[ax] < a + SEG}
                    if len(seg) >= MIN_TILES:
                        out.append((area, seg))
            else:
                out.append((area, comp))
    return out


def _short(path, pre):
    return path[len(pre):] if path.startswith(pre) else path


def card(m, area, tiles, au, ps):
    """The text under a place's picture."""
    import doordb as DD
    lines = []
    xs, ys = [p[0] for p in tiles], [p[1] for p in tiles]
    lines.append("%s  %d tiles  x %d-%d  y %d-%d" % (area, len(tiles), min(xs), max(xs), min(ys), max(ys)))
    doors = sorted({(p[0] + dx, p[1] + dy) for p in tiles for dx, dy in N4
                    if (m.get(p[0] + dx, p[1] + dy) is not None and m.get(p[0] + dx, p[1] + dy).has("/obj/machinery/door"))})
    for d in doors:
        t = m.get(*d)
        a = next((o for o in t.objs if o.path.startswith(("/obj/machinery/door/airlock", "/obj/machinery/door/window",
                                                            "/obj/machinery/door/poddoor"))), None)
        if a is None:
            a = next(o for o in t.objs if o.path.startswith("/obj/machinery/door"))
        acc = ";".join(v.strip('"') for k, v in a.vars if k in ("req_access_txt", "req_one_access_txt") and v.strip('"') not in ("", "0"))
        s = DD.sides(m, *d)
        beyond = ""
        if s:
            far = [q for q in s if q[0] != area or q[2] not in tiles]
            beyond = ", ".join(sorted({_short(q[0], "/area/") for q in far})) if far else "same area"
        lines.append("  door %d,%d %s %s%s -> %s" % (d[0], d[1], _short(a.path, "/obj/machinery/door/") or "/",
                                                    ('"%s"' % a.get("name").strip('"')) if a.get("name") else "",
                                                    (" access " + acc) if acc else "", beyond))
    c = Counter()
    for p in tiles:
        for o in m.get(*p).objs:
            if o.path.startswith(NOT_LISTED) or o.path.startswith("/obj/item"):
                continue
            c[_short(_short(o.path.split("{")[0], "/obj/machinery/"), "/obj/structure/")] += 1
    items = Counter()
    for p in tiles:
        for o in m.get(*p).objs:
            if o.path.startswith("/obj/item"):
                items[o.path.split("/")[-1].split("{")[0]] += 1
    lines += _wrap("  has: " + ", ".join("%s%s" % (k, (" x%d" % n) if n > 1 else "") for k, n in sorted(c.items())))
    if items:
        lines += _wrap("  items: " + ", ".join("%s%s" % (k, (" x%d" % n) if n > 1 else "") for k, n in items.most_common(14)))
    free = sum(1 for p in tiles if not any(FN.is_dense(o) for o in m.get(*p).objs))
    lines.append("  free floor %d of %d" % (free, len(tiles)))
    box = (min(xs) - 1, min(ys) - 1, max(xs) + 1, max(ys) + 1)
    found = []
    for k, v in au.items():
        for it in v if isinstance(v, list) else ():
            if len(it) >= 3 and box[0] <= it[0] <= box[2] and box[1] <= it[1] <= box[3] and (it[0], it[1]) != (0, 0):
                found.append("%s: %s" % (k, it[2]))
            elif len(it) >= 3 and (it[0], it[1]) == (0, 0) and str(it[2]).startswith(area + ":"):
                found.append("%s: %s" % (k, it[2]))
    for k, v in ps.items():
        if k.startswith("_"):
            continue
        for it in v:
            if (it[0], it[1]) == (0, 0):
                if str(it[2]).startswith(area + ":") or str(it[2]).startswith(area + " "):
                    found.append("%s: %s" % (k, it[2]))
            elif (it[0], it[1]) in tiles:
                found.append("%s: %s" % (k, it[2]))
    for f in found[:10]:
        lines += _wrap("  ! " + f)
    return lines


def _wrap(s, n=120):
    out = []
    while len(s) > n:
        cut = s.rfind(", ", 0, n)
        cut = cut + 1 if cut > 20 else n
        out.append(s[:cut])
        s = "      " + s[cut:].lstrip()
    out.append(s)
    return out


def main(argv=None):
    from PIL import Image, ImageDraw
    ap = argparse.ArgumentParser()
    ap.add_argument("dmm")
    ap.add_argument("--out")
    ap.add_argument("--scale", type=float, default=0.75)
    ap.add_argument("--maint", action="store_true")
    ap.add_argument("--only", help="only areas whose path holds this text")
    a = ap.parse_args(argv)
    name = os.path.splitext(os.path.basename(a.dmm))[0]
    out = a.out or os.path.join(OUT, name, "rooms")
    os.makedirs(out, exist_ok=True)
    m = dmm.read(a.dmm)
    full = os.path.join(out, "_full.png")
    if not os.path.exists(full) or os.path.getmtime(full) < os.path.getmtime(a.dmm):
        render.render(a.dmm, full, scale=a.scale)
    img = Image.open(full).convert("RGB")
    px = 32 * a.scale
    import audit as AU
    import placestudy as PS
    au = AU.audit(m)
    ps = PS.check(m)
    font = render._font(13)
    idx = []
    for i, (area, tiles) in enumerate(places(m, a.maint, a.only)):
        xs, ys = [p[0] for p in tiles], [p[1] for p in tiles]
        x0, x1 = max(1, min(xs) - MARGIN), min(m.maxx, max(xs) + MARGIN)
        y0, y1 = max(1, min(ys) - MARGIN), min(m.maxy, max(ys) + MARGIN)
        crop = img.crop((int((x0 - 1) * px), int((m.maxy - y1) * px), int(x1 * px), int((m.maxy - y0 + 1) * px)))
        d = ImageDraw.Draw(crop)
        # the place's outline: edges of its tiles that face a tile not in it
        for (x, y) in tiles:
            X, Y = (x - x0) * px, (y1 - y) * px
            for (dx, dy), seg in (((0, 1), (X, Y, X + px, Y)), ((0, -1), (X, Y + px, X + px, Y + px)),
                                  ((-1, 0), (X, Y, X, Y + px)), ((1, 0), (X + px, Y, X + px, Y + px))):
                if (x + dx, y + dy) not in tiles:
                    d.line(seg, fill=(255, 200, 0), width=2)
        for x in range(x0, x1 + 1):
            if x % 5 == 0:
                d.text(((x - x0) * px + 2, 1), str(x), fill=(120, 255, 255), font=font)
        for y in range(y0, y1 + 1):
            if y % 5 == 0:
                d.text((1, (y1 - y) * px + 2), str(y), fill=(120, 255, 255), font=font)
        lines = card(m, area, tiles, au, ps)
        W = max(crop.width, 760)
        H = crop.height + 16 * len(lines) + 8
        sheet = Image.new("RGB", (W, H), (16, 16, 20))
        sheet.paste(crop, (0, 0))
        dd = ImageDraw.Draw(sheet)
        for k, ln in enumerate(lines):
            dd.text((4, crop.height + 4 + 16 * k), ln, fill=(235, 235, 235) if k else (255, 220, 120), font=font)
        fn = "%03d_%s.png" % (i, area.replace("/area/", "").replace("/", "_"))
        sheet.save(os.path.join(out, fn))
        idx.append("%03d  %-48s %4d tiles  %s" % (i, area, len(tiles), fn))
    open(os.path.join(out, "index.txt"), "w").write("\n".join(idx) + "\n")
    print("%d places -> %s" % (len(idx), out))


if __name__ == "__main__":
    main()
