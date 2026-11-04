// hippie -- the autolathe's window in tgui: the same panel as the department techfabs (RdFabricator in tgui-next's
// interfaces/RdConsole.js), with search, item cards, a build queue, and metal and glass that can be taken back out. The old
// browse() window's procs and Topic() are left as they were.

/obj/machinery/autolathe
	/// What's waiting to be made once it's free, as list(design id, amount)
	var/list/build_queue

#define AUTOLATHE_QUEUE_MAX 20

/obj/machinery/autolathe/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	if(!is_operational())
		return
	if(shocked && !(stat & NOPOWER))
		shock(user, 50)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		var/datum/asset/assets = get_asset_datum(/datum/asset/spritesheet/research_designs)
		assets.send(user)
		ui = new(user, src, ui_key, "rd_fabricator", name, 760, 640, master_ui, state)
		ui.open()

/obj/machinery/autolathe/ui_base_html(html)
	var/datum/asset/spritesheet/assets = get_asset_datum(/datum/asset/spritesheet/research_designs)
	. = replacetext(html, "<!--customheadhtml-->", assets.css_tag())

/obj/machinery/autolathe/ui_static_data(mob/user)
	return rd_ui_static_data()

/obj/machinery/autolathe/ui_data(mob/user)
	. = list()
	.["name"] = name
	.["busy"] = busy
	.["disabled"] = disabled
	.["coeff"] = 1 / prod_coeff // the panel divides by it, as the R&D machines' efficiency goes; prod_coeff multiplies
	.["stacks_flat"] = TRUE // every stack costs the same whatever the parts, not only sheets
	.["buildtype"] = ALL // whatever's on it: a design from a disk is made here whatever machine it was for
	.["dept"] = null
	.["categories"] = categories
	.["no_sync"] = TRUE
	.["no_chems"] = TRUE
	.["sheet"] = MINERAL_MATERIAL_AMOUNT
	var/datum/component/material_container/materials = GetComponent(/datum/component/material_container)
	var/list/mat_list = list()
	for(var/id in materials.materials)
		var/datum/material/M = materials.materials[id]
		mat_list += list(list("id" = id, "name" = M.name, "amount" = M.amount))
	.["mats"] = mat_list
	.["storage"] = list("total" = materials.total_amount, "max" = materials.max_amount)
	var/list/queue = list()
	for(var/list/entry in build_queue)
		var/datum/design/D = SSresearch.techweb_design_by_id(entry[1])
		queue += list(list("id" = entry[1], "name" = D ? D.name : entry[1], "amount" = entry[2]))
	.["queue"] = queue
	.["researched"] = assoc_list_strip_value(stored_research.researched_designs)

/obj/machinery/autolathe/ui_act(action, list/params)
	if(..())
		return
	if(disabled) // a cut wire: none of its controls answer
		return
	switch(action)
		if("print")
			print_or_queue(params["id"], text2num(params["amount"]) || 1)
		if("queue_remove")
			var/index = text2num(params["index"])
			if(index >= 1 && index <= length(build_queue))
				build_queue.Cut(index, index + 1)
			UNSETEMPTY(build_queue)
		if("queue_clear")
			build_queue = null
		if("eject_sheets")
			var/datum/component/material_container/materials = GetComponent(/datum/component/material_container)
			var/id = params["mat"]
			if(!(id in materials.materials))
				return
			if(busy) // what's being made is paid for when it's done
				say("Not while it's making something.")
				return
			materials.retrieve_sheets(clamp(text2num(params["amount"]) || 1, 1, 50), id, drop_location())
	return TRUE

/// Made now, or queued behind what's being made.
/obj/machinery/autolathe/proc/print_or_queue(id, amount)
	amount = clamp(round(amount), 1, 50)
	if(busy || length(build_queue))
		if(length(build_queue) >= AUTOLATHE_QUEUE_MAX)
			say("The build queue is full.")
			return FALSE
		LAZYINITLIST(build_queue)
		build_queue += list(list(id, amount))
		return TRUE
	return try_make(id, amount)

/// What the old window's "make" link did, as a proc: starts it if the autolathe's free and has the materials.
/obj/machinery/autolathe/proc/try_make(id, multiplier)
	if(busy || disabled || !is_operational())
		return FALSE
	var/datum/design/D = stored_research.isDesignResearchedID(id)
	if(!D)
		return FALSE
	multiplier = clamp(round(multiplier), 1, 50)
	var/is_stack = ispath(D.build_path, /obj/item/stack)
	var/coeff = is_stack ? 1 : prod_coeff //stacks are unaffected by production coefficient
	var/datum/component/material_container/materials = GetComponent(/datum/component/material_container)
	for(var/mat in D.materials)
		if(materials.amount(mat) < D.materials[mat] * multiplier * coeff)
			return FALSE
	being_built = D
	var/metal_cost = D.materials[MAT_METAL]
	var/glass_cost = D.materials[MAT_GLASS]
	var/power = max(2000, (metal_cost + glass_cost) * multiplier / 5)
	busy = TRUE
	use_power(power)
	icon_state = "autolathe_n"
	var/time = is_stack ? 32 : (32 * coeff * multiplier) ** 0.8
	addtimer(CALLBACK(src, PROC_REF(make_item), power, metal_cost, glass_cost, multiplier, coeff, is_stack), time)
	return TRUE

/obj/machinery/autolathe/make_item(power, metal_cost, glass_cost, multiplier, coeff, is_stack)
	. = ..()
	if(length(build_queue))
		addtimer(CALLBACK(src, PROC_REF(start_next_queued)), 5) //a moment between one job and the next

/// The next thing in the queue that can be made: one it's short of materials for is passed over.
/obj/machinery/autolathe/proc/start_next_queued()
	while(length(build_queue) && !busy && !QDELETED(src))
		var/list/next = build_queue[1]
		build_queue.Cut(1, 2)
		if(try_make(next[1], next[2]))
			break
		var/datum/design/D = SSresearch.techweb_design_by_id(next[1])
		say("Not enough materials for [D ? D.name : "that"]: skipped.")
	UNSETEMPTY(build_queue)

#undef AUTOLATHE_QUEUE_MAX
