"""Stock study for the Security / Command / station spec: per map, the facts each rule reads (gen/learn/
fn_security_command.measure), over the 8 stock maps and any generated map given.

    python study.py [extra.dmm ...]  -> prints the tables, writes study.json beside this file
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
import fn_security_command as FS  # noqa: E402

ROOT = CO.ROOT


def facts(m):
    M = FS.measure(m)
    F, J, RL, K, present = M["F"], M["J"], M["RL"], M["K"], M["present"]
    f = {}
    f["present"] = dict(present)
    timed = [c for c in M["cells"] if c["doors"] and len(c["interior"]) >= 2]
    f["timers"] = len(M["cells"])
    f["timed_cells"] = len(timed)
    f["cell_sizes"] = sorted(len(c["interior"]) for c in timed)
    f["cells_locker"] = sum(1 for c in timed if c["locker"])
    f["cells_bed"] = sum(1 for c in timed if c["bed"])
    f["cells_flasher"] = sum(1 for c in timed if c["flasher"])
    f["timer_dist"] = sorted(c["dist"] for c in timed)
    f["timer_area"] = Counter(FS.role_of(m.get(*c["pos"]).apath) or FS._tag(m.get(*c["pos"]).apath) for c in M["cells"])
    f["cell_area"] = Counter(FS.role_of(m.get(*next(iter(c["interior"]))).apath) or "?" for c in timed if c["interior"])
    f["untimed_cellpieces"] = len(M["cellp"])
    for r in FS.SEC + FS.POSTS + FS.CMD + ("lawoffice",):
        if present[r]:
            f["links_" + r] = dict(RL.get(r, {}))
    # lockers etc. by role
    for name, pre, ex in (("seclocker", FS.LOCKER_SEC, False), ("wardenlocker", "/obj/structure/closet/secure_closet/warden", False),
                          ("hoslocker", "/obj/structure/closet/secure_closet/hos", False),
                          ("evidence", "/obj/structure/closet/secure_closet/evidence", False),
                          ("secvend", "/obj/machinery/vending/security", False),
                          ("recharger", "/obj/machinery/recharger", False),
                          ("brigphys", "/obj/machinery/vending/medical", False),
                          ("cardcon", "/obj/machinery/computer/card", True),
                          ("secdata", "/obj/machinery/computer/secure_data", False),
                          ("seccam", "/obj/machinery/computer/security", True),
                          ("prisoner_con", "/obj/machinery/computer/prisoner", False),
                          ("gulag_tp", "/obj/machinery/gulag_teleporter", False),
                          ("labor_con", "/obj/machinery/computer/shuttle/labor", False),
                          ("comms", "/obj/machinery/computer/communications", False),
                          ("idcon", "/obj/machinery/computer/card", True),
                          ("crewmon", "/obj/machinery/computer/crew", False),
                          ("upload_con", "/obj/machinery/computer/upload", False),
                          ("tele_con", "/obj/machinery/computer/teleporter", False),
                          ("nuke", "/obj/machinery/nuclearbomb", False),
                          ("suitstorage", "/obj/machinery/suit_storage_unit", False),
                          ("hopqueue_flasher", "/obj/machinery/flasher", False),
                          ("riot", "/obj/structure/rack", False),
                          ("weapons", "/obj/item/gun", False),
                          ("bench", "/obj/structure/chair", False)):
        d = {}
        for r, c in K.items():
            n = FS.has(c, pre, exact=ex)
            if n:
                d[r] = n
        f["kit_" + name] = d
    # doors of each role into what (by tag)
    for r in ("armory", "prison", "vault", "hop", "detective", "courtroom", "lawoffice", "warden", "hos", "education",
              "transfer", "labor", "eva", "teleporter", "gateway", "upload", "tcomms_ctrl", "bridge", "captain",
              "captain_bed", "customs", "post_escape"):
        if present[r]:
            f["doors_" + r] = Counter(FS._tag(o) for p, o in FS._doors_of(J, r, ("airlock", "windoor", "desk")))
    f["hop_airlock_hall"] = FS._hop_airlock_on_hall(m)
    f["hop_desk_hall"] = FS._hop_desk_hall(m, J)
    # desks: by (role a, role b)
    dk = Counter()
    for k, p, a, b in J:
        if k == "desk":
            ta, tb = FS._tag(a), FS._tag(b)
            dk["%s|%s" % tuple(sorted((ta, tb)))] += 1
    f["desks"] = dict(dk)
    # routes
    R = FS.routes(m, J)
    f["radius"] = R["radius"]
    f["route_arr"] = {k: round(v / R["radius"], 2) for k, v in R["arrivals"].items()}
    f["route_esc"] = {k: round(v / R["radius"], 2) for k, v in R["escape"].items()}
    # maint back doors per group, hall doors per group
    back, front = Counter(), Counter()
    for k, p, a, b in J:
        if k not in ("airlock",):
            continue
        for x, y in ((a, b), (b, a)):
            gx = FS.group_of(x) or "other"
            if y.startswith("/area/maintenance") and not x.startswith(("/area/maintenance", "/area/hallway")):
                back[gx] += 1
            if FS.is_hall(y) and not FS.is_hall(x) and not x.startswith("/area/maintenance"):
                front[gx] += 1
    f["back"] = dict(back)
    f["front"] = dict(front)
    # department footprint fill (tiles / bbox) for security and command, and room box fill
    for g in ("security", "command"):
        ts = [p for a, v in F.items() if FS.group_of(a) == g and not a.startswith("/area/security/checkpoint")
              and FS.role_of(a) not in FS.POSTS for p in v]
        if ts:
            xs, ys = [p[0] for p in ts], [p[1] for p in ts]
            f["fill_" + g] = round(len(ts) / float((max(xs) - min(xs) + 1) * (max(ys) - min(ys) + 1)), 2)
        rf = []
        for a, v in F.items():
            if FS.group_of(a) != g:
                continue
            for pc in FS.pieces(v):
                if len(pc) < 6:
                    continue
                xs, ys = [p[0] for p in pc], [p[1] for p in pc]
                rf.append(len(pc) / float((max(xs) - min(xs) + 1) * (max(ys) - min(ys) + 1)))
        if rf:
            f["boxrooms_" + g] = round(sum(1 for v in rf if v >= 0.999) / float(len(rf)), 2)
    return f


def main():
    maps = [(rel.split("/")[0], os.path.join(ROOT, "_maps", "map_files", rel)) for rel in CO.MAPS]
    maps += [(os.path.basename(p).split(".")[0], p) for p in sys.argv[1:]]
    out = {}
    for name, path in maps:
        m = dmm.read(path)
        out[name] = facts(m)
        print("done", name, file=sys.stderr)
    with open(os.path.join(HERE, "study.json"), "w", newline="") as fh:
        json.dump(out, fh, indent=1, sort_keys=True, default=lambda o: dict(o) if isinstance(o, Counter) else list(o))


if __name__ == "__main__":
    main()
