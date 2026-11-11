// Station looks with a real admin client (hippiestation/code/modules/station_looks/): a hall by day and on the Night shift,
// the department Tired wiring tripped, and the Station Looks window with a look pressed on the page. Not part of the game:
//   HARNESS=station_looks_shots.dm SENDER=shot.ps1 tools/keybind_check/run.sh looks
// Results in data/keycheck_looks.txt, pictures in data/previews/looks_game_*.png and popup_station_looks_*.png.

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
			looks_shots_run(src)

/proc/ls_check(name, ok, detail = "")
	kc_log("[ok ? "PASS" : "FAIL"] [name][detail ? " ([detail])" : ""]")

/proc/ls_shot(name, title)
	fdel("data/keycheck_shot_title")
	if(title)
		text2file(title, "data/keycheck_shot_title")
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/proc/ls_ui(mob/user, datum/src_object)
	var/deadline = world.time + 15 SECONDS
	while(world.time < deadline)
		for(var/datum/tgui/open as anything in user.open_uis)
			if(open.src_object == src_object && open.initialized)
				return open
		sleep(2)

/// Presses the first button on the page whose text starts with this
/proc/ls_click(client/C, datum/tgui/ui, text)
	var/js = "var t=[json_encode(text)];var b=Array.prototype.slice.call(document.querySelectorAll('.Button')).filter(function(e){return e.textContent.trim().indexOf(t)===0;})\[0\];if(b){b.click();}"
	C << output(url_encode(js), "[ui.window_id].browser:eval")
	sleep(10)

/// A clear floor in an area of this type, near its middle
/proc/ls_spot(area_type)
	var/area/A = GLOB.areas_by_type[area_type]
	var/list/floors = list()
	for(var/turf/open/floor/F in A)
		if(!is_blocked_turf(F, TRUE))
			floors += F
	if(length(floors))
		return floors[round(length(floors) / 2) + 1]

/proc/looks_shots_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1
	GLOB.master_mode = "extended"
	CONFIG_SET(number/bot_crew_target, 0)
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	var/datum/controller/subsystem/station_looks/S = SSstation_looks
	kc_log("rolled: [S.summary()]")
	// From a plain day: whatever extras rolled come off
	S.force("day")
	var/list/extras = S.picked[LOOK_SLOT_EXTRA]
	for(var/id in extras.Copy())
		S.force(id)
	sleep(5 SECONDS)

	var/turf/hall = ls_spot(/area/hallway/primary/central) || ls_spot(/area/hallway/primary/fore)
	var/mob/living/carbon/human/H = new(hall)
	H.mind_initialize()
	H.fully_replace_character_name(null, "Alex Admin")
	H.equipOutfit(/datum/outfit/job/assistant)
	H.ckey = C.ckey
	sleep(3 SECONDS)
	if(!C.holder)
		var/datum/admins/A = new(new /datum/admin_rank("!localhost!", R_EVERYTHING, R_DBRANKS, R_EVERYTHING), C.ckey, 1, 1)
		A.associate(C)
	sleep(2 SECONDS)
	usr = H
	kc_log("standing at [hall.x],[hall.y] in [get_area(hall)]")
	ls_shot("looks_game_day_hall")

	S.force("night")
	sleep(6 SECONDS)
	var/night_lamps = 0
	for(var/obj/machinery/light/L in view(7, H))
		night_lamps += L.nightshift_enabled
	ls_check("night: lamps in view on night lighting", night_lamps, "[night_lamps]")
	ls_shot("looks_game_night_hall")
	S.force("day")
	sleep(6 SECONDS)

	S.force("tired_wiring")
	sleep(8 SECONDS)
	var/datum/station_look/tired_wiring/wiring = S.looks["tired_wiring"]
	var/static/list/dept_rooms = list("Science" = /area/science/research, "Cargo" = /area/quartermaster/office, "Medbay" = /area/medical/medbay,
		"Engineering" = /area/engine/engineering, "Service" = /area/crew_quarters/bar)
	var/turf/dept = ls_spot(dept_rooms[wiring.department])
	kc_log("tripped: [wiring.department], standing at [dept?.x],[dept?.y]")
	if(dept)
		H.forceMove(dept)
		sleep(4 SECONDS)
		ls_shot("looks_game_tripped")
	// A humming lamp: stand under it and hear it
	var/obj/machinery/light/buzzer = length(GLOB.buzzing_lights) ? GLOB.buzzing_lights[1] : null
	ls_check("a lamp hums", buzzer)
	if(buzzer)
		H.forceMove(get_step(buzzer, turn(buzzer.dir, 180)) || get_turf(buzzer))
		sleep(4 SECONDS)
		ls_shot("looks_game_humming")

	C.cmd_admin_station_looks()
	var/datum/tgui/ui = ls_ui(H, GLOB.station_looks_window)
	ls_check("window opened", ui)
	if(ui)
		sleep(2 SECONDS)
		ls_shot("popup_station_looks_open", "420x600")
		ls_click(C, ui, "Morning shift")
		sleep(3 SECONDS)
		ls_check("pressing Morning shift forces it", "morning" in S.picked[LOOK_SLOT_SHIFT], english_list(S.picked[LOOK_SLOT_SHIFT]))
		ls_shot("popup_station_looks_morning", "420x600")
	ls_finish(C)

/proc/ls_finish(client/C)
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
