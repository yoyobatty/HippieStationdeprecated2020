/**********************Ore Redemption Unit**************************/
//Turns all the various mining machines into a single unit to speed up mining and establish a point system

/obj/machinery/mineral/ore_redemption
	name = "ore redemption machine"
	desc = "A machine that accepts ore and instantly transforms it into workable material sheets. Points for ore are generated based on type and can be redeemed at a mining equipment vendor."
	icon = 'icons/obj/machines/mining_machines.dmi'
	icon_state = "ore_redemption"
	density = TRUE
	input_dir = NORTH
	output_dir = SOUTH
	req_access = list(ACCESS_MINERAL_STOREROOM)
	speed_process = TRUE
	circuit = /obj/item/circuitboard/machine/ore_redemption
	layer = BELOW_OBJ_LAYER
	var/obj/item/card/id/inserted_id
	var/points = 0
	var/ore_pickup_rate = 15
	var/sheet_per_ore = 1
	var/point_upgrade = 1
	var/list/ore_values = list(MAT_GLASS = 1, MAT_METAL = 1, MAT_PLASMA = 15, MAT_SILVER = 16, MAT_GOLD = 18, MAT_TITANIUM = 30, MAT_URANIUM = 30, MAT_DIAMOND = 50, MAT_BLUESPACE = 50, MAT_BANANIUM = 60)
	var/message_sent = FALSE
	var/list/ore_buffer = list()
	var/datum/techweb/stored_research
	var/obj/item/disk/design_disk/inserted_disk
	var/datum/component/remote_materials/materials

/obj/machinery/mineral/ore_redemption/Initialize(mapload)
	. = ..()
	stored_research = new /datum/techweb/specialized/autounlocking/smelter
	materials = AddComponent(/datum/component/remote_materials, "orm", mapload)

/obj/machinery/mineral/ore_redemption/Destroy()
	QDEL_NULL(stored_research)
	return ..()

/obj/machinery/mineral/ore_redemption/RefreshParts()
	var/ore_pickup_rate_temp = 15
	var/point_upgrade_temp = 1
	var/sheet_per_ore_temp = 1
	for(var/obj/item/stock_parts/matter_bin/B in component_parts)
		sheet_per_ore_temp = 0.65 + (0.35 * B.rating)
	for(var/obj/item/stock_parts/manipulator/M in component_parts)
		ore_pickup_rate_temp = 15 * M.rating
	for(var/obj/item/stock_parts/micro_laser/L in component_parts)
		point_upgrade_temp = 0.65 + (0.35 * L.rating)
	ore_pickup_rate = ore_pickup_rate_temp
	point_upgrade = point_upgrade_temp
	sheet_per_ore = sheet_per_ore_temp

/obj/machinery/mineral/ore_redemption/examine(mob/user)
	. = ..()
	if(in_range(user, src) || isobserver(user))
		. += "<span class='notice'>The status display reads: Smelting <b>[sheet_per_ore]</b> sheet(s) per piece of ore.<br>Reward point generation at <b>[point_upgrade*100]%</b>.<br>Ore pickup speed at <b>[ore_pickup_rate]</b>.</span>"

/obj/machinery/mineral/ore_redemption/proc/smelt_ore(obj/item/stack/ore/O)
	var/datum/component/material_container/mat_container = materials.mat_container
	if (!mat_container)
		return

	if(O.refined_type == null)
		return

	ore_buffer -= O

	if(O && O.refined_type)
		points += O.points * point_upgrade * O.amount

	var/material_amount = mat_container.get_item_material_amount(O)

	if(!material_amount)
		qdel(O) //no materials, incinerate it

	else if(!mat_container.has_space(material_amount * sheet_per_ore * O.amount)) //if there is no space, eject it
		unload_mineral(O)

	else
		var/mats = O.materials & mat_container.materials
		var/amount = O.amount
		var/id = inserted_id && inserted_id.registered_name
		if (id)
			id = " (ID: [id])"
		mat_container.insert_item(O, sheet_per_ore) //insert it
		materials.silo_log(src, "smelted", amount, "ores[id]", mats)
		qdel(O)

/obj/machinery/mineral/ore_redemption/proc/can_smelt_alloy(datum/design/D)
	var/datum/component/material_container/mat_container = materials.mat_container
	if(!mat_container || D.make_reagents.len)
		return FALSE

	var/build_amount = 0

	for(var/mat_id in D.materials)
		var/M = D.materials[mat_id]
		var/datum/material/redemption_mat = mat_container.materials[mat_id]

		if(!M || !redemption_mat)
			return FALSE

		var/smeltable_sheets = FLOOR(redemption_mat.amount / M, 1)

		if(!smeltable_sheets)
			return FALSE

		if(!build_amount)
			build_amount = smeltable_sheets

		build_amount = min(build_amount, smeltable_sheets)

	return build_amount

/obj/machinery/mineral/ore_redemption/proc/process_ores(list/ores_to_process)
	var/current_amount = 0
	for(var/ore in ores_to_process)
		if(current_amount >= ore_pickup_rate)
			break
		smelt_ore(ore)

/obj/machinery/mineral/ore_redemption/proc/send_console_message()
	var/datum/component/material_container/mat_container = materials.mat_container
	if(!mat_container || !is_station_level(z))
		return
	message_sent = TRUE

	var/area/A = get_area(src)
	var/msg = "Now available in [A]:<br>"

	var/has_minerals = FALSE

	for(var/mat_id in mat_container.materials)
		var/datum/material/M = mat_container.materials[mat_id]
		var/mineral_amount = M.amount / MINERAL_MATERIAL_AMOUNT
		if(mineral_amount)
			has_minerals = TRUE
		msg += "[capitalize(M.name)]: [mineral_amount] sheets<br>"

	if(!has_minerals)
		return

	var/datum/signal/subspace/messaging/rc/signal = new(src, list(
		"ore_update" = TRUE,
		"sender" = "Ore Redemption Machine",
		"message" = msg,
		"verified" = "<font color='green'><b>Verified by Ore Redemption Machine</b></font>",
		"priority" = REQ_NORMAL_MESSAGE_PRIORITY
	))
	signal.send_to_receivers()

/obj/machinery/mineral/ore_redemption/process()
	if(!materials.mat_container || panel_open || !powered())
		return
	var/atom/input = get_step(src, input_dir)
	var/obj/structure/ore_box/OB = locate() in input
	if(OB)
		input = OB

	for(var/obj/item/stack/ore/O in input)
		if(QDELETED(O))
			continue
		ore_buffer |= O
		O.forceMove(src)
		CHECK_TICK

	if(LAZYLEN(ore_buffer))
		message_sent = FALSE
		process_ores(ore_buffer)
	else if(!message_sent)
		send_console_message()

/obj/machinery/mineral/ore_redemption/attackby(obj/item/W, mob/user, params)
	if(default_unfasten_wrench(user, W))
		return
	if(default_deconstruction_screwdriver(user, "ore_redemption-open", "ore_redemption", W))
		updateUsrDialog()
		return
	if(default_deconstruction_crowbar(W))
		return

	if(!powered())
		return
	if(istype(W, /obj/item/card/id))
		var/obj/item/card/id/I = user.get_active_held_item()
		if(istype(I) && !istype(inserted_id))
			if(!user.transferItemToLoc(I, src))
				return
			inserted_id = I
			interact(user)
		return

	if(istype(W, /obj/item/disk/design_disk))
		if(user.transferItemToLoc(W, src))
			inserted_disk = W
			return TRUE

	if(W.tool_behaviour == TOOL_WIRECUTTER)
		if (panel_open)
			input_dir = turn(input_dir, -90)
			output_dir = turn(output_dir, -90)
			to_chat(user, "<span class='notice'>You change [src]'s I/O settings, setting the input to [dir2text(input_dir)] and the output to [dir2text(output_dir)].</span>")
			return TRUE

	var/obj/item/stack/ore/O = W
	if(istype(O))
		if(O.refined_type == null)
			to_chat(user, "<span class='notice'>[O] has already been refined!</span>")
			return

	return ..()

/* HIPPIE START - changes the tool to a wire cutter to avoid conflic with ore silo
/obj/machinery/mineral/ore_redemption/multitool_act(mob/living/user, obj/item/multitool/I)
	if (panel_open)
		input_dir = turn(input_dir, -90)
		output_dir = turn(output_dir, -90)
		to_chat(user, "<span class='notice'>You change [src]'s I/O settings, setting the input to [dir2text(input_dir)] and the output to [dir2text(output_dir)].</span>")
		return TRUE
HIPPIE END */

/obj/machinery/mineral/ore_redemption/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "ore_redemption_machine", "Ore Redemption Machine", 540, 660, master_ui, state)
		ui.set_autoupdate(TRUE)
		ui.open()

/obj/machinery/mineral/ore_redemption/ui_data(mob/user)
	var/list/data = list()
	data["unclaimedPoints"] = points
	data["pointRate"] = point_upgrade
	data["sheetsPerOre"] = sheet_per_ore
	if(inserted_id)
		data["hasID"] = TRUE
		data["idName"] = inserted_id.registered_name || inserted_id.name
		data["claimedPoints"] = inserted_id.mining_points
	else
		// Claim with the slot empty goes to the card the user has on them
		var/obj/item/card/id/worn = user.get_idcard(TRUE)
		if(worn)
			data["wornName"] = worn.registered_name || worn.name
			data["wornPoints"] = worn.mining_points
	data["access"] = (check_access(inserted_id) || allowed(user)) ? TRUE : FALSE

	// Where the stock lives. On a silo it's the silo's: the lathes on it draw from the same sheets, and what goes into
	// any of them shows up here again (players took that for the machine copying sheets, 2026-11-10).
	var/datum/component/material_container/mat_container = materials.mat_container
	data["storage"] = !mat_container ? "none" : (materials.silo ? "silo" : "local")
	if(materials.silo)
		data["siloArea"] = get_area_name(materials.silo, TRUE)
		data["sharedWith"] = max(length(materials.silo.connected) - 1, 0)
		data["onHold"] = materials.on_hold() ? TRUE : FALSE

	data["materials"] = list()
	data["alloys"] = list()
	if (mat_container)
		for(var/mat_id in mat_container.materials)
			var/datum/material/M = mat_container.materials[mat_id]
			data["materials"] += list(list("name" = M.name, "id" = M.id, "amount" = round(M.amount / MINERAL_MATERIAL_AMOUNT), "value" = round((ore_values[M.id] || 0) * point_upgrade, 0.1)))

		for(var/v in stored_research.researched_designs)
			var/datum/design/D = SSresearch.techweb_design_by_id(v)
			var/list/cost = list()
			for(var/mat_id in D.materials)
				var/datum/material/M = mat_container.materials[mat_id]
				cost += list(list("name" = M ? M.name : "[mat_id]", "sheets" = D.materials[mat_id] / MINERAL_MATERIAL_AMOUNT))
			data["alloys"] += list(list("name" = D.name, "id" = D.id, "amount" = can_smelt_alloy(D) || 0, "cost" = cost))

	data["diskDesigns"] = list()
	if(inserted_disk)
		data["hasDisk"] = TRUE
		if(inserted_disk.blueprints.len)
			var/index = 1
			for (var/datum/design/thisdesign in inserted_disk.blueprints)
				if(thisdesign)
					data["diskDesigns"] += list(list("name" = thisdesign.name, "index" = index, "canupload" = thisdesign.build_type&SMELTER))
				index++
	return data

/obj/machinery/mineral/ore_redemption/ui_act(action, params)
	if(..())
		return
	var/datum/component/material_container/mat_container = materials.mat_container
	switch(action)
		if("Eject")
			if(!inserted_id)
				return
			usr.put_in_hands(inserted_id)
			inserted_id = null
			return TRUE
		if("Insert")
			var/obj/item/card/id/I = usr.get_active_held_item()
			if(istype(I))
				if(!usr.transferItemToLoc(I,src))
					return
				inserted_id = I
			else
				to_chat(usr, "<span class='warning'>Not a valid ID!</span>")
			return TRUE
		if("Claim")
			// The card in the slot, or with the slot empty the one the user has on them
			var/obj/item/card/id/claimant = inserted_id || usr.get_idcard(TRUE)
			if(!claimant)
				to_chat(usr, "<span class='warning'>No ID to claim to.</span>")
				return TRUE
			claimant.mining_points += points
			points = 0
			return TRUE
		if("Release")
			if(!mat_container)
				return
			if(materials.on_hold())
				to_chat(usr, "<span class='warning'>Mineral access is on hold, please contact the quartermaster.</span>")
			else if(!check_access(inserted_id) && !allowed(usr)) //Check the ID inside, otherwise check the user
				to_chat(usr, "<span class='warning'>Required access not found.</span>")
			else
				var/mat_id = params["id"]
				if(!mat_container.materials[mat_id])
					return
				var/datum/material/mat = mat_container.materials[mat_id]
				var/stored_amount = mat.amount / MINERAL_MATERIAL_AMOUNT

				if(!stored_amount)
					return

				var/desired = 0
				if (params["all"])
					desired = stored_amount
				else if (!isnull(params["sheets"])) // any count the window sends, 0 included; the prompt only when it sends none
					desired = text2num(params["sheets"])
				else
					desired = tgui_input_number(usr, "How many sheets?", "How many sheets would you like to smelt?", 1)

				// No 50 cap any more: retrieve_sheets() puts it out in stacks of 50
				var/sheets_to_remove = round(min(desired, stored_amount))
				if(sheets_to_remove < 1)
					return TRUE
				var/count = mat_container.retrieve_sheets(sheets_to_remove, mat_id, get_step(src, output_dir))
				var/list/mats = list()
				mats[mat_id] = MINERAL_MATERIAL_AMOUNT
				materials.silo_log(src, "released", -count, "sheets", mats)
			return TRUE
		if("diskInsert")
			var/obj/item/disk/design_disk/disk = usr.get_active_held_item()
			if(istype(disk))
				if(!usr.transferItemToLoc(disk,src))
					return
				inserted_disk = disk
			else
				to_chat(usr, "<span class='warning'>Not a valid Design Disk!</span>")
			return TRUE
		if("diskEject")
			if(inserted_disk)
				usr.put_in_hands(inserted_disk)
				inserted_disk = null
			return TRUE
		if("diskUpload")
			var/n = text2num(params["design"])
			if(inserted_disk && inserted_disk.blueprints && inserted_disk.blueprints[n])
				stored_research.add_design(inserted_disk.blueprints[n])
			return TRUE
		if("Smelt")
			if(!mat_container)
				return
			if(materials.on_hold())
				to_chat(usr, "<span class='warning'>Mineral access is on hold, please contact the quartermaster.</span>")
				return
			var/alloy_id = params["id"]
			var/datum/design/alloy = stored_research.isDesignResearchedID(alloy_id)
			if((check_access(inserted_id) || allowed(usr)) && alloy)
				var/smelt_amount = can_smelt_alloy(alloy)
				var/desired = 0
				if (params["all"])
					desired = smelt_amount
				else if (!isnull(params["sheets"])) // any count the window sends, 0 included; the prompt only when it sends none
					desired = text2num(params["sheets"])
				else
					desired = tgui_input_number(usr, "How many sheets?", "How many sheets would you like to smelt?", 1)
				var/is_sheets = ispath(alloy.build_path, /obj/item/stack/sheet)
				// Checked again after the prompt, and never below 1: a negative count made use_amount() ADD materials
				var/amount = is_sheets ? round(min(desired, can_smelt_alloy(alloy))) : 1
				if(amount < 1 || !mat_container.use_amount(alloy.materials, amount))
					return TRUE
				materials.silo_log(src, "released", -amount, "sheets", alloy.materials)
				if(is_sheets)
					// In stacks of 50: a bigger stack splits itself inside the machine, where the rest was lost
					for(var/left = amount, left > 0, left -= MAX_STACK_SIZE)
						unload_mineral(new alloy.build_path(src, min(left, MAX_STACK_SIZE)))
				else
					unload_mineral(new alloy.build_path(src))
			else
				to_chat(usr, "<span class='warning'>Required access not found.</span>")
			return TRUE

/obj/machinery/mineral/ore_redemption/ex_act(severity, target)
	do_sparks(5, TRUE, src)
	..()

/obj/machinery/mineral/ore_redemption/power_change()
	..()
	update_icon()

/obj/machinery/mineral/ore_redemption/update_icon()
	if(powered())
		icon_state = initial(icon_state)
	else
		icon_state = "[initial(icon_state)]-off"
	update_state_glow() // the screen glows in the dark (see emissive_glow.dm)
