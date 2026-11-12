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
	if(world.params["mob-storm-scenario"] == "speech")
		run_speech_storm(pile, text2num(world.params["mob-storm-seconds"]) || 60)
		mob_storm_log("done")
		sleep(1 SECONDS)
		Master.Shutdown()
		qdel(world)
		return
	if(world.params["mob-storm-scenario"] == "conveyor")
		run_conveyor_storm(pile, text2num(world.params["mob-storm-seconds"]) || 60)
		mob_storm_log("done")
		sleep(1 SECONDS)
		Master.Shutdown()
		qdel(world)
		return

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

// ---------------------------------------------------------------------------------------------
// mob-storm-scenario=conveyor: the griefer's lag machine. Two conveyor belts facing each other, 25 naked corpses and 50 glass
// shards on each tile, everything bouncing between them. Counts what the glass does (every shard's Crossed by a mob, every
// caltrop that answered: a cut and, for a shard, the glass_step sound before it) and what the server spent.
// ---------------------------------------------------------------------------------------------

GLOBAL_VAR_INIT(storm_glass_crossings, 0)
GLOBAL_VAR_INIT(storm_glass_reactions, 0)
GLOBAL_VAR_INIT(storm_body_moves, 0)

/obj/item/shard/Crossed(mob/living/L)
	if(istype(L))
		GLOB.storm_glass_crossings++
	return ..()

/datum/component/caltrop/Crossed(datum/source, atom/movable/AM)
	if(isliving(AM))
		GLOB.storm_glass_reactions++
	return ..()

/datum/mob_storm_watch/proc/body_moved()
	SIGNAL_HANDLER
	GLOB.storm_body_moves++

/proc/conveyor_storm_open(turf/T)
	return isopenturf(T) && !is_blocked_turf(T, TRUE) && !(locate(/obj/machinery) in T)

/proc/run_conveyor_storm(turf/A, seconds)
	var/turf/B
	var/turf/C
	for(var/d in GLOB.cardinals)
		var/turf/maybe_b = get_step(A, d)
		var/turf/maybe_c = get_step(A, turn(d, 90))
		if(conveyor_storm_open(maybe_b) && conveyor_storm_open(maybe_c))
			B = maybe_b
			C = maybe_c
			break
	if(!B)
		mob_storm_log("no room for the belts next to [A.x],[A.y]")
		return
	var/datum/mob_storm_watch/W = new

	// what one step does: a barefoot crewmember walks onto 5 shards, then onto 5 more
	for(var/i in 1 to 5)
		new /obj/item/shard(A)
		new /obj/item/shard(B)
	var/mob/living/carbon/human/walker = new(C)
	GLOB.storm_glass_crossings = 0
	GLOB.storm_glass_reactions = 0
	walker.Move(A, get_dir(C, A))
	var/first = GLOB.storm_glass_reactions
	var/first_crossed = GLOB.storm_glass_crossings
	sleep(1)
	walker.Move(B, get_dir(A, B))
	mob_storm_log("CHECK a barefoot step onto 5 shards: [first_crossed] crossed, [first] answered; the next step onto 5 more: [GLOB.storm_glass_crossings - first_crossed] crossed, [GLOB.storm_glass_reactions - first] answered (1 a step expected with the fix, 5 before). Walker on [walker.loc == B ? "the second tile" : "[walker.loc]"]")
	qdel(walker)

	// the machine
	var/dir = get_dir(A, B)
	new /obj/machinery/conveyor/auto(A, dir)
	new /obj/machinery/conveyor/auto(B, turn(dir, 180))
	// mob-storm-shards (default 50) a tile in all. A belt takes the first 30 things on its tile each pass and BYOND lists a tile's
	// objects before its mobs, so with 30 or more shards a tile the belts carry only glass and the bodies hardly ride
	var/shards = text2num(world.params["mob-storm-shards"]) || 50
	for(var/i in 1 to max(0, shards - 5))
		new /obj/item/shard(A)
		new /obj/item/shard(B)
	for(var/i in 1 to 50)
		var/mob/living/carbon/human/H = new((i % 2) ? A : B)
		H.death()
		W.RegisterSignal(H, COMSIG_MOVABLE_MOVED, TYPE_PROC_REF(/datum/mob_storm_watch, body_moved))
	mob_storm_log("built: belts at [A.x],[A.y] and [B.x],[B.y], [length(A.contents)] and [length(B.contents)] things on them, [get_area(A)] powered [A.loc:powered(AREA_USAGE_EQUIP)]")
	sleep(10 SECONDS) // the belts get going

	GLOB.storm_glass_crossings = 0
	GLOB.storm_glass_reactions = 0
	GLOB.storm_body_moves = 0
	var/start_real = REALTIMEOFDAY
	var/start_game = world.time
	W.watch()
	sleep(seconds SECONDS)
	W.watching = FALSE
	var/real = (REALTIMEOFDAY - start_real) / 10
	var/game = (world.time - start_game) / 10
	var/busy = 0
	var/list/selfs = SSprofiler.recent(round(real * 1000))
	var/list/bits = list()
	for(var/name in selfs)
		if(copytext(name, 1, 2) == "(") // idle, and BYOND's own time between ticks (the sampler can't tell them apart): procs only
			continue
		busy += selfs[name]
		if(length(bits) < 12)
			bits += "[name] [round(selfs[name], 0.01)] s"
	mob_storm_log("over [round(real, 0.1)] s real, [round(game, 0.1)] s game: procs busy [round(busy, 0.01)] s ([round(100 * busy / real, 0.1)]% of real time), \
		body moves [GLOB.storm_body_moves], shard crossings by mobs [GLOB.storm_glass_crossings], glass that answered (cut, and a shard's sound) [GLOB.storm_glass_reactions]")
	mob_storm_log("self time: [jointext(bits, ", ")]")
	mob_storm_log("TOTAL procs [round(100 * busy / real, 0.1)]%, game [round(100 * game / real)]%, worst stall [round(W.worst / 10, 0.1)] s, stalls over 0.5 s: [W.stalls]")

// ---------------------------------------------------------------------------------------------
// mob-storm-scenario=speech: a room of spammers. mob-storm-speakers (60) crew with headsets packed round the spot, every one of
// them doing something every tick in turn: talking, the common channel, an emote, a whisper. Everyone else on the station who
// hears (bots parse what they hear) pays too. No clients, so what reaching a player costs isn't in it.
// ---------------------------------------------------------------------------------------------

GLOBAL_VAR_INIT(storm_hears, 0)

/mob/living/carbon/human/Hear(message, atom/movable/speaker, message_language, raw_message, radio_freq, list/spans, message_mode)
	GLOB.storm_hears++
	return ..()

/proc/storm_measure_start()
	return list("real" = REALTIMEOFDAY, "game" = world.time)

/// Proc time, game speed and the heaviest procs over the window since storm_measure_start()
/proc/storm_measure_report(list/start, label)
	var/real = (REALTIMEOFDAY - start["real"]) / 10
	var/game = (world.time - start["game"]) / 10
	var/busy = 0
	var/list/selfs = SSprofiler.recent(round(real * 1000))
	var/list/bits = list()
	for(var/name in selfs)
		if(copytext(name, 1, 2) == "(")
			continue
		busy += selfs[name]
		if(length(bits) < 14)
			bits += "[name] [round(selfs[name], 0.01)] s"
	mob_storm_log("[label]: over [round(real, 0.1)] s real, [round(game, 0.1)] s game ([round(100 * game / max(real, 0.1))]%), procs busy [round(busy, 0.01)] s ([round(100 * busy / max(real, 0.1), 0.1)]% of real time)")
	mob_storm_log("self time: [jointext(bits, ", ")]")
	for(var/list/row in SSprofiler.recent_stacks(min(15000, round(real * 1000))))
		var/list/stack = row["stack"]
		mob_storm_log("   last 15 s, [round(row["ms"] / 1000, 0.1)] s: [jointext(stack.Copy(max(1, length(stack) - 7)), " > ")]")
	return busy

/proc/run_speech_storm(turf/center, seconds)
	var/count = text2num(world.params["mob-storm-speakers"]) || 60
	var/list/speakers = list()
	for(var/turf/open/floor/F in range(6, center))
		if(length(speakers) >= count)
			break
		if(is_blocked_turf(F, TRUE))
			continue
		var/mob/living/carbon/human/H = new(F)
		H.equipOutfit(/datum/outfit/job/assistant)
		H.real_name = "Spammer [length(speakers) + 1]"
		H.name = H.real_name
		speakers += H
	var/living = 0
	for(var/mob/living/carbon/human/H in GLOB.mob_living_list)
		living++
	mob_storm_log("speakers: [length(speakers)] round [center.x],[center.y] ([get_area(center)]); humans on the station: [living], bots: [length(GLOB.bot_brains)]")
	sleep(5 SECONDS)
	var/datum/mob_storm_watch/W = new
	var/sent = 0
	var/list/kinds = list("say" = 0, "radio" = 0, "emote" = 0, "whisper" = 0)
	GLOB.storm_hears = 0
	var/list/start = storm_measure_start()
	W.watch()
	var/n = 0
	var/end = REALTIMEOFDAY + seconds * 10
	while(REALTIMEOFDAY < end)
		n++
		var/i = 0
		for(var/mob/living/carbon/human/H as anything in speakers)
			i++
			if(QDELETED(H) || H.stat)
				continue
			switch((i + n) % 4)
				if(0)
					H.say("spam number [n] from [i], lorem ipsum dolor sit amet", ignore_spam = TRUE)
					kinds["say"]++
				if(1)
					H.say("; radio spam [n] from [i], all hands this is not a drill", ignore_spam = TRUE)
					kinds["radio"]++
				if(2)
					H.emote("me", EMOTE_VISIBLE, "flails wildly for the [n]th time", TRUE)
					kinds["emote"]++
				if(3)
					H.say("#whisper spam [n] from [i]", ignore_spam = TRUE)
					kinds["whisper"]++
			sent++
		sleep(world.tick_lag)
	W.watching = FALSE
	var/busy = storm_measure_report(start, "speech storm")
	var/list/kind_bits = list()
	for(var/k in kinds)
		kind_bits += "[k] [kinds[k]]"
	mob_storm_log("messages [sent] ([jointext(kind_bits, ", ")]), heard [GLOB.storm_hears] times by humans; [round(busy * 1e6 / max(sent, 1))] us of procs a message")
	mob_storm_log("TOTAL procs [round(100 * busy / seconds, 0.1)]%, worst stall [round(W.worst / 10, 0.1)] s, stalls over 0.5 s: [W.stalls], over 2 s: [W.big_stalls]")
