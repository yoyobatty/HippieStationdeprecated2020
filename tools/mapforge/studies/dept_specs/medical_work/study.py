"""Medical department, by function, on the stock maps and ours: every medical room piece typed by what it holds (an
operating table makes a surgery whatever its area is called: Box and Hippie keep theirs in /area/medical/sleeper),
then counted per map: which types exist, their sizes, which types share a door, which reach the hall, what the
public reaches without access, where the chemistry desk faces, the virology entrance, safety kit per type.

    python tools/mapforge/studies/dept_specs/medical_work/study.py [extra.dmm ...]
    -> medical_work/study.txt (tables), study.json

Used by gen/learn/fn_medical.py (classify) and the spec (tools/mapforge/studies/dept_specs/medical.md).
"""
import json
import os
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
MF = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, MF)
sys.path.insert(0, HERE)
from forge import corpus as CO, dmm  # noqa: E402
import survey as SV  # noqa: E402

ROOT = os.path.abspath(os.path.join(MF, "..", ".."))
N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
STOCK = ["_maps/map_files/" + p for p in CO.MAPS]


def classify(area, tiles, kit):
    """A medical room piece's function type from its area and kit."""
    k = kit.get
    if area.startswith("/area/crew_quarters/heads/cmo"):
        return "cmo"
    if area.startswith("/area/security/checkpoint"):
        return "checkpoint"
    if k("optable") and not area.startswith("/area/medical/morgue"):
        return "surgery"
    if k("cryo"):
        return "cryo"
    if k("chem_dispenser") or k("chem_master"):
        return "chemistry"
    if k("pandemic"):
        return "viro_lab"
    if k("dna_console"):
        return "genetics"
    if k("clonepod") or k("clone_console"):
        return "cloning"
    if (k("morgue") or 0) >= 3:
        return "morgue"
    if area.startswith("/area/medical/virology"):
        if (k("bio_closet") or 0) >= 2 or (k("shower") and k("bio_closet")):
            return "viro_airlock"
        if k("monkey"):
            return "viro_pen"
        if tiles <= 12 and (k("bed") or k("iv_drip")):
            return "viro_cell"
        return "viro_other"
    if k("sleeper") or k("stasis"):
        return "treatment"
    if (k("firstaid") or 0) >= 4 or ((k("medlocker") or 0) >= 2 and tiles <= 40):
        return "storage"
    if area.startswith("/area/medical/patients_rooms") or (tiles <= 15 and k("bed") and (k("glass_cab") or k("wallmed"))):
        return "patient_room"
    if area.startswith("/area/medical/morgue"):
        return "morgue_other"
    if area.startswith("/area/medical/surgery"):
        return "surgery_obs" if (k("bed") or k("iv_drip") or k("roller")) else "surgery_prep"
    if area.startswith("/area/medical/medbay/lobby"):
        return "lobby"
    if area.startswith(("/area/medical/medbay", "/area/medical/sleeper", "/area/medical/exam_room")):
        if k("crew_monitor") or k("med_records"):
            return "reception" if tiles <= 20 else "medhall"
        return "medhall"
    if area.startswith("/area/medical/genetics"):
        return "genetics_other"
    if area.startswith("/area/medical/storage"):
        return "storage"
    if area.startswith("/area/medical/abandoned"):
        return "abandoned"
    return "other:" + area


def outside(a):
    if a is None:
        return "wall"
    if a.startswith("/area/hallway"):
        return "HALL"
    if a.startswith("/area/maintenance"):
        return "MAINT"
    if a.startswith("/area/space"):
        return "SPACE"
    if a.startswith("/area/chapel"):
        return "CHAPEL"
    return "OUT:" + "/".join(a.split("/")[2:4])


def study(path, label):
    m, pieces = SV.survey(path, label)
    pid = {}
    for i, r in enumerate(pieces):
        r["type"] = classify(r["area"], r["tiles"], r["kit"])
    # piece tiles again (survey keeps bbox only): flood per area
    tiles_of = []
    for i, r in enumerate(pieces):
        x0, y0, x1, y1 = r["bbox"]
        ts = set()
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                t = m.get(x, y)
                if SV.floor(t) and t.apath == r["area"]:
                    ts.add((x, y))
        tiles_of.append(ts)
    for i, ts in enumerate(tiles_of):
        for p in ts:
            pid.setdefault(p, i)

    def side(p, step=None):
        """What lies at p, through up to 3 more door tiles along step (double doors, vestibules)."""
        for _ in range(4):
            if p in pid:
                return ("P", pid[p])
            t = m.get(*p)
            if t is None or not (SV.floor(t) or t.has("/obj/machinery/door")):
                return ("X", "wall")
            if t.has("/obj/machinery/door/airlock") and step:
                p = (p[0] + step[0], p[1] + step[1])
                continue
            return ("X", outside(t.apath))
        return ("X", "wall")

    doors = []
    seen = set()
    for i, r in enumerate(pieces):
        for d in r["doors"]:
            w = tuple(d["at"])
            if w in seen:
                continue
            seen.add(w)
            sides = []
            for dx, dy in ((1, 0), (0, 1)):
                a, b = (w[0] + dx, w[1] + dy), (w[0] - dx, w[1] - dy)
                sa, sb = side(a, (dx, dy)), side(b, (-dx, -dy))
                if sa[1] != "wall" and sb[1] != "wall":
                    sides = [sa, sb]
                    break
            doors.append({"at": w, "type": d["type"], "name": d["name"], "acc": d["acc"], "sides": sides})
    # desks (table + windoor): what's on both sides
    desks = []
    dseen = set()
    for i, r in enumerate(pieces):
        for d in r["desks"]:
            w = tuple(d["at"])
            if w in dseen:
                continue
            dseen.add(w)
            for dx, dy in ((1, 0), (0, 1)):
                a, b = (w[0] + dx, w[1] + dy), (w[0] - dx, w[1] - dy)
                sa, sb = side(a), side(b)
                if sa[1] != "wall" and sb[1] != "wall":
                    desks.append({"at": w, "sides": [sa, sb]})
                    break
    wins = []
    for i, r in enumerate(pieces):
        for d in r["windows"]:
            w = tuple(d["at"])
            for dx, dy in ((1, 0), (0, 1)):
                a, b = (w[0] + dx, w[1] + dy), (w[0] - dx, w[1] - dy)
                sa, sb = side(a), side(b)
                if sa[1] != "wall" and sb[1] != "wall" and sa != sb:
                    wins.append({"at": w, "sides": [sa, sb]})
                    break

    def name(s):
        return pieces[s[1]]["type"] if s[0] == "P" else s[1]

    # openings: a piece's floor tile beside another place's floor tile (no door: an archway, a firelock line, the
    # lobby's open front on Meta) count as a free door
    for i, ts in enumerate(tiles_of):
        got = set()
        for p in ts:
            for dx, dy in N4:
                n = (p[0] + dx, p[1] + dy)
                if n in ts:
                    continue
                tn = m.get(*n)
                if tn is None or not SV.floor(tn):
                    continue
                s = side(n)
                if s[1] == "wall" or s in got or (s[0] == "P" and s[1] < i):
                    continue
                got.add(s)
                doors.append({"at": n, "type": "opening", "name": "", "acc": "", "sides": [("P", i), s]})
    # public reach: from the hall, tile by tile, through floor and airlocks with no access (windoors are desks)
    adj = defaultdict(list)
    for d in doors:
        if len(d["sides"]) == 2:
            a, b = d["sides"]
            free = not d["acc"] and "window" not in d["type"]
            adj[a].append((b, free, d))
            adj[b].append((a, free, d))
    public = set()

    def passable(t):
        if t is None or not t.tpath.startswith("/turf/open") or t.tpath.startswith("/turf/open/space") or CO.solid(t):
            return False
        for o in t.objs:
            if o.path.startswith("/obj/machinery/door/airlock"):
                return not ((o.get("req_access_txt") or "").strip('"0') or (o.get("req_one_access_txt") or "").strip('"0'))
            if o.path.startswith("/obj/machinery/door/window") or o.path.startswith("/obj/machinery/door/poddoor/shutters") and not "preopen" in o.path:
                return False
        return True
    start = [p for (x, y, z), t in m.tiles.items() if z == 1 and t.apath.startswith("/area/hallway") and passable(t)
             for p in [(x, y)]]
    seenp = set(start)
    q = list(start)
    while q:
        p = q.pop()
        for dx, dy in N4:
            n = (p[0] + dx, p[1] + dy)
            if n in seenp:
                continue
            tn = m.get(*n)
            if not passable(tn):
                continue
            if not (tn.apath.startswith("/area/hallway") or SV.is_med(tn.apath)):
                continue            # the public walks the halls and medical only here
            seenp.add(n)
            q.append(n)
            if n in pid:
                public.add(pid[n])
    # hall distance in door hops (any access) per piece
    hop = {}
    q = [(s, 0) for s in adj if s[0] == "X" and s[1] == "HALL"]
    for s, _ in q:
        hop[s] = 0
    i = 0
    while i < len(q):
        s, h = q[i]
        i += 1
        for n, free, d in adj[s]:
            if n not in hop and n[0] == "P":
                hop[n] = h + 1
                q.append((n, h + 1))
    # the lobby: a public medical hall piece on the hall (the stock maps call it medbay/central more often than lobby)
    for i, r in enumerate(pieces):
        if r["type"] in ("medhall", "reception", "lobby") and i in public and \
                any(n == ("X", "HALL") for n, _, _ in adj[("P", i)]):
            r["type"] = "lobby"
    out = {"map": label, "pieces": [], "doors": [], "desks": [], "wins": []}
    for i, r in enumerate(pieces):
        nbs = Counter(name(n) for n, _, _ in adj[("P", i)])
        out["pieces"].append({"type": r["type"], "area": r["area"], "tiles": r["tiles"], "bbox": r["bbox"], "kit": r["kit"],
                              "door_to": dict(nbs), "public": i in public, "hops": hop.get(("P", i))})
    for d in doors:
        out["doors"].append({"at": d["at"], "type": d["type"], "name": d["name"], "acc": d["acc"],
                             "between": sorted(name(s) for s in d["sides"])})
    for d in desks:
        out["desks"].append({"at": d["at"], "between": sorted(name(s) for s in d["sides"])})
    for d in wins:
        out["wins"].append({"at": d["at"], "between": sorted(name(s) for s in d["sides"])})
    return out


def report(res, f):
    labels = list(res)
    types = sorted({p["type"] for r in res.values() for p in r["pieces"]})
    f.write("Room types (pieces / tiles) per map\n")
    f.write("%-16s" % "type" + "".join("%-14s" % l[:13] for l in labels) + "\n")
    for t in types:
        row = []
        for l in labels:
            ps = [p for p in res[l]["pieces"] if p["type"] == t]
            row.append("%d/%d" % (len(ps), sum(p["tiles"] for p in ps)) if ps else "-")
        f.write("%-16s" % t + "".join("%-14s" % c for c in row) + "\n")
    f.write("\nDoor neighbours per type (how many maps have a door between the two)\n")
    for l in labels:
        pass
    pair_maps = defaultdict(set)
    for l in labels:
        for d in res[l]["doors"]:
            pair_maps[tuple(d["between"])].add(l)
    for pr, ls in sorted(pair_maps.items(), key=lambda kv: (-len(kv[1]), kv[0])):
        f.write("  %-40s %d  %s\n" % (" | ".join(pr), len(ls), ",".join(sorted(x[:5] for x in ls))))
    f.write("\nDesks (table + windoor) between\n")
    dm = defaultdict(set)
    for l in labels:
        for d in res[l]["desks"]:
            dm[tuple(d["between"])].add(l)
    for pr, ls in sorted(dm.items(), key=lambda kv: -len(kv[1])):
        f.write("  %-40s %d  %s\n" % (" | ".join(pr), len(ls), ",".join(sorted(x[:5] for x in ls))))
    f.write("\nWindows between\n")
    wm = defaultdict(set)
    for l in labels:
        for d in res[l]["wins"]:
            wm[tuple(d["between"])].add(l)
    for pr, ls in sorted(wm.items(), key=lambda kv: -len(kv[1])):
        f.write("  %-40s %d  %s\n" % (" | ".join(pr), len(ls), ",".join(sorted(x[:5] for x in ls))))
    f.write("\nPublic (no-access path from the hall) / hops from hall, per type\n")
    for l in labels:
        pub = sorted({p["type"] for p in res[l]["pieces"] if p["public"]})
        hops = defaultdict(list)
        for p in res[l]["pieces"]:
            hops[p["type"]].append(p["hops"])
        f.write("  %-14s public: %s\n" % (l[:13], ", ".join(pub)))
        f.write("  %-14s hops: %s\n" % ("", ", ".join("%s %s" % (t, h) for t, h in sorted(hops.items()))))
    f.write("\nHall doors (type, name, access, room)\n")
    for l in labels:
        for d in res[l]["doors"]:
            if "HALL" in d["between"]:
                f.write("  %-14s %-34s %-28s %-10s %s\n" % (l[:13], d["type"].replace("/obj/machinery/door/", ""), d["name"][:27],
                                                           d["acc"], d["between"]))
    f.write("\nKit per type: share of maps whose rooms of the type hold it (any piece), and median count\n")
    for t in types:
        n = 0
        have = defaultdict(list)
        for l in labels:
            ps = [p for p in res[l]["pieces"] if p["type"] == t]
            if not ps:
                continue
            n += 1
            c = Counter()
            for p in ps:
                c.update(p["kit"])
            for k_, v in c.items():
                have[k_].append(v)
        if not n:
            continue
        f.write("  %-14s (%d maps): %s\n" % (t, n, ", ".join("%s %d/%d" % (k_, len(v), n) for k_, v in
                                                           sorted(have.items(), key=lambda kv: -len(kv[1])) if k_ not in ("sign",))))


def main():
    extra = sys.argv[1:]
    res = {}
    for p in STOCK + extra:
        label = os.path.basename(p).replace(".dmm", "")
        res[label] = study(os.path.join(ROOT, p), label)
    with open(os.path.join(HERE, "study.json"), "w", newline="") as f:
        json.dump(res, f, indent=0)
    with open(os.path.join(HERE, "study.txt"), "w", newline="") as f:
        report(res, f)
    print(open(os.path.join(HERE, "study.txt")).read())


if __name__ == "__main__":
    main()
