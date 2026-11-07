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
	vv_check_changes(C, H)
	vv_check_internals(C, H)
	vv_check_inline(C, H)
	vv_check_logs(C, H)
	vv_check_gaps(C, H)
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

/// Changed from default and edited: the marks, the page's own undo and default links, the Changed / Edited boxes
/proc/vv_check_changes(client/C, mob/living/carbon/human/H)
	var/obj/item/pen/pen = new(get_turf(H))
	pen.throwforce = 13 // set by the game, not an admin: changed, not edited
	var/old_name = pen.name
	vv_note_edit(pen, "name", pen.name, C) // what modify_variables() notes when an admin edits it
	pen.vv_edit_var("name", "renamed pen")
	C.debug_variables(pen)
	var/window = vc_window_of(C, pen)
	sleep(15)
	var/marks = vc_ask(C, window, "marks", "(document.getElementById('vvar_throwforce').getAttribute('data-changed') || '-') + ' ' + (document.getElementById('vvar_name').getAttribute('data-edited') || '-') + ' ' + (document.getElementById('vvar_force').getAttribute('data-changed') || '-')")
	vc_check("throwforce is marked changed, name edited, force (its default) neither ([marks])", marks == "1 1 -")
	var/counts = vc_ask(C, window, "counts", "document.body.innerText.match(/\\d+ edited, \\d+ changed from default/)")
	vc_check("the header counts them ([counts])", findtext(counts, "1 edited"))
	// Only the changed ones
	vc_js(C, window, "document.getElementById('only_changed').click();")
	sleep(5)
	var/shown = vc_ask(C, window, "shown", "document.getElementById('vars').children.length + ' of ' + complete_list.length + ', all changed: ' + Array.prototype.every.call(document.getElementById('vars').children, function (li) { return li.getAttribute('data-changed'); })")
	vc_check("the Changed box shows only changed vars ([shown])", findtext(shown, "all changed: true") && text2num(shown) < 40)
	vc_shot("changed")
	vc_js(C, window, "document.getElementById('only_changed').click();")
	sleep(5)
	// undo, through the page's link
	vc_js(C, window, "var a = document.querySelector('#vvar_name a\[href*=vvundo\]'); if (a) a.click();")
	sleep(15)
	vc_check("undo puts the name back ([pen.name])", pen.name == old_name && !length(LAZYACCESS(pen.vv_edits, "name")))
	var/row = vc_ask(C, window, "namerow", "document.getElementById('vvar_name').innerText + ' / ' + (document.getElementById('vvar_name').getAttribute('data-edited') || 'not edited')")
	vc_check("and its row says so ([row])", findtext(row, old_name) && findtext(row, "not edited"))
	// default, through the page's link
	vc_js(C, window, "var a = document.querySelector('#vvar_throwforce a\[href*=vvdefault\]'); if (a) a.click();")
	sleep(15)
	vc_check("default puts throwforce back ([pen.throwforce])", pen.throwforce == initial(pen.throwforce))
	vc_check("and that can be undone too", length(LAZYACCESS(pen.vv_edits, "throwforce")) == 1)
	for(var/id in C.vv_windows)
		C << browse(null, "window=[id]")
	qdel(pen)

/// The internals: a human's traits, timers, status effects and signals; a machine's subsystem; open or shut carried over
/proc/vv_check_internals(client/C, mob/living/carbon/human/H)
	var/mob/living/carbon/human/bob = new(get_step(H, EAST))
	bob.fully_replace_character_name(null, "Bob Internals")
	bob.equipOutfit(/datum/outfit/job/assistant)
	ADD_TRAIT(bob, TRAIT_NODEATH, "vv_check")
	addtimer(CALLBACK(bob, TYPE_PROC_REF(/atom, drop_location)), 2 MINUTES)
	bob.Stun(600)
	C.debug_variables(bob)
	var/window = vc_window_of(C, bob)
	sleep(15)
	var/summary = vc_ask(C, window, "summary", "document.querySelector('#vv_internals summary').innerText")
	vc_check("Bob's internals line counts traits, timers, status effects and signals ([summary])", findtext(summary, "trait") && findtext(summary, "timer") && findtext(summary, "status effect") && findtext(summary, "listen"))
	vc_js(C, window, "document.querySelector('#vv_internals summary').click();")
	sleep(5)
	var/inside = vc_ask(C, window, "inside", "document.getElementById('vv_internals').innerText")
	vc_check("opened: the trait with its source, the stun, the timer's proc", findtext(inside, "TRAIT_NODEATH") || findtext(inside, "nodeath") ? (findtext(inside, "vv_check") && findtext(inside, "stun") && findtext(inside, "drop_location")) : FALSE, copytext(inside, 1, 300))
	vc_shot("internals")
	// Open stays open on the next page
	var/obj/machinery/power/apc/apc = locate() in GLOB.machines
	C.vv_show(apc, window)
	sleep(15)
	var/open = vc_ask(C, window, "open", "document.getElementById('vv_internals') ? document.getElementById('vv_internals').open : 'none'")
	vc_check("the next page's internals are open too ([open])", open == "true")
	var/apc_line = vc_ask(C, window, "apcline", "document.querySelector('#vv_internals summary').innerText")
	vc_check("an APC is processed by Machines ([apc_line])", findtext(apc_line, "processed by") && findtext(apc_line, "Machines"))
	vc_js(C, window, "document.querySelector('#vv_internals summary').click();")
	sleep(5)
	for(var/id in C.vv_windows)
		C << browse(null, "window=[id]")
	qdel(bob)

/// Opens the editor of a var's row and types into it; Enter
/proc/vc_inline(client/C, window, var_name, value)
	vc_js(C, window, "var v = document.querySelector('#vvar_[var_name] .vvv'); if (v) v.click(); var ed = document.querySelector('.vve'); if (ed) { var f = ed.querySelector('input\[type=text\], textarea'); if (f) f.value = [json_encode(value)]; ed.onkeydown({ keyCode: 13, shiftKey: false }); }")
	sleep(15)

/// The editor in place of E/C/M: a number, text, flags, the direction compass, a type path, null, every pen at once; watch
/proc/vv_check_inline(client/C, mob/living/carbon/human/H)
	var/obj/item/pen/pen = new(get_turf(H))
	var/obj/item/pen/pen2 = new(get_turf(H))
	var/obj/item/pen/blue/blue = new(get_turf(H))
	var/obj/item/storage/box/box = new(get_turf(H))
	C.debug_variables(pen)
	var/window = vc_window_of(C, pen)
	sleep(15)
	var/no_ecm = vc_ask(C, window, "noecm", "document.querySelectorAll('#vars > li').length + ' rows, ' + Array.prototype.filter.call(document.querySelectorAll('#vars > li'), function (li) { return li.innerText.indexOf('(E) (C) (M)') == 0; }).length + ' with E/C/M'")
	vc_check("no row has E/C/M any more ([no_ecm])", findtext(no_ecm, " 0 with E/C/M"))
	// the editor, opened for the picture
	vc_js(C, window, "document.querySelector('#vvar_resistance_flags .vvv').click();")
	sleep(5)
	vc_shot("editor_flags")
	vc_js(C, window, "var ed = document.querySelector('.vve'); var boxes = ed.querySelectorAll('input\[type=checkbox\]'); for (var i = 0; i < boxes.length; i++) if (boxes\[i\].parentNode.textContent.indexOf('FIRE_PROOF') != -1) boxes\[i\].checked = true; ed.querySelectorAll('button')\[0\].click();")
	sleep(15)
	vc_check("flags: FIRE_PROOF ticked and set ([pen.resistance_flags])", pen.resistance_flags & FIRE_PROOF)
	vc_inline(C, window, "throwforce", "7")
	vc_check("a number typed and Enter ([pen.throwforce])", pen.throwforce == 7 && length(LAZYACCESS(pen.vv_edits, "throwforce")) == 1)
	var/row = vc_ask(C, window, "row", "document.getElementById('vvar_throwforce').innerText")
	vc_check("its row shows it, marked edited ([row])", findtext(row, "throwforce = 7") && findtext(row, "edited"))
	vc_inline(C, window, "name", "inline pen")
	vc_check("text ([pen.name])", pen.name == "inline pen")
	vc_inline(C, window, "throwforce", "seven")
	vc_check("a number field won't take words ([pen.throwforce])", pen.throwforce == 7)
	vc_js(C, window, "document.querySelector('#vvar_dir .vvv').click();")
	sleep(5)
	vc_shot("editor_dir")
	vc_js(C, window, "var bs = document.querySelectorAll('.vve .vvc button'); for (var i = 0; i < bs.length; i++) if (bs\[i\].textContent == 'E') bs\[i\].click();")
	sleep(15)
	vc_check("dir: the compass's E ([pen.dir])", pen.dir == EAST)
	vc_js(C, window, "var v = document.querySelector('#vvar_desc .vvv'); v.click(); var ed = document.querySelector('.vve'); ed.querySelector('select').value = 'null'; ed.querySelectorAll('button')\[0\].click();")
	sleep(15)
	vc_check("null from the type list ([isnull(pen.desc) ? "null" : pen.desc])", isnull(pen.desc))
	// all of exactly this type
	vc_js(C, window, "var v = document.querySelector('#vvar_throwforce .vvv'); v.click(); var ed = document.querySelector('.vve'); ed.querySelector('input\[type=text\]').value = '5'; ed.querySelector('input\[type=checkbox\]').checked = true; ed.querySelectorAll('button')\[0\].click();")
	sleep(20)
	vc_check("all /obj/item/pen: both pens, not the blue one ([pen.throwforce], [pen2.throwforce], blue [blue.throwforce])", pen.throwforce == 5 && pen2.throwforce == 5 && blue.throwforce != 5)

	// a type path, on a box
	C.vv_show(box, window)
	sleep(15)
	vc_inline(C, window, "foldable", "/obj/item/stack/sheet/metal")
	vc_check("a type path ([box.foldable])", box.foldable == /obj/item/stack/sheet/metal)
	vc_inline(C, window, "foldable", "/obj/item/no_such_thing")
	vc_check("not a type: refused ([box.foldable])", box.foldable == /obj/item/stack/sheet/metal)

	// Watching, through the row's own link
	C.vv_show(pen, window)
	sleep(15)
	var/datum/vv_window/W = C.vv_windows[window]
	vc_js(C, window, "var a = document.querySelector('#vvar_throwforce a\[href*=vvwatch\]'); a.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));")
	sleep(15)
	vc_check("watch puts throwforce in the window's watch list", ("throwforce" in W.watching))
	pen.throwforce = 9
	sleep(25)
	var/box_text = vc_ask(C, window, "watchbox", "document.getElementById('vv_watch').style.display + '|' + document.getElementById('vv_watch_rows').innerText")
	vc_check("the Watching box shows it change without a reload ([box_text])", findtext(box_text, "throwforce = 9") && !findtext(box_text, "none|"))
	vc_shot("watching")
	vc_js(C, window, "var x = document.querySelector('#vv_watch_rows a'); x.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));")
	sleep(25)
	box_text = vc_ask(C, window, "watchbox2", "document.getElementById('vv_watch').style.display")
	vc_check("its x stops it ([box_text])", box_text == "none" && !length(W.watching))
	// watching, then the window closed
	vc_js(C, window, "var a = document.querySelector('#vvar_throwforce a\[href*=vvwatch\]'); a.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));")
	sleep(15)
	winset(C, window, "is-visible=false")
	C << browse(null, "window=[window]")
	sleep(60)
	vc_check("closing the window stops it ([length(C.vv_windows)] windows open, watcher has [length(GLOB.vv_watcher.windows)])", !(window in C.vv_windows) && !(W in GLOB.vv_watcher.windows))
	for(var/id in C.vv_windows)
		C << browse(null, "window=[id]")
	qdel(pen)
	qdel(pen2)
	qdel(blue)
	qdel(box)

/datum/tgui/vc_stub/New()
	status = UI_INTERACTIVE

/proc/vc_act(datum/src_object, mob/user, action, list/params = list())
	var/datum/tgui/vc_stub/stub = new
	usr = user
	return src_object.ui_act(action, params, stub, GLOB.admin_state)

/proc/vc_find_ui(mob/user, datum/src_object)
	var/deadline = world.time + 15 SECONDS
	while(world.time < deadline)
		for(var/datum/tgui/open as anything in user.open_uis)
			if(open.src_object == src_object && open.initialized)
				return open
		sleep(2)

/// The round log and Search Logs: lines caught with who and where, a death with who last hurt them, the quick starts, a
/// player, words with |, a player panel's SEARCH LOGS, a line's VV button
/proc/vv_check_logs(client/C, mob/living/carbon/human/H)
	var/mob/living/carbon/human/bob = new(get_step(H, EAST))
	bob.fully_replace_character_name(null, "Bob Logger")
	bob.equipOutfit(/datum/outfit/job/assistant)
	var/mob/living/carbon/human/alice = new(get_step(H, WEST))
	alice.fully_replace_character_name(null, "Alice Logged")
	var/mob/living/carbon/monkey/monkey = new(get_step(H, NORTH))
	monkey.mind_initialize()
	var/before = GLOB.round_log_total
	log_combat(bob, alice, "punched")
	log_combat(bob, monkey, "kicked")
	monkey.death()
	bob.say("the harness was here")
	var/obj/item/grenade/chem_grenade/grenade = new(get_turf(bob))
	log_bomber(bob, "has primed a", grenade, message_admins = FALSE)
	grenade.investigate_log("was tested by the harness", INVESTIGATE_ATMOS)
	log_admin("Harness admin did an admin thing")
	sleep(10)
	var/list/kinds = list()
	var/list/attack_entry
	var/list/death_entry
	for(var/list/entry in GLOB.round_log)
		if(entry[RL_ID] <= before)
			continue
		kinds |= entry[RL_CAT]
		if(entry[RL_CAT] == "Attack" && findtext(entry[RL_TEXT], "punched") && !attack_entry)
			attack_entry = entry
		if(entry[RL_CAT] == "Death" && findtext(entry[RL_TEXT], "monkey"))
			death_entry = entry
	vc_check("lines come in as Attack, Death, Say, Bomb, Investigate: atmos and Admin ([kinds.Join(", ")])", ("Attack" in kinds) && ("Death" in kinds) && ("Say" in kinds) && ("Bomb" in kinds) && ("Investigate: atmos" in kinds) && ("Admin" in kinds))
	vc_check("an attack knows who and whom, and where ([attack_entry ? "[attack_entry[RL_NAME]] to [attack_entry[RL_TNAME]] in [attack_entry[RL_AREA]]" : "none"])", attack_entry && attack_entry[RL_NAME] == bob.name && attack_entry[RL_TNAME] == alice.name && attack_entry[RL_AREA])
	vc_check("a monkey's death is logged, with who last hurt it ([death_entry ? death_entry[RL_TEXT] : "none"])", death_entry && findtext(death_entry[RL_TEXT], "last hurt by") && findtext(death_entry[RL_TEXT], bob.name))
	var/said = 0
	for(var/list/entry in GLOB.round_log)
		if(entry[RL_ID] > before && findtext(entry[RL_TEXT], "the harness was here"))
			said++
	vc_check("a thing said is one line, not two ([said])", said == 1)

	// The window
	C.open_log_search()
	var/datum/log_search/LS = C.log_search
	var/datum/tgui/ui = vc_find_ui(H, LS)
	vc_check("Search Logs opens", ui)
	if(ui)
		winset(C, ui.window_id, "pos=20,10")
	vc_act(LS, H, "search", list("text" = "harness was here", "who" = "", "area" = "", "minutes" = "0"))
	vc_check("words find the line ([LS.matched])", LS.matched == 1 && findtext(LS.results[1][RL_TEXT], "harness was here"))
	vc_act(LS, H, "search", list("text" = "punched|primed", "who" = "", "area" = "", "minutes" = "0"))
	vc_check("a | b finds either ([LS.matched])", LS.matched >= 2)
	vc_act(LS, H, "search", list("text" = "", "who" = "Alice Logged", "area" = "", "minutes" = "5"))
	vc_check("a player finds lines on either side ([LS.matched], [LS.matched ? LS.results[1][RL_NAME] : "-"])", LS.matched >= 1 && LS.results[1][RL_TNAME] == alice.name)
	// a quick start, clicked in the page (a quick start keeps the player box: Clear first)
	vc_act(LS, H, "clear")
	vc_js(C, ui?.window_id, "var b = Array.prototype.slice.call(document.querySelectorAll('.Button')).filter(function (e) { return e.textContent.trim() == 'Deaths'; })\[0\]; if (b) b.click();")
	sleep(20)
	vc_check("the Deaths quick start, clicked ([LS.preset], [LS.matched] lines)", LS.preset == "Deaths" && LS.matched >= 1 && LS.results[1][RL_CAT] == "Death")
	vc_shot("logs_deaths")
	vc_act(LS, H, "preset", list("name" = "Fights"))
	sleep(15)
	vc_shot("logs_fights")
	// the kinds as chips
	vc_act(LS, H, "all_kinds")
	vc_act(LS, H, "kind", list("name" = "Bomb"))
	vc_check("the Bomb chip alone ([LS.matched])", LS.matched >= 1 && LS.results[1][RL_CAT] == "Bomb")
	// a player panel's SEARCH LOGS
	C.holder.Topic("searchlogs=[url_encode(bob.name)]", list("searchlogs" = bob.name, "admin_token" = C.holder.href_token))
	sleep(15)
	vc_check("a player panel's SEARCH LOGS shows that player's lines ([LS.who], [LS.matched])", LS.who == bob.name && LS.matched >= 3)
	sleep(10)
	vc_shot("logs_player")
	var/shown_who = vc_ask(C, ui?.window_id, "who", "document.querySelectorAll('.LogSearch__whoBox input')\[0\].value")
	vc_check("and its box says who ([shown_who])", shown_who == bob.name)
	// a line's VV button
	vc_act(LS, H, "vv", list("id" = "[LS.results[1][RL_ID]]"))
	sleep(15)
	vc_check("a line's VV opens who did it", length(C.vv_windows_showing(bob)) == 1)
	for(var/id in C.vv_windows)
		C << browse(null, "window=[id]")
	SStgui.close_user_uis(H)
	qdel(grenade)
	qdel(bob)
	qdel(alice)
	qdel(monkey)

/// The round log's newest line containing this, made after line number `after`
/proc/vc_logged(after, text)
	for(var/i in GLOB.round_log.len to 1 step -1)
		var/list/entry = GLOB.round_log[i]
		if(entry[RL_ID] <= after)
			break
		if(findtext(entry[RL_TEXT], text))
			return entry

/// Log gaps closed: the ID console, an APC's channels, a cell timer; and who touched a thing, in VV
/proc/vv_check_gaps(client/C, mob/living/carbon/human/H)
	var/turf/home = get_turf(H)
	var/start = GLOB.round_log_total
	// The ID console: access given, a job changed
	var/obj/machinery/computer/card/console = new(get_step(H, NORTH))
	console.stat &= ~(NOPOWER|BROKEN)
	var/obj/item/card/id/card = new(console)
	card.registered_name = "Carl Card"
	card.assignment = "Assistant"
	console.modify = card
	console.authenticated = 2
	usr = H
	console.Topic(null, list("choice" = "access", "access_target" = "[ACCESS_CAPTAIN]", "allowed" = "1"))
	var/list/gave = vc_logged(start, "gave Carl Card's ID")
	vc_check("the ID console logs access given ([gave ? gave[RL_TEXT] : "nothing"])", gave && gave[RL_CAT] == "Access" && findtext(gave[RL_TEXT], "Captain"))
	console.Topic(null, list("choice" = "assign", "assign_target" = "Clown"))
	var/list/job = vc_logged(start, "changed Carl Card's ID job")
	vc_check("and a job changed ([job ? job[RL_TEXT] : "nothing"])", job && findtext(job[RL_TEXT], "Clown"))
	qdel(console)
	// An APC's environment switched off
	var/obj/machinery/power/apc/apc = locate() in get_area(H)
	if(!apc)
		for(var/obj/machinery/power/apc/other in GLOB.apcs_list)
			if(other.z == H.z)
				apc = other
				break
	if(apc)
		H.forceMove(get_turf(apc))
		apc.locked = FALSE
		vc_act(apc, H, "channel", list("env" = "1"))
		var/list/env = vc_logged(start, "'s environment from")
		vc_check("an APC's environment switched off is logged ([env ? env[RL_TEXT] : "nothing"])", env && findtext(env[RL_TEXT], "to Off"))
		vc_act(apc, H, "channel", list("env" = "3"))
		H.forceMove(home)
	else
		vc_check("an APC to switch", FALSE)
	// A cell timer started, then stopped early
	var/obj/machinery/door_timer/timer = new(get_step(H, SOUTH))
	timer.stat &= ~(NOPOWER|BROKEN)
	timer.req_access = null
	timer.req_one_access = null
	timer.set_timer(3 MINUTES)
	vc_act(timer, H, "start")
	sleep(5)
	vc_act(timer, H, "stop")
	var/list/started = vc_logged(start, "started [timer]")
	var/list/stopped = vc_logged(start, "opened the cell with")
	vc_check("a cell timer started and stopped early are logged ([stopped ? stopped[RL_TEXT] : "nothing"])", started && stopped)
	qdel(timer)
	// Who touched it, in VV
	var/obj/item/pen/pen = new(home)
	pen.add_fingerprint(H)
	C.debug_variables(pen)
	var/window = vc_window_of(C, pen)
	sleep(15)
	var/touched = vc_ask(C, window, "touched", "document.body.innerText.match(/Touched by \[^\\n\]*/)")
	vc_check("VV says who touched it ([touched])", findtext(touched, "Touched by 1 player") && findtext(touched, H.ckey))
	vc_js(C, window, "document.querySelector('details summary').click();")
	sleep(5)
	vc_shot("touched")
	for(var/id in C.vv_windows)
		C << browse(null, "window=[id]")
	qdel(pen)
