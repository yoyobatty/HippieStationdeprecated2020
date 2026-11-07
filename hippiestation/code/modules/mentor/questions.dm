// Questions: mentorhelps as tickets, in a window mentors and admins share (tgui-next Questions.js). The user's ruling
// (2026-11-07): "Questions also go to mentors, and admins and mentors can all see what's going on, see who's replying, who's
// handling which ticket/question, mentors of course having a nice window too." A question has the conversation (mentorhelps
// and mentor PMs), who's handling it (Claim, or the first mentor to answer), how long they've waited, Done, and To admins
// for one that's really an ahelp. Mentors see no antagonist status, no logs and no notes: what a mentor sees is what any
// player could know, but for how new the player is. Admins see the questions in their Tickets window too.

GLOBAL_LIST_EMPTY(help_questions)
GLOBAL_VAR_INIT(help_question_count, 0)

/client/var/datum/help_question/current_question

/datum/help_question
	var/id
	var/name
	var/open = TRUE
	var/client/initiator
	var/initiator_ckey
	var/initiator_key
	/// Who they were in the round when they asked
	var/char_name
	var/job
	var/opened_at
	var/closed_at
	var/closed_by
	/// list(list("time", "kind" = player|mentor|event, "who", "text"))
	var/list/messages = list()
	var/claimed_ckey
	var/claimed_key
	var/waiting_since
	/// The ahelp it became (To admins)
	var/ahelp_id

/datum/help_question/New(client/C, msg)
	id = ++GLOB.help_question_count
	name = copytext_char(msg, 1, 120)
	initiator = C
	initiator_ckey = C.ckey
	initiator_key = C.key
	opened_at = world.time
	var/mob/M = C.mob
	if(M && !isnewplayer(M) && !isobserver(M))
		char_name = M.real_name
		job = M.mind?.assigned_role
	C.current_question = src
	GLOB.help_questions += src
	add("player", C.key, msg)

/datum/help_question/proc/add(kind, who, text)
	messages += list(list("time" = world.time, "kind" = kind, "who" = who, "text" = text))
	switch(kind)
		if("player")
			if(!waiting_since)
				waiting_since = world.time
		if("mentor")
			waiting_since = null
	questions_changed()

/datum/help_question/proc/claim(client/C, silent = FALSE)
	if(!open || !C)
		return
	claimed_ckey = C.ckey
	claimed_key = C.key
	add("event", null, "Claimed by [C.key]")
	log_mentor("Question #[id] ([initiator_key]) claimed by [key_name(C)]")
	if(!silent)
		for(var/client/X in GLOB.mentors | GLOB.admins)
			to_chat(X, "<span class='mentornotice'><font color='purple'>Question #[id] ([initiator_key]) claimed by [C.key].</font></span>", confidential = TRUE)

/datum/help_question/proc/unclaim(client/C)
	claimed_ckey = null
	claimed_key = null
	add("event", null, "Unclaimed by [C.key]")

/datum/help_question/proc/close(client/C)
	if(!open)
		return
	open = FALSE
	closed_at = world.time
	closed_by = C?.key
	waiting_since = null
	add("event", null, "Done, by [C ? C.key : "nobody"]")
	log_mentor("Question #[id] ([initiator_key]) done, by [C ? key_name(C) : "nobody"]")
	if(initiator?.current_question == src)
		initiator.current_question = null
		to_chat(initiator, "<span class='mentornotice'><font color='purple'>Your question was answered. Mentorhelp again if there's more.</font></span>", confidential = TRUE)

/datum/help_question/proc/reopen(client/C)
	if(open)
		return
	if(initiator?.current_question && initiator.current_question != src)
		return
	open = TRUE
	closed_at = null
	if(initiator)
		initiator.current_question = src
	add("event", null, "Reopened by [C.key]")

/// Really an ahelp: it becomes one, with what was said so far, and the question is done
/datum/help_question/proc/to_admins(client/C)
	if(!open || !initiator)
		return FALSE
	var/list/said = list()
	for(var/list/M in messages)
		if(M["kind"] != "event")
			said += "[M["who"]]: [M["text"]]"
	var/ahelp_text = "(Question #[id], passed to admins by mentor [C.key]) [jointext(said, " / ")]"
	if(initiator.current_ticket)
		initiator.current_ticket.MessageNoRecipient(ahelp_text)
		ahelp_id = initiator.current_ticket.id
	else
		var/datum/admin_help/AH = new(ahelp_text, initiator, FALSE)
		if(QDELETED(AH))
			return FALSE
		ahelp_id = AH.id
	add("event", null, "Passed to the admins by [C.key]: ahelp #[ahelp_id]")
	close(C)
	return TRUE

/// A mentorhelp: their open question gets it, or a new one starts
/proc/help_question_asked(client/C, msg)
	var/datum/help_question/Q = C.current_question
	if(Q && Q.open)
		Q.add("player", C.key, msg)
		return Q
	return new /datum/help_question(C, msg)

/// A mentor PM: the question it answers, or the player's reply to one
/proc/help_question_pm(client/sender, client/recipient, msg)
	if(!sender || !recipient)
		return
	if(sender.is_mentor() && !recipient.is_mentor())
		var/datum/help_question/Q = recipient.current_question
		if(Q && Q.open)
			Q.add("mentor", sender.key, msg)
			if(!Q.claimed_ckey)
				Q.claim(sender, TRUE)
	else if(!sender.is_mentor() && recipient.is_mentor())
		var/datum/help_question/Q = sender.current_question
		if(Q && Q.open)
			Q.add("player", sender.key, msg)

/proc/questions_changed()
	for(var/datum/question_window/W in GLOB.question_windows)
		if(!W.owner)
			qdel(W)
			continue
		SStgui.update_uis(W)
	tickets_changed() // admins see questions in the Tickets window
	help_windows_changed()

// reconnecting picks their open question back up
/datum/admin_help_tickets/ClientLogin(client/C)
	. = ..()
	for(var/datum/help_question/Q in GLOB.help_questions)
		if(Q.open && Q.initiator_ckey == C.ckey)
			Q.initiator = C
			C.current_question = Q
			Q.add("event", null, "Reconnected")

/datum/admin_help_tickets/ClientLogout(client/C)
	. = ..()
	var/datum/help_question/Q = C.current_question
	if(Q)
		Q.initiator = null
		Q.add("event", null, "Disconnected")
		C.current_question = null

////////////////////
// Saved replies for mentors
////////////////////

GLOBAL_LIST(mentor_replies)
GLOBAL_VAR_INIT(mentor_replies_path, "data/mentor_replies.json")

/proc/mentor_replies()
	if(GLOB.mentor_replies)
		return GLOB.mentor_replies
	if(fexists(GLOB.mentor_replies_path))
		var/list/loaded
		try
			loaded = json_decode(file2text(GLOB.mentor_replies_path))
		catch
			loaded = null
		if(islist(loaded))
			GLOB.mentor_replies = loaded
			return loaded
	GLOB.mentor_replies = list(
		"Details" = "What are you trying to do, and what happens?",
		"Ask your department" = "Ask your department on the radio: they'll know.",
		"Wiki" = "There's a guide on the wiki for that.",
		"Ahelp" = "That one's for the admins: press F1 to ahelp.",
	)
	return GLOB.mentor_replies

/proc/mentor_replies_save()
	fdel(GLOB.mentor_replies_path)
	text2file(json_encode(GLOB.mentor_replies), GLOB.mentor_replies_path)

////////////////////
// The window
////////////////////

GLOBAL_LIST_EMPTY(question_windows)

/client/var/datum/question_window/question_window

/client/proc/cmd_questions()
	set name = "Questions"
	set category = "Mentor"
	set desc = "Every mentorhelp this round: who's answering which."
	if(!is_mentor())
		return
	open_questions()

/client/proc/open_questions(question_id)
	if(!is_mentor())
		return
	if(!question_window)
		question_window = new
		question_window.owner = src
	if(question_id)
		question_window.selected_id = question_id
		var/datum/help_question/Q = help_question_by_id(question_id)
		if(Q)
			question_window.show_open = Q.open
	question_window.ui_interact(mob)

/proc/help_question_by_id(id)
	for(var/datum/help_question/Q in GLOB.help_questions)
		if(Q.id == id)
			return Q

/datum/ui_state/mentor_state/can_use_topic(src_object, mob/user)
	if(user.client?.is_mentor())
		return UI_INTERACTIVE
	return UI_CLOSE

GLOBAL_DATUM_INIT(mentor_state, /datum/ui_state/mentor_state, new)

/datum/question_window
	var/client/owner
	var/show_open = TRUE
	var/selected_id
	var/notice
	var/notice_bad = FALSE

/datum/question_window/New()
	GLOB.question_windows += src

/datum/question_window/Destroy()
	GLOB.question_windows -= src
	owner = null
	return ..()

/datum/question_window/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.mentor_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "questions", "Questions", 900, 620, master_ui, state)
		ui.open()

/// What any mentor may see of a question: no antagonist status, no logs, no notes
/datum/question_window/proc/question_row(datum/help_question/Q)
	var/list/last = length(Q.messages) ? Q.messages[Q.messages.len] : null
	return list(
		"id" = Q.id,
		"open" = Q.open,
		"title" = Q.name,
		"key" = Q.initiator_key,
		"name" = Q.char_name,
		"job" = Q.job,
		"online" = !!Q.initiator,
		"age" = ticket_ago_text(world.time - Q.opened_at),
		"waiting" = Q.open && Q.waiting_since ? ticket_ago_text(world.time - Q.waiting_since) : null,
		"wait_ds" = Q.open && Q.waiting_since ? world.time - Q.waiting_since : 0,
		"waiting_long" = Q.open && Q.waiting_since && world.time - Q.waiting_since > 2 MINUTES,
		"claimed" = Q.claimed_key,
		"mine" = !!owner && Q.claimed_ckey == owner.ckey,
		"last" = last ? "[last["who"] ? "[last["who"]]: " : ""][last["text"]]" : null,
		"ahelp" = Q.ahelp_id,
	)

/datum/question_window/ui_data(mob/user)
	var/list/rows = list()
	var/open_count = 0
	var/done_count = 0
	for(var/datum/help_question/Q in GLOB.help_questions)
		if(Q.open)
			open_count++
		else
			done_count++
		if(Q.open == show_open)
			rows += list(question_row(Q))
	sortTim(rows, GLOBAL_PROC_REF(cmp_ticket_rows))
	var/list/data = list(
		"show_open" = show_open,
		"open_count" = open_count,
		"done_count" = done_count,
		"questions" = rows,
		"replies" = mentor_replies(),
		"notice" = notice,
		"notice_bad" = notice_bad,
		"is_admin" = !!owner?.holder,
		"mentors_on" = length(GLOB.mentors),
		"admins_on" = length(GLOB.admins),
	)
	var/datum/help_question/Q = help_question_by_id(selected_id)
	if(Q)
		var/list/Qdata = question_row(Q)
		var/list/messages = list()
		for(var/list/M in Q.messages)
			messages += list(list("time" = log_search_clock(M["time"]), "kind" = M["kind"], "who" = M["who"], "text" = M["text"]))
		Qdata["messages"] = messages
		Qdata["opened"] = log_search_clock(Q.opened_at)
		var/list/seen = SSbans.seen[Q.initiator_ckey]
		if(seen && text2num(seen["first"]))
			var/days = round((world.realtime - text2num(seen["first"])) / 864000)
			if(days < 7)
				Qdata["new_player"] = days < 1 ? "first seen today" : "first seen [days] d ago"
		data["question"] = Qdata
	return data

/datum/question_window/ui_act(action, list/params)
	if(..())
		return
	if(!usr.client?.is_mentor())
		return
	notice = null
	switch(action)
		if("list")
			show_open = !!text2num(params["open"])
			return TRUE
		if("select")
			selected_id = text2num(params["id"])
			return TRUE
		if("reply_save")
			var/title = copytext_char(trim("[params["title"]]"), 1, 40)
			var/text = copytext_char(trim("[params["text"]]"), 1, MAX_MESSAGE_LEN)
			if(!title || !text)
				notice = "A saved reply needs a name and some text."
				notice_bad = TRUE
				return TRUE
			mentor_replies()[title] = text
			mentor_replies_save()
			return TRUE
		if("reply_remove")
			var/list/replies = mentor_replies()
			replies -= "[params["title"]]"
			mentor_replies_save()
			return TRUE
	var/datum/help_question/Q = help_question_by_id(selected_id)
	if(!Q)
		return
	switch(action)
		if("reply")
			var/text = trim("[params["text"]]")
			if(!text)
				return
			if(!Q.open)
				notice = "It's done: reopen it to answer."
				notice_bad = TRUE
				return TRUE
			if(!Q.initiator)
				notice = "[Q.initiator_key] isn't connected."
				notice_bad = TRUE
				return TRUE
			usr.client.cmd_mentor_pm(Q.initiator, text)
			return TRUE
		if("claim")
			Q.claim(usr.client)
			return TRUE
		if("unclaim")
			Q.unclaim(usr.client)
			return TRUE
		if("done")
			Q.close(usr.client)
			return TRUE
		if("reopen")
			Q.reopen(usr.client)
			show_open = Q.open
			return TRUE
		if("to_admins")
			if(!Q.to_admins(usr.client))
				notice = "[Q.initiator_key] isn't connected."
				notice_bad = TRUE
			return TRUE
		if("ticket")
			if(Q.ahelp_id && usr.client.holder)
				usr.client.open_tickets(Q.ahelp_id)
		if("follow")
			var/mob/M = Q.initiator?.mob
			if(M)
				usr.client.mentor_follow(M)
