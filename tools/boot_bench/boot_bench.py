"""Boot benchmark: boot the server headless N times and report how long loading takes.

Each run launches DreamDaemon with -params "profile-exit=1", which shuts the world down right
after the master controller finishes initializing. The wall-clock numbers come from the
launch time and the UTC timestamps rust_g writes into runtime.log.

Usage (from the repo root):
    python tools/boot_bench/boot_bench.py run  <tag> [--runs N] [--compile] [--config DIR]
    python tools/boot_bench/boot_bench.py show <tag>
    python tools/boot_bench/boot_bench.py compare <tag_before> <tag_after>
    python tools/boot_bench/boot_bench.py ab <tag_a> <repo_a> <tag_b> <repo_b> [--runs N]   (alternating A/B boots)

Results go to data/boot_bench/<tag>.json; round logs to data/logs/boot_bench/<tag>/<run>/.
Set BYOND_BIN to override the BYOND install path.

Before/after a change: build the old commit in a worktree at a short path (Windows' path limit), then alternate:
    git worktree add --detach ../hbase HEAD && cp config/hippiestation_config.txt ../hbase/config/
    (cd ../hbase && "<BYOND>/bin/dm.exe" hippiestation.dme)
    python tools/boot_bench/boot_bench.py ab before ../hbase after . --runs 5
    git worktree remove --force ../hbase
Boots only start once no other DreamDaemon is running, and one that overlaps another server is redone - a second
server on the machine easily shifts boot time by 10s. AUTO_PROFILE (config.txt) adds ~4.5s to every boot; compare
without it by passing --config (or --config-a/--config-b) a copy of config/ with it commented out.
"""
import argparse
import datetime
import json
import os
import re
import shutil
import statistics
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BYOND_BIN = os.environ.get("BYOND_BIN", r"C:\Program Files (x86)\BYOND\bin")
RESULTS_DIR = os.path.join(ROOT, "data", "boot_bench")
LOG_ROOT = os.path.join(ROOT, "data", "logs", "boot_bench")

LINE_RE = re.compile(r"^\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3})\] (.*)$")
SS_RE = re.compile(r"^Initialized (.+?) subsystem within ([\d.e-]+) seconds?!")
LOADED_RE = re.compile(r"^Loaded (.+?) in ([\d.e-]+)s!")
DONE_RE = re.compile(r"^Initializations complete within ([\d.e-]+) seconds?!")


def parse_ts(text):
	stamp = datetime.datetime.strptime(text, "%Y-%m-%d %H:%M:%S.%f")
	return stamp.replace(tzinfo=datetime.timezone.utc).timestamp()


def parse_run(log_path, launched_at, exited_at):
	"""Pull the timings out of one run's runtime.log."""
	run = {"subsystems": {}, "loaded": {}}
	first_ts = None
	with open(log_path, encoding="utf-8", errors="replace") as f:
		for raw in f:
			m = LINE_RE.match(raw.rstrip("\n"))
			if not m:
				continue
			ts = parse_ts(m.group(1))
			msg = m.group(2)
			if first_ts is None:
				first_ts = ts
			if (sm := SS_RE.match(msg)):
				run["subsystems"][sm.group(1)] = float(sm.group(2))
			elif (lm := LOADED_RE.match(msg)):
				run["loaded"][lm.group(1)] = float(lm.group(2))
			elif (dm := DONE_RE.match(msg)):
				run["mc_init"] = float(dm.group(1))
				run["ready"] = ts - launched_at
	if first_ts is None or "ready" not in run:
		return None
	run["pre_mc"] = run["ready"] - run["mc_init"]  # launch -> MC starts initializing
	run["to_first_log"] = first_ts - launched_at  # launch -> world/New sets up logging
	run["exit"] = exited_at - launched_at
	return run


def compile_dme():
	print("Compiling...", flush=True)
	started = time.time()
	out = subprocess.run([os.path.join(BYOND_BIN, "dm.exe"), "hippiestation.dme"], cwd=ROOT,
		capture_output=True, text=True, errors="replace")
	for line in out.stdout.splitlines():
		if re.search(r"error|warning|\.dmb -", line):
			print("  " + line)
	print(f"  compile took {time.time() - started:.1f}s", flush=True)
	if out.returncode != 0:
		sys.exit("Compile failed")


def other_servers():
	"""PIDs of any DreamDaemon already running - one competing for the CPU skews every number."""
	if os.name != "nt":
		return []
	out = subprocess.run(["tasklist", "/FO", "CSV", "/NH"], capture_output=True, text=True, errors="replace").stdout
	pids = []
	for line in out.splitlines():
		cols = [c.strip('"') for c in line.split('","')]
		if len(cols) > 1 and cols[0].lower() in ("dd.exe", "dreamdaemon.exe"):
			pids.append(f"{cols[0]} {cols[1]}")
	return pids


def wait_for_quiet_machine():
	waited = 0
	while (pids := other_servers()):
		if waited == 0:
			print(f"  waiting for other servers to exit first: {', '.join(pids)}", flush=True)
		if waited >= 1800:
			sys.exit("Other servers still running after 30 minutes - close them and rerun")
		time.sleep(5)
		waited += 5


def boot_once(root, tag, i, config_dir, port, attempts=4):
	"""One headless boot of root's hippiestation.dmb; logs go to <root>/data/logs/boot_bench/<tag>/<i>/.
	A boot that another server ran alongside (checked every second) is thrown away and redone."""
	params = f"profile-exit=1&log-directory=boot_bench/{tag}/{i}"
	if config_dir:
		params += f"&config={config_dir}"
	cmd = [os.path.join(BYOND_BIN, "dd.exe"), "hippiestation.dmb", str(port), "-trusted", "-invisible", "-params", params]
	for attempt in range(attempts):
		wait_for_quiet_machine()
		launched_at = time.time()
		overlapped = []
		with open(os.path.join(RESULTS_DIR, f"{tag}_dd.log"), "w") as dd_log:
			proc = subprocess.Popen(cmd, cwd=root, stdout=dd_log, stderr=subprocess.STDOUT)
			while proc.poll() is None:
				if time.time() - launched_at > 600:
					proc.kill()
					sys.exit(f"{tag} run {i} timed out")
				others = [p for p in other_servers() if not p.endswith(f" {proc.pid}")]
				if others:
					overlapped = others
				time.sleep(1)
		exited_at = time.time()
		if not overlapped:
			break
		print(f"  {tag} run {i}: another server ran alongside ({', '.join(overlapped)}) - redoing it", flush=True)
	else:
		sys.exit(f"{tag} run {i}: couldn't get a boot without another server running")
	log = os.path.join(root, "data", "logs", "boot_bench", tag, str(i), "runtime.log")
	run = parse_run(log, launched_at, exited_at)
	if not run:
		sys.exit(f"{tag} run {i}: no 'Initializations complete' line - see {log}")
	print(f"  {tag} run {i}: ready in {run['ready']:.2f}s (MC init {run['mc_init']:.2f}s, before MC {run['pre_mc']:.2f}s)", flush=True)
	return run


def save(tag, results, root):
	summary = {"tag": tag, "root": root, "runs": results, "when": datetime.datetime.now().isoformat(timespec="seconds")}
	with open(os.path.join(RESULTS_DIR, f"{tag}.json"), "w") as f:
		json.dump(summary, f, indent=1)
	return summary


def run_bench(tag, runs, config_dir, port, root=ROOT):
	os.makedirs(RESULTS_DIR, exist_ok=True)
	shutil.rmtree(os.path.join(root, "data", "logs", "boot_bench", tag), ignore_errors=True)
	results = [boot_once(root, tag, i, config_dir, port) for i in range(1, runs + 1)]
	return save(tag, results, root)


def run_ab(tag_a, root_a, tag_b, root_b, runs, config_a, config_b, port):
	"""Alternates boots of two builds (A B A B ...) so drift in machine load hits both the same."""
	os.makedirs(RESULTS_DIR, exist_ok=True)
	for tag, root in ((tag_a, root_a), (tag_b, root_b)):
		shutil.rmtree(os.path.join(root, "data", "logs", "boot_bench", tag), ignore_errors=True)
	res_a, res_b = [], []
	for i in range(1, runs + 1):
		res_a.append(boot_once(root_a, tag_a, i, config_a, port))
		res_b.append(boot_once(root_b, tag_b, i, config_b, port))
	save(tag_a, res_a, root_a)
	save(tag_b, res_b, root_b)


def load(tag):
	with open(os.path.join(RESULTS_DIR, f"{tag}.json")) as f:
		return json.load(f)


def medians(summary):
	runs = summary["runs"]
	out = {}
	for key in ("ready", "pre_mc", "mc_init", "to_first_log"):
		out[key] = statistics.median(r[key] for r in runs)
	names = []
	for r in runs:
		for name in list(r["loaded"]) + list(r["subsystems"]):
			if name not in names:
				names.append(name)
	for name in names:
		vals = [r["subsystems"].get(name, r["loaded"].get(name, 0.0)) for r in runs]
		out[name] = statistics.median(vals)
	return out


def show(tag):
	summary = load(tag)
	med = medians(summary)
	readies = [r["ready"] for r in summary["runs"]]
	print(f"{tag}: {len(readies)} runs, launch -> ready median {med['ready']:.2f}s (min {min(readies):.2f}, max {max(readies):.2f})")
	for name, val in med.items():
		if val >= 0.05 or name in ("ready", "pre_mc", "mc_init"):
			print(f"  {name:<28}{val:8.2f}s")


def compare(tag_a, tag_b):
	a, b = medians(load(tag_a)), medians(load(tag_b))
	ra = [r["ready"] for r in load(tag_a)["runs"]]
	rb = [r["ready"] for r in load(tag_b)["runs"]]
	print(f"{'median seconds':<28}{tag_a:>12}{tag_b:>12}{'change':>10}")
	order = ["ready", "pre_mc", "mc_init"] + [k for k in a if k not in ("ready", "pre_mc", "mc_init", "to_first_log")]
	order += [k for k in b if k not in order and k != "to_first_log"]
	for key in order:
		va, vb = a.get(key, 0.0), b.get(key, 0.0)
		if max(va, vb) < 0.05 and key not in ("ready", "pre_mc", "mc_init"):
			continue
		pct = f"{(vb - va) / va * 100:+.0f}%" if va > 0.001 else ""
		label = {"ready": "LAUNCH -> READY", "pre_mc": "  before MC init", "mc_init": "  MC init total"}.get(key, "    " + key)
		print(f"{label:<28}{va:12.2f}{vb:12.2f}{pct:>10}")
	print(f"runs: {len(ra)} vs {len(rb)}; ready range {min(ra):.2f}-{max(ra):.2f} vs {min(rb):.2f}-{max(rb):.2f}")


def main():
	parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	sub = parser.add_subparsers(dest="cmd", required=True)
	p_run = sub.add_parser("run")
	p_run.add_argument("tag")
	p_run.add_argument("--runs", type=int, default=3)
	p_run.add_argument("--compile", action="store_true")
	p_run.add_argument("--config", default=None, help="config directory override (relative to the repo root)")
	p_run.add_argument("--port", type=int, default=45211)
	p_show = sub.add_parser("show")
	p_show.add_argument("tag")
	p_cmp = sub.add_parser("compare")
	p_cmp.add_argument("tag_a")
	p_cmp.add_argument("tag_b")
	p_ab = sub.add_parser("ab", help="alternate boots of two builds: ab <tag_a> <root_a> <tag_b> <root_b>")
	p_ab.add_argument("tag_a")
	p_ab.add_argument("root_a")
	p_ab.add_argument("tag_b")
	p_ab.add_argument("root_b")
	p_ab.add_argument("--runs", type=int, default=5)
	p_ab.add_argument("--config", default=None, help="config directory override for both sides")
	p_ab.add_argument("--config-a", default=None)
	p_ab.add_argument("--config-b", default=None)
	p_ab.add_argument("--port", type=int, default=45211)
	args = parser.parse_args()
	if args.cmd == "run":
		if args.compile:
			compile_dme()
		run_bench(args.tag, args.runs, args.config, args.port)
		show(args.tag)
	elif args.cmd == "show":
		show(args.tag)
	elif args.cmd == "ab":
		run_ab(args.tag_a, os.path.abspath(args.root_a), args.tag_b, os.path.abspath(args.root_b), args.runs,
			args.config_a or args.config, args.config_b or args.config, args.port)
		compare(args.tag_a, args.tag_b)
	else:
		compare(args.tag_a, args.tag_b)


if __name__ == "__main__":
	main()
