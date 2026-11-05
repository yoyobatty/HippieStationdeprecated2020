// hippie -- the plant DNA manipulator is a tgui window: the sample and the disk on top with Insert or Eject, the seed's core,
// content and trait genes with Extract, Replace, Remove and Insert where the old window had them, and the confirmation in place, with
// what the machine's parts will degrade a gene to on extraction. The buttons go through the manipulator's own Topic(), so the checks
// and the two clicks (choose, then confirm) are the old window's. Bot botanists don't use the window: they work the machine directly
// (goals/botany_projects.dm).

/obj/machinery/plantgenes/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "plant_dna_manipulator", "Plant DNA Manipulator", 480, 620, master_ui, state)
		ui.open()

/// What this machine's parts limit a core gene to on extraction, if the gene's beyond it: "extracts at 62"
/obj/machinery/plantgenes/proc/gene_extract_limit(datum/plant_gene/core/G)
	if(!istype(G))
		return null
	var/limit
	if(istype(G, /datum/plant_gene/core/potency))
		limit = G.value > max_potency ? max_potency : null
	else if(istype(G, /datum/plant_gene/core/lifespan) || istype(G, /datum/plant_gene/core/endurance))
		limit = G.value > max_endurance ? max_endurance : null
	else if(istype(G, /datum/plant_gene/core/yield))
		limit = G.value > max_yield ? max_yield : null
	else if(istype(G, /datum/plant_gene/core/production))
		limit = G.value < min_production ? min_production : null
	else if(istype(G, /datum/plant_gene/core/weed_rate))
		limit = G.value < min_wrate ? min_wrate : null
	else if(istype(G, /datum/plant_gene/core/weed_chance))
		limit = G.value < min_wchance ? min_wchance : null
	return isnull(limit) ? null : "[limit]"

/obj/machinery/plantgenes/proc/gene_ui_entry(datum/plant_gene/G, can_extract, can_insert)
	return list(
		"ref" = REF(G),
		"name" = G.get_name(),
		"can_extract" = can_extract,
		"can_replace" = can_insert && istype(G, /datum/plant_gene/core) && istype(disk.gene, G.type),
		"can_remove" = !istype(G, /datum/plant_gene/core),
		"limit" = gene_extract_limit(G),
	)

/obj/machinery/plantgenes/ui_data(mob/user)
	// An operation waiting on something that's gone since: dropped, as the old window did
	if(operation && (!seed || (!target && operation != "insert") || ((operation == "replace" || operation == "insert") && !disk?.gene)))
		operation = ""
		target = null
	var/list/data = list()
	var/obj/item/held = user.get_active_held_item()
	data["holding_seed"] = istype(held, /obj/item/seeds)
	data["holding_disk"] = istype(held, /obj/item/disk/plantgene)
	data["seed"] = seed ? list("name" = seed.name, "icon" = tgui_item_picture(seed.icon, seed.icon_state, user)) : null
	data["disk"] = disk ? list("gene" = disk.gene?.get_name(), "read_only" = !!disk.read_only) : null
	data["operation"] = operation
	if(operation)
		var/list/warnings = list()
		var/question
		switch(operation)
			if("remove")
				question = "Remove the [target.get_name()] gene from the [seed.name]?"
			if("extract")
				question = "Extract the [target.get_name()] gene from the [seed.name] onto the disk?"
				warnings += "The sample will be destroyed in the process."
				var/limit = gene_extract_limit(target)
				if(limit)
					warnings += "This machine's parts extract it at [limit]: it will be degraded to that."
			if("replace")
				question = "Replace the [target.get_name()] gene with the disk's [disk.gene.get_name()]?"
			if("insert")
				question = "Insert the disk's [disk.gene.get_name()] gene into the [seed.name]?"
		data["question"] = question
		data["warnings"] = warnings
		data["target_ref"] = target ? REF(target) : null
	if(seed)
		var/can_extract = disk && !disk.read_only
		var/can_insert = disk?.gene && disk.gene.can_add(seed)
		var/list/core = list()
		for(var/datum/plant_gene/G as anything in core_genes)
			if(G)
				core += list(gene_ui_entry(G, can_extract, can_insert))
		var/list/contents = list()
		for(var/datum/plant_gene/G as anything in reagent_genes)
			contents += list(gene_ui_entry(G, can_extract, can_insert))
		var/list/traits = list()
		for(var/datum/plant_gene/G as anything in trait_genes)
			traits += list(gene_ui_entry(G, can_extract, can_insert))
		data["core"] = core
		data["has_contents"] = seed.yield != -1
		data["contents"] = contents
		data["traits"] = traits
		data["insert_reagent"] = can_insert && istype(disk.gene, /datum/plant_gene/reagent) ? disk.gene.get_name() : null
		data["insert_trait"] = can_insert && istype(disk.gene, /datum/plant_gene/trait) ? disk.gene.get_name() : null
	return data

/obj/machinery/plantgenes/ui_act(action, params)
	if(..())
		return
	switch(action)
		if("eject_seed") // or put in the one in hand
			Topic(null, list("eject_seed" = "1"))
		if("eject_disk") // or swap in the one in hand
			Topic(null, list("eject_disk" = "1"))
		if("gene") // choose a gene and what to do with it, then the same again to confirm
			var/op = params["op"]
			if(!seed || !(op in list("remove", "extract", "replace")) || !istext(params["ref"]) || !seed.get_gene(params["ref"]))
				return
			Topic(null, list("gene" = params["ref"], "op" = op))
		if("insert")
			Topic(null, list("op" = "insert"))
		if("abort")
			Topic(null, list("abort" = "1"))
	return TRUE
