"""Atmos A/B: the same small seeded atmos scenes on two testkit servers at once, compared side by side.

  python tools/atmos_ab/ab.py --b "atmos-engine=linda"                 # A: default params, B: LINDA
  python tools/atmos_ab/ab.py --a "atmos-model=zones" --b ""            # any world params for either side
  python tools/atmos_ab/ab.py --b-lib hippie_atmos_test                 # B loads another build of the engine DLL
  python tools/atmos_ab/ab.py --scenes fire,breach --seconds 30 --seeds 1,2
  python tools/atmos_ab/ab.py --no-build                               # reuse atmos_ab.mdme.dmb

Scenes (tools/atmos_ab/atmos_ab.dm): calm, release, fire, breach, reactions (a patch for each gas reaction; not in the
default set). Both servers run testbench (or --map) with no bot crew and no speed
limit. Prints, per scene: SSair ms per game second by stage (A, B, change), then the air at each quarter of the scene. Writes the
raw results to data/atmos_ab/<time>.json.
"""
import argparse
import json
import os
import sys
import threading
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "testkit"))
import tk  # noqa: E402

BUILD = "atmos_ab.mdme"
CHECK = "tools/atmos_ab/atmos_ab.dm"
OUT = os.path.join(tk.ROOT, "data", "atmos_ab")

# Sample fields worth showing, per scene
FIELDS = {
	"calm": ["mol", "kpa_mean", "kpa_min"],
	"release": ["mol", "n2o_tiles", "kpa_mean", "windy"],
	"fire": ["burning", "hottest_k", "plasma_mol", "kpa_mean", "tritium", "water_vapor"],
	"breach": ["kpa_mean", "kpa_min", "under_20kpa", "windy", "mol"],
	"tritium": ["hottest_k", "burning", "tritium", "water_vapor", "mol", "kpa_mean"],
	"reactions": ["hottest_k", "tritium", "water_vapor", "bz", "nitrous_oxide", "nitryl", "freon", "miasma", "research"],
}
# Stages to show, in order (others are summed into "other")
STAGES = ["all of SSair", "active turfs", "excited groups", "hotspots", "wind pushes", "atmos machinery", "pipe networks",
	"heat through walls", "engine: packing", "engine: native", "engine: following up", "follow-up: air", "follow-up: turns",
	"follow-up: groups", "follow-up: wind", "follow-up: react", "follow-up: redraw", "follow-up: hot"]


def run_side(label, params, scenes, seconds, seeds, results, dmb, port, map_name="testbench"):
	server = None
	try:
		server = tk.start(map_name, port=port, speed=0, params=params, dmb=dmb)
		for scene in scenes:
			for seed in seeds:
				r = server.call("call", ref="global", proc="atmos_ab_scene", args=[scene, seconds, seed], depth=4, timeout=600)
				results[(label, scene, seed)] = r
				print("  %s %s seed %s: %.1f s real" % (label, scene, seed, (r or {}).get("real_seconds", -1)), flush=True)
	except Exception as err:  # one side failing shows up as missing numbers, with the reason
		results[(label, "error", 0)] = str(err)
		print("  %s failed: %s" % (label, err), flush=True)
	finally:
		if server:
			try:
				tk.stop(server)
			except Exception:
				pass


def change(a, b):
	if a is None or b is None:
		return ""
	if a == 0:
		return "" if b == 0 else "new"
	return "%+.0f%%" % ((b - a) / abs(a) * 100)


def fmt(v):
	if v is None:
		return "-"
	if isinstance(v, float):
		return ("%.3f" % v) if abs(v) < 10 else ("%.1f" % v)
	return str(v)


def average(rows):
	"""Several seeds' results -> one, numbers averaged"""
	rows = [r for r in rows if isinstance(r, dict)]
	if not rows:
		return None
	ms = {}
	for r in rows:
		for k, v in r["ms_per_s"].items():
			ms[k] = ms.get(k, 0) + v / len(rows)
	samples = []
	for i in range(min(len(r["samples"]) for r in rows)):
		s = {}
		for k in rows[0]["samples"][i]:
			vals = [r["samples"][i][k] for r in rows]
			s[k] = sum(vals) / len(vals)
		samples.append(s)
	return {"ms_per_s": ms, "samples": samples, "engine": rows[0]["engine"], "real_seconds": sum(r["real_seconds"] for r in rows)}


def table(rows, widths):
	for row in rows:
		print("  " + "  ".join(str(c).rjust(w) if i else str(c).ljust(w) for i, (c, w) in enumerate(zip(row, widths))))


def report(scenes, seeds, results, a_name, b_name):
	for scene in scenes:
		a = average([results.get(("A", scene, s)) for s in seeds])
		b = average([results.get(("B", scene, s)) for s in seeds])
		print()
		print("== %s  (A %s: %s | B %s: %s)" % (scene, a_name, a and a["engine"], b_name, b and b["engine"]))
		if not a or not b:
			print("  missing results")
			continue
		rows = [["SSair ms per game second", "A", "B", "B vs A"]]
		shown = set()
		for stage in STAGES:
			va, vb = a["ms_per_s"].get(stage), b["ms_per_s"].get(stage)
			if (va or 0) < 0.005 and (vb or 0) < 0.005:
				continue
			shown.add(stage)
			rows.append([stage, fmt(va), fmt(vb), change(va, vb)])
		table(rows, [28, 9, 9, 8])
		print()
		fields = FIELDS.get(scene, ["mol", "kpa_mean"])
		head = ["t (s)"]
		for f in fields:
			head += [f + " A", "B"]
		rows = [head]
		for sa, sb in zip(a["samples"], b["samples"]):
			row = ["%.0f" % sa["t"]]
			for f in fields:
				row += [fmt(sa[f]), fmt(sb[f])]
			rows.append(row)
		table(rows, [6] + [11, 9] * len(fields))


def main():
	ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	ap.add_argument("--a", default="", help="world params for A")
	ap.add_argument("--b", default="", help="world params for B")
	ap.add_argument("--a-lib", default="", help="atmos-lib for A (another build of the DLL)")
	ap.add_argument("--b-lib", default="", help="atmos-lib for B")
	ap.add_argument("--scenes", default="calm,release,fire,breach")
	ap.add_argument("--seconds", type=float, default=16)
	ap.add_argument("--seeds", default="1")
	ap.add_argument("--no-build", action="store_true")
	ap.add_argument("--map", default="testbench", help="testbench (default) or hippiestation, metastation: calm runs on its station")
	opts = ap.parse_args()

	scenes = [s for s in opts.scenes.split(",") if s]
	seeds = [int(s) for s in opts.seeds.split(",") if s]
	a_params = "&".join(p for p in [opts.a, opts.a_lib and "atmos-lib=" + opts.a_lib] if p)
	b_params = "&".join(p for p in [opts.b, opts.b_lib and "atmos-lib=" + opts.b_lib] if p)
	started = time.time()
	dmb = os.path.join(tk.ROOT, BUILD + ".dmb")
	if not opts.no_build or not os.path.exists(dmb):
		dmb = tk.build([CHECK], name=BUILD)
	print("A: %s\nB: %s" % (a_params or "(defaults)", b_params or "(defaults)"), flush=True)
	results = {}
	ports = [p for p in tk.PORTS if tk.port_free(p) and not os.path.exists(tk.server_file(p))][:2]
	if len(ports) < 2:
		sys.exit("no two free testkit ports")
	threads = [threading.Thread(target=run_side, args=(label, params, scenes, opts.seconds, seeds, results, dmb, port, opts.map))
		for (label, params), port in zip((("A", a_params), ("B", b_params)), ports)]
	for t in threads:
		t.start()
	for t in threads:
		t.join()
	for key in (("A", "error", 0), ("B", "error", 0)):
		if key in results:
			print("%s failed: %s" % (key[0], results[key]))
	report(scenes, seeds, results, a_params or "defaults", b_params or "defaults")
	os.makedirs(OUT, exist_ok=True)
	path = os.path.join(OUT, time.strftime("%Y%m%d-%H%M%S") + ".json")
	with open(path, "w") as f:
		json.dump({"a": a_params, "b": b_params, "results": {"%s|%s|%s" % k: v for k, v in results.items()}}, f, indent=1)
	print("\n%.0f s in all; raw results in %s" % (time.time() - started, os.path.relpath(path, tk.ROOT)))


if __name__ == "__main__":
	main()
