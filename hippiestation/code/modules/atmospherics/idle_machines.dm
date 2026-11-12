// Idle atmos machines: vents, scrubbers, tank sensors and shut canisters with nothing to do stop being run every
// atmos tick.
//
// A vent in a full room or a scrubber over clean air spends every tick finding out it has nothing to do. Instead its
// process_atmos() returns ATMOS_IDLE, and SSair skips it until its turf's air changes, its settings change
// (atmos_wake()), or ATMOS_IDLE_RECHECK ticks go by. The last one is a backstop for anything that changes a machine
// without waking it, like an admin editing its vars.
//
// A turf's air counts as changed when the tile engine changes it or anything calls add_to_active() on it, which is
// what code that changes a turf's air already does. Only while the tile engine runs turfs: LINDA doesn't keep track.
//
// Idle machines aren't even looked at (2026-11-06). The machinery stage used to go through all of atmos_machinery every tick
// to find the few awake ones, looking at each idle one's turf: SSair.atmos_awake now holds the ones that run, in
// atmos_machinery's order (atmos_serial), and an idle one waits on its turf's idle_atmos_machines until one of the things
// above wakes it - which is what that check looked for, so the same machines run on the same ticks in the same order. The
// recheck backstop is atmos_recheck, a list for each tick of ATMOS_IDLE_RECHECK. Boot with atmos-idle-shadow=1 to run the old
// check alongside and count any machine the two disagree on (the atmos bench and stress bench print it).

/atom
	/// SSair's times_fired when this turf's air last changed (see idle_machines.dm). Only turfs set it; it's on /atom so
	/// a machine that ends up inside something, like a canister in a mech, reads 0.
	var/air_changed_at = 0

/obj/machinery
	/// The tile engine watches us while we're idle, and wakes us when our turf's air gives us something to do (atmos_watch_params())
	var/atmos_engine_watched = FALSE
	/// atmos-machine-filter=shadow: we were woken by the engine changing our turf's air, and the engine said we'd have something to do
	var/atmos_air_woken = FALSE
	var/atmos_engine_predicted = FALSE
	/// SSair's times_fired when process_atmos() last said there was nothing to do, or 0 if it runs every tick
	var/atmos_idle_since = 0
	/// When we were put in SSair.atmos_machinery, in the order it keeps: SSair.start_processing_machine()
	var/atmos_serial = 0
	/// The turf whose idle_atmos_machines we wait on, while we're idle on a turf
	var/turf/atmos_idle_turf
	/// We're in SSair.atmos_woken, to join SSair.atmos_awake at the next machinery stage
	var/atmos_wake_queued = FALSE

/turf
	/// Idle atmos machines on us, woken when our air changes
	var/list/obj/machinery/idle_atmos_machines

/datum/controller/subsystem/air
	var/atmos_serial_next = 0
	/// The machines the machinery stage runs: atmos_machinery without the idle ones, in its order
	var/list/obj/machinery/atmos_awake = list()
	/// Idle machines woken since the machinery stage last started, to join atmos_awake when it next does
	var/list/obj/machinery/atmos_woken = list()
	/// ATMOS_IDLE_RECHECK lists: a machine that goes idle on tick T is in list (T % ATMOS_IDLE_RECHECK) + 1, to be looked at
	/// again on tick T + ATMOS_IDLE_RECHECK if nothing has woken it by then
	var/list/atmos_recheck
	/// While the machinery stage runs: the atmos_serial of the machine it's on. A machine woken with a lower one is still to
	/// come in this run, and joins it, as the old check would have run it when it got there.
	var/atmos_run_serial = -1
	/// The run it joins: the machinery stage's currentrun (or, shadowing, the run the registry would have made)
	var/list/obj/machinery/atmos_run_list
	/// atmos-idle-shadow=1: the old check runs the machines and the registry is set against it. Counts.
	var/list/atmos_idle_shadow
	var/list/obj/machinery/atmos_shadow_run

/// Has SSair run process_atmos() again from the next atmos tick, for when the machine's settings change
/obj/machinery/proc/atmos_wake()
	if(atmos_idle_since)
		SSair.atmos_wake_machine(src)

/obj/machinery/Moved(atom/OldLoc, Dir, Forced = FALSE)
	. = ..()
	if(atmos_idle_since)
		SSair.atmos_idle_moved(src)

/obj/machinery/afterShuttleMove(turf/oldT, list/movement_force, shuttle_dir, shuttle_preferred_direction, move_dir, rotation)
	. = ..()
	if(atmos_idle_since) // a shuttle sets loc without Moved()
		SSair.atmos_idle_moved(src)

/// Keeps a list sorted by atmos_serial, smallest first, with the machine in it once
/proc/atmos_insert_by_serial(list/obj/machinery/L, obj/machinery/M)
	var/serial = M.atmos_serial
	var/low = 1
	var/high = length(L) + 1
	while(low < high)
		var/middle = round((low + high) / 2)
		var/obj/machinery/other = L[middle]
		if((other ? other.atmos_serial : 0) < serial)
			low = middle + 1
		else
			high = middle
	if(low <= length(L) && L[low] == M)
		return
	L.Insert(low, M)

/// An idle machine is to run again: from the next machinery stage, or in this one if it's still to come
/datum/controller/subsystem/air/proc/atmos_wake_machine(obj/machinery/M)
	if(M.atmos_engine_watched) // the tile engine stops watching it
		M.atmos_engine_watched = FALSE
		tile_engine_machine_events.Add(2, M.atmos_serial)
	M.atmos_idle_since = 0
	var/turf/T = M.atmos_idle_turf
	if(T)
		LAZYREMOVE(T.idle_atmos_machines, M)
		M.atmos_idle_turf = null
	if(atmos_run_list && M.atmos_serial < atmos_run_serial && currentpart == SSAIR_ATMOSMACHINERY)
		atmos_insert_by_serial(atmos_run_list, M)
	if(!M.atmos_wake_queued)
		M.atmos_wake_queued = TRUE
		atmos_woken += M

/// A turf's air changed: what was idle on it runs again. When the tile engine changed it (`from_engine`), the machines it
/// watches are left to it: it wakes the ones whose air gives them something to do (tile_engine_machine_wakes()).
/datum/controller/subsystem/air/proc/atmos_wake_turf(turf/T, from_engine = FALSE)
	var/list/obj/machinery/waiting = T.idle_atmos_machines
	if(from_engine && tile_engine_machine_filter == "on")
		var/list/obj/machinery/still
		for(var/obj/machinery/M as anything in waiting)
			if(M.atmos_engine_watched)
				LAZYADD(still, M)
				continue
			M.atmos_idle_turf = null
			if(M.atmos_idle_since)
				atmos_wake_machine(M)
		T.idle_atmos_machines = still
		return
	T.idle_atmos_machines = null
	for(var/obj/machinery/M as anything in waiting)
		M.atmos_idle_turf = null
		if(from_engine && M.atmos_engine_watched) // atmos-machine-filter=shadow: to check the engine's word against what it does
			M.atmos_air_woken = TRUE
		if(M.atmos_idle_since)
			atmos_wake_machine(M)

/// process_atmos() said there's nothing to do
/datum/controller/subsystem/air/proc/atmos_went_idle(obj/machinery/M, fired)
	M.atmos_idle_since = fired
	var/turf/T = M.loc
	if(isturf(T))
		if(T.air_changed_at >= fired) // changed earlier this tick: the old check ran it again next tick
			atmos_wake_machine(M)
			return
		LAZYADD(T.idle_atmos_machines, M)
		M.atmos_idle_turf = T
		if(tile_engine_machine_filter != "off")
			tile_engine_watch(M, T)
	if(!atmos_recheck)
		atmos_recheck = list()
		for(var/i in 1 to ATMOS_IDLE_RECHECK)
			atmos_recheck += list(list())
	var/list/obj/machinery/bucket = atmos_recheck[(fired % ATMOS_IDLE_RECHECK) + 1]
	bucket += M

/// An idle machine moved: it waits on its new turf, unless that turf's air has changed since it went idle
/datum/controller/subsystem/air/proc/atmos_idle_moved(obj/machinery/M)
	if(M.atmos_engine_watched) // watched on the turf it left: from here on any change in the air wakes it
		M.atmos_engine_watched = FALSE
		tile_engine_machine_events.Add(2, M.atmos_serial)
	var/turf/old = M.atmos_idle_turf
	if(old)
		LAZYREMOVE(old.idle_atmos_machines, M)
		M.atmos_idle_turf = null
	var/turf/T = M.loc
	if(!isturf(T))
		return
	if(T.air_changed_at >= M.atmos_idle_since)
		atmos_wake_machine(M)
	else
		LAZYADD(T.idle_atmos_machines, M)
		M.atmos_idle_turf = T

/// The start of a machinery stage: machines due their recheck wake, and everything woken joins atmos_awake
/datum/controller/subsystem/air/proc/atmos_idle_due(fired)
	if(atmos_recheck)
		var/list/obj/machinery/bucket = atmos_recheck[(fired % ATMOS_IDLE_RECHECK) + 1]
		if(length(bucket))
			var/list/obj/machinery/again = list()
			atmos_recheck[(fired % ATMOS_IDLE_RECHECK) + 1] = again
			for(var/obj/machinery/M as anything in bucket)
				if(M?.atmos_idle_since && fired - M.atmos_idle_since >= ATMOS_IDLE_RECHECK)
					// The tile engine watches its air, so only something that changed it without waking it is left to catch:
					// 20 seconds will do (every one of tens of thousands of 10-tick rechecks of a watched machine found nothing)
					if(M.atmos_engine_watched && fired - M.atmos_idle_since < ATMOS_IDLE_RECHECK_WATCHED)
						again += M
						continue
					atmos_wake_machine(M)
	if(!length(atmos_woken))
		return
	var/list/obj/machinery/woken = atmos_woken
	atmos_woken = list()
	for(var/obj/machinery/M as anything in woken)
		M.atmos_wake_queued = FALSE
	if(length(woken) > 48) // a lot at once: put the list together afresh, by serial
		var/list/obj/machinery/slots = new /list(atmos_serial_next)
		for(var/obj/machinery/M as anything in atmos_awake)
			if(M?.atmos_serial)
				slots[M.atmos_serial] = M
		for(var/obj/machinery/M as anything in woken)
			if(M?.atmos_serial && !M.atmos_idle_since)
				slots[M.atmos_serial] = M
		var/list/obj/machinery/rebuilt = list()
		for(var/obj/machinery/M as anything in slots)
			if(M)
				rebuilt += M
		atmos_awake = rebuilt
		return
	for(var/obj/machinery/M as anything in woken)
		if(M?.atmos_serial && !M.atmos_idle_since)
			atmos_insert_by_serial(atmos_awake, M)

/// The end of a machinery stage: atmos_awake without the ones that went idle in it
/datum/controller/subsystem/air/proc/atmos_idle_settle()
	atmos_run_serial = -1
	atmos_run_list = null
	var/list/obj/machinery/still = list()
	for(var/obj/machinery/M as anything in atmos_awake)
		if(M && !M.atmos_idle_since)
			still += M
	atmos_awake = still

/// The machinery stage with the registry: only the awake machines
/datum/controller/subsystem/air/proc/process_awake_machinery(delta_time, resumed)
	var/fired = times_fired
	if(!resumed)
		atmos_idle_due(fired)
		src.currentrun = atmos_awake.Copy()
		atmos_run_list = src.currentrun
		atmos_run_serial = INFINITY
	var/list/currentrun = src.currentrun
	while(currentrun.len)
		var/obj/machinery/M = currentrun[currentrun.len]
		currentrun.len--
		if(!M)
			continue
		atmos_run_serial = M.atmos_serial
		var/result = M.process_atmos(delta_time)
		if(M.atmos_air_woken) // atmos-machine-filter=shadow: what it did against what the engine said it would
			tile_engine_machine_shadow_check(M, result != ATMOS_IDLE)
		M.atmos_engine_predicted = FALSE
		if(result == PROCESS_KILL)
			stop_processing_machine(M)
		else if(result == ATMOS_IDLE)
			atmos_went_idle(M, fired)
		if(MC_TICK_CHECK)
			return
	atmos_idle_settle()

/// The machinery stage looking at every machine, as it always did: with LINDA, with atmos-idle=off, and to shadow the registry
/datum/controller/subsystem/air/proc/process_every_machine(delta_time, resumed, can_idle)
	var/fired = times_fired
	var/shadow = atmos_idle_shadow && can_idle
	if(!resumed)
		src.currentrun = atmos_machinery.Copy()
		if(shadow)
			atmos_idle_due(fired)
			atmos_shadow_run = atmos_awake.Copy()
			atmos_run_list = atmos_shadow_run
			atmos_run_serial = INFINITY
	var/list/currentrun = src.currentrun
	while(currentrun.len)
		var/obj/machinery/M = currentrun[currentrun.len]
		currentrun.len--
		if(!M)
			atmos_machinery.Remove(M)
		else
			var/runs = TRUE
			if(M.atmos_idle_since)
				var/turf/T = M.loc
				if(can_idle && T?.air_changed_at < M.atmos_idle_since && fired - M.atmos_idle_since < ATMOS_IDLE_RECHECK)
					runs = FALSE
			if(shadow)
				atmos_run_serial = M.atmos_serial
				var/list/obj/machinery/registry_run = atmos_shadow_run
				var/registry_runs = length(registry_run) && registry_run[length(registry_run)] == M
				if(registry_runs)
					registry_run.len--
				if(registry_runs == runs)
					atmos_idle_shadow["agree"]++
				else
					atmos_idle_shadow[runs ? "only the old check ran it" : "only the registry ran it"]++
					if(length(atmos_idle_shadow) < 12)
						atmos_idle_shadow["[runs ? "old" : "registry"]: [M.type] at [AREACOORD(M)] idle since [M.atmos_idle_since], turf changed [M.loc?.air_changed_at], tick [fired]"] = 1
			if(!runs)
				continue
			if(M.atmos_idle_turf)
				LAZYREMOVE(M.atmos_idle_turf.idle_atmos_machines, M)
				M.atmos_idle_turf = null
			M.atmos_idle_since = 0
			var/result = M.process_atmos(delta_time)
			if(result == PROCESS_KILL)
				stop_processing_machine(M)
			else if(result == ATMOS_IDLE && can_idle)
				if(shadow)
					atmos_went_idle(M, fired)
				else
					M.atmos_idle_since = fired
		if(MC_TICK_CHECK)
			return
	if(shadow)
		atmos_idle_settle()

// ---------------------------------------------------------------------------------------------
// The tile engine watching idle vents and scrubbers (tools/atmos_engine/src/machines.rs). A vent in a full room goes idle,
// and the air on its turf changes nearly every tick while the room settles: each change woke it to find out again that it
// had nothing to do. Now when one goes idle the engine is told its turf and what its own check looks at, and when the engine
// changes that turf's air it wakes it only if the check would come out differently. Everything else that wakes it (its
// settings, power, moving, DM changing the air, the recheck) still does, and tells the engine. -params
// "atmos-machine-filter=shadow" wakes them as before and counts any that had something to do when the engine said they
// wouldn't; "off" leaves it all to DM.
// ---------------------------------------------------------------------------------------------

/datum/controller/subsystem/air
	/// "on", "shadow" or "off" (needs the engine keeping LINDA's state, atmos-engine-own=on)
	var/tile_engine_machine_filter = "off"
	/// Machines going idle and waking for the engine: 1, atmos_serial, turf, kind, flags, bound, filters; or 2, atmos_serial
	var/list/tile_engine_machine_events = list()
	/// atmos_serial -> machine, for the ones the engine wakes
	var/list/obj/machinery/tile_engine_machine_serials = list()
	/// Gas path -> its bit in the engine's filters
	var/list/tile_engine_gas_bits = list()
	/// From the engine: machines watched, turfs looked at, kept idle, woken
	var/list/tile_engine_machine_stats
	/// atmos-machine-filter=shadow: machines woken by a change in the air, how many had something to do though the engine said
	/// they wouldn't, and how many the engine would have woken for nothing
	var/list/tile_engine_machine_shadow = list("checked" = 0, "missed" = 0, "woken for nothing" = 0)

/// What the tile engine needs to tell whether our turf's air gives us something to do: list(kind, flags, bound, filters) as
/// machines.rs takes them, or null to be woken by any change in the air
/obj/machinery/proc/atmos_watch_params()
	return null

/obj/machinery/atmospherics/components/unary/vent_pump/atmos_watch_params()
	if(!is_operational() || !nodes[1] || !on || welded)
		return list(3, 0, 0, 0) // idle for its settings, which wake it when they change
	var/flags = 0
	if(pump_direction & 1) // RELEASING, vent_pump.dm
		flags |= 1
	if(pressure_checks & 1) // EXT_BOUND
		flags |= 2
	return list(1, flags, external_pressure_bound, 0)

/obj/machinery/atmospherics/components/unary/vent_scrubber/atmos_watch_params()
	if(welded || !is_operational() || !nodes[1] || !on)
		return list(3, 0, 0, 0)
	if(widenet || !(scrubbing & 1)) // SCRUBBING, vent_scrubber.dm
		return null // it doesn't go idle for its air
	var/filters = 0
	var/list/bits = SSair.tile_engine_gas_bits
	for(var/gas in filter_types)
		filters |= bits[gas]
	return list(2, 0, 0, filters)

/// Turns the engine's watching on if atmos-machine-filter asks for it and the library has it
/datum/controller/subsystem/air/proc/tile_engine_machine_setup()
	tile_engine_machine_filter = "off"
	var/wanted = world.params["atmos-machine-filter"] || "on"
	if(wanted == "off" || !tile_engine_owns)
		return
	try
		call_ext(GLOB.tile_engine_lib, "byond:atmos_engine_machine_wakes")(list(), null)
	catch
		log_world("Atmos: the tile engine can't watch idle machines (an older hippie_atmos), so any change in the air wakes them")
		return
	tile_engine_gas_bits = list()
	for(var/i in 1 to length(tile_engine_gas_types))
		tile_engine_gas_bits[tile_engine_gas_types[i]] = 1 << (i - 1)
	tile_engine_machine_filter = wanted == "shadow" ? "shadow" : "on"
	log_world("Atmos: the tile engine watches idle vents and scrubbers ([tile_engine_machine_filter])")

/// It went idle on T: the engine watches it, if it can tell from the air when it'll have something to do
/datum/controller/subsystem/air/proc/tile_engine_watch(obj/machinery/M, turf/T)
	var/list/params = M.atmos_watch_params()
	if(!params)
		return
	var/serial = M.atmos_serial
	if(serial > length(tile_engine_machine_serials))
		tile_engine_machine_serials.len = serial
	tile_engine_machine_serials[serial] = M
	tile_engine_machine_events.Add(1, serial, T, params[1], params[2], params[3], params[4])
	M.atmos_engine_watched = TRUE

/// The machines the engine woke, after it changed some turfs' air
/datum/controller/subsystem/air/proc/tile_engine_machine_wakes()
	if(tile_engine_machine_filter == "off")
		return
	var/list/serials = list()
	var/list/stats = list()
	try
		call_ext(GLOB.tile_engine_lib, "byond:atmos_engine_machine_wakes")(serials, stats)
	catch(var/exception/error)
		stack_trace("Atmos: machine wakes failed: [error]")
		tile_engine_machine_filter = "off"
		return
	tile_engine_machine_stats = stats
	var/shadow = tile_engine_machine_filter == "shadow"
	var/list/obj/machinery/machines = tile_engine_machine_serials
	for(var/serial in serials)
		var/obj/machinery/M = serial <= length(machines) ? machines[serial] : null
		if(!M)
			continue
		if(shadow) // DM woke it anyway: note what the engine said
			M.atmos_engine_predicted = TRUE
			continue
		if(M.atmos_engine_watched && M.atmos_idle_since)
			M.atmos_engine_watched = FALSE // the engine has already let it go
			atmos_wake_machine(M)

/// atmos-machine-filter=shadow: a machine woken by a change in the air has run
/datum/controller/subsystem/air/proc/tile_engine_machine_shadow_check(obj/machinery/M, acted)
	M.atmos_air_woken = FALSE
	var/list/counts = tile_engine_machine_shadow
	counts["checked"]++
	if(acted && !M.atmos_engine_predicted)
		counts["missed"]++
		if(length(counts) < 13)
			counts["[M.type] at [AREACOORD(M)], tick [times_fired]"] = 1
	else if(!acted && M.atmos_engine_predicted)
		counts["woken for nothing"]++
