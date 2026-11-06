// The gun locker and the janitorial cart moved off their old HTML windows (tgui-next Storage.js): what's inside drawn as
// item cards with their pictures (tgui_item_picture(), machine_vending_tgui.dm), click to take one. Taking goes through
// each one's own Topic(), so reach and hands work as before.

// Gun locker

/obj/structure/guncase/ShowWindow(mob/user)
	ui_interact(user)

/obj/structure/guncase/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
									datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	if(!open || !length(contents)) // a click on a shut or empty locker works its door (attack_hand, guncase.dm)
		return
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "gun_locker", name, 420, 300, master_ui, state)
		ui.open()

/obj/structure/guncase/ui_status(mob/user, datum/ui_state/state)
	if(!open)
		return UI_CLOSE
	return ..()

/obj/structure/guncase/ui_data(mob/user)
	var/list/data = list()
	data["capacity"] = capacity
	var/list/guns = list()
	for(var/obj/item/I in contents)
		var/ammo
		if(istype(I, /obj/item/gun/ballistic))
			var/obj/item/gun/ballistic/B = I
			ammo = "[B.get_ammo(TRUE)] rounds"
		else if(istype(I, /obj/item/gun/energy))
			var/obj/item/gun/energy/E = I
			ammo = E.cell ? "[round(E.cell.percent())]%" : "No cell"
		guns += list(list(
			"ref" = REF(I),
			"name" = I.name,
			"icon" = tgui_item_picture(I.icon, I.icon_state, user),
			"ammo" = ammo,
		))
	data["guns"] = guns
	return data

/obj/structure/guncase/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("take")
			Topic(null, list("retrieve" = params["ref"]))
			return TRUE
		if("shut")
			if(usr.canUseTopic(src, BE_CLOSE))
				open = FALSE
				update_icon()
			return TRUE

// Janitorial cart: attack_hand (janicart.dm) builds the old window after ..(), which reaches ui_interact through
// interact(); returning TRUE there stops it

/obj/structure/janitorialcart/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
										datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "jani_cart", name, 420, 390, master_ui, state)
		ui.open()
	return TRUE

/obj/structure/janitorialcart/ui_data(mob/user)
	var/list/data = list()
	var/list/slots = list()
	slots += list(tgui_cart_slot(user, mybag, "garbage", "Trash bag", mybag ? "[length(mybag.contents)] items" : null))
	slots += list(tgui_cart_slot(user, mymop, "mop", "Mop", mymop ? (mymop.reagents.total_volume ? "Wet" : "Dry") : null))
	slots += list(tgui_cart_slot(user, myspray, "spray", "Spray", myspray ? "[round(myspray.reagents.total_volume)]/[myspray.volume] u" : null))
	slots += list(tgui_cart_slot(user, myreplacer, "replacer", "Light replacer", myreplacer ? "[myreplacer.uses] lights" : null))
	var/obj/item/clothing/suit/caution/sign = locate() in src
	slots += list(tgui_cart_slot(user, sign, "sign", "Wet floor signs", signs ? "[signs] left" : null))
	data["slots"] = slots
	data["water"] = round(reagents.total_volume)
	data["water_max"] = reagents.maximum_volume
	return data

/obj/structure/janitorialcart/proc/tgui_cart_slot(mob/user, obj/item/I, key, label, info)
	return list(
		"key" = key,
		"label" = label,
		"name" = I ? I.name : null,
		"icon" = I ? tgui_item_picture(I.icon, I.icon_state, user) : null,
		"info" = info,
	)

/obj/structure/janitorialcart/ui_act(action, list/params)
	if(..())
		return
	if(action == "take" && (params["key"] in list("garbage", "mop", "spray", "replacer", "sign")))
		Topic(null, list("[params["key"]]" = "1"))
		return TRUE
