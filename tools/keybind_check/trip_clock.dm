// How smoothly the client draws a trip's vision. A marker sweeps along the screen at a steady speed, over everything; the window is
// grabbed as fast as it can be, and where the marker sits in each grab against when the grab was taken shows how old the frame on
// the screen was. A smooth client draws a new frame every few dozen ms; a stutter is a frame that stays up far longer.
// Not part of the game: HARNESS=trip_clock.dm SENDER=clock_capture.ps1 MAP=testbench tools/keybind_check/run.sh tripclock
// then python tools/keybind_check/clock_read.py. The marker runs on the splash screen's plane, above the trip.

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
			trip_clock_run(src)

/proc/clock_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)

/// Grabs the window as fast as it can for seconds, while the vision is driven as life ticks would drive it
/proc/clock_phase(name, seconds, datum/trip_vision/V, intensity = 0.7)
	kc_log("phase [name]")
	text2file("[name],[seconds]", "data/trip_clock_go")
	var/deadline = world.time + (seconds + 20) SECONDS
	while(fexists("data/trip_clock_go") && world.time < deadline)
		V?.update(intensity, FALSE, clamp((intensity - 0.3) / 0.5, 0, 1) * 0.7)
		sleep(2 SECONDS)
	clock_shot("clock_[name]")

/proc/trip_clock_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	fdel("data/trip_clock_go")
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 4 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
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
	sleep(3 SECONDS)
	// the clock: 400 px across in 2 s, over and over
	var/obj/screen/marker = new
	marker.icon = 'icons/mob/screen_gen.dmi'
	marker.icon_state = "flash"
	marker.color = "#ff00ff"
	marker.plane = SPLASHSCREEN_PLANE
	marker.screen_loc = "1,3"
	marker.appearance_flags = NO_CLIENT_COLOR | PIXEL_SCALE
	marker.mouse_opacity = MOUSE_OPACITY_TRANSPARENT
	C.screen += marker
	sleep(1)
	marker.transform = matrix(0.5, 0, 0, 0, 0.5, 0)
	animate(marker, transform = matrix(0.5, 0, 200, 0, 0.5, 0), time = 10, loop = -1)
	animate(transform = matrix(0.5, 0, 400, 0, 0.5, 0), time = 10)
	sleep(2 SECONDS)
	text2file("go", "data/keycheck_sendkeys") //starts clock_capture.ps1
	sleep(3 SECONDS)

	clock_phase("base", 6)
	var/datum/trip_vision/V = new(H)
	H.trip_vision = V
	V.start()
	for(var/i in 1 to 6)
		V.update(0.7, FALSE, 0.5)
		sleep(2 SECONDS)
	kc_log("view alpha [V.view_pm.alpha] mood [V.mood] sway [V.sway_period] grade [V.grade_period] fractal [V.fractal_alpha]")
	clock_phase("trip", 6, V)
	V.flow_until = 0
	V.flow_size = 0
	V.update(0.9, FALSE, 0.6) // a flow glide
	clock_phase("flow_glide", 5, V, 0.9)
	V.fisheye_until = 0
	V.fisheye(3)
	clock_phase("fisheye", 6, V)
	V.ripple(3)
	V.melt(3)
	V.radial(3)
	V.rays(3)
	V.bloom(3)
	clock_phase("bursts", 5, V)
	sleep(4 SECONDS)
	V.colour_until = 0
	V.flash(TRUE)
	clock_phase("flash", 4, V)
	V.geometry_until = 0
	V.spin()
	clock_phase("spin", 7, V)
	sleep(2 SECONDS)
	V.split(3)
	clock_phase("split", 4, V)
	V.kaleido_until = 0
	V.set_kaleido(255, 3 SECONDS)
	clock_phase("kaleido_fading_in", 3, V)
	V.kaleido_until = world.time + 1 MINUTES
	clock_phase("kaleido", 5, V)
	V.kaleido_until = 0
	V.set_kaleido(0, 2 SECONDS)
	sleep(3 SECONDS)
	V.tunnel(16 SECONDS)
	sleep(4 SECONDS)
	clock_phase("tunnel", 6, V)
	sleep(8 SECONDS)
	V.geometry_until = 0
	V.breakthrough(14 SECONDS)
	sleep(3 SECONDS)
	clock_phase("breakthrough", 7, V, 0.95)
	qdel(V)
	sleep(2 SECONDS)
	clock_phase("after", 5)
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
