"""One table comparing atmos bench builds against LINDA: speed and how the air behaved, each number the mean of the runs.
Usage: python tools/atmos_bench/scorecard.py <runs dir> <linda prefix> <runs> <prefix> [<prefix> ...]
A prefix can be name:runs if that build has a different number of runs. Runs are named <prefix>_1, <prefix>_2 and so on."""
import re
import statistics
import sys

base, linda, default_runs = sys.argv[1], sys.argv[2], int(sys.argv[3])
builds = sys.argv[4:]


def block(text, scene):
	m = re.search(re.escape(scene) + r" - .*?(?=\n\n|\Z)", text, re.S)
	return m.group(0) if m else ""


def num(text, pattern):
	m = re.search(pattern, text)
	return float(m.group(1)) if m else float("nan")


def read(path):
	text = open(path, encoding="utf-8", errors="replace").read()
	calm, gas, fire, breach = (block(text, s) for s in ("Calm station", "Gas release", "Plasma fire", "Hull breaches"))
	ssair = r"all of SSair: [\d.]+ ms total, ([\d.]+) ms per"
	turfs = r"  active turfs: [\d.]+ ms total, ([\d.]+) ms per"
	groups = r"excited groups: [\d.]+ ms total, ([\d.]+) ms per"
	walls = r"heat through walls: [\d.]+ ms total, ([\d.]+) ms per"
	return {
		"SPEED, ms per atmos tick": None,
		"calm: all of SSair": num(calm, ssair),
		"gas release: all of SSair": num(gas, ssair),
		"fire: all of SSair": num(fire, ssair),
		"breaches: all of SSair": num(breach, ssair),
		"breaches: turfs + groups": num(breach, turfs) + num(breach, groups),
		"breaches: heat through walls": num(breach, walls),
		"WORK": None,
		"fire: awake turfs, average": num(fire, r"active turfs: average ([\d.]+)"),
		"breaches: awake turfs, average": num(breach, r"active turfs: average ([\d.]+)"),
		"GAS": None,
		"tiles with N2O, 60 s after release": num(gas, r"on (\d+) turfs with a mole or more"),
		"tiles with N2O, after the fire": num(fire, r"on (\d+) turfs with a mole or more"),
		"tiles with N2O, after the breaches": num(breach, r"on (\d+) turfs with a mole or more"),
		"tiles under 20 kPa, after the fire": num(fire, r"(\d+) turfs under 20 kPa"),
		"tiles under 20 kPa, after the breaches": num(breach, r"(\d+) turfs under 20 kPa"),
		"thousand mol on station, after the breaches": num(breach, r"open station turfs: (\d+) mol in all") / 1000,
		"FIRE": None,
		"tiles burning at once, most": num(fire, r"hotspots most (\d+)"),
		"plasma burned, mol": num(gas, r"plasma (\d+) mol") + 1200 - num(fire, r"plasma (\d+) mol"),
		"tiles over 100 C, after the fire": num(fire, r"(\d+) turfs over 100 C"),
		"heat in the air after the fire, MJ": num(fire, r"([\d.]+) MJ in the air"),
		"heat in turfs after the fire, MJ": num(fire, r"([\d.]+) MJ in turfs"),
	}


def pool(prefix):
	name, _, count = prefix.partition(":")
	runs = int(count) if count else default_runs
	rows = [read(f"{base}/{name}_{r}/results.txt") for r in range(1, runs + 1)]
	return name, rows


names = []
tables = {}
for prefix in [linda, *builds]:
	name, rows = pool(prefix)
	names.append(name)
	tables[name] = rows

width = max(len(k) for k in tables[linda][0])
print(" " * width + "".join(f"{n[:16]:>18}" for n in names))
for key in tables[linda][0]:
	if tables[linda][0][key] is None:
		print(key)
		continue
	cells = []
	reference = statistics.mean(r[key] for r in tables[linda])
	for name in names:
		values = [r[key] for r in tables[name]]
		mean = statistics.mean(values)
		text = f"{mean:.2f}" if mean < 100 else f"{mean:.0f}"
		if name != linda and reference:
			text += f" {(mean / reference - 1) * 100:+.0f}%"
		cells.append(f"{text:>18}")
	print(key.ljust(width) + "".join(cells))
