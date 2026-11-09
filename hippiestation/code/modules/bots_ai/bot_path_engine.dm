// The bots' A* searches in the path engine (tools/path_engine, hippie_path.dll; the user's go 2026-11-08, "stage 1", and 2026-11-09,
// "stage 2").
//
// Bot pathfinding was about a quarter of the server's time in the stress bench: 12,254 searches a round opened four million tiles,
// ~21 us each, nearly all of it AStar()'s own loop, its nodes and its heap, and the route checks asked once per neighbour. The
// engine runs the search itself, the same steps as AStar() (the same heap, the same single-precision node weights), so the path
// is the same one, and asks DM what each tile allows the first time the search needs it, a batch at a time: one pass over the
// tile's contents answers every way into and out of it (the loop in path_engine_search(), the same rules as bot_reachable_strict()
// and bot_reachable_permissive()). In a disaster round, shadowed: 10,025 searches, every one the same path (or none) as AStar()'s,
// in 505 us on average against AStar()'s 1,052; most of what was left was DM looking at the tiles (~3 us a tile).
//
// Stage 2: the station picture (hippiestation/code/modules/station_picture/station_picture.dm) keeps, between searches, the tiles
// whose answer is the same for every bot and every search (open floor with nothing in the way on it, solid turf), and hears when
// they change, so DM is only asked about the rest (doors, windows, tables, machines...) and about tiles that changed. And a search
// with no route leaves the tiles it opened in the engine as a region (/datum/path_region) for the bots' region checks to ask about,
// instead of a list of 10,000-odd tiles built here.
//
// World params: path-engine=dm leaves AStar() as it was; path-engine=shadow runs both and checks the engine's answer against
// AStar()'s for every search, using AStar()'s (data/path_engine_check.txt); path-lib=<name> loads another build of the library;
// path-picture=off|check (station_picture.dm).

#define PATH_ENGINE_VERSION 3

/// The station picture's kinds (tools/path_engine/src/picture.rs), sent above each answer, times this
#define PATH_PICTURE_UNIT 1048576
#define PATH_PICTURE_OPEN 1
#define PATH_PICTURE_SOLID 2
#define PATH_PICTURE_OPEN_SPACE 3
#define PATH_PICTURE_VOLATILE 4
/// path_begin()'s mode, besides the cost and the look-ahead (tools/path_engine/src/lib.rs)
#define PATH_MODE_SIMULATED_ONLY 16
#define PATH_MODE_PICTURE_OFF 32
#define PATH_MODE_PICTURE_CHECK 64
#define PATH_MODE_RETURN_TILES 128
#define PATH_MODE_BACKWARD 256
#define PATH_MODE_STOP_AT_HUB 512

GLOBAL_VAR_INIT(path_engine_lib, world.params["path-lib"] || "hippie_path")
/// null until the first search, then TRUE if the engine is doing the bots' searches, FALSE if not
GLOBAL_VAR(path_engine_on)
GLOBAL_VAR_INIT(path_engine_shadow, FALSE)
GLOBAL_VAR_INIT(path_engine_status, "not started")
GLOBAL_VAR_INIT(path_engine_maxx, 0)
GLOBAL_VAR_INIT(path_engine_maxy, 0)
/// "on", "off" or "check": what the engine does with the station picture (path-picture)
GLOBAL_VAR_INIT(path_picture_mode, "on")
/// path-engine=shadow: what the checks found
GLOBAL_LIST_INIT(path_engine_check, list("checked" = 0, "same" = 0, "different" = 0, "different, the world moved on" = 0, "native us" = 0, "dm us" = 0, "native searches" = 0, "dm searches" = 0))
GLOBAL_LIST_EMPTY(path_engine_samples)
/// path-picture=check: the tiles the picture would have answered differently, described
GLOBAL_LIST_EMPTY(path_picture_samples)
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
	GLOB.station_picture_kept = FALSE
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
	var/picture = world.params["path-picture"]
	GLOB.path_picture_mode = (picture == "off" || picture == "check") ? picture : "on"
	// a fresh picture: nothing to hear of from before it (the engine starts it empty)
	GLOB.station_picture_dirty.Cut()
	GLOB.station_picture_kept = (GLOB.path_picture_mode != "off")
	GLOB.path_engine_status = "[GLOB.path_engine_shadow ? "shadowing AStar()" : "on"], station picture [GLOB.path_picture_mode]"
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
	if(GLOB.path_picture_mode == "check" && !(tally["searches"] % 500))
		path_engine_write_check() // what the picture check has found so far
	tally["turfs"] += result[2]
	if(result[1])
		return result[1]
	tally["failed"]++
	tally["failed_turfs"] += result[2]
	if(explored)
		explored["reached"] = result[3]
		explored["depth_cut"] = result[4]
	return null

/// The search: list(path or null, tiles opened, what it opened (no path only: a /datum/path_region, or with `return_tiles` every tile
/// opened as keys), whether maxnodedepth cut it short), or null if the engine couldn't do it. Yields between batches like AStar() does
/// if `yields`.
/proc/path_engine_search(caller, turf/start, turf/end, dist, maxnodedepth, mintargetdist, adjacent, id, turf/exclude, simulated_only, yields, return_tiles = FALSE)
	var/weighted = (dist == /turf/proc/bot_weighted_distance)
	var/permissive = (adjacent == /turf/proc/bot_reachable_permissive)
	var/end_penalty = weighted ? bot_turf_penalty(end) : 0
	// the next nodes on the open list to ask about the tiles of as well, when it has to ask (search.rs): 4 asked 40% less often for
	// 2% more tiles than none (tools/path_bench, 2026-11-08). path-ahead=N to try another.
	var/static/ahead = isnull(text2num(world.params["path-ahead"])) ? 4 : clamp(text2num(world.params["path-ahead"]), 0, 255)
	var/mode = (weighted ? 2 : 1) + ahead * 256
	if(simulated_only)
		mode += PATH_MODE_SIMULATED_ONLY
	switch(GLOB.path_picture_mode)
		if("off")
			mode += PATH_MODE_PICTURE_OFF
		if("check")
			mode += PATH_MODE_PICTURE_CHECK
	if(return_tiles)
		mode += PATH_MODE_RETURN_TILES
	if(GLOB.station_picture_kept)
		station_picture_flush() // what's changed since the last search, before this one goes by the picture
	var/search = call_ext(GLOB.path_engine_lib, "byond:path_begin")(start, end, maxnodedepth || 0, mintargetdist || 0, mode, end_penalty, exclude)
	if(!isnum(search) || search <= 0)
		return null
	var/list/out = list()
	var/status = path_engine_rounds(search, "byond:path_step", caller, start, id, simulated_only, permissive, weighted, yields, out)
	switch(status)
		if(2) // out: how many tiles it opened, then the path
			var/opened = out[1]
			out.Cut(1, 2)
			return list(out, opened, null, FALSE)
		if(3) // out: how many it opened, whether maxnodedepth cut it short, the region's number, then (return_tiles) every tile it opened
			var/opened = out[1]
			var/depth_cut = out[2]
			if(!return_tiles)
				return list(null, opened, new /datum/path_region(out[3], opened), depth_cut)
			var/list/reached = list()
			var/build_started = TICK_USAGE_REAL
			var/build_ms = 0
			for(var/i in 4 to length(out))
				reached[out[i]] = TRUE
				if(yields && !(i % 1000)) // tens of thousands of tiles after a breach: not all in one tick
					build_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - build_started)
					CHECK_TICK
					build_started = TICK_USAGE_REAL
			build_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - build_started)
			if(build_ms > 20 && GLOB.path_engine_slow_noted < 20)
				GLOB.path_engine_slow_noted++
				log_world("Path engine: the [length(out) - 3] tiles a search opened took [round(build_ms, 0.1)] ms to list")
			return list(null, opened, reached, depth_cut)
		if(4) // AStar() would have had a runtime error here: let it
			return null
	call_ext(GLOB.path_engine_lib, "byond:path_forget")(search) // an error: logged in the server's output
	return null

/// The rounds of a search or a flood: the engine says which tiles it wants told about, DM says what each allows (and its kind for
/// the station picture), until it's done. Returns the last status; `out` holds what the engine wrote last. `start` is the tile a
/// blocked tile is still looked at for (a search's start), or null.
/proc/path_engine_rounds(handle, step_fn, caller, turf/start, id, simulated_only, permissive, weighted, yields, list/out)
	// What doesn't change over it
	var/may_jump = bot_may_jump_in(caller)
	var/mob/living/carbon/human/H = caller
	var/space_ok = istype(H) && H.bot_brain && H.bot_brain.is_space_protected_without_boots()
	var/list/trapdoors
	var/list/field_turfs
	var/list/generator_turfs
	var/list/hazards
	var/list/space_types = SSpathfinder.space_type_cache
	var/list/special_types = GLOB.path_engine_special_types
	var/list/deadly_types = GLOB.path_engine_deadly_types
	var/list/penalties = (weighted && permissive) ? GLOB.path_engine_penalties : null
	var/list/inert = GLOB.station_picture_inert
	// whose answer is for one side only: windows and windoors face a way, and a door's button is on one side of it
	// (bot_doors.dm). Anything else answers the same from every side, so it's asked once.
	var/static/list/one_side = typecacheof(list(/obj/structure/window, /obj/machinery/door))
	var/list/cardinals = GLOB.cardinals
	var/list/answers = list()
	var/status
	var/list/timing = GLOB.path_engine_timing // tools/path_bench: where the time goes
	var/mark
	while(TRUE)
		if(GLOB.station_picture_kept && length(GLOB.station_picture_dirty))
			station_picture_flush() // changed while the search yielded
		var/step_started = TICK_USAGE_REAL
		if(timing)
			mark = step_started
		status = call_ext(GLOB.path_engine_lib, step_fn)(handle, answers, out)
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
		// the turf lists, only when there's anything in them (mostly there isn't), read each round: the hazards are a new list
		// every few seconds, and one kept from before a yield told the station picture a new hazard tile was open floor
		trapdoors = length(GLOB.bot_open_trapdoors) ? GLOB.bot_open_trapdoors : null
		field_turfs = length(GLOB.bot_field_turfs) ? GLOB.bot_field_turfs : null
		generator_turfs = length(GLOB.bot_field_generator_turfs) ? GLOB.bot_field_generator_turfs : null
		hazards = length(GLOB.bot_hazard_turfs) ? GLOB.bot_hazard_turfs : null
		// What a bot may do on each tile, as the engine wants it (tools/path_engine/src/search.rs): the ways onto it that are refused
		// (bits 0-3, by the direction to the tile stepped from), the ways off it that are (bits 4-7) and, for the weighted cost, its
		// penalty times 256. The same checks as bot_reachable_strict()/bot_link_blocked_strict() and bot_reachable_permissive()/
		// bot_link_blocked_permissive(), each tile once for every way in and out of it, here and not in a proc of their own because
		// a proc call is a fair part of the cost of most tiles. A tile nothing can step onto only matters as where the search starts.
		// Above that, the tile's kind for the station picture (picture.rs): solid turf, open floor or space with nothing on it that
		// could be in the way, or asked about every time.
		for(var/i in 1 to length(out))
			var/turf/T = out[i]
			var/bits = 0
			var/listed = (trapdoors && trapdoors[T]) || (field_turfs && field_turfs[T]) || (generator_turfs && generator_turfs[T] && bot_turf_has_active_field(T))
			var/blocked = T.density || listed
			// space, the deadly kinds of floor (bot_turf_is_deadly()) and pools, in one look at the type
			var/special = !blocked && special_types[T.type]
			if(special)
				blocked = (deadly_types[T.type] && bot_turf_is_deadly(T)) || (simulated_only && space_types[T.type] && !(space_ok && bot_turf_has_pushoff_backup(T)))
			var/kind
			if(T.density)
				kind = PATH_PICTURE_SOLID
			else if(listed || (hazards && hazards[T]) || (special && (!space_types[T.type] || deadly_types[T.type])))
				kind = PATH_PICTURE_VOLATILE
			else
				kind = special ? PATH_PICTURE_OPEN_SPACE : PATH_PICTURE_OPEN // odd: still to look at what's on it
			if(blocked)
				if(T != start)
					// nothing steps onto it, but a backward flood (bot_sealed_pocket()) asks what can step off it, and DM's adjacency
					// still minds a window on the tile stepped from: open space with windows round a hull, to a bot that can't cross it
					var/blocked_exits = 0
					if(!T.density)
						for(var/obj/O in T)
							if(O.density && (istype(O, /obj/structure/window) || istype(O, /obj/machinery/door/window)))
								for(var/dir in cardinals)
									if(!(blocked_exits & dir) && !O.CanAStarPass(id, dir) && !(permissive && bot_can_break_through(O, caller)))
										blocked_exits |= dir
					answers[i] = 15 + (blocked_exits << 4) + (kind == PATH_PICTURE_SOLID ? PATH_PICTURE_SOLID : PATH_PICTURE_VOLATILE) * PATH_PICTURE_UNIT
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
					if((kind & 1) && (O.density || O.astar_always_asks || !inert[O.type]))
						kind = PATH_PICTURE_VOLATILE
					if(penalties) // bot_turf_penalty(), in the same pass
						var/kind_of_penalty = penalties[O.type]
						if(kind_of_penalty > 0)
							penalty += kind_of_penalty
						else if(kind_of_penalty == PATH_ENGINE_PENALTY_AIRLOCK)
							var/obj/machinery/door/airlock/A = O
							if(A.density)
								penalty += A.security_level ? 25 : 8
								if(A.welded)
									penalty += 15
						else if(kind_of_penalty == PATH_ENGINE_PENALTY_FIREDOOR)
							var/obj/machinery/door/firedoor/F = O
							if(F.density && F.welded)
								penalty += 15
					if(!O.density && !O.astar_always_asks)
						continue // passed by bot_can_astar_pass_permissive(): their CanAStarPass() is !density
					if(bits != 15)
						if(!one_side[O.type])
							if(!bot_can_astar_pass_permissive(O, id, NORTH, caller))
								bits |= 15
						else
							for(var/dir in cardinals)
								if(!(bits & dir) && !bot_can_astar_pass_permissive(O, id, dir, caller))
									bits |= dir
					if(O.density && (istype(O, /obj/structure/window) || istype(O, /obj/machinery/door/window))) // not dense: CanAStarPass() lets it by
						for(var/dir in cardinals)
							if(!(exits & dir) && !O.CanAStarPass(id, dir) && !bot_can_break_through(O, caller))
								exits |= dir
				if(kind & 1) // nobody sat on it either: the strict search's answer would be different then (below)
					for(var/mob/M in T)
						if(M.buckled)
							kind = PATH_PICTURE_VOLATILE
							break
			else
				for(var/atom/movable/AM as anything in T)
					if(!AM.density)
						if(isobj(AM))
							var/obj/door = AM
							if(door.astar_always_asks)
								kind = (kind & 1) ? PATH_PICTURE_VOLATILE : kind
								if(bits != 15)
									if(!one_side[door.type])
										if(!door.CanAStarPass(id, NORTH, caller))
											bits |= 15
									else
										for(var/dir in cardinals)
											if(!(bits & dir) && !door.CanAStarPass(id, dir, caller))
												bits |= dir
							else if((kind & 1) && !inert[door.type])
								kind = PATH_PICTURE_VOLATILE
						else if((kind & 1) && ismob(AM))
							var/mob/lying = AM
							if(lying.buckled)
								kind = PATH_PICTURE_VOLATILE
						continue
					if(isobj(AM))
						var/obj/O = AM
						kind = (kind & 1) ? PATH_PICTURE_VOLATILE : kind
						if(bits != 15)
							if(!one_side[O.type])
								if(!O.CanAStarPass(id, NORTH, caller))
									bits |= 15
							else
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
							kind = (kind & 1) ? PATH_PICTURE_VOLATILE : kind
			bits |= exits << 4
			if(weighted && (bits & 15) != 15)
				bits += (penalties ? penalty : bot_turf_penalty(T)) * 256
			answers[i] = bits + kind * PATH_PICTURE_UNIT
		if(timing)
			timing["tiles us"] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - mark) * 1000
			timing["rounds"]++
			timing["tiles"] += length(out)
		if(yields)
			CHECK_TICK
	return status

/// Whether bot_flood_reachable() and bot_sealed_pocket() go to the engine for this adjacency (path-flood=dm leaves them in DM)
/proc/path_engine_takes_flood(adjacent)
	if(world.params["path-flood"] == "dm")
		return FALSE
	return path_engine_takes(/turf/proc/Distance_cardinal, adjacent, null)

/// The mode bits a flood starts with
/proc/path_engine_flood_mode(simulated_only, backward, return_tiles)
	. = 0
	if(simulated_only)
		. += PATH_MODE_SIMULATED_ONLY
	switch(GLOB.path_picture_mode)
		if("off")
			. += PATH_MODE_PICTURE_OFF
		if("check")
			. += PATH_MODE_PICTURE_CHECK
	if(return_tiles)
		. += PATH_MODE_RETURN_TILES
	if(backward)
		. += PATH_MODE_BACKWARD

/// bot_flood_reachable() in the engine: every tile reachable from `start` within `max_steps` steps, as a /datum/path_region (or as
/// keys of a list with `return_tiles`). PATH_ENGINE_FALLBACK if the engine couldn't.
/proc/path_engine_flood(caller, turf/start, adjacent, id, simulated_only, max_steps, yields, return_tiles = FALSE)
	if(GLOB.station_picture_kept)
		station_picture_flush()
	var/flood = call_ext(GLOB.path_engine_lib, "byond:path_flood_begin")(start, path_engine_flood_mode(simulated_only, FALSE, return_tiles), max_steps, 0, null)
	if(!isnum(flood) || flood <= 0)
		return PATH_ENGINE_FALLBACK
	var/list/out = list()
	var/status = path_engine_rounds(flood, "byond:path_flood_step", caller, start, id, simulated_only, adjacent == /turf/proc/bot_reachable_permissive, FALSE, yields, out)
	if(status != 2)
		call_ext(GLOB.path_engine_lib, "byond:path_forget")(flood)
		return PATH_ENGINE_FALLBACK
	if(!return_tiles)
		return new /datum/path_region(out[4], out[1])
	var/list/reached = list()
	for(var/i in 5 to length(out))
		reached[out[i]] = TRUE
	return reached

/// bot_sealed_pocket() in the engine: every tile that can reach `dest`, as keys, if there are at most `max_tiles` of them, `start`
/// isn't one and none is in a hallway; else null. PATH_ENGINE_FALLBACK if the engine couldn't. Done in one go, as DM's is.
/proc/path_engine_pocket(caller, turf/start, turf/dest, adjacent, id, simulated_only, max_tiles)
	if(GLOB.station_picture_kept)
		station_picture_flush()
	var/static/list/hubs = typecacheof(list(/area/hallway)) // as bot_sealed_pocket()'s
	// the hallway tiles, so the flood stops at the first one as DM's does: told again now and then, should an area change
	var/static/hubs_told_at
	if(isnull(hubs_told_at) || world.time > hubs_told_at + 5 MINUTES)
		hubs_told_at = world.time
		var/list/hub_turfs = list()
		for(var/area/A as anything in GLOB.sortedAreas)
			if(hubs[A.type])
				for(var/turf/T in A)
					hub_turfs += T
		call_ext(GLOB.path_engine_lib, "byond:path_hubs")(hub_turfs)
	var/flood = call_ext(GLOB.path_engine_lib, "byond:path_flood_begin")(dest, path_engine_flood_mode(simulated_only, TRUE, TRUE) + PATH_MODE_STOP_AT_HUB, 0, max_tiles, start)
	if(!isnum(flood) || flood <= 0)
		return PATH_ENGINE_FALLBACK
	var/list/out = list()
	var/status = path_engine_rounds(flood, "byond:path_flood_step", caller, null, id, simulated_only, adjacent == /turf/proc/bot_reachable_permissive, FALSE, FALSE, out)
	if(status != 2)
		call_ext(GLOB.path_engine_lib, "byond:path_forget")(flood)
		return PATH_ENGINE_FALLBACK
	if(out[2] || out[3]) // reached the bot, or too big to be shut in anywhere small
		return null
	var/list/pocket = list()
	for(var/i in 5 to length(out))
		var/turf/T = out[i]
		if(T != dest && hubs[T.loc.type])
			return null
		pocket[T] = TRUE
	return pocket

/// The tiles a search that found no route opened, kept in the path engine. The bots' region checks (bot_pathing_permissive.dm) ask
/// it about a tile or two, which is all they ever did with the list of them AStar() made.
/datum/path_region
	var/id
	/// how many tiles
	var/count

/datum/path_region/New(id, count)
	src.id = id
	src.count = count

/// 1 if the search opened T, 0 if it didn't, -1 if the engine has let the region go
/datum/path_region/proc/has(turf/T)
	var/answer = call_ext(GLOB.path_engine_lib, "byond:path_region_has")(id, T)
	return answer == 1 ? 1 : (answer == 0 ? 0 : -1)

/// Whether a search's opened tiles (a list from AStar() or a flood, or a /datum/path_region from the path engine) hold T: 1 if they
/// do, 0 if they don't, -1 if that isn't known any more
/proc/path_region_has(region, turf/T)
	if(islist(region))
		var/list/tiles = region
		return tiles[T] ? 1 : 0
	if(istype(region, /datum/path_region))
		var/datum/path_region/kept = region
		return kept.has(T)
	return -1

/// path-engine=shadow: the engine's search, then AStar()'s in the same tick, and every difference noted. AStar()'s answer is the one used.
/proc/path_engine_shadow(caller, turf/start, turf/end, dist, maxnodedepth, mintargetdist, adjacent, id, turf/exclude, simulated_only, list/explored)
	var/list/check = GLOB.path_engine_check
	var/started = TICK_USAGE_REAL
	var/list/native = path_engine_search(caller, start, end, dist, maxnodedepth, mintargetdist, adjacent, id, exclude, simulated_only, FALSE, TRUE)
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
	if(check["floods checked"] || check["pockets checked"])
		lines += "Floods against DM's (path-flood=shadow): [check["floods checked"]] checked, the same [check["floods same"]], different [check["floods different"]]; pockets [check["pockets checked"]] checked, the same [check["pockets same"]], different [check["pockets different"]]"
		lines += "  time, the same tick: floods the engine [round(check["flood native us"] / max(1, check["floods checked"]))] us, DM [round(check["flood dm us"] / max(1, check["floods checked"]))] us; pockets the engine [round(check["pocket native us"] / max(1, check["pockets checked"]), 0.1)] us, DM [round(check["pocket dm us"] / max(1, check["pockets checked"]), 0.1)] us"
	lines += path_engine_stats_lines()
	lines += GLOB.path_engine_samples
	var/written = jointext(lines, "\n")
	fdel("data/path_engine_check.txt")
	text2file(written, "data/path_engine_check.txt")
	if(GLOB.log_directory) // and the run's own, as servers running at once share data/
		fdel("[GLOB.log_directory]/path_engine_check.txt")
		text2file(written, "[GLOB.log_directory]/path_engine_check.txt")

/// The engine's own counts, and in the picture check what it found
/proc/path_engine_stats_lines()
	. = list()
	var/list/stats = list()
	call_ext(GLOB.path_engine_lib, "byond:path_stats")(stats)
	if(length(stats) >= 18)
		. += "Engine: [stats[1]] begun, [stats[2]] found, [stats[3]] no route, [stats[4]] handed back, [stats[5]] rounds, [stats[6]] tiles asked about, [stats[7]] opened, [stats[8]] open now"
		. += "Station picture ([GLOB.path_picture_mode]): [stats[9]] tiles answered from it, [stats[10]] told it had changed; it knows [stats[11]] open, [stats[12]] solid, [stats[13]] open space, [stats[14]] asked about every time; [stats[15]] regions kept, [stats[16]] tiles in them"
		if(GLOB.path_picture_mode == "check")
			. += "Picture check: [stats[17]] answers it would have given, [stats[18]] of them not what DM said"
			var/list/samples = list()
			call_ext(GLOB.path_engine_lib, "byond:path_check_samples")(samples)
			for(var/i in 1 to length(samples) step 4)
				var/turf/T = samples[i]
				if(length(GLOB.path_picture_samples) >= 40)
					break
				var/list/on_it = list()
				for(var/atom/movable/AM as anything in T)
					if(isobj(AM) || ismob(AM))
						on_it += "[AM.type][AM.density ? " (dense)" : ""][ismob(AM) && AM:buckled ? " (buckled)" : ""]"
				GLOB.path_picture_samples += "  [T.x],[T.y],[T.z] [T.type]: kept as [samples[i + 3]] answering [samples[i + 1]], DM said [samples[i + 2]]; on it: [jointext(on_it, ", ") || "nothing"]"
			. += GLOB.path_picture_samples

#undef PATH_ENGINE_VERSION
#undef PATH_ENGINE_PENALTY_AIRLOCK
#undef PATH_ENGINE_PENALTY_FIREDOOR
#undef PATH_PICTURE_UNIT
#undef PATH_PICTURE_OPEN
#undef PATH_PICTURE_SOLID
#undef PATH_PICTURE_OPEN_SPACE
#undef PATH_PICTURE_VOLATILE
#undef PATH_MODE_SIMULATED_ONLY
#undef PATH_MODE_PICTURE_OFF
#undef PATH_MODE_PICTURE_CHECK
#undef PATH_MODE_RETURN_TILES
#undef PATH_MODE_BACKWARD
#undef PATH_MODE_STOP_AT_HUB
