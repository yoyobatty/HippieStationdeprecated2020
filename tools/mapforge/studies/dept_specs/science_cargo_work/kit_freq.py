"""Scratch: per room type (science, cargo), in how many of the 8 stock maps each kit family appears, and the median
floor size. python kit_freq.py > kit_freq.txt"""
import os, sys
from collections import Counter, defaultdict
HERE = os.path.dirname(os.path.abspath(__file__))
MF = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, MF)
from forge import corpus as CO, dmm
ROOT = os.path.abspath(os.path.join(MF, "..", ".."))
PRE = ("/area/science", "/area/crew_quarters/heads/hor", "/area/quartermaster", "/area/security/checkpoint/supply",
       "/area/security/checkpoint/science")
SKIP = ("/obj/structure/cable", "/obj/machinery/atmospherics/pipe", "/obj/structure/disposalpipe", "/obj/effect",
        "/obj/item/paper", "/obj/item/pen", "/obj/machinery/door/firedoor", "/obj/structure/window", "/obj/structure/grille")
def fam(p):
    parts = p.split("{")[0].split("/")
    return "/".join(parts[:5])
have = defaultdict(Counter); size = defaultdict(list)
for rel in CO.MAPS:
    m = dmm.read(os.path.join(ROOT, "_maps", "map_files", rel))
    seen = defaultdict(set); fl = Counter()
    for (x, y, z), t in m.tiles.items():
        if z != 1 or not t.apath.startswith(PRE):
            continue
        a = t.apath
        if t.tpath.startswith("/turf/open") and not CO.solid(t):
            fl[a] += 1
        for o in t.objs:
            if not o.path.startswith(SKIP):
                seen[a].add(fam(o.path))
    for a, s in seen.items():
        for f in s:
            have[a][f] += 1
        size[a].append(fl[a])
for a in sorted(have):
    v = sorted(size[a]); n = len(v)
    print("== %s  maps %d  floor median %d (%d-%d)" % (a, n, v[n // 2], v[0], v[-1]))
    print("   " + ", ".join("%s %d" % (f.replace("/obj/machinery/", "M/").replace("/obj/structure/", "S/").replace("/obj/item/", "I/"), c)
                            for f, c in have[a].most_common() if c >= max(2, n // 2)))
