// The bots' A* searches in the path engine (tools/path_engine, hippie_path.dll; the user's go 2026-11-08, "stage 1").
//
// Bot pathfinding was about a quarter of the server's time in the stress bench: 12,254 searches a round opened four million tiles,
// ~21 us each, nearly all of it AStar()'s own loop, its nodes and its heap, and the route checks asked once per neighbour. The
// engine runs the search itself, the same steps as AStar() (the same heap, the same single-precision node weights), so the path
// is the same one, and asks DM what each tile allows the first time the search needs it, a batch at a time: one pass over the
// tile's contents answers every way into and out of it (the loop in path_engine_search(), the same rules as bot_reachable_strict()
// and bot_reachable_permissive()). Nothing is kept from one search to the next, so nothing it goes by is older than it would have
// been. In a disaster round, shadowed: 10,025 searches, every one the same path (or none) as AStar()'s, in 505 us on average
// against AStar()'s 1,052. What's left is mostly DM looking at the tiles (~3 us a tile); the engine itself is under 0.5 us.
//
// World params: path-engine=dm leaves AStar() as it was; path-engine=shadow runs both and checks the engine's answer against
// AStar()'s for every search, using AStar()'s (data/path_engine_check.txt); path-lib=<name> loads another build of the library.

#define PATH_ENGINE_VERSION 1

GLOBAL_VAR_INIT(path_engine_lib, world.params["path-lib"] || "hippie_path")
/// null until the first search, then TRUE if the engine is doing the bots' searches, FALSE if not
GLOBAL_VAR(path_engine_on)
GLOBAL_VAR_INIT(path_engine_shadow, FALSE)
GLOBAL_VAR_INIT(path_engine_status, "not started")
GLOBAL_VAR_INIT(path_engine_maxx, 0)
GLOBAL_VAR_INIT(path_engine_maxy, 0)
/// path-engine=shadow: what the checks found
GLOBAL_LIST_INIT(path_engine_check, list("checked" = 0, "same" = 0, "different" = 0, "different, the world moved on" = 0, "native us" = 0, "dm us" = 0, "native searches" = 0, "dm searches" = 0))
GLOBAL_LIST_EMPTY(path_engine_samples)
/// tools/path_bench sets this to a list to have path_engine_search() note where its time goes
GLOBAL_VAR(path_engine_timing)
/// Slow steps logged so far (world.log), up to 20
GLOBAL_VAR_INIT(path_engine_slow_noted, 0)

/// The turfs the ground checks look at more closely than its density: space, the floors bot_turf_is_deadly() knows, and pools
GLOBAL_LIST_INIT(path_engine_special_types, typecacheof(list(/turf/open/space, /turf/open/lava, /turf/open/chasm, /turf/open/pool)))
GLOBAL_LIST_INIT(path_engine_deadly_types, typecacheof(list(/turf/open/space/transit, /turf/open/lava, /turf/open/chasm)))
/// bot_turf_penalty() by type: what each adds, or how to work it out
#define PATH_ENGINE_PENALTY_AIRLOCK -1
#define PATH_ENGINE_PENALTY_FIREDOOR -2
GLOBAL_LIST_INIT(path_engine_penalties, path_engine_penalty_types())

/proc/path_engine_penalty_types()
	. = list()
	for(var/list/kind in list(list(/obj/structure/window, 60), list(/obj/structure/grille, 10), list(/obj/machinery/door/window, 20), \
		list(/obj/machinery/door/airlock, PATH_ENGINE_PENALTY_AIRLOCK), list(/obj/machinery/door/firedoor, PATH_ENGINE_PENALTY_FIREDOOR), list(/obj/structure/table, 8)))
		for(var/type in typesof(kind[1]))
			.[type] = kind[2]

/proc/path_engine_setup()
	GLOB.path_engine_on = FALSE
	var/mode = world.params["path-engine"]
	if(mode == "dm")
		GLOB.path_engine_status = "off (path-engine=dm)"
		log_world("Path engine: [GLOB.path_engine_status]")
		return
	if(world.system_type != MS_WINDOWS || !fexists("[GLOB.path_engine_lib].dll"))
		GLOB.path_engine_status = "off: no [GLOB.path_engine_lib].dll"
		log_world("Path engine: [GLOB.path_engine_status]")
		return
	var/list/turfs = list()
	var/list/coordinates = list()
	for(var/list/spot in list(list(1, 1, 1), list(world.maxx, 1, 1), list(1, world.maxy, 1), list(world.maxx, world.maxy, world.maxz), list(round(world.maxx / 2), round(world.maxy / 3), max(1, world.maxz - 1))))
		var/turf/T = locate(spot[1], spot[2], spot[3])
		if(T)
			turfs += T
			coordinates += spot
	var/result
	try
		result = call_ext(GLOB.path_engine_lib, "byond:path_setup")(world.maxx, world.maxy, world.maxz, turfs, coordinates)
	catch(var/exception/error)
		result = "[error]"
	if(result != PATH_ENGINE_VERSION)
		GLOB.path_engine_status = "off: [result]"
		log_world("Path engine: [GLOB.path_engine_status]")
		return
	GLOB.path_engine_maxx = world.maxx
	GLOB.path_engine_maxy = world.maxy
	GLOB.path_engine_on = TRUE
	GLOB.path_engine_shadow = (mode == "shadow")
	GLOB.path_engine_status = GLOB.path_engine_shadow ? "shadowing AStar()" : "on"
	log_world("Path engine: [GLOB.path_engine_status]")

/// Whether this search is one the engine does: the bots' two kinds
/proc/path_engine_takes(dist, adjacent, list/explored)
	if(GLOB.path_engine_on == FALSE || (explored && explored["dm_only"]))
		return FALSE
	if(adjacent != /turf/proc/bot_reachable_strict && adjacent != /turf/proc/bot_reachable_permissive)
		return FALSE
	if(dist != /turf/proc/Distance_cardinal && dist != /turf/proc/bot_weighted_distance)
		return FALSE
	if(isnull(GLOB.path_engine_on) || world.maxx != GLOB.path_engine_maxx || world.maxy != GLOB.path_engine_maxy)
		path_engine_setup() // first search, or the world grew: turfs are numbered by the world's size
	return GLOB.path_engine_on

/// AStar() (code/__HELPERS/AStar.dm) from after its checks, for the searches path_engine_takes(): the same path, the same explored
/// and the same tally. PATH_ENGINE_FALLBACK when AStar() should do it.
/proc/path_engine_astar(caller, turf/start, turf/end, dist, maxnodedepth, mintargetdist, adjacent, id, turf/exclude, simulated_only, list/explored)
	if(GLOB.path_engine_shadow)
		return path_engine_shadow(caller, start, end, dist, maxnodedepth, mintargetdist, adjacent, id, exclude, simulated_only, explored)
	var/list/result = path_engine_search(caller, start, end, dist, maxnodedepth, mintargetdist, adjacent, id, exclude, simulated_only, TRUE)
	if(!result)
		return PATH_ENGINE_FALLBACK
	var/list/tally = GLOB.astar_tally
	tally["searches"]++
	tally["turfs"] += result[2]
	if(result[1])
		return result[1]
	tally["failed"]++
	tally["failed_turfs"] += result[2]
	if(explored)
		explored["reached"] = result[3]
		explored["depth_cut"] = result[4]
	return null

/// The search: list(path or null, tiles opened, every tile opened as keys (no path only), whether maxnodedepth cut it short), or
/// null if the engine couldn't do it. Yields between batches like AStar() does if `yields`.
/proc/path_engine_search(caller, turf/start, turf/end, dist, maxnodedepth, mintargetdist, adjacent, id, turf/exclude, simulated_only, yields)
	var/weighted = (dist == /turf/proc/bot_weighted_distance)
	var/permissive = (adjacent == /turf/proc/bot_reachable_permissive)
	var/end_penalty = weighted ? bot_turf_penalty(end) : 0
	// the next nodes on the open list to ask about the tiles of as well, when it has to ask (search.rs): 4 asked 40% less often for
	// 2% more tiles than none (tools/path_bench, 2026-11-08). path-ahead=N to try another.
	var/static/ahead = isnull(text2num(world.params["path-ahead"])) ? 4 : clamp(text2num(world.params["path-ahead"]), 0, 255)
	var/search = call_ext(GLOB.path_engine_lib, "byond:path_begin")(start, end, maxnodedepth || 0, mintargetdist || 0, (weighted ? 2 : 1) + ahead * 256, end_penalty, exclude)
	if(!isnum(search) || search <= 0)
		return null
	// What doesn't change over the search
	var/may_jump = bot_may_jump_in(caller)
	var/mob/living/carbon/human/H = caller
	var/space_ok = istype(H) && H.bot_brain && H.bot_brain.is_space_protected_without_boots()
	// the turf lists only when there's anything in them: mostly there isn't
	var/list/trapdoors = length(GLOB.bot_open_trapdoors) ? GLOB.bot_open_trapdoors : null
	var/list/field_turfs = length(GLOB.bot_field_turfs) ? GLOB.bot_field_turfs : null
	var/list/generator_turfs = length(GLOB.bot_field_generator_turfs) ? GLOB.bot_field_generator_turfs : null
	var/list/hazards = length(GLOB.bot_hazard_turfs) ? GLOB.bot_hazard_turfs : null
	var/list/space_types = SSpathfinder.space_type_cache
	var/list/special_types = GLOB.path_engine_special_types
	var/list/deadly_types = GLOB.path_engine_deadly_types
	var/list/penalties = (weighted && permissive) ? GLOB.path_engine_penalties : null
	var/list/cardinals = GLOB.cardinals
	var/list/answers = list()
	var/list/out = list()
	var/status
	var/list/timing = GLOB.path_engine_timing // tools/path_bench: where the time goes
	var/mark
	while(TRUE)
		var/step_started = TICK_USAGE_REAL
		if(timing)
			mark = step_started
		status = call_ext(GLOB.path_engine_lib, "byond:path_step")(search, answers, out)
		var/step_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - step_started)
		if(step_ms > 20 && GLOB.path_engine_slow_noted < 20)
			GLOB.path_engine_slow_noted++
			log_world("Path engine: one step took [round(step_ms, 0.1)] ms (status [status], [length(out)] in the list, [length(answers)] answers)")
		if(timing)
			timing["engine us"] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - mark) * 1000
			mark = TICK_USAGE_REAL
		if(status != 1)
			break
		answers.len = length(out)
		// What a bot may do on each tile, as the engine wants it (tools/path_engine/src/search.rs): the ways onto it that are refused
		// (bits 0-3, by the direction to the tile stepped from), the ways off it that are (bits 4-7) and, for the weighted cost, its
		// penalty times 256. The same checks as bot_reachable_strict()/bot_link_blocked_strict() and bot_reachable_permissive()/
		// bot_link_blocked_permissive(), each tile once for every way in and out of it, here and not in a proc of their own because
		// a proc call is a fair part of the cost of most tiles. A tile nothing can step onto only matters as where the search starts.
		for(var/i in 1 to length(out))
			var/turf/T = out[i]
			var/bits = 0
			var/blocked = T.density || (trapdoors && trapdoors[T]) || (field_turfs && field_turfs[T]) || (generator_turfs && generator_turfs[T] && bot_turf_has_active_field(T))
			// space, the deadly kinds of floor (bot_turf_is_deadly()) and pools, in one look at the type
			var/special = !blocked && special_types[T.type]
			if(special)
				blocked = (deadly_types[T.type] && bot_turf_is_deadly(T)) || (simulated_only && space_types[T.type] && !(space_ok && bot_turf_has_pushoff_backup(T)))
			if(blocked)
				if(T != start)
					answers[i] = 15
					if(timing)
						timing["blocked"]++
					continue
				bits = 15
			else
				if(special && !may_jump && istype(T, /turf/open/pool)) //bot_steps_into_pool()
					for(var/dir in cardinals)
						if(!istype(get_step(T, dir), /turf/open/pool))
							bits |= dir
				if(hazards && hazards[T])
					for(var/dir in cardinals)
						var/turf/from = get_step(T, dir)
						if(from && !(bits & dir) && bot_steps_into_hazard(from, T, caller))
							bits |= dir
			if(timing)
				timing["contents"] += length(T.contents)
			var/exits = 0
			var/penalty = 0
			if(permissive)
				for(var/obj/O in T)
					if(penalties) // bot_turf_penalty(), in the same pass
						var/kind = penalties[O.type]
						if(kind > 0)
							penalty += kind
						else if(kind == PATH_ENGINE_PENALTY_AIRLOCK)
							var/obj/machinery/door/airlock/A = O
							if(A.density)
								penalty += A.security_level ? 25 : 8
								if(A.welded)
									penalty += 15
						else if(kind == PATH_ENGINE_PENALTY_FIREDOOR)
							var/obj/machinery/door/firedoor/F = O
							if(F.density && F.welded)
								penalty += 15
					if(!O.density && !O.astar_always_asks)
						continue // passed by bot_can_astar_pass_permissive(): their CanAStarPass() is !density
					if(bits != 15)
						for(var/dir in cardinals)
							if(!(bits & dir) && !bot_can_astar_pass_permissive(O, id, dir, caller))
								bits |= dir
					if(O.density && (istype(O, /obj/structure/window) || istype(O, /obj/machinery/door/window))) // not dense: CanAStarPass() lets it by
						for(var/dir in cardinals)
							if(!(exits & dir) && !O.CanAStarPass(id, dir) && !bot_can_break_through(O, caller))
								exits |= dir
			else
				for(var/atom/movable/AM as anything in T)
					if(!AM.density)
						if(bits != 15 && isobj(AM))
							var/obj/door = AM
							if(door.astar_always_asks)
								for(var/dir in cardinals)
									if(!(bits & dir) && !door.CanAStarPass(id, dir, caller))
										bits |= dir
						continue
					if(isobj(AM))
						var/obj/O = AM
						if(bits != 15)
							for(var/dir in cardinals)
								if(!(bits & dir) && !O.CanAStarPass(id, dir, caller))
									bits |= dir
						if(istype(O, /obj/structure/window) || istype(O, /obj/machinery/door/window))
							for(var/dir in cardinals)
								if(!(exits & dir) && !O.CanAStarPass(id, dir))
									exits |= dir
					else if(isliving(AM))
						var/mob/living/L = AM
						if(L.buckled) //bot_turf_has_seated_mob()
							bits = 15
			bits |= exits << 4
			if(weighted && (bits & 15) != 15)
				bits += (penalties ? penalty : bot_turf_penalty(T)) * 256
			answers[i] = bits
		if(timing)
			timing["tiles us"] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - mark) * 1000
			timing["rounds"]++
			timing["tiles"] += length(out)
		if(yields)
			CHECK_TICK
	switch(status)
		if(2) // out: how many tiles it opened, then the path
			var/opened = out[1]
			out.Cut(1, 2)
			return list(out, opened, null, FALSE)
		if(3) // out: how many it opened, whether maxnodedepth cut it short, then every tile it opened
			var/opened = out[1]
			var/depth_cut = out[2]
			var/list/reached = list()
			var/build_started = TICK_USAGE_REAL
			var/build_ms = 0
			for(var/i in 3 to length(out))
				reached[out[i]] = TRUE
				if(yields && !(i % 1000)) // tens of thousands of tiles after a breach: not all in one tick
					build_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - build_started)
					CHECK_TICK
					build_started = TICK_USAGE_REAL
			build_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - build_started)
			if(build_ms > 20 && GLOB.path_engine_slow_noted < 20)
				GLOB.path_engine_slow_noted++
				log_world("Path engine: the [length(out) - 2] tiles a search opened took [round(build_ms, 0.1)] ms to list")
			return list(null, opened, reached, depth_cut)
		if(4) // AStar() would have had a runtime error here: let it
			return null
	call_ext(GLOB.path_engine_lib, "byond:path_forget")(search) // an error: logged in the server's output
	return null

/// path-engine=shadow: the engine's search, then AStar()'s in the same tick, and every difference noted. AStar()'s answer is the one used.
/proc/path_engine_shadow(caller, turf/start, turf/end, dist, maxnodedepth, mintargetdist, adjacent, id, turf/exclude, simulated_only, list/explored)
	var/list/check = GLOB.path_engine_check
	var/started = TICK_USAGE_REAL
	var/list/native = path_engine_search(caller, start, end, dist, maxnodedepth, mintargetdist, adjacent, id, exclude, simulated_only, FALSE)
	var/native_us = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) * 1000
	var/time = world.time
	var/list/dm_explored = list("dm_only" = TRUE)
	var/turfs_before = GLOB.astar_tally["turfs"]
	started = TICK_USAGE_REAL
	var/list/path = AStar(caller, end, dist, 0, maxnodedepth, mintargetdist, adjacent, id, exclude, simulated_only, dm_explored)
	var/dm_us = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started) * 1000
	var/dm_opened = GLOB.astar_tally["turfs"] - turfs_before
	if(explored && !path)
		explored["reached"] = dm_explored["reached"]
		explored["depth_cut"] = dm_explored["depth_cut"]
	if(!native)
		return path
	check["checked"]++
	var/yielded = world.time != time
	if(!yielded) // timings only for searches AStar() did in one go
		check["native us"] += native_us
		check["dm us"] += dm_us
		check["native searches"]++
	var/why
	if(!!path != !!native[1])
		why = path ? "AStar() found a path, the engine none" : "the engine found a path, AStar() none"
	else if(path)
		var/list/other = native[1]
		if(length(path) != length(other))
			why = "paths [length(path)] and [length(other)] long"
		else
			for(var/i in 1 to length(path))
				if(path[i] != other[i])
					why = "the paths part at step [i]"
					break
	else
		var/list/dm_reached = dm_explored["reached"]
		var/list/reached = native[3]
		if(length(dm_reached) != length(reached))
			why = "no path, but [length(dm_reached)] tiles opened against [length(reached)]"
		else if(!!dm_explored["depth_cut"] != !!native[4])
			why = "no path, but cut short [dm_explored["depth_cut"] ? "by AStar() only" : "by the engine only"]"
		else
			for(var/turf/T as anything in dm_reached)
				if(!reached[T])
					why = "no path, but the engine never opened [T.x],[T.y]"
					break
	if(!why && dm_opened != native[2])
		why = "the same answer, but [dm_opened] tiles opened against [native[2]]"
	if(!why)
		check["same"]++
	else
		var/kind = yielded ? "different, the world moved on" : "different"
		check[kind]++
		if(length(GLOB.path_engine_samples) < 40)
			GLOB.path_engine_samples += "[kind]: [why]; [caller] from [start.x],[start.y],[start.z] to [end.x],[end.y] ([adjacent == /turf/proc/bot_reachable_permissive ? "permissive" : "strict"], [dist == /turf/proc/bot_weighted_distance ? "weighted" : "cardinal"], depth [maxnodedepth])"
	if(check["checked"] % 100 == 0 || why)
		path_engine_write_check()
	return path

/proc/path_engine_write_check()
	var/list/check = GLOB.path_engine_check
	var/list/lines = list("Path engine against AStar(), [time_stamp()]:")
	lines += "[check["checked"]] searches checked: the same [check["same"]], different [check["different"]], different with the world changed while AStar() yielded [check["different, the world moved on"]]"
	if(check["native searches"])
		lines += "Done in one go by both ([check["native searches"]]): the engine [round(check["native us"] / check["native searches"], 0.1)] us a search, AStar() [round(check["dm us"] / check["native searches"], 0.1)] us"
	var/list/stats = list()
	call_ext(GLOB.path_engine_lib, "byond:path_stats")(stats)
	if(length(stats) >= 8)
		lines += "Engine: [stats[1]] begun, [stats[2]] found, [stats[3]] no route, [stats[4]] handed back, [stats[5]] rounds, [stats[6]] tiles asked about, [stats[7]] opened, [stats[8]] open now"
	lines += GLOB.path_engine_samples
	fdel("data/path_engine_check.txt")
	text2file(jointext(lines, "\n"), "data/path_engine_check.txt")

#undef PATH_ENGINE_VERSION
#undef PATH_ENGINE_PENALTY_AIRLOCK
#undef PATH_ENGINE_PENALTY_FIREDOOR
