// hippie -- the vote panel is a tgui window (VotePanel.js), SSvote itself is its source.
// Before: a datum/browser page, built again for every voter every second (the flicker), that had to be reopened to see
// anything new. Now the counts and the time left come live, your own pick is lit, and you can change it until the vote
// ends. Starting votes, the admin toggles and Cancel are the old page's, through the same checks.

/// ckey -> index of the choice that ckey picked (was a plain list of ckeys; get_result()'s `non_voters -= voted` still works)
/datum/controller/subsystem/vote/var/list/vote_picks = list()

/datum/controller/subsystem/vote/fire()
	if(!mode)
		return
	time_remaining = round((started_time + CONFIG_GET(number/vote_period) - world.time) / 10)
	if(time_remaining < 0)
		result()
		SStgui.close_uis(src)
		reset()
	else
		SStgui.update_uis(src)

/datum/controller/subsystem/vote/reset()
	. = ..()
	vote_picks.Cut()
	SStgui.update_uis(src)

/// One vote a ckey; picking another choice moves it.
/datum/controller/subsystem/vote/submit_vote(vote)
	if(!mode || !usr?.client)
		return 0
	if(CONFIG_GET(flag/no_dead_vote) && usr.stat == DEAD && !usr.client.holder)
		return 0
	if(!vote || vote < 1 || vote > length(choices))
		return 0
	var/old = vote_picks[usr.ckey]
	if(old == vote)
		return vote
	if(old && old <= length(choices))
		choices[choices[old]] = max(0, choices[choices[old]] - 1)
	voted |= usr.ckey
	vote_picks[usr.ckey] = vote
	choices[choices[vote]]++
	return vote

/mob/vote()
	if(client)
		SSvote.ui_interact(src)

/datum/controller/subsystem/vote/ui_interact(mob/user, ui_key = "vote", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "vote_panel", "Vote", 400, 360, master_ui, state)
		ui.open()

/datum/controller/subsystem/vote/ui_data(mob/user)
	var/list/data = list()
	var/client/C = user.client
	var/trialmin = C && check_rights_for(C, R_ADMIN)
	data["mode"] = mode
	data["question"] = question
	data["initiator"] = initiator
	data["time_left"] = max(0, time_remaining)
	data["vote_period"] = round(CONFIG_GET(number/vote_period) / 10)
	data["admin"] = C?.holder ? TRUE : FALSE
	data["trialmin"] = trialmin ? TRUE : FALSE
	data["my_vote"] = C ? (vote_picks[C.ckey] || 0) : 0
	data["dead_blocked"] = (CONFIG_GET(flag/no_dead_vote) && user.stat == DEAD && !C?.holder) ? TRUE : FALSE
	var/list/rows = list()
	var/total = 0
	for(var/i in 1 to length(choices))
		var/votes = choices[choices[i]] || 0
		total += votes
		rows += list(list("name" = "[choices[i]]", "votes" = votes))
	data["choices"] = rows
	data["total"] = total
	if(!mode)
		var/list/starts = list()
		starts += list(vote_start_row("restart", "Restart", CONFIG_GET(flag/allow_vote_restart), trialmin, min_restart_time))
		starts += list(vote_start_row("shuttlecall", "Call Shuttle", CONFIG_GET(flag/allow_vote_shuttlecall), trialmin, min_shuttle_time))
		starts += list(vote_start_row("gamemode", "Game Mode", CONFIG_GET(flag/allow_vote_mode), trialmin, 0))
		if(trialmin)
			starts += list(list("type" = "custom", "name" = "Custom", "allowed" = TRUE, "can_start" = TRUE, "toggle" = FALSE, "wait" = 0))
		data["starts"] = starts
		var/next = started_time ? started_time + CONFIG_GET(number/vote_delay) - world.time : 0
		data["cooldown"] = (next > 0 && !C?.holder) ? round(next / 10) : 0
	return data

/datum/controller/subsystem/vote/proc/vote_start_row(type, name, allowed, trialmin, min_time)
	var/wait = min_time > world.time ? round((min_time - world.time) / 10) : 0
	return list(
		"type" = type,
		"name" = name,
		"allowed" = allowed ? TRUE : FALSE,
		"can_start" = (allowed || trialmin) ? TRUE : FALSE,
		"toggle" = trialmin ? TRUE : FALSE,
		"wait" = wait,
	)

/// The old page's links, through the same Topic() and its checks
/datum/controller/subsystem/vote/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("vote")
			var/i = text2num(params["index"])
			if(i)
				submit_vote(round(i))
			return TRUE
		if("start", "toggle")
			var/static/list/allowed = list("restart", "shuttlecall", "gamemode", "custom")
			var/type = params["type"]
			if(!(type in allowed) || (action == "toggle" && type == "custom"))
				return
			vote_topic(action == "toggle" ? "toggle_[type]" : type)
			return TRUE
		if("cancel")
			vote_topic("cancel")
			return TRUE

/// Runs one of the old page's actions without reopening a window afterwards (Topic() ends with usr.vote())
/datum/controller/subsystem/vote/proc/vote_topic(what)
	if(!usr?.client)
		return
	switch(what)
		if("cancel")
			if(usr.client.holder)
				reset()
		if("toggle_restart")
			if(usr.client.holder)
				CONFIG_SET(flag/allow_vote_restart, !CONFIG_GET(flag/allow_vote_restart))
		if("toggle_shuttlecall")
			if(usr.client.holder)
				CONFIG_SET(flag/allow_vote_shuttlecall, !CONFIG_GET(flag/allow_vote_shuttlecall))
		if("toggle_gamemode")
			if(usr.client.holder)
				CONFIG_SET(flag/allow_vote_mode, !CONFIG_GET(flag/allow_vote_mode))
		if("restart")
			if(CONFIG_GET(flag/allow_vote_restart) || usr.client.holder)
				if(min_restart_time < world.time)
					initiate_vote("restart", usr.key)
				else
					to_chat(usr, "<span class='boldannounce'>Restart can only initiate after [DisplayTimeText(min_restart_time)].</span>")
		if("shuttlecall")
			if(CONFIG_GET(flag/allow_vote_shuttlecall) || usr.client.holder)
				if(min_shuttle_time < world.time)
					initiate_vote("shuttlecall", usr.key)
				else
					to_chat(usr, "<span class='boldannounce'>Shuttle call can only initiate after [DisplayTimeText(min_shuttle_time)].</span>")
		if("gamemode")
			if(CONFIG_GET(flag/allow_vote_mode) || usr.client.holder)
				initiate_vote("gamemode", usr.key)
		if("custom")
			if(usr.client.holder)
				initiate_vote("custom", usr.key)
	SStgui.update_uis(src)
