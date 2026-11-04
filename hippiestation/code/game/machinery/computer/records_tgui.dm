// hippie -- the security and medical records consoles' windows in tgui (tgui-next interfaces/RecordsConsole.js): a searchable list
// of the crew, and the record beside it with its photos, edited in the window instead of input() popups. Whatever has no text to type
// goes through the console's own Topic(), so the logs, sounds and HUD updates are the old window's; typed fields keep its checks
// (canUseSecurityRecordsConsole(), canUseMedicalRecordsConsole()). Every change to a record now wants a login on the server: the old
// Topic() never checked one, the page just didn't offer the links.

/// A record photo's file name for the window: its own for every photo, so one replaced is never shown from the cache.
/proc/records_photo_name(obj/item/photo/P)
	return "recphoto_[copytext(REF(P), 4, -1)].png"

/// Sends a general record's photos to a user, returning their file names (null for a side with no photo).
/proc/records_send_photos(mob/user, datum/data/record/G)
	. = list("front" = null, "side" = null)
	if(!G || !user?.client)
		return
	for(var/side in list("front", "side"))
		var/obj/item/photo/P = record_photo(G, "photo_[side]")
		if(istype(P) && P.picture?.picture_image)
			var/name = records_photo_name(P)
			user << browse_rsc(P.picture.picture_image, name)
			.[side] = name

/// A record's comments, com_1 onwards, as text: the deleted ones say so.
/proc/records_comments(datum/data/record/R)
	. = list()
	var/counter = 1
	while(R.fields["com_[counter]"])
		var/text = R.fields["com_[counter]"]
		. += list(list("index" = counter, "text" = comm_plain_text(text), "deleted" = text == "<B>Deleted</B>"))
		counter++

/// A comment on a record, as the old window wrote them.
/proc/records_add_comment(datum/data/record/R, author, rank, text)
	var/counter = 1
	while(R.fields["com_[counter]"])
		counter++
	R.fields["com_[counter]"] = "Made by [author] ([rank]) on [station_time_timestamp()] [time2text(world.realtime, "MMM DD")], [GLOB.year_integer + 540]<BR>[text]"

/proc/records_general_fields(datum/data/record/G)
	return list(
		"ref" = REF(G),
		"name" = G.fields["name"],
		"id" = G.fields["id"],
		"rank" = G.fields["rank"],
		"gender" = G.fields["gender"],
		"age" = G.fields["age"],
		"species" = G.fields["species"],
		"fingerprint" = G.fields["fingerprint"],
		"p_stat" = G.fields["p_stat"],
		"m_stat" = G.fields["m_stat"],
	)

// ---------------------------------------------------------------------------------------------
// Security records
// ---------------------------------------------------------------------------------------------

/obj/machinery/computer/secure_data
	/// The photos last sent for the selected record, by side
	var/list/photo_files

/obj/machinery/computer/secure_data/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	if(z > 6)
		to_chat(user, "<span class='boldannounce'>Unable to establish a connection</span>: \black You're too far away from the station!")
		return
	add_fingerprint(user)
	photo_files = records_send_photos(user, active1)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "security_records", "Security Records Console", 900, 640, master_ui, state)
		ui.open()

/obj/machinery/computer/secure_data/ui_static_data(mob/user)
	. = list()
	.["species"] = GLOB.roundstart_races
	.["jobs"] = get_all_jobs()
	.["statuses"] = list(
		list("key" = "none", "name" = "None"),
		list("key" = "arrest", "name" = "*Arrest*"),
		list("key" = "incarcerated", "name" = "Incarcerated"),
		list("key" = "paroled", "name" = "Paroled"),
		list("key" = "released", "name" = "Discharged"),
	)

/obj/machinery/computer/secure_data/ui_data(mob/user)
	. = list()
	.["kind"] = "security"
	.["scan"] = scan ? scan.name : null
	.["holding_id"] = !!user.is_holding_item_of_type(/obj/item/card/id)
	.["silicon"] = issilicon(user)
	.["authenticated"] = authenticated
	.["rank"] = rank
	.["can_rank"] = (rank in list("Head of Personnel", "Captain", "AI", "Central Command"))
	.["printing"] = !!printing
	.["temp"] = temp ? comm_plain_text(temp) : null
	var/list/status_of = list()
	for(var/datum/data/record/E in GLOB.data_core.security)
		status_of["[E.fields["name"]]|[E.fields["id"]]"] = E.fields["criminal"]
	var/list/records = list()
	if(authenticated)
		for(var/datum/data/record/R in GLOB.data_core.general)
			var/list/entry = records_general_fields(R)
			entry["status"] = status_of["[R.fields["name"]]|[R.fields["id"]]"] || "No record"
			records += list(entry)
	.["records"] = records
	if(!(active1 in GLOB.data_core.general))
		active1 = null
	if(!(active2 in GLOB.data_core.security))
		active2 = null
	if(authenticated && (active1 || active2))
		var/list/selected = list()
		selected["general"] = active1 ? records_general_fields(active1) : null
		selected["photos"] = photo_files || list()
		if(active2)
			var/list/minor = list()
			for(var/datum/data/crime/C in active2.fields["mi_crim"])
				minor += list(list("name" = C.crimeName, "details" = C.crimeDetails, "author" = C.author, "time" = C.time, "id" = "[C.dataId]"))
			var/list/major = list()
			for(var/datum/data/crime/C in active2.fields["ma_crim"])
				major += list(list("name" = C.crimeName, "details" = C.crimeDetails, "author" = C.author, "time" = C.time, "id" = "[C.dataId]"))
			selected["record"] = list(
				"criminal" = active2.fields["criminal"],
				"minor" = minor,
				"major" = major,
				"notes" = active2.fields["notes"],
				"comments" = records_comments(active2),
			)
		else
			selected["record"] = null
		.["selected"] = selected
	else
		.["selected"] = null

/obj/machinery/computer/secure_data/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("eject_id")
			Topic(null, list("choice" = "Confirm Identity"))
			return TRUE
		if("login")
			Topic(null, list("choice" = "Log In"))
			return TRUE
		if("logout")
			Topic(null, list("choice" = "Log Out"))
			return TRUE
		if("clear_temp")
			temp = null
			return TRUE
	if(!authenticated)
		return
	switch(action)
		if("select")
			Topic(null, list("choice" = "Browse Record", "d_rec" = params["ref"]))
			photo_files = records_send_photos(usr, active1)
		if("close")
			active1 = null
			active2 = null
		if("new_record")
			Topic(null, list("choice" = "New Record (General)"))
			photo_files = list()
		if("new_security_record")
			Topic(null, list("choice" = "New Record (Security)"))
		if("edit")
			sec_records_edit(usr, params["field"], params["value"])
		if("gender")
			Topic(null, list("choice" = "Edit Field", "field" = "gender"))
		if("rank")
			if(active1 && (rank in list("Head of Personnel", "Captain", "AI", "Central Command")) && (params["rank"] in get_all_jobs()))
				active1.fields["rank"] = params["rank"]
		if("criminal")
			if(active2 && (params["status"] in list("none", "arrest", "incarcerated", "paroled", "released")))
				Topic(null, list("choice" = "Change Criminal Status", "criminal2" = params["status"]))
		if("add_crime")
			sec_records_add_crime(usr, params["kind"] == "major", params["name"], params["details"])
		if("delete_crime")
			Topic(null, list("choice" = "Edit Field", "field" = params["kind"] == "major" ? "ma_crim_delete" : "mi_crim_delete", "cdataid" = params["id"]))
		if("add_comment")
			var/text = stripped_input_text(params["text"], MAX_MESSAGE_LEN, TRUE)
			if(active2 && canUseSecurityRecordsConsole(usr, text, null, active2))
				records_add_comment(active2, authenticated, rank, text)
		if("delete_comment")
			Topic(null, list("choice" = "Delete Entry", "del_c" = "[text2num(params["index"])]"))
		if("delete_security")
			Topic(null, list("choice" = "Delete Record (Security) Execute"))
		if("delete_all")
			Topic(null, list("choice" = "Delete Record (ALL) Execute"))
			photo_files = list()
		if("purge")
			Topic(null, list("choice" = "Purge All Records"))
		if("print")
			Topic(null, list("choice" = "Print Record"))
		if("poster")
			sec_records_poster(usr, params["kind"] == "missing", params["alias"], params["header"], params["text"])
		if("photo_update")
			Topic(null, list("choice" = "Edit Field", "field" = params["side"] == "side" ? "upd_photo_side" : "upd_photo_front"))
			photo_files = records_send_photos(usr, active1)
		if("photo_print")
			Topic(null, list("choice" = "Edit Field", "field" = params["side"] == "side" ? "print_photo_side" : "print_photo_front"))
		if("photo_show")
			Topic(null, list("choice" = "Edit Field", "field" = params["side"] == "side" ? "show_photo_side" : "show_photo_front"))
	return TRUE

/// The old window's Edit Field popups, with the value from the window.
/obj/machinery/computer/secure_data/proc/sec_records_edit(mob/user, field, value)
	switch(field)
		if("name", "id")
			var/t1 = stripped_input_text(value, field == "name" ? MAX_MESSAGE_LEN : MAX_NAME_LEN)
			if(!active1 || !canUseSecurityRecordsConsole(user, t1, active1))
				return
			active1.fields[field] = t1
			if(active2)
				active2.fields[field] = t1
		if("fingerprint")
			var/t1 = stripped_input_text(value, MAX_NAME_LEN)
			if(active1 && canUseSecurityRecordsConsole(user, t1, active1))
				active1.fields["fingerprint"] = t1
		if("age")
			var/age = text2num(value)
			if(active1 && !isnull(age) && canUseSecurityRecordsConsole(user, "age", active1))
				active1.fields["age"] = round(clamp(age, 0, 999))
		if("species")
			if(active1 && (value in GLOB.roundstart_races) && canUseSecurityRecordsConsole(user, value, active1))
				active1.fields["species"] = value
		if("notes")
			var/t1 = stripped_input_text(value)
			if(active2 && canUseSecurityRecordsConsole(user, t1, null, active2))
				active2.fields["notes"] = t1

/obj/machinery/computer/secure_data/proc/sec_records_add_crime(mob/user, major, crime_name, details)
	var/t1 = stripped_input_text(crime_name, MAX_NAME_LEN)
	var/t2 = stripped_input_text(details)
	if(!active1 || !active2 || !canUseSecurityRecordsConsole(user, t1, null, active2))
		return
	var/crime = GLOB.data_core.createCrimeEntry(t1, t2, authenticated, station_time_timestamp())
	if(major)
		GLOB.data_core.addMajorCrime(active1.fields["id"], crime)
	else
		GLOB.data_core.addMinorCrime(active1.fields["id"], crime)
	investigate_log("New [major ? "Major" : "Minor"] Crime: <strong>[t1]</strong>: [t2] | Added to [active1.fields["name"]] by [key_name(user)]", INVESTIGATE_RECORDS)

/// The Print Poster and Print Missing branches of Topic(), with the alias, heading and description from the window.
/obj/machinery/computer/secure_data/proc/sec_records_poster(mob/user, missing, alias, header, text)
	if(printing || !active1)
		return
	var/name = stripped_input_text(alias, MAX_NAME_LEN)
	var/heading = stripped_input_text(header, 8)
	var/info = stripped_input_text(text, MAX_MESSAGE_LEN, TRUE)
	if(!name || !info || !canUseSecurityRecordsConsole(user, name, active1))
		return
	var/obj/item/photo/photo = record_photo(active1, "photo_front")
	if(!istype(photo))
		say("There's no photo on file for that record.")
		return
	playsound(loc, 'sound/items/poster_being_created.ogg', 100, TRUE)
	printing = TRUE
	sleep(30)
	if(active1 in GLOB.data_core.general) //make sure the record still exists.
		if(missing)
			new /obj/item/poster/wanted/missing(loc, photo.picture.picture_image, name, info, heading || "MISSING")
		else
			new /obj/item/poster/wanted(loc, photo.picture.picture_image, name, info, heading || "WANTED")
	printing = FALSE

// ---------------------------------------------------------------------------------------------
// Medical records
// ---------------------------------------------------------------------------------------------

/obj/machinery/computer/med_data
	var/list/photo_files

/// The diseases the old window's Virus Database listed, worked out the first time a window asks.
GLOBAL_LIST_EMPTY(records_virus_database)

/proc/records_build_virus_database()
	. = list()
	var/list/seen = list()
	for(var/Dt in typesof(/datum/disease))
		var/datum/disease/D = new Dt(0)
		if(istype(D, /datum/disease/advance) || !D.desc || seen[D.name]) // subtypes share a name: once each, as a player would look it up
			qdel(D)
			continue
		seen[D.name] = TRUE
		var/list/affects = list()
		for(var/mob/M as anything in D.viable_mobtypes)
			affects += initial(M.name)
		. += list(list(
			"name" = D.name,
			"stages" = D.max_stages,
			"spread" = D.spread_text,
			"cure" = D.cure_text || "none",
			"affects" = affects.Join(", "),
			"desc" = D.desc,
			"severity" = D.severity,
		))
		qdel(D)

/obj/machinery/computer/med_data/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.default_state)
	add_fingerprint(user)
	photo_files = records_send_photos(user, active1)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "medical_records", "Medical Records Console", 900, 640, master_ui, state)
		ui.open()

/obj/machinery/computer/med_data/ui_static_data(mob/user)
	. = list()
	if(!length(GLOB.records_virus_database))
		GLOB.records_virus_database = records_build_virus_database()
	.["viruses"] = GLOB.records_virus_database
	.["p_stats"] = list(
		list("key" = "deceased", "name" = "*Deceased*"),
		list("key" = "unconscious", "name" = "*Unconscious*"),
		list("key" = "active", "name" = "Active"),
		list("key" = "unfit", "name" = "Physically Unfit"),
	)
	.["m_stats"] = list(
		list("key" = "insane", "name" = "*Insane*"),
		list("key" = "unstable", "name" = "*Unstable*"),
		list("key" = "watch", "name" = "*Watch*"),
		list("key" = "stable", "name" = "Stable"),
	)
	.["blood_types"] = list(
		list("key" = "an", "name" = "A-"), list("key" = "ap", "name" = "A+"),
		list("key" = "bn", "name" = "B-"), list("key" = "bp", "name" = "B+"),
		list("key" = "abn", "name" = "AB-"), list("key" = "abp", "name" = "AB+"),
		list("key" = "on", "name" = "O-"), list("key" = "op", "name" = "O+"),
	)

/obj/machinery/computer/med_data/ui_data(mob/user)
	. = list()
	.["kind"] = "medical"
	.["scan"] = scan ? scan.name : null
	.["holding_id"] = !!user.is_holding_item_of_type(/obj/item/card/id)
	.["silicon"] = issilicon(user)
	.["authenticated"] = authenticated ? (istext(authenticated) ? authenticated : rank) : null
	.["rank"] = rank
	.["printing"] = !!printing
	.["temp"] = temp ? comm_plain_text(temp) : null
	var/list/medical_of = list()
	for(var/datum/data/record/E in GLOB.data_core.medical)
		medical_of["[E.fields["name"]]|[E.fields["id"]]"] = E
	var/list/records = list()
	if(authenticated)
		for(var/datum/data/record/R in GLOB.data_core.general)
			var/list/entry = records_general_fields(R)
			var/datum/data/record/M = medical_of["[R.fields["name"]]|[R.fields["id"]]"]
			entry["blood_type"] = M ? M.fields["blood_type"] : null
			entry["b_dna"] = M ? M.fields["b_dna"] : null
			records += list(entry)
	.["records"] = records
	if(!(active1 in GLOB.data_core.general))
		active1 = null
	if(!(active2 in GLOB.data_core.medical))
		active2 = null
	if(authenticated && active1)
		var/list/selected = list()
		selected["general"] = records_general_fields(active1)
		selected["photos"] = photo_files || list()
		if(active2)
			var/list/record = list()
			for(var/field in list("blood_type", "b_dna", "mi_dis", "mi_dis_d", "ma_dis", "ma_dis_d", "alg", "alg_d", "cdi", "cdi_d", "notes"))
				record[field] = active2.fields[field]
			record["comments"] = records_comments(active2)
			selected["record"] = record
		else
			selected["record"] = null
		.["selected"] = selected
	else
		.["selected"] = null
	var/list/medbots = list()
	if(authenticated)
		for(var/mob/living/simple_animal/bot/medbot/M in GLOB.alive_mob_list)
			var/turf/T = get_turf(M)
			if(!T || M.z != z) //only those on the same level as the computer, as the old window had it
				continue
			var/beaker = (!isnull(M.reagent_glass) && M.use_beaker) ? "[M.reagent_glass.reagents.total_volume] / [M.reagent_glass.reagents.maximum_volume]" : null
			medbots += list(list("name" = M.name, "x" = T.x, "y" = T.y, "area" = get_area_name(T, TRUE), "on" = !!M.on, "beaker" = beaker))
	.["medbots"] = medbots

/obj/machinery/computer/med_data/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("eject_id")
			Topic(null, list("scan" = "1"))
			return TRUE
		if("login")
			Topic(null, list("login" = "1"))
			return TRUE
		if("logout")
			Topic(null, list("logout" = "1"))
			return TRUE
		if("clear_temp")
			temp = null
			return TRUE
	if(!authenticated)
		return
	switch(action)
		if("select")
			// A general record with no medical one is shown too, with a button to make one (the old window dropped it)
			var/datum/data/record/G = locate(params["ref"]) in GLOB.data_core.general
			active1 = G
			active2 = G ? find_record("id", G.fields["id"], GLOB.data_core.medical) : null
			photo_files = records_send_photos(usr, active1)
		if("close")
			active1 = null
			active2 = null
		if("new_record")
			Topic(null, list("new" = "1"))
		if("edit")
			med_records_edit(usr, params["field"], params["value"])
		if("gender")
			Topic(null, list("field" = "gender"))
		if("p_stat")
			if(active1 && (params["key"] in list("deceased", "unconscious", "active", "unfit")))
				Topic(null, list("p_stat" = params["key"]))
		if("m_stat")
			if(active1 && (params["key"] in list("insane", "unstable", "watch", "stable")))
				Topic(null, list("m_stat" = params["key"]))
		if("blood_type")
			if(active2 && (params["key"] in list("an", "ap", "bn", "bp", "abn", "abp", "on", "op")))
				Topic(null, list("blood_type" = params["key"]))
		if("add_comment")
			var/text = stripped_input_text(params["text"], MAX_MESSAGE_LEN, TRUE)
			if(active2 && canUseMedicalRecordsConsole(usr, text, null, active2))
				records_add_comment(active2, authenticated, rank, text)
		if("delete_comment")
			Topic(null, list("del_c" = "[text2num(params["index"])]"))
		if("delete_medical")
			if(active2)
				Topic(null, list("del_r2" = "1"))
		if("purge")
			Topic(null, list("del_all2" = "1"))
		if("print")
			Topic(null, list("print_p" = "1"))
		if("photo_show")
			Topic(null, list("field" = params["side"] == "side" ? "show_photo_side" : "show_photo_front"))
	return TRUE

/// The old window's field popups, with the value from the window.
/obj/machinery/computer/med_data/proc/med_records_edit(mob/user, field, value)
	switch(field)
		if("fingerprint")
			var/t1 = stripped_input_text(value, MAX_NAME_LEN)
			if(active1 && canUseMedicalRecordsConsole(user, t1, active1))
				active1.fields["fingerprint"] = t1
		if("age")
			var/age = text2num(value)
			if(active1 && !isnull(age) && canUseMedicalRecordsConsole(user, "age", active1))
				active1.fields["age"] = round(clamp(age, 0, 999))
		if("species")
			var/t1 = stripped_input_text(value, MAX_NAME_LEN)
			if(active1 && canUseMedicalRecordsConsole(user, t1, active1))
				active1.fields["species"] = t1
		if("mi_dis", "mi_dis_d", "ma_dis", "ma_dis_d", "alg", "alg_d", "cdi", "cdi_d", "notes", "b_dna")
			var/t1 = stripped_input_text(value)
			if(active2 && canUseMedicalRecordsConsole(user, t1, null, active2))
				active2.fields[field] = t1
