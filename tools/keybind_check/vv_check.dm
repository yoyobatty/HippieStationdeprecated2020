// View Variables and the admin find tools with a real admin client: VV windows opened and navigated the way an admin clicks
// them (the page's own link handler), what the page shows read back from it, and pictures. Not part of the game:
//   HARNESS=vv_check.dm SENDER=shot.ps1 tools/keybind_check/run.sh vv
// Results in data/keycheck_vv.txt, pictures in data/previews/popup_vv_*.png.

GLOBAL_VAR_INIT(keycheck_running, FALSE)
GLOBAL_LIST_EMPTY(vc_probes)

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
			vv_check_run(src)

/client/Topic(href, href_list, hsrc)
	if(href_list["probe"])
		GLOB.vc_probes[href_list["probe"]] = href_list["value"]
		return
	return ..()

/proc/vc_check(name, ok, detail = "")
	kc_log("[ok ? "PASS" : "FAIL"] [name][detail ? " ([detail])" : ""]")

/// A picture of the biggest popup (VV pages have no caption on 516)
/proc/vc_shot(name)
	fdel("data/keycheck_shot_title")
	text2file("popup_vv_[name]", "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/// Runs js in a browse() window. No square brackets: DM reads them as embedded expressions.
/proc/vc_js(client/C, window, js)
	C << output(url_encode(js), "[window].browser:eval")

/// Asks a window's page for a value (a js expression) and waits for the answer
/proc/vc_ask(client/C, window, name, expr)
	GLOB.vc_probes -= name
	vc_js(C, window, "var vcv; try { vcv = String(" + expr + "); } catch (e) { vcv = 'error ' + e; } window.chrome.webview.postMessage('byond://?probe=[name]&value=' + encodeURIComponent(vcv));")
	var/deadline = world.time + 5 SECONDS
	while(!(name in GLOB.vc_probes) && world.time < deadline)
		sleep(1)
	return GLOB.vc_probes[name]

/// Clicks the first link in a window whose text starts with this, through the page's own handler (shift: a new window)
/proc/vc_click(client/C, window, text, shift = FALSE)
	vc_js(C, window, "var t=[json_encode(text)];var a=Array.prototype.slice.call(document.querySelectorAll('a')).filter(function(e){return e.textContent.trim().indexOf(t)===0;})\[0\];if(a){a.dispatchEvent(new MouseEvent('click',{bubbles:true,cancelable:true,shiftKey:[shift ? "true" : "false"]}));}")

/// The window showing D now, waiting a little for a page to land
/proc/vc_window_of(client/C, datum/D)
	var/deadline = world.time + 5 SECONDS
	while(world.time < deadline)
		var/list/ids = C.vv_windows_showing(D)
		if(length(ids))
			return ids[1]
		sleep(1)

/proc/vv_check_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(3 SECONDS)
	var/turf/home = get_turf(pick(SSjob.latejoin_trackers))
	var/mob/living/carbon/human/H = new(home)
	H.mind_initialize()
	H.fully_replace_character_name(null, "Alex Admin")
	H.equipOutfit(/datum/outfit/job/assistant)
	H.ckey = C.ckey
	sleep(3 SECONDS)
	if(!C.holder)
		var/datum/admins/A = new(new /datum/admin_rank("!localhost!", R_EVERYTHING, R_DBRANKS, R_EVERYTHING), C.ckey, 1, 1)
		A.associate(C)
	sleep(2 SECONDS)
	usr = H
	vv_check_windows(C, H)
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)

/// One window: references open in it, Back and Forward, shift-click for a new one, where a thing is, an edit shown in place
/proc/vv_check_windows(client/C, mob/living/carbon/human/H)
	var/mob/living/carbon/human/bob = new(get_step(H, EAST))
	bob.fully_replace_character_name(null, "Bob Carrier")
	bob.equipOutfit(/datum/outfit/job/assistant)
	var/obj/item/storage/box/box = new(bob)
	bob.equip_to_slot_or_del(box, ITEM_SLOT_BACKPACK)
	var/obj/item/pen/pen = new(box)
	var/started = world.timeofday
	C.debug_variables(pen)
	var/window = vc_window_of(C, pen)
	// How long the page takes to answer at all (516 stalls some pages on files they ask for while those are still arriving)
	var/answered
	for(var/i in 1 to 30)
		GLOB.vc_probes -= "ready"
		vc_js(C, window, "window.chrome.webview.postMessage('byond://?probe=ready&value=' + encodeURIComponent(document.readyState + ' ' + performance.getEntriesByType('resource').map(function (r) { return r.name.split('/').pop() + '=' + Math.round(r.duration) + 'ms'; }).join(' ')));")
		sleep(5)
		if(GLOB.vc_probes["ready"])
			answered = GLOB.vc_probes["ready"]
			break
	kc_log("page answers after [(world.timeofday - started) / 10] s: [answered]")
	var/loaded = vc_ask(C, window, "loaded", "document.getElementById('vars').children.length")
	vc_check("a pen's VV page comes up ([window], [text2num(loaded)] vars, [(world.timeofday - started) / 10] s)", window && text2num(loaded) > 10)
	var/where = vc_ask(C, window, "where", "document.body.innerText.split('In:')\[1\].split('\\n')\[0\]")
	var/area/bob_area = get_area(bob)
	vc_check("it says where the pen is: area, turf, Bob, his backpack, the box ([where])", findtext(where, bob.name) && findtext(where, box.name) && findtext(where, bob_area.name))
	var/carried = vc_ask(C, window, "carried", "document.body.innerText.indexOf('Carried by: [bob]') != -1")
	vc_check("and who's carrying it", carried == "true")
	sleep(10)
	vc_shot("where")

	// The box, from the pen's page: same window
	vc_click(C, window, box.name)
	sleep(15)
	var/list/showing = C.vv_windows_showing(box)
	vc_check("clicking the box opens it in the same window ([showing.Join(",")])", length(showing) == 1 && showing[1] == window && !length(C.vv_windows_showing(pen)))
	var/datum/vv_window/W = C.vv_windows[window]
	vc_check("the window has the pen then the box ([W.history.len] pages)", W.history.len == 2 && W.index == 2)
	vc_click(C, window, "< Back")
	sleep(15)
	vc_check("Back shows the pen again", length(C.vv_windows_showing(pen)) == 1 && W.index == 1)
	vc_click(C, window, "Forward >")
	sleep(15)
	vc_check("Forward, the box", length(C.vv_windows_showing(box)) == 1 && W.index == 2)
	// Shift-click Bob: a window of his own
	vc_click(C, window, bob.name, shift = TRUE)
	sleep(20)
	var/list/bob_windows = C.vv_windows_showing(bob)
	vc_check("shift-clicking Bob opens a new window ([length(C.vv_windows)] windows)", length(bob_windows) == 1 && bob_windows[1] != window)
	// A page of a deleted thing drops out of the history
	vc_click(C, window, "< Back")
	sleep(15)
	vc_click(C, window, box.name)
	sleep(15)
	var/obj/item/pen/gone = new(box)
	C.vv_show(gone, window)
	sleep(10)
	qdel(gone)
	vc_click(C, window, "< Back")
	sleep(15)
	vc_check("Back past a deleted pen lands on the box", length(C.vv_windows_showing(box)) == 1)

	// An edit shows in its row without a refresh
	C.vv_show(pen, window)
	sleep(15)
	pen.name = "edited pen"
	pen.vv_edit_var("desc", "Edited by the harness.")
	C.vv_refresh_var(pen, "desc")
	sleep(10)
	var/row = vc_ask(C, window, "row", "document.getElementById('vvar_desc').innerText")
	vc_check("an edited var's row shows its new value ([row])", findtext(row, "Edited by the harness."))
	for(var/id in C.vv_windows)
		C << browse(null, "window=[id]")
	qdel(pen)
	qdel(bob)
