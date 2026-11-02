// How a tgui page talks to the client on 516, and whether opening one raises the "open BYOND" prompt: a real client opens a few
// windows, watchwindows.ps1 lists every window that turns up, and the page reports what it can see. Not part of the game:
// HARNESS=tgui_bridge_check.dm SENDER=watchwindows.ps1 tools/keybind_check/run.sh <label>

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
			tgui_bridge_run(src)

/// Whatever a page sends back.
/client/Topic(href, href_list, hsrc)
	if(href_list["probe"])
		kc_log("page says [href_list["probe"]]: [href_list["value"]]")
		return
	return ..()

/proc/tgui_bridge_eval(client/C, id, js)
	C << output(url_encode(js), "[id].browser:eval")

/proc/tgui_bridge_open(client/C, datum/thing, key)
	var/mob/M = C.mob
	var/datum/tgui/ui = new(M, thing, key, "BotPatrol", "Probe [key]", 420, 260, null, GLOB.always_state)
	ui.open()
	winset(C, ui.window_id, "pos=1780,760;focus=true") //clear of anything else on the desktop, for the picture
	return ui

/// Calls from the page while it's running: an action with a camelCase name in it has to arrive the way it left.
/datum/tgui_bridge_thing/ui_act(action, params)
	kc_log("ui_act [action]: [json_encode(params)]")
	return TRUE

/datum/tgui_bridge_thing/ui_data(mob/user)
	return list("x" = 1)

/proc/tgui_bridge_run(client/C)
	UNTIL(SSticker.initialized)
	kc_log("connected: [C.ckey], byond [C.byond_version].[C.byond_build]")
	if(fexists("data/keycheck_old_page"))
		SStgui.basehtml = file2text("data/keycheck_old_page")
		kc_log("on the old page")
	text2file("go", "data/keycheck_sendkeys") //starts watchwindows.ps1
	sleep(30)
	var/datum/tgui_bridge_thing/thing = new
	var/list/opened = list()
	for(var/i in 1 to 3)
		var/datum/tgui/ui = tgui_bridge_open(C, thing, "probe[i]")
		opened += ui
		sleep(25)
		kc_log("window [i]: [ui.window_id] is a [winexists(C, ui.window_id)], initialized [ui.initialized]")
		fdel("data/keycheck_shot")
		text2file("tgui_[fexists("data/keycheck_old_page") ? "before" : "after"]_[i]", "data/keycheck_shot")
		sleep(10)
	var/obj/machinery/sleeper/S = new(C.mob.loc)
	var/datum/tgui/old_style = new(C.mob, S, "main", "sleeper", "Sleeper", 375, 550, null, GLOB.always_state)
	old_style.open()
	winset(C, old_style.window_id, "pos=1780,760;focus=true")
	sleep(35)
	kc_log("old tgui window: [old_style.window_id] is a [winexists(C, old_style.window_id)], initialized [old_style.initialized]")
	fdel("data/keycheck_shot")
	text2file("tgui_[fexists("data/keycheck_old_page") ? "before" : "after"]_sleeper", "data/keycheck_shot")
	sleep(10)
	old_style.close()
	var/datum/tgui/first = opened[1]
	var/js = {"(function(){
		var say = function(k, v) { window.__sendToByond__('byond://?probe=' + encodeURIComponent(k) + '&value=' + encodeURIComponent(String(v).slice(0, 700))); };
		say('transport', window.__byondTransport__ || 'bridge');
		say('typeof _pm', typeof _pm);
		try { say('_pm', _pm); } catch(e) { say('_pm', e); }
		try { say('fromCamel', fromCamel); } catch(e) { say('fromCamel', e); }
		say('webview', typeof window.chrome + ' ' + typeof (window.chrome && chrome.webview));
		window.__sendToByond__('byond://?src=' + window.__ref__ + '&action=tgui:view&screen=x');
	})();"}
	tgui_bridge_eval(C, first.window_id, js)
	sleep(30)
	// An action through the bundle, as a button would send it.
	tgui_bridge_eval(C, first.window_id, {"window.__sendToByond__('byond://?src=' + window.__ref__ + '&action=someCamelAction&someKey=a%20b&plain=1');"})
	sleep(15)
	// Dragging a tgui window asks for its position: a call that wants an answer, on the page that asked.
	tgui_bridge_eval(C, first.window_id, {"window.__callbacks__ = window.__callbacks__ || \[]; window.__callbacks__.push(function(o){ window.__sendToByond__('byond://?probe=winget&value=' + encodeURIComponent(JSON.stringify(o))); }); window.__sendToByond__('byond://winget?id=' + encodeURIComponent('[first.window_id]') + '&property=pos&callback=' + encodeURIComponent('__callbacks__\[' + (window.__callbacks__.length - 1) + ']'));"})
	sleep(15)
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
