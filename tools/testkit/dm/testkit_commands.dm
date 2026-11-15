// Testkit commands for the world: what's there, making things, reading and changing them, people doing things. See testkit_core.dm.

/// name -> what it does and takes, for "help" (and the MCP server's tool list)
GLOBAL_LIST_INIT(testkit_help, list(
	"ping" = "-> pong",
	"status" = "round phase, world.time, tick usage, cpu, counts of mobs, bots, clients, events, jobs",
	"help" = "this list",
	"job" = "{id} the result of a command that slept (pending until done)",
	"blob" = "{id, offset} a part of an answer too long for one packet",
	"spawn" = "{type, at, n?, outfit?, bot?, job?} makes n of type at a tile (see where); bot=1 makes a bot crewmember (job)",
	"find" = "{type?, name?, near?, range?, area?, limit?} things by type/name/where",
	"look" = "{at, range?} what's on the tiles around a place",
	"get" = "{ref, vars?, changed?} a thing's vars (all, the named ones, or only those changed from the type's)",
	"set" = "{ref, var, value} sets a var (through vv_edit_var); value {ref:...}/{type:...}/{turf:\[x,y,z]} for things",
	"call" = "{ref|global, proc, args?, user?} calls a proc (args a list, or an object of named args); user sets usr",
	"del" = "{ref} qdel",
	"give" = "{mob, type|ref, slot?} puts an item in hand (or a slot: ITEM_SLOT number)",
	"move" = "{ref, to|dir, walk?} teleport to a place, step a direction, or walk=1 to walk there",
	"say" = "{mob, text} says it (a bot or anyone)",
	"use" = "{user, item?, target?, how?} item on target (melee_attack_chain), item alone (attack_self), hand on target (attack_hand); how=click goes through ClickOn",
	"intent" = "{mob, intent?, zone?} sets a/intent and zone_selected",
	"damage" = "{mob, brute?, burn?, tox?, oxy?, stamina?} hurts or heals (negative)",
	"wait" = "{seconds} sleeps here (a job): game time passes",
	"until" = "{ref, var, value?, op?, seconds?} waits until a var is (or isn't) a value, or the timeout",
	"pause" = "the MC stops firing subsystems (world.time still runs)",
	"resume" = "the MC fires again",
	"speed" = "{speed} timewarp: 1 real time, 0 no limit, N at most N times",
	"arena" = "{w?, h?, floor?} an empty walled floor in reserved space -> {id, corner, middle}",
	"arena_reset" = "{id} everything on the arena goes, floor back",
	"arena_free" = "{id} gives the space back",
	"reset_rect" = "{x1, y1, x2, y2, z?} clears those tiles and loads them again from the station's .dmm",
	"reset_area" = "{area} reset_rect over the area's tiles",
	"events" = "{since?, kinds?, limit?, match?} events after a sequence number (kinds: prefixes such as bot. death attack)",
	"record" = "{kinds, on?} which event kinds are recorded (defaults: everything but door and move)",
	"mark" = "{name?} remembers the counts of runtimes, hard deletes, MC alerts, deaths now",
	"invariants" = "{mark?} what's happened since the mark: runtimes (with sites), hard deletes, MC alerts, MC health",
	"run_check" = "{proc, results?, done?} runs a check's global proc as a job, reading its results file as it goes",
	"gym_list" = "{match?} Bot Gym scenario names",
	"gym_run" = "{name, runs?} runs scenarios on this server, each in its own arena -> a job with each verdict and transcript",
	"bots" = "every bot: name, job, state, goal, step, health, where",
	"bot_why" = "{bot, question?} the brain laid bare: state, goal, step, what it's waiting on, last lines, last give-up, path failure",
	"bot_watch" = "{bot, on?} a bot.watch event every second with its brain (off with on=0)",
	"possess" = "{bot} the bot's brain stops: commands drive the body",
	"release" = "{bot} the brain thinks again",
	"bot_goal" = "{bot, goal, target?, vars?} gives a bot a goal (type path)",
	"ui_data" = "{src, user?} the tgui data a window would show",
	"ui_act" = "{src, action, params?, user?} presses a tgui button as user (a stub window, usr set)",
	"verbs" = "{ref} the verbs a mob or thing has",
	"verb" = "{user, verb, args?, src?} runs a verb as user",
	"admin" = "{proc, args?} runs an admin proc (holder procs) with a stub admin; for client-only verbs use the real client lane",
	"perf" = "{top?} MC subsystems (cost, overrun, ticks) and the profiler's top procs",
	"perf_mark" = "{name} keeps the profiler totals",
	"perf_compare" = "{a, top?} proc costs since mark a",
	"fuzz_ui" = "{match?, n?, seed?} presses every action a window's JS sends, on every object type matched, with junk params",
	"fuzz_use" = "{match?, n?, seed?} every object matched, used by hand, each tool and in hand",
	"stall" = "{type, n, at?} a pile of n on one tile (mob_storm), then the MC's view of what it cost",
	"commands" = "the commands run so far (the replay log)",
	"seed" = "{seed} rand_seed",
	"areas" = "{match?} the station's areas with how many tiles each",
	"shutdown" = "stops the server",
	"client_view" = "{at?, zoom?} the connected client's view at a place (an observer it's put in)",
	"client_winset" = "{control?, params} winset on the connected client",
	"client_info" = "the connected client: ckey, mob, view, hwmode",
))

/datum/testkit/proc/cmd_ping(list/a)
	return "pong"

/datum/testkit/proc/cmd_help(list/a)
	return GLOB.testkit_help

/datum/testkit/proc/cmd_status(list/a)
	var/bots = 0
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(!QDELETED(B.owner))
			bots++
	return list(
		"phase" = phase,
		"map" = SSmapping.config?.map_name,
		"round_state" = SSticker.current_state,
		"time" = world.time,
		"realtime" = REALTIMEOFDAY,
		"tick_usage" = world.tick_usage,
		"cpu" = world.cpu,
		"map_cpu" = world.map_cpu,
		"mc_paused" = Master.processing <= 0,
		"speed" = GLOB.timewarp_speed,
		"mobs" = length(GLOB.mob_list),
		"bots" = bots,
		"clients" = length(GLOB.clients),
		"event_seq" = event_seq,
		"jobs_pending" = length(jobs),
		"runtimes" = counters["runtime"],
		"hard_deletes" = counters["hard_delete"],
		"mc_alerts" = counters["mc_alert"],
		"seed" = world.params["testkit-seed"],
	)

/datum/testkit/proc/cmd_job(list/a)
	var/list/job = jobs["[a["id"]]"]
	if(!job)
		CRASH("no job [a["id"]] (done jobs are read once)")
	if(!job["done"])
		return list("pending" = TRUE, "cmd" = job["cmd"], "for" = (world.time - job["started"]) / 10)
	jobs -= "[a["id"]]"
	if(job["error"])
		CRASH(job["error"])
	return job["result"]

/datum/testkit/proc/cmd_blob(list/a)
	var/text = blobs["[a["id"]]"]
	if(!text)
		CRASH("no blob [a["id"]]")
	var/offset = text2num("[a["offset"]]") || 0
	return copytext(text, offset + 1, offset + 1 + TESTKIT_BLOB_PART)

/datum/testkit/proc/cmd_areas(list/a)
	var/list/result = list()
	for(var/area/A in GLOB.sortedAreas)
		if(a["match"] && !findtext(lowertext(A.name), lowertext(a["match"])))
			continue
		var/tiles = 0
		var/station = FALSE
		for(var/turf/T in A)
			tiles++
			if(!station && is_station_level(T.z))
				station = TRUE
		if(tiles && (station || a["all"]))
			result[A.name] = tiles
	return result

/datum/testkit/proc/cmd_seed(list/a)
	rand_seed(text2num("[a["seed"]]"))
	return TRUE

/datum/testkit/proc/cmd_commands(list/a)
	return command_log

/datum/testkit/proc/cmd_shutdown(list/a)
	phase = "stopping"
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(testkit_shutdown)), 1, TIMER_CLIENT_TIME)
	return TRUE

/proc/testkit_shutdown()
	hippie_log_flush()
	Master.Shutdown()
	del(world)

// ---------------------------------------------------------------------------------------------
// Things
// ---------------------------------------------------------------------------------------------

/datum/testkit/proc/cmd_spawn(list/a)
	var/turf/T = need(where(a["at"]), "place [json_encode(a["at"])]")
	var/n = clamp(text2num("[a["n"]]") || 1, 1, 1000)
	var/list/made = list()
	if(a["bot"])
		for(var/i in 1 to n)
			var/mob/living/carbon/human/H = spawn_bot_crew_member(a["job"] || "Assistant")
			if(H)
				H.forceMove(T)
				made += H
		return out(made)
	var/path = need(text2path(a["type"]), "type [a["type"]]")
	for(var/i in 1 to n)
		var/atom/A = new path(T)
		if(a["outfit"] && ishuman(A))
			var/mob/living/carbon/human/H = A
			var/outfit = text2path(a["outfit"])
			if(outfit)
				H.equipOutfit(outfit)
		if(ishuman(A) && a["mind"] != 0)
			var/mob/living/carbon/human/H = A
			if(!H.mind)
				H.mind_initialize()
		made += A
	return out(made)

/datum/testkit/proc/cmd_find(list/a)
	var/path = a["type"] ? need(text2path(a["type"]), "type [a["type"]]") : /atom/movable
	var/name = a["name"] ? lowertext(a["name"]) : null
	var/limit = text2num("[a["limit"]]") || 50
	var/list/found = list()
	var/list/candidates
	if(a["near"])
		var/turf/T = need(where(a["near"]), "place [json_encode(a["near"])]")
		candidates = list()
		for(var/turf/U in range(text2num("[a["range"]]") || 7, T))
			candidates += U
			candidates += U.contents
	else if(a["area"])
		var/area/A = need(find_area(a["area"]), "area [a["area"]]")
		candidates = list()
		for(var/turf/U in A)
			candidates += U
			candidates += U.contents
	else if(ispath(path, /mob))
		candidates = GLOB.mob_list
	else if(ispath(path, /obj/machinery))
		candidates = GLOB.machines
	else
		candidates = world
	var/count = 0
	for(var/atom/A in candidates)
		if(!istype(A, path))
			continue
		if(name && !findtext(lowertext(A.name), name))
			continue
		count++
		if(length(found) < limit)
			found += A
	return list("count" = count, "found" = out(found))

/datum/testkit/proc/cmd_look(list/a)
	var/turf/T = need(where(a["at"]), "place [json_encode(a["at"])]")
	var/list/tiles = list()
	for(var/turf/U in range(text2num("[a["range"]]") || 0, T))
		var/list/here = list()
		for(var/atom/movable/AM in U)
			if(istype(AM, /atom/movable/lighting_object) || istype(AM, /obj/effect/landmark))
				continue
			here += AM
		var/datum/gas_mixture/air = U.return_air()
		tiles += list(list("turf" = out(U), "area" = get_area_name(U, TRUE), "contents" = out(here),
			"pressure" = air ? round(air.return_pressure(), 0.1) : null, "temperature" = air ? round(air.return_temperature(), 0.1) : null,
			"light" = U.get_lumcount()))
	return tiles

/datum/testkit/proc/cmd_get(list/a)
	var/datum/D = need(thing(a["ref"]), "thing [json_encode(a["ref"])]")
	var/list/result = list("thing" = out(D))
	var/list/vars = list()
	if(islist(a["vars"]))
		for(var/v in a["vars"])
			if(v in D.vars)
				vars[v] = out(D.vars[v], text2num("[a["depth"]]") || 2)
			else
				vars[v] = "(no such var)"
	else
		var/changed = a["changed"] != 0
		for(var/v in D.vars)
			if(v == "vars" || v == "contents" || v == "overlays" || v == "underlays" || v == "vis_contents" || v == "verbs")
				continue
			var/value = D.vars[v]
			if(changed && value == initial(D.vars[v]))
				continue
			vars[v] = out(value, 1)
	result["vars"] = vars
	if(isatom(D))
		var/atom/A = D
		result["contents"] = out(A.contents, 1)
	return result

/datum/testkit/proc/cmd_set(list/a)
	var/datum/D = need(thing(a["ref"]), "thing [json_encode(a["ref"])]")
	var/v = a["var"]
	if(!(v in D.vars))
		CRASH("[D.type] has no var [v]")
	var/value = in_value(a["value"])
	if(!D.vv_edit_var(v, value))
		D.vars[v] = value
	return out(D.vars[v])

/datum/testkit/proc/cmd_call(list/a)
	var/datum/D = a["ref"] && a["ref"] != "global" ? need(thing(a["ref"]), "thing [json_encode(a["ref"])]") : null
	var/proc_name = a["proc"]
	var/list/call_args = islist(a["args"]) ? in_value(a["args"]) : list()
	var/mob/user = a["user"] ? thing(a["user"]) : null
	if(user)
		usr = user
	if(D)
		if(!hascall(D, proc_name))
			CRASH("[D.type] has no proc [proc_name]")
		return out(call(D, proc_name)(arglist(call_args)), text2num("[a["depth"]]") || 2)
	var/path = text2path("/proc/[proc_name]")
	if(!path)
		CRASH("no global proc [proc_name]")
	return out(call(path)(arglist(call_args)), text2num("[a["depth"]]") || 2)

/datum/testkit/proc/cmd_del(list/a)
	var/datum/D = need(thing(a["ref"]), "thing [json_encode(a["ref"])]")
	qdel(D)
	return TRUE

/datum/testkit/proc/cmd_give(list/a)
	var/mob/living/M = need(thing(a["mob"]), "mob [a["mob"]]")
	var/obj/item/I
	if(a["type"])
		var/path = need(text2path(a["type"]), "type [a["type"]]")
		I = new path(get_turf(M))
	else
		I = need(thing(a["ref"]), "item [a["ref"]]")
	if(a["slot"])
		var/mob/living/carbon/human/H = M
		if(!istype(H) || !H.equip_to_slot_if_possible(I, text2num("[a["slot"]]"), disable_warning = TRUE))
			CRASH("couldn't put [I] in slot [a["slot"]]")
	else if(!M.put_in_hands(I))
		CRASH("hands full")
	return out(I)

/datum/testkit/proc/cmd_move(list/a)
	var/atom/movable/AM = need(thing(a["ref"]), "thing [a["ref"]]")
	if(a["dir"])
		var/dir = isnum(a["dir"]) ? a["dir"] : text2dir(uppertext(a["dir"]))
		return step(AM, dir) ? out(get_turf(AM)) : FALSE
	var/turf/T = need(where(a["to"]), "place [json_encode(a["to"])]")
	if(a["walk"])
		walk_to(AM, T, 0, ismob(AM) ? max(1, AM:movement_delay()) : 2)
		return "walking"
	AM.forceMove(T)
	return out(T)

/datum/testkit/proc/cmd_say(list/a)
	var/mob/M = need(thing(a["mob"]), "mob [a["mob"]]")
	M.say(a["text"])
	return TRUE

/datum/testkit/proc/cmd_intent(list/a)
	var/mob/living/M = need(thing(a["mob"]), "mob [a["mob"]]")
	if(a["intent"])
		M.a_intent = a["intent"]
	if(a["zone"])
		M.zone_selected = a["zone"]
	return list("intent" = M.a_intent, "zone" = M.zone_selected)

/datum/testkit/proc/cmd_use(list/a)
	var/mob/living/user = need(thing(a["user"]), "user [a["user"]]")
	var/atom/target = a["target"] ? need(thing(a["target"]), "target [a["target"]]") : null
	var/obj/item/item
	if(a["item"] == "held")
		item = user.get_active_held_item()
	else if(a["item"])
		item = need(thing(a["item"]), "item [a["item"]]")
	usr = user
	var/before = event_seq
	if(a["how"] == "click")
		user.next_move = 0
		user.ClickOn(target || item, a["params"] || "")
	else if(item && target)
		if(item.loc != user)
			user.put_in_active_hand(item)
		item.melee_attack_chain(user, target, a["params"] || "")
	else if(item)
		if(item.loc != user)
			user.put_in_active_hand(item)
		item.attack_self(user)
	else if(target)
		target.attack_hand(user)
	else
		CRASH("nothing to use")
	return list("events" = events_since(before, null, 50))

/datum/testkit/proc/cmd_damage(list/a)
	var/mob/living/M = need(thing(a["mob"]), "mob [a["mob"]]")
	if(a["brute"])
		M.adjustBruteLoss(a["brute"])
	if(a["burn"])
		M.adjustFireLoss(a["burn"])
	if(a["tox"])
		M.adjustToxLoss(a["tox"])
	if(a["oxy"])
		M.adjustOxyLoss(a["oxy"])
	if(a["stamina"])
		M.adjustStaminaLoss(a["stamina"])
	M.updatehealth()
	return list("health" = M.health, "stat" = M.stat)

// ---------------------------------------------------------------------------------------------
// Time
// ---------------------------------------------------------------------------------------------

/datum/testkit/proc/cmd_wait(list/a)
	var/seconds = clamp(text2num("[a["seconds"]]") || 1, 0.1, 600)
	sleep(seconds SECONDS)
	return world.time

/datum/testkit/proc/cmd_until(list/a)
	var/datum/D = need(thing(a["ref"]), "thing [a["ref"]]")
	var/v = a["var"]
	var/want = in_value(a["value"])
	var/op = a["op"] || "=="
	var/deadline = world.time + (text2num("[a["seconds"]]") || 30) SECONDS
	while(world.time < deadline)
		if(QDELETED(D))
			return list("met" = op == "deleted", "deleted" = TRUE, "time" = world.time)
		var/value = D.vars[v]
		var/met
		switch(op)
			if("==")
				met = value == want
			if("!=")
				met = value != want
			if(">")
				met = value > want
			if("<")
				met = value < want
			if("truthy")
				met = !!value
			if("falsy")
				met = !value
		if(met)
			return list("met" = TRUE, "value" = out(value), "time" = world.time)
		sleep(world.tick_lag)
	return list("met" = FALSE, "value" = out(D.vars[v]), "time" = world.time)

/datum/testkit
	var/paused_processing

/datum/testkit/proc/cmd_pause(list/a)
	if(Master.processing > 0)
		paused_processing = Master.processing
		Master.processing = 0
	return TRUE

/datum/testkit/proc/cmd_resume(list/a)
	if(Master.processing <= 0)
		Master.processing = paused_processing || CONFIG_GET(number/mc_tick_rate/base_mc_tick_rate)
	return TRUE

/datum/testkit/proc/cmd_speed(list/a)
	return timewarp_set_speed(a["speed"]) ? GLOB.timewarp_speed : "timewarp.dll didn't take it"

// ---------------------------------------------------------------------------------------------
// Arenas and resets
// ---------------------------------------------------------------------------------------------

/area/testkit
	name = "Testkit Arena"
	icon_state = "yellow"
	requires_power = FALSE
	has_gravity = STANDARD_GRAVITY
	dynamic_lighting = DYNAMIC_LIGHTING_DISABLED

/datum/testkit
	var/next_arena = 0
	/// id -> reservation
	var/list/arenas = list()

/datum/testkit/proc/cmd_arena(list/a)
	var/w = clamp(text2num("[a["w"]]") || 15, 3, 100)
	var/h = clamp(text2num("[a["h"]]") || 15, 3, 100)
	var/datum/turf_reservation/R = SSmapping.RequestBlockReservation(w + 2, h + 2)
	if(!R)
		CRASH("no reserved space left")
	var/id = "[++next_arena]"
	arenas[id] = R
	build_arena(R, a["floor"])
	var/list/low = R.bottom_left_coords
	return list("id" = id, "corner" = list(low[1] + 1, low[2] + 1, low[3]), "middle" = out(arena_middle(id)), "w" = w, "h" = h)

/datum/testkit/proc/build_arena(datum/turf_reservation/R, floor)
	var/floor_type = (floor && text2path(floor)) || /turf/open/floor/plasteel
	var/area/testkit/A = new
	var/list/low = R.bottom_left_coords
	var/list/high = R.top_right_coords
	for(var/turf/T as anything in R.reserved_turfs)
		var/area/old_area = T.loc
		if(old_area != A)
			old_area.contents -= T
			A.contents += T
			T.change_area(old_area, A)
		clear_turf(T)
		var/edge = T.x == low[1] || T.x == high[1] || T.y == low[2] || T.y == high[2]
		T.ChangeTurf(edge ? /turf/closed/indestructible/riveted : floor_type, flags = CHANGETURF_IGNORE_AIR)
		CHECK_TICK

/// Everything on a tile goes but lighting and players. Again until nothing's left: a locker deleted drops what it held there.
/datum/testkit/proc/clear_turf(turf/T)
	. = 0
	for(var/pass in 1 to 6)
		var/found = FALSE
		for(var/atom/movable/AM as anything in T.contents.Copy())
			if(QDELETED(AM) || istype(AM, /atom/movable/lighting_object))
				continue
			if(ismob(AM))
				var/mob/M = AM
				if(M.client || isobserver(M))
					continue
			found = TRUE
			qdel(AM, force = TRUE)
			.++
		if(!found)
			return

/datum/testkit/proc/arena_middle(id)
	var/datum/turf_reservation/R = arenas["[id]"]
	if(!R)
		return null
	var/list/low = R.bottom_left_coords
	var/list/high = R.top_right_coords
	return locate(round((low[1] + high[1]) / 2), round((low[2] + high[2]) / 2), low[3])

/datum/testkit/proc/cmd_arena_reset(list/a)
	var/datum/turf_reservation/R = need(arenas["[a["id"]]"], "arena [a["id"]]")
	build_arena(R, a["floor"])
	return TRUE

/datum/testkit/proc/cmd_arena_free(list/a)
	var/datum/turf_reservation/R = need(arenas["[a["id"]]"], "arena [a["id"]]")
	build_arena(R)
	arenas -= "[a["id"]]"
	qdel(R)
	return TRUE

/datum/testkit/proc/cmd_reset_area(list/a)
	var/area/A = need(find_area(a["area"]), "area [a["area"]]")
	var/x1 = world.maxx
	var/y1 = world.maxy
	var/x2 = 0
	var/y2 = 0
	var/z
	for(var/turf/T in A)
		if(!is_station_level(T.z))
			continue
		z = T.z
		x1 = min(x1, T.x)
		y1 = min(y1, T.y)
		x2 = max(x2, T.x)
		y2 = max(y2, T.y)
	if(!z)
		CRASH("[A] has no station tiles")
	return cmd_reset_rect(list("x1" = x1, "y1" = y1, "x2" = x2, "y2" = y2, "z" = z))

/// The station's tiles in a rectangle back as the map has them: what's on them goes (mobs with a player excepted), the map loads again
/datum/testkit/proc/cmd_reset_rect(list/a)
	var/z = text2num("[a["z"]]") || SSmapping.station_start
	var/x1 = text2num("[a["x1"]]")
	var/y1 = text2num("[a["y1"]]")
	var/x2 = text2num("[a["x2"]]")
	var/y2 = text2num("[a["y2"]]")
	if(!x1 || !y1 || !x2 || !y2)
		CRASH("x1, y1, x2, y2 wanted")
	var/list/files = SSmapping.config.map_file
	if(!islist(files))
		files = list(files)
	var/z_index = z - SSmapping.station_start + 1
	if(z_index < 1 || z_index > length(files))
		CRASH("z [z] isn't a station level loaded from a single-level file")
	var/started = REALTIMEOFDAY
	var/cleared = 0
	for(var/turf/T in block(locate(x1, y1, z), locate(x2, y2, z)))
		cleared += clear_turf(T)
		CHECK_TICK
	// as map_template/load(): the border's air stops until initTemplateBounds() hands it back
	for(var/turf/border as anything in block(locate(max(x1 - 1, 1), max(y1 - 1, 1), z), locate(min(x2 + 1, world.maxx), min(y2 + 1, world.maxy), z)))
		SSair.remove_from_active(border)
		border.atmos_adjacent_turfs?.Cut()
		TILE_ENGINE_DIRTY(border)
	var/datum/parsed_map/pm = new(file("_maps/[SSmapping.config.map_path]/[files[z_index]]"), x1, x2, y1, y2)
	if(!pm.bounds)
		CRASH("the map didn't parse")
	pm.load(1, 1, z, cropMap = TRUE, no_changeturf = FALSE, x_lower = x1, x_upper = x2, y_lower = y1, y_upper = y2)
	pm.initTemplateBounds()
	event("testkit.reset", list("x1" = x1, "y1" = y1, "x2" = x2, "y2" = y2, "z" = z))
	return list("cleared" = cleared, "ms" = (REALTIMEOFDAY - started) * 100)
