// Tickets: every ahelp ticket in one window (tgui-next Tickets.js) instead of the ticket list pages and each ticket's own page.
// The user's tooling plan, stage 2 (2026-11-07): the ahelp comes with what happened around the player, for a bigger admin team
// with new admins. A ticket shows:
//	the conversation, with a box to reply in and saved replies to start from;
//	who's handling it (Claim, or the first admin to answer), and how long the player has been waiting for an answer;
//	the player: who they are now, what they are, who hurt them or whom they hurt lately, how new they are, notes, alt keys;
//	the round log lines about them, the people they named, and the room they asked from, from a few minutes before they asked;
//	the kills among them, with what an admin needs to judge one (antagonists, objectives, who struck first, Security) and a
//	warning when the player mustn't hear it (the user's ruling: only admins know a killer was a traitor);
//	notes only admins see, log lines quoted into a Ban or Note, and the conversation to Discord's admin channel when it's done.
// Under each new ahelp in admin chat goes a short line of the same: where, what, hurt by whom, how new, notes.
// The stat panel's ticket links, the #id links in chat and the Admin tab's Tickets verb open it.

#define TICKET_CONTEXT_MAX 200
#define TICKET_BRIEF_KEEP (30 SECONDS)

/datum/admin_help
	/// Who's handling it: Claim, or the first admin to answer
	var/claimed_ckey
	var/claimed_key
	/// The conversation as plain text: list(list("time", "kind" = player|admin|event, "who", "text"))
	var/list/ticket_messages = list()
	/// When the player wrote and no admin has answered since; null once answered
	var/waiting_since
	/// Where and who they were when they asked
	var/opened_area
	var/opened_x
	var/opened_y
	var/opened_z
	var/opened_name
	var/opened_job
	var/opened_antag
	/// The round log's line count then: the window marks where the ahelp falls among the lines
	var/opened_log_id = 0
	/// Mobs the player named in their messages (weakrefs), as keywords_lookup() finds them
	var/list/mentioned = list()

/datum/admin_help/New(msg, client/C, is_bwoink)
	..()
	if(QDELETED(src) || !initiator)
		return
	opened_log_id = GLOB.round_log_total
	var/mob/M = initiator.mob
	var/turf/T = get_turf(M)
	if(T)
		var/area/A = T.loc
		opened_area = A.name
		opened_x = T.x
		opened_y = T.y
		opened_z = T.z
	if(M && !isnewplayer(M))
		opened_name = M.real_name
		opened_job = M.mind?.assigned_role
		opened_antag = admin_antag_text(M)
	if(!is_bwoink)
		var/list/chips = ticket_chips(admin_player_brief(initiator_ckey))
		if(chips.len)
			var/list/bits = list()
			for(var/list/chip in chips)
				bits += chip["tone"] == "bad" ? "<b>[chip["text"]]</b>" : chip["text"]
			var/line = "<span class='adminnotice'>&nbsp;&nbsp;&nbsp;#[id]: [jointext(bits, " &middot; ")] [TicketHref("(TICKET)")]</span>"
			for(var/client/X in GLOB.admins)
				to_chat(X, line, confidential = TRUE)
	tickets_changed()

/datum/admin_help/AddInteraction(formatted_message)
	..()
	var/plain = ticket_plain_text(formatted_message)
	var/kind = "event"
	var/who
	var/text = plain
	var/player_prefix = "[ticket_plain_text(initiator_key_name)]: "
	if(findtext(plain, player_prefix) == 1)
		kind = "player"
		who = initiator_key_name
		text = copytext(plain, length(player_prefix) + 1)
	else
		var/static/list/prefixes = list("Reply PM from-" = "player", "PM From " = "admin", "PM from-" = "admin")
		for(var/prefix in prefixes)
			if(findtext(plain, prefix) != 1)
				continue
			var/colon = findtext(plain, ": ", length(prefix) + 1)
			if(colon)
				kind = prefixes[prefix]
				who = copytext(plain, length(prefix) + 1, colon)
				text = copytext(plain, colon + 2)
				var/to_whom = findtext(who, " to-") // admin to admin: "A to-B"
				if(to_whom)
					who = copytext(who, 1, to_whom)
			break
	var/list/entry = list("time" = world.time, "kind" = kind, "who" = who, "text" = text)
	if(kind == "admin" && usr?.client?.holder)
		entry["shown_as"] = usr.client.holder.fakekey || usr.key // what the player's own window calls them (help_window.dm)
	var/first_answer = kind == "admin" && !ticket_has_answer()
	ticket_messages += list(entry)
	if(first_answer && initiator && usr?.ckey != initiator_ckey)
		to_chat(initiator, "<span class='adminhelp'><a href='?help_window=1'>Your ticket</a> has the whole conversation, and a box to answer in.</span>", confidential = TRUE)
	switch(kind)
		if("player")
			if(!waiting_since)
				waiting_since = world.time
			for(var/mob/found in ahelp_named_mobs(text))
				mentioned |= WEAKREF(found)
		if("admin")
			waiting_since = null
			if(!claimed_ckey && usr?.client?.holder && usr.ckey != initiator_ckey)
				claim(usr.client, TRUE)
	tickets_changed()

/// Whether an admin has answered yet
/datum/admin_help/proc/ticket_has_answer()
	for(var/list/M in ticket_messages)
		if(M["kind"] == "admin")
			return TRUE
	return FALSE

/// The ticket's own page and the ticket lists both open the window now
/datum/admin_help/TicketPanel()
	usr?.client?.open_tickets(id, null, TRUE) // chat's #id links and the stat panel: the admin hub (admin_hub.dm)

/datum/admin_help_tickets/BrowseTickets(state)
	usr?.client?.open_tickets(null, state, TRUE)

/datum/admin_help/proc/claim(client/C, silent = FALSE)
	if(state != AHELP_ACTIVE || !C)
		return
	claimed_ckey = C.ckey
	claimed_key = C.key
	AddInteraction("Claimed by [key_name_admin(C)]")
	log_admin_private("Ticket #[id] claimed by [key_name(C)].")
	if(silent)
		return
	message_admins("Ticket [TicketHref("#[id]")] claimed by [key_name_admin(C)].")
	if(initiator)
		to_chat(initiator, "<span class='adminhelp'>An admin is handling your ticket.</span>", confidential = TRUE)

/datum/admin_help/proc/unclaim(client/C)
	if(!claimed_ckey)
		return
	claimed_ckey = null
	claimed_key = null
	AddInteraction("Unclaimed by [key_name_admin(C)]")
	message_admins("Ticket [TicketHref("#[id]")] unclaimed by [key_name_admin(C)].")

/datum/admin_help/proc/set_title(new_title)
	new_title = copytext_char(trim(sanitize(new_title)), 1, MAX_MESSAGE_LEN)
	if(!new_title || new_title == name)
		return
	name = new_title
	var/msg = "Ticket [TicketHref("#[id]")] titled [name] by [key_name_admin(usr)]"
	message_admins(msg)
	log_admin_private(msg)
	tickets_changed()

/// Round log lines about the player, the people they named, the room they asked from (before they asked), what they saw (fights,
/// deaths, bombs they could see) and what was said within earshot of them (whereabouts.dm), oldest first
/datum/admin_help/proc/context_entries(minutes_before, show_player, show_named, show_area, show_seen, show_heard)
	. = list()
	var/list/heard_from = list() // snapshot index = where they were then
	var/since = opened_at - minutes_before MINUTES
	var/list/refs = list()
	var/list/ckeys = list()
	if(show_named)
		for(var/datum/weakref/W in mentioned)
			refs[W] = TRUE
			var/mob/M = W.resolve()
			if(M?.ckey && M.ckey != initiator_ckey)
				ckeys[M.ckey] = TRUE
	var/list/log = GLOB.round_log
	for(var/i in log.len to 1 step -1)
		var/list/entry = log[i]
		if(entry[RL_TIME] < since)
			break
		var/actor_ckey = entry[RL_CKEY]
		var/target_ckey = entry[RL_TCKEY]
		var/hit = FALSE
		if(show_player && (actor_ckey == initiator_ckey || target_ckey == initiator_ckey))
			hit = TRUE
		else if(show_named && ((actor_ckey && ckeys[actor_ckey]) || (target_ckey && ckeys[target_ckey]) || (entry[RL_REF] && refs[entry[RL_REF]]) || (entry[RL_TREF] && refs[entry[RL_TREF]])))
			hit = TRUE
		else if(show_area && opened_area && entry[RL_ID] <= opened_log_id && entry[RL_AREA] == opened_area)
			hit = TRUE
		else if(show_seen && entry[RL_SEEN])
			for(var/list/witness in entry[RL_SEEN])
				if(witness[1] == initiator_ckey)
					hit = TRUE
					break
		if(!hit && show_heard && entry[RL_Z] && (entry[RL_CAT] == "Say" || entry[RL_CAT] == "Whisper" || entry[RL_CAT] == "Emote"))
			var/index = SSwhereabouts.nearest(entry[RL_TIME])
			if(!heard_from.Find("[index]"))
				heard_from["[index]"] = SSwhereabouts.position_of(initiator_ckey, entry[RL_TIME]) || FALSE
			var/list/pos = heard_from["[index]"]
			var/reach = entry[RL_CAT] == "Whisper" ? 2 : 7
			if(islist(pos) && pos[3] == entry[RL_Z] && abs(pos[1] - entry[RL_X]) <= reach && abs(pos[2] - entry[RL_Y]) <= reach)
				hit = TRUE
		if(hit)
			. += list(entry)
			if(length(.) >= TICKET_CONTEXT_MAX)
				break
		if(!(i % 2000))
			CHECK_TICK
	reverseRange(.)

/// What changed in tickets: the windows redraw
/proc/tickets_changed()
	for(var/datum/ticket_window/W in GLOB.ticket_windows)
		if(!W.owner) // its admin left; a new connection makes a new one
			qdel(W)
			continue
		SStgui.update_uis(W)

/// An interaction line as text: no tags, no keywords_lookup "(?|F)" links
/proc/ticket_plain_text(text)
	var/static/regex/tags = new("<\[^>\]*>", "g")
	var/static/regex/lookups = new(@"\(\?\|F\)", "g")
	text = tags.Replace("[text]", "")
	text = lookups.Replace(text, "")
	return trim(html_decode(text))

/// The mobs a message names, the way keywords_lookup() finds them for the (?|F) links: ckeys, surnames, then first names
/proc/ahelp_named_mobs(msg)
	. = list()
	var/static/list/ignored = list("unknown", "the", "a", "an", "of", "monkey", "alien", "as", "i", "ai")
	var/list/words = list()
	for(var/word in splittext(msg, " "))
		word = ckey(word)
		if(word && !(word in ignored) && isnull(text2num(word))) // "#2" isn't anyone: "MULEbot #2" was named by "Question #2"
			words[word] = TRUE
	if(!words.len)
		return
	var/list/surnames = list()
	var/list/forenames = list()
	var/list/ckeys = list()
	for(var/mob/M in GLOB.mob_list)
		var/list/indexing = list(M.real_name, M.name)
		if(M.mind)
			indexing += M.mind.name
		for(var/string in indexing)
			var/list/L = splittext(string, " ")
			var/surname_found = 0
			for(var/i in L.len to 1 step -1)
				var/word = ckey(L[i])
				if(word && isnull(text2num(word)))
					surnames[word] = M
					surname_found = i
					break
			for(var/i in 1 to surname_found - 1)
				var/word = ckey(L[i])
				if(word)
					forenames[word] = M
		if(M.ckey)
			ckeys[M.ckey] = M
	for(var/word in words)
		var/mob/found = ckeys[word] || surnames[word] || forenames[word]
		if(found)
			. |= found

/// "Traitor", "Changeling and Brother", or null
/proc/admin_antag_text(mob/M)
	if(!M?.mind)
		return null
	var/list/names = list()
	for(var/datum/antagonist/A in M.mind.antag_datums)
		names |= A.name
	if(!names.len && M.mind.special_role)
		names += M.mind.special_role
	return names.len ? english_list(names) : null

/proc/admin_mob_state(mob/M)
	if(!M)
		return "gone"
	if(isnewplayer(M))
		return "lobby"
	if(isobserver(M))
		return "ghost"
	if(isliving(M))
		var/mob/living/L = M
		switch(L.stat)
			if(DEAD)
				return "dead"
			if(UNCONSCIOUS)
				return "unconscious"
			if(SOFT_CRIT)
				return "critical"
	return "alive"

/// Who hurt this mob most lately, and whom it hurt, from the round log: list("by", "by_ago", "on", "on_ago")
/proc/round_log_recent_hurt(mob/M, player_ckey, window = 3 MINUTES)
	. = list()
	var/datum/weakref/mine = M?.weak_reference
	var/since = world.time - window
	var/list/log = GLOB.round_log
	for(var/i in log.len to max(1, log.len - 5000) step -1)
		var/list/entry = log[i]
		if(entry[RL_TIME] < since)
			break
		if(entry[RL_CAT] != "Attack")
			continue
		var/is_me = (player_ckey && entry[RL_CKEY] == player_ckey) || (mine && entry[RL_REF] == mine)
		var/on_me = (player_ckey && entry[RL_TCKEY] == player_ckey) || (mine && entry[RL_TREF] == mine)
		if(on_me && !is_me && !.["by"])
			.["by"] = "[entry[RL_NAME]][entry[RL_CKEY] ? " ([entry[RL_CKEY]])" : ""]"
			.["by_ago"] = world.time - entry[RL_TIME]
		else if(is_me && !on_me && !.["on"] && (entry[RL_TNAME] || entry[RL_TCKEY]))
			.["on"] = "[entry[RL_TNAME]][entry[RL_TCKEY] ? " ([entry[RL_TCKEY]])" : ""]"
			.["on_ago"] = world.time - entry[RL_TIME]
		if(.["by"] && .["on"])
			break

/// "40 s", "3 min", "2 h"
/proc/ticket_ago_text(deciseconds)
	var/seconds = round(deciseconds / 10)
	if(seconds < 60)
		return "[seconds] s"
	if(seconds < 3600)
		return "[round(seconds / 60)] min"
	return "[round(seconds / 3600)] h"

/// What's known about a player, for the ticket and the player profile: online or not, what they are, how long they've been
/// coming here, notes, alt keys. Reads the notes ledger (and the database when it's on): don't call it every redraw.
/proc/admin_player_brief(player_ckey)
	player_ckey = ckey(player_ckey)
	var/list/B = list("ckey" = player_ckey, "key" = note_key_of(player_ckey))
	var/client/C = GLOB.directory[player_ckey]
	var/mob/M = C?.mob
	if(!M)
		for(var/mob/candidate in GLOB.mob_list)
			if(candidate.ckey == player_ckey)
				M = candidate
				break
	B["online"] = !!C
	B["state"] = admin_mob_state(M)
	if(M && !isnewplayer(M))
		B["name"] = M.real_name
		B["job"] = M.mind?.assigned_role
		B["antag"] = admin_antag_text(M)
		var/area/A = get_area(M)
		B["area"] = A?.name
	B["hurt"] = round_log_recent_hurt(M, player_ckey)
	var/list/seen = SSbans.seen[player_ckey]
	if(seen)
		var/first = text2num(seen["first"])
		if(first)
			B["first_days"] = round((world.realtime - first) / 864000)
		B["connections"] = seen["count"]
	var/list/same_computer = list()
	for(var/other in SSbans.seen_sharing(player_ckey, "cids"))
		same_computer += note_key_of(other)
	B["same_computer"] = same_computer
	var/list/notes = SSnotes.rows_for(player_ckey)
	B["note_count"] = length(notes)
	var/static/list/severity_rank = list("none" = 1, "minor" = 2, "medium" = 3, "high" = 4)
	var/top
	for(var/list/N in notes)
		if(N["severity"] && severity_rank[N["severity"]] > severity_rank[top])
			top = N["severity"]
	B["note_severity"] = top
	B["notes"] = length(notes) > 3 ? notes.Copy(1, 4) : notes
	var/list/role_bans = list()
	for(var/datum/ban_record/R in SSbans.role_ban_records(player_ckey))
		if(R.is_active() && lowertext(R.role) != "server")
			role_bans |= R.role
	B["role_bans"] = role_bans
	var/list/history = player_history_read(player_ckey)
	var/round = player_history_round()
	var/past = 0
	for(var/list/T in history["tickets"])
		if(T["round_id"] != round)
			past++
	B["past_tickets"] = past
	return B

/// The brief as a few short chips: list(list("text", "tone" = bad|warn|info))
/proc/ticket_chips(list/B)
	. = list()
	if(!B)
		return
	if(B["area"])
		. += list(list("text" = B["area"], "tone" = "info"))
	if(B["job"])
		. += list(list("text" = B["job"], "tone" = "info"))
	if(B["antag"])
		. += list(list("text" = B["antag"], "tone" = "bad"))
	if(B["state"] != "alive")
		. += list(list("text" = B["state"], "tone" = B["state"] == "dead" || B["state"] == "critical" ? "bad" : "info"))
	var/list/hurt = B["hurt"]
	if(hurt["by"])
		. += list(list("text" = "hurt by [hurt["by"]] [ticket_ago_text(hurt["by_ago"])] ago", "tone" = "warn"))
	if(hurt["on"])
		. += list(list("text" = "hurt [hurt["on"]] [ticket_ago_text(hurt["on_ago"])] ago", "tone" = "warn"))
	if(!isnull(B["first_days"]) && B["first_days"] < 7)
		. += list(list("text" = "first seen [B["first_days"] < 1 ? "today" : "[B["first_days"]] d ago"]", "tone" = "warn"))
	if(B["note_count"])
		. += list(list("text" = "[B["note_count"]] note[B["note_count"] == 1 ? "" : "s"][B["note_severity"] && B["note_severity"] != "none" ? " ([B["note_severity"]])" : ""]", "tone" = "warn"))
	var/list/same_computer = B["same_computer"]
	if(length(same_computer))
		. += list(list("text" = "[same_computer.len] other key[same_computer.len == 1 ? "" : "s"] on this computer", "tone" = "warn"))
	var/list/role_bans = B["role_bans"]
	if(length(role_bans))
		. += list(list("text" = "role-banned: [english_list(role_bans)]", "tone" = "warn"))
	if(B["past_tickets"])
		. += list(list("text" = "[B["past_tickets"]] past ticket[B["past_tickets"] == 1 ? "" : "s"]", "tone" = B["past_tickets"] >= 3 ? "warn" : "info"))

/// A note on the ticket that only admins see: the player never does
/datum/admin_help/proc/add_note(client/C, text)
	text = copytext_char(trim("[text]"), 1, MAX_MESSAGE_LEN)
	if(!text || !C)
		return
	ticket_messages += list(list("time" = world.time, "kind" = "note", "who" = C.key, "text" = text))
	_interactions += "[time_stamp()]: <font color='gray'>Admin note by [key_name_admin(C)]: [html_encode(text)]</font>"
	log_admin_private("Ticket #[id] note by [key_name(C)]: [text]")
	message_admins("Ticket [TicketHref("#[id]")] note by [key_name_admin(C)]: [html_encode(text)]")
	tickets_changed()

/// The conversation, once the ticket's done, to Discord's admin channels (through TGS): notes too, they're admin channels
/proc/ticket_send_transcript(datum/admin_help/AH)
	if(!AH || !world.TgsAvailable())
		return
	var/closed_by = AH.history_closed_by()
	var/list/lines = list("Ticket #[AH.id] [AH.history_outcome()][closed_by ? " by [closed_by]" : ""] - [AH.initiator_key_name]: [AH.name]")
	for(var/list/M in AH.ticket_messages)
		if(M["kind"] == "event")
			continue
		lines += "[log_search_clock(M["time"])] [M["kind"] == "note" ? "(note) " : ""][M["who"] || M["kind"]]: [M["text"]]"
	var/text = jointext(lines, "\n")
	if(length(text) > 1900)
		text = copytext(text, 1, 1880) + "\n(cut short)"
	world.TgsTargetedChatBroadcast(new /datum/tgs_message_content(text), TRUE)

/// One side of a kill, for admins: what they are, their objectives, whether they're Security, wanted or cuffed
/proc/kill_side(mob/living/M, name, side_ckey)
	var/list/S = list("name" = name, "ckey" = side_ckey, "ref" = M ? REF(M) : null, "mob" = !!M)
	var/datum/mind/mind = M?.mind
	if(!mind && side_ckey)
		var/mob/now = mob_of_ckey(side_ckey)
		mind = now?.mind
	if(!M && !mind)
		return S
	S["job"] = mind?.assigned_role
	var/list/antags = list()
	if(mind)
		for(var/datum/antagonist/A in mind.antag_datums)
			antags |= A.name
		if(!antags.len && mind.special_role)
			antags += mind.special_role
	S["antag"] = antags.len ? english_list(antags) : null
	S["bot"] = M?.is_bot_crew()
	var/list/objectives = list()
	if(mind)
		for(var/datum/objective/O in mind.get_all_objectives())
			objectives += O.explanation_text
	S["objectives"] = objectives
	S["security"] = (S["job"] in GLOB.security_positions)
	var/datum/data/record/R = find_record("name", M ? M.real_name : name, GLOB.data_core.security)
	if(R && R.fields["criminal"] && R.fields["criminal"] != "None")
		S["wanted"] = R.fields["criminal"]
	if(iscarbon(M))
		var/mob/living/carbon/C = M
		S["cuffed"] = !!C.handcuffed
	return S

/// A death and the hit that did it, as admins judge it: both sides, who struck first, and the reasons it could be fair
/proc/kill_record(list/death, list/kill, index)
	var/datum/weakref/victim_ref = death[RL_REF]
	var/datum/weakref/killer_ref = kill ? kill[RL_REF] : null
	var/mob/living/victim = victim_ref?.resolve()
	var/mob/living/killer = killer_ref?.resolve()
	var/list/R = list("id" = death[RL_ID], "time" = log_search_clock(death[RL_TIME]), "area" = death[RL_AREA], "how" = kill ? kill[RL_TEXT] : null, "seen" = round_log_seen_text(kill || death))
	var/list/V = kill_side(victim, death[RL_NAME], death[RL_CKEY])
	var/list/K = kill ? kill_side(killer, kill[RL_NAME], kill[RL_CKEY]) : null
	R["victim"] = V
	R["killer"] = K
	if(!kill)
		R["reasons"] = list()
		return R
	// who struck first, between the two, in the three minutes before
	var/first
	var/list/log = GLOB.round_log
	var/since = death[RL_TIME] - 3 MINUTES
	for(var/i in index - 1 to max(1, index - 3000) step -1)
		var/list/entry = log[i]
		if(entry[RL_TIME] < since)
			break
		if(entry[RL_CAT] != "Attack")
			continue
		if(entry[RL_REF] == killer_ref && entry[RL_TREF] == victim_ref)
			first = "killer"
		else if(entry[RL_REF] == victim_ref && entry[RL_TREF] == killer_ref)
			first = "victim"
	R["first"] = first
	var/list/reasons = list()
	var/datum/mind/victim_mind = victim?.mind
	if(!victim_mind && death[RL_CKEY])
		var/mob/now = mob_of_ckey(death[RL_CKEY])
		victim_mind = now?.mind
	if(K["antag"])
		var/target = FALSE
		if(killer?.mind && victim_mind)
			for(var/datum/objective/O in killer.mind.get_all_objectives())
				if(O.target == victim_mind)
					target = TRUE
		reasons += target ? "the dead one is their objective target" : "the killer is a [K["antag"]]"
	if(V["antag"])
		reasons += "the dead one was a [V["antag"]]"
	if(K["security"] && V["wanted"])
		reasons += "Security, and the dead one was set to [V["wanted"]]"
	if(first == "victim")
		reasons += "the dead one struck first"
	R["reasons"] = reasons
	return R

/// Kills since a time where the dead or the killer is one of these players or mobs, newest first
/proc/kill_records(list/ckeys, list/refs, since, limit = 4)
	. = list()
	var/list/log = GLOB.round_log
	for(var/i in log.len to 1 step -1)
		var/list/entry = log[i]
		if(entry[RL_TIME] < since)
			break
		if(entry[RL_CAT] != "Death" || !entry[RL_CKEY])
			continue
		var/list/kill = SSadmin_alerts.killing_blow(entry, i)
		var/involved = ckeys[entry[RL_CKEY]] || (entry[RL_REF] && refs[entry[RL_REF]])
		if(kill && !involved)
			involved = (kill[RL_CKEY] && ckeys[kill[RL_CKEY]]) || (kill[RL_REF] && refs[kill[RL_REF]])
		if(!involved)
			continue
		. += list(kill_record(entry, kill, i))
		if(length(.) >= limit)
			break

////////////////////
// Saved replies
////////////////////

GLOBAL_LIST(ahelp_replies)
/// Where saved replies are kept (a check run points it elsewhere)
GLOBAL_VAR_INIT(ahelp_replies_path, "data/ahelp_replies.json")

/// Saved replies, title = text: the file's, or a few to start with
/proc/ahelp_replies()
	if(GLOB.ahelp_replies)
		return GLOB.ahelp_replies
	if(fexists(GLOB.ahelp_replies_path))
		var/list/loaded
		try
			loaded = json_decode(file2text(GLOB.ahelp_replies_path))
		catch
			loaded = null
		if(islist(loaded))
			GLOB.ahelp_replies = loaded
			return loaded
	GLOB.ahelp_replies = list(
		"Details" = "Who did it, where, and when? Names help.",
		"Looking" = "Looking into it.",
		"IC" = "That's an IC issue. Deal with it in character: Security, the heads of staff, or the AI.",
		"Not a rule break" = "That isn't against the rules.",
		"Bug" = "Sounds like a bug. Report it on the GitHub issue tracker: what you did, and what happened.",
		"Appeals" = "Ban appeals go on the forum, not in ahelps.",
	)
	return GLOB.ahelp_replies

/proc/ahelp_replies_save()
	fdel(GLOB.ahelp_replies_path)
	text2file(json_encode(GLOB.ahelp_replies), GLOB.ahelp_replies_path)


////////////////////
// The window
////////////////////

GLOBAL_LIST_EMPTY(ticket_windows)

/client/var/datum/ticket_window/ticket_window

/client/proc/cmd_tickets()
	set name = "Tickets"
	set category = "Admin"
	set desc = "Every ahelp this round, with what happened around the player."
	if(!check_rights(R_ADMIN))
		return
	open_tickets()

/client/proc/open_tickets(ticket_id, state, via_hub)
	if(!holder)
		return
	if(!ticket_window)
		ticket_window = new
		ticket_window.owner = src
	if(hub_wants(via_hub))
		ticket_window.open(mob, ticket_id, state, FALSE)
		open_admin_hub("tickets")
		return
	ticket_window.open(mob, ticket_id, state)

/datum/ticket_window
	var/client/owner
	/// Open, Resolved or Closed tickets listed
	var/list_state = AHELP_ACTIVE
	var/selected_id
	var/notice
	var/notice_bad = FALSE
	/// The context lines: minutes before the ahelp, and whose lines
	var/context_minutes = 5
	var/show_player = TRUE
	var/show_named = TRUE
	var/show_area = FALSE
	var/show_seen = TRUE
	var/show_heard = FALSE
	/// The Map tab: open, the time picked on it (null: the ahelp's), the level, and whether to send the level's map next time
	var/map_open = FALSE
	var/map_time
	var/map_z
	var/map_send = FALSE
	var/list/context_rows
	var/list/kills
	var/context_for
	var/context_total = -1
	var/context_time = 0
	var/layout_loaded = FALSE
	/// The player's brief, kept a while (it reads notes)
	var/list/brief
	var/brief_for
	var/brief_time = 0
	/// Round log lines quoted into a Ban or Note: ticket id = list(line ids)
	var/list/quotes = list()

/datum/ticket_window/New()
	GLOB.ticket_windows += src

/datum/ticket_window/Destroy()
	GLOB.ticket_windows -= src
	owner = null
	return ..()

/datum/ticket_window/proc/open(mob/user, ticket_id, state, show = TRUE)
	notice = null
	if(ticket_id)
		var/datum/admin_help/AH = GLOB.ahelp_tickets.TicketByID(ticket_id)
		if(AH)
			selected_id = AH.id
			list_state = AH.state
	else if(state)
		list_state = state
	if(show)
		ui_interact(user)

/datum/ticket_window/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.admin_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "tickets", "Tickets", 1180, 720, master_ui, state)
		ui.open()

/datum/ticket_window/proc/say(text, bad = FALSE)
	notice = text
	notice_bad = bad

/datum/ticket_window/proc/tickets_in(state)
	switch(state)
		if(AHELP_ACTIVE)
			return GLOB.ahelp_tickets.active_tickets
		if(AHELP_CLOSED)
			return GLOB.ahelp_tickets.closed_tickets
		if(AHELP_RESOLVED)
			return GLOB.ahelp_tickets.resolved_tickets
	return list()

/datum/ticket_window/proc/selected()
	if(!selected_id)
		return null
	return GLOB.ahelp_tickets.TicketByID(selected_id)

/datum/ticket_window/proc/ticket_row(datum/admin_help/AH)
	var/list/last = length(AH.ticket_messages) ? AH.ticket_messages[AH.ticket_messages.len] : null
	return list(
		"id" = AH.id,
		"state" = AH.state,
		"title" = AH.name,
		"kind" = GLOB.help_kinds[AH.help_kind],
		"key" = AH.initiator_key_name,
		"name" = AH.opened_name,
		"job" = AH.opened_job,
		"antag" = AH.opened_antag,
		"online" = !!AH.initiator,
		"opened" = log_search_clock(AH.opened_at),
		"age" = ticket_ago_text(world.time - AH.opened_at),
		"waiting" = AH.state == AHELP_ACTIVE && AH.waiting_since ? ticket_ago_text(world.time - AH.waiting_since) : null,
		"wait_ds" = AH.state == AHELP_ACTIVE && AH.waiting_since ? world.time - AH.waiting_since : 0,
		"waiting_long" = AH.state == AHELP_ACTIVE && AH.waiting_since && world.time - AH.waiting_since > 2 MINUTES,
		"claimed" = AH.claimed_key,
		"mine" = !!owner && AH.claimed_ckey == owner.ckey,
		"last" = last ? "[last["who"] ? "[last["kind"] == "admin" ? "Admin" : "Player"]: " : ""][last["text"]]" : null,
	)

/// The list as the window shows it
/datum/ticket_window/proc/shown_rows()
	. = list()
	for(var/datum/admin_help/AH in tickets_in(list_state))
		. += list(ticket_row(AH))
	sortTim(., GLOBAL_PROC_REF(cmp_ticket_rows))

/// Each admin's context choices, kept across rounds (admin_hub.dm)
/datum/ticket_window/proc/load_layout()
	layout_loaded = TRUE
	var/list/L = admin_layout(owner?.ckey)["tickets_context"]
	if(!islist(L))
		return
	if(L["minutes"] in list(2, 5, 15, 30))
		context_minutes = L["minutes"]
	show_player = !!L["player"]
	show_named = !!L["named"]
	show_area = !!L["area"]
	show_seen = !!L["seen"]
	show_heard = !!L["heard"]

/datum/ticket_window/proc/save_layout()
	admin_layout_set(owner?.ckey, "tickets_context", list("minutes" = context_minutes, "player" = show_player, "named" = show_named, "area" = show_area, "seen" = show_seen, "heard" = show_heard))

/proc/cmp_ticket_rows(list/a, list/b)
	if(!!a["wait_ds"] != !!b["wait_ds"])
		return a["wait_ds"] ? -1 : 1
	if(a["wait_ds"])
		return b["wait_ds"] - a["wait_ds"]
	return b["id"] - a["id"]

/datum/ticket_window/ui_data(mob/user)
	if(!layout_loaded && owner)
		load_layout()
	var/list/rows = list()
	var/open_questions = 0
	for(var/datum/help_question/Q in GLOB.help_questions)
		if(Q.open)
			open_questions++
			if(list_state == 0)
				rows += list(list(
					"id" = Q.id,
					"question" = TRUE,
					"state" = AHELP_ACTIVE,
					"title" = Q.name,
					"key" = Q.initiator_key,
					"online" = !!Q.initiator,
					"age" = ticket_ago_text(world.time - Q.opened_at),
					"waiting" = Q.waiting_since ? ticket_ago_text(world.time - Q.waiting_since) : null,
					"wait_ds" = Q.waiting_since ? world.time - Q.waiting_since : 0,
					"waiting_long" = Q.waiting_since && world.time - Q.waiting_since > 2 MINUTES,
					"claimed" = Q.claimed_key,
					"mine" = !!owner && Q.claimed_ckey == owner.ckey,
				))
	for(var/datum/admin_help/AH in tickets_in(list_state))
		rows += list(ticket_row(AH))
	sortTim(rows, GLOBAL_PROC_REF(cmp_ticket_rows))
	var/list/data = list(
		"list_state" = list_state,
		"counts" = list(
			"[AHELP_ACTIVE]" = length(GLOB.ahelp_tickets.active_tickets),
			"[AHELP_RESOLVED]" = length(GLOB.ahelp_tickets.resolved_tickets),
			"[AHELP_CLOSED]" = length(GLOB.ahelp_tickets.closed_tickets),
			"0" = open_questions,
		),
		"tickets" = rows,
		"notice" = notice,
		"notice_bad" = notice_bad,
		"replies" = ahelp_replies(),
		"me" = owner?.key,
		"round_time" = log_search_clock(world.time),
	)
	var/datum/admin_help/AH = selected()
	if(AH)
		data["ticket"] = ticket_data(AH)
	return data

/datum/ticket_window/proc/ticket_data(datum/admin_help/AH)
	var/list/messages = list()
	for(var/list/M in AH.ticket_messages)
		messages += list(list("time" = log_search_clock(M["time"]), "kind" = M["kind"], "who" = M["who"], "text" = M["text"]))
	if(brief_for != AH.id || world.time > brief_time + TICKET_BRIEF_KEEP)
		brief = admin_player_brief(AH.initiator_ckey)
		brief_for = AH.id
		brief_time = world.time
	var/context_key = "[AH.id]|[context_minutes]|[show_player][show_named][show_area][show_seen][show_heard]"
	if(context_key != context_for || (context_total != GLOB.round_log_total && world.time > context_time + 2 SECONDS))
		context_rows = list()
		for(var/list/entry in AH.context_entries(context_minutes, show_player, show_named, show_area, show_seen, show_heard))
			context_rows += list(round_log_row(entry))
		var/list/kill_ckeys = list()
		kill_ckeys[AH.initiator_ckey] = TRUE
		var/list/kill_refs = list()
		for(var/datum/weakref/W in AH.mentioned)
			kill_refs[W] = TRUE
			var/mob/named_mob = W.resolve()
			if(named_mob?.ckey)
				kill_ckeys[named_mob.ckey] = TRUE
		kills = kill_records(kill_ckeys, kill_refs, AH.opened_at - 30 MINUTES)
		context_for = context_key
		context_total = GLOB.round_log_total
		context_time = world.time
	var/list/named = list()
	for(var/i in 1 to length(AH.mentioned))
		var/datum/weakref/W = AH.mentioned[i]
		var/mob/M = W.resolve()
		if(!M)
			continue
		named += list(list("index" = i, "ref" = REF(M), "name" = M.real_name || M.name, "ckey" = M.ckey, "job" = M.mind?.assigned_role, "antag" = admin_antag_text(M), "state" = admin_mob_state(M), "bot" = M.is_bot_crew()))
	var/list/notes = list()
	for(var/list/N in brief["notes"])
		notes += list(list("kind" = N["kind"], "text" = N["text"], "admin" = N["admin_key"], "severity" = N["severity"], "age_days" = N["age_days"]))
	return list(
		"id" = AH.id,
		"state" = AH.state,
		"title" = AH.name,
		"kind" = GLOB.help_kinds[AH.help_kind],
		"key" = AH.initiator_key_name,
		"ckey" = AH.initiator_ckey,
		"online" = !!AH.initiator,
		"opened" = log_search_clock(AH.opened_at),
		"age" = ticket_ago_text(world.time - AH.opened_at),
		"closed" = AH.closed_at ? log_search_clock(AH.closed_at) : null,
		"claimed" = AH.claimed_key,
		"mine" = !!owner && AH.claimed_ckey == owner.ckey,
		"waiting" = AH.state == AHELP_ACTIVE && AH.waiting_since ? ticket_ago_text(world.time - AH.waiting_since) : null,
		"opened_where" = AH.opened_area ? "[AH.opened_area] ([AH.opened_x], [AH.opened_y], [AH.opened_z])" : null,
		"opened_name" = AH.opened_name,
		"opened_job" = AH.opened_job,
		"opened_antag" = AH.opened_antag,
		"messages" = messages,
		"player" = list(
			"who" = player_link(ticket_mob(AH), AH.initiator_ckey, brief["name"] || AH.initiator_key_name),
			"name" = brief["name"],
			"job" = brief["job"],
			"state" = brief["state"],
			"area" = brief["area"],
			"chips" = ticket_chips(brief),
			"notes" = notes,
			"note_count" = brief["note_count"],
			"same_computer" = brief["same_computer"],
			"first_days" = brief["first_days"],
			"connections" = brief["connections"],
			"has_mob" = !!ticket_mob(AH),
		),
		"named" = named,
		"context" = context_rows,
		"context_minutes" = context_minutes,
		"show_player" = show_player,
		"show_named" = show_named,
		"show_area" = show_area,
		"show_seen" = show_seen,
		"show_heard" = show_heard,
		"map_open" = map_open,
		"whereabouts" = map_open ? map_data(AH, named) : null,
		"opened_log_id" = AH.opened_log_id,
		"kills" = kills,
		"secret_warning" = secret_warning(AH, named),
		"quoted" = quotes["[AH.id]"] || list(),
	)

/// The Map tab: everyone on the level at the picked time, the player and the people they named picked out
/datum/ticket_window/proc/map_data(datum/admin_help/AH, list/named)
	var/list/snapshots = SSwhereabouts.snapshots
	if(!snapshots.len)
		return list("none" = TRUE)
	var/oldest = max(snapshots[1][1], AH.opened_at - 15 MINUTES)
	var/newest = snapshots[snapshots.len][1]
	var/at = clamp(isnull(map_time) ? AH.opened_at : map_time, oldest, newest)
	var/index = SSwhereabouts.nearest(at)
	var/z = map_z
	if(!z)
		var/list/pos = SSwhereabouts.position_of(AH.initiator_ckey, at)
		z = pos ? pos[3] : (AH.opened_z || SSmapping.station_start)
	var/list/named_ckeys = list()
	for(var/list/N in named)
		if(N["ckey"])
			named_ckeys[N["ckey"]] = TRUE
	var/list/dots = list()
	for(var/list/D in SSwhereabouts.dots(index, z))
		D["role"] = D["ckey"] == AH.initiator_ckey ? "player" : (named_ckeys[D["ckey"]] ? "named" : "other")
		dots += list(D)
	var/list/levels = list()
	for(var/level in SSmapping.levels_by_trait(ZTRAIT_STATION))
		levels += level
	var/list/data = list(
		"z" = z,
		"levels" = levels,
		"t" = snapshots[index][1],
		"time" = log_search_clock(snapshots[index][1]),
		"min" = oldest,
		"max" = newest,
		"ahelp_t" = AH.opened_at,
		"dots" = dots,
	)
	if(map_send)
		map_send = FALSE
		data["map"] = crew_monitor_map(z)
	return data

/// What the player mustn't be told (the user's ruling, 2026-11-07): their killer was an antagonist, or, once they're dead, that
/// someone they named is one. Shown to the admin above the reply box.
/datum/ticket_window/proc/secret_warning(datum/admin_help/AH, list/named)
	for(var/list/K in kills)
		var/list/victim = K["victim"]
		var/list/killer = K["killer"]
		if(victim["ckey"] == AH.initiator_ckey && killer && killer["antag"])
			return "Their killer, [killer["name"]], is a [killer["antag"]]. Don't tell them, or anything that gives it away."
	var/mob/M = ticket_mob(AH)
	var/state = admin_mob_state(M)
	if(state == "dead" || state == "ghost")
		for(var/list/N in named)
			if(N["antag"])
				return "[N["name"]] is a [N["antag"]]. They're dead: don't confirm it to them."

/// "Ticket #3: title", then the quoted lines, oldest first: a Ban's reason or a Note's text
/datum/ticket_window/proc/quote_text(datum/admin_help/AH)
	var/list/lines = list("Ticket #[AH.id]: [AH.name]")
	var/list/quoted = quotes["[AH.id]"]
	var/list/ids = quoted ? quoted.Copy() : list()
	sortTim(ids, GLOBAL_PROC_REF(cmp_numeric_asc))
	for(var/id in ids)
		var/list/entry = round_log_entry(id)
		if(entry)
			lines += "[log_search_clock(entry[RL_TIME])] [entry[RL_TEXT]]"
	return jointext(lines, "\n")

/// The player's mob now, connected or not
/datum/ticket_window/proc/ticket_mob(datum/admin_help/AH)
	if(AH.initiator)
		return AH.initiator.mob
	for(var/mob/M in GLOB.mob_list)
		if(M.ckey == AH.initiator_ckey)
			return M

/// The admin buttons on a mob: player panel, variables, follow, subtle message, jump
/datum/ticket_window/proc/mob_act(what, mob/M, mob/user)
	if(!M || !user.client?.holder)
		return
	switch(what)
		if("pp")
			user.client.holder.show_player_panel(M)
		if("vv")
			user.client.debug_variables(M)
		if("flw")
			if(isobserver(user) || user.client.admin_ghost())
				var/mob/dead/observer/ghost = user.client.mob
				ghost.ManualFollow(M)
		if("sm")
			user.client.cmd_admin_subtle_message(M)
		if("jmp")
			user.client.jumptomob(M)

/datum/ticket_window/ui_act(action, list/params)
	if(..())
		return
	if(!check_rights(R_ADMIN))
		return
	if(action == "player_menu") // a name's menu (player_menu.dm)
		return player_menu_act(usr, params)
	if(round_log_line_act(action, params, usr))
		return
	notice = null
	switch(action)
		if("list")
			var/state = text2num(params["state"])
			if(state in list(0, AHELP_ACTIVE, AHELP_RESOLVED, AHELP_CLOSED)) // 0: the mentors' questions
				list_state = state
			return TRUE
		if("select")
			var/datum/admin_help/AH = GLOB.ahelp_tickets.TicketByID(text2num(params["id"]))
			selected_id = AH?.id
			map_time = null
			map_z = null
			map_send = map_open
			return TRUE
		if("context")
			var/minutes = text2num(params["minutes"])
			if(minutes in list(2, 5, 15, 30))
				context_minutes = minutes
			switch(params["source"])
				if("player")
					show_player = !show_player
				if("named")
					show_named = !show_named
				if("area")
					show_area = !show_area
				if("seen")
					show_seen = !show_seen
				if("heard")
					show_heard = !show_heard
			save_layout()
			return TRUE
		if("step") // J and K in the hub: the next or previous ticket down the list
			var/list/rows = shown_rows()
			if(!rows.len)
				return
			var/at = 0
			for(var/i in 1 to rows.len)
				if(rows[i]["id"] == selected_id)
					at = i
			at = clamp(at + (text2num(params["dir"]) < 0 ? -1 : 1), 1, rows.len)
			selected_id = rows[at]["id"]
			return TRUE
		if("map_open")
			map_open = !!text2num(params["open"])
			map_send = map_open
			return TRUE
		if("map_need") // the page hasn't this level's map
			map_send = TRUE
			return TRUE
		if("map_time")
			map_time = text2num(params["t"])
			return TRUE
		if("map_z")
			var/z = text2num(params["z"])
			if(z in SSmapping.levels_by_trait(ZTRAIT_STATION))
				map_z = z
				map_send = TRUE
			return TRUE
		if("map_dot")
			var/mob/M = mob_of_ckey(ckey(params["ckey"]))
			mob_act(params["what"], M, usr)
			return
		if("question")
			usr.client.open_questions(text2num(params["id"]))
			return
		if("reply_save")
			var/title = copytext_char(trim("[params["title"]]"), 1, 40)
			var/text = copytext_char(trim("[params["text"]]"), 1, MAX_MESSAGE_LEN)
			if(!title || !text)
				say("A saved reply needs a name and some text.", TRUE)
				return TRUE
			ahelp_replies()[title] = text
			ahelp_replies_save()
			log_admin_private("[key_name(usr)] saved the ahelp reply \"[title]\": [text]")
			say("Saved \"[title]\".")
			return TRUE
		if("reply_remove")
			var/title = "[params["title"]]"
			var/list/replies = ahelp_replies()
			if(!(title in replies))
				return
			replies -= title
			ahelp_replies_save()
			log_admin_private("[key_name(usr)] removed the ahelp reply \"[title]\"")
			return TRUE
	var/datum/admin_help/AH = selected()
	if(!AH)
		return
	switch(action)
		if("player")
			var/what = params["what"]
			switch(what)
				if("logs")
					usr.client.open_log_search(AH.initiator_ckey)
				if("profile")
					usr.client.open_player_profile(AH.initiator_ckey)
				if("notes")
					usr.client.open_ban_window("notes", list("view" = "player", "ckey" = AH.initiator_ckey))
				if("ban")
					usr.client.open_ban_window("new", list("key" = note_key_of(AH.initiator_ckey), "reason" = quote_text(AH)))
				if("note_add")
					usr.client.open_ban_window("notes", list("view" = "player", "ckey" = AH.initiator_ckey, "compose" = TRUE, "kind" = "note", "text" = quote_text(AH)))
				if("where")
					if(AH.opened_z)
						usr.client.jumptocoord(AH.opened_x, AH.opened_y, AH.opened_z)
				else
					mob_act(what, ticket_mob(AH), usr)
			return
		if("named")
			var/index = text2num(params["index"])
			if(index < 1 || index > length(AH.mentioned))
				return
			var/datum/weakref/W = AH.mentioned[index]
			mob_act(params["what"], W.resolve(), usr)
			return
		if("refresh")
			brief_for = null
			context_for = null
			return TRUE
		if("note")
			AH.add_note(usr.client, params["text"])
			return TRUE
		if("quote")
			var/line_id = text2num(params["id"])
			if(!round_log_entry(line_id))
				return
			var/list/quoted = quotes["[AH.id]"] || list()
			if(line_id in quoted)
				quoted -= line_id
			else
				quoted += line_id
			quotes["[AH.id]"] = quoted
			return TRUE
		if("unquote_all")
			quotes -= "[AH.id]"
			return TRUE
		if("reply")
			var/text = trim("[params["text"]]")
			if(!text)
				return
			if(AH.state != AHELP_ACTIVE)
				say("The ticket is closed: reopen it to reply.", TRUE)
				return TRUE
			if(!AH.initiator)
				say("[AH.initiator_key_name] isn't connected.", TRUE)
				return TRUE
			usr.client.cmd_admin_pm(AH.initiator, text)
			return TRUE
		if("claim")
			if(AH.claimed_ckey == usr.ckey)
				return
			AH.claim(usr.client)
			return TRUE
		if("unclaim")
			AH.unclaim(usr.client)
			return TRUE
		if("retitle")
			AH.set_title(params["title"])
			return TRUE
		if("resolve")
			AH.Resolve()
			return TRUE
		if("icissue")
			AH.ICIssue()
			return TRUE
		if("reject")
			AH.Reject()
			return TRUE
		if("close")
			AH.Close()
			return TRUE
		if("reopen")
			usr.client.hub_suppress = TRUE // Reopen() redraws the ticket's page: this window, not the hub
			AH.Reopen()
			usr.client.hub_suppress = FALSE
			list_state = AH.state
			return TRUE

#undef TICKET_CONTEXT_MAX
#undef TICKET_BRIEF_KEEP
