"""Science and Cargo on the stock maps (forge.corpus.MAPS) and on a generated map: the facts the spec's rules count.

    python stock_study.py                 # the 8 stock maps -> stock_study.json + a table on stdout
    python stock_study.py <dmm> [...]     # any maps (a generated one)

Per map: room areas present and their tile counts, joins between areas (doors, windoor desks, windows), xenobiology
(pens, cameras, kill room freezer, console/recycler/processor/fridge, slimes, cube boxes, bins/outlets, windoors,
blast doors), toxins (chamber area and its machines, vent blast door on space, ignition, mass driver and its button,
test range distance, doppler, freezer, portable pump/scrubber, canisters, tank dispenser), R&D and robotics desks,
mech bay, cargo (supply dock beside the bay, conveyors, flaps, office desk to the hall, consoles, ORM, mail chute,
mining dock and its port), checkpoints.
"""
import json
import os
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
MF = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, MF)
sys.path.insert(0, os.path.join(MF, "gen", "learn"))
from forge import corpus as CO, dmm  # noqa: E402

ROOT = os.path.abspath(os.path.join(MF, "..", ".."))
N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
SCI = ("/area/science", "/area/crew_quarters/heads/hor", "/area/security/checkpoint/science")
CARGO = ("/area/quartermaster", "/area/security/checkpoint/supply", "/area/security/checkpoint/customs")


def _open(t):
    return t is not None and t.tpath.startswith("/turf/open") and not t.tpath.startswith("/turf/open/space") \
        and not CO.solid(t)


def _space(t):
    return t is not None and t.tpath.startswith("/turf/open/space")


def _door(t):
    return t is not None and any(o.path.startswith("/obj/machinery/door") and not o.path.startswith(
        "/obj/machinery/door/firedoor") for o in t.objs)


def mine(m):
    area_tiles = defaultdict(set)
    objs = defaultdict(list)            # path prefix bucket -> [(x, y, area, atom)]
    for (x, y, z), t in m.tiles.items():
        if z != 1:
            continue
        if t.apath:
            area_tiles[t.apath].add((x, y))
        for o in t.objs:
            objs[o.path].append((x, y, t.apath, o))
    return area_tiles, objs


def find(objs, prefix, area=None):
    out = []
    for p, lst in objs.items():
        if p == prefix or p.startswith(prefix + "/") or p.startswith(prefix + "{"):
            for x, y, a, o in lst:
                if area is None or a == area or a.startswith(area + "/"):
                    out.append((x, y, a, o))
    return out


def joins(m, prefixes):
    """Area pairs joined by a door, a windoor desk or a window, where one side is in prefixes."""
    out = Counter()
    for (x, y, z), t in m.tiles.items():
        if z != 1:
            continue
        kind = None
        if t.has("/obj/machinery/door/window") and t.has("/obj/structure/table"):
            kind = "desk"
        elif _door(t) and not t.has("/obj/machinery/door/poddoor"):
            kind = "door"
        elif CO.solid(t) and not t.tpath.startswith("/turf/closed"):
            kind = "window"
        elif t.has("/obj/machinery/door/poddoor") and t.has("/obj/structure/table"):
            kind = "hatch"
        if not kind:
            continue
        for ax in ((1, 0), (0, 1)):
            a, b = m.get(x + ax[0], y + ax[1]), m.get(x - ax[0], y - ax[1])
            if _open(a) and _open(b) and a.apath != b.apath:
                pa, pb = sorted((a.apath, b.apath))
                if any(pa.startswith(p) or pb.startswith(p) for p in prefixes):
                    out[(pa, pb, kind)] += 1
    return out


def near(lst_a, lst_b):
    best = None
    for xa, ya, _, _ in lst_a:
        for xb, yb, _, _ in lst_b:
            d = abs(xa - xb) + abs(ya - yb)
            if best is None or d < best:
                best = d
    return best


def port_rect(o, x, y):
    """Tiles of a stationary docking port's rect (2020 tg: dir is the port's facing; width along, dwidth offset)."""
    d = int(o.get("dir", "2"))
    w, dw, h = int(o.get("width", "1")), int(o.get("dwidth", "0")), int(o.get("height", "1"))
    # rect in the port's own frame: x from -dwidth to width-dwidth-1, y from 0 to height-1, rotated by dir (NORTH = 1)
    pts = set()
    for i in range(-dw, w - dw):
        for j in range(0, h):
            if d == 1:
                pts.add((x + i, y + j))
            elif d == 2:
                pts.add((x - i, y - j))
            elif d == 4:
                pts.add((x + j, y - i))
            else:
                pts.add((x - j, y + i))
    return pts


def pens(m, xeno_tiles):
    """Pens: floor pieces of xenobiology entered through a windoor (or a door) from the rest of it, 4-30 tiles."""
    floor = {p for p in xeno_tiles if _open(m.get(*p)) and not _door(m.get(*p))}
    left, comps = set(floor), []
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
        comps.append(comp)
    comps.sort(key=len, reverse=True)
    out = []
    for c in comps[1:]:
        if 4 <= len(c) <= 30:
            out.append(c)
    return comps[0] if comps else set(), out


def science(m, at, objs, sp):
    r = {}
    xeno = at.get("/area/science/xenobiology", set())
    r["xeno_tiles"] = len(xeno)
    if xeno:
        main, pp = pens(m, xeno)
        r["xeno_pens"] = len(pp)
        slimes = find(objs, "/mob/living/simple_animal/slime", "/area/science/xenobiology")
        r["slimes"] = len(slimes)
        in_pen = sum(1 for x, y, _, _ in slimes if any((x, y) in p for p in pp))
        r["slimes_in_pens"] = in_pen
        cams = find(objs, "/obj/machinery/camera", "/area/science/xenobiology")
        r["xeno_cameras"] = len(cams)
        r["pens_with_camera"] = sum(1 for p in pp if any((x, y) in p for x, y, _, _ in cams))
        r["xeno_windoors"] = len(find(objs, "/obj/machinery/door/window", "/area/science/xenobiology"))
        r["xeno_blastdoors"] = len(find(objs, "/obj/machinery/door/poddoor", "/area/science/xenobiology"))
        r["xeno_door_buttons"] = len(find(objs, "/obj/machinery/button/door", "/area/science/xenobiology"))
        pen_doors = Counter()
        for p in pp:
            for (x, y) in p:
                for dx, dy in N4:
                    t = m.get(x + dx, y + dy)
                    if _door(t):
                        pen_doors["windoor" if t.has("/obj/machinery/door/window") else "airlock"] += 1
        r["pen_door_kinds"] = dict(pen_doors)
        r["xeno_bins"] = len(find(objs, "/obj/machinery/disposal/bin", "/area/science/xenobiology"))
        r["xeno_outlets"] = len(find(objs, "/obj/structure/disposaloutlet", "/area/science/xenobiology"))
        fr = find(objs, "/obj/machinery/atmospherics/components/unary/thermomachine/freezer", "/area/science/xenobiology")
        r["xeno_freezer"] = len(fr)
        con = find(objs, "/obj/machinery/computer/camera_advanced/xenobio")
        r["xeno_consoles"] = len(con)
        r["console_in_xeno"] = sum(1 for c in con if c[2] == "/area/science/xenobiology")
        rec = find(objs, "/obj/machinery/monkey_recycler")
        r["recycler_same_area"] = any(c[2] == x[2] for c in con for x in rec)
        pro = find(objs, "/obj/machinery/processor/slime")
        fridge = find(objs, "/obj/machinery/smartfridge/extract")
        r["processor"] = len(pro)
        r["fridge"] = len(fridge)
        r["processor_fridge_dist"] = near(pro, fridge)
        r["console_processor_dist"] = near(con, pro)
        r["cube_boxes"] = len(find(objs, "/obj/item/storage/box/monkeycubes", "/area/science/xenobiology"))
        r["xeno_showers"] = len(find(objs, "/obj/machinery/shower", "/area/science/xenobiology"))
        r["xeno_l3"] = len(find(objs, "/obj/structure/closet/l3closet", "/area/science/xenobiology"))
        r["xeno_shieldgen"] = len(find(objs, "/obj/machinery/power/shieldwallgen/xenobiologyaccess"))
        # kill room: the piece the freezer's vents feed (a pen-sized piece with a vent/injector and no slime), or
        # the piece holding the freezer
        r["kill_room"] = None
        for p in pp:
            vents = [o for (x, y) in p for o in m.get(x, y).objs if o.path.startswith((
                "/obj/machinery/atmospherics/components/unary/outlet_injector",
                "/obj/machinery/atmospherics/components/unary/vent_pump"))]
            if vents and not any((x, y) in p for x, y, _, _ in slimes) and len(p) <= 16:
                r["kill_room"] = len(p)
        # where the xeno lab sits: doors from it to non-xeno areas
        outs = Counter()
        for (x, y) in xeno:
            t = m.get(x, y)
            if not _door(t):
                continue
            for dx, dy in N4:
                n = m.get(x + dx, y + dy)
                if _open(n) and n.apath != "/area/science/xenobiology" and not _door(n):
                    outs[n.apath] += 1
        r["xeno_exits"] = dict(outs)
    # toxins
    ch = at.get("/area/science/mixing/chamber", set())
    r["chamber_tiles"] = len(ch)
    chamber_like = ch
    if not ch:
        # older maps: the chamber is a piece of mixing behind a blast door to space with an injector
        inj = find(objs, "/obj/machinery/atmospherics/components/unary/outlet_injector", "/area/science/mixing")
        chamber_like = {(x, y) for x, y, _, _ in inj}
    r["chamber_injector"] = len(find(objs, "/obj/machinery/atmospherics/components/unary/outlet_injector", "/area/science/mixing"))
    r["chamber_igniter"] = len(find(objs, "/obj/machinery/igniter", "/area/science/mixing")) + \
        len(find(objs, "/obj/machinery/sparker", "/area/science/mixing"))
    vent_doors = [(x, y, a, o) for x, y, a, o in find(objs, "/obj/machinery/door/poddoor")
                  if "toxmix" in (o.get("id") or "") or "mix" in (o.get("id") or "")]
    r["vent_blastdoors"] = len(vent_doors)
    r["vent_on_space"] = sum(1 for x, y, a, o in vent_doors if any(_space(m.get(x + dx, y + dy)) for dx, dy in N4)
                             or any(_space(m.get(x + 2 * dx, y + 2 * dy)) for dx, dy in N4))
    r["ignition_button"] = len([1 for x, y, a, o in find(objs, "/obj/machinery/button/ignition") if a.startswith("/area/science")])
    drv = [(x, y, a, o) for x, y, a, o in find(objs, "/obj/machinery/mass_driver") if "toxin" in (o.get("id") or "")]
    r["toxins_driver"] = len(drv)
    r["driver_area"] = drv[0][2] if drv else None
    r["driver_button"] = len([1 for x, y, a, o in find(objs, "/obj/machinery/button/massdriver") if "toxin" in (o.get("id") or "")])
    rng = at.get("/area/science/test_area", set())
    if drv and rng:
        r["driver_to_range"] = min(abs(drv[0][0] - x) + abs(drv[0][1] - y) for x, y in rng)
    r["doppler_area"] = sorted({a for x, y, a, o in find(objs, "/obj/machinery/doppler_array")})
    r["mixing_freezer"] = len(find(objs, "/obj/machinery/atmospherics/components/unary/thermomachine", "/area/science/mixing"))
    r["mixing_pump"] = len(find(objs, "/obj/machinery/portable_atmospherics/pump", "/area/science/mixing"))
    r["mixing_scrubber"] = len([1 for x, y, a, o in find(objs, "/obj/machinery/portable_atmospherics/scrubber", "/area/science/mixing")
                                if o.path == "/obj/machinery/portable_atmospherics/scrubber"])
    r["tank_dispenser"] = len(find(objs, "/obj/structure/tank_dispenser", "/area/science"))
    cans = Counter(o.path.split("/")[-1] for x, y, a, o in find(objs, "/obj/machinery/portable_atmospherics/canister", "/area/science"))
    r["sci_canisters"] = dict(cans)
    mix = at.get("/area/science/mixing", set())
    r["mixing_tiles"] = len(mix)
    r["mixing_on_hull"] = any(_space(m.get(x + dx, y + dy)) or _space(m.get(x + 2 * dx, y + 2 * dy))
                              for (x, y) in mix | ch for dx, dy in N4)
    # desks
    for area, key in (("/area/science/lab", "rnd_desk"), ("/area/science/robotics/lab", "robo_desk")):
        tiles = at.get(area, set())
        desks = Counter()
        for (x, y) in tiles:
            t = m.get(x, y)
            if t.has("/obj/machinery/door/window") and t.has("/obj/structure/table"):
                for dx, dy in N4:
                    n = m.get(x + dx, y + dy)
                    if _open(n) and n.apath != area and not n.has("/obj/structure/table"):
                        desks[n.apath] += 1
        # desks whose tile is in the outer area
        for (x, y, z), t in m.tiles.items():
            if t.apath != area and t.has("/obj/machinery/door/window") and t.has("/obj/structure/table"):
                if any(m.get(x + dx, y + dy) is not None and m.get(x + dx, y + dy).apath == area and _open(m.get(x + dx, y + dy))
                       for dx, dy in N4):
                    desks[t.apath] += 1
        r[key] = dict(desks)
    # robotics / mech bay
    r["exofab"] = len(find(objs, "/obj/machinery/mecha_part_fabricator"))
    r["exofab_area"] = sorted({a for x, y, a, o in find(objs, "/obj/machinery/mecha_part_fabricator")})
    r["optable_robotics"] = len(find(objs, "/obj/structure/table/optable", "/area/science/robotics"))
    r["mech_ports"] = len(find(objs, "/obj/machinery/mech_bay_recharge_port"))
    r["mech_port_area"] = sorted({a for x, y, a, o in find(objs, "/obj/machinery/mech_bay_recharge_port")})
    r["borg_chargers_sci"] = len(find(objs, "/obj/machinery/recharge_station", "/area/science"))
    # explab
    exp = find(objs, "/obj/machinery/rnd/experimentor")
    r["experimentor_area"] = sorted({a for x, y, a, o in exp})
    r["exp_console_dist"] = near(exp, find(objs, "/obj/machinery/computer/rdconsole/experiment"))
    # server
    r["servers"] = len(find(objs, "/obj/machinery/rnd/server"))
    r["server_area"] = sorted({a for x, y, a, o in find(objs, "/obj/machinery/rnd/server")})
    r["server_control_area"] = sorted({a for x, y, a, o in find(objs, "/obj/machinery/computer/rdservercontrol")})
    r["server_freezer"] = len(find(objs, "/obj/machinery/atmospherics/components/unary/thermomachine", "/area/science/server"))
    # safety
    for k, p in (("sci_showers", "/obj/machinery/shower"), ("sci_fireclosets", "/obj/structure/closet/firecloset"),
                 ("sci_emclosets", "/obj/structure/closet/emcloset"), ("sci_extinguisher_cab", "/obj/structure/extinguisher_cabinet"),
                 ("sci_l3", "/obj/structure/closet/l3closet"), ("sci_rad", "/obj/structure/closet/radiation"),
                 ("sci_bombcloset", "/obj/structure/closet/bombcloset"), ("sci_cameras", "/obj/machinery/camera")):
        r[k] = len(find(objs, p, "/area/science"))
    r["shower_area"] = sorted(Counter(a for x, y, a, o in find(objs, "/obj/machinery/shower", "/area/science")).items())
    return r


def cargo(m, at, objs, sp):
    r = {}
    bay = at.get("/area/quartermaster/storage", set())
    r["bay_tiles"] = len(bay)
    ports = {}
    for x, y, a, o in find(objs, "/obj/docking_port/stationary"):
        pid = (o.get("id") or "").strip('"')
        if pid in ("supply_home", "mining_home"):
            ports[pid] = port_rect(o, x, y)
    def dist_to(area_prefixes, rect):
        best = None
        for a, tiles in at.items():
            if not any(a == p or a.startswith(p + "/") for p in area_prefixes):
                continue
            for (x, y) in tiles:
                if not _open(m.get(x, y)):
                    continue
                for (u, v) in rect:
                    d = abs(x - u) + abs(y - v)
                    if best is None or d < best:
                        best = d
        return best
    if "supply_home" in ports:
        r["supply_to_bay"] = dist_to(("/area/quartermaster/storage",), ports["supply_home"])
        # which area the supply dock's airlocks open into
        rect = ports["supply_home"]
        ring = {(x + dx, y + dy) for (x, y) in rect for dx, dy in N4} - rect
        open_into = Counter()
        for (x, y) in ring:
            t = m.get(x, y)
            if _door(t) or t is not None and t.has("/obj/structure/plasticflaps"):
                for dx, dy in N4:
                    n = m.get(x + dx, y + dy)
                    if _open(n) and (x + dx, y + dy) not in rect and not _door(n):
                        open_into[n.apath] += 1
        r["supply_opens_into"] = dict(open_into)
    if "mining_home" in ports:
        r["mining_to_dock"] = dist_to(("/area/quartermaster/miningdock", "/area/quartermaster/miningoffice",
                                       "/area/mine"), ports["mining_home"])
        rect = ports["mining_home"]
        ring = {(x + dx, y + dy) for (x, y) in rect for dx, dy in N4} - rect
        open_into = Counter()
        for (x, y) in ring:
            t = m.get(x, y)
            if _door(t):
                for dx, dy in N4:
                    n = m.get(x + dx, y + dy)
                    if _open(n) and (x + dx, y + dy) not in rect and not _door(n):
                        open_into[n.apath] += 1
        r["mining_opens_into"] = dict(open_into)
    conv = find(objs, "/obj/machinery/conveyor")
    r["conveyors"] = Counter(a for x, y, a, o in conv if not o.path.startswith("/obj/machinery/conveyor_switch"))
    r["conveyors"] = dict(r["conveyors"])
    r["flaps"] = dict(Counter(a for x, y, a, o in find(objs, "/obj/structure/plasticflaps")
                              if a.startswith(("/area/quartermaster", "/area/shuttle/supply"))))
    r["conveyor_switch"] = dict(Counter(a for x, y, a, o in find(objs, "/obj/machinery/conveyor_switch") if a.startswith("/area/quartermaster")))
    for k, p in (("cargo_console", "/obj/machinery/computer/cargo"), ("ore_redemption", "/obj/machinery/mineral/ore_redemption"),
                 ("mining_vendor", "/obj/machinery/mineral/equipment_vendor"), ("miner_lockers", "/obj/structure/closet/secure_closet/miner"),
                 ("qm_locker", "/obj/structure/closet/secure_closet/quartermaster"), ("autolathe", "/obj/machinery/autolathe"),
                 ("delivery_chute", "/obj/machinery/disposal/deliveryChute"), ("bounty", "/obj/machinery/computer/bounty"),
                 ("mining_console", "/obj/machinery/computer/shuttle/mining"), ("tagger", "/obj/item/destTagger"),
                 ("wrap", "/obj/item/stack/packageWrap"), ("stacker", "/obj/machinery/mineral/stacking_machine"),
                 ("photocopier", "/obj/machinery/photocopier"), ("crates", "/obj/structure/closet/crate"),
                 ("cargo_cameras", "/obj/machinery/camera"), ("firecloset", "/obj/structure/closet/firecloset"),
                 ("emcloset", "/obj/structure/closet/emcloset"), ("extinguisher_cab", "/obj/structure/extinguisher_cabinet"),
                 ("mulebot", "/mob/living/simple_animal/bot/mulebot"), ("navbeacon", "/obj/machinery/navbeacon"),
                 ("cargo_vendor", "/obj/machinery/vending/wardrobe/cargo_wardrobe"), ("requests", "/obj/machinery/requests_console")):
        r[k] = dict(Counter(a for x, y, a, o in find(objs, p) if a.startswith(("/area/quartermaster", "/area/security/checkpoint/supply"))))
    r["ore_redemption_any"] = sorted({a for x, y, a, o in find(objs, "/obj/machinery/mineral/ore_redemption")})
    # office front: desk or door onto a hall
    office = at.get("/area/quartermaster/office", set())
    fronts = Counter()
    for (x, y) in office:
        for dx, dy in N4:
            w = (x + dx, y + dy)
            tw = m.get(*w)
            if tw is None:
                continue
            if tw.has("/obj/machinery/door/window") and tw.has("/obj/structure/table") or _door(tw):
                for ex, ey in N4:
                    n = m.get(w[0] + ex, w[1] + ey)
                    if _open(n) and n.apath.startswith("/area/hallway"):
                        fronts["desk" if tw.has("/obj/structure/table") else "door"] += 1
            if tw.has("/obj/machinery/door/window") and tw.has("/obj/structure/table") and tw.apath == "/area/quartermaster/office":
                pass
    # desks inside the office's own tiles facing out
    for (x, y) in office:
        t = m.get(x, y)
        if t.has("/obj/structure/table") and t.has("/obj/machinery/door/window"):
            for dx, dy in N4:
                n = m.get(x + dx, y + dy)
                if _open(n) and n.apath != "/area/quartermaster/office":
                    fronts["desk_in:" + n.apath.split("/")[2]] += 1
    r["office_fronts"] = dict(fronts)
    for a in ("/area/quartermaster/office", "/area/quartermaster/storage", "/area/quartermaster/sorting",
              "/area/quartermaster/warehouse", "/area/quartermaster/qm", "/area/quartermaster/miningdock",
              "/area/quartermaster/miningoffice", "/area/quartermaster", "/area/security/checkpoint/supply"):
        r["tiles:" + a.replace("/area/", "")] = len([p for p in at.get(a, set()) if _open(m.get(*p))])
    return r


def study(path):
    m = dmm.read(path)
    at, objs = mine(m)
    sp = None
    out = {"science": science(m, at, objs, sp), "cargo": cargo(m, at, objs, sp)}
    out["sci_areas"] = {a: len([p for p in t if _open(m.get(*p))]) for a, t in at.items() if a.startswith(SCI)}
    out["joins"] = ["%s | %s | %s x%d" % (a, b, k, n) for (a, b, k), n in sorted(joins(m, SCI + CARGO).items())]
    return out


def main():
    paths = sys.argv[1:] or [os.path.join(ROOT, "_maps", "map_files", p) for p in CO.MAPS]
    res = {}
    for p in paths:
        name = os.path.splitext(os.path.basename(p))[0]
        res[name] = study(p)
        print("== %s" % name)
        for sec in ("science", "cargo"):
            for k, v in res[name][sec].items():
                print("  %-22s %s" % (k, v))
        print("  areas:", res[name]["sci_areas"])
    out = os.path.join(HERE, "stock_study.json" if not sys.argv[1:] else "map_study.json")
    with open(out, "w", newline="") as f:
        json.dump(res, f, indent=1, default=str)
    print("->", out)


if __name__ == "__main__":
    main()
