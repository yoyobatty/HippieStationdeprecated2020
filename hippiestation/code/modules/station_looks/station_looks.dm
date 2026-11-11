// Station looks: each round rolls how the station looks and feels, in layers. Every round gets a sky and a shift time,
// most get an extra or two, and now and then one gets a history. Each look's weight is in its code; STATION_LOOK_WEIGHT
// in hippiestation_config.txt changes it, and 0 means it never comes up. "none_extra" and "none_history" there weigh
// rolling nothing for those slots.
//
// The sky goes up as soon as it's rolled, so the lobby sees it. The rest waits for the round to start, when the lights
// and APCs are all in place, and then everyone gets a line of shift notes saying what's different. Admins can force,
// ban and re-roll looks with the Station Looks verb (station_looks_window.dm), in the lobby or later: every look but a
// history can be taken off again, so forcing one mid-round swaps it cleanly.
//
// Test runs pick them with the station-looks world param: "plain" is a day shift and nothing else (the sky still rolls),
// or give look ids joined by commas ("night,tired_wiring"). Without the param they roll as in a real round.

/datum/config_entry/keyed_list/station_look_weight // how often each station look comes up (hippiestation/code/modules/station_looks/)
	key_mode = KEY_MODE_TEXT
	value_mode = VALUE_MODE_NUM

/datum/station_look
	/// Its name in config and params. Null on the abstract types in between
	var/id
	var/name
	var/slot
	var/weight = 10
	/// Its part of the shift notes everyone gets as the round starts, or null to say nothing
	var/news
	/// Whether it's on the station now
	var/active = FALSE
	/// Whether remove() takes it off again. A history can't be: it wrecks things
	var/removable = TRUE

/// Puts the look on the station. at_start is TRUE when the round is starting, FALSE when an admin forces it later.
/datum/station_look/proc/apply(at_start)
	active = TRUE

/// Takes the look off the station again.
/datum/station_look/proc/remove()
	active = FALSE

/// Its part of the shift notes, for when it's rolled.
/datum/station_look/proc/news_line()
	return news

SUBSYSTEM_DEF(station_looks)
	name = "Station Looks"
	flags = SS_NO_FIRE
	init_order = INIT_ORDER_STATION_LOOKS
	/// Every look, by id
	var/list/looks = list()
	/// Slot -> the ids rolled into it
	var/list/picked = list()
	/// Ids an admin has ruled out of this round's re-rolls
	var/list/banned = list()
	/// Whether the round's looks are on the station: they go on as the round starts
	var/applied = FALSE
	/// Lamps on the station take this colour multiplied in (the shift time's), or null for none
	var/lamp_tint
	/// ...and this much of their power
	var/lamp_power = 1
	/// Lamps on night lighting take this colour multiplied in, or null to keep their own night colour
	var/night_tint

/// Each slot: list(most looks it takes, weight of rolling nothing for it). Extras roll a second look half the time.
GLOBAL_LIST_INIT(station_look_slots, list(
	LOOK_SLOT_SKY = list(1, 0),
	LOOK_SLOT_SHIFT = list(1, 0),
	LOOK_SLOT_EXTRA = list(2, 10),
	LOOK_SLOT_HISTORY = list(1, 20)))

/datum/controller/subsystem/station_looks/Initialize(timeofday)
	for(var/path in subtypesof(/datum/station_look))
		var/datum/station_look/L = path
		if(initial(L.id))
			add_look(new path)
	for(var/path in subtypesof(/datum/sky_theme))
		add_look(new /datum/station_look/sky(path))
	for(var/slot in GLOB.station_look_slots)
		picked[slot] = list()
	var/forced = world.params[STATION_LOOKS_PARAMETER]
	if(forced)
		pick_from_param(forced)
	else
		for(var/slot in GLOB.station_look_slots)
			roll_slot(slot)
	log_game("Station looks rolled: [summary()]")
	SSticker.OnRoundstart(CALLBACK(src, PROC_REF(round_started)))
	return ..()

/datum/controller/subsystem/station_looks/Recover()
	looks = SSstation_looks.looks
	picked = SSstation_looks.picked
	banned = SSstation_looks.banned
	applied = SSstation_looks.applied
	lamp_tint = SSstation_looks.lamp_tint
	lamp_power = SSstation_looks.lamp_power
	night_tint = SSstation_looks.night_tint

/datum/controller/subsystem/station_looks/proc/add_look(datum/station_look/L)
	if(looks[L.id])
		stack_trace("Two station looks have the id [L.id]")
		return
	looks[L.id] = L

/// How likely a look is to roll: its own weight, or the config's.
/datum/controller/subsystem/station_looks/proc/look_weight(datum/station_look/L)
	var/list/config_weights = CONFIG_GET(keyed_list/station_look_weight)
	if(!isnull(config_weights[L.id]))
		return max(0, config_weights[L.id])
	return L.weight

/// How likely a slot is to roll nothing.
/datum/controller/subsystem/station_looks/proc/none_weight(slot)
	var/list/config_weights = CONFIG_GET(keyed_list/station_look_weight)
	if(!isnull(config_weights["none_[slot]"]))
		return max(0, config_weights["none_[slot]"])
	var/list/rule = GLOB.station_look_slots[slot]
	return rule[2]

/// Whether a slot's looks can still change: not once a history that can't be taken off is on.
/datum/controller/subsystem/station_looks/proc/slot_locked(slot)
	for(var/id in picked[slot])
		var/datum/station_look/L = looks[id]
		if(L.active && !L.removable)
			return TRUE
	return FALSE

/// Rolls a slot afresh, taking off what it had. Returns FALSE if it can't change.
/datum/controller/subsystem/station_looks/proc/roll_slot(slot)
	if(slot_locked(slot))
		return FALSE
	clear_slot(slot)
	var/list/rule = GLOB.station_look_slots[slot]
	for(var/draw in 1 to rule[1])
		if(draw > 1 && prob(50))
			break
		var/list/weights = list()
		for(var/id in looks)
			var/datum/station_look/L = looks[id]
			if(L.slot != slot || banned[id] || (id in picked[slot]))
				continue
			var/chance = look_weight(L)
			if(chance > 0)
				weights[id] = chance
		if(!length(weights))
			break
		if(draw == 1)
			var/nothing = none_weight(slot)
			if(nothing > 0)
				weights["none"] = nothing
		var/id = pickweight(weights)
		if(!id || id == "none")
			break
		picked[slot] += id
	put_on(slot)
	return TRUE

/// Takes a slot's looks off and forgets them.
/datum/controller/subsystem/station_looks/proc/clear_slot(slot)
	for(var/id in picked[slot])
		var/datum/station_look/L = looks[id]
		if(L.active)
			L.remove()
	picked[slot] = list()

/// Puts on whatever a slot has that isn't on yet: at once for the sky, from the round's start for the rest.
/datum/controller/subsystem/station_looks/proc/put_on(slot, at_start = FALSE)
	if(slot != LOOK_SLOT_SKY && !applied)
		return
	for(var/id in picked[slot])
		var/datum/station_look/L = looks[id]
		if(!L.active)
			L.apply(at_start)

/// An admin's pick. A slot that takes one look gets just this one; extras and histories take it on or off.
/datum/controller/subsystem/station_looks/proc/force(id)
	var/datum/station_look/L = looks[id]
	if(!L || slot_locked(L.slot))
		return FALSE
	var/list/rule = GLOB.station_look_slots[L.slot]
	if(id in picked[L.slot])
		if(rule[1] == 1 && L.slot != LOOK_SLOT_HISTORY)
			return TRUE //a sky or shift time can't be taken off, only swapped for another
		if(L.active)
			L.remove()
		picked[L.slot] -= id
		return TRUE
	if(rule[1] == 1)
		clear_slot(L.slot)
	picked[L.slot] += id
	banned -= id
	put_on(L.slot)
	return TRUE

/datum/controller/subsystem/station_looks/proc/pick_from_param(text)
	var/list/ids = splittext(lowertext(text), ",")
	if("plain" in ids)
		ids -= "plain"
		ids += "day"
		roll_slot(LOOK_SLOT_SKY)
	for(var/id in ids)
		var/datum/station_look/L = looks[id]
		if(!L)
			log_world("Station looks: no look called [id]")
			continue
		if(GLOB.station_look_slots[L.slot][1] == 1)
			picked[L.slot] = list()
		picked[L.slot] += id
	for(var/slot in list(LOOK_SLOT_SKY, LOOK_SLOT_SHIFT))
		if(!length(picked[slot]))
			roll_slot(slot)
	put_on(LOOK_SLOT_SKY)

/datum/controller/subsystem/station_looks/proc/round_started()
	applied = TRUE
	for(var/slot in list(LOOK_SLOT_SHIFT, LOOK_SLOT_HISTORY, LOOK_SLOT_EXTRA))
		put_on(slot, TRUE)
	addtimer(CALLBACK(src, PROC_REF(send_notes)), 2 SECONDS) //after the welcome
	log_game("Station looks on: [summary()]")

/// The shift notes: a line for everyone saying what this round's station is like, or null if there's nothing to say.
/datum/controller/subsystem/station_looks/proc/shift_notes()
	var/text = notes_text()
	if(text)
		return "<span class='notice'><b>Shift notes:</b> [text]</span>"

/// What the shift notes say, as plain text, or null for nothing.
/datum/controller/subsystem/station_looks/proc/notes_text()
	var/list/lines = list()
	for(var/slot in list(LOOK_SLOT_SHIFT, LOOK_SLOT_SKY, LOOK_SLOT_HISTORY, LOOK_SLOT_EXTRA))
		for(var/id in picked[slot])
			var/datum/station_look/L = looks[id]
			var/line = L.news_line()
			if(line)
				lines += line
	if(length(lines))
		return jointext(lines, " ")

/datum/controller/subsystem/station_looks/proc/send_notes()
	var/notes = shift_notes()
	if(notes)
		to_chat(world, notes)

/// What's rolled, for logs: "sky: Ember Reach; shift: Night; extra: Tired wiring"
/datum/controller/subsystem/station_looks/proc/summary()
	var/list/parts = list()
	for(var/slot in GLOB.station_look_slots)
		var/list/names = list()
		for(var/id in picked[slot])
			var/datum/station_look/L = looks[id]
			names += L.name
		parts += "[slot]: [length(names) ? english_list(names) : "none"]"
	return jointext(parts, "; ")

/// Every lamp on the station's levels, the ones a look changes, and any a look changed before that's gone elsewhere since
/// (the arrivals shuttle's, tinted while it was docked).
/proc/station_lamps()
	. = list()
	for(var/obj/machinery/light/L in GLOB.machines)
		if(L.look_base || (L.z && is_station_level(L.z)))
			. += L

/// rgb multiplied by tint, channel by channel: white takes the tint, a tint of white changes nothing.
/proc/look_tint(rgb, tint)
	if(!tint)
		return rgb
	var/list/base = ReadRGB(rgb)
	var/list/by = ReadRGB(tint)
	if(!base || !by)
		return rgb
	return rgb(round(base[1] * by[1] / 255), round(base[2] * by[2] / 255), round(base[3] * by[3] / 255))
