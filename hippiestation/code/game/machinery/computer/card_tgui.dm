// hippie -- the ID console's window in tgui (tgui-next interfaces/IdConsole.js): the two card slots, logging in, the job templates,
// access by department with Grant all and Revoke all and a search, renaming, job slots, and the crew manifest by department.
// Every button goes through the console's own Topic(), so the rules are the old window's: who may log in to what, what a department
// head may change, the slot cooldowns. The HoP bots (bots_ai/bot_hopping.dm) work its slots and cards directly, as before.

/obj/machinery/computer/card/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	add_fingerprint(user)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "id_console", name, 900, 680, master_ui, state)
		ui.open()

/// The departments' job titles, for grouping the templates and the manifest.
/proc/card_console_departments()
	return list(
		list("name" = "Command", "jobs" = GLOB.command_positions),
		list("name" = "Security", "jobs" = GLOB.security_positions),
		list("name" = "Engineering", "jobs" = GLOB.engineering_positions),
		list("name" = "Medical", "jobs" = GLOB.medical_positions),
		list("name" = "Science", "jobs" = GLOB.science_positions),
		list("name" = "Supply", "jobs" = GLOB.supply_positions),
		list("name" = "Service", "jobs" = GLOB.civilian_positions),
	)

/obj/machinery/computer/card/ui_static_data(mob/user)
	. = list()
	var/centcom = istype(src, /obj/machinery/computer/card/centcom)
	.["centcom"] = centcom
	var/list/regions = list()
	if(centcom)
		var/list/accesses = list()
		for(var/A in get_all_centcom_access())
			accesses += list(list("id" = A, "name" = get_centcom_access_desc(A)))
		regions += list(list("id" = 0, "name" = "Central Command", "accesses" = accesses))
	else
		for(var/i in 1 to 7)
			var/list/accesses = list()
			for(var/A in get_region_accesses(i))
				accesses += list(list("id" = A, "name" = get_access_desc(A)))
			regions += list(list("id" = i, "name" = get_region_accesses_name(i), "accesses" = accesses))
	.["regions"] = regions
	// The templates, by department; the CentCom console has its own
	var/list/jobs = get_jobs()
	var/list/groups = list()
	if(centcom)
		groups += list(list("name" = "Central Command", "jobs" = jobs))
	else
		var/list/placed = list()
		for(var/list/dept in card_console_departments())
			var/list/titles = list()
			for(var/title in dept["jobs"])
				if((title in jobs) && !placed[title])
					titles += title
					placed[title] = TRUE
			if(length(titles))
				groups += list(list("name" = dept["name"], "jobs" = titles))
		var/list/other = list()
		for(var/title in jobs)
			if(!placed[title])
				other += title
		if(length(other))
			groups += list(list("name" = "Other", "jobs" = other))
	.["job_groups"] = groups

/obj/machinery/computer/card/ui_data(mob/user)
	. = list()
	.["authenticated"] = authenticated
	.["target_dept"] = target_dept
	.["regions_allowed"] = authenticated == 1 ? region_access : null
	.["scan"] = scan ? scan.name : null
	.["holding_id"] = istype(user.get_active_held_item(), /obj/item/card/id)
	.["silicon"] = issilicon(user)
	if(modify)
		.["modify"] = list(
			"name" = modify.name,
			"owner" = modify.registered_name,
			"assignment" = modify.assignment || "Unassigned",
			"access" = modify.access,
		)
		.["can_demote"] = authenticated == 1 && ((modify.assignment in head_subordinates) || modify.assignment == "Assistant")
	else
		.["modify"] = null
	.["printing"] = !!printing
	// Job slots: open to an ID that can change IDs, on the main console
	var/can_slots = scan && (ACCESS_CHANGE_IDS in scan.access) && !target_dept
	.["can_slots"] = !!can_slots
	var/list/slots = list()
	if(!target_dept)
		var/wait = max(0, round(change_position_cooldown - ((world.time / 10) - GLOB.time_last_changed_position), 1))
		for(var/datum/job/job in SSjob.occupations)
			if(job.title in blacklisted)
				continue
			slots += list(list(
				"title" = job.title,
				"current" = job.current_positions,
				"total" = job.total_positions,
				"open" = can_open_job(job), // JOB_ALLOWED 1, JOB_DENIED 0, JOB_MAX_POSITIONS -1, JOB_COOLDOWN -2
				"close" = can_close_job(job),
				"wait" = wait,
				"prioritized" = (job in SSjob.prioritized_jobs),
				"can_prioritize" = job.total_positions > 0 && ((job in SSjob.prioritized_jobs) || length(SSjob.prioritized_jobs) < 5),
			))
	.["slots"] = slots
	// The manifest, by department
	var/list/manifest = list()
	var/list/dept_of = list()
	for(var/list/dept in card_console_departments())
		for(var/title in dept["jobs"])
			if(!dept_of[title])
				dept_of[title] = dept["name"]
	for(var/datum/data/record/R in sortRecord(GLOB.data_core.general))
		var/rank = R.fields["rank"]
		manifest += list(list("name" = R.fields["name"], "rank" = rank, "dept" = dept_of[rank] || "Other"))
	.["manifest"] = manifest

/obj/machinery/computer/card/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("eject_scan")
			Topic(null, list("choice" = "scan"))
		if("eject_modify")
			Topic(null, list("choice" = "modify"))
		if("login")
			Topic(null, list("choice" = "auth"))
		if("logout")
			Topic(null, list("choice" = "logout"))
		if("access")
			var/A = text2num(params["access"])
			if(!card_region_editable(card_region_of(A)))
				return
			Topic(null, list("choice" = "access", "access_target" = "[A]", "allowed" = params["allowed"] ? "1" : "0"))
		if("region")
			var/region = text2num(params["region"])
			if(!authenticated || !modify || !card_region_editable(region))
				return
			var/list/accesses = istype(src, /obj/machinery/computer/card/centcom) ? get_all_centcom_access() : get_region_accesses(region)
			var/list/had = modify.access.Copy()
			if(params["allowed"])
				modify.access |= accesses
			else
				modify.access -= accesses
			log_card_changes(usr, modify, had, modify.assignment, modify.registered_name) // log_gaps.dm
			playsound(src, "terminal_type", 50, FALSE)
			modify.update_label()
		if("assign")
			Topic(null, list("choice" = "assign", "assign_target" = params["job"]))
		if("assign_custom")
			if(authenticated != 2 || !modify)
				return
			var/title = reject_bad_text(params["title"], MAX_NAME_LEN)
			if(!title)
				to_chat(usr, "<span class='error'>Invalid assignment.</span>")
				return
			var/old_job = modify.assignment
			modify.assignment = title
			log_card_changes(usr, modify, modify.access.Copy(), old_job, modify.registered_name) // log_gaps.dm
			modify.update_label()
			playsound(src, 'sound/machines/terminal_prompt_confirm.ogg', 50, FALSE)
		if("demote")
			Topic(null, list("choice" = "demote"))
		if("rename")
			Topic(null, list("choice" = "reg", "reg" = params["name"]))
		if("open_slot")
			Topic(null, list("choice" = "make_job_available", "job" = params["job"]))
		if("close_slot")
			Topic(null, list("choice" = "make_job_unavailable", "job" = params["job"]))
		if("prioritize")
			Topic(null, list("choice" = "prioritize_job", "job" = params["job"]))
		if("print")
			Topic(null, list("choice" = "print"))
	return TRUE

/// The region an access is listed under here: 0 on the CentCom console.
/obj/machinery/computer/card/proc/card_region_of(access)
	if(istype(src, /obj/machinery/computer/card/centcom))
		return (access in get_all_centcom_access()) ? 0 : null
	for(var/i in 1 to 7)
		if(access in get_region_accesses(i))
			return i
	return null

/// Whether whoever's logged in may change a region: all of them at full access, only their own department as a department head.
/obj/machinery/computer/card/proc/card_region_editable(region)
	if(isnull(region) || !authenticated)
		return FALSE
	return authenticated == 2 || (region in region_access)
