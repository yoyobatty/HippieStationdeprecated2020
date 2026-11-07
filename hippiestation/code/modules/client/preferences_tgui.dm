// Character setup as one tgui window (tgui-next Preferences.js): the same tabs and settings as the old browser window, with the
// occupation and quirk windows folded in as tabs, the character drawn on the left with buttons to turn it, and choices made in the
// window where the old one asked in pop-ups (lists become dropdowns, the name and age are typed). Colours still open BYOND's colour
// picker. Everything else is the old link sent on to process_link(), so its rules stay the same. The user's ruling, 2026-11-05.
//
// Each tab is sections of rows. A row says what it is (label), what it's set to (value) and how it changes: "toggle" (click sends
// link to process_link), "pick" (a dropdown of options, sent back as "set"), "text" and "number" (typed, sent as "set"), "color"
// (a swatch; click sends link, which opens the colour picker) or "info" (just shown).

#define PREFS_PREVIEW_MAP "prefs_preview_map"
#define PREFS_TAB_JOBS 5
#define PREFS_TAB_QUIRKS 6

/datum/preferences
	/// The character, as drawn in the window
	var/obj/screen/preview_screen
	/// The floor it stands on
	var/obj/screen/preview_floor
	/// Which way the drawing faces
	var/preview_dir = SOUTH
	/// The character from its four sides
	var/list/preview_sides
	/// Draw them in plain clothes, not their top job's outfit
	var/preview_plain = FALSE
	/// Changed since the last save or load
	var/prefs_dirty = FALSE

/datum/preferences/Destroy()
	QDEL_NULL(preview_screen)
	QDEL_NULL(preview_floor)
	QDEL_LIST(preview_sides)
	return ..()

/datum/preferences/ShowChoices(mob/user)
	if(!user || !user.client)
		return
	update_preview_icon()
	ui_interact(user)

/datum/preferences/SetChoices(mob/user, limit, list/splitJobs, widthPerColumn, height)
	current_tab = PREFS_TAB_JOBS
	ShowChoices(user)

/datum/preferences/SetQuirks(mob/user)
	if(!SSquirks)
		to_chat(user, "<span class='danger'>The quirk subsystem is still initializing! Try again in a minute.</span>")
		return
	current_tab = PREFS_TAB_QUIRKS
	ShowChoices(user)

/// The drawing in the window, where the old window drew four on its own map
/client/show_character_previews(mutable_appearance/MA)
	if(prefs)
		prefs.set_preview(MA)

/datum/preferences/proc/set_preview(mutable_appearance/MA)
	if(!preview_screen)
		// The floor: a second map shows a whole view (about 15 by 15), not just what's on it
		preview_floor = new
		preview_floor.icon = 'icons/effects/alphacolors.dmi'
		preview_floor.icon_state = ""
		preview_floor.color = "#1b1d21"
		preview_floor.layer = TURF_LAYER
		preview_floor.plane = FLOOR_PLANE - 1
		preview_floor.assigned_map = PREFS_PREVIEW_MAP
		preview_floor.del_on_map_removal = FALSE
		preview_floor.screen_loc = "[PREFS_PREVIEW_MAP]:1,1 to 15,15"
		preview_screen = new // the front, also what a client registers first
		preview_sides = list(preview_screen)
		for(var/i in 1 to 3)
			preview_sides += new /obj/screen
		// A card behind each view
		for(var/i in 1 to 4)
			var/obj/screen/card = new
			card.icon = 'icons/effects/alphacolors.dmi'
			card.icon_state = ""
			card.color = "#2c3038"
			card.plane = FLOOR_PLANE - 1
			card.layer = TURF_LAYER + 0.1
			card.transform = matrix(5.6, 0, 0, 0, 5.6, 0)
			preview_sides += card
		for(var/obj/screen/side as anything in preview_sides)
			side.assigned_map = PREFS_PREVIEW_MAP
			side.del_on_map_removal = FALSE
	// The boarding pass look: photos on file paper, light or dark
	var/pass = GLOB.lobby_design == "pass"
	var/floor_color = "#1b1d21"
	var/card_color = "#2c3038"
	if(pass)
		floor_color = pass_dark ? "#1d232d" : "#e9e3d3"
		card_color = pass_dark ? "#2b3341" : "#c9d2de"
	preview_floor.color = floor_color
	// Front, left side, back, right side, two by two, each drawn five times over
	var/list/dirs = list(SOUTH, WEST, NORTH, EAST)
	var/list/spots = list("4,10", "11,10", "4,3", "11,3")
	for(var/i in 1 to 4)
		var/obj/screen/side = preview_sides[i]
		side.appearance = MA
		side.dir = dirs[i]
		side.transform = matrix(5, 0, 0, 0, 5, 0)
		side.screen_loc = "[PREFS_PREVIEW_MAP]:[spots[i]]"
		var/obj/screen/card = preview_sides[i + 4]
		card.screen_loc = "[PREFS_PREVIEW_MAP]:[spots[i]]"
		card.color = card_color

/datum/preferences/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		if(preview_screen)
			user.client.register_map_obj(preview_floor)
			for(var/obj/screen/side as anything in preview_sides)
				user.client.register_map_obj(side)
		ui = new(user, src, ui_key, "preferences", "Character Setup", 1120, 780, master_ui, state)
		ui.set_autoupdate(FALSE)
		ui.open()

/datum/preferences/ui_status(mob/user, datum/ui_state/state)
	return (user.client && user.client == parent) ? UI_INTERACTIVE : UI_CLOSE

/datum/preferences/ui_close(mob/user)
	if(user && user.client)
		user.client.clear_map(PREFS_PREVIEW_MAP)

/datum/preferences/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	if(..())
		return
	var/mob/user = usr
	if(!user.client || user.client != parent)
		return
	if(findtext(action, "kb_") == 1) //the keybind panel (keybind_panel.dm)
		return keybind_act(action, params, user)
	switch(action)
		if("link")
			var/list/href = params.Copy()
			href -= "src"
			var/preference = href["preference"]
			if(preference in list("save", "load", "changeslot"))
				prefs_dirty = FALSE
			else if(!(preference in list("tab", "keybindings_capture")) && !(href["task"] in list("menu", "close")) && !href["bancheck"])
				prefs_dirty = TRUE
			process_link(user, href)
			return TRUE
		if("set")
			if(pref_set(user, params["key"], params["value"]))
				prefs_dirty = TRUE
				ShowChoices(user)
			return TRUE
		if("outfit")
			preview_plain = !preview_plain
			ShowChoices(user)
			return TRUE
		if("pass_dark")
			// The boarding pass windows on dark paper or light; kept at once, like the Display panel's choices
			pass_dark = !pass_dark
			save_preferences()
			ShowChoices(user)
			SStgui.update_uis(user) // the lobby and job list behind it
			var/mob/dead/new_player/NP = user
			if(istype(NP) && NP.late_join_menu)
				SStgui.update_uis(NP.late_join_menu)
			return TRUE
		if("copy_slot", "delete_slot")
			var/slot = text2num(params["num"])
			if(!path || !slot || slot < 1 || slot > max_save_slots)
				return
			if(action == "copy_slot")
				// This character, saved into that slot, which becomes the one in use
				default_slot = slot
				save_character()
				save_preferences()
				prefs_dirty = FALSE
			else
				var/savefile/S = new /savefile(path)
				S.cd = "/"
				S.dir.Remove("character[slot]")
				if(slot == default_slot)
					random_character()
					real_name = random_unique_name(gender)
					save_character()
					prefs_dirty = FALSE
			ShowChoices(user)
			return TRUE

// Rows

/datum/preferences/proc/pref_row(label, value, kind, list/link, key, list/options, list/extra)
	var/list/row = list("label" = label, "value" = value, "kind" = kind)
	if(link)
		row["link"] = link
	if(key)
		row["key"] = key
	if(options)
		row["options"] = options
	if(extra)
		row += extra
	return row

/datum/preferences/proc/pref_toggle(label, on_text, preference, on = TRUE)
	return pref_row(label, on_text, "toggle", list("preference" = preference), extra = list("on" = !!on))

/datum/preferences/proc/pref_pick(label, value, key)
	return pref_row(label, value, "pick", key = key, options = pref_pick_options(key))

/datum/preferences/proc/pref_color(label, hex, preference)
	if(hex && copytext(hex, 1, 2) != "#")
		hex = "#[hex]"
	return pref_row(label, hex, "color", list("preference" = preference, "task" = "input"), key = preference)

/datum/preferences/proc/pref_section(title, list/rows, list/extra)
	var/list/section = list("title" = title, "rows" = rows)
	if(extra)
		section += extra
	return section

// What each choice offers, by the old link's preference key

/datum/preferences/proc/pref_pick_options(key)
	var/list/L
	switch(key)
		if("gender")
			L = friendlyGenders
		if("voice")
			L = ((gender == FEMALE) ? splittext(CONFIG_GET(string/tts_voice_female), ",") : splittext(CONFIG_GET(string/tts_voice_male), ","))
		if("species")
			// Shown by name; the list holds ids
			L = list()
			for(var/id in GLOB.roundstart_races)
				var/datum/species/S = GLOB.species_list[id]
				L += initial(S.name)
		if("hair_style")
			L = (gender == MALE) ? GLOB.hair_styles_male_list : (gender == FEMALE) ? GLOB.hair_styles_female_list : GLOB.hair_styles_list
		if("facial_hair_style")
			L = (gender == MALE) ? GLOB.facial_hair_styles_male_list : (gender == FEMALE) ? GLOB.facial_hair_styles_female_list : GLOB.facial_hair_styles_list
		if("underwear")
			L = (gender == MALE) ? GLOB.underwear_m : (gender == FEMALE) ? GLOB.underwear_f : GLOB.underwear_list
		if("undershirt")
			L = (gender == MALE) ? GLOB.undershirt_m : (gender == FEMALE) ? GLOB.undershirt_f : GLOB.undershirt_list
		if("socks")
			L = GLOB.socks_list
		if("bag")
			L = GLOB.backbaglist
		if("uplink_loc")
			L = GLOB.uplink_spawn_loc_list
		if("s_tone")
			L = GLOB.skin_tones
		if("color_ethereal")
			L = GLOB.color_list_ethereal
		if("tail_lizard")
			L = GLOB.tails_list_lizard
		if("tail_human")
			L = GLOB.tails_list_human
		if("snout")
			L = GLOB.snouts_list
		if("horns")
			L = GLOB.horns_list
		if("ears")
			L = GLOB.ears_list
		if("wings")
			L = GLOB.r_wings_list
		if("frills")
			L = GLOB.frills_list
		if("spines")
			L = GLOB.spines_list
		if("body_markings")
			L = GLOB.body_markings_list
		if("legs")
			L = GLOB.legs_list
		if("moth_wings")
			L = GLOB.moth_wings_list
		if("ipc_screen")
			L = GLOB.ipc_screens_list
		if("ai_core_icon")
			L = GLOB.ai_core_display_screens
		if("sec_dept")
			L = GLOB.security_depts_prefs
		if("ui")
			L = GLOB.available_ui_styles
		if("pda_style")
			L = GLOB.pda_styles
		if("ghostform")
			L = unlock_content ? GLOB.ghost_forms : null
		if("ghostorbit")
			L = unlock_content ? GLOB.ghost_orbits : null
		if("ghostaccs")
			L = list(GHOST_ACCS_FULL_NAME, GHOST_ACCS_DIR_NAME, GHOST_ACCS_NONE_NAME)
		if("ghostothers")
			L = list(GHOST_OTHERS_THEIR_SETTING_NAME, GHOST_OTHERS_DEFAULT_SPRITE_NAME, GHOST_OTHERS_SIMPLE_NAME)
		if("preferred_map")
			L = pref_map_choices()
	if(!L)
		return null
	var/list/names = list()
	for(var/option in L)
		names += "[option]"
	return names

/// Shown map name -> the map it means ("Default" means none)
/datum/preferences/proc/pref_map_choices()
	var/list/maplist = list()
	for(var/M in config.maplist)
		var/datum/map_config/VM = config.maplist[M]
		if(!VM.votable)
			continue
		maplist["[VM.map_name][VM.voteweight <= 0 ? " (disabled)" : ""]"] = VM.map_name
	maplist["Default[config.defaultmap ? " ([config.defaultmap.map_name])" : ""]"] = null
	return maplist

/// A choice made in the window: checked against what the old pop-up would have offered, then set as it did
/datum/preferences/proc/pref_set(mob/user, key, value)
	if(isnull(key) || isnull(value))
		return FALSE
	if(key in GLOB.preferences_custom_names)
		var/namedata = GLOB.preferences_custom_names[key]
		if(!value)
			if(namedata["allow_null"])
				custom_names[key] = get_default_name(key)
			return TRUE
		var/sanitized_name = reject_bad_name(value, namedata["allow_numbers"])
		if(!sanitized_name)
			to_chat(user, "<font color='red'>Invalid name. Your name should be at least 2 and at most [MAX_NAME_LEN] characters long. It may only contain the characters A-Z, a-z,[namedata["allow_numbers"] ? ",0-9," : ""] -, ' and .</font>")
			return TRUE
		custom_names[key] = sanitized_name
		return TRUE
	var/static/regex/hex_colour = regex("^#\[0-9a-fA-F\]{6}$")
	if(key in list("hair", "facial", "eyes", "mutant_color", "ooccolor", "asaycolor", "pda_color"))
		if(!hex_colour.Find(value))
			return FALSE
		switch(key)
			if("hair")
				hair_color = sanitize_hexcolor(value)
			if("facial")
				facial_hair_color = sanitize_hexcolor(value)
			if("eyes")
				eye_color = sanitize_hexcolor(value)
			if("mutant_color")
				// Same rule as the old picker: bright enough, unless it only colours parts
				if(value == "#000000")
					features["mcolor"] = pref_species.default_color
				else if((MUTCOLORS_PARTSONLY in pref_species.species_traits) || ReadHSV(RGBtoHSV(value))[3] >= ReadHSV("#7F7F7F")[3])
					features["mcolor"] = sanitize_hexcolor(value)
				else
					to_chat(user, "<span class='danger'>Invalid color. Your color is not bright enough.</span>")
			if("ooccolor")
				if(!(unlock_content || check_rights_for(user.client, R_ADMIN)))
					return FALSE
				ooccolor = value
			if("asaycolor")
				if(!user.client.holder)
					return FALSE
				asaycolor = value
			if("pda_color")
				pda_color = value
		return TRUE
	switch(key)
		if("name")
			var/new_name = reject_bad_name(value)
			if(new_name)
				real_name = new_name
			else
				to_chat(user, "<font color='red'>Invalid name. Your name should be at least 2 and at most [MAX_NAME_LEN] characters long. It may only contain the characters A-Z, a-z, -, ' and .</font>")
			return TRUE
		if("age")
			var/new_age = text2num(value)
			if(isnull(new_age))
				return FALSE
			age = clamp(round(new_age), AGE_MIN, AGE_MAX)
			return TRUE
		if("clientfps")
			var/desiredfps = text2num(value)
			if(isnull(desiredfps))
				return FALSE
			clientfps = clamp(round(desiredfps), 0, 1000)
			parent.fps = clientfps
			return TRUE
	var/list/options = pref_pick_options(key)
	if(!options || !(value in options))
		return FALSE
	switch(key)
		if("gender")
			var/new_gender = friendlyGenders[value]
			if(new_gender && new_gender != gender)
				gender = new_gender
				underwear = random_underwear(gender)
				undershirt = random_undershirt(gender)
				socks = random_socks()
				facial_hair_style = random_facial_hair_style(gender)
				hair_style = random_hair_style(gender)
		if("voice")
			voice = value
		if("species")
			var/newtype
			for(var/id in GLOB.roundstart_races)
				var/datum/species/S = GLOB.species_list[id]
				if(initial(S.name) == value)
					newtype = S
			if(!newtype)
				return FALSE
			pref_species = new newtype()
			// Same check as the old pop-up: the mutant colour still has to suit the new species
			var/temp_hsv = RGBtoHSV(features["mcolor"])
			if(features["mcolor"] == "#000" || (!(MUTCOLORS_PARTSONLY in pref_species.species_traits) && ReadHSV(temp_hsv)[3] < ReadHSV("#7F7F7F")[3]))
				features["mcolor"] = pref_species.default_color
		if("hair_style")
			hair_style = value
		if("facial_hair_style")
			facial_hair_style = value
		if("underwear")
			underwear = value
		if("undershirt")
			undershirt = value
		if("socks")
			socks = value
		if("bag")
			backbag = value
		if("uplink_loc")
			uplink_spawn_loc = value
		if("s_tone")
			skin_tone = value
		if("color_ethereal")
			features["ethcolor"] = GLOB.color_list_ethereal[value]
		if("ai_core_icon")
			preferred_ai_core_display = value
		if("sec_dept")
			prefered_security_department = value
		if("ui")
			UI_style = value
			if(parent && parent.mob && parent.mob.hud_used)
				parent.mob.hud_used.update_ui_style(ui_style2icon(UI_style))
		if("pda_style")
			pda_style = value
		if("ghostform")
			ghost_form = value
		if("ghostorbit")
			ghost_orbit = value
		if("ghostaccs")
			switch(value)
				if(GHOST_ACCS_FULL_NAME)
					ghost_accs = GHOST_ACCS_FULL
				if(GHOST_ACCS_DIR_NAME)
					ghost_accs = GHOST_ACCS_DIR
				if(GHOST_ACCS_NONE_NAME)
					ghost_accs = GHOST_ACCS_NONE
		if("ghostothers")
			switch(value)
				if(GHOST_OTHERS_THEIR_SETTING_NAME)
					ghost_others = GHOST_OTHERS_THEIR_SETTING
				if(GHOST_OTHERS_DEFAULT_SPRITE_NAME)
					ghost_others = GHOST_OTHERS_DEFAULT_SPRITE
				if(GHOST_OTHERS_SIMPLE_NAME)
					ghost_others = GHOST_OTHERS_SIMPLE
		if("preferred_map")
			preferred_map = pref_map_choices()[value]
		else // The body features
			features[key] = value
	return TRUE

// What the window shows

/datum/preferences/ui_data(mob/user)
	var/list/data = list()
	data["tab"] = current_tab
	data["previewMap"] = PREFS_PREVIEW_MAP
	data["hasPreview"] = !!preview_screen
	data["guest"] = IsGuestKey(user.key)
	data["noAccount"] = !path
	data["name"] = real_name
	data["slot"] = default_slot
	data["slots"] = pref_slot_names()
	data["quirksEnabled"] = CONFIG_GET(flag/roundstart_traits)
	data["plain"] = preview_plain
	data["dirty"] = prefs_dirty
	data["design"] = GLOB.lobby_design // the boarding pass look dresses this window as its personnel file
	data["dark"] = pass_dark
	data["maxSlots"] = max_save_slots
	switch(current_tab)
		if(0)
			data["sections"] = pref_character_sections(user)
			data["quirks"] = all_quirks
		if(1)
			data["sections"] = pref_game_sections(user)
		if(2)
			data["sections"] = pref_ooc_sections(user)
		if(3)
			data["keybinds"] = keybind_panel_data(user)
			data["hotkeys"] = hotkeys
		if(4)
			data["loadout"] = pref_loadout_data()
		if(PREFS_TAB_JOBS)
			data["jobs"] = pref_job_data(user)
		if(PREFS_TAB_QUIRKS)
			data["quirkList"] = pref_quirk_data()
	return data

/datum/preferences/proc/pref_slot_names()
	var/list/slots = list()
	if(!path)
		return slots
	var/savefile/S = new /savefile(path)
	if(!S)
		return slots
	for(var/i in 1 to max_save_slots)
		var/slot_name
		S.cd = "/character[i]"
		S["real_name"] >> slot_name
		slots += list(list("num" = i, "name" = slot_name || "Character [i]"))
	return slots

/datum/preferences/proc/pref_character_sections(mob/user)
	var/list/sections = list()
	var/list/rows = list()
	var/banned = is_banned_from(user.ckey, "Appearance")
	rows += list(pref_row("Name", real_name, "text", key = "name", extra = list("random" = list("preference" = "name", "task" = "random"))))
	rows += list(pref_toggle("Random name", be_random_name ? "Always" : "Never", "name", be_random_name))
	if(!(AGENDER in pref_species.species_traits))
		var/shown_gender = "Other"
		for(var/G in friendlyGenders)
			if(friendlyGenders[G] == gender)
				shown_gender = G
		rows += list(pref_pick("Gender", shown_gender, "gender"))
	rows += list(pref_row("Voice", voice || "Random", "pick", key = "voice", options = pref_pick_options("voice")))
	rows += list(pref_row("Age", age, "number", key = "age", extra = list("min" = AGE_MIN, "max" = AGE_MAX)))
	sections += list(pref_section("Identity", rows, list("note" = banned ? "You are banned from custom names and appearances: you can still adjust your characters, but you'll be randomised when you join." : null)))

	rows = list()
	for(var/custom_name_id in GLOB.preferences_custom_names)
		var/namedata = GLOB.preferences_custom_names[custom_name_id]
		rows += list(pref_row(namedata["pref_name"], custom_names[custom_name_id], "text", key = custom_name_id))
	rows += list(pref_pick("AI core display", preferred_ai_core_display, "ai_core_icon"))
	rows += list(pref_pick("Security department", prefered_security_department, "sec_dept"))
	sections += list(pref_section("Special names and jobs", rows))

	rows = list()
	rows += list(pref_pick("Species", pref_species.name, "species"))
	rows += list(pref_toggle("Random body", be_random_body ? "Always" : "Never", "all", be_random_body))
	if(pref_species.use_skintones)
		rows += list(pref_pick("Skin tone", skin_tone, "s_tone"))
	if((MUTCOLORS in pref_species.species_traits) || (MUTCOLORS_PARTSONLY in pref_species.species_traits))
		rows += list(pref_color("Mutant colour", features["mcolor"], "mutant_color"))
	if(istype(pref_species, /datum/species/ethereal))
		var/eth_name
		for(var/N in GLOB.color_list_ethereal)
			if(GLOB.color_list_ethereal[N] == features["ethcolor"])
				eth_name = N
		rows += list(pref_pick("Ethereal colour", eth_name, "color_ethereal"))
	if((EYECOLOR in pref_species.species_traits) && !(NOEYESPRITES in pref_species.species_traits))
		rows += list(pref_color("Eye colour", eye_color, "eyes"))
	rows += list(pref_pick("Underwear", underwear, "underwear"))
	rows += list(pref_pick("Undershirt", undershirt, "undershirt"))
	rows += list(pref_pick("Socks", socks, "socks"))
	rows += list(pref_pick("Backpack", backbag, "bag"))
	rows += list(pref_pick("Uplink spawn", uplink_spawn_loc, "uplink_loc"))
	sections += list(pref_section("Body", rows, list("random" = list("preference" = "all", "task" = "random"))))

	if(HAIR in pref_species.species_traits)
		rows = list()
		rows += list(pref_row("Hair style", hair_style, "pick", key = "hair_style", options = pref_pick_options("hair_style"), extra = list(
			"prev" = list("preference" = "previous_hair_style", "task" = "input"),
			"next" = list("preference" = "next_hair_style", "task" = "input"))))
		rows += list(pref_color("Hair colour", hair_color, "hair"))
		rows += list(pref_row("Facial hair", facial_hair_style, "pick", key = "facial_hair_style", options = pref_pick_options("facial_hair_style"), extra = list(
			"prev" = list("preference" = "previous_facehair_style", "task" = "input"),
			"next" = list("preference" = "next_facehair_style", "task" = "input"))))
		rows += list(pref_color("Facial hair colour", facial_hair_color, "facial"))
		sections += list(pref_section("Hair", rows))

	rows = list()
	var/list/feature_names = list("tail_lizard" = "Tail", "snout" = "Snout", "horns" = "Horns", "frills" = "Frills", "spines" = "Spines",
		"body_markings" = "Body markings", "legs" = "Legs", "moth_wings" = "Moth wings", "tail_human" = "Tail", "ears" = "Ears")
	for(var/feature in feature_names)
		if(feature in pref_species.default_features)
			rows += list(pref_pick(feature_names[feature], features[feature], feature))
	if("ipc_screen" in pref_species.mutant_bodyparts)
		rows += list(pref_pick("Screen", features["ipc_screen"], "ipc_screen"))
	if(CONFIG_GET(flag/join_with_mutant_humans) && ("wings" in pref_species.default_features) && GLOB.r_wings_list.len > 1)
		rows += list(pref_pick("Wings", features["wings"], "wings"))
	if(length(rows))
		sections += list(pref_section("Features", rows))
	return sections

/datum/preferences/proc/pref_game_sections(mob/user)
	var/list/sections = list()
	var/list/rows = list()
	rows += list(pref_pick("UI style", UI_style, "ui"))
	rows += list(pref_toggle("Overhead chat", overhead_chat ? "Enabled" : "Disabled", "overheadchat", overhead_chat))
	rows += list(pref_toggle("tgui monitors", tgui_lock ? "Primary" : "All", "tgui_lock", tgui_lock))
	rows += list(pref_toggle("tgui style", tgui_fancy ? "Fancy" : "No frills", "tgui_fancy", tgui_fancy))
	rows += list(pref_toggle("Action buttons", buttons_locked ? "Locked in place" : "Unlocked", "action_buttons", buttons_locked))
	rows += list(pref_toggle("Hotkey mode", hotkeys ? "Hotkeys" : "Default", "hotkeys", hotkeys))
	rows += list(pref_color("PDA colour", pda_color, "pda_color"))
	rows += list(pref_pick("PDA style", pda_style, "pda_style"))
	rows += list(pref_toggle("Income updates", (chat_toggles & CHAT_BANKCARD) ? "Allowed" : "Muted", "income_pings", chat_toggles & CHAT_BANKCARD))
	sections += list(pref_section("General", rows))

	rows = list()
	rows += list(pref_row("FPS", clientfps, "number", key = "clientfps", extra = list("min" = 0, "max" = 1000, "hint" = "0 follows the server ([world.fps])")))
	var/parallax_name = "High"
	switch(parallax)
		if(PARALLAX_LOW)
			parallax_name = "Low"
		if(PARALLAX_MED)
			parallax_name = "Medium"
		if(PARALLAX_INSANE)
			parallax_name = "Insane"
		if(PARALLAX_DISABLE)
			parallax_name = "Disabled"
	rows += list(pref_row("Parallax (fancy space)", parallax_name, "info", extra = list(
		"prev" = list("preference" = "parallaxdown"),
		"next" = list("preference" = "parallaxup"))))
	rows += list(pref_toggle("Ambient occlusion", ambientocclusion ? "Enabled" : "Disabled", "ambientocclusion", ambientocclusion))
	rows += list(pref_toggle("Fit viewport", auto_fit_viewport ? "Auto" : "Manual", "auto_fit_viewport", auto_fit_viewport))
	if(CONFIG_GET(string/default_view) != CONFIG_GET(string/default_view_square))
		rows += list(pref_toggle("Widescreen", widescreenpref ? "Enabled ([CONFIG_GET(string/default_view)])" : "Disabled ([CONFIG_GET(string/default_view_square)])", "widescreenpref", widescreenpref))
	if(CONFIG_GET(flag/maprotation) && CONFIG_GET(flag/preference_map_voting))
		var/shown_map = "Default[config.defaultmap ? " ([config.defaultmap.map_name])" : ""]"
		var/list/choices = pref_map_choices()
		for(var/N in choices)
			if(preferred_map && choices[N] == preferred_map)
				shown_map = N
		rows += list(pref_pick("Preferred map", shown_map, "preferred_map"))
	sections += list(pref_section("Display", rows))

	rows = list()
	rows += list(pref_toggle("Ghost ears", (chat_toggles & CHAT_GHOSTEARS) ? "All speech" : "Nearest creatures", "ghost_ears", chat_toggles & CHAT_GHOSTEARS))
	rows += list(pref_toggle("Ghost radio", (chat_toggles & CHAT_GHOSTRADIO) ? "All messages" : "No messages", "ghost_radio", chat_toggles & CHAT_GHOSTRADIO))
	rows += list(pref_toggle("Ghost sight", (chat_toggles & CHAT_GHOSTSIGHT) ? "All emotes" : "Nearest creatures", "ghost_sight", chat_toggles & CHAT_GHOSTSIGHT))
	rows += list(pref_toggle("Ghost whispers", (chat_toggles & CHAT_GHOSTWHISPER) ? "All speech" : "Nearest creatures", "ghost_whispers", chat_toggles & CHAT_GHOSTWHISPER))
	rows += list(pref_toggle("Ghost PDA", (chat_toggles & CHAT_GHOSTPDA) ? "All messages" : "Nearest creatures", "ghost_pda", chat_toggles & CHAT_GHOSTPDA))
	if(unlock_content)
		rows += list(pref_pick("Ghost form", ghost_form, "ghostform"))
		rows += list(pref_pick("Ghost orbit", ghost_orbit, "ghostorbit"))
	var/accs_name = GHOST_ACCS_FULL_NAME
	switch(ghost_accs)
		if(GHOST_ACCS_DIR)
			accs_name = GHOST_ACCS_DIR_NAME
		if(GHOST_ACCS_NONE)
			accs_name = GHOST_ACCS_NONE_NAME
	rows += list(pref_pick("Ghost accessories", accs_name, "ghostaccs"))
	var/others_name = GHOST_OTHERS_THEIR_SETTING_NAME
	switch(ghost_others)
		if(GHOST_OTHERS_DEFAULT_SPRITE)
			others_name = GHOST_OTHERS_DEFAULT_SPRITE_NAME
		if(GHOST_OTHERS_SIMPLE)
			others_name = GHOST_OTHERS_SIMPLE_NAME
	rows += list(pref_pick("Ghosts of others", others_name, "ghostothers"))
	sections += list(pref_section("Ghost", rows))

	rows = list()
	var/antag_banned = is_banned_from(user.ckey, ROLE_SYNDICATE)
	if(antag_banned)
		be_special = list()
	for(var/i in GLOB.special_roles)
		if(is_banned_from(user.ckey, list(i, CATBAN, CLUWNEBAN)))
			rows += list(pref_row("Be [i]", "BANNED", "toggle", list("bancheck" = i), extra = list("bad" = TRUE)))
			continue
		var/days_remaining = null
		if(ispath(GLOB.special_roles[i]) && CONFIG_GET(flag/use_age_restriction_for_jobs))
			var/mode_path = GLOB.special_roles[i]
			var/datum/game_mode/temp_mode = new mode_path
			days_remaining = temp_mode.get_remaining_days(user.client)
		if(days_remaining)
			rows += list(pref_row("Be [i]", "In [days_remaining] days", "info", extra = list("bad" = TRUE)))
		else
			rows += list(pref_row("Be [i]", (i in be_special) ? "Yes" : "No", "toggle", list("preference" = "be_special", "be_special_type" = i), extra = list("on" = (i in be_special))))
	rows += list(pref_toggle("Midround antagonist", (toggles & MIDROUND_ANTAG) ? "Yes" : "No", "allow_midround_antag", toggles & MIDROUND_ANTAG))
	sections += list(pref_section("Special roles", rows, list("note" = antag_banned ? "You are banned from antagonist roles." : null)))
	return sections

/datum/preferences/proc/pref_ooc_sections(mob/user)
	var/list/sections = list()
	var/list/rows = list()
	rows += list(pref_toggle("Window flashing", windowflashing ? "Enabled" : "Disabled", "winflash", windowflashing))
	rows += list(pref_toggle("Admin MIDIs", (toggles & SOUND_MIDI) ? "Play" : "Don't play", "hear_midis", toggles & SOUND_MIDI))
	rows += list(pref_toggle("Lobby music", (toggles & SOUND_LOBBY) ? "Play" : "Don't play", "lobby_music", toggles & SOUND_LOBBY))
	rows += list(pref_toggle("Pull requests", (chat_toggles & CHAT_PULLR) ? "Shown" : "Hidden", "pull_requests", chat_toggles & CHAT_PULLR))
	if(unlock_content)
		rows += list(pref_toggle("BYOND membership", (toggles & MEMBER_PUBLIC) ? "Public" : "Hidden", "publicity", toggles & MEMBER_PUBLIC))
	if(unlock_content || check_rights_for(user.client, R_ADMIN))
		rows += list(pref_color("OOC colour", ooccolor || GLOB.normal_ooc_colour, "ooccolor"))
	sections += list(pref_section("OOC", rows))

	rows = list()
	rows += list(pref_toggle("Text-to-speech", (hippie_toggles & SOUND_TTS) ? "Play" : "Don't play", "hear_tts", hippie_toggles & SOUND_TTS))
	rows += list(pref_toggle("Footsteps", (hippie_toggles & SOUND_FOOTSTEPS) ? "Play" : "Don't play", "hear_footsteps", hippie_toggles & SOUND_FOOTSTEPS))
	rows += list(pref_toggle("AI vox", (hippie_toggles & SOUND_VOX) ? "Play" : "Don't play", "hear_vox", hippie_toggles & SOUND_VOX))
	rows += list(pref_toggle("Screentips", (hippie_toggles & SCREENTIPS_DISABLED) ? "Off" : "On", "screentips", !(hippie_toggles & SCREENTIPS_DISABLED)))
	sections += list(pref_section("Sounds and hints", rows))

	if(user.client.holder)
		rows = list()
		rows += list(pref_toggle("Adminhelp sounds", (toggles & SOUND_ADMINHELP) ? "Play" : "Don't play", "hear_adminhelps", toggles & SOUND_ADMINHELP))
		rows += list(pref_toggle("Prayer sounds", (toggles & SOUND_PRAYERS) ? "Play" : "Don't play", "hear_prayers", toggles & SOUND_PRAYERS))
		rows += list(pref_toggle("Announce login", (toggles & ANNOUNCE_LOGIN) ? "Yes" : "No", "announce_login", toggles & ANNOUNCE_LOGIN))
		rows += list(pref_toggle("Combo HUD lighting", (toggles & COMBOHUD_LIGHTING) ? "Full-bright" : "No change", "combohud_lighting", toggles & COMBOHUD_LIGHTING))
		rows += list(pref_toggle("Dead chat", (chat_toggles & CHAT_DEAD) ? "Shown" : "Hidden", "toggle_dead_chat", chat_toggles & CHAT_DEAD))
		rows += list(pref_toggle("Radio messages", (chat_toggles & CHAT_RADIO) ? "Shown" : "Hidden", "toggle_radio_chatter", chat_toggles & CHAT_RADIO))
		rows += list(pref_toggle("Prayers", (chat_toggles & CHAT_PRAYER) ? "Shown" : "Hidden", "toggle_prayers", chat_toggles & CHAT_PRAYER))
		if(CONFIG_GET(flag/allow_admin_asaycolor))
			rows += list(pref_color("ASAY colour", asaycolor || "#FF4500", "asaycolor"))
		sections += list(pref_section("Admin", rows))

		rows = list()
		if(CONFIG_GET(flag/auto_deadmin_players))
			rows += list(pref_row("Always deadmin", "Forced", "info"))
		else
			rows += list(pref_toggle("Always deadmin", (toggles & DEADMIN_ALWAYS) ? "Yes" : "No", "toggle_deadmin_always", toggles & DEADMIN_ALWAYS))
			if(!(toggles & DEADMIN_ALWAYS))
				var/list/deadmins = list("As antagonist" = list(/datum/config_entry/flag/auto_deadmin_antagonists, DEADMIN_ANTAGONIST, "toggle_deadmin_antag"),
					"As command" = list(/datum/config_entry/flag/auto_deadmin_heads, DEADMIN_POSITION_HEAD, "toggle_deadmin_head"),
					"As security" = list(/datum/config_entry/flag/auto_deadmin_security, DEADMIN_POSITION_SECURITY, "toggle_deadmin_security"),
					"As silicon" = list(/datum/config_entry/flag/auto_deadmin_silicons, DEADMIN_POSITION_SILICON, "toggle_deadmin_silicon"))
				for(var/label in deadmins)
					var/list/D = deadmins[label]
					if(config.Get(D[1]))
						rows += list(pref_row(label, "Forced", "info"))
					else
						rows += list(pref_toggle(label, (toggles & D[2]) ? "Deadmin" : "Keep admin", D[3], toggles & D[2]))
		sections += list(pref_section("Deadmin while playing", rows))
	return sections

/datum/preferences/proc/pref_keybind_data()
	var/list/user_binds = list()
	for(var/key in key_bindings)
		for(var/kb_name in key_bindings[key])
			user_binds[kb_name] += list(key)
	var/list/categories = list()
	var/list/order = list()
	for(var/name in GLOB.keybindings_by_name)
		var/datum/keybinding/kb = GLOB.keybindings_by_name[name]
		if(!categories[kb.category])
			categories[kb.category] = list()
			order += kb.category
		var/list/defaults = hotkeys ? kb.hotkey_keys : kb.classic_keys
		var/list/keys = user_binds[kb.name] || list()
		categories[kb.category] += list(list(
			"name" = kb.name,
			"fullName" = kb.full_name,
			"keys" = keys,
			"defaults" = LAZYLEN(defaults) ? defaults.Join(", ") : null,
			"canAdd" = length(keys) && length(keys) < MAX_KEYS_PER_KEYBIND,
		))
	var/list/out = list()
	for(var/category in order)
		out += list(list("name" = category, "binds" = categories[category]))
	return out

/datum/preferences/proc/pref_loadout_data()
	if(!gear_tab)
		gear_tab = GLOB.loadout_items[1]
	var/list/items = list()
	for(var/j in GLOB.loadout_items[gear_tab])
		var/datum/gear/G = GLOB.loadout_items[gear_tab][j]
		items += list(list(
			"name" = j,
			"cost" = G.cost,
			"desc" = G.description,
			"restricted" = islist(G.restricted_roles) && length(G.restricted_roles) ? G.restricted_roles.Join(", ") : null,
			"chosen" = (G.type in chosen_gear),
		))
	var/list/categories = list()
	for(var/i in GLOB.loadout_items)
		categories += i
	return list("points" = gear_points, "category" = gear_tab, "categories" = categories, "items" = items)

/datum/preferences/proc/pref_job_data(mob/user)
	var/list/out = list()
	if(!SSjob || !length(SSjob.occupations))
		return list("ready" = FALSE)
	var/list/jobs = list()
	var/overflow = SSjob.overflow_role
	for(var/datum/job/job in sortList(SSjob.occupations, /proc/cmp_job_display_asc))
		var/rank = job.title
		var/list/J = list("title" = rank, "color" = job.selection_color, "head" = (rank in GLOB.command_positions) || rank == "AI", "overflow" = rank == overflow)
		if(is_banned_from(user.ckey, rank))
			J["locked"] = "Banned"
			J["link"] = list("bancheck" = rank)
		else if(is_banned_from(user.ckey, list(CLUWNEBAN, CATBAN, CRABBAN)) && rank != overflow)
			J["locked"] = "Banned"
			J["link"] = list("jobbancheck" = rank)
		else if(job.required_playtime_remaining(user.client))
			J["locked"] = "[get_exp_format(job.required_playtime_remaining(user.client))] as [job.get_exp_req_type()]"
		else if(!job.player_old_enough(user.client))
			J["locked"] = "In [job.available_in_days(user.client)] days"
		else if(job_preferences[overflow] == JP_LOW && rank != overflow && !is_banned_from(user.ckey, overflow))
			J["locked"] = "[overflow] only"
			J["soft"] = TRUE
		else
			J["level"] = job_preferences[rank] || 0
		jobs += list(J)
	out["ready"] = TRUE
	out["jobs"] = jobs
	out["overflow"] = overflow
	var/message = "Be an [overflow] if preferences unavailable"
	if(joblessrole == BERANDOMJOB)
		message = "Get a random job if preferences unavailable"
	else if(joblessrole == RETURNTOLOBBY)
		message = "Return to the lobby if preferences unavailable"
	out["jobless"] = message
	return out

/datum/preferences/proc/pref_quirk_data()
	if(!SSquirks || !length(SSquirks.quirks))
		return list("ready" = FALSE)
	var/list/quirks = list()
	for(var/V in SSquirks.quirks)
		var/datum/quirk/T = SSquirks.quirks[V]
		var/quirk_name = initial(T.name)
		var/list/Q = list("name" = quirk_name, "desc" = initial(T.desc), "value" = initial(T.value), "has" = (quirk_name in all_quirks))
		if(initial(T.mood_quirk) && CONFIG_GET(flag/disable_human_mood))
			Q["locked"] = "Mood is disabled"
			all_quirks -= quirk_name
			Q["has"] = FALSE
		quirks += list(Q)
	return list("ready" = TRUE, "quirks" = quirks, "balance" = GetQuirkBalance(), "positive" = length(positive_quirks), "maxPositive" = MAX_QUIRKS)

#undef PREFS_PREVIEW_MAP
#undef PREFS_TAB_JOBS
#undef PREFS_TAB_QUIRKS

/// As the old preview, but in plain clothes when the window's toggle says so (code/modules/mob/dead/new_player/preferences_setup.dm)
/datum/preferences/update_preview_icon()
	var/datum/job/previewJob
	var/highest_pref = 0
	if(!preview_plain)
		for(var/job in job_preferences)
			if(job_preferences[job] > highest_pref)
				previewJob = SSjob.GetJob(job)
				highest_pref = job_preferences[job]
	if(previewJob)
		if(istype(previewJob, /datum/job/ai))
			parent.show_character_previews(image('icons/mob/ai.dmi', icon_state = resolve_ai_icon(preferred_ai_core_display), dir = SOUTH))
			return
		if(istype(previewJob, /datum/job/cyborg))
			parent.show_character_previews(image('icons/mob/robots.dmi', icon_state = "robot", dir = SOUTH))
			return
	var/mob/living/carbon/human/dummy/mannequin = generate_or_wait_for_human_dummy(DUMMY_HUMAN_SLOT_PREFERENCES)
	copy_to(mannequin)
	if(previewJob)
		mannequin.job = previewJob.title
		previewJob.equip(mannequin, TRUE, preference_source = parent)
	COMPILE_OVERLAYS(mannequin)
	parent.show_character_previews(new /mutable_appearance(mannequin))
	unset_busy_human_dummy(DUMMY_HUMAN_SLOT_PREFERENCES)
