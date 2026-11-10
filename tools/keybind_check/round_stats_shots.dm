// Round Stats with a real client (hippiestation/code/modules/stats/round_stats.dm): every tab as a player, then as an admin, against a
// throwaway database seeded with finished rounds and deaths. Not part of the game:
//   DB_PORT=3307 DB_NAME=hippie_stats DB_PASS=... HARNESS=round_stats_shots.dm SENDER=shot.ps1 tools/keybind_check/run.sh roundstats
// Results in data/keycheck_roundstats.txt, pictures in data/previews/popup_roundstats_*.png.

GLOBAL_VAR_INIT(keycheck_running, FALSE)

/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

/proc/kc_log(text)
	text2file(text, "data/keycheck.txt")

/client/New()
	. = ..()
	if(. && !GLOB.keycheck_running)
		GLOB.keycheck_running = TRUE
		spawn(50)
			round_stats_shots_run(src)

/proc/rs_check(name, ok, detail = "")
	kc_log("[ok ? "PASS" : "FAIL"] [name][detail ? " ([detail])" : ""]")

/proc/rs_shot(name)
	fdel("data/keycheck_shot_title") //tgui windows have no caption: the biggest popup
	text2file("popup_[name]", "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/// The window, once the page has loaded
/proc/rs_ui(mob/user, datum/src_object)
	var/deadline = world.time + 20 SECONDS
	while(world.time < deadline)
		for(var/datum/tgui/open as anything in user.open_uis)
			if(open.src_object == src_object && open.initialized)
				return open
		sleep(2)

/// A button press, as the page sends it (ui_act wants the window)
/proc/rs_act(datum/round_stats/stats, action, list/params)
	var/client/C = GLOB.directory[stats.owner_ckey]
	var/datum/tgui/ui = rs_ui(C.mob, stats)
	stats.ui_act(action, params, ui, ui?.state)
	sleep(2)
	UNTIL(!stats.loading)
	sleep(15)

/// A tab, read and shown
/proc/rs_tab(datum/round_stats/stats, tab, list/extra)
	var/list/params = list("tab" = tab)
	if(extra)
		params |= extra
	rs_act(stats, "tab", params)

/proc/round_stats_shots_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE //a round being played, which players mustn't see in the list
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	//their playtime, logged the way update_exp_db() logs it
	SSdbcore.MassInsert(format_table_name("role_time"), list(
		list("ckey" = C.ckey, "job" = "Living", "minutes" = 1914), list("ckey" = C.ckey, "job" = "Ghost", "minutes" = 342),
		list("ckey" = C.ckey, "job" = "Station Engineer", "minutes" = 806), list("ckey" = C.ckey, "job" = "Chief Engineer", "minutes" = 431),
		list("ckey" = C.ckey, "job" = "Atmospheric Technician", "minutes" = 297), list("ckey" = C.ckey, "job" = "Assistant", "minutes" = 212),
		list("ckey" = C.ckey, "job" = "Clown", "minutes" = 96), list("ckey" = C.ckey, "job" = "traitor", "minutes" = 72)),
		duplicate_key = "ON DUPLICATE KEY UPDATE minutes = VALUES(minutes)")

	//a player first: the host connects as an admin
	if(C.holder)
		C.holder.deactivate()
	sleep(1 SECONDS)
	C.round_stats()
	var/datum/round_stats/stats = C.round_stats
	rs_check("the window opens", rs_ui(C.mob, stats))
	UNTIL(!stats.loading)
	sleep(2 SECONDS)
	rs_check("player: rounds read", length(stats.rounds) >= 10, "[length(stats.rounds)]")
	var/current = text2num(GLOB.round_id)
	var/shows_current = FALSE
	for(var/list/row in stats.rounds)
		if(row["id"] == current)
			shows_current = TRUE
	rs_check("player: the round being played isn't listed", !shows_current, "round [current]")
	rs_check("player: no server address", length(stats.rounds) && !stats.rounds[1]["server"])
	rs_shot("roundstats_rounds")

	rs_tab(stats, "deaths")
	rs_check("player: deaths read, without keys", length(stats.deaths) >= 10 && !stats.deaths[1]["key"], "[length(stats.deaths)]")
	rs_shot("roundstats_deaths")

	var/list/busy_round
	for(var/list/row in stats.rounds)
		if(!busy_round || row["deaths"] > busy_round["deaths"])
			busy_round = row
	rs_tab(stats, "deaths", list("round" = "[busy_round["id"]]"))
	var/all_that_round = TRUE
	for(var/list/row in stats.deaths)
		if(row["round"] != busy_round["id"])
			all_that_round = FALSE
	rs_check("player: one round's deaths", length(stats.deaths) == busy_round["deaths"] && all_that_round, "round [busy_round["id"]]: [length(stats.deaths)] of [busy_round["deaths"]]")
	rs_shot("roundstats_round_deaths")
	rs_act(stats, "round_filter", list("round" = null))
	rs_act(stats, "search", list("search" = "Engineer"))
	var/all_engineers = length(stats.deaths) > 0
	for(var/list/row in stats.deaths)
		if(!findtext(row["job"], "Engineer") && !findtext(row["name"], "Engineer") && !findtext(row["where"], "Engineer") && !findtext(row["killer"], "Engineer"))
			all_engineers = FALSE
	rs_check("player: search", all_engineers, "[length(stats.deaths)]")
	rs_act(stats, "search", list("search" = ""))

	rs_tab(stats, "modes")
	var/list/top = stats.modes?[1]
	rs_check("player: modes, most played first, with results", top && top["mode"] == "traitor" && length(top["results"]) >= 1 && top["minutes"] > 0, json_encode(top))
	rs_shot("roundstats_modes")

	rs_tab(stats, "playtime")
	rs_check("player: their playtime", length(stats.playtime) == 8 && stats.playtime[1]["job"] == "Living", json_encode(stats.playtime?[1]))
	rs_shot("roundstats_playtime")

	//a round's page (round_stats_seed.sql gives round 4 its antagonists, round-end numbers and runtimes)
	rs_act(stats, "round", list("round" = 4))
	var/list/antags = stats.page?["antags"]
	rs_check("player: a round's page, its antagonists and objectives", length(antags) == 2 && length(antags[1]["objectives"]) == 3 && !antags[1]["key"], json_encode(antags?[1]))
	rs_check("player: its round-end numbers and deaths, no runtimes", stats.page?["stats"]?["escapees"] == 14 && length(stats.page?["deaths"]) == 5 && !stats.page?["runtimes"])
	rs_shot("roundstats_round_page")
	rs_act(stats, "round", list("round" = current))
	rs_check("player: the round being played has no page", !stats.page && stats.error, stats.error)
	rs_tab(stats, "runtimes")
	rs_check("player: no runtimes tab", stats.tab != "runtimes")

	//as an admin
	var/datum/admins/was = GLOB.deadmins[C.ckey]
	if(was)
		was.activate()
	else if(!C.holder)
		var/datum/admins/A = new(new /datum/admin_rank("!localhost!", R_EVERYTHING, R_DBRANKS, R_EVERYTHING), C.ckey, 1, 1)
		A.associate(C)
	sleep(1 SECONDS)
	rs_tab(stats, "rounds")
	shows_current = FALSE
	for(var/list/row in stats.rounds)
		if(row["id"] == current)
			shows_current = TRUE
	rs_check("admin: the round being played is listed, with the server", shows_current && length(stats.rounds) && stats.rounds[1]["server"], "round [current]")
	rs_shot("roundstats_admin_rounds")
	rs_tab(stats, "deaths")
	rs_check("admin: deaths with keys", length(stats.deaths) && stats.deaths[1]["key"])
	rs_shot("roundstats_admin_deaths")
	rs_tab(stats, "playtime")
	rs_act(stats, "playtime_ckey", list("ckey" = "Nobody Here"))
	rs_check("admin: another key's playtime", stats.playtime_ckey == "nobodyhere" && !length(stats.playtime))
	rs_act(stats, "round", list("round" = 4))
	rs_check("admin: a round's page, with keys and runtimes", stats.page?["antags"]?[1]?["key"] == "Shotsplayer" && length(stats.page?["runtimes"]) == 3, json_encode(stats.page?["runtimes"]))
	rs_shot("roundstats_admin_round_page")
	rs_tab(stats, "runtimes")
	var/list/sites = stats.runtimes
	rs_check("admin: runtimes by site, the most first", length(sites) >= 4 && sites[1]["count"] >= sites[2]["count"], json_encode(sites?[1]))
	rs_shot("roundstats_admin_runtimes")

	text2file("done", "data/keycheck_shots_done")
	sleep(2 SECONDS)
	kc_log("done")
