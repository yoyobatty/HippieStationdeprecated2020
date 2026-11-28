// What a blast's set-up costs, and whether the per-turf block cache (hippiestation/code/controllers/subsystem/explosions_block.dm)
// keeps right, headless on the real station (run_block_bench.sh). Not part of the game. Builds with or without the cache, so two
// builds can be set side by side:
//  - bench: CaculateExplosionBlock() at 100 random station spots in three sizes (medium, maxcap, range 50), with the air on the way
//    (realism, as the game has it) and without, the whole set-up (the turfs, the blocks, the shape), and one item step (forceMove(),
//    Move()). Each the best of three passes, in ms a blast (or us a step).
//  - severity: what each of those blasts does to each tile (explosion_severity_map(), as explode() works it out): one line a blast,
//    for a diff between two builds (severity.txt).
//  - with the cache (EXPLOSION_BLOCK_CACHE): the cache against the old loop at every spot, the hook's own cost, then (round) a round
//    of doors cycling, windows built and broken, walls taken down and put up, blockers moved and var-edited, a shuttle flown and real
//    blasts, with the full map recount (explosion_block_cache_check()) after each part, and once with a window moved behind the
//    cache's back, to see the recount catch it.
// World param explosion-block-bench=bench or round (round does the bench first).

/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	if("explosion-block-bench" in world.params)
		sleep_offline_after_initializations = FALSE // nobody connects to this, so the world has to keep ticking
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(block_bench_run))
	return ..()

#define BLOCK_BENCH_DIR "data/explosion_block_bench/"

/proc/bb_log(text)
	text2file(text, BLOCK_BENCH_DIR + "results.txt")
	log_world("BLOCK BENCH: [text]")

/proc/bb_sev(text)
	text2file(text, BLOCK_BENCH_DIR + "severity.txt")

/proc/block_bench_run()
	UNTIL(Master.current_runlevel)
	sleep(5 SECONDS)
	try
		block_bench_body()
	catch(var/exception/E)
		bb_log("FAILED: [E] at [E.file]:[E.line]")
	bb_log("done")
	sleep(1 SECONDS)
	Master.Shutdown()
	qdel(world)

/proc/block_bench_body()
	var/cache = FALSE
#ifdef EXPLOSION_BLOCK_CACHE
	cache = TRUE
#endif
	bb_log("Map: [SSmapping.config.map_name], block cache [cache ? "on" : "not in this build"], realism [GLOB.explosion_realism ? "on" : "off"], shape [GLOB.explosion_shape_mode]")
	rand_seed(1128)
	var/list/station = list()
	for(var/z in SSmapping.levels_by_trait(ZTRAIT_STATION))
		for(var/turf/open/floor/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
			if(istype(T.loc, /area/space) || istype(T.loc, /area/shuttle))
				continue
			station += T
	var/list/spots = list()
	for(var/i in 1 to 100)
		spots += pick(station)
	bb_log("[length(station)] station floor tiles, [length(spots)] spots")

	// dev, heavy, light, as explosion() is given them
	var/list/sizes = list("medium" = list(2, 4, 8), "maxcap" = list(5, 10, 20), "range50" = list(12, 25, 50))
	bb_time_sizes(spots, sizes, 3, "on the fresh station")
	bb_breakdown(spots, 20, "on the fresh station")

	// one step of an item, which is what the cache's hook in Moved() adds to
	var/turf/open/floor/here
	var/turf/open/floor/there
	for(var/turf/open/floor/T as anything in spots)
		var/turf/open/floor/E = get_step(T, EAST)
		if(istype(E) && !T.density && !E.density && !(locate(/obj/structure) in T) && !(locate(/obj/structure) in E) && !(locate(/obj/machinery) in T) && !(locate(/obj/machinery) in E))
			here = T
			there = E
			break
	if(here)
		var/obj/item/crowbar/C = new(here)
		var/best_force = INFINITY
		var/best_move = INFINITY
		for(var/pass in 1 to 5)
			var/force_ms = 0
			var/move_ms = 0
			for(var/chunk in 1 to 20)
				var/start = TICK_USAGE_REAL
				for(var/i in 1 to 500)
					C.forceMove(there)
					C.forceMove(here)
				force_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
				CHECK_TICK
				start = TICK_USAGE_REAL
				for(var/i in 1 to 500)
					C.Move(there, EAST)
					C.Move(here, WEST)
				move_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
				CHECK_TICK
			best_force = min(best_force, force_ms)
			best_move = min(best_move, move_ms)
		// 20 chunks of 1000 steps a pass: ms / 20000 steps * 1000 = us a step
		bb_log("an item's step at [here.x],[here.y],[here.z]: forceMove() [round(best_force / 20, 0.0001)] us, Move() [round(best_move / 20, 0.0001)] us (best of 5 passes of 20,000)")
#ifdef EXPLOSION_BLOCK_CACHE
		// the hook alone: what Moved() reads for something that blocks nothing
		bb_hook_cost(C, "a crowbar")
		var/mob/living/carbon/human/H = new(there)
		bb_hook_cost(H, "a new human")
		qdel(H)
#endif
		qdel(C)

	// what each blast does to each tile, and with the cache, the same blasts by the old path (tg's loop) in the same world
	for(var/size_name in sizes)
		var/list/s = sizes[size_name]
		var/list/sum = list(0, 0, 0, 0)
		var/differ_tiles = 0
		var/differ_blasts = 0
		for(var/turf/T as anything in spots)
			var/list/severity = explosion_severity_map(T, s[1], s[2], s[3])
			var/list/counts = list(0, 0, 0, 0)
			var/digest = 0
			for(var/turf/A as anything in severity)
				var/sev = severity[A]
				counts[sev]++
				digest = (digest * 31 + (A.x * 256 + A.y) * 4 + sev) % 65521
			for(var/i in 1 to 4)
				sum[i] += counts[i]
			bb_sev("[size_name] at [T.x],[T.y],[T.z]: [counts[1]] devastated, [counts[2]] heavy, [counts[3]] light, [counts[4]] glass, digest [digest]")
#ifdef EXPLOSION_BLOCK_CACHE
			GLOB.explosion_block_cache = FALSE
			var/list/before = explosion_severity_map(T, s[1], s[2], s[3])
			GLOB.explosion_block_cache = TRUE
			var/these = 0
			for(var/turf/A as anything in severity | before)
				if(severity[A] != before[A])
					these++
			differ_tiles += these
			if(these)
				differ_blasts++
#endif
			CHECK_TICK
		var/line = "[size_name] severity over [length(spots)] blasts: [sum[1]] devastated, [sum[2]] heavy, [sum[3]] light, [sum[4]] glass"
#ifdef EXPLOSION_BLOCK_CACHE
		line += "; by the old path: [differ_tiles] tiles hit differently, in [differ_blasts] blasts"
#endif
		bb_log(line)

#ifdef EXPLOSION_BLOCK_CACHE
	var/recount_start = REALTIMEOFDAY
	var/startup_wrong = explosion_block_cache_check(BLOCK_BENCH_DIR + "mismatches.txt")
	bb_log("full map recount after startup: [startup_wrong] mismatches, over [world.maxz] z-levels of [world.maxx]x[world.maxy] in [round((REALTIMEOFDAY - recount_start) / 10, 0.1)] s")
	if(world.params["explosion-block-bench"] == "round")
		block_bench_round(spots, sizes)
#endif

/// Times CaculateExplosionBlock() (without the air and with it) and the whole set-up (the turfs, the blocks with the air, the shape) at
/// each spot for each size, the best of `passes`. With the cache in the build, the old path too (explosion_block_cache off: tg's loop,
/// lists), and the two paths' blocks compared tile by tile.
/proc/bb_time_sizes(list/spots, list/sizes, passes, when)
	var/cache = FALSE
#ifdef EXPLOSION_BLOCK_CACHE
	cache = TRUE
#endif
	var/n = length(spots)
	for(var/size_name in sizes)
		var/list/s = sizes[size_name]
		var/range = s[3]
		var/list/affected_of = list()
		var/tiles = 0
		for(var/turf/T as anything in spots)
			var/list/affected = SSexplosions.GatherSpiralTurfs(range, T)
			affected_of[T] = affected
			tiles += length(affected)
		var/list/results = list()
		var/differ = 0
		var/differ_spots = 0
		var/was_realism = GLOB.explosion_realism
		for(var/path in (cache ? list("old", "new") : list("this build")))
#ifdef EXPLOSION_BLOCK_CACHE
			GLOB.explosion_block_cache = path != "old"
#endif
			var/best_plain = INFINITY
			var/best_air = INFINITY
			var/best_setup = INFINITY
			for(var/pass in 1 to passes)
				var/plain_ms = 0
				var/air_ms = 0
				var/setup_ms = 0
				for(var/turf/T as anything in spots)
					var/list/affected = affected_of[T]
					GLOB.explosion_realism = FALSE
					var/start = TICK_USAGE_REAL
					SSexplosions.CaculateExplosionBlock(affected)
					plain_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
					GLOB.explosion_realism = was_realism
					CHECK_TICK
					start = TICK_USAGE_REAL
					SSexplosions.CaculateExplosionBlock(affected)
					air_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
					CHECK_TICK
					start = TICK_USAGE_REAL
					var/list/again = SSexplosions.GatherSpiralTurfs(range, T)
					var/list/with_air = SSexplosions.CaculateExplosionBlock(again)
					explosion_shape(T, range, with_air)
					setup_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
					CHECK_TICK
				best_plain = min(best_plain, plain_ms)
				best_air = min(best_air, air_ms)
				best_setup = min(best_setup, setup_ms)
			results += "[path]: blocks [round(best_plain / n, 0.001)] ms, with the air [round(best_air / n, 0.001)] ms, whole set-up [round(best_setup / n, 0.001)] ms"
#ifdef EXPLOSION_BLOCK_CACHE
		// the two paths' blocks, with the air, tile by tile
		for(var/turf/T as anything in spots)
			var/list/affected = affected_of[T]
			GLOB.explosion_block_cache = FALSE
			var/list/old = SSexplosions.CaculateExplosionBlock(affected)
			GLOB.explosion_block_cache = TRUE
			var/list/blocks = SSexplosions.CaculateExplosionBlock(affected)
			var/these = length(old) != length(blocks) ? 1 : 0
			for(var/turf/A as anything in old)
				if(old[A] != blocks[A])
					these++
					if(differ < 5)
						bb_log("  DIFFER at [A.x],[A.y],[A.z] [A.type]: old [old[A]], cache [blocks[A]]")
			differ += these
			if(these)
				differ_spots++
			CHECK_TICK
		GLOB.explosion_block_cache = TRUE
#endif
		GLOB.explosion_realism = was_realism
		bb_log("[size_name] (light [range]) [when], [round(tiles / n)] tiles a blast, a blast at [n] spots: [jointext(results, "; ")][cache ? "; [differ] tiles differ between the two at [differ_spots] spots" : ""]")

/// What one turf's lookup costs, piece by piece, in ns a turf over every turf of a blast this size at each spot: the loop alone, the
/// builtin vars (x and y, density), a turf var left at its type's value (explosion_block), one of the cache's vars, and adding the
/// answer to a list or an alist keyed by the turf.
/proc/bb_breakdown(list/spots, range, when)
	var/list/names = list("loop", "x and y", "density", "explosion_block", "a cache var", "list build", "alist build")
	var/list/ms = list(0, 0, 0, 0, 0, 0, 0)
	var/tiles = 0
	for(var/turf/spot as anything in spots)
		var/list/affected = SSexplosions.GatherSpiralTurfs(range, spot)
		tiles += length(affected)
		var/sum = 0
		var/start = TICK_USAGE_REAL
		for(var/turf/T as anything in affected)
			sum++
		ms[1] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
		start = TICK_USAGE_REAL
		for(var/turf/T as anything in affected)
			sum += T.x + T.y
		ms[2] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
		start = TICK_USAGE_REAL
		for(var/turf/T as anything in affected)
			sum += T.density
		ms[3] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
		start = TICK_USAGE_REAL
		for(var/turf/T as anything in affected)
			sum += T.explosion_block
		ms[4] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
#ifdef EXPLOSION_BLOCK_CACHE
		start = TICK_USAGE_REAL
		for(var/turf/T as anything in affected)
			sum += T.explosion_block_static
		ms[5] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
#endif
		start = TICK_USAGE_REAL
		var/list/L = list()
		for(var/turf/T as anything in affected)
			L[T] = 1
		ms[6] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
		start = TICK_USAGE_REAL
		var/alist/A = alist()
		for(var/turf/T as anything in affected)
			A[T] = 1
		ms[7] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
		CHECK_TICK
	var/list/parts = list()
	for(var/i in 1 to length(names))
		var/each = ms[i] / tiles * 1000000
		if(i > 1 && i < 6)
			each -= ms[1] / tiles * 1000000 //over the loop's own
		parts += "[names[i]] [round(each)]"
	bb_log("one turf's lookup [when] (light [range], [round(tiles / length(spots))] tiles a blast), ns a turf: [jointext(parts, ", ")]")

#ifdef EXPLOSION_BLOCK_CACHE
/// What the Moved() hook's check costs on this thing, in ns a step (a million checks, the best of five passes, less the loop's own)
/proc/bb_hook_cost(atom/movable/AM, what)
	var/best_hook = INFINITY
	var/best_empty = INFINITY
	for(var/pass in 1 to 5)
		var/hook_ms = 0
		var/empty_ms = 0
		var/hits = 0
		for(var/chunk in 1 to 20)
			var/start = TICK_USAGE_REAL
			for(var/i in 1 to 50000)
				if(AM.explosion_block)
					hits++
			hook_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
			CHECK_TICK
			start = TICK_USAGE_REAL
			for(var/i in 1 to 50000)
				if(hits < 0)
					hits++
			empty_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
			CHECK_TICK
		best_hook = min(best_hook, hook_ms)
		best_empty = min(best_empty, empty_ms)
	// 1,000,000 checks a pass: ms / 1e6 * 1e6 = ns a check
	bb_log("the Moved() hook's check on [what] ([AM.type]): [round(best_hook - best_empty, 0.1)] ns a step ([round(best_hook, 0.1)] with the loop, [round(best_empty, 0.1)] the loop alone)")

#endif

#ifdef EXPLOSION_BLOCK_CACHE
/proc/bb_recount(what)
	var/found = explosion_block_cache_check(BLOCK_BENCH_DIR + "mismatches.txt")
	bb_log("  recount after [what]: [found] mismatches")
	return found

/proc/bb_station_turfs(kind)
	. = list()
	for(var/z in SSmapping.levels_by_trait(ZTRAIT_STATION))
		for(var/turf/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
			if(istype(T, kind) && !istype(T.loc, /area/space) && !istype(T.loc, /area/shuttle))
				. += T

/proc/bb_wait_explosions()
	sleep(2 SECONDS)
	UNTIL(!SSexplosions.is_exploding())
	sleep(2 SECONDS)

/proc/block_bench_round(list/spots, list/sizes)
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/deadline = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < deadline)
		sleep(1 SECONDS)
	sleep(10 SECONDS)
	bb_log("round: [SSticker.current_state >= GAME_STATE_PLAYING ? "started" : "DID NOT START"]")
	var/total = bb_recount("roundstart")
	rand_seed(2811)

	// doors, three times round: every station airlock, firelock and blast door shut and opened
	var/list/doors = list()
	for(var/obj/machinery/door/D in GLOB.airlocks)
		if(D.z in SSmapping.levels_by_trait(ZTRAIT_STATION))
			doors += D
	for(var/cycle in 1 to 3)
		for(var/obj/machinery/door/D as anything in doors)
			if(QDELETED(D))
				continue
			if(D.density)
				INVOKE_ASYNC(D, TYPE_PROC_REF(/obj/machinery/door, open))
			else
				INVOKE_ASYNC(D, TYPE_PROC_REF(/obj/machinery/door, close))
		sleep(3 SECONDS)
	var/shut = 0
	for(var/obj/machinery/door/D as anything in doors)
		if(!QDELETED(D) && D.density)
			shut++
	total += bb_recount("[length(doors)] doors cycled three times ([shut] shut now)")

	// windows built: full-tile reinforced, directional, plasma, on open floor
	var/list/floors = bb_station_turfs(/turf/open/floor)
	var/built = 0
	for(var/i in 1 to 60)
		var/turf/open/floor/F = pick(floors)
		if(F.density || (locate(/obj/structure/window) in F) || (locate(/obj/machinery/door) in F))
			continue
		switch(i % 4)
			if(0)
				new /obj/structure/window/reinforced/fulltile(F)
			if(1)
				new /obj/structure/window/reinforced(F, pick(GLOB.cardinals))
			if(2)
				new /obj/structure/window/plasma/reinforced/fulltile(F)
			if(3)
				new /obj/structure/window/fulltile(F)
		built++
	total += bb_recount("[built] windows built")

	// windows broken, taken apart, unanchored, deleted
	var/list/windows = list()
	for(var/obj/structure/window/W in world)
		if(isturf(W.loc) && (W.z in SSmapping.levels_by_trait(ZTRAIT_STATION)))
			windows += W
	var/broken = 0
	for(var/i in 1 to 80)
		if(!length(windows))
			break
		var/obj/structure/window/W = pick_n_take(windows)
		switch(i % 4)
			if(0)
				W.take_damage(W.max_integrity * 2, BRUTE, "melee", FALSE)
			if(1)
				W.deconstruct(TRUE)
			if(2)
				W.setAnchored(FALSE)
			if(3)
				qdel(W)
		broken++
	total += bb_recount("[broken] windows broken, taken apart, unanchored or deleted")

	// walls taken down and put up
	var/list/walls = bb_station_turfs(/turf/closed/wall)
	var/down = 0
	for(var/i in 1 to 40)
		if(!length(walls))
			break
		var/turf/closed/wall/W = pick_n_take(walls)
		if(i % 2)
			W.dismantle_wall(TRUE, FALSE)
		else
			W.ScrapeAway()
		down++
	var/up = 0
	for(var/i in 1 to 20)
		var/turf/open/floor/F = pick(floors)
		if(!istype(F) || F.density)
			continue
		F.PlaceOnTop(null, i % 2 ? /turf/closed/wall : /turf/closed/wall/r_wall)
		up++
	total += bb_recount("[down] walls taken down, [up] put up")

	// blockers moved: a window stepped, forceMoved, into a locker and out, a door moved, a table var-edited to block and moved
	windows = list()
	for(var/obj/structure/window/W in world)
		if(isturf(W.loc) && (W.z in SSmapping.levels_by_trait(ZTRAIT_STATION)))
			windows += W
	var/moved = 0
	for(var/i in 1 to 10)
		if(!length(windows))
			break
		var/obj/structure/window/W = pick_n_take(windows)
		var/turf/open/floor/F = pick(floors)
		if(!istype(F))
			continue
		switch(i % 3)
			if(0)
				W.forceMove(F)
			if(1)
				var/obj/structure/closet/L = new(F)
				W.forceMove(L)
				L.open()
				qdel(L)
			if(2)
				W.setAnchored(FALSE)
				W.Move(get_step(W, pick(GLOB.cardinals)))
		moved++
	var/obj/machinery/door/D = pick(doors)
	if(!QDELETED(D))
		D.forceMove(get_step(D, NORTH))
		moved++
	var/obj/structure/table/T = locate() in world
	if(T)
		T.vv_edit_var("explosion_block", 4)
		T.forceMove(pick(floors))
		moved++
	var/obj/structure/window/edited = pick(windows)
	if(edited)
		edited.vv_edit_var("explosion_block", 7) // off the slow path onto the total
		edited.forceMove(pick(floors))
		edited.vv_edit_var("explosion_block", EXPLOSION_BLOCK_PROC) // and back
	total += bb_recount("[moved] blockers moved, a table and a window var-edited")
	if(T)
		T.vv_edit_var("explosion_block", 0)
	total += bb_recount("the table edited back to nothing")

	// blob shields made and killed
	var/list/shields = list()
	for(var/i in 1 to 6)
		var/turf/open/floor/F = pick(floors)
		if(istype(F) && !F.density)
			shields += new /obj/structure/blob/shield(F)
	total += bb_recount("[length(shields)] blob shields made")
	for(var/obj/structure/blob/B as anything in shields)
		qdel(B)
	total += bb_recount("the blob shields killed")

	// a shuttle flown there and back, its airlocks and windows with it
	var/obj/docking_port/mobile/M = SSshuttle.getShuttle("mining")
	if(M)
		var/home = M.getDockedId()
		var/away = home == "mining_home" ? "mining_away" : "mining_home"
		SSshuttle.moveShuttle("mining", away, FALSE)
		total += bb_recount("the mining shuttle flown to [away]")
		SSshuttle.moveShuttle("mining", home, FALSE)
		total += bb_recount("the mining shuttle flown back")
	else
		bb_log("  no mining shuttle")

	// real blasts, with every blast's blocks checked against the old loop as it goes off
	GLOB.explosion_block_check = TRUE
	var/list/blasts = list(list(2, 4, 8), list(5, 10, 20), list(1, 2, 4), list(3, 6, 12))
	for(var/list/s as anything in blasts)
		var/turf/open/floor/F = pick(floors)
		explosion(F, s[1], s[2], s[3], 0, FALSE, TRUE)
		bb_wait_explosions()
	bb_log("  [length(blasts)] blasts: [GLOB.explosion_block_checked] block lists checked against the old loop as they went off, [GLOB.explosion_block_differed] differed")
	GLOB.explosion_block_check = !!text2num(world.params["explosion-block-check"]) // or it'd time the check too, below
	total += bb_recount("the blasts")

	// a window moved behind the cache's back (loc set, as old code does): the recount has to see it
	windows = list()
	for(var/obj/structure/window/W in world)
		if(isturf(W.loc) && (W.z in SSmapping.levels_by_trait(ZTRAIT_STATION)))
			windows += W
	var/obj/structure/window/sneaky = pick(windows)
	var/turf/was = sneaky.loc
	sneaky.loc = pick(floors)
	var/caught = bb_recount("a window moved by setting loc (expected: some)")
	bb_log("  the recount [caught ? "caught" : "MISSED"] it")
	sneaky.loc = was
	total += bb_recount("it put back")
	bb_log("round total: [total] mismatches over every recount but the deliberate one")

	// the same blasts' set-up now the station's been lived in: doors open and shut, glass and rubble about
	var/list/some = spots.Copy(1, 41)
	bb_time_sizes(some, list("maxcap" = sizes["maxcap"], "range50" = sizes["range50"]), 2, "after the round")
	bb_breakdown(some, 20, "after the round")
	var/mob/living/carbon/human/lived
	for(var/mob/living/carbon/human/someone in GLOB.mob_living_list)
		if(someone.stat != DEAD)
			lived = someone
			break
	if(lived)
		bb_hook_cost(lived, "a human of the round")
#endif

#undef BLOCK_BENCH_DIR
