// Testkit - a test server that can be steered while it runs. Not part of the game: tools/testkit/run.sh builds testkit.mdme
// (hippiestation.dme, then these files, then any checks asked for) into its own dmb, so hippiestation.dmb is left alone.
//
// The server boots, starts the round and waits. Commands come in as world/Topic packets on its port, from this machine only and
// with the key given at boot (-params "testkit=1&testkit-key=..."):  ?testkit=<json>&key=<key>
//   {"cmd": "spawn", "type": "/obj/item/crowbar", "at": [100, 100, 2]}   ->   {"ok": true, "result": ...}
// tools/testkit/tk.py sends them (and is the command line), tools/testkit/ss13_mcp.py puts them in front of Claude as tools.
//
// A command whose proc sleeps (a check, a gym scenario, a proc that waits on a do_after) is a job: the answer is
// {"ok": true, "job": N, "pending": true} and "job" with that number gives the result once it's done.
// An answer longer than a packet holds (65535 bytes) is kept as a blob: {"blob": N, "size": ...}, read with "blob" in parts.
//
// Every command is a proc of /datum/testkit named cmd_<name>(list/a); "help" lists them with their first comment line.

/// Checks built in after these files (CHECKS= on tk.py build) don't start themselves in world/New() when this is defined
#define TESTKIT_BUILD
#define TESTKIT_PARAMETER "testkit"
#define TESTKIT_KEY_PARAMETER "testkit-key"
#define TESTKIT_DIR "data/testkit/"
/// Text per blob part: well under a packet's 65535 bytes even when every character is 3 bytes of UTF-8
#define TESTKIT_BLOB_PART 12000
/// Events kept for "events" to read back (the file has them all)
#define TESTKIT_EVENTS_KEPT 20000

GLOBAL_DATUM(testkit, /datum/testkit)

/// The server doesn't pause with nobody connected: every harness needs this
/datum/controller/master
	sleep_offline_after_initializations = FALSE

/world/New()
	. = ..()
	if(TESTKIT_PARAMETER in world.params)
		GLOB.testkit = new /datum/testkit
		INVOKE_ASYNC(GLOB.testkit, TYPE_PROC_REF(/datum/testkit, boot))

/world/Topic(T, addr, master, key)
	if(GLOB.testkit && findtext(T, "testkit=") && (findtext(T, "testkit=") <= 2))
		return GLOB.testkit.topic(T, addr)
	return ..()

/datum/testkit
	var/key
	/// "starting", "ready" (round under way), "stopping"
	var/phase = "starting"
	var/next_job = 0
	/// job number -> list("done" = TRUE/FALSE, "result" = ..., "error" = ..., "started" = world.time, "cmd" = name)
	var/list/jobs = list()
	var/next_blob = 0
	var/list/blobs = list()
	/// Commands run, for the replay log
	var/list/command_log = list()
	var/started_at
	/// data/testkit/<port>/: events.jsonl, commands.jsonl, ready.txt
	var/dir = TESTKIT_DIR

/datum/testkit/proc/boot()
	key = world.params[TESTKIT_KEY_PARAMETER]
	started_at = REALTIMEOFDAY
	world.sleep_offline = FALSE
	dir = "[TESTKIT_DIR][world.port]/"
	fdel(dir + "events.jsonl")
	fdel(dir + "commands.jsonl")
	var/seed = text2num(world.params["testkit-seed"])
	if(!isnull(seed))
		rand_seed(seed)
	events_boot()
	CONFIG_SET(flag/bot_telemetry, TRUE) // the bots' telemetry events reach the stream (bot_telemetry_wanted())
	UNTIL(SSticker.initialized)
	// No bot crew unless asked for (testkit-crew=N): a test spawns the bots it wants (spawn bot=1)
	CONFIG_SET(number/bot_crew_target, text2num(world.params["testkit-crew"]) || 0)
	if(!("testkit-lobby" in world.params))
		if(!("bot-mode" in world.params))
			GLOB.master_mode = world.params["testkit-mode"] || "extended"
			CONFIG_SET(flag/allow_random_events, ("testkit-events" in world.params))
		SSticker.start_immediately = TRUE
		var/deadline = world.time + 5 MINUTES
		while(SSticker.current_state < GAME_STATE_PLAYING && world.time < deadline)
			sleep(1 SECONDS)
		if(!("testkit-round-end" in world.params))
			SSticker.can_fire = FALSE // a round that ends reboots the world, and everything set up is gone
	phase = SSticker.current_state == GAME_STATE_PLAYING ? "ready" : "lobby"
	text2file("[phase] [world.port]", dir + "ready.txt")
	log_world("TESTKIT: [phase] on port [world.port], after [(REALTIMEOFDAY - started_at) / 10] s")
	event("testkit.ready", list("phase" = phase, "map" = SSmapping.config?.map_name))
	watch_loop()

// ---------------------------------------------------------------------------------------------
// Packets
// ---------------------------------------------------------------------------------------------

/datum/testkit/proc/topic(T, addr)
	if(addr && !findtext(addr, "127.0.0.1"))
		return json_encode(list("ok" = FALSE, "error" = "testkit takes commands from this machine only"))
	var/list/input = params2list(T)
	if(!key || input["key"] != key)
		return json_encode(list("ok" = FALSE, "error" = "bad key"))
	var/list/a
	try
		a = json_decode(input[TESTKIT_PARAMETER])
	catch
		return json_encode(list("ok" = FALSE, "error" = "the command isn't JSON"))
	if(!islist(a) || !istext(a["cmd"]))
		return json_encode(list("ok" = FALSE, "error" = "no cmd"))
	var/list/answer = run_command(a)
	if(a["cmd"] == "blob") // a part is never a blob itself: escaped, it can be longer than the part was
		return json_encode(answer)
	return reply(answer)

/// The answer as text, kept as a blob when it's too long for a packet
/datum/testkit/proc/reply(list/answer)
	var/text = json_encode(answer)
	if(length(text) <= TESTKIT_BLOB_PART)
		return text
	var/id = ++next_blob
	blobs["[id]"] = text
	if(length(blobs) > 50)
		blobs.Cut(1, 2)
	return json_encode(list("ok" = answer["ok"], "blob" = id, "size" = length(text), "part" = TESTKIT_BLOB_PART))

/// Runs a command as a job: if it finishes without sleeping, its answer comes straight back
/datum/testkit/proc/run_command(list/a)
	var/name = a["cmd"]
	if(!hascall(src, "cmd_[name]"))
		return list("ok" = FALSE, "error" = "no command [name] (try help)")
	if(name != "events" && name != "job" && name != "blob" && name != "status" && name != "ping")
		command_log += list(list("t" = world.time, "a" = a))
		hippie_log_append(dir + "commands.jsonl", json_encode(list("t" = world.time, "rt" = REALTIMEOFDAY, "a" = a)))
	var/id = ++next_job
	var/list/job = list("done" = FALSE, "cmd" = name, "started" = world.time)
	jobs["[id]"] = job
	if(length(jobs) > 500)
		jobs.Cut(1, 2)
	run_job(job, name, a)
	if(job["done"])
		jobs -= "[id]"
		if(job["error"])
			return list("ok" = FALSE, "error" = job["error"])
		return list("ok" = TRUE, "result" = job["result"])
	return list("ok" = TRUE, "job" = id, "pending" = TRUE)

/datum/testkit/proc/run_job(list/job, name, list/a)
	set waitfor = FALSE
	try
		job["result"] = call(src, "cmd_[name]")(a)
	catch(var/exception/e)
		job["error"] = "[e.name] at [e.file]:[e.line]"
		if(e.file && !findtext(e.file, "tools\\testkit") &&!findtext(e.file, "tools/testkit")) // the game's own runtime, not a bad command
			note_exception(e, name)
	job["done"] = TRUE
	job["ended"] = world.time

// ---------------------------------------------------------------------------------------------
// Values in and out
// ---------------------------------------------------------------------------------------------

/// A value for JSON: things become {ref, type, name, at}, lists go `depth` deep
/datum/testkit/proc/out(value, depth = 2)
	if(isnull(value) || isnum(value) || istext(value))
		return value
	if(ispath(value))
		return "[value]"
	if(islist(value))
		var/list/L = value
		if(depth <= 0)
			return "(list of [length(L)])"
		var/assoc = FALSE
		try // contents, verbs and the like have no values to look up: "bad index"
			for(var/k in L)
				if(!isnum(k) && !isnull(L[k]))
					assoc = TRUE
					break
		catch
			assoc = FALSE
		var/list/result = list()
		var/count = 0
		for(var/k in L)
			if(++count > 200)
				if(assoc)
					result["..."] = "[length(L) - 200] more"
				else
					result += "... [length(L) - 200] more"
				break
			if(assoc)
				result["[istext(k) ? k : (istype(k, /datum) ? REF(k) : "[k]")]"] = out(L[k], depth - 1)
			else
				result += list(out(k, depth - 1))
		return result
	if(istype(value, /datum) || isatom(value))
		var/datum/D = value
		var/list/brief = list("ref" = REF(D), "type" = "[D.type]")
		if(isatom(D))
			var/atom/A = D
			brief["name"] = A.name
			var/turf/T = get_turf(A)
			if(T)
				brief["at"] = list(T.x, T.y, T.z)
			if(QDELETED(A))
				brief["deleted"] = TRUE
		return brief
	if(istype(value, /client))
		var/client/C = value
		return list("client" = C.ckey)
	return "[value]"

/// A value from JSON: {"ref": "[0x..]"} is that thing, {"type": "/obj/..."} a type, {"turf": [x, y, z]} that tile; lists go in
/datum/testkit/proc/in_value(value)
	if(islist(value))
		var/list/L = value
		if(L["ref"])
			return locate_ref(L["ref"])
		if(L["type"] && length(L) == 1)
			return text2path(L["type"])
		if(L["turf"])
			var/list/xyz = L["turf"]
			return locate(xyz[1], xyz[2], xyz[3])
		var/list/result = list()
		for(var/k in L)
			if(istext(k) && !isnull(L[k]))
				result[k] = in_value(L[k])
			else
				result += list(in_value(k))
		return result
	if(istext(value) && findtext(value, "\[") == 1 && findtext(value, "]") == length(value))
		return locate_ref(value)
	return value

/// The thing a command names: a ref, "mob:<name>", "bot:<name>", "type:<path>" (the first one), or {"ref": ...}
/datum/testkit/proc/thing(spec)
	if(islist(spec))
		return in_value(spec)
	if(!istext(spec))
		return null
	if(findtext(spec, "\[") == 1)
		return locate_ref(spec)
	if(findtext(spec, "mob:") == 1 || findtext(spec, "bot:") == 1)
		var/wanted = lowertext(copytext(spec, findtext(spec, ":") + 1))
		var/bots_only = findtext(spec, "bot:") == 1
		for(var/mob/M as anything in GLOB.mob_list)
			if(bots_only && !(ishuman(M) && M:bot_brain))
				continue
			if(lowertext(M.real_name) == wanted || lowertext(M.name) == wanted)
				return M
		for(var/mob/M as anything in GLOB.mob_list)
			if(bots_only && !(ishuman(M) && M:bot_brain))
				continue
			if(findtext(lowertext(M.real_name), wanted))
				return M
		return null
	if(findtext(spec, "type:") == 1)
		var/path = text2path(copytext(spec, 6))
		if(!path)
			return null
		if(ispath(path, /area))
			return GLOB.areas_by_type[path]
		for(var/atom/A in world)
			if(istype(A, path))
				return A
		return null
	if(spec == "global")
		return GLOB
	if(spec == "testkit")
		return src
	if(findtext(spec, "SS") == 1)
		for(var/datum/controller/subsystem/S in Master.subsystems)
			if("[S.type]" == "/datum/controller/subsystem/[lowertext(copytext(spec, 3))]" || S.name == copytext(spec, 3))
				return S
	return null

/// A tile: [x, y, z], a thing (its tile), "area:<name or path>" (an open tile in it), "landmark:<name>", "arena:<id>" (its middle)
/datum/testkit/proc/where(spec)
	if(islist(spec))
		var/list/L = spec
		if(length(L) == 3 && isnum(L[1]))
			return locate(L[1], L[2], L[3])
		if(L["arena"])
			return arena_middle(L["arena"])
		return get_turf(in_value(spec))
	if(!istext(spec))
		return null
	if(findtext(spec, "area:") == 1)
		var/area/A = find_area(copytext(spec, 6))
		if(!A)
			return null
		var/list/open = list()
		for(var/turf/open/T in A)
			if(!T.density && !is_blocked_turf(T, TRUE))
				open += T
		return length(open) ? pick(open) : null
	if(findtext(spec, "landmark:") == 1)
		var/wanted = copytext(spec, 10)
		for(var/obj/effect/landmark/L in GLOB.landmarks_list)
			if(L.name == wanted)
				return get_turf(L)
		return null
	if(findtext(spec, "arena:") == 1)
		return arena_middle(copytext(spec, 7))
	return get_turf(thing(spec))

/datum/testkit/proc/find_area(name)
	var/path = text2path(name)
	if(path)
		return GLOB.areas_by_type[path]
	for(var/area/A in GLOB.sortedAreas)
		if(lowertext(A.name) == lowertext(name))
			return A
	for(var/area/A in GLOB.sortedAreas)
		if(findtext(lowertext(A.name), lowertext(name)))
			return A

/// "[0x2001234]" (a ref), or "[mob_82]": REF() gives a tagged thing's tag in brackets
/datum/testkit/proc/locate_ref(text)
	. = locate(text)
	if(!. && findtext(text, "\[") == 1)
		. = locate(copytext(text, 2, length(text)))

/datum/testkit/proc/need(value, what)
	if(isnull(value))
		CRASH("[what] not found")
	return value
