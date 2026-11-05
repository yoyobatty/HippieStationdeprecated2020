// hippie -- the mining equipment vendor is a tgui window: the ID in it and its mining points, and everything it sells with a picture,
// what it costs and a Buy button, searchable and in groups. The buttons go through the vendor's own Topic() (machine_vending.dm), so
// the checks and the messages are the old window's.

/obj/machinery/mineral/equipment_vendor/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "mining_vendor", name, 520, 640, master_ui, state)
		ui.open()

/// Which shelf a prize goes on
/obj/machinery/mineral/equipment_vendor/proc/prize_group(datum/data/mining_equipment/prize)
	var/path = prize.equipment_path
	if(ispath(path, /mob/living/simple_animal/hostile/mining_drone) || findtext(prize.equipment_name, "Minebot"))
		return "Minebot"
	if(ispath(path, /obj/item/borg/upgrade/modkit))
		return "Kinetic accelerator mods"
	if(ispath(path, /obj/item/reagent_containers/food) || ispath(path, /obj/item/clothing/mask/cigarette) || ispath(path, /obj/item/soap) || ispath(path, /obj/item/laser_pointer) || ispath(path, /obj/item/clothing/mask/facehugger) || ispath(path, /obj/item/survivalcapsule/luxuryelite))
		return "Comforts"
	return "Equipment"

/obj/machinery/mineral/equipment_vendor/ui_static_data(mob/user)
	var/list/data = list()
	var/list/prizes = list()
	for(var/i in 1 to length(prize_list))
		var/datum/data/mining_equipment/prize = prize_list[i]
		var/atom/path = prize.equipment_path
		prizes += list(list(
			"index" = i,
			"name" = prize.equipment_name,
			"cost" = prize.cost,
			"group" = prize_group(prize),
			"icon" = tgui_item_picture(initial(path.icon), initial(path.icon_state), user),
		))
	data["prizes"] = prizes
	return data

/// A picture of a kind of thing for a tgui window (what a vendor sells, what a machine makes), made once for each icon and state
/// and sent to the user once
/proc/tgui_item_picture(icon_file, icon_state, mob/user)
	if(!icon_file || !user?.client)
		return null
	var/static/list/made = list()
	var/known_as = "[icon_file]|[icon_state]"
	var/asset_name = made[known_as]
	if(!asset_name)
		var/icon/picture = icon(icon_file, icon_state, SOUTH, 1)
		asset_name = "[generate_asset_name(picture)].png"
		register_asset(asset_name, picture)
		made[known_as] = asset_name
	send_asset(user.client, asset_name)
	return asset_name

/obj/machinery/mineral/equipment_vendor/ui_data(mob/user)
	var/list/data = list()
	data["id"] = inserted_id ? inserted_id.name : null
	data["points"] = inserted_id ? inserted_id.mining_points : 0
	var/obj/item/card/id/held = user.get_active_held_item()
	data["holding_id"] = istype(held)
	return data

/obj/machinery/mineral/equipment_vendor/ui_act(action, params)
	if(..())
		return
	switch(action)
		if("insert")
			Topic(null, list("choice" = "insert"))
		if("eject")
			Topic(null, list("choice" = "eject"))
		if("purchase")
			var/index = text2num(params["index"])
			if(!index || index < 1 || index > length(prize_list))
				return
			Topic(null, list("purchase" = REF(prize_list[index])))
	return TRUE
