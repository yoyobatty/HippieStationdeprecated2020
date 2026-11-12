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
	if(world.params["mob-storm-scenario"] == "monkeys")
		run_monkey_storm(pile, text2num(world.params["mob-storm-seconds"]) || 60)
		mob_storm_log("done")
		sleep(1 SECONDS)
		Master.Shutdown()
		qdel(world)
		return
	if(world.params["mob-storm-scenario"] == "chemloop")
		run_chemloop_storm(pile, text2num(world.params["mob-storm-seconds"]) || 30)
		mob_storm_log("done")
		sleep(1 SECONDS)
		Master.Shutdown()
		qdel(world)
		return
	if(world.params["mob-storm-scenario"] == "fire")
		run_fire_storm(pile, text2num(world.params["mob-storm-seconds"]) || 90)
		mob_storm_log("done")
		sleep(1 SECONDS)
		Master.Shutdown()
		qdel(world)
		return
	if(world.params["mob-storm-scenario"] == "photo")
		run_photo_storm(pile, text2num(world.params["mob-storm-seconds"]) || 60)
		mob_storm_log("done")
		sleep(1 SECONDS)
		Master.Shutdown()
		qdel(world)
		return
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
GLOBAL_VAR_INIT(storm_squeaks, 0)

/datum/component/squeak/play_squeak()
	GLOB.storm_squeaks++
	return ..()

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

	// a squeaky toy (or anything else) moved onto 5 of its own kind: how many squeaks
	var/item_param = world.params["mob-storm-item"] || ""
	if(item_param && copytext(item_param, 1, 2) != "/") // run.sh passes it without the slash: Git Bash turns /obj/... into a path
		item_param = "/[item_param]"
	var/item_type = text2path(item_param) || /obj/item/shard
	if(item_type != /obj/item/shard)
		var/turf/D = get_step(C, turn(get_dir(A, C), 90))
		if(conveyor_storm_open(D))
			for(var/i in 1 to 5)
				new item_type(D)
			var/obj/item/mover = new item_type(C)
			GLOB.storm_squeaks = 0
			mover.Move(D, get_dir(C, D))
			mob_storm_log("CHECK one [mover] moved onto 5 more: [GLOB.storm_squeaks] squeak(s) (1 expected with the fix, 5 or 6 before)")
			for(var/obj/item/I in D)
				qdel(I)

	// the machine: mob-storm-pairs (1) pairs of facing belts. Each belt tile gets mob-storm-shards (50) of mob-storm-item (a glass
	// shard), and mob-storm-bodies (50) naked corpses are shared out over the belts. A belt takes the first 30 things on its tile
	// each pass and BYOND lists a tile's objects before its mobs, so with 30 or more items a tile the bodies hardly ride.
	var/per_tile = text2num(world.params["mob-storm-shards"]) || 50
	var/bodies = isnull(world.params["mob-storm-bodies"]) ? 50 : text2num(world.params["mob-storm-bodies"])
	var/pairs = text2num(world.params["mob-storm-pairs"]) || 1
	var/list/belts = list(list(A, B))
	var/list/used = list()
	used[A] = TRUE
	used[B] = TRUE
	used[C] = TRUE
	for(var/turf/T in range(10, A))
		if(length(belts) >= pairs)
			break
		if(used[T] || !conveyor_storm_open(T))
			continue
		for(var/d in GLOB.cardinals)
			var/turf/U = get_step(T, d)
			if(U && !used[U] && conveyor_storm_open(U))
				belts += list(list(T, U))
				used[T] = TRUE
				used[U] = TRUE
				break
	var/list/belt_tiles = list()
	for(var/list/pair in belts)
		var/turf/P = pair[1]
		var/turf/Q = pair[2]
		var/dir = get_dir(P, Q)
		new /obj/machinery/conveyor/auto(P, dir)
		new /obj/machinery/conveyor/auto(Q, turn(dir, 180))
		belt_tiles += P
		belt_tiles += Q
		for(var/turf/T in list(P, Q))
			var/already = (item_type == /obj/item/shard && (T == A || T == B)) ? 5 : 0
			for(var/i in 1 to max(0, per_tile - already))
				new item_type(T)
	for(var/i in 1 to bodies)
		var/mob/living/carbon/human/H = new(belt_tiles[(i % length(belt_tiles)) + 1])
		H.death()
		W.RegisterSignal(H, COMSIG_MOVABLE_MOVED, TYPE_PROC_REF(/datum/mob_storm_watch, body_moved))
	mob_storm_log("built: [length(belts)] pair(s) of belts from [A.x],[A.y], [per_tile] [item_type] a tile, [bodies] corpses, [length(A.contents)] things on the first tile, [get_area(A)] powered [A.loc:powered(AREA_USAGE_EQUIP)]")
	sleep(10 SECONDS) // the belts get going

	GLOB.storm_glass_crossings = 0
	GLOB.storm_glass_reactions = 0
	GLOB.storm_body_moves = 0
	GLOB.storm_squeaks = 0
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
		body moves [GLOB.storm_body_moves], shard crossings by mobs [GLOB.storm_glass_crossings], glass that answered (cut, and a shard's sound) [GLOB.storm_glass_reactions], squeaks [GLOB.storm_squeaks]")
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

// ---------------------------------------------------------------------------------------------
// mob-storm-scenario=photo: a 3x3 pile, mob-storm-shards (300) bits of glass and wrappers a tile and two dressed crew on each, and
// mob-storm-speakers (10) photographers round it taking 3x3 photos of it as fast as each one finishes.
// ---------------------------------------------------------------------------------------------

GLOBAL_VAR_INIT(storm_photos, 0)
GLOBAL_VAR_INIT(storm_photo_running, FALSE)
GLOBAL_VAR_INIT(storm_flat_icons, 0)

/obj/effect/appearance_clone/New(loc, atom/A) // one for every atom a photo draws
	GLOB.storm_flat_icons++
	return ..()

/proc/storm_photographer(mob/living/carbon/human/H, obj/item/camera/C, turf/target)
	set waitfor = FALSE
	while(GLOB.storm_photo_running && !QDELETED(H))
		C.captureimage(target, H, TRUE, 1, 1)
		GLOB.storm_photos++
		for(var/obj/item/photo/P in H.held_items)
			qdel(P)
		for(var/obj/item/photo/P in get_turf(H))
			qdel(P)
		sleep(world.tick_lag)

/proc/run_photo_storm(turf/center, seconds)
	var/per_tile = text2num(world.params["mob-storm-shards"]) || 300
	var/count = text2num(world.params["mob-storm-speakers"]) || 10
	for(var/turf/T in range(1, center))
		for(var/i in 1 to per_tile)
			if(i % 2)
				new /obj/item/shard(T)
			else
				new /obj/item/trash/candy(T)
		for(var/i in 1 to 2)
			var/mob/living/carbon/human/H = new(T)
			H.equipOutfit(/datum/outfit/job/engineer)
	var/list/photographers = list()
	for(var/turf/open/floor/F in range(3, center))
		if(length(photographers) >= count)
			break
		if(get_dist(F, center) < 3 || is_blocked_turf(F, TRUE))
			continue
		var/mob/living/carbon/human/H = new(F)
		var/obj/item/camera/C = new(F)
		H.put_in_hands(C)
		photographers[H] = C
	mob_storm_log("pile: [per_tile] a tile on the 3x3 round [center.x],[center.y] and 18 dressed crew; [length(photographers)] photographers")
	sleep(3 SECONDS)
	var/datum/mob_storm_watch/W = new
	GLOB.storm_photos = 0
	GLOB.storm_flat_icons = 0
	GLOB.storm_photo_running = TRUE
	var/list/start = storm_measure_start()
	W.watch()
	for(var/mob/living/carbon/human/H as anything in photographers)
		storm_photographer(H, photographers[H], center)
	sleep(seconds SECONDS)
	GLOB.storm_photo_running = FALSE
	W.watching = FALSE
	var/busy = storm_measure_report(start, "photo storm")
	mob_storm_log("photos [GLOB.storm_photos], atoms drawn [GLOB.storm_flat_icons] ([round(GLOB.storm_flat_icons / max(GLOB.storm_photos, 1))] a photo); [round(busy * 1000 / max(GLOB.storm_photos, 1), 0.1)] ms of procs a photo")
	mob_storm_log("TOTAL procs [round(100 * busy / seconds, 0.1)]%, worst stall [round(W.worst / 10, 0.1)] s, stalls over 0.5 s: [W.stalls], over 2 s: [W.big_stalls]")

// ---------------------------------------------------------------------------------------------
// mob-storm-scenario=fire: plasma and oxygen on every open floor of the station (or within mob-storm-range tiles of the spot),
// lit in mob-storm-speakers (5) places.
// ---------------------------------------------------------------------------------------------

/proc/fire_storm_census()
	var/hotspots = 0
	for(var/obj/effect/hotspot/H in world)
		hotspots++
	var/burning = 0
	for(var/obj/O in SSfire_burning.processing)
		burning++
	return "hotspots [hotspots], things burning [burning]"


/proc/run_fire_storm(turf/center, seconds)
	var/range = text2num(world.params["mob-storm-range"]) || 999
	var/lights = text2num(world.params["mob-storm-speakers"]) || 5
	var/list/floors = list()
	for(var/turf/open/floor/F in block(locate(1, 1, center.z), locate(world.maxx, world.maxy, center.z)))
		if(get_dist(F, center) > range || !is_station_level(F.z) || istype(get_area(F), /area/space))
			continue
		floors += F
	var/clutter = text2num(world.params["mob-storm-shards"]) || 0 // mob-storm-shards: bits of mob-storm-item (paper) on every floor
	var/item_param = world.params["mob-storm-item"] || "obj/item/paper"
	var/clutter_type = text2path(copytext(item_param, 1, 2) == "/" ? item_param : "/[item_param]") || /obj/item/paper
	for(var/turf/open/floor/F as anything in floors)
		F.atmos_spawn_air("plasma=30;o2=60;TEMP=293")
		for(var/i in 1 to clutter)
			new clutter_type(F)
		CHECK_TICK
	mob_storm_log("fire: plasma and oxygen on [length(floors)] floors round [center.x],[center.y], [clutter] [clutter_type] on each; [length(GLOB.bot_brains)] bots aboard")
	sleep(3 SECONDS)
	var/datum/mob_storm_watch/W = new
	var/list/start = storm_measure_start()
	W.watch()
	for(var/i in 1 to lights)
		var/turf/open/floor/F = pick(floors)
		F.hotspot_expose(1500, 500)
		new /obj/effect/hotspot(F)
	var/end = REALTIMEOFDAY + seconds * 10
	while(REALTIMEOFDAY < end)
		sleep(15 SECONDS)
		mob_storm_log("at [round((REALTIMEOFDAY - start["real"]) / 10)] s real, [round((world.time - start["game"]) / 10)] s game: [fire_storm_census()]")
	W.watching = FALSE
	var/busy = storm_measure_report(start, "fire storm")
	mob_storm_log("TOTAL procs [round(100 * busy / seconds, 0.1)]%, worst stall [round(W.worst / 10, 0.1)] s, stalls over 0.5 s: [W.stalls] adding to [round(W.stalled / 10, 0.1)] s, over 2 s: [W.big_stalls]")

// ---------------------------------------------------------------------------------------------
// mob-storm-scenario=chemloop: two recipes, in this build only, that make each other's ingredient (sugar to salt, salt back to
// sugar), and mob-storm-speakers (50) beakers of sugar poured one a tick. Without a stop in handle_reactions() the first one never
// finishes reacting, and the server never gets out of that tick.
// ---------------------------------------------------------------------------------------------

/datum/chemical_reaction/storm_loop_sugar_to_salt
	name = "storm loop: sugar to salt"
	id = "storm_loop_sugar_to_salt"
	results = list(/datum/reagent/consumable/sodiumchloride = 1)
	required_reagents = list(/datum/reagent/consumable/sugar = 1)

/datum/chemical_reaction/storm_loop_salt_to_sugar
	name = "storm loop: salt to sugar"
	id = "storm_loop_salt_to_sugar"
	results = list(/datum/reagent/consumable/sugar = 1)
	required_reagents = list(/datum/reagent/consumable/sodiumchloride = 1)

/proc/run_chemloop_storm(turf/center, seconds)
	var/count = text2num(world.params["mob-storm-speakers"]) || 50
	mob_storm_log("pouring [count] beakers of sugar at [center.x],[center.y], one a tick")
	var/datum/mob_storm_watch/W = new
	var/list/start = storm_measure_start()
	W.watch()
	for(var/i in 1 to count)
		var/obj/item/reagent_containers/glass/beaker/large/B = new(center)
		B.reagents.add_reagent(/datum/reagent/consumable/sugar, 50)
		if(i == 1)
			mob_storm_log("first beaker done reacting: [B.reagents.get_reagent_amount(/datum/reagent/consumable/sugar)] sugar, [B.reagents.get_reagent_amount(/datum/reagent/consumable/sodiumchloride)] salt")
		sleep(world.tick_lag)
	mob_storm_log("all [count] poured")
	sleep(seconds SECONDS)
	W.watching = FALSE
	var/busy = storm_measure_report(start, "chem loop")
	mob_storm_log("TOTAL procs [round(100 * busy / max(1, seconds), 0.1)]%, worst stall [round(W.worst / 10, 0.1)] s, stalls over 0.5 s: [W.stalls]")

// ---------------------------------------------------------------------------------------------
// mob-storm-scenario=monkeys: mob-storm-speakers (300) monkey cubes on the floor round the spot, all wetted in the same tick.
// ---------------------------------------------------------------------------------------------

/proc/run_monkey_storm(turf/center, seconds)
	var/count = text2num(world.params["mob-storm-speakers"]) || 300
	var/list/cubes = list()
	var/list/floors = list()
	for(var/turf/open/floor/F in range(5, center))
		if(!is_blocked_turf(F, TRUE))
			floors += F
	for(var/i in 1 to count)
		cubes += new /obj/item/reagent_containers/food/snacks/monkeycube(floors[(i % length(floors)) + 1])
	var/before = 0
	for(var/mob/living/carbon/monkey/M in GLOB.mob_living_list)
		before++
	mob_storm_log("[count] cubes on [length(floors)] floors round [center.x],[center.y]; [before] monkeys aboard before")
	sleep(2 SECONDS)
	var/datum/mob_storm_watch/W = new
	var/list/start = storm_measure_start()
	W.watch()
	var/spawn_start = TICK_USAGE_REAL
	for(var/obj/item/reagent_containers/food/snacks/monkeycube/C as anything in cubes)
		if(!QDELETED(C))
			C.Expand()
	mob_storm_log("all expanded in [round(TICK_DELTA_TO_MS(TICK_USAGE_REAL - spawn_start))] ms of one tick")
	sleep(seconds SECONDS)
	W.watching = FALSE
	var/after = 0
	for(var/mob/living/carbon/monkey/M in GLOB.mob_living_list)
		after++
	var/busy = storm_measure_report(start, "monkey storm")
	mob_storm_log("monkeys now [after]; TOTAL procs [round(100 * busy / seconds, 0.1)]%, worst stall [round(W.worst / 10, 0.1)] s, stalls over 0.5 s: [W.stalls]")
