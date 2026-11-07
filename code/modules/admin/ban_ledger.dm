//Bans are kept here as well as in the database, and every ban check reads this copy (or a client's ban_cache, made from here
//and the database at login) rather than running a query of its own. So bans hold whatever the database does:
//	with SQL off this is the ban list, and banning works with no database at all;
//	with the database down, banned players stay banned from the last copy, and admins can still ban, unban and edit. What they
//	do waits here and goes to the database when it's back, which is checked every minute;
//	a ban check never queries or sleeps, wherever it's called from (set_species, the job picks, ghost spawners, bots).
//The copy is saved to data/bans.json whenever it changes, with the one before it kept in data/bans.json.bak.

//Seconds in each length an admin can pick. A month and a year are approximate only for bans made with no database: the database counts them by the calendar.
#define BAN_INTERVALS list("SECOND" = 1, "MINUTE" = 60, "HOUR" = 3600, "DAY" = 86400, "WEEK" = 604800, "MONTH" = 2592000, "YEAR" = 31536000)
//How often the copy of the database's bans is refreshed, for bans made or lifted by other servers on the same database
#define BAN_SYNC_INTERVAL (5 MINUTES)
//Sizes of the ban table's text columns, which strict mode refuses to overflow
#define BAN_REASON_MAX 2048
#define BAN_WHO_MAX 2048

/datum/ban_record
	var/id //"123" for a ban in the database, "L7" for one made on this server that isn't in the database (yet)
	var/role
	var/ckey
	var/key
	var/ip
	var/cid
	var/bantime //text, for showing
	var/bantime_rt //world.realtime when it was made
	var/expire_rt //world.realtime when it ends, null if it doesn't
	var/amount //the length as the admin gave it, so the database gets the same INTERVAL
	var/unit
	var/applies_to_admins = FALSE
	var/reason
	var/round_id
	var/a_ckey
	var/a_key
	var/a_ip
	var/a_cid
	var/who
	var/adminwho
	var/edits
	var/unbanned_datetime
	var/unbanned_rt
	var/unbanned_ckey
	var/unbanned_key
	var/unbanned_ip
	var/unbanned_cid
	var/unbanned_round_id
	var/exact_bantime = FALSE //a role added to a ban already made: it goes to the database with that ban's time, so they stay together

GENERAL_PROTECT_DATUM(/datum/ban_record)

/datum/ban_record/proc/is_local()
	return copytext(id, 1, 2) == "L"

/datum/ban_record/proc/is_active()
	return !unbanned_datetime && (!expire_rt || expire_rt > world.realtime)

//From the length it was given when there is one: world.realtime is a float about a minute coarse, so the two times alone make a
//three-day ban 4319 minutes ("2 days and 23 hours and 59 minutes")
/datum/ban_record/proc/duration_minutes()
	if(!expire_rt)
		return
	var/list/intervals = BAN_INTERVALS
	if(amount && (unit in intervals))
		return round(amount * intervals[unit] / 60)
	return round((expire_rt - bantime_rt) / 600)

/datum/ban_record/proc/expiration_text()
	if(expire_rt)
		return SQLtime(expire_rt)

/datum/ban_record/proc/matches(match_ckey, match_ip, match_cid)
	return (match_ckey && ckey == match_ckey) || (match_ip && ip == match_ip) || (match_cid && cid == match_cid)

//In the shape is_banned_from_with_details() gives the database's
/datum/ban_record/proc/details()
	return list("id" = id, "bantime" = bantime, "round_id" = round_id, "expiration_time" = expiration_text(), "duration" = duration_minutes(), "applies_to_admins" = applies_to_admins, "reason" = reason, "key" = key || ckey, "ip" = ip, "computerid" = cid, "admin_key" = a_key || a_ckey)

/datum/ban_record/proc/fields()
	var/static/list/names = list("id", "role", "ckey", "key", "ip", "cid", "bantime", "bantime_rt", "expire_rt", "amount", "unit", "applies_to_admins", "reason", "round_id", "a_ckey", "a_key", "a_ip", "a_cid", "who", "adminwho", "edits", "unbanned_datetime", "unbanned_rt", "unbanned_ckey", "unbanned_key", "unbanned_ip", "unbanned_cid", "unbanned_round_id")
	return names

//world.realtime goes into the file as text: json_encode keeps six digits of it, which is five minutes
/datum/ban_record/proc/to_list()
	var/static/list/times = list("bantime_rt", "expire_rt", "unbanned_rt")
	. = list()
	for(var/field in fields())
		var/value = vars[field]
		if(isnum(value) && (field in times))
			value = num2text(value, 12)
		.[field] = value

/datum/ban_record/proc/from_list(list/L)
	var/static/list/times = list("bantime_rt", "expire_rt", "unbanned_rt")
	for(var/field in fields())
		var/value = L[field]
		if(istext(value) && (field in times))
			value = text2num(value)
		vars[field] = value

//Column = SQL, for MassInsert(). Times are counted back from NOW(), so a ban kept here while the database was down lands on the database's clock at the time it was made.
/datum/ban_record/proc/sql_values()
	var/age = max(0, round((world.realtime - bantime_rt) / 10))
	var/bantime_sql = age ? "(NOW() - INTERVAL [age] SECOND)" : "NOW()"
	if(exact_bantime && bantime)
		bantime_sql = "'[sanitizeSQL(bantime)]'"
	var/expiration_sql = "NULL"
	if(expire_rt)
		if(amount && (unit in BAN_INTERVALS))
			expiration_sql = "[bantime_sql] + INTERVAL [num2text(amount, 12)] [unit]"
		else
			expiration_sql = "[bantime_sql] + INTERVAL [max(0, round((expire_rt - bantime_rt) / 10))] SECOND"
	. = list("bantime" = bantime_sql,
		"server_ip" = "INET_ATON(IF('[world.internet_address]' LIKE '', '0', '[world.internet_address]'))",
		"server_port" = "[world.port]",
		"round_id" = "'[text2num(round_id) || 0]'",
		"role" = "'[sanitizeSQL(role)]'",
		"expiration_time" = expiration_sql,
		"applies_to_admins" = applies_to_admins ? "1" : "0",
		"reason" = "'[sanitizeSQL(reason)]'",
		"ckey" = ckey ? "'[sanitizeSQL(ckey)]'" : "NULL",
		"ip" = ip ? "INET_ATON('[sanitizeSQL(ip)]')" : "NULL",
		"computerid" = cid ? "'[sanitizeSQL(cid)]'" : "NULL",
		"a_ckey" = "'[sanitizeSQL(a_ckey)]'",
		"a_ip" = "IFNULL(INET_ATON('[sanitizeSQL(a_ip)]'), 0)", //the column is NOT NULL, and the host's address is empty
		"a_computerid" = "'[sanitizeSQL(a_cid)]'",
		"who" = "'[sanitizeSQL(copytext_char(who, 1, BAN_WHO_MAX))]'", //everyone online: a busy server's list is longer than the column
		"adminwho" = "'[sanitizeSQL(copytext_char(adminwho, 1, BAN_WHO_MAX))]'",
		"edits" = edits ? "'[sanitizeSQL(edits)]'" : "NULL")
	if(unbanned_datetime)
		var/unban_age = max(0, round((world.realtime - unbanned_rt) / 10))
		.["unbanned_datetime"] = unban_age ? "(NOW() - INTERVAL [unban_age] SECOND)" : "NOW()"
		.["unbanned_ckey"] = "'[sanitizeSQL(unbanned_ckey)]'"
		.["unbanned_ip"] = "INET_ATON('[sanitizeSQL(unbanned_ip)]')"
		.["unbanned_computerid"] = "'[sanitizeSQL(unbanned_cid)]'"
		.["unbanned_round_id"] = "'[text2num(unbanned_round_id) || 0]'"

SUBSYSTEM_DEF(bans)
	name = "Bans"
	wait = 1 MINUTES
	flags = SS_NO_INIT|SS_BACKGROUND
	runlevels = RUNLEVEL_LOBBY|RUNLEVELS_DEFAULT

	var/list/records = list() //id = /datum/ban_record: the database's active bans as last copied, and every ban made on this server
	var/list/by_ckey = list() //ckey, ip or cid = list of records with it, for the checks
	var/list/by_ip = list()
	var/list/by_cid = list()
	var/list/queued_ops = list() //unbans and edits of bans in the database, made while it couldn't be reached
	var/list/moved_ids = list() //"L7" = "123" once a ban made here reaches the database, for panels still open on the old id
	var/next_local_id = 1
	var/ledger_path = "data/bans.json"
	var/last_saved //the file's text, so an unchanged copy isn't written again
	var/primary_ok = FALSE //bans.json read fine or has been written: only then is it copied over the backup
	var/next_sync = 0
	var/db_busy = FALSE
	var/list/refused = list() //bans made here that the database said no to this round: still enforced here, not retried until next round
	var/list/known_cids = list() //ckey = the computer ID it logged in with this round, for role bans on that computer

/datum/controller/subsystem/bans/stat_entry()
	..("B:[records.len] Q:[queued_ops.len]")

/datum/controller/subsystem/bans/Recover()
	records = SSbans.records
	by_ckey = SSbans.by_ckey
	by_ip = SSbans.by_ip
	by_cid = SSbans.by_cid
	queued_ops = SSbans.queued_ops
	moved_ids = SSbans.moved_ids
	refused = SSbans.refused
	known_cids = SSbans.known_cids
	seen = SSbans.seen
	seen_by_ip = SSbans.seen_by_ip
	seen_by_cid = SSbans.seen_by_cid
	left_this_round = SSbans.left_this_round
	seen_loaded = SSbans.seen_loaded
	seen_dirty = SSbans.seen_dirty
	next_local_id = SSbans.next_local_id
	ledger_path = SSbans.ledger_path
	last_saved = SSbans.last_saved
	primary_ok = SSbans.primary_ok

//The lists hold every banned player's IP and computer ID
/datum/controller/subsystem/bans/can_vv_get(var_name)
	return !(var_name in list(NAMEOF(src, records), NAMEOF(src, by_ckey), NAMEOF(src, by_ip), NAMEOF(src, by_cid), NAMEOF(src, queued_ops), NAMEOF(src, last_saved), NAMEOF(src, known_cids), NAMEOF(src, seen), NAMEOF(src, seen_by_ip), NAMEOF(src, seen_by_cid))) && ..()

/datum/controller/subsystem/bans/vv_edit_var(var_name, var_value)
	return FALSE

/datum/controller/subsystem/bans/CanProcCall(procname)
	return FALSE

/datum/controller/subsystem/bans/fire()
	save_seen()
	if(!CONFIG_GET(flag/sql_enabled))
		return
	if(!db_busy && (length(queued_ops) || world.time >= next_sync || has_unsent()))
		INVOKE_ASYNC(src, PROC_REF(db_update))

/datum/controller/subsystem/bans/proc/has_unsent()
	for(var/id in records)
		var/datum/ban_record/B = records[id]
		if(B.is_local() && !refused[id])
			return TRUE

//Called from world/New(), before anyone can connect: the file now, the database after
/datum/controller/subsystem/bans/proc/load()
	var/list/data = read_ledger(ledger_path)
	primary_ok = !!data //if bans.json is broken it mustn't be copied over the backup at the next save
	if(!data)
		data = read_ledger("[ledger_path].bak")
		if(data)
			log_world("Bans: [ledger_path] couldn't be read, loaded the backup")
	records = list()
	by_ckey = list()
	by_ip = list()
	by_cid = list()
	queued_ops = list()
	moved_ids = list()
	last_saved = null
	if(data)
		next_local_id = max(1, text2num(data["next_local_id"]))
		for(var/list/L in data["records"])
			var/datum/ban_record/B = new
			B.from_list(L)
			if(B.id)
				add(B)
		for(var/list/op in data["queued_ops"])
			queued_ops += list(op)
		for(var/old_id in data["moved_ids"])
			moved_ids[old_id] = data["moved_ids"][old_id]
	log_world("Bans: [records.len] from [ledger_path][length(queued_ops) ? ", [queued_ops.len] changes waiting for the database" : ""]")
	if(!seen_loaded)
		load_seen()
	if(CONFIG_GET(flag/sql_enabled))
		INVOKE_ASYNC(src, PROC_REF(db_update))

/datum/controller/subsystem/bans/proc/read_ledger(path)
	if(!fexists(path))
		return
	var/text = file2text(path)
	if(!length(text))
		return
	var/list/data
	try
		data = json_decode(text)
	catch
		return
	if(islist(data) && islist(data["records"]))
		return data

/datum/controller/subsystem/bans/proc/save()
	var/list/out = list()
	for(var/id in records)
		var/datum/ban_record/B = records[id]
		out += list(B.to_list())
	var/text = json_encode(list("version" = 1, "next_local_id" = next_local_id, "records" = out, "queued_ops" = queued_ops, "moved_ids" = moved_ids))
	if(text == last_saved)
		return
	if(primary_ok && fexists(ledger_path))
		fcopy(ledger_path, "[ledger_path].bak")
	fdel(ledger_path)
	text2file(text, ledger_path)
	last_saved = text
	primary_ok = TRUE

/datum/controller/subsystem/bans/proc/add(datum/ban_record/B)
	records[B.id] = B
	if(B.ckey)
		var/list/L = by_ckey[B.ckey]
		if(!L)
			L = by_ckey[B.ckey] = list()
		L |= B
	if(B.ip)
		var/list/L = by_ip[B.ip]
		if(!L)
			L = by_ip[B.ip] = list()
		L |= B
	if(B.cid)
		var/list/L = by_cid[B.cid]
		if(!L)
			L = by_cid[B.cid] = list()
		L |= B

/datum/controller/subsystem/bans/proc/remove(datum/ban_record/B)
	records -= B.id
	var/list/L = by_ckey[B.ckey]
	if(L)
		L -= B
		if(!L.len)
			by_ckey -= B.ckey
	L = by_ip[B.ip]
	if(L)
		L -= B
		if(!L.len)
			by_ip -= B.ip
	L = by_cid[B.cid]
	if(L)
		L -= B
		if(!L.len)
			by_cid -= B.cid

/datum/controller/subsystem/bans/proc/get(id)
	id = "[id]"
	if(moved_ids[id])
		id = moved_ids[id]
	return records[id]

//Active bans with any of the three
/datum/controller/subsystem/bans/proc/matching(match_ckey, match_ip, match_cid)
	var/list/found = list()
	if(match_ckey && by_ckey[match_ckey])
		found |= by_ckey[match_ckey]
	if(match_ip && by_ip[match_ip])
		found |= by_ip[match_ip]
	if(match_cid && by_cid[match_cid])
		found |= by_cid[match_cid]
	. = list()
	for(var/datum/ban_record/B in found)
		if(B.is_active())
			. += B

//Role bans hold the key, and every key on a computer whose ID a ban has: alts on the same machine don't get the role either.
//match_cid defaults to the computer they logged in from this round, so it holds after they disconnect too.
/datum/controller/subsystem/bans/proc/role_ban_records(match_ckey, match_cid)
	match_cid = match_cid || known_cids[match_ckey]
	. = list()
	if(by_ckey[match_ckey])
		. |= by_ckey[match_ckey]
	if(match_cid && by_cid[match_cid])
		. |= by_cid[match_cid]

//roles lowercased
/datum/controller/subsystem/bans/proc/role_banned(match_ckey, list/roles, is_admin)
	for(var/datum/ban_record/B in role_ban_records(match_ckey))
		if(!B.is_active() || (is_admin && !B.applies_to_admins))
			continue
		if(lowertext(B.role) in roles)
			return TRUE
	return FALSE

//A client's role bans from here; local_only leaves out the copies of database bans, for when the database has just been asked
/datum/controller/subsystem/bans/proc/add_to_cache(list/cache, match_ckey, is_admin, local_only = FALSE, match_cid)
	for(var/datum/ban_record/B in role_ban_records(match_ckey, match_cid))
		if(!B.is_active() || (local_only && !B.is_local()) || (is_admin && !B.applies_to_admins))
			continue
		ban_cache_add(cache, B.role, B.expire_rt)

//The database's role bans on a key or its computer, into a cache. FALSE if the database couldn't be asked.
/datum/controller/subsystem/bans/proc/db_cache_rows(list/cache, match_ckey, match_cid, is_admin)
	var/datum/DBQuery/query_build_ban_cache = SSdbcore.NewQuery("SELECT role, applies_to_admins, TIMESTAMPDIFF(SECOND, NOW(), expiration_time) FROM [format_table_name("ban")] WHERE (ckey = '[sanitizeSQL(match_ckey)]'[match_cid ? " OR computerid = '[sanitizeSQL(match_cid)]'" : ""]) AND unbanned_datetime IS NULL AND (expiration_time IS NULL OR expiration_time > NOW())")
	if(!query_build_ban_cache.Execute())
		qdel(query_build_ban_cache)
		return FALSE
	while(query_build_ban_cache.NextRow())
		if(is_admin && !text2num(query_build_ban_cache.item[2]))
			continue
		var/seconds_left = query_build_ban_cache.item[3]
		ban_cache_add(cache, query_build_ban_cache.item[1], isnull(seconds_left) ? 0 : world.realtime + text2num(seconds_left) * 10)
	qdel(query_build_ban_cache)
	return TRUE

//What IsBanned() checks: the database when it answers (it's the fresh word, other servers ban there too) and the bans made
//here that it doesn't have yet; this copy alone when it doesn't. use_db: the caller's SSdbcore.Connect(), so a dead database is waited on once.
/datum/controller/subsystem/bans/proc/server_ban_details(match_ckey, match_ip, match_cid, use_db)
	var/list/found
	var/db_checked = FALSE
	if(use_db)
		found = is_banned_from_with_details(match_ckey, match_ip, match_cid, "Server")
		db_checked = !isnull(found)
	if(!found)
		found = list()
	for(var/datum/ban_record/B as anything in matching(match_ckey, match_ip, match_cid))
		if(lowertext(B.role) != "server" || (db_checked && !B.is_local()))
			continue
		found += list(B.details())
	return found

//Every ban, active or not, with all the given ones, newest first
/datum/controller/subsystem/bans/proc/search(search_key, search_admin_key, search_ip, search_cid)
	var/search_ckey = ckey(search_key)
	var/search_admin_ckey = ckey(search_admin_key)
	. = list()
	for(var/id in records)
		var/datum/ban_record/B = records[id]
		if((search_ckey && B.ckey != search_ckey) || (search_admin_ckey && B.a_ckey != search_admin_ckey) || (search_ip && B.ip != search_ip) || (search_cid && B.cid != search_cid))
			continue
		. += B
	sortTim(., GLOBAL_PROC_REF(cmp_ban_records_newest))

/proc/cmp_ban_records_newest(datum/ban_record/a, datum/ban_record/b)
	return b.bantime_rt - a.bantime_rt

//Returns "database" or "local" (kept here: the database is off or out of reach), or null if the database refused them
/datum/controller/subsystem/bans/proc/add_bans(list/new_bans)
	if(CONFIG_GET(flag/sql_enabled) && SSdbcore.Connect())
		var/list/rows = list()
		for(var/datum/ban_record/B as anything in new_bans)
			rows += list(B.sql_values())
		if(!SSdbcore.MassInsert(format_table_name("ban"), rows, warn = TRUE))
			return
		var/datum/ban_record/first = new_bans[1]
		db_sync(first.ckey, first.ip, first.cid) //back with their ids
		return "database"
	for(var/datum/ban_record/B as anything in new_bans)
		B.id = "L[next_local_id++]"
		add(B)
	save()
	return "local"

//Distinct times this admin made admin bans that are still on: role bans made together count once
/datum/controller/subsystem/bans/proc/admin_ban_times(admin_ckey, local_only = FALSE)
	. = list()
	for(var/id in records)
		var/datum/ban_record/B = records[id]
		if(B.a_ckey == admin_ckey && B.applies_to_admins && B.is_active() && (!local_only || B.is_local()))
			.[B.bantime] = TRUE

//lift() and edit() return "done", "queued" (the database is out of reach: done here, and sent when it's back), or null if refused
/datum/controller/subsystem/bans/proc/lift(id, admin_ckey, admin_key, admin_ip, admin_cid)
	var/datum/ban_record/B = get(id)
	if(B && B.is_local())
		set_unbanned(B, admin_ckey, admin_key, admin_ip, admin_cid)
		save()
		return "done"
	var/db_id = text2num(B ? B.id : id)
	if(!db_id)
		return
	. = run_or_queue(list("op" = "unban", "id" = db_id, "ckey" = admin_ckey, "ip" = admin_ip, "cid" = admin_cid, "round_id" = GLOB.round_id, "rt" = num2text(world.realtime, 12)))
	if(!.)
		return
	if(B)
		remove(B)
	save()

/datum/controller/subsystem/bans/proc/set_unbanned(datum/ban_record/B, admin_ckey, admin_key, admin_ip, admin_cid)
	B.unbanned_datetime = SQLtime()
	B.unbanned_rt = world.realtime
	B.unbanned_ckey = admin_ckey
	B.unbanned_key = admin_key
	B.unbanned_ip = admin_ip
	B.unbanned_cid = admin_cid
	B.unbanned_round_id = GLOB.round_id

//op: id, mirror, old_ckey, old_ip, old_cid, amount, unit, applies_to_admins, reason, ckey, key, ip, cid, edit_text
/datum/controller/subsystem/bans/proc/edit(list/op)
	var/datum/ban_record/target = get(op["id"])
	if(!target && !text2num(op["id"]))
		return
	. = "done"
	var/list/affected = list()
	if(target)
		affected += target
		if(op["mirror"])
			for(var/id in records)
				var/datum/ban_record/B = records[id]
				if(B != target && B.bantime == target.bantime && (!op["old_ckey"] || B.ckey == op["old_ckey"]) && (!op["old_ip"] || B.ip == op["old_ip"]) && (!op["old_cid"] || B.cid == op["old_cid"]))
					affected += B
	if(!target || !target.is_local())
		op["id"] = text2num(target ? target.id : op["id"])
		if(target)
			op["bantime"] = target.bantime
		op["op"] = "edit"
		. = run_or_queue(op)
		if(!.)
			return
	var/list/intervals = BAN_INTERVALS
	for(var/datum/ban_record/B in affected)
		remove(B)
		B.amount = op["amount"]
		B.unit = op["unit"]
		B.expire_rt = B.amount ? B.bantime_rt + B.amount * intervals[B.unit] * 10 : null
		B.applies_to_admins = op["applies_to_admins"]
		B.reason = op["reason"]
		B.ckey = op["ckey"]
		B.key = op["key"]
		B.ip = op["ip"]
		B.cid = op["cid"]
		B.edits = "[B.edits][op["edit_text"]]"
		add(B)
	save()

//Runs a change to a database ban, or keeps it for when the database is back
/datum/controller/subsystem/bans/proc/run_or_queue(list/op)
	if(CONFIG_GET(flag/sql_enabled) && SSdbcore.Connect())
		var/datum/DBQuery/query_ban_change = SSdbcore.NewQuery(op_sql(op))
		if(query_ban_change.warn_execute())
			. = "done"
		qdel(query_ban_change)
		return
	queued_ops += list(op)
	return "queued"

//Built when it's run, not when it's made: sanitizeSQL() needs the connection
/datum/controller/subsystem/bans/proc/op_sql(list/op)
	var/ban_table = format_table_name("ban")
	switch(op["op"])
		if("unban")
			var/age = max(0, round((world.realtime - text2num(op["rt"])) / 10))
			return "UPDATE [ban_table] SET unbanned_datetime = [age ? "(NOW() - INTERVAL [age] SECOND)" : "NOW()"], unbanned_ckey = '[sanitizeSQL(op["ckey"])]', unbanned_ip = INET_ATON('[sanitizeSQL(op["ip"])]'), unbanned_computerid = '[sanitizeSQL(op["cid"])]', unbanned_round_id = '[text2num(op["round_id"]) || 0]' WHERE id = [text2num(op["id"])] AND unbanned_datetime IS NULL"
		if("edit")
			var/expiration_sql = "NULL"
			if(op["amount"] && (op["unit"] in BAN_INTERVALS))
				expiration_sql = "bantime + INTERVAL [num2text(op["amount"], 12)] [op["unit"]]"
			var/where = "id = [text2num(op["id"])]"
			if(op["mirror"] && op["bantime"])
				var/list/wherelist = list("bantime = '[sanitizeSQL(op["bantime"])]'")
				if(op["old_ckey"])
					wherelist += "ckey = '[sanitizeSQL(op["old_ckey"])]'"
				if(op["old_ip"])
					wherelist += "ip = INET_ATON('[sanitizeSQL(op["old_ip"])]')"
				if(op["old_cid"])
					wherelist += "computerid = '[sanitizeSQL(op["old_cid"])]'"
				where = wherelist.Join(" AND ")
			return "UPDATE [ban_table] SET expiration_time = [expiration_sql], applies_to_admins = [op["applies_to_admins"] ? 1 : 0], reason = '[sanitizeSQL(op["reason"])]', ckey = [op["ckey"] ? "'[sanitizeSQL(op["ckey"])]'" : "NULL"], ip = [op["ip"] ? "INET_ATON('[sanitizeSQL(op["ip"])]')" : "NULL"], computerid = [op["cid"] ? "'[sanitizeSQL(op["cid"])]'" : "NULL"], edits = CONCAT(IFNULL(edits,''),'[sanitizeSQL(op["edit_text"])]') WHERE [where]"

//The minute's check: send what waited, then refresh the copy
/datum/controller/subsystem/bans/proc/db_update()
	if(db_busy || !CONFIG_GET(flag/sql_enabled))
		return
	db_busy = TRUE //before Connect(), which can sleep: set after, two at once both sent the waiting changes
	if(SSdbcore.Connect() && db_flush())
		db_sync()
	db_busy = FALSE

//FALSE if the connection went
/datum/controller/subsystem/bans/proc/db_flush()
	var/sent = 0
	for(var/id in records.Copy())
		var/datum/ban_record/B = records[id]
		if(!B?.is_local() || refused[id])
			continue
		if(!SSdbcore.MassInsert(format_table_name("ban"), list(B.sql_values()), async = FALSE))
			if(!SSdbcore.IsConnected())
				return FALSE
			//the database answered and said no; the ban still holds here, and it's tried again next round
			refused[id] = TRUE
			log_sql("Bans: the database refused ban [B.id] ([B.role] for [B.ckey || "[B.ip]-[B.cid]"]), keeping it on this server")
			message_admins("The database refused ban [B.id] ([B.role] for [B.ckey || "[B.ip]-[B.cid]"]), made while it was out of reach. It's still enforced on this server; the server log has why.")
			continue
		var/datum/DBQuery/query_ban_id = SSdbcore.NewQuery("SELECT LAST_INSERT_ID()")
		var/new_id
		if(query_ban_id.Execute(async = FALSE) && query_ban_id.NextRow(async = FALSE))
			new_id = query_ban_id.item[1]
		qdel(query_ban_id)
		remove(B)
		if(text2num(new_id))
			moved_ids[B.id] = new_id
			B.id = new_id
			add(B)
		sent++
	for(var/list/op as anything in queued_ops.Copy())
		var/datum/DBQuery/query_ban_change = SSdbcore.NewQuery(op_sql(op))
		var/ok = query_ban_change.Execute()
		qdel(query_ban_change)
		if(!ok)
			if(!SSdbcore.IsConnected())
				return FALSE
			log_sql("Bans: the database refused a waiting [op["op"]] of ban [op["id"]], dropped it")
		queued_ops -= list(op) //by reference: the list can change while the query sleeps
		sent++
	if(sent)
		log_sql("Bans: sent [sent] ban change\s made while the database was out of reach")
		message_admins("[sent] ban change\s made while the database was out of reach have been saved to it.")
		next_sync = 0
	save()
	return TRUE

//Refresh the copy of the database's active bans: all of them, or just those with one of a ckey, ip and cid
/datum/controller/subsystem/bans/proc/db_sync(sync_ckey, sync_ip, sync_cid)
	var/list/where = list()
	if(sync_ckey)
		where += "ckey = '[sanitizeSQL(sync_ckey)]'"
	if(sync_ip)
		where += "ip = INET_ATON('[sanitizeSQL(sync_ip)]')"
	if(sync_cid)
		where += "computerid = '[sanitizeSQL(sync_cid)]'"
	var/ban_table = format_table_name("ban")
	var/player_table = format_table_name("player")
	var/datum/DBQuery/query_ban_sync = SSdbcore.NewQuery("SELECT id, role, ckey, IFNULL((SELECT byond_key FROM [player_table] WHERE [player_table].ckey = [ban_table].ckey), ckey), INET_NTOA(ip), computerid, TIMESTAMPDIFF(SECOND, bantime, NOW()), TIMESTAMPDIFF(SECOND, NOW(), expiration_time), applies_to_admins, reason, a_ckey, IFNULL((SELECT byond_key FROM [player_table] WHERE [player_table].ckey = [ban_table].a_ckey), a_ckey), round_id, bantime, edits FROM [ban_table] WHERE unbanned_datetime IS NULL AND (expiration_time IS NULL OR expiration_time > NOW())[where.len ? " AND ([where.Join(" OR ")])" : ""]")
	if(!query_ban_sync.Execute())
		qdel(query_ban_sync)
		return FALSE
	var/list/seen = list()
	while(query_ban_sync.NextRow())
		var/list/row = query_ban_sync.item
		var/id = row[1]
		seen[id] = TRUE
		var/datum/ban_record/B = records[id]
		if(B)
			remove(B)
		else
			B = new
			B.id = id
		B.role = row[2]
		B.ckey = row[3]
		B.key = row[4]
		B.ip = row[5]
		B.cid = row[6]
		B.bantime_rt = world.realtime - text2num(row[7]) * 10
		B.expire_rt = isnull(row[8]) ? null : world.realtime + text2num(row[8]) * 10
		B.amount = null //a database edit counts from the database's own bantime
		B.unit = null
		B.applies_to_admins = text2num(row[9])
		B.reason = row[10]
		B.a_ckey = row[11]
		B.a_key = row[12]
		B.round_id = row[13]
		B.bantime = row[14]
		B.edits = row[15]
		add(B)
	qdel(query_ban_sync)
	//database bans not in the answer have ended or been lifted
	for(var/id in records.Copy())
		var/datum/ban_record/B = records[id]
		if(B.is_local() || seen[id])
			continue
		if(where.len && !B.matches(sync_ckey, sync_ip, sync_cid))
			continue
		remove(B)
	if(!where.len)
		next_sync = world.time + BAN_SYNC_INTERVAL
	save()
	return TRUE

//role = expire_rt, 0 for permanent: the longest of any two for the same role stays
/proc/ban_cache_add(list/cache, role, expire_rt)
	role = lowertext(role)
	if(role in cache)
		var/existing = cache[role]
		if(!existing || (expire_rt && expire_rt <= existing))
			return
	cache[role] = expire_rt || 0
