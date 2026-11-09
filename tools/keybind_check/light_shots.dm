// Pictures of the station's lighting with a real client: lamp mood and the soft finish before and after, and the lights that move.
// Not part of the game: HARNESS=light_shots.dm SENDER=shot.ps1 SHOT_MINUTES=9 tools/keybind_check/run.sh light
// It needs the real station (its departments), so no MAP=testbench. Pictures in data/previews/light_*.png, notes in
// data/keycheck_light.txt. For each room: 1 every lamp plain white with Low graphics (how it was), 2 the room's own lamps,
// 3 the soft finish on top. Then a tripped fire alarm, the supermatter and a plasma fire, each pictured twice a moment apart.

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
			light_shots_run(src)

/proc/light_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/// A clear floor near the middle of the first station area of a type.
/proc/light_spot(area_type)
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

/// A floor beside a working lamp in an area of a type: maintenance is mostly dark, its middle tells nothing.
/proc/light_lamp_spot(area_type)
	for(var/obj/machinery/light/L in world)
		if(!L.on || !is_station_level(L.z) || !istype(get_area(L), area_type))
			continue
		var/lamps = 0
		for(var/obj/machinery/light/near in range(5, L))
			if(near.on)
				lamps++
		if(lamps < 2)
			continue
		for(var/turf/open/floor/T in range(2, L))
			if(!T.density && !(locate(/obj/structure) in T) && !(locate(/obj/machinery) in T) && istype(T.loc, area_type))
				return T

/// Every lamp plain white at full strength (how it was), or as its area has it.
/proc/light_mood(on)
	var/changed = 0
	for(var/obj/machinery/light/L in world)
		var/area/A = get_area(L)
		if(!A || !A.lamp_colour && A.lamp_power == 1)
			continue
		var/colour = on ? A.lamp_colour : "#FFFFFF"
		var/power = initial(L.bulb_power) * (on ? A.lamp_power : 1)
		if(L.bulb_colour == colour && L.bulb_power == power)
			continue
		if(L.bulb_colour != "#FFFFFF" && L.bulb_colour != A.lamp_colour)
			continue //a colour of its own
		L.bulb_colour = colour || "#FFFFFF"
		L.bulb_power = power
		L.update(0)
		changed++
		CHECK_TICK
	return changed

/proc/light_quality(mob/M, quality)
	M.client.prefs.set_graphics_quality(quality)
	M.hud_used.plane_masters_update()
	var/obj/screen/plane_master/lighting/PM = M.hud_used.plane_masters["[LIGHTING_PLANE]"]
	return length(PM.filters)

/proc/light_shots_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 4 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1
	kc_log("hwmode [winget(C, null, "hwmode")], theme [SSparallax.theme.name], [length(GLOB.worn_lights)] worn tubes, [length(GLOB.light_glows)] kinds of pool made so far")

	var/list/rooms = list(
		"bar" = /area/crew_quarters/bar,
		"medbay" = /area/medical/medbay/central,
		"engineering" = /area/engine/engineering,
		"maintenance" = /area/maintenance,
		"hallway" = /area/hallway/primary/central,
		"bridge" = /area/bridge)
	var/list/spots = list()
	for(var/room in rooms)
		var/turf/T = room == "maintenance" ? light_lamp_spot(rooms[room]) : light_spot(rooms[room])
		if(T)
			spots[room] = T
			kc_log("[room]: ([T.x],[T.y]) in [get_area(T)], lamp colour [T.loc:lamp_colour], power [T.loc:lamp_power]")
		else
			kc_log("[room]: no spot found")

	var/mob/living/carbon/human/H = new(spots[spots[1]])
	H.mind_initialize()
	H.equipOutfit(/datum/outfit/job/assistant)
	H.status_flags |= GODMODE
	H.ckey = C.ckey
	sleep(2 SECONDS)
	H.hud_used.show_hud(HUD_STYLE_NOHUD)

	// 1: how it was
	kc_log("mood off: [light_mood(FALSE)] lamps changed; lighting filters on Low: [light_quality(H, GRAPHICS_QUALITY_LOW)]")
	sleep(6 SECONDS)
	for(var/room in spots)
		H.forceMove(spots[room])
		sleep(12)
		light_shot("light_[room]_1_before")
	// 2 and 3: the rooms' own lamps, then the finish
	kc_log("mood on: [light_mood(TRUE)] lamps changed")
	sleep(6 SECONDS)
	for(var/room in spots)
		H.forceMove(spots[room])
		light_quality(H, GRAPHICS_QUALITY_LOW)
		sleep(12)
		light_shot("light_[room]_2_mood")
		var/count = light_quality(H, GRAPHICS_QUALITY_HIGH)
		sleep(5)
		light_shot("light_[room]_3_finish")
		if(room == spots[1])
			kc_log("lighting filters on High: [count]")

	// A tripped fire alarm: its red light pulses
	var/obj/machinery/firealarm/alarm
	for(var/obj/machinery/firealarm/F in range(12, spots["hallway"]))
		alarm = F
		break
	if(alarm)
		H.forceMove(get_step(alarm, alarm.dir) || get_turf(alarm))
		alarm.alarm()
		sleep(20)
		kc_log("fire alarm at ([alarm.x],[alarm.y]): light power [alarm.light_power], [length(alarm.vis_contents)] in vis_contents")
		light_shot("light_alarm_a")
		sleep(3)
		light_shot("light_alarm_b")
		alarm.reset()
		sleep(10)
		kc_log("after reset: [length(alarm.vis_contents)] in vis_contents")

	// The supermatter
	var/obj/machinery/power/supermatter_crystal/crystal = locate() in GLOB.machines
	if(crystal)
		var/turf/by = locate(crystal.x, crystal.y - 3, crystal.z)
		H.forceMove(by)
		sleep(15)
		kc_log("supermatter at ([crystal.x],[crystal.y]): [length(crystal.vis_contents)] in vis_contents")
		light_shot("light_supermatter_a")
		sleep(8)
		light_shot("light_supermatter_b")

	// A plasma fire in maintenance
	var/turf/open/fire_at = spots["maintenance"]
	if(fire_at)
		H.forceMove(fire_at)
		sleep(10)
		light_shot("light_fire_0_none")
		for(var/turf/open/T in range(1, fire_at))
			T.atmos_spawn_air("plasma=60;o2=120;TEMP=900")
		sleep(25)
		var/fires = 0
		var/pools = 0
		for(var/obj/effect/hotspot/hot in range(7, fire_at))
			fires++
			if(length(hot.vis_contents))
				pools++
		kc_log("fire: [fires] hotspots in view, [pools] carrying a pool of light")
		light_shot("light_fire_a")
		sleep(2)
		light_shot("light_fire_b")

	// A worn tube sputters, and is no nearer burning out for it
	if(length(GLOB.worn_lights))
		var/lit = 0
		var/list/counts = list()
		for(var/obj/machinery/light/L as anything in GLOB.worn_lights)
			counts[L] = L.switchcount
			if(L.on && L.status == LIGHT_OK)
				lit++
		for(var/i in 1 to 30) //each call picks one tube at random
			sputter_worn_light()
		sleep(3)
		var/sputtering = 0
		for(var/obj/machinery/light/L as anything in GLOB.worn_lights)
			if(L.flickering)
				sputtering++
		sleep(12 SECONDS) //a sputter is at most 8 switches of up to 1.5 seconds
		var/still = 0
		var/counted = 0
		for(var/obj/machinery/light/L as anything in GLOB.worn_lights)
			if(L.flickering)
				still++
			if(L.switchcount != counts[L])
				counted++
		kc_log("worn tubes: [length(GLOB.worn_lights)], [lit] lit; [sputtering] sputtering after 30 calls, [still] still at it 12 seconds on, [counted] with a changed switch count (should be 0)")

	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
