// hippie -- the exosuit fabricator as a tgui window (tgui-next interfaces/ExosuitFabricator.js), redesigned where it helps (the user's
// ruling, 2026-11-05). The materials down the side with eject buttons; the part sets as tabs with one search over all of them; every part
// with its picture, its cost (red where there isn't enough), its time, Build and Queue and what it is; and the queue beside them, with
// what's printing now and how long it has left, the order changeable, and what the whole queue needs against what's stored. The old
// browse() page was a screen per set, a page per part's description, and a queue that only showed where it could fit.
// build_part() is as it was: bot roboticists print limbs through it (bots_ai/bot_collabs.dm). Topic() stays for anything still on it.

#define FAB_QUEUE_MAX 50

/obj/machinery/mecha_part_fabricator
	/// When the part being built is done, and how long it takes: the window's bar
	var/build_finish = 0
	var/build_length = 0
	/// Updating the designs from a console nearby
	var/syncing = FALSE

/obj/machinery/mecha_part_fabricator/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	var/turf/exit = get_step(src, dir)
	if(exit?.density)
		say("Error! Part outlet is obstructed.")
		return
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		var/datum/asset/assets = get_asset_datum(/datum/asset/spritesheet/research_designs)
		assets.send(user)
		ui = new(user, src, ui_key, "exosuit_fabricator", name, 1040, 700, master_ui, state)
		ui.open()

/obj/machinery/mecha_part_fabricator/ui_base_html(html)
	var/datum/asset/spritesheet/assets = get_asset_datum(/datum/asset/spritesheet/research_designs)
	. = replacetext(html, "<!--customheadhtml-->", assets.css_tag())

/// A researched design this fabricator makes, by its id: nothing else is built from the window
/obj/machinery/mecha_part_fabricator/proc/fab_design(id)
	if(!istext(id) || !(id in stored_research.researched_designs))
		return null
	var/datum/design/D = SSresearch.techweb_design_by_id(id)
	return (D && (D.build_type & MECHFAB)) ? D : null

/obj/machinery/mecha_part_fabricator/ui_static_data(mob/user)
	rd_ui_static_data() //research/rdconsole_tgui.dm: the designs' pictures and the materials' names
	var/list/designs = list()
	for(var/id in stored_research.researched_designs)
		var/datum/design/D = SSresearch.techweb_design_by_id(id)
		if(!D || !(D.build_type & MECHFAB))
			continue
		var/obj/item/part = D.build_path
		var/list/cost = list()
		for(var/M in D.materials)
			cost[M] = get_resource_cost_w_coeff(D, M)
		var/list/sets = list()
		for(var/S in D.category)
			if(S in part_sets)
				sets += S
		var/list/cached = GLOB.rd_ui_designs[id]
		designs += list(list(
			"id" = id,
			"name" = initial(D.name),
			"desc" = initial(part.desc),
			"icon" = cached ? cached["icon"] : null,
			"cost" = cost,
			"time" = get_construction_time_w_coeff(D) / 10,
			"sets" = sets,
		))
	return list(
		"sets" = part_sets,
		"designs" = designs,
		"mat_names" = GLOB.rd_ui_mat_names,
		"sheet" = MINERAL_MATERIAL_AMOUNT,
		"coeff_mats" = round(component_coeff * 100),
		"coeff_time" = round(time_coeff * 100),
	)

/obj/machinery/mecha_part_fabricator/ui_data(mob/user)
	var/list/data = list()
	var/datum/component/material_container/materials = rmat.mat_container
	var/list/mats = list()
	if(materials)
		for(var/mat_id in materials.materials)
			var/datum/material/M = materials.materials[mat_id]
			mats += list(list("id" = mat_id, "name" = M.name, "amount" = M.amount))
	data["mats"] = mats
	data["connected"] = !!materials
	data["silo"] = !!rmat.silo
	data["on_hold"] = rmat.on_hold()
	data["storage"] = materials ? list("total" = materials.total_amount, "max" = materials.max_amount) : null
	var/list/waiting = list()
	for(var/datum/design/D in queue)
		waiting += list(list("id" = D.id, "name" = initial(D.name)))
	data["queue"] = waiting
	data["processing"] = !!processing_queue
	data["building"] = being_built ? list("name" = initial(being_built.name), "left" = max(0, build_finish - world.time) / 10, "length" = build_length / 10) : null
	data["syncing"] = syncing
	return data

/obj/machinery/mecha_part_fabricator/ui_act(action, params)
	if(..())
		return
	switch(action)
		if("build") // the old page's Build: straight away, or into the queue if it's running
			var/datum/design/D = fab_design(params["id"])
			if(!D)
				return
			if(processing_queue || being_built)
				if(length(queue) < FAB_QUEUE_MAX)
					add_to_queue(D)
			else
				INVOKE_ASYNC(src, PROC_REF(build_part), D)
		if("queue")
			var/datum/design/D = fab_design(params["id"])
			if(D && length(queue) < FAB_QUEUE_MAX)
				add_to_queue(D)
		if("queue_set")
			if((params["set"] in part_sets) && length(queue) < FAB_QUEUE_MAX)
				add_part_set_to_queue(params["set"])
				if(length(queue) > FAB_QUEUE_MAX)
					queue.Cut(FAB_QUEUE_MAX + 1)
		if("queue_remove")
			remove_from_queue(text2num(params["index"]))
		if("queue_move")
			var/index = text2num(params["index"])
			var/new_index = index + text2num(params["by"])
			if(ISINTEGER(index) && ISINTEGER(new_index) && ISINRANGE(index, 1, length(queue)) && ISINRANGE(new_index, 1, length(queue)))
				queue.Swap(index, new_index)
		if("queue_clear")
			queue = list()
		if("process")
			INVOKE_ASYNC(src, PROC_REF(do_process_queue))
		if("sync")
			if(!syncing)
				INVOKE_ASYNC(src, PROC_REF(fab_sync))
		if("eject")
			var/datum/component/material_container/materials = rmat.mat_container
			var/amount = text2num(params["amount"])
			if(materials && (params["mat"] in materials.materials) && amount)
				eject_sheets(params["mat"], clamp(round(amount), 1, 50))
	return TRUE

/// The old page's "Sync with R&D servers": the window says it's updating, and gets the new designs after
/obj/machinery/mecha_part_fabricator/proc/fab_sync()
	syncing = TRUE
	SStgui.update_uis(src)
	sleep(30)
	syncing = FALSE
	var/synced = FALSE
	for(var/obj/machinery/computer/rdconsole/RDC in oview(7, src))
		RDC.stored_research.copy_research_to(stored_research)
		synced = TRUE
		break
	say(synced ? "Successfully synchronized with R&D server." : "Unable to connect to local R&D database.")
	fab_push_static()

/// The designs again, to every window open on it
/obj/machinery/mecha_part_fabricator/proc/fab_push_static()
	var/list/by_key = SStgui.open_uis["[REF(src)]"]
	if(!islist(by_key))
		return
	for(var/ui_key in by_key)
		for(var/datum/tgui/ui in by_key[ui_key])
			if(ui?.user)
				ui.push_data(null, ui_static_data(ui.user), TRUE)

/obj/machinery/mecha_part_fabricator/RefreshParts()
	. = ..()
	fab_push_static() //what parts cost and take changes with them

#undef FAB_QUEUE_MAX
