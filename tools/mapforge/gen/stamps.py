"""The stock-room library for the room stage (S3): every room of every human map (parse.humans(), all 38: the user's
ruling 2026-11-22) that can be copied whole into this codebase, by type.

    python tools/mapforge/gen/stamps.py            # build data/mapforge/gen/stamps.json, print coverage
    from gen import stamps; lib = stamps.library()  # {area type: [entry]}

An entry is one room (forge/room_stats.rooms: an area's largest piece): map, area, tiles, box w/h, and
  known     every object, turf and area path on its floor and inner walls resolves here (resolve(): known as it
            is, a later codebase's mapping helper or nav landmark dropped, else its nearest known ancestor 3+
            segments deep). A room with any path that resolves to nothing is never copied.
  fixed     how many paths the copy rewrites that way.
  faults    wall-piece faults on its own walls (piece stacks, both faces), the same count v6_rooms.src_faults uses;
            the room stage prefers the cleanest copy of a type.
Types are kept when 3+ families have a copyable room of them (studies/stamp_supply.py's "ready").
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, os.path.join(HERE, "..", "studies"))
sys.path.insert(0, HERE)
import corpus_common as CC  # noqa: E402
from forge import parse, room_stats as RS  # noqa: E402

OUT = os.path.join(parse.ROOT, "data", "mapforge", "gen", "stamps.json")
VERSION = 5


DROP_UNKNOWN = ("/obj/effect/mapping_helpers", "/obj/effect/landmark/navigate_destination")
# other codebases' names for things this one has (prefix -> prefix); checked with forge/typeindex
RENAME = (("/obj/machinery/alarm", "/obj/machinery/airalarm"), ("/obj/item/kirbyplants/random", "/obj/item/twohanded/required/kirbyplants/random"),
          ("/obj/item/kirbyplants", "/obj/item/twohanded/required/kirbyplants"),
          ("/obj/machinery/hologram/holopad", "/obj/machinery/holopad"), ("/obj/machinery/door_control", "/obj/machinery/button/door"),
          ("/obj/machinery/ai_status_display", "/obj/machinery/status_display/ai"))
_RES = {}
BARE = ("/turf/open/floor", "/turf/open", "/turf/closed", "/turf/closed/wall/mineral", "/obj/machinery", "/obj/structure",
        "/obj/item", "/obj/effect", "/obj/effect/decal", "/obj/effect/turf_decal", "/obj/machinery/atmospherics")


def resolve(path):
    """A path as this codebase can take it: itself when known; None for later codebases' mapping helpers and
    navigation landmarks (they only set vars or guide a UI); else its nearest known ancestor at least three segments
    deep (/obj/machinery/x: a layer-2 vent becomes a plain vent, a newer decal its parent decal); "" when none."""
    if path in _RES:
        return _RES[path]
    import gate
    for old, new in RENAME:
        if path == old or path.startswith(old + "/"):
            path2 = new + path[len(old):]
            r = resolve(path2) if path2 != path else ""
            _RES[path] = r if r else (new if gate.known(new) else "")
            return _RES[path]
    if gate.known(path):
        r = path
    elif path.startswith(DROP_UNKNOWN) or path.startswith(("/obj/item/", "/obj/machinery/digital_clock",
                                                          "/obj/structure/desk_bell")):
        r = None        # loose items and wall decor a later codebase added: dressing, left out of the copy
    else:
        r = ""
        parts = path.split("/")
        for k in range(len(parts) - 1, 3, -1):
            q = "/".join(parts[:k])
            if gate.known(q):
                r = q
                break
        # a bare base type draws nothing (magenta in the renderer, invisible in game): a floor turf becomes plain
        # plasteel, anything else counts as unknown
        if r in BARE:
            r = "/turf/open/floor/plasteel" if r == "/turf/open/floor" else ""
    _RES[path] = r
    return r


def _known_room(sm, tiles):
    ring = {(p[0] + dx, p[1] + dy) for p in tiles for dx in (-1, 0, 1) for dy in (-1, 0, 1)}
    bad, fixed = set(), 0
    for p in ring:
        t = sm.m.get(p[0], p[1], sm.z)
        if t is None:
            continue
        paths = [a.path for a in t.objs]
        if p in tiles:
            paths += [x for x in (t.tpath, t.apath) if x]
        for x in paths:
            r = resolve(x)
            if r == "":
                bad.add(x)
            elif r != x:
                fixed += 1
    return sorted(bad), fixed


def _faults(sm, tiles):
    ts = set(tiles)
    stacked = sum(1 for (p, side), v in sm.hung.items() if p in ts and len(v) > 1)
    return stacked


def build():
    fam = dict(CC.maps())
    out = {}
    for name, _ in CC.maps():
        sm = parse.load(name)
        for r in RS.rooms(sm):
            bad, fixed = _known_room(sm, r.tiles)
            xs = [p[0] for p in r.tiles]
            ys = [p[1] for p in r.tiles]
            out.setdefault(r.area, []).append(dict(
                map=name, family=fam.get(name, name), area=r.area, tiles=len(r.tiles),
                w=max(xs) - min(xs) + 1, h=max(ys) - min(ys) + 1, known=not bad, unknown=bad[:5], fixed=fixed,
                faults=_faults(sm, r.tiles), group=sm.group.get(r.tiles[0])))
    lib = {}
    for a, es in out.items():
        ok = [e for e in es if e["known"]]
        if len({e["family"] for e in ok}) >= 3:
            lib[a] = sorted(ok, key=lambda e: (e["faults"], e["tiles"]))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump(dict(_version=VERSION, lib=lib, all_types=len(out)), open(OUT, "w"), indent=0)
    return lib, out


_LIB = None


def library():
    global _LIB
    if _LIB is None:
        if not os.path.exists(OUT):
            build()
        d = json.load(open(OUT))
        _LIB = d["lib"]
    return _LIB


if __name__ == "__main__":
    lib, allt = build()
    from collections import Counter
    g = Counter(es[0]["group"] for es in lib.values())
    n = sum(len(v) for v in lib.values())
    print("types %d, copyable in 3+ families %d (%d rooms); by department %s" % (len(allt), len(lib), n,
                                                                              dict(g.most_common())))
    unk = Counter(p for es in allt.values() for e in es for p in e["unknown"])
    print("commonest unknown paths:", unk.most_common(8))
