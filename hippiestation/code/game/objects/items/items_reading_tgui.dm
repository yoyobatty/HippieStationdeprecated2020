// hippie -- small things to read or pick from, off their old HTML windows (interfaces/ItemsReading.js): a hand of cards, a valentine,
// a photo sent by PDA, paper held up to a camera (for the AI, and anyone watching through that camera), the newspaper, and the
// hand teleporter's locator. Their own Topic()s still do the work where they had one.

// ---------------------------------------------------------------------------------------------
// A hand of cards
// ---------------------------------------------------------------------------------------------

/obj/item/toy/cards/cardhand/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.hands_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "card_hand", "Hand of Cards", 480, 290, master_ui, state)
		ui.open()

/obj/item/toy/cards/cardhand/ui_data(mob/user)
	return list("cards" = currenthand.Copy(), "deck" = deckstyle)

/obj/item/toy/cards/cardhand/ui_act(action, list/params)
	if(..())
		return
	if(action == "pick" && (params["card"] in currenthand))
		Topic(null, list("pick" = params["card"]))
		return TRUE

// ---------------------------------------------------------------------------------------------
// A photo sent by PDA (the message monitor's photo link, data_pda_msg)
// ---------------------------------------------------------------------------------------------

/datum/data_pda_msg/Topic(href, href_list)
	if(href_list["photo"] && picture)
		var/datum/picture_view/V = new(picture, "PDA Photo")
		V.ui_interact(usr)

/// A picture on its own, in the photo viewer's window (books_tgui.dm's photo_viewer)
/datum/picture_view
	var/datum/picture/picture
	var/name

/datum/picture_view/New(datum/picture/P, title)
	picture = P
	name = title

/datum/picture_view/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "photo_viewer", name, 420, 460, master_ui, state)
		ui.open()

/datum/picture_view/ui_close(mob/user)
	qdel(src)

/datum/picture_view/ui_data(mob/user)
	var/list/data = list("name" = name, "scribble" = null, "image" = null)
	if(istype(picture) && picture.picture_image && user?.client)
		var/static/list/registered = list()
		var/asset_name = "photo_[md5("[REF(picture)]")].png"
		if(!registered[asset_name])
			register_asset(asset_name, picture.picture_image)
			registered[asset_name] = TRUE
		send_asset(user.client, asset_name)
		data["image"] = asset_name
	return data

// ---------------------------------------------------------------------------------------------
// Paper held up to a camera
// ---------------------------------------------------------------------------------------------

/// What was held up, kept to be read in the paper's own window: its name, page and stamps
/datum/paper_snapshot
	var/name
	var/text
	var/stamps

/datum/paper_snapshot/New(obj/item/I)
	name = I.name
	if(istype(I, /obj/item/paper))
		var/obj/item/paper/P = I
		text = P.info
		stamps = P.stamps
	else if(istype(I, /obj/item/pda))
		var/obj/item/pda/PDA = I
		text = PDA.notehtml

/datum/paper_snapshot/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "paper", name, 460, 600, master_ui, state)
		ui.open()

/datum/paper_snapshot/ui_data(mob/user)
	return list("name" = name, "text" = text, "stamps" = stamps, "writing" = FALSE, "fields" = 0, "in_hand" = FALSE)

/mob/living/silicon/ai
	var/datum/paper_snapshot/last_paper_snapshot

// The camera's "OTHER" branch for paper and PDAs (camera.dm attackby()), with the page read in the paper window
/obj/machinery/camera/attackby(obj/item/I, mob/living/user, params)
	if(!((istype(I, /obj/item/paper) || istype(I, /obj/item/pda)) && isliving(user)))
		return ..()
	if(panel_open && (I.tool_behaviour == TOOL_ANALYZER))
		return ..()
	var/mob/living/U = user
	var/datum/paper_snapshot/snapshot = new(I)
	to_chat(U, "<span class='notice'>You hold \the [snapshot.name] up to the camera...</span>")
	U.changeNext_move(CLICK_CD_MELEE)
	for(var/mob/O in GLOB.player_list)
		if(isAI(O))
			var/mob/living/silicon/ai/AI = O
			if(AI.control_disabled || (AI.stat == DEAD))
				return
			if(U.name == "Unknown")
				to_chat(AI, "<span class='name'>[U]</span> holds <a href='?_src_=usr;show_paper=1;'>\a [snapshot.name]</a> up to one of your cameras ...")
			else
				to_chat(AI, "<b><a href='?src=[REF(AI)];track=[html_encode(U.name)]'>[U]</a></b> holds <a href='?_src_=usr;show_paper=1;'>\a [snapshot.name]</a> up to one of your cameras ...")
			AI.last_paper_snapshot = snapshot
		else if(O.client && O.client.eye == src)
			to_chat(O, "<span class='name'>[U]</span> holds \a [snapshot.name] up to one of the cameras ...")
			snapshot.ui_interact(O)

/mob/living/silicon/ai/Topic(href, href_list)
	if(href_list["show_paper"] && usr == src)
		last_paper_snapshot?.ui_interact(src)
		return
	return ..()

// ---------------------------------------------------------------------------------------------
// The newspaper
// ---------------------------------------------------------------------------------------------

/obj/item/newspaper/attack_self(mob/user)
	if(!ishuman(user))
		to_chat(user, "<span class='warning'>The paper is full of unintelligible symbols!</span>")
		return
	ui_interact(user)

/obj/item/newspaper/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.hands_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "newspaper", "The Griffon", 440, 560, master_ui, state)
		ui.open()

/obj/item/newspaper/ui_data(mob/user)
	. = list()
	pages = length(news_content)
	.["screen"] = screen
	.["page"] = curr_page
	.["pages"] = pages + (wantedAuthor ? 2 : 1)
	.["scribble"] = scribble_page == curr_page ? scribble : null
	.["wanted"] = !!wantedAuthor
	switch(screen)
		if(0)
			var/list/contents = list()
			var/n = 0
			for(var/datum/newscaster/feed_channel/NP in news_content)
				n++
				contents += list(list("name" = NP.channel_name, "page" = n + 1))
			.["contents"] = contents
			.["wanted_page"] = wantedAuthor ? pages + 2 : null
		if(1)
			if(curr_page >= 1 && curr_page <= length(news_content))
				var/datum/newscaster/feed_channel/C = news_content[curr_page]
				var/list/channel = list("name" = C.channel_name, "author" = C.returnAuthor(notContent(C.authorCensorTime)), "dnotice" = notContent(C.DclassCensorTime))
				var/list/stories = list()
				if(!channel["dnotice"])
					for(var/datum/newscaster/feed_message/M in C.messages)
						if(M.creationTime > creationTime)
							break
						var/list/story = list("body" = comm_plain_text(M.returnBody(notContent(M.bodyCensorTime))), "author" = M.returnAuthor(notContent(M.authorCensorTime)))
						if(M.img)
							var/asset = "newspaper_[md5("[REF(M)]")].png"
							user << browse_rsc(M.img, asset)
							story["img"] = asset
						stories += list(story)
				channel["stories"] = stories
				.["channel"] = channel
		if(2)
			if(wantedAuthor)
				var/list/wanted = list("criminal" = wantedCriminal, "body" = comm_plain_text(wantedBody))
				if(wantedPhoto)
					var/asset = "newspaper_wanted_[md5("[REF(src)]")].png"
					user << browse_rsc(wantedPhoto, asset)
					wanted["img"] = asset
				.["wanted_issue"] = wanted

/obj/item/newspaper/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("next")
			Topic(null, list("next_page" = "1"))
		if("prev")
			Topic(null, list("prev_page" = "1"))
	return TRUE

// ---------------------------------------------------------------------------------------------
// The hand teleporter's locator
// ---------------------------------------------------------------------------------------------

/obj/item/locator
	/// The last scan: list("beacons", "implants", "x", "y", "z"), or an error
	var/list/locator_scan

/obj/item/locator/attack_self(mob/user)
	user.set_machine(src)
	ui_interact(user)

/obj/item/locator/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.hands_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "locator", "Persistent Signal Locator", 380, 420, master_ui, state)
		ui.open()

/obj/item/locator/ui_data(mob/user)
	return list("scan" = locator_scan)

/obj/item/locator/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("refresh")
			locator_scan = locator_refresh(usr)
		if("clear")
			locator_scan = null
	return TRUE

/// The old Topic()'s refresh, as data: beacons and tracking implants on this level, with direction and strength
/obj/item/locator/proc/locator_refresh(mob/user)
	var/turf/current_location = get_turf(user)
	if(!current_location || is_centcom_level(current_location.z))
		to_chat(user, "[src] is malfunctioning.")
		return null
	var/turf/sr = get_turf(src)
	if(!sr)
		return list("error" = "Unable to locate.")
	var/list/beacons = list()
	for(var/obj/item/beacon/W in GLOB.teleportbeacons)
		if(!W.renamed)
			continue
		var/turf/tr = get_turf(W)
		if(tr && tr.z == sr.z)
			var/dist = max(abs(tr.x - sr.x), abs(tr.y - sr.y))
			beacons += list(list("name" = W.name, "dir" = dir2text(get_dir(sr, tr)), "strength" = dist < 5 ? "very strong" : dist < 10 ? "strong" : dist < 20 ? "weak" : "very weak"))
	var/list/implants = list()
	for(var/obj/item/implant/tracking/W in GLOB.tracked_implants)
		if(!W.imp_in || !isliving(W.loc))
			continue
		var/mob/living/M = W.loc
		if(M.stat == DEAD && M.timeofdeath + W.lifespan_postmortem < world.time)
			continue
		var/turf/tr = get_turf(W)
		if(tr && tr.z == sr.z)
			var/dist = max(abs(tr.x - sr.x), abs(tr.y - sr.y))
			if(dist < 20)
				implants += list(list("name" = W.imp_in.name, "dir" = dir2text(get_dir(sr, tr)), "strength" = dist < 5 ? "very strong" : dist < 10 ? "strong" : "weak"))
	return list("beacons" = beacons, "implants" = implants, "x" = sr.x, "y" = sr.y, "z" = sr.z)

// ---------------------------------------------------------------------------------------------
// A valentine (vday.dm examine() opens it)
// ---------------------------------------------------------------------------------------------

/obj/item/valentine/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "valentine", name, 380, 300, master_ui, state)
		ui.open()

/obj/item/valentine/ui_status(mob/user, datum/ui_state/state)
	return (in_range(user, src) || isobserver(user)) ? UI_INTERACTIVE : UI_CLOSE

/obj/item/valentine/ui_data(mob/user)
	var/clear = ishuman(user) || isobserver(user) || issilicon(user)
	return list("name" = name, "message" = clear ? message : stars(message))
