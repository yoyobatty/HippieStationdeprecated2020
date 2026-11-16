"""Room assets for Engineering's front: how each room is played, as kits and placing rules.

From Hippie's own engineering front (census 2026-11-16, x99-124 y74-93) and how a shift uses it:
  foyer       the walk from the rad airlock to the engine room doors: personal lockers, tool racks, rad closets
  storage     secure storage behind blast doors: emitters, the gas canisters for the engine, the TEG crate
  workshop    sheets and gloves on tables, the solar crate, welding fuel and water tanks, a portable pump
  control     the alert consoles and the engine cameras, engineering hardsuits and the tank dispenser
  CE          desk facing the door, the ID and APC consoles at hand, the hardsuit and locker behind, Poly
  airlock     the cycled decontamination passage to the break room: shower, rad and fire closets
  break room  the public's way in: vendors, a table with a charger, the noticeboard
  checkpoint  one officer behind glass that looks over the break room
An asset never names a coordinate. It asks the room which wall faces which neighbour and where its doors are.
"""
from forge.proc.place import Kit, cell, dist
from assets.science import (TABLE, BOT, CARPET, PAPER, OCHAIR, PLANT_K, SEAT, BIN, one, hang, seat_at, near_tiles)

RTABLE = "/obj/structure/table/reinforced"
RACK = "/obj/structure/rack"
ENGINEER = "/obj/effect/landmark/start/station_engineer"


def button(name, vs):
    return hang(name, "button", "/obj/machinery/button/door", dict({"name": name}, **vs))


def free_spots(R, near, n):
    free = [p for p in R.tiles if R.free(p) and p not in R.front]
    return sorted(free, key=lambda p: (dist(p, near), p))[:n]


# ================================================================================================= foyer
def foyer(R):
    # lockers and tool racks along the walls, the way from the airlock to the engine doors kept clear
    door = (R.doors("airlock") or R.doors())[0]
    R.run([one("engineer locker", "L", "/obj/structure/closet/secure_closet/engineering_personal")] * 3, near=door)
    R.run([one("tools", "t", TABLE, "/obj/item/crowbar/large", "/obj/item/storage/box/lights/mixed",
               "/obj/item/clothing/glasses/meson", "/obj/item/clothing/glasses/meson", back="any"),
           one("belt rack", "r", RACK, "/obj/item/storage/belt/utility", "/obj/item/wrench", "/obj/item/weldingtool",
               "/obj/item/clothing/head/welding", back="any"),
           one("manuals", "t", TABLE, "/obj/item/book/manual/wiki/engineering_hacking",
               "/obj/item/book/manual/wiki/engineering_construction", "/obj/item/clothing/glasses/meson", back="any")])
    R.run([one("radiation closet", "L", "/obj/structure/closet/radiation")] * 2)
    # portable scrubbers by the engine doors, for a leak
    R.run([one("scrubber", "SC", "/obj/machinery/portable_atmospherics/scrubber", back="any", use=())] * 2,
          near=(R.doors() or [R.room.attrs["heart"]])[0])
    R.place(hang("engine safety", "sign", "/obj/structure/sign/warning/enginesafety"), must=False)
    R.place(hang("no smoking", "sign", "/obj/structure/sign/warning/nosmoking"), must=False)
    R.place(hang("requests console", "requests_console", "/obj/machinery/requests_console",
                 {"name": "Engineering RC", "department": "Engineering", "departmentType": 4}), must=False)
    for p in free_spots(R, R.room.attrs["heart"], 2):
        R.mark(p, ENGINEER)
    R.mark(R.room.attrs["heart"], "/obj/machinery/holopad")
    R.mark(R.room.attrs["heart"], "/obj/effect/landmark/event_spawn")
    for d in R.doors()[:2]:
        R.place(hang("secure area", "sign", "/obj/structure/sign/warning/securearea"), near=d, must=False)


# ================================================================================================= secure storage
def storage(R):
    # what the engine needs, behind blast doors: emitters, gas canisters, the generator crate, reflectors
    door = R.doors()[0]
    R.run([one("emitter", "EM", ("/obj/machinery/power/emitter", {"dir": "IN"}), back="any", use=())] * 2, far=door)
    R.run([one("nitrogen", "N2", "/obj/machinery/portable_atmospherics/canister/nitrogen", back="any", use=()),
           one("nitrogen", "N2", "/obj/machinery/portable_atmospherics/canister/nitrogen", back="any", use=()),
           one("plasma", "PL", "/obj/machinery/portable_atmospherics/canister/toxins", back="any", use=()),
           one("plasma", "PL", "/obj/machinery/portable_atmospherics/canister/toxins", back="any", use=()),
           one("CO2", "CO", "/obj/machinery/portable_atmospherics/canister/carbon_dioxide", back="any", use=()),
           one("oxygen", "O2", "/obj/machinery/portable_atmospherics/canister/oxygen", back="any", use=())])
    # the kit comes unanchored with its panels open, as cargo ships it (anchored circulators would be open pipe ends)
    R.place(one("generator crate", "CR", ("/obj/structure/closet/crate/engineering", {"name": '"T.E.G. crate"'}),
                ("/obj/machinery/power/generator", {"dir": 4, "anchored": 0, "panel_open": 1}),
                ("/obj/machinery/atmospherics/components/binary/circulator",
                 {"anchored": 0, "move_resist": 1000, "flipped": 1, "panel_open": 1}),
                ("/obj/machinery/atmospherics/components/binary/circulator/cold",
                 {"dir": 1, "anchored": 0, "move_resist": 1000, "flipped": 1, "panel_open": 1}),
                back="any", use=()), must=False)
    R.place(one("reflector", "RF", "/obj/structure/reflector/box", back="any", use=()), must=False)
    R.place(hang("safety report", "sign", "/obj/structure/sign/poster/official/safety_report"), must=False)
    R.place(hang("secure area", "sign", "/obj/structure/sign/warning/securearea"), near=door, must=False)
    spots = free_spots(R, R.room.attrs["heart"], 1)
    if spots:
        R.mark(spots[0], "/obj/effect/landmark/blobstart")


# ================================================================================================= workshop
def workshop(R):
    # building stock on tables, the solar crate, tanks by the door
    door = (R.doors("foyer") or R.doors())[0]
    R.run([one("sheets", "t", TABLE, "/obj/item/stack/sheet/metal/fifty", "/obj/item/stack/sheet/glass/fifty",
               "/obj/item/stack/sheet/mineral/plasma", back="any"),
           one("gloves", "t", TABLE, *(["/obj/item/clothing/gloves/color/yellow"] * 4
                                       + ["/obj/item/clothing/suit/hazardvest"] * 3
                                       + ["/obj/item/tank/internals/emergency_oxygen/engi"] * 3), back="any"),
           one("electronics", "t", TABLE, "/obj/item/electronics/airlock", "/obj/item/electronics/airlock",
               "/obj/item/electronics/apc", "/obj/item/electronics/apc", "/obj/item/stock_parts/cell/high/plus",
               "/obj/item/stock_parts/cell/high/plus", back="any"),
           one("cables", "t", TABLE, "/obj/item/stack/cable_coil", "/obj/item/stack/cable_coil",
               "/obj/item/storage/box/lights/mixed", back="any")], far=door)
    R.place(one("solar crate", "CR", "/obj/structure/closet/crate", *(["/obj/item/solar_assembly"] * 13
                + ["/obj/item/circuitboard/computer/solar_control", "/obj/item/electronics/tracker",
                   "/obj/item/paper/guides/jobs/engi/solars"]), back="any", use=()), must=False)
    R.run([one("fuel tank", "FT", "/obj/structure/reagent_dispensers/fueltank"),
           one("water tank", "WT", "/obj/structure/reagent_dispensers/watertank")], near=door)
    R.place(one("pump", "PU", "/obj/machinery/portable_atmospherics/pump", back="any", use=()), must=False)
    R.place(hang("extinguisher", "extinguisher", "/obj/structure/extinguisher_cabinet"), near=door, must=False)
    for p in free_spots(R, door, 1):
        R.mark(p, ENGINEER)


# ================================================================================================= control
CONTROL = Kit("alert consoles", [
    cell(0, 0, ("/obj/machinery/computer/station_alert", {"dir": "IN"}), label="SA"),
    cell(1, 0, ("/obj/machinery/modular_computer/console/preset/engineering", {"dir": "IN"}), label="EC"),
    cell(2, 0, ("/obj/machinery/computer/atmos_alert", {"dir": "IN"}), label="AA"),
    seat_at(1, 1, "/obj/structure/chair/office", ENGINEER),
], use=[(0, 1), (1, 1), (2, 1)])


def control(R):
    # the alert consoles with the engine cameras above them; hardsuits and air by the door
    door = (R.doors("foyer") or R.doors())[0]
    row = R.place(CONTROL, far=door, must=False)
    chair = row.at(1, 1) if row else R.room.attrs["heart"]
    R.place(hang("engine cameras", "telescreen", "/obj/machinery/computer/security/telescreen/engine",
                 {"network": 'list("engine","singularity")'}), near=chair, must=False)
    R.run([one("engine suit", "SU", "/obj/machinery/suit_storage_unit/engine"),
           one("tank dispenser", "TD", "/obj/structure/tank_dispenser"),
           one("engine suit", "SU", "/obj/machinery/suit_storage_unit/engine")], near=door)
    R.place(hang("intercom", "intercom", "/obj/item/radio/intercom"), near=chair, must=False)
    R.place(hang("walk", "sign", "/obj/structure/sign/poster/official/walk"), must=False)


# ================================================================================================= CE
CE_DESK = Kit("CE desk", [
    cell(0, 0, RTABLE, "/obj/item/folder/yellow", "/obj/item/stamp/ce", label="t"),
    cell(1, 0, RTABLE, "/obj/item/clipboard", "/obj/item/paper/monitorkey", label="t"),
    seat_at(0, 1, "/obj/structure/chair/office/light", "/obj/effect/landmark/start/chief_engineer"),
], use=[(0, -1), (1, -1)], back=None)


def ce(R):
    # the chief sits facing the door, the ID and APC consoles at hand, the locker and hardsuit behind
    door = (R.doors("foyer") or R.doors())[0]
    dwall = R.geo.field("dwall")
    desk = R.place(CE_DESK, near=R.room.attrs["heart"], must=False,
                   need=lambda pl: dist(pl.at(0, 1), door) > dist(pl.at(0, -1), door)
                   and all(dwall.get(t, 0) >= 1 for t in pl.tiles))
    chair = desk.at(0, 1) if desk else R.room.attrs["heart"]
    R.run([one("ID console", "C", ("/obj/machinery/computer/card/minor/ce", {"dir": "IN"})),
           one("APC console", "C", ("/obj/machinery/computer/apc_control", {"dir": "IN"})),
           one("alerts", "C", ("/obj/machinery/computer/station_alert", {"dir": "IN"}))], near=chair)
    R.run([one("CE locker", "L", "/obj/structure/closet/secure_closet/engineering_chief"),
           one("CE suit", "SU", "/obj/machinery/suit_storage_unit/ce")], far=door)
    R.place(one("chargers", "t", RTABLE, "/obj/machinery/cell_charger", "/obj/item/stock_parts/cell/high/plus",
                "/obj/item/twohanded/rcl/pre_loaded", back="any"), must=False)
    R.place(one("cartridges", "t", RTABLE, *(["/obj/item/cartridge/engineering"] * 3 + ["/obj/item/cartridge/atmos"]),
                back="any"), must=False)
    R.place(one("CE rack", "r", RACK, "/obj/item/lighter", "/obj/item/clothing/glasses/meson",
                "/obj/item/stock_parts/cell/high/plus", "/obj/item/reagent_containers/pill/patch/silver_sulf"),
            far=door, must=False)
    R.place(one("files", "F", "/obj/structure/filingcabinet/chestdrawer", back="any"), must=False)
    R.place(BIN, near=door, must=False)
    R.place(hang("engine cameras", "telescreen", "/obj/machinery/computer/security/telescreen/engine",
                 {"network": 'list("engine","singularity")'}), near=chair, must=False)
    R.place(hang("keycard", "button", "/obj/machinery/keycard_auth"), near=chair, must=False)
    R.place(button("Privacy Shutters Control", {"id": "ceprivacy", "req_access_txt": "56"}), near=chair, must=False)
    R.place(button("Engineering Secure Storage", {"id": "Secure Storage", "req_access_txt": "11"}), near=chair,
            must=False)
    R.place(button("Engineering Lockdown", {"id": "Engineering", "req_access_txt": "10"}), near=chair, must=False)
    R.place(button("Atmospherics Lockdown", {"id": "atmos", "req_access_txt": "24"}), near=chair, must=False)
    R.place(hang("requests console", "requests_console", "/obj/machinery/requests_console",
                 {"name": "Chief Engineer RC", "department": "Chief Engineer's Desk", "departmentType": 3,
                  "announcementConsole": 1}), near=chair, must=False)
    R.place(hang("intercom", "intercom", "/obj/item/radio/intercom"), far=chair, must=False)
    if desk:
        R.zone(near_tiles(R, desk.tiles), floor=CARPET)
    spots = free_spots(R, chair, 1)
    if spots:
        R.mark(spots[0], "/mob/living/simple_animal/parrot/Poly")
    R.mark(R.room.attrs["heart"], "/obj/machinery/holopad")


# ================================================================================================= rad airlock
def airlock(R):
    # rinse off on the way out: a shower, rad suits and fire gear down the walls, the middle clear to walk
    R.place(one("shower", "SH", ("/obj/machinery/shower", {"dir": "IN"}), back="wall", use=()), must=False)
    R.place(one("radiation closet", "L", "/obj/structure/closet/radiation"), must=False)
    R.run([one("fire closet", "L", "/obj/structure/closet/firecloset")] * 2)
    for d in R.doors():
        R.place(hang("rad area", "sign", "/obj/structure/sign/warning/radiation/rad_area"), near=d, must=False)


# ================================================================================================= break room
def break_room(R):
    # where the public waits: vendors on one wall, a table with a charger and mesons, the noticeboard
    door = (R.doors("public") or R.doors())[0]
    R.run([one("snacks", "V", "/obj/machinery/vending/snack/random", use=()),
           one("cigarettes", "V", "/obj/machinery/vending/cigarette", use=())], far=door)
    R.place(one("charger", "t", TABLE, "/obj/machinery/cell_charger", back="any"), must=False)
    R.place(one("mesons", "t", TABLE, "/obj/item/clothing/glasses/meson", back="any"), must=False)
    R.run([SEAT, SEAT])
    R.place(one("fire closet", "L", "/obj/structure/closet/firecloset"), must=False)
    R.place(hang("noticeboard", "noticeboard", "/obj/structure/noticeboard"), must=False)
    R.place(hang("engineering", "sign", "/obj/structure/sign/departments/engineering"), near=door, must=False)
    R.place(PLANT_K, near=door, must=False)
    R.mark(R.room.attrs["heart"], "/obj/machinery/holopad")
    R.mark(R.room.attrs["heart"], "/obj/effect/landmark/event_spawn")


# ================================================================================================= checkpoint
CHECK_DESK = Kit("checkpoint desk", [
    cell(0, 0, ("/obj/machinery/computer/secure_data", {"dir": "IN"}), label="SD"),
    seat_at(0, 1, "/obj/structure/chair/office", "/obj/effect/landmark/start/depsec/engineering"),
], use=[(0, 1)])


def checkpoint(R):
    # one officer, records at hand, looking out over the break room through the glass
    door = R.doors()[0]
    desk = R.place(CHECK_DESK, far=door, must=False)
    chair = desk.at(0, 1) if desk else R.room.attrs["heart"]
    R.place(one("desk", "t", TABLE, PAPER, "/obj/item/pen", "/obj/item/book/manual/wiki/security_space_law",
                back="any"), near=chair, must=False)
    R.place(one("charger", "t", TABLE, ("/obj/machinery/recharger", {"pixel_y": 4}), back="any"), must=False)
    R.place(one("officer locker", "L", "/obj/structure/closet/secure_closet/security/engine"), must=False)
    R.place(one("SecDrobe", "W", "/obj/machinery/vending/wardrobe/sec_wardrobe"), must=False)
    R.place(one("files", "F", "/obj/structure/filingcabinet", back="any"), must=False)
    R.place(one("pepper", "PT", "/obj/structure/reagent_dispensers/peppertank"), must=False)
    R.place(button("Engineering Lockdown", {"id": "Engineering", "req_access_txt": "10"}), near=chair, must=False)
    R.place(hang("engine cameras", "telescreen", "/obj/machinery/computer/security/telescreen/engine",
                 {"network": 'list("engine","singularity")'}), near=chair, must=False)
    R.place(hang("requests console", "requests_console", "/obj/machinery/requests_console",
                 {"name": "Security RC", "department": "Security"}), must=False)
    R.place(hang("newscaster", "newscaster", "/obj/machinery/newscaster/security_unit"), must=False)


ASSETS = {"foyer": foyer, "storage": storage, "workshop": workshop, "control": control, "ce": ce,
          "airlock": airlock, "break": break_room, "checkpoint": checkpoint}
