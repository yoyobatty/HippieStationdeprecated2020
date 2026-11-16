#!/usr/bin/env python3
"""mapforge: hand-drawn blueprints -> finished, wired, piped, lit map areas.

    python tools/mapforge/mapforge.py build blueprints/hippie_service.py      # build + pictures + report
    python tools/mapforge/mapforge.py build <bp> --apply                      # also write into the real map
    python tools/mapforge/mapforge.py trace x1 y1 x2 y2 /area/a,/area/b      # skeleton of an existing zone
    python tools/mapforge/mapforge.py render map.dmm x1 y1 x2 y2 out.png
    python tools/mapforge/mapforge.py light blueprints/hippie_medbay.py      # boot it headless, picture with real lighting

Output: data/mapforge/<name>.dmm (a whole-map copy with the build in it), pictures in data/previews/mapforge/.
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from forge import build, render, check  # noqa: E402

ROOT = build.ROOT
OUT = os.path.join(ROOT, "data", "mapforge")


def cmd_build(args):
    bp_path = args.blueprint if os.path.isabs(args.blueprint) else os.path.join(HERE, args.blueprint) \
        if not os.path.exists(args.blueprint) else args.blueprint
    bp = build.load_blueprint(bp_path)
    b = build.Builder(bp).run()
    os.makedirs(OUT, exist_ok=True)
    out = os.path.join(OUT, bp.NAME + ".dmm")
    b.save(out)
    report = check.run(b)
    print("\n".join(b.notes))
    if b.outside_edits:
        by = {}
        for cls, p in b.trimmed:
            by.setdefault(cls, []).append("%d,%d" % p)
        for cls, ps in by.items():
            print("trimmed dead %s stub outside the zone: %s" % (cls, " ".join(ps)))
    for w in b.warn + report["problems"]:
        print("WARN", w)
    for line in report["info"]:
        print(line)
    if not args.no_render:
        x1, y1, x2, y2 = b.bounds(pad=2)
        before = after_tmp = None
        if b.base_path == "blank":
            b.base_path_render = out
        before = render.render(out if b.base_path == "blank" else b.base_path, os.path.join(render.PREVIEWS, bp.NAME + "_before.png"), region=(x1, y1, x2, y2))
        after = render.render(out, os.path.join(render.PREVIEWS, bp.NAME + "_after.png"), region=(x1, y1, x2, y2))
        from forge import overlay
        wires = overlay.draw(b, after, os.path.join(render.PREVIEWS, bp.NAME + "_wiring.png"), (x1, y1, x2, y2))
        render.sheet([before, after], ["before", "after (mapforge)"], os.path.join(render.PREVIEWS, bp.NAME + "_sheet.png"),
                     title=bp.NAME)
        print("pictures:", os.path.relpath(after, ROOT))
    if args.apply:
        build.dmm.merge_write(b.m, b.base_path)
        print("applied to", os.path.relpath(b.base_path, ROOT))


def cmd_light(args):
    """Boot the last build of a blueprint headless (run_zone_check.sh), snapshot the game's lighting, render it lit."""
    import subprocess
    bp_path = args.blueprint if os.path.exists(args.blueprint) else os.path.join(HERE, args.blueprint)
    bp = build.load_blueprint(bp_path)
    b = build.Builder(bp)
    x1, y1, x2, y2 = b.bounds(pad=2)
    snap = os.path.join(OUT, "light_%s.txt" % bp.NAME)
    dmm_path = os.path.join(OUT, bp.NAME + ".dmm")
    if args.reboot or not os.path.exists(snap) or os.path.getmtime(snap) < os.path.getmtime(dmm_path):
        print("booting %s headless for its lighting (a few minutes)..." % bp.NAME)
        env = dict(os.environ, WAIT="20")
        subprocess.run(["bash", os.path.join(HERE, "run_zone_check.sh"), bp.NAME, "%d,%d,%d,%d" % (x1, y1, x2, y2)],
                       cwd=ROOT, env=env, stdout=subprocess.DEVNULL)
    if not os.path.exists(snap):
        sys.exit("no lighting snapshot came back; see data/update_check_dd.log")
    out = os.path.join(render.PREVIEWS, bp.NAME + "_lit.png")
    render.render(dmm_path, out, region=(x1, y1, x2, y2), light=snap)
    print("lit picture:", os.path.relpath(out, ROOT))


def cmd_remodel(args):
    from forge import remodel
    path, areas, req = remodel.write(args.name, args.areas.split(","), args.keep.split(",") if args.keep else [])
    print("blueprint:", os.path.relpath(path, ROOT))
    for a in areas:
        print("  %-45s requires %s" % (a, ", ".join("%s x%d" % (p.rsplit("/", 1)[-1], n) for p, n in req[a]) or "-"))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd")
    p = sub.add_parser("build")
    p.add_argument("blueprint")
    p.add_argument("--apply", action="store_true")
    p.add_argument("--no-render", action="store_true")
    p = sub.add_parser("remodel")
    p.add_argument("name")
    p.add_argument("areas")
    p.add_argument("--keep", default="")
    p = sub.add_parser("light")
    p.add_argument("blueprint")
    p.add_argument("--reboot", action="store_true")
    p = sub.add_parser("render")
    p.add_argument("map")
    p.add_argument("coords", nargs=4, type=int)
    p.add_argument("out")
    args, rest = ap.parse_known_args()
    if args.cmd == "build":
        cmd_build(args)
    elif args.cmd == "remodel":
        cmd_remodel(args)
    elif args.cmd == "light":
        cmd_light(args)
    elif args.cmd == "render":
        render.render(args.map, args.out, region=tuple(args.coords))
    elif args.cmd == "trace":
        from forge import trace
        sys.argv = [sys.argv[0]] + rest
        trace.main()
    else:
        ap.print_help()


if __name__ == "__main__":
    main()
