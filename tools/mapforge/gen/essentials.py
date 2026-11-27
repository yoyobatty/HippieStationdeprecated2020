"""The kit a room type nearly always has on the human maps, and adding what a generated room lacks.

    python tools/mapforge/gen/essentials.py              # build data/mapforge/gen/essentials.json from the corpus
    python tools/mapforge/gen/essentials.py --show bar   # the essentials of area types matching "bar"
    from gen import essentials; essentials.apply(m, log) # after dress, before connect and walkfix

A room copied whole from one human map keeps only what that one map put there. On crew 80 seed 1 (2026-11-25) the bar
had both drink dispensers but no Booze-O-Mat and no glass, so the Bot Shift's bartender never poured a drink.

An essential of an area type: an object family (forge/room_stats._family: an /obj path cut to five segments) on the
floor of at least SHARE of that type's rooms across all human maps, the type having MIN_ROOMS rooms or more. Wall
pieces, lights, alarms, doors, windows, pipes, cable, decals, effects and plain furniture (tables, chairs, beds) are
not kit (other passes own them). The path added is the family's most common full path that this codebase knows.

Placement: machines and structures on a free floor tile of the room against a wall, corners first, never in front
of a door; items on a table of the room, else on free floor. At most MAX_ADD things a room.
"""
import argparse
import json
import os
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, HERE)
from forge import dmm, kit, parse, room_stats as RS  # noqa: E402

OUT = os.path.join(parse.ROOT, "data", "mapforge", "gen", "essentials.json")
VERSION = 1
SHARE = 0.7
MIN_ROOMS = 5
MAX_ADD = 4
NOT_KIT = ("/obj/machinery/light", "/obj/machinery/power/apc", "/obj/machinery/airalarm", "/obj/machinery/firealarm",
           "/obj/item/radio/intercom", "/obj/machinery/newscaster", "/obj/machinery/camera", "/obj/structure/sign",
           "/obj/machinery/door", "/obj/structure/window", "/obj/structure/grille", "/obj/effect",
           "/obj/machinery/atmospherics", "/obj/structure/cable", "/obj/structure/disposalpipe",
           "/obj/structure/table", "/obj/structure/chair", "/obj/structure/bed", "/obj/structure/lattice",
           "/obj/machinery/power/terminal", "/obj/machinery/button", "/obj/machinery/light_switch",
           "/obj/machinery/status_display", "/obj/machinery/ai_status_display", "/obj/structure/extinguisher_cabinet",
           "/obj/structure/fireaxecabinet", "/obj/machinery/requests_console", "/obj/item/paper", "/obj/item/pen",
           "/obj/structure/noticeboard", "/obj/machinery/computer/security/telescreen", "/obj/structure/railing",
           "/obj/machinery/holopad", "/obj/item/kirbyplants", "/obj/item/twohanded/required/kirbyplants",
           "/obj/structure/curtain", "/obj/machinery/navbeacon", "/obj/docking_port", "/obj/machinery/porta_turret",
           "/obj/machinery/flasher", "/obj/machinery/doorButtons", "/obj/machinery/embedded_controller")


def build(quiet=False):
    import stamps
    rooms = defaultdict(list)           # area -> [set of families]
    full = defaultdict(Counter)         # (area, family) -> Counter(full path)
    for name in parse.humans():
        try:
            sm = parse.load(name)
        except Exception as e:          # noqa: BLE001 - a corpus map that doesn't load is skipped
            if not quiet:
                print("skip %s: %s" % (name, str(e)[:80]))
            continue
        for rm in RS.rooms(sm):
            fams = set()
            for p in rm.tiles:
                t = sm.m.get(p[0], p[1], sm.z)
                for o in (t.objs if t else []):
                    if not o.path.startswith(("/obj/machinery", "/obj/structure", "/obj/item")) or o.path.startswith(NOT_KIT):
                        continue
                    f = RS._family(o.path)
                    fams.add(f)
                    full[(rm.area, f)][o.path] += 1
            rooms[rm.area].append(fams)
    out = {}
    for area, sets in rooms.items():
        if len(sets) < MIN_ROOMS:
            continue
        cnt = Counter(f for s in sets for f in s)
        ess = []
        for f, n in cnt.most_common():
            if n < SHARE * len(sets):
                break
            path = next((p for p, _ in full[(area, f)].most_common() if stamps.resolve(p) == p), None)
            if path:
                ess.append(dict(family=f, share=round(n / float(len(sets)), 2), path=path))
        if ess:
            out[area] = dict(rooms=len(sets), kit=ess)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump(dict(version=VERSION, share=SHARE, min_rooms=MIN_ROOMS, types=out), open(OUT, "w"), indent=1)
    return out


_E = None


def table():
    global _E
    if _E is None:
        if os.path.exists(OUT):
            d = json.load(open(OUT))
            if d.get("version") == VERSION:
                _E = d["types"]
        if _E is None:
            _E = build(quiet=True)
    return _E


# what a job's work needs in the room whatever the corpus share says (the bot crew's workflows, bots_ai/goals): a bar
# pours from glasses out of the Booze-O-Mat (goals/bartender.dm; 13 of 34 stock bar rooms have one, the rest stand it
# in a neighbouring bar area)
# Telecomms' message server carries every requests console's message and every PDA message (the Bot Shift's crate drills
# never went through on crew 80 seed 1: its copied server room had the whole array but no message server, which stock
# maps stand in a room of its own as often as not).
WORK_KIT = {"/area/crew_quarters/bar": ["/obj/machinery/vending/boozeomat"],
            "/area/tcommsat/server": ["/obj/machinery/telecomms/message_server/preset"],
            # the experimentor runs from an experiment console within 3 tiles (Bot Shift f7: an explab with the
            # experimentor and no console, the scientist gave up on every experiment, 2026-11-26)
            "/area/science/explab": ["/obj/machinery/computer/rdconsole/experiment"],
            # the lab's console runs its lathe and imprinter (Bot Shift f17: a lab with both and no console, 0 parts
            # printed, no upgrades); each head's locker holds their gear (the CE's gloves and cloak, f17)
            "/area/science/lab": ["/obj/machinery/computer/rdconsole/core"],
            "/area/crew_quarters/heads/chief": ["/obj/structure/closet/secure_closet/engineering_chief"],
            "/area/crew_quarters/heads/hos": ["/obj/structure/closet/secure_closet/hos"],
            "/area/crew_quarters/heads/hor": ["/obj/structure/closet/secure_closet/RD"],
            "/area/crew_quarters/heads/cmo": ["/obj/structure/closet/secure_closet/CMO"],
            "/area/crew_quarters/heads/hop": ["/obj/structure/closet/secure_closet/hop"],
            "/area/crew_quarters/heads/captain": ["/obj/structure/closet/secure_closet/captains"],
            "/area/quartermaster/qm": ["/obj/structure/closet/secure_closet/quartermaster"]}
# partners a machine works with that forge/function.py LINKS doesn't list (it finds them nearby, not only beside it)
NEAR = {"/obj/machinery/computer/rdconsole/experiment": ("/obj/machinery/rnd/experimentor",),
        "/obj/machinery/rnd/experimentor": ("/obj/machinery/computer/rdconsole/experiment",),
        "/obj/machinery/computer/rdconsole/core": ("/obj/machinery/rnd/production/protolathe",
                                                   "/obj/machinery/rnd/production/circuit_imprinter")}

N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
EXACT_KIT = ("/obj/machinery/chem_dispenser/drinks/beer",)    # kit pieces their family's siblings don't stand in for
LINKED_SET = ("/obj/machinery/conveyor", "/obj/machinery/conveyor_switch", "/obj/structure/disposaloutlet",
              "/obj/structure/plasticflaps", "/obj/machinery/mass_driver", "/obj/machinery/button",
              "/obj/machinery/door_timer", "/obj/machinery/disposal/deliveryChute", "/obj/structure/disposalpipe")
FREE_OK = ("/obj/effect", "/obj/machinery/atmospherics", "/obj/structure/cable", "/obj/structure/disposalpipe")


def apply(m, log=print):
    """Add each room's missing essentials (by area). Returns how many things were added."""
    E = {a: dict(v, kit=list(v["kit"])) for a, v in table().items()}
    for area, paths in WORK_KIT.items():
        E.setdefault(area, dict(rooms=0, kit=[]))
        E[area]["kit"] = [dict(family=RS._family(p), share=1.0, path=p) for p in paths] + E[area]["kit"]
    by_area = defaultdict(list)
    for (x, y, z), t in m.tiles.items():
        if t.apath in E and t.tpath.startswith("/turf/open") and not t.tpath.startswith("/turf/open/space"):
            by_area[t.apath].append((x, y))
    doors = {(x, y) for (x, y, z), t in m.tiles.items() if t.has("/obj/machinery/door")}
    fronts = {(d[0] + dx, d[1] + dy) for d in doors for dx, dy in N4}
    added = Counter()
    # one of a kind on the whole station (forge/function.py UNIQUE: the nuke disk, the captain's spare, the pinpointer):
    # never added where another room has it (the captain's bedroom got a second disk, 2026-11-26)
    from forge import function as FN
    on_station = {o.path for t in m.tiles.values() for o in t.objs if o.path.startswith(FN.UNIQUE)}
    for area, tiles in sorted(by_area.items()):
        # a kit piece that must be its own exact type, not any of its family: the bar's beer dispenser (its booze)
        # beside the soda one; two soda dispensers made every bar drink unmixable (Bot Shift f19, f21: 0 drinks
        # poured). A second sibling of the family turns into it, so the room keeps its count
        for k in E[area]["kit"]:
            if k["path"] not in EXACT_KIT or any(o.path == k["path"] for p in tiles for o in m.get(*p).objs):
                continue
            sib = [(p, o) for p in sorted(tiles) for o in m.get(*p).objs
                   if RS._family(o.path) == k["family"] and o.path != k["path"]]
            if len(sib) >= 2:
                p, o = sib[-1]
                t_ = m.get(*p)
                t_.objs[t_.objs.index(o)] = dmm.Atom(k["path"], [(a_, v_) for a_, v_ in o.vars if a_ == "dir"])
                added[k["path"]] += 1
        have = {RS._family(o.path) for p in tiles for o in m.get(*p).objs}
        have |= {o.path for p in tiles for o in m.get(*p).objs if o.path in EXACT_KIT}
        # the work's machines and lockers first, then loose items, MAX_ADD of each (Atmospherics got a sheet of
        # glass, a welding mask, a gas mask and gloves, and no suit storage or canister, 2026-11-26)
        # never a piece that works only in a linked set (a conveyor belt, a disposal outlet, flaps: cargo got two
        # loose belts, 2026-11-26)
        miss_ = [k for k in E[area]["kit"] if (k["path"] not in have if k["path"] in EXACT_KIT else k["family"] not in have)
                 and not k["path"].startswith(LINKED_SET)
                 and not (k["path"].startswith(FN.UNIQUE) and any(u.startswith(k["path"]) or k["path"].startswith(u)
                                                                 for u in on_station))]
        miss = [k for k in miss_ if not k["path"].startswith("/obj/item")][:MAX_ADD] +             [k for k in miss_ if k["path"].startswith("/obj/item")][:MAX_ADD]
        if not miss:
            continue
        tset = set(tiles)

        def free(p):
            t = m.get(*p)
            return p not in fronts and p not in doors and all(o.path.startswith(FREE_OK) for o in t.objs)

        def walls(p):
            return sum(1 for dx, dy in N4 if (p[0] + dx, p[1] + dy) not in tset and
                       m.get(p[0] + dx, p[1] + dy) is not None and m.get(p[0] + dx, p[1] + dy).tpath.startswith("/turf/closed"))
        placed_paths = set()
        for k in miss:
            path = k["path"]
            if path in placed_paths or any(o.path == path for p_ in tiles for o in m.get(*p_).objs):
                continue                # the kit lists it twice under two family keys (two CE lockers, f17)
            if path.startswith("/obj/item"):
                # on a table or rack, the least loaded one; never loose on the floor (the user 2026-11-25: "no random
                # crowbars in that big open floor")
                spots = [p for p in tiles if m.get(*p).has("/obj/structure/table") or m.get(*p).has("/obj/structure/rack")]
                spots.sort(key=lambda p: (sum(1 for o in m.get(*p).objs if o.path.startswith("/obj/item")), p))
            else:
                # beside its partner when it has one in the room (forge/function.py LINKS: a nanite chamber control
                # finds its chamber on a cardinal neighbour; added apart, neither worked)
                from forge import function as FN
                mates = tuple(q for piece, groups in FN.LINKS if path == piece or path.startswith(piece + "/")
                              for g in groups for q in g) + NEAR.get(path, ())
                near = {(p[0] + dx, p[1] + dy) for p in tiles for dx, dy in N4
                        if mates and any(o.path.startswith(mates) for o in m.get(*p).objs)}
                # with a free tile in front to stand at and walk on from (a 1-tile wall alcove with a closet before it
                # held an experimentor no one could reach, Bot Shift f10, 2026-11-26)
                def front_ok(p):
                    for dx, dy in N4:
                        q = (p[0] + dx, p[1] + dy)
                        if q in tset and free(q) and sum(1 for ex, ey in N4 if (q[0] + ex, q[1] + ey) in tset
                                                         and (q[0] + ex, q[1] + ey) != p and free((q[0] + ex, q[1] + ey))) >= 1:
                            return True
                    return False
                spots = sorted((p for p in tiles if free(p) and (walls(p) >= 1 or p in near) and walls(p) <= 2
                                and front_ok(p)),
                               key=lambda p: (p not in near, -walls(p), p))
            if not spots and path in WORK_KIT.get(area, ()):
                # the work's own piece before the room's optional furniture: a table, rack or chair against a wall
                # gives its tile up (its load goes too)
                opt = [p for p in tiles if walls(p) >= 1 and p not in fronts and p not in doors
                       and any(o.path.startswith(("/obj/structure/table", "/obj/structure/rack", "/obj/structure/chair"))
                               for o in m.get(*p).objs)
                       and not any(o.path.startswith(("/obj/machinery", "/obj/structure/closet")) for o in m.get(*p).objs)]
                if opt:
                    p0 = sorted(opt, key=lambda p: (-walls(p), p))[0]
                    t0 = m.get(*p0)
                    t0.objs = [o for o in t0.objs if not o.path.startswith(("/obj/structure/table", "/obj/structure/rack",
                                                                             "/obj/structure/chair", "/obj/item"))]
                    spots = [p0]
            if not spots:
                continue
            m.get(*spots[0]).objs.append(dmm.Atom(path))
            added[path.rsplit("/", 1)[-1]] += 1
            placed_paths.add(path)
    log("essentials: %d things added to rooms missing their type's kit: %s" % (
        sum(added.values()), ", ".join("%s x%d" % kv for kv in added.most_common(12))))
    return sum(added.values())


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--show")
    ap.add_argument("--rebuild", action="store_true")
    a = ap.parse_args()
    E = build() if (a.rebuild or not os.path.exists(OUT)) else table()
    for area, v in sorted(E.items()):
        if a.show and a.show not in area:
            continue
        print("%s (%d rooms): %s" % (area, v["rooms"], ", ".join("%s %.0f%%" % (k["path"].replace("/obj/", ""), 100 * k["share"])
                                                              for k in v["kit"])))
    print("%d area types with kit" % len(E))
