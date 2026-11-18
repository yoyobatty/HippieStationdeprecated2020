"""Alias table (plan A1): read maps from other codebases as if they were 2020 tg maps, so parse.py and every judge
treat them like the human maps we already have.

    alias.apply(m)      # rewrite a dmm.Map in place; returns counts of what was renamed

What changes between codebases, and what each rewrite does:
    areas   modern tg and Paradise put everything under /area/station/...; tg 2021+ renamed departments
            (/area/command, /area/commons, /area/service, /area/cargo, /area/engineering/main ...). Both go back to
            the 2020 paths that studies/stations.py GROUPS and walk.py's places know.
    turfs   Paradise: /turf/simulated/wall, /turf/simulated/floor, /turf/space.
    windows Paradise: /obj/effect/spawner/window/... (grille + glass spawner).
    wall pieces  tg 2021+ and Paradise: .../directional/north and .../auto_name/... subtypes instead of pixel offsets.
            The suffix goes, and the pixel offset (and a light's dir) it stood for is written in.
    density types our build doesn't have are dense by name (kit.DENSE_HINTS) when they look like furniture.
"""
import re

AREAS = [
    # AI
    ("/area/ai/satellite", "/area/ai_monitored/turret_protected/aisat"),
    ("/area/ai/upload/foyer", "/area/ai_monitored/turret_protected/ai_upload_foyer"),
    ("/area/ai/upload", "/area/ai_monitored/turret_protected/ai_upload"),
    ("/area/ai", "/area/ai_monitored/turret_protected/ai"),
    ("/area/aisat", "/area/ai_monitored/turret_protected/aisat"),
    ("/area/turret_protected", "/area/ai_monitored/turret_protected"),
    ("/area/telecomms", "/area/tcommsat"),
    ("/area/ai_monitored/command/storage/eva", "/area/ai_monitored/storage/eva"),
    ("/area/ai_monitored/command/nuke_storage", "/area/ai_monitored/nuke_storage"),
    ("/area/ai_monitored/command", "/area/bridge"),
    # cargo
    ("/area/cargo/qm", "/area/quartermaster/qm"),
    ("/area/cargo", "/area/quartermaster"),
    ("/area/supply/qm", "/area/quartermaster/qm"),
    ("/area/supply", "/area/quartermaster"),
    # command
    ("/area/command/heads_quarters/captain", "/area/crew_quarters/heads/captain"),
    ("/area/command/heads_quarters/hop", "/area/crew_quarters/heads/hop"),
    ("/area/command/heads_quarters/hos", "/area/crew_quarters/heads/hos"),
    ("/area/command/heads_quarters/cmo", "/area/crew_quarters/heads/cmo"),
    ("/area/command/heads_quarters/ce", "/area/crew_quarters/heads/chief"),
    ("/area/command/heads_quarters/rd", "/area/crew_quarters/heads/hor"),
    ("/area/command/heads_quarters/qm", "/area/quartermaster/qm"),
    ("/area/command/heads_quarters", "/area/crew_quarters/heads"),
    ("/area/command/eva", "/area/ai_monitored/storage/eva"),
    ("/area/command/gateway", "/area/gateway"),
    ("/area/command/teleporter", "/area/teleporter"),
    ("/area/command/vault", "/area/ai_monitored/nuke_storage"),
    ("/area/command/meeting_room", "/area/bridge/meeting_room"),
    ("/area/command/corporate_showroom", "/area/bridge/showroom/corporate"),
    ("/area/command/customs", "/area/security/checkpoint/customs"),
    ("/area/command/bridge", "/area/bridge"),
    ("/area/command", "/area/bridge"),
    # commons (tg) and public (Paradise)
    ("/area/commons/storage", "/area/storage"),
    ("/area/commons/vacant_room", "/area/vacant_room"),
    ("/area/commons", "/area/crew_quarters"),
    ("/area/public/storage", "/area/storage"),
    ("/area/public/vacant_office", "/area/vacant_room/office"),
    ("/area/public/construction", "/area/construction"),
    ("/area/public", "/area/crew_quarters"),
    # engineering
    ("/area/engineering/atmospherics_engine", "/area/engine/atmospherics_engine"),
    ("/area/engineering/atmos", "/area/engine/atmos"),
    ("/area/engineering/main", "/area/engine/engineering"),
    ("/area/engineering/engine", "/area/engine/engineering"),
    ("/area/engineering/controlroom", "/area/engine/engineering"),
    ("/area/engineering/control", "/area/engine/engineering"),
    ("/area/engineering/gravitygenerator", "/area/engine/gravity_generator"),
    ("/area/engineering/tech_storage", "/area/storage/tech"),
    ("/area/engineering/storage/tech", "/area/storage/tech"),
    ("/area/engineering/storage/tcomms", "/area/storage/tcom"),
    ("/area/engineering", "/area/engine"),
    # legal (Paradise)
    ("/area/legal/courtroom", "/area/security/courtroom"),
    ("/area/legal", "/area/lawoffice"),
    # medical
    ("/area/medical/treatment_center", "/area/medical/medbay/central"),
    ("/area/medical/reception", "/area/medical/medbay/lobby"),
    ("/area/medical/cloning", "/area/medical/genetics/cloning"),
    # science
    ("/area/science/ordnance", "/area/science/mixing"),
    ("/area/science/toxins", "/area/science/mixing"),
    ("/area/science/rnd", "/area/science/lab"),
    # security
    ("/area/security/armory", "/area/ai_monitored/security/armory"),
    ("/area/security/office", "/area/security/main"),
    ("/area/security/detective", "/area/security/detectives_office"),
    ("/area/security/permabrig", "/area/security/prison"),
    # service
    ("/area/service/theater", "/area/crew_quarters/theatre"),
    ("/area/service/theatre", "/area/crew_quarters/theatre"),
    ("/area/service/hydroponics", "/area/hydroponics"),
    ("/area/service/janitor", "/area/janitor"),
    ("/area/service/chapel/office", "/area/chapel/office"),
    ("/area/service/chapel", "/area/chapel/main"),
    ("/area/service/library", "/area/library"),
    ("/area/service/lawoffice", "/area/lawoffice"),
    ("/area/service", "/area/crew_quarters"),
    # the rest
    ("/area/solars", "/area/solar"),
    ("/area/misc/space", "/area/space"),  # Bee
    ("/area/docking/arrival", "/area/hallway/secondary/entry"),
    ("/area/docking", "/area/hallway/secondary/docking"),
    ("/area/router", "/area/hallway/primary/router"),  # Citadel CogStation: hall junctions
    ("/area/escapepodbay", "/area/hallway/secondary/escape_pods"),
]
TURFS = [("/turf/simulated/wall", "/turf/closed/wall"), ("/turf/simulated/mineral", "/turf/closed/mineral"),
         ("/turf/unsimulated/wall", "/turf/closed/indestructible"), ("/turf/simulated", "/turf/open/floor"),
         ("/turf/unsimulated", "/turf/open/indestructible"), ("/turf/space", "/turf/open/space")]
OBJS = [("/obj/effect/spawner/window", "/obj/effect/spawner/structure/window"),
        ("/obj/machinery/atmospherics/unary", "/obj/machinery/atmospherics/components/unary")]  # Paradise vents
DIRECTIONAL = re.compile(r"^(.*?)(?:/auto_name)?/directional/(north|south|east|west)$")
PIXEL = {"north": ("pixel_y", 32, 1), "south": ("pixel_y", -32, 2), "east": ("pixel_x", 32, 4), "west": ("pixel_x", -32, 8)}


def _prefix_map(path, table):
    for old, new in table:
        if path == old or path.startswith(old + "/"):
            return new + path[len(old):]
    return path


def area(path):
    if path.startswith("/area/station/"):
        path = "/area/" + path[len("/area/station/"):]
    return _prefix_map(path, AREAS)


def needs(m):
    """True when the map uses paths from a later or other codebase."""
    for body in m.keys.values():
        if "/area/station/" in body or "/turf/simulated" in body or "/directional/" in body or \
                "/area/commons" in body or "/area/command/" in body or "/area/cargo" in body:
            return True
    return False


def apply(m):
    from collections import Counter
    from forge import kit
    dense = kit.dense_types() or set()
    n = Counter()
    memo = {}
    for t in m.tiles.values():
        if t.area is not None:
            a = t.area.path
            if a not in memo:
                memo[a] = area(a)
            if memo[a] != a:
                t.area.path = memo[a]
                n["area"] += 1
        if t.turf is not None:
            p = _prefix_map(t.turf.path, TURFS)
            if p != t.turf.path:
                t.turf.path = p
                n["turf"] += 1
        for o in t.objs:
            p = _prefix_map(o.path, OBJS)
            g = DIRECTIONAL.match(p)
            if g:
                p, d = g.group(1), g.group(2)
                var, val, dirn = PIXEL[d]
                if o.get(var) is None:
                    o.vars.append((var, str(val)))
                if p.startswith("/obj/machinery/light") and o.get("dir") is None:
                    o.vars.append(("dir", str(dirn)))
                n["directional"] += 1
            if p != o.path:
                o.path = p
                n["obj"] += 1
            if p not in dense and o.get("density") is None and p.startswith(kit.DENSE_HINTS) and \
                    not p.startswith("/obj/structure/window"):
                o.vars.append(("density", "1"))
                n["dense_by_name"] += 1
    return n
