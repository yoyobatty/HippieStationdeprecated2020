"""Mine a map's dressing habits: decals, signs, table items and their offsets, dirs.

    python tools/mapforge/forge/style_mine.py [MetaStation]     -> data/mapforge/style_<map>.json + a text report

What it records, per context:
- decals under each kind of anchor (machine/structure type): how often, which decal, which dir
- decals next to doors (inside a room / on the hall side), by side relative to the door
- floor decals in halls and rooms with no anchor: trims by wall side, stripes, by area
- signs on walls: which sign, how far from the nearest door, pixel offsets by wall side
- items on tables: which items by area and table type, how many per table, their pixel_x/pixel_y
- turfs per area, so floors match the department
"""
import json
import os
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from forge import dmm  # noqa: E402
from forge.corpus import ANCHOR, INFRA, mounted, solid  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
MAPS = {"MetaStation": "MetaStation/MetaStation.dmm", "hippiestation": "HippieStation/hippiestation.dmm",
        "DeltaStation": "Deltastation/DeltaStation2.dmm", "BoxStation": "BoxStation/BoxStation.dmm"}
D4 = {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0)}


def area_kind(a):
    """Coarse room family: hallway / maintenance / department path two levels deep."""
    parts = a.split("/")
    if len(parts) > 2 and parts[2] in ("hallway", "maintenance"):
        return "/".join(parts[:3])
    return "/".join(parts[:4]) if len(parts) > 3 else a


def anchor_key(path):
    """Group anchors into families a decal habit applies to (vending/*, closet/crate/*, ...)."""
    for fam in ("/obj/machinery/vending", "/obj/structure/closet/crate", "/obj/structure/closet/secure_closet",
                "/obj/structure/closet", "/obj/machinery/portable_atmospherics/canister", "/obj/machinery/portable_atmospherics",
                "/obj/structure/reagent_dispensers", "/obj/machinery/computer", "/obj/structure/table", "/obj/structure/rack",
                "/obj/machinery/rnd", "/obj/machinery/suit_storage_unit", "/obj/machinery/hydroponics", "/obj/structure/chair",
                "/obj/machinery/disposal", "/obj/machinery/power", "/obj/machinery/atmospherics/components",
                "/obj/machinery/chem", "/obj/machinery/sleeper", "/obj/machinery/mecha_part_fabricator", "/obj/machinery/autolathe"):
        if path.startswith(fam):
            return fam
    return path


def mine(name):
    m = dmm.read(os.path.join(ROOT, "_maps", "map_files", MAPS[name]))
    st = {
        "under": defaultdict(Counter),      # anchor family -> decal text -> count
        "anchors": Counter(),               # anchor family -> tiles
        "door_side": defaultdict(Counter),  # "in"/"out" + decal -> count, for tiles beside an airlock
        "door_tiles": 0,
        "open_decal": defaultdict(Counter),  # area kind -> decal text (no anchor, not by door)
        "open_tiles": Counter(),
        "signs": Counter(),                 # sign path -> count
        "sign_door_dist": Counter(),
        "sign_offsets": defaultdict(Counter),  # wall side -> (px,py)
        "table_items": defaultdict(Counter),   # area kind -> item path
        "tables": Counter(),
        "items_per_table": Counter(),
        "item_offsets": defaultdict(Counter),  # item path -> "px,py"
        "turfs": defaultdict(Counter),
        "dirs": defaultdict(Counter),          # anchor path -> dir relative to wall side ("wallN:dir")
    }
    doors = {(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and t.has("/obj/machinery/door/airlock")}
    for (x, y, z), t in m.tiles.items():
        if z != 1 or not t.tpath.startswith("/turf/open") or t.tpath.startswith("/turf/open/space"):
            continue
        ak = area_kind(t.apath)
        st["turfs"][ak][t.tpath] += 1
        anchors = [o for o in t.objs if o.path.startswith(ANCHOR) and not o.path.startswith(INFRA) and not mounted(o)]
        decals = [o.text() for o in t.objs if o.path.startswith("/obj/effect/turf_decal")]
        walls = [d for d, (dx, dy) in D4.items() if solid(m.get(x + dx, y + dy, z))]
        near_door = [d for d, (dx, dy) in D4.items() if (x + dx, y + dy) in doors]
        if anchors:
            fam = anchor_key(anchors[0].path)
            st["anchors"][fam] += 1
            for dtext in decals:
                st["under"][fam][dtext] += 1
            if not decals:
                st["under"][fam]["(none)"] += 1
            a0 = anchors[0]
            if len(walls) == 1:
                st["dirs"][fam]["wall%d:dir%s" % (walls[0], a0.get("dir", "2"))] += 1
        elif near_door:
            st["door_tiles"] += 1
            for dtext in decals:
                st["door_side"][ak.split("/")[2] if ak.count("/") >= 2 else ak][dtext] += 1
        else:
            st["open_tiles"][ak] += 1
            for dtext in decals:
                st["open_decal"][ak][dtext] += 1
        # tables and what's on them
        if any(o.path.startswith("/obj/structure/table") for o in t.objs):
            st["tables"][ak] += 1
            items = [o for o in t.objs if o.path.startswith("/obj/item") and not mounted(o)]
            st["items_per_table"][min(len(items), 4)] += 1
            for it in items:
                st["table_items"][ak][it.path] += 1
                st["item_offsets"][it.path]["%d,%d" % (it.num("pixel_x"), it.num("pixel_y"))] += 1
        # signs (mounted on this tile's wall)
        for o in t.objs:
            if o.path.startswith("/obj/structure/sign"):
                st["signs"][o.path] += 1
                dd = min((abs(x - a) + abs(y - b) for a, b in doors), default=99)
                st["sign_door_dist"][min(dd, 8)] += 1
                side = walls[0] if len(walls) == 1 else 0
                st["sign_offsets"][side]["%d,%d" % (o.num("pixel_x"), o.num("pixel_y"))] += 1
    out = {k: ({kk: dict(vv) for kk, vv in v.items()} if isinstance(v, defaultdict) else (dict(v) if isinstance(v, Counter) else v))
           for k, v in st.items()}
    path = os.path.join(ROOT, "data", "mapforge", "style_%s.json" % name)
    json.dump(out, open(path, "w"), indent=0)
    return out


def report(s):
    lines = []
    lines.append("== decals under anchors (share of tiles with that decal)")
    for fam, n in sorted(s["anchors"].items(), key=lambda kv: -kv[1])[:28]:
        c = s["under"].get(fam, {})
        top = sorted(((v, k) for k, v in c.items() if k != "(none)"), reverse=True)[:3]
        lines.append("  %-52s %4d tiles: %s" % (fam, n, "; ".join("%s %.0f%%" % (k.replace("/obj/effect/turf_decal/", ""), 100 * v / n) for v, k in top)))
    lines.append("== decals on tiles beside airlocks, by area family (%d tiles)" % s["door_tiles"])
    for fam, c in sorted(s["door_side"].items(), key=lambda kv: -sum(kv[1].values()))[:8]:
        top = sorted(((v, k) for k, v in c.items()), reverse=True)[:4]
        lines.append("  %-20s %s" % (fam, "; ".join("%s x%d" % (k.replace("/obj/effect/turf_decal/", ""), v) for v, k in top)))
    lines.append("== open-floor decals by area (share of open tiles)")
    for ak, n in sorted(s["open_tiles"].items(), key=lambda kv: -kv[1])[:24]:
        c = s["open_decal"].get(ak, {})
        tot = sum(c.values())
        top = sorted(((v, k) for k, v in c.items()), reverse=True)[:3]
        lines.append("  %-42s %4d tiles, %.1f decals/tile: %s" % (ak, n, tot / n, "; ".join("%s x%d" % (k.replace("/obj/effect/turf_decal/", ""), v) for v, k in top)))
    lines.append("== signs: %d; distance to nearest airlock: %s" % (sum(s["signs"].values()), dict(sorted(s["sign_door_dist"].items()))))
    lines.append("   top: " + ", ".join("%s x%d" % (k.replace("/obj/structure/sign/", ""), v) for k, v in sorted(s["signs"].items(), key=lambda kv: -kv[1])[:12]))
    for side, c in s["sign_offsets"].items():
        lines.append("   wall %s offsets: %s" % (side, ", ".join("%s x%d" % kv for kv in sorted(c.items(), key=lambda kv: -kv[1])[:3])))
    lines.append("== items per table: %s" % dict(sorted(s["items_per_table"].items())))
    for ak, n in sorted(s["tables"].items(), key=lambda kv: -kv[1])[:12]:
        c = s["table_items"].get(ak, {})
        top = sorted(((v, k) for k, v in c.items()), reverse=True)[:5]
        lines.append("  %-40s %3d tables: %s" % (ak, n, ", ".join("%s x%d" % (k.rsplit("/", 1)[-1], v) for v, k in top)))
    lines.append("== item offsets (most common items)")
    for it, c in sorted(s["item_offsets"].items(), key=lambda kv: -sum(kv[1].values()))[:14]:
        lines.append("  %-50s %s" % (it.replace("/obj/item/", ""), ", ".join("%s x%d" % kv for kv in sorted(c.items(), key=lambda kv: -kv[1])[:4])))
    lines.append("== anchor dir by wall side (wallN = wall on that side)")
    for fam in ("/obj/machinery/computer", "/obj/structure/chair", "/obj/machinery/vending", "/obj/machinery/disposal"):
        c = s["dirs"].get(fam, {})
        lines.append("  %-30s %s" % (fam, ", ".join("%s x%d" % kv for kv in sorted(c.items(), key=lambda kv: -kv[1])[:6])))
    return "\n".join(lines)


if __name__ == "__main__":
    name = sys.argv[1] if len(sys.argv) > 1 else "MetaStation"
    s = mine(name)
    r = report(json.load(open(os.path.join(ROOT, "data", "mapforge", "style_%s.json" % name))))
    open(os.path.join(ROOT, "data", "mapforge", "style_%s.txt" % name), "w").write(r)
    print(r)
