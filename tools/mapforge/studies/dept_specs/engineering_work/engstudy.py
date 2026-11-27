"""Engineering on the stock maps (and on ours), room by room: the department's rooms cut at walls, doors and area
changes, each with its kit, its doors (style, name, access, what's beyond), the glass it looks through, and walking
distances that matter to engineers (engine door to the radiation closets, showers, fire gear; the department to its
solars, telecomms, the gravity generator).

    python tools/mapforge/studies/dept_specs/engineering_work/engstudy.py             # 8 stock maps, tables
    python tools/mapforge/studies/dept_specs/engineering_work/engstudy.py <dmm> ...   # any maps
    python ... engstudy.py --json out.json                                             # rooms as JSON too

Written for the engineering function spec (studies/dept_specs/engineering.md, 2026-11-26). The room cutting and the
families (FAM) are reused by gen/learn/fn_engineering.py's checks (it carries its own copy: gen files never import
from studies scratch).
"""
import argparse
import json
import os
import sys
from collections import Counter, defaultdict, deque

HERE = os.path.dirname(os.path.abspath(__file__))
MF = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, MF)
sys.path.insert(0, os.path.join(MF, "studies"))
from forge import corpus as CO, dmm  # noqa: E402
import stations as ST  # noqa: E402

ROOT = os.path.abspath(os.path.join(MF, "..", ".."))
N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))

# label -> path prefixes (most specific first where it matters)
FAM = [
    ("shower", ("/obj/machinery/shower",)),
    ("sink", ("/obj/structure/sink",)),
    ("rad_closet", ("/obj/structure/closet/radiation",)),
    ("fire_closet", ("/obj/structure/closet/firecloset",)),
    ("em_closet", ("/obj/structure/closet/emcloset",)),
    ("extinguisher", ("/obj/structure/extinguisher_cabinet",)),
    ("fireaxe", ("/obj/structure/fireaxecabinet",)),
    ("wallmed", ("/obj/machinery/vending/wallmed",)),
    ("firstaid", ("/obj/item/storage/firstaid",)),
    ("eng_locker", ("/obj/structure/closet/secure_closet/engineering_personal",)),
    ("elec_locker", ("/obj/structure/closet/secure_closet/engineering_electrical",)),
    ("weld_locker", ("/obj/structure/closet/secure_closet/engineering_welding",)),
    ("ce_locker", ("/obj/structure/closet/secure_closet/engineering_chief",)),
    ("atmos_locker", ("/obj/structure/closet/secure_closet/atmospherics",)),
    ("tool_closet", ("/obj/structure/closet/toolcloset",)),
    ("eng_crate", ("/obj/structure/closet/crate/engineering",)),
    ("sus_engine", ("/obj/machinery/suit_storage_unit/engine",)),
    ("sus_ce", ("/obj/machinery/suit_storage_unit/ce",)),
    ("sus_atmos", ("/obj/machinery/suit_storage_unit/atmos",)),
    ("sus_other", ("/obj/machinery/suit_storage_unit",)),
    ("engivend", ("/obj/machinery/vending/engivend",)),
    ("toolvend", ("/obj/machinery/vending/tool",)),
    ("engi_wardrobe", ("/obj/machinery/vending/wardrobe/engi_wardrobe",)),
    ("atmos_wardrobe", ("/obj/machinery/vending/wardrobe/atmos_wardrobe",)),
    ("fueltank", ("/obj/structure/reagent_dispensers/fueltank",)),
    ("watertank", ("/obj/structure/reagent_dispensers/watertank",)),
    ("tank_disp", ("/obj/structure/tank_dispenser",)),
    ("metal", ("/obj/item/stack/sheet/metal",)),
    ("glass", ("/obj/item/stack/sheet/glass", "/obj/item/stack/sheet/rglass")),
    ("plasteel", ("/obj/item/stack/sheet/plasteel",)),
    ("cable", ("/obj/item/stack/cable_coil",)),
    ("toolbox", ("/obj/item/storage/toolbox",)),
    ("belt", ("/obj/item/storage/belt/utility",)),
    ("meson", ("/obj/item/clothing/glasses/meson",)),
    ("igloves", ("/obj/item/clothing/gloves/color/yellow",)),
    ("geiger", ("/obj/item/geiger_counter",)),
    ("rpd", ("/obj/item/pipe_dispenser",)),
    ("rcd", ("/obj/item/construction/rcd",)),
    ("pipe_disp", ("/obj/machinery/pipedispenser",)),
    ("emitter", ("/obj/machinery/power/emitter",)),
    ("field_gen", ("/obj/machinery/field/generator",)),
    ("shieldgen", ("/obj/machinery/shieldgen", "/obj/machinery/power/shieldwallgen")),
    ("rad_collector", ("/obj/machinery/power/rad_collector",)),
    ("crystal", ("/obj/machinery/power/supermatter_crystal",)),
    ("port_gen", ("/obj/machinery/power/port_gen",)),
    ("smes", ("/obj/machinery/power/smes",)),
    ("terminal", ("/obj/machinery/power/terminal",)),
    ("grav", ("/obj/machinery/gravity_generator",)),
    ("power_mon", ("/obj/machinery/computer/monitor",)),
    ("station_alert", ("/obj/machinery/computer/station_alert",)),
    ("atmos_alert", ("/obj/machinery/computer/atmos_alert",)),
    ("apc_ctrl", ("/obj/machinery/computer/apc_control",)),
    ("atmos_ctrl", ("/obj/machinery/computer/atmos_control",)),
    ("eng_modcon", ("/obj/machinery/modular_computer/console/preset/engineering",)),
    ("telescreen", ("/obj/machinery/computer/security/telescreen",)),
    ("cam_console", ("/obj/machinery/computer/security",)),
    ("card_ce", ("/obj/machinery/computer/card/minor/ce",)),
    ("keycard", ("/obj/machinery/keycard_auth",)),
    ("req_console", ("/obj/machinery/requests_console",)),
    ("lathe_eng", ("/obj/machinery/rnd/production/protolathe/department/engineering",)),
    ("lathe", ("/obj/machinery/rnd/production/protolathe", "/obj/machinery/autolathe")),
    ("imprinter", ("/obj/machinery/rnd/production/circuit_imprinter",)),
    ("rdconsole", ("/obj/machinery/computer/rdconsole",)),
    ("cell_charger", ("/obj/machinery/cell_charger",)),
    ("recharger", ("/obj/machinery/recharger",)),
    ("canister", ("/obj/machinery/portable_atmospherics/canister",)),
    ("port_pump", ("/obj/machinery/portable_atmospherics/pump",)),
    ("port_scrub", ("/obj/machinery/portable_atmospherics/scrubber",)),
    ("thermo", ("/obj/machinery/atmospherics/components/unary/thermomachine",)),
    ("heater", ("/obj/machinery/space_heater",)),
    ("disposal", ("/obj/machinery/disposal/bin",)),
    ("board", ("/obj/item/circuitboard",)),
    ("rack", ("/obj/structure/rack",)),
    ("table", ("/obj/structure/table",)),
    ("chair", ("/obj/structure/chair",)),
    ("bed", ("/obj/structure/bed",)),
    ("coffee", ("/obj/machinery/vending/coffee", "/obj/machinery/vending/cola", "/obj/machinery/vending/snack",
                "/obj/machinery/vending/cigarette")),
    ("microwave", ("/obj/machinery/microwave",)),
    ("sign_rad", ("/obj/structure/sign/warning/radiation",)),
    ("sign_eng", ("/obj/structure/sign/departments/engineering",)),
    ("sign_fire", ("/obj/structure/sign/warning/fire",)),
    ("sign_other", ("/obj/structure/sign",)),
    ("holopad", ("/obj/machinery/holopad",)),
    ("camera", ("/obj/machinery/camera",)),
    ("blueprints", ("/obj/item/areaeditor/blueprints",)),
    ("hazvest", ("/obj/item/clothing/suit/hazardvest",)),
    ("hardhat", ("/obj/item/clothing/head/hardhat",)),
    ("radsuit", ("/obj/item/clothing/suit/radiation",)),
    ("firesuit", ("/obj/item/clothing/suit/fire",)),
    ("welder", ("/obj/item/weldingtool",)),
    ("weld_mask", ("/obj/item/clothing/head/welding",)),
    ("magboots", ("/obj/item/clothing/shoes/magboots",)),
    ("lightrepl", ("/obj/item/lightreplacer",)),
    ("lightbox", ("/obj/item/storage/box/lights",)),
    ("airlock_e", ("/obj/item/electronics",)),
    ("cell", ("/obj/item/stock_parts/cell",)),
    ("blast_btn", ("/obj/machinery/button/door",)),
    ("blast", ("/obj/machinery/door/poddoor",)),
    ("windoor", ("/obj/machinery/door/window",)),
    ("emergency_btn", ("/obj/machinery/button",)),
    ("tcomms", ("/obj/machinery/telecomms",)),
    ("solar_ctrl", ("/obj/machinery/power/solar_control",)),
    ("tracker", ("/obj/machinery/power/tracker",)),
    ("arcade", ("/obj/machinery/computer/arcade",)),
    ("plant", ("/obj/item/twohanded/required/kirbyplants",)),
    ("dresser", ("/obj/structure/dresser",)),
    ("mirror", ("/obj/structure/mirror",)),
    ("toilet", ("/obj/structure/toilet", "/obj/structure/urinal")),
]
DOORISH = ("/obj/machinery/door/airlock", "/obj/machinery/door/poddoor", "/obj/machinery/door/window",
           "/obj/machinery/door/password")


def fam(path):
    for lab, pres in FAM:
        if path.startswith(pres):
            return lab
    return None


def in_scope(area):
    if not area:
        return False
    if area.startswith("/area/security/checkpoint/engineering"):
        return True
    g = ST.group_of(area)
    return g in ("engineering", "atmos")


def is_door(t):
    return t is not None and any(o.path.startswith(DOORISH) for o in t.objs)


def is_floor(t):
    return t is not None and t.tpath.startswith("/turf/open") and not t.tpath.startswith("/turf/open/space") \
        and not CO.solid(t)


def segment(m, scope=in_scope, z=1):
    """Rooms: 4-connected floor tiles of one area, not doors, in scope. -> [dict(area, tiles)]"""
    seen = set()
    rooms = []
    for (x, y, zz), t in sorted(m.tiles.items()):
        if zz != z or (x, y) in seen or not is_floor(t) or is_door(t) or not scope(t.apath):
            continue
        a = t.apath
        comp, q = {(x, y)}, [(x, y)]
        seen.add((x, y))
        while q:
            p = q.pop()
            for dx, dy in N4:
                n = (p[0] + dx, p[1] + dy)
                if n in seen:
                    continue
                tn = m.get(*n)
                if is_floor(tn) and not is_door(tn) and tn.apath == a:
                    seen.add(n)
                    comp.add(n)
                    q.append(n)
        if len(comp) >= 2:
            rooms.append(dict(area=a, tiles=comp))
    return rooms


def door_atom(t):
    for pre in ("/obj/machinery/door/airlock", "/obj/machinery/door/window", "/obj/machinery/door/poddoor",
                "/obj/machinery/door/password"):
        for o in t.objs:
            if o.path.startswith(pre):
                return o
    return None


def kit(m, tiles, ring=True):
    """Counter of families on the room's tiles; wall mounts on the ring of walls round it count too."""
    c = Counter()
    for p in tiles:
        for o in m.get(*p).objs:
            f = fam(o.path)
            if f:
                c[f] += 1
    if ring:
        # wall-mounted things are mapped on the floor tile with a pixel offset, already counted; some maps put them
        # on the wall tile itself (rare); count those too
        walls = {(p[0] + dx, p[1] + dy) for p in tiles for dx, dy in N4} - set(tiles)
        for q in walls:
            t = m.get(*q)
            if t is None or not t.tpath.startswith("/turf/closed"):
                continue
            for o in t.objs:
                f = fam(o.path)
                if f and f.startswith(("sign", "extinguisher", "fireaxe", "wallmed", "telescreen", "keycard",
                                       "req_console", "blast_btn", "emergency_btn")):
                    c[f] += 1
    return c


def room_index(m, rooms):
    idx = {}
    for i, r in enumerate(rooms):
        for p in r["tiles"]:
            idx[p] = i
    return idx


def doors_of(m, room, idx, rooms):
    """[(x, y, path, name, access, beyond)] for door tiles next to the room; beyond: areas/rooms across."""
    out = []
    tiles = room["tiles"]
    seen = set()
    for p in tiles:
        for dx, dy in N4:
            d = (p[0] + dx, p[1] + dy)
            if d in seen:
                continue
            t = m.get(*d)
            if not is_door(t):
                continue
            seen.add(d)
            a = door_atom(t)
            # across: step on through the door (doors 1 deep; a double door line: 2)
            beyond = set()
            for k in (1, 2, 3):
                q = (d[0] + dx * k, d[1] + dy * k)
                tq = m.get(*q)
                if tq is None:
                    break
                if is_door(tq):
                    continue
                if is_floor(tq):
                    beyond.add(tq.apath)
                break
            acc = ";".join(v.strip('"') for k_, v in a.vars if k_ in ("req_access_txt", "req_one_access_txt")
                           and v.strip('"') not in ("", "0"))
            nm = (a.get("name") or "").strip('"')
            out.append(dict(x=d[0], y=d[1], path=a.path, name=nm, access=acc, beyond=sorted(beyond),
                            table=t.has("/obj/structure/table")))
    return out


def glass_of(m, room):
    """Areas seen through window tiles next to the room (control room over the crystal, a desk window)."""
    out = Counter()
    tiles = room["tiles"]
    for p in tiles:
        for dx, dy in N4:
            q = (p[0] + dx, p[1] + dy)
            t = m.get(*q)
            if t is None or not (t.has("/obj/effect/spawner/structure/window") or t.has("/obj/structure/window")
                                 or t.has("/obj/structure/grille")) or t.tpath.startswith("/turf/closed"):
                continue
            for k in (1, 2):
                r = (q[0] + dx * k, q[1] + dy * k)
                tr = m.get(*r)
                if tr is None:
                    break
                if is_floor(tr) and not tr.tpath.startswith("/turf/open/space"):
                    if tr.apath != room["area"] or r not in tiles:
                        out[tr.apath] += 1
                    break
                if tr.tpath.startswith("/turf/open/space"):
                    out["space"] += 1
                    break
    return out


def walk_dist(m, starts, z=1, limit=400):
    """BFS over walkable tiles (floor, doors of any access, no dense furniture) -> {(x,y): steps}."""
    from forge import function as FN
    dist = {}
    q = deque()
    for s in starts:
        dist[s] = 0
        q.append(s)
    while q:
        p = q.popleft()
        if dist[p] >= limit:
            continue
        for dx, dy in N4:
            n = (p[0] + dx, p[1] + dy)
            if n in dist:
                continue
            t = m.get(*n)
            if t is None or not t.tpath.startswith("/turf/open") or t.tpath.startswith("/turf/open/space"):
                continue
            if CO.solid(t) and not is_door(t):
                continue
            if not is_door(t) and any(FN.is_dense(o) for o in t.objs):
                # a dense piece: reachable to use (distance counted) but not walked through
                dist[n] = dist[p] + 1
                continue
            dist[n] = dist[p] + 1
            q.append(n)
    return dist


def tags(r):
    k = r["kit"]
    a = r["area"]
    t = []
    if "supermatter" in a or k["crystal"]:
        t.append("crystal")
    if k["rad_collector"] or (k["emitter"] and "supermatter" not in a and r["n"] > 60):
        t.append("engine_room")
    if a.endswith("/chief"):
        t.append("ce_office")
    if "storage/tech" in a:
        t.append("tech_storage")
    if "checkpoint" in a:
        t.append("checkpoint")
    if k["grav"]:
        t.append("grav")
    if k["smes"] >= 2 or "engine_smes" in a:
        t.append("smes")
    if k["eng_locker"] >= 2:
        t.append("lockers")
    if k["shower"]:
        t.append("showers")
    if k["sus_engine"] >= 2:
        t.append("suits")
    if k["engivend"] or k["toolvend"] or k["engi_wardrobe"]:
        t.append("vend")
    if (k["emitter"] and "engine_room" not in t) or k["field_gen"] or k["shieldgen"] >= 2:
        t.append("emitter_store")
    if k["station_alert"] or k["power_mon"] or k["eng_modcon"] or k["atmos_alert"]:
        t.append("consoles")
    if "break_room" in a or k["coffee"] or k["microwave"]:
        t.append("break")
    if "/atmos" in a:
        t.append("atmos")
    if k["metal"] or k["glass"]:
        t.append("sheets")
    if k["windoor"]:
        t.append("desk")
    return t


def study(path, label=None):
    m = dmm.read(path)
    rooms = segment(m)
    idx = room_index(m, rooms)
    for r in rooms:
        r["n"] = len(r["tiles"])
        xs, ys = [p[0] for p in r["tiles"]], [p[1] for p in r["tiles"]]
        r["box"] = (min(xs), min(ys), max(xs), max(ys))
        r["kit"] = kit(m, r["tiles"])
        r["doors"] = doors_of(m, r, idx, rooms)
        r["glass"] = glass_of(m, r)
        r["tags"] = tags(r)
    return m, rooms


def summary_line(r):
    k = r["kit"]
    ks = ", ".join("%s%s" % (f, ("x%d" % n) if n > 1 else "") for f, n in sorted(k.items(), key=lambda kv: (-kv[1], kv[0]))
                   if f not in ("table", "chair", "camera", "holopad", "rack", "sign_other"))
    ds = "; ".join("%s%s%s>%s" % (d["path"].replace("/obj/machinery/door/", ""), (' "%s"' % d["name"]) if d["name"] else "",
                                   ("[%s]" % d["access"]) if d["access"] else "",
                                   ",".join(b.replace("/area/", "") for b in d["beyond"]) or "?") for d in r["doors"])
    gl = ", ".join("%s" % a.replace("/area/", "") for a in r["glass"])
    return "%-38s %4d %-24s %s\n      doors: %s\n      glass: %s\n      kit: %s" % (
        r["area"].replace("/area/", ""), r["n"], "x%d-%d y%d-%d" % (r["box"][0], r["box"][2], r["box"][1], r["box"][3]),
        ",".join(r["tags"]), ds, gl, ks)


STOCK = [("meta", "MetaStation/MetaStation.dmm"), ("box", "BoxStation/BoxStation.dmm"),
         ("delta", "Deltastation/DeltaStation2.dmm"), ("hippie", "HippieStation/hippiestation.dmm"),
         ("pubby", "PubbyStation/PubbyStation.dmm"), ("donut", "Donutstation/Donutstation.dmm"),
         ("endo", "EndoStation/EndoStation.dmm"), ("metalake", "MetaLake/MetaLake.dmm")]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("maps", nargs="*")
    ap.add_argument("--json")
    a = ap.parse_args()
    maps = [(os.path.splitext(os.path.basename(p))[0], p) for p in a.maps] or \
        [(n, os.path.join(ROOT, "_maps", "map_files", p)) for n, p in STOCK]
    dump = {}
    for name, p in maps:
        m, rooms = study(p)
        print("=" * 30, name, len(rooms), "rooms")
        for r in sorted(rooms, key=lambda r: (r["area"], -r["n"])):
            if r["n"] < 3:
                continue
            print(summary_line(r))
        dump[name] = [dict(area=r["area"], n=r["n"], box=r["box"], tags=r["tags"], kit=dict(r["kit"]), doors=r["doors"],
                           glass=dict(r["glass"])) for r in rooms]
    if a.json:
        with open(a.json, "w", newline="") as f:
            json.dump(dump, f, indent=1)


if __name__ == "__main__":
    main()
