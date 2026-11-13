// A chem tank bolted beside a chemical heater: the heater, switched on, takes it to its target temperature too, slower the fuller it is
// (a full tank about 90 s to get most of the way with the stock laser, 22 s with a quantum one). While it does, the tank doesn't drift
// towards the air (reagent_heat.dm).

/// The bolted chem tank beside it it heats, if any
/obj/machinery/chem_heater/proc/linked_tank()
	for(var/dir in GLOB.cardinals)
		var/turf/T = get_step(src, dir)
		if(!T)
			continue
		for(var/obj/structure/reagent_dispensers/chemical/tank in T)
			if(tank.anchored && tank.reagents)
				return tank

/obj/machinery/chem_heater/process()
	. = ..()
	if(!on || (stat & (NOPOWER|BROKEN)))
		return
	var/obj/structure/reagent_dispensers/chemical/tank = linked_tank()
	if(!tank)
		return
	var/datum/reagents/R = tank.reagents
	R.drift_held_until = world.time + 5 SECONDS
	if(!R.total_volume || R.chem_temp == target_temperature)
		return
	// As it heats a beaker, by the square root of how much more is in the tank than a beaker's worth
	var/rate = heater_coefficient * min(1, sqrt(REAGENT_HEAT_REFERENCE_VOLUME / R.total_volume))
	R.adjust_thermal_energy((target_temperature - R.chem_temp) * rate * SPECIFIC_HEAT_DEFAULT * R.total_volume)
	R.handle_reactions()

/obj/machinery/chem_heater/ui_data(mob/user)
	. = ..()
	var/obj/structure/reagent_dispensers/chemical/tank = linked_tank()
	.["isTankLinked"] = !!tank
	if(tank)
		.["tankTemp"] = tank.reagents.chem_temp
		.["tankCurrentVolume"] = tank.reagents.total_volume
		.["tankMaxVolume"] = tank.reagents.maximum_volume
		.["tankColor"] = tgui_reagent_mix_color(tank.reagents)
