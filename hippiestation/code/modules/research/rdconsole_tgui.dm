// The R&D console as a tgui window (tgui-next interfaces/RdConsole.js). One live page: the points at the top, one search over every node,
// what it says and every design it unlocks, the nodes as cards with what each needs and unlocks and the way there from what's researched,
// and the linked protolathe, imprinter and analyzer as tabs. The old browse() page rebuilt itself on every click and jumped back to the
// top: a player clicked one node seven times in six seconds before researching it.
//
// The old page's Topic() stays (rdconsole.dm): bot traitors copy the research to a tech disk through it.

/// Nodes and designs as the console and the fabricators show them. The same every round, built the first time a window opens (the design
/// sprites aren't drawn until after the world starts: /datum/asset/spritesheet/research_designs, build_after_init).
GLOBAL_LIST_EMPTY(rd_ui_nodes)
GLOBAL_LIST_EMPTY(rd_ui_designs)
GLOBAL_LIST_EMPTY(rd_ui_mat_names)

/proc/rd_ui_static_data()
	if(!length(GLOB.rd_ui_nodes))
		for(var/id in SSresearch.techweb_nodes)
			var/datum/techweb_node/N = SSresearch.techweb_nodes[id]
			// id = TRUE lists since the node's Initialize(): plain lists for the page, or they'd go over as objects
			GLOB.rd_ui_nodes += list(list(
				"id" = N.id,
				"name" = N.display_name,
				"desc" = N.description,
				"prereqs" = assoc_list_strip_value(N.prereq_ids),
				"unlocks" = assoc_list_strip_value(N.unlock_ids),
				"designs" = assoc_list_strip_value(N.design_ids),
				"cost" = N.research_costs[TECHWEB_POINT_TYPE_GENERIC] || 0,
			))
	if(!length(GLOB.rd_ui_designs))
		var/datum/asset/spritesheet/sheet = get_asset_datum(/datum/asset/spritesheet/research_designs)
		for(var/id in SSresearch.techweb_designs)
			var/datum/design/D = SSresearch.techweb_designs[id]
			var/list/mats = list()
			for(var/M in D.materials)
				mats[M] = D.materials[M]
				if(!GLOB.rd_ui_mat_names[M])
					GLOB.rd_ui_mat_names[M] = CallMaterialName(M)
			for(var/R in D.reagents_list)
				mats["[R]"] = D.reagents_list[R]
				if(!GLOB.rd_ui_mat_names["[R]"])
					GLOB.rd_ui_mat_names["[R]"] = CallMaterialName(R)
			GLOB.rd_ui_designs[id] = list(
				"name" = D.name,
				"icon" = sheet.icon_class_name(id),
				"build" = D.build_type,
				"mats" = mats,
				"cats" = D.category,
				// One home each on the protolathe/techfabs and on the imprinter (design_groups.dm)
				"lathe" = (D.build_type & PROTOLATHE) ? D.lathe_group() : null,
				"board" = (D.build_type & IMPRINTER) ? D.board_group() : null,
				"dept" = D.departmental_flags,
				// Sheets and bluespace crystals cost the same whatever the manipulators (production/efficient_with()).
				"flat" = ispath(D.build_path, /obj/item/stack/sheet) || ispath(D.build_path, /obj/item/stack/ore/bluespace_crystal),
				// Any stack: the autolathe's parts change none of them, and they're made 50 at a time (autolathe_tgui.dm)
				"stack" = ispath(D.build_path, /obj/item/stack),
			)
	return list(
		"nodes" = GLOB.rd_ui_nodes,
		"designs" = GLOB.rd_ui_designs,
		"mat_names" = GLOB.rd_ui_mat_names,
		"build_types" = list("protolathe" = PROTOLATHE, "imprinter" = IMPRINTER, "autolathe" = AUTOLATHE, "mechfab" = MECHFAB, "biogenerator" = BIOGENERATOR, "limbgrower" = LIMBGROWER, "smelter" = SMELTER),
	)

/obj/machinery/computer/rdconsole/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		var/datum/asset/assets = get_asset_datum(/datum/asset/spritesheet/research_designs)
		assets.send(user)
		ui = new(user, src, ui_key, "rdconsole", name, 960, 680, master_ui, state)
		ui.open()

/obj/machinery/computer/rdconsole/ui_base_html(html)
	var/datum/asset/spritesheet/assets = get_asset_datum(/datum/asset/spritesheet/research_designs)
	. = replacetext(html, "<!--customheadhtml-->", assets.css_tag())

/obj/machinery/computer/rdconsole/ui_static_data(mob/user)
	return rd_ui_static_data()

/obj/machinery/computer/rdconsole/ui_data(mob/user)
	. = list()
	.["locked"] = locked
	.["emagged"] = !!(obj_flags & EMAGGED)
	.["research_control"] = research_control
	.["org"] = stored_research.organization
	.["points"] = round(stored_research.research_points[TECHWEB_POINT_TYPE_GENERIC] || 0)
	var/last = stored_research.last_bitcoins[TECHWEB_POINT_TYPE_GENERIC] || 0
	.["per_minute"] = round(last * ((SSresearch.flags & SS_TICKER) ? (600 / (world.tick_lag * SSresearch.wait)) : (600 / SSresearch.wait)))
	var/list/researched = list()
	var/list/from_nodes = list()
	for(var/id in stored_research.researched_nodes)
		researched += id
		var/datum/techweb_node/N = SSresearch.techweb_node_by_id(id)
		for(var/design_id in N?.design_ids)
			from_nodes[design_id] = TRUE
	.["researched"] = researched
	var/list/available = list()
	for(var/id in stored_research.available_nodes)
		if(!stored_research.researched_nodes[id])
			available += id
	.["available"] = available
	var/list/hidden = list()
	for(var/id in stored_research.hidden_nodes)
		hidden += id
	.["hidden"] = hidden
	// Costs a boost has brought down, by node: the rest cost what they always do.
	var/list/costs = list()
	for(var/id in stored_research.boosted_nodes)
		var/datum/techweb_node/N = SSresearch.techweb_node_by_id(id)
		if(N)
			costs[id] = N.get_price(stored_research)[TECHWEB_POINT_TYPE_GENERIC] || 0
	.["costs"] = costs
	// Designs it has that no researched node gave it: off a disk, or given.
	var/list/extra = list()
	for(var/design_id in stored_research.researched_designs)
		if(!from_nodes[design_id])
			extra += design_id
	.["extra_designs"] = extra
	.["panel_prefs"] = lathe_panel_prefs(user)
	.["lathe"] = linked_lathe?.fabricator_data()
	.["imprinter"] = linked_imprinter?.fabricator_data()
	.["analyzer"] = linked_destroy ? analyzer_data() : null
	.["samples"] = GLOB.sample_board.board_data() // sample_requests.dm
	if(t_disk)
		var/list/disk_nodes = list()
		for(var/id in t_disk.stored_research.researched_nodes)
			disk_nodes += id
		.["tdisk"] = list("nodes" = disk_nodes)
	if(d_disk)
		var/list/slots = list()
		for(var/i in 1 to d_disk.max_blueprints)
			var/datum/design/D = d_disk.blueprints[i]
			slots += istype(D) ? D.id : ""
		.["ddisk"] = list("slots" = slots)

/// What the analyzer has in it, and what destroying it would do for which nodes.
/obj/machinery/computer/rdconsole/proc/analyzer_data()
	var/obj/machinery/rnd/destructive_analyzer/A = linked_destroy
	var/obj/item/I = A.loaded_item
	. = list("busy" = A.busy, "item" = I?.name)
	if(!I)
		return
	.["sample"] = analyzer_sample_data(I)
	var/list/options = list()
	var/list/boostable = techweb_item_boost_check(I)
	for(var/id in boostable)
		var/datum/techweb_node/N = SSresearch.techweb_node_by_id(id)
		if(!N)
			continue
		var/list/worth = boostable[id]
		var/state
		var/amount = 0
		if(stored_research.researched_nodes[id])
			state = "researched"
		else if(!length(worth))
			state = stored_research.hidden_nodes[id] ? "reveal" : "revealed"
		else
			var/list/already = stored_research.boosted_nodes[id]
			for(var/kind in worth)
				amount += max(0, min(worth[kind], N.research_costs[kind]) - (already ? already[kind] : 0))
			state = amount > 0 ? "boost" : "boosted"
		options += list(list("id" = id, "name" = N.display_name, "state" = state, "amount" = amount))
	.["options"] = options
	var/list/points = techweb_item_point_check(I)
	.["points"] = points ? (points[TECHWEB_POINT_TYPE_GENERIC] || 0) : 0
	.["points_claimed"] = !!stored_research.deconstructed_items[I.type]
	.["materials"] = length(I.materials)
	.["indestructible"] = !!(I.resistance_flags & INDESTRUCTIBLE)

/obj/machinery/computer/rdconsole/proc/linked_machine(key)
	switch(key)
		if("lathe")
			return linked_lathe
		if("imprinter")
			return linked_imprinter
		if("analyzer")
			return linked_destroy

/obj/machinery/computer/rdconsole/ui_act(action, list/params)
	if(..())
		return
	add_fingerprint(usr)
	if(action == "unlock" || action == "lock")
		if(action == "lock" && (obj_flags & EMAGGED))
			to_chat(usr, "<span class='boldwarning'>Security protocol error: Unable to lock.</span>")
		else if(allowed(usr))
			if(action == "lock")
				lock_console(usr)
			else
				unlock_console(usr)
		else
			to_chat(usr, "<span class='boldwarning'>Unauthorized Access.</span>")
		return TRUE
	if(action == "panel_pref")
		lathe_panel_pref_set(usr, params["key"], params["value"])
		return TRUE
	if(locked)
		return
	var/obj/machinery/rnd/production/P = linked_machine(params["machine"])
	switch(action)
		if("research")
			if(research_control && stored_research.available_nodes[params["id"]])
				research_node(params["id"], usr)
		if("print")
			if(istype(P))
				P.print_or_queue(params["id"], text2num(params["amount"]) || 1)
		if("queue_remove")
			if(istype(P))
				P.queue_remove(text2num(params["index"]))
		if("queue_clear")
			if(istype(P))
				P.build_queue = null
		if("eject_sheets")
			if(istype(P) && P.materials.mat_container)
				P.eject_sheets(params["mat"], text2num(params["amount"]))
		if("purge")
			var/chem = text2path(params["chem"])
			if(istype(P) && chem)
				P.reagents.del_reagent(chem)
		if("purge_all")
			if(istype(P))
				P.reagents.clear_reagents()
		if("decon")
			var/node_id = params["id"] == "reclaim" ? RESEARCH_MATERIAL_RECLAMATION_ID : params["id"]
			if(linked_destroy && !linked_destroy.busy && !linked_destroy.user_try_decon_id(node_id, usr))
				say("Destructive analysis failed!")
		if("hand_in")
			hand_in_sample(usr)
		if("eject_item")
			if(linked_destroy && !linked_destroy.busy)
				linked_destroy.unload_item()
		if("tdisk_upload")
			if(t_disk)
				say("Uploading technology disk.")
				t_disk.stored_research.copy_research_to(stored_research)
		if("tdisk_download")
			if(t_disk)
				say("Downloading to technology disk.")
				stored_research.copy_research_to(t_disk.stored_research)
		if("tdisk_clear")
			if(t_disk)
				say("Wiping technology disk.")
				qdel(t_disk.stored_research)
				t_disk.stored_research = new
		if("tdisk_eject")
			if(t_disk)
				say("Ejecting Technology Disk")
				eject_disk("tech")
		if("ddisk_upload")
			if(d_disk)
				var/slot = text2num(params["slot"])
				for(var/i in 1 to d_disk.max_blueprints)
					if((!slot || slot == i) && d_disk.blueprints[i])
						stored_research.add_design(d_disk.blueprints[i], TRUE)
		if("ddisk_clear")
			if(d_disk)
				var/slot = text2num(params["slot"])
				for(var/i in 1 to d_disk.max_blueprints)
					if(!slot || slot == i)
						d_disk.blueprints[i] = null
				say("Wiping design disk.")
		if("ddisk_copy")
			if(d_disk && stored_research.researched_designs[params["id"]])
				copy_design_to_disk(text2num(params["slot"]), SSresearch.techweb_design_by_id(params["id"]))
		if("ddisk_eject")
			if(d_disk)
				say("Ejecting Design Disk")
				eject_disk("design")
		if("resync")
			SyncRDevices()
			say("Resynced with nearby devices.")
		if("disconnect")
			var/obj/machinery/rnd/M = linked_machine(params["machine"])
			if(M)
				M.linked_console = null
				if(M == linked_lathe)
					linked_lathe = null
				else if(M == linked_imprinter)
					linked_imprinter = null
				else if(M == linked_destroy)
					linked_destroy = null
	return TRUE

/// A design onto a slot of the design disk, the way the old page did it: anything a protolathe makes from metal and glass alone is made
/// autolathe-friendly as it goes.
/obj/machinery/computer/rdconsole/proc/copy_design_to_disk(slot, datum/design/D)
	if(!D || !slot || slot > d_disk.max_blueprints)
		return
	var/autolathe_friendly = TRUE
	if(D.reagents_list.len)
		autolathe_friendly = FALSE
		D.category -= "Imported"
	else
		for(var/x in D.materials)
			if(!(x in list(MAT_METAL, MAT_GLASS)))
				autolathe_friendly = FALSE
				D.category -= "Imported"
	if(D.build_type & (AUTOLATHE|PROTOLATHE|CRAFTLATHE))
		D.build_type = autolathe_friendly ? (D.build_type | AUTOLATHE) : D.build_type
		D.category |= "Imported"
	d_disk.blueprints[slot] = D

// ---------------------------------------------------------------------------------------------
// The fabricators: the console's protolathe and imprinter tabs, and the department ones on their own (interfaces/RdFabricator.js)
// ---------------------------------------------------------------------------------------------

/obj/machinery/rnd/production
	/// What's waiting to be printed once the machine's free, as list(design id, amount): the user's "lathe build queue".
	var/list/build_queue

#define RD_QUEUE_MAX 20

/// Printed now, or queued behind what's printing.
/obj/machinery/rnd/production/proc/print_or_queue(id, amount)
	amount = clamp(round(amount), 1, 50)
	if(busy || length(build_queue))
		if(length(build_queue) >= RD_QUEUE_MAX)
			say("The build queue is full.")
			return FALSE
		LAZYINITLIST(build_queue)
		build_queue += list(list(id, amount))
		return TRUE
	return user_try_print_id(id, amount)

/obj/machinery/rnd/production/proc/queue_remove(index)
	if(index >= 1 && index <= length(build_queue))
		build_queue.Cut(index, index + 1)
	UNSETEMPTY(build_queue)

/obj/machinery/rnd/production/reset_busy()
	. = ..()
	if(length(build_queue))
		addtimer(CALLBACK(src, PROC_REF(start_next_queued)), 5) //a moment between one job and the next

/// The next thing in the queue that can be made: one short of materials says why and is passed over.
/obj/machinery/rnd/production/proc/start_next_queued()
	while(length(build_queue) && !busy && !QDELETED(src))
		var/list/next = build_queue[1]
		build_queue.Cut(1, 2)
		if(user_try_print_id(next[1], next[2]))
			break
	UNSETEMPTY(build_queue)

/// The machine's side of the window: materials, chemicals, the queue, and what it builds.
/obj/machinery/rnd/production/proc/fabricator_data()
	. = list()
	.["busy"] = busy
	.["coeff"] = efficiency_coeff
	.["buildtype"] = allowed_buildtypes
	.["categories"] = categories //its own: designs carry the autolathe's "initial" and "hacked" as well
	// Which of a design's groups this machine lists it under, the first it has: a techfab makes both kinds
	var/list/grouping = list()
	if(allowed_buildtypes & PROTOLATHE)
		grouping += "lathe"
	if(allowed_buildtypes & IMPRINTER)
		grouping += "board"
	.["grouping"] = grouping
	.["dept"] = allowed_department_flags //null: anything at all, no department flags or not (user_try_print_id())
	var/datum/component/material_container/mats = materials?.mat_container
	var/list/mat_list = list()
	if(mats)
		for(var/id in mats.materials)
			var/datum/material/M = mats.materials[id]
			mat_list += list(list("id" = id, "name" = M.name, "amount" = M.amount))
		.["storage"] = list("total" = mats.total_amount, "max" = mats.max_amount)
	.["mats"] = mat_list
	.["sheet"] = MINERAL_MATERIAL_AMOUNT
	.["silo"] = !!materials?.silo
	.["on_hold"] = !!materials?.on_hold()
	var/list/chems = list()
	for(var/datum/reagent/R in reagents.reagent_list)
		chems += list(list("id" = "[R.type]", "name" = R.name, "volume" = round(R.volume, 0.1)))
	.["chems"] = chems
	.["chem_volume"] = round(reagents.total_volume, 0.1)
	.["chem_max"] = reagents.maximum_volume
	var/list/queue = list()
	for(var/list/entry in build_queue)
		var/datum/design/D = SSresearch.techweb_design_by_id(entry[1])
		queue += list(list("id" = entry[1], "name" = D ? D.name : entry[1], "amount" = entry[2]))
	.["queue"] = queue

/obj/machinery/rnd/production/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	if(!consoleless_interface)
		return //worked from the R&D console it's linked to
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		var/datum/asset/assets = get_asset_datum(/datum/asset/spritesheet/research_designs)
		assets.send(user)
		ui = new(user, src, ui_key, "rd_fabricator", name, 760, 640, master_ui, state)
		ui.open()

/obj/machinery/rnd/production/ui_base_html(html)
	var/datum/asset/spritesheet/assets = get_asset_datum(/datum/asset/spritesheet/research_designs)
	. = replacetext(html, "<!--customheadhtml-->", assets.css_tag())

/obj/machinery/rnd/production/ui_static_data(mob/user)
	return rd_ui_static_data()

/obj/machinery/rnd/production/ui_data(mob/user)
	. = fabricator_data()
	var/list/designs = list()
	for(var/datum/design/D in cached_designs)
		designs += D.id
	.["researched"] = designs
	.["name"] = name
	.["panel_prefs"] = lathe_panel_prefs(user)

/obj/machinery/rnd/production/ui_act(action, list/params)
	if(..())
		return
	if(action == "panel_pref")
		lathe_panel_pref_set(usr, params["key"], params["value"])
		return TRUE
	switch(action)
		if("print")
			print_or_queue(params["id"], text2num(params["amount"]) || 1)
		if("queue_remove")
			queue_remove(text2num(params["index"]))
		if("queue_clear")
			build_queue = null
		if("eject_sheets")
			if(materials.mat_container)
				eject_sheets(params["mat"], text2num(params["amount"]))
		if("purge")
			var/chem = text2path(params["chem"])
			if(chem)
				reagents.del_reagent(chem)
		if("purge_all")
			reagents.clear_reagents()
		if("sync")
			update_research()
			say("Synchronized with the research network.")
	return TRUE

#undef RD_QUEUE_MAX
