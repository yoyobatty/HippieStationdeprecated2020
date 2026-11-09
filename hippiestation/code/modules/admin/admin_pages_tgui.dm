// hippie -- three admin pages that were HTML popups, designed for tgui (interfaces/AdminPages.js): Check Antagonists (RoundStatus), the
// traitor panel (TraitorPanel) and Check Teams (TeamListing). Their data is laid out by hand; each action is the old page's link built
// here and sent to the same Topic() the link went to (the admin holder's with the admin token, the mind's, an antagonist's), so the
// rights checks, prompts and logs are the old ones. An action naming a mind, mob, antagonist, objective or team is only taken if the page
// shows it right now.

/datum/admins
	/// The page windows open: "kind|target ref" -> /datum/admin_page_window
	var/list/page_windows

/datum/admins/proc/open_admin_page(kind, datum/target)
	LAZYINITLIST(page_windows)
	var/key = "[kind]|[target ? REF(target) : ""]"
	var/datum/admin_page_window/W = page_windows[key]
	if(!W || QDELETED(W))
		var/page_type = kind == "round_status" ? /datum/admin_page_window/round_status : kind == "teams" ? /datum/admin_page_window/teams : /datum/admin_page_window/traitor_panel
		W = new page_type(src, target)
		W.key = key
		page_windows[key] = W
	W.ui_interact(usr)
	SStgui.update_uis(W)

/// The holder's Topic() with an old link's fields and the admin token, outside the click (most of these ask something first)
/datum/admins/proc/page_holder_link(list/href_list)
	href_list["admin_token"] = RawHrefToken()
	INVOKE_ASYNC(src, TYPE_PROC_REF(/datum/admins, window_topic), href_list)

/datum/admin_page_window
	var/datum/admins/holder
	var/datum/weakref/target_ref
	var/key
	var/interface
	var/title
	var/width = 600
	var/height = 700

/datum/admin_page_window/New(datum/admins/H, datum/target)
	holder = H
	target_ref = target ? WEAKREF(target) : null

/datum/admin_page_window/Destroy()
	SStgui.close_uis(src)
	if(holder)
		LAZYREMOVE(holder.page_windows, key)
	holder = null
	return ..()

/datum/admin_page_window/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, interface, page_title(), width, height, master_ui, state)
		ui.open()

/datum/admin_page_window/proc/page_title()
	return title

/datum/admin_page_window/ui_status(mob/user, datum/ui_state/state)
	return (user.client?.holder && user.client.holder == holder && check_rights_for(user.client, R_ADMIN)) ? UI_INTERACTIVE : UI_CLOSE

/datum/admin_page_window/ui_close(mob/user)
	if(!QDELETED(src)) // Destroy() closing the window lands here too
		qdel(src)

/// An antagonist as the pages show one
/proc/admin_page_antag(datum/antagonist/A)
	var/datum/mind/M = A.owner
	var/mob/body = M?.current
	var/list/out = list("ref" = REF(A), "role" = A.name, "mind" = M ? REF(M) : null, "mob" = body ? REF(body) : null, "ckey" = M?.key ? ckey(M.key) : null)
	out["name"] = body ? body.real_name : (M ? M.name : "Unassigned")
	// What the antagonist adds to its name in the old listing (a changeling's chosen name, a head revolutionary's mark)
	var/listed = trim(comm_plain_text(A.antag_listing_name()))
	if(length(listed) > length(out["name"]) && findtext(listed, out["name"]) == 1)
		out["note"] = trim(copytext(listed, length(out["name"]) + 1))
	var/status = trim(comm_plain_text(A.antag_listing_status()))
	out["status"] = length(status) ? status : null
	out["dead"] = !body || body.stat == DEAD
	out["client"] = !!body?.client
	return out

// ---------------------------------------------------------------------------------------------
// Check Antagonists
// ---------------------------------------------------------------------------------------------

/datum/admins/check_antagonists()
	if(!SSticker.HasRoundStarted())
		tgui_alert(usr, "The game hasn't started yet!")
		return
	open_admin_page("round_status")

/datum/admin_page_window/round_status
	interface = "admin_round_status"
	title = "Round Status"
	width = 640

/datum/admin_page_window/round_status/ui_data(mob/user)
	. = list()
	var/datum/game_mode/mode = SSticker.mode
	.["mode"] = mode?.name
	.["replacement"] = mode?.replacementmode?.name
	.["dynamic"] = istype(mode, /datum/game_mode/dynamic)
	.["duration"] = DisplayTimeText(world.time - SSticker.round_start_time)
	.["delay_end"] = !!SSticker.delay_end
	if(EMERGENCY_IDLE_OR_RECALLED)
		.["shuttle"] = "idle"
	else
		var/timeleft = SSshuttle.emergency.timeLeft()
		.["shuttle"] = SSshuttle.emergency.mode == SHUTTLE_CALL ? "called" : "other"
		.["eta"] = "[(timeleft / 60) % 60]:[add_leading(num2text(timeleft % 60), 2, "0")]"
		.["shuttle_mode"] = SSshuttle.emergency.getModeStr()
	if(mode)
		var/continuous = CONFIG_GET(keyed_list/continuous)[mode.config_tag]
		var/midround = CONFIG_GET(keyed_list/midround_antag)[mode.config_tag]
		.["continuous"] = !!continuous
		.["midround"] = !!midround
		.["time_limit"] = CONFIG_GET(number/midround_antag_time_check)
		.["life_limit"] = CONFIG_GET(number/midround_antag_life_check) * 100
		.["end_on_limit"] = !!mode.round_ends_with_antag_death
	// The head count, as check_antagonists() counted it
	var/list/count = list("in_game" = 0, "connected" = GLOB.clients.len, "lobby" = 0, "living_active" = 0, "living_dc" = 0, "antagonists" = 0, \
		"skipped" = 0, "drones" = 0, "dead_active" = 0, "dead_dc" = 0, "brains" = 0, "invalid" = 0)
	for(var/mob/M in GLOB.mob_list)
		if(!M.ckey)
			continue
		if(isnewplayer(M))
			count["lobby"]++
		else if(M.stat != DEAD && M.mind && !isbrain(M))
			if(isdrone(M))
				count["drones"]++
				continue
			if(is_centcom_level(M.z))
				count["skipped"]++
				continue
			if(M.mind.special_role)
				count["antagonists"]++
			if(M.client)
				count["living_active"]++
			else
				count["living_dc"]++
		else if(M.stat == DEAD || isobserver(M))
			if(M.client)
				count["dead_active"]++
			else
				count["dead_dc"]++
		else if(isbrain(M))
			count["brains"]++
		else
			count["invalid"]++
	count["in_game"] = count["connected"] - count["lobby"]
	.["players"] = count
	.["groups"] = antag_groups()

/// build_antag_listing() as data: each team, then each kind of antagonist, the game mode's heroes first
/datum/admin_page_window/round_status/proc/antag_groups()
	var/list/heroes = list()
	var/list/rest = list()
	var/list/all_teams = list()
	var/list/all_antagonists = list()
	for(var/datum/antagonist/A in GLOB.antagonists)
		if(!A.owner)
			continue
		all_teams |= A.get_team()
		all_antagonists += A
	for(var/datum/team/T in all_teams)
		var/list/members = list()
		for(var/datum/antagonist/X in all_antagonists)
			if(X.get_team() == T)
				all_antagonists -= X
		for(var/datum/antagonist/A in T.get_team_antags())
			members += list(admin_page_antag(A))
		var/list/G = list("name" = comm_plain_text(T.antag_listing_name()), "team" = TRUE, "antags" = members)
		if(istype(T, /datum/team/nuclear))
			var/list/disks = list()
			for(var/obj/item/disk/nuclear/N in GLOB.poi_list)
				var/list/where = list()
				var/atom/disk_loc = N.loc
				var/carrier
				while(disk_loc && !isturf(disk_loc))
					if(ismob(disk_loc))
						var/mob/M = disk_loc
						where += "carried by [M.real_name]"
						carrier = REF(M)
					else if(isobj(disk_loc))
						where += "in \a [disk_loc.name]"
					disk_loc = disk_loc.loc
				if(disk_loc)
					where += "in [disk_loc.loc] ([disk_loc.x], [disk_loc.y], [disk_loc.z])"
				disks += list(list("name" = N.name, "where" = where.Join(" "), "ref" = REF(N), "carrier" = carrier))
			G["disks"] = disks
		if(T.is_gamemode_hero())
			heroes += list(G)
		else
			rest += list(G)
	sortTim(all_antagonists, /proc/cmp_antag_category)
	var/list/current
	var/current_category
	for(var/datum/antagonist/A in all_antagonists)
		if(A.roundend_category != current_category)
			current_category = A.roundend_category
			current = list("name" = capitalize(current_category), "antags" = list())
			if(A.is_gamemode_hero())
				heroes += list(current)
			else
				rest += list(current)
		current["antags"] += list(admin_page_antag(A))
	return heroes + rest

/datum/admin_page_window/round_status/ui_act(action, list/params)
	if(..())
		return
	var/static/list/round_links = list(
		"gamemode_panel" = list("gamemode_panel" = "1"),
		"delay" = list("delay_round_end" = "1"),
		"check_teams" = list("check_teams" = "1"),
		"call_shuttle" = list("call_shuttle" = "1"),
		"recall_shuttle" = list("call_shuttle" = "2"),
		"edit_eta" = list("edit_shuttle_time" = "1"),
		"toggle_continuous" = list("toggle_continuous" = "1"),
		"toggle_midround" = list("toggle_midround_antag" = "1"),
		"time_limit" = list("alter_midround_time_limit" = "1"),
		"life_limit" = list("alter_midround_life_limit" = "1"),
		"limit_behaviour" = list("toggle_noncontinuous_behavior" = "1"),
	)
	var/list/link = round_links[action]
	if(link)
		holder.page_holder_link(link.Copy())
		return TRUE
	if(action == "end_round")
		holder.page_holder_link(list("end_round" = REF(usr)))
		return TRUE
	// The buttons on an antagonist or disk: only for those listed now
	var/ref = "[params["ref"]]"
	var/known = FALSE
	for(var/list/G in antag_groups())
		for(var/list/A in G["antags"])
			if(ref in list(A["mind"], A["mob"], A["ckey"]))
				known = TRUE
		for(var/list/D in G["disks"])
			if(ref in list(D["ref"], D["carrier"]))
				known = TRUE
	if(!known)
		return
	switch(action)
		if("pm")
			usr.client.cmd_admin_pm(ref, null)
		if("follow")
			holder.page_holder_link(list("adminplayerobservefollow" = ref))
		if("traitor_panel")
			holder.page_holder_link(list("traitor" = ref))
		if("player_panel")
			holder.page_holder_link(list("adminplayeropts" = ref))
		if("vv")
			var/datum/D = locate(ref)
			if(D)
				usr.client.debug_variables(D)
	return TRUE

// ---------------------------------------------------------------------------------------------
// Check Teams
// ---------------------------------------------------------------------------------------------

/datum/admins/check_teams()
	if(!SSticker.HasRoundStarted())
		tgui_alert(usr, "The game hasn't started yet!")
		return
	open_admin_page("teams")

/datum/admin_page_window/teams
	interface = "admin_team_listing"
	title = "Team Listing"
	width = 560

/datum/admin_page_window/teams/ui_data(mob/user)
	var/list/teams = list()
	for(var/datum/team/T in GLOB.antagonist_teams)
		var/list/objectives = list()
		for(var/datum/objective/O in T.objectives)
			objectives += list(list("ref" = REF(O), "text" = O.explanation_text))
		var/list/members = list()
		for(var/datum/mind/M in T.members)
			members += list(list("ref" = REF(M), "name" = M.name, "mob" = M.current ? REF(M.current) : null, "dead" = !M.current || M.current.stat == DEAD))
		var/list/commands = list()
		for(var/command in T.get_admin_commands())
			commands += command
		teams += list(list("ref" = REF(T), "name" = T.name, "type" = "[T.type]", "objectives" = objectives, "members" = members, "commands" = commands))
	return list("teams" = teams)

/datum/admin_page_window/teams/ui_act(action, list/params)
	if(..())
		return
	if(action == "create")
		holder.page_holder_link(list("team_command" = "create_team"))
		return TRUE
	var/datum/team/T = locate(params["team"]) in GLOB.antagonist_teams
	if(!T)
		return
	switch(action)
		if("rename", "delete", "communicate", "add_objective", "add_member")
			var/static/list/commands = list("rename" = "rename_team", "delete" = "delete_team", "communicate" = "communicate", \
				"add_objective" = "add_objective", "add_member" = "add_member")
			holder.page_holder_link(list("team_command" = commands[action], "team" = REF(T)))
		if("remove_objective")
			var/datum/objective/O = locate(params["ref"]) in T.objectives
			if(O)
				holder.page_holder_link(list("team_command" = "remove_objective", "team" = REF(T), "tobjective" = REF(O)))
		if("remove_member")
			var/datum/mind/M = locate(params["ref"]) in T.members
			if(M)
				holder.page_holder_link(list("team_command" = "remove_member", "team" = REF(T), "tmember" = REF(M)))
		if("command")
			var/command = "[params["command"]]"
			if(command in T.get_admin_commands())
				INVOKE_ASYNC(T, TYPE_PROC_REF(/datum/team, page_team_command), command)
		if("player_panel")
			var/datum/mind/M = locate(params["ref"]) in T.members
			if(M?.current)
				holder.page_holder_link(list("adminplayeropts" = REF(M.current)))
	return TRUE

/// A team's admin command, as its old link did (team_panel.dm: ?src=team;command=X)
/datum/team/proc/page_team_command(command)
	Topic(list2params(list("command" = command)), list("command" = command))

// ---------------------------------------------------------------------------------------------
// The traitor panel
// ---------------------------------------------------------------------------------------------

/datum/mind/traitor_panel()
	if(!SSticker.HasRoundStarted())
		tgui_alert(usr, "Not before round-start!", "Alert")
		return
	if(QDELETED(src))
		tgui_alert(usr, "This mind doesn't have a mob, or is deleted! For some reason!", "Edit Memory")
		return
	usr.client?.holder?.open_admin_page("traitor_panel", src)

/datum/admin_page_window/traitor_panel
	interface = "admin_traitor_panel"
	width = 640

/datum/admin_page_window/traitor_panel/page_title()
	var/datum/mind/M = target_ref?.resolve()
	return "Traitor Panel: [M ? M.name : "?"]"

/datum/admin_page_window/traitor_panel/ui_data(mob/user)
	. = list()
	var/datum/mind/M = target_ref?.resolve()
	if(!M || QDELETED(M))
		.["gone"] = TRUE
		return
	.["name"] = M.name
	.["real_name"] = M.current && M.current.real_name != M.name ? M.current.real_name : null
	.["key"] = M.key
	.["synced"] = !!M.active
	.["role"] = M.assigned_role
	.["special_role"] = M.special_role
	.["no_body"] = !M.current
	.["mindshield"] = M.current && HAS_TRAIT(M.current, TRAIT_MINDSHIELD)
	var/mob/living/silicon/robot/R = M.current
	.["emagged"] = istype(R) && R.emagged
	// What they are
	var/list/current = list()
	for(var/datum/antagonist/A in M.antag_datums)
		var/list/objectives = list()
		for(var/datum/objective/O in A.objectives)
			objectives += list(list("ref" = REF(O), "text" = O.explanation_text, "completed" = !!O.completed))
		var/list/commands = list()
		for(var/command in A.get_admin_commands())
			commands += command
		current += list(list("ref" = REF(A), "name" = A.name, "category" = A.antagpanel_category, "objectives" = objectives, "commands" = commands, \
			"memory" = trim(comm_plain_text(A.antag_memory)), "data" = trim(comm_plain_text(A.antag_panel_data()))))
	.["antags"] = current
	// What they could be made, by category (traitor_panel()'s headers)
	if(!GLOB.antag_prototypes)
		GLOB.antag_prototypes = list()
		for(var/antag_type in subtypesof(/datum/antagonist))
			var/datum/antagonist/A = new antag_type
			var/cat_id = A.antagpanel_category
			if(!GLOB.antag_prototypes[cat_id])
				GLOB.antag_prototypes[cat_id] = list(A)
			else
				GLOB.antag_prototypes[cat_id] += A
	sortTim(GLOB.antag_prototypes, /proc/cmp_text_asc, associative = TRUE)
	var/list/categories = list()
	for(var/category in GLOB.antag_prototypes)
		var/has_one = FALSE
		var/list/options = list()
		var/datum/antagonist/pref_source
		for(var/datum/antagonist/prototype in GLOB.antag_prototypes[category])
			if(M.has_antag_datum(prototype.type))
				has_one = TRUE
				break
			if(!prototype.show_in_antagpanel)
				continue
			if(!pref_source)
				pref_source = prototype
			options += list(list("type" = "[prototype.type]", "name" = prototype.name, "can" = !!prototype.can_be_owned(M)))
		if(has_one || !length(options))
			continue
		categories += list(list("name" = category, "options" = options, "pref" = pref_source?.job_rank ? (pref_source.enabled_in_preferences(M) ? "enabled" : "disabled") : null))
	.["categories"] = categories
	// The uplink and the rest
	if(ishuman(M.current))
		var/datum/component/uplink/U = M.find_syndicate_uplink()
		.["uplink"] = list("has" = !!U, "tc" = U?.telecrystals, "can_set" = check_rights_for(user.client, R_FUN))
	.["memory"] = trim(comm_plain_text(M.memory))
	var/list/common = list()
	if(ishuman(M.current))
		common += list(list("label" = "Undress", "key" = "common", "value" = "undress"))
	else if(istype(R) && R.emagged)
		common += list(list("label" = "Unemag", "key" = "silicon", "value" = "unemag"))
	else if(isAI(M.current))
		var/mob/living/silicon/ai/AI = M.current
		for(var/mob/living/silicon/robot/borg in AI.connected_robots)
			if(borg.emagged)
				common += list(list("label" = "Unemag slaved cyborgs", "key" = "silicon", "value" = "unemagcyborgs"))
				break
	.["common"] = common

/datum/admin_page_window/traitor_panel/ui_act(action, list/params)
	if(..())
		return
	var/datum/mind/M = target_ref?.resolve()
	if(!M || QDELETED(M))
		return
	var/list/href_list
	switch(action)
		if("role_edit")
			href_list = list("role_edit" = "1")
		if("memory_edit")
			href_list = list("memory_edit" = "1")
		if("announce")
			href_list = list("obj_announce" = "1")
		if("add_antag")
			var/path = text2path("[params["type"]]")
			if(!ispath(path, /datum/antagonist))
				return
			for(var/category in GLOB.antag_prototypes)
				for(var/datum/antagonist/prototype in GLOB.antag_prototypes[category])
					if(prototype.type == path && prototype.show_in_antagpanel && prototype.can_be_owned(M))
						href_list = list("add_antag" = "[path]")
		if("remove_antag")
			var/datum/antagonist/A = locate(params["ref"]) in M.antag_datums
			if(A)
				href_list = list("remove_antag" = REF(A))
		if("obj_add")
			var/datum/antagonist/A = locate(params["ref"]) in M.antag_datums
			if(A)
				href_list = list("obj_add" = "1", "target_antag" = REF(A))
		if("obj_edit", "obj_delete", "obj_completed")
			for(var/datum/antagonist/A in M.antag_datums)
				var/datum/objective/O = locate(params["ref"]) in A.objectives
				if(O)
					href_list = list("[action]" = REF(O))
		if("uplink_give")
			href_list = list("common" = "uplink")
		if("uplink_take")
			href_list = list("common" = "takeuplink")
		if("uplink_tc")
			href_list = list("common" = "crystals")
		if("common")
			if(params["key"] == "common" && params["value"] == "undress")
				href_list = list("common" = "undress")
			else if(params["key"] == "silicon" && (params["value"] in list("unemag", "unemagcyborgs")))
				href_list = list("silicon" = params["value"])
		// The antagonist's own: its memory and commands go to its Topic()
		if("antag_memory", "antag_command")
			var/datum/antagonist/A = locate(params["ref"]) in M.antag_datums
			if(!A)
				return
			var/list/antag_href = action == "antag_memory" ? list("memory_edit" = "1") : list("command" = "[params["command"]]")
			if(action == "antag_command" && !(antag_href["command"] in A.get_admin_commands()))
				return
			INVOKE_ASYNC(A, TYPE_PROC_REF(/datum/antagonist, page_antag_topic), antag_href)
			return TRUE
	if(!href_list)
		return
	INVOKE_ASYNC(M, TYPE_PROC_REF(/datum/mind, page_mind_topic), href_list)
	return TRUE

/// The mind's Topic() with an old traitor panel link (it checks the admin's rights itself)
/datum/mind/proc/page_mind_topic(list/href_list)
	Topic(list2params(href_list), href_list)

/datum/antagonist/proc/page_antag_topic(list/href_list)
	Topic(list2params(href_list), href_list)
