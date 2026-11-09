// hippie -- more admin windows designed for tgui (interfaces/AdminFun.js, and the newscaster's own window): the admins' newscaster
// (Access Newscaster Network: the security unit's window, from anywhere, signed as Nanotrasen), dynamic mode (its options before the
// round, the live panel and the threat log in one window), Trigger Event (every event by kind, with what stops it running on its own),
// the reagent container and grenade spawner (Spawn reagent container), and a sound emitter's settings. The old procs open these; the
// rights checks, limits and logs are the old ones.

// ---------------------------------------------------------------------------------------------
// The admins' newscaster
// ---------------------------------------------------------------------------------------------

GLOBAL_DATUM(admin_newscaster, /obj/machinery/newscaster/admin_desk)

/datum/admins/access_news_network()
	if(!check_rights(R_ADMIN))
		return
	if(!GLOB.admin_newscaster)
		GLOB.admin_newscaster = new
	GLOB.admin_newscaster.ui_interact(usr)

/// Nowhere on the map: a security unit the admins' window runs on, posting as their signature, its channels and wanted issues
/// flagged as Nanotrasen's (no one can censor them), as the old admin newscaster's were
/obj/machinery/newscaster/admin_desk
	name = "admin newscaster"
	securityCaster = TRUE
	admin_desk = TRUE
	use_power = NO_POWER_USE
	paper_remaining = 0

/obj/machinery/newscaster/admin_desk/Initialize(mapload)
	. = ..()
	GLOB.allCasters -= src // nothing to alert or light up

/obj/machinery/newscaster/admin_desk/scan_user(mob/user)
	scanned_user = user?.client?.holder ? "[user.client.holder.admin_signature]" : "Unknown"

/obj/machinery/newscaster/admin_desk/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.admin_state)
	if(!user?.client?.holder)
		return
	scan_user(user)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "newscaster", "Admin newscaster", 600, 680, master_ui, GLOB.admin_state)
		ui.open()

/// The old Topic's buttons, done here: it wants you next to the unit
/obj/machinery/newscaster/admin_desk/news_topic(list/href_list)
	var/datum/newscaster/feed_network/network = GLOB.news_network
	if(href_list["set_channel_lock"])
		c_locked = !c_locked
	else if(href_list["set_attachment"])
		AttachPhoto(usr)
	else if(href_list["set_comment"])
		allow_comments ^= 1
	else if(href_list["submit_new_message"])
		if(msg == "" || msg == "\[REDACTED\]" || scanned_user == "Unknown" || channel_name == "")
			screen = 6
		else
			network.SubmitArticle("<font face=\"[PEN_FONT]\">[parsemarkdown(msg, usr)]</font>", scanned_user, channel_name, picture, 1, allow_comments)
			SSblackbox.record_feedback("amount", "newscaster_stories", 1)
			log_admin("[key_name(usr)] submitted a feed story to channel: [channel_name] as [scanned_user].")
			screen = 4
			msg = ""
	else if(href_list["create_channel"])
		screen = 2
	else if(href_list["create_feed_story"])
		screen = 3
	else if(href_list["menu_wanted"])
		if(network.wanted_issue.active)
			channel_name = network.wanted_issue.criminal
			msg = network.wanted_issue.body
		screen = 14
	else if(href_list["view_wanted"])
		screen = 18
	else if(href_list["view"])
		screen = 1
	else if(href_list["setScreen"])
		screen = text2num(href_list["setScreen"])
		if(screen == 0)
			msg = ""
			c_locked = 0
			channel_name = ""
			viewing_channel = null
	else if(href_list["show_channel"])
		var/datum/newscaster/feed_channel/FC = locate(href_list["show_channel"]) in network.network_channels
		if(FC)
			viewing_channel = FC
			screen = 9

// ---------------------------------------------------------------------------------------------
// Dynamic mode: the options before the round, the live panel and the threat log
// ---------------------------------------------------------------------------------------------

/datum/admins/dynamic_mode_options(mob/user)
	open_admin_tool("dynamic", /datum/admin_tool_window/dynamic, list("tab" = "options"))

/datum/game_mode/dynamic/admin_panel()
	usr?.client?.holder?.open_admin_tool("dynamic", /datum/admin_tool_window/dynamic, list("tab" = "round"))

/datum/game_mode/dynamic/show_threatlog(mob/admin)
	if(!check_rights(R_ADMIN))
		return
	usr?.client?.holder?.open_admin_tool("dynamic", /datum/admin_tool_window/dynamic, list("tab" = "log"))

/datum/admin_tool_window/dynamic
	interface = "admin_dynamic"
	title = "Dynamic mode"
	width = 560
	height = 620
	var/tab = "options"
	/// What the last setting did, shown at the top: list(text, good)
	var/list/notice

/datum/admin_tool_window/dynamic/setup(list/arguments)
	if(arguments?["tab"] in list("options", "round", "log"))
		tab = arguments["tab"]

/datum/admin_tool_window/dynamic/proc/running_mode()
	var/datum/game_mode/dynamic/D = SSticker.mode
	return istype(D) ? D : null

/datum/admin_tool_window/dynamic/ui_data(mob/user)
	. = list("tab" = tab, "notice" = notice)
	.["is_dynamic"] = GLOB.master_mode == "dynamic"
	.["started"] = !!SSticker.mode
	.["options"] = list(
		"forced_extended" = GLOB.dynamic_forced_extended,
		"no_stacking" = GLOB.dynamic_no_stacking,
		"classic_secret" = GLOB.dynamic_classic_secret,
		"forced_threat" = GLOB.dynamic_forced_threat_level,
		"high_pop_limit" = GLOB.dynamic_high_pop_limit,
		"stacking_limit" = GLOB.dynamic_stacking_limit,
		"curve_centre" = GLOB.dynamic_curve_centre,
		"curve_width" = GLOB.dynamic_curve_width,
		"latejoin_min" = GLOB.dynamic_latejoin_delay_min / (1 MINUTES),
		"latejoin_max" = GLOB.dynamic_latejoin_delay_max / (1 MINUTES),
		"midround_min" = GLOB.dynamic_midround_delay_min / (1 MINUTES),
		"midround_max" = GLOB.dynamic_midround_delay_max / (1 MINUTES),
	)
	var/datum/game_mode/dynamic/D = running_mode()
	if(!D)
		return
	var/list/round = list()
	round["ref"] = REF(D)
	round["threat_level"] = D.threat_level
	round["threat"] = D.threat
	round["peaceful"] = D.peaceful_percentage
	var/list/executed = list()
	for(var/datum/dynamic_ruleset/DR in D.executed_rules)
		executed += list(list("name" = DR.name, "type" = DR.ruletype))
	round["executed"] = executed
	round["injection_chance"] = D.get_injection_chance(TRUE)
	round["latejoin_in"] = max(0, D.latejoin_injection_cooldown - world.time) / 10
	round["midround_in"] = max(0, D.midround_injection_cooldown - world.time) / 10
	.["round"] = round
	var/list/log = list()
	for(var/entry in D.threat_log)
		if(istext(entry))
			log += comm_plain_text(entry)
	.["log"] = log

/datum/admin_tool_window/dynamic/ui_act(action, list/params)
	if(..())
		return
	notice = null
	switch(action)
		if("tab")
			if(params["tab"] in list("options", "round", "log"))
				tab = params["tab"]
			return TRUE
		if("toggle")
			// Midround as well as before: the old links only asked for dynamic
			if(GLOB.master_mode != "dynamic")
				notice = list("The game mode has to be dynamic.", FALSE)
				return TRUE
			var/option = params["option"]
			switch(option)
				if("forced_extended")
					GLOB.dynamic_forced_extended = !GLOB.dynamic_forced_extended
					dynamic_option_set("forced_extended", GLOB.dynamic_forced_extended)
				if("no_stacking")
					GLOB.dynamic_no_stacking = !GLOB.dynamic_no_stacking
					dynamic_option_set("no_stacking", GLOB.dynamic_no_stacking)
				if("classic_secret")
					GLOB.dynamic_classic_secret = !GLOB.dynamic_classic_secret
					dynamic_option_set("classic_secret", GLOB.dynamic_classic_secret)
			return TRUE
		if("set")
			set_option(params["option"], text2num("[params["value"]]"))
			return TRUE
	var/datum/game_mode/dynamic/D = running_mode()
	if(!D)
		return
	switch(action)
		if("adjust_threat")
			var/amount = text2num("[params["amount"]]")
			if(!amount)
				return
			if(amount > 0)
				D.create_threat(amount)
			else
				D.spend_threat(-amount)
			log_admin("[key_name(usr)] adjusted dynamic mode's threat by [amount] (now [D.threat]).")
			message_admins("[key_name_admin(usr)] adjusted dynamic mode's threat by [amount] (now [D.threat]).")
		if("inject_late")
			D.latejoin_injection_cooldown = 0
			D.forced_injection = TRUE
			message_admins("[key_name(usr)] forced a latejoin injection.", 1)
		if("inject_mid")
			D.midround_injection_cooldown = 0
			D.forced_injection = TRUE
			message_admins("[key_name(usr)] forced a midround injection.", 1)
		if("vv")
			usr.client.debug_variables(D)
	return TRUE

/proc/dynamic_option_set(name, value)
	log_admin("[key_name(usr)] set '[name]' to [value].")
	message_admins("[key_name(usr)] set '[name]' to [value].")

/// One of the number settings, with the limits topic.dm's prompts had. Those before the round can't change once it's started.
/datum/admin_tool_window/dynamic/proc/set_option(option, value)
	if(GLOB.master_mode != "dynamic")
		notice = list("The game mode has to be dynamic.", FALSE)
		return
	if(isnull(value))
		return
	var/static/list/midround_ok = list("stacking_limit")
	if(SSticker.mode && !(option in midround_ok))
		notice = list("The game has already started.", FALSE)
		return
	switch(option)
		if("stacking_limit")
			GLOB.dynamic_stacking_limit = value
		if("high_pop_limit")
			if(value < 0)
				notice = list("Only positive values.", FALSE)
				return
			GLOB.dynamic_high_pop_limit = value
		if("forced_threat")
			if(value > 100)
				notice = list("The most it can be is 100.", FALSE)
				return
			GLOB.dynamic_forced_threat_level = value
		if("curve_centre")
			if(value < -5 || value > 5)
				notice = list("Only values from -5 to 5.", FALSE)
				return
			GLOB.dynamic_curve_centre = value
		if("curve_width")
			if(value < 0.5 || value > 4)
				notice = list("Only values from 0.5 to 4.", FALSE)
				return
			GLOB.dynamic_curve_width = value
		if("latejoin_min", "latejoin_max", "midround_min", "midround_max")
			if(value <= 0)
				notice = list("It can't be zero or lower.", FALSE)
				return
			var/list/delays = list("latejoin_min" = GLOB.dynamic_latejoin_delay_min, "latejoin_max" = GLOB.dynamic_latejoin_delay_max, \
				"midround_min" = GLOB.dynamic_midround_delay_min, "midround_max" = GLOB.dynamic_midround_delay_max)
			delays[option] = value MINUTES
			if(delays["latejoin_min"] > delays["latejoin_max"] || delays["midround_min"] > delays["midround_max"])
				notice = list("The minimum must be lower than the maximum.", FALSE)
				return
			GLOB.dynamic_latejoin_delay_min = delays["latejoin_min"]
			GLOB.dynamic_latejoin_delay_max = delays["latejoin_max"]
			GLOB.dynamic_midround_delay_min = delays["midround_min"]
			GLOB.dynamic_midround_delay_max = delays["midround_max"]
		else
			return
	dynamic_option_set(option, value)
	notice = list("Set.", TRUE)

// ---------------------------------------------------------------------------------------------
// Trigger Event
// ---------------------------------------------------------------------------------------------

/datum/admins/forceEvent()
	if(!check_rights(R_FUN))
		return
	open_admin_tool("events", /datum/admin_tool_window/events)

/datum/admin_tool_window/events
	interface = "admin_events"
	title = "Trigger Event"
	width = 640
	height = 640
	rights = R_FUN

/datum/admin_tool_window/events/ui_data(mob/user)
	var/players = length(GLOB.alive_mob_list & GLOB.player_list) // close to what SSevents counts
	var/list/events = list()
	for(var/datum/round_event_control/E in SSevents.control)
		var/kind = E.holidayID ? "holiday" : (E.wizardevent ? "wizard" : "station")
		var/list/stops = list()
		if(!E.max_occurrences)
			stops += "never on its own"
		else if(E.occurrences >= E.max_occurrences)
			stops += "ran its [E.max_occurrences] times"
		if(E.earliest_start >= world.time - SSticker.round_start_time)
			stops += "not before [round(E.earliest_start / (1 MINUTES))] min"
		if(players < E.min_players)
			stops += "needs [E.min_players] players"
		if(E.holidayID && !(E.holidayID in SSevents.holidays))
			stops += "not [E.holidayID]"
		events += list(list("ref" = REF(E), "name" = E.name, "kind" = kind, "weight" = E.weight, "ran" = E.occurrences, \
			"max" = E.max_occurrences, "stops" = stops))
	return list("events" = events, "players" = players, "started" = SSticker.HasRoundStarted())

/datum/admin_tool_window/events/ui_act(action, list/params)
	if(..())
		return
	if(action != "run")
		return
	var/datum/round_event_control/E = locate(params["ref"]) in SSevents.control
	if(E)
		holder.page_holder_link(list("forceevent" = REF(E)))
	return TRUE

// ---------------------------------------------------------------------------------------------
// Spawn reagent container (beakerpanel.dm)
// ---------------------------------------------------------------------------------------------

/datum/admins/beaker_panel()
	if(!check_rights())
		return
	open_admin_tool("beakers", /datum/admin_tool_window/beakers)

/datum/admin_tool_window/beakers
	interface = "admin_beakers"
	title = "Spawn reagent container"
	width = 720
	height = 640
	rights = R_SPAWN

/datum/admin_tool_window/beakers/ui_static_data(mob/user)
	var/list/reagents = list()
	for(var/path in subtypesof(/datum/reagent))
		var/datum/reagent/R = path
		reagents += list(list("path" = "[path]", "name" = initial(R.name)))
	var/list/containers = list()
	for(var/path in subtypesof(/obj/item/reagent_containers))
		var/obj/item/reagent_containers/C = path
		containers += list(list("path" = "[path]", "name" = initial(C.name), "volume" = initial(C.volume)))
	return list("reagents" = reagents, "containers" = containers)

/// A container as the page sends it: its path and reagents ({reagent, volume}), checked to be real types
/datum/admin_tool_window/beakers/proc/container_data(list/sent)
	if(!islist(sent))
		return
	var/path = text2path("[sent["container"]]")
	if(!ispath(path, /obj/item/reagent_containers))
		return
	var/list/reagents = list()
	for(var/list/item in sent["reagents"])
		var/reagent = text2path("[item["reagent"]]")
		var/volume = text2num("[item["volume"]]")
		if(ispath(reagent, /datum/reagent) && volume > 0)
			reagents += list(list("reagent" = "[reagent]", "volume" = "[min(volume, 10000)]"))
	return list("container" = "[path]", "reagents" = reagents)

/datum/admin_tool_window/beakers/ui_act(action, list/params)
	if(..())
		return
	switch(action)
		if("spawn_container")
			var/list/data = container_data(params["container"])
			if(data)
				holder.beaker_panel_act(list("beakerpanel" = "spawncontainer", "container" = json_encode(data)))
		if("spawn_grenade")
			var/list/first = container_data(params["first"])
			var/list/second = container_data(params["second"])
			if(first && second)
				var/timer = clamp(text2num("[params["timer"]]") || 5, 1, 300)
				holder.beaker_panel_act(list("beakerpanel" = "spawngrenade", "containers" = json_encode(list(first, second)), \
					"grenadetype" = "normal", "grenadedata" = json_encode(list("grenade-timer" = "[timer * 10]"))))
	return TRUE

// ---------------------------------------------------------------------------------------------
// A sound emitter's settings (sound_emitter.dm)
// ---------------------------------------------------------------------------------------------

/obj/effect/sound_emitter/edit_emitter(mob/user)
	ui_interact(user)

/obj/effect/sound_emitter/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "admin_sound_emitter", "Sound emitter", 380, 420, master_ui, GLOB.always_state)
		ui.open()

/// BYOND's file picker, as the old link opened it (it waits for the upload)
/obj/effect/sound_emitter/proc/pick_sound_file(mob/user)
	var/new_file = input(user, "Choose a sound file.", "Sound Emitter") as null|sound
	if(!new_file || !check_rights_for(user.client, R_SOUND))
		return
	sound_file = new_file
	to_chat(user, "<span class='notice'>New sound file set to [sound_file].</span>")
	SStgui.update_uis(src)

/obj/effect/sound_emitter/ui_status(mob/user, datum/ui_state/state)
	return check_rights_for(user.client, R_SOUND) ? UI_INTERACTIVE : UI_CLOSE

/obj/effect/sound_emitter/ui_data(mob/user)
	return list("label" = maptext, "file" = sound_file ? "[sound_file]" : null, "volume" = sound_volume, "mode" = motus_operandi, \
		"range" = emitter_range, "radius" = play_radius, "x" = x, "y" = y, "z" = z)

/obj/effect/sound_emitter/ui_act(action, list/params)
	if(..())
		return
	if(!check_rights_for(usr.client, R_SOUND))
		return
	switch(action)
		if("label")
			maptext = stripped_input_text("[params["text"]]", MAX_NAME_LEN)
		if("file")
			INVOKE_ASYNC(src, PROC_REF(pick_sound_file), usr)
		if("volume")
			sound_volume = clamp(round(text2num("[params["value"]]")), 0, 100)
		if("mode")
			if(params["value"] in list("local", "direct"))
				motus_operandi = params["value"]
		if("range")
			if(params["value"] in list("radius", "zlevel", "global"))
				emitter_range = params["value"]
		if("radius")
			play_radius = clamp(round(text2num("[params["value"]]")), 0, 127)
		if("play")
			activate(usr)
		if("jump")
			usr.client.jumptoturf(get_turf(src))
	return TRUE
