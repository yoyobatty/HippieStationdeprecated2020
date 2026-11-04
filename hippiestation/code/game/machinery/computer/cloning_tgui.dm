// hippie -- the cloning console's window in tgui (tgui-next interfaces/CloningConsole.js): the scanner, the pods and how far along
// each clone is, the records with their clone and delete buttons, and the data disk. Every button goes through the console's own
// Topic(), so the rules, logs and sounds are the old window's: body-only scans, the access check on deleting a record, autoprocess
// wanting a good enough scanner. The Medbay bots work the console's procs directly (bots_ai goals/cloning.dm), as before.

/obj/machinery/computer/cloning/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	add_fingerprint(user)
	updatemodules(TRUE)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "cloning_console", "Cloning System Control", 620, 660, master_ui, state)
		ui.open()

/obj/machinery/computer/cloning/ui_data(mob/user)
	. = list()
	.["temp"] = temp ? comm_plain_text(temp) : null
	.["loading"] = loading
	.["autoprocess"] = autoprocess
	.["can_autoprocess"] = !!(scanner && HasEfficientPod() && scanner.scan_level >= 3) // AUTOCLONING_MINIMAL_LEVEL, cloning.dm
	.["revival"] = !!CONFIG_GET(flag/revival_cloning)
	var/list/scan = null
	if(scanner)
		var/mob/living/scanner_occupant = get_mob_or_brainmob(scanner.occupant)
		if(scanner_occupant && scanner_occupant.ckey != scantemp_ckey) // as the old window did when it drew itself
			scantemp = "Ready to Scan"
			scantemp_ckey = scanner_occupant.ckey
		scan = list(
			"operational" = scanner.is_operational(),
			"occupant" = scanner_occupant ? "[scanner_occupant]" : null,
			"status" = comm_plain_text(scantemp),
			"locked" = !!scanner.locked,
			"level" = scanner.scan_level,
		)
	.["scanner"] = scan
	var/list/pod_list = list()
	for(var/obj/machinery/clonepod/P as anything in pods)
		var/mob/living/O = P.occupant
		pod_list += list(list(
			"name" = "[P]",
			"occupant" = O ? "[O.real_name]" : null,
			"progress" = O ? round(clamp(P.get_completion(), 0, 100)) : null,
			"mess" = !!P.mess,
			"working" = P.is_operational(),
			"efficient" = P.efficiency > 5,
		))
	.["pods"] = pod_list
	var/list/record_list = list()
	for(var/datum/data/record/R in records)
		var/list/mutations = list()
		for(var/key in R.fields["SE"])
			if(key != RACEMUT)
				var/datum/mutation/human/M = GLOB.all_mutations[key]
				mutations += list(list("name" = M ? M.alias : "[key]", "value" = "[R.fields["SE"][key]]"))
		var/obj/item/implant/health/H = locate(R.fields["imp"])
		record_list += list(list(
			"id" = R.fields["id"],
			"name" = R.fields["name"],
			"body_only" = !!R.fields["body_only"],
			"health" = (istype(H) ? comm_plain_text(H.sensehealth()) : null),
			"ui" = R.fields["UI"],
			"mutations" = mutations,
		))
	.["records"] = record_list
	.["active"] = active_record ? active_record.fields["id"] : null
	var/list/disk = null
	if(diskette)
		var/list/contents = list()
		if(diskette.fields)
			if(diskette.fields["UI"])
				contents += "Unique Identifier"
			if(diskette.fields["UE"] && diskette.fields["name"] && diskette.fields["blood_type"])
				contents += "Unique Enzymes"
			if(diskette.fields["SE"])
				contents += "Structural Enzymes"
		disk = list(
			"name" = diskette.name,
			"contents" = contents,
			"read_only" = !!diskette.read_only,
			"has_ui" = !!diskette.fields?["UI"],
			"has_ue" = !!diskette.fields?["UE"],
			"has_se" = !!diskette.fields?["SE"],
		)
	.["disk"] = disk
	.["include_se"] = include_se
	.["include_ui"] = include_ui
	.["include_ue"] = include_ue
	var/obj/item/card/id/C = user.get_idcard(TRUE)
	.["can_load"] = !!(C && check_access(C))

/obj/machinery/computer/cloning/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("refresh")
			Topic(null, list("refresh" = "1"))
		if("autoprocess")
			Topic(null, list("task" = autoprocess ? "stopautoprocess" : "autoprocess"))
		if("scan")
			Topic(null, params["body_only"] ? list("scan" = "1", "body_only" = "1") : list("scan" = "1"))
		if("lock")
			Topic(null, list("lock" = "1"))
		if("clone")
			Topic(null, params["empty"] ? list("clone" = params["id"], "empty" = "TRUE") : list("clone" = params["id"]))
		if("delete")
			// The old window's two steps, asked once more in the window: look at the record, ask to delete it (the access check), confirm
			Topic(null, list("view_rec" = params["id"]))
			if(active_record && active_record.fields["id"] == params["id"])
				Topic(null, list("del_rec" = "1"))
				if(menu == 4)
					Topic(null, list("del_rec" = "1"))
		if("disk_eject")
			Topic(null, list("disk" = "eject"))
		if("disk_save", "disk_load")
			Topic(null, list("view_rec" = params["id"]))
			if(active_record && active_record.fields["id"] == params["id"])
				Topic(null, list("disk" = action == "disk_save" ? "save" : "load"))
		if("include")
			var/part = params["part"]
			if(part in list("se", "ui", "ue"))
				var/on = (part == "se" && include_se) || (part == "ui" && include_ui) || (part == "ue" && include_ue)
				Topic(null, list("task" = "[on ? "exclude" : "include"]_[part]"))
		if("clear_temp")
			temp = "Inactive"
	return TRUE
