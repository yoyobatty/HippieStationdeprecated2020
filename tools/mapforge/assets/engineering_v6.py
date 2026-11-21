"""Room assets for the v6 station's Engineering: engineering.py's rooms plus the supermatter stamp and atmos.

The engine is Meta's supermatter block (station/to_dmm.engine_block), turned a quarter counter-clockwise so its hull
wall lies on Engineering's east hull and its cooling coil sits out in space beyond it (plan/canvas.py lays the coil).
ENGINE_ANCHOR is the map tile of the block's (u 0, v 0): map x = anchor x - v, map y = anchor y + u.

  break     the public's way in off arm E: vendors, a table with a charger, seats, the noticeboard
  checkpoint one officer behind glass over the break room
  smes      three SMES with their terminals on the wall
  gravgen   the gravity generator in the middle of its room, the control panel by the door
  control   engine monitors, the supermatter and power consoles, hardsuits
  lockers   the engineers' lockers, the vendors, the tool racks
  storage   secure storage: emitters, field generators, canisters
  atmos     the front desk, the main floor with canisters, pumps and scrubbers, the gas chambers (gas turfs)
"""
from forge.proc.place import Kit, cell, dist
from assets.engineering import ASSETS as V1
from assets.science import TABLE, CHAIR, PAPER, PLANT_K, BIN, BOT, SEAT, one, hang, seat_at
from assets.security_v6 import desk_station

ENGINE_ANCHOR = (146, 60)
ENGINE_TURNS = 3            # clockwise quarter turns (= one counter-clockwise)
SM_AREA = "/area/engine/supermatter"


def engine_cells():
    """Map tile -> (turf atom, area, [atoms]) for the block's station side (v >= 0), atoms turned."""
    import os
    import sys
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "station"))
    import to_dmm as T
    out = {}
    for (u, v), (turf, area, objs) in T.engine_block().items():
        if v < 0:
            continue
        p = (ENGINE_ANCHOR[0] - v, ENGINE_ANCHOR[1] + u)
        out[p] = (T.rot_engine_atom(turf, ENGINE_TURNS) if turf.get("dir") else turf, area,
                  [T.rot_engine_atom(o, ENGINE_TURNS) for o in objs])
    return out


def engine_prefab(supermatter):
    """A shell.stamp prefab of the block's cells in the supermatter area (supermatter=True) or the rest."""
    cells = engine_cells()
    ax, ay = ENGINE_ANCHOR
    m = {}
    for (x, y), (turf, area, objs) in cells.items():
        if (area == SM_AREA) != supermatter:
            continue
        obj = [(o.path, dict(o.vars)) if o.vars else o.path for o in objs]
        if turf.path.startswith("/turf/closed"):
            # Meta runs pipes through these walls (the coil's HE junctions, the chamber feeds): they come along
            spec = {"turf": "rwall" if "r_wall" in turf.path else "wall", "obj": obj}
        else:
            spec = {"floor": (turf.path, dict(turf.vars)) if turf.vars else turf.path, "obj": obj}
        m[(x - ax, y - ay)] = dict(raw=spec)
    if not supermatter:
        for (x, y), spec in ENGINE_CUTS.items():
            if (x - ax, y - ay) in m:
                m[(x - ax, y - ay)] = dict(raw=spec)
    return m


# cuts into the stamp's walls (map tiles): the SMES room's back door, engine control's window over the engine floor
ENGINE_CUTS = {(137, 77): {"floor": "/turf/open/floor/plasteel", "obj": [
    ("/obj/machinery/door/airlock/engineering", {"name": "Engineering SMES", "req_access_txt": "10"}),
    "/obj/machinery/door/firedoor"]}}
for _y in (66, 67, 68):
    ENGINE_CUTS[(129, _y)] = {"floor": "/turf/open/floor/plating",
                              "obj": ["/obj/effect/spawner/structure/window/reinforced"]}


# ================================================================================================= rooms
def break_room(R):
    V1["break"](R)
    R.place(PLANT_K, must=False)


def checkpoint(R):
    V1["checkpoint"](R)


def smes(R):
    door = R.doors()[0]
    R.run([one("SMES", "SM", "/obj/machinery/power/smes/engineering", decal=[BOT])] * 3, far=door)
    R.place(one("power monitor", "C", ("/obj/machinery/computer/monitor", {"dir": "IN"})), near=door, must=False)


def gravgen(R):
    # the generator stands in the middle of its room: the machine's tile is the bottom centre of its 3x3
    mid = (126, 74)         # the 3x3 grows up from this tile (gravitygenerator.dm:147): rows 74-76 of 72-78
    R.put(mid, "obj", obj=["/obj/machinery/gravity_generator/main/station"])
    R.reserve([(mid[0] + dx, mid[1] + dy) for dx in (-1, 0, 1) for dy in (0, 1, 2)], "obj")
    R.place(hang("radiation sign", "sign", "/obj/structure/sign/warning/radiation"), must=False)


def control(R):
    V1["control"](R)
    R.place(one("supermatter monitor", "C", ("/obj/machinery/computer/station_alert", {"dir": "IN"})),
            must=False)


def lockers(R):
    V1["foyer"](R)


def storage(R):
    V1["storage"](R)


def atmos_desk(R):
    seat = desk_station(R, "hall", ("/obj/structure/chair/office", "/obj/effect/landmark/start/atmospheric_technician"),
                        ["/obj/machinery/computer/atmos_alert"])
    R.place(one("atmos locker", "L", "/obj/structure/closet/secure_closet/atmospherics"), must=False)
    R.place(one("atmos wardrobe", "W", "/obj/machinery/vending/wardrobe/atmos_wardrobe"), must=False)


def atmos_lockers(R):
    R.run([one("atmos locker", "L", "/obj/structure/closet/secure_closet/atmospherics")] * 2)
    R.run([one("fire closet", "L", "/obj/structure/closet/firecloset"),
           one("suit", "SU", "/obj/machinery/suit_storage_unit/atmos")])


def atmos_main(R):
    # canisters on the walls, the portable pumps and scrubbers ready, the middle clear for pipework
    R.run([one("canister", "CN", "/obj/machinery/portable_atmospherics/canister/%s" % g, decal=[BOT]) for g in
           ("oxygen", "oxygen", "nitrogen", "nitrogen", "carbon_dioxide", "toxins", "nitrous_oxide", "air")])
    R.run([one("pump", "pp", "/obj/machinery/portable_atmospherics/pump", decal=[BOT]),
           one("pump", "pp", "/obj/machinery/portable_atmospherics/pump", decal=[BOT]),
           one("scrubber", "sc", "/obj/machinery/portable_atmospherics/scrubber", decal=[BOT]),
           one("scrubber", "sc", "/obj/machinery/portable_atmospherics/scrubber", decal=[BOT])])
    R.place(one("tools", "t", TABLE, "/obj/item/analyzer", "/obj/item/wrench", "/obj/item/pipe_dispenser",
                back="wall"), must=False)
    R.place(one("pipe dispenser", "PD", "/obj/machinery/pipedispenser"), must=False)
    R.place(hang("requests console", "requests_console", "/obj/machinery/requests_console",
                 {"department": "Atmospherics", "departmentType": 3}), must=False)


def chamber(gas):
    def run(R):
        for p in R.tiles:
            R.put(p, None, floor="/turf/open/floor/engine/%s" % gas)
    return run


def engine_room_old(R):
    # the walkway round the stamped block: fire closets and the radiation gear by the door
    doors = R.doors("enghall") or R.doors()
    if not doors:
        return
    door = doors[0]
    R.run([one("rad closet", "L", "/obj/structure/closet/radiation"), one("fire closet", "L", "/obj/structure/closet/firecloset")],
          near=door)
    R.place(hang("radiation sign", "sign", "/obj/structure/sign/warning/radiation"), near=door, must=False)


ASSETS = {"break": break_room, "checkpoint": checkpoint, "smes": smes, "gravgen": gravgen, "control": control,
          "lockers": lockers, "storage": storage, "ce": V1["ce"], "workshop": V1["workshop"], "engine": engine_room_old,
          "atmosdesk": atmos_desk, "atmoslockers": atmos_lockers, "atmos": atmos_main,
          "n2": chamber("n2"), "o2": chamber("o2"), "co2": chamber("co2"), "plasma": chamber("plasma"),
          "enghall": lambda R: None}


# ================================================================================================= review 1 (11-21)
def engine_room(R):
    # the startup floor below the block: the gas the crystal starts on, rad gear and tanks, hazard stripes
    doors = R.doors("enghall") or R.doors()
    door = doors[0] if doors else R.room.attrs["heart"]
    R.run([one("nitrogen", "CN", "/obj/machinery/portable_atmospherics/canister/nitrogen", decal=[BOT])] * 3 +
          [one("plasma", "CN", "/obj/machinery/portable_atmospherics/canister/toxins", decal=[BOT])])
    R.run([one("rad closet", "L", "/obj/structure/closet/radiation"),
           one("rad closet", "L", "/obj/structure/closet/radiation"),
           one("tanks", "TD", "/obj/structure/tank_dispenser")], near=door)
    R.place(one("fire closet", "L", "/obj/structure/closet/firecloset"), must=False)
    R.place(hang("radiation sign", "sign", "/obj/structure/sign/warning/radiation"), near=door, must=False)
    for p in R.tiles:
        if any(q not in R.tiles and R.geo.kind.get(q) == "raw" for q in ((p[0], p[1] + 1),)):
            R.put(p, None, decal=[("/obj/effect/turf_decal/stripes/line", {"dir": 1})])


def workshop2(R):
    V1["workshop"](R)
    R.run([one("engivend", "V", "/obj/machinery/vending/engivend"), one("tools", "V", "/obj/machinery/vending/tool"),
           one("wardrobe", "V", "/obj/machinery/vending/wardrobe/engi_wardrobe"),
           one("lathe", "TF", "/obj/machinery/rnd/production/protolathe/department/engineering", decal=[BOT])])


ASSETS.update({"engine": engine_room, "workshop": workshop2, "airmix": chamber("air")})


# ================================================================================================= review 2 (11-21)
def atmos_main2(R):
    # the atmos techs' gear on the west wall by the desk door (lost when the lockers room merged in)
    desk = (R.doors("atmosdesk") or R.doors())[0]
    R.run([one("atmos locker", "L", "/obj/structure/closet/secure_closet/atmospherics")] * 3 +
          [one("fire closet", "L", "/obj/structure/closet/firecloset"),
           one("atmos suit", "SU", "/obj/machinery/suit_storage_unit/atmos")], near=desk)
    atmos_main(R)


def engine_room2(R):
    engine_room(R)
    # the rest of the startup floor along the strip: suits for the engine, the tank dispenser, a spare canister bank
    R.run([one("engine suit", "SU", "/obj/machinery/suit_storage_unit/engine"),
           one("engine suit", "SU", "/obj/machinery/suit_storage_unit/engine"),
           one("oxygen", "CN", "/obj/machinery/portable_atmospherics/canister/oxygen", decal=[BOT]),
           one("nitrogen", "CN", "/obj/machinery/portable_atmospherics/canister/nitrogen", decal=[BOT])],
          near=(R.doors("enghall") or R.doors())[0])


def lockers2(R):
    lockers(R)
    R.run([one("engineer locker", "L", "/obj/structure/closet/secure_closet/engineering_personal")] * 2)


def break2(R):
    break_room(R)
    # a table island for the seats to face
    dwall = R.geo.field("dwall")
    R.place(Kit("break table", [cell(0, 0, TABLE, "/obj/item/storage/fancy/donut_box", label="t"),
                                cell(1, 0, TABLE, label="t"),
                                (0, 1, dict(obj=[(CHAIR, {"dir": "OUT"})], open=True, seat=True, label="c")),
                                (1, 1, dict(obj=[(CHAIR, {"dir": "OUT"})], open=True, seat=True, label="c")),
                                (0, -1, dict(obj=[(CHAIR, {"dir": "IN"})], open=True, seat=True, label="c")),
                                (1, -1, dict(obj=[(CHAIR, {"dir": "IN"})], open=True, seat=True, label="c"))],
                use=[], back=None, mirror=False), near=R.room.attrs["heart"], must=False,
            need=lambda pl: all(dwall.get(pl.at(u, 0), 0) >= 1 for u in (0, 1)))


ASSETS.update({"atmos": atmos_main2, "engine": engine_room2, "lockers": lockers2, "break": break2})


# ================================================================================================= review 3 (11-21)
from assets.engineering import button  # noqa: E402
def gravgen3(R):
    gravgen(R)
    # the notch south-east of the generator: the rad closet and a sign, not a dead corner (review 3 #4)
    if (130, 71) in R.tiles:
        R.put((130, 71), "obj", obj=["/obj/structure/closet/radiation"])
    R.place(one("rad closet", "L", "/obj/structure/closet/radiation"), near=R.doors()[0], must=False)


def control3(R):
    # the alert row and the engine cameras looking out over the engine floor through the east window; a power
    # monitor, not a second alert console; the suits and tanks live on the engine floor now (review 3 #2)
    from assets.engineering import CONTROL
    door = (R.doors("enghall") or R.doors())[0]
    for y in (66, 67, 68):
        R.faces[((128, y), 4)] = "window"       # the cut below: nothing hangs on it
    row = R.place(CONTROL, far=door, must=False)
    chair = row.at(1, 1) if row else R.room.attrs["heart"]
    R.place(hang("engine cameras", "telescreen", "/obj/machinery/computer/security/telescreen/engine",
                 {"network": 'list("engine","singularity")'}), near=chair, must=False)
    R.place(one("power monitor", "C", ("/obj/machinery/computer/monitor", {"dir": "IN"})), must=False)
    R.place(hang("intercom", "intercom", "/obj/item/radio/intercom"), near=chair, must=False)
    # the window in the east wall over the engine floor (review 3 #2)
    for y in (66, 67, 68):
        R.put((129, y), None, floor="/turf/open/floor/plating", obj=["/obj/effect/spawner/structure/window/reinforced"])


def atmos_desk3(R):
    atmos_desk(R)
    R.place(button("Desk Shutters", {"id": "atmosdesk", "req_access_txt": "24"}), must=False)


def break3(R):
    # the public's way in: vendors on the walls, the table island with its seats, a plant, the noticeboard; no
    # loose tools on a public table (review 3 #9)
    door = (R.doors("hall") or R.doors())[0]
    R.run([one("snacks", "V", "/obj/machinery/vending/snack/random"),
           one("cola", "V", "/obj/machinery/vending/cola/random"),
           one("coffee", "V", "/obj/machinery/vending/coffee")], far=door)
    dwall = R.geo.field("dwall")
    R.place(Kit("break table", [cell(0, 0, TABLE, "/obj/item/storage/fancy/donut_box", label="t"),
                                cell(1, 0, TABLE, "/obj/machinery/cell_charger", label="t"),
                                (0, 1, dict(obj=[(CHAIR, {"dir": "OUT"})], open=True, seat=True, label="c")),
                                (1, 1, dict(obj=[(CHAIR, {"dir": "OUT"})], open=True, seat=True, label="c")),
                                (0, -1, dict(obj=[(CHAIR, {"dir": "IN"})], open=True, seat=True, label="c")),
                                (1, -1, dict(obj=[(CHAIR, {"dir": "IN"})], open=True, seat=True, label="c"))],
                use=[], back=None, mirror=False), near=R.room.attrs["heart"], must=False,
            need=lambda pl: all(dwall.get(pl.at(u, 0), 0) >= 1 for u in (0, 1)))
    R.place(PLANT_K, near=door, must=False)
    R.place(hang("noticeboard", "noticeboard", "/obj/structure/noticeboard"), must=False)


def engine_room3(R):
    # keep the row under the stamp's doors and windows clear: nothing in a doorway, nothing against glass
    R.reserve([(x, 59) for x in range(133, 146)], "open")
    engine_room2(R)
    # the strip: backup generators, fuel and water, a workbench of meson glasses and cells (review 3 #5)
    R.run([one("pacman", "PG", "/obj/machinery/power/port_gen/pacman", decal=[BOT]),
           one("pacman", "PG", "/obj/machinery/power/port_gen/pacman", decal=[BOT]),
           one("fuel", "FT", "/obj/structure/reagent_dispensers/fueltank"),
           one("water", "WT", "/obj/structure/reagent_dispensers/watertank"),
           one("bench", "t", TABLE, "/obj/item/clothing/glasses/meson/engine", "/obj/item/clothing/glasses/meson/engine",
               "/obj/item/stock_parts/cell/high", back="wall"),
           one("bench", "t", TABLE, "/obj/item/storage/toolbox/mechanical", "/obj/item/stack/cable_coil",
               "/obj/item/geiger_counter", back="wall")], far=(R.doors("enghall") or R.doors())[0])


ASSETS.update({"gravgen": gravgen3, "control": control3, "atmosdesk": atmos_desk3, "break": break3,
               "engine": engine_room3})
