// Atmos bench - headless benchmark of the atmos engine, for working on it.
//
// Starts a round, then on the station z-level runs a few scenes one after another and times every stage of SSair
// over each: a calm station, a big gas release, a plasma fire, and hull breaches to space. The same spots get picked
// every run, so runs compare.
//
// Run it:   tools/atmos_bench/run_atmos_bench.sh [profile | machine-times | idle-check | blocker-check | machines]
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

	if(option == "blocker-check")
		lines += atmos_bench_blocker_check(z)
		atmos_bench_finish(lines)
		return

	if(option == "toxins-check")
		lines += atmos_bench_toxins_check(z)
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
		var/all_machines_ms = 0
		for(var/machine_type in machine_ms)
			all_machines_ms += machine_ms[machine_type]
		. += "  machinery by type, ms per SSair fire (machines of that type run per fire, microseconds each); all types [round(all_machines_ms / fires, 0.01)] ms:"
		var/shown = 0
		for(var/machine_type in machine_ms)
			if(++shown > 40)
				break
			var/per_fire = machine_ms[machine_type] / fires
			var/count = GLOB.atmos_bench_machine_calls[machine_type] / fires
			. += "    [round(per_fire, 0.001)] [machine_type] ([round(count, 0.1)], [count ? round(per_fire * 1000 / count, 0.1) : 0] us each)"
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

/// Checks everything that holds air back lets it through again once it's gone ("atmos-bench=blocker-check"). Each kind
/// is put on an empty hallway tile and checked to block, then deleted, wrecked or taken apart, and the tile's air
/// connections are compared with what's really there. Walls get knocked down every way there is, and one gets built.
/proc/atmos_bench_blocker_check(z)
	. = list("", "Air blockers check")
	var/turf/open/floor/spot = atmos_bench_clear_tile(z)
	if(!spot)
		. += "  no empty hallway tile with open floor on all four sides"
		return
	. += "  test tile ([spot.x],[spot.y]); each line: what it blocks once built, its connections after it's gone, whether the tile woke, and for whole-tile blockers whether air left on the tile flowed out"
	var/list/blocker_types = list(
		/obj/machinery/door/firedoor/closed,
		/obj/machinery/door/firedoor/border_only/closed,
		/obj/machinery/door/firedoor/heavy,
		/obj/machinery/door/airlock/public/glass,
		/obj/machinery/door/poddoor,
		/obj/machinery/door/poddoor/shutters,
		/obj/machinery/door/window,
		/obj/structure/window/fulltile,
		/obj/structure/window/reinforced/fulltile,
		/obj/structure/window,
		/obj/structure/falsewall,
		/obj/structure/mineral_door/iron,
		/obj/structure/plasticflaps,
		/obj/structure/holosign/barrier/atmos,
		/obj/structure/foamedmetal,
		/obj/structure/inflatable,
		/obj/structure/inflatable/door,
	)
	var/list/problems = list()
	for(var/blocker_type in blocker_types)
		for(var/how in list("deleted", "wrecked", "taken apart"))
			var/line = atmos_bench_try_blocker(spot, blocker_type, how)
			. += "  [line]"
			if(findtext(line, "WRONG") || findtext(line, "NOT ") || findtext(line, "DOESN'T") || findtext(line, "DIDN'T"))
				problems += line
	atmos_bench_clean_tile(spot)

	// An inflatable door has to let air through while it's open, and only then
	var/obj/structure/inflatable/door/flap = new(spot)
	sleep(0.5 SECONDS)
	var/sides_shut = length(spot.atmos_adjacent_turfs)
	flap.SwitchState()
	var/sides_open = length(spot.atmos_adjacent_turfs)
	flap.SwitchState()
	var/sides_shut_again = length(spot.atmos_adjacent_turfs)
	var/flap_line = "inflatable door: [sides_shut] sides connected shut, [sides_open] open, [sides_shut_again] shut again[(sides_shut || sides_open != 4 || sides_shut_again) ? " - WRONG" : ""]"
	. += "  [flap_line]"
	if(findtext(flap_line, "WRONG"))
		problems += flap_line
	atmos_bench_clean_tile(spot)

	// Walls: a different one for each way of knocking one down, with extra air on one side to come through the gap.
	// A knocked down wall gets its connections from SSadjacent_air, which runs every second, so "right after" can be
	// wrong; two seconds on they have to be right.
	var/list/used = list(spot)
	for(var/how in list("dismantled", "scraped away (build mode)", "blown up", "changed to plating"))
		var/turf/closed/wall/W = atmos_bench_wall_between_floors(z, used)
		if(!W)
			. += "  no wall left to try [how] on"
			continue
		used += W
		var/x = W.x
		var/y = W.y
		var/turf/open/floor/high
		var/turf/open/floor/low
		for(var/dir in list(NORTH, EAST))
			var/turf/open/floor/one = get_step(W, dir)
			var/turf/open/floor/other = get_step(W, turn(dir, 180))
			if(istype(one) && istype(other))
				high = one
				low = other
				break
		high.air.assert_gas(/datum/gas/nitrogen)
		high.air.moles[/datum/gas/nitrogen] += 300
		SSair.add_to_active(high)
		var/low_before = low.air.total_moles()
		switch(how)
			if("dismantled")
				W.dismantle_wall()
			if("scraped away (build mode)")
				W.ScrapeAway(flags = CHANGETURF_INHERIT_AIR)
			if("blown up")
				W.ex_act(EXPLODE_DEVASTATE)
			if("changed to plating")
				W.ChangeTurf(/turf/open/floor/plating)
		var/turf/open/T = locate(x, y, z)
		if(!istype(T))
			. += "  wall [how] at ([x],[y]): still a [T.type]"
			continue
		var/list/wrong_now = atmos_bench_wrong_connections(T)
		sleep(2 SECONDS)
		var/list/wrong_later = atmos_bench_wrong_connections(T)
		sleep(2 SECONDS)
		var/gained = low.air.total_moles() - low_before
		var/line = "wall [how] at ([x],[y]): [length(wrong_now) ? "connections not in yet right after" : "connections right straight away"][length(wrong_later) ? ", still WRONG after 2 s ([jointext(wrong_later, ", ")])" : ", right after 2 s"]; [gained > 5 ? "air came through ([round(gained, 0.1)] mol reached the far side)" : "air DIDN'T come through ([round(gained, 0.1)] mol)"]"
		. += "  [line]"
		if(findtext(line, "WRONG") || findtext(line, "DIDN'T"))
			problems += line

	// A floor scraped down to space the way build mode does (keeping its air and whether it was awake), and one turned
	// into space outright: the floors around each have to start venting
	for(var/how in list("scraped down to space (build mode)", "turned into space"))
		var/turf/open/floor/F = atmos_bench_room_floor(z, used)
		if(!F)
			. += "  no room floor left to try [how] on"
			continue
		used += F
		var/x = F.x
		var/y = F.y
		var/list/turf/open/around = list()
		for(var/dir in GLOB.cardinals)
			around += get_step(F, dir)
		var/before = 0
		for(var/turf/open/neighbour as anything in around)
			before += neighbour.air.total_moles()
		if(how == "turned into space")
			F.ChangeTurf(/turf/open/space)
		else
			var/turf/T = F
			for(var/i in 1 to 5)
				if(isspaceturf(T))
					break
				T = T.ScrapeAway(flags = CHANGETURF_INHERIT_AIR)
		var/turf/T = locate(x, y, z)
		if(!isspaceturf(T))
			. += "  floor [how]: ended up a [T.type], not space"
			continue
		sleep(2 SECONDS)
		var/after = 0
		for(var/turf/open/neighbour as anything in around)
			after += neighbour.air.total_moles()
		var/line = "floor [how] at ([x],[y]): the four floors around it [after < before - 20 ? "vented ([round(before)] to [round(after)] mol)" : "DIDN'T VENT ([round(before)] to [round(after)] mol)"] in 2 s"
		. += "  [line]"
		if(findtext(line, "DIDN'T"))
			problems += line
		T.ChangeTurf(/turf/open/floor/plating) // patched up again, so the station doesn't keep venting

	// And a wall built on the test tile has to cut it off
	var/turf/built = spot.ChangeTurf(/turf/closed/wall)
	var/list/still_open = list()
	for(var/dir in GLOB.cardinals)
		var/turf/open/neighbour = get_step(built, dir)
		if(istype(neighbour) && neighbour.atmos_adjacent_turfs && neighbour.atmos_adjacent_turfs[built])
			still_open += dir2text(dir)
	var/built_line = length(still_open) ? "wall built on the test tile: neighbours STILL CONNECTED to it ([jointext(still_open, ", ")])" : "wall built on the test tile: cut off on every side"
	. += "  [built_line]"
	if(length(still_open))
		problems += built_line
	built.ChangeTurf(/turf/open/floor/plasteel)

	// Last, the real map (this takes the station apart, so nothing can come after it): everything on it that can hold
	// air back, deleted one at a time and checked, then every open tile checked against what's really around it
	sleep(2 SECONDS) // for SSadjacent_air to catch up on the tiles changed above
	. += "  every open station tile checked before the sweep: [atmos_bench_connection_audit(z)] tiles with wrong connections"
	var/list/obj/blockers = list()
	var/list/kinds = list()
	for(var/turf/open/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		for(var/obj/O in T)
			if(O.CanAtmosPass != ATMOS_PASS_YES)
				blockers += O
				kinds["[O.type]"] += 1
	var/left_wrong = 0
	var/left_asleep = 0
	for(var/obj/O as anything in blockers)
		if(QDELETED(O) || !isopenturf(O.loc))
			continue
		var/turf/open/T = O.loc
		var/type_name = "[O.type]"
		qdel(O)
		if(length(atmos_bench_wrong_connections(T)))
			left_wrong++
			problems += "[type_name] deleted at ([T.x],[T.y]) left its tile's connections WRONG"
		if(!T.excited)
			left_asleep++
			problems += "[type_name] deleted at ([T.x],[T.y]) left its tile NOT awake"
		CHECK_TICK
	sleep(2 SECONDS)
	. += "  swept [length(blockers)] air blockers of [length(kinds)] kinds off the station: [left_wrong] left connections wrong, [left_asleep] left the tile asleep"
	. += "  every open station tile checked after the sweep: [atmos_bench_connection_audit(z)] tiles with wrong connections"

	. += "  [length(problems)] problems"
	for(var/problem in problems)
		. += "    [problem]"

/// How many open tiles on a z-level have cached air connections that disagree with what's really there
/proc/atmos_bench_connection_audit(z)
	. = 0
	for(var/turf/open/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		if(T.air && !istype(T.air, /datum/gas_mixture/immutable) && length(atmos_bench_wrong_connections(T))) // space doesn't keep connections to itself
			.++
		CHECK_TICK

/// The real thing ("atmos-bench=toxins-check"): a plasma fire in the toxins lab on the real map, then every firelock
/// around the lab deleted the way build mode does, printing what's on each one's tile and what the air does after
/proc/atmos_bench_toxins_check(z)
	. = list("", "Toxins fire check")
	var/list/lab = list()
	var/sum_x = 0
	var/sum_y = 0
	for(var/turf/open/floor/F in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		if(istype(F.loc, /area/science/mixing))
			lab[F] = TRUE
			sum_x += F.x
			sum_y += F.y
	if(!length(lab))
		. += "  no toxins lab on this map"
		return
	var/turf/middle = locate(round(sum_x / length(lab)), round(sum_y / length(lab)), z)
	var/turf/open/floor/fire_spot
	var/nearest = INFINITY
	for(var/turf/open/floor/F as anything in lab)
		if(get_dist(F, middle) < nearest)
			nearest = get_dist(F, middle)
			fire_spot = F
	var/fuelled = 0
	for(var/turf/open/floor/F in range(2, fire_spot))
		if(!lab[F])
			continue
		var/datum/gas_mixture/air = F.return_air()
		air.assert_gases(/datum/gas/plasma, /datum/gas/oxygen)
		air.moles[/datum/gas/plasma] += 60
		air.moles[/datum/gas/oxygen] += 40
		SSair.add_to_active(F)
		fuelled++
	fire_spot.hotspot_expose(1000, CELL_VOLUME)
	. += "  lit [fuelled] tiles around ([fire_spot.x],[fire_spot.y]) in a lab of [length(lab)] floors"
	sleep(10 SECONDS)

	var/list/obj/machinery/door/firedoor/locks = list()
	for(var/obj/machinery/door/firedoor/door in GLOB.machines)
		if(door.z != z)
			continue
		var/near = istype(door.loc.loc, /area/science/mixing)
		for(var/dir in GLOB.cardinals)
			if(lab[get_step(door, dir)])
				near = TRUE
		if(near)
			locks += door
	. += "  [length(locks)] firelocks around the lab, 10 s into the fire ([length(SSair.hotspots)] tiles burning):"
	var/list/turf/open/tiles = list()
	for(var/obj/machinery/door/firedoor/door as anything in locks)
		var/turf/open/T = door.loc
		tiles += T
		var/list/others = list()
		for(var/obj/O in T)
			if(O != door && (istype(O, /obj/machinery/door) || istype(O, /obj/structure/window) || O.density))
				var/obj/machinery/door/other = O
				others += "[O.type][istype(O, /obj/machinery/door) ? (other.density ? " (shut)" : " (open)") : ""]"
		. += "    ([T.x],[T.y]) [door.type] [door.density ? "shut" : "open"], [length(T.atmos_adjacent_turfs)] connections, sharing the tile with: [length(others) ? jointext(others, ", ") : "nothing"]"
	var/outside_before = atmos_bench_plasma_outside(z, lab)
	for(var/obj/machinery/door/firedoor/door as anything in locks)
		if(!door.density)
			door.close()
	sleep(1 SECONDS)
	. += "  deleting them all (plasma outside the lab: [round(outside_before, 0.1)] mol)"
	for(var/obj/machinery/door/firedoor/door as anything in locks)
		qdel(door)
	for(var/turf/open/T as anything in tiles)
		var/list/wrong = atmos_bench_wrong_connections(T)
		. += "    ([T.x],[T.y]): [length(T.atmos_adjacent_turfs)] connections right after[length(wrong) ? ", WRONG: [jointext(wrong, ", ")]" : ""], [T.excited ? "awake" : "NOT AWAKE"]"
	for(var/seconds in list(2, 5, 15))
		var/start = world.time
		sleep(seconds SECONDS)
		. += "  [seconds] s later: plasma outside the lab [round(atmos_bench_plasma_outside(z, lab), 0.1)] mol, [length(SSair.hotspots)] tiles burning, [length(SSair.active_turfs)] awake (waited [(world.time - start) / 10] s)"
	for(var/turf/open/T as anything in tiles)
		var/datum/gas_mixture/air = T.air
		. += "    ([T.x],[T.y]) at the end: [round(air.total_moles())] mol, [round(air.moles[/datum/gas/plasma] || 0, 0.1)] plasma, [round(air.temperature)] K"

/// Plasma on the station's open turfs outside the lab
/proc/atmos_bench_plasma_outside(z, list/lab)
	. = 0
	for(var/turf/open/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		if(lab[T] || istype(T.loc, /area/science/storage) || istype(T.loc, /area/engine))
			continue // the plasma that's kept in canisters and tanks doesn't count
		var/datum/gas_mixture/air = T.air
		if(air && !istype(air, /datum/gas_mixture/immutable))
			. += air.moles[/datum/gas/plasma] || 0

/// One blocker: built, checked, removed one way, checked again
/proc/atmos_bench_try_blocker(turf/open/spot, blocker_type, how)
	var/label = "[blocker_type] [how]:"
	atmos_bench_clean_tile(spot)
	if(length(atmos_bench_wrong_connections(spot)))
		return "[label] the test tile's connections were wrong before starting"
	var/obj/blocker = new blocker_type(spot)
	if(istype(blocker, /obj/machinery/door))
		var/obj/machinery/door/door = blocker
		if(!door.density)
			door.close()
	sleep(1 SECONDS)
	var/list/cut = list()
	for(var/dir in GLOB.cardinals)
		if(!spot.atmos_adjacent_turfs || !spot.atmos_adjacent_turfs[get_step(spot, dir)])
			cut += dir2text(dir)
	var/blocks = length(cut) ? "blocks [jointext(cut, " ")]" : "DOESN'T BLOCK"
	var/whole_tile = length(cut) == 4
	var/before = 0
	if(whole_tile)
		// Sealed in, so extra air left here stays until the blocker goes
		spot.air.assert_gas(/datum/gas/nitrogen)
		spot.air.moles[/datum/gas/nitrogen] += 200
		before = spot.air.total_moles()
	switch(how)
		if("deleted")
			qdel(blocker)
		if("wrecked")
			blocker.take_damage(blocker.max_integrity * 4, BRUTE, "melee", FALSE)
			if(!QDELETED(blocker))
				blocker.ex_act(EXPLODE_DEVASTATE)
		if("taken apart")
			blocker.deconstruct(TRUE)
	if(!QDELETED(blocker))
		return "[label] [blocks]; still there after being [how]"
	var/list/wrong_now = atmos_bench_wrong_connections(spot)
	var/awake = spot.excited ? "awake" : "NOT AWAKE"
	sleep(2 SECONDS)
	var/list/wrong_later = atmos_bench_wrong_connections(spot)
	var/connections = length(wrong_now) ? "connections WRONG right after ([jointext(wrong_now, ", ")])" : "connections right"
	if(length(wrong_later))
		connections += ", still WRONG after 2 s ([jointext(wrong_later, ", ")])"
	var/flow = ""
	if(whole_tile)
		var/list/leftovers = list()
		for(var/obj/O in spot)
			leftovers += "[O.type]"
		var/open_sides = length(spot.atmos_adjacent_turfs)
		var/after = spot.air.total_moles()
		if(open_sides < 4)
			flow = "; air stays, as what's left still blocks ([jointext(leftovers, ", ")])"
		else
			flow = after < before - 50 ? "; air flowed out ([round(before)] to [round(after)] mol)" : "; air DIDN'T FLOW out ([round(before)] to [round(after)] mol)"
	return "[label] [blocks]; [connections]; [awake][flow]"

/// Directions where a tile's cached air connections disagree with what's on and around it now
/proc/atmos_bench_wrong_connections(turf/open/spot)
	. = list()
	for(var/dir in GLOB.cardinals)
		var/turf/open/neighbour = get_step(spot, dir)
		if(!istype(neighbour))
			continue
		var/should = !(spot.blocks_air || neighbour.blocks_air) && CANATMOSPASS(spot, spot) && CANATMOSPASS(neighbour, spot)
		var/cached = !!(spot.atmos_adjacent_turfs && spot.atmos_adjacent_turfs[neighbour])
		if(should != cached)
			. += "[dir2text(dir)] [cached ? "open, should be shut" : "shut, should be open"]"

/// Clears the test tile of whatever the last test left there, and puts its connections right
/proc/atmos_bench_clean_tile(turf/open/spot)
	for(var/obj/O in spot)
		qdel(O)
	spot.air_update_turf(TRUE)

/// An empty hallway floor tile with open floor on all four sides that it shares air with
/proc/atmos_bench_clear_tile(z)
	for(var/turf/open/floor/F in block(locate(2, 2, z), locate(world.maxx - 1, world.maxy - 1, z)))
		if(!istype(F.loc, /area/hallway) || (locate(/obj) in F) || (locate(/mob) in F))
			continue
		var/all_open = TRUE
		for(var/dir in GLOB.cardinals)
			var/turf/neighbour = get_step(F, dir)
			if(!istype(neighbour, /turf/open/floor) || !F.atmos_adjacent_turfs || !F.atmos_adjacent_turfs[neighbour])
				all_open = FALSE
				break
		if(all_open)
			return F

/// A plain wall with floor on two opposite sides and no space near it, that isn't in `used` or near one of them
/proc/atmos_bench_wall_between_floors(z, list/used)
	for(var/turf/closed/wall/W in block(locate(3, 3, z), locate(world.maxx - 2, world.maxy - 2, z)))
		if(istype(W, /turf/closed/wall/r_wall) || (W in used))
			continue
		var/ok = TRUE
		for(var/turf/T in range(2, W))
			if(isspaceturf(T) || (T in used))
				ok = FALSE
				break
		if(!ok)
			continue
		if((istype(get_step(W, NORTH), /turf/open/floor) && istype(get_step(W, SOUTH), /turf/open/floor)) \
			|| (istype(get_step(W, EAST), /turf/open/floor) && istype(get_step(W, WEST), /turf/open/floor)))
			return W

/// A floor inside a room (open floor on all four sides, no space within two tiles) that isn't in `used` or near one
/proc/atmos_bench_room_floor(z, list/used)
	for(var/turf/open/floor/F in block(locate(3, 3, z), locate(world.maxx - 2, world.maxy - 2, z)))
		if(istype(F.loc, /area/hallway) || !F.air || F.air.total_moles() < 50)
			continue
		var/ok = TRUE
		for(var/turf/T in range(2, F))
			if(isspaceturf(T) || (T in used))
				ok = FALSE
				break
		if(!ok)
			continue
		var/floors = 0
		for(var/dir in GLOB.cardinals)
			if(istype(get_step(F, dir), /turf/open/floor))
				floors++
		if(floors == 4)
			return F

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
	// Heat above room temperature, in the air and in the turfs themselves (floors and walls hold heat too), so where a
	// fire's heat went can be compared between engines
	var/air_heat = 0
	var/solid_heat = 0
	for(var/turf/T as anything in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		if(T.temperature > T20C)
			solid_heat += T.heat_capacity * (T.temperature - T20C)
		if(!isopenturf(T))
			continue
		var/turf/open/O = T
		var/datum/gas_mixture/air = O.air
		if(air && !istype(air, /datum/gas_mixture/immutable) && air.temperature > T20C)
			air_heat += air.heat_capacity() * (air.temperature - T20C)
	return "  air now, over [open] open station turfs: [round(total)] mol in all; N2O [round(n2o)] mol, on [n2o_tiles] turfs with a mole or more; plasma [round(plasma)] mol; [low_pressure] turfs under 20 kPa; [hot] turfs over 100 C; heat over 20 C: [round(air_heat / 1e6, 0.1)] MJ in the air, [round(solid_heat / 1e6, 0.1)] MJ in turfs"

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
