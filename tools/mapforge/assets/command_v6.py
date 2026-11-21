"""Room assets for the v6 station's Command: the bridge in the core, its vault and AI upload, the HoP's office, the
conference room, the captain's office and quarters; EVA, the teleporter and tech storage in the north wing.

Lessons from the v6 reviews are built in: the essential machines are must=True, chairs face their tables and
consoles with kit-relative dirs, desk stations sit behind their windoors (security_v6.desk_station).
"""
from forge.proc.place import Kit, cell, dist
from assets.science import TABLE, CHAIR, PAPER, PLANT_K, BIN, BOT, one, hang, seat_at, apart
from assets.security import button
from assets.security_v6 import desk_station

WOOD = "/obj/structure/table/wood"
CARPET = "/turf/open/floor/carpet"


def console(name, path):
    return one(name, "C", (path, {"dir": "IN"}))


BRIDGE_ROW = [console("communications", "/obj/machinery/computer/communications"),
              console("crew monitor", "/obj/machinery/computer/crew"),
              console("cameras", "/obj/machinery/computer/security"),
              console("ID console", "/obj/machinery/computer/card"),
              console("power monitor", "/obj/machinery/computer/monitor"),
              console("station alerts", "/obj/machinery/computer/station_alert")]


def bridge(R):
    # Meta's bridge: the consoles in a row on the far wall looking out over the ring, the captain's chair in the
    # middle facing them, the comms and records within a step; the doors from the ring behind
    door = (R.doors("hall") or R.doors())[0]
    row = R.run(BRIDGE_ROW, far=door)
    heart = R.room.attrs["heart"]
    R.mark(heart, ("/obj/structure/chair/comfy/black", {"dir": 1}))
    R.run([one("bridge locker", "L", "/obj/structure/closet/emcloset"),
           one("fire locker", "L", "/obj/structure/closet/firecloset")], near=door)
    R.place(one("bridge table", "t", WOOD, "/obj/item/storage/firstaid/regular", "/obj/item/radio", back="wall"),
            must=False)
    R.place(PLANT_K, near=door, must=False)
    R.place(PLANT_K, near=door, must=False)
    R.place(hang("keycard", "button", "/obj/machinery/keycard_auth"), must=False)
    R.place(hang("requests console", "requests_console", "/obj/machinery/requests_console",
                 {"department": "Bridge", "departmentType": 5, "announcementConsole": 1}), must=False)
    R.mark((heart[0], heart[1] - 1), "/obj/machinery/holopad")


def vault(R):
    # the station's vault: the self-destruct, the ore silo every ORM and lathe draws on, the safe and the coin crates
    R.place(one("self-destruct", "SD", "/obj/machinery/nuclearbomb/selfdestruct", back="any"))
    R.place(one("ore silo", "OS", "/obj/machinery/ore_silo", decal=[BOT]))
    R.place(one("safe", "SF", "/obj/structure/safe"), must=False)
    R.run([one("gold", "CR", "/obj/structure/closet/crate/goldcrate"),
           one("silver", "CR", "/obj/structure/closet/crate/silvercrate")])
    R.place(one("files", "F", "/obj/structure/filingcabinet", back="any"), must=False)


def upload(R):
    # the AI upload: the two upload consoles, the law boards on a table, turrets in the corners
    door = R.doors()[0]
    R.run([console("AI upload", "/obj/machinery/computer/upload/ai"),
           console("borg upload", "/obj/machinery/computer/upload/borg")], far=door)
    R.place(one("law boards", "t", TABLE, "/obj/item/aiModule/core/full/asimov", "/obj/item/aiModule/supplied/quarantine",
                "/obj/item/aiModule/reset", back="wall"))
    corners = sorted(R.tiles, key=lambda p: -dist(p, door))[:2]
    for p in corners:
        if p not in R.geo.taken:
            R.put(p, "obj", obj=["/obj/machinery/porta_turret/ai"])


def hop(R):
    # the HoP serves the queue over the windoor onto the ring, ID console at hand, Ian underfoot
    seat = desk_station(R, "hall", ("/obj/structure/chair/office", "/obj/effect/landmark/start/head_of_personnel"),
                        ["/obj/machinery/computer/card", "/obj/machinery/computer/secure_data"])
    chair = seat or R.room.attrs["heart"]
    R.place(one("HoP locker", "L", "/obj/structure/closet/secure_closet/hop"), far=chair)
    R.place(one("photocopier", "PC", "/obj/machinery/photocopier", back="any"), must=False)
    R.place(one("paperwork", "t", WOOD, PAPER, "/obj/item/pen", "/obj/item/stamp/hop", back="wall"), near=chair,
            must=False)
    R.place(one("bed", "bd", "/obj/structure/bed/dogbed/ian", back="any"), far=chair, must=False)
    free = [p for p in R.tiles if R.free(p) and p not in R.front]
    if free:
        R.mark(min(free, key=lambda p: (dist(p, chair), p)), "/mob/living/simple_animal/pet/dog/corgi/Ian")
    R.place(hang("requests console", "requests_console", "/obj/machinery/requests_console",
                 {"department": "Head of Personnel's Desk", "departmentType": 5, "announcementConsole": 1}),
            near=chair, must=False)


def conference(R):
    dwall = R.geo.field("dwall")
    R.place(Kit("conference table", [cell(0, u, WOOD, *([PAPER] if u == 1 else []), label="t") for u in range(3)] +
                [(du, u, dict(obj=[(CHAIR, {"dir": "A-" if du > 0 else "A+"})], open=True, seat=True, label="c"))
                 for u in range(3) for du in (1, -1)], use=[], back=None, mirror=False),
            near=R.room.attrs["heart"], must=False,
            need=lambda pl: all(dwall.get(pl.at(0, u), 0) >= 1 for u in range(3)))
    R.place(PLANT_K, must=False)


CAP_DESK = Kit("captain's desk", [
    cell(0, 0, WOOD, PAPER, "/obj/item/pen/fountain/captain", "/obj/item/stamp/captain", label="t"),
    cell(1, 0, WOOD, "/obj/item/flashlight/lamp/green", label="t"),
    (0, 1, dict(obj=[("/obj/structure/chair/comfy/black", {"dir": "OUT"}), "/obj/effect/landmark/start/captain"],
                open=True, seat=True, label="c")),
], use=[(0, -1), (1, -1)], back=None)


def captain(R):
    door = (R.doors("bridge") or R.doors())[0]
    dwall = R.geo.field("dwall")
    desk = R.place(CAP_DESK, need=lambda pl: dist(pl.at(0, 1), door) > dist(pl.at(0, -1), door)
                   and dwall.get(pl.at(0, 0), 0) >= 1 and dwall.get(pl.at(1, 0), 0) >= 1, must=False)
    desk = desk or R.place(CAP_DESK, need=lambda pl: dist(pl.at(0, 1), door) > dist(pl.at(0, -1), door))
    chair = desk.at(0, 1) if desk else door
    R.run([console("communications", "/obj/machinery/computer/communications"),
           console("ID console", "/obj/machinery/computer/card")], near=chair)
    R.place(one("captain's case", "DC", "/obj/structure/displaycase/captain"), must=False)
    R.place(PLANT_K, must=False)
    R.place(hang("keycard", "button", "/obj/machinery/keycard_auth"), near=chair, must=False)


def quarters(R):
    door = R.doors()[0]
    R.place(one("bed", "bd", "/obj/structure/bed", "/obj/item/bedsheet/captain", back="any"), far=door)
    R.place(one("captain locker", "L", "/obj/structure/closet/secure_closet/captains"))
    R.place(one("captain suit", "SU", "/obj/machinery/suit_storage_unit/captain"), must=False)
    R.place(one("dresser", "DR", "/obj/structure/dresser"), must=False)
    R.place(one("toilet", "WC", ("/obj/structure/toilet", {"dir": "IN"})), must=False)
    for p in R.tiles:
        R.put(p, None, floor=CARPET) if p not in R.geo.taken else None


def eva(R):
    # suits on one wall, jetpacks and magboots on racks on the other, the middle clear to suit up
    door = (R.doors("hall") or R.doors())[0]
    R.run([one("EVA suit", "SU", "/obj/machinery/suit_storage_unit/standard_unit")] * 4, far=door)
    R.run([one("jetpacks", "r", "/obj/structure/rack", "/obj/item/tank/jetpack/carbondioxide",
               "/obj/item/tank/jetpack/carbondioxide", back="wall"),
           one("magboots", "r", "/obj/structure/rack", "/obj/item/clothing/shoes/magboots",
               "/obj/item/clothing/shoes/magboots", back="wall"),
           one("oxygen", "r", "/obj/structure/rack", "/obj/item/tank/internals/oxygen",
               "/obj/item/tank/internals/oxygen", "/obj/item/clothing/mask/breath", back="wall")])
    R.place(one("tools", "t", TABLE, "/obj/item/storage/toolbox/mechanical", "/obj/item/multitool", back="wall"),
            must=False)


def teleporter(R):
    # the console, the station and the hub in one line, the pad out in the room
    door = (R.doors("hall") or R.doors())[0]
    R.place(Kit("teleporter", [cell(0, 0, ("/obj/machinery/computer/teleporter", {"dir": "IN"}), label="TC"),
                               cell(1, 0, ("/obj/machinery/teleport/station", {"dir": "IN"}), label="TS"),
                               cell(2, 0, ("/obj/machinery/teleport/hub", {"dir": "IN"}), label="TH")],
                use=[(0, 1), (2, 1)]), far=door)


def techstorage(R):
    door = (R.doors("hall") or R.doors())[0]
    kinds = ("engineering", "medical", "rnd", "security", "service", "tcomms", "command")
    R.run([one("boards", "r", "/obj/structure/rack", "/obj/effect/spawner/lootdrop/techstorage/%s" % k, back="wall")
           for k in kinds], far=door)
    R.place(one("tools", "t", TABLE, "/obj/item/storage/toolbox/electrical", "/obj/item/multitool", back="wall"),
            must=False)


ASSETS = {"bridge": bridge, "vault": vault, "upload": upload, "hop": hop, "conference": conference,
          "captain": captain, "quarters": quarters, "eva": eva, "teleporter": teleporter, "techstorage": techstorage}


# ================================================================================================= review 1 (11-21)
C = "/obj/machinery/computer/"
OCHAIR = "/obj/structure/chair/office"


def bridge2(R):
    # Meta's horseshoe: two banks of three consoles facing the front windows either side of the central aisle, an
    # office chair at each, the side wings with the rest of the set, the captain's chair behind the aisle
    front = [("communications", 92), ("card", 93), ("crew", 94), ("security", 97), ("monitor", 98),
             ("station_alert", 99)]
    for path, x in front:
        R.put((x, 92), "obj", obj=[(C + path, {"dir": 1})])
        R.put((x, 91), "open", obj=[(OCHAIR, {"dir": 1})])
    for y, path in ((90, "secure_data"), (89, "med_data"), (88, "cargo/request")):
        R.put((92, y), "obj", obj=[(C + path, {"dir": 4})])
    for y, path in ((90, "atmos_alert"), (89, "prisoner"), (88, "shuttle/labor")):
        R.put((99, y), "obj", obj=[(C + path, {"dir": 8})])
    R.put((95, 89), "open", obj=[("/obj/structure/chair/comfy/black", {"dir": 1})])
    R.reserve([(95, y) for y in range(86, 94)] + [(96, y) for y in range(86, 94)], "open")
    R.put((96, 88), "open", obj=["/obj/machinery/holopad"])
    R.place(hang("turret control", "button", "/obj/machinery/turretid",
                 {"name": "AI Upload turret control", "control_area": "/area/ai_monitored/turret_protected/ai_upload"}),
            near=(100, 88), must=False)
    R.place(hang("keycard", "button", "/obj/machinery/keycard_auth"), must=False)
    R.place(hang("requests console", "requests_console", "/obj/machinery/requests_console",
                 {"department": "Bridge", "departmentType": 5, "announcementConsole": 1}), must=False)
    R.run([one("bridge locker", "L", "/obj/structure/closet/emcloset"),
           one("fire locker", "L", "/obj/structure/closet/firecloset")])


def upload2(R):
    door = R.doors()[0]
    R.run([console("AI upload", "/obj/machinery/computer/upload/ai"),
           console("borg upload", "/obj/machinery/computer/upload/borg")], far=door)
    R.place(one("law boards", "t", TABLE, "/obj/item/aiModule/core/full/asimov", "/obj/item/aiModule/supplied/freeform",
                "/obj/item/aiModule/supplied/oxygen", "/obj/item/aiModule/supplied/protectStation",
                "/obj/item/aiModule/supplied/quarantine", back="wall"))
    R.place(one("law boards", "t", TABLE, "/obj/item/aiModule/reset", "/obj/item/aiModule/reset/purge",
                "/obj/item/aiModule/zeroth/oneHuman", "/obj/item/aiModule/core/freeformcore", back="wall"))
    xs, ys = [p[0] for p in R.tiles], [p[1] for p in R.tiles]
    for p in ((min(xs), max(ys)), (max(xs), min(ys)), (max(xs), max(ys)), (min(xs), min(ys))):
        if p in R.tiles and p not in R.geo.taken and p not in R.front:
            R.put(p, "obj", obj=["/obj/machinery/porta_turret/ai"])


def captain2(R):
    # the desk faces the door from the room's far end, the chair behind it; consoles on the wall away from it
    R.put((103, 83), "obj", obj=[WOOD, PAPER, "/obj/item/pen/fountain/captain", "/obj/item/stamp/captain"])
    R.put((104, 83), "open", obj=[("/obj/structure/chair/comfy/black", {"dir": 8}),
                                   "/obj/effect/landmark/start/captain"])
    R.put((101, 82), "obj", obj=[(C + "communications", {"dir": 1})])
    R.put((102, 82), "obj", obj=[(C + "card", {"dir": 1})])
    R.place(one("captain's case", "DC", "/obj/structure/displaycase/captain"), must=False)
    R.place(hang("keycard", "button", "/obj/machinery/keycard_auth"), must=False)


def quarters2(R):
    door = R.doors()[0]
    R.place(one("bed", "bd", "/obj/structure/bed", "/obj/item/bedsheet/captain", back="any"), far=door)
    R.place(one("captain locker", "L", "/obj/structure/closet/secure_closet/captains"))
    R.place(one("captain suit", "SU", "/obj/machinery/suit_storage_unit/captain"), must=False)
    R.place(one("dresser", "DR", "/obj/structure/dresser"), must=False)
    R.place(one("hand tele", "t", WOOD, "/obj/item/hand_tele", back="wall"), must=False)
    for p in R.tiles:
        if p not in R.geo.taken:
            R.put(p, None, floor=CARPET)


def bathroom(R):
    door = R.doors()[0]
    R.place(one("toilet", "WC", ("/obj/structure/toilet", {"dir": "IN"})), far=door)
    R.place(one("shower", "SH", ("/obj/machinery/shower", {"dir": "IN"}), back="wall", use=()), must=False)
    R.place(Kit("sink", [(0, 0, dict(obj=[], open=True, free=True, label="s",
                                     mount=[("sink", "/obj/structure/sink", {}), ("sign", "/obj/structure/mirror", {})]))],
                back="wall"), near=door, must=False,
            need=lambda pl: pl.origin not in R.geo.taken and not R.geo.cells.get(pl.origin))


def hop2(R):
    hop(R)
    R.place(button("Queue Shutters", {"id": "hopqueue", "req_access_txt": "57"}), must=False)
    R.place(one("PDA painter", "PP", "/obj/machinery/pdapainter"), must=False)


def teleporter2(R):
    teleporter(R)
    R.place(one("beacon", "BB", "/obj/machinery/bluespace_beacon", back="any", use=()), must=False)
    R.place(one("hand tele", "t", TABLE, "/obj/item/hand_tele", "/obj/item/beacon", back="wall"), must=False)


def vault2(R):
    R.place(one("self-destruct", "SD", "/obj/machinery/nuclearbomb/selfdestruct", decal=[BOT], back="any"),
            near=R.room.attrs["heart"])
    R.place(one("ore silo", "OS", "/obj/machinery/ore_silo", decal=[BOT]))
    R.place(one("bank", "BK", ("/obj/machinery/computer/bank_machine", {"dir": "IN"})))
    R.place(one("safe", "SF", "/obj/structure/safe"), must=False)
    R.run([one("gold", "CR", "/obj/structure/closet/crate/goldcrate"),
           one("silver", "CR", "/obj/structure/closet/crate/silvercrate")])


def securetech(R):
    R.run([one("boards", "r", "/obj/structure/rack", "/obj/effect/spawner/lootdrop/techstorage/%s" % k, back="wall")
           for k in ("command", "tcomms", "AI")])


def techstorage2(R):
    door = (R.doors("hall") or R.doors())[0]
    R.run([one("boards", "r", "/obj/structure/rack", "/obj/effect/spawner/lootdrop/techstorage/%s" % k, back="wall")
           for k in ("engineering", "medical", "rnd", "security", "service")], far=door)
    R.place(one("tools", "t", TABLE, "/obj/item/storage/toolbox/electrical", "/obj/item/multitool", back="wall"),
            must=False)


def eva2(R):
    eva(R)
    R.run([one("EVA suit", "SU", "/obj/machinery/suit_storage_unit/standard_unit")] * 2)
    R.place(one("suit-up bench", "c", (CHAIR, {"dir": "IN"}), back="any", use=()), near=R.room.attrs["heart"],
            must=False)


ASSETS.update({"bridge": bridge2, "upload": upload2, "captain": captain2, "quarters": quarters2, "bath": bathroom,
               "hop": hop2, "teleporter": teleporter2, "vault": vault2, "securetech": securetech,
               "techstorage": techstorage2, "eva": eva2})


# ================================================================================================= review 3 (11-21)
def free_tile(R, p):
    return p in R.tiles and R.geo.taken.get(p) != "obj"


def eva3(R):
    eva(R)
    R.run([one("EVA suit", "SU", "/obj/machinery/suit_storage_unit/standard_unit")] * 2)
    # a suit-up island in the middle: a table of tanks and masks, benches either side (review 3)
    tiles = [(80, 125), (81, 125)]
    if all(free_tile(R, p) for p in tiles + [(80, 124), (81, 124), (80, 126), (81, 126)]):
        R.put((80, 125), "obj", obj=[TABLE, "/obj/item/tank/internals/emergency_oxygen/engi",
                                     "/obj/item/clothing/mask/breath"])
        R.put((81, 125), "obj", obj=[TABLE, "/obj/item/tank/internals/emergency_oxygen/engi", "/obj/item/radio"])
        for x in (80, 81):
            R.put((x, 124), "open", obj=[(CHAIR, {"dir": 1})])
            R.put((x, 126), "open", obj=[(CHAIR, {"dir": 2})])
    else:
        R.geo.problem("eva: the middle is not free for the suit-up island")


def teleporter3(R):
    teleporter2(R)
    # the secure-area sign on the hall side of the door: a sign on the wall turf, rehung onto the hall face
    R.put((93, 130), None, obj=["/obj/structure/sign/warning/securearea"])


def vault3(R):
    # the self-destruct in the middle on its bot decal, the silo and the bank by the door, the safe and the coin
    # crates at the far end, the aisle clear (review 2 #7, review 3)
    for p, why, objs in (((88, 91), "obj", ["/obj/machinery/nuclearbomb/selfdestruct"]),
                         ((87, 86), "obj", ["/obj/machinery/ore_silo"]),
                         ((89, 86), "obj", [("/obj/machinery/computer/bank_machine", {"dir": 1})]),
                         ((87, 93), "obj", ["/obj/structure/safe"]),
                         ((88, 93), "obj", ["/obj/structure/closet/crate/goldcrate"]),
                         ((89, 93), "obj", ["/obj/structure/closet/crate/silvercrate"])):
        if free_tile(R, p):
            R.put(p, why, obj=objs, decal=[BOT] if p in ((88, 91), (87, 86)) else [])
        else:
            R.geo.problem("vault: %d,%d not free for %s" % (p[0], p[1], objs[0] if isinstance(objs[0], str) else objs[0][0]))


def bridge3(R):
    bridge2(R)


def captain3(R):
    captain2(R)
    # the lamp on a second desk tile beside the first (review 2 #4)
    if free_tile(R, (103, 82)):
        R.put((103, 82), "obj", obj=[WOOD, "/obj/item/flashlight/lamp/green", "/obj/item/folder/blue"])


ASSETS.update({"eva": eva3, "teleporter": teleporter3, "vault": vault3, "captain": captain3})
