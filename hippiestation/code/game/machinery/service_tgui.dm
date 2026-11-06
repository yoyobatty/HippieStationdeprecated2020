// Service and misc machines moved off their old HTML windows (tgui-next ServiceMachines.js): the jukebox, the slot
// machine, the holopad, the seed extractor, the limb grower, the nav beacon, the vault's bank machine, the airlock and
// vent controllers, and the laser tag turret. Buttons run each machine's own Topic(); where the old window asked
// with an input() pop-up (the jukebox's track, the holopad's area, the nav beacon's codes) the window sends the answer.

// Jukebox

/obj/machinery/jukebox/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
									datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	if(!user.canUseTopic(src, !issilicon(user)))
		return TRUE
	if(!anchored)
		to_chat(user,"<span class='warning'>This device must be anchored by a wrench!</span>")
		return TRUE
	if(!allowed(user))
		to_chat(user,"<span class='warning'>Error: Access Denied.</span>")
		user.playsound_local(src,'sound/misc/compiler-failure.ogg', 25, 1)
		return TRUE
	if(!songs.len)
		to_chat(user,"<span class='warning'>Error: No music tracks have been authorized for your station. Petition Central Command to resolve this issue.</span>")
		playsound(src,'sound/misc/compiler-failure.ogg', 25, 1)
		return TRUE
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "jukebox", name, 420, 520, master_ui, state)
		ui.open()
	return TRUE

/obj/machinery/jukebox/ui_data(mob/user)
	var/list/data = list()
	data["active"] = active
	data["selected"] = selection ? selection.song_name : null
	data["length"] = selection ? selection.song_length : 0
	data["time_left"] = active ? max(stop - world.time, 0) : 0
	data["cooldown"] = (!active && stop > world.time) ? stop - world.time : 0
	var/list/tracks = list()
	for(var/datum/track/T in songs)
		tracks += list(list("name" = T.song_name, "length" = T.song_length))
	data["tracks"] = tracks
	return data

/obj/machinery/jukebox/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("toggle")
			Topic(null, list("action" = "toggle"))
			return TRUE
		if("select")
			if(active)
				to_chat(usr, "<span class='warning'>Error: You cannot change the song until the current one is over.</span>")
				return
			for(var/datum/track/T in songs)
				if(T.song_name == params["name"])
					selection = T
					return TRUE

// Slot machine

/obj/machinery/computer/slot_machine/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
												datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "slot_machine", "Slot Machine", 440, 600, master_ui, state)
		ui.open()
	return TRUE

/obj/machinery/computer/slot_machine/ui_data(mob/user)
	var/list/data = list()
	data["working"] = working
	data["money"] = money
	data["balance"] = balance
	data["plays"] = plays
	data["jackpots"] = jackpots
	data["price"] = 5 // slotmachine.dm's SPIN_PRICE
	var/list/rows = list()
	for(var/i in 1 to 3)
		var/list/row = list()
		for(var/r in 1 to 5)
			row += reels[r][i]
		rows += list(row)
	data["reels"] = rows
	var/list/spinning = list()
	for(var/reel in reels)
		spinning += reels[reel] ? TRUE : FALSE
	data["spinning"] = spinning
	return data

/obj/machinery/computer/slot_machine/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("spin")
			Topic(null, list("spin" = "1"))
			return TRUE
		if("refund")
			Topic(null, list("refund" = "1"))
			return TRUE

// Holopad

/obj/machinery/holopad/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
									datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	if(!ishuman(user))
		return TRUE
	var/mob/living/carbon/human/H = user
	if(outgoing_call || H.incapacitated() || !is_operational())
		return TRUE
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "holopad", name, 420, 380, master_ui, state)
		ui.open()
	return TRUE

/// The other holopads by area, as the old Holocall prompt offered them
/obj/machinery/holopad/proc/holocall_areas()
	var/list/callnames = list()
	for(var/I in holopads)
		var/area/A = get_area(I)
		if(A)
			LAZYADD(callnames[A], I)
	callnames -= get_area(src)
	return callnames

/obj/machinery/holopad/ui_data(mob/user)
	var/list/data = list()
	data["on_network"] = on_network
	data["elevated"] = allowed(user)
	data["on_pad"] = user.loc == loc
	var/static/regex/tags = regex("<\[^>]*>", "g")
	var/notice = replacetext(replacetext(temp, "Main Menu", ""), tags, " ")
	data["notice"] = trim(notice)
	data["outgoing"] = !!outgoing_call
	data["disk"] = !!disk
	data["disk_record"] = disk ? !!disk.record : FALSE
	data["replay_mode"] = replay_mode
	data["loop_mode"] = loop_mode
	data["record_mode"] = record_mode
	var/list/calls = list()
	for(var/I in holo_calls)
		var/datum/holocall/HC = I
		calls += list(list(
			"ref" = REF(HC),
			"from" = "[get_area(HC.calling_holopad)]",
			"caller" = "[HC.user]",
			"answered" = HC.connected_holopad == src,
		))
	data["calls"] = calls
	var/list/areas = list()
	if(on_network)
		for(var/area/A in holocall_areas())
			areas += "[A]"
	data["areas"] = sortList(areas)
	return data

/obj/machinery/holopad/ui_act(action, list/params)
	if(..())
		return
	var/static/list/plain = list("request_ai" = "AIrequest", "answer" = "connectcall", "disconnect" = "disconnectcall", \
		"main_menu" = "mainmenu", "disk_eject" = "disk_eject", "replay_start" = "replay_start", "replay_stop" = "replay_stop", \
		"loop_start" = "loop_start", "record_start" = "record_start", "record_stop" = "record_stop", "record_clear" = "record_clear")
	if(plain[action])
		Topic(null, list("[plain[action]]" = params["ref"] || "1"))
		return TRUE
	if(action == "call")
		// The old Holocall/Holoconnect links, with the area from the window instead of a prompt; Holoconnect (forced)
		// was what it offered to those with access
		if(outgoing_call || !is_operational() || isAI(usr))
			return
		if(usr.loc != loc)
			temp = "You must stand on the holopad to make a call!"
			return TRUE
		var/list/callnames = holocall_areas()
		for(var/area/A in callnames)
			if("[A]" == params["area"])
				temp = "Dialing..."
				new /datum/holocall(usr, src, callnames[A], allowed(usr))
				return TRUE

// Seed extractor

/obj/machinery/seed_extractor/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
										datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	if(stat)
		return TRUE
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "seed_extractor", name, 720, 480, master_ui, state)
		ui.open()
	return TRUE

/obj/machinery/seed_extractor/ui_data(mob/user)
	var/list/data = list()
	var/list/seeds = list()
	for(var/datum/seed_pile/O in piles)
		seeds += list(list(
			"ref" = REF(O),
			"name" = O.name,
			"lifespan" = O.lifespan,
			"endurance" = O.endurance,
			"maturation" = O.maturation,
			"production" = O.production,
			"yield" = O.yield,
			"potency" = O.potency,
			"amount" = O.amount,
		))
	data["seeds"] = seeds
	return data

/obj/machinery/seed_extractor/ui_act(action, list/params)
	if(..())
		return
	if(action == "vend")
		var/datum/seed_pile/N = locate(params["ref"]) in piles
		if(N)
			Topic(null, list("name" = N.name, "li" = "[N.lifespan]", "en" = "[N.endurance]", "ma" = "[N.maturation]", \
				"pr" = "[N.production]", "yi" = "[N.yield]", "pot" = "[N.potency]"))
		return TRUE

// Limb grower

/obj/machinery/limbgrower/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
									datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	if(!is_operational())
		return TRUE
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "limb_grower", name, 520, 560, master_ui, state)
		ui.open()
	return TRUE

/obj/machinery/limbgrower/ui_data(mob/user)
	var/list/data = list()
	data["busy"] = busy
	data["building"] = (busy && being_built) ? being_built.name : null
	data["synthflesh"] = reagents.get_reagent_amount(/datum/reagent/medicine/synthflesh)
	data["volume"] = reagents.total_volume
	data["max_volume"] = reagents.maximum_volume
	var/list/chems = list()
	for(var/datum/reagent/R in reagents.reagent_list)
		chems += list(list("name" = R.name, "volume" = R.volume, "path" = "[R.type]"))
	data["reagents"] = chems
	var/list/cats = list()
	for(var/C in categories)
		cats[C] = list()
	for(var/v in stored_research.researched_designs)
		var/datum/design/D = SSresearch.techweb_design_by_id(v)
		var/cost = D.reagents_list[/datum/reagent/medicine/synthflesh] * prod_coeff
		for(var/C in D.category)
			if(!(C in cats))
				continue
			cats[C] += list(list("id" = D.id, "name" = D.name, "cost" = cost, "can_build" = !disabled && can_build(D)))
	var/list/out = list()
	for(var/C in cats)
		out += list(list("name" = C, "designs" = cats[C]))
	data["categories"] = out
	return data

/obj/machinery/limbgrower/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("make")
			Topic(null, list("make" = params["id"]))
			return TRUE
		if("purge")
			// The old window sent the reagent's name, which text2path() never found
			Topic(null, list("disposeI" = params["path"]))
			return TRUE

// Nav beacon

/obj/machinery/navbeacon/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
									datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	var/turf/T = loc
	if(T.intact)
		return TRUE // prevent interaction when T-scanner revealed
	if(!open && !isAI(user))
		to_chat(user, "<span class='warning'>The beacon's control cover is closed!</span>")
		return TRUE
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "nav_beacon", "Navigation Beacon", 400, 420, master_ui, state)
		ui.open()
	return TRUE

/obj/machinery/navbeacon/ui_data(mob/user)
	var/list/data = list()
	data["locked"] = locked && !isAI(user)
	data["editable"] = open && !locked
	data["location"] = location
	var/list/code_list = list()
	for(var/key in codes)
		code_list += list(list("key" = key, "value" = codes[key]))
	data["codes"] = code_list
	return data

/obj/machinery/navbeacon/ui_act(action, list/params)
	if(..())
		return
	if(!open || locked) // as the old Topic
		return
	switch(action)
		if("location")
			var/newloc = trim(html_encode(params["value"]), MAX_MESSAGE_LEN)
			if(newloc)
				location = newloc
			return TRUE
		if("add", "edit")
			var/newkey = trim(html_encode(params["key"]), MAX_NAME_LEN)
			var/newval = trim(html_encode(params["value"]), MAX_NAME_LEN)
			if(!newkey || !newval)
				return
			if(!codes)
				codes = list()
			if(action == "edit")
				codes.Remove(params["old"])
			codes[newkey] = newval
			return TRUE
		if("delete")
			codes.Remove(params["key"])
			return TRUE

// Bank machine (the vault)

/obj/machinery/computer/bank_machine/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
												datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "bank_vault", "Bank Vault", 380, 230, master_ui, state)
		ui.open()
	return TRUE

/obj/machinery/computer/bank_machine/ui_data(mob/user)
	var/list/data = list()
	var/datum/bank_account/D = SSeconomy.get_dep_account(ACCOUNT_CAR)
	data["station"] = station_name()
	data["balance"] = D ? D.account_balance : null
	data["siphoning"] = siphoning
	data["siphoned"] = syphoning_credits
	return data

/obj/machinery/computer/bank_machine/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("siphon")
			Topic(null, list("siphon" = "1"))
			return TRUE
		if("halt")
			Topic(null, list("halt" = "1"))
			return TRUE

// Airlock and vent controllers: the embedded ones (incinerators, vents) and the access airlock controllers share a
// window of status lines and the commands their old window offered

/obj/machinery/embedded_controller/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
												datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "airlock_controller", name, 380, 300, master_ui, state)
		ui.open()
	return TRUE

/// Status lines for the window: list(list(label, value, colour)), the colour a tgui one or null
/obj/machinery/embedded_controller/proc/tgui_status()
	return list()

/// The commands the old window offered: list(list(label, command, colour))
/obj/machinery/embedded_controller/proc/tgui_commands()
	return list()

/obj/machinery/embedded_controller/ui_data(mob/user)
	return list("status" = tgui_status(), "commands" = tgui_commands())

/obj/machinery/embedded_controller/ui_act(action, list/params)
	if(..())
		return
	if(action == "command")
		for(var/list/C in tgui_commands())
			if(C[2] == params["command"])
				Topic(null, list("command" = C[2]))
				return TRUE

/obj/machinery/embedded_controller/radio/airlock_controller/tgui_status()
	var/state = program ? program.state : 0
	var/list/status = list()
	var/current = "Inactive"
	var/color
	switch(state)
		if(AIRLOCK_STATE_INOPEN)
			current = "Interior Airlock Open, Chamber Pressurized"
			color = "good"
		if(AIRLOCK_STATE_PRESSURIZE)
			current = "Cycling to Interior Airlock, Chamber Pressurizing"
			color = "average"
		if(AIRLOCK_STATE_DEPRESSURIZE)
			current = "Cycling to Exterior Airlock, Chamber Depressurizing"
			color = "average"
		if(AIRLOCK_STATE_OUTOPEN)
			current = "Exterior Airlock Open, Chamber Depressurized"
			color = "bad"
	status += list(list("Current Status", current, color))
	var/list/memory = program ? program.memory : list()
	status += list(list("Chamber Pressure", "[memory["sensor_pressure"] || "----"] kPa", null))
	status += list(list("Control Pump", "[memory["pump_status"] || "----"]", null))
	status += list(list("Interior Door", "[memory["interior_status"] || "----"]", null))
	status += list(list("Exterior Door", "[memory["exterior_status"] || "----"]", null))
	return status

/obj/machinery/embedded_controller/radio/airlock_controller/tgui_commands()
	var/state = program ? program.state : 0
	switch(state)
		if(AIRLOCK_STATE_INOPEN)
			return list(list("Close Interior Airlock", "cycle_closed", null), list("Cycle to Exterior Airlock", "cycle_exterior", null))
		if(AIRLOCK_STATE_PRESSURIZE, AIRLOCK_STATE_DEPRESSURIZE)
			return list(list("Abort Cycling", "abort", "bad"))
		if(AIRLOCK_STATE_CLOSED)
			return list(list("Open Interior Airlock", "cycle_interior", null), list("Open Exterior Airlock", "cycle_exterior", null))
		if(AIRLOCK_STATE_OUTOPEN)
			return list(list("Cycle to Interior Airlock", "cycle_interior", null), list("Close Exterior Airlock", "cycle_closed", null))
	return list()

/obj/machinery/embedded_controller/radio/simple_vent_controller/tgui_commands()
	return list(list("Deactivate Vent", "vent_inactive", null), list("Activate Vent / Pump", "vent_pump", null), \
		list("Activate Vent / Clear", "vent_clear", null))

/obj/machinery/doorButtons/airlock_controller/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
														datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "airlock_controller", name, 380, 220, master_ui, state)
		ui.open()
	return TRUE

/// The same choices as returnText() (access_controller.dm)
/obj/machinery/doorButtons/airlock_controller/proc/tgui_commands()
	if((!exteriorAirlock && !interiorAirlock) || lostPower)
		return list()
	if(!exteriorAirlock || !interiorAirlock)
		if(!exteriorAirlock)
			return interiorAirlock.density ? list(list("Open Interior Airlock", "open_interior", null)) : list(list("Close Interior Airlock", "close_interior", null))
		return exteriorAirlock.density ? list(list("Open Exterior Airlock", "open_exterior", null)) : list(list("Close Exterior Airlock", "close_exterior", null))
	if(exteriorAirlock.density)
		if(interiorAirlock.density)
			return list(list("Open Exterior Airlock", "open_exterior", null), list("Open Interior Airlock", "open_interior", null))
		return list(list("Cycle to Exterior Airlock", "cycle_exterior", null), list("Close Interior Airlock", "close_interior", null))
	if(interiorAirlock.density)
		return list(list("Close Exterior Airlock", "close_exterior", null), list("Cycle to Interior Airlock", "cycle_interior", null))
	return list(list("Close Exterior Airlock", "close_exterior", null), list("Close Interior Airlock", "close_interior", null))

/obj/machinery/doorButtons/airlock_controller/ui_data(mob/user)
	var/list/status = list()
	if(!exteriorAirlock && !interiorAirlock)
		status += list(list("Status", "ERROR", "bad"))
	else if(lostPower)
		status += list(list("Status", "Initializing...", "average"))
	else
		if(interiorAirlock)
			status += list(list("Interior Door", interiorAirlock.density ? "Closed" : "Open", null))
		if(exteriorAirlock)
			status += list(list("Exterior Door", exteriorAirlock.density ? "Closed" : "Open", null))
	return list("status" = status, "commands" = tgui_commands(), "busy" = busy)

/obj/machinery/doorButtons/airlock_controller/ui_act(action, list/params)
	if(..())
		return
	if(action == "command")
		for(var/list/C in tgui_commands())
			if(C[2] == params["command"])
				Topic(null, list("command" = C[2]))
				return TRUE

// Laser tag turret: the turret window (turret_tgui.dm) with only the power switch, kept from the other team

/obj/machinery/porta_turret/lasertag/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
												datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	if(ishuman(user))
		var/mob/living/carbon/human/H = user
		if(team_color == "blue" && istype(H.wear_suit, /obj/item/clothing/suit/redtag))
			return TRUE
		if(team_color == "red" && istype(H.wear_suit, /obj/item/clothing/suit/bluetag))
			return TRUE
	// Not ..(): that's portable_turret.dm's lasertag ui_interact on this same type, which builds the old window
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "porta_turret", name, 380, 200, master_ui, state)
		ui.open()
	return TRUE

/obj/machinery/porta_turret/lasertag/ui_data(mob/user)
	. = ..()
	.["settings"] = list()
