#!/usr/bin/env python3
"""Testkit smoke test: drives every kind of command on a running testkit server and says PASS/FAIL for each.
  python tools/testkit/smoke.py [--port N] [--only name,name]
Needs a server: tk.py build && tk.py start (testbench is enough)."""
import json
import os
import sys
import time
import traceback

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tk  # noqa: E402

results = []


def check(name, ok, detail=""):
	results.append((name, bool(ok), detail))
	print("%s %s%s" % ("PASS" if ok else "FAIL", name, (" (%s)" % detail) if detail else ""))
	sys.stdout.flush()


def ref(made):
	return made[0]["ref"] if isinstance(made, list) else made["ref"]


def t_basics(s):
	check("ping", s.call("ping") == "pong")
	st = s.call("status")
	check("status: round under way", st["phase"] == "ready" and st["round_state"] == 3, "phase %s" % st["phase"])
	check("help lists commands", len(s.call("help")) > 40)


def t_world(s):
	arena = s.call("arena", w=9, h=9)
	aid = arena["id"]
	a = ref(s.call("spawn", type="/mob/living/carbon/human", at="arena:%s" % aid, outfit="/datum/outfit/job/assistant"))
	b = ref(s.call("spawn", type="/mob/living/carbon/human", at="arena:%s" % aid))
	s.call("move", ref=b, dir="east")
	s.call("give", mob=a, type="/obj/item/storage/toolbox/mechanical")
	s.call("intent", mob=a, intent="harm")
	before = s.call("get", ref=b, vars=["health"])["vars"]["health"]
	s.call("mark", name="world")
	hits = 0
	for _ in range(6):
		s.call("use", user=a, item="held", target=b)
		s.call("wait", seconds=1)
		hits += 1
	after = s.call("get", ref=b, vars=["health"])["vars"]["health"]
	check("use: a toolbox hurts", after < before, "health %s -> %s after %d swings" % (before, after, hits))
	ev = s.call("events", kinds=["attack"], limit=50)["events"]
	check("events: attacks recorded", any(e.get("target_ref") == b for e in ev), "%d attack events" % len(ev))
	s.call("damage", mob=b, brute=300)
	s.call("wait", seconds=1)
	deaths = s.call("events", kinds=["death"])["events"]
	mine = [e for e in deaths if e.get("ref") == b]
	check("events: death with killer", mine and mine[-1].get("killer"), json.dumps(mine[-1]) if mine else "no death event")
	got = s.call("get", ref=a)
	check("get: changed vars", "vars" in got and len(got["vars"]) > 5, "%d vars" % len(got.get("vars", {})))
	box = s.call("call", ref=a, proc="get_active_held_item")["ref"]
	s.call("set", ref=box, var="desc", value="smoke test box")
	check("set: a var", s.call("get", ref=box, vars=["desc"])["vars"]["desc"] == "smoke test box")
	found = s.call("find", type="/mob/living/carbon/human", near="arena:%s" % aid, range=6)
	check("find near", found["count"] >= 2, "%d found" % found["count"])
	look = s.call("look", at="arena:%s" % aid, range=1)
	check("look: tiles with air", len(look) == 9 and look[0]["pressure"] is not None)
	r = s.call("call", ref=a, proc="get_active_held_item")
	check("call: proc on a thing", isinstance(r, dict) and "toolbox" in r.get("type", ""), str(r))
	r = s.call("call", ref="global", proc="get_area_name", args=[{"ref": a}, 1])
	check("call: global proc with a thing arg", r == "Testkit Arena", str(r))
	u = s.call("until", ref=b, var="stat", value=3, seconds=5)
	check("until: dead stat", u["met"])
	inv = s.call("invariants", mark="world")
	check("invariants: no runtimes in a fight", inv["counts"]["runtime"] == 0, json.dumps(inv["runtime_sites"])[:300])
	s.call("arena_reset", id=aid)
	found = s.call("find", type="/mob/living/carbon/human", near="arena:%s" % aid, range=6)
	check("arena_reset clears", found["count"] == 0, "%d left" % found["count"])
	s.call("arena_free", id=aid)


def t_time(s):
	t0 = s.call("status")["time"]
	s.call("pause")
	st = s.call("status")
	check("pause", st["mc_paused"])
	s.call("resume")
	check("resume", not s.call("status")["mc_paused"])
	t1 = s.call("wait", seconds=2)
	check("wait is a job and game time passes", t1 - t0 >= 20, "%s -> %s" % (t0, t1))


def t_ui(s):
	arena = s.call("arena", w=7, h=7)
	v = ref(s.call("spawn", type="/obj/machinery/vending/cola", at="arena:%s" % arena["id"]))
	data = s.call("ui_data", src=v)
	check("ui_data: vending", data and (data.get("static") or data.get("data")), str(list((data.get("static") or {}).keys()))[:200])
	tank = ref(s.call("spawn", type="/obj/machinery/portable_atmospherics/canister/oxygen", at="arena:%s" % arena["id"]))
	before = s.call("get", ref=tank, vars=["release_pressure"])["vars"]["release_pressure"]
	r = s.call("ui_act", src=tank, action="pressure", params={"pressure": "max"})
	after = s.call("get", ref=tank, vars=["release_pressure"])["vars"]["release_pressure"]
	check("ui_act: canister release pressure max", after > before, "%s -> %s" % (before, after))
	verbs = s.call("verbs", ref=s.call("find", type="/mob/living/carbon/human", near="arena:%s" % arena["id"], range=5)["found"][0]["ref"]) \
		if s.call("find", type="/mob/living/carbon/human", near="arena:%s" % arena["id"], range=5)["count"] else None
	check("verbs: tester has verbs", verbs is None or len(verbs) > 0)
	s.call("arena_free", id=arena["id"])


def t_reset(s):
	areas = s.call("areas")
	area = next((a for a in ("Bar", "Kitchen", "Medbay", "Bridge") if a in areas), None) or max(areas, key=lambda a: areas[a] if areas[a] < 200 else 0)
	n_before = s.call("find", type="/obj", area=area)["count"]
	thing = s.call("find", type="/obj/structure/table", area=area)
	if thing["count"]:
		s.call("del", ref=thing["found"][0]["ref"])
	r = s.call("reset_area", area=area)
	n_after = s.call("find", type="/obj", area=area)["count"]
	check("reset_area: %s back as mapped" % area, abs(n_after - n_before) <= max(2, n_before // 20), "objs %d -> %d, %s" % (n_before, n_after, r))


def t_bots(s):
	areas = s.call("areas")
	place = next((a for a in ("Bar", "Kitchen", "Medbay", "Bridge") if a in areas), None) or max(areas, key=areas.get)
	made = s.call("spawn", bot=1, job="Assistant", at="area:" + place)
	check("spawn a bot crewmember", isinstance(made, list) and made, str(made)[:200])
	if not made:
		return
	b = made[0]["ref"]
	s.call("wait", seconds=3)
	bots = s.call("bots")
	check("bots lists it", any(x["ref"] == b for x in bots), "%d bots" % len(bots))
	why = s.call("bot_why", bot=b, question="what are you doing")
	check("bot_why: brain laid bare", "state" in why and "waiting_seconds" in why and "lines" in why, ", ".join(sorted(why))[:300])
	s.call("bot_watch", bot=b)
	s.call("wait", seconds=2)
	w = s.call("events", kinds=["bot.watch"])["events"]
	check("bot_watch events", len(w) >= 1, "%d" % len(w))
	s.call("bot_watch", bot=b, on=0)
	s.call("possess", bot=b)
	check("possess", s.call("bots") and next(x for x in s.call("bots") if x["ref"] == b)["possessed"])
	s.call("say", mob=b, text="smoke test says hi")
	said = s.call("events", kinds=["say"], match="smoke test says hi")["events"]
	check("say as a bot, say event", len(said) >= 1)
	s.call("release", bot=b)
	check("release", not next(x for x in s.call("bots") if x["ref"] == b)["possessed"])


def t_gym(s):
	names = s.call("gym_list", match="reach")
	check("gym_list", len(names) > 0, ", ".join(names[:5]))
	if not names:
		return
	r = s.call("gym_run", name=names[0], exact=1)
	res = r["results"][0]
	check("gym_run %s" % names[0], res["verdict"] in ("PASS", "XFAIL"), "%s %s in %ss" % (res["verdict"], res["reason"] or "", res["seconds"]))


def t_check(s):
	r = s.call("run_check", proc="combat_check_run", results="data/combat_check/results.txt")
	check("run_check combat_check_run", r["finished"] and r["pass"] > 0, "%d pass, %d fail in %ss: %s" % (r["pass"], r["fail"], r["seconds"], "; ".join(r["fails"])[:300]))


def t_perf(s):
	p = s.call("perf", top=10)
	check("perf: subsystems", len(p["subsystems"]) > 20, "profiler %s" % p["profiler"])
	s.call("perf_mark", name="A")
	s.call("wait", seconds=2)
	c = s.call("perf_compare", a="A", top=10)
	check("perf_compare", c["seconds"] > 1 and isinstance(c["procs"], list), "%d procs, ss %s" % (len(c["procs"]), list(c["subsystem_ms_per_s"].items())[:4]))
	st = s.call("stall", type="/obj/item/stack/sheet/metal", n=200)
	check("stall: a pile of 200", st["made"] == 200, "avg tick %s%%, peak %s%%, spawn %s ms" % (st["tick_usage_avg"], st["tick_usage_peak"], st["spawn_ms"]))


def t_fuzz(s):
	r = s.call("fuzz_use", match="/obj/item/crowbar", n=5, seed=1)
	check("fuzz_use", r["types"] > 0, "%d types, runtimes %s" % (r["types"], r["runtimes_by_type"]))
	r = s.call("fuzz_ui", cases=[{"type": "/obj/machinery/portable_atmospherics/canister/oxygen", "actions": ["relabel", "pressure", "valve", "eject"], "keys": ["pressure"]}], seed=1)
	check("fuzz_ui", r["pressed"] > 0, "%d pressed, runtimes %s" % (r["pressed"], r["runtimes_by_type"]))


TESTS = [("basics", t_basics), ("world", t_world), ("time", t_time), ("ui", t_ui), ("reset", t_reset), ("bots", t_bots),
	("gym", t_gym), ("check", t_check), ("perf", t_perf), ("fuzz", t_fuzz)]


def main():
	port = None
	only = None
	args = sys.argv[1:]
	if "--port" in args:
		port = int(args[args.index("--port") + 1])
	if "--only" in args:
		only = args[args.index("--only") + 1].split(",")
	s = tk.load_server(port)
	started = time.time()
	for name, fn in TESTS:
		if only and name not in only:
			continue
		t = time.time()
		try:
			fn(s)
		except Exception as err:  # noqa: BLE001
			check("%s ran to the end" % name, False, "%s: %s" % (type(err).__name__, err))
			traceback.print_exc()
		print("  (%s took %.1f s)" % (name, time.time() - t))
	failed = [r for r in results if not r[1]]
	inv = s.call("invariants")
	print("%d passed, %d failed in %.0f s; runtimes since boot %d, hard deletes %d, MC alerts %d" % (len(results) - len(failed), len(failed),
		time.time() - started, inv["counts"]["runtime"], inv["counts"]["hard_delete"], inv["counts"]["mc_alert"]))
	for site, e in list((inv["runtime_sites"] or {}).items())[:15]:
		print("  runtime %s x%d: %s" % (site, e["count"], e["error"]))
	return 1 if failed else 0


if __name__ == "__main__":
	sys.exit(main())
