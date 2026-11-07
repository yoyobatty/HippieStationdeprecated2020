// The Tickets window with a real admin client: tickets made the way players make them, the window pictured, and its buttons
// clicked the way an admin clicks them (the page's own buttons, not ui_act), then what that did checked on the server. Not part
// of the game:
//   HARNESS=tickets_check.dm SENDER=shot.ps1 tools/keybind_check/run.sh tickets
// Results in data/keycheck_tickets.txt, pictures in data/previews/popup_tickets_*.png. Its notes, connections and saved
// replies go to data/tickets_check/, never data/notes.json and the rest.
//
// The old pages, for the before pictures (a build without the window):
//   EXCLUDE="$(printf '%s\n%s' 'hippiestation\code\modules\admin\tickets.dm' 'hippiestation\code\modules\admin\admin_verbs.dm')" \
//     HARNESS=tickets_check.dm SENDER=shot.ps1 tools/keybind_check/run.sh tickets_before
// The window's own procs are reached by name (call(), vars[]) so this file builds both ways.

GLOBAL_VAR_INIT(keycheck_running, FALSE)

/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

GLOBAL_VAR_INIT(tk_cleared, FALSE)

/datum/controller/subsystem/bans/load()
	if(!GLOB.tk_cleared)
		GLOB.tk_cleared = TRUE
		fdel("data/tickets_check/")
	ledger_path = "data/tickets_check/bans.json"
	seen_path = "data/tickets_check/connections.json"
	seen_loaded = FALSE
	return ..()

/datum/controller/subsystem/notes/load()
	ledger_path = "data/tickets_check/notes.json"
	return ..()

/proc/kc_log(text)
	text2file(text, "data/keycheck.txt")

/client/New()
	. = ..()
	if(. && !GLOB.keycheck_running)
		GLOB.keycheck_running = TRUE
		spawn(50)
			tickets_check_run(src)

/proc/tk_check(name, ok, detail = "")
	kc_log("[ok ? "PASS" : "FAIL"] [name][detail ? " ([detail])" : ""]")

/proc/tk_shot(name, title)
	fdel("data/keycheck_shot_title")
	if(title)
		text2file(title, "data/keycheck_shot_title")
	text2file("popup_tickets_[name]", "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/proc/tk_ui(mob/user, datum/src_object)
	var/deadline = world.time + 15 SECONDS
	while(world.time < deadline)
		for(var/datum/tgui/open as anything in user.open_uis)
			if(open.src_object == src_object && open.initialized)
				return open
		sleep(2)

/// One thing done on the page, then a second for the server to hear it and the page to redraw. "click:<text>" presses the first
/// button whose text starts with it; "pick:<css>|<text>" clicks the first element matching css whose text starts with text;
/// "textarea:<text>" fills the first box of text; "type<N>:<text>" types in the Nth one-line box and leaves it;
/// "ctrlenter" presses Ctrl+Enter in the box of text.
/proc/tk_do(client/C, datum/tgui/ui, action)
	var/js
	if(findtext(action, "click:") == 1)
		js = "var t=[json_encode(copytext(action, 7))];var b=Array.prototype.slice.call(document.querySelectorAll('.Button')).filter(function(e){return e.textContent.trim().indexOf(t)===0;})\[0\];if(b){b.click();}"
	else if(findtext(action, "pick:") == 1)
		var/list/bits = splittext(copytext(action, 6), "|")
		js = "var t=[json_encode(bits[2])];var b=Array.prototype.slice.call(document.querySelectorAll([json_encode(bits[1])])).filter(function(e){return e.textContent.trim().indexOf(t)===0;})\[0\];if(b){b.click();}"
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

/proc/tk_spawn(turf/T, name, outfit, job)
	var/mob/living/carbon/human/M = new(T)
	M.mind_initialize()
	M.fully_replace_character_name(null, name)
	M.equipOutfit(outfit)
	M.mind.assigned_role = job
	return M

/proc/tk_bar_turf(offset = 0)
	var/list/open = list()
	for(var/turf/open/floor/F in get_area_turfs(/area/crew_quarters/bar))
		if(!F.density && !is_blocked_turf(F, TRUE))
			open += F
	return open.len ? open[1 + (offset % open.len)] : get_turf(pick(SSjob.latejoin_trackers))

/proc/tickets_check_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1
	if("ahelp_replies_path" in GLOB.vars)
		GLOB.vars["ahelp_replies_path"] = "data/tickets_check/replies.json"
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(3 SECONDS)
	var/turf/home = tk_bar_turf(0)
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
	// the people in the bar, and what happened there
	var/mob/living/carbon/human/bob = tk_spawn(tk_bar_turf(3), "Bob Barman", /datum/outfit/job/bartender, "Bartender")
	var/mob/living/carbon/human/tara = tk_spawn(tk_bar_turf(6), "Tara Tide", /datum/outfit/job/assistant, "Assistant")
	tara.mind.add_antag_datum(/datum/antagonist/traitor)
	SSbans.note_seen(C.ckey, C.key, "203.0.113.20", "9990001111")
	SSbans.note_seen("altaccount", "Alt Account", "203.0.113.20", "9990001111")
	SSnotes.add("note", C.ckey, C.key, "moderatormaya", "Moderator Maya", "Argued with Security in OOC.", TRUE, null, "minor", SQLtime(world.realtime - 3 * 864000))
	tara.log_message("Who wants a drink?", LOG_SAY)
	log_combat(tara, bob, "shoved")
	H.log_message("Bob, can I get a drink?", LOG_SAY)
	bob.log_message("No. Get out of my bar.", LOG_SAY)
	log_combat(bob, H, "punched")
	log_combat(bob, H, "punched")
	log_combat(H, bob, "shoved")
	log_combat(bob, H, "hit", new /obj/item/reagent_containers/food/drinks/drinkingglass(bob.loc))
	sleep(5)
	var/has_window = hascall(C, "open_tickets")
	tickets_made(C, H, has_window)
	if(has_window)
		tickets_window(C, H, bob, tara)
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)

/// Tickets made as players make them; in a build without the window, the old pages pictured
/proc/tickets_made(client/C, mob/living/carbon/human/H, has_window)
	// a player gone since they asked
	C.adminhelp("Someone emagged the armory and is handing out lasers in the hall")
	var/datum/admin_help/gone = C.current_ticket
	gone.initiator = null
	gone.initiator_ckey = "griefermcgee"
	gone.initiator_key_name = "Griefer McGee/(Greg Tide)"
	if("ticket_messages" in gone.vars)
		gone.vars["ticket_messages"] = list()
	C.current_ticket = null
	C.giveadminhelpverb()
	// one handled and resolved
	C.adminhelp("How do I set up the supermatter?")
	var/datum/admin_help/done = C.current_ticket
	done.Resolve()
	C.current_ticket = null
	C.giveadminhelpverb()
	sleep(5)
	// the one being looked at: punched in the bar, names who did it
	C.adminhelp("Bob Barman keeps punching me in the bar for no reason, and he threw a glass at me")
	var/datum/admin_help/AH = C.current_ticket
	tk_check("the ahelp makes a ticket", AH && AH.state == AHELP_ACTIVE)
	sleep(1 SECONDS)
	if(has_window)
		AH.TicketPanel()
		sleep(2 SECONDS)
		return
	AH.TicketPanel()
	sleep(3 SECONDS)
	tk_shot("before_ticket")
	GLOB.ahelp_tickets.BrowseTickets(AHELP_ACTIVE)
	sleep(3 SECONDS)
	tk_shot("before_list")

/proc/tickets_window(client/C, mob/living/carbon/human/H, mob/living/carbon/human/bob, mob/living/carbon/human/tara)
	var/datum/admin_help/AH = C.current_ticket
	var/datum/W = C.vars["ticket_window"]
	tk_check("the ticket's own page and the list open the window", W && W.vars["selected_id"] == AH.id)
	var/datum/tgui/ui = tk_ui(H, W)
	tk_check("the window opens", !!ui)
	var/list/messages = AH.vars["ticket_messages"]
	var/list/first = length(messages) ? messages[1] : null
	tk_check("the ahelp is the player's message, as text", first && first["kind"] == "player" && findtext(first["text"], "Bob Barman keeps punching me") == 1 && !findtext(first["text"], "<"), first ? "[first["kind"]]: [first["text"]]" : "none")
	tk_check("they're waiting for an answer", !!AH.vars["waiting_since"])
	var/list/named = AH.vars["mentioned"]
	var/list/named_mobs = list()
	for(var/datum/weakref/named_one in named)
		named_mobs += named_one.resolve()
	tk_check("Bob Barman, named in it, is picked out", (bob in named_mobs), "[length(named)] named")
	var/area/here = get_area(H)
	tk_check("where they asked from", AH.vars["opened_area"] == here.name && AH.vars["opened_job"] == "Assistant", "[AH.vars["opened_area"]] [AH.vars["opened_job"]]")
	var/list/brief = call(text2path("/proc/admin_player_brief"))(C.ckey)
	var/list/chips = call(text2path("/proc/ticket_chips"))(brief)
	var/list/chip_text = list()
	for(var/list/chip in chips)
		chip_text += chip["text"]
	var/joined = jointext(chip_text, " | ")
	tk_check("the line under the ahelp: who hurt them, new, the note, the alt", findtext(joined, "hurt by Bob Barman") && findtext(joined, "first seen today") && findtext(joined, "1 note (minor)") && findtext(joined, "1 other key on this computer"), joined)
	var/list/data = W.ui_data(H)
	var/list/T = data["ticket"]
	var/list/context = T ? T["context"] : null
	var/punches = 0
	var/tara_said = 0
	var/tara_shoved_bob = 0
	for(var/list/row in context)
		if(findtext(row["text"], "punched"))
			punches++
		if(row["name"] == "Tara Tide" && findtext(row["text"], "drink"))
			tara_said++
		if(row["name"] == "Tara Tide" && row["tname"] == "Bob Barman")
			tara_shoved_bob++
	tk_check("what happened: their lines, and Bob's (named), not the rest of the bar", punches == 2 && tara_shoved_bob == 1 && !tara_said, "[punches] punches, [tara_shoved_bob] Tara on Bob, [tara_said] Tara said, [length(context)] lines")
	sleep(1 SECONDS)
	tk_shot("window")
	// Claim, from the page
	tk_do(C, ui, "click:Claim")
	sleep(5)
	tk_check("Claim makes it theirs", AH.vars["claimed_ckey"] == C.ckey)
	// a saved reply clicked into the box, then sent
	tk_do(C, ui, "pick:.Tickets__savedChip|Details")
	tk_do(C, ui, "click:Send")
	sleep(1 SECONDS)
	messages = AH.vars["ticket_messages"]
	var/list/latest = messages[messages.len]
	tk_check("a saved reply goes in the box and Send answers with it", latest["kind"] == "admin" && latest["text"] == "Who did it, where, and when? Names help.", "[latest["kind"]]: [latest["text"]]")
	tk_check("and they're not waiting any more", !AH.vars["waiting_since"])
	var/count = messages.len
	tk_do(C, ui, "click:Send")
	sleep(1 SECONDS)
	messages = AH.vars["ticket_messages"]
	tk_check("the box is empty after sending: Send again does nothing", messages.len == count, "[messages.len - count] more")
	tk_do(C, ui, "textarea:Looking into it. Did he say anything before he hit you?")
	tk_do(C, ui, "click:Send")
	sleep(1 SECONDS)
	messages = AH.vars["ticket_messages"]
	latest = messages[messages.len]
	tk_check("a typed answer sent", latest["kind"] == "admin" && findtext(latest["text"], "Did he say anything"), "[latest["kind"]]: [latest["text"]]")
	// their reply, as a player adds to their ahelp
	AH.MessageNoRecipient("He said get out of my bar, then hit me with a glass")
	sleep(1 SECONDS)
	tk_check("their reply makes them wait again", !!AH.vars["waiting_since"])
	// Ctrl+Enter sends
	tk_do(C, ui, "textarea:Thanks. I'll talk to him.")
	tk_do(C, ui, "ctrlenter")
	sleep(1 SECONDS)
	messages = AH.vars["ticket_messages"]
	latest = messages[messages.len]
	tk_check("Ctrl+Enter sends", latest["kind"] == "admin" && findtext(latest["text"], "talk to him"), "[latest["kind"]]: [latest["text"]]")
	// a reply saved
	tk_do(C, ui, "textarea:Please stay in the bar so I can see what happens.")
	tk_do(C, ui, "click:Save as reply")
	tk_do(C, ui, "type0:Stay put")
	tk_do(C, ui, "click:Save")
	sleep(5)
	var/list/replies = call(text2path("/proc/ahelp_replies"))()
	tk_check("Save as reply keeps it", replies["Stay put"] == "Please stay in the bar so I can see what happens.")
	tk_check("in this run's own file", fexists("data/tickets_check/replies.json") && findtext(file2text("data/tickets_check/replies.json"), "Stay put"))
	// the room, 15 minutes
	tk_do(C, ui, "pick:.LogSearch__chip|Room")
	tk_do(C, ui, "pick:.Tickets__min|15m")
	sleep(1 SECONDS)
	tk_check("Room and 15m", W.vars["show_area"] && W.vars["context_minutes"] == 15)
	data = W.ui_data(H)
	T = data["ticket"]
	tara_said = 0
	for(var/list/row in T["context"])
		if(row["name"] == "Tara Tide" && findtext(row["text"], "drink"))
			tara_said++
	tk_check("Room adds what else happened in the bar before they asked", tara_said == 1, "[tara_said]")
	sleep(1 SECONDS)
	tk_shot("room")
	// renamed in place (a click mid-redraw can be lost: once more if so)
	for(var/try_count in 1 to 2)
		tk_do(C, ui, "pick:.Tickets__title|Bob Barman")
		sleep(5)
		tk_do(C, ui, "type0:Bob punching people in the bar")
		sleep(5)
		if(AH.name == "Bob punching people in the bar")
			break
	tk_check("the title renamed in the window", AH.name == "Bob punching people in the bar", AH.name)
	// the list: the gone player's ticket waiting longest is first
	var/list/rows = data["tickets"]
	var/list/top = length(rows) ? rows[1] : null
	tk_check("the list: the one waiting longest is first, and the gone player is marked", top && top["key"] == "Griefer McGee/(Greg Tide)" && !top["online"], top ? "[top["key"]] [top["online"]]" : "none")
	// resolved from the window
	tk_do(C, ui, "click:Resolve")
	sleep(1 SECONDS)
	tk_check("Resolve resolves it", AH.state == AHELP_RESOLVED)
	tk_do(C, ui, "pick:.Tickets__tab|Resolved")
	sleep(1 SECONDS)
	tk_check("the Resolved list", W.vars["list_state"] == AHELP_RESOLVED)
	tk_shot("resolved")
	// the old way in still works: the stat panel's link to the closed list
	GLOB.ahelp_tickets.BrowseTickets(AHELP_CLOSED)
	sleep(1 SECONDS)
	tk_check("the old list links open the window on that list", W.vars["list_state"] == AHELP_CLOSED)
	// a new ahelp while it's open shows up without a refresh
	C.current_ticket = null
	C.giveadminhelpverb()
	C.adminhelp("The AI bolted me in the kitchen")
	sleep(2 SECONDS)
	tk_do(C, ui, "pick:.Tickets__tab|Open")
	sleep(1 SECONDS)
	data = W.ui_data(H)
	var/found = FALSE
	for(var/list/row in data["tickets"])
		if(findtext(row["title"], "The AI bolted me"))
			found = TRUE
	tk_check("a new ahelp is in the open list", found)
