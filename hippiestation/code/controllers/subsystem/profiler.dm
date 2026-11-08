// Duty-cycled profiling (hippie, 2026-11-08, the user's "optimize the profiler as much as possible").
//
// BYOND's profiler adds ~255 ns to every proc call while it's on (516.1688: a call 110 -> 365 ns; loops without calls cost
// the same either way), all inside byondcore, so nothing in DM makes a call cheaper. Over a round that was +20-45% on every
// subsystem (Bot Shifts side by side, 2026-11-07). Stopping and starting it keeps adding to the same figures, and a toggle
// costs under a microsecond, so with AUTO_PROFILE it's on for 1 s in every 10 (PROFILE_DUTY 10, the default): a round's
// profile is built from samples spread over all of it, for a tenth of the cost. PROFILE_DUTY 100 is the old always-on.
// PROFILE 30 S on a lag alert (mc_watchdog.dm) turns it fully on for its 30 s, then the cycle carries on.

/datum/controller/subsystem/profiler
	/// With AUTO_PROFILE: the share of the time (%) the profiler is on (config PROFILE_DUTY)
	var/duty = 100
	/// REALTIMEOFDAY until which it stays fully on (PROFILE 30 S)
	var/full_until = 0
	/// Real time (ds) it's been on, and since the cycle started, for reading the figures
	var/on_time = 0
	var/cycle_started = 0
	var/cycle_running = FALSE
	/// Whether the cycle has it on right now
	var/cycle_on = FALSE

/datum/controller/subsystem/profiler/Initialize()
	. = ..()
	if(profiling)
		duty = CONFIG_GET(number/profile_duty)
		if(duty < 100)
			duty_cycle()

/datum/controller/subsystem/profiler/stat_entry(msg)
	if(profiling && duty < 100)
		msg += "[duty]% of the time ([round(on_time / max(1, REALTIMEOFDAY - cycle_started) * 100, 0.1)]% so far)|"
	return ..(msg)

/// On for half a second in every (50 / duty) s of game time, at a random point in each, and fully on while full_until hasn't
/// passed. The random point matters: a window at the same point of every period lined up with subsystems that fire every 1 or 2
/// s and counted them always or never (a 10% profile put 4 of the full one's top 10 procs in its own; Bot Shifts 2026-11-08).
/datum/controller/subsystem/profiler/proc/duty_cycle()
	set waitfor = FALSE
	if(cycle_running)
		return
	cycle_running = TRUE
	cycle_started = REALTIMEOFDAY
	cycle_on = TRUE // Initialize() left it on
	var/window = 0.5 SECONDS
	var/period_ends = 0
	var/on_from = 0
	while(profiling && duty < 100)
		if(world.time >= period_ends)
			var/period = window * 100 / max(1, duty)
			period_ends = world.time + period
			on_from = world.time + rand(0, max(0, round((period - window) / world.tick_lag))) * world.tick_lag
		var/on = REALTIMEOFDAY < full_until || (world.time >= on_from && world.time < on_from + window)
		if(on != cycle_on)
			world.Profile(on ? PROFILE_START : PROFILE_STOP)
			cycle_on = on
		var/before = REALTIMEOFDAY
		sleep(world.tick_lag)
		if(cycle_on)
			on_time += REALTIMEOFDAY - before
	if(!profiling && cycle_on)
		world.Profile(PROFILE_STOP)
	cycle_running = FALSE

/// What share of the time the figures cover, for reports (1 = all of it)
/datum/controller/subsystem/profiler/proc/sampled_share()
	if(!profiling || duty >= 100 || REALTIMEOFDAY < full_until)
		return 1
	return on_time / max(1, REALTIMEOFDAY - cycle_started)

/// world.Profile(PROFILE_REFRESH) reads the figures, and PROFILE_REFRESH is 0, the same as PROFILE_START: every read turns the
/// profiler on. In the cycle's off part, turn it straight back off. Call after any read.
/datum/controller/subsystem/profiler/proc/after_read()
	if(cycle_running && !cycle_on)
		world.Profile(PROFILE_STOP)

// tg's, with the profiler stopped again right after the read in the cycle's off part, before the write is counted
/datum/controller/subsystem/profiler/DumpFile()
	var/timer = TICK_USAGE_REAL
	var/current_profile_data = world.Profile(PROFILE_REFRESH, format = "json")
	after_read()
	fetch_cost = MC_AVERAGE(fetch_cost, TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer))
	CHECK_TICK
	if(!length(current_profile_data)) //Would be nice to have explicit proc to check this
		stack_trace("Warning, profiling stopped manually before dump.")
	var/json_file = file("[GLOB.log_directory]/profiler.json")
	if(fexists(json_file))
		fdel(json_file)
	timer = TICK_USAGE_REAL
	WRITE_FILE(json_file, current_profile_data)
	write_cost = MC_AVERAGE(write_cost, TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer))
