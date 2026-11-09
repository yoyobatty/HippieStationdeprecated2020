// hippie -- sandbox mode's windows in tgui (interfaces/Sandbox.js): the Sandbox Panel (the build kit as buttons, and a search with
// pictures for clothes, reagent containers and other items) and the airlock maker (name, paint, glass, access by department). Each
// button still goes through the panel's or maker's own Topic(), so what spawns and who may spawn it are the old rules.

// ---------------------------------------------------------------------------------------------
// The Sandbox Panel
// ---------------------------------------------------------------------------------------------

/// The panel's buttons: section, then label = list(hsb, path)
/proc/sandbox_buttons()
	var/static/list/buttons = list(
		"Space gear" = list(
			"Suit up" = list("hsbsuit"),
			"Gas mask" = list("hsbspawn", /obj/item/clothing/mask/gas),
			"Emergency air tank" = list("hsbspawn", /obj/item/tank/internals/emergency_oxygen/double),
		),
		"Tools" = list(
			"Flashlight" = list("hsbspawn", /obj/item/flashlight),
			"Toolbox" = list("hsbspawn", /obj/item/storage/toolbox/mechanical),
			"Light replacer" = list("hsbspawn", /obj/item/lightreplacer),
			"Medkit" = list("hsbspawn", /obj/item/storage/firstaid/regular),
			"All-access ID" = list("hsbaaid"),
		),
		"Building" = list(
			"50 wood" = list("hsbwood"),
			"50 metal" = list("hsbmetal"),
			"50 plasteel" = list("hsbplasteel"),
			"50 reinforced glass" = list("hsbrglass"),
			"50 glass" = list("hsbglass"),
			"Cable coil" = list("hsbspawn", /obj/item/stack/cable_coil),
			"Hyper power cell" = list("hsbspawn", /obj/item/stock_parts/cell/hyper),
			"Infinite power cell" = list("hsbspawn", /obj/item/stock_parts/cell/infinite),
			"RCD" = list("hsbrcd"),
			"RCD ammo" = list("hsb_safespawn", /obj/item/rcd_ammo),
			"Airlock" = list("hsbairlock"),
		),
		"Other" = list(
			"Air scrubber" = list("hsbscrubber"),
			"Fuel tank" = list("hsbspawn", /obj/structure/reagent_dispensers/fueltank),
			"Water tank" = list("hsbspawn", /obj/structure/reagent_dispensers/watertank),
			"Cleanbot" = list("hsbspawn", /mob/living/simple_animal/bot/cleanbot),
			"Floorbot" = list("hsbspawn", /mob/living/simple_animal/bot/floorbot),
			"Medbot" = list("hsbspawn", /mob/living/simple_animal/bot/medbot),
			"O2 canister" = list("hsbspawn", /obj/machinery/portable_atmospherics/canister/oxygen),
			"Air canister" = list("hsbspawn", /obj/machinery/portable_atmospherics/canister/air),
		),
	)
	return buttons

/proc/sandbox_admin_buttons()
	var/static/list/buttons = list(
		"Plasma canister" = list("hsbspawn", /obj/machinery/portable_atmospherics/canister/toxins),
		"CO2 canister" = list("hsbspawn", /obj/machinery/portable_atmospherics/canister/carbon_dioxide),
		"N2 canister" = list("hsbspawn", /obj/machinery/portable_atmospherics/canister/nitrogen),
		"N2O canister" = list("hsbspawn", /obj/machinery/portable_atmospherics/canister/nitrous_oxide),
	)
	return buttons

/datum/hSB
	/// The item search: which list and what's typed, and what it found
	var/search_kind = "cloth"
	var/search_query = ""
	var/list/search_results

/datum/hSB/update()
	ui_interact(usr)

/datum/hSB/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "sandbox_panel", "Sandbox Panel", 560, 640, master_ui, GLOB.always_state)
		ui.open()

/datum/hSB/ui_status(mob/user, datum/ui_state/state)
	return user?.ckey == owner ? UI_INTERACTIVE : UI_CLOSE

/datum/hSB/ui_static_data(mob/user)
	var/list/sections = list()
	var/list/buttons = sandbox_buttons()
	if(admin)
		buttons = list("Admin canisters" = sandbox_admin_buttons()) + buttons
	for(var/section in buttons)
		var/list/rows = list()
		for(var/label in buttons[section])
			rows += label
		sections += list(list("name" = section, "buttons" = rows))
	return list("sections" = sections)

/datum/hSB/ui_data(mob/user)
	return list("admin" = admin, "spawning" = GLOB.hsboxspawn, "search_kind" = search_kind, "search_query" = search_query, \
		"results" = search_results || list())

/// What the item search looks through: clothes, reagent containers, or the other items
/datum/hSB/proc/search_paths(kind, query)
	. = list()
	var/root = /obj/item
	if(kind == "cloth")
		root = /obj/item/clothing
	else if(kind == "reag")
		root = /obj/item/reagent_containers
	for(var/text_path in admin_type_search(root, query, 400))
		var/path = text2path(text_path)
		if(!path || is_type_in_list(path, spawn_forbidden))
			continue
		if(kind == "obj" && (ispath(path, /obj/item/clothing) || ispath(path, /obj/item/reagent_containers)))
			continue
		. += path
		if(length(.) >= 60)
			return

/datum/hSB/ui_act(action, list/params)
	if(..())
		return
	if(usr.ckey != owner)
		return
	switch(action)
		if("button")
			var/list/found
			var/list/all = sandbox_buttons()
			if(admin)
				all = list("Admin canisters" = sandbox_admin_buttons()) + all
			for(var/section in all)
				if(params["section"] == section)
					found = all[section][params["label"]]
			if(!found)
				return
			var/list/href_list = list("hsb" = found[1])
			if(length(found) > 1)
				href_list["path"] = "[found[2]]"
			Topic(null, href_list)
		if("search")
			if(params["kind"] in list("cloth", "reag", "obj"))
				search_kind = params["kind"]
			search_query = copytext("[params["query"]]", 1, 60)
			search_results = list()
			if(GLOB.hsboxspawn && length(trim(search_query)) >= 2)
				for(var/path in search_paths(search_kind, search_query))
					var/obj/item/I = path
					search_results += list(list("path" = "[path]", "name" = initial(I.name), "icon" = admin_path_icon(path, usr)))
		if("spawn_item")
			var/path = text2path("[params["path"]]")
			if(!ispath(path, /obj/item) || is_type_in_list(path, spawn_forbidden))
				return
			Topic(null, list("hsb" = "hsb_safespawn", "path" = "[path]"))
		if("toggle_spawning")
			if(admin)
				Topic(null, list("hsb" = "hsbtobj"))
	return TRUE

// ---------------------------------------------------------------------------------------------
// The airlock maker
// ---------------------------------------------------------------------------------------------

/datum/airlock_maker/interact()
	ui_interact(usr)

/datum/airlock_maker/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "airlock_maker", "Airlock maker", 600, 560, master_ui, GLOB.always_state)
		ui.open()

/datum/airlock_maker/ui_status(mob/user, datum/ui_state/state)
	return (linked && !QDELETED(linked) && linked.loc) ? UI_INTERACTIVE : UI_CLOSE

/datum/airlock_maker/ui_static_data(mob/user)
	var/list/regions = list()
	for(var/code in 1 to 7)
		var/list/accesses = list()
		for(var/access in get_region_accesses(code))
			accesses += list(list("id" = access, "name" = get_access_desc(access)))
		regions += list(list("name" = get_region_accesses_name(code), "accesses" = accesses))
	return list("regions" = regions, "paints" = list("none", "engineering", "atmos", "security", "command", "medical", "research", \
		"mining", "maintenance", "external", "highsecurity"))

/datum/airlock_maker/ui_data(mob/user)
	return list("name" = doorname, "paint" = paintjob, "glass" = glassdoor, "require_all" = require_all, "access" = access_used)

/datum/airlock_maker/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("rename")
			var/new_name = stripped_input_text("[params["name"]]", MAX_CHARTER_LEN)
			if(new_name)
				doorname = new_name
		if("access")
			var/access = text2num("[params["id"]]")
			if(access in get_all_accesses())
				Topic(null, list("access" = "[access]"))
				return TRUE
		if("reqall", "glass")
			Topic(null, list("[action]" = "1"))
			return TRUE
		if("paint")
			if(params["paint"] in list("none", "engineering", "atmos", "security", "command", "medical", "research", "mining", "maintenance", "external", "highsecurity"))
				Topic(null, list("paint" = params["paint"]))
				return TRUE
		if("done", "cancel")
			SStgui.close_uis(src)
			Topic(null, list("[action]" = "1"))
	return TRUE
