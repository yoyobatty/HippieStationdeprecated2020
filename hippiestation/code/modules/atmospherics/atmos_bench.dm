// Atmos bench - headless benchmark of the atmos engine, for working on it.
//
// Starts a round, then on the station z-level runs a few scenes one after another and times every stage of SSair
// over each: a calm station, a big gas release, a plasma fire, and hull breaches to space. The same spots get picked
// every run, so runs compare.
//
// Run it:   tools/atmos_bench/run_atmos_bench.sh [profile | machine-times | idle-check | machines]
// or boot:  DreamDaemon hippiestation.dmb -params "atmos-bench=1" ("atmos-bench=profile" to also profile)
// Results:  data/atmos_bench/results.txt, and with profiling data/atmos_bench/profile.json

#define ATMOS_BENCH_DIR "data/atmos_bench/"

GLOBAL_VAR_INIT(atmos_bench_recording, FALSE)
/// Stage name -> real ms spent in it while recording
GLOBAL_LIST_EMPTY(atmos_bench_stage_ms)
/// Stage name -> how many times it ran while recording
GLOBAL_LIST_EMPTY(atmos_bench_stage_calls)
/// Machine type -> real ms in its process_atmos(), only kept with "atmos-bench=machine-times" (null otherwise)
GLOBAL_VAR(atmos_bench_machine_ms)
/// Machine type -> process_atmos() calls, alongside the above
GLOBAL_VAR(atmos_bench_machine_calls)
/// Pipe network -> real ms in its process(), and how many times it rebalanced (reconcile_air()), with machine-times
GLOBAL_VAR(atmos_bench_net_ms)
GLOBAL_VAR(atmos_bench_net_reconciles)
/// Machine type -> update_parents() calls, with machine-times
GLOBAL_VAR(atmos_bench_updaters)

/proc/atmos_bench_add(stage, start)
	GLOB.atmos_bench_stage_ms[stage] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
	GLOB.atmos_bench_stage_calls[stage] += 1

// Every stage of SSair is timed while the bench records. Each one can return early to resume next tick, so these add
// up every piece of it.
/datum/controller/subsystem/air/fire(resumed = FALSE)
	if(!GLOB.atmos_bench_recording)
		return ..()
	var/start = TICK_USAGE_REAL
	. = ..()
	atmos_bench_add("all of SSair", start)

/datum/controller/subsystem/air/process_pipenets(delta_time, resumed = FALSE)
	if(!GLOB.atmos_bench_recording)
		return ..()
	var/start = TICK_USAGE_REAL
	if(GLOB.atmos_bench_net_ms)
		atmos_bench_timed_pipenets(delta_time, resumed)
	else
		. = ..()
	atmos_bench_add("pipe networks", start)

/// The pipe network stage as SSair runs it, but timing every network ("atmos-bench=machine-times")
/datum/controller/subsystem/air/proc/atmos_bench_timed_pipenets(delta_time, resumed)
	if (!resumed)
		src.currentrun = updating_networks.Copy()
	var/list/currentrun = src.currentrun
	var/list/net_ms = GLOB.atmos_bench_net_ms
	var/list/net_reconciles = GLOB.atmos_bench_net_reconciles
	while(currentrun.len)
		var/datum/pipeline/net = currentrun[currentrun.len]
		currentrun.len--
		if(!net)
			networks.Remove(net)
			updating_networks.Remove(net)
		else
			var/reconciling = net.update && !net.building
			var/net_start = TICK_USAGE_REAL
			net.process(delta_time)
			if(net.settled())
				updating_networks -= net
			net_ms[net] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - net_start)
			if(reconciling)
				net_reconciles[net] += 1
		if(MC_TICK_CHECK)
			return

// Who flags pipe networks for rebalancing, by type
/obj/machinery/atmospherics/components/update_parents()
	if(GLOB.atmos_bench_updaters && GLOB.atmos_bench_recording)
		GLOB.atmos_bench_updaters[type] += 1
	return ..()

/datum/controller/subsystem/air/process_atmos_machinery(delta_time, resumed = FALSE)
	if(!GLOB.atmos_bench_recording)
		return ..()
	var/start = TICK_USAGE_REAL
	if(GLOB.atmos_bench_machine_ms)
		atmos_bench_timed_machinery(delta_time, resumed)
	else
		. = ..()
	atmos_bench_add("atmos machinery", start)

/// The machinery stage as SSair runs it, but timing every machine by type ("atmos-bench=machine-times")
/datum/controller/subsystem/air/proc/atmos_bench_timed_machinery(delta_time, resumed)
	if (!resumed)
		src.currentrun = atmos_machinery.Copy()
	var/list/currentrun = src.currentrun
	var/list/machine_ms = GLOB.atmos_bench_machine_ms
	var/list/machine_calls = GLOB.atmos_bench_machine_calls
	var/can_idle = tile_engine
	var/fired = times_fired
	while(currentrun.len)
		var/obj/machinery/M = currentrun[currentrun.len]
		currentrun.len--
		if(!M)
			atmos_machinery.Remove(M)
		else
			var/machine_start = TICK_USAGE_REAL
			if(M.atmos_idle_since)
				var/turf/T = M.loc
				if(can_idle && T?.air_changed_at < M.atmos_idle_since && fired - M.atmos_idle_since < ATMOS_IDLE_RECHECK)
					machine_ms[M.type] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - machine_start)
					continue
				M.atmos_idle_since = 0
			var/result = M.process_atmos(delta_time)
			if(result == PROCESS_KILL)
				atmos_machinery.Remove(M)
			else if(result == ATMOS_IDLE && can_idle)
				M.atmos_idle_since = fired
			machine_ms[M.type] += TICK_DELTA_TO_MS(TICK_USAGE_REAL - machine_start)
			machine_calls[M.type] += 1
		if(MC_TICK_CHECK)
			return

/datum/controller/subsystem/air/process_active_turfs(resumed = FALSE)
	if(!GLOB.atmos_bench_recording)
		return ..()
	var/start = TICK_USAGE_REAL
	. = ..()
	atmos_bench_add("active turfs", start)

/datum/controller/subsystem/air/process_hotspots(delta_time, resumed = FALSE)
	if(!GLOB.atmos_bench_recording)
		return ..()
	var/start = TICK_USAGE_REAL
	. = ..()
	atmos_bench_add("hotspots", start)

/datum/controller/subsystem/air/process_excited_groups(resumed = FALSE)
	if(!GLOB.atmos_bench_recording)
		return ..()
	var/start = TICK_USAGE_REAL
	. = ..()
	atmos_bench_add("excited groups", start)

/datum/controller/subsystem/air/process_high_pressure_delta(resumed = FALSE)
	if(!GLOB.atmos_bench_recording)
		return ..()
	var/start = TICK_USAGE_REAL
	. = ..()
	atmos_bench_add("wind pushes", start)

/datum/controller/subsystem/air/process_super_conductivity(resumed = FALSE)
	if(!GLOB.atmos_bench_recording)
		return ..()
	var/start = TICK_USAGE_REAL
	. = ..()
	atmos_bench_add("heat through walls", start)

/datum/controller/subsystem/air/process_atoms(resumed = FALSE)
	if(!GLOB.atmos_bench_recording)
		return ..()
	var/start = TICK_USAGE_REAL
	. = ..()
	atmos_bench_add("atoms", start)

/datum/controller/subsystem/air/process_rebuilds()
	if(!GLOB.atmos_bench_recording)
		return ..()
	var/start = TICK_USAGE_REAL
	. = ..()
	atmos_bench_add("pipe rebuilds", start)

/proc/run_atmos_bench(option)
	// Headless: nobody is connected, and with sleep_offline on the world pauses.
	Master.sleep_offline_after_initializations = FALSE
	world.sleep_offline = FALSE
	CONFIG_SET(flag/allow_random_events, FALSE) //a meteor shower would make runs not compare
	SSticker.start_immediately = TRUE
	var/round_deadline = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < round_deadline)
		sleep(1 SECONDS)
	sleep(10 SECONDS) // let roundstart settle
	fdel(ATMOS_BENCH_DIR)

	var/z = SSmapping.levels_by_trait(ZTRAIT_STATION)[1]
	var/list/lines = list("Atmos bench - station z-level [z], BYOND [world.byond_version].[world.byond_build], round state [SSticker.current_state], turfs run by [SSair.tile_engine ? "the tile engine" : "LINDA"]")

	// Same spots every run
	rand_seed(1337)
	var/list/turf/open/floor/hall_floors = list()
	var/list/turf/closed/wall/hull_walls = list()
	for(var/turf/T as anything in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		if(istype(T, /turf/open/floor) && istype(T.loc, /area/hallway))
			hall_floors += T
		else if(istype(T, /turf/closed/wall) && !istype(T, /turf/closed/wall/r_wall))
			for(var/dir in GLOB.cardinals)
				var/turf/inside = get_step(T, dir)
				var/turf/outside = get_step(T, turn(dir, 180))
				if(istype(inside, /turf/open/floor) && istype(inside.loc, /area/hallway) && istype(outside, /turf/open/space))
					hull_walls += T
					break
	lines += "[length(hall_floors)] hallway floor tiles, [length(hull_walls)] hallway walls with space behind them"
	if(!length(hall_floors))
		lines += "No hallways found - nothing to do"
		atmos_bench_finish(lines)
		return

	// Every spot is picked now, before anything else in the round has had a chance to use random numbers
	var/turf/open/floor/release_spot = pick(hall_floors)
	var/turf/open/floor/fire_spot = pick(hall_floors)
	shuffle_inplace(hull_walls)
	var/list/turf/closed/wall/to_breach = list()
	for(var/turf/closed/wall/W as anything in hull_walls)
		if(length(to_breach) >= 6)
			break
		var/too_close = FALSE
		for(var/turf/other as anything in to_breach)
			if(get_dist(W, other) < 15)
				too_close = TRUE
				break
		if(!too_close)
			to_breach += W

	if(option == "idle-check")
		lines += atmos_bench_idle_check(z)
		atmos_bench_finish(lines)
		return

	if(option == "profile")
		world.Profile(PROFILE_CLEAR)
		world.Profile(PROFILE_START)
	if(option == "machine-times")
		GLOB.atmos_bench_machine_ms = list()
		GLOB.atmos_bench_machine_calls = list()
		GLOB.atmos_bench_net_ms = list()
		GLOB.atmos_bench_net_reconciles = list()
		GLOB.atmos_bench_updaters = list()

	if(option == "machines")
		// What SSair's machinery stage goes through every tick, by type
		var/list/by_type = list()
		for(var/obj/machinery/machine as anything in SSair.atmos_machinery)
			by_type["[machine.type]"] += 1
		sortTim(by_type, GLOBAL_PROC_REF(cmp_numeric_dsc), associative = TRUE)
		lines += list("", "[length(SSair.atmos_machinery)] machines in SSair.atmos_machinery:")
		for(var/type_name in by_type)
			lines += "  [by_type[type_name]] [type_name]"
		atmos_bench_finish(lines)
		return

	lines += atmos_bench_scene("Calm station", 60 SECONDS)

	// A canister's worth of gas let out on one tile
	var/datum/gas_mixture/release_air = release_spot.return_air()
	release_air.assert_gas(/datum/gas/nitrous_oxide)
	release_air.moles[/datum/gas/nitrous_oxide] += 5000
	SSair.add_to_active(release_spot)
	lines += "Released 5000 mol of N2O at ([release_spot.x],[release_spot.y])"
	lines += atmos_bench_scene("Gas release", 60 SECONDS)

	// A plasma fire: plasma and oxygen on a 5 by 5 patch, then a spark
	var/fire_tiles = 0
	for(var/turf/open/floor/F in range(2, fire_spot))
		var/datum/gas_mixture/fire_air = F.return_air()
		fire_air.assert_gases(/datum/gas/plasma, /datum/gas/oxygen)
		fire_air.moles[/datum/gas/plasma] += 60
		fire_air.moles[/datum/gas/oxygen] += 40
		SSair.add_to_active(F)
		fire_tiles++
	fire_spot.hotspot_expose(1000, CELL_VOLUME)
	lines += "Plasma and oxygen on [fire_tiles] tiles around ([fire_spot.x],[fire_spot.y]), lit"
	lines += atmos_bench_scene("Plasma fire", 90 SECONDS)

	// Hull breaches: hallway walls with space behind them knocked out
	var/list/breached = list()
	for(var/turf/closed/wall/W as anything in to_breach)
		breached += W.ChangeTurf(/turf/open/floor/plating)
	var/list/breach_text = list()
	for(var/turf/B as anything in breached)
		breach_text += "([B.x],[B.y])"
	lines += "Knocked out [length(breached)] hull walls: [jointext(breach_text, " ")]"
	lines += atmos_bench_scene("Hull breaches", 90 SECONDS)

	if(option == "profile")
		text2file(world.Profile(PROFILE_REFRESH, format = "json"), "[ATMOS_BENCH_DIR]profile.json")
		world.Profile(PROFILE_STOP)
	atmos_bench_finish(lines)

/// Records SSair for this long and returns lines saying where its time went
/proc/atmos_bench_scene(name, length)
	GLOB.atmos_bench_stage_ms = list()
	GLOB.atmos_bench_stage_calls = list()
	if(GLOB.atmos_bench_machine_ms)
		GLOB.atmos_bench_machine_ms = list()
		GLOB.atmos_bench_machine_calls = list()
		GLOB.atmos_bench_net_ms = list()
		GLOB.atmos_bench_net_reconciles = list()
		GLOB.atmos_bench_updaters = list()
	var/list/active = list()
	var/list/groups = list()
	var/list/hotspots = list()
	var/list/wind = list()
	var/start_time = world.time
	var/start_real = REALTIMEOFDAY
	var/pack_ms = SSair.tile_engine_pack_ms
	var/native_ms = SSair.tile_engine_native_ms
	var/apply_ms = SSair.tile_engine_apply_ms
	GLOB.atmos_bench_recording = TRUE
	while(world.time < start_time + length)
		active += length(SSair.active_turfs)
		groups += length(SSair.excited_groups)
		hotspots += length(SSair.hotspots)
		wind += length(SSair.high_pressure_delta)
		sleep(1 SECONDS)
	GLOB.atmos_bench_recording = FALSE
	var/fires = GLOB.atmos_bench_stage_calls["all of SSair"] || 0
	. = list("", "[name] - [length / 10] s of game time in [round((REALTIMEOFDAY - start_real) / 10, 0.1)] s real time, SSair fired [fires] times")
	. += "  active turfs: average [atmos_bench_mean(active)], most [max(active)]; excited groups: average [atmos_bench_mean(groups)], most [max(groups)]; hotspots most [max(hotspots)]; wind tiles most [max(wind)]"
	var/list/stages = list("all of SSair", "active turfs", "excited groups", "hotspots", "wind pushes", "atmos machinery", "pipe networks", "heat through walls", "atoms", "pipe rebuilds")
	for(var/stage in stages)
		var/ms = GLOB.atmos_bench_stage_ms[stage] || 0
		. += "  [stage]: [round(ms, 0.1)] ms total, [fires ? round(ms / fires, 0.01) : 0] ms per SSair fire"
	if(SSair.tile_engine && fires)
		. += "  tile engine, ms per SSair fire: packing [round((SSair.tile_engine_pack_ms - pack_ms) / fires, 0.01)], the engine itself [round((SSair.tile_engine_native_ms - native_ms) / fires, 0.01)], following up [round((SSair.tile_engine_apply_ms - apply_ms) / fires, 0.01)]"
	var/list/machine_ms = GLOB.atmos_bench_machine_ms
	if(length(machine_ms) && fires)
		sortTim(machine_ms, GLOBAL_PROC_REF(cmp_numeric_dsc), associative = TRUE)
		. += "  machinery by type, ms per SSair fire (machines of that type, microseconds each):"
		var/shown = 0
		for(var/machine_type in machine_ms)
			if(++shown > 15)
				break
			var/per_fire = machine_ms[machine_type] / fires
			var/count = GLOB.atmos_bench_machine_calls[machine_type] / fires
			. += "    [round(per_fire, 0.001)] [machine_type] ([round(count, 0.1)], [round(per_fire * 1000 / count, 0.1)] us each)"
	var/list/net_ms = GLOB.atmos_bench_net_ms
	if(length(net_ms) && fires)
		sortTim(net_ms, GLOBAL_PROC_REF(cmp_numeric_dsc), associative = TRUE)
		. += "  pipe networks, ms per SSair fire (of [length(SSair.networks)]), rebalances per fire, what's on it:"
		var/shown = 0
		for(var/datum/pipeline/net as anything in net_ms)
			if(++shown > 8)
				break
			var/rebalances = (GLOB.atmos_bench_net_reconciles[net] || 0) / fires
			. += "    [round(net_ms[net] / fires, 0.001)] ms, [round(rebalances, 0.01)] rebalances: [atmos_bench_describe_net(net)]"
		var/list/updaters = GLOB.atmos_bench_updaters
		sortTim(updaters, GLOBAL_PROC_REF(cmp_numeric_dsc), associative = TRUE)
		var/list/updater_text = list()
		for(var/updater_type in updaters)
			if(length(updater_text) >= 8)
				break
			updater_text += "[round(updaters[updater_type] / fires, 0.1)] [updater_type]"
		. += "  update_parents() calls per fire: [jointext(updater_text, "; ")]"
	. += atmos_bench_outcome()

/// Checks idle vents and scrubbers still do their job ("atmos-bench=idle-check"): CO2 put on two scrubbers' turfs, one
/// the usual way (add_to_active()) and one behind atmos's back, and half the air taken off a vent's turf. Run it with
/// ENGINE=linda too: that's how it worked before, as nothing idles there.
/proc/atmos_bench_idle_check(z)
	. = list("", "Idle machines check")
	var/list/obj/machinery/atmospherics/components/unary/vent_scrubber/scrubbers = list()
	var/obj/machinery/atmospherics/components/unary/vent_pump/vent
	for(var/obj/machinery/atmospherics/components/unary/machine in SSair.atmos_machinery)
		if(machine.z != z || !isopenturf(machine.loc) || !machine.on || !machine.is_operational() || machine.welded)
			continue
		if(istype(machine, /obj/machinery/atmospherics/components/unary/vent_scrubber))
			var/obj/machinery/atmospherics/components/unary/vent_scrubber/scrubber = machine
			// scrubbing 1 is scrubbing, not siphoning
			if(length(scrubbers) < 2 && scrubber.scrubbing == 1 && !scrubber.widenet && (/datum/gas/carbon_dioxide in scrubber.filter_types))
				scrubbers += scrubber
		else if(!vent && istype(machine, /obj/machinery/atmospherics/components/unary/vent_pump))
			var/obj/machinery/atmospherics/components/unary/vent_pump/candidate = machine
			// pump_direction 1 is releasing, pressure_checks 1 the external bound
			if(candidate.pump_direction == 1 && (candidate.pressure_checks & 1))
				vent = candidate
	if(length(scrubbers) < 2 || !vent)
		. += "  couldn't find two scrubbers and a vent to try"
		return
	var/list/obj/machinery/machines = scrubbers + vent
	var/list/idle_text = list()
	for(var/obj/machinery/machine as anything in machines)
		idle_text += machine.atmos_idle_since ? "idle" : "running"
	. += "  before: scrubbers and vent [jointext(idle_text, ", ")]"

	var/co2_start = atmos_bench_station_moles(z, /datum/gas/carbon_dioxide)
	var/total_start = atmos_bench_station_moles(z)
	var/fired_at = SSair.times_fired // the next atmos tick, as this runs between them
	for(var/i in 1 to 2)
		var/obj/machinery/atmospherics/components/unary/vent_scrubber/scrubber = scrubbers[i]
		var/turf/open/T = scrubber.loc
		T.air.assert_gas(/datum/gas/carbon_dioxide)
		T.air.moles[/datum/gas/carbon_dioxide] += 20
		if(i == 1)
			SSair.add_to_active(T)
	var/turf/open/vent_turf = vent.loc
	vent_turf.remove_air(vent_turf.air.total_moles() / 2)
	vent_turf.air_update_turf()
	var/total_after_removal = atmos_bench_station_moles(z)
	. += "  put 40 mol of CO2 on the scrubbers' turfs (the second without telling atmos), took [round(total_start - total_after_removal + 40, 0.1)] mol of air off the vent's turf"

	var/start_time = world.time
	for(var/seconds in list(1, 2, 3, 6))
		sleep(start_time + seconds SECONDS - world.time)
		var/list/state = list()
		for(var/obj/machinery/machine as anything in machines)
			var/ran = !machine.atmos_idle_since || machine.atmos_idle_since >= fired_at
			state += ran ? "ran" : "still idle"
		var/co2_gone = co2_start + 40 - atmos_bench_station_moles(z, /datum/gas/carbon_dioxide)
		var/air_back = atmos_bench_station_moles(z) - total_after_removal
		. += "  [SSair.times_fired - fired_at] atmos ticks on: scrubbers and vent [jointext(state, ", ")]; [round(co2_gone, 0.01)] mol CO2 scrubbed, [round(air_back, 0.1)] mol of air vented back in"

/// Moles of one gas (or all of them) on the open turfs of a z-level
/proc/atmos_bench_station_moles(z, gas_type)
	. = 0
	for(var/turf/open/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		var/datum/gas_mixture/air = T.air
		if(!air || istype(air, /datum/gas_mixture/immutable))
			continue
		if(gas_type)
			. += air.moles[gas_type] || 0
		else
			for(var/each_type, amount in air.moles)
				. += amount

/// Roughly what a pipe network is: how many pipes, and the machines on it by kind
/proc/atmos_bench_describe_net(datum/pipeline/net)
	if(QDELETED(net))
		return "(gone)"
	var/list/kinds = list()
	for(var/obj/machinery/atmospherics/machine as anything in net.other_atmosmch)
		var/kind = "other"
		if(istype(machine, /obj/machinery/atmospherics/components/unary/vent_pump))
			kind = "vents"
		else if(istype(machine, /obj/machinery/atmospherics/components/unary/vent_scrubber))
			kind = "scrubbers"
		else if(istype(machine, /obj/machinery/atmospherics/components/unary/portables_connector))
			var/obj/machinery/atmospherics/components/unary/portables_connector/port = machine
			kind = port.connected_device ? "connectors in use" : "empty connectors"
		else if(istype(machine, /obj/machinery/atmospherics/components/binary))
			kind = "pumps and valves"
		else if(istype(machine, /obj/machinery/atmospherics/components/trinary))
			kind = "filters and mixers"
		kinds[kind] += 1
	var/list/parts = list()
	for(var/kind in kinds)
		parts += "[kinds[kind]] [kind]"
	return "[length(net.members)] pipes, [length(net.other_airs)] machine airs ([jointext(parts, ", ")]), [round(net.air.return_pressure(), 0.1)] kPa"

/// What the station's air looks like now, to compare how the engines behave: totals over every open station turf
/proc/atmos_bench_outcome()
	var/z = SSmapping.levels_by_trait(ZTRAIT_STATION)[1]
	var/total = 0
	var/n2o = 0
	var/n2o_tiles = 0
	var/plasma = 0
	var/low_pressure = 0
	var/hot = 0
	var/open = 0
	for(var/turf/open/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		var/datum/gas_mixture/air = T.air
		if(!air || istype(air, /datum/gas_mixture/immutable))
			continue
		open++
		var/list/moles = air.moles
		var/here = 0
		for(var/gas_type, amount in moles)
			here += amount
		total += here
		var/n2o_here = moles[/datum/gas/nitrous_oxide] || 0
		n2o += n2o_here
		if(n2o_here >= 1)
			n2o_tiles++
		plasma += moles[/datum/gas/plasma] || 0
		if(here * R_IDEAL_GAS_EQUATION * air.temperature / air.volume < 20)
			low_pressure++
		if(air.temperature > T0C + 100)
			hot++
	return "  air now, over [open] open station turfs: [round(total)] mol in all; N2O [round(n2o)] mol, on [n2o_tiles] turfs with a mole or more; plasma [round(plasma)] mol; [low_pressure] turfs under 20 kPa; [hot] turfs over 100 C"

/proc/atmos_bench_mean(list/values)
	if(!length(values))
		return 0
	var/total = 0
	for(var/value in values)
		total += value
	return round(total / length(values), 0.1)

/proc/atmos_bench_finish(list/lines)
	text2file(jointext(lines, "\n"), "[ATMOS_BENCH_DIR]results.txt")
	log_world("ATMOS BENCH: done")
	Master.Shutdown()
	qdel(world)

#undef ATMOS_BENCH_DIR
