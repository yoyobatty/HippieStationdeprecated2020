// Lava's glow with a real client: the old whole-tile glow ("before") against each smoothed tile's own molten-part mask ("after"),
// in the same boot, by the mining station (where the user saw it, round-16.29.52) and at the edge of a lava field.
// Not part of the game: HARNESS=lava_shots.dm SENDER=shot.ps1 tools/keybind_check/run.sh lava
// Pictures in data/previews/lava_*.png.

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
			lava_shots_run(src)

/proc/lava_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/// The old way on every lava tile round about (TRUE), or the new (FALSE)
/proc/lava_glow_old_way(turf/T, old)
	var/old_glow = emissive_glow('icons/effects/alphacolors.dmi', "white", color = LIGHT_COLOR_LAVA)
	var/n = 0
	for(var/turf/open/lava/L in range(12, T))
		n++
		if(L.lava_glow)
			L.cut_overlay(L.lava_glow)
		if(old)
			L.lava_glow = old_glow
			L.add_overlay(old_glow)
		else
			L.lava_glow = null
			L.update_lava_glow()
	return n

/proc/lava_field_edge(z)
	for(var/turf/open/lava/smooth/L in block(locate(60, 60, z), locate(world.maxx - 60, world.maxy - 60, z)))
		var/rock = 0
		for(var/turf/N in orange(1, L))
			if(!istype(N, /turf/open/lava))
				rock++
		if(rock >= 3)
			for(var/turf/open/N in orange(1, L))
				if(!istype(N, /turf/open/lava) && !N.density)
					return N
	return null

/proc/lava_shots_spot(mob/living/carbon/human/H, turf/spot, name)
	if(!spot)
		kc_log("[name]: no spot")
		return
	H.forceMove(spot)
	sleep(3 SECONDS)
	var/n = lava_glow_old_way(spot, TRUE)
	kc_log("[name] at [spot.x],[spot.y],[spot.z]: [n] lava tiles")
	sleep(2 SECONDS)
	lava_shot("lava_[name]_1_before")
	lava_glow_old_way(spot, FALSE)
	sleep(2 SECONDS)
	lava_shot("lava_[name]_2_after")

/proc/lava_shots_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1
	var/z = SSmapping.levels_by_trait(ZTRAIT_MINING)[1]
	var/mob/living/carbon/human/H = new(locate(45, 27, z))
	H.mind_initialize()
	H.equipOutfit(/datum/outfit/job/miner)
	H.status_flags |= GODMODE
	H.ckey = C.ckey
	sleep(3 SECONDS)
	kc_log("hwmode [winget(C, null, "hwmode")]")
	lava_shots_spot(H, locate(45, 27, z), "mining_station")
	lava_shots_spot(H, lava_field_edge(z), "field_edge")
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
