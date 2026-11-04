// Pictures of the consoles being moved to tgui, old window and new, with a real client, and checks of the new windows' buttons.
// Not part of the game. Which console: echo id > data/console_shots_which. The old window comes from a build without the new file:
//   echo before > data/console_shots_label; EXCLUDE=card_tgui.dm HARNESS=console_shots.dm SENDER=shot.ps1 tools/keybind_check/run.sh console
//   echo after > data/console_shots_label; HARNESS=console_shots.dm SENDER=shot.ps1 tools/keybind_check/run.sh console
// Pictures in data/previews/popup_<which>_<label>_*.png, results in data/keycheck_console.txt.

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
			console_shots_run(src)

/// A picture of a window: the one titled `title` when given (shot.ps1 takes the biggest otherwise).
/proc/cs_shot(name, title)
	fdel("data/keycheck_shot_title")
	if(title)
		text2file(title, "data/keycheck_shot_title")
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/proc/cs_check(name, ok, detail = "")
	kc_log("[ok ? "PASS" : "FAIL"] [name][detail ? " ([detail])" : ""]")

/// ui_act() bails unless the window's interactive: a window that only says it is.
/datum/tgui/cs_stub/New()
	status = UI_INTERACTIVE

/proc/cs_act(datum/src_object, mob/user, action, list/params = list())
	var/datum/tgui/cs_stub/stub = new
	usr = user
	return src_object.ui_act(action, params, stub, GLOB.default_state)

/proc/cs_find_ui(mob/user, datum/src_object)
	for(var/datum/tgui/open as anything in user.open_uis)
		if(open.src_object == src_object)
			return open

/// One click or keystroke on a tgui page, from script. "click:<text>" presses the first button whose text starts with it,
/// "input<N>:<text>" types in the Nth text box (from 0), "scroll:<pixels>" scrolls the page to there.
/proc/cs_tgui_do(client/C, window_id, action)
	var/js
	if(findtext(action, "click:") == 1)
		var/text = copytext(action, 7)
		js = "var t=[json_encode(text)];var b=Array.prototype.slice.call(document.querySelectorAll('.Button, .Collapsible, \[style*=\"cursor\"\]')).filter(function(e){return e.textContent.trim().indexOf(t)===0;})\[0\];if(b){b.click();}"
	else if(findtext(action, "scroll:") == 1)
		var/pixels = text2num(copytext(action, 8))
		js = "var c=document.querySelector('.Layout__content')||document.scrollingElement||document.body;c.scrollTop=[pixels];"
	else if(findtext(action, "input") == 1)
		var/colon = findtext(action, ":")
		var/index = text2num(copytext(action, 6, colon))
		var/text = copytext(action, colon + 1)
		js = "var i=document.querySelectorAll('input')\[[index]\];if(i){i.value=[json_encode(text)];i.dispatchEvent(new Event('input',{bubbles:true}));}"
	if(js)
		C << output(url_encode(js), "[window_id].browser:eval")

/// A crew for the manifest: the round has nobody else on it.
/proc/cs_add_records()
	var/list/crew = list(
		"Mara Lindqvist" = "Captain", "Jonah Achterberg" = "Head of Personnel", "Ines Okafor" = "Head of Security",
		"Tomas Reyes" = "Security Officer", "Priya Natarajan" = "Warden", "Hugo Brandt" = "Chief Engineer",
		"Lena Kowalczyk" = "Station Engineer", "Ade Bello" = "Atmospheric Technician", "Rosa Delgado" = "Medical Doctor",
		"Kenji Mori" = "Chemist", "Ola Svensson" = "Scientist", "Dev Patel" = "Roboticist", "Nia Brooks" = "Cargo Technician",
		"Sam Tanaka" = "Assistant", "Luca Romano" = "Cook", "Zara Haddad" = "Botanist",
	)
	for(var/name in crew)
		var/datum/data/record/R = new
		R.fields["name"] = name
		R.fields["rank"] = crew[name]
		GLOB.data_core.general += R

/proc/cs_card(name, assignment, list/access, turf/at)
	var/obj/item/card/id/card = new(at)
	card.registered_name = name
	card.assignment = assignment
	card.access = access.Copy()
	card.update_label()
	return card

/proc/console_shots_run(client/C)
	var/which = trim(file2text("data/console_shots_which")) || "id"
	var/label = trim(file2text("data/console_shots_label")) || "now"
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(3 SECONDS)
	cs_add_records()
	var/turf/home = get_turf(pick(SSjob.latejoin_trackers))
	var/mob/living/carbon/human/H = new(home)
	H.mind_initialize()
	H.ckey = C.ckey
	sleep(2 SECONDS)
	kc_log("console [which], [label] build")
	switch(which)
		if("id")
			cs_id(C, H, label)
		if("comms")
			cs_comms(C, H, label)
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)

// The ID console

/proc/cs_id(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/hop)
	var/obj/machinery/computer/card/console = new(get_step(H, EAST))
	console.stat &= ~(NOPOWER|BROKEN)
	var/obj/item/card/id/own = H.get_idcard()
	var/obj/item/card/id/target = cs_card("Sam Tanaka", "Assistant", list(ACCESS_MAINT_TUNNELS), H.loc)
	// Into the slots as a player puts them, the way the HoP bots do
	H.temporarilyRemoveItemFromInventory(own, TRUE)
	H.put_in_active_hand(own)
	console.attackby(own, H)
	H.put_in_active_hand(target)
	console.attackby(target, H)
	cs_check("both cards are in", console.scan == own && console.modify == target, "scan [console.scan], modify [console.modify]")
	usr = H
	console.Topic(null, list("choice" = "auth"))
	cs_check("the HoP logs in at full access", console.authenticated == 2, "authenticated [console.authenticated]")
	console.interact(H)
	sleep(3 SECONDS)
	var/datum/tgui/ui = cs_find_ui(H, console)
	if(ui)
		winset(C, ui.window_id, "pos=200,40")
		var/list/steps = list(
			list("1_card", list()),
			list("2_access_search", list("input2:eva")),
			list("3_slots", list("click:Job slots")),
			list("4_manifest", list("click:Crew manifest")),
			list("5_manifest_search", list("input0:engineer")),
		)
		for(var/list/step in steps)
			for(var/action in step[2])
				cs_tgui_do(C, ui.window_id, action)
				sleep(4)
			sleep(10)
			cs_shot("popup_id_[label]_[step[1]]", console.name)
		cs_id_checks(console, H, target)
	else
		winset(C, "id_com", "pos=200,40")
		sleep(5)
		cs_shot("popup_id_[label]_1_card")
		console.Topic(null, list("choice" = "mode", "mode_target" = "2"))
		sleep(10)
		cs_shot("popup_id_[label]_3_slots")
		console.Topic(null, list("choice" = "mode", "mode_target" = "1"))
		sleep(10)
		cs_shot("popup_id_[label]_4_manifest")
		console.Topic(null, list("choice" = "mode", "mode_target" = "0"))
	SStgui.close_user_uis(H)
	H << browse(null, "window=id_com")
	// The Chief Engineer at their department console: only Engineering
	var/obj/machinery/computer/card/minor/ce/dept = new(get_step(H, WEST))
	dept.stat &= ~(NOPOWER|BROKEN)
	var/datum/job/chief = SSjob.GetJob("Chief Engineer")
	var/obj/item/card/id/ce_card = cs_card("Hugo Brandt", "Chief Engineer", chief.get_access(), H.loc)
	var/obj/item/card/id/engineer = cs_card("Lena Kowalczyk", "Station Engineer", list(ACCESS_ENGINE, ACCESS_MAINT_TUNNELS), H.loc)
	H.put_in_active_hand(ce_card)
	dept.attackby(ce_card, H)
	H.put_in_active_hand(engineer)
	dept.attackby(engineer, H)
	usr = H
	dept.Topic(null, list("choice" = "auth"))
	cs_check("the CE logs in to their own department", dept.authenticated == 1, "authenticated [dept.authenticated]")
	dept.interact(H)
	sleep(3 SECONDS)
	ui = cs_find_ui(H, dept)
	if(ui)
		winset(C, ui.window_id, "pos=200,40")
	else
		winset(C, "id_com", "pos=200,40")
	sleep(10)
	cs_shot("popup_id_[label]_6_department_console", dept.name)
	if(ui)
		var/list/before = engineer.access.Copy()
		cs_act(dept, H, "access", list("access" = "[ACCESS_ARMORY]", "allowed" = 1))
		cs_check("a department head can't give access outside their department", !(ACCESS_ARMORY in engineer.access))
		cs_act(dept, H, "region", list("region" = "2", "allowed" = 1))
		cs_check("nor a whole other department", !(ACCESS_SECURITY in engineer.access))
		cs_act(dept, H, "region", list("region" = "5", "allowed" = 1))
		cs_check("their own department, all of it", !length(get_region_accesses(5) - engineer.access), "had [before.Join(",")]")
		cs_act(dept, H, "demote")
		cs_check("and demote one of their own", engineer.assignment == "Unassigned", engineer.assignment)
	SStgui.close_user_uis(H)

/proc/cs_id_checks(obj/machinery/computer/card/console, mob/living/carbon/human/H, obj/item/card/id/target)
	cs_act(console, H, "assign", list("job" = "Station Engineer"))
	cs_check("a job template sets the job and its access", target.assignment == "Station Engineer" && (ACCESS_ENGINE in target.access), "[target.assignment]")
	cs_act(console, H, "region", list("region" = "5", "allowed" = 0))
	cs_check("Revoke all takes a department's access", !length(get_region_accesses(5) & target.access))
	cs_act(console, H, "region", list("region" = "5", "allowed" = 1))
	cs_check("Grant all gives all of it", !length(get_region_accesses(5) - target.access))
	cs_act(console, H, "access", list("access" = "[ACCESS_ENGINE]", "allowed" = 0))
	cs_check("one access off", !(ACCESS_ENGINE in target.access))
	cs_act(console, H, "access", list("access" = "[ACCESS_ENGINE]", "allowed" = 1))
	cs_check("and back on", (ACCESS_ENGINE in target.access))
	cs_act(console, H, "assign_custom", list("title" = "Pool Guard"))
	cs_check("a custom assignment", target.assignment == "Pool Guard", target.assignment)
	cs_act(console, H, "rename", list("name" = "Sam T. Tanaka"))
	cs_check("rename", target.registered_name == "Sam T. Tanaka", target.registered_name)
	var/list/data = console.ui_data(H)
	var/list/slots = data["slots"]
	cs_check("job slots are listed", length(slots) > 10, "[length(slots)] jobs")
	cs_act(console, H, "logout")
	cs_act(console, H, "access", list("access" = "[ACCESS_CAPTAIN]", "allowed" = 1))
	cs_check("logged out, nothing changes", !(ACCESS_CAPTAIN in target.access))
	console.Topic(null, list("choice" = "auth"))

// The communications console

/proc/cs_comms(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/captain)
	var/obj/machinery/computer/communications/console = new(get_step(H, EAST))
	console.stat &= ~(NOPOWER|BROKEN)
	var/datum/comm_message/report = new("Central Command Status Summary", "Your station has been selected for a routine audit.<br>Answer <b>within the hour</b>.", list("Accept the audit", "Refuse it"))
	console.add_message(report)
	var/datum/comm_message/old = new("Crew transfer notice", "A shuttle of replacement staff is scheduled.", list())
	console.add_message(old)
	usr = H
	console.Topic(null, list("operation" = "login"))
	cs_check("the Captain logs in to captain functions", console.authenticated == 2, "authenticated [console.authenticated], [console.auth_id]")
	console.interact(H)
	sleep(3 SECONDS)
	var/datum/tgui/ui = cs_find_ui(H, console)
	if(ui)
		winset(C, ui.window_id, "pos=200,40")
		var/list/steps = list(
			list("1_main", list()),
			list("2_message", list("click:Central Command Status Summary", "scroll:420")),
			list("3_captain", list("scroll:250")),
			list("4_status_and_shuttles", list("scroll:2000")),
		)
		for(var/list/step in steps)
			for(var/action in step[2])
				cs_tgui_do(C, ui.window_id, action)
				sleep(4)
			sleep(10)
			cs_shot("popup_comms_[label]_[step[1]]", "Communications Console")
		// The real buttons, clicked in the window: the alert level wants the Captain's ID in hand
		cs_tgui_do(C, ui.window_id, "scroll:0")
		var/obj/item/card/id/captain_id = H.get_idcard()
		H.temporarilyRemoveItemFromInventory(captain_id, TRUE)
		H.put_in_active_hand(captain_id)
		cs_tgui_do(C, ui.window_id, "click:Blue")
		sleep(10)
		cs_check("clicking Blue sets blue alert", GLOB.security_level == SEC_LEVEL_BLUE, "[get_security_level()]")
		cs_tgui_do(C, ui.window_id, "click:Green")
		sleep(10)
		cs_check("clicking Green sets green", GLOB.security_level == SEC_LEVEL_GREEN, "[get_security_level()]")
		CONFIG_SET(number/shuttle_refuel_delay, 0)
		cs_tgui_do(C, ui.window_id, "input0:A clicked shuttle call")
		sleep(4)
		cs_tgui_do(C, ui.window_id, "click:Call the shuttle")
		sleep(4)
		cs_tgui_do(C, ui.window_id, "click:Call it")
		sleep(10)
		cs_check("calling the shuttle from the window, with the confirm", SSshuttle.emergency.mode == SHUTTLE_CALL, "mode [SSshuttle.emergency.mode]")
		cs_tgui_do(C, ui.window_id, "click:Recall the shuttle")
		sleep(4)
		cs_tgui_do(C, ui.window_id, "click:Recall it")
		sleep(10)
		cs_check("and recalling it", SSshuttle.emergency.mode == SHUTTLE_RECALL, "mode [SSshuttle.emergency.mode]")
		var/list/data = console.ui_data(H)
		var/list/shuttle = data["shuttle"]
		cs_check("no Call button while it's on its way back", !shuttle["can_call"])
		cs_shuttle_idle()
		cs_comms_checks(console, H, report)
	else
		winset(C, "communications", "pos=200,40")
		var/list/pages = list(
			list("1_main", null),
			list("2_message", list("operation" = "viewmessage", "message-num" = "1")),
			list("3_alert", list("operation" = "changeseclevel")),
			list("4_status", list("operation" = "status")),
		)
		for(var/list/page in pages)
			if(page[2])
				console.Topic(null, list("operation" = "main"))
				console.currmsg = null
				console.Topic(null, page[2])
			console.interact(H)
			sleep(10)
			cs_shot("popup_comms_[label]_[page[1]]")
	SStgui.close_user_uis(H)
	H << browse(null, "window=communications")

/proc/cs_comms_checks(obj/machinery/computer/communications/console, mob/living/carbon/human/H, datum/comm_message/report)
	cs_act(console, H, "status", list("display" = "message", "line1" = "ALL HANDS", "line2" = "MUSTER"))
	cs_check("the status displays' two lines", console.stat_msg1 == "ALL HANDS" && console.stat_msg2 == "MUSTER", "[console.stat_msg1] / [console.stat_msg2]")
	cs_act(console, H, "answer", list("index" = "1", "answer" = "1"))
	cs_check("a message is answered", report.answered == 1)
	cs_act(console, H, "answer", list("index" = "1", "answer" = "2"))
	cs_check("and stays answered", report.answered == 1)
	// The alert level wants a Captain's ID in hand, as the old window's "swipe ID"
	var/obj/item/card/id/captain_id = H.get_idcard()
	H.temporarilyRemoveItemFromInventory(captain_id, TRUE)
	H.put_in_active_hand(captain_id)
	cs_act(console, H, "alert", list("level" = "[SEC_LEVEL_BLUE]"))
	cs_check("blue alert, with the Captain's ID in hand", GLOB.security_level == SEC_LEVEL_BLUE, "[get_security_level()]")
	cs_act(console, H, "alert", list("level" = "[SEC_LEVEL_GREEN]"))
	cs_check("and back to green", GLOB.security_level == SEC_LEVEL_GREEN, "[get_security_level()]")
	H.dropItemToGround(captain_id)
	cs_act(console, H, "alert", list("level" = "[SEC_LEVEL_BLUE]"))
	cs_check("not without the ID in hand", GLOB.security_level == SEC_LEVEL_GREEN, "[get_security_level()]")
	H.put_in_active_hand(captain_id)
	cs_act(console, H, "emergency_access")
	cs_check("emergency maintenance access lifted", GLOB.emergency_access)
	cs_act(console, H, "emergency_access")
	cs_check("and restored", !GLOB.emergency_access)
	cs_act(console, H, "announce", list("text" = "This is a test of the new console."))
	cs_check("an announcement goes out (and the intercomms recharge)", !SScommunications.can_announce(H, FALSE))
	cs_act(console, H, "message_centcom", list("text" = "Testing the quantum link."))
	var/list/data = console.ui_data(H)
	cs_check("a message to CentCom starts the arrays' cooldown", data["cc_cooldown"] > 0, "[data["cc_cooldown"]] s")
	var/count = length(console.messages)
	cs_act(console, H, "delete", list("index" = "2"))
	cs_check("a message is deleted", length(console.messages) == count - 1)
	CONFIG_SET(number/shuttle_refuel_delay, 0)
	set_security_level(SEC_LEVEL_BLUE)
	var/mode_before = SSshuttle.emergency.mode
	cs_act(console, H, "call_shuttle", list("reason" = "short"))
	cs_check("above green, a reason too short calls nothing", SSshuttle.emergency.mode == mode_before, "mode [SSshuttle.emergency.mode]")
	set_security_level(SEC_LEVEL_GREEN)
	cs_act(console, H, "call_shuttle", list("reason" = "Testing the new communications console"))
	cs_check("the shuttle is called", SSshuttle.emergency.mode == SHUTTLE_CALL, "mode [SSshuttle.emergency.mode]")
	cs_act(console, H, "recall_shuttle")
	cs_check("and recalled", SSshuttle.emergency.mode == SHUTTLE_RECALL, "mode [SSshuttle.emergency.mode]")
	cs_act(console, H, "logout")
	SScommunications.nonsilicon_message_cooldown = 0
	cs_act(console, H, "announce", list("text" = "Logged out."))
	cs_check("logged out, no announcement", SScommunications.can_announce(H, FALSE))

/// Back at CentCom at once, as a recall ends: a test calls it again without waiting out the trip.
/proc/cs_shuttle_idle()
	SSshuttle.emergency.mode = SHUTTLE_IDLE
	SSshuttle.emergency.timer = 0
