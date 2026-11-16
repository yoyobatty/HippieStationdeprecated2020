"""Dressing pass in MetaStation's style (mined by style_mine.py into data/mapforge/style_MetaStation.json).

What Meta does, and what this pass does the same way:
- each department has a floor colour (medical blue, science purple, security red, engineering yellow, cargo brown,
  hydroponics green, the bar its own tile_bar); rooms are trimmed in it along the walls (halves toward a wall,
  three quarters in inside corners)
- tall furniture stands on a full tinted tile (lockers, vendors, suit storage, racks, chem machines); canisters on a
  "bot" box, portable machines on "delivery"
- the hall tile outside a department door gets the department's colour on the door side, the tile inside is full
- tables carry things: an empty table gets 1-2 items the room's kind of table carries in Meta, at Meta's offsets
- rooms get a plant in a free corner by the door; secure doors get a warning sign beside them on the hall side

Every choice is seeded so a blueprint builds the same each time.
"""
import json
import os
import random

from forge import dmm, kit
from forge.kit import CARD, DELTA, OPP, N, S, E, W

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
QUARTERS = {N: (1, 4), S: (2, 8), E: (4, 2), W: (8, 1)}  # tile_corner dirs painting each side's half
HAZARD_DECALS = ("/obj/effect/turf_decal/stripes", "/obj/effect/turf_decal/bot", "/obj/effect/turf_decal/delivery",
                 "/obj/effect/turf_decal/loading_area", "/obj/effect/turf_decal/box")
DEPT = [("/area/medical", "blue"), ("/area/science", "purple"), ("/area/security", "red"), ("/area/engine", "yellow"),
        ("/area/quartermaster", "brown"), ("/area/hydroponics", "green"), ("/area/crew_quarters/bar", "bar"),
        ("/area/bridge", "blue"), ("/area/crew_quarters/heads/cmo", "blue"), ("/area/crew_quarters/heads/hos", "red"),
        ("/area/crew_quarters/heads/chief", "yellow"), ("/area/crew_quarters/heads/hor", "purple"),
        ("/area/storage", "brown"), ("/area/janitor", "neutral"), ("/area/crew_quarters/kitchen", None),
        ("/area/hallway", "neutral")]
FULL_UNDER = ("/obj/structure/closet", "/obj/machinery/vending", "/obj/machinery/suit_storage_unit", "/obj/structure/rack",
              "/obj/machinery/chem", "/obj/structure/filingcabinet", "/obj/machinery/rnd/production")
BOT_UNDER = ("/obj/machinery/portable_atmospherics/canister", "/obj/structure/reagent_dispensers/watertank",
             "/obj/structure/reagent_dispensers/fueltank", "/obj/structure/closet/crate")
DELIVERY_UNDER = ("/obj/machinery/portable_atmospherics/pump", "/obj/machinery/portable_atmospherics/scrubber",
                  "/obj/machinery/space_heater")
SECURE_ACCESS = {"1", "2", "3", "19", "20", "40", "41", "16", "24", "10", "56", "57", "58", "55", "5"}

_style = None


def style():
    global _style
    if _style is None:
        p = os.path.join(ROOT, "data", "mapforge", "style_MetaStation.json")
        _style = json.load(open(p)) if os.path.exists(p) else {}
    return _style


def light_floor(floor):
    """Meta trims plain and white plasteel only: dark, checker, freezer floors (morgue, CMO, kitchen) stay bare."""
    return floor in ("/turf/open/floor/plasteel", "/turf/open/floor/plasteel/white")


def dept_colour(area):
    for pre, col in DEPT:
        if area == pre or area.startswith(pre + "/"):
            return col
    return "neutral"


def area_kind(a):
    parts = a.split("/")
    if len(parts) > 2 and parts[2] in ("hallway", "maintenance"):
        return "/".join(parts[:3])
    return "/".join(parts[:4]) if len(parts) > 3 else a


def has_tile_decal(t, colour, d):
    path = "/obj/effect/turf_decal/tile/%s" % colour
    for o in t.objs:
        if o.path == path and o.num("dir", 2) == d:
            return True
    return False


def paint(t, colour, dirs):
    for d in dirs:
        if not has_tile_decal(t, colour, d):
            t.objs.insert(0, dmm.Atom("/obj/effect/turf_decal/tile/%s" % colour, [("dir", str(d))] if d != 2 else []))


def item_choices(area):
    """Items Meta puts on tables in this kind of room (falls back to the department, then any office)."""
    st = style().get("table_items", {})
    ak = area_kind(area)
    for key in (ak, "/".join(ak.split("/")[:3]), "/area/crew_quarters/heads"):
        for k, c in st.items():
            if k == key or k.startswith(key + "/"):
                if sum(c.values()) >= 4:
                    return c
    return {}


def offsets_for(item):
    c = style().get("item_offsets", {}).get(item, {})
    if not c:
        return (0, 0)
    best = max(c.items(), key=lambda kv: kv[1])[0]
    x, y = best.split(",")
    return int(x), int(y)


ITEM_SKIP = ("/obj/item/stack/spacecash", "/obj/item/gun", "/obj/item/card", "/obj/item/disk", "/obj/item/key",
             "/obj/item/reagent_containers/food/snacks/grown/poppy")


def dress(b, seed=1):
    rng = random.Random(seed)
    m = b.m
    notes = []
    painted = full = items = signs = plants = 0
    for p in b.zone:
        t = m.get(*p)
        if not b.is_floor(p) or b.room.get(p) is None:
            continue
        rd = b.roomdefs[b.room[p]]
        if rd.get("dress") is False:
            continue
        own_style = p in getattr(b, "template_tiles", ())  # a fitted human room keeps its own decals
        area = rd["area"]
        colour = rd.get("trim") or dept_colour(area)
        anchors = [o for o in t.objs if o.path.startswith(("/obj/structure", "/obj/machinery")) and
                   not o.path.startswith(("/obj/machinery/door", "/obj/machinery/atmospherics", "/obj/machinery/light",
                                          "/obj/structure/cable", "/obj/structure/disposalpipe"))
                   and abs(o.num("pixel_x")) < 16 and abs(o.num("pixel_y")) < 16]
        # a work zone keeps its own marking: a tile with hazard stripes, or with a floor that is not the room's own
        # (a dark assembly floor in a white lab), gets no department colour on top (the two fight)
        hazard = any(o.path.startswith(HAZARD_DECALS) for o in t.objs)
        zoned = hazard or (isinstance(rd.get("floor"), str) and t.tpath != rd["floor"])
        # 1. under furniture
        if anchors and colour and not own_style and not zoned:
            a0 = anchors[0].path
            if a0.startswith(BOT_UNDER):
                t.objs.insert(0, dmm.Atom("/obj/effect/turf_decal/bot"))
                full += 1
            elif a0.startswith(DELIVERY_UNDER):
                t.objs.insert(0, dmm.Atom("/obj/effect/turf_decal/delivery"))
                full += 1
            elif a0.startswith(FULL_UNDER) and rd.get("floor", "").startswith("/turf/open/floor/plasteel") \
                    and "cafeteria" not in rd.get("floor", "") and "freezer" not in rd.get("floor", ""):
                paint(t, colour if colour != "bar" else "neutral", (1, 2, 4, 8))
                full += 1
        # 2. trim along walls (rooms that asked for it already have it from build.decals)
        if rd.get("trim") is None and colour not in (None, "neutral", "bar") and light_floor(rd.get("floor", "")) \
                and rd.get("auto_trim", True) and not own_style and not zoned:
            for d in CARD:
                q = b.nb(p, d)
                if b.kind(q) != "floor" or (q in b.zone and b.area_of(q) != area):
                    paint(t, colour, QUARTERS[d])
                    painted += 1
        # 3. empty tables get what Meta's tables carry
        if any(o.path.startswith("/obj/structure/table") for o in t.objs) and \
                not any(o.path.startswith("/obj/item") or o.path.startswith(("/obj/machinery/microwave", "/obj/machinery/reagentgrinder",
                                                                              "/obj/machinery/cell_charger", "/obj/machinery/computer",
                                                                              "/obj/machinery/door")) for o in t.objs):
            if rd.get("table_items", True) and rng.random() < 0.8:
                ch = {k: v for k, v in item_choices(area).items() if not k.startswith(ITEM_SKIP)}
                if ch:
                    keys = list(ch)
                    n = 1 if rng.random() < 0.55 else 2
                    picked = set()
                    for _ in range(n):
                        it = rng.choices(keys, weights=[ch[k] for k in keys])[0]
                        if it in picked:
                            continue
                        picked.add(it)
                        x, y = offsets_for(it)
                        vs = []
                        if x:
                            vs.append(("pixel_x", str(x)))
                        if y:
                            vs.append(("pixel_y", str(y)))
                        t.objs.append(dmm.Atom(it, vs))
                        items += 1
                        if it == "/obj/item/paper_bin" and "/obj/item/pen" not in picked:
                            t.objs.append(dmm.Atom("/obj/item/pen"))
                            picked.add("/obj/item/pen")
    # 4. department doors: colour the hall tile outside, full tile inside; warning sign by secure doors
    for p in b.zone:
        t = m.get(*p)
        door = next((o for o in t.objs if o.path.startswith("/obj/machinery/door/airlock")), None)
        if not door or b.room.get(p) is None:
            continue
        area = b.roomdefs[b.room[p]]["area"]
        colour = b.roomdefs[b.room[p]].get("trim") or dept_colour(area)
        for d in CARD:
            q = b.nb(p, d)
            qt = m.get(*q)
            if qt is None or not qt.tpath.startswith("/turf/open/floor/plasteel"):
                continue
            outside = qt.apath.startswith("/area/hallway") and not area.startswith("/area/hallway")
            if outside and colour not in (None, "neutral", "bar") and (q in b.zone or getattr(b.bp, "DRESS_HALL_FRONT", False)):
                if q not in b.zone:
                    b.outside_edits.append(q)
                paint(qt, colour, QUARTERS[OPP[d]])
                painted += 1
                acc = (door.get("req_access_txt") or door.get("req_one_access_txt") or "").strip('"')
                if acc and set(acc.split(";")) & SECURE_ACCESS and rng.random() < 0.7:
                    # beside the door on the hall side, on the wall
                    for side in [x for x in CARD if x not in (d, OPP[d])]:
                        w = b.nb(p, side)
                        spot = b.nb(w, d)
                        st = m.get(*spot)
                        if b.solid(w) and st is not None and st.tpath.startswith("/turf/open") \
                                and not any(o.path.startswith("/obj/structure/sign") for o in st.objs):
                            mk = kit.MOUNT["sign"][OPP[d]]  # the wall w is behind the spot, back toward the door
                            vs = [(k, str(v)) for k, v in (("pixel_x", mk[1]), ("pixel_y", mk[2])) if v is not None]
                            st.objs.append(dmm.Atom("/obj/structure/sign/warning/securearea", vs))
                            signs += 1
                            break
    # 5. a plant in a free corner of each room, near its door
    for rc, rd in b.roomdefs.items():
        if rd.get("dress") is False or rd.get("plant") is False or rd["area"].startswith("/area/hallway"):
            continue
        tiles = [p for p in b.zone if b.room.get(p) == rc and b.is_floor(p)]
        corners = [p for p in tiles if len(b.wall_sides(p)) >= 2 and not kit.dense(m.get(*p).objs)
                   and not any(o.path.startswith(("/obj/item", "/mob", "/obj/effect/landmark", "/obj/machinery")) for o in m.get(*p).objs)
                   and not any(m.get(*b.nb(p, d)) is not None and m.get(*b.nb(p, d)).has("/obj/machinery/door") for d in CARD)]
        if corners and len(tiles) >= 12:
            doors = [q for q in b.zone if m.get(*q).has("/obj/machinery/door/airlock")
                     and any(b.room.get(b.nb(q, d)) == rc for d in CARD)]
            c = min(corners, key=lambda p: min((abs(p[0] - q[0]) + abs(p[1] - q[1]) for q in doors), default=0) + rng.random())
            m.get(*c).objs.append(dmm.Atom("/obj/item/twohanded/required/kirbyplants/random"))
            plants += 1
    # 6. companions: what hangs over a piece of furniture in this kind of room on the human maps (a mirror over a
    #    washroom or treatment-room sink, a flasher over a cell bed), when they do it at least half the time
    from forge import habits
    from forge.corpus import mount_side
    H = habits.habits()
    comps = 0
    given = {}
    PER_OBJECT = ("/obj/structure/mirror", "/obj/machinery/flasher", "/obj/machinery/defibrillator_mount")
    SKIP = ("/obj/machinery/light_switch", "/obj/structure/extinguisher_cabinet", "/obj/machinery/newscaster",
            "/obj/machinery/status_display", "/obj/item/radio/intercom")
    for p in sorted(b.zone):
        t = m.get(*p)
        if t is None or b.room.get(p) is None or b.roomdefs[b.room[p]].get("dress") is False:
            continue
        an = [o for o in t.objs if o.path.startswith(("/obj/structure", "/obj/machinery")) and not o.path.startswith(
            ("/obj/machinery/door", "/obj/machinery/atmospherics", "/obj/machinery/light", "/obj/structure/cable",
             "/obj/structure/disposalpipe", "/obj/machinery/power/apc", "/obj/machinery/airalarm", "/obj/machinery/firealarm",
             "/obj/machinery/camera")) and not (abs(o.num("pixel_x")) >= 16 or abs(o.num("pixel_y")) >= 16)]
        if not an:
            continue
        a0 = an[0]
        rt = habits.room_type(b.roomdefs[b.room[p]]["area"])
        key = a0.path + "@" + rt
        if H["companion_n"].get(key, 0) < 3:
            continue
        walls = [d for d in CARD if b.solid(b.nb(p, d))]
        if not walls:
            continue
        # the wall the piece itself hangs on (sinks) or the only wall
        side = mount_side(a0) if (abs(a0.num("pixel_x")) >= 8 or abs(a0.num("pixel_y")) >= 8) else walls[0]
        if side not in walls:
            side = walls[0]
        for c, rate in sorted(H["companions"].get(key, {}).items(), key=lambda kv: -kv[1]):
            if rate < 0.5 or c.startswith(SKIP) or (p[0], p[1], side) in b.faces:
                continue
            # one per room for room-level pieces; only per-object pieces (a mirror per sink, a flasher per bed) repeat
            if not c.startswith(PER_OBJECT) and c in given.get(b.room[p], set()):
                continue
            given.setdefault(b.room[p], set()).add(c)
            if any(o.path == c for o in t.objs):
                continue
            offs = {k: v for k, v in H["companion_offsets"].get(c, {}).items() if k.startswith("%d:" % side)}
            if offs:
                px, py = map(int, max(offs.items(), key=lambda kv: kv[1])[0].split(":")[1].split(","))
            else:
                d0, px, py = kit.MOUNT["sign"][side]
                px, py = px or 0, py or 0
            vs = [(k, str(v)) for k, v in (("pixel_x", px), ("pixel_y", py)) if v]
            t.objs.append(dmm.Atom(c, vs))
            b.faces.add((p[0], p[1], side))
            comps += 1
            break
    # 7. the sign a room type gets beside its door, outside (EXAM, biohazard, no smoking...)
    dsigns = 0
    for p in sorted(b.zone):
        t = m.get(*p)
        if not t.has("/obj/machinery/door/airlock"):
            continue
        for d in CARD:
            inner, outer = b.nb(p, d), b.nb(p, OPP[d])
            it, ot = m.get(*inner), m.get(*outer)
            if it is None or ot is None or it.apath == ot.apath:
                continue
            ss = H["door_signs"].get(habits.room_type(it.apath), {})
            best = max(ss.items(), key=lambda kv: kv[1], default=(None, 0))
            if not best[0] or best[1] < 0.3:
                continue
            for side in [x for x in CARD if x not in (d, OPP[d])]:
                w = b.nb(p, side)
                spot = b.nb(w, OPP[d])
                st = m.get(*spot)
                if b.solid(w) and st is not None and st.tpath.startswith("/turf/open") and (spot in b.zone)                         and not any(o.path.startswith("/obj/structure/sign") for o in st.objs) and (spot[0], spot[1], d) not in b.faces:
                    mk = kit.MOUNT["sign"][d]  # the wall w is behind the spot, toward the room
                    st.objs.append(dmm.Atom(best[0], [(k, str(v)) for k, v in (("pixel_x", mk[1]), ("pixel_y", mk[2])) if v is not None]))
                    b.faces.add((spot[0], spot[1], d))
                    dsigns += 1
                    break
    notes.append("dressing: %d companions (mirror over a sink...), %d door signs" % (comps, dsigns))
    notes.append("dressing: %d trims/edges painted, %d tiles under furniture marked, %d table items, %d signs, %d plants"
                 % (painted, full, items, signs, plants))
    return notes
