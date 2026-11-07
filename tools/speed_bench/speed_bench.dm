// What the everyday things cost on the real station: a step, a word, a radio message, a bullet, a mob's Life(). Not part of the game: tools/speed_bench/run.sh
// A crowd of equipped crew in a hallway, no clients. Each thing is timed in batches that fit inside a tick, in real CPU time, and the
// median batch is reported so a busy moment doesn't count. Nothing here sees a client: what a client costs is not in these numbers.

/datum/controller/master
	sleep_offline_after_initializations = FALSE

GLOBAL_LIST_EMPTY(sb_crew)

/proc/sb_log(text)
	text2file(text, "data/speed_bench.txt")

/world/New()
	. = ..()
	spawn(0)
		speed_bench_run()

/proc/sb_report(label, list/times, unit = "us")
	var/list/sorted = sortTim(times.Copy(), /proc/cmp_numeric_asc)
	var/middle = sorted[ceil(length(sorted) / 2)]
	sb_log("[label]: [round(middle, 0.1)] [unit] (best [round(sorted[1], 0.1)], worst [round(sorted[length(sorted)], 0.1)], [length(sorted)] batches)")

/// One section, and with the boot param speed-profile=1 the profile of just that section in data/speed_profile_<name>.json
/proc/sb_run(name, proc_path, arg1, arg2)
	var/profiling = ("speed-profile" in world.params)
	if(profiling)
		world.Profile(PROFILE_CLEAR)
		world.Profile(PROFILE_START)
	call(proc_path)(arg1, arg2)
	if(profiling)
		var/report = world.Profile(PROFILE_REFRESH, format = "json")
		world.Profile(PROFILE_STOP)
		fdel("data/speed_profile_[name].json")
		text2file(report, "data/speed_profile_[name].json")

/proc/sb_person(turf/where)
	var/mob/living/carbon/human/H = new(where)
	H.equipOutfit(/datum/outfit/job/engineer)
	GLOB.sb_crew += H
	return H

/// One person on their own at the far end of the hallway, so what's timed is steps and not bumping into the crowd
/proc/sb_steps(turf/where)
	var/mob/living/carbon/human/H = sb_person(where)
	GLOB.sb_crew -= H
	var/list/times = list()
	var/d = EAST
	var/moved = 0
	for(var/b in 1 to 40)
		sleep(1)
		var/start = TICK_USAGE_REAL
		for(var/i in 1 to 150)
			if(H.Move(get_step(H, d), d))
				moved++
			else
				d = pick(GLOB.cardinals)
		times += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start) * 1000 / 150
	sb_report("a step ([moved] of [40 * 150] moved)", times)

/proc/sb_say()
	var/mob/living/carbon/human/H = GLOB.sb_crew[2]
	var/list/times = list()
	for(var/b in 1 to 30)
		sleep(2)
		var/start = TICK_USAGE_REAL
		for(var/i in 1 to 10)
			H.say("testing, testing, number [b] [i]")
		times += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start) * 1000 / 10
	sb_report("saying something with [length(GLOB.sb_crew)] around", times)

/proc/sb_radio()
	var/mob/living/carbon/human/H = GLOB.sb_crew[2]
	var/list/times = list()
	for(var/b in 1 to 30)
		sleep(2)
		var/start = TICK_USAGE_REAL
		for(var/i in 1 to 5)
			H.say(";radio test number [b] [i]")
		times += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start) * 1000 / 5
	sb_report("a radio message", times)

/proc/sb_radio_hearers()
	var/list/radios = list()
	for(var/obj/item/radio/R in GLOB.all_radios["[FREQ_COMMON]"])
		if(R.can_receive(FREQ_COMMON, list(SSmapping.station_start)))
			radios += R
	var/list/times = list()
	var/list/heard
	for(var/b in 1 to 30)
		sleep(1)
		var/start = TICK_USAGE_REAL
		for(var/i in 1 to 5)
			heard = get_mobs_in_radio_ranges(radios)
		times += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start) * 1000 / 5
	sb_report("working out who hears a radio ([length(radios)] radios, [length(heard)] hearers)", times)

/proc/sb_hearers()
	var/mob/living/carbon/human/H = GLOB.sb_crew[3]
	var/list/times = list()
	var/list/heard
	for(var/b in 1 to 30)
		sleep(1)
		var/start = TICK_USAGE_REAL
		for(var/i in 1 to 30)
			heard = get_hearers_in_view(7, H)
		times += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start) * 1000 / 30
	sb_report("finding who can hear something ([length(heard)] found)", times)

/proc/sb_visible()
	var/mob/living/carbon/human/H = GLOB.sb_crew[3]
	var/list/times = list()
	for(var/b in 1 to 30)
		sleep(1)
		var/start = TICK_USAGE_REAL
		for(var/i in 1 to 30)
			H.visible_message("[H] does something.")
		times += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start) * 1000 / 30
	sb_report("a visible message", times)

/proc/sb_examine()
	var/mob/living/carbon/human/H = GLOB.sb_crew[3]
	var/mob/living/carbon/human/other = GLOB.sb_crew[4]
	var/list/times = list()
	for(var/b in 1 to 30)
		sleep(1)
		var/start = TICK_USAGE_REAL
		for(var/i in 1 to 10)
			other.examine(H)
		times += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start) * 1000 / 10
	sb_report("examining a person", times)

/proc/sb_life()
	var/list/times = list()
	var/turn_number = 0
	for(var/b in 1 to 30)
		sleep(1)
		var/start = TICK_USAGE_REAL
		for(var/mob/living/carbon/human/H as anything in GLOB.sb_crew)
			H.Life(2, ++turn_number)
		times += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start) * 1000 / length(GLOB.sb_crew)
	sb_report("a person's Life()", times)

/proc/sb_hostile(turf/spot)
	var/list/carps = list()
	for(var/i in 1 to 10)
		var/mob/living/simple_animal/hostile/carp/C = new(spot)
		C.toggle_ai(AI_OFF)
		carps += C
	var/list/times = list()
	for(var/b in 1 to 30)
		sleep(1)
		var/start = TICK_USAGE_REAL
		for(var/mob/living/simple_animal/hostile/carp/C as anything in carps)
			C.ListTargets()
		times += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start) * 1000 / length(carps)
	sb_report("a hostile mob looking for targets", times)
	QDEL_LIST(carps)

/proc/sb_projectile(turf/from, angle)
	var/list/times = list()
	var/moves_done = 0
	for(var/b in 1 to 30)
		sleep(1)
		var/obj/item/projectile/bullet/c9mm/P = new(from)
		P.range = 300
		P.firer = null
		P.fire(angle)
		var/moves = 0
		var/start = TICK_USAGE_REAL
		for(var/i in 1 to 16)
			if(QDELETED(P))
				break
			P.pixel_move(1)
			moves++
		var/spent = TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
		if(moves)
			times += spent * 1000 / moves
		moves_done += moves
		if(!QDELETED(P))
			qdel(P)
	sb_report("a bullet's move ([moves_done] moves)", times)

/// Routes between departments the way a bot plans its first try (bot_movement.dm: Distance_cardinal, bot_reachable_strict, 300 nodes,
/// its own card, an engineer's here), the same routes every boot. Timed whole, a search a sample, with the tiles they opened.
/proc/sb_paths()
	var/list/areas = list(/area/crew_quarters/bar, /area/medical/medbay/central, /area/engine/engineering, /area/science/research, /area/quartermaster/storage,
		/area/bridge, /area/security/brig, /area/hydroponics, /area/crew_quarters/kitchen, /area/janitor, /area/hallway/primary/central, /area/storage/primary)
	var/list/spots = list()
	for(var/A in areas)
		for(var/turf/open/floor/T in get_area_turfs(A))
			if(!is_blocked_turf(T, TRUE))
				spots += T
				break
	if(length(spots) < 2)
		sb_log("paths: only [length(spots)] places found")
		return
	var/mob/living/carbon/human/H = sb_person(spots[1])
	GLOB.sb_crew -= H
	var/obj/item/card/id/card = H.get_idcard()
	var/list/times = list()
	var/total = 0
	var/steps = 0 //every route's length added up: the same in a faster build, or it's found different routes
	var/turfs_before = GLOB.astar_tally["turfs"]
	var/failed_before = GLOB.astar_tally["failed"]
	for(var/turf/from in spots)
		for(var/turf/dest in spots)
			if(from == dest)
				continue
			H.forceMove(from)
			sleep(1)
			var/start = TICK_USAGE_REAL
			var/list/path = get_path_to(H, dest, /turf/proc/Distance_cardinal, 300, 250, adjacent = /turf/proc/bot_reachable_strict, id = card, simulated_only = TRUE)
			var/took = TICK_DELTA_TO_MS(TICK_USAGE_REAL - start) * 1000
			times += took
			total += took
			steps += length(path)
	var/searches = length(times)
	sb_report("a route between departments ([length(spots)] places, [GLOB.astar_tally["failed"] - failed_before] of [searches] found none, [round((GLOB.astar_tally["turfs"] - turfs_before) / searches)] tiles opened each, [steps] steps in all, [round(total / 1000, 0.1)] ms in all)", times)

/// update_icon() on every station APC and airlock, and regenerate_icons() on the crew. A build with the old overlay queue
/// has its queue flushed inside the timing, so both builds pay for getting the overlays onto the atoms.
/proc/sb_overlays()
	var/list/things = list()
	for(var/obj/machinery/power/apc/A in GLOB.apcs_list)
		if(is_station_level(A.z))
			things += A
	for(var/obj/machinery/door/airlock/D in GLOB.airlocks)
		if(is_station_level(D.z))
			things += D
	var/list/times = list()
	for(var/b in 1 to 30)
		sleep(1)
		var/start = TICK_USAGE_REAL
		for(var/obj/O as anything in things)
			O.update_icon()
		if("queue" in SSoverlays.vars)
			SSoverlays.fire(FALSE, FALSE)
		times += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start) * 1000 / length(things)
	sb_report("an APC or airlock update_icon() ([length(things)] of them)", times)
	times = list()
	for(var/b in 1 to 30)
		sleep(1)
		var/start = TICK_USAGE_REAL
		for(var/mob/living/carbon/human/H as anything in GLOB.sb_crew)
			H.regenerate_icons()
		if("queue" in SSoverlays.vars)
			SSoverlays.fire(FALSE, FALSE)
		times += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start) * 1000 / length(GLOB.sb_crew)
	sb_report("a crew member's regenerate_icons() ([length(GLOB.sb_crew)] of them)", times)

/proc/sb_hallway()
	. = list()
	for(var/turf/open/floor/T in get_area_turfs(/area/hallway/primary/central))
		if(!is_blocked_turf(T, TRUE))
			. += T

/proc/speed_bench_run()
	UNTIL(SSticker.initialized) // it reads data/mode.txt when it starts up
	GLOB.master_mode = "extended" // data/mode.txt is whatever the last real round left there, and most modes won't start with nobody playing
	SSticker.start_immediately = TRUE
	var/deadline = world.time + 5 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < deadline)
		sleep(1 SECONDS)
	sleep(15 SECONDS)
	var/list/spots = sb_hallway()
	if(length(spots) < 40)
		sb_log("only [length(spots)] hallway tiles")
		sb_log("done")
		del(world)
		return
	var/turf/middle = spots[round(length(spots) / 2)]
	var/made = 0
	for(var/turf/T in spots)
		if(get_dist(T, middle) <= 2 && made < 12)
			sb_person(T)
			made++
	for(var/turf/T in spots)
		if(made >= 12)
			break
		sb_person(T)
		made++
	sleep(5 SECONDS)
	sb_log("round state [SSticker.current_state], [length(GLOB.sb_crew)] crew, [length(GLOB.player_list)] players, [length(GLOB.all_radios["[FREQ_COMMON]"])] radios on common")
	sb_run("step", /proc/sb_steps, spots[length(spots)])
	sb_run("say", /proc/sb_say)
	sb_run("radio", /proc/sb_radio)
	sb_run("radio_hearers", /proc/sb_radio_hearers)
	sb_run("visible", /proc/sb_visible)
	sb_run("hearers", /proc/sb_hearers)
	sb_run("examine", /proc/sb_examine)
	sb_run("life", /proc/sb_life)
	sb_run("hostile", /proc/sb_hostile, spots[1])
	sb_run("projectile", /proc/sb_projectile, spots[1], 90)
	sb_run("paths", /proc/sb_paths)
	sb_run("overlays", /proc/sb_overlays)
	sb_log("done")
	sleep(5)
	del(world)
