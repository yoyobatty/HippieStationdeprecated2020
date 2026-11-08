#define MAX_ADMINBANS_PER_ADMIN 1
#define MAX_ADMINBANS_PER_HEADMIN 3

//checks the client's ban cache, or SSbans' copy of the bans for someone who isn't connected, if ckey is banned from one or more roles
//doesn't return any details, use only for if statements. It never queries or sleeps, so it's safe to call from anywhere.
/proc/is_banned_from(player_ckey, roles)
	player_ckey = ckey(player_ckey) //some callers have a key
	if(!player_ckey)
		return FALSE
	var/list/check = list() //lowercased: the ghost spawners asked for "lavaland" and the panel bans "Lavaland"
	if(islist(roles))
		for(var/R in roles)
			check += lowertext(R)
	else
		check += lowertext(roles)
	var/is_admin = GLOB.admin_datums[player_ckey] || GLOB.deadmins[player_ckey]
	var/client/C = GLOB.directory[player_ckey]
	if(!C)
		return SSbans.role_banned(player_ckey, check, is_admin)
	if(isnull(C.ban_cache)) //login hasn't built it yet: from the copy for now, which needs no query
		var/list/cache = list()
		SSbans.add_to_cache(cache, player_ckey, is_admin, FALSE, C.computer_id)
		C.ban_cache = cache
	for(var/R in check)
		if(R in C.ban_cache)
			var/expire_rt = C.ban_cache[R]
			if(!expire_rt || expire_rt > world.realtime)
				return TRUE //they're banned from at least one role, no need to keep checking
	return FALSE

//checks DB ban table if a ckey, ip and/or cid is banned from a specific role
//returns an associative nested list of each matching row's ban id, bantime, ban round id, expiration time, ban duration, applies to admins, reason, key, ip, cid and banning admin's key in that order, or null if the query failed
/proc/is_banned_from_with_details(player_ckey, player_ip, player_cid, role)
	if(!player_ckey && !player_ip && !player_cid)
		return
	var/datum/DBQuery/query_check_ban = SSdbcore.NewQuery("SELECT id, bantime, round_id, expiration_time, TIMESTAMPDIFF(MINUTE, bantime, expiration_time), applies_to_admins, reason, IFNULL((SELECT byond_key FROM [format_table_name("player")] AS p WHERE p.ckey = b.ckey), ckey), INET_NTOA(ip), computerid, IFNULL((SELECT byond_key FROM [format_table_name("player")] AS p WHERE p.ckey = b.a_ckey), a_ckey) FROM [format_table_name("ban")] AS b WHERE role = :role AND (ckey = :ckey OR ip = INET_ATON(:ip) OR computerid = :cid) AND unbanned_datetime IS NULL AND (expiration_time IS NULL OR expiration_time > NOW()) ORDER BY bantime DESC",
		list("role" = role, "ckey" = player_ckey || null, "ip" = player_ip || null, "cid" = player_cid || null)) //a NULL never matches, so a missing one checks nothing
	if(!query_check_ban.Execute())
		qdel(query_check_ban)
		return
	. = list()
	while(query_check_ban.NextRow())
		. += list(list("id" = query_check_ban.item[1], "bantime" = query_check_ban.item[2], "round_id" = query_check_ban.item[3], "expiration_time" = query_check_ban.item[4], "duration" = query_check_ban.item[5], "applies_to_admins" = query_check_ban.item[6], "reason" = query_check_ban.item[7], "key" = query_check_ban.item[8], "ip" = query_check_ban.item[9], "computerid" = query_check_ban.item[10], "admin_key" = query_check_ban.item[11]))
	qdel(query_check_ban)

//A client's role bans, on their key or the computer they're on, as role = the world.realtime it ends (0 for permanent): the
//database's when it answers, and the bans kept on this server that it hasn't got. Built at login and whenever one of their bans
//changes; until then is_banned_from() uses the copy.
/proc/build_ban_cache(client/C)
	if(!istype(C))
		return
	var/player_ckey = C.ckey
	var/player_cid = C.computer_id
	if(player_cid)
		SSbans.known_cids[player_ckey] = player_cid
	var/is_admin = GLOB.admin_datums[player_ckey] || GLOB.deadmins[player_ckey]
	var/list/cache = list()
	var/db_checked = CONFIG_GET(flag/sql_enabled) && SSdbcore.Connect() && SSbans.db_cache_rows(cache, player_ckey, player_cid, is_admin)
	SSbans.add_to_cache(cache, player_ckey, is_admin, db_checked, player_cid)
	if(!QDELETED(C))
		C.ban_cache = cache

//TRUE (and tells them) if this admin already has as many admin bans on as they're allowed; role bans made together count once
/datum/admins/proc/over_admin_ban_limit()
	var/admin_ckey = usr.client.ckey
	var/list/bantimes = list()
	var/db_checked = FALSE
	if(CONFIG_GET(flag/sql_enabled) && SSdbcore.Connect())
		var/datum/DBQuery/query_check_adminban_count = SSdbcore.NewQuery("SELECT DISTINCT bantime FROM [format_table_name("ban")] WHERE a_ckey = :ckey AND applies_to_admins = 1 AND unbanned_datetime IS NULL AND (expiration_time IS NULL OR expiration_time > NOW())", list("ckey" = admin_ckey))
		if(!query_check_adminban_count.warn_execute())
			qdel(query_check_adminban_count)
			return TRUE
		while(query_check_adminban_count.NextRow())
			bantimes[query_check_adminban_count.item[1]] = TRUE
		qdel(query_check_adminban_count)
		db_checked = TRUE
	for(var/bantime in SSbans.admin_ban_times(admin_ckey, local_only = db_checked))
		bantimes[bantime] = TRUE
	var/max_adminbans = MAX_ADMINBANS_PER_ADMIN
	if((rank.can_edit_rights & R_EVERYTHING) == R_EVERYTHING) //edit rights are a more effective way to check hierarchical rank since many non-headmins have R_PERMISSIONS now
		max_adminbans = MAX_ADMINBANS_PER_HEADMIN
	if(bantimes.len >= max_adminbans)
		to_chat(usr, "<span class='danger'>You've already logged [max_adminbans] admin ban(s) or more. Do not abuse this function!</span>", confidential=TRUE)
		return TRUE
	return FALSE

//The player's key, and their IP and CID from their last connection if asked for: from the database, their client if they're
//connected, or what this server remembers of them (SSbans.seen). Returns list(key, ip, cid), or null if the admin backed out.
//quiet: the Bans window already showed the key was never seen, so don't ask.
/datum/admins/proc/ban_lookup_player(player_key, player_ip, player_cid, use_last_connection, ip_check, cid_check, action, quiet = FALSE)
	var/player_ckey = ckey(player_key)
	var/seen = FALSE
	if(CONFIG_GET(flag/sql_enabled) && SSdbcore.Connect())
		var/datum/DBQuery/query_ban_get_player = SSdbcore.NewQuery("SELECT byond_key, INET_NTOA(ip), computerid FROM [format_table_name("player")] WHERE ckey = :ckey", list("ckey" = player_ckey))
		if(!query_ban_get_player.warn_execute())
			qdel(query_ban_get_player)
			return
		if(query_ban_get_player.NextRow())
			seen = TRUE
			player_key = query_ban_get_player.item[1]
			if(use_last_connection)
				if(ip_check)
					player_ip = query_ban_get_player.item[2]
				if(cid_check)
					player_cid = query_ban_get_player.item[3]
		qdel(query_ban_get_player)
	if(!seen)
		var/client/online = GLOB.directory[player_ckey]
		if(online)
			seen = TRUE
			player_key = online.key
			if(use_last_connection)
				if(ip_check)
					player_ip = online.address
				if(cid_check)
					player_cid = online.computer_id
	if(!seen && SSbans.seen[player_ckey]) //remembered from an earlier connection: no database, or none that has them
		seen = TRUE
		var/list/entry = SSbans.seen[player_ckey]
		player_key = entry["key"] || player_key
		if(use_last_connection)
			if(ip_check)
				player_ip = SSbans.last_seen_address(player_ckey, "ips")
			if(cid_check)
				player_cid = SSbans.last_seen_address(player_ckey, "cids")
	if(!seen && !quiet)
		var/question
		if(use_last_connection)
			question = "[player_key]/([player_ckey]) has never been seen here, so there's no IP or CID from a last connection. Do you want to [action] the ban without them?"
		else
			question = "[player_key]/([player_ckey]) has never been seen here. Are you sure you want to [action] a ban for them?"
		if(tgui_alert(usr, question, "Unknown key", list("Yes", "No", "Cancel")) != "Yes")
			return
	return list(player_key, player_ip, player_cid)

//The old Banning Panel's callers (the player panel's Ban link, the verb): the Bans window, on a new ban for that player, or with
//an edit_id, on that ban in the list
/datum/admins/proc/ban_panel(player_key, player_ip, player_cid, role, duration = 1440, applies_to_admins, reason, edit_id, page, admin_key)
	if(!check_rights(R_BAN))
		return
	if(edit_id)
		usr.client.open_ban_window("bans", list("search" = player_key || player_ip || player_cid))
		return
	usr.client.open_ban_window("new", list("key" = player_key, "ip" = player_ip, "cid" = player_cid))

/datum/admins/proc/create_ban(player_key, ip_check, player_ip, cid_check, player_cid, use_last_connection, applies_to_admins, duration, interval, severity, reason, list/roles_to_ban, quiet = FALSE)
	if(!check_rights(R_BAN))
		return
	var/player_ckey = ckey(player_key)
	if(player_ckey)
		var/list/found = ban_lookup_player(player_key, player_ip, player_cid, use_last_connection, ip_check, cid_check, "create", quiet)
		if(!found)
			return
		player_key = found[1]
		player_ip = found[2]
		player_cid = found[3]
	if(applies_to_admins && over_admin_ban_limit())
		return
	duration = text2num(duration)
	if(!(interval in BAN_INTERVALS)) //it goes into the query unquoted, so escaping can't make it safe
		interval = "MINUTE"
	var/time_message = "[duration] [lowertext(interval)]" //no DisplayTimeText because our duration is of variable interval type
	if(duration > 1) //pluralize the interval if necessary
		time_message += "s"
	var/banned_from = roles_to_ban[1] == "Server" ? "the server" : roles_to_ban.Join(", ") //"from  Roles: Cook" read oddly in notes and to the player
	var/note_reason = "Banned from [banned_from] [isnull(duration) ? "permanently" : "for [time_message]"] - [reason]"
	var/list/clients_online = GLOB.clients.Copy()
	var/list/admins_online = list()
	for(var/client/C in clients_online)
		if(C.holder) //deadmins aren't included since they wouldn't show up on adminwho
			admins_online += C
	var/kn = key_name(usr)
	var/kna = key_name_admin(usr)
	//raw values: sanitizeSQL() gives nothing with no database, so they're escaped when they're written to it
	var/list/intervals = BAN_INTERVALS
	var/bantime = SQLtime()
	var/list/new_bans = list()
	for(var/role in roles_to_ban)
		var/datum/ban_record/B = new
		B.role = role
		B.ckey = player_ckey
		B.key = player_key
		B.ip = player_ip
		B.cid = player_cid
		B.bantime = bantime
		B.bantime_rt = world.realtime
		if(duration)
			B.amount = duration
			B.unit = interval
			B.expire_rt = world.realtime + duration * intervals[interval] * 10
		B.applies_to_admins = applies_to_admins
		B.reason = reason
		B.round_id = GLOB.round_id
		B.a_ckey = usr.client.ckey
		B.a_key = usr.client.key
		B.a_ip = usr.client.address
		B.a_cid = usr.client.computer_id
		B.who = clients_online.Join(", ")
		B.adminwho = admins_online.Join(", ")
		new_bans += B
	var/stored = SSbans.add_bans(new_bans)
	if(!stored)
		return
	if(stored == "local" && CONFIG_GET(flag/sql_enabled))
		to_chat(usr, "<span class='danger'>The database couldn't be reached. The ban is saved on this server and enforced here, and it goes to the database when the database is back.</span>", confidential=TRUE)
	var/target = ban_target_string(player_key, player_ip, player_cid)
	var/msg = "has created a [isnull(duration) ? "permanent" : "temporary [time_message]"] [applies_to_admins ? "admin " : ""][roles_to_ban[1] == "Server" ? "server ban" : "role ban from [roles_to_ban.len] roles"] for [target]."
	log_admin_private("[kn] [msg][roles_to_ban[1] == "Server" ? "" : " Roles: [roles_to_ban.Join(", ")]"] Reason: [reason]")
	message_admins("[kna] [msg][roles_to_ban[1] == "Server" ? "" : " Roles: [roles_to_ban.Join("\n")]"]\nReason: [reason]")
	if(applies_to_admins)
		send2irc("BAN ALERT","[kn] [msg]")
	if(player_ckey)
		create_message("note", player_ckey, usr.client.ckey, note_reason, null, null, 0, 0, null, 0, severity) //kept on this server when there's no database
		hippie_on_jobban(get_mob_by_key(player_ckey), roles_to_ban) // hippie -- apply stuff like catify on jobban
	var/client/C = GLOB.directory[player_ckey]
	var/datum/admin_help/AH = admin_ticket_log(player_ckey, msg)
	var/appeal_url = "No ban appeal url set!"
	appeal_url = CONFIG_GET(string/banappeals)
	var/is_admin = FALSE
	if(C)
		build_ban_cache(C)
		to_chat(C, "<span class='boldannounce'>You have been [applies_to_admins ? "admin " : ""]banned by [usr.client.key] from [banned_from].\nReason: [reason]</span><br><span class='danger'>This ban is [isnull(duration) ? "permanent." : "temporary, it will be removed in [time_message]."] The round ID is [GLOB.round_id].</span><br><span class='danger'>To appeal this ban go to [appeal_url]</span>", confidential=TRUE)
		if(GLOB.admin_datums[C.ckey] || GLOB.deadmins[C.ckey])
			is_admin = TRUE
		if(roles_to_ban[1] == "Server" && (!is_admin || (is_admin && applies_to_admins)))
			qdel(C)
	if(roles_to_ban[1] == "Server" && AH)
		AH.Resolve()
	for(var/client/i in GLOB.clients - C)
		if((player_ip && i.address == player_ip) || (player_cid && i.computer_id == player_cid)) //a ban with no IP would otherwise match the host, whose address is null
			build_ban_cache(i)
			to_chat(i, "<span class='boldannounce'>You have been [applies_to_admins ? "admin " : ""]banned by [usr.client.key] from [banned_from].\nReason: [reason]</span><br><span class='danger'>This ban is [isnull(duration) ? "permanent." : "temporary, it will be removed in [time_message]."] The round ID is [GLOB.round_id].</span><br><span class='danger'>To appeal this ban go to [appeal_url]</span>", confidential=TRUE)
			if(GLOB.admin_datums[i.ckey] || GLOB.deadmins[i.ckey])
				is_admin = TRUE
			if(roles_to_ban[1] == "Server" && (!is_admin || (is_admin && applies_to_admins)))
				qdel(i)
	return TRUE

//The old Unbanning Panel's callers: the Bans window's list, searching for whichever was given
/datum/admins/proc/unban_panel(player_key, admin_key, player_ip, player_cid, page = 0)
	if(!check_rights(R_BAN))
		return
	usr.client.open_ban_window("bans", list("search" = player_key || admin_key || player_ip || player_cid))

//Lifts one ban. confirmed: the Bans window asked already.
/datum/admins/proc/unban(ban_id, player_key, player_ip, player_cid, role, confirmed = FALSE)
	if(!check_rights(R_BAN))
		return
	var/target = ban_target_string(player_key, player_ip, player_cid)
	if(!confirmed && tgui_alert(usr, "Please confirm unban of [target] from [role].", "Unban confirmation", list("Yes", "No")) != "Yes")
		return
	var/kn = key_name(usr)
	var/kna = key_name_admin(usr)
	var/result = SSbans.lift(ban_id, usr.client.ckey, usr.client.key, usr.client.address, usr.client.computer_id)
	if(!result)
		return
	if(result == "queued")
		to_chat(usr, "<span class='danger'>The database couldn't be reached. The ban is lifted on this server, and in the database when the database is back.</span>", confidential=TRUE)
	log_admin_private("[kn] has unbanned [target] from [role].")
	message_admins("[kna] has unbanned [target] from [role].")
	ban_tell_lifted(player_key, player_ip, player_cid, role)
	return TRUE

//Rebuilds the ban caches of everyone a lifted ban held, and tells them
/datum/admins/proc/ban_tell_lifted(player_key, player_ip, player_cid, what)
	var/client/C = GLOB.directory[ckey(player_key)]
	if(C)
		build_ban_cache(C)
		to_chat(C, "<span class='boldannounce'>[usr.client.key] has removed a ban from [what] for your key.</span>", confidential=TRUE)
	for(var/client/i in GLOB.clients - C)
		if((player_ip && i.address == player_ip) || (player_cid && i.computer_id == player_cid))
			build_ban_cache(i)
			to_chat(i, "<span class='boldannounce'>[usr.client.key] has removed a ban from [what] for your IP or CID.</span>", confidential=TRUE)

/datum/admins/proc/edit_ban(ban_id, player_key, ip_check, player_ip, cid_check, player_cid, use_last_connection, applies_to_admins, duration, interval, reason, mirror_edit, old_key, old_ip, old_cid, old_applies, page, admin_key, list/changes, quiet = FALSE)
	if(!check_rights(R_BAN))
		return
	if(!SSbans.get(ban_id) && !text2num(ban_id))
		return
	var/player_ckey = ckey(player_key)
	if(player_ckey)
		var/list/found = ban_lookup_player(player_key, player_ip, player_cid, use_last_connection, ip_check, cid_check, "edit", quiet)
		if(!found)
			return
		player_key = found[1]
		player_ip = found[2]
		player_cid = found[3]
	if(applies_to_admins && (applies_to_admins != old_applies) && over_admin_ban_limit())
		return
	duration = text2num(duration)
	if(!(interval in BAN_INTERVALS))
		interval = "MINUTE"
	var/kn = key_name(usr)
	var/kna = key_name_admin(usr)
	var/list/changes_text= list()
	var/list/changes_keys = list()
	for(var/i in changes)
		changes_text += "[i]: [changes[i]]"
		changes_keys += i
	var/list/op = list("id" = "[ban_id]", "mirror" = text2num(mirror_edit), "old_ckey" = ckey(old_key), "old_ip" = old_ip, "old_cid" = old_cid, "amount" = duration, "unit" = duration ? interval : null, "applies_to_admins" = applies_to_admins, "reason" = reason, "ckey" = player_ckey, "key" = player_key, "ip" = player_ip, "cid" = player_cid, "edit_text" = "[usr.client.key] edited the following [jointext(changes_text, ", ")]<hr>")
	//a mirrored edit matches on the ban time, which the copy has, unless the ban was made elsewhere after it was last refreshed
	if(op["mirror"] && !SSbans.get(ban_id) && CONFIG_GET(flag/sql_enabled) && SSdbcore.Connect())
		var/datum/DBQuery/query_edit_ban_get_bantime = SSdbcore.NewQuery("SELECT bantime FROM [format_table_name("ban")] WHERE id = :id", list("id" = text2num(ban_id)))
		if(!query_edit_ban_get_bantime.warn_execute())
			qdel(query_edit_ban_get_bantime)
			return
		if(query_edit_ban_get_bantime.NextRow())
			op["bantime"] = query_edit_ban_get_bantime.item[1]
		qdel(query_edit_ban_get_bantime)
	var/result = SSbans.edit(op)
	if(!result)
		return
	if(result == "queued")
		to_chat(usr, "<span class='danger'>The database couldn't be reached. The ban is changed on this server, and in the database when the database is back.</span>", confidential=TRUE)
	var/changes_keys_text = jointext(changes_keys, ", ")
	log_admin_private("[kn] has edited the [changes_keys_text] of a ban for [old_key ? "[old_key]" : "[old_ip]-[old_cid]"].") //if a ban doesn't have a key it must have an ip and/or a cid to have reached this point normally
	message_admins("[kna] has edited the [changes_keys_text] of a ban for [old_key ? "[old_key]" : "[old_ip]-[old_cid]"].")
	if(changes["Applies to admins"])
		send2irc("BAN ALERT","[kn] has edited a ban for [old_key ? "[old_key]" : "[old_ip]-[old_cid]"] to [applies_to_admins ? "" : "not "]affect admins")
	var/client/C = GLOB.directory[ckey(old_key)]
	if(C)
		build_ban_cache(C)
		to_chat(C, "<span class='boldannounce'>[usr.client.key] has edited the [changes_keys_text] of a ban for your key.</span>", confidential=TRUE)
	for(var/client/i in GLOB.clients - C)
		if((old_ip && i.address == old_ip) || (old_cid && i.computer_id == old_cid))
			build_ban_cache(i)
			to_chat(i, "<span class='boldannounce'>[usr.client.key] has edited the [changes_keys_text] of a ban for your IP or CID.</span>", confidential=TRUE)
	return TRUE

/datum/admins/proc/ban_log(ban_id)
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
		var/datum/browser/edit_log = new(usr, "baneditlog", "Ban edit log")
		edit_log.set_content(edits)
		edit_log.open()

/datum/admins/proc/ban_target_string(player_key, player_ip, player_cid)
	. = list()
	if(player_key)
		. += player_key
	else
		if(player_ip)
			. += player_ip
		else
			. += "NULL"
		if(player_cid)
			. += player_cid
		else
			. += "NULL"
	. = jointext(., "/")
