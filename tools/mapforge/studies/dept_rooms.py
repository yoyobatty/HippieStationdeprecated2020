"""Room-by-room reading of one department on a stock map: every walled room, its size, what stands in it, and which
doors join it to which rooms. Used before hand-designing a v6 department (studies/mapping_practice.md stage 5).

    python tools/mapforge/studies/dept_rooms.py MetaStation security
    python tools/mapforge/studies/dept_rooms.py BoxStation security --render
    python tools/mapforge/studies/dept_rooms.py MetaStation /area/medical /area/crew_quarters/heads/cmo

A department name picks a set of area prefixes (DEPTS below); anything starting with "/area" is taken as a prefix.
Rooms are flood fills of open floor inside the department's areas, cut by walls, windows and doors (fire doors
don't cut). The text lists each room (id, main area, tiles, size, the notable things in it) and each door
(kind, name, access, the two rooms it joins; "out:<area>" is a room outside the department).
--render writes data/previews/mapforge/study/<map>_<dept>.png, the region in the game's sprites with room ids.
"""
import argparse
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import dmm  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(ROOT, "data", "previews", "mapforge", "study")
DEPTS = {
    "security": ("/area/security", "/area/ai_monitored/security/armory", "/area/crew_quarters/heads/hos"),
    "medical": ("/area/medical", "/area/crew_quarters/heads/cmo"),
    "science": ("/area/science", "/area/crew_quarters/heads/hor"),
    "engineering": ("/area/engine", "/area/crew_quarters/heads/chief", "/area/storage/tech"),
    "cargo": ("/area/quartermaster", "/area/crew_quarters/heads/qm"),
    "command": ("/area/bridge", "/area/crew_quarters/heads/captain", "/area/crew_quarters/heads/hop",
                "/area/teleporter", "/area/ai_monitored/storage/eva"),
}
# security checkpoints sit in other departments; studying the brig means leaving them out
SKIP = ("/area/security/checkpoint",)
WALLS = ("/turf/closed",)
CUTS = ("/obj/structure/window", "/obj/effect/spawner/structure/window", "/obj/structure/grille",
        "/obj/machinery/door")
NOT_CUTS = ("/obj/machinery/door/firedoor",)
SKIP_ITEMS = ("/obj/effect", "/obj/machinery/atmospherics", "/obj/structure/cable", "/obj/machinery/door",
              "/obj/machinery/light", "/obj/structure/disposalpipe", "/obj/machinery/camera", "/obj/structure/sign",
              "/obj/machinery/firealarm", "/obj/machinery/airalarm", "/obj/machinery/power/apc",
              "/obj/machinery/light_switch", "/obj/machinery/navbeacon", "/obj/item/radio/intercom",
              "/obj/structure/window", "/obj/structure/grille", "/obj/item/", "/obj/machinery/power/terminal",
              "/obj/machinery/newscaster", "/obj/structure/extinguisher_cabinet", "/obj/machinery/status_display",
              "/obj/machinery/holopad", "/obj/structure/table", "/obj/structure/chair", "/obj/structure/rack",
              "/obj/structure/closet/firecloset", "/obj/structure/closet/emcloset", "/obj/machinery/firealarm")
D4 = ((1, 0), (-1, 0), (0, 1), (0, -1))


def find_map(name):
    if os.path.exists(name):
        return name
    p = os.path.join(ROOT, "_maps", "map_files", name, name + ".dmm")
    if os.path.exists(p):
        return p
    raise SystemExit("no map " + name)


def is_cut(t):
    if t is None or t.tpath.startswith(WALLS) or t.tpath.startswith("/turf/open/space"):
        return True
    return any(o.isa(p) for o in t.objs for p in CUTS if not any(o.isa(n) for n in NOT_CUTS))


def is_door(t):
    return t is not None and any(o.isa("/obj/machinery/door") and not o.isa("/obj/machinery/door/firedoor")
                                 for o in t.objs)


def short(path):
    return path.rsplit("/", 2)[-2] + "/" + path.rsplit("/", 1)[-1] if path.count("/") > 3 else path


def study(m, prefixes, pad=3):
    def mine(t):
        return t is not None and t.apath.startswith(prefixes) and not t.apath.startswith(SKIP)
    dept = [(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and mine(t)]
    xs, ys = [p[0] for p in dept], [p[1] for p in dept]
    box = (min(xs) - pad, min(ys) - pad, max(xs) + pad, max(ys) + pad)
    rid, rooms = {}, []
    for (x, y) in sorted(dept, key=lambda p: (-p[1], p[0])):
        t = m.get(x, y)
        if (x, y) in rid or is_cut(t):
            continue
        n = len(rooms)
        tiles, st = [], [(x, y)]
        rid[(x, y)] = n
        while st:
            p = st.pop()
            tiles.append(p)
            for dx, dy in D4:
                q = (p[0] + dx, p[1] + dy)
                tq = m.get(*q)
                if q not in rid and mine(tq) and not is_cut(tq):
                    rid[q] = n
                    st.append(q)
        areas = Counter(m.get(*p).apath for p in tiles)
        things = Counter()
        for p in tiles:
            for o in m.get(*p).objs:
                if not o.path.startswith(SKIP_ITEMS) or o.isa("/obj/structure/closet/secure_closet"):
                    things[o.path.rsplit("/", 1)[-1] if o.path.count("/") > 3 else o.path] += 1
        rx, ry = [p[0] for p in tiles], [p[1] for p in tiles]
        rooms.append(dict(id=n, area=areas.most_common(1)[0][0], tiles=tiles, n=len(tiles),
                          size=(max(rx) - min(rx) + 1, max(ry) - min(ry) + 1), things=things))
    doors = []
    for (x, y, z), t in m.tiles.items():
        if z != 1 or not (box[0] <= x <= box[2] and box[1] <= y <= box[3]) or not is_door(t):
            continue
        sides = []
        for dx, dy in D4:
            q = (x + dx, y + dy)
            tq = m.get(*q)
            if q in rid:
                sides.append("R%d" % rid[q])
            elif tq is not None and not is_cut(tq) and not mine(tq):
                sides.append("out:" + short(tq.apath))
        sides = sorted(set(sides))
        if len(sides) < 2 or not any(s.startswith("R") for s in sides):
            continue
        d = [o for o in t.objs if o.isa("/obj/machinery/door") and not o.isa("/obj/machinery/door/firedoor")][0]
        kind = d.path.replace("/obj/machinery/door/", "")
        doors.append(dict(at=(x, y), kind=kind, name=(d.get("name") or "").strip('"'),
                          access=(d.get("req_access_txt") or d.get("req_one_access_txt") or "").strip('"'),
                          sides=sides))
    return box, rooms, doors


def report(rooms, doors):
    out = []
    for r in rooms:
        if r["n"] < 2:
            continue
        top = ", ".join("%s%s" % (k, "" if v == 1 else " x%d" % v) for k, v in r["things"].most_common(9))
        out.append("R%-3d %-40s %4d tiles %2dx%-2d  %s" % (r["id"], short(r["area"]), r["n"], r["size"][0],
                                                          r["size"][1], top))
    out.append("")
    seen = set()
    for d in sorted(doors, key=lambda d: d["sides"]):
        key = (tuple(d["sides"]), d["kind"])
        tag = "" if key not in seen else "  (again)"
        seen.add(key)
        out.append("%-34s %-28s acc %-6s %s%s" % (" <-> ".join(d["sides"]), d["kind"][:28], d["access"][:6],
                                                 d["name"][:30], tag))
    return out


def render_labelled(path, box, rooms, png):
    from PIL import ImageDraw
    from forge import render
    render.render(path, png, region=box)
    from PIL import Image
    img = Image.open(png).convert("RGB")
    d = ImageDraw.Draw(img)
    T = img.width // (box[2] - box[0] + 1)
    font = render._font(max(12, T // 2))
    for r in rooms:
        if r["n"] < 2:
            continue
        cx = sum(p[0] for p in r["tiles"]) / float(r["n"])
        cy = sum(p[1] for p in r["tiles"]) / float(r["n"])
        X, Y = (cx - box[0] + 0.5) * T, (box[3] - cy + 0.5) * T
        label = "R%d" % r["id"]
        d.rectangle([X - T * 0.6, Y - T * 0.3, X + T * 0.6, Y + T * 0.3], fill=(0, 0, 0))
        d.text((X - T * 0.5, Y - T * 0.28), label, fill=(255, 240, 120), font=font)
    img.save(png)
    return png


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("map")
    ap.add_argument("dept", nargs="+")
    ap.add_argument("--render", action="store_true")
    a = ap.parse_args()
    prefixes = tuple(p for d in a.dept for p in (DEPTS.get(d) or ((d,) if d.startswith("/area") else ())))
    if not prefixes:
        raise SystemExit("unknown department " + " ".join(a.dept))
    path = find_map(a.map)
    m = dmm.read(path)
    box, rooms, doors = study(m, prefixes)
    print("%s %s  region %s  rooms %d  floor %d" % (a.map, " ".join(a.dept), box, len(rooms),
                                                     sum(r["n"] for r in rooms)))
    for line in report(rooms, doors):
        print(line)
    if a.render:
        name = os.path.splitext(os.path.basename(path))[0] + "_" + "_".join(d.strip("/").replace("/", "-")
                                                                            for d in a.dept)
        png = render_labelled(path, box, rooms, os.path.join(OUT, name + ".png"))
        print("picture:", os.path.relpath(png, ROOT))


if __name__ == "__main__":
    main()
