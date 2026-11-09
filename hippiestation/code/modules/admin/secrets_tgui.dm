// hippie -- the admin Secrets panel and its lists in tgui (interfaces/AdminSecrets.js): the secrets by section, the ones that change
// the round marked, with a search; each one is the old link (secrets=...) sent with the admin token to the holder's Topic(), so the
// rights checks, confirmations and logs are Secrets_topic()'s. The lists it showed as HTML popups (the admin and mentor logs, the
// admins, bombers, signalers, law changes, the crew manifest, DNA and fingerprints) open in a searchable list window.

/datum/admins
	var/datum/admin_secrets_window/secrets_window

/datum/admins/Secrets()
	if(!check_rights(0))
		return
	if(!secrets_window)
		secrets_window = new(src)
	secrets_window.ui_interact(usr)

/datum/admin_secrets_window
	var/datum/admins/holder

/datum/admin_secrets_window/New(datum/admins/H)
	holder = H

/datum/admin_secrets_window/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "admin_secrets", "Secrets", 560, 680, master_ui, state)
		ui.open()

/datum/admin_secrets_window/ui_status(mob/user, datum/ui_state/state)
	return (user.client?.holder && user.client.holder == holder) ? UI_INTERACTIVE : UI_CLOSE

/// Secrets() as data, section by section, each with the rights it needed there. "danger" marks the ones that change the round.
/datum/admin_secrets_window/proc/secret_sections(mob/user)
	var/list/sections = list()
	sections += list(list("name" = "General", "items" = list(
		list("id" = "spawnselfdummy", "label" = "Spawn yourself as a test dummy"),
		list("id" = "admin_log", "label" = "Admin log"),
		list("id" = "mentor_log", "label" = "Mentor log"),
		list("id" = "show_admins", "label" = "Admin list"),
	)))
	if(check_rights_for(user.client, R_ADMIN))
		sections += list(list("name" = "Admin", "items" = list(
			list("id" = "clear_virus", "label" = "Cure all diseases"),
			list("id" = "list_bombers", "label" = "Bombing list"),
			list("id" = "list_signalers", "label" = "Last [length(GLOB.lastsignalers)] signalers"),
			list("id" = "list_lawchanges", "label" = "Last [length(GLOB.lawchanges)] law changes"),
			list("id" = "showailaws", "label" = "AI laws"),
			list("id" = "showgm", "label" = "Game mode"),
			list("id" = "manifest", "label" = "Crew manifest"),
			list("id" = "DNA", "label" = "DNA (blood)"),
			list("id" = "fingerprints", "label" = "Fingerprints"),
			list("id" = "ctfbutton", "label" = "Enable/disable CTF"),
			list("id" = "tdomereset", "label" = "Reset the Thunderdome"),
			list("id" = "set_name", "label" = "Rename the station", "danger" = TRUE),
			list("id" = "reset_name", "label" = "Reset the station name"),
			list("id" = "night_shift_set", "label" = "Night shift mode"),
		)))
		sections += list(list("name" = "Shuttles", "items" = list(
			list("id" = "moveferry", "label" = "Move the ferry"),
			list("id" = "togglearrivals", "label" = "Toggle the arrivals ferry"),
			list("id" = "moveminingshuttle", "label" = "Move the mining shuttle"),
			list("id" = "movelaborshuttle", "label" = "Move the labor shuttle"),
		)))
	if(check_rights_for(user.client, R_FUN))
		sections += list(list("name" = "Fun", "items" = list(
			list("id" = "virus", "label" = "Virus outbreak", "danger" = TRUE),
			list("id" = "monkey", "label" = "Turn all humans into monkeys", "danger" = TRUE),
			list("id" = "anime", "label" = "Chinese cartoons", "danger" = TRUE),
			list("id" = "allspecies", "label" = "Change every human's species", "danger" = TRUE),
			list("id" = "power", "label" = "Power all areas"),
			list("id" = "unpower", "label" = "Unpower all areas", "danger" = TRUE),
			list("id" = "quickpower", "label" = "Charge all SMES"),
			list("id" = "tripleAI", "label" = "Triple AI mode (in the lobby)"),
			list("id" = "traitor_all", "label" = "Everyone is the traitor", "danger" = TRUE),
			list("id" = "guns", "label" = "Summon guns", "danger" = TRUE),
			list("id" = "magic", "label" = "Summon magic", "danger" = TRUE),
			list("id" = "events", "label" = "Summon events (toggle)", "danger" = TRUE),
			list("id" = "onlyone", "label" = "There can only be one!", "danger" = TRUE),
			list("id" = "delayed_onlyone", "label" = "There can only be one! (40 s delay)", "danger" = TRUE),
			list("id" = "dumbify", "label" = "Make all players dumb", "danger" = TRUE),
			list("id" = "eagles", "label" = "Egalitarian station mode", "danger" = TRUE),
			list("id" = "ancap", "label" = "Anarcho-capitalist station mode", "danger" = TRUE),
			list("id" = "blackout", "label" = "Break all lights", "danger" = TRUE),
			list("id" = "whiteout", "label" = "Fix all lights"),
			list("id" = "floorlava", "label" = "The floor is lava!", "danger" = TRUE),
			list("id" = "customportal", "label" = "Custom portal storm", "danger" = TRUE),
			list("id" = "changebombcap", "label" = "Change the bomb cap", "danger" = TRUE),
			list("id" = "masspurrbation", "label" = "Mass purrbation", "danger" = TRUE),
			list("id" = "massremovepurrbation", "label" = "Mass remove purrbation"),
			list("id" = "winter_start", "label" = "Start winter", "danger" = TRUE),
			list("id" = "winter_stop", "label" = "Stop winter"),
			list("id" = "upgrade_machines", "label" = "Upgrade all station machines, APCs, SMES, mechs and cyborgs"),
			list("id" = "plasma_flood", "label" = "Flood the station with plasma", "danger" = TRUE),
		)))
	if(check_rights_for(user.client, R_DEBUG))
		sections += list(list("name" = "Security level elevated", "items" = list(
			list("id" = "maint_access_engiebrig", "label" = "Maintenance doors: engineering and brig access only", "danger" = TRUE),
			list("id" = "maint_access_brig", "label" = "Maintenance doors: brig access only", "danger" = TRUE),
			list("id" = "infinite_sec", "label" = "Remove the cap on security officers"),
		)))
	return sections

/datum/admin_secrets_window/ui_data(mob/user)
	return list("sections" = secret_sections(user))

/datum/admin_secrets_window/ui_act(action, list/params)
	if(..())
		return
	if(action != "secret")
		return
	var/id = "[params["id"]]"
	var/known = FALSE
	for(var/list/section in secret_sections(usr))
		for(var/list/item in section["items"])
			if(item["id"] == id)
				known = TRUE
	if(!known)
		return
	var/list/href_list = list("secrets" = id)
	// The old Start/Stop Winter links sent toggle=1 and toggle=0, and "0" is a string: Stop started it again. Stop sends no toggle.
	if(id == "winter_start")
		href_list = list("secrets" = "winter", "toggle" = "1")
	else if(id == "winter_stop")
		href_list = list("secrets" = "winter")
	href_list["admin_token"] = RawHrefToken()
	INVOKE_ASYNC(holder, TYPE_PROC_REF(/datum/admins, window_topic), href_list)
	return TRUE

/// The holder's Topic() with a link from a window: the secrets can ask for confirmation, so not in the click
/datum/admins/proc/window_topic(list/href_list)
	Topic(list2params(href_list), href_list)

// ---------------------------------------------------------------------------------------------
// The lists
// ---------------------------------------------------------------------------------------------

/// A list of lines (or rows with columns) in a searchable window, for admins
/datum/admin_list_window
	var/title
	var/list/columns
	var/list/rows

/proc/show_admin_list(mob/user, title, list/rows, list/columns)
	var/datum/admin_list_window/W = new
	W.title = title
	W.rows = rows
	W.columns = columns
	var/datum/tgui/ui = new(user, W, "main", "admin_list", title, columns ? 620 : 720, 520, null, GLOB.always_state)
	ui.open()

/datum/admin_list_window/ui_status(mob/user, datum/ui_state/state)
	return user.client?.holder ? UI_INTERACTIVE : UI_CLOSE

/datum/admin_list_window/ui_close(mob/user)
	qdel(src)

/datum/admin_list_window/ui_static_data(mob/user)
	return list("title" = title, "columns" = columns, "rows" = rows)

/// Each entry of a log list as plain text
/proc/admin_list_lines(list/L)
	. = list()
	for(var/line in L)
		. += list(list(comm_plain_text("[line]")))

/datum/admins/Secrets_topic(item, href_list)
	switch(item)
		if("admin_log")
			show_admin_list(usr, "Admin log", admin_list_lines(GLOB.admin_log))
			return
		if("mentor_log")
			show_admin_list(usr, "Mentor log", admin_list_lines(GLOB.mentorlog))
			return
		if("show_admins")
			var/list/rows = list()
			for(var/ckey in GLOB.admin_datums)
				var/datum/admins/D = GLOB.admin_datums[ckey]
				rows += list(list(ckey, "[D.rank.name]"))
			show_admin_list(usr, "Current admins", rows, list("Key", "Rank"))
			return
		if("list_bombers", "list_signalers", "list_lawchanges", "manifest", "DNA", "fingerprints")
			if(!check_rights(R_ADMIN))
				return
			switch(item)
				if("list_bombers")
					show_admin_list(usr, "Bombing list", admin_list_lines(GLOB.bombers))
				if("list_signalers")
					show_admin_list(usr, "Last [length(GLOB.lastsignalers)] signalers", admin_list_lines(GLOB.lastsignalers))
				if("list_lawchanges")
					show_admin_list(usr, "Last [length(GLOB.lawchanges)] law changes", admin_list_lines(GLOB.lawchanges))
				if("manifest")
					var/list/rows = list()
					for(var/datum/data/record/t in GLOB.data_core.general)
						rows += list(list("[t.fields["name"]]", "[t.fields["rank"]]"))
					show_admin_list(usr, "Crew manifest", rows, list("Name", "Position"))
				if("DNA")
					var/list/rows = list()
					for(var/mob/living/carbon/human/H in GLOB.carbon_list)
						if(H.ckey)
							rows += list(list("[H]", "[H.dna.unique_enzymes]", "[H.dna.blood_type]"))
					show_admin_list(usr, "DNA from blood", rows, list("Name", "DNA", "Blood type"))
				if("fingerprints")
					var/list/rows = list()
					for(var/mob/living/carbon/human/H in GLOB.carbon_list)
						if(H.ckey)
							rows += list(list("[H]", md5(H.dna.uni_identity)))
					show_admin_list(usr, "Fingerprints", rows, list("Name", "Fingerprints"))
			return
	return ..()
