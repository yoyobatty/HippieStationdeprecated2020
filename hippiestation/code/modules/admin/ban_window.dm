// The Bans window (tgui-next BanWindow.js): making bans, the list of them, sticky bans and notes in one window, instead of the
// old Banning Panel, Unbanning Panel, Sticky Ban Panel and notes page. The user's rulings, 2026-11-07:
//	New ban: length presets with when it ends; the player's record beside the form (their bans, notes, and the keys on the same
//	computer); a picker of who's online and who left this round, with the IP and computer ID they came from (remembered with no
//	database too, SSbans.seen); the role grid marks roles they're already banned from with the time left, and lifts them there.
//	Bans: opens on the active ones; role bans made together are one row; edit which roles, lift all or one; time left on each.
//	Notes: notes, messages, watchlist entries and memos, kept on this server when there's no database (SSnotes).
// Edits, unbans and sticky ban changes are confirmed in the window, not with alert()s.

#define BAN_WINDOW_GROUPS_SHOWN 150
#define BAN_WINDOW_ROWS_ASKED 600

/client/var/datum/ban_window/ban_window

/client/proc/open_ban_window(tab, list/options)
	if(!holder)
		return
	if(!ban_window)
		ban_window = new
	ban_window.open(mob, tab, options)

/client/proc/cmd_admin_notes()
	set name = "Notes"
	set category = "Admin"
	set desc = "Notes, messages, watchlist entries and memos."
	if(!check_rights(R_ADMIN))
		return
	open_ban_window("notes", list("view" = "index"))

//The roles the panel bans from, in its groups. Heads are in Command and their department both, as on the old panel.
/proc/ban_role_groups()
	var/static/list/groups
	if(groups)
		return groups
	groups = list(
		list("name" = "Command", "roles" = GLOB.command_positions.Copy()),
		list("name" = "Security", "roles" = GLOB.security_positions.Copy()),
		list("name" = "Engineering", "roles" = GLOB.engineering_positions.Copy()),
		list("name" = "Medical", "roles" = GLOB.medical_positions.Copy()),
		list("name" = "Science", "roles" = GLOB.science_positions.Copy()),
		list("name" = "Supply", "roles" = GLOB.supply_positions.Copy()),
		list("name" = "Civilian", "roles" = GLOB.civilian_positions.Copy()),
		list("name" = "Silicon", "roles" = GLOB.nonhuman_positions.Copy()),
		list("name" = "Abstract", "roles" = list("Appearance", "Emote", "OOC")),
		list("name" = "Ghost and Other Roles", "roles" = list(ROLE_BRAINWASHED, ROLE_DEATHSQUAD, ROLE_DRONE, ROLE_LAVALAND, ROLE_MIND_TRANSFER, ROLE_PAI, ROLE_POSIBRAIN, ROLE_SENTIENCE, ROLE_HOLOPARASITE, ROLE_DEFECTIVE_CLONE, ROLE_SANTA, ROLE_MEESEEKS)),
		//ROLE_REV_HEAD isn't here: rev bans are ROLE_REV's. Hippie's own antagonists and the cat, cluwne and crab bans are.
		list("name" = "Antagonists", "roles" = list(ROLE_ABDUCTOR, ROLE_ALIEN, ROLE_BLOB, ROLE_BROTHER, ROLE_CHANGELING, ROLE_CULTIST, ROLE_DEVIL, ROLE_INTERNAL_AFFAIRS, ROLE_MALF, ROLE_MONKEY, ROLE_NINJA, ROLE_OPERATIVE, ROLE_OVERTHROW, ROLE_REV, ROLE_REVENANT, ROLE_REV_HEAD, ROLE_SERVANT_OF_RATVAR, ROLE_SYNDICATE, ROLE_TRAITOR, ROLE_WIZARD, ROLE_OBSESSED, ROLE_HIVE, ROLE_VAMPIRE, ROLE_SHADOWLING, ROLE_GANG, ROLE_INFILTRATOR, ROLE_KOTD, CATBAN, CLUWNEBAN, CRABBAN)))
	return groups

/proc/ban_role_valid(role)
	for(var/list/group in ban_role_groups())
		if(role in group["roles"])
			return TRUE
	return FALSE

//"3d 4h", "5h 12m", "12m", "<1m"
/proc/ban_span_text(seconds)
	seconds = max(0, round(seconds))
	var/days = round(seconds / 86400)
	var/hours = round((seconds - days * 86400) / 3600)
	var/minutes = round((seconds - days * 86400 - hours * 3600) / 60)
	if(days >= 365)
		var/years = round(days / 365)
		days -= years * 365
		return "[years]y[days ? " [days]d" : ""]"
	if(days)
		return "[days]d[hours ? " [hours]h" : ""]"
	if(hours)
		return "[hours]h[minutes ? " [minutes]m" : ""]"
	if(minutes)
		return "[minutes]m"
	return "<1m"

/datum/ban_window
	var/tab = "new"
	var/notice
	var/notice_bad = FALSE
	//New ban: what the form is set to when the serial changes (full: everything, else only who), and the player's record
	var/list/prefill
	var/list/record
	//Bans
	var/search = ""
	var/show_active = TRUE
	var/show_expired = FALSE
	var/show_lifted = FALSE
	var/sort = "ending"
	var/list/groups = list()
	var/searched = FALSE
	var/log_id
	var/log_text
	//Sticky
	var/list/sticky = list()
	//Notes: index (players with notes), player, memos or watchlist
	var/notes_view = "index"
	var/notes_ckey
	var/notes_search = ""
	var/list/notes_players = list()
	var/list/notes_rows = list()
	var/notes_online_only = FALSE
	var/list/compose
	var/note_log_id
	var/note_log_text

/datum/ban_window/New()
	prefill = default_form(1)

/datum/ban_window/proc/default_form(serial)
	return list("serial" = serial, "full" = TRUE, "key" = "", "ip" = "", "cid" = "", "use_ip" = FALSE, "use_cid" = TRUE, "kind" = "server", "roles" = list(), "perm" = FALSE, "length" = 1, "unit" = "DAY", "reason" = "", "applies" = FALSE, "severity" = null)

/datum/ban_window/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.admin_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "ban_window", "Bans", 1060, 720, master_ui, state)
		ui.open()

/datum/ban_window/proc/open(mob/user, new_tab, list/options)
	if(new_tab)
		tab = new_tab
	notice = null
	switch(tab)
		if("new")
			if(options && (options["key"] || options["ip"] || options["cid"]))
				set_player(options["key"], options["ip"], options["cid"])
			if(options && options["reason"]) // a ticket's Ban: the ticket and its quoted lines (tickets.dm)
				var/list/form = prefill.Copy()
				form["serial"] = prefill["serial"] + 1
				form["full"] = TRUE
				form["reason"] = copytext_char(options["reason"], 1, BAN_REASON_MAX)
				prefill = form
		if("bans")
			if(options && !isnull(options["search"]))
				search = options["search"] || ""
				show_active = TRUE
				show_expired = TRUE
				show_lifted = TRUE
				find()
			else if(!searched)
				find()
		if("sticky")
			build_sticky()
		if("notes")
			if(options)
				notes_open(options["view"], options["ckey"], options["kind"], options["compose"])
				if(compose && options["text"]) // a ticket's Note: the ticket and its quoted lines (tickets.dm)
					compose["text"] = copytext_char(options["text"], 1, NOTE_TEXT_MAX)
			else
				notes_refresh()
	ui_interact(user)

/datum/ban_window/proc/say(text, bad = FALSE)
	notice = text
	notice_bad = bad

////////////
// New ban
////////////

//The form to the player, with the IP and computer ID they last came from unless given
/datum/ban_window/proc/set_player(player_key, ip, cid)
	lookup(player_key)
	var/list/form = prefill.Copy()
	form["serial"] = prefill["serial"] + 1
	form["full"] = FALSE
	form["key"] = record ? record["key"] : (player_key || "")
	var/list/ips = record ? record["ips"] : null
	var/list/cids = record ? record["cids"] : null
	form["ip"] = ip || (length(ips) ? ips[1] : "")
	form["cid"] = cid || (length(cids) ? cids[1] : "")
	prefill = form

//Everything known about a key, for the record beside the form
/datum/ban_window/proc/lookup(player_key)
	var/player_ckey = ckey(player_key)
	record = null
	if(!player_ckey)
		return
	var/list/R = list("ckey" = player_ckey)
	var/key = player_key
	var/client/C = GLOB.directory[player_ckey]
	var/list/entry = SSbans.seen[player_ckey]
	var/list/ips = list()
	var/list/cids = list()
	var/list/db_ips = list()
	var/list/db_cids = list()
	var/db_first
	var/db_last
	if(CONFIG_GET(flag/sql_enabled) && SSdbcore.Connect())
		var/datum/DBQuery/query_ban_window_player = SSdbcore.NewQuery("SELECT byond_key, INET_NTOA(ip), computerid, firstseen, lastseen FROM [format_table_name("player")] WHERE ckey = '[sanitizeSQL(player_ckey)]'")
		if(query_ban_window_player.warn_execute() && query_ban_window_player.NextRow())
			key = query_ban_window_player.item[1]
			if(query_ban_window_player.item[2])
				db_ips += query_ban_window_player.item[2]
			if(query_ban_window_player.item[3])
				db_cids += query_ban_window_player.item[3]
			db_first = query_ban_window_player.item[4]
			db_last = query_ban_window_player.item[5]
		qdel(query_ban_window_player)
	if(C)
		key = C.key
		if(C.address)
			ips += C.address
		if(C.computer_id)
			cids += C.computer_id
	if(entry)
		if(!C && entry["key"])
			key = entry["key"]
		var/list/seen_ips = entry["ips"]
		for(var/i in length(seen_ips) to 1 step -1)
			ips |= seen_ips[i]
		var/list/seen_cids = entry["cids"]
		for(var/i in length(seen_cids) to 1 step -1)
			cids |= seen_cids[i]
	ips |= db_ips
	cids |= db_cids
	R["key"] = key
	R["ips"] = ips
	R["cids"] = cids
	if(C)
		R["status"] = "online"
		R["name"] = (!C.mob || isnewplayer(C.mob)) ? "in the lobby" : C.mob.real_name
		R["job"] = C.mob?.mind?.assigned_role
	else if(SSbans.left_this_round[player_ckey] && entry)
		R["status"] = "left"
		R["name"] = entry["name"]
		R["job"] = entry["job"]
		R["left_ago"] = ban_span_text((world.realtime - text2num(entry["left"])) / 10)
	else if(entry || db_last)
		R["status"] = "seen"
	else
		R["status"] = "unknown"
	R["first_seen"] = entry ? SQLtime(text2num(entry["first"])) : db_first
	R["last_seen"] = entry ? SQLtime(text2num(entry["last"])) : db_last
	R["connections"] = entry ? entry["count"] : null
	var/list/same_computer = list()
	for(var/other in SSbans.seen_sharing(player_ckey, "cids"))
		same_computer += note_key_of(other)
	var/list/same_ip = list()
	for(var/other in SSbans.seen_sharing(player_ckey, "ips") - SSbans.seen_sharing(player_ckey, "cids"))
		same_ip += note_key_of(other)
	R["same_computer"] = same_computer
	R["same_ip"] = same_ip
	//their role bans, on their key or the computer they're on: the grid shows these
	var/list/role_bans = list()
	for(var/datum/ban_record/B in SSbans.role_ban_records(player_ckey, length(cids) ? cids[1] : null))
		if(!B.is_active() || lowertext(B.role) == "server")
			continue
		var/list/existing = role_bans[lowertext(B.role)]
		if(existing && (!existing["expire_rt"] || (B.expire_rt && B.expire_rt <= existing["expire_rt"])))
			continue
		role_bans[lowertext(B.role)] = list("id" = B.id, "role" = B.role, "key" = B.key || B.ckey, "ip" = B.ip, "cid" = B.cid, "expire_rt" = B.expire_rt, "computer" = B.ckey != player_ckey)
	R["role_bans_raw"] = role_bans
	R["groups_raw"] = sort_groups(group_rows(find_rows(null, player_ckey, list("active", "expired", "lifted"), 100)), "newest")
	R["notes_raw"] = SSnotes.rows_for(player_ckey)
	record = R

/datum/ban_window/proc/record_data()
	if(!record)
		return null
	var/list/R = record.Copy()
	R -= "role_bans_raw"
	R -= "groups_raw"
	R -= "notes_raw"
	var/list/role_bans = list()
	var/list/raw = record["role_bans_raw"]
	for(var/role in raw)
		var/list/B = raw[role]
		if(B["expire_rt"] && B["expire_rt"] <= world.realtime)
			continue
		role_bans[role] = list("id" = B["id"], "left" = B["expire_rt"] ? ban_span_text((B["expire_rt"] - world.realtime) / 10) : "Perm", "computer" = B["computer"])
	R["role_bans"] = role_bans
	var/list/shown = list()
	for(var/list/G in record["groups_raw"])
		shown += list(group_data(G))
	R["groups"] = shown
	var/list/notes = record["notes_raw"]
	R["note_count"] = length(notes)
	R["notes"] = length(notes) > 6 ? notes.Copy(1, 7) : notes
	return R

//Who's online, and who left since the server started, for the picker
/datum/ban_window/proc/online_list()
	. = list()
	for(var/client/C in GLOB.clients)
		var/mob/M = C.mob
		. += list(list("key" = C.key, "ckey" = C.ckey, "name" = (!M || isnewplayer(M)) ? "Lobby" : M.real_name, "job" = M?.mind?.assigned_role, "admin" = !!C.holder))
	sortTim(., GLOBAL_PROC_REF(cmp_ban_window_by_key))

/datum/ban_window/proc/left_list()
	. = list()
	for(var/player_ckey in SSbans.left_this_round)
		if(GLOB.directory[player_ckey])
			continue
		var/list/entry = SSbans.seen[player_ckey]
		if(!entry)
			continue
		. += list(list("key" = entry["key"] || player_ckey, "ckey" = player_ckey, "name" = entry["name"], "job" = entry["job"], "ago" = ban_span_text((world.realtime - text2num(entry["left"])) / 10)))
	sortTim(., GLOBAL_PROC_REF(cmp_ban_window_by_key))

/proc/cmp_ban_window_by_key(list/a, list/b)
	return sorttext(b["ckey"], a["ckey"])

/datum/ban_window/proc/make_ban(list/params)
	var/static/regex/ipv4 = new(@"^\d{1,3}(\.\d{1,3}){3}$")
	var/list/errors = list()
	var/key = trim("[params["key"]]")
	var/ip = text2num(params["use_ip"]) ? trim("[params["ip"]]") : null
	var/cid = text2num(params["use_cid"]) ? trim("[params["cid"]]") : null
	if(text2num(params["use_ip"]) && !ip)
		errors += "IP is ticked but empty."
	else if(ip && !ipv4.Find(ip))
		errors += "[ip] isn't an IP address."
	if(text2num(params["use_cid"]) && !cid)
		errors += "Computer ID is ticked but empty."
	if(!key && !ip && !cid)
		errors += "Give a key, an IP or a computer ID."
	var/perm = text2num(params["perm"])
	var/length = text2num(params["length"])
	var/unit = params["unit"]
	if(!perm)
		if(!(length > 0))
			errors += "The length has to be a number above 0."
		if(!(unit in BAN_INTERVALS))
			errors += "Pick minutes, hours, days, weeks, months or years."
	var/reason = trim("[params["reason"]]")
	if(!reason)
		errors += "Write a reason."
	else if(length_char(reason) > BAN_REASON_MAX)
		errors += "The reason is [length_char(reason)] characters long; the most it can be is [BAN_REASON_MAX]."
	var/severity = params["severity"]
	if(!(severity in list("none", "minor", "medium", "high")))
		errors += "Pick a severity for the note the ban writes."
	var/list/roles = list()
	if(params["kind"] == "roles")
		for(var/role in splittext("[params["roles"]]", ","))
			if(ban_role_valid(role))
				roles |= role
		if(!roles.len)
			errors += "Pick the roles to ban from."
	else
		roles += "Server"
	if(errors.len)
		say("Not banned: [errors.Join(" ")]", TRUE)
		return
	var/datum/admins/holder = usr.client.holder
	if(!holder.create_ban(key, !!ip, ip, !!cid, cid, FALSE, text2num(params["applies"]) ? TRUE : FALSE, perm ? null : "[length]", perm ? null : unit, severity, reason, roles, TRUE))
		say("Not banned: see the chat for why.", TRUE)
		return
	var/list/intervals = BAN_INTERVALS
	var/what = roles[1] == "Server" ? "the server" : (roles.len == 1 ? roles[1] : "[roles.len] roles")
	say("Banned [ban_target_text(key, ip, cid)] from [what] [perm ? "permanently" : "for [ban_span_text(length * intervals[unit])]"].")
	var/list/form = default_form(prefill["serial"] + 1)
	form["key"] = key
	form["ip"] = params["ip"]
	form["cid"] = params["cid"]
	prefill = form
	lookup(key)
	searched = FALSE

/proc/ban_target_text(key, ip, cid)
	if(key)
		return key
	var/list/parts = list()
	if(ip)
		parts += ip
	if(cid)
		parts += cid
	return parts.Join("/")

////////////
// Bans
////////////

//Bans as rows, from the database (if it answers; with the ones kept here it hasn't got) or this server's copy.
//statuses: any of active, expired, lifted. text: part of a key, admin, role, reason, IP or computer ID.
/datum/ban_window/proc/find_rows(text, exact_ckey, list/statuses, limit = BAN_WINDOW_ROWS_ASKED)
	. = list()
	if(!length(statuses))
		return
	var/needle = lowertext(trim("[text]"))
	var/needle_ckey = ckey(needle)
	var/use_db = CONFIG_GET(flag/sql_enabled) && SSdbcore.Connect()
	if(use_db)
		var/ban_table = format_table_name("ban")
		var/player_table = format_table_name("player")
		var/list/status_sql = list()
		if("active" in statuses)
			status_sql += "(unbanned_datetime IS NULL AND (expiration_time IS NULL OR expiration_time > NOW()))"
		if("expired" in statuses)
			status_sql += "(unbanned_datetime IS NULL AND expiration_time <= NOW())"
		if("lifted" in statuses)
			status_sql += "(unbanned_datetime IS NOT NULL)"
		var/list/where = list("([status_sql.Join(" OR ")])")
		if(exact_ckey)
			where += "ckey = '[sanitizeSQL(exact_ckey)]'"
		if(needle)
			var/n = sanitizeSQL(needle)
			var/list/any = list("role LIKE '%[n]%'", "reason LIKE '%[n]%'", "INET_NTOA(ip) LIKE '%[n]%'", "computerid LIKE '%[n]%'")
			if(needle_ckey)
				any += "ckey LIKE '%[sanitizeSQL(needle_ckey)]%'"
				any += "a_ckey LIKE '%[sanitizeSQL(needle_ckey)]%'"
			where += "([any.Join(" OR ")])"
		var/datum/DBQuery/query_ban_window = SSdbcore.NewQuery("SELECT id, role, ckey, IFNULL((SELECT byond_key FROM [player_table] WHERE [player_table].ckey = [ban_table].ckey), ckey), INET_NTOA(ip), computerid, bantime, TIMESTAMPDIFF(SECOND, bantime, NOW()), TIMESTAMPDIFF(SECOND, NOW(), expiration_time), applies_to_admins, reason, IFNULL((SELECT byond_key FROM [player_table] WHERE [player_table].ckey = [ban_table].a_ckey), a_ckey), round_id, unbanned_datetime, IFNULL((SELECT byond_key FROM [player_table] WHERE [player_table].ckey = [ban_table].unbanned_ckey), unbanned_ckey), unbanned_round_id, IF(edits IS NULL, 0, 1), TIMESTAMPDIFF(MINUTE, bantime, expiration_time) FROM [ban_table] WHERE [where.Join(" AND ")] ORDER BY id DESC LIMIT [limit]")
		if(query_ban_window.warn_execute())
			while(query_ban_window.NextRow())
				var/list/i = query_ban_window.item
				var/bantime_rt = world.realtime - text2num(i[8]) * 10
				var/expire_rt = isnull(i[9]) ? null : world.realtime + text2num(i[9]) * 10
				. += list(ban_window_row(i[1], i[2], i[3], i[4], i[5], i[6], i[7], bantime_rt, expire_rt, text2num(i[10]), i[11], i[12], i[13], i[14], i[15], i[16], text2num(i[17]), FALSE, text2num(i[18])))
		else
			use_db = FALSE
		qdel(query_ban_window)
	for(var/id in SSbans.records)
		var/datum/ban_record/B = SSbans.records[id]
		if(use_db && !B.is_local())
			continue
		if(exact_ckey && B.ckey != exact_ckey)
			continue
		var/status = B.unbanned_datetime ? "lifted" : ((B.expire_rt && B.expire_rt <= world.realtime) ? "expired" : "active")
		if(!(status in statuses))
			continue
		if(needle && !(findtext(B.role, needle) || findtext(B.reason, needle) || findtext(B.ip, needle) || findtext(B.cid, needle) || (needle_ckey && (findtext(B.ckey, needle_ckey) || findtext(B.a_ckey, needle_ckey)))))
			continue
		. += list(ban_window_row(B.id, B.role, B.ckey, B.key || B.ckey, B.ip, B.cid, B.bantime, B.bantime_rt, B.expire_rt, B.applies_to_admins, B.reason, B.a_key || B.a_ckey, B.round_id, B.unbanned_datetime, B.unbanned_key || B.unbanned_ckey, B.unbanned_round_id, !!B.edits, B.is_local(), B.duration_minutes()))

//minutes: its length as given, null for permanent
/proc/ban_window_row(id, role, ckey, key, ip, cid, bantime, bantime_rt, expire_rt, applies, reason, a_key, round_id, unbanned, unbanned_key, unbanned_round_id, edits, local, minutes)
	return list("id" = "[id]", "role" = role, "ckey" = ckey, "key" = key, "ip" = ip, "cid" = cid, "bantime" = bantime, "bantime_rt" = bantime_rt, "expire_rt" = expire_rt, "applies" = applies ? TRUE : FALSE, "reason" = reason, "a_key" = a_key, "round_id" = round_id, "unbanned" = unbanned, "unbanned_key" = unbanned_key, "unbanned_round_id" = unbanned_round_id, "edits" = edits ? TRUE : FALSE, "local" = local ? TRUE : FALSE, "minutes" = expire_rt ? minutes : null)

/proc/ban_window_status(list/row)
	if(row["unbanned"])
		return "lifted"
	if(row["expire_rt"] && row["expire_rt"] <= world.realtime)
		return "expired"
	return "active"

//Role bans made together (same player, same time) as one group; a server ban is a group of its own
/datum/ban_window/proc/group_rows(list/rows)
	var/list/by_key = list()
	. = list()
	for(var/list/row in rows)
		var/group_key = "[row["ckey"]]|[row["ip"]]|[row["cid"]]|[row["bantime"]]|[lowertext(row["role"]) == "server" ? "S" : "R"]"
		var/list/G = by_key[group_key]
		if(!G)
			G = list("rows" = list())
			by_key[group_key] = G
			. += list(G)
		var/list/members = G["rows"]
		members += list(row)

//ending: active temporary ones ending soonest first, then active permanent ones, then the rest; newest: newest first
/datum/ban_window/proc/sort_groups(list/found, how)
	for(var/list/G in found)
		var/tier = 2
		var/newest = 0
		var/soonest
		for(var/list/row in G["rows"])
			newest = max(newest, row["bantime_rt"])
			if(ban_window_status(row) == "active")
				if(row["expire_rt"])
					soonest = soonest ? min(soonest, row["expire_rt"]) : row["expire_rt"]
					tier = 0
				else if(tier > 1)
					tier = 1
		if(how == "newest")
			G["sort_tier"] = 0
			G["sort_key"] = -newest
		else
			G["sort_tier"] = tier
			G["sort_key"] = tier == 0 ? soonest : -newest
	sortTim(found, GLOBAL_PROC_REF(cmp_ban_window_groups))
	return found

/proc/cmp_ban_window_groups(list/a, list/b)
	if(a["sort_tier"] != b["sort_tier"])
		return a["sort_tier"] - b["sort_tier"]
	return a["sort_key"] - b["sort_key"]

/datum/ban_window/proc/find()
	searched = TRUE
	var/list/statuses = list()
	if(show_active)
		statuses += "active"
	if(show_expired)
		statuses += "expired"
	if(show_lifted)
		statuses += "lifted"
	groups = sort_groups(group_rows(find_rows(search, null, statuses)), sort)

//A group as the window shows it, with the time left as of now
/datum/ban_window/proc/group_data(list/G)
	var/list/rows = G["rows"]
	var/list/first = rows[1]
	var/list/roles = list()
	var/list/active_ids = list()
	var/any_active = FALSE
	var/all_lifted = TRUE
	var/edits = FALSE
	var/local = FALSE
	var/list/lead = first //the row the header describes: an active one if any
	for(var/list/row in rows)
		var/status = ban_window_status(row)
		roles += list(list("role" = row["role"], "id" = row["id"], "status" = status))
		if(status == "active")
			if(!any_active)
				lead = row
			any_active = TRUE
			active_ids += row["id"]
		if(status != "lifted")
			all_lifted = FALSE
		if(row["edits"])
			edits = TRUE
		if(row["local"])
			local = TRUE
	var/expire_rt = lead["expire_rt"]
	var/bantime_rt = lead["bantime_rt"]
	var/fraction = 0
	if(expire_rt && expire_rt > bantime_rt)
		fraction = clamp((world.realtime - bantime_rt) / (expire_rt - bantime_rt), 0, 1)
	var/minutes = expire_rt ? max(1, lead["minutes"] || round((expire_rt - bantime_rt) / 600)) : null
	return list(
		"id" = lead["id"],
		"ids" = active_ids,
		"server" = lowertext(first["role"]) == "server",
		"key" = lead["key"],
		"ckey" = lead["ckey"],
		"ip" = lead["ip"],
		"cid" = lead["cid"],
		"target" = ban_target_text(lead["key"], lead["ip"], lead["cid"]),
		"admin" = lead["a_key"],
		"bantime" = lead["bantime"],
		"bantime_rt" = num2text(bantime_rt, 12),
		"round_id" = lead["round_id"],
		"applies" = lead["applies"],
		"reason" = lead["reason"],
		"status" = any_active ? "active" : (all_lifted ? "lifted" : "expired"),
		"left" = !expire_rt ? "Permanent" : (expire_rt > world.realtime ? "[ban_span_text((expire_rt - world.realtime) / 10)] left" : "Ended"),
		"fraction" = fraction,
		"length" = minutes ? ban_span_text(minutes * 60) : "Permanent",
		"minutes" = minutes,
		"ends" = expire_rt ? SQLtime(expire_rt) : null,
		"lifted_by" = first["unbanned_key"],
		"lifted_at" = first["unbanned"],
		"roles" = roles,
		"edits" = edits,
		"local" = local)

//The group (in the list, or the record's) a ban is in
/datum/ban_window/proc/find_group(id)
	id = "[id]"
	var/list/all = groups.Copy()
	if(record)
		all += record["groups_raw"]
	for(var/list/G in all)
		for(var/list/row in G["rows"])
			if(row["id"] == id)
				return G

/datum/ban_window/proc/find_row(id)
	var/list/G = find_group(id)
	if(!G)
		return
	for(var/list/row in G["rows"])
		if(row["id"] == "[id]")
			return row

//Lifts the given rows of one group, with one message for all of them
/datum/ban_window/proc/lift_rows(list/rows)
	var/list/lifted = list()
	var/queued = FALSE
	var/list/lead
	for(var/list/row in rows)
		if(ban_window_status(row) != "active")
			continue
		var/result = SSbans.lift(row["id"], usr.client.ckey, usr.client.key, usr.client.address, usr.client.computer_id)
		if(!result)
			continue
		if(result == "queued")
			queued = TRUE
		lifted += row["role"]
		if(!lead)
			lead = row
	if(!lifted.len)
		say("Nothing was lifted: see the chat for why.", TRUE)
		return
	var/target = ban_target_text(lead["key"], lead["ip"], lead["cid"])
	var/what = (lowertext(lifted[1]) == "server") ? "the server" : lifted.Join(", ")
	log_admin_private("[key_name(usr)] has unbanned [target] from [what].")
	message_admins("[key_name_admin(usr)] has unbanned [target] from [what].")
	usr.client.holder.ban_tell_lifted(lead["key"], lead["ip"], lead["cid"], what)
	say("Lifted [target]'s ban from [what].[queued ? " The database couldn't be reached: it's lifted here, and there when it's back." : ""]")

//An edit from the list: key, IP, CID, length (from when it was made), admins, reason for the whole group, and for role bans,
//which roles (the ones taken off are lifted, the ones added are made with the group's time)
/datum/ban_window/proc/save_edit(list/params)
	var/static/regex/ipv4 = new(@"^\d{1,3}(\.\d{1,3}){3}$")
	var/list/G = find_group(params["id"])
	if(!G)
		say("That ban isn't in the list any more.", TRUE)
		return
	var/list/active = list()
	for(var/list/row in G["rows"])
		if(ban_window_status(row) == "active")
			active += list(row)
	if(!active.len)
		say("That ban has ended or been lifted, so it can't be edited.", TRUE)
		return
	var/list/target = active[1]
	var/list/errors = list()
	var/key = trim("[params["key"]]")
	var/ip = trim("[params["ip"]]")
	var/cid = trim("[params["cid"]]")
	if(ip && !ipv4.Find(ip))
		errors += "[ip] isn't an IP address."
	if(!key && !ip && !cid)
		errors += "Give a key, an IP or a computer ID."
	var/perm = text2num(params["perm"])
	var/length = text2num(params["length"])
	var/unit = params["unit"]
	if(!perm && (!(length > 0) || !(unit in BAN_INTERVALS)))
		errors += "The length has to be a number above 0, in minutes, hours, days, weeks, months or years."
	var/reason = trim("[params["reason"]]")
	if(!reason)
		errors += "Write a reason."
	else if(length_char(reason) > BAN_REASON_MAX)
		errors += "The reason is [length_char(reason)] characters long; the most it can be is [BAN_REASON_MAX]."
	var/applies = text2num(params["applies"]) ? TRUE : FALSE
	var/server = lowertext(target["role"]) == "server"
	var/list/wanted = list()
	if(!server)
		for(var/role in splittext("[params["roles"]]", ","))
			if(ban_role_valid(role))
				wanted |= role
		if(!wanted.len)
			errors += "A role ban needs a role; to end it, lift it."
	if(errors.len)
		say("Not saved: [errors.Join(" ")]", TRUE)
		return
	var/list/intervals = BAN_INTERVALS
	var/old_minutes = target["minutes"]
	var/new_minutes = perm ? null : round(length * intervals[unit] / 60)
	var/list/changes = list()
	if(key != target["key"])
		changes["Key"] = "[target["key"]] to [key]"
	if(ip != (target["ip"] || ""))
		changes["IP"] = "[target["ip"]] to [ip]"
	if(cid != (target["cid"] || ""))
		changes["CID"] = "[target["cid"]] to [cid]"
	if(applies != target["applies"])
		changes["Applies to admins"] = "[target["applies"]] to [applies]"
	if(isnull(old_minutes) != isnull(new_minutes) || (!isnull(new_minutes) && abs(new_minutes - old_minutes) > 1))
		changes["Duration"] = "[old_minutes ? "[old_minutes] MINUTE" : "permanent"] to [perm ? "permanent" : "[length] [unit]"]"
	if(reason != target["reason"])
		changes["Reason"] = "[target["reason"]]<br>to<br>[reason]"
	var/list/have = list()
	for(var/list/row in active)
		have[row["role"]] = row
	var/list/removed = list()
	var/list/added = list()
	if(!server)
		for(var/role in have)
			if(!(role in wanted))
				removed += list(have[role])
		for(var/role in wanted)
			if(!have[role])
				added += role
	if(!changes.len && !removed.len && !added.len)
		say("Nothing was changed.", TRUE)
		return
	var/datum/admins/holder = usr.client.holder
	if(changes.len && !holder.edit_ban(target["id"], key, !!ip, ip, !!cid, cid, FALSE, applies, perm ? null : "[length]", perm ? null : unit, reason, TRUE, target["key"], target["ip"], target["cid"], target["applies"], null, null, changes, TRUE))
		say("Not saved: see the chat for why.", TRUE)
		return
	if(removed.len)
		lift_rows(removed)
	if(added.len)
		add_roles(target, added, key, ip, cid, applies, reason, perm ? null : length, unit)
	var/list/done = list()
	if(changes.len)
		done += "changed the [jointext(changes, ", ")]"
	if(removed.len)
		done += "lifted [removed.len] role\s"
	if(added.len)
		done += "added [added.len] role\s"
	say("Saved: [done.Join(", ")].")

//New role bans with an existing group's time, so they show and edit as one
/datum/ban_window/proc/add_roles(list/target, list/roles, key, ip, cid, applies, reason, amount, unit)
	var/list/intervals = BAN_INTERVALS
	var/list/clients_online = GLOB.clients.Copy()
	var/list/admins_online = list()
	for(var/client/C in clients_online)
		if(C.holder)
			admins_online += C
	var/list/new_bans = list()
	for(var/role in roles)
		var/datum/ban_record/B = new
		B.role = role
		B.ckey = ckey(key)
		B.key = key
		B.ip = ip || null
		B.cid = cid || null
		B.bantime = target["bantime"]
		B.bantime_rt = target["bantime_rt"]
		B.exact_bantime = TRUE
		if(amount)
			B.amount = amount
			B.unit = unit
			B.expire_rt = B.bantime_rt + amount * intervals[unit] * 10
		B.applies_to_admins = applies
		B.reason = reason
		B.round_id = GLOB.round_id
		B.a_ckey = usr.client.ckey
		B.a_key = usr.client.key
		B.a_ip = usr.client.address
		B.a_cid = usr.client.computer_id
		B.who = clients_online.Join(", ")
		B.adminwho = admins_online.Join(", ")
		B.edits = "[usr.client.key] added this role to the ban on [SQLtime()]<hr>"
		new_bans += B
	var/stored = SSbans.add_bans(new_bans)
	if(!stored)
		say("The roles weren't added: see the chat for why.", TRUE)
		return
	var/target_text = ban_target_text(key, ip, cid)
	log_admin_private("[key_name(usr)] has added roles to [target_text]'s ban: [roles.Join(", ")]")
	message_admins("[key_name_admin(usr)] has added roles to [target_text]'s ban: [roles.Join(", ")]")
	if(GLOB.directory[ckey(key)])
		usr.client.holder.hippie_on_jobban(get_mob_by_key(ckey(key)), roles)
	for(var/client/C in GLOB.clients)
		if(C.ckey == ckey(key) || (ip && C.address == ip) || (cid && C.computer_id == cid))
			build_ban_cache(C)
			to_chat(C, "<span class='boldannounce'>[usr.client.key] has added [roles.Join(", ")] to your ban.\nReason: [reason]</span>", confidential=TRUE)

/datum/ban_window/proc/show_ban_log(id)
	if(log_id == "[id]")
		log_id = null
		log_text = null
		return
	var/edits
	var/datum/ban_record/B = SSbans.get(id)
	if(B && (B.is_local() || !CONFIG_GET(flag/sql_enabled) || !SSdbcore.Connect()))
		edits = B.edits
	else if(text2num(id) && CONFIG_GET(flag/sql_enabled) && SSdbcore.Connect())
		var/datum/DBQuery/query_ban_window_edits = SSdbcore.NewQuery("SELECT edits FROM [format_table_name("ban")] WHERE id = [text2num(id)]")
		if(query_ban_window_edits.warn_execute() && query_ban_window_edits.NextRow())
			edits = query_ban_window_edits.item[1]
		qdel(query_ban_window_edits)
	log_id = "[id]"
	log_text = edits ? comm_plain_text(replacetext(edits, "<hr>", "\n")) : "No edits."

////////////
// Sticky
////////////

//BYOND's one-key lookup misses a sticky ban made this tick (the whole list has it), so the copy SSstickyban keeps stands in
/datum/ban_window/proc/build_sticky()
	sticky = list()
	for(var/sticky_key in sticky_banned_ckeys())
		var/sticky_ckey = ckey(sticky_key)
		var/list/ban = get_stickyban_from_ckey(sticky_ckey) || SSstickyban.cache[sticky_ckey]
		if(!islist(ban))
			continue
		var/list/caught = list()
		for(var/k in ban["keys"])
			if(ckey(k) != sticky_ckey)
				caught += list(list("key" = k, "exempt" = FALSE))
		for(var/k in ban["whitelist"])
			if(ckey(k) != sticky_ckey)
				caught += list(list("key" = k, "exempt" = TRUE))
		sticky += list(list("ckey" = sticky_ckey, "reason" = ban["message"], "admin" = ban["admin"] || "Legacy", "caught" = caught, "timeout" = ban["timeout"] ? TRUE : FALSE))

////////////
// Notes
////////////

/datum/ban_window/proc/notes_open(view, target_ckey, kind, open_compose)
	if(view in list("index", "player", "memos", "watchlist", "watchlist_online"))
		notes_online_only = view == "watchlist_online"
		notes_view = view == "watchlist_online" ? "watchlist" : view
	if(target_ckey)
		notes_ckey = ckey(target_ckey)
	if(notes_view == "player" && !notes_ckey)
		notes_view = "index"
	compose = open_compose ? list("serial" = world.time, "kind" = kind || "note") : null
	note_log_id = null
	note_log_text = null
	notes_refresh()

/datum/ban_window/proc/notes_refresh()
	notes_players = SSnotes.players(notes_search)
	switch(notes_view)
		if("player")
			notes_rows = SSnotes.rows_for(notes_ckey)
		if("memos")
			notes_rows = SSnotes.rows_of_kind("memo")
		if("watchlist")
			notes_rows = SSnotes.rows_of_kind("watchlist entry")

/datum/ban_window/proc/notes_data()
	. = list()
	.["notes_view"] = notes_view
	.["notes_ckey"] = notes_ckey
	.["notes_key"] = notes_ckey ? note_key_of(notes_ckey) : null
	.["notes_online"] = notes_ckey && GLOB.directory[notes_ckey] ? TRUE : FALSE
	.["notes_search"] = notes_search
	.["notes_online_only"] = notes_online_only
	.["compose"] = compose
	.["note_log_id"] = note_log_id
	.["note_log_text"] = note_log_text
	.["stale_days"] = CONFIG_GET(number/note_stale_days)
	.["fresh_days"] = CONFIG_GET(number/note_fresh_days)
	.["notes_players"] = notes_players
	if(notes_view == "index")
		return
	var/list/rows = list()
	for(var/list/row in notes_rows)
		if(notes_view == "watchlist" && notes_online_only && !GLOB.directory[row["target_ckey"]])
			continue
		var/list/shown = row.Copy()
		shown["edits"] = row["edits"] ? TRUE : FALSE
		shown["online"] = GLOB.directory[row["target_ckey"]] ? TRUE : FALSE
		rows += list(shown)
	.["notes_rows"] = rows

/datum/ban_window/proc/note_log(id)
	if(note_log_id == "[id]")
		note_log_id = null
		note_log_text = null
		return
	var/edits = SSnotes.edits_of(id)
	note_log_id = "[id]"
	note_log_text = edits ? comm_plain_text(replacetext(edits, "<hr>", "\n")) : "No edits."

////////////
// tgui
////////////

/datum/ban_window/ui_static_data(mob/user)
	. = list()
	.["role_groups"] = ban_role_groups()
	.["expiry_choices"] = GLOB.note_expiry_choices
	.["reason_max"] = BAN_REASON_MAX
	.["note_max"] = NOTE_TEXT_MAX

/datum/ban_window/ui_data(mob/user)
	var/list/data = list()
	var/can_ban = check_rights_for(user.client, R_BAN) ? TRUE : FALSE
	data["can_ban"] = can_ban
	var/shown_tab = (!can_ban && tab != "notes") ? "notes" : tab
	data["tab"] = shown_tab
	data["notice"] = notice
	data["notice_bad"] = notice_bad
	data["db"] = !CONFIG_GET(flag/sql_enabled) ? "off" : (SSdbcore.IsConnected() ? "up" : "down")
	data["now"] = num2text(world.realtime, 12)
	data["tz"] = world.timezone
	switch(shown_tab)
		if("new")
			data["prefill"] = prefill
			data["record"] = record_data()
			data["online"] = online_list()
			data["left"] = left_list()
		if("bans")
			data["search"] = search
			data["show_active"] = show_active
			data["show_expired"] = show_expired
			data["show_lifted"] = show_lifted
			data["sort"] = sort
			var/list/shown = list()
			for(var/i in 1 to min(groups.len, BAN_WINDOW_GROUPS_SHOWN))
				shown += list(group_data(groups[i]))
			data["groups"] = shown
			data["more"] = max(0, groups.len - BAN_WINDOW_GROUPS_SHOWN)
			data["log_id"] = log_id
			data["log_text"] = log_text
		if("sticky")
			data["sticky"] = sticky
			data["sticky_db"] = CONFIG_GET(flag/sql_enabled) && SSdbcore.IsConnected() ? TRUE : FALSE
		if("notes")
			var/list/notes = notes_data()
			for(var/field in notes)
				data[field] = notes[field]
	return data

/datum/ban_window/ui_act(action, list/params)
	if(..())
		return
	if(!usr.client?.holder)
		return
	if(action == "player_menu") // a name's menu (player_menu.dm)
		return player_menu_act(usr, params)
	var/datum/admins/holder = usr.client.holder
	notice = null
	notice_bad = FALSE
	switch(action)
		if("tab")
			var/new_tab = params["tab"]
			if(!(new_tab in list("new", "bans", "sticky", "notes")))
				return
			if(new_tab != "notes" && !check_rights(R_BAN))
				return
			tab = new_tab
			switch(tab)
				if("bans")
					find()
				if("sticky")
					build_sticky()
				if("notes")
					notes_refresh()
				if("new")
					if(record)
						lookup(record["ckey"])
			return TRUE
		if("open_player")
			if(!check_rights(R_BAN))
				return
			tab = "new"
			set_player(params["key"])
			return TRUE
		if("show_in_list")
			if(!check_rights(R_BAN))
				return
			tab = "bans"
			search = "[params["key"]]"
			show_active = TRUE
			show_expired = TRUE
			show_lifted = TRUE
			sort = "newest"
			find()
			return TRUE
		if("open_notes")
			tab = "notes"
			notes_open("player", params["key"])
			return TRUE

		//New ban
		if("lookup")
			if(!check_rights(R_BAN))
				return
			lookup(params["key"])
			return TRUE
		if("pick")
			if(!check_rights(R_BAN))
				return
			set_player(params["key"])
			return TRUE
		if("ban")
			if(!check_rights(R_BAN))
				return
			make_ban(params)
			return TRUE
		if("lift_role")
			if(!check_rights(R_BAN) || !record)
				return
			var/list/raw = record["role_bans_raw"]
			for(var/role in raw)
				var/list/B = raw[role]
				if(B["id"] == params["id"])
					if(holder.unban(B["id"], B["key"], B["ip"], B["cid"], B["role"], TRUE))
						say("Lifted the [B["role"]] ban.")
					break
			lookup(record["ckey"])
			searched = FALSE
			return TRUE

		//Bans
		if("search")
			if(!check_rights(R_BAN))
				return
			search = "[params["text"]]"
			show_active = text2num(params["active"]) ? TRUE : FALSE
			show_expired = text2num(params["expired"]) ? TRUE : FALSE
			show_lifted = text2num(params["lifted"]) ? TRUE : FALSE
			if(params["sort"] in list("ending", "newest"))
				sort = params["sort"]
			find()
			return TRUE
		if("lift_group", "lift_one")
			if(!check_rights(R_BAN))
				return
			var/list/G = find_group(params["id"])
			if(!G)
				say("That ban isn't in the list any more.", TRUE)
				return TRUE
			if(action == "lift_group")
				lift_rows(G["rows"])
			else
				var/list/row = find_row(params["id"])
				if(row)
					lift_rows(list(row))
			ban_window_refresh()
			return TRUE
		if("edit_save")
			if(!check_rights(R_BAN))
				return
			save_edit(params)
			ban_window_refresh()
			return TRUE
		if("ban_log")
			if(!check_rights(R_BAN))
				return
			show_ban_log(params["id"])
			return TRUE

		//Sticky
		if("sticky_add")
			if(!check_rights(R_BAN))
				return
			var/sticky_ckey = ckey(params["ckey"])
			var/reason = trim("[params["reason"]]")
			if(!sticky_ckey || !reason)
				say("A sticky ban needs a key and a reason.", TRUE)
				return TRUE
			holder.stickyban("add", list("ckey" = sticky_ckey, "reason" = reason))
			build_sticky()
			return TRUE
		if("sticky")
			if(!check_rights(R_BAN))
				return
			var/op = params["op"]
			if(!(op in list("remove", "remove_alt", "exempt", "unexempt", "timeout", "untimeout", "revert", "edit")))
				return
			holder.stickyban(op, list("ckey" = ckey(params["ckey"]), "alt" = params["alt"], "confirmed" = TRUE, "newreason" = params["reason"]))
			build_sticky()
			return TRUE

		//Notes
		if("notes_view")
			if(!check_rights(R_ADMIN))
				return
			notes_open(params["view"], params["key"])
			return TRUE
		if("notes_search")
			if(!check_rights(R_ADMIN))
				return
			notes_search = "[params["text"]]"
			notes_view = "index"
			notes_refresh()
			return TRUE
		if("notes_online_only")
			notes_online_only = !notes_online_only
			return TRUE
		if("compose")
			compose = params["kind"] ? list("serial" = world.time, "kind" = params["kind"]) : null
			return TRUE
		if("note_add")
			if(!check_rights(R_ADMIN))
				return
			var/kind = params["kind"]
			if(!(kind in list("note", "message", "watchlist entry", "memo")))
				return
			var/text = trim("[params["text"]]")
			var/target_key = kind == "memo" ? null : (params["key"] || notes_ckey)
			if(!text)
				say("Write something first.", TRUE)
				return TRUE
			if(kind != "memo" && !ckey(target_key))
				say("A [kind] needs a player.", TRUE)
				return TRUE
			if(kind == "note" && !(params["severity"] in list("none", "minor", "medium", "high")))
				say("Pick a severity for the note.", TRUE)
				return TRUE
			var/seconds = GLOB.note_expiry_choices[params["expiry"]] || 0
			var/secret = kind == "watchlist entry" ? TRUE : (text2num(params["secret"]) ? TRUE : FALSE)
			if(create_message(kind, target_key, null, text, null, null, secret, 1, null, seconds, kind == "note" ? params["severity"] : null))
				say("Added the [kind][kind == "memo" ? "" : " for [note_key_of(ckey(target_key))]"].")
				compose = null
				if(kind != "memo" && notes_view != "watchlist")
					notes_view = "player"
					notes_ckey = ckey(target_key)
			notes_refresh()
			return TRUE
		if("note_text")
			if(!check_rights(R_ADMIN))
				return
			if(note_set_text(params["id"], trim("[params["text"]]")))
				say("Saved.")
			notes_refresh()
			return TRUE
		if("note_severity")
			if(!check_rights(R_ADMIN))
				return
			note_set_severity(params["id"], params["severity"])
			notes_refresh()
			return TRUE
		if("note_secret")
			if(!check_rights(R_ADMIN))
				return
			note_toggle_secret(params["id"])
			notes_refresh()
			return TRUE
		if("note_expiry")
			if(!check_rights(R_ADMIN))
				return
			if(params["expiry"] in GLOB.note_expiry_choices)
				note_set_expiry(params["id"], GLOB.note_expiry_choices[params["expiry"]])
			notes_refresh()
			return TRUE
		if("note_delete")
			if(!check_rights(R_ADMIN))
				return
			if(note_delete(params["id"]))
				say("Deleted.")
			notes_refresh()
			return TRUE
		if("note_log")
			if(!check_rights(R_ADMIN))
				return
			note_log(params["id"])
			return TRUE

//After a lift or an edit: the list and the record again, from what's there now
/datum/ban_window/proc/ban_window_refresh()
	if(searched)
		find()
	if(record)
		lookup(record["ckey"])

#undef BAN_WINDOW_GROUPS_SHOWN
#undef BAN_WINDOW_ROWS_ASKED
