//Ban system self-test, in the real engine with nobody connected: bans with no database, and with one that's down.
//Only in the check's own build: tools/ban_check/run_ban_check.sh adds this file to a copy of the .dme. Results in data/ban_check/results.txt.

/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	if("ban-selftest" in world.params)
		sleep_offline_after_initializations = FALSE //nobody connects to this, so the world has to keep ticking
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(run_ban_selftest))
	return ..()

/proc/ban_check(list/out, name, ok, detail)
	out += "[ok ? "PASS" : "FAIL"] [name][detail ? " ([detail])" : ""]"

/proc/ban_check_record(role, ckey, key, ip, cid)
	var/datum/ban_record/B = new
	B.role = role
	B.ckey = ckey
	B.key = key
	B.ip = ip
	B.cid = cid
	B.bantime = SQLtime()
	B.bantime_rt = world.realtime
	B.reason = "ban check"
	B.a_ckey = "bancheckadmin"
	B.a_key = "BanCheckAdmin"
	B.round_id = GLOB.round_id
	return B

/proc/ban_check_kept_out(key, ip, cid)
	var/list/result = world.IsBanned(key, ip, cid, "world")
	return islist(result) && result["reason"] == "Banned"

//The first column of the first row, or the error
/proc/ban_check_sql(sql)
	var/datum/DBQuery/query_ban_check = SSdbcore.NewQuery(sql)
	if(!query_ban_check.Execute())
		. = "error: [query_ban_check.ErrorMsg()]"
	else if(query_ban_check.NextRow())
		. = query_ban_check.item[1]
	qdel(query_ban_check)

//With a real database (run_ban_check.sh with DB_PORT set): bans in it, its clock, edits and unbans, and it going away and coming back
/proc/run_ban_selftest_db(list/out, prefix, db_port)
	var/ban_table = format_table_name("ban")
	CONFIG_SET(flag/sql_enabled, TRUE)
	CONFIG_SET(number/port, db_port)
	SSdbcore.failed_connections = 0
	SSdbcore.failed_connection_timeout = 0
	ban_check(out, "database up: connects", SSdbcore.Connect(), SSdbcore.ErrorMsg())
	if(!SSdbcore.IsConnected())
		return
	ban_check(out, "database up: in strict mode", findtext(ban_check_sql("SELECT @@SESSION.sql_mode"), "STRICT_TRANS_TABLES"))
	UNTIL(!SSbans.db_busy) //the minute's check may be sending the bans from above
	SSbans.ledger_path = "[prefix]bans.json"
	SSbans.primary_ok = FALSE
	SSbans.next_local_id = 1
	SSbans.load()
	sleep(1)
	UNTIL(!SSbans.db_busy)

	var/datum/ban_record/server_ban = ban_check_record("Server", "dbserverban", "DB Server Ban", "10.8.8.8", "8888")
	ban_check(out, "database up: a server ban goes to the database", SSbans.add_bans(list(server_ban)) == "database")
	var/list/found = SSbans.search("dbserverban")
	var/datum/ban_record/server_copy = length(found) ? found[1] : null
	ban_check(out, "database up: and comes back into the copy with its id", server_copy && text2num(server_copy.id), server_copy?.id)
	ban_check(out, "database up: the row is there", ban_check_sql("SELECT COUNT(*) FROM [ban_table] WHERE ckey = 'dbserverban' AND role = 'Server' AND unbanned_datetime IS NULL") == "1")
	ban_check(out, "database up: IsBanned keeps out the key", ban_check_kept_out("DB Server Ban", "10.9.9.1", "1"))
	ban_check(out, "database up: and another key on its IP", ban_check_kept_out("DB Alt", "10.8.8.8", "2"))

	var/datum/ban_record/host_ban = ban_check_record("Server", "hostbanned", "Host Banned", null, "9999")
	host_ban.a_ip = null //the host connects with no address
	var/list/many = list()
	for(var/i in 1 to 300)
		many += "Player Number [i]"
	host_ban.who = jointext(many, ", ") //a busy server
	ban_check(out, "database up: the host can ban, with a busy server online", SSbans.add_bans(list(host_ban)) == "database", "who is [length(host_ban.who)] characters")

	var/datum/ban_record/role_ban = ban_check_record("Chef", "dbroleban", "DB Role Ban", null, "7777")
	role_ban.amount = 2
	role_ban.unit = "DAY"
	role_ban.expire_rt = world.realtime + 2 * 864000
	ban_check(out, "database up: a temporary role ban goes to the database", SSbans.add_bans(list(role_ban)) == "database")
	ban_check(out, "database up: two days, on the database's clock", ban_check_sql("SELECT TIMESTAMPDIFF(HOUR, bantime, expiration_time) FROM [ban_table] WHERE ckey = 'dbroleban'") == "48")
	var/list/cid_cache = list()
	ban_check(out, "database up: the login query finds role bans on the computer", SSbans.db_cache_rows(cid_cache, "anotheraccount", "7777", FALSE) && ("chef" in cid_cache))
	ban_check(out, "database up: an offline check finds it in the copy", is_banned_from("dbroleban", "Chef"))
	found = SSbans.search("dbroleban")
	var/datum/ban_record/role_copy = length(found) ? found[1] : null
	var/list/op = list("id" = role_copy?.id, "mirror" = FALSE, "amount" = 3, "unit" = "HOUR", "applies_to_admins" = FALSE, "reason" = "edited in the database", "ckey" = "dbroleban", "key" = "DB Role Ban", "ip" = null, "cid" = "7777", "edit_text" = "ban check db edit<hr>")
	ban_check(out, "database up: edit", SSbans.edit(op) == "done")
	ban_check(out, "database up: the edited length counts from the ban time", ban_check_sql("SELECT TIMESTAMPDIFF(MINUTE, bantime, expiration_time) FROM [ban_table] WHERE ckey = 'dbroleban'") == "180")
	ban_check(out, "database up: the edit's reason and log are saved", ban_check_sql("SELECT COUNT(*) FROM [ban_table] WHERE ckey = 'dbroleban' AND reason = 'edited in the database' AND edits LIKE '%ban check db edit%'") == "1")

	var/datum/ban_record/mirror_a = ban_check_record("Chef", "dbmirror", "DB Mirror", "10.5.4.3", null)
	var/datum/ban_record/mirror_b = ban_check_record("Clown", "dbmirror", "DB Mirror", "10.5.4.3", null)
	SSbans.add_bans(list(mirror_a, mirror_b))
	found = SSbans.search("dbmirror")
	var/datum/ban_record/mirror_copy = length(found) ? found[1] : null
	op = list("id" = mirror_copy?.id, "mirror" = TRUE, "old_ckey" = "dbmirror", "old_ip" = "10.5.4.3", "amount" = null, "unit" = null, "applies_to_admins" = FALSE, "reason" = "mirrored", "ckey" = "dbmirror", "key" = "DB Mirror", "ip" = "10.5.4.3", "cid" = null, "edit_text" = "mirror<hr>")
	ban_check(out, "database up: a mirrored edit changes both bans made together", SSbans.edit(op) == "done" && ban_check_sql("SELECT COUNT(*) FROM [ban_table] WHERE ckey = 'dbmirror' AND reason = 'mirrored'") == "2")

	ban_check(out, "database up: unban", SSbans.lift(server_copy?.id, "bancheckadmin", "BanCheckAdmin", "127.0.0.1", "1") == "done")
	ban_check(out, "database up: the row is lifted, by whom", ban_check_sql("SELECT COUNT(*) FROM [ban_table] WHERE id = [text2num(server_copy?.id)] AND unbanned_datetime IS NOT NULL AND unbanned_ckey = 'bancheckadmin'") == "1")
	ban_check(out, "database up: the unbanned key gets in", !world.IsBanned("DB Server Ban", "10.9.9.1", "1", "world"))

	//it goes away, and comes back
	SSdbcore.Disconnect()
	CONFIG_SET(number/port, 9)
	var/datum/ban_record/while_down = ban_check_record("Server", "whiledown", "While Down", "10.6.6.6", "6666")
	while_down.bantime_rt = world.realtime - 6000 //made ten minutes before the database is back
	ban_check(out, "database gone: a new ban is kept here", SSbans.add_bans(list(while_down)) == "local", while_down.id)
	var/local_id = while_down.id
	ban_check(out, "database gone: lifting one of its bans waits", SSbans.lift(role_copy?.id, "bancheckadmin", "BanCheckAdmin", "127.0.0.1", "1") == "queued")
	CONFIG_SET(number/port, db_port)
	SSdbcore.failed_connections = 0
	SSdbcore.failed_connection_timeout = 0
	UNTIL(!SSbans.db_busy) //the minute's check may be at it already
	SSbans.db_update()
	UNTIL(!SSbans.db_busy)
	ban_check(out, "database back: nothing is left waiting", !length(SSbans.queued_ops) && !SSbans.has_unsent(), "[length(SSbans.queued_ops)] queued")
	var/minutes_old = ban_check_sql("SELECT TIMESTAMPDIFF(MINUTE, bantime, NOW()) FROM [ban_table] WHERE ckey = 'whiledown'")
	ban_check(out, "database back: the ban made meanwhile is in it, timed when it was made", minutes_old in list("9", "10", "11"), "[minutes_old] minutes old")
	ban_check(out, "database back: it holds", ban_check_kept_out("While Down", "10.6.6.6", "6666"))
	ban_check(out, "database back: its old local id still finds it", SSbans.get(local_id) == while_down && text2num(while_down.id), "[local_id] is now [while_down.id]")
	ban_check(out, "database back: the waiting unban was applied", ban_check_sql("SELECT COUNT(*) FROM [ban_table] WHERE ckey = 'dbroleban' AND unbanned_datetime IS NOT NULL") == "1")

	//the earlier SQL fixes, against the real thing
	var/datum/ban_record/full_row = ban_check_record("Chef", "nullcheck1", "Null Check", null, null)
	var/datum/ban_record/short_row = ban_check_record("Chef", "nullcheck2", "Null Check", null, null)
	var/list/row_a = full_row.sql_values()
	var/list/row_b = short_row.sql_values()
	row_b -= "edits"
	row_b -= "computerid"
	ban_check(out, "MassInsert writes a missing column as NULL", SSdbcore.MassInsert(ban_table, list(row_a, row_b)) && ban_check_sql("SELECT COUNT(*) FROM [ban_table] WHERE ckey = 'nullcheck2' AND computerid IS NULL") == "1")
	create_message("note", "notetarget", "CID-Error", "ban check system note", null, null, 0, 0, null, 0, 0)
	ban_check(out, "a system note (severity 0, no usr) is saved", ban_check_sql("SELECT COUNT(*) FROM [format_table_name("messages")] WHERE targetckey = 'notetarget' AND severity IS NULL") == "1")
	SSstickyban.import_raw_stickyban_to_db("stickycheck", list("IP" = "1.2.3.4", "message" = "ban check", "admin" = "bancheckadmin"))
	ban_check(out, "a legacy stickyban's IP goes in whole", ban_check_sql("SELECT INET_NTOA(matched_ip) FROM [format_table_name("stickyban_matched_ip")] WHERE stickyban = 'stickycheck'") == "1.2.3.4")
	var/list/two_roles = list()
	var/datum/ban_record/offline_roles = ban_check_record("Captain", "offlinelist", "Offline List", null, null)
	SSbans.add_bans(list(offline_roles))
	two_roles = is_banned_from_with_details("offlinelist", null, null, "Captain")
	ban_check(out, "the database's ban details query works", length(two_roles) == 1)
	var/datum/DBQuery/query_kill = SSdbcore.NewQuery("KILL CONNECTION_ID()")
	query_kill.Execute()
	qdel(query_kill)
	ban_check(out, "a query after its connection was killed still runs", ban_check_sql("SELECT 1") == "1")

/proc/run_ban_selftest()
	UNTIL(Master.current_runlevel)
	var/list/out = list()
	var/dir = "data/ban_check/"
	fdel(dir)
	CONFIG_SET(flag/sql_enabled, FALSE)
	SSbans.ledger_path = "[dir]bans.json"
	SSbans.last_saved = null
	SSbans.primary_ok = FALSE
	SSbans.queued_ops = list()
	SSbans.moved_ids = list()
	SSbans.next_local_id = 1
	SSbans.load()
	ban_check(out, "starts empty", !SSbans.records.len, "[SSbans.records.len] records")

	//server bans: the key, and anyone else on its IP or computer
	var/datum/ban_record/S = ban_check_record("Server", "testbanned", "TestBanned", "10.1.2.3", "123456789")
	ban_check(out, "a server ban is kept on this server with no database", SSbans.add_bans(list(S)) == "local", S.id)
	ban_check(out, "IsBanned keeps out the key", ban_check_kept_out("TestBanned", "10.9.9.9", "999"))
	ban_check(out, "IsBanned keeps out another key on its IP", ban_check_kept_out("Alt Account", "10.1.2.3", "555"))
	ban_check(out, "IsBanned keeps out another key on its computer", ban_check_kept_out("Alt Two", "10.5.5.5", "123456789"))
	ban_check(out, "IsBanned lets in someone else", !world.IsBanned("Innocent", "10.7.7.7", "777", "world"))
	ban_check(out, "the file is written", fexists(SSbans.ledger_path))

	//role bans, made together like the panel makes them
	var/datum/ban_record/R1 = ban_check_record("Lavaland", "rolebanned", "Role Banned", "10.2.2.2", "222")
	var/datum/ban_record/R2 = ban_check_record("Captain", "rolebanned", "Role Banned", "10.2.2.2", "222")
	R2.bantime = R1.bantime
	R2.bantime_rt = R1.bantime_rt
	SSbans.add_bans(list(R1, R2))
	ban_check(out, "a role ban holds given a key and the spawners' lowercase role", is_banned_from("Role Banned", "lavaland"))
	ban_check(out, "a role ban holds in a list of roles", is_banned_from("rolebanned", list("Chef", ROLE_LAVALAND)))
	ban_check(out, "a role ban leaves other roles", !is_banned_from("rolebanned", "Chef"))
	ban_check(out, "a role ban isn't a server ban", !world.IsBanned("Role Banned", "10.2.2.2", "222", "world"))
	ban_check(out, "nobody else is banned", !is_banned_from("innocent", ROLE_LAVALAND) && !is_banned_from(null, ROLE_LAVALAND))
	//role bans hold every key on the banned computer
	SSbans.known_cids["altonsamepc"] = "222" //as build_ban_cache() notes it at login
	ban_check(out, "a role ban holds another key that logged in from its computer", is_banned_from("altonsamepc", "Captain"))
	var/list/alt_cache = list()
	SSbans.add_to_cache(alt_cache, "altonlogin", FALSE, FALSE, "222")
	ban_check(out, "a client's cache has the role bans on its computer", ("captain" in alt_cache) && ("lavaland" in alt_cache))
	ban_check(out, "a key from another computer isn't held", !is_banned_from("altelsewhere", "Captain"))

	//lengths
	var/datum/ban_record/ended = ban_check_record("Chef", "endedban", "Ended Ban", null, null)
	ended.amount = 1
	ended.unit = "MINUTE"
	ended.expire_rt = world.realtime - 600
	var/datum/ban_record/running = ban_check_record("Chef", "tempban", "Temp Ban", null, null)
	running.amount = 1
	running.unit = "DAY"
	running.expire_rt = world.realtime + 864000
	SSbans.add_bans(list(ended))
	SSbans.add_bans(list(running))
	ban_check(out, "an ended temporary ban doesn't hold", !is_banned_from("endedban", "Chef"))
	ban_check(out, "a running temporary ban holds", is_banned_from("tempban", "Chef"))

	//admins are only held by bans that say they apply to admins
	var/datum/admin_rank/test_rank = new("Ban Check Rank", R_EVERYTHING, 0, R_EVERYTHING)
	var/datum/admins/test_admin = new(test_rank, "bancheckadminplayer")
	var/datum/ban_record/plain = ban_check_record("Chef", "bancheckadminplayer", "BanCheckAdminPlayer", null, null)
	var/datum/ban_record/for_admins = ban_check_record("Clown", "bancheckadminplayer", "BanCheckAdminPlayer", null, null)
	for_admins.applies_to_admins = TRUE
	SSbans.add_bans(list(plain))
	SSbans.add_bans(list(for_admins))
	ban_check(out, "an admin isn't held by a plain ban", !is_banned_from("bancheckadminplayer", "Chef"))
	ban_check(out, "an admin is held by an admin ban", is_banned_from("bancheckadminplayer", "Clown"))
	GLOB.admin_datums -= "bancheckadminplayer"
	GLOB.deadmins -= "bancheckadminplayer"
	qdel(test_admin)

	//a client's cache keeps the longest ban for a role
	var/list/cache = list()
	ban_cache_add(cache, "Chef", world.realtime + 100)
	ban_cache_add(cache, "chef", 0)
	ban_cache_add(cache, "Chef", world.realtime + 999999)
	ban_check(out, "the cache keeps a permanent ban over temporary ones", ("chef" in cache) && cache["chef"] == 0)

	//what the bots and set_species do: no query, no sleep, quick
	var/started_time = world.time
	var/started = world.timeofday
	for(var/i in 1 to 20000)
		is_banned_from("botsomeone[i % 40]", list(CATBAN, CLUWNEBAN, CRABBAN))
	ban_check(out, "20000 checks for players who aren't connected never sleep", world.time == started_time, "[(world.timeofday - started) * 100] ms")

	//lifting a ban
	ban_check(out, "unban", SSbans.lift(S.id, "bancheckadmin", "BanCheckAdmin", "127.0.0.1", "1") == "done")
	ban_check(out, "the unbanned key gets in", !world.IsBanned("TestBanned", "10.9.9.9", "999", "world"))
	ban_check(out, "the lifted ban stays as history", S.unbanned_datetime && length(SSbans.search("TestBanned")) == 1)

	//an edit, mirrored to the ban made with it
	var/list/op = list("id" = R1.id, "mirror" = TRUE, "old_ckey" = "rolebanned", "old_ip" = "10.2.2.2", "old_cid" = "222", "amount" = 2, "unit" = "HOUR", "applies_to_admins" = FALSE, "reason" = "edited", "ckey" = "rolebanned2", "key" = "Role Banned 2", "ip" = "10.2.2.2", "cid" = "222", "edit_text" = "ban check edit<hr>")
	ban_check(out, "edit", SSbans.edit(op) == "done")
	ban_check(out, "the edit frees the old key", !is_banned_from("rolebanned", list("Lavaland", "Captain")))
	ban_check(out, "the edit is mirrored to the ban made with it", is_banned_from("rolebanned2", "Lavaland") && is_banned_from("rolebanned2", "Captain"))
	ban_check(out, "the edited length counts from the ban time", R2.expire_rt && abs(R2.expire_rt - (R2.bantime_rt + 72000)) < 1100, "[R2.expire_rt - R2.bantime_rt] ds")
	ban_check(out, "the edit is logged on the ban", findtext(R2.edits, "ban check edit"))

	//a restart
	var/before = SSbans.records.len
	var/running_expiry = running.expire_rt
	SSbans.load()
	ban_check(out, "after a restart every ban is back", SSbans.records.len == before, "[SSbans.records.len] of [before]")
	ban_check(out, "after a restart role bans hold", is_banned_from("rolebanned2", "Captain"))
	ban_check(out, "after a restart the unban holds", !world.IsBanned("TestBanned", "10.9.9.9", "999", "world"))
	var/datum/ban_record/reloaded = SSbans.get(running.id)
	ban_check(out, "after a restart a ban ends when it did", reloaded?.expire_rt == running_expiry, "[reloaded?.expire_rt] vs [running_expiry]")
	var/datum/ban_record/later = ban_check_record("Chef", "laterban", "Later Ban", null, null)
	SSbans.add_bans(list(later))
	ban_check(out, "after a restart new ids don't reuse old ones", !(later.id in list(S.id, R1.id, R2.id, ended.id, running.id, plain.id, for_admins.id)), later.id)

	//a broken file: the copy before it is loaded
	var/saved = SSbans.records.len
	fdel(SSbans.ledger_path)
	text2file("{not json", SSbans.ledger_path)
	SSbans.load()
	ban_check(out, "a broken file falls back to the backup", SSbans.records.len == saved - 1, "[SSbans.records.len] records, [saved] before the last change")
	ban_check(out, "with the backup loaded, bans still hold", is_banned_from("rolebanned2", "Captain"))
	SSbans.save()
	ban_check(out, "saving after that leaves the backup readable", SSbans.read_ledger("[SSbans.ledger_path].bak"))

	run_ban_selftest_window(out, dir)

	//the database configured but down: port 9, where nothing listens, so this never reaches a real database
	var/db_port = CONFIG_GET(number/port)
	SSdbcore.Disconnect()
	CONFIG_SET(number/port, 9)
	CONFIG_SET(flag/sql_enabled, TRUE)
	var/datum/ban_record/copied = ban_check_record("Server", "dbbanned", "DB Banned", "10.3.3.3", "333")
	copied.id = "900" //a copy of one of the database's bans
	SSbans.add(copied)
	ban_check(out, "database down: its banned players are still kept out", ban_check_kept_out("DB Banned", "10.3.3.3", "333"))
	ban_check(out, "database down: BSQL itself answers, with the refused connection", findtext(SSdbcore.ErrorMsg(), "connect"), SSdbcore.ErrorMsg())
	var/datum/ban_record/made_meanwhile = ban_check_record("Server", "pendingban", "Pending Ban", "10.4.4.4", "444")
	ban_check(out, "database down: a new ban is kept here", SSbans.add_bans(list(made_meanwhile)) == "local", made_meanwhile.id)
	ban_check(out, "database down: and enforced", ban_check_kept_out("Pending Ban", "10.4.4.4", "444"))
	ban_check(out, "database down: and waits to be sent", SSbans.has_unsent())
	ban_check(out, "database down: lifting a database ban waits", SSbans.lift("900", "bancheckadmin", "BanCheckAdmin", "127.0.0.1", "1") == "queued" && length(SSbans.queued_ops) == 1)
	ban_check(out, "database down: and the player gets in meanwhile", !world.IsBanned("DB Banned", "10.3.3.3", "333", "world"))
	SSbans.load()
	ban_check(out, "database down: the waiting unban survives a restart", length(SSbans.queued_ops) == 1 && SSbans.queued_ops[1]["op"] == "unban")
	ban_check(out, "database down: a note is kept here", SSnotes.add("note", "pendingnote", "Pending Note", "bancheckadmin", "BanCheckAdmin", "made while it was down", FALSE, null, "minor") == "local")
	ban_check(out, "database down: a note made here can still be changed", SSnotes.change(SSnotes.records[SSnotes.records.len], list("severity" = "high")))
	ban_check(out, "database down: one already in the database waits for it, and says so", !SSnotes.change("900", list("severity" = "high")))
	ban_check(out, "database down: notes made here wait to be sent", SSnotes.has_unsent())
	CONFIG_SET(flag/sql_enabled, FALSE)
	CONFIG_SET(number/port, db_port)

	if(world.params["ban-selftest"] == "db")
		run_ban_selftest_db(out, "[dir]db_", db_port)
		run_ban_selftest_window_db(out, "[dir]db_", db_port)

	var/passed = 0
	for(var/line in out)
		if(copytext(line, 1, 5) == "PASS")
			passed++
	out += "[passed] of [out.len] passed"
	text2file(jointext(out, "\n"), "[dir]results.txt")
	shutdown()
