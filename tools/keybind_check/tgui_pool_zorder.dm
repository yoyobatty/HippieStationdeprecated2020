// A pooled tgui window (winclone) against a browse() popup, as Windows sees them: owned by the game window or not, a taskbar
// button or not, still above the game window once the game window is clicked. Then the X of a pooled window with a title bar
// (WM_CLOSE): the UI closes and the window is kept, not destroyed. Uses window_owner_probe.ps1 through shell().
// Not part of the game: HARNESS=tgui_pool_zorder.dm MAP=testbench tools/keybind_check/run.sh pool_zorder

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
		spawn(10)
			tgui_pool_zorder_run(src)

/proc/tpz_probe(titles)
	fdel("data/window_owner_probe.txt")
	shell("powershell -NoProfile -ExecutionPolicy Bypass -File tools/keybind_check/window_owner_probe.ps1 -Titles \"[titles]\"")
	var/deadline = world.time + 10 SECONDS
	while(!fexists("data/window_owner_probe.txt") && world.time < deadline)
		sleep(1)
	sleep(2)
	return file2text("data/window_owner_probe.txt")

GLOBAL_LIST_EMPTY(tpz_probes)

/client/Topic(href, href_list, hsrc)
	if(href_list["probe"])
		GLOB.tpz_probes[href_list["probe"]] = href_list["value"]
		return
	return ..()

/proc/tpz_eval(client/C, target, expression, probe)
	GLOB.tpz_probes -= probe
	C << output(url_encode("(function () { var v; try { v = [expression]; } catch (e) { v = 'ERROR ' + e; } window.chrome.webview.postMessage('byond://?probe=[probe]&value=' + encodeURIComponent(String(v))); })();"), "[target]:eval")
	var/deadline = world.time + 3 SECONDS
	while(isnull(GLOB.tpz_probes[probe]) && world.time < deadline)
		sleep(1)
	return GLOB.tpz_probes[probe] || "no answer"

/proc/tgui_pool_zorder_run(client/C)
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
	C.prefs.tgui_fancy = FALSE // title bars, so Windows can find them by title

	// a browse() popup, the old way
	GLOB.tgui_pool_enabled = FALSE
	var/obj/machinery/space_heater/heater = new(home)
	heater.name = "oldwindow"
	heater.ui_interact(H)
	var/datum/tgui/old_ui = SStgui.get_open_ui(H, heater, "main")
	GLOB.tgui_pool_enabled = TRUE
	// a pooled window
	var/obj/machinery/power/smes/smes = new(home)
	smes.name = "poolwindow"
	smes.ui_interact(H)
	var/datum/tgui/pooled_ui = SStgui.get_open_ui(H, smes, "main")
	sleep(20)
	kc_log("old [old_ui?.window_id], pooled [pooled_ui?.window_id] ([pooled_ui?.pool_window ? "pooled" : "NOT pooled"])")
	kc_log(tpz_probe("oldwindow|poolwindow"))

	// its title bar's X
	var/datum/tgui_pool_window/W = pooled_ui.pool_window
	kc_log(tpz_probe("close:poolwindow"))
	sleep(10)
	kc_log("after the X: UI [SStgui.get_open_ui(H, smes, "main") ? "still open" : "closed"], window [winexists(C, W.id) || "GONE"], state [W.state], visible [winget(C, W.id, "is-visible")]")
	sleep(60)
	kc_log("6 s on: window [winexists(C, W.id) || "GONE"], in the pool [(W in C.tgui_pool.windows) ? "yes" : "no"], pool [length(C.tgui_pool.windows)] windows")
	smes.ui_interact(H)
	var/datum/tgui/again = SStgui.get_open_ui(H, smes, "main")
	sleep(10)
	kc_log("opened again: [again?.window_id] ([again?.pool_window ? "pooled" : "old way"]), visible [winget(C, again?.window_id, "is-visible")]")
	again?.close()
	old_ui?.close()
	kc_log("done")
