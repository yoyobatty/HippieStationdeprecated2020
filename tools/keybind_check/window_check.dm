// The game window with a real client: the layout, the hover label, the Display panel, the themes and fullscreen. Not part of the
// game: HARNESS=window_check.dm SENDER=shot.ps1 tools/keybind_check/run.sh <label>
// Pictures land in data/previews/window_*.png.

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
			window_check_run(src)

/client/Topic(href, href_list, hsrc)
	if(href_list["probe"])
		kc_log("page says [href_list["probe"]]: [href_list["value"]]")
		return
	return ..()

GLOBAL_LIST_EMPTY(wc_statuses)
/client/verb/wc_status(text as text)
	set name = "wc-status"
	set hidden = TRUE
	if(length(text) > 2)
		GLOB.wc_statuses |= text

GLOBAL_VAR_INIT(wc_entered, 0)
/atom/MouseEntered(location, control, params)
	GLOB.wc_entered++

/proc/wc_check(name, ok, detail)
	kc_log("[ok ? "PASS" : "FAIL"] [name][isnull(detail) ? "" : " ([detail])"]")

/proc/wc_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/// What the page sends for a button, less the trip.
/proc/wc_act(client/C, datum/tgui/ui, action, path)
	C.display_settings.ui_act(action, path ? list("path" = path) : list(), ui, ui.state)

/proc/window_check_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1
	wc_check("the skin in use has the new controls", winexists(C, "status_bar") == "LABEL" && winexists(C, "display") == "BUTTON" && winexists(C, "input") == "INPUT")
	wc_check("no menu bar, no native status bar", !length(winget(C, "mainwindow", "menu")) && winget(C, "mainwindow", "statusbar") == "false", "[winget(C, "mainwindow", "menu")] / [winget(C, "mainwindow", "statusbar")]")
	wc_shot("window_lobby")
	C << output(url_encode({"runByond('byond://?probe=chat&value=' + encodeURIComponent(opts.darkmode + ' ' + document.getElementById('sheetofstyles').getAttribute('href') + ' cookie=' + getCookie('darkmode')));"}), "browseroutput:eval")
	sleep(10)
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	var/turf/home = get_turf(pick(SSjob.latejoin_trackers))
	var/mob/living/carbon/human/H = new(home)
	H.mind_initialize()
	H.equipOutfit(/datum/outfit/job/assistant)
	H.ckey = C.ckey
	sleep(4 SECONDS)
	kc_log("round state [SSticker.current_state], mob [C.mob]")
	C.fit_viewport()
	sleep(10)
	wc_shot("window_round")
	// The hover label: what BYOND writes to the status bar goes to it (on-status).
	var/label_command = winget(C, "mapwindow", "on-status")
	winset(C, "mapwindow", list2params(list("on-status" = "wc-status \"\[\[*]]\"")))
	text2file("go", "data/keycheck_hover") //shot.ps1 moves the mouse over the map
	sleep(30)
	wc_check("hovering the map raises status events", length(GLOB.wc_statuses), jointext(GLOB.wc_statuses, " | "))
	winset(C, "mapwindow", list2params(list("on-status" = label_command)))
	sleep(5)
	wc_check("the skin's command is back", winget(C, "mapwindow", "on-status") == label_command, label_command)
	// [[*]] expands to the text in quotes, and the label's cleared by the mouse leaving: this is the command with "shuttle seat" in it.
	winset(C, null, list2params(list("command" = replacetext(label_command, "\[\[*]]", "\"shuttle seat\""))))
	sleep(5)
	wc_check("the label takes the text", winget(C, "status_bar", "text") == "shuttle seat", winget(C, "status_bar", "text"))
	wc_shot("window_label")

	// The Display panel.
	C.display_settings()
	sleep(30)
	var/datum/tgui/ui = SStgui.get_open_ui(C.mob, C.display_settings, "main")
	wc_check("the Display panel opens", ui && ui.initialized)
	var/list/data = C.display_settings.ui_data(C.mob)
	kc_log(json_encode(data))
	winset(C, ui?.window_id, "pos=1800,300;focus=true")
	sleep(10)
	wc_shot("popup_display")
	wc_act(C, ui, "size", "/datum/verbs/menu/Icon/Size/verb/icon64")
	sleep(5)
	wc_check("icon size is set", winget(C, "mapwindow.map", "icon-size") == "64", winget(C, "mapwindow.map", "icon-size"))
	wc_act(C, ui, "size", "/datum/verbs/menu/Icon/Size/verb/iconstretchtofit")
	sleep(5)
	wc_check("icon size back to auto", winget(C, "mapwindow.map", "icon-size") == "0", winget(C, "mapwindow.map", "icon-size"))
	wc_act(C, ui, "scaling", "/datum/verbs/menu/Icon/Scaling/verb/BL")
	sleep(5)
	wc_check("scaling is set", winget(C, "mapwindow.map", "zoom-mode") == "blur", winget(C, "mapwindow.map", "zoom-mode"))
	wc_act(C, ui, "scaling", "/datum/verbs/menu/Icon/Scaling/verb/NN")
	sleep(5)
	wc_check("scaling back", winget(C, "mapwindow.map", "zoom-mode") == "distort", winget(C, "mapwindow.map", "zoom-mode"))

	// The themes, through the panel's own switch: it goes round by the chat, which calls back.
	wc_check("starts dark", C.dark_theme)
	wc_act(C, ui, "dark")
	sleep(20)
	wc_check("goes light", !C.dark_theme && winget(C, "stat", "background-color") != COLOR_DARKMODE_DARKBACKGROUND, "stat [winget(C, "stat", "background-color")], button [winget(C, "display", "background-color")]")
	wc_shot("window_light")
	wc_act(C, ui, "dark")
	sleep(20)
	wc_check("back to dark", C.dark_theme && winget(C, "display", "background-color") == "#2c2f33", winget(C, "display", "background-color"))

	// Fullscreen.
	wc_check("not fullscreen to begin with", winget(C, "mainwindow", "is-fullscreen") == "false", winget(C, "mainwindow", "is-fullscreen"))
	wc_act(C, ui, "fullscreen")
	sleep(20)
	wc_check("fullscreen on", winget(C, "mainwindow", "is-fullscreen") == "true", "[winget(C, "mainwindow", "is-fullscreen")], [winget(C, "mainwindow", "size")]")
	wc_shot("window_fullscreen")
	wc_act(C, ui, "fullscreen")
	sleep(20)
	wc_check("fullscreen off", winget(C, "mainwindow", "is-fullscreen") == "false", winget(C, "mainwindow", "is-fullscreen"))
	C.keyDown("F11")
	C.keyUp("F11")
	sleep(15)
	wc_check("F11 goes fullscreen", winget(C, "mainwindow", "is-fullscreen") == "true", winget(C, "mainwindow", "is-fullscreen"))
	C.keyDown("F11")
	C.keyUp("F11")
	sleep(15)
	wc_check("F11 comes back", winget(C, "mainwindow", "is-fullscreen") == "false", winget(C, "mainwindow", "is-fullscreen"))
	wc_shot("window_after")

	// Popups.
	C.prefs.ShowChoices(C.mob)
	sleep(20)
	wc_shot("window_prefs_behind")

	winset(C, "preferences_window", "pos=1200,120;focus=true")
	sleep(10)
	wc_shot("screen_prefs")
	wc_check("no runtimes from any of it", !fexists("data/keycheck_stop"))
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
