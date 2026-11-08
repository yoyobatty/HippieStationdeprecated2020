// Pictures of the lathes' category sidebar with a real client (hippiestation/code/modules/research/design_groups.dm and
// FabricatorPanel in tgui-next's interfaces/RdConsole.js), and checks that the category and the hide toggle are remembered.
// Not part of the game: echo before|after > data/lathe_cat_label; HARNESS=lathe_category_shots.dm SENDER=shot.ps1 MAP=testbench tools/keybind_check/run.sh latcat
// Pictures in data/previews/popup_latcat_<label>_*.png, results in data/keycheck_latcat.txt.

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
			latcat_run(src)

/proc/latcat_label()
	var/label = trim(file2text("data/lathe_cat_label"))
	return label || "now"

/proc/latcat_shot(name)
	text2file("popup_latcat_[latcat_label()]_[name]", "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/proc/latcat_check(name, ok, detail = "")
	kc_log("[ok ? "PASS" : "FAIL"] [name][detail ? " ([detail])" : ""]")

/// One click or keystroke on a tgui page: "click:<text>" presses the first button whose text starts with it, "search:<text>" types
/// in the search box.
/proc/latcat_do(client/C, window_id, action)
	var/js
	if(findtext(action, "click:") == 1)
		var/text = copytext(action, 7)
		js = "var t=[json_encode(text)];var b=Array.prototype.slice.call(document.querySelectorAll('.Button, .Tabs__tab, \[style*=\"cursor\"\]')).filter(function(e){return e.textContent.trim().indexOf(t)===0;})\[0\];if(b){b.click();}"
	else if(findtext(action, "search:") == 1)
		var/text = copytext(action, 8)
		js = "var i=document.querySelector('input');if(i){i.value=[json_encode(text)];i.dispatchEvent(new Event('input',{bubbles:true}));}"
	if(js)
		C << output(url_encode(js), "[window_id].browser:eval")

/proc/latcat_window(mob/user, obj/machinery/M)
	for(var/datum/tgui/open as anything in user.open_uis)
		if(open.src_object == M)
			return open

/// Opens the machine's window, places it, runs the steps and takes a picture after each.
/proc/latcat_steps(client/C, mob/user, obj/machinery/M, prefix, list/steps)
	M.ui_interact(user)
	sleep(4 SECONDS)
	var/datum/tgui/ui = latcat_window(user, M)
	kc_log("[prefix] window [ui ? "open" : "missing"]")
	if(!ui)
		return
	winset(C, ui.window_id, "pos=120,60")
	for(var/list/step in steps)
		for(var/action in step[2])
			latcat_do(C, ui.window_id, action)
			sleep(4)
		sleep(12)
		kc_log("[prefix] [step[1]]: window status [ui.status], [M] stat [M.stat] at [M.x],[M.y] ([M.loc?.density ? "dense" : "clear"] tile), [get_dist(user, M)] tiles away")
		latcat_shot("[prefix]_[step[1]]")
	SStgui.close_uis(M)
	sleep(5)

/proc/latcat_fill(datum/component/material_container/mats)
	if(!mats)
		return
	mats.insert_amount(20 * MINERAL_MATERIAL_AMOUNT, MAT_GLASS) // glass first: the imprinter holds 38 sheets
	mats.insert_amount(10 * MINERAL_MATERIAL_AMOUNT, MAT_METAL)
	mats.insert_amount(4 * MINERAL_MATERIAL_AMOUNT, MAT_SILVER)
	mats.insert_amount(3 * MINERAL_MATERIAL_AMOUNT, MAT_GOLD)

/proc/latcat_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(3 SECONDS)
	// Everything researched, so every group has something in it
	for(var/id in SSresearch.techweb_nodes)
		SSresearch.science_tech.research_node_id(id, TRUE, FALSE)
	var/turf/home = get_turf(pick(SSjob.latejoin_trackers))
	var/mob/living/carbon/human/H = new(home)
	H.mind_initialize()
	H.equipOutfit(/datum/outfit/job/scientist)
	H.ckey = C.ckey
	sleep(3 SECONDS)

	var/obj/machinery/computer/rdconsole/console = new /obj/machinery/computer/rdconsole/core(get_step(H, NORTH))
	var/obj/machinery/rnd/production/protolathe/lathe = new(get_step(H, EAST))
	var/obj/machinery/rnd/production/circuit_imprinter/imprinter = new(get_step(H, WEST))
	for(var/obj/machinery/M in list(console, lathe, imprinter))
		M.stat &= ~(NOPOWER|BROKEN)
	console.linked_lathe = lathe
	lathe.linked_console = console
	console.linked_imprinter = imprinter
	imprinter.linked_console = console
	console.locked = FALSE
	lathe.update_research()
	imprinter.update_research()
	latcat_fill(lathe.materials?.mat_container)
	latcat_fill(imprinter.materials?.mat_container)
	imprinter.reagents.add_reagent(/datum/reagent/toxin/acid, 60) // boards take sulphuric acid

	latcat_steps(C, H, console, "console", list(
		list("1_lathe_all", list("click:Protolathe")),
		list("2_lathe_medical", list("click:Medical")),
		list("3_eject_open", list("click:Eject")),
		list("4_hide_unaffordable", list("click:Eject", "click:Hide unaffordable")),
		list("5_search_beaker", list("search:beaker")),
		list("6_imprinter_all", list("search:", "click:Imprinter")),
		list("7_imprinter_engineering", list("click:Engineering")),
	))
	var/list/prefs = lathe_panel_prefs(H)
	latcat_check("the console remembers the lathe's and imprinter's categories and the hide toggle", prefs["lathe"] == "Medical" && prefs["board"] == "Engineering" && prefs["hide"] == 1, json_encode(prefs))
	latcat_steps(C, H, console, "console", list(
		list("8_reopened_lathe", list("click:Protolathe")),
	))

	var/obj/machinery/rnd/production/techfab/department/medical/fab = new(get_step(H, SOUTH))
	fab.stat &= ~(NOPOWER|BROKEN)
	fab.update_research()
	latcat_fill(fab.materials?.mat_container)
	latcat_steps(C, H, fab, "techfab", list(
		list("1_opened", list()),
		list("2_all", list("click:Hide unaffordable", "click:All")),
	))

	qdel(fab) // its tile, next to the player: diagonally, behind the techfab and protolathe, the player isn't adjacent
	var/obj/machinery/autolathe/auto = new(get_step(H, SOUTH))
	auto.stat &= ~(NOPOWER|BROKEN)
	latcat_fill(auto.GetComponent(/datum/component/material_container))
	latcat_steps(C, H, auto, "autolathe", list(
		list("1_opened", list()),
		list("2_tools", list("click:Tools")),
	))
	prefs = lathe_panel_prefs(H)
	latcat_check("the autolathe's category is kept apart from the lathe's", prefs["autolathe"] == "Tools" && prefs["lathe"] == "", json_encode(prefs))

	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
