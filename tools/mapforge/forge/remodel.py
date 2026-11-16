"""Remodel a whole department in place: write a blueprint that keeps every wall, door, window, pipe, cable, light and
wall piece, and re-furnishes each room from the corpus by its room type.

    python tools/mapforge/mapforge.py remodel science /area/science,/area/crew_quarters/heads/hor \\
        --keep /area/science/mixing,/area/science/server,/area/science/xenobiology,/area/science/robotics/mechbay

- rooms = areas under the given prefixes; --keep areas (functional cores: burn chambers, server loops, slime pens,
  mech bay ports) are left exactly as they are
- each room must end with every machine and purpose-built locker it had (counts kept), placed by the furnisher with
  the learned rules (facing, fronts, doors, glass, squeezes, pairs)
- items and pets that exist once on the whole map (the RD's gear, Lamarr) are put back in the same room
- job start and event landmarks stay, moved off any new furniture
The blueprint lands in tools/mapforge/blueprints/<name>.py; edit its LAYOUT to reshape walls, then build as usual.
"""
import os
from collections import Counter

from forge import dmm
from forge.corpus import ANCHOR, INFRA, mounted

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
HIPPIE = os.path.join(ROOT, "_maps", "map_files", "HippieStation", "hippiestation.dmm")
LETTERS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
# these must survive a remodel with their counts: they're what the room is for
REQUIRED = ("/obj/machinery", "/obj/structure/closet/secure_closet", "/obj/structure/closet/wardrobe",
            "/obj/structure/closet/l3closet", "/obj/structure/closet/bombcloset", "/obj/structure/closet/radiation",
            "/obj/structure/reagent_dispensers", "/obj/structure/table/optable", "/obj/structure/displaycase",
            "/obj/structure/bodycontainer", "/obj/structure/tank_dispenser", "/obj/structure/closet/crate/freezer")
NOT_REQUIRED = ("/obj/machinery/door", "/obj/machinery/light", "/obj/machinery/atmospherics", "/obj/machinery/power/apc",
                "/obj/machinery/airalarm", "/obj/machinery/firealarm", "/obj/machinery/camera", "/obj/machinery/holopad",
                "/obj/machinery/navbeacon", "/obj/machinery/light_switch", "/obj/machinery/status_display",
                "/obj/machinery/newscaster", "/obj/machinery/requests_console", "/obj/machinery/button",
                "/obj/machinery/disposal", "/obj/machinery/conveyor", "/obj/machinery/conveyor_switch",
                "/obj/machinery/computer/security/telescreen", "/obj/machinery/keycard_auth", "/obj/machinery/flasher",
                "/obj/machinery/vending/wallmed", "/obj/machinery/defibrillator_mount", "/obj/machinery/power/terminal")


def write(name, prefixes, keep, path_out=None, base=HIPPIE):
    m = dmm.read(base)
    prefixes = tuple(prefixes)
    keep = tuple(keep)

    def mine(a):
        return a.startswith(prefixes) and not a.startswith(keep)
    tiles = {(x, y): t for (x, y, z), t in m.tiles.items() if z == 1 and mine(t.apath)}
    floors = {p for p, t in tiles.items() if t.tpath.startswith("/turf/open") and not t.tpath.startswith("/turf/open/space")
              and not t.has("/obj/machinery/door") and not t.has("/obj/effect/spawner/structure/window")
              and not t.has("/obj/structure/grille")}
    xs = [p[0] for p in floors] or [0]
    ys = [p[1] for p in floors]
    x1, y1, x2, y2 = min(xs) - 1, min(ys) - 1, max(xs) + 1, max(ys) + 1
    # small staffed posts are packed tight by design: re-furnishing makes them worse, keep them
    sizes = Counter(tiles[p].apath for p in floors)
    small = {a for a, n in sizes.items() if n < 16}
    floors = {p for p in floors if tiles[p].apath not in small}
    # store rooms (what they store fills 40%+ of the floor, e.g. canister storage) are packed by design too
    stores = set()
    for a in sizes:
        if a in small:
            continue
        n_req = sum(1 for p in floors if tiles[p].apath == a for o in tiles[p].objs
                    if o.path.startswith(REQUIRED) and not o.path.startswith(NOT_REQUIRED) and not mounted(o))
        if n_req >= 0.4 * sizes[a]:
            stores.add(a)
    floors = {p for p in floors if tiles[p].apath not in stores}
    keep = tuple(keep) + tuple(sorted(small | stores))
    areas = sorted({tiles[p].apath for p in floors})
    letter = {a: LETTERS[i] for i, a in enumerate(areas)}
    # map-wide counts, to spot one-of-a-kind items
    everywhere = Counter(o.path for t in m.tiles.values() for o in t.objs)
    req, keep_items, turf = {}, {}, {}
    for a in areas:
        c = Counter()
        items = []
        turfs = Counter()
        for p in floors:
            t = tiles[p]
            if t.apath != a:
                continue
            turfs[t.tpath] += 1
            for o in t.objs:
                if mounted(o):
                    continue
                if o.path.startswith(REQUIRED) and not o.path.startswith(NOT_REQUIRED):
                    c[o.path] += 1
                elif (o.path.startswith("/obj/item") or o.path.startswith("/mob")) and everywhere[o.path] == 1:
                    items.append(o.text())
        req[a] = sorted(c.items())
        keep_items[a] = items
        turf[a] = turfs.most_common(1)[0][0]
    lay, rooms = [], []
    for y in range(y2, y1 - 1, -1):
        lr, rr = [], []
        for x in range(x1, x2 + 1):
            if (x, y) in floors:
                lr.append(".")
                rr.append(letter[tiles[(x, y)].apath])
            else:
                lr.append("~")
                rr.append("~")
        lay.append("".join(lr))
        rooms.append("".join(rr))
    out = ['"""%s: remodel of %s (kept as they are: %s).' % (name, ", ".join(prefixes), ", ".join(keep) or "nothing"),
           "Generated by forge/remodel.py: walls, doors, glass, pipes, power, lights and wall pieces stay; every room is",
           'refurnished from the corpus with its own machines required. Reshape walls by editing LAYOUT."""',
           "NAME = %r" % name, 'STYLE = "meta"', 'INFRA = "keep"', "ORIGIN = (%d, %d)" % (x1, y1),
           "", 'LAYOUT = """', "\n".join(lay), '"""', "", 'ROOMS = """', "\n".join(rooms), '"""', "",
           'LEGEND = {"B": {"no_vent": True}}', "", "ROOMDEFS = {"]
    for a in areas:
        name_ = a.rsplit("/", 1)[-1].replace("_", " ").title()
        rq = ", ".join('("%s", %d)' % (p, n) if n > 1 else '"%s"' % p for p, n in req[a])
        out.append("    %r: dict(area=%r, floor=%r, name=%r," % (letter[a], a, turf[a], name_))
        out.append("              furnish=dict(kind=%r, seed=1, mode='template', require=[%s])," % (a, rq))
        out.append("              keep_items=%r)," % (keep_items[a],))
    out.append("}")
    out.append("FOOTPRINT = %r" % (areas,))
    path_out = path_out or os.path.join(ROOT, "tools", "mapforge", "blueprints", name + ".py")
    with open(path_out, "w") as f:
        f.write("\n".join(out) + "\n")
    return path_out, areas, req
