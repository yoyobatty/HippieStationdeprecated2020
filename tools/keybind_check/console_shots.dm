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
			// A page that hasn't loaded yet takes no clicks (the first window of a session can take a while)
			var/deadline = world.time + 15 SECONDS
			while(!open.initialized && world.time < deadline && !QDELETED(open))
				sleep(2)
			if(!open.initialized)
				kc_log("NOTE: [src_object]'s window never finished loading")
			return open

/// One click or keystroke on a tgui page, from script. "click:<text>" presses the first button whose text starts with it,
/// "input<N>:<text>" types in the Nth text box (from 0), "type<N>:<text>" types and leaves it (for boxes that send on
/// change), "scroll:<pixels>" scrolls the page to there.
/proc/cs_tgui_do(client/C, window_id, action)
	var/js
	if(findtext(action, "click:") == 1)
		var/text = copytext(action, 7)
		js = "var t=[json_encode(text)];var b=Array.prototype.slice.call(document.querySelectorAll('.Button, .Collapsible, \[style*=\"cursor\"\]')).filter(function(e){return e.textContent.trim().indexOf(t)===0;})\[0\];if(b){b.click();}"
	else if(findtext(action, "clickexact:") == 1)
		// The first button whose whole text is this: one-letter buttons ("C" would find "Close Scanner")
		var/text = copytext(action, 12)
		js = "var t=[json_encode(text)];var b=Array.prototype.slice.call(document.querySelectorAll('.Button')).filter(function(e){return e.textContent.trim()===t;})\[0\];if(b){b.click();}"
	else if(findtext(action, "scroll:") == 1)
		var/pixels = text2num(copytext(action, 8))
		js = "Array.prototype.slice.call(document.querySelectorAll('*')).filter(function(e){var o=getComputedStyle(e).overflowY;return (o=='auto'||o=='scroll')&&e.scrollHeight>e.clientHeight;}).forEach(function(e){e.scrollTop=[pixels];});"
	else if(findtext(action, "textarea:") == 1)
		var/text = copytext(action, 10)
		js = "var a=document.querySelector('textarea');if(a){a.focus();a.value=[json_encode(text)];a.dispatchEvent(new Event('input',{bubbles:true}));}"
	else if(findtext(action, "type") == 1)
		// Typed and left, as a player does: for boxes that only send what's in them on enter or leaving (onChange)
		var/colon = findtext(action, ":")
		var/index = text2num(copytext(action, 5, colon))
		var/text = copytext(action, colon + 1)
		js = "var i=document.querySelectorAll('input')\[[index]\];if(i){i.focus();i.value=[json_encode(text)];i.dispatchEvent(new Event('input',{bubbles:true}));i.blur();}"
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
		if("teg")
			cs_teg(C, H, label)
		if("pipes")
			cs_pipes(C, H, label)
		if("tcomms")
			cs_tcomms(C, H, label)
		if("tlogs")
			cs_tlogs(C, H, label)
		if("dna")
			cs_dna(C, H, label)
		if("news")
			cs_news(C, H, label)
		if("req")
			cs_req(C, H, label)
		if("mining")
			cs_mining(C, H, label)
		if("biogen")
			cs_biogen(C, H, label)
		if("plantdna")
			cs_plantdna(C, H, label)
		if("pda")
			cs_pda(C, H, label)
		if("msgmon")
			cs_msgmon(C, H, label)
		if("tcmachine")
			cs_tcmachine(C, H, label)
		if("robotics")
			cs_robotics(C, H, label)
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

// The thermoelectric generator

/proc/cs_clear_floor(turf/T)
	if(!istype(T, /turf/open/floor) || T.density)
		return FALSE
	for(var/atom/movable/AM in T)
		if(AM.density || istype(AM, /obj/machinery) || ismob(AM))
			return FALSE
	return TRUE

/// Somewhere to stand or set something down: pipes and vents under the floor are fine
/proc/cs_free_floor(turf/T)
	if(!istype(T, /turf/open/floor) || T.density)
		return FALSE
	for(var/atom/movable/AM in T)
		if(AM.density || ismob(AM))
			return FALSE
	return TRUE

/proc/cs_teg(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/engineer)
	// A floor with room for a circulator either side, and for us beside it
	var/turf/spot
	for(var/turf/T in range(7, H))
		if(cs_clear_floor(T) && cs_clear_floor(get_step(T, EAST)) && cs_clear_floor(get_step(T, WEST)) && (cs_clear_floor(get_step(T, NORTH)) || cs_clear_floor(get_step(T, SOUTH))))
			spot = T
			break
	cs_check("there's room for a generator", spot)
	if(!spot)
		return
	var/obj/machinery/atmospherics/components/binary/circulator/hot = new(get_step(spot, EAST))
	hot.setDir(WEST)
	var/obj/machinery/atmospherics/components/binary/circulator/cold/cold = new(get_step(spot, WEST))
	cold.setDir(EAST)
	new /obj/structure/cable(spot)
	var/obj/machinery/power/generator/teg = new(spot)
	if(!teg.powernet)
		var/obj/structure/cable/wire = locate() in spot
		if(!wire.powernet)
			var/datum/powernet/net = new
			net.add_cable(wire)
		teg.connect_to_network()
	cs_check("it finds both circulators and the cable", teg.hot_circ == hot && teg.cold_circ == cold && teg.powernet, "hot [teg.hot_circ ? "yes" : "no"], cold [teg.cold_circ ? "yes" : "no"], power net [teg.powernet ? "yes" : "no"]")
	// Burning plasma one side, nitrogen near the boil the other
	var/datum/gas_mixture/hot_in = hot.airs[2]
	hot_in.parse_gas_string("plasma=150;TEMP=1600")
	var/datum/gas_mixture/cold_in = cold.airs[2]
	cold_in.parse_gas_string("n2=150;TEMP=80")
	H.forceMove(cs_clear_floor(get_step(spot, SOUTH)) ? get_step(spot, SOUTH) : get_step(spot, NORTH))
	sleep(6 SECONDS)
	cs_check("it generates", teg.lastgenlev > 0, DisplayPower(teg.lastgenlev))
	usr = H
	teg.interact(H)
	sleep(3 SECONDS)
	var/datum/tgui/ui = cs_find_ui(H, teg)
	if(!ui)
		// The old window
		winset(C, "teg", "pos=200,40")
		sleep(10)
		cs_shot("popup_teg_[label]_1_running")
		H << browse(null, "window=teg")
		return
	winset(C, ui.window_id, "pos=200,40")
	sleep(10)
	cs_shot("popup_teg_[label]_1_running", teg.name)
	var/list/data = teg.ui_data(H)
	var/list/hot_data = data["hot"]
	cs_check("the window has the generator's own numbers", data["output_level"] == teg.lastgenlev && hot_data["inlet_temperature"] == round(hot_in.temperature, 0.1), "[data["output"]], hot inlet [hot_data["inlet_temperature"]] K")
	// A circulator gone
	qdel(hot)
	teg.find_circs()
	sleep(3 SECONDS)
	data = teg.ui_data(H)
	cs_check("with the hot circulator gone it says so", !data["hot"] && data["cold"])
	cs_shot("popup_teg_[label]_2_no_hot_loop", teg.name)
	SStgui.close_user_uis(H)

// The pipe, disposal pipe and transit tube dispensers

/proc/cs_pipes(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/atmos)
	var/list/taken = list()
	var/obj/machinery/pipedispenser/atmos = new(cs_open_beside(H, taken))
	taken += atmos.loc
	var/obj/machinery/pipedispenser/disposal/disposal = new(cs_open_beside(H, taken))
	taken += disposal.loc
	var/obj/machinery/pipedispenser/disposal/transit_tube/tubes = new(cs_open_beside(H, taken))
	var/list/dispensers = list()
	dispensers[atmos] = "1_atmos"
	dispensers[disposal] = "2_disposal"
	dispensers[tubes] = "3_transit"
	usr = H
	atmos.interact(H)
	sleep(3 SECONDS)
	if(!cs_find_ui(H, atmos))
		// The old windows, one at a time: they share a window
		for(var/obj/machinery/pipedispenser/D in dispensers)
			usr = H
			D.interact(H)
			sleep(2 SECONDS)
			winset(C, "pipedispenser", "pos=200,40")
			sleep(10)
			cs_shot("popup_pipes_[label]_[dispensers[D]]")
			H << browse(null, "window=pipedispenser")
			sleep(5)
		return
	var/datum/tgui/ui = cs_find_ui(H, atmos)
	winset(C, ui.window_id, "pos=200,40")
	sleep(10)
	cs_shot("popup_pipes_[label]_1_atmos", atmos.name)
	// Clicked in the window
	cs_tgui_do(C, ui.window_id, "click:Manifold")
	sleep(10)
	var/obj/item/pipe/made = locate() in atmos.loc
	cs_check("clicking Manifold makes a manifold", made?.pipe_type == /obj/machinery/atmospherics/pipe/manifold, "[made ? made.pipe_type : "nothing"]")
	qdel(made)
	sleep(5)
	cs_tgui_do(C, ui.window_id, "click:Bent Pipe")
	sleep(10)
	made = locate() in atmos.loc
	cs_check("clicking Bent Pipe makes a bent pipe", made?.pipe_type == /obj/machinery/atmospherics/pipe/simple && made.dir == NORTHEAST, "[made ? "[made.pipe_type], dir [made.dir]" : "nothing"]")
	qdel(made)
	cs_tgui_do(C, ui.window_id, "click:3")
	sleep(10)
	cs_check("clicking 3 sets the piping layer", atmos.piping_layer == 3, "layer [atmos.piping_layer]")
	cs_tgui_do(C, ui.window_id, "click:Pipe")
	sleep(10)
	made = locate() in atmos.loc
	cs_check("and the next pipe's on it", made?.piping_layer == 3, "[made ? "layer [made.piping_layer]" : "nothing"]")
	qdel(made)
	sleep(5)
	cs_tgui_do(C, ui.window_id, "click:Meter")
	sleep(10)
	var/obj/item/pipe_meter/meter = locate() in atmos.loc
	cs_check("clicking Meter makes a meter", meter)
	qdel(meter)
	// What the old Topic took on trust
	sleep(15)
	var/before = length(atmos.loc.contents)
	cs_act(atmos, H, "make", list("group" = "Pipes", "index" = "99"))
	cs_act(atmos, H, "make", list("group" = "Disposal Pipes", "index" = "1"))
	cs_check("nothing it doesn't list", length(atmos.loc.contents) == before)
	SStgui.close_user_uis(H)
	// The disposal and transit tube dispensers
	usr = H
	disposal.interact(H)
	sleep(3 SECONDS)
	ui = cs_find_ui(H, disposal)
	cs_check("the disposal dispenser's window opens", ui)
	if(ui)
		winset(C, ui.window_id, "pos=200,40")
		sleep(10)
		cs_shot("popup_pipes_[label]_2_disposal", disposal.name)
		cs_tgui_do(C, ui.window_id, "click:Junction")
		sleep(10)
		var/obj/structure/disposalconstruct/piece = locate() in disposal.loc
		cs_check("clicking Junction makes a disposal junction", piece?.pipe_type == /obj/structure/disposalpipe/junction, "[piece ? piece.pipe_type : "nothing"]")
		SStgui.close_user_uis(H)
	usr = H
	tubes.interact(H)
	sleep(3 SECONDS)
	ui = cs_find_ui(H, tubes)
	cs_check("the transit tube dispenser's window opens", ui)
	if(ui)
		winset(C, ui.window_id, "pos=200,40")
		sleep(10)
		cs_shot("popup_pipes_[label]_3_transit", tubes.name)
		cs_tgui_do(C, ui.window_id, "click:Terminus")
		sleep(10)
		cs_check("clicking Terminus Tube Station makes one", locate(/obj/structure/c_transit_tube/station/reverse) in tubes.loc)
	SStgui.close_user_uis(H)

// The telecommunications monitor, in the telecomms control room beside the station's own servers

/proc/cs_tcomms(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/engineer)
	var/turf/spot
	for(var/turf/T in get_area_turfs(/area/tcommsat/computer))
		if(cs_free_floor(T) && cs_free_floor(get_step(T, EAST)))
			spot = T
			break
	var/obj/machinery/telecomms/hub/hub
	for(var/obj/machinery/telecomms/hub/candidate in GLOB.telecomms_list)
		if(is_station_level(candidate.z))
			hub = candidate
			break
	cs_check("the telecomms control room and the hub are there", spot && hub, "room [spot ? "yes" : "no"], hub [hub ? "yes" : "no"], [length(GLOB.telecomms_list)] telecomms machines")
	if(!spot || !hub)
		return
	H.forceMove(spot)
	var/obj/machinery/computer/telecomms/monitor/console = new(get_step(spot, EAST))
	console.stat &= ~(NOPOWER|BROKEN)
	usr = H
	console.interact(H)
	sleep(3 SECONDS)
	var/datum/tgui/ui = cs_find_ui(H, console)
	if(!ui)
		// The old window, probed and then on a machine
		console.network = hub.network
		usr = H
		console.Topic(null, list("operation" = "probe"))
		sleep(10)
		winset(C, "comm_monitor", "pos=200,40")
		sleep(10)
		cs_shot("popup_tcomms_[label]_1_probed")
		usr = H
		console.Topic(null, list("viewmachine" = hub.id))
		sleep(10)
		cs_shot("popup_tcomms_[label]_2_machine")
		H << browse(null, "window=comm_monitor")
		return
	winset(C, ui.window_id, "pos=200,40")
	// Clicked and typed in the window
	cs_tgui_do(C, ui.window_id, "type0:[hub.network]")
	sleep(10)
	cs_check("typing the network sets it", console.network == hub.network, console.network)
	cs_tgui_do(C, ui.window_id, "click:Probe network")
	sleep(10)
	cs_check("clicking Probe network finds its machines", length(console.machinelist) > 3, "[length(console.machinelist)] found")
	cs_shot("popup_tcomms_[label]_1_probed", console.name)
	var/obj/machinery/telecomms/first = length(console.machinelist) ? console.machinelist[1] : null
	cs_tgui_do(C, ui.window_id, "click:View")
	sleep(10)
	cs_check("clicking View shows that machine", console.screen == 1 && console.SelectedMachine == first, "[console.SelectedMachine]")
	cs_shot("popup_tcomms_[label]_2_machine", console.name)
	cs_tgui_do(C, ui.window_id, "click:Main menu")
	sleep(10)
	cs_check("clicking Main menu goes back", console.screen == 0)
	cs_tgui_do(C, ui.window_id, "type0:a network name far too long")
	sleep(10)
	cs_check("a network name over 15 letters is refused, as before", console.network == hub.network && findtext(console.temp, "TOO LENGHTLY"), console.network)
	cs_tgui_do(C, ui.window_id, "click:Flush buffer")
	sleep(10)
	cs_check("clicking Flush buffer empties it", !length(console.machinelist))
	SStgui.close_user_uis(H)

// The telecommunications server monitor (the log browser), in the telecomms control room

/proc/cs_tlogs(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/engineer)
	var/turf/spot
	for(var/turf/T in get_area_turfs(/area/tcommsat/computer))
		if(cs_free_floor(T) && cs_free_floor(get_step(T, EAST)))
			spot = T
			break
	cs_check("the telecomms control room is there", spot)
	if(!spot)
		return
	H.forceMove(spot)
	var/obj/machinery/computer/telecomms/server/console = new(get_step(spot, EAST))
	console.stat &= ~(NOPOWER|BROKEN)
	// Something on the radio for the logs
	var/said = "Checking the telecomms logs, over."
	H.say(";[said]")
	sleep(3 SECONDS)
	var/obj/machinery/telecomms/server/logged
	for(var/obj/machinery/telecomms/server/S in GLOB.telecomms_list)
		for(var/datum/comm_log_entry/entry in S.log_entries)
			if(findtext(entry.parameters["message"], "telecomms logs"))
				logged = S
	cs_check("what was said on the radio is in a server's logs", logged, logged ? logged.id : "nowhere")
	if(!logged)
		return
	usr = H
	console.interact(H)
	sleep(3 SECONDS)
	var/datum/tgui/ui = cs_find_ui(H, console)
	if(!ui)
		// The old window, scanned and then on the server with the log
		console.network = logged.network
		usr = H
		console.Topic(null, list("operation" = "scan"))
		sleep(10)
		winset(C, "comm_monitor", "pos=200,40")
		sleep(10)
		cs_shot("popup_tlogs_[label]_1_scanned")
		usr = H
		console.Topic(null, list("viewserver" = logged.id))
		sleep(10)
		cs_shot("popup_tlogs_[label]_2_logs")
		H << browse(null, "window=comm_monitor")
		return
	winset(C, ui.window_id, "pos=200,40")
	// Clicked and typed in the window
	cs_tgui_do(C, ui.window_id, "type0:[logged.network]")
	sleep(10)
	cs_tgui_do(C, ui.window_id, "click:Scan")
	sleep(10)
	cs_check("clicking Scan finds the servers", length(console.servers) > 3, "[length(console.servers)] found")
	cs_shot("popup_tlogs_[label]_1_scanned", console.name)
	cs_tgui_do(C, ui.window_id, "click:View")
	sleep(10)
	cs_check("clicking View opens a server", console.screen == 1 && console.SelectedServer, "[console.SelectedServer]")
	cs_act(console, H, "view", list("id" = logged.id))
	sleep(10)
	var/list/data = console.ui_data(H)
	var/list/selected = data["selected"]
	var/found = FALSE
	var/list/logs = selected ? selected["logs"] : list()
	for(var/list/entry in logs)
		if(findtext(entry["message"], "telecomms logs") && entry["source"] == H.real_name && entry["race"] == "Humanoid")
			found = TRUE
	cs_check("the log has who said it, as what, and the words", found)
	cs_shot("popup_tlogs_[label]_2_logs", console.name)
	// Deleting: telecomms access only, and only a log that's there
	var/count = length(logged.log_entries)
	var/mob/living/carbon/human/visitor = new(cs_free_floor(get_step(spot, WEST)) ? get_step(spot, WEST) : spot)
	visitor.equipOutfit(/datum/outfit/job/assistant)
	cs_act(console, visitor, "delete", list("index" = "1"))
	cs_check("an assistant can't delete a log", length(logged.log_entries) == count, "[length(logged.log_entries)] of [count]")
	qdel(visitor)
	cs_act(console, H, "delete", list("index" = "999"))
	cs_check("nor can anyone delete one that isn't there", length(logged.log_entries) == count)
	usr = H
	cs_tgui_do(C, ui.window_id, "click:Delete")
	sleep(10)
	cs_check("an engineer clicking Delete deletes it", length(logged.log_entries) == count - 1, "[length(logged.log_entries)] of [count]")
	SStgui.close_user_uis(H)

// The DNA console, the station's own in Genetics, with somebody in its scanner

/proc/cs_dna(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/geneticist)
	var/obj/machinery/computer/scan_consolenew/console
	for(var/obj/machinery/computer/scan_consolenew/candidate in GLOB.machines)
		if(is_station_level(candidate.z) && candidate.connected)
			console = candidate
			break
	cs_check("Genetics has a console and scanner", console)
	if(!console)
		return
	var/obj/machinery/dna_scannernew/scanner = console.connected
	console.stat &= ~(NOPOWER|BROKEN)
	scanner.stat &= ~(NOPOWER|BROKEN)
	var/turf/stand
	for(var/dir in GLOB.alldirs)
		var/turf/T = get_step(console, dir)
		if(cs_free_floor(T) && T != scanner.loc)
			stand = T
			break
	H.forceMove(stand || get_turf(console))
	// The subject, with the first gene in their sequence switched on
	var/mob/living/carbon/human/subject = new(get_turf(scanner))
	subject.fully_replace_character_name(null, "Rosa Lindgren")
	scanner.open_machine()
	scanner.close_machine(subject)
	// Not one that turns them into something else (a monkey): the round's genes are random
	var/gene_path
	for(var/path in subject.dna.mutation_index)
		if(!ispath(path, /datum/mutation/human/race))
			gene_path = path
			break
	subject.dna.mutation_index[gene_path] = GET_SEQUENCE(gene_path)
	subject.domutcheck()
	var/edit_path
	for(var/path in subject.dna.mutation_index)
		if(path != gene_path && !ispath(path, /datum/mutation/human/race))
			edit_path = path
			break
	console.jokerready = 0
	console.injectorready = 0
	cs_check("the subject's in the scanner with a gene on", scanner.occupant == subject && subject.dna.get_mutation(gene_path), "[gene_path]")
	usr = H
	console.Topic(null, list("task" = "screen", "text" = "mainmenu"))
	console.Topic(null, list("task" = "inspect", "num" = "[subject.dna.mutation_index.Find(gene_path)]"))
	console.interact(H)
	sleep(3 SECONDS)
	var/datum/tgui/ui = cs_find_ui(H, console)
	if(!ui)
		// The old window
		winset(C, "scannernew", "pos=200,40")
		sleep(10)
		cs_shot("popup_dna_[label]_1_sequencer")
		usr = H
		console.Topic(null, list("task" = "setbuffer", "num" = "1"))
		console.Topic(null, list("task" = "screen", "text" = "ui"))
		sleep(10)
		cs_shot("popup_dna_[label]_2_identifiers")
		usr = H
		console.Topic(null, list("task" = "savemut", "path" = "[gene_path]"))
		console.Topic(null, list("task" = "screen", "text" = "mutations"))
		sleep(10)
		cs_shot("popup_dna_[label]_3_storage")
		H << browse(null, "window=scannernew")
		return
	winset(C, ui.window_id, "pos=200,40")
	sleep(10)
	cs_shot("popup_dna_[label]_1_sequencer", console.name)
	cs_check("the page names genes by alias, never by mutation", !findtext(json_encode(console.ui_data(H)), "/datum/mutation"))
	// Clicked in the window: print an activator for the gene that's on, and store it
	var/injectors = 0
	for(var/obj/item/dnainjector/activator/A in console.loc)
		injectors++
	cs_tgui_do(C, ui.window_id, "click:Print Activator")
	sleep(10)
	var/injectors_after = 0
	for(var/obj/item/dnainjector/activator/A in console.loc)
		injectors_after++
	cs_check("clicking Print Activator prints one", injectors_after == injectors + 1, "[injectors_after - injectors] printed")
	cs_tgui_do(C, ui.window_id, "click:Store")
	sleep(10)
	cs_check("clicking Store stores it", length(console.stored_mutations) == 1, "[length(console.stored_mutations)] stored")
	// A base changed in the window, the JOKER way: it becomes the right one
	usr = H
	console.Topic(null, list("task" = "inspect", "num" = "[subject.dna.mutation_index.Find(edit_path)]"))
	sleep(15)
	var/before = GET_GENE_STRING(edit_path, subject.dna)
	var/right = GET_SEQUENCE(edit_path)
	var/num = 0
	for(var/i in 1 to length_char(before))
		if(copytext_char(before, i, i + 1) != copytext_char(right, i, i + 1))
			num = i
			break
	if(num)
		var/letter = copytext_char(before, num, num + 1)
		// The first base with this letter might not be the wrong one: pick it out by number
		var/datum/mutation/human/edit_mutation = GET_INITIALIZED_MUTATION(edit_path)
		cs_act(console, H, "gene", list("alias" = edit_mutation.alias, "num" = "[num]", "gene" = "JOKER"))
		sleep(5)
		var/now = GET_GENE_STRING(edit_path, subject.dna)
		cs_check("the JOKER puts the right base in", copytext_char(now, num, num + 1) == copytext_char(right, num, num + 1) && console.jokerready > world.time, "base [num]: [letter] -> [copytext_char(now, num, num + 1)], should be [copytext_char(right, num, num + 1)]")
		// And by hand, clicking a base then a letter, once the window has the JOKER's change
		SStgui.update_uis(console)
		sleep(10)
		var/first_letter = copytext_char(now, 1, 2)
		var/other = first_letter == "A" ? "T" : "A"
		cs_tgui_do(C, ui.window_id, "clickexact:[first_letter]")
		sleep(5)
		cs_tgui_do(C, ui.window_id, "clickexact:[other]")
		sleep(10)
		var/after = GET_GENE_STRING(edit_path, subject.dna)
		var/changed = 0
		var/changed_to
		for(var/i in 1 to length_char(after))
			if(copytext_char(after, i, i + 1) != copytext_char(now, i, i + 1))
				changed++
				changed_to = copytext_char(after, i, i + 1)
		cs_check("clicking a base and then a letter changes that base", changed == 1 && changed_to == other, "[now] -> [after]")
		cs_shot("popup_dna_[label]_2_editing", console.name)
	// The unique identifiers and a buffer
	cs_tgui_do(C, ui.window_id, "click:Unique Identifiers")
	sleep(10)
	cs_check("clicking Unique Identifiers opens them", console.current_screen == "ui")
	cs_tgui_do(C, ui.window_id, "click:Save to Buffer")
	sleep(10)
	var/list/slot = console.buffer[1]
	cs_check("clicking Save to Buffer saves the subject", islist(slot) && slot["name"] == subject.real_name)
	cs_tgui_do(C, ui.window_id, "type0:Rosa, before")
	sleep(10)
	slot = console.buffer[1]
	cs_check("typing a label labels it, without a popup", islist(slot) && slot["label"] == "Rosa, before", "[islist(slot) ? slot["label"] : "nothing"]")
	cs_shot("popup_dna_[label]_3_identifiers", console.name)
	// A pulse: the window shows it working, then what it did
	var/list/data = console.ui_data(H)
	var/list/identity = data["identity"]
	var/list/first_block = identity[1]
	var/list/first_char = first_block[1]
	cs_tgui_do(C, ui.window_id, "clickexact:[first_char["char"]]")
	sleep(5)
	cs_check("clicking an identifier block pulses it", console.current_screen == "working")
	sleep(console.radduration * 10 + 15)
	var/last_operation = console.vars["last_operation"] // the new file's: the old build has no such var
	cs_check("and the last operation says what changed", console.current_screen == "ui" && findtext(last_operation, "UI #"), last_operation)
	// Storage, and the chromosomes the old window couldn't eject (only the last)
	var/obj/item/chromosome/first_one = new /obj/item/chromosome/stabilizer(console)
	var/obj/item/chromosome/second_one = new /obj/item/chromosome/synchronizer(console)
	console.stored_chromosomes += first_one
	console.stored_chromosomes += second_one
	cs_tgui_do(C, ui.window_id, "click:Mutations")
	sleep(10)
	cs_shot("popup_dna_[label]_4_storage", console.name)
	cs_tgui_do(C, ui.window_id, "click:Eject")
	sleep(10)
	cs_check("clicking the first chromosome's Eject ejects that one", !(first_one in console.stored_chromosomes) && (second_one in console.stored_chromosomes))
	// What the old Topic took on trust
	cs_act(console, H, "task", list("task" = "screen", "text" = "working"))
	cs_check("the page can't put it to work and lock it", console.current_screen == "mutations", console.current_screen)
	cs_act(console, H, "task", list("task" = "deletemut", "num" = "99"))
	cs_check("nor delete storage that isn't there", length(console.stored_mutations) == 1)
	// A bot's way: Topic() with the mutation, and no window for it
	var/mob/living/carbon/human/bot = new(stand || get_turf(console))
	usr = bot
	console.Topic(null, list("task" = "savemut", "path" = "[gene_path]"))
	cs_check("a bot's Topic() still stores a mutation", length(console.stored_mutations) == 2, "[length(console.stored_mutations)] stored")
	cs_check("and opens no window", !length(bot.open_uis))
	qdel(bot)
	usr = H
	SStgui.close_user_uis(H)

// The newscaster and the security one

/proc/cs_news_channel(name)
	for(var/datum/newscaster/feed_channel/FC in GLOB.news_network.network_channels)
		if(FC.channel_name == name)
			return FC

/// Waits until `what` on `thing` is `value`, up to `seconds`: the window's next click needs the page the last one made
/proc/cs_wait_until(datum/thing, what, value, seconds = 5)
	var/deadline = world.time + seconds SECONDS
	while(world.time < deadline && thing.vars[what] != value)
		sleep(2)
	sleep(5) // and for the page to draw it
	return thing.vars[what] == value

/proc/cs_news(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/assistant)
	var/list/taken = list()
	var/obj/machinery/newscaster/caster = new(cs_open_beside(H, taken))
	taken += caster.loc
	var/obj/machinery/newscaster/security_unit/security = new(cs_open_beside(H, taken))
	caster.stat &= ~(NOPOWER|BROKEN)
	security.stat &= ~(NOPOWER|BROKEN)
	// A photo in hand for the story
	var/datum/picture/pic = new("the bar", "A photo of the bar.", list(), list(), icon('icons/obj/drinks.dmi', "beer"), null, 32, 32, null, "Opening night")
	var/obj/item/photo/photo = new(H.loc, pic)
	H.put_in_active_hand(photo)
	var/channel = "Station Gazette"
	usr = H
	caster.interact(H)
	sleep(3 SECONDS)
	var/datum/tgui/ui = cs_find_ui(H, caster)
	if(!ui)
		// The old windows, filled in the way the old popups would have
		winset(C, "newscaster_main", "pos=200,40")
		sleep(10)
		cs_shot("popup_news_[label]_1_main")
		caster.scan_user(H)
		GLOB.news_network.CreateFeedChannel(channel, caster.scanned_user, FALSE)
		GLOB.news_network.SubmitArticle("<font face=\"[PEN_FONT]\">The bar is open again after the meteor.<br>Drinks are on the Captain.</font>", caster.scanned_user, channel, pic, 0, 1)
		var/datum/newscaster/feed_channel/FC = cs_news_channel(channel)
		var/datum/newscaster/feed_message/story = FC.messages[1]
		var/datum/newscaster/feed_comment/comment = new
		comment.author = "Tomas Reyes (Security Officer)"
		comment.body = "Is it open to Security?"
		comment.time_stamp = station_time_timestamp()
		story.comments += comment
		usr = H
		caster.Topic(null, list("show_channel" = REF(FC)))
		sleep(10)
		cs_shot("popup_news_[label]_2_channel")
		H << browse(null, "window=newscaster_main")
		usr = H
		security.interact(H)
		sleep(2 SECONDS)
		winset(C, "newscaster_main", "pos=200,40")
		sleep(10)
		cs_shot("popup_news_[label]_3_security")
		H << browse(null, "window=newscaster_main")
		return
	winset(C, ui.window_id, "pos=200,40")
	sleep(10)
	cs_shot("popup_news_[label]_0_empty", caster.name)
	// A channel, clicked and typed in the window
	cs_tgui_do(C, ui.window_id, "click:New channel")
	cs_wait_until(caster, "screen", 2)
	cs_tgui_do(C, ui.window_id, "type0:[channel]")
	cs_wait_until(caster, "channel_name", channel)
	cs_tgui_do(C, ui.window_id, "click:Submit")
	cs_wait_until(caster, "screen", 9)
	var/datum/newscaster/feed_channel/FC = cs_news_channel(channel)
	cs_check("typing a name and clicking Submit makes the channel and opens it, with no popups", FC && FC.author == caster.scanned_user && caster.screen == 9 && caster.viewing_channel == FC, "[FC ? FC.author : "no channel"], screen [caster.screen]")
	// A story with the photo
	cs_tgui_do(C, ui.window_id, "click:New story")
	cs_wait_until(caster, "screen", 3)
	cs_act(caster, H, "set_channel_receiving", list("text" = channel))
	cs_tgui_do(C, ui.window_id, "click:Attach the photo")
	sleep(10)
	cs_check("clicking Attach takes the photo in hand", caster.picture == pic)
	cs_tgui_do(C, ui.window_id, "textarea:The bar is open again after the meteor.\nDrinks are on the Captain.")
	sleep(5)
	cs_tgui_do(C, ui.window_id, "click:Submit")
	cs_wait_until(caster, "screen", 9)
	var/datum/newscaster/feed_message/story = length(FC?.messages) ? FC.messages[1] : null
	cs_check("typing the story and clicking Submit posts it and shows it in its channel", story && caster.screen == 9, "[FC ? length(FC.messages) : 0] stories, screen [caster.screen]")
	cs_check("with its photo and both lines", story?.img && findtext(story.body, "Drinks are on the Captain"), "[story ? story.body : "none"]")
	// A comment, in the channel
	cs_tgui_do(C, ui.window_id, "input0:Is it open to Security?")
	sleep(5)
	cs_tgui_do(C, ui.window_id, "click:Comment")
	sleep(10)
	cs_check("typing a comment and clicking Comment posts it", story && length(story.comments) == 1, "[story ? length(story.comments) : 0] comments")
	cs_shot("popup_news_[label]_2_channel", caster.name)
	// The channel's owner can lock the comments; somebody else can't
	var/mob/living/carbon/human/reader = new(cs_open_beside(caster, list(get_turf(H))))
	reader.equipOutfit(/datum/outfit/job/cook)
	cs_act(caster, reader, "lock_comment", list("ref" = REF(story)))
	cs_check("a reader who doesn't own the channel can't lock its comments", story && !story.locked)
	usr = H
	caster.scan_user(H)
	SStgui.update_uis(caster)
	sleep(10)
	cs_tgui_do(C, ui.window_id, "click:Lock comments")
	sleep(10)
	cs_check("the owner clicking Lock comments locks them", story?.locked)
	cs_act(caster, reader, "comment", list("ref" = REF(story), "text" = "Let me in"))
	cs_check("and a comment on a locked story is refused", story && length(story.comments) == 1)
	cs_act(caster, reader, "censor_story_body", list("ref" = REF(story)))
	cs_check("an ordinary newscaster can't censor", story && !story.bodyCensor)
	qdel(reader)
	usr = H
	// The front page, and printing in one click
	cs_tgui_do(C, ui.window_id, "click:Front page")
	cs_wait_until(caster, "screen", 0)
	caster.scan_user(H)
	SStgui.update_uis(caster)
	sleep(10)
	cs_shot("popup_news_[label]_1_front_page", caster.name)
	var/paper = caster.paper_remaining
	cs_tgui_do(C, ui.window_id, "click:Print")
	sleep(10)
	cs_check("clicking Print prints a newspaper there and then", caster.paper_remaining == paper - 1 && (locate(/obj/item/newspaper) in caster.drop_location()) && caster.screen == 0, "[caster.paper_remaining] of [paper] left, screen [caster.screen]")
	SStgui.close_user_uis(H)
	// The security unit: a wanted issue, and censoring on the stories themselves
	security.interact(H)
	sleep(3 SECONDS)
	ui = cs_find_ui(H, security)
	cs_check("the security newscaster opens", ui)
	if(!ui)
		return
	winset(C, ui.window_id, "pos=200,40")
	cs_tgui_do(C, ui.window_id, "click:Wanted")
	cs_wait_until(security, "screen", 14)
	cs_tgui_do(C, ui.window_id, "type0:Griff Mcfrag")
	cs_wait_until(security, "channel_name", "Griff Mcfrag")
	cs_tgui_do(C, ui.window_id, "type1:Broke into the armory. Armed.")
	cs_wait_until(security, "msg", "Broke into the armory. Armed.")
	cs_tgui_do(C, ui.window_id, "click:Submit")
	cs_wait_until(security, "screen", 0)
	var/datum/newscaster/wanted_message/wanted = GLOB.news_network.wanted_issue
	cs_check("filling in the wanted issue and clicking Submit publishes it, with no popups", wanted.active && wanted.criminal == "Griff Mcfrag", "[wanted.active ? wanted.criminal : "not published"]; screen [security.screen], name '[security.channel_name]', description '[security.msg]'")
	sleep(10)
	cs_shot("popup_news_[label]_3_security", security.name)
	cs_tgui_do(C, ui.window_id, "click:Censor story")
	sleep(10)
	cs_check("on a security unit, clicking Censor story on the front page censors it", story?.bodyCensor)
	cs_tgui_do(C, ui.window_id, "click:[channel]")
	cs_wait_until(security, "screen", 9)
	cs_tgui_do(C, ui.window_id, "click:D-Notice")
	sleep(10)
	cs_check("and clicking D-Notice on its channel marks it", FC?.censored)
	cs_shot("popup_news_[label]_4_censor", security.name)
	var/list/front = caster.ui_data(H)["front"]
	var/hidden = TRUE
	for(var/list/entry in front)
		if(entry["channel"] == channel)
			hidden = FALSE
	cs_check("an ordinary newscaster's front page leaves out a D-Noticed channel", hidden)
	SStgui.close_user_uis(H)

// The requests consoles: the station's own, the Bridge's sending to Medbay

/proc/cs_req(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/captain)
	var/obj/machinery/requests_console/bridge
	var/obj/machinery/requests_console/medbay
	for(var/obj/machinery/requests_console/console in GLOB.allConsoles)
		if(!is_station_level(console.z))
			continue
		if(!bridge && console.announcementConsole && console.department == "Bridge")
			bridge = console
		if(!medbay && console.department == "Medbay")
			medbay = console
	cs_check("the Bridge and Medbay have requests consoles", bridge && medbay)
	if(!bridge || !medbay)
		return
	bridge.stat &= ~(NOPOWER|BROKEN)
	var/turf/stand
	for(var/dir in GLOB.alldirs)
		var/turf/T = get_step(bridge, dir)
		if(cs_free_floor(T))
			stand = T
			break
	H.forceMove(stand || get_turf(bridge))
	var/obj/item/card/id/captain_id = H.get_idcard()
	usr = H
	bridge.interact(H)
	sleep(3 SECONDS)
	var/datum/tgui/ui = cs_find_ui(H, bridge)
	if(!ui)
		// The old window
		winset(C, "req_console", "pos=200,40")
		sleep(10)
		cs_shot("popup_req_[label]_1_main")
		usr = H
		bridge.Topic(null, list("setScreen" = "1"))
		sleep(10)
		cs_shot("popup_req_[label]_2_assistance")
		H << browse(null, "window=req_console")
		return
	winset(C, ui.window_id, "pos=200,40")
	sleep(10)
	cs_tgui_do(C, ui.window_id, "click:Assistance")
	cs_wait_until(bridge, "screen", 1)
	cs_shot("popup_req_[label]_2_assistance", bridge.name)
	// A message to Medbay, written in the window and validated with the ID
	cs_act(bridge, H, "write", list("department" = ckey(medbay.department), "priority" = "3"))
	cs_check("EXTREME priority is refused on a console nobody's rewired", bridge.screen == 1)
	cs_act(bridge, H, "write", list("department" = ckey(medbay.department), "priority" = "2"))
	cs_wait_until(bridge, "screen", 9)
	SStgui.update_uis(bridge)
	sleep(10)
	cs_tgui_do(C, ui.window_id, "type0:Need a doctor on the bridge, the Captain fainted")
	cs_wait_until(bridge, "message", "Need a doctor on the bridge, the Captain fainted")
	bridge.attackby(captain_id, H)
	sleep(10)
	cs_check("typing the message and swiping the ID validates it, with no popup", bridge.message && findtext(bridge.msgVerified, H.real_name), "message '[bridge.message]', [bridge.msgVerified ? "validated" : "not validated"]")
	cs_shot("popup_req_[label]_3_writing", bridge.name)
	var/list/medbay_entries = medbay.vars["message_entries"] // the new file's: the old build has no such var
	var/before = length(medbay_entries)
	cs_tgui_do(C, ui.window_id, "click:Send Message")
	cs_wait_until(bridge, "screen", 6)
	cs_check("clicking Send Message sends it", bridge.screen == 6, "screen [bridge.screen]")
	sleep(10)
	var/list/arrived = length(medbay_entries) > before ? medbay_entries[length(medbay_entries)] : null
	cs_check("Medbay gets it, high priority, validated, with Reply to the Bridge", arrived && arrived["priority"] == 2 && findtext(arrived["body"], "Captain fainted") && arrived["verified"] && arrived["reply"] == ckey(bridge.department), "[arrived ? "[arrived["from"]]: [arrived["body"]]" : "nothing"]")
	cs_check("and Medbay's console flashes", medbay.newmessagepriority == 2)
	cs_act(medbay, H, "screen", list("screen" = "8"))
	cs_check("until its messages are read", medbay.newmessagepriority == 0)
	// An announcement, with the Captain's ID
	cs_tgui_do(C, ui.window_id, "click:Announce")
	cs_wait_until(bridge, "screen", 10)
	cs_act(bridge, H, "set_announcement", list("text" = "Drill at noon"))
	cs_act(bridge, H, "announce")
	cs_check("an announcement isn't sent before a card that can is swiped", bridge.screen == 10)
	bridge.attackby(captain_id, H)
	sleep(5)
	cs_tgui_do(C, ui.window_id, "type0:All hands: drill in the cafeteria at noon.")
	cs_wait_until(bridge, "message", "All hands: drill in the cafeteria at noon.")
	cs_shot("popup_req_[label]_4_announcement", bridge.name)
	cs_tgui_do(C, ui.window_id, "click:Announce Message")
	cs_wait_until(bridge, "screen", 0)
	var/announced = FALSE
	for(var/datum/newscaster/feed_channel/FC in GLOB.news_network.network_channels)
		for(var/datum/newscaster/feed_message/story in FC.messages)
			if(findtext(story.body, "drill in the cafeteria"))
				announced = TRUE
	cs_check("swiping the Captain's ID, typing it and clicking Announce Message announces it", announced && bridge.screen == 0)
	// A quick request: one click, with the room
	var/list/requests = GLOB.vars["station_requests"] // the new file's: the old build has no such list
	var/had = length(requests)
	cs_tgui_do(C, ui.window_id, "clickexact:Doctor")
	sleep(15)
	var/datum/station_request/quick = length(requests) > had ? requests[length(requests)] : null
	cs_check("clicking Doctor asks Medbay, with the room and who's asking", quick && quick.to_dept == "Medbay" && quick.kind == "Doctor" && findtext(quick.body, "A doctor is needed in") && findtext(quick.sender, H.real_name), "[quick ? "[quick.to_dept]: [quick.body] ([quick.sender])" : "nothing"]")
	cs_tgui_do(C, ui.window_id, "clickexact:Doctor")
	sleep(15)
	cs_check("and clicking it again straight away doesn't send another", length(requests) == had + 1, "[length(requests) - had] sent")
	// Tracking: Medbay is on it, then done, and the Bridge sees it
	cs_act(bridge, H, "request_status", list("id" = "[quick?.id]", "status" = "done"))
	cs_check("the Bridge can't mark a request it sent to Medbay", quick && quick.status == "new", quick?.status)
	var/mob/living/carbon/human/doctor = new(get_turf(medbay))
	doctor.equipOutfit(/datum/outfit/job/doctor)
	cs_act(medbay, doctor, "request_status", list("id" = "[quick?.id]", "status" = "on it"))
	cs_check("Medbay marks it on it, with who", quick && quick.status == "on it" && findtext(quick.handler, doctor.real_name), "[quick?.status] - [quick?.handler]")
	SStgui.update_uis(bridge)
	cs_tgui_do(C, ui.window_id, "click:Messages")
	sleep(15)
	var/list/sent = bridge.ui_data(H)["sent"]
	var/list/first_sent = length(sent) ? sent[1] : null
	var/list/first_tracking = first_sent ? first_sent["tracking"] : null
	cs_check("and the Bridge's sent list says so", first_tracking && first_tracking["status"] == "on it", "[first_tracking ? first_tracking["status"] : "nothing"]")
	cs_shot("popup_req_[label]_5_tracking", bridge.name)
	cs_act(medbay, doctor, "request_status", list("id" = "[quick?.id]", "status" = "done"))
	cs_check("then done", quick && quick.status == "done")
	qdel(doctor)
	usr = H
	// A crate for Cargo
	var/requested = length(SSshuttle.requestlist)
	cs_tgui_do(C, ui.window_id, "click:Supplies")
	cs_wait_until(bridge, "screen", 2)
	SStgui.update_uis(bridge)
	sleep(10)
	cs_tgui_do(C, ui.window_id, "input0:medical")
	sleep(5)
	cs_tgui_do(C, ui.window_id, "input1:For the injured on the bridge")
	sleep(10)
	cs_shot("popup_req_[label]_6_crates", bridge.name)
	cs_tgui_do(C, ui.window_id, "click:Request")
	sleep(15)
	var/datum/supply_order/order = length(SSshuttle.requestlist) > requested ? SSshuttle.requestlist[length(SSshuttle.requestlist)] : null
	cs_check("searching the crates and clicking Request puts it in cargo's request list", order && order.reason == "For the injured on the bridge", "[order ? "[order.pack.name]: [order.reason]" : "nothing"]")
	var/datum/station_request/crate = length(requests) ? requests[length(requests)] : null
	cs_check("and Cargo Bay hears about it", crate && crate.kind == "crate" && crate.to_dept == "Cargo Bay" && crate.order == order, "[crate ? "[crate.to_dept]: [crate.body]" : "nothing"]")
	// An emergency call
	cs_tgui_do(C, ui.window_id, "click:Security")
	sleep(10)
	cs_check("clicking Security calls Security", bridge.emergency == "Security", "[bridge.emergency]")
	sleep(10)
	cs_shot("popup_req_[label]_1_main", bridge.name)
	SStgui.close_user_uis(H)

// The mining equipment vendor

/proc/cs_mining(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/miner)
	var/obj/machinery/mineral/equipment_vendor/vendor = new(cs_open_beside(H))
	vendor.stat &= ~(NOPOWER|BROKEN)
	var/obj/item/card/id/card = H.get_idcard()
	card.mining_points = 1500
	H.temporarilyRemoveItemFromInventory(card, TRUE)
	H.put_in_active_hand(card)
	usr = H
	vendor.interact(H)
	sleep(3 SECONDS)
	var/datum/tgui/ui = cs_find_ui(H, vendor)
	if(!ui)
		// The old window
		usr = H
		vendor.Topic(null, list("choice" = "insert"))
		sleep(10)
		winset(C, "miningvendor", "pos=200,40")
		sleep(10)
		cs_shot("popup_mining_[label]_1_vendor")
		H << browse(null, "window=miningvendor")
		return
	winset(C, ui.window_id, "pos=200,40")
	sleep(10)
	cs_shot("popup_mining_[label]_0_no_id", vendor.name)
	cs_tgui_do(C, ui.window_id, "click:Insert ID")
	cs_wait_until(vendor, "inserted_id", card)
	cs_check("clicking Insert ID puts the ID in", vendor.inserted_id == card)
	sleep(10)
	cs_shot("popup_mining_[label]_1_vendor", vendor.name)
	cs_tgui_do(C, ui.window_id, "input0:silver")
	sleep(10)
	cs_tgui_do(C, ui.window_id, "click:Buy")
	sleep(10)
	cs_check("searching and clicking Buy buys a silver pickaxe for 1000", card.mining_points == 500 && (locate(/obj/item/pickaxe/silver) in vendor.loc), "[card.mining_points] points left")
	cs_shot("popup_mining_[label]_2_bought", vendor.name)
	var/diamond = 0
	for(var/i in 1 to length(vendor.prize_list))
		var/datum/data/mining_equipment/prize = vendor.prize_list[i]
		if(prize.equipment_path == /obj/item/pickaxe/diamond)
			diamond = i
	cs_act(vendor, H, "purchase", list("index" = "[diamond]"))
	cs_check("one it can't afford isn't sold", card.mining_points == 500 && !(locate(/obj/item/pickaxe/diamond) in vendor.loc), "[card.mining_points] points left")
	cs_act(vendor, H, "purchase", list("index" = "999"))
	cs_check("nor anything it doesn't sell", card.mining_points == 500)
	cs_tgui_do(C, ui.window_id, "click:Eject ID")
	cs_wait_until(vendor, "inserted_id", null)
	cs_check("clicking Eject ID gives it back", !vendor.inserted_id && (card in H.GetAllContents()))
	SStgui.close_user_uis(H)

// The biogenerator

/proc/cs_biogen(client/C, mob/living/carbon/human/H, label)
	var/obj/machinery/biogenerator/biogen = new(cs_open_beside(H))
	biogen.stat &= ~(NOPOWER|BROKEN)
	for(var/i in 1 to 5)
		new /obj/item/reagent_containers/food/snacks/grown/banana(biogen)
	if(!("ui_categories" in biogen.vars))
		// The old window, which lists nothing without a container
		biogen.beaker = new /obj/item/reagent_containers/glass/beaker/large(biogen)
		biogen.points = 500
		usr = H
		biogen.interact(H)
		sleep(20)
		winset(C, "biogen", "pos=200,40")
		sleep(10)
		cs_shot("popup_biogen_[label]_1_biomass")
		H << browse(null, "window=biogen")
		return
	usr = H
	biogen.interact(H)
	var/datum/tgui/ui = cs_find_ui(H, biogen)
	if(!ui)
		cs_check("the window opens", FALSE)
		return
	winset(C, ui.window_id, "pos=200,40")
	sleep(10)
	cs_shot("popup_biogen_[label]_0_no_container", biogen.name)
	cs_tgui_do(C, ui.window_id, "click:Activate")
	var/deadline = world.time + 15 SECONDS
	while(world.time < deadline && (biogen.processing || (locate(/obj/item/reagent_containers/food/snacks/grown) in biogen)))
		sleep(2)
	cs_check("clicking Activate turns the growns into biomass", biogen.points > 0 && !(locate(/obj/item/reagent_containers/food/snacks/grown) in biogen), "[biogen.points] biomass")
	biogen.points = 500
	var/obj/item/reagent_containers/glass/beaker/large/B = new(H.loc)
	H.put_in_active_hand(B)
	biogen.attackby(B, H)
	SStgui.update_uis(biogen)
	sleep(10)
	cs_check("a container goes in by hand", biogen.beaker == B)
	cs_shot("popup_biogen_[label]_1_biomass", biogen.name)
	var/datum/design/milk = SSresearch.techweb_design_by_id("milk")
	var/cost = milk.materials[MAT_BIOMASS] / biogen.efficiency
	cs_tgui_do(C, ui.window_id, "input0:10 milk")
	sleep(10)
	cs_tgui_do(C, ui.window_id, "click:Make")
	sleep(10)
	cs_check("searching and clicking Make pours 10 milk", B.reagents.get_reagent_amount(/datum/reagent/consumable/milk) == 10 && biogen.points == 500 - cost, "[B.reagents.get_reagent_amount(/datum/reagent/consumable/milk)]u, [biogen.points] biomass")
	cs_tgui_do(C, ui.window_id, "click:x5")
	sleep(10)
	cs_check("x5 pours 50 more", B.reagents.get_reagent_amount(/datum/reagent/consumable/milk) == 60 && biogen.points == 500 - 6 * cost, "[B.reagents.get_reagent_amount(/datum/reagent/consumable/milk)]u, [biogen.points] biomass")
	cs_tgui_do(C, ui.window_id, "click:x5")
	sleep(10)
	cs_check("x5 with room for four makes four and says the container's full", B.reagents.get_reagent_amount(/datum/reagent/consumable/milk) == 100 && biogen.points == 500 - 10 * cost && biogen.menustat == "nobeakerspace", "[B.reagents.get_reagent_amount(/datum/reagent/consumable/milk)]u, [biogen.points] biomass, [biogen.menustat]")
	SStgui.update_uis(biogen)
	sleep(10)
	cs_shot("popup_biogen_[label]_2_full", biogen.name)
	var/points = biogen.points
	cs_act(biogen, H, "create", list("id" = "not_a_design", "amount" = "1"))
	cs_act(biogen, H, "create", list("id" = "milk", "amount" = "7"))
	cs_check("nothing it hasn't the design for, nor an amount it doesn't offer", biogen.points == points)
	cs_tgui_do(C, ui.window_id, "click:Detach")
	cs_wait_until(biogen, "beaker", null)
	cs_check("clicking Detach gives the container back", !biogen.beaker && B.loc == biogen.drop_location())
	SStgui.close_user_uis(H)

// The plant DNA manipulator

/proc/cs_plantdna(client/C, mob/living/carbon/human/H, label)
	var/obj/machinery/plantgenes/M = new(cs_open_beside(H))
	M.stat &= ~(NOPOWER|BROKEN)
	var/obj/item/seeds/tomato/S = new(H.loc)
	var/obj/item/disk/plantgene/D = new(H.loc)
	if(!hascall(M, "gene_extract_limit"))
		// The old window
		H.put_in_active_hand(S)
		M.attackby(S, H)
		H.put_in_active_hand(D)
		M.attackby(D, H)
		sleep(20)
		winset(C, "plantdna", "pos=200,40")
		sleep(10)
		cs_shot("popup_plantdna_[label]_1_genes")
		H << browse(null, "window=plantdna")
		return
	usr = H
	M.interact(H)
	var/datum/tgui/ui = cs_find_ui(H, M)
	if(!ui)
		cs_check("the window opens", FALSE)
		return
	winset(C, ui.window_id, "pos=200,40")
	sleep(10)
	cs_shot("popup_plantdna_[label]_0_empty", M.name)
	H.put_in_active_hand(S)
	SStgui.update_uis(M)
	sleep(5)
	cs_tgui_do(C, ui.window_id, "clickexact:Insert")
	cs_wait_until(M, "seed", S)
	cs_check("clicking Insert with seeds in hand puts them in", M.seed == S)
	H.put_in_active_hand(D)
	SStgui.update_uis(M)
	sleep(5)
	cs_tgui_do(C, ui.window_id, "clickexact:Insert")
	cs_wait_until(M, "disk", D)
	cs_check("and with a disk in hand, the disk", M.disk == D)
	SStgui.update_uis(M)
	sleep(10)
	cs_shot("popup_plantdna_[label]_1_genes", M.name)
	cs_tgui_do(C, ui.window_id, "clickexact:Extract")
	cs_wait_until(M, "operation", "extract")
	cs_check("Extract asks for confirmation first", M.operation == "extract" && M.seed == S)
	sleep(10)
	cs_shot("popup_plantdna_[label]_2_confirm", M.name)
	cs_tgui_do(C, ui.window_id, "clickexact:Abort")
	cs_wait_until(M, "operation", "")
	cs_check("Abort calls it off", M.operation == "" && M.seed == S && !D.gene)
	var/genes_before = length(S.genes)
	cs_tgui_do(C, ui.window_id, "clickexact:Remove")
	cs_wait_until(M, "operation", "remove")
	cs_tgui_do(C, ui.window_id, "clickexact:Confirm")
	cs_wait_until(M, "operation", "")
	cs_check("Remove, confirmed, takes a content gene out", length(S.genes) == genes_before - 1, "[genes_before] genes -> [length(S.genes)]")
	cs_tgui_do(C, ui.window_id, "clickexact:Extract")
	cs_wait_until(M, "operation", "extract")
	cs_tgui_do(C, ui.window_id, "clickexact:Confirm")
	cs_wait_until(M, "seed", null)
	cs_check("Extract, confirmed, puts the potency gene on the disk and uses up the sample", istype(D.gene, /datum/plant_gene/core/potency) && !M.seed && QDELETED(S))
	var/obj/item/seeds/tomato/S2 = new(M)
	M.insert_seed(S2)
	var/datum/plant_gene/core/potency/P = D.gene
	P.value = 42
	SStgui.update_uis(M)
	sleep(10)
	cs_tgui_do(C, ui.window_id, "clickexact:Replace")
	cs_wait_until(M, "operation", "replace")
	cs_tgui_do(C, ui.window_id, "clickexact:Confirm")
	cs_wait_until(M, "operation", "")
	cs_check("Replace, confirmed, gives a new sample the disk's potency", S2.potency == 42, "potency [S2.potency]")
	var/genes = length(S2.genes)
	cs_act(M, H, "gene", list("ref" = "not_a_gene", "op" = "remove"))
	cs_act(M, H, "gene", list("ref" = REF(S2.genes[length(S2.genes)]), "op" = "melt"))
	cs_check("nothing for a gene it hasn't got, nor an operation it hasn't", M.operation == "" && length(S2.genes) == genes)
	cs_tgui_do(C, ui.window_id, "clickexact:Eject")
	cs_wait_until(M, "seed", null)
	cs_check("Eject gives the sample back", !M.seed && !QDELETED(S2) && isturf(S2.loc) || (S2 in H.GetAllContents()))
	SStgui.close_user_uis(H)

// The PDA

/proc/cs_pda(client/C, mob/living/carbon/human/H, label)
	var/obj/item/pda/P = new(H.loc)
	P.owner = H.real_name
	P.ownjob = "Assistant"
	P.update_label()
	H.put_in_active_hand(P)
	var/obj/item/pda/friend = new(H.loc)
	friend.owner = "Riley Test"
	friend.ownjob = "Botanist"
	friend.update_label()
	if(!hascall(P, "pda_apps"))
		// The old window
		usr = H
		P.attack_self(H)
		sleep(20)
		winset(C, "pda", "pos=200,40")
		sleep(10)
		cs_shot("popup_pda_[label]_0_home")
		P.Topic(null, list("choice" = "2"))
		sleep(20)
		cs_shot("popup_pda_[label]_1_messenger")
		H << browse(null, "window=pda")
		return
	usr = H
	P.attack_self(H)
	var/datum/tgui/ui = cs_find_ui(H, P)
	if(!ui)
		cs_check("the window opens", FALSE)
		return
	winset(C, ui.window_id, "pos=200,40")
	sleep(10)
	cs_shot("popup_pda_[label]_0_home", "Personal Data Assistant")
	cs_tgui_do(C, ui.window_id, "click:Messenger")
	cs_wait_until(P, "pda_screen", "messenger")
	cs_tgui_do(C, ui.window_id, "clickexact:New")
	cs_wait_until(P, "pda_screen", "contacts")
	cs_tgui_do(C, ui.window_id, "clickexact:Riley Test (Botanist)")
	cs_wait_until(P, "pda_screen", "thread")
	cs_check("Messenger, New and a name opens a conversation with them", P.vars["pda_screen"] == "thread" && P.vars["pda_thread_open"] == "Riley Test (Botanist)")
	sleep(10)
	cs_tgui_do(C, ui.window_id, "input0:Are the tomatoes in yet?")
	sleep(5)
	cs_tgui_do(C, ui.window_id, "clickexact:Send")
	sleep(20)
	var/list/mine = LAZYACCESS(P.vars["pda_threads"], "Riley Test (Botanist)")
	var/list/theirs = LAZYACCESS(friend.vars["pda_threads"], "[H.real_name] (Assistant)")
	cs_check("typing and Send delivers it, into both sides' conversations and the old message log", findtext(friend.tnote, "Are the tomatoes in yet?") && length(mine?["messages"]) == 1 && length(theirs?["messages"]) == 1)
	friend.last_text = 0
	call(friend, "send_message")(H, list(P), FALSE, "Ten minutes, I'm watering them")
	SStgui.update_uis(P)
	sleep(10)
	cs_check("a reply lands in the same conversation", length(mine?["messages"]) == 2)
	cs_shot("popup_pda_[label]_1_thread", "Personal Data Assistant")
	cs_act(P, H, "screen", list("screen" = "messenger"))
	SStgui.update_uis(P)
	friend.last_text = 0
	call(friend, "send_message")(H, list(P), FALSE, "Also we're out of ash")
	SStgui.update_uis(P)
	sleep(10)
	cs_check("one that comes in while it's not open counts as unread", mine?["unread"] == 1)
	cs_shot("popup_pda_[label]_2_messenger", "Personal Data Assistant")
	cs_act(P, H, "screen", list("screen" = "home"))
	SStgui.update_uis(P)
	sleep(5)
	cs_tgui_do(C, ui.window_id, "click:Notes")
	cs_wait_until(P, "pda_screen", "notes")
	sleep(5)
	cs_tgui_do(C, ui.window_id, "textarea:Buy more seeds")
	sleep(5)
	cs_shot("popup_pda_[label]_4_notes", "Personal Data Assistant")
	cs_tgui_do(C, ui.window_id, "clickexact:Save")
	sleep(10)
	cs_check("Notes are typed in and saved", P.note == "Buy more seeds", P.note)
	cs_act(P, H, "screen", list("screen" = "home"))
	SStgui.update_uis(P)
	sleep(5)
	cs_tgui_do(C, ui.window_id, "click:Settings")
	cs_wait_until(P, "pda_screen", "settings")
	sleep(5)
	var/was_silent = P.silent
	cs_tgui_do(C, ui.window_id, "clickexact:On")
	sleep(5)
	cs_check("the ringer turns off", P.silent && !was_silent)
	cs_tgui_do(C, ui.window_id, "type0:chirp")
	cs_tgui_do(C, ui.window_id, "clickexact:Set")
	sleep(5)
	cs_check("a ringtone is typed in and set", P.ttone == "chirp", P.ttone)
	var/datum/component/uplink/uplink = P.AddComponent(/datum/component/uplink, H.key)
	uplink.unlock_code = "Orange 42"
	cs_tgui_do(C, ui.window_id, "type0:orange 42")
	cs_tgui_do(C, ui.window_id, "clickexact:Set")
	sleep(10)
	cs_check("an uplink's code as the ringtone opens the uplink and keeps the old tone", !uplink.locked && P.ttone == "chirp", "locked [uplink.locked], tone [P.ttone]")
	SStgui.close_user_uis(H)
	qdel(uplink)
	P.cartridge = new /obj/item/cartridge/engineering(P)
	P.cartridge.host_pda = P
	usr = H
	P.attack_self(H)
	ui = cs_find_ui(H, P)
	cs_act(P, H, "screen", list("screen" = "home"))
	SStgui.update_uis(P)
	sleep(10)
	cs_shot("popup_pda_[label]_3_cartridge", "Personal Data Assistant")
	if(ui)
		cs_tgui_do(C, ui.window_id, "click:Power Monitor")
	sleep(20)
	cs_check("a cartridge program opens its old window, and this one shuts", P.mode == 43 && !SStgui.get_open_ui(H, P, "main"), "mode [P.mode]")
	P.Topic(null, list("choice" = "Return"))
	sleep(20)
	cs_check("Return there comes back here", P.mode == 0 && cs_find_ui(H, P))
	SStgui.close_user_uis(H)
	H << browse(null, "window=pda")

// The message monitor console

/proc/cs_msgmon(client/C, mob/living/carbon/human/H, label)
	var/obj/machinery/computer/message_monitor/M = new(cs_open_beside(H))
	M.stat &= ~(NOPOWER|BROKEN)
	var/obj/machinery/telecomms/message_server/server = M.linkedServer
	if(!server)
		cs_check("there's a message server to link to", FALSE)
		return
	var/key = server.decryptkey
	var/obj/item/pda/P1 = new(H.loc)
	P1.owner = "Sam Sender"
	P1.ownjob = "Cook"
	var/obj/item/pda/P2 = new(H.loc)
	P2.owner = "Robin Reader"
	P2.ownjob = "Botanist"
	call(P1, "send_message")(H, list(P2), FALSE, "Lunch is ready")
	if(!hascall(M, "msgmon_server_down"))
		// The old window, logged in on its logs
		M.auth = TRUE
		M.screen = 1
		usr = H
		M.interact(H)
		sleep(20)
		winset(C, "hologram_console", "pos=200,40")
		sleep(10)
		cs_shot("popup_msgmon_[label]_1_logs")
		H << browse(null, "window=hologram_console")
		return
	usr = H
	M.interact(H)
	var/datum/tgui/ui = cs_find_ui(H, M)
	if(!ui)
		cs_check("the window opens", FALSE)
		return
	winset(C, ui.window_id, "pos=200,40")
	sleep(10)
	cs_shot("popup_msgmon_[label]_0_locked", M.name)
	cs_tgui_do(C, ui.window_id, "input0:not the key")
	sleep(3)
	cs_tgui_do(C, ui.window_id, "clickexact:Log in")
	sleep(10)
	cs_check("a wrong key doesn't log in", !M.auth)
	cs_tgui_do(C, ui.window_id, "input0:[key]")
	sleep(3)
	cs_tgui_do(C, ui.window_id, "clickexact:Log in")
	cs_wait_until(M, "auth", TRUE)
	cs_check("the server's key, typed in, does", M.auth)
	sleep(5)
	cs_tgui_do(C, ui.window_id, "clickexact:Messages")
	cs_wait_until(M, "screen", 1)
	sleep(10)
	var/datum/data_pda_msg/logged
	for(var/datum/data_pda_msg/L in server.pda_msgs)
		if(L.message == "Lunch is ready")
			logged = L
	cs_check("the Messages tab shows the logs, with the message sent", M.screen == 1 && logged)
	cs_shot("popup_msgmon_[label]_1_logs", M.name)
	if(logged)
		cs_act(M, H, "delete_log", list("ref" = REF(logged)))
		cs_check("a log can be deleted", !(logged in server.pda_msgs))
	SStgui.update_uis(M)
	sleep(5)
	cs_tgui_do(C, ui.window_id, "clickexact:Send a message")
	cs_wait_until(M, "screen", 3)
	sleep(5)
	cs_tgui_do(C, ui.window_id, "type0:Captain Fake")
	cs_tgui_do(C, ui.window_id, "type2:Report to the bridge")
	cs_act(M, H, "custom", list("field" = "recipient", "value" = REF(P2)))
	SStgui.update_uis(M)
	sleep(10)
	cs_shot("popup_msgmon_[label]_2_custom", M.name)
	cs_tgui_do(C, ui.window_id, "clickexact:Send")
	sleep(10)
	cs_check("a message sent as somebody else reaches the PDA in their name", findtext(P2.tnote, "Report to the bridge") && findtext(P2.tnote, "Captain Fake"), M.customsender)
	cs_tgui_do(C, ui.window_id, "clickexact:Key")
	cs_wait_until(M, "screen", 0)
	sleep(5)
	cs_tgui_do(C, ui.window_id, "input0:[key]")
	cs_tgui_do(C, ui.window_id, "input1:newkey42")
	sleep(3)
	cs_tgui_do(C, ui.window_id, "clickexact:Set key")
	sleep(10)
	cs_check("the key changes with the old one", server.decryptkey == "newkey42")
	server.decryptkey = key
	cs_tgui_do(C, ui.window_id, "clickexact:Log out")
	cs_wait_until(M, "auth", FALSE)
	cs_check("Log out", !M.auth)
	SStgui.close_user_uis(H)

// A telecomms machine's multitool menu

/proc/cs_tcmachine(client/C, mob/living/carbon/human/H, label)
	var/obj/machinery/telecomms/relay/R = new(cs_open_beside(H))
	R.stat &= ~(NOPOWER|BROKEN)
	R.on = TRUE
	R.toggled = TRUE
	R.id = "Test Relay"
	R.freq_listening = list(FREQ_COMMON)
	var/obj/machinery/telecomms/bus/B = new(get_turf(H))
	B.id = "Test Bus"
	B.network = R.network
	var/obj/item/multitool/tool = new(H.loc)
	H.put_in_active_hand(tool)
	usr = H
	R.attackby(tool, H)
	if(!hascall(R, "tcomms_tool_ok"))
		sleep(20)
		winset(C, "tcommachine", "pos=200,40")
		sleep(40)
		cs_shot("popup_tcmachine_[label]_0_menu")
		H << browse(null, "window=tcommachine")
		return
	var/datum/tgui/ui = cs_find_ui(H, R)
	if(!ui)
		cs_check("a multitool on it opens the window", FALSE)
		return
	winset(C, ui.window_id, "pos=200,40")
	sleep(10)
	cs_shot("popup_tcmachine_[label]_0_menu", "[R.name] Access")
	cs_tgui_do(C, ui.window_id, "type0:Relay Alpha")
	sleep(5)
	cs_check("the ID is typed in", R.id == "Relay Alpha", R.id)
	cs_tgui_do(C, ui.window_id, "input2:145.9")
	sleep(3)
	cs_tgui_do(C, ui.window_id, "clickexact:Add filter")
	sleep(5)
	cs_check("a frequency filter is added, 145.9 read as 1459", (1459 in R.freq_listening))
	SStgui.update_uis(R)
	sleep(5)
	cs_tgui_do(C, ui.window_id, "clickexact:145.9 GHz")
	sleep(5)
	cs_check("and taken off again", !(1459 in R.freq_listening))
	cs_tgui_do(C, ui.window_id, "clickexact:Yes")
	sleep(5)
	cs_check("the relay's broadcasting switches off", !R.broadcasting)
	tool.buffer = B
	SStgui.update_uis(R)
	sleep(5)
	cs_tgui_do(C, ui.window_id, "clickexact:Link")
	sleep(5)
	cs_check("Link joins it to the machine in the multitool's buffer, both ways", (B in R.links) && (R in B.links))
	SStgui.update_uis(R)
	sleep(5)
	cs_shot("popup_tcmachine_[label]_1_linked", "[R.name] Access")
	cs_act(R, H, "unlink", list("index" = "[R.links.Find(B)]"))
	cs_check("Unlink parts them", !(B in R.links) && !(R in B.links))
	SStgui.update_uis(R)
	sleep(5)
	cs_tgui_do(C, ui.window_id, "clickexact:Flush")
	sleep(5)
	cs_check("Flush empties the buffer", !tool.buffer)
	SStgui.update_uis(R)
	sleep(5)
	cs_tgui_do(C, ui.window_id, "clickexact:Store this machine")
	sleep(5)
	cs_check("and Store this machine puts it there", tool.buffer == R)
	cs_tgui_do(C, ui.window_id, "clickexact:On")
	sleep(5)
	cs_check("Power turns it off", !R.toggled)
	SStgui.close_user_uis(H)
	H.dropItemToGround(tool)
	cs_act(R, H, "toggle")
	cs_check("nothing without a multitool in hand", !R.toggled)

// The robotics control console

/proc/cs_robotics(client/C, mob/living/carbon/human/H, label)
	var/obj/machinery/computer/robotics/M = new(cs_open_beside(H))
	M.stat &= ~(NOPOWER|BROKEN)
	var/obj/item/card/id/card = H.get_idcard()
	if(!card)
		card = new /obj/item/card/id(H.loc) // in hand: the ID slot holds an empty PDA
		H.put_in_active_hand(card)
	card.access |= ACCESS_ROBOTICS
	var/mob/living/silicon/robot/R = new(get_turf(H))
	R.name = "Cyborg-Test"
	var/mob/living/simple_animal/drone/D = new(get_turf(H))
	D.name = "Drone (Test)"
	usr = H
	M.interact(H)
	if(!hascall(M, "ui_data") || !cs_find_ui(H, M))
		sleep(20)
		winset(C, "computer", "pos=200,40")
		sleep(20)
		cs_shot("popup_robotics_[label]_0_units")
		H << browse(null, "window=computer")
		return
	var/datum/tgui/ui = cs_find_ui(H, M)
	winset(C, ui.window_id, "pos=200,40")
	sleep(10)
	cs_shot("popup_robotics_[label]_0_units", "Robotics Control Console")
	var/list/free = list() // the station's own (an AI shell) may be listed before ours: whichever is first
	for(var/mob/living/silicon/robot/other in GLOB.silicon_mobs)
		if(!other.lockcharge)
			free += other
	cs_tgui_do(C, ui.window_id, "clickexact:Lockdown")
	sleep(5)
	var/locked_any = FALSE
	for(var/mob/living/silicon/robot/other in free)
		if(other.lockcharge)
			locked_any = TRUE
	cs_check("one click on Lockdown only asks", !locked_any)
	cs_shot("popup_robotics_[label]_1_sure", "Robotics Control Console")
	cs_tgui_do(C, ui.window_id, "clickexact:Lockdown? Sure")
	sleep(10)
	for(var/mob/living/silicon/robot/other in free)
		if(other.lockcharge)
			R = other
	cs_check("the second locks the cyborg down", R.lockcharge, R.name)
	SStgui.update_uis(M)
	sleep(10)
	cs_tgui_do(C, ui.window_id, "clickexact:Release")
	sleep(3)
	cs_tgui_do(C, ui.window_id, "clickexact:Release? Sure")
	sleep(10)
	cs_check("Release, twice, lets it go", !R.lockcharge)
	cs_act(M, H, "destroy_drone", list("ref" = REF(D)))
	sleep(5)
	cs_check("a drone can be destroyed", QDELETED(D) || D.stat == DEAD)
	card.access -= ACCESS_ROBOTICS
	cs_act(M, H, "lockdown", list("ref" = REF(R)))
	cs_check("no lockdown without robotics access", !R.lockcharge)
	SStgui.close_user_uis(H)
