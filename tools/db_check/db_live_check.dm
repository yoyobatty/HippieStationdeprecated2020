//Every-query check, live half: a real boot and round against a real database, recording every query that runs and how it went.
//Only in the check's own build: tools/db_check/run_db_check.sh adds this file to a copy of the .dme.
//Writes data/db_check/ran.json (sql -> "ok" or the error) and data/db_check/done.txt; query_check.py --ran maps them back to their sites.

GLOBAL_LIST_EMPTY(db_check_ran)
GLOBAL_LIST_EMPTY(db_check_steps)

/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	if("db-check" in world.params)
		sleep_offline_after_initializations = FALSE //nobody connects to this, so the world has to keep ticking
		//the boot's own copies of the bans, notes and connections go here, not over the real ones in data/
		SSbans.ledger_path = "data/db_check/bans.json"
		SSbans.seen_path = "data/db_check/connections.json"
		SSnotes.ledger_path = "data/db_check/notes.json"
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(run_db_live_check))
	return ..()

//every query the game runs goes through here, the boot's and the round's included
/datum/DBQuery/Execute(async = TRUE, log_error = TRUE)
	. = ..()
	if(sql)
		var/key = trim(sql)
		var/was = GLOB.db_check_ran[key]
		if(!was || was == "ok") //keep an error once seen
			GLOB.db_check_ran[key] = . ? "ok" : "[ErrorMsg() || "failed"]"

/proc/db_check_step(name, ok, detail)
	GLOB.db_check_steps += "[ok ? "PASS" : "FAIL"] [name][detail ? " ([detail])" : ""]"

/proc/db_check_save(final)
	fdel("data/db_check/ran.json")
	text2file(json_encode(GLOB.db_check_ran), "data/db_check/ran.json")
	if(final)
		fdel("data/db_check/steps.txt")
		text2file(jointext(GLOB.db_check_steps, "\n"), "data/db_check/steps.txt")
		text2file("done", "data/db_check/done.txt")

//first column of the first row, or the error
/proc/db_check_value(sql)
	var/datum/DBQuery/query_db_check = SSdbcore.NewQuery(sql)
	if(!query_db_check.Execute())
		. = "error: [query_db_check.ErrorMsg()]"
	else if(query_db_check.NextRow())
		. = query_db_check.item[1]
	qdel(query_db_check)

//The login's database work (client/set_client_age_from_db()), without a client: db_login_read() and db_login_write() on made-up
//players, checked, and timed against the queries the login used to run one after another
/proc/db_check_login()
	var/player = format_table_name("player")
	//two alts seen before on one IP and computer, then a new player on them
	db_login_write("dbcheckalta", "DB Check Alt A", "10.20.30.40", "5550001", "Player")
	db_login_write("dbcheckaltb", "DB Check Alt B", "10.20.30.40", "5550001", "Player")
	sleep(1 SECONDS)
	var/list/row = db_login_read("dbchecknew", "10.20.30.40", "5550001")
	db_check_step("login read: a new player reads as new", row && !row["exists"], json_encode(row))
	db_check_step("login read: finds the alts on the IP and computer", row && row["related_ip"] == "dbcheckalta, dbcheckaltb" && row["related_cid"] == "dbcheckalta, dbcheckaltb", "[row?["related_ip"]] / [row?["related_cid"]]")
	db_login_write("dbchecknew", "DB Check New", "10.20.30.40", "5550001", "Player")
	sleep(1 SECONDS)
	db_check_step("login write: the new player's row", db_check_value("SELECT CONCAT(byond_key, '|', INET_NTOA(ip), '|', computerid) FROM [player] WHERE ckey = 'dbchecknew'") == "DB Check New|10.20.30.40|5550001")
	db_check_step("login write: and the connection log", text2num(db_check_value("SELECT COUNT(*) FROM [format_table_name("connection_log")] WHERE ckey = 'dbchecknew'")) == 1)
	db_login_write("dbchecknew", "DB Check Renamed", "10.20.30.41", "5550002", "Game Master") //seen again, with a changed key
	sleep(1 SECONDS)
	row = db_login_read("dbchecknew", "10.20.30.41", "5550002")
	db_check_step("login read: seen before, age 0 days, last computer", row && row["exists"] && row["age"] == "0" && row["last_cid"] == "5550002", json_encode(row))
	db_check_step("login write: seen again updates key, IP and rank", db_check_value("SELECT CONCAT(byond_key, '|', INET_NTOA(ip), '|', lastadminrank) FROM [player] WHERE ckey = 'dbchecknew'") == "DB Check Renamed|10.20.30.41|Game Master")

	//timing: what the login waits on, for a player seen before. Before: these one after another (the randomizer's is off by default).
	var/list/old_chain = list(
		"SELECT ckey FROM [player] WHERE ip = INET_ATON('10.20.30.41') AND ckey != 'dbchecknew'",
		"SELECT ckey FROM [player] WHERE computerid = '5550002' AND ckey != 'dbchecknew'",
		"SELECT 1 FROM [player] WHERE ckey = 'dbchecknew'",
		"SELECT firstseen, DATEDIFF(Now(),firstseen), accountjoindate, DATEDIFF(Now(),accountjoindate) FROM [player] WHERE ckey = 'dbchecknew'",
		"UPDATE [player] SET lastseen = Now(), lastseen_round_id = 1, ip = INET_ATON('10.20.30.41'), computerid = '5550002', lastadminrank = 'Player', accountjoindate = NULL WHERE ckey = 'dbchecknew'",
		"INSERT INTO [format_table_name("connection_log")] (datetime, server_ip, server_port, round_id, ckey, ip, computerid) VALUES (Now(), 0, 1, 1, 'dbchecknew', INET_ATON('10.20.30.41'), '5550002')",
		"SELECT byond_key FROM [player] WHERE ckey = 'dbchecknew'",
		"SELECT role, applies_to_admins, TIMESTAMPDIFF(SECOND, NOW(), expiration_time) FROM [format_table_name("ban")] WHERE (ckey = 'dbchecknew' OR computerid = '5550002') AND unbanned_datetime IS NULL")
	var/runs = 10
	var/old_ticks = world.time
	var/old_real = REALTIMEOFDAY
	for(var/n in 1 to runs)
		for(var/sql in old_chain)
			var/datum/DBQuery/query_old = SSdbcore.NewQuery(sql)
			query_old.Execute()
			while(query_old.NextRow())
				pass()
			qdel(query_old)
	old_ticks = (world.time - old_ticks) / runs
	old_real = (REALTIMEOFDAY - old_real) / runs
	var/new_ticks = world.time
	var/new_real = REALTIMEOFDAY
	for(var/n in 1 to runs)
		db_login_read("dbchecknew", "10.20.30.41", "5550002")
	new_ticks = (world.time - new_ticks) / runs
	new_real = (REALTIMEOFDAY - new_real) / runs
	var/timing = "before [length(old_chain)] queries one after another: [old_real * 100] ms ([old_ticks / world.tick_lag] ticks); now one read: [new_real * 100] ms ([new_ticks / world.tick_lag] ticks); at [world.fps] fps, over [runs] logins"
	GLOB.db_check_steps += "TIME login [timing]"
	db_check_step("login: the read waits on less than the old chain did", new_real < old_real, timing)

/proc/run_db_live_check()
	UNTIL(SSticker.initialized)
	db_check_step("connected at boot", SSdbcore.IsConnected(), SSdbcore.ErrorMsg())
	db_check_step("schema version matches", !SSdbcore.schema_mismatch, "[SSdbcore.db_major].[SSdbcore.db_minor]")
	db_check_step("round id from the database", text2num(GLOB.round_id) > 0, "[GLOB.round_id]")
	db_check_step("strict mode", findtext(db_check_value("SELECT @@SESSION.sql_mode"), "STRICT_TRANS_TABLES"))
	db_check_save()

	UNTIL(SSticker.current_state >= GAME_STATE_PLAYING)
	sleep(5 SECONDS)
	db_check_step("round start written", text2num(db_check_value("SELECT start_datetime IS NOT NULL FROM [format_table_name("round")] WHERE id = [text2num(GLOB.round_id)]")) == 1)

	//things the round does on its own, called now so they're sure to happen
	SSblackbox.CheckPlayerCount()
	sleep(1 SECONDS)
	db_check_step("population row", text2num(db_check_value("SELECT COUNT(*) FROM [format_table_name("legacy_population")] WHERE round_id = [text2num(GLOB.round_id)]")) >= 1)

	var/mob/living/carbon/human/victim
	for(var/mob/living/carbon/human/H in GLOB.alive_mob_list)
		if(H.key && H.mind && !H.stat)
			victim = H
			break
	if(victim)
		victim.death()
		sleep(2 SECONDS)
		db_check_step("death row", text2num(db_check_value("SELECT COUNT(*) FROM [format_table_name("death")] WHERE round_id = [text2num(GLOB.round_id)]")) >= 1, victim.key)
	else
		db_check_step("death row", FALSE, "no crew with a key to kill")

	var/turf/T = locate(world.maxx / 2, world.maxy / 2, SSmapping.station_start)
	var/obj/machinery/computer/libraryconsole/bookmanagement/console = new(T)
	console.author = "DB Check"
	console.title = "Every Query"
	console.category = "Any"
	console.library_search()
	db_check_step("library search", islist(console.search_results))
	var/obj/item/book/B = new(T)
	B.author = "DB Check"
	B.title = "Every Query"
	B.name = "Every Query"
	B.dat = "A book with a 'quote' and a \\ backslash, and ünïcödé."
	console.scanner = new /obj/machinery/libraryscanner(T)
	console.scanner.cache = B
	var/mob/living/carbon/human/reader = new(T)
	reader.ckey = null
	reader.key = "DBCheckReader"
	console.library_upload(reader)
	sleep(1 SECONDS)
	db_check_step("library upload keeps the text", db_check_value("SELECT content FROM [format_table_name("library")] WHERE title = 'Every Query' ORDER BY id DESC LIMIT 1") == B.dat, db_check_value("SELECT content FROM [format_table_name("library")] WHERE title = 'Every Query' ORDER BY id DESC LIMIT 1"))
	create_random_books(2, T, FALSE)
	db_check_step("random books", TRUE)

	db_check_login()

	SSipstack.check_ip("8.8.8.8")
	SSdiscord.lookup_id("dbcheckplayer")
	SSdiscord.lookup_ckey("12345")
	db_check_step("discord and ipstack lookups ran", TRUE)
	db_check_save()

	//round end, as the game does it
	SSticker.force_ending = TRUE
	UNTIL(SSticker.current_state == GAME_STATE_FINISHED)
	sleep(10 SECONDS) //the round-end report and feedback
	db_check_step("round end written", text2num(db_check_value("SELECT end_datetime IS NOT NULL FROM [format_table_name("round")] WHERE id = [text2num(GLOB.round_id)]")) == 1)
	//what the reboot does: the feedback goes in, then the round's shutdown time
	SSblackbox.Shutdown()
	sleep(2 SECONDS)
	db_check_step("feedback rows", text2num(db_check_value("SELECT COUNT(*) FROM [format_table_name("feedback")] WHERE round_id = [text2num(GLOB.round_id)]")) >= 1)
	SSdbcore.Shutdown()
	var/sql_errors = 0
	for(var/s in GLOB.db_check_ran)
		if(GLOB.db_check_ran[s] != "ok")
			sql_errors++
	db_check_step("no query failed", !sql_errors, "[sql_errors] of [length(GLOB.db_check_ran)]")
	db_check_save(TRUE)
