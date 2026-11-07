// How long the chat takes to come up on a fresh connection, with the server's own retry switched off, and what the page fetched
// when (its chatLoadLog). If it's stuck at 7 s, which of its files are, and whether name?r=1 is served. Not part of the game:
//   HARNESS=chat_reload_check.dm tools/keybind_check/run.sh chatup
// 516.1688, 2026-11-06: without the page's loader, 3 of 3 connects never came up in 60 s; with it, all up in 1.5-1.8 s.
// Never log a line starting "done" before the end: run.sh takes it for the finish and kills the server.

GLOBAL_VAR_INIT(keycheck_running, FALSE)
GLOBAL_LIST_EMPTY(cc_probes)

/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

/datum/chatOutput/retry_load(attempt) // the diagnostic wants the page left as it is
	return

GLOBAL_VAR_INIT(cc_login_time, 0)
/datum/chatOutput/start()
	GLOB.cc_login_time = REALTIMEOFDAY
	kc_log("start() at 0 ms")
	. = ..()
	kc_log("start() returned at [REALTIMEOFDAY - GLOB.cc_login_time] ms")

/datum/chatOutput/load(attempt = 1)
	set waitfor = FALSE
	kc_log("load() at [REALTIMEOFDAY - GLOB.cc_login_time] ds")
	var/datum/asset/stuff = get_asset_datum(/datum/asset/group/goonchat)
	kc_log("got asset datum at [REALTIMEOFDAY - GLOB.cc_login_time] ds")
	stuff.send(owner)
	kc_log("sent assets at [REALTIMEOFDAY - GLOB.cc_login_time] ds")
	owner << browse(file('code/modules/goonchat/browserassets/html/browserOutput.html'), "window=browseroutput")
	kc_log("browse() sent at [REALTIMEOFDAY - GLOB.cc_login_time] ds")

/datum/chatOutput/doneLoading(fresh)
	kc_log("page reported in at [REALTIMEOFDAY - GLOB.cc_login_time] ds")
	return ..()

/proc/kc_log(text)
	text2file(text, "data/keycheck.txt")

/client/New()
	. = ..()
	if(. && !GLOB.keycheck_running)
		GLOB.keycheck_running = TRUE
		spawn(50)
			chat_reload_run(src)

/client/Topic(href, href_list, hsrc)
	if(href_list["probe"])
		GLOB.cc_probes[href_list["probe"]] = href_list["value"]
		kc_log("page says [href_list["probe"]]: [href_list["value"]]")
		return
	return ..()

/proc/cc_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/proc/cc_ask(client/C, name, expr)
	GLOB.cc_probes -= name
	C << output(url_encode("try { runByond('byond://?probe=[name]&value=' + encodeURIComponent(String([expr]))); } catch (e) { runByond('byond://?probe=[name]&value=' + encodeURIComponent('error ' + e)); }"), "browseroutput:eval")
	var/deadline = world.time + 3 SECONDS
	while(!(name in GLOB.cc_probes) && world.time < deadline)
		sleep(1)
	return GLOB.cc_probes[name]

/proc/chat_reload_run(client/C)
	// How long the chat takes to come up on its own (the client was just connected; this runs 5 s after client/New).
	var/start = world.time - 5 SECONDS
	sleep(70)
	if(!C.chatOutput?.loaded) // stuck: what the page can get, under its own URL and another
		GLOB.cc_probes -= "fetch"
		C << output(url_encode({"(function () { var t = Date.now(); var out = ''; var pending = Array.from(document.querySelectorAll('link')).filter(function (l) { return !l.sheet; }).map(function (l) { return l.href.split('/').pop(); }); out += 'stuck: ' + pending.join(',') + '; '; function one(name) { fetch(name).then(function (r) { out += name + '=' + r.status + ' in ' + (Date.now() - t) + 'ms; '; }, function (e) { out += name + ' failed; '; }); } pending.forEach(function (n) { one(n); one(n + '?r=1'); }); one('jquery.min.js?r=1'); setTimeout(function () { window.chrome.webview.postMessage('byond://?probe=fetch&value=' + encodeURIComponent(out)); }, 2500); })()"}), "browseroutput:eval")
		sleep(60)
		kc_log("fetch at 12 s: [GLOB.cc_probes["fetch"]]")
	while(!C.chatOutput?.loaded && world.time < start + 60 SECONDS)
		sleep(2)
	kc_log("chat up: [C.chatOutput?.loaded ? "yes after [(world.time - start) / 10] s" : "NO after 60 s"]")
	kc_log("page's load log: [cc_ask(C, "loadlog", "(window.chatLoadLog || \['none'\]).join(', ')")]")
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
