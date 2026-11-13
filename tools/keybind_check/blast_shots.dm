// Pictures of a realistic blast with a real client (hippiestation/code/modules/explosion_realism/): the flash and the dust, in a lit
// hallway and in dark maintenance, from just before to after the dust has settled.
// Not part of the game: HARNESS=blast_shots.dm SENDER=shot.ps1 SHOT_MINUTES=6 tools/keybind_check/run.sh blasts
// Pictures in data/previews/blast_*.png, notes in data/keycheck.txt.

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
			blast_shots_run(src)

/proc/blast_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)

/// A clear floor in the first station area of a type with clear floor `reach` tiles east of it
/proc/blast_shot_spot(area_type, reach)
	for(var/area/A in GLOB.sortedAreas)
		if(!istype(A, area_type))
			continue
		for(var/turf/open/floor/T in A)
			if(!is_station_level(T.z))
				continue
			var/clear = TRUE
			for(var/dx in 0 to reach + 2)
				var/turf/along = locate(T.x + dx, T.y, T.z)
				if(!along || along.density || !istype(along, /turf/open/floor))
					clear = FALSE
					break
			if(clear)
				return T

/proc/blast_shots_scene(mob/living/carbon/human/H, turf/spot, label, distance, list/size)
	H.forceMove(spot)
	sleep(3 SECONDS)
	var/turf/epicenter = locate(spot.x + distance, spot.y, spot.z)
	kc_log("[label]: viewer at [spot.x],[spot.y] in [get_area(spot)], blast ([size[1]], [size[2]], [size[3]]) [distance] tiles east")
	blast_shot("blast_[label]_0_before")
	explosion(epicenter, size[1], size[2], size[3], 0, adminlog = FALSE)
	sleep(1)
	kc_log("  flash: [length(GLOB.blast_flashes)] flashes, [GLOB.blast_dust_clouds] dust clouds")
	blast_shot("blast_[label]_1_flash")
	sleep(10)
	blast_shot("blast_[label]_2_dust")
	sleep(40)
	blast_shot("blast_[label]_3_dust_hanging")
	sleep(60)
	blast_shot("blast_[label]_4_settling")
	sleep(60)
	kc_log("  after: [GLOB.blast_dust_clouds] dust clouds left")
	blast_shot("blast_[label]_5_after")

/proc/blast_shots_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 4 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1
	var/turf/hall = blast_shot_spot(/area/hallway/primary, 6)
	var/turf/maint = blast_shot_spot(/area/maintenance, 6)
	if(!hall)
		kc_log("no open stretch of hallway found")
	else
		var/mob/living/carbon/human/H = new(hall)
		H.mind_initialize()
		H.equipOutfit(/datum/outfit/job/assistant)
		H.status_flags |= GODMODE
		H.move_resist = INFINITY
		H.ckey = C.ckey
		sleep(2 SECONDS)
		H.hud_used.show_hud(HUD_STYLE_NOHUD)
		C.prefs.set_graphics_quality(GRAPHICS_QUALITY_HIGH)
		H.hud_used.plane_masters_update()
		kc_log("hwmode [winget(C, null, "hwmode")]")
		if(fexists("data/blast_shots_flash")) //touch it for the flash timing check instead
			fdel("data/blast_shots_flash")
			blast_shots_flash(H, maint || hall)
		else if(fexists("data/blast_shots_black")) //touch it for the black-rectangle check instead
			fdel("data/blast_shots_black")
			blast_shots_black(H, hall, maint)
		else
			blast_shots_scene(H, hall, "hall", 5, list(0, 1, 3))
			if(maint)
				blast_shots_scene(H, maint, "maint", 6, list(1, 2, 4))
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)

/// Whatever goes black for a moment next to a blast: the flash on its own, then a blast with realism off, then one with it on
/proc/blast_shots_black(mob/living/carbon/human/H, turf/hall, turf/maint)
	H.forceMove(hall)
	sleep(3 SECONDS)
	var/turf/east = locate(hall.x + 4, hall.y, hall.z)
	blast_shot("blastblack_0_before")
	new /obj/effect/temp_visual/blast_flash(east, 6)
	sleep(1)
	blast_shot("blastblack_1_flash_alone")
	sleep(3 SECONDS)
	GLOB.explosion_realism = FALSE
	explosion(east, 0, 1, 3, 0, adminlog = FALSE)
	sleep(1)
	blast_shot("blastblack_2_blast_realism_off")
	sleep(1)
	blast_shot("blastblack_3_blast_realism_off_later")
	GLOB.explosion_realism = TRUE
	if(maint)
		H.forceMove(maint)
		sleep(3 SECONDS)
		explosion(locate(maint.x + 4, maint.y, maint.z), 0, 1, 3, 0, adminlog = FALSE)
		sleep(1)
		blast_shot("blastblack_4_blast_realism_on")
		sleep(1)
		blast_shot("blastblack_5_blast_realism_on_later")

/// The flash on its own in the dark, pictured as it fades
/proc/blast_shots_flash(mob/living/carbon/human/H, turf/spot)
	H.forceMove(spot)
	sleep(3 SECONDS)
	var/turf/east = locate(spot.x + 3, spot.y, spot.z)
	blast_shot("blastflash_0_before")
	var/start = world.time
	new /obj/effect/temp_visual/blast_flash(east, 6)
	sleep(1)
	kc_log("flash shot 1 at [world.time - start] ds")
	blast_shot("blastflash_1")
	sleep(1)
	kc_log("flash shot 2 at [world.time - start] ds")
	blast_shot("blastflash_2")
	sleep(1)
	kc_log("flash shot 3 at [world.time - start] ds")
	blast_shot("blastflash_3")
	sleep(3)
	kc_log("flash shot 4 at [world.time - start] ds")
	blast_shot("blastflash_4")
