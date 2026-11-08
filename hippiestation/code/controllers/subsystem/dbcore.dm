// hippie -- the database through rust_g's MySQL pool, replacing BSQL (abandoned 2019, and every value had to be escaped by
// hand with sanitizeSQL()). Rewritten whole from code/controllers/subsystem/dbcore.dm, which is out of the .dme.
//
// Values go in as bound parameters, never as part of the SQL text:
//	var/datum/DBQuery/query_x = SSdbcore.NewQuery("SELECT a FROM [format_table_name("t")] WHERE ckey = :ckey", list("ckey" = ckey))
// Parameters are named (:name), from an associative list. Results read as before: Execute(), NextRow(), item[n], and item
// values are text (or null for NULL), as BSQL gave them. rust_g can't read DOUBLE, DECIMAL (so SUM(), AVG() and /) or TIME
// columns, they come back null, and BIGINT past 2^24 loses digits in a BYOND number: CAST(x AS CHAR) those in the SELECT.

SUBSYSTEM_DEF(dbcore)
	name = "Database"
	flags = SS_BACKGROUND
	wait = 1 MINUTES
	init_order = INIT_ORDER_DBCORE

	var/schema_mismatch = 0
	var/db_minor = 0
	var/db_major = 0

	var/last_error
	var/list/active_queries = list()

	/// rust_g's pool handle, or null
	var/connection
	/// a Connect() is waiting on the library: others wait for its answer instead of starting a second
	var/connecting = FALSE
	/// failed connects in a row
	var/failed_connections = 0
	/// world.time before which Connect() doesn't try again (5 s, doubling each failure in a row, up to DB_CONNECT_BACKOFF_MAX):
	/// a connect blocks the server while it waits, and a dead database shouldn't freeze it every few seconds
	var/failed_connection_timeout = 0

	var/queries_run = 0
	var/queries_failed = 0
	var/slow_queries = 0

/datum/controller/subsystem/dbcore/Initialize()
	//We send warnings to the admins during subsystem init, as the clients will be New'd and messages
	//will queue properly with goonchat
	switch(schema_mismatch)
		if(1)
			message_admins("Database schema ([db_major].[db_minor]) doesn't match the latest schema version ([DB_MAJOR_VERSION].[DB_MINOR_VERSION]), this may lead to undefined behaviour or errors")
		if(2)
			message_admins("Could not get schema version from database")

	return ..()

/datum/controller/subsystem/dbcore/stat_entry(msg)
	return ..("[IsConnected() ? "Up" : "Down"], [queries_run] queries ([queries_failed] failed, [slow_queries] slow)")

/datum/controller/subsystem/dbcore/fire()
	for(var/I in active_queries)
		var/datum/DBQuery/Q = I
		if(world.time - Q.last_activity_time > (5 MINUTES))
			message_admins("Found undeleted query, please check the server logs and notify coders.")
			log_sql("Undeleted query: \"[Q.sql]\" LA: [Q.last_activity] LAT: [Q.last_activity_time]")
			qdel(Q)
		if(MC_TICK_CHECK)
			return

/datum/controller/subsystem/dbcore/Recover()
	connection = SSdbcore.connection

/datum/controller/subsystem/dbcore/Shutdown()
	//This is as close as we can get to the true round end before Disconnect() without changing where it's called, defeating the reason this is a subsystem
	if(SSdbcore.Connect())
		var/datum/DBQuery/query_round_shutdown = SSdbcore.NewQuery("UPDATE [format_table_name("round")] SET shutdown_datetime = Now(), end_state = :end_state WHERE id = :round_id",
			list("end_state" = SSticker.end_state, "round_id" = GLOB.round_id))
		query_round_shutdown.Execute(async = FALSE) //the world is going down: nothing would wake an async one
		qdel(query_round_shutdown)
	if(IsConnected())
		Disconnect()

//nu
/datum/controller/subsystem/dbcore/can_vv_get(var_name)
	return var_name != NAMEOF(src, connection) && var_name != NAMEOF(src, active_queries) && ..()

/datum/controller/subsystem/dbcore/vv_edit_var(var_name, var_value)
	if(var_name == NAMEOF(src, connection))
		return FALSE
	return ..()

/datum/controller/subsystem/dbcore/proc/Connect()
	if(IsConnected())
		return TRUE
	if(!CONFIG_GET(flag/sql_enabled))
		return FALSE
	if(connecting)
		UNTIL(!connecting)
		return IsConnected()
	if(world.time < failed_connection_timeout)
		return FALSE

	connecting = TRUE
	var/timeout = max(CONFIG_GET(number/async_query_timeout), CONFIG_GET(number/blocking_query_timeout)) || null //0 is no limit
	var/list/options = list(
		"host" = CONFIG_GET(string/address),
		"port" = CONFIG_GET(number/port),
		"user" = CONFIG_GET(string/feedback_login),
		"pass" = CONFIG_GET(string/feedback_password),
		"db_name" = CONFIG_GET(string/feedback_database),
		"read_timeout" = timeout,
		"write_timeout" = timeout,
		"min_threads" = CONFIG_GET(number/pooling_min_sql_connections),
		"max_threads" = CONFIG_GET(number/pooling_max_sql_connections),
	)
	var/list/result = json_decode(rustg_sql_connect_pool(json_encode(options)))
	connecting = FALSE
	if(result?["status"] == "ok")
		connection = result["handle"]
		last_error = null
		if(failed_connections)
			log_sql("Connected after [failed_connections] failed tr[failed_connections == 1 ? "y" : "ies"].")
		failed_connections = 0
		failed_connection_timeout = 0
		return TRUE
	last_error = result?["data"] || "rust_g gave no answer"
	failed_connections++
	var/wait = min(5 SECONDS * (2 ** min(failed_connections - 1, 8)), DB_CONNECT_BACKOFF_MAX)
	failed_connection_timeout = world.time + wait
	log_sql("Connect() failed ([failed_connections] in a row, next try in [wait / 10] s) | [last_error]")
	return FALSE

/datum/controller/subsystem/dbcore/proc/CheckSchemaVersion()
	if(CONFIG_GET(flag/sql_enabled))
		if(Connect())
			log_world("Database connection established.")
			var/datum/DBQuery/query_db_version = NewQuery("SELECT major, minor FROM [format_table_name("schema_revision")] ORDER BY date DESC LIMIT 1")
			query_db_version.Execute()
			if(query_db_version.NextRow())
				db_major = text2num(query_db_version.item[1])
				db_minor = text2num(query_db_version.item[2])
				if(db_major != DB_MAJOR_VERSION || db_minor != DB_MINOR_VERSION)
					schema_mismatch = 1 // flag admin message about mismatch
					log_sql("Database schema ([db_major].[db_minor]) doesn't match the latest schema version ([DB_MAJOR_VERSION].[DB_MINOR_VERSION]), this may lead to undefined behaviour or errors")
			else
				schema_mismatch = 2 //flag admin message about no schema version
				log_sql("Could not get schema version from database")
			qdel(query_db_version)
		else
			log_sql("Your server failed to establish a connection with the database.")
	else
		log_sql("Database is not enabled in configuration.")

/datum/controller/subsystem/dbcore/proc/SetRoundID()
	if(!Connect())
		return
	var/datum/DBQuery/query_round_initialize = SSdbcore.NewQuery("INSERT INTO [format_table_name("round")] (initialize_datetime, server_ip, server_port) VALUES (Now(), INET_ATON(:ip), :port)",
		list("ip" = world.internet_address || "0", "port" = "[world.port]"))
	query_round_initialize.Execute(async = FALSE)
	//the id from the INSERT itself: a separate SELECT LAST_INSERT_ID() can land on another of the pool's connections
	if(query_round_initialize.last_insert_id)
		GLOB.round_id = "[query_round_initialize.last_insert_id]"
	qdel(query_round_initialize)

/datum/controller/subsystem/dbcore/proc/SetRoundStart()
	if(!Connect())
		return
	var/datum/DBQuery/query_round_start = SSdbcore.NewQuery("UPDATE [format_table_name("round")] SET start_datetime = Now() WHERE id = :round_id", list("round_id" = GLOB.round_id))
	query_round_start.Execute()
	qdel(query_round_start)

/datum/controller/subsystem/dbcore/proc/SetRoundEnd()
	if(!Connect())
		return
	var/datum/DBQuery/query_round_end = SSdbcore.NewQuery("UPDATE [format_table_name("round")] SET end_datetime = Now(), game_mode_result = :result, station_name = :station WHERE id = :round_id",
		list("result" = SSticker.mode_result, "station" = station_name(), "round_id" = GLOB.round_id))
	query_round_end.Execute()
	qdel(query_round_end)

/// A line in the admin_log table, by usr (the permissions panel's log). TRUE if it went in.
/datum/controller/subsystem/dbcore/proc/admin_log(operation, target, log_text)
	var/datum/DBQuery/query_admin_log = NewQuery("INSERT INTO [format_table_name("admin_log")] (datetime, round_id, adminckey, adminip, operation, target, log) VALUES (:time, :round_id, :adminckey, INET_ATON(:adminip), :operation, :target, :log)", list(
		"time" = SQLtime(),
		"round_id" = text2num(GLOB.round_id) || 0,
		"adminckey" = usr?.ckey || "",
		"adminip" = usr?.client?.address || "0",
		"operation" = "[operation]",
		"target" = "[target]",
		"log" = "[log_text]"))
	. = query_admin_log.warn_execute()
	qdel(query_admin_log)

/datum/controller/subsystem/dbcore/proc/Disconnect()
	failed_connections = 0
	if(connection)
		rustg_sql_disconnect_pool(connection)
	connection = null

/datum/controller/subsystem/dbcore/proc/IsConnected()
	if(!CONFIG_GET(flag/sql_enabled) || isnull(connection))
		return FALSE
	var/list/result = json_decode(rustg_sql_connected(connection))
	return result?["status"] == "online"

/datum/controller/subsystem/dbcore/proc/ErrorMsg()
	if(!CONFIG_GET(flag/sql_enabled))
		return "Database disabled by configuration"
	return last_error

/datum/controller/subsystem/dbcore/proc/ReportError(error)
	last_error = error

/// sql: the query, with :name where each value goes. arguments: name = value (text, numbers or null).
/datum/controller/subsystem/dbcore/proc/NewQuery(sql_query, list/arguments)
	if(IsAdminAdvancedProcCall())
		log_admin_private("ERROR: Advanced admin proc call led to sql query: [sql_query]. Query has been blocked")
		message_admins("ERROR: Advanced admin proc call led to sql query. Query has been blocked")
		return FALSE
	return new /datum/DBQuery(sql_query, arguments)

/datum/controller/subsystem/dbcore/proc/QuerySelect(list/querys, warn = FALSE, qdel = FALSE)
	if (!islist(querys))
		if (!istype(querys, /datum/DBQuery))
			CRASH("Invalid query passed to QuerySelect: [querys]")
		querys = list(querys)

	for (var/thing in querys)
		var/datum/DBQuery/query = thing
		if (warn)
			INVOKE_ASYNC(query, TYPE_PROC_REF(/datum/DBQuery, warn_execute))
		else
			INVOKE_ASYNC(query, TYPE_PROC_REF(/datum/DBQuery, Execute))

	for (var/thing in querys)
		var/datum/DBQuery/query = thing
		UNTIL(!query.in_progress)
		if (qdel)
			qdel(query)

/*
Takes a list of rows (each an associative list of column = value) and inserts them in as few queries as it can.
Values are plain values, bound as parameters: no quotes, no escaping. A column missing from a row is NULL.
special_columns: column = SQL for that column's value, with ? where the row's value goes, e.g. list("ip" = "INET_ATON(?)",
	"datetime" = "NOW()") (a special column with no ? ignores the row's value).
duplicate_key: TRUE to update every column on a duplicate key, or text to append after the VALUES.
ignore_errors: INSERT IGNORE, rows that fail are skipped. delayed is kept for old callers and ignored (InnoDB has no DELAYED).
Returns TRUE if every query went in.
*/
/datum/controller/subsystem/dbcore/proc/MassInsert(table, list/rows, duplicate_key = FALSE, ignore_errors = FALSE, delayed = FALSE, warn = FALSE, async = TRUE, list/special_columns = null)
	if (!table || !islist(rows) || !length(rows)) //no rows would make "INSERT INTO table () VALUES", a syntax error
		return
	var/list/column_set = list()
	for (var/list/row in rows)
		for (var/column in row)
			column_set[column] = TRUE
	var/list/columns = list()
	for (var/column in column_set)
		columns += column

	var/duplicate_sql = ""
	if (duplicate_key == TRUE)
		var/list/column_list = list()
		for (var/column in columns)
			column_list += "[column] = VALUES([column])"
		duplicate_sql = " ON DUPLICATE KEY UPDATE [column_list.Join(", ")]"
	else if (istext(duplicate_key))
		duplicate_sql = " [duplicate_key]"

	. = TRUE
	for (var/start = 1, start <= length(rows), start += DB_MASS_INSERT_ROWS)
		var/list/arguments = list()
		var/list/values = list()
		for (var/r in start to min(start + DB_MASS_INSERT_ROWS - 1, length(rows)))
			var/list/row = rows[r]
			var/list/placeholders = list()
			for (var/i in 1 to length(columns))
				var/column = columns[i]
				var/name = "r[r]c[i]"
				arguments[name] = row[column]
				var/special = special_columns && special_columns[column]
				placeholders += special ? replacetext(special, "?", ":[name]") : ":[name]"
			values += "([placeholders.Join(", ")])"
		var/datum/DBQuery/Query = NewQuery("INSERT[ignore_errors ? " IGNORE" : ""] INTO [table] ([columns.Join(", ")]) VALUES [values.Join(", ")][duplicate_sql]", arguments)
		var/ok = warn ? Query.warn_execute(async) : Query.Execute(async)
		qdel(Query)
		if (!ok)
			. = FALSE

/datum/DBQuery
	var/sql // The sql query being executed.
	var/list/arguments // name = value, bound to the query's :name placeholders
	var/list/item = list() //list of data values populated by NextRow()

	var/list/rows
	var/next_row_to_take = 1
	var/affected
	var/last_insert_id

	var/last_activity
	var/last_activity_time

	var/last_error
	var/in_progress

/datum/DBQuery/New(sql_query, list/arguments)
	SSdbcore.active_queries[src] = TRUE
	Activity("Created")
	sql = sql_query
	src.arguments = arguments

/datum/DBQuery/Destroy()
	Close()
	SSdbcore.active_queries -= src
	return ..()

/datum/DBQuery/CanProcCall(proc_name)
	//fuck off kevinz
	return FALSE

/datum/DBQuery/proc/SetQuery(new_sql, list/new_arguments)
	if(in_progress)
		CRASH("Attempted to set new sql while waiting on active query")
	Close()
	sql = new_sql
	arguments = new_arguments

/datum/DBQuery/proc/Activity(activity)
	last_activity = activity
	last_activity_time = world.time

/datum/DBQuery/proc/warn_execute(async = TRUE)
	. = Execute(async)
	if(!.)
		to_chat(usr, "<span class='danger'>A SQL error occurred during this operation, check the server logs.</span>")

/datum/DBQuery/proc/Execute(async = TRUE, log_error = TRUE)
	Activity("Execute")
	if(in_progress)
		CRASH("Attempted to start a new query while waiting on the old one")
	Close()
	if(!SSdbcore.Connect())
		last_error = "No connection! ([SSdbcore.ErrorMsg()])"
		return FALSE

	var/start_time = REALTIMEOFDAY
	. = run_query(async)
	if(!. && is_connection_error(last_error))
		//the database went away (restarted, killed, or the connection timed out): a new pool, and a read is run again on it.
		//A write isn't, since it may already have gone in before the connection dropped.
		log_sql("Lost the database connection: [last_error]")
		SSdbcore.Disconnect()
		if(SSdbcore.Connect())
			log_sql("Connection reestablished")
			if(findtext(trim(sql), "SELECT", 1, 7))
				. = run_query(async)
		else
			log_sql("Couldn't reestablish the database connection.")
	var/took = REALTIMEOFDAY - start_time
	SSdbcore.queries_run++
	if(!.)
		SSdbcore.queries_failed++
		SSdbcore.last_error = last_error
		if(log_error)
			log_sql("[last_error] | Query used: [sql][length(arguments) ? " | Arguments: [json_encode(arguments)]" : ""]")
	if(took > DB_SLOW_QUERY)
		SSdbcore.slow_queries++
		log_sql("Slow query ([took / 10] s): [sql]")
		if(!async)
			log_query_debug("Slow blocking query ([took / 10] s): [sql]")

/// Driver and network errors, as against the database refusing the SQL ("MySqlError { ERROR 1064 ... }")
/datum/DBQuery/proc/is_connection_error(error)
	if(!error || findtext(error, "MySqlError") || findtext(error, "named parameter"))
		return FALSE
	return findtext(error, "IoError") || findtext(error, "Could not connect") || findtext(error, "ConnectionClosed") || findtext(error, "gone away") || findtext(error, "Lost connection") || findtext(error, "timed out") || findtext(error, "offline")

/datum/DBQuery/proc/run_query(async)
	var/connection = SSdbcore.connection
	var/job_result
	if(async)
		var/job_id = rustg_sql_query_async(connection, sql, encode_arguments())
		in_progress = TRUE
		UNTIL((job_result = rustg_sql_check_query(job_id)) != RUSTG_JOB_NO_RESULTS_YET)
		in_progress = FALSE
		if(job_result == RUSTG_JOB_ERROR || job_result == RUSTG_JOB_NO_SUCH_JOB)
			last_error = "rust_g: [job_result]"
			return FALSE
	else
		job_result = rustg_sql_query_blocking(connection, sql, encode_arguments())
	var/list/result = json_decode(job_result)
	switch(result?["status"])
		if("ok")
			rows = result["rows"]
			affected = result["affected"]
			last_insert_id = result["last_insert_id"]
			return TRUE
		if("err")
			last_error = result["data"]
			return FALSE
		if("offline")
			last_error = "offline"
			return FALSE
	last_error = "rust_g gave no answer we know: [copytext(job_result, 1, 200)]"
	return FALSE

/// The arguments as rust_g's JSON. A BYOND number is a 32-bit float: past 2^24, or with a fraction, it goes as text, which
/// MariaDB converts back, so json_encode's rounding never reaches the database.
/// Only the ones the SQL uses go: rust_g refuses named parameters for SQL with none in it (a WHERE built without its filters).
/datum/DBQuery/proc/encode_arguments()
	if(!length(arguments))
		return "{}"
	var/list/encoded = list()
	for(var/name in arguments)
		if(!findtext(sql, ":[name]"))
			continue
		var/value = arguments[name]
		if(isnum(value))
			if(value != round(value))
				value = "[value]"
			else if(abs(value) >= 16777216)
				value = num2text(value, 12)
		else if(!isnull(value) && !istext(value))
			value = "[value]"
		encoded[name] = value
	return json_encode(encoded)

/datum/DBQuery/proc/NextRow(async = TRUE)
	Activity("NextRow")
	UNTIL(!in_progress)
	if(!rows || next_row_to_take > length(rows))
		item = list()
		return FALSE
	var/list/row = rows[next_row_to_take]
	rows[next_row_to_take++] = null //read once: the rows can be big
	//text, as BSQL gave it, so callers' text2num() and string checks stay as they were
	for(var/i in 1 to length(row))
		var/value = row[i]
		if(isnum(value))
			row[i] = value == round(value) ? num2text(value, 12) : "[value]"
		else if(islist(value)) //a BLOB comes as its bytes
			var/list/chars = list()
			for(var/byte in value)
				chars += ascii2text(byte)
			row[i] = chars.Join()
	item = row
	return TRUE

/datum/DBQuery/proc/ErrorMsg()
	return last_error

/datum/DBQuery/proc/Close()
	rows = null
	next_row_to_take = 1
	item = list()
	affected = null
	last_insert_id = null
