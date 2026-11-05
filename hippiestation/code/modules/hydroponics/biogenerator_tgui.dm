// hippie -- the biogenerator is a tgui window: its biomass, what's in the reactor waiting, the container, Activate and Detach, and
// everything it can make in its groups, with a picture, the biomass each costs and Make, x5 and x10 where the old window had them.
// The buttons go through the biogenerator's own Topic(), so the checks and what it makes are the old window's.

/obj/machinery/biogenerator
	/// What it makes, by group, for the window: made again only when a design disk adds to it or new parts change the cost
	var/list/ui_categories
	var/ui_categories_made_for
	var/list/ui_pictures

/obj/machinery/biogenerator/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	if(stat & BROKEN || panel_open)
		return
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "biogenerator", name, 500, 640, master_ui, state)
		ui.open()

/obj/machinery/biogenerator/proc/biogen_ui_categories(mob/user)
	var/made_for = "[length(stored_research.researched_designs)]|[efficiency]"
	if(ui_categories && ui_categories_made_for == made_for)
		return ui_categories
	ui_categories_made_for = made_for
	ui_categories = list()
	ui_pictures = list()
	for(var/category in show_categories)
		var/list/designs = list()
		for(var/id in stored_research.researched_designs)
			var/datum/design/D = SSresearch.techweb_design_by_id(id)
			if(!(category in D.category))
				continue
			var/atom/path = D.build_path
			var/picture = path ? tgui_item_picture(initial(path.icon), initial(path.icon_state), user) : null
			if(picture)
				ui_pictures |= picture
			designs += list(list(
				"id" = D.id,
				"name" = D.name,
				"cost" = round(D.materials[MAT_BIOMASS] / efficiency, 0.1),
				"times5" = (category in timesFiveCategories),
				"stack" = ispath(path, /obj/item/stack),
				"icon" = picture,
				"reagent" = !path && length(D.make_reagents), // poured into the container: no thing to picture
			))
		ui_categories += list(list("name" = category, "designs" = designs))
	return ui_categories

/obj/machinery/biogenerator/ui_data(mob/user)
	var/list/data = list()
	data["points"] = round(points, 0.1)
	data["processing"] = processing
	var/growns = 0
	for(var/obj/item/reagent_containers/food/snacks/grown/G in contents)
		growns++
	data["growns"] = growns
	data["max_items"] = max_items
	data["beaker"] = beaker ? list("name" = beaker.name, "volume" = beaker.reagents.total_volume, "max" = beaker.reagents.maximum_volume) : null
	var/static/list/notices = list(
		"nopoints" = "Not enough biomass for that. Put growns into the reactor and activate it.",
		"complete" = "Operation complete.",
		"void" = "No growns inside. Put growns into the reactor.",
		"nobeakerspace" = "Not enough space left in the container for that.",
	)
	data["notice"] = notices[menustat]
	data["notice_good"] = menustat == "complete"
	data["categories"] = biogen_ui_categories(user)
	if(user?.client && length(ui_pictures))
		send_asset_list(user.client, ui_pictures)
	return data

/obj/machinery/biogenerator/ui_act(action, params)
	if(..())
		return
	menustat = "menu" // the old window showed each message once
	switch(action)
		if("activate")
			Topic(null, list("activate" = "1"))
		if("detach")
			Topic(null, list("detach" = "1"))
		if("create")
			var/amount = text2num(params["amount"])
			var/id = params["id"]
			if(!(amount in list(1, 5, 10)) || !istext(id) || !stored_research.researched_designs.Find(id))
				return
			Topic(null, list("create" = id, "amount" = "[amount]"))
	return TRUE
