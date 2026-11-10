// The Bot Crew panel with a real client (hippiestation/code/modules/admin/bot_crew_panel.dm): eight bots spawned into a round, the
// panel opened as an admin, then one bot's row opened. Not part of the game:
//   MAP=hippiestation HARNESS=bot_crew_shots.dm SENDER=shot.ps1 tools/keybind_check/run.sh botcrew
// Results in data/keycheck_botcrew.txt, pictures in data/previews/popup_botcrew_*.png.

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
			bot_crew_shots_run(src)

/proc/bc_check(name, ok, detail = "")
	kc_log("[ok ? "PASS" : "FAIL"] [name][detail ? " ([detail])" : ""]")

/proc/bc_shot(name)
	fdel("data/keycheck_shot_title") //tgui windows have no caption: the biggest popup
	text2file("popup_[name]", "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/proc/bc_ui(mob/user, datum/src_object)
	var/deadline = world.time + 20 SECONDS
	while(world.time < deadline)
		for(var/datum/tgui/open as anything in user.open_uis)
			if(open.src_object == src_object && open.initialized)
				return open
		sleep(2)

/proc/bot_crew_shots_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	var/list/bots = list()
	for(var/rank in list("Station Engineer", "Medical Doctor", "Security Officer", "Scientist", "Assistant", "Cargo Technician", "Cook", "Botanist"))
		var/mob/living/carbon/human/H = spawn_bot_crew_member(rank, TRUE)
		if(H)
			bots += H
	bc_check("bots spawned", length(bots) == 8, "[length(bots)]")

	var/datum/admins/was = GLOB.deadmins[C.ckey]
	if(was)
		was.activate()
	else if(!C.holder)
		var/datum/admins/A = new(new /datum/admin_rank("!localhost!", R_EVERYTHING, R_DBRANKS, R_EVERYTHING), C.ckey, 1, 1)
		A.associate(C)
	sleep(1 SECONDS)
	bc_check("the verb is there", (/client/proc/cmd_bot_crew in C.verbs))
	usr = C.mob //the verb's check_rights() reads usr, which a spawned proc hasn't got
	C.cmd_bot_crew()
	var/datum/admin_tool_window/bot_crew/panel = C.holder.tool_windows?["bot_crew"]
	var/datum/tgui/ui = bc_ui(C.mob, panel)
	bc_check("the panel opens", ui)
	bc_check("lines kept while it's open", GLOB.bot_crew_panel_open)
	sleep(40 SECONDS) //the crew get going
	var/list/data = panel.ui_data(C.mob)
	bc_check("a row a bot", length(data["bots"]) == length(GLOB.bot_crew_members), "[length(data["bots"])] rows, [length(GLOB.bot_crew_members)] bots")
	var/doing = 0
	for(var/list/row in data["bots"])
		if(row["goal"])
			doing++
	bc_check("what they're doing", doing >= 1, "[doing] with a goal")
	bc_shot("botcrew_table")

	var/mob/living/carbon/human/busiest
	for(var/mob/living/carbon/human/H in bots)
		if(!busiest || length(H.bot_brain?.panel_lines) > length(busiest.bot_brain?.panel_lines))
			busiest = H
	panel.ui_act("open", list("ref" = REF(busiest)), ui, ui?.state)
	sleep(3 SECONDS)
	data = panel.ui_data(C.mob)
	bc_check("a row opens", data["open_ref"] == REF(busiest) && islist(data["open"]), busiest?.real_name)
	bc_check("its last lines", length(data["open"]?["lines"]) >= 1, "[length(data["open"]?["lines"])]")
	bc_shot("botcrew_open")

	qdel(panel)
	sleep(1 SECONDS)
	bc_check("closed, nothing kept", !GLOB.bot_crew_panel_open && !length(busiest?.bot_brain?.panel_lines))

	text2file("done", "data/keycheck_shots_done")
	sleep(2 SECONDS)
	kc_log("done")
