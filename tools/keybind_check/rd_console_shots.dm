// Pictures of the R&D console with a real client, for a before and after: a lab set up round the console the way R&D has it, a few nodes
// researched and the lathe stocked, and the screens a player goes through, each a picture.
// Not part of the game: echo <label> > data/rd_shots_label; HARNESS=rd_console_shots.dm SENDER=shot.ps1 tools/keybind_check/run.sh rd
// Pictures in data/previews/popup_rd_<label>_*.png. The old console's screens are reached by its own links (Topic()), a tgui one's by
// clicking its tabs and typing in its search box from script (rd_tgui_steps).

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
			rd_shots_run(src)

/proc/rd_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/// For a tgui console: what's clicked or typed before each picture. "click:<text>" presses the first button or tab whose text starts with
/// it, "search:<text>" types in the search box, "wait" lets an update come through.
GLOBAL_LIST_INIT(rd_tgui_steps, list(
	list("1_available", list()),
	list("2_search_manipulator", list("search:manipulator")),
	list("3_path_to_bluespace_rped", list("search:applied bluespace", "click:Applied Bluespace Research")),
	list("4_researched", list("search:", "click:Researched")),
	list("5_protolathe", list("click:Protolathe")),
	list("6_print_and_queue", list("click:x10", "click:Queue", "click:Queue")),
	list("7_protolathe_search", list("search:stock parts")),
	list("8_imprinter", list("search:", "click:Imprinter")),
))

/proc/rd_shots_run(client/C)
	var/label = trim(file2text("data/rd_shots_label")) || "now"
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
	H.equipOutfit(/datum/outfit/job/scientist)
	H.ckey = C.ckey
	sleep(3 SECONDS)
	// The lab: the lathe, the imprinter and the analyzer round the console, linked as R&D's are (SyncRDevices(), within three tiles).
	var/turf/at = get_step(H, EAST)
	var/obj/machinery/rnd/production/protolathe/lathe = new(get_step(at, NORTH))
	var/obj/machinery/rnd/production/circuit_imprinter/imprinter = new(get_step(at, SOUTH))
	new /obj/machinery/rnd/destructive_analyzer(get_step(get_step(at, EAST), NORTH))
	var/obj/machinery/computer/rdconsole/core/console = new(at)
	for(var/obj/machinery/M in list(lathe, imprinter, console))
		M.stat &= ~(NOPOWER|BROKEN)
	var/datum/techweb/web = SSresearch.science_tech
	web.add_point_list(list(TECHWEB_POINT_TYPE_GENERIC = 12500))
	for(var/id in list("engineering", "datatheory", "high_efficiency", "adv_engi", "basic_tools"))
		if(SSresearch.techweb_node_by_id(id))
			web.research_node_id(id, TRUE)
	for(var/obj/machinery/rnd/production/P in list(lathe, imprinter))
		P.update_research()
		var/datum/component/material_container/mats = P.materials?.mat_container
		if(mats) //glass first: the imprinter's store is half the lathe's, and lives on glass
			mats.insert_amount(30000, MAT_GLASS)
			mats.insert_amount(8000, MAT_GOLD)
			mats.insert_amount(6000, MAT_SILVER)
			mats.insert_amount(60000, MAT_METAL)
	kc_log("round [SSticker.current_state], console [console] linked to [console.linked_lathe] / [console.linked_imprinter] / [console.linked_destroy]")
	console.ui_interact(H)
	sleep(4 SECONDS)
	var/datum/tgui/ui
	for(var/datum/tgui/open as anything in H.open_uis)
		if(open.src_object == console)
			ui = open
	if(ui)
		winset(C, ui.window_id, "pos=200,100")
		for(var/list/step in GLOB.rd_tgui_steps)
			for(var/action in step[2])
				rd_tgui_do(C, ui.window_id, action)
				sleep(4) //a click's update is back in well under that, and a ten-item print is still going
			sleep(10)
			rd_shot("popup_rd_[label]_[step[1]]")
		// A department techfab, worked at the machine itself: the Chief Engineer's.
		SStgui.close_user_uis(H)
		var/obj/machinery/rnd/production/techfab/department/engineering/fab = new(get_step(H, WEST))
		fab.stat &= ~(NOPOWER|BROKEN)
		fab.update_research()
		var/datum/component/material_container/fab_mats = fab.materials?.mat_container
		if(fab_mats)
			fab_mats.insert_amount(60000, MAT_METAL)
			fab_mats.insert_amount(40000, MAT_GLASS)
		fab.ui_interact(H)
		sleep(4 SECONDS)
		for(var/datum/tgui/open as anything in H.open_uis)
			if(open.src_object == fab)
				winset(C, open.window_id, "pos=200,100")
		sleep(5)
		rd_shot("popup_rd_[label]_9_engineering_techfab")
	else
		// The old browse() page: its own links.
		winset(C, "rndconsole", "pos=200,100")
		var/list/screens = list(
			list("1_menu", list()),
			list("2_technology", list("switch_screen" = "[RDSCREEN_TECHWEB]")),
			list("3_node", list("view_node" = "adv_power", "back_screen" = "[RDSCREEN_TECHWEB]")),
			list("4_protolathe", list("switch_screen" = "[RDSCREEN_PROTOLATHE]")),
			list("5_protolathe_parts", list("switch_screen" = "[RDSCREEN_PROTOLATHE_CATEGORY_VIEW]", "category" = "Stock Parts")),
			list("6_imprinter", list("switch_screen" = "[RDSCREEN_IMPRINTER]")),
		)
		for(var/list/screen in screens)
			if(length(screen[2]))
				usr = H
				console.Topic(null, screen[2])
				sleep(15)
			rd_shot("popup_rd_[label]_[screen[1]]")
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)

/// One click or keystroke on a tgui page, from script.
/proc/rd_tgui_do(client/C, window_id, action)
	var/js
	if(findtext(action, "click:") == 1)
		var/text = copytext(action, 7)
		js = "var t=[json_encode(text)];var b=Array.prototype.slice.call(document.querySelectorAll('.Button, .Tabs__tab, \[style*=\"cursor\"\]')).filter(function(e){return e.textContent.trim().indexOf(t)===0;})\[0\];if(b){b.click();}"
	else if(findtext(action, "search:") == 1)
		var/text = copytext(action, 8)
		js = "var i=document.querySelector('input');if(i){i.value=[json_encode(text)];i.dispatchEvent(new Event('input',{bubbles:true}));}"
	if(js)
		C << output(url_encode(js), "[window_id].browser:eval")
