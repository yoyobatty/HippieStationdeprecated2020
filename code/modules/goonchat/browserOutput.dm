/*********************************
For the main html chat area
*********************************/

//Precaching a bunch of shit
GLOBAL_DATUM_INIT(iconCache, /savefile, new("tmp/iconCache[world.port].sav")) //Cache of icons for the browser output. hippie -- by port: two servers on one machine (a batch of Bot Shifts) fight over it and icon2base64() throws

//Should match the value set in the browser js
#define MAX_COOKIE_LENGTH 5

/// hippie: tells one boot from the next, so the chat's kept messages know whether their links still point at the same things
GLOBAL_VAR_INIT(chat_round_token, "[world.realtime]-[rand(1, 999999)]")
/// hippie: each player's last chat messages this round, by ckey, as sent (url-encoded twice): a new page gets them back on a reconnect
GLOBAL_LIST_EMPTY(chat_histories)
#define CHAT_HISTORY_KEEP 200

//On client, created on login
/datum/chatOutput
	var/client/owner	 //client ref
	// How many times client data has been checked
	var/total_checks = 0
	// When to next clear the client data checks counter
	var/next_time_to_clear = 0
	var/loaded       = FALSE // Has the client loaded the browser output area?
	var/list/messageQueue //If they haven't loaded chat, this is where messages will go until they do
	var/cookieSent   = FALSE // Has the client sent a cookie for analysis
	var/broken       = FALSE
	var/list/connectionHistory //Contains the connection history passed from chat cookie
	var/adminMusicVolume = 25 //This is for the Play Global Sound verb
	var/list/history // hippie: GLOB.chat_histories' list for this ckey

/datum/chatOutput/New(client/C)
	owner = C
	messageQueue = list()
	connectionHistory = list()
	if(C?.ckey)
		history = GLOB.chat_histories[C.ckey]
		if(!history)
			history = list()
			GLOB.chat_histories[C.ckey] = history

/// hippie: a message the page was sent, already url-encoded twice. Kept to give a new page after a reconnect.
/datum/chatOutput/proc/remember(encoded)
	if(!history)
		return
	history += encoded
	if(history.len > CHAT_HISTORY_KEEP + 50)
		history.Cut(1, history.len - CHAT_HISTORY_KEEP + 1)

/datum/chatOutput/proc/start()
	//Check for existing chat
	if(!owner)
		return FALSE

	if(!winexists(owner, "browseroutput")) // Oh goddamnit.
		set waitfor = FALSE
		broken = TRUE
		message_admins("Couldn't start chat for [key_name_admin(owner)]!")
		. = FALSE
		tgui_alert(owner.mob, "Updated chat window does not exist. If you are using a custom skin file please allow the game to update.")
		return

	if(winget(owner, "browseroutput", "is-visible") == "true") //Already setup
		doneLoading()

	else //Not setup
		load()

	return TRUE

/datum/chatOutput/proc/load(attempt = 1)
	set waitfor = FALSE
	if(!owner)
		return

	var/datum/asset/stuff = get_asset_datum(/datum/asset/group/goonchat)
	stuff.send(owner)

	owner << browse(file('code/modules/goonchat/browserassets/html/browserOutput.html'), "window=browseroutput")
	// hippie: on 516 the page can hang for good on a file that was still arriving when it asked for it (a stylesheet in its head
	// holds up every script after it). The same page loaded again finds the file, so it's loaded again until it says it's up.
	if(attempt < 5)
		addtimer(CALLBACK(src, PROC_REF(retry_load), attempt), 8 SECONDS)

/datum/chatOutput/proc/retry_load(attempt)
	if(loaded || broken || QDELETED(owner))
		return
	log_world("Chat for [owner.ckey] hadn't loaded after [attempt * 8] s, loading it again")
	load(attempt + 1)

/datum/chatOutput/Topic(href, list/href_list)
	if(usr.client != owner)
		return TRUE

	// Build arguments.
	// Arguments are in the form "param[paramname]=thing"
	var/list/params = list()
	for(var/key in href_list)
		if(length_char(key) > 7 && findtext(key, "param")) // 7 is the amount of characters in the basic param key template.
			var/param_name = copytext_char(key, 7, -1)
			var/item       = href_list[key]

			params[param_name] = item

	var/data // Data to be sent back to the chat.
	switch(href_list["proc"])
		if("doneLoading")
			data = doneLoading(arglist(params))

		if("debug")
			data = debug(arglist(params))

		if("ping")
			data = ping(arglist(params))

		if("analyzeClientData")
			data = analyzeClientData(arglist(params))

		if("setMusicVolume")
			data = setMusicVolume(arglist(params))
		if("swaptodarkmode")
			swaptodarkmode()
		if("swaptolightmode")
			swaptolightmode()

	if(data)
		ehjax_send(data = data)


//Called on chat output done-loading by JS.
/datum/chatOutput/proc/doneLoading(fresh)
	if(loaded)
		return

	testing("Chat loaded for [owner.ckey]")
	loaded = TRUE
	showChat()
	sendClientData() //hippie: first, so the page knows the round before the history comes

	// hippie: a page that came up empty (a new client, or Fix chat) gets this round's last messages back
	if(fresh == "1" && length(history))
		owner << output(jointext(history, "&"), "browseroutput:chatRestore")

	for(var/message in messageQueue)
		// whitespace has already been handled by the original to_chat
		to_chat(owner, message, handle_whitespace=FALSE, confidential=TRUE)

	messageQueue = null

	//do not convert to to_chat()
	SEND_TEXT(owner, "<span class=\"userdanger\">Failed to load fancy chat, reverting to old chat. Certain features won't work.</span>")

/datum/chatOutput/proc/showChat()
	winset(owner, "output", "is-visible=false")
	winset(owner, "browseroutput", "is-disabled=false;is-visible=true")

/datum/chatOutput/proc/ehjax_send(client/C = owner, window = "browseroutput", data)
	if(islist(data))
		data = json_encode(data)
	C << output("[data]", "[window]:ehjaxCallback")

/datum/chatOutput/proc/sendMusic(music, list/extra_data)
	if(!findtext(music, GLOB.is_http_protocol))
		return
	var/list/music_data = list("adminMusic" = url_encode(url_encode(music)))

	if(extra_data?.len)
		music_data["musicRate"] = extra_data["pitch"]
		music_data["musicSeek"] = extra_data["start"]
		music_data["musicHalt"] = extra_data["end"]

	ehjax_send(data = music_data)

/datum/chatOutput/proc/stopMusic()
	ehjax_send(data = "stopMusic")

/datum/chatOutput/proc/setMusicVolume(volume = "")
	if(volume)
		adminMusicVolume = clamp(text2num(volume), 0, 100)

//Sends client connection details to the chat to handle and save
/datum/chatOutput/proc/sendClientData()
	//Get dem deets
	var/list/deets = list("clientData" = list())
	deets["clientData"]["ckey"] = owner.ckey
	deets["clientData"]["ip"] = owner.address
	deets["clientData"]["compid"] = owner.computer_id
	deets["clientData"]["admin"] = owner.holder ? TRUE : FALSE //hippie: the chat's Admin tab
	deets["clientData"]["round"] = GLOB.chat_round_token //hippie: links in messages kept from another round go nowhere
	var/data = json_encode(deets)
	ehjax_send(data = data)

/// hippie: whether the chat shows its Admin tab, when someone gains or loses admin
/datum/chatOutput/proc/sendChatState()
	if(!loaded)
		return
	ehjax_send(data = list("chatAdmin" = owner?.holder ? TRUE : FALSE))

//Called by client, sent data to investigate (cookie history so far)
/datum/chatOutput/proc/analyzeClientData(cookie = "")
	//Spam check
	if(world.time  >  next_time_to_clear)
		next_time_to_clear = world.time + (3 SECONDS)
		total_checks = 0

	total_checks += 1

	if(total_checks > SPAM_TRIGGER_AUTOMUTE)
		message_admins("[key_name(owner)] kicked for goonchat topic spam")
		qdel(owner)
		return

	if(!cookie)
		return

	if(cookie != "none")
		var/list/connData = json_decode(cookie)
		if (connData && islist(connData) && connData.len > 0 && connData["connData"])
			connectionHistory = connData["connData"] //lol fuck
			var/list/found = new()

			if(connectionHistory.len > MAX_COOKIE_LENGTH)
				message_admins("[key_name(src.owner)] was kicked for an invalid ban cookie)")
				qdel(owner)
				return

			for(var/i in connectionHistory.len to 1 step -1)
				if(QDELETED(owner))
					//he got cleaned up before we were done
					return
				var/list/row = src.connectionHistory[i]
				if (!row || row.len < 3 || (!row["ckey"] || !row["compid"] || !row["ip"])) //Passed malformed history object
					return
				if (world.IsBanned(row["ckey"], row["ip"], row["compid"], real_bans_only=TRUE))
					found = row
					break
				CHECK_TICK

			//Uh oh this fucker has a history of playing on a banned account!!
			if (found.len > 0)
				message_admins("[key_name(src.owner)] has a cookie from a banned account! (Matched: [found["ckey"]], [found["ip"]], [found["compid"]])")
				log_admin_private("[key_name(owner)] has a cookie from a banned account! (Matched: [found["ckey"]], [found["ip"]], [found["compid"]])")

	cookieSent = TRUE

//Called by js client every 60 seconds
/datum/chatOutput/proc/ping()
	return "pong"

//Called by js client on js error
/datum/chatOutput/proc/debug(error)
	log_world("\[[time2text(world.realtime, "YYYY-MM-DD hh:mm:ss")]\] Client: [(src.owner.key ? src.owner.key : src.owner)] triggered JS error: [error]")

//Global chat procs
/proc/to_chat_immediate(target, message, handle_whitespace = TRUE, confidential = FALSE)
	if(!target || !message)
		return

	if(target == world)
		target = GLOB.clients

	var/original_message = message
	if(handle_whitespace)
		message = replacetext(message, "\n", "<br>")
		message = replacetext(message, "\t", "[GLOB.TAB][GLOB.TAB]")

	if(!confidential && target != GLOB.admins && target != GLOB.mentors) // hippie -- moody blues
		SSdemo.write_chat(target, message)

	if(islist(target))
		for(var/I in target)
			var/client/C = CLIENT_FROM_VAR(I) //Grab us a client if possible

			if (!C)
				continue

			//Send it to the old style output window.
			SEND_TEXT(C, original_message)

			if(!C.chatOutput || C.chatOutput.broken) // A player who hasn't updated his skin file.
				continue

			if(!C.chatOutput.loaded)
				//Client still loading, put their messages in a queue
				C.chatOutput.messageQueue += message
				continue

			C.chatOutput.send_batch(list(message)) //hippie -- the tgui chat (hippiestation/code/modules/tgui_panel)
			C.chatOutput.remember(message)
	else
		var/client/C = CLIENT_FROM_VAR(target) //Grab us a client if possible

		if (!C)
			return

		//Send it to the old style output window.
		SEND_TEXT(C, original_message)

		if(!C.chatOutput || C.chatOutput.broken) // A player who hasn't updated his skin file.
			return

		if(!C.chatOutput.loaded)
			//Client still loading, put their messages in a queue
			C.chatOutput.messageQueue += message
			return

		C.chatOutput.send_batch(list(message)) //hippie -- the tgui chat (hippiestation/code/modules/tgui_panel)
		C.chatOutput.remember(message)

/proc/to_chat(target, message, handle_whitespace = TRUE, confidential = FALSE)
	if(Master.current_runlevel == RUNLEVEL_INIT || !SSchat?.initialized)
		to_chat_immediate(target, message, handle_whitespace, confidential)
		return
	SSchat.queue(target, message, handle_whitespace, confidential)

/datum/chatOutput/proc/swaptolightmode() //Dark mode light mode stuff. Yell at KMC if this breaks! (See darkmode.dm for documentation)
	owner.force_white_theme()

/datum/chatOutput/proc/swaptodarkmode()
	owner.force_dark_theme()

#undef MAX_COOKIE_LENGTH
#undef CHAT_HISTORY_KEEP
