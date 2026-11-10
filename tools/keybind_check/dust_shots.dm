// Pictures of the dust in the air with a real client, and what it costs the server to send.
// Not part of the game: HARNESS=dust_shots.dm SENDER=shot.ps1 SHOT_MINUTES=8 tools/keybind_check/run.sh dust
// Uses the real station (maintenance, the chapel, the library, a hallway, medbay). Pictures in data/previews/dust_*.png, notes in
// data/keycheck_dust.txt. Each place twice: dust on (High graphics), then off (Medium), from the same spot a moment apart.
// data/dust_shots_which holding "flow" skips the places and the walk: only the vent and the scrubber.
// Then the air moving it: bursts of pictures by a running vent, by a scrubber, and in a hallway with wind blown east across it
// (data/previews/dust_flow_*), and a walk up and down a hallway with the dust and without it, for world.map_cpu.

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
			dust_shots_run(src)

/proc/dust_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/// The floor of an area's kind nearest the middle of its biggest stretch on the station with the most lamps lit round it.
/proc/dust_spot(area_type)
	var/turf/best
	var/best_score = -1
	for(var/area/A in GLOB.sortedAreas)
		if(!istype(A, area_type))
			continue
		for(var/turf/open/floor/T in A)
			if(!is_station_level(T.z) || (T.x + T.y) % 2)
				continue
			if((locate(/obj/structure) in T) || (locate(/obj/machinery) in T))
				continue
			var/score = 0
			for(var/obj/machinery/light/L in range(4, T))
				if(L.on)
					score += 2
			for(var/turf/open/floor/near in range(3, T))
				if(near.loc == A)
					score++
			if(score > best_score)
				best_score = score
				best = T
	kc_log("[area_type]: spot ([best?.x],[best?.y]) in [get_area(best)], score [best_score]")
	return best

/proc/dust_holders()
	. = list()
	for(var/turf/open/floor/T in world)
		if(T.air_dust_fx)
			.[T] = T.air_dust_fx

/// A running vent or scrubber in a lit, dusty spot with open floor round it, moving dust of the kind asked for
/proc/dust_device(type, kind)
	var/obj/machinery/atmospherics/components/unary/best
	var/best_score = -1
	for(var/obj/machinery/atmospherics/components/unary/U in GLOB.machines)
		if(!istype(U, type) || U.dust_flow != kind || !is_station_level(U.z))
			continue
		var/score = 0
		for(var/turf/open/floor/near in range(2, U))
			if(!near.density && !(locate(/obj/structure) in near))
				score += 1 + near.get_lumcount() * 4 * (istype(near, /turf/open/floor/plasteel/white) ? 0 : 1) //lit, not white: dust shows where the light falls on something darker than it
		if(score > best_score)
			best_score = score
			best = U
	kc_log("[kind]: [best] at ([best?.x],[best?.y]) in [get_area(best)], score [best_score]")
	return best

/// Pictures in quick succession, for the trails the specks leave between them
/proc/dust_burst(name, frames = 4)
	for(var/i in 1 to frames)
		dust_shot("[name]_[i]")
		sleep(2)

/proc/dust_walk(mob/living/carbon/human/H, turf/start, seconds)
	H.forceMove(start)
	sleep(10)
	var/cpu = 0
	var/samples = 0
	var/dir = EAST
	var/stop_at = world.time + seconds SECONDS
	while(world.time < stop_at)
		if(!step(H, dir))
			dir = turn(dir, 180)
		cpu += world.map_cpu
		samples++
		sleep(2)
	return samples ? round(cpu / samples, 0.01) : 0

/proc/dust_shots_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 4 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1

	var/list/holders = dust_holders()
	var/light = 0
	var/heavy = 0
	var/in_medical = 0
	for(var/turf/T as anything in holders)
		var/area/A = T.loc
		if(A.air_dust == AIR_DUST_HEAVY)
			heavy++
		else
			light++
		if(istype(A, /area/medical))
			in_medical++
	var/list/flows = list()
	for(var/obj/machinery/atmospherics/components/unary/U in GLOB.machines)
		if(U.dust_flow)
			flows["[U.type] [U.dust_flow == "air_dust_vent" ? "out" : "in"]"]++
	kc_log("[length(holders)] floors hold dust ([light] light, [heavy] heavy, [in_medical] in medical); moving it: [json_encode(flows)]")

	var/list/places = list(
		"maint" = /area/maintenance,
		"chapel" = /area/chapel,
		"library" = /area/library,
		"hallway" = /area/hallway/primary)
	var/list/spots = list()
	for(var/name in places)
		spots[name] = dust_spot(places[name])
	var/turf/first = spots["hallway"] || spots[spots[1]]

	var/mob/living/carbon/human/H = new(first)
	H.mind_initialize()
	H.equipOutfit(/datum/outfit/job/assistant)
	H.status_flags |= GODMODE
	H.ckey = C.ckey
	sleep(2 SECONDS)
	H.hud_used.show_hud(HUD_STYLE_NOHUD)
	var/obj/screen/plane_master/air_dust/PM = H.hud_used.plane_masters["[AIR_DUST_PLANE]"]
	kc_log("hwmode [winget(C, null, "hwmode")], view [C.view], dust plane master [PM ? "there" : "missing"], filters [PM ? length(PM.filters) : 0]")

	var/flow_only = fexists("data/dust_shots_which") && trim(file2text("data/dust_shots_which")) == "flow"
	for(var/name in spots)
		if(flow_only)
			break
		var/turf/T = spots[name]
		if(!T)
			continue
		C.prefs.set_graphics_quality(GRAPHICS_QUALITY_HIGH)
		H.hud_used.plane_masters_update()
		H.forceMove(T)
		sleep(12 SECONDS) //the specks fill in over about eight seconds once a square comes into view
		var/near = 0
		for(var/turf/held as anything in holders)
			if(held.z == T.z && abs(held.x - T.x) <= 10 && abs(held.y - T.y) <= 7)
				near++
		kc_log("[name]: [near] dust squares in view, plane alpha [PM?.alpha]")
		dust_shot("dust_[name]_1_on")
		C.prefs.set_graphics_quality(GRAPHICS_QUALITY_MEDIUM)
		H.hud_used.plane_masters_update()
		sleep(5)
		kc_log("[name] on Medium: plane alpha [PM?.alpha]")
		dust_shot("dust_[name]_2_off")

	// The air moving it
	C.prefs.set_graphics_quality(GRAPHICS_QUALITY_HIGH)
	H.hud_used.plane_masters_update()
	var/obj/machinery/atmospherics/components/unary/vent = dust_device(/obj/machinery/atmospherics/components/unary/vent_pump, "air_dust_vent")
	if(vent)
		H.forceMove(locate(vent.x, vent.y - 3, vent.z) || get_turf(vent))
		sleep(8 SECONDS)
		dust_burst("dust_flow_vent")
	var/obj/machinery/atmospherics/components/unary/scrubber = dust_device(/obj/machinery/atmospherics/components/unary/vent_scrubber, "air_dust_scrubber")
	if(scrubber)
		H.forceMove(locate(scrubber.x, scrubber.y - 3, scrubber.z) || get_turf(scrubber))
		sleep(8 SECONDS)
		dust_burst("dust_flow_scrubber")
	if(flow_only)
		// The hallway dust as it is, then on Medium (none at all), then High again: a picture each
		H.forceMove(first)
		sleep(10 SECONDS)
		var/list/near = list()
		for(var/turf/open/floor/T as anything in holders)
			if(T.z == first.z && abs(T.x - first.x) <= 7 && abs(T.y - first.y) <= 7)
				near += "([T.x - first.x],[T.y - first.y]) plane [T.air_dust_fx.plane] vis_flags [T.air_dust_fx.vis_flags]"
		kc_log("dust squares round the viewer: [near.Join("; ")]")
		dust_burst("dust_flow_still", 2)
		C.prefs.set_graphics_quality(GRAPHICS_QUALITY_MEDIUM)
		H.hud_used.plane_masters_update()
		sleep(10)
		dust_shot("dust_flow_still_medium")
		C.prefs.set_graphics_quality(GRAPHICS_QUALITY_HIGH)
		H.hud_used.plane_masters_update()
		dust_finish(C)
		return
	// Wind east across the hallway: every dust square in view feels it, as SSair would tell it, twice a second
	H.forceMove(first)
	sleep(10 SECONDS)
	dust_burst("dust_flow_calm")
	var/list/windy = list()
	for(var/turf/open/floor/T as anything in holders)
		if(T.z == first.z && abs(T.x - first.x) <= 10 && abs(T.y - first.y) <= 8)
			windy += T
	for(var/pass in 1 to 16)
		for(var/turf/open/floor/T as anything in windy)
			T.pressure_difference = 12
			T.pressure_direction = EAST
			T.high_pressure_movements()
			T.pressure_difference = 0
		if(pass == 10)
			var/obj/effect/particle_fx/air_dust/sample = windy[1]?.air_dust_fx
			kc_log("wind: [length(windy)] squares, [length(GLOB.windy_dust)] showing it, the first going [sample?.wind_dir] at [sample?.wind_speed]")
			dust_burst("dust_flow_wind")
		sleep(5)
	sleep(5 SECONDS)
	var/obj/effect/particle_fx/air_dust/after = windy[1]?.air_dust_fx
	kc_log("wind over: [length(GLOB.windy_dust)] still showing it, the first going [after?.wind_dir] at [after?.wind_speed]")

	// What it costs to send: a walk up and down the hallway with the dust held, then with it taken off every floor
	var/with_dust = dust_walk(H, first, 20)
	for(var/turf/T as anything in holders)
		T.vis_contents -= holders[T]
	var/without = dust_walk(H, first, 20)
	kc_log("walking: map_cpu [with_dust] with the dust, [without] without")
	for(var/turf/T as anything in holders)
		T.vis_contents += holders[T]

	dust_finish(C)

/proc/dust_finish(client/C)
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
