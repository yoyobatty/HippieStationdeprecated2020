// Why a test client's map is drawn small in the bottom left of its pane: logs the map's drawn size (view-size) against its pane
// size, compares it with parallax off, and checks auto fit, the square view option, and saved manual settings.
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
	kc_log("  split [winget(C, "mainwindow.split", "size")], splitter [winget(C, "mainwindow.split", "splitter")], pane [winget(C, "mapwindow", "size")], sizes [winget(C, "mainwindow.split;mapwindow", "size")], auto [C.prefs.auto_fit_viewport]")

/// Names the screen objects that make BYOND draw the map bigger than the view (an extra row or column of black that zoom-to-fit
/// and Auto Fit then size for): takes each off the screen in turn and reads the map's drawn size without it
/proc/probe_map_growers(client/C, label)
	var/list/view_size = getviewsize(C.view)
	var/base = winget(C, "mapwindow.map", "view-size")
	kc_log("[label]: drawn [base] for a [view_size[1]]x[view_size[2]] view, [length(C.screen)] screen objects")
	var/found = 0
	for(var/atom/movable/A as anything in C.screen.Copy())
		C.screen -= A
		sleep(2)
		var/without = winget(C, "mapwindow.map", "view-size")
		for(var/retry in 1 to 3) // the client can answer 0x0 or nothing while it's busy (the lobby loading): ask again
			if(without && without != "0x0")
				break
			sleep(5)
			without = winget(C, "mapwindow.map", "view-size")
		C.screen += A
		sleep(2)
		if(!without || without == "0x0")
			kc_log("  couldn't read the drawn size without [A.type] '[A.name]'")
		else if(without != base)
			found++
			kc_log("  grows the map: [A.type] '[A.name]' loc '[A.screen_loc]' icon '[A.icon]' '[A.icon_state]' maptext [A.maptext_width]x[A.maptext_height] at [A.maptext_x],[A.maptext_y], transform [A.transform?.a],[A.transform?.e]: drawn [without] without it")
	kc_log("[found ? "FAIL" : "PASS"] [label]: [found] screen object(s) grow the map")

/proc/probe_side_bars(client/C, label)
	var/pane_width = text2num(splittext(winget(C, "mapwindow.map", "size"), "x")[1])
	var/drawn_width = text2num(splittext(winget(C, "mapwindow.map", "view-size"), "x")[1])
	var/fits = pane_width && drawn_width && abs(pane_width - drawn_width) <= 2
	kc_log("[fits ? "PASS" : "FAIL"] [label]: pane width [pane_width], drawn width [drawn_width]")

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
	C.fps = 60
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1
	probe_state(C, "lobby")
	probe_map_growers(C, "lobby")
	// What the lobby's sides show without the title's blurred backdrop (hippiestation/code/controllers/subsystem/title.dm)
	var/obj/effect/title_backdrop/backdrop = SStitle.splash_turf?.backdrop
	if(backdrop)
		backdrop.invisibility = INVISIBILITY_ABSTRACT
		sleep(5)
		probe_shot("mapfit_lobby_no_backdrop")
		backdrop.invisibility = 0
		sleep(5)
	probe_shot("mapfit_auto_0_lobby")
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(3 SECONDS)
	var/mob/living/carbon/human/H = new(locate(world.maxx / 2, world.maxy / 2, SSmapping.levels_by_trait(ZTRAIT_STATION)[1]))
	H.status_flags |= GODMODE
	H.ckey = C.ckey
	sleep(3 SECONDS)
	probe_state(C, "in the round")
	probe_side_bars(C, "default auto fit")
	probe_map_growers(C, "in the round")
	kc_log("screen objects ([length(C.screen)]) that could move or shrink the picture:")
	probe_screen(C)
	kc_log("key [C.ckey], parallax pref [C.prefs.parallax], graphics [C.prefs.graphics_quality()]")
	probe_shot("mapfit_auto_1_as_is")
	// The sky off: if the map fills its pane now, a sky screen object reaching past the view grew the map's area
	C.prefs.parallax = PARALLAX_DISABLE
	H.hud_used.update_parallax_pref(H)
	sleep(1 SECONDS)
	kc_log("sky off:")
	probe_screen(C)
	probe_state(C, "parallax off")
	probe_shot("mapfit_auto_2_sky_off")
	C.prefs.parallax = PARALLAX_HIGH
	H.hud_used.update_parallax_pref(H)
	sleep(1 SECONDS)
	probe_state(C, "parallax on")
	probe_shot("mapfit_auto_3_sky_back")
	var/widescreen = C.prefs.widescreenpref
	var/auto_fit = C.prefs.auto_fit_viewport
	C.prefs.widescreenpref = FALSE
	C.change_view(CONFIG_GET(string/default_view))
	sleep(2 SECONDS)
	probe_state(C, "square preference")
	probe_side_bars(C, "square viewport")
	probe_shot("mapfit_auto_4_square")
	C.prefs.widescreenpref = widescreen
	C.change_view(CONFIG_GET(string/default_view))
	sleep(2 SECONDS)

	var/original_window = winget(C, "mainwindow", "size;is-maximized;is-fullscreen")
	var/original_zoom = winget(C, "mapwindow.map", "zoom;zoom-mode;letterbox")
	var/original_splitter = winget(C, "mainwindow.split", "splitter")
	C.set_auto_fit_viewport(FALSE)
	winset(C, "mainwindow.split", "splitter=57")
	C.set_auto_fit_viewport(TRUE)
	sleep(2 SECONDS)
	winset(C, "mainwindow", "is-fullscreen=false;is-maximized=false;size=1100x820")
	sleep(1 SECONDS)
	winset(C, null, "command=viewport-resized") // winset() itself does not fire on-size
	sleep(2 SECONDS)
	probe_state(C, "compact window")
	probe_side_bars(C, "compact window")
	probe_shot("mapfit_auto_5_compact")

	winset(C, "mapwindow.map", "zoom=1;letterbox=false;zoom-mode=blur")
	var/fixed_settings = winget(C, "mapwindow.map", "zoom;zoom-mode;letterbox")
	C.fit_viewport()
	var/after_settings = winget(C, "mapwindow.map", "zoom;zoom-mode;letterbox")
	kc_log("[fixed_settings == after_settings ? "PASS" : "FAIL"] fixed zoom, scaling and letterbox kept: [after_settings]")
	C.set_auto_fit_viewport(FALSE)
	sleep(1 SECONDS)
	var/restored_splitter = text2num(winget(C, "mainwindow.split", "splitter"))
	kc_log("[abs(restored_splitter - 57) < 0.01 ? "PASS" : "FAIL"] remembered manual divider: [restored_splitter]")
	C.prefs.auto_fit_viewport = auto_fit
	winset(C, "mainwindow", original_window)
	winset(C, "mapwindow.map", original_zoom)
	winset(C, "mainwindow.split", "splitter=[original_splitter]")
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
