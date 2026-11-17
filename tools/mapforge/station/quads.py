"""Room-by-room review sheets of a generated map: every room cut into four quarters, each quarter shown and scored.

    python tools/mapforge/station/quads.py <map.dmm> [--out DIR] [--only TEXT] [--per 6]

A room is a run of floor of one area closed in by walls, glass and airlocks. Its box is split at the middle into
NW / NE / SW / SE; each quarter gets a few numbers (floor, dense pieces, loose items, wall pieces) and flags:
  bare     9+ floor tiles and nothing on them or on their walls but lights, APC and alarms (the liminal look)
  stack    two dense pieces on one tile, or two pieces of one kind (sprites drawn over each other)
  doorway  a dense piece on the tile straight inside an airlock
  boxed    a floor tile with every side blocked (nobody can stand there)
Writes DIR/sheet_NN.png (rooms side by side, quarters outlined and named) and DIR/quads.txt (numbers + flags).
Halls, maint corridors and solar fields are left out: they are not rooms.
"""
import argparse
import os
import sys
from collections import Counter

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import dmm, kit, render as R  # noqa: E402
from forge.kit import CARD, DELTA  # noqa: E402

Image.MAX_IMAGE_PIXELS = None
SKIP = ("/area/hallway/", "/area/solar/", "/area/maintenance/central", "/area/maintenance/port",
        "/area/maintenance/starboard", "/area/maintenance/fore", "/area/maintenance/aft", "/area/space")
WALLPIECE = ("/obj/machinery/light", "/obj/machinery/power/apc", "/obj/machinery/airalarm", "/obj/machinery/firealarm",
             "/obj/machinery/light_switch", "/obj/structure/extinguisher_cabinet", "/obj/machinery/newscaster",
             "/obj/item/radio/intercom", "/obj/machinery/requests_console", "/obj/structure/sign",
             "/obj/machinery/status_display", "/obj/structure/noticeboard", "/obj/structure/mirror",
             "/obj/machinery/camera", "/obj/machinery/button", "/obj/machinery/computer/security/telescreen",
             "/obj/structure/fireaxecabinet", "/obj/machinery/defibrillator_mount")
UTILITY = ("/obj/machinery/light", "/obj/machinery/power/apc", "/obj/machinery/airalarm", "/obj/machinery/firealarm",
           "/obj/machinery/light_switch", "/obj/machinery/camera")
IGNORE = ("/obj/effect/landmark", "/obj/effect/turf_decal", "/obj/machinery/atmospherics/pipe", "/obj/structure/cable",
          "/obj/machinery/door/firedoor", "/obj/effect/decal/cleanable", "/obj/machinery/navbeacon",
          "/obj/structure/disposalpipe", "/obj/effect/mapping_helpers", "/obj/effect/spawner/lootdrop/maintenance")


def is_floor(t):
    return t and t.tpath.startswith("/turf/open") and not t.tpath.startswith("/turf/open/space") and \
        not t.has("/obj/machinery/door/airlock") and not t.has(kit.WINDOW) and not t.has("/obj/structure/grille") \
        and not t.has("/obj/structure/window")


def rooms_of(m):
    seen, out = set(), []
    for x in range(1, m.maxx + 1):
        for y in range(1, m.maxy + 1):
            t = m.get(x, y)
            if (x, y) in seen or not is_floor(t):
                continue
            area = t.apath
            part, st = [], [(x, y)]
            seen.add((x, y))
            while st:
                p = st.pop()
                part.append(p)
                for d in CARD:
                    q = (p[0] + DELTA[d][0], p[1] + DELTA[d][1])
                    tq = m.get(*q) if 1 <= q[0] <= m.maxx and 1 <= q[1] <= m.maxy else None
                    if q not in seen and is_floor(tq) and tq.apath == area:
                        seen.add(q)
                        st.append(q)
            if len(part) >= 4 and not area.startswith(SKIP):
                out.append((area, part))
    return out


def counted(o):
    return not o.path.startswith(IGNORE) and not o.path.startswith("/obj/machinery/atmospherics/components/unary/vent") \
        and not o.path.startswith("/obj/machinery/door")


def score(m, area, tiles):
    xs, ys = [p[0] for p in tiles], [p[1] for p in tiles]
    x1, x2, y1, y2 = min(xs), max(xs), min(ys), max(ys)
    mx, my = (x1 + x2) / 2.0, (y1 + y2) / 2.0
    tset = set(tiles)
    quads = {k: [] for k in ("NW", "NE", "SW", "SE")}
    for p in tiles:
        quads[("N" if p[1] > my else "S") + ("W" if p[0] <= mx else "E")].append(p)
    res = {}
    for k, ps in quads.items():
        dense = items = wall = dressing = 0
        flags = []
        for p in ps:
            t = m.get(*p)
            objs = [o for o in t.objs if counted(o)]
            d = [o for o in objs if kit.is_dense_atom(o)]
            dense += len(d)
            w = [o for o in objs if o.path.startswith(WALLPIECE)]
            wall += len(w)
            # a room's light, APC and alarms are on every wall: they don't keep a quarter from looking empty
            dressing += sum(1 for o in w if not o.path.startswith(UTILITY))
            items += sum(1 for o in objs if o.path.startswith("/obj/item"))
            # a machine on a table or rack is how it's meant to stand
            if len(d) > 1 and not any(o.path.startswith(("/obj/structure/table", "/obj/structure/rack")) for o in d):
                flags.append("stack %d,%d %s" % (p[0], p[1], "+".join(o.path.rsplit("/", 1)[-1] for o in d)))
            # slimes share a pen tile on purpose
            kinds = Counter(o.path for o in objs if not o.path.startswith(("/obj/item", "/obj/effect",
                                                                           "/mob/living/simple_animal/slime")))
            dup = [kk for kk, n in kinds.items() if n > 1]
            if dup:
                flags.append("stack %d,%d 2x %s" % (p[0], p[1], dup[0].rsplit("/", 1)[-1]))
            # two different seats on one tile (a teal and a black armchair drawn over each other)
            seats = sorted({o.path for o in objs if o.path.startswith(("/obj/structure/chair", "/obj/structure/bed"))})
            if len(seats) > 1:
                flags.append("stack %d,%d %s" % (p[0], p[1], "+".join(s.rsplit("/", 1)[-1] for s in seats)))
            if d:
                for dd in CARD:
                    q = (p[0] + DELTA[dd][0], p[1] + DELTA[dd][1])
                    if m.get(*q) and m.get(*q).has("/obj/machinery/door/airlock"):
                        flags.append("doorway %d,%d %s" % (p[0], p[1], d[0].path.rsplit("/", 1)[-1]))
                        break
            elif not any(o.path.startswith("/obj/structure/window") for o in t.objs):
                nb = []
                for dd in CARD:
                    q = (p[0] + DELTA[dd][0], p[1] + DELTA[dd][1])
                    tq = m.get(*q)
                    nb.append(tq is None or not tq.tpath.startswith("/turf/open") or
                              kit.dense([o for o in tq.objs if not o.path.startswith("/obj/machinery/door")]))
                if all(nb):
                    flags.append("boxed %d,%d" % p)
        if len(ps) >= 9 and dense == 0 and items == 0 and dressing == 0:
            flags.append("bare")
        res[k] = dict(floor=len(ps), dense=dense, items=items, wall=wall, flags=flags)
    return (x1, y1, x2, y2), (mx, my), res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dmm")
    ap.add_argument("--out")
    ap.add_argument("--only", default="")
    ap.add_argument("--per", type=int, default=6, help="rooms per sheet")
    ap.add_argument("--full", help="reuse this whole-map render")
    a = ap.parse_args()
    name = os.path.splitext(os.path.basename(a.dmm))[0]
    out = a.out or os.path.join(R.PREVIEWS, "quads", name)
    os.makedirs(out, exist_ok=True)
    m = dmm.read(a.dmm)
    full = a.full or os.path.join(out, "full.png")
    if not a.full or not os.path.exists(full):
        R.render(a.dmm, full)
    img = Image.open(full).convert("RGB")
    tile = img.width // m.maxx
    rooms = [(ar, ts) for ar, ts in rooms_of(m) if a.only in ar]
    rooms.sort(key=lambda r: (r[0], min(r[1])))
    lines, cells = [], []
    font = R._font(15)
    for i, (area, tiles) in enumerate(rooms):
        (x1, y1, x2, y2), (mx, my), res = score(m, area, tiles)
        label = "%d %s (%dx%d at %d,%d)" % (i, area.replace("/area/", ""), x2 - x1 + 1, y2 - y1 + 1, x1, y1)
        lines.append(label)
        for k in ("NW", "NE", "SW", "SE"):
            q = res[k]
            lines.append("   %s floor %3d dense %2d items %2d wall %2d  %s" % (
                k, q["floor"], q["dense"], q["items"], q["wall"], "; ".join(q["flags"])))
        # crop: the room box and one tile round it; tiles outside the room dimmed; quarter lines through the middle
        bx1, by1, bx2, by2 = x1 - 1, y1 - 1, x2 + 1, y2 + 1
        box = ((bx1 - 1) * tile, (m.maxy - by2) * tile, bx2 * tile, (m.maxy - by1 + 1) * tile)
        crop = img.crop(box).copy()
        dim = Image.new("RGBA", crop.size, (0, 0, 0, 0))
        dd = ImageDraw.Draw(dim)
        tset = set(tiles)
        for x in range(bx1, bx2 + 1):
            for y in range(by1, by2 + 1):
                if (x, y) not in tset:
                    px, py = (x - bx1) * tile, (by2 - y) * tile
                    dd.rectangle((px, py, px + tile - 1, py + tile - 1), fill=(0, 0, 0, 110))
        crop = Image.alpha_composite(crop.convert("RGBA"), dim).convert("RGB")
        d = ImageDraw.Draw(crop)
        # W is x <= mx, N is y > my: the lines run between those tiles
        vx = (int(mx) - bx1 + 1) * tile
        hy = (by2 - int(my)) * tile
        d.line((vx, tile, vx, crop.height - tile), fill=(255, 60, 60), width=2)
        d.line((tile, hy, crop.width - tile, hy), fill=(255, 60, 60), width=2)
        for k, (qx, qy) in {"NW": (tile + 2, tile + 2), "NE": (vx + 3, tile + 2), "SW": (tile + 2, hy + 2),
                            "SE": (vx + 3, hy + 2)}.items():
            fl = [f.split()[0] for f in res[k]["flags"]]
            txt = k + (" " + ",".join(sorted(set(fl))) if fl else "")
            d.text((qx + 1, qy + 1), txt, fill=(0, 0, 0), font=font)
            d.text((qx, qy), txt, fill=(255, 235, 80) if fl else (255, 255, 255), font=font)
        cells.append((str(i) + " " + area.replace("/area/", "") + " @%d,%d" % (x1, y1), crop))
    # sheets: rooms in a row-wrapped grid, at most ~1500 px wide
    n = 0
    for s in range(0, len(cells), a.per):
        chunk = cells[s:s + a.per]
        rows, row, w = [], [], 0
        for c in chunk:
            if row and w + c[1].width > 1500:
                rows.append(row)
                row, w = [], 0
            row.append(c)
            w += c[1].width + 12
        rows.append(row)
        W = max(sum(c[1].width + 12 for c in r) for r in rows) + 12
        H = sum(max(c[1].height for c in r) + 30 for r in rows) + 12
        sheet = Image.new("RGB", (W, H), (24, 26, 32))
        sd = ImageDraw.Draw(sheet)
        y = 6
        for r in rows:
            x = 12
            for cap, im in r:
                sd.text((x, y), cap, fill=(220, 220, 230), font=font)
                sheet.paste(im, (x, y + 22))
                x += im.width + 12
            y += max(c[1].height for c in r) + 30
        if max(W, H) > 1800:
            f = 1800.0 / max(W, H)
            sheet = sheet.resize((int(W * f), int(H * f)), Image.LANCZOS)
        sheet.save(os.path.join(out, "sheet_%02d.png" % n))
        n += 1
    open(os.path.join(out, "quads.txt"), "w").write("\n".join(lines) + "\n")
    flagged = Counter(f.split()[0] for l in lines if l.startswith("   ") for f in l.split("  ")[-1].split("; ") if f.strip())
    print("%d rooms, %d sheets in %s; flags %s" % (len(rooms), n, out, dict(flagged)))


if __name__ == "__main__":
    main()
