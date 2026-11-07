// The chat (goonchat) with a real client: a round's worth of messages of every kind, pictures, and checks of the tabs, search,
// timestamps, settings, history over a reload and the light theme. Not part of the game:
//   echo before > data/chat_check_label; SHOT_MINUTES=6 HARNESS=chat_check.dm SENDER=shot.ps1 tools/keybind_check/run.sh chat
// Pictures in data/previews/chat_<label>_*.png (the whole game window), results in data/keycheck_chat.txt.

GLOBAL_VAR_INIT(keycheck_running, FALSE)
GLOBAL_VAR_INIT(cc_label, "now")
GLOBAL_LIST_EMPTY(cc_probes)

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
			chat_check_run(src)

/client/Topic(href, href_list, hsrc)
	if(href_list["probe"])
		GLOB.cc_probes[href_list["probe"]] = href_list["value"]
		kc_log("page says [href_list["probe"]]: [href_list["value"]]")
		return
	return ..()

/proc/cc_check(name, ok, detail)
	kc_log("[ok ? "PASS" : "FAIL"] [name][isnull(detail) ? "" : " ([detail])"]")

/proc/cc_shot(name)
	text2file("chat_[GLOB.cc_label]_[name]", "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/// Runs js in the chat. No square brackets in it: DM would read them as embedded expressions.
/proc/cc_js(client/C, js)
	C << output(url_encode(js), "browseroutput:eval")

/// Asks the page for a value (a js expression) and waits for the answer.
/proc/cc_ask(client/C, name, expr)
	GLOB.cc_probes -= name
	cc_js(C, "try { runByond('byond://?probe=[name]&value=' + encodeURIComponent(String([expr]))); } catch (e) { runByond('byond://?probe=[name]&value=' + encodeURIComponent('error ' + e)); }")
	var/deadline = world.time + 5 SECONDS
	while(!(name in GLOB.cc_probes) && world.time < deadline)
		sleep(1)
	return GLOB.cc_probes[name]

/proc/cc_free_turf_near(turf/T)
	for(var/turf/open/floor/F in orange(1, T))
		if(!F.density && !(locate(/obj/structure) in F) && !(locate(/mob) in F))
			return F

/proc/chat_check_run(client/C)
	if(fexists("data/chat_check_label"))
		GLOB.cc_label = trim(file2text("data/chat_check_label"))
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1
	var/wait_chat = world.time + 30 SECONDS
	while(!C.chatOutput?.loaded && world.time < wait_chat)
		sleep(5)
	cc_check("the chat comes up on its own", C.chatOutput?.loaded, C.chatOutput?.loaded ? "after [(world.time - wait_chat + 30 SECONDS) / 10] s" : "not in 30 s")
	if(!C.chatOutput?.loaded)
		kc_log("browseroutput visible=[winget(C, "browseroutput", "is-visible")] output visible=[winget(C, "output", "is-visible")]")
		kc_log("page: [cc_ask(C, "stuck", {"document.readyState + ' ' + document.body.className + ' ' + typeof window.chatui + ' ' + typeof window.jQuery + ' ' + location.href"})]")
		// Not through the page's own runByond: whatever page is there
		GLOB.cc_probes -= "raw"
		C << output(url_encode({"window.chrome.webview.postMessage('byond://?probe=raw&value=' + encodeURIComponent(location.href + ' | ' + document.readyState + ' | jq=' + typeof window.jQuery + ' rb=' + typeof window.runByond + ' | ' + Array.from(document.querySelectorAll('link,script')).map(function (e) { return (e.href || e.src || 'inline').split('/').pop() + (e.sheet ? ':css-ok' : ''); }).join(' ') + ' | done: ' + performance.getEntriesByType('resource').map(function (r) { return r.name.split('/').pop() + '=' + Math.round(r.duration) + 'ms'; }).join(' ')));"}), "browseroutput:eval")
		sleep(30)
		kc_log("raw: [GLOB.cc_probes["raw"]]")
		for(var/name in list("browserOutput_ui.css", "spritesheet_chat.css", "browserOutput.css", "browserOutput.js"))
			var/datum/asset_cache_item/ACI = SSassets.cache[name]
			kc_log("asset [name]: registered [ACI ? ACI.md5 : "NO"], client has [C.sent_assets[name] || "nothing"]")
		GLOB.cc_probes -= "fetch"
		C << output(url_encode({"(function () { var t = Date.now(); var out = ''; var done = 0; function one(name) { fetch(name).then(function (r) { out += name + '=' + r.status + ' in ' + (Date.now() - t) + 'ms; '; }, function (e) { out += name + ' failed ' + e + '; '; }); } one('no_such_file.css'); one('browserOutput_ui.css'); one('browserOutput.css'); setTimeout(function () { window.chrome.webview.postMessage('byond://?probe=fetch&value=' + encodeURIComponent(out || 'nothing answered in 4 s')); }, 4000); })()"}), "browseroutput:eval")
		sleep(60)
		kc_log("fetch: [GLOB.cc_probes["fetch"]]")
		C.chatOutput.load()
		wait_chat = world.time + 20 SECONDS
		while(!C.chatOutput?.loaded && world.time < wait_chat)
			sleep(5)
		kc_log("after load(): loaded=[C.chatOutput.loaded]")
	sleep(10)
	// What 516's page can keep between sessions, and what was kept from the last run.
	var/env = cc_ask(C, "env", {"(function () { var r = {}; r.hub = typeof window.hubStorage; r.server = typeof window.serverStorage; r.domain = typeof window.domainStorage; r.picker = typeof window.showSaveFilePicker; r.href = location.href; try { r.lsPrev = localStorage.getItem('chatcheck_prev'); localStorage.setItem('chatcheck_prev', String(Date.now())); } catch (e) { r.ls = 'error ' + e; } try { if (window.serverStorage) { var v = window.serverStorage.getItem('chatcheck_prev'); r.serverGet = (v && v.then) ? 'promise' : String(v); window.serverStorage.setItem('chatcheck_prev', String(Date.now())); } } catch (e) { r.serverErr = String(e); } try { if (window.hubStorage) { var h = window.hubStorage.getItem('chatcheck_prev'); r.hubGet = (h && h.then) ? 'promise' : String(h); window.hubStorage.setItem('chatcheck_prev', String(Date.now())); } } catch (e) { r.hubErr = String(e); } r.cookie = document.cookie.length; return JSON.stringify(r); })()"})
	kc_log("environment: [env]")
	var/new_chat = cc_ask(C, "newchat", "typeof window.chatui") == "object"
	kc_log("new chat: [new_chat]")

	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(3 SECONDS)
	var/turf/home = get_turf(pick(SSjob.latejoin_trackers))
	var/mob/living/carbon/human/H = new(home)
	H.mind_initialize()
	H.fully_replace_character_name(null, "Alex Harness") //before the outfit, so the ID says it too
	H.equipOutfit(/datum/outfit/job/assistant)
	H.ckey = C.ckey
	sleep(3 SECONDS)
	C.fit_viewport()
	if(!C.holder) // the Admin tab
		var/datum/admins/A = new(new /datum/admin_rank("!localhost!", R_EVERYTHING, R_DBRANKS, R_EVERYTHING), C.ckey, 1, 1)
		A.associate(C)
	sleep(10)

	var/mob/living/carbon/human/sam = new(cc_free_turf_near(get_turf(H)) || get_turf(H))
	sam.fully_replace_character_name(null, "Sam Hill")
	sam.equipOutfit(/datum/outfit/job/assistant)
	sleep(10)
	cc_js(C, "$('#clearMessages').click(); if (window.chatui) chatui.clear();")
	sleep(5)

	// A round's worth: local talk, radio, emotes, OOC, combat, notices, repeats, an announcement, an admin log line.
	sam.say("Anyone seen my toolbox?")
	sleep(3)
	sam.say(";Breach in the bar, need engineering!")
	sleep(10)
	sam.emote("laugh")
	sleep(3)
	to_chat(C, "<span class='ooc'><span class='prefix'>OOC:</span> <EM>yoyobatty:</EM> <span class='message linkify'>anyone up for cards after this round?</span></span>")
	sleep(3)
	for(var/i in 1 to 3)
		to_chat(H, "<span class='notice'>You pick up the wrench.</span>")
		sleep(1)
	sam.a_intent = INTENT_HARM
	for(var/i in 1 to 2)
		sam.UnarmedAttack(H, TRUE)
		sleep(3)
	H.visible_message("<span class='danger'>Alex Harness has hit Sam Hill with the wrench!</span>", "<span class='danger'>You hit Sam Hill with the wrench!</span>")
	sleep(3)
	H.say("Hey! Cut it out!")
	sleep(3)
	sam.say(";Never mind, it was a false alarm.")
	sleep(5)
	minor_announce("Meteors have been detected on collision course with the station.", "Meteor Alert")
	sleep(3)
	message_admins("[key_name_admin(H)] has opened a test console.")
	sleep(3)
	to_chat(H, "<span class='warning'>You need a free hand to do that!</span>")
	to_chat(H, "Sam Hill picks up the wrench.")
	sleep(10)
	cc_shot("all")
	var/total = text2num(cc_ask(C, "count", "$('#messages .entry').length"))
	kc_log("messages: [total]")

	if(!new_chat)
		cc_check("old chat pictured", TRUE)
		chat_check_done(C)
		return

	// The tabs: what each shows.
	var/list/expect = list(
		"local" = list("Anyone seen my toolbox", "Cut it out", "laughs"),
		"radio" = list("Breach in the bar", "false alarm"),
		"ooc" = list("cards after this round"),
		"combat" = list("with the wrench"),
		"admin" = list("test console"))
	for(var/tab in expect)
		cc_js(C, "chatui.selectTab('[tab]');")
		sleep(5)
		var/shown = cc_ask(C, "shown_[tab]", "chatui.visibleText()")
		var/list/missing = list()
		for(var/bit in expect[tab])
			if(!findtext(shown, bit))
				missing += bit
		cc_check("the [tab] tab shows its messages", !missing.len, missing.len ? "missing [jointext(missing, ", ")]; shows: [copytext(shown, 1, 300)]" : null)
		cc_check("the [tab] tab hides the rest", !findtext(shown, "You pick up the wrench"), copytext(shown, 1, 200))
		cc_shot("tab_[tab]")
	cc_js(C, "chatui.selectTab('all');")
	sleep(3)

	// Unread counts: a radio message lands while Local is open.
	cc_js(C, "chatui.selectTab('local');")
	sleep(3)
	sam.say(";Radio check, one two.")
	sleep(10)
	var/unread = cc_ask(C, "unread", "chatui.unread.radio")
	cc_check("a message for another tab counts as unread there", text2num(unread) >= 1, unread)
	cc_shot("unread")
	cc_js(C, "chatui.selectTab('radio');")
	sleep(3)
	unread = cc_ask(C, "unread2", "chatui.unread.radio")
	cc_check("opening the tab clears its count", text2num(unread) == 0, unread)
	cc_js(C, "chatui.selectTab('all');")
	sleep(3)

	// Search.
	cc_js(C, "chatui.openSearch(); chatui.setSearch('wrench');")
	sleep(5)
	var/found = cc_ask(C, "search", "chatui.visibleText()")
	cc_check("search shows the lines with the word", findtext(found, "wrench") && !findtext(found, "toolbox"), copytext(found, 1, 300))
	cc_shot("search")
	cc_js(C, "chatui.closeSearch();")
	sleep(3)

	// Timestamps.
	cc_js(C, "chatui.setOption('timestamps', true);")
	sleep(5)
	var/ts = cc_ask(C, "ts", "$('#messages .entry .ts:visible').length")
	cc_check("timestamps show", text2num(ts) > 3, ts)
	cc_shot("timestamps")
	cc_js(C, "chatui.setOption('timestamps', false);")
	sleep(3)

	// Settings.
	cc_js(C, "chatui.openSettings();")
	sleep(8)
	cc_shot("settings")
	cc_js(C, "chatui.closeSettings();")
	sleep(3)

	// Light theme.
	cc_js(C, "swap();")
	sleep(15)
	cc_shot("light")
	cc_js(C, "swap();")
	sleep(15)
	cc_check("dark again", C.dark_theme)

	// History, 1: Fix chat loads the page again; it keeps its own.
	cc_js(C, "chatui.saveHistory(true);")
	sleep(5)
	cc_reload(C)
	var/restored = cc_ask(C, "restored", "$('#messages .entry.restored').length")
	cc_check("Fix chat: the last messages come back", text2num(restored) >= total - 2, "[restored] of [total]")
	var/restored_text = cc_ask(C, "restored_text", "chatui.visibleText()")
	cc_check("Fix chat: they're the round's", findtext(restored_text, "Breach in the bar"), copytext(restored_text, 1, 200))
	cc_check("Fix chat: their links still work (same round)", cc_ask(C, "stale1", "$('#messages .entry.stale').length") == "0")
	cc_shot("restored")
	// History, 2: a new client (another game window, the page's storage empty): the server sends them.
	cc_js(C, "chatui.saveHistory = function () {}; localStorage.removeItem('goonchat_history');")
	sleep(3)
	cc_reload(C)
	var/recovered = cc_ask(C, "recovered", "$('#messages .entry.restored').length")
	cc_check("new client: the server sends the last messages", text2num(recovered) >= total - 2, "[recovered] of [total]")
	var/recovered_text = cc_ask(C, "recovered_text", "chatui.visibleText()")
	cc_check("new client: they're the round's", findtext(recovered_text, "Breach in the bar") && findtext(recovered_text, "Reconnected"), copytext(recovered_text, 1, 200))
	cc_check("new client: their links work", cc_ask(C, "stale2", "$('#messages .entry.stale').length") == "0")
	cc_check("new client: no 'AFK or lagging' banner", cc_ask(C, "afk", "$('.connectionClosed').length") == "0")
	cc_shot("recovered")
	cc_check("the Admin tab is there for an admin", cc_ask(C, "admintab", "$('#tab-admin:visible').length") == "1")
	cc_check("Save log has something to save with", cc_ask(C, "picker", "typeof window.showSaveFilePicker") == "function")
	chat_check_done(C)

/// The page loaded again the way Fix chat does it.
/proc/cc_reload(client/C)
	C.chatOutput.loaded = FALSE
	C.chatOutput.messageQueue = list()
	C.chatOutput.load()
	var/deadline = world.time + 20 SECONDS
	while(!C.chatOutput.loaded && world.time < deadline)
		sleep(2)
	sleep(20)

/proc/chat_check_done(client/C)
	cc_check("no js errors reported", !fexists("data/keycheck_stop"))
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
