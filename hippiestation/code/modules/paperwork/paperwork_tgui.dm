// hippie -- paperwork as tgui windows (tgui-next interfaces/Paper.js and PaperList.js), redesigned where it helps (the user's ruling,
// 2026-11-05).
//  - Paper: the page as written, on paper, with its stamps. Holding a pen or a crayon, a box under it to write in, at the end or in
//    any of the form's fields (clicked on the page), with the pen-code help to hand, and the label. The old window was the page in a
//    browser popup with a "write" link at each field and the end, each opening a text box of its own.
//  - Folders, clipboards, filing cabinets and notice boards: what's in them as a list, with Read, Take out and the rest by each, and a
//    search for a cabinet's drawers. The old windows were lists of links.
// What the old windows' links did goes through their own Topic(); writing on paper is its old "write" link with the text in hand.

// ---------------------------------------------------------------------------------------------
// Paper
// ---------------------------------------------------------------------------------------------

/// Read in your hands or in a folder or clipboard you're holding, or from a tile away; a ghost or a silicon only reads
/datum/ui_state/paper_state/can_use_topic(src_object, mob/user)
	if(isobserver(user) || issilicon(user))
		return UI_UPDATE
	if(user.contains(src_object) || get_dist(get_turf(src_object), get_turf(user)) <= 1)
		return user.shared_ui_interaction(src_object)
	return UI_CLOSE

GLOBAL_DATUM_INIT(paper_state, /datum/ui_state/paper_state, new)

/obj/item/paper/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.paper_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		var/datum/asset/assets = get_asset_datum(/datum/asset/spritesheet/simple/paper)
		assets.send(user) // the stamps' pictures
		ui = new(user, src, ui_key, "paper", name, 500, 640, master_ui, state)
		ui.open()

/obj/item/paper/ui_data(mob/user)
	var/list/data = list()
	data["name"] = name
	var/clear = user.is_literate() || isobserver(user)
	if(isAI(user)) // as the old window had it: read from the camera's spot, starred from further
		var/mob/living/silicon/ai/AI = user
		clear = get_dist(src, AI.eyeobj || AI) < 2
	data["text"] = clear ? paper_fields_marked(info) : stars(info)
	data["stamps"] = stamps
	var/obj/item/held = user.get_active_held_item()
	var/writing = (istype(held, /obj/item/pen) || istype(held, /obj/item/toy/crayon)) && user.is_literate() && !is_blind(user) && !(resistance_flags & ON_FIRE)
	data["writing"] = writing
	data["with"] = writing ? held.name : null
	data["crayon"] = writing && istype(held, /obj/item/toy/crayon)
	data["fields"] = min(fields, 15)
	data["in_hand"] = loc == user
	return data

/obj/item/paper/ui_act(action, params)
	if(..())
		return
	var/mob/user = usr
	switch(action)
		if("write")
			paper_write(user, params["text"], params["field"])
		if("rename") // the "Rename paper" verb, typed in the window
			if(loc != user || user.incapacitated() || !user.is_literate())
				return
			if(ishuman(user))
				var/mob/living/carbon/human/H = user
				if(HAS_TRAIT(H, TRAIT_CLUMSY) && prob(25))
					to_chat(H, "<span class='warning'>You cut yourself on the paper! Ahhhh! Ahhhhh!</span>")
					H.damageoverlaytemp = 9001
					H.update_damage_hud()
					return
			var/label = stripped_input_text(params["name"], MAX_NAME_LEN)
			name = "paper[label ? " - '[label]'" : ""]"
			add_fingerprint(user)
	return TRUE

/// The old "write" link's text box, typed in the window: at the end, or in form field `field`
/obj/item/paper/proc/paper_write(mob/user, text, field)
	if(!istext(text) || (resistance_flags & ON_FIRE) || is_blind(user) || !user.is_literate())
		return
	var/obj/item/held = user.get_active_held_item()
	var/iscrayon = istype(held, /obj/item/toy/crayon)
	if(!iscrayon && !istype(held, /obj/item/pen))
		return
	var/t = copytext(html_encode(text), 1, MAX_MESSAGE_LEN)
	if(!length(t))
		return
	log_paper("[key_name(user)] writing to paper [t]")
	t = parsepencode(t, held, user, iscrayon)
	if(!t)
		return
	var/id = text2num(field)
	if(id && id >= 1 && id <= min(fields, 15))
		addtofield(id, t)
	else
		info += t
		updateinfolinks()
	update_icon()
	add_fingerprint(user)

/// The page with its form fields numbered, for the window to click on
/obj/item/paper/proc/paper_fields_marked(text)
	var/tag = "<span class=\"paper_field\">"
	var/field = 0
	var/at = 1
	while(field < 15)
		at = findtext(text, tag, at)
		if(!at)
			break
		field++
		text = copytext(text, 1, at + length(tag) - 1) + " data-field=\"[field]\">" + copytext(text, at + length(tag))
		at += length(tag)
	return text

// ---------------------------------------------------------------------------------------------
// Folders, clipboards, filing cabinets and notice boards: one window, "paper_list"
// ---------------------------------------------------------------------------------------------

/// What one of these holds, for the window
/proc/paperwork_entry(obj/item/I, list/extra)
	var/kind = "paper"
	if(istype(I, /obj/item/photo))
		kind = "photo"
	else if(istype(I, /obj/item/documents))
		kind = "documents"
	else if(istype(I, /obj/item/folder))
		kind = "folder"
	var/list/entry = list("ref" = REF(I), "name" = I.name, "kind" = kind)
	if(extra)
		entry += extra
	return entry

/obj/item/folder/attack_self(mob/user)
	ui_interact(user)
	add_fingerprint(user)

/obj/item/folder/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.inventory_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "paper_list", name, 380, 420, master_ui, state)
		ui.open()

/obj/item/folder/ui_data(mob/user)
	var/list/items = list()
	for(var/obj/item/I in src)
		items += list(paperwork_entry(I))
	return list("kind" = "folder", "name" = name, "items" = items, "can_take" = TRUE, "can_read" = TRUE)

/obj/item/folder/ui_act(action, params)
	if(..())
		return
	switch(action)
		if("take")
			Topic(null, list("remove" = params["ref"]))
		if("read")
			Topic(null, list("read" = params["ref"]))
	return TRUE

/obj/item/clipboard/attack_self(mob/user)
	ui_interact(user)
	add_fingerprint(user)

/obj/item/clipboard/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.inventory_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "paper_list", "Clipboard", 380, 420, master_ui, state)
		ui.open()

/obj/item/clipboard/ui_data(mob/user)
	var/list/items = list()
	if(toppaper)
		items += list(paperwork_entry(toppaper, list("top" = TRUE)))
	for(var/obj/item/paper/P in src)
		if(P != toppaper)
			items += list(paperwork_entry(P))
	var/obj/item/held = user.get_active_held_item()
	return list(
		"kind" = "clipboard",
		"name" = name,
		"items" = items,
		"can_take" = TRUE,
		"can_read" = TRUE,
		"can_write" = istype(held, /obj/item/pen) || istype(held, /obj/item/toy/crayon),
		"pen" = haspen ? haspen.name : null,
		"holding_pen" = istype(held, /obj/item/pen),
	)

/obj/item/clipboard/ui_act(action, params)
	if(..())
		return
	switch(action)
		if("take")
			Topic(null, list("remove" = params["ref"]))
		if("read")
			Topic(null, list("read" = params["ref"]))
		if("write")
			Topic(null, list("write" = params["ref"]))
		if("top")
			Topic(null, list("top" = params["ref"]))
		if("pen_out")
			Topic(null, list("pen" = "1"))
		if("pen_in")
			Topic(null, list("addpen" = "1"))
	return TRUE

/obj/structure/filingcabinet/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "paper_list", name, 380, 480, master_ui, state)
		ui.open()

/obj/structure/filingcabinet/ui_data(mob/user)
	var/list/items = list()
	for(var/i in length(contents) to 1 step -1) // the last one in at the front, as the old list had it
		var/obj/item/I = contents[i]
		if(istype(I))
			items += list(paperwork_entry(I))
	return list("kind" = "cabinet", "name" = name, "items" = items, "can_take" = TRUE)

/obj/structure/filingcabinet/ui_act(action, params)
	if(..())
		return
	if(action == "take")
		Topic(null, list("retrieve" = params["ref"]))
	return TRUE

/obj/structure/noticeboard/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "paper_list", name, 380, 360, master_ui, state)
		ui.open()

/obj/structure/noticeboard/ui_data(mob/user)
	var/list/items = list()
	for(var/obj/item/I in src)
		items += list(paperwork_entry(I))
	var/auth = allowed(user)
	return list(
		"kind" = "noticeboard",
		"name" = name,
		"items" = items,
		"can_read" = TRUE,
		"can_take" = auth,
		"can_write" = auth && user.is_holding_item_of_type(/obj/item/pen),
		"locked" = !auth && length(req_access),
		"slots" = 5,
	)

/obj/structure/noticeboard/ui_act(action, params)
	if(..())
		return
	if(action != "read" && !allowed(usr)) // the old page only hid the links: its Topic() let anybody take a notice down
		to_chat(usr, "<span class='warning'>You are not authorized to do that!</span>")
		return
	switch(action)
		if("take")
			Topic(null, list("remove" = params["ref"]))
		if("read")
			Topic(null, list("read" = params["ref"]))
		if("write")
			Topic(null, list("write" = params["ref"]))
	return TRUE
