// hippie -- the chat is tg's tgui-panel (tgui6/, `bun run tgui:build` there; pinned tg commit in tgui6/TG_COMMIT).
// /datum/chatOutput stays as each client's chat, so everything that talks to it (SSchat, SSping, internet sound, the admin
// tab, Fix Chat) is unchanged; what it drives underneath is the tgui page in the skin's "browseroutput" element instead
// of goonchat. The old text output stays under it and gets every message too, so nothing is lost if the page won't load.

#define TGUI_PANEL_WINDOW "browseroutput"
/// Messages kept for the page's resend requests (it asks for any sequence number it missed)
#define TGUI_PANEL_RESEND_KEEP 100
/// Each player's last messages this round, given back to a page that loads again (reconnect, Fix Chat)
#define CHAT_PANEL_HISTORY_KEEP 200

/// The chat's built stylesheet (fonts inside) and script, sent before the page; hippie-loader.js fetches them
/datum/asset/simple/tgui_panel
	assets = list(
		"tgui-panel.bundle.js" = 'tgui6/public/tgui-panel.bundle.js',
		"tgui-panel.bundle.css" = 'tgui6/public/tgui-panel.bundle.css',
	)

/// The page, built once: tg's tgui.html with the Byond helpers and our loader inlined. Small on purpose: browse() cuts a
/// page off under 1 MB, so the 1.4 MB stylesheet and script come as files (see hippie-loader.js for the 516 trap).
GLOBAL_VAR(tgui_panel_page)

/proc/tgui_panel_page()
	if(GLOB.tgui_panel_page)
		return GLOB.tgui_panel_page
	var/html = file2text("tgui6/public/tgui.html")
	var/helpers = file2text("tgui6/public/helpers.min.js")
	var/loader = file2text("tgui6/public/hippie-loader.js")
	if(!html || !helpers || !loader)
		return null
	html = replacetextEx(html, "\[tgui:windowId]", TGUI_PANEL_WINDOW)
	html = replacetextEx(html, "\[tgui:strictMode]", "1")
	html = replacetextEx(html, "\[tgui:storagecdn]", "")
	html = replacetextEx(html, "<!-- tgui:helpers -->", "<script>[helpers]</script>")
	html = replacetextEx(html, "<!-- tgui:ntos-error -->", "<style>[file2text("tgui6/public/ntos-error.min.css")]</style>") // keeps the crash screen hidden until there is one
	// In tg's assets spot, before the page's last script: that one says "ready" by navigating to a byond:// link, and the
	// page stops reading anything after it. The loader only fetches, so the bundle runs (and makes its React root) after
	// the page is all there. Messages that come before it does wait in the helpers' queue.
	html = replacetextEx(html, "<!-- tgui:assets -->", "<script>[loader]</script>")
	GLOB.tgui_panel_page = html
	return html

/datum/chatOutput
	/// Next sequence number for a message to this page
	var/panel_sequence = 0
	/// "sequence" -> the message as sent, for the page's resends
	var/list/panel_sent = list()
	/// When the page last loaded, for the first-load timeout
	var/panel_loaded_at
	/// Telemetry: when it was asked for, and what came back
	var/telemetry_requested_at
	var/list/telemetry_connections
	/// Message spam guard
	var/panel_messages_this_second = 0
	var/panel_second

/// Always a fresh page: one left from the last connection counts messages from where it was and would drop the new ones
/datum/chatOutput/start()
	if(!owner)
		return FALSE
	if(!winexists(owner, TGUI_PANEL_WINDOW))
		broken = TRUE
		message_admins("Couldn't start chat for [key_name_admin(owner)]: their skin has no chat element")
		return FALSE
	load()
	return TRUE

/datum/chatOutput/load(attempt = 1)
	set waitfor = FALSE
	if(!owner)
		return
	var/page = tgui_panel_page()
	if(!page)
		broken = TRUE
		log_world("Chat: tgui6/public has no built chat; run `bun run tgui:build` in tgui6/. The old text output stays.")
		return
	loaded = FALSE
	panel_sequence = 0
	panel_sent = list()
	panel_loaded_at = world.time
	var/datum/asset/files = get_asset_datum(/datum/asset/simple/tgui_panel)
	files.send(owner)
	owner << browse(page, "window=[TGUI_PANEL_WINDOW]")
	if(attempt < 5)
		addtimer(CALLBACK(src, PROC_REF(retry_load), attempt), 10 SECONDS)

/// A message for the page: tg's tgui window format (url-encoded JSON of type and payload), to its update()
/datum/chatOutput/proc/panel_send(type, payload)
	if(!owner)
		return
	owner << output(url_encode(json_encode(list("type" = type, "payload" = payload))), "[TGUI_PANEL_WINDOW]:update")

/// Sends messages (HTML) to the page in one output, numbered so it can ask again for any it misses
/datum/chatOutput/proc/send_batch(list/messages)
	if(!owner || !length(messages))
		return
	var/list/batch = list()
	for(var/html in messages)
		var/list/sequenced = list("sequence" = panel_sequence, "content" = list("html" = html))
		panel_sent["[panel_sequence]"] = sequenced
		panel_sequence++
		batch += list(sequenced)
	if(length(panel_sent) > TGUI_PANEL_RESEND_KEEP + 50)
		panel_sent.Cut(1, length(panel_sent) - TGUI_PANEL_RESEND_KEEP + 1)
	panel_send("hippie/messages", batch)

/// What the page says (`?tgui=1&window_id=browseroutput&type=...&payload=json`, routed by /client/Topic)
/datum/chatOutput/proc/on_panel_message(type, list/payload, list/href_list)
	if(world.time >= panel_second + 1 SECONDS)
		panel_second = world.time
		panel_messages_this_second = 0
	if(++panel_messages_this_second > 60)
		if(panel_messages_this_second == 61)
			log_admin_private("[key_name(owner)] sent the chat page more than 60 messages in a second; ignoring the rest")
		return
	switch(type)
		if("ready")
			panel_ready()
		if("ping")
			panel_send("ping/reply", payload)
		if("ping/set")
			if(isnum(payload?["ping"]))
				owner.chat_ping = payload["ping"]
		if("chat/resend")
			var/list/again = panel_sent["[text2num(href_list["payload"])]"]
			if(again)
				panel_send("chat/message", json_encode(again))
		if("audio/setAdminMusicVolume")
			if(isnum(payload?["volume"]))
				adminMusicVolume = clamp(round(payload["volume"] * 100), 0, 100)
		if("audio/protected")
			var/static/warned_at = -1 MINUTES
			if(world.time > warned_at + 10 SECONDS)
				warned_at = world.time
				message_admins("<span class='notice'>Internet sound returned a protected playback error, likely because it's copyrighted.</span>")
		if("telemetry")
			analyze_telemetry(payload)
		if("hippie/name")
			name_menu_open(payload)
		if("hippie/nameAct")
			name_menu_act(payload)
		if("openLink")
			var/url = href_list["url"]
			if(findtext(url, GLOB.is_http_protocol) == 1)
				owner << link(url)
		if("log")
			if(href_list["fatal"])
				log_world("Chat page error for [owner.ckey]: [href_list["message"] || href_list["payload"]]")
		else
			if(findtext(type, "verbs/") == 1)
				on_panel_verbs(type, payload)

/// The page is up: show it, tell it who it's for, give it this round's messages back, then what queued while it loaded
/datum/chatOutput/proc/panel_ready()
	var/first = !loaded
	loaded = TRUE
	broken = FALSE
	showChat()
	panel_send("update", list(
		"config" = list(
			"client" = list("ckey" = owner.ckey, "address" = owner.address, "computer_id" = owner.computer_id),
			"window" = list("locked" = FALSE),
		),
	))
	send_player_info()
	panel_send("hippie/admin", list("admin" = owner.holder ? TRUE : FALSE))
	if(!first)
		return
	if(length(history))
		panel_send("hippie/history", list("messages" = history.Copy()))
	if(length(messageQueue))
		send_batch(messageQueue)
		for(var/message in messageQueue)
			remember(message)
	messageQueue = list()
	request_telemetry()

/// The job and character names the chat can highlight
/datum/chatOutput/proc/send_player_info()
	if(!loaded)
		return
	var/mob/M = owner.mob
	panel_send("player/set", list(
		"job" = M?.mind?.assigned_role,
		"character" = owner.prefs?.real_name,
		"characters" = owner.prefs?.real_name ? list(owner.prefs.real_name) : list(),
	))

/datum/chatOutput/doneLoading(fresh)
	panel_ready()

/datum/chatOutput/retry_load(attempt)
	if(loaded || broken || QDELETED(owner))
		return
	log_world("Chat for [owner.ckey] hadn't loaded after [attempt * 10] s, loading it again")
	load(attempt + 1)

/// Old goonchat calls, as the panel's messages
/datum/chatOutput/ehjax_send(client/C = owner, window = TGUI_PANEL_WINDOW, data)
	if(C != owner)
		C?.chatOutput?.ehjax_send(C, window, data)
		return
	if(!loaded)
		return
	switch(data)
		if("pang")
			panel_send("ping/soft", list("afk" = FALSE))
		if("softPang")
			panel_send("ping/soft", list("afk" = TRUE))
		if("roundrestart")
			panel_send("roundrestart")
		if("stopMusic")
			panel_send("audio/stopMusic")

/datum/chatOutput/sendMusic(music, list/extra_data)
	if(!loaded || !findtext(music, GLOB.is_http_protocol))
		return
	var/list/play = list("url" = music)
	if(extra_data)
		for(var/key in extra_data)
			play[key] = extra_data[key]
	panel_send("audio/playMusic", play)

/datum/chatOutput/stopMusic()
	if(loaded)
		panel_send("audio/stopMusic")

/datum/chatOutput/sendClientData()
	return

/datum/chatOutput/sendChatState()
	if(loaded)
		panel_send("hippie/admin", list("admin" = owner?.holder ? TRUE : FALSE))

/// Messages kept for a reconnect: as HTML now (goonchat kept them url-encoded twice)
/datum/chatOutput/remember(html)
	if(!history)
		return
	history += html
	if(history.len > CHAT_PANEL_HISTORY_KEEP + 50)
		history.Cut(1, history.len - CHAT_PANEL_HISTORY_KEEP + 1)

// Telemetry: the page keeps the last few ckeys/computers that used it and reports them; one that's banned is reported to
// admins (goonchat's ban cookie did this).
#define TGUI_TELEMETRY_MAX_CONNECTIONS 5

/datum/chatOutput/proc/request_telemetry()
	telemetry_requested_at = world.time
	panel_send("telemetry/request", list("limits" = list("connections" = TGUI_TELEMETRY_MAX_CONNECTIONS)))

/datum/chatOutput/proc/analyze_telemetry(list/payload)
	if(!telemetry_requested_at || world.time > telemetry_requested_at + 30 SECONDS || telemetry_connections)
		return
	var/list/connections = payload?["connections"]
	if(!islist(connections))
		return
	if(length(connections) > TGUI_TELEMETRY_MAX_CONNECTIONS)
		message_admins("[key_name(owner)] sent the chat's connection history with too many entries ([length(connections)])")
		return
	telemetry_connections = connections
	cookieSent = TRUE
	for(var/list/row in connections)
		if(QDELETED(owner))
			return
		if(!islist(row))
			continue
		var/ckey = ckey(row["ckey"])
		var/address = row["address"]
		var/cid = row["computer_id"]
		if(!ckey || ckey == owner.ckey)
			continue
		if(world.IsBanned(ckey, address, cid, real_bans_only = TRUE))
			message_admins("[key_name(owner)] played from a computer a banned account used (matched: [ckey], [address], [cid])")
			log_admin_private("[key_name(owner)] played from a computer a banned account used (matched: [ckey], [address], [cid])")
			return
		CHECK_TICK

#undef TGUI_TELEMETRY_MAX_CONNECTIONS

// The page's settings and tabs keep themselves: with no storage CDN set, tg's storage uses BYOND's own (+byondstorage),
// which lasts between launches.

/// Page -> server: tgui messages arrive as ?tgui=1&window_id=...&type=...&payload=...
/client/Topic(href, list/href_list, hsrc)
	if(href_list["tgui"] && href_list["window_id"] == TGUI_PANEL_WINDOW)
		var/payload
		if(href_list["payload"])
			try
				payload = json_decode(href_list["payload"])
			catch
				return
		chatOutput?.on_panel_message(href_list["type"], islist(payload) ? payload : null, href_list)
		return
	return ..()

// SSchat: a tick's messages for each player go to the page in one output (hippie/messages), as HTML; the old text output
// gets each one as before

/datum/controller/subsystem/chat/fire()
	for(var/i in payload)
		var/client/C = i
		var/list/messages = payload[C]
		payload -= C
		C?.chatOutput?.send_batch(messages)
		if(MC_TICK_CHECK)
			return

/datum/controller/subsystem/chat/queue(target, message, handle_whitespace = TRUE, confidential = FALSE)
	if(!target || !message)
		return
	if(!istext(message))
		stack_trace("to_chat called with invalid input type")
		return
	if(target == world)
		target = GLOB.clients
	else if(!islist(target) && !CLIENT_FROM_VAR(target))
		return // a mob with no player: nothing below shows it to anyone, demos included

	var/original_message = message
	// Some macros remain in the string even after parsing
	message = replacetext(message, "\improper", "")
	message = replacetext(message, "\proper", "")
	if(handle_whitespace)
		message = replacetext(message, "\n", "<br>")
		message = replacetext(message, "\t", "[FOURSPACES][FOURSPACES]")

	if(!confidential && target != GLOB.admins && target != GLOB.mentors) // hippie -- moody blues
		SSdemo.write_chat(target, message + "<br>")

	var/list/targets = islist(target) ? target : list(target)
	for(var/I in targets)
		var/client/C = CLIENT_FROM_VAR(I)
		if(!C)
			continue
		SEND_TEXT(C, original_message) // the old text output, under the page
		var/datum/chatOutput/chat = C.chatOutput
		if(!chat || chat.broken)
			continue
		if(!chat.loaded)
			chat.messageQueue += message
			continue
		LAZYADD(payload[C], message)
		chat.remember(message)

/// The ping the page measures, for anything that wants it
/client/var/chat_ping

#undef TGUI_PANEL_WINDOW
#undef TGUI_PANEL_RESEND_KEEP

#undef CHAT_PANEL_HISTORY_KEEP
