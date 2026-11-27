"""Medical department survey: per map, every medical room piece (area, tiles, bbox), its kit counts, its doors
(type, name, access, what is beyond), its windows/desks toward other places. For the medical spec
(tools/mapforge/studies/dept_specs/medical.md).

    python tools/mapforge/studies/dept_specs/medical_work/survey.py [map ...]   # default: the 8 stock maps + f21c
    -> medical_work/survey.json and a text table on stdout
"""
import json
import os
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
MF = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, MF)
sys.path.insert(0, os.path.join(MF, "studies"))
from forge import corpus as CO, dmm  # noqa: E402
import stations  # noqa: E402

ROOT = os.path.abspath(os.path.join(MF, "..", ".."))
N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))

KIT = {
    "sleeper": ("/obj/machinery/sleeper",),
    "cryo": ("/obj/machinery/atmospherics/components/unary/cryo_cell",),
    "freezer": ("/obj/machinery/atmospherics/components/unary/thermomachine/freezer",),
    "o2_canister": ("/obj/machinery/portable_atmospherics/canister/oxygen",),
    "medvend": ("/obj/machinery/vending/medical",),
    "wallmed": ("/obj/machinery/vending/wallmed",),
    "drugvend": ("/obj/machinery/vending/drugs",),
    "medlocker": ("/obj/structure/closet/secure_closet/medical",),
    "cmo_locker": ("/obj/structure/closet/secure_closet/CMO",),
    "chem_locker": ("/obj/structure/closet/secure_closet/chemical",),
    "wardrobe": ("/obj/structure/closet/wardrobe",),
    "optable": ("/obj/structure/table/optable",),
    "op_computer": ("/obj/machinery/computer/operating",),
    "surgery_tray": ("/obj/item/storage/backpack/duffelbag/med/surgery", "/obj/item/surgical_drapes",
                     "/obj/item/scalpel", "/obj/item/retractor", "/obj/item/hemostat"),
    "sink": ("/obj/structure/sink",),
    "shower": ("/obj/machinery/shower",),
    "iv_drip": ("/obj/machinery/iv_drip",),
    "anesthetic": ("/obj/machinery/portable_atmospherics/canister/nitrous_oxide",
                   "/obj/item/tank/internals/anesthetic", "/obj/structure/closet/secure_closet/medical2"),
    "chem_dispenser": ("/obj/machinery/chem_dispenser",),
    "chem_master": ("/obj/machinery/chem_master",),
    "chem_heater": ("/obj/machinery/chem_heater",),
    "smartfridge_chem": ("/obj/machinery/smartfridge/chemistry",),
    "smartfridge": ("/obj/machinery/smartfridge",),
    "pill_bottles": ("/obj/item/storage/pill_bottle", "/obj/item/storage/box/pillbottles"),
    "beakers": ("/obj/item/reagent_containers/glass/beaker", "/obj/item/storage/box/beakers"),
    "dna_scanner": ("/obj/machinery/dna_scannernew",),
    "dna_console": ("/obj/machinery/computer/scan_consolenew",),
    "monkey": ("/mob/living/carbon/monkey",),
    "monkey_cubes": ("/obj/item/storage/box/monkeycubes", "/obj/item/reagent_containers/food/snacks/monkeycube"),
    "clonepod": ("/obj/machinery/clonepod",),
    "clone_console": ("/obj/machinery/computer/cloning",),
    "morgue": ("/obj/structure/bodycontainer/morgue",),
    "bodybag": ("/obj/item/storage/box/bodybags", "/obj/item/bodybag"),
    "pandemic": ("/obj/machinery/computer/pandemic",),
    "bio_closet": ("/obj/structure/closet/l3closet",),
    "viro_locker": ("/obj/structure/closet/secure_closet/medical1",),
    "crew_monitor": ("/obj/machinery/computer/crew",),
    "med_records": ("/obj/machinery/computer/med_data",),
    "keycard": ("/obj/machinery/keycard_auth",),
    "defib": ("/obj/machinery/defibrillator_mount", "/obj/item/defibrillator"),
    "stasis": ("/obj/machinery/stasis",),
    "roller": ("/obj/structure/bed/roller", "/obj/item/roller"),
    "bed": ("/obj/structure/bed",),
    "chair": ("/obj/structure/chair",),
    "table": ("/obj/structure/table",),
    "firstaid": ("/obj/item/storage/firstaid",),
    "extinguisher": ("/obj/structure/extinguisher_cabinet",),
    "fire_closet": ("/obj/structure/closet/firecloset",),
    "em_closet": ("/obj/structure/closet/emcloset",),
    "sign": ("/obj/structure/sign",),
    "requests": ("/obj/machinery/requests_console",),
    "holopad": ("/obj/machinery/holopad",),
    "biohazard_sign": ("/obj/structure/sign/warning/biohazard",),
    "plumbed": ("/obj/machinery/plumbing",),
    "medbot": ("/mob/living/simple_animal/bot/medbot",),
    "glass_cab": ("/obj/structure/closet/secure_closet/personal/patient",),
    "curtain": ("/obj/structure/curtain",),
    "mirror": ("/obj/structure/mirror",),
    "body_scanner": ("/obj/machinery/bodyscanner", "/obj/machinery/body_scan_display"),
    "mass_driver": ("/obj/machinery/mass_driver",),
    "disposal": ("/obj/machinery/disposal",),
    "chute": ("/obj/structure/disposaloutlet",),
    "flasher": ("/obj/machinery/flasher",),
    "seccomp": ("/obj/machinery/computer/secure_data", "/obj/machinery/computer/security"),
    "sec_locker": ("/obj/structure/closet/secure_closet/security",),
    "medkit_wall": ("/obj/machinery/vending/wallmed",),
}

MED = ("/area/medical", "/area/crew_quarters/heads/cmo", "/area/security/checkpoint/medical")


def is_med(a):
    return a is not None and a.startswith(MED)


def floor(t):
    return t is not None and t.tpath.startswith("/turf/open") and not t.tpath.startswith("/turf/open/space") \
        and not CO.solid(t) and not t.has("/obj/machinery/door")


def kit_of(objs):
    c = Counter()
    for o in objs:
        for k, pre in KIT.items():
            if o.path.startswith(pre):
                c[k] += 1
    return c


def region_name(a):
    return a


def survey(path, label):
    m = dmm.read(path)
    by = defaultdict(set)
    for (x, y, z), t in m.tiles.items():
        if z != 1 or not floor(t):
            continue
        if is_med(t.apath):
            by[t.apath].add((x, y))
    pieces = []
    for area, tiles in sorted(by.items()):
        left = set(tiles)
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
            pieces.append((area, comp))
    out = []
    piece_of = {}
    for i, (area, comp) in enumerate(pieces):
        for p in comp:
            piece_of[p] = i
    for i, (area, comp) in enumerate(pieces):
        xs = [p[0] for p in comp]
        ys = [p[1] for p in comp]
        objs = []
        for p in comp:
            objs += m.get(*p).objs
        kit = kit_of(objs)
        # doors and windows: a door/window tile next to the piece; what's on its far side
        doors, windows, desks = [], [], []
        seen = set()
        for p in comp:
            for dx, dy in N4:
                w = (p[0] + dx, p[1] + dy)
                tw = m.get(*w)
                if tw is None or w in seen:
                    continue
                q = (w[0] + dx, w[1] + dy)
                tq = m.get(*q)
                beyond = tq.apath if tq is not None and (floor(tq) or tq.has("/obj/machinery/door")) else None
                if tw.has("/obj/machinery/door/airlock") or (tw.has("/obj/machinery/door/window") and not tw.has("/obj/structure/table")):
                    seen.add(w)
                    d = (tw.find("/obj/machinery/door/airlock") or tw.find("/obj/machinery/door/window"))[0]
                    doors.append({"at": w, "type": d.path, "name": (d.get("name") or "").strip('"'),
                                  "acc": (d.get("req_access_txt") or d.get("req_one_access_txt") or "").strip('"'),
                                  "beyond": beyond, "door_area": tw.apath})
                elif tw.has("/obj/structure/table") and tw.has("/obj/machinery/door/window"):
                    seen.add(w)
                    desks.append({"at": w, "beyond": beyond, "area": tw.apath})
                elif CO.solid(tw) and not tw.tpath.startswith("/turf/closed") and beyond and beyond != area:
                    seen.add(w)
                    windows.append({"at": w, "beyond": beyond})
        # desks inside the area's own tiles (a table+windoor on the area's floor? floor() excludes doors, so check border)
        out.append({"map": label, "area": area, "tiles": len(comp), "bbox": [min(xs), min(ys), max(xs), max(ys)],
                    "kit": dict(kit), "doors": doors, "windows": windows, "desks": desks})
    return m, out


def main():
    maps = sys.argv[1:] or ([("_maps/map_files/" + p) for p in CO.MAPS] + ["data/mapforge/gen_learn/f21c_c100_s7.dmm"])
    res = {}
    for p in maps:
        label = os.path.basename(p).replace(".dmm", "")
        _, out = survey(os.path.join(ROOT, p), label)
        res[label] = out
        print("== %s: %d medical pieces, %d tiles" % (label, len(out), sum(r["tiles"] for r in out)))
        for r in out:
            k = ", ".join("%s %d" % kv for kv in sorted(r["kit"].items()) if kv[0] not in ("chair", "table", "sign", "holopad"))
            print("  %-42s %4d  bbox %s  doors %d win %d desk %d | %s" % (r["area"], r["tiles"], r["bbox"], len(r["doors"]),
                  len(r["windows"]), len(r["desks"]), k))
    with open(os.path.join(HERE, "survey.json"), "w", newline="") as f:
        json.dump(res, f, indent=0)


if __name__ == "__main__":
    main()
