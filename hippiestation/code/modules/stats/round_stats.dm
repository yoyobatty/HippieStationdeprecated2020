// hippie -- Round Stats (interfaces/RoundStats.js, the OOC tab's Round Stats verb): past rounds, deaths, game modes and playtime, from
// the database. Open to everyone. The round being played is left out for players (it would say who died where, and to whom, and as
// what); admins see it, and keys: whose body it was and whose hands did it, and any player's playtime.

#define ROUND_STATS_ROWS 100

/client
	var/datum/round_stats/round_stats

/client/verb/round_stats()
	set name = "Round Stats"
	set category = "OOC"
	set desc = "Past rounds, deaths, game modes and your playtime"
	if(!round_stats)
		round_stats = new(ckey)
	round_stats.ui_interact(mob)
	round_stats.load()

/datum/round_stats
	/// whose window it is: a ckey, not the client, so the window never keeps a client alive
	var/owner_ckey
	var/tab = "rounds"
	var/loading = FALSE
	var/error
	var/list/rounds
	var/list/deaths
	var/list/modes
	var/list/playtime
	/// the deaths tab: one round's (a number), or every round's (null)
	var/round_filter
	var/search
	/// admins: whose playtime
	var/playtime_ckey
	/// the round tab: which round's page, and the page
	var/page_round
	var/list/page
	/// admins: runtimes by site over the last rounds
	var/list/runtimes

/datum/round_stats/New(ckey)
	owner_ckey = ckey
	playtime_ckey = ckey

/datum/round_stats/Destroy()
	SStgui.close_uis(src)
	return ..()

/datum/round_stats/proc/is_admin()
	var/client/C = GLOB.directory[owner_ckey]
	return C && check_rights_for(C, R_ADMIN)

/datum/round_stats/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "round_stats", "Round Stats", 760, 580, master_ui, state)
		ui.open()

/datum/round_stats/ui_status(mob/user, datum/ui_state/state)
	return user?.client?.ckey == owner_ckey ? UI_INTERACTIVE : UI_CLOSE

/datum/round_stats/ui_data(mob/user)
	. = list(
		"tab" = tab,
		"loading" = loading,
		"error" = error,
		"admin" = is_admin(),
		"current_round" = text2num(GLOB.round_id),
		"round_filter" = round_filter,
		"search" = search,
		"playtime_ckey" = playtime_ckey,
	)
	switch(tab)
		if("rounds")
			.["rows"] = rounds
		if("deaths")
			.["rows"] = deaths
		if("modes")
			.["rows"] = modes
		if("playtime")
			.["rows"] = playtime
		if("round")
			.["page"] = page
		if("runtimes")
			.["rows"] = runtimes

/datum/round_stats/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("tab")
			if((params["tab"] in list("rounds", "deaths", "modes", "playtime")) || params["tab"] == "runtimes" && is_admin())
				tab = params["tab"]
				if(tab == "deaths" && params["round"] != null)
					round_filter = text2num(params["round"])
				load()
			return TRUE
		if("round")
			page_round = text2num(params["round"])
			if(page_round)
				tab = "round"
				page = null
				load()
			return TRUE
		if("round_filter")
			round_filter = params["round"] == null ? null : text2num(params["round"])
			load()
			return TRUE
		if("search")
			search = copytext_char(trim("[params["search"]]"), 1, 64) || null
			load()
			return TRUE
		if("playtime_ckey")
			if(is_admin())
				playtime_ckey = ckey(params["ckey"]) || owner_ckey
				load()
			return TRUE
		if("refresh")
			load()
			return TRUE

/// Reads the shown tab from the database, in the background (a window's data can't wait on it)
/datum/round_stats/proc/load()
	set waitfor = FALSE
	if(loading)
		return
	loading = TRUE
	error = null
	SStgui.update_uis(src)
	if(!SSdbcore.Connect())
		error = CONFIG_GET(flag/sql_enabled) ? "Database unreachable" : "No database"
	else
		switch(tab)
			if("rounds")
				rounds = load_rounds()
			if("deaths")
				deaths = load_deaths()
			if("modes")
				modes = load_modes()
			if("playtime")
				playtime = load_playtime()
			if("round")
				page = load_round(page_round)
			if("runtimes")
				runtimes = is_admin() ? load_runtimes() : null
	loading = FALSE
	SStgui.update_uis(src)

/// Every row of a query (each a list of its columns), deleting it after; null and the error set if it failed
/datum/round_stats/proc/query_rows(datum/DBQuery/query_round_stats)
	if(!query_round_stats.Execute())
		error = "Database error"
		qdel(query_round_stats)
		return
	. = list()
	while(query_round_stats.NextRow())
		. += list(query_round_stats.item.Copy())
	qdel(query_round_stats)

/// The rounds, newest first, or just the one (only: its id)
/datum/round_stats/proc/load_rounds(only)
	var/admin = is_admin()
	var/list/found = query_rows(SSdbcore.NewQuery({"SELECT r.id, r.start_datetime, r.end_datetime, TIMESTAMPDIFF(MINUTE, r.start_datetime, IFNULL(r.end_datetime, r.shutdown_datetime)),
		r.game_mode, r.game_mode_result, r.end_state, r.map_name, r.station_name, r.shuttle_name,
		(SELECT COUNT(*) FROM [format_table_name("death")] AS d WHERE d.round_id = r.id), CONCAT(INET_NTOA(r.server_ip), ':', r.server_port), r.commit_hash
		FROM [format_table_name("round")] AS r
		WHERE r.start_datetime IS NOT NULL AND (:admin = 1 OR r.id != :current) AND (:only IS NULL OR r.id = :only)
		ORDER BY r.id DESC LIMIT :rows"}, list("admin" = admin ? 1 : 0, "current" = text2num(GLOB.round_id) || 0, "only" = only, "rows" = ROUND_STATS_ROWS)))
	if(!found)
		return
	. = list()
	for(var/list/i in found)
		var/list/row = list("id" = text2num(i[1]), "start" = i[2], "end" = i[3], "minutes" = text2num(i[4]), "mode" = i[5], "result" = i[6],
			"end_state" = i[7], "map" = i[8], "station" = i[9], "shuttle" = i[10], "deaths" = text2num(i[11]))
		if(admin)
			row["server"] = i[12]
			row["commit"] = i[13] ? copytext(i[13], 1, 8) : null
		. += list(row)

/datum/round_stats/proc/load_deaths()
	var/admin = is_admin()
	var/list/found = query_rows(SSdbcore.NewQuery({"SELECT id, round_id, tod, name, job, special, pod, bruteloss, fireloss, oxyloss, toxloss, cloneloss, brainloss, staminaloss, laname, last_words, suicide, byondkey, lakey
		FROM [format_table_name("death")]
		WHERE (:admin = 1 OR round_id != :current) AND (:round IS NULL OR round_id = :round)
		AND (:search IS NULL OR INSTR(name, :search) > 0 OR INSTR(job, :search) > 0 OR INSTR(pod, :search) > 0 OR INSTR(laname, :search) > 0
			OR (:admin = 1 AND (INSTR(byondkey, :search) > 0 OR INSTR(lakey, :search) > 0)))
		ORDER BY id DESC LIMIT :rows"},
		list("admin" = admin ? 1 : 0, "current" = text2num(GLOB.round_id) || 0, "round" = round_filter, "search" = search, "rows" = ROUND_STATS_ROWS)))
	if(!found)
		return
	. = list()
	for(var/list/i in found)
		var/list/row = list("id" = text2num(i[1]), "round" = text2num(i[2]), "time" = i[3], "name" = i[4], "job" = i[5], "special" = i[6], "where" = i[7],
			"brute" = text2num(i[8]), "burn" = text2num(i[9]), "oxy" = text2num(i[10]), "tox" = text2num(i[11]), "clone" = text2num(i[12]), "brain" = text2num(i[13]), "stamina" = text2num(i[14]),
			"killer" = i[15], "last_words" = i[16], "suicide" = text2num(i[17]))
		if(admin)
			row["key"] = i[18]
			row["killer_key"] = i[19]
		. += list(row)

/// One row a game mode: how many rounds, how long on average, and how they ended
/datum/round_stats/proc/load_modes()
	var/list/arguments = list("admin" = is_admin() ? 1 : 0, "current" = text2num(GLOB.round_id) || 0)
	//AVG() is a DECIMAL, which rust_g reads as null: as text
	var/list/totals = query_rows(SSdbcore.NewQuery({"SELECT IFNULL(game_mode, '?'), COUNT(*), CAST(ROUND(AVG(TIMESTAMPDIFF(MINUTE, start_datetime, IFNULL(end_datetime, shutdown_datetime)))) AS CHAR)
		FROM [format_table_name("round")] WHERE start_datetime IS NOT NULL AND (:admin = 1 OR id != :current) GROUP BY 1 ORDER BY 2 DESC"}, arguments))
	var/list/results = query_rows(SSdbcore.NewQuery({"SELECT IFNULL(game_mode, '?'), IFNULL(game_mode_result, 'undecided'), COUNT(*)
		FROM [format_table_name("round")] WHERE start_datetime IS NOT NULL AND (:admin = 1 OR id != :current) GROUP BY 1, 2 ORDER BY 3 DESC"}, arguments))
	if(!totals || !results)
		return
	. = list()
	var/list/by_mode = list()
	for(var/list/i in totals)
		var/list/row = list("mode" = i[1], "rounds" = text2num(i[2]), "minutes" = text2num(i[3]), "results" = list())
		by_mode[i[1]] = row
		. += list(row)
	for(var/list/i in results)
		var/list/row = by_mode[i[1]]
		if(row)
			row["results"] += list(list("result" = i[2], "rounds" = text2num(i[3])))

/datum/round_stats/proc/load_playtime()
	var/who = is_admin() ? playtime_ckey : owner_ckey
	var/list/found = query_rows(SSdbcore.NewQuery("SELECT job, minutes FROM [format_table_name("role_time")] WHERE ckey = :ckey ORDER BY minutes DESC", list("ckey" = who)))
	if(!found)
		return
	. = list()
	for(var/list/i in found)
		. += list(list("job" = i[1], "minutes" = text2num(i[2])))

/// One round's page: the round, its antagonists and how their objectives went, the round-end numbers (blackbox feedback, written at
/// shutdown), its deaths in order, and for admins its runtimes (round_history.dm). The round being played isn't there for players.
/datum/round_stats/proc/load_round(id)
	var/list/found = load_rounds(id)
	if(!length(found))
		if(!error)
			error = "No round [id]"
		return
	var/admin = is_admin()
	. = list("round" = found[1], "antags" = list(), "stats" = null, "deaths" = list())
	var/list/feedback = query_rows(SSdbcore.NewQuery("SELECT key_name, json FROM [format_table_name("feedback")] WHERE round_id = :id AND key_name IN ('antagonists', 'round_end_stats')", list("id" = id)))
	for(var/list/i in feedback)
		var/list/data
		try
			var/list/json = json_decode(i[2])
			data = json["data"]
		catch
			continue
		if(!islist(data))
			continue
		if(i[1] == "antagonists")
			for(var/n in data)
				var/list/A = data[n]
				if(!islist(A))
					continue
				var/list/objectives = list()
				if(islist(A["objectives"]))
					for(var/list/O in A["objectives"])
						objectives += list(list("text" = O["text"], "result" = O["result"]))
				var/list/team = A["team"]
				var/list/antag = list("name" = A["name"], "role" = A["antagonist_name"], "team" = islist(team) ? team["name"] : null, "objectives" = objectives)
				if(admin)
					antag["key"] = A["key"]
				.["antags"] += list(antag)
		else
			var/list/players = data["players"]
			var/list/survivors = data["survivors"]
			var/list/escapees = data["escapees"]
			.["stats"] = list(
				"players" = islist(players) ? players["total"] : null,
				"dead" = islist(players) ? players["dead"] : null,
				"survivors" = islist(survivors) ? survivors["total"] : null,
				"escapees" = islist(escapees) ? escapees["total"] : null)
	var/list/deaths = query_rows(SSdbcore.NewQuery("SELECT tod, name, job, special, pod, laname, suicide, byondkey, lakey FROM [format_table_name("death")] WHERE round_id = :id ORDER BY tod, id LIMIT :rows",
		list("id" = id, "rows" = ROUND_STATS_ROWS)))
	for(var/list/i in deaths)
		var/list/row = list("time" = i[1], "name" = i[2], "job" = i[3], "special" = i[4], "where" = i[5], "killer" = i[6], "suicide" = text2num(i[7]))
		if(admin)
			row["key"] = i[8]
			row["killer_key"] = i[9]
		.["deaths"] += list(row)
	if(admin)
		.["runtimes"] = list()
		var/had_error = error
		var/list/ran = query_rows(SSdbcore.NewQuery("SELECT file, line, message, count, first_seen FROM [format_table_name("runtime")] WHERE round_id = :id ORDER BY count DESC LIMIT :rows",
			list("id" = id, "rows" = ROUND_STATS_ROWS)))
		for(var/list/i in ran)
			.["runtimes"] += list(list("file" = i[1], "line" = text2num(i[2]), "message" = i[3], "count" = text2num(i[4]), "first" = text2num(i[5])))
		error = had_error //a database with no runtime table yet still shows the page

/// Admins: runtimes by file and line over the last 20 rounds that had any, the most first. New: first seen in the latest of them.
/datum/round_stats/proc/load_runtimes()
	//SUM() is a DECIMAL, which rust_g reads as null: as text. round_id is unsigned, so the subtraction is done signed.
	var/list/found = query_rows(SSdbcore.NewQuery({"SELECT file, line, MIN(message), COUNT(DISTINCT round_id), CAST(SUM(count) AS CHAR), MAX(round_id), MIN(round_id), (SELECT MAX(round_id) FROM [format_table_name("runtime")])
		FROM [format_table_name("runtime")]
		WHERE round_id IN (SELECT round_id FROM (SELECT DISTINCT round_id FROM [format_table_name("runtime")] ORDER BY round_id DESC LIMIT 20) AS latest)
		GROUP BY file, line ORDER BY SUM(count) DESC LIMIT :rows"}, list("rows" = ROUND_STATS_ROWS)))
	if(!found)
		return
	. = list()
	for(var/list/i in found)
		. += list(list("file" = i[1], "line" = text2num(i[2]), "message" = i[3], "rounds" = text2num(i[4]), "count" = text2num(i[5]), "last" = text2num(i[6]),
			"new" = i[7] == i[8]))

#undef ROUND_STATS_ROWS
