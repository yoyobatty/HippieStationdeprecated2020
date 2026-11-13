// Does a trip's vision play smoothly? Bursts of pictures in a row while it runs: a stutter or a freeze shows as frames that
// don't change between frames that do. Then the fractal's variations, and a real dose of Grape Blast.
// Not part of the game: HARNESS=trip_smooth.dm SENDER=shot.ps1 SHOT_MINUTES=8 MAP=testbench tools/keybind_check/run.sh tripsmooth
// Pictures in data/previews/smooth_*.png; each burst's times in data/keycheck_tripsmooth.txt.

GLOBAL_VAR_INIT(keycheck_running, FALSE)

/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

/proc/kc_log(text)
	text2file(text, "data/keycheck.txt")

/client/New()
	. = ..()
	if(. && !GLOB.keycheck_running)
		GLOB.keycheck_running = TRUE
		spawn(50)
			trip_smooth_run(src)

/proc/smooth_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(world.tick_lag)

/// count pictures as fast as they can be taken, each one's time (in ms of the day) logged
/proc/smooth_burst(name, count = 20)
	var/list/times = list()
	for(var/n in 1 to count)
		smooth_shot("smooth_[name]_[n]")
		times += "[world.timeofday]"
	kc_log("burst [name]: [jointext(times, ",")]")

/// Drives the vision as life ticks would, at a strength, for time
/proc/smooth_hold(datum/trip_vision/V, intensity, bad, time)
	var/until = world.time + time
	while(world.time < until)
		V.update(intensity, bad, clamp((intensity - 0.3) / 0.5, 0, 1) * 0.7 + (bad ? 0.3 : 0))
		sleep(2 SECONDS)

/datum/trip_hear_log/proc/heard(datum/source, list/hearing_args)
	SIGNAL_HANDLER
	kc_log("   heard: [hearing_args[HEARING_MESSAGE]]")

/proc/smooth_planes(mob/M)
	. = list()
	for(var/key in M.hud_used.plane_masters)
		var/obj/screen/plane_master/PM = M.hud_used.plane_masters[key]
		var/list/types = list()
		for(var/F in PM.filters)
			types += F:type
		. += "[PM.plane]: rt [PM.render_target || "-"] a[PM.alpha] f[jointext(types, "+")]"

/proc/trip_smooth_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 4 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1
	var/turf/spot
	for(var/turf/open/space/S in world)
		if(!is_station_level(S.z))
			continue
		for(var/turf/open/floor/F in range(3, S))
			if(!(locate(/obj/structure) in F) && F.get_lumcount() > 0.3)
				spot = F
				break
		if(spot)
			break
	var/mob/living/carbon/human/H = new(spot)
	H.mind_initialize()
	H.equipOutfit(/datum/outfit/job/assistant)
	H.status_flags |= GODMODE
	H.ckey = C.ckey
	sleep(4 SECONDS)
	var/list/planes_before = smooth_planes(H)

	var/datum/trip_vision/V = new(H)
	H.trip_vision = V
	V.start()
	smooth_hold(V, 0.5, FALSE, 8 SECONDS)
	kc_log("fractal: variation [V.fractal_variation[V.fractal_slot]] slot [V.fractal_slot] alpha [V.fractal_alpha], mood [V.mood], sway [V.sway_period], grade [V.grade_period]")
	smooth_hold(V, 0.7, FALSE, 6 SECONDS)
	smooth_burst("steady")
	V.kaleido_until = 0
	V.set_kaleido(255, 2 SECONDS)
	V.kaleido_until = world.time + 1 MINUTES
	smooth_hold(V, 0.7, FALSE, 3 SECONDS)
	smooth_burst("kaleido")
	V.kaleido_until = 0
	V.set_kaleido(0, 2 SECONDS)
	smooth_hold(V, 0.7, FALSE, 3 SECONDS)
	V.tunnel(20 SECONDS)
	smooth_hold(V, 0.7, FALSE, 4 SECONDS)
	smooth_burst("tunnel")
	// the fractal's variations, each fading into the next
	for(var/n in 1 to 4)
		V.next_fractal = 0
		V.fractal_until = 0
		smooth_hold(V, 0.9, FALSE, 8 SECONDS)
		kc_log("fractal [n]: variation [V.fractal_variation[V.fractal_slot]] slot [V.fractal_slot] alpha [V.fractal_alpha]")
		smooth_shot("smooth_fractal_[n]")
	smooth_hold(V, 0.9, TRUE, 6 SECONDS)
	smooth_shot("smooth_bad")
	qdel(V)
	sleep(2 SECONDS)

	// a real dose, with someone talking
	H.reagents.add_reagent(/datum/reagent/drug/grape_blast, 25)
	sleep(5 SECONDS)
	var/datum/trip_hear_log/hear_log = new
	hear_log.RegisterSignal(H, COMSIG_MOVABLE_HEAR, TYPE_PROC_REF(/datum/trip_hear_log, heard))
	var/mob/living/carbon/human/talker = new(get_step(spot, WEST))
	talker.status_flags |= GODMODE
	for(var/second in 1 to 70)
		sleep(1 SECONDS)
		H.forceMove(spot)
		if(second % 8 == 0)
			talker.say("hello there friend, how are you doing today")
		if(second % 20 == 0)
			smooth_shot("smooth_dose_[second]")
	hear_log.UnregisterSignal(H, COMSIG_MOVABLE_HEAR)
	qdel(talker)
	smooth_burst("dose", 12)
	H.reagents.remove_all_type(/datum/reagent/drug/grape_blast, 1000)
	sleep(12 SECONDS)
	var/list/planes_after = smooth_planes(H)
	kc_log(planes_before ~= planes_after ? "planes after: the same as before" : "planes after: CHANGED\n   before: [jointext(planes_before, " | ")]\n   after: [jointext(planes_after, " | ")]")
	kc_log("vision left: [H.trip_vision ? "yes" : "no"]")
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
