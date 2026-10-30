"""Pools Hippie atmos bench runs: per scene and engine, the mean and range of each number over the runs.
Usage: python tools/atmos_bench/compare_runs.py <runs dir> <prefix_a> <prefix_b> <runs>"""
import re
import statistics
import sys

base, a, b, runs = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
SCENES = ["Calm station", "Gas release", "Plasma fire", "Hull breaches"]


def scenes(path):
	text = open(path, encoding="utf-8", errors="replace").read()
	out = {}
	for scene in SCENES:
		m = re.search(re.escape(scene) + r" - .*?(?=\n\n|\Z)", text, re.S)
		block = m.group(0) if m else ""

		def num(pattern):
			x = re.search(pattern, block)
			return float(x.group(1)) if x else float("nan")
		out[scene] = {
			"turf processing (ms over the scene)": num(r"  active turfs: ([\d.]+) ms total"),
			"all of SSair (ms over the scene)": num(r"  all of SSair: ([\d.]+) ms total"),
			"awake turfs (average)": num(r"active turfs: average ([\d.]+)"),
			"total moles on the station after": num(r"over \d+ open station turfs: (\d+) mol in all"),
			"turfs with 1+ mol N2O after": num(r"on (\d+) turfs with a mole or more"),
			"turfs under 20 kPa after": num(r"(\d+) turfs under 20 kPa"),
			"turfs over 100 C after": num(r"(\d+) turfs over 100 C"),
		}
	return out


data = {}
for prefix in (a, b):
	data[prefix] = [scenes(f"{base}/{prefix}_{r}/results.txt") for r in range(1, runs + 1)]

for scene in SCENES:
	print(f"== {scene}")
	for key in data[a][0][scene]:
		cells = []
		for prefix in (a, b):
			values = [run[scene][key] for run in data[prefix]]
			cells.append(f"{prefix} {statistics.mean(values):.0f} [{', '.join(f'{v:.0f}' for v in values)}]")
		print(f"  {key}: " + " | ".join(cells))
