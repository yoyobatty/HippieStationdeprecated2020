// The last machines with old browser pages, in tgui windows (tgui-next MiscMachines.js; the turbine reuses TurbineComputer.js):
// the gas turbine's own panel, the magnetic controller, the stacking machine console, the food cart and the ice cream vat.
// Their moves go through each machine's old Topic(). The carts' Purge never worked: the page sent the reagent's type as text and
// del_reagent() looks for the type itself, so the windows send the type.

// Gas turbine: the same page as its control computer

/obj/machinery/power/turbine/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
										datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "turbine_computer", name, 300, 200, master_ui, state)
		ui.open()

/obj/machinery/power/turbine/ui_data(mob/user)
	var/list/data = list()
	data["compressor"] = !!compressor
	data["compressor_broke"] = !compressor || (compressor.stat & BROKEN)
	data["turbine"] = TRUE
	data["turbine_broke"] = !!(stat & BROKEN)
	data["online"] = compressor ? compressor.starter : FALSE
	data["power"] = DisplayPower(lastgen)
	data["rpm"] = compressor ? compressor.rpm : 0
	data["temp"] = compressor ? compressor.gas_contained.temperature : 0
	return data

/obj/machinery/power/turbine/ui_act(action, params)
	if(..())
		return
	if(action == "toggle_power")
		Topic(null, list("str" = 1))
		return TRUE

// Magnetic controller

/obj/machinery/magnetic_controller/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
										datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "magnet_controller", "Magnetic Control Console", 420, 460, master_ui, state)
		ui.open()

/obj/machinery/magnetic_controller/ui_data(mob/user)
	var/list/data = list()
	data["autolink"] = autolink
	data["frequency"] = frequency
	data["code"] = code
	data["speed"] = speed
	data["path"] = path
	data["moving"] = moving
	var/list/listed = list()
	for(var/obj/machinery/magnetic_module/M in magnets)
		listed += list(list("on" = M.on, "electricity" = M.electricity_level, "field" = M.magnetic_field))
	data["magnets"] = listed
	return data

/obj/machinery/magnetic_controller/ui_act(action, params)
	if(..())
		return
	if(action in list("togglepower", "minuselec", "pluselec", "minusmag", "plusmag"))
		Topic(null, list("radio-op" = action))
	else if(action in list("plusspeed", "minusspeed", "togglemoving"))
		Topic(null, list("operation" = action))
	else if(action == "setpath")
		// The path typed in the window, where it was a pop-up; the same steps after
		var/newpath = trim(copytext(sanitize(params["path"]), 1, MAX_MESSAGE_LEN))
		if(!newpath)
			return
		moving = 0
		path = newpath
		pathpos = 1
		filter_path()
	return TRUE

// Stacking machine console

/obj/machinery/mineral/stacking_unit_console/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
										datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "stacking_console", name, 360, 400, master_ui, state)
		ui.open()

/obj/machinery/mineral/stacking_unit_console/ui_data(mob/user)
	var/list/data = list()
	data["linked"] = !!machine
	var/list/sheets = list()
	if(machine)
		data["stackAmount"] = machine.stack_amt
		for(var/O in machine.stack_list)
			var/obj/item/stack/sheet/S = machine.stack_list[O]
			if(S.amount > 0)
				sheets += list(list("name" = capitalize(S.name), "amount" = S.amount, "type" = "[S.type]"))
	data["sheets"] = sheets
	return data

/obj/machinery/mineral/stacking_unit_console/ui_act(action, params)
	if(..())
		return
	if(action == "release" && machine)
		Topic(null, list("release" = params["type"]))
		return TRUE

// Food cart

/obj/machinery/food_cart/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
										datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "food_cart", "Food Cart", 480, 560, master_ui, state)
		ui.open()

/proc/cart_reagent_list(datum/reagents/holder)
	var/list/listed = list()
	for(var/datum/reagent/R in holder.reagent_list)
		listed += list(list("name" = R.name, "volume" = round(R.volume, 0.1), "type" = "[R.type]"))
	return listed

/obj/machinery/food_cart/ui_data(mob/user)
	var/list/data = list()
	data["glasses"] = glasses
	data["portion"] = portion
	data["reagents"] = cart_reagent_list(reagents)
	data["mixer"] = cart_reagent_list(mixer.reagents)
	var/list/food = list()
	for(var/V in stored_food)
		if(stored_food[V] > 0)
			food += list(list("name" = V, "amount" = stored_food[V]))
	data["food"] = food
	return data

/obj/machinery/food_cart/ui_act(action, params)
	if(..())
		return
	switch(action)
		if("portion")
			var/new_portion = text2num(params["amount"])
			if(isnull(new_portion))
				return
			portion = clamp(round(new_portion), 0, 50)
		if("disposeI", "pour", "mix", "transfer", "m_pour")
			var/reagent_type = text2path(params["type"])
			if(!ispath(reagent_type, /datum/reagent))
				return
			Topic(null, list("[action]" = reagent_type))
		if("dispense")
			if(!stored_food[params["name"]])
				return
			Topic(null, list("dispense" = params["name"]))
	return TRUE

// Ice cream vat (1-4 the flavours, 5-6 the cones, as its defines)

/obj/machinery/icecream_vat/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
										datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "icecream_vat", "Ice Cream Vat", 520, 560, master_ui, state)
		ui.open()

/obj/machinery/icecream_vat/ui_data(mob/user)
	var/list/data = list()
	data["selected"] = dispense_flavour
	var/list/products = list()
	var/list/ingredients = list("milk, ice", "milk, ice, coco powder", "milk, ice, berry juice", "milk, ice, singulo", "flour, sugar", "flour, sugar, coco powder")
	for(var/i in 1 to 6)
		products += list(list("id" = i, "name" = capitalize(get_flavour_name(i)), "amount" = product_types[i], "cone" = i > 4, "ingredients" = ingredients[i]))
	data["products"] = products
	data["reagents"] = cart_reagent_list(reagents)
	return data

/obj/machinery/icecream_vat/ui_act(action, params)
	if(..())
		return
	var/id = text2num(params["id"])
	switch(action)
		if("select")
			if(id in 1 to 4)
				Topic(null, list("select" = "[id]"))
		if("cone")
			if(id in 5 to 6)
				Topic(null, list("cone" = "[id]"))
		if("make")
			var/amount = text2num(params["amount"])
			if((id in 1 to 6) && (amount in list(1, 5)))
				Topic(null, list("make" = "[id]", "amount" = "[amount]"))
		if("disposeI")
			var/reagent_type = text2path(params["type"])
			if(ispath(reagent_type, /datum/reagent))
				Topic(null, list("disposeI" = reagent_type))
	return TRUE
