#!/usr/bin/env python3
"""ss13: an MCP server (stdio, JSON-RPC, no dependencies) that puts HippieStation testkit servers in front of Claude as tools.
It builds the testkit dmb, starts and stops headless servers, and sends them commands (tools/testkit/tk.py, dm/*.dm).

Register (this project, this machine only):
  claude mcp add ss13 --scope local -- python tools/testkit/ss13_mcp.py
"""
import json
import os
import sys
import time
import traceback

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tk  # noqa: E402
import ui_scan  # noqa: E402

INSTRUCTIONS = """HippieStation test servers you can steer while they run (tools/testkit).
ss_build once (CHECKS adds self-check .dm files), then ss_start (map testbench unless the test needs the real station: hippiestation).
The round is already under way when ss_start returns, with no bot crew (spawn bots with ss_spawn bot=true or ss_start crew=N).
Things are named by ref ("[0x2001234]" or "[mob_12]"), "mob:<name>", "bot:<name>", "type:/obj/...", "SS<name>" (a subsystem), "global".
Places: [x,y,z], a ref, "area:<name>", "landmark:<name>", "arena:<id>" (ss_arena makes an empty walled floor in reserved space).
Commands that sleep (wait, until, gym, checks, fuzz) are waited for. ss_events reads what happened (death, attack, say, bot.*, runtime,
hard_delete, mc_alert, door.*): pass since=<seq> from the last answer to read only what's new. ss_mark then ss_invariants says what broke
since (runtimes with sites, hard deletes, MC alerts). ss_cmd runs any testkit command (ss_cmd cmd=help lists them all).
Stop servers with ss_stop when done; each keeps data/testkit/<port>/ (events.jsonl, commands.jsonl for ss_replay, dd.log)."""


def obj(props, required=()):
	return {"type": "object", "properties": props, "required": list(required)}


S = {"type": "string"}
N = {"type": "number"}
B = {"type": "boolean"}
ANY = {}
PORT = {"type": "integer", "description": "server port (default: the last one started)"}
PLACE = {"description": "[x,y,z], a ref, area:<name>, landmark:<name>, arena:<id>"}
THING = {"type": "string", "description": "ref, mob:<name>, bot:<name>, type:<path>, SS<name>, global"}

# name -> (testkit command or None for local, description, schema properties, required)
TOOLS = {
	"ss_build": (None, "Build the testkit dmb (hippiestation.dme + tools/testkit/dm + checks). Needed after any .dm change; stop servers first.",
		{"checks": {"type": "array", "items": S, "description": "check .dm files to build in, e.g. tools/combat_check/combat_check.dm"}}, ()),
	"ss_start": (None, "Start a headless test server and wait until its round is under way.",
		{"map": {"type": "string", "description": "testbench (default, small) or hippiestation, metastation"}, "seed": N,
		"speed": {"type": "number", "description": "timewarp: 1 real time (default), 0 no limit, N at most N times"},
		"crew": {"type": "integer", "description": "bot crew to fill the station with (default 0)"},
		"params": {"type": "string", "description": "extra world params, a=1&b=2"}, "port": {"type": "integer"}}, ()),
	"ss_stop": (None, "Stop a test server.", {"port": PORT}, ()),
	"ss_servers": (None, "Test servers started from this machine, alive or not.", {}, ()),
	"ss_status": ("status", "Round phase, time, tick usage, cpu, counts, runtimes so far.", {}, ()),
	"ss_cmd": (None, "Any testkit command with its arguments (cmd=help lists every command).",
		{"cmd": S, "args": {"type": "object"}, "wait": B}, ("cmd",)),
	"ss_spawn": ("spawn", "Make n of a type at a place (outfit for humans), or bot=true for a bot crewmember with a job.",
		{"type": S, "at": PLACE, "n": N, "outfit": S, "bot": B, "job": S}, ("at",)),
	"ss_find": ("find", "Find things by type/name, near a place (range) or in an area.",
		{"type": S, "name": S, "near": PLACE, "range": N, "area": S, "limit": N}, ()),
	"ss_look": ("look", "Tiles around a place: contents, area, pressure, temperature, light.", {"at": PLACE, "range": N}, ("at",)),
	"ss_areas": ("areas", "Station areas with tile counts.", {"match": S}, ()),
	"ss_get": ("get", "A thing's vars (all changed from its type, or the named ones) and contents.",
		{"ref": THING, "vars": {"type": "array", "items": S}, "changed": N, "depth": N}, ("ref",)),
	"ss_set": ("set", "Set a var (through vv_edit_var). Values {ref:..}/{type:..}/{turf:[x,y,z]} for things.",
		{"ref": THING, "var": S, "value": ANY}, ("ref", "var")),
	"ss_call": ("call", "Call a proc on a thing (or ref=global for a global proc). args: list, or object of named args; user sets usr.",
		{"ref": THING, "proc": S, "args": ANY, "user": THING, "depth": N}, ("proc",)),
	"ss_del": ("del", "qdel a thing.", {"ref": THING}, ("ref",)),
	"ss_give": ("give", "Put a new item of a type (or an existing ref) in a mob's hands or a slot.",
		{"mob": THING, "type": S, "ref": THING, "slot": N}, ("mob",)),
	"ss_move": ("move", "Teleport a thing to a place, step it a direction (north...), or walk=true to walk there.",
		{"ref": THING, "to": PLACE, "dir": ANY, "walk": B}, ("ref",)),
	"ss_say": ("say", "A mob says something.", {"mob": THING, "text": S}, ("mob", "text")),
	"ss_use": ("use", "A person uses: item on target, item alone (attack_self), empty hand on target; how=click goes through ClickOn. "
		"item=held for the item in hand. Returns the events it caused.",
		{"user": THING, "item": S, "target": THING, "how": S, "params": S}, ("user",)),
	"ss_intent": ("intent", "Set a mob's intent (help/disarm/grab/harm) and zone (chest, head, l_arm...).",
		{"mob": THING, "intent": S, "zone": S}, ("mob",)),
	"ss_damage": ("damage", "Hurt (or heal, negative) a mob.", {"mob": THING, "brute": N, "burn": N, "tox": N, "oxy": N, "stamina": N}, ("mob",)),
	"ss_wait": ("wait", "Let game time pass.", {"seconds": N}, ("seconds",)),
	"ss_until": ("until", "Wait until a var meets a condition (op ==, !=, >, <, truthy, falsy, deleted) or the timeout.",
		{"ref": THING, "var": S, "value": ANY, "op": S, "seconds": N}, ("ref", "var")),
	"ss_pause": ("pause", "The MC stops firing subsystems (world.time still runs).", {}, ()),
	"ss_resume": ("resume", "The MC fires again.", {}, ()),
	"ss_speed": ("speed", "Timewarp: 1 real time, 0 no limit, N at most N times.", {"speed": N}, ("speed",)),
	"ss_arena": ("arena", "An empty walled floor in reserved space: {id, corner, middle}. Use place arena:<id>.",
		{"w": N, "h": N, "floor": S}, ()),
	"ss_arena_reset": ("arena_reset", "Clear an arena back to bare floor.", {"id": S}, ("id",)),
	"ss_reset_area": ("reset_area", "Clear a station area's tiles and load them again from the map file.", {"area": S}, ("area",)),
	"ss_events": ("events", "What happened, after sequence number since. kinds: prefixes (death, attack, say, bot., runtime, hard_delete, "
		"mc_alert, door., gym., check.). match: text in the event.",
		{"since": N, "kinds": {"type": "array", "items": S}, "limit": N, "match": S}, ()),
	"ss_record": ("record", "Turn event kinds on or off (door and bot.click/pull/sit are off by default).",
		{"kinds": {"type": "array", "items": S}, "on": B}, ("kinds",)),
	"ss_mark": ("mark", "Remember the counts now (runtimes, hard deletes, MC alerts, deaths) for ss_invariants.", {"name": S}, ()),
	"ss_invariants": ("invariants", "What broke since a mark: runtimes with sites, hard deletes by type, MC alerts, MC health.", {"mark": S}, ()),
	"ss_bots": ("bots", "Every bot: name, job, state, goal, step, health, hands, where, possessed.", {}, ()),
	"ss_bot_why": ("bot_why", "One bot's brain laid bare: state, goal with strategies and steps, what it's waiting on (next_* clocks), "
		"goal clocks, last give-up and path failure, urgency, claims, its last 40 log lines and recent events.",
		{"bot": THING, "question": S}, ("bot",)),
	"ss_bot_watch": ("bot_watch", "A bot.watch event every second with the bot's brain (on=false stops).", {"bot": THING, "on": B}, ("bot",)),
	"ss_possess": ("possess", "Stop a bot's brain: commands drive its body.", {"bot": THING}, ("bot",)),
	"ss_release": ("release", "Start a possessed bot's brain again.", {"bot": THING}, ("bot",)),
	"ss_bot_goal": ("bot_goal", "Give a bot a goal (type path or name under /datum/bot_goal/) with a target and vars.",
		{"bot": THING, "goal": S, "target": ANY, "vars": {"type": "object"}}, ("bot", "goal")),
	"ss_gym_list": ("gym_list", "Bot Gym scenario names.", {"match": S}, ()),
	"ss_gym_run": ("gym_run", "Run Bot Gym scenarios (names or parts of names, | between) on this server: verdicts and transcripts.",
		{"name": S, "runs": N, "exact": B}, ("name",)),
	"ss_run_check": ("run_check", "Run a self-check's global proc (built in with ss_build checks=...) and read its PASS/FAIL lines.",
		{"proc": S, "results": S, "done": S, "seconds": N}, ("proc",)),
	"ss_ui_data": ("ui_data", "The tgui data a thing's window would show (user: who looks; default an all-access tester).",
		{"src": THING, "user": THING}, ("src",)),
	"ss_ui_act": ("ui_act", "Press a tgui button: action with params, as user (default the tester). Returns events and the new data.",
		{"src": THING, "action": S, "params": {"type": "object"}, "user": THING, "data": B}, ("src", "action")),
	"ss_verbs": ("verbs", "The verbs a mob or thing has.", {"ref": THING}, ("ref",)),
	"ss_verb": ("verb", "Run a verb as user (src: the thing it's on, default the user).", {"user": THING, "verb": S, "args": ANY, "src": THING}, ("verb",)),
	"ss_admin": ("admin", "Run an admin proc (a /datum/admins proc, or a global one) with a clientless all-rights holder.",
		{"proc": S, "args": ANY}, ("proc",)),
	"ss_perf": ("perf", "Subsystem costs and the profiler's recent top procs and stacks.", {"top": N, "ms": N}, ()),
	"ss_perf_mark": ("perf_mark", "Keep the profiler totals now, for ss_perf_compare.", {"name": S}, ()),
	"ss_perf_compare": ("perf_compare", "Proc and subsystem costs (ms per second) since a perf mark.", {"a": S, "top": N}, ()),
	"ss_stall": ("stall", "A pile of n of a type on one tile (mob_storm), then the tick usage and costs it caused.",
		{"type": S, "n": N, "at": PLACE, "keep": B}, ("type",)),
	"ss_fuzz_ui": (None, "Press every action every matched type's ui_act() answers to (read from the DM source), with junk and "
		"known params, on fresh ones in an arena: runtimes by type and invariants.",
		{"match": {"type": "string", "description": "part of a type path, e.g. /obj/machinery/chem"}, "tries": N, "seed": N,
		"limit": {"type": "integer", "description": "types at most (default 40)"}}, ()),
	"ss_fuzz_use": ("fuzz_use", "Every type under type/matching match used by hand, in hand and with each tool: runtimes by type.",
		{"type": S, "match": S, "n": N, "seed": N}, ()),
	"ss_replay": (None, "Run a server's commands.jsonl again on a server (best effort: the scheduler isn't deterministic).",
		{"file": S, "fast": B}, ("file",)),
	"ss_screenshot": (None, "Connect a real DreamSeeker client to the server, optionally move its view to a place, and save a "
		"screenshot (PNG path returned). Slow (~20 s); needs a desktop.",
		{"at": PLACE, "name": S, "seconds": N}, ()),
	"ss_client_close": (None, "Close the DreamSeeker ss_screenshot opened.", {}, ()),
	"ss_commands": ("commands", "The commands run on the server so far.", {}, ()),
}


def text_result(value, is_error=False):
	text = value if isinstance(value, str) else json.dumps(value, indent=1)
	if len(text) > 200000:
		text = text[:200000] + "\n... (cut at 200000 characters)"
	return {"content": [{"type": "text", "text": text}], "isError": is_error}


def run_tool(name, args):
	port = args.pop("port", None)
	if name not in TOOLS:
		raise tk.TestkitError("no tool " + name)
	cmd = TOOLS[name][0]
	if cmd:
		return tk.load_server(port).call(cmd, **args)
	if name == "ss_build":
		dmb = tk.build(args.get("checks") or [], quiet=True)
		return {"built": dmb}
	if name == "ss_start":
		params = args.get("params", "")
		if args.get("crew"):
			params = (params + "&" if params else "") + "testkit-crew=%d" % int(args["crew"])
		s = tk.start(args.get("map", "testbench"), args.get("port"), args.get("seed"), args.get("speed"), params)
		st = s.call("status")
		return {"port": s.port, "pid": s.pid, "status": st}
	if name == "ss_stop":
		tk.stop(tk.load_server(port))
		return "stopped"
	if name == "ss_servers":
		return [{k: v for k, v in s.items() if k != "key"} for s in tk.list_servers()]
	if name == "ss_cmd":
		return tk.load_server(port).call(args["cmd"], wait=args.get("wait", True), **(args.get("args") or {}))
	if name == "ss_fuzz_ui":
		cases = ui_scan.cases_for(args.get("match"))[: int(args.get("limit", 40))]
		if not cases:
			return "no ui_act() matches " + str(args.get("match"))
		result = tk.load_server(port).call("fuzz_ui", cases=[{k: c[k] for k in ("type", "actions", "keys", "values")} for c in cases],
			tries=args.get("tries", 3), seed=args.get("seed"))
		result["files"] = {c["type"]: c["file"] for c in cases}
		return result
	if name == "ss_replay":
		return tk.replay(tk.load_server(port), args["file"], args.get("fast", False))
	if name == "ss_screenshot":
		import client_lane
		return client_lane.screenshot(tk.load_server(port), args.get("at"), args.get("name"), args.get("seconds", 8))
	if name == "ss_client_close":
		import client_lane
		client_lane.close(tk.load_server(port))
		return "closed"
	raise tk.TestkitError("not done: " + name)


def handle(msg):
	method = msg.get("method")
	if method == "initialize":
		version = (msg.get("params") or {}).get("protocolVersion", "2024-11-05")
		return {"protocolVersion": version, "capabilities": {"tools": {}}, "serverInfo": {"name": "ss13", "version": "1.0"},
			"instructions": INSTRUCTIONS}
	if method == "ping":
		return {}
	if method == "tools/list":
		tools = []
		for name, (_, desc, props, required) in TOOLS.items():
			p = dict(props)
			if name not in ("ss_build", "ss_start", "ss_servers"):
				p.setdefault("port", PORT)
			tools.append({"name": name, "description": desc, "inputSchema": obj(p, required)})
		return {"tools": tools}
	if method == "tools/call":
		params = msg.get("params") or {}
		name = params.get("name")
		args = dict(params.get("arguments") or {})
		started = time.time()
		try:
			result = run_tool(name, args)
			out = text_result(result)
		except tk.TestkitError as err:
			out = text_result("error: %s" % err, True)
		except (OSError, ValueError) as err:
			out = text_result("error: %s: %s (is the server up? ss_servers)" % (type(err).__name__, err), True)
		except Exception:  # noqa: BLE001
			out = text_result("error:\n" + traceback.format_exc(), True)
		log("%s %.1f s" % (name, time.time() - started))
		return out
	raise KeyError(method)


def log(text):
	sys.stderr.write("[ss13] %s\n" % text)
	sys.stderr.flush()


def main():
	stdin = sys.stdin.buffer
	stdout = sys.stdout.buffer
	while True:
		line = stdin.readline()
		if not line:
			return
		line = line.strip()
		if not line:
			continue
		try:
			msg = json.loads(line)
		except ValueError:
			continue
		if "id" not in msg:
			continue  # a notification
		reply = {"jsonrpc": "2.0", "id": msg["id"]}
		try:
			reply["result"] = handle(msg)
		except KeyError:
			reply["error"] = {"code": -32601, "message": "no method %s" % msg.get("method")}
		except Exception as err:  # noqa: BLE001
			reply["error"] = {"code": -32603, "message": str(err)}
		stdout.write((json.dumps(reply) + "\n").encode("utf-8"))
		stdout.flush()


if __name__ == "__main__":
	main()
