// hippie -- the newscaster is a tgui window that opens onto a front page: the latest stories from every channel, a toolbar
// for the channels, a new story, a new channel and printing the paper in one click. Reading a channel shows its stories with
// their photos and comments, and you comment in place. On a security unit the censor and D-Notice buttons sit on the
// stories and channels you're reading, and Wanted joins the toolbar.
// Buttons that didn't ask anything go through the newscaster's own Topic(); the ones that asked in a popup or an "are you
// sure" alert do the same thing here with what was typed in the window, the click on Submit being the yes.
// New: a channel's owner can lock and unlock the comments on its stories, which only a security unit could before.

/obj/machinery/newscaster
	/// What the last button did, shown at the top until the next: list(text, "good"/"bad")
	var/list/news_notice
	/// The admins' newscaster (Access Newscaster Network, admin_fun_tgui.dm): anyone with a holder, from anywhere, signing as Nanotrasen
	var/admin_desk = FALSE

/obj/machinery/newscaster/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	if(!(ishuman(user) || issilicon(user)) || !user.client)
		return
	scan_user(user)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "newscaster", "Newscaster Unit #[unit_no]", 600, 680, master_ui, state)
		ui.open()

/// A picture for the window, sent to the reader once. Named for the picture: an edited wanted issue gets a new one
/obj/machinery/newscaster/proc/news_photo(icon/img, mob/user)
	if(!img || !user?.client)
		return null
	var/name = "news_photo_[REF(img)].png"
	if(!SSassets.cache[name])
		register_asset(name, img)
	send_asset(user.client, name)
	return name

/obj/machinery/newscaster/proc/news_channel_entry(datum/newscaster/feed_channel/FC)
	return list(
		"ref" = REF(FC),
		"name" = FC.channel_name,
		"author" = FC.returnAuthor(-1),
		"censored" = FC.censored,
		"admin" = FC.is_admin_channel,
		"public" = !FC.locked,
		"stories" = length(FC.messages),
		"author_censored" = FC.authorCensor,
		"owner" = (FC.author == scanned_user),
	)

/obj/machinery/newscaster/proc/news_story_entry(datum/newscaster/feed_message/MESSAGE, datum/newscaster/feed_channel/FC, mob/user)
	var/list/comments = list()
	for(var/datum/newscaster/feed_comment/comment in MESSAGE.comments)
		comments += list(list("ref" = REF(comment), "body" = comm_plain_text(comment.body), "author" = comment.author, "time" = comment.time_stamp))
	return list(
		"ref" = REF(MESSAGE),
		"channel" = FC.channel_name,
		"channel_ref" = REF(FC),
		"order" = MESSAGE.creationTime,
		"body" = comm_plain_text(MESSAGE.returnBody(-1)),
		"author" = MESSAGE.returnAuthor(-1),
		"time" = MESSAGE.time_stamp,
		"photo" = news_photo(MESSAGE.img, user),
		"caption" = MESSAGE.caption,
		"comments" = comments,
		"locked" = MESSAGE.locked,
		"body_censored" = MESSAGE.bodyCensor,
		"author_censored" = MESSAGE.authorCensor,
		"admin" = MESSAGE.is_admin_message,
		"can_lock" = securityCaster || FC.author == scanned_user,
	)

/// The story and its channel for a reference from the page, from any channel
/obj/machinery/newscaster/proc/news_find_story(ref)
	for(var/datum/newscaster/feed_channel/FC in GLOB.news_network.network_channels)
		var/datum/newscaster/feed_message/MESSAGE = locate(ref) in FC.messages
		if(MESSAGE)
			return list(MESSAGE, FC)

/obj/machinery/newscaster/ui_data(mob/user)
	var/list/data = list()
	var/datum/newscaster/feed_network/network = GLOB.news_network
	data["unit"] = unit_no
	data["user"] = scanned_user
	data["security"] = securityCaster
	data["screen"] = screen
	data["notice"] = news_notice
	data["channel_name"] = channel_name
	data["msg"] = comm_plain_text(msg)
	data["c_locked"] = c_locked
	data["allow_comments"] = allow_comments
	data["photo_attached"] = !!picture
	data["paper"] = paper_remaining

	var/datum/newscaster/wanted_message/wanted = network.wanted_issue
	data["wanted"] = null
	if(wanted.active)
		data["wanted"] = list(
			"criminal" = wanted.criminal,
			"body" = comm_plain_text(wanted.body),
			"author" = wanted.scannedUser,
			"admin" = wanted.isAdminMsg,
			"photo" = (screen == 18) ? news_photo(wanted.img, user) : null,
		)

	var/list/channels = list()
	var/list/receiving = list()
	for(var/datum/newscaster/feed_channel/FC in network.network_channels)
		channels += list(news_channel_entry(FC))
		// Where a story can go: public channels and your own, not under a D-Notice
		if((!FC.locked || FC.author == scanned_user) && !FC.censored)
			receiving += FC.channel_name
	data["channels"] = channels
	data["receiving"] = receiving

	// The front page: every story, newest first in the window, but none from a channel under a D-Notice (a security unit
	// still shows them, to deal with)
	if(screen == 0)
		var/list/front = list()
		for(var/datum/newscaster/feed_channel/FC in network.network_channels)
			if(FC.censored && !securityCaster)
				continue
			for(var/datum/newscaster/feed_message/MESSAGE in FC.messages)
				front += list(news_story_entry(MESSAGE, FC, user))
		data["front"] = front

	data["viewing"] = null
	if(viewing_channel && screen == 9)
		var/list/channel = news_channel_entry(viewing_channel)
		var/list/stories = list()
		if(!viewing_channel.censored || securityCaster)
			for(var/datum/newscaster/feed_message/MESSAGE in viewing_channel.messages)
				stories += list(news_story_entry(MESSAGE, viewing_channel, user))
		channel["messages"] = stories
		data["viewing"] = channel

	// What went wrong, as the old error screens listed it
	var/list/errors = list()
	switch(screen)
		if(6)
			if(channel_name == "")
				errors += "Invalid receiving channel name."
			if(scanned_user == "Unknown")
				errors += "Channel author unverified."
			if(msg == "" || msg == "\[REDACTED\]")
				errors += "Invalid message body."
		if(7)
			for(var/datum/newscaster/feed_channel/FC in network.network_channels)
				if((FC.authorCensor ? network.redactedText : FC.author) == scanned_user)
					errors += "There is already a Feed channel under your name."
					break
			if(channel_name == "" || channel_name == "\[REDACTED\]")
				errors += "Invalid channel name."
			for(var/datum/newscaster/feed_channel/FC in network.network_channels)
				if(FC.channel_name == channel_name)
					errors += "Channel name already in use."
					break
			if(scanned_user == "Unknown")
				errors += "Channel author unverified."
		if(16)
			if(channel_name == "" || channel_name == "\[REDACTED\]")
				errors += "Invalid name for person wanted."
			if(scanned_user == "Unknown")
				errors += "Issue author unverified."
			if(msg == "" || msg == "\[REDACTED\]")
				errors += "Invalid description."
	data["errors"] = errors
	return data

/obj/machinery/newscaster/ui_act(action, params)
	if(..())
		return
	if(!(ishuman(usr) || issilicon(usr) || (admin_desk && usr.client?.holder)))
		return
	scan_user(usr)
	news_notice = null
	var/datum/newscaster/feed_network/network = GLOB.news_network
	var/static/list/security_actions = list("menu_wanted", "submit_wanted", "cancel_wanted", "set_wanted_name", "set_wanted_desc", "censor_channel_author", "censor_story_author", "censor_story_body", "toggle_d_notice", "del_comment")
	// The old Topic took these from any newscaster's page
	if((action in security_actions) && !securityCaster)
		return
	switch(action)
		// What the old Topic did as it was
		if("view", "create_channel", "create_feed_story", "menu_wanted", "view_wanted", "set_channel_lock", "set_attachment", "set_comment")
			news_topic(list("[action]" = "1"))
		if("screen")
			var/to_screen = text2num(params["screen"])
			if(!(to_screen in list(0, 1, 2, 3)))
				return
			news_topic(list("setScreen" = "[to_screen]"))
		if("show_channel")
			var/datum/newscaster/feed_channel/FC = locate(params["ref"]) in network.network_channels
			if(!FC)
				return
			news_topic(list("show_channel" = REF(FC)))
		if("print_paper")
			// One click: where you are, with what happened at the top
			if(!paper_remaining)
				news_notice = list("Unable to print newspaper. Insufficient paper. Please notify maintenance personnel to refill machine storage.", "bad")
			else
				print_paper()
				news_notice = list("Printing successful. Please receive your newspaper from the bottom of the machine.", "good")

		// What it asked in a popup, typed in the window instead
		if("set_channel_name")
			channel_name = stripped_input_text(params["text"], MAX_NAME_LEN)
		if("set_channel_receiving")
			// Only a channel you could pick from its list
			for(var/datum/newscaster/feed_channel/F in network.network_channels)
				if(F.channel_name == params["text"] && (!F.locked || F.author == scanned_user) && !F.censored)
					channel_name = F.channel_name
		if("submit_story")
			var/body = stripped_input_text(params["text"], MAX_MESSAGE_LEN, TRUE)
			if(body)
				msg = body
			var/posted_to = channel_name
			news_topic(list("submit_new_message" = "1"))
			if(screen == 4) // posted: on to the channel, to see it there
				news_show_channel(posted_to)
				news_notice = list("Feed story successfully submitted to [posted_to].", "good")
		if("set_wanted_name")
			channel_name = stripped_input_text(params["text"])
		if("set_wanted_desc")
			msg = stripped_input_text(params["text"])
		if("comment")
			// As the old Topic, 140 letters; but not on a story with its comments locked, which it only hid the link for
			var/list/found = news_find_story(params["ref"])
			var/text = stripped_input_text(params["text"], 140)
			if(!found || !text)
				return
			var/datum/newscaster/feed_message/FM = found[1]
			if(FM.locked)
				return
			var/datum/newscaster/feed_comment/comment = new
			comment.author = scanned_user
			comment.body = text
			comment.time_stamp = station_time_timestamp()
			FM.comments += comment
			usr.log_message("(as [scanned_user]) commented on message [FM.returnBody(-1)] -- [comment.body]", LOG_COMMENT)
		if("lock_comment")
			// A security unit, or now the channel's owner
			var/list/found = news_find_story(params["ref"])
			if(!found)
				return
			var/datum/newscaster/feed_message/FM = found[1]
			var/datum/newscaster/feed_channel/FC = found[2]
			if(!(securityCaster || FC.author == scanned_user))
				return
			FM.locked ^= 1
			usr.log_message("(as [scanned_user]) [FM.locked ? "locked" : "unlocked"] the comments on [FM.returnBody(-1)]", LOG_COMMENT)
		if("del_comment")
			var/list/found = news_find_story(params["story"])
			if(!found)
				return
			var/datum/newscaster/feed_message/FM = found[1]
			var/datum/newscaster/feed_comment/comment = locate(params["ref"]) in FM.comments
			if(!comment)
				return
			FM.comments -= comment
			qdel(comment)

		// What it asked "are you sure" about: the click on Submit is the yes
		if("submit_channel")
			var/created = channel_name
			news_submit_channel()
			if(screen == 5)
				news_show_channel(created)
				news_notice = list("Feed Channel [created] created successfully.", "good")
		if("submit_wanted")
			var/criminal = channel_name
			var/editing = network.wanted_issue.active
			if(news_submit_wanted(editing ? 2 : 1))
				screen = 0
				news_notice = list("Wanted issue for [criminal] [editing ? "successfully edited" : "is now in Network Circulation"].", "good")
		if("cancel_wanted")
			if(!network.wanted_issue.active)
				return
			if(network.wanted_issue.isAdminMsg)
				to_chat(usr, "<span class='warning'>The wanted issue has been distributed by a Nanotrasen higherup. You cannot take it down.</span>")
				return
			network.deleteWanted()
			screen = 0
			news_notice = list("Wanted Issue successfully deleted from Circulation.", "good")
		if("censor_channel_author", "toggle_d_notice")
			var/datum/newscaster/feed_channel/FC = locate(params["ref"]) in network.network_channels
			if(!FC)
				return
			if(FC.is_admin_channel)
				to_chat(usr, "<span class='warning'>This channel was created by a Nanotrasen Officer. You cannot [action == "toggle_d_notice" ? "place a D-Notice upon" : "censor"] it.</span>")
				return
			if(action == "toggle_d_notice")
				FC.toggleCensorDclass()
			else
				FC.toggleCensorAuthor()
		if("censor_story_author", "censor_story_body")
			var/list/found = news_find_story(params["ref"])
			if(!found)
				return
			var/datum/newscaster/feed_message/MSG = found[1]
			if(MSG.is_admin_message)
				to_chat(usr, "<span class='warning'>This message was created by a Nanotrasen Officer. You cannot censor it.</span>")
				return
			if(action == "censor_story_body")
				MSG.toggleCensorBody()
			else
				MSG.toggleCensorAuthor()
	add_fingerprint(usr)
	return TRUE

/// The old Topic's buttons the window still uses (the admins' desk does them itself: the old Topic wants you next to the unit)
/obj/machinery/newscaster/proc/news_topic(list/href_list)
	Topic(null, href_list)

/obj/machinery/newscaster/proc/news_show_channel(name)
	for(var/datum/newscaster/feed_channel/FC in GLOB.news_network.network_channels)
		if(FC.channel_name == name)
			viewing_channel = FC
			screen = 9
			return

/// The old Topic's "submit_new_channel", without its confirmation alert
/obj/machinery/newscaster/proc/news_submit_channel()
	var/datum/newscaster/feed_network/network = GLOB.news_network
	var/list/existing_authors = list()
	var/taken = FALSE
	for(var/datum/newscaster/feed_channel/FC in network.network_channels)
		existing_authors += FC.authorCensor ? network.redactedText : FC.author
		if(FC.channel_name == channel_name)
			taken = TRUE
	if(channel_name == "" || channel_name == "\[REDACTED\]" || scanned_user == "Unknown" || taken || (scanned_user in existing_authors))
		screen = 7
		return
	network.CreateFeedChannel(channel_name, scanned_user, c_locked, admin_desk)
	SSblackbox.record_feedback("text", "newscaster_channels", 1, "[channel_name]")
	screen = 5

/// The old Topic's "submit_wanted" (1 a new issue, 2 an edit), without its confirmation alert. TRUE if it went out
/obj/machinery/newscaster/proc/news_submit_wanted(input_param)
	var/datum/newscaster/feed_network/network = GLOB.news_network
	if(msg == "" || channel_name == "" || scanned_user == "Unknown")
		screen = 16
		return FALSE
	if(input_param == 1)
		network.submitWanted(channel_name, msg, scanned_user, picture, admin_desk, 1)
		return TRUE
	if(network.wanted_issue.isAdminMsg && !admin_desk)
		to_chat(usr, "<span class='warning'>The wanted issue has been distributed by a Nanotrasen higherup. You cannot edit it.</span>")
		return FALSE
	network.submitWanted(channel_name, msg, scanned_user, picture, admin_desk)
	return TRUE
