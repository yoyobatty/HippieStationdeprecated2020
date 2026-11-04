// Pictures of the autolathe's window with a real client, the old browse() one and the tgui one, and checks of what it takes in.
// Not part of the game: HARNESS=autolathe_shots.dm SENDER=shot.ps1 tools/keybind_check/run.sh lathe
// Pictures in data/previews/popup_autolathe_*.png, results in data/keycheck_lathe.txt. The old window is still there in the old
// procs (main_win(), category_win(), search_win()): it's opened from them for the "before" pictures.

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
			lathe_shots_run(src)

/proc/lathe_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/proc/lathe_check(name, ok, detail = "")
	kc_log("[ok ? "PASS" : "FAIL"] [name][detail ? " ([detail])" : ""]")

/proc/lathe_metal(obj/machinery/autolathe/lathe)
	var/datum/component/material_container/mats = lathe.GetComponent(/datum/component/material_container)
	return mats.amount(MAT_METAL)

/// What goes in and what doesn't, with a mob that has no client: the prompt can't be answered, which counts as "Keep it".
/proc/lathe_input_checks(turf/at)
	var/mob/living/carbon/human/T = new(at)
	T.equipOutfit(/datum/outfit/job/engineer)
	var/obj/machinery/autolathe/lathe = new(get_step(at, EAST))
	T.a_intent = INTENT_HELP

	var/obj/item/wrench/W = new(at)
	T.put_in_active_hand(W)
	var/before = lathe_metal(lathe)
	lathe.attackby(W, T)
	sleep(2)
	lathe_check("a wrench on help intent asks first, and isn't taken without a yes", !QDELETED(W) && T.get_active_held_item() == W && lathe_metal(lathe) == before, "metal [before] -> [lathe_metal(lathe)]")
	qdel(W)

	var/obj/item/stack/sheet/metal/M = new(at, 5)
	T.put_in_active_hand(M)
	before = lathe_metal(lathe)
	lathe.attackby(M, T)
	sleep(2)
	lathe_check("metal sheets go straight in", lathe_metal(lathe) == before + 5 * MINERAL_MATERIAL_AMOUNT, "metal [before] -> [lathe_metal(lathe)]")

	var/obj/item/screwdriver/S = new(at)
	T.put_in_active_hand(S)
	lathe.attackby(S, T)
	sleep(2)
	lathe_check("a screwdriver opens the panel, no question", lathe.panel_open && !QDELETED(S))
	lathe.attackby(S, T)
	qdel(S)

	var/obj/item/wrench/H = new(at)
	T.put_in_active_hand(H)
	T.a_intent = INTENT_HARM
	before = lathe_metal(lathe)
	lathe.attackby(H, T)
	sleep(2)
	lathe_check("on harm intent it's a hit, nothing goes in", !QDELETED(H) && lathe_metal(lathe) == before)
	qdel(H)
	qdel(lathe)
	qdel(T)

/// ui_act() bails unless the window's interactive: a window that only says it is.
/datum/tgui/lathe_stub/New()
	status = UI_INTERACTIVE

/// The queue and the eject buttons, through ui_act as the window sends them.
/proc/lathe_act_checks(obj/machinery/autolathe/lathe, mob/user)
	var/datum/tgui/lathe_stub/stub = new
	var/datum/design/rods
	var/datum/design/wrench
	for(var/id in lathe.stored_research.researched_designs)
		var/datum/design/D = SSresearch.techweb_design_by_id(id)
		if(D.build_path == /obj/item/stack/rods)
			rods = D
		if(D.build_path == /obj/item/wrench)
			wrench = D
	usr = user
	var/turf/out = lathe.drop_location()
	var/wrenches_before = 0
	for(var/obj/item/wrench/W in out)
		wrenches_before++
	lathe.ui_act("print", list("id" = wrench.id, "amount" = "1"), stub, GLOB.default_state)
	lathe.ui_act("print", list("id" = wrench.id, "amount" = "2"), stub, GLOB.default_state)
	lathe.ui_act("print", list("id" = rods.id, "amount" = "25"), stub, GLOB.default_state)
	lathe_check("printing while it's busy queues", length(lathe.build_queue) == 2, "queue [length(lathe.build_queue)]")
	var/deadline = world.time + 30 SECONDS
	while((lathe.busy || length(lathe.build_queue)) && world.time < deadline)
		sleep(5)
	var/wrenches = -wrenches_before
	for(var/obj/item/wrench/W in out)
		wrenches++
	var/obj/item/stack/rods/R = locate() in out
	lathe_check("the queue runs through: 3 wrenches and 25 rods", wrenches == 3 && R?.amount >= 25, "wrenches [wrenches], rods [R?.amount]")
	var/datum/component/material_container/mats = lathe.GetComponent(/datum/component/material_container)
	var/sheets_before = 0
	for(var/obj/item/stack/sheet/glass/G in out)
		sheets_before += G.amount
	lathe.ui_act("eject_sheets", list("mat" = MAT_GLASS, "amount" = "1"), stub, GLOB.default_state)
	var/sheets = -sheets_before
	for(var/obj/item/stack/sheet/glass/G in out)
		sheets += G.amount
	lathe_check("eject gives a sheet of glass back", sheets == 1, "glass sheets out [sheets], left [mats.amount(MAT_GLASS)]")

/proc/lathe_shots_run(client/C)
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
	H.equipOutfit(/datum/outfit/job/engineer)
	H.ckey = C.ckey
	sleep(3 SECONDS)
	var/obj/machinery/autolathe/lathe = new(get_step(H, EAST))
	lathe.stat &= ~(NOPOWER|BROKEN)
	var/datum/component/material_container/mats = lathe.GetComponent(/datum/component/material_container)
	mats.insert_amount(40000, MAT_METAL)
	mats.insert_amount(15000, MAT_GLASS)

	// Before: the old window, from its own procs
	var/list/old_pages = list(
		list("1_menu", lathe.main_win(H)),
		list("2_tools", lathe.category_win(H, "Tools")),
	)
	lathe.matching_designs.Cut()
	for(var/id in lathe.stored_research.researched_designs)
		var/datum/design/D = SSresearch.techweb_design_by_id(id)
		if(findtext(D.name, "rod"))
			lathe.matching_designs += D
	old_pages += list(list("3_search_rod", lathe.search_win(H)))
	for(var/list/page in old_pages)
		var/datum/browser/popup = new(H, "autolathe", lathe.name, 400, 500)
		popup.set_content(page[2])
		popup.open()
		winset(C, "autolathe", "pos=200,100")
		sleep(10)
		lathe_shot("popup_autolathe_before_[page[1]]")
	H << browse(null, "window=autolathe")
	sleep(5)

	// After: the tgui window
	lathe.ui_interact(H)
	sleep(4 SECONDS)
	var/datum/tgui/ui
	for(var/datum/tgui/open as anything in H.open_uis)
		if(open.src_object == lathe)
			ui = open
	kc_log("tgui window [ui ? "open" : "missing"]")
	if(ui)
		winset(C, ui.window_id, "pos=200,100")
		var/list/steps = list(
			list("1_all", list()),
			list("2_tools", list("click:Tools")),
			list("3_search_rod", list("search:rod")),
			list("4_print_and_queue", list("search:wrench", "click:Print", "click:Queue", "click:x5")),
		)
		for(var/list/step in steps)
			for(var/action in step[2])
				lathe_tgui_do(C, ui.window_id, action)
				sleep(4)
			sleep(10)
			lathe_shot("popup_autolathe_after_[step[1]]")
		lathe.adjust_hacked(TRUE)
		lathe_tgui_do(C, ui.window_id, "search:")
		sleep(4)
		lathe_tgui_do(C, ui.window_id, "click:Security")
		sleep(15)
		lathe_shot("popup_autolathe_after_5_hacked_security")
		lathe.disabled = TRUE
		sleep(15)
		lathe_shot("popup_autolathe_after_6_wire_cut")
		lathe.disabled = FALSE
		lathe.adjust_hacked(FALSE)
	SStgui.close_user_uis(H)
	var/deadline = world.time + 30 SECONDS
	while((lathe.busy || length(lathe.build_queue)) && world.time < deadline)
		sleep(5)
	lathe_act_checks(lathe, H)
	lathe_input_checks(get_step(get_step(home, SOUTH), SOUTH))

	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)

/// One click or keystroke on a tgui page, from script: "click:<text>" presses the first button whose text starts with it,
/// "search:<text>" types in the search box.
/proc/lathe_tgui_do(client/C, window_id, action)
	var/js
	if(findtext(action, "click:") == 1)
		var/text = copytext(action, 7)
		js = "var t=[json_encode(text)];var b=Array.prototype.slice.call(document.querySelectorAll('.Button, .Tabs__tab, \[style*=\"cursor\"\]')).filter(function(e){return e.textContent.trim().indexOf(t)===0;})\[0\];if(b){b.click();}"
	else if(findtext(action, "search:") == 1)
		var/text = copytext(action, 8)
		js = "var i=document.querySelector('input');if(i){i.value=[json_encode(text)];i.dispatchEvent(new Event('input',{bubbles:true}));}"
	if(js)
		C << output(url_encode(js), "[window_id].browser:eval")
