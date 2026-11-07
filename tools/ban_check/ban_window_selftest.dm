//The Bans window's own parts, with no database: connections remembered, notes kept on this server, and the list's rows, groups,
//search and the player's record. Run by run_ban_selftest() (tools/ban_check/ban_selftest.dm), into its results.

/proc/ban_check_note(list/rows, text)
	for(var/list/row in rows)
		if(findtext(row["text"], text))
			return row

/proc/run_ban_selftest_window(list/out, dir)
	CONFIG_SET(flag/sql_enabled, FALSE)

	//connections
	SSbans.seen_path = "[dir]connections.json"
	SSbans.load_seen()
	SSbans.left_this_round = list()
	ban_check(out, "connections: start empty", !SSbans.seen.len, "[SSbans.seen.len]")
	SSbans.note_seen("windowgriefer", "Window Griefer", "10.20.30.40", "4242")
	SSbans.note_seen("windowalt", "Window Alt", "10.20.30.99", "4242")
	SSbans.note_seen("windowneighbour", "Window Neighbour", "10.20.30.40", "5151")
	SSbans.note_left("windowgriefer", "Greg Tide", "Assistant")
	ban_check(out, "connections: a key's last IP and computer are kept", SSbans.last_seen_address("windowgriefer", "ips") == "10.20.30.40" && SSbans.last_seen_address("windowgriefer", "cids") == "4242")
	ban_check(out, "connections: another key on the same computer is found", ("windowalt" in SSbans.seen_sharing("windowgriefer", "cids")) && !("windowneighbour" in SSbans.seen_sharing("windowgriefer", "cids")))
	ban_check(out, "connections: another key on the same address is found", ("windowneighbour" in SSbans.seen_sharing("windowgriefer", "ips")))
	ban_check(out, "connections: who left, and as whom", SSbans.left_this_round["windowgriefer"] && SSbans.seen["windowgriefer"]["name"] == "Greg Tide")
	var/datum/ban_window/W = new
	var/list/left = W.left_list()
	ban_check(out, "connections: the picker lists who left", length(left) == 1 && left[1]["key"] == "Window Griefer" && left[1]["name"] == "Greg Tide", json_encode(left))
	for(var/i in 1 to 7)
		SSbans.note_seen("windowgriefer", "Window Griefer", "10.20.31.[i]", "4242")
	var/list/entry = SSbans.seen["windowgriefer"]
	var/list/entry_ips = entry["ips"]
	ban_check(out, "connections: only the newest five addresses are kept", length(entry_ips) == 5 && SSbans.last_seen_address("windowgriefer", "ips") == "10.20.31.7" && !(SSbans.seen_by_ip["10.20.30.40"] && SSbans.seen_by_ip["10.20.30.40"]["windowgriefer"]), json_encode(entry_ips))
	ban_check(out, "connections: coming back takes them off the left list", !SSbans.left_this_round["windowgriefer"] && text2num(entry["count"]) == 8)
	SSbans.save_seen()
	SSbans.load_seen()
	ban_check(out, "connections: kept across a restart", SSbans.last_seen_address("windowgriefer", "ips") == "10.20.31.7" && ("windowalt" in SSbans.seen_sharing("windowgriefer", "cids")) && SSbans.seen["windowgriefer"]["name"] == "Greg Tide")
	var/datum/admin_rank/window_rank = new("Window Check", R_EVERYTHING, 0, R_EVERYTHING)
	var/datum/admins/window_admin = new(window_rank, "windowcheckadmin")
	var/list/found = window_admin.ban_lookup_player("Window Griefer", null, null, TRUE, TRUE, TRUE, "create", TRUE)
	ban_check(out, "with no database, a key that's gone is banned by the IP and computer it last came from", found && found[1] == "Window Griefer" && found[2] == "10.20.31.7" && found[3] == "4242", json_encode(found))
	GLOB.admin_datums -= "windowcheckadmin"
	GLOB.deadmins -= "windowcheckadmin"
	qdel(window_admin)

	//notes, with no database
	SSnotes.ledger_path = "[dir]notes.json"
	SSnotes.last_saved = null
	SSnotes.primary_ok = FALSE
	SSnotes.next_local_id = 1
	SSnotes.load()
	ban_check(out, "notes: start empty", !SSnotes.records.len)
	ban_check(out, "notes: a note is kept on this server with no database", SSnotes.add("note", "windowgriefer", "Window Griefer", "windowcheckadmin", "WindowCheckAdmin", "griefed the bar", TRUE, null, "medium") == "local")
	SSnotes.add("watchlist entry", "windowgriefer", "Window Griefer", "windowcheckadmin", "WindowCheckAdmin", "keep an eye out", TRUE, null, null)
	SSnotes.add("message", "windowgriefer", "Window Griefer", "windowcheckadmin", "WindowCheckAdmin", "read the rules", FALSE, null, null)
	SSnotes.add("memo", "windowcheckadmin", "WindowCheckAdmin", "windowcheckadmin", "WindowCheckAdmin", "a memo for admins", FALSE, null, null)
	SSnotes.add("note", "windowgriefer", "Window Griefer", "windowcheckadmin", "WindowCheckAdmin", "an expired note", FALSE, world.realtime - 10, "minor")
	var/list/rows = SSnotes.rows_for("Window Griefer")
	ban_check(out, "notes: a player's note, message and watchlist entry are read back, not the expired one", length(rows) == 3, "[length(rows)]")
	var/list/note = ban_check_note(rows, "griefed the bar")
	ban_check(out, "notes: the severity and secrecy are kept", note && note["severity"] == "medium" && note["secret"])
	ban_check(out, "notes: memos are apart from players' notes", length(SSnotes.rows_of_kind("memo")) == 1 && !ban_check_note(rows, "a memo"))
	ban_check(out, "notes: players with notes are found by part of their key", length(SSnotes.players("griefer")) == 1 && !length(SSnotes.players("nobodyhere")) && SSnotes.players("")[1]["count"] == 3)
	var/first_login = get_message_output("message", "windowgriefer")
	var/second_login = get_message_output("message", "windowgriefer")
	ban_check(out, "notes: an admin's message is shown at the next login, once", findtext(first_login, "read the rules") && !findtext("[second_login]", "read the rules"))
	ban_check(out, "notes: memos are shown to admins at login", findtext(get_message_output("memo"), "a memo for admins"))
	ban_check(out, "notes: changes are kept", SSnotes.change(note["id"], list("severity" = "high", "text" = "griefed the bar twice", "secret" = FALSE), "windowcheckadmin", "WindowCheckAdmin", "an edit<hr>"))
	var/list/changed = SSnotes.get_row(note["id"])
	ban_check(out, "notes: with the edit logged", changed && changed["severity"] == "high" && changed["text"] == "griefed the bar twice" && !changed["secret"] && findtext(SSnotes.edits_of(note["id"]), "an edit"))
	var/system = create_message("note", "windowgriefer", "system", "a system note", null, null, 0, 0, null, 0, 0)
	ban_check(out, "notes: a system note with nobody behind it is kept", system == "local" && ban_check_note(SSnotes.rows_for("windowgriefer"), "a system note"), "[system]")
	var/before_restart = length(SSnotes.rows_for("windowgriefer"))
	SSnotes.load()
	var/list/reloaded = SSnotes.get_row(note["id"])
	ban_check(out, "notes: kept across a restart", length(SSnotes.rows_for("windowgriefer")) == before_restart && reloaded && reloaded["severity"] == "high", "[before_restart]")
	SSnotes.change(note["id"], list("deleted" = TRUE))
	ban_check(out, "notes: a deleted one isn't shown", !SSnotes.get_row(note["id"]) && length(SSnotes.rows_for("windowgriefer")) == before_restart - 1)
	var/list/ids_before = SSnotes.records.Copy()
	SSnotes.add("note", "windowother", "Window Other", "windowcheckadmin", "WindowCheckAdmin", "another", FALSE, null, "none")
	var/list/ids_after = SSnotes.records - ids_before
	ban_check(out, "notes: after a restart new ids don't reuse old ones", length(ids_after) == 1 && SSnotes.records.len == ids_before.len + 1, json_encode(ids_after))

	//the list: role bans made together are one row, searchable by any part
	var/datum/ban_record/R1 = ban_check_record("Botanist", "windowgriefer", "Window Griefer", "10.20.31.7", "4242")
	var/datum/ban_record/R2 = ban_check_record("Cook", "windowgriefer", "Window Griefer", "10.20.31.7", "4242")
	var/datum/ban_record/R3 = ban_check_record("Bartender", "windowgriefer", "Window Griefer", "10.20.31.7", "4242")
	for(var/datum/ban_record/R in list(R1, R2, R3))
		R.bantime = "2026-11-07 10:00:00"
		R.bantime_rt = world.realtime - 36000
		R.amount = 3
		R.unit = "DAY"
		R.expire_rt = R.bantime_rt + 3 * 864000
		R.reason = "spilled drinks on purpose"
	SSbans.add_bans(list(R1, R2, R3))
	var/datum/ban_record/P = ban_check_record("Server", "windowperma", "Window Perma", null, null)
	P.reason = "permanent one"
	SSbans.add_bans(list(P))
	var/datum/ban_record/T = ban_check_record("Server", "windowtemp", "Window Temp", null, null)
	T.amount = 1
	T.unit = "HOUR"
	T.expire_rt = world.realtime + 36000
	T.reason = "short one"
	SSbans.add_bans(list(T))
	var/list/groups = W.group_rows(W.find_rows("windowgriefer", null, list("active")))
	ban_check(out, "the list: role bans made together are one row", length(groups) == 1 && length(groups[1]["rows"]) == 3, "[length(groups)] groups")
	ban_check(out, "the list: found by a role", length(W.find_rows("botanist", null, list("active"))) == 1)
	ban_check(out, "the list: found by part of the reason", length(W.find_rows("drinks", null, list("active"))) == 3)
	ban_check(out, "the list: found by the IP", length(W.find_rows("10.20.31.7", null, list("active"))) == 3)
	ban_check(out, "the list: found by the admin", length(W.find_rows("BanCheckAdmin", null, list("active"))) >= 5)
	var/list/shown = W.group_data(groups[1])
	ban_check(out, "the list: a group's time left and how far through", findtext(shown["left"], "left") && shown["fraction"] > 0.01 && shown["fraction"] < 0.02 && shown["minutes"] == 4320, "[shown["left"]], [shown["fraction"]], [shown["minutes"]] min")
	var/list/ordered = W.sort_groups(W.group_rows(W.find_rows("window", null, list("active"))), "ending")
	var/list/order_keys = list()
	for(var/list/G in ordered)
		var/list/first_row = G["rows"][1]
		order_keys += first_row["ckey"]
	ban_check(out, "the list: ending soonest first, then permanent ones", order_keys.Find("windowtemp") < order_keys.Find("windowgriefer") && order_keys.Find("windowgriefer") < order_keys.Find("windowperma"), order_keys.Join(", "))
	SSbans.lift(R2.id, "bancheckadmin", "BanCheckAdmin", "127.0.0.1", "1")
	ban_check(out, "the list: a lifted role isn't active, and shows with Lifted", length(W.find_rows("windowgriefer", null, list("active"))) == 2 && length(W.find_rows("windowgriefer", null, list("lifted"))) == 1)
	var/list/mixed = W.group_data(W.group_rows(W.find_rows("windowgriefer", null, list("active", "lifted")))[1])
	var/list/role_states = list()
	for(var/list/role in mixed["roles"])
		role_states[role["role"]] = role["status"]
	ban_check(out, "the list: one group, with the lifted role marked in it", role_states["Cook"] == "lifted" && role_states["Botanist"] == "active" && mixed["status"] == "active", json_encode(role_states))

	//the player's record beside the form
	W.lookup("Window Griefer")
	var/list/record = W.record_data()
	ban_check(out, "the record: their addresses, newest first", record && record["ips"][1] == "10.20.31.7" && ("4242" in record["cids"]))
	ban_check(out, "the record: the other key on their computer", record && ("Window Alt" in record["same_computer"]) && !("Window Alt" in record["same_ip"]))
	ban_check(out, "the record: their role bans with the time left, for the grid", record && record["role_bans"]["botanist"] && findtext(record["role_bans"]["botanist"]["left"], "d") && !record["role_bans"]["cook"], json_encode(record ? record["role_bans"] : null))
	ban_check(out, "the record: their notes", record && record["note_count"] == length(SSnotes.rows_for("windowgriefer")))
	W.lookup("Window Alt")
	var/list/alt_bans = W.record ? W.record["role_bans_raw"] : list()
	var/list/alt_botanist = alt_bans["botanist"]
	ban_check(out, "the record: a role ban on their computer holds the other key too", alt_botanist && alt_botanist["computer"])
	qdel(W)

//With a real database (run_ban_check.sh with DB_PORT set): notes in it, read and changed there, kept here while it's gone and
//sent when it's back; the list and the record read from it; a role added to a ban already in it joining that ban
/proc/run_ban_selftest_window_db(list/out, prefix, db_port)
	CONFIG_SET(flag/sql_enabled, TRUE)
	CONFIG_SET(number/port, db_port)
	SSdbcore.failed_connections = 0
	SSdbcore.failed_connection_timeout = 0
	if(!SSdbcore.Connect())
		ban_check(out, "notes in the database: connects", FALSE, SSdbcore.ErrorMsg())
		return
	var/messages = format_table_name("messages")
	SSnotes.ledger_path = "[prefix]notes.json"
	SSnotes.last_saved = null
	SSnotes.primary_ok = FALSE
	SSnotes.records = list()
	SSnotes.refused = list()
	ban_check(out, "notes in the database: a note goes to it", SSnotes.add("note", "dbnoteplayer", "DB Note Player", "bancheckadmin", "BanCheckAdmin", "db note one", TRUE, null, "high") == "database")
	ban_check(out, "notes in the database: with its severity and secrecy", ban_check_sql("SELECT COUNT(*) FROM [messages] WHERE targetckey = 'dbnoteplayer' AND severity = 'high' AND secret = 1 AND text = 'db note one'") == "1")
	SSnotes.add("message", "dbnoteplayer", "DB Note Player", "bancheckadmin", "BanCheckAdmin", "db message", FALSE, null, null)
	SSnotes.add("memo", "bancheckadmin", "BanCheckAdmin", "bancheckadmin", "BanCheckAdmin", "db memo", FALSE, world.realtime + 864000, null)
	ban_check(out, "notes in the database: an expiry goes in on its clock", ban_check_sql("SELECT TIMESTAMPDIFF(HOUR, NOW(), expire_timestamp) FROM [messages] WHERE text = 'db memo'") in list("23", "24"))
	var/list/rows = SSnotes.rows_for("dbnoteplayer")
	var/list/note = ban_check_note(rows, "db note one")
	ban_check(out, "notes in the database: read back", length(rows) == 2 && note && note["severity"] == "high" && note["secret"] && !note["local"], "[length(rows)]")
	var/list/players = SSnotes.players("dbnote")
	ban_check(out, "notes in the database: the players list counts them", length(players) == 1 && players[1]["count"] == 2, json_encode(players))
	ban_check(out, "notes in the database: memos", ban_check_note(SSnotes.rows_of_kind("memo"), "db memo"))
	ban_check(out, "notes in the database: a change", note && SSnotes.change(note["id"], list("severity" = "minor", "text" = "db note edited", "expire_seconds" = 3600, "secret" = FALSE), "bancheckadmin", "BanCheckAdmin", "db edit<hr>") && ban_check_sql("SELECT COUNT(*) FROM [messages] WHERE id = [text2num(note["id"])] AND severity = 'minor' AND text = 'db note edited' AND secret = 0 AND lasteditor = 'bancheckadmin' AND edits LIKE '%db edit%' AND expire_timestamp IS NOT NULL") == "1")
	var/list/one = note ? SSnotes.get_row(note["id"]) : null
	ban_check(out, "notes in the database: one read by id, with its edit log", one && one["text"] == "db note edited" && findtext(SSnotes.edits_of(note["id"]), "db edit"))
	var/output = get_message_output("message", "dbnoteplayer")
	ban_check(out, "notes in the database: a message shown at login is marked read", findtext(output, "db message") && ban_check_sql("SELECT COUNT(*) FROM [messages] WHERE targetckey = 'dbnoteplayer' AND type = 'message sent'") == "1")
	ban_check(out, "notes in the database: deleted", note && SSnotes.change(note["id"], list("deleted" = TRUE)) && !SSnotes.get_row(note["id"]) && ban_check_sql("SELECT deleted FROM [messages] WHERE id = [text2num(note["id"])]") == "1")
	//gone, then back
	SSdbcore.Disconnect()
	CONFIG_SET(number/port, 9)
	ban_check(out, "notes, database gone: a note is kept here", SSnotes.add("note", "dbnoteplayer", "DB Note Player", "bancheckadmin", "BanCheckAdmin", "made while gone", FALSE, null, "medium") == "local")
	ban_check(out, "notes, database gone: and read from here meanwhile", ban_check_note(SSnotes.rows_for("dbnoteplayer"), "made while gone"))
	CONFIG_SET(number/port, db_port)
	SSdbcore.failed_connections = 0
	SSdbcore.failed_connection_timeout = 0
	UNTIL(!SSnotes.db_busy)
	SSnotes.db_flush()
	ban_check(out, "notes, database back: the one made meanwhile is sent, and not kept here", !SSnotes.has_unsent() && !SSnotes.records.len && ban_check_sql("SELECT severity FROM [messages] WHERE text = 'made while gone'") == "medium")
	var/count = 0
	for(var/list/row in SSnotes.rows_for("dbnoteplayer"))
		if(row["text"] == "made while gone")
			count++
	ban_check(out, "notes, database back: read back once, not twice", count == 1, "[count]")
	//the list and the record, from the database
	var/datum/ban_window/W = new
	var/list/found = W.find_rows("dbmirror", null, list("active", "expired", "lifted"))
	ban_check(out, "the list from the database: found by key", length(found) == 2, "[length(found)]")
	ban_check(out, "the list from the database: the two made together are one row", length(W.group_rows(found)) == 1)
	ban_check(out, "the list from the database: found by reason", length(W.find_rows("mirrored", null, list("active"))) == 2)
	ban_check(out, "the list from the database: a lifted one only with Lifted", length(W.find_rows("dbserverban", null, list("lifted"))) == 1 && !length(W.find_rows("dbserverban", null, list("active"))))
	W.lookup("DB Role Ban")
	ban_check(out, "the record from the database: their bans", W.record && length(W.record["groups_raw"]) == 1)
	var/list/mirror_rows = W.find_rows("dbmirror", null, list("active"))
	var/list/lead = mirror_rows[1]
	var/datum/ban_record/added = ban_check_record("Janitor", "dbmirror", "DB Mirror", "10.5.4.3", null)
	added.bantime = lead["bantime"]
	added.bantime_rt = lead["bantime_rt"]
	added.exact_bantime = TRUE
	ban_check(out, "a role added to a ban in the database goes to it", SSbans.add_bans(list(added)) == "database")
	found = W.find_rows("dbmirror", null, list("active"))
	ban_check(out, "and joins that ban, one row", length(found) == 3 && length(W.group_rows(found)) == 1, "[length(found)] rows, [length(W.group_rows(found))] groups")
	qdel(W)
