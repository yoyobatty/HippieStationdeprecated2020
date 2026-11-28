// Where a new tgui window opens: centred on the map pane (the game view), not on the whole game window with the stat panel on its
// right. Checks a pooled window, a tgui_alert() and a tgui_input_list(), a window without fancy frills, one opened the old way (no
// pool), and the game window restored instead of maximized; that a window the player moved stays put when its UI is shown again
// (reinitialize), and that a pooled window is centred again for its next UI. Where the windows are comes from Windows itself
// (shot.ps1's keycheck_rects: the map's own window and the popup's), not from BYOND's numbers. Auto Fit is on throughout.
// Not part of the game: HARNESS=tgui_centre_check.dm SENDER=shot.ps1 MAP=testbench tools/keybind_check/run.sh centre
// Pictures in data/previews/desk_centre_*.png (the game window with its popups on it), log in data/keycheck_<label>.txt.

GLOBAL_VAR_INIT(keycheck_running, FALSE)
GLOBAL_VAR_INIT(tcc_passed, 0)
GLOBAL_VAR_INIT(tcc_failed, 0)
GLOBAL_VAR(tcc_answer)

/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

/proc/kc_log(text)
	text2file(text, "data/keycheck.txt")

/proc/tcc_check(name, condition, detail)
	if(condition)
		GLOB.tcc_passed++
	else
		GLOB.tcc_failed++
	kc_log("[condition ? "PASS" : "FAIL"] [name][detail ? " - [detail]" : ""]")

/client/New()
	. = ..()
	if(. && !GLOB.keycheck_running)
		GLOB.keycheck_running = TRUE
		spawn(10)
			tgui_centre_check_run(src)

/proc/tcc_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/// "name left top right bottom" lines from shot.ps1 for the popup of this size: list(name = list(l, t, r, b))
/proc/tcc_rects(popup_size)
	fdel("data/keycheck_rects_out")
	text2file(popup_size || "", "data/keycheck_rects")
	var/deadline = world.time + 10 SECONDS
	while(!fexists("data/keycheck_rects_out") && world.time < deadline)
		sleep(1)
	. = list()
	for(var/line in splittext(file2text("data/keycheck_rects_out"), "\n"))
		var/list/parts = splittext(trim(line), " ")
		if(length(parts) == 5)
			.[parts[1]] = list(text2num(parts[2]), text2num(parts[3]), text2num(parts[4]), text2num(parts[5]))
	fdel("data/keycheck_rects_out")

/// The popup's middle against the map's, from where Windows has them: list(ok, offset x, offset y, detail)
/proc/tcc_centred(datum/tgui/ui, slack = 2)
	var/list/rects = tcc_rects("[ui.width]x[ui.height]")
	var/list/map = rects["map"]
	var/list/popup = rects["popup"]
	if(!map || !popup)
		return list(FALSE, 0, 0, "no rects: [json_encode(rects)]")
	var/off_x = (popup[1] + popup[3]) / 2 - (map[1] + map[3]) / 2
	var/off_y = (popup[2] + popup[4]) / 2 - (map[2] + map[4]) / 2
	return list(abs(off_x) <= slack && abs(off_y) <= slack, off_x, off_y, "popup [popup[1]],[popup[2]]-[popup[3]],[popup[4]], map [map[1]],[map[2]]-[map[3]],[map[4]], off by [off_x],[off_y]")

/proc/tcc_geometry(client/C, label)
	kc_log("[label]: mainwindow [winget(C, "mainwindow", "is-maximized;pos;size;outer-pos;outer-size;inner-pos;inner-size;screen-pos;screen-size")]")
	kc_log("  map [winget(C, "mapwindow.map", "pos;size;view-size")], split [winget(C, "mainwindow.split", "size;splitter")], auto fit [C.prefs.auto_fit_viewport]")
	var/list/rects = tcc_rects()
	kc_log("  Windows: map [json_encode(rects["map"])], game window [json_encode(rects["main"])]")

/proc/tcc_open(mob/user, obj/machinery/M)
	M.stat = 0
	M.ui_interact(user)
	return SStgui.get_open_ui(user, M, "main")

/proc/tcc_pair(text) // "12,34" or "12x34" from winget
	var/list/parts = splittext(replacetext(text, "x", ","), ",")
	return list(text2num(parts[1]), text2num(parts[2]))

/// A UI opened, centred on the map, and its picture
/proc/tcc_window(name, datum/tgui/ui, slack = 2)
	tcc_check("[name]: open and shown", ui && winget(ui.user.client, ui.window_id, "is-visible") == "true", ui ? "[ui.window_id], [ui.pool_window ? "pooled" : "its own window"]" : "no UI")
	if(!ui)
		return
	var/list/centred = tcc_centred(ui, slack)
	tcc_check("[name]: centred on the map pane", centred[1], centred[4])
	tcc_shot("desk_centre_[name]")

/// Moved as a player would, then shown again with new data (SStgui.try_update_ui(force_open), reinitialize): it stays where it was put
/proc/tcc_moved_stays(name, mob/user, obj/machinery/M, datum/tgui/ui)
	var/client/C = user.client
	var/list/pos = tcc_pair(winget(C, ui.window_id, "pos"))
	var/moved = "[pos[1] - 260],[pos[2] + 140]"
	winset(C, ui.window_id, "pos=[moved]")
	sleep(5)
	SStgui.try_update_ui(user, M, "main", null, TRUE)
	sleep(20)
	var/now = winget(C, ui.window_id, "pos")
	tcc_check("[name]: moved, then shown again, stays where it was put", now == moved && winget(C, ui.window_id, "is-visible") == "true", "moved to [moved], now [now]")
	tcc_shot("desk_centre_[name]_moved")

/proc/tgui_centre_check_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	fdel("data/keycheck_rects")
	text2file("go", "data/keycheck_sendkeys") // starts shot.ps1
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(3 SECONDS)
	var/turf/home = get_turf(pick(SSjob.latejoin_trackers))
	var/mob/living/carbon/human/H = new(home)
	H.mind_initialize()
	H.equipOutfit(/datum/outfit/job/assistant)
	H.ckey = C.ckey
	sleep(3 SECONDS)
	try
		tcc_steps(C, H, home)
	catch(var/exception/e)
		tcc_check("ran to the end", FALSE, "[e] at [e.file]:[e.line]")
	kc_log("[GLOB.tcc_passed] passed, [GLOB.tcc_failed] failed")
	text2file("done", "data/keycheck_shots_done")
	kc_log("done")

/proc/tcc_steps(client/C, mob/living/carbon/human/H, turf/home)
	// maximized, Auto Fit on, as it's played
	C.prefs.auto_fit_viewport = TRUE
	winset(C, "mainwindow", "is-maximized=true")
	sleep(3 SECONDS) // Auto Fit waits a second after the window's new size
	C.fit_viewport()
	sleep(2 SECONDS)
	tcc_geometry(C, "maximized")
	var/list/rects = tcc_rects()
	var/list/map = rects["map"]
	var/list/inner = tcc_pair(winget(C, "mainwindow", "inner-pos"))
	var/list/outer = tcc_pair(winget(C, "mainwindow", "outer-pos"))
	var/list/map_size = tcc_pair(winget(C, "mapwindow.map", "size"))
	tcc_check("BYOND's numbers put the map where Windows has it (outer-pos + inner-pos, the map's size)", map && map[1] == outer[1] + inner[1] && map[2] == outer[2] + inner[2] && map[3] - map[1] == map_size[1] && map[4] - map[2] == map_size[2], "Windows [json_encode(map)], BYOND [outer[1] + inner[1]],[outer[2] + inner[2]] [map_size[1]]x[map_size[2]]")

	var/obj/machinery/space_heater/heater = new(home)
	heater.on = FALSE
	var/datum/tgui/ui = tcc_open(H, heater)
	sleep(10)
	tcc_window("heater", ui)
	if(ui)
		tcc_moved_stays("heater", H, heater, ui)
		ui.close()
	sleep(10)
	// the pooled window, kept for the next UI, comes back in the middle again
	ui = tcc_open(H, heater)
	sleep(10)
	tcc_window("heater_again", ui)
	ui?.close()
	sleep(5)

	// prompts
	GLOB.tcc_answer = null
	spawn(0)
		GLOB.tcc_answer = tgui_alert(H, "Centred on the map?", "Centre", list("Yes", "No"))
	sleep(10)
	var/datum/tgui/prompt
	for(var/datum/tgui/open as anything in H.open_uis)
		prompt = open
	tcc_window("alert", prompt)
	prompt?.close()
	sleep(5)
	spawn(0)
		GLOB.tcc_answer = tgui_input_list(H, "Which one?", "Centre", list("Alpha", "Beta", "Gamma", "Delta"))
	sleep(10)
	prompt = null
	for(var/datum/tgui/open as anything in H.open_uis)
		prompt = open
	tcc_window("input_list", prompt)
	prompt?.close()
	sleep(5)

	// without fancy frills: the OS title bar and borders (Windows' rect has invisible borders on three sides: a few pixels' slack)
	C.prefs.tgui_fancy = FALSE
	ui = tcc_open(H, heater)
	sleep(10)
	tcc_window("heater_nofrills", ui, 6)
	ui?.close()
	C.prefs.tgui_fancy = TRUE
	sleep(5)

	// the old way, its own window: centred once its page has loaded, and left where the player put it after that
	GLOB.tgui_pool_enabled = FALSE
	var/obj/machinery/power/smes/smes = new(get_step(home, EAST))
	ui = tcc_open(H, smes)
	sleep(25)
	tcc_window("smes_own_window", ui)
	if(ui)
		tcc_moved_stays("smes_own_window", H, smes, ui)
		ui.close()
	GLOB.tgui_pool_enabled = TRUE
	sleep(10)

	// the game window restored, smaller and off to one side: still the map's middle
	winset(C, "mainwindow", "is-maximized=false")
	sleep(5)
	winset(C, "mainwindow", "pos=180,90;size=1700x1050")
	sleep(3 SECONDS)
	C.fit_viewport()
	sleep(2 SECONDS)
	tcc_geometry(C, "restored")
	ui = tcc_open(H, heater)
	sleep(10)
	tcc_window("heater_restored", ui)
	ui?.close()
	winset(C, "mainwindow", "is-maximized=true")
	sleep(10)
