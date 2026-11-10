// The profiler with AUTO_PROFILE (hippie, 2026-11-08, the user's "optimize the profiler as much as possible" and "develop our
// own profiler system that is super cheap").
//
// First choice: hippie_prof.dll (tools/hippie_prof), our own. A hook on byondcore's exec_proc keeps a shadow stack of proc ids
// and a thread of its own samples it every millisecond: +3 ns a proc call (516.1688, 117 -> 120 ns), on all round, every proc
// counted; and it keeps the last ~65 s of samples, so a freeze is put down to the proc that held the server. It knows the BYOND
// builds whose insides it has the addresses for (516.1666, 516.1688) and refuses any other.
//
// Otherwise BYOND's own, world.Profile, which adds ~255 ns to every proc call while it's on (a call 110 -> 365 ns; loops
// without calls the same), all inside byondcore. Over a round that was +20-45% on every subsystem (Bot Shifts side by side,
// 2026-11-07). It keeps adding to the same figures across stop and start, and a toggle costs under a microsecond, so it's on
// for half a second at a random point in every (50 / PROFILE_DUTY) s (10, the default): +7% instead of +28%, its profile
// within 0.17 points a proc of the full one's. PROFILE 30 S on a lag alert (mc_watchdog.dm) turns it fully on for 30 s.
// BYOND_PROFILER in config.txt uses BYOND's whatever the DLL can do.

#define HIPPIE_PROF_DLL "hippie_prof.dll"

/// Calls one of hippie_prof.dll's procs; "error: ..." when there's no DLL
/proc/hippie_prof(proc_name, arg)
	if(world.system_type != MS_WINDOWS || !fexists(HIPPIE_PROF_DLL))
		return "error: no [HIPPIE_PROF_DLL]"
	return isnull(arg) ? call_ext(HIPPIE_PROF_DLL, proc_name)() : call_ext(HIPPIE_PROF_DLL, proc_name)("[arg]")

/datum/controller/subsystem/profiler
	/// "hippie" when hippie_prof.dll does the profiling, "byond" for world.Profile
	var/engine = "byond"
	/// With BYOND's: the share of the time (%) it's on (config PROFILE_DUTY)
	var/duty = 100
	/// REALTIMEOFDAY until which BYOND's stays fully on (PROFILE 30 S)
	var/full_until = 0
	/// Real time (ds) BYOND's has been on, and since the cycle started, for reading the figures
	var/on_time = 0
	var/cycle_started = 0
	var/cycle_running = FALSE
	/// Whether the cycle has BYOND's on right now
	var/cycle_on = FALSE

/datum/controller/subsystem/profiler/Initialize()
	. = ..()
	if(!profiling)
		return
	if(!CONFIG_GET(flag/byond_profiler))
		var/started = hippie_prof("start")
		if(findtext(started, "ok") == 1)
			engine = "hippie"
			world.Profile(PROFILE_STOP) // BYOND's (on since world/New) is off: ours does it
			log_world("Profiler: [HIPPIE_PROF_DLL] ([started])")
			return
		log_world("Profiler: [HIPPIE_PROF_DLL] not used ([started]), BYOND's at PROFILE_DUTY instead")
	duty = CONFIG_GET(number/profile_duty)
	if(duty < 100)
		duty_cycle()

/datum/controller/subsystem/profiler/stat_entry(msg)
	if(profiling && engine == "hippie")
		msg += "hippie_prof|"
	else if(profiling && duty < 100)
		msg += "[duty]% of the time ([round(on_time / max(1, REALTIMEOFDAY - cycle_started) * 100, 0.1)]% so far)|"
	return ..(msg)

/// BYOND's: on for half a second in every (50 / duty) s of game time, at a random point in each, and fully on while full_until
/// hasn't passed. The random point matters: a window at the same point of every period lined up with subsystems that fire every
/// 1 or 2 s and counted them always or never (a 10% profile put 4 of the full one's top 10 procs in its own; Bot Shifts 2026-11-08).
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
	while(profiling && duty < 100 && engine == "byond")
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

/// What share of the time BYOND's figures cover, for reports (1 = all of it)
/datum/controller/subsystem/profiler/proc/sampled_share()
	if(!profiling || engine == "hippie" || duty >= 100 || REALTIMEOFDAY < full_until)
		return 1
	return on_time / max(1, REALTIMEOFDAY - cycle_started)

/// world.Profile(PROFILE_REFRESH) reads the figures, and PROFILE_REFRESH is 0, the same as PROFILE_START: every read turns the
/// profiler on. In the cycle's off part, or with hippie_prof doing the profiling, turn it straight back off. Call after any read.
/datum/controller/subsystem/profiler/proc/after_read()
	if((cycle_running && !cycle_on) || engine == "hippie")
		world.Profile(PROFILE_STOP)

/// The procs that were running in the last `ms` of real time, most first (hippie_prof only): list(name = seconds)
/datum/controller/subsystem/profiler/proc/recent(ms)
	. = list()
	if(engine != "hippie")
		return
	var/list/rows = json_decode(hippie_prof("recent", round(ms)))
	for(var/list/row in rows)
		.[row["name"]] = row["self"]

/// The five stacks the server was in most over the last `ms` of real time, the heaviest first (hippie_prof only): list(list("ms",
/// "depth", "stack" = list(bottom ... top)), ...). The top 32 frames of each; "depth" is how deep it really was.
/datum/controller/subsystem/profiler/proc/recent_stacks(ms)
	. = list()
	if(engine != "hippie")
		return
	var/list/rows = json_decode(hippie_prof("stacks", round(ms)))
	for(var/list/row in rows)
		. += list(row)

// tg's, from hippie_prof when it's doing the profiling, and with BYOND's stopped again right after the read in the cycle's off part
/datum/controller/subsystem/profiler/DumpFile()
	var/timer = TICK_USAGE_REAL
	var/current_profile_data
	if(engine == "hippie")
		current_profile_data = hippie_prof("dump")
	else
		current_profile_data = world.Profile(PROFILE_REFRESH, format = "json")
		after_read()
	fetch_cost = MC_AVERAGE(fetch_cost, TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer))
	CHECK_TICK
	if(!length(current_profile_data)) //Would be nice to have explicit proc to check this
		stack_trace("Warning, profiling stopped manually before dump.")
	// Written over the old one by the log writer's thread (hippie_log_replace(), __HELPERS/log_writer.dm), not fdel() and WRITE_FILE()
	// here and now: 0.4-0.9 MB every 5 minutes, on the game's thread, was the one write left that a slow drive could still stall it on.
	timer = TICK_USAGE_REAL
	hippie_log_replace("[GLOB.log_directory]/profiler.json", current_profile_data)
	write_cost = MC_AVERAGE(write_cost, TICK_DELTA_TO_MS(TICK_USAGE_REAL - timer))

#undef HIPPIE_PROF_DLL
