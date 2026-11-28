// The BYOND behaviour the MC's stale-fire guard leans on (code/controllers/subsystem.dm pause() and current_run()), checked
// on its own in a world of a few procs, in a second. Re-run it after a BYOND update.
//
//   A proc that slept under a waitfor = FALSE caller still finds that caller through `caller` when it wakes, with the
//   arguments it was called with, so pause() can tell which run of ignite() it's in: the one the MC counts now, or one it
//   gave up on. And what that walk costs.
//
// Run: tools/mc_check/run_callee_probe.sh (builds in a temp folder, nothing left in the repo). PASS/FAIL lines on the terminal.

#define PROBE_TICK_USAGE world.tick_usage

/datum/probe_ss
	var/list/seen = list()

/datum/probe_ss/proc/ignite(resumed, generation)
	set waitfor = FALSE
	fire(resumed)

/datum/probe_ss/proc/fire(resumed)
	if(resumed)
		sleep(resumed)
	helper()

/datum/probe_ss/proc/helper()
	seen += list(list(world.time, find_generation()))

/// Like current_run(): up the callers to this datum's ignite(), and the generation it was called with
/datum/probe_ss/proc/find_generation()
	var/callee/frame = caller
	for(var/i in 1 to 32)
		if(!frame)
			return "none"
		if(frame.proc == /datum/probe_ss/proc/ignite && frame.src == src)
			return frame.args[2]
		frame = frame.caller
	return "too deep"

/world/New()
	..()
	spawn(1)
		var/datum/probe_ss/S = new
		// run 1 sleeps 10 ds; run 2, started at once after it (as the watchdog does), sleeps 3, so it wakes first; run 3, of the
		// same generation as run 2, doesn't sleep at all
		S.ignite(10, 1)
		S.ignite(3, 2)
		S.ignite(0, 2)
		sleep(15)
		var/list/order = list()
		for(var/list/entry in S.seen)
			order += "gen [entry[2]] at [entry[1]]"
		var/ok = S.seen.len == 3 && S.seen[1][2] == 2 && S.seen[2][2] == 2 && S.seen[3][2] == 1
		world.log << "[ok ? "PASS" : "FAIL"] each run finds its own ignite() and generation after a sleep: [jointext(order, ", ")] (want 2, 2, 1)"
		// a walk that finds no ignite() at all (the caller chain of a spawn: 2 frames) - what pause() pays at most, short of a deep stack
		var/list/costs = list()
		for(var/k in 1 to 5)
			var/calls = 20000
			var/before = PROBE_TICK_USAGE
			for(var/i in 1 to calls)
				S.find_generation()
			costs += "[round((PROBE_TICK_USAGE - before) * world.tick_lag * 1000 / calls, 0.001)]"
			sleep(1)
		world.log << "NOTE a walk up 2 frames, us a call (5 runs): [jointext(costs, " ")]"
		del(world)

#undef PROBE_TICK_USAGE
