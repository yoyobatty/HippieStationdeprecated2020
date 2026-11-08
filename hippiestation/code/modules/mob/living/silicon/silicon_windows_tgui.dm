// hippie -- the AI's and cyborgs' old HTML windows in tgui (interfaces/SiliconWindows.js): Current Station Alerts (the AI's with
// its cameras, a cyborg's without), the AI's Remote Robot Control and its Announcement Help (the VOX words, searchable, a word
// clicked to hear it, and a sentence checked word by word and announced from the window). Each window is its own datum, as the law
// panel is, so the mobs keep no ui procs of their own. Every button goes through what the old page's link did: the AI's Topic()
// for cameras, bots and words, and announcement()'s rules for the sentence.

/// A bot's get_mode() is a coloured span: its words, and its colour for the window
/proc/bot_mode_for_ui(mob/living/simple_animal/bot/B)
	var/raw = B.get_mode()
	var/static/regex/span_class = new("class='(\\w+)'")
	return list("mode" = comm_plain_text(raw), "mode_color" = span_class.Find(raw) ? span_class.group[1] : null)

/mob/living/silicon
	var/datum/silicon_alerts_window/alerts_window

/mob/living/silicon/ai
	var/datum/ai_bot_control_window/bot_control_window
	var/datum/ai_vox_window/vox_window

// ---------------------------------------------------------------------------------------------
// Current Station Alerts
// ---------------------------------------------------------------------------------------------

/mob/living/silicon/ai/ai_alerts()
	viewalerts = 1
	if(!alerts_window)
		alerts_window = new(src)
	alerts_window.ui_interact(src)

/mob/living/silicon/robot/robot_alerts()
	if(!alerts_window)
		alerts_window = new(src)
	alerts_window.ui_interact(src)

// A cyborg's window follows its alarms as the AI's does (the old one was a snapshot)
/mob/living/silicon/robot/triggerAlarm(class, area/A, O, obj/alarmsource)
	. = ..()
	if(alerts_window)
		SStgui.update_uis(alerts_window)

/mob/living/silicon/robot/cancelAlarm(class, area/A, obj/origin)
	. = ..()
	if(alerts_window)
		SStgui.update_uis(alerts_window)

/datum/silicon_alerts_window
	var/datum/weakref/owner_ref

/datum/silicon_alerts_window/New(mob/living/silicon/owner)
	owner_ref = WEAKREF(owner)

/datum/silicon_alerts_window/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	if(user != owner_ref?.resolve())
		return
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "silicon_alerts", "Current Station Alerts", 420, 520, master_ui, state)
		ui.open()

/datum/silicon_alerts_window/ui_close(mob/user)
	var/mob/living/silicon/ai/AI = owner_ref?.resolve()
	if(istype(AI))
		AI.viewalerts = 0

/datum/silicon_alerts_window/ui_data(mob/user)
	var/mob/living/silicon/owner = owner_ref?.resolve()
	. = list()
	if(!owner)
		return
	var/list/alarms
	if(isAI(owner))
		var/mob/living/silicon/ai/AI = owner
		alarms = AI.alarms
	else if(iscyborg(owner))
		var/mob/living/silicon/robot/R = owner
		alarms = R.alarms
	.["cameras"] = isAI(owner)
	var/list/categories = list()
	for(var/category in alarms)
		var/list/entries = list()
		var/list/L = alarms[category]
		for(var/alarm in L)
			var/list/alm = L[alarm]
			var/area/A = alm[1]
			var/list/cams = list()
			var/C = alm[2]
			if(islist(C))
				for(var/obj/machinery/camera/I in C)
					cams += list(list("name" = I.c_tag, "ref" = REF(I)))
			else if(istype(C, /obj/machinery/camera))
				var/obj/machinery/camera/I = C
				cams += list(list("name" = I.c_tag, "ref" = REF(I)))
			var/list/sources = alm[3]
			entries += list(list("area" = A ? A.name : "[alarm]", "sources" = length(sources), "cameras" = cams))
		categories += list(list("name" = category, "alarms" = entries))
	.["categories"] = categories

/datum/silicon_alerts_window/ui_act(action, list/params)
	if(..())
		return
	var/mob/living/silicon/ai/AI = owner_ref?.resolve()
	if(action == "camera" && istype(AI) && usr == AI)
		AI.Topic(null, list("switchcamera" = params["ref"]))
		return TRUE

// ---------------------------------------------------------------------------------------------
// Remote Robot Control
// ---------------------------------------------------------------------------------------------

/mob/living/silicon/ai/botcall()
	set category = "AI Commands"
	set name = "Access Robot Control"
	set desc = "Wirelessly control various automatic robots."
	if(incapacitated())
		return
	if(control_disabled)
		to_chat(src, "<span class='warning'>Wireless control is disabled.</span>")
		return
	if(!bot_control_window)
		bot_control_window = new(src)
	bot_control_window.ui_interact(src)

/datum/ai_bot_control_window
	var/datum/weakref/owner_ref

/datum/ai_bot_control_window/New(mob/living/silicon/ai/owner)
	owner_ref = WEAKREF(owner)

/datum/ai_bot_control_window/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	if(user != owner_ref?.resolve())
		return
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "ai_bot_control", "Remote Robot Control", 620, 440, master_ui, state)
		ui.open()

/datum/ai_bot_control_window/ui_status(mob/user, datum/ui_state/state)
	var/mob/living/silicon/ai/AI = owner_ref?.resolve()
	if(!istype(AI) || user != AI || AI.incapacitated())
		return UI_CLOSE
	return UI_INTERACTIVE

/datum/ai_bot_control_window/ui_data(mob/user)
	var/mob/living/silicon/ai/AI = owner_ref?.resolve()
	. = list()
	if(!istype(AI))
		return
	.["disabled"] = !!AI.control_disabled
	.["waypoint"] = !!AI.waypoint_mode
	.["calling"] = AI.Bot && !QDELETED(AI.Bot) ? AI.Bot.name : null
	var/turf/here = get_turf(AI)
	var/list/bots = list()
	for(var/mob/living/simple_animal/bot/B in GLOB.alive_mob_list)
		if(B.z != here?.z || B.remote_disabled) //Only non-emagged bots on the same Z-level are detected!
			continue
		bots += list(list("ref" = REF(B), "name" = B.name, "model" = B.model, "hacked" = !!B.hacked, "location" = get_area_name(B, TRUE)) + bot_mode_for_ui(B))
	.["bots"] = bots

/datum/ai_bot_control_window/ui_act(action, list/params)
	if(..())
		return
	var/mob/living/silicon/ai/AI = owner_ref?.resolve()
	if(!istype(AI) || usr != AI)
		return
	switch(action)
		if("interface")
			AI.Topic(null, list("interface" = params["ref"]))
			return TRUE
		if("call")
			AI.Topic(null, list("callbot" = params["ref"]))
			return TRUE
		if("cancel_call")
			AI.waypoint_mode = 0
			return TRUE

// ---------------------------------------------------------------------------------------------
// Announcement Help (the VOX words)
// ---------------------------------------------------------------------------------------------

#ifdef AI_VOX
GLOBAL_VAR_INIT(ai_vox_next, 0)

/mob/living/silicon/ai/announcement_help()
	set name = "Announcement Help"
	set desc = "Display a list of vocal words to announce to the crew."
	set category = "AI Commands"
	if(incapacitated())
		return
	if(!vox_window)
		vox_window = new(src)
	vox_window.ui_interact(src)

// The Announcement button and verb keep their typed prompt, with the window's cooldown (announcement()'s own was a static var)
/mob/living/silicon/ai/announcement()
	if(GLOB.ai_vox_next > world.time)
		to_chat(src, "<span class='notice'>Please wait [DisplayTimeText(GLOB.ai_vox_next - world.time)].</span>")
		return
	var/message = tgui_input_text(src, "WARNING: Misuse of this verb can result in you being job banned. More help is available in 'Announcement Help'", "Announcement", src.last_announcement, allow_cancel = FALSE)
	ai_vox_announce(message)

/// announcement() after its prompt: the same checks, the same log, the same cooldown
/mob/living/silicon/ai/proc/ai_vox_announce(message)
	last_announcement = message
	if(!message || GLOB.ai_vox_next > world.time)
		return FALSE
	if(incapacitated())
		return FALSE
	if(control_disabled)
		to_chat(src, "<span class='warning'>Wireless interface disabled, unable to interact with announcement PA.</span>")
		return FALSE
	var/list/words = splittext(trim(message), " ")
	var/list/incorrect_words = list()
	if(words.len > 30)
		words.len = 30
	for(var/word in words)
		word = lowertext(trim(word))
		if(!word)
			words -= word
			continue
		if(!GLOB.vox_sounds[word])
			incorrect_words += word
	if(incorrect_words.len)
		to_chat(src, "<span class='notice'>These words are not available on the announcement system: [english_list(incorrect_words)].</span>")
		return FALSE
	GLOB.ai_vox_next = world.time + 60 SECONDS // say.dm VOX_DELAY (undefined past that file)
	log_game("[key_name(src)] made a vocal announcement with the following message: [message].")
	for(var/word in words)
		play_vox_word(word, src.z, null)
	return TRUE

/datum/ai_vox_window
	var/datum/weakref/owner_ref

/datum/ai_vox_window/New(mob/living/silicon/ai/owner)
	owner_ref = WEAKREF(owner)

/datum/ai_vox_window/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.always_state)
	if(user != owner_ref?.resolve())
		return
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "ai_vox", "Announcement Help", 560, 600, master_ui, state)
		ui.open()

/datum/ai_vox_window/ui_status(mob/user, datum/ui_state/state)
	var/mob/living/silicon/ai/AI = owner_ref?.resolve()
	if(!istype(AI) || user != AI)
		return UI_CLOSE
	return AI.incapacitated() ? UI_DISABLED : UI_INTERACTIVE

/datum/ai_vox_window/ui_static_data(mob/user)
	var/list/words = list()
	for(var/word in GLOB.vox_sounds)
		words += word
	return list("words" = sortList(words), "max_words" = 30)

/datum/ai_vox_window/ui_data(mob/user)
	var/mob/living/silicon/ai/AI = owner_ref?.resolve()
	. = list()
	.["cooldown"] = max(0, round((GLOB.ai_vox_next - world.time) / 10))
	.["last"] = istype(AI) ? AI.last_announcement : ""
	.["disabled"] = istype(AI) && !!AI.control_disabled

/datum/ai_vox_window/ui_act(action, list/params)
	if(..())
		return
	var/mob/living/silicon/ai/AI = owner_ref?.resolve()
	if(!istype(AI) || usr != AI)
		return
	switch(action)
		if("preview")
			var/word = lowertext("[params["word"]]")
			if(GLOB.vox_sounds[word])
				play_vox_word(word, null, AI)
			return TRUE
		if("announce")
			AI.ai_vox_announce(copytext_char("[params["text"]]", 1, MAX_MESSAGE_LEN))
			return TRUE
#endif
