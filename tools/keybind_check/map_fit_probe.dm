// Why a test client's map is drawn small in the bottom left of its pane: logs the map's drawn size (view-size) against its pane
// size, then tries ways to make DreamSeeker lay the map out again, with a picture after each.
// Not part of the game: MAP=testbench HARNESS=map_fit_probe.dm SENDER=shot.ps1 tools/keybind_check/run.sh mapfit
// Pictures in data/previews/mapfit_*.png, log in data/keycheck.txt.

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
			map_fit_probe_run(src)

/proc/probe_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)

/proc/probe_state(client/C, label)
	kc_log("[label]: main [winget(C, "mainwindow", "size")] min [winget(C, "mainwindow", "is-minimized")] max [winget(C, "mainwindow", "is-maximized")]; map pane [winget(C, "mapwindow.map", "size")], drawn [winget(C, "mapwindow.map", "view-size")], zoom [winget(C, "mapwindow.map", "zoom")], icon-size [winget(C, "mapwindow.map", "icon-size")], letterbox [winget(C, "mapwindow.map", "letterbox")], view [C.view]")

/// Every screen object that could shrink or move the whole picture: a transform, a screen_loc other than the plain ones, a
/// render_source relay
/proc/probe_screen(client/C)
	var/list/identity = list(1, 0, 0, 0, 1, 0)
	for(var/obj/screen/S in C.screen)
		var/matrix/M = S.transform
		var/list/parts = list(M.a, M.b, M.c, M.d, M.e, M.f)
		var/plane_master = istype(S, /obj/screen/plane_master)
		if(parts ~= identity && !S.render_source && (S.screen_loc == "CENTER" || !plane_master))
			continue
		kc_log("  [S.type] '[S.name]' plane [S.plane] loc '[S.screen_loc]' transform [jointext(parts, ",")] source '[S.render_source]' target '[S.render_target]' filters [length(S.filters)]")

/proc/map_fit_probe_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(3 SECONDS)
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1
	var/mob/living/carbon/human/H = new(locate(world.maxx / 2, world.maxy / 2, SSmapping.levels_by_trait(ZTRAIT_STATION)[1]))
	H.status_flags |= GODMODE
	H.ckey = C.ckey
	sleep(3 SECONDS)
	probe_state(C, "in the round")
	kc_log("screen objects ([length(C.screen)]) that could move or shrink the picture:")
	probe_screen(C)
	kc_log("key [C.ckey], parallax pref [C.prefs.parallax], graphics [C.prefs.graphics_quality()]")
	probe_shot("mapfit7_0_as_is")
	// The sky off: if the map fills its pane now, a sky screen object reaching past the view grew the map's area
	C.prefs.parallax = PARALLAX_DISABLE
	H.hud_used.update_parallax_pref(H)
	sleep(1 SECONDS)
	kc_log("sky off:")
	probe_screen(C)
	probe_shot("mapfit7_1_sky_off")
	C.prefs.parallax = PARALLAX_HIGH
	H.hud_used.update_parallax_pref(H)
	sleep(1 SECONDS)
	probe_shot("mapfit7_2_sky_back")
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
