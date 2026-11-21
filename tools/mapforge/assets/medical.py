"""Room assets for a Medbay: how each room is played, as kits and placing rules.

The program is the user's (2026-11-14): MetaStation's medbay, with ONE operating theatre and a real store room.
  lobby       the public wait here; a reception desk with a windoor; nobody walks behind the desk
  ward        sleepers as a mirrored pair facing each other, the records console and a supply table between them
  theatre     the table in the middle of the room so a surgeon can stand on either side; tools only here
  store       the department's lathe, lockers and kits live here, not in the halls
  patient     a bed, a drip, a privacy shutter
An asset never names a coordinate. It asks the room which wall faces which neighbour and where its doors are.
"""
from forge.proc.geo import step
from forge.proc.place import Kit, cell, dist
from assets.science import (TABLE, GTABLE, DARK, BOT, CARPET, PAPER, CHAIR, OCHAIR, BIN, PLANT_K, SEAT, STRIPE,
                            one, hang, seat_at, near_tiles, apart)

FIRSTAID = "/obj/item/storage/firstaid"
MED_DOC = "/obj/effect/landmark/start/medical_doctor"


def bench(R, n, near, **kw):
    return R.run([SEAT] * n, near=near, **kw)


# ================================================================================================= lobby
def lobby(R):
    # people wait on benches along the walls; the way from the entrance to the ward doors stays open
    desk = (R.doors("reception") or R.doors())[0]
    inner = (R.doors("medhall") or R.doors())[0]
    seats = bench(R, 3, near=R.room.attrs["heart"]) + bench(R, 2, near=desk)
    R.place(one("snacks", "V", "/obj/machinery/vending/snack/random", use=()), far=inner, must=False)
    R.place(one("first aid", "t", TABLE, FIRSTAID + "/regular", back="any"), near=seats[0].origin if seats else desk, must=False)
    R.place(PLANT_K, far=desk, must=False)
    R.place(PLANT_K, near=inner, must=False)
    R.mark(R.room.attrs["heart"], "/obj/machinery/holopad")


RECEPTION = Kit("crew monitor", [
    cell(0, 0, ("/obj/machinery/computer/crew", {"dir": "IN"}), label="CM"),
    seat_at(0, 1),
], use=[(0, 1)], back="any")


def reception(R):
    # one person: the desk windoor in front, the crew monitor beside the chair, files behind
    desk = (R.doors("lobby") or R.doors())[0]
    R.place(RECEPTION, near=desk)
    R.place(one("files", "F", "/obj/structure/filingcabinet/chestdrawer", back="any"), far=desk, must=False)
    R.place(one("forms", "t", TABLE, PAPER, "/obj/item/pen", "/obj/item/folder/white", back="any"), near=desk, must=False)
    R.mark(desk, MED_DOC)


# ================================================================================================= the halls
def medhall(R):
    # a street: NanoMed by the lobby doors, seats on the cryo glass, roller beds where a patient is wheeled in
    lob = (R.doors("lobby") or R.doors())[0]
    ward = (R.doors("recovery") or [lob])[0]
    store = (R.doors("medstore") or [lob])[0]
    R.place(one("NanoMed", "V", "/obj/machinery/vending/medical", use=()), near=lob)
    bench(R, 3, near=ward, side=R.side("keep"))
    R.run([one("roller bed", "rb", "/obj/structure/bed/roller", back="any", use=()),
           one("roller bed", "rb", "/obj/structure/bed/roller", back="any", use=())], near=lob)
    R.place(hang("wall NanoMed", "wallmed", "/obj/machinery/vending/wallmed"), near=ward, must=False)
    R.place(hang("wall NanoMed", "wallmed", "/obj/machinery/vending/wallmed"), near=store, must=False)
    R.place(hang("noticeboard", "noticeboard", "/obj/structure/noticeboard"), near=lob, must=False)
    R.place(hang("requests console", "requests_console", "/obj/machinery/requests_console",
                 {"department": "Medbay", "departmentType": 1}), near=store, must=False)
    # the east wing: visitors wait outside the patient rooms and the chief's door, not in a bare hall
    cmo_door = (R.doors("cmo") or [store])[0]
    rooms = (R.doors("roomA") or [cmo_door])[0]
    seats = bench(R, 3, near=cmo_door) + bench(R, 2, near=rooms)
    if seats:
        R.place(one("magazines", "t", TABLE, "/obj/item/newspaper", FIRSTAID + "/regular", back="any"),
                near=seats[0].origin, must=False)
    R.place(one("stretcher bay", "rb", "/obj/structure/bed/roller", back="any", use=()), near=store, must=False)
    # one plant by the chief's door: a plant at every door closed the street's mouth to one tile (v6 Medical review 3)
    R.place(PLANT_K, near=cmo_door, must=False)
    for spot in (lob, ward, store):
        R.mark(spot, MED_DOC)
    R.mark(R.room.attrs["heart"], "/obj/machinery/holopad")


# ================================================================================================= ward
SLEEPERS = Kit("sleeper pair", [
    cell(0, 0, ("/obj/machinery/sleeper", {"dir": "A+"}), label="SL"),
    cell(1, 0, ("/obj/machinery/computer/med_data", {"dir": "IN"}), label="MD"),
    cell(2, 0, GTABLE, FIRSTAID + "/regular", "/obj/item/storage/box/syringes", "/obj/item/reagent_containers/glass/beaker/large", label="g"),
    cell(3, 0, ("/obj/machinery/sleeper", {"dir": "A-"}), label="SL"),
], use=[(0, 1), (1, 1), (2, 1), (3, 1)], back="any")
IV = one("drip", "iv", "/obj/machinery/iv_drip", back="any", use=())


def recovery(R):
    # the sleepers stand on the wall away from the cryo bay so the ward stays one open floor with it
    door = (R.doors("medhall") or R.doors())[0]
    open_side = R.side("keep")
    wall = {1: 2, 2: 1, 4: 8, 8: 4}[open_side] if open_side else None
    pair = R.place(SLEEPERS, side=wall, far=door)
    if pair:
        R.zone(pair.tiles + pair.uses, floor=DARK)
    R.run([IV, IV], near=pair.origin if pair else door)
    R.place(one("roller bed", "rb", "/obj/structure/bed/roller", back="any", use=()), near=door, must=False)
    R.place(hang("wall NanoMed", "wallmed", "/obj/machinery/vending/wallmed"), near=door, must=False)
    R.place(hang("sink", "sink", "/obj/structure/sink"), far=door, must=False)


# ================================================================================================= surgery
OPTABLE = Kit("operating table", [
    cell(0, 0, "/obj/structure/table/optable", label="OT"),
    cell(1, 0, ("/obj/machinery/computer/operating", {"dir": "A-"}), label="OC"),
], use=[(0, 1), (0, -1), (-1, 0)], back=None)
SURG_TOOLS = one("instruments", "t", TABLE, "/obj/item/scalpel", "/obj/item/hemostat", "/obj/item/retractor",
                 "/obj/item/cautery", back="any")
SURG_SAWS = one("saws", "t", TABLE, "/obj/item/circular_saw", "/obj/item/surgicaldrill", "/obj/item/surgical_drapes",
                "/obj/item/clothing/gloves/color/latex", back="any")


def theatre(R):
    # the table stands free in the middle; instruments on the wall within a step; nothing between door and table
    door = (R.doors("scrub") or R.doors())[0]
    dwall = R.geo.field("dwall")
    table = R.place(OPTABLE, near=R.room.attrs["heart"], need=lambda pl: all(dwall.get(t, 0) >= 1 for t in pl.tiles))
    if table:
        R.zone(near_tiles(R, table.tiles), floor=DARK)
    R.run([SURG_TOOLS, SURG_SAWS], near=table.origin if table else None, far=None if table else door)
    R.place(one("anaesthetic locker", "L", "/obj/structure/closet/secure_closet/medical2"), far=door, must=False)
    R.place(one("blood", "bl", "/obj/structure/closet/crate/freezer/blood"), far=door, must=False)
    R.place(hang("sink", "sink", "/obj/structure/sink"), near=door, must=False)
    R.place(hang("defibrillator", "wallmed", "/obj/machinery/defibrillator_mount/loaded"), far=door, must=False)
    R.place(hang("no smoking", "sign", "/obj/structure/sign/warning/nosmoking"), near=door, must=False)


def scrub(R):
    # surgeons wash and gown here; patients are wheeled through, so the middle stays clear
    door = (R.doors("recovery") or R.doors())[0]
    R.place(hang("sink", "sink", "/obj/structure/sink"), near=door, must=False)
    R.place(hang("sink", "sink", "/obj/structure/sink"), near=door, must=False)
    R.run([one("gowns", "L", "/obj/structure/closet/secure_closet/medical2"),
           one("roller bed", "rb", "/obj/structure/bed/roller", back="any", use=())], far=door)
    R.mark(R.room.attrs["heart"], "/obj/machinery/holopad")


# ================================================================================================= store
KITS_A = one("trauma kits", "t", TABLE, (FIRSTAID + "/brute", {"pixel_x": 3, "pixel_y": 3}), FIRSTAID + "/fire",
             (FIRSTAID + "/toxin", {"pixel_x": -3, "pixel_y": -3}), FIRSTAID + "/o2", back="any")
KITS_B = one("lab supplies", "t", TABLE, ("/obj/item/storage/box/beakers", {"pixel_x": 3, "pixel_y": 3}),
             "/obj/item/storage/box/syringes", "/obj/item/storage/box/rxglasses", "/obj/item/hand_labeler", back="any")
STORE_BENCH = Kit("sorting bench", [
    cell(0, 0, TABLE, FIRSTAID + "/regular", "/obj/item/storage/box/gloves", label="t"),
    cell(1, 0, TABLE, "/obj/item/storage/box/masks", "/obj/item/storage/box/bodybags", label="t"),
], use=[(0, 1), (1, 1), (0, -1), (1, -1)], back=None)


def medstore(R):
    # everything a doctor fetches: the lathe, lockers, blood, kits. One of each, each with its front clear.
    door = (R.doors("medhall") or R.doors())[0]
    dwall = R.geo.field("dwall")
    R.place(one("medical lathe", "TF", "/obj/machinery/rnd/production/techfab/department/medical", decal=[BOT]), far=door)
    R.run([one("doctors' locker", "L", "/obj/structure/closet/secure_closet/medical3"),
           one("doctors' locker", "L", "/obj/structure/closet/secure_closet/medical3"),
           one("medicine locker", "L", "/obj/structure/closet/secure_closet/medical1")], near=door)
    R.run([KITS_A, KITS_B], far=door)
    R.place(one("blood", "bl", "/obj/structure/closet/crate/freezer/blood"), far=door, must=False)
    R.place(one("wardrobe", "W", "/obj/machinery/vending/wardrobe/medi_wardrobe"), near=door, must=False)
    R.place(STORE_BENCH, near=R.room.attrs["heart"], must=False, zone=(DARK, None),
            need=lambda pl: all(dwall.get(t, 0) >= 2 for t in pl.tiles) and apart(R, pl, 1))


# ================================================================================================= patient rooms
def patient(R):
    door = R.doors()[0]
    bed = R.place(one("bed", "bd", "/obj/structure/bed", "/obj/item/bedsheet/medical", back="any"), far=door)
    R.place(IV, near=bed.origin if bed else door, must=False)
    R.place(hang("privacy button", "button", "/obj/machinery/button/door",
                 {"name": "Privacy Shutters", "id": "medpriv_%s" % R.rid}), near=door, must=False)


# ================================================================================================= CMO
CMO_DESK = Kit("CMO desk", [
    cell(0, 0, TABLE, PAPER, "/obj/item/pen", "/obj/item/folder/white", label="t"),
    cell(1, 0, TABLE, "/obj/item/flashlight/lamp", "/obj/item/stamp/cmo", label="t"),
    seat_at(0, 1, OCHAIR, "/obj/effect/landmark/start/chief_medical_officer"),
], use=[(0, -1), (1, -1)], back=None)


def cmo(R):
    # the chief sits facing the door, the crew monitor at hand, the locker and suit behind
    door = R.doors()[0]
    dwall = R.geo.field("dwall")
    desk = R.place(CMO_DESK, near=R.room.attrs["heart"],
                   need=lambda pl: dist(pl.at(0, 1), door) > dist(pl.at(0, -1), door)
                   and all(dwall.get(t, 0) >= 1 for t in pl.tiles))
    chair = desk.at(0, 1) if desk else R.room.attrs["heart"]
    if desk:
        R.zone(near_tiles(R, desk.tiles), floor=CARPET)
    R.run([one("crew monitor", "C", ("/obj/machinery/computer/crew", {"dir": "IN"})),
           one("medical records", "C", ("/obj/machinery/computer/med_data", {"dir": "IN"}))], near=chair)
    R.run([one("CMO locker", "L", "/obj/structure/closet/secure_closet/CMO"),
           one("CMO suit", "SU", "/obj/machinery/suit_storage_unit/cmo")], far=door)
    R.place(one("files", "F", "/obj/structure/filingcabinet/chestdrawer", back="any"), near=door, must=False)
    R.place(BIN, far=chair, must=False)
    R.place(PLANT_K, near=door, must=False)
    R.place(hang("requests console", "requests_console", "/obj/machinery/requests_console",
                 {"department": "Chief Medical Officer's Desk", "departmentType": 5, "announcementConsole": 1}),
            near=chair, must=False)
    R.place(hang("keycard", "button", "/obj/machinery/keycard_auth"), near=chair, must=False)
    free = [p for p in R.tiles if R.free(p) and p not in R.front]
    if free:
        R.mark(min(free, key=lambda p: (dist(p, chair), p)), "/mob/living/simple_animal/pet/cat/Runtime")


# ================================================================================================= morgue
EAST, WEST = 4, 8
# The morgue tray in this codebase has one icon, drawn facing east, and slides out east. So trays stand in
# north-south columns, each with the tile east of it free; that free column is also the aisle for the next one.
TRAY_COLUMN = Kit("tray column", [cell(i, 0, ("/obj/structure/bodycontainer/morgue", {"dir": EAST}), label="MG") for i in range(3)],
                  use=[(i, 1) for i in range(3)], back=None, mirror=False, tight=True)


def morgue(R):
    # bodies come in from the ward door and leave by the hall. Columns of trays from the west wall, as Hippie has
    # them: tray, aisle, tray, aisle. Every tray opens onto its own aisle tile.
    door = (R.doors("medhall") or R.doors())[0]
    heart = R.room.attrs["heart"]
    col = R.place(TRAY_COLUMN, side=WEST, near=heart, need=lambda pl: all(step(t, WEST) not in R.tiles for t in pl.tiles))
    for _ in range(1):
        if col is None:
            break
        col = R.place(TRAY_COLUMN, side=WEST, must=False,
                      need=lambda pl, prev=col: all(step(t, WEST) in prev.uses for t in pl.tiles))
    R.run([one("body bags", "t", TABLE, "/obj/item/storage/box/bodybags", "/obj/item/pen", PAPER, back="any"),
           one("autopsy tools", "t", TABLE, "/obj/item/scalpel", "/obj/item/clothing/gloves/color/latex", back="any")], near=door)
    R.place(hang("sink", "sink", "/obj/structure/sink"), near=door, must=False)
    R.place(one("chair", "c", (CHAIR, {"dir": "IN"}), back="any", use=()), near=door, must=False)


ASSETS = {"lobby": lobby, "reception": reception, "medhall": medhall, "recovery": recovery, "theatre": theatre,
          "scrub": scrub, "medstore": medstore, "roomA": patient, "roomB": patient, "cmo": cmo, "morgue": morgue}
