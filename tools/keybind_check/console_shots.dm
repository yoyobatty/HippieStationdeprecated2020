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
		js = "Array.prototype.slice.call(document.querySelectorAll('*')).filter(function(e){var o=getComputedStyle(e).overflowY;return (o=='auto'||o=='scroll')&&e.scrollHeight>e.clientHeight;}).forEach(function(e){e.scrollTop=[pixels];});"
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
		"Lena Kowalczyk" = "Station Engineer", "Ade Bello" = "Atmospheric Technician", "Maya Ferreira" = "Medical Doctor",
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
		if("secrec")
			cs_secrec(C, H, label)
		if("medrec")
			cs_medrec(C, H, label)
		if("cloning")
			cs_cloning(C, H, label)
		if("stack")
			cs_stack(C, H, label)
		if("strip")
			cs_strip(C, H, label)
		if("apc")
			cs_apc(C, H, label)
		if("pa")
			cs_pa(C, H, label)
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

// The records consoles

/// A crew member on the manifest as the game puts them there at round start, photos and all; the body's gone after.
/proc/cs_inject_crew(turf/at, name, job, outfit)
	var/mob/living/carbon/human/P = new(at)
	P.real_name = name
	P.name = name
	P.mind_initialize()
	P.mind.assigned_role = job
	if(outfit)
		P.equipOutfit(outfit)
	GLOB.data_core.manifest_inject(P)
	return P

/proc/cs_records_crew(turf/at)
	var/list/bodies = list()
	bodies += cs_inject_crew(at, "Cam Oyelaran", "Assistant", /datum/outfit/job/assistant)
	bodies += cs_inject_crew(at, "Rosa Delgado", "Medical Doctor", /datum/outfit/job/doctor)
	bodies += cs_inject_crew(at, "Tomas Reyes", "Security Officer", /datum/outfit/job/security)
	bodies += cs_inject_crew(at, "Wren Gallagher", "Botanist", /datum/outfit/job/botanist)
	sleep(3 SECONDS) // manifest_inject() doesn't wait: the photos take a moment
	for(var/mob/M in bodies)
		qdel(M)
	var/datum/data/record/S = find_record("name", "Cam Oyelaran", GLOB.data_core.security)
	if(S)
		S.fields["criminal"] = "*Arrest*"
		GLOB.data_core.addMajorCrime(S.fields["id"], GLOB.data_core.createCrimeEntry("Grand theft", "Took the captain's spare ID from the bridge", "Ines Okafor", "12:14:05"))
		GLOB.data_core.addMinorCrime(S.fields["id"], GLOB.data_core.createCrimeEntry("Trespass", "Seen in the armory hallway", "Tomas Reyes", "12:20:41"))
	S = find_record("name", "Wren Gallagher", GLOB.data_core.security)
	if(S)
		S.fields["criminal"] = "Paroled"
	var/datum/data/record/M = find_record("name", "Rosa Delgado", GLOB.data_core.medical)
	if(M)
		M.fields["alg"] = "Penicillin"
		M.fields["alg_d"] = "Hives within minutes"
	var/datum/data/record/G = find_record("name", "Wren Gallagher", GLOB.data_core.general)
	if(G)
		G.fields["p_stat"] = "Physically Unfit"

/proc/cs_secrec(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/hos)
	cs_records_crew(get_step(H, SOUTH))
	var/obj/machinery/computer/secure_data/console = new(get_step(H, EAST))
	console.stat &= ~(NOPOWER|BROKEN)
	var/obj/item/card/id/own = H.get_idcard()
	H.temporarilyRemoveItemFromInventory(own, TRUE)
	H.put_in_active_hand(own)
	console.attackby(own, H)
	usr = H
	console.Topic(null, list("choice" = "Log In"))
	cs_check("the HoS logs in", console.authenticated == H.real_name, "[console.authenticated]")
	var/datum/data/record/cam = find_record("name", "Cam Oyelaran", GLOB.data_core.general)
	console.interact(H)
	sleep(3 SECONDS)
	var/datum/tgui/ui = cs_find_ui(H, console)
	if(ui)
		winset(C, ui.window_id, "pos=200,40")
		sleep(10)
		cs_shot("popup_secrec_[label]_1_list", "Security Records Console")
		cs_act(console, H, "select", list("ref" = REF(cam)))
		sleep(15)
		cs_shot("popup_secrec_[label]_2_record", "Security Records Console")
		cs_tgui_do(C, ui.window_id, "click:Wanted poster")
		sleep(4)
		cs_tgui_do(C, ui.window_id, "scroll:2000")
		sleep(10)
		cs_shot("popup_secrec_[label]_3_crimes_and_poster", "Security Records Console")
		cs_secrec_checks(C, ui, console, H, cam)
	else
		winset(C, "secure_rec", "pos=200,40")
		sleep(10)
		cs_shot("popup_secrec_[label]_1_list")
		console.Topic(null, list("choice" = "Browse Record", "d_rec" = REF(cam)))
		sleep(10)
		cs_shot("popup_secrec_[label]_2_record")
	SStgui.close_user_uis(H)
	H << browse(null, "window=secure_rec")

/proc/cs_secrec_checks(client/C, datum/tgui/ui, obj/machinery/computer/secure_data/console, mob/living/carbon/human/H, datum/data/record/cam)
	// Clicked in the window
	cs_tgui_do(C, ui.window_id, "scroll:0")
	cs_tgui_do(C, ui.window_id, "click:Incarcerated")
	sleep(10)
	var/datum/data/record/S = find_record("name", "Cam Oyelaran", GLOB.data_core.security)
	cs_check("clicking Incarcerated sets it", S?.fields["criminal"] == "Incarcerated", S?.fields["criminal"])
	// Through ui_act
	cs_act(console, H, "edit", list("field" = "age", "value" = "41"))
	cs_check("age", cam.fields["age"] == 41, "[cam.fields["age"]]")
	cs_act(console, H, "edit", list("field" = "species", "value" = "lizard"))
	cs_check("species, from the list", cam.fields["species"] == "lizard", "[cam.fields["species"]]")
	cs_act(console, H, "edit", list("field" = "species", "value" = "a toaster"))
	cs_check("but nothing off it", cam.fields["species"] == "lizard", "[cam.fields["species"]]")
	cs_act(console, H, "edit", list("field" = "notes", "value" = "Known to the HoP."))
	cs_check("notes", S?.fields["notes"] == "Known to the HoP.", "[S?.fields["notes"]]")
	var/list/major = S?.fields["ma_crim"]
	var/before = length(major)
	cs_act(console, H, "add_crime", list("kind" = "major", "name" = "Assault", "details" = "Hit an officer with a toolbox"))
	major = S?.fields["ma_crim"]
	cs_check("a major crime is added", length(major) == before + 1, "[length(major)]")
	var/datum/data/crime/added = major[length(major)]
	cs_act(console, H, "delete_crime", list("kind" = "major", "id" = "[added.dataId]"))
	major = S?.fields["ma_crim"]
	cs_check("and deleted", length(major) == before, "[length(major)]")
	cs_act(console, H, "add_comment", list("text" = "Questioned at 12:30."))
	cs_check("a comment", findtext(S?.fields["com_1"], "Questioned at 12:30."), "[S?.fields["com_1"]]")
	cs_act(console, H, "delete_comment", list("index" = "1"))
	cs_check("and it's deleted", S?.fields["com_1"] == "<B>Deleted</B>")
	cs_act(console, H, "rank", list("rank" = "Captain"))
	cs_check("the HoS can't change a rank", cam.fields["rank"] == "Assistant", cam.fields["rank"])
	var/turf/T = console.loc
	cs_act(console, H, "poster", list("kind" = "wanted", "alias" = "The Ghost", "header" = "WANTED", "text" = "Armed and dangerous."))
	cs_check("a wanted poster prints", locate(/obj/item/poster/wanted) in T)
	cs_act(console, H, "print")
	cs_check("the record prints", locate(/obj/item/paper) in T)
	var/count = length(GLOB.data_core.general)
	cs_act(console, H, "new_record")
	cs_check("a new record", length(GLOB.data_core.general) == count + 1)
	cs_act(console, H, "delete_all")
	cs_check("and deleting all of it", length(GLOB.data_core.general) == count)
	cs_act(console, H, "logout")
	cs_act(console, H, "select", list("ref" = REF(cam)))
	cs_act(console, H, "edit", list("field" = "age", "value" = "99"))
	cs_check("logged out, nothing changes", cam.fields["age"] == 41, "[cam.fields["age"]]")

/proc/cs_medrec(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/cmo)
	cs_records_crew(get_step(H, SOUTH))
	new /mob/living/simple_animal/bot/medbot(get_step(get_step(H, SOUTH), SOUTH))
	var/obj/machinery/computer/med_data/console = new(get_step(H, EAST))
	console.stat &= ~(NOPOWER|BROKEN)
	var/obj/item/card/id/own = H.get_idcard()
	H.temporarilyRemoveItemFromInventory(own, TRUE)
	H.put_in_active_hand(own)
	console.attackby(own, H)
	if(!console.scan)
		usr = H
		console.Topic(null, list("scan" = "1"))
	usr = H
	console.Topic(null, list("login" = "1"))
	cs_check("the CMO logs in", console.authenticated == H.real_name, "[console.authenticated]")
	var/datum/data/record/rosa = find_record("name", "Rosa Delgado", GLOB.data_core.general)
	console.interact(H)
	sleep(3 SECONDS)
	var/datum/tgui/ui = cs_find_ui(H, console)
	if(ui)
		winset(C, ui.window_id, "pos=200,40")
		cs_act(console, H, "select", list("ref" = REF(rosa)))
		sleep(15)
		cs_shot("popup_medrec_[label]_1_record", "Medical Records Console")
		cs_tgui_do(C, ui.window_id, "scroll:2000")
		sleep(10)
		cs_shot("popup_medrec_[label]_2_record_lower", "Medical Records Console")
		cs_tgui_do(C, ui.window_id, "click:Virus database")
		sleep(4)
		cs_tgui_do(C, ui.window_id, "click:Cold")
		sleep(10)
		cs_shot("popup_medrec_[label]_3_viruses", "Medical Records Console")
		cs_tgui_do(C, ui.window_id, "click:Medbots")
		sleep(10)
		cs_shot("popup_medrec_[label]_4_medbots", "Medical Records Console")
		cs_tgui_do(C, ui.window_id, "click:Records")
		sleep(6)
		cs_medrec_checks(C, ui, console, H, rosa)
	else
		winset(C, "med_rec", "pos=200,40")
		console.Topic(null, list("d_rec" = rosa.fields["id"]))
		console.interact(H)
		sleep(10)
		cs_shot("popup_medrec_[label]_1_record")
		console.Topic(null, list("screen" = "2"))
		console.interact(H)
		sleep(10)
		cs_shot("popup_medrec_[label]_2_list")
		console.Topic(null, list("screen" = "5"))
		console.interact(H)
		sleep(10)
		cs_shot("popup_medrec_[label]_3_viruses")
	SStgui.close_user_uis(H)
	H << browse(null, "window=med_rec")

/proc/cs_medrec_checks(client/C, datum/tgui/ui, obj/machinery/computer/med_data/console, mob/living/carbon/human/H, datum/data/record/rosa)
	var/datum/data/record/M = find_record("name", "Rosa Delgado", GLOB.data_core.medical)
	cs_tgui_do(C, ui.window_id, "scroll:0")
	cs_tgui_do(C, ui.window_id, "click:O-")
	sleep(10)
	cs_check("clicking O- sets the blood type", M?.fields["blood_type"] == "O-", M?.fields["blood_type"])
	cs_tgui_do(C, ui.window_id, "click:*Unconscious*")
	sleep(10)
	cs_check("clicking *Unconscious* sets the physical status", rosa.fields["p_stat"] == "*Unconscious*", rosa.fields["p_stat"])
	cs_act(console, H, "edit", list("field" = "alg", "value" = "Penicillin, latex"))
	cs_check("allergies", M?.fields["alg"] == "Penicillin, latex", M?.fields["alg"])
	cs_act(console, H, "edit", list("field" = "species", "value" = "felinid"))
	cs_check("species, typed", rosa.fields["species"] == "felinid", rosa.fields["species"])
	cs_act(console, H, "m_stat", list("key" = "watch"))
	cs_check("mental status", rosa.fields["m_stat"] == "*Watch*", rosa.fields["m_stat"])
	cs_act(console, H, "add_comment", list("text" = "Treated for burns."))
	cs_check("a comment", findtext(M?.fields["com_1"], "Treated for burns."), "[M?.fields["com_1"]]")
	cs_act(console, H, "delete_medical")
	cs_check("the medical record is deleted", !find_record("name", "Rosa Delgado", GLOB.data_core.medical))
	cs_act(console, H, "select", list("ref" = REF(rosa)))
	cs_act(console, H, "new_record")
	cs_check("and a new one made", find_record("name", "Rosa Delgado", GLOB.data_core.medical))
	var/turf/T = console.loc
	cs_act(console, H, "print")
	cs_check("the record prints", locate(/obj/item/paper) in T)
	var/list/static_data = console.ui_static_data(H)
	var/list/viruses = static_data["viruses"]
	cs_check("the virus database", length(viruses) > 10, "[length(viruses)] diseases")
	var/list/data = console.ui_data(H)
	var/list/medbots = data["medbots"]
	cs_check("the medbot", length(medbots) >= 1, "[length(medbots)] medbots")
	cs_act(console, H, "logout")
	cs_act(console, H, "edit", list("field" = "fingerprint", "value" = "1234"))
	cs_check("logged out, nothing changes", rosa.fields["fingerprint"] != "1234")

// The cloning console

/proc/cs_cloning(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/cmo)
	var/turf/at = get_step(H, EAST)
	var/obj/machinery/computer/cloning/console = new(at)
	var/obj/machinery/dna_scannernew/scanner = new(get_step(at, EAST))
	var/obj/machinery/clonepod/pod = new(get_step(at, NORTH))
	for(var/obj/machinery/M in list(console, scanner, pod))
		M.stat &= ~(NOPOWER|BROKEN)
	console.updatemodules(TRUE)
	console.diskette = new /obj/item/disk/data(console)
	cs_check("the console finds its scanner and pod", console.scanner == scanner && (pod in console.pods), "scanner [console.scanner], pods [length(console.pods)]")
	// Somebody dead, in the scanner
	var/mob/living/carbon/human/body = new(get_step(scanner, SOUTH))
	body.real_name = "Ines Okafor"
	body.name = body.real_name
	body.mind_initialize()
	body.mind.assigned_role = "Head of Security"
	body.equipOutfit(/datum/outfit/job/hos)
	body.death()
	scanner.open_machine()
	scanner.close_machine(body)
	cs_check("the body is in the scanner", scanner.occupant == body)
	usr = H
	console.interact(H)
	sleep(3 SECONDS)
	var/datum/tgui/ui = cs_find_ui(H, console)
	if(ui)
		winset(C, ui.window_id, "pos=200,40")
		sleep(10)
		cs_shot("popup_cloning_[label]_1_occupied", "Cloning System Control")
		cs_tgui_do(C, ui.window_id, "click:Scan")
		sleep(35)
		cs_check("clicking Scan makes a record", find_record("name", "Ines Okafor", console.records))
		cs_tgui_do(C, ui.window_id, "click:Ines Okafor")
		sleep(10)
		cs_shot("popup_cloning_[label]_2_scanned", "Cloning System Control")
		cs_tgui_do(C, ui.window_id, "click:Empty clone")
		sleep(20)
		cs_check("clicking Empty clone starts one in the pod", pod.occupant, "[pod.occupant]")
		cs_shot("popup_cloning_[label]_3_growing", "Cloning System Control")
		cs_cloning_checks(console, H, pod)
	else
		winset(C, "cloning", "pos=200,40")
		sleep(10)
		cs_shot("popup_cloning_[label]_1_occupied")
		console.Topic(null, list("scan" = "1"))
		sleep(35)
		console.interact(H)
		sleep(10)
		var/datum/data/record/R = find_record("name", "Ines Okafor", console.records)
		console.Topic(null, list("view_rec" = R?.fields["id"]))
		console.interact(H)
		sleep(10)
		cs_shot("popup_cloning_[label]_2_scanned")
		console.Topic(null, list("clone" = R?.fields["id"], "empty" = "TRUE"))
		sleep(20)
		console.interact(H)
		sleep(10)
		cs_shot("popup_cloning_[label]_3_growing")
	SStgui.close_user_uis(H)
	H << browse(null, "window=cloning")

/proc/cs_cloning_checks(obj/machinery/computer/cloning/console, mob/living/carbon/human/H, obj/machinery/clonepod/pod)
	var/list/data = console.ui_data(H)
	var/list/pods = data["pods"]
	var/list/first = length(pods) ? pods[1] : null
	cs_check("the pod's progress shows", first && !isnull(first["progress"]), "[first?["progress"]]%")
	var/datum/data/record/R = find_record("name", "Ines Okafor", console.records)
	cs_act(console, H, "disk_save", list("id" = R?.fields["id"]))
	cs_check("a record saved to the disk", console.diskette?.fields?["name"] == "Ines Okafor", "[console.diskette?.name]")
	cs_act(console, H, "include", list("part" = "ui"))
	cs_check("loading includes the identifier", console.include_ui)
	cs_act(console, H, "disk_eject")
	cs_check("the disk comes out", !console.diskette)
	cs_act(console, H, "scan", list("body_only" = 1))
	sleep(35)
	cs_act(console, H, "delete", list("id" = R?.fields["id"]))
	// The body-only scan made a second record by the same name and ID: the one deleted is the first
	cs_check("the CMO deletes a record", !(R in console.records), "[length(console.records)] left")
	cs_act(console, H, "lock")
	cs_check("the scanner locks", console.scanner.locked)
	cs_act(console, H, "lock")
	cs_check("and unlocks", !console.scanner.locked)

// The stack crafting window

/proc/cs_stack(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/engineer)
	var/obj/item/stack/sheet/metal/sheets = new(H.loc, 50)
	H.put_in_active_hand(sheets)
	usr = H
	sheets.attack_self(H)
	sleep(3 SECONDS)
	var/datum/tgui/ui = cs_find_ui(H, sheets)
	if(ui)
		winset(C, ui.window_id, "pos=200,40")
		sleep(10)
		cs_shot("popup_stack_[label]_1_metal", sheets.name)
		cs_tgui_do(C, ui.window_id, "input0:rod")
		sleep(10)
		cs_shot("popup_stack_[label]_2_search_rods", sheets.name)
		// Clicked in the window: one rod recipe, then twenty rods at once
		cs_tgui_do(C, ui.window_id, "click:Make")
		sleep(10)
		cs_check("clicking Make uses a sheet", sheets.amount == 49, "[sheets.amount] sheets")
		var/obj/item/stack/rods/R = H.is_holding_item_of_type(/obj/item/stack/rods)
		cs_check("and the rods are in hand", R?.amount == 2, "[R?.amount] rods")
		cs_tgui_do(C, ui.window_id, "click:20x")
		sleep(10)
		cs_check("clicking 20x uses ten sheets", sheets.amount == 39, "[sheets.amount] sheets")
		cs_tgui_do(C, ui.window_id, "input0:")
		sleep(4)
		cs_tgui_do(C, ui.window_id, "click:chairs")
		sleep(10)
		cs_shot("popup_stack_[label]_3_group", sheets.name)
		// The bots' way: Topic() straight, as goals/repair_damage.dm does
		var/obj/item/stack/rods/rods = new(H.loc, 10)
		H.dropItemToGround(sheets)
		H.put_in_active_hand(rods)
		var/rods_before = rods.amount // it can merge with the rods made above
		rods.Topic(null, list("make" = "1", "multiplier" = "1"))
		sleep(5)
		cs_check("a bot's Topic() still makes things", rods.amount < rods_before, "[rods_before] -> [rods.amount] rods")
		// Used up: the window shuts
		H.dropItemToGround(rods)
		var/obj/item/stack/sheet/glass/glass = new(H.loc, 1)
		H.put_in_active_hand(glass)
		glass.attack_self(H)
		sleep(2 SECONDS)
		cs_check("a glass window opens", cs_find_ui(H, glass))
		cs_act(glass, H, "make", list("index" = "1", "multiplier" = "1"))
		sleep(10)
		cs_check("and shuts once the glass is used up", QDELETED(glass) || !cs_find_ui(H, glass), "[QDELETED(glass) ? "used up" : "[glass.amount] left"]")
	else
		winset(C, "stack", "pos=200,40")
		sleep(10)
		cs_shot("popup_stack_[label]_1_metal")
	SStgui.close_user_uis(H)
	H << browse(null, "window=stack")

// The strip menu

/// A floor next to them to stand someone on
/proc/cs_open_beside(atom/A, list/taken)
	for(var/dir in GLOB.alldirs)
		var/turf/open/T = get_step(A, dir)
		if(istype(T) && !T.density && !(T in taken) && !(locate(/mob) in T) && !(locate(/obj/structure) in T) && !(locate(/obj/machinery) in T))
			return T
	return get_turf(A)

/// Waits until `what` on `thing` isn't `was` any more, up to `seconds`
/proc/cs_wait_change(datum/thing, what, was, seconds)
	var/deadline = world.time + seconds SECONDS
	while(world.time < deadline && thing.vars[what] == was)
		sleep(2)

/proc/cs_strip(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/engineer)
	H.dropItemToGround(H.get_active_held_item())
	var/mob/living/carbon/human/V = new(cs_open_beside(H))
	V.fully_replace_character_name(null, "Tomas Reyes")
	V.equipOutfit(/datum/outfit/job/security)
	qdel(V.s_store)
	V.equip_to_slot_or_del(new /obj/item/tank/internals/emergency_oxygen(V), ITEM_SLOT_SUITSTORE)
	V.equip_to_slot_or_del(new /obj/item/clothing/glasses/hud/security/sunglasses(V), ITEM_SLOT_EYES)
	V.equip_to_slot_or_del(new /obj/item/clothing/mask/gas(V), ITEM_SLOT_MASK)
	qdel(V.l_store)
	var/obj/item/coin/gold/coin = new(V)
	coin.name = "lucky coin"
	V.equip_to_slot_or_del(coin, ITEM_SLOT_LPOCKET)
	V.handcuffed = new /obj/item/restraints/handcuffs(V)
	V.update_handcuffed()
	sleep(1 SECONDS)
	usr = H
	H.MouseDrop_T(V, H)
	sleep(3 SECONDS)
	var/datum/tgui/ui = cs_find_ui(H, V)
	if(!ui)
		// The old windows
		winset(C, "mob[REF(V)]", "pos=200,40")
		sleep(10)
		cs_shot("popup_strip_[label]_1_officer")
		H << browse(null, "window=mob[REF(V)]")
		var/mob/living/carbon/monkey/M = cs_strip_monkey(H, V)
		usr = H
		H.MouseDrop_T(M, H)
		sleep(2 SECONDS)
		winset(C, "mob[REF(M)]", "pos=200,40")
		sleep(10)
		cs_shot("popup_strip_[label]_3_monkey")
		H << browse(null, "window=mob[REF(M)]")
		return
	winset(C, ui.window_id, "pos=200,40")
	sleep(10)
	cs_shot("popup_strip_[label]_1_officer", V.name)
	var/json = json_encode(V.ui_data(H))
	cs_check("the window doesn't say what's in the pockets", V.l_store && V.r_store && !findtextEx(json, V.l_store.name) && !findtextEx(json, V.r_store.name), "[V.l_store] and [V.r_store]")
	// Clicked in the window: the valve, the left pocket, the boots
	var/obj/item/tank = V.s_store
	cs_tgui_do(C, ui.window_id, "click:Set internals")
	cs_wait_change(V, "internal", null, 8)
	cs_check("clicking Set internals opens their tank", V.internal == tank, "[V.internal || "no tank open"]")
	var/obj/item/pocketed = V.l_store
	cs_tgui_do(C, ui.window_id, "click:Left (Full)")
	cs_wait_change(V, "l_store", pocketed, 8)
	cs_check("clicking Left (Full) empties that pocket", !V.l_store && pocketed?.loc == V.loc, "[V.l_store ? "still has [V.l_store]" : "[pocketed] on the floor"]")
	var/obj/item/boots = V.shoes
	cs_tgui_do(C, ui.window_id, "click:[boots.name]")
	cs_wait_change(V, "shoes", boots, 10)
	cs_check("clicking the boots takes them off into your hands", !V.shoes && H.is_holding(boots), "[V.shoes ? "still on" : "[boots.loc]"]")
	sleep(10)
	cs_shot("popup_strip_[label]_2_stripped", V.name)
	cs_act(V, H, "item", list("slot" = "[ITEM_SLOT_FEET]", "hand" = "0"))
	cs_check("Empty with them in hand puts the boots back on", V.shoes == boots, "[V.shoes || "barefoot"]")
	// What the old window's Topic took on trust
	var/obj/item/flash = V.r_store
	cs_act(V, H, "item", list("slot" = "[ITEM_SLOT_RPOCKET]", "hand" = "0"))
	cs_check("a pocket can't be sent as a slot", V.r_store == flash, "[V.r_store || "taken"]")
	var/obj/item/glasses = V.glasses
	cs_act(V, H, "item", list("slot" = "[ITEM_SLOT_EYES]", "hand" = "0"))
	cs_check("nor eyes the gas mask covers", V.glasses == glasses, "[V.glasses || "taken"]")
	// A bot strips without a window
	var/mob/living/carbon/human/bot = new(cs_open_beside(V, list(get_turf(H))))
	var/obj/item/helmet = V.head
	bot.stripPanelUnequip(helmet, V, ITEM_SLOT_HEAD)
	cs_check("a bot's stripPanelUnequip() still strips", V.head != helmet, "[V.head || "bareheaded"]")
	cs_check("and opens no window", !length(bot.open_uis))
	qdel(bot)
	// Out of reach: the window shuts
	H.forceMove(locate(H.x, H.y + 4, H.z))
	sleep(4 SECONDS)
	cs_check("walking off shuts it", !cs_find_ui(H, V))
	H.forceMove(cs_open_beside(V))
	// A monkey's window, with its tank on its back
	var/mob/living/carbon/monkey/M = cs_strip_monkey(H, V)
	usr = H
	H.MouseDrop_T(M, H)
	sleep(2 SECONDS)
	ui = cs_find_ui(H, M)
	cs_check("a monkey's window opens", ui)
	if(ui)
		winset(C, ui.window_id, "pos=200,40")
		sleep(10)
		cs_shot("popup_strip_[label]_3_monkey", M.name)
		var/turf/was_at = M.loc
		var/started = world.time
		cs_act(M, H, "internal", list("slot" = "[ITEM_SLOT_BACK]"))
		cs_check("and its tank opens (the old link sent the wrong slot)", M.internal == M.back, "[M.internal || "no tank open"], [get_dist(H, M)] apart, [(world.time - started) / 10] s, [M.loc == was_at ? "stayed put" : "moved"], holding [H.get_active_held_item() || "nothing"], mask [M.wear_mask], back [M.back], [M.mobility_flags & MOBILITY_MOVE ? "can move" : "held still"]")
	SStgui.close_user_uis(H)

/proc/cs_strip_monkey(mob/living/carbon/human/H, mob/living/carbon/human/V)
	var/mob/living/carbon/monkey/M = new(cs_open_beside(H, list(get_turf(V))))
	M.equip_to_slot_or_del(new /obj/item/clothing/mask/breath(M), ITEM_SLOT_MASK)
	M.equip_to_slot_or_del(new /obj/item/tank/internals/oxygen(M), ITEM_SLOT_BACK)
	M.Immobilize(2 MINUTES) // monkeys wander, and a strip stops when they move
	sleep(5)
	return M

// The power flow control console

/proc/cs_apc(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/ce)
	var/obj/machinery/computer/apc_control/console = new(cs_open_beside(H))
	console.stat &= ~(NOPOWER|BROKEN)
	usr = H
	console.Topic(null, list("authenticate" = "1"))
	cs_check("the Chief Engineer logs in", console.authenticated, console.auth_id)
	console.interact(H)
	sleep(3 SECONDS)
	var/datum/tgui/ui = cs_find_ui(H, console)
	if(!ui)
		// The old window
		winset(C, "apc_control", "pos=200,40")
		sleep(10)
		cs_shot("popup_apc_[label]_1_list")
		usr = H
		console.Topic(null, list("check_logs" = "1"))
		sleep(10)
		cs_shot("popup_apc_[label]_3_logs")
		H << browse(null, "window=apc_control")
		return
	winset(C, ui.window_id, "pos=200,40")
	sleep(10)
	cs_shot("popup_apc_[label]_1_list", console.name)
	cs_tgui_do(C, ui.window_id, "input0:engi")
	sleep(10)
	cs_shot("popup_apc_[label]_2_search", console.name)
	// Access, clicked in the window: the first engineering APC that answers
	var/obj/machinery/power/apc/first
	for(var/obj/machinery/power/apc/APC as anything in GLOB.apcs_list)
		if(console.check_apc(APC) && !APC.aidisabled && !APC.panel_open && (findtext(APC.name, "engi") || findtext(get_area_name(APC.area, TRUE), "engi")))
			first = APC
			break
	cs_tgui_do(C, ui.window_id, "click:Access")
	sleep(2 SECONDS)
	cs_check("clicking Access reaches an engineering APC", console.active_apc && console.active_apc == first, "[console.active_apc ? get_area_name(console.active_apc.area, TRUE) : "none"]")
	cs_check("which unlocks and opens its own window", console.active_apc && !console.active_apc.locked && cs_find_ui(H, console.active_apc))
	if(console.active_apc)
		var/datum/tgui/apc_ui = cs_find_ui(H, console.active_apc)
		apc_ui?.close()
	sleep(5)
	// What the old window's Topic took on trust
	var/obj/machinery/power/apc/far
	for(var/obj/machinery/power/apc/APC as anything in GLOB.apcs_list)
		if(APC.z != console.z && !APC.aidisabled && !APC.panel_open)
			far = APC
			break
	if(far)
		var/obj/machinery/power/apc/was = console.active_apc
		cs_act(console, H, "access", list("ref" = REF(far)))
		cs_check("an APC off the station's level can't be sent", console.active_apc == was, "[get_area_name(far.area, TRUE)]")
		var/datum/tgui/far_ui = cs_find_ui(H, far)
		far_ui?.close()
	else
		kc_log("SKIP no APC off the station's level to try")
	var/log_count = length(console.logs)
	cs_act(console, H, "clear_logs")
	cs_check("nor clearing the logs without an emag", length(console.logs) == log_count, "[length(console.logs)] of [log_count] entries")
	// The logs, clicked
	cs_tgui_do(C, ui.window_id, "click:Logs")
	sleep(10)
	cs_check("clicking Logs shows the log", console.checking_logs)
	var/list/data = console.ui_data(H)
	var/found = FALSE
	for(var/entry in data["logs"])
		if(findtext(entry, "remotely accessed APC"))
			found = TRUE
	cs_check("which has the access, in plain text", found && !findtext(json_encode(data["logs"]), "<b>"), "[length(data["logs"])] entries")
	cs_shot("popup_apc_[label]_3_logs", console.name)
	// Emagged: the warning, and the logs can be cleared
	console.emag_act(H)
	sleep(10)
	cs_shot("popup_apc_[label]_4_emagged", console.name)
	cs_tgui_do(C, ui.window_id, "click:@#%! Clear logs")
	sleep(10)
	cs_check("an emagged console's Clear logs clears them", !length(console.logs), "[length(console.logs)] left")
	cs_tgui_do(C, ui.window_id, "click:Restore logging")
	sleep(10)
	cs_check("clicking Restore logging restores it", !(console.obj_flags & EMAGGED))
	cs_tgui_do(C, ui.window_id, "click:Log out")
	sleep(10)
	cs_check("clicking Log out logs out", !console.authenticated)
	cs_tgui_do(C, ui.window_id, "click:Log in")
	sleep(10)
	var/last_entry = length(console.logs) ? console.logs[length(console.logs)] : ""
	cs_check("clicking Log in logs in, under their name (the old window put NULL OPERATOR)", console.authenticated && findtext(last_entry, H.real_name) && findtext(last_entry, "logged in"), last_entry)
	SStgui.close_user_uis(H)
	sleep(1 SECONDS)
	cs_apc_outage(C, H, label)
	SStgui.close_user_uis(H)

// The particle accelerator's control console

/proc/cs_pa(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/engineer)
	var/obj/machinery/particle_accelerator/control_box/CB
	for(var/obj/machinery/particle_accelerator/control_box/box in GLOB.machines)
		if(is_station_level(box.z))
			CB = box
			break
	cs_check("the station has an accelerator", CB)
	if(!CB)
		return
	// Bolted down, wired and closed up, as engineers leave it
	for(var/obj/structure/particle_accelerator/part in range(4, CB))
		part.construction_state = 3
		part.anchored = TRUE
		part.update_icon()
	CB.construction_state = 3
	CB.anchored = TRUE
	CB.stat &= ~(NOPOWER|BROKEN)
	CB.use_power = IDLE_POWER_USE
	cs_check("all its parts are there", CB.part_scan())
	CB.assembled = FALSE
	CB.connected_parts.Cut()
	CB.update_icon()
	H.forceMove(cs_open_beside(CB))
	usr = H
	CB.interact(H)
	sleep(3 SECONDS)
	var/datum/tgui/ui = cs_find_ui(H, CB)
	if(!ui)
		// The old window
		winset(C, "pacontrol", "pos=200,40")
		sleep(10)
		cs_shot("popup_pa_[label]_1_unscanned")
		usr = H
		CB.Topic(null, list("scan" = "1"))
		CB.Topic(null, list("togglep" = "1"))
		CB.Topic(null, list("strengthup" = "1"))
		sleep(10)
		cs_shot("popup_pa_[label]_2_running")
		CB.Topic(null, list("togglep" = "1"))
		H << browse(null, "window=pacontrol")
		return
	winset(C, ui.window_id, "pos=200,40")
	sleep(10)
	cs_shot("popup_pa_[label]_1_unscanned", CB.name)
	cs_act(CB, H, "power")
	cs_check("it won't switch on before a scan finds the parts", !CB.active)
	// Clicked in the window
	cs_tgui_do(C, ui.window_id, "click:Run scan")
	sleep(10)
	cs_check("clicking Run scan finds the parts", CB.assembled)
	cs_tgui_do(C, ui.window_id, "click:Off")
	sleep(10)
	cs_check("clicking Off switches it on", CB.active)
	cs_tgui_do(C, ui.window_id, "click:+")
	sleep(10)
	cs_tgui_do(C, ui.window_id, "click:+")
	sleep(10)
	cs_check("clicking + twice takes it to 2", CB.strength == 2, "strength [CB.strength]")
	cs_tgui_do(C, ui.window_id, "click:+")
	sleep(10)
	cs_check("and no further", CB.strength == 2, "strength [CB.strength]")
	cs_shot("popup_pa_[label]_2_running", CB.name)
	cs_tgui_do(C, ui.window_id, "click:-")
	sleep(10)
	cs_check("clicking - turns it down", CB.strength == 1, "strength [CB.strength]")
	// The wires still have their say: a cut interface wire times the window out
	CB.wires.cut(WIRE_INTERFACE)
	cs_tgui_do(C, ui.window_id, "click:On")
	sleep(10)
	cs_check("with the interface wire cut, clicking On does nothing", CB.active)
	CB.wires.cut(WIRE_INTERFACE) // mended; it takes a pulse to bring the interface back, as it always has
	CB.wires.pulse(WIRE_INTERFACE)
	cs_tgui_do(C, ui.window_id, "click:On")
	sleep(10)
	cs_check("mended and pulsed, clicking On switches it off", !CB.active)
	SStgui.close_user_uis(H)

/// A real Grid Check, at the console in the Chief Engineer's office: backup power, then Reset all APCs
/proc/cs_apc_outage(client/C, mob/living/carbon/human/H, label)
	var/obj/machinery/computer/apc_control/office
	for(var/obj/machinery/computer/apc_control/A in GLOB.machines)
		if(is_station_level(A.z) && istype(get_area(A), /area/crew_quarters/heads/chief))
			office = A
			break
	cs_check("there's a power flow console in the Chief Engineer's office", office)
	if(!office)
		return
	H.forceMove(cs_open_beside(office))
	usr = H
	office.Topic(null, list("authenticate" = "1"))
	office.interact(H)
	sleep(2 SECONDS)
	var/datum/tgui/ui = cs_find_ui(H, office)
	cs_check("its window opens", ui)
	if(!ui)
		return
	winset(C, ui.window_id, "pos=200,40")
	for(var/datum/round_event_control/grid_check/event in SSevents.control)
		event.runEvent()
	var/area/room = get_area(office)
	var/obj/machinery/power/apc/office_apc = room.get_apc()
	var/deadline = world.time + 20 SECONDS
	while(world.time < deadline && !(office_apc?.failure_timer && office.backup_power))
		sleep(5)
	sleep(3 SECONDS)
	var/down = 0
	for(var/obj/machinery/power/apc/APC as anything in GLOB.apcs_list)
		if(office.check_apc(APC) && APC.failure_timer)
			down++
	cs_check("the Grid Check times the APCs out", down > 20, "[down] down")
	cs_check("the office goes dark but the console runs on its backup cell", !room.power_light && office.backup_power && !(office.stat & NOPOWER), "lights [room.power_light ? "on" : "off"], backup [office.backup_power]")
	cs_shot("popup_apc_[label]_5_grid_failure", office.name)
	// Only the Chief Engineer's ID resets the grid
	var/mob/living/carbon/human/engineer = new(cs_open_beside(office, list(get_turf(H))))
	engineer.equipOutfit(/datum/outfit/job/engineer)
	cs_act(office, engineer, "reset_all")
	cs_check("an engineer's ID can't reset the grid", !office.resetting && !office.ui_data(engineer)["can_reset"])
	qdel(engineer)
	usr = H
	// Clicked in the window
	cs_tgui_do(C, ui.window_id, "click:Reset all APCs")
	var/started = world.time
	sleep(5)
	cs_check("clicking Reset all APCs starts the reset", office.resetting, "[office.reset_total] to reset")
	sleep(5)
	cs_check("the office's own APC is among the first back", !office_apc.failure_timer && office.reset_done <= 10, "[office.reset_done] back by then")
	sleep(6 SECONDS)
	cs_shot("popup_apc_[label]_6_resetting", office.name)
	cs_check("halfway there at 7 seconds", office.reset_done > office.reset_total * 0.3 && office.reset_done < office.reset_total * 0.7, "[office.reset_done] of [office.reset_total]")
	deadline = world.time + 15 SECONDS
	while(world.time < deadline && office.resetting)
		sleep(2)
	var/took = (world.time - started) / 10
	cs_check("it takes 15 seconds", took >= 14 && took <= 17, "[took] s")
	var/still_down = 0
	for(var/obj/machinery/power/apc/APC as anything in GLOB.apcs_list)
		if(office.check_apc(APC) && APC.failure_timer)
			still_down++
	cs_check("and every APC is back", !still_down, "[still_down] still down")
	cs_check("the office lights are back and the console off its backup", room.power_light && !office.backup_power)
	var/logged = FALSE
	for(var/entry in office.logs)
		if(findtext(entry, "began resetting"))
			logged = TRUE
	cs_check("the reset is in the log", logged)
	sleep(2 SECONDS)
	cs_shot("popup_apc_[label]_7_reset_done", office.name)
