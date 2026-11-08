// Player profile: everything known about one player in one window (tgui-next PlayerProfile.js), for admins. Who they are now and
// what (antagonist included: admins only), how long they've been coming here, the keys on their computer and address and whether
// those are banned, their bans and notes, their tickets this round and before, the rounds they played, and what they've done
// this round by the round log. Opened from the player panel's PROFILE, the Tickets window, an alert, or the Player Profile verb.
// The user's tooling plan, stage 2 (2026-11-07).

/client/var/datum/player_profile/player_profile

/client/proc/cmd_player_profile()
	set name = "Player Profile"
	set category = "Admin"
	set desc = "Everything known about a player: bans, notes, alts, tickets and rounds."
	if(!check_rights(R_ADMIN))
		return
	var/list/keys = list()
	for(var/client/C in GLOB.clients)
		keys[C.key] = C.ckey
	for(var/player_ckey in SSbans.left_this_round)
		if(!GLOB.directory[player_ckey])
			keys["[note_key_of(player_ckey)] (left)"] = player_ckey
	var/picked = tgui_input_list(src, "Whose profile? Online and left this round; or type a key with Other.", "Player Profile", (sortList(keys) + "Other..."))
	if(!picked)
		return
	var/player_ckey = keys[picked]
	if(picked == "Other...")
		player_ckey = ckey(tgui_input_text(src, "Key", "Player Profile"))
	if(player_ckey)
		open_player_profile(player_ckey)

/client/proc/open_player_profile(player_ckey, via_hub)
	if(!holder)
		return
	player_ckey = ckey(player_ckey)
	if(!player_ckey)
		return
	if(!player_profile)
		player_profile = new
		player_profile.owner = src
	player_profile.show(player_ckey)
	if(hub_wants(via_hub)) // the hub's panel at the right, on whatever tab it's on
		open_admin_hub(null, TRUE)
		return
	player_profile.ui_interact(mob)

/datum/player_profile
	var/client/owner
	var/shown_ckey
	/// Profiles opened from this one, for Back
	var/list/back = list()
	/// What's shown, built when opened or refreshed (bans and notes may ask the database)
	var/list/built

/datum/player_profile/Destroy()
	owner = null
	return ..()

/datum/player_profile/proc/show(player_ckey, remember = TRUE)
	if(remember && shown_ckey && shown_ckey != player_ckey)
		back += shown_ckey
		if(back.len > 20)
			back.Cut(1, 2)
	shown_ckey = player_ckey
	build()

/datum/player_profile/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.admin_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "player_profile", "Player Profile", 980, 720, master_ui, state)
		ui.open()

/// The player's mob now, connected or not
/proc/mob_of_ckey(player_ckey)
	var/client/C = GLOB.directory[player_ckey]
	if(C?.mob)
		return C.mob
	for(var/mob/M in GLOB.mob_list)
		if(M.ckey == player_ckey)
			return M

/datum/player_profile/proc/build()
	var/player_ckey = shown_ckey
	var/datum/ban_window/lookup = new
	lookup.lookup(note_key_of(player_ckey) || player_ckey)
	var/list/R = lookup.record || list()
	var/list/B = list(
		"ckey" = player_ckey,
		"key" = R["key"] || note_key_of(player_ckey) || player_ckey,
		"status" = R["status"],
		"left_ago" = R["left_ago"],
		"first_seen" = R["first_seen"],
		"last_seen" = R["last_seen"],
		"connections" = R["connections"],
		"can_see_addresses" = !!check_rights_for(owner, R_BAN),
		"ips" = R["ips"],
		"cids" = R["cids"],
	)
	// alts, and whether each is banned now
	var/list/alts = list()
	for(var/field in list("cids", "ips"))
		for(var/other in SSbans.seen_sharing(player_ckey, field))
			if(alts[other])
				continue
			var/banned = FALSE
			for(var/datum/ban_record/ban in SSbans.matching(other))
				if(lowertext(ban.role) == "server")
					banned = TRUE
			alts[other] = list("ckey" = other, "key" = note_key_of(other), "how" = field == "cids" ? "same computer" : "same address", "banned" = banned, "online" = !!GLOB.directory[other])
	var/list/alt_rows = list()
	for(var/other in alts)
		alt_rows += list(alts[other])
	B["alts"] = alt_rows
	// bans, as the Bans window groups them
	var/list/bans = list()
	for(var/list/G in R["groups_raw"])
		var/list/shown = lookup.group_data(G)
		var/list/roles = list()
		for(var/list/role in shown["roles"])
			roles += role["role"]
		bans += list(list("status" = shown["status"], "server" = shown["server"], "roles" = roles, "reason" = shown["reason"], "admin" = shown["admin"], "when" = shown["bantime"], "length" = shown["length"], "left" = shown["left"]))
	B["bans"] = bans
	qdel(lookup)
	// notes, all of them
	var/list/notes = list()
	for(var/list/N in SSnotes.rows_for(player_ckey))
		notes += list(list("kind" = N["kind"], "text" = N["text"], "admin" = N["admin_key"], "severity" = N["severity"], "when" = N["timestamp"], "age_days" = N["age_days"], "secret" = N["secret"]))
	B["notes"] = notes
	// tickets: this round's, then the kept ones from before
	var/list/history = player_history_read(player_ckey)
	var/list/tickets = list()
	var/round = player_history_round()
	for(var/datum/admin_help/AH in GLOB.ahelp_tickets.TicketsByCKey(player_ckey))
		tickets += list(list("round_id" = "this round", "id" = AH.id, "title" = AH.name, "outcome" = AH.history_outcome(), "handled_by" = AH.claimed_key, "closed_by" = AH.history_closed_by(), "now" = TRUE))
	var/list/past_tickets = history["tickets"]
	for(var/i in past_tickets.len to 1 step -1)
		var/list/T = past_tickets[i]
		if(T["round_id"] == round)
			continue
		tickets += list(list("round_id" = T["round_id"], "date" = T["date"], "id" = T["id"], "title" = T["title"], "outcome" = T["outcome"], "handled_by" = T["handled_by"], "closed_by" = T["closed_by"], "first" = T["first"]))
	B["tickets"] = tickets
	var/list/rounds = list()
	var/list/past_rounds = history["rounds"]
	for(var/i in past_rounds.len to 1 step -1)
		rounds += list(past_rounds[i])
	B["rounds"] = rounds
	// this round, by the round log
	var/list/counts = list("attacked" = 0, "attacked_by" = 0, "deaths" = 0, "said" = 0)
	var/list/hit_people = list()
	var/list/hit_by = list()
	var/list/log = GLOB.round_log
	for(var/i in 1 to log.len)
		var/list/entry = log[i]
		if(!(i % 5000))
			CHECK_TICK
		var/mine = entry[RL_CKEY] == player_ckey
		var/on_me = entry[RL_TCKEY] == player_ckey
		if(!mine && !on_me)
			continue
		switch(entry[RL_CAT])
			if("Attack")
				if(mine && !on_me)
					counts["attacked"]++
					if(entry[RL_TNAME])
						hit_people[entry[RL_TNAME]]++
				else if(on_me && !mine)
					counts["attacked_by"]++
					if(entry[RL_NAME])
						hit_by[entry[RL_NAME]]++
			if("Death")
				if(mine)
					counts["deaths"]++
			if("Say", "Whisper", "Radio", "OOC")
				if(mine)
					counts["said"]++
	B["round_counts"] = counts
	B["hit_people"] = profile_top(hit_people)
	B["hit_by"] = profile_top(hit_by)
	built = B

/// The five biggest, as "Name (3)"
/proc/profile_top(list/tally)
	. = list()
	var/list/names = list()
	for(var/name in tally)
		names += name
	while(names.len && length(.) < 5)
		var/best
		for(var/name in names)
			if(!best || tally[name] > tally[best])
				best = name
		names -= best
		. += "[best] ([tally[best]])"

/datum/player_profile/ui_data(mob/user)
	if(!built)
		return list()
	var/list/data = built.Copy()
	// who they are now changes as you watch
	var/mob/M = mob_of_ckey(shown_ckey)
	var/list/now = list("online" = !!GLOB.directory[shown_ckey], "state" = admin_mob_state(M), "has_mob" = !!M)
	if(M && !isnewplayer(M))
		now["name"] = M.real_name
		now["job"] = M.mind?.assigned_role
		now["antag"] = admin_antag_text(M)
		var/area/A = get_area(M)
		now["area"] = A?.name
		now["bot"] = M.is_bot_crew()
	data["now"] = now
	var/datum/admin_help/open_ticket = GLOB.ahelp_tickets.CKey2ActiveTicket(shown_ckey)
	data["open_ticket"] = open_ticket?.id
	data["can_back"] = back.len > 0
	return data

/datum/player_profile/ui_act(action, list/params)
	if(..())
		return
	if(!check_rights(R_ADMIN))
		return
	if(action == "player_menu") // a name's menu (player_menu.dm)
		return player_menu_act(usr, params)
	var/mob/M = mob_of_ckey(shown_ckey)
	switch(action)
		if("refresh")
			build()
			return TRUE
		if("back")
			if(back.len)
				var/previous = back[back.len]
				back.Cut(back.len)
				show(previous, FALSE)
			return TRUE
		if("profile")
			var/other = ckey(params["ckey"])
			if(other)
				show(other)
			return TRUE
		if("pp")
			if(M)
				usr.client.holder.show_player_panel(M)
		if("vv")
			if(M)
				usr.client.debug_variables(M)
		if("flw")
			if(M && (isobserver(usr) || usr.client.admin_ghost()))
				var/mob/dead/observer/ghost = usr.client.mob
				ghost.ManualFollow(M)
		if("pm")
			var/client/C = GLOB.directory[shown_ckey]
			if(C)
				usr.client.cmd_admin_pm(C, null)
		if("logs")
			usr.client.open_log_search(shown_ckey)
		if("notes")
			usr.client.open_ban_window("notes", list("view" = "player", "ckey" = shown_ckey))
		if("add_note")
			usr.client.open_ban_window("notes", list("view" = "player", "ckey" = shown_ckey, "compose" = TRUE, "kind" = "note"))
		if("ban")
			usr.client.open_ban_window("new", list("key" = note_key_of(shown_ckey) || shown_ckey))
		if("bans")
			usr.client.open_ban_window("bans", list("search" = note_key_of(shown_ckey) || shown_ckey))
		if("ticket")
			var/id = text2num(params["id"])
			if(id)
				usr.client.open_tickets(id)
