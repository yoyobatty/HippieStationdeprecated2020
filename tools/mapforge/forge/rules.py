"""Rule registry: every ruling the user has given on map layouts, in their words, with a check that runs on any
parsed map (human or generated). Running it on the human maps shows how often human mappers break a ruling, so we
know which rulings are stricter than the human maps (a ruling still wins).

    python tools/mapforge/forge/rules.py                  # human maps + _maps/map_files/Generated: hits per 1000 floor
    python tools/mapforge/forge/rules.py --list           # every ruling, and what enforces it
    python tools/mapforge/forge/rules.py a.dmm --spots R03  # where rule R03 is broken on a.dmm

A rule with check=None is enforced only inside the builder (named in `enforced`); it still needs a map check.
New rulings: add a Rule here the same day, with the user's words and a check; then fix the generator.
"""
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import parse  # noqa: E402
from forge.parse import DIRS, SIDE  # noqa: E402

TALL = ("/obj/machinery/vending", "/obj/structure/closet", "/obj/structure/bookcase", "/obj/machinery/suit_storage_unit",
        "/obj/machinery/rnd/production", "/obj/machinery/autolathe", "/obj/structure/reagent_dispensers/fueltank",
        "/obj/structure/reagent_dispensers/watertank")
LOOSE_OK = ("/obj/structure/closet/crate", "/obj/structure/closet/body_bag", "/obj/structure/closet/cardboard")
UNIQUE = ("/obj/machinery/rnd/production/techfab", "/obj/machinery/rnd/production/protolathe",
          "/obj/machinery/rnd/production/circuit_imprinter", "/obj/machinery/autolathe", "/obj/machinery/computer/rdconsole")


class Rule:
    def __init__(self, rid, date, words, why, check=None, enforced=""):
        self.id, self.date, self.words, self.why, self.check, self.enforced = rid, date, words, why, check, enforced


def _objs(sm, p):
    t = sm.m.get(p[0], p[1], sm.z)
    return t.objs if t else []


def _st(sm):
    if not hasattr(sm, "_st"):
        sm._st = set(sm.station_tiles())
    return sm._st


def _room(sm, p):
    r = sm.region.get(p)
    return r is not None and sm.regions[r].kind == "room"


# ---- checks: each returns a list of tiles where the rule is broken ----

def c_double_wall(sm):
    out = []
    st = _st(sm)
    for p in st:
        if not _room(sm, p):
            continue
        for dx, dy in ((1, 0), (0, 1)):
            a, b, c = (p[0] + dx, p[1] + dy), (p[0] + 2 * dx, p[1] + 2 * dy), (p[0] + 3 * dx, p[1] + 3 * dy)
            if sm.cls.get(a) == "W" and sm.cls.get(b) == "W" and c in st and _room(sm, c) and \
                    sm.region[c] != sm.region[p] and a not in sm.glass and b not in sm.glass:
                out.append(a)
    return out


def c_corner_join(sm):
    out = []
    st = _st(sm)
    for p, c in sm.cls.items():
        if c != "W":
            continue
        x, y = p
        for dx in (1, -1):
            q = (x + dx, y + 1)
            if sm.cls.get(q) == "W" and sm.cls.get((x + dx, y)) == "F" and sm.cls.get((x, y + 1)) == "F" and \
                    ((x + dx, y) in st or (x, y + 1) in st):
                out.append(p)
    return out


def c_airlock_line(sm):
    out = []
    for p, c in sm.cls.items():
        if c != "D" or not any(o.path.startswith("/obj/machinery/door/airlock") for o in _objs(sm, p)):
            continue
        if p not in _near_station(sm, p):
            continue
        ns = sm.cls.get((p[0], p[1] + 1)) in "WD" and sm.cls.get((p[0], p[1] - 1)) in "WD"
        ew = sm.cls.get((p[0] + 1, p[1])) in "WD" and sm.cls.get((p[0] - 1, p[1])) in "WD"
        if not ns and not ew:
            out.append(p)
    return out


def _near_station(sm, p):
    st = _st(sm)
    return {p} if any((p[0] + dx, p[1] + dy) in st for dx, dy in DIRS) else set()


def c_open_seam(sm):
    out = []
    for p, r in sm.region.items():
        if sm.regions[r].kind != "room":
            continue
        for dx, dy in ((1, 0), (0, 1)):
            r2 = sm.region.get((p[0] + dx, p[1] + dy))
            if r2 is not None and r2 != r and sm.regions[r2].kind == "room" and \
                    sm.regions[r2].group == sm.regions[r].group:
                out.append(p)
    return out


def c_decal_wall_line(sm):
    out = []
    for p, c in sm.cls.items():
        if c in "WD" and any(o.path.startswith("/obj/effect/turf_decal/tile") for o in _objs(sm, p)) and _near_station(sm, p):
            out.append(p)
    return out


def c_wall_face(sm):
    st = _st(sm)
    out = []
    for (p, s), v in sm.hung.items():
        if p in st and len(set(v)) >= 2 and not _sink_mirror(v):
            out.append(p)
    # both faces of one wall tile
    seen = Counter()
    for (p, s), v in sm.hung.items():
        if p in st:
            dx, dy = SIDE[s]
            seen[(p[0] + dx, p[1] + dy)] += 1
    out += [w for w, n in seen.items() if n >= 2 and sm.cls.get(w) == "W"]
    return out


def _sink_mirror(v):
    return all(x.startswith(("/obj/structure/sink", "/obj/structure/mirror")) for x in v)


def _tall_tiles(sm):
    for p in _st(sm):
        for o in _objs(sm, p):
            if o.path.startswith(TALL) and not o.path.startswith(LOOSE_OK) and not parse.corpus.mounted(o):
                yield p, o


def c_tall_on_glass(sm):
    out = []
    for p, o in _tall_tiles(sm):
        g = [q for q in ((p[0] + dx, p[1] + dy) for dx, dy in DIRS) if q in sm.glass]
        w = [q for q in ((p[0] + dx, p[1] + dy) for dx, dy in DIRS) if sm.cls.get(q) == "W" and q not in sm.glass]
        if g and not w:
            out.append(p)
    return out


def c_tall_loose(sm):
    out = []
    for p, o in _tall_tiles(sm):
        if not _room(sm, p) or o.path.startswith(("/obj/structure/bookcase", "/obj/machinery/rnd")):
            continue  # bookcases (37%) and R&D machines (19%) stand free on human maps; the ruling allows it
        if not any(sm.cls.get((p[0] + dx, p[1] + dy)) == "W" for dx, dy in DIRS):
            out.append(p)
    return out


def c_door_clear(sm):
    out = []
    for p, c in sm.cls.items():
        if c != "D" or not _near_station(sm, p):
            continue
        for dx, dy in DIRS:
            q = (p[0] + dx, p[1] + dy)
            if sm.cls.get(q) == "F" and q in sm.dense and sm.cls.get((p[0] - dx, p[1] - dy)) in ("F", "D"):
                out.append(q)
    return out


def c_squeeze(sm):
    """Diagonal squeeze inside a room: two free floor tiles touching only at a corner, both tiles between blocked."""
    out = []
    blocked = lambda q: sm.cls.get(q) != "F" or q in sm.dense  # noqa: E731
    for p in _st(sm):
        if blocked(p) or not _room(sm, p):
            continue
        for dx in (1, -1):
            q = (p[0] + dx, p[1] + 1)
            if q in _st(sm) and not blocked(q) and sm.region.get(q) == sm.region.get(p) and \
                    blocked((p[0] + dx, p[1])) and blocked((p[0], p[1] + 1)) and \
                    ((p[0] + dx, p[1]) in sm.dense or (p[0], p[1] + 1) in sm.dense):
                out.append(p)
    return out


def c_maint_vents(sm):
    out = []
    for r in sm.regions.values():
        if r.kind != "maint" or r.area.startswith("/area/maintenance/") and "/solars" in r.area:
            continue
        v = s = 0
        for p in r.tiles:
            for o in _objs(sm, p):
                if o.path.startswith("/obj/machinery/atmospherics/components/unary/vent_pump"):
                    v += 1
                elif o.path.startswith("/obj/machinery/atmospherics/components/unary/vent_scrubber"):
                    s += 1
        # rooms (not corridors): a maint region is a room when its box is not thin
        x0, y0, x1, y1 = sm.bbox(r.tiles)
        if min(x1 - x0, y1 - y0) < 3 or len(r.tiles) < 0.6 * (x1 - x0 + 1) * (y1 - y0 + 1):
            continue  # corridors (thin or sprawling): one vent per ~90 tiles is allowed there
        if (len(r.tiles) < 40 and (v or s)) or v > 1 or s > 1:
            out.append(sorted(r.tiles)[len(r.tiles) // 2])
    return out


def c_morgue(sm):
    out = []
    for p in _st(sm):
        for o in _objs(sm, p):
            if o.path.startswith("/obj/structure/bodycontainer/morgue"):
                d = o.num("dir", 4)
                dx, dy = SIDE.get(d, (1, 0))
                q = (p[0] + dx, p[1] + dy)
                if sm.cls.get(q) != "F" or q in sm.dense:
                    out.append(p)
    return out


def c_unique_machine(sm):
    out = []
    for r in sm.regions.values():
        if r.kind != "room":
            continue
        c = Counter()
        for p in r.tiles:
            for o in _objs(sm, p):
                for u in UNIQUE:
                    if o.path.startswith(u):
                        c[u] += 1
                        if c[u] == 2:
                            out.append(p)
    return out


RULES = [
    Rule("R01", "2026-11-14", "Is that layout practical and pretty?",
         "a vendor diagonal to a tray closed the aisle mouth; you can't step diagonally between two blocked tiles",
         c_squeeze, "check.py squeeze; furnisher rejects"),
    Rule("R02", "2026-11-14", "a table with a surgical saw in front of a sleeper (horrible)",
         "the tile a sleeper/dispenser/console faces is its use tile and stays free", None,
         "orient.keep_front_clear; check.py front"),
    Rule("R03", "2026-11-14", "techfab beside the CMO office window ... should be in the supplies room",
         "lathes and supply machines go in the storage room; one of each machine per room", c_unique_machine,
         "furnish.unique_machines"),
    Rule("R04", "2026-11-14", "look at surrounding areas and walls + airlocks and glass",
         "every airlock keeps both sides of its passage clear", c_door_clear, "check.py doorways"),
    Rule("R05", "2026-11-14", "the vending machine up against the glass looks bad",
         "tall furniture never backs onto glass with no wall", c_tall_on_glass, "check.py tall-on-glass"),
    Rule("R06", "2026-11-14", "(vendors standing loose in a room)",
         "vendors/lockers/suit storage/tanks/lathes stand against a wall", c_tall_loose, "check.py loose furniture"),
    Rule("R07", "2026-11-15", "still double walls",
         "rooms run up to the existing wall; never floor-wall-wall-floor", c_double_wall, "check.py; builder.thin_walls"),
    Rule("R08", "2026-11-15", "nanite lab open straight into the launch room",
         "two rooms never meet floor to floor without wall/door/glass", c_open_seam, "check.py OPEN_SEAMS"),
    Rule("R09", "2026-11-15", "launch room airlock with floor beside it",
         "every airlock sits in a wall line", c_airlock_line, "check.py airlock line"),
    Rule("R10", "2026-11-15", "walls should connect at each other, never diagonal spacing",
         "no corner-only wall joins; never patch with a glass tile", c_corner_join, "check.py; builder.close_diagonals"),
    Rule("R11", "2026-11-15", "connected tables should never float into a room if they start on a wall",
         "wall-run tables wrap around, never jut out", None, "check.py wall-run tables; furnisher"),
    Rule("R12", "2026-11-15", "(xeno pen carved over the station's space notch)",
         "never carve a room over space notches", None, "shell outline"),
    Rule("R13", "2026-11-15", "Read what a full room does, what a full entire department does",
         "rooms are workflows: inputs, outputs, stand spots, links, open work areas", None,
         "assets/*.py kits (authored)"),
    Rule("R14", "2026-11-16", "make sure the body holders open correctly and make sense",
         "morgue trays face east (one-facing icon), the tray tile free, in N-S columns", c_morgue, "assets/medical.py"),
    Rule("R15", "2026-11-16", "(no decal in the wall line)",
         "no floor decal on door or wall tiles", c_decal_wall_line, "dress.py; check.py"),
    Rule("R16", "2026-11-16", "the light tube, the urinal toilet and the mirror all fight for a spot",
         "one wall piece per wall face; never pieces on both faces of one wall tile", c_wall_face,
         "to_dmm.one_per_wall_face"),
    Rule("R17", "2026-11-16", "smaller maint rooms shouldn't have scrubbers/vents, bigger ones only 1 of each",
         "maint room <40 tiles: 0+0; else at most 1+1", c_maint_vents, "to_dmm.vent_count"),
    Rule("R18", "2026-11-16", "chevrons ... only where they make sense",
         "hazard stripes only round hazards (heavy machines, conveyors, fabs, cryo)", None, "floors.py"),
    Rule("R19", "2026-11-16", "few vents, symmetric lines/boxes; one pair per ~10x10",
         "vents and scrubbers laid in lines and boxes", None, "to_dmm vents"),
    Rule("R20", "2026-11-16", "no loose MULEs",
         "Meta-style MULE parking row (4 stalls, 2 MULEs)", None, "to_dmm cargo"),
    Rule("R21", "2026-11-16", "our departments have a boxy look",
         "departments branch out; odd-shaped rooms, wings (fingerprint odd_share, dept_corners)", None,
         "grow.py; fingerprint"),
    Rule("R22", "2026-11-16", "a lot of repeating windows, need some hull variation",
         "window patterns vary per hull run", None, "to_dmm GLAZE"),
    Rule("R23", "2026-11-15", "purple dept trim fought the hazard stripes",
         "no dept trim on tiles with hazard decals", None, "dress.py"),
    Rule("R24", "2026-11-14", "two mirrored operating theatres ... lmao",
         "one theatre + real storage in Medbay", None, "assets/medical.py"),
    Rule("R25", "2026-11-08", "secure rooms isolated (AI core, vault, upload, armory)",
         "secure rooms only through a foyer; never touch maint or a hall door", None, "perihelion render.py only"),
    Rule("R26", "2026-11-08", "departments not opening onto halls everyone shares",
         "department rooms open onto their own hall, behind a lobby or desk", None, "grow.py (partly)"),
]


def run(names, only=None):
    res = {}
    for n in names:
        sm = parse.load(n)
        N = max(1, len(_st(sm)))
        res[sm.name] = {}
        for r in RULES:
            if r.check is None or (only and r.id != only):
                continue
            hits = r.check(sm)
            res[sm.name][r.id] = (len(hits), len(hits) * 1000.0 / N, hits)
    return res


def crops(res, out_dir, per_map=3, R=7):
    """One sheet per rule: crops round the first hits on each map, the hit tile boxed in red."""
    from PIL import ImageDraw, Image
    from forge import gallery
    os.makedirs(out_dir, exist_ok=True)
    paths = {parse.load(n).name: parse.map_path(n) for n in res}
    full = gallery.full_renders(sorted(set(paths.values())))
    imgs = {m: Image.open(full[p]).convert("RGB") for m, p in paths.items()}
    for r in RULES:
        if r.check is None:
            continue
        rows = []
        for human in (True, False):
            ims, caps = [], []
            for m, v in res.items():
                if (m in parse.MAPS) != human or r.id not in v:
                    continue
                for (x, y) in v[r.id][2][:per_map]:
                    sm = parse.load(m)
                    c = gallery.crop(imgs[m], sm.m.maxy, (x - R, y - R, x + R, y + R)).copy()
                    d = ImageDraw.Draw(c)
                    k = gallery.PX
                    d.rectangle([R * k - 1, R * k - 1, (R + 1) * k, (R + 1) * k], outline=(255, 40, 40), width=2)
                    ims.append(c)
                    caps.append("%s %d,%d" % (m.replace("gen_", "")[:16], x, y))
            if ims:
                rows.append((ims, caps))
        if rows:
            gallery._rows_sheet(rows, os.path.join(out_dir, "%s.png" % r.id),
                                "%s  %s  (human maps top, generated bottom)" % (r.id, r.why[:110]), H=220)
    print("rule crops in", out_dir)


def main(args):
    import glob
    if "--crops" in args:
        args = [a for a in args if a != "--crops"]
        res = run(list(parse.MAPS) + (args or sorted(glob.glob(os.path.join(parse.ROOT, "_maps", "map_files", "Generated", "*.dmm")))))
        crops(res, os.path.join(parse.ROOT, "data", "previews", "mapforge", "rules"))
        return
    if "--list" in args:
        for r in RULES:
            print("%s %s  %s\n     rule: %s\n     map check: %s   builder: %s" % (
                r.id, r.date, r.words, r.why, "yes" if r.check else "NO", r.enforced))
        return
    spots = None
    if "--spots" in args:
        i = args.index("--spots")
        spots = args[i + 1]
        args = args[:i] + args[i + 2:]
    gens = args or sorted(glob.glob(os.path.join(parse.ROOT, "_maps", "map_files", "Generated", "*.dmm")))
    names = ([] if args else list(parse.MAPS)) + gens
    res = run(names, spots)
    if spots:
        for m, v in res.items():
            print(m, spots, v[spots][0], v[spots][2][:40])
        return
    ids = [r.id for r in RULES if r.check]
    w = 13
    print("hits per 1000 floor tiles (raw count)")
    print("%-22s" % "map" + "".join("%*s" % (w, i) for i in ids))
    for m, v in res.items():
        print("%-22s" % m[:22] + "".join("%*s" % (w, "%.2f (%d)" % (v[i][1], v[i][0])) for i in ids))
    nochk = [r.id for r in RULES if not r.check]
    print("\n%d rulings, %d with a map check; builder-only: %s" % (len(RULES), len(ids), " ".join(nochk)))


if __name__ == "__main__":
    main(sys.argv[1:])
