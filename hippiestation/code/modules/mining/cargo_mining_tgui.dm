// Cargo and mining windows moved to tgui (tgui-next CargoMining.js): the bounty console, the ore silo, the smelter's
// console, the coin press and the auxiliary base console. Each button calls the machine's own Topic(), so the rules,
// sounds and logs stay as they were.

// Bounty console

/obj/machinery/computer/bounty/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
										datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	if(!GLOB.bounties_list.len)
		setup_bounties()
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "bounty_console", "Nanotrasen Bounties", 760, 600, master_ui, state)
		ui.open()
	return TRUE

/obj/machinery/computer/bounty/ui_data(mob/user)
	var/list/data = list()
	var/datum/bank_account/D = SSeconomy.get_dep_account(ACCOUNT_CAR)
	data["credits"] = D ? D.account_balance : 0
	var/list/bounties = list()
	for(var/datum/bounty/B in GLOB.bounties_list)
		bounties += list(list(
			"ref" = REF(B),
			"name" = B.name,
			"description" = B.description,
			"reward" = B.reward_string(),
			"completion" = B.completion_string(),
			"claimed" = B.claimed,
			"can_claim" = !B.claimed && B.can_claim(),
			"priority" = B.high_priority,
		))
	data["bounties"] = bounties
	return data

/obj/machinery/computer/bounty/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("claim")
			Topic(null, list("choice" = "Claim", "d_rec" = params["ref"], "refresh" = "1"))
			return TRUE
		if("print")
			Topic(null, list("choice" = "Print", "refresh" = "1"))
			return TRUE

// Ore silo

/obj/machinery/ore_silo/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
									datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "ore_silo", "Ore Silo", 620, 600, master_ui, state)
		ui.open()
	return TRUE

/obj/machinery/ore_silo/ui_data(mob/user)
	var/list/data = list()
	var/datum/component/material_container/materials = GetComponent(/datum/component/material_container)
	var/list/mats = list()
	for(var/M in materials.materials)
		var/datum/material/mat = materials.materials[M]
		mats += list(list("id" = mat.id, "name" = mat.name, "sheets" = round(mat.amount / MINERAL_MATERIAL_AMOUNT, 0.01)))
	data["materials"] = mats
	var/list/machines = list()
	for(var/C in connected)
		var/datum/component/remote_materials/remote = C
		var/atom/parent = remote.parent
		var/hold_key = "[get_area(parent)]/[remote.category]"
		machines += list(list(
			"ref" = REF(remote),
			"name" = parent.name,
			"area" = get_area_name(parent, TRUE),
			"hold_key" = hold_key,
			"held" = !!holds[hold_key],
		))
	data["machines"] = machines
	var/list/logs = list()
	var/list/entries = GLOB.silo_access_logs[REF(src)]
	for(var/i in 1 to min(LAZYLEN(entries), 100))
		var/datum/ore_silo_log/entry = entries[i]
		var/list/changes = list()
		for(var/key in entry.materials)
			changes += "[entry.amount < 0 ? "-" : "+"][round(entry.materials[key]) / MINERAL_MATERIAL_AMOUNT] [copytext(key, length(key[1]) + 1)]"
		logs += list(list(
			"time" = entry.timestamp,
			"machine" = entry.machine_name,
			"area" = entry.area_name,
			"action" = "[entry.action] [abs(entry.amount)]x [entry.noun]",
			"changes" = changes.Join(", "),
			"out" = entry.amount < 0,
		))
	data["logs"] = logs
	return data

/obj/machinery/ore_silo/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("eject")
			var/amount = round(text2num(params["amount"]))
			if(amount > 0)
				Topic(null, list("ejectsheet" = params["id"], "eject_amt" = "[amount]"))
			return TRUE
		if("remove")
			Topic(null, list("remove" = params["ref"]))
			return TRUE
		if("hold")
			Topic(null, list("hold1" = params["key"]))
			return TRUE
		if("allow")
			Topic(null, list("hold0" = params["key"]))
			return TRUE

// Smelter console

/obj/machinery/mineral/processing_unit_console/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
														datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	if(!machine)
		return
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "smelter_console", "Smelting Console", 460, 560, master_ui, state)
		ui.open()
	return TRUE

/obj/machinery/mineral/processing_unit_console/ui_data(mob/user)
	var/list/data = list()
	if(!machine)
		return data
	data["on"] = machine.on
	var/datum/component/material_container/materials = machine.GetComponent(/datum/component/material_container)
	var/list/mats = list()
	for(var/mat_id in materials.materials)
		var/datum/material/M = materials.materials[mat_id]
		mats += list(list(
			"id" = mat_id,
			"name" = M.name,
			"amount" = M.amount,
			"sheets" = round(M.amount / MINERAL_MATERIAL_AMOUNT, 0.01),
			"selected" = machine.selected_material == mat_id,
		))
	data["materials"] = mats
	var/list/alloys = list()
	for(var/v in machine.stored_research.researched_designs)
		var/datum/design/D = SSresearch.techweb_design_by_id(v)
		alloys += list(list("id" = D.id, "name" = D.name, "selected" = machine.selected_alloy == D.id))
	data["alloys"] = alloys
	return data

/obj/machinery/mineral/processing_unit_console/ui_act(action, list/params)
	if(..() || !machine)
		return
	switch(action)
		if("material")
			Topic(null, list("material" = params["id"]))
			return TRUE
		if("alloy")
			Topic(null, list("alloy" = params["id"]))
			return TRUE
		if("power")
			Topic(null, list("set_on" = machine.on ? "off" : "on"))
			return TRUE

// Coin press: attack_hand (mint.dm) builds the old window only when the interaction chain's ui_interact returns nothing

/obj/machinery/mineral/mint/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
										datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "coin_press", "Coin Press", 420, 440, master_ui, state)
		ui.open()
	return TRUE

/obj/machinery/mineral/mint/ui_data(mob/user)
	var/list/data = list()
	var/datum/component/material_container/materials = GetComponent(/datum/component/material_container)
	var/list/mats = list()
	for(var/mat_id in materials.materials)
		var/datum/material/M = materials.materials[mat_id]
		mats += list(list(
			"id" = mat_id,
			"name" = M.name,
			"amount" = M.amount,
			"coins" = round(M.amount / (MINERAL_MATERIAL_AMOUNT * 0.2)),
		))
	data["materials"] = mats
	data["chosen"] = chosen
	data["count"] = coinsToProduce
	data["made"] = newCoins
	data["processing"] = processing
	return data

/obj/machinery/mineral/mint/ui_act(action, list/params)
	if(..() || processing)
		return
	switch(action)
		if("choose")
			Topic(null, list("choose" = params["id"]))
			return TRUE
		if("count")
			var/target = text2num(params["count"])
			if(!isnull(target))
				Topic(null, list("chooseAmt" = "[round(target) - coinsToProduce]"))
			return TRUE
		if("make")
			// Topic sleeps between coins, so it runs on its own
			INVOKE_ASYNC(src, PROC_REF(mint_make), usr)
			return TRUE

/obj/machinery/mineral/mint/proc/mint_make(mob/user)
	usr = user
	Topic(null, list("makeCoins" = "1"))

// Auxiliary base console

/obj/machinery/computer/auxillary_base/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, \
												datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "aux_base", "Base Management", 560, 420, master_ui, state)
		ui.open()
	return TRUE

/obj/machinery/computer/auxillary_base/ui_data(mob/user)
	var/list/data = list()
	var/obj/docking_port/mobile/M = SSshuttle.getShuttle(shuttleId)
	data["docked"] = is_station_level(z)
	data["status"] = M ? M.getStatusText() : "OFFLINE"
	data["online"] = !!M
	var/list/destinations = list()
	if(M)
		var/list/options = params2list(possible_destinations)
		for(var/obj/docking_port/stationary/S in SSshuttle.stationary)
			if(!options.Find(S.id))
				continue
			if(!M.check_dock(S, silent = TRUE))
				continue
			destinations += list(list("id" = S.id, "name" = S.name))
	data["destinations"] = destinations
	data["blind_drop"] = M && !length(destinations) && is_station_level(z)
	var/list/turret_list = list()
	for(var/PDT in turrets)
		var/obj/machinery/porta_turret/aux_base/T = PDT
		var/status
		if(T.stat & BROKEN)
			status = "ERROR"
		else if(!T.on)
			status = "Disabled"
		else if(T.raised)
			status = "Firing"
		else
			status = "All Clear"
		turret_list += list(list(
			"ref" = REF(T),
			"name" = T.name,
			"integrity" = round(max((T.obj_integrity - T.integrity_failure) / (T.max_integrity - T.integrity_failure) * 100, 0)),
			"status" = status,
			"direction" = dir2text(get_dir(src, T)),
			"distance" = get_dist(src, T),
		))
	data["turrets"] = turret_list
	return data

/obj/machinery/computer/auxillary_base/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("move")
			Topic(null, list("move" = params["id"]))
			return TRUE
		if("random")
			Topic(null, list("random" = "1"))
			return TRUE
		if("turrets")
			Topic(null, list("turrets_power" = params["state"]))
			return TRUE
		if("turret")
			Topic(null, list("single_turret_power" = params["ref"]))
			return TRUE
