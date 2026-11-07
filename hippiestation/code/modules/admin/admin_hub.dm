// The admin hub (tgui-next AdminHub.js): one window with the admin tools as tabs across the top (Tickets, Questions, Alerts, Logs,
// Find, Bans) with counts on them, and a player's profile as a panel at the right. The user's rulings (2026-11-07, making the
// admin tools easier to get around): tabs across the top; the separate windows still open on their own from their verbs; the
// hub opens from the Admin verb, a line in the stat panel's Tickets tab, and the links in admin chat (a ticket's #id, ALERTS,
// LOGS, a player panel's PROFILE, View Variables' "Everything here").
//
// Each tab is the same tool its own window shows, with the same state: the hub hands the tool's ui_data to the page and the
// page's actions to the tool's ui_act. A tool that opens another tool (an alert's TICKET, a ticket's NOTES, a name's Logs or
// Profile) goes through its client/open_*() proc; while the hub is handling an action (client.hub_routing), those switch the
// hub's tab, or open the profile panel, instead of opening a separate window.

GLOBAL_LIST_INIT(admin_hub_tabs, list("tickets", "questions", "alerts", "logs", "find", "bans"))

/client/var/datum/admin_hub/admin_hub
/// While the hub handles an action: another tool opening goes to a tab instead of a window
/client/var/hub_routing = FALSE
/// A ticket's Reopen redraws its own page (TicketPanel()): not a reason to open the hub from the separate Tickets window
/client/var/hub_suppress = FALSE

/client/proc/cmd_admin_hub()
	set name = "Admin"
	set category = "Admin"
	set desc = "Tickets, questions, alerts, logs, find and bans in one window."
	if(!check_rights(R_ADMIN))
		return
	open_admin_hub()

/// The hub, on a tab if one's given, with the profile panel shown if asked
/client/proc/open_admin_hub(tab, show_profile = FALSE)
	if(!holder)
		return
	if(!admin_hub)
		admin_hub = new
		admin_hub.owner = src
	if(tab in GLOB.admin_hub_tabs)
		admin_hub.tab = tab
	if(show_profile)
		admin_hub.profile_open = TRUE
	admin_hub.ui_interact(mob)
	SStgui.update_uis(admin_hub)

/// Whether a tool being opened goes to the hub: during a hub action, or from a link meant for it
/client/proc/hub_wants(via_hub)
	return holder && (hub_routing || (via_hub && !hub_suppress))

/datum/admin_hub
	var/client/owner
	var/tab = "tickets"
	var/profile_open = FALSE
	/// The newest alert seen on the Alerts tab: newer ones are counted on it
	var/alerts_seen = 0
	/// The search box (the user's ruling: a dropdown as you type, in the hub only): what was typed, and what it found
	var/search_text = ""
	var/list/search_results

/datum/admin_hub/Destroy()
	owner = null
	return ..()

/datum/admin_hub/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.admin_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "admin_hub", "Admin", 1440, 820, master_ui, state)
		ui.open()

/// The tool a tab shows: the client's own, made if it isn't yet
/datum/admin_hub/proc/tool(which)
	var/client/C = owner
	if(!C)
		return null
	switch(which)
		if("tickets")
			if(!C.ticket_window)
				C.ticket_window = new
				C.ticket_window.owner = C
			return C.ticket_window
		if("questions")
			if(!C.question_window)
				C.question_window = new
				C.question_window.owner = C
			return C.question_window
		if("alerts")
			if(!C.admin_alerts_window)
				C.admin_alerts_window = new
				C.admin_alerts_window.owner = C
			return C.admin_alerts_window
		if("logs")
			if(!C.log_search)
				C.log_search = new
				C.log_search.owner = C
				C.log_search.search()
			return C.log_search
		if("find")
			if(!C.admin_find)
				C.admin_find = new
			return C.admin_find
		if("bans")
			if(!C.ban_window)
				C.ban_window = new
				C.ban_window.open(C.mob, "bans", null, FALSE)
			return C.ban_window

/// What each tab says on it: list(tab = list("count", "hot"))
/datum/admin_hub/proc/tab_counts()
	. = list()
	var/open = length(GLOB.ahelp_tickets.active_tickets)
	var/waiting = 0
	for(var/datum/admin_help/AH in GLOB.ahelp_tickets.active_tickets)
		if(AH.waiting_since)
			waiting++
	.["tickets"] = list("count" = open, "hot" = waiting, "title" = "[open] open, [waiting] waiting for an answer")
	var/questions = 0
	var/questions_waiting = 0
	for(var/datum/help_question/Q in GLOB.help_questions)
		if(Q.open)
			questions++
			if(Q.waiting_since)
				questions_waiting++
	.["questions"] = list("count" = questions, "hot" = questions_waiting, "title" = "[questions] open, [questions_waiting] waiting")
	var/fresh = 0
	for(var/datum/admin_alert/A in SSadmin_alerts.alerts)
		if(A.id > alerts_seen)
			fresh++
	.["alerts"] = list("count" = fresh, "hot" = fresh, "title" = "[fresh] new since you last looked")

/datum/admin_hub/ui_data(mob/user)
	if(tab == "alerts")
		alerts_seen = SSadmin_alerts.next_id
	var/datum/T = tool(tab)
	var/list/data = list(
		"tab" = tab,
		"counts" = tab_counts(),
		"tool" = T ? T.ui_data(user) : list(),
	)
	var/datum/player_profile/P = owner?.player_profile
	if(profile_open && P?.shown_ckey)
		data["profile"] = P.ui_data(user)
	data["search"] = search_text ? list("text" = search_text, "results" = search_results) : null
	return data

/// Everything a search box's text could mean: players (online, bots, and keys seen before), tickets and questions, places, and
/// how many log lines have it. Each kind a few at most, best first.
/datum/admin_hub/proc/search(text)
	search_text = copytext_char(trim("[text]"), 1, 60)
	search_results = list()
	if(length(search_text) < 2 && !findtext(search_text, "#"))
		return
	var/plain = ckey(search_text)
	// players: a key or name with the text in it; whoever's in the round first
	var/list/players = list()
	var/list/done = list()
	for(var/mob/M in GLOB.mob_list)
		if(!M.ckey || done[M.ckey] || isnewplayer(M) && !M.client)
			continue
		var/name = isobserver(M) ? (M.mind?.name || M.name) : M.real_name
		if(!(plain && findtext(M.ckey, plain)) && !findtext(name, search_text))
			continue
		done[M.ckey] = TRUE
		var/area/A = get_area(M)
		players += list(list("kind" = "player", "id" = M.ckey, "label" = "[name] ([M.ckey])", "hint" = jointext(list(M.mind?.assigned_role, admin_mob_state(M) == "alive" ? A?.name : admin_mob_state(M)) - null, ", ")))
		if(players.len >= 8)
			break
	if(players.len < 8 && plain)
		for(var/seen_ckey in SSbans.seen)
			if(done[seen_ckey] || !findtext(seen_ckey, plain))
				continue
			done[seen_ckey] = TRUE
			players += list(list("kind" = "player", "id" = seen_ckey, "label" = note_key_of(seen_ckey), "hint" = "not here"))
			if(players.len >= 8)
				break
	// tickets and questions: "#3", "q2", or words in the title or the player's key
	var/list/tickets = list()
	var/number = text2num(replacetext(replacetext(lowertext(search_text), "#", ""), "q", ""))
	var/list/all_tickets = GLOB.ahelp_tickets.active_tickets + GLOB.ahelp_tickets.resolved_tickets + GLOB.ahelp_tickets.closed_tickets
	for(var/datum/admin_help/AH in all_tickets)
		if((number && AH.id == number && !findtext(lowertext(search_text), "q")) || findtext(AH.name, search_text) || (plain && findtext(AH.initiator_ckey, plain)))
			tickets += list(list("kind" = "ticket", "id" = AH.id, "label" = "#[AH.id] [AH.name]", "hint" = "[AH.initiator_key_name], [AH.state == AHELP_ACTIVE ? "open" : AH.history_outcome()]"))
			if(tickets.len >= 5)
				break
	for(var/datum/help_question/Q in GLOB.help_questions)
		if(tickets.len >= 6)
			break
		if((number && Q.id == number && findtext(lowertext(search_text), "q")) || findtext(Q.name, search_text) || (plain && findtext(Q.initiator_ckey, plain)))
			tickets += list(list("kind" = "question", "id" = Q.id, "label" = "Q[Q.id] [Q.name]", "hint" = "[Q.initiator_key], [Q.open ? "open" : "done"]"))
	// places
	var/list/places = list()
	for(var/area/A in GLOB.sortedAreas)
		if(!findtext(A.name, search_text) || !is_station_level(A.z))
			continue
		places += list(list("kind" = "place", "id" = REF(A), "label" = A.name))
		if(places.len >= 5)
			break
	// log lines with it
	var/lines = 0
	var/list/log = GLOB.round_log
	for(var/i in 1 to log.len)
		if(findtext(log[i][RL_TEXT], search_text))
			lines++
		if(!(i % 5000))
			CHECK_TICK
	search_results = list(
		list("name" = "Players", "items" = players),
		list("name" = "Tickets", "items" = tickets),
		list("name" = "Places", "items" = places),
		list("name" = "Log lines", "items" = lines ? list(list("kind" = "logs", "id" = search_text, "label" = "[lines] line[lines == 1 ? "" : "s"] with \"[search_text]\"", "hint" = "Logs")) : list()),
	)

/// A search result picked: their profile, the ticket, the place, or the log lines
/datum/admin_hub/proc/search_go(kind, id)
	var/client/C = owner
	switch(kind)
		if("player")
			C.open_player_profile(id)
		if("ticket")
			C.open_tickets(text2num(id))
		if("question")
			C.open_questions(text2num(id))
		if("place")
			var/area/A = locate(id)
			if(istype(A))
				C.jumptoarea(A)
		if("logs")
			if(!C.log_search)
				C.log_search = new
				C.log_search.owner = C
			C.log_search.reset()
			C.log_search.text = "[id]"
			C.log_search.search()
			tab = "logs"
	search_text = ""
	search_results = null

/datum/admin_hub/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	if(..())
		return
	if(!check_rights(R_ADMIN))
		return
	var/client/C = usr.client
	switch(action)
		if("hub_tab")
			if(params["tab"] in GLOB.admin_hub_tabs)
				tab = params["tab"]
			return TRUE
		if("hub_profile_close")
			profile_open = FALSE
			return TRUE
		if("hub_search")
			search(params["text"])
			return TRUE
		if("hub_search_clear")
			search_text = ""
			search_results = null
			return TRUE
	C.hub_routing = TRUE
	try
		if(action == "hub_go") // a search result
			search_go(params["kind"], params["id"])
		else if(findtext(action, "p:") == 1) // the profile panel's own buttons
			C.player_profile?.ui_act(copytext(action, 3), params, ui, state)
		else
			var/datum/T = tool(tab)
			T?.ui_act(action, params, ui, state)
	catch(var/exception/e)
		C.hub_routing = FALSE
		throw e
	C.hub_routing = FALSE
	return TRUE

/// The stat panel's Tickets tab: a line that opens the hub
/obj/effect/statclick/admin_hub/Click()
	usr?.client?.open_admin_hub()

GLOBAL_DATUM_INIT(admin_hub_statclick, /obj/effect/statclick/admin_hub, new(null, "Admin hub"))

/// What the stat panel's hub line says, for one admin
/proc/admin_hub_stat_text(client/C)
	var/open = length(GLOB.ahelp_tickets.active_tickets)
	var/waiting = 0
	for(var/datum/admin_help/AH in GLOB.ahelp_tickets.active_tickets)
		if(AH.waiting_since)
			waiting++
	var/seen = C?.admin_hub ? C.admin_hub.alerts_seen : 0
	var/fresh = 0
	for(var/datum/admin_alert/A in SSadmin_alerts.alerts)
		if(A.id > seen)
			fresh++
	return "[open] ticket[open == 1 ? "" : "s"][waiting ? " ([waiting] waiting)" : ""], [fresh] new alert[fresh == 1 ? "" : "s"]"
