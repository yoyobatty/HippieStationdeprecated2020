// Every tgui window on the map, opened by a crew member, the AI and a cyborg, headless. Not part of the game.
//
// Run:      tools/tgui_preview/run_tgui_preview.sh   (builds its own copy; hippiestation.dmb is left alone)
// Results:  data/tgui_preview/<interface>__<who>.json, the state each window's page would be sent, and
//           data/tgui_preview/results.txt, one line per object and viewer: OK, or the runtime its ui_interact()/ui_data() hit.
// render.py then puts each one through the real bundle in headless Edge for a picture, and says which ones the page itself failed on.
//
// What it catches that a compile and a lint don't: a window whose ui_data() runtimes for the AI (no hands, no Adjacent), a cyborg
// (a module in hand), or anybody at all; and with the pictures, a window that comes up blank or broken.

/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	if("tgui-dump" in world.params)
		sleep_offline_after_initializations = FALSE
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(run_tgui_dump))
	return ..()

#define TGUI_DUMP_DIR "data/tgui_preview/"

GLOBAL_DATUM(tgui_dump, /datum/tgui_dump)

/datum/tgui_dump
	var/list/lines = list()
	/// "[interface]__[who]" -> TRUE once written
	var/list/written = list()
	var/who = "crew"
	var/current_type
	var/opened = 0
	var/errors = 0

/// The window it would have opened: its state written out instead, the way get_json() builds it but with no client to ask.
/datum/tgui/open()
	var/datum/tgui_dump/D = GLOB.tgui_dump
	if(!D)
		return ..()
	D.capture(src)

/datum/tgui_dump/proc/capture(datum/tgui/ui)
	opened++
	var/key = "[ui.interface]__[who]"
	if(written[key])
		return
	written[key] = TRUE
	var/list/data
	var/list/static_data
	try
		data = ui.src_object.ui_data(ui.user)
		static_data = ui.src_object.ui_static_data(ui.user)
	catch(var/exception/e)
		errors++
		lines += "ERROR [current_type] as [who] ([ui.interface]): ui_data: [e] at [e.file]:[e.line]"
		return
	var/list/json = list()
	json["config"] = list("title" = ui.title, "status" = UI_INTERACTIVE, "screen" = ui.ui_screen, "style" = ui.style,
		"interface" = ui.interface, "fancy" = TRUE, "locked" = FALSE, "observer" = FALSE, "window" = "preview", "ref" = "preview",
		"width" = ui.width, "height" = ui.height, "who" = who, "type" = "[current_type]")
	if(!isnull(data))
		json["data"] = data
	if(!isnull(static_data))
		json["static_data"] = static_data
	var/text = json_encode(json)
	text = replacetext(text, "\proper", "")
	text = replacetext(text, "\improper", "")
	text2file(text, "[TGUI_DUMP_DIR][ui.interface]__[who].json")

/proc/run_tgui_dump()
	sleep(5 SECONDS)
	fdel(TGUI_DUMP_DIR)
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/deadline = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < deadline)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	var/datum/tgui_dump/D = new
	GLOB.tgui_dump = D
	D.run_all()
	GLOB.tgui_dump = null
	text2file(jointext(D.lines, "\n"), "[TGUI_DUMP_DIR]results.txt")
	log_world("TGUI DUMP: done, [D.opened] opened, [D.errors] errors")
	Master.Shutdown()
	qdel(world)

/datum/tgui_dump/proc/run_all()
	var/turf/start = get_turf(pick(SSjob.latejoin_trackers))
	// The crew member: everything's access, so the ID checks show what's behind them.
	var/mob/living/carbon/human/H = new(start)
	H.real_name = "Preview Crewman"
	H.name = H.real_name
	H.mind_initialize()
	H.mind.assigned_role = "Captain"
	var/obj/item/card/id/captains_spare/card = new(H)
	H.equip_to_slot_or_del(card, ITEM_SLOT_ID)
	var/mob/living/carbon/human/to_ai = new(start)
	to_ai.mind_initialize()
	to_ai.mind.assigned_role = "AI"
	var/mob/living/silicon/ai/A = to_ai.AIize(TRUE)
	var/mob/living/carbon/human/to_borg = new(start)
	to_borg.mind_initialize()
	to_borg.mind.assigned_role = "Cyborg"
	var/mob/living/silicon/robot/R = to_borg.Robotize(FALSE, TRUE)
	R.module.transform_to(/obj/item/robot_module/engineering)
	var/list/viewers = list("crew" = H, "ai" = A, "cyborg" = R)
	// One of each type on the map, then each viewer opens it.
	var/list/seen = list()
	var/list/targets = list()
	for(var/obj/O in world)
		if(seen[O.type] || !isturf(O.loc) || !is_station_level(O.z))
			continue
		seen[O.type] = TRUE
		targets += O
	lines += "[length(targets)] object types on the station"
	for(var/obj/O as anything in targets)
		if(QDELETED(O))
			continue
		current_type = O.type
		for(var/name in viewers)
			who = name
			var/mob/living/L = viewers[name]
			if(QDELETED(L))
				continue
			if(name != "ai")
				L.forceMove(get_turf(O))
			var/before = opened
			try
				O.ui_interact(L)
			catch(var/exception/e)
				errors++
				lines += "ERROR [O.type] as [name]: ui_interact: [e] at [e.file]:[e.line]"
				continue
			if(opened > before)
				lines += "OK [O.type] as [name]"
			SStgui.close_uis(O)
		CHECK_TICK
	lines += "[opened] windows opened, [errors] errors, [length(written)] interface/viewer pairs written"

#undef TGUI_DUMP_DIR
