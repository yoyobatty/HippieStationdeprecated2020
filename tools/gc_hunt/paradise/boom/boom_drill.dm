// Local test, not part of any PR. Hippie's explosion drills on Paradise: boots headless, starts an extended round, puts 40 crew
// on the station walking about, and 40 seconds later at the middle of the station sets off one of (boom-drill=<what>)
//  none       nothing, a control
//  maxcap     one bomb at the cap (5/10/20)
//  maxcap6    six of them on the same tile at once
//  reactor    a fission reactor meltdown at its biggest, past the cap (20/40/43/46, ignorecap): Paradise's chemicals stop at the cap
//  tesla      an energy ball loose with five mini-balls
//  nuke       what a nuke on the station does here: station_explosion_cinematic(), every mob on the station level dusted
// Every tick's real length is kept from 20 seconds before to 3 minutes after, through timewarp's own clock (timewarp.dll next to
// the dmb). Results in data/boom/<what>.txt.

#define BOOM_BASELINE (20 SECONDS)
#define BOOM_AFTER (3 MINUTES)
#define BOOM_SURVEY 50
#define BOOM_CREW 40
#define BOOM_GC_WAIT ((text2num(world.params["boom-gc-wait"]) || 6.5) MINUTES)

GLOBAL_DATUM(boom_drill, /datum/boom_drill)

/world/New()
	. = ..()
	if(params["boom-drill"])
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(boom_drill_run), params["boom-drill"])

/proc/boom_real_ms()
	return text2num(splittext(call_ext("timewarp.dll", "timewarp_clock")(), " ")[1])

/proc/boom_drill_run(what)
	var/speed = call_ext("timewarp.dll", "timewarp_speed")("0")
	log_world("BOOM DRILL: timewarp [speed]")
	UNTIL(Master.current_runlevel)
	sleep(10 SECONDS)
	GLOB.master_mode = "extended"
	SSticker.force_start = TRUE
	var/wait_start = world.time
	UNTIL(SSticker.current_state == GAME_STATE_PLAYING || world.time > wait_start + 5 MINUTES)
	if(SSticker.current_state != GAME_STATE_PLAYING)
		text2file("round never started (state [SSticker.current_state])", "data/boom/[what].txt")
		del(world)
		return
	var/datum/boom_drill/D = new
	D.what = what
	GLOB.boom_drill = D
	D.go()
	text2file(D.report(), "data/boom/[what].txt")
	log_world("BOOM DRILL: done")
	del(world)

/datum/boom_drill
	var/what
	var/turf/epicenter
	var/event_time = 0
	var/sample_until = 0
	var/baseline_ms = 0
	var/baseline_ticks = 0
	var/after_ms = 0
	var/after_ticks = 0
	var/worst_ms = 0
	var/worst_at = 0
	var/over_100 = 0
	var/over_1000 = 0
	/// Explosions that finished, and the game time the slowest took from start to end
	var/booms_done = 0
	var/boom_longest = 0
	var/list/turf_types_before
	var/list/mob/living/carbon/human/crew = list()
	var/list/hard_deletes_before
	var/real_start

/datum/boom_drill/proc/go()
	sleep(20 SECONDS)
	var/z = levels_by_trait(STATION_LEVEL)[1]
	rand_seed(1337)
	var/list/turf/floors = list()
	var/sx = 0
	var/sy = 0
	for(var/turf/simulated/floor/T in block(1, 1, z, world.maxx, world.maxy, z))
		if(T.density || !istype(T.loc, /area/station))
			continue
		sx += T.x
		sy += T.y
		var/blocked = FALSE
		for(var/atom/movable/AM in T)
			if(AM.density)
				blocked = TRUE
				break
		if(!blocked)
			floors += T
	var/turf/middle = locate(round(sx / length(floors)), round(sy / length(floors)), z)
	for(var/turf/T as anything in floors)
		if(!epicenter || get_dist(T, middle) < get_dist(epicenter, middle))
			epicenter = T

	var/list/outfits = list(/datum/outfit/job/assistant, /datum/outfit/job/engineer, /datum/outfit/job/officer, /datum/outfit/job/doctor, /datum/outfit/job/scientist, /datum/outfit/job/cargo_tech, /datum/outfit/job/chef)
	for(var/i in 1 to BOOM_CREW)
		var/mob/living/carbon/human/H = new(pick(floors))
		H.equipOutfit(pick(outfits))
		if(text2num(world.params["boom-minds"]))
			H.mind_initialize() // the way a player's body has one
		crew += H
		SSmobs.clients_by_zlevel[z] += H
	for(var/datum/ai_controller/controller as anything in GLOB.ai_controllers_by_zlevel[z])
		controller.set_ai_status(controller.get_expected_ai_status())
	for(var/mob/living/simple_animal/SA as anything in SSidlenpcpool.idle_mobs_by_zlevel[z])
		SA?.toggle_ai(AI_ON)
	INVOKE_ASYNC(src, PROC_REF(walk_crew))

	RegisterSignal(SSdcs, COMSIG_GLOB_EXPLOSION, PROC_REF(on_explosion))
	// Real time while ticks are timed: skipping the idle time makes the game wait on MILLA's own thread, and every tick looks slow
	call_ext("timewarp.dll", "timewarp_speed")("1")
	event_time = world.time + BOOM_BASELINE
	sample_until = event_time + BOOM_AFTER
	INVOKE_ASYNC(src, PROC_REF(sample))
	sleep(BOOM_BASELINE)
	survey_before()
	hard_deletes_before = boom_hard_deletes()
	real_start = boom_real_ms()
	log_world("BOOM DRILL: [what] at [epicenter.x],[epicenter.y],[epicenter.z] in [get_area(epicenter)], map [SSmapping.map_datum?.technical_name]")
	switch(what)
		if("maxcap")
			explosion(epicenter, 1000, 1000, 1000, 1000, cause = "boom drill")
		if("maxcap6")
			for(var/i in 1 to 6)
				explosion(epicenter, 1000, 1000, 1000, 1000, cause = "boom drill")
		if("reactor")
			explosion(epicenter, 20, 40, 43, 46, ignorecap = TRUE, cause = "boom drill")
		if("tesla")
			var/obj/singularity/energy_ball/ball = new(epicenter, 200)
			for(var/i in 1 to 5)
				ball.new_mini_ball()
		if("nuke")
			INVOKE_ASYNC(SSticker, TYPE_PROC_REF(/datum/controller/subsystem/ticker, station_explosion_cinematic), NUKE_SITE_ON_STATION, null)
	UNTIL(world.time >= sample_until)
	// Something deleted is only checked 5 minutes later (GC_CHECK_QUEUE): fast-forward to past that for the hard deletes
	call_ext("timewarp.dll", "timewarp_speed")("0")
	UNTIL(world.time >= event_time + BOOM_GC_WAIT)

/datum/boom_drill/proc/walk_crew()
	while(world.time < sample_until || !sample_until)
		sleep(5)
		for(var/mob/living/carbon/human/H as anything in crew)
			if(QDELETED(H) || H.stat != CONSCIOUS || !isturf(H.loc) || prob(40))
				continue
			var/dir = pick(GLOB.cardinal)
			var/turf/next = get_step(H, dir)
			if(next && !next.density)
				H.Move(next, dir)

/datum/boom_drill/proc/on_explosion(datum/source, turf/epicenter, devastation_range, heavy_impact_range, light_impact_range, took)
	SIGNAL_HANDLER
	booms_done++
	boom_longest = max(boom_longest, took)

/datum/boom_drill/proc/survey_area()
	return block(max(1, epicenter.x - BOOM_SURVEY), max(1, epicenter.y - BOOM_SURVEY), epicenter.z, min(world.maxx, epicenter.x + BOOM_SURVEY), min(world.maxy, epicenter.y + BOOM_SURVEY), epicenter.z)

/datum/boom_drill/proc/survey_before()
	turf_types_before = list()
	for(var/turf/T as anything in survey_area())
		turf_types_before[T] = T.type

/datum/boom_drill/proc/sample()
	var/last = boom_real_ms()
	while(world.time < sample_until)
		sleep(world.tick_lag)
		var/now = boom_real_ms()
		var/gap = now - last
		last = now
		if(world.time < event_time)
			baseline_ms += gap
			baseline_ticks++
			continue
		after_ms += gap
		after_ticks++
		if(gap > worst_ms)
			worst_ms = gap
			worst_at = world.time - event_time
		if(gap > 100)
			over_100++
		if(gap > 1000)
			over_1000++

/proc/boom_hard_deletes()
	. = list()
	for(var/type_name in SSgarbage.items)
		var/datum/qdel_item/item = SSgarbage.items[type_name]
		.[type_name] = list(item.hard_deletes, item.hard_delete_time)

/datum/boom_drill/proc/report()
	var/changed = 0
	var/space = 0
	for(var/turf/T as anything in turf_types_before)
		if(T.type != turf_types_before[T])
			changed++
			if(isspaceturf(T))
				space++
	var/dead = 0
	for(var/mob/living/carbon/human/H as anything in crew)
		if(QDELETED(H) || H.stat == DEAD)
			dead++
	var/per_tick = baseline_ticks ? baseline_ms / baseline_ticks : 0
	var/extra = after_ms - per_tick * after_ticks
	var/list/after = boom_hard_deletes()
	var/hd_count = 0
	var/hd_ms = 0
	var/list/hd_types = list()
	for(var/type_name in after)
		var/list/now = after[type_name]
		var/list/was = hard_deletes_before[type_name] || list(0, 0)
		if(now[1] > was[1])
			hd_count += now[1] - was[1]
			hd_ms += now[2] - was[2]
			hd_types += "[type_name] [now[1] - was[1]]"
	return "boom drill [what] on [SSmapping.map_datum?.technical_name]: worst tick [round(worst_ms)] ms at +[round(worst_at / 10, 0.1)]s, [over_100] ticks over 100 ms, [over_1000] over a second; \
		[round(extra / 1000, 0.1)] s more than the ticks before ([round(per_tick, 0.1)] ms a tick then) over [BOOM_AFTER / 10] s; \
		[booms_done] explosions finished, the longest over [boom_longest] s of game time; [changed] tiles changed ([space] to space), [dead] of [length(crew)] crew dead; \
		[hd_count] hard deletes by +[BOOM_GC_WAIT / 600] min, [round(hd_ms)] ms: [jointext(hd_types, ", ")]"

#undef BOOM_BASELINE
#undef BOOM_AFTER
#undef BOOM_SURVEY
#undef BOOM_CREW
#undef BOOM_GC_WAIT
