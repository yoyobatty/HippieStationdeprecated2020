// hippie -- admin tools that were HTML forms, designed for tgui (interfaces/AdminTools.js): the spawner (Create Object, Create Turf,
// Create Mob and Quick Create Object), the outfit manager and its outfit editor, and Manage Free Slots. The type lists are searched here
// (they're thousands long), what's picked shows its picture, and each action sends the fields the old form or link sent to the admin
// holder's Topic() with the admin token, so the rights checks, limits and logs are the old ones.

/// Every path under a root, made once per root
/proc/admin_type_list(root)
	var/static/list/cache = list()
	var/key = "[root]"
	if(!cache[key])
		var/list/L = list()
		for(var/path in typesof(root))
			L += "[path]"
		cache[key] = L
	return cache[key]

/// The paths under root matching every word of the query, at most `limit`
/proc/admin_type_search(root, query, limit = 200)
	. = list()
	var/list/words = splittext(lowertext(trim("[query]")), " ")
	if(!length(words) || !length(words[1]))
		return
	for(var/path in admin_type_list(root))
		var/lowered = lowertext(path)
		var/match = TRUE
		for(var/word in words)
			if(length(word) && !findtext(lowered, word))
				match = FALSE
				break
		if(match)
			. += path
			if(length(.) >= limit)
				return

/// A path's own picture (its initial icon and state), sent to the viewer once per icon and state, or null
/proc/admin_path_icon(path, mob/user)
	if(!user?.client || !ispath(path, /atom))
		return null
	var/atom/A = path
	var/icon_file = initial(A.icon)
	var/state = initial(A.icon_state)
	if(!isfile(icon_file) || !(state in icon_states(icon_file)))
		return null
	var/static/list/made = list()
	var/known_as = "[icon_file]|[state]"
	var/asset_name = made[known_as]
	if(!asset_name)
		var/icon/picture = icon(icon_file, state, SOUTH, 1)
		asset_name = "[generate_asset_name(picture)].png"
		register_asset(asset_name, picture)
		made[known_as] = asset_name
	send_asset(user.client, asset_name)
	return asset_name

/datum/admins
	/// Tool windows open, by kind
	var/list/tool_windows

/datum/admins/proc/open_admin_tool(kind, type, list/arguments)
	LAZYINITLIST(tool_windows)
	var/datum/admin_tool_window/W = tool_windows[kind]
	if(!W || QDELETED(W))
		W = new type(src, kind)
		tool_windows[kind] = W
	W.setup(arguments)
	W.ui_interact(usr)
	SStgui.update_uis(W)

/datum/admin_tool_window
	var/datum/admins/holder
	var/kind
	var/interface
	var/title
	var/width = 520
	var/height = 600
	/// What check_rights() the tool needs to be open
	var/rights = R_ADMIN

/datum/admin_tool_window/New(datum/admins/H, tool_kind)
	holder = H
	kind = tool_kind

/datum/admin_tool_window/Destroy()
	SStgui.close_uis(src)
	if(holder)
		LAZYREMOVE(holder.tool_windows, kind)
	holder = null
	return ..()

/datum/admin_tool_window/proc/setup(list/arguments)
	return

/datum/admin_tool_window/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, interface, title, width, height, master_ui, state)
		ui.open()

/datum/admin_tool_window/ui_status(mob/user, datum/ui_state/state)
	return (user.client?.holder && user.client.holder == holder && check_rights_for(user.client, rights)) ? UI_INTERACTIVE : UI_CLOSE

/datum/admin_tool_window/ui_close(mob/user)
	if(!QDELETED(src)) // Destroy() closing the window lands here too
		qdel(src)

// ---------------------------------------------------------------------------------------------
// The spawner
// ---------------------------------------------------------------------------------------------

/datum/admins/create_object(mob/user)
	open_admin_tool("spawn_obj", /datum/admin_tool_window/spawner, list("root" = /obj, "title" = "Create Object"))

/datum/admins/create_turf(mob/user)
	open_admin_tool("spawn_turf", /datum/admin_tool_window/spawner, list("root" = /turf, "title" = "Create Turf"))

/datum/admins/create_mob(mob/user)
	open_admin_tool("spawn_mob", /datum/admin_tool_window/spawner, list("root" = /mob, "title" = "Create Mob"))

/datum/admins/quick_create_object(mob/user)
	var/static/list/roots = list(/obj, /obj/structure, /obj/machinery, /obj/effect, /obj/item, /obj/item/clothing, /obj/item/stack, \
		/obj/item/reagent_containers, /obj/item/gun)
	var/path = tgui_input_list(usr, "Select the path of the object you wish to create.", "Path", roots, /obj, allow_cancel = FALSE)
	if(!path)
		return
	open_admin_tool("spawn_obj", /datum/admin_tool_window/spawner, list("root" = path, "title" = "Create [path]"))

/datum/admin_tool_window/spawner
	interface = "admin_spawner"
	width = 560
	height = 640
	rights = R_SPAWN
	var/root = /obj
	var/query = ""
	var/list/results = list()
	var/list/picked = list()
	var/offset = "0,0,0"
	var/offset_type = "relative"
	var/count = 1
	var/spawn_dir = 0
	var/spawn_name = ""
	var/where = "onfloor"

/datum/admin_tool_window/spawner/setup(list/arguments)
	if(arguments["root"] != root)
		root = arguments["root"]
		results = list()
		picked = list()
		query = ""
	title = arguments["title"]

/datum/admin_tool_window/spawner/ui_data(mob/user)
	var/list/chosen = list()
	for(var/path in picked)
		chosen += list(list("path" = path, "icon" = admin_path_icon(text2path(path), user)))
	return list("title" = title, "root" = "[root]", "query" = query, "results" = results, "picked" = chosen, "offset" = offset, \
		"offset_type" = offset_type, "count" = count, "dir" = spawn_dir, "name" = spawn_name, "where" = where, \
		"marked" = holder.marked_datum ? "[holder.marked_datum]" : null, "total" = length(admin_type_list(root)))

/datum/admin_tool_window/spawner/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("search")
			query = copytext("[params["query"]]", 1, 100)
			results = admin_type_search(root, query)
		if("pick")
			var/path = "[params["path"]]"
			if(path in picked)
				picked -= path
			else if((path in admin_type_list(root)) && length(picked) < 5)
				picked += path
		if("clear")
			picked = list()
		if("set")
			var/value = params["value"]
			switch(params["field"])
				if("offset")
					offset = copytext("[value]", 1, 30)
				if("offset_type")
					offset_type = value == "absolute" ? "absolute" : "relative"
				if("count")
					count = clamp(round(text2num(value)), 1, 100)
				if("dir")
					var/d = text2num(value)
					spawn_dir = (d in list(0, 1, 2, 4, 8, 5, 6, 9, 10)) ? d : 0
				if("name")
					spawn_name = copytext("[value]", 1, MAX_NAME_LEN)
				if("where")
					if(value in list("onfloor", "frompod", "inhand", "inmarked"))
						where = value
		if("spawn")
			if(!length(picked))
				return
			// The old form's fields, to the holder's Topic() ("object_list")
			holder.page_holder_link(list("object_list" = picked.Copy(), "offset" = offset, "offset_type" = offset_type, \
				"object_count" = "[count]", "object_dir" = spawn_dir ? "[spawn_dir]" : "", "object_name" = spawn_name, "object_where" = where))
	return TRUE

// ---------------------------------------------------------------------------------------------
// The outfit manager and editor
// ---------------------------------------------------------------------------------------------

/datum/admins/outfit_manager(mob/admin)
	open_admin_tool("outfits", /datum/admin_tool_window/outfits)

/datum/admins/create_outfit(mob/admin)
	open_admin_tool("outfit_editor", /datum/admin_tool_window/outfit_editor)

/datum/admin_tool_window/outfits
	interface = "admin_outfit_manager"
	title = "Outfit Manager"
	width = 460
	height = 460
	rights = R_DEBUG

/datum/admin_tool_window/outfits/ui_data(mob/user)
	var/list/outfits = list()
	for(var/datum/outfit/O in GLOB.custom_outfits)
		var/datum/outfit/varedit/VO = O
		outfits += list(list("ref" = REF(O), "name" = O.name, "vv" = istype(VO) && length(VO.vv_values)))
	return list("outfits" = outfits)

/datum/admin_tool_window/outfits/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("create")
			holder.create_outfit(usr)
		if("load")
			holder.page_holder_link(list("load_outfit" = "1"))
		if("save", "delete")
			var/datum/outfit/O = locate(params["ref"]) in GLOB.custom_outfits
			if(O)
				holder.page_holder_link(list("[action]_outfit" = "1", "chosen_outfit" = REF(O)))
	return TRUE

/datum/admin_tool_window/outfit_editor
	interface = "admin_outfit_editor"
	title = "Create Outfit"
	width = 620
	height = 640
	var/outfit_name = "Custom Outfit"
	/// slot -> path text
	var/list/chosen = list()
	/// The slot being picked for
	var/editing
	var/query = ""
	var/list/results = list()

/// The old form's slots: its field name, label and the types it offered (a dropdown's root; null for its free text boxes)
/datum/admin_tool_window/outfit_editor/proc/slots()
	var/static/list/S = list(
		list("key" = "uniform", "label" = "Uniform", "root" = /obj/item/clothing/under),
		list("key" = "suit", "label" = "Suit", "root" = /obj/item/clothing/suit),
		list("key" = "head", "label" = "Head", "root" = /obj/item/clothing/head),
		list("key" = "mask", "label" = "Mask", "root" = /obj/item/clothing/mask),
		list("key" = "glasses", "label" = "Glasses", "root" = /obj/item/clothing/glasses),
		list("key" = "ears", "label" = "Ears", "root" = /obj/item),
		list("key" = "gloves", "label" = "Gloves", "root" = /obj/item/clothing/gloves),
		list("key" = "shoes", "label" = "Shoes", "root" = /obj/item/clothing/shoes),
		list("key" = "back", "label" = "Back", "root" = /obj/item),
		list("key" = "belt", "label" = "Belt", "root" = /obj/item),
		list("key" = "id", "label" = "ID", "root" = /obj/item/card/id),
		list("key" = "s_store", "label" = "Suit storage", "root" = /obj/item),
		list("key" = "l_pocket", "label" = "Left pocket", "root" = /obj/item),
		list("key" = "r_pocket", "label" = "Right pocket", "root" = /obj/item),
		list("key" = "l_hand", "label" = "Left hand", "root" = /obj/item),
		list("key" = "r_hand", "label" = "Right hand", "root" = /obj/item),
	)
	return S

/datum/admin_tool_window/outfit_editor/proc/slot_root(key)
	for(var/list/S in slots())
		if(S["key"] == key)
			return S["root"]

/datum/admin_tool_window/outfit_editor/ui_data(mob/user)
	var/list/out = list()
	for(var/list/S in slots())
		var/path = chosen[S["key"]]
		var/atom/A = path ? text2path(path) : null
		out += list(list("key" = S["key"], "label" = S["label"], "root" = "[S["root"]]", "path" = path, "name" = A ? initial(A.name) : null, \
			"icon" = A ? admin_path_icon(A, user) : null))
	return list("name" = outfit_name, "slots" = out, "editing" = editing, "query" = query, "results" = results)

/datum/admin_tool_window/outfit_editor/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("name")
			outfit_name = copytext(sanitize("[params["value"]]"), 1, MAX_NAME_LEN)
		if("edit")
			var/key = "[params["slot"]]"
			if(slot_root(key))
				editing = key
				query = ""
				results = list()
		if("search")
			if(!editing)
				return
			query = copytext("[params["query"]]", 1, 100)
			results = admin_type_search(slot_root(editing), query)
		if("choose")
			var/path = "[params["path"]]"
			if(editing && (path in admin_type_list(slot_root(editing))))
				chosen[editing] = path
				editing = null
		if("empty")
			chosen -= "[params["slot"]]"
		if("done")
			editing = null
		if("create")
			// create_outfit_finalize()'s fields, from the old form
			var/list/href_list = list("create_outfit_finalize" = "1", "outfit_name" = outfit_name)
			for(var/list/S in slots())
				href_list["outfit_[S["key"]]"] = chosen[S["key"]] || ""
			holder.page_holder_link(href_list)
			chosen = list()
			outfit_name = "Custom Outfit"
			SStgui.close_uis(src)
	return TRUE

// ---------------------------------------------------------------------------------------------
// Manage Free Slots
// ---------------------------------------------------------------------------------------------

/datum/admins/manage_free_slots()
	if(!check_rights())
		return
	if(!SSjob.initialized)
		tgui_alert(usr, "You cannot manage jobs before the job subsystem is initialized!")
		return
	open_admin_tool("job_slots", /datum/admin_tool_window/job_slots)

/datum/admin_tool_window/job_slots
	interface = "admin_job_slots"
	title = "Manage Free Slots"
	width = 520
	height = 640

/datum/admin_tool_window/job_slots/ui_data(mob/user)
	var/list/jobs = list()
	for(var/datum/job/job in SSjob.occupations)
		jobs += list(list("title" = job.title, "current" = job.current_positions, "total" = job.total_positions))
	var/list/departments = list()
	for(var/list/D in card_console_departments())
		departments += list(list("name" = D["name"], "jobs" = D["jobs"]))
	return list("jobs" = jobs, "departments" = departments)

/datum/admin_tool_window/job_slots/ui_act(action, list/params)
	if(..())
		return
	var/datum/job/job = SSjob.GetJob("[params["job"]]")
	if(!job)
		return
	var/static/list/links = list("add" = "addjobslot", "custom" = "customjobslot", "remove" = "removejobslot", "unlimit" = "unlimitjobslot", "limit" = "limitjobslot")
	if(links[action])
		holder.page_holder_link(list("[links[action]]" = job.title))
	return TRUE
