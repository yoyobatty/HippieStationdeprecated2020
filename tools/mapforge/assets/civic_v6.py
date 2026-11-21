"""Room assets for the v6 station's Civic block: chapel, library, gallery, game room, meeting room, lawyer.

  chapel      the altar at the far (north) end with candles and the bible, pews in pairs either side of the aisle
              facing it, the organ; the chaplain's place by the altar
  office      the chaplain's desk facing the door, the chaplain's closet, a bookcase
  crematorium the crematorium against the wall with its button, a morgue tray beside it, a coffin crate
  confession  two chairs either side of the grille window into the chapel
  library     bookcases in rows, reading tables with chairs, the library computer, scanner and binder by the desk
  back room   the librarian's store: a bookcase, cardboard, the camera and the typewriter table
  gallery     easels and statues round the walls, benches in the middle
  game room   card tables, the arcade machines, a vendor
  meeting     one long table with chairs round it
  lawyer      desk facing the door, the law closet, filing cabinets, a client chair
Essential pieces (the altar, the library computer, the crematorium, the lawyer's desk) are placed with must=True so a
missing one shows as a problem instead of vanishing.
"""
from forge.proc.place import Kit, cell, dist
from assets.science import TABLE, CHAIR, PAPER, PLANT_K, BIN, one, hang, seat_at, apart
from assets.security import button

WOOD = "/obj/structure/table/wood"
CANDLE = "/obj/item/candle"


def free_spots(R, near, n):
    free = [p for p in R.tiles if R.free(p) and p not in R.front and p not in R.lane]
    return sorted(free, key=lambda p: (dist(p, near), p))[:n]


ALTAR = Kit("altar", [
    cell(0, 0, WOOD, "/obj/item/storage/book/bible", CANDLE, label="t"),
    cell(1, 0, WOOD, "/obj/item/reagent_containers/food/drinks/bottle/holywater", label="t"),
    cell(2, 0, WOOD, CANDLE, "/obj/item/storage/fancy/candle_box", label="t"),
], use=[(1, 1)], back="wall")


def pew_row(n, d):
    return Kit("pews", [(i, 0, dict(obj=[("/obj/structure/chair/pew", {"dir": d})], open=True, seat=True, label="P"))
                        for i in range(n)], use=[], back=None, mirror=False)


def chapel(R):
    # the altar on the wall opposite the door, pews facing it in two banks with the aisle down the middle
    door = (R.doors("foyer") or R.doors())[0]
    altar = R.place(ALTAR, far=door)
    front = altar.uses[0] if altar else R.room.attrs["heart"]
    toward = (front[0] - door[0], front[1] - door[1])
    d = (1 if toward[1] > 0 else 2) if abs(toward[1]) >= abs(toward[0]) else (4 if toward[0] > 0 else 8)
    aisle = {p for p in R.tiles if (abs(p[0] - door[0]) <= 0 if d in (1, 2) else abs(p[1] - door[1]) <= 0)}
    R.reserve(sorted(aisle), "open")
    for _ in range(6):
        R.place(pew_row(3, d), near=front, must=False,
                need=lambda pl: all(t not in R.geo.taken for t in pl.tiles) and apart(R, pl, 0)
                and not any(R.geo.taken.get(q) == "open" and q not in aisle and q not in pl.tiles
                            for t in pl.tiles for q in [(t[0], t[1] + 1), (t[0], t[1] - 1)]))
    R.place(one("organ", "OR", "/obj/structure/piano"), near=front, must=False)
    R.place(PLANT_K, near=front, must=False)
    R.place(PLANT_K, near=front, must=False)
    spot = free_spots(R, front, 1)
    if spot:
        R.mark(spot[0], "/obj/effect/landmark/start/chaplain")


def office(R):
    door = R.doors()[0]
    R.place(Kit("chaplain desk", [cell(0, 0, WOOD, PAPER, "/obj/item/pen", "/obj/item/flashlight/lamp", label="t"),
                                  seat_at(0, 1, "/obj/structure/chair/wood")], use=[(0, 1)]), far=door)
    R.place(one("chaplain closet", "L", "/obj/structure/closet/wardrobe/chaplain_black"), must=False)
    R.place(one("bookcase", "BC", "/obj/structure/bookcase/random/religion"), must=False)


def crematorium(R):
    door = R.doors()[0]
    cr = R.place(one("crematorium", "CR", ("/obj/structure/bodycontainer/crematorium", {"id": "crematorium",
                                                                                         "dir": 4}), back="wall"),
                 far=door)
    R.place(hang("ignition", "button", "/obj/machinery/button/crematorium",
                 {"id": "crematorium", "req_access_txt": "27", "name": "Crematorium Ignition"}), must=False)
    R.place(one("tray", "MG", ("/obj/structure/bodycontainer/morgue", {"dir": 4}), back="any"), must=False)


def confession(R):
    R.place(one("confessor", "c", (CHAIR, {"dir": "IN"}), back="wall", use=()), must=False)
    R.place(one("candles", "t", WOOD, CANDLE, back="any"), must=False)


def bookcases(n):
    return [one("bookcase", "BC", path) for path in (
        "/obj/structure/bookcase/random/fiction", "/obj/structure/bookcase/random/nonfiction",
        "/obj/structure/bookcase/random/reference", "/obj/structure/bookcase/random/religion",
        "/obj/structure/bookcase/random/fiction", "/obj/structure/bookcase/random/nonfiction")[:n]]


LIB_DESK = Kit("library desk", [
    cell(0, 0, ("/obj/machinery/computer/libraryconsole", {"dir": "IN"}), label="LC"),
    cell(1, 0, WOOD, PAPER, "/obj/item/pen", label="t"),
    seat_at(0, 1, "/obj/structure/chair/office", "/obj/effect/landmark/start/librarian"),
], use=[(0, 1), (1, 1)])


def reading(name):
    return Kit(name, [cell(0, 0, WOOD, "/obj/item/flashlight/lamp/green", label="t"),
                      (0, 1, dict(obj=[(CHAIR, {"dir": "OUT"})], open=True, seat=True, label="c")),
                      (0, -1, dict(obj=[(CHAIR, {"dir": "IN"})], open=True, seat=True, label="c"))],
               use=[], back=None, mirror=False)


def library(R):
    door = (R.doors("hall") or R.doors())[0]
    R.place(LIB_DESK, near=door)
    R.run([one("scanner", "SC", "/obj/machinery/libraryscanner"), one("binder", "BB", "/obj/machinery/bookbinder")],
          near=door)
    R.run(bookcases(6), far=door)
    R.run(bookcases(4))
    dwall = R.geo.field("dwall")
    for _ in range(3):
        R.place(reading("reading table"), near=R.room.attrs["heart"], must=False,
                need=lambda pl: apart(R, pl, 1) and dwall.get(pl.origin, 0) >= 2)
    R.place(PLANT_K, near=door, must=False)
    R.place(hang("quiet", "sign", "/obj/structure/sign/poster/official/random"), must=False)


def backroom(R):
    R.run(bookcases(2))
    R.place(one("typewriter", "t", WOOD, PAPER, "/obj/item/camera", back="any"), must=False)
    R.place(one("cardboard", "CB", "/obj/structure/closet/cardboard"), must=False)


def gallery(R):
    door = R.doors()[0]
    R.run([one("easel", "EA", "/obj/structure/easel", "/obj/item/canvas/twentythreeXtwentythree", back="any"),
           one("statue", "ST", "/obj/structure/statue/sandstone/venus", back="any")], far=door)
    R.place(one("statue", "ST", "/obj/structure/statue/silver/md", back="any"), must=False)
    dwall = R.geo.field("dwall")
    R.place(Kit("bench", [(i, 0, dict(obj=[(CHAIR, {"dir": 1})], open=True, seat=True, label="c")) for i in range(2)],
                use=[], back=None, mirror=False), near=R.room.attrs["heart"], must=False,
            need=lambda pl: dwall.get(pl.origin, 0) >= 2)
    for _ in range(3):
        R.place(hang("painting", "sign", "/obj/structure/sign/poster/official/random"), must=False)


def gameroom(R):
    door = R.doors()[0]
    R.run([one("arcade", "AR", ("/obj/machinery/computer/arcade/battle", {"dir": "IN"})),
           one("arcade", "AR", ("/obj/machinery/computer/arcade/orion_trail", {"dir": "IN"}))], far=door)
    dwall = R.geo.field("dwall")
    for _ in range(2):
        R.place(Kit("card table", [cell(0, 0, WOOD, "/obj/item/toy/cards/deck", label="t"),
                                   (-1, 0, dict(obj=[(CHAIR, {"dir": "A+"})], open=True, seat=True, label="c")),
                                   (1, 0, dict(obj=[(CHAIR, {"dir": "A-"})], open=True, seat=True, label="c"))],
                    use=[], back=None, mirror=False), near=R.room.attrs["heart"], must=False,
                need=lambda pl: apart(R, pl, 1) and dwall.get(pl.origin, 0) >= 1)
    R.place(one("cola", "V", "/obj/machinery/vending/cola/random"), near=door, must=False)


def meeting_old(R):
    dwall = R.geo.field("dwall")
    R.place(Kit("meeting table", [cell(u, 0, WOOD, *( [PAPER] if u == 1 else []), label="t") for u in range(3)] +
                [(u, v, dict(obj=[(CHAIR, {"dir": "OUT" if v > 0 else "IN"})], open=True, seat=True, label="c"))
                 for u in range(3) for v in (1, -1)], use=[], back=None, mirror=False),
            near=R.room.attrs["heart"], must=False, need=lambda pl: all(dwall.get(pl.at(u, 0), 0) >= 1 for u in range(3)))
    R.place(PLANT_K, must=False)
    R.place(hang("map", "sign", "/obj/structure/sign/map/left"), must=False)


LAW_DESK = Kit("lawyer desk", [
    cell(0, 0, WOOD, PAPER, "/obj/item/pen", "/obj/item/folder/blue", label="t"),
    cell(1, 0, WOOD, "/obj/item/book/manual/wiki/security_space_law", "/obj/item/flashlight/lamp", label="t"),
    seat_at(0, 1, "/obj/structure/chair/office", "/obj/effect/landmark/start/lawyer"),
], use=[(0, -1), (1, -1)], back=None)


def lawyer(R):
    door = (R.doors("hall") or R.doors())[0]
    R.place(LAW_DESK, need=lambda pl: dist(pl.at(0, 1), door) > dist(pl.at(0, -1), door))
    R.place(one("law closet", "L", "/obj/structure/closet/lawcloset"), far=door, must=False)
    R.run([one("files", "F", "/obj/structure/filingcabinet"), one("files", "F", "/obj/structure/filingcabinet")],
          far=door)
    R.place(one("client chair", "c", (CHAIR, {"dir": "IN"}), back="any", use=()), near=door, must=False)
    R.place(PLANT_K, must=False)


def foyer(R):
    R.place(hang("directions", "sign", "/obj/structure/sign/directions/evac"), must=False)


ASSETS = {"chapel": chapel, "chapeloffice": office, "crematorium": crematorium, "confession": confession,
          "library": library, "libback": backroom, "gallery": gallery, "gameroom": gameroom, "meeting": meeting_old,
          "lawyer": lawyer, "foyer": foyer}


# ================================================================================================= review 1 (11-21)
# Civic is drawn by hand, so its showpieces are laid at fixed tiles of the drawing (map coordinates).
PEW, PEWL, PEWR = "/obj/structure/chair/pew", "/obj/structure/chair/pew/left", "/obj/structure/chair/pew/right"


def chapel2(R):
    # Meta's chapel: the altar under the north windows, a carpet aisle from the doors to it, two banks of pews
    # facing it, coffins by the mass driver that sends the dead out to space
    for x in range(110, 113):
        R.put((x, 145), "obj", obj=[WOOD] + ([CANDLE] if x != 111 else ["/obj/item/storage/book/bible", CANDLE]))
        for y in range(134, 145):
            R.put((x, y), "open", floor="/turf/open/floor/carpet")
    for y in (136, 138, 140, 142):
        for x0 in (107, 113):
            for i, path in enumerate((PEWL, PEW, PEWR)):
                R.put((x0 + i, y), "open", obj=[(path, {"dir": 1})])
    for x in (107, 108):        # on the solid south wall beside the doors (the tower's sides are glass)
        R.put((x, 134), "obj", obj=["/obj/structure/closet/crate/coffin"])
    R.mark((111, 144), "/obj/effect/landmark/start/chaplain")
    R.place(one("organ", "OR", "/obj/structure/piano"), must=False)
    R.place(PLANT_K, must=False)
    for p in R.tiles:
        if not R.geo.cells.get(p) or not any(c.get("floor") for c in R.geo.cells[p]):
            # the chapel sprite is one quarter of the pattern: each 2x2 block turns its tiles NW 1, NE 4, SW 8,
            # SE 2 so the blocks read whole (Meta's; the user caught them all facing one way, 2026-11-21)
            d = {(0, 1): 1, (1, 1): 4, (0, 0): 8, (1, 0): 2}[(p[0] % 2, p[1] % 2)]
            R.put(p, None, floor=("/turf/open/floor/plasteel/chapel", {"dir": d}))


def booth(R):
    # one booth each side of the tinted grille: a chair facing it
    grille = R.side("confess1" if R.rid == "confess2" else "confess2")
    d = grille if grille else 2
    seat = min(R.tiles, key=lambda p: (abs(p[0] - 103), p))
    R.put(seat, "open", obj=[(CHAIR, {"dir": d})])
    R.place(one("candles", "t", WOOD, CANDLE, back="any"), must=False)


def chapeloffice2(R):
    R.put((119, 134), "obj", obj=[WOOD, PAPER, "/obj/item/pen", "/obj/item/flashlight/lamp"])
    R.put((120, 134), "open", obj=[("/obj/structure/chair/wood", {"dir": 8})])
    R.reserve([(120, 135)], "open")
    R.place(one("chaplain closet", "L", "/obj/structure/closet/wardrobe/chaplain_black"), must=False)
    R.place(one("bookcase", "BC", "/obj/structure/bookcase/random/religion"), must=False)
    R.place(button("Chapel Launcher Door", {"id": "chapelgun", "req_access_txt": "22"}), must=False)
    R.place(hang("mass driver", "button", "/obj/machinery/button/massdriver",
                 {"id": "chapelgun", "name": "Chapel Mass Driver"}), must=False)


def library2(R):
    # the desk, scanner and binder together by the console; reading tables on a rug in the west half; a free
    # bookcase row in the north arm; shelves round the walls
    for (x, y), what in (((103, 127), [("/obj/machinery/computer/libraryconsole", {"dir": 2})]),
                         ((101, 127), ["/obj/machinery/libraryscanner"]),
                         ((104, 127), ["/obj/machinery/bookbinder"]),
                         ((102, 127), [WOOD, PAPER, "/obj/item/pen"])):
        R.put((x, y), "obj", obj=what)
    R.put((103, 126), "open", obj=[("/obj/structure/chair/office", {"dir": 1}),
                                    "/obj/effect/landmark/start/librarian"])
    R.reserve([(100, 127), (101, 126), (102, 126), (104, 126)], "open")
    for x in range(105, 109):
        R.put((x, 130), "obj", obj=["/obj/structure/bookcase/random/fiction"])
    for x in range(98, 103):
        for y in range(121, 126):
            if (x, y) in R.tiles:
                R.put((x, y), None, floor="/turf/open/floor/carpet")
    for (x, y) in ((99, 124), (99, 122), (102, 124)):
        R.put((x, y), "obj", obj=[WOOD, "/obj/item/flashlight/lamp/green"])
        R.put((x - 1, y), "open", obj=[(CHAIR, {"dir": 4})])
        R.put((x + 1, y), "open", obj=[(CHAIR, {"dir": 8})])
    R.run(bookcases(6))
    R.run(bookcases(4))
    R.place(PLANT_K, must=False)


def backroom2(R):
    R.place(Kit("librarian desk", [cell(0, 0, WOOD, PAPER, "/obj/item/pen", "/obj/item/camera", label="t"),
                                   seat_at(0, 1, "/obj/structure/chair/wood")], use=[(0, 1)]))
    R.run(bookcases(2))
    R.place(one("locker", "L", "/obj/structure/closet"), must=False)
    R.place(one("cardboard", "CB", "/obj/structure/closet/cardboard"), must=False)


def lawyer2(R):
    door = (R.doors("hall") or R.doors())[0]
    dwall = R.geo.field("dwall")
    desk = R.place(LAW_DESK, need=lambda pl: dist(pl.at(0, 1), door) > dist(pl.at(0, -1), door)
                   and dwall.get(pl.at(0, 0), 0) >= 1 and dwall.get(pl.at(1, 0), 0) >= 1, must=False)
    desk = desk or R.place(LAW_DESK, need=lambda pl: dist(pl.at(0, 1), door) > dist(pl.at(0, -1), door))
    # a client chair on each tile in front of the desk, facing it
    toward = {(0, 1): 1, (0, -1): 2, (1, 0): 4, (-1, 0): 8}
    for u in (0, 1):
        if not desk:
            break
        seat, table = desk.at(u, -1), desk.at(u, 0)
        if seat in R.tiles and R.geo.taken.get(seat) != "obj":
            R.put(seat, "open", obj=[(CHAIR, {"dir": toward[(table[0] - seat[0], table[1] - seat[1])]})])
    R.place(one("law closet", "L", "/obj/structure/closet/lawcloset"), far=door, must=False)
    R.run([one("files", "F", "/obj/structure/filingcabinet"), one("files", "F", "/obj/structure/filingcabinet")],
          far=door)
    R.place(PLANT_K, must=False)


def gallery2(R):
    door = R.doors()[0]
    R.reserve([p for p in R.tiles if p[1] == 129], "open")
    for x in (115, 117, 119):
        if (x, 132) in R.tiles:
            R.put((x, 132), "obj", obj=["/obj/structure/statue/sandstone/venus" if x != 117 else
                                        "/obj/structure/statue/silver/md"])
    for x in (115, 117, 119):
        if (x, 127) in R.tiles:
            R.put((x, 127), "obj", obj=["/obj/structure/displaycase"])
    for x in (116, 117, 118):
        if (x, 130) in R.tiles and R.geo.taken.get((x, 130)) != "obj":
            R.put((x, 130), "open", obj=[(CHAIR, {"dir": 1})])
    R.place(one("easel", "EA", "/obj/structure/easel", "/obj/item/canvas/twentythreeXtwentythree", back="any"),
            near=door, must=False)
    R.place(one("art table", "t", WOOD, "/obj/item/toy/crayon/spraycan", "/obj/item/stack/sheet/cloth/ten",
                back="wall"), near=door, must=False)


def foyer2(R):
    door = (R.doors("hall") or R.doors())[0]
    R.place(hang("map", "sign", "/obj/structure/sign/map/left"), near=door, must=False)
    R.place(PLANT_K, near=door, must=False)


ASSETS.update({"chapel": chapel2, "confess1": booth, "confess2": booth, "chapeloffice": chapeloffice2,
               "library": library2, "libback": backroom2, "lawyer": lawyer2, "gallery": gallery2, "foyer": foyer2})


def meeting(R):
    for x in (116, 117, 118):
        R.put((x, 123), "obj", obj=[WOOD] + ([PAPER] if x == 117 else []))
        R.put((x, 124), "open", obj=[(CHAIR, {"dir": 2})])
        R.put((x, 122), "open", obj=[(CHAIR, {"dir": 1})])
    R.reserve([(114, 123)], "open")
    R.place(PLANT_K, must=False)


def library3(R):
    library2(R)
    # a second free-standing shelf row and the north wall refilled (review 2 #8)
    for x in (105, 106, 107):
        if (x, 125) in R.tiles and R.geo.taken.get((x, 125)) != "obj":
            R.put((x, 125), "obj", obj=["/obj/structure/bookcase/random/nonfiction"])
    for x in (106, 107, 108, 109):
        if (x, 132) in R.tiles and R.geo.taken.get((x, 132)) != "obj":
            R.put((x, 132), "obj", obj=["/obj/structure/bookcase/random/reference"])


ASSETS.update({"meeting": meeting, "library": library3})


# ================================================================================================= review 3 (11-21)
def launch(R):
    # the driver against the launch door, nothing else in the niche
    # a straight tube in line with the shot: push the coffin in from 113,145 through the windoor onto the driver
    # (Civic review 4: the L-shaped niche could not be loaded)
    R.put((115, 145), "obj", obj=[("/obj/machinery/mass_driver", {"dir": 4, "id": "chapelgun"})])
    R.put((115, 145), None, decal=[("/obj/effect/turf_decal/stripes/line", {"dir": 4})])


def chapel3(R):
    # the driver moved into its niche; a coffin waits by the windoor (review 3 #1, #9)
    chapel2(R)
    if (114, 143) in R.tiles and R.geo.taken.get((114, 143)) != "obj":
        R.put((114, 143), "obj", obj=["/obj/structure/closet/crate/coffin"])
    R.reserve([(113, 145)], "open")


def booth3(R):
    booth(R)
    if R.rid == "confess1":
        R.put((103, 135), None, floor="/turf/open/floor/plating",
              obj=["/obj/effect/spawner/structure/window/reinforced/tinted"])


def backroom3(R):
    # the curator's back room: the desk out in the room facing the door, the curator's wardrobe, shelves on the east
    # wall, the cardboard box in a corner (review 3 #5)
    door = R.doors()[0]
    R.place(Kit("librarian desk", [cell(0, 0, WOOD, PAPER, "/obj/item/pen", "/obj/item/camera", label="t"),
                                   seat_at(0, 1, "/obj/structure/chair/wood")], use=[(0, -1)], back=None),
            near=R.room.attrs["heart"], need=lambda pl: dist(pl.at(0, 1), door) > dist(pl.at(0, -1), door))
    R.place(one("curator wardrobe", "L", "/obj/structure/closet/wardrobe/curator"), far=door, must=False)
    R.run(bookcases(2), far=door)
    R.place(one("cardboard", "CB", "/obj/structure/closet/cardboard"), must=False)


ASSETS.update({"launch": launch, "chapel": chapel3, "confess1": booth3, "confess2": booth3, "libback": backroom3})
