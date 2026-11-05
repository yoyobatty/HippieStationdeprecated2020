// hippie -- the DNA scanner access console is a tgui window on the same screens as before: the genetic sequencer, the unique
// identifiers and buffers, mutation and chromosome storage, and the disk. Its buttons go through the console's own Topic(),
// which bots run genetics through too (goals/genetics.dm). The few that asked in a popup (a base's new letter, a buffer's
// label, which chromosome) are answered in the window, and do what Topic() did with the answer.
//
// As the old page did, it names genes by alias and position, never by their mutation, so the page can't be read for what an
// undiscovered gene is.

// As dna_console.dm has them (it undefines them at its end)
#define DNA_TGUI_BUFFERS 3
#define DNA_TGUI_STRENGTH_MAX 15
#define DNA_TGUI_DURATION_MAX 30
#define DNA_TGUI_ACCURACY_MULTIPLIER 3
#define DNA_TGUI_SCANNER_ACTION_UI 2
#define DNA_TGUI_SCANNER_ACTION_UE 3
#define DNA_TGUI_SCANNER_ACTION_MIXED 4

/obj/machinery/computer/scan_consolenew
	/// What the last pulse did. The console's Topic() hands it over as ui_interact()'s second argument
	var/last_operation

/obj/machinery/computer/scan_consolenew/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	if(ui_key != "main")
		last_operation = ui_key
		ui_key = "main"
	if(!user?.client) // a bot at the console
		return
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		var/datum/asset/simple/assets = get_asset_datum(/datum/asset/simple/genetics)
		assets.send(user.client)
		ui = new(user, src, ui_key, "dna_console", name, 760, 680, master_ui, state)
		ui.open()

/obj/machinery/computer/scan_consolenew/ui_data(mob/user)
	var/list/data = list()
	var/screen = current_screen || "mainmenu"
	data["screen"] = screen
	var/mob/living/carbon/viable_occupant = get_viable_occupant()

	// The scanner and who's in it
	var/list/scanner = list("present" = !!(connected && connected.is_operational()))
	if(scanner["present"])
		scanner["open"] = connected.state_open
		scanner["locked"] = connected.locked
		var/mob/living/carbon/occupant = connected.occupant
		if(istype(occupant))
			if(occupant.has_dna() && !HAS_TRAIT(occupant, TRAIT_RADIMMUNE) && !HAS_TRAIT(occupant, TRAIT_BADDNA) || (connected.scan_level == 3))
				// The old page read soft crit as DEAD
				var/status = "Unconscious"
				var/status_color = "average"
				if(occupant.stat == CONSCIOUS)
					status = "Conscious"
					status_color = "good"
				else if(occupant.stat == DEAD)
					status = "DEAD"
					status_color = "bad"
				scanner["subject"] = list(
					"name" = occupant.name,
					"status" = status,
					"status_color" = status_color,
					"health" = occupant.health,
					"radiation" = round(occupant.radiation / (RAD_MOB_SAFE / 100), 0.1),
					"ue" = occupant.dna?.unique_enzymes,
				)
			else
				scanner["invalid"] = TRUE
	data["scanner"] = scanner
	data["last_operation"] = last_operation

	// The emitter
	data["radstrength"] = radstrength
	data["radduration"] = radduration
	data["max_strength"] = DNA_TGUI_STRENGTH_MAX
	data["max_duration"] = DNA_TGUI_DURATION_MAX
	data["mutation_range"] = "(-[radstrength] to +[radstrength] = 68 %) (-[2 * radstrength] to +[2 * radstrength] = 95 %)"
	var/stddev = DNA_TGUI_ACCURACY_MULTIPLIER / (radduration + (connected ? connected.precision_coeff ** 2 : 0))
	switch(stddev)
		if(0 to 0.25)
			data["accuracy"] = ">95 %"
		if(0.25 to 0.5)
			data["accuracy"] = "68-95 %"
		if(0.5 to 0.75)
			data["accuracy"] = "55-68 %"
		else
			data["accuracy"] = "<38 %"

	data["can_scramble"] = !!(viable_occupant && scrambleready < world.time)
	data["injector_ready"] = injectorready < world.time
	data["joker_ready"] = jokerready < world.time
	data["has_disk"] = !!diskette
	data["working_time"] = DisplayTimeText(radduration * 10)

	switch(screen)
		if("mainmenu")
			var/list/sequence = list()
			if(viable_occupant)
				var/list/with_storage = get_mutation_list(TRUE)
				for(var/mutation in get_mutation_list())
					var/location = viable_occupant.dna.mutation_index.Find(mutation)
					if(!location)
						location = with_storage.Find(mutation)
					var/kind = "undiscovered"
					if(location > DNA_MUTATION_BLOCKS)
						kind = "extra"
					else if(mutation in stored_research.discovered_mutations)
						kind = "discovered"
					sequence += list(list("location" = location, "kind" = kind, "selected" = (mutation == current_mutation)))
				if(current_mutation in with_storage)
					data["gene"] = dna_gene_data(current_mutation)
			data["sequence"] = sequence
		if("info")
			if(current_storage && current_storage <= LAZYLEN(stored_mutations))
				var/datum/mutation/human/HM = stored_mutations[current_storage]
				data["gene"] = dna_gene_data(HM.type, current_storage)
		if("ui")
			var/list/identity = list()
			if(viable_occupant)
				var/ui_text = viable_occupant.dna.uni_identity
				var/list/block = list()
				for(var/i in 1 to length_char(ui_text))
					block += list(list("char" = copytext_char(ui_text, i, i + 1), "num" = i))
					if(!(i % DNA_BLOCK_SIZE))
						identity += list(block)
						block = list()
				if(length(block))
					identity += list(block)
			data["identity"] = identity
			var/list/buffers = list()
			for(var/i in 1 to DNA_TGUI_BUFFERS)
				var/list/slot = buffer[i]
				if(!slot || !slot.len || !slot["name"] || !((slot["UI"] && slot["UE"]) || slot["SE"]))
					buffers += list(list("index" = i, "empty" = TRUE))
					continue
				buffers += list(list(
					"index" = i,
					"label" = slot["label"] || slot["name"],
					"name" = slot["name"],
					"blood_type" = slot["blood_type"],
					"ue" = slot["UE"],
					"ui" = slot["UI"],
					"has_ue" = !!(slot["UE"] && slot["name"] && slot["blood_type"]),
				))
			data["buffers"] = buffers
			data["delayed"] = delayed_action ? delayed_action["buffer"] : null
			data["disk_read_only"] = diskette?.read_only
		if("mutations")
			var/list/stored = list()
			for(var/i in 1 to length(stored_mutations))
				var/datum/mutation/human/HM = stored_mutations[i]
				stored += list(list("name" = HM.name, "alias" = HM.alias, "index" = i, "combining" = (combine == HM.type)))
			data["stored"] = stored
			data["max_storage"] = max_storage
			var/list/chromosomes = list()
			for(var/i in 1 to length(stored_chromosomes))
				var/obj/item/chromosome/CM = stored_chromosomes[i]
				chromosomes += list(list("name" = CM.name, "index" = i))
			data["chromosomes"] = chromosomes
		if("disk")
			if(diskette)
				var/list/mutations = list()
				for(var/i in 1 to LAZYLEN(diskette.mutations))
					var/datum/mutation/human/A = diskette.mutations[i]
					mutations += list(list("name" = A.name, "index" = i))
				data["disk"] = list(
					"name" = diskette.name,
					"read_only" = diskette.read_only,
					"mutations" = mutations,
					"can_import" = LAZYLEN(stored_mutations) < max_storage,
				)
	return data

/// A gene as the old window's display_sequence() showed it: by alias, its name and words only once discovered
/obj/machinery/computer/scan_consolenew/proc/dna_gene_data(mutation, storage_slot)
	if(!mutation)
		return null
	var/mob/living/carbon/viable_occupant = get_viable_occupant()
	var/datum/mutation/human/HM = get_valid_mutation(mutation)
	var/active = FALSE
	var/scrambled = FALSE
	if(viable_occupant)
		var/datum/mutation/human/M = viable_occupant.dna.get_mutation(mutation)
		if(M)
			scrambled = M.scrambled
			active = TRUE
	var/datum/mutation/human/A = GET_INITIALIZED_MUTATION(mutation)
	if(active && !scrambled)
		discover(mutation)
	var/discovered = stored_research && (mutation in stored_research.discovered_mutations)
	var/list/gene = list(
		"alias" = A.alias,
		"storage_slot" = storage_slot,
		"discovered" = discovered,
		"name" = discovered ? A.name : null,
		"desc" = discovered ? A.desc : "No information available.",
		"active" = active,
		"scrambled" = scrambled,
	)
	if(discovered && !scrambled)
		var/instability = A.instability
		if(HM)
			instability *= GET_MUTATION_STABILIZER(HM)
		gene["instability"] = round(instability)
		switch(A.quality)
			if(POSITIVE)
				gene["quality"] = "good"
			if(MINOR_NEGATIVE)
				gene["quality"] = "average"
			if(NEGATIVE)
				gene["quality"] = "bad"
	// The chromosome slot, on one that's on in the subject
	if(active && !storage_slot && HM?.can_chromosome && (HM in viable_occupant.dna.mutations))
		gene["chromosome"] = HM.chromosome_name || "----"
		gene["mutation_index"] = viable_occupant.dna.mutations.Find(HM)
		var/list/fits = list()
		if(!HM.chromosome_name)
			for(var/i in 1 to length(stored_chromosomes))
				var/obj/item/chromosome/CM = stored_chromosomes[i]
				if(CM.can_apply(HM))
					fits += list(list("name" = CM.name, "index" = i))
		gene["chromosomes"] = fits
	// The base pairs
	var/whole = scrambled ? null : get_valid_gene_string(mutation)
	if(whole)
		var/list/blocks = list()
		for(var/block in 1 to A.blocks)
			var/sequence = copytext_char(whole, 1 + (block - 1) * (DNA_SEQUENCE_LENGTH * 2), DNA_SEQUENCE_LENGTH * 2 * block + 1)
			if(length_char(sequence) < DNA_SEQUENCE_LENGTH * 2)
				break
			var/list/top = list()
			var/list/bottom = list()
			for(var/i in 1 to DNA_SEQUENCE_LENGTH)
				var/upper = 1 + (i - 1) * 2
				top += list(list("base" = copytext_char(sequence, upper, upper + 1), "num" = upper + DNA_SEQUENCE_LENGTH * 2 * (block - 1)))
				bottom += list(list("base" = copytext_char(sequence, i * 2, i * 2 + 1), "num" = i * 2 + DNA_SEQUENCE_LENGTH * 2 * (block - 1)))
			blocks += list(list("top" = top, "bottom" = bottom))
		gene["blocks"] = blocks
	gene["editable"] = !storage_slot && viable_occupant && (mutation in viable_occupant.dna.mutation_index)
	gene["can_print"] = (active || storage_slot) && injectorready < world.time && !scrambled
	gene["can_store"] = !storage_slot && active && !scrambled
	gene["can_nullify"] = (viable_occupant && !(storage_slot || viable_occupant.dna.mutation_in_sequence(mutation))) || scrambled
	gene["can_export"] = storage_slot && LAZYLEN(stored_mutations) < max_storage && diskette && !diskette.read_only
	return gene

/obj/machinery/computer/scan_consolenew/ui_act(action, params)
	if(..())
		return
	if(current_screen == "working")
		return
	last_operation = null
	var/num = text2num(params["num"])
	switch(action)
		if("task")
			var/task = params["task"]
			if(!dna_task_allowed(task, num, params))
				return
			var/list/href = list("task" = task)
			for(var/key in list("num", "text", "delayaction", "slot"))
				if(!isnull(params[key]))
					href[key] = "[params[key]]"
			// Genes go by alias in the window; Topic() takes the mutation
			if(params["alias"])
				var/path = GET_MUTATION_TYPE_FROM_ALIAS(params["alias"])
				if(!path)
					return
				href["path"] = "[path]"
			Topic(null, href)
		if("label")
			// The old Topic asked in a popup
			var/text = sanitize(copytext_char("[params["label"]]", 1, MAX_NAME_LEN))
			if(!num || !text)
				return
			var/list/slot = buffer[clamp(num, 1, DNA_TGUI_BUFFERS)]
			if(istype(slot))
				slot["label"] = text
			add_fingerprint(usr)
		if("gene")
			dna_window_edit_gene(GET_MUTATION_TYPE_FROM_ALIAS(params["alias"]), num, params["gene"])
		if("apply_chromosome")
			// The old Topic only let the last mutation have one (its check was the wrong way round) and asked which in a popup
			var/mob/living/carbon/viable_occupant = get_viable_occupant()
			var/index = text2num(params["mutation_index"])
			var/chosen = text2num(params["chromosome"])
			if(!viable_occupant || !index || index < 1 || index > LAZYLEN(viable_occupant.dna.mutations) || !chosen || chosen < 1 || chosen > LAZYLEN(stored_chromosomes))
				return
			var/datum/mutation/human/HM = viable_occupant.dna.mutations[index]
			var/obj/item/chromosome/CM = stored_chromosomes[chosen]
			if(HM.chromosome_name || !CM.can_apply(HM))
				return
			to_chat(usr, "<span class='notice'>You apply [CM] to [HM.name].</span>")
			stored_chromosomes -= CM
			CM.apply(HM)
			add_fingerprint(usr)
		if("eject_chromosome")
			// The old Topic only ejected the last one (its check was the wrong way round)
			if(!num || num < 1 || num > LAZYLEN(stored_chromosomes))
				return
			var/obj/item/chromosome/CM = stored_chromosomes[num]
			CM.forceMove(drop_location())
			adjust_item_drop_location(CM)
			stored_chromosomes -= CM
			add_fingerprint(usr)
	return TRUE

/// What the window may ask Topic() for: what the old page offered, with numbers that are there (out-of-range ones were runtimes)
/obj/machinery/computer/scan_consolenew/proc/dna_task_allowed(task, num, list/params)
	switch(task)
		if("togglelock", "toggleopen", "scramble", "ejectdisk", "nullify")
			return TRUE
		if("setduration", "setstrength")
			return !!num // without one, Topic() asks in a popup
		if("screen")
			return params["text"] in list("mainmenu", "ui", "mutations", "disk")
		if("setbuffer", "clearbuffer", "transferbuffer", "injector", "loaddisk", "savedisk")
			return num >= 1 && num <= DNA_TGUI_BUFFERS
		if("setdelayed")
			return num >= 1 && num <= DNA_TGUI_BUFFERS && (text2num(params["delayaction"]) in list(DNA_TGUI_SCANNER_ACTION_UI, DNA_TGUI_SCANNER_ACTION_UE, DNA_TGUI_SCANNER_ACTION_MIXED))
		if("pulseui")
			var/mob/living/carbon/viable_occupant = get_viable_occupant()
			return viable_occupant && num >= 1 && num <= length_char(viable_occupant.dna.uni_identity)
		if("inspect")
			return num >= 1 && num <= length(get_mutation_list(TRUE))
		if("inspectstorage", "deletemut", "combine")
			return num >= 1 && num <= LAZYLEN(stored_mutations)
		if("deletediskmut", "importdiskmut")
			return diskette && num >= 1 && num <= LAZYLEN(diskette.mutations)
		if("savemut", "activator", "mutator", "exportdiskmut")
			return !!params["alias"]
	return FALSE

/// The old Topic's "pulsegene" with the letter picked in the window: the same change, the JOKER if it's ready, the same bit of
/// radiation and the same check that a gene has come on
/obj/machinery/computer/scan_consolenew/proc/dna_window_edit_gene(path, num, new_gene)
	if(current_screen == "info")
		return
	var/mob/living/carbon/viable_occupant = get_viable_occupant()
	if(!path || !viable_occupant || !connected || !num || !(path in viable_occupant.dna.mutation_index))
		return
	var/list/genes = list("A", "T", "G", "C", "X")
	if(jokerready < world.time)
		genes += "JOKER"
	if(!(new_gene in genes))
		return
	var/sequence = GET_GENE_STRING(path, viable_occupant.dna)
	if(num < 1 || num > length_char(sequence))
		return
	if(new_gene == "JOKER")
		var/true_genes = GET_SEQUENCE(path)
		new_gene = copytext_char(true_genes, num, num + 1)
		jokerready = world.time + JOKER_TIMEOUT - (JOKER_UPGRADE * (connected.precision_coeff - 1))
	sequence = copytext_char(sequence, 1, num) + new_gene + copytext_char(sequence, num + 1)
	viable_occupant.dna.mutation_index[path] = sequence
	viable_occupant.radiation += 1 / connected.damage_coeff // RADIATION_STRENGTH_MULTIPLIER
	viable_occupant.domutcheck()
	add_fingerprint(usr)

#undef DNA_TGUI_BUFFERS
#undef DNA_TGUI_STRENGTH_MAX
#undef DNA_TGUI_DURATION_MAX
#undef DNA_TGUI_ACCURACY_MULTIPLIER
#undef DNA_TGUI_SCANNER_ACTION_UI
#undef DNA_TGUI_SCANNER_ACTION_UE
#undef DNA_TGUI_SCANNER_ACTION_MIXED
