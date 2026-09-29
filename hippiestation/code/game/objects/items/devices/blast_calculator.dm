// Blast yield calculator: scan a tank transfer valve, a one-tank bomb or a gas tank and it replays the tank's own reaction
// ticks on a copy of the gas - /obj/item/tank/process() then check_status(), leaking and rupturing included - so it says
// what the bomb will actually do: detonate (how big, capped and uncapped, and how long after the valve opens), rupture,
// leak, or sit there. Gas reactions don't roll dice without a turf to act on, so the prediction is exact.

/// The most tank ticks a prediction runs for: 60 is two minutes (SSobj fires every two seconds)
#define BLAST_PREDICTION_TICKS 60

/obj/item/blast_calculator
	name = "blast yield calculator"
	desc = "A toxins lab calculator. Scan a tank transfer valve, a one-tank bomb or a gas tank with it and it simulates the mix to predict the blast."
	icon = 'hippiestation/icons/obj/dept_gear.dmi'
	icon_state = "blast_calculator"
	item_state = "analyzer"
	lefthand_file = 'icons/mob/inhands/equipment/tools_lefthand.dmi'
	righthand_file = 'icons/mob/inhands/equipment/tools_righthand.dmi'
	w_class = WEIGHT_CLASS_SMALL
	flags_1 = CONDUCT_1
	slot_flags = ITEM_SLOT_BELT
	throwforce = 0
	throw_speed = 3
	throw_range = 7
	materials = list(MAT_METAL = 300, MAT_GLASS = 200)
	/// One line on the last thing it simulated, read back on examine
	var/last_result

/obj/item/blast_calculator/examine(mob/user)
	. = ..()
	if(last_result)
		. += "<span class='notice'>Its screen shows its last result: [last_result]</span>"

/obj/item/blast_calculator/afterattack(atom/target, mob/user, proximity_flag, click_parameters)
	. = ..()
	if(!proximity_flag)
		return
	var/report = blast_report(target)
	if(!report)
		return
	playsound(src, 'sound/machines/ping.ogg', 20, TRUE)
	to_chat(user, report)

/// The prediction for whatever was scanned, or null if it isn't a bomb or a tank
/obj/item/blast_calculator/proc/blast_report(atom/target)
	var/datum/gas_mixture/mix
	var/list/prediction
	var/list/lines
	if(istype(target, /obj/item/transfer_valve))
		var/obj/item/transfer_valve/valve = target
		if(!valve.tank_one || !valve.tank_two)
			return "<span class='warning'>[valve] needs two tanks attached to simulate.</span>"
		if(valve.valve_open) // the two are already one mix, in the second tank
			mix = copy_tank_mix(valve.tank_two.air_contents)
		else // what merge_gases() does when the valve opens
			mix = copy_tank_mix(valve.tank_two.air_contents)
			mix.volume += valve.tank_one.air_contents.volume
			mix.merge(copy_tank_mix(valve.tank_one.air_contents).remove_ratio(1))
		lines = list("<b>[valve]</b>, [valve.valve_open ? "valve open" : "if the valve opens"]:")
		lines += describe_mix(mix)
		prediction = predict_tank_blast(mix, valve.tank_two.integrity)
		lines += describe_prediction(prediction, valve.valve_open ? "from now" : "after the valve opens")
	else if(istype(target, /obj/item/onetankbomb))
		var/obj/item/onetankbomb/bomb = target
		if(!bomb.bombtank)
			return
		mix = copy_tank_mix(bomb.bombtank.air_contents)
		lines = list("<b>[bomb]</b>:")
		lines += describe_mix(mix)
		var/list/idle = predict_tank_blast(mix, bomb.bombtank.integrity)
		if(!bomb.status)
			lines += "Its valve hasn't been bored out, so setting it off would just vent the tank."
			prediction = idle
			if(idle["result"] != "stable")
				lines += "Left alone: [describe_prediction(idle, "from now")]"
		else
			// Setting one off only heats its tank by 10 K (/obj/item/tank/ignite() in hippiestation/code/modules/assembly/bomb.dm),
			// and the tank's own reactions do the rest
			var/datum/gas_mixture/triggered = copy_tank_mix(mix)
			triggered.temperature += 10
			prediction = predict_tank_blast(triggered, bomb.bombtank.integrity)
			lines += "Set off: [describe_prediction(prediction, "after it's set off")]"
			if(idle["result"] != "stable")
				lines += "Left alone, it also: [describe_prediction(idle, "from now")]"
	else if(istype(target, /obj/item/tank))
		var/obj/item/tank/tank = target
		mix = copy_tank_mix(tank.air_contents)
		lines = list("<b>[tank]</b>:")
		lines += describe_mix(mix)
		prediction = predict_tank_blast(mix, tank.integrity)
		lines += describe_prediction(prediction, "from now")
	else
		return
	if(prediction)
		last_result = "[target]: [prediction_summary(prediction)]"
	return "<span class='notice'>[jointext(lines, "\n")]</span>"

/// A copy of a gas mix, volume included (/datum/gas_mixture/proc/copy() leaves the copy at CELL_VOLUME)
/proc/copy_tank_mix(datum/gas_mixture/air)
	var/datum/gas_mixture/copy = air.copy()
	copy.volume = air.volume
	return copy

/// Runs a copy of a tank's gas tick by tick exactly as /obj/item/tank/process() and check_status() would.
/// Returns a list: "result" is "explodes", "ruptures" or "stable"; "tick" is the tank tick it happened on;
/// "pressure" the pressure then (or the peak, when stable); "leaked" whether it leaked some gas on the way; and for
/// explosions "dev", "heavy", "light" and "flash", the ranges before any bomb cap.
/proc/predict_tank_blast(datum/gas_mixture/air, integrity = 3, max_ticks = BLAST_PREDICTION_TICKS)
	var/datum/gas_mixture/sim = copy_tank_mix(air)
	var/peak = sim.return_pressure()
	var/leaked = FALSE
	for(var/tick in 1 to max_ticks)
		var/reacted = sim.react()
		var/pressure = sim.return_pressure()
		peak = max(peak, pressure)
		if(pressure > TANK_FRAGMENT_PRESSURE)
			sim.react() // check_status() gives the mix one more reaction before it measures the blast
			pressure = sim.return_pressure()
			var/range = (pressure - TANK_FRAGMENT_PRESSURE) / TANK_FRAGMENT_SCALE
			return list("result" = "explodes", "tick" = tick, "pressure" = pressure, "leaked" = leaked,
				"dev" = round(range * 0.25), "heavy" = round(range * 0.5), "light" = round(range), "flash" = round(range * 1.5))
		if(pressure > TANK_RUPTURE_PRESSURE || sim.temperature > TANK_MELT_TEMPERATURE)
			if(integrity <= 0)
				return list("result" = "ruptures", "tick" = tick, "pressure" = pressure, "leaked" = leaked)
			integrity--
		else if(pressure > TANK_LEAK_PRESSURE)
			if(integrity <= 0)
				sim.remove_ratio(0.25)
				leaked = TRUE
			else
				integrity--
		else
			if(integrity < 3)
				integrity++
			else if(!reacted) // nothing reacting, nothing straining the tank: it stays like this
				break
	return list("result" = "stable", "tick" = 0, "pressure" = peak, "leaked" = leaked)

/obj/item/blast_calculator/proc/describe_mix(datum/gas_mixture/mix)
	return "Mix: [round(mix.total_moles(), 0.1)] mol at [round(mix.return_pressure(), 1)] kPa and [round(mix.temperature, 1)] K, in [mix.volume] L."

/obj/item/blast_calculator/proc/describe_prediction(list/prediction, when)
	var/seconds = prediction["tick"] * 2
	switch(prediction["result"])
		if("explodes")
			. = "<b>Detonates</b> within [seconds] seconds [when], at [round(prediction["pressure"])] kPa. [describe_yield(prediction["dev"], prediction["heavy"], prediction["light"], prediction["flash"])]"
		if("ruptures")
			. = "<b>Ruptures</b> within [seconds] seconds [when] at [round(prediction["pressure"])] kPa, spilling the mix without detonating."
		else
			. = "<b>No detonation.</b> It peaks at [round(prediction["pressure"])] kPa; a tank needs more than [round(TANK_FRAGMENT_PRESSURE)] kPa to detonate."
	if(prediction["leaked"])
		. += " It leaks some of the mix on the way."

/// The ranges, and what the station's bomb cap cuts them down to here
/obj/item/blast_calculator/proc/describe_yield(dev, heavy, light, flash)
	dev = max(dev, 0)
	heavy = max(heavy, 0)
	light = max(light, 0)
	flash = max(flash, 0)
	. = "Yield: <b>[dev]</b> devastation, <b>[heavy]</b> heavy, <b>[light]</b> light, [flash] flash."
	var/turf/here = get_turf(src)
	var/cap_multiplier = here ? SSmapping.level_trait(here.z, ZTRAIT_BOMBCAP_MULTIPLIER) : null
	if(isnull(cap_multiplier))
		cap_multiplier = 1
	var/capped_dev = min(GLOB.MAX_EX_DEVESTATION_RANGE * cap_multiplier, dev)
	var/capped_heavy = min(GLOB.MAX_EX_HEAVY_RANGE * cap_multiplier, heavy)
	var/capped_light = min(GLOB.MAX_EX_LIGHT_RANGE * cap_multiplier, light)
	var/capped_flash = min(GLOB.MAX_EX_FLASH_RANGE * cap_multiplier, flash)
	if(capped_dev != dev || capped_heavy != heavy || capped_light != light || capped_flash != flash)
		. += " The bomb cap here holds it to [capped_dev] / [capped_heavy] / [capped_light] / [capped_flash]; a doppler array would still read the full yield."

/proc/prediction_summary(list/prediction)
	switch(prediction["result"])
		if("explodes")
			return "detonates, [max(prediction["dev"], 0)] / [max(prediction["heavy"], 0)] / [max(prediction["light"], 0)]"
		if("ruptures")
			return "ruptures without detonating"
	return "no detonation (peaks at [round(prediction["pressure"])] kPa)"

// A closer look (examine it twice): how to use it
/obj/item/blast_calculator/examine_more(mob/user)
	. = ..()
	. += "<span class='notice'>Use it on a tank transfer valve, a one-tank bomb or a plain gas tank. It runs the tank's reactions forward on a copy of the gas and tells you what will actually happen: a detonation (how big, capped and uncapped, and how long after the valve opens), a rupture, a leak, or nothing at all.</span>"


#undef BLAST_PREDICTION_TICKS
