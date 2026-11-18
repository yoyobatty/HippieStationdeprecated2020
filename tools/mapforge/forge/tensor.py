"""Semantic tile tensors (plan C2 input): a map as C x H x W channels a network reads, the same for every codebase
(it is built from parse.py's SemanticMap, after forge/alias.py).

    python tools/mapforge/forge/tensor.py MetaStation        # build (cached) and print channel sums

Cached as data/mapforge/tensors/<name>.npz (keyed by the map file's hash): planes uint8 [C, H, W], row 0 = map y 1
(so plane[c, y-1, x-1] is tile x,y), and the station-floor mask.
"""
import hashlib
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import parse  # noqa: E402

CACHE = os.path.join(parse.ROOT, "data", "mapforge", "tensors")
CHANNELS = ["space", "wall", "glass", "door", "floor", "dense", "furniture", "hung_n", "hung_s", "hung_e", "hung_w",
            "hall", "maint", "dept", "decal", "light", "vent", "item", "area_edge"]
C = len(CHANNELS)
CI = {n: i for i, n in enumerate(CHANNELS)}
SIDE_CH = {1: CI["hung_n"], 2: CI["hung_s"], 4: CI["hung_e"], 8: CI["hung_w"]}
VENTS = ("/obj/machinery/atmospherics/components/unary/vent_pump", "/obj/machinery/atmospherics/components/unary/vent_scrubber")
ROCK = ("/turf/closed/mineral", "/turf/closed/indestructible/rock", "/turf/closed/wall/mineral/snow")
VERSION = 3  # bump when alias.py or parse.py change what a map reads as


def _key(name):
    cm = parse.corpus_maps().get(name)
    path = cm["path"] if cm else parse.map_path(name)
    h = hashlib.sha1(open(path, "rb").read()).hexdigest()[:12]
    if os.path.exists(name):  # a .dmm path (generated trial builds): its file name, the hash tells copies apart
        name = os.path.splitext(os.path.basename(name))[0]
    return "%s_%s_v%d" % (name.replace(":", "_").replace("/", "_"), h, VERSION)


def build(sm):
    W, H = sm.m.maxx, sm.m.maxy
    t = np.zeros((C, H, W), dtype=np.uint8)
    mask = np.zeros((H, W), dtype=np.uint8)
    for (x, y), c in sm.cls.items():
        i, j = y - 1, x - 1
        # outside the station reads as space: planet snow and asteroid rock round a station are a codebase's
        # setting, not its mapping, and a generator makes neither
        g0 = sm.group.get((x, y))
        if c == "F" and g0 is None:
            c = "S"
        elif c == "W" and (x, y) not in sm.glass and g0 is None:
            tl = sm.m.get(x, y, sm.z)
            if tl is not None and tl.turf is not None and tl.turf.path.startswith(ROCK):
                c = "S"
        if c == "S":
            t[CI["space"], i, j] = 1
        elif c == "W":
            t[CI["wall"], i, j] = 1
            if (x, y) in sm.glass:
                t[CI["glass"], i, j] = 1
        elif c == "D":
            t[CI["door"], i, j] = 1
        else:
            t[CI["floor"], i, j] = 1
            g = sm.group.get((x, y))
            if g in ("hall", "arrivals", "escape"):
                t[CI["hall"], i, j] = 1
            elif g == "maint":
                t[CI["maint"], i, j] = 1
            elif g and not g.startswith("other:") and g not in ("shuttle", "solar"):
                t[CI["dept"], i, j] = 1
            if g and not g.startswith("other:") and g not in ("shuttle", "solar"):
                mask[i, j] = 1
            a = sm.area.get((x, y))
            for dx, dy in parse.DIRS:
                q = (x + dx, y + dy)
                if sm.cls.get(q) == "F" and sm.area.get(q) != a:
                    t[CI["area_edge"], i, j] = 1
                    break
    for (x, y) in sm.dense:
        t[CI["dense"], y - 1, x - 1] = 1
    for (x, y) in sm.furn:
        t[CI["furniture"], y - 1, x - 1] = 1
    for ((x, y), s), v in sm.hung.items():
        if v:
            t[SIDE_CH[s], y - 1, x - 1] = 1
    for (x, y) in sm.decals:
        t[CI["decal"], y - 1, x - 1] = 1
    for (x, y) in sm.items:
        t[CI["item"], y - 1, x - 1] = 1
    for (x, y, z), tile in sm.m.tiles.items():
        if z != sm.z or sm.cls.get((x, y)) != "F":
            continue
        for o in tile.objs:
            if o.path.startswith("/obj/machinery/light") and not o.path.startswith("/obj/machinery/light_switch"):
                t[CI["light"], y - 1, x - 1] = 1
            elif o.path.startswith(VENTS):
                t[CI["vent"], y - 1, x - 1] = 1
    return t, mask


def load(name):
    os.makedirs(CACHE, exist_ok=True)
    f = os.path.join(CACHE, _key(name) + ".npz")
    if os.path.exists(f):
        d = np.load(f)
        return d["planes"], d["mask"]
    planes, mask = build(parse.load(name))
    np.savez_compressed(f, planes=planes, mask=mask)
    return planes, mask


# the 8 symmetries of the square; hung-side channels follow the turn (a piece on the north wall of a tile turned
# 90 degrees anticlockwise hangs on the west wall)
def dihedral(a, k):
    """a: [C, H, W] (row 0 = south). k in 0..7: rotations by 90 anticlockwise (k % 4), then a mirror (k >= 4)."""
    n, s, e, w = CI["hung_n"], CI["hung_s"], CI["hung_e"], CI["hung_w"]
    out = a
    for _ in range(k % 4):
        # rows run south to north, so np.rot90 on (y, x) axes with k=-1 turns the map anticlockwise as seen in game
        out = np.rot90(out, -1, axes=(1, 2))
        out = out[_perm({n: w, w: s, s: e, e: n})]
    if k >= 4:
        out = out[:, :, ::-1]
        out = out[_perm({e: w, w: e})]
    return np.ascontiguousarray(out)


def _perm(move):
    """Channel order so that the channel moving to slot d comes from move-inverse."""
    idx = list(range(C))
    for src, dst in move.items():
        idx[dst] = src
    return idx


if __name__ == "__main__":
    import time
    t0 = time.time()
    p, m = load(sys.argv[1] if len(sys.argv) > 1 else "MetaStation")
    print("shape", p.shape, "station floor", int(m.sum()), "(%.1fs)" % (time.time() - t0))
    for i, n in enumerate(CHANNELS):
        print("  %-10s %6d" % (n, int(p[i].sum())))
