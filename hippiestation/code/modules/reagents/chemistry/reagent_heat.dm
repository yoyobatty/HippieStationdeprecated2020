// Heat in reagent containers.
// A hot tool, a fire or a microwave heats by how much is in the container: expose_temperature() used to move any amount the same part of
// the way, so a 1000 unit tank heated as fast as a pill bottle. And a container of reagents well off room temperature drifts towards the air
// around it (Newton's cooling), bigger ones slower, slower still in thin air: a heated beaker isn't hot for ever, a chilled one warms up.
// Kept from the air (no drift) in a machine (the chem heater holds its beaker where it's set; a fridge keeps what's in it), a grenade, a mech,
// anything but a mob, a bag or box, or a locker. Only reagent containers and tanks (/obj/structure/reagent_dispensers); not a mob's blood,
// a puddle, smoke or vapour. Only a container that's been heated or cooled away from room temperature is looked at at all: on SSprocessing
// while it drifts, off it again once it's at the air's temperature.

/datum/reagents
	/// When process() last moved it towards the air
	var/drift_last = 0
	/// When process() looks at it again (later while it's kept from the air)
	var/drift_next = 0
	/// Kept from the air till then: a chemical heater holds a chem tank beside it at its target (chem_heater.dm)
	var/drift_held_until = 0

/datum/reagents/expose_temperature(temperature, coeff = 0.02)
	if(!total_volume)
		return
	// The same coefficient as before at REAGENT_HEAT_REFERENCE_VOLUME units of the default specific heat: by heat capacity otherwise
	var/step = coeff * (REAGENT_HEAT_REFERENCE_VOLUME / total_volume) * (SPECIFIC_HEAT_DEFAULT / max(specific_heat(), 1))
	var/temp_delta = (temperature - chem_temp) * min(step, REAGENT_HEAT_MAX_STEP)
	if(temp_delta > 0)
		chem_temp = min(chem_temp + max(temp_delta, 1), temperature)
	else
		chem_temp = max(chem_temp + min(temp_delta, -1), temperature)
	chem_temp = round(chem_temp)
	handle_reactions()

/datum/reagents/Destroy()
	if(datum_flags & DF_ISPROCESSING)
		STOP_PROCESSING(SSprocessing, src)
	return ..()

/// Whether these reagents drift towards the air: a reagent container's or a tank's
#define REAGENT_DRIFTS(R) (istype(R.my_atom, /obj/item/reagent_containers) || istype(R.my_atom, /obj/structure/reagent_dispensers))

/// From handle_reactions(), when it's off room temperature and not drifting already
/datum/reagents/proc/start_drift()
	if(!total_volume || !REAGENT_DRIFTS(src) || QDELETED(my_atom))
		return
	drift_last = world.time
	drift_next = 0
	START_PROCESSING(SSprocessing, src)

/datum/reagents/process()
	if(!total_volume || QDELETED(my_atom) || !REAGENT_DRIFTS(src))
		return PROCESS_KILL
	var/now = world.time
	if(now < drift_next)
		return
	var/elapsed = (now - drift_last) / (1 SECONDS)
	drift_last = now
	var/turf/open/T = (now < drift_held_until) ? null : reagent_drift_turf(my_atom)
	if(!T)
		drift_next = now + REAGENT_DRIFT_INSULATED_RECHECK
		return
	var/datum/gas_mixture/air = T.air
	var/ambient = air.return_temperature()
	var/gap = chem_temp - ambient
	if(abs(gap) <= REAGENT_DRIFT_STOP)
		return PROCESS_KILL
	drift_next = now + REAGENT_DRIFT_STEP
	// Thin air carries heat off slower; in a vacuum it only radiates
	var/contact = clamp(air.return_pressure() / ONE_ATMOSPHERE, 0.1, 1)
	var/drift_time = (REAGENT_DRIFT_TIME / (1 SECONDS)) * (specific_heat() / SPECIFIC_HEAT_DEFAULT) * ((total_volume / REAGENT_HEAT_REFERENCE_VOLUME) ** (1/3)) / contact
	chem_temp = ambient + gap * (NUM_E ** (-elapsed / drift_time))
	handle_reactions()

#undef REAGENT_DRIFTS

/// The open turf whose air a reagent container (A) gives its heat to, or null when it's kept from it: anywhere but on the floor, on a mob,
/// in a bag or box, or in a locker or crate (each of those may be in another)
/proc/reagent_drift_turf(atom/A)
	var/atom/at = A.loc
	for(var/depth in 1 to 6)
		if(isturf(at))
			var/turf/open/T = at
			return (istype(T) && T.air) ? T : null
		if(!(ismob(at) || istype(at, /obj/item/storage) || istype(at, /obj/structure/closet)))
			return null
		at = at.loc
	return null
