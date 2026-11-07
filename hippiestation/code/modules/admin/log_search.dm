// Search Logs: the round log (round_log.dm) searched in a window (tgui-next LogSearch.js). Words to look for ("|" between them:
// any of them), a player (ckey or name, either side of the line), kinds of line, the last so many minutes, an area; quick
// starts for the usual questions (deaths, fights, bombs, admin actions...); every line with the round time, what kind it is,
// and buttons for who did it, who it was done to and where (player panel, view variables, follow, jump). Opened from the
// Admin tab or a player panel's SEARCH LOGS. The user asked for investigating made easy and friendly to new admins, 2026-11-07.

#define LOG_SEARCH_SHOWN 300

/client/var/datum/log_search/log_search

/client/proc/cmd_search_logs()
	set name = "Search Logs"
	set category = "Admin"
	set desc = "Search everything logged this round: who did what, where and when."
	if(!check_rights(R_ADMIN))
		return
	open_log_search()

/// The window, filtered to a player when given one (a player panel's SEARCH LOGS)
/client/proc/open_log_search(who)
	if(!log_search)
		log_search = new
		log_search.owner = src
	if(who)
		log_search.reset()
		log_search.who = who
	log_search.search()
	log_search.ui_interact(mob)

/// Kinds of line, in the order the window shows them, and what each holds (the chips' tooltips)
GLOBAL_LIST_INIT(log_search_kinds, list(
	"Attack" = "Hits, shots, grabs, cuffs: anything done to someone",
	"Death" = "Who died, where, their damage and who last hurt them",
	"Bomb" = "Bombs set, primed or armed, and by whom",
	"Game" = "Everything else that happened in play",
	"Say" = "Things said out loud",
	"Whisper" = "Things whispered",
	"Radio" = "Radio and telecomms",
	"PDA" = "PDA messages",
	"Emote" = "Emotes",
	"OOC" = "OOC and LOOC",
	"Dead chat" = "Ghosts talking",
	"Join" = "Who joined as what",
	"Admin" = "Admin actions",
	"Admin (private)" = "Admin actions not shown to players",
	"Asay" = "Admin chat",
	"Investigate" = "Engines, atmos, wires, research, cargo and more (the old Investigate logs)",
	"Law" = "AI law changes",
	"Access" = "ID access changes",
	"Mecha" = "Exosuits",
	"Virus" = "Diseases",
	"Cloning" = "Cloning",
	"Paper" = "What was written on paper",
	"Prayer" = "Prayers",
	"Vote" = "Votes",
	"Chat" = "NTOS chat",
	"Comment" = "Newscaster comments",
))

/// The quick starts: name = list(kinds, words, minutes, what it's for)
GLOBAL_LIST_INIT(log_search_presets, list(
	"Deaths" = list(list("Death"), "", 0, "Every death this round, with who last hurt them"),
	"Fights" = list(list("Attack"), "", 0, "Who hit, shot or grabbed whom"),
	"Bombs" = list(list("Bomb", "Game"), "explosion|bomb|detonat|primed|armed", 0, "Bombs, grenades and explosions"),
	"Admin" = list(list("Admin", "Admin (private)"), "", 0, "What admins did"),
	"Chat" = list(list("Say", "Whisper", "Radio", "PDA", "Emote", "OOC", "Dead chat"), "", 0, "Everything said, typed or emoted"),
	"Joins" = list(list("Join"), "", 0, "Who joined, as what and when"),
	"Engines & gas" = list(list("Investigate"), "", 0, "The engines, atmos changes, wires and machines"),
	"Last 5 min" = list(list(), "", 5, "Everything in the last five minutes"),
))

/datum/log_search
	var/client/owner
	var/text = ""
	var/who = ""
	var/area_text = ""
	var/minutes = 0
	var/list/kinds = list()
	var/oldest_first = FALSE
	var/preset
	var/list/results = list()
	var/matched = 0
	var/scanned = 0

/datum/log_search/proc/reset()
	text = ""
	who = ""
	area_text = ""
	minutes = 0
	kinds = list()
	preset = null

/datum/log_search/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.admin_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "log_search", "Search Logs", 1000, 680, master_ui, state)
		ui.open()

/// Whether a line matches what's asked
/datum/log_search/proc/matches(list/entry, list/terms, since)
	if(since && entry[RL_TIME] < since)
		return FALSE
	if(kinds.len)
		var/kind = entry[RL_CAT]
		if(!(kind in kinds) && !(findtext(kind, "Investigate") == 1 && ("Investigate" in kinds)))
			return FALSE
	if(area_text && !findtext(entry[RL_AREA], area_text))
		return FALSE
	if(who && !findtext(entry[RL_CKEY], who) && !findtext(entry[RL_NAME], who) && !findtext(entry[RL_TCKEY], who) && !findtext(entry[RL_TNAME], who) && !findtext(entry[RL_TEXT], who))
		return FALSE
	if(terms.len)
		for(var/term in terms)
			if(findtext(entry[RL_TEXT], term))
				return TRUE
		return FALSE
	return TRUE

/datum/log_search/proc/search()
	var/list/terms = list()
	for(var/term in splittext(text, "|"))
		term = trim(term)
		if(term)
			terms += term
	var/since = minutes ? world.time - minutes MINUTES : 0
	results = list()
	matched = 0
	var/list/log = GLOB.round_log
	scanned = log.len
	for(var/i in log.len to 1 step -1) // newest first; the window shows the first LOG_SEARCH_SHOWN
		var/list/entry = log[i]
		if(since && entry[RL_TIME] < since)
			break
		if(matches(entry, terms, since))
			matched++
			if(results.len < LOG_SEARCH_SHOWN)
				results += list(entry)
		if(!(i % 2000))
			CHECK_TICK

/proc/log_search_clock(time)
	var/t = round((time - SSticker.round_start_time) / 10)
	if(!SSticker.round_start_time || t < 0)
		return "lobby"
	var/h = round(t / 3600)
	var/m = round(t / 60) % 60
	var/s = t % 60
	return "[h ? "[h]:" : ""][m < 10 ? "0[m]" : m]:[s < 10 ? "0[s]" : s]"

/datum/log_search/ui_data(mob/user)
	var/list/rows = list()
	var/list/shown = oldest_first ? reverseRange(results.Copy()) : results
	for(var/list/entry in shown)
		var/datum/weakref/actor = entry[RL_REF]
		var/datum/weakref/target = entry[RL_TREF]
		rows += list(list(
			"id" = entry[RL_ID],
			"time" = log_search_clock(entry[RL_TIME]),
			"kind" = entry[RL_CAT],
			"text" = entry[RL_TEXT],
			"ckey" = entry[RL_CKEY],
			"name" = entry[RL_NAME],
			"actor" = !!actor?.resolve(),
			"actor_mob" = ismob(actor?.resolve()),
			"tckey" = entry[RL_TCKEY],
			"tname" = entry[RL_TNAME],
			"target" = !!target?.resolve(),
			"target_mob" = ismob(target?.resolve()),
			"area" = entry[RL_AREA],
			"where" = entry[RL_Z] ? "[entry[RL_X]], [entry[RL_Y]], [entry[RL_Z]]" : null,
		))
	var/list/kind_list = list()
	for(var/kind in GLOB.log_search_kinds)
		kind_list += list(list("name" = kind, "desc" = GLOB.log_search_kinds[kind], "count" = GLOB.round_log_counts[kind] || 0, "on" = (kind in kinds)))
	var/list/presets = list()
	for(var/name in GLOB.log_search_presets)
		presets += list(list("name" = name, "desc" = GLOB.log_search_presets[name][4], "on" = preset == name))
	return list(
		"text" = text,
		"who" = who,
		"area" = area_text,
		"minutes" = minutes,
		"oldest_first" = oldest_first,
		"kinds" = kind_list,
		"presets" = presets,
		"rows" = rows,
		"matched" = matched,
		"shown" = rows.len,
		"scanned" = scanned,
		"total" = GLOB.round_log_total,
		"kept_from" = GLOB.round_log.len ? log_search_clock(GLOB.round_log[1][RL_TIME]) : null,
		"round_time" = log_search_clock(world.time),
	)

/// The line with this id, if it's still kept
/proc/round_log_entry(id)
	var/list/log = GLOB.round_log
	if(!log.len)
		return null
	var/index = id - log[1][RL_ID] + 1
	if(index < 1 || index > log.len)
		return null
	return log[index]

/datum/log_search/ui_act(action, list/params)
	if(..())
		return
	if(!check_rights(R_ADMIN))
		return
	switch(action)
		if("search")
			text = params["text"] || ""
			who = params["who"] || ""
			area_text = params["area"] || ""
			minutes = text2num(params["minutes"]) || 0
			preset = null
			search()
			return TRUE
		if("kind")
			var/kind = params["name"]
			if(kind in kinds)
				kinds -= kind
			else if(kind in GLOB.log_search_kinds)
				kinds += kind
			preset = null
			search()
			return TRUE
		if("all_kinds")
			kinds = list()
			preset = null
			search()
			return TRUE
		if("preset")
			var/list/P = GLOB.log_search_presets[params["name"]]
			if(!P)
				return
			var/list/preset_kinds = P[1]
			kinds = preset_kinds.Copy()
			text = P[2]
			minutes = P[3]
			preset = params["name"]
			search()
			return TRUE
		if("clear")
			reset()
			search()
			return TRUE
		if("order")
			oldest_first = !oldest_first
			return TRUE
		if("refresh")
			search()
			return TRUE
	// a line's buttons
	var/list/entry = round_log_entry(text2num(params["id"]))
	if(!entry)
		return
	var/datum/weakref/W = entry[findtext(action, "t_") == 1 ? RL_TREF : RL_REF]
	var/atom/thing = W?.resolve()
	switch(action)
		if("pp", "t_pp")
			if(ismob(thing))
				usr.client.holder.show_player_panel(thing)
		if("vv", "t_vv")
			if(thing)
				usr.client.debug_variables(thing)
		if("flw", "t_flw")
			if(ismovable(thing) && (isobserver(usr) || usr.client.admin_ghost())) // as the player panel's FLW does
				var/mob/dead/observer/ghost = usr.client.mob
				ghost.ManualFollow(thing)
		if("jmp")
			if(entry[RL_Z])
				usr.client.jumptocoord(entry[RL_X], entry[RL_Y], entry[RL_Z])

/// Lines kept, by kind (every one this round, not only the ones still kept)
GLOBAL_LIST_EMPTY(round_log_counts)

#undef LOG_SEARCH_SHOWN
