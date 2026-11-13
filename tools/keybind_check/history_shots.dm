// Station looks' histories with a real client (hippiestation/code/modules/station_looks/looks_history.dm): the history named in
// data/looks_shots_which forced in the lobby, the round started on a plain day shift, and pictures where it shows best. Not part
// of the game:
//   echo overgrown > data/looks_shots_which; HARNESS=history_shots.dm SENDER=shot.ps1 tools/keybind_check/run.sh history
// Results in data/keycheck_history.txt, pictures in data/previews/history_<id>_<n>.png.

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
			history_shots_run(src)

/proc/hs_shot(name)
	fdel("data/keycheck_shot_title")
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/proc/history_shots_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1
	var/id = trim(file2text("data/looks_shots_which"))
	var/datum/controller/subsystem/station_looks/S = SSstation_looks
	var/datum/station_look/history/H = S.looks[id]
	kc_log("history: [id] ([H?.name])")
	if(!istype(H))
		kc_log("FAIL no history called [id]")
		hs_finish(C)
		return
	// A plain day shift with nothing else on, and the history
	S.force("day")
	S.picked[LOOK_SLOT_EXTRA] = list()
	S.force(id)
	GLOB.master_mode = "extended"
	CONFIG_SET(number/bot_crew_target, 0)
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(15 SECONDS) //it goes on as the round starts, a floor at a time
	kc_log("[H.active ? "PASS" : "FAIL"] [H.name] on: [S.notes_text()]")
	var/list/turf/spots = H.showcase.Copy()
	for(var/area_type in list(/area/hallway/primary/central, /area/crew_quarters/bar, /area/medical/medbay))
		if(length(spots) >= 3)
			break
		var/turf/T = station_look_middle(GLOB.areas_by_type[area_type])
		if(T)
			spots += T
	var/mob/living/carbon/human/body = new(spots[1])
	body.mind_initialize()
	body.fully_replace_character_name(null, "Alex Admin")
	body.equipOutfit(/datum/outfit/job/assistant)
	body.ckey = C.ckey
	sleep(3 SECONDS)
	var/n = 0
	for(var/turf/T as anything in spots)
		if(n >= 4)
			break
		n++
		body.forceMove(T)
		sleep(4 SECONDS)
		kc_log("picture [n] at [T.x],[T.y] in [get_area(T)]")
		hs_shot("history_[id]_[n]")
	hs_finish(C)

/proc/hs_finish(client/C)
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
