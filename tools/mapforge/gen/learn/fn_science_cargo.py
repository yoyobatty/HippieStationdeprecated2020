"""Science and Cargo function pass (spec: tools/mapforge/studies/dept_specs/science_cargo.md): the departments'
checkable rules, measured on the 8 stock maps, and the fixes that a finished layout allows.

    python tools/mapforge/gen/learn/fn_science_cargo.py <in.dmm> <out.dmm>    # check() before and after fix()
    python tools/mapforge/gen/learn/fn_science_cargo.py <in.dmm>              # check() only
    from gen.learn import fn_science_cargo as FSC
    FSC.check(m) -> [(x, y, text)]       # each text starts with its rule id (X1 ..., E1 ..., T1 ..., C1 ...)
    FSC.fix(m, seed, log) -> int          # build.py: the last pass, after the networks and audit.mend

What fix() does (each step keeps every free floor tile reached from the room's doors and never stands a dense piece
on a door front):
- Xenobiology, for the bots' slime work (goals/xenobiology.dm; Bot Shift "science: slimes tended" failed on every
  generated map with 0 fed): the bot feeds and harvests through the slime console, which only acts where a camera
  sees (bot_camera_sees), and the generated lab had no camera at all. A camera in every pen and the kill room, and
  lab cameras until the processor's side is seen. Slimes to the stock 2-3, one a pen, none loose in the lab. One
  pen becomes the kill room: cold telecomms floor (TCOMMS_ATMOS, 80 K, the stock kill rooms' floor), the freezer
  and siphon of Box's, its supply vent off, a "Kill Chamber" airlock. The other pens get the stock front: a
  windoor and a blast door with its button on the lab side, and glass toward the lab. The extract fridge within
  4 tiles of the processor (run_processor looks in range(4)).
- Experimentation lab: the console 3 tiles from the experimentor (stock 7 of 7 maps: Chebyshev 3, never in the
  experimentor's own piece), so it stays linked (oview(3)) and out of the machine's oview(1) malfunctions.
- Cameras in every science and cargo room of 9+ tiles that has none (stock: science 20-45, cargo 6-8; f22 had 1
  and 0), on the wall face that sees most of the room.
- Cargo: miner lockers down to the stock 3 (f22 had 6), a cargo wardrobe in the bay or office (stock 8 of 8).
- Toxins: plan_burn_chamber()/stamp_burn_chamber() copy Box's burn chamber (/area/science/mixing/chamber, the
  incinerator_toxmix set goals/toxins.dm find_lab() needs) onto a hull wall of the mixing room when one fits; the
  generator has to put the mixing room on the hull first (spec, "Generator changes").
"""
import os
import random
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(HERE, "..", "..", "station"))
from forge import atmos as AT, corpus as CO, dmm, function as FN  # noqa: E402

N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
N8 = N4 + ((1, 1), (1, -1), (-1, 1), (-1, -1))
DIRV = {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0)}
VDIR = {v: k for k, v in DIRV.items()}
DIRNAME = {1: "north", 2: "south", 4: "east", 8: "west"}
OPP = {1: 2, 2: 1, 4: 8, 8: 4}

XENO = "/area/science/xenobiology"
EXPLAB = "/area/science/explab"
MIXING = "/area/science/mixing"
CHAMBER = "/area/science/mixing/chamber"
SCI = ("/area/science", "/area/crew_quarters/heads/hor", "/area/security/checkpoint/science")
CARGO = ("/area/quartermaster", "/area/security/checkpoint/supply")
CAMERA = "/obj/machinery/camera"
KILL_TURF = "/turf/open/floor/circuit/telecomms"
PEN_TURF = "/turf/open/floor/engine"
SLIMES_KEEP = 3          # stock 2-3 slimes in the pens (8 of 8 maps)
CAM_RANGE = 7            # /obj/machinery/camera view_range
NOT_ROOMS = ("/area/science/test_area",)
ROOM_NAMES = {
    "/area/science": "Research Division", "/area/science/research": "Research Division Lobby",
    "/area/science/lab": "R&D Lab", "/area/science/xenobiology": "Xenobiology Lab", "/area/science/storage": "Toxins Storage",
    "/area/science/mixing": "Toxins Lab", "/area/science/misc_lab": "Testing Lab", "/area/science/server": "Server Room",
    "/area/science/explab": "Experimentation Lab", "/area/science/robotics/lab": "Robotics Lab",
    "/area/science/robotics/mechbay": "Mech Bay", "/area/science/nanite": "Nanite Lab",
    "/area/crew_quarters/heads/hor": "Research Director's Office", "/area/security/checkpoint/science/research":
    "Science Security Post", "/area/security/checkpoint/science": "Science Security Post",
    "/area/quartermaster": "Cargo", "/area/quartermaster/office": "Cargo Office", "/area/quartermaster/storage": "Cargo Bay",
    "/area/quartermaster/sorting": "Mail Sorting", "/area/quartermaster/warehouse": "Warehouse",
    "/area/quartermaster/qm": "Quartermaster's Office", "/area/quartermaster/miningdock": "Mining Dock",
    "/area/quartermaster/miningoffice": "Mining Office", "/area/security/checkpoint/supply": "Cargo Security Post"}


# ------------------------------------------------------------------------------------------------ tiles

def _floor(t):
    return t is not None and t.tpath.startswith("/turf/open") and not t.tpath.startswith("/turf/open/space") \
        and not CO.solid(t)


def _door(t):
    return t is not None and any(o.path.startswith("/obj/machinery/door") and not o.path.startswith(
        "/obj/machinery/door/firedoor") for o in t.objs)


def _wall(t):
    return t is None or t.tpath.startswith("/turf/closed")


def _dense(t):
    return t is not None and any(FN.is_dense(o) for o in t.objs)


def _opaque(t):
    """What a camera can't see through (2020 tg opacity): walls, shut non-glass airlocks, shut blast doors."""
    if t is None or t.tpath.startswith("/turf/closed"):
        return True
    for o in t.objs:
        p = o.path
        if p.startswith("/obj/machinery/door/airlock"):
            if "/glass" in p or (o.get("glass") or "").strip() == "1" or (o.get("opacity") or "").strip() == "0":
                continue
            return True
        if p.startswith("/obj/machinery/door/poddoor") and "preopen" not in p:
            return True
        if p.startswith("/obj/structure/plasticflaps"):
            return True
    return False


def _cheb(a, b):
    return max(abs(a[0] - b[0]), abs(a[1] - b[1]))


def _line(a, b):
    """Tiles strictly between a and b on a Bresenham line."""
    (x0, y0), (x1, y1) = a, b
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    out = []
    x, y = x0, y0
    while (x, y) != (x1, y1):
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x += sx
        if e2 <= dx:
            err += dx
            y += sy
        if (x, y) != (x1, y1):
            out.append((x, y))
    return out


def sees(m, cam, p):
    """A camera at cam sees tile p: in range and a line either way with nothing opaque between (BYOND's view is a
    little looser than one Bresenham line, so both directions count)."""
    if _cheb(cam, p) > CAM_RANGE:
        return False
    if cam == p:
        return True
    for ln in (_line(cam, p), _line(p, cam)):
        if not any(_opaque(m.get(*q)) for q in ln):
            return True
    return False


def cameras(m):
    return [(x, y) for (x, y, z), t in m.tiles.items() if z == 1 and t.has(CAMERA)]


def seen(m, p, cams):
    return any(sees(m, c, p) for c in cams)


def floor_of(m, prefix, exact=False):
    out = {}
    for (x, y, z), t in m.tiles.items():
        if z != 1 or not _floor(t) or _door(t):
            continue
        a = t.apath
        if (a == prefix) if exact else (a == prefix or a.startswith(prefix + "/")):
            out.setdefault(a, set()).add((x, y))
    return out


def pieces(tiles):
    left, out = set(tiles), []
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
        out.append(comp)
    out.sort(key=lambda c: (-len(c), min(c)))
    return out


def doors_of(m, F):
    return {(p[0] + dx, p[1] + dy) for p in F for dx, dy in N4 if _door(m.get(p[0] + dx, p[1] + dy))}


def reach(m, F, doors):
    """(reached free tiles, free tiles, door fronts) of a piece F: walking in from its doors over non-dense floor."""
    fronts = {(d[0] + dx, d[1] + dy) for d in doors for dx, dy in N4} & F
    free = {p for p in F if not _dense(m.get(*p))}
    seen_, q = set(), [p for p in fronts if p in free]
    seen_ |= set(q)
    while q:
        p = q.pop()
        for dx, dy in N4:
            n = (p[0] + dx, p[1] + dy)
            if n in free and n not in seen_:
                seen_.add(n)
                q.append(n)
    return seen_, free, fronts


def _keeps_reach(m, F, doors, before):
    """After a change: no free tile newly unreached and no reached dense piece boxed in."""
    seen0, free0, used0 = before
    seen1, free1, _ = reach(m, F, doors)
    if (free1 - seen1) - (free0 - seen0):
        return False
    for q in used0:
        if q in free1:
            continue
        if not any((q[0] + dx, q[1] + dy) in seen1 for dx, dy in N4):
            return False
    return True


def _state(m, F, doors):
    seen0, free0, _ = reach(m, F, doors)
    used0 = {q for q in F if q not in free0 and any((q[0] + dx, q[1] + dy) in seen0 for dx, dy in N4)}
    return seen0, free0, used0


def hung_faces(m):
    """{(floor tile, side)} wall faces something already hangs on: mounted pieces by their offset, lights and cameras
    by their dir (a light's dir is its wall; a camera faces away from its wall), and walls with a mount from behind."""
    out = set()
    for (x, y, z), t in m.tiles.items():
        if z != 1:
            continue
        for o in t.objs:
            if CO.mounted(o):
                out.add(((x, y), CO.mount_side(o)))
            elif o.path.startswith("/obj/machinery/light"):
                out.add(((x, y), o.num("dir", 2)))
            elif o.path.startswith(CAMERA):
                out.add(((x, y), OPP.get(o.num("dir", 2), 1)))
    walls = set()
    for (p, s) in out:
        v = DIRV.get(s)
        if v:
            walls.add((p[0] + v[0], p[1] + v[1]))
    return out, walls


def wall_faces(m, F, doors, hung, hung_walls):
    """[(tile, side)] free wall faces of a piece: the wall behind is a plain wall with nothing hung on it from
    either side, the tile is not a door."""
    out = []
    for p in sorted(F):
        if p in doors:
            continue
        for s, v in DIRV.items():
            w = (p[0] + v[0], p[1] + v[1])
            tw = m.get(*w)
            if not _wall(tw) or tw is None or w in doors or (p, s) in hung or w in hung_walls:
                continue
            if any(not o.path.startswith(("/obj/structure/cable", "/obj/machinery/atmospherics/pipe")) for o in tw.objs):
                continue
            out.append((p, s))
    return out


def camera_atom(side, tag, network=None):
    vs = [("dir", str(OPP[side]))]
    vs.append(("c_tag", '"%s"' % tag))
    if network:
        vs.append(("network", "list(%s)" % ",".join('"%s"' % n for n in network)))
    return dmm.Atom(CAMERA, vs)


def network_for(area):
    if area.startswith(XENO):
        return ("ss13", "rd", "xeno")
    if area.startswith(SCI):
        return ("ss13", "rd")
    return None


# ------------------------------------------------------------------------------------------------ xenobiology

def xeno_layout(m):
    tiles = floor_of(m, XENO, exact=True).get(XENO, set())
    if not tiles:
        return None
    pcs = pieces(tiles)
    main = pcs[0]
    pens, annex, small = [], [], []
    for pc in pcs[1:]:
        # a pen: a small piece with one way in (Meta's cycling vestibules have two doors and are no pens)
        if 4 <= len(pc) <= 16:
            small.append(pc)
            entries = {d for d in doors_of(m, pc) if m.get(*d).has("/obj/machinery/door/airlock")
                       or m.get(*d).has("/obj/machinery/door/window")}
            (pens if len(entries) == 1 else annex).append(pc)
        else:
            annex.append(pc)
    objs = {}
    for (x, y, z), t in m.tiles.items():
        if z != 1 or t.apath != XENO:
            continue
        for o in t.objs:
            objs.setdefault(o.path, []).append((x, y))

    def find(prefix):
        return [p for path, ps in objs.items() if path == prefix or path.startswith(prefix + "/") for p in ps]
    L = dict(tiles=tiles, main=main, pens=pens, annex=annex,
             slimes=find("/mob/living/simple_animal/slime"),
             consoles=find("/obj/machinery/computer/camera_advanced/xenobio"),
             processor=find("/obj/machinery/processor/slime"), fridge=find("/obj/machinery/smartfridge/extract"),
             recycler=find("/obj/machinery/monkey_recycler"), cubes=find("/obj/item/storage/box/monkeycubes"))
    L["kill"] = None
    for pc in small:
        if any(m.get(*p).tpath.startswith(KILL_TURF) for p in pc) and not any(s in pc for s in L["slimes"]):
            L["kill"] = pc
    return L


def _pen_front(m, L, pc):
    """(door tile, lab tile in front) of a pen: its door with the main lab on the other side, else any door."""
    best = None
    for p in pc:
        for dx, dy in N4:
            d = (p[0] + dx, p[1] + dy)
            if not _door(m.get(*d)):
                continue
            q = (d[0] + dx, d[1] + dy)
            if q in L["main"]:
                return d, q, p
            best = best or (d, q, p)
    return best


def _spot_beside_visible(m, p, cams):
    for dx, dy in N8:
        q = (p[0] + dx, p[1] + dy)
        t = m.get(*q)
        if _floor(t) and not _dense(t) and seen(m, q, cams):
            return q
    return None


def check_xeno(m, L, cams, out):
    if L is None:
        return
    cx = sorted(L["tiles"])[0]
    if len(L["consoles"]) < 2:
        out.append(cx + ("X1 xenobiology: %d slime consoles (stock 2 on 8 of 8)" % len(L["consoles"]),))
    if not L["recycler"]:
        out.append(cx + ("X2 xenobiology: no monkey recycler in the consoles' area (stock 8 of 8)",))
    if not L["processor"] or not L["fridge"]:
        out.append(cx + ("X3 xenobiology: processor %d, extract fridge %d (stock 1 and 1)" % (len(L["processor"]), len(L["fridge"])),))
    elif min(_cheb(a, b) for a in L["processor"] for b in L["fridge"]) > 4:
        p = L["processor"][0]
        out.append(p + ("X3 xenobiology: extract fridge more than 4 tiles from the processor (run_processor looks in range(4))",))
    npens = len([pc for pc in L["pens"] if pc is not L["kill"]])
    if npens < 4:
        out.append(cx + ("X4 xenobiology: %d pens (stock 7-9 besides the kill room)" % npens,))
    for s in L["slimes"]:
        if not any(s in pc for pc in L["pens"]):
            out.append(s + ("X5 xenobiology: a slime loose outside the pens",))
    if len(L["slimes"]) > SLIMES_KEEP or len(L["slimes"]) < 2:
        out.append(cx + ("X5 xenobiology: %d slimes (stock 2-3)" % len(L["slimes"]),))
    for s in L["slimes"]:
        if not _spot_beside_visible(m, s, cams):
            out.append(s + ("X6 xenobiology: no camera sees a free tile beside this slime (the console feeds only where a camera sees)",))
    for p in L["processor"]:
        if not _spot_beside_visible(m, p, cams):
            out.append(p + ("X6 xenobiology: no camera sees a free tile beside the slime processor",))
    if L["kill"] is None:
        out.append(cx + ("X7 xenobiology: no kill room (a pen of cold telecomms floor; stock 8 of 8 have one, with a freezer)",))
    else:
        if not any(_floor(m.get(*p)) and not _dense(m.get(*p)) and seen(m, p, cams) for p in L["kill"]):
            out.append(min(L["kill"]) + ("X6 xenobiology: no camera sees the kill room",))
    for pc in L["pens"]:
        if pc is L["kill"]:
            continue
        f = _pen_front(m, L, pc)
        if f and m.get(*f[0]).has("/obj/machinery/door/airlock"):
            out.append(f[0] + ("X8 xenobiology: pen behind an airlock (stock: windoor and blast door, 7 pens of 7)",))
    if not L["cubes"]:
        out.append(cx + ("X9 xenobiology: no monkey cube box (stock 2 on 8 of 8)",))
    for p in L["tiles"]:
        if m.get(*p).has(SHIELDGEN) and not any(_wall(m.get(p[0] + dx, p[1] + dy)) for dx, dy in N4):
            out.append(p + ("X11 xenobiology: shield wall generator in the open floor (stock 8 of 8: the entrance's corners); "
                            "the bots push it aside",))
    ring = sorted(set(L["tiles"]) | {(p[0] + dx, p[1] + dy) for p in L["tiles"] for dx, dy in N4})
    for prob in AT.check(m, ring):
        if prob.startswith("open"):
            out.append(cx + ("X10 xenobiology: %s" % prob,))


def fix_xeno(m, L, r, log):
    if L is None:
        return 0
    n = 0
    slime_atoms = []
    for s in L["slimes"]:
        t = m.get(*s)
        for o in list(t.objs):
            if o.path.startswith("/mob/living/simple_animal/slime"):
                slime_atoms.append((s, o))
                t.objs.remove(o)
    pens = sorted(L["pens"], key=lambda pc: min(pc))
    # the kill room: a pen with cold floor already, else the pen nearest the processor (Box, Meta: beside the lab's
    # working end); the body is moved to the processor by the console either way
    kill = L["kill"]
    if kill is None and len(pens) >= 2:
        pr = (L["processor"] or L["consoles"] or [min(L["main"])])[0]
        kill = min(pens, key=lambda pc: (min(abs(p[0] - pr[0]) + abs(p[1] - pr[1]) for p in pc), min(pc)))
        n += make_kill_room(m, L, kill, log)
    others = [pc for pc in pens if pc is not kill]
    # slimes: the stock 2-3, one a pen, at its middle
    keep = slime_atoms[:SLIMES_KEEP]
    if len(slime_atoms) > len(keep):
        log("xeno: %d slimes past the stock 3 taken out" % (len(slime_atoms) - len(keep)))
        n += len(slime_atoms) - len(keep)
    for i, (s, o) in enumerate(keep):
        if not others:
            m.get(*s).objs.append(o)
            continue
        pc = others[i % len(others)]
        cx = sum(p[0] for p in pc) / float(len(pc))
        cy = sum(p[1] for p in pc) / float(len(pc))
        free = [p for p in pc if not _dense(m.get(*p))] or list(pc)
        q = min(free, key=lambda p: ((p[0] - cx) ** 2 + (p[1] - cy) ** 2, p))
        m.get(*q).objs.append(o)
        if q != s:
            n += 1
    # pen fronts: windoor + blast door + button, glass toward the lab
    hung, hung_walls = hung_faces(m)
    k = 0
    for pc in others:
        k += 1
        n += pen_front(m, L, pc, k, hung, hung_walls, log)
    n += shield_gens(m, L, log)
    # cameras: one in every pen and the kill room, then the lab until the processor's side is seen
    n += xeno_cameras(m, L, pens, kill, log)
    # the extract fridge within reach of the processor
    if L["processor"] and L["fridge"] and min(_cheb(a, b) for a in L["processor"] for b in L["fridge"]) > 4:
        n += _move_near(m, L["main"], L["fridge"][0], "/obj/machinery/smartfridge/extract", L["processor"][0], 4, log)
    if not L["cubes"]:
        tables = sorted(p for p in L["main"] if m.get(*p).has("/obj/structure/table"))
        if tables:
            m.get(*tables[0]).objs += [dmm.Atom("/obj/item/storage/box/monkeycubes"), dmm.Atom("/obj/item/storage/box/monkeycubes")]
            log("xeno: 2 monkey cube boxes on the table at %d,%d" % tables[0])
            n += 1
    return n


MASK_DIR = {AT.N | AT.S: 1, AT.E | AT.W: 4, AT.N | AT.E: 5, AT.S | AT.E: 6, AT.N | AT.W: 9, AT.S | AT.W: 10}


def _open_dirs(m, p, a):
    return [d for d, (dx, dy) in AT.DELTA.items() if AT.mask(a) & d and not any(
        AT.joins(a, b, d) for b in AT.atoms(m.get(p[0] + dx, p[1] + dy)))]


def prune_stubs(m, tiles, log=None):
    """Station pipes left with an open end after a vent came out: drop the dead pipe back to the line it hangs off;
    a manifold that loses one side becomes the bend or straight pipe of the two it keeps."""
    todo = set(tiles)
    n = 0
    for _ in range(80):
        if not todo:
            break
        p = todo.pop()
        t = m.get(*p)
        if t is None:
            continue
        for a in list(t.objs):
            if "/pipe/" not in a.path or AT.kind(a) not in ("supply", "scrubbers"):
                continue
            od = _open_dirs(m, p, a)
            if not od:
                continue
            keep = AT.mask(a) & ~sum(od)
            if bin(keep).count("1") <= 1:
                t.objs.remove(a)
                n += 1
                for d, (dx, dy) in AT.DELTA.items():
                    if keep & d:
                        todo.add((p[0] + dx, p[1] + dy))
            elif "/manifold" in a.path and bin(keep).count("1") == 2:
                a.path = a.path.replace("/manifold4w/", "/simple/").replace("/manifold/", "/simple/")
                a.vars = [(k, v) for k, v in a.vars if k != "dir"] + [("dir", str(MASK_DIR[keep]))]
                n += 1
    return n


SHIELDGEN = "/obj/machinery/power/shieldwallgen/xenobiologyaccess"
SHIELD_RANGE = 8


def shield_gens(m, L, log):
    """The lab's two containment shield generators to the corners of its entrance from the corridor, one each side of
    the way in, as Box and Meta have them (f22 left them in the open floor, where the bots pushed them about)."""
    F = L["main"]
    gens = [p for p in L["tiles"] if m.get(*p).has(SHIELDGEN)]
    lone = None
    if len(gens) == 1:
        # one generator alone makes no shield and stands in the way: it gets its partner, or goes (f50: a lone one
        # mid-passage, with a table and a disposal bin beside it, cut the lab in two and the scientist was stuck
        # behind it all shift: "science: experiments run" and "machines upgraded" failed)
        t1 = m.get(*gens[0])
        o1 = next(x for x in t1.objs if x.path.startswith(SHIELDGEN))
        lone = dmm.Atom(o1.path, list(o1.vars))
        t1.objs.append(lone)
        gens = [gens[0], gens[0]]
    elif len(gens) != 2 or all(any(_wall(m.get(p[0] + dx, p[1] + dy)) for dx, dy in N4) for p in gens):
        return 0
    doors = doors_of(m, F)
    entries = []
    for d in sorted(doors):
        for dx, dy in N4:
            o = m.get(d[0] + dx, d[1] + dy)
            i = (d[0] - dx, d[1] - dy)
            if _floor(o) and not o.apath.startswith(XENO) and i in F:
                entries.append((d, i, (-dx, -dy)))
    atoms = []
    for p in gens:
        t = m.get(*p)
        o = next(x for x in t.objs if x.path.startswith(SHIELDGEN))
        t.objs.remove(o)
        atoms.append((p, o))
    if lone is not None and len(entries) == 0:
        log("xeno: a lone shield generator at %d,%d and no entrance to pair it at: taken out" % gens[0])
        return 1
    before = _state(m, F, doors)
    fronts = {(d[0] + dx, d[1] + dy) for d in doors for dx, dy in N4}
    for d, i, inward in entries:
        along = (inward[1], inward[0])
        for depth in (1, 2):
            row0 = (d[0] + inward[0] * depth, d[1] + inward[1] * depth)
            if row0 not in F:
                continue
            ends = []
            for sgn in (1, -1):
                q = row0
                while (q[0] + sgn * along[0], q[1] + sgn * along[1]) in F:
                    q = (q[0] + sgn * along[0], q[1] + sgn * along[1])
                ends.append(q)
            a, b = ends
            if abs(a[0] - b[0]) + abs(a[1] - b[1]) > SHIELD_RANGE or a == b:
                continue
            if any(_dense(m.get(*q)) or q in fronts for q in (a, b)):
                continue
            m.get(*a).objs.append(atoms[0][1])
            m.get(*b).objs.append(atoms[1][1])
            if _keeps_reach(m, F, doors, before):
                log("xeno: shield generators to the entrance's corners %d,%d and %d,%d" % (a + b))
                return 1
            m.get(*a).objs.remove(atoms[0][1])
            m.get(*b).objs.remove(atoms[1][1])
    # no straight run at the entrance: each to the nearest wall spot (a lone one and its partner: both go)
    if lone is not None:
        log("xeno: a lone shield generator at %d,%d with no entrance corners for a pair: taken out" % gens[0])
        return 1
    moved = 0
    for p, o in atoms:
        m.get(*p).objs.append(o)
        if not any(_wall(m.get(p[0] + dx, p[1] + dy)) for dx, dy in N4):
            moved += _move_near(m, F, p, SHIELDGEN, p, 6, log)
    return moved


def make_kill_room(m, L, pc, log):
    """A pen made the kill room: cold telecomms floor (n2 at 80 K from roundstart), its station vent and scrubber out
    (a supply vent would warm it) and their dead pipe with them, Box's freezer and siphon, the door a "Kill
    Chamber" airlock."""
    for p in pc:
        t = m.get(*p)
        t.turf = dmm.Atom(KILL_TURF)
        t.objs = [o for o in t.objs if not (o.path.startswith(("/obj/machinery/atmospherics/components/unary/vent_pump",
                                                               "/obj/machinery/atmospherics/components/unary/vent_scrubber")))]
        t.objs = [o for o in t.objs if not o.path.startswith("/obj/effect/turf_decal")]
    ring = set(pc) | {(p[0] + dx, p[1] + dy) for p in pc for dx, dy in N4}
    prune_stubs(m, ring)
    f = _pen_front(m, L, pc)
    if f:
        d = m.get(*f[0])
        for o in d.objs:
            if o.path.startswith("/obj/machinery/door/airlock"):
                o.vars = [(k, v) for k, v in o.vars if k not in ("name", "req_access_txt", "req_one_access_txt")]
                o.vars += [("name", '"Kill Chamber"'), ("req_access_txt", '"55"')]
    # freezer against the back wall, the siphon on the tile in front of it, joined head to head (no pipe between)
    door = f[0] if f else None
    cands = []
    for p in sorted(pc):
        if door and abs(p[0] - door[0]) + abs(p[1] - door[1]) == 1:
            continue
        if _dense(m.get(*p)) or AT.atoms(m.get(*p)):
            continue
        for s, v in DIRV.items():
            if not _wall(m.get(p[0] - v[0], p[1] - v[1])):
                continue
            q = (p[0] + v[0], p[1] + v[1])
            if q in pc and not _dense(m.get(*q)) and not AT.atoms(m.get(*q)) and q != door:
                dist = abs(p[0] - door[0]) + abs(p[1] - door[1]) if door else 0
                cands.append((-dist, p, s, q))
    added = ""
    if cands:
        before = _state(m, pc, doors_of(m, pc))
        for _, p, s, q in sorted(cands):
            fr = dmm.Atom("/obj/machinery/atmospherics/components/unary/thermomachine/freezer/on",
                          [("dir", str(s)), ("name", '"kill room freezer"')])
            m.get(*p).objs.append(fr)
            if _keeps_reach(m, pc, doors_of(m, pc), before):
                m.get(*q).objs.append(dmm.Atom("/obj/machinery/atmospherics/components/unary/vent_pump/siphon/on",
                                               [("dir", str(OPP[s])), ("external_pressure_bound", "120"),
                                                ("name", '"killroom vent"')]))
                added = ", freezer at %d,%d" % p
                break
            m.get(*p).objs.remove(fr)
    log("xeno: kill room at %d,%d (%d tiles): cold floor%s" % (min(pc) + (len(pc), added)))
    return 1


def pen_front(m, L, pc, k, hung, hung_walls, log):
    f = _pen_front(m, L, pc)
    if not f:
        return 0
    d, q, inside = f
    t = m.get(*d)
    n = 0
    if t.has("/obj/machinery/door/airlock"):
        step = (q[0] - d[0], q[1] - d[1])               # toward the lab
        side = VDIR[step]
        keep = [o for o in t.objs if o.path.startswith(("/obj/structure/cable", "/obj/machinery/atmospherics/pipe",
                                                         "/obj/structure/disposalpipe"))]
        bid = "xenobio%d" % k
        t.turf = dmm.Atom(PEN_TURF)
        t.objs = keep + [dmm.Atom("/obj/machinery/door/window/%sleft" % DIRNAME[side],
                                  [("name", '"Containment Pen #%d"' % k), ("req_access_txt", '"55"')]),
                         dmm.Atom("/obj/machinery/door/poddoor/preopen", [("id", '"%s"' % bid),
                                                                         ("name", '"containment blast door"')])]
        n += 1
        # the button on the lab side, on the wall beside the front
        along = (step[1], step[0])
        placed = None
        for sgn in (1, -1, 2, -2):
            w = (d[0] + sgn * along[0], d[1] + sgn * along[1])
            lt = (w[0] + step[0], w[1] + step[1])
            tw, tl = m.get(*w), m.get(*lt)
            back = VDIR[(-step[0], -step[1])]
            if not _wall(tw) or tw is None or lt not in L["main"] or (lt, back) in hung or w in hung_walls or _door(tl):
                continue
            pv = DIRV[back]
            tl.objs.append(dmm.Atom("/obj/machinery/button/door", [("id", '"%s"' % bid), ("name", '"Containment Blast Doors"'),
                                                                   ("pixel_x", str(pv[0] * 24)), ("pixel_y", str(pv[1] * 24)),
                                                                   ("req_access_txt", '"55"')]))
            hung.add((lt, back))
            hung_walls.add(w)
            placed = lt
            break
        log("xeno: pen %d front at %d,%d: windoor and blast door%s" % (k, d[0], d[1],
                                                                       (", button at %d,%d" % placed) if placed else ""))
    # glass between the pen and the lab: each plain wall with the pen on one side and the lab's floor on the other
    glazed = 0
    for p in pc:
        for dx, dy in N4:
            w = (p[0] + dx, p[1] + dy)
            o2 = (w[0] + dx, w[1] + dy)
            tw = m.get(*w)
            if o2 not in L["main"] or tw is None or not tw.tpath.startswith("/turf/closed/wall") or w in hung_walls:
                continue
            if any(not o.path.startswith(("/obj/structure/cable", "/obj/machinery/atmospherics/pipe", "/obj/structure/disposalpipe"))
                   for o in tw.objs):
                continue
            # not a corner of the pen's wall (both neighbours along the wall are wall or glass)
            al = (dy, dx)
            if not all(CO.solid(m.get(w[0] + s * al[0], w[1] + s * al[1])) or _door(m.get(w[0] + s * al[0], w[1] + s * al[1]))
                       for s in (1, -1)):
                continue
            tw.turf = dmm.Atom("/turf/open/floor/plating")
            tw.objs = [o for o in tw.objs] + [dmm.Atom("/obj/effect/spawner/structure/window/reinforced")]
            glazed += 1
    if glazed:
        n += 1
    return n


def _cam_spot(m, F, want, cams, hung, hung_walls, doors, area_tag, network, log, extra=()):
    """Hang one camera in piece F on the free wall face that sees most of `want` (tiles); returns its tile or None."""
    faces = wall_faces(m, F, doors, hung, hung_walls)
    if not faces:
        return None
    best = None
    for p, s in faces:
        score = sum(1 for q in want if sees(m, p, q))
        far = min((abs(p[0] - d[0]) + abs(p[1] - d[1]) for d in doors), default=0)
        key = (score, far, -p[0], -p[1])
        if best is None or key > best[0]:
            best = (key, p, s)
    _, p, s = best
    m.get(*p).objs.append(camera_atom(s, area_tag, network))
    hung.add((p, s))
    v = DIRV[s]
    hung_walls.add((p[0] + v[0], p[1] + v[1]))
    cams.append(p)
    return p


def xeno_cameras(m, L, pens, kill, log):
    hung, hung_walls = hung_faces(m)
    cams = cameras(m)
    n = 0
    num = {id(pc): i + 1 for i, pc in enumerate([p for p in pens if p is not kill])}
    for pc in pens:
        if any(c in pc for c in cams):
            continue
        tag = "Xenobiology Lab - Kill Chamber" if pc is kill else "Xenobiology Lab - Pen #%d" % num[id(pc)]
        if _cam_spot(m, pc, pc, cams, hung, hung_walls, doors_of(m, pc), tag, network_for(XENO), log):
            n += 1
    need = []
    for p in L["processor"]:
        need.append([(p[0] + dx, p[1] + dy) for dx, dy in N8 if _floor(m.get(p[0] + dx, p[1] + dy))
                     and not _dense(m.get(p[0] + dx, p[1] + dy))])
    doors = doors_of(m, L["main"])
    for k in range(3):
        todo = [grp for grp in need if grp and not any(seen(m, q, cams) for q in grp)]
        if not todo and any(c in L["main"] for c in cams):
            break
        want = [q for grp in todo for q in grp] or sorted(L["main"])
        tag = "Xenobiology Lab - %s" % ("Processing" if todo else "Main")
        if not _cam_spot(m, L["main"], want, cams, hung, hung_walls, doors, tag, network_for(XENO), log):
            break
        n += 1
    log("xeno: %d cameras hung" % n)
    return n


def _move_near(m, F, at, path, target, rng, log):
    """Move the piece `path` at `at` to a wall spot of F within rng (Chebyshev) of target, keeping reach."""
    doors = doors_of(m, F)
    t = m.get(*at)
    o = next((x for x in t.objs if x.path.startswith(path)), None)
    if o is None:
        return 0
    before = _state(m, F, doors)
    t.objs.remove(o)
    fronts = {(d[0] + dx, d[1] + dy) for d in doors for dx, dy in N4}
    cands = sorted((q for q in F if _cheb(q, target) <= rng and q not in fronts and not _dense(m.get(*q))
                    and any(_wall(m.get(q[0] + dx, q[1] + dy)) for dx, dy in N4)),
                   key=lambda q: (_cheb(q, target), q))
    for q in cands:
        m.get(*q).objs.append(o)
        if _keeps_reach(m, F, doors, before):
            log("moved %s %d,%d -> %d,%d" % (path.split("/")[-1], at[0], at[1], q[0], q[1]))
            return 1
        m.get(*q).objs.remove(o)
    t.objs.append(o)
    return 0


# ------------------------------------------------------------------------------------------------ experimentation lab

def explab_layout(m):
    F = floor_of(m, EXPLAB, exact=True).get(EXPLAB, set())
    if not F:
        return None
    exp = [p for p in F if m.get(*p).has("/obj/machinery/rnd/experimentor")]
    con = [p for p in F if m.get(*p).has("/obj/machinery/computer/rdconsole")]
    return dict(F=F, exp=exp, con=con)


def check_explab(m, E, out):
    if E is None or not E["exp"]:
        return
    e = E["exp"][0]
    if not E["con"]:
        out.append(e + ("E1 explab: no R&D console within 3 tiles: the experimentor can't link (stock 7 of 7 at 3)",))
    else:
        d = min(_cheb(c, e) for c in E["con"])
        if d > 3:
            out.append(e + ("E1 explab: console %d tiles from the experimentor (links within 3)" % d,))
        elif d < 2:
            out.append(E["con"][0] + ("E2 explab: console beside the experimentor (stock 7 of 7: 3 away, out of its piece)",))
    atm = Counter()
    for p in E["F"] | doors_of(m, E["F"]):
        if m.get(*p).apath != EXPLAB:
            continue
        for o in m.get(*p).objs:
            if "vent_scrubber" in o.path:
                atm["scrubber"] += 1
            elif "vent_pump" in o.path:
                atm["vent"] += 1
            elif o.path.startswith("/obj/machinery/door/poddoor"):
                atm["blast"] += 1
    if not atm["scrubber"]:
        out.append(e + ("E3 explab: no scrubber (stock 7 of 7, 1-6): the machine's smoke and hot air stay in",))
    if not atm["vent"]:
        out.append(e + ("E3 explab: no air vent (stock 7 of 7)",))
    if not atm["blast"]:
        out.append(e + ("E4 explab: no blast doors closing off the test chamber (stock 7 of 7, 1-5)",))


def fix_explab(m, E, log):
    if E is None or not E["exp"] or not E["con"]:
        return 0
    e = E["exp"][0]
    c = min(E["con"], key=lambda q: _cheb(q, e))
    if _cheb(c, e) >= 2:
        return 0
    F = E["F"]
    doors = doors_of(m, F)
    t = m.get(*c)
    o = next(x for x in t.objs if x.path.startswith("/obj/machinery/computer/rdconsole"))
    before = _state(m, F, doors)
    t.objs.remove(o)
    fronts = {(d[0] + dx, d[1] + dy) for d in doors for dx, dy in N4}
    cands = []
    for q in F:
        if q in fronts or _dense(m.get(*q)) or _cheb(q, e) not in (2, 3):
            continue
        for s, v in DIRV.items():
            if not _wall(m.get(q[0] - v[0], q[1] - v[1])):
                continue
            fq = (q[0] + v[0], q[1] + v[1])                # the tile the user stands on
            if fq not in F or _dense(m.get(*fq)):
                continue
            cands.append((-_cheb(q, e), abs(q[0] - e[0]) + abs(q[1] - e[1]), q, s))
    for _, _, q, s in sorted(cands):
        o2 = o.copy()
        o2.vars = [(k, v) for k, v in o2.vars if k != "dir"] + ([("dir", str(s))] if s != 2 else [])
        m.get(*q).objs.append(o2)
        if _keeps_reach(m, F, doors, before) and _sees_tile(m, q, e):
            log("explab: console %d,%d -> %d,%d (%d from the experimentor)" % (c[0], c[1], q[0], q[1], _cheb(q, e)))
            return 1
        m.get(*q).objs.remove(o2)
    t.objs.append(o)
    return 0


def _sees_tile(m, a, b):
    """oview(3) from the experimentor: a line with nothing opaque between."""
    return any(not any(_opaque(m.get(*q)) for q in ln) for ln in (_line(a, b), _line(b, a)))


# ------------------------------------------------------------------------------------------------ toxins

BOX = None
# Box's burn chamber, x 184-192 y 100-104 on BoxStation.dmm, in block coordinates (u east from the hull line, v north
# from the middle row): u 0 the hull line (blast doors to space between two r_walls), 1-2 the vacuum chamber
# (injector, scrubber, sparkers, sensor), 3 the wall with the exterior airlock, 4 the dp vent pump between the
# airlocks and the two line pumps, 5 the interior airlock wall, 6 the control nook (chamber area: vent button,
# ignition switch, mixing-chamber air alarm, airlock controller, meters), 7 the valves, 8 the ports (mixing area).
# The station's own distro and scrubber pipes that cross Box's block are left out; the chamber's lines are
# /general/visible pipes and components, which the air pass leaves alone except the chamber's scrubber (see
# place_burn_chamber).
BOX_CHAMBER = (184, 100, 192, 104)
HULL_K = {8: 0, 1: 1, 4: 2, 2: 3}       # hull side -> quarter turns clockwise of Box's block (Box's hull is west)
PORTS_UV = ((8, -1), (8, 1))            # the inlet and outlet ports, which the bot must reach
NOOK_UV = ((6, -1), (6, 0), (6, 1))


def _station_pipe(o):
    return "/supply/" in o.path or "/scrubbers/" in o.path or o.path.startswith(("/obj/structure/cable",
                                                                                 "/obj/structure/disposalpipe"))


def _box_block():
    """{(u, v): Tile} of Box's chamber, station pipes and cables left out."""
    global BOX
    if BOX is None:
        bm = dmm.read(os.path.join(CO.ROOT, "_maps", "map_files", "BoxStation", "BoxStation.dmm"))
        x0, y0, x1, y1 = BOX_CHAMBER
        cells = {}
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                t = bm.get(x, y).copy()
                t.objs = [o for o in t.objs if not _station_pipe(o) and not o.path.startswith("/obj/effect/turf_decal")]
                cells[(x - x0, y - y0 - 2)] = t
        BOX = cells
    return BOX


def _block_pos(w, k, u, v):
    from forge import furnish
    rx, ry = furnish.rot_xy(u, v, k)
    return (w[0] + rx, w[1] + ry)


def _fits(m, mixing, side, w):
    """Box's block fits with its hull column centred on hull wall w: the hull column on wall with space outside, its
    floor cells on the mixing lab's floor, its wall cells on that floor or a wall (never another room's floor or a
    door)."""
    k = HULL_K[side]
    out = DIRV[side]
    lost = 0
    for (u, v), t in _box_block().items():
        q = _block_pos(w, k, u, v)
        tq = m.get(*q)
        if tq is None or _door(tq):
            return None
        if u == 0:
            o = m.get(q[0] + out[0], q[1] + out[1])
            if not _wall(tq) or o is None or not (o.tpath.startswith("/turf/open/space") or (abs(v) == 2 and _wall(o))):
                return None
            continue
        if t.tpath.startswith("/turf/open"):
            if q not in mixing:
                return None
        elif not (q in mixing or _wall(tq)):
            return None
        lost += sum(1 for o_ in tq.objs if not o_.path.startswith(("/obj/structure/cable", "/obj/machinery/atmospherics/pipe",
                                                                     "/obj/effect")))
    return lost


def plan_burn_chamber(m, mixing=None):
    """[(objects lost, side, hull wall tile)] where Box's chamber fits on the mixing lab's hull, fewest lost first."""
    if mixing is None:
        mixing = floor_of(m, MIXING, exact=True).get(MIXING, set())
    out = []
    seen_ = set()
    for (x, y) in sorted(mixing):
        for side, v in DIRV.items():
            w = (x + v[0], y + v[1])
            if (side, w) in seen_:
                continue
            seen_.add((side, w))
            tw, ts = m.get(*w), m.get(w[0] + v[0], w[1] + v[1])
            if not _wall(tw) or tw is None or ts is None or not ts.tpath.startswith("/turf/open/space"):
                continue
            lost = _fits(m, mixing, side, w)
            if lost is not None:
                out.append((lost, side, w))
    out.sort()
    return out


def stamp_burn_chamber(m, side, w, log=print):
    """Copy Box's chamber with its hull column on hull wall w (side: where space is). Returns the tiles it replaced
    {pos: old Tile} so a caller can undo it."""
    import to_dmm as T
    k = HULL_K[side]
    old = {}
    for (u, v), t in _box_block().items():
        q = _block_pos(w, k, u, v)
        old[q] = m.get(*q)
        nt = t.copy()
        nt.objs = [T.rot_engine_atom(o, k) for o in nt.objs]
        if nt.turf is not None and nt.turf.get("dir") is not None:
            nt.turf = T.rot_engine_atom(nt.turf, k)
        nt.area = dmm.Atom(CHAMBER if "chamber" in (t.apath or "") else MIXING)
        m.set(q[0], q[1], nt)
        if u == 0 and abs(v) <= 1:
            o = DIRV[side]
            so = (q[0] + o[0], q[1] + o[1])
            ts = m.get(*so)
            if ts is not None and ts.tpath.startswith("/turf/open/space") and not ts.has("/obj/structure/lattice"):
                old.setdefault(so, ts.copy())
                ts.objs.append(dmm.Atom("/obj/structure/lattice"))
    return old


def place_burn_chamber(m, log=print):
    """The generator's step (spec "Generator changes"): Box's burn chamber on a hull wall of the mixing lab, the spot
    that loses the fewest pieces and keeps the lab's floor, nook and ports reached from its doors. Run it after
    furnishing and BEFORE net.power (the APC sweep gives /area/science/mixing/chamber its APC) and net.air, with
    net.air skipping /area/science/mixing/chamber (its scrubber is the chamber's own, not the station's). Returns 1
    if stamped."""
    mixing = floor_of(m, MIXING, exact=True).get(MIXING, set())
    if not mixing or floor_of(m, CHAMBER, exact=True):
        return 0
    for lost, side, w in plan_burn_chamber(m, mixing):
        old = stamp_burn_chamber(m, side, w)
        k = HULL_K[side]
        F = floor_of(m, MIXING, exact=True).get(MIXING, set()) | floor_of(m, CHAMBER, exact=True).get(CHAMBER, set())
        doors = {d for d in doors_of(m, F) if d not in old}
        seen1, free1, _ = reach(m, F, doors)
        want = [_block_pos(w, k, u, v) for u, v in PORTS_UV + NOOK_UV]
        ok = doors and all(q in seen1 for q in want)
        if ok:
            log("toxins: Box's burn chamber on the hull at %d,%d (space to the %s), %d pieces replaced"
                % (w[0], w[1], DIRNAME[side], lost))
            return 1
        for q, t in old.items():
            m.set(q[0], q[1], t)
    log("toxins: no hull wall of the mixing lab takes Box's burn chamber")
    return 0



def check_toxins(m, out):
    mix = floor_of(m, MIXING, exact=True).get(MIXING, set())
    ch = floor_of(m, CHAMBER, exact=True).get(CHAMBER, set())
    at = sorted(mix)[0] if mix else (1, 1)
    if not mix:
        out.append(at + ("T1 toxins: no mixing lab",))
        return
    if not ch:
        out.append(at + ("T1 toxins: no burn chamber (/area/science/mixing/chamber; stock 7 of 8, goals/toxins.dm find_lab)",))
    else:
        has = Counter()
        for (x, y, z), t in m.tiles.items():
            if z == 1 and t.apath == CHAMBER:
                for o in t.objs:
                    for key, pre in (("injector", "/obj/machinery/atmospherics/components/unary/outlet_injector"),
                                     ("scrubber", "/obj/machinery/atmospherics/components/unary/vent_scrubber"),
                                     ("alarm", "/obj/machinery/airalarm"), ("vent_door", "/obj/machinery/door/poddoor")):
                        if o.path.startswith(pre):
                            has[key] += 1
        for key in ("injector", "scrubber", "alarm", "vent_door"):
            if not has[key]:
                out.append(min(ch) + ("T1 toxins: burn chamber has no %s" % key,))
    on_hull = any(m.get(x + 2 * dx, y + 2 * dy) is not None and m.get(x + 2 * dx, y + 2 * dy).tpath.startswith("/turf/open/space")
                  for (x, y) in mix | ch for dx, dy in N4)
    if not on_hull:
        out.append(at + ("T2 toxins: the mixing lab is not on the hull (stock 8 of 8): its chamber can't vent to space",))
    objs = Counter()
    for (x, y, z), t in m.tiles.items():
        if z != 1 or not t.apath.startswith("/area/science"):
            continue
        for o in t.objs:
            if o.path.startswith("/obj/machinery/mass_driver") and "toxins" in (o.get("id") or ""):
                objs["driver"] += 1
            if o.path.startswith("/obj/machinery/button/massdriver") and "toxins" in (o.get("id") or ""):
                objs["driver_button"] += 1
            if t.apath.startswith(MIXING) and o.path.startswith("/obj/machinery/atmospherics/components/unary/thermomachine"):
                objs["freezer"] += 1
            if o.path.startswith("/obj/structure/tank_dispenser"):
                objs["tanks"] += 1
            if o.path.startswith("/obj/machinery/doppler_array"):
                objs["doppler"] += 1
    if not objs["driver"] or not objs["driver_button"]:
        out.append(at + ("T3 toxins: no mass driver \"toxinsdriver\" with its button (stock 8 of 8) out to the test range",))
    if not objs["freezer"]:
        out.append(at + ("T4 toxins: no freezer on a port in the mixing lab (stock 7 of 8)",))
    if not objs["tanks"]:
        out.append(at + ("T5 toxins: no tank dispenser (stock 8 of 8)",))
    port = Counter()
    for p in mix:
        for o in m.get(*p).objs:
            if o.path == "/obj/machinery/portable_atmospherics/scrubber":
                port["scrubber"] += 1
            elif o.path.startswith("/obj/machinery/portable_atmospherics/pump"):
                port["pump"] += 1
    for key in ("pump", "scrubber"):
        if not port[key]:
            out.append(at + ("T7 toxins: no portable %s in the mixing lab (find_lab needs one; stock pump 5, scrubber 4 of 8)" % key,))
    if not objs["doppler"]:
        out.append(at + ("T6 toxins: no doppler array (stock 8 of 8)",))


# ------------------------------------------------------------------------------------------------ desks, joins, rooms

def _joined(m, a, b, kinds=("door", "desk", "window")):
    """Areas a and b (exact) meet through a door, a windoor desk or a window."""
    for (x, y, z), t in m.tiles.items():
        if z != 1:
            continue
        k = None
        if t.has("/obj/machinery/door/window") and t.has("/obj/structure/table"):
            k = "desk"
        elif _door(t):
            k = "door"
        elif CO.solid(t) and not t.tpath.startswith("/turf/closed"):
            k = "window"
        if k not in kinds:
            continue
        for ax in ((1, 0), (0, 1)):
            p, q = m.get(x + ax[0], y + ax[1]), m.get(x - ax[0], y - ax[1])
            if _floor(p) and _floor(q) and {p.apath, q.apath} == {a, b}:
                return (x, y)
            if _floor(p) and _floor(q) and a.endswith("*") and b in (p.apath, q.apath) and \
                    (p.apath if q.apath == b else q.apath).startswith(a[:-1]):
                return (x, y)
    return None


def _desks_of(m, area):
    """[(tile, the area it serves)] desks (windoor on a table) on the edge of `area`."""
    out = []
    for (x, y, z), t in m.tiles.items():
        if z != 1 or not (t.has("/obj/machinery/door/window") and t.has("/obj/structure/table")):
            continue
        sides = [m.get(x + dx, y + dy) for dx, dy in N4]
        areas = {s.apath for s in sides if _floor(s)} | {t.apath}
        if area in areas:
            other = [a for a in areas if a != area]
            if other:
                out.append(((x, y), other[0]))
    return out


def research_is_corridor(m):
    """Stock maps' /area/science/research is the department's corridor and lobby; ours can be a dead-end room."""
    res = floor_of(m, "/area/science/research", exact=True).get("/area/science/research", set())
    if not res:
        return False
    for d in doors_of(m, res):
        for dx, dy in N4:
            t = m.get(d[0] + dx, d[1] + dy)
            if _floor(t) and (t.apath.startswith("/area/hallway") or t.apath == "/area/science"):
                return True
    return len(res) >= 80


def check_science_rooms(m, out):
    A = floor_of(m, "/area/science")
    A.update(floor_of(m, "/area/crew_quarters/heads/hor"))
    first = lambda a: sorted(A[a])[0] if a in A else (1, 1)   # noqa: E731
    rc = research_is_corridor(m)
    for a, rule in (("/area/science/lab", "S1 R&D lab"), ("/area/science/robotics/lab", "S2 robotics")):
        if a not in A:
            out.append((1, 1, "%s: missing" % rule))
            continue
        ds = _desks_of(m, a)
        okd = [d for d in ds if d[1].startswith("/area/hallway") or d[1] == "/area/science"
               or (d[1] == "/area/science/research" and rc)]
        if not ds:
            out.append(first(a) + ("%s: no desk (windoor on a table) for the crew to collect from (stock: R&D 8 of 8 onto a "
                                   "primary hall, robotics 6 of 8)" % rule,))
        elif not okd:
            out.append(ds[0][0] + ("%s: its desk opens onto %s, not a hall or the science corridor" % (rule, ds[0][1]),))
    if "/area/science/robotics/lab" in A and "/area/science/robotics/mechbay" in A and \
            not _joined(m, "/area/science/robotics/lab", "/area/science/robotics/mechbay", ("door",)):
        out.append(first("/area/science/robotics/mechbay") + ("S3 mech bay: no door to robotics (stock 8 of 8 join by door)",))
    corr = [a for a in ("/area/science", "/area/science/research") if a in A and (a == "/area/science" or rc)]
    for a, rule in (("/area/crew_quarters/heads/hor", "S4 RD office"), ("/area/science/explab", "S5 explab"),
                    ("/area/science/xenobiology", "S6 xenobiology"), ("/area/science/server", "S7 server room")):
        if a in A and not any(_joined(m, a, c, ("door",)) for c in corr):
            out.append(first(a) + ("%s: no door onto the science corridor (stock: off the research corridor)" % rule,))
    srv = A.get("/area/science/server", set())
    if srv:
        n = sum(1 for p in srv for o in m.get(*p).objs if o.path.startswith("/obj/machinery/rnd/server"))
        fr = sum(1 for p in srv for o in m.get(*p).objs if o.path.startswith("/obj/machinery/atmospherics/components/unary/thermomachine"))
        if n < 2:
            out.append(first("/area/science/server") + ("S7 server room: %d R&D servers (stock 2 on 8 of 8)" % n,))
        if not fr:
            out.append(first("/area/science/server") + ("S7 server room: no freezer (stock 8 of 8 keep it cold)",))
    sh = [p for a in ("/area/science", "/area/science/research", XENO) for p in A.get(a, ())
          if m.get(*p).has("/obj/machinery/shower")]
    if not sh:
        out.append((1, 1, "S8 science: no emergency shower in the corridor or xenobiology (stock 8 of 8)"))
    res = A.get("/area/science/research", set())
    if res and not rc:
        exits = doors_of(m, res)
        onto = {m.get(d[0] + dx, d[1] + dy).apath for d in exits for dx, dy in N4
                if _floor(m.get(d[0] + dx, d[1] + dy))} - {"/area/science/research"}
        if True:
            out.append(first("/area/science/research") + ("S9 research lobby: a dead-end room (doors onto %s); stock "
                                                          "/area/science/research IS the corridor" % ", ".join(sorted(onto)),))


def port_rect(o, x, y):
    """Tiles of a stationary docking port's rect (2020 tg: dir is the port's facing; width along, dwidth offset)."""
    d = int(o.get("dir", "2"))
    w, dw, h = int(o.get("width", "1")), int(o.get("dwidth", "0")), int(o.get("height", "1"))
    pts = set()
    for i in range(-dw, w - dw):
        for j in range(0, h):
            pts.add({1: (x + i, y + j), 2: (x - i, y - j), 4: (x + j, y - i)}.get(d, (x - j, y + i)))
    return pts


def check_cargo(m, out):
    A = floor_of(m, "/area/quartermaster")
    A.update(floor_of(m, "/area/security/checkpoint/supply"))
    first = lambda a: sorted(A[a])[0] if a in A else (1, 1)   # noqa: E731
    ports = {}
    for (x, y, z), t in m.tiles.items():
        for o in t.objs:
            if o.path == "/obj/docking_port/stationary" and o.get("id") in ('"supply_home"', '"mining_home"'):
                ports[o.get("id").strip('"')] = (x, y, o)
    rect_of = port_rect

    def opens_into(pid):
        x, y, o = ports[pid]
        rect = rect_of(o, x, y)
        ring = {(a + dx, b + dy) for (a, b) in rect for dx, dy in N4} - rect
        got = set()
        for q in ring:
            if _door(m.get(*q)):
                for dx, dy in N4:
                    n = (q[0] + dx, q[1] + dy)
                    if n not in rect and _floor(m.get(*n)) and not _door(m.get(*n)):
                        got.add(m.get(*n).apath)
        return got
    if "supply_home" not in ports:
        out.append((1, 1, "C1 cargo: no supply shuttle dock"))
    elif rect_of:
        into = opens_into("supply_home")
        if "/area/quartermaster/storage" not in into:
            x, y, _ = ports["supply_home"]
            out.append((x, y, "C1 cargo: the supply dock opens into %s, not the cargo bay (stock 8 of 8 into the bay)"
                        % (", ".join(sorted(into)) or "nothing")))
    if "mining_home" in ports and rect_of:
        into = opens_into("mining_home")
        if not into & {"/area/quartermaster/miningdock", "/area/quartermaster/miningoffice"}:
            x, y, _ = ports["mining_home"]
            out.append((x, y, "C2 mining: the mining dock opens into %s, not the mining dock room (stock 8 of 8)"
                        % (", ".join(sorted(into)) or "nothing")))
    bay = A.get("/area/quartermaster/storage", set())
    cnt = Counter()
    for (x, y, z), t in m.tiles.items():
        if z != 1 or not t.apath.startswith(CARGO):
            continue
        for o in t.objs:
            for key, pre in (("conveyor", "/obj/machinery/conveyor"), ("flaps", "/obj/structure/plasticflaps"),
                             ("miner_locker", "/obj/structure/closet/secure_closet/miner"),
                             ("vendor", "/obj/machinery/mineral/equipment_vendor"), ("orm", "/obj/machinery/mineral/ore_redemption"),
                             ("chute", "/obj/machinery/disposal/deliveryChute"), ("qm_locker", "/obj/structure/closet/secure_closet/quartermaster"),
                             ("autolathe", "/obj/machinery/autolathe"), ("wardrobe", "/obj/machinery/vending/wardrobe/cargo_wardrobe"),
                             ("navbeacon", "/obj/machinery/navbeacon")):
                if o.path.startswith(pre) and not (key == "conveyor" and o.path.startswith("/obj/machinery/conveyor_switch")):
                    cnt[key] += 1
                    if key == "conveyor" and (x, y) in bay:
                        cnt["bay_conveyor"] += 1
    if bay and cnt["bay_conveyor"] < 4:
        out.append(first("/area/quartermaster/storage") + ("C3 cargo bay: %d conveyor belts from the dock (stock 11-17 on 8 of 8, "
                                                           "with 2 plastic flaps)" % cnt["bay_conveyor"],))
    if cnt["miner_locker"] != 3:
        out.append(first("/area/quartermaster/miningdock") + ("C4 mining: %d miner lockers (stock 3 on 8 of 8)" % cnt["miner_locker"],))
    for key, rule, why in (("vendor", "C4 mining", "no mining equipment vendor (stock 8 of 8)"),
                           ("orm", "C5 cargo", "no ore redemption machine (stock 8 of 8)"),
                           ("chute", "C6 mail", "no delivery chute in sorting (stock 7 of 8)"),
                           ("qm_locker", "C7 QM", "no quartermaster's locker (stock 8 of 8)"),
                           ("autolathe", "C8 office", "no autolathe in the office (stock 8 of 8)"),
                           ("wardrobe", "C9 cargo", "no cargo wardrobe (stock 8 of 8)")):
        if not cnt[key]:
            out.append((1, 1, "%s: %s" % (rule, why)))
    # the office: the crew's way in (a desk or door onto a hall)
    off = A.get("/area/quartermaster/office", set())
    if off:
        hall = False
        for p in off:
            for dx, dy in N4:
                w = (p[0] + dx, p[1] + dy)
                tw = m.get(*w)
                o2 = m.get(w[0] + dx, w[1] + dy)
                if tw is not None and (_door(tw) or tw.has("/obj/structure/table")) and _floor(o2) and o2.apath.startswith("/area/hallway"):
                    hall = True
                if _floor(tw) and tw.apath.startswith("/area/hallway"):
                    hall = True             # Box: the lobby open to the hall, no door
        if not hall:
            out.append(first("/area/quartermaster/office") + ("C10 cargo office: no door or desk onto a hall (stock: the office "
                                                              "is the public front, 8 of 8)",))
    if "/area/quartermaster/qm" in A and "/area/quartermaster/storage" in A and \
            not _joined(m, "/area/quartermaster/qm", "/area/quartermaster/storage"):
        out.append(first("/area/quartermaster/qm") + ("C11 QM office: doesn't look onto the bay (stock 8 of 8: door or window)",))
    if "/area/security/checkpoint/supply" not in A:
        out.append((1, 1, "C12 cargo: no security post (stock 7 of 8)"))


def check_cameras(m, out, cams=None):
    cams = cams if cams is not None else cameras(m)
    for prefixes, rule in ((SCI, "K1 science"), (CARGO, "K2 cargo")):
        A = {}
        for pre in prefixes:
            A.update(floor_of(m, pre))
        for a, tiles in sorted(A.items()):
            if a.startswith(NOT_ROOMS) or a == XENO:
                continue
            for F in pieces(tiles):
                if len(F) < 9:
                    continue
                if not any(c in F for c in cams):
                    out.append(min(F) + ("%s: %s (%d tiles) has no camera (stock: a camera in each room)" % (rule, a, len(F)),))


def check(m):
    out = []
    cams = cameras(m)
    check_xeno(m, xeno_layout(m), cams, out)
    check_explab(m, explab_layout(m), out)
    check_toxins(m, out)
    check_science_rooms(m, out)
    check_cargo(m, out)
    check_cameras(m, out, cams)
    return out


# ------------------------------------------------------------------------------------------------ fixes

def fix_cameras(m, log):
    hung, hung_walls = hung_faces(m)
    cams = cameras(m)
    n = 0
    for prefixes in (SCI, CARGO):
        A = {}
        for pre in prefixes:
            A.update(floor_of(m, pre))
        for a, tiles in sorted(A.items()):
            if a.startswith(NOT_ROOMS) or a == XENO:
                continue
            for i, F in enumerate(pieces(tiles)):
                if len(F) < 9 or any(c in F for c in cams):
                    continue
                name = ROOM_NAMES.get(a, a.split("/")[-1].replace("_", " ").title())
                tag = name if i == 0 else "%s %d" % (name, i + 1)
                if _cam_spot(m, F, sorted(F), cams, hung, hung_walls, doors_of(m, F), tag, network_for(a), log):
                    n += 1
    log("cameras: %d hung in science and cargo rooms" % n)
    return n


def fix_cargo(m, r, log):
    n = 0
    A = floor_of(m, "/area/quartermaster")
    lockers = [(p, a) for a, F in A.items() for p in F for o in m.get(*p).objs
               if o.path.startswith("/obj/structure/closet/secure_closet/miner")]
    if len(lockers) > 3:
        # stock: the lockers in the mining office where a map has one (Meta, Delta, MetaLake 3 of 3), else the dock
        home = "/area/quartermaster/miningoffice" if any(a == "/area/quartermaster/miningoffice" for p, a in lockers)             else "/area/quartermaster/miningdock"
        lockers.sort(key=lambda pa: (pa[1] != home, pa[0]))
        # three in all, the stock count; with both a dock and an office one stays in the other room (the audit's kit
        # lists a locker for each room type)
        keep = lockers[:3]
        other = [pa for pa in lockers if pa[1] != home]
        if other and all(pa[1] == home for pa in keep):
            keep = keep[:2] + other[:1]
        for p, a in [pa for pa in lockers if pa not in keep]:
            t = m.get(*p)
            o = next(x for x in t.objs if x.path.startswith("/obj/structure/closet/secure_closet/miner"))
            t.objs.remove(o)
            n += 1
        log("cargo: %d miner lockers past the stock 3 taken out (kept: %s)" % (len(lockers) - 3, ", ".join(
            "%d,%d" % pa[0] for pa in keep)))
    have = any(o.path.startswith("/obj/machinery/vending/wardrobe/cargo_wardrobe") for F in A.values() for p in F
               for o in m.get(*p).objs)
    if not have:
        for a in ("/area/quartermaster/storage", "/area/quartermaster/office"):
            if a not in A:
                continue
            F = pieces(A[a])[0]
            if _place_on_wall(m, F, dmm.Atom("/obj/machinery/vending/wardrobe/cargo_wardrobe"), log):
                n += 1
                break
    return n


def _place_on_wall(m, F, atom, log):
    doors = doors_of(m, F)
    before = _state(m, F, doors)
    fronts = {(d[0] + dx, d[1] + dy) for d in doors for dx, dy in N4}
    far = lambda q: -min((abs(q[0] - d[0]) + abs(q[1] - d[1]) for d in doors), default=0)  # noqa: E731
    cands = sorted((q for q in F if q not in fronts and not _dense(m.get(*q)) and not m.get(*q).objs
                    and any(_wall(m.get(q[0] + dx, q[1] + dy)) for dx, dy in N4)), key=lambda q: (far(q), q))
    for q in cands:
        m.get(*q).objs.append(atom)
        if _keeps_reach(m, F, doors, before):
            log("placed %s at %d,%d" % (atom.path.split("/")[-1], q[0], q[1]))
            return q
        m.get(*q).objs.remove(atom)
    return None


def fix_mixing(m, log):
    """The mixing lab's movable kit goals/toxins.dm find_lab() wants besides the chamber: a portable pump and a portable
    scrubber (exact type) in the lab, and a freezer on a port (Box: freezer and heater on connectors; stock 7 of 8),
    here the freezer joined head to head with its connector against a wall."""
    F0 = floor_of(m, MIXING, exact=True).get(MIXING, set())
    if not F0 or not floor_of(m, CHAMBER, exact=True):
        return 0                # no chamber, no bomb: the kit would only crowd a lab already half the stock size (f22)
    F = pieces(F0)[0]
    n = 0
    have = Counter()
    for p in F0:
        for o in m.get(*p).objs:
            if o.path == "/obj/machinery/portable_atmospherics/scrubber":
                have["scrubber"] += 1
            elif o.path.startswith("/obj/machinery/portable_atmospherics/pump"):
                have["pump"] += 1
            elif o.path.startswith("/obj/machinery/atmospherics/components/unary/thermomachine"):
                have["freezer"] += 1
    for key, path in (("pump", "/obj/machinery/portable_atmospherics/pump"), ("scrubber", "/obj/machinery/portable_atmospherics/scrubber")):
        if not have[key] and _place_on_wall(m, F, dmm.Atom(path), log):
            n += 1
    if not have["freezer"]:
        doors = doors_of(m, F)
        before = _state(m, F, doors)
        fronts = {(d[0] + dx, d[1] + dy) for d in doors for dx, dy in N4}
        done = False
        for p in sorted(F):
            if done:
                break
            if p in fronts or _dense(m.get(*p)) or AT.atoms(m.get(*p)) or m.get(*p).objs:
                continue
            for s_, v in DIRV.items():
                if not _wall(m.get(p[0] - v[0], p[1] - v[1])):
                    continue
                q = (p[0] + v[0], p[1] + v[1])
                if q not in F or q in fronts or _dense(m.get(*q)) or AT.atoms(m.get(*q)):
                    continue
                fr = dmm.Atom("/obj/machinery/atmospherics/components/unary/thermomachine/freezer", [("dir", str(s_))])
                m.get(*p).objs.append(fr)
                if not _keeps_reach(m, F, doors, before):
                    m.get(*p).objs.remove(fr)
                    continue
                m.get(*q).objs.append(dmm.Atom("/obj/machinery/atmospherics/components/unary/portables_connector/visible",
                                               [("dir", str(OPP[s_]))]))
                log("toxins: freezer at %d,%d on its port at %d,%d" % (p + q))
                n += 1
                done = True
                break
    return n


def fix(m, seed=1, log=print):
    r = random.Random("fn_science_cargo|%s" % seed)
    n = 0
    n += fix_xeno(m, xeno_layout(m), r, log)
    n += fix_explab(m, explab_layout(m), log)
    # the burn chamber is the generator's (place_burn_chamber before the networks): stamped after them it would have
    # no APC and cut the station's pipes under the mixing lab
    n += fix_mixing(m, log)
    n += fix_cameras(m, log)
    n += fix_cargo(m, r, log)
    log("fn_science_cargo: %d fixes" % n)
    return n


def _summary(issues):
    c = Counter(t.split(" ", 1)[0] for _, _, t in issues)
    return ", ".join("%s %d" % kv for kv in sorted(c.items()))


if __name__ == "__main__":
    m = dmm.read(sys.argv[1])
    before = check(m)
    print("check before: %d (%s)" % (len(before), _summary(before)))
    for x, y, t in before:
        print("  %d,%d %s" % (x, y, t))
    if len(sys.argv) > 2:
        fix(m, 1)
        after = check(m)
        print("check after: %d (%s)" % (len(after), _summary(after)))
        for x, y, t in after:
            print("  %d,%d %s" % (x, y, t))
        dmm.write(m, sys.argv[2])
        print("->", sys.argv[2])
