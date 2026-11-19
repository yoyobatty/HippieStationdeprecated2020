"""Room assets for the v6 station's Medical: medbay_v2's rooms plus the ones the new block carries itself.

  ward        sleepers and the cryo loop share one open room (no kept cryo bay here: the loop is a kit)
  chemistry   two benches, the chem fridge, a desk onto the public hall where prescriptions are handed out
  genetics    the cloning line (scanner, console, pod) and the DNA bench, monkey cubes at hand
"""
from forge.proc.place import Kit, cell
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
    pair = R.place(SLEEPERS, far=door, side=R.side("hall") or None)
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
    R.place(IV, near=bed.origin if bed else door, must=False)
    R.place(one("visitor chair", "c", (CHAIR, {"dir": "IN"}), back="any", use=()), near=bed.origin if bed else door,
            must=False)


ASSETS = dict(V2)
ASSETS.update({"recovery": recovery, "chemistry": chemistry, "genetics": genetics, "lobby": lobby,
               "reception": reception, "medstore": medstore, "scrub": scrub,
               "roomA": patient, "roomB": patient})
