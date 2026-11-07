// How long the first tgui window of a connection (the lobby panel, which opens by itself) takes to come up, and what its page
// has when it hasn't. Not part of the game: HARNESS=tgui_first_check.dm tools/keybind_check/run.sh tguifirst

GLOBAL_VAR_INIT(keycheck_running, FALSE)
GLOBAL_VAR_INIT(tf_login, 0)
GLOBAL_LIST_EMPTY(tf_probes)

/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

/proc/kc_log(text)
	text2file(text, "data/keycheck.txt")

/client/New()
	GLOB.tf_login = REALTIMEOFDAY
	. = ..()
	if(. && !GLOB.keycheck_running)
		GLOB.keycheck_running = TRUE
		spawn(1)
			tgui_first_run(src)

/client/Topic(href, href_list, hsrc)
	if(href_list["probe"])
		GLOB.tf_probes[href_list["probe"]] = href_list["value"]
		return
	return ..()

/proc/tgui_first_run(client/C)
	var/datum/tgui/ui
	var/opened_at
	var/deadline = world.time + 60 SECONDS
	while(world.time < deadline)
		if(!ui && length(C.mob?.open_uis))
			ui = C.mob.open_uis[1]
			opened_at = REALTIMEOFDAY
		if(ui?.initialized)
			break
		sleep(1)
	if(!ui)
		kc_log("no tgui window opened in 60 s")
	else if(ui.initialized)
		kc_log("first window [ui.interface] opened [(opened_at - GLOB.tf_login) / 10] s after login, up [(REALTIMEOFDAY - opened_at) / 10] s later")
	else
		kc_log("first window [ui.interface] opened [(opened_at - GLOB.tf_login) / 10] s after login, NOT up in 60 s")
		GLOB.tf_probes -= "page"
		C << output(url_encode({"window.chrome.webview.postMessage('byond://?probe=page&value=' + encodeURIComponent(document.readyState + ' | ' + Array.from(document.querySelectorAll('link,script')).map(function (e) { return (e.href || e.src || 'inline').split('/').pop() + (e.sheet ? ':ok' : ''); }).join(' ') + ' | done: ' + performance.getEntriesByType('resource').map(function (r) { return r.name.split('/').pop(); }).join(' ')));"}), "[ui.window_id].browser:eval")
		sleep(30)
		kc_log("page: [GLOB.tf_probes["page"]]")
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
