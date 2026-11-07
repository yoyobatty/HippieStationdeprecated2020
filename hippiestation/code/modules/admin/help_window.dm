// The player's side of ahelps (tgui-next HelpWindow.js). The user's rulings (2026-11-07): an ahelp form (what kind, and who
// it's about) and the player's own ticket window instead of popups: the conversation, its status, a box to reply in.
// F1 opens it (the old box asked for the text alone); the Adminhelp verb typed with a message still sends at once.
//	Form: Player report, Bug, Question or Other; who it's about, from the people they can see and the ones who hurt them or
//	whom they hurt lately (names as they saw them, never keys); what happened. A Question goes to the mentors.
//	Ticket: what they and the admins said, and plain lines for the rest ("An admin is handling it", "Resolved"). Never the
//	admins' notes or who claimed it, and nothing from the admin side of the Tickets window: no antagonists, no logs.

GLOBAL_LIST_EMPTY(help_windows)

/client/var/datum/help_window/help_window

/client/verb/ask_for_help()
	set name = "Ask for help"
	set category = "Admin"
	set desc = "Ask the admins or mentors, and see your ticket."
	open_help_window()

/client/get_adminhelp()
	open_help_window()

/client/proc/open_help_window()
	if(!help_window)
		help_window = new
		help_window.owner = src
	help_window.ui_interact(mob)

/proc/help_windows_changed()
	for(var/datum/help_window/W in GLOB.help_windows)
		if(!W.owner)
			qdel(W)
			continue
		SStgui.update_uis(W)

/// The kinds on the form: what the ticket's title starts with
GLOBAL_LIST_INIT(help_kinds, list(
	"report" = "Player report",
	"bug" = "Bug",
	"question" = "Question",
	"other" = "Other",
))

/datum/admin_help
	/// What the form said it was (help_window.dm), or null for a plain ahelp
	var/help_kind

/datum/help_window
	var/client/owner
	/// The people offered for "who it's about", as the form last listed them: weakrefs, in its order
	var/list/about_refs = list()
	/// Shown: "ahelp" or "question" when they have both
	var/showing = "ahelp"
	var/notice
	var/notice_bad = FALSE
	/// When their last new question went: one every 15 seconds from here (the verb has its own 30 second cooldown)
	var/last_question = -INFINITY

/datum/help_window/New()
	GLOB.help_windows += src

/datum/help_window/Destroy()
	GLOB.help_windows -= src
	owner = null
	return ..()

/datum/help_window/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "help_window", "Ask for help", 520, 560, master_ui, state)
		ui.open()

/// Who they might mean: the people they can see now, then whoever hurt them or they hurt in the last ten minutes.
/// Names as they appear (a masked face is "Unknown"), never keys.
/datum/help_window/proc/about_people()
	. = list()
	about_refs = list()
	var/mob/me = owner?.mob
	if(!me || isnewplayer(me))
		return
	var/list/found = list()
	for(var/mob/living/M in view(7, me))
		if(M == me || M.invisibility > me.see_invisible || !(M.ckey || M.is_bot_crew() || ishuman(M)))
			continue
		found[M] = "nearby"
	var/since = world.time - 10 MINUTES
	var/list/log = GLOB.round_log
	for(var/i in log.len to max(1, log.len - 4000) step -1)
		var/list/entry = log[i]
		if(entry[RL_TIME] < since)
			break
		if(entry[RL_CAT] != "Attack")
			continue
		var/datum/weakref/other_ref
		if(entry[RL_TCKEY] == me.ckey)
			other_ref = entry[RL_REF]
		else if(entry[RL_CKEY] == me.ckey)
			other_ref = entry[RL_TREF]
		var/mob/living/other = other_ref?.resolve()
		if(istype(other) && other != me && !found[other])
			found[other] = "fought you"
	for(var/mob/living/M in found)
		about_refs += WEAKREF(M)
		. += list(list("index" = about_refs.len, "name" = M.name, "why" = found[M]))
		if(about_refs.len >= 12)
			break

/// A message as the player sees it: who said it as they'd know them, events in plain words, admins' notes left out
/proc/help_player_line(list/M, kind_of_ticket)
	switch(M["kind"])
		if("player")
			return list("kind" = "player", "who" = "You", "text" = M["text"], "time" = log_search_clock(M["time"]))
		if("admin", "mentor")
			return list("kind" = "staff", "who" = M["shown_as"] || (M["kind"] == "admin" ? "Admin" : (M["who"] || "Mentor")), "text" = M["text"], "time" = log_search_clock(M["time"]))
		if("event")
			var/text = M["text"]
			var/shown
			if(findtext(text, "Claimed by") == 1)
				shown = kind_of_ticket == "question" ? "A mentor is answering." : "An admin is handling it."
			else if(findtext(text, "Marked as IC issue") == 1)
				shown = "Marked as an IC issue: sort it out in character."
			else if(findtext(text, "Resolved by") == 1)
				shown = "Resolved."
			else if(findtext(text, "Rejected by") == 1)
				shown = "Rejected: ask again, clearly."
			else if(findtext(text, "Closed by") == 1)
				shown = "Closed."
			else if(findtext(text, "Done, by") == 1)
				shown = "Answered."
			else if(findtext(text, "Passed to the admins") == 1)
				shown = "Passed to the admins."
			if(shown)
				return list("kind" = "event", "text" = shown, "time" = log_search_clock(M["time"]))
	return null

/datum/help_window/ui_data(mob/user)
	var/client/C = owner
	var/datum/admin_help/AH = C?.current_ticket
	var/datum/help_question/Q = C?.current_question
	var/list/data = list(
		"kinds" = GLOB.help_kinds,
		"notice" = notice,
		"notice_bad" = notice_bad,
		"admins_on" = length(get_admin_counts()["present"]),
		"mentors_on" = length(GLOB.mentors),
		"can_ask" = !!(/client/verb/adminhelp in C?.verbs),
	)
	if(AH && AH.state == AHELP_ACTIVE)
		var/list/lines = list()
		for(var/list/M in AH.ticket_messages)
			var/list/shown = help_player_line(M, "ahelp")
			if(shown)
				lines += list(shown)
		data["ahelp"] = list("id" = AH.id, "title" = AH.name, "claimed" = !!AH.claimed_ckey, "waiting" = !!AH.waiting_since, "lines" = lines, "kind" = GLOB.help_kinds[AH.help_kind])
	if(Q && Q.open)
		var/list/lines = list()
		for(var/list/M in Q.messages)
			var/list/shown = help_player_line(M, "question")
			if(shown)
				lines += list(shown)
		data["question"] = list("id" = Q.id, "title" = Q.name, "claimed" = !!Q.claimed_ckey, "waiting" = !!Q.waiting_since, "lines" = lines)
	data["showing"] = data[showing] ? showing : (data["ahelp"] ? "ahelp" : (data["question"] ? "question" : null))
	if(!data["showing"])
		data["about"] = about_people()
	return data

/datum/help_window/ui_act(action, list/params)
	if(..())
		return
	var/client/C = owner
	if(!C || usr.client != C)
		return
	notice = null
	switch(action)
		if("show")
			if(params["which"] in list("ahelp", "question"))
				showing = params["which"]
			return TRUE
		if("send")
			var/text = trim("[params["text"]]")
			var/kind = params["kind"]
			if(!text)
				notice = "Say what happened."
				notice_bad = TRUE
				return TRUE
			if(!GLOB.help_kinds[kind])
				kind = "other"
			var/mob/about
			var/index = text2num(params["about"])
			if(index && index <= about_refs.len)
				var/datum/weakref/W = about_refs[index]
				about = W.resolve()
			if(kind == "question")
				if(world.time < last_question + 15 SECONDS)
					notice = "You asked a moment ago: wait a little."
					notice_bad = TRUE
					return TRUE
				last_question = world.time
				C.mentorhelp_send(text)
				showing = "question"
				return TRUE
			if(!(/client/verb/adminhelp in C.verbs))
				notice = "You ahelped a moment ago: wait a little."
				notice_bad = TRUE
				return TRUE
			var/title = "[kind == "other" ? "" : "[GLOB.help_kinds[kind]]: "][about ? "about [about.name]: " : ""][text]"
			C.adminhelp(title)
			var/datum/admin_help/AH = C.current_ticket
			if(AH)
				AH.help_kind = kind
				if(about)
					AH.mentioned |= WEAKREF(about)
			showing = "ahelp"
			tickets_changed()
			return TRUE
		if("reply")
			var/text = trim("[params["text"]]")
			if(!text)
				return
			if(params["which"] == "question")
				var/datum/help_question/Q = C.current_question
				if(!Q || !Q.open)
					return TRUE
				var/client/mentor = Q.claimed_ckey ? GLOB.directory[Q.claimed_ckey] : null
				if(mentor)
					C.cmd_mentor_pm(mentor, text)
				else
					C.mentorhelp_send(text)
				return TRUE
			var/datum/admin_help/AH = C.current_ticket
			if(!AH || AH.state != AHELP_ACTIVE)
				return TRUE
			var/client/admin = AH.claimed_ckey ? GLOB.directory[AH.claimed_ckey] : null
			if(admin?.holder)
				C.cmd_admin_pm(admin, text)
			else
				AH.MessageNoRecipient(text)
			return TRUE
