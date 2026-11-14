"""Tick-spread A/B: does loading go faster or slower when it's spread over more ticks, or packed into fewer?

Two phases are timed in every boot:
  - startup (MC init): TICK_LIMIT_MC_INIT (config), how far into a tick init runs before it sleeps a tick. 500 = 5 ticks' worth.
  - lobby build (Lavaland + space ruin levels, lobby_build.dm): lobby-build-ticklimit=N (world param). Unset = the MC's pace,
    which leaves the last quarter of each tick to the MC.
Each arm pairs one of each; arms are booted in turn (A B C D A B C D ...) so machine noise hits them all alike.

Usage (repo root):  python tools/boot_bench/lobby_tick_ab.py [--runs 5] [--dmb tickab.mdme.dmb]
Results: data/tick_ab/results.txt (+ results.json); logs in data/logs/tick_ab/<arm>/<run>/.
"""
import argparse
import json
import os
import re
import shutil
import statistics
import subprocess
import sys
import time

os.environ.pop("__COMPAT_LAYER", None)
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BYOND_BIN = os.environ.get("BYOND_BIN", r"C:\Program Files (x86)\BYOND\bin")
OUT = os.path.join(ROOT, "data", "tick_ab")

# (name, TICK_LIMIT_MC_INIT, lobby-build-ticklimit or None)
ARMS = [
	("init500_buildMC", 500, None),
	("init98_build98", 98, 98),
	("init2000_build200", 2000, 200),
	("init5000_build400", 5000, 400),
	("init50_build50", 50, 50),
]
STALL = 150  # s after launch with no "Lobby build: done" line: recorded as stalled (a thin pace can starve: stoplag waits for a tick under it)

DONE_RE = re.compile(r"Initializations complete within ([\d.]+) seconds")
SS_RE = re.compile(r"Initialized (Mapping|Atoms|Air) subsystem within ([\d.]+) seconds")
BUILD_RE = re.compile(r"Lobby build: done in ([\d.]+)s: .*?\((.*); (\d+) ticks, pace (\S+)\)")


def make_config(limit):
	d = os.path.join(OUT, f"cfg_{limit}")
	if os.path.isdir(d):
		shutil.rmtree(d)
	shutil.copytree(os.path.join(ROOT, "config"), d)
	path = os.path.join(d, "config.txt")
	with open(path, newline="") as f:
		text = f.read()
	text = re.sub(r"(?m)^TICK_LIMIT_MC_INIT \d+", f"TICK_LIMIT_MC_INIT {limit}", text)
	text = re.sub(r"(?m)^AUTO_PROFILE\b", "#AUTO_PROFILE", text)
	with open(path, "w", newline="") as f:
		f.write(text)
	return os.path.relpath(d, ROOT).replace("\\", "/")


def busy_servers(mine):
	"""dd.exe processes other than ours (an idle GUI dreamdaemon.exe with no world is ignored)."""
	out = subprocess.run(["tasklist", "/FO", "CSV", "/NH"], capture_output=True, text=True, errors="replace").stdout
	pids = []
	for line in out.splitlines():
		cols = [c.strip('"') for c in line.split('","')]
		if len(cols) > 1 and cols[0].lower() == "dd.exe" and cols[1] != str(mine):
			pids.append(cols[1])
	return pids


def boot(dmb, arm, run, cfg, pace, port):
	logdir = f"tick_ab/{arm}/{run}"
	shutil.rmtree(os.path.join(ROOT, "data", "logs", logdir), ignore_errors=True)
	params = f"log-directory={logdir}&config={cfg}&bot-map=hippiestation"
	if pace:
		params += f"&lobby-build-ticklimit={pace}"
	for attempt in range(4):
		waited = 0
		while busy_servers(None):
			if waited > 1800:
				sys.exit("other servers busy for 30 min")
			time.sleep(5)
			waited += 5
		launched = time.time()
		proc = subprocess.Popen([os.path.join(BYOND_BIN, "dd.exe"), dmb, str(port), "-trusted", "-invisible", "-params", params],
			cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
		log = os.path.join(ROOT, "data", "logs", logdir, "runtime.log")
		res = None
		overlapped = False
		while time.time() - launched < STALL:
			time.sleep(1)
			if busy_servers(proc.pid):
				overlapped = True
			if proc.poll() is not None or not os.path.exists(log):
				if proc.poll() is not None:
					break
				continue
			with open(log, errors="replace") as f:
				text = f.read()
			m = BUILD_RE.search(text)
			if m:
				res = {"build": float(m.group(1)), "stages": m.group(2), "ticks": int(m.group(3)), "pace": m.group(4)}
				d = DONE_RE.search(text)
				res["init"] = float(d.group(1)) if d else None
				res["ss"] = {k: float(v) for k, v in SS_RE.findall(text)}
				break
		proc.kill()
		proc.wait()
		if not res and not overlapped and os.path.exists(log):
			with open(log, errors="replace") as f:
				d = DONE_RE.search(f.read())
			if d:  # started up, but the build never finished
				return {"build": None, "stages": "stalled", "ticks": 0, "pace": str(pace), "init": float(d.group(1)), "ss": {}}
		if res and not overlapped:
			return res
		print(f"  {arm} run {run}: {'overlapped another server' if overlapped else 'no lobby build line'} - redoing", flush=True)
	sys.exit(f"{arm} run {run} failed 4 times; see data/logs/{logdir}")


def build_med(rs):
	done = [r["build"] for r in rs if r["build"] is not None]
	stalled = len(rs) - len(done)
	return (f"{statistics.median(done):.2f}" if done else "-") + (f" ({stalled} stalled)" if stalled else "")


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--runs", type=int, default=5)
	ap.add_argument("--dmb", default="tickab.mdme.dmb")
	ap.add_argument("--port", type=int, default=45471)
	a = ap.parse_args()
	os.makedirs(OUT, exist_ok=True)
	cfgs = {lim: make_config(lim) for _, lim, _ in ARMS}
	results = {name: [] for name, _, _ in ARMS}
	began = time.time()
	for run in range(1, a.runs + 1):
		for name, lim, pace in ARMS:
			t0 = time.time()
			r = boot(a.dmb, name, run, cfgs[lim], pace, a.port)
			results[name].append(r)
			print(f"  run {run}/{a.runs} {name}: init {r['init']}s, build {r['build']}s in {r['ticks']} ticks ({r['stages']})"
				f" [{time.time() - t0:.0f}s, {time.time() - began:.0f}s total]", flush=True)
	lines = [f"Tick-spread A/B, {a.runs} runs per arm, medians (hippiestation map)", ""]
	lines.append(f"{'arm':<20} {'init limit':>10} {'MC init s':>10} {'Mapping s':>10} {'Atoms s':>8} | {'build pace':>10} {'build s':>14} {'ticks':>6}")
	for name, lim, pace in ARMS:
		rs = results[name]
		med = lambda f: statistics.median(f(r) for r in rs)
		lines.append(f"{name:<20} {lim:>10} {med(lambda r: r['init']):>10.2f} {med(lambda r: r['ss'].get('Mapping', 0)):>10.2f}"
			f" {med(lambda r: r['ss'].get('Atoms', 0)):>8.2f} | {str(pace or 'MC'):>10} {build_med(rs):>14} {med(lambda r: r['ticks']):>6.0f}")
	lines.append("")
	lines.append("spread (min-max): " + "; ".join(f"{n} init {min(r['init'] for r in results[n]):.1f}-{max(r['init'] for r in results[n]):.1f},"
		f" build {min((r['build'] for r in results[n] if r['build']), default=0):.1f}-{max((r['build'] for r in results[n] if r['build']), default=0):.1f}" for n, _, _ in ARMS))
	lines.append(f"took {time.time() - began:.0f}s")
	text = "\n".join(lines)
	with open(os.path.join(OUT, "results.txt"), "w") as f:
		f.write(text + "\n")
	with open(os.path.join(OUT, "results.json"), "w") as f:
		json.dump(results, f, indent=1)
	print(text)
	print("BATCH_DONE", flush=True)


if __name__ == "__main__":
	main()
