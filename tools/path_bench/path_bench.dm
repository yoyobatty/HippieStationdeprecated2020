// Path engine bench: the same searches by the path engine (hippie_path.dll, bot_path_engine.dm) and by AStar(), on the real station,
// headless, without timewarp. Every pair of answers compared, and both timed, each search started at the top of a tick so neither
// yields part way.
//
// Run:      tools/path_bench/run_path_bench.sh   (SEARCHES=600, SEED=1, LIB=hippie_path; builds its own copy)
// Results:  data/path_bench/results.txt

/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	if("path-bench" in world.params)
		sleep_offline_after_initializations = FALSE //nobody connects to this, so the world has to keep ticking
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(run_path_bench))
	return ..()

/proc/run_path_bench()
	sleep(5 SECONDS)
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/round_deadline = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < round_deadline)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	var/list/lines = list()
	if(isnull(GLOB.path_engine_on))
		path_engine_setup()
	lines += "Path engine: [GLOB.path_engine_status]"
	if(GLOB.path_engine_on)
		rand_seed(text2num(world.params["seed"]) || 1)
		var/count = text2num(world.params["searches"]) || 600
		var/list/floors = list()
		for(var/turf/open/floor/F in GLOB.station_turfs)
			if(!F.density)
				floors += F
		var/mob/living/carbon/human/walker = new(pick(floors))
		var/obj/item/card/id/card = new(walker)
		card.access = get_all_accesses()
		var/list/pairs = list()
		while(length(pairs) < count * 2)
			var/turf/a = pick(floors)
			var/turf/b = pick(floors)
			if(a != b && a.z == b.z && abs(a.x - b.x) + abs(a.y - b.y) <= 250)
				pairs += a
				pairs += b
		var/list/kinds = list(
			list("strict, cardinal", /turf/proc/bot_reachable_strict, /turf/proc/Distance_cardinal),
			list("permissive, weighted", /turf/proc/bot_reachable_permissive, /turf/proc/bot_weighted_distance))
		for(var/list/kind in kinds)
			if(world.params["kind"] && !findtext(kind[1], world.params["kind"]))
				continue
			var/list/totals = list("searches" = 0, "same" = 0, "different" = 0, "yielded" = 0, "moved" = 0, "found" = 0, "native us" = 0, "dm us" = 0, "opened" = 0)
			var/list/timing = list("engine us" = 0, "tiles us" = 0, "rounds" = 0, "tiles" = 0, "blocked" = 0, "contents" = 0)
			var/list/samples = list()
			for(var/i in 1 to count)
				var/turf/start = pairs[i * 2 - 1]
				var/turf/end = pairs[i * 2]
				var/id = (i % 2) ? card : null
				sleep(world.tick_lag) // start at the top of a tick
				walker.forceMove(start) // and only then put it there: a tick stood anywhere and space wind or a conveyor can move it on
				var/time = world.time
				var/refreshed = GLOB.bot_hazards_refresh_at
				var/list/hazard_list = GLOB.bot_hazard_turfs
				var/list/this_timing = list("engine us" = 0, "tiles us" = 0, "rounds" = 0, "tiles" = 0, "blocked" = 0, "contents" = 0)
				GLOB.path_engine_timing = this_timing
				var/mark = TICK_USAGE_REAL
				var/list/native = path_engine_search(walker, start, end, kind[3], 250, 0, kind[2], id, null, TRUE, FALSE)
				var/native_us = TICK_DELTA_TO_MS(TICK_USAGE_REAL - mark) * 1000
				GLOB.path_engine_timing = null
				var/list/dm_explored = list("dm_only" = TRUE)
				var/turfs_before = GLOB.astar_tally["turfs"]
				mark = TICK_USAGE_REAL
				var/list/path = AStar(walker, end, kind[3], 0, 250, 0, kind[2], id, null, TRUE, dm_explored)
				if(get_turf(walker) != start)
					totals["searches"]++
					totals["moved"]++
					continue
				var/dm_us = TICK_DELTA_TO_MS(TICK_USAGE_REAL - mark) * 1000
				var/dm_opened = GLOB.astar_tally["turfs"] - turfs_before
				totals["searches"]++
				if(world.time != time)
					totals["yielded"]++
					continue
				totals["native us"] += native_us
				for(var/key in this_timing)
					timing[key] += this_timing[key]
				totals["dm us"] += dm_us
				totals["opened"] += dm_opened
				if(path)
					totals["found"]++
				var/why
				if(!native)
					why = "the engine failed"
				else if(!!path != !!native[1])
					why = path ? "AStar() found a path, the engine none" : "the engine found one, AStar() none"
				else if(path)
					var/list/other = native[1]
					if(length(path) != length(other))
						why = "paths [length(path)] and [length(other)] long"
					else
						for(var/step in 1 to length(path))
							if(path[step] != other[step])
								why = "the paths part at step [step]"
								break
				else
					var/list/dm_reached = dm_explored["reached"]
					var/list/reached = native[3]
					if(length(dm_reached) != length(reached) || !!dm_explored["depth_cut"] != !!native[4])
						why = "no path either way, opened [length(dm_reached)] against [length(reached)]"
				if(!why && dm_opened != native[2])
					why = "the same answer, opened [dm_opened] against [native[2]]"
				if(why)
					totals["different"]++
					if(length(samples) < 10)
						samples += "    [why]: [start.x],[start.y] to [end.x],[end.y][id ? " with all access" : ""] (search [i])"
						// the same tick still: is either side not the same twice, and where do they part?
						var/list/native2 = path_engine_search(walker, start, end, kind[3], 250, 0, kind[2], id, null, TRUE, FALSE)
						var/list/dm_explored2 = list("dm_only" = TRUE)
						var/before2 = GLOB.astar_tally["turfs"]
						var/list/path2 = AStar(walker, end, kind[3], 0, 250, 0, kind[2], id, null, TRUE, dm_explored2)
						samples += "      again: the engine opened [native2?[2]] (first [native[2]]), AStar() [GLOB.astar_tally["turfs"] - before2] (first [dm_opened]); paths [length(native2?[1])]/[length(native[1])] and [length(path2)]/[length(path)]; hazards redrawn [refreshed] -> [GLOB.bot_hazards_refresh_at], [hazard_list == GLOB.bot_hazard_turfs ? "the same list" : "a new list"], world.time [time] -> [world.time]"
						if(!path && !native[1])
							var/list/dm_reached = dm_explored["reached"]
							var/list/reached = native[3]
							var/shown = 0
							for(var/turf/X as anything in reached)
								if(dm_reached[X] || shown >= 3)
									continue
								shown++
								var/list/ways = list()
								for(var/dir in GLOB.cardinals)
									var/turf/N = get_step(X, dir)
									if(N && reached[N])
										ways += "from [dir2text(dir)] [call(N, kind[2])(walker, X, id, TRUE) ? "allowed" : "refused"] by AStar()'s check[dm_reached[N] ? "" : " (not reached by AStar() either)"]"
								var/list/things = list()
								for(var/atom/movable/AM as anything in X)
									var/obj/O = AM
									things += "[AM.type][AM.density ? " (dense)" : ""][isobj(AM) && O.astar_always_asks ? " (asks)" : ""][isobj(AM) ? " CanAStarPass S/E [O.CanAStarPass(id, SOUTH, walker)]/[O.CanAStarPass(id, EAST, walker)]" : ""]"
								var/turf/below = get_step(X, SOUTH)
								things += "checks: hazard [GLOB.bot_hazard_turfs[X]], into it from the south [bot_steps_into_hazard(below, X, walker)], deadly [bot_turf_is_deadly(X)], field [bot_turf_has_active_field(X)], link blocked from the south [below.bot_link_blocked_strict(X, walker, id)], pool [istype(X, /turf/open/pool)]"
								samples += "      the engine only: [X.x],[X.y] [X.type], [jointext(ways, "; ")]; on it: [jointext(things, ", ")]"
							for(var/turf/X as anything in dm_reached)
								if(!reached[X] && shown < 6)
									shown++
									samples += "      AStar() only: [X.x],[X.y] [X.type]"
				else
					totals["same"]++
			var/n = max(1, totals["searches"] - totals["yielded"] - totals["moved"])
			lines += "[kind[1]]: [totals["searches"]] searches ([totals["found"]] found a path), the same [totals["same"]], different [totals["different"]], yielded part way [totals["yielded"]], the walker moved [totals["moved"]]"
			lines += "    engine [round(totals["native us"] / n, 0.1)] us a search, AStar() [round(totals["dm us"] / n, 0.1)] us: [round(totals["dm us"] / max(1, totals["native us"]), 0.01)]x; [round(totals["opened"] / n)] tiles opened a search"
			lines += "    of the engine's: in the library [round(timing["engine us"] / n, 0.1)] us, telling it about tiles [round(timing["tiles us"] / n, 0.1)] us, [round(timing["rounds"] / n, 0.1)] rounds and [round(timing["tiles"] / n, 0.1)] tiles a search ([round(timing["tiles us"] / max(1, timing["tiles"]), 0.01)] us a tile)"
			lines += "    tiles asked: [round(timing["blocked"] / max(1, timing["tiles"]) * 100)]% blocked outright, the rest [round(timing["contents"] / max(1, timing["tiles"] - timing["blocked"]), 0.1)] things on them on average"
			lines += samples
	fdel("data/path_bench/results.txt")
	text2file(jointext(lines, "\n"), "data/path_bench/results.txt")
	log_world("PATH BENCH: done")
	Master.Shutdown()
	qdel(world)
