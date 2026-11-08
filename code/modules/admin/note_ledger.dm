//Admin notes, messages, watchlist entries and memos with no database, or with it out of reach. Before, they lived only in the
//database: with SQL off a ban wrote no note, its severity went nowhere, and every notes link said "Failed to establish database
//connection". Now:
//	with SQL off, they're kept here, in data/notes.json (the one before in data/notes.json.bak);
//	with the database on, it's still where they live and are read from, and this only holds the ones made while it couldn't be
//	reached (ids "L3"), sent every minute once it's back. A change to one already in the database needs the database.
//Every reader gets rows in one shape (note_row()), wherever they came from, newest first.

//Longest text the messages table's column takes
#define NOTE_TEXT_MAX 2048

/datum/note_record
	var/id //"L3": made here and not in the database (yet)
	var/kind //note, message, message sent, watchlist entry, memo
	var/targetckey
	var/target_key
	var/adminckey
	var/admin_key
	var/text
	var/timestamp //text, as the database has it
	var/timestamp_rt
	var/server
	var/round_id
	var/secret = FALSE
	var/expire_rt //world.realtime it stops showing, null for never
	var/severity //none, minor, medium, high, or null
	var/lasteditor
	var/lasteditor_key
	var/edits
	var/deleted = FALSE

GENERAL_PROTECT_DATUM(/datum/note_record)

/datum/note_record/proc/fields()
	var/static/list/names = list("id", "kind", "targetckey", "target_key", "adminckey", "admin_key", "text", "timestamp", "timestamp_rt", "server", "round_id", "secret", "expire_rt", "severity", "lasteditor", "lasteditor_key", "edits", "deleted")
	return names

/datum/note_record/proc/to_list()
	var/static/list/times = list("timestamp_rt", "expire_rt")
	. = list()
	for(var/field in fields())
		var/value = vars[field]
		if(isnum(value) && (field in times))
			value = num2text(value, 12)
		.[field] = value

/datum/note_record/proc/from_list(list/L)
	var/static/list/times = list("timestamp_rt", "expire_rt")
	for(var/field in fields())
		var/value = L[field]
		if(istext(value) && (field in times))
			value = text2num(value)
		vars[field] = value

/datum/note_record/proc/is_shown()
	return !deleted && (!expire_rt || expire_rt > world.realtime)

/datum/note_record/proc/row()
	return note_row(id, kind, targetckey, target_key || targetckey, admin_key || adminckey, text, timestamp, server, round_id, secret, severity, expire_rt ? SQLtime(expire_rt) : null, max(0, round((world.realtime - timestamp_rt) / (24 HOURS))), lasteditor_key || lasteditor, edits, TRUE)

//Into the database's messages table. Times are counted back from NOW(), so one kept here while the database was down lands on
//its clock; exact_timestamp (an old note brought over) keeps its own date. TRUE if it went in.
/datum/note_record/proc/db_insert(exact_timestamp, warn = FALSE, async = TRUE)
	var/datum/DBQuery/query_note_insert = SSdbcore.NewQuery({"INSERT INTO [format_table_name("messages")]
		(type, targetckey, adminckey, text, timestamp, server, server_ip, server_port, round_id, secret, expire_timestamp, severity, lasteditor, edits, deleted)
		VALUES (:kind, :targetckey, :adminckey, :text, IFNULL(:exact_timestamp, NOW() - INTERVAL :age SECOND), :server, INET_ATON(:server_ip), :server_port, :round_id, :secret,
		IF(:expire_seconds IS NULL, NULL, NOW() + INTERVAL :expire_seconds SECOND), :severity, :lasteditor, :edits, :deleted)"}, list(
		"kind" = "[kind]", //NOT NULL columns: "" for a missing one, as the old quoted SQL gave
		"targetckey" = "[targetckey]",
		"adminckey" = "[adminckey]",
		"text" = "[text]",
		"exact_timestamp" = exact_timestamp || null,
		"age" = max(0, round((world.realtime - timestamp_rt) / 10)),
		"server" = server || null,
		"server_ip" = world.internet_address || "0",
		"server_port" = world.port,
		"round_id" = text2num(round_id) || 0,
		"secret" = secret ? 1 : 0,
		"expire_seconds" = expire_rt ? max(1, round((expire_rt - world.realtime) / 10)) : null,
		"severity" = (severity in list("none", "minor", "medium", "high")) ? severity : null,
		"lasteditor" = lasteditor || null,
		"edits" = edits || null,
		"deleted" = deleted ? 1 : 0))
	. = warn ? query_note_insert.warn_execute(async) : query_note_insert.Execute(async)
	qdel(query_note_insert)

//One note as every reader gets it
/proc/note_row(id, kind, target_ckey, target_key, admin_key, text, timestamp, server, round_id, secret, severity, expires, age_days, editor_key, edits, local)
	return list("id" = "[id]", "kind" = kind, "target_ckey" = target_ckey, "target_key" = target_key, "admin_key" = admin_key, "text" = text, "timestamp" = timestamp, "server" = server, "round_id" = round_id, "secret" = !!secret, "severity" = severity, "expires" = expires, "age_days" = age_days, "editor_key" = editor_key, "edits" = edits, "local" = !!local)

/proc/cmp_note_rows_newest(list/a, list/b)
	return sorttext(a["timestamp"], b["timestamp"])

SUBSYSTEM_DEF(notes)
	name = "Notes"
	wait = 1 MINUTES
	flags = SS_NO_INIT|SS_BACKGROUND
	runlevels = RUNLEVEL_LOBBY|RUNLEVELS_DEFAULT

	var/list/records = list() //id = /datum/note_record: every one kept here
	var/next_local_id = 1
	var/ledger_path = "data/notes.json"
	var/last_saved
	var/primary_ok = FALSE
	var/db_busy = FALSE
	var/list/refused = list() //ones the database said no to this round: still kept here, tried again next round

/datum/controller/subsystem/notes/stat_entry()
	..("N:[records.len]")

/datum/controller/subsystem/notes/Recover()
	records = SSnotes.records
	next_local_id = SSnotes.next_local_id
	ledger_path = SSnotes.ledger_path
	last_saved = SSnotes.last_saved
	primary_ok = SSnotes.primary_ok
	refused = SSnotes.refused

/datum/controller/subsystem/notes/can_vv_get(var_name)
	return !(var_name in list(NAMEOF(src, records), NAMEOF(src, last_saved))) && ..()

/datum/controller/subsystem/notes/vv_edit_var(var_name, var_value)
	return FALSE

/datum/controller/subsystem/notes/CanProcCall(procname)
	return FALSE

/datum/controller/subsystem/notes/fire()
	if(!db_busy && CONFIG_GET(flag/sql_enabled) && has_unsent())
		INVOKE_ASYNC(src, PROC_REF(db_flush))

/datum/controller/subsystem/notes/proc/has_unsent()
	for(var/id in records)
		if(!refused[id])
			return TRUE

//Called from world/New(), with the bans
/datum/controller/subsystem/notes/proc/load()
	var/list/data = SSbans.read_ledger(ledger_path)
	primary_ok = !!data
	if(!data)
		data = SSbans.read_ledger("[ledger_path].bak")
		if(data)
			log_world("Notes: [ledger_path] couldn't be read, loaded the backup")
	records = list()
	last_saved = null
	if(data)
		next_local_id = max(1, text2num(data["next_local_id"]))
		for(var/list/L in data["records"])
			var/datum/note_record/R = new
			R.from_list(L)
			if(R.id)
				records[R.id] = R
	log_world("Notes: [records.len] from [ledger_path]")

/datum/controller/subsystem/notes/proc/save()
	var/list/out = list()
	for(var/id in records)
		var/datum/note_record/R = records[id]
		out += list(R.to_list())
	var/text = json_encode(list("version" = 1, "next_local_id" = next_local_id, "records" = out))
	if(text == last_saved)
		return
	if(primary_ok && fexists(ledger_path))
		fcopy(ledger_path, "[ledger_path].bak")
	fdel(ledger_path)
	text2file(text, ledger_path)
	last_saved = text
	primary_ok = TRUE

/datum/controller/subsystem/notes/proc/use_db()
	return CONFIG_GET(flag/sql_enabled) && SSdbcore.Connect()

//"database" or "local" (kept here), or null if the database refused it. expire_rt: world.realtime it stops showing, or null.
/datum/controller/subsystem/notes/proc/add(kind, target_ckey, target_key, admin_ckey, admin_key, text, secret, expire_rt, severity, timestamp)
	var/datum/note_record/R = new
	R.kind = kind
	R.targetckey = target_ckey
	R.target_key = target_key
	R.adminckey = admin_ckey
	R.admin_key = admin_key
	R.text = text
	R.timestamp = timestamp || SQLtime()
	R.timestamp_rt = world.realtime
	R.server = CONFIG_GET(string/serversqlname)
	R.round_id = GLOB.round_id
	R.secret = secret ? TRUE : FALSE
	R.expire_rt = expire_rt
	R.severity = severity
	if(use_db())
		if(!R.db_insert(timestamp, warn = TRUE)) //an old note brought over keeps its date
			return
		return "database"
	R.id = "L[next_local_id++]"
	records[R.id] = R
	save()
	return "local"

//The SELECT columns every database read uses, in note_row()'s order after the first
/datum/controller/subsystem/notes/proc/db_columns()
	var/player = format_table_name("player")
	return "id, type, targetckey, IFNULL((SELECT byond_key FROM [player] WHERE ckey = targetckey), targetckey), IFNULL((SELECT byond_key FROM [player] WHERE ckey = adminckey), adminckey), text, timestamp, server, round_id, secret, severity, expire_timestamp, DATEDIFF(NOW(), timestamp), IFNULL((SELECT byond_key FROM [player] WHERE ckey = lasteditor), lasteditor), edits"

//where: SQL with :name for its values, which are in where_args
/datum/controller/subsystem/notes/proc/db_rows(where, list/where_args, limit)
	var/list/arguments = where_args ? where_args.Copy() : list()
	arguments["limit"] = limit || 100000
	var/datum/DBQuery/query_notes = SSdbcore.NewQuery("SELECT [db_columns()] FROM [format_table_name("messages")] WHERE [where] ORDER BY timestamp DESC LIMIT :limit", arguments)
	if(!query_notes.warn_execute())
		qdel(query_notes)
		return
	. = list()
	while(query_notes.NextRow())
		var/list/i = query_notes.item
		. += list(note_row(i[1], i[2], i[3], i[4], i[5], i[6], i[7], i[8], i[9], text2num(i[10]), i[11], i[12], text2num(i[13]), i[14], i[15], FALSE))
	qdel(query_notes)

//Showing notes: the database's (if it answers) and the ones kept here. db_ok: set to whether the database was read.
/datum/controller/subsystem/notes/proc/rows(where_sql, list/where_args, datum/callback/local_check, limit)
	. = list()
	if(use_db())
		var/list/found = db_rows(where_sql, where_args, limit)
		if(found)
			. += found
	for(var/id in records)
		var/datum/note_record/R = records[id]
		if(R.is_shown() && local_check.Invoke(R))
			. += list(R.row())
	sortTim(., GLOBAL_PROC_REF(cmp_note_rows_newest))

//A player's messages, watchlist entries and notes
/datum/controller/subsystem/notes/proc/rows_for(target_ckey)
	target_ckey = ckey(target_ckey)
	if(!target_ckey)
		return list()
	return rows("type <> 'memo' AND targetckey = :target_ckey AND deleted = 0 AND (expire_timestamp > NOW() OR expire_timestamp IS NULL)", list("target_ckey" = target_ckey), CALLBACK(src, PROC_REF(local_for), target_ckey))

/datum/controller/subsystem/notes/proc/local_for(target_ckey, datum/note_record/R)
	return R.kind != "memo" && R.targetckey == target_ckey

//Every memo, or every watchlist entry
/datum/controller/subsystem/notes/proc/rows_of_kind(kind)
	return rows("type = :kind AND deleted = 0 AND (expire_timestamp > NOW() OR expire_timestamp IS NULL)", list("kind" = kind), CALLBACK(src, PROC_REF(local_of_kind), kind))

/datum/controller/subsystem/notes/proc/local_of_kind(kind, datum/note_record/R)
	return R.kind == kind

//Players with any shown note, message or watchlist entry, whose key has the text in it: list(list("ckey", "key", "count")), by key
/datum/controller/subsystem/notes/proc/players(search)
	search = ckey(search)
	var/list/found = list() //ckey = list
	if(use_db())
		var/player = format_table_name("player")
		var/datum/DBQuery/query_note_players = SSdbcore.NewQuery("SELECT targetckey, IFNULL((SELECT byond_key FROM [player] WHERE ckey = targetckey), targetckey), COUNT(*) FROM [format_table_name("messages")] WHERE type <> 'memo' AND deleted = 0 AND (expire_timestamp > NOW() OR expire_timestamp IS NULL) AND (:search IS NULL OR INSTR(targetckey, :search) > 0) GROUP BY targetckey ORDER BY targetckey LIMIT 500",
			list("search" = search || null))
		if(query_note_players.warn_execute())
			while(query_note_players.NextRow())
				found[query_note_players.item[1]] = list("ckey" = query_note_players.item[1], "key" = query_note_players.item[2], "count" = text2num(query_note_players.item[3]))
		qdel(query_note_players)
	for(var/id in records)
		var/datum/note_record/R = records[id]
		if(R.kind == "memo" || !R.is_shown() || (search && !findtext(R.targetckey, search)))
			continue
		var/list/entry = found[R.targetckey]
		if(!entry)
			entry = found[R.targetckey] = list("ckey" = R.targetckey, "key" = R.target_key || R.targetckey, "count" = 0)
		entry["count"]++
	. = list()
	for(var/player_ckey in sortList(found))
		. += list(found[player_ckey])

//One shown note by id, from here or the database
/datum/controller/subsystem/notes/proc/get_row(id)
	var/datum/note_record/R = records["[id]"]
	if(R)
		return R.is_shown() ? R.row() : null
	var/db_id = text2num(id)
	if(db_id && use_db())
		var/list/found = db_rows("id = :id AND deleted = 0", list("id" = db_id))
		if(length(found))
			return found[1]

/datum/controller/subsystem/notes/proc/edits_of(id)
	var/datum/note_record/R = records["[id]"]
	if(R)
		return R.edits
	var/db_id = text2num(id)
	if(db_id && use_db())
		var/datum/DBQuery/query_note_edits = SSdbcore.NewQuery("SELECT edits FROM [format_table_name("messages")] WHERE id = :id", list("id" = db_id))
		if(query_note_edits.warn_execute() && query_note_edits.NextRow())
			. = query_note_edits.item[1]
		qdel(query_note_edits)

//A change to one. changes: "text", "severity", "secret" (TRUE/FALSE), "expire_seconds" (from now; 0 for never), "deleted",
//"kind". edit_text goes on the end of its edit log. TRUE if done; the reason in a message to usr if not.
/datum/controller/subsystem/notes/proc/change(id, list/changes, editor_ckey, editor_key, edit_text)
	var/datum/note_record/R = records["[id]"]
	if(R)
		if(!isnull(changes["text"]))
			R.text = changes["text"]
		if(!isnull(changes["severity"]))
			R.severity = changes["severity"]
		if(!isnull(changes["secret"]))
			R.secret = changes["secret"] ? TRUE : FALSE
		if(!isnull(changes["expire_seconds"]))
			R.expire_rt = changes["expire_seconds"] ? world.realtime + changes["expire_seconds"] * 10 : null
		if(changes["deleted"])
			R.deleted = TRUE
		if(changes["kind"])
			R.kind = changes["kind"]
		if(editor_ckey)
			R.lasteditor = editor_ckey
			R.lasteditor_key = editor_key
		if(edit_text)
			R.edits = "[R.edits][edit_text]"
		save()
		return TRUE
	var/db_id = text2num(id)
	if(!db_id)
		return FALSE
	if(!use_db())
		to_chat(usr, "<span class='danger'>That one is in the database, which can't be reached right now. Notes made since it went are kept here; changing one already in it has to wait until it's back.</span>", confidential=TRUE)
		return FALSE
	var/list/sets = list()
	var/list/arguments = list("id" = db_id)
	if(!isnull(changes["text"]))
		sets += "text = :text"
		arguments["text"] = changes["text"]
	if(!isnull(changes["severity"]))
		sets += "severity = :severity"
		arguments["severity"] = changes["severity"]
	if(!isnull(changes["secret"]))
		sets += "secret = :secret"
		arguments["secret"] = changes["secret"] ? 1 : 0
	if(!isnull(changes["expire_seconds"]))
		sets += "expire_timestamp = IF(:expire_seconds > 0, NOW() + INTERVAL :expire_seconds SECOND, NULL)"
		arguments["expire_seconds"] = round(changes["expire_seconds"])
	if(changes["deleted"])
		sets += "deleted = 1"
	if(changes["kind"])
		sets += "type = :kind"
		arguments["kind"] = changes["kind"]
	if(editor_ckey)
		sets += "lasteditor = :editor"
		arguments["editor"] = editor_ckey
	if(edit_text)
		sets += "edits = CONCAT(IFNULL(edits, ''), :edit_text)"
		arguments["edit_text"] = edit_text
	if(!sets.len)
		return FALSE
	var/datum/DBQuery/query_note_change = SSdbcore.NewQuery("UPDATE [format_table_name("messages")] SET [sets.Join(", ")] WHERE id = :id AND deleted = 0", arguments)
	. = query_note_change.warn_execute()
	qdel(query_note_change)

//The minute's check, once the database answers: what was made here goes to it, and stops being kept here
/datum/controller/subsystem/notes/proc/db_flush()
	if(db_busy)
		return
	db_busy = TRUE
	if(!SSdbcore.Connect())
		db_busy = FALSE
		return
	var/sent = 0
	for(var/id in records.Copy())
		var/datum/note_record/R = records[id]
		if(!R || refused[id])
			continue
		if(!R.db_insert(async = FALSE))
			if(!SSdbcore.IsConnected())
				break
			refused[id] = TRUE
			log_sql("Notes: the database refused [R.kind] [R.id] for [R.targetckey], keeping it on this server")
			continue
		records -= id
		sent++
	if(sent)
		log_sql("Notes: sent [sent] note\s, message\s or memo\s made while the database was out of reach")
		message_admins("[sent] note\s, message\s or memo\s made while the database was out of reach have been saved to it.")
	save()
	db_busy = FALSE
