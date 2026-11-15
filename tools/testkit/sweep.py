#!/usr/bin/env python3
"""Interaction sweep on testkit servers (dm/testkit_sweep.dm): every type under a root made, used by hand, with six tools and in hand,
and examined. A server that goes down or hangs is started again and the type that took it is noted and skipped.

  python tools/testkit/sweep.py run /obj [/mob/living ...] [--batch 60] [--map testbench] [--match text]
  python tools/testkit/sweep.py report            data/testkit/sweep/report.txt from what's been swept

Results: data/testkit/sweep/<root>.jsonl (one type a line, resumable), sites.json (runtime sites with where they happened),
hard_deletes.json, killers.txt (types that took a server down), report.txt.
"""
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tk  # noqa: E402

OUT = os.path.join(tk.ROOT, "data", "testkit", "sweep")


def out_file(root):
	return os.path.join(OUT, root.strip("/").replace("/", "_") + ".jsonl")


def load_json(name, default):
	p = os.path.join(OUT, name)
	if os.path.exists(p):
		with open(p) as f:
			return json.load(f)
	return default


def save_json(name, value):
	with open(os.path.join(OUT, name), "w") as f:
		json.dump(value, f, indent=1)


def merge_sites(server):
	sites = load_json("sites.json", {})
	try:
		got = server.call("runtime_sites") or {}
		hard = server.call("invariants", mark="none").get("hard_deletes") or {}
	except (tk.TestkitError, OSError, ValueError):
		return
	for site, e in got.items():
		short = site.split("master\\")[-1].replace("\\", "/")
		old = sites.get(short, {"count": 0, "error": e["error"], "where": []})
		old["count"] = max(old["count"], 0) + e["count"]
		old["where"] = sorted(set(old.get("where", [])) | set(e.get("where") or []))[:12]
		sites[short] = old
	save_json("sites.json", sites)
	hd = load_json("hard_deletes.json", {})
	for t, n in hard.items():
		hd[t] = hd.get(t, 0) + n
	save_json("hard_deletes.json", hd)


def fresh_server(map_name, old=None):
	if old:
		try:
			tk.stop(old)
		except Exception:  # noqa: BLE001
			pass
	for _ in range(60):  # a rebuild in progress has the dmb away for a moment
		try:
			return tk.start(map_name, params="")
		except tk.TestkitError as err:
			if "build first" not in str(err):
				raise
			time.sleep(5)
	return tk.start(map_name, params="")


def progress_type(server):
	p = os.path.join(tk.DATA, str(server.port), "sweep_progress.txt")
	if not os.path.exists(p):
		return None
	lines = [l.strip() for l in open(p, errors="replace") if l.strip()]
	return lines[-1] if lines else None


def run(roots, batch=60, map_name="testbench", match=None):
	os.makedirs(OUT, exist_ok=True)
	server = fresh_server(map_name)
	started = time.time()
	try:
		for root in roots:
			path = out_file(root)
			done = set()
			if os.path.exists(path):
				with open(path) as f:
					for line in f:
						try:
							done.add(json.loads(line)["type"])
						except ValueError:
							pass
			types = [t for t in server.call("types", root=root, match=match) if t not in done]
			print("%s: %d types to sweep (%d done before)" % (root, len(types), len(done)), flush=True)
			i = 0
			batches = 0
			while i < len(types):
				chunk = types[i:i + batch]
				pf = os.path.join(tk.DATA, str(server.port), "sweep_progress.txt")
				if os.path.exists(pf):
					os.remove(pf)
				t0 = time.time()
				try:
					records = server.call("sweep_use", types=chunk, timeout=max(600, batch * 20))
				except (tk.TestkitError, OSError, ValueError) as err:
					killer = progress_type(server)
					print("  server lost at %s (%s): restarting" % (killer, err), flush=True)
					with open(os.path.join(OUT, "killers.txt"), "a") as f:
						f.write("%s\t%s\n" % (killer, str(err)[:200]))
					server = fresh_server(map_name, server)
					if killer in chunk:
						k = chunk.index(killer)
						with open(path, "a") as f:
							f.write(json.dumps({"type": killer, "killed_server": str(err)[:200]}) + "\n")
						# the ones before it in the batch are lost with the server's answer: they go round again
						types = types[:i] + chunk[:k] + types[i + k + 1:]
					continue
				with open(path, "a") as f:
					for r in records:
						f.write(json.dumps(r) + "\n")
				i += len(chunk)
				batches += 1
				if batches % 10 == 0:
					merge_sites(server)
					server = fresh_server(map_name, server)  # a fresh world now and then: what earlier types left can't pile up
				el = time.time() - started
				print("  %s %d/%d  batch %.0f s  elapsed %.0f min" % (root, i, len(types), time.time() - t0, el / 60), flush=True)
	finally:
		try:
			merge_sites(server)
			tk.stop(server)
		except Exception:  # noqa: BLE001
			pass
	print("SWEEP_DONE in %.0f min" % ((time.time() - started) / 60), flush=True)


# ---------------------------------------------------------------------------------------------

TOOLS = ("crowbar", "wrench", "welder", "screwdriver", "wirecutters", "multitool")


def report():
	records = []
	for name in os.listdir(OUT):
		if name.endswith(".jsonl"):
			with open(os.path.join(OUT, name)) as f:
				for line in f:
					try:
						records.append(json.loads(line))
					except ValueError:
						pass
	sites = load_json("sites.json", {})
	hard = load_json("hard_deletes.json", {})
	lines = []
	killed = [r for r in records if r.get("killed_server")]
	not_made = [r for r in records if r.get("made")]
	stuck, slow, bad_text, user_state, silent_tool = [], [], {}, [], {}
	for r in records:
		for u in r.get("uses", []):
			label = "%s: %s" % (r["type"], u["u"])
			if u.get("stuck"):
				stuck.append(label)
			if u.get("ms", 0) > 50:
				slow.append((u["ms"], label))
			for b in u.get("bad_text", []):
				kind = b.split(":")[0]
				if kind == "space before punctuation" and not re.search(r" [.,!](\s|$|<)", b):
					continue  # " .50 AE", " .357": a number, not a stray space
				if kind == "null" and re.search(r"null (rod|extract)|make null", b):
					continue
				bad_text.setdefault(kind, []).append("%s -- %s" % (label, b[len(kind) + 2:]))
			if u.get("user") and u["u"] != "examine":
				user_state.append("%s -> %s" % (label, ", ".join(u["user"])))
			if u.get("silent") and u["u"] in TOOLS and r["type"].startswith(("/obj/machinery", "/obj/structure")):
				silent_tool.setdefault(u["u"], []).append(r["type"])
	lines.append("Interaction sweep: %d types, %d uses" % (len(records), sum(len(r.get("uses", [])) for r in records)))
	lines.append("")
	lines.append("== Runtime sites: %d (%d runtimes)" % (len(sites), sum(e["count"] for e in sites.values())))
	for site, e in sorted(sites.items(), key=lambda kv: -kv[1]["count"]):
		lines.append("%5d  %s  %s" % (e["count"], site, e["error"][:100]))
		for w in e.get("where", [])[:4]:
			lines.append("         at %s" % w)
	lines.append("")
	lines.append("== Hard deletes by type: %d" % len(hard))
	for t, n in sorted(hard.items(), key=lambda kv: -kv[1]):
		lines.append("%5d  %s" % (n, t))
	lines.append("")
	lines.append("== Took a server down: %d" % len(killed))
	lines += ["  %s  (%s)" % (r["type"], r["killed_server"]) for r in killed]
	lines.append("")
	lines.append("== Couldn't be made: %d" % len(not_made))
	lines += ["  %s: %s" % (r["type"], r["made"]) for r in not_made[:200]]
	lines.append("")
	lines.append("== Stuck (never came back in 3 s with do_after not waiting): %d" % len(stuck))
	lines += ["  " + s for s in stuck[:300]]
	lines.append("")
	lines.append("== Slowest uses (ms of server time, >50): %d" % len(slow))
	lines += ["  %8.1f  %s" % (ms, l) for ms, l in sorted(slow, reverse=True)[:80]]
	lines.append("")
	lines.append("== Left the person changed: %d" % len(user_state))
	lines += ["  " + s for s in user_state[:300]]
	lines.append("")
	lines.append("== Broken text")
	for kind, items in sorted(bad_text.items(), key=lambda kv: -len(kv[1])):
		lines.append("-- %s: %d" % (kind, len(items)))
		lines += ["  " + s for s in items[:60]]
	lines.append("")
	lines.append("== Silent tool uses on machines and structures (nothing said, nothing changed) by tool")
	for tool, types in sorted(silent_tool.items()):
		lines.append("-- %s: %d types" % (tool, len(types)))
	text = "\n".join(lines)
	with open(os.path.join(OUT, "report.txt"), "w", encoding="utf-8") as f:
		f.write(text)
	save_json("silent_tools.json", silent_tool)
	return text


def main(argv):
	if not argv or argv[0] not in ("run", "report"):
		print(__doc__)
		return 0
	if argv[0] == "report":
		print(report()[:6000])
		return 0
	opts = {}
	roots = []
	i = 1
	while i < len(argv):
		if argv[i].startswith("--"):
			opts[argv[i][2:]] = argv[i + 1]
			i += 2
		else:
			roots.append(re.sub(r"^[A-Za-z]:/Program Files/Git", "", argv[i]))
			i += 1
	run(roots or ["/obj"], int(opts.get("batch", 60)), opts.get("map", "testbench"), opts.get("match"))
	print(report()[:3000])
	return 0


if __name__ == "__main__":
	sys.exit(main(sys.argv[1:]))
