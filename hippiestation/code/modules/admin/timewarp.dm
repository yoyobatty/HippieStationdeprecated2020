// Timewarp - fast-forward for headless runs (Bot Shift, Bot Gym, the self-tests).
//
// BYOND has no time-scale or fixed-step switch, so this is done from outside: timewarp.dll
// (tools/timewarp/) takes over the server's tick timer and clock, and the idle wait between ticks
// is skipped. The game still runs one ordinary tick at a time - same tick_lag, same world.time per
// tick, and world.tick_usage still measures the real CPU time a tick took - it just doesn't sit
// out the rest of each tick. So nothing in the game runs differently; it's only how busy the
// server is that sets how much faster it goes.
//
// Boot with -params "timewarp=0" for no speed limit, or "timewarp=10" for at most ten times real
// time. Meant for runs nobody is connected to - a connected player would see everything sped up.

#define TIMEWARP_LIBRARY "timewarp.dll"

/// What the game speed was last set to: 1 is real time, 0 is no limit, N is at most N times real time.
GLOBAL_VAR_INIT(timewarp_speed, 1)
GLOBAL_VAR_INIT(timewarp_loaded, FALSE)

/// Sets the game speed (see GLOB.timewarp_speed). Returns TRUE if it took effect.
/proc/timewarp_set_speed(speed)
	speed = max(text2num("[speed]") || 0, 0)
	if(world.system_type != MS_WINDOWS || !fexists(TIMEWARP_LIBRARY))
		log_world("TIMEWARP: [TIMEWARP_LIBRARY] not found, staying at real time - build it with tools/timewarp/build.bat")
		return FALSE
	var/result = call_ext(TIMEWARP_LIBRARY, "timewarp_speed")("[speed]")
	if(result != "ok")
		log_world("TIMEWARP: [result] - staying at real time")
		return FALSE
	GLOB.timewarp_loaded = TRUE
	GLOB.timewarp_speed = speed
	log_world("TIMEWARP: game speed [speed == 1 ? "back to real time" : (speed ? "up to [speed]x" : "unlimited")]")
	return TRUE

/// Real milliseconds on a clock that keeps real time whatever the game speed is - world.timeofday
/// and world.realtime follow game time once timewarp is on. Only differences between two readings
/// mean anything.
/proc/timewarp_real_ms()
	if(!GLOB.timewarp_loaded)
		return REALTIMEOFDAY * 100
	return text2num(splittext(call_ext(TIMEWARP_LIBRARY, "timewarp_clock")(), " ")[1])

#undef TIMEWARP_LIBRARY
