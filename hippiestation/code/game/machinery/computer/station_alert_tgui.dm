// hippie -- fire alarm trip points, and the station alert console that clears fire alarms and sets them (tgui-next
// StationAlertConsole.js). The user's ruling, 2026-11-10: Chief Engineer's access and up (worn or in hand) clears an area's fire alarm
// from the console and sets what temperature trips them, for the station and for single areas. Within limits a fire always trips them:
// the hottest a trip point goes is tg's own 200 C. Cold can be turned right down or off, for rooms that are cold by design (the Kitchen
// Cold Room and the server rooms were every false alarm in a batch of shifts, 2026-11-08). An emagged console has no limits: a traitor
// can stop the alarms tripping for a fire at all, and clear them without anybody's ID.
//
// An alarm that's cleared trips again straight away if the room's still past its trip point, as a pulled alarm would.

/// Hot trip points: never above tg's (a fire is far past it), never so low an ordinary room trips them
#define FIRE_TRIP_HOT_MIN (T0C + 50)
#define FIRE_TRIP_HOT_MAX (T0C + 200)
/// Cold trip points: anything from off up to freezing
#define FIRE_TRIP_COLD_MAX (T0C)
/// The most an emagged console sets the hot point to, short of off
#define FIRE_TRIP_EMAGGED_MAX 100000
/// A trip point that never trips
#define FIRE_TRIP_OFF -1

/// The station's trip points, for every area without its own
GLOBAL_VAR_INIT(fire_trip_hot, T0C + 200)
GLOBAL_VAR_INIT(fire_trip_cold, BODYTEMP_COLD_DAMAGE_LIMIT)

/area
	/// This area's own hot trip point for its fire alarms (null: the station's, FIRE_TRIP_OFF: never)
	var/fire_trip_hot
	/// And cold
	var/fire_trip_cold

/// The telecomms server room is kept at 80 K (TCOMMS_ATMOS), and the Hippie map has two fire alarms on its floor: with the station's
/// cold point (260 K) they tripped from roundstart to round end. It still trips on heat, for servers overheating their room.
/area/tcommsat/server
	fire_trip_cold = FIRE_TRIP_OFF

/area/proc/fire_trip_hot_point()
	return isnull(fire_trip_hot) ? GLOB.fire_trip_hot : fire_trip_hot

/area/proc/fire_trip_cold_point()
	return isnull(fire_trip_cold) ? GLOB.fire_trip_cold : fire_trip_cold

/// Whether air at this temperature trips the fire alarms here
/area/proc/fire_trips_at(temperature)
	var/hot = fire_trip_hot_point()
	var/cold = fire_trip_cold_point()
	return (hot != FIRE_TRIP_OFF && temperature > hot) || (cold != FIRE_TRIP_OFF && temperature < cold)

/// tg's: hotter than 200 C or colder than a body can stand (code/game/machinery/firealarm.dm), now the area's trip points
/obj/machinery/firealarm/should_atmos_process(datum/gas_mixture/air, exposed_temperature)
	var/area/A = get_area(src)
	return A?.fire_trips_at(exposed_temperature) && !(obj_flags & EMAGGED) && detecting && !stat

// ---- The console

/obj/machinery/computer/station_alert
	ui_x = 440
	ui_y = 620

/// Whether this user may clear fire alarms and set trip points here
/obj/machinery/computer/station_alert/proc/can_set_trips(mob/user)
	if(obj_flags & EMAGGED)
		return TRUE
	if(issilicon(user) || IsAdminGhost(user))
		return TRUE
	var/obj/item/card/id/I = user?.get_idcard(TRUE)
	return istype(I) && (ACCESS_CE in I.access)

/obj/machinery/computer/station_alert/emag_act(mob/user)
	if(obj_flags & EMAGGED)
		return
	obj_flags |= EMAGGED
	playsound(src, "sparks", 50, TRUE)
	if(user)
		to_chat(user, "<span class='notice'>You short out [src]'s safety limits.</span>")
		log_game("[key_name(user)] emagged [src] at [AREACOORD(src)]")

/// A trip point as the window shows it: kelvin, or null for off
/proc/fire_trip_for_ui(value)
	return value == FIRE_TRIP_OFF ? null : round(value, 0.1)

/obj/machinery/computer/station_alert/ui_data(mob/user)
	var/list/data = ..()
	data["can_edit"] = can_set_trips(user)
	data["emagged"] = !!(obj_flags & EMAGGED)
	data["station_hot"] = fire_trip_for_ui(GLOB.fire_trip_hot)
	data["station_cold"] = fire_trip_for_ui(GLOB.fire_trip_cold)
	var/list/own = list()
	for(var/area/A as anything in GLOB.sortedAreas)
		if(isnull(A.fire_trip_hot) && isnull(A.fire_trip_cold))
			continue
		own += list(list(
			"name" = A.name,
			"ref" = REF(A),
			"hot" = fire_trip_for_ui(A.fire_trip_hot_point()),
			"cold" = fire_trip_for_ui(A.fire_trip_cold_point()),
			"own_hot" = !isnull(A.fire_trip_hot),
			"own_cold" = !isnull(A.fire_trip_cold),
		))
	data["area_trips"] = own
	return data

/obj/machinery/computer/station_alert/ui_static_data(mob/user)
	var/list/data = list()
	data["hot_min"] = FIRE_TRIP_HOT_MIN
	data["hot_max"] = FIRE_TRIP_HOT_MAX
	data["cold_max"] = FIRE_TRIP_COLD_MAX
	data["emagged_max"] = FIRE_TRIP_EMAGGED_MAX
	// The areas on this level with fire alarms, for giving one its own trip points
	var/list/choices = list()
	for(var/area/A as anything in GLOB.sortedAreas)
		if(!length(A.firealarms))
			continue
		var/obj/machinery/firealarm/F = A.firealarms[1]
		if(F.z == z)
			choices += list(list("name" = A.name, "ref" = REF(A)))
	data["alarm_areas"] = choices
	return data

/obj/machinery/computer/station_alert/ui_act(action, list/params)
	if(..())
		return
	if(!can_set_trips(usr))
		to_chat(usr, "<span class='warning'>Access denied.</span>")
		playsound(src, 'sound/machines/terminal_prompt_deny.ogg', 50, FALSE)
		return
	switch(action)
		if("reset")
			return reset_fire_alarm(params["name"], usr)
		if("set")
			var/area/A
			if(params["ref"] != "station")
				A = trip_area(params["ref"])
				if(!A)
					return
			return set_trip(A, params["which"] == "cold" ? "cold" : "hot", params["value"] == "off" ? FIRE_TRIP_OFF : text2num("[params["value"]]"), usr)
		if("own")
			var/area/A = trip_area(params["ref"])
			if(!A)
				return
			A.fire_trip_hot = GLOB.fire_trip_hot
			A.fire_trip_cold = GLOB.fire_trip_cold
			log_game("[key_name(usr)] gave [A.name] its own fire alarm trip points at [src] ([AREACOORD(src)])")
			return TRUE
		if("unown")
			var/area/A = trip_area(params["ref"])
			if(!A)
				return
			A.fire_trip_hot = null
			A.fire_trip_cold = null
			log_game("[key_name(usr)] put [A.name]'s fire alarm trip points back to the station's at [src] ([AREACOORD(src)])")
			return TRUE

/// The area a window's ref names, if it is one
/obj/machinery/computer/station_alert/proc/trip_area(ref)
	var/area/A = locate(ref)
	return (istype(A) && (A in GLOB.sortedAreas)) ? A : null

/// Clears the fire alarm in the area of that name, every source it has, as resetting each of them would
/obj/machinery/computer/station_alert/proc/reset_fire_alarm(area_name, mob/user)
	var/list/alarm = alarms["Fire"][area_name]
	if(!islist(alarm) || !isarea(alarm[1]))
		return FALSE
	var/area/A = alarm[1]
	var/list/sources = alarm[3]
	for(var/source in sources?.Copy())
		A.firereset(source)
	playsound(src, 'sound/machines/terminal_prompt_confirm.ogg', 50, FALSE)
	log_game("[key_name(user)] cleared the fire alarm in [A.name] at [src] ([AREACOORD(src)])")
	return TRUE

/// Sets a trip point for the station (A null) or one area, kept within the limits unless the console's emagged
/obj/machinery/computer/station_alert/proc/set_trip(area/A, which, value, mob/user)
	if(!isnum(value))
		return FALSE
	var/emagged = obj_flags & EMAGGED
	if(which == "hot")
		if(value == FIRE_TRIP_OFF)
			if(!emagged)
				return FALSE
		else
			value = clamp(value, FIRE_TRIP_HOT_MIN, emagged ? FIRE_TRIP_EMAGGED_MAX : FIRE_TRIP_HOT_MAX)
	else if(value != FIRE_TRIP_OFF)
		value = clamp(value, 0, FIRE_TRIP_COLD_MAX)
	if(A)
		if(which == "hot")
			A.fire_trip_hot = value
		else
			A.fire_trip_cold = value
	else if(which == "hot")
		GLOB.fire_trip_hot = value
	else
		GLOB.fire_trip_cold = value
	var/shown = value == FIRE_TRIP_OFF ? "off" : "[round(value, 0.1)] K"
	log_game("[key_name(user)] set the [which] fire alarm trip point for [A ? A.name : "the station"] to [shown] at [src] ([AREACOORD(src)])[emagged ? " (emagged)" : ""]")
	if(emagged && which == "hot" && (value == FIRE_TRIP_OFF || value > FIRE_TRIP_HOT_MAX))
		message_admins("[ADMIN_LOOKUPFLW(user)] set the hot fire alarm trip point for [A ? A.name : "the whole station"] to [shown] on an emagged [src] [ADMIN_JMP(src)]: fires there won't trip the alarms.")
	return TRUE

#undef FIRE_TRIP_HOT_MIN
#undef FIRE_TRIP_COLD_MAX
#undef FIRE_TRIP_EMAGGED_MAX
