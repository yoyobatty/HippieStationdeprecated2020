// The mech sleeper's patient statistics and the mech syringe gun's reagent synthesizer moved off their old HTML pages
// (tgui-next MechMedical.js). The exosuit window's "View stats" and "Show reagents" buttons (mecha_tgui.dm) open these;
// the rest still goes through each tool's own Topic(). Only the pilot sees them.

/obj/item/mecha_parts/mecha_equipment/medical/ui_status(mob/user, datum/ui_state/state)
	if(!chassis || chassis.occupant != user || QDELETED(src))
		return UI_CLOSE
	return UI_INTERACTIVE

// Sleeper

/obj/item/mecha_parts/mecha_equipment/medical/sleeper/Topic(href, href_list)
	if(!pilot_topic(usr)) // the pilot's (mecha_tgui.dm): anyone could eject the patient or inject them
		return TRUE
	if(href_list["view_stats"])
		if(chassis?.occupant)
			ui_interact(chassis.occupant)
		return
	return ..()

/obj/item/mecha_parts/mecha_equipment/medical/sleeper/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
															datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "mech_sleeper", "[patient ? patient : "Sleeper"] statistics", 460, 520, master_ui, state)
		ui.open()

/obj/item/mecha_parts/mecha_equipment/medical/sleeper/ui_data(mob/user)
	var/list/data = list()
	if(!patient)
		data["patient"] = null
		return data
	data["patient"] = list(
		"name" = patient.name,
		"stat" = patient.stat,
		"health" = patient.health,
		"temperature" = round(patient.bodytemperature - T0C, 0.1),
		"brute" = patient.getBruteLoss(),
		"oxy" = patient.getOxyLoss(),
		"tox" = patient.getToxLoss(),
		"burn" = patient.getFireLoss(),
		"clone" = !!patient.getCloneLoss(),
		"brain" = !!patient.getBrainLoss(),
		"traumas" = !!length(patient.get_traumas()),
	)
	var/list/blood = list()
	if(patient.reagents)
		for(var/datum/reagent/R in patient.reagents.reagent_list)
			if(R.volume > 0)
				blood += list(list("name" = R.name, "volume" = round(R.volume, 0.01)))
	data["blood"] = blood
	var/list/injectable = list()
	var/obj/item/mecha_parts/mecha_equipment/medical/syringe_gun/SG = locate() in chassis
	if(SG?.reagents)
		for(var/datum/reagent/R in SG.reagents.reagent_list)
			if(R.volume > 0)
				injectable += list(list("ref" = REF(R), "name" = R.name, "volume" = round(R.volume, 0.01)))
	data["injectable"] = injectable
	data["inject_amount"] = inject_amount
	return data

/obj/item/mecha_parts/mecha_equipment/medical/sleeper/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("inject")
			Topic(null, list("inject" = params["ref"]))
			return TRUE
		if("eject")
			Topic(null, list("eject" = "1"))
			return TRUE

// Syringe gun

/obj/item/mecha_parts/mecha_equipment/medical/syringe_gun/Topic(href, href_list)
	if(!pilot_topic(usr)) // the pilot's (mecha_tgui.dm): anyone could purge it or change what it makes
		return TRUE
	if(href_list["show_reagents"])
		if(chassis?.occupant)
			ui_interact(chassis.occupant)
		return
	return ..()

/obj/item/mecha_parts/mecha_equipment/medical/syringe_gun/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
																datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "mech_syringe_gun", "Reagent Synthesizer", 460, 520, master_ui, state)
		ui.open()

/obj/item/mecha_parts/mecha_equipment/medical/syringe_gun/ui_data(mob/user)
	var/list/data = list()
	var/list/current = list()
	for(var/datum/reagent/R in reagents.reagent_list)
		if(R.volume > 0)
			current += list(list("name" = R.name, "volume" = round(R.volume, 0.001), "path" = "[R.type]"))
	data["reagents"] = current
	data["total"] = round(reagents.total_volume, 0.001)
	data["max"] = reagents.maximum_volume
	var/list/known = list()
	for(var/reagent_id in known_reagents)
		known += list(list("path" = "[reagent_id]", "name" = known_reagents[reagent_id], "on" = (reagent_id in processed_reagents)))
	data["known"] = known
	data["synth_speed"] = synth_speed
	data["syringes"] = length(syringes)
	data["max_syringes"] = max_syringes
	return data

/obj/item/mecha_parts/mecha_equipment/medical/syringe_gun/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("purge")
			// The old page sent the reagent's name, which del_reagent() never matched
			var/reagent = text2path(params["path"])
			if(reagent)
				reagents.del_reagent(reagent)
			return TRUE
		if("purge_all")
			Topic(null, list("purge_all" = "1"))
			return TRUE
		if("produce")
			// The old page's checkbox form: the first synth_speed reagents picked are made
			var/reagent = text2path(params["path"])
			if(!reagent || !(reagent in known_reagents))
				return
			if(reagent in processed_reagents)
				processed_reagents -= reagent
				return TRUE
			if(processed_reagents.len >= synth_speed)
				occupant_message("Only [synth_speed] reagents can be produced at once.")
				return
			processed_reagents += reagent
			START_PROCESSING(SSobj, src)
			occupant_message("[known_reagents[reagent]] added to production.")
			log_message("Reagent processing started.", LOG_MECHA)
			return TRUE
