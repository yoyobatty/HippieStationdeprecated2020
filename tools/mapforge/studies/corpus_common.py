"""Shared helpers for the generator-target studies (skeleton_types, dept_scaling, dept_adjacency, space_sizes).

Every study reads all human maps through forge/parse.py (parse.humans(): the 9 local maps and the corpus), measures
each map once, caches the per-map result in data/mapforge/gen_targets/<study>.json (keyed by the map file's size and
mtime, so an edited map is measured again), and reports bands.

Bands count each map FAMILY once (corpus_index.py groups remakes: Meta on tg, bee and paradise is one family), so the
Meta and Box lines don't outvote everything else. A family's value is the median of its members. The band is the
10th..90th percentile over families (min..max when fewer than 10), as the judges already use with 20+ maps.

    from corpus_common import maps, measure_all, band, family_values
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from forge import parse  # noqa: E402

OUT = os.path.join(parse.ROOT, "data", "mapforge", "gen_targets")


def maps():
    """[(name, family)] for every human map. Local maps that a corpus map names as its family share it."""
    cm = parse.corpus_maps()
    out = [(n, n) for n in parse.MAPS]
    out += [(n, v.get("family") or n) for n, v in cm.items()]
    return out


def _stamp(name):
    cm = parse.corpus_maps().get(name)
    p = cm["path"] if cm else parse.map_path(name)
    try:
        st = os.stat(p)
        return "%d:%d" % (st.st_size, int(st.st_mtime))
    except OSError:
        return "?"


def measure_all(study, fn, names=None, fresh=False, version=1):
    """{name: fn(SemanticMap)} for every human map, cached per study in data/mapforge/gen_targets/<study>.json.
    fn must return JSON-able data. Bump version when fn changes what it measures."""
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, study + ".json")
    cache = {}
    if os.path.exists(path) and not fresh:
        try:
            cache = json.load(open(path))
        except ValueError:
            cache = {}
    if cache.get("_version") != version:
        cache = {"_version": version}
    names = names or [n for n, _ in maps()]
    res = {}
    dirty = False
    for n in names:
        st = _stamp(n)
        c = cache.get(n)
        if c and c.get("_stamp") == st:
            res[n] = c["v"]
            continue
        sm = parse.load(n)
        v = fn(sm)
        cache[n] = {"_stamp": st, "v": v}
        res[n] = v
        dirty = True
    if dirty:
        json.dump(cache, open(path, "w"), indent=0, sort_keys=True)
    return res


def measure_one(path, fn):
    """fn on a built map (a .dmm path or a name in data/mapforge/), not cached: for comparing a build with the bands."""
    p = path
    if not os.path.exists(p):
        q = os.path.join(parse.ROOT, "data", "mapforge", path + ".dmm")
        p = q if os.path.exists(q) else path
    return fn(parse.load(p))


def median(vs):
    vs = sorted(v for v in vs if v is not None)
    if not vs:
        return None
    n = len(vs)
    return vs[n // 2] if n % 2 else 0.5 * (vs[n // 2 - 1] + vs[n // 2])


def quant(vs, q):
    vs = sorted(v for v in vs if v is not None)
    if not vs:
        return None
    i = q * (len(vs) - 1)
    lo = int(i)
    hi = min(lo + 1, len(vs) - 1)
    return vs[lo] + (vs[hi] - vs[lo]) * (i - lo)


def family_values(per_map, key):
    """{family: median of key over its maps}. key is a callable(value) -> number or None."""
    fam = dict(maps())
    acc = {}
    for n, v in per_map.items():
        x = key(v)
        if x is None:
            continue
        acc.setdefault(fam.get(n, n), []).append(x)
    return {f: median(xs) for f, xs in acc.items()}


def band(per_map, key):
    """(lo, median, hi, n_families): 10th..90th percentile over families, min..max under 10 families."""
    fv = list(family_values(per_map, key).values())
    if not fv:
        return None, None, None, 0
    if len(fv) < 10:
        return min(fv), median(fv), max(fv), len(fv)
    return quant(fv, 0.1), median(fv), quant(fv, 0.9), len(fv)


def fit_power(xs, ys):
    """Least squares on logs: y = a * x^b. Returns (a, b, r2) or None."""
    import math
    pts = [(math.log(x), math.log(y)) for x, y in zip(xs, ys) if x and y and x > 0 and y > 0]
    if len(pts) < 3:
        return None
    n = float(len(pts))
    mx = sum(p[0] for p in pts) / n
    my = sum(p[1] for p in pts) / n
    sxx = sum((p[0] - mx) ** 2 for p in pts)
    sxy = sum((p[0] - mx) * (p[1] - my) for p in pts)
    if sxx == 0:
        return None
    b = sxy / sxx
    a = math.exp(my - b * mx)
    ss_tot = sum((p[1] - my) ** 2 for p in pts)
    ss_res = sum((p[1] - (my + b * (p[0] - mx))) ** 2 for p in pts)
    return a, b, (1 - ss_res / ss_tot) if ss_tot else 0.0


def pearson(xs, ys):
    pts = [(x, y) for x, y in zip(xs, ys) if x is not None and y is not None]
    n = float(len(pts))
    if n < 3:
        return None
    mx = sum(p[0] for p in pts) / n
    my = sum(p[1] for p in pts) / n
    sx = sum((p[0] - mx) ** 2 for p in pts) ** 0.5
    sy = sum((p[1] - my) ** 2 for p in pts) ** 0.5
    if not sx or not sy:
        return None
    return sum((p[0] - mx) * (p[1] - my) for p in pts) / (sx * sy)


NOT_CREW = ("hangover", "depsec", "prisoner", "ai", "cyborg", "assistant", "positronic", "pai")


def crew(sm):
    """Roundstart job slots: job start landmarks on the station level, not assistants, AI, cyborgs, prisoners,
    departmental-security copies or tg's hangover spawns (tg maps put hundreds of those down)."""
    n = 0
    for (x, y, z), t in sm.m.tiles.items():
        if z != sm.z:
            continue
        for a in t.objs:
            if a.path.startswith("/obj/effect/landmark/start/"):
                first = a.path[len("/obj/effect/landmark/start/"):].split("/")[0]
                if first not in NOT_CREW:
                    n += 1
    return n


def save(study, data):
    """Write a study's targets (bands, fits) to data/mapforge/gen_targets/<study>_targets.json."""
    os.makedirs(OUT, exist_ok=True)
    p = os.path.join(OUT, study + "_targets.json")
    json.dump(data, open(p, "w"), indent=1, sort_keys=True)
    return p


def fmt(v, nd=3):
    if v is None:
        return "-"
    if isinstance(v, float):
        return ("%." + str(nd) + "f") % v
    return str(v)
