// MC health self-test: breaks the MC each way the watchdog and the Failsafe are meant to catch, in the real engine, headless.
//
// Run:      tools/mc_check/run_mc_check.sh   (builds its own copy, so hippiestation.dmb is left alone)
// Results:  data/mc_check/results.txt, one PASS/FAIL line per check, with what each alert said.
//
// 1 The stack end detector, then the MC's loop "gone": the Failsafe restarts it at once, no subsystem blamed.
// 2 A freeze outside the MC (an admin action and a click just before it): reported with both, no admin token in it.
// 3 A freeze inside a subsystem's fire(): reported with the subsystem's name.
// 4 A fire() that sleeps 75 s: warned at 10 s, started afresh at 60 s, and its old fire() waking later leaves the state alone.
// 5 Other code taking 2.5 ticks of every tick, 30 s: the lag alert. Then the MC finding each tick used up at its turn: with
//   the cap and the forced turn, with the cap only, and as it was (no cap, no forced turn), compared.
// 6 A subsystem that crashes the MC's RunQueue: strikes 1-4, offline 5 minutes then its last chance, then off until an admin.
// 7 SStimer: a timer deleted a tick after joining the second queue at its edge; then 40 s of timers made and deleted at
//   random (every live one fires once, on time; no deleted one fires; no runtimes).
// 8 PROFILE 30 S (10 here) during lag: the alert names the proc that took the time, and the profiler goes off again.
// 9 A fresh subsystem in place of one that stopped the MC twice, as the MC makes it, for SSobj and SSair (no Recover() of
//   their own): it keeps the old one's lists and goes on firing.

/datum/controller/master/Initialize(delay, init_sss, tgs_prime)
	if("mc-selftest" in world.params)
		sleep_offline_after_initializations = FALSE //nobody connects to this, so the world has to keep ticking
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(run_mc_selftest))
	return ..()

#define MC_CHECK_DIR "data/mc_check/"

SUBSYSTEM_DEF(mctest)
	name = "MC test"
	wait = 1 SECONDS
	flags = SS_NO_INIT
	runlevels = RUNLEVEL_LOBBY | RUNLEVELS_DEFAULT
	var/mode = "idle"
	var/sleep_for = 0
	var/hog_for = 0
	var/stale_woke = FALSE
	var/hogging = FALSE
	var/fires = 0

/datum/controller/subsystem/mctest/fire(resumed)
	fires++
	switch(mode)
		if("sleep")
			mode = "idle"
			sleep(sleep_for)
			stale_woke = TRUE
		if("hog")
			mode = "idle"
			mc_check_busy(hog_for)
		if("hog_ticks")
			mode = "idle"
			INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(mc_check_hog_ticks), 2.5, 30 SECONDS)

/// Keep the server busy for `ds` deciseconds of real time without sleeping
/proc/mc_check_busy(ds)
	var/end = REALTIMEOFDAY + ds
	var/x = 0
	while(REALTIMEOFDAY < end)
		for(var/i in 1 to 2000)
			x += sqrt(i)
	return x

/proc/run_mc_selftest()
	sleep(5 SECONDS)
	fdel(MC_CHECK_DIR)
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/round_deadline = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < round_deadline)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	var/datum/mc_selftest/test = new
	test.run_all()
	text2file(jointext(test.lines, "\n"), "[MC_CHECK_DIR]results.txt")
	log_world("MC CHECK: done, [test.passed] passed, [test.failed] failed")
	Master.Shutdown()
	qdel(world)

/datum/mc_selftest
	var/list/lines = list()
	var/passed = 0
	var/failed = 0
	var/last_alert_id = 0
	var/min_defcon = 5
	var/watching_defcon = FALSE

/datum/mc_selftest/proc/check(name, condition, detail)
	if(condition)
		passed++
	else
		failed++
	lines += "[condition ? "PASS" : "FAIL"] [name][isnull(detail) ? "" : " - [detail]"]"
	text2file("[condition ? "PASS" : "FAIL"] [name][isnull(detail) ? "" : " - [detail]"]", "[MC_CHECK_DIR]progress.txt")

/datum/mc_selftest/proc/note(text)
	lines += "     [text]"
	text2file("     [text]", "[MC_CHECK_DIR]progress.txt")

/// The first Server alert since the last one looked at whose text has `find`, waiting up to `timeout`
/datum/mc_selftest/proc/wait_alert(find, timeout)
	var/deadline = world.time + timeout
	while(world.time <= deadline)
		for(var/datum/admin_alert/A as anything in SSadmin_alerts.alerts)
			if(A.id <= last_alert_id || A.kind != "server")
				continue
			if(findtext(A.text, find))
				last_alert_id = A.id
				return A
		sleep(2)

/datum/mc_selftest/proc/latest_alert_id()
	var/list/alerts = SSadmin_alerts.alerts
	return alerts.len ? alerts[alerts.len].id : 0

/datum/mc_selftest/proc/watch_defcon()
	set waitfor = FALSE
	watching_defcon = TRUE
	min_defcon = 5
	while(watching_defcon)
		min_defcon = min(min_defcon, Failsafe.defcon)
		sleep(1)

/datum/mc_selftest/proc/run_all()
	check("round started", SSticker.current_state >= GAME_STATE_PLAYING, "state [SSticker.current_state]")
	check("watchdog running", MCWatchdog && MCWatchdog.lasttick >= world.time - 1 SECONDS, "last woke [MCWatchdog ? world.time - MCWatchdog.lasttick : "never"] ds ago")
	check("test subsystem firing", SSmctest.fires > 0, "[SSmctest.fires] fires")
	last_alert_id = latest_alert_id()
	// dd -invisible reports world.sleep_offline as 1 and won't take 0, though the world keeps ticking: without this the watchdog
	// takes the freezes for the world asleep with nobody on
	MCWatchdog.watch_with_nobody_on = TRUE
	var/list/steps = list("stack_end", "freeze_outside", "freeze_inside", "native", "asleep", "lag", "strikes", "timer_edge", "timers", "profile", "recover", "inits", "status", "duty")
	// init_fail runs only when asked (STEPS=init_fail): its subsystem breaks at boot
	if(world.params["mc-steps"]) // STEPS=freeze_outside,lag on the runner: only those
		steps = splittext(world.params["mc-steps"], ",")
	for(var/step in steps)
		try
			call(src, step)()
		catch(var/exception/e)
			check("[step] ran to the end", FALSE, "[e] at [e.file]:[e.line]")
	var/datum/mc_watchdog/W = MCWatchdog
	note("watchdog tick cost [round(W.tick_cost_ms, 0.001)] ms average")

/datum/mc_selftest/proc/hold_canary(datum/stack_end_detector/D, ds)
	set waitfor = FALSE
	var/datum/stack_canary/canary = D.prime_canary()
	canary.use_variable()
	sleep(ds)

/datum/mc_selftest/proc/stack_end()
	var/datum/stack_end_detector/D = new
	hold_canary(D, 10)
	sleep(2)
	check("stack end detector: true while the stack holds the canary", D.check())
	sleep(15)
	check("stack end detector: false once that stack has ended", !D.check())
	var/datum/controller/master/old_master = Master
	var/strikes_before = length(SSmctest.failure_strikes)
	var/old_iteration = Master.iteration
	Master.stack_end_detector = D // as if Loop()'s stack were gone
	var/began = world.time
	while(Master == old_master && world.time - began < 10 SECONDS)
		sleep(1)
	check("the Failsafe restarts an MC whose loop is gone", Master != old_master, "in [(world.time - began) / 10] s (the DEFCON countdown took ~12 s)")
	sleep(3 SECONDS)
	check("the new MC runs", Master.iteration > 1 && Master.stack_end_detector?.check(), "iteration [Master.iteration], old one stopped at [old_iteration]")
	var/datum/admin_alert/A = wait_alert("loop stopped", 2 SECONDS)
	check("admins told the loop stopped", A, A?.text)
	check("no subsystem blamed for it", length(SSmctest.failure_strikes) == strikes_before, "strikes [json_encode(SSmctest.failure_strikes)]")

/datum/mc_selftest/proc/freeze_outside()
	round_log_add("Admin", "Testadmin spawned 500 singularities at the bar.")
	var/i = mc_watchdog_action_next
	mc_watchdog_actions[i] = list(REALTIMEOFDAY, "testadmin", "?_src_=holder;admin_token=SECRETTOKEN;spawn_many=500")
	mc_watchdog_action_next = i >= length(mc_watchdog_actions) ? 1 : i + 1
	mc_check_busy(6 SECONDS)
	var/datum/admin_alert/A = wait_alert("froze for", 3 SECONDS)
	check("freeze outside the MC alerted", A, A?.text)
	check("it names the admin action from the round log", A && findtext(A.text, "500 singularities"))
	check("it names the click just before", A && findtext(A.text, "testadmin") && findtext(A.text, "spawn_many"))
	check("no admin token in it", A && !findtext(A.text, "SECRETTOKEN"))
	var/secs = A ? text2num(copytext(A.text, findtext(A.text, "froze for ") + 10)) : 0
	check("it says how long", secs >= 5.5 && secs <= 7.5, "[secs] s for a 6 s freeze")
	check("the MC tab counts it", findtext(MCWatchdog.stat_line(), "Freezes 1"), MCWatchdog.stat_line())

/datum/mc_selftest/proc/freeze_inside()
	sleep(16 SECONDS) // the watchdog holds back a second freeze alert for 15 s after one
	SSmctest.hog_for = 6 SECONDS
	SSmctest.mode = "hog"
	var/datum/admin_alert/A = wait_alert("froze for", 10 SECONDS)
	check("freeze inside a fire() alerted", A, A?.text)
	check("it names the subsystem", A && findtext(A.text, "MC test's fire() held the server"))

/datum/mc_selftest/proc/asleep()
	sleep(2 SECONDS)
	SSmctest.stale_woke = FALSE
	SSmctest.sleep_for = 75 SECONDS
	SSmctest.mode = "sleep"
	var/began = world.time
	var/datum/admin_alert/A = wait_alert("slept and hasn't come back", 20 SECONDS)
	check("asleep fire() warned", A, A ? "after [(world.time - began) / 10] s: [A.text]" : null)
	check("the warning has a START IT NOW link", A && findtext(A.chat_links, "mcwatchdog=wake"))
	check("the MC tab names it asleep", findtext(MCWatchdog.stat_line(), "Asleep: MC test"), MCWatchdog.stat_line())
	check("the MC didn't fire it meanwhile", SSmctest.state == SS_SLEEPING || SSmctest.state == SS_PAUSING, "state [SSmctest.state]")
	var/datum/admin_alert/B = wait_alert("started it afresh", 70 SECONDS)
	check("started afresh", B, B ? "after [(world.time - began) / 10] s: [B.text]" : null)
	var/fires = SSmctest.fires
	sleep(5 SECONDS)
	check("it fires again", SSmctest.fires > fires, "[SSmctest.fires - fires] fires in 5 s")
	while(!SSmctest.stale_woke && world.time - began < 90 SECONDS)
		sleep(5)
	check("the old fire() woke", SSmctest.stale_woke)
	fires = SSmctest.fires
	sleep(5 SECONDS)
	check("and the state was left alone: it still fires", SSmctest.fires > fires && (SSmctest.state in list(SS_IDLE, SS_QUEUED)), "[SSmctest.fires - fires] fires in 5 s, state [SSmctest.state]")

/// Other code taking `share` ticks of every tick, for `ds` of real time. Started from inside a subsystem's turn it goes to sleep
/// before the MC does, so it wakes before the MC every tick and the MC finds the tick used up: the worst case.
/// Twenty workers, each taking its share every tick, so that some of them wake before the MC whatever order BYOND runs
/// sleepers in (one worker alone always ran after the MC)
/proc/mc_check_hog_ticks(share, ds)
	var/end = REALTIMEOFDAY + ds
	for(var/n in 1 to 20)
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(mc_check_hog_worker), share / 20, end)
		sleep(world.tick_lag * 0.5) // spread over the tick
	while(REALTIMEOFDAY < end)
		sleep(1)
	SSmctest.hogging = FALSE

/proc/mc_check_hog_worker(share, end)
	while(REALTIMEOFDAY < end)
		mc_check_busy(world.tick_lag * share)
		sleep(world.tick_lag)

/datum/mc_selftest/proc/total_fires()
	. = 0
	for(var/datum/controller/subsystem/SS as anything in Master.subsystems)
		. += SS.times_fired

/// 30 game seconds with the MC finding 150% of each tick used when its turn comes (Master.contention_test_usage: sleeping procs
/// never got ahead of it in these tests, BYOND resumes it first; players' commands can), its limits set as given. Returns
/// list(subsystem fires a game second, lowest DEFCON, MC restarts)
/datum/mc_selftest/proc/contention(label, cap, force_after)
	Master.sleep_delta_max = cap
	Master.contention_force_after = force_after
	Master.contention_test_usage = 150
	var/restarts = 0
	var/datum/controller/master/seen = Master
	var/fires = total_fires()
	var/time = world.time
	watch_defcon()
	while(world.time - time < 30 SECONDS)
		if(Master != seen)
			restarts++
			seen = Master
		sleep(1)
	watching_defcon = FALSE
	Master.contention_test_usage = 0
	Master.sleep_delta_max = MC_SLEEP_DELTA_MAX
	Master.contention_force_after = MC_CONTENTION_SKIPS_MAX
	var/rate = (total_fires() - fires) / 30
	note("[label]: [round(rate, 0.1)] subsystem fires a game second, lowest DEFCON [min_defcon], MC restarted [restarts] time\s")
	return list(rate, min_defcon, restarts)

/datum/mc_selftest/proc/lag()
	sleep(2 SECONDS)
	var/fires = total_fires()
	sleep(10 SECONDS)
	var/calm_rate = (total_fires() - fires) / 10
	note("calm: [round(calm_rate, 0.1)] subsystem fires a game second")
	// real lag: other code taking 2.5 ticks of every tick for 30 s
	var/time = world.time
	var/real = REALTIMEOFDAY
	SSmctest.hogging = TRUE
	SSmctest.mode = "hog_ticks"
	while(SSmctest.hogging && REALTIMEOFDAY - real < 60 SECONDS)
		sleep(1)
	note("other code taking 2.5 ticks of every tick: game ran [round((world.time - time) / (REALTIMEOFDAY - real) * 100)]% speed, other code before the MC's turn [round(Master.pre_mc_usage)]%")
	var/datum/admin_alert/A = wait_alert("speed for the last", 5 SECONDS)
	check("lag alerted", A, A?.text)
	check("it says the time went outside the MC", A && findtext(A.text, "the rest went to code outside the MC"))
	sleep(10 SECONDS)
	// the MC's turn when other code has already used up the tick
	var/strikes_before = json_encode(SSmctest.failure_strikes)
	var/list/new_code = contention("cap and forced turn (new)", MC_SLEEP_DELTA_MAX, MC_CONTENTION_SKIPS_MAX)
	check("new: the MC kept running (no restart)", new_code[3] == 0 && new_code[2] >= 3, "lowest DEFCON [new_code[2]], restarts [new_code[3]]")
	check("new: subsystems still fire", new_code[1] >= calm_rate * 0.1, "[round(new_code[1], 0.1)] a game second vs [round(calm_rate, 0.1)] calm")
	sleep(20 SECONDS)
	var/list/cap_only = contention("cap only", MC_SLEEP_DELTA_MAX, INFINITY)
	sleep(20 SECONDS)
	var/list/old_code = contention("old code (no cap, no forced turn)", INFINITY, INFINITY)
	check("old code: the MC stalled (the bug)", old_code[3] > 0 || old_code[2] <= 2, "lowest DEFCON [old_code[2]], restarts [old_code[3]]")
	check("the new code beats both", new_code[1] > cap_only[1] && new_code[1] > old_code[1], "fires a game second: new [round(new_code[1], 0.1)], cap only [round(cap_only[1], 0.1)], old [round(old_code[1], 0.1)]")
	check("nothing blamed for any of it", json_encode(SSmctest.failure_strikes) == strikes_before, "strikes [json_encode(SSmctest.failure_strikes)]")
	sleep(20 SECONDS) // let a restart in progress finish

/// Make the test subsystem crash RunQueue every time it's run, and wait for the MC restart that follows
/datum/mc_selftest/proc/strike(n)
	var/datum/controller/master/old_master = Master
	var/datum/controller/subsystem/mctest/T = SSmctest
	T.tick_overrun = "broken"
	T.next_fire = world.time
	var/began = world.time
	while(Master == old_master && world.time - began < 60 SECONDS)
		sleep(2)
	var/strikes = T.failure_strikes ? T.failure_strikes[T.type] : 0
	check("strike [n]: the MC restarted", Master != old_master, "after [(world.time - began) / 10] s, restart_count [Master.restart_count]")
	check("strike [n]: the test subsystem blamed", strikes == n, "strikes [strikes]")
	return T

/datum/mc_selftest/proc/strikes()
	Master.restart_timeout = 0 // the restarts above shouldn't hold these up
	var/datum/controller/subsystem/mctest/T = strike(1)
	// it's still broken, so it stops the MC again by itself: strike 2 makes a fresh one
	var/datum/controller/master/old_master = Master
	var/began = world.time
	while(Master == old_master && world.time - began < 60 SECONDS)
		sleep(2)
	check("strike 2: the MC restarted again", Master != old_master, "after [(world.time - began) / 10] s, restart_count [Master.restart_count]")
	check("strike 2: a fresh subsystem made", SSmctest != T && SSmctest.tick_overrun == 0, "same one: [SSmctest == T]")
	sleep(3 SECONDS)
	check("strike 2: the fresh one fires", SSmctest.fires > 0 && SSmctest.can_fire)
	T = strike(3)
	check("the MC tab names it offline", findtext(MCWatchdog.stat_line(), "Offline: MC test"), MCWatchdog.stat_line())
	check("strike 3: offline", !T.can_fire && T.watchdog_offline > world.time + 4 MINUTES, "can_fire [T.can_fire], back in [(T.watchdog_offline - world.time) / 10] s")
	var/datum/admin_alert/A = wait_alert("offline for 5 minutes", 5 SECONDS)
	check("strike 3: admins told, with a TURN IT ON link", A && findtext(A.chat_links, "mcwatchdog=enable"), A?.text)
	T.tick_overrun = 0
	T.watchdog_offline = world.time + 1 // as if the 5 minutes were up
	A = wait_alert("back on after 5 minutes", 5 SECONDS)
	check("its last chance: back on", A && T.can_fire && !T.watchdog_offline, A?.text)
	T = strike(4)
	check("strike 4: off until an admin turns it on", !T.can_fire && T.watchdog_offline == -1, "can_fire [T.can_fire], watchdog_offline [T.watchdog_offline]")
	A = wait_alert("until an admin", 5 SECONDS)
	check("strike 4: admins told", A, A?.text)
	T.tick_overrun = 0
	sleep(20 SECONDS)
	check("strike 4: it stays off", !T.can_fire)
	mc_watchdog_admin_action("enable", T.type)
	var/fires = T.fires
	sleep(4 SECONDS)
	check("an admin's TURN IT ON works", T.can_fire && T.fires > fires, "[T.fires - fires] fires in 4 s")
	note("restart_count [Master.restart_count] (5 s more between restarts for each, halved after a quiet spell, 30 s at most)")

#undef MC_CHECK_DIR

////////////////////
// SStimer under load: timers made and deleted at random, some right at the edge of the buckets' minute
////////////////////

/datum/timer_probe
	/// key = list(due world.time, deleted, times fired, world.time it last fired)
	var/list/timers = list()
	var/made = 0

/datum/timer_probe/proc/fired(key)
	var/list/T = timers[key]
	T[3]++
	T[4] = world.time

/// The second_queue edge case on its own: a timer that joins the second queue at the very edge, deleted a tick later
/datum/mc_selftest/proc/timer_edge()
	var/datum/timer_probe/P = new
	var/left_behind = 0
	var/tried = 0
	for(var/n in 1 to 40)
		// TIMER_MAX for a timer made now: the first time that goes to the second queue
		var/limit = world.time + TICKS2DS(min(world.fps * 60 - (SStimer.practical_offset - DS2TICKS(world.time - SStimer.head_offset)) - 1, world.fps * 60 - 1))
		var/wait = limit - world.time
		var/key = "edge[n]"
		P.timers[key] = list(world.time + wait, FALSE, 0, 0)
		var/id = addtimer(CALLBACK(P, TYPE_PROC_REF(/datum/timer_probe, fired), key), wait, TIMER_STOPPABLE)
		var/datum/timedevent/T = SStimer.timer_id_dict[id]
		var/in_second = (T in SStimer.second_queue)
		sleep(world.tick_lag)
		P.timers[key][2] = TRUE
		deltimer(id)
		if(in_second)
			tried++
			if(T in SStimer.second_queue)
				left_behind++
	check("timer edge: a timer deleted a tick after joining the second queue at its edge leaves it", tried && !left_behind, "[left_behind] of [tried] still in the second queue after deltimer()")

/datum/mc_selftest/proc/timers()
	var/runtimes_before = GLOB.total_runtimes
	var/datum/timer_probe/P = new
	var/list/live_ids = list()
	var/began = world.time
	// 40 s of making 30 timers a tick, waits from a tick to 90 s, a third of them deleted later at random
	while(world.time - began < 40 SECONDS)
		for(var/n in 1 to 30)
			var/wait = prob(50) ? rand(1, 40) * world.tick_lag : rand(1, 900)
			var/key = "t[++P.made]"
			var/due = world.time + max(CEILING(wait, world.tick_lag), world.tick_lag)
			P.timers[key] = list(due, FALSE, 0, 0)
			var/id = addtimer(CALLBACK(P, TYPE_PROC_REF(/datum/timer_probe, fired), key), wait, TIMER_STOPPABLE)
			if(prob(33))
				live_ids[key] = id
		// delete some of the ones marked, at random moments, often the tick after they were made
		for(var/key in live_ids)
			if(prob(25))
				var/list/T = P.timers[key]
				if(!T[3])
					T[2] = TRUE
					deltimer(live_ids[key])
				live_ids -= key
		sleep(world.tick_lag)
	note("timers: [P.made] made; waiting 95 s for the last of them")
	sleep(95 SECONDS)
	var/late = 0
	var/worst = 0
	var/never = 0
	var/twice = 0
	var/deleted_fired = 0
	for(var/key in P.timers)
		var/list/T = P.timers[key]
		if(T[2])
			if(T[3])
				deleted_fired++
			continue
		if(!T[3])
			never++
			continue
		if(T[3] > 1)
			twice++
		var/lateness = T[4] - T[1]
		worst = max(worst, lateness)
		if(lateness > 1 SECONDS)
			late++
	check("timers: every live timer fired", !never, "[never] never fired")
	check("timers: none fired twice", !twice, "[twice] fired twice")
	check("timers: no deleted timer fired", !deleted_fired, "[deleted_fired] fired after deltimer()")
	check("timers: on time", !late, "[late] over a second late, worst [worst / 10] s")
	check("timers: no runtimes meanwhile", GLOB.total_runtimes == runtimes_before, "[GLOB.total_runtimes - runtimes_before] runtimes (see runtime.log for Invalid timer)")

/// PROFILE 30 S (here 10): the profiler on for a while during lag, then an alert naming the procs that took the time
/datum/mc_selftest/proc/profile()
	use_byond_profiler()
	var/was = SSprofiler.profiling
	SSmctest.hogging = TRUE
	INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(mc_check_hog_ticks), 1.5, 15 SECONDS)
	sleep(1 SECONDS)
	MCWatchdog.profile_for(10, "testadmin")
	var/datum/admin_alert/A = wait_alert("profiled the server", 20 SECONDS)
	check("profile: alert after the time", A, A?.text)
	check("profile: it names the busy proc", A && findtext(A.text, "mc_check_busy"))
	check("profile: the profiler is off again", SSprofiler.profiling == was && !MCWatchdog.profiling_for)
	while(SSmctest.hogging)
		sleep(5)

/// Replace a subsystem the way the MC does after its second strike (master.dm Recover(), FireHim)
/datum/mc_selftest/proc/replace_like_strike_two(datum/controller/subsystem/old)
	Master.subsystems += new old.type
	sleep(1) // let the MC pick it up next time round
	var/datum/controller/subsystem/fresh
	for(var/datum/controller/subsystem/SS as anything in Master.subsystems)
		if(SS.type == old.type)
			fresh = SS
	return fresh

/datum/mc_selftest/proc/recover()
	// SSobj: what it's processing
	var/datum/controller/subsystem/processing/obj/old_obj = SSobj
	var/list/processing = old_obj.processing
	var/count = processing.len
	var/datum/controller/subsystem/processing/obj/fresh_obj = replace_like_strike_two(old_obj)
	check("recover SSobj: a fresh one", fresh_obj && fresh_obj != old_obj && SSobj == fresh_obj)
	check("recover SSobj: keeps the processing list", fresh_obj?.processing == processing && fresh_obj.processing.len >= count * 0.9, "[fresh_obj?.processing.len] of [count]")
	// the MC lists it took subsystems from at Loop() start: a fresh one only fires once the MC goes round again with it in
	// Master.subsystems, which RunQueue's lists don't follow until a restart; the strike path restarts the MC, so do that
	Recreate_MC()
	sleep(5 SECONDS)
	check("recover SSobj: it fires", SSobj.times_fired > 0, "[SSobj.times_fired] fires")
	// SSair: active turfs, networks, machinery
	var/datum/controller/subsystem/air/old_air = SSair
	var/list/networks = old_air.networks
	var/list/machinery = old_air.atmos_machinery
	var/datum/controller/subsystem/air/fresh_air = replace_like_strike_two(old_air)
	check("recover SSair: keeps its networks and machinery", fresh_air?.networks == networks && fresh_air.atmos_machinery == machinery, "networks [fresh_air?.networks.len], machinery [fresh_air?.atmos_machinery.len]")
	Master.restart_timeout = 0
	Recreate_MC()
	sleep(5 SECONDS)
	check("recover SSair: it fires", SSair.times_fired > 0 && SSair.initialized, "[SSair.times_fired] fires")

/// Every subsystem that initializes did, after a plain boot (a runtime in Initialize() used to leave it firing uninitialized)
/datum/mc_selftest/proc/inits()
	var/list/not_done = list()
	for(var/datum/controller/subsystem/SS as anything in Master.subsystems)
		if(!(SS.flags & SS_NO_INIT) && !SS.initialized)
			not_done += "[SS.name]"
	check("inits: every subsystem that initializes did", !not_done.len, not_done.len ? jointext(not_done, ", ") : null)

/// STEPS=init_fail only: a subsystem whose Initialize() runtimes at boot
SUBSYSTEM_DEF(mctest_init)
	name = "MC init test"
	flags = SS_NO_FIRE

/datum/controller/subsystem/mctest_init/Initialize(timeofday)
	if(findtext(world.params["mc-steps"], "init_fail"))
		var/list/nothing
		nothing.Cut() // a runtime, as a broken Initialize() would have
	return ..()

/datum/mc_selftest/proc/init_fail()
	var/datum/admin_alert/found
	for(var/datum/admin_alert/A as anything in SSadmin_alerts.alerts)
		if(A.kind == "server" && findtext(A.text, "MC init test didn't finish initializing"))
			found = A
	check("init_fail: admins told", found, found?.text)
	check("init_fail: the rest initialized", Master.iteration > 0 && SSatoms.initialized)

/// STEPS=timer_cost only: what a timer costs apart from its callback (trivial callbacks, 20,000 of them)
/datum/timer_probe/proc/nothing()
	return

/datum/mc_selftest/proc/timer_cost()
	var/datum/timer_probe/P = new
	sleep(2 SECONDS)
	var/ms_before = SStimer.total_ms
	var/fired_before = SStimer.times_fired
	var/started = TICK_USAGE_REAL
	var/made_ms = 0
	for(var/batch in 1 to 20)
		started = TICK_USAGE_REAL
		for(var/n in 1 to 1000)
			addtimer(CALLBACK(P, TYPE_PROC_REF(/datum/timer_probe, nothing)), rand(1, 40) * world.tick_lag)
		made_ms += TICK_USAGE_TO_MS(started)
		sleep(world.tick_lag)
	sleep(5 SECONDS)
	var/fire_ms = SStimer.total_ms - ms_before
	note("timer_cost: 20,000 timers: addtimer() [round(made_ms / 20, 0.01)] us each, SStimer [round(fire_ms / 20, 0.01)] us each to run (trivial callback), [SStimer.times_fired - fired_before] SStimer fires")
	// the same with TIMER_STOPPABLE, as bots' step timers are
	ms_before = SStimer.total_ms
	made_ms = 0
	for(var/batch in 1 to 20)
		started = TICK_USAGE_REAL
		for(var/n in 1 to 1000)
			addtimer(CALLBACK(P, TYPE_PROC_REF(/datum/timer_probe, nothing)), rand(1, 40) * world.tick_lag, TIMER_STOPPABLE)
		made_ms += TICK_USAGE_TO_MS(started)
		sleep(world.tick_lag)
	sleep(5 SECONDS)
	fire_ms = SStimer.total_ms - ms_before
	note("timer_cost: stoppable: addtimer() [round(made_ms / 20, 0.01)] us each, SStimer [round(fire_ms / 20, 0.01)] us each")

/// Status effects with nothing to do over time aren't processed (the crusher tally on every mining mob was, 5 times a second)
/datum/mc_selftest/proc/status()
	var/turf/T = locate(world.maxx / 2, world.maxy / 2, SSmapping.levels_by_trait(ZTRAIT_STATION)[1])
	var/mob/living/simple_animal/hostile/asteroid/goliath/G = new(T)
	var/datum/status_effect/crusher_damage/C = G.has_status_effect(STATUS_EFFECT_CRUSHERDAMAGETRACKING)
	check("status: a goliath has its crusher tally", C)
	check("status: and it isn't processed", C && !(C in SSfastprocess.processing))
	G.apply_damage(10)
	C.total_damage += 10
	check("status: the tally still counts", C?.total_damage == 10)
	var/mob/living/carbon/human/H = new(T)
	var/datum/status_effect/music = H.apply_status_effect(STATUS_EFFECT_GOOD_MUSIC)
	check("status: a timed effect is processed", music && (music in SSfastprocess.processing))
	sleep(8 SECONDS)
	check("status: and ends on time", QDELETED(music) && !H.has_status_effect(STATUS_EFFECT_GOOD_MUSIC))
	qdel(G)
	qdel(H)

/// AUTO_PROFILE's duty cycle: on 10% of the time, and PROFILE 30 S (10 here) fully on in the middle of it
/datum/mc_selftest/proc/duty()
	use_byond_profiler()
	SSprofiler.profiling = TRUE
	SSprofiler.duty = 10
	world.Profile(PROFILE_CLEAR)
	world.Profile(PROFILE_START)
	SSprofiler.on_time = 0
	SSprofiler.duty_cycle()
	SSmctest.hogging = TRUE
	INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(mc_check_hog_ticks), 0.5, 150 SECONDS)
	sleep(40 SECONDS)
	var/share = SSprofiler.sampled_share()
	check("duty: on about 10% of the time", share > 0.05 && share < 0.16, "[round(share * 100, 0.1)]% (cycle running [SSprofiler.cycle_running], on [SSprofiler.on_time] ds)")
	MCWatchdog.profile_for(10, "testadmin")
	sleep(2 SECONDS)
	for(var/n in 1 to 20) // work of its own in the window: 2 s of it, spread out
		mc_check_busy(1)
		sleep(2)
	check("duty: PROFILE 30 S turns it fully on", SSprofiler.sampled_share() == 1)
	var/datum/admin_alert/A = wait_alert("profiled the server", 20 SECONDS)
	check("duty: and names the busy proc", A && findtext(A.text, "mc_check_busy"), A?.text)
	var/on_before = SSprofiler.on_time
	var/real_before = REALTIMEOFDAY
	sleep(15 SECONDS)
	var/share_after = (SSprofiler.on_time - on_before) / max(1, REALTIMEOFDAY - real_before)
	check("duty: then back to the cycle", share_after > 0.03 && share_after < 0.2, "[round(share_after * 100, 0.1)]% in the 15 s after")
	// a read turns the profiler on (PROFILE_REFRESH is PROFILE_START): in the off part it must go straight back off
	while(SSprofiler.cycle_on)
		sleep(1)
	MCWatchdog.profile_read()
	for(var/n in 1 to 1000)
		mc_check_marker()
	var/list/rows = json_decode(world.Profile(PROFILE_REFRESH, null, "json"))
	SSprofiler.after_read()
	var/marked = 0
	for(var/list/row in rows)
		if(row["name"] == "/proc/mc_check_marker")
			marked = row["calls"]
	check("duty: a read in the off part leaves it off", !marked, "[marked] marker calls counted")
	SSprofiler.profiling = FALSE
	while(SSmctest.hogging)
		sleep(5)

/proc/mc_check_marker()
	return 1

/// The profile and duty steps are about BYOND's profiler: hippie_prof off for them
/datum/mc_selftest/proc/use_byond_profiler()
	if(SSprofiler.engine == "hippie")
		hippie_prof("stop")
		SSprofiler.engine = "byond"
		SSprofiler.profiling = FALSE

/// hippie_prof.dll (AUTO_PROFILE is on in config.txt): on, sampling, naming the proc behind a freeze, dumping every proc
/datum/mc_selftest/proc/native()
	check("native: hippie_prof is the profiler", SSprofiler.engine == "hippie", "engine [SSprofiler.engine]")
	if(SSprofiler.engine != "hippie")
		return
	var/list/status = json_decode(hippie_prof("status"))
	check("native: sampling", status["sampling"] && status["samples"] > 1000, "[status["samples"]] samples, [status["procs"]] procs, build [status["build"]]")
	sleep(16 SECONDS) // past the last freeze alert's hold-back
	SSmctest.hog_for = 6 SECONDS
	SSmctest.mode = "hog"
	var/datum/admin_alert/A = wait_alert("froze for", 10 SECONDS)
	check("native: the freeze report names what was running", A && findtext(A.text, "Running in those") && findtext(A.text, "mc_check_busy"), A?.text)
	var/list/rows = json_decode(hippie_prof("dump"))
	check("native: the dump has the round's procs", length(rows) > 200, "[length(rows)] rows")
	SSprofiler.DumpFile()
	check("native: profiler.json written", fexists("[GLOB.log_directory]/profiler.json") && length(file2text("[GLOB.log_directory]/profiler.json")) > 1000)
