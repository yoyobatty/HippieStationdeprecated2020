"""Room assets for the v6 station's Medical: medbay_v2's rooms plus the ones the new block carries itself.

  ward        sleepers and the cryo loop share one open room (no kept cryo bay here: the loop is a kit)
  chemistry   two benches, the chem fridge, a desk onto the public hall where prescriptions are handed out
  genetics    the cloning line (scanner, console, pod) and the DNA bench, monkey cubes at hand
"""
from forge.proc.place import Kit, cell, dist
from assets.medical import ASSETS as V2, SLEEPERS, IV, FIRSTAID, MED_DOC, lobby as lobby_v2
from assets.science import (TABLE, GTABLE, DARK, BOT, PIPE, CHAIR, PLANT_K, BIN, one, hang, button, seat_at, near_tiles)

SIGN = "/obj/structure/sign/departments"


def sign(R, name, path, near):
    # a department sign on the hall side of the room, by its public door; the builder turns it to face the hall
    side = R.side("hall")
    if side is not None:
        R.place(hang(name, "sign", path), side=side, near=near, must=False)

AT = "/obj/machinery/atmospherics/components"
MANIFOLD = "/obj/machinery/atmospherics/pipe/manifold/general/visible"

# ================================================================================================= ward
# freezer -> pipe -> manifold -> pipe -> manifold -> pipe -> the oxygen port, a cryo cell on each manifold. The
# pipe tiles between keep every machine off its neighbour's diagonal (the placer reads that as a pinched aisle). Every cryo cell
# connects in its own dir, so each faces the wall where its pipe runs.
CRYO = Kit("cryo loop", [
    cell(0, 0, (AT + "/unary/thermomachine/freezer/on", {"dir": "A+"}), label="FZ"),
    (1, 0, dict(obj=[(PIPE, {"dir": "A+"})], open=True, label="=")),
    (2, 0, dict(obj=[(MANIFOLD, {"dir": "OUT"})], open=True, label="=")),
    cell(2, 1, (AT + "/unary/cryo_cell", {"dir": "OUT"}), label="CR"),
    (3, 0, dict(obj=[(PIPE, {"dir": "A+"})], open=True, label="=")),
    (4, 0, dict(obj=[(MANIFOLD, {"dir": "OUT"})], open=True, label="=")),
    cell(4, 1, (AT + "/unary/cryo_cell", {"dir": "OUT"}), label="CR"),
    (5, 0, dict(obj=[(PIPE, {"dir": "A+"})], open=True, label="=")),
    cell(6, 0, (AT + "/unary/portables_connector/visible", {"dir": "A-"}),
         "/obj/machinery/portable_atmospherics/canister/oxygen", decal=[BOT], label="O2"),
], use=[(0, 1), (2, 2), (4, 2), (6, 1)], back="wall", mirror=True)
BED = one("bed", "bd", "/obj/structure/bed", "/obj/item/bedsheet/medical", back="any")
CRYOX = one("cryo beakers", "g", GTABLE, "/obj/item/reagent_containers/glass/beaker/cryoxadone",
            "/obj/item/reagent_containers/glass/beaker/cryoxadone", back="any")


def recovery(R):
    # patients come in from the hall door: the cryo loop on the far wall, the sleepers along the outer wall, drips
    # and rollers by the door, the middle kept clear for a roller bed to turn
    door = (R.doors("medhall") or R.doors())[0]
    loop = R.place(CRYO, far=door)
    if loop:
        R.zone(loop.tiles, floor=DARK)
        R.place(CRYOX, near=loop.origin, must=False)
    pair = R.place(SLEEPERS, far=door, side=R.side("hall") or None, must=False) or R.place(SLEEPERS, far=door)
    if pair:
        R.zone(pair.tiles + pair.uses, floor=DARK)
    R.run([IV, IV], near=pair.origin if pair else door)
    pair2 = R.place(SLEEPERS, far=door, must=False)
    if pair2:
        R.zone(pair2.tiles + pair2.uses, floor=DARK)
    # recovery beds along a wall, a drip between each two: where patients lie once they are out of the sleeper
    R.run([BED, IV, BED, IV, BED], near=R.room.attrs["heart"])
    R.run([one("roller bed", "rb", "/obj/structure/bed/roller", back="any", use=()),
           one("roller bed", "rb", "/obj/structure/bed/roller", back="any", use=())], near=door)
    R.place(hang("wall NanoMed", "wallmed", "/obj/machinery/vending/wallmed"), near=door, must=False)
    R.place(hang("defibrillator", "wallmed", "/obj/machinery/defibrillator_mount/loaded"), near=door, must=False)
    R.place(hang("sink", "sink", "/obj/structure/sink"), far=door, must=False)
    R.mark(door, MED_DOC)


# ================================================================================================= lobby
SEAT_ISLAND = Kit("seat island", [
    cell(0, 0, (CHAIR, {"dir": 2}), label="c"), cell(1, 0, (CHAIR, {"dir": 2}), label="c"),
    cell(0, 1, (CHAIR, {"dir": 1}), label="c"), cell(1, 1, (CHAIR, {"dir": 1}), label="c"),
], use=[(0, -1), (1, -1), (0, 2), (1, 2)], back=None, mirror=False)


def lobby(R):
    # the walls as v2 has them; a back-to-back seat island in the middle where the lobby is wide enough for one
    lobby_v2(R)
    sign(R, "medbay sign", SIGN + "/medbay/alt", (R.doors("hall") or R.doors())[0])
    dwall = R.geo.field("dwall")
    R.place(SEAT_ISLAND, near=R.room.attrs["heart"], must=False, need=lambda pl: all(dwall.get(t, 0) >= 2 for t in pl.tiles))


# ================================================================================================= chemistry
CHEM_BENCH = Kit("chem bench", [
    cell(0, 0, "/obj/machinery/chem_dispenser", label="CD"),
    cell(1, 0, "/obj/machinery/chem_heater", label="CH"),
    cell(2, 0, "/obj/machinery/chem_master", label="CM"),
], use=[(0, 1), (1, 1), (2, 1)])
CHEM_SUPPLY = one("chem supplies", "t", GTABLE, "/obj/item/storage/box/beakers", "/obj/item/storage/box/pillbottles",
                  "/obj/item/reagent_containers/dropper", "/obj/item/hand_labeler", back="any")
GRINDER = one("grinder", "t", GTABLE, ("/obj/machinery/reagentgrinder", {"pixel_y": 6}), "/obj/item/stack/sheet/mineral/plasma",
              back="any")


def chemistry(R):
    # two chemists at two benches facing the wall, the fridge by the hand-out desk so a finished order goes
    # straight out; lockers and the wardrobe by the staff door
    door = (R.doors("medhall") or R.doors())[0]
    desk = (R.doors("hall") or [door])[0]
    R.place(one("chem fridge", "SF", "/obj/machinery/smartfridge/chemistry/preloaded"), near=desk)
    benches = R.run([CHEM_BENCH, CHEM_BENCH], far=door)
    for b in benches:
        R.zone(b.tiles, floor=DARK)
    R.run([CHEM_SUPPLY, GRINDER], near=benches[0].origin if benches else desk)
    R.run([one("chem locker", "L", "/obj/structure/closet/secure_closet/chemical"),
           one("ChemDrobe", "W", "/obj/machinery/vending/wardrobe/chem_wardrobe")], near=door)
    R.place(hang("sink", "sink", "/obj/structure/sink"), near=door, must=False)
    R.place(BIN, near=door, must=False)
    R.place(button("Chemistry Shutters", "b", {"name": "Chemistry Shutters", "id": "chem_desk", "req_access_txt": "33"}),
            near=desk, must=False)
    sign(R, "chemistry sign", SIGN + "/chemistry", desk)
    R.mark(desk, "/obj/effect/landmark/start/chemist")


# ================================================================================================= genetics
CLONE_LINE = Kit("cloning line", [
    cell(0, 0, "/obj/machinery/dna_scannernew", label="DS"),
    cell(1, 0, ("/obj/machinery/computer/cloning", {"dir": "IN"}), label="CC"),
    cell(2, 0, "/obj/machinery/clonepod", label="CP"),
], use=[(0, 1), (1, 1), (2, 1)])
DNA_BENCH = Kit("DNA bench", [
    cell(0, 0, "/obj/machinery/dna_scannernew", label="DS"),
    cell(1, 0, ("/obj/machinery/computer/scan_consolenew", {"dir": "IN"}), label="DC"),
], use=[(0, 1), (1, 1)])
GENE_ISLAND = Kit("gene bench", [
    cell(0, 0, TABLE, "/obj/item/storage/box/syringes", "/obj/item/reagent_containers/glass/beaker", label="t"),
    cell(1, 0, TABLE, "/obj/item/flashlight/pen", "/obj/item/clothing/gloves/color/latex", label="t"),
], use=[(0, 1), (1, 1), (0, -1), (1, -1)], back=None)
GENE_SUPPLY = one("gene supplies", "t", TABLE, "/obj/item/storage/box/monkeycubes", "/obj/item/storage/box/disks",
                  "/obj/item/storage/box/rxglasses", back="any")


def genetics(R):
    # the dead come in by the hall door on a roller and go straight to the cloning line; the DNA bench is the
    # geneticists' own corner, away from the door
    door = (R.doors("medhall") or R.doors())[0]
    line = R.place(CLONE_LINE, near=door)
    if line:
        R.zone(line.tiles, floor=DARK)
    bench = R.place(DNA_BENCH, far=door)
    if bench:
        R.zone(bench.tiles, floor=DARK)
    R.place(GENE_SUPPLY, near=bench.origin if bench else door, must=False)
    dwall = R.geo.field("dwall")
    R.place(GENE_ISLAND, near=R.room.attrs["heart"], must=False, need=lambda pl: all(dwall.get(t, 0) >= 2 for t in pl.tiles))
    R.run([one("gene wardrobe", "W", "/obj/machinery/vending/wardrobe/gene_wardrobe"),
           one("roller bed", "rb", "/obj/structure/bed/roller", back="any", use=())], near=door)
    R.place(PLANT_K, far=door, must=False)
    R.mark(door, "/obj/effect/landmark/start/geneticist")


    # the geneticists' worktop along a free wall, and a pair of monkeys for the DNA bench
    R.run([one("gene tools", "t", TABLE, "/obj/item/storage/box/syringes", "/obj/item/flashlight/pen",
               "/obj/item/clothing/gloves/color/latex", back="any"),
           one("gene beakers", "t", TABLE, "/obj/item/reagent_containers/glass/beaker",
               "/obj/item/reagent_containers/dropper", back="any")], far=door)
    for _ in range(2):
        free = [p for p in R.tiles if R.free(p) and p not in R.front]
        if bench and free:
            R.mark(min(free, key=lambda p: (abs(p[0] - bench.origin[0]) + abs(p[1] - bench.origin[1]), p)),
                   "/mob/living/carbon/monkey")


# ================================================================================================= reception
def reception(R):
    # v2's monitor, files and forms, and the records console and a medicine locker the desk hands out from
    V2["reception"](R)
    desk = (R.doors("lobby") or R.doors())[0]
    R.place(button("Reception Shutters", "b", {"name": "Reception Shutters", "id": "med_reception", "req_access_txt": "5"}),
            near=desk, must=False)
    R.place(one("medical records", "C", ("/obj/machinery/computer/med_data", {"dir": "IN"})), near=desk, must=False)
    R.place(one("medicine locker", "L", "/obj/structure/closet/secure_closet/medical1"), far=desk, must=False)
    R.place(hang("wall NanoMed", "wallmed", "/obj/machinery/vending/wallmed"), far=desk, must=False)
    R.place(PLANT_K, far=desk, must=False)


# ================================================================================================= store
STORE_BENCH = Kit("sorting bench", [
    cell(0, 0, TABLE, FIRSTAID + "/regular", "/obj/item/storage/box/gloves", label="t"),
    cell(0, 1, TABLE, "/obj/item/storage/box/masks", "/obj/item/storage/box/bodybags", label="t"),
], use=[(-1, 0), (-1, 1), (1, 0), (1, 1)], back=None, mirror=False)


def medstore(R):
    # v2's lathe, lockers, kits and blood; a sorting bench down the middle where the room is wide enough to walk
    # round it, and the belts and the spare defibrillator on a table by the door
    V2["medstore"](R)
    door = (R.doors("medhall") or R.doors())[0]
    dwall = R.geo.field("dwall")
    R.place(STORE_BENCH, near=R.room.attrs["heart"], must=False, zone=(DARK, None),
            need=lambda pl: all(dwall.get(t, 0) >= 2 for t in pl.tiles))
    R.run([one("belts", "t", TABLE, "/obj/item/storage/belt/medical", "/obj/item/storage/belt/medical", back="any"),
           one("defibrillator", "t", TABLE, "/obj/item/defibrillator/loaded", back="any")], near=door)
    R.place(hang("wall NanoMed", "wallmed", "/obj/machinery/vending/wallmed"), near=door, must=False)


# ================================================================================================= scrub
def scrub(R):
    # v2's sinks, gowns and roller; masks and gloves on a table and a wall NanoMed for the surgeons going in
    V2["scrub"](R)
    door = (R.doors("theatre") or R.doors())[0]
    R.place(one("scrubs", "t", TABLE, "/obj/item/clothing/mask/surgical", "/obj/item/clothing/mask/surgical",
                "/obj/item/storage/box/gloves", back="any"), near=door, must=False)
    R.place(hang("wall NanoMed", "wallmed", "/obj/machinery/vending/wallmed"), far=door, must=False)


# ================================================================================================= patient rooms
def patient(R):
    # a bed away from the door, its drip, a chair for a visitor. No privacy button: these rooms have no window to
    # shutter
    door = R.doors()[0]
    bed = R.place(one("bed", "bd", "/obj/structure/bed", "/obj/item/bedsheet/medical", back="any"), far=door)
    # the drip stands right beside the bed (review 1: it had drifted to the far wall)
    R.place(IV, near=bed.origin if bed else door, must=False,
            need=lambda pl: bed is None or max(abs(pl.origin[0] - bed.origin[0]), abs(pl.origin[1] - bed.origin[1])) == 1)
    R.place(one("visitor chair", "c", (CHAIR, {"dir": "IN"}), back="any", use=()), near=bed.origin if bed else door,
            must=False)


def exam(R):
    # Meta's exam room: a bed, the doctor's table with a health analyzer, a chair, the wall NanoMed
    door = R.doors()[0]
    R.place(one("exam bed", "bd", "/obj/structure/bed", "/obj/item/bedsheet/medical", back="any"), far=door)
    R.place(one("exam table", "t", TABLE, "/obj/item/healthanalyzer", "/obj/item/clipboard", back="wall"), must=False)
    R.place(one("chair", "c", (CHAIR, {"dir": "IN"}), back="any", use=()), near=door, must=False)
    R.place(hang("wall NanoMed", "wallmed", "/obj/machinery/vending/wallmed"), must=False)


ASSETS = dict(V2)
ASSETS.update({"recovery": recovery, "chemistry": chemistry, "genetics": genetics, "lobby": lobby,
               "reception": reception, "medstore": medstore, "scrub": scrub,
               "roomA": patient, "roomB": patient, "exam": exam})


# ================================================================================================= review 2 (11-21)
def cmo2(R):
    V2["cmo"](R)
    door = R.doors()[0]
    R.place(one("visitor chair", "c", (CHAIR, {"dir": "IN"}), back="any", use=()), near=door, must=False)
    R.place(one("couch", "SO", ("/obj/structure/chair/sofa", {"dir": "IN"}), back="wall", use=()), far=door,
            must=False)
    R.place(one("coffee table", "t", "/obj/structure/table/wood", "/obj/item/reagent_containers/food/drinks/mug",
                back="any"), far=door, must=False)


ASSETS.update({"cmo": cmo2})


# ================================================================================================= review 3 (11-21)
def scrub3(R):
    # the surgeons' wash-up: two sinks with mirrors on the north wall off the street door, the gowns locker and the
    # masks table at the store end, the roller by the theatre door; the door tiles stay clear (review 3 #2)
    for x in (80, 81):
        R.put((x, 65), None, obj=[("/obj/structure/sink", {"pixel_y": 30}), ("/obj/structure/mirror", {"pixel_y": 28})])
        R.faces[((x, 65), 1)] = "sink"
    R.put((84, 65), "obj", obj=["/obj/structure/closet/secure_closet/medical2"])
    R.put((83, 65), "obj", obj=[TABLE, "/obj/item/clothing/mask/surgical", "/obj/item/clothing/mask/surgical",
                                "/obj/item/storage/box/gloves"])
    R.put((79, 64), "obj", obj=["/obj/structure/bed/roller"])
    R.reserve([(78, 64), (78, 65), (80, 64), (85, 64)], "open")
    R.place(hang("wall NanoMed", "wallmed", "/obj/machinery/vending/wallmed"), must=False)


def recovery3(R):
    recovery(R)
    # the sleepers face out from their wall: dir 4 on the west wall, 8 on the east (review 3 #1)
    xs = [p[0] for p in R.tiles]
    for p in R.tiles:
        for c in R.geo.cells.get(p, []):
            c["obj"] = [(o[0], dict(o[1], dir=4 if p[0] <= min(xs) + 1 else 8))
                        if isinstance(o, tuple) and o[0] == "/obj/machinery/sleeper" else o for o in c.get("obj", [])]


ASSETS.update({"scrub": scrub3, "recovery": recovery3})


# ================================================================================================= review 3 (11-21)
def patient3(R):
    # the bed in the corner farthest from the door, its drip right beside it, a visitor's chair turned to the bed
    # (review 3 #4: room A's chair faced away, room B had none)
    door = R.doors()[0]
    free = [p for p in R.tiles if R.geo.taken.get(p) is None and p not in R.front]
    if not free:
        return
    bed = max(free, key=lambda p: (dist(p, door), p))
    R.put(bed, "obj", obj=["/obj/structure/bed", "/obj/item/bedsheet/medical"])
    nbrs = [(bed[0] + dx, bed[1] + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))]
    side = [q for q in nbrs if q in free and q != bed]
    if side:
        iv = max(side, key=lambda q: (dist(q, door), q))
        R.put(iv, "obj", obj=["/obj/machinery/iv_drip"])
        side = [q for q in side if q != iv]
    if side:
        ch = min(side, key=lambda q: (dist(q, door), q))
        d = {(1, 0): 8, (-1, 0): 4, (0, 1): 2, (0, -1): 1}[(ch[0] - bed[0], ch[1] - bed[1])]
        R.put(ch, "open", obj=[(CHAIR, {"dir": d})])


def theatre3(R):
    V2["theatre"](R)
    # the anaesthetic and a drip by the table (review 3 #8)
    R.place(one("anaesthetic", "t", TABLE, "/obj/item/tank/internals/anesthetic", "/obj/item/clothing/mask/breath/medical",
                back="wall"), must=False)
    R.place(one("drip", "iv", "/obj/machinery/iv_drip", back="any", use=()), must=False)


ASSETS.update({"roomA": patient3, "roomB": patient3, "theatre": theatre3})
