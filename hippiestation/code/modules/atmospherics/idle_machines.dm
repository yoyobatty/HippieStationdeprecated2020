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

/// A turf's air changed: what was idle on it runs again
/datum/controller/subsystem/air/proc/atmos_wake_turf(turf/T)
	var/list/obj/machinery/waiting = T.idle_atmos_machines
	T.idle_atmos_machines = null
	for(var/obj/machinery/M as anything in waiting)
		M.atmos_idle_turf = null
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
	if(!atmos_recheck)
		atmos_recheck = list()
		for(var/i in 1 to ATMOS_IDLE_RECHECK)
			atmos_recheck += list(list())
	var/list/obj/machinery/bucket = atmos_recheck[(fired % ATMOS_IDLE_RECHECK) + 1]
	bucket += M

/// An idle machine moved: it waits on its new turf, unless that turf's air has changed since it went idle
/datum/controller/subsystem/air/proc/atmos_idle_moved(obj/machinery/M)
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
			atmos_recheck[(fired % ATMOS_IDLE_RECHECK) + 1] = list()
			for(var/obj/machinery/M as anything in bucket)
				if(M?.atmos_idle_since && fired - M.atmos_idle_since >= ATMOS_IDLE_RECHECK)
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
