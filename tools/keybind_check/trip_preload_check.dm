// Drinking Grape Blast mustn't move the view: trip_preload() once grew the screen to fit the art and zoomed the game right out.
// Not part of the game: HARNESS=trip_preload_check.dm SENDER=shot.ps1 MAP=testbench tools/keybind_check/run.sh trippreload
// Pictures data/previews/preload_*.png: before, 3 s after the drink (art loading), and the trip 25 s in.

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
			trip_preload_check_run(src)

/proc/preload_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/proc/trip_preload_check_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 4 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	text2file("go", "data/keycheck_sendkeys")
	var/turf/spot
	for(var/turf/open/floor/F in world)
		if(is_station_level(F.z) && F.get_lumcount() > 0.5 && !(locate(/obj/structure) in F))
			spot = F
			break
	var/mob/living/carbon/human/H = new(spot)
	H.mind_initialize()
	H.equipOutfit(/datum/outfit/job/assistant)
	H.status_flags |= GODMODE
	H.ckey = C.ckey
	sleep(4 SECONDS)
	preload_shot("preload_0_before")
	H.reagents.add_reagent(/datum/reagent/drug/grape_blast, 20)
	sleep(3 SECONDS)
	kc_log("3 s after the drink: images [length(C.images)], screen [length(C.screen)], view [C.view]")
	preload_shot("preload_1_loading")
	for(var/i in 1 to 12)
		sleep(2 SECONDS)
		H.forceMove(spot)
	preload_shot("preload_2_tripping")
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
