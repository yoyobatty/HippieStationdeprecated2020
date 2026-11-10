// The tile atmos engine: LINDA's process_cell() done natively, all of it in one go per atmos tick. The engine is
// tools/atmos_engine (Rust), built into hippie_atmos.dll.
//
// - The maths, the order turfs go in and LINDA's quirks are all process_cell()'s, so air behaves the way it always has.
//   Excited groups stay in DM as they were: the engine says who joins up, and process_excited_groups() does the rest.
// - Every tick SSair packs the awake turfs, the engine asks for the turfs next to them, and next to any it wakes, and the
//   engine writes back what changed. The engine keeps each turf's kind and neighbours, and its air as DM holds it after
//   the tick: a turf only sends its air again if DM has touched it since (air_touched, set wherever DM hands out or
//   changes a turf's air: return_air(), assume_air(), reactions, excited groups, heat through walls). DM's air stays the
//   one everything else reads. -params "atmos-engine-air=shadow" sends every turf's air anyway and has the engine check
//   what it kept against it, which is how a way of changing air that doesn't say so gets found; "off" sends it all.
// - Reactions run after the sweep instead of during it, and the engine says which turfs need one, a new gas overlay or
//   heat through walls, so SSair only does those for the turfs that need them.
// - If the library is missing or a different version, or a tick fails, SSair runs LINDA as before. Everything LINDA needs
//   is kept up to date, so that can happen at any time. Boot with -params "atmos-engine=linda" to choose LINDA anyway
//   (for comparing the two).

#define TILE_ENGINE_LIB (GLOB.tile_engine_lib)
/// The library: hippie_atmos.dll, ./libhippie_atmos.so on Linux, or another build of it (-params "atmos-lib=hippie_atmos_test",
/// for testing a build while running servers have hippie_atmos.dll open)
GLOBAL_VAR_INIT(tile_engine_lib, world.params["atmos-lib"] || (world.system_type == UNIX ? "./libhippie_atmos.so" : "hippie_atmos"))
/// The version of the lists passed back and forth; the library has to report this one
#define TILE_ENGINE_VERSION 11

/datum/controller/subsystem/air
	/// TRUE when turfs are processed by the tile engine instead of LINDA
	var/tile_engine = FALSE
	/// TRUE keeps every machine running every tick even with the tile engine on (-params "atmos-idle=off", for testing)
	var/atmos_never_idle = FALSE
	/// Position -> gas typepath
	var/list/tile_engine_gas_types
	/// Planetary gas string -> its mix's number for the engine (from 0)
	var/list/tile_engine_planetary_index = list()
	/// Every planetary mix's gases and temperature, in the order of tile_engine_planetary_index
	var/list/tile_engine_planetary_data = list()
	/// How many excited groups there have been, for numbering them
	var/tile_engine_groups_made = 0
	/// times_fired the last time the engine went through any turfs
	var/tile_engine_swept_at = 0
	/// What the last tick handled, for the stat panel and the atmos bench
	var/tile_engine_awake = 0
	var/tile_engine_packed = 0
	var/tile_engine_rounds = 0
	var/tile_engine_changed = 0
	/// Running totals of those, and of turfs that had their turn, for the atmos bench
	var/tile_engine_total_packed = 0
	var/tile_engine_total_rounds = 0
	var/tile_engine_total_changed = 0
	var/tile_engine_total_turns = 0
	/// How many of the turfs packed so far had air that never changes (space, and planets' fixed air)
	var/tile_engine_total_immutable = 0
	/// Real ms spent so far packing, in the engine itself, and following up, for the atmos bench
	var/tile_engine_pack_ms = 0
	var/tile_engine_native_ms = 0
	var/tile_engine_apply_ms = 0
	/// The follow-up's time by part, for benches (stress_bench.dm)
	var/list/tile_engine_apply_parts = list("air" = 0, "turns" = 0, "groups" = 0, "wind" = 0, "react" = 0, "redraw" = 0, "hot" = 0)
	/// The engine keeps turfs' kinds and neighbours between ticks. This goes up every time it starts, and a turf whose
	/// tile_engine_sent is the same has nothing new to send. 0 turns that off (-params "atmos-engine-cache=0", for testing).
	var/tile_engine_generation = 0
	/// -params "atmos-engine-cache=shadow": every turf sends its kind and neighbours anyway, for the engine to check what it
	/// kept against
	var/tile_engine_cache_shadow = FALSE
	/// The engine writes the new air straight into turfs' gas lists, instead of handing it back for DM to write
	/// (-params "atmos-engine-writes=dm" turns that off, for testing)
	var/tile_engine_writes = FALSE
	/// The engine keeps turfs' air (an older library doesn't): "on", "shadow" (sends it all and has the engine check what it
	/// kept), or "off"
	var/tile_engine_air = "off"
	/// Goes up before each tick is packed and again once the engine has written its air: a turf touched at or after the clock
	/// it was last sent at sends its air again (/turf/open air_touched, tile_engine_air_sent)
	var/tile_engine_air_clock = 1
	/// The clock when the engine last started: air sent before that is gone
	var/tile_engine_air_epoch = 0
	/// Turfs whose air was sent this tick, and kept, so far (for benches)
	var/tile_engine_air_sent_count = 0
	var/tile_engine_air_kept_count = 0
	/// -params "atmos-engine-writes=check": the engine writes, then DM checks every value against what it would have written
	/// itself, and that no reference count changed. Counts of what was checked and what was wrong.
	var/list/tile_engine_writes_check

/turf
	/// SSair.tile_engine_generation when the tile engine was last sent our kind and neighbours, 0 if what it has is out of
	/// date (our atmos_adjacent_turfs changed since)
	var/tmp/tile_engine_sent = 0

/turf/open
	/// SSair.tile_engine_air_clock when DM last handed out or changed our air (return_air(), assume_air()...)
	var/tmp/air_touched = 0
	/// SSair.tile_engine_air_clock when the tile engine was last sent our air: it keeps it from then on, until we're touched
	var/tmp/tile_engine_air_sent = 0
	/// The overlay key the tile engine last drew this turf with, -1 for none
	var/tile_engine_drawn = -1
	/// times_fired when a reaction last redrew this turf
	var/tile_engine_reacted = 0

/datum/excited_group
	/// What the tile engine knows this group as
	var/tile_engine_number = 0

/datum/excited_group/New()
	tile_engine_number = ++SSair.tile_engine_groups_made
	return ..()

/datum/controller/subsystem/air/Initialize(timeofday)
	. = ..()
	tile_engine_setup()

/datum/controller/subsystem/air/stat_entry(msg)
	if(tile_engine)
		msg += "Tile engine: [tile_engine_awake] awake, [tile_engine_packed] packed, [tile_engine_rounds] rounds, [tile_engine_changed] changed | "
	return ..()

/// Turns the tile engine on if the library is there and it's the version this code expects
/datum/controller/subsystem/air/proc/tile_engine_setup()
	tile_engine = FALSE
	atmos_never_idle = world.params["atmos-idle"] == "off"
	if(world.params["atmos-idle-shadow"]) // idle_machines.dm: the old check runs the machines, the registry is set against it
		atmos_idle_shadow = list("agree" = 0, "only the old check ran it" = 0, "only the registry ran it" = 0)
	if(world.params["atmos-engine"] == "linda")
		log_world("Atmos: running LINDA, the tile engine was turned off with atmos-engine=linda")
		return
	if(world.system_type != UNIX && !fexists("[TILE_ENGINE_LIB].dll"))
		log_world("Atmos: running LINDA, [TILE_ENGINE_LIB].dll isn't there (build it with tools/atmos_engine/build.sh)")
		return
	try
		var/version = call_ext(TILE_ENGINE_LIB, "byond:atmos_engine_version")()
		if(version != TILE_ENGINE_VERSION)
			log_world("Atmos: running LINDA, hippie_atmos is version [version] and this code wants [TILE_ENGINE_VERSION]")
			return
		tile_engine_gas_types = list()
		var/list/gas_index = list()
		var/list/specific_heat = GAS_META[META_GAS_SPECIFIC_HEAT]
		var/list/moles_visible = GAS_META[META_GAS_MOLES_VISIBLE]
		var/static/list/nonoverlaying_gases = typecache_of_gases_with_no_overlays()
		var/list/heats = list()
		var/list/visible = list()
		for(var/gas_type in specific_heat)
			tile_engine_gas_types += gas_type
			gas_index[gas_type] = length(tile_engine_gas_types)
			heats += specific_heat[gas_type]
			visible += (nonoverlaying_gases[gas_type] || isnull(moles_visible[gas_type])) ? -1 : moles_visible[gas_type]
		var/list/settings = list(length(tile_engine_gas_types))
		settings += heats
		settings += visible
		settings += list(MOLES_GAS_VISIBLE_STEP, TOTAL_VISIBLE_STATES)
		settings += list(MINIMUM_MOLES_DELTA_TO_MOVE, MINIMUM_AIR_RATIO_TO_MOVE, MINIMUM_TEMPERATURE_DELTA_TO_SUSPEND, \
			MINIMUM_TEMPERATURE_DELTA_TO_CONSIDER, MINIMUM_TEMPERATURE_TO_MOVE, OPEN_HEAT_TRANSFER_COEFFICIENT, HEAT_CAPACITY_VACUUM, \
			MINIMUM_HEAT_CAPACITY, TCMB, R_IDEAL_GAS_EQUATION, CELL_VOLUME, MOLAR_ACCURACY, MINIMUM_MOLE_COUNT, \
			MINIMUM_TEMPERATURE_START_SUPERCONDUCTION, M_CELL_WITH_RATIO, MINIMUM_AIR_TO_SUSPEND, EXCITED_GROUP_DISMANTLE_CYCLES)
		settings += length(gas_reactions)
		for(var/datum/gas_reaction/reaction as anything in gas_reactions)
			var/list/needs = reaction.min_requirements || list()
			var/list/gas_needs = list()
			for(var/requirement in needs)
				if(requirement == "TEMP" || requirement == "ENER")
					continue
				gas_needs += gas_index[requirement]
				gas_needs += needs[requirement]
			settings += list(needs["TEMP"] || 0, needs["ENER"] || 0, length(gas_needs) / 2)
			settings += gas_needs
		var/gases = call_ext(TILE_ENGINE_LIB, "byond:atmos_engine_setup")(settings, tile_engine_gas_types)
		if(gases != length(tile_engine_gas_types))
			log_world("Atmos: running LINDA, the tile engine didn't take its settings (said [gases], see the server's error output)")
			return
	catch(var/exception/error)
		log_world("Atmos: running LINDA, the tile engine failed to start: [error]")
		return
	tile_engine = TRUE
	// A fresh start: the engine has no turfs yet, so every turf has to send its kind and neighbours again
	var/cache = world.params["atmos-engine-cache"]
	tile_engine_cache_shadow = cache == "shadow"
	tile_engine_generation = cache == "0" ? 0 : tile_engine_generation + 1
	tile_engine_write_setup()
	tile_engine_air_setup()
	log_world("Atmos: tile engine on, [length(tile_engine_gas_types)] gases, [length(gas_reactions)] reactions[tile_engine_generation ? "" : ", sending every turf's neighbours every tick"][tile_engine_cache_shadow ? ", checking what it keeps of turfs" : ""], keeping turfs' air: [tile_engine_air]")

/// Whether the engine keeps turfs' air (a library from before that hasn't got atmos_engine_kept_air()). A fresh start of the
/// engine has none kept, so the epoch moves past every turf's tile_engine_air_sent.
/datum/controller/subsystem/air/proc/tile_engine_air_setup()
	tile_engine_air = "off"
	var/wanted = world.params["atmos-engine-air"] || "on"
	if(wanted == "off")
		return
	try
		if(call_ext(TILE_ENGINE_LIB, "byond:atmos_engine_kept_air")() != 1)
			return
	catch
		return
	tile_engine_air = wanted == "shadow" ? "shadow" : "on"
	tile_engine_air_clock += 2
	tile_engine_air_epoch = tile_engine_air_clock

/// With atmos-engine-air=shadow, in the world log: how the kept air has checked out so far, and where it hasn't
/datum/controller/subsystem/air/proc/tile_engine_air_log()
	var/list/check = tile_engine_air_check()
	if(length(check) < 2)
		return
	var/list/where = list()
	for(var/i in 3 to length(check))
		var/turf/T = check[i]
		if(isturf(T))
			where += "[T.x],[T.y],[T.z] [get_area_name(T, TRUE)]"
	log_world("Atmos: kept air checked [check[1]] turfs, [check[2]] different[length(where) ? ": [jointext(where, "; ")]" : ""]")

/// With atmos-engine-air=shadow: list(turfs checked, how many didn't match, then some of those turfs)
/datum/controller/subsystem/air/proc/tile_engine_air_check()
	. = list()
	if(tile_engine && tile_engine_air == "shadow")
		call_ext(TILE_ENGINE_LIB, "byond:atmos_engine_air_check")(.)

/// With atmos-engine-cache=shadow: how many turfs had what the engine kept of them checked against what was sent, and how
/// many of those didn't match, as a list
/datum/controller/subsystem/air/proc/tile_engine_cache_check()
	. = list()
	if(tile_engine)
		call_ext(TILE_ENGINE_LIB, "byond:atmos_engine_cache_check")(.)

/// Has the engine write the new air into turfs itself, if it can. Reading a gas list from DM counts as a reference to it
/// on some BYOND builds and not others, so the engine works out which from a probe, and the probe's count has to come out
/// the same as it went in.
/datum/controller/subsystem/air/proc/tile_engine_write_setup()
	tile_engine_writes = FALSE
	tile_engine_writes_check = null
	var/mode = world.params["atmos-engine-writes"]
	if(mode == "dm")
		log_world("Atmos: the tile engine hands its air back for DM to write (atmos-engine-writes=dm)")
		return
	var/datum/probe = new
	var/list/probe_list = list(probe)
	var/before = refcount(probe)
	var/result
	try
		result = call_ext(TILE_ENGINE_LIB, "byond:atmos_engine_write_setup")(probe_list)
	catch(var/exception/error)
		result = "[error]"
	var/after = refcount(probe)
	if((result != 1 && result != 2) || before != after)
		log_world("Atmos: DM writes the tile engine's air (the engine can't: [result], probe references [before] then [after])")
		return
	tile_engine_writes = TRUE
	if(mode == "check")
		tile_engine_writes_check = list("turfs" = 0, "values" = 0, "wrong" = 0, "references changed" = 0, "exposed" = 0, "exposed differently" = 0)
	log_world("Atmos: the tile engine writes its air into turfs itself ([result == 1 ? "releasing what it reads" : "what it reads is temporary"])[mode == "check" ? ", checked against what DM would write" : ""]")

/// Air first: the engine writes each changed turf's new air straight into its own gas list, then DM takes off the gases that
/// ran out and does what it does for turfs whose air changed. Returns FALSE if the engine failed.
/datum/controller/subsystem/air/proc/tile_engine_write_air(list/turf/open/changed, list/values, fired)
	var/list/refs = new /list(length(changed) * 2)
	var/list/listened = list() // positions of turfs with something listening on them, which get exposed whatever their temperature
	var/i = 0
	var/position = 0
	for(var/turf/open/T as anything in changed)
		position++
		T.air_changed_at = fired // wakes idle machines on it (idle_machines.dm)
		if(T.idle_atmos_machines)
			atmos_wake_turf(T)
		if(T.comp_lookup)
			listened += position
		var/datum/gas_mixture/air = T.air
		refs[++i] = air
		refs[++i] = air.moles
	var/list/counts
	if(tile_engine_writes_check)
		counts = list()
		for(var/k in 1 to length(refs)) // read the same way as after the write, so they compare
			counts += refcount(refs[k])
	var/list/removed = list()
	var/list/hot = list()
	var/status
	try
		status = call_ext(TILE_ENGINE_LIB, "byond:atmos_engine_write")(refs, removed, hot)
	catch(var/exception/error)
		status = "[error]"
	if(status != 1)
		tile_engine_failed(status)
		return FALSE
	// Gases that ran out: only DM can take a key off a list
	for(var/r = 1, r < length(removed), r += 2)
		var/list/moles = refs[removed[r] * 2]
		moles -= removed[r + 1]
	if(tile_engine_writes_check)
		tile_engine_check_writes(changed, values, refs, counts)
		tile_engine_check_exposed(changed, refs, listened, hot)
	// What's on a turf whose air changed feels its new temperature. LINDA exposed every active turf every tick, but all
	// that does is tell things listening on the turf, and check if the turf itself melts (nothing open does under
	// 10000 K). Things moving onto a turf check on arrival. Exposing changes no air, so it can wait till all of it is written,
	// as long as the turfs go in the same order: the listened-to ones and the hot ones, merged.
	var/listened_at = 1
	var/hot_at = 1
	var/listened_count = length(listened)
	var/hot_count = length(hot)
	while(listened_at <= listened_count || hot_at <= hot_count)
		var/next_listened = listened_at <= listened_count ? listened[listened_at] : INFINITY
		var/next_hot = hot_at <= hot_count ? hot[hot_at] : INFINITY
		position = min(next_listened, next_hot)
		if(next_listened == position)
			listened_at++
		if(next_hot == position)
			hot_at++
		var/turf/open/T = changed[position]
		var/datum/gas_mixture/air = refs[position * 2 - 1]
		T.temperature_expose(air, air.temperature)
	return TRUE

/// atmos-engine-writes=check: the turfs that get exposed, listened-to and hot ones merged, against every changed turf the old
/// way (temperature 10000 K or more, or something listening on it), in order
/datum/controller/subsystem/air/proc/tile_engine_check_exposed(list/turf/open/changed, list/refs, list/listened, list/hot)
	var/list/expected = list()
	var/position = 0
	for(var/turf/open/T as anything in changed)
		position++
		var/datum/gas_mixture/air = refs[position * 2 - 1]
		if(air.temperature >= 10000 || T.comp_lookup)
			expected += position
	var/list/merged = sortList(listened | hot, GLOBAL_PROC_REF(cmp_numeric_asc))
	tile_engine_writes_check["exposed"] += length(expected)
	if(merged.len != expected.len)
		tile_engine_writes_check["exposed differently"]++
		return
	for(var/k in 1 to length(expected))
		if(merged[k] != expected[k])
			tile_engine_writes_check["exposed differently"]++
			return

/// atmos-engine-writes=check: every gas and temperature the engine wrote, against what DM's own write-back would have
/// written (`values`, in atmos_engine_results()'s layout), and every reference count against what it was before
/datum/controller/subsystem/air/proc/tile_engine_check_writes(list/turf/open/changed, list/values, list/refs, list/counts)
	var/list/check = tile_engine_writes_check
	var/at = 1
	var/position = 0
	for(var/turf/open/T as anything in changed)
		position++
		var/datum/gas_mixture/air = refs[position * 2 - 1]
		var/list/moles = refs[position * 2]
		check["turfs"]++
		for(var/gas in 1 to values[at++])
			var/path = values[at]
			var/amount = values[at + 1]
			at += 2
			check["values"]++
			if(amount ? moles[path] != amount : (path in moles))
				check["wrong"]++
		check["values"]++
		if(air.temperature != values[at++])
			check["wrong"]++
	for(var/k in 1 to length(refs))
		if(refcount(refs[k]) != counts[k])
			check["references changed"]++

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

/// Packs turfs the way atmos_engine_run() takes them. See tools/atmos_engine/src/lib.rs.
/datum/controller/subsystem/air/proc/tile_engine_pack(list/turf/open/turfs, list/tiles, list/adjacent)
	var/generation = tile_engine_generation
	var/shadow = tile_engine_cache_shadow
	var/kept_air = tile_engine_air != "off"
	var/air_shadow = tile_engine_air == "shadow"
	var/clock = tile_engine_air_clock
	var/epoch = tile_engine_air_epoch
	for(var/turf/open/T as anything in turfs)
		var/datum/gas_mixture/air = isopenturf(T) ? T.air : null
		if(!air)
			tiles += -1
			continue
		// The engine has this turf's air as it is, unless something's touched it since it was sent
		var/air_kept = kept_air && T.tile_engine_air_sent > epoch && T.air_touched < T.tile_engine_air_sent
		var/sent_air = !air_kept || air_shadow
		if(sent_air)
			var/list/moles = air.moles
			tiles += air_kept ? -3 - length(moles) : length(moles) // shadow: here it is anyway, to check against
			for(var/gas_type, amount in moles)
				tiles += gas_type
				tiles += amount
			tiles += air.temperature
			if(!air_kept)
				T.tile_engine_air_sent = clock
				tile_engine_air_sent_count++
		else
			tiles += -2
		if(air_kept)
			tile_engine_air_kept_count++ // in the shadow too: what it would have kept
		var/datum/excited_group/group = T.excited_group
		var/sent = generation && T.tile_engine_sent == generation
		if(sent && !shadow) // The engine still has our kind and neighbours
			tiles.Add(-1, 0, group ? group.tile_engine_number : 0, T.significant_share_ticker, T.active_hotspot ? 1 : 0, T.tile_engine_drawn)
			continue
		var/kind = 0
		if(istype(air, /datum/gas_mixture/immutable))
			kind = istype(air, /datum/gas_mixture/immutable/space) ? 1 : 2
			tile_engine_total_immutable++
		else if(T.planetary_atmos)
			kind = 3 + tile_engine_planetary(T.initial_gas_mix)
		var/list/neighbours = T.atmos_adjacent_turfs
		var/neighbour_count = length(neighbours)
		if(neighbour_count)
			adjacent += neighbours
		var/count = neighbour_count
		if(sent) // shadow: the engine checks what it kept against these
			count = -2 - neighbour_count
		else if(generation)
			T.tile_engine_sent = generation
		tiles.Add(count, kind, group ? group.tile_engine_number : 0, T.significant_share_ticker, T.active_hotspot ? 1 : 0, T.tile_engine_drawn)

/// Heat through walls works from turfs' archives, which nothing else needs, so the engine only hands over the ones it's
/// about to read. Run before process_super_conductivity() goes through the conducting turfs. A turf the engine didn't
/// archive this tick archives itself, as it would when heat through walls got to it.
/datum/controller/subsystem/air/proc/tile_engine_archives()
	var/fired = times_fired
	var/list/turf/open/wanted = list()
	for(var/turf/T as anything in active_super_conductivity)
		if(isopenturf(T) && T.archived_cycle < fired)
			T.archived_cycle = fired
			wanted += T
		for(var/direction in GLOB.cardinals)
			var/turf/neighbour = get_step(T, direction)
			if(isopenturf(neighbour) && neighbour.archived_cycle < fired)
				neighbour.archived_cycle = fired
				wanted += neighbour
	if(!length(wanted))
		return
	if(tile_engine_swept_at != fired) // no awake turfs this tick, so the engine's archives are from an older one
		for(var/turf/open/T as anything in wanted)
			T.archive()
		return
	var/list/values = list()
	var/status
	try
		status = call_ext(TILE_ENGINE_LIB, "byond:atmos_engine_archives")(wanted, values)
	catch(var/exception/error)
		status = "[error]"
	if(status != 1)
		tile_engine_failed(status)
		for(var/turf/open/T as anything in wanted)
			T.archive()
		return
	var/at = 1
	for(var/turf/open/T as anything in wanted)
		var/temperature = values[at++]
		if(temperature == -1) //not archived. Only -1 will do: LINDA's air can really go below 0 K, and reading that as
			T.archive() //"no record" put every turf after it out of step with the list
			continue
		var/datum/gas_mixture/air = T.air
		var/list/archive = list()
		for(var/gas in 1 to values[at++])
			archive[values[at]] = values[at + 1]
			at += 2
		air.moles_archive = archive
		air.temperature_archived = temperature
		T.temperature_archived = T.temperature

/// Something went wrong with the library, so atmos goes back to LINDA for the rest of the round
/datum/controller/subsystem/air/proc/tile_engine_failed(status)
	tile_engine = FALSE
	log_world("Atmos: the tile engine failed ([status], see the server's error output), switching to LINDA")
	stack_trace("Atmos: the tile engine failed ([status]), switching to LINDA")

/// One atmos tick of turfs: pack what the engine asks for until it's done, then follow up
/datum/controller/subsystem/air/proc/tile_engine_process()
	tile_engine_awake = length(active_turfs)
	if(!tile_engine_awake)
		tile_engine_packed = 0
		tile_engine_rounds = 0
		tile_engine_changed = 0
		return
	var/timer = TICK_USAGE_REAL
	tile_engine_air_clock++
	if(tile_engine_air == "shadow" && !(times_fired % 1200)) // every few minutes of a round, for checking it in shift batches
		tile_engine_air_log()
	var/list/need = active_turfs
	var/awake = 1
	var/packed = 0
	var/rounds = 0
	var/status = 2
	while(status == 2)
		var/list/tiles = list()
		var/list/adjacent = list()
		tile_engine_pack(need, tiles, adjacent)
		var/list/wanted = list()
		packed += length(need)
		rounds++
		tile_engine_pack_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer)
		timer = TICK_USAGE_REAL
		try
			status = call_ext(TILE_ENGINE_LIB, "byond:atmos_engine_run")(need, tiles, adjacent, tile_engine_planetary_data, awake, wanted)
		catch(var/exception/error)
			status = "[error]"
		tile_engine_native_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer)
		timer = TICK_USAGE_REAL
		if(status == 3) // it has no air for some turfs we said it kept (it started afresh): the same again, with theirs
			for(var/turf/open/T as anything in wanted)
				T.tile_engine_air_sent = 0
			status = 2
			continue
		need = wanted
		awake = 0
	if(status != 1)
		tile_engine_failed(status)
		return
	tile_engine_packed = packed
	tile_engine_rounds = rounds

	var/list/turf/open/changed = list()
	var/list/values = list()
	var/list/turf/open/processed = list()
	var/list/tickers = list()
	var/list/turf/open/woken = list()
	var/list/turf/open/slept = list()
	var/list/turf/open/joins = list()
	var/list/turf/open/groups_big = list()
	var/list/turf/open/groups_small = list()
	var/list/turf/open/windy = list()
	var/list/turf/open/wind_to = list()
	var/list/wind_force = list()
	var/list/turf/open/react = list()
	var/list/turf/open/redraw = list()
	var/list/redraw_keys = list()
	var/list/turf/open/hot = list()
	try
		// values are only needed when DM writes the air, or checks what the engine wrote
		status = call_ext(TILE_ENGINE_LIB, "byond:atmos_engine_results")(active_turfs, changed, (tile_engine_writes && !tile_engine_writes_check) ? null : values, processed, tickers, woken, slept, joins, groups_big, groups_small, windy, wind_to, wind_force, react, redraw, redraw_keys, hot)
	catch(var/exception/error)
		status = "[error]"
	tile_engine_native_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer)
	timer = TICK_USAGE_REAL
	if(status != 1)
		tile_engine_failed(status)
		return
	tile_engine_changed = length(changed)
	tile_engine_total_packed += packed
	tile_engine_total_rounds += rounds
	tile_engine_total_changed += tile_engine_changed
	tile_engine_total_turns += length(processed)

	var/fired = times_fired
	tile_engine_swept_at = fired
	var/part = TICK_USAGE_REAL
	// The engine's writes aren't touches. Anything DM does to a turf's air from here on is (exposing, reactions...).
	tile_engine_air_clock++
	// Air first. Only the gases that changed get written, in the turf's own list.
	var/at = 1
	if(tile_engine_writes)
		if(!tile_engine_write_air(changed, values, fired))
			return
	else for(var/turf/open/T as anything in changed)
		T.air_changed_at = fired // wakes idle machines on it (idle_machines.dm)
		if(T.idle_atmos_machines)
			atmos_wake_turf(T)
		var/datum/gas_mixture/air = T.air
		var/list/moles = air.moles
		for(var/gas in 1 to values[at++])
			var/amount = values[at + 1]
			if(amount)
				moles[values[at]] = amount
			else
				moles -= values[at]
			at += 2
		var/temperature = values[at++]
		air.temperature = temperature
		// What's on a turf whose air changed feels its new temperature. LINDA exposed every active turf every tick, but all
		// that does is tell things listening on the turf, and check if the turf itself melts (nothing open does under
		// 10000 K). Things moving onto a turf check on arrival.
		if(temperature >= 10000 || T.comp_lookup)
			T.temperature_expose(air, temperature)

	tile_engine_apply_parts["air"] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - part) // for benches
	part = TICK_USAGE_REAL
	// What process_cell() leaves on a turf that had its turn. current_cycle tells a new hotspot whether it's on a turf
	// that's already had its turn this tick.
	at = 0
	for(var/turf/open/T as anything in processed)
		T.current_cycle = fired
		T.significant_share_ticker = tickers[++at]
	for(var/turf/open/T as anything in woken)
		T.excited = TRUE
	for(var/turf/open/T as anything in slept)
		T.excited = FALSE

	tile_engine_apply_parts["turns"] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - part) // for benches
	part = TICK_USAGE_REAL
	// Excited groups, in the order LINDA's process_cell() would have gone through them: a pair in two groups merges them,
	// and otherwise they join a group, a new one if neither is in one (a turf alone with its planet's air comes as a pair
	// with itself). LAST_SHARE_CHECK comes after, on one turf from each group that had a share.
	var/join_count = length(joins)
	for(var/i = 1, i < join_count, i += 2)
		var/turf/open/A = joins[i]
		var/turf/open/B = joins[i + 1]
		var/datum/excited_group/ours = A.excited_group
		var/datum/excited_group/theirs = B.excited_group
		if(ours && theirs)
			if(ours != theirs)
				ours.merge_groups(theirs)
		else
			var/datum/excited_group/joined = ours || theirs || new
			if(!ours)
				joined.add_turf(A)
			if(!theirs && A != B)
				joined.add_turf(B)
	for(var/turf/open/T as anything in groups_big)
		T.excited_group?.reset_cooldowns()
	for(var/turf/open/T as anything in groups_small)
		var/datum/excited_group/group = T.excited_group
		if(group)
			group.dismantle_cooldown = 0

	tile_engine_apply_parts["groups"] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - part) // for benches
	part = TICK_USAGE_REAL
	// Wind, as consider_pressure_difference() records it. A turf whose pressure_difference is still 0 isn't in
	// high_pressure_delta (process_high_pressure_delta() zeroes it as it takes a turf out), so it goes straight on the end
	// instead of searching the whole list with |= for every windy turf.
	at = 0
	for(var/turf/open/T as anything in windy)
		at++
		var/difference = wind_force[at]
		if(!T.pressure_difference)
			high_pressure_delta += T
		if(difference > T.pressure_difference)
			T.pressure_direction = get_dir(T, wind_to[at])
			T.pressure_difference = difference

	tile_engine_apply_parts["wind"] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - part) // for benches
	part = TICK_USAGE_REAL
	// One turf's reaction can change the next turf on the list into a wall, so from here on they might not be open any more
	for(var/turf/open/T as anything in react)
		if(!isopenturf(T))
			continue
		var/datum/gas_mixture/air = T.air
		T.air_touched = tile_engine_air_clock
		if(air.react(T))
			T.tile_engine_reacted = fired
			T.update_visuals()
			T.tile_engine_drawn = -1 // drawn from after the reaction, so the next tick checks it again
			T.consider_superconductivity(TRUE) // a small fire flashing hot starts heating its floor, which is what cools it
			T.temperature_expose(air, air.temperature)

	tile_engine_apply_parts["react"] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - part) // for benches
	part = TICK_USAGE_REAL
	// Gas overlays that would look different now
	at = 0
	for(var/turf/open/T as anything in redraw)
		at++
		if(isopenturf(T) && T.tile_engine_reacted != fired)
			T.update_visuals()
			T.tile_engine_drawn = redraw_keys[at]

	tile_engine_apply_parts["redraw"] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - part) // for benches
	part = TICK_USAGE_REAL
	// Hot enough to conduct heat through walls
	for(var/turf/open/T as anything in hot)
		T.consider_superconductivity(TRUE)
	tile_engine_apply_parts["hot"] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - part)
	tile_engine_apply_ms += TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer)


// ---------------------------------------------------------------------------------------------
// Touching a turf's air: the tile engine keeps every turf's air between ticks, and DM sends it again when it's been touched
// ---------------------------------------------------------------------------------------------

/turf/open/return_air()
	RETURN_TYPE(/datum/gas_mixture)
	air_touched = SSair.tile_engine_air_clock // whoever has it may change it
	return air

/turf/open/assume_air(datum/gas_mixture/giver)
	air_touched = SSair.tile_engine_air_clock
	return ..()

/turf/open/copy_air_with_tile(turf/open/T)
	air_touched = SSair.tile_engine_air_clock
	return ..()

/turf/open/copy_air(datum/gas_mixture/copy)
	air_touched = SSair.tile_engine_air_clock
	return ..()

/// An excited group breaking down evens out its turfs' air
/datum/excited_group/self_breakdown(roundstart = FALSE, poke_turfs = FALSE)
	var/clock = SSair.tile_engine_air_clock
	for(var/turf/open/T as anything in turf_list)
		T.air_touched = clock
	return ..()

/// Heat through walls changes the temperature of the air either side
/turf/open/temperature_share_open_to_solid(turf/sharer)
	air_touched = SSair.tile_engine_air_clock
	return ..()

/turf/neighbor_conduct_with_src(turf/open/other)
	var/clock = SSair.tile_engine_air_clock
	if(isopenturf(other))
		other.air_touched = clock
	var/turf/open/us = src
	if(isopenturf(us))
		us.air_touched = clock
	return ..()

/// Through a window the air either side shares heat straight, open turf to open turf (the plasma fire's shadow check found it)
/turf/open/neighbor_conduct_with_src(turf/other)
	var/clock = SSair.tile_engine_air_clock
	air_touched = clock
	if(isopenturf(other))
		var/turf/open/them = other
		them.air_touched = clock
	return ..()

/// Gas made on the spot, by a plasma floor burning say, goes straight into the turf's air
/turf/open/atmos_spawn_air(text)
	air_touched = SSair.tile_engine_air_clock
	return ..()

/turf/super_conduct()
	var/turf/open/us = src
	if(isopenturf(us))
		us.air_touched = SSair.tile_engine_air_clock
	return ..()

#undef TILE_ENGINE_LIB
#undef TILE_ENGINE_VERSION
