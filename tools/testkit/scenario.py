#!/usr/bin/env python3
"""Testkit scenarios: tests written as a list of steps in JSON, run on a testkit server, compared with the saved expectations.

  python tools/testkit/scenario.py run [files or folders...] [--port N] [--save] [--runs N]
  python tools/testkit/scenario.py list

With no files, every tools/testkit/scenarios/*.json. Each run's results go to data/testkit/results/<name>.json; --save makes them the
expectations (tools/testkit/expectations.json). Without --save the run is compared with them: WORSE / BETTER / SAME per scenario.

A scenario:
  {"name": "toolbox fight", "steps": [
    {"do": "arena", "w": 9, "h": 9, "save": "arena"},
    {"do": "spawn", "type": "/mob/living/carbon/human", "at": "arena:${arena.id}", "save": "a"},
    {"do": "use", "user": "${a.0.ref}", "item": "held", "target": "${b.0.ref}", "repeat": 5, "every": 1},
    {"expect": "event", "kinds": ["death"], "match": "${b.0.ref}", "within": 20},
    {"expect": "var", "ref": "${b.0.ref}", "var": "stat", "op": "==", "value": 3, "within": 5},
    {"expect": "result", "of": "fight", "path": "verdict", "op": "==", "value": "PASS"},
    {"expect": "no_event", "kinds": ["runtime"]},
    {"metric": "swings", "value": "${fight.count}"}
  ], "invariants": true, "cleanup": true}
Every "do" is a testkit command (tk.py help); "save" keeps its result for ${name.path} later. "${x}" alone keeps x's type.
"repeat"/"every" run a step again (seconds between). An expect fails the scenario; the rest of it still runs unless "stop": true.
"invariants": the scenario fails on a runtime, hard delete or MC alert while it ran. "cleanup": arenas it made are freed.
"""
import glob
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tk  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
SCENARIOS = os.path.join(HERE, "scenarios")
EXPECTATIONS = os.path.join(HERE, "expectations.json")
RESULTS = os.path.join(tk.ROOT, "data", "testkit", "results")
VAR_RE = re.compile(r"\$\{([^}]+)\}")


def lookup(saved, path):
	value = saved
	for part in path.split("."):
		if isinstance(value, list):
			value = value[int(part)]
		elif isinstance(value, dict):
			value = value.get(part)
		else:
			raise KeyError(path)
	return value


def fill(value, saved):
	if isinstance(value, str):
		whole = VAR_RE.fullmatch(value)
		if whole:
			return lookup(saved, whole.group(1))
		return VAR_RE.sub(lambda m: str(lookup(saved, m.group(1))), value)
	if isinstance(value, list):
		return [fill(v, saved) for v in value]
	if isinstance(value, dict):
		return {k: fill(v, saved) for k, v in value.items()}
	return value


def compare(op, a, b):
	return {
		"==": lambda: a == b, "!=": lambda: a != b, ">": lambda: a > b, "<": lambda: a < b, ">=": lambda: a >= b, "<=": lambda: a <= b,
		"in": lambda: a in b, "contains": lambda: b in a, "truthy": lambda: bool(a), "falsy": lambda: not a,
	}[op]()


def run_scenario(server, sc):
	saved = {}
	notes = []
	failures = []
	metrics = {}
	arenas = []
	started = time.time()
	status = server.call("status")
	t0 = status["time"]
	saved["_start_seq"] = server.call("mark", name="scenario")["seq"]
	if sc.get("seed") is not None:
		server.call("seed", seed=sc["seed"])
	for i, raw in enumerate(sc["steps"]):
		label = raw.get("label") or raw.get("do") or raw.get("expect") or raw.get("metric")
		try:
			step = fill(dict(raw), saved)
		except (KeyError, IndexError, ValueError, TypeError) as err:
			failures.append("step %d (%s): ${} not filled: %s" % (i + 1, label, err))
			if raw.get("stop"):
				break
			continue
		try:
			if "do" in step:
				cmd = step.pop("do")
				name = step.pop("save", None)
				repeat = int(step.pop("repeat", 1))
				every = float(step.pop("every", 0))
				step.pop("label", None)
				step.pop("stop", None)
				if cmd == "fuzz_ui" and "cases" not in step: # match: the types' ui_act() cases read from the DM (ui_scan.py)
					import ui_scan
					found = ui_scan.cases_for(step.pop("match", None))[: int(step.pop("limit", 200))]
					step["cases"] = [{k: c[k] for k in ("type", "actions", "keys", "values")} for c in found]
				result = None
				for n in range(repeat):
					result = server.call(cmd, **step)
					if every and n < repeat - 1:
						server.call("wait", seconds=every)
				if cmd == "arena":
					arenas.append(result["id"])
				if name:
					saved[name] = result
					if repeat > 1 and isinstance(result, dict):
						result["count"] = repeat
			elif "expect" in step:
				ok, detail = expect(server, step, saved)
				if not ok:
					failures.append("step %d (%s): %s" % (i + 1, label, detail))
					if raw.get("stop"):
						break
				else:
					notes.append("ok %s: %s" % (label, detail))
			elif "metric" in step:
				metrics[step["metric"]] = step.get("value")
		except tk.TestkitError as err:
			failures.append("step %d (%s): %s" % (i + 1, label, err))
			if raw.get("stop"):
				break
	inv = server.call("invariants", mark="scenario")
	if sc.get("invariants", True) and not inv["clean"]:
		failures.append("invariants: %s %s" % (inv["counts"], json.dumps(inv["runtime_sites"])[:500]))
	if sc.get("cleanup", True):
		for aid in arenas:
			try:
				server.call("arena_free", id=aid)
			except tk.TestkitError:
				pass
	game_seconds = (server.call("status")["time"] - t0) / 10
	metrics.setdefault("game_seconds", round(game_seconds, 1))
	return {"name": sc["name"], "passed": not failures, "failures": failures, "notes": notes, "metrics": metrics,
		"seconds": round(time.time() - started, 1), "runtimes": inv["counts"].get("runtime", 0), "hard_deletes": inv["counts"].get("hard_delete", 0)}


def expect(server, step, saved):
	kind = step["expect"]
	within = float(step.get("within", 0))
	if kind in ("event", "no_event"):
		since = step.get("since", saved.get("_start_seq", 0))
		deadline = time.time() + within
		while True:
			got = server.call("events", since=since, kinds=step.get("kinds"), match=step.get("match"), limit=50)["events"]
			if kind == "event" and got:
				return True, "%s at seq %s" % (got[0]["k"], got[0]["seq"])
			if time.time() >= deadline:
				break
			server.call("wait", seconds=min(1, max(0.1, deadline - time.time())))
		if kind == "event":
			return False, "no %s event%s within %s s" % (step.get("kinds"), " matching %s" % step.get("match") if step.get("match") else "", within)
		return (not got), ("none" if not got else "%d: %s" % (len(got), json.dumps(got[0])[:300]))
	if kind == "var":
		r = server.call("until", ref=step["ref"], var=step["var"], value=step.get("value"), op=step.get("op", "=="), seconds=within or 0.1)
		return r["met"], "%s %s %s: %s" % (step["var"], step.get("op", "=="), step.get("value"), r.get("value"))
	if kind == "result":
		value = lookup(saved, step["of"] + ("." + step["path"] if step.get("path") else ""))
		ok = compare(step.get("op", "=="), value, step.get("value"))
		return ok, "%s = %s" % (step.get("path") or step["of"], json.dumps(value)[:200])
	if kind == "invariants":
		inv = server.call("invariants", mark="scenario")
		return inv["clean"], json.dumps(inv["counts"])
	raise tk.TestkitError("no expect kind " + kind)


def load(paths):
	files = []
	for p in paths or [SCENARIOS]:
		if os.path.isdir(p):
			files += sorted(glob.glob(os.path.join(p, "*.json")))
		else:
			files.append(p)
	scenarios = []
	for f in files:
		with open(f) as fh:
			data = json.load(fh)
		for sc in data if isinstance(data, list) else [data]:
			sc["_file"] = os.path.relpath(f, tk.ROOT)
			scenarios.append(sc)
	return scenarios


def verdict(old, new):
	"""WORSE, BETTER or SAME against the saved expectation."""
	if old is None:
		return "NEW"
	if old["passed"] and not new["passed"]:
		return "WORSE"
	if not old["passed"] and new["passed"]:
		return "BETTER"
	# a failing scenario's counts move a little run to run (the game's own rand): worse is clearly more
	if new.get("runtimes", 0) > old.get("runtimes", 0) * 1.1 + 1 or new.get("hard_deletes", 0) > old.get("hard_deletes", 0):
		return "WORSE"
	changed = []
	for k, v in new["metrics"].items():
		o = old.get("metrics", {}).get(k)
		if isinstance(v, (int, float)) and isinstance(o, (int, float)) and o and abs(v - o) / abs(o) > 0.25 and k != "game_seconds":
			changed.append("%s %s -> %s" % (k, o, v))
	return "CHANGED (%s)" % ", ".join(changed) if changed else "SAME"


def main(argv):
	if not argv or argv[0] not in ("run", "list"):
		print(__doc__)
		return 0
	opts = [a for a in argv[1:] if a.startswith("--")]
	paths = [a for a in argv[1:] if not a.startswith("--")]
	port = None
	runs = 1
	for i, a in enumerate(argv):
		if a == "--port":
			port = int(argv[i + 1])
			paths = [p for p in paths if p != argv[i + 1]]
		if a == "--runs":
			runs = int(argv[i + 1])
			paths = [p for p in paths if p != argv[i + 1]]
	scenarios = load(paths)
	if argv[0] == "list":
		for sc in scenarios:
			print("%s  (%s, %d steps)" % (sc["name"], sc["_file"], len(sc["steps"])))
		return 0
	server = tk.load_server(port)
	expectations = {}
	if os.path.exists(EXPECTATIONS):
		with open(EXPECTATIONS) as f:
			expectations = json.load(f)
	os.makedirs(RESULTS, exist_ok=True)
	worse = 0
	all_results = {}
	for sc in scenarios:
		for run in range(runs):
			r = run_scenario(server, sc)
			key = sc["name"] if runs == 1 else "%s #%d" % (sc["name"], run + 1)
			all_results[key] = r
			v = verdict(expectations.get(sc["name"]), r)
			if v == "WORSE":
				worse += 1
			print("%-5s %-7s %s (%.1f s)%s" % ("PASS" if r["passed"] else "FAIL", v.split(" ")[0], key, r["seconds"],
				"" if v in ("SAME", "NEW", "BETTER", "WORSE") else " " + v))
			for f in r["failures"]:
				print("        " + f)
			with open(os.path.join(RESULTS, re.sub(r"[^\w\-]+", "_", key) + ".json"), "w") as f:
				json.dump(r, f, indent=1)
	if "--save" in opts:
		for name, r in all_results.items():
			expectations[name.split(" #")[0]] = {k: r[k] for k in ("passed", "metrics", "runtimes", "hard_deletes")}
		with open(EXPECTATIONS, "w") as f:
			json.dump(expectations, f, indent=1, sort_keys=True)
		print("saved %d expectations to %s" % (len(all_results), os.path.relpath(EXPECTATIONS, tk.ROOT)))
	passed = sum(1 for r in all_results.values() if r["passed"])
	print("%d/%d passed, %d worse than expected" % (passed, len(all_results), worse))
	return 1 if worse else 0


if __name__ == "__main__":
	sys.exit(main(sys.argv[1:]))
