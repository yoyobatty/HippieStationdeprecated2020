// The lobby and the late-join job list in tgui-next (Lobby.js), in place of the old HTML panel and job table
// (code/modules/mob/dead/new_player/new_player.dm). Same buttons, sent through the lobby mob's own Topic(), plus the
// round's state; the job list is grouped by department and shows full and locked jobs too, greyed, with why. The
// lobby window can't be closed, like the old one (can_close=0).

/// The lobby's look (Lobby.js): "pass", the boarding pass the user picked; the other prototypes stay selectable by
/// setting this: "hud", "board", "crt", or anything else for the plain panel
GLOBAL_VAR_INIT(lobby_design, "pass")

/mob/dead/new_player
	/// Polls can be shown (not a guest, the DB is up); looked up when the lobby opens, as it queries the DB
	var/lobby_has_polls = FALSE
	/// There are polls this player hasn't answered
	var/lobby_new_polls = FALSE
	/// The character's front view as a PNG data URI, made when the lobby opens and when Character Setup closes
	var/lobby_portrait
	var/datum/late_join_menu/late_join_menu

/mob/dead/new_player/proc/lobby_make_portrait()
	lobby_portrait = null
	var/datum/preferences/P = client?.prefs
	if(!P)
		return
	P.update_preview_icon()
	if(!P.preview_screen)
		return
	var/icon/flat = getFlatIcon(P.preview_screen, SOUTH, no_anim = TRUE)
	if(flat)
		lobby_portrait = "data:image/png;base64,[icon2base64(flat)]"

/mob/dead/new_player/ui_static_data(mob/user)
	return list("portrait" = lobby_portrait)

/// Character Setup closed: the lobby's portrait and name follow what was picked
/datum/preferences/ui_close(mob/user)
	..()
	var/mob/dead/new_player/NP = user
	if(istype(NP) && NP.client && SStgui.get_open_ui(NP, NP, "lobby"))
		NP.lobby_make_portrait()
		NP.update_static_data(NP, null, "lobby")

/mob/dead/new_player/Destroy()
	QDEL_NULL(late_join_menu)
	return ..()

/mob/dead/new_player/new_player_panel()
	if(!client)
		return
	if(SStgui.get_open_ui(src, src, "lobby"))
		SStgui.update_uis(src)
		return
	src << browse(null, "window=playersetup")
	lobby_check_polls()
	if(QDELETED(src) || !client)
		return
	lobby_make_portrait()
	ui_interact(src)

/mob/dead/new_player/proc/lobby_check_polls()
	lobby_has_polls = FALSE
	lobby_new_polls = FALSE
	if(IsGuestKey(key) || !SSdbcore.Connect())
		return
	lobby_has_polls = TRUE
	var/isadmin = client?.holder ? 1 : 0
	var/datum/DBQuery/query_get_new_polls = SSdbcore.NewQuery("SELECT id FROM [format_table_name("poll_question")] WHERE (:admin = 1 OR adminonly = false) AND Now() BETWEEN starttime AND endtime AND id NOT IN (SELECT pollid FROM [format_table_name("poll_vote")] WHERE ckey = :ckey) AND id NOT IN (SELECT pollid FROM [format_table_name("poll_textreply")] WHERE ckey = :ckey)", list("ckey" = ckey, "admin" = isadmin))
	if(query_get_new_polls.Execute() && query_get_new_polls.NextRow())
		lobby_new_polls = TRUE
	qdel(query_get_new_polls)

/mob/dead/new_player/ui_interact(mob/user, ui_key = "lobby", datum/tgui/ui = null, force_open = FALSE, \
									datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "lobby", station_name(), 380, 480, master_ui, state)
		ui.no_close = TRUE
		ui.open()
		if(user.client)
			LAZYOR(user.client.lobby_windows, ui.window_id)

/// Only the lobby mob's own player
/mob/dead/new_player/ui_status(mob/user, datum/ui_state/state)
	if(user != src)
		return UI_CLOSE
	return ..()

/client
	/// The lobby's windows on this client's screen. A client moved into another mob any way but joining or observing
	/// (an admin putting them in a body) leaves the lobby mob without a client, so tgui's own close never reaches the
	/// screen, and the lobby can't be closed by hand: they're closed when the client lands anywhere else.
	var/list/lobby_windows

/mob/Login()
	. = ..()
	if(client && length(client.lobby_windows) && !isnewplayer(src))
		for(var/window in client.lobby_windows)
			if(!client.tgui_pool?.release_id(window)) // a pooled window is hidden and kept, not closed (tgui_pool.dm)
				src << browse(null, "window=[window]")
		client.lobby_windows = null

/// What the round is doing, for both windows
/proc/lobby_round_data()
	var/list/data = list()
	var/state = SSticker.current_state
	data["startup"] = state == GAME_STATE_STARTUP
	data["pregame"] = state <= GAME_STATE_PREGAME
	data["setting_up"] = state == GAME_STATE_SETTING_UP
	data["ended"] = state >= GAME_STATE_FINISHED
	data["map"] = SSmapping.config?.map_name
	data["round_id"] = GLOB.round_id
	data["station"] = station_name()
	data["design"] = GLOB.lobby_design
	if(state <= GAME_STATE_PREGAME)
		var/left = SSticker.GetTimeLeft()
		data["time_left"] = left > 0 ? round(left / 10) : 0
		data["delayed"] = left == -10
		data["countdown"] = CONFIG_GET(number/lobby_countdown)
	else
		data["round_time"] = round((world.time - SSticker.round_start_time) / 10)
		data["crew"] = length(GLOB.data_core.general)
		if(SSshuttle.emergency)
			switch(SSshuttle.emergency.mode)
				if(SHUTTLE_ESCAPE)
					data["evac"] = "Evacuated"
				if(SHUTTLE_CALL)
					if(!SSshuttle.canRecall())
						data["evac"] = "Evacuating"
	return data

/mob/dead/new_player/ui_data(mob/user)
	var/list/data = lobby_round_data()
	data["ready"] = ready
	data["players"] = SSticker.totalPlayers
	if(client?.holder)
		data["players_ready"] = SSticker.totalPlayersReady
	var/datum/preferences/prefs = client?.prefs
	if(prefs)
		data["dark"] = prefs.pass_dark
		data["character"] = prefs.be_random_name ? "Random" : prefs.real_name
		for(var/title in prefs.job_preferences)
			if(prefs.job_preferences[title] == JP_HIGH)
				data["job"] = title
				break
	data["queue"] = SSticker.queued_players.Find(src)
	data["polls"] = lobby_has_polls
	data["new_polls"] = lobby_new_polls
	return data

/mob/dead/new_player/ui_act(action, list/params)
	if(..())
		return
	if(usr != src || !client)
		return
	switch(action)
		if("setup")
			Topic(null, list("show_preferences" = "1"))
		if("ready")
			var/value = text2num(params["value"])
			if(!(value in list(PLAYER_NOT_READY, PLAYER_READY_TO_PLAY, PLAYER_READY_TO_OBSERVE)))
				return
			Topic(null, list("ready" = "[value]"))
		if("join")
			Topic(null, list("late_join" = "1"))
		if("manifest")
			Topic(null, list("manifest" = "1"))
		if("polls")
			Topic(null, list("showpoll" = "1"))
	return TRUE

/mob/dead/new_player/close_spawn_windows()
	..()
	SStgui.close_uis(src)
	if(late_join_menu)
		SStgui.close_uis(late_join_menu)

/// A late join that fell through (full, malfunctioning arrivals) closed the lobby first: bring it back.
/// One that went through gets the round's shift notes, as everyone did when it started (station_looks.dm).
/mob/dead/new_player/AttemptLateSpawn(rank)
	var/client/joining = client
	. = ..()
	if(!. && !QDELETED(src) && client && !spawning)
		new_player_panel()
	else if(. && joining)
		var/notes = SSstation_looks.shift_notes()
		if(notes)
			to_chat(joining, notes)

/mob/dead/new_player/LateChoices()
	if(!client)
		return
	for(var/datum/job/prioritized_job in SSjob.prioritized_jobs)
		if(prioritized_job.current_positions >= prioritized_job.total_positions)
			SSjob.prioritized_jobs -= prioritized_job
	if(!late_join_menu)
		late_join_menu = new(src)
	late_join_menu.ui_interact(src)

// The job list

/datum/late_join_menu
	var/mob/dead/new_player/owner

/datum/late_join_menu/New(mob/dead/new_player/new_owner)
	owner = new_owner

/datum/late_join_menu/Destroy()
	SStgui.close_uis(src)
	owner = null
	return ..()

/datum/late_join_menu/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
									datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "late_join", "Choose Profession", 660, 590, master_ui, state)
		ui.open()
		if(user.client)
			LAZYOR(user.client.lobby_windows, ui.window_id)

/datum/late_join_menu/ui_status(mob/user, datum/ui_state/state)
	if(user != owner || QDELETED(owner) || owner.spawning)
		return UI_CLOSE
	return ..()

/datum/late_join_menu/ui_data(mob/user)
	var/list/data = lobby_round_data()
	var/list/departments = list()
	var/list/categories = list(GLOB.command_positions, GLOB.engineering_positions, GLOB.supply_positions, GLOB.nonhuman_positions - "pAI", \
								GLOB.civilian_positions, GLOB.medical_positions, GLOB.science_positions, GLOB.security_positions)
	for(var/list/category in categories)
		if(!length(category))
			continue
		var/datum/job/head = SSjob.name_occupations[category[1]]
		if(!head)
			continue
		var/list/jobs = list()
		for(var/title in category)
			var/datum/job/J = SSjob.name_occupations[title]
			if(!J)
				continue
			var/why = owner.IsJobUnavailable(J.title, TRUE)
			jobs += list(list(
				"title" = J.title,
				"filled" = J.current_positions,
				"slots" = J.total_positions,
				"priority" = (J in SSjob.prioritized_jobs),
				"command" = (title in GLOB.command_positions),
				"status" = late_join_status_word(why),
			))
		departments += list(list(
			"name" = head.exp_type_department,
			"color" = head.selection_color,
			"jobs" = jobs,
		))
	data["departments"] = departments
	data["dark"] = owner.client?.prefs?.pass_dark
	data["can_join"] = SSticker.IsRoundInProgress() && GLOB.enter_allowed
	data["queue"] = SSticker.queued_players.Find(owner)
	return data

/proc/late_join_status_word(why)
	switch(why)
		if(JOB_AVAILABLE)
			return null
		if(JOB_UNAVAILABLE_SLOTFULL)
			return "Full"
		if(JOB_UNAVAILABLE_BANNED)
			return "Banned"
		if(JOB_UNAVAILABLE_PLAYTIME)
			return "Playtime"
		if(JOB_UNAVAILABLE_ACCOUNTAGE)
			return "Account age"
	return "Closed"

/datum/late_join_menu/ui_act(action, list/params)
	if(..())
		return
	if(usr != owner || !owner.client)
		return
	if(action == "join")
		var/datum/job/J = SSjob.GetJob(params["job"])
		if(!J)
			return
		owner.Topic(null, list("SelectedJob" = J.title))
		return TRUE
