"""A station block plan built into a whole playable map: areas, turfs, walls and windows, airlocks with access,
furniture from the corpus (whole human-made rooms where one fits), APCs, alarms, lights, vents and scrubbers piped to
the atmos room, cable from every APC to the SMES room, solar fields wired in, job start points, latejoin, the shuttle
docks (arrivals, cargo, mining, escape) and the AI satellite.

    python tools/mapforge/station/to_dmm.py <seed> [--crew 80] [--layout pinwheel|spine|ring|mix]

Writes _maps/map_files/Generated/gen_<layout>_c<crew>_s<seed>.dmm and _maps/gen_<layout>_c<crew>_s<seed>.json, and
pictures to data/previews/mapforge/station/dmm_*.png. Boot it with bot-map=gen_<layout>_c<crew>_s<seed>.

Power and air are stand-ins for now: the SMES room holds a magical SMES (no engine), the atmos room an air tank on the
supply line and an empty tank on the scrubbers. Radio runs through one all-in-one telecomms mainframe in tcomms.
"""
import argparse
import json
import math
import os
import re
import sys
import types

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from station import shapes  # noqa: E402
from forge import build as B, dmm, kit  # noqa: E402
from forge.kit import CARD, OPP, DELTA  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
WHITE, DARK, WOOD, CARPET = ("/turf/open/floor/plasteel/white", "/turf/open/floor/plasteel/dark",
                             "/turf/open/floor/wood", "/turf/open/floor/carpet")
STEEL, PLATING = "/turf/open/floor/plasteel", "/turf/open/floor/plating"

# room id -> (area, floor turf, furnish kind (None: same as the area; "": nothing), door access, airlock kind)
A = {
    # security
    "cells": ("/area/security/brig", STEEL, None, "2", "security"),
    "detective": ("/area/security/detectives_office", WOOD, None, "4", "security"),
    "lawyer": ("/area/lawoffice", WOOD, None, "38", "public"),
    "court": ("/area/security/courtroom", WOOD, None, "", "public"),
    "processing": ("/area/security/processing", STEEL, None, "1", "security"),
    "office": ("/area/security/main", STEEL, None, "1", "security"),
    "warden": ("/area/security/warden", STEEL, None, "3", "security"),
    "armory": ("/area/ai_monitored/security/armory", DARK, None, "3", "highsecurity"),
    "hos": ("/area/crew_quarters/heads/hos", CARPET, None, "58", "command"),
    "interro": ("/area/security/processing", DARK, "/area/security/main", "1", "security"),
    "gear": ("/area/security/main", STEEL, None, "1", "security"),
    "evidence": ("/area/security/warden", DARK, "/area/security/warden", "1", "security"),
    "perma": ("/area/security/prison", STEEL, None, "2", "security"),
    "transfer": ("/area/security/execution/transfer", DARK, None, "2", "security"),
    "sec_lobby": ("/area/security/brig", STEEL, "/area/security/checkpoint", "", "public"),
    # medical
    "treatment": ("/area/medical/medbay/central", WHITE, None, "5", "medical"),
    "chem": ("/area/medical/chemistry", WHITE, None, "33", "medical"),
    "cryo": ("/area/medical/cryo", WHITE, None, "5", "medical"),
    "surgery": ("/area/medical/surgery", WHITE, None, "45", "medical"),
    "medstore": ("/area/medical/storage", WHITE, None, "5", "medical"),
    "cmo": ("/area/crew_quarters/heads/cmo", WHITE, None, "40", "command"),
    "genetics": ("/area/medical/genetics", WHITE, None, "9", "research"),
    "cloning": ("/area/medical/genetics/cloning", WHITE, None, "68", "medical"),
    "morgue": ("/area/medical/morgue", DARK, None, "6", "medical"),
    "virology": ("/area/medical/virology", WHITE, None, "39", "virology"),
    "paramedic": ("/area/medical/medbay/aft", WHITE, "/area/medical/storage", "5", "medical"),
    "med_lobby": ("/area/medical/medbay/lobby", WHITE, None, "", "public"),
    # science
    "rnd": ("/area/science/lab", WHITE, None, "7", "research"),
    "robotics": ("/area/science/robotics/lab", WHITE, None, "29", "research"),
    "mechbay": ("/area/science/robotics/mechbay", STEEL, None, "29", "research"),
    "rd": ("/area/crew_quarters/heads/hor", WHITE, None, "30", "command"),
    "server": ("/area/science/server", DARK, None, "30", "highsecurity"),
    "explab": ("/area/science/explab", WHITE, None, "7", "research"),
    "nanite": ("/area/science/nanite", WHITE, None, "7", "research"),
    "testlab": ("/area/science/misc_lab", WHITE, None, "47", "research"),
    "toxins": ("/area/science/mixing", WHITE, None, "8", "research"),
    "toxstore": ("/area/science/storage", WHITE, None, "8", "research"),
    "range": ("/area/science/misc_lab/range", STEEL, None, "47", "research"),
    "xeno": ("/area/science/xenobiology", WHITE, None, "55", "research"),
    "xeno_pens": ("/area/science/xenobiology", "/turf/open/floor/engine", "", "55", "research"),   # carve_pens
    "sci_lobby": ("/area/science/research", WHITE, None, "", "public"),
    # engineering, atmos
    "eng_check": ("/area/security/checkpoint/engineering", STEEL, None, "63", "security"),
    "techstore": ("/area/storage/tech", DARK, None, "23", "engineering"),
    "workshop": ("/area/engine/engineering", STEEL, None, "10", "engineering"),
    "ce": ("/area/crew_quarters/heads/chief", STEEL, None, "56", "command"),
    "smes": ("/area/engine/engine_smes", STEEL, "", "11", "engineering"),
    "grav": ("/area/engine/gravity_generator", STEEL, "", "11", "engineering"),
    "engbreak": ("/area/engine/break_room", STEEL, None, "10", "engineering"),
    "engine": ("/area/engine/engine_room", "/turf/open/floor/engine", "", "10", "engineering"),
    "eng_lobby": ("/area/engine/break_room", STEEL, "/area/engine/break_room", "", "public"),
    "atmos": ("/area/engine/atmos", STEEL, None, "24", "atmos"),
    "atmos_store": ("/area/engine/atmos", STEEL, "/area/storage/tech", "24", "atmos"),
    "tanks": ("/area/engine/atmos", STEEL, "", "24", "atmos"),
    "atm_lobby": ("/area/engine/atmos", STEEL, "", "", "public"),
    # cargo
    "cargo_office": ("/area/quartermaster/office", STEEL, None, "", "public"),
    "cargo_check": ("/area/security/checkpoint/supply", STEEL, None, "63", "security"),
    "qm": ("/area/quartermaster/qm", STEEL, None, "41", "mining"),
    "sorting": ("/area/quartermaster/sorting", STEEL, None, "50", "mining"),
    "warehouse": ("/area/quartermaster/warehouse", STEEL, None, "31", "mining"),
    "bay": ("/area/quartermaster/storage", STEEL, None, "31", "mining"),
    "mining": ("/area/quartermaster/miningdock", STEEL, None, "48", "mining"),
    "cargo_lobby": ("/area/quartermaster/office", STEEL, None, "", "public"),
    # dorms, civic
    "cabins": ("/area/crew_quarters/dorms", CARPET, None, "", "public"),
    "lockers": ("/area/crew_quarters/locker", STEEL, None, "", "public"),
    "restroom": ("/area/crew_quarters/toilet/restrooms", "/turf/open/floor/plasteel/freezer", None, "", "public"),
    "gym": ("/area/crew_quarters/fitness/recreation", STEEL, None, "", "public"),
    "cryodorm": ("/area/crew_quarters/dorms", STEEL, "/area/crew_quarters/dorms", "", "public"),
    "library": ("/area/library", WOOD, None, "", "public"),
    "toolstore": ("/area/storage/tools", STEEL, "/area/storage/primary", "", "public"),
    "art": ("/area/storage/art", STEEL, None, "", "public"),
    "chapel": ("/area/chapel/main", DARK, None, "", "public"),
    "chap_office": ("/area/chapel/office", DARK, None, "22", "public"),
    "vacant": ("/area/vacant_room/office", STEEL, "/area/vacant_room", "", "public"),
    # arrivals, escape
    "arr_lounge": ("/area/hallway/secondary/entry", STEEL, "", "", "public"),
    "customs": ("/area/security/checkpoint/customs", STEEL, None, "63", "security"),
    "arr_store": ("/area/storage/primary", STEEL, "/area/storage/emergency/port", "", "public"),
    "departures": ("/area/hallway/secondary/exit/departure_lounge", STEEL, "", "", "public"),
    "esc_check": ("/area/security/checkpoint/escape", STEEL, "/area/security/checkpoint", "63", "security"),
    # command, service
    "bridge": ("/area/bridge", DARK, None, "19", "command"),
    "captain": ("/area/crew_quarters/heads/captain", WOOD, None, "20", "command"),
    "cap_bed": ("/area/crew_quarters/heads/captain/private", CARPET, None, "20", "command"),
    "hop": ("/area/crew_quarters/heads/hop", STEEL, None, "57", "command"),
    "eva": ("/area/ai_monitored/storage/eva", STEEL, None, "18", "command"),
    "teleporter": ("/area/teleporter", STEEL, None, "17", "command"),
    "gateway": ("/area/gateway", DARK, None, "62", "command"),
    "vault": ("/area/ai_monitored/nuke_storage", DARK, None, "53", "vault"),
    "upload": ("/area/ai_monitored/turret_protected/ai_upload", DARK, None, "16", "highsecurity"),
    "bar": ("/area/crew_quarters/bar", WOOD, None, "", "public"),
    "kitchen": ("/area/crew_quarters/kitchen", "/turf/open/floor/plasteel/cafeteria", None, "28", "public"),
    "cold": ("/area/crew_quarters/kitchen/coldroom", "/turf/open/floor/plasteel/freezer", None, "28", "public"),
    "theatre": ("/area/crew_quarters/theatre", WOOD, None, "46", "public"),
    "hydro": ("/area/hydroponics", STEEL, None, "35", "public"),
    "garden": ("/area/hydroponics/garden", "/turf/open/floor/grass", None, "", "public"),
    "janitor": ("/area/janitor", STEEL, None, "26", "public"),
    # AI satellite
    "ai_core": ("/area/ai_monitored/turret_protected/ai", "/turf/open/floor/circuit", "", "16", "highsecurity"),
    "tcomms": ("/area/tcommsat/server", "/turf/open/floor/circuit", "", "61", "highsecurity"),
    "tc_control": ("/area/tcommsat/computer", DARK, None, "61", "command"),
    "sat_hall": ("/area/ai_monitored/turret_protected/aisat/hallway", DARK, "", "65", "highsecurity"),
    "sat_tunnel": ("/area/ai_monitored/turret_protected/aisat/foyer", DARK, "", "65", "highsecurity"),
}
# big public side rooms and closets off the halls, by label
SIDE = {"park": ("/area/hydroponics/garden", "/turf/open/floor/grass", "/area/hydroponics/garden"),
        "arcade": ("/area/crew_quarters/fitness/recreation", CARPET, "/area/crew_quarters/abandoned_gambling_den"),
        "holodeck": ("/area/crew_quarters/fitness/recreation", STEEL, "/area/crew_quarters/fitness/recreation"),
        "pool": ("/area/hippie/pool", STEEL, "/area/hippie/pool"),
        "gallery": ("/area/library/lounge", WOOD, "/area/library/lounge"),
        "lounge": ("/area/crew_quarters/lounge", CARPET, "/area/crew_quarters/lounge"),
        "restroom": ("/area/crew_quarters/toilet/auxiliary", "/turf/open/floor/plasteel/freezer", "/area/crew_quarters/toilet"),
        "fire closet": ("/area/storage/emergency/port", STEEL, "/area/storage/emergency/port"),
        "e-closet": ("/area/storage/emergency/starboard", STEEL, "/area/storage/emergency/starboard"),
        "aux storage": ("/area/storage/primary", STEEL, "/area/storage/primary"),
        "vending": (None, STEEL, ""),
        "closet": ("/area/storage/emergency/port", PLATING, "/area/storage/emergency/port"),
        "vacant": ("/area/vacant_room", STEEL, "/area/vacant_room"),
        "office": ("/area/vacant_room/office", WOOD, "/area/vacant_room/office"),
        "game room": ("/area/crew_quarters/fitness/recreation", CARPET, "/area/crew_quarters/abandoned_gambling_den"),
        "substation": ("/area/maintenance/department/electrical", PLATING, "/area/storage/tools"),
        "cryo": ("/area/crew_quarters/dorms", STEEL, "/area/crew_quarters/dorms"),
        "barber": ("/area/crew_quarters/lounge", STEEL, "/area/crew_quarters/lounge"),
        "photo": ("/area/crew_quarters/lounge", STEEL, "/area/crew_quarters/lounge"),
        }
ABANDONED = ["/area/crew_quarters/abandoned_gambling_den", "/area/library/abandoned", "/area/medical/abandoned",
             "/area/science/research/abandoned", "/area/crew_quarters/theatre/abandoned", "/area/hydroponics/garden/abandoned"]
# the rooms maint closes in, each its own area (and APC) and look, in this order: abandoned rooms between emergency
# storage, vacant offices and storerooms, as the stock maps' maint has them. Every one used to be the dorms' maint
# area with six looks in turn: the ring's core packed 20 of them, one area, each look three times over (2026-11-16).
# Areas a station room already has are skipped; past the list, maint department areas with the abandoned looks.
FILLERS = [("/area/crew_quarters/abandoned_gambling_den", PLATING, None), ("/area/library/abandoned", PLATING, None),
           ("/area/storage/emergency/port", PLATING, None), ("/area/medical/abandoned", PLATING, None),
           ("/area/vacant_room/office", STEEL, None), ("/area/science/research/abandoned", PLATING, None),
           ("/area/storage/art", STEEL, None), ("/area/crew_quarters/theatre/abandoned", PLATING, None),
           ("/area/vacant_room/commissary", STEEL, None), ("/area/hydroponics/garden/abandoned", PLATING, None),
           ("/area/storage/emergency/starboard", PLATING, None), ("/area/construction/storage_wing", PLATING, None),
           ("/area/crew_quarters/abandoned_gambling_den/secondary", PLATING, None), ("/area/vacant_room", STEEL, None)]
FILLER_AREAS = {a for a, _, _ in FILLERS}
FILLER_MAINT = ["/area/maintenance/department/electrical", "/area/maintenance/department/science",
                "/area/maintenance/department/chapel", "/area/maintenance/department/crew_quarters/bar",
                "/area/maintenance/department/crew_quarters/dorms", "/area/maintenance/department/cargo",
                "/area/maintenance/department/engine", "/area/maintenance/department/medical"]
DEPT_HALL = {"security": "/area/security/brig", "medical": "/area/medical/medbay/central",
             "science": "/area/science/research", "engineering": "/area/engine/engineering",
             "atmos": "/area/engine/atmos", "cargo": "/area/quartermaster/office", "dorms": "/area/crew_quarters/dorms",
             "civic": "/area/hallway/secondary/service", "service": "/area/hallway/secondary/service",
             "command": "/area/hallway/secondary/command", "arrivals": "/area/hallway/secondary/entry",
             "escape": "/area/hallway/secondary/exit", "ai": "/area/ai_monitored/turret_protected/aisat/hallway"}
DEPT_DOOR = {"security": ("1", "security"), "medical": ("5", "medical"), "science": ("47", "research"),
             "engineering": ("10", "engineering"), "atmos": ("24", "atmos"), "cargo": ("31", "mining"),
             "command": ("19", "command"), "ai": ("65", "highsecurity")}
# job -> (room ids in order of preference, how many)
JOBS = [("captain", ("captain", "bridge"), 1), ("head_of_personnel", ("hop", "bridge"), 1),
        ("head_of_security", ("hos", "office"), 1), ("warden", ("warden", "office"), 1),
        ("detective", ("detective", "office"), 1), ("security_officer", ("office", "gear", "cells"), 5),
        ("chief_medical_officer", ("cmo", "treatment"), 1), ("medical_doctor", ("treatment", "medstore"), 5),
        ("chemist", ("chem", "treatment"), 2), ("geneticist", ("genetics", "treatment"), 2),
        ("virologist", ("virology", "treatment"), 1), ("research_director", ("rd", "rnd"), 1),
        ("scientist", ("rnd", "testlab", "explab", "sci_lobby"), 5), ("roboticist", ("robotics", "rnd"), 2),
        ("chief_engineer", ("ce", "workshop"), 1), ("station_engineer", ("workshop", "engbreak", "smes"), 5),
        ("atmospheric_technician", ("atmos",), 3), ("quartermaster", ("qm", "cargo_office"), 1),
        ("cargo_technician", ("bay", "cargo_office"), 3), ("shaft_miner", ("mining", "bay"), 3),
        ("bartender", ("bar",), 1), ("cook", ("kitchen", "bar"), 2), ("botanist", ("hydro",), 3),
        ("janitor", ("janitor",), 1), ("librarian", ("library",), 1), ("chaplain", ("chapel", "chap_office"), 1),
        ("lawyer", ("lawyer", "court"), 2), ("clown", ("theatre", "bar"), 1), ("mime", ("theatre", "bar"), 1),
        ("assistant", ("lockers", "cabins"), 8), ("cyborg", ("robotics", "mechbay", "sat_hall"), 2),
        ("ai", ("ai_core",), 1)]
# what makes each room that room: the pieces most stock maps have in it (Hippie, Meta, Box, Delta, Pubby). A
# template without them loses score and gets them added; without this a "kitchen" came from Delta's meat locker
# (spikes, gibber, no stove) and "hydroponics" from a seed closet with no trays.
REQUIRE = {
    "kitchen": [("/obj/structure/table", 4), "/obj/machinery/microwave", "/obj/machinery/deepfryer", "/obj/machinery/processor",
                "/obj/machinery/vending/dinnerware", "/obj/machinery/icecream_vat"],
    "hydro": [("/obj/machinery/hydroponics/constructable", 8), "/obj/machinery/biogenerator", "/obj/machinery/seed_extractor",
              "/obj/machinery/plantgenes", "/obj/structure/sink"],
    "bar": [("/obj/structure/table/reinforced", 3), ("/obj/structure/chair/stool", 4)],
    "treatment": [("/obj/structure/bed/roller", 3), ("/obj/machinery/sleeper", 2), "/obj/machinery/vending/medical",
                  "/obj/machinery/computer/crew", ("/obj/machinery/iv_drip", 2)],
    "rnd": ["/obj/machinery/rnd/destructive_analyzer", "/obj/machinery/computer/rdconsole/core",
            "/obj/machinery/rnd/production/protolathe/department/science",
            "/obj/machinery/rnd/production/circuit_imprinter/department/science"],
    "robotics": ["/obj/machinery/mecha_part_fabricator", "/obj/structure/table/optable", "/obj/machinery/computer/operating",
                 "/obj/machinery/computer/rdconsole/robotics"],
    "chem": [("/obj/machinery/chem_dispenser", 2), ("/obj/machinery/chem_master", 2), "/obj/machinery/chem_heater"],
    "surgery": ["/obj/structure/table/optable", "/obj/machinery/computer/operating"],
    "morgue": [("/obj/structure/bodycontainer/morgue", 4)],
    "xeno": ["/obj/machinery/computer/camera_advanced/xenobio", "/obj/machinery/monkey_recycler"],
    "mechbay": ["/obj/machinery/mech_bay_recharge_port", "/obj/machinery/computer/mech_bay_power_console",
                "/obj/machinery/recharge_station"],
    "nanite": ["/obj/machinery/nanite_chamber", "/obj/machinery/computer/nanite_chamber_control",
               "/obj/machinery/nanite_program_hub", "/obj/machinery/nanite_programmer"],
    "explab": ["/obj/machinery/rnd/experimentor", "/obj/machinery/computer/rdconsole/experiment"],
    "library": [("/obj/structure/table/wood", 4), "/obj/structure/bookcase/random/fiction",
                "/obj/structure/bookcase/random/nonfiction", "/obj/structure/bookcase/random/reference"],
    "cabins": [("/obj/structure/bed", 1)],
    "cells": [("/obj/structure/bed", 1)],
    # the long-stay cell sleeps two: perma had no bed on any seed (2026-11-16 quad review)
    "perma": [("/obj/structure/bed", 2)],
    "vault": ["/obj/machinery/ore_silo", "/obj/machinery/computer/bank_machine", "/obj/structure/safe",
              "/obj/structure/closet/crate/goldcrate"],
    "restroom": [("/obj/structure/toilet", 2), ("/obj/structure/sink", 2)],
    # bomb benches with their parts, the bomb suits, and the portable air you fill tanks with
    "toxins": [("/obj/structure/table/reinforced", 4), ("/obj/structure/closet/bombcloset", 2), "/obj/item/transfer_valve",
               "/obj/machinery/portable_atmospherics/pump", "/obj/machinery/portable_atmospherics/scrubber"],
    # an open floor for crates to land on: a few crates and racks by the walls, an emergency closet, no desks
    "bay": [("/obj/structure/closet/crate", 3), ("/obj/structure/rack", 2), "/obj/structure/closet/emcloset"],
    # wrapping benches: tagger, labeler, paper, a seat at the desk
    "sorting": [("/obj/structure/table/reinforced", 3), "/obj/item/destTagger", "/obj/item/hand_labeler",
                "/obj/item/stack/packageWrap", "/obj/structure/chair/office", "/obj/structure/filingcabinet/filingcabinet"],
    "lockers": [("/obj/structure/closet/secure_closet/personal", 4)],
    "genetics": ["/obj/machinery/dna_scannernew", "/obj/machinery/computer/scan_consolenew"],
    "cloning": ["/obj/machinery/clonepod", "/obj/machinery/computer/cloning", "/obj/machinery/dna_scannernew"],
    "virology": ["/obj/machinery/computer/pandemic", ("/obj/structure/bed", 2)],
    "eva": [("/obj/machinery/suit_storage_unit/standard_unit", 4)],
    "office": [("/obj/structure/closet/secure_closet/security/sec", 4)],
    "toolstore": ["/obj/machinery/vending/tool", "/obj/machinery/vending/assist"],
    "janitor": ["/obj/structure/janitorialcart", "/obj/structure/closet/l3closet/janitor"],
    "theatre": ["/obj/structure/piano", "/obj/machinery/vending/autodrobe"],
    "medstore": [("/obj/structure/closet/secure_closet/medical3", 2), "/obj/machinery/vending/medical"],
    "bridge": ["/obj/machinery/computer/communications", "/obj/machinery/computer/crew", "/obj/machinery/computer/security",
               "/obj/machinery/computer/station_alert"],
    # engineers' and atmos techs' own lockers (insulated gloves, belts), the CE's locker with the advanced gloves
    "workshop": [("/obj/structure/closet/secure_closet/engineering_personal", 3), "/obj/machinery/vending/engivend"],
    "ce": ["/obj/structure/closet/secure_closet/engineering_chief"],
    "atmos": [("/obj/structure/closet/secure_closet/atmospherics", 2)],
}
# the produce fridge Botany stocks and the Kitchen cooks from: stock maps set it in the wall between the two
REQUIRE["hydro"] = REQUIRE["hydro"] + ["/obj/machinery/smartfridge"]
# requests consoles (department, departmentType bits: 1 assistance, 2 supplies, 4 information), as the stock maps
REQUESTS = {"bridge": ("Bridge", 5), "captain": ("Captain's Desk", 5), "hop": ("Head of Personnel's Desk", 5),
            "hos": ("Head of Security's Desk", 5), "office": ("Security", 5), "warden": ("Warden", 1),
            "cmo": ("Chief Medical Officer's Desk", 5), "treatment": ("Medbay", 1), "chem": ("Chemistry", 2),
            "virology": ("Virology", 1), "genetics": ("Genetics", 1),
            "rd": ("Research Director's Desk", 5), "rnd": ("Science", 3), "robotics": ("Robotics", 2),
            "ce": ("Chief Engineer's Desk", 5), "workshop": ("Engineering", 3), "atmos": ("Atmospherics", 3),
            "cargo_office": ("Cargo Bay", 2), "qm": ("Quartermaster's Desk", 5), "mining": ("Mining", 1),
            "kitchen": ("Kitchen", 1), "hydro": ("Hydroponics", 1), "bar": ("Bar", 1), "janitor": ("Janitorial", 1),
            "toolstore": ("Tool Storage", 0)}
# Box's dock ports, so stock shuttle templates fit: id -> (width, dwidth, height, template / json key)
PORTS = {"arrivals": ("arrivals_stationary", 7, 3, 13, "roundstart_template = /datum/map_template/shuttle/arrival/donut"),
         "cargo": ("supply_home", 12, 5, 7, None),           # the cargo shuttle starts at CentCom, as on Box
         "mining": ("mining_home", 7, 3, 5, "roundstart_template = /datum/map_template/shuttle/mining/box"),
         "escape": ("emergency_home", 14, 6, 18, None)}      # Birdboat's own size
SHUTTLES = {"cargo": "cargo_box", "emergency": "emergency_birdboat"}


# pieces a room never takes from the corpus (a cargo bay is not an office: paperwork desks came from Delta's bay)
EXCLUDE = {"bay": ("/obj/structure/table", "/obj/structure/chair", "/obj/item/paper", "/obj/machinery/computer")}
# and none, anywhere: a stock engine's working parts. Box's engine is in /area/engine/engineering, so the workshop took
# its wired emitters and reflectors from the corpus, and the engineers set up those instead of the crystal's (gen1116e)
ENGINE_PARTS = ("/obj/machinery/power/emitter", "/obj/structure/reflector", "/obj/machinery/power/rad_collector",
                "/obj/machinery/field", "/obj/machinery/power/supermatter", "/obj/machinery/particle_accelerator",
                "/obj/structure/particle_accelerator", "/obj/machinery/the_singularitygen", "/obj/machinery/power/tesla_coil",
                "/obj/machinery/power/grounding_rod", "/obj/machinery/power/generator",
                "/obj/machinery/atmospherics/components/binary/circulator")
# required pieces that grow with the room: one per this many floor tiles (a big treatment ward is rows of beds)
SCALE = {"treatment": {"/obj/structure/bed/roller": 14, "/obj/machinery/iv_drip": 28},
         "toxins": {"/obj/structure/table/reinforced": 20},
         "sorting": {"/obj/structure/table/reinforced": 18}}


def base_id(rid):
    return re.sub(r"_?\d+$", "", rid)      # cabins_3 is a cabin, rnd2 an R&D lab


class StationBuilder(B.Builder):
    """The forge builder, fed from a plan instead of a drawing; networks grow from roots, not from a zone edge."""

    def __init__(self, bp, roots):
        self.roots = roots          # cls -> tile the network grows from
        super().__init__(bp)

    def free_faces(self, area, avoid_doors=True, on_wall=True, optional=False):
        out = super().free_faces(area, avoid_doors, on_wall, optional)
        no = getattr(self, "no_mount", ())
        return [f for f in out if f[0] not in no] if no else out

    # the supermatter block's tiles (fit_engine): the station's cables, pipes, vents and wall-hung things keep off them,
    # and the block's two cable ends join the station grid like APCs do
    engine_cable_fence = frozenset()
    engine_pipe_fence = frozenset()
    engine_no_vent = frozenset()    # the walkway beside the core: a pipe can only reach it through the block
    engine_cables = ()
    tank_tiles = frozenset()

    def find_ports(self):
        self.ports = {"supply": [], "scrubbers": [], "cable": []}
        self.cable_fence = set(self.engine_cable_fence)

    pool_water = frozenset()        # reserve_pools(): the basin dug after the run; no vent or pipe under it

    def spec(self, p):
        s = super().spec(p)
        return dict(s, no_vent=True) if p in self.engine_pipe_fence or p in self.engine_no_vent or \
            p in self.tank_tiles or p in self.pool_water else s

    def pipe_cost(self, cls):
        base = super().pipe_cost(cls)
        # the distro tanks go down after the run: a pipe laid over the air tank's tile took its connection
        fence = self.engine_pipe_fence | self.tank_tiles | self.pool_water
        return (lambda q, p, d: None if q in fence else base(q, p, d)) if fence else base

    def power(self):
        apcs = getattr(self, "apc_tiles", [])
        self.apc_tiles = list(apcs) + [p for p in self.engine_cables if p not in apcs]
        try:
            return super().power()
        finally:
            self.apc_tiles = apcs

    def vent_count(self, area, rd=None):
        """Maint as the stock maps vent it (the user's ruling, 2026-11-16): a maint room under 40 tiles has no vent or
        scrubber, a bigger one one of each; the maint corridors a vent every ~90 tiles and no scrubbers (MetaStation:
        port/fore 300 tiles, five vents, no scrubber). One pair per 45 tiles put 17 of each down maint/fore."""
        n, ns = super().vent_count(area, rd)
        if not n:
            return n, ns
        floors = len([p for p in self.floors_of(area) if p not in self.engine_pipe_fence])
        if floors < len(self.floors_of(area)):      # the engine room: vented for the floor the block leaves
            n = ns = max(1, round(floors / 45.0))
        corridor = area.startswith("/area/maintenance/") and not area.startswith(
            ("/area/maintenance/department", "/area/maintenance/solars", "/area/maintenance/disposal"))
        if corridor:
            return max(1, round(floors / 90)), 0
        if area.startswith(("/area/maintenance/department", "/area/maintenance/solars")) or area in FILLER_AREAS:
            return (0, 0) if floors < 40 else (1, 1)
        return n, ns

    def atmos(self):
        # the cryo bay's own loop goes down first, so the station's pipes route round it
        from forge import function as F
        for area in ("/area/medical/cryo", "/area/medical/medbay/central"):
            if self.floors_of(area):
                self.notes.append(F.place_cryo(self, area))
                print("   ", self.notes[-1])
                if self.notes[-1].startswith("cryo bay"):
                    break
        return super().atmos()

    def forest(self, cls, terminals, cost_fn):
        root = self.roots.get(cls)
        if root is None:
            return super().forest(cls, terminals, cost_fn)
        mask = {}
        unary = set(terminals) - {root} if cls != "cable" else set()

        def lay(path):
            for a, b in zip(path, path[1:]):
                d = next(dd for dd in CARD if self.nb(a, dd) == b)
                mask[a] = mask.get(a, 0) | d
                mask[b] = mask.get(b, 0) | OPP[d]
            if len(path) == 1:
                mask.setdefault(path[0], 0)
        lay([root])
        left = {t for t in terminals if t != root}
        # one search that goes on as the tree grows: each new branch joins the sources at cost 0 and the search
        # carries on from where it stood (a fresh search per terminal was 600 searches over the whole station)
        import heapq
        dist, prev, heap = {}, {}, []

        def add_source(p):
            if p in unary or dist.get((p, 0), 1e9) == 0:
                return
            dist[(p, 0)] = 0
            prev.pop((p, 0), None)
            heapq.heappush(heap, (0, p, 0))
        add_source(root)
        while left:
            found = None
            while heap:
                c, p, din = heapq.heappop(heap)
                if dist.get((p, din), 1e9) < c:
                    continue
                if p in left:
                    found = (p, din)
                    break
                if p in unary and din:
                    continue
                for d in CARD:
                    q = self.nb(p, d)
                    if q in mask:
                        continue
                    step = cost_fn(q, p, d)
                    if step is None:
                        continue
                    if din and d != din:
                        step += 2.5
                    nc = c + step
                    if nc < dist.get((q, d), 1e9):
                        dist[(q, d)] = nc
                        prev[(q, d)] = (p, din)
                        heapq.heappush(heap, (nc, q, d))
            if not found:
                self.warn.append("%s: could not reach %s" % (cls, ", ".join("%d,%d" % t for t in sorted(left)[:8])))
                break
            path, node = [found[0]], found
            while node in prev:
                node = prev[node]
                path.append(node[0])
            path.reverse()
            lay(path)
            left -= set(mask)
            for p in path:
                add_source(p)
        return mask


def convert(plan, layout_name, crew, seed):
    """plan -> (blueprint namespace, the map transform, notes)."""
    pts = set(plan.floor) | plan.walls | set(plan.doors) | plan.glass | set(plan.solar)
    for p, side, name, dims in plan.docks:
        pts.add(p)
        if name in PORTS:   # the docked shuttle's footprint stays on the map
            _, w, dw, h, _ = PORTS[name]
            dirn = {(0, 1): 1, (0, -1): 2, (1, 0): 4, (-1, 0): 8}[tuple(side)]
            x1, y1, x2, y2 = port_rect((p[0] + side[0], p[1] + side[1]), dirn, w, dw, h)
            pts |= {(x1, y1), (x2, y2)}
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    pad = 8
    x0, y0 = min(xs) - pad, min(ys) - pad
    W, H = max(xs) - x0 + pad + 1, max(ys) - y0 + pad + 1
    W, H = max(W, 255), max(H, 255)
    off = ((W - (max(xs) - min(xs) + 1)) // 2 - min(xs) + 1, (H - (max(ys) - min(ys) + 1)) // 2 - min(ys) + 1)

    def T(p):
        return (p[0] + off[0], p[1] + off[1])
    cx = sum(xs) / float(len(xs)) + off[0]
    cy = sum(ys) / float(len(ys)) + off[1]
    span = max(max(xs) - min(xs), max(ys) - min(ys))

    def compass(p, inner=0.18):
        dx, dy = p[0] - cx, p[1] - cy
        if math.hypot(dx, dy) < inner * span:
            return "central"
        a = math.degrees(math.atan2(dy, dx)) % 360
        return ["starboard", "fore", "port", "aft"][int(((a + 45) % 360) // 90)]

    # areas per room
    roomdefs, area_of = {}, {}
    aband_n = 0
    side_used = {}
    fillers = list(FILLERS)
    # the station's own rooms first, so a filler never takes an area one of them has
    for rid, meta in sorted(plan.rooms.items(), key=lambda kv: kv[0].startswith("aband")):
        b = base_id(rid)
        tiles = [T(p) for p, r in plan.floor.items() if r == rid]
        if not tiles:
            continue
        mid = (sum(t[0] for t in tiles) / float(len(tiles)), sum(t[1] for t in tiles) / float(len(tiles)))
        floor, furn = STEEL, ""
        if b in A:
            area, floor, furn, _, _ = A[b]
            furn = area if furn is None else furn
        elif rid == "ring":
            area, furn = "/area/hallway/primary/central", ""
        elif rid == "maint" or meta.get("kind") == "maint" or meta.get("dept") == "maint" and not rid.startswith("aband"):
            area, floor, furn = "/area/maintenance/central", PLATING, ""
        elif rid.startswith("aband"):
            taken = {v[0] for v in area_of.values()}
            while fillers and fillers[0][0] in taken:
                fillers.pop(0)
            if fillers:
                area, floor, furn = fillers.pop(0)
                furn = area if furn is None else furn
            else:
                free_m = [a_ for a_ in FILLER_MAINT if a_ not in taken] or FILLER_MAINT
                area, floor = free_m[0], PLATING
                furn = ABANDONED[aband_n % len(ABANDONED)]
                aband_n += 1
        elif rid.startswith("solar_lock"):
            area, floor, furn = "/area/maintenance/solars", PLATING, ""
        elif rid.startswith("solar_"):
            area, floor, furn = "/area/maintenance/solars", PLATING, ""
        elif meta.get("kind") == "hall":
            area = DEPT_HALL.get(meta.get("dept"), "/area/hallway/secondary/construction")
            floor = WHITE if meta.get("dept") in ("medical", "science") else STEEL
        else:
            lab = meta.get("label", "")
            area, floor, furn = SIDE.get(lab, ("/area/storage/emergency/port", STEEL, ""))
            if area is None:
                area = "/area/hallway/primary/central"
            if furn is None:
                furn = area
            side_used[lab] = side_used.get(lab, 0) + 1
        area_of[rid] = [area, floor, furn, mid]
    # halls and maint split by compass, so each stretch has its own APC and name
    for rid, v in area_of.items():
        if v[0] == "/area/hallway/primary/central":
            pass
    rd_list = []
    hall_split, maint_split = {}, {}
    for p, rid in plan.floor.items():
        q = T(p)
        if rid == "ring":
            k = compass(q)
            hall_split[q] = "/area/hallway/primary/%s" % k
        elif rid == "maint":
            k = compass(q, 0.0)
            sub = "fore" if q[1] > cy else "aft"
            maint_split[q] = {"port": "/area/maintenance/port/%s" % sub, "starboard": "/area/maintenance/starboard/%s" % sub,
                              "fore": "/area/maintenance/fore", "aft": "/area/maintenance/aft"}[k]
    # solar rooms and fields by quadrant, each array its own pair of areas
    solar_area = {}
    free = [("port", "fore"), ("starboard", "fore"), ("port", "aft"), ("starboard", "aft")]
    for rect, label in plan.solars:
        mx, my = T(((rect[0] + rect[2]) // 2, (rect[1] + rect[3]) // 2))
        want = ("port" if mx < cx else "starboard", "fore" if my > cy else "aft")
        pick = want if want in free else (free[0] if free else want)
        if pick in free:
            free.remove(pick)
        solar_area[label] = pick
    for label, (ps, fa) in solar_area.items():
        for rid in ("solar_%s" % label, "solar_lock_%s" % label):
            if rid in area_of:
                area_of[rid][0] = "/area/maintenance/solars/%s/%s" % (ps, fa)

    # one roomdef per (room, area): chars from a pool
    pool = iter(chr(c) for c in range(0x100, 0x6000))
    rc_of = {}
    for rid, (area, floor, furn, mid) in area_of.items():
        ch = next(pool)
        rc_of[rid] = ch
        rd = dict(area=area, floor=floor, name=rid)
        if furn:
            need = REQUIRE.get(base_id(rid)) or (REQUIRE["restroom"] if plan.rooms.get(rid, {}).get("label") == "restroom" else ())
            per = SCALE.get(base_id(rid))
            if per:
                size = sum(1 for r in plan.floor.values() if r == rid)
                need = [(e if isinstance(e, tuple) else (e, 1)) for e in need]
                need = [(p_, max(n_, size // per[p_]) if p_ in per else n_) for p_, n_ in need]
            rd["furnish"] = dict(kind=furn, mode="template", seed=seed, require=need, exclude=EXCLUDE.get(base_id(rid), ()) + ENGINE_PARTS)
        roomdefs[ch] = rd
    # a requests console per department room; the builder hangs it on the first roomdef of the area (rooms that
    # share an area, like the security office and the gear room, get one between them)
    for rid, (area, floor, furn, mid) in area_of.items():
        rq = REQUESTS.get(base_id(rid))
        if rq:
            first = next(rd for rd in roomdefs.values() if rd["area"] == area)
            first.setdefault("requests", rq)
    split_rc = {}
    for q, area in list(hall_split.items()) + list(maint_split.items()):
        if area not in split_rc:
            ch = next(pool)
            split_rc[area] = ch
            roomdefs[ch] = dict(area=area, floor=PLATING if "/maintenance/" in area else STEEL, name=area.rsplit("/", 2)[-2] + "/" + area.rsplit("/", 1)[-1])

    # door legend entries
    legend = {"#": {"turf": "wall"}, "R": {"turf": "rwall"}, "=": {"turf": "window"}, "%": {"turf": "rwindow"},
              ".": {}}
    dspecs = {}

    def door_char(spec):
        key = repr(spec)
        if key not in dspecs:
            dspecs[key] = next(pool)
            legend[dspecs[key]] = spec
        return dspecs[key]

    ch, room = {}, {}
    for p, rid in plan.floor.items():
        q = T(p)
        ch[q] = "."
        room[q] = split_rc[hall_split[q]] if q in hall_split else split_rc[maint_split[q]] if q in maint_split else rc_of[rid]
    for p in plan.walls | plan.hull:
        q = T(p)
        if q in ch:
            continue
        ch[q] = "R" if p in plan.rwall else "#"
    for p in plan.glass:
        q = T(p)
        ch[q] = "%" if p in plan.hull or p in plan.rwall else "="
    for p, kind in plan.doors.items():
        q = T(p)
        sides = [plan.floor.get((p[0] + DELTA[d][0], p[1] + DELTA[d][1])) for d in CARD]
        sides = [s for s in sides if s]
        spec = door_spec(plan, kind, sides)
        if spec is None:
            ch[q] = "."
        else:
            ch[q] = door_char(spec)
        # the door belongs to the more private side's area
        inner = sorted(sides, key=lambda r: (r == "ring", r == "maint", plan.rooms.get(r, {}).get("kind") == "hall"))
        if inner:
            r0 = inner[0]
            q0 = T(next(pp for pp in ((p[0] + DELTA[d][0], p[1] + DELTA[d][1]) for d in CARD) if plan.floor.get(pp) == r0))
            room[q] = room[q0]
    bp = types.SimpleNamespace(NAME="gen_%s_c%d_s%d" % (layout_name, crew, seed), BASE="blank", THIN_WALLS=False,
                               ORIGIN=(1, 1), ROOMDEFS=roomdefs, LEGEND=legend, STYLE="meta", SEED=seed,
                               DISPOSALS="none", REHANG=False)
    lay_lines, room_lines = [], []
    for y in range(H, 0, -1):
        lay_lines.append("".join(ch.get((x, y), "~") for x in range(1, W + 1)))
        room_lines.append("".join(room.get((x, y), " ") for x in range(1, W + 1)))
    bp.LAYOUT = "\n".join(lay_lines)
    bp.ROOMS = "\n".join(room_lines)
    return bp, T, (W, H), rc_of, solar_area


def door_spec(plan, kind, sides):
    """A plan door -> legend spec (None: an open doorway)."""
    if kind == "open":
        return None
    priv = [r for r in sides if r not in ("ring", "maint") and plan.rooms.get(r, {}).get("kind") != "hall"]
    if kind == "maint":
        return {"obj": [("/obj/machinery/door/airlock/maintenance", {"req_access_txt": "12"})]}
    if kind in ("dock", "external"):
        acc = {"req_access_txt": "13"} if kind == "external" else {}
        return {"obj": [("/obj/machinery/door/airlock/external", dict(acc))], "firedoor": False}
    if kind == "public":
        r = priv[0] if priv else None
        b = base_id(r) if r else None
        acc = A[b][3] if b in A else ""
        vs = {"req_access_txt": acc} if acc else {}
        return {"obj": [("/obj/machinery/door/airlock/public/glass" if not acc else "/obj/machinery/door/airlock/public/glass", vs)]}
    # access / secure / link: the private room's own door
    target = priv[0] if priv else (sides[0] if sides else None)
    b = base_id(target) if target else None
    if b in A:
        acc, kind_ = A[b][3], A[b][4]
    else:
        dept = plan.rooms.get(target, {}).get("dept") if target else None
        acc, kind_ = DEPT_DOOR.get(dept, ("", "public"))
    path = "/obj/machinery/door/airlock/%s" % kind_
    if kind_ in ("security", "medical", "research", "engineering", "atmos", "mining", "command", "virology", "public") \
            and kind != "secure":
        path += "/glass"
    vs = {"req_access_txt": acc} if acc else {}
    return {"obj": [(path, vs)]}


def free_tiles(bd, rc, n=1, avoid=()):
    """Free floor tiles of a room, most central first, off its doors."""
    tiles = [p for p, r in bd.room.items() if r == rc and bd.is_floor(p) and bd.ch.get(p) == "."]
    if not tiles:
        return []
    mx = sum(p[0] for p in tiles) / float(len(tiles))
    my = sum(p[1] for p in tiles) / float(len(tiles))
    out = []
    for p in sorted(tiles, key=lambda p: (p[0] - mx) ** 2 + (p[1] - my) ** 2):
        t = bd.t(*p)
        if kit.dense(t.objs) or t.has("/obj/machinery/door") or p in avoid:
            continue
        if any(bd.t(*bd.nb(p, d)).has("/obj/machinery/door") for d in CARD):
            continue
        if any(o.path.startswith(("/obj/effect/landmark", "/obj/machinery/atmospherics", "/obj/machinery/holopad"))
               for o in t.objs):
            continue
        out.append(p)
        if len(out) >= n:
            break
    return out


D4 = {1: (0, 1), 2: (0, -1), 4: (1, 0), 8: (-1, 0)}
PIX = {1: ("pixel_y", 32), 2: ("pixel_y", -32), 4: ("pixel_x", 32), 8: ("pixel_x", -32)}


VENTS = ("/obj/machinery/atmospherics/components/unary/vent_pump", "/obj/machinery/atmospherics/components/unary/vent_scrubber")
FLOOR_ONLY = ("/obj/effect/turf_decal", "/obj/machinery/atmospherics/pipe", "/obj/structure/cable", "/obj/effect/landmark",
              "/obj/structure/disposalpipe", "/obj/effect/decal/cleanable")


def carve_pens(plan):
    """Slime pens along one wall of each xenobiology lab, as the stock maps have them: 3x3 cells side by side, reinforced
    walls between, a reinforced window front with a windoor in the middle, and an aisle in front to work from. The
    corpus furnishes objects only, so without this the pens' walls never came and the slimes roamed the lab (and
    Robotics next door). Changes the plan in place; returns [(windoor tile, inward step, interior tiles)] per pen."""
    pens = []
    doors = set(plan.doors)
    for rid in [r for r in plan.rooms if base_id(r) == "xeno"]:
        R = {p for p, r in plan.floor.items() if r == rid}
        best = None
        for n in (4, 3, 2):
            L = 4 * n + 1
            for b in CARD:          # b: from the pens' back row out through the back wall
                bx, by = DELTA[b]
                for a in CARD:
                    if a in (b, OPP[b]) or best:
                        continue
                    ax, ay = DELTA[a]
                    # flush first: the end pen's outer wall is the lab's own side wall (no doubled wall)
                    cands = [((s[0] - ax, s[1] - ay), 1) for s in sorted(R)
                             if all((s[0] - ax - j * bx, s[1] - ay - j * by) not in R for j in range(5))]
                    cands += [(s, 0) for s in sorted(R)]
                    for s, flush in cands:
                        def tile(i, j, s=s, ax=ax, ay=ay, bx=bx, by=by):
                            return (s[0] + i * ax - j * bx, s[1] + i * ay - j * by)
                        rect = [tile(i, j) for i in range(flush, L) for j in range(4)]
                        if not all(q in R for q in rect) or not all(tile(i, 4) in R for i in range(flush, L)):
                            continue
                        if any((tile(i, 0)[0] + bx, tile(i, 0)[1] + by) in R for i in range(flush, L)):
                            continue        # the back row has to be against the room's wall
                        if any((q[0] + DELTA[d][0], q[1] + DELTA[d][1]) in doors for q in rect for d in CARD):
                            continue
                        rest = R - set(rect)
                        if len(rest) < 40:
                            continue
                        seen, todo = set(), [next(iter(rest))]
                        while todo:
                            q = todo.pop()
                            if q in seen:
                                continue
                            seen.add(q)
                            todo += [(q[0] + DELTA[d][0], q[1] + DELTA[d][1]) for d in CARD
                                     if (q[0] + DELTA[d][0], q[1] + DELTA[d][1]) in rest]
                        if len(seen) != len(rest):
                            continue
                        best = (n, b, tile)
                        break
            if best:
                break
        if not best:
            continue
        n, b, tile = best
        plan.rooms.setdefault("xeno_pens", {"kind": "room", "dept": "science", "label": "slime pens"})
        inward = (DELTA[b][0], DELTA[b][1])
        for k in range(n):
            inside = []
            for i in range(4 * k, 4 * k + 5):
                for j in range(4):
                    q = tile(i, j)
                    if q not in R and q not in plan.floor:
                        continue        # the lab's own side wall, already there
                    if i in (4 * k, 4 * k + 4):
                        plan.floor.pop(q, None)
                        plan.walls.add(q)
                        plan.rwall.add(q)
                    elif j == 3 and i != 4 * k + 2:
                        plan.floor.pop(q, None)
                        plan.walls.add(q)
                        plan.rwall.add(q)
                        plan.glass.add(q)
                    else:
                        plan.floor[q] = "xeno_pens"
                        if j < 3:
                            inside.append(q)
            pens.append((tile(4 * k + 2, 3), inward, inside))
    return pens


def fit_pens(m, pens, T):
    """The pens' windoors (Xenobiology access), and the lab's slimes moved into the first pen, two of a colour so the
    line carries on."""
    if not pens:
        return []
    slimes = []
    for (x, y, z), t in m.tiles.items():
        if t.apath.startswith("/area/science/xenobiology"):
            keep = [o for o in t.objs if not o.path.startswith("/mob/living/simple_animal/slime")]
            slimes += [o for o in t.objs if o.path.startswith("/mob/living/simple_animal/slime")]
            t.objs = keep
    for door, inward, inside in pens:
        d = {(0, 1): 1, (0, -1): 2, (1, 0): 4, (-1, 0): 8}[inward]
        m.get(*T(door)).objs.append(dmm.Atom("/obj/machinery/door/window/northleft",
                                             [("dir", str(d)), ("name", '"Containment Pen"'), ("req_access_txt", '"55"')]))
    first = [T(q) for q in pens[0][2]]
    mid = sorted(first)[len(first) // 2]
    for _ in range(max(2, len(slimes))):
        m.get(*mid).objs.append(dmm.Atom("/mob/living/simple_animal/slime"))
    return ["slime pens: %d with windoors, %d slimes in the first" % (len(pens), max(2, len(slimes)))]


def fill_ward(m, tiles):
    """A big treatment room's open middle: two rows of roller beds with drips between, an aisle down the middle and
    a tile's walk all round, as Meta and Box lay out their wards. Furnishing hugs the walls, so without this the
    middle of a big ward is bare floor."""
    from forge import kit
    tiles = set(tiles)

    def free(p):
        t = m.get(*p)
        return p in tiles and t is not None and t.tpath.startswith("/turf/open") and \
            all(o.path.startswith(FLOOR_ONLY + VENTS) for o in t.objs)

    def vent(p):
        return any(o.path.startswith(VENTS) for o in m.get(*p).objs)
    core = {p for p in tiles if all(free((p[0] + dx, p[1] + dy)) for dx in (-1, 0, 1) for dy in (-1, 0, 1))}
    # the biggest full rectangle inside the core
    best = None
    for (x0, y0) in core:
        for w in range(3, 12):
            if (x0 + w - 1, y0) not in core:
                break
            for h in range(3, 6):       # an aisle of three at most between the rows
                if not all((x, y0 + h - 1) in core for x in range(x0, x0 + w)):
                    break
                if best is None or w * h > best[2] * best[3]:
                    best = (x0, y0, w, h)
    if best is None or best[2] * best[3] < 12:
        return []
    x0, y0, w, h = best
    rows = (y0, y0 + h - 1) if h >= 3 else (y0,)
    n = 0
    for y in rows:
        for x in range(x0, x0 + w):
            k = (x - x0) % 3
            if k == 2 or vent((x, y)):
                continue        # a gap every third tile to step between the beds
            path = "/obj/structure/bed/roller" if k == 0 else "/obj/machinery/iv_drip"
            m.get(x, y).objs.append(dmm.Atom(path))
            n += 1
    return ["ward: %d beds and drips in a %dx%d block at %d,%d" % (n, w, h, x0, y0)]


# what a firelock may share a tile with: under-floor runs, decals, vents, and wall-hung things (lights hang by dir)
HALL_FD_OK = FLOOR_ONLY + VENTS + ("/obj/machinery/navbeacon", "/obj/effect", "/obj/machinery/light")


def fit_hall_firelocks(m, zone, target=55):
    """Firelock lines across the halls, as stock maps split them: MetaStation has 36 lines over 1732 hall tiles (one
    every 7-12 tiles of corridor, full width, wall to wall), so a fire or a breach shuts off one stretch. The generator
    only put firelocks in doorways, so one opened plasma canister burned the whole hall (2026-11-16 shift batch: 8 dead
    in 3 seconds). Cuts go where the hall is a plain corridor (walls at both ends of the line, hall on both sides of
    it), each one splitting the biggest stretch left as evenly as it can, until none is over `target` tiles."""
    def t(p):
        return m.get(p[0], p[1])

    def hall(p):
        tt = t(p)
        return tt is not None and p in zone and tt.apath.startswith("/area/hallway") and tt.tpath.startswith("/turf/open") \
            and not tt.has("/obj/machinery/door")

    def solid(p):
        tt = t(p)
        return tt is not None and (tt.tpath.startswith("/turf/closed") or tt.has("/obj/structure/window") or
                                   tt.has("/obj/structure/grille"))

    def mounted(o):
        return abs(o.num("pixel_x")) >= 20 or abs(o.num("pixel_y")) >= 20

    def clear(p):
        return all(o.path.startswith(HALL_FD_OK) or mounted(o) for o in t(p).objs)
    halls = {p for p in zone if hall(p)}
    # candidate cuts: a full-width line across a straight stretch (2..7 wide)
    cuts = []
    for p in halls:
        for along, across in (((0, 1), (1, 0)), ((1, 0), (0, 1))):
            back = (p[0] - across[0], p[1] - across[1])
            if back in halls or not solid(back):
                continue        # start each line at its wall
            line = [p]
            q = (p[0] + across[0], p[1] + across[1])
            while q in halls and len(line) <= 7:
                line.append(q)
                q = (q[0] + across[0], q[1] + across[1])
            if not 2 <= len(line) <= 7 or not solid(q):
                continue
            if not all(clear(c) for c in line):
                continue
            if not all((c[0] + s * along[0], c[1] + s * along[1]) in halls for c in line for s in (1, -1)):
                continue        # not at a junction's mouth or against a door
            cuts.append(tuple(line))
    blocked = {p for p in halls if t(p).has("/obj/machinery/door/firedoor")}

    def parts(tiles, cut=()):
        cs = set(cut)
        left, out = set(tiles) - cs, []
        while left:
            s = left.pop()
            comp, st = {s}, [s]
            while st:
                a = st.pop()
                for d in D4.values():
                    b = (a[0] + d[0], a[1] + d[1])
                    if b in left:
                        left.discard(b)
                        comp.add(b)
                        st.append(b)
            out.append(comp)
        return out
    todo = parts(halls - blocked)
    done, chosen = [], []
    while todo:
        big = todo.pop()
        if len(big) <= target:
            done.append(big)
            continue
        best, loop = None, None
        shut = [k for line in chosen for k in line] + list(blocked)
        for cut in cuts:
            if not all(c in big for c in cut):
                continue
            if any(abs(c[0] - k[0]) + abs(c[1] - k[1]) < 4 for line in chosen for k in line for c in cut):
                continue        # two lines side by side
            ps = parts(big, cut)
            if len(ps) == 1:
                # a loop (a ring hall, the hub round the core): one line doesn't split it. Remember the line farthest
                # from any other firelock, to open the loop if nothing splits
                far = min((abs(cut[0][0] - k[0]) + abs(cut[0][1] - k[1]) for k in shut), default=999)
                if loop is None or far > loop[0]:
                    loop = (far, cut, ps)
                continue
            if min(len(x) for x in ps) < 12:
                continue        # a cut that only shuts off a dead end
            score = max(len(x) for x in ps)
            if best is None or score < best[0]:
                best = (score, cut, ps)
        best = best or loop
        if best is None:
            done.append(big)
            continue
        _, cut, ps = best
        chosen.append(cut)
        todo += ps
    comps = done
    for cut in chosen:
        for c in cut:
            t(c).objs.insert(0, dmm.Atom(kit.FIREDOOR))
    biggest = max((len(c) for c in comps), default=0)
    return ["hall firelocks: %d lines (%d tiles) over %d hall tiles, biggest stretch left %d" %
            (len(chosen), sum(len(c) for c in chosen), len(halls), biggest)]


# ------------------------------------------------------------------ the supermatter engine
# MetaStation's engine block, taken whole: the core x162..180 y147..161 (the crystal's chamber, the gas loop with its
# filters and pumps, the emitter room, its hull wall on the south side) and the heat-exchange coil out in space below
# it. Stamp coordinates: u = x - 162 (along the hull), v = y - 147 (into the room); v = 0 is the hull wall. Rotated
# only, never mirrored (the filters are flipped ones). The parts of Meta round it are not taken: the freezer room
# north of the core becomes two rows of loop in front of it (u 5..9, v 15..16), the waste line that ran north to an
# injector in space is piped round to the nearest hull wall, and the walkway west of the core (u = -1) stays floor.
META_ENGINE = (162, 147)
ENGINE_CORE = [(u, v) for u in range(18) for v in range(15)]    # u 18 is Meta's space past its east wall: not taken
ENGINE_NOOK = [(u, v) for u in range(5, 10) for v in (15, 16)]
ENGINE_CABLES = [(-1, 7), (9, 17)]    # the collectors' line out of the west door; the emitters' feed up the loop
_ENGINE = None


def engine_block():
    """{(u, v): (turf atom, area path, [atoms])} of Meta's engine, with what does not come along taken out."""
    global _ENGINE
    if _ENGINE is not None:
        return _ENGINE
    m = dmm.read(os.path.join(ROOT, "_maps", "map_files", "MetaStation", "MetaStation.dmm"))
    x0, y0 = META_ENGINE

    def keep(o, area):
        p = o.path
        if p.startswith("/obj/structure/disposalpipe") or "/supply/hidden" in p or "/scrubbers/hidden" in p:
            return False        # the station's own networks passing through
        if "/unary/vent_" in p and area != "/area/engine/supermatter":
            return False        # the station's vents in the walkways: the builder vents the room
        return not p.startswith("/obj/machinery/power/apc")
    cells = {}
    for u, v in ENGINE_CORE:
        t = m.tiles[(x0 + u, y0 + v, 1)]
        cells[(u, v)] = [t.turf, t.apath, [o for o in t.objs if keep(o, t.apath)]]
    # the coil, out in space (its lattice and catwalks with it; Meta's security post beside it stays behind)
    for u in range(6, 21):
        for v in range(-6, 0):
            t = m.tiles[(x0 + u, y0 + v, 1)]
            if t.tpath.startswith("/turf/open/space"):
                # the coil only: Meta's other line out here (orange, to its atmos) would dangle cut off
                cells[(u, v)] = [t.turf, "/area/space/nearstation",
                                 [o for o in t.objs if "/atmospherics/" not in o.path or "heat_exchanging" in o.path]]
    # the hull wall: Meta's maint door at 164,147 opens onto its security post; here it would open onto space
    cells[(2, 0)] = [dmm.Atom("/turf/closed/wall/r_wall"), "/area/engine/engineering", []]
    # "Atmos to Loop" fed the loop from Meta's atmos line through the hull; here a canister port does
    cells[(4, 0)][2] = [o for o in cells[(4, 0)][2] if "/pipe/" not in o.path]
    cells[(4, 1)][2] = [o for o in cells[(4, 1)][2] if "/binary/pump" not in o.path] + \
        [dmm.Atom("/obj/machinery/atmospherics/components/unary/portables_connector/visible", [("dir", "1")])]
    # the freezers' loop, closed in two rows (Meta's room round it, its connectors and doors left out)
    for u, v in ENGINE_NOOK:
        t = m.tiles[(x0 + u, y0 + v, 1)]
        objs = []
        for o in t.objs:
            if not (o.path.startswith(("/obj/machinery/atmospherics/pipe/simple/general", "/obj/machinery/meter",
                                       "/obj/machinery/atmospherics/components/unary/thermomachine")) or
                    (o.path == "/obj/structure/cable" and u == 9)):
                continue
            objs.append(o)
        if (u, v) == (6, 16):       # the manifold up to a connector: a straight run now
            objs.append(dmm.Atom("/obj/machinery/atmospherics/pipe/simple/general/visible", [("dir", "4")]))
        if (u, v) in ((7, 16), (8, 16)):    # four-way to the connectors above: closed on that side
            objs.append(dmm.Atom("/obj/machinery/atmospherics/pipe/manifold/general/visible", [("dir", "1")]))
        cells[(u, v)] = [dmm.Atom("/turf/open/floor/plasteel/dark"), "/area/engine/engineering", objs]
    _ENGINE = cells
    return cells


def rot_engine_atom(o, k):
    """An atom turned k quarter turns clockwise. Everything that faces gets its dir turned (pipes, pumps and filters
    face south when they have no dir); smart cables, lattice and loose things only move their offsets."""
    from forge import furnish
    vs = [(n, v) for n, v in o.vars if n not in ("dir", "pixel_x", "pixel_y")]
    plain = o.path.startswith(("/obj/structure/cable", "/obj/structure/lattice", "/obj/effect/spawner",
                               "/obj/effect/landmark", "/obj/item", "/turf/"))
    if o.get("dir") is not None or not plain:
        nd = furnish.rot_dir(o.num("dir", 2), k)
        if nd != 2:
            vs.append(("dir", str(nd)))
    px, py = furnish.rot_xy(o.num("pixel_x"), o.num("pixel_y"), k)
    if px:
        vs.append(("pixel_x", str(px)))
    if py:
        vs.append(("pixel_y", str(py)))
    return dmm.Atom(o.path, vs)


def plan_engine(room, walls, doors, taken, W, H):
    """Where the block goes in the engine room: (k, origin, map of (u, v) -> tile), or None. The hull wall row lies
    on the room's own hull wall with space for the coil behind it, the core and the freezer rows fit in the room with
    the walkway and a row in front, every door of the room still opens onto floor, and that floor is one piece."""
    from forge import furnish
    cells = engine_block()
    room = set(room)
    foot = set(ENGINE_CORE) | set(ENGINE_NOOK)

    def at(o, k, u, v):
        du, dv = furnish.rot_xy(u, v, k)
        return (o[0] + du, o[1] + dv)
    inner = {}
    for d in doors:
        for e in CARD:
            q = (d[0] + DELTA[e][0], d[1] + DELTA[e][1])
            if q in room:
                inner[d] = q
    if not inner:
        return None
    for k in range(4):
        for o in sorted(walls):
            if at(o, k, 0, 1) not in room:
                continue
            need_floor = [(u, v) for u in range(-1, 18) for v in range(1, 18)]
            if not all(at(o, k, u, v) in room for u, v in need_floor):
                continue
            if not all(at(o, k, 18, v) in room or at(o, k, 18, v) in walls for v in range(1, 15)):
                continue
            if not all(at(o, k, u, 0) in walls and at(o, k, u, 0) not in doors for u in range(-1, 18)):
                continue
            space = [uv for uv in cells if uv[1] < 0] + [(-1, -1)]
            if not all(at(o, k, u, v) not in taken and 2 <= at(o, k, u, v)[0] <= W - 1 and
                       2 <= at(o, k, u, v)[1] <= H - 1 for u, v in space):
                continue
            ft = {at(o, k, u, v) for u, v in foot}
            if any(q in ft for q in inner.values()):
                continue
            rest = room - ft
            start = next(iter(inner.values()))
            seen, st = {start}, [start]
            while st:
                a = st.pop()
                for e in CARD:
                    b = (a[0] + DELTA[e][0], a[1] + DELTA[e][1])
                    if b in rest and b not in seen:
                        seen.add(b)
                        st.append(b)
            if len(seen) != len(rest):
                continue
            return k, o, {uv: at(o, k, *uv) for uv in list(cells) + [(-1, v) for v in range(18)] +
                          [(u, 17) for u in range(-1, 18)] + [(u, v) for u in range(-1, 18) for v in range(15, 18)]}
    return None


def route_engine_waste(place, room, walls, doors, taken):
    """The waste line from the core's north wall (u 11, v 14) over the room floor to the nearest hull wall, and the
    injector in space past it: [tiles from the first floor tile to the wall], injector tile; or None."""
    k, o, at = place
    foot = {at[uv] for uv in set(ENGINE_CORE) | set(ENGINE_NOOK)}
    start = at[(11, 15)]
    coil = {at[uv] for uv in engine_block() if uv[1] < 0}
    free = set(room) - foot
    prev, seen, queue = {}, {start}, [start]
    end = None
    while queue and end is None:
        nxt = []
        for a in queue:
            for e in CARD:
                h = (a[0] + DELTA[e][0], a[1] + DELTA[e][1])
                s = (h[0] + DELTA[e][0], h[1] + DELTA[e][1])
                if h in walls and h not in doors and h not in foot and s not in taken and s not in coil:
                    end = (a, h, s)
                    break
            if end:
                break
            for e in CARD:
                b = (a[0] + DELTA[e][0], a[1] + DELTA[e][1])
                if b in free and b not in seen and b not in doors:
                    seen.add(b)
                    prev[b] = a
                    nxt.append(b)
        queue = sorted(nxt)
    if end is None:
        return None
    a, h, s = end
    path = [a]
    while path[-1] != start:
        path.append(prev[path[-1]])
    path.reverse()
    return path + [h], s


def paste_engine(m, place, waste, area):
    """The block into the built map: Meta's tiles turned to fit, the waste line and its injector, and a tank
    dispenser (plasma for the emitters' room) on the walkway's far end."""
    k, o, at = place
    amap = {"/area/engine/engineering": area, "/area/maintenance/starboard": area}
    for uv, (turf, ar, objs) in engine_block().items():
        t = m.get(*at[uv])
        t.turf = rot_engine_atom(turf, k) if turf.get("dir") else dmm.Atom(turf.path, list(turf.vars))
        t.area = dmm.Atom(amap.get(ar, ar))
        t.objs = [rot_engine_atom(a, k) for a in objs]
    path, inj = waste
    core_wall = at[(11, 14)]
    seq = [core_wall] + path + [inj]
    bit = {(0, 1): 1, (0, -1): 2, (1, 0): 4, (-1, 0): 8}
    for i in range(1, len(seq) - 1):
        p = seq[i]
        mk = bit[(seq[i - 1][0] - p[0], seq[i - 1][1] - p[1])] | bit[(seq[i + 1][0] - p[0], seq[i + 1][1] - p[1])]
        d = {3: 2, 12: 4}.get(mk, mk)
        m.get(*p).objs.append(dmm.Atom("/obj/machinery/atmospherics/pipe/simple/scrubbers/visible",
                                       [("dir", str(d))] if d != 2 else []))
    t = m.get(*inj)
    d = bit[(seq[-2][0] - inj[0], seq[-2][1] - inj[1])]
    t.turf = dmm.Atom("/turf/open/floor/plating/airless")
    t.area = dmm.Atom(area)      # powered: an injector in a space area never runs
    t.objs = [dmm.Atom("/obj/machinery/atmospherics/components/unary/outlet_injector/atmos/engine_waste",
                       [("dir", str(d))] if d != 2 else [])]
    # the plasma the emitter room's canisters and the engineers' tanks come from, by the walkway
    for v in (16, 17, 15):
        p = at[(-1, v)]
        if p not in path and all(a.path.startswith(FLOOR_ONLY + VENTS) for a in m.get(*p).objs):
            m.get(*p).objs.append(dmm.Atom("/obj/structure/tank_dispenser"))
            break
    return ["engine: MetaStation's supermatter block turned %d, origin %d,%d; waste line %d tiles to an injector at %d,%d"
            % (k * 90, o[0], o[1], len(path), inj[0], inj[1])]


def maint_corridor(area):
    """The maint run itself (not a department maint room, the solars or disposals)."""
    return area.startswith("/area/maintenance/") and not area.startswith(
        ("/area/maintenance/department", "/area/maintenance/solars", "/area/maintenance/disposal"))


# MetaStation's maint, counted (2026-11-16): per 10 open tiles about 1.5 dense things against the walls (racks,
# crates, closets, tables, tanks, heaters, emergency closets, girders) and 0.7 loot spawners, with cigarette butts,
# dirt, cobwebs in the corners and contraband posters. (weight, base atom, what goes on or in it)
MAINT_DENSE = [(50, "/obj/structure/rack", "loot"), (29, "/obj/structure/closet/crate", "loot"),
               (26, "/obj/structure/closet", "loot"), (28, "/obj/structure/table", "top"),
               (22, "/obj/structure/reagent_dispensers/watertank", None),
               (16, "/obj/structure/reagent_dispensers/fueltank", None), (30, "/obj/machinery/space_heater", None),
               (14, "/obj/structure/closet/emcloset", None), (13, "/obj/structure/closet/firecloset", None),
               (10, "/obj/structure/girder", None)]
MAINT_TOP = ["/obj/effect/spawner/lootdrop/maintenance", "/obj/effect/spawner/lootdrop/maintenance", "/obj/item/cigbutt",
             "/obj/item/storage/box/lights/mixed", "/obj/item/flashlight", "/obj/item/clothing/mask/gas",
             "/obj/item/reagent_containers/food/drinks/drinkingglass", "/obj/item/extinguisher"]


# What hangs on a wall face, by rank: the lower rank stays and anything ranked after it on the same face moves along
# the wall. An APC sits on its cable terminal and never moves; the plumbing (sink with its mirror, urinal, toilet,
# shower) is placed by the function review and stays; then alarms and buttons, the light, the wall boxes, signs.
FACE_RANKS = [
    (0, ("/obj/machinery/power/apc",)),
    (1, ("/obj/structure/sink", "/obj/structure/mirror", "/obj/structure/urinal", "/obj/structure/toilet", "/obj/machinery/shower")),
    (2, ("/obj/machinery/airalarm", "/obj/machinery/firealarm", "/obj/machinery/light_switch", "/obj/machinery/button",
         "/obj/machinery/requests_console", "/obj/machinery/keycard_auth", "/obj/machinery/door_timer")),
    (3, ("/obj/machinery/light",)),
    (4, ("/obj/structure/extinguisher_cabinet", "/obj/machinery/newscaster", "/obj/item/radio/intercom",
         "/obj/machinery/status_display", "/obj/structure/noticeboard", "/obj/machinery/defibrillator_mount",
         "/obj/machinery/vending/wallmed", "/obj/machinery/flasher", "/obj/structure/fireaxecabinet",
         "/obj/machinery/computer/security/telescreen")),
    (5, ("/obj/structure/sign",)),
]


def face_rank(o):
    if o.path.startswith(("/obj/machinery/light/floor", "/obj/structure/sign/barsign")):
        return None
    for r, pres in FACE_RANKS:
        if o.path.startswith(pres):
            return r
    return None


def face_side(o):
    """The wall a piece hangs on: a light and a shower by their dir (a shower faces away from its wall), a toilet by
    which way it faces, the rest by their pixel offset."""
    if o.path.startswith("/obj/machinery/light"):
        return o.num("dir", 2) or 2
    if o.path.startswith("/obj/machinery/shower"):
        return OPP[o.num("dir", 2) or 2]
    if min(abs(o.num("pixel_x")), abs(o.num("pixel_y"))) >= 16:
        return None     # hung across a corner (an intercom up in the corner): left where it is
    from forge import function as F
    s = F.wall_side_of(o)
    if s:
        return s
    px, py = o.num("pixel_x"), o.num("pixel_y")
    if max(abs(px), abs(py)) < 16 or min(abs(px), abs(py)) >= 16:
        return None     # not hung, or hung across a corner (an intercom up in the corner): left where it is
    return (1 if py > 0 else 2) if abs(py) >= abs(px) else (4 if px > 0 else 8)


def one_per_wall_face(m, zone, keep=frozenset()):
    """One thing per wall face. Lights, urinals, mirrors, posters and alarms were each placed by their own step, and
    nothing stopped two of them landing on the same bit of wall: a light tube behind a urinal, a fire alarm over a
    toilet, a poster through a urinal (the user's restroom, 2026-11-16). The stock maps never stack them. The
    lower-ranked piece moves along the same wall in the same room to the nearest free face, preferring a tile with
    nothing on its other walls (an inside corner holding two pieces reads as a pile too); a sign or wall box with
    nowhere to go is dropped, a light only if its room keeps another one. A sink on a shower's tile moves off it."""
    zone = set(zone)
    WET = ("/obj/structure/sink", "/obj/structure/urinal", "/obj/structure/toilet")

    def t(p):
        return m.get(p[0], p[1])

    def pieces(p):
        out = []
        for o in t(p).objs:
            r = face_rank(o)
            if r is not None:
                s = face_side(o)
                if s:
                    out.append((r, s, o))
        return out

    def wall_at(p, s):
        q = (p[0] + DELTA[s][0], p[1] + DELTA[s][1])
        tq = t(q)
        return tq is not None and tq.tpath.startswith("/turf/closed") and not tq.has("/obj/machinery/door")

    def floor_ok(p):
        tp = t(p)
        return tp is not None and p in zone and p not in keep and tp.tpath.startswith("/turf/open") \
            and not tp.tpath.startswith("/turf/open/space") and not tp.has("/obj/machinery/door")

    def taken(p, s, o):
        if any(s2 == s for _, s2, o2 in pieces(p) if o2 is not o):
            return True
        # the wall tile already carries something hung from another side (both faces of one wall read as one pile)
        w = (p[0] + DELTA[s][0], p[1] + DELTA[s][1])
        for d, dl in DELTA.items():
            r = (w[0] + dl[0], w[1] + dl[1])
            if r != p and t(r) is not None and t(r).tpath.startswith("/turf/open") and \
                    any(s2 == OPP[d] for _, s2, o2 in pieces(r) if o2 is not o):
                return True
        return False

    def usable(q, s, o, area, floor_piece):
        if not floor_ok(q) or t(q).apath != area or not wall_at(q, s) or taken(q, s, o):
            return False
        return not (floor_piece and (kit.dense(t(q).objs) or t(q).has("/obj/machinery/shower") or
                                     any(a.path.startswith(WET) for a in t(q).objs)))

    def spot_for(p, s, o, floor_piece):
        perp = (DELTA[s][1], DELTA[s][0])
        area = t(p).apath
        best = None
        for k in range(1, 7):
            for sg in (1, -1):
                q = (p[0] + sg * k * perp[0], p[1] + sg * k * perp[1])
                if not usable(q, s, o, area, floor_piece):
                    continue
                if not pieces(q):
                    return q, s
                best = best or (q, s)
        if best or floor_piece or o.path.startswith(("/obj/structure/mirror", "/obj/structure/sign")):
            return best
        # an alarm, light or wall box can go on any wall of its room: the nearest free face, turned to that wall
        cands = []
        for q in zone:
            if t(q) is None or t(q).apath != area or abs(q[0] - p[0]) + abs(q[1] - p[1]) > 12:
                continue
            for s2 in CARD:
                if usable(q, s2, o, area, False):
                    # a tile with something already on another of its walls (an inside corner) only if nothing else
                    crowd = len(pieces(q)) + sum(1 for o2 in t(q).objs if o2.path.startswith(("/obj/item/twohanded/required/kirbyplants", "/obj/structure/flora")))
                    cands.append((abs(q[0] - p[0]) + abs(q[1] - p[1]) + 8 * crowd, q, s2))
        if not cands:
            return None
        _, q, s2 = min(cands)
        return q, s2

    def turn(o, s_from, s_to):
        """Rehang a wall piece on another wall: its dir and pixel offset follow the wall."""
        if s_from == s_to:
            return
        if o.path.startswith("/obj/machinery/light"):
            o.vars = [kv for kv in o.vars if kv[0] != "dir"] + [("dir", str(s_to))]
            return
        px, py = o.num("pixel_x"), o.num("pixel_y")
        off = max(abs(px), abs(py))
        dx, dy = DELTA[s_to]
        vs = [kv for kv in o.vars if kv[0] not in ("pixel_x", "pixel_y", "dir")]
        if dx:
            vs.append(("pixel_x", str(dx * off)))
        if dy:
            vs.append(("pixel_y", str(dy * off)))
        if any(kv[0] == "dir" for kv in o.vars) or face_rank(o) == 2:
            # alarms and buttons face out of their wall (default dir 2 is the north wall's)
            vs.append(("dir", str(OPP[s_to])))
        o.vars = vs

    moved = dropped = 0
    notes = []
    for p in sorted(zone):
        tp = t(p)
        if tp is None or p in keep or not tp.has("/obj/machinery/shower") or not tp.has("/obj/structure/sink"):
            continue
        area = tp.apath
        if sum(1 for z in zone if t(z) and t(z).apath == area and t(z).has("/obj/machinery/shower")) > 1:
            tp.objs = [o for o in tp.objs if not o.path.startswith("/obj/machinery/shower")]
            dropped += 1
            notes.append("dropped shower at %d,%d (a sink stands there; the row keeps the others)" % p)
    for p in sorted(zone):
        tp = t(p)
        if tp is None or p in keep or not tp.tpath.startswith("/turf/open"):
            continue
        by_side = {}
        for r, s, o in pieces(p):
            by_side.setdefault(s, []).append((r, o))
        losers = []
        for s, lst in by_side.items():
            # a toilet or shower stays put before a sink or urinal, which hang on the wall and move more easily
            lst.sort(key=lambda ro: (ro[0], 0 if ro[1].path.startswith(("/obj/structure/toilet", "/obj/machinery/shower")) else 1))
            top = lst[0][0]
            for r, o in lst[1:]:
                # a mirror over its sink is one piece, as on the stock maps
                if o.path.startswith("/obj/structure/mirror") and any(a.path.startswith("/obj/structure/sink") for _, a in lst):
                    continue
                if r == 0:
                    continue      # two APCs: never moved here
                losers.append((s, o))     # plumbing on plumbing too: the second one moves along the wall
        if tp.has("/obj/machinery/shower"):
            for o in tp.objs:
                if o.path.startswith("/obj/structure/sink"):
                    s = face_side(o)
                    if s:
                        losers.append((s, o))
                        losers += [(s, a) for a in tp.objs if a.path.startswith("/obj/structure/mirror") and face_side(a) == s]
        for s, o in losers:
            if o not in tp.objs:
                continue
            got = spot_for(p, s, o, o.path.startswith(WET + ("/obj/machinery/shower",)))
            if got:
                q, s2 = got
                tp.objs.remove(o)
                turn(o, s, s2)
                t(q).objs.append(o)
                moved += 1
                notes.append("%s %d,%d -> %d,%d (its wall face was taken)" % (o.path.rsplit("/", 1)[-1], p[0], p[1], q[0], q[1]))
                continue
            r = face_rank(o)
            if r == 1 and not o.path.startswith("/obj/structure/mirror"):
                # plumbing with nowhere to go: dropped only where the room keeps another of its kind
                kind = o.path.split("/")[3]
                if sum(1 for z in zone if t(z) and t(z).apath == tp.apath and
                       any(a.path.split("/")[3:4] == [kind] for a in t(z).objs)) > 1:
                    tp.objs.remove(o)
                    tp.objs[:] = [a for a in tp.objs if not (a.path.startswith("/obj/structure/mirror") and face_side(a) == s and kind == "sink")]
                    dropped += 1
                    notes.append("dropped %s at %d,%d (its wall face was taken, the room has another)" % (kind, p[0], p[1]))
                continue
            if r >= 4 or o.path.startswith("/obj/structure/mirror") or (r == 3 and sum(1 for z in zone if t(z) and t(z).apath == tp.apath and
                                         t(z).has("/obj/machinery/light")) > 1):
                tp.objs.remove(o)
                dropped += 1
                notes.append("dropped %s at %d,%d (its wall face was taken, no free one near)" % (o.path.rsplit("/", 1)[-1], p[0], p[1]))
    notes.insert(0, "wall faces: %d pieces moved off a taken face, %d dropped" % (moved, dropped))
    return notes


NOT_ANCHOR = ("/obj/machinery/door", "/obj/machinery/atmospherics", "/obj/machinery/light", "/obj/structure/cable",
              "/obj/structure/disposalpipe", "/obj/machinery/navbeacon", "/obj/structure/lattice")
SEAT = ("/obj/structure/chair", "/obj/structure/bed")
QUARTER_SIDES = {1: (1, 8), 4: (1, 4), 2: (2, 4), 8: (2, 8)}    # tile decal dir -> the two sides it trims


def is_anchor(o):
    """Furniture standing on the tile (not a pipe, door, light or a wall piece hung over it)."""
    if o.path.startswith("/mob/living"):
        return True
    if not o.path.startswith(("/obj/structure", "/obj/machinery")) or o.path.startswith(NOT_ANCHOR):
        return False
    return abs(o.num("pixel_x")) < 16 and abs(o.num("pixel_y")) < 16


def wall_run(bd, rc, n, used, center=False):
    """Up to n free floor tiles of room rc in one straight line along a wall, off doors: canister rows, consoles."""
    m = bd.m
    tiles = set(p for p, r in bd.room.items() if r == rc and bd.is_floor(p) and bd.ch.get(p) == ".")
    def free(p):
        t = m.get(*p)
        if p in used or kit.dense(t.objs) or t.has("/obj/machinery/door"):
            return False
        if any(o.path.startswith(("/obj/effect/landmark", "/obj/machinery/atmospherics", "/obj/machinery/holopad",
                                  "/obj/machinery/navbeacon", "/obj/structure/disposalpipe")) for o in t.objs):
            return False
        # off every door, and two tiles off its mouth so the way in stays wide
        for d in CARD:
            q = bd.nb(p, d)
            if m.get(*q).has("/obj/machinery/door") or m.get(*bd.nb(q, d)).has("/obj/machinery/door"):
                return False
        return True
    best = []
    for d in CARD:
        line = {}
        for p in tiles:
            q = bd.nb(p, d)
            if free(p) and m.get(*q).tpath.startswith("/turf/closed"):
                key = p[1] if d in (1, 2) else p[0]
                line.setdefault(key, []).append(p)
        for key, ps in line.items():
            ps.sort(key=lambda p: p[0] if d in (1, 2) else p[1])
            run = [ps[0]]
            for p in ps[1:]:
                prev = run[-1]
                if abs(p[0] - prev[0]) + abs(p[1] - prev[1]) == 1:
                    run.append(p)
                else:
                    if len(run) > len(best):
                        best = run
                    run = [p]
            if len(run) > len(best):
                best = run
    if center and len(best) > n:
        s = (len(best) - n) // 2
        return best[s:s + n]
    return best[:n]


def fill_utility(m, bd, rc_of, used, put):
    """Rooms the corpus leaves bare that a crew still uses: the gas store, the AI core, the SMES room.
    2026-11-16 quad review: a 15x12 gas store held two tanks, the AI core was 14x11 of empty circuit floor."""
    notes = []
    # gas store: a canister of each gas on a bot decal along one wall, then the portable pump and scrubber
    rc = rc_of.get("tanks")
    if rc:
        gases = ["nitrogen", "oxygen", "toxins", "carbon_dioxide", "nitrous_oxide", "air", "air"]
        run = wall_run(bd, rc, len(gases), used, center=True)
        for p, g in zip(run, gases):
            put(p, "/obj/effect/turf_decal/bot")
            put(p, "/obj/machinery/portable_atmospherics/canister/" + g)
            used.add(p)
        run2 = wall_run(bd, rc, 4, used, center=True)
        for p, kind in zip(run2, ("pump", "pump", "scrubber", "scrubber")):
            put(p, "/obj/effect/turf_decal/bot")
            put(p, "/obj/machinery/portable_atmospherics/" + kind)
            used.add(p)
        notes.append("gas store: %d canisters, %d portables" % (len(run), len(run2)))
    # AI core: a turret in each corner of the room
    rc = rc_of.get("ai_core")
    if rc:
        tiles = [p for p, r in bd.room.items() if r == rc and bd.is_floor(p) and bd.ch.get(p) == "."]
        got = 0
        for p in tiles:
            t = m.get(*p)
            walls = [d for d in CARD if m.get(*bd.nb(p, d)).tpath.startswith("/turf/closed")]
            corner = any((a, b) in ((1, 4), (1, 8), (2, 4), (2, 8)) for a in walls for b in walls)
            if not corner or p in used or kit.dense(t.objs) or t.has("/obj/machinery/door") or \
                    any(o.path.startswith("/obj/effect/landmark") for o in t.objs) or \
                    any(m.get(*bd.nb(p, d)).has("/obj/machinery/door") for d in CARD):
                continue
            put(p, "/obj/machinery/porta_turret/ai")
            used.add(p)
            got += 1
        notes.append("AI core: %d corner turrets" % got)
    # SMES room: the power monitor console on a wall, cabled into the grid beside it
    rc = rc_of.get("smes")
    present = {o.path for p, r in bd.room.items() if r == rc for o in m.get(*p).objs} if rc else set()
    if rc and "/obj/machinery/computer/monitor" not in present:
        cand = wall_run(bd, rc, 30, used)
        def on_grid(q):
            return any(any(o.path == kit.CABLE for o in m.get(*bd.nb(q, d)).objs) for d in CARD)
        # on a wall by a cable; else anywhere off the doors by a cable (consoles may stand free); else on a wall
        cabled = [p for p in cand if on_grid(p)] or [p for p in free_tiles(bd, rc, 200, used) if on_grid(p)]
        p = (cabled or cand or [None])[0]
        if p:
            wall_d = next((d for d in CARD if m.get(*bd.nb(p, d)).tpath.startswith("/turf/closed")), 1)
            put(p, "/obj/machinery/computer/monitor", [("dir", str(OPP[wall_d]))])
            if not any(o.path == kit.CABLE for o in m.get(*p).objs):
                put(p, kit.CABLE)
            used.add(p)
            notes.append("SMES room: power monitor at %d,%d%s" % (p[0], p[1], "" if cabled else " (no cable beside it)"))
    for rc, rd in bd.roomdefs.items():
        if rd.get("area") == "/area/hippie/pool":
            notes.append(dig_pool(m, bd, rc, used))
    rc = rc_of.get("engine")
    if rc:
        notes.append(dress_engine(m, bd, rc, used, put))
    return notes


# MetaStation's engine room round the block (counted 2026-11-16): nitrogen for the cooling loop, radiation closets,
# mesons and geiger counters on racks, the alert console and the engineering console, fire and emergency closets
ENGINE_DRESS = [
    (4, [("/obj/effect/turf_decal/bot",), ("/obj/machinery/portable_atmospherics/canister/nitrogen",)]),
    (2, [("/obj/structure/closet/radiation",)]),
    (2, [("/obj/structure/rack",), ("/obj/item/clothing/glasses/meson/engine",), ("/obj/item/clothing/glasses/meson/engine",),
         ("/obj/item/geiger_counter",), ("/obj/item/geiger_counter",)]),
    (1, [("/obj/machinery/computer/station_alert", "face")]),
    (1, [("/obj/machinery/modular_computer/console/preset/engineering", "face")]),
    (1, [("/obj/structure/closet/firecloset",)]),
    (1, [("/obj/structure/closet/emcloset",)]),
]


def dress_engine(m, bd, rc, used, put):
    """The engine room floor outside the pasted supermatter block. The room has no corpus template (the block is
    the room), so on every seed 3-4 of its quarters were bare engine floor (2026-11-16 quad review). Each group
    goes along a wall outside the block, off its doors."""
    avoid = set(used) | set(getattr(bd, "engine_block", ())) | set(getattr(bd, "engine_pipe_fence", ()))
    got = 0
    for n, group in ENGINE_DRESS:
        run = wall_run(bd, rc, n, avoid, center=True)
        for p in run:
            for spec in group:
                vs = []
                if len(spec) > 1 and spec[1] == "face":
                    wall_d = next((d for d in CARD if m.get(*bd.nb(p, d)).tpath.startswith("/turf/closed")), 1)
                    vs = [("dir", str(OPP[wall_d]))]
                put(p, spec[0], vs)
            avoid.add(p)
            used.add(p)
            got += 1
    return "engine room: %d pieces round the block" % got


# yellow siding round a pool faces the water: N rim dir 2, S rim 1, W rim 4, E rim 8; corners NW 2, NE 8, SW 4, SE 1
SIDING = "/turf/open/floor/plasteel/yellowsiding"
POOL_SIZES = ((7, 5), (5, 7), (6, 4), (4, 6), (5, 4), (4, 5), (5, 3), (3, 5), (4, 3), (3, 4), (3, 3))
# holds the basin and its rim through the run: the furnisher and the vents keep off dense tiles
POOL_MARK = "/obj/effect/mapforge_pool"


def reserve_pools(bd):
    """Pick each pool room's basin before the run, so the builder lays its vents and pipes round it: dug after
    the run, the vents it had already put mid-room held a 12x11 room to a 5x3 pool."""
    notes, rect = [], {}
    for rc, rd in bd.roomdefs.items():
        if rd.get("area") != "/area/hippie/pool":
            continue
        tiles = {p for p, r in bd.room.items() if r == rc and bd.is_floor(p) and bd.ch.get(p) == "."}
        if not tiles:
            continue
        # off the way in: any tile beside a door, or beside floor that isn't this room's
        door = {p for p in tiles for d in CARD if bd.nb(p, d) not in tiles and
                (bd.t(*bd.nb(p, d)).has("/obj/machinery/door") or bd.kind(bd.nb(p, d)) == "floor")}
        xs, ys = [p[0] for p in tiles], [p[1] for p in tiles]
        cx, cy = (min(xs) + max(xs)) / 2.0, (min(ys) + max(ys)) / 2.0
        best = None
        for size, (w, h) in enumerate(POOL_SIZES):
            for x0 in range(min(xs) + 1, max(xs) - w + 1):
                for y0 in range(min(ys) + 1, max(ys) - h + 1):
                    # the rim plus a walkway tile all round, so the vents and the door have floor beyond it
                    ring = [(x, y) for x in range(x0 - 2, x0 + w + 2) for y in range(y0 - 2, y0 + h + 2)]
                    box = [(x, y) for x in range(x0 - 1, x0 + w + 1) for y in range(y0 - 1, y0 + h + 1)]
                    if any(p not in tiles or p in door for p in box) or \
                            sum(1 for p in ring if p in tiles) < len(box) + 4:
                        continue
                    key = (size, abs(x0 + (w - 1) / 2.0 - cx) + abs(y0 + (h - 1) / 2.0 - cy))
                    if best is None or key < best[0]:
                        best = (key, x0, y0, w, h)
        if not best:
            continue
        _, x0, y0, w, h = best
        rect[rc] = (x0, y0, w, h)
        for x in range(x0 - 1, x0 + w + 1):
            for y in range(y0 - 1, y0 + h + 1):
                bd.t(x, y).objs.append(dmm.Atom(POOL_MARK, [("density", "1")]))
        notes.append("pool: %dx%d basin held at %d,%d" % (w, h, x0, y0))
    bd.pool_rect = rect
    bd.pool_water = frozenset((x, y) for (x0, y0, w, h) in rect.values()
                              for x in range(x0, x0 + w) for y in range(y0, y0 + h))
    return notes


def dig_pool(m, bd, rc, used):
    """The pool room had no water. Dig Hippie's stock pool (7x5 at most) where it and its siding rim fit on the
    room's floor, clear of doors and start points, with filter, drain, ladder, diving board and the controller."""
    tiles = set(p for p, r in bd.room.items() if r == rc and bd.is_floor(p) and bd.ch.get(p) == ".")
    if not tiles:
        return "pool: no floor"
    # the corpus's pool room brings ladders, diving boards and drains with no water: they belong to the dig only
    FIXTURE = ("/obj/structure/pool", "/obj/machinery/drain", "/obj/machinery/poolfilter", "/obj/machinery/poolcontroller",
               POOL_MARK)
    # and sometimes a few tiles of its water and siding: back to the room's floor, one pool is dug below
    from collections import Counter
    wet_turf = ("/turf/open/pool", SIDING)
    plain = Counter(m.get(*p).tpath for p in tiles if not m.get(*p).tpath.startswith(wet_turf)).most_common(1)
    for p in tiles:
        t = m.get(*p)
        t.objs = [o for o in t.objs if not o.path.startswith(FIXTURE)]
        if plain and t.tpath.startswith(wet_turf):
            t.turf = dmm.Atom(plain[0][0])
    xs, ys = [p[0] for p in tiles], [p[1] for p in tiles]
    door = {p for p in tiles for d in CARD if m.get(*bd.nb(p, d)).has("/obj/machinery/door")}
    best = None
    held = getattr(bd, "pool_rect", {}).get(rc)
    if held:
        best = (None,) + held
    for size, (w, h) in enumerate(POOL_SIZES if not held else ()):
        for x0 in range(min(xs) + 1, max(xs) - w + 1):
            for y0 in range(min(ys) + 1, max(ys) - h + 1):
                water = [(x, y) for x in range(x0, x0 + w) for y in range(y0, y0 + h)]
                rim = [(x, y) for x in range(x0 - 1, x0 + w + 1) for y in range(y0 - 1, y0 + h + 1) if (x, y) not in water]
                # the room's vent and scrubber stay where they are, never under water (the rim is floor: they may stay there)
                # start points under the water move out after (used tiles of other kinds stay put)
                if any(p not in tiles or p in door or (p in used and not m.get(*p).has("/obj/effect/landmark"))
                       for p in water + rim) or \
                        any(m.get(*p).has("/obj/machinery/atmospherics/components") for p in water):
                    continue
                # no pipes drawn across the water (s3 2026-11-16) before size; then the biggest, least furniture
                # lost, nearest the middle
                pipes = sum(1 for p in water if m.get(*p).has("/obj/machinery/atmospherics"))
                cost = sum(1 for p in water + rim for o in m.get(*p).objs if is_anchor(o))
                cx, cy = x0 + w / 2.0, y0 + h / 2.0
                mid = abs(cx - (min(xs) + max(xs) + 1) / 2.0) + abs(cy - (min(ys) + max(ys) + 1) / 2.0)
                key = (pipes > 0, size, pipes, cost, mid)
                if best is None or key < best[0]:
                    best = (key, x0, y0, w, h)
    if not best:
        return "pool: room too small for a pool"
    _, x0, y0, w, h = best
    x1, y1 = x0 + w - 1, y0 + h - 1
    wet = {(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)}
    box = {(x, y) for x in range(x0 - 1, x1 + 2) for y in range(y0 - 1, y1 + 2)}
    dry = [p for p in sorted(tiles, key=lambda q: -min(abs(q[0] - x) + abs(q[1] - y) for x, y in box))
           if p not in box and p not in door and p not in used and not kit.dense(m.get(*p).objs)]
    for p in sorted(wet):
        for o in [o for o in m.get(*p).objs if o.path.startswith("/obj/effect/landmark")]:
            m.get(*p).objs.remove(o)
            if dry:
                q = dry.pop()
                m.get(*q).objs.append(o)
                used.add(q)
    KEEP = ("/obj/structure/cable", "/obj/machinery/atmospherics", "/obj/structure/disposalpipe", "/obj/effect/landmark",
            "/obj/machinery/light", "/obj/machinery/power/apc", "/obj/machinery/airalarm", "/obj/machinery/firealarm",
            "/obj/machinery/light_switch", "/obj/structure/extinguisher_cabinet", "/obj/machinery/newscaster",
            "/obj/item/radio/intercom", "/obj/structure/sign", "/obj/machinery/camera", "/obj/machinery/status_display")
    for x in range(x0 - 1, x1 + 2):
        for y in range(y0 - 1, y1 + 2):
            t = m.get(x, y)
            # nothing stands in the water or on its rim: furniture, decals, vents (a vent under water)
            t.objs = [o for o in t.objs if o.path.startswith(KEEP)]
            if x0 <= x <= x1 and y0 <= y <= y1:
                t.turf = dmm.Atom("/turf/open/pool")
                continue
            n, s, wv, e = y == y1 + 1, y == y0 - 1, x == x0 - 1, x == x1 + 1
            corner = (n or s) and (wv or e)
            d = 2 if n and not corner else 1 if s and not corner else 4 if wv and not corner else 8 if e and not corner else \
                2 if n and wv else 8 if n and e else 4 if s and wv else 1
            t.turf = dmm.Atom(SIDING + ("/corner" if corner else ""), [] if d == 2 else [("dir", str(d))])
    def add(p, path, vs=()):
        m.get(*p).objs.append(dmm.Atom(path, list(vs)))
        used.add(p)
    # as on the stock map: filter in the far corner, drain mid-pool, ladder at one end, board at the other,
    # controller on the rim beside the long side (the filter sits in the water: the stock pixel_y 18 hangs it on air)
    add((x0, y1), "/obj/machinery/poolfilter")
    add((x0 + w // 2, y0 + h // 2), "/obj/machinery/drain")
    add((x0, y0 + h // 2), "/obj/structure/pool/ladder")
    add((x1, y0 + h // 2), "/obj/structure/pool/Lboard")
    add((x1 + 1, y0 + h // 2), "/obj/structure/pool/Rboard")
    add((x0 + w // 2, y1 + 1), "/obj/machinery/poolcontroller")
    return "pool: %dx%d at %d,%d" % (w, h, x0, y0)


def tidy_rooms(m, zone, keep=frozenset()):
    """What the late passes leave behind when they move or drop furniture (the 2026-11-16 quad review, every room
    of the three seeds cut in quarters): a second chair or pet on the same tile, stools at no counter, potted plants
    in every corner, the full-tile colour that sat under a moved locker, and a template's grey work tile with its
    hazard edge in the middle of a white lab with nothing on it."""
    from collections import Counter
    notes = []
    # a pasted stock block (the supermatter engine) is left as its map has it: its chamber floor is plating and
    # engine floor on purpose
    allzone = set(zone)
    zone = allzone - set(keep)

    def t(p):
        return m.get(p[0], p[1])

    def floor(p):
        tt = t(p)
        return tt is not None and tt.tpath.startswith("/turf/open") and not tt.tpath.startswith("/turf/open/space") \
            and not tt.has("/obj/machinery/door/airlock") and not tt.has(kit.WINDOW) and not tt.has("/obj/structure/window")

    def room_tile(p):
        a = t(p).apath
        return not a.startswith(("/area/hallway", "/area/maintenance", "/area/solar", "/area/space"))
    # 1. the same thing twice on one tile, or two seats on one tile
    dup = 0
    for p in sorted(zone):
        tt = t(p)
        if tt is None:
            continue
        seen, keep, seat = set(), [], False
        for o in tt.objs:
            key = o.path
            # (slimes share a pen tile; two of one pet are a double)
            if not o.path.startswith(("/obj/item", "/obj/effect", "/obj/structure/cable", "/obj/machinery/atmospherics",
                                      "/mob/living/simple_animal/slime")):
                if key in seen or (o.path.startswith(SEAT) and seat and is_anchor(o)):
                    dup += 1
                    continue
                seen.add(key)
                if o.path.startswith(SEAT) and is_anchor(o):
                    seat = True
            keep.append(o)
        tt.objs = keep
    if dup:
        notes.append("tidy: %d doubled pieces taken off" % dup)
    # 1b. the tile straight through an airlock is the way in: a dispenser, locker or crate standing there moves to a
    # free wall tile of its room nearby, or goes (a pasted engine block put a tank dispenser in Engineering's door)
    moved = 0
    def door_near(q):
        return any(t(kit_nb(q, d)) is not None and t(kit_nb(q, d)).has("/obj/machinery/door") for d in CARD)
    for p in sorted(allzone):
        tt = t(p)
        if tt is None or not tt.has("/obj/machinery/door/airlock"):
            continue
        for d in CARD:
            q = kit_nb(p, d)
            tq = t(q)
            if tq is None or not floor(q) or tq.has("/obj/machinery/door"):
                continue
            block = [o for o in tq.objs if is_anchor(o) and kit.is_dense_atom(o) and not o.path.startswith("/mob")]
            if not block:
                continue
            spot = None
            for r in sorted(((q[0] + dx, q[1] + dy) for dx in range(-3, 4) for dy in range(-3, 4)),
                            key=lambda r: abs(r[0] - q[0]) + abs(r[1] - q[1])):
                tr = t(r)
                if r == q or r not in allzone or tr is None or not floor(r) or tr.apath != tq.apath or door_near(r) or \
                        any(is_anchor(o) for o in tr.objs) or tr.has("/obj/machinery/atmospherics/components") or \
                        not any(not floor(kit_nb(r, e)) and not t(kit_nb(r, e)).has("/obj/machinery/door") for e in CARD
                                if t(kit_nb(r, e)) is not None):
                    continue
                spot = r
                break
            for o in block:
                tq.objs.remove(o)
                if spot:
                    t(spot).objs.append(o)
                moved += 1
    if moved:
        notes.append("tidy: %d pieces moved out of airlock mouths" % moved)
    # 2. a stool stands at a counter, a table, a machine or a game; one out on the floor alone goes (rows and blocks
    # of stools are seating: the chapel's congregation)
    STOOL_AT = ("/obj/structure/table", "/obj/machinery/computer", "/obj/machinery/vending", "/obj/structure/piano",
                "/obj/machinery/smartfridge", "/obj/machinery/chem", "/obj/structure/displaycase", "/obj/machinery/computer/arcade",
                "/obj/machinery/slot_machine", "/obj/structure/sink", "/obj/machinery/rnd", "/obj/machinery/microwave")
    lone = 0
    for p in sorted(zone):
        tt = t(p)
        if tt is None or not room_tile(p) or t(p).apath in FILLER_AREAS:
            continue
        for o in [o for o in tt.objs if o.path.startswith("/obj/structure/chair/stool")]:
            near = [t((p[0] + dx, p[1] + dy)) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy]
            if sum(1 for n in near if n is not None and any(a.path.startswith(SEAT) for a in n.objs)) >= 2:
                continue
            if not any(t(kit_nb(p, d)) is not None and any(a.path.startswith(STOOL_AT) for a in t(kit_nb(p, d)).objs)
                       for d in CARD):
                tt.objs.remove(o)
                lone += 1
    if lone:
        notes.append("tidy: %d stools standing at nothing taken off" % lone)
    # rooms: runs of floor of one area
    seen, rooms = set(), []
    for p in sorted(zone):
        if p in seen or not floor(p) or not room_tile(p):
            continue
        a = t(p).apath
        part, st = [], [p]
        seen.add(p)
        while st:
            q = st.pop()
            part.append(q)
            for d in CARD:
                r = kit_nb(q, d)
                if r not in seen and r in zone and floor(r) and t(r).apath == a:
                    seen.add(r)
                    st.append(r)
        rooms.append(part)
    # 3. potted plants: one per 35 floor tiles at most (corners first); the stock maps don't line a room with them
    PLANT = "/obj/item/twohanded/required/kirbyplants"
    cut = 0
    for part in rooms:
        pl = [p for p in part if any(o.path.startswith(PLANT) for o in t(p).objs)]
        cap = max(1, len(part) // 35)
        if len(pl) <= cap:
            continue
        walls = {p: sum(1 for d in CARD if not floor(kit_nb(p, d))) for p in pl}
        for p in sorted(pl, key=lambda q: (-walls[q], q))[cap:]:
            t(p).objs = [o for o in t(p).objs if not o.path.startswith(PLANT)]
            cut += 1
    if cut:
        notes.append("tidy: %d potted plants over the room's share taken off" % cut)
    # 4. a full tile of colour with nothing standing on it, alone (one or two tiles, corners counted): keep only the
    # quarters that trim a wall. Bands and checkers of colour (virology's green, cargo's brown) are runs: they stay.
    dec = 0
    for part in rooms:
        ps = set(part)
        full = {}
        for p in part:
            by = {}
            for o in t(p).objs:
                if o.path.startswith("/obj/effect/turf_decal/tile/") and not o.path.endswith("/bar"):
                    by.setdefault(o.path, set()).add(o.num("dir", 2) or 2)
            for path, dirs in by.items():
                if {1, 2, 4, 8} <= dirs:
                    full.setdefault(path, set()).add(p)
        for path, fs in full.items():
            left = set(fs)
            while left:
                s = left.pop()
                comp, st = [s], [s]
                while st:
                    q = st.pop()
                    for dx in (-1, 0, 1):
                        for dy in (-1, 0, 1):
                            r = (q[0] + dx, q[1] + dy)
                            if r in left:
                                left.discard(r)
                                comp.append(r)
                                st.append(r)
                if len(comp) > 2:
                    continue
                for p in comp:
                    tt = t(p)
                    if any(is_anchor(o) for o in tt.objs):
                        continue
                    edge = {d for d in CARD if kit_nb(p, d) not in ps}
                    keep = {q for q in (1, 2, 4, 8) if set(QUARTER_SIDES[q]) & edge}
                    before = len(tt.objs)
                    tt.objs = [o for o in tt.objs if not (o.path == path and (o.num("dir", 2) or 2) not in keep)]
                    dec += before - len(tt.objs)
    if dec:
        notes.append("tidy: %d stray floor-colour quarters (furniture moved off them) taken off" % dec)
    # 5. a template's work floor (another turf, hazard edge) of 1-3 tiles with nothing on it: back to the room floor
    HAZ = ("/obj/effect/turf_decal/stripes", "/obj/effect/turf_decal/tile/")
    zt = 0
    for part in rooms:
        ps = set(part)
        # the pool's water and its rim are built, not leftovers
        kept = ("/turf/open/pool", "/turf/open/floor/plasteel/yellowsiding")
        rest = [p for p in part if not t(p).tpath.startswith(kept)]
        if not rest:
            continue
        main = Counter(t(p).tpath for p in rest).most_common(1)[0][0]
        odd = {p for p in rest if t(p).tpath != main}
        done, back = set(), set()
        for s in sorted(odd):
            if s in done:
                continue
            comp, st = [], [s]
            done.add(s)
            while st:
                q = st.pop()
                comp.append(q)
                for d in CARD:
                    r = kit_nb(q, d)
                    if r in odd and r not in done and t(r).tpath == t(s).tpath:
                        done.add(r)
                        st.append(r)
            if len(comp) > 3 or any(is_anchor(o) for q in comp for o in t(q).objs):
                continue
            for q in comp:
                tt = t(q)
                tt.turf = dmm.Atom(main)
                tt.objs = [o for o in tt.objs if not o.path.startswith(HAZ)]
                back.add(q)
                zt += 1
        # the hazard edge round a zone that went: stripes beside a reverted tile with no zone tile or furniture beside
        # them (stripes elsewhere on the room floor are kept: an empty assembly floor is marked that way on purpose)
        for p in part:
            tt = t(p)
            if not any(o.path.startswith("/obj/effect/turf_decal/stripes") for o in tt.objs) or tt.tpath != main:
                continue
            if not any((p[0] + dx, p[1] + dy) in back for dx in (-1, 0, 1) for dy in (-1, 0, 1)):
                continue
            near = [kit_nb(p, d) for d in CARD] + [p]
            if any(q in ps and (t(q).tpath != main or any(is_anchor(o) for o in t(q).objs)) for q in near):
                continue
            tt.objs = [o for o in tt.objs if not o.path.startswith("/obj/effect/turf_decal/stripes")]
            zt += 1
    if zt:
        notes.append("tidy: %d leftover work-floor tiles and hazard edges cleared" % zt)
    return notes


def kit_nb(p, d):
    return (p[0] + DELTA[d][0], p[1] + DELTA[d][1])


def dress_maint(m, zone, seed):
    """Clutter down the maint runs as the stock maps have it. Generated maint was bare plating: 2455 tiles, five
    objects (2026-11-16). A dense thing only goes against a wall, away from doors and corridor mouths, and only where
    the walkable tiles round it still join up without it, so no run is ever shut and every APC, valve or alarm tile
    stays reachable."""
    import random
    rnd = random.Random(seed * 7919 + 13)

    def t(p):
        return m.get(p[0], p[1])

    def walk(p):
        tt = t(p)
        if tt is None or not tt.tpath.startswith("/turf/open") or tt.tpath.startswith("/turf/open/space"):
            return False
        return tt.has("/obj/machinery/door") or not kit.dense(tt.objs)

    def solid(p):
        tt = t(p)
        return tt is None or tt.tpath.startswith("/turf/closed") or tt.has("/obj/structure/window") or \
            tt.has("/obj/structure/grille")

    def free(p):
        return all(o.path.startswith(FLOOR_ONLY) for o in t(p).objs)
    M = [p for p in sorted(zone) if t(p) and maint_corridor(t(p).apath) and walk(p)]
    Ms = set(M)
    ring8 = [(dx, dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy]

    def near_door(p):
        return any(t(q) and t(q).has("/obj/machinery/door") for q in
                   [p] + [(p[0] + d[0], p[1] + d[1]) for d in D4.values()])

    def safe(p):
        nb = [(p[0] + d[0], p[1] + d[1]) for d in D4.values()]
        N = [q for q in nb if walk(q)]
        if not N or any(q not in Ms for q in N):
            return False        # a corridor mouth into a room or hall
        for q in nb:
            # a crate or machine beside it keeps a tile to stand at
            if t(q) and t(q).tpath.startswith("/turf/open") and not walk(q) and \
                    not any(walk((q[0] + d[0], q[1] + d[1])) for d in D4.values() if (q[0] + d[0], q[1] + d[1]) != p):
                return False
        ringw = {(p[0] + dx, p[1] + dy) for dx, dy in ring8 if walk((p[0] + dx, p[1] + dy))}
        seen, st = {N[0]}, [N[0]]
        while st:
            a = st.pop()
            for d in D4.values():
                b = (a[0] + d[0], a[1] + d[1])
                if b in ringw and b not in seen:
                    seen.add(b)
                    st.append(b)
        return all(q in seen for q in N)
    placed = set()
    cands = [p for p in M if free(p) and not near_door(p)
             and any(solid((p[0] + d[0], p[1] + d[1])) for d in D4.values())]
    # corners and dead ends first, as the stock maps fill them
    cands.sort(key=lambda p: -sum(solid((p[0] + d[0], p[1] + d[1])) for d in D4.values()) - 2 * rnd.random())
    budget = int(0.15 * len(M))
    total = float(sum(w for w, _, _ in MAINT_DENSE))
    for p in cands:
        if len(placed) >= budget:
            break
        if sum((p[0] + dx, p[1] + dy) in placed for dx, dy in ring8) > 1 or not safe(p):
            continue
        r = rnd.random() * total
        for w, path, extra in MAINT_DENSE:
            r -= w
            if r <= 0:
                break
        objs = t(p).objs
        objs.append(dmm.Atom(path))
        if extra == "loot" and rnd.random() < 0.6:
            objs.append(dmm.Atom("/obj/effect/spawner/lootdrop/maintenance"))
        elif extra == "top" and rnd.random() < 0.8:
            objs.append(dmm.Atom(rnd.choice(MAINT_TOP)))
        placed.add(p)
    # the small things, on open floor
    n_small = 0
    for p in M:
        if p in placed or not free(p) or t(p).has("/obj/machinery/door"):
            continue
        objs = t(p).objs
        sN, sS = solid((p[0], p[1] + 1)), solid((p[0], p[1] - 1))
        sE, sW = solid((p[0] + 1, p[1])), solid((p[0] - 1, p[1]))
        if sN and sW and rnd.random() < 0.35:
            objs.append(dmm.Atom("/obj/effect/decal/cleanable/cobweb"))
            n_small += 1
        elif sN and sE and rnd.random() < 0.35:
            objs.append(dmm.Atom("/obj/effect/decal/cleanable/cobweb/cobweb2"))
            n_small += 1
        r = rnd.random()
        if r < 0.035:
            objs.append(dmm.Atom("/obj/effect/spawner/lootdrop/maintenance"))
        elif r < 0.055:
            objs.append(dmm.Atom("/obj/item/cigbutt"))
        elif r < 0.115:
            objs.append(dmm.Atom("/obj/effect/decal/cleanable/dirt"))
        elif r < 0.12:
            objs.append(dmm.Atom("/obj/effect/decal/cleanable/blood/old"))
        else:
            # a contraband poster on a plain wall beside the tile
            def bare_wall(d):
                dx, dy = D4[d]
                w, past = t((p[0] + dx, p[1] + dy)), t((p[0] + 2 * dx, p[1] + 2 * dy))
                od = {1: 2, 2: 1, 4: 8, 8: 4}[d]
                k_, v_ = PIX[od]

                def hung(o):     # hangs on this wall from the far side: an offset that way (alarms sit at 24), or a lamp
                    return o.num(k_) * v_ >= 20 * 32 or (o.path.startswith("/obj/machinery/light") and o.num("dir", 2) == od)
                return w is not None and w.tpath.startswith("/turf/closed/wall") and \
                    not (past and any(hung(o) for o in past.objs))
            walls = [d for d in D4 if bare_wall(d)]
            if walls and r < 0.14:
                d = rnd.choice(walls)
                k, v = PIX[d]
                if not any(o.get(k) for o in objs):
                    objs.append(dmm.Atom("/obj/structure/sign/poster/contraband/random", [(k, str(v))]))
            else:
                continue
        n_small += 1
    return ["maint dressing: %d dense things (budget %d, %d spots) and %d small over %d maint tiles" %
            (len(placed), budget, len(cands), n_small, len(M))]


def fit_cells(m, cells):
    """Brig cells as MetaStation has them, so Security (bots too) can sentence someone: the way in is a brig windoor
    (id "Cell N") instead of an airlock, its timer hangs on the hall side of the wall beside it, a flasher inside on
    the back wall, and the cell's locker is the brig locker the timer unlocks."""
    from forge import dmm as _d
    notes = []

    def at(p):
        return m.get(p[0], p[1])

    def hung(p, d):
        t = at(p)
        k, v = PIX[d]
        return t is None or any(abs(o.num(k)) >= 20 and (o.num(k) > 0) == (v > 0) for o in t.objs)

    for i, tiles in enumerate(cells, 1):
        if not tiles:
            continue
        cid = "Cell %d" % i
        room = set(tiles)
        door = None
        for p in tiles:
            for d, (dx, dy) in D4.items():
                q = (p[0] + dx, p[1] + dy)
                h = (q[0] + dx, q[1] + dy)
                tq, th = at(q), at(h)
                if q in room or tq is None or th is None or not tq.has("/obj/machinery/door/airlock"):
                    continue
                if th.apath.startswith("/area/maintenance"):
                    # a back door out of a cell is a way out for the prisoner: solid wall instead
                    tq.objs = [o for o in tq.objs if not o.path.startswith(("/obj/machinery/door", "/obj/effect/mapping_helpers/airlock"))]
                    tq.turf = _d.Atom("/turf/closed/wall/r_wall")
                    notes.append("%s: walled its maint door at %d,%d" % (cid, q[0], q[1]))
                    continue
                if door is None and th.tpath.startswith("/turf/open") and h not in room:
                    door = (q, d)
        if not door:
            notes.append("%s: no door onto the hall" % cid)
            continue
        q, d = door
        tq = at(q)
        tq.objs = [o for o in tq.objs if not o.path.startswith(("/obj/machinery/door/airlock", "/obj/effect/mapping_helpers/airlock"))]
        # dir points INTO the cell (stock cells: the default south, cell below): the bots flood the cell from the door's
        # dir side; pointing it at the hall made the whole brig hall "the cell" (prisoner "not inside", cells "full")
        tq.objs.insert(0, _d.Atom("/obj/machinery/door/window/brigdoor/security/cell",
                                  [("dir", str({1: 2, 2: 1, 4: 8, 8: 4}[d])), ("id", '"%s"' % cid), ("name", '"%s"' % cid)]))
        # the timer: on the hall side of a wall tile next to the door
        perp = (4, 8) if d in (1, 2) else (1, 2)
        placed = False
        for e in perp:
            w = (q[0] + D4[e][0], q[1] + D4[e][1])
            f = (w[0] + D4[d][0], w[1] + D4[d][1])
            tw, tf = at(w), at(f)
            back = {1: 2, 2: 1, 4: 8, 8: 4}[d]
            if tw is None or tf is None or not tw.tpath.startswith("/turf/closed") or not tf.tpath.startswith("/turf/open") \
                    or tf.has("/obj/machinery/door") or hung(f, back):
                continue
            k, v = PIX[back]
            tf.objs.append(_d.Atom("/obj/machinery/door_timer", [("id", '"%s"' % cid), ("name", '"%s"' % cid), (k, str(v))]))
            placed = True
            break
        if not placed:
            notes.append("%s: no wall beside its door for the timer" % cid)
        # the flasher: inside, on the wall across from the door if it can, else any wall
        inside = (q[0] - D4[d][0], q[1] - D4[d][1])
        spots = []
        for p in tiles:
            for e, (dx, dy) in D4.items():
                w = (p[0] + dx, p[1] + dy)
                if w in room or at(w) is None or not at(w).tpath.startswith("/turf/closed") or hung(p, e):
                    continue
                spots.append((0 if e == {1: 2, 2: 1, 4: 8, 8: 4}[d] else 1, abs(p[0] - inside[0]) + abs(p[1] - inside[1]), p, e))
        if spots:
            _, _, p, e = min(spots, key=lambda s: (s[0], -s[1]))
            k, v = PIX[e]
            at(p).objs.append(_d.Atom("/obj/machinery/flasher", [("id", '"%s"' % cid), (k, str(28 if v > 0 else -28))]))
        # the cell's locker becomes the brig locker its timer opens
        for p in tiles:
            t = at(p)
            for j, o in enumerate(t.objs):
                if o.path.startswith("/obj/structure/closet") and not o.path.startswith("/obj/structure/closet/secure_closet/brig"):
                    t.objs[j] = _d.Atom("/obj/structure/closet/secure_closet/brig", [("id", '"%s"' % cid), ("name", '"%s Locker"' % cid)])
                    break
        notes.append("%s: brig door at %d,%d" % (cid, q[0], q[1]))
    return notes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("seed", type=int)
    ap.add_argument("--crew", type=int, default=80)
    ap.add_argument("--layout", default="pinwheel")
    a = ap.parse_args()
    run_seed = a.seed       # `a` is reused as a loop name further down
    plan = shapes.generate(a.seed, a.crew, a.layout)
    if plan.problems:
        print("plan problems:", plan.problems[:5])
    pens = carve_pens(plan)
    bp, T, (W, H), rc_of, solar_area = convert(plan, a.layout, a.crew, a.seed)
    print("map %dx%d, %d rooms" % (W, H, len(bp.ROOMDEFS)))

    # roots: the SMES room's centre (a magical SMES), the atmos room's air tank (supply) and waste tank (scrubbers)
    def room_tiles(rid):
        return sorted(T(p) for p, r in plan.floor.items() if r == rid)

    def centre(tiles):
        mx = sum(p[0] for p in tiles) / float(len(tiles))
        my = sum(p[1] for p in tiles) / float(len(tiles))
        return min(tiles, key=lambda p: (p[0] - mx) ** 2 + (p[1] - my) ** 2)
    smes_t = centre(room_tiles("smes") or room_tiles("workshop"))
    atm = room_tiles("tanks") or room_tiles("atmos")
    ts = set(atm)
    # two tank tiles against a plain wall of the room (not a door), each with its tap tile straight in from it
    door_t = {T(p) for p in plan.doors}
    tanks = []
    for p in atm:
        out = [d for d in CARD if (p[0] + DELTA[d][0], p[1] + DELTA[d][1]) not in ts]
        if len(out) != 1 or (p[0] + DELTA[out[0]][0], p[1] + DELTA[out[0]][1]) in door_t:
            continue
        d = OPP[out[0]]
        tap = (p[0] + DELTA[d][0], p[1] + DELTA[d][1])
        if any(abs(p[0] - q[0]) + abs(p[1] - q[1]) < 3 for q, _ in tanks):
            continue
        if any((tap[0] + DELTA[e][0], tap[1] + DELTA[e][1]) in door_t for e in CARD):
            continue
        tanks.append((p, d))
        if len(tanks) == 2:
            break
    roots = {"cable": smes_t}
    taps = {}
    for cls, (p, d) in zip(("supply", "scrubbers"), tanks):
        tap = (p[0] + DELTA[d][0], p[1] + DELTA[d][1])
        roots[cls] = tap
        taps[cls] = [(tap, OPP[d])]
    bp.TAPS = taps
    bd = StationBuilder(bp, roots)
    bd.tank_tiles = frozenset(p for p, _ in tanks)
    # devices that must sit on the networks go down before the passes that route to them
    bd.run_pre = []
    # nothing hangs inside a slime pen (an APC or a camera a slime sits under)
    bd.no_mount = {T(q) for _, _, inside in pens for q in inside}
    # the supermatter block: where it goes is settled on the plan, so the station's networks route round it
    eng = None
    eng_room = room_tiles("engine")
    if eng_room:
        taken = {T(p) for p in set(plan.floor) | plan.walls | set(plan.doors) | plan.glass | set(plan.solar)}
        walls_t = {T(p) for p in plan.walls}
        place = plan_engine(eng_room, walls_t, door_t, taken, W, H)
        waste = place and route_engine_waste(place, eng_room, walls_t - {T(p) for p in plan.glass}, door_t, taken)
        if place and waste:
            _, _, at = place
            foot = {at[uv] for uv in set(ENGINE_CORE) | set(ENGINE_NOOK)}
            coil = {at[uv] for uv in engine_block() if uv[1] < 0}
            path, inj = waste
            bd.engine_cable_fence = frozenset(foot | coil | {inj})
            bd.engine_pipe_fence = frozenset(foot | coil | set(path) | {inj} | {at[(-1, v)] for v in (15, 16, 17)})
            bd.engine_cables = tuple(at[uv] for uv in ENGINE_CABLES)
            # floor the fence cuts off from the rest of the room (between the block, the freezer rows and the waste
            # line) can't be piped from outside: no vent there either
            rest = set(eng_room) - bd.engine_pipe_fence
            parts, seen = [], set()
            for s0 in sorted(rest):
                if s0 in seen:
                    continue
                part, st = {s0}, [s0]
                seen.add(s0)
                while st:
                    a0 = st.pop()
                    for e in CARD:
                        b0 = (a0[0] + DELTA[e][0], a0[1] + DELTA[e][1])
                        if b0 in rest and b0 not in seen:
                            seen.add(b0)
                            part.add(b0)
                            st.append(b0)
                parts.append(part)
            cut = set().union(*[q for q in parts if q is not max(parts, key=len)]) if parts else set()
            bd.engine_no_vent = frozenset({at[(-1, v)] for v in range(18)} | cut)
            bd.no_mount |= foot
            bd.stamped = foot | coil
            bd.engine_block = frozenset(at[uv] for uv in engine_block())
            eng = (place, waste)
        else:
            print("    engine: no place for the supermatter block in the engine room (%s)" %
                  ("no fit" if not place else "no way out for the waste line"))
    for note in reserve_pools(bd):
        print("   ", note)
    bd.run()
    m = bd.m
    for note in fit_pens(m, pens, T):
        print("   ", note)
    cells = sorted((r for r in plan.rooms if base_id(r) == "cells"), key=lambda r: min(room_tiles(r)) if room_tiles(r) else (0, 0))
    for note in fit_cells(m, [room_tiles(r) for r in cells]):
        print("   ", note)
    for r in plan.rooms:
        if base_id(r) == "treatment":
            for note in fill_ward(m, room_tiles(r)):
                print("   ", note)
    # does each piece work where it stands (links, standing tiles, plants, chairs, one-of-a-kind things)
    from forge import function as F
    fixes = F.fix(m, bd.zone)
    print("function fixes: %d" % len(fixes))
    for n_ in fixes[:80]:
        print("   ", n_)
    if eng:
        for note in paste_engine(m, eng[0], eng[1], A["engine"][0]):
            print("   ", note)

    def put(p, path, vs=()):
        m.get(*p).objs.append(dmm.Atom(path, list(vs)))
    # stock grids draw 150-230 kW; the default 50 kW output let every APC drain flat by the end of a shift
    put(smes_t, "/obj/machinery/power/smes/magical", [("output_level", "300000"), ("output_level_max", "300000")])
    for (cls, (p, d)) in zip(("supply", "scrubbers"), tanks):
        tank = "/obj/machinery/atmospherics/components/unary/tank/air" if cls == "supply" else \
            "/obj/machinery/atmospherics/components/unary/tank"
        # supply runs on layer 1, scrubbers on the default layer 2
        put(p, tank, [("dir", str(d))] + ([("piping_layer", "1")] if cls == "supply" else []))

    # landmarks: jobs, latejoin, observers, events
    used = set()
    lm = 0
    for job, rooms_, n in JOBS:
        got = 0
        for rid in rooms_:
            if rid not in rc_of:
                continue
            for p in free_tiles(bd, rc_of[rid], n - got, used):
                put(p, "/obj/effect/landmark/start/%s" % job)
                used.add(p)
                got += 1
                lm += 1
            if got >= n:
                break
        if not got:
            bd.warn.append("no start point for %s" % job)
    for rid in ("arr_lounge",):
        for p in free_tiles(bd, rc_of.get(rid, ""), 8, used):
            put(p, "/obj/effect/landmark/latejoin")
            used.add(p)
    obs = free_tiles(bd, rc_of.get("bar", rc_of.get("arr_lounge")), 1, used)
    for p in obs:
        put(p, "/obj/effect/landmark/observer_start")
    maint_rc = [c for c, rd in bd.roomdefs.items() if "/maintenance/" in rd["area"] and "solars" not in rd["area"]]
    for i, c in enumerate(maint_rc):
        for p in free_tiles(bd, c, 3, used):
            put(p, ("/obj/effect/landmark/blobstart", "/obj/effect/landmark/xeno_spawn",
                    "/obj/effect/landmark/event_spawn")[i % 3])
            used.add(p)
    # the machines the round needs
    def first_free(rids, avoid=used):
        for rid in rids:
            if rid in rc_of:
                ps = free_tiles(bd, rc_of[rid], 1, avoid)
                if ps:
                    avoid.add(ps[0])
                    return ps[0]
    # PDA messages need the message server; the blackbox records the round (none on any seed, 2026-11-16 quad review)
    need = [(("tcomms", "tc_control"), "/obj/machinery/telecomms/allinone"),
            (("tcomms", "tc_control"), "/obj/machinery/telecomms/message_server"),
            (("tcomms", "tc_control"), "/obj/machinery/blackbox_recorder"),
            (("vault", "bridge"), "/obj/machinery/nuclearbomb/selfdestruct"),
            (("grav", "smes"), "/obj/machinery/gravity_generator/main/station"),
            (("upload",), "/obj/machinery/computer/upload/ai"),
            (("bridge",), "/obj/machinery/computer/communications"),
            (("captain", "cap_bed", "bridge"), "/obj/item/disk/nuclear")]
    present = {o.path for t in [m.get(*p) for p in bd.zone] if t for o in t.objs}
    for rids, path in need:
        if path in present:
            continue
        p = first_free(rids)
        if p:
            put(p, path)
        else:
            bd.warn.append("no room for %s" % path)
    for note in fill_utility(m, bd, rc_of, used, put):
        print("   ", note)

    # solar fields: lattice, catwalks with cable, panels, the tracker; cable down the lead into the control room
    for p, kind in plan.solar.items():
        q = T(p)
        t = m.get(*q)
        lab = next((l for (r, l) in plan.solars if r[0] - 2 <= p[0] <= r[2] + 2 and r[1] - 2 <= p[1] <= r[3] + 2), None)
        ps, fa = solar_area.get(lab, ("port", "fore"))
        t.area = dmm.Atom("/area/solar/%s/%s" % (ps, fa))
        if kind == "panel":
            t.turf = dmm.Atom("/turf/open/floor/plasteel/airless/solarpanel")
            t.objs = [dmm.Atom("/obj/machinery/power/solar"), dmm.Atom(kit.CABLE)]
        elif kind == "tracker":
            t.turf = dmm.Atom("/turf/open/floor/plasteel/airless/solarpanel")
            t.objs = [dmm.Atom("/obj/machinery/power/tracker"), dmm.Atom(kit.CABLE)]
        elif kind == "cable":
            t.objs = [dmm.Atom("/obj/structure/lattice/catwalk"), dmm.Atom(kit.CABLE)]
        else:
            t.objs = [dmm.Atom("/obj/structure/lattice")]
    for rect, label in plan.solars:
        rid = "solar_%s" % label
        if rid not in rc_of:
            continue
        rt = [q for q, r in bd.room.items() if r == rc_of[rid]]
        # the control room: console on the grid, the lock and lead cabled through to the field
        lock = [q for q, r in bd.room.items() if r == rc_of.get("solar_lock_%s" % label)]
        for q in lock:
            if not any(o.path == kit.CABLE for o in m.get(*q).objs):
                m.get(*q).objs.append(dmm.Atom(kit.CABLE))
            for d in CARD:
                n1 = bd.nb(q, d)
                if m.get(*n1).has("/obj/machinery/door/airlock/external") and not any(o.path == kit.CABLE for o in m.get(*n1).objs):
                    m.get(*n1).objs.append(dmm.Atom(kit.CABLE))
        for q in rt:
            if not any(o.path == kit.CABLE for o in m.get(*q).objs):
                m.get(*q).objs.append(dmm.Atom(kit.CABLE))
        c = free_tiles(bd, rc_of[rid], 1, used)
        if c:
            put(c[0], "/obj/machinery/power/solar_control", [("id", '"%s"' % label), ("track", "2")])
            used.add(c[0])

    # dock ports, just outside each dock door
    for p, side, name, dims in plan.docks:
        key = name if name in PORTS else None
        if not key:
            continue
        pid, w, dw, h, extra = PORTS[key]
        q = T((p[0] + side[0], p[1] + side[1]))
        dirn = {(0, 1): 1, (0, -1): 2, (1, 0): 4, (-1, 0): 8}[tuple(side)]

        def clear(q_):
            x1, y1, x2, y2 = port_rect(q_, dirn, w, dw, h)
            return all(m.get(x, y) and m.get(x, y).tpath.startswith("/turf/open/space") and
                       not any(o.path.startswith("/obj/structure/lattice") for o in m.get(x, y).objs)
                       for x in range(min(x1, x2), max(x1, x2) + 1) for y in range(min(y1, y2), max(y1, y2) + 1))
        dp = T(p)
        sd = (q[0] - dp[0], q[1] - dp[1])
        if key == "arrivals":
            note = side_dock(m, dp, sd, pid, w, dw, h, extra)
            if note:
                print("   ", note)
            else:
                bd.warn.append("arrivals dock: no straight stretch of hull with room for the shuttle's two side doors")
            continue
        # a neighbour's hull juts into the shuttle's space: run a short docking arm out past it, as stock maps do
        # (the door moves to the arm's end, walls either side)
        if not clear(q):
            for k in (1, 2, 3):
                q2 = (q[0] + k * sd[0], q[1] + k * sd[1])
                arm = [(dp[0] + i * sd[0], dp[1] + i * sd[1]) for i in range(1, k + 1)]
                if not clear(q2) or not all(m.get(*a) and m.get(*a).tpath.startswith("/turf/open/space") for a in arm):
                    continue
                inner = m.get(dp[0] - sd[0], dp[1] - sd[1])
                door_t = m.get(*dp)
                end = m.get(*arm[-1])
                end.objs, end.turf, end.area = door_t.objs, door_t.turf, inner.area
                door_t.objs = []
                for a in [dp] + arm[:-1]:
                    t_ = m.get(*a)
                    t_.turf, t_.area = dmm.Atom(inner.turf.path, list(inner.turf.vars)), inner.area
                for a in arm:
                    for s_ in (1, -1):
                        f = (a[0] + s_ * sd[1], a[1] + s_ * sd[0])
                        ft = m.get(*f)
                        if ft and ft.tpath.startswith("/turf/open/space"):
                            ft.turf, ft.objs, ft.area = dmm.Atom("/turf/closed/wall/r_wall"), [], inner.area
                q = q2
                print("    %s dock: %d-tile docking arm past the next room's hull" % (name, k))
                break
        vs = [("dir", str(dirn)), ("dwidth", str(dw)), ("height", str(h)), ("id", '"%s"' % pid),
              ("name", '"%s"' % pid.replace("_", " ")), ("width", str(w))]
        if extra:
            k, v = extra.split(" = ", 1)
            vs.append((k, v))
        put(q, "/obj/docking_port/stationary", vs)
        # is the footprint clear space?
        x1, y1, x2, y2 = port_rect(q, dirn, w, dw, h)
        blocked = [(x, y) for x in range(min(x1, x2), max(x1, x2) + 1) for y in range(min(y1, y2), max(y1, y2) + 1)
                   if not m.get(x, y) or not m.get(x, y).tpath.startswith("/turf/open/space") or
                   any(o.path.startswith("/obj/structure/lattice") for o in m.get(x, y).objs)]
        if blocked:
            bd.warn.append("%s dock: %d tiles of its shuttle's space are built on (first %s)" % (name, len(blocked), blocked[0]))

    for note in fit_hall_firelocks(m, set(bd.zone)):
        print("   ", note)
    for note in dress_maint(m, set(bd.zone), run_seed):
        print("   ", note)
    face_notes = one_per_wall_face(m, bd.zone, keep=frozenset(getattr(bd, "stamped", ())))
    for note in face_notes[:12]:
        print("   ", note)
    for note in tidy_rooms(m, bd.zone, keep=frozenset(getattr(bd, "stamped", ()))):
        print("   ", note)
    from station import floors
    for note in floors.style_floors(m, bd, keep=frozenset(getattr(bd, "engine_block", ()))):
        print("   ", note)
    left = F.review(m, bd.zone)
    from collections import Counter
    print("function review after: %d %s" % (len(left), dict(Counter(r for r, _, _ in left))))
    for r, p, txt in left[:40]:
        print("    %-6s %3d,%3d  %s" % (r, p[0], p[1], txt))
    from forge import check
    bd.ports = {cls: [(roots[cls], 0)] for cls in ("supply", "scrubbers", "cable") if cls in roots}
    res = check.run(bd)
    print("forge check: %d problems" % len(res["problems"]))
    for pr in res["problems"][:40]:
        print("   ", pr)

    name = bp.NAME
    outdir = os.path.join(ROOT, "_maps", "map_files", "Generated")
    if os.environ.get("MAPFORGE_OUT"):
        # a trial build beside the real one (a shift batch loads the .dmm at round start, so rebuilding mid-batch
        # would change the map under the shifts still to come)
        outdir = os.environ["MAPFORGE_OUT"]
        os.makedirs(outdir, exist_ok=True)
        bd.save(os.path.join(outdir, name + ".dmm"))
        print("wrote", os.path.join(outdir, name + ".dmm"), "(trial)")
        return
    os.makedirs(outdir, exist_ok=True)
    path = os.path.join(outdir, name + ".dmm")
    bd.save(path)
    js = {"map_name": "Generated %s" % name, "map_path": "map_files/Generated", "map_file": name + ".dmm",
          "shuttles": SHUTTLES}   # Lavaland and space ruins as on the stock maps (the mining shuttle needs mining_away)
    json.dump(js, open(os.path.join(ROOT, "_maps", name + ".json"), "w"), indent=4)
    print("wrote", os.path.relpath(path, ROOT), "landmarks", lm)
    print("warnings %d" % len(bd.warn))
    for w_ in bd.warn[:40]:
        print("   ", w_)


# the donut arrivals shuttle (the template every generated map loads): its port sits mid-nose facing south, its two
# airlocks on the east flank 4 and 9 tiles down from the port. Every stock arrivals shuttle docks side-on like this,
# its flank doors against two station airlocks (Donut: x=136, five apart); a station door at the nose opens onto
# the shuttle's wall and its own doors onto space (bots spawned there, vented it, died).
ARRIVALS_DOORS = ((3, -4), (3, -9))
ANGLE = {1: 0, 4: 90, 2: 180, 8: 270}


def rot(v, ang):
    """v turned clockwise by ang degrees (BYOND's shuttle rotation)."""
    x, y = v
    for _ in range((ang // 90) % 4):
        x, y = y, -x
    return (x, y)


def side_dock(m, dp, sd, pid, w, dw, h, extra):
    """Dock the arrivals shuttle side-on to the hull at dp (a dock door, sd pointing out to space): the stationary
    port turned so the shuttle's door flank faces the station, two station airlocks where its doors land, the
    old door walled if neither. Returns a note, or None when no spot along the wall fits."""
    for D in (1, 2, 4, 8):
        ang = (ANGLE[D] - 180) % 360
        if rot((1, 0), ang) == (-sd[0], -sd[1]):
            break
    along = rot((0, 1), ang)

    def at(P, v):
        r = rot(v, ang)
        return (P[0] + r[0], P[1] + r[1])

    def hull_door_ok(t):
        """A hull wall (or the dock door) with station floor behind and space in front."""
        tt, back, front = m.get(*t), m.get(t[0] - sd[0], t[1] - sd[1]), m.get(t[0] + sd[0], t[1] + sd[1])
        if not (tt and back and front):
            return False
        # a wall or a window run (grille + glass on plating): both are hull an airlock can replace
        wallish = tt.tpath.startswith("/turf/closed") or t == dp or \
            any(o.path.startswith("/obj/structure/grille") or "window" in o.path for o in tt.objs)
        return wallish and back.tpath.startswith("/turf/open") and not back.tpath.startswith("/turf/open/space") \
            and not any(kit.is_dense_atom(o) for o in back.objs) and front.tpath.startswith("/turf/open/space")

    def footprint_clear(P):
        for dx in range(-dw, w - dw):
            for dy in range(-(h - 1), 1):
                t = m.get(*at(P, (dx, dy)))
                if not t or not t.tpath.startswith("/turf/open/space") or \
                        any(o.path.startswith("/obj/structure/lattice") for o in t.objs):
                    return False
        return True
    tries = []
    for k in range(0, 9):
        for sgn in ((1, -1) if k else (1,)):
            for anchor in ARRIVALS_DOORS:
                # P such that this shuttle door sits in front of dp shifted k along the wall
                base = (dp[0] + sgn * k * along[0], dp[1] + sgn * k * along[1])
                r = rot((anchor[0] + 1, anchor[1]), ang)
                tries.append((base[0] - r[0], base[1] - r[1]))
    for P in tries:
        doors = [at(P, (dx + 1, dy)) for dx, dy in ARRIVALS_DOORS]
        if not all(hull_door_ok(t) for t in doors) or not footprint_clear(P):
            continue
        src = m.get(*dp)
        door_objs = [dmm.Atom(o.path, list(o.vars)) for o in src.objs]
        door_turf = dmm.Atom(src.turf.path, list(src.turf.vars))
        if dp not in doors:
            wall = next((m.get(dp[0] + a[0], dp[1] + a[1]) for a in (along, (-along[0], -along[1]))
                         if m.get(dp[0] + a[0], dp[1] + a[1]).tpath.startswith("/turf/closed")), None)
            src.turf = dmm.Atom(wall.turf.path if wall else "/turf/closed/wall/r_wall")
            src.objs = [o for o in src.objs if o.path == kit.CABLE]
        for t in doors:
            if t != dp:
                tt = m.get(*t)
                tt.turf = dmm.Atom(door_turf.path, list(door_turf.vars))
                tt.objs = [o for o in tt.objs if o.path == kit.CABLE] + [dmm.Atom(o.path, list(o.vars)) for o in door_objs
                                                                         if o.path != kit.CABLE]
        vs = [("dir", str(D)), ("dwidth", str(dw)), ("height", str(h)), ("id", '"%s"' % pid),
              ("name", '"%s"' % pid.replace("_", " ")), ("width", str(w))]
        if extra:
            k_, v_ = extra.split(" = ", 1)
            vs.append((k_, v_))
        m.get(*P).objs.append(dmm.Atom("/obj/docking_port/stationary", vs))
        return "arrivals dock: shuttle side-on at %d,%d dir %d, airlocks %s" % (P[0], P[1], D, " ".join("%d,%d" % t for t in doors))
    return None


def port_rect(q, dirn, width, dwidth, height, dheight=0):
    cos, sin = {1: (1, 0), 8: (0, 1), 2: (-1, 0), 4: (0, -1)}[dirn]
    x, y = q
    return (x + (-dwidth * cos) - (-dheight * sin), y + (-dwidth * sin) + (-dheight * cos),
            x + (-dwidth + width - 1) * cos - (-dheight + height - 1) * sin,
            y + (-dwidth + width - 1) * sin + (-dheight + height - 1) * cos)


if __name__ == "__main__":
    main()
