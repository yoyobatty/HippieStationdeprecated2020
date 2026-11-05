// hippie -- the assemblies as tgui windows (tgui-next interfaces/Assembly.js), one window for the five: the signaler (frequency and
// code dragged or typed, Send, and back to the default), the timer and the proximity sensor (the time as a clock with - and +,
// counting down live, repeat, the sensor's range), the infrared laser (on, visible) and the health sensor (on, the reading, what it
// goes off at). The old windows were short pages of links, the signaler's frequency and code a popup each, and the timer's time stood
// still unless you pressed Refresh. Each button goes through the assembly's own Topic().

/// In your hands or anywhere on you (an assembly sits in a holder, a bomb, a backpack), or within reach; and screwed shut, as the
/// old windows wanted
/datum/ui_state/assembly_state/can_use_topic(src_object, mob/user)
	var/obj/item/assembly/A = src_object
	if(istype(A) && !A.secured)
		return UI_CLOSE
	if(user.contains(src_object) || get_dist(get_turf(src_object), get_turf(user)) <= 1)
		return user.shared_ui_interaction(src_object)
	return UI_CLOSE

GLOBAL_DATUM_INIT(assembly_state, /datum/ui_state/assembly_state, new)

/obj/item/assembly/proc/assembly_window(mob/user, ui_key, datum/tgui/ui, force_open, datum/tgui/master_ui, datum/ui_state/state, height)
	if(!ui && !is_secured(user))
		return
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "assembly", name, 320, height, master_ui, state)
		ui.open()

// The signaler

/obj/item/assembly/signaler/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.assembly_state)
	assembly_window(user, ui_key, ui, force_open, master_ui, state, 200)

/obj/item/assembly/signaler/ui_data(mob/user)
	return list(
		"kind" = "signaler",
		"frequency" = frequency,
		"code" = code,
		"min_frequency" = MIN_FREE_FREQ,
		"max_frequency" = MAX_FREE_FREQ,
		"default_frequency" = FREQ_SIGNALER,
		"default_code" = DEFAULT_SIGNALER_CODE,
	)

/obj/item/assembly/signaler/ui_act(action, params)
	if(..())
		return
	switch(action)
		if("send")
			Topic(null, list("send" = "1"))
		if("frequency") // the old popup's number, set in the window
			var/new_frequency = text2num(params["frequency"])
			if(!isnull(new_frequency))
				set_frequency(sanitize_frequency(unformat_frequency(new_frequency), TRUE))
		if("code")
			var/new_code = text2num(params["code"])
			if(!isnull(new_code))
				code = clamp(round(new_code), 1, 100)
		if("reset")
			set_frequency(FREQ_SIGNALER)
			code = DEFAULT_SIGNALER_CODE
	return TRUE

// The electropack: a signaler's receiver on a backpack, in the same window, set through its old - and + links

/obj/item/electropack/attack_self(mob/user)
	if(ishuman(user))
		ui_interact(user)

/obj/item/electropack/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.assembly_state)
	ui = SStgui.try_update_ui(user, src, ui_key, ui, force_open)
	if(!ui)
		ui = new(user, src, ui_key, "assembly", name, 320, 200, master_ui, state)
		ui.open()

/obj/item/electropack/ui_data(mob/user)
	var/mob/living/carbon/C = user
	return list(
		"kind" = "electropack",
		"on" = on,
		"frequency" = frequency,
		"code" = code,
		"min_frequency" = MIN_FREE_FREQ,
		"max_frequency" = MAX_FREE_FREQ,
		"worn" = istype(C) && C.back == src,
	)

/obj/item/electropack/ui_act(action, params)
	if(..())
		return
	switch(action)
		if("power")
			Topic(null, list("power" = "1"))
		if("frequency")
			var/new_frequency = text2num(params["frequency"])
			if(!isnull(new_frequency))
				Topic(null, list("freq" = "[unformat_frequency(new_frequency) - frequency]"))
		if("code")
			var/new_code = text2num(params["code"])
			if(!isnull(new_code))
				Topic(null, list("code" = "[round(new_code) - code]"))
	return TRUE

// The timer

/obj/item/assembly/timer/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.assembly_state)
	assembly_window(user, ui_key, ui, force_open, master_ui, state, 190)

/obj/item/assembly/timer/ui_data(mob/user)
	return list("kind" = "timer", "time" = time, "timing" = timing, "repeat" = loop)

/obj/item/assembly/timer/ui_act(action, params)
	if(..())
		return
	switch(action)
		if("timing")
			Topic(null, list("time" = timing ? "0" : "1"))
		if("repeat")
			Topic(null, list("repeat" = loop ? "0" : "1"))
		if("time")
			Topic(null, list("tp" = "[round(text2num(params["by"]))]"))
	return TRUE

// The proximity sensor

/obj/item/assembly/prox_sensor/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.assembly_state)
	assembly_window(user, ui_key, ui, force_open, master_ui, state, 250)

/obj/item/assembly/prox_sensor/ui_data(mob/user)
	return list("kind" = "prox", "time" = time, "timing" = timing, "armed" = scanning, "range" = sensitivity, "max_range" = 5)

/obj/item/assembly/prox_sensor/ui_act(action, params)
	if(..())
		return
	switch(action)
		if("arm")
			Topic(null, list("scanning" = scanning ? "0" : "1"))
		if("timing")
			Topic(null, list("time" = timing ? "0" : "1"))
		if("time")
			Topic(null, list("tp" = "[round(text2num(params["by"]))]"))
		if("range")
			Topic(null, list("sense" = text2num(params["by"]) > 0 ? "up" : "down"))
	return TRUE

// The infrared laser

/obj/item/assembly/infra/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.assembly_state)
	assembly_window(user, ui_key, ui, force_open, master_ui, state, 170)

/obj/item/assembly/infra/ui_data(mob/user)
	return list("kind" = "infra", "on" = on, "visible" = visible)

/obj/item/assembly/infra/ui_act(action, params)
	if(..())
		return
	switch(action)
		if("power")
			Topic(null, list("state" = on ? "0" : "1"))
		if("visible")
			Topic(null, list("visible" = visible ? "0" : "1"))
	return TRUE

// The health sensor

/obj/item/assembly/health/ui_interact(mob/user, ui_key = "main", datum/tgui/ui = null, force_open = FALSE, datum/tgui/master_ui = null, datum/ui_state/state = GLOB.assembly_state)
	assembly_window(user, ui_key, ui, force_open, master_ui, state, 190)

/obj/item/assembly/health/ui_data(mob/user)
	return list(
		"kind" = "health",
		"on" = scanning,
		"health" = scanning ? health_scan : null,
		"alarm" = alarm_health == HEALTH_THRESHOLD_DEAD ? "death" : "critical",
	)

/obj/item/assembly/health/ui_act(action, params)
	if(..())
		return
	if(action == "power")
		Topic(null, list("scanning" = "1"))
	return TRUE
