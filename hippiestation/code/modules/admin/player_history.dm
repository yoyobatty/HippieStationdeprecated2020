// Player history: what each player did in earlier rounds on this server, kept in data/player_history/<ckey>.json with no
// database: the rounds they played (character, job, antagonist, alive at the end) and their tickets (title, how it ended, who
// handled it). The player profile (player_profile.dm) and the Tickets window show it. The user's tooling plan, stage 2
// (2026-11-07): ticket history across rounds.

#define PLAYER_HISTORY_ROUNDS 100
#define PLAYER_HISTORY_TICKETS 100

/// Where the files go (a check run points it elsewhere)
GLOBAL_VAR_INIT(player_history_dir, "data/player_history/")
/// This round as the history names it: the round ID with a database, else when it started
GLOBAL_VAR(player_history_round)

/proc/player_history_round()
	if(!GLOB.player_history_round)
		GLOB.player_history_round = GLOB.round_id ? "[GLOB.round_id]" : time2text(world.realtime, "YYYY-MM-DD hh:mm")
	return GLOB.player_history_round

/proc/player_history_read(player_ckey)
	player_ckey = ckey(player_ckey)
	var/path = "[GLOB.player_history_dir][player_ckey].json"
	var/list/H
	if(player_ckey && fexists(path))
		try
			H = json_decode(file2text(path))
		catch
			H = null
	if(!islist(H))
		H = list()
	if(!islist(H["rounds"]))
		H["rounds"] = list()
	if(!islist(H["tickets"]))
		H["tickets"] = list()
	return H

/proc/player_history_write(player_ckey, list/H)
	player_ckey = ckey(player_ckey)
	if(!player_ckey)
		return
	var/path = "[GLOB.player_history_dir][player_ckey].json"
	fdel(path)
	text2file(json_encode(H), path)

/// How a ticket ended, from its state and the lines that closed it
/datum/admin_help/proc/history_outcome()
	switch(state)
		if(AHELP_ACTIVE)
			return "open"
		if(AHELP_RESOLVED)
			for(var/list/M in ticket_messages)
				if(M["kind"] == "event" && findtext(M["text"], "Marked as IC issue") == 1)
					return "IC issue"
			return "resolved"
	for(var/list/M in ticket_messages)
		if(M["kind"] == "event" && findtext(M["text"], "Rejected by") == 1)
			return "rejected"
	return "closed"

/// Who closed, resolved or rejected it last
/datum/admin_help/proc/history_closed_by()
	var/static/regex/closing = new(@"^(?:Closed|Resolved|Rejected) by (.+?)\.?$")
	for(var/i in length(ticket_messages) to 1 step -1)
		var/list/M = ticket_messages[i]
		if(M["kind"] == "event" && closing.Find(M["text"]))
			return closing.group[1]

/// A ticket as kept: added, or brought up to date
/proc/ticket_history_save(datum/admin_help/AH)
	if(!AH?.initiator_ckey)
		return
	var/list/H = player_history_read(AH.initiator_ckey)
	var/list/tickets = H["tickets"]
	var/round = player_history_round()
	var/list/record
	for(var/list/T in tickets)
		if(T["round_id"] == round && T["id"] == AH.id)
			record = T
			break
	if(!record)
		record = list("round_id" = round, "id" = AH.id, "date" = time2text(world.realtime, "YYYY-MM-DD hh:mm"))
		tickets += list(record)
	var/said = 0
	var/first
	for(var/list/M in AH.ticket_messages)
		if(M["kind"] == "player" || M["kind"] == "admin")
			said++
			if(!first && M["kind"] == "player")
				first = copytext_char(M["text"], 1, 200)
	record["title"] = AH.name
	record["outcome"] = AH.history_outcome()
	record["handled_by"] = AH.claimed_key
	record["closed_by"] = AH.history_closed_by()
	record["messages"] = said
	record["first"] = first
	while(tickets.len > PLAYER_HISTORY_TICKETS)
		tickets.Cut(1, 2)
	player_history_write(AH.initiator_ckey, H)

/datum/admin_help/New(msg, client/C, is_bwoink)
	..()
	if(!QDELETED(src) && initiator_ckey)
		ticket_history_save(src)

/datum/admin_help/Close(key_name = key_name_admin(usr), silent = FALSE)
	var/was_open = state == AHELP_ACTIVE
	. = ..(key_name, silent)
	ticket_history_save(src)
	if(was_open && state != AHELP_ACTIVE)
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(ticket_send_transcript), src)

/datum/admin_help/Resolve(key_name = key_name_admin(usr), silent = FALSE)
	var/was_open = state == AHELP_ACTIVE
	. = ..(key_name, silent)
	ticket_history_save(src)
	if(was_open && state != AHELP_ACTIVE)
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(ticket_send_transcript), src)

/datum/admin_help/Reopen()
	. = ..()
	ticket_history_save(src)

/// At the end of the round, each player's round: who they were, what, and whether they lived. Bots aren't players.
/proc/player_history_round_end()
	var/round = player_history_round()
	var/date = time2text(world.realtime, "YYYY-MM-DD hh:mm")
	for(var/datum/mind/M in SSticker.minds)
		if(!M.key || M.bot_handle)
			continue
		var/mob/body = M.current
		if(body?.is_bot_crew())
			continue
		var/list/antags = list()
		for(var/datum/antagonist/A in M.antag_datums)
			antags |= A.name
		var/list/H = player_history_read(M.key)
		var/list/rounds = H["rounds"]
		rounds += list(list(
			"round_id" = round,
			"date" = date,
			"name" = M.name,
			"job" = M.assigned_role,
			"antag" = antags.len ? english_list(antags) : null,
			"end" = !body ? "gone" : (body.stat == DEAD ? "dead" : "alive"),
		))
		while(rounds.len > PLAYER_HISTORY_ROUNDS)
			rounds.Cut(1, 2)
		player_history_write(M.key, H)
		CHECK_TICK

/datum/controller/subsystem/ticker/declare_completion()
	. = ..()
	player_history_round_end()

#undef PLAYER_HISTORY_ROUNDS
#undef PLAYER_HISTORY_TICKETS
