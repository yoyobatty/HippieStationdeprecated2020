//Notes, messages, watchlist entries and memos: SSnotes keeps them (code/modules/admin/note_ledger.dm), in the database when
//there is one and on this server when there isn't. They're read and written in the Bans window's Notes tab
//(hippiestation/code/modules/admin/ban_window.dm); these procs are what the old links and other code call.

//How long a note shows, as the window and the prompts offer it: name = seconds, 0 for always
GLOBAL_LIST_INIT(note_expiry_choices, list("Never" = 0, "1 day" = 86400, "1 week" = 604800, "1 month" = 2592000, "3 months" = 7776000, "1 year" = 31536000))

//The admin's Bans window on its Notes tab, if usr is an admin who can have one
/proc/open_notes_window(view, target_ckey, kind, compose)
	var/client/C = usr?.client
	if(!C?.holder)
		return
	C.open_ban_window("notes", list("view" = view, "ckey" = target_ckey, "compose" = compose, "kind" = kind))

//Who a ckey is, as written: the last connection's key, else the ckey
/proc/note_key_of(target_ckey)
	var/client/C = GLOB.directory[target_ckey]
	if(C)
		return C.key
	var/list/entry = SSbans.seen[target_ckey]
	if(entry && entry["key"])
		return entry["key"]
	return target_ckey

/proc/note_is_for_player(kind)
	return kind == "note" || kind == "message" || kind == "message sent" || kind == "watchlist entry"

//With text, makes one; with none (an admin's link), opens the window to write it in. expiry: seconds it shows for, 0 for always.
/proc/create_message(type, target_key, admin_ckey, text, timestamp, server, secret, logged = 1, browse, expiry, note_severity)
	if(!type)
		return
	if(!text)
		open_notes_window(note_is_for_player(type) ? "player" : (type == "memo" ? "memos" : "watchlist"), ckey(target_key), type, TRUE)
		return
	if(usr && QDELETED(usr)) //an admin gone mid-way; system notes (cid randomizer, note conversion) can come with no usr at all
		return
	var/target_ckey = ckey(target_key)
	if(!admin_ckey)
		admin_ckey = usr?.ckey
		if(!admin_ckey)
			return
	var/admin_key = (usr?.ckey == admin_ckey) ? usr.key : note_key_of(admin_ckey)
	if(!target_ckey)
		target_ckey = admin_ckey //a memo is filed under its writer
	if(!target_key)
		target_key = note_key_of(target_ckey)
	if(length_char(text) > NOTE_TEXT_MAX)
		to_chat(usr, "<span class='danger'>That [type] is [length_char(text)] characters long; the most it can be is [NOTE_TEXT_MAX].</span>", confidential=TRUE)
		return
	if(note_severity)
		note_severity = lowertext(note_severity)
		if(!(note_severity in list("none", "minor", "medium", "high")))
			note_severity = null
	else
		note_severity = null //system notes pass 0
	var/expire_rt = (isnum(expiry) && expiry > 0) ? world.realtime + expiry * 10 : null
	var/stored = SSnotes.add(type, target_ckey, target_key, admin_ckey, admin_key, text, secret, expire_rt, note_severity, timestamp)
	if(!stored)
		return
	if(stored == "local" && CONFIG_GET(flag/sql_enabled))
		to_chat(usr, "<span class='danger'>The database couldn't be reached. The [type] is kept on this server and goes to the database when it's back.</span>", confidential=TRUE)
	if(logged)
		var/for_text = note_is_for_player(type) ? " for [target_key]" : ""
		log_admin_private("[key_name(usr)] has created a [type][for_text]: [text]")
		message_admins("[key_name_admin(usr)] has created a [type][for_text]:<br>[text]")
		admin_ticket_log(target_ckey, "<font color='blue'>[key_name_admin(usr)] has created a [type][for_text]</font>")
		admin_ticket_log(target_ckey, text)
		if(browse)
			open_notes_window(type == "memo" ? "memos" : (type == "watchlist entry" ? "watchlist" : "player"), target_ckey)
	return stored

//The note before a change, or null (and a message) if it's gone
/proc/note_before_change(message_id)
	. = SSnotes.get_row(message_id)
	if(!.)
		to_chat(usr, "<span class='danger'>That note is gone: deleted, expired, or in a database that can't be reached.</span>", confidential=TRUE)

/proc/note_about(list/row)
	return "[row["kind"]][note_is_for_player(row["kind"]) ? " for [row["target_key"]]" : ""] made by [row["admin_key"]]"

/proc/note_set_text(message_id, new_text)
	var/list/row = note_before_change(message_id)
	if(!row || !new_text || new_text == row["text"])
		return
	if(length_char(new_text) > NOTE_TEXT_MAX)
		to_chat(usr, "<span class='danger'>That's [length_char(new_text)] characters long; the most it can be is [NOTE_TEXT_MAX].</span>", confidential=TRUE)
		return
	if(!SSnotes.change(message_id, list("text" = new_text), usr.ckey, usr.key, "Edited by [usr.key] on [SQLtime()] from<br>[row["text"]]<br>to<br>[new_text]<hr>"))
		return
	log_admin_private("[key_name(usr)] has edited a [note_about(row)] from [row["text"]] to [new_text]")
	message_admins("[key_name_admin(usr)] has edited a [note_about(row)] from<br>[row["text"]]<br>to<br>[new_text]")
	return TRUE

//seconds: from now, 0 for never
/proc/note_set_expiry(message_id, seconds)
	var/list/row = note_before_change(message_id)
	if(!row)
		return
	var/old_text = row["expires"] || "non-expiring"
	var/new_text = seconds ? SQLtime(world.realtime + seconds * 10) : "non-expiring"
	if(!SSnotes.change(message_id, list("expire_seconds" = seconds), usr.ckey, usr.key, "Expiration time edited by [usr.key] on [SQLtime()] from [old_text] to [new_text]<hr>"))
		return
	log_admin_private("[key_name(usr)] has edited the expiration time of a [note_about(row)] from [old_text] to [new_text]")
	message_admins("[key_name_admin(usr)] has edited the expiration time of a [note_about(row)] from [old_text] to [new_text]")
	return TRUE

/proc/note_set_severity(message_id, severity)
	var/list/row = note_before_change(message_id)
	if(!row || !(severity in list("none", "minor", "medium", "high")) || severity == row["severity"])
		return
	var/old = row["severity"] || "NA"
	if(!SSnotes.change(message_id, list("severity" = severity), usr.ckey, usr.key, "Note severity edited by [usr.key] on [SQLtime()] from [old] to [severity]<hr>"))
		return
	log_admin_private("[key_name(usr)] has edited the severity of a [note_about(row)] from [old] to [severity]")
	message_admins("[key_name_admin(usr)] has edited the severity of a [note_about(row)] from [old] to [severity]")
	return TRUE

/proc/note_toggle_secret(message_id)
	var/list/row = note_before_change(message_id)
	if(!row)
		return
	var/now_secret = !row["secret"]
	if(!SSnotes.change(message_id, list("secret" = now_secret), usr.ckey, usr.key, "Made [now_secret ? "secret" : "not secret"] by [usr.key] on [SQLtime()]<hr>"))
		return
	log_admin_private("[key_name(usr)] has toggled [row["target_key"]]'s [row["kind"]] made by [row["admin_key"]] to [now_secret ? "secret" : "not secret"]")
	message_admins("[key_name_admin(usr)] has toggled [row["target_key"]]'s [row["kind"]] made by [row["admin_key"]] to [now_secret ? "secret" : "not secret"]")
	return TRUE

/proc/note_delete(message_id)
	var/list/row = note_before_change(message_id)
	if(!row)
		return
	if(!SSnotes.change(message_id, list("deleted" = TRUE)))
		return
	var/for_player = note_is_for_player(row["kind"])
	var/whom = for_player ? "for [row["target_key"]]" : "made by [row["admin_key"]]"
	log_admin_private("[key_name(usr)] has deleted a [row["kind"]] [whom]: [row["text"]]")
	message_admins("[key_name_admin(usr)] has deleted a [row["kind"]] [whom]:<br>[row["text"]]")
	return TRUE

//Where the old links went back to after a change
/proc/note_show_after(list/row, browse)
	if(!row)
		return
	if(browse || !note_is_for_player(row["kind"]))
		open_notes_window(row["kind"] == "memo" ? "memos" : "watchlist")
	else
		open_notes_window("player", row["target_ckey"])

/proc/delete_message(message_id, logged = 1, browse)
	var/list/row = SSnotes.get_row(message_id)
	if(note_delete(message_id))
		note_show_after(row, browse)

/proc/edit_message(message_id, browse)
	var/list/row = note_before_change(message_id)
	if(!row)
		return
	var/new_text = tgui_input_text(usr, "Input new [row["kind"]]", "New [row["kind"]]", row["text"], multiline = TRUE)
	if(note_set_text(message_id, new_text))
		note_show_after(row, browse)

/proc/edit_message_expiry(message_id, browse)
	var/list/row = note_before_change(message_id)
	if(!row)
		return
	var/choice = tgui_input_list(usr, "Show this [row["kind"]] for how long, from now?", "Expiry time", GLOB.note_expiry_choices)
	if(!choice)
		return
	if(note_set_expiry(message_id, GLOB.note_expiry_choices[choice]))
		note_show_after(row, browse)

/proc/edit_message_severity(message_id)
	var/list/row = note_before_change(message_id)
	if(!row)
		return
	var/new_severity = tgui_input_list(usr, "Set the severity of the note.", "Severity", list("high", "medium", "minor", "none"))
	if(note_set_severity(message_id, new_severity))
		note_show_after(row)

/proc/toggle_message_secrecy(message_id)
	var/list/row = SSnotes.get_row(message_id)
	if(note_toggle_secret(message_id))
		note_show_after(row)

//Admins get the window; a player looking at their own notes (linkless) gets them as a page, secret ones left out
/proc/browse_messages(type, target_ckey, index, linkless = FALSE, filter, agegate = FALSE)
	if(!linkless)
		if(type == "memo")
			open_notes_window("memos")
		else if(type == "watchlist entry")
			open_notes_window(filter ? "watchlist_online" : "watchlist")
		else if(target_ckey)
			open_notes_window("player", ckey(target_ckey))
		else
			open_notes_window("index")
		return
	target_ckey = ckey(target_ckey)
	var/list/output = list("<h2><center>[note_key_of(target_ckey)]</center></h2>")
	var/list/sections = list("Messages" = list(), "Watchlist" = list(), "Notes" = list())
	for(var/list/row in SSnotes.rows_for(target_ckey))
		if(row["secret"])
			continue
		var/entry = "<p><b>[row["timestamp"]] | [row["server"]] | [row["admin_key"]][row["expires"] ? " | Expires [row["expires"]]" : ""]</b></p><p>[row["text"]]</p><hr style='background:#000000; border:0; height:1px'>"
		switch(row["kind"])
			if("message", "message sent")
				sections["Messages"] += entry
			if("watchlist entry")
				sections["Watchlist"] += entry
			if("note")
				sections["Notes"] += entry
	var/any = FALSE
	for(var/section in sections)
		var/list/entries = sections[section]
		if(entries.len)
			any = TRUE
			output += "<h2>[section]</h2>"
			output += entries
	if(!any)
		output += "<center>Nothing here.</center>"
	var/datum/browser/browser = new(usr, "Note panel", "Notes", 700, 500)
	browser.set_content(jointext(output, ""))
	browser.open()

//At login: memos for admins, a player's unread messages (marked read), and admins told about anyone on the watchlist
/proc/get_message_output(type, target_ckey)
	if(!type)
		return
	var/list/rows
	if(type == "memo")
		rows = SSnotes.rows_of_kind("memo")
	else
		rows = list()
		for(var/list/row in SSnotes.rows_for(target_ckey))
			if(row["kind"] == type)
				rows += list(row)
	var/output
	for(var/list/row in rows)
		switch(type)
			if("message")
				output += "<font color='red' size='3'><b>Admin message left by <span class='prefix'>[row["admin_key"]]</span> on [row["timestamp"]]</b></font>"
				output += "<br><font color='red'>[row["text"]]</font><br>"
				SSnotes.change(row["id"], list("kind" = "message sent"))
			if("watchlist entry")
				message_admins("<font color='red'><B>Notice: </B></font><font color='blue'>[key_name_admin(target_ckey)] has been on the watchlist since [row["timestamp"]] and has just connected - Reason: [row["text"]]</font>")
				send2irc_adminless_only("Watchlist", "[key_name(target_ckey)] is on the watchlist and has just connected - Reason: [row["text"]]")
			if("memo")
				output += "<span class='memo'>Memo by <span class='prefix'>[row["admin_key"]]</span> on [row["timestamp"]]"
				if(row["editor_key"])
					output += "<br><span class='memoedit'>Last edit by [row["editor_key"]] <A href='?_src_=holder;[HrefToken()];messageedits=[row["id"]]'>(Click here to see edit log)</A></span>"
				output += "<br>[row["text"]]</span><br>"
	return output

#define NOTESFILE "data/player_notes.sav"
//if the AUTOCONVERT_NOTES is turned on, anytime a player connects this will be run to try and add all their notes to the databas
/proc/convert_notes_sql(ckey)
	if(!fexists(NOTESFILE))
		return

	var/savefile/notesfile = new(NOTESFILE)
	if(!notesfile)
		log_game("Error: Cannot access [NOTESFILE]")
		return
	notesfile.cd = "/[ckey]"
	while(!notesfile.eof)
		var/notetext
		notesfile >> notetext
		var/server
		var/ssqlname = CONFIG_GET(string/serversqlname)
		if (ssqlname)
			server = ssqlname
		var/regex/note = new("^(\\d{2}-\\w{3}-\\d{4}) \\| (.+) ~(\\w+)$", "i")
		note.Find(notetext)
		var/timestamp = note.group[1]
		notetext = note.group[2]
		var/admin_ckey = note.group[3]
		var/datum/DBQuery/query_convert_time = SSdbcore.NewQuery("SELECT ADDTIME(STR_TO_DATE(:timestamp, '%d-%b-%Y'), '0')", list("timestamp" = timestamp))
		if(!query_convert_time.Execute())
			qdel(query_convert_time)
			return
		if(query_convert_time.NextRow())
			timestamp = query_convert_time.item[1]
		qdel(query_convert_time)
		if(ckey && notetext && timestamp && admin_ckey && server)
			create_message("note", ckey, admin_ckey, notetext, timestamp, server, 1, 0, null, 0, 0)
	notesfile.cd = "/"
	notesfile.dir.Remove(ckey)

/*alternatively this proc can be run once to pass through every note and attempt to convert it before deleting the file, if done then AUTOCONVERT_NOTES should be turned off
this proc can take several minutes to execute fully if converting and cause DD to hang if converting a lot of notes; it's not advised to do so while a server is live
/proc/mass_convert_notes()
	to_chat(world, "Beginning mass note conversion")
	var/savefile/notesfile = new(NOTESFILE)
	if(!notesfile)
		log_game("Error: Cannot access [NOTESFILE]")
		return
	notesfile.cd = "/"
	for(var/ckey in notesfile.dir)
		convert_notes_sql(ckey)
	to_chat(world, "Deleting NOTESFILE")
	fdel(NOTESFILE)
	to_chat(world, "Finished mass note conversion, remember to turn off AUTOCONVERT_NOTES")*/
#undef NOTESFILE
