// Stage 2 with a real admin client (the user's tooling plan, 2026-11-07): the player's Ask for help form and ticket window, the
// Tickets window (conversation, notes only admins see, quoted lines into a Ban or Note, kills judged for admins, the map of
// where everyone was), the alert feed, the player profile, the mentors' Questions, and the history kept across rounds. The
// page's own buttons are clicked, then what that did is checked on the server. Not part of the game:
//   HARNESS=stage2_check.dm SENDER=shot.ps1 tools/keybind_check/run.sh stage2
// Results in data/keycheck_stage2.txt, pictures in data/previews/popup_stage2_*.png. Its bans, notes, connections, saved
// replies, mutes and history go to data/stage2_check/, never data/notes.json and the rest.
// One client only (DreamSeeker is one per machine): the admin asks too, so a mentor's PM to a player isn't covered here.

GLOBAL_VAR_INIT(keycheck_running, FALSE)

/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

GLOBAL_VAR_INIT(s2_cleared, FALSE)

/datum/controller/subsystem/bans/load()
	if(!GLOB.s2_cleared)
		GLOB.s2_cleared = TRUE
		fdel("data/stage2_check/")
	ledger_path = "data/stage2_check/bans.json"
	seen_path = "data/stage2_check/connections.json"
	seen_loaded = FALSE
	return ..()

/datum/controller/subsystem/notes/load()
	ledger_path = "data/stage2_check/notes.json"
	return ..()

/proc/kc_log(text)
	text2file(text, "data/keycheck.txt")

/client/New()
	. = ..()
	if(. && !GLOB.keycheck_running)
		GLOB.keycheck_running = TRUE
		spawn(50)
			stage2_check_run(src)

/proc/s2_check(name, ok, detail = "")
	kc_log("[ok ? "PASS" : "FAIL"] [name][detail ? " ([detail])" : ""]")

/proc/s2_shot(name)
	fdel("data/keycheck_shot_title")
	text2file("popup_stage2_[name]", "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/proc/s2_ui(mob/user, datum/src_object)
	var/deadline = world.time + 15 SECONDS
	while(world.time < deadline)
		for(var/datum/tgui/open as anything in user.open_uis)
			if(open.src_object == src_object && open.initialized)
				return open
		sleep(2)

/proc/s2_close(mob/user, datum/src_object)
	for(var/datum/tgui/open as anything in user.open_uis)
		if(open.src_object == src_object)
			open.close()
	sleep(5)

/// One thing done on the page, then a second. "click:<text>" presses the first button whose text starts with it;
/// "pick:<css>|<text>" clicks the first element matching css whose text starts with text; "pickin:<css>|<inner css>|<container
/// text>|<text>" the same inside the first container that has container text; "textarea:<text>" fills the first box of text;
/// "type<N>:<text>" types in the Nth one-line box and leaves it; "ctrlenter" presses Ctrl+Enter in the box of text.
/proc/s2_do(client/C, datum/tgui/ui, action)
	var/js
	if(findtext(action, "click:") == 1)
		js = "var t=[json_encode(copytext(action, 7))];var b=Array.prototype.slice.call(document.querySelectorAll('.Button')).filter(function(e){return e.textContent.trim().indexOf(t)===0;})\[0\];if(b){b.click();}"
	else if(findtext(action, "pick:") == 1)
		var/list/bits = splittext(copytext(action, 6), "|")
		js = "var t=[json_encode(bits[2])];var b=Array.prototype.slice.call(document.querySelectorAll([json_encode(bits[1])])).filter(function(e){return e.textContent.trim().indexOf(t)===0;})\[0\];if(b){b.click();}"
	else if(findtext(action, "pickin:") == 1)
		var/list/bits = splittext(copytext(action, 8), "|")
		js = "var c=Array.prototype.slice.call(document.querySelectorAll([json_encode(bits[1])])).filter(function(e){return e.textContent.indexOf([json_encode(bits[3])])>=0;})\[0\];if(c){var t=[json_encode(bits[4])];var b=Array.prototype.slice.call(c.querySelectorAll([json_encode(bits[2])])).filter(function(e){return e.textContent.trim().indexOf(t)===0;})\[0\];if(b){b.click();}}"
	else if(findtext(action, "textarea:") == 1)
		js = "var a=document.querySelector('textarea');if(a){a.focus();a.value=[json_encode(copytext(action, 10))];a.dispatchEvent(new Event('input',{bubbles:true}));}"
	else if(action == "ctrlenter")
		js = "var a=document.querySelector('textarea');if(a){a.dispatchEvent(new KeyboardEvent('keydown',{bubbles:true,keyCode:13,ctrlKey:true}));}"
	else if(findtext(action, "type") == 1)
		var/colon = findtext(action, ":")
		var/index = text2num(copytext(action, 5, colon))
		js = "var i=document.querySelectorAll('input')\[[index]\];if(i){i.focus();i.value=[json_encode(copytext(action, colon + 1))];i.dispatchEvent(new Event('input',{bubbles:true}));i.blur();}"
	if(js)
		C << output(url_encode(js), "[ui.window_id].browser:eval")
	sleep(10)

/datum/tgui/s2_stub/New()
	status = UI_INTERACTIVE

/proc/s2_spawn(turf/T, name, outfit, job, key)
	var/mob/living/carbon/human/M = new(T)
	if(key)
		M.key = key
	M.mind_initialize()
	M.fully_replace_character_name(null, name)
	M.equipOutfit(outfit)
	M.mind.assigned_role = job
	return M

/proc/s2_area_turf(area_type, offset = 0)
	var/list/open = list()
	for(var/turf/open/floor/F in get_area_turfs(area_type))
		if(!is_blocked_turf(F, TRUE))
			open += F
	return open.len ? open[1 + (offset % open.len)] : null

/proc/s2_messages_of(datum/admin_help/AH, kind)
	. = list()
	for(var/list/M in AH.ticket_messages)
		if(M["kind"] == kind)
			. += list(M)

/proc/s2_alerts_of(kind)
	. = list()
	for(var/datum/admin_alert/A in SSadmin_alerts.alerts)
		if(A.kind == kind)
			. += A

/proc/stage2_check_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1
	GLOB.ahelp_replies_path = "data/stage2_check/replies.json"
	GLOB.mentor_replies_path = "data/stage2_check/mentor_replies.json"
	GLOB.admin_alert_mutes_path = "data/stage2_check/mutes.json"
	GLOB.player_history_dir = "data/stage2_check/history/"
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(3 SECONDS)
	var/turf/home = s2_area_turf(/area/crew_quarters/bar, 0)
	var/mob/living/carbon/human/H = new(home)
	H.mind_initialize()
	H.fully_replace_character_name(null, "Alex Assistant")
	H.equipOutfit(/datum/outfit/job/assistant)
	H.mind.assigned_role = "Assistant"
	H.ckey = C.ckey
	sleep(3 SECONDS)
	if(!C.holder)
		var/datum/admins/A = new(new /datum/admin_rank("!localhost!", R_EVERYTHING, R_DBRANKS, R_EVERYTHING), C.ckey, 1, 1)
		A.associate(C)
	sleep(2 SECONDS)
	usr = H
	var/list/people = list()
	people["bob"] = s2_spawn(s2_area_turf(/area/crew_quarters/bar, 3), "Bob Barman", /datum/outfit/job/bartender, "Bartender", "bobbarman")
	people["tara"] = s2_spawn(s2_area_turf(/area/crew_quarters/bar, 6), "Tara Tide", /datum/outfit/job/assistant, "Assistant", "taratide")
	people["vic"] = s2_spawn(s2_area_turf(/area/crew_quarters/bar, 9), "Vic Tim", /datum/outfit/job/cook, "Cook", "victim1")
	people["rob"] = s2_spawn(s2_area_turf(/area/crew_quarters/bar, 12), "Rob Ott", /datum/outfit/job/assistant, "Assistant", "robott")
	people["dan"] = s2_spawn(s2_area_turf(/area/crew_quarters/bar, 15), "Dan Dee", /datum/outfit/job/assistant, "Assistant", "dandee")
	var/mob/living/carbon/human/tara = people["tara"]
	var/datum/antagonist/traitor/T = tara.mind.add_antag_datum(/datum/antagonist/traitor)
	var/datum/objective/assassinate/hit = new
	hit.owner = tara.mind
	var/mob/living/carbon/human/vic_mob = people["vic"]
	hit.target = vic_mob.mind
	hit.update_explanation_text()
	T.objectives += hit
	SSbans.note_seen(C.ckey, C.key, "203.0.113.20", "9990001111")
	SSbans.note_seen("altaccount", "Alt Account", "203.0.113.20", "9990001111")
	SSnotes.add("note", C.ckey, C.key, "moderatormaya", "Moderator Maya", "Argued with Security in OOC.", TRUE, null, "minor", SQLtime(world.realtime - 3 * 864000))
	// an earlier round, as the history keeps it
	var/list/past = player_history_read(C.ckey)
	past["rounds"] += list(list("round_id" = "1040", "date" = "2026-11-06 21:10", "name" = "Alex Assistant", "job" = "Cook", "antag" = null, "end" = "alive"))
	past["tickets"] += list(list("round_id" = "1040", "id" = 2, "date" = "2026-11-06 21:30", "title" = "Someone stole my knife", "outcome" = "IC issue", "handled_by" = "Moderator Maya", "closed_by" = "moderatormaya/(Moderator Maya)", "messages" = 3, "first" = "Someone stole my knife"))
	player_history_write(C.ckey, past)
	var/mob/living/carbon/human/bob = people["bob"]
	tara.log_message("Who wants a drink?", LOG_SAY)
	log_combat(tara, bob, "shoved")
	H.log_message("Bob, can I get a drink?", LOG_SAY)
	bob.log_message("No. Get out of my bar.", LOG_SAY)
	log_combat(bob, H, "punched")
	log_combat(bob, H, "punched")
	log_combat(H, bob, "shoved")
	sleep(6 SECONDS) // a whereabouts snapshot or two
	s2_help_form(C, H, people)
	var/datum/admin_help/AH = C.current_ticket
	if(!AH)
		s2_check("a ticket to go on with", FALSE)
	else
		s2_tickets(C, H, AH, people)
		s2_kills(C, H, AH, people)
		s2_alerts(C, H, AH, people)
		s2_profile(C, H, AH)
		s2_questions(C, H, AH)
		s2_history(C, H)
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)

/// The player's side: F1's form, then their ticket
/proc/s2_help_form(client/C, mob/living/carbon/human/H, list/people)
	C.get_adminhelp() // what F1 does
	var/datum/help_window/W = C.help_window
	var/datum/tgui/ui = s2_ui(H, W)
	s2_check("F1 opens the form", ui && W)
	var/list/data = W.ui_data(H)
	var/list/about_names = list()
	for(var/list/P in data["about"])
		about_names += P["name"]
	s2_check("who it's about offers Bob, who punched them, by name", ("Bob Barman" in about_names), about_names.Join(", "))
	s2_shot("help_form")
	s2_do(C, ui, "pick:.HelpWindow__kind|Player report")
	s2_do(C, ui, "pick:.HelpWindow__person|Bob Barman")
	s2_do(C, ui, "textarea:He keeps punching me in the bar for no reason, and he threw a glass at me")
	s2_do(C, ui, "click:Send")
	sleep(1 SECONDS)
	var/datum/admin_help/AH = C.current_ticket
	s2_check("Send makes a ticket marked Player report, about Bob", AH && AH.help_kind == "report" && findtext(AH.name, "Player report: about Bob Barman: He keeps punching me") == 1, AH ? "[AH.help_kind]: [AH.name]" : "none")
	var/list/named = list()
	for(var/datum/weakref/R in AH?.mentioned)
		named += R.resolve()
	s2_check("and Bob is among the people it names", (people["bob"] in named))
	data = W.ui_data(H)
	s2_check("the window turns into their ticket, waiting", data["showing"] == "ahelp" && data["ahelp"] && data["ahelp"]["waiting"])
	s2_shot("help_ticket")
	s2_close(H, W)

/proc/s2_tickets(client/C, mob/living/carbon/human/H, datum/admin_help/AH, list/people)
	AH.TicketPanel()
	var/datum/ticket_window/W = C.ticket_window
	var/datum/tgui/ui = s2_ui(H, W)
	s2_check("the ticket's own link opens the Tickets window on it", ui && W.selected_id == AH.id)
	s2_do(C, ui, "click:Claim")
	s2_check("Claim", AH.claimed_ckey == C.ckey)
	s2_do(C, ui, "pick:.Tickets__savedChip|Details")
	s2_do(C, ui, "click:Send")
	sleep(5)
	var/list/answers = s2_messages_of(AH, "admin")
	s2_check("a saved reply sent from the window", answers.len == 1 && answers[1]["text"] == "Who did it, where, and when? Names help.")
	// a note only admins see
	s2_do(C, ui, "pick:.Tickets__mode|Note")
	s2_do(C, ui, "textarea:Checked the logs: Bob hit first, twice.")
	s2_do(C, ui, "click:Add note")
	sleep(5)
	var/list/notes = s2_messages_of(AH, "note")
	s2_check("Note adds a note to the ticket", notes.len == 1 && findtext(notes[1]["text"], "Bob hit first"))
	s2_do(C, ui, "pick:.Tickets__mode|Reply")
	// the player's view of the same ticket: their words, the admin's, plain events, never the note or who claimed it
	if(!C.help_window)
		C.help_window = new
		C.help_window.owner = C
	var/list/player_view = C.help_window.ui_data(H)
	var/list/lines = player_view["ahelp"] ? player_view["ahelp"]["lines"] : list()
	var/saw_note = FALSE
	var/saw_claim_key = FALSE
	var/saw_handling = FALSE
	for(var/list/L in lines)
		if(findtext(L["text"], "Checked the logs"))
			saw_note = TRUE
		if(findtext(L["text"], "Claimed by"))
			saw_claim_key = TRUE
		if(L["text"] == "An admin is handling it.")
			saw_handling = TRUE
	s2_check("the player never sees the note or the claiming admin's key, only that an admin is on it", !saw_note && !saw_claim_key && saw_handling, "[lines.len] lines")
	// a quoted line into Note+ and Ban
	s2_do(C, ui, "pickin:.LogSearch__line|a|has punched|QUOTE")
	sleep(5)
	var/list/quoted = W.quotes["[AH.id]"]
	s2_check("QUOTE marks the line", length(quoted) == 1)
	s2_do(C, ui, "pick:.Tickets__links a|NOTE+")
	sleep(1 SECONDS)
	var/datum/ban_window/B = C.ban_window
	var/note_text = B?.compose ? B.compose["text"] : null
	s2_check("NOTE+ opens a note with the ticket and the quoted line", note_text && findtext(note_text, "Ticket #[AH.id]") && findtext(note_text, "has punched"), note_text)
	s2_close(H, B)
	s2_do(C, ui, "pick:.Tickets__links a|BAN")
	sleep(1 SECONDS)
	var/reason = B?.prefill ? B.prefill["reason"] : null
	s2_check("BAN opens a new ban with them and the same reason", reason && findtext(reason, "has punched") && B.prefill["key"] == C.key, reason)
	s2_close(H, B)
	// the list of tickets: the form's kind on it
	var/list/data = W.ui_data(H)
	var/list/row = length(data["tickets"]) ? data["tickets"][1] : null
	s2_check("the list says what kind of ahelp it is", row && row["kind"] == "Player report")
	s2_shot("tickets")

/proc/s2_kills(client/C, mob/living/carbon/human/H, datum/admin_help/AH, list/people)
	var/datum/ticket_window/W = C.ticket_window
	var/datum/tgui/ui = s2_ui(H, W)
	var/mob/living/carbon/human/tara = people["tara"]
	var/mob/living/carbon/human/bob = people["bob"]
	AH.MessageNoRecipient("Tara Tide was there too, she looked shifty")
	// the traitor kills her target, the bartender kills someone for nothing, the traitor kills the player who asked
	var/mob/living/carbon/human/vic = people["vic"]
	var/mob/living/carbon/human/rob = people["rob"]
	var/mob/living/carbon/human/dan = people["dan"]
	log_combat(tara, vic, "stabbed")
	vic.death()
	log_combat(bob, rob, "smashed a bottle over")
	rob.death()
	log_combat(dan, bob, "punched")
	log_combat(bob, dan, "punched")
	dan.death()
	log_combat(tara, H, "stabbed")
	H.death()
	sleep(3 SECONDS)
	W.context_for = null
	var/list/data = W.ui_data(H)
	var/list/T = data["ticket"]
	var/list/kills = T["kills"]
	var/list/by_victim = list()
	for(var/list/K in kills)
		var/list/victim = K["victim"]
		by_victim[victim["name"]] = K
	var/list/vic_kill = by_victim["Vic Tim"]
	var/list/rob_kill = by_victim["Rob Ott"]
	var/list/dan_kill = by_victim["Dan Dee"]
	var/list/own_kill = by_victim["Alex Assistant"]
	s2_check("the traitor's kill of her target: her objective says so", vic_kill && ("the dead one is their objective target" in vic_kill["reasons"]), vic_kill ? jointext(vic_kill["reasons"], "; ") : "missing")
	s2_check("the bartender's kill: no reason found", rob_kill && !length(rob_kill["reasons"]) && rob_kill["killer"]["name"] == "Bob Barman")
	s2_check("Dan hit Bob first: that's a reason", dan_kill && ("the dead one struck first" in dan_kill["reasons"]), dan_kill ? jointext(dan_kill["reasons"], "; ") : "missing")
	s2_check("the player's own death, by the traitor, with her objectives", own_kill && own_kill["killer"]["antag"] && length(own_kill["killer"]["objectives"]))
	s2_check("the warning: don't tell them their killer is a traitor", T["secret_warning"] && findtext(T["secret_warning"], "Tara Tide") && findtext(T["secret_warning"], "Traitor"), T["secret_warning"])
	s2_check("who saw it: Bob saw his own bar's stabbing", own_kill && findtext(own_kill["seen"], "bobbarman"), own_kill ? own_kill["seen"] : "missing")
	s2_do(C, ui, "pick:.Tickets__ctxTab|Kills")
	sleep(1 SECONDS)
	s2_shot("kills")
	// where everyone was
	s2_do(C, ui, "pick:.Tickets__ctxTab|Map")
	sleep(2 SECONDS)
	data = W.ui_data(H)
	T = data["ticket"]
	var/list/wb = T["whereabouts"]
	var/player_dot = FALSE
	var/named_dot = FALSE
	for(var/list/D in wb?["dots"])
		if(D["role"] == "player")
			player_dot = TRUE
		if(D["role"] == "named")
			named_dot = TRUE
	s2_check("the map: them and the people they named, where they were when they asked", W.map_open && player_dot && named_dot, "[length(wb?["dots"])] dots")
	s2_shot("map")
	s2_do(C, ui, "pick:.Tickets__ctxTab|What happened")
	// what they heard
	s2_do(C, ui, "pick:.LogSearch__chip|Heard")
	sleep(1 SECONDS)
	data = W.ui_data(H)
	T = data["ticket"]
	var/heard = FALSE
	for(var/list/R in T["context"])
		if(findtext(R["text"], "Who wants a drink"))
			heard = TRUE
	s2_check("Heard adds what was said near them", W.show_heard && heard)

/proc/s2_alerts(client/C, mob/living/carbon/human/H, datum/admin_help/AH, list/people)
	var/mob/living/carbon/human/bob = people["bob"]
	s2_close(H, C.ticket_window) // the pictures take the biggest window: the next ones are smaller
	// an explosion, gas, an emag, a crystal near its end, a ticket left waiting
	var/turf/far = s2_area_turf(/area/maintenance/department/science, 0) || s2_area_turf(/area/hallway/primary/central, 20)
	explosion(far, 1, 2, 3, 0)
	var/obj/machinery/portable_atmospherics/canister/toxins/can = new(s2_area_turf(/area/hallway/primary/central, 5))
	usr = bob
	var/datum/tgui/s2_stub/stub = new
	can.ui_act("valve", list(), stub, GLOB.default_state)
	can.ui_act("valve", list(), stub, GLOB.default_state)
	usr = H
	var/obj/item/card/emag/E = new(bob.loc)
	E.afterattack(bob.loc, bob, TRUE)
	var/obj/machinery/power/supermatter_crystal/crystal = GLOB.main_supermatter_engine
	if(crystal)
		crystal.damage = crystal.emergency_point + 1
	AH.waiting_since = world.time - 4 MINUTES
	SSadmin_alerts.check_engines()
	SSadmin_alerts.check_tickets()
	if(crystal)
		crystal.damage = 0
	sleep(4 SECONDS)
	var/list/kills = s2_alerts_of("kill")
	var/datum/admin_alert/bob_kill
	for(var/datum/admin_alert/A in kills)
		if(A.actor_ckey == "bobbarman")
			bob_kill = A
	s2_check("Kill: the bartender's kill, not the traitor's", bob_kill && findtext(bob_kill.text, "Rob Ott") && !length(kills - bob_kill), "[kills.len] kill alerts")
	s2_check("his second kill (Dan, who hit first) counts on the same alert, marked", bob_kill && bob_kill.count == 2 && findtext(bob_kill.text, "both fought"), bob_kill ? "x[bob_kill.count] [bob_kill.text]" : "")
	s2_check("Deaths: four dead in two minutes", length(s2_alerts_of("deaths")) == 1)
	s2_check("Explosion", length(s2_alerts_of("boom")) == 1)
	var/list/gas = s2_alerts_of("gas")
	var/datum/admin_alert/gas_alert = length(gas) ? gas[1] : null
	s2_check("Gas: the plasma canister opened, by whom", length(gas) == 1 && findtext(gas_alert.text, "Plasma") && gas_alert.actor_ckey == "bobbarman", gas_alert ? gas_alert.text : "none")
	s2_check("Emag: used by someone who isn't an antagonist", length(s2_alerts_of("emag")) == 1)
	s2_check("Ticket: waiting three minutes", length(s2_alerts_of("ticket")) == 1)
	s2_check("Engine: the crystal past its emergency point[crystal ? "" : " (no crystal on this map: skipped)"]", !crystal || length(s2_alerts_of("engine")) == 1)
	C.open_admin_alerts()
	var/datum/admin_alerts_window/W = C.admin_alerts_window
	var/datum/tgui/ui = s2_ui(H, W)
	s2_check("the Alerts window opens", !!ui)
	s2_do(C, ui, "pickin:.AdminAlerts__row|.Button|Rob Ott|On it")
	sleep(5)
	s2_check("On it marks it handled by them", bob_kill?.handled_ckey == C.ckey && bob_kill?.handled_by == C.key, "[bob_kill?.handled_by]")
	s2_do(C, ui, "pickin:.AdminAlerts__kind|.AdminAlerts__bell|Kill|")
	sleep(5)
	var/list/muted = SSadmin_alerts.mutes[C.ckey]
	s2_check("the bell mutes Kill in their chat, kept in this run's file", muted && muted["kill"] && findtext(file2text("data/stage2_check/mutes.json"), "kill"))
	s2_shot("alerts")
	s2_close(H, W)

/proc/s2_profile(client/C, mob/living/carbon/human/H, datum/admin_help/AH)
	C.open_player_profile(C.ckey)
	var/datum/player_profile/P = C.player_profile
	var/datum/tgui/ui = s2_ui(H, P)
	s2_check("the profile opens", !!ui)
	var/list/B = P.built
	var/has_alt = FALSE
	for(var/list/alt in B["alts"])
		if(alt["ckey"] == "altaccount")
			has_alt = TRUE
	s2_check("the alt on their computer", has_alt)
	s2_check("their note", length(B["notes"]) == 1)
	var/now_ticket = FALSE
	var/past_ticket = FALSE
	for(var/list/T in B["tickets"])
		if(T["now"] && T["id"] == AH.id)
			now_ticket = TRUE
		if(T["title"] == "Someone stole my knife")
			past_ticket = TRUE
	s2_check("this round's ticket and the one from an earlier round", now_ticket && past_ticket)
	s2_check("the earlier round", length(B["rounds"]) == 1 && B["rounds"][1]["job"] == "Cook")
	s2_check("this round by the log: hit twice, died once", B["round_counts"]["attacked_by"] >= 3 && B["round_counts"]["deaths"] == 1, json_encode(B["round_counts"]))
	s2_shot("profile")
	s2_do(C, ui, "pick:.PlayerProfile__name|Alt Account")
	sleep(1 SECONDS)
	s2_check("an alt's name opens their profile", P.shown_ckey == "altaccount")
	s2_do(C, ui, "pick:.PlayerProfile__titleRow .Button|")
	sleep(1 SECONDS)
	s2_check("Back goes back", P.shown_ckey == C.ckey)
	s2_close(H, P)

/proc/s2_questions(client/C, mob/living/carbon/human/H, datum/admin_help/AH)
	C.mentorhelp("How do I set up the supermatter?")
	var/datum/help_question/Q = C.current_question
	s2_check("a mentorhelp makes a question", Q && Q.open && Q.name == "How do I set up the supermatter?")
	C.open_questions(Q.id)
	var/datum/question_window/W = C.question_window
	var/datum/tgui/ui = s2_ui(H, W)
	s2_check("the Questions window opens on it", ui && W.selected_id == Q.id)
	s2_do(C, ui, "click:Claim")
	s2_check("Claim", Q.claimed_ckey == C.ckey)
	s2_do(C, ui, "textarea:Ask the engineers on the radio, they'll walk you through it.")
	s2_do(C, ui, "click:Save as reply")
	s2_do(C, ui, "type0:Engineers")
	s2_do(C, ui, "click:Save")
	sleep(5)
	s2_check("a mentors' saved reply, in this run's file", mentor_replies()["Engineers"] && findtext(file2text("data/stage2_check/mentor_replies.json"), "Engineers"))
	s2_shot("questions")
	s2_do(C, ui, "click:Done")
	sleep(5)
	s2_check("Done answers it", !Q.open && !C.current_question)
	// one that's really an ahelp
	C.mentorhelp_send("Someone is spawning guns at the bar, is that allowed?") // the verb is cooling down from the first
	var/datum/help_question/Q2 = C.current_question
	C.open_questions(Q2.id)
	s2_do(C, ui, "click:To admins")
	sleep(1 SECONDS)
	s2_check("To admins puts it in their ahelp and closes the question", !Q2.open && Q2.ahelp_id == AH.id && findtext(AH.ticket_messages[AH.ticket_messages.len]["text"], "spawning guns"), "[Q2.ahelp_id]")
	// admins see the questions in their Tickets window
	var/datum/ticket_window/TW = C.ticket_window
	TW.list_state = 0
	C.mentorhelp_send("Where is the bar?")
	var/list/data = TW.ui_data(H)
	var/listed = FALSE
	for(var/list/row in data["tickets"])
		if(row["question"] && row["title"] == "Where is the bar?")
			listed = TRUE
	s2_check("the Tickets window's Questions list", listed)
	TW.list_state = AHELP_ACTIVE
	s2_close(H, W)

/proc/s2_history(client/C, mob/living/carbon/human/H)
	var/list/before = player_history_read(C.ckey)
	var/rounds_before = length(before["rounds"])
	var/this_round = FALSE
	for(var/list/T in before["tickets"])
		if(T["round_id"] == player_history_round() && findtext(T["title"], "Player report"))
			this_round = TRUE
	s2_check("this round's ticket is kept in their history file", this_round)
	player_history_round_end()
	var/list/after = player_history_read(C.ckey)
	var/list/last = length(after["rounds"]) ? after["rounds"][after["rounds"].len] : null
	s2_check("the round's end keeps their round: who, what, dead", length(after["rounds"]) == rounds_before + 1 && last["name"] == "Alex Assistant" && last["end"] == "dead", last ? json_encode(last) : "none")
	var/bot_rounds = fexists("data/stage2_check/history/bobbarman.json")
	s2_check("and the others' (they have keys)", bot_rounds)
