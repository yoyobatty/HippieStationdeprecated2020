// Mob storm: the 2026-11-11 admin stress test, headless. 100 clown cats, then ash drakes, then 99 of each, all on one tile, as the
// create panel spawns them. A gibbed clown cat leaves 3 retaliating clowns, a dead clown leaves a human corpse, a drake's swoop gibs
// the dead around it, and its lava falls on the pile. That round stood still 10, 14 and 88 s.
//
// Run:      tools/mob_storm/run.sh build <name>, then run.sh run <name> [label]   (its own dmb, hippiestation.dmb is left alone)
// Results:  data/mob_storm/<label>.txt: each stall over half a second, what ran in the ones over 2 s (hippie_prof), and totals.

/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	if("mob-storm" in world.params)
		sleep_offline_after_initializations = FALSE //nobody connects to this, so the world has to keep ticking
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(run_mob_storm))
	return ..()

GLOBAL_VAR(mob_storm_file)

/proc/mob_storm_log(text)
	text2file(text, GLOB.mob_storm_file)

/proc/run_mob_storm()
	sleep(5 SECONDS)
	GLOB.mob_storm_file = "data/mob_storm/[world.params["mob-storm-label"] || "storm"].txt"
	fdel(GLOB.mob_storm_file)
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/round_deadline = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < round_deadline)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	MCWatchdog.watch_with_nobody_on = TRUE

	// the middle of the roomiest open floor in chemistry, else the central hallway, else any station hallway
	var/turf/pile
	for(var/area_type in list(/area/medical/chemistry, /area/hallway/primary/central, /area/hallway))
		var/list/floors = list()
		for(var/area/A in GLOB.sortedAreas)
			if(!istype(A, area_type) || !is_station_level(A.z))
				continue
			for(var/turf/open/floor/F in A)
				if(!is_blocked_turf(F, TRUE))
					floors += F
		if(!length(floors))
			continue
		var/best = -1
		for(var/turf/open/floor/F in floors)
			var/room = 0
			for(var/turf/open/floor/N in RANGE_TURFS(2, F))
				if(N in floors)
					room++
			if(room > best)
				best = room
				pile = F
		break
	mob_storm_log("pile at [pile.x],[pile.y],[pile.z] ([get_area(pile)]), profiler [SSprofiler.engine]")

	var/seconds = text2num(world.params["mob-storm-seconds"]) || 180
	var/start_real = REALTIMEOFDAY
	var/start_game = world.time
	var/datum/mob_storm_watch/W = new
	W.watch()
	for(var/i in 1 to 100)
		new /mob/living/simple_animal/pet/cat/clown(pile)
	sleep(5 SECONDS)
	for(var/i in 1 to 5)
		new /mob/living/simple_animal/hostile/megafauna/dragon(pile)
	sleep(5 SECONDS)
	for(var/i in 1 to 9)
		new /mob/living/simple_animal/hostile/megafauna/dragon(pile)
		sleep(2)
	sleep(5 SECONDS)
	for(var/i in 1 to 99)
		new /mob/living/simple_animal/hostile/megafauna/dragon(pile)
		new /mob/living/simple_animal/pet/cat/clown(pile)
	mob_storm_log("spawned at [round((REALTIMEOFDAY - start_real) / 10, 0.1)] s")

	while(REALTIMEOFDAY - start_real < seconds * 10)
		sleep(1 SECONDS)
		if(world.time - W.last_census >= 15 SECONDS)
			W.last_census = world.time
			mob_storm_log(W.census(pile, REALTIMEOFDAY - start_real))
	W.watching = FALSE
	var/list/selfs = SSprofiler.recent(30000) // where the last 30 s went, stalls or not
	var/list/bits = list()
	for(var/name in selfs)
		bits += "[name] [round(selfs[name], 0.01)] s"
		if(length(bits) >= 15)
			break
	mob_storm_log("last 30 s, self time: [jointext(bits, ", ")]")
	for(var/list/row in SSprofiler.recent_stacks(15000))
		var/list/stack = row["stack"]
		mob_storm_log("   last 15 s, [round(row["ms"] / 1000, 0.1)] s: [jointext(stack.Copy(max(1, length(stack) - 7)), " > ")]")
	var/real = (REALTIMEOFDAY - start_real) / 10
	var/game = (world.time - start_game) / 10
	mob_storm_log(W.census(pile, REALTIMEOFDAY - start_real))
	mob_storm_log("TOTAL real [round(real, 0.1)] s, game [round(game, 0.1)] s ([round(100 * game / real)]%), worst stall [round(W.worst / 10, 0.1)] s, \
		stalls over 0.5 s: [W.stalls] adding to [round(W.stalled / 10, 0.1)] s, over 2 s: [W.big_stalls]")
	mob_storm_log("done")
	sleep(1 SECONDS)
	Master.Shutdown()
	qdel(world)

/datum/mob_storm_watch
	var/watching = TRUE
	var/worst = 0
	var/stalls = 0
	var/big_stalls = 0
	var/stalled = 0
	var/last_census = 0

/datum/mob_storm_watch/proc/watch()
	set waitfor = FALSE
	var/last = REALTIMEOFDAY
	while(watching)
		sleep(world.tick_lag)
		var/now = REALTIMEOFDAY
		var/gap = now - last
		last = now
		if(gap < 5)
			continue
		stalls++
		stalled += gap
		worst = max(worst, gap)
		var/line = "stall [round(gap / 10, 0.1)] s at game [round(world.time / 10)] s"
		if(gap >= 20)
			big_stalls++
			var/list/selfs = SSprofiler.recent(gap * 100) // seconds of self time, heaviest first
			var/list/bits = list()
			for(var/name in selfs)
				bits += "[name] [round(selfs[name], 0.01)] s"
				if(length(bits) >= 10)
					break
			line += "\n   self: [jointext(bits, ", ")]"
			for(var/list/row in SSprofiler.recent_stacks(gap * 100))
				var/list/stack = row["stack"]
				var/list/tail = stack.Copy(max(1, length(stack) - 7))
				line += "\n   [round(row["ms"] / 1000, 0.1)] s: [jointext(tail, " > ")]"
		mob_storm_log(line)

/datum/mob_storm_watch/proc/census(turf/pile, real_ds)
	var/drakes = 0
	var/cats = 0
	var/clowns = 0
	var/humans = 0
	var/other = 0
	for(var/mob/living/L in GLOB.mob_living_list)
		if(istype(L, /mob/living/simple_animal/hostile/megafauna/dragon))
			drakes++
		else if(istype(L, /mob/living/simple_animal/pet/cat/clown))
			cats++
		else if(istype(L, /mob/living/simple_animal/hostile/retaliate/clown))
			clowns++
		else if(ishuman(L))
			humans++
		else
			other++
	var/lava = 0
	for(var/turf/open/lava/T in RANGE_TURFS(20, pile))
		lava++
	var/biggest = 0
	for(var/turf/T in RANGE_TURFS(20, pile))
		biggest = max(biggest, length(T.contents))
	return "census at [round(real_ds / 10)] s real, [round(world.time / 10)] s game: drakes [drakes], clown cats [cats], clowns [clowns], humans [humans], \
		other living [other], lava tiles [lava], most things on a tile [biggest], on the pile [length(pile.contents)]"
