// The tile atmos engine: SSair's turf processing done in one native call per atmos tick, in place of LINDA's
// process_cell() and excited groups. The engine is tools/atmos_engine (Rust), built into hippie_atmos.dll.
//
// - Each turf's air stays the only copy of it. Every tick SSair packs the awake turfs and their neighbours into
//   flat number lists, the engine works out the sharing between them from the tick's starting values, and SSair
//   writes back only the turfs that changed. Nothing is cached, so nothing can go stale.
// - Only awake turfs do any work, and a turf goes back to sleep once nothing around it has moved more than
//   MINIMUM_MOLES_DELTA_TO_MOVE for TILE_ENGINE_QUIET_TICKS ticks. A sleeping turf wakes when a neighbour's air
//   differs from it by as much as LINDA's compare() would act on, or when anything calls add_to_active() on it.
// - Gas moves at LINDA's speed (the same share() maths), every move takes from one turf what it gives the other,
//   and the order turfs come in doesn't change anything.
// - The engine also says which turfs need what after the tick: wind, a reaction check, a new gas overlay, heat
//   through walls. SSair only does those for the turfs that need them.
// - If the library is missing or a different version, SSair runs LINDA as before. Boot with
//   -params "atmos-engine=linda" to choose LINDA anyway (for comparing the two).

#define TILE_ENGINE_LIB (world.system_type == UNIX ? "./libhippie_atmos.so" : "hippie_atmos")
/// The version of the lists passed back and forth; the library has to report this one
#define TILE_ENGINE_VERSION 5
/// Sharing passes per tick. LINDA's gas got further than one turf a tick; three passes matched how fast it spread and
/// vented in the atmos bench (one pass vented about half as much to space in 90 seconds). -params
/// "atmos-engine-passes=N" overrides it, for trying others.
#define TILE_ENGINE_PASSES 3
/// How many ticks in a row an awake turf has to be quiet before it sleeps. -params "atmos-engine-quiet=N" overrides it.
#define TILE_ENGINE_QUIET_TICKS (SSair.tile_engine_quiet_ticks)
/// Numbers per turf in the packed list after its gases: temperature, adjacent turf count, kind, awake, drawn overlay
/// key, ticks since its last big share
#define TILE_ENGINE_EXTRAS 6
/// What tile_engine_calm says for a turf that just woke: it doesn't hold up the group it joins from being evened out
#define TILE_ENGINE_CALM 1000

/datum/controller/subsystem/air
	/// TRUE when turfs are processed by the tile engine instead of LINDA
	var/tile_engine = FALSE
	/// How many ticks in a row an awake turf has to be quiet before it sleeps. 6 got thin gas clouds spreading about as
	/// far as LINDA's in the atmos bench; 3 stopped them early, 11 cost more for no closer match.
	var/tile_engine_quiet_ticks = 6
	/// Gas typepath -> its position in the packed lists
	var/list/tile_engine_gas_index
	/// Position -> gas typepath
	var/list/tile_engine_gas_types
	var/tile_engine_gases = 0
	/// Planetary gas string -> its mix's number for the engine (from 0)
	var/list/tile_engine_planetary_index = list()
	/// Every planetary mix's gases and temperature, in the order of tile_engine_planetary_index
	var/list/tile_engine_planetary_data = list()
	/// What the last tick handled, for the stat panel and the atmos bench
	var/tile_engine_awake = 0
	var/tile_engine_packed = 0
	var/tile_engine_pairs = 0
	var/tile_engine_changed = 0
	/// Real ms spent so far packing, in the engine itself, and following up, for the atmos bench
	var/tile_engine_pack_ms = 0
	var/tile_engine_native_ms = 0
	var/tile_engine_apply_ms = 0

/turf/open
	/// Ticks in a row this turf has been quiet under the tile engine
	var/tile_engine_quiet = 0
	/// The overlay key the tile engine last drew this turf with, -1 for none
	var/tile_engine_drawn = -1
	/// times_fired when a reaction last happened here, so it stays awake
	var/tile_engine_reacted = 0
	/// Ticks since this turf last shared more than MINIMUM_AIR_TO_SUSPEND. A group of awake turfs that all got past
	/// EXCITED_GROUP_BREAKDOWN_CYCLES gets evened out, like LINDA's excited groups did.
	var/tile_engine_calm = TILE_ENGINE_CALM

/datum/controller/subsystem/air/Initialize(timeofday)
	. = ..()
	tile_engine_setup()

/datum/controller/subsystem/air/stat_entry(msg)
	if(tile_engine)
		msg += "Tile engine: [tile_engine_awake] awake, [tile_engine_packed] packed, [tile_engine_pairs] pairs, [tile_engine_changed] changed | "
	return ..()

/// Turns the tile engine on if the library is there and it's the version this code expects
/datum/controller/subsystem/air/proc/tile_engine_setup()
	tile_engine = FALSE
	tile_engine_quiet_ticks = text2num(world.params["atmos-engine-quiet"]) || tile_engine_quiet_ticks
	if(world.params["atmos-engine"] == "linda")
		log_world("Atmos: running LINDA, the tile engine was turned off with atmos-engine=linda")
		return
	if(world.system_type != UNIX && !fexists("hippie_atmos.dll"))
		log_world("Atmos: running LINDA, hippie_atmos.dll isn't there (build it with tools/atmos_engine/build.sh)")
		return
	try
		var/version = call_ext(TILE_ENGINE_LIB, "byond:atmos_engine_version")()
		if(version != TILE_ENGINE_VERSION)
			log_world("Atmos: running LINDA, hippie_atmos is version [version] and this code wants [TILE_ENGINE_VERSION]")
			return
		tile_engine_gas_index = list()
		tile_engine_gas_types = list()
		var/list/specific_heat = GAS_META[META_GAS_SPECIFIC_HEAT]
		var/list/moles_visible = GAS_META[META_GAS_MOLES_VISIBLE]
		var/static/list/nonoverlaying_gases = typecache_of_gases_with_no_overlays()
		var/list/heats = list()
		var/list/visible = list()
		for(var/gas_type in specific_heat)
			tile_engine_gas_types += gas_type
			tile_engine_gas_index[gas_type] = length(tile_engine_gas_types)
			heats += specific_heat[gas_type]
			visible += (nonoverlaying_gases[gas_type] || isnull(moles_visible[gas_type])) ? -1 : moles_visible[gas_type]
		tile_engine_gases = length(tile_engine_gas_types)
		var/list/settings = list(tile_engine_gases)
		settings += heats
		settings += visible
		settings += list(MOLES_GAS_VISIBLE_STEP, TOTAL_VISIBLE_STATES)
		settings += list(MINIMUM_MOLES_DELTA_TO_MOVE, MINIMUM_AIR_RATIO_TO_MOVE, MINIMUM_TEMPERATURE_DELTA_TO_SUSPEND, \
			MINIMUM_TEMPERATURE_DELTA_TO_CONSIDER, MINIMUM_TEMPERATURE_TO_MOVE, OPEN_HEAT_TRANSFER_COEFFICIENT, HEAT_CAPACITY_VACUUM, \
			MINIMUM_HEAT_CAPACITY, TCMB, R_IDEAL_GAS_EQUATION, CELL_VOLUME, MOLAR_ACCURACY, MINIMUM_MOLE_COUNT, \
			MINIMUM_TEMPERATURE_START_SUPERCONDUCTION, M_CELL_WITH_RATIO, MINIMUM_AIR_TO_SUSPEND, EXCITED_GROUP_BREAKDOWN_CYCLES, \
			text2num(world.params["atmos-engine-passes"]) || TILE_ENGINE_PASSES)
		settings += length(gas_reactions)
		for(var/datum/gas_reaction/reaction as anything in gas_reactions)
			var/list/needs = reaction.min_requirements || list()
			var/list/gas_needs = list()
			for(var/requirement in needs)
				if(requirement == "TEMP" || requirement == "ENER")
					continue
				gas_needs += tile_engine_gas_index[requirement]
				gas_needs += needs[requirement]
			settings += list(needs["TEMP"] || 0, needs["ENER"] || 0, length(gas_needs) / 2)
			settings += gas_needs
		var/gases = call_ext(TILE_ENGINE_LIB, "byond:atmos_engine_setup")(settings)
		if(gases != tile_engine_gases)
			log_world("Atmos: running LINDA, the tile engine didn't take its settings (said [gases], see the server's error output)")
			return
	catch(var/exception/error)
		log_world("Atmos: running LINDA, the tile engine failed to start: [error]")
		return
	tile_engine = TRUE
	// LINDA's excited groups from roundstart go, the engine doesn't use them
	for(var/datum/excited_group/group as anything in excited_groups)
		group.garbage_collect()
	excited_groups.Cut()
	log_world("Atmos: tile engine on, [tile_engine_gases] gases, [length(gas_reactions)] reactions")

/// The engine's number for a planetary gas string's mix, adding it if it's new
/datum/controller/subsystem/air/proc/tile_engine_planetary(gas_string)
	. = tile_engine_planetary_index[gas_string]
	if(!isnull(.))
		return
	var/datum/gas_mixture/planet = planetary[gas_string]
	if(!planet)
		planet = new /datum/gas_mixture/immutable/planetary
		var/datum/gas_mixture/immutable/planetary/mix = planet
		mix.parse_string_immutable(gas_string)
		planetary[gas_string] = mix
	var/list/planet_moles = planet.moles
	for(var/gas_type in tile_engine_gas_types)
		tile_engine_planetary_data += planet_moles[gas_type] || 0
	tile_engine_planetary_data += planet.temperature
	. = length(tile_engine_planetary_index)
	tile_engine_planetary_index[gas_string] = .

/// One atmos tick of turf processing: pack the awake turfs and their neighbours, run the engine, follow up
/datum/controller/subsystem/air/proc/tile_engine_process()
	var/list/awake = active_turfs
	tile_engine_awake = length(awake)
	if(!tile_engine_awake)
		tile_engine_packed = 0
		tile_engine_pairs = 0
		tile_engine_changed = 0
		return
	var/timer = TICK_USAGE_REAL
	var/gases = tile_engine_gases
	var/stride = gases + TILE_ENGINE_EXTRAS
	var/list/gas_index = tile_engine_gas_index
	var/list/index_of = list()
	var/list/turf/open/packed = list()
	var/list/tiles = list()
	var/list/pairs = list()

	// Awake turfs first, so every index up to awake_count is one. Space and other air that never changes has
	// nothing to work out, so it goes straight back to sleep (it's still packed as a neighbour below).
	var/list/fixed = list()
	for(var/turf/open/T as anything in awake)
		var/datum/gas_mixture/air = T.air
		if(!air || istype(air, /datum/gas_mixture/immutable))
			fixed += T
			continue
		packed += T
		index_of[T] = length(packed)
		var/base = length(tiles)
		tiles.len += stride
		for(var/gas_type, amount in air.moles)
			tiles[base + gas_index[gas_type]] = amount
		tiles[base + gases + 1] = air.temperature
		tiles[base + gases + 2] = length(T.atmos_adjacent_turfs)
		tiles[base + gases + 3] = T.planetary_atmos ? 3 + tile_engine_planetary(T.initial_gas_mix) : 0
		tiles[base + gases + 4] = 1
		tiles[base + gases + 5] = T.tile_engine_drawn
		tiles[base + gases + 6] = T.active_hotspot ? 0 : T.tile_engine_calm // a fire keeps its group from being evened out
	var/awake_count = length(packed)
	if(length(fixed))
		for(var/turf/open/T as anything in fixed)
			T.excited = FALSE
		active_turfs -= fixed
		tile_engine_awake = awake_count

	// Then their neighbours, and every pair once
	for(var/i in 1 to awake_count)
		var/turf/open/T = packed[i]
		for(var/turf/open/neighbour as anything in T.atmos_adjacent_turfs)
			var/j = index_of[neighbour]
			if(!j)
				var/datum/gas_mixture/air = neighbour.air
				if(!air)
					continue
				packed += neighbour
				j = length(packed)
				index_of[neighbour] = j
				var/base = length(tiles)
				tiles.len += stride
				for(var/gas_type, amount in air.moles)
					tiles[base + gas_index[gas_type]] = amount
				tiles[base + gases + 1] = air.temperature
				tiles[base + gases + 2] = length(neighbour.atmos_adjacent_turfs)
				var/kind = 0
				if(istype(air, /datum/gas_mixture/immutable))
					kind = istype(air, /datum/gas_mixture/immutable/space) ? 1 : 2
				else if(neighbour.planetary_atmos)
					kind = 3 + tile_engine_planetary(neighbour.initial_gas_mix)
				tiles[base + gases + 3] = kind
				tiles[base + gases + 4] = 0
				tiles[base + gases + 5] = neighbour.tile_engine_drawn
				tiles[base + gases + 6] = TILE_ENGINE_CALM
			else if(j <= awake_count && j < i)
				continue // an awake turf earlier on already paired with this one
			pairs += i
			pairs += j
	tile_engine_packed = length(packed)
	tile_engine_pairs = length(pairs) / 2

	var/list/result = list()
	var/status
	tile_engine_pack_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer)
	timer = TICK_USAGE_REAL
	try
		status = call_ext(TILE_ENGINE_LIB, "byond:atmos_engine_tick")(tiles, pairs, tile_engine_planetary_data, result)
	catch(var/exception/error)
		status = "[error]"
	tile_engine_native_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer)
	timer = TICK_USAGE_REAL
	if(status != 1)
		tile_engine = FALSE
		log_world("Atmos: the tile engine failed ([status], see the server's error output), switching to LINDA")
		stack_trace("Atmos: the tile engine failed ([status]), switching to LINDA")
		return

	// Changed turfs: the tick's starting air becomes the archive, like archive() did, and the new air goes in
	var/list/gas_types = tile_engine_gas_types
	var/at = 1
	var/count = result[at++]
	tile_engine_changed = count
	var/list/turf/open/exposed = list()
	for(var/k in 1 to count)
		var/turf/open/T = packed[result[at++]]
		exposed += T
		T.air_changed_at = times_fired // wakes idle machines on it (idle_machines.dm)
		var/datum/gas_mixture/air = T.air
		air.moles_archive = air.moles
		var/list/new_moles = list()
		var/present = result[at++] // only the gases it has, as gas index and moles
		for(var/gas in 1 to present)
			new_moles[gas_types[result[at]]] = result[at + 1]
			at += 2
		air.moles = new_moles
		air.temperature_archived = air.temperature
		air.temperature = result[at++]
		T.archived_cycle = times_fired
		T.temperature_archived = T.temperature

	// Wind, as consider_pressure_difference() records it. A turf whose pressure_difference is still 0 isn't in
	// high_pressure_delta (process_high_pressure_delta() zeroes it as it takes a turf out), so it goes straight on
	// the end instead of searching the whole list with |= for every windy turf.
	count = result[at++]
	for(var/k in 1 to count)
		var/turf/open/T = packed[result[at]]
		var/difference = result[at + 2]
		if(!T.pressure_difference)
			high_pressure_delta += T
		if(difference > T.pressure_difference)
			T.pressure_direction = get_dir(T, packed[result[at + 1]])
			T.pressure_difference = difference
		at += 3

	// Neighbours with enough difference to wake up
	count = result[at++]
	for(var/k in 1 to count)
		var/turf/open/woken = packed[result[at++]]
		woken.tile_engine_calm = TILE_ENGINE_CALM
		add_to_active(woken)

	// Quiet awake turfs, sleeping the ones that have been quiet long enough. Reactions go first so a turf that's
	// burning stays awake.
	var/quiet_at = at
	count = result[at++]
	at += count
	var/react_count = result[at++]
	for(var/k in 1 to react_count)
		var/turf/open/T = packed[result[at++]]
		var/datum/gas_mixture/air = T.air
		if(air.react(T))
			T.tile_engine_reacted = times_fired
			T.update_visuals()
			T.tile_engine_drawn = -1 // drawn from after the reaction, so the next tick checks it again
			exposed |= T
	var/quiet_count = result[quiet_at]
	var/next_quiet = quiet_count ? result[quiet_at + 1] : 0
	var/quiet_seen = 0
	var/list/sleepers = list()
	for(var/i in 1 to awake_count)
		var/turf/open/T = packed[i]
		if(i != next_quiet)
			T.tile_engine_quiet = 0
			continue
		quiet_seen++
		next_quiet = quiet_seen < quiet_count ? result[quiet_at + 1 + quiet_seen] : 0
		if(T.tile_engine_reacted == times_fired || T.active_hotspot)
			T.tile_engine_quiet = 0
			continue
		if(++T.tile_engine_quiet >= TILE_ENGINE_QUIET_TICKS)
			T.tile_engine_quiet = 0
			T.tile_engine_calm = TILE_ENGINE_CALM
			T.excited = FALSE
			sleepers += T
	if(length(sleepers))
		active_turfs -= sleepers

	// Gas overlays that would look different now
	count = result[at++]
	for(var/k in 1 to count)
		var/turf/open/T = packed[result[at]]
		if(T.tile_engine_reacted != times_fired)
			T.update_visuals()
			T.tile_engine_drawn = result[at + 1]
		at += 2

	// Hot enough to conduct heat through walls
	count = result[at++]
	for(var/k in 1 to count)
		var/turf/open/T = packed[result[at++]]
		T.consider_superconductivity(TRUE)

	// Calm counts go up for every awake turf, and back to 0 for the ones that had a big share. A burning turf stays at
	// 0, so its group isn't evened out while it burns and gets EXCITED_GROUP_BREAKDOWN_CYCLES after: LINDA's hotspots
	// reset their excited group's cooldowns the same way. Evening out a group with a fire in it spread the fire's heat
	// over the whole group at once and lit everything there was to burn.
	for(var/i in 1 to awake_count)
		var/turf/open/T = packed[i]
		if(T.active_hotspot)
			T.tile_engine_calm = 0
		else if(T.tile_engine_calm < TILE_ENGINE_CALM)
			T.tile_engine_calm++
	count = result[at++]
	for(var/k in 1 to count)
		var/turf/open/T = packed[result[at++]]
		T.tile_engine_calm = 0

	// Groups that just got evened out start counting again, and sleep next tick if nothing moves
	count = result[at++]
	for(var/k in 1 to count)
		var/turf/open/T = packed[result[at++]]
		if(T.excited)
			T.tile_engine_calm = 0
			T.tile_engine_quiet = TILE_ENGINE_QUIET_TICKS - 1

	// What's on a turf whose air changed feels its new temperature. LINDA exposed every active turf every tick, but
	// all that does is check whether things there should start or stop reacting to the air (check_atmos_process()),
	// which only changes when the air does; anything that moves onto a turf checks on arrival.
	for(var/turf/open/T as anything in exposed)
		var/datum/gas_mixture/air = T.air
		T.temperature_expose(air, air.temperature)
	tile_engine_apply_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer)

#undef TILE_ENGINE_LIB
#undef TILE_ENGINE_VERSION
#undef TILE_ENGINE_QUIET_TICKS
#undef TILE_ENGINE_EXTRAS
#undef TILE_ENGINE_CALM
#undef TILE_ENGINE_PASSES
