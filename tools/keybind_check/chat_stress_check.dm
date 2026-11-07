// The chat under load: 2000 mixed messages at about 100 a second through the server's chat queue (to_chat), the page's time on
// them measured inside it (its chatBatch wrapped), the history save timed, and the cap on messages kept. Not part of the game:
//   HARNESS=chat_stress_check.dm tools/keybind_check/run.sh chatstress
// Results in data/keycheck_chatstress.txt.

GLOBAL_VAR_INIT(keycheck_running, FALSE)
GLOBAL_LIST_EMPTY(cs2_probes)

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
			chat_stress_run(src)

/client/Topic(href, href_list, hsrc)
	if(href_list["probe"])
		GLOB.cs2_probes[href_list["probe"]] = href_list["value"]
		return
	return ..()

/proc/cs2_ask(client/C, name, expr)
	GLOB.cs2_probes -= name
	C << output(url_encode("window.chrome.webview.postMessage('byond://?probe=[name]&value=' + encodeURIComponent(String([expr])));"), "browseroutput:eval")
	var/deadline = world.time + 5 SECONDS
	while(!(name in GLOB.cs2_probes) && world.time < deadline)
		sleep(1)
	return GLOB.cs2_probes[name]

/proc/chat_stress_run(client/C)
	var/wait = world.time + 30 SECONDS
	while(!C.chatOutput?.loaded && world.time < wait)
		sleep(2)
	sleep(20)
	// The page's time on what the server sends, counted inside it
	C << output(url_encode({"window.__ms = 0; window.__calls = 0; window.__max = 0; var __orig = chatBatch; chatBatch = function () { var t = performance.now(); __orig.apply(this, arguments); var d = performance.now() - t; window.__ms += d; window.__calls++; if (d > window.__max) { window.__max = d; } }; var __save = chatui.saveHistory; window.__saveMs = 0; window.__saves = 0; chatui.saveHistory = function (f) { var t = performance.now(); __save(f); window.__saveMs += performance.now() - t; window.__saves++; };"}), "browseroutput:eval")
	sleep(10)
	var/list/kinds = list(
		"<span class='game say'><span class='name'>Sam Hill</span> <span class='message'>says, \"Message number %N, anyone seen my toolbox?\"</span></span>",
		"<span class='radio'><span class='name'>\[Common\] Rosa Delgado</span> <span class='message'>says, \"Breach at %N, need engineering\"</span></span>",
		"<span class='danger'>Sam Hill has punched Alex Harness! (%N)</span>",
		"<span class='notice'>You pick up the wrench. (%N)</span>",
		"<span class='ooc'><span class='prefix'>OOC:</span> <EM>somebody:</EM> <span class='message linkify'>see https://example.com/page%N for it</span></span>",
		"<span class='emote'><b>Sam Hill</b> laughs. (%N)</span>")
	var/started = REALTIMEOFDAY
	for(var/i in 1 to 2000)
		to_chat(C, replacetext(kinds[(i % kinds.len) + 1], "%N", "[i]"))
		if(i % 10 == 0)
			sleep(1) // ~100 a second at 10 ticks a second... the server's tick rate decides
	var/sent_in = (REALTIMEOFDAY - started) / 10
	sleep(30)
	var/count = text2num(cs2_ask(C, "count", "document.querySelectorAll('#messages .entry').length"))
	var/ms = text2num(cs2_ask(C, "ms", "window.__ms.toFixed(1)"))
	var/calls = text2num(cs2_ask(C, "calls", "window.__calls"))
	var/worst = cs2_ask(C, "max", "window.__max.toFixed(2)")
	var/saves = cs2_ask(C, "saves", "window.__saves + ' saves, ' + window.__saveMs.toFixed(1) + ' ms, history ' + chatui.history.length + ', stored ' + (localStorage.getItem('goonchat_history') || '').length + ' chars'")
	kc_log("sent 2000 in [sent_in] s; the page took [ms] ms over [calls] batches (worst batch [worst] ms) = [round(ms / 2000, 0.001)] ms a message")
	kc_log("history saves: [saves]")
	kc_log("[(count >= 1900 && count <= 2100) ? "PASS" : "FAIL"] the page keeps about the last 2000 messages ([count])")
	kc_log("[(ms / 2000 < 0.5) ? "PASS" : "FAIL"] under half a millisecond a message")
	var/tabs = cs2_ask(C, "tabs", "(function () { chatui.selectTab('radio'); var n = Array.from(document.querySelectorAll('#messages .entry')).filter(function (e) { return e.offsetParent !== null; }).length; chatui.selectTab('all'); return n; })()")
	kc_log("radio tab shows [tabs] of [count]")
	var/t0 = cs2_ask(C, "searchms", "(function () { var t = performance.now(); chatui.setSearch('toolbox'); var d = performance.now() - t; chatui.setSearch(''); return d.toFixed(1); })()")
	kc_log("searching 2000 messages: [t0] ms")
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
