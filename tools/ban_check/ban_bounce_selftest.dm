//The database really going away and coming back under a running server: MariaDB stopped and started while the test runs
//(run_ban_check.sh with BOUNCE=1 does it when asked, through tools/db_setup), and what the pools, bans and notes do meanwhile.
//Only in the check's own build, and only with ban-bounce in the params (after the ban-selftest=db part).
//	errors:    which driver errors are a lost connection (is_connection_error()), real ones from this machine and others'
//	pools:     many queries at once share the two pools; a read timeout isn't taken for a lost database, and holds no longer
//	killed:    a connection killed under a running SELECT, the database still up: the SELECT is run again
//	writes:    a connection killed under a ban, note, unban or flush INSERT/UPDATE (held in a slow trigger meanwhile): kept here or
//	           queued, never "refused", and sent once; one whose INSERT went in after all isn't sent twice
//	restarted: MariaDB restarted with nothing running, then the first thing after is a ban, a note, an unban or ten SELECTs
//	crashed:   MariaDB killed hard under a SELECT (a reset connection, os error 10054): taken for a lost database
//	stopped:   MariaDB stopped under a SELECT, then down for a while with the server busy: things wait here, connects only on
//	           the backoff, then all goes in
//	sending:   an unban, edit or note change asked for while what it changes is on its way to the database (db_sending)

#define BAN_BOUNCE_DIR "data/ban_check/bounce/"
#define BAN_BOUNCE_CONNECTIONS "SELECT VARIABLE_VALUE FROM information_schema.GLOBAL_STATUS WHERE VARIABLE_NAME = 'CONNECTIONS'"

//Run beside the write: kills the connection waiting in the slow trigger once it shows up (five seconds at most; PROCESSLIST
//shows the trigger's statement then, not the write's), then drops the trigger. The connection's id goes in killed, or 0.
/proc/ban_bounce_kill_when(list/killed)
	var/give_up = world.time + 5 SECONDS
	var/victim
	while(!victim && world.time < give_up)
		victim = text2num(ban_bounce_sql("SELECT ID FROM information_schema.PROCESSLIST WHERE INFO = 'DO SLEEP(3)' AND ID <> CONNECTION_ID() LIMIT 1"))
		if(!victim)
			sleep(1)
	if(victim)
		ban_bounce_sql("KILL CONNECTION [victim]")
	sleep(10) //the victim's Execute() swaps the pool meanwhile
	for(var/try_drop in 1 to 3)
		if(!ban_bounce_failed(ban_bounce_sql("DROP TRIGGER IF EXISTS bancheck_slow")))
			break
		sleep(5)
	killed += victim || 0

//The killer's victim, once it's done (ten seconds at most)
/proc/ban_bounce_killed(list/killed)
	var/give_up = world.time + 10 SECONDS
	UNTIL(length(killed) || world.time > give_up)
	return length(killed) ? killed[1] : 0

//The next INSERT or UPDATE (kind) on table waits three seconds in a trigger, and its connection is killed meanwhile. (A table
//lock can't hold it: rust_g's pool resets a connection as it takes it back, which lets go of its locks.)
/proc/ban_bounce_kill_next(table, kind, list/killed)
	ban_bounce_sql("CREATE TRIGGER bancheck_slow BEFORE [kind] ON [table] FOR EACH ROW DO SLEEP(3)")
	INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(ban_bounce_kill_when), killed)

//A query a second, as the server would run them, until one answers (three minutes at most): the seconds it took, or null
/proc/ban_bounce_wait_back()
	var/from = world.time
	var/give_up = world.time + 3 MINUTES
	while(ban_bounce_sql("SELECT 1") != "1")
		if(world.time > give_up)
			return
		sleep(10)
	return (world.time - from) / 10

//is_connection_error() on errors as rust_g gives them: the first ones seen on this machine (Windows), the rest as other
//systems give them or as nothing here can make happen
/proc/run_ban_selftest_errors(list/out)
	var/list/cases = list(
		"DriverError { Could not connect to address `127.0.0.1:3307': No connection could be made because the target machine actively refused it. (os error 10061) }" = TRUE,
		"IoError { server disconnected }" = TRUE,
		"CodecError { IO error: `An existing connection was forcibly closed by the remote host. (os error 10054)' }" = TRUE,
		"CodecError { IO error: `A connection attempt failed because the connected party did not properly respond after a period of time, or established connection failed because connected host has failed to respond. (os error 10060)' }" = FALSE,
		"MySqlError { ERROR 1927 (70100): Connection was killed }" = FALSE,
		"MySqlError { ERROR 1064 (42000): You have an error in your SQL syntax; check the manual that corresponds to your MariaDB server version for the right syntax to use near 'FROM' at line 1 }" = FALSE,
		"offline" = TRUE,
		"rust_g: JOB_ERROR" = FALSE,
		"CodecError { IO error: `An established connection was aborted by the software in your host machine. (os error 10053)' }" = TRUE,
		"DriverError { Could not connect to address `10.255.255.1:3306': A connection attempt failed because the connected party did not properly respond after a period of time, or established connection failed because connected host has failed to respond. (os error 10060) }" = TRUE,
		"IoError { An existing connection was forcibly closed by the remote host. (os error 10054) }" = TRUE,
		"CodecError { IO error: `Broken pipe (os error 32)' }" = TRUE,
		"CodecError { IO error: `Connection reset by peer (os error 104)' }" = TRUE,
		"CodecError { IO error: `Connection refused (os error 111)' }" = TRUE,
		"CodecError { IO error: `Connection timed out (os error 110)' }" = TRUE, //Linux: TCP gave up on a peer that's gone (its read timeout is os error 11)
		"CodecError { IO error: `Resource temporarily unavailable (os error 11)' }" = FALSE,
		"CodecError { IO error: `A non-blocking socket operation could not be completed immediately. (os error 10035)' }" = FALSE)
	var/datum/DBQuery/query_errors = SSdbcore.NewQuery("SELECT 1")
	var/list/wrong = list()
	for(var/error in cases)
		if(!!query_errors.is_connection_error(error) != cases[error])
			wrong += "[cases[error] ? "lost" : "not lost"]: [copytext(error, 1, 90)]"
	qdel(query_errors)
	ban_check(out, "errors: [length(cases)] driver errors, each taken for a lost connection or not as it should be", !length(wrong), jointext(wrong, "; "))

//Asks run_ban_check.sh to stop or start MariaDB, and waits for it (two minutes at most). TRUE if it did.
/proc/ban_bounce_db(action)
	var/static/asked = 0
	var/base = "[BAN_BOUNCE_DIR][++asked]_[action]"
	text2file(action, "[base].req")
	var/give_up = world.time + 2 MINUTES
	UNTIL(fexists("[base].done") || world.time > give_up)
	return fexists("[base].done") && findtext(file2text("[base].done"), "ok")

/proc/ban_bounce_restart(list/out, name)
	. = ban_bounce_db("stop") && ban_bounce_db("start")
	if(!.)
		ban_check(out, "restarted ([name]): run_ban_check.sh stopped and started MariaDB", FALSE, "see [BAN_BOUNCE_DIR]last_db_setup.txt")

//The first column of the first row ("" for no rows), or "error: ..."
/proc/ban_bounce_sql(sql, async = TRUE)
	var/datum/DBQuery/query_bounce = SSdbcore.NewQuery(sql)
	if(!query_bounce.Execute(async))
		. = "error: [query_bounce.ErrorMsg()]"
	else if(query_bounce.NextRow())
		. = query_bounce.item[1]
	else
		. = ""
	qdel(query_bounce)

/proc/ban_bounce_failed(answer)
	return findtext("[answer]", "error: ") == 1

//Every query at once, as the server's procs would run them: their answers, in order
/proc/ban_bounce_parallel(list/sqls)
	var/list/answers = new /list(length(sqls))
	var/list/done = list()
	for(var/i in 1 to length(sqls))
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(ban_bounce_parallel_one), answers, done, i, sqls[i])
	var/give_up = world.time + 1 MINUTES
	UNTIL(length(done) >= length(sqls) || world.time > give_up)
	return answers

/proc/ban_bounce_parallel_one(list/answers, list/done, i, sql)
	answers[i] = ban_bounce_sql(sql)
	done += i

/proc/ban_bounce_selects(count, base)
	. = list()
	for(var/i in 1 to count)
		. += "SELECT [base + i]"

//null if every answer is its SELECT's number, or what was wrong
/proc/ban_bounce_wrong(list/answers, base)
	var/wrong = 0
	var/example
	for(var/i in 1 to length(answers))
		if(answers[i] != "[base + i]")
			wrong++
			example = example || "[answers[i]]"
	if(wrong)
		return "[wrong] of [length(answers)] wrong, e.g. [example]"

//Its first run answers as rust_g does when the pool it was given is gone ("offline"), as when another query's lost connection
//threw that pool away between the query taking its handle and rust_g using it
/datum/DBQuery/bounce_offline
	var/gone_once = FALSE

/datum/DBQuery/bounce_offline/run_query(async)
	if(gone_once)
		return ..()
	gone_once = TRUE
	ran_on = SSdbcore.connection
	last_error = "offline"
	return FALSE

//rust_g numbers its pools in order: the newest one open, for how many were opened in between
/proc/ban_bounce_newest_pool()
	return max(text2num(SSdbcore.connection) || 0, text2num(SSdbcore.blocking_connection) || 0)

/proc/ban_bounce_pools()
	return "main [SSdbcore.connection || "none"], blocking [SSdbcore.blocking_connection || "none"]"

/proc/ban_bounce_db_ban(ckey, key, ip, cid)
	var/datum/ban_record/B = ban_check_record("Server", ckey, key, ip, cid)
	if(SSbans.add_bans(list(B)) != "database")
		return
	var/list/found = SSbans.search(ckey)
	var/datum/ban_record/copy = length(found) ? found[1] : null
	return copy?.id

/proc/run_ban_selftest_bounce(list/out, db_port)
	CONFIG_SET(flag/sql_enabled, TRUE)
	CONFIG_SET(number/port, db_port)
	SSdbcore.failed_connections = 0
	SSdbcore.failed_connection_timeout = 0
	if(!SSdbcore.Connect())
		ban_check(out, "bounce: connects", FALSE, SSdbcore.ErrorMsg())
		return
	var/ban_table = format_table_name("ban")
	var/messages = format_table_name("messages")
	var/async_timeout = CONFIG_GET(number/async_query_timeout)
	var/blocking_timeout = CONFIG_GET(number/blocking_query_timeout)
	var/two_pools = blocking_timeout != async_timeout
	UNTIL(!SSbans.db_busy && !SSnotes.db_busy)
	SSnotes.records = list()
	SSnotes.refused = list()
	run_ban_selftest_errors(out)

	//pools: many queries at once share them, nothing new is opened
	ban_bounce_sql("SELECT 1")
	ban_bounce_sql("SELECT 1", FALSE)
	var/main_pool = SSdbcore.connection
	var/blocking_pool = SSdbcore.blocking_connection
	if(two_pools)
		ban_check(out, "pools: a blocking query gets a pool of its own", blocking_pool && blocking_pool != main_pool, ban_bounce_pools())
	var/connections_before = text2num(ban_bounce_sql(BAN_BOUNCE_CONNECTIONS))
	var/list/wrong = list()
	for(var/pass in 1 to 3)
		var/round_wrong = ban_bounce_wrong(ban_bounce_parallel(ban_bounce_selects(10, pass * 100)), pass * 100)
		if(round_wrong)
			wrong += round_wrong
	for(var/i in 1 to 5)
		var/first_answer = ban_bounce_sql("SELECT [i]", FALSE)
		if(first_answer != "[i]")
			wrong += "blocking [i]: [first_answer]"
	var/opened = text2num(ban_bounce_sql(BAN_BOUNCE_CONNECTIONS)) - connections_before
	ban_check(out, "pools: 35 queries, 30 of them ten at a time, all answered right", !length(wrong), jointext(wrong, "; "))
	ban_check(out, "pools: still the same two pools", SSdbcore.connection == main_pool && SSdbcore.blocking_connection == blocking_pool, ban_bounce_pools())
	ban_check(out, "pools: the database saw few new connections for them (no churn)", opened <= 12, "[opened] new connections")

	//a read timeout is a slow query, not a lost database, and it waits no longer than the config says. (rust_g reads once more,
	//as long again, as it drops a timed-out connection, so dbcore gives it half: SSdbcore.pool_options().) The queries sleep
	//twice the timeout and more, so a wait of twice the timeout would show.
	if(async_timeout)
		var/async_started = REALTIMEOFDAY
		var/async_answer = ban_bounce_sql("SELECT SLEEP([async_timeout * 2 + 4])")
		var/async_took = (REALTIMEOFDAY - async_started) / 10
		ban_check(out, "read timeout: a slow async query fails by ASYNC_QUERY_TIMEOUT", ban_bounce_failed(async_answer) && async_took < async_timeout + 1, "[async_took] s: [async_answer]")
		ban_check(out, "read timeout: and isn't taken for a lost database (same pool, no reconnect)", SSdbcore.connection == main_pool && !SSdbcore.failed_connections, ban_bounce_pools())
		var/after_wrong = ban_bounce_wrong(ban_bounce_parallel(ban_bounce_selects(10, 500)), 500)
		ban_check(out, "read timeout: the pool's next queries get their own answers", !after_wrong, after_wrong)
	if(blocking_timeout && two_pools)
		var/blocking_started = REALTIMEOFDAY
		var/blocking_answer = ban_bounce_sql("SELECT SLEEP([blocking_timeout * 2 + 4])", FALSE)
		var/blocking_took = (REALTIMEOFDAY - blocking_started) / 10
		ban_check(out, "read timeout: a slow blocking query holds the server only BLOCKING_QUERY_TIMEOUT", ban_bounce_failed(blocking_answer) && blocking_took < blocking_timeout + 1, "[blocking_took] s: [blocking_answer]")
		ban_check(out, "read timeout: its pool is kept too", SSdbcore.blocking_connection == blocking_pool && SSdbcore.connection == main_pool, ban_bounce_pools())
		var/list/blocking_wrong = list()
		for(var/i in 1 to 3)
			var/after = ban_bounce_sql("SELECT [600 + i]", FALSE)
			if(after != "[600 + i]")
				blocking_wrong += after
		ban_check(out, "read timeout: the blocking pool's next queries get their own answers", !length(blocking_wrong), jointext(blocking_wrong, "; "))

	//killed: a connection killed under a running SELECT, the database still up
	var/newest = ban_bounce_newest_pool()
	var/list/killed = new /list(1)
	var/list/killed_done = list()
	INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(ban_bounce_parallel_one), killed, killed_done, 1, "SELECT CONCAT('survived', SLEEP(2))")
	sleep(5)
	var/victim = text2num(ban_bounce_sql("SELECT ID FROM information_schema.PROCESSLIST WHERE INFO LIKE 'SELECT CONCAT(''survived''%' AND ID <> CONNECTION_ID() LIMIT 1"))
	if(victim)
		ban_bounce_sql("KILL CONNECTION [victim]")
	var/give_up = world.time + 1 MINUTES
	UNTIL(length(killed_done) || world.time > give_up)
	ban_check(out, "killed under a SELECT: the SELECT is run again and answers", victim && killed[1] == "survived0", "connection [victim]: [killed[1]]")
	ban_check(out, "killed under a SELECT: at most one new pool", ban_bounce_newest_pool() - newest <= 1, "[ban_bounce_newest_pool() - newest] opened, [ban_bounce_pools()]")

	//writes: a connection killed under a write, the database still up (a trigger holds the write three seconds, so it waits to be
	//killed). Execute() makes a new pool but doesn't run a write again (it may have gone in), so what it was for is kept here or
	//queued, as when the database is down, never "refused"; and the next flush sends it once.
	var/list/kills = list()
	ban_bounce_kill_next(ban_table, "INSERT", kills)
	var/datum/ban_record/killed_ban = ban_check_record("Server", "killedinsert", "Killed Insert", "10.16.16.16", "1616")
	var/killed_where = SSbans.add_bans(list(killed_ban))
	var/victim_ban = ban_bounce_killed(kills)
	ban_check(out, "writes: a ban whose INSERT lost its connection is kept here, not refused", victim_ban && killed_where == "local", "connection [victim_ban]: [killed_where || "refused"] [killed_ban.id]")
	ban_check(out, "writes: and it holds meanwhile", ban_check_kept_out("Killed Insert", "10.16.16.16", "1616"))
	var/killed_lift_id = ban_bounce_db_ban("killedlift", "Killed Lift", "10.17.17.17", "1717")
	kills = list()
	ban_bounce_kill_next(ban_table, "UPDATE", kills)
	var/killed_lifted = SSbans.lift(killed_lift_id, "bancheckadmin", "BanCheckAdmin", "127.0.0.1", "1")
	var/victim_lift = ban_bounce_killed(kills)
	ban_check(out, "writes: an unban whose UPDATE lost its connection is queued, not refused", text2num(killed_lift_id) && victim_lift && killed_lifted == "queued", "connection [victim_lift]: [killed_lifted || "refused"]")
	kills = list()
	ban_bounce_kill_next(messages, "INSERT", kills)
	var/killed_note = SSnotes.add("note", "killedinsert", "Killed Insert", "bancheckadmin", "BanCheckAdmin", "note whose insert was killed", FALSE, null, "minor")
	var/victim_note = ban_bounce_killed(kills)
	ban_check(out, "writes: a note whose INSERT lost its connection is kept here, not refused", victim_note && killed_note == "local", "connection [victim_note]: [killed_note || "refused"]")
	UNTIL(!SSbans.db_busy)
	CONFIG_SET(flag/sql_enabled, FALSE)
	var/datum/ban_record/flush_ban = ban_check_record("Server", "killedflush", "Killed Flush", "10.18.18.18", "1818")
	SSbans.add_bans(list(flush_ban))
	CONFIG_SET(flag/sql_enabled, TRUE)
	var/refused_before = length(SSbans.refused)
	kills = list()
	ban_bounce_kill_next(ban_table, "INSERT", kills)
	SSbans.db_update()
	var/victim_flush = ban_bounce_killed(kills)
	ban_check(out, "writes: a flush whose INSERT lost its connection keeps its bans here to send again, none refused", victim_flush && length(SSbans.refused) == refused_before && SSbans.has_unsent(), "connection [victim_flush]: [length(SSbans.refused) - refused_before] refused")
	UNTIL(!SSbans.db_busy)
	SSbans.db_update()
	UNTIL(!SSnotes.db_busy)
	SSnotes.db_flush()
	ban_check(out, "writes: the next flush sends each once", !SSbans.has_unsent() && !length(SSbans.queued_ops) && !SSnotes.has_unsent() && ban_check_sql("SELECT COUNT(*) FROM [ban_table] WHERE ckey IN ('killedinsert', 'killedflush')") == "2" && ban_check_sql("SELECT COUNT(*) FROM [ban_table] WHERE ckey = 'killedlift' AND unbanned_datetime IS NOT NULL") == "1" && ban_check_sql("SELECT COUNT(*) FROM [messages] WHERE targetckey = 'killedinsert'") == "1", "bans [ban_check_sql("SELECT COUNT(*) FROM [ban_table] WHERE ckey IN ('killedinsert', 'killedflush')")] of 2, unban [ban_check_sql("SELECT COUNT(*) FROM [ban_table] WHERE ckey = 'killedlift' AND unbanned_datetime IS NOT NULL")], note [ban_check_sql("SELECT COUNT(*) FROM [messages] WHERE targetckey = 'killedinsert'")], [length(SSbans.queued_ops)] queued")

	//writes that got no answer but went in all the same (the connection dropped after the database had done them): the flush
	//finds them rather than sending them twice
	var/datum/ban_record/landed = ban_check_record("Server", "landedban", "Landed Ban", "10.19.19.19", "1919")
	var/landed_id = SSbans.db_insert(list(landed))
	landed.maybe_sent = TRUE
	CONFIG_SET(flag/sql_enabled, FALSE)
	SSbans.add_bans(list(landed))
	var/landed_note_kept = SSnotes.add("note", "landednote", "Landed Note", "bancheckadmin", "BanCheckAdmin", "note that went in", FALSE, null, "minor") == "local"
	var/datum/note_record/landed_note = SSnotes.records[SSnotes.records[SSnotes.records.len]]
	CONFIG_SET(flag/sql_enabled, TRUE)
	var/landed_note_id = landed_note?.db_insert()
	if(landed_note)
		landed_note.maybe_sent = TRUE
	UNTIL(!SSbans.db_busy)
	SSbans.db_update()
	ban_check(out, "writes: a ban that went in without an answer isn't sent twice, and takes the id it has", istext(landed_id) && landed.id == landed_id && ban_check_sql("SELECT COUNT(*) FROM [ban_table] WHERE ckey = 'landedban'") == "1", "[ban_check_sql("SELECT COUNT(*) FROM [ban_table] WHERE ckey = 'landedban'")] rows, [landed.id] vs [landed_id]")
	UNTIL(!SSnotes.db_busy)
	SSnotes.db_flush()
	ban_check(out, "writes: a note that went in without an answer isn't sent twice", landed_note_kept && istext(landed_note_id) && !SSnotes.records[landed_note?.id] && ban_check_sql("SELECT COUNT(*) FROM [messages] WHERE targetckey = 'landednote'") == "1" && SSnotes.moved_ids[landed_note?.id] == landed_note_id, "[ban_check_sql("SELECT COUNT(*) FROM [messages] WHERE targetckey = 'landednote'")] rows")
	var/list/edit_op = list("id" = landed.id, "mirror" = FALSE, "amount" = null, "unit" = null, "applies_to_admins" = FALSE, "reason" = "edited once", "ckey" = "landedban", "key" = "Landed Ban", "ip" = "10.19.19.19", "cid" = "1919", "edit_text" = "bounce edit once<hr>")
	var/edit_done = SSbans.edit(edit_op)
	var/list/edit_again = edit_op.Copy()
	edit_again["maybe_sent"] = TRUE //as run_or_queue() queues an edit that got no answer
	SSbans.queued_ops += list(edit_again)
	UNTIL(!SSbans.db_busy)
	SSbans.db_update()
	ban_check(out, "writes: an edit sent again after no answer adds its log line once", edit_done == "done" && !length(SSbans.queued_ops) && ban_check_sql("SELECT LOCATE('bounce edit once', edits, LOCATE('bounce edit once', edits) + 1) FROM [ban_table] WHERE id = [text2num(landed.id)]") == "0" && ban_check_sql("SELECT reason FROM [ban_table] WHERE id = [text2num(landed.id)]") == "edited once", "[edit_done || "refused"], [length(SSbans.queued_ops)] queued")
	//a write whose pool was thrown away (by another query's lost connection) before rust_g used it was never sent: run again
	var/datum/DBQuery/bounce_offline/query_offline = new("INSERT INTO [messages] (type, targetckey, adminckey, text, timestamp, server_ip, server_port, round_id, secret, deleted) VALUES ('note', 'offlinenote', 'bancheckadmin', 'pool was gone', NOW(), 0, 0, 0, 0, 0)")
	var/offline_ok = query_offline.Execute()
	var/offline_unanswered = query_offline.unanswered
	qdel(query_offline)
	ban_check(out, "writes: one whose pool was gone before it was sent is run on the new pool, once", offline_ok && !offline_unanswered && ban_check_sql("SELECT COUNT(*) FROM [messages] WHERE targetckey = 'offlinenote'") == "1", "[offline_ok], [ban_bounce_pools()]")

	//restarted: MariaDB restarted with nothing running, so the first query after meets the pools' dead connections
	var/lift_id = ban_bounce_db_ban("bouncelift", "Bounce Lift", "10.10.10.10", "1010")
	ban_check(out, "restarted: a ban to lift after is in the database", text2num(lift_id), lift_id)
	if(ban_bounce_restart(out, "a ban"))
		var/datum/ban_record/after_restart = ban_check_record("Server", "afterrestart", "After Restart", "10.11.11.11", "1111")
		var/where = SSbans.add_bans(list(after_restart))
		ban_check(out, "restarted: the first thing after is a ban, and it isn't lost", where in list("database", "local"), "[where || "refused"]: [SSdbcore.last_error]")
		ban_check(out, "restarted: it holds", ban_check_kept_out("After Restart", "10.11.11.11", "1111"))
	if(ban_bounce_restart(out, "a note"))
		var/where = SSnotes.add("note", "afterrestart", "After Restart", "bancheckadmin", "BanCheckAdmin", "note after a restart", FALSE, null, "minor")
		ban_check(out, "restarted: the first thing after is a note, and it isn't lost", where in list("database", "local"), "[where || "refused"]: [SSdbcore.last_error]")
	if(text2num(lift_id) && ban_bounce_restart(out, "an unban"))
		var/lifted = SSbans.lift(lift_id, "bancheckadmin", "BanCheckAdmin", "127.0.0.1", "1")
		ban_check(out, "restarted: the first thing after is an unban, and it isn't lost", lifted in list("done", "queued"), "[lifted || "refused"]: [SSdbcore.last_error]")
	if(ban_bounce_restart(out, "SELECTs"))
		newest = ban_bounce_newest_pool()
		var/restart_wrong = ban_bounce_wrong(ban_bounce_parallel(ban_bounce_selects(10, 700)), 700)
		ban_check(out, "restarted: ten SELECTs at once after it all answer", !restart_wrong, restart_wrong)
		var/restart_answer = ban_bounce_sql("SELECT 777", FALSE)
		ban_check(out, "restarted: a blocking SELECT after it answers", restart_answer == "777", restart_answer)
		opened = ban_bounce_newest_pool() - newest
		ban_check(out, "restarted: at most one new pool each (no churn)", opened <= (two_pools ? 2 : 1), "[opened] opened, [ban_bounce_pools()]")

	//crashed: MariaDB killed hard under a SELECT, so the connection is reset (os error 10054 on Windows)
	var/list/crashed = new /list(1)
	var/list/crashed_done = list()
	INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(ban_bounce_parallel_one), crashed, crashed_done, 1, "SELECT SLEEP(5)")
	sleep(5)
	var/crash_pool = SSdbcore.connection
	if(!ban_bounce_db("crash"))
		ban_check(out, "crashed: run_ban_check.sh killed MariaDB", FALSE, "see [BAN_BOUNCE_DIR]last_db_setup.txt")
		return
	give_up = world.time + 1 MINUTES
	UNTIL(length(crashed_done) || world.time > give_up)
	ban_check(out, "crashed: a SELECT running when MariaDB was killed fails, and is taken for a lost database", ban_bounce_failed(crashed[1]) && SSdbcore.connection != crash_pool, "[crashed[1]], [ban_bounce_pools()]")
	if(!ban_bounce_db("start"))
		ban_check(out, "crashed: run_ban_check.sh started MariaDB again", FALSE, "see [BAN_BOUNCE_DIR]last_db_setup.txt")
		return
	var/crash_back = ban_bounce_wait_back()
	ban_check(out, "crashed: and started again, the server reconnects on its own", !isnull(crash_back), "after [crash_back] s")

	//stopped: MariaDB stopped under a SELECT, then down for a while with the server busy meanwhile
	var/outage_id = ban_bounce_db_ban("beforeoutage", "Before Outage", "10.12.12.12", "1212")
	var/list/stopped_under = new /list(1)
	var/list/stopped_done = list()
	INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(ban_bounce_parallel_one), stopped_under, stopped_done, 1, "SELECT SLEEP(5)")
	sleep(5)
	var/outage_pool = SSdbcore.connection
	if(!ban_bounce_db("stop"))
		ban_check(out, "stopped: run_ban_check.sh stopped MariaDB", FALSE, "see [BAN_BOUNCE_DIR]last_db_setup.txt")
		return
	give_up = world.time + 1 MINUTES
	UNTIL(length(stopped_done) || world.time > give_up)
	ban_check(out, "stopped: a SELECT running when it stopped fails, and is taken for a lost database", ban_bounce_failed(stopped_under[1]) && SSdbcore.connection != outage_pool, "[stopped_under[1]], [ban_bounce_pools()]")
	var/started = REALTIMEOFDAY
	var/answer = ban_bounce_sql("SELECT 1")
	var/took = (REALTIMEOFDAY - started) / 10
	ban_check(out, "stopped: a query fails, without a long wait", ban_bounce_failed(answer) && took < 10, "[took] s: [answer]")
	started = REALTIMEOFDAY
	answer = ban_bounce_sql("SELECT 1", FALSE)
	took = (REALTIMEOFDAY - started) / 10
	ban_check(out, "stopped: a blocking query then fails at once, not holding the server", ban_bounce_failed(answer) && took < 1, "[took] s: [answer]")
	var/datum/ban_record/during = ban_check_record("Server", "duringoutage", "During Outage", "10.13.13.13", "1313")
	ban_check(out, "stopped: a new ban is kept here", SSbans.add_bans(list(during)) == "local", during.id)
	ban_check(out, "stopped: and holds", ban_check_kept_out("During Outage", "10.13.13.13", "1313"))
	ban_check(out, "stopped: lifting a database ban waits", text2num(outage_id) && SSbans.lift(outage_id, "bancheckadmin", "BanCheckAdmin", "127.0.0.1", "1") == "queued", outage_id)
	ban_check(out, "stopped: a note is kept here", SSnotes.add("note", "duringoutage", "During Outage", "bancheckadmin", "BanCheckAdmin", "note during the outage", FALSE, null, "minor") == "local")
	//a busy server: a query every half second for ten seconds, connecting only as often as the backoff lets it
	var/tries_before = SSdbcore.failed_connections
	var/slowest = 0
	for(var/i in 1 to 20)
		started = REALTIMEOFDAY
		ban_bounce_sql("SELECT 1")
		slowest = max(slowest, REALTIMEOFDAY - started)
		sleep(5)
	var/tries = SSdbcore.failed_connections - tries_before
	ban_check(out, "stopped: twenty queries in ten seconds try to connect only on the backoff", tries <= 2, "[tries] tries, slowest query [slowest / 10] s")
	if(!ban_bounce_db("start"))
		ban_check(out, "started again: run_ban_check.sh started MariaDB", FALSE, "see [BAN_BOUNCE_DIR]last_db_setup.txt")
		return
	//a query a second, as the server would run them, until one answers
	var/back_from = world.time
	give_up = world.time + 3 MINUTES
	while(ban_bounce_sql("SELECT 1") != "1" && world.time < give_up)
		sleep(10)
	ban_check(out, "started again: the server reconnects on its own", ban_bounce_sql("SELECT 1") == "1", "after [(world.time - back_from) / 10] s")
	UNTIL(!SSbans.db_busy)
	SSbans.db_update()
	UNTIL(!SSbans.db_busy)
	ban_check(out, "started again: no ban change is left waiting", !length(SSbans.queued_ops) && !SSbans.has_unsent(), "[length(SSbans.queued_ops)] queued")
	ban_check(out, "started again: the ban made meanwhile is in it", ban_check_sql("SELECT COUNT(*) FROM [ban_table] WHERE ckey = 'duringoutage' AND unbanned_datetime IS NULL") == "1")
	ban_check(out, "started again: the ban made right after the restart is in it", ban_check_sql("SELECT COUNT(*) FROM [ban_table] WHERE ckey = 'afterrestart' AND unbanned_datetime IS NULL") == "1")
	ban_check(out, "started again: the waiting unban was applied", ban_check_sql("SELECT COUNT(*) FROM [ban_table] WHERE ckey = 'beforeoutage' AND unbanned_datetime IS NOT NULL") == "1")
	ban_check(out, "started again: the unban right after the restart was applied", ban_check_sql("SELECT COUNT(*) FROM [ban_table] WHERE ckey = 'bouncelift' AND unbanned_datetime IS NOT NULL") == "1")
	UNTIL(!SSnotes.db_busy)
	SSnotes.db_flush()
	ban_check(out, "started again: the notes are in it, none left here", !SSnotes.has_unsent() && ban_check_sql("SELECT COUNT(*) FROM [messages] WHERE targetckey IN ('afterrestart', 'duringoutage')") == "2", "[ban_check_sql("SELECT COUNT(*) FROM [messages] WHERE targetckey IN ('afterrestart', 'duringoutage')")] in it, [length(SSnotes.records)] here")
	//then steady on one pool
	ban_bounce_sql("SELECT 1", FALSE)
	main_pool = SSdbcore.connection
	blocking_pool = SSdbcore.blocking_connection
	connections_before = text2num(ban_bounce_sql(BAN_BOUNCE_CONNECTIONS))
	wrong = list()
	for(var/pass in 1 to 2)
		var/round_wrong = ban_bounce_wrong(ban_bounce_parallel(ban_bounce_selects(10, 800 + pass * 100)), 800 + pass * 100)
		if(round_wrong)
			wrong += round_wrong
	for(var/i in 1 to 3)
		answer = ban_bounce_sql("SELECT [i]", FALSE)
		if(answer != "[i]")
			wrong += "blocking [i]: [answer]"
	opened = text2num(ban_bounce_sql(BAN_BOUNCE_CONNECTIONS)) - connections_before
	ban_check(out, "started again: then steady, 23 queries on the same pools (no churn)", !length(wrong) && SSdbcore.connection == main_pool && SSdbcore.blocking_connection == blocking_pool && opened <= 12, "[jointext(wrong, "; ")] [opened] new connections, [ban_bounce_pools()]")

	//sending: changes asked for while what they change is on its way to the database (db_flush()'s inserts are async)
	UNTIL(!SSbans.db_busy)
	CONFIG_SET(flag/sql_enabled, FALSE)
	var/datum/ban_record/racing = ban_check_record("Server", "racingban", "Racing Ban", "10.14.14.14", "1414")
	var/datum/ban_record/racing_edit = ban_check_record("Chef", "racingedit", "Racing Edit", null, "1515")
	var/kept = SSbans.add_bans(list(racing)) == "local" && SSbans.add_bans(list(racing_edit)) == "local"
	var/racing_id = racing.id
	var/racing_edit_id = racing_edit.id
	CONFIG_SET(flag/sql_enabled, TRUE)
	INVOKE_ASYNC(SSbans, TYPE_PROC_REF(/datum/controller/subsystem/bans, db_update))
	var/was_sending = SSbans.db_sending
	var/lifted = SSbans.lift(racing_id, "bancheckadmin", "BanCheckAdmin", "127.0.0.1", "1")
	ban_check(out, "sending: an unban asked for while its ban goes in waits, then lifts it in the database", kept && was_sending && lifted == "done" && ban_check_sql("SELECT COUNT(*) FROM [ban_table] WHERE ckey = 'racingban' AND unbanned_datetime IS NOT NULL") == "1", "sending [was_sending], [lifted || "refused"], [racing_id] is now [racing.id]")
	ban_check(out, "sending: and the player gets in", !world.IsBanned("Racing Ban", "10.14.14.14", "1414", "world"))
	var/list/op = list("id" = racing_edit_id, "mirror" = FALSE, "amount" = null, "unit" = null, "applies_to_admins" = FALSE, "reason" = "edited while it went in", "ckey" = "racingedit", "key" = "Racing Edit", "ip" = null, "cid" = "1515", "edit_text" = "race<hr>")
	var/edited = SSbans.edit(op)
	ban_check(out, "sending: an edit of one sent meanwhile changes it in the database", edited == "done" && ban_check_sql("SELECT COUNT(*) FROM [ban_table] WHERE ckey = 'racingedit' AND reason = 'edited while it went in'") == "1", "[edited || "refused"], [racing_edit_id] is now [racing_edit.id]")
	UNTIL(!SSbans.db_busy && !SSnotes.db_busy)
	CONFIG_SET(flag/sql_enabled, FALSE)
	var/note_kept = SSnotes.add("note", "racingnote", "Racing Note", "bancheckadmin", "BanCheckAdmin", "racing note", FALSE, null, "minor") == "local"
	var/note_id = SSnotes.records[SSnotes.records.len]
	CONFIG_SET(flag/sql_enabled, TRUE)
	INVOKE_ASYNC(SSnotes, TYPE_PROC_REF(/datum/controller/subsystem/notes, db_flush))
	var/notes_sending = SSnotes.db_sending
	var/changed = SSnotes.change(note_id, list("severity" = "high"))
	ban_check(out, "sending: a note changed while it goes in waits, then changes it in the database", note_kept && notes_sending && changed && ban_check_sql("SELECT severity FROM [messages] WHERE targetckey = 'racingnote'") == "high", "sending [notes_sending], [note_id]: [changed]")

#undef BAN_BOUNCE_DIR
#undef BAN_BOUNCE_CONNECTIONS
