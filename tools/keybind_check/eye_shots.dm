// Pictures of the tone curve and eye adaptation with a real client (lighting_tone.dm, eye_adapt.dm).
// Not part of the game: HARNESS=eye_shots.dm SENDER=shot.ps1 tools/keybind_check/run.sh eye
// It needs the real station, so no MAP=testbench. Pictures in data/previews/eye_*.png, notes in data/keycheck_eye.txt.
// 1 each room with tg's cut-off, 2 with the tone curve (adaptation off for both); then walking from the hallway into
// maintenance and back with adaptation on, pictured as the eyes adjust; then night vision and Low graphics, which turn it off.

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
			eye_shots_run(src)

/proc/eye_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/// A clear floor near the middle of the first station area of a type.
/proc/eye_spot(area_type)
	for(var/area/A in GLOB.sortedAreas)
		if(!istype(A, area_type))
			continue
		var/list/floors = list()
		var/sum_x = 0
		var/sum_y = 0
		for(var/turf/open/floor/T in A)
			if(!is_station_level(T.z))
				continue
			floors += T
			sum_x += T.x
			sum_y += T.y
		if(length(floors) < 12)
			continue
		var/mid_x = sum_x / length(floors)
		var/mid_y = sum_y / length(floors)
		var/turf/best
		var/best_dist = INFINITY
		for(var/turf/open/floor/T as anything in floors)
			if(T.density || (locate(/obj/structure) in T) || (locate(/obj/machinery) in T))
				continue
			var/dist = (T.x - mid_x) ** 2 + (T.y - mid_y) ** 2
			if(dist < best_dist)
				best_dist = dist
				best = T
		if(best)
			return best

/// A floor two tiles from a lone working lamp in maintenance: a pool of light with dark round it
/proc/eye_maint_spot()
	for(var/obj/machinery/light/L in world)
		if(!L.on || !is_station_level(L.z) || !istype(get_area(L), /area/maintenance))
			continue
		var/lamps = 0
		for(var/obj/machinery/light/near in range(7, L))
			if(near.on)
				lamps++
		if(lamps != 1)
			continue
		for(var/turf/open/floor/T in range(2, L))
			if(get_dist(T, L) == 2 && !T.density && !(locate(/obj/structure) in T) && !(locate(/obj/machinery) in T) && istype(T.loc, /area/maintenance))
				return T

/proc/eye_state(mob/M)
	var/obj/screen/plane_master/lighting/PM = M.hud_used.plane_masters["[LIGHTING_PLANE]"]
	var/turf/T = get_turf(M)
	return "brightness [round(SSeye_adapt.eye_brightness(T, M.client), 0.001)], exposure [round(PM.exposure, 0.001)], shown [round(PM.exposure_shown, 0.001)], colour [islist(PM.color) ? jointext(PM.color, ",") : "none"]"

/proc/eye_adapting(mob/M, on)
	SSeye_adapt.can_fire = on
	if(!on)
		var/obj/screen/plane_master/lighting/PM = M.hud_used.plane_masters["[LIGHTING_PLANE]"]
		PM.exposure = 1
		PM.exposure_shown = 1
		animate(PM)
		PM.color = null

/proc/eye_tone(knee)
	SSlighting.set_tone(knee)
	sleep(4 SECONDS) // SSlighting redraws the lighting objects over its next few fires

/proc/eye_shots_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 4 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1
	kc_log("hwmode [winget(C, null, "hwmode")], view [C.view], lighting engine [SSlighting.native_status], knee [GLOB.lighting_tone_knee]")

	var/list/spots = list(
		"hall" = eye_spot(/area/hallway/primary/central),
		"bar" = eye_spot(/area/crew_quarters/bar),
		"engineering" = eye_spot(/area/engine/engineering),
		"maint" = eye_maint_spot())
	for(var/room in spots)
		var/turf/T = spots[room]
		kc_log(T ? "[room]: ([T.x],[T.y]) in [get_area(T)]" : "[room]: no spot found")

	var/mob/living/carbon/human/H = new(spots["hall"])
	H.mind_initialize()
	H.equipOutfit(/datum/outfit/job/assistant)
	H.status_flags |= GODMODE
	H.ckey = C.ckey
	sleep(2 SECONDS)
	H.hud_used.show_hud(HUD_STYLE_NOHUD)
	var/default_knee = GLOB.lighting_tone_knee

	// 1 and 2: tg's cut-off, then the tone curve, adaptation off
	eye_adapting(H, FALSE)
	for(var/knee in list(1, default_knee))
		eye_tone(knee)
		for(var/room in spots)
			if(!spots[room])
				continue
			H.forceMove(spots[room])
			sleep(12)
			eye_shot("eye_[room]_[knee == 1 ? "1_tg" : "2_tone"]")

	// 3: into maintenance from the hallway and back, adaptation on
	H.forceMove(spots["hall"])
	eye_adapting(H, TRUE)
	sleep(3 SECONDS)
	kc_log("hall, settled: [eye_state(H)]")
	if(spots["maint"])
		H.forceMove(spots["maint"])
		sleep(5)
		kc_log("maint, just in: [eye_state(H)]")
		eye_shot("eye_maint_3_arrive")
		sleep(15)
		kc_log("maint, 2 s: [eye_state(H)]")
		eye_shot("eye_maint_4_2s")
		sleep(8 SECONDS)
		kc_log("maint, 10 s: [eye_state(H)]")
		eye_shot("eye_maint_5_adapted")
		// Night vision, then Low graphics: back to as it was
		H.lighting_alpha = LIGHTING_PLANE_ALPHA_MOSTLY_VISIBLE
		H.sync_lighting_plane_alpha()
		sleep(2 SECONDS)
		kc_log("maint, night vision 2 s: [eye_state(H)]")
		H.lighting_alpha = LIGHTING_PLANE_ALPHA_VISIBLE
		H.sync_lighting_plane_alpha()
		sleep(8 SECONDS)
		kc_log("maint, night vision off 8 s: [eye_state(H)]")
		C.prefs.set_graphics_quality(GRAPHICS_QUALITY_LOW)
		sleep(2 SECONDS)
		kc_log("maint, Low graphics 2 s: [eye_state(H)]")
		C.prefs.set_graphics_quality(GRAPHICS_QUALITY_HIGH)
		sleep(8 SECONDS)
		kc_log("maint, High graphics 8 s: [eye_state(H)]")
		H.forceMove(spots["hall"])
		sleep(3)
		kc_log("hall, just back: [eye_state(H)]")
		eye_shot("eye_hall_3_back")
		sleep(2 SECONDS)
		kc_log("hall, 2 s: [eye_state(H)]")
		eye_shot("eye_hall_4_settled")
	kc_log("subsystem: [SSeye_adapt.stat_entry()]")

	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
