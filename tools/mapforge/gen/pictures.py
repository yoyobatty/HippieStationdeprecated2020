"""Pictures of a generated station for review: the whole map in the game's own sprites, its networks, and close-ups of
the parts gen/net.py builds (engine, Atmospherics, the docks, a solar array), lit by the boot's lighting snapshot when
one exists (run_zone_check.sh writes data/mapforge/light_<name>.txt).

    python tools/mapforge/gen/pictures.py gen_c80_s1            # data/mapforge/gen_c80_s1.dmm
    python tools/mapforge/gen/pictures.py gen_c80_s1 --full-scale 0.3 --no-light
    python tools/mapforge/gen/pictures.py gen_c80_s1 --grid 40      # the station cut in 40-tile squares, for an audit

Writes data/previews/mapforge/<name>/: full.png, nets.png, and one png per close-up, plus sheet.png with the close-ups
side by side. Renders go through forge/render.py (SpacemanDMM's dmm-tools, "pretty" mode).
"""
import argparse
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import dmm, parse, render  # noqa: E402

ROOT = parse.ROOT
OUT = os.path.join(ROOT, "data", "previews", "mapforge")

# close-ups: name -> (how to find it: area prefixes or an object path, the margin round it in tiles)
SHOTS = (
    ("engine", ("area", ("/area/engine/supermatter",)), 12),
    ("atmos", ("area", ("/area/engine/atmos",)), 3),
    ("cargo_dock", ("port", "supply_home"), 7),
    ("mining_dock", ("port", "mining_home"), 7),
    ("escape_dock", ("port", "emergency_home"), 7),
    ("arrivals_dock", ("port", "arrivals_stationary"), 7),
    ("solar", ("area", ("/area/solar/",)), 6),
    # the learned departments (gen/learn/floorplan.py): the biggest cluster of their areas
    ("medical", ("dept", ("/area/medical", "/area/crew_quarters/heads/cmo")), 2),
    ("science", ("dept", ("/area/science", "/area/crew_quarters/heads/hor")), 2),
    ("security", ("dept", ("/area/security/brig", "/area/security/prison", "/area/security/main",
                           "/area/security/warden", "/area/ai_monitored/security", "/area/security/courtroom",
                           "/area/crew_quarters/heads/hos")), 2),
    ("service", ("dept", ("/area/crew_quarters/bar", "/area/crew_quarters/kitchen", "/area/hydroponics",
                          "/area/crew_quarters/theatre", "/area/janitor")), 2),
)
MAX_SIDE = 70           # a close-up box is cut to this many tiles a side round its middle


def find(m, how):
    kind, what = how
    if kind == "dept":
        tiles = {(x, y) for (x, y, z), t in m.tiles.items() if t.apath.startswith(what)}
        best = []
        left = set(tiles)
        while left:
            s0 = left.pop()
            grp, todo = [s0], [s0]
            while todo:
                a = todo.pop()
                for dx in range(-3, 4):
                    for dy in range(-3, 4):
                        b = (a[0] + dx, a[1] + dy)
                        if b in left:
                            left.discard(b)
                            grp.append(b)
                            todo.append(b)
            if len(grp) > len(best):
                best = grp
        return best
    if kind == "area":
        tiles = [(x, y) for (x, y, z), t in m.tiles.items() if t.apath.startswith(what)]
        if what == ("/area/solar/",) and tiles:
            # one array: the tiles of the first solar area found
            a = sorted({m.get(*p).apath for p in tiles})[0]
            tiles = [p for p in tiles if m.get(*p).apath == a]
        return tiles
    for (x, y, z), t in m.tiles.items():
        for o in t.objs:
            if o.path == "/obj/docking_port/stationary" and o.get("id") == '"%s"' % what:
                # the port lies out where the shuttle will be: frame it with the station's airlocks nearest it
                locks = [(a, b) for (a, b, c), tt in m.tiles.items() if tt.has("/obj/machinery/door/airlock/external")
                         and abs(a - x) + abs(b - y) <= 12]
                locks.sort(key=lambda q: abs(q[0] - x) + abs(q[1] - y))
                return [(x, y)] + locks[:2]
    return []


def box(m, tiles, margin):
    x0, x1 = min(p[0] for p in tiles) - margin, max(p[0] for p in tiles) + margin
    y0, y1 = min(p[1] for p in tiles) - margin, max(p[1] for p in tiles) + margin
    if x1 - x0 + 1 > MAX_SIDE:
        c = (x0 + x1) // 2
        x0, x1 = c - MAX_SIDE // 2, c + MAX_SIDE // 2
    if y1 - y0 + 1 > MAX_SIDE:
        c = (y0 + y1) // 2
        y0, y1 = c - MAX_SIDE // 2, c + MAX_SIDE // 2
    return max(1, x0), max(1, y0), min(m.maxx, x1), min(m.maxy, y1)


def grid(m, path, out, size, scale):
    """The station's bounding box cut into size x size squares (grid_<col>_<row>.png, row 0 at the top, each
    captioned with its tile range), for reading the whole map square by square."""
    st = [(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and not t.apath.startswith("/area/space")]
    x0, x1 = min(p[0] for p in st), max(p[0] for p in st)
    y0, y1 = min(p[1] for p in st), max(p[1] for p in st)
    made = []
    os.makedirs(os.path.join(out, "grid"), exist_ok=True)
    rows = list(range(y1, y0 - 1, -size))
    for r, ytop in enumerate(rows):
        for c, xl in enumerate(range(x0, x1 + 1, size)):
            reg = (xl, max(y0, ytop - size + 1), min(x1, xl + size - 1), ytop)
            if not any(reg[0] <= p[0] <= reg[2] and reg[1] <= p[1] <= reg[3] for p in st):
                continue
            png = os.path.join(out, "grid", "grid_%d_%d.png" % (c, r))
            render.render(path, png, region=reg, scale=scale)
            _label(m, png, reg, scale)
            made.append(png)
            print("grid %d,%d  x %d-%d  y %d-%d  %s" % (c, r, reg[0], reg[2], reg[1], reg[3], png), flush=True)
    return made


def _label(m, png, reg, scale):
    """Each room's area name (its last two parts) at the middle of its biggest piece in the square, and the tile
    coordinates every 10 tiles on the edges: an audit reads what each room is meant to be."""
    from PIL import Image, ImageDraw
    img = Image.open(png).convert("RGB")
    d = ImageDraw.Draw(img)
    f = render._font(max(10, int(13 * scale)))
    px = 32 * scale
    by = {}
    for (x, y, z), t in m.tiles.items():
        if z == 1 and reg[0] <= x <= reg[2] and reg[1] <= y <= reg[3] and t.tpath.startswith("/turf/open")                 and not t.apath.startswith(("/area/space", "/area/hallway")):
            by.setdefault(t.apath, []).append((x, y))
    for a, ts in by.items():
        if len(ts) < 6:
            continue
        cx = sum(p[0] for p in ts) / float(len(ts))
        cy = sum(p[1] for p in ts) / float(len(ts))
        c = min(ts, key=lambda p: (p[0] - cx) ** 2 + (p[1] - cy) ** 2)
        name = "/".join(a.split("/")[-2:])
        X, Y = (c[0] - reg[0]) * px, (reg[3] - c[1]) * px
        w = d.textlength(name, font=f)
        d.rectangle([X - 2, Y - 1, X + w + 2, Y + 14 * scale + 2], fill=(0, 0, 0))
        d.text((X, Y), name, fill=(255, 235, 120), font=f)
    for x in range(reg[0], reg[2] + 1):
        if x % 10 == 0:
            d.text(((x - reg[0]) * px + 2, 2), str(x), fill=(120, 255, 255), font=f)
    for y in range(reg[1], reg[3] + 1):
        if y % 10 == 0:
            d.text((2, (reg[3] - y) * px + 2), str(y), fill=(120, 255, 255), font=f)
    img.save(png)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("name", help="data/mapforge/<name>.dmm")
    ap.add_argument("--full-scale", type=float, default=0.25)
    ap.add_argument("--shot-scale", type=float, default=0.75)
    ap.add_argument("--no-light", action="store_true")
    ap.add_argument("--grid", type=int, default=0, help="only cut the station into squares of this many tiles")
    ap.add_argument("--path", help="a .dmm anywhere (the name is then only the output folder)")
    a = ap.parse_args(argv)
    path = a.path or os.path.join(ROOT, "data", "mapforge", a.name + ".dmm")
    out = os.path.join(OUT, a.name)
    os.makedirs(out, exist_ok=True)
    m = dmm.read(path)
    if a.grid:
        return grid(m, path, out, a.grid, a.shot_scale)
    light = os.path.join(ROOT, "data", "mapforge", "light_%s.txt" % a.name)
    light = light if (os.path.exists(light) and not a.no_light) else None
    made = []
    full = render.render(path, os.path.join(out, "full.png"), scale=a.full_scale)
    made.append(full)
    print("full", full, flush=True)
    r = subprocess.run([sys.executable, os.path.join(HERE, "..", "studies", "net_view.py"), a.name, "--scale", "4"],
                       capture_output=True, text=True, cwd=ROOT)
    nets = os.path.join(OUT, a.name + "_nets.png")
    if os.path.exists(nets):
        os.replace(nets, os.path.join(out, "nets.png"))
        made.append(os.path.join(out, "nets.png"))
        print("nets", os.path.join(out, "nets.png"), flush=True)
    else:
        print("nets failed:", r.stderr[-500:])
    shots, caps = [], []
    for name, how, margin in SHOTS:
        tiles = find(m, how)
        if not tiles:
            print("%s: not on the map" % name)
            continue
        reg = box(m, tiles, margin)
        png = os.path.join(out, name + ".png")
        try:
            render.render(path, png, region=reg, scale=a.shot_scale, light=light)
        except Exception as e:                      # noqa: BLE001 - one failed close-up doesn't stop the rest
            print("%s: render failed: %s" % (name, str(e)[:300]))
            continue
        shots.append(png)
        caps.append("%s  %d,%d - %d,%d" % (name.replace("_", " "), reg[0], reg[1], reg[2], reg[3]))
        made.append(png)
        print(name, png, flush=True)
    if shots:
        sheet = render.sheet(shots, caps, os.path.join(out, "sheet.png"), title=a.name)
        made.append(sheet)
        print("sheet", sheet)
    return made


if __name__ == "__main__":
    main()
