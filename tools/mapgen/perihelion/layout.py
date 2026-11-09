"""Perihelion Station block layout.

Coordinates are tiles, drawn with y going down (north at the top). Rects are
(x0, y0, x1, y1), end-exclusive; neighbouring rooms share an edge value. The
whole plan is shifted by OFFSET when placed on the 255x255 z-level.

Each module has a 1-tile maint ring just inside its hull (module rect grown
by 1), and the hull wall is the rect grown by 2. Maint tunnels run between
the rings; a tunnel opens into a ring by covering one ring tile.

Public and department space are kept apart. Each module carries a stretch
of the public concourse (the loop). Department rooms open only onto their
own department hall, which the public reaches only through an access door,
usually from a lobby or front desk. render.py walks the plan as a member of
the public and fails if that walk reaches a room not flagged "public".

This file is the single source for the preview (render.py) and, later, the
.dmm generator.
"""

OFFSET = (17, 40)
WORLD = 255
EDGE = 8  # keep everything this far from the z-level edge (space transit)

# dept -> preview colour
DEPTS = {
    "sec": (176, 62, 62),
    "cmd": (60, 92, 170),
    "srv": (74, 150, 86),
    "med": (90, 170, 200),
    "eng": (214, 150, 40),
    "sup": (160, 120, 70),
    "sci": (150, 90, 190),
    "arr": (130, 130, 140),
    "ai":  (60, 150, 140),
    "mnt": (110, 100, 90),
}

# name, dept, outer rect (rooms + halls)
MODULES = [
    ("Security",      "sec", (14, 22, 52, 78)),
    ("Command",       "cmd", (78, 12, 132, 52)),
    ("Service",       "srv", (158, 22, 200, 82)),
    ("Medical",       "med", (158, 106, 200, 164)),
    ("Engineering",   "eng", (78, 132, 134, 196)),
    ("Cargo",         "sup", (14, 104, 52, 162)),
    ("Science core",  "sci", (80, 66, 130, 118)),
]

# halls: name, owner ("public" or a dept), rect. 4 wide (bot routes).
# Halls with the same owner join where they touch; a public hall and a
# department hall never join except through a GATE.
HALLS = [
    # Security: concourse along the east side, department hall behind
    ("sec-P",  "public", (48, 30, 52, 78)),
    ("sec-D",  "sec",    (30, 26, 34, 74)),
    # Command: concourse across the middle and down the spoke
    ("cmd-P",  "public", (78, 30, 132, 34)),
    ("cmd-P2", "public", (103, 34, 107, 52)),
    ("cmd-Dn", "cmd",    (92, 26, 118, 30)),   # bridge side
    ("cmd-Dw", "cmd",    (78, 34, 103, 38)),   # vault / upload side
    ("cmd-De", "cmd",    (107, 34, 132, 38)),  # teleporter / EVA side
    # Service: concourse, kitchen/hydro back hall on the west
    ("srv-P",  "public", (158, 30, 181, 34)),
    ("srv-P2", "public", (177, 34, 181, 82)),
    ("srv-D",  "srv",    (158, 34, 162, 82)),
    # Medical: concourse along the top and west side
    ("med-P",  "public", (158, 106, 181, 110)),
    ("med-P2", "public", (158, 110, 162, 136)),
    ("med-D",  "med",    (177, 110, 181, 164)),
    # Engineering: concourse along the top, department hall below
    ("eng-P",  "public", (78, 132, 134, 136)),
    ("eng-D",  "eng",    (78, 146, 134, 150)),
    # Cargo: concourse along the east side, department hall behind
    ("sup-P",  "public", (48, 104, 52, 136)),
    ("sup-D",  "sup",    (30, 104, 34, 158)),
    # Science: no public route through; the lobby is the only way in
    ("sci-D",  "sci",    (103, 72, 107, 118)),
    ("sci-D2", "sci",    (80, 90, 103, 94)),
    ("sci-D3", "sci",    (107, 90, 130, 94)),
]

# walkways between modules, blast doors at both ends. They join public
# halls openly; a department hall needs a GATE.
# kind "glass" = windowed bridge, "tunnel" = reinforced, no windows
WALKWAYS = [
    ("W1", (52, 30, 78, 34), "glass"),     # security - command
    ("W2", (132, 30, 158, 34), "glass"),   # command - service
    ("W3", (177, 82, 181, 106), "glass"),  # service - medical (departures)
    ("W4", (134, 132, 158, 136), "glass"), # engineering - medical
    ("W5", (52, 132, 78, 136), "glass"),   # cargo - engineering
    ("W6", (48, 78, 52, 104), "glass"),    # security - cargo
    ("S1", (103, 52, 107, 66), "glass"),   # command - science lobby
    ("S2", (103, 118, 107, 132), "glass"), # science (staff) - engineering
    ("T1", (103, -6, 107, 12), "tunnel"),  # bridge - AI satellite
]

# access-locked doors between a department hall and a public passage
GATES = [
    ("cmd-Dn", "cmd-P"),
    ("cmd-Dw", "cmd-P"),
    ("cmd-De", "cmd-P"),
    ("srv-D", "srv-P"),
    ("sci-D", "S2"),
]

# maintenance tunnels (2 wide), separate from the walkways
MAINT = [
    # west trunk between Security / Cargo and the science core
    ("MW",  (64, 38, 66, 128)),
    ("MW-sec", (52, 56, 64, 58)),
    ("MW-cmd", (64, 36, 78, 38)),
    ("MW-sci", (66, 98, 80, 100)),
    ("MW-sup", (52, 122, 64, 124)),
    # east trunk, broken by the xenobiology pod
    ("ME1", (142, 38, 144, 76)),
    ("ME1-cmd", (132, 44, 142, 46)),
    ("ME1-srv", (144, 60, 158, 62)),
    ("ME1-sci", (130, 70, 142, 72)),
    ("ME2", (142, 112, 144, 128)),
    ("ME2-med", (144, 126, 158, 128)),
    ("ME2-sci", (130, 114, 142, 116)),
    # outer links
    ("MN",  (132, 20, 158, 22)),     # command - service, north
    ("MSW", (52, 160, 78, 162)),     # cargo - engineering, south
    ("MSE", (134, 160, 158, 162)),   # engineering - medical, south
    ("MWO", (18, 78, 20, 104)),      # security - cargo, outer west
    ("MSM", (160, 82, 162, 106)),    # service - medical, inner
    # solar control stubs
    ("M-solNW", (9, 42, 14, 44)),
    ("M-solNE", (200, 42, 204, 44)),
    ("M-solSW", (32, 162, 34, 166)),
    ("M-solSE", (172, 164, 174, 168)),
]

# name, dept, rect, flags:
#   public  - open to everyone; its door goes on a public hall/walkway
#   locked  - door straight onto a public hall, but access-locked
#   (none)  - department room; its door goes on its department's hall
#   noauto  - no automatic door; MANUAL_DOORS only
#   pod     - outside a module, gets its own hull
#   secure  - reinforced walls; maint ring next to it is walled off
#   turrets - turret coverage
#   post    - staffed Security post
ROOMS = [
    # Security
    ("Checkpoint",     "sec", (40, 22, 52, 30), "public post"),
    ("Sec Lockers",    "sec", (34, 22, 40, 30), ""),
    ("HoS Office",     "sec", (14, 22, 30, 34), ""),
    ("Sec Office",     "sec", (14, 34, 30, 48), ""),
    ("Interrogation",  "sec", (14, 48, 30, 54), ""),
    ("Detective",      "sec", (14, 54, 30, 64), ""),
    ("Permabrig",      "sec", (14, 64, 30, 78), ""),
    ("Sec Lobby",      "sec", (34, 30, 48, 38), "public"),
    ("Warden",         "sec", (34, 38, 48, 44), ""),
    ("Armory",         "sec", (34, 44, 44, 54), "noauto secure"),
    ("Evidence",       "sec", (44, 44, 48, 54), "noauto"),
    ("Cells",          "sec", (34, 54, 48, 66), ""),
    ("Courtroom",      "sec", (34, 66, 48, 78), "public"),
    # Arrivals (on walkway W1)
    ("Arrivals",       "arr", (56, 18, 74, 30), "public pod"),
    # the arrivals shuttle docks in the slot between these two, airlocks on both sides
    ("Arrivals Dock W", "arr", (57, 5, 61, 18), "public pod noauto"),
    ("Arrivals Dock E", "arr", (69, 5, 73, 18), "public pod noauto"),
    # Command
    ("Captain",        "cmd", (78, 12, 92, 24), "noauto"),
    ("Cmd Checkpoint", "sec", (78, 24, 92, 30), "public post"),
    ("Bridge",         "cmd", (92, 18, 118, 26), ""),
    ("Cmd Storage",    "cmd", (92, 12, 100, 18), "noauto"),
    ("Sat Access",     "cmd", (100, 12, 110, 18), "noauto"),
    ("Cmd Lockers",    "cmd", (110, 12, 118, 18), "noauto"),
    ("HoP Office",     "cmd", (118, 12, 132, 26), "noauto"),
    ("HoP Queue",      "cmd", (118, 26, 132, 30), "public"),
    ("Vault Foyer",    "cmd", (78, 38, 90, 43), ""),
    ("Vault",          "cmd", (78, 43, 90, 52), "noauto secure"),
    ("Upload Foyer",   "cmd", (90, 38, 103, 43), "turrets"),
    ("AI Upload",      "cmd", (90, 43, 103, 52), "noauto secure turrets"),
    ("Teleporter",     "cmd", (107, 38, 116, 52), ""),
    ("Conference",     "cmd", (116, 38, 124, 52), ""),
    ("EVA",            "cmd", (124, 38, 132, 52), ""),
    # AI satellite, north of Command at the end of tunnel T1
    ("Sat Checkpoint", "ai",  (98, -12, 112, -6), "noauto pod turrets post"),
    ("Turret Hall",    "ai",  (98, -20, 112, -12), "noauto pod secure turrets"),
    ("AI Core",        "ai",  (98, -30, 112, -20), "noauto pod secure turrets"),
    ("Sat Storage",    "ai",  (88, -20, 98, -6), "noauto pod"),
    ("Sat Power",      "ai",  (88, -30, 98, -20), "noauto pod"),
    ("Telecomms",      "ai",  (112, -30, 124, -6), "noauto pod"),
    # Service
    ("Janitor",        "srv", (158, 22, 168, 30), "locked"),
    ("Theatre",        "srv", (168, 22, 177, 30), "locked"),
    ("Chapel",         "srv", (181, 22, 200, 40), "public"),
    ("Bar",            "srv", (162, 34, 177, 50), "public"),
    ("Kitchen",        "srv", (162, 50, 177, 62), ""),
    ("Hydroponics",    "srv", (162, 62, 177, 82), ""),
    ("Library",        "srv", (181, 40, 200, 52), "public"),
    ("Dorms",          "srv", (181, 52, 200, 70), "public"),
    ("Restrooms",      "srv", (181, 70, 200, 82), "public"),
    # Departures (on walkway W3)
    ("Departures",     "arr", (181, 86, 204, 102), "public pod"),
    # Medical
    ("Med Lobby",      "med", (162, 110, 177, 120), "public"),
    ("Ward",           "med", (162, 120, 177, 136), ""),
    ("Surgery",        "med", (158, 136, 177, 150), ""),
    ("Morgue",         "med", (158, 150, 177, 164), ""),
    ("Chemistry",      "med", (181, 106, 200, 118), ""),
    ("Cloning",        "med", (181, 118, 200, 134), ""),
    ("CMO",            "med", (181, 134, 200, 142), ""),
    ("Cryo",           "med", (181, 142, 200, 148), ""),
    ("Med Storage",    "med", (181, 148, 200, 164), ""),
    ("Viro Airlock",   "med", (200, 154, 206, 158), "noauto pod"),
    ("Virology",       "med", (206, 150, 218, 162), "noauto pod"),
    # Engineering
    ("Eng Lockers",    "eng", (78, 136, 100, 146), ""),
    ("Eng Lobby",      "eng", (100, 136, 110, 146), "public"),
    ("CE Office",      "eng", (110, 136, 120, 146), ""),
    ("Tech Storage",   "eng", (120, 136, 134, 146), ""),
    ("Atmospherics",   "eng", (78, 150, 100, 172), ""),
    ("Atmos Tanks",    "eng", (78, 172, 100, 184), "noauto"),
    ("Atmos Storage",  "eng", (78, 184, 100, 194), "noauto"),
    ("Gravity Gen",    "eng", (100, 150, 112, 162), ""),
    ("Engine Airlock", "eng", (112, 150, 122, 162), ""),
    ("SMES",           "eng", (122, 150, 134, 162), ""),
    # Solar control rooms (pods off the maint stubs)
    ("NW Solars",      "eng", (3, 40, 9, 46), "pod"),
    ("NE Solars",      "eng", (204, 40, 210, 46), "pod"),
    ("SW Solars",      "eng", (29, 166, 37, 172), "pod"),
    ("SE Solars",      "eng", (169, 168, 177, 174), "pod"),
    # Cargo
    ("QM Office",      "sup", (14, 104, 30, 114), ""),
    ("Cargo Bay",      "sup", (14, 114, 30, 148), ""),
    ("Mining Dock",    "sup", (14, 148, 30, 162), ""),
    ("Cargo Lobby",    "sup", (34, 104, 48, 114), "public"),
    ("Warehouse",      "sup", (34, 114, 48, 136), ""),
    ("Recycling",      "sup", (34, 136, 52, 148), ""),
    ("Mining Lockers", "sup", (34, 148, 52, 162), ""),
    # Science core
    ("Sci Lobby",      "sci", (98, 66, 112, 72), "public"),
    ("Sci Lockers",    "sci", (80, 66, 98, 72), "noauto"),
    ("R&D",            "sci", (80, 72, 103, 82), ""),
    ("RD Office",      "sci", (80, 82, 92, 90), ""),
    ("Servers",        "sci", (92, 82, 103, 90), ""),
    ("Mech Storage",   "sci", (112, 66, 130, 72), "noauto"),
    ("Robotics",       "sci", (107, 72, 130, 82), ""),
    ("Mech Bay",       "sci", (107, 82, 130, 90), ""),
    ("Toxins Lab",     "sci", (80, 94, 103, 106), ""),
    ("Burn Chamber",   "sci", (80, 106, 92, 118), "noauto"),
    ("Toxins Storage", "sci", (92, 106, 103, 118), ""),
    ("Nanites",        "sci", (107, 94, 118, 118), ""),
    ("Anomaly Lab",    "sci", (118, 94, 130, 118), ""),
    # Xenobiology pod east of the core, behind an airlock off the cross hall
    ("Xeno Airlock",   "sci", (130, 90, 136, 94), "pod"),
    # Maintenance rooms along the tunnels
    ("Abandoned Office", "mnt", (56, 86, 64, 94), "pod"),
    ("Maint Bar",      "mnt", (66, 112, 76, 122), "pod"),
    ("Storage Closet", "mnt", (144, 40, 154, 48), "pod"),
    ("Abandoned Lab",  "mnt", (144, 116, 154, 124), "pod"),
]

# doors by name (rooms, halls or walkways): (a, b, kind)
#   ""       ordinary door
#   access   department access door (the way from public into a department)
#   secure   high-security door (vault door, secure airlock)
#   desk     counter with a windoor; things pass, people don't
MANUAL_DOORS = [
    # front desks and lobbies: the only ways into each department
    ("Sec Lobby", "sec-D", "access"),
    ("Courtroom", "sec-D", "access"),
    ("Cmd Checkpoint", "cmd-Dn", "access"),
    ("HoP Queue", "HoP Office", "desk"),
    ("Bar", "srv-D", "access"),
    ("Kitchen", "Bar", "desk"),
    ("Hydroponics", "srv-P2", "desk"),
    ("Med Lobby", "med-D", "access"),
    ("Chemistry", "med-P", "desk"),
    ("Eng Lobby", "eng-D", "access"),
    ("Cargo Lobby", "sup-D", "access"),
    ("Sci Lobby", "sci-D", "access"),
    ("Arrivals Dock W", "Arrivals", "open"),
    ("Arrivals Dock E", "Arrivals", "open"),
    ("R&D", "Sci Lobby", "desk"),
    ("Robotics", "Sci Lobby", "desk"),
    # inner rooms
    ("Armory", "Warden", "secure"),
    ("Evidence", "Warden", ""),
    ("Captain", "Bridge", ""),
    ("HoP Office", "Bridge", ""),
    ("Cmd Storage", "Bridge", ""),
    ("Cmd Lockers", "Bridge", ""),
    ("Vault", "Vault Foyer", "secure"),
    ("AI Upload", "Upload Foyer", "secure"),
    ("Sat Access", "Bridge", "secure"),
    ("Sat Access", "T1", "secure"),
    ("Sat Checkpoint", "T1", "secure"),
    ("Turret Hall", "Sat Checkpoint", "secure"),
    ("AI Core", "Turret Hall", "secure"),
    ("Sat Storage", "Sat Checkpoint", ""),
    ("Sat Power", "Sat Storage", ""),
    ("Telecomms", "Sat Checkpoint", "secure"),
    ("Atmos Tanks", "Atmospherics", ""),
    ("Atmos Storage", "Atmos Tanks", ""),
    ("Viro Airlock", "Med Storage", ""),
    ("Virology", "Viro Airlock", ""),
    ("Burn Chamber", "Toxins Lab", ""),
    ("Sci Lockers", "R&D", ""),
    ("Mech Storage", "Robotics", ""),
]

# shuttle footprints for the preview (the builder places the real ports)
DOCKS = [
    ("Arrivals shuttle", (62, 3, 69, 18)),
    ("Escape shuttle",   (205, 88, 223, 120)),
    ("Cargo shuttle",    (5, 120, 12, 132)),
    ("Mining shuttle",   (7, 152, 12, 159)),
    ("Labour shuttle",   (7, 68, 12, 77)),
    ("Pod",              (189, 16, 192, 20)),
    ("Pod",              (203, 124, 207, 127)),
]

# The engine: a block copied tile for tile from Hippie Station, placed by build_dmm.paste_engine().
# Swappable: ENGINE picks which. "tesla" is Hippie's port engineering (particle accelerator, field generators,
# emitters, coils, its own SMES), the engine Hippie's bots start every round. "sm" is Hippie's supermatter room,
# which Hippie never lights: the bots' setup there left the chamber empty in a test (0 mol, 50% at 40 min).
# src = Hippie rect (DM coords, inclusive), at = where its top-left lands here, door = our door into it,
# l1/l2 = Hippie tiles where its layer-1 (generator side) and layer-2 (emitters) cables leave the block.
ENGINE = "tesla"
ENGINES = {
    "tesla": dict(src=(51, 51, 83, 71), at=(101, 163), door=(125, 162), l1=(83, 70), l2=(83, 70), rect=(101, 163, 134, 184),
                  label="TESLA\n(Hippie's port engineering)"),
    "sm": dict(src=(96, 53, 127, 76), at=(101, 163), door=(117, 162), l1=(96, 73), l2=(117, 76), rect=(101, 163, 133, 187),
               label="SUPERMATTER\n(Hippie's engine room)"),
}
ENGINE_SRC = ENGINES[ENGINE]["src"]
ENGINE_AT = ENGINES[ENGINE]["at"]
ENGINE_DOOR = ENGINES[ENGINE]["door"]
ENGINE_RECT = ENGINES[ENGINE]["rect"]

# Xenobiology: Hippie's whole lab (pens with windoors, console room, kill room), its west door meeting the airlock
XENO_SRC = (164, 84, 178, 110)
XENO_AT = (137, 84)
XENO_DOOR = (136, 92)  # Xeno Airlock's east wall, in front of Hippie's west door
XENO_RECT = (137, 84, 152, 111)

# outside the hull
SOLARS = [
    ("NW array", (-6, 34, 1, 52)),
    ("NE array", (212, 34, 219, 52)),
    ("SW array", (22, 174, 50, 180)),
    ("SE array", (158, 176, 188, 182)),
]
# open catwalks over space (control rooms out to their panels)
CATWALKS = [(1, 42, 3, 44), (210, 42, 212, 44), (32, 172, 34, 174), (172, 174, 174, 176)]
RADIATORS = [("Engine radiators", (138, 166, 144, 194))]
ASTEROIDS = [(-3, 4, 6), (40, -6, 6), (150, -2, 6), (212, -6, 6),
             (-2, 92, 5), (224, 140, 4), (68, 184, 5)]
DERELICTS = [("Derelict", (180, -22, 196, -8))]
# external airlocks, one tile on a hull wall
EXT_AIRLOCKS = [(134, 48), (136, 180), (76, 178)]
