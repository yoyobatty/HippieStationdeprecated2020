// hippie -- more admin panels designed for tgui (interfaces/AdminPanels.js): the Player Panel (every player, searchable, with the admin
// buttons), the Game Panel (with the mode lists Change Game Mode and Force Secret opened as pages), Create Antagonist and Modify Goals.
// Built on admin_tools_tgui.dm's tool window; each action is the old link sent with the admin token to the holder's Topic() (a station
// goal's own Topic() for its buttons), and only for a player or goal the panel shows.

// ---------------------------------------------------------------------------------------------
// The Player Panel
// ---------------------------------------------------------------------------------------------

/datum/admins/player_panel_new()
	if(!check_rights())
		return
	log_admin("[key_name(usr)] checked the player panel.")
	open_admin_tool("players", /datum/admin_tool_window/players)

/datum/admin_tool_window/players
	interface = "admin_players"
	title = "Player Panel"
	width = 900
	height = 640

/// player_panel_new()'s job words for a mob
/proc/admin_player_job(mob/M)
	if(isnewplayer(M))
		return "New player"
	if(isobserver(M))
		var/mob/dead/observer/O = M
		return O.started_as_observer ? "Observer" : "Ghost"
	if(ishuman(M))
		return M.job || "Human"
	if(ismonkey(M))
		return "Monkey"
	if(isalien(M))
		return islarva(M) ? "Alien larva" : ROLE_ALIEN
	if(iscarbon(M))
		return "Carbon-based"
	if(isAI(M))
		return "AI"
	if(ispAI(M))
		return ROLE_PAI
	if(iscyborg(M))
		return "Cyborg"
	if(issilicon(M))
		return "Silicon-based"
	if(iscorgi(M))
		return "Corgi"
	if(isslime(M))
		return "Slime"
	if(isanimal(M))
		return "Animal"
	return isliving(M) ? "Living" : "?"

/datum/admin_tool_window/players/proc/player_rows()
	. = list()
	for(var/mob/M in sortmobs())
		if(!M.ckey)
			continue
		var/state = "alive"
		if(isnewplayer(M))
			state = "lobby"
		else if(isobserver(M))
			state = "ghost"
		else if(M.stat == DEAD)
			state = "dead"
		var/list/old_names = list()
		var/datum/player_details/P = GLOB.player_details[M.ckey]
		if(P)
			old_names = P.played_names.Copy()
		. += list(list("ref" = REF(M), "ckey" = M.ckey, "key" = M.key, "name" = M.name, "real_name" = M.real_name, "job" = admin_player_job(M), \
			"state" = state, "antag" = !!is_special_character(M), "client" = !!M.client, "ip" = M.lastKnownIP, "old_names" = old_names, \
			"cyborg" = iscyborg(M), "has_mind" = !!M.mind))

/datum/admin_tool_window/players/ui_data(mob/user)
	return list("players" = player_rows())

/datum/admin_tool_window/players/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("check_antagonists")
			holder.page_holder_link(list("check_antagonist" = "1"))
			return TRUE
		if("kick_lobby")
			holder.page_holder_link(list("kick_all_from_lobby" = "1", "afkonly" = params["afk"] ? "1" : "0"))
			return TRUE
	var/mob/M = locate(params["ref"]) in GLOB.mob_list
	if(!M?.ckey)
		return
	switch(action)
		if("pp")
			holder.page_holder_link(list("adminplayeropts" = REF(M)))
		if("notes")
			holder.page_holder_link(list("showmessageckey" = M.ckey))
		if("vv")
			usr.client.debug_variables(M)
		if("tp")
			holder.page_holder_link(list("traitor" = REF(M)))
		if("bp")
			if(iscyborg(M))
				holder.page_holder_link(list("borgpanel" = REF(M)))
		if("pm")
			usr.client.cmd_admin_pm(M.ckey, null)
		if("sm")
			holder.page_holder_link(list("subtlemessage" = REF(M)))
		if("flw")
			holder.page_holder_link(list("adminplayerobservefollow" = REF(M)))
		if("logs")
			holder.page_holder_link(list("individuallog" = REF(M), "log_src" = M.client ? LOGSRC_CLIENT : LOGSRC_MOB))
	return TRUE

// ---------------------------------------------------------------------------------------------
// The Game Panel, with Change Game Mode and Force Secret Mode as its pages
// ---------------------------------------------------------------------------------------------

/datum/admins/Game()
	if(!check_rights(0))
		return
	open_admin_tool("game", /datum/admin_tool_window/game)

/datum/admins/HandleCMode()
	if(!check_rights(R_ADMIN))
		return
	open_admin_tool("game", /datum/admin_tool_window/game, list("page" = "mode"))

/datum/admins/HandleFSecret()
	if(!check_rights(R_ADMIN))
		return
	if(SSticker.HasRoundStarted())
		return tgui_alert(usr, "The game has already started.")
	if(GLOB.master_mode != "secret")
		return tgui_alert(usr, "The game mode has to be secret!")
	open_admin_tool("game", /datum/admin_tool_window/game, list("page" = "secret"))

/datum/admin_tool_window/game
	interface = "admin_game_panel"
	title = "Game Panel"
	width = 460
	height = 560
	rights = NONE
	var/page

/datum/admin_tool_window/game/setup(list/arguments)
	if(arguments)
		page = arguments["page"]

/datum/admin_tool_window/game/ui_data(mob/user)
	. = list()
	.["page"] = page
	.["master_mode"] = GLOB.master_mode
	.["secret_force"] = GLOB.secret_force_mode
	.["started"] = SSticker.HasRoundStarted()
	.["in_progress"] = SSticker.IsRoundInProgress()
	.["pregame"] = SSticker.current_state <= GAME_STATE_PREGAME
	.["marked"] = (holder.marked_datum && istype(holder.marked_datum, /atom)) ? "[holder.marked_datum]" : null
	var/list/modes = list()
	for(var/mode in config.modes)
		modes += list(list("id" = mode, "name" = config.mode_names[mode]))
	.["modes"] = modes
	if(GLOB.master_mode == "dynamic")
		var/list/forced = list()
		for(var/datum/dynamic_ruleset/roundstart/rule in GLOB.dynamic_forced_roundstart_ruleset)
			forced += list(list("ref" = REF(rule), "name" = rule.name))
		.["dynamic_forced"] = forced
		var/datum/game_mode/dynamic/D = SSticker.mode
		if(istype(D) && D.forced_latejoin_rule)
			.["dynamic_latejoin"] = D.forced_latejoin_rule.name

/datum/admin_tool_window/game/ui_act(action, list/params)
	if(..())
		return
	var/static/list/plain = list("gamemode_panel", "create_object", "quick_create_object", "create_turf", "create_mob", "dupe_marked_datum", \
		"f_dynamic_roundstart", "f_dynamic_roundstart_clear", "f_dynamic_options", "f_dynamic_latejoin", "f_dynamic_latejoin_clear", "f_dynamic_midround")
	switch(action)
		if("page")
			page = (params["page"] in list("mode", "secret")) ? params["page"] : null
		if("link")
			var/link = "[params["link"]]"
			if(link in plain)
				holder.page_holder_link(list("[link]" = "1"))
		if("set_mode")
			var/mode = "[params["mode"]]"
			if((mode in config.modes) || (mode in list("secret", "random")))
				holder.page_holder_link(list("c_mode2" = mode))
				page = null
		if("force_secret")
			var/mode = "[params["mode"]]"
			if((mode in config.modes) || mode == "secret")
				holder.page_holder_link(list("f_secret2" = mode))
				page = null
		if("remove_ruleset")
			var/datum/dynamic_ruleset/roundstart/rule = locate(params["ref"]) in GLOB.dynamic_forced_roundstart_ruleset
			if(rule)
				holder.page_holder_link(list("f_dynamic_roundstart_remove" = REF(rule)))
	return TRUE

// ---------------------------------------------------------------------------------------------
// Create Antagonist (one_click_antag.dm)
// ---------------------------------------------------------------------------------------------

/datum/admins/one_click_antag()
	open_admin_tool("one_click", /datum/admin_tool_window/one_click)

/datum/admin_tool_window/one_click
	interface = "admin_one_click_antag"
	title = "Create Antagonist"
	width = 440
	height = 560

/// one_click_antag()'s list: makeAntag= value, name, whether it needs ghosts, and a sentence of what it does
/datum/admin_tool_window/one_click/proc/kinds()
	var/static/list/K = list(
		list("id" = "traitors", "name" = "Traitors", "ghosts" = FALSE, "icon" = "user-secret"),
		list("id" = "changelings", "name" = "Changelings", "ghosts" = FALSE, "icon" = "dna"),
		list("id" = "revs", "name" = "Revolutionaries", "ghosts" = FALSE, "icon" = "fist-raised"),
		list("id" = "cult", "name" = "Blood cult", "ghosts" = FALSE, "icon" = "tint"),
		list("id" = "clockcult", "name" = "Clockwork cult", "ghosts" = FALSE, "icon" = "cog"),
		list("id" = "blob", "name" = "Blob", "ghosts" = FALSE, "icon" = "circle"),
		list("id" = "shadowling", "name" = "Shadowling", "ghosts" = FALSE, "icon" = "moon"),
		list("id" = "messiah", "name" = "Space Jesus", "ghosts" = FALSE, "icon" = "cross"),
		list("id" = "wizard", "name" = "Wizard", "ghosts" = TRUE, "icon" = "hat-wizard"),
		list("id" = "nukeops", "name" = "Nuke team", "ghosts" = TRUE, "icon" = "radiation"),
		list("id" = "centcom", "name" = "CentCom response team", "ghosts" = TRUE, "icon" = "shield-alt"),
		list("id" = "abductors", "name" = "Abductor team", "ghosts" = TRUE, "icon" = "user-astronaut"),
		list("id" = "revenant", "name" = "Revenant", "ghosts" = TRUE, "icon" = "ghost"),
		list("id" = "infiltrator", "name" = "Infiltration team", "ghosts" = TRUE, "icon" = "user-ninja"),
	)
	return K

/datum/admin_tool_window/one_click/ui_data(mob/user)
	var/ghosts = 0
	for(var/mob/dead/observer/G in GLOB.player_list)
		if(G.client)
			ghosts++
	return list("kinds" = kinds(), "ghosts" = ghosts, "started" = SSticker.HasRoundStarted())

/datum/admin_tool_window/one_click/ui_act(action, list/params)
	if(..())
		return
	if(action != "make")
		return
	for(var/list/K in kinds())
		if(K["id"] == params["id"])
			holder.page_holder_link(list("makeAntag" = K["id"]))
			return TRUE

// ---------------------------------------------------------------------------------------------
// Modify Goals (randomverbs.dm)
// ---------------------------------------------------------------------------------------------

/datum/admins/modify_goals()
	open_admin_tool("goals", /datum/admin_tool_window/goals)

/datum/admin_tool_window/goals
	interface = "admin_station_goals"
	title = "Station Goals"
	width = 460
	height = 420

/datum/admin_tool_window/goals/ui_data(mob/user)
	var/list/goals = list()
	for(var/datum/station_goal/S in SSticker.mode?.station_goals)
		goals += list(list("ref" = REF(S), "name" = S.name, "report" = trim(comm_plain_text(S.get_report())), "done" = !!S.check_completion()))
	return list("goals" = goals)

/datum/admin_tool_window/goals/ui_act(action, list/params)
	if(..())
		return
	if(action == "add")
		holder.page_holder_link(list("add_station_goal" = "1"))
		return TRUE
	var/datum/station_goal/S = locate(params["ref"]) in SSticker.mode?.station_goals
	if(!S || !(action in list("announce", "remove")))
		return
	// The goal's own Topic() checks the token itself
	var/list/href_list = list("[action]" = "1", "admin_token" = RawHrefToken())
	S.Topic(list2params(href_list), href_list)
	return TRUE
