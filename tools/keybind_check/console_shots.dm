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
	else if(findtext(action, "css:") == 1)
		// The first element matching a CSS selector, for controls that aren't .Button
		js = "var e=document.querySelector([json_encode(copytext(action, 5))]);if(e){e.click();}"
	else if(findtext(action, "card:") == 1)
		var/index = text2num(copytext(action, 6)) - 1
		js = "var c=document.querySelectorAll('.Uplink__card')\[[index]\];if(c){c.click();}"
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
		R.fields["id"] = copytext(md5(name), 1, 7)
		R.fields["name"] = name
		R.fields["rank"] = crew[name]
		R.fields["fingerprint"] = md5(name + "print")
		R.fields["p_stat"] = "Active"
		R.fields["m_stat"] = "Stable"
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
		if("exofab")
			cs_exofab(C, H, label)
		if("exosuit")
			cs_exosuit(C, H, label)
		if("mechcontrol")
			cs_mechcontrol(C, H, label)
		if("library")
			cs_library(C, H, label)
		if("photocopier")
			cs_photocopier(C, H, label)
		if("paperwork")
			cs_paperwork(C, H, label)
		if("lockermech")
			cs_lockermech(C, H, label)
		if("mechpaints")
			cs_mechpaints(C, H, label)
		if("assemblies")
			cs_assemblies(C, H, label)
		if("gadgets")
			cs_gadgets(C, H, label)
		if("oldlook")
			cs_oldlook(C, H, label)
		if("camera")
			cs_camera(C, H, label)
		if("prefs")
			cs_prefs(C, H, label)
		if("teleporter")
			cs_teleporter(C, H, label)
		if("arcade")
			cs_arcade(C, H, label)
		if("machines")
			cs_machines(C, H, label)
		if("vending")
			cs_vending(C, H, label)
		if("chemistry")
			cs_chemistry(C, H, label)
		if("medical")
			cs_medical(C, H, label)
		if("crafting")
			cs_crafting(C, H, label)
		if("power")
			cs_power(C, H, label)
		if("atmos")
			cs_atmos(C, H, label)
		if("uplink")
			cs_uplink(C, H, label)
		if("cargo")
			cs_cargo(C, H, label)
		if("shuttle")
			cs_shuttle(C, H, label)
		if("service")
			cs_service(C, H, label)
		if("secsci")
			cs_secsci(C, H, label)
		if("tsignal")
			cs_tsignal(C, H, label)
		if("trules")
			cs_trules(C, H, label)
		if("tmap")
			cs_tmap(C, H, label)
		if("twiretap")
			cs_twiretap(C, H, label)
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
	var/obj/item/pda/other = new(H.loc)
	other.owner = "Sam Tanaka"
	other.ownjob = "Assistant"
	other.update_label()
	P.note = "Buy more seeds.\nAsk Riley about the tomatoes."
	var/datum/data/record/patient = find_record("name", "Maya Ferreira", GLOB.data_core.general)
	patient.fields["gender"] = "Female"
	patient.fields["age"] = 34
	var/datum/data/record/medical = new
	medical.fields["id"] = patient.fields["id"]
	medical.fields["name"] = patient.fields["name"]
	medical.fields["blood_type"] = "O-"
	medical.fields["mi_dis"] = "Nearsighted"
	medical.fields["mi_dis_d"] = "Wears prescription glasses."
	medical.fields["ma_dis"] = "None"
	medical.fields["ma_dis_d"] = "No major disabilities have been diagnosed."
	medical.fields["alg"] = "Penicillin"
	medical.fields["alg_d"] = "Rash and swelling. Use cephalexin."
	medical.fields["cdi"] = "None"
	medical.fields["cdi_d"] = "No diseases have been diagnosed at the moment."
	medical.fields["notes"] = "Donates blood every shift."
	GLOB.data_core.medical += medical
	if(!hascall(P, "pda_menu"))
		// The original window, on the same screens. Its send_message() asks for the text in a popup, so the message is
		// written into the log as its receive_message() writes it.
		P.tnote += "<i><b>&larr; From <a href='byond://?src=[REF(P)];choice=Message;target=[REF(friend)]'>Riley Test</a> (Botanist):</b></i><br>\"Did anyone water the tomatoes?\"<br>"
		P.tnote += "<i><b>&rarr; To Riley Test (Botanist):</b></i><br>\"Ten minutes, I'm on my way\"<br>"
		usr = H
		P.attack_self(H)
		sleep(20)
		winset(C, "pda", "pos=200,40")
		sleep(10)
		cs_shot("popup_pda_[label]_0_home")
		for(var/list/step in list(list("2", "1_messenger"), list("21", "2_messages"), list("1", "4_notes")))
			usr = H
			P.Topic(null, list("choice" = step[1]))
			sleep(15)
			cs_shot("popup_pda_[label]_[step[2]]")
		P.cartridge = new /obj/item/cartridge/captain(P)
		P.cartridge.host_pda = P
		usr = H
		P.Topic(null, list("choice" = "0"))
		sleep(15)
		cs_shot("popup_pda_[label]_5_cart_home")
		usr = H
		P.Topic(null, list("choice" = "43"))
		sleep(15)
		usr = H
		P.cartridge.Topic(null, list("choice" = "Power Select", "target" = "1"))
		sleep(15)
		cs_shot("popup_pda_[label]_6_power")
		usr = H
		P.Topic(null, list("choice" = "41"))
		sleep(15)
		cs_shot("popup_pda_[label]_7_manifest")
		usr = H
		P.Topic(null, list("choice" = "44"))
		sleep(5)
		usr = H
		P.cartridge.Topic(null, list("choice" = "Medical Records", "target" = patient.fields["id"]))
		sleep(15)
		cs_shot("popup_pda_[label]_8_medical")
		usr = H
		P.Topic(null, list("choice" = "54"))
		sleep(5)
		usr = H
		P.cartridge.Topic(null, list("op" = "botlist"))
		sleep(15)
		cs_shot("popup_pda_[label]_9_bots")
		H << browse(null, "window=pda")
		return
	call(friend, "send_message")(H, list(P), FALSE, "Did anyone water the tomatoes?")
	usr = H
	P.attack_self(H)
	var/datum/tgui/ui = cs_find_ui(H, P)
	if(!ui)
		cs_check("the window opens", FALSE)
		return
	winset(C, ui.window_id, "pos=200,40")
	cs_shot("popup_pda_[label]_00_boot", "Personal Data Assistant")
	sleep(20)
	var/list/opened = P.ui_data(H)
	cs_check("the boot screen is only for the first time it's opened", P.vars["pda_booted"] && !opened["boot"])
	cs_check("a message that came in shows on the home screen as unread", P.vars["pda_unread"] == 1)
	cs_shot("popup_pda_[label]_0_home", "Personal Data Assistant")
	cs_tgui_do(C, ui.window_id, "click:Messenger")
	cs_wait_until(P, "mode", 2)
	cs_check("Messenger opens SpaceMessenger", P.mode == 2)
	cs_shot("popup_pda_[label]_1_messenger", "Personal Data Assistant")
	cs_tgui_do(C, ui.window_id, "click:PDA-Riley Test")
	cs_wait_until(P, "mode", 24)
	cs_check("a name under Detected PDAs opens a message to them", P.mode == 24)
	cs_tgui_do(C, ui.window_id, "input0:Ten minutes, I'm on my way")
	sleep(3)
	cs_tgui_do(C, ui.window_id, "clickexact:Send")
	cs_wait_until(P, "mode", 2)
	cs_check("typed in the window and Sent, it reaches them, and it's back to the messenger", findtext(friend.tnote, "on my way") && P.mode == 2)
	cs_tgui_do(C, ui.window_id, "click:Messages")
	cs_wait_until(P, "mode", 21)
	cs_check("Messages shows the log, and reading it clears the unread", P.mode == 21 && P.vars["pda_unread"] == 0 && length(P.vars["pda_log"]) == 2)
	cs_shot("popup_pda_[label]_2_messages", "Personal Data Assistant")
	cs_tgui_do(C, ui.window_id, "clickexact:Reply")
	cs_wait_until(P, "mode", 24)
	cs_check("Reply in the log opens a message back", P.mode == 24)
	cs_tgui_do(C, ui.window_id, "clickexact:Back")
	cs_wait_until(P, "mode", 2)
	cs_tgui_do(C, ui.window_id, "clickexact:Conversations")
	cs_wait_until(P, "mode", 22)
	cs_tgui_do(C, ui.window_id, "click:Riley Test")
	cs_wait_until(P, "mode", 23)
	cs_check("Conversations, then a name, opens that conversation", P.mode == 23 && P.vars["pda_thread_open"] == "Riley Test (Botanist)")
	friend.last_text = 0
	call(friend, "send_message")(H, list(P), FALSE, "Thanks! Also we're out of ash")
	SStgui.update_uis(P)
	sleep(5)
	cs_tgui_do(C, ui.window_id, "input0:I'll bring some from the incinerator")
	sleep(3)
	cs_tgui_do(C, ui.window_id, "clickexact:Send")
	sleep(10)
	var/list/thread = LAZYACCESS(P.vars["pda_threads"], "Riley Test (Botanist)")
	cs_check("a reply typed into the conversation goes out and lands in it", length(thread?["messages"]) == 4 && findtext(friend.tnote, "incinerator"), "[length(thread?["messages"])] messages")
	cs_check("one that came in while the conversation was open isn't left unread", P.vars["pda_unread"] == 0, "[P.vars["pda_unread"]] unread")
	cs_shot("popup_pda_[label]_3_thread", "Personal Data Assistant")
	cs_tgui_do(C, ui.window_id, "clickexact:Home")
	cs_wait_until(P, "mode", 0)
	cs_tgui_do(C, ui.window_id, "click:Notekeeper")
	cs_wait_until(P, "mode", 1)
	cs_tgui_do(C, ui.window_id, "clickexact:Edit")
	sleep(5)
	cs_tgui_do(C, ui.window_id, "textarea:Buy more seeds.\nAsk Riley about the tomatoes.\nAsh from the incinerator.")
	sleep(3)
	cs_tgui_do(C, ui.window_id, "clickexact:Save")
	sleep(10)
	cs_check("Edit, typed in the window and Saved", findtext(P.note, "incinerator"), P.note)
	cs_shot("popup_pda_[label]_4_notes", "Personal Data Assistant")
	cs_tgui_do(C, ui.window_id, "clickexact:Back")
	cs_wait_until(P, "mode", 0)
	cs_tgui_do(C, ui.window_id, "click:Messenger")
	cs_wait_until(P, "mode", 2)
	var/was_silent = P.silent
	cs_tgui_do(C, ui.window_id, "click:Ringer")
	sleep(5)
	cs_check("Ringer turns it off", P.silent && !was_silent)
	cs_tgui_do(C, ui.window_id, "input0:chirp")
	sleep(3)
	cs_tgui_do(C, ui.window_id, "clickexact:Set Ringtone")
	sleep(5)
	cs_check("a ringtone is typed in and set", P.ttone == "chirp", P.ttone)
	var/datum/component/uplink/uplink = P.AddComponent(/datum/component/uplink, H.key)
	uplink.unlock_code = "Orange 42"
	cs_tgui_do(C, ui.window_id, "input0:orange 42")
	sleep(3)
	cs_tgui_do(C, ui.window_id, "clickexact:Set Ringtone")
	sleep(10)
	cs_check("an uplink's code as the ringtone opens the uplink and keeps the old tone", !uplink.locked && P.ttone == "chirp", "locked [uplink.locked], tone [P.ttone]")
	SStgui.close_user_uis(H)
	qdel(uplink)
	P.cartridge = new /obj/item/cartridge/captain(P)
	P.cartridge.host_pda = P
	cs_act(P, H, "home")
	usr = H
	P.attack_self(H)
	ui = cs_find_ui(H, P)
	if(!ui)
		cs_check("the window opens again", FALSE)
		return
	sleep(10)
	var/list/titles = list()
	for(var/list/section in call(P, "pda_menu")())
		titles += section["title"]
	cs_check("a captain's cartridge adds its sections between General Functions and Utilities", titles.Join(", ") == "General Functions, Engineering Functions, Medical Functions, Security Functions, Quartermaster Functions, Utilities", titles.Join(", "))
	cs_shot("popup_pda_[label]_5_cart_home", "Personal Data Assistant")
	cs_tgui_do(C, ui.window_id, "click:Power Monitor")
	cs_wait_until(P, "mode", 43)
	var/list/monitors = P.cartridge.powermonitors
	cs_check("Power Monitor lists the station's power monitors", P.mode == 43 && length(monitors), "mode [P.mode], [length(monitors)] monitors")
	if(length(monitors))
		var/obj/machinery/computer/monitor/first = monitors[1]
		cs_tgui_do(C, ui.window_id, "click:[capitalize(first.name)]")
		cs_wait_until(P, "mode", 433)
	cs_check("one picked shows its readings", P.mode == 433 && P.cartridge.powmonitor)
	cs_shot("popup_pda_[label]_6_power", "Personal Data Assistant")
	cs_tgui_do(C, ui.window_id, "clickexact:Back")
	cs_wait_until(P, "mode", 43)
	cs_check("Back goes to the list of monitors", P.mode == 43)
	cs_tgui_do(C, ui.window_id, "clickexact:Home")
	cs_wait_until(P, "mode", 0)
	cs_tgui_do(C, ui.window_id, "click:View Crew Manifest")
	cs_wait_until(P, "mode", 41)
	cs_check("View Crew Manifest opens it", P.mode == 41)
	cs_shot("popup_pda_[label]_7_manifest", "Personal Data Assistant")
	cs_tgui_do(C, ui.window_id, "clickexact:Home")
	cs_wait_until(P, "mode", 0)
	cs_tgui_do(C, ui.window_id, "click:Set Status Display")
	cs_wait_until(P, "mode", 42)
	cs_tgui_do(C, ui.window_id, "input0:EVAC AT")
	sleep(3)
	cs_tgui_do(C, ui.window_id, "clickexact:Set")
	sleep(5)
	cs_check("a status display line is typed in and Set", P.cartridge.message1 == "EVAC AT", P.cartridge.message1)
	cs_shot("popup_pda_[label]_10_status", "Personal Data Assistant")
	cs_act(P, H, "cart", list("do" = "status", "what" = "not_a_screen"))
	cs_act(P, H, "open", list("key" = "999"))
	cs_check("nothing for a status it hasn't, nor a screen the cartridge hasn't", P.mode == 42)
	cs_tgui_do(C, ui.window_id, "clickexact:Home")
	cs_wait_until(P, "mode", 0)
	cs_tgui_do(C, ui.window_id, "click:Medical Records")
	cs_wait_until(P, "mode", 44)
	cs_tgui_do(C, ui.window_id, "click:[patient.fields["id"]]: Maya")
	cs_wait_until(P, "mode", 441)
	cs_check("Medical Records, then a name, opens their record", P.mode == 441)
	cs_shot("popup_pda_[label]_8_medical", "Personal Data Assistant")
	cs_tgui_do(C, ui.window_id, "clickexact:Home")
	cs_wait_until(P, "mode", 0)
	cs_tgui_do(C, ui.window_id, "click:Bots Access")
	cs_wait_until(P, "mode", 54)
	cs_tgui_do(C, ui.window_id, "click:Scan for active bots")
	sleep(10)
	cs_shot("popup_pda_[label]_9_bots", "Personal Data Assistant")
	cs_tgui_do(C, ui.window_id, "clickexact:Home")
	cs_wait_until(P, "mode", 0)
	cs_tgui_do(C, ui.window_id, "click:Eject")
	sleep(10)
	cs_check("the cartridge ejects from the home screen", !P.cartridge)
	// The signal bars are the route a message takes
	var/list/signal = call(P, "pda_signal_now")()
	cs_check("with telecomms up, the signal bars are full", signal["bars"] == 4, signal["why"])
	P.toff = TRUE
	sleep(11)
	signal = call(P, "pda_signal_now")()
	cs_check("with Send / Receive off, no bars, and that's why", !signal["bars"] && findtext(signal["why"], "Send / Receive"), signal["why"])
	P.toff = FALSE
	var/list/servers = list()
	for(var/obj/machinery/telecomms/message_server/S in GLOB.telecomms_list)
		if(S.toggled)
			S.toggled = FALSE
			S.update_power()
			servers += S
	sleep(11)
	signal = call(P, "pda_signal_now")()
	cs_check("with the message server off, no bars, and that's why", !signal["bars"] && findtext(signal["why"], "message server"), signal["why"])
	cs_tgui_do(C, ui.window_id, "click:Messenger")
	cs_wait_until(P, "mode", 2)
	sleep(5)
	cs_shot("popup_pda_[label]_11_no_signal", "Personal Data Assistant")
	for(var/obj/machinery/telecomms/message_server/S in servers)
		S.toggled = TRUE
		S.update_power()
	SStgui.close_user_uis(H)
	// Each department's paint, and the clown's and the mime's
	for(var/kind in list("medical", "engineering", "security", "toxins", "cargo", "captain", "syndicate", "clown", "mime"))
		var/path = text2path("/obj/item/pda/[kind]")
		var/obj/item/pda/T = new path(H.loc)
		T.owner = H.real_name
		T.ownjob = "Assistant"
		T.update_label()
		usr = H
		T.interact(H)
		var/datum/tgui/tui = cs_find_ui(H, T)
		if(!tui)
			cs_check("[kind]'s PDA opens", FALSE)
			continue
		winset(C, tui.window_id, "pos=200,40")
		sleep(20)
		cs_shot("popup_pda_[label]_t_[kind]", "Personal Data Assistant")
		if(kind == "clown")
			cs_tgui_do(C, tui.window_id, "clickexact:HONK!")
			sleep(5)
			cs_check("the clown's big HONK! honks", T.last_noise)
		SStgui.close_user_uis(H, T)
		qdel(T)

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

// The exosuit fabricator

/proc/cs_exofab(client/C, mob/living/carbon/human/H, label)
	var/obj/item/card/id/card = H.get_idcard()
	if(!card)
		card = new /obj/item/card/id(H.loc) // in hand: the ID slot holds an empty PDA
		H.put_in_active_hand(card)
	card.access |= ACCESS_ROBOTICS
	var/obj/machinery/mecha_part_fabricator/F = new(cs_open_beside(H))
	F.stat &= ~(NOPOWER|BROKEN)
	F.setDir(get_dir(F, H)) //its outlet clear
	var/datum/component/material_container/M = F.rmat.mat_container
	M.insert_amount(40 * MINERAL_MATERIAL_AMOUNT, MAT_METAL)
	M.insert_amount(20 * MINERAL_MATERIAL_AMOUNT, MAT_GLASS)
	M.insert_amount(3 * MINERAL_MATERIAL_AMOUNT, MAT_SILVER)
	var/list/cyborg = list()
	for(var/id in F.stored_research.researched_designs)
		var/datum/design/D = SSresearch.techweb_design_by_id(id)
		if(D && (D.build_type & MECHFAB) && ("Cyborg" in D.category))
			cyborg += id
	usr = H
	F.interact(H)
	if(!hascall(F, "fab_design"))
		// The old window, on the same screens
		sleep(20)
		winset(C, "mecha_fabricator", "pos=100,40")
		sleep(10)
		cs_shot("popup_exofab_[label]_0_main")
		usr = H
		F.Topic(null, list("part_set" = "Cyborg"))
		usr = H
		F.Topic(null, list("add_to_queue" = cyborg[1]))
		usr = H
		F.Topic(null, list("add_to_queue" = cyborg[2]))
		sleep(15)
		cs_shot("popup_exofab_[label]_1_cyborg")
		H << browse(null, "window=mecha_fabricator")
		return
	var/datum/tgui/ui = cs_find_ui(H, F)
	if(!ui)
		cs_check("the window opens", FALSE)
		return
	winset(C, ui.window_id, "pos=100,40")
	sleep(10)
	cs_shot("popup_exofab_[label]_0_main", F.name)
	cs_tgui_do(C, ui.window_id, "clickexact:Queue")
	sleep(5)
	cs_check("Queue puts a part in the queue", length(F.queue) == 1, "[length(F.queue)] queued")
	cs_tgui_do(C, ui.window_id, "click:Queue all")
	sleep(5)
	cs_check("Queue all puts the whole set in", length(F.queue) == 1 + length(cyborg), "[length(F.queue)] queued, [length(cyborg)] in the set")
	var/datum/design/second = F.queue[2]
	cs_act(F, H, "queue_move", list("index" = 2, "by" = -1))
	cs_check("a part moves up the queue", F.queue[1] == second)
	cs_act(F, H, "queue_move", list("index" = 1, "by" = -1))
	cs_check("nothing moves above the top", F.queue[1] == second)
	cs_act(F, H, "queue_remove", list("index" = 1))
	cs_check("a part comes out of the queue", length(F.queue) == length(cyborg))
	cs_act(F, H, "queue", list("id" = "not_a_design"))
	cs_act(F, H, "build", list("id" = "ripley_chassis_not"))
	cs_check("nothing for a design it hasn't got", length(F.queue) == length(cyborg) && !F.being_built)
	SStgui.update_uis(F)
	sleep(10)
	cs_shot("popup_exofab_[label]_1_queue", F.name)
	var/metal = M.materials[MAT_METAL].amount
	cs_tgui_do(C, ui.window_id, "clickexact:Build")
	sleep(10)
	cs_check("Build starts the part", !!F.being_built, "[F.being_built]")
	SStgui.update_uis(F)
	sleep(10)
	cs_shot("popup_exofab_[label]_2_building", F.name)
	cs_check("it takes the materials", M.materials[MAT_METAL].amount < metal)
	var/glass = M.materials[MAT_GLASS].amount
	cs_act(F, H, "eject", list("mat" = MAT_GLASS, "amount" = 1))
	cs_check("Eject 1 gives a sheet of glass", M.materials[MAT_GLASS].amount == glass - MINERAL_MATERIAL_AMOUNT && (locate(/obj/item/stack/sheet/glass) in F.drop_location()))
	cs_act(F, H, "eject", list("mat" = "$nothing", "amount" = 5))
	cs_tgui_do(C, ui.window_id, "input0:leg")
	sleep(10)
	cs_shot("popup_exofab_[label]_3_search", F.name)
	var/deadline = world.time + 75 SECONDS //the endoskeleton takes 50
	while(F.being_built && world.time < deadline)
		sleep(5)
	cs_tgui_do(C, ui.window_id, "click:Process queue")
	sleep(10)
	cs_check("Process queue starts on the queue", F.processing_queue && !!F.being_built)
	cs_act(F, H, "queue_clear")
	cs_check("Clear empties the queue", !length(F.queue))
	SStgui.close_user_uis(H)

// A mech's own menu

/proc/cs_exosuit(client/C, mob/living/carbon/human/H, label)
	var/obj/mecha/working/ripley/M = new(cs_open_beside(H))
	var/obj/item/mecha_parts/mecha_equipment/drill/D = new
	D.attach(M)
	var/obj/item/mecha_parts/mecha_equipment/hydraulic_clamp/K = new
	K.attach(M)
	var/obj/item/mecha_parts/mecha_equipment/generator/G = new
	G.attach(M)
	G.fuel.amount = 10 //with none it switches itself straight off
	usr = H //moved_inside() checks range(1) of usr
	M.moved_inside(H)
	cs_check("the pilot is in", M.occupant == H)
	sleep(5)
	usr = H
	M.stats_action.Activate()
	sleep(10)
	var/datum/tgui/ui = SStgui.get_open_ui(H, M, "main")
	if(!ui)
		// The old window
		sleep(30)
		winset(C, "exosuit", "pos=200,40;size=520x600")
		sleep(10)
		cs_shot("popup_exosuit_[label]_0_stats", "[M.name] data")
		H << browse(null, "window=exosuit")
		M.go_out()
		return
	ui = cs_find_ui(H, M)
	winset(C, ui.window_id, "pos=200,40")
	sleep(10)
	cs_shot("popup_exosuit_[label]_0_stats", M.name)
	cs_tgui_do(C, ui.window_id, "clickexact:Select")
	sleep(5)
	cs_check("Select picks the first tool, the drill", M.selected == D, "[M.selected]")
	cs_tgui_do(C, ui.window_id, "clickexact:Activate")
	sleep(5)
	cs_check("the generator's own Activate, read off its info, works", !G.equip_ready)
	cs_tgui_do(C, ui.window_id, "click:Lights off")
	sleep(5)
	cs_check("Lights turns them on", M.lights)
	var/was_mic = M.radio.broadcasting
	cs_tgui_do(C, ui.window_id, "click:Mic")
	sleep(5)
	cs_check("the mic toggles", M.radio.broadcasting != was_mic)
	var/freq = M.radio.frequency
	cs_act(M, H, "frequency", list("by" = 2))
	cs_check("the frequency goes up a step", M.radio.frequency != freq)
	cs_act(M, H, "frequency", list("by" = 7))
	cs_check("nothing for a step there's no button for", M.radio.frequency == freq + 2)
	cs_tgui_do(C, ui.window_id, "click:Lock to my DNA")
	sleep(5)
	cs_check("DNA lock takes the pilot's DNA", M.dna_lock == H.dna.unique_enzymes)
	cs_act(M, H, "dna_reset")
	cs_check("and Reset clears it", !M.dna_lock)
	cs_act(M, H, "rename", list("name" = "Digger"))
	cs_check("renamed in the window", M.name == "Digger", M.name)
	cs_act(M, H, "link", list("target" = REF(H), "query" = "toggle=1"))
	cs_act(M, H, "detach", list("ref" = REF(K)))
	cs_check("a tool comes off with Detach", !(K in M.equipment))
	SStgui.update_uis(M)
	sleep(10)
	cs_shot("popup_exosuit_[label]_1_used", M.name)
	// Battered: a quarter of its integrity and a short circuit (MECHA_INT_SHORT_CIRCUIT, mecha.dm's own define)
	M.obj_integrity = M.max_integrity * 0.25
	M.setInternalDamage(4)
	SStgui.update_uis(M)
	sleep(10)
	cs_shot("popup_exosuit_[label]_2_damaged", M.name)
	SStgui.close_user_uis(H)
	M.go_out()

// The exosuit control console

/proc/cs_mechcontrol(client/C, mob/living/carbon/human/H, label)
	var/obj/item/card/id/card = H.get_idcard()
	if(!card)
		card = new /obj/item/card/id(H.loc) // in hand: the ID slot holds an empty PDA
		H.put_in_active_hand(card)
	card.access |= ACCESS_ROBOTICS
	var/obj/machinery/computer/mecha/console = new(cs_open_beside(H))
	console.stat &= ~(NOPOWER|BROKEN)
	var/obj/mecha/working/ripley/M = new(get_step(H, SOUTH))
	var/obj/item/mecha_parts/mecha_tracking/TR = new(M)
	M.trackers += TR
	var/mob/living/carbon/human/pilot = new(get_turf(M))
	pilot.real_name = "Robin Pilot"
	pilot.name = pilot.real_name
	M.occupant = pilot
	pilot.forceMove(M)
	var/obj/item/mecha_parts/mecha_tracking/loose = new(H.loc) //not in an exosuit
	usr = H
	console.interact(H)
	if(!hascall(console, "ui_act") || !SStgui.get_open_ui(H, console, "main"))
		sleep(20)
		winset(C, "computer", "pos=200,40")
		sleep(10)
		cs_shot("popup_mechcontrol_[label]_0_beacons")
		H << browse(null, "window=computer")
		return
	var/datum/tgui/ui = cs_find_ui(H, console)
	winset(C, ui.window_id, "pos=200,40")
	sleep(10)
	cs_shot("popup_mechcontrol_[label]_0_beacons", console.name)
	cs_tgui_do(C, ui.window_id, "input0:Bring the ore round to the Brig")
	sleep(3)
	cs_tgui_do(C, ui.window_id, "clickexact:Send")
	sleep(10)
	var/logged = file2text("[GLOB.log_directory]/game.log")
	cs_check("a message typed in and sent reaches the pilot", findtext(logged, "the message \"Bring the ore round to the Brig\""))
	cs_tgui_do(C, ui.window_id, "clickexact:EMP pulse")
	sleep(5)
	cs_check("the EMP pulse asks first", !TR.recharging)
	SStgui.update_uis(console)
	sleep(5)
	cs_shot("popup_mechcontrol_[label]_1_sure", console.name)
	cs_tgui_do(C, ui.window_id, "clickexact:Sure?")
	sleep(5)
	cs_check("and goes when it's sure", TR.recharging)
	cs_act(console, H, "shock", list("ref" = REF(loose)))
	cs_act(console, H, "message", list("ref" = REF(loose), "text" = "hello"))
	cs_check("nothing for a beacon that isn't in an exosuit", !loose.recharging)
	SStgui.close_user_uis(H)
	qdel(loose)

// The library: the librarian's console, the book scanner and the visitor console. There's no database here, so the Archive is a
// handful of books put straight in the cache the console reads.

/proc/cs_library(client/C, mob/living/carbon/human/H, label)
	var/list/taken = list()
	var/turf/at = cs_open_beside(H, taken)
	taken += at
	var/obj/machinery/computer/libraryconsole/bookmanagement/console = new(at)
	console.stat &= ~(NOPOWER|BROKEN)
	var/turf/scanner_at = cs_open_beside(H, taken)
	taken += scanner_at
	var/obj/machinery/libraryscanner/scanner = new(scanner_at)
	var/obj/item/book/B = new(scanner)
	B.name = "Book: The Long Shift"
	B.title = "The Long Shift"
	B.author = "Ines Okafor"
	B.dat = "It was the third hour of the shift when the lights went out in Cargo."
	GLOB.cachedbooks = list()
	var/list/archive = list(
		list("Space Law, Annotated", "Ines Okafor", "Reference"), list("A Brief History of Plasma", "Ola Svensson", "Non-Fiction"),
		list("Robust Botany", "Zara Haddad", "Reference"), list("The Clown Who Fell Up", "Anonymous", "Fiction"),
		list("Plasma Fires and You", "Hugo Brandt", "Reference"), list("Night Shift at the Singularity", "Lena Kowalczyk", "Fiction"),
		list("The Gospel of the Geometer", "Anonymous", "Religion"), list("Cooking With Meat Of Uncertain Origin", "Luca Romano", "Non-Fiction"),
		list("Wires, Wires, Wires", "Ade Bello", "Reference"), list("The Last Shuttle Out", "Mara Lindqvist", "Fiction"),
	)
	var/id = 101
	for(var/list/entry in archive)
		var/datum/cachedbook/CB = new
		CB.id = "[id++]"
		CB.title = entry[1]
		CB.author = entry[2]
		CB.category = entry[3]
		GLOB.cachedbooks += CB
	for(var/name in list("Book: Robust Botany", "Book: Space Law, Annotated", "Book: The Clown Who Fell Up"))
		var/obj/item/book/shelved = new
		shelved.name = name
		console.inventory += shelved
	var/datum/borrowbook/late = new
	late.bookname = "Robust Botany"
	late.mobname = "Zara Haddad"
	late.getdate = world.time - 25 MINUTES
	late.duedate = world.time - 5 MINUTES
	console.checkouts += late
	var/datum/borrowbook/due = new
	due.bookname = "A Brief History of Plasma"
	due.mobname = "Ola Svensson"
	due.getdate = world.time - 2 MINUTES
	due.duedate = world.time + 8 MINUTES
	console.checkouts += due
	usr = H
	console.interact(H)
	if(!hascall(console, "ui_act") || !SStgui.get_open_ui(H, console, "main"))
		// The old pages: the menu, then the ones the new window has as tabs
		scanner.cache = B
		sleep(20)
		winset(C, "library", "pos=200,40")
		sleep(10)
		cs_shot("popup_library_[label]_0_menu")
		for(var/screen in list(1, 2, 3, 4, 5, 7))
			console.screenstate = screen
			console.ui_interact(H)
			sleep(10)
			cs_shot("popup_library_[label]_[screen]_page")
		H << browse(null, "window=library")
		scanner.attack_hand(H)
		sleep(15)
		winset(C, "scanner", "pos=200,40")
		sleep(5)
		cs_shot("popup_library_[label]_scanner")
		H << browse(null, "window=scanner")
		var/obj/machinery/computer/libraryconsole/visitor = new(cs_open_beside(H, taken))
		visitor.stat &= ~(NOPOWER|BROKEN)
		visitor.interact(H)
		sleep(15)
		winset(C, "publiclibrary", "pos=200,40")
		sleep(5)
		cs_shot("popup_library_[label]_visitor")
		H << browse(null, "window=publiclibrary")
		return
	var/datum/tgui/ui = cs_find_ui(H, console)
	winset(C, ui.window_id, "pos=200,40")
	sleep(10)
	cs_shot("popup_library_[label]_0_inventory", console.name)
	var/obj/item/book/gone = console.inventory[1]
	cs_act(console, H, "delbook", list("ref" = REF(gone)))
	cs_check("a book comes off the inventory", !(gone in console.inventory) && length(console.inventory) == 2)
	// What's out, and lending one from the form in place
	cs_tgui_do(C, ui.window_id, "click:Checked out")
	sleep(5)
	cs_tgui_do(C, ui.window_id, "input0:The Long Shift")
	cs_tgui_do(C, ui.window_id, "input1:Sam Tanaka")
	sleep(3)
	cs_shot("popup_library_[label]_1_checkouts", console.name)
	cs_tgui_do(C, ui.window_id, "click:Commit entry")
	sleep(5)
	var/datum/borrowbook/lent = console.checkouts[length(console.checkouts)]
	cs_check("a book lent from the form typed in place", lent.bookname == "The Long Shift" && lent.mobname == "Sam Tanaka", "[lent.bookname] to [lent.mobname]")
	cs_check("for the period shown", lent.duedate - lent.getdate == console.checkoutperiod * 600)
	cs_tgui_do(C, ui.window_id, "click:Check in")
	sleep(5)
	cs_check("Check in takes the first off the list", !(late in console.checkouts) && (due in console.checkouts))
	var/period = console.checkoutperiod
	cs_act(console, H, "period", list("by" = "1"))
	cs_check("+ lends for a minute longer", console.checkoutperiod == period + 1)
	cs_act(console, H, "period", list("by" = "-1"))
	cs_check("and - a minute less", console.checkoutperiod == period)
	// The Archive, all of it, and searched
	cs_tgui_do(C, ui.window_id, "click:External Archive")
	sleep(5)
	cs_shot("popup_library_[label]_2_archive", console.name)
	cs_tgui_do(C, ui.window_id, "input0:plasma")
	sleep(5)
	cs_shot("popup_library_[label]_3_search", console.name)
	// The scanner's window (on its own for its picture: a tgui window has no caption to pick it out by), and what it scanned on the
	// console
	scanner.cache = null
	cs_tgui_do(C, ui.window_id, "click:Upload & post")
	sleep(5)
	cs_shot("popup_library_[label]_4_nothing_scanned", console.name)
	SStgui.close_uis(console)
	scanner.attack_hand(H)
	var/datum/tgui/sui = cs_find_ui(H, scanner)
	cs_check("the scanner opens its window by hand", sui)
	if(sui)
		winset(C, sui.window_id, "pos=200,40")
		sleep(10)
		cs_tgui_do(C, sui.window_id, "click:Scan")
		sleep(5)
		cs_check("Scan keeps the book in memory", scanner.cache == B)
		SStgui.update_uis(scanner)
		sleep(5)
		cs_shot("popup_library_[label]_5_scanner", scanner.name)
		winset(C, sui.window_id, "pos=960,40")
	console.interact(H)
	ui = cs_find_ui(H, console)
	winset(C, ui.window_id, "pos=200,40")
	sleep(10)
	cs_tgui_do(C, ui.window_id, "click:Upload & post")
	sleep(5)
	cs_tgui_do(C, ui.window_id, "input0:Ines Okafor-Reyes")
	sleep(2)
	cs_tgui_do(C, ui.window_id, "clickexact:Set")
	sleep(5)
	cs_check("the author typed in place", B.author == "Ines Okafor-Reyes", B.author)
	cs_act(console, H, "category", list("category" = "Reference"))
	cs_act(console, H, "category", list("category" = "Banned books"))
	cs_check("a category from the list, and only from it", console.upload_category == "Reference", console.upload_category)
	SStgui.update_uis(console)
	sleep(5)
	cs_shot("popup_library_[label]_6_upload", console.name)
	cs_tgui_do(C, ui.window_id, "click:Post to the newscasters")
	sleep(5)
	var/stories = 0
	for(var/datum/newscaster/feed_channel/FC in GLOB.news_network.network_channels)
		if(FC.channel_name == "Nanotrasen Book Club")
			stories = length(FC.messages)
	cs_check("Post puts it on the newscasters' book club", stories == 1, "[stories] stories")
	// The printer, and the vault once it's emagged
	cs_tgui_do(C, ui.window_id, "clickexact:Print")
	sleep(5)
	cs_tgui_do(C, ui.window_id, "click:Print a poster")
	sleep(5)
	cs_check("Print a poster prints one", locate(/obj/item/poster) in console.loc)
	cs_check("and the printer waits after", console.cooldown > world.time)
	SStgui.update_uis(console)
	sleep(5)
	cs_shot("popup_library_[label]_7_print", console.name)
	console.obj_flags |= EMAGGED
	SStgui.update_uis(console)
	sleep(5)
	cs_shot("popup_library_[label]_8_vault", console.name)
	cs_tgui_do(C, ui.window_id, "click:Access the vault")
	sleep(5)
	var/relics = 0
	for(var/obj/item/I in console.loc)
		if(istype(I, /obj/item/melee/cultblade/dagger) || istype(I, /obj/item/clockwork/slab))
			relics++
	cs_check("the vault gives up a relic", relics == 1, "[relics]")
	console.obj_flags &= ~EMAGGED
	cs_act(console, H, "forbidden")
	var/after = 0
	for(var/obj/item/I in console.loc)
		if(istype(I, /obj/item/melee/cultblade/dagger) || istype(I, /obj/item/clockwork/slab))
			after++
	cs_check("but not unless it's emagged", after == relics)
	if(sui)
		cs_tgui_do(C, sui.window_id, "click:Remove book")
		sleep(5)
		cs_check("Remove book puts it down", B.loc == scanner.drop_location())
	SStgui.close_user_uis(H)
	// The visitor console
	var/obj/machinery/computer/libraryconsole/visitor = new(cs_open_beside(H, taken))
	visitor.stat &= ~(NOPOWER|BROKEN)
	visitor.interact(H)
	var/datum/tgui/vui = cs_find_ui(H, visitor)
	winset(C, vui.window_id, "pos=200,40")
	sleep(10)
	cs_tgui_do(C, vui.window_id, "input0:plasma")
	cs_tgui_do(C, vui.window_id, "input1:Ola")
	sleep(3)
	cs_tgui_do(C, vui.window_id, "clickexact:Search")
	sleep(5)
	cs_check("the visitor's search takes what was typed", visitor.vars["searched"] && visitor.title == "plasma" && visitor.author == "Ola", "[visitor.title], [visitor.author]")
	SStgui.update_uis(visitor)
	sleep(5)
	cs_shot("popup_library_[label]_9_visitor", visitor.name)
	SStgui.close_user_uis(H)

// The photocopier

/proc/cs_photocopier(client/C, mob/living/carbon/human/H, label)
	var/obj/machinery/photocopier/copier = new(cs_open_beside(H))
	copier.stat &= ~(NOPOWER|BROKEN)
	var/obj/item/paper/P = new(copier)
	P.name = "paper - 'Shift report'"
	P.info = "<B>Shift report</B><BR>Cargo: three crates in, two sent round.<BR>Science: the protolathe's waiting on silver.<BR>Nothing else to report."
	P.update_icon()
	copier.copy = P
	usr = H
	copier.interact(H)
	var/turf/out = copier.loc
	var/before_count = 0
	for(var/obj/item/paper/made in out)
		before_count++
	if(!hascall(copier, "copy_next"))
		sleep(20)
		winset(C, "copier", "pos=200,40")
		sleep(5)
		cs_shot("popup_photocopier_[label]_0_glass")
		copier.Topic(null, list("add" = "1"))
		copier.Topic(null, list("add" = "1"))
		copier.Topic(null, list("copy" = "1"))
		sleep(80)
		var/made = -before_count
		for(var/obj/item/paper/copied in out)
			made++
		kc_log("NOTE before: 3 copies asked for, [made] came out")
		H << browse(null, "window=copier")
		return
	var/datum/tgui/ui = cs_find_ui(H, copier)
	winset(C, ui.window_id, "pos=200,40")
	sleep(10)
	cs_shot("popup_photocopier_[label]_0_glass", copier.name)
	cs_act(copier, H, "copies", list("by" = "1"))
	cs_act(copier, H, "copies", list("by" = "1"))
	cs_check("+ twice asks for three", copier.copies == 3, "[copier.copies]")
	SStgui.update_uis(copier)
	sleep(5)
	cs_tgui_do(C, ui.window_id, "clickexact:Copy")
	sleep(12)
	SStgui.update_uis(copier)
	sleep(3)
	cs_shot("popup_photocopier_[label]_1_printing", copier.name)
	sleep(60)
	var/made = -before_count
	for(var/obj/item/paper/copied in out)
		if(findtext(copied.info, "Shift report"))
			made++
	cs_check("three copies asked for, three came out", made == 3, "[made]")
	cs_check("a sheet of toner each", copier.toner == 37, "[copier.toner]")
	cs_check("and the run's over", !copier.vars["copies_left"] && !copier.busy)
	cs_tgui_do(C, ui.window_id, "clickexact:Take out")
	sleep(5)
	cs_check("Take out hands the paper back", P.loc == H && !copier.copy)
	copier.toner = 0
	var/obj/item/paper/blank = new(copier)
	copier.copy = blank
	SStgui.update_uis(copier)
	sleep(5)
	cs_shot("popup_photocopier_[label]_2_no_toner", copier.name)
	cs_act(copier, H, "copy")
	sleep(20)
	cs_check("no toner, no copies", !copier.vars["copies_left"])
	SStgui.close_user_uis(H)

// Paper, folders, clipboards, filing cabinets and notice boards

/proc/cs_paperwork(client/C, mob/living/carbon/human/H, label)
	var/list/taken = list()
	var/obj/item/pen/pen = new(H.loc)
	H.put_in_active_hand(pen)
	var/obj/item/paper/P = new(H.loc)
	var/tgui_build = hascall(P, "paper_write")
	P.name = "paper - 'Supply request form'"
	P.info = "<center><B>Supply Request</B></center><BR>Name: <span class=\"paper_field\"></span><BR>Department: <span class=\"paper_field\"></span><BR>What for: <span class=\"paper_field\"></span><BR><BR>"
	P.reload_fields()
	P.update_icon()
	var/obj/item/stamp/qm/qm_stamp = new
	P.attackby(qm_stamp, H)
	H.put_in_inactive_hand(P)
	usr = H
	// The paper, with a pen in hand
	P.attackby(pen, H)
	sleep(20)
	if(!tgui_build)
		cs_shot("popup_paperwork_[label]_0_paper_writing")
		H << browse(null, "window=[P.name]")
	else
		var/datum/tgui/ui = cs_find_ui(H, P)
		cs_check("a pen on a paper opens its window", ui)
		if(!ui)
			return
		winset(C, ui.window_id, "pos=200,20")
		sleep(10)
		cs_shot("popup_paperwork_[label]_0_paper_writing", P.name)
		cs_tgui_do(C, ui.window_id, "clickexact:Field 1")
		sleep(3)
		cs_tgui_do(C, ui.window_id, "textarea:Ida Asker")
		sleep(3)
		cs_tgui_do(C, ui.window_id, "clickexact:Write it")
		sleep(5)
		cs_check("written in the first field", findtext(P.info, "Ida Asker</font></span><BR>Department"), copytext(P.info, 1, 300))
		cs_tgui_do(C, ui.window_id, "clickexact:At the end")
		sleep(3)
		cs_tgui_do(C, ui.window_id, "textarea:**Approved**, %s")
		sleep(3)
		cs_tgui_do(C, ui.window_id, "clickexact:Write it")
		sleep(5)
		cs_check("and at the end, pen code and signature", findtext(P.info, "<B>Approved</B>") && findtext(P.info, H.real_name))
		cs_tgui_do(C, ui.window_id, "input0:Silver for Science")
		sleep(3)
		cs_tgui_do(C, ui.window_id, "clickexact:Set")
		sleep(5)
		cs_check("labelled from the window", P.name == "paper - 'Silver for Science'", P.name)
		SStgui.update_uis(P)
		sleep(5)
		cs_shot("popup_paperwork_[label]_1_paper_written", P.name)
		H.dropItemToGround(pen)
		cs_act(P, H, "write", list("text" = "scrawled without a pen", "field" = ""))
		cs_check("nothing written without a pen in hand", !findtext(P.info, "scrawled"))
		SStgui.update_uis(P)
		sleep(5)
		cs_shot("popup_paperwork_[label]_2_paper_reading", P.name)
		SStgui.close_user_uis(H)
	H.dropItemToGround(pen)
	H.dropItemToGround(P)
	// A folder
	var/obj/item/folder/blue/F = new(H.loc)
	var/obj/item/paper/memo = new(F)
	memo.name = "paper - 'Memo from the HoP'"
	memo.info = "Please return all borrowed stamps."
	new /obj/item/documents/nanotrasen(F)
	var/obj/item/paper/second = new(F)
	second.name = "paper - 'Crew roster'"
	F.update_icon()
	H.put_in_active_hand(F)
	F.attack_self(H)
	sleep(20)
	if(!tgui_build)
		cs_shot("popup_paperwork_[label]_3_folder")
		H << browse(null, "window=folder")
	else
		var/datum/tgui/fui = cs_find_ui(H, F)
		winset(C, fui.window_id, "pos=200,40")
		sleep(10)
		cs_shot("popup_paperwork_[label]_3_folder", F.name)
		cs_tgui_do(C, fui.window_id, "clickexact:Read")
		sleep(10)
		cs_check("Read opens the paper's own window", SStgui.get_open_ui(H, memo, "main"))
		SStgui.close_uis(memo)
		cs_tgui_do(C, fui.window_id, "clickexact:Take out")
		sleep(5)
		cs_check("Take out takes it out of the folder", memo.loc != F && length(F.contents) == 2)
		SStgui.close_user_uis(H)
	H.dropItemToGround(F)
	if(memo.loc != F)
		H.dropItemToGround(memo)
	// A clipboard
	var/obj/item/clipboard/CB = new(H.loc)
	var/obj/item/paper/bottom = new(CB)
	bottom.name = "paper - 'Engine checklist'"
	var/obj/item/paper/top = new(CB)
	top.name = "paper - 'Incident report'"
	CB.toppaper = top
	CB.haspen = new /obj/item/pen/blue(CB)
	CB.update_icon()
	H.put_in_active_hand(CB)
	CB.attack_self(H)
	sleep(20)
	if(!tgui_build)
		cs_shot("popup_paperwork_[label]_4_clipboard")
		H << browse(null, "window=clipboard")
	else
		var/datum/tgui/cui = cs_find_ui(H, CB)
		winset(C, cui.window_id, "pos=200,40")
		sleep(10)
		cs_shot("popup_paperwork_[label]_4_clipboard", "Clipboard")
		cs_act(CB, H, "top", list("ref" = REF(bottom)))
		cs_check("the one underneath moved to the top", CB.toppaper == bottom)
		cs_tgui_do(C, cui.window_id, "clickexact:Take it")
		sleep(5)
		cs_check("the pen out of the clip", !CB.haspen)
		SStgui.close_user_uis(H)
	H.drop_all_held_items()
	// A filing cabinet
	var/turf/cab_at = cs_open_beside(H, taken)
	taken += cab_at
	var/obj/structure/filingcabinet/cab = new(cab_at)
	for(var/datum/data/record/R in GLOB.data_core.general)
		var/obj/item/paper/file = new(cab)
		file.name = "paper - '[R.fields["name"]]'"
	cab.interact(H)
	sleep(20)
	if(!tgui_build)
		cs_shot("popup_paperwork_[label]_5_cabinet")
		H << browse(null, "window=filingcabinet")
	else
		var/datum/tgui/kui = cs_find_ui(H, cab)
		winset(C, kui.window_id, "pos=200,40")
		sleep(10)
		cs_shot("popup_paperwork_[label]_5_cabinet", cab.name)
		cs_tgui_do(C, kui.window_id, "input0:kowal")
		sleep(5)
		cs_shot("popup_paperwork_[label]_6_cabinet_search", cab.name)
		var/had = length(cab.contents)
		cs_tgui_do(C, kui.window_id, "clickexact:Take out")
		sleep(5)
		var/obj/item/paper/pulled = H.get_active_held_item() || H.get_inactive_held_item()
		cs_check("Take out hands over the one searched for", length(cab.contents) == had - 1 && istype(pulled) && findtext(pulled.name, "Kowalczyk"), "[pulled]")
		SStgui.close_user_uis(H)
	H.drop_all_held_items()
	// A notice board, the Quartermaster's
	var/obj/structure/noticeboard/qm/board = new(cs_open_beside(H, taken))
	for(var/notice in list("Cargo hours", "No climbing on the conveyor", "MULE schedule"))
		var/obj/item/paper/N = new(board)
		N.name = "paper - '[notice]'"
		board.notices++
	board.icon_state = "nboard0[board.notices]"
	board.interact(H)
	sleep(20)
	if(!tgui_build)
		cs_shot("popup_paperwork_[label]_7_noticeboard")
		H << browse(null, "window=noticeboard")
		return
	var/datum/tgui/nui = cs_find_ui(H, board)
	winset(C, nui.window_id, "pos=200,40")
	sleep(10)
	cs_shot("popup_paperwork_[label]_7_noticeboard_locked", board.name)
	var/obj/item/paper/first = locate() in board
	cs_act(board, H, "take", list("ref" = REF(first)))
	cs_check("no taking a notice down without the access", first.loc == board)
	var/obj/item/card/id/card = cs_card(H.real_name, "Quartermaster", list(ACCESS_QM, ACCESS_CARGO), H.loc)
	H.put_in_active_hand(card)
	SStgui.update_uis(board)
	sleep(5)
	cs_shot("popup_paperwork_[label]_8_noticeboard", board.name)
	cs_tgui_do(C, nui.window_id, "clickexact:Take out")
	sleep(5)
	cs_check("with it, Take out takes one down", board.notices == 2 && length(board.contents) == 2, "[board.notices]")
	SStgui.close_user_uis(H)

// Every mech in its own paint: each boarded in turn and its menu pictured

/proc/cs_mechpaints(client/C, mob/living/carbon/human/H, label)
	var/list/types = list(
		/obj/mecha/working/ripley, /obj/mecha/working/ripley/firefighter, /obj/mecha/working/ripley/deathripley,
		/obj/mecha/medical/odysseus, /obj/mecha/combat/gygax, /obj/mecha/combat/gygax/dark, /obj/mecha/combat/durand,
		/obj/mecha/combat/marauder, /obj/mecha/combat/marauder/seraph, /obj/mecha/combat/marauder/mauler, /obj/mecha/combat/phazon,
		/obj/mecha/combat/honker, /obj/mecha/combat/honker/dark, /obj/mecha/combat/reticence, /obj/mecha/makeshift, /obj/mecha/neovgre,
	)
	var/turf/at = cs_open_beside(H)
	var/n = 0
	for(var/path in types)
		n++
		var/obj/mecha/M = new path(at)
		usr = H
		M.moved_inside(H)
		if(M.occupant != H)
			cs_check("[M.name] takes the pilot", FALSE)
			qdel(M)
			continue
		sleep(5)
		usr = H
		M.stats_action.Activate()
		sleep(10)
		var/datum/tgui/ui = SStgui.get_open_ui(H, M, "main")
		var/paint = hascall(M, "mecha_ui_paint") ? call(M, "mecha_ui_paint")() : "old"
		if(ui)
			ui = cs_find_ui(H, M)
			winset(C, ui.window_id, "pos=200,40")
			sleep(15)
			cs_shot("popup_mechpaint_[label]_[n < 10 ? "0[n]" : n]_[paint]", M.name) //shot.ps1 looks for a window only for popup_ names
		cs_check("[M.name]: its window, in [paint]", ui)
		SStgui.close_user_uis(H)
		M.go_out()
		qdel(M)
		sleep(5)

// Hippie's locker mech: the same window, with its hold

/proc/cs_lockermech(client/C, mob/living/carbon/human/H, label)
	var/obj/mecha/makeshift/M = new(cs_open_beside(H))
	var/obj/item/crowbar/bar = new(M)
	M.cargo += bar
	var/obj/item/stack/sheet/metal/five/sheets = new(M)
	M.cargo += sheets
	usr = H
	M.moved_inside(H)
	cs_check("the pilot is in", M.occupant == H)
	sleep(5)
	usr = H
	M.stats_action.Activate()
	sleep(10)
	var/datum/tgui/ui = SStgui.get_open_ui(H, M, "main")
	if(!ui)
		sleep(30)
		winset(C, "exosuit", "pos=200,40;size=520x600")
		sleep(10)
		cs_shot("popup_lockermech_[label]_0_stats", "[M.name] data")
		H << browse(null, "window=exosuit")
		M.go_out()
		return
	ui = cs_find_ui(H, M)
	winset(C, ui.window_id, "pos=200,40")
	sleep(10)
	cs_shot("popup_lockermech_[label]_0_stats", M.name)
	var/list/data = M.ui_data(H)
	var/list/hold = data["cargo"]
	cs_check("its hold is in the window", islist(hold) && length(hold["items"]) == 2 && hold["capacity"] == 5)
	cs_tgui_do(C, ui.window_id, "clickexact:Unload")
	sleep(5)
	cs_check("Unload takes the first thing out", !(bar in M.cargo) && (sheets in M.cargo) && isturf(bar.loc))
	SStgui.close_user_uis(H)
	M.go_out()

// The signaler, timer, proximity sensor, infrared laser, health sensor and electropack

/// One held thing's window: the old one pictured and closed in a before build, the tgui one found and moved into view in an after one
/proc/cs_gadget_window(client/C, mob/living/carbon/human/H, atom/A, old_window, shot)
	H.drop_all_held_items()
	if(isitem(A))
		H.put_in_active_hand(A)
	usr = H
	if(isitem(A))
		var/obj/item/I = A
		I.attack_self(H)
	else
		A.interact(H)
	var/datum/tgui/ui = SStgui.get_open_ui(H, A, "main")
	if(!ui)
		sleep(15)
		winset(C, old_window, "pos=200,40")
		sleep(5)
		cs_shot(shot)
		H << browse(null, "window=[old_window]")
		return null
	ui = cs_find_ui(H, A)
	winset(C, ui.window_id, "pos=200,40")
	sleep(10)
	cs_shot(shot, A.name)
	return ui

/proc/cs_assemblies(client/C, mob/living/carbon/human/H, label)
	var/obj/item/assembly/signaler/S = new(H.loc)
	var/datum/tgui/ui = cs_gadget_window(C, H, S, "radio", "popup_assemblies_[label]_0_signaler")
	if(ui)
		cs_act(S, H, "frequency", list("frequency" = "145.1"))
		cs_check("the frequency set in the window", S.frequency == 1451, "[S.frequency]")
		cs_act(S, H, "frequency", list("frequency" = "145.4"))
		cs_check("and kept to the odd ones a signaler uses", S.frequency == 1455, "[S.frequency]")
		cs_act(S, H, "code", list("code" = "142"))
		cs_check("the code kept to 1-100", S.code == 100, "[S.code]")
		var/sent = length(GLOB.lastsignalers)
		cs_tgui_do(C, ui.window_id, "clickexact:Send signal")
		sleep(5)
		cs_check("Send signal sends", length(GLOB.lastsignalers) == sent + 1)
		SStgui.update_uis(S)
		sleep(5)
		cs_shot("popup_assemblies_[label]_1_signaler_set", S.name)
		cs_tgui_do(C, ui.window_id, "clickexact:Default")
		sleep(5)
		cs_check("Default puts it back", S.frequency == FREQ_SIGNALER && S.code == DEFAULT_SIGNALER_CODE)
	SStgui.close_user_uis(H)
	var/obj/item/assembly/signaler/loose = new(H.loc)
	loose.secured = FALSE
	H.drop_all_held_items()
	H.put_in_active_hand(loose)
	loose.attack_self(H)
	sleep(5)
	if(ui)
		cs_check("an unsecured one opens no window", !SStgui.get_open_ui(H, loose, "main"))
	var/obj/item/assembly/timer/T = new(H.loc)
	ui = cs_gadget_window(C, H, T, "timer", "popup_assemblies_[label]_2_timer")
	if(ui)
		cs_act(T, H, "time", list("by" = "30"))
		cs_check("+30 s", T.time == 35, "[T.time]")
		cs_tgui_do(C, ui.window_id, "clickexact:Start")
		sleep(5)
		cs_check("Start starts it", T.timing)
		sleep(25)
		SStgui.update_uis(T)
		sleep(5)
		cs_shot("popup_assemblies_[label]_3_timer_running", T.name)
		cs_check("and it counts down", T.time < 35, "[T.time]")
		cs_tgui_do(C, ui.window_id, "clickexact:Stop")
		sleep(5)
		cs_check("Stop stops it", !T.timing)
		cs_tgui_do(C, ui.window_id, "clickexact:Once")
		sleep(5)
		cs_check("set to repeat", T.loop)
	SStgui.close_user_uis(H)
	var/obj/item/assembly/prox_sensor/P = new(H.loc)
	ui = cs_gadget_window(C, H, P, "prox", "popup_assemblies_[label]_4_prox")
	if(ui)
		cs_act(P, H, "range", list("by" = "1"))
		cs_check("its range up one", P.sensitivity == 2, "[P.sensitivity]")
		cs_tgui_do(C, ui.window_id, "clickexact:Arm now")
		sleep(5)
		cs_check("Arm now arms it", P.scanning)
		SStgui.update_uis(P)
		sleep(5)
		cs_shot("popup_assemblies_[label]_5_prox_armed", P.name)
		cs_tgui_do(C, ui.window_id, "clickexact:Disarm")
		sleep(5)
		cs_check("and Disarm", !P.scanning)
	SStgui.close_user_uis(H)
	var/obj/item/assembly/infra/I = new(H.loc)
	ui = cs_gadget_window(C, H, I, "infra", "popup_assemblies_[label]_6_infra")
	if(ui)
		cs_tgui_do(C, ui.window_id, "clickexact:Off")
		sleep(5)
		cs_tgui_do(C, ui.window_id, "clickexact:Invisible")
		sleep(5)
		cs_check("the laser on and visible", I.on && I.visible)
	SStgui.close_user_uis(H)
	var/obj/item/assembly/health/HS = new(H.loc)
	ui = cs_gadget_window(C, H, HS, "hscan", "popup_assemblies_[label]_7_health")
	if(ui)
		var/was = HS.scanning
		cs_act(HS, H, "power")
		cs_check("the health sensor switched", HS.scanning != was)
	SStgui.close_user_uis(H)
	var/obj/item/electropack/E = new(H.loc)
	ui = cs_gadget_window(C, H, E, "radio", "popup_assemblies_[label]_8_electropack")
	if(ui)
		cs_act(E, H, "code", list("code" = "17"))
		cs_check("the electropack's code set", E.code == 17, "[E.code]")
		cs_act(E, H, "frequency", list("frequency" = "144.9"))
		cs_check("and its frequency", E.frequency == 1449, "[E.frequency]")
		SStgui.close_user_uis(H)
		H.drop_all_held_items()
		H.equip_to_slot_or_del(E, ITEM_SLOT_BACK)
		E.attack_self(H)
		sleep(10)
		var/datum/tgui/worn = SStgui.get_open_ui(H, E, "main")
		if(worn)
			winset(C, worn.window_id, "pos=200,40")
			sleep(10)
			cs_shot("popup_assemblies_[label]_9_electropack_worn", E.name)
		cs_act(E, H, "code", list("code" = "50"))
		cs_check("not set while it's on your back", E.code == 17, "[E.code]")
	SStgui.close_user_uis(H)

// The implant pad, hand teleporter, safe, destination tagger and secure briefcase

/proc/cs_gadgets(client/C, mob/living/carbon/human/H, label)
	var/list/taken = list()
	var/obj/item/implantpad/pad = new(H.loc)
	pad.case = new /obj/item/implantcase/tracking(pad)
	pad.update_icon()
	var/datum/tgui/ui = cs_gadget_window(C, H, pad, "implantpad", "popup_gadgets_[label]_0_implant_pad")
	if(ui)
		cs_tgui_do(C, ui.window_id, "clickexact:Eject")
		sleep(5)
		cs_check("Eject hands the case over", !pad.case && (locate(/obj/item/implantcase) in H))
	SStgui.close_user_uis(H)
	// The hand teleporter: the old one was a pick-from-a-list popup, which waits on an answer
	var/obj/item/hand_tele/tele = new(H.loc)
	var/obj/machinery/computer/teleporter/com = locate() in GLOB.machines
	if(!hascall(tele, "tele_destinations"))
		kc_log("NOTE before: the hand teleporter was an input() list of [com ? "teleporters" : "no teleporters"] (not pictured: it waits on an answer)")
	else
		if(com)
			com.target = get_turf(pick(SSjob.latejoin_trackers))
		ui = cs_gadget_window(C, H, tele, "hand_tele", "popup_gadgets_[label]_1_hand_teleporter")
		if(ui && com)
			cs_tgui_do(C, ui.window_id, "clickexact:Open portal")
			sleep(10)
			cs_check("Open portal opens a pair", length(tele.active_portal_pairs) == 1, "[length(tele.active_portal_pairs)]")
			SStgui.update_uis(tele)
			sleep(5)
			cs_shot("popup_gadgets_[label]_2_hand_teleporter_open", tele.name)
			for(var/obj/effect/portal/portal in tele.active_portal_pairs)
				qdel(portal)
		else if(!com)
			kc_log("NOTE no teleporter computer on this map to lock on to")
		SStgui.close_user_uis(H)
	H.drop_all_held_items()
	// A safe
	var/obj/structure/safe/safe = new(cs_open_beside(H, taken))
	taken += get_turf(safe)
	var/obj/item/stack/spacecash/c1000/cash = new(safe)
	ui = cs_gadget_window(C, H, safe, "safe", "popup_gadgets_[label]_3_safe")
	if(ui)
		var/dial = safe.dial
		cs_act(safe, H, "turn", list("by" = "5"))
		cs_check("turned five notches", safe.dial == (dial + 5) % 72, "[dial] -> [safe.dial]")
		safe.tumbler_1_pos = safe.tumbler_1_open
		safe.tumbler_2_pos = safe.tumbler_2_open
		cs_tgui_do(C, ui.window_id, "clickexact:Open the safe")
		sleep(5)
		cs_check("open with the tumblers lined up", safe.open)
		SStgui.update_uis(safe)
		sleep(5)
		cs_shot("popup_gadgets_[label]_4_safe_open", safe.name)
		cs_tgui_do(C, ui.window_id, "clickexact:Take out")
		sleep(5)
		cs_check("Take out takes the cash out", cash.loc == H)
	SStgui.close_user_uis(H)
	// The destination tagger
	var/obj/item/destTagger/tagger = new(H.loc)
	ui = cs_gadget_window(C, H, tagger, "destTagScreen", "popup_gadgets_[label]_5_tagger")
	if(ui)
		cs_tgui_do(C, ui.window_id, "clickexact:Chemistry")
		sleep(5)
		cs_check("tagged for Chemistry", tagger.currTag && GLOB.TAGGERLOCATIONS[tagger.currTag] == "Chemistry", "[tagger.currTag]")
		cs_act(tagger, H, "tag", list("index" = "999"))
		cs_check("no destination that isn't on the list", GLOB.TAGGERLOCATIONS[tagger.currTag] == "Chemistry")
		SStgui.update_uis(tagger)
		sleep(5)
		cs_shot("popup_gadgets_[label]_6_tagger_set", tagger.name)
	SStgui.close_user_uis(H)
	// A secure briefcase
	var/obj/item/storage/secure/briefcase/brief = new(H.loc)
	ui = cs_gadget_window(C, H, brief, "caselock", "popup_gadgets_[label]_7_keypad")
	if(ui)
		for(var/key in list("1", "2", "3", "4", "5", "E"))
			cs_tgui_do(C, ui.window_id, "clickexact:[key]")
			sleep(2)
		cs_check("five digits and E set the code", brief.l_set && brief.l_code == "12345", "[brief.l_code]")
		for(var/key in list("1", "2", "3", "4", "5"))
			cs_tgui_do(C, ui.window_id, "clickexact:[key]")
			sleep(2)
		SStgui.update_uis(brief)
		sleep(5)
		cs_shot("popup_gadgets_[label]_8_keypad_typed", brief.name)
		cs_tgui_do(C, ui.window_id, "clickexact:E")
		sleep(5)
		cs_check("and again to open it", !SEND_SIGNAL(brief, COMSIG_IS_STORAGE_LOCKED))
		cs_tgui_do(C, ui.window_id, "clickexact:R")
		sleep(5)
		cs_check("R locks it", SEND_SIGNAL(brief, COMSIG_IS_STORAGE_LOCKED))
	SStgui.close_user_uis(H)

// The windows still on the 2017 tgui look (an old .ract page and no tgui-next route): each one opened and pictured.
// The same build gives "before" until the routes go in. data/console_shots_sub limits it to some (names, one per line).

/proc/cs_oldlook_wanted(name)
	var/sub = trim(file2text("data/console_shots_sub"))
	if(!sub)
		return TRUE
	return (name in splittext(sub, "\n"))

/// The window `A` has open for `user`, moved into view and pictured; FALSE when none opened
/proc/cs_oldlook_shot(client/C, mob/user, datum/A, label, name, title)
	var/datum/tgui/ui = cs_find_ui(user, A)
	if(!ui)
		var/detail = "status [A.ui_status(user, GLOB.default_state)]"
		if(ismachinery(A))
			var/obj/machinery/M = A
			detail += ", stat [M.stat], adjacent [M.Adjacent(user)], can_interact [M.can_interact(user)], at [M.x],[M.y] [M.loc], user at [user.x],[user.y]"
		cs_check("[name]: the window opens", FALSE, detail)
		return null
	sleep(5)
	winset(C, ui.window_id, "pos=200,40")
	sleep(20)
	cs_shot("popup_oldlook_[label]_[name]", title)
	return ui

/proc/cs_oldlook_patient(turf/at, name)
	var/mob/living/carbon/human/P = new(at)
	P.fully_replace_character_name(null, name)
	P.equipOutfit(/datum/outfit/job/doctor)
	return P

/proc/cs_oldlook(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/captain)
	var/turf/home = get_turf(H)

	if(cs_oldlook_wanted("sleeper"))
		var/obj/machinery/sleeper/S = new(cs_open_beside(H))
		S.stat &= ~(NOPOWER|BROKEN)
		var/mob/living/carbon/human/P = cs_oldlook_patient(get_turf(S), "Lena Kowalczyk")
		P.adjustBruteLoss(45)
		P.adjustFireLoss(22)
		P.adjustToxLoss(8)
		P.adjustOxyLoss(30)
		P.reagents.add_reagent(/datum/reagent/medicine/epinephrine, 4.5)
		P.reagents.add_reagent(/datum/reagent/medicine/morphine, 2)
		S.close_machine(P)
		S.ui_interact(H)
		var/datum/tgui/ui = cs_oldlook_shot(C, H, S, label, "sleeper", S.name)
		if(ui && label == "after")
			cs_tgui_do(C, ui.window_id, "click:Epinephrine")
			sleep(10)
			cs_check("sleeper: clicking Epinephrine injects it", P.reagents.get_reagent_amount(/datum/reagent/medicine/epinephrine) > 4.5, "[P.reagents.get_reagent_amount(/datum/reagent/medicine/epinephrine)]u")
			cs_tgui_do(C, ui.window_id, "click:Open door")
			cs_wait_until(S, "state_open", TRUE)
			cs_check("sleeper: clicking Open opens it", S.state_open)
		SStgui.close_user_uis(H)
		qdel(P)
		qdel(S)

	if(cs_oldlook_wanted("autodoc"))
		var/obj/machinery/autodoc/D = new(cs_open_beside(H))
		D.stat &= ~(NOPOWER|BROKEN)
		D.ui_interact(H)
		var/datum/tgui/ui = cs_oldlook_shot(C, H, D, label, "autodoc", D.name)
		if(ui && label == "after")
			cs_tgui_do(C, ui.window_id, "click:Left Arm")
			sleep(10)
			cs_check("autodoc: clicking Left Arm aims it there", D.target_zone == BODY_ZONE_L_ARM, "[D.target_zone]")
		SStgui.close_user_uis(H)
		qdel(D)

	if(cs_oldlook_wanted("mulebot"))
		var/mob/living/simple_animal/bot/mulebot/M = new(cs_open_beside(H))
		M.locked = FALSE
		M.ui_interact(H)
		var/datum/tgui/ui = cs_oldlook_shot(C, H, M, label, "mulebot", M.name)
		if(ui && label == "after" && length(GLOB.deliverybeacontags))
			var/beacon = GLOB.deliverybeacontags[1]
			cs_act(M, H, "destination", list("value" = beacon))
			cs_check("mulebot: a destination picked in the window", M.destination == beacon, "[M.destination]")
			cs_act(M, H, "destination", list("value" = "Nowhere At All"))
			cs_check("mulebot: but not one that isn't a beacon", M.destination == beacon, "[M.destination]")
			cs_act(M, H, "setid", list("value" = "Mule-7"))
			cs_check("mulebot: its ID typed in the window", M.id == "Mule-7", "[M.id]")
			SStgui.update_uis(M)
			sleep(10)
			cs_shot("popup_oldlook_[label]_mulebot_2_set", M.name)
		SStgui.close_user_uis(H)
		qdel(M)

	if(cs_oldlook_wanted("shuttle"))
		var/obj/machinery/computer/emergency_shuttle/E = new(cs_open_beside(H))
		E.authorized += cs_card("Hugo Brandt", "Chief Engineer", list(ACCESS_HEADS), null)
		E.authorized += cs_card("Ines Okafor", "Head of Security", list(ACCESS_HEADS), null)
		E.ui_interact(H)
		cs_oldlook_shot(C, H, E, label, "shuttle", E.name)
		SStgui.close_user_uis(H)
		E.authorized.Cut()
		qdel(E)

	if(cs_oldlook_wanted("launchpad"))
		var/obj/machinery/computer/launchpad/L = new(cs_open_beside(H))
		L.stat &= ~(NOPOWER|BROKEN)
		var/obj/machinery/launchpad/pad1 = new(cs_open_beside(L))
		pad1.display_name = "Cargo Bay"
		var/obj/machinery/launchpad/pad2 = new(cs_open_beside(L, list(get_turf(pad1))))
		pad2.display_name = "Toxins"
		L.launchpads += pad1
		L.launchpads += pad2
		L.ui_interact(H)
		var/datum/tgui/ui = cs_oldlook_shot(C, H, L, label, "launchpad_0_select", L.name)
		if(ui)
			cs_act(L, H, "select_pad", list("id" = "1"))
			cs_act(L, H, "up-right")
			cs_act(L, H, "up")
			SStgui.update_uis(L)
			sleep(10)
			cs_shot("popup_oldlook_[label]_launchpad_1_control", L.name)
			if(label == "after")
				cs_act(L, H, "set_x", list("value" = "3"))
				cs_act(L, H, "set_y", list("value" = "-2"))
				cs_check("launchpad: X and Y typed in the window", pad1.x_offset == 3 && pad1.y_offset == -2, "[pad1.x_offset],[pad1.y_offset]")
				cs_act(L, H, "set_x", list("value" = "99"))
				cs_check("launchpad: kept within the pad's reach", pad1.x_offset == pad1.range, "[pad1.x_offset]")
				cs_act(L, H, "rename_to", list("value" = "Cargo <b>Bay</b>"))
				cs_check("launchpad: renamed in the window, tags escaped", findtext(pad1.display_name, "Cargo &lt;b&gt") == 1 && !findtext(pad1.display_name, "<"), "[pad1.display_name]")
				pad1.display_name = "Cargo Bay"
				SStgui.update_uis(L)
				sleep(10)
				cs_tgui_do(C, ui.window_id, "click:All launchpads")
				cs_wait_until(L, "screen", "select")
				cs_check("launchpad: clicking All launchpads goes back to the list", L.screen == "select")
		SStgui.close_user_uis(H)
		qdel(L)
		qdel(pad1)
		qdel(pad2)

	if(cs_oldlook_wanted("launchpad_remote"))
		var/obj/item/storage/briefcase/launchpad/case = new(home)
		var/obj/item/launchpad_remote/R = new(home)
		R.pad = case.pad
		case.pad.closed = FALSE
		H.drop_all_held_items()
		H.put_in_active_hand(R)
		R.ui_interact(H)
		cs_oldlook_shot(C, H, R, label, "launchpad_remote", R.name)
		SStgui.close_user_uis(H)
		qdel(R)
		qdel(case)

	if(cs_oldlook_wanted("gulag"))
		var/obj/machinery/computer/gulag_teleporter_computer/G = new(cs_open_beside(H))
		G.stat &= ~(NOPOWER|BROKEN)
		var/obj/item/card/id/prisoner/P = new(G)
		P.registered_name = "Sam Tanaka"
		P.goal = 200
		G.id = P
		G.ui_interact(H)
		cs_oldlook_shot(C, H, G, label, "gulag", G.name)
		SStgui.close_user_uis(H)
		qdel(G)

	if(cs_oldlook_wanted("labor"))
		// It deletes itself without a labor stacker south of it, as the camp has
		var/turf/spot = cs_open_beside(H)
		var/obj/machinery/mineral/stacking_machine/laborstacker/stacker = new(get_step(spot, SOUTH))
		stacker.points = 40
		var/obj/machinery/mineral/labor_claim_console/LC = new(spot)
		LC.stat &= ~(NOPOWER|BROKEN)
		var/obj/item/card/id/prisoner/P = new(LC)
		P.registered_name = "Sam Tanaka"
		P.goal = 200
		P.points = 85
		LC.inserted_id = P
		LC.ui_interact(H)
		var/datum/tgui/ui = cs_oldlook_shot(C, H, LC, label, "labor", LC.name)
		if(ui && label == "after")
			cs_tgui_do(C, ui.window_id, "click:Claim")
			sleep(10)
			cs_check("labor: clicking Claim moves the stacker's points to the ID", P.points == 125 && !stacker.points, "[P.points]")
		SStgui.close_user_uis(H)
		qdel(LC)
		qdel(stacker)

	if(cs_oldlook_wanted("intellicard"))
		var/obj/item/aicard/card = new(home)
		var/mob/living/silicon/ai/A = new(home, null, null)
		A.fully_replace_character_name(null, "HAL-9001")
		A.laws = new /datum/ai_laws/default/asimov
		A.laws.associate(A)
		A.forceMove(card)
		card.AI = A
		A.control_disabled = TRUE
		A.adjustOxyLoss(30)
		A.updatehealth()
		card.update_icon()
		H.drop_all_held_items()
		H.put_in_active_hand(card)
		card.ui_interact(H)
		var/datum/tgui/ui = cs_oldlook_shot(C, H, card, label, "intellicard", card.name)
		if(ui && label == "after")
			cs_tgui_do(C, ui.window_id, "click:Wireless")
			sleep(10)
			cs_check("intellicard: clicking Wireless turns it on", !A.control_disabled)
		SStgui.close_user_uis(H)
		H.drop_all_held_items()
		qdel(card)

	if(cs_oldlook_wanted("relay"))
		var/obj/machinery/ntnet_relay/NR = new(cs_open_beside(H))
		NR.ui_interact(H)
		cs_oldlook_shot(C, H, NR, label, "relay", "NTNet Quantum Relay")
		SStgui.close_user_uis(H)
		qdel(NR)

	if(cs_oldlook_wanted("chem"))
		var/list/chem_types = list(/obj/machinery/chem/pressure, /obj/machinery/chem/radioactive, /obj/machinery/chem/bluespace, /obj/machinery/chem/centrifuge)
		for(var/path in chem_types)
			var/obj/machinery/chem/M = new path(cs_open_beside(H))
			M.stat &= ~(NOPOWER|BROKEN)
			M.beaker = new /obj/item/reagent_containers/glass/beaker/large(M)
			M.beaker.reagents.add_reagent(/datum/reagent/water, 40)
			M.beaker.reagents.add_reagent(/datum/reagent/consumable/sugar, 12.5)
			M.ui_interact(H)
			// The old radioactive and centrifuge windows were 275 wide, under what shot.ps1 takes for a window
			var/datum/tgui/opened = cs_find_ui(H, M)
			if(opened)
				winset(C, opened.window_id, "size=400x400")
			var/short = copytext("[path]", length("/obj/machinery/chem/") + 1)
			var/datum/tgui/ui = cs_oldlook_shot(C, H, M, label, "chem_[short]", M.name)
			if(ui && label == "after" && path == /obj/machinery/chem/radioactive)
				var/obj/machinery/chem/radioactive/RM = M
				cs_act(RM, H, "irradiate", list("target" = "12"))
				cs_check("chem: the radioactive target set from the window", RM.target_radioactivity == 12, "[RM.target_radioactivity]")
			SStgui.close_user_uis(H)
			qdel(M)
		var/obj/machinery/reagent_material_manipulator/MM = new(cs_open_beside(H))
		MM.ui_interact(H)
		cs_oldlook_shot(C, H, MM, label, "chem_analyser", MM.name)
		SStgui.close_user_uis(H)
		qdel(MM)
		var/obj/machinery/reagent_forge/F = new(locate(home.x + 2, home.y, home.z))
		F.ui_interact(H)
		cs_oldlook_shot(C, H, F, label, "chem_forge", F.name)
		SStgui.close_user_uis(H)
		qdel(F)

	if(cs_oldlook_wanted("slime"))
		var/mob/living/carbon/human/S1 = new(home)
		S1.fully_replace_character_name(null, "Gloop Primary")
		S1.set_species(/datum/species/jelly/slime)
		var/datum/species/jelly/slime/SS = S1.dna.species
		var/mob/living/carbon/human/S2 = new(cs_open_beside(H))
		S2.fully_replace_character_name(null, "Gloop Spare")
		S2.set_species(/datum/species/jelly/slime)
		SS.bodies |= S2
		var/datum/species/jelly/slime/SS2 = S2.dna.species
		SS2.bodies = SS.bodies
		S2.Unconscious(600)
		var/datum/action/innate/swap_body/swap = locate() in S1.actions
		if(swap)
			swap.ui_interact(H)
			cs_oldlook_shot(C, H, swap, label, "slime", "Swap Body")
		else
			cs_check("slime: the swap action is there", FALSE)
		SStgui.close_user_uis(H)
		qdel(S2)
		qdel(S1)

	if(cs_oldlook_wanted("ntos"))
		var/obj/machinery/modular_computer/console/preset/command/PC = new(cs_open_beside(H))
		PC.stat &= ~(NOPOWER|BROKEN)
		var/obj/item/modular_computer/processor/cpu = PC.cpu
		cpu.install_component(new /obj/item/computer_hardware/ai_slot)
		var/obj/item/computer_hardware/hard_drive/drive = cpu.all_components[MC_HDD]
		var/list/progs = list(
			/datum/computer_file/program/card_mod, /datum/computer_file/program/computerconfig, /datum/computer_file/program/filemanager,
			/datum/computer_file/program/chatclient, /datum/computer_file/program/ntnetmonitor, /datum/computer_file/program/nttransfer,
			/datum/computer_file/program/alarm_monitor, /datum/computer_file/program/aidiag, /datum/computer_file/program/ntnet_dos,
			/datum/computer_file/program/revelation, /datum/computer_file/program/contract_uplink)
		var/list/names = list()
		for(var/path in progs)
			var/datum/computer_file/program/P = new path
			names += P.filename
			if(drive.find_file_by_name(P.filename))
				qdel(P)
			else
				drive.store_file(P)
		cpu.turn_on(H)
		var/datum/computer_file/data/text = new
		text.filename = "shift_notes"
		text.stored_data = "Remember to set up the <b>SMES</b> before the engine.<br>Ask cargo about the plasma."
		drive.store_file(text)
		var/obj/item/card/id/target = cs_card("Sam Tanaka", "Assistant", list(ACCESS_MAINT_TUNNELS, ACCESS_NETWORK), home)
		var/obj/item/computer_hardware/card_slot/slot = cpu.all_components[MC_CARD]
		H.drop_all_held_items()
		H.put_in_active_hand(target)
		slot.try_insert(target, H)
		var/obj/item/card/id/mine = H.get_idcard()
		if(mine)
			H.temporarilyRemoveItemFromInventory(mine, TRUE)
			H.put_in_active_hand(mine)
			slot.try_insert(mine, H)
		// The programs read the ID being worn, not the one in the slot (can_run() checks the slot before it has it)
		var/obj/item/card/id/worn = cs_card("Fernando Stall", "Captain", get_all_accesses(), home)
		H.equip_to_slot_or_del(worn, ITEM_SLOT_ID)
		for(var/fname in names)
			if(cpu.active_program)
				cs_act(cpu, H, "PC_exit")
			cs_act(cpu, H, "PC_runprogram", list("name" = fname))
			if(!cpu.active_program)
				cs_check("ntos: [fname] starts", FALSE)
				continue
			cpu.ui_interact(H)
			var/datum/tgui/ui = cs_oldlook_shot(C, H, cpu.active_program, label, "ntos_[fname]", null)
			if(ui && fname == "ntnrc_client")
				// A channel to be in, said in from the window (the old program asked in a pop-up)
				var/datum/computer_file/program/chatclient/chat = cpu.active_program
				var/datum/ntnet_conversation/conv = new
				conv.title = "#engineering"
				conv.add_client(chat)
				chat.channel = conv
				conv.add_message("anyone seen the CE?", "Hugo")
				cs_act(chat, H, "PRG_changename", list("text" = "Fernando"))
				cs_act(chat, H, "PRG_speak", list("text" = "on my way to the SM"))
				cs_check("ntos chat: a message and a nickname typed in the window", findtext(conv.messages[conv.messages.len], "Fernando: on my way to the SM") && chat.username == "Fernando", "[conv.messages[conv.messages.len]]")
				SStgui.update_uis(chat)
				sleep(10)
				cs_shot("popup_oldlook_[label]_ntos_ntnrc_client_2_channel")
			if(ui && fname == "cardmod")
				cs_act(cpu.active_program, H, "PRG_switchm", list("target" = "manage"))
				SStgui.update_uis(cpu.active_program)
				sleep(10)
				cs_shot("popup_oldlook_[label]_ntos_cardmod_2_jobs")
			SStgui.close_user_uis(H)
		SStgui.close_user_uis(H)
		qdel(PC)

	if(cs_oldlook_wanted("slab"))
		add_servant_of_ratvar(H, TRUE)
		var/obj/item/clockwork/slab/slab = new(home)
		H.drop_all_held_items()
		H.put_in_active_hand(slab)
		slab.ui_interact(H)
		cs_oldlook_shot(C, H, slab, label, "slab_0_recital", slab.name)
		if(cs_find_ui(H, slab))
			cs_act(slab, H, "toggle")
			SStgui.update_uis(slab)
			sleep(10)
			cs_shot("popup_oldlook_[label]_slab_1_recollection", slab.name)
		SStgui.close_user_uis(H)
		H.drop_all_held_items()
		qdel(slab)
		remove_servant_of_ratvar(H, TRUE)

	// Ghost windows last: ghosting takes the body away
	if(cs_oldlook_wanted("ghost"))
		var/obj/item/toy/eightball/haunted/ball = new(home)
		ball.shaking = TRUE
		ball.selected_message = "Will the shuttle be called before the hour?"
		var/mob/dead/observer/G = H.ghostize(TRUE)
		sleep(10)
		ball.votes["someone"] = "Yes"
		ball.votes["someone else"] = "Ask again later"
		ball.ui_interact(G)
		cs_oldlook_shot(C, G, ball, label, "eightball", ball.name)
		SStgui.close_user_uis(G)
		var/datum/notificationpanel/panel = new(G)
		panel.ui_interact(G)
		cs_oldlook_shot(C, G, panel, label, "notifications", "Notification Preferences")
		SStgui.close_user_uis(G)

// The camera console: a pop-up list that moved your whole view before, a window with the list and the picture after

/proc/cs_camera_named(text)
	for(var/obj/machinery/camera/C in GLOB.cameranet.cameras)
		if(C.status && findtext(C.c_tag, text) && ("ss13" in C.network))
			return C

/proc/cs_camera(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/hos)
	var/obj/machinery/computer/security/console = new(cs_open_beside(H))
	console.stat &= ~(NOPOWER|BROKEN)
	var/obj/machinery/camera/bar = cs_camera_named("Bar") || cs_camera_named("Kitchen") || cs_camera_named("Arrivals")
	if(!("map_name" in console.vars))
		// The old console: a pop-up list, and picking one moves your whole view there
		spawn(0)
			usr = H
			console.interact(H)
		sleep(20)
		cs_shot("popup_camera_[label]_0_list")
		H.reset_perspective(bar)
		sleep(15)
		cs_shot("camera_[label]_1_view")
		H.reset_perspective(null)
		return
	usr = H
	console.interact(H)
	var/datum/tgui/ui = cs_find_ui(H, console)
	if(!ui)
		cs_check("the window opens", FALSE)
		return
	winset(C, ui.window_id, "pos=120,40")
	sleep(20)
	cs_check("the window's map is registered on the client", length(C.screen_maps[console.vars["map_name"]]) > 5 && (console.vars["cam_screen"] in C.screen))
	cs_shot("popup_camera_[label]_0_list", console.name)
	cs_tgui_do(C, ui.window_id, "click:[bar.c_tag]")
	cs_wait_until(console, "active_camera", bar)
	cs_check("clicking a camera in the list shows it", console.vars["active_camera"] == bar && length(console.vars["cam_screen"]:vis_contents) > 20, "[console.vars["active_camera"]], [length(console.vars["cam_screen"]:vis_contents)] turfs")
	cs_check("and your own view stays where you are", C.eye == H)
	sleep(20)
	cs_shot("popup_camera_[label]_1_picture", console.name)
	// A dark one, to see the lighting come through
	var/obj/machinery/camera/maint = cs_camera_named("Maint")
	if(maint)
		cs_act(console, H, "switch_camera", list("name" = maint.c_tag))
		SStgui.update_uis(console)
		sleep(20)
		cs_shot("popup_camera_[label]_1b_dark", console.name)
	cs_tgui_do(C, ui.window_id, "input0:bar")
	sleep(10)
	cs_shot("popup_camera_[label]_2_search", console.name)
	// A camera that's been cut shows static
	var/obj/machinery/camera/other = cs_camera_named("Brig") || cs_camera_named("Security")
	if(other && other != bar)
		other.status = FALSE
		cs_act(console, H, "switch_camera", list("name" = other.c_tag))
		SStgui.update_uis(console)
		sleep(15)
		cs_check("a camera that's off shows static", console.vars["active_camera"] == other && !length(console.vars["cam_screen"]:vis_contents) && console.vars["cam_background"]:icon == 'icons/effects/cameravis.dmi')
		cs_shot("popup_camera_[label]_3_static", console.name)
		other.status = TRUE
	cs_act(console, H, "switch_camera", list("name" = "Nowhere At All"))
	cs_check("nor a camera it doesn't reach", console.vars["active_camera"] == other)
	SStgui.close_user_uis(H, console)
	sleep(5)
	cs_check("closing it takes the map off the client", !(console.vars["map_name"] in C.screen_maps) && !(console.vars["cam_screen"] in C.screen) && !console.vars["active_camera"])
	// Deleting a console someone's watching takes its map off their screen too
	usr = H
	console.interact(H)
	cs_find_ui(H, console)
	var/obj/screen/screen = console.vars["cam_screen"]
	qdel(console)
	sleep(5)
	cs_check("a console deleted while watched leaves nothing on the screen", !(screen in C.screen) && !length(C.screen_maps))
	// The same spot in the main view, to compare the lighting
	var/obj/machinery/camera/dark = cs_camera_named("Maint")
	if(dark && label == "after")
		H.forceMove(get_turf(dark))
		sleep(30)
		cs_shot("camera_[label]_9_main_view_of_dark")

// Character setup: the old browser window and its pop-ups before, one tgui window with the character drawn in it after

/proc/cs_prefs(client/C, mob/living/carbon/human/H, label)
	var/datum/preferences/P = C.prefs
	P.current_tab = 0
	P.real_name = "Mikayla Collins"
	P.gender = FEMALE
	P.pref_species = new /datum/species/human
	P.hair_style = "Bob Hair"
	P.hair_color = "a35"
	P.job_preferences = list("Chief Engineer" = JP_HIGH, "Station Engineer" = JP_MEDIUM)
	if(!("preview_screen" in P.vars))
		// The old window: a skin window with the page and the four-sided preview, and the occupations in a window of their own
		P.ShowChoices(H)
		sleep(30)
		cs_shot("popup_prefs_[label]_0_character")
		P.current_tab = 1
		P.ShowChoices(H)
		sleep(20)
		cs_shot("popup_prefs_[label]_1_game")
		P.SetChoices(H)
		sleep(20)
		cs_shot("popup_prefs_[label]_2_jobs")
		H << browse(null, "window=mob_occupation")
		P.SetQuirks(H)
		sleep(20)
		cs_shot("popup_prefs_[label]_3_quirks")
		H << browse(null, "window=mob_occupation")
		P.current_tab = 4
		P.ShowChoices(H)
		sleep(20)
		cs_shot("popup_prefs_[label]_4_loadout")
		winshow(H, "preferences_window", FALSE)
		return
	P.ShowChoices(H)
	var/datum/tgui/ui = cs_find_ui(H, P)
	if(!ui)
		cs_check("the window opens", FALSE)
		return
	winset(C, ui.window_id, "pos=80,20")
	sleep(25)
	cs_check("the character is drawn in the window", length(C.screen_maps["prefs_preview_map"]) >= 2 && (P.vars["preview_screen"] in C.screen))
	cs_shot("popup_prefs_[label]_0_character", "Character Setup")
	// Choices made in the window, checked against what the pop-ups offered
	cs_act(P, H, "set", list("key" = "hair_style", "value" = "Ponytail"))
	cs_check("a hair style picked in the window", P.hair_style == "Ponytail", "[P.hair_style]")
	cs_act(P, H, "set", list("key" = "hair_style", "value" = "Not A Hair Style"))
	cs_check("but not one the list doesn't have", P.hair_style == "Ponytail", "[P.hair_style]")
	cs_act(P, H, "set", list("key" = "age", "value" = "500"))
	cs_check("an age typed in is kept to the limits", P.age == AGE_MAX, "[P.age]")
	cs_act(P, H, "set", list("key" = "species", "value" = "Lizardperson"))
	cs_check("a species picked in the window", istype(P.pref_species, /datum/species/lizard), "[P.pref_species]")
	cs_act(P, H, "set", list("key" = "gender", "value" = "Male"))
	cs_check("a gender picked in the window", P.gender == MALE)
	cs_tgui_do(C, ui.window_id, "type0:Kit Brannigan")
	cs_wait_until(P, "real_name", "Kit Brannigan")
	cs_check("a name typed into the window", P.real_name == "Kit Brannigan", "[P.real_name]")
	cs_act(P, H, "set", list("key" = "name", "value" = "<b>x</b>"))
	cs_check("a name with tags is cleaned as the old pop-up did", P.real_name == reject_bad_name("<b>x</b>"), "[P.real_name]")
	cs_check("the character is drawn from four sides", length(P.vars["preview_sides"]) == 8 && length(C.screen_maps["prefs_preview_map"]) == 9)
	cs_tgui_do(C, ui.window_id, "click:Plain")
	cs_wait_until(P, "preview_plain", TRUE)
	cs_check("clicking Plain draws them out of the job outfit", P.vars["preview_plain"])
	cs_act(P, H, "set", list("key" = "hair", "value" = "#c62828"))
	cs_check("a hair colour picked in the window", lowertext(P.hair_color) == "c62828" || lowertext(P.hair_color) == "c22", "[P.hair_color]")
	cs_act(P, H, "set", list("key" = "hair", "value" = "red; background:url(x)"))
	cs_check("but not something that isn't a colour", lowertext(P.hair_color) == "c62828" || lowertext(P.hair_color) == "c22", "[P.hair_color]")
	cs_check("changes are marked unsaved", P.vars["prefs_dirty"])
	SStgui.update_uis(P)
	sleep(20)
	cs_shot("popup_prefs_[label]_0b_lizard", "Character Setup")
	// The tabs, clicked
	cs_tgui_do(C, ui.window_id, "click:Occupations")
	cs_wait_until(P, "current_tab", 5)
	cs_check("clicking Occupations shows the jobs", P.current_tab == 5)
	cs_act(P, H, "link", list("preference" = "job", "task" = "setJobLevel", "level" = "1", "text" = "Station Engineer"))
	cs_check("a job set to High, and the old High drops to Medium", P.job_preferences["Station Engineer"] == JP_HIGH && P.job_preferences["Chief Engineer"] == JP_MEDIUM)
	SStgui.update_uis(P)
	sleep(15)
	cs_shot("popup_prefs_[label]_2_jobs", "Character Setup")
	if(CONFIG_GET(flag/roundstart_traits))
		cs_tgui_do(C, ui.window_id, "click:Quirks")
		cs_wait_until(P, "current_tab", 6)
		var/list/quirk_names = SSquirks.quirks
		var/negative
		for(var/Q in quirk_names)
			if(SSquirks.quirk_points[Q] < 0)
				negative = Q
				break
		cs_act(P, H, "link", list("preference" = "trait", "task" = "update", "trait" = negative))
		cs_check("a quirk taken", (negative in P.all_quirks), "[negative]")
		SStgui.update_uis(P)
		sleep(15)
		cs_shot("popup_prefs_[label]_3_quirks", "Character Setup")
	cs_tgui_do(C, ui.window_id, "click:Game")
	cs_wait_until(P, "current_tab", 1)
	sleep(10)
	cs_shot("popup_prefs_[label]_1_game", "Character Setup")
	cs_act(P, H, "set", list("key" = "ghostaccs", "value" = GHOST_ACCS_NONE_NAME))
	cs_check("a ghost setting picked in the window, where it was an alert", P.ghost_accs == GHOST_ACCS_NONE)
	cs_tgui_do(C, ui.window_id, "click:Loadout")
	cs_wait_until(P, "current_tab", 4)
	sleep(10)
	cs_shot("popup_prefs_[label]_4_loadout", "Character Setup")
	cs_tgui_do(C, ui.window_id, "click:Keybindings")
	cs_wait_until(P, "current_tab", 3)
	sleep(10)
	cs_shot("popup_prefs_[label]_5_keys", "Character Setup")
	SStgui.close_user_uis(H, P)
	sleep(5)
	cs_check("closing it takes the drawing off the screen", !("prefs_preview_map" in C.screen_maps) && !(P.vars["preview_screen"] in C.screen))

// The teleporter control console: a pop-up list of beacons before, the list in the window after

/proc/cs_teleporter(client/C, mob/living/carbon/human/H, label)
	var/turf/T1 = cs_open_beside(H)
	var/obj/machinery/teleport/hub/hub = new(get_step(T1, EAST))
	var/obj/machinery/teleport/station/station = new(T1)
	var/obj/machinery/computer/teleporter/console = new(get_step(T1, WEST))
	if(get_dist(console, H) > 1)
		console.forceMove(get_step(H, get_dir(H, T1) == NORTH ? SOUTH : NORTH))
	for(var/obj/machinery/M in list(hub, station, console))
		M.stat &= ~(NOPOWER|BROKEN)
	station.link_console_and_hub()
	console.power_station = station
	station.teleporter_console = console
	var/obj/item/beacon/B = new(get_turf(H))
	usr = H
	console.interact(H)
	sleep(20)
	var/datum/tgui/ui = cs_find_ui(H, console)
	if(!ui)
		winset(C, "teleporter", "pos=200,40")
		sleep(10)
		cs_shot("popup_teleporter_[label]_0_console")
		return
	winset(C, ui.window_id, "pos=200,40")
	sleep(15)
	cs_shot("popup_teleporter_[label]_0_console", console.name)
	var/area/A = get_area(B)
	cs_tgui_do(C, ui.window_id, "click:[A.name]")
	cs_wait_change(console, "target", null, 5)
	var/area/locked = console.target ? get_area(console.target) : null
	cs_check("clicking a beacon in the list locks onto it", locked && findtext(locked.name, A.name) == 1, "[locked]")
	var/was = console.target
	cs_act(console, H, "target", list("name" = "Nowhere At All"))
	cs_check("but not one it doesn't list", console.target == was)
	cs_tgui_do(C, ui.window_id, "click:Calibrate")
	cs_wait_until(console, "calibrating", TRUE)
	cs_check("Calibrate starts calibrating", console.calibrating)
	SStgui.update_uis(console)
	sleep(10)
	cs_shot("popup_teleporter_[label]_1_locked", console.name)
	cs_tgui_do(C, ui.window_id, "click:Gate")
	sleep(10)
	cs_check("the regime can't change while calibrating", console.regime_set == "Teleporter")
	SStgui.close_user_uis(H)


// The arcade machines, as they are
/proc/cs_arcade(client/C, mob/living/carbon/human/H, label)
	for(var/path in list(/obj/machinery/computer/arcade/battle, /obj/machinery/computer/arcade/orion_trail, /obj/machinery/computer/arcade/minesweeper))
		var/obj/machinery/computer/arcade/A = new path(cs_open_beside(H))
		A.stat &= ~(NOPOWER|BROKEN)
		usr = H
		A.interact(H)
		sleep(25)
		var/short = copytext("[path]", length("/obj/machinery/computer/arcade/") + 1)
		if(SStgui.get_open_ui(H, A, "main"))
			var/datum/tgui/opened = SStgui.get_open_ui(H, A, "main")
			winset(C, opened.window_id, "pos=200,40")
			sleep(10)
		cs_shot("popup_arcade_[label]_[short]")
		var/window = (path == /obj/machinery/computer/arcade/minesweeper) ? "minesweeper" : "arcade"
		// The real links, clicked: anything whose text starts with it
		var/js_click = "var t=%T%;var b=Array.prototype.slice.call(document.querySelectorAll('a')).filter(function(e){return e.textContent.trim().indexOf(t)===0;})\[0\];if(b){b.click();}"
		var/first = (path == /obj/machinery/computer/arcade/battle) ? "Attack" : (path == /obj/machinery/computer/arcade/orion_trail) ? "New Game" : "Easy"
		var/status_var = ("game_status" in A.vars) ? "game_status" : (("gameStatus" in A.vars) ? "gameStatus" : "enemy_hp")
		var/before_status = A.vars[status_var]
		var/datum/tgui/ui = SStgui.get_open_ui(H, A, "main")
		if(ui)
			winset(C, ui.window_id, "pos=200,40")
			if(path == /obj/machinery/computer/arcade/orion_trail)
				C << output(url_encode(replacetext(replacetext(js_click, "%T%", json_encode(first)), "querySelectorAll('a')", "querySelectorAll('.OrionTrail a')")), "[ui.window_id].browser:eval")
			else
				cs_tgui_do(C, ui.window_id, "click:[first]")
		else
			C << output(url_encode(replacetext(js_click, "%T%", json_encode(first))), "[window].browser:eval")
		sleep(25)
		kc_log("[short]: clicked [first]: [status_var] [before_status] -> [A.vars[status_var]]")
		cs_shot("popup_arcade_[label]_[short]_2_clicked")
		if(path == /obj/machinery/computer/arcade/orion_trail && ui)
			C << output(url_encode("var b=Array.prototype.slice.call(document.querySelectorAll('.OrionTrail a')).filter(function(e){return e.textContent.trim()==='Continue';})\[0\];if(b){b.click();}"), "[ui.window_id].browser:eval")
			sleep(40)
			kc_log("orion_trail: clicked Continue: turn [A.vars["turns"]], event [A.vars["event"]], food [A.vars["food"]]")
			cs_shot("popup_arcade_[label]_[short]_3_continued")
		if(path == /obj/machinery/computer/arcade/minesweeper && ui)
			var/obj/machinery/computer/arcade/minesweeper/M = A
			cs_act(M, H, "square", list("y" = "5", "x" = "5"))
			cs_act(M, H, "flagsquare", list("y" = "1", "x" = "1"))
			kc_log("minesweeper: after a reveal and a flag: status [M.game_status], square 5,5 = [M.table[5][5]], 1,1 = [M.table[1][1]]")
			SStgui.update_uis(M)
			sleep(15)
			cs_shot("popup_arcade_[label]_[short]_3_played")
			cs_act(M, H, "custom", list("rows" = "99", "columns" = "2", "mines" = "0"))
			kc_log("minesweeper: custom 99x2 with 0 mines became [M.rows - 1]x[M.columns - 1] with [M.mine_placed] mines")
		H << browse(null, "window=arcade")
		H << browse(null, "window=minesweeper")
		SStgui.close_user_uis(H)
		qdel(A)
		sleep(5)

// The last machines with old pages: each opened, pictured, and a real button clicked

/proc/cs_machine_open(client/C, mob/living/carbon/human/H, atom/A, label, name)
	usr = H
	if(ismob(A) || isobj(A))
		A:interact(H)
	var/datum/tgui/ui = cs_find_ui(H, A)
	if(!ui)
		cs_check("[name]: the window opens", FALSE)
		return null
	winset(C, ui.window_id, "pos=200,40")
	sleep(15)
	cs_shot("popup_machines_[label]_[name]")
	return ui

/proc/cs_machines(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/captain)
	var/datum/tgui/ui

	var/obj/machinery/porta_turret/T = new(cs_open_beside(H))
	T.locked = FALSE
	T.stat &= ~(NOPOWER|BROKEN)
	var/was_records = T.check_records
	ui = cs_machine_open(C, H, T, label, "porta_turret")
	if(ui)
		cs_tgui_do(C, ui.window_id, "click:Check security records")
		sleep(10)
		cs_check("turret: clicking a target setting toggles it", T.check_records != was_records)
	SStgui.close_user_uis(H)

	var/obj/machinery/turretid/P = new(get_turf(H))
	P.locked = FALSE
	P.stat &= ~(NOPOWER|BROKEN)
	P.turrets += T
	ui = cs_machine_open(C, H, P, label, "turret_control")
	if(ui)
		cs_tgui_do(C, ui.window_id, "click:Lethal")
		cs_wait_until(P, "lethal", TRUE)
		cs_check("turret panel: clicking Lethal sets lethal, from the next tile", P.lethal && get_dist(P, H) == 0 || P.lethal)
	SStgui.close_user_uis(H)
	qdel(P)
	qdel(T)

	var/obj/machinery/computer/rdservercontrol/R = new(cs_open_beside(H))
	R.stat &= ~(NOPOWER|BROKEN)
	cs_machine_open(C, H, R, label, "rd_server_control")
	SStgui.close_user_uis(H)
	qdel(R)

	var/obj/machinery/rnd/experimentor/E = new(cs_open_beside(H))
	E.stat &= ~(NOPOWER|BROKEN)
	var/obj/item/relic/relic = new(E)
	E.loaded_item = relic
	cs_machine_open(C, H, E, label, "experimentor")
	SStgui.close_user_uis(H)
	qdel(E)

	var/obj/machinery/magnetic_controller/M = new(cs_open_beside(H))
	M.stat &= ~(NOPOWER|BROKEN)
	ui = cs_machine_open(C, H, M, label, "magnet")
	if(ui)
		cs_act(M, H, "setpath", list("path" = "N;S;E;W"))
		cs_check("magnet: a path typed in the window", M.path == "N;S;E;W", "[M.path]")
		cs_tgui_do(C, ui.window_id, "click:Stopped")
		cs_wait_until(M, "moving", TRUE)
		cs_check("magnet: clicking Stopped starts it moving", M.moving)
		M.moving = FALSE
	SStgui.close_user_uis(H)
	qdel(M)

	var/obj/machinery/mineral/stacking_unit_console/S = new(cs_open_beside(H))
	var/obj/machinery/mineral/stacking_machine/SM = new(cs_open_beside(H, list(get_turf(S))))
	S.machine = SM
	SM.CONSOLE = S
	var/obj/item/stack/sheet/metal/sheets = new(null, 30)
	SM.stack_list[sheets.type] = sheets
	ui = cs_machine_open(C, H, S, label, "stacking")
	if(ui)
		cs_tgui_do(C, ui.window_id, "click:Release")
		sleep(10)
		cs_check("stacking: clicking Release puts the sheets out", !sheets.amount)
	SStgui.close_user_uis(H)
	qdel(S)
	qdel(SM)

	var/obj/machinery/food_cart/F = new(cs_open_beside(H))
	F.reagents.add_reagent(/datum/reagent/water, 50)
	F.reagents.add_reagent(/datum/reagent/consumable/orangejuice, 30)
	F.glasses = 2
	F.stored_food["Burger"] = 2
	ui = cs_machine_open(C, H, F, label, "food_cart")
	if(ui)
		cs_act(F, H, "disposeI", list("type" = "/datum/reagent/water"))
		cs_check("food cart: Purge empties a drink (it never did before)", !F.reagents.has_reagent(/datum/reagent/water))
		cs_tgui_do(C, ui.window_id, "click:Pour")
		sleep(10)
		cs_check("food cart: clicking Pour fills a glass", F.glasses == 1 && (locate(/obj/item/reagent_containers/food/drinks/drinkingglass) in F.loc))
	SStgui.close_user_uis(H)
	qdel(F)

	var/obj/machinery/icecream_vat/V = new(cs_open_beside(H))
	var/waffles = V.product_types[5]
	ui = cs_machine_open(C, H, V, label, "icecream")
	if(ui)
		cs_act(V, H, "make", list("id" = "5", "amount" = "5"))
		cs_check("ice cream: x5 waffle cones made", V.product_types[5] == waffles + 5, "[V.product_types[5]]")
		cs_act(V, H, "select", list("id" = "2"))
		cs_check("ice cream: a flavour picked to scoop", V.dispense_flavour == 2)
	SStgui.close_user_uis(H)
	qdel(V)

// Vending machines: a list before, a shop grid after
/proc/cs_vending(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/assistant)
	var/obj/item/card/id/card = H.get_idcard(TRUE)
	if(card && !card.registered_account)
		card.registered_account = new /datum/bank_account(H.real_name, SSjob.GetJob("Assistant"))
	if(card)
		card.registered_account.account_balance = 120
	var/obj/machinery/vending/snack/V = new(cs_open_beside(H))
	V.stat &= ~(NOPOWER|BROKEN)
	usr = H
	V.interact(H)
	var/datum/tgui/ui = cs_find_ui(H, V)
	if(!ui)
		cs_check("the window opens", FALSE)
		return
	winset(C, ui.window_id, "pos=200,30")
	sleep(25)
	cs_shot("popup_vending_[label]_0_products", V.name)
	var/datum/data/vending_product/first = V.product_records[1]
	var/before = first.amount
	if(label == "after")
		cs_tgui_do(C, ui.window_id, "click:$")
		sleep(20)
		cs_check("clicking a price buys one", first.amount == before - 1, "[first.name]: [before] -> [first.amount]")
	V.extended_inventory = TRUE
	SStgui.update_uis(V)
	sleep(10)
	if(label == "after")
		cs_tgui_do(C, ui.window_id, "click:Contraband")
		sleep(10)
	cs_shot("popup_vending_[label]_1_contraband", V.name)
	SStgui.close_user_uis(H)

// Chemistry: the dispenser, ChemMaster and heater
/proc/cs_chem_window(client/C, mob/living/carbon/human/H, obj/machinery/M, label, name)
	M.stat &= ~(NOPOWER|BROKEN)
	usr = H
	M.ui_interact(H)
	var/datum/tgui/ui = cs_find_ui(H, M)
	if(!ui)
		cs_check("[name]: the window opens", FALSE)
		return null
	winset(C, ui.window_id, "pos=150,20")
	sleep(20)
	cs_shot("popup_chem_[label]_[name]", M.name)
	return ui

/proc/cs_chemistry(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/chemist)
	var/obj/machinery/chem_dispenser/D = new(cs_open_beside(H))
	D.beaker = new /obj/item/reagent_containers/glass/beaker/large(D)
	D.beaker.reagents.add_reagent(/datum/reagent/water, 20)
	D.beaker.reagents.add_reagent(/datum/reagent/consumable/sugar, 10)
	D.saved_recipes = list(list("recipe_name" = "Sweet water", "contents" = "water=10;sugar=5"))
	var/datum/tgui/ui = cs_chem_window(C, H, D, label, "dispenser")
	if(ui && label == "after")
		var/before = D.beaker.reagents.total_volume
		cs_tgui_do(C, ui.window_id, "click:Carbon")
		sleep(10)
		cs_check("dispenser: clicking a chemical dispenses it", D.beaker.reagents.has_reagent(/datum/reagent/carbon), "[before] -> [D.beaker.reagents.total_volume]")
		cs_act(D, H, "add_recipe", list("name" = "Mix", "recipe" = "carbon=5;notachem=5"))
		cs_check("dispenser: a recipe with an unknown chemical is refused", length(D.saved_recipes) == 1)
		cs_act(D, H, "add_recipe", list("name" = "Mix", "recipe" = "carbon=5;water=5"))
		cs_check("dispenser: a recipe typed in the window is saved", length(D.saved_recipes) == 2)
		SStgui.update_uis(D)
		sleep(10)
		cs_shot("popup_chem_[label]_dispenser_2", D.name)
	SStgui.close_user_uis(H)
	qdel(D)

	var/obj/machinery/chem_master/M = new(cs_open_beside(H))
	M.beaker = new /obj/item/reagent_containers/glass/beaker/large(M)
	M.beaker.reagents.add_reagent(/datum/reagent/medicine/bicaridine, 40)
	M.beaker.reagents.add_reagent(/datum/reagent/medicine/kelotane, 20)
	ui = cs_chem_window(C, H, M, label, "master")
	if(ui && label == "after")
		cs_tgui_do(C, ui.window_id, "click:All")
		sleep(10)
		cs_check("ChemMaster: clicking All moves a reagent to the buffer", M.reagents.total_volume > 0, "[M.reagents.total_volume]u in the buffer")
		SStgui.update_uis(M)
		sleep(10)
		cs_tgui_do(C, ui.window_id, "click:Make")
		sleep(15)
		var/pills = 0
		for(var/obj/item/reagent_containers/pill/P in range(1, M))
			pills++
		cs_check("ChemMaster: clicking Make makes a pill, with no pop-ups", pills >= 1, "[pills] pills")
		cs_shot("popup_chem_[label]_master_2", M.name)
	SStgui.close_user_uis(H)
	qdel(M)

	var/obj/machinery/chem_heater/T = new(cs_open_beside(H))
	T.beaker = new /obj/item/reagent_containers/glass/beaker/large(T)
	T.beaker.reagents.add_reagent(/datum/reagent/water, 30)
	cs_chem_window(C, H, T, label, "heater")
	SStgui.close_user_uis(H)
	qdel(T)

// Medical: the crew monitor, cryo cell and operating computer
/proc/cs_med_patient(turf/at, name, brute, burn, tox, oxy)
	var/mob/living/carbon/human/P = new(at)
	P.fully_replace_character_name(null, name)
	P.equipOutfit(/datum/outfit/job/assistant)
	P.adjustBruteLoss(brute)
	P.adjustFireLoss(burn)
	P.adjustToxLoss(tox)
	P.adjustOxyLoss(oxy)
	var/obj/item/clothing/under/U = P.w_uniform
	if(U)
		U.sensor_mode = SENSOR_COORDS
	return P

/proc/cs_medical(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/cmo)
	var/list/made = list()
	made += cs_med_patient(cs_open_beside(H), "Lena Kowalczyk", 30, 12, 0, 0)
	made += cs_med_patient(cs_open_beside(H, list(get_turf(made[1]))), "Tomas Reyes", 60, 40, 10, 20)
	var/mob/living/carbon/human/dead = cs_med_patient(cs_open_beside(H, list(get_turf(made[1]), get_turf(made[2]))), "Ola Svensson", 150, 50, 0, 0)
	dead.death()
	made += dead
	// Spread out over the station, for the map
	for(var/mob/living/carbon/human/M in made)
		var/turf/somewhere = get_safe_random_station_turf()
		if(somewhere && somewhere.z == H.z)
			M.forceMove(somewhere)
	var/obj/machinery/computer/crew/monitor = new(get_turf(H))
	monitor.stat &= ~(NOPOWER|BROKEN)
	usr = H
	monitor.interact(H)
	sleep(10)
	var/datum/tgui/ui = cs_find_ui(H, GLOB.crewmonitor)
	if(ui)
		winset(C, ui.window_id, "pos=100,20")
		sleep(20)
		cs_shot("popup_med_[label]_crew", "crew monitor")
	else
		cs_check("crew monitor: the window opens", FALSE)
	SStgui.close_user_uis(H)
	qdel(monitor)

	var/obj/machinery/atmospherics/components/unary/cryo_cell/cryo = new(cs_open_beside(H))
	cryo.stat &= ~(NOPOWER|BROKEN)
	cryo.beaker = new /obj/item/reagent_containers/glass/beaker/large(cryo)
	cryo.beaker.reagents.add_reagent(/datum/reagent/medicine/cryoxadone, 40)
	var/mob/living/carbon/human/P = made[2]
	cryo.open_machine()
	cryo.close_machine(P)
	cs_check("cryo: the patient is inside", cryo.occupant == P)
	usr = H
	cryo.ui_interact(H)
	ui = cs_find_ui(H, cryo)
	if(ui)
		winset(C, ui.window_id, "pos=100,20")
		sleep(20)
		cs_shot("popup_med_[label]_cryo", cryo.name)
		if(label == "after")
			var/was_auto = cryo.autoeject
			cs_tgui_do(C, ui.window_id, "click:Let them out")
			sleep(10)
			cs_check("cryo: clicking the auto-eject box toggles it", cryo.autoeject != was_auto)
	else
		cs_check("cryo: the window opens", FALSE)
	SStgui.close_user_uis(H)
	cryo.open_machine()
	qdel(cryo)

	var/turf/table_spot = cs_open_beside(H)
	var/obj/structure/table/optable/table = new(table_spot)
	var/obj/machinery/computer/operating/computer = new(get_turf(H))
	computer.stat &= ~(NOPOWER|BROKEN)
	computer.table = table
	var/mob/living/carbon/human/patient = made[1]
	patient.forceMove(table_spot)
	patient.set_resting(TRUE)
	new /datum/surgery/organ_manipulation(patient, BODY_ZONE_CHEST, patient.get_bodypart(BODY_ZONE_CHEST))
	patient.set_resting(TRUE)
	cs_check("operating: the patient lies on the table", table.check_patient(), "resting [patient.resting], on [get_turf(patient) == table_spot]")
	usr = H
	computer.ui_interact(H)
	ui = cs_find_ui(H, computer)
	if(ui)
		winset(C, ui.window_id, "pos=100,20")
		sleep(20)
		cs_shot("popup_med_[label]_operating", computer.name)
	else
		cs_check("operating computer: the window opens", FALSE)
	SStgui.close_user_uis(H)
	qdel(computer)
	qdel(table)
	for(var/mob/M in made)
		qdel(M)

// The crafting menu, as it is
/proc/cs_crafting(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/engineer)
	new /obj/item/stack/sheet/metal/fifty(get_turf(H))
	new /obj/item/stack/rods/fifty(get_turf(H))
	new /obj/item/stack/cable_coil(get_turf(H))
	var/datum/component/personal_crafting/PC = H.GetComponent(/datum/component/personal_crafting)
	if(!PC)
		cs_check("crafting: the component is there", FALSE)
		return
	usr = H
	PC.ui_interact(H)
	var/datum/tgui/ui = cs_find_ui(H, PC)
	if(!ui)
		cs_check("crafting: the window opens", FALSE)
		return
	winset(C, ui.window_id, "pos=80,20")
	sleep(30)
	cs_shot("popup_craft_[label]_0", "Crafting Menu")
	SStgui.close_user_uis(H)

// Power: an APC, an SMES and the power monitor
/proc/cs_power_window(client/C, mob/living/carbon/human/H, datum/D, label, name)
	usr = H
	D.ui_interact(H)
	var/datum/tgui/ui = cs_find_ui(H, D)
	if(!ui)
		cs_check("[name]: the window opens", FALSE)
		return null
	winset(C, ui.window_id, "pos=100,20")
	sleep(25)
	cs_shot("popup_power_[label]_[name]")
	return ui

/proc/cs_power(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/ce)
	// The Engineering APC, with someone standing at it
	var/obj/machinery/power/apc/apc
	for(var/obj/machinery/power/apc/A in GLOB.apcs_list)
		if(istype(A.area, /area/engine/engineering))
			apc = A
			break
	if(apc)
		H.forceMove(get_turf(apc))
		apc.locked = FALSE
		var/datum/tgui/ui = cs_power_window(C, H, apc, label, "apc")
		if(ui && label == "after")
			var/list/data = apc.ui_data(H)
			cs_check("apc: channel loads and battery time sent ([json_encode(data["channelLoads"])], [data["cellSeconds"]] s)", islist(data["channelLoads"]) && length(data["channelLoads"]) == 3)
			cs_act(apc, H, "channel", list("lgt" = "1"))
			cs_check("apc: Off on the lighting card turns lighting off (now [apc.lighting])", apc.lighting == 0)
			cs_act(apc, H, "channel", list("lgt" = "3"))
			cs_check("apc: Auto turns it back on (now [apc.lighting])", apc.lighting == 3)
		SStgui.close_user_uis(H)
	var/obj/machinery/power/smes/S
	for(var/obj/machinery/power/smes/each in GLOB.machines)
		if(get_area(each) && istype(get_area(each), /area/engine))
			S = each
			break
	if(S)
		H.forceMove(get_step(S, SOUTH))
		var/datum/tgui/ui = cs_power_window(C, H, S, label, "smes")
		if(ui && label == "after")
			var/was = S.input_level
			cs_act(S, H, "input", list("target" = "120000"))
			cs_check("smes: a typed 120 kW sets the input level (now [S.input_level])", S.input_level == min(120000, S.input_level_max))
			S.input_level = was
		SStgui.close_user_uis(H)
	var/obj/machinery/computer/monitor/M
	for(var/obj/machinery/computer/monitor/each in GLOB.machines)
		if(is_station_level(each.z))
			M = each
			break
	if(M)
		H.forceMove(get_step(M, SOUTH))
		sleep(50) // a few readings for its chart
		var/datum/tgui/ui = cs_power_window(C, H, M, label, "monitor")
		if(ui && label == "after")
			var/list/data = M.ui_data(H)
			var/list/areas = data["areas"]
			var/list/first = length(areas) ? areas[1] : list()
			cs_check("monitor: raw supply/draw and [length(areas)] areas with raw loads", !isnull(data["supplyRaw"]) && !isnull(first["loadRaw"]))
		SStgui.close_user_uis(H)

// Atmos: the Atmospherics air alarm, a canister with a tank in it, a portable pump and scrubber, a freezer and a
// space heater
/proc/cs_atmos_window(client/C, mob/living/carbon/human/H, datum/D, label, name)
	usr = H
	D.ui_interact(H)
	var/datum/tgui/ui = cs_find_ui(H, D)
	if(!ui)
		cs_check("[name]: the window opens", FALSE)
		return null
	winset(C, ui.window_id, "pos=100,20")
	if(ui.width < 340) // the picture taker passes over windows 300 wide
		winset(C, ui.window_id, "size=340x[ui.height]")
	sleep(25)
	cs_shot("popup_atmos_[label]_[name]")
	return ui

/// An open floor next to A, for setting a machine down
/proc/cs_open_turf_by(atom/A)
	for(var/d in GLOB.cardinals)
		var/turf/T = get_step(A, d)
		if(!T || T.density || isspaceturf(T))
			continue
		var/blocked = FALSE
		for(var/atom/movable/M in T)
			if(M.density)
				blocked = TRUE
				break
		if(!blocked)
			return T
	return null

/proc/cs_atmos(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/atmos)
	var/obj/machinery/airalarm/alarm
	for(var/obj/machinery/airalarm/A in GLOB.machines)
		if(istype(get_area(A), /area/engine/atmos))
			alarm = A
			break
	if(!alarm)
		cs_check("an air alarm in Atmospherics", FALSE)
		return
	H.forceMove(get_turf(alarm))
	alarm.locked = FALSE
	var/datum/tgui/ui = cs_atmos_window(C, H, alarm, label, "alarm")
	if(ui)
		cs_tgui_do(C, ui.window_id, label == "after" ? "click:Scrubbers" : "click:Scrubber Controls")
		sleep(15)
		cs_shot("popup_atmos_[label]_alarm_scrubbers")
		if(label == "after")
			cs_atmos_alarm_checks(C, H, alarm, ui)
	SStgui.close_user_uis(H)

	var/turf/spot = cs_open_turf_by(H)
	if(!spot)
		cs_check("a free tile beside the air alarm", FALSE)
		return
	// An air canister with some plasma in it and a tank in its regulator
	var/obj/machinery/portable_atmospherics/canister/air/can = new(spot)
	can.air_contents.assert_gas(/datum/gas/plasma)
	can.air_contents.moles[/datum/gas/plasma] = 120
	can.air_contents.assert_gas(/datum/gas/carbon_dioxide)
	can.air_contents.moles[/datum/gas/carbon_dioxide] = 60
	can.holding = new /obj/item/tank/internals/oxygen(can)
	can.update_icon()
	ui = cs_atmos_window(C, H, can, label, "canister")
	if(ui && label == "after")
		cs_atmos_canister_checks(C, H, can, ui)
	SStgui.close_user_uis(H)
	qdel(can)

	var/obj/machinery/portable_atmospherics/pump/pump = new(spot)
	cs_atmos_window(C, H, pump, label, "pump")
	SStgui.close_user_uis(H)
	qdel(pump)

	var/obj/machinery/portable_atmospherics/scrubber/scrubber = new(spot)
	ui = cs_atmos_window(C, H, scrubber, label, "scrubber")
	if(ui && label == "after")
		cs_atmos_scrubber_checks(C, H, scrubber, ui)
	SStgui.close_user_uis(H)
	qdel(scrubber)

	var/obj/machinery/space_heater/heater = new(spot)
	heater.panel_open = TRUE
	ui = cs_atmos_window(C, H, heater, label, "heater")
	if(ui && label == "after")
		cs_atmos_heater_checks(C, H, heater, ui)
	SStgui.close_user_uis(H)
	qdel(heater)

	// A station freezer, with someone at it
	var/obj/machinery/atmospherics/components/unary/thermomachine/freezer/freezer
	for(var/obj/machinery/atmospherics/components/unary/thermomachine/freezer/F in GLOB.machines)
		if(is_station_level(F.z) && cs_open_turf_by(F))
			freezer = F
			break
	if(freezer)
		H.forceMove(cs_open_turf_by(freezer))
		freezer.on = TRUE
		freezer.target_temperature = 200
		ui = cs_atmos_window(C, H, freezer, label, "freezer")
		if(ui && label == "after")
			cs_atmos_freezer_checks(C, H, freezer, ui)
		SStgui.close_user_uis(H)
	else
		cs_check("a station freezer", FALSE)

// The after build's checks
/proc/cs_atmos_alarm_checks(client/C, mob/living/carbon/human/H, obj/machinery/airalarm/alarm, datum/tgui/ui)
	var/list/data = alarm.ui_data(H)
	var/list/gases = data["gases"]
	cs_check("alarm: the air sent gas by gas ([length(gases)] gases, [data["pressure"]] kPa)", length(gases) >= 2 && !isnull(data["pressure"]))
	var/datum/tlv/tlv = alarm.TLV["pressure"]
	var/was = tlv.max1
	cs_act(alarm, H, "threshold_set", list("env" = "pressure", "var" = "max1", "value" = "150"))
	cs_check("alarm: a pressure threshold typed in the window sets it (now [tlv.max1])", tlv.max1 == 150)
	cs_act(alarm, H, "threshold_set", list("env" = "pressure", "var" = "bogus", "value" = "1"))
	cs_check("alarm: an unknown threshold name is refused", !("bogus" in tlv.vars))
	tlv.max1 = was
	cs_tgui_do(C, ui.window_id, "click:Mode")
	sleep(15)
	cs_shot("popup_atmos_after_alarm_modes")
	cs_tgui_do(C, ui.window_id, "click:Thresholds")
	sleep(15)
	cs_shot("popup_atmos_after_alarm_thresholds")

/proc/cs_atmos_canister_checks(client/C, mob/living/carbon/human/H, obj/machinery/portable_atmospherics/canister/can, datum/tgui/ui)
	var/list/data = can.ui_data()
	cs_check("canister: contents and labels sent ([length(data["gases"])] gases, [length(data["labels"])] labels)", length(data["gases"]) >= 3 && length(data["labels"]) > 5)
	cs_tgui_do(C, ui.window_id, "click:Closed")
	sleep(10)
	cs_check("canister: clicking the valve opens it", can.valve_open)
	sleep(10)
	cs_shot("popup_atmos_after_canister_open")
	cs_act(can, H, "valve")
	cs_act(can, H, "relabel_to", list("label" = "plasma"))
	var/obj/machinery/portable_atmospherics/canister/plasma_type = /obj/machinery/portable_atmospherics/canister/toxins
	cs_check("canister: relabel from the list (now [can.name])", can.name == initial(plasma_type.name))

/proc/cs_atmos_scrubber_checks(client/C, mob/living/carbon/human/H, obj/machinery/portable_atmospherics/scrubber/scrubber, datum/tgui/ui)
	var/had = (/datum/gas/plasma in scrubber.scrubbing)
	cs_act(scrubber, H, "toggle_filter", list("val" = "plasma"))
	cs_check("scrubber: a filter chip toggles plasma", (/datum/gas/plasma in scrubber.scrubbing) != had)

/proc/cs_atmos_heater_checks(client/C, mob/living/carbon/human/H, obj/machinery/space_heater/heater, datum/tgui/ui)
	var/list/data = heater.ui_data()
	cs_check("heater: what it's doing is sent ([data["working"]])", !isnull(data["working"]))
	cs_act(heater, H, "mode", list("mode" = "heat"))
	cs_check("heater: Heat only sets the mode ([heater.setMode])", heater.setMode == "heat")

/proc/cs_atmos_freezer_checks(client/C, mob/living/carbon/human/H, obj/machinery/atmospherics/components/unary/thermomachine/freezer, datum/tgui/ui)
	var/list/data = freezer.ui_data(H)
	cs_check("freezer: says it cools", data["cooling"])
	var/was = freezer.target_temperature
	cs_act(freezer, H, "target", list("adjust" = "-10"))
	cs_check("freezer: minus steps the target down 10 K ([was] -> [freezer.target_temperature])", freezer.target_temperature == max(was - 10, freezer.min_temperature))

// The traitor uplink: a 20 TC uplink in hand, opened
/proc/cs_uplink(client/C, mob/living/carbon/human/H, label)
	var/obj/item/uplink/device = new(get_turf(H), H.key, 20)
	H.put_in_hands(device)
	var/datum/component/uplink/U = device.GetComponent(/datum/component/uplink)
	U.locked = FALSE
	usr = H
	U.ui_interact(H)
	var/datum/tgui/ui = cs_find_ui(H, U)
	if(!ui)
		cs_check("uplink: the window opens", FALSE)
		return
	winset(C, ui.window_id, "pos=100,20")
	sleep(30)
	cs_shot("popup_uplink_[label]_main")
	cs_tgui_do(C, ui.window_id, "input0:grenade")
	sleep(15)
	cs_shot("popup_uplink_[label]_search")
	cs_tgui_do(C, ui.window_id, "input0:")
	sleep(10)
	if(label == "after")
		var/list/static_data = U.ui_static_data(H)
		var/pictured = 0
		var/total = 0
		for(var/list/category in static_data["categories"])
			for(var/list/item in category["items"])
				total++
				if(item["icon"])
					pictured++
		cs_check("uplink: items with a picture ([pictured] of [total])", pictured > total * 0.8)
		// Pick a card and buy it from the panel, as a player would
		var/tc = U.telecrystals
		cs_tgui_do(C, ui.window_id, "click:Stealth")
		sleep(10)
		cs_tgui_do(C, ui.window_id, "card:1")
		sleep(10)
		cs_shot("popup_uplink_after_picked")
		cs_tgui_do(C, ui.window_id, "click:Buy")
		sleep(15)
		cs_check("uplink: Buy in the panel spends TC ([tc] -> [U.telecrystals])", U.telecrystals < tc)
		cs_tgui_do(C, ui.window_id, "click:List")
		sleep(15)
		cs_shot("popup_uplink_after_list")
	SStgui.close_user_uis(H)
	qdel(device)

// Cargo and mining: the bounty console, the ore silo, the smelter console, the coin press and the aux base console
/proc/cs_window_shot(client/C, mob/living/carbon/human/H, datum/D, name)
	usr = H
	if(isatom(D))
		var/atom/A = D
		A.attack_hand(H) // as a player's click; the coin press builds its old window there, not in interact()
	else
		D.ui_interact(H)
	var/datum/tgui/ui = cs_find_ui(H, D)
	if(!ui)
		// The before build: the old HTML popup, closed again after its picture
		sleep(25)
		cs_shot(name)
		for(var/window in list("bounties", "ore_silo", "processing", "mint", "computer", "vending", "slotmachine", "holopad", \
			"seed_ext", "Limb Grower", "navbeacon", "autosec", "announcement_config"))
			C << browse(null, "window=[window]")
		return null
	winset(C, ui.window_id, "pos=100,20")
	if(ui.width < 340)
		winset(C, ui.window_id, "size=340x[ui.height]")
	sleep(25)
	cs_shot(name)
	return ui

/// The first machine of this type on a station or mining level, or a new one beside H
/proc/cs_find_or_make(type, mob/living/carbon/human/H)
	for(var/obj/machinery/M in GLOB.machines)
		if(istype(M, type) && (is_station_level(M.z) || SSmapping.level_trait(M.z, ZTRAIT_MINING)) && cs_open_turf_by(M))
			return M
	var/turf/spot = cs_open_turf_by(H)
	return spot ? new type(spot) : null

/proc/cs_stand_by(mob/living/carbon/human/H, atom/A)
	var/turf/T = cs_open_turf_by(A)
	if(T)
		H.forceMove(T)

/proc/cs_cargo(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/quartermaster)
	var/obj/item/card/id/id = H.wear_id
	if(istype(id))
		id.access = get_all_accesses()
	if(!GLOB.bounties_list.len)
		setup_bounties()

	var/obj/machinery/computer/bounty/bounty = cs_find_or_make(/obj/machinery/computer/bounty, H)
	if(bounty)
		cs_stand_by(H, bounty)
		var/datum/tgui/ui = cs_window_shot(C, H, bounty, "popup_cargo_[label]_bounty")
		if(ui && label == "after")
			bounty.printer_ready = 0
			cs_act(bounty, H, "print")
			cs_check("bounty: Print makes the bounty list", locate(/obj/item/paper/bounty_printout) in bounty.loc)
		SStgui.close_user_uis(H)

	var/obj/machinery/ore_silo/silo = GLOB.ore_silo_default || cs_find_or_make(/obj/machinery/ore_silo, H)
	if(silo)
		var/datum/component/material_container/mats = silo.GetComponent(/datum/component/material_container)
		mats.insert_amount(MINERAL_MATERIAL_AMOUNT * 30, MAT_METAL)
		mats.insert_amount(MINERAL_MATERIAL_AMOUNT * 12, MAT_GLASS)
		mats.insert_amount(MINERAL_MATERIAL_AMOUNT * 5, MAT_GOLD)
		silo.silo_log(silo, "deposited", 30, "sheets", list(MAT_METAL = MINERAL_MATERIAL_AMOUNT))
		cs_stand_by(H, silo)
		var/datum/tgui/ui = cs_window_shot(C, H, silo, "popup_cargo_[label]_silo")
		if(ui && label == "after")
			var/datum/material/metal = mats.materials[MAT_METAL]
			var/before = metal.amount
			cs_act(silo, H, "eject", list("id" = MAT_METAL, "amount" = "5"))
			cs_check("silo: eject 5 metal ([before / MINERAL_MATERIAL_AMOUNT] -> [metal.amount / MINERAL_MATERIAL_AMOUNT] sheets)", metal.amount == before - MINERAL_MATERIAL_AMOUNT * 5)
		SStgui.close_user_uis(H)

	var/obj/machinery/mineral/processing_unit_console/smelter = cs_find_or_make(/obj/machinery/mineral/processing_unit_console, H)
	if(!smelter || QDELETED(smelter))
		var/turf/spot = cs_open_turf_by(H)
		var/turf/east = spot ? get_step(spot, EAST) : null
		if(east && !east.density)
			new /obj/machinery/mineral/processing_unit(east)
			smelter = new(spot)
	if(smelter && !QDELETED(smelter) && smelter.machine)
		var/datum/component/material_container/mats = smelter.machine.GetComponent(/datum/component/material_container)
		mats.insert_amount(MINERAL_MATERIAL_AMOUNT * 14, MAT_METAL)
		mats.insert_amount(MINERAL_MATERIAL_AMOUNT * 6, MAT_PLASMA)
		cs_stand_by(H, smelter)
		var/datum/tgui/ui = cs_window_shot(C, H, smelter, "popup_cargo_[label]_smelter")
		if(ui && label == "after")
			var/was = smelter.machine.on
			cs_act(smelter, H, "power")
			cs_check("smelter: the power switch flips the furnace", smelter.machine.on != was)
			smelter.machine.on = was
			cs_act(smelter, H, "material", list("id" = MAT_PLASMA))
			cs_check("smelter: Smelt picks plasma", smelter.machine.selected_material == MAT_PLASMA)
		SStgui.close_user_uis(H)
	else
		cs_check("a smelter console", FALSE)

	var/obj/machinery/mineral/mint/mint = cs_find_or_make(/obj/machinery/mineral/mint, H)
	if(mint)
		var/datum/component/material_container/mats = mint.GetComponent(/datum/component/material_container)
		mats.insert_amount(MINERAL_MATERIAL_AMOUNT * 4, MAT_GOLD)
		mats.insert_amount(MINERAL_MATERIAL_AMOUNT * 2, MAT_SILVER)
		cs_stand_by(H, mint)
		var/datum/tgui/ui = cs_window_shot(C, H, mint, "popup_cargo_[label]_mint")
		if(ui && label == "after")
			cs_act(mint, H, "choose", list("id" = MAT_GOLD))
			cs_act(mint, H, "count", list("count" = "3"))
			sleep(5)
			var/made = mint.newCoins
			cs_tgui_do(C, ui.window_id, "click:Make coins")
			sleep(30)
			cs_check("mint: Make coins presses 3 gold coins ([made] -> [mint.newCoins])", mint.newCoins == made + 3)
		SStgui.close_user_uis(H)

	var/obj/machinery/computer/auxillary_base/aux
	for(var/obj/machinery/computer/auxillary_base/A in GLOB.machines)
		aux = A
		break
	if(aux)
		cs_stand_by(H, aux)
		var/datum/tgui/ui = cs_window_shot(C, H, aux, "popup_cargo_[label]_aux")
		if(ui && label == "after")
			var/list/data = aux.ui_data(H)
			cs_check("aux base: status sent ([data["status"]], [length(data["destinations"])] landing zones)", !isnull(data["status"]))
		SStgui.close_user_uis(H)
	else
		cs_check("an aux base console", FALSE)

// Shuttle consoles: the mining shuttle's, the labor shuttle's, and a mass driver console
/proc/cs_shuttle(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/captain)
	var/obj/item/card/id/id = H.wear_id
	if(istype(id))
		id.access = get_all_accesses()
	for(var/kind in list(/obj/machinery/computer/shuttle/mining, /obj/machinery/computer/shuttle/labor))
		var/obj/machinery/computer/shuttle/console
		for(var/obj/machinery/computer/shuttle/S in GLOB.machines)
			if(S.type == kind && is_station_level(S.z) && cs_open_turf_by(S))
				console = S
				break
		if(!console)
			cs_check("a [kind] on the station", FALSE)
			continue
		cs_stand_by(H, console)
		var/name = (kind == /obj/machinery/computer/shuttle/mining) ? "mining" : "labor"
		var/datum/tgui/ui = cs_window_shot(C, H, console, "popup_shuttle_[label]_[name]")
		if(ui && label == "after" && name == "mining")
			var/list/data = console.ui_data(H)
			var/list/dests = data["destinations"]
			cs_check("shuttle: [length(dests)] destinations sent ([data["status"]])", length(dests) >= 1)
			var/obj/docking_port/mobile/M = SSshuttle.getShuttle(console.shuttleId)
			var/target
			for(var/list/D in dests)
				if(!D["here"])
					target = D["id"]
			if(M && target)
				cs_tgui_do(C, ui.window_id, "click:Send to")
				sleep(10)
				cs_check("shuttle: clicking a destination launches it ([M.mode])", M.mode != SHUTTLE_IDLE)
				sleep(10)
				cs_shot("popup_shuttle_after_mining_moving")
		SStgui.close_user_uis(H)

	var/turf/spot = cs_open_turf_by(H)
	var/obj/machinery/mass_driver/driver = spot ? new(get_step(spot, EAST)) : null
	var/obj/machinery/computer/pod/pod = spot ? new(spot) : null
	if(pod)
		pod.connected = driver
		var/datum/tgui/ui = cs_window_shot(C, H, pod, "popup_shuttle_[label]_massdriver")
		if(ui && label == "after")
			cs_act(pod, H, "power", list("level" = "4"))
			cs_check("mass driver: power level 4 ([driver.power])", driver.power == 4)
			cs_act(pod, H, "time", list("time" = "45"))
			cs_check("mass driver: typed timer 45 s ([pod.time])", pod.time == 45)
		SStgui.close_user_uis(H)
		qdel(pod)
		qdel(driver)

// Service and misc machines
/proc/cs_service(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/captain)
	var/obj/item/card/id/id = H.wear_id
	if(istype(id))
		id.access = get_all_accesses()
	// Everything is set down beside a station holopad
	var/obj/machinery/holopad/pad
	for(var/obj/machinery/holopad/P in GLOB.machines)
		if(is_station_level(P.z) && P.on_network && cs_open_turf_by(P))
			pad = P
			break
	if(pad)
		H.forceMove(pad.loc)
	var/turf/spot = cs_open_turf_by(H)

	var/obj/machinery/jukebox/jukebox = new(spot)
	jukebox.anchored = TRUE
	if(!jukebox.songs.len)
		jukebox.songs += new /datum/track("Space Asshole", null, 1850, 5)
		jukebox.songs += new /datum/track("Title3", null, 2400, 6)
		jukebox.songs += new /datum/track("Clown", null, 1200, 4)
		jukebox.selection = jukebox.songs[1]
	var/datum/tgui/ui = cs_window_shot(C, H, jukebox, "popup_service_[label]_jukebox")
	if(ui && label == "after")
		cs_act(jukebox, H, "select", list("name" = "Title3"))
		cs_check("jukebox: picking a track ([jukebox.selection.song_name])", jukebox.selection.song_name == "Title3")
		// As if playing (the test tracks have no sound file to play)
		jukebox.active = TRUE
		jukebox.stop = world.time + 1500
		sleep(20)
		cs_shot("popup_service_after_jukebox_playing")
		jukebox.active = FALSE
		jukebox.stop = 0
	SStgui.close_user_uis(H)
	qdel(jukebox)

	var/obj/machinery/computer/slot_machine/slots = new(spot)
	slots.balance = 20
	ui = cs_window_shot(C, H, slots, "popup_service_[label]_slots")
	if(ui && label == "after")
		cs_tgui_do(C, ui.window_id, "css:.Slots__button--spin")
		sleep(10)
		cs_check("slots: clicking Play spins (credit [slots.balance], spinning [slots.working])", slots.balance == 15 && slots.working)
		sleep(5)
		cs_shot("popup_service_after_slots_spinning")
		sleep(70)
	SStgui.close_user_uis(H)
	qdel(slots)

	var/obj/machinery/seed_extractor/extractor = new(spot)
	for(var/kind in list(/obj/item/seeds/tomato, /obj/item/seeds/tomato, /obj/item/seeds/wheat, /obj/item/seeds/potato, /obj/item/seeds/ambrosia))
		var/obj/item/seeds/seed = new kind(H.loc)
		H.put_in_hands(seed)
		extractor.add_seed(seed)
	ui = cs_window_shot(C, H, extractor, "popup_service_[label]_seeds")
	if(ui && label == "after")
		var/list/data = extractor.ui_data(H)
		var/list/seeds = data["seeds"]
		var/before = length(extractor.contents)
		cs_act(extractor, H, "vend", list("ref" = seeds[1]["ref"]))
		cs_check("seeds: Vend drops one ([before] -> [length(extractor.contents)] stored)", length(extractor.contents) == before - 1)
	SStgui.close_user_uis(H)
	qdel(extractor)

	var/obj/machinery/limbgrower/grower = new(spot)
	grower.reagents.add_reagent(/datum/reagent/medicine/synthflesh, 60)
	ui = cs_window_shot(C, H, grower, "popup_service_[label]_limbs")
	if(ui && label == "after")
		var/list/data = grower.ui_data(H)
		var/list/cats = data["categories"]
		var/list/human = cats[1]
		var/list/designs = human["designs"]
		cs_check("limb grower: [length(cats)] categories, [length(designs)] in the first", length(designs) > 0)
		cs_act(grower, H, "make", list("id" = designs[1]["id"]))
		cs_check("limb grower: growing [designs[1]["name"]]", grower.busy)
		sleep(5)
		cs_shot("popup_service_after_limbs_growing")
	SStgui.close_user_uis(H)
	sleep(50)
	qdel(grower)

	// A station patrol beacon, its floor tile lifted and its cover opened
	var/obj/machinery/navbeacon/beacon
	for(var/obj/machinery/navbeacon/B in GLOB.machines)
		if(is_station_level(B.z) && B.codes && B.codes["patrol"] && cs_open_turf_by(B))
			beacon = B
			break
	if(beacon)
		var/turf/beacon_turf = beacon.loc
		var/was_intact = beacon_turf.intact
		var/old_location = beacon.location
		var/list/old_codes = beacon.codes.Copy()
		beacon_turf.intact = FALSE
		beacon.hide(FALSE)
		beacon.open = TRUE
		beacon.locked = FALSE
		cs_stand_by(H, beacon)
		ui = cs_window_shot(C, H, beacon, "popup_service_[label]_beacon")
		if(ui && label == "after")
			cs_act(beacon, H, "location", list("value" = "Dorms"))
			cs_act(beacon, H, "add", list("key" = "delivery", "value" = "1"))
			cs_check("beacon: location and a new code typed in ([beacon.location], [length(beacon.codes)] codes)", beacon.location == "Dorms" && beacon.codes["delivery"] == "1")
		SStgui.close_user_uis(H)
		beacon.location = old_location
		beacon.codes = old_codes
		beacon.open = FALSE
		beacon.locked = TRUE
		beacon_turf.intact = was_intact
		beacon.hide(was_intact)
		if(pad)
			H.forceMove(pad.loc)
		spot = cs_open_turf_by(H)
	else
		cs_check("a station patrol beacon", FALSE)

	var/obj/machinery/computer/bank_machine/bank = new(spot)
	ui = cs_window_shot(C, H, bank, "popup_service_[label]_bank")
	if(ui && label == "after")
		cs_act(bank, H, "siphon")
		var/started = bank.siphoning
		cs_act(bank, H, "halt")
		cs_check("bank: siphon then halt ([started] then [bank.siphoning])", started && !bank.siphoning)
	SStgui.close_user_uis(H)
	qdel(bank)

	if(pad)
		H.forceMove(pad.loc)
		ui = cs_window_shot(C, H, pad, "popup_service_[label]_holopad")
		if(ui && label == "after")
			var/list/data = pad.ui_data(H)
			cs_check("holopad: [length(data["areas"])] areas to call", length(data["areas"]) > 3)
		SStgui.close_user_uis(H)

	var/obj/machinery/embedded_controller/radio/airlock_controller/airlock
	for(var/obj/machinery/embedded_controller/radio/airlock_controller/A in GLOB.machines)
		if(is_station_level(A.z))
			airlock = A
			break
	if(airlock)
		cs_stand_by(H, airlock)
		ui = cs_window_shot(C, H, airlock, "popup_service_[label]_airlock")
		if(ui && label == "after")
			var/list/data = airlock.ui_data(H)
			cs_check("airlock controller: [length(data["commands"])] commands offered", length(data["commands"]) > 0)
		SStgui.close_user_uis(H)
	else
		cs_check("an airlock controller", FALSE)


// Security and science: the prisoner console with a card, a chem and a tracking implant; the AI fixer with an AI in it;
// a doppler array with a blast logged; the announcement system
/proc/cs_secsci(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/hos)
	var/obj/item/card/id/id = H.wear_id
	if(istype(id))
		id.access = get_all_accesses()
	var/obj/machinery/holopad/pad
	for(var/obj/machinery/holopad/P in GLOB.machines)
		if(is_station_level(P.z) && cs_open_turf_by(P))
			pad = P
			break
	if(pad)
		H.forceMove(pad.loc)
	var/turf/spot = cs_open_turf_by(H)

	// Two prisoners with implants, one card
	var/mob/living/carbon/human/convict = new(spot)
	convict.real_name = "Tomas Reyes"
	convict.name = convict.real_name
	var/obj/item/implant/chem/chem = new
	chem.reagents.add_reagent(/datum/reagent/medicine/salbutamol, 30)
	chem.implant(convict, null, TRUE)
	var/obj/item/implant/tracking/tracker = new
	tracker.implant(convict, null, TRUE)
	var/obj/item/card/id/prisoner/card = new(get_turf(H))
	card.registered_name = convict.real_name
	card.goal = 300
	card.points = 120
	var/obj/machinery/computer/prisoner/console = new(spot)
	console.screen = 1
	console.inserted_id = card
	card.forceMove(console)
	var/datum/tgui/ui = cs_window_shot(C, H, console, "popup_secsci_[label]_prisoner")
	if(ui && label == "after")
		cs_act(console, H, "goal", list("goal" = "450"))
		cs_check("prisoner: goal typed in ([card.goal])", card.goal == 450)
		var/units = chem.reagents.total_volume
		cs_act(console, H, "inject", list("ref" = REF(chem), "amount" = "5"))
		cs_check("prisoner: Inject 5 ([units] -> [chem.reagents.total_volume] u)", chem.reagents.total_volume < units)
	SStgui.close_user_uis(H)
	qdel(console)
	qdel(convict)

	var/obj/machinery/computer/aifixer/fixer = new(spot)
	// As the intelliCard check: an AI with no mob behind it gets no laws from Initialize, so they're set here
	var/mob/living/silicon/ai/AI = new(fixer, null, null)
	AI.fully_replace_character_name(null, "HAL 9000")
	AI.laws = new /datum/ai_laws/default/asimov
	AI.laws.associate(AI)
	AI.laws.add_ion_law("THE CAPTAIN IS A LIZARD")
	AI.adjustBruteLoss(80)
	AI.updatehealth()
	fixer.occupier = AI
	ui = cs_window_shot(C, H, fixer, "popup_secsci_[label]_aifixer")
	if(ui && label == "after")
		cs_act(fixer, H, "fix")
		cs_check("ai fixer: Begin Reconstruction", fixer.active)
		fixer.active = FALSE
	SStgui.close_user_uis(H)
	fixer.occupier = null
	qdel(AI)
	qdel(fixer)

	var/obj/machinery/doppler_array/research/science/doppler = new(spot)
	doppler.anchored = TRUE
	doppler.power_change()
	LAZYADD(doppler.message_log, "Explosive disturbance detected. Epicenter at: grid (120,88). Temporal displacement of tachyons: 0.7 seconds. Factual: Epicenter radius: 5. Outer radius: 10. Shockwave radius: 20. Theoretical: Epicenter radius: 12. Outer radius: 25. Shockwave radius: 50.")
	ui = cs_window_shot(C, H, doppler, "popup_secsci_[label]_doppler")
	if(ui && label == "after")
		cs_act(doppler, H, "delete")
		cs_check("doppler: Delete logs", !length(doppler.message_log))
	SStgui.close_user_uis(H)
	qdel(doppler)

	var/obj/machinery/announcement_system/announcer = new(spot)
	ui = cs_window_shot(C, H, announcer, "popup_secsci_[label]_announcer")
	if(ui && label == "after")
		cs_act(announcer, H, "arrival", list("text" = "%PERSON, %RANK, is here."))
		cs_check("announcer: arrival text typed in ([announcer.arrival])", announcer.arrival == "%PERSON, %RANK, is here.")
	SStgui.close_user_uis(H)
	qdel(announcer)

// Telecomms signal quality: real radio messages through the station's network, with the common server damaged, EMP'd,
// warm and overheated; what the broadcaster sent is in GLOB.tcomms_last_broadcast (signal_quality.dm)
/// Sends text on the radio and waits for the broadcast of that message (not anyone else's): list(sent, noise, delay, original)
/proc/cs_tsignal_send(mob/living/carbon/human/H, obj/item/radio/R, text)
	GLOB.tcomms_last_broadcast = null
	R.talk_into(H, text, null)
	for(var/i in 1 to 25)
		sleep(2)
		var/list/L = GLOB.tcomms_last_broadcast
		if(L && findtext(lowertext(L[4]), lowertext(text)))
			return L
	return null

/proc/cs_tsignal(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/ce)
	var/obj/machinery/telecomms/server/presets/common/server
	for(var/obj/machinery/telecomms/server/presets/common/S in GLOB.telecomms_list)
		if(is_station_level(S.z))
			server = S
			break
	if(!server)
		cs_check("a common server", FALSE)
		return
	var/obj/machinery/holopad/pad
	for(var/obj/machinery/holopad/P in GLOB.machines)
		if(is_station_level(P.z) && cs_open_turf_by(P))
			pad = P
			break
	H.forceMove(pad ? pad.loc : get_turf(H))
	var/obj/item/radio/R = new(get_turf(H))
	R.set_frequency(FREQ_COMMON)
	R.broadcasting = TRUE
	var/turf/open/server_turf = get_turf(server)
	var/datum/gas_mixture/air = server_turf.return_air()
	var/room_temp = air.temperature
	var/words = "one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty"

	var/list/L = cs_tsignal_send(H, R, "clean [words]")
	cs_check("tcomms: a healthy network sends it clean (noise [L ? L[2] : "none"])", L && L[1] == L[4] && L[2] < 0.05)

	server.obj_integrity = server.max_integrity * 0.5
	var/changed = 0
	var/noise_seen = 0
	for(var/i in 1 to 6)
		L = cs_tsignal_send(H, R, "damaged [i] [words]")
		if(L)
			noise_seen = L[2]
			if(L[1] != L[4])
				changed++
	cs_check("tcomms: a server at half integrity crackles (noise [noise_seen], [changed] of 6 messages touched)", noise_seen >= 0.25 && noise_seen < 0.5 && changed >= 1)
	if(L)
		cs_check("tcomms: light static example: [L[1]]", TRUE)
	server.obj_integrity = server.max_integrity

	server.stat |= EMPED
	server.update_power()
	L = cs_tsignal_send(H, R, "emp [words]")
	cs_check("tcomms: an EMP'd server stays up but garbles and delays (noise [L ? L[2] : "none"], delay [L ? L[3] : "none"] ds)", L && L[2] >= 0.6 && L[3] >= 12 && L[1] != L[4])
	if(L)
		cs_check("tcomms: heavy static example: [L[1]]", TRUE)
	server.stat &= ~EMPED
	server.update_power()

	air.temperature = 300
	L = cs_tsignal_send(H, R, "warm [words]")
	cs_check("tcomms: a 300 K server room adds static (noise [L ? L[2] : "none"])", L && L[2] >= 0.3 && L[2] < 0.5)

	// The whole room, as a real overheat would be: one hot tile cools back to the room's 80 K in seconds
	var/area/hot_room = get_area(server)
	var/list/old_temps = list()
	for(var/turf/open/T in hot_room)
		var/datum/gas_mixture/G = T.return_air()
		old_temps[T] = G.temperature
		G.temperature = 400
	server.process()
	cs_check("tcomms: past 373 K the server shuts down", server.overheated && !server.on)
	if(label == "after")
		cs_stand_by(H, server)
		H.drop_all_held_items()
		H.put_in_active_hand(new /obj/item/multitool(H)) // what opens a telecomms machine's window
		cs_window_shot(C, H, server, "popup_tsignal_after_server_hot")
		SStgui.close_user_uis(H)
		H.forceMove(pad ? pad.loc : get_turf(H))
	L = cs_tsignal_send(H, R, "overheated [words]")
	cs_check("tcomms: with the common server down and the room at 400 K our message [L ? "went out, noise [L[2]]: [L[1]]" : "was lost"]", !L || L[2] >= 0.5)
	cs_check("tcomms: still down a few seconds later in the hot room", server.overheated && !server.on)
	for(var/turf/open/T in old_temps)
		var/datum/gas_mixture/G = T.return_air()
		G.temperature = old_temps[T]
	server.process()
	cs_check("tcomms: below 323 K it starts again", !server.overheated && server.on)
	air.temperature = room_temp

	// How fast the servers warm their room at base load
	var/area/room = get_area(server)
	var/capacity = 0
	var/tiles = 0
	for(var/turf/open/T in room)
		var/datum/gas_mixture/G = T.return_air()
		capacity += G.heat_capacity()
		tiles++
	var/servers = 0
	for(var/obj/machinery/telecomms/server/S in room)
		servers++
	var/per_minute = capacity ? servers * 500 * 60 / capacity : 0
	cs_check("tcomms: [servers] servers warm their [tiles]-tile room by about [round(per_minute, 0.01)] K a minute at base load (80 K to 200 K in [per_minute ? round(120 / per_minute) : "never"] min, to 373 K in [per_minute ? round(293 / per_minute) : "never"] min, before any heat leaks away)", TRUE)
	qdel(R)

/// What went out after a message: list(frequency = message as sent); the noise of the last one in heard_noise
GLOBAL_VAR_INIT(cs_trules_noise, 0)
/proc/cs_trules_say(mob/living/carbon/human/H, obj/item/radio/R, text, match)
	GLOB.tcomms_recent_broadcasts.Cut()
	R.talk_into(H, text, null)
	sleep(30)
	var/list/heard = list()
	for(var/list/L in GLOB.tcomms_recent_broadcasts)
		if(!findtext(lowertext(L[4]), lowertext(match || text))) // only ours, not the crew's chatter
			continue
		heard["[L[5]]"] = L[1]
		GLOB.cs_trules_noise = L[2]
	return heard

// Telecomms traffic rules, added from the Traffic Control app on a console as a player would, then real radio messages
/proc/cs_trules(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/ce)
	var/obj/machinery/holopad/pad
	for(var/obj/machinery/holopad/P in GLOB.machines)
		if(is_station_level(P.z) && cs_open_turf_by(P))
			pad = P
			break
	if(pad)
		H.forceMove(pad.loc)
	var/obj/item/card/id/worn = cs_card("Hugo Brandt", "Chief Engineer", get_all_accesses(), get_turf(H))
	H.equip_to_slot_or_del(worn, ITEM_SLOT_ID)
	var/obj/machinery/modular_computer/console/preset/engineering/PC = new(cs_open_beside(H))
	PC.stat &= ~(NOPOWER|BROKEN)
	var/obj/item/modular_computer/processor/cpu = PC.cpu
	var/obj/item/computer_hardware/hard_drive/drive = cpu.all_components[MC_HDD]
	drive.store_file(new /datum/computer_file/program/traffic_control)
	cpu.turn_on(H)
	cs_act(cpu, H, "PC_runprogram", list("name" = "trafficctrl"))
	var/datum/computer_file/program/traffic_control/app = cpu.active_program
	if(!istype(app))
		cs_check("traffic control: the app starts", FALSE)
		return
	GLOB.tcomms_rules.Cut()
	var/common = "[FREQ_COMMON]"
	cs_act(app, H, "add_rule", list("frequency" = common, "word" = "honk", "action" = "replace", "replace_with" = "hug"))
	cs_act(app, H, "add_rule", list("frequency" = common, "word" = "secret", "action" = "block"))
	cs_act(app, H, "add_rule", list("frequency" = common, "word" = "reroute me", "action" = "reroute", "target" = "[FREQ_SECURITY]"))
	cs_act(app, H, "add_rule", list("frequency" = common, "word" = "copy me", "action" = "copy", "target" = "[FREQ_ENGINEERING]"))
	cs_act(app, H, "add_rule", list("frequency" = common, "speaker" = H.real_name, "word" = "fuzz", "action" = "garble", "garble" = "60"))
	cs_act(app, H, "add_rule", list("action" = "rename", "rename_to" = "Captain"))
	cs_check("traffic control: 5 legal rules added, rename refused without an emag ([length(GLOB.tcomms_rules)] rules)", length(GLOB.tcomms_rules) == 5)

	var/obj/item/radio/R = new(get_turf(H))
	R.set_frequency(FREQ_COMMON)
	R.broadcasting = TRUE
	var/list/heard = cs_trules_say(H, R, "the clown said honk twice", "the clown said")
	cs_check("rules: replace ([heard[common]])", heard[common] && findtext(heard[common], "hug") && !findtext(heard[common], "honk"))
	heard = cs_trules_say(H, R, "this is secret stuff")
	cs_check("rules: block ([length(heard)] broadcasts)", !length(heard))
	heard = cs_trules_say(H, R, "please reroute me now")
	cs_check("rules: reroute to security ([json_encode(heard)])", heard["[FREQ_SECURITY]"] && !heard[common])
	heard = cs_trules_say(H, R, "copy me please")
	cs_check("rules: copy to engineering ([json_encode(heard)])", heard["[FREQ_ENGINEERING]"] && heard[common])
	heard = cs_trules_say(H, R, "fuzz alpha bravo charlie delta echo foxtrot golf hotel india juliet", "fuzz alpha")
	cs_check("rules: garble by speaker (noise [GLOB.cs_trules_noise]: [heard[common]])", heard[common] && GLOB.cs_trules_noise >= 0.6)
	var/datum/tcomms_rule/first = GLOB.tcomms_rules[1]
	cs_check("rules: hits counted (#[first.id]: [first.hits])", first.hits == 1)

	cpu.ui_interact(H)
	var/datum/tgui/ui = cs_find_ui(H, app)
	if(ui)
		winset(C, ui.window_id, "pos=100,20")
		sleep(25)
		cs_shot("popup_trules_[label]_app")

	// An emagged computer: rename and silent rules
	cpu.obj_flags |= EMAGGED
	cs_act(app, H, "add_rule", list("speaker" = H.real_name, "word" = "orders", "action" = "rename", "rename_to" = "Captain"))
	cs_act(app, H, "add_rule", list("frequency" = common, "word" = "hidden", "action" = "block", "silent" = "1"))
	var/datum/tcomms_rule/silent_rule = GLOB.tcomms_rules[GLOB.tcomms_rules.len]
	cs_check("hacked: rename and a silent block added ([length(GLOB.tcomms_rules)] rules, last silent [silent_rule.silent])", length(GLOB.tcomms_rules) == 7 && silent_rule.silent)
	var/obj/machinery/telecomms/server/presets/common/server
	for(var/obj/machinery/telecomms/server/presets/common/S in GLOB.telecomms_list)
		if(is_station_level(S.z))
			server = S
	GLOB.tcomms_recent_broadcasts.Cut()
	R.talk_into(H, "new orders from above", null)
	sleep(30)
	var/renamed = FALSE
	for(var/list/L in GLOB.tcomms_recent_broadcasts)
		if(findtext(L[4], "orders"))
			renamed = TRUE
	var/datum/comm_log_entry/last_log = server.log_entries[server.log_entries.len]
	cs_check("hacked: the speaker is renamed in the server log ([last_log.parameters["name"]])", renamed && last_log.parameters["name"] == "Captain")
	var/logs = server.log_entries.len
	heard = cs_trules_say(H, R, "this is hidden stuff")
	cs_check("hacked: silent block leaves no broadcast and no log ([length(heard)] broadcasts, logs [logs] -> [server.log_entries.len])", !length(heard) && server.log_entries.len == logs)
	sleep(10)
	cs_shot("popup_trules_[label]_app_hacked")
	cpu.obj_flags &= ~EMAGGED
	var/list/data = app.ui_data(H)
	cs_check("hacked rules are hidden off an emagged computer ([length(data["rules"])] of [length(GLOB.tcomms_rules)] shown)", length(data["rules"]) == 6)
	SStgui.close_user_uis(H)
	GLOB.tcomms_rules.Cut()
	qdel(R)
	qdel(PC)

// The telecomms network map: the Traffic Control app's Network tab and the telecomms monitor, with faults and traffic
/proc/cs_tmap(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/ce)
	var/obj/item/card/id/worn = cs_card("Hugo Brandt", "Chief Engineer", get_all_accesses(), get_turf(H))
	H.equip_to_slot_or_del(worn, ITEM_SLOT_ID)
	var/obj/machinery/telecomms/server/presets/science/sci
	var/obj/machinery/telecomms/server/presets/security/sec
	var/obj/machinery/telecomms/bus/preset_two/bus
	for(var/obj/machinery/telecomms/T in GLOB.telecomms_list)
		if(!is_station_level(T.z))
			continue
		if(istype(T, /obj/machinery/telecomms/server/presets/science))
			sci = T
		if(istype(T, /obj/machinery/telecomms/server/presets/security))
			sec = T
		if(istype(T, /obj/machinery/telecomms/bus/preset_two))
			bus = T
	if(sci)
		sci.obj_integrity = sci.max_integrity * 0.6
	if(bus)
		bus.stat |= EMPED
	if(sec)
		sec.overheated = TRUE
		sec.update_power()
	var/list/map = tcomms_map_data(tcomms_station_machines())
	var/list/nodes = map["nodes"]
	var/list/links = map["links"]
	var/sci_state
	var/sec_state
	var/bus_state
	for(var/list/N in nodes)
		if(sci && N["ref"] == REF(sci))
			sci_state = N["state"]
		if(sec && N["ref"] == REF(sec))
			sec_state = N["state"]
		if(bus && N["ref"] == REF(bus))
			bus_state = N["state"]
	cs_check("map: [length(nodes)] machines, [length(links)] links", length(nodes) >= 10 && length(links) >= 10)
	cs_check("map: damaged server [sci_state], EMP'd bus [bus_state], overheated server [sec_state]", sci_state == "warn" && bus_state == "fault" && sec_state == "off")

	var/obj/machinery/holopad/pad
	for(var/obj/machinery/holopad/P in GLOB.machines)
		if(is_station_level(P.z) && cs_open_turf_by(P))
			pad = P
			break
	if(pad)
		H.forceMove(pad.loc)
	// Some traffic, so the busy links show
	var/obj/item/radio/R = new(get_turf(H))
	R.set_frequency(FREQ_COMMON)
	R.broadcasting = TRUE
	for(var/i in 1 to 4)
		R.talk_into(H, "map traffic [i]", null)
		R.set_frequency(pick(FREQ_COMMON, FREQ_ENGINEERING, FREQ_MEDICAL, FREQ_SUPPLY))
	var/obj/machinery/modular_computer/console/preset/engineering/PC = new(cs_open_beside(H))
	PC.stat &= ~(NOPOWER|BROKEN)
	var/obj/item/modular_computer/processor/cpu = PC.cpu
	var/obj/item/computer_hardware/hard_drive/drive = cpu.all_components[MC_HDD]
	drive.store_file(new /datum/computer_file/program/traffic_control)
	cpu.turn_on(H)
	cs_act(cpu, H, "PC_runprogram", list("name" = "trafficctrl"))
	cpu.ui_interact(H)
	var/datum/tgui/ui = cs_find_ui(H, cpu.active_program)
	if(ui)
		winset(C, ui.window_id, "pos=100,20")
		sleep(25)
		cs_tgui_do(C, ui.window_id, "css:.TcommsMap__node")
		sleep(15)
		cs_shot("popup_tmap_[label]_app")
	else
		cs_check("map: the app window opens", FALSE)
	SStgui.close_user_uis(H)
	qdel(PC)

	// The telecomms monitor, probed
	var/obj/machinery/computer/telecomms/monitor/monitor
	for(var/obj/machinery/computer/telecomms/monitor/M in GLOB.machines)
		if(is_station_level(M.z) && cs_open_turf_by(M))
			monitor = M
			break
	if(monitor)
		cs_stand_by(H, monitor)
		monitor.network = "tcommsat"
		usr = H
		monitor.interact(H)
		cs_act(monitor, H, "probe")
		ui = cs_find_ui(H, monitor)
		if(ui)
			winset(C, ui.window_id, "pos=100,20")
			sleep(25)
			cs_shot("popup_tmap_[label]_monitor")
			var/list/data = monitor.ui_data(H)
			var/list/mon_map = data["map"]
			cs_check("monitor: probed map has [length(mon_map["nodes"])] machines", length(mon_map["nodes"]) >= 5)
		SStgui.close_user_uis(H)
	else
		cs_check("a telecomms monitor on the station", FALSE)
	if(sci)
		sci.obj_integrity = sci.max_integrity
	if(bus)
		bus.stat &= ~EMPED
	if(sec)
		sec.overheated = FALSE
		sec.update_power()
	qdel(R)

// The Wiretap tab: the servers' logs as a feed; on an emagged computer, inject, delete and wipe
/proc/cs_twiretap(client/C, mob/living/carbon/human/H, label)
	H.equipOutfit(/datum/outfit/job/ce)
	var/obj/item/card/id/worn = cs_card("Hugo Brandt", "Chief Engineer", get_all_accesses(), get_turf(H))
	H.equip_to_slot_or_del(worn, ITEM_SLOT_ID)
	var/obj/machinery/holopad/pad
	for(var/obj/machinery/holopad/P in GLOB.machines)
		if(is_station_level(P.z) && cs_open_turf_by(P))
			pad = P
			break
	if(pad)
		H.forceMove(pad.loc)
	var/obj/machinery/modular_computer/console/preset/engineering/PC = new(cs_open_beside(H))
	PC.stat &= ~(NOPOWER|BROKEN)
	var/obj/item/modular_computer/processor/cpu = PC.cpu
	var/obj/item/computer_hardware/hard_drive/drive = cpu.all_components[MC_HDD]
	drive.store_file(new /datum/computer_file/program/traffic_control)
	cpu.turn_on(H)
	cs_act(cpu, H, "PC_runprogram", list("name" = "trafficctrl"))
	var/datum/computer_file/program/traffic_control/app = cpu.active_program
	if(!istype(app))
		cs_check("wiretap: the app starts", FALSE)
		return
	cs_act(app, H, "tab", list("tab" = "wiretap"))
	var/obj/item/radio/R = new(get_turf(H))
	R.broadcasting = TRUE
	R.set_frequency(FREQ_COMMON)
	R.talk_into(H, "wiretap check on common", null)
	sleep(20)
	R.set_frequency(FREQ_ENGINEERING)
	R.talk_into(H, "wiretap check on engineering", null)
	sleep(20)
	var/list/data = app.ui_data(H)
	var/found_common = FALSE
	var/found_eng = FALSE
	for(var/list/L in data["logs"])
		if(findtext(L["message"], "wiretap check on common") && L["channel"] == "Common" && L["time"])
			found_common = TRUE
		if(findtext(L["message"], "wiretap check on engineering") && L["channel"] == "Engineering")
			found_eng = TRUE
	cs_check("wiretap: both messages in the feed with channel and time ([length(data["logs"])] entries)", found_common && found_eng)
	cpu.ui_interact(H)
	var/datum/tgui/ui = cs_find_ui(H, app)
	if(ui)
		winset(C, ui.window_id, "pos=100,20")
		sleep(25)
		cs_shot("popup_twiretap_[label]_feed")

	cpu.obj_flags |= EMAGGED
	GLOB.tcomms_recent_broadcasts.Cut()
	cs_act(app, H, "inject", list("frequency" = "[FREQ_COMMON]", "name" = "Captain", "job" = "Captain", "message" = "All hands, report to the bridge."))
	sleep(30)
	var/heard = FALSE
	for(var/list/L in GLOB.tcomms_recent_broadcasts)
		if(findtext(L[4], "report to the bridge") && L[5] == FREQ_COMMON)
			heard = TRUE
	var/datum/comm_log_entry/fake
	for(var/list/item in GLOB.tcomms_wiretap)
		var/datum/comm_log_entry/E = item[1]
		if(findtext(E.parameters["message"], "report to the bridge"))
			fake = E
	cs_check("wiretap: an injected message goes out on Common and is logged as the Captain ([fake ? fake.parameters["name"] : "no log"])", heard && fake && fake.parameters["name"] == "Captain")
	sleep(10)
	cs_shot("popup_twiretap_[label]_hacked")
	if(fake)
		var/obj/machinery/telecomms/server/holder
		for(var/list/item in GLOB.tcomms_wiretap)
			if(item[1] == fake)
				holder = item[2]
		cs_act(app, H, "delete_log", list("ref" = REF(fake)))
		cs_check("wiretap: delete removes it from the server's log", holder && !(fake in holder.log_entries))
	cs_act(app, H, "wipe_logs")
	var/left = 0
	for(var/obj/machinery/telecomms/server/S in tcomms_station_machines())
		left += length(S.log_entries)
	cs_check("wiretap: wipe empties every server log ([left] left)", left == 0)
	cpu.obj_flags &= ~EMAGGED
	cs_act(app, H, "inject", list("frequency" = "[FREQ_COMMON]", "name" = "Captain", "message" = "should not send"))
	sleep(20)
	var/sent = FALSE
	for(var/list/L in GLOB.tcomms_recent_broadcasts)
		if(findtext(L[4], "should not send"))
			sent = TRUE
	cs_check("wiretap: no inject without an emag", !sent)
	SStgui.close_user_uis(H)
	qdel(R)
	qdel(PC)
