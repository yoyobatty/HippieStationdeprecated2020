 /*
What are the archived variables for?
	Calculations are done using the archived variables with the results merged into the regular variables.
	This prevents race conditions that arise based on the order of tile processing.
*/
#define MINIMUM_HEAT_CAPACITY	0.0003
#define MINIMUM_MOLE_COUNT		0.01
#define MOLAR_ACCURACY  1E-4
/**
 *I feel the need to document what happens here. Basically this is used
 *catch rounding errors, and make gas go away in small portions.
 *People have raised it to higher levels in the past, do not do this. Consider this number a soft limit
 *If you're making gasmixtures that have unexpected behavior related to this value, you're doing something wrong.
 *
 *On an unrelated note this may cause a bug that creates negative gas, related to round(). When it has a second arg it will round up.
 *So for instance round(0.5, 1) == 1. I've hardcoded a fix for this into share, by forcing the garbage collect.
 *Any other attempts to fix it just killed atmos. I leave this to a greater man then I
 */
#define QUANTIZE(variable) (round((variable), (MOLAR_ACCURACY)))
GLOBAL_LIST_INIT(meta_gas_info, meta_gas_list()) //see ATMOSPHERICS/gas_types.dm

/datum/gas_mixture
	/// Associative list of moles for each gas. List key is /datum/gas/<gas_name>, value is amount in moles.
	var/list/moles
	/// Archived version of moles.
	var/list/moles_archive
	/// Static, column-oriented gas metadata (see GAS_META / meta_gas_list()). Shared by every instance.
	var/static/list/gas_meta
	var/temperature = 0 //kelvins
	var/tmp/temperature_archived = 0
	var/volume = CELL_VOLUME //liters
	var/last_share = 0
	var/list/reaction_results
	var/list/analyzer_results //used for analyzer feedback - not initialized until its used
	var/gc_share = FALSE // Whether to call garbage_collect() on the sharer during shares, used for immutable mixtures

/datum/gas_mixture/New(volume)
	moles = list()
	moles_archive = list()
	if (!isnull(volume))
		src.volume = volume
	reaction_results = new

//listmos procs
//use the macros in performance intensive areas. for their definitions, refer to code/__DEFINES/atmospherics.dm

	//assert_gas(gas_id) - used to guarantee that this gas exists in moles/moles_archive.
	//Must be used before adding to a gas. May be used before reading from a gas.
/datum/gas_mixture/proc/assert_gas(gas_id)
	ASSERT_GAS(gas_id, src)

	//assert_gases(args) - shorthand for calling ASSERT_GAS() once for each gas type.
/datum/gas_mixture/proc/assert_gases(...)
	for(var/id in args)
		ASSERT_GAS(id, src)

	//add_gas(gas_id) - similar to assert_gas(), but does not check for an existing
		//entry for this id. This can clobber an existing gas.
	//Used instead of assert_gas() when you know the gas does not exist. Faster than assert_gas().
/datum/gas_mixture/proc/add_gas(gas_id)
	ADD_GAS(gas_id, src)

	//add_gases(args) - shorthand for calling add_gas() once for each gas_type.
/datum/gas_mixture/proc/add_gases(...)
	for(var/id in args)
		ADD_GAS(id, src)

	//garbage_collect() - removes any gas entry with a negligible amount.
	//Must be used after subtracting from a gas. Must be used after assert_gas()
		//if assert_gas() was called only to read from the gas.
	//By removing empty gases, processing speed is increased.
/datum/gas_mixture/proc/garbage_collect(list/tocheck)
	var/list/cached_moles = moles
	var/list/cached_moles_archive = moles_archive
	for(var/id in (tocheck || cached_moles))
		if(QUANTIZE(cached_moles[id]) < MINIMUM_MOLE_COUNT && QUANTIZE(cached_moles_archive[id]) < MINIMUM_MOLE_COUNT)
			cached_moles -= id
			cached_moles_archive -= id

	//PV = nRT

/datum/gas_mixture/proc/heat_capacity(data) //joules per kelvin
	return values_dot(data ? moles_archive : moles, GAS_META[META_GAS_SPECIFIC_HEAT])

/datum/gas_mixture/turf/heat_capacity(data) // Same as above except vacuums return HEAT_CAPACITY_VACUUM
	return values_dot(data ? moles_archive : moles, GAS_META[META_GAS_SPECIFIC_HEAT]) || HEAT_CAPACITY_VACUUM

/datum/gas_mixture/proc/total_moles()
	return values_sum(moles)

/datum/gas_mixture/proc/return_pressure() //kilopascals
	if(volume > 0) // to prevent division by zero
		return values_sum(moles) * R_IDEAL_GAS_EQUATION * temperature / volume
	return 0

/datum/gas_mixture/proc/return_temperature() //kelvins
	return temperature

/datum/gas_mixture/proc/return_volume() //liters
	return max(0, volume)

/datum/gas_mixture/proc/thermal_energy() //joules
	return THERMAL_ENERGY(src) //see code/__DEFINES/atmospherics.dm; use the define in performance critical areas

/datum/gas_mixture/proc/archive()
	//Update archived versions of variables
	//Returns: 1 in all cases
	moles_archive = moles.Copy()
	temperature_archived = temperature
	return 1

/datum/gas_mixture/proc/merge(datum/gas_mixture/giver)
	//Merges all air from giver into self. Deletes giver.
	//Returns: 1 if we are mutable, 0 otherwise
	if(!giver)
		return 0

	//heat transfer
	if(abs(temperature - giver.temperature) > MINIMUM_TEMPERATURE_DELTA_TO_CONSIDER)
		var/self_heat_capacity = heat_capacity()
		var/giver_heat_capacity = giver.heat_capacity()
		var/combined_heat_capacity = giver_heat_capacity + self_heat_capacity
		if(combined_heat_capacity)
			temperature = (giver.temperature * giver_heat_capacity + temperature * self_heat_capacity) / combined_heat_capacity

	var/list/cached_moles = moles //accessing datum vars is slower than proc vars
	var/list/giver_moles = giver.moles
	//gas transfer
	for(var/gas_id, value in giver_moles)
		cached_moles[gas_id] += value

	return 1

/datum/gas_mixture/proc/remove(amount)
	//Proportionally removes amount of gas from the gas_mixture
	//Returns: gas_mixture with the gases removed
	var/list/cached_moles = moles
	var/sum = values_sum(cached_moles)
	amount = min(amount, sum) //Can not take more air than tile has!
	if(amount <= 0)
		return null
	var/datum/gas_mixture/removed = new type
	var/list/removed_moles = removed.moles //accessing datum vars is slower than proc vars

	removed.temperature = temperature
	for(var/id, value in cached_moles)
		removed_moles[id] = QUANTIZE((value / sum) * amount)
		cached_moles[id] -= removed_moles[id]
	garbage_collect()

	return removed

/datum/gas_mixture/proc/remove_ratio(ratio)
	//Proportionally removes amount of gas from the gas_mixture
	//Returns: gas_mixture with the gases removed
	if(ratio <= 0)
		return null
	ratio = min(ratio, 1)

	var/list/cached_moles = moles
	var/datum/gas_mixture/removed = new type
	var/list/removed_moles = removed.moles //accessing datum vars is slower than proc vars

	removed.temperature = temperature
	for(var/id, value in cached_moles)
		removed_moles[id] = QUANTIZE(value * ratio)
		cached_moles[id] -= removed_moles[id]

	garbage_collect()

	return removed

/datum/gas_mixture/proc/copy()
	//Creates new, identical gas mixture
	//Returns: duplicate gas mixture
	var/list/cached_moles = moles
	var/datum/gas_mixture/copy = new type
	var/list/copy_moles = copy.moles

	copy.temperature = temperature
	for(var/id, value in cached_moles)
		copy_moles[id] = value

	return copy


/datum/gas_mixture/proc/copy_from(datum/gas_mixture/sample)
	//Copies variables from sample
	//Returns: 1 if we are mutable, 0 otherwise
	var/list/cached_moles = moles //accessing datum vars is slower than proc vars
	var/list/sample_moles = sample.moles

	temperature = sample.temperature
	cached_moles.Cut()
	for(var/id, value in sample_moles)
		cached_moles[id] = value

	return 1

	///Copies all gas info from the turf into the gas list along with temperature
	///Returns: TRUE if we are mutable, FALSE otherwise
/datum/gas_mixture/proc/copy_from_turf(turf/model)
	parse_gas_string(model.initial_gas_mix)

	//acounts for changes in temperature
	var/turf/model_parent = model.parent_type
	if(model.temperature != initial(model.temperature) || model.temperature != initial(model_parent.temperature))
		temperature = model.temperature

	return TRUE

/datum/gas_mixture/proc/parse_gas_string(gas_string)
	gas_string = SSair.preprocess_gas_string(gas_string)

	// hippie -- every open turf parses its initial_gas_mix at init (~60k of them, from a few dozen distinct strings), so
	// each string is parsed once: list(temperature or null, list(gas path = moles))
	var/list/parsed = istext(gas_string) ? GLOB.parsed_gas_strings[gas_string] : null
	if(!parsed)
		var/list/gas = params2list(gas_string)
		var/parsed_temperature
		if(gas["TEMP"])
			parsed_temperature = text2num(gas["TEMP"])
			gas -= "TEMP"
		var/list/parsed_moles = list()
		for(var/id, value in gas)
			var/path = id
			if(!ispath(path))
				path = gas_id2path(path) //a lot of these strings can't have embedded expressions (especially for mappers), so support for IDs needs to stick around
			parsed_moles[path] = text2num(value)
		parsed = list(parsed_temperature, parsed_moles)
		if(istext(gas_string) && length(GLOB.parsed_gas_strings) < 500) // bounded: atmos_spawn_air() callers build strings with any amounts
			GLOB.parsed_gas_strings[gas_string] = parsed

	if(!isnull(parsed[1]))
		temperature = parsed[1]
		temperature_archived = temperature
	var/list/cached_moles = moles
	var/list/cached_moles_archive = moles_archive
	cached_moles.Cut()
	cached_moles_archive.Cut()
	var/list/parsed_moles = parsed[2]
	for(var/path in parsed_moles)
		cached_moles[path] = parsed_moles[path]
		cached_moles_archive[path] = 0
	return 1

///Gas strings parse_gas_string() has parsed: gas string = list(temperature or null, list(gas path = moles))
GLOBAL_LIST_EMPTY(parsed_gas_strings)

/datum/gas_mixture/proc/share(datum/gas_mixture/sharer, our_coeff = 1, sharer_coeff = 1)
	//Performs air sharing calculations between two gas_mixtures.
	//our_coeff/sharer_coeff scale how much of the delta moves each way - replaces the old atmos_adjacent_turfs count.
	//Returns: amount of gas exchanged (+ if sharer received)
	var/list/cached_moles = moles
	var/list/cached_moles_archive = moles_archive
	var/list/sharer_moles = sharer.moles
	var/list/sharer_moles_archive = sharer.moles_archive

	var/temperature_delta = temperature_archived - sharer.temperature_archived
	var/abs_temperature_delta = abs(temperature_delta)

	var/old_self_heat_capacity = 0
	var/old_sharer_heat_capacity = 0
	if(abs_temperature_delta > MINIMUM_TEMPERATURE_DELTA_TO_CONSIDER)
		old_self_heat_capacity = heat_capacity()
		old_sharer_heat_capacity = sharer.heat_capacity()

	var/heat_capacity_self_to_sharer = 0 //heat capacity of the moles transferred from us to the sharer
	var/heat_capacity_sharer_to_self = 0 //heat capacity of the moles transferred from the sharer to us

	var/moved_moles = 0
	var/abs_moved_moles = 0

	//GAS TRANSFER

	//Prep - create gases not in the other mixture's cache
	for(var/id in sharer_moles - cached_moles)
		cached_moles[id] = 0
		cached_moles_archive[id] = 0
	for(var/id in cached_moles - sharer_moles)
		sharer_moles[id] = 0
		sharer_moles_archive[id] = 0

	var/list/cached_specific_heat = GAS_META[META_GAS_SPECIFIC_HEAT]
	for(var/id in cached_moles) //transfer gases
		var/delta = QUANTIZE(cached_moles_archive[id] - sharer_moles_archive[id]) //the amount of gas that gets moved between the mixtures

		if(!delta)
			continue

		// If we have more gas then they do, gas is moving from us to them
		// This means we want to scale it by our coeff. Vis versa for their case
		if(delta > 0)
			delta *= our_coeff
		else
			delta *= sharer_coeff

		if(abs_temperature_delta > MINIMUM_TEMPERATURE_DELTA_TO_CONSIDER)
			var/gas_heat_capacity = delta * cached_specific_heat[id]
			if(delta > 0)
				heat_capacity_self_to_sharer += gas_heat_capacity
			else
				heat_capacity_sharer_to_self -= gas_heat_capacity //subtract here instead of adding the absolute value because we know that delta is negative.

		cached_moles[id] -= delta
		sharer_moles[id] += delta
		moved_moles += delta
		abs_moved_moles += abs(delta)

	last_share = abs_moved_moles

	//THERMAL ENERGY TRANSFER
	if(abs_temperature_delta > MINIMUM_TEMPERATURE_DELTA_TO_CONSIDER)
		var/new_self_heat_capacity = old_self_heat_capacity + heat_capacity_sharer_to_self - heat_capacity_self_to_sharer
		var/new_sharer_heat_capacity = old_sharer_heat_capacity + heat_capacity_self_to_sharer - heat_capacity_sharer_to_self

		//transfer of thermal energy (via changed heat capacity) between self and sharer
		if(new_self_heat_capacity > MINIMUM_HEAT_CAPACITY)
			temperature = (old_self_heat_capacity*temperature - heat_capacity_self_to_sharer*temperature_archived + heat_capacity_sharer_to_self*sharer.temperature_archived)/new_self_heat_capacity

		if(new_sharer_heat_capacity > MINIMUM_HEAT_CAPACITY)
			sharer.temperature = (old_sharer_heat_capacity*sharer.temperature-heat_capacity_sharer_to_self*sharer.temperature_archived + heat_capacity_self_to_sharer*temperature_archived)/new_sharer_heat_capacity
		//thermal energy of the system (self and sharer) is unchanged

			if(abs(old_sharer_heat_capacity) > MINIMUM_HEAT_CAPACITY)
				if(abs(new_sharer_heat_capacity/old_sharer_heat_capacity - 1) < 0.1) // <10% change in sharer heat capacity
					temperature_share(sharer, OPEN_HEAT_TRANSFER_COEFFICIENT)

	if(length(cached_moles ^ sharer_moles)) //if all gases were present in both mixtures, we know that no gases are 0
		garbage_collect(cached_moles - sharer_moles) //any gases the sharer had, we are guaranteed to have. gases that it didn't have we are not.
		sharer.garbage_collect(sharer_moles - cached_moles) //the reverse is equally true
	if (initial(sharer.gc_share))
		sharer.garbage_collect()

	if(temperature_delta > MINIMUM_TEMPERATURE_TO_MOVE || abs(moved_moles) > MINIMUM_MOLES_DELTA_TO_MOVE)
		var/our_moles = values_sum(cached_moles)
		var/their_moles = values_sum(sharer_moles)
		return (temperature_archived*(our_moles + moved_moles) - sharer.temperature_archived*(their_moles - moved_moles)) * R_IDEAL_GAS_EQUATION / volume

///Performs temperature sharing calculations (via conduction) between two gas_mixtures assuming only 1 boundary length
///Returns: new temperature of the sharer
/datum/gas_mixture/proc/temperature_share(datum/gas_mixture/sharer, conduction_coefficient, sharer_temperature, sharer_heat_capacity)
	//transfer of thermal energy (via conduction) between self and sharer
	if(sharer)
		sharer_temperature = sharer.temperature_archived
	var/temperature_delta = temperature_archived - sharer_temperature
	if(abs(temperature_delta) > MINIMUM_TEMPERATURE_DELTA_TO_CONSIDER)
		var/self_heat_capacity = heat_capacity(TRUE)
		sharer_heat_capacity = sharer_heat_capacity || sharer.heat_capacity(TRUE)

		if((sharer_heat_capacity > MINIMUM_HEAT_CAPACITY) && (self_heat_capacity > MINIMUM_HEAT_CAPACITY))
			var/heat = conduction_coefficient*temperature_delta* \
				(self_heat_capacity*sharer_heat_capacity/(self_heat_capacity+sharer_heat_capacity))

			temperature = max(temperature - heat/self_heat_capacity, TCMB)
			sharer_temperature = max(sharer_temperature + heat/sharer_heat_capacity, TCMB)
			if(sharer)
				sharer.temperature = sharer_temperature
				if (initial(sharer.gc_share))
					sharer.garbage_collect()
	return sharer_temperature
	//thermal energy of the system (self and sharer) is unchanged

/datum/gas_mixture/proc/compare(datum/gas_mixture/sample)
	//Compares sample to self to see if within acceptable ranges that group processing may be enabled
	//Returns: a string indicating what check failed, or "" if check passes
	var/list/sample_moles = sample.moles //accessing datum vars is slower than proc vars
	var/list/cached_moles = moles

	for(var/id in cached_moles | sample_moles) // compare gases from either mixture
		var/gas_moles = cached_moles[id] || 0
		var/sample_moles_val = sample_moles[id] || 0
		var/delta = abs(gas_moles - sample_moles_val)
		if(delta > MINIMUM_MOLES_DELTA_TO_MOVE && \
			delta > gas_moles * MINIMUM_AIR_RATIO_TO_MOVE)
			return id

	var/our_moles = values_sum(cached_moles)
	if(our_moles > MINIMUM_MOLES_DELTA_TO_MOVE) //Don't consider temp if there's not enough mols
		var/temp = temperature
		var/sample_temp = sample.temperature

		var/temperature_delta = abs(temp - sample_temp)
		if(temperature_delta > MINIMUM_TEMPERATURE_DELTA_TO_SUSPEND)
			return "temp"

	return ""

/datum/gas_mixture/proc/react(datum/holder)
	//Performs various reactions such as combustion or fusion (LOL)
	//Returns: 1 if any reaction took place; 0 otherwise
	. = NO_REACTION
	var/list/cached_moles = moles
	if(!length(cached_moles))
		return
	// Most mixes (plain air, idle pipenets) hold no gas that any reaction keys on, so check the few gases present
	// against the index before building anything. See init_gas_reactions_by_key().
	var/list/reactions_by_key = SSair.gas_reactions_by_key
	var/list/reactions
	var/key_gas_count = 0
	for(var/gas_id, amount in cached_moles)
		if(!amount)
			continue
		var/list/keyed = reactions_by_key[gas_id]
		if(keyed)
			reactions = keyed
			key_gas_count++
	if(!key_gas_count)
		return
	if(key_gas_count > 1) // candidates from several key gases, so keep the global priority order across all of them
		reactions = list()
		for(var/datum/gas_reaction/reaction as anything in SSair.gas_reactions)
			if(cached_moles[reaction.major_gas])
				reactions += reaction

	reaction_results = new
	//It might be worth looking into updating these after each reaction, but it changes things a lot, so be careful
	var/temp = temperature
	var/ener = THERMAL_ENERGY(src)

	reaction_loop:
		for(var/r in reactions)
			var/datum/gas_reaction/reaction = r

			var/list/min_reqs = reaction.min_requirements
			if((min_reqs["TEMP"] && temp < min_reqs["TEMP"]) \
			|| (min_reqs["ENER"] && ener < min_reqs["ENER"]))
				continue

			for(var/id, req_value in min_reqs)
				if (id == "TEMP" || id == "ENER")
					continue
				if(!cached_moles[id] || cached_moles[id] < req_value)
					continue reaction_loop

			//at this point, all requirements for the reaction are satisfied. we can now react()

			. |= reaction.react(src, holder)

			if (. & STOP_REACTIONS)
				break

	if(.) //If we changed the mix to any degree, or if we stopped reacting
		garbage_collect()

//Takes the amount of the gas you want to PP as an argument
//So I don't have to do some hacky switches/defines/magic strings
//eg:
//Tox_PP = get_partial_pressure(gas_mixture.moles[/datum/gas/plasma])
//O2_PP = get_partial_pressure(gas_mixture.moles[/datum/gas/oxygen])

/datum/gas_mixture/proc/get_breath_partial_pressure(gas_pressure)
	return (gas_pressure * R_IDEAL_GAS_EQUATION * temperature) / BREATH_VOLUME
//inverse
/datum/gas_mixture/proc/get_true_breath_pressure(partial_pressure)
	return (partial_pressure * BREATH_VOLUME) / (R_IDEAL_GAS_EQUATION * temperature)

//Mathematical proofs:
/*
get_breath_partial_pressure(gas_pp) --> gas_pp/total_moles()*breath_pp = pp
get_true_breath_pressure(pp) --> gas_pp = pp/breath_pp*total_moles()

10/20*5 = 2.5
10 = 2.5/5*20
**/

/// Pumps gas from src to output_air. Amount depends on target_pressure
/datum/gas_mixture/proc/pump_gas_to(datum/gas_mixture/output_air, target_pressure)
	var/output_starting_pressure = output_air.return_pressure()

	if((target_pressure - output_starting_pressure) < 0.01)
		//No need to pump gas if target is already reached!
		return FALSE

	//Calculate necessary moles to transfer using PV=nRT
	if((total_moles() > 0) && (temperature>0))
		var/pressure_delta = target_pressure - output_starting_pressure
		var/transfer_moles = (pressure_delta*output_air.volume)/(temperature * R_IDEAL_GAS_EQUATION)

		//Actually transfer the gas
		var/datum/gas_mixture/removed = remove(transfer_moles)
		output_air.merge(removed)
		return TRUE
	return FALSE

/// Releases gas from src to output air. This means that it can not transfer air to gas mixture with higher pressure.
/datum/gas_mixture/proc/release_gas_to(datum/gas_mixture/output_air, target_pressure)
	var/output_starting_pressure = output_air.return_pressure()
	var/input_starting_pressure = return_pressure()

	if(output_starting_pressure >= min(target_pressure,input_starting_pressure-10))
		//No need to pump gas if target is already reached or input pressure is too low
		//Need at least 10 KPa difference to overcome friction in the mechanism
		return FALSE

	//Calculate necessary moles to transfer using PV = nRT
	if((total_moles() > 0) && (temperature>0))
		var/pressure_delta = min(target_pressure - output_starting_pressure, (input_starting_pressure - output_starting_pressure)/2)
		//Can not have a pressure delta that would cause output_pressure > input_pressure

		var/transfer_moles = (pressure_delta*output_air.volume)/(temperature * R_IDEAL_GAS_EQUATION)

		//Actually transfer the gas
		var/datum/gas_mixture/removed = remove(transfer_moles)
		output_air.merge(removed)

		return TRUE
	return FALSE
