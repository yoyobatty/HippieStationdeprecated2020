// hippie -- the strip menu (dragging someone onto yourself) is a tgui window. Each click goes through the mob's own Topic(), so
// the strip times, the checks and the messages are the old window's. Bots strip with stripPanelUnequip() and never open it.
// Aliens, larvae, corgis and parrots keep their own windows.

GLOBAL_DATUM_INIT(strip_state, /datum/ui_state/strip_state, new)

/// Usable while standing next to them; only looking while restrained or lying down; shut once out of reach
/datum/ui_state/strip_state/can_use_topic(src_object, mob/user)
	if(!isliving(user))
		return UI_CLOSE
	. = user.shared_ui_interaction(src_object)
	if(. > UI_CLOSE && !user.Adjacent(src_object))
		return UI_CLOSE

/mob/living/carbon/show_inv(mob/user)
	if(user?.client)
		ui_interact(user)

/mob/living/carbon/human/show_inv(mob/user)
	if(user?.client)
		ui_interact(user)

/mob/living/carbon/ui_interact(mob/user, ui_key = "strip", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.strip_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "strip_menu", name, 420, ishuman(src) ? 680 : 330, master_ui, state)
		ui.open()

/mob/living/carbon/ui_data(mob/user)
	var/list/data = list()
	data["rows"] = strip_menu_rows(user)
	var/obj/item/held = user.get_active_held_item()
	data["holding"] = (held && !(held.item_flags & ABSTRACT)) ? held.name : null
	return data

/mob/living/carbon/ui_act(action, params)
	if(..())
		return
	var/list/row = strip_menu_row_for(action, params)
	if(!row)
		return
	switch(action)
		if("item")
			if(row["hand"])
				Topic(null, list("item" = "[ITEM_SLOT_HANDS]", "hand_index" = "[row["hand"]]"))
			else
				Topic(null, list("item" = "[row["slot"]]"))
		if("internal")
			Topic(null, list("internal" = "[row["slot"]]"))
		if("pockets")
			Topic(null, list("pockets" = (params["side"] == "right" ? "right" : "left")))
	return TRUE

/// The line of the window a click was on, or null if the window doesn't offer it (an obscured slot, a pocket with no
/// jumpsuit, a tank that's gone): the old window's Topic took any slot it was sent
/mob/living/carbon/proc/strip_menu_row_for(action, list/params)
	var/slot = text2num(params["slot"])
	var/hand = text2num(params["hand"]) || 0
	for(var/list/row in strip_menu_rows())
		if(row["obscured"] || row["blocked"])
			continue
		switch(action)
			if("item")
				if(row["slot"] && row["slot"] == slot && row["hand"] == hand)
					return row
			if("internal")
				if(row["internals"] && row["slot"] == slot)
					return row
			if("pockets")
				if(row["pockets"])
					return row

/// Each line of the strip menu in the old window's order. With a user, it sends them the items' pictures
/mob/living/carbon/proc/strip_menu_rows(mob/user)
	var/list/rows = list()
	var/list/obscured = check_obscured_slots()
	rows += list(strip_menu_slot(user, "Head", ITEM_SLOT_HEAD, head))
	rows += list(strip_menu_slot(user, "Neck", ITEM_SLOT_NECK, wear_neck, ITEM_SLOT_NECK in obscured))
	rows += list(strip_menu_slot(user, "Mask", ITEM_SLOT_MASK, wear_mask, ITEM_SLOT_MASK in obscured))
	for(var/i in 1 to held_items.len)
		var/list/hand_row = strip_menu_slot(user, capitalize(get_held_index_name(i)), ITEM_SLOT_HANDS, get_item_for_held_index(i), gap = (i == 1))
		hand_row["hand"] = i
		rows += list(hand_row)
	var/list/back_row = strip_menu_slot(user, "Back", ITEM_SLOT_BACK, back, gap = TRUE)
	strip_menu_internals(back_row, back, istype(wear_mask, /obj/item/clothing/mask))
	rows += list(back_row)
	strip_menu_cuffs(user, rows)
	return rows

/mob/living/carbon/human/strip_menu_rows(mob/user)
	var/list/rows = list()
	var/list/obscured = check_obscured_slots()
	var/has_breathable_mask = istype(wear_mask, /obj/item/clothing/mask)
	for(var/i in 1 to held_items.len)
		var/list/hand_row = strip_menu_slot(user, capitalize(get_held_index_name(i)), ITEM_SLOT_HANDS, get_item_for_held_index(i))
		hand_row["hand"] = i
		rows += list(hand_row)
	var/list/back_row = strip_menu_slot(user, "Back", ITEM_SLOT_BACK, back, gap = TRUE)
	strip_menu_internals(back_row, back, has_breathable_mask)
	rows += list(back_row)
	rows += list(strip_menu_slot(user, "Head", ITEM_SLOT_HEAD, head, gap = TRUE))
	rows += list(strip_menu_slot(user, "Mask", ITEM_SLOT_MASK, wear_mask, ITEM_SLOT_MASK in obscured))
	rows += list(strip_menu_slot(user, "Neck", ITEM_SLOT_NECK, wear_neck, ITEM_SLOT_NECK in obscured))
	rows += list(strip_menu_slot(user, "Eyes", ITEM_SLOT_EYES, glasses, ITEM_SLOT_EYES in obscured))
	rows += list(strip_menu_slot(user, "Ears", ITEM_SLOT_EARS, ears, ITEM_SLOT_EARS in obscured))
	rows += list(strip_menu_slot(user, "Exosuit", ITEM_SLOT_OCLOTHING, wear_suit, gap = TRUE))
	if(wear_suit)
		var/list/storage_row = strip_menu_slot(user, "Suit storage", ITEM_SLOT_SUITSTORE, s_store, ITEM_SLOT_SUITSTORE in obscured)
		storage_row["sub"] = TRUE
		if(!storage_row["obscured"])
			strip_menu_internals(storage_row, s_store, has_breathable_mask)
		rows += list(storage_row)
	else
		rows += list(list("label" = "Suit storage", "sub" = TRUE, "blocked" = TRUE))
	rows += list(strip_menu_slot(user, "Shoes", ITEM_SLOT_FEET, shoes, ITEM_SLOT_FEET in obscured))
	rows += list(strip_menu_slot(user, "Gloves", ITEM_SLOT_GLOVES, gloves, ITEM_SLOT_GLOVES in obscured))
	rows += list(strip_menu_slot(user, "Uniform", ITEM_SLOT_ICLOTHING, w_uniform, ITEM_SLOT_ICLOTHING in obscured))
	// The belt, pockets and ID hang off the uniform
	if((w_uniform == null && !(dna && dna.species.nojumpsuit)) || (ITEM_SLOT_ICLOTHING in obscured))
		for(var/label in list("Belt", "Pockets", "ID"))
			rows += list(list("label" = label, "sub" = TRUE, "blocked" = TRUE))
	else
		var/list/belt_row = strip_menu_slot(user, "Belt", ITEM_SLOT_BELT, belt)
		belt_row["sub"] = TRUE
		strip_menu_internals(belt_row, belt, has_breathable_mask)
		rows += list(belt_row)
		// Only whether each pocket has something in it, as before
		rows += list(list("label" = "Pockets", "sub" = TRUE, "pockets" = list(
			"left" = !!(l_store && !(l_store.item_flags & ABSTRACT)),
			"right" = !!(r_store && !(r_store.item_flags & ABSTRACT)))))
		var/list/id_row = strip_menu_slot(user, "ID", ITEM_SLOT_ID, wear_id)
		id_row["sub"] = TRUE
		rows += list(id_row)
	strip_menu_cuffs(user, rows)
	return rows

/mob/living/carbon/proc/strip_menu_slot(mob/user, label, slot, obj/item/I, obscured = FALSE, gap = FALSE)
	var/list/row = list("label" = label, "slot" = slot, "hand" = 0)
	if(gap)
		row["gap"] = TRUE
	if(obscured)
		row["obscured"] = TRUE
	else if(I && !(I.item_flags & ABSTRACT))
		row["item"] = I.name
		row["icon"] = strip_menu_icon(I, user)
	return row

/// The valve button by a tank, as the old window had it: a mask on and a tank in that slot
/mob/living/carbon/proc/strip_menu_internals(list/row, obj/item/I, has_mask)
	if(has_mask && istype(I, /obj/item/tank))
		row["internals"] = internal ? "close" : "open"

/mob/living/carbon/proc/strip_menu_cuffs(mob/user, list/rows)
	if(handcuffed)
		var/list/cuff_row = strip_menu_slot(user, "Handcuffed", ITEM_SLOT_HANDCUFFED, handcuffed, gap = TRUE)
		cuff_row["item"] = cuff_row["item"] || handcuffed.name
		cuff_row["cuffs"] = TRUE
		rows += list(cuff_row)
	if(legcuffed)
		var/list/legcuff_row = strip_menu_slot(user, "Legcuffed", ITEM_SLOT_LEGCUFFED, legcuffed, gap = !handcuffed)
		legcuff_row["item"] = legcuff_row["item"] || legcuffed.name
		legcuff_row["cuffs"] = TRUE
		rows += list(legcuff_row)

/// The item's picture as a file sent to the user, made once for each icon and state. Icons made at runtime have no name
/// to go by, so those go without
/proc/strip_menu_icon(obj/item/I, mob/user)
	if(!user?.client || !isfile(I.icon))
		return null
	var/static/list/made = list()
	var/known_as = "[I.icon]|[I.icon_state]"
	var/asset_name = made[known_as]
	if(!asset_name)
		var/icon/picture = icon(I.icon, I.icon_state, SOUTH, 1)
		asset_name = "[generate_asset_name(picture)].png"
		register_asset(asset_name, picture)
		made[known_as] = asset_name
	send_asset(user.client, asset_name)
	return asset_name
