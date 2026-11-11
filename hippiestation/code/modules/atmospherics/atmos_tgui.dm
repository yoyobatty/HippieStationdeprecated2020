// Atmos windows redone (tgui-next AirAlarm.js, Canister.js, PortableAtmos.js, ThermoMachine.js, SpaceHeater.js): what's in
// the air or the tank gas by gas, so the windows can draw it as a coloured bar, and a couple of actions that take their
// value from the window instead of a pop-up (the air alarm's thresholds, the canister's label).

/// A gas mixture as a list for the windows: each gas present with its id (for its colour), name, moles and share
/proc/tgui_gas_list(datum/gas_mixture/air)
	var/list/gases = list()
	if(!air)
		return gases
	var/total = air.total_moles()
	if(total <= 0)
		return gases
	for(var/gas_id in air.moles)
		var/moles = air.moles[gas_id]
		if(moles <= 0)
			continue
		gases += list(list(
			"id" = GAS_META[META_GAS_ID][gas_id],
			"name" = GAS_META[META_GAS_NAME][gas_id],
			"moles" = round(moles, 0.01),
			"percent" = round(moles / total * 100, 0.01),
		))
	return gases

// Air alarm

/obj/machinery/airalarm
	ui_x = 520
	ui_y = 700

/obj/machinery/airalarm/ui_data(mob/user)
	. = ..()
	var/turf/T = get_turf(src)
	var/datum/gas_mixture/environment = T?.return_air()
	if(!environment)
		return
	var/area/A = get_area(src)
	.["areaName"] = A ? A.name : name
	.["pressure"] = round(environment.return_pressure(), 0.01)
	.["temperature"] = round(environment.temperature, 0.01)
	// Each gas with how worried the alarm is about it, as the readings list has it
	var/list/gases = tgui_gas_list(environment)
	var/partial_pressure = R_IDEAL_GAS_EQUATION * environment.temperature / environment.volume
	for(var/list/gas in gases)
		var/gas_path = gas_id2path(gas["id"])
		var/datum/tlv/tlv = TLV[gas_path]
		gas["danger"] = tlv ? tlv.get_danger_level(environment.moles[gas_path] * partial_pressure) : 0
	.["gases"] = gases
	// The air at each vent and scrubber, not just at the alarm (the user's ask, 2026-11-11): an alarm reads its own tile, like a
	// thermostat, so a vent across the room blowing plasma or a dead scrubber in a pocket of CO2 didn't show.
	if(A)
		for(var/list/vent in .["vents"])
			var/datum/weakref/ref = LAZYACCESS(A.air_vent_refs, vent["id_tag"])
			vent["air"] = device_air_data(ref?.resolve())
		for(var/list/scrubber in .["scrubbers"])
			var/datum/weakref/ref = LAZYACCESS(A.air_scrub_refs, scrubber["id_tag"])
			scrubber["air"] = device_air_data(ref?.resolve())

/// The air on a vent's or scrubber's tile, judged by this alarm's thresholds, and the pressure in the pipe behind it.
/obj/machinery/airalarm/proc/device_air_data(obj/machinery/atmospherics/components/unary/device)
	if(QDELETED(device))
		return null
	var/turf/T = get_turf(device)
	var/datum/gas_mixture/air = T?.return_air()
	if(!air)
		return null
	var/pressure = air.return_pressure()
	var/datum/tlv/pressure_tlv = TLV["pressure"]
	var/datum/tlv/temp_tlv = TLV["temperature"]
	var/list/gases = tgui_gas_list(air)
	var/partial_pressure = R_IDEAL_GAS_EQUATION * air.temperature / air.volume
	for(var/list/gas in gases)
		var/gas_path = gas_id2path(gas["id"])
		var/datum/tlv/tlv = TLV[gas_path]
		gas["danger"] = tlv ? tlv.get_danger_level(air.moles[gas_path] * partial_pressure) : 0
	var/datum/gas_mixture/pipe = device.airs[1]
	return list(
		"pressure" = round(pressure, 0.1),
		"pressure_danger" = pressure_tlv ? pressure_tlv.get_danger_level(pressure) : 0,
		"temperature" = round(air.temperature, 0.1),
		"temperature_danger" = temp_tlv ? temp_tlv.get_danger_level(air.temperature) : 0,
		"gases" = gases,
		"pipe" = pipe ? round(pipe.return_pressure(), 0.1) : null,
	)

/// Vents and scrubbers by id_tag, so an air alarm can read the air where each one is. Weak: an area outlives its vents.
/area
	var/list/air_vent_refs
	var/list/air_scrub_refs

/obj/machinery/atmospherics/components/unary/vent_pump/broadcast_status()
	. = ..()
	var/area/A = get_area(src)
	if(A && id_tag)
		LAZYSET(A.air_vent_refs, id_tag, WEAKREF(src))

/obj/machinery/atmospherics/components/unary/vent_scrubber/broadcast_status()
	. = ..()
	var/area/A = get_area(src)
	if(A && id_tag)
		LAZYSET(A.air_scrub_refs, id_tag, WEAKREF(src))

// "threshold_set" takes the value from the window (the old "threshold" asks with a pop-up)
/obj/machinery/airalarm/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	if(action != "threshold_set")
		return ..()
	if(!ui || ui.status != UI_INTERACTIVE || buildstage != 2)
		return
	if((locked && !usr.has_unlimited_silicon_privilege) || (usr.has_unlimited_silicon_privilege && aidisabled))
		return
	var/env = params["env"]
	if(text2path(env))
		env = text2path(env)
	var/name = params["var"]
	if(!(name in list("min1", "min2", "max1", "max2")))
		return
	var/datum/tlv/tlv = TLV[env]
	var/value = text2num(params["value"])
	if(isnull(tlv) || isnull(value))
		return
	tlv.vars[name] = value < 0 ? -1 : round(value, 0.01)
	investigate_log(" treshold value for [env]:[name] was set to [value] by [key_name(usr)]", INVESTIGATE_ATMOS)
	update_icon()
	return TRUE

// Canister

/obj/machinery/portable_atmospherics/canister
	ui_x = 460
	ui_y = 480

/obj/machinery/portable_atmospherics/canister/ui_data()
	. = ..()
	.["gases"] = tgui_gas_list(air_contents)
	.["temperature"] = round(air_contents.temperature, 0.1)
	.["maxPressure"] = round(maximum_pressure)
	var/list/labels = list()
	for(var/label in label2types)
		labels += label
	.["labels"] = labels
	if(holding)
		var/list/tank = .["holdingTank"]
		tank["gases"] = tgui_gas_list(holding.air_contents)

// "relabel_to" takes the label from the window's list (the old "relabel" asks with a pop-up)
/obj/machinery/portable_atmospherics/canister/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
	if(action != "relabel_to")
		return ..()
	if(!ui || ui.status != UI_INTERACTIVE)
		return
	var/newtype = label2types[params["label"]]
	if(!newtype)
		return
	var/obj/machinery/portable_atmospherics/canister/replacement = newtype
	investigate_log("was relabelled to [initial(replacement.name)] by [key_name(usr)].", INVESTIGATE_ATMOS)
	name = initial(replacement.name)
	desc = initial(replacement.desc)
	icon_state = initial(replacement.icon_state)
	update_icon()
	return TRUE

// Portable pump and scrubber

/obj/machinery/portable_atmospherics/pump
	ui_x = 400
	ui_y = 380

/obj/machinery/portable_atmospherics/pump/ui_data()
	. = ..()
	.["gases"] = tgui_gas_list(air_contents)
	if(holding)
		var/list/tank = .["holding"]
		tank["gases"] = tgui_gas_list(holding.air_contents)

/obj/machinery/portable_atmospherics/scrubber
	ui_x = 420
	ui_y = 400

/obj/machinery/portable_atmospherics/scrubber/ui_data()
	. = ..()
	.["gases"] = tgui_gas_list(air_contents)
	if(holding)
		var/list/tank = .["holding"]
		tank["gases"] = tgui_gas_list(holding.air_contents)

// Freezer and heater

/obj/machinery/atmospherics/components/unary/thermomachine
	ui_x = 400
	ui_y = 270

/obj/machinery/atmospherics/components/unary/thermomachine/ui_data(mob/user)
	. = ..()
	.["cooling"] = istype(src, /obj/machinery/atmospherics/components/unary/thermomachine/freezer)
	.["roomTemp"] = T20C

// Space heater

/obj/machinery/space_heater
	ui_x = 400
	ui_y = 340

/obj/machinery/space_heater/ui_data()
	. = ..()
	.["working"] = on ? mode : "standby" // heat, cool or standby (spaceheater.dm's HEATER_MODE_*)
