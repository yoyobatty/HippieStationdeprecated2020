"""Room assets for Security and the Brig: how each room is played, as kits and placing rules.

From Hippie's own brig (census 2026-11-16) and how a shift uses it:
  cells       a bed, a locker the timer opens on release, a flasher; the timer hangs outside on the corridor wall
  front desk  one officer serves the public through the desk shutters and lets people through the entry airlocks
  warden      sits at the desk window onto the corridor: cameras, records, prisoner console, the wing's lockdown buttons
  armory      only through the warden's office; racks of guns and armour on the walls, the floor clear to grab and go
  gear room   officers dress here at roundstart: lockers, the vendor, the wardrobe, the lathe, chargers
  briefing    consoles and chairs facing them, the donut table
  HoS         desk facing the door, consoles at hand, locker and suit behind
  infirmary   a sleeper and a bed for the beaten; a morgue tray for the worse
An asset never names a coordinate. It asks the room which wall faces which neighbour and where its doors are.
"""
from forge.proc.place import Kit, cell, dist
from assets.science import (TABLE, GTABLE, DARK, BOT, CARPET, PAPER, CHAIR, OCHAIR, PLANT_K, SEAT, STRIPE, BIN,
                            one, hang, seat_at, near_tiles, apart)

RTABLE = "/obj/structure/table/reinforced"
RACK = "/obj/structure/rack"
OFFICER = "/obj/effect/landmark/start/security_officer"
CELL_IDS = {"cell1": "Cell 1", "cell2": "Cell 2", "cell3": "Cell 3", "cell4": "Cell 4"}


def button(name, vs):
    return hang(name, "button", "/obj/machinery/button/door", dict({"name": name}, **vs))


# ================================================================================================= cells
def cell_room(R):
    # the bed away from the door so the officer can see the prisoner from the corridor; the locker the timer
    # opens on release; the flasher on the wall
    cid = CELL_IDS[R.rid]
    door = R.doors()[0]
    R.place(one("bed", "bd", "/obj/structure/bed", "/obj/item/bedsheet", back="any"), far=door)
    R.place(one("cell locker", "L", ("/obj/structure/closet/secure_closet/brig", {"name": "%s Locker" % cid, "id": cid})),
            far=door, must=False)
    R.place(hang("flasher", "button", "/obj/machinery/flasher", {"id": cid}), far=door, must=False)


# ================================================================================================= corridor
def brighall(R):
    # each cell's timer on the corridor wall beside its door; the way from the entry to the wings stays clear
    for rid, cid in sorted(CELL_IDS.items()):
        for d in R.doors(rid)[:1]:
            R.place(hang("%s timer" % cid, "status_display", "/obj/machinery/door_timer", {"id": cid, "name": cid}),
                    near=d)
    entry = (R.doors("entry") or R.doors())[0]
    R.place(hang("plaque", "sign", "/obj/structure/sign/plaques/golden"), near=entry, must=False)
    R.place(hang("ion rifle poster", "sign", "/obj/structure/sign/poster/official/ion_rifle"), far=entry, must=False)
    R.mark(R.room.attrs["heart"], "/obj/effect/landmark/event_spawn")


def evidence(R):
    # evidence and confiscated gear: lockers down the walls
    door = R.doors()[0]
    R.run([one("evidence locker", "L", "/obj/structure/closet")] * 3, far=door)
    R.run([one("evidence locker", "L", "/obj/structure/closet")] * 2, near=door)


# ================================================================================================= front desk
DESK_SEAT = Kit("desk console", [
    cell(0, 0, ("/obj/machinery/computer/secure_data", {"dir": "IN"}), label="C"),
    seat_at(0, 1, "/obj/structure/chair/office"),
], use=[(0, 1)], back=None)


def frontdesk(R):
    # one officer: records at hand, the entry and desk controls on the wall, cuffs on the table
    door = (R.doors("brighall") or R.doors())[0]
    if not R.place(DESK_SEAT, far=door, must=False):
        # a two-by-two booth is all door aprons: the console goes in the corner furthest from the corridor door
        spots = sorted(R.tiles, key=lambda p: (-dist(p, door), p))
        R.mark(spots[0], ("/obj/machinery/computer/secure_data", {"dir": 1 if spots[0][1] < door[1] else 2}))
    R.place(one("desk kit", "t", TABLE, PAPER, "/obj/item/pen", "/obj/item/restraints/handcuffs", "/obj/item/radio/off",
                back="any"), near=door, must=False)
    R.place(button("Brig Exterior Doors Control", {"id": "outerbrig", "normaldoorcontrol": 1, "req_access_txt": "63"}),
            far=door, must=False)
    R.place(button("Brig Interior Doors Control", {"id": "innerbrig", "normaldoorcontrol": 1, "req_access_txt": "63"}),
            far=door, must=False)
    R.place(button("Desk Shutters", {"id": "briggate"}), far=door, must=False)
    R.place(hang("entry flash", "button", "/obj/machinery/button/flasher", {"id": "brigentry"}), far=door, must=False)
    R.mark(door, OFFICER)


def entry(R):
    R.place(hang("flasher", "button", "/obj/machinery/flasher", {"id": "brigentry"}), near=R.room.attrs["heart"], must=False)


# ================================================================================================= warden
WARDEN_ROW = Kit("warden consoles", [
    cell(0, 0, ("/obj/machinery/computer/prisoner", {"dir": "IN"}), label="PC"),
    cell(1, 0, ("/obj/machinery/computer/security", {"dir": "IN"}), label="SC"),
    cell(2, 0, ("/obj/machinery/computer/secure_data", {"dir": "IN"}), label="SD"),
    seat_at(1, 1, "/obj/structure/chair/office", "/obj/effect/landmark/start/warden"),
], use=[(0, 1), (1, 1), (2, 1)])


def warden(R):
    # the warden sits by the desk window onto the corridor; consoles behind, the armory door within a step
    desk = (R.doors("brighall") or R.doors())[0]
    armory = (R.doors("armory") or [desk])[0]
    row = R.place(WARDEN_ROW, near=desk, must=False) or R.place(WARDEN_ROW, must=False)
    chair = row.at(1, 1) if row else desk
    R.place(one("crew monitor", "C", ("/obj/machinery/computer/crew", {"dir": "IN"})), near=chair, must=False)
    R.place(one("warden locker", "L", "/obj/structure/closet/secure_closet/warden"), far=desk, must=False)
    R.place(one("chargers", "t", TABLE, ("/obj/machinery/recharger", {"pixel_y": 4}), back="any"), near=armory, must=False)
    R.place(one("gear rack", "r", RACK, "/obj/item/clothing/mask/gas/sechailer", "/obj/item/clothing/mask/gas/sechailer",
                "/obj/item/clothing/ears/earmuffs", "/obj/item/clothing/glasses/sunglasses"), near=armory, must=False)
    R.place(one("files", "F", "/obj/structure/filingcabinet/chestdrawer", back="any"), far=desk, must=False)
    R.place(one("law", "t", TABLE, "/obj/item/book/manual/wiki/security_space_law", "/obj/item/folder/red",
                "/obj/item/hand_labeler", back="any"), near=chair, must=False)
    for name, vs in (("Prison Wing Lockdown", {"id": "Prison Gate", "req_access_txt": "2"}),
                     ("Cell Shutters", {"id": "Secure Gate", "req_access_txt": "2"}),
                     ("Warden Office Shutters", {"id": "wardenshutter", "req_access_txt": "2"})):
        R.place(button(name, vs), near=chair, must=False)
    R.place(hang("requests console", "requests_console", "/obj/machinery/requests_console",
                 {"department": "Security", "departmentType": 5}), near=chair, must=False)
    R.mark(R.room.attrs["heart"], "/obj/machinery/holopad/secure")


# ================================================================================================= armory
def rack(name, *items):
    return one(name, "r", RACK, *items, back="wall")


GUNS = [
    rack("riot shotguns", *["/obj/item/gun/ballistic/shotgun/riot"] * 3),
    rack("e-guns", *["/obj/item/gun/energy/e_gun"] * 3),
    rack("lasers", *["/obj/item/gun/energy/laser"] * 3),
    rack("tasers", *["/obj/item/gun/energy/e_gun/advtaser"] * 3),
]
ARMOUR = [
    rack("riot boomerangs", *["/obj/item/boomerang/riot"] * 3),
    rack("bulletproof", *(["/obj/item/clothing/suit/armor/bulletproof"] * 3 + ["/obj/item/clothing/head/helmet/alt"] * 3)),
    rack("riot gear", *(["/obj/item/clothing/suit/armor/riot"] * 3 + ["/obj/item/clothing/head/helmet/riot"] * 3
                        + ["/obj/item/shield/riot"] * 3)),
    rack("specials", "/obj/item/clothing/suit/armor/laserproof", "/obj/item/gun/energy/e_gun/dragnet",
         "/obj/item/gun/energy/e_gun/dragnet", "/obj/item/gun/energy/ionrifle", "/obj/item/gun/energy/temperature/security"),
]


def armory(R):
    # guns on one wall, armour on another, lockers and suits by the door; the middle clear to grab and go
    door = (R.doors("warden") or R.doors())[0]
    R.run(GUNS, far=door)
    R.run(ARMOUR, far=door)
    R.run([one("lethal shot locker", "L", "/obj/structure/closet/secure_closet/lethalshots"),
           one("contraband locker", "L", "/obj/structure/closet/secure_closet/contraband/armory")], near=door)
    R.run([one("security suit", "SU", "/obj/machinery/suit_storage_unit/security"),
           one("security suit", "SU", "/obj/machinery/suit_storage_unit/security")])
    R.place(one("implants", "t", TABLE, "/obj/item/storage/box/chemimp", "/obj/item/storage/box/trackimp",
                "/obj/item/storage/lockbox/loyalty", "/obj/item/storage/box/firingpins", "/obj/item/storage/box/firingpins",
                back="any"), must=False)
    R.place(one("ammo", "t", TABLE, *(["/obj/item/storage/box/rubbershot"] * 3 + ["/obj/item/storage/box/flashbangs",
                "/obj/item/storage/box/teargas", "/obj/item/storage/box/handcuffs"]), back="any"), must=False)
    R.place(one("barriers", "t", TABLE, *(["/obj/item/grenade/barrier"] * 3 + ["/obj/item/key/security"] * 2), back="any"),
            must=False)
    R.place(one("pepper", "PT", "/obj/structure/reagent_dispensers/peppertank"), near=door, must=False)
    R.place(one("secways", "sw", "/obj/vehicle/ridden/secway", "/obj/vehicle/ridden/secway", back="any"), must=False)
    R.run([one("portable flasher", "pf", "/obj/machinery/flasher/portable", back="any", use=())] * 3)
    R.place(button("Armory Shutters", {"id": "armoryshutter", "req_access_txt": "2"}), near=door, must=False)


# ================================================================================================= gear room
def gear(R):
    # officers dress here: lockers along the walls, the vendor and wardrobe by the door, the lathe at the back
    door = (R.doors("main") or R.doors())[0]
    lockers = R.run([one("officer locker", "L", "/obj/structure/closet/secure_closet/security/sec")] * 6, far=door)
    for k in (lockers or [])[:4]:
        R.mark(k.origin, "/obj/effect/landmark/secequipment")
    R.place(one("SecTech", "V", "/obj/machinery/vending/security"), near=door)
    R.place(one("SecDrobe", "W", "/obj/machinery/vending/wardrobe/sec_wardrobe"), near=door, must=False)
    R.place(one("security lathe", "TF", "/obj/machinery/rnd/production/techfab/department/security", decal=[BOT]),
            must=False)
    R.place(one("chargers", "t", TABLE, ("/obj/machinery/recharger", {"pixel_x": -6}),
                ("/obj/machinery/recharger", {"pixel_x": 6}), back="any"), near=door, must=False)
    R.run([one("bomb suit", "L", "/obj/structure/closet/bombcloset/security"),
           one("bio suit", "L", "/obj/structure/closet/l3closet/security")])
    R.place(one("pepper", "PT", "/obj/structure/reagent_dispensers/peppertank"), must=False)
    R.place(hang("space cops", "sign", "/obj/structure/sign/poster/official/space_cops"), must=False)
    free = [p for p in R.tiles if R.free(p) and p not in R.front]
    for p in sorted(free, key=lambda p: dist(p, door))[:5]:
        R.mark(p, OFFICER)


# ================================================================================================= briefing
BRIEF_DESK = Kit("briefing consoles", [
    cell(0, 0, ("/obj/machinery/computer/security", {"dir": "IN"}), label="SC"),
    cell(1, 0, ("/obj/machinery/computer/secure_data", {"dir": "IN"}), label="SD"),
], use=[(0, 1), (1, 1)])
DONUTS = Kit("donut table", [
    cell(0, 0, TABLE, "/obj/item/storage/fancy/donut_box", label="t"),
    cell(1, 0, TABLE, PAPER, "/obj/item/pen", "/obj/item/folder/red", label="t"),
], use=[(0, 1), (1, 1), (0, -1), (1, -1)], back=None)


def main(R):
    # the shift's briefing: consoles on one wall, chairs facing them, the donut table in the middle
    hall = (R.doors("brighall") or R.doors())[0]
    desk = R.place(BRIEF_DESK, far=hall)
    seats = R.run([SEAT] * 4, near=desk.origin if desk else R.room.attrs["heart"])
    dwall = R.geo.field("dwall")
    R.place(DONUTS, near=R.room.attrs["heart"], must=False,
            need=lambda pl: apart(R, pl, 1) and all(dwall.get(t, 0) >= 2 for t in pl.tiles))
    R.place(one("training bomb", "TB", "/obj/machinery/syndicatebomb/training", back="any"), must=False)
    R.place(one("practice", "t", TABLE, "/obj/item/gun/energy/laser/practice", "/obj/item/assembly/flash/handheld",
                "/obj/item/restraints/handcuffs", back="any"), must=False)
    R.place(one("files", "F", "/obj/structure/filingcabinet", back="any"), must=False)
    R.place(hang("noticeboard", "noticeboard", "/obj/structure/noticeboard"), near=hall, must=False)
    R.place(hang("requests console", "requests_console", "/obj/machinery/requests_console",
                 {"department": "Security", "departmentType": 5}), near=hall, must=False)
    R.place(hang("secure area", "sign", "/obj/structure/sign/warning/securearea"), near=hall, must=False)
    for s in (seats or [])[:4]:
        R.mark(s.origin, OFFICER)
    free = [p for p in R.tiles if R.free(p) and p not in R.front]
    for p in sorted(free, key=lambda p: dist(p, R.room.attrs["heart"]))[:2]:
        R.mark(p, "/obj/effect/landmark/start/vice_officer")
    R.mark(R.room.attrs["heart"], "/obj/machinery/holopad/secure")


def dock(R):
    # the way out to the pod airlock and the MULE flaps: an emergency closet, a bin, nothing in the way
    R.place(one("emergency closet", "L", "/obj/structure/closet/emcloset"), must=False)
    R.place(one("parcels", "t", TABLE, "/obj/item/stack/packageWrap", "/obj/item/pen", back="any"), must=False)
    R.place(BIN, must=False)
    R.place(hang("pods", "sign", "/obj/structure/sign/warning/pods"), must=False)


# ================================================================================================= interrogation
def interro(R):
    # a table between two chairs, the recorder on it; nothing else to throw
    door = R.doors()[0]
    R.place(Kit("interview table", [
        cell(0, 0, TABLE, "/obj/item/taperecorder", label="t"),
        (-1, 0, dict(obj=[(CHAIR, {"dir": "A+"})], open=True, seat=True, label="c")),
        (1, 0, dict(obj=[(CHAIR, {"dir": "A-"})], open=True, seat=True, label="c")),
    ], use=[(0, 1), (0, -1)], back=None, mirror=False), near=R.room.attrs["heart"], must=False)
    R.place(hang("flasher", "button", "/obj/machinery/flasher", {"id": "interrogation"}), far=door, must=False)


# ================================================================================================= HoS
HOS_DESK = Kit("HoS desk", [
    cell(0, 0, "/obj/structure/table/wood", PAPER, "/obj/item/pen", "/obj/item/folder/red", label="t"),
    cell(1, 0, "/obj/structure/table/wood", "/obj/item/stamp/hos", "/obj/item/book/manual/wiki/security_space_law", label="t"),
    seat_at(0, 1, "/obj/structure/chair/comfy/black", "/obj/effect/landmark/start/head_of_security"),
], use=[(0, -1), (1, -1)], back=None)


def hos(R):
    # the head sits facing the door, consoles at hand, the locker and suit behind
    door = R.doors()[0]
    dwall = R.geo.field("dwall")
    desk = R.place(HOS_DESK, near=R.room.attrs["heart"],
                   need=lambda pl: dist(pl.at(0, 1), door) > dist(pl.at(0, -1), door)
                   and all(dwall.get(t, 0) >= 1 for t in pl.tiles))
    chair = desk.at(0, 1) if desk else R.room.attrs["heart"]
    if desk:
        R.zone(near_tiles(R, desk.tiles), floor=CARPET)
    R.run([one("ID console", "C", ("/obj/machinery/computer/card/minor/hos", {"dir": "IN"})),
           one("cameras", "C", ("/obj/machinery/computer/security/hos", {"dir": "IN"})),
           one("records", "C", ("/obj/machinery/computer/secure_data", {"dir": "IN"}))], near=chair)
    R.run([one("HoS locker", "L", "/obj/structure/closet/secure_closet/hos"),
           one("HoS suit", "SU", "/obj/machinery/suit_storage_unit/hos")], far=door)
    R.place(one("drinks", "t", "/obj/structure/table/wood", "/obj/item/reagent_containers/food/drinks/bottle/vodka/badminka",
                "/obj/item/taperecorder", "/obj/item/storage/box/deputy", "/obj/item/storage/box/seccarts", back="any"),
            far=door, must=False)
    R.place(BIN, near=door, must=False)
    R.place(hang("safe", "sign", "/obj/item/storage/secure/safe/HoS"), far=door, must=False)
    R.place(hang("keycard", "button", "/obj/machinery/keycard_auth"), near=chair, must=False)
    R.place(button("Space Shutters", {"id": "HOSOfficespace", "req_access_txt": "58"}), near=chair, must=False)
    R.place(hang("requests console", "requests_console", "/obj/machinery/requests_console",
                 {"department": "Head of Security's Desk", "departmentType": 5, "announcementConsole": 1}),
            near=chair, must=False)
    R.place(hang("newscaster", "newscaster", "/obj/machinery/newscaster/security_unit"), far=chair, must=False)
    free = [p for p in R.tiles if R.free(p) and p not in R.front]
    if free:
        R.mark(min(free, key=lambda p: (dist(p, chair), p)), "/mob/living/simple_animal/pet/dog/pug")


# ================================================================================================= infirmary
def infirm(R):
    # a sleeper for the beaten, beds for the restrained, a tray for the worse; meds on the table
    door = R.doors()[0]
    R.place(one("sleeper", "SL", ("/obj/machinery/sleeper", {"dir": "A+"})), far=door)
    R.run([one("bed", "bd", "/obj/structure/bed", "/obj/item/clothing/suit/straight_jacket", back="any"),
           one("bed", "bd", "/obj/structure/bed", "/obj/item/clothing/suit/straight_jacket", back="any")])
    R.place(one("meds", "g", GTABLE, "/obj/item/reagent_containers/glass/bottle/charcoal",
                "/obj/item/reagent_containers/glass/bottle/epinephrine", "/obj/item/reagent_containers/syringe",
                "/obj/item/storage/firstaid/regular", back="any"), near=door, must=False)
    R.place(one("laptop", "g", GTABLE, "/obj/machinery/computer/med_data/laptop", back="any"), must=False)
    R.place(one("drip", "iv", "/obj/machinery/iv_drip", back="any", use=()), must=False)


ASSETS = {"cell1": cell_room, "cell2": cell_room, "cell3": cell_room, "cell4": cell_room, "brighall": brighall,
          "evidence": evidence, "frontdesk": frontdesk, "entry": entry, "warden": warden, "armory": armory,
          "gear": gear, "main": main, "dock": dock, "interro": interro, "hos": hos, "infirm": infirm}
