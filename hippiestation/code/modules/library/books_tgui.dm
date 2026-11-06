// Books, the codex gigas's findings, photos, the chaplain's bible style and the mime's book moved off their old HTML
// windows (tgui-next Books.js). A book's text is the same HTML the old window showed, drawn on a page. Manuals that
// embed the wiki in an iframe keep the old window.

/// A page of text in a window: what a book or the codex shows. Its reach is its host's.
/datum/book_reader
	var/atom/host
	var/title = ""
	var/author
	var/html = ""

/datum/book_reader/New(atom/host)
	src.host = host

/datum/book_reader/Destroy()
	host = null
	return ..()

/datum/book_reader/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
								datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "book_reader", title, 560, 640, master_ui, state)
		ui.open()

/datum/book_reader/ui_status(mob/user, datum/ui_state/state)
	return host && !QDELETED(host) ? host.ui_status(user, state) : UI_CLOSE

/datum/book_reader/ui_data(mob/user)
	return list("title" = title, "author" = author, "html" = html)

/obj/item/book
	var/datum/book_reader/reader

/obj/item/book/Destroy()
	QDEL_NULL(reader)
	return ..()

/obj/item/book/attack_self(mob/user)
	if(dat && findtext(dat, "<iframe"))
		return ..() // the wiki manuals keep their old window
	if(!user.can_read(src))
		return
	if(!dat)
		to_chat(user, "<span class='notice'>This book is completely blank!</span>")
		return
	if(!reader)
		reader = new(src)
	reader.title = title || name
	reader.author = author
	reader.html = dat
	reader.ui_interact(user)
	user.visible_message("[user] opens a book titled \"[title]\" and begins reading intently.")
	SEND_SIGNAL(user, COMSIG_ADD_MOOD_EVENT, "book_nerd", /datum/mood_event/book_nerd)

// The codex gigas's findings

/obj/item/book/codex_gigas/display_devil(datum/antagonist/devil/devil, mob/reader_mob, devilName)
	if(!reader)
		reader = new(src)
	reader.title = "Information on [devilName]"
	reader.author = null
	reader.html = "[GLOB.lawlorify[LORE][devil.ban]]<br>[GLOB.lawlorify[LORE][devil.bane]]<br>[GLOB.lawlorify[LORE][devil.obligation]]<br>[GLOB.lawlorify[LORE][devil.banish]]<br>[devil.ascendable ? "This devil may ascend given enough souls." : ""]"
	reader.ui_interact(reader_mob, "devil")

// Photos

/obj/item/photo/show(mob/user)
	if(!istype(picture) || !picture.picture_image)
		to_chat(user, "<span class='warning'>[src] seems to be blank...</span>")
		return
	ui_interact(user)

/obj/item/photo/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
							datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "photo_viewer", name, 520, 600, master_ui, state)
		ui.open()

/obj/item/photo/ui_data(mob/user)
	var/list/data = list("name" = name, "scribble" = scribble, "image" = null)
	if(istype(picture) && picture.picture_image && user?.client)
		var/static/list/registered = list() // a picture's image is made once; register it once
		var/asset_name = "photo_[md5("[REF(picture)]")].png"
		if(!registered[asset_name])
			register_asset(asset_name, picture.picture_image)
			registered[asset_name] = TRUE
		send_asset(user.client, asset_name)
		data["image"] = asset_name
	return data

// The chaplain's bible style, picked once

/obj/item/storage/book/bible/attack_self(mob/living/carbon/human/H)
	if(!istype(H))
		return
	if(!H.can_read(src))
		return FALSE
	if(!GLOB.bible_icon_state && H.job == "Chaplain")
		ui_interact(H)

/obj/item/storage/book/bible/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
										datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "bible_style", "Pick Bible Style", 520, 560, master_ui, state)
		ui.open()

/obj/item/storage/book/bible/ui_status(mob/user, datum/ui_state/state)
	if(GLOB.bible_icon_state)
		return UI_CLOSE // picked, once for the station
	return ..()

/obj/item/storage/book/bible/ui_data(mob/user)
	var/list/styles = list()
	for(var/i in 1 to GLOB.biblestates.len)
		styles += list(list("index" = i, "name" = GLOB.biblenames[i], "icon" = tgui_item_picture('icons/obj/storage.dmi', GLOB.biblestates[i], user)))
	return list("styles" = styles)

/obj/item/storage/book/bible/ui_act(action, list/params)
	if(..())
		return
	if(action == "pick")
		Topic(null, list("seticon" = "[params["index"]]"))
		return TRUE

// The mime's book

/obj/item/book/mimery/attack_self(mob/user)
	user.set_machine(src)
	ui_interact(user)

/obj/item/book/mimery/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
								datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "mime_book", "Guide to Dank Mimery", 420, 360, master_ui, state)
		ui.open()

/obj/item/book/mimery/ui_act(action, list/params)
	if(..())
		return
	if(action in list("invisible_wall", "invisible_chair", "invisible_box"))
		SStgui.close_uis(src)
		Topic(null, list("[action]" = "1"))
		return TRUE
