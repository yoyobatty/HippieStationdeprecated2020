// hippie -- the admin's log and report windows designed for tgui (interfaces/AdminLogs.js): Investigate (a subject's log, read from
// its file into lines with where it happened), a mob's individual logs (by kind, from the client or the mob, newest first), the
// server's log files (folders and files, viewed in the window or opened or downloaded as before), SDQL results (each thing found with
// view variables and jump), playtime (everyone online, and one player's departments, jobs and what's still locked), and the station
// upgrade report. The old procs open these; their rights checks, logs and file rules are the old ones.

// ---------------------------------------------------------------------------------------------
// Investigate
// ---------------------------------------------------------------------------------------------

/// The investigate subjects, as investigate_show() lists them
/proc/investigate_subjects()
	return list(INVESTIGATE_RESEARCH, INVESTIGATE_EXONET, INVESTIGATE_PORTAL, INVESTIGATE_SINGULO, INVESTIGATE_WIRES, INVESTIGATE_TELESCI, \
		INVESTIGATE_GRAVITY, INVESTIGATE_RECORDS, INVESTIGATE_CARGO, INVESTIGATE_SUPERMATTER, INVESTIGATE_ATMOS, INVESTIGATE_EXPERIMENTOR, \
		INVESTIGATE_BOTANY, INVESTIGATE_HALLUCINATIONS, INVESTIGATE_RADIATION, INVESTIGATE_NANITES, INVESTIGATE_PRESENTS, INVESTIGATE_CIRCUIT)

/client/investigate_show()
	if(!holder)
		return
	holder.open_admin_tool("investigate", /datum/admin_tool_window/investigate)

/datum/admin_tool_window/investigate
	interface = "admin_investigate"
	title = "Investigate"
	width = 860
	height = 600
	var/subject
	var/list/lines
	/// Lines in the file when it was read, before the newest LOG_SEARCH_SHOWN were kept
	var/total = 0

/// How many of a subject's newest lines the window shows
#define INVESTIGATE_SHOWN 1000

/datum/admin_tool_window/investigate/proc/read_subject()
	lines = list()
	total = 0
	if(!subject)
		return
	var/F = file("[GLOB.log_directory]/[subject].html")
	if(!fexists(F))
		return
	var/static/regex/line_parts = regex(@"^(\d\d:\d\d:\d\d) (\[[^\]]+\]) \((\d+),(\d+),(\d+)\) \|\| (.*)$")
	var/list/raw = splittext(file2text(F), "<br>")
	for(var/i in length(raw) to 1 step -1)
		var/text = trim(raw[i])
		if(!length(text))
			continue
		total++
		if(length(lines) >= INVESTIGATE_SHOWN)
			continue
		if(line_parts.Find(text))
			lines += list(list("time" = line_parts.group[1], "ref" = line_parts.group[2], "x" = text2num(line_parts.group[3]), \
				"y" = text2num(line_parts.group[4]), "z" = text2num(line_parts.group[5]), "text" = comm_plain_text(line_parts.group[6])))
		else
			lines += list(list("text" = comm_plain_text(text)))

/datum/admin_tool_window/investigate/ui_data(mob/user)
	var/list/subjects = list()
	for(var/name in investigate_subjects())
		subjects += list(list("name" = name, "present" = fexists("[GLOB.log_directory]/[name].html")))
	return list("subjects" = subjects, "subject" = subject, "lines" = lines || list(), "total" = total, "shown_max" = INVESTIGATE_SHOWN, \
		"can_notes" = check_rights_for(user.client, R_ADMIN))

/datum/admin_tool_window/investigate/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("subject")
			if(params["subject"] in investigate_subjects())
				subject = params["subject"]
				read_subject()
		if("refresh")
			read_subject()
		if("notes")
			if(check_rights(R_ADMIN))
				browse_messages()
		if("jump")
			var/x = text2num("[params["x"]]")
			var/y = text2num("[params["y"]]")
			var/z = text2num("[params["z"]]")
			if(x && y && z)
				holder.page_holder_link(list("adminplayerobservecoodjump" = "1", "X" = "[x]", "Y" = "[y]", "Z" = "[z]"))
		if("vv")
			var/datum/D = locate(params["ref"])
			if(D)
				usr.client.debug_variables(D)
	return TRUE

#undef INVESTIGATE_SHOWN

// ---------------------------------------------------------------------------------------------
// A mob's individual logs
// ---------------------------------------------------------------------------------------------

/// show_individual_logging_panel() hands over to this (individual_logging.dm)
/proc/open_individual_log_window(mob/M, source = LOGSRC_CLIENT, type = INDIVIDUAL_ATTACK_LOG)
	if(!ismob(M) || !usr?.client?.holder)
		return
	usr.client.holder.open_admin_tool("ilog_[REF(M)]", /datum/admin_tool_window/individual_log, list("mob" = M, "source" = source, "type" = text2num("[type]")))

/// The kinds of line a mob's log keeps, by flag, and the tabs that group them
/proc/individual_log_names()
	var/static/list/names = list("[LOG_ATTACK]" = "Attack", "[LOG_SAY]" = "Say", "[LOG_WHISPER]" = "Whisper", "[LOG_DSAY]" = "Dead chat", \
		"[LOG_EMOTE]" = "Emote", "[LOG_PDA]" = "PDA", "[LOG_CHAT]" = "Chat", "[LOG_COMMENT]" = "Comment", "[LOG_TELECOMMS]" = "Telecomms", \
		"[LOG_OOC]" = "OOC", "[LOG_ADMIN]" = "Admin", "[LOG_OWNERSHIP]" = "Ownership", "[LOG_GAME]" = "Game")
	return names

/datum/admin_tool_window/individual_log
	interface = "admin_individual_log"
	title = "Individual logs"
	width = 760
	height = 600
	var/datum/weakref/target
	var/source = LOGSRC_CLIENT
	var/log_type = INDIVIDUAL_ATTACK_LOG

#define INDIVIDUAL_LOG_SHOWN 600

/datum/admin_tool_window/individual_log/setup(list/arguments)
	var/mob/M = arguments["mob"]
	if(M)
		target = WEAKREF(M)
		title = "Logs: [M.real_name || M.name]"
	if(arguments["source"] in list(LOGSRC_CLIENT, LOGSRC_MOB))
		source = arguments["source"]
	if(arguments["type"])
		log_type = arguments["type"]

/datum/admin_tool_window/individual_log/ui_data(mob/user)
	var/mob/M = target?.resolve()
	. = list("gone" = !M)
	if(!M)
		return
	.["name"] = M.real_name || M.name
	.["key"] = M.key
	.["has_client"] = !!M.client
	.["source"] = (source == LOGSRC_CLIENT && M.client) ? LOGSRC_CLIENT : LOGSRC_MOB
	.["type"] = log_type
	.["tabs"] = list(list("Attack", INDIVIDUAL_ATTACK_LOG), list("Say", INDIVIDUAL_SAY_LOG), list("Emote", INDIVIDUAL_EMOTE_LOG), \
		list("Comms", INDIVIDUAL_COMMS_LOG), list("OOC", INDIVIDUAL_OOC_LOG), list("All", INDIVIDUAL_SHOW_ALL_LOG))
	var/list/log_source = M.logging
	if(.["source"] == LOGSRC_CLIENT)
		log_source = M.client.player_details.logging
	var/static/regex/key_parts = regex(@"^(\d+)\[([^\]]+)\] (.*)$")
	var/list/names = individual_log_names()
	var/list/entries = list()
	var/list/counts = list()
	for(var/kind in log_source)
		var/list/kind_lines = log_source[kind]
		if(!islist(kind_lines))
			continue
		var/flag = text2num(kind)
		for(var/list/tab in .["tabs"])
			if(flag & tab[2])
				counts["[tab[2]]"] += length(kind_lines)
		if(!(flag & log_type))
			continue
		for(var/entry_key in kind_lines)
			var/list/entry = list("kind" = names[kind] || "[kind]", "text" = comm_plain_text("[kind_lines[entry_key]]"))
			if(key_parts.Find(entry_key))
				entry["n"] = text2num(key_parts.group[1])
				entry["time"] = key_parts.group[2]
				entry["who"] = comm_plain_text(key_parts.group[3])
			else
				entry["who"] = comm_plain_text(entry_key)
			entries += list(entry)
	// Newest first, across kinds by the time of day
	entries = sortTim(entries, GLOBAL_PROC_REF(cmp_individual_log_newest))
	if(length(entries) > INDIVIDUAL_LOG_SHOWN)
		entries.Cut(INDIVIDUAL_LOG_SHOWN + 1)
	.["entries"] = entries
	.["counts"] = counts

/proc/cmp_individual_log_newest(list/a, list/b)
	if(a["time"] != b["time"])
		return sorttext(a["time"], b["time"]) // -1 when a's time is later: it goes first
	return b["n"] - a["n"]

/datum/admin_tool_window/individual_log/ui_act(action, list/params)
	if(..())
		return
	var/mob/M = target?.resolve()
	switch(action)
		if("source")
			if(params["source"] in list(LOGSRC_CLIENT, LOGSRC_MOB))
				source = params["source"]
		if("type")
			var/wanted = text2num("[params["type"]]")
			if(wanted in list(INDIVIDUAL_ATTACK_LOG, INDIVIDUAL_SAY_LOG, INDIVIDUAL_EMOTE_LOG, INDIVIDUAL_COMMS_LOG, INDIVIDUAL_OOC_LOG, INDIVIDUAL_SHOW_ALL_LOG))
				log_type = wanted
		if("pp")
			if(M)
				holder.page_holder_link(list("adminplayeropts" = REF(M)))
		if("flw")
			if(M)
				holder.page_holder_link(list("adminplayerobservefollow" = REF(M)))
	return TRUE

#undef INDIVIDUAL_LOG_SHOWN

// ---------------------------------------------------------------------------------------------
// The server's log files
// ---------------------------------------------------------------------------------------------

/client/browseserverlogs(path = "data/logs/")
	if(!holder)
		return
	holder.open_admin_tool("log_files", /datum/admin_tool_window/log_files, list("path" = path))

/datum/admin_tool_window/log_files
	interface = "admin_log_files"
	title = "Server logs"
	width = 900
	height = 640
	/// Everything shown is under this
	var/root = "data/logs/"
	var/path = "data/logs/"
	var/viewing
	var/view_text
	var/view_size = 0
	var/view_cut = FALSE

/// What browse_files() let you pick: a file with one of these endings
#define LOG_FILES_VIEWABLE list("txt", "log", "htm", "html")
/// The most of a file the window shows, from its end
#define LOG_FILES_VIEW_MAX 262144

/datum/admin_tool_window/log_files/setup(list/arguments)
	var/wanted = "[arguments["path"]]"
	if(log_files_inside(wanted, root) && copytext(wanted, -1) == "/")
		path = wanted

/// A path under root with no way out of it
/proc/log_files_inside(path, root)
	return findtext(path, root) == 1 && !findtext(path, "..") && !findtext(path, "\\")

/datum/admin_tool_window/log_files/ui_data(mob/user)
	. = list("root" = root, "path" = path, "viewing" = viewing, "view_text" = view_text, "view_size" = view_size, "view_cut" = view_cut)
	var/list/folders = list()
	var/list/files = list()
	var/static/regex/viewable = regex("\\.(txt|log|htm|html)$", "i")
	for(var/entry in flist(path))
		if(copytext(entry, -1) == "/")
			folders += entry
		else
			files += list(list("name" = entry, "size" = length(file("[path][entry]")), "viewable" = !!viewable.Find(entry)))
	.["folders"] = sortList(folders)
	.["files"] = files
	.["current"] = (path == "[GLOB.log_directory]/")

/datum/admin_tool_window/log_files/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("open_folder")
			var/folder = "[params["name"]]"
			if((folder in flist(path)) && copytext(folder, -1) == "/" && log_files_inside("[path][folder]", root))
				path = "[path][folder]"
				viewing = null
				view_text = null
		if("up")
			if(path != root)
				var/list/parts = splittext(copytext(path, 1, -1), "/")
				parts.Cut(length(parts))
				path = "[jointext(parts, "/")]/"
				if(!log_files_inside(path, root))
					path = root
			viewing = null
			view_text = null
		if("go")
			var/wanted = "[params["path"]]"
			if(log_files_inside(wanted, root) && copytext(wanted, -1) == "/" && fexists(wanted))
				path = wanted
				viewing = null
				view_text = null
		if("current")
			path = "[GLOB.log_directory]/"
			viewing = null
			view_text = null
		if("view", "open", "download")
			var/name = "[params["name"]]"
			var/full = "[path][name]"
			var/static/regex/viewable = regex("\\.(txt|log|htm|html)$", "i")
			if(!(name in flist(path)) || !log_files_inside(full, root) || !viewable.Find(name) || !fexists(full))
				return
			if(usr.client.file_spam_check())
				return
			message_admins("[key_name_admin(usr)] accessed file: [full]")
			switch(action)
				if("view")
					var/text = file2text(file(full))
					view_size = length(text)
					view_cut = view_size > LOG_FILES_VIEW_MAX
					if(view_cut)
						text = copytext(text, -LOG_FILES_VIEW_MAX)
					viewing = full
					view_text = text
				if("open")
					usr << run(file(full))
				if("download")
					to_chat(usr, "Attempting to send [full], this may take a fair few minutes if the file is very large.", confidential = TRUE)
					usr << ftp(file(full))
		if("close_view")
			viewing = null
			view_text = null
	return TRUE

#undef LOG_FILES_VIEWABLE
#undef LOG_FILES_VIEW_MAX

// ---------------------------------------------------------------------------------------------
// SDQL results
// ---------------------------------------------------------------------------------------------

/// SDQL_2.dm's, with the results in a window instead of an HTML page: Run() is left to do its work without showing anything, then the
/// summary goes to chat and the window opens. A query that deletes itself when done does so after.
/datum/SDQL2_query/Run()
	var/show_to = show_next_to_key
	var/delete_after = qdel_on_finish
	show_next_to_key = null
	qdel_on_finish = FALSE
	. = ..()
	var/client/C = show_to ? GLOB.directory[show_to] : null
	if(C && finished)
		to_chat(C.mob, "<span class='admin'>SDQL query results: [get_query_text()]<br>\
			SDQL query completed: [islist(obj_count_all)? length(obj_count_all) : obj_count_all] objects selected by path, and \
			[where_switched? "[islist(obj_count_eligible)? length(obj_count_eligible) : obj_count_eligible] objects executed on after WHERE keyword selection." : ""]<br>\
			SDQL query took [DisplayTimeText(end_time - start_time)] to complete.</span>", confidential=TRUE)
		if(length(select_refs) && C.holder)
			C.holder.open_admin_tool("sdql_[id]", /datum/admin_tool_window/sdql_results, list("query" = src))
	if(delete_after && finished)
		qdel(src)

/datum/admin_tool_window/sdql_results
	interface = "admin_sdql_results"
	title = "SDQL results"
	width = 860
	height = 600
	var/query_text
	var/took
	var/list/rows

#define SDQL_RESULTS_SHOWN 2000

/datum/admin_tool_window/sdql_results/setup(list/arguments)
	var/datum/SDQL2_query/Q = arguments["query"]
	if(!Q)
		return
	query_text = Q.get_query_text()
	took = DisplayTimeText(Q.end_time - Q.start_time)
	title = "SDQL results: query #[Q.id]"
	rows = list()
	var/n = 0
	for(var/ref in Q.select_refs)
		n++
		if(n > SDQL_RESULTS_SHOWN)
			break
		var/thing = locate(ref)
		var/list/row = list("ref" = ref)
		if(istype(thing, /datum))
			var/datum/D = thing
			row["name"] = "[D]"
			row["type"] = "[D.type]"
			if(isatom(D))
				var/turf/T = get_turf(D)
				if(T)
					row["x"] = T.x
					row["y"] = T.y
					row["z"] = T.z
					row["area"] = "[get_area(T)]"
		else
			row["name"] = "[thing]"
		rows += list(row)

/datum/admin_tool_window/sdql_results/ui_data(mob/user)
	return list("query" = query_text, "took" = took, "rows" = rows || list(), "shown_max" = SDQL_RESULTS_SHOWN)

/datum/admin_tool_window/sdql_results/ui_act(action, list/params)
	if(..())
		return
	var/found = FALSE
	for(var/list/row in rows)
		if(row["ref"] == params["ref"])
			found = TRUE
			break
	if(!found)
		return
	var/datum/D = locate(params["ref"])
	if(!istype(D))
		return
	switch(action)
		if("vv")
			usr.client.debug_variables(D)
		if("jump")
			var/turf/T = get_turf(D)
			if(T)
				holder.page_holder_link(list("adminplayerobservecoodjump" = "1", "X" = "[T.x]", "Y" = "[T.y]", "Z" = "[T.z]"))
	return TRUE

#undef SDQL_RESULTS_SHOWN

// ---------------------------------------------------------------------------------------------
// Playtime
// ---------------------------------------------------------------------------------------------

/// One player's playtime: departments and jobs in minutes, and the jobs they haven't unlocked with how far along they are
/proc/playtime_report_data(client/C)
	. = list("key" = C.key, "ckey" = C.ckey)
	if(!CONFIG_GET(flag/use_exp_tracking))
		.["disabled"] = TRUE
		return
	var/list/play_records = C.prefs.exp
	if(!length(play_records))
		C.set_exp_from_db()
		play_records = C.prefs.exp
	var/living = text2num(play_records[EXP_TYPE_LIVING]) || 0
	.["living"] = living
	.["ghost"] = text2num(play_records[EXP_TYPE_GHOST]) || 0
	.["exempt"] = !!(C.prefs.db_flags & DB_FLAG_EXEMPT)
	.["admin_bypass"] = CONFIG_GET(flag/use_exp_restrictions_admin_bypass) && check_rights_for(C, R_ADMIN)
	var/list/departments = list()
	for(var/category in GLOB.exp_jobsmap)
		if(category == EXP_TYPE_CREW) // every crew job together: the same as alive, near enough
			continue
		var/minutes = text2num(play_records[category]) || 0
		if(minutes)
			departments += list(list("name" = category, "minutes" = minutes))
	.["departments"] = departments
	var/list/jobs = list()
	for(var/job_name in SSjob.name_occupations)
		var/minutes = text2num(play_records[job_name]) || 0
		if(minutes)
			jobs += list(list("name" = job_name, "minutes" = minutes))
	for(var/category in list(EXP_TYPE_SPECIAL, EXP_TYPE_ANTAG))
		for(var/inner in GLOB.exp_specialmap[category])
			var/minutes = text2num(play_records[inner]) || 0
			if(minutes)
				jobs += list(list("name" = inner, "minutes" = minutes, "special" = TRUE))
	.["jobs"] = jobs
	var/list/locked = list()
	for(var/datum/job/job in SSjob.occupations)
		if(!job.exp_requirements || !job.exp_type || !job_is_xp_locked(job.title))
			continue
		if(!job.required_playtime_remaining(C))
			continue
		locked += list(list("name" = job.title, "have" = text2num(C.calc_exp_type(job.get_exp_req_type())) || 0, \
			"need" = job.get_exp_req_amount(), "as" = job.get_exp_req_type()))
	.["locked"] = locked

/client/cmd_admin_check_player_exp()
	if(!check_rights(R_ADMIN))
		return
	if(!CONFIG_GET(flag/use_exp_tracking))
		to_chat(usr, "<span class='warning'>Tracking is disabled in the server configuration file.</span>", confidential = TRUE)
		return
	holder.open_admin_tool("playtime", /datum/admin_tool_window/playtime)

/datum/admins/cmd_show_exp_panel(client/C)
	if(!check_rights(R_ADMIN))
		return
	if(!C)
		to_chat(usr, "<span class='danger'>ERROR: Client not found.</span>", confidential = TRUE)
		return
	if(!CONFIG_GET(flag/use_exp_tracking))
		to_chat(usr, "<span class='warning'>Tracking is disabled in the server configuration file.</span>", confidential = TRUE)
		return
	open_admin_tool("playtime", /datum/admin_tool_window/playtime, list("ckey" = C.ckey))

/datum/admin_tool_window/playtime
	interface = "admin_playtime"
	title = "Playtime"
	width = 820
	height = 600
	var/selected

/datum/admin_tool_window/playtime/setup(list/arguments)
	if(arguments?["ckey"])
		selected = arguments["ckey"]

/datum/admin_tool_window/playtime/ui_data(mob/user)
	var/list/players = list()
	for(var/client/C in GLOB.clients)
		var/list/exp = C.prefs?.exp
		players += list(list("ckey" = C.ckey, "key" = C.key, "living" = text2num(exp?[EXP_TYPE_LIVING]) || 0, \
			"ghost" = text2num(exp?[EXP_TYPE_GHOST]) || 0, "job" = C.mob?.mind?.assigned_role))
	. = list("players" = players, "selected" = selected)
	var/client/S = GLOB.directory[selected]
	if(S)
		.["detail"] = playtime_report_data(S)

/datum/admin_tool_window/playtime/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("select")
			selected = GLOB.directory[params["ckey"]] ? params["ckey"] : null
		if("toggle_exempt")
			var/client/C = GLOB.directory[selected]
			if(C)
				holder.toggle_exempt_status(C)
	return TRUE

/// A player's own playtime (View tracked playtime): the same report, without the admin's buttons
/datum/playtime_window
	var/client/owner

/datum/playtime_window/New(client/C)
	owner = C

/datum/playtime_window/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "player_playtime", "Playtime", 520, 600, master_ui, state)
		ui.open()

/datum/playtime_window/ui_data(mob/user)
	return owner ? playtime_report_data(owner) : list()

/datum/playtime_window/ui_close(mob/user)
	qdel(src)

/datum/playtime_window/Destroy()
	owner = null
	return ..()

// ---------------------------------------------------------------------------------------------
// The station upgrade report (Upgrade All Machines in Secrets, secrets.dm)
// ---------------------------------------------------------------------------------------------

/datum/admin_tool_window/upgrade_report
	interface = "admin_upgrade_report"
	title = "Station upgrade report"
	width = 820
	height = 620
	var/summary
	var/list/explanations
	var/list/totals
	var/list/rows

/datum/admin_tool_window/upgrade_report/setup(list/arguments)
	summary = arguments["summary"]
	var/list/report = arguments["report"]
	explanations = list()
	var/static/regex/titled = regex(@"^<B>(.*?)</B>(.*)$")
	for(var/explanation in report["explanations"])
		if(titled.Find(explanation))
			explanations += list(list("title" = comm_plain_text(titled.group[1]), "text" = comm_plain_text(titled.group[2])))
		else
			explanations += list(list("text" = comm_plain_text(explanation)))
	totals = list()
	var/list/report_totals = report["totals"]
	for(var/change in report_totals)
		totals += list(list("name" = comm_plain_text(change), "count" = report_totals[change]))
	rows = report["rows"] || list()

/datum/admin_tool_window/upgrade_report/ui_data(mob/user)
	return list("summary" = summary, "explanations" = explanations, "totals" = totals, "rows" = rows)

/datum/admin_tool_window/upgrade_report/ui_act(action, list/params)
	if(..())
		return
	for(var/list/row in rows)
		if(row["ref"] != params["ref"])
			continue
		var/atom/A = locate(row["ref"])
		if(!A)
			return
		switch(action)
			if("jump")
				var/turf/T = get_turf(A)
				if(T)
					holder.page_holder_link(list("adminplayerobservecoodjump" = "1", "X" = "[T.x]", "Y" = "[T.y]", "Z" = "[T.z]"))
			if("vv")
				usr.client.debug_variables(A)
		return TRUE
