// Grief undo with a real admin client (hippiestation/code/modules/admin/grief_undo.dm): the bar griefed, the window opened on it,
// the map's preview and the window pictured, Apply and Undo pressed on the page the way an admin presses them. Not part of the game:
//   HARNESS=grief_undo_shots.dm SENDER=shot.ps1 tools/keybind_check/run.sh griefundo
// Results in data/keycheck_griefundo.txt, pictures in data/previews/griefundo_*.png and popup_griefundo_*.png.

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
			grief_shots_run(src)

/proc/gs_check(name, ok, detail = "")
	kc_log("[ok ? "PASS" : "FAIL"] [name][detail ? " ([detail])" : ""]")

/proc/gs_shot(name, title)
	fdel("data/keycheck_shot_title")
	if(title)
		text2file(title, "data/keycheck_shot_title")
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/proc/gs_ui(mob/user, datum/src_object)
	var/deadline = world.time + 15 SECONDS
	while(world.time < deadline)
		for(var/datum/tgui/open as anything in user.open_uis)
			if(open.src_object == src_object && open.initialized)
				return open
		sleep(2)

/// Presses the first button on the page whose text starts with this
/proc/gs_click(client/C, datum/tgui/ui, text)
	var/js = "var t=[json_encode(text)];var b=Array.prototype.slice.call(document.querySelectorAll('.Button')).filter(function(e){return e.textContent.trim().indexOf(t)===0;})\[0\];if(b){b.click();}"
	C << output(url_encode(js), "[ui.window_id].browser:eval")
	sleep(10)

/proc/grief_shots_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(12 SECONDS) // what's left below counts as made this round

	var/area/bar = GLOB.areas_by_type[/area/crew_quarters/bar]
	var/list/floors = list()
	for(var/turf/open/floor/F in bar)
		if(!is_blocked_turf(F, TRUE))
			floors += F
	var/turf/middle = floors[round(floors.len / 2) + 1]
	var/mob/living/carbon/human/H = new(middle)
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

	// the grief: the bar's windows smashed out, a door torn off, a wall taken down, plasma let in, a canister and a girder left
	var/windows = 0
	for(var/turf/T in range(9, middle))
		if(windows >= 3)
			break
		var/obj/structure/window/W = locate() in T
		if(W?.fulltile && (locate(/obj/structure/grille) in T))
			for(var/obj/structure/window/each in T)
				qdel(each)
			for(var/obj/structure/grille/G in T)
				qdel(G)
			windows++
	var/obj/machinery/door/airlock/door
	for(var/obj/machinery/door/airlock/A in range(9, middle))
		door = A
		break
	var/turf/door_turf = door?.loc
	qdel(door)
	var/turf/wall
	for(var/turf/closed/wall/W in range(6, middle))
		if(get_area(W) == bar || get_area(get_step(W, NORTH)) == bar || get_area(get_step(W, SOUTH)) == bar)
			wall = W.ChangeTurf(/turf/open/floor/plating)
			break
	var/turf/open/gas = floors[max(1, round(floors.len / 3))]
	gas.atmos_spawn_air("plasma=60;TEMP=293")
	var/turf/junk = floors[max(1, round(floors.len * 2 / 3))]
	new /obj/machinery/portable_atmospherics/canister/toxins(junk)
	new /obj/structure/girder(junk)
	kc_log("grief: [windows] windows, door [!!door_turf], wall [!!wall] at [wall?.x],[wall?.y], door at [door_turf?.x],[door_turf?.y], junk at [junk.x],[junk.y]")
	// stand where the grief shows: by the door, or the wall
	var/turf/stand = door_turf || wall
	if(stand)
		for(var/turf/open/T in range(2, stand))
			if(!is_blocked_turf(T, TRUE))
				H.forceMove(T)
				break
	sleep(2 SECONDS)

	gs_shot("griefundo_map_griefed")
	C.open_grief_undo("area", bar)
	var/datum/grief_undo/G = C.grief_undo
	var/datum/tgui/ui = gs_ui(H, G)
	gs_check("window opened", ui)
	if(!ui)
		gs_finish(C)
		return
	sleep(2 SECONDS)
	var/list/data = G.ui_data(H)
	gs_check("scan lists the grief", length(data["rows"]) >= windows + 2 && length(data["adds"]) >= 2, "[length(data["rows"])] rows, [length(data["adds"])] added, [data["source"]]")
	gs_shot("popup_griefundo_window", "980x700")
	gs_shot("griefundo_map_preview")

	// a tile skipped by a click on the map
	if(wall)
		var/datum/grief_tile/tile = G.tiles["[wall.x],[wall.y],[wall.z]"]
		G.InterceptClickOn(H, "left=1", wall)
		sleep(1 SECONDS)
		gs_check("map click skips a tile", tile && !tile.ticked)
		gs_shot("popup_griefundo_skipped", "980x700")
		G.InterceptClickOn(H, "left=1", wall)
		sleep(1 SECONDS)

	gs_click(C, ui, "Apply")
	sleep(3 SECONDS)
	gs_check("Apply pressed on the page", findtext(G.message, "Applied"), G.message)
	var/back = 0
	for(var/turf/T in range(9, middle))
		if(locate(/obj/structure/window) in T)
			back++
	gs_check("windows back", back >= windows, "[back] window tiles in range")
	gs_check("door back", door_turf && (locate(/obj/machinery/door/airlock) in door_turf))
	gs_shot("popup_griefundo_applied", "980x700")
	gs_shot("griefundo_map_applied")

	gs_click(C, ui, "Undo last")
	sleep(3 SECONDS)
	gs_check("Undo pressed on the page", findtext(G.message, "Undone"), G.message)
	gs_check("door gone again", door_turf && !(locate(/obj/machinery/door/airlock) in door_turf))
	gs_shot("popup_griefundo_undone", "980x700")

	// a player scan typed into the page
	var/list/entry = new /list(RL_LEN)
	entry[RL_ID] = ++GLOB.round_log_total
	entry[RL_TIME] = world.time
	entry[RL_CAT] = "Attack"
	entry[RL_TEXT] = "greytider smashed a window"
	entry[RL_CKEY] = "greytider"
	entry[RL_X] = middle.x
	entry[RL_Y] = middle.y
	entry[RL_Z] = middle.z
	GLOB.round_log += list(entry)
	G.scan_player("greytider", 15)
	sleep(2 SECONDS)
	gs_check("player scan", findtext(G.source, "greytider") && length(G.tiles), "[G.source]")
	gs_shot("popup_griefundo_player", "980x700")
	gs_finish(C)

/proc/gs_finish(client/C)
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
