"""Hippie Station Medbay, rebuilt inside the 2020 footprint with the auto-furnisher.

Hand-drawn: walls, doors, lobby, reception, corridors, the surgical wing hall and the two patient rooms.
Furnished from the corpus: Recovery, the operating theatre, Medbay Storage, the CMO's office and the Morgue.
Kept as they are: the cryo room (its tubes need their coolant loop), chemistry's door, morgue and CMO doors.
"""
NAME = "hippie_medbay"
STYLE = "meta"
DRESS_HALL_FRONT = True
ORIGIN = (130, 102)
X0, Y0, W, H = 130, 102, 33, 27

_lay = {y: ["~"] * W for y in range(Y0, Y0 + H)}
_room = {y: ["~"] * W for y in range(Y0, Y0 + H)}


def put(y, x, s, room=None):
    for i, ch in enumerate(s):
        _lay[y][x - X0 + i] = ch
        if room and ch not in "#=~":
            _room[y][x - X0 + i] = room


# lobby
put(126, 138, "p.....p", "L")
put(125, 138, "e.....w", "L")
put(124, 138, "e..t..w", "L")
put(123, 141, "h", "L")
put(123, 138, "e.....w", "L")
put(122, 138, "v....%%", "L")  # glass over the reception, so the lobby can't walk behind the desk
put(121, 139, "DD=", "L")
put(121, 142, "Rcm", "m")
# corridor
put(120, 138, "...##Q", "m")
put(120, 146, "B.p..", "m")  # security post door at 147,121 and morgue door at 150,121 open onto this row
put(119, 138, "p...V........", "m")  # NanoMed against the reception wall
put(118, 136, ".......h.......", "m")
put(117, 136, "........NNN....", "m")  # waiting seats against the cryo glass
put(116, 138, "=A==", "m")
put(116, 149, "..", "m")
for y in range(112, 116):
    put(y, 149, "..", "m")
put(115, 150, "p", "m")
# recovery (furnished)
for y in range(112, 116):
    put(y, 138, "....", "r")
put(111, 138, "=G=########", "h")
put(111, 149, "......B", "m")
put(111, 157, "...B", "c")
# shared scrub room between the two theatres: sinks with mirrors, anaesthetic lockers, roller beds
put(110, 138, "s.s", "h")
put(109, 138, "...", "h")
put(108, 138, ".h.", "h")
put(107, 138, "b.K", "h")
put(106, 138, "K.b", "h")
# operating theatre 1 (furnished)
for y in range(106, 111):
    put(y, 132, ".....", "S")
put(109, 137, "=", None)
put(108, 137, "O", "S")
put(107, 137, "=", None)
put(106, 137, "#", None)
# medbay storage: doors from the scrub room (surgeons) and the east hall; supplies along the south wall
put(110, 141, "#.....B=", "s")
put(109, 141, "#......D", "s")
put(108, 141, "X......#", "s")
put(107, 141, "#......#", "s")
put(106, 141, "#MnFf..#", "s")
# east hall, with medical storage along its south wall
put(110, 149, "......p", "m")
put(109, 149, ".......", "m")
put(108, 148, "#####...", "m")
for y in range(103, 108):
    put(y, 153, "...", "m")
put(103, 155, "p", "m")
# patient rooms
put(107, 149, "1.t", "a")
put(106, 149, "i..P", "a")
put(105, 149, "####")
put(104, 149, "1..Y", "b")
put(103, 149, "i.t", "b")
# CMO (furnished)
for y in range(106, 111):
    put(y, 157, "....", "c")
put(105, 157, "~~~~")
# morgue (furnished)
for y in range(122, 127):
    put(y, 150, ".......", "g")

LAYOUT = "\n".join("".join(_lay[y]) for y in range(Y0 + H - 1, Y0 - 1, -1))
ROOMS = "\n".join("".join(_room[y]) for y in range(Y0 + H - 1, Y0 - 1, -1))

TABLE = "/obj/structure/table"


def L(*objs, **kw):
    d = dict(kw)
    d["obj"] = list(objs)
    return d


LEGEND = {
    "B": {"no_vent": True},
    "p": L("/obj/item/twohanded/required/kirbyplants/random"),
    "t": L(TABLE, "/obj/item/storage/firstaid/regular"),
    "e": L("/obj/structure/chair", face="east"),
    "w": L("/obj/structure/chair", face="west"),
    "v": L("/obj/machinery/vending/snack/random"),
    "D": L(("/obj/machinery/door/airlock/medical/glass", {"name": "Medbay", "req_access_txt": "5"})),
    "R": L("/obj/structure/table/reinforced",
           ("/obj/machinery/door/window/northleft", {"name": "Medbay Reception", "req_access_txt": "5"}),
           "/obj/item/paper_bin", "/obj/item/pen"),
    "c": L("/obj/structure/chair/office/light", face="table"),
    "m": L("/obj/machinery/computer/crew", face="west"),
    "Q": L(("/obj/machinery/door/airlock/medical", {"name": "Medbay Reception", "req_access_txt": "5"})),
    "A": L(("/obj/machinery/door/airlock/medical/glass", {"name": "Recovery Room", "req_access_txt": "5"})),
    "G": L(("/obj/machinery/door/airlock/medical/glass", {"name": "Surgical Wing", "req_access_txt": "5"})),
    "O": L(("/obj/machinery/door/airlock/medical", {"name": "Operating Theatre", "req_access_txt": "45"})),
    "P": L(("/obj/machinery/door/airlock/medical", {"name": "Patient Room", "req_access_txt": "5"})),
    "Y": L(("/obj/machinery/door/airlock/medical", {"name": "Patient Room 2", "req_access_txt": "5"})),
    "s": dict(mount=[("sink", "/obj/structure/sink", {})]),
    "i": L("/obj/machinery/iv_drip"),
    "b": L("/obj/structure/bed/roller"),
    "1": L("/obj/structure/bed", "/obj/item/bedsheet/medical"),
    "h": L("/obj/machinery/holopad"),
    "k": L("/obj/machinery/vending/coffee"),
    "C": L("/obj/structure/chair", face="table"),
    "u": L("/obj/structure/table"),
    "N": L("/obj/structure/chair", face="north"),
    "V": L("/obj/machinery/vending/medical"),
    "F": L("/obj/machinery/rnd/production/techfab/department/medical"),
    "K": L("/obj/structure/closet/secure_closet/medical2"),
    "X": L(("/obj/machinery/door/airlock/medical", {"name": "Operating Theatre 2", "req_access_txt": "45"})),
    "M": L("/obj/structure/closet/secure_closet/medical1"),
    "n": L("/obj/structure/closet/crate/freezer/blood"),
    "f": L(TABLE, ("/obj/item/storage/firstaid/brute", {"pixel_x": 3, "pixel_y": 3}), "/obj/item/storage/firstaid/fire",
           ("/obj/item/storage/firstaid/toxin", {"pixel_x": -3, "pixel_y": -3}), "/obj/item/storage/firstaid/o2",
           "/obj/item/storage/box/beakers", "/obj/item/storage/box/syringes", "/obj/item/hand_labeler"),
    "r": L(TABLE, ("/obj/item/storage/box/beakers", {"pixel_x": 3, "pixel_y": 3}), "/obj/item/storage/box/syringes",
           "/obj/item/storage/box/rxglasses", "/obj/item/hand_labeler"),
}
# the storage room's doors
STORAGE = {"D": L(("/obj/machinery/door/airlock/medical/glass", {"name": "Medbay Storage", "req_access_txt": "5"})),
           "X": L(("/obj/machinery/door/airlock/medical/glass", {"name": "Medbay Storage", "req_access_txt": "5"}))}

WHITE = "/turf/open/floor/plasteel/white"
ROOMDEFS = {
    "L": dict(area="/area/medical/medbay/lobby", floor=WHITE, name="Medbay Lobby", trim="blue", newscaster=True),
    "m": dict(area="/area/medical/medbay/central", floor=WHITE, name="Medbay", trim="blue"),
    "r": dict(area="/area/medical/patients_rooms", floor=WHITE, name="Recovery Room",
              furnish=dict(kind="/area/medical/sleeper", seed=1, require=[("/obj/machinery/sleeper", 2), "/obj/machinery/computer/med_data"])),
    "h": dict(area="/area/medical/medbay/aft", floor=WHITE, name="Surgical Scrub"),
    "S": dict(area="/area/medical/surgery", floor=WHITE, name="Operating Theatre",
              furnish=dict(kind="/area/medical/surgery", seed=1,
                           require=["/obj/structure/table/optable", "/obj/machinery/computer/operating", "/obj/item/scalpel"])),
    "s": dict(area="/area/medical/storage", floor=WHITE, name="Medbay Storage", legend=STORAGE,
              furnish=dict(kind="/area/medical/storage", seed=1)),
    "a": dict(area="/area/medical/patients_rooms/room_a", floor=WHITE, name="Patient Room A", camera=False),
    "b": dict(area="/area/medical/patients_rooms/room_b", floor=WHITE, name="Patient Room B", camera=False),
    "c": dict(area="/area/crew_quarters/heads/cmo", floor="/turf/open/floor/plasteel/cafeteria", name="Chief Medical Officer's Office",
              furnish=dict(kind="/area/crew_quarters/heads/cmo", seed=1, require=["/obj/structure/closet/secure_closet/CMO"])),
    "g": dict(area="/area/medical/morgue", floor="/turf/open/floor/plasteel/dark", name="Morgue",
              furnish=dict(kind="/area/medical/morgue", seed=1)),
}

FOOTPRINT = ["/area/medical/sleeper", "/area/medical/medbay/central", "/area/crew_quarters/heads/cmo", "/area/medical/morgue"]

EXTRA = [
    (140, 118, "/obj/effect/landmark/start/medical_doctor", {}),
    (144, 117, "/obj/effect/landmark/start/medical_doctor", {}),
    (148, 118, "/obj/effect/landmark/start/medical_doctor", {}),
    (158, 108, "/obj/effect/landmark/start/chief_medical_officer", {}),
    (159, 107, "/mob/living/simple_animal/pet/cat/Runtime", {}),
    (143, 122, "/obj/item/folder/white", {}),
    (138, 110, "/obj/structure/mirror", {"pixel_x": -28}),
    (140, 110, "/obj/structure/mirror", {"pixel_x": 28}),
]
MOUNTS = [
    (145, 119, "north", "wallmed", "/obj/machinery/vending/wallmed", {}),
    (145, 106, None, "wallmed", "/obj/machinery/vending/wallmed", {}),
    (133, 106, None, "wallmed", "/obj/machinery/defibrillator_mount/loaded", {}),
    (141, 119, "north", "noticeboard", "/obj/structure/noticeboard", {}),
    (146, 117, "south", "sign", "/obj/structure/sign/poster/official/cleanliness", {}),
    (135, 110, None, "sign", "/obj/structure/sign/warning/nosmoking", {}),
    (153, 111, "north", "requests_console", "/obj/machinery/requests_console", {"department": "Medbay", "departmentType": 1}),
    (158, 111, "north", "requests_console", "/obj/machinery/requests_console",
     {"department": "Chief Medical Officer's Desk", "departmentType": 5, "announcementConsole": 1}),
    (160, 109, "east", "button", "/obj/machinery/keycard_auth", {}),
    (160, 107, "east", "button", "/obj/machinery/button/door", {"name": "Privacy Shutters", "id": "CMOOffice", "req_access_txt": "40"}),
    (151, 107, "north", "button", "/obj/machinery/button/door", {"name": "Privacy Shutters", "id": "medpriv4"}),
    (151, 103, "south", "button", "/obj/machinery/button/door", {"name": "Privacy Shutters", "id": "medpriv1"}),
]
