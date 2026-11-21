"""Room assets for the v6 station's Security: security.py's brig rooms plus the ones the hand-drawn block adds.

  brighall    each cell's timer on the cell's own wall beside its door (a missing one is a problem, not a skip),
              benches by the warden's window, the bin, Beepsky's spot
  cells       bed, toilet and sink, the locker the timer opens, a flasher; shutters over the street windows
  holding     a bench along the back wall, a flasher; its timer on the hall like a cell's
  lobby       the public wait here: seats, the desk window, the entry flasher, the law on the wall, a vendor
  detective   desk facing the door with the lamp, records and medical consoles, the closet, files, the TV
  court       Meta's courtroom: the judge's bench at the far end, the two counsel tables facing it, the witness
              chair, the courtroom closet; the gallery's rows of chairs face the railing, the vendors by its doors
  exec        the education chamber's control side: the injections closet, the tools on a table, the ignition,
              flash and bolt buttons, a chair at the glass; the justice chamber: a bed, the sparker, the flasher
  perma       Meta's prison wing: a prison hall with the inmates' lockers, three long-term cells whose shutters open
              onto the common room or the garden, the common room, a garden and a sanitarium
"""
from forge.proc.place import Kit, cell, dist
from assets.security import (ASSETS as V1, CELL_IDS, button, frontdesk as frontdesk_v1, entry as entry_v1,
                             BRIEF_DESK as V1_BRIEF_DESK)
from assets.science import (TABLE, GTABLE, CHAIR, PAPER, PLANT_K, SEAT, BIN, BOT, SINK, one, hang, seat_at, apart,
                            near_tiles)

WOOD = "/obj/structure/table/wood"
LAMP = "/obj/item/flashlight/lamp/green"
FLASHER = "/obj/machinery/flasher"
TIMED = dict(CELL_IDS, holding="Holding Cell")


def sign(R, name, path, near):
    side = R.side("hall")
    if side is not None:
        R.place(hang(name, "sign", path), side=side, near=near, must=False)


STEP = {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0)}
TURN = {(0, 1): 1, (0, -1): 2, (1, 0): 4, (-1, 0): 8}


def desk_station(R, target, chair, consoles):
    """The tile just inside a desk (brigdesk/desk) to `target` gets the chair facing the desk; `consoles` stand on
    the tiles either side of it, facing the chair. Returns the chair tile."""
    for p, dr in sorted(R.geo.doors.items()):
        sp = dr.get("spec", {})
        if sp.get("type") not in ("brigdesk", "desk") or R.rid not in dr.get("sides", {}):
            continue
        if target not in dr.get("sides", {}) and dr.get("b") != target and dr.get("a") != target:
            continue
        q = dr["sides"][R.rid]
        d = TURN[(p[0] - q[0], p[1] - q[1])]
        R.put(q, "open", obj=[(chair[0], {"dir": d})] + list(chair[1:]))
        side = [(q[0] + STEP[d][1], q[1] + STEP[d][0]), (q[0] - STEP[d][1], q[1] - STEP[d][0])]
        for t, path in zip(side, consoles):
            if t in R.tiles and t not in R.geo.taken:
                R.put(t, "obj", obj=[(path, {"dir": TURN[(q[0] - t[0], q[1] - t[1])]})])
        return q
    return None


def chair_row(name, n, d):
    """n chairs side by side, all facing compass dir d (a gallery row, a bench)."""
    return Kit(name, [(i, 0, dict(obj=[(CHAIR, {"dir": d})], open=True, seat=True, label="c")) for i in range(n)],
               use=[], back=None, mirror=False)


# ================================================================================================= brig
def brighall(R):
    # every timed door's timer hangs on that room's own wall, beside the door, where the officer locking it stands
    for rid, cid in sorted(TIMED.items()):
        for d in R.doors(rid)[:1]:
            R.place(hang("%s timer" % cid, "status_display", "/obj/machinery/door_timer", {"id": cid, "name": cid}),
                    side=R.side(rid), near=d)
    entry = (R.doors("lobby") or R.doors())[0]
    warden = (R.doors("warden") or [entry])[0]
    R.place(hang("plaque", "sign", "/obj/structure/sign/plaques/golden"), near=entry, must=False)
    R.place(hang("ion rifle poster", "sign", "/obj/structure/sign/poster/official/ion_rifle"), far=entry, must=False)
    R.place(hang("report crimes", "sign", "/obj/structure/sign/poster/official/report_crimes"), must=False)
    R.place(BIN, near=warden, must=False)
    for _ in range(1):
        R.place(Kit("bench", [(i, 0, dict(obj=[(CHAIR, {"dir": "IN"})], open=True, seat=True, label="c"))
                              for i in range(2)], use=[], back="wall"), near=warden, must=False,
                need=lambda pl: all(t not in R.geo.taken for t in pl.tiles))
    R.mark(R.room.attrs["heart"], "/obj/effect/landmark/event_spawn")
    free = [p for p in R.tiles if R.free(p) and p not in R.front] or [R.room.attrs["heart"]]
    R.mark(min(free, key=lambda p: (dist(p, warden), p)), "/mob/living/simple_animal/bot/secbot/beepsky")


def cell_room(R):
    # the bed in the far corner, the toilet and sink on the other side wall, the locker the timer opens by the door
    cid = TIMED[R.rid]
    door = R.doors()[0]
    R.place(one("bed", "bd", "/obj/structure/bed", "/obj/item/bedsheet/orange", back="any"), far=door)
    R.place(one("toilet", "WC", ("/obj/structure/toilet", {"dir": "IN"})), far=door, must=False)
    R.place(SINK, far=door, must=False, need=lambda pl: pl.origin not in R.geo.taken and not R.geo.cells.get(pl.origin))
    R.place(one("cell locker", "L", ("/obj/structure/closet/secure_closet/brig", {"name": "%s Locker" % cid,
                                                                                    "id": cid})), near=door, must=False)
    R.place(hang("flasher", "button", FLASHER, {"id": cid}), far=door, must=False)


def holding(R):
    # people waiting to be processed: a bench along the back wall, flashed if they start something
    door = (R.doors("frontdesk") or R.doors())[0]
    R.place(Kit("bench", [(i, 0, dict(obj=[(CHAIR, {"dir": "IN"})], open=True, seat=True, label="c")) for i in range(3)],
                use=[], back="wall"), far=door, must=False)
    R.place(hang("flasher", "button", FLASHER, {"id": "Holding Cell"}), must=False)
    R.place(hang("crime poster", "sign", "/obj/structure/sign/poster/official/do_not_question"), must=False)


def lobby(R):
    # visitors wait on the seats along the inner wall; the entry flasher; the brig sign on the street side
    door = (R.doors("hall") or R.doors())[0]
    entry_v1(R)
    R.run([SEAT, SEAT, SEAT], far=door)
    R.place(one("coffee", "V", "/obj/machinery/vending/coffee"), must=False)
    R.place(PLANT_K, near=door, must=False)
    R.place(hang("space law", "sign", "/obj/structure/sign/plaques/golden"), far=door, must=False)
    R.place(hang("wanted", "sign", "/obj/structure/sign/poster/official/do_not_question"), must=False)
    sign(R, "brig sign", "/obj/structure/sign/plaques/deempisi", door)


def frontdesk(R):
    # the desk officer sits at the windoor onto the lobby, records at one hand
    seat = desk_station(R, "lobby", ("/obj/structure/chair/office", "/obj/effect/landmark/start/security_officer"),
                        ["/obj/machinery/computer/secure_data"])
    door = seat or (R.doors("brighall") or R.doors())[0]
    R.place(one("desk kit", "t", TABLE, PAPER, "/obj/item/pen", "/obj/item/restraints/handcuffs", "/obj/item/radio/off",
                back="wall"), near=door, must=False)
    for name, vs in (("Brig Exterior Doors Control", {"id": "outerbrig", "normaldoorcontrol": 1, "req_access_txt": "63"}),
                     ("Brig Interior Doors Control", {"id": "innerbrig", "normaldoorcontrol": 1, "req_access_txt": "63"}),
                     ("Desk Shutters", {"id": "briggate"})):
        R.place(button(name, vs), near=door, must=False)
    R.place(hang("entry flash", "button", "/obj/machinery/button/flasher", {"id": "brigentry"}), near=door, must=False)
    R.place(button("Holding Cell Bolts", {"id": "Holding Cell", "req_access_txt": "63"}), must=False)
    R.place(hang("brig telescreen", "status_display", "/obj/machinery/computer/security/telescreen/prison",
                 {"name": "Prison Monitor", "network": "list(\"prison\")"}), must=False)


def warden(R):
    # the warden sits at the desk window over the brig hall, prisoner and camera consoles either side
    seat = desk_station(R, "brighall", ("/obj/structure/chair/office", "/obj/effect/landmark/start/warden"),
                        ["/obj/machinery/computer/prisoner", "/obj/machinery/computer/security"])
    chair = seat or R.room.attrs["heart"]
    armory = (R.doors("armory") or [chair])[0]
    R.run([one("records", "C", ("/obj/machinery/computer/secure_data", {"dir": "IN"})),
           one("crew monitor", "C", ("/obj/machinery/computer/crew", {"dir": "IN"}))], near=chair)
    R.place(one("warden locker", "L", "/obj/structure/closet/secure_closet/warden"), far=chair, must=False)
    R.place(one("chargers", "t", TABLE, ("/obj/machinery/recharger", {"pixel_y": 4}), back="wall"), near=armory,
            must=False)
    R.place(one("law", "t", TABLE, "/obj/item/book/manual/wiki/security_space_law", "/obj/item/folder/red",
                "/obj/item/hand_labeler", back="wall"), must=False)
    R.place(one("files", "F", "/obj/structure/filingcabinet/chestdrawer", back="any"), must=False)
    for name, vs in (("Prison Wing Lockdown", {"id": "Prison Gate", "req_access_txt": "2"}),
                     ("Cell Shutters", {"id": "Secure Gate", "req_access_txt": "2"}),
                     ("Warden Office Shutters", {"id": "wardenshutter", "req_access_txt": "2"})):
        R.place(button(name, vs), near=chair, must=False)
    R.place(hang("requests console", "requests_console", "/obj/machinery/requests_console",
                 {"department": "Security", "departmentType": 5}), near=chair, must=False)


def armory(R):
    # guns on the far wall, armour and the lockers on the side walls, the middle clear to grab and go
    from assets.security import GUNS, ARMOUR, RACK
    door = (R.doors("warden") or R.doors())[0]
    R.run(GUNS, far=door)
    R.run(ARMOUR[:2])
    R.run([one("lethal shot locker", "L", "/obj/structure/closet/secure_closet/lethalshots"),
           one("implants", "t", TABLE, "/obj/item/storage/box/chemimp", "/obj/item/storage/box/trackimp",
               "/obj/item/storage/lockbox/loyalty", "/obj/item/storage/box/firingpins", back="wall"),
           one("ammo", "t", TABLE, "/obj/item/storage/box/rubbershot", "/obj/item/storage/box/flashbangs",
               "/obj/item/storage/box/teargas", "/obj/item/storage/box/handcuffs", back="wall")])
    R.run([one("contraband locker", "L", "/obj/structure/closet/secure_closet/contraband/armory"),
           one("security suit", "SU", "/obj/machinery/suit_storage_unit/security"),
           one("barriers", "t", TABLE, "/obj/item/grenade/barrier", "/obj/item/grenade/barrier",
               "/obj/item/key/security", back="wall")])
    for k in ARMOUR[2:]:
        R.place(k, must=False)
    R.place(one("pepper", "PT", "/obj/structure/reagent_dispensers/peppertank"), near=door, must=False)
    R.run([one("portable flasher", "pf", "/obj/machinery/flasher/portable", back="wall", use=())] * 2)
    R.place(button("Armory Shutters", {"id": "armoryshutter", "req_access_txt": "2"}), near=door, must=False)


def infirm(R):
    V1["infirm"](R)
    R.place(one("medkits", "g", GTABLE, "/obj/item/storage/firstaid/regular", "/obj/item/storage/firstaid/brute",
                "/obj/item/storage/firstaid/fire", back="any"), must=False)
    R.place(hang("medbay poster", "sign", "/obj/structure/sign/poster/official/cleanliness"), must=False)


def interro(R):
    V1["interro"](R)
    R.place(hang("interrogation screen", "status_display", "/obj/machinery/computer/security/telescreen/interrogation",
                 {"name": "isolation room monitor"}), must=False)
    R.place(hang("no smoking", "sign", "/obj/structure/sign/warning/nosmoking"), must=False)


# ================================================================================================= officers
def sechall(R):
    # a working corridor: nothing on the floor, the department's posters on the walls
    door = (R.doors("hall") or R.doors())[0]
    R.place(hang("secure area", "sign", "/obj/structure/sign/warning/securearea"), near=door, must=False)
    for poster in ("/obj/structure/sign/poster/official/help_others",):
        R.place(hang("poster", "sign", poster), must=False)


DET_DESK = Kit("detective desk", [
    cell(0, 0, WOOD, LAMP, PAPER, "/obj/item/pen", "/obj/item/folder/red", label="t"),
    seat_at(0, 1, "/obj/structure/chair/comfy/brown", "/obj/effect/landmark/start/detective"),
], use=[(0, -1)], back=None)


def detective(R):
    # the desk faces the door the clients come in by; consoles and the closet behind the detective
    door = (R.doors("hall") or R.doors())[0]
    dwall = R.geo.field("dwall")
    desk = R.place(DET_DESK, need=lambda pl: dist(pl.at(0, 1), door) > dist(pl.at(0, -1), door)
                   and dwall.get(pl.at(0, 0), 0) >= 2, must=False)
    if not desk:
        desk = R.place(DET_DESK, need=lambda pl: dist(pl.at(0, 1), door) > dist(pl.at(0, -1), door), must=False)
    chair = desk.at(0, 1) if desk else door
    R.run([one("records", "C", ("/obj/machinery/computer/secure_data", {"dir": "IN"})),
           one("medical records", "C", ("/obj/machinery/computer/med_data", {"dir": "IN"}))], near=chair)
    R.place(one("detective closet", "L", "/obj/structure/closet/secure_closet/detective"), far=door)
    R.place(one("files", "F", "/obj/structure/filingcabinet", back="any"), far=door, must=False)
    R.place(one("TV", "TV", ("/obj/machinery/computer/security/wooden_tv", {"dir": "IN"})), near=door, must=False)
    R.place(one("evidence kit", "t", WOOD, "/obj/item/storage/box/evidence", "/obj/item/camera/detective",
                "/obj/item/reagent_containers/food/drinks/bottle/whiskey", back="any"), must=False)
    R.place(one("client chair", "c", (CHAIR, {"dir": "IN"}), back="any", use=()), near=door, must=False)
    R.place(BIN, near=door, must=False)
    R.place(hang("requests console", "requests_console", "/obj/machinery/requests_console",
                 {"department": "Detective", "departmentType": 5}), near=chair, must=False)
    R.place(hang("noir poster", "sign", "/obj/structure/sign/poster/contraband/random"), must=False)


def evidence(R):
    # confiscated gear: lockers down the walls, a table with the bags; the middle clear
    door = R.doors()[0]
    R.run([one("evidence locker", "L", "/obj/structure/closet/secure_closet/evidence")] * 3, far=door)
    R.run([one("evidence locker", "L", "/obj/structure/closet")] * 2, near=door)
    R.place(one("bags", "t", TABLE, "/obj/item/storage/box/evidence", "/obj/item/storage/box/evidence",
                "/obj/item/hand_labeler", back="any"), near=door, must=False)


BRIEF_TABLE = Kit("briefing table", [
    cell(0, 0, TABLE, "/obj/item/storage/fancy/donut_box", label="t"),
    cell(1, 0, TABLE, PAPER, "/obj/item/pen", label="t"),
    cell(2, 0, TABLE, "/obj/item/folder/red", "/obj/item/book/manual/wiki/security_space_law", label="t"),
    (0, 1, dict(obj=[(CHAIR, {"dir": "OUT"})], open=True, seat=True, label="c")),
    (1, 1, dict(obj=[(CHAIR, {"dir": "OUT"})], open=True, seat=True, label="c")),
    (2, 1, dict(obj=[(CHAIR, {"dir": "OUT"})], open=True, seat=True, label="c")),
    (0, -1, dict(obj=[(CHAIR, {"dir": "IN"})], open=True, seat=True, label="c")),
    (1, -1, dict(obj=[(CHAIR, {"dir": "IN"})], open=True, seat=True, label="c")),
    (2, -1, dict(obj=[(CHAIR, {"dir": "IN"})], open=True, seat=True, label="c")),
], use=[], back=None, mirror=False)


def briefing(R):
    # the shift's briefing round one long table in the middle, the consoles on the wall away from the hall door,
    # the training gear and files along the other walls
    hall = (R.doors("sechall") or R.doors())[0]
    dwall = R.geo.field("dwall")
    table = R.place(BRIEF_TABLE, near=R.room.attrs["heart"], must=False,
                    need=lambda pl: all(dwall.get(pl.at(u, 0), 0) >= 2 for u in range(3)))
    R.place(V1_BRIEF_DESK, far=hall, must=False)
    R.place(one("training bomb", "TB", "/obj/machinery/syndicatebomb/training", back="any"), must=False)
    R.place(one("practice", "t", TABLE, "/obj/item/gun/energy/laser/practice", "/obj/item/assembly/flash/handheld",
                "/obj/item/restraints/handcuffs", back="any"), must=False)
    R.place(one("files", "F", "/obj/structure/filingcabinet", back="any"), must=False)
    R.place(one("recharger", "t", TABLE, ("/obj/machinery/recharger", {"pixel_y": 4}), back="any"), near=hall,
            must=False)
    R.place(one("coffee", "t", TABLE, "/obj/item/reagent_containers/food/drinks/coffee",
                "/obj/item/reagent_containers/food/drinks/coffee", back="any"), must=False)
    R.place(PLANT_K, must=False)
    R.place(hang("noticeboard", "noticeboard", "/obj/structure/noticeboard"), near=hall, must=False)
    R.place(hang("requests console", "requests_console", "/obj/machinery/requests_console",
                 {"department": "Security", "departmentType": 5}), near=hall, must=False)
    R.place(hang("station map", "sign", "/obj/structure/sign/map/left"), must=False)
    if table:
        for u in range(3):
            for v in (1, -1):
                R.mark(table.at(u, v), "/obj/effect/landmark/start/security_officer")
    R.mark(R.room.attrs["heart"], "/obj/machinery/holopad/secure")


# ================================================================================================= court
# the bench runs wall to wall across its alcove, the judge behind its middle (Meta's bench is one long table)
JUDGE = Kit("judge's bench", [
    (1, 0, dict(obj=[("/obj/structure/chair/comfy/black", {"dir": "IN"})], open=True, seat=True, label="c")),
    cell(0, 1, WOOD, PAPER, "/obj/item/pen", label="t"),
    cell(1, 1, WOOD, "/obj/item/gavelblock", "/obj/item/gavelhammer", label="t"),
    cell(2, 1, WOOD, "/obj/item/book/manual/wiki/security_space_law", label="t"),
], use=[(1, 2)], back="wall", tight=True)


def counsel(name, folder):
    return Kit(name, [
        cell(0, 0, WOOD, folder, "/obj/item/pen", label="t"),
        seat_at(0, 1, CHAIR),
    ], use=[(0, -1)], back=None, mirror=False)


def court(R):
    # the judge at the far end from the public gate, facing it; prosecution and defence facing the judge; the
    # witness chair beside the bench; the closet with the court's robes
    gate = (R.doors("gallery") or R.doors())[0]
    dwall = R.geo.field("dwall")
    centred = lambda pl: all(dwall.get(pl.at(u, 1), 0) >= 1 for u in range(3))
    bench = R.place(JUDGE, side=1, far=gate, need=centred, must=False) or R.place(JUDGE, far=gate, must=False)
    ref = bench.at(1, 2) if bench else R.room.attrs["heart"]
    # counsel: mirrored tables across the room facing the bench, chairs behind them (plan 74/77,63 and 74/77,64)
    for (tx, ty), folder in (((80, 102), "/obj/item/folder/red"), ((83, 102), "/obj/item/folder/blue")):
        if (tx, ty) in R.tiles and (tx, ty - 1) in R.tiles:
            R.put((tx, ty), "obj", obj=["/obj/structure/table/wood", folder, "/obj/item/pen"])
            R.put((tx, ty - 1), "open", obj=[(CHAIR, {"dir": 1})])
    R.place(one("witness", "c", (CHAIR, {"dir": "IN"}), back="any", use=()), near=ref, must=False)
    R.place(one("court closet", "L", "/obj/structure/closet/secure_closet/courtroom"), far=ref, must=False)
    R.place(hang("court flasher", "button", FLASHER, {"id": "courtflash"}), must=False)
    R.mark(R.room.attrs["heart"], "/obj/effect/landmark/start/lawyer")


def gallery(R):
    # the public sit in rows facing the railing; the vendors by the street doors
    gate = (R.doors("court") or R.doors())[0]
    side = R.side("court")
    d = {1: 1, 2: 2, 4: 4, 8: 8}.get(side, 8)
    # two north-south columns of seats facing the railing, the gate's row left clear (plan x 81 and 83)
    for x in (87, 89):
        for y in (103, 102, 100, 99):
            if (x, y) in R.tiles and (x, y) not in R.geo.taken:
                R.put((x, y), "open", obj=[(CHAIR, {"dir": d})])
    street = (R.doors("hall") or [gate])[0]
    R.place(one("coffee", "V", "/obj/machinery/vending/coffee"), near=street, must=False)
    R.place(hang("court sign", "sign", "/obj/structure/sign/plaques/golden"), must=False)


def courtcell(R):
    R.place(one("bench", "c", (CHAIR, {"dir": "IN"}), back="any", use=()), must=False)
    R.place(hang("flasher", "button", FLASHER, {"id": "courtflash"}), must=False)


# ================================================================================================= execution
EXEC_DESK = Kit("execution desk", [
    cell(0, 0, TABLE, "/obj/item/electropack", "/obj/item/assembly/signaler", "/obj/item/clothing/mask/muzzle",
         label="t"),
    cell(1, 0, TABLE, "/obj/item/reagent_containers/syringe", "/obj/item/reagent_containers/glass/bottle/morphine",
         "/obj/item/reagent_containers/glass/bottle/chloralhydrate", label="t"),
    seat_at(0, 1, "/obj/structure/chair/office"),
], use=[(0, 1), (1, 1)], back="wall")


def exec_room(R):
    # the control side of the justice chamber: tools on the table, the chamber's controls on the wall by the glass
    glass_side = R.side("justice")
    R.place(EXEC_DESK, must=False)
    R.place(one("injections", "L", "/obj/structure/closet/secure_closet/injection"), must=False)
    R.place(one("pepper", "PT", "/obj/structure/reagent_dispensers/peppertank"), must=False)
    # the chamber's three controls side by side on the control room's solid north wall, one per tile
    top = max(p[1] for p in R.tiles)
    row = sorted(p for p in R.tiles if p[1] == top)[-3:]
    for p, (name, path, vs) in zip(row, (
            ("Justice Ignition Switch", "/obj/machinery/button/ignition", {"id": "executionburn"}),
            ("Justice Flash Control", "/obj/machinery/button/flasher", {"id": "justiceflash"}),
            ("Door Bolt Control", "/obj/machinery/button/door",
             {"id": "prisonereducation", "normaldoorcontrol": 1, "specialfunctions": 4}))):
        R.put(p, None, obj=[(path, dict({"name": name, "pixel_y": 26}, **vs))])
        R.faces[(p, 1)] = name


def justice(R):
    R.place(one("bed", "bd", "/obj/structure/bed", "/obj/item/restraints/handcuffs", back="any"), must=False)
    R.place(hang("sparker", "button", "/obj/machinery/sparker", {"id": "executionburn"}), must=False)
    R.place(hang("justice flash", "button", FLASHER, {"id": "justiceflash", "name": "mounted justice flash"}),
            must=False)


# ================================================================================================= perma
def prisonhall(R):
    # the inmates' own clothes wait in lockers by the door; the way to the cells stays clear
    door = (R.doors("brighall") or R.doors())[0]
    R.run([one("prisoner locker", "L", "/obj/structure/closet/secure_closet/brig")] * 3, near=door)
    R.place(one("pepper", "PT", "/obj/structure/reagent_dispensers/peppertank"), near=door, must=False)
    R.place(hang("prison screen", "status_display", "/obj/machinery/computer/security/telescreen/prison",
                 {"name": "Prison Monitor", "network": "list(\"prison\")"}), near=door, must=False)
    R.place(hang("perma flasher", "button", FLASHER, {"id": "PCell"}), far=door, must=False)


def lt_cell(R):
    door = (R.doors("prisonhall") or R.doors())[0]
    R.place(one("bed", "bd", "/obj/structure/bed", "/obj/item/bedsheet/orange", back="any"), far=door)
    R.place(one("toilet", "WC", ("/obj/structure/toilet", {"dir": "IN"})), far=door, must=False)
    R.place(hang("flasher", "button", FLASHER, {"id": "PCell"}), far=door, must=False)
    shut = R.doors("permacommon") or R.doors("garden")
    R.place(button("Cell Shutters", {"id": "permacell%s" % R.rid[-1], "req_access_txt": "2"}),
            near=shut[0] if shut else door, must=False)


def sanit(R):
    door = R.doors()[0]
    R.run([one("bed", "bd", "/obj/structure/bed", "/obj/item/bedsheet/medical", back="any"),
           one("bed", "bd", "/obj/structure/bed", "/obj/item/bedsheet/medical", back="any")], far=door)
    R.place(one("drip", "iv", "/obj/machinery/iv_drip", back="any", use=()), must=False)
    R.place(hang("flasher", "button", FLASHER, {"id": "PCell"}), must=False)


COMMON_TABLE = Kit("common table", [
    cell(0, 0, TABLE, "/obj/item/toy/cards/deck", label="t"),
    cell(1, 0, TABLE, "/obj/item/storage/pill_bottle/dice", label="t"),
    (0, 1, dict(obj=[(CHAIR, {"dir": "OUT"})], open=True, seat=True, label="c")),
    (1, 1, dict(obj=[(CHAIR, {"dir": "OUT"})], open=True, seat=True, label="c")),
    (0, -1, dict(obj=[(CHAIR, {"dir": "IN"})], open=True, seat=True, label="c")),
    (1, -1, dict(obj=[(CHAIR, {"dir": "IN"})], open=True, seat=True, label="c")),
], use=[], back=None, mirror=False)


def permacommon(R):
    # the inmates' day room: a table in the middle, the vendor, the arcade and the TV on the walls, a shower corner
    dwall = R.geo.field("dwall")
    R.place(COMMON_TABLE, near=R.room.attrs["heart"], must=False,
            need=lambda pl: apart(R, pl, 1) and all(dwall.get(t, 0) >= 1 for t in pl.tiles))
    R.place(one("sustenance", "V", "/obj/machinery/vending/sustenance"))
    R.place(one("arcade", "AR", ("/obj/machinery/computer/arcade/battle", {"dir": "IN"})), must=False)
    R.place(one("books", "BK", ("/obj/machinery/computer/libraryconsole/bookmanagement", {"dir": "IN"})), must=False)
    R.place(one("washer", "WM", "/obj/machinery/washing_machine"), must=False)
    R.place(one("easel", "ea", "/obj/structure/easel", "/obj/item/canvas/twentythreeXtwentythree", back="any"),
            must=False)
    R.place(one("microwave", "MW", TABLE, "/obj/machinery/microwave"), must=False)
    R.place(one("shower", "SH", ("/obj/machinery/shower", {"dir": "IN"}), back="wall", use=()), must=False)
    R.place(one("hoop", "HH", "/obj/structure/holohoop", back="wall"), must=False, need=lambda pl: apart(R, pl, 1))
    R.place(hang("TV", "status_display", "/obj/machinery/computer/security/telescreen/entertainment"), must=False)
    R.place(hang("flasher", "button", FLASHER, {"id": "PCell"}), must=False)


def garden(R):
    # trays on the walls, the seed extractor and the biogenerator, the tools on a table
    R.place(one("water", "WT", "/obj/structure/reagent_dispensers/watertank"))
    R.place(one("biogen", "BG", "/obj/machinery/biogenerator"))
    R.place(one("seeds", "SX", "/obj/machinery/seed_extractor"))
    R.run([one("tray", "HT", "/obj/machinery/hydroponics/constructable", decal=[BOT], back="any")] * 4)
    R.place(one("tools", "t", TABLE, "/obj/item/cultivator", "/obj/item/reagent_containers/glass/bucket",
                "/obj/item/plant_analyzer", "/obj/item/seeds/potato", "/obj/item/seeds/carrot", back="any"),
            must=False)


ASSETS = dict(V1)
ASSETS.update({"warden": warden, "armory": armory, "brighall": brighall, "cell1": cell_room, "cell2": cell_room, "cell3": cell_room, "holding": holding,
               "lobby": lobby, "frontdesk": frontdesk, "infirm": infirm, "interro": interro, "sechall": sechall,
               "detective": detective, "evidence": evidence, "briefing": briefing, "court": court,
               "gallery": gallery, "courtcell": courtcell, "exec": exec_room, "justice": justice,
               "prisonhall": prisonhall, "lt1": lt_cell, "lt2": lt_cell, "lt3": lt_cell, "sanit": sanit,
               "permacommon": permacommon, "garden": garden})


# ================================================================================================= review 2 (11-21)
def armory3(R):
    armory(R)
    # what the placer could not fit, set by hand on the side walls (plan coordinates in the comments)
    for (px, py), objs in (((67, 61), [RACK_P, "/obj/item/clothing/suit/armor/riot", "/obj/item/clothing/head/helmet/riot",
                                       "/obj/item/shield/riot"]),
                           ((68, 58), [RACK_P, "/obj/item/gun/energy/e_gun/dragnet", "/obj/item/gun/energy/ionrifle",
                                       "/obj/item/clothing/suit/armor/laserproof"]),
                           ((64, 58), ["/obj/structure/table", "/obj/item/grenade/barrier", "/obj/item/grenade/barrier"]),
                           ((64, 60), ["/obj/machinery/suit_storage_unit/security"])):
        p = (px + 6, 165 - py)
        if p in R.tiles and R.geo.taken.get(p) != "obj" and p not in R.doors():     # never a door's own tile
            R.put(p, "obj", obj=objs)
        else:
            R.geo.problem("armory: no room for %s at plan %d,%d" % (objs[-1].rsplit("/", 1)[-1], px, py))


RACK_P = "/obj/structure/rack"


def hos2(R):
    V1["hos"](R)


ASSETS.update({"armory": armory3})


def garden3(R):
    garden(R)
    p = (59 + 6, 165 - 51)           # plan 59,51: between the water tank and the trays
    if p in R.tiles and R.geo.taken.get(p) != "obj":
        R.put(p, "obj", obj=["/obj/structure/table", "/obj/item/cultivator", "/obj/item/reagent_containers/glass/bucket",
                             "/obj/item/plant_analyzer", "/obj/item/seeds/potato", "/obj/item/seeds/carrot"])
    else:
        R.geo.problem("garden: no room for the tools table")


def hos3(R):
    # the head faces the door; the ID, camera and records consoles on the wall right behind the chair
    from assets.security import HOS_DESK
    door = R.doors()[0]
    dwall = R.geo.field("dwall")
    desk = R.place(HOS_DESK, near=R.room.attrs["heart"],
                   need=lambda pl: dist(pl.at(0, 1), door) > dist(pl.at(0, -1), door)
                   and all(dwall.get(t, 0) >= 1 for t in pl.tiles))
    chair = desk.at(0, 1) if desk else R.room.attrs["heart"]
    R.run([one("ID console", "C", ("/obj/machinery/computer/card/minor/hos", {"dir": "IN"})),
           one("cameras", "C", ("/obj/machinery/computer/security/hos", {"dir": "IN"})),
           one("records", "C", ("/obj/machinery/computer/secure_data", {"dir": "IN"}))], near=chair,
          need=lambda pl: dist(pl.origin, chair) <= 2)
    R.run([one("HoS locker", "L", "/obj/structure/closet/secure_closet/hos"),
           one("HoS suit", "SU", "/obj/machinery/suit_storage_unit/hos")], far=chair)
    R.place(BIN, near=door, must=False)
    R.place(hang("keycard", "button", "/obj/machinery/keycard_auth"), near=chair, must=False)
    R.place(button("Space Shutters", {"id": "HOSOfficespace", "req_access_txt": "58"}), near=chair, must=False)
    R.place(hang("requests console", "requests_console", "/obj/machinery/requests_console",
                 {"department": "Head of Security's Desk", "departmentType": 5, "announcementConsole": 1}),
            near=chair, must=False)
    free = [p for p in R.tiles if R.free(p) and p not in R.front]
    if free:
        R.mark(min(free, key=lambda p: (dist(p, chair), p)), "/mob/living/simple_animal/pet/dog/pug")


def infirm3(R):
    # a sleeper for the beaten with its front clear, beds for the restrained, the meds on a table by the door
    door = R.doors()[0]
    R.place(one("sleeper", "SL", ("/obj/machinery/sleeper", {"dir": "A+"})), far=door)
    R.run([one("bed", "bd", "/obj/structure/bed", "/obj/item/clothing/suit/straight_jacket", back="any"),
           one("bed", "bd", "/obj/structure/bed", "/obj/item/clothing/suit/straight_jacket", back="any")])
    R.place(one("meds", "g", GTABLE, "/obj/item/reagent_containers/glass/bottle/charcoal",
                "/obj/item/reagent_containers/glass/bottle/epinephrine", "/obj/item/reagent_containers/syringe",
                "/obj/item/storage/firstaid/regular", "/obj/item/storage/firstaid/brute", back="any"),
            near=door, must=False)
    R.place(one("drip", "iv", "/obj/machinery/iv_drip", back="any", use=()), must=False)


ASSETS.update({"garden": garden3, "hos": hos3, "infirm": infirm3})


# ================================================================================================= review r3 (11-21)
# the warden's buttons open real doors (the builder now takes down buttons that open nothing)
def armory4(R):
    armory3(R)
    for q in R.doors("warden"):
        R.put(q, "open", obj=[("/obj/machinery/door/poddoor/shutters/preopen", {"id": "armoryshutter",
                                                                                  "name": "Armory Shutters"})])


def prisonhall4(R):
    prisonhall(R)
    for q in R.doors("permaentry"):
        R.put(q, "open", obj=[("/obj/machinery/door/poddoor/preopen", {"id": "Prison Gate",
                                                                         "name": "Prison Wing Blast Door"})])


ASSETS.update({"armory": armory4, "prisonhall": prisonhall4})
