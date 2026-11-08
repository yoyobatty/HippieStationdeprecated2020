// hippie -- player polls in tgui (interfaces/PlayerPolls.js), where the lobby's Polls button used to open two old HTML pages. The list
// and each poll are read with poll.dm's own queries (in the background: the database can be slow, and a window's data can't wait), and a
// vote goes through new_player.dm's Topic() with the fields the old forms sent, so every check (the poll still open, the option the
// poll's, the vote not rigged, the limits) is the old code's.

/mob/dead/new_player
	var/datum/poll_window/poll_window

/mob/dead/new_player/handle_player_polling()
	if(!poll_window)
		poll_window = new(src)
	poll_window.pollid = null
	poll_window.ui_interact(src)
	INVOKE_ASYNC(poll_window, TYPE_PROC_REF(/datum/poll_window, load_list))

/mob/dead/new_player/poll_player(pollid)
	if(!pollid)
		return
	if(!poll_window)
		poll_window = new(src)
	poll_window.ui_interact(src)
	INVOKE_ASYNC(poll_window, TYPE_PROC_REF(/datum/poll_window, load_poll), pollid)

/mob/dead/new_player/Destroy()
	QDEL_NULL(poll_window)
	return ..()

/datum/poll_window
	var/mob/dead/new_player/player
	var/loading = FALSE
	var/error
	/// The open polls: list(list("id", "question"))
	var/list/polls
	/// The poll being looked at, or null for the list
	var/pollid
	var/list/poll

/datum/poll_window/New(mob/dead/new_player/owner)
	player = owner

/datum/poll_window/Destroy()
	SStgui.close_uis(src)
	player = null
	return ..()

/datum/poll_window/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "player_polls", "Player Polls", 560, 560, master_ui, state)
		ui.open()

/datum/poll_window/ui_status(mob/user, datum/ui_state/state)
	return user == player ? UI_INTERACTIVE : UI_CLOSE

/datum/poll_window/ui_data(mob/user)
	return list("loading" = loading, "error" = error, "polls" = polls, "poll" = pollid ? poll : null)

/// handle_player_polling()'s query
/datum/poll_window/proc/load_list()
	loading = TRUE
	error = null
	SStgui.update_uis(src)
	. = list()
	if(!SSdbcore.Connect())
		error = "Failed to establish database connection."
	else
		var/datum/DBQuery/query_poll_get = SSdbcore.NewQuery("SELECT id, question FROM [format_table_name("poll_question")] WHERE Now() BETWEEN starttime AND endtime [(player?.client?.holder ? "" : "AND adminonly = false")]")
		if(query_poll_get.warn_execute())
			while(query_poll_get.NextRow())
				. += list(list("id" = text2num(query_poll_get.item[1]), "question" = query_poll_get.item[2]))
		else
			error = "The polls couldn't be read."
		qdel(query_poll_get)
	if(QDELETED(src))
		return
	polls = .
	loading = FALSE
	SStgui.update_uis(src)

/// poll_player()'s queries: the poll, its options and this player's votes
/datum/poll_window/proc/load_poll(id)
	id = text2num(id)
	if(!id || !player)
		return
	pollid = id
	poll = null
	loading = TRUE
	error = null
	SStgui.update_uis(src)
	var/list/P = list("id" = id)
	var/ckey = player.ckey
	if(!SSdbcore.Connect())
		error = "Failed to establish database connection."
	else
		var/datum/DBQuery/q = SSdbcore.NewQuery("SELECT starttime, endtime, question, polltype, multiplechoiceoptions FROM [format_table_name("poll_question")] WHERE id = :pollid", list("pollid" = id))
		if(q.warn_execute() && q.NextRow())
			P["start"] = q.item[1]
			P["end"] = q.item[2]
			P["question"] = q.item[3]
			P["type"] = q.item[4]
			P["max_choices"] = text2num(q.item[5])
		qdel(q)
		var/list/options = list()
		var/list/voted = list()
		switch(P["type"])
			if(POLLTYPE_TEXT)
				q = SSdbcore.NewQuery("SELECT replytext FROM [format_table_name("poll_textreply")] WHERE pollid = :pollid AND ckey = :ckey", list("pollid" = id, "ckey" = ckey))
				if(q.warn_execute() && q.NextRow())
					P["reply"] = q.item[1]
				qdel(q)
			if(POLLTYPE_RATING)
				q = SSdbcore.NewQuery("SELECT id, text, minval, maxval, descmin, descmid, descmax FROM [format_table_name("poll_option")] WHERE pollid = :pollid", list("pollid" = id))
				if(q.warn_execute())
					while(q.NextRow())
						options += list(list("id" = text2num(q.item[1]), "text" = q.item[2], "min" = text2num(q.item[3]), "max" = text2num(q.item[4]), \
							"desc_min" = q.item[5], "desc_mid" = q.item[6], "desc_max" = q.item[7]))
				qdel(q)
				q = SSdbcore.NewQuery("SELECT optionid, rating FROM [format_table_name("poll_vote")] WHERE pollid = :pollid AND ckey = :ckey", list("pollid" = id, "ckey" = ckey))
				if(q.warn_execute())
					while(q.NextRow())
						voted["[q.item[1]]"] = isnull(q.item[2]) ? "abstain" : text2num(q.item[2])
				qdel(q)
			else // option, multiple choice, ranked (IRV)
				q = SSdbcore.NewQuery("SELECT id, text FROM [format_table_name("poll_option")] WHERE pollid = :pollid", list("pollid" = id))
				if(q.warn_execute())
					while(q.NextRow())
						options += list(list("id" = text2num(q.item[1]), "text" = q.item[2]))
				qdel(q)
				q = SSdbcore.NewQuery("SELECT optionid FROM [format_table_name("poll_vote")] WHERE pollid = :pollid AND ckey = :ckey", list("pollid" = id, "ckey" = ckey))
				if(q.warn_execute())
					while(q.NextRow())
						voted += text2num(q.item[1])
				qdel(q)
		P["options"] = options
		P["voted"] = voted
	if(QDELETED(src) || pollid != id)
		return
	poll = P
	loading = FALSE
	SStgui.update_uis(src)

/datum/poll_window/ui_act(action, list/params)
	if(..())
		return
	if(usr != player || loading)
		return
	switch(action)
		if("list")
			pollid = null
			INVOKE_ASYNC(src, PROC_REF(load_list))
		if("open")
			INVOKE_ASYNC(src, PROC_REF(load_poll), params["id"])
		if("vote")
			if(!poll || !pollid)
				return
			INVOKE_ASYNC(src, PROC_REF(send_vote), params)
	return TRUE

/// The old forms' fields, to new_player.dm's Topic(), then the poll read again to show the vote
/datum/poll_window/proc/send_vote(list/params)
	var/id = pollid
	var/type = poll["type"]
	var/list/href = list("votepollid" = "[id]", "votetype" = type)
	var/list/ids = list()
	for(var/list/option in poll["options"])
		ids += option["id"]
	switch(type)
		if(POLLTYPE_OPTION)
			href["voteoptionid"] = "[text2num(params["option"])]"
		if(POLLTYPE_TEXT)
			href["replytext"] = "[params["text"]]"
		if(POLLTYPE_RATING, POLLTYPE_MULTI)
			if(!length(ids))
				return
			href[type == POLLTYPE_RATING ? "minid" : "minoptionid"] = "[min(ids)]"
			href[type == POLLTYPE_RATING ? "maxid" : "maxoptionid"] = "[max(ids)]"
			var/list/picked = json_decode(params["picked"] || "{}")
			for(var/key in picked)
				var/optionid = text2num(key)
				if(!(optionid in ids))
					continue
				if(type == POLLTYPE_RATING)
					href["o[optionid]"] = picked[key] == "abstain" ? "abstain" : "[text2num(picked[key])]"
				else if(picked[key])
					href["option_[optionid]"] = "1"
		if(POLLTYPE_IRV)
			href["IRVdata"] = "[params["order"]]"
	usr = player
	player.Topic(null, href)
	if(!QDELETED(src))
		load_poll(id)
