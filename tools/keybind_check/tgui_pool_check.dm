// The tgui window pool (hippiestation/code/modules/tgui/tgui_pool.dm) with a real client: a window is shown where it should be,
// clicks reach the right object and updates come back, the close button hides it and the next UI reuses it, two UIs at once, an
// object's own style sheet, old tgui taking a window over, the window without fancy frills, a re-open with new data, keyboard
// focus, a tgui_alert(), and a window taken from its UI by hand (the lobby's cleanup). Pictures in data/previews/popup_pool_*.png.
// Not part of the game: HARNESS=tgui_pool_check.dm SENDER=shot.ps1 MAP=testbench tools/keybind_check/run.sh pool_check

GLOBAL_VAR_INIT(keycheck_running, FALSE)
GLOBAL_LIST_EMPTY(tpc_probes)
GLOBAL_VAR_INIT(tpc_probe_count, 0)
GLOBAL_VAR_INIT(tpc_passed, 0)
GLOBAL_VAR_INIT(tpc_failed, 0)
GLOBAL_VAR(tpc_alert_answer)

/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

/proc/kc_log(text)
	text2file(text, "data/keycheck.txt")

/proc/tpc_check(name, condition, detail)
	if(condition)
		GLOB.tpc_passed++
	else
		GLOB.tpc_failed++
	kc_log("[condition ? "PASS" : "FAIL"] [name][detail ? " - [detail]" : ""]")

/client/New()
	. = ..()
	if(. && !GLOB.keycheck_running)
		GLOB.keycheck_running = TRUE
		spawn(10)
			tgui_pool_check_run(src)

/client/Topic(href, href_list, hsrc)
	if(href_list["probe"])
		GLOB.tpc_probes[href_list["probe"]] = href_list["value"]
		return
	return ..()

/// What the expression comes to in the UI's page, as text
/proc/tpc_eval(client/C, datum/tgui/ui, expression)
	var/probe = "p[++GLOB.tpc_probe_count]"
	var/js = "(function () { var v; try { v = (function () { return [expression]; })(); } catch (e) { v = 'ERROR ' + e; } window.chrome.webview.postMessage('byond://?probe=[probe]&value=' + encodeURIComponent(String(v))); })();"
	C << output(url_encode(js), ui.window_output_id("eval"))
	var/deadline = world.time + 5 SECONDS
	while(isnull(GLOB.tpc_probes[probe]) && world.time < deadline)
		sleep(1)
	return GLOB.tpc_probes[probe]

/proc/tpc_shot(name, datum/tgui/ui)
	text2file("[ui.width]x[ui.height]", "data/keycheck_shot_title")
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	fdel("data/keycheck_shot_title")
	sleep(2)

/// No tgui-next route (none of the game's own UIs lack one now): old tgui takes the page, with its VR sleeper template
/datum/tpc_oldtgui

/datum/tpc_oldtgui/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "vr_sleeper", "VR Sleeper", 475, 340, master_ui, state)
		ui.open()

/datum/tpc_oldtgui/ui_data(mob/user)
	return list("emagged" = FALSE, "vr_avatar" = FALSE, "toggle_open" = FALSE, "isoccupant" = FALSE)

/proc/tpc_open(mob/user, obj/machinery/M)
	M.stat = 0
	M.ui_interact(user)
	return SStgui.get_open_ui(user, M, "main")

/proc/tpc_pair(text) // "12,34" or "12x34" from winget
	var/list/parts = splittext(replacetext(text, "x", ","), ",")
	return list(text2num(parts[1]), text2num(parts[2]))

/// Where it is against where it should be: the middle of the game window
/proc/tpc_centred(client/C, datum/tgui/ui)
	var/list/main_pos = tpc_pair(winget(C, "mainwindow", "pos"))
	var/list/main_size = tpc_pair(winget(C, "mainwindow", "size"))
	var/list/pos = tpc_pair(winget(C, ui.window_id, "pos"))
	var/list/size = tpc_pair(winget(C, ui.window_id, "size"))
	var/off_x = (pos[1] + size[1] / 2) - (main_pos[1] + main_size[1] / 2)
	var/off_y = (pos[2] + size[2] / 2) - (main_pos[2] + main_size[2] / 2)
	return list(abs(off_x) <= 2 && abs(off_y) <= 2, "window [pos[1]],[pos[2]] [size[1]]x[size[2]], game window [main_pos[1]],[main_pos[2]] [main_size[1]]x[main_size[2]]")

/proc/tgui_pool_check_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
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
		tpc_steps(C, H, home)
	catch(var/exception/e)
		tpc_check("ran to the end", FALSE, "[e] at [e.file]:[e.line]")
	kc_log("[GLOB.tpc_passed] passed, [GLOB.tpc_failed] failed")
	text2file("done", "data/keycheck_shots_done")
	kc_log("done")

/proc/tpc_steps(client/C, mob/living/carbon/human/H, turf/home)
	var/datum/tgui_pool/pool = C.tgui_pool
	var/ready = 0
	for(var/datum/tgui_pool_window/W as anything in pool?.windows)
		if(W.state == 2)
			ready++
	tpc_check("a pool made at the lobby, a window ready", pool && ready >= 1, "[length(pool?.windows)] windows, [ready] ready")

	// shown where it should be, its page holds this UI
	var/obj/machinery/space_heater/heater = new(home)
	heater.on = FALSE
	var/datum/tgui/ui = tpc_open(H, heater)
	var/datum/tgui_pool_window/first = ui?.pool_window
	tpc_check("heater: in a pooled window", first, ui ? ui.window_id : "no UI")
	sleep(10)
	tpc_check("heater: shown", winget(C, ui.window_id, "is-visible") == "true")
	tpc_check("heater: its size", winget(C, ui.window_id, "size") == "[ui.width]x[ui.height]", winget(C, ui.window_id, "size"))
	var/list/centred = tpc_centred(C, ui)
	tpc_check("heater: centred on the game window", centred[1], centred[2])
	tpc_check("heater: the page has its ref", tpc_eval(C, ui, "window.__ref__") == "\ref[ui]")
	tpc_check("heater: its title drawn", lowertext(tpc_eval(C, ui, "document.querySelector('.TitleBar__title').innerText")) == lowertext(ui.title), tpc_eval(C, ui, "document.querySelector('.TitleBar__title').innerText"))
	tpc_shot("popup_pool_heater", ui)
	var/focused = winget(C, null, "focus")
	tpc_check("heater: has the keyboard, and the game knows it passes keys on", findtext(focused, ui.window_id) == 1 && C.focus_hears_keys(focused), "focus '[focused]'")

	// a click reaches the heater, and its update comes back
	tpc_eval(C, ui, "(window.__updates__ = 0, window.__realUpdate__ = window.update, window.update = function (j) { window.__updates__++; return window.__realUpdate__(j); }, 1)")
	tpc_eval(C, ui, "(window.chrome.webview.postMessage('byond://?src=' + window.__ref__ + '&action=power'), 1)")
	sleep(10)
	tpc_check("heater: the click turned it on", heater.on)
	tpc_check("heater: its update reached the page", text2num(tpc_eval(C, ui, "window.__updates__")) > 0, "[tpc_eval(C, ui, "window.__updates__")] updates")

	// the close button: hidden, kept, and the next UI gets it
	tpc_eval(C, ui, "(document.querySelector('.TitleBar__close').click(), 1)")
	sleep(10)
	tpc_check("close button: the UI is closed", !SStgui.get_open_ui(H, heater, "main"))
	tpc_check("close button: the window is hidden and ready", first.state == 2 && winget(C, first.id, "is-visible") == "false", "state [first.state], visible [winget(C, first.id, "is-visible")]")
	var/obj/machinery/power/smes/smes = new(home)
	ui = tpc_open(H, smes)
	sleep(10)
	tpc_check("SMES: the same window again", ui?.pool_window == first, ui?.window_id)
	tpc_check("SMES: its own title, nothing of the heater's", lowertext(tpc_eval(C, ui, "document.querySelector('.TitleBar__title').innerText")) == lowertext(ui.title) && !findtext(tpc_eval(C, ui, "document.body.innerText"), "Thermostat"), tpc_eval(C, ui, "document.querySelector('.TitleBar__title').innerText"))

	// a re-open with new data (NTOS changing program does this) stays in the window
	var/mounts = text2num(tpc_eval(C, ui, "window.__hippieMounts__"))
	smes.ui_interact(H, "main", null, TRUE)
	sleep(10)
	tpc_check("SMES: a re-open mounts again in the same window", ui.pool_window == first && text2num(tpc_eval(C, ui, "window.__hippieMounts__")) == mounts + 1 && winget(C, ui.window_id, "is-visible") == "true", "mounts [mounts] -> [tpc_eval(C, ui, "window.__hippieMounts__")]")

	// two at once
	var/obj/machinery/portable_atmospherics/canister/oxygen/can = new(home)
	var/datum/tgui/ui2 = tpc_open(H, can)
	sleep(10)
	tpc_check("two at once: the canister in another window", ui2 && ui2.window_id != ui.window_id, "[ui.window_id], [ui2?.window_id]")
	tpc_check("two at once: both shown", winget(C, ui.window_id, "is-visible") == "true" && winget(C, ui2.window_id, "is-visible") == "true")
	tpc_check("two at once: each page has its own ref", tpc_eval(C, ui, "window.__ref__") == "\ref[ui]" && tpc_eval(C, ui2, "window.__ref__") == "\ref[ui2]")
	ui.close()
	ui2.close()
	sleep(5)

	// an object's own style sheet (the autolathe's design pictures)
	var/obj/machinery/autolathe/lathe = new(home)
	ui = tpc_open(H, lathe)
	sleep(20)
	tpc_check("autolathe: pooled", ui?.pool_window)
	var/sheet = copytext(lathe.ui_base_html("<!--customheadhtml-->"), findtext(lathe.ui_base_html("<!--customheadhtml-->"), "spritesheet_"))
	sheet = copytext(sheet, 1, findtext(sheet, ".css") + 4)
	tpc_check("autolathe: its sprite sheet ([sheet]) in the head and loaded", tpc_eval(C, ui, "Array.prototype.some.call(document.styleSheets, function (s) { return s.href && s.href.indexOf('[sheet]') >= 0 && s.cssRules.length > 0; })") == "true", tpc_eval(C, ui, "Array.prototype.map.call(document.styleSheets, function (s) { return (s.href || 'inline').split('/').pop(); }).join(' ')"))
	tpc_shot("popup_pool_autolathe", ui)
	ui.close()
	sleep(5)

	// a map inside the window (the camera console): made in the pooled window, gone with its UI
	var/obj/machinery/computer/security/cams = new(home)
	ui = tpc_open(H, cams)
	sleep(20)
	var/map_id = cams.vars["map_name"]
	tpc_check("camera console: pooled, its map made in the window", ui?.pool_window && winexists(C, map_id) == "MAP" && winget(C, map_id, "parent") == ui.window_id, "[map_id]: [winexists(C, map_id)], parent [winget(C, map_id, "parent")]")
	tpc_shot("popup_pool_cameras", ui)
	ui.close()
	sleep(10)
	tpc_check("camera console: its map gone when it closed", !winexists(C, map_id), "'[winexists(C, map_id)]'")

	// old tgui takes a window over for good: it's thrown away when it closes
	var/datum/tpc_oldtgui/vr = new
	vr.ui_interact(H)
	ui = SStgui.get_open_ui(H, vr, "main")
	var/datum/tgui_pool_window/spent = ui?.pool_window
	sleep(30)
	tpc_check("VR sleeper (old tgui): pooled, then spent", spent && spent.state == 4, "state [spent?.state]")
	tpc_check("VR sleeper (old tgui): shown, old tgui drew it", winget(C, ui.window_id, "is-visible") == "true" && text2num(tpc_eval(C, ui, "document.getElementById('container').innerText.length")) > 0, "container text [tpc_eval(C, ui, "document.getElementById('container').innerText.length")]")
	tpc_shot("popup_pool_vr_sleeper", ui)
	var/spent_id = spent?.id
	ui.close()
	sleep(5)
	tpc_check("VR sleeper: its window thrown away", spent && !(spent in pool.windows) && !winexists(C, spent_id), "exists '[winexists(C, spent_id)]'")

	// without fancy frills: the OS title bar, resizable, its close button wired
	C.prefs.tgui_fancy = FALSE
	ui = tpc_open(H, heater)
	sleep(10)
	tpc_check("no frills: title bar and resizing", winget(C, ui.window_id, "titlebar") == "true" && winget(C, ui.window_id, "can-resize") == "true", winget(C, ui.window_id, "titlebar;can-resize"))
	tpc_check("no frills: its title and close command", winget(C, ui.window_id, "title") == ui.title && findtext(winget(C, ui.window_id, "on-close"), "uiclose"), winget(C, ui.window_id, "title;on-close"))
	tpc_shot("popup_pool_nofrills", ui)
	ui.close()
	C.prefs.tgui_fancy = TRUE
	sleep(5)

	// a tgui_alert(): shown, focused, answered by a click
	GLOB.tpc_alert_answer = null
	spawn(0)
		GLOB.tpc_alert_answer = tgui_alert(H, "Pool test?", "Pool", list("Yes", "No"))
	sleep(10)
	var/datum/tgui/prompt
	for(var/datum/tgui/open as anything in H.open_uis)
		prompt = open
	tpc_check("alert: in a pooled window, shown", prompt?.pool_window && winget(C, prompt.window_id, "is-visible") == "true", prompt?.window_id)
	tpc_shot("popup_pool_alert", prompt)
	tpc_eval(C, prompt, "(Array.prototype.filter.call(document.querySelectorAll('.Button'), function (b) { return b.innerText.trim() === 'Yes'; })\[0\].click(), 1)")
	sleep(10)
	tpc_check("alert: the click answered it", GLOB.tpc_alert_answer == "Yes", "answer [GLOB.tpc_alert_answer]")

	// taken from its UI by hand, as the lobby's cleanup does: the UI closing later leaves the window alone
	ui = tpc_open(H, smes)
	var/datum/tgui_pool_window/taken = ui.pool_window
	sleep(5)
	var/released = pool.release_id(taken.id)
	sleep(5) // its page answers that it's empty
	tpc_check("by hand: released", released && taken.state == 2 && winget(C, taken.id, "is-visible") == "false", "state [taken.state]")
	var/datum/tgui/ui3 = tpc_open(H, can) // takes it
	sleep(5)
	ui.close() // the old UI closing late
	sleep(5)
	tpc_check("by hand: the old UI closing doesn't touch the window now in use", ui3.pool_window && winget(C, ui3.window_id, "is-visible") == "true" && tpc_eval(C, ui3, "window.__ref__") == "\ref[ui3]", "[ui3.window_id] visible [winget(C, ui3.window_id, "is-visible")]")
	ui3.close()
	sleep(10)

	// a page that died while its window waited: the UI's mount is never answered, so it opens the old way
	var/datum/tgui_pool_window/dead
	for(var/datum/tgui_pool_window/W as anything in pool.windows)
		if(W.state == 2)
			dead = W
			break
	C << browse("<html><body>gone</body></html>", "window=[dead?.browser_id]")
	sleep(10)
	ui = tpc_open(H, heater)
	tpc_check("dead page: the UI went to that window", ui?.pool_window == dead, "[ui?.window_id], dead [dead?.id]")
	sleep(70)
	tpc_check("dead page: the UI opened the old way, shown", ui && !ui.pool_window && ui.window_id == ui.own_window_id && winget(C, ui.window_id, "is-visible") == "true", "[ui?.window_id] visible [winget(C, ui?.window_id, "is-visible")]")
	tpc_check("dead page: its window thrown away", dead && !(dead in pool.windows) && !winexists(C, dead.id))
	ui?.close()
	kc_log("pool at the end: [length(pool.windows)] windows")
