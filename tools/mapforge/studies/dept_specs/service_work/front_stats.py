"""Stock (or any) map: how each service room meets the station - what its airlocks open on, what its counters face,
its size - for the spec's numbers.

    python tools/mapforge/studies/dept_specs/service_work/front_stats.py [dmm ...]     # default: the 8 stock maps
"""
import os
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
MF = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, MF)
sys.path.insert(0, os.path.join(MF, "gen", "learn"))
from forge import corpus as CO, dmm  # noqa: E402
import fn_service as S  # noqa: E402

FAMS = ("kitchen", "coldroom", "bar", "hydro", "garden", "janitor", "theatre", "chapel", "chapel_office", "library",
        "law", "dorms", "toilet", "locker", "fitness", "tools")


def short(a):
    if a.startswith("/area/hallway/primary"):
        return "HALL"
    if a.startswith("/area/maintenance"):
        return "maint"
    return S.fam(a) or a.replace("/area/", "")


def stats(m, name, out=print):
    c = S.Ctx(m)
    out("== %s" % name)
    for f in FAMS:
        t = c.tiles.get(f)
        if not t:
            continue
        doors = Counter(short(a) for _, a in c.joins(f))
        cnt = Counter(short(a) for _, a in S.serving_counters(c, (f,)))
        pub = sum(1 for p in t if p in c.public)
        acc = Counter(",".join(sorted(S._access(c.doors[d]))) or "-" for d, _ in c.joins(f))
        out("  %-13s %4d tiles  public %3d  doors %s  counters onto %s  access %s" % (
            f, len(t), pub, dict(doors), dict(cnt), dict(acc)))


if __name__ == "__main__":
    names = sys.argv[1:] or [os.path.join(S.ROOT, "_maps", "map_files", rel) for rel in CO.MAPS]
    for n in names:
        stats(dmm.read(n), os.path.basename(n))
