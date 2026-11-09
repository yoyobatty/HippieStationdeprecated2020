// hippie -- admin records designed for tgui (interfaces/AdminRecords.js): the Permissions Panel (the admins grouped by rank, a rank's
// flags edited in place, the admin log and the rank checks), the edit history of a ban, note or mentor memo, a client's related accounts,
// and a player's own notes. Each change goes through the old link (editrights= and the rest) to the holder's Topic() with the admin token,
// so the rights checks, the permanent/temporary question, the database writes and the logs are the old ones.

// ---------------------------------------------------------------------------------------------
// The Permissions Panel
// ---------------------------------------------------------------------------------------------

/datum/admins
	/// The flags the Permissions window sent for one admin: change_admin_flags() takes them in place of its three prompts
	var/list/pending_rank_flags

/datum/admins/edit_admin_permissions(action, target, operation, page)
	if(!check_rights(R_PERMISSIONS))
		return
	var/list/arguments = list()
	if(action == 1)
		arguments = list("tab" = "log", "target" = target, "operation" = operation, "page" = page)
	else if(action == 2)
		arguments = list("tab" = "manage")
	open_admin_tool("permissions", /datum/admin_tool_window/permissions, arguments)

/datum/admin_tool_window/permissions
	interface = "admin_permissions"
	title = "Permissions Panel"
	width = 980
	height = 660
	rights = R_PERMISSIONS
	var/tab = "admins"
	var/log_target = ""
	var/log_operation = ""
	var/log_page = 0
	var/log_pages = 0
	var/list/log_rows
	var/list/bad_ranks
	var/list/unused_ranks
	/// Why the log or the checks are empty: no database, or a query that failed
	var/db_error

/datum/admin_tool_window/permissions/setup(list/arguments)
	if(arguments?["tab"])
		tab = arguments["tab"]
	if(tab == "log" && arguments?["tab"] == "log")
		log_target = "[arguments["target"]]"
		log_operation = "[arguments["operation"]]"
		log_page = max(0, round(text2num("[arguments["page"]]")))
	load_tab()

/// The log or the rank checks, read from the database (here, not in ui_data(), since a query waits)
/datum/admin_tool_window/permissions/proc/load_tab()
	db_error = null
	if(tab != "log" && tab != "manage")
		return
	if(!SSdbcore.Connect())
		db_error = "No database, so there's no log or rank checks."
		return
	if(tab == "log")
		load_log()
	else
		load_manage()

/datum/admin_tool_window/permissions/proc/load_log()
	log_rows = list()
	var/search = " WHERE (:target IS NULL OR target = :target) AND (:operation IS NULL OR operation = :operation)"
	var/list/search_args = list("target" = log_target || null, "operation" = log_operation || null)
	var/per_page = 20
	var/datum/DBQuery/query_count = SSdbcore.NewQuery("SELECT COUNT(id) FROM [format_table_name("admin_log")][search]", search_args)
	if(!query_count.warn_execute())
		qdel(query_count)
		db_error = "The log couldn't be read."
		return
	var/count = 0
	if(query_count.NextRow())
		count = text2num(query_count.item[1])
	qdel(query_count)
	log_pages = max(1, CEILING(count / per_page, 1))
	log_page = clamp(log_page, 0, log_pages - 1)
	search_args["skip"] = per_page * log_page
	search_args["count"] = per_page
	var/datum/DBQuery/query_log = SSdbcore.NewQuery("SELECT datetime, round_id, IFNULL((SELECT byond_key FROM [format_table_name("player")] WHERE ckey = adminckey), adminckey), operation, IF(ckey IS NULL, target, byond_key), log FROM [format_table_name("admin_log")] LEFT JOIN [format_table_name("player")] ON target = ckey[search] ORDER BY datetime DESC LIMIT :skip, :count", search_args)
	if(!query_log.warn_execute())
		qdel(query_log)
		db_error = "The log couldn't be read."
		return
	while(query_log.NextRow())
		log_rows += list(list("when" = query_log.item[1], "round" = query_log.item[2], "admin" = query_log.item[3], "operation" = query_log.item[4], \
			"target" = query_log.item[5], "log" = query_log.item[6]))
	qdel(query_log)

/datum/admin_tool_window/permissions/proc/load_manage()
	bad_ranks = list()
	unused_ranks = list()
	var/datum/DBQuery/query_bad = SSdbcore.NewQuery("SELECT IFNULL((SELECT byond_key FROM [format_table_name("player")] WHERE [format_table_name("player")].ckey = [format_table_name("admin")].ckey), ckey), [format_table_name("admin")].rank FROM [format_table_name("admin")] LEFT JOIN [format_table_name("admin_ranks")] ON [format_table_name("admin_ranks")].rank = [format_table_name("admin")].rank WHERE [format_table_name("admin_ranks")].rank IS NULL")
	if(!query_bad.warn_execute())
		qdel(query_bad)
		db_error = "The rank checks couldn't be read."
		return
	while(query_bad.NextRow())
		bad_ranks += list(list("key" = query_bad.item[1], "rank" = query_bad.item[2]))
	qdel(query_bad)
	var/datum/DBQuery/query_unused = SSdbcore.NewQuery("SELECT [format_table_name("admin_ranks")].rank, flags, exclude_flags, can_edit_flags FROM [format_table_name("admin_ranks")] LEFT JOIN [format_table_name("admin")] ON [format_table_name("admin")].rank = [format_table_name("admin_ranks")].rank WHERE [format_table_name("admin")].rank IS NULL")
	if(!query_unused.warn_execute())
		qdel(query_unused)
		db_error = "The rank checks couldn't be read."
		return
	while(query_unused.NextRow())
		unused_ranks += list(list("rank" = query_unused.item[1], "include" = text2num(query_unused.item[2]), "exclude" = text2num(query_unused.item[3]), \
			"can_edit" = text2num(query_unused.item[4])))
	qdel(query_unused)

/// Every admin and deadminned admin, by ckey
/datum/admin_tool_window/permissions/proc/admin_holders()
	. = list()
	for(var/adm_ckey in GLOB.admin_datums + GLOB.deadmins)
		var/datum/admins/D = GLOB.admin_datums[adm_ckey] || GLOB.deadmins[adm_ckey]
		if(D)
			.[adm_ckey] = D

/datum/admin_tool_window/permissions/ui_data(mob/user)
	. = list()
	.["tab"] = tab
	var/list/flags = list()
	var/list/names = GLOB.bitfields["admin_flags"]
	for(var/name in names)
		flags += list(list("name" = name, "bit" = names[name]))
	.["flags"] = flags
	.["my_can_edit"] = holder.rank.can_edit_rights
	.["dbranks"] = check_rights_for(user.client, R_DBRANKS)
	var/list/admins = list()
	var/list/ranks = list()
	var/list/holders = admin_holders()
	// What edit_rights_topic() refuses: a txt admin's rank and a txt rank's flags, when the config protects them
	var/protect_admins = !CONFIG_GET(flag/admin_legacy_system) && CONFIG_GET(flag/protect_legacy_admins)
	var/protect_ranks = !CONFIG_GET(flag/admin_legacy_system) && CONFIG_GET(flag/protect_legacy_ranks)
	for(var/adm_ckey in holders)
		var/datum/admins/D = holders[adm_ckey]
		var/editable = holder.check_if_greater_rights_than_holder(D)
		admins += list(list("ckey" = adm_ckey, "key" = D.owner ? D.owner.key : adm_ckey, "rank" = D.rank.name, "deadmined" = !!D.deadmined, \
			"online" = !!D.owner, "protected" = protect_admins && (adm_ckey in GLOB.protected_admins), "editable" = editable, "me" = (D == holder)))
		var/list/R = ranks[D.rank.name]
		if(!R)
			R = list("name" = D.rank.name, "include" = D.rank.include_rights, "exclude" = D.rank.exclude_rights, \
				"can_edit" = D.rank.can_edit_rights, "protected" = protect_ranks && (D.rank in GLOB.protected_ranks), "editable" = FALSE)
			ranks[D.rank.name] = R
		if(editable)
			R["editable"] = TRUE
	.["admins"] = admins
	var/list/rank_rows = list()
	for(var/name in ranks)
		rank_rows += list(ranks[name])
	.["ranks"] = rank_rows
	.["db_error"] = db_error
	if(tab == "log")
		.["log"] = log_rows || list()
		.["log_page"] = log_page
		.["log_pages"] = log_pages
		.["log_target"] = log_target
		.["log_operation"] = log_operation
		.["operations"] = list("add admin", "remove admin", "change admin rank", "add rank", "remove rank", "change rank flags")
	else if(tab == "manage")
		.["bad_ranks"] = bad_ranks || list()
		.["unused_ranks"] = unused_ranks || list()

/datum/admin_tool_window/permissions/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("tab")
			if(params["tab"] in list("admins", "log", "manage"))
				tab = params["tab"]
				load_tab()
			return TRUE
		if("refresh")
			load_tab()
			return TRUE
		if("log_filter")
			log_target = trim("[params["target"]]")
			log_operation = (params["operation"] in list("add admin", "remove admin", "change admin rank", "add rank", "remove rank", "change rank flags")) ? params["operation"] : ""
			log_page = 0
			load_tab()
			return TRUE
		if("log_page")
			log_page = max(0, round(text2num("[params["page"]]")))
			load_tab()
			return TRUE
		if("add")
			var/new_key = trim("[params["key"]]")
			if(!ckey(new_key))
				return
			holder.page_holder_link(list("editrights" = "add", "key" = new_key))
			return TRUE
		if("manage_change", "manage_remove")
			for(var/list/row in bad_ranks)
				if(row["key"] == params["key"])
					holder.page_holder_link(list("editrightsbrowsermanage" = "1", "[action == "manage_change" ? "editrightschange" : "editrightsremove"]" = row["key"]))
					return TRUE
			return
		if("manage_remove_rank")
			for(var/list/row in unused_ranks)
				if(row["rank"] == params["rank"])
					holder.page_holder_link(list("editrightsbrowsermanage" = "1", "editrightsremoverank" = row["rank"]))
					return TRUE
			return
	var/list/holders = admin_holders()
	// A rank's flags: sent as the old link for one admin holding it (one this editor outranks), applied to the whole rank
	if(action == "set_flags")
		for(var/adm_ckey in holders)
			var/datum/admins/D = holders[adm_ckey]
			if(D.rank.name != params["rank"] || !holder.check_if_greater_rights_than_holder(D))
				continue
			holder.pending_rank_flags = list("rank" = D.rank.name, "ckey" = adm_ckey, "include" = round(text2num("[params["include"]]")), \
				"exclude" = round(text2num("[params["exclude"]]")), "can_edit" = round(text2num("[params["can_edit"]]")))
			holder.page_holder_link(list("editrights" = "permissions", "key" = D.owner ? D.owner.key : adm_ckey))
			return TRUE
		return
	// One admin's buttons
	var/datum/admins/D = holders[params["ckey"]]
	if(!D)
		return
	var/admin_key = D.owner ? D.owner.key : params["ckey"]
	if(action in list("rank", "remove", "activate", "deactivate", "sync"))
		holder.page_holder_link(list("editrights" = action, "key" = admin_key))
	return TRUE

/// permissionedit.dm's, with the window's flags for a rank in place of the three bitfield prompts (flags outside what the editor may
/// edit stay as they were, as in the prompts). The window edits a rank, so "this round" changes it for every admin holding it, not a
/// copy for one admin as the prompts did.
/datum/admins/change_admin_flags(admin_ckey, admin_key, use_db, datum/admins/D, legacy_only)
	var/list/preset = pending_rank_flags
	pending_rank_flags = null
	if(preset && (preset["ckey"] != admin_ckey || preset["rank"] != D.rank.name))
		preset = null
	var/allowed = usr.client.holder.rank.can_edit_rights
	var/new_flags
	var/new_exclude_flags
	var/new_can_edit_flags
	if(preset)
		new_flags = (D.rank.include_rights & ~allowed) | (preset["include"] & allowed)
		new_exclude_flags = (D.rank.exclude_rights & ~allowed) | (preset["exclude"] & allowed)
		new_can_edit_flags = (D.rank.can_edit_rights & ~allowed) | (preset["can_edit"] & allowed)
	else
		new_flags = input_bitfield(usr, "Include permission flags<br>[use_db ? "This will affect ALL admins with this rank." : "This will affect only the current admin [admin_key]"]", "admin_flags", D.rank.include_rights, 350, 590, allowed_edit_list = allowed)
		if(isnull(new_flags))
			return
		new_exclude_flags = input_bitfield(usr, "Exclude permission flags<br>Flags enabled here will be removed from a rank.<br>Note these take precedence over included flags.<br>[use_db ? "This will affect ALL admins with this rank." : "This will affect only the current admin [admin_key]"]", "admin_flags", D.rank.exclude_rights, 350, 670, "red", allowed)
		if(isnull(new_exclude_flags))
			return
		new_can_edit_flags = input_bitfield(usr, "Editable permission flags<br>These are the flags this rank is allowed to edit if they have access to the permissions panel.<br>They will be unable to modify admins to a rank that has a flag not included here.<br>[use_db ? "This will affect ALL admins with this rank." : "This will affect only the current admin [admin_key]"]", "admin_flags", D.rank.can_edit_rights, 350, 710, allowed_edit_list = allowed)
		if(isnull(new_can_edit_flags))
			return
	var/m1 = "[key_name_admin(usr)] edited the permissions of [use_db ? " rank [D.rank.name] permanently" : "[admin_key] temporarily"]"
	var/m2 = "[key_name(usr)] edited the permissions of [use_db ? " rank [D.rank.name] permanently" : "[admin_key] temporarily"]"
	if(preset && !use_db && !legacy_only)
		// The window edits a rank: this round, every admin holding it, without the database
		var/rank_name = D.rank.name
		var/list/rank_datums = list()
		for(var/datum/admin_rank/R in GLOB.admin_ranks)
			if(R.name == rank_name)
				rank_datums |= R
		var/list/holding = list()
		for(var/i in GLOB.admin_datums + GLOB.deadmins)
			var/datum/admins/A = GLOB.admin_datums[i] || GLOB.deadmins[i]
			if(A?.rank.name == rank_name)
				rank_datums |= A.rank
				holding += A
		for(var/datum/admin_rank/R in rank_datums)
			R.rights = new_flags & ~new_exclude_flags
			R.include_rights = new_flags
			R.exclude_rights = new_exclude_flags
			R.can_edit_rights = new_can_edit_flags
		for(var/datum/admins/A in holding)
			var/client/C = GLOB.directory[A.target]
			A.disassociate()
			A.associate(C)
		message_admins("[key_name_admin(usr)] edited the permissions of rank [rank_name] for this round: [rights2text(new_flags, " ")][rights2text(new_exclude_flags, " ", "-")]")
		log_admin("[key_name(usr)] edited the permissions of rank [rank_name] for this round: [rights2text(new_flags, " ")][rights2text(new_exclude_flags, " ", "-")][rights2text(new_can_edit_flags, " ", "*")]")
		return
	if(use_db || legacy_only)
		var/rank_name = D.rank.name
		var/old_flags
		var/old_exclude_flags
		var/old_can_edit_flags
		var/datum/DBQuery/query_get_rank_flags = SSdbcore.NewQuery("SELECT flags, exclude_flags, can_edit_flags FROM [format_table_name("admin_ranks")] WHERE rank = :rank", list("rank" = rank_name))
		if(!query_get_rank_flags.warn_execute())
			qdel(query_get_rank_flags)
			return
		if(query_get_rank_flags.NextRow())
			old_flags = text2num(query_get_rank_flags.item[1])
			old_exclude_flags = text2num(query_get_rank_flags.item[2])
			old_can_edit_flags = text2num(query_get_rank_flags.item[3])
		qdel(query_get_rank_flags)
		var/datum/DBQuery/query_change_rank_flags = SSdbcore.NewQuery("UPDATE [format_table_name("admin_ranks")] SET flags = :flags, exclude_flags = :exclude_flags, can_edit_flags = :can_edit_flags WHERE rank = :rank",
			list("flags" = new_flags, "exclude_flags" = new_exclude_flags, "can_edit_flags" = new_can_edit_flags, "rank" = rank_name))
		if(!query_change_rank_flags.warn_execute())
			qdel(query_change_rank_flags)
			return
		qdel(query_change_rank_flags)
		if(!SSdbcore.admin_log("change rank flags", rank_name, "Permissions of [rank_name] changed from[rights2text(old_flags," ")][rights2text(old_exclude_flags," ", "-")][rights2text(old_can_edit_flags," ", "*")] to[rights2text(new_flags," ")][rights2text(new_exclude_flags," ", "-")][rights2text(new_can_edit_flags," ", "*")]"))
			return
		for(var/datum/admin_rank/R in GLOB.admin_ranks)
			if(R.name != D.rank.name)
				continue
			R.rights = new_flags &= ~new_exclude_flags
			R.exclude_rights = new_exclude_flags
			R.include_rights = new_flags
			R.can_edit_rights = new_can_edit_flags
		for(var/i in GLOB.admin_datums+GLOB.deadmins)
			var/datum/admins/A = GLOB.admin_datums[i]
			if(!A)
				A = GLOB.deadmins[i]
				if (!A)
					continue
			if(A.rank.name != D.rank.name)
				continue
			var/client/C = GLOB.directory[A.target]
			A.disassociate()
			A.associate(C)
	else
		D.disassociate()
		if(!findtext(D.rank.name, "([admin_ckey])")) //not a modified subrank, need to duplicate the admin_rank datum to prevent modifying others too
			D.rank = new("[D.rank.name]([admin_ckey])", new_flags, new_exclude_flags, new_can_edit_flags) //duplicate our previous admin_rank but with a new name
			//we don't add this clone to the admin_ranks list, as it is unique to that ckey
		else
			D.rank.rights = new_flags &= ~new_exclude_flags
			D.rank.include_rights = new_flags
			D.rank.exclude_rights = new_exclude_flags
			D.rank.can_edit_rights = new_can_edit_flags
		var/client/C = GLOB.directory[admin_ckey] //find the client with the specified ckey (if they are logged in)
		D.associate(C) //link up with the client and add verbs
	message_admins(m1)
	log_admin(m2)

// ---------------------------------------------------------------------------------------------
// An edit history: a ban's, a note's or a mentor memo's edits
// ---------------------------------------------------------------------------------------------

/// Opens the edit history window on `edits`, the <hr>-separated log the database keeps
/datum/admins/proc/open_edit_log(what, about, edits, needed_rights = R_ADMIN)
	open_admin_tool("edit_log", /datum/admin_tool_window/edit_log, list("what" = what, "about" = about, "edits" = edits, "rights" = needed_rights))

/datum/admin_tool_window/edit_log
	interface = "admin_edit_log"
	title = "Edit history"
	width = 560
	height = 520
	var/what
	var/about
	var/list/entries

/datum/admin_tool_window/edit_log/setup(list/arguments)
	what = arguments["what"]
	about = arguments["about"]
	rights = arguments["rights"]
	entries = edit_log_entries(arguments["edits"])

/// Each edit as a heading (who and when) and, when it says what changed, the old and new text. "Edited by X on T from<br>OLD<br>to<br>NEW"
/proc/edit_log_entries(edits)
	. = list()
	for(var/entry in splittext("[edits]", "<hr>"))
		if(!length(trim(entry)))
			continue
		var/list/lines = splittext(entry, "<br>")
		var/heading = trim(lines[1])
		var/old_text
		var/new_text
		var/body
		var/to_at = lines.Find("to")
		if(to_at > 2 && copytext(heading, -5) == " from")
			heading = copytext(heading, 1, -5)
			old_text = comm_plain_text(jointext(lines.Copy(2, to_at), "\n"))
			new_text = comm_plain_text(jointext(lines.Copy(to_at + 1), "\n"))
		else if(length(lines) > 1)
			body = comm_plain_text(jointext(lines.Copy(2), "\n"))
		. += list(list("heading" = comm_plain_text(heading), "old" = old_text, "new" = new_text, "body" = body))
	// Newest first
	var/list/reversed = list()
	for(var/i in length(.) to 1 step -1)
		reversed += list(.[i])
	return reversed

/datum/admin_tool_window/edit_log/ui_data(mob/user)
	return list("what" = what, "about" = about, "entries" = entries)

/datum/admins/ban_log(ban_id)
	if(!check_rights(R_BAN))
		return
	var/edits
	var/datum/ban_record/B = SSbans.get(ban_id)
	if(B && (B.is_local() || !CONFIG_GET(flag/sql_enabled) || !SSdbcore.Connect()))
		edits = B.edits
	else
		var/db_id = text2num(ban_id)
		if(!db_id)
			return
		if(!SSdbcore.Connect())
			to_chat(usr, "<span class='danger'>Failed to establish database connection.</span>", confidential=TRUE)
			return
		var/datum/DBQuery/query_get_ban_edits = SSdbcore.NewQuery("SELECT edits FROM [format_table_name("ban")] WHERE id = :id", list("id" = db_id))
		if(!query_get_ban_edits.warn_execute())
			qdel(query_get_ban_edits)
			return
		if(query_get_ban_edits.NextRow())
			edits = query_get_ban_edits.item[1]
		qdel(query_get_ban_edits)
	if(edits)
		open_edit_log("Ban", "Ban #[ban_id][B ? " on [B.key || B.ckey]" : ""]", edits, R_BAN)

/datum/admins/checkMentorEditList(ckey)
	var/datum/DBQuery/query_memoedits = SSdbcore.NewQuery("SELECT edits FROM [format_table_name("mentor_memo")] WHERE ckey = :ckey", list("ckey" = "[ckey]"))
	if(!query_memoedits.warn_execute())
		qdel(query_memoedits)
		return
	if(query_memoedits.NextRow())
		open_edit_log("Mentor memo", "[ckey]'s mentor memo", query_memoedits.item[1], NONE)
	qdel(query_memoedits)

// ---------------------------------------------------------------------------------------------
// Related accounts
// ---------------------------------------------------------------------------------------------

/datum/admin_tool_window/related
	interface = "admin_related_accounts"
	title = "Related accounts"
	width = 460
	height = 460
	var/key
	var/by = "cid"
	var/list/by_cid
	var/list/by_ip

/datum/admin_tool_window/related/setup(list/arguments)
	var/client/C = arguments["client"]
	if(C)
		key = C.key
		by_cid = related_list(C.related_accounts_cid, C.ckey)
		by_ip = related_list(C.related_accounts_ip, C.ckey)
	if(arguments["by"] in list("cid", "ip"))
		by = arguments["by"]

/datum/admin_tool_window/related/proc/related_list(text, own_ckey)
	. = list()
	for(var/other in splittext("[text]", ", "))
		var/other_ckey = ckey(other)
		if(other_ckey && other_ckey != own_ckey && !(other_ckey in .))
			. += other_ckey

/datum/admin_tool_window/related/proc/rows_for(list/ckeys)
	. = list()
	for(var/other_ckey in ckeys)
		var/client/C = GLOB.directory[other_ckey]
		. += list(list("ckey" = other_ckey, "key" = C ? C.key : note_key_of(other_ckey), "online" = !!C, "admin" = !!(GLOB.admin_datums[other_ckey] || GLOB.deadmins[other_ckey])))

/datum/admin_tool_window/related/ui_data(mob/user)
	return list("key" = key, "by" = by, "cid" = rows_for(by_cid), "ip" = rows_for(by_ip))

/datum/admin_tool_window/related/ui_act(action, list/params)
	if(..())
		return
	if(action == "by")
		by = params["by"] == "ip" ? "ip" : "cid"
		return TRUE
	var/other_ckey = params["ckey"]
	if(!(other_ckey in by_cid) && !(other_ckey in by_ip))
		return
	switch(action)
		if("notes")
			holder.page_holder_link(list("showmessageckey" = other_ckey))
		if("bans")
			usr.client.open_ban_window("bans", list("search" = other_ckey))
		if("pp")
			var/client/C = GLOB.directory[other_ckey]
			if(C?.mob)
				holder.page_holder_link(list("adminplayeropts" = REF(C.mob)))
	return TRUE

// ---------------------------------------------------------------------------------------------
// The links: related accounts, a note's edits and a player's notes without the admin buttons
// ---------------------------------------------------------------------------------------------

/datum/admins/Topic(href, href_list)
	if(href_list["showrelatedacc"] || href_list["messageedits"] || href_list["showmessageckeylinkless"])
		if(usr.client != owner || !check_rights(0, FALSE))
			return ..() // the old checks say why
		if(!CheckAdminHref(href, href_list))
			return
		if(!check_rights(R_ADMIN))
			return
		if(href_list["showrelatedacc"])
			var/client/C = locate(href_list["client"]) in GLOB.clients
			if(C)
				open_admin_tool("related", /datum/admin_tool_window/related, list("client" = C, "by" = href_list["showrelatedacc"]))
		else if(href_list["messageedits"])
			var/list/row = SSnotes.get_row(href_list["messageedits"])
			var/edit_log = SSnotes.edits_of(href_list["messageedits"])
			if(edit_log && !QDELETED(usr))
				open_edit_log(row ? capitalize(row["kind"]) : "Note", row ? note_about(row) : "Note #[href_list["messageedits"]]", edit_log)
		else
			open_player_notes(usr, href_list["showmessageckeylinkless"])
		return
	return ..()

// ---------------------------------------------------------------------------------------------
// A player's own notes (View Admin Remarks), secret ones left out
// ---------------------------------------------------------------------------------------------

/client/self_notes()
	if(!CONFIG_GET(flag/see_own_notes))
		to_chat(usr, "<span class='notice'>Sorry, that function is not enabled on this server.</span>")
		return
	open_player_notes(usr, ckey)

/proc/open_player_notes(mob/viewer, target_ckey)
	target_ckey = ckey(target_ckey)
	if(!viewer?.client || !target_ckey)
		return
	var/datum/player_notes_window/W = new(target_ckey)
	W.ui_interact(viewer)

/datum/player_notes_window
	var/target_ckey
	var/list/rows

/datum/player_notes_window/New(target_ckey)
	src.target_ckey = target_ckey
	rows = list()
	for(var/list/row in SSnotes.rows_for(target_ckey))
		if(row["secret"])
			continue
		var/section
		switch(row["kind"])
			if("message", "message sent")
				section = "messages"
			if("watchlist entry")
				section = "watchlist"
			if("note")
				section = "notes"
		if(section)
			rows += list(list("section" = section, "when" = row["timestamp"], "server" = row["server"], "admin" = row["admin_key"], \
				"expires" = row["expires"], "severity" = row["severity"], "text" = comm_plain_text(row["text"])))

/datum/player_notes_window/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "player_notes", "Admin remarks", 560, 560, master_ui, state)
		ui.open()

/datum/player_notes_window/ui_static_data(mob/user)
	return list("key" = note_key_of(target_ckey), "own" = (user.ckey == target_ckey), "rows" = rows)

/datum/player_notes_window/ui_close(mob/user)
	qdel(src)
