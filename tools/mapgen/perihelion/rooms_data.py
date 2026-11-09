"""Per-room data for the Perihelion builder: areas, floors, access, door styles, starts."""

PLASTEEL = "/turf/open/floor/plasteel"
WHITE = "/turf/open/floor/plasteel/white"
DARK = "/turf/open/floor/plasteel/dark"
WOOD = "/turf/open/floor/wood"
PLATING = "/turf/open/floor/plating"

MODULE_MAINT = {
    "Security": "/area/maintenance/port/fore",
    "Command": "/area/maintenance/fore",
    "Service": "/area/maintenance/starboard/fore",
    "Medical": "/area/maintenance/starboard/aft",
    "Engineering": "/area/maintenance/aft",
    "Cargo": "/area/maintenance/port/aft",
    "Science core": "/area/maintenance/department/science",
}
TUNNEL_AREA = "/area/maintenance/central"

HALL_AREA = {
    "sec-P": "/area/hallway/primary/port",
    "sup-P": "/area/hallway/primary/port",
    "sec-D": "/area/security/brig",
    "cmd-P": "/area/hallway/primary/fore",
    "cmd-P2": "/area/hallway/primary/fore",
    "cmd-Dn": "/area/hallway/secondary/command",
    "cmd-Dw": "/area/hallway/secondary/command",
    "cmd-De": "/area/hallway/secondary/command",
    "srv-P": "/area/hallway/primary/starboard",
    "srv-P2": "/area/hallway/primary/starboard",
    "srv-D": "/area/hallway/secondary/service",
    "med-P": "/area/hallway/primary/central",
    "med-P2": "/area/hallway/primary/central",
    "med-D": "/area/medical/medbay/central",
    "eng-P": "/area/hallway/primary/aft",
    "eng-D": "/area/engine/engineering",
    "sup-D": "/area/quartermaster/storage",
    "sci-D": "/area/science/research",
    "sci-D2": "/area/science/research",
    "sci-D3": "/area/science/research",
}
HALL_FLOOR = {"sec-D": DARK, "cmd-Dn": DARK, "cmd-Dw": DARK, "cmd-De": DARK,
              "med-D": WHITE, "sci-D": WHITE, "sci-D2": WHITE, "sci-D3": WHITE}

WALK_AREA = {
    "W1": "/area/hallway/primary/fore",
    "W2": "/area/hallway/primary/starboard",
    "W3": "/area/hallway/primary/central",
    "W4": "/area/hallway/primary/aft",
    "W5": "/area/hallway/primary/aft",
    "W6": "/area/hallway/primary/port",
    "S1": "/area/hallway/primary/fore",
    "S2": "/area/science/research",
    "T1": "/area/ai_monitored/turret_protected/aisat/hallway",
}
WALK_FLOOR = {"glass": PLASTEEL, "tunnel": DARK}

SOLAR_AREA = {
    "NW array": "/area/solar/port/fore",
    "NE array": "/area/solar/starboard/fore",
    "SW array": "/area/solar/port/aft",
    "SE array": "/area/solar/starboard/aft",
}
SOLAR_ID = {"NW array": "portsolar", "NE array": "starboardsolar",
            "SW array": "aftportsolar", "SE array": "aftstarboardsolar"}

# room -> (area, floor or None for the dept default, access, door name)
ROOMS = {
    # Security
    "Checkpoint":     ("/area/security/checkpoint/auxiliary", DARK, "63"),
    "Sec Lockers":    ("/area/security/main", DARK, "63"),
    "HoS Office":     ("/area/crew_quarters/heads/hos", DARK, "58"),
    "Sec Office":     ("/area/security/main", DARK, "63"),
    "Interrogation":  ("/area/security/processing", DARK, "63"),
    "Detective":      ("/area/security/detectives_office", WOOD, "4"),
    "Permabrig":      ("/area/security/prison", PLASTEEL, "2"),
    "Sec Lobby":      ("/area/security/checkpoint", DARK, None),
    "Warden":         ("/area/security/warden", DARK, "3"),
    "Armory":         ("/area/ai_monitored/security/armory", DARK, "3"),
    "Evidence":       ("/area/security/warden", DARK, "63"),
    "Cells":          ("/area/security/brig", DARK, "63"),
    "Courtroom":      ("/area/security/courtroom", WOOD, None),
    # Arrivals / departures
    "Arrivals":       ("/area/hallway/secondary/entry", PLASTEEL, None),
    "Arrivals Dock W": ("/area/hallway/secondary/entry", PLASTEEL, None),
    "Arrivals Dock E": ("/area/hallway/secondary/entry", PLASTEEL, None),
    "Departures":     ("/area/hallway/secondary/exit", PLASTEEL, None),
    # Command
    "Captain":        ("/area/crew_quarters/heads/captain", WOOD, "20"),
    "Cmd Checkpoint": ("/area/security/checkpoint/customs", DARK, "63"),
    "Bridge":         ("/area/bridge", DARK, "19"),
    "Cmd Storage":    ("/area/storage/tools", DARK, "19"),
    "Sat Access":     ("/area/bridge", DARK, "65"),
    "Cmd Lockers":    ("/area/bridge", DARK, "19"),
    "HoP Office":     ("/area/crew_quarters/heads/hop", WOOD, "57"),
    "HoP Queue":      ("/area/hallway/primary/fore", PLASTEEL, None),
    "Vault Foyer":    ("/area/ai_monitored/nuke_storage", DARK, "19"),
    "Vault":          ("/area/ai_monitored/nuke_storage", DARK, "53"),
    "Upload Foyer":   ("/area/ai_monitored/turret_protected/ai_upload_foyer", DARK, "16"),
    "AI Upload":      ("/area/ai_monitored/turret_protected/ai_upload", "/turf/open/floor/circuit", "16"),
    "Teleporter":     ("/area/teleporter", DARK, "17"),
    "Conference":     ("/area/bridge/meeting_room", WOOD, "19"),
    "EVA":            ("/area/ai_monitored/storage/eva", DARK, "18"),
    # AI satellite
    "Sat Checkpoint": ("/area/ai_monitored/turret_protected/aisat/hallway", DARK, "65"),
    "Turret Hall":    ("/area/ai_monitored/turret_protected/aisat_interior", DARK, "65"),
    "AI Core":        ("/area/ai_monitored/turret_protected/ai", "/turf/open/floor/circuit", "16"),
    "Sat Storage":    ("/area/ai_monitored/turret_protected/aisat/service", DARK, "65"),
    "Sat Power":      ("/area/ai_monitored/turret_protected/aisat/atmos", DARK, "65"),
    "Telecomms":      ("/area/tcommsat/server", "/turf/open/floor/circuit", "61"),
    # Service
    "Janitor":        ("/area/janitor", PLASTEEL, "26"),
    "Theatre":        ("/area/crew_quarters/theatre", WOOD, "46"),
    "Chapel":         ("/area/chapel/main", "/turf/open/floor/carpet", None),
    "Bar":            ("/area/crew_quarters/bar", WOOD, None),
    "Kitchen":        ("/area/crew_quarters/kitchen", "/turf/open/floor/plasteel/cafeteria", "28"),
    "Hydroponics":    ("/area/hydroponics", PLASTEEL, "35"),
    "Library":        ("/area/library", WOOD, None),
    "Dorms":          ("/area/crew_quarters/dorms", PLASTEEL, None),
    "Restrooms":      ("/area/crew_quarters/toilet", "/turf/open/floor/plasteel/freezer", None),
    # Medical
    "Med Lobby":      ("/area/medical/medbay/lobby", WHITE, None),
    "Ward":           ("/area/medical/medbay/central", WHITE, "5"),
    "Surgery":        ("/area/medical/surgery", WHITE, "45"),
    "Morgue":         ("/area/medical/morgue", DARK, "6"),
    "Chemistry":      ("/area/medical/chemistry", WHITE, "33"),
    "Cloning":        ("/area/medical/genetics", WHITE, "5;9;68"),
    "CMO":            ("/area/crew_quarters/heads/cmo", WHITE, "40"),
    "Cryo":           ("/area/medical/cryo", WHITE, "5"),
    "Med Storage":    ("/area/medical/storage", WHITE, "5"),
    "Viro Airlock":   ("/area/medical/virology", WHITE, "39"),
    "Virology":       ("/area/medical/virology", WHITE, "39"),
    # Engineering
    "Eng Lockers":    ("/area/engine/break_room", PLASTEEL, "10;24"),
    "Eng Lobby":      ("/area/security/checkpoint/engineering", PLASTEEL, None),
    "CE Office":      ("/area/crew_quarters/heads/chief", PLASTEEL, "56"),
    "Tech Storage":   ("/area/storage/tech", PLATING, "23"),
    "Atmospherics":   ("/area/engine/atmos", PLASTEEL, "24"),
    "Atmos Tanks":    ("/area/engine/atmos", PLASTEEL, "24"),
    "Atmos Storage":  ("/area/engine/atmos", PLASTEEL, "24"),
    "Gravity Gen":    ("/area/engine/gravity_generator", DARK, "10"),
    "Engine Airlock": ("/area/engine/engineering", PLASTEEL, "10"),
    "SMES":           ("/area/engine/engine_smes", PLASTEEL, "10"),
    "NW Solars":      ("/area/maintenance/solars/port/fore", PLATING, "10"),
    "NE Solars":      ("/area/maintenance/solars/starboard/fore", PLATING, "10"),
    "SW Solars":      ("/area/maintenance/solars/port/aft", PLATING, "10"),
    "SE Solars":      ("/area/maintenance/solars/starboard/aft", PLATING, "10"),
    # Cargo
    "QM Office":      ("/area/quartermaster/qm", PLASTEEL, "41"),
    "Cargo Bay":      ("/area/quartermaster/storage", PLASTEEL, "31"),
    "Mining Dock":    ("/area/quartermaster/miningdock", PLASTEEL, "48"),
    "Cargo Lobby":    ("/area/quartermaster/office", PLASTEEL, None),
    "Warehouse":      ("/area/quartermaster/warehouse", PLASTEEL, "31"),
    "Recycling":      ("/area/maintenance/disposal", PLATING, "31"),
    "Mining Lockers": ("/area/quartermaster/sorting", PLASTEEL, "48"),
    # Science
    "Sci Lobby":      ("/area/security/checkpoint/science/research", WHITE, None),
    "Sci Lockers":    ("/area/science/research", WHITE, "47"),
    "R&D":            ("/area/science/lab", WHITE, "47"),
    "RD Office":      ("/area/crew_quarters/heads/hor", WHITE, "30"),
    "Servers":        ("/area/science/server", DARK, "30"),
    "Mech Storage":   ("/area/science/robotics/mechbay", PLASTEEL, "29"),
    "Robotics":       ("/area/science/robotics/lab", WHITE, "29"),
    "Mech Bay":       ("/area/science/robotics/mechbay", PLASTEEL, "29"),
    "Toxins Lab":     ("/area/science/mixing", WHITE, "7"),
    "Burn Chamber":   ("/area/science/mixing/chamber", "/turf/open/floor/engine", "7"),
    "Toxins Storage": ("/area/science/storage", WHITE, "8"),
    "Nanites":        ("/area/science/nanite", WHITE, "47"),
    "Anomaly Lab":    ("/area/science/explab", WHITE, "47"),
    "Xeno Airlock":   ("/area/science/xenobiology", WHITE, "55"),
    "Xenobiology":    ("/area/science/xenobiology", WHITE, "55"),
    # Maintenance rooms
    "Abandoned Office": ("/area/vacant_room", WOOD, "12"),
    "Maint Bar":      ("/area/crew_quarters/bar/maint", WOOD, "12"),
    "Storage Closet": ("/area/storage/emergency/port", PLATING, "12"),
    "Abandoned Lab":  ("/area/maintenance/strangeroom", PLATING, "12"),
}
ROOM_AREA = {k: v[0] for k, v in ROOMS.items()}

DEPT_FLOOR = {"sec": DARK, "cmd": DARK, "med": WHITE, "sci": WHITE, "ai": DARK, "mnt": PLATING}


def room_floor(name, dept):
    if name in ROOMS and ROOMS[name][1]:
        return ROOMS[name][1]
    return DEPT_FLOOR.get(dept, PLASTEEL)


DEPT_DOOR = {
    "sec": "/obj/machinery/door/airlock/security",
    "cmd": "/obj/machinery/door/airlock/command",
    "ai": "/obj/machinery/door/airlock/command",
    "med": "/obj/machinery/door/airlock/medical",
    "sci": "/obj/machinery/door/airlock/research",
    "eng": "/obj/machinery/door/airlock/engineering",
    "sup": "/obj/machinery/door/airlock/mining",
    "srv": "/obj/machinery/door/airlock",
    "arr": "/obj/machinery/door/airlock/public/glass",
    "mnt": "/obj/machinery/door/airlock/maintenance",
}
SPECIAL_DOOR = {
    "Vault": "/obj/machinery/door/airlock/vault",
    "AI Upload": "/obj/machinery/door/airlock/highsecurity",
    "AI Core": "/obj/machinery/door/airlock/highsecurity",
    "Turret Hall": "/obj/machinery/door/airlock/highsecurity",
    "Armory": "/obj/machinery/door/airlock/highsecurity",
    "Atmospherics": "/obj/machinery/door/airlock/atmos/glass",
    "Atmos Tanks": "/obj/machinery/door/airlock/atmos",
    "Virology": "/obj/machinery/door/airlock/virology",
    "Viro Airlock": "/obj/machinery/door/airlock/virology/glass",
    "Restrooms": "/obj/machinery/door/airlock",
    "Kitchen": "/obj/machinery/door/airlock",
    "Hydroponics": "/obj/machinery/door/airlock/glass",
    "Cmd Checkpoint": "/obj/machinery/door/airlock/security/glass",
    "Checkpoint": "/obj/machinery/door/airlock/security/glass",
    "Sat Access": "/obj/machinery/door/airlock/highsecurity",
    "Telecomms": "/obj/machinery/door/airlock/hatch",
    "Sat Checkpoint": "/obj/machinery/door/airlock/highsecurity",
    "Xenobiology": "/obj/machinery/door/airlock/research",
    "Xeno Airlock": "/obj/machinery/door/airlock/research/glass",
    "Burn Chamber": "/obj/machinery/door/airlock/research/glass",
}
# department hall -> access for its gate / lobby door
GATE_ACCESS = {
    "sec-D": "63", "cmd-Dn": "19", "cmd-Dw": "19", "cmd-De": "19", "srv-D": "25;28;35",
    "med-D": "5", "eng-D": "10;24", "sup-D": "31;48", "sci-D": "47", "sci-D2": "47", "sci-D3": "47",
}
HALL_DEPT = {"sec-D": "sec", "cmd-Dn": "cmd", "cmd-Dw": "cmd", "cmd-De": "cmd", "srv-D": "srv",
             "med-D": "med", "eng-D": "eng", "sup-D": "sup", "sci-D": "sci", "sci-D2": "sci", "sci-D3": "sci"}


def door_access(inner, outer, kind):
    if inner in GATE_ACCESS:
        return GATE_ACCESS[inner]
    if outer in GATE_ACCESS and kind == "access":
        return GATE_ACCESS[outer]
    if inner in ROOMS:
        return ROOMS[inner][2]
    return None


def door_name(inner):
    if inner in ROOMS:
        return inner.replace("ENGINE (SM / singulo / tesla)", "Engine Room")
    return {"sec-D": "Brig", "cmd-Dn": "Bridge Hall", "cmd-Dw": "Secure Hall", "cmd-De": "Command Hall",
            "srv-D": "Service Hall", "med-D": "Medbay", "eng-D": "Engineering", "sup-D": "Cargo",
            "sci-D": "Research Division"}.get(inner, inner)


def door_path(inner, dept, kind, side_kind):
    if kind == "secure":
        return SPECIAL_DOOR.get(inner, "/obj/machinery/door/airlock/highsecurity")
    if inner in SPECIAL_DOOR:
        return SPECIAL_DOOR[inner]
    if side_kind == "hall":
        dept = HALL_DEPT.get(inner, dept)
        return DEPT_DOOR.get(dept, "/obj/machinery/door/airlock") + "/glass"
    if kind == "access":
        return DEPT_DOOR.get(dept, "/obj/machinery/door/airlock") + ("/glass" if dept not in ("srv", "arr", "mnt") else "")
    p = DEPT_DOOR.get(dept, "/obj/machinery/door/airlock")
    if dept == "srv" and inner in ("Bar", "Chapel", "Library", "Dorms"):
        p = "/obj/machinery/door/airlock/public/glass"
    return p


# job start landmarks: room -> [(job, count)]
STARTS = {
    "Sec Office": [("security_officer", 5)],
    "HoS Office": [("head_of_security", 1)],
    "Warden": [("warden", 1)],
    "Detective": [("detective", 1)],
    "Courtroom": [("lawyer", 1)],
    "Captain": [("captain", 1)],
    "HoP Office": [("head_of_personnel", 1)],
    "AI Core": [("ai", 1)],
    "Sat Storage": [("cyborg", 2)],
    "Robotics": [("roboticist", 2), ("cyborg", 1)],
    "Janitor": [("janitor", 1)],
    "Theatre": [("clown", 1), ("mime", 1), ("discjockey", 1)],
    "Chapel": [("chaplain", 1)],
    "Bar": [("bartender", 1)],
    "Kitchen": [("cook", 1)],
    "Hydroponics": [("botanist", 2)],
    "Library": [("librarian", 1)],
    "Dorms": [("assistant", 6)],
    "Arrivals": [("assistant", 4)],
    "Ward": [("medical_doctor", 3)],
    "Chemistry": [("chemist", 2)],
    "Cloning": [("geneticist", 1)],
    "CMO": [("chief_medical_officer", 1)],
    "Virology": [("virologist", 1)],
    "Eng Lockers": [("station_engineer", 5)],
    "CE Office": [("chief_engineer", 1)],
    "Atmospherics": [("atmospheric_technician", 2)],
    "QM Office": [("quartermaster", 1)],
    "Cargo Bay": [("cargo_technician", 3)],
    "Mining Dock": [("shaft_miner", 3)],
    "R&D": [("scientist", 3)],
    "Toxins Lab": [("scientist", 1)],
    "RD Office": [("research_director", 1)],
}
DEPSEC = {"Cargo Lobby": "supply", "Med Lobby": "medical", "Eng Lobby": "engineering", "Sci Lobby": "science"}

# where each room's furniture comes from on Hippie (areas, in order of preference)
HARVEST = {
    "Checkpoint": ["/area/security/checkpoint/auxiliary"],
    "Sec Lockers": [],
    "HoS Office": ["/area/crew_quarters/heads/hos"],
    "Sec Office": ["/area/security/main"],
    "Detective": ["/area/security/detectives_office"],
    "Permabrig": ["/area/security/prison"],
    "Warden": ["/area/security/warden"],
    "Armory": ["/area/ai_monitored/security/armory"],
    "Cells": ["/area/security/brig"],
    "Courtroom": ["/area/security/courtroom"],
    "Interrogation": ["/area/security/processing"],
    "Arrivals": [],
    "Departures": ["/area/hallway/secondary/exit"],
    "Captain": ["/area/crew_quarters/heads/captain"],
    "Cmd Checkpoint": ["/area/security/checkpoint/supply"],
    "Bridge": ["/area/bridge"],
    "Cmd Storage": ["/area/storage/tools"],
    "HoP Office": ["/area/crew_quarters/heads/hop"],
    "Vault": ["/area/ai_monitored/nuke_storage"],
    "AI Upload": ["/area/ai_monitored/turret_protected/ai_upload"],
    "Teleporter": ["/area/teleporter"],
    "Conference": ["/area/bridge/meeting_room"],
    "EVA": ["/area/ai_monitored/storage/eva"],
    "Sat Checkpoint": ["/area/ai_monitored/turret_protected/aisat/hallway"],
    "Turret Hall": ["/area/ai_monitored/turret_protected/aisat_interior"],
    "AI Core": ["/area/ai_monitored/turret_protected/ai"],
    "Sat Storage": ["/area/ai_monitored/turret_protected/aisat/service"],
    "Sat Power": ["/area/ai_monitored/turret_protected/aisat/atmos"],
    "Telecomms": ["/area/tcommsat/server", "/area/tcommsat/computer"],
    "Janitor": ["/area/janitor"],
    "Theatre": ["/area/crew_quarters/theatre", "/area/hippie/clown", "/area/hippie/mime"],
    "Chapel": ["/area/chapel/main", "/area/chapel/office"],
    "Bar": ["/area/crew_quarters/bar"],
    "Kitchen": ["/area/crew_quarters/kitchen"],
    "Hydroponics": ["/area/hydroponics"],
    "Library": ["/area/library"],
    "Dorms": ["/area/crew_quarters/dorms", "/area/crew_quarters/locker"],
    "Restrooms": ["/area/crew_quarters/toilet", "/area/crew_quarters/toilet/locker"],
    "Med Lobby": [],
    "Ward": ["/area/medical/medbay/central"],
    "Surgery": ["/area/medical/sleeper"],
    "Morgue": ["/area/medical/morgue"],
    "Chemistry": ["/area/medical/chemistry"],
    "Cloning": ["/area/medical/genetics"],
    "CMO": ["/area/crew_quarters/heads/cmo"],
    "Med Storage": ["/area/storage/emergency/starboard"],
    "Virology": ["/area/medical/virology"],
    "Eng Lockers": ["/area/engine/break_room"],
    "Eng Lobby": ["/area/security/checkpoint/engineering"],
    "CE Office": ["/area/crew_quarters/heads/chief"],
    "Tech Storage": ["/area/storage/tech"],
    "Atmospherics": ["/area/engine/atmos"],
    "Gravity Gen": [],
    "QM Office": ["/area/quartermaster/qm"],
    "Cargo Bay": ["/area/quartermaster/storage"],
    "Mining Dock": ["/area/quartermaster/miningdock"],
    "Cargo Lobby": ["/area/quartermaster/office"],
    "Warehouse": ["/area/quartermaster/warehouse"],
    "Recycling": ["/area/maintenance/disposal"],
    "Mining Lockers": ["/area/quartermaster/sorting"],
    "Sci Lobby": ["/area/security/checkpoint/science/research"],
    "R&D": ["/area/science/lab"],
    "RD Office": ["/area/crew_quarters/heads/hor"],
    "Servers": ["/area/science/server"],
    "Robotics": ["/area/science/robotics/lab"],
    "Mech Bay": ["/area/science/robotics/mechbay"],
    "Toxins Lab": ["/area/science/mixing"],
    "Burn Chamber": ["/area/science/mixing/chamber"],
    "Toxins Storage": ["/area/science/storage"],
    "Nanites": ["/area/science/nanite"],
    "Anomaly Lab": ["/area/science/explab"],  # alone it fits whole, keeping the R&D console within 3 tiles of the experimentor
    "Abandoned Office": ["/area/vacant_room"],
    "Maint Bar": ["/area/crew_quarters/bar/maint"],
    "Storage Closet": ["/area/storage/emergency/port", "/area/storage/primary"],
    "Abandoned Lab": ["/area/maintenance/strangeroom"],
}


# rooms whose wall onto their hall is glass (bar the door and a tile either side of it)
WINDOW_ROOMS = {
    "Bar", "Library", "Chapel", "Med Lobby", "Sci Lobby", "Eng Lobby", "Cargo Lobby", "Sec Lobby", "Courtroom",
    "Dorms", "Hydroponics", "Ward", "Chemistry", "Cloning", "Surgery", "R&D", "Robotics", "Mech Bay", "Toxins Lab",
    "Nanites", "Anomaly Lab", "Bridge", "Cells", "Atmospherics", "Cargo Bay", "Mining Dock", "Warehouse",
    "Kitchen", "Departures", "Checkpoint", "Cmd Checkpoint", "Eng Lockers", "Teleporter", "EVA", "Conference",
}

CHAIR = "/obj/structure/chair"
# furniture for rooms Hippie has no match for (or too little); a list is one tile's stack
EXTRA = {
    "Sec Lockers": ["/obj/structure/closet/secure_closet/security/sec"] * 4 + ["/obj/machinery/vending/wardrobe/sec_wardrobe", "/obj/structure/closet/wardrobe/red"],
    "Sci Lockers": ["/obj/structure/closet/wardrobe/science_white"] * 2 + ["/obj/machinery/vending/wardrobe/science_wardrobe", "/obj/structure/closet/firecloset", "/obj/structure/closet/emcloset"],
    "Mech Storage": ["/obj/structure/closet/crate"] * 2 + ["/obj/structure/closet/wardrobe/robotics_black"],
    "Cmd Storage": ["/obj/structure/closet/toolcloset", "/obj/structure/closet/emcloset", "/obj/structure/closet/firecloset", "/obj/machinery/vending/tool"],
    "Cmd Lockers": ["/obj/structure/closet/secure_closet/personal"] * 3 + ["/obj/machinery/vending/cola/random"],
    "Sat Access": ["/obj/structure/closet/emcloset", "/obj/structure/closet/firecloset", CHAIR, CHAIR],
    "HoP Queue": [CHAIR, CHAIR, CHAIR],
    "Arrivals": ["/obj/machinery/vending/cola/random", "/obj/machinery/vending/snack/random", "/obj/structure/closet/emcloset",
                 "/obj/structure/closet/firecloset", "/obj/machinery/vending/cigarette"] + [CHAIR] * 10,
    "Med Lobby": ["/obj/machinery/vending/snack/random", "/obj/machinery/vending/cola/random"] + [CHAIR] * 8,
    "Eng Lobby": ["/obj/machinery/vending/engivend"] + [CHAIR] * 4,
    "Sci Lobby": ["/obj/machinery/vending/coffee"] + [CHAIR] * 4,
    "Cargo Lobby": [CHAIR] * 4,
    "Sec Lobby": [CHAIR] * 4,
    "Med Storage": ["/obj/structure/closet/secure_closet/medical1", "/obj/structure/closet/secure_closet/medical2",
                    "/obj/structure/closet/l3closet", "/obj/machinery/vending/wardrobe/medi_wardrobe", "/obj/machinery/vending/medical",
                    ["/obj/structure/table", "/obj/item/storage/firstaid/regular", "/obj/item/storage/firstaid/regular"]],
    "Eng Lockers": ["/obj/structure/closet/secure_closet/engineering_personal"] * 3 + [
        "/obj/machinery/vending/wardrobe/engi_wardrobe", "/obj/structure/tank_dispenser/oxygen",
        "/obj/structure/closet/secure_closet/engineering_electrical", "/obj/structure/closet/secure_closet/engineering_welding"],
    "Interrogation": [["/obj/structure/table"], "/obj/structure/chair{dir = 4}", "/obj/structure/chair{dir = 8}"],
    "Atmos Storage": ["/obj/machinery/portable_atmospherics/canister/nitrogen"] * 3 + ["/obj/machinery/portable_atmospherics/canister/oxygen"] * 2
                     + ["/obj/machinery/portable_atmospherics/canister/air"] * 2,
    "Gravity Gen": ["/obj/machinery/computer/station_alert"],
    "SMES": ["/obj/machinery/computer/monitor"],
    "Engine Airlock": ["/obj/structure/closet/radiation", "/obj/structure/closet/radiation", "/obj/structure/closet/firecloset"],
    "Atmospherics": ["/obj/machinery/computer/atmos_alert"],
    "Cryo": [CHAIR, CHAIR],
    "Departures": ["/obj/machinery/vending/cola/random", "/obj/structure/closet/emcloset"],
    "Dorms": ["/obj/structure/closet/wardrobe/grey", "/obj/structure/closet/wardrobe/mixed", "/obj/machinery/vending/assist"],
}


def _rc(dept, kind=None, name=None, extra=""):
    parts = []
    if name:
        parts.append('name = "%s"' % name)
    parts.append('department = "%s"' % dept)
    if kind:
        parts.append("departmentType = %d" % kind)
    if extra:
        parts.append(extra)
    return "/obj/machinery/requests_console{%s}" % "; ".join(parts)


# wall-mounted things, put on a wall with the right pixel offset (furnish.wall_mounts). Hippie's settings.
WALL_MOUNTS = {
    "Bar": [_rc("Bar", 2, extra="receive_ore_updates = 1"), "sink"],
    "Cargo Bay": [_rc("Cargo Bay", 2)],
    "Chapel": [_rc("Chapel", 2)],
    "Chemistry": [_rc("Chemistry", 2, extra="receive_ore_updates = 1"), "sink"],
    "Hydroponics": [_rc("Hydroponics", 2), "sink", "sink"],
    "Janitor": [_rc("Janitorial", 1), "sink"],
    "Kitchen": [_rc("Kitchen", 2), "sink"],
    "Mining Dock": [_rc("Mining")],
    "Sec Office": [_rc("Security", 5, name="Security RC")],
    "Tech Storage": [_rc("Tech storage")],
    "Atmospherics": [_rc("Atmospherics", 4, name="Atmos RC")],
    "Bridge": [_rc("Bridge", 5, name="Bridge RC", extra="announcementConsole = 1")],
    "Captain": [_rc("Captain's Desk", 5, name="Captain RC", extra="announcementConsole = 1")],
    "CE Office": [_rc("Chief Engineer's Desk", 3, name="Chief Engineer RC", extra="announcementConsole = 1")],
    "CMO": [_rc("Chief Medical Officer's Desk", 5, name="Chief Medical Officer RC", extra="announcementConsole = 1")],
    "Eng Lockers": [_rc("Engineering", 4, name="Engineering RC")],
    "Cloning": [_rc("Genetics", name="Genetics Requests Console")],
    "HoP Office": [_rc("Head of Personnel's Desk", 5, name="Head of Personnel RC", extra="announcementConsole = 1")],
    "HoS Office": [_rc("Head of Security's Desk", 5, name="Head of Security RC", extra="announcementConsole = 1")],
    "Ward": [_rc("Medbay", 1, name="Medbay RC"), "sink"],
    "Surgery": ["sink"],
    "RD Office": [_rc("Research Director's Desk", 5, name="Research Director RC", extra="announcementConsole = 1; receive_ore_updates = 1")],
    "Robotics": [_rc("Robotics", 2, name="Robotics RC", extra="receive_ore_updates = 1")],
    "R&D": [_rc("Science", 2, name="Science Requests Console", extra="receive_ore_updates = 1")],
    "Telecomms": [_rc("Telecomms Admin", 5, name="Telecomms RC", extra="announcementConsole = 1")],
    "Virology": [_rc("Virology", name="Virology Requests Console"), "sink"],
    "EVA": [_rc("EVA")],
    "Dorms": [_rc("Crew Quarters")],
    "Courtroom": [_rc("Law office")],
    "Cmd Storage": [_rc("Tool Storage")],
    "Restrooms": ["sink", "sink", "sink"],
}
EXTRA.setdefault("Janitor", []).append("/obj/structure/reagent_dispensers/watertank")

WALL_MOUNTS["Restrooms"] = ["sink", "sink", "shower", "shower", "shower"]
EXTRA["Dorms"] = EXTRA.get("Dorms", []) + [["/obj/structure/bed", "/obj/item/bedsheet"]] * 4
