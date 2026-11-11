// Can a page be loaded into a window that stays hidden until it's wanted? Two ways, with a real client (BYOND 516):
// A: browse() a popup with is-visible=false among its options. B: winclone() a blank window, give it a browser control with winset,
// browse() into that. For each: is it hidden after loading, did the page load (it posts back), and how it looks once shown.
// Not part of the game: HARNESS=tgui_pool_probe.dm SENDER=shot.ps1 tools/keybind_check/run.sh pool_probe

GLOBAL_VAR_INIT(keycheck_running, FALSE)
GLOBAL_LIST_EMPTY(tpp_probes)

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
		spawn(30)
			tgui_pool_probe_run(src)

/client/Topic(href, href_list, hsrc)
	if(href_list["probe"])
		GLOB.tpp_probes[href_list["probe"]] = href_list["value"]
		return
	return ..()

/proc/tpp_page(label)
	return {"<!DOCTYPE html><html><head><meta charset="utf-8"></head><body style="background:#252525;color:#fff;font:16px sans-serif">
<h2>Pool window [label]</h2><p id="t"></p>
<script>window.chrome.webview.postMessage('byond://?probe=[label]&value=loaded%20' + Math.round(performance.now()));</script>
</body></html>"}

/proc/tpp_wait(label, ds)
	var/deadline = world.time + ds
	while(isnull(GLOB.tpp_probes[label]) && world.time < deadline)
		sleep(1)
	return GLOB.tpp_probes[label]

/proc/tpp_shot(name, title)
	text2file(title, "data/keycheck_shot_title")
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	fdel("data/keycheck_shot_title")
	sleep(2)

/proc/tpp_state(client/C, id)
	return "exists [winexists(C, id) || "no"], [winget(C, id, "is-visible;size;pos;titlebar;can-resize")]"

/proc/tgui_pool_probe_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	text2file("go", "data/keycheck_sendkeys") // starts shot.ps1

	// A: a popup asked to be hidden
	C << browse(tpp_page("A"), "window=tgpoolA;is-visible=false;size=410x310;can_minimize=0;titlebar=0;can_resize=0")
	var/loaded = tpp_wait("A", 5 SECONDS)
	kc_log("A browse is-visible=false: page [loaded || "never loaded"]; [tpp_state(C, "tgpoolA")]; browser [winexists(C, "tgpoolA.browser") || "none"]")
	sleep(5)
	kc_log("A half a second on: [tpp_state(C, "tgpoolA")]")
	tpp_shot("popup_pool_A_hidden", "410x310")
	winset(C, "tgpoolA", "is-visible=true")
	sleep(5)
	kc_log("A shown: [tpp_state(C, "tgpoolA")]")
	tpp_shot("popup_pool_A_shown", "410x310")
	winset(C, "tgpoolA", "is-visible=false")
	sleep(5)
	kc_log("A hidden again: [tpp_state(C, "tgpoolA")]")

	// B: a blank window from winclone, a browser put in it
	winclone(C, "window", "tgpoolB")
	winset(C, "tgpoolB", "size=430x330;titlebar=false;can-resize=false;can-minimize=false;statusbar=false")
	winset(C, "tgpoolB_browser", "parent=tgpoolB;type=browser;pos=0,0;size=430x330;anchor1=0,0;anchor2=100,100")
	kc_log("B made: [tpp_state(C, "tgpoolB")]; browser [winexists(C, "tgpoolB_browser") || "none"]")
	C << browse(tpp_page("B"), "window=tgpoolB_browser")
	loaded = tpp_wait("B", 5 SECONDS)
	kc_log("B browse into its browser: page [loaded || "never loaded"]; [tpp_state(C, "tgpoolB")]")
	tpp_shot("popup_pool_B_hidden", "430x330")
	winset(C, "tgpoolB", "is-visible=true")
	sleep(5)
	kc_log("B shown: [tpp_state(C, "tgpoolB")]")
	tpp_shot("popup_pool_B_shown", "430x330")
	// output() into it while shown, as an update would be
	GLOB.tpp_probes -= "B2"
	C << output(url_encode("window.chrome.webview.postMessage('byond://?probe=B2&value=eval%20ok');"), "tgpoolB_browser:eval")
	kc_log("B eval: [tpp_wait("B2", 3 SECONDS) || "no answer"]")
	winset(C, "tgpoolB", "is-visible=false")
	sleep(5)
	kc_log("B hidden again: [tpp_state(C, "tgpoolB")]")

	text2file("done", "data/keycheck_shots_done")
	kc_log("done")
