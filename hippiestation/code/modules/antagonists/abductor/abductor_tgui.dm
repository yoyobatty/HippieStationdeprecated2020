// The abductors' machines in tgui (interfaces/Abductor.js): the agent console, the gland storage and the probing console. Their
// moves still go through each machine's Topic(), as before; the old pages are gone from their attack_hand()/experimentUI().

// The agent console

/// What the console makes, in the old page's order: id (its Topic's dispense=), name, cost
GLOBAL_LIST_INIT(abductor_supplies, list(
	list("baton", "Advanced Baton", 2),
	list("mind_device", "Mental Interface Device", 2),
	list("helmet", "Agent Helmet", 1),
	list("vest", "Agent Vest", 1),
	list("silencer", "Radio Silencer", 1),
	list("tool", "Science Tool", 1),
	list("tongue", "Superlingual Matrix", 1),
))

/obj/machinery/abductor/console/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "abductor_console", "Abductsoft 3000", 440, 560, master_ui, state)
		ui.open()

/obj/machinery/abductor/console/ui_data(mob/user)
	var/list/data = list()
	data["team"] = team_number
	data["has_experiment"] = !!experiment
	data["points"] = experiment?.points || 0
	data["credits"] = experiment?.credits || 0
	var/list/supplies = list()
	for(var/list/supply in GLOB.abductor_supplies)
		supplies += list(list("id" = supply[1], "name" = supply[2], "cost" = supply[3]))
	data["supplies"] = supplies
	data["has_pad"] = !!pad
	data["has_mark"] = !!(gizmo?.marked)
	data["mark_name"] = gizmo?.marked ? "[gizmo.marked]" : null
	data["has_vest"] = !!vest
	data["vest_stealth"] = vest ? (vest.mode == VEST_STEALTH) : FALSE
	data["vest_locked"] = vest ? HAS_TRAIT_FROM(vest, TRAIT_NODROP, ABDUCTOR_VEST_TRAIT) : FALSE
	data["disguises"] = length(disguises)
	return data

/obj/machinery/abductor/console/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("dispense")
			Topic(null, list("dispense" = "[params["id"]]"))
		if("teleporter_send")
			Topic(null, list("teleporter_send" = "1"))
		if("teleporter_retrieve")
			Topic(null, list("teleporter_retrieve" = "1"))
		if("flip_vest")
			Topic(null, list("flip_vest" = "1"))
		if("toggle_vest")
			Topic(null, list("toggle_vest" = "1"))
		if("select_disguise")
			INVOKE_ASYNC(src, PROC_REF(SelectDisguise)) // a radial menu: it waits for the pick
		else
			return
	return TRUE

// The gland storage

/obj/machinery/abductor/gland_dispenser/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "gland_dispenser", name, 340, 300, master_ui, state)
		ui.open()

/obj/machinery/abductor/gland_dispenser/ui_data(mob/user)
	var/list/glands = list()
	for(var/i in 1 to length(gland_colors))
		glands += list(list("index" = i, "color" = gland_colors[i], "amount" = amounts[i]))
	return list("glands" = glands)

/obj/machinery/abductor/gland_dispenser/ui_act(action, list/params)
	if(..())
		return
	if(action == "dispense")
		var/index = text2num(params["index"])
		if(index >= 1 && index <= length(gland_colors))
			Topic(null, list("dispense" = "[index]"))
		return TRUE

// The probing console

/obj/machinery/abductor/experiment
	/// The occupant's dissection picture as a data URI, and whose it is, so it isn't drawn again every refresh
	var/dissection_uri
	var/dissection_of

/obj/machinery/abductor/experiment/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "abductor_experiment", "Probing Console", 420, 400, master_ui, state)
		ui.open()

/obj/machinery/abductor/experiment/ui_data(mob/user)
	var/list/data = list()
	data["open"] = state_open
	data["points"] = points
	data["credits"] = credits
	var/mob/living/carbon/human/H = occupant
	if(istype(H))
		data["occupant"] = H.name
		switch(H.stat)
			if(CONSCIOUS)
				data["occupant_state"] = "Conscious"
			if(UNCONSCIOUS)
				data["occupant_state"] = "Unconscious"
			else
				data["occupant_state"] = "Deceased"
		if(dissection_of != REF(H))
			dissection_uri = specimen_picture(H)
			if(dissection_uri)
				dissection_of = REF(H)
		data["picture"] = dissection_uri
	var/static/regex/tags = regex("<\[^>]*>", "g")
	data["result"] = html_decode(tags.Replace(flash, ""))
	data["result_kind"] = findtext(flash, "'bad'") ? "bad" : (findtext(flash, "'good'") ? "good" : "")
	return data

/obj/machinery/abductor/experiment/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("experiment")
			var/kind = text2num(params["kind"])
			if(kind in list(1, 2, 3))
				INVOKE_ASYNC(src, PROC_REF(experiment_move), list("experiment" = "[kind]"), usr) // it waits while it works
		if("open")
			Topic(null, list("open" = "1"))
		if("close")
			Topic(null, list("close" = "1"))
		else
			return
	return TRUE

/obj/machinery/abductor/experiment/proc/experiment_move(list/href, mob/user)
	usr = user
	Topic(null, href)
	SStgui.update_uis(src)

/// The specimen as they look, with the old picture's splat on the chest. dissection_icon() asks human.dmi for body states this
/// fork's bodies don't use any more, so it came out as the whole sheet (the old window showed just the eyes).
/obj/machinery/abductor/experiment/proc/specimen_picture(mob/living/carbon/human/H)
	var/icon/flat = autodoc_flat_patient(H) // the Auto-Doc's: a copy of their look, facing south, that getFlatIcon() can flatten
	if(!flat)
		return null
	var/icon/photo = icon(flat)
	photo.Blend(icon('icons/mob/dam_mob.dmi', "human_chest_30", SOUTH, 1), ICON_OVERLAY) // the old "chest30" isn't a state here, and asking for a missing one gave more than one picture
	return "data:image/png;base64,[icon2base64(photo)]"
