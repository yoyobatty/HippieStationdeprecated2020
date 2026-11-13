// The MC watchdog (hippie, 2026-11-07, the user's "fix all of these" on the Failsafe's gaps). The Failsafe only notices the MC's
// loop not coming round; this watches for what it can't see, wakes every tick, and tells admins (an Alert of the Server kind:
// chat, the Alerts window and Discord, admin_alerts.dm):
//	Freeze    one stretch where the server stood still (a proc that never let go of the tick). Nothing in DM can stop that while
//	          it's happening, BYOND runs everything on one thread, so it's reported once it's over, with what started just before
//	          it: a subsystem's fire() that ran on, an admin proc call, players' clicks (client/Topic below), the round log.
//	Lag       the game running under 60% speed for 30 s of real time: which subsystems took the time, how much of each tick
//	          other code took before the MC's turn, admin actions in that time.
//	Asleep    a subsystem whose fire() slept and hasn't come back. The MC skips it until it does, and the Failsafe can't see it
//	          (the MC itself carries on). Warned at 10 s, started afresh at 60 s (the user's ruling); if the old fire() wakes
//	          later it finishes, but leaves the state alone (fire_generation, subsystem.dm).
//	Offline   a subsystem that stopped the MC three times is off for 5 minutes, then gets one more chance; a fourth time keeps
//	          it off until an admin turns it on (master.dm Recover(), the user's ruling). Its alert has a link to turn it on.
//	Timers    SStimer 5 s or more behind world.time while the game runs at full speed: every timer late, which looks to players like
//	          a frozen server though nothing froze (2026-11-13, a pile of cascade grenades). Names what the waiting timers are for.
//	Behind    any other subsystem on one pass of its queue for 10 s with the game at full speed: the same, for its queue.
// With the profiler running (AUTO_PROFILE or Toggle Profiling) the reports also name the procs that took the time: it keeps a
// copy of the profiler's figures every 30 s to compare with. The profiler slows every proc while it runs (2x30 min Bot Shifts
// side by side, 2026-11-07: Timer +35%, Machines +45%, Processing +20%, Mobs +40%), so it stays off by default; a lag alert
// has PROFILE 30 S instead, which turns it on for 30 s and then names the procs. With hippie_prof.dll doing the profiling
// (profiler.dm) none of that is needed: it's on all round for ~3 ns a call and keeps the last ~65 s of samples, so a freeze report
// names the procs that were running during the freeze itself, and a lag report the ones in its 30 s.
// The watchdog and the Failsafe each restart the other if it stops.

#define MC_WATCHDOG_FREEZE_LOG (1 SECONDS)
#define MC_WATCHDOG_FREEZE_ALERT (5 SECONDS)
#define MC_WATCHDOG_FREEZE_WINDOW (15 SECONDS)
#define MC_WATCHDOG_ASLEEP_WARN (10 SECONDS)
#define MC_WATCHDOG_ASLEEP_RESTART (60 SECONDS)
#define MC_WATCHDOG_LAG_WINDOW (30 SECONDS)
#define MC_WATCHDOG_LAG_SPEED 0.6
#define MC_WATCHDOG_LAG_REALERT (5 MINUTES)
/// SStimer this far behind world.time is reported (check_timers())
#define MC_WATCHDOG_TIMERS_LATE (5 SECONDS)
/// Any other subsystem this long on one pass is reported (check_backlog())
#define MC_WATCHDOG_BACKLOG (10 SECONDS)
#define MC_WATCHDOG_PROFILE_EVERY (5 MINUTES)
#define MC_WATCHDOG_ACTIONS_KEPT 64

GLOBAL_REAL(MCWatchdog, /datum/mc_watchdog)

/// Players' and admins' latest clicks and window actions: list(real time, ckey, href), a ring of MC_WATCHDOG_ACTIONS_KEPT
GLOBAL_REAL_VAR(list/mc_watchdog_actions) = new /list(MC_WATCHDOG_ACTIONS_KEPT)
GLOBAL_REAL_VAR(mc_watchdog_action_next) = 1

/datum/mc_watchdog
	var/running = TRUE
	/// world.time it last woke: the Failsafe restarts it if this goes stale
	var/lasttick = 0
	var/last_real
	var/last_time
	/// The world may have been asleep with nobody on last tick (world.sleep_offline): the real time that passed isn't a freeze
	var/was_offline = FALSE
	/// Count freezes with nobody on too: headless runs (tools/mc_check). dd -invisible reports sleep_offline as 1 and won't
	/// take 0, though the world keeps ticking
	var/static/watch_with_nobody_on = FALSE
	var/next_slow = 0
	/// Every 2 s: list(real time, world.time, list(subsystem = total_ms)), back to the start of the lag window
	var/list/samples = list()
	var/last_lag_alert = -INFINITY
	var/last_freeze_alert = -INFINITY
	/// Stretches the server stood still lately: list(real time it ended, real time lost, real time it began, world.time)
	var/list/freeze_pieces = list()
	/// The profiler's figures (proc name = self seconds) and when they were read (real time)
	var/list/profile_baseline
	var/profile_baseline_real = 0
	/// What reading the profiler costs (ms, average): the user wants it measured before the profiler goes on by default
	var/profile_fetch_ms = 0
	/// PROFILE 30 S is running (profile_for()): its baseline stays put
	var/profiling_for = FALSE
	var/profile_fetches = 0
	/// What a tick of the watchdog itself costs (ms, average)
	var/tick_cost_ms = 0
	/// For the MC tab: freezes and lag alerts this round, and the last freeze (seconds, world.time)
	var/freeze_count = 0
	var/lag_count = 0
	var/last_freeze_secs = 0
	var/last_freeze_time = 0
	/// Timers running late (check_timers()): alerts this round, the worst lateness seen (ds), the last alert (real time)
	var/timers_late_count = 0
	var/timers_late_worst = 0
	var/last_timers_alert = -INFINITY
	/// The MC last seen (its ref, so an old one can still be deleted), and when (real time) a new one was: a restarted MC's timers
	/// are late for reasons already reported
	var/seen_master
	var/master_changed_real = -INFINITY
	/// Subsystems behind on their queue (check_backlog()): alerts this round, the longest pass seen (ds), subsystem type = last alert
	var/backlog_count = 0
	var/backlog_worst = 0
	var/list/backlog_alerted

/datum/mc_watchdog/New()
	if(MCWatchdog != src)
		if(istype(MCWatchdog))
			MCWatchdog.running = FALSE
		MCWatchdog = src
	lasttick = world.time
	if(world.params["mc-watch-all"]) // a headless run at real speed (no timewarp, which makes timeofday follow game time)
		watch_with_nobody_on = TRUE
	Loop()

/datum/mc_watchdog/proc/Loop()
	set waitfor = FALSE
	last_real = REALTIMEOFDAY
	last_time = world.time
	while(running && MCWatchdog == src)
		sleep(world.tick_lag)
		lasttick = world.time
		var/started = TICK_USAGE_REAL
		try
			tick()
		catch(var/exception/e)
			log_world("MC watchdog: [e] at [e.file]:[e.line]")
		tick_cost_ms = MC_AVERAGE_FAST(tick_cost_ms, TICK_DELTA_TO_MS(TICK_USAGE_REAL - started))

/datum/mc_watchdog/proc/tick()
	var/now_real = REALTIMEOFDAY
	var/now_time = world.time
	var/lost = (now_real - last_real) - (now_time - last_time)
	if(lost >= MC_WATCHDOG_FREEZE_LOG && !was_offline)
		saw_freeze(lost, last_real, last_time, now_real, now_time)
	last_real = now_real
	last_time = now_time
	was_offline = !watch_with_nobody_on && world.sleep_offline && !length(GLOB.clients)
	if(now_time < next_slow)
		return
	next_slow = now_time + 2 SECONDS
	if(Failsafe?.processing_interval > 0 && Failsafe.lasttick + Failsafe.processing_interval * 5 < now_time)
		log_world("MC watchdog: the Failsafe stopped, restarting it.")
		new /datum/controller/failsafe()
	if(!Master || !islist(Master.subsystems))
		return
	check_subsystems(now_time)
	check_lag(now_real, now_time)
	check_timers(now_real, now_time)
	check_backlog(now_real, now_time)
	// A copy of the profiler's figures to compare reports with: every 5 minutes (a whole round's figures take ~66 ms to read and
	// decode: every 30 s, as it was, that was a hitch every 30 s and 2% of the profiled time), and a fresh one as soon as the
	// game starts slowing, so a lag report 30 s later covers about the lag
	if(SSprofiler?.profiling && SSprofiler.engine == "byond" && !profiling_for)
		var/stale = now_real - profile_baseline_real >= MC_WATCHDOG_PROFILE_EVERY
		var/slowing = now_real - profile_baseline_real >= 1 MINUTES && recent_speed(now_real, now_time) < 0.8
		if(stale || slowing)
			profile_baseline = profile_read()
			profile_baseline_real = now_real

/// The MC tab's line (statpanels.dm): what it's seen this round, and any subsystem asleep or taken offline
/datum/mc_watchdog/proc/stat_line()
	var/list/parts = list("Freezes [freeze_count][freeze_count ? " (last [last_freeze_secs] s, [round((world.time - last_freeze_time) / 600)] min ago)" : ""]", "Lag alerts [lag_count]")
	if(timers_late_count)
		parts += "Timers late [timers_late_count] (worst [round(timers_late_worst / 10)] s)"
	if(backlog_count)
		parts += "Behind [backlog_count] (worst pass [round(backlog_worst / 10)] s)"
	var/list/asleep = list()
	var/list/offline = list()
	for(var/datum/controller/subsystem/SS as anything in Master?.subsystems)
		if(SS.asleep_warned)
			asleep += SS.name
		if(SS.watchdog_offline)
			offline += SS.name
	if(asleep.len)
		parts += "Asleep: [jointext(asleep, ", ")]"
	if(offline.len)
		parts += "Offline: [jointext(offline, ", ")]"
	return jointext(parts, " | ")

////////////////////
// Subsystems: asleep, and offline ones' last chance
////////////////////

/datum/controller/subsystem/proc/watchdog_link(action, label)
	return mc_watchdog_link(action, label, type)

/proc/mc_watchdog_link(action, label, ss_type)
	return "(<a href='?_src_=holder;[HrefToken(TRUE)];mcwatchdog=[action][ss_type ? ";ss=[ss_type]" : ""]'>[label]</a>)"

/datum/mc_watchdog/proc/check_subsystems(now_time)
	for(var/datum/controller/subsystem/SS as anything in Master.subsystems)
		if(SS.watchdog_offline > 0 && now_time >= SS.watchdog_offline)
			mc_watchdog_turn_on(SS)
			mc_watchdog_alert("[SS.name] is back on after 5 minutes offline. If it stops the MC again it stays off until an admin turns it on.")
		if(SS.state != SS_SLEEPING && SS.state != SS_PAUSING)
			SS.asleep_since = 0
			continue
		// times_fired goes up as each fire() starts its sleep, so a subsystem that sleeps a little on every fire isn't counted as one long sleep
		if(!SS.asleep_since || SS.asleep_fire != SS.times_fired)
			SS.asleep_since = now_time
			SS.asleep_warned = FALSE
			SS.asleep_fire = SS.times_fired
			continue
		var/asleep = now_time - SS.asleep_since
		if(asleep >= MC_WATCHDOG_ASLEEP_RESTART)
			mc_watchdog_wake(SS)
			mc_watchdog_alert("[SS.name]'s fire() slept and didn't come back for [round(asleep / 10)] s. The MC has started it afresh.")
		else if(asleep >= MC_WATCHDOG_ASLEEP_WARN && !SS.asleep_warned)
			SS.asleep_warned = TRUE
			log_world("MC watchdog: [SS.name]'s fire() has been asleep [round(asleep / 10)] s.")
			mc_watchdog_alert("[SS.name]'s fire() slept and hasn't come back for [round(asleep / 10)] s: it doesn't run until it does. Started afresh at 60 s.", SS.watchdog_link("wake", "START IT NOW"))

/// Start a subsystem whose fire() is asleep afresh. Its old fire() may still wake: it finishes, but leaves the state alone.
/proc/mc_watchdog_wake(datum/controller/subsystem/SS)
	if(SS.state != SS_SLEEPING && SS.state != SS_PAUSING)
		return FALSE
	log_world("MC watchdog: starting [SS.name] afresh, its fire() asleep since [SS.asleep_since].")
	SS.fire_generation++
	SS.state = SS_IDLE
	SS.paused_ticks = 0
	SS.paused_tick_usage = 0
	SS.next_fire = world.time
	SS.asleep_since = 0
	SS.asleep_warned = FALSE
	return TRUE

/// Off for stopping the MC: for `duration`, or until an admin turns it on (0)
/proc/mc_watchdog_take_offline(datum/controller/subsystem/SS, duration)
	SS.can_fire = FALSE
	SS.watchdog_offline = duration ? world.time + duration : -1

/proc/mc_watchdog_turn_on(datum/controller/subsystem/SS)
	SS.watchdog_offline = 0
	SS.can_fire = TRUE
	SS.next_fire = world.time + SS.wait
	log_world("MC watchdog: [SS.name] turned back on.")

////////////////////
// Freezes
////////////////////

/// One stretch of a second or more where the server stood still. They're added up over MC_WATCHDOG_FREEZE_WINDOW: BYOND can
/// pause a proc that runs long and finish it in the next tick, which splits one freeze into pieces, each under the threshold.
/datum/mc_watchdog/proc/saw_freeze(lost, start_real, start_time, now_real, now_time)
	var/ticks = max(1, round((now_time - start_time) / world.tick_lag))
	log_world("MC watchdog: the server stood still for [round(lost / 10, 0.1)] s over [ticks] tick\s. [freeze_report(start_real, start_time, now_time, FALSE)]")
	freeze_pieces += list(list(now_real, lost, start_real, start_time))
	while(freeze_pieces.len && freeze_pieces[1][1] < now_real - MC_WATCHDOG_FREEZE_WINDOW)
		freeze_pieces.Cut(1, 2)
	var/total = 0
	for(var/list/piece as anything in freeze_pieces)
		total += piece[2]
	if(total < MC_WATCHDOG_FREEZE_ALERT || now_real - last_freeze_alert < MC_WATCHDOG_FREEZE_WINDOW)
		return
	if(!SSticker || SSticker.current_state < GAME_STATE_PLAYING) // the round being set up: logged only
		return
	var/list/first = freeze_pieces[1]
	var/pieces = freeze_pieces.len
	freeze_pieces.Cut()
	last_freeze_alert = now_real
	freeze_count++
	last_freeze_secs = round(total / 10, 0.1)
	last_freeze_time = now_time
	var/how = pieces > 1 ? " in [pieces] stretches over [round((now_real - first[3]) / 10)] s" : (ticks > 3 ? " over [ticks] ticks" : "")
	mc_watchdog_alert("The server froze for [round(total / 10, 0.1)] s[how]. [freeze_report(first[3], first[4], now_time, TRUE)]")

/datum/mc_watchdog/proc/freeze_report(start_real, start_time, now_time, with_profile)
	var/list/parts = list()
	var/list/long_fire = Master?.last_long_fire
	if(long_fire && long_fire[3] >= start_time && long_fire[3] <= now_time)
		parts += "[long_fire[1]]'s fire() held the server [round(long_fire[2] / 1000, 0.1)] s at a stretch."
	if(GLOB.AdminProcCaller)
		parts += "[GLOB.AdminProcCaller]'s proc call ([GLOB.LastAdminCalledProc]) is still running."
	var/list/before = list()
	before += recent_actions(start_real - 2 SECONDS, start_real + 1 SECONDS, 3)
	before += round_log_between(start_time - 2 SECONDS, now_time, 3, "Admin")
	if(before.len)
		parts += "Just before: [jointext(before, "; ")]"
	if(with_profile)
		var/top = profile_top(3, REALTIMEOFDAY - start_real + 5)
		if(top)
			parts += top
		var/path = profile_stack(REALTIMEOFDAY - start_real + 5)
		if(path)
			parts += path
	return jointext(parts, " ")

////////////////////
// Lag
////////////////////

/// The game's speed over the last ~10 s of real time, from the lag samples (1 when there aren't enough yet)
/datum/mc_watchdog/proc/recent_speed(now_real, now_time)
	for(var/i in samples.len to 1 step -1)
		var/list/sample = samples[i]
		if(now_real - sample[1] >= 10 SECONDS)
			return (now_time - sample[2]) / max(1, now_real - sample[1])
	return 1

/datum/mc_watchdog/proc/check_lag(now_real, now_time)
	var/list/ms = list()
	for(var/datum/controller/subsystem/SS as anything in Master.subsystems)
		ms[SS] = SS.total_ms
	samples += list(list(now_real, now_time, ms))
	while(samples.len > 2 && samples[2][1] <= now_real - MC_WATCHDOG_LAG_WINDOW)
		samples.Cut(1, 2)
	var/list/oldest = samples[1]
	var/span_real = now_real - oldest[1]
	if(span_real < MC_WATCHDOG_LAG_WINDOW)
		return
	var/speed = (now_time - oldest[2]) / span_real
	if(speed >= MC_WATCHDOG_LAG_SPEED)
		return
	if(now_real - last_lag_alert < MC_WATCHDOG_LAG_REALERT || now_real - last_freeze_alert < MC_WATCHDOG_LAG_WINDOW)
		return
	if(!SSticker || SSticker.current_state < GAME_STATE_PLAYING)
		return
	last_lag_alert = now_real
	lag_count++
	var/report = lag_report(oldest, ms, span_real, now_time)
	log_world("MC watchdog: the game ran at [round(speed * 100)]% speed for [round(span_real / 10)] s. [report]")
	mc_watchdog_alert("The game has run at [round(speed * 100)]% speed for the last [round(span_real / 10)] s. [report]", (SSprofiler?.profiling && (SSprofiler.engine == "hippie" || SSprofiler.duty >= 100)) ? null : mc_watchdog_link("profile", "PROFILE 30 S"))

////////////////////
// Timers late
////////////////////

/// SStimer running behind world.time: every timer (doors, stuns, do-afters, explosions' after-effects...) late by that much while
/// the game itself runs at full speed, so neither the freeze nor the lag check sees it. 2026-11-13: a pile of cascade grenades put
/// the timers a minute behind with the game at 96% speed; to the player the server had stopped.
/// The MC itself in trouble (stalling, restarted, frozen, slowed): its subsystems' queues fall behind too, and the Failsafe's,
/// freeze and lag reports already say so. The timers and backlog checks are for one queue falling behind while the rest keeps up.
/datum/mc_watchdog/proc/mc_in_trouble(now_real, now_time)
	if(REF(Master) != seen_master)
		if(seen_master) // the first one seen is the one the world started with, not a restart
			master_changed_real = now_real
		seen_master = REF(Master)
	if(Failsafe?.defcon < 5 || now_real - master_changed_real < 1 MINUTES || now_real - last_freeze_alert < 1 MINUTES || now_real - last_lag_alert < 1 MINUTES)
		return TRUE
	return recent_speed(now_real, now_time) < MC_WATCHDOG_LAG_SPEED

/datum/mc_watchdog/proc/check_timers(now_real, now_time)
	if(!SStimer || SStimer.practical_offset > length(SStimer.bucket_list))
		return
	if(mc_in_trouble(now_real, now_time))
		return
	var/late = now_time - (SStimer.head_offset + (SStimer.practical_offset - 1) * world.tick_lag)
	timers_late_worst = max(timers_late_worst, late)
	if(late < MC_WATCHDOG_TIMERS_LATE || now_real - last_timers_alert < MC_WATCHDOG_LAG_REALERT)
		return
	if(!SSticker || SSticker.current_state < GAME_STATE_PLAYING)
		return
	last_timers_alert = now_real
	timers_late_count++
	var/report = "Timers are running [round(late / 10, 0.1)] s late with the game at full speed: [SStimer.bucket_count] waiting. [timers_report()]"
	log_world("MC watchdog: [report]")
	mc_watchdog_alert(report)

/// Any other subsystem still on one pass of its queue after MC_WATCHDOG_BACKLOG with the game at full speed: its fire() keeps
/// pausing for the tick and picking up where it left off, and never gets to the end, so whatever it runs (explosions, air, throws,
/// garbage...) is that far behind. The same blind spot as the timers (check_timers()), for the rest.
/datum/mc_watchdog/proc/check_backlog(now_real, now_time)
	if(!SSticker || SSticker.current_state < GAME_STATE_PLAYING || mc_in_trouble(now_real, now_time))
		return
	var/limit = MC_WATCHDOG_BACKLOG / world.tick_lag
	for(var/datum/controller/subsystem/SS as anything in Master.subsystems)
		if(SS.paused_ticks < limit || SS == SStimer)
			continue
		backlog_worst = max(backlog_worst, SS.paused_ticks * world.tick_lag)
		if(now_real - (LAZYACCESS(backlog_alerted, SS.type) || -INFINITY) < MC_WATCHDOG_LAG_REALERT)
			continue
		LAZYSET(backlog_alerted, SS.type, now_real)
		backlog_count++
		SS.stat_entry()
		var/report = "[SS.name] has been on one pass for [round(SS.paused_ticks * world.tick_lag / 10)] s with the game at full speed: it isn't keeping up\
			[SS.stat_extra ? " ([SS.stat_extra])" : ""]. [profile_top(5, MC_WATCHDOG_BACKLOG)]"
		log_world("MC watchdog: [report]")
		mc_watchdog_alert(report)

/// What the timers SStimer is on are for: the procs they call, the most first (the bucket it's on and the next few, up to 5000).
/datum/mc_watchdog/proc/timers_report()
	var/list/counts = list()
	var/seen = 0
	var/list/bucket_list = SStimer.bucket_list
	for(var/i in SStimer.practical_offset to min(length(bucket_list), SStimer.practical_offset + 20))
		var/datum/timedevent/head = bucket_list[i]
		var/datum/timedevent/node = head
		while(node && seen < 5000)
			counts[node.info_type == GLOBAL_PROC ? "/proc/[node.info_proc]" : "[node.info_type]/proc/[node.info_proc]"]++
			seen++
			node = node.next
			if(node == head)
				break
		if(seen >= 5000)
			break
	if(!seen)
		return "None in the next 20 buckets."
	sortTim(counts, GLOBAL_PROC_REF(cmp_numeric_dsc), TRUE)
	var/list/bits = list()
	for(var/name in counts)
		bits += "[name] [counts[name]]"
		if(length(bits) >= 5)
			break
	return "Of the next [seen]: [jointext(bits, ", ")]."

/datum/mc_watchdog/proc/lag_report(list/oldest, list/ms_now, span_real, now_time)
	var/list/old_ms = oldest[3]
	var/list/shares = list()
	var/mc_total = 0
	for(var/datum/controller/subsystem/SS as anything in ms_now)
		var/share = (ms_now[SS] - (old_ms[SS] || 0)) / span_real // ms per decisecond of real time = % of real time
		mc_total += share
		if(share >= 1)
			shares[SS.name] = share
	sortTim(shares, GLOBAL_PROC_REF(cmp_numeric_dsc), TRUE)
	var/list/top = list()
	for(var/name in shares)
		top += "[name] [round(shares[name])]%"
		if(top.len >= 3)
			break
	var/list/parts = list()
	parts += "The MC took [round(mc_total)]% of real time[top.len ? " ([jointext(top, ", ")])" : ""]; the rest went to code outside the MC (procs running on their own, players' and admins' commands) and sending the map ([round(world.map_cpu)]% of a tick)."
	if(Master.pre_mc_usage >= 20)
		parts += "Other code used [round(Master.pre_mc_usage)]% of each tick before the MC's turn."
	var/list/admin_lines = round_log_between(oldest[2], now_time, 3, "Admin")
	if(admin_lines.len)
		parts += "Admin actions: [jointext(admin_lines, "; ")]."
	var/top_procs = profile_top(3, span_real)
	if(top_procs)
		parts += top_procs
	var/path = profile_stack(span_real)
	if(path)
		parts += path
	return jointext(parts, " ")

////////////////////
// What happened: players' actions, the round log, the profiler
////////////////////

/client/Topic(href, href_list, hsrc)
	var/i = mc_watchdog_action_next
	mc_watchdog_actions[i] = list(REALTIMEOFDAY, ckey, href)
	mc_watchdog_action_next = i >= MC_WATCHDOG_ACTIONS_KEPT ? 1 : i + 1
	return ..()

/// Actions between two real times, newest last, without admin tokens
/datum/mc_watchdog/proc/recent_actions(from_real, to_real, count)
	. = list()
	var/i = mc_watchdog_action_next
	for(var/n in 1 to MC_WATCHDOG_ACTIONS_KEPT)
		i = i <= 1 ? MC_WATCHDOG_ACTIONS_KEPT : i - 1
		var/list/entry = mc_watchdog_actions[i]
		if(!entry || entry[1] < from_real)
			break
		if(entry[1] > to_real)
			continue
		. = list("[entry[2]] [describe_href(entry[3])]") + .
		if(length(.) >= count)
			break

/datum/mc_watchdog/proc/describe_href(href)
	if(copytext(href, 1, 2) == "?")
		href = copytext(href, 2)
	var/list/params = params2list(href)
	var/list/out = list()
	var/datum/D = params["src"] ? locate(params["src"]) : null
	if(D)
		out += "used [D.type]"
	else if(params["_src_"])
		out += params["_src_"] == "holder" ? "admin panel" : "[params["_src_"]]"
	for(var/key in params)
		if(key in list("src", "_src_", "admin_token", "token", "priv"))
			continue
		var/value = params[key]
		out += istext(value) && length(value) <= 30 ? "[key]=[value]" : key
		if(out.len >= 4)
			break
	return copytext_char(jointext(out, " "), 1, 100)

/// The profiler's figures now: proc name = self seconds since it started
/datum/mc_watchdog/proc/profile_read()
	var/started = TICK_USAGE_REAL
	var/raw = world.Profile(PROFILE_REFRESH, null, "json")
	SSprofiler.after_read() // that read turned it on (PROFILE_REFRESH is PROFILE_START): off again before the decode is counted
	var/list/rows = json_decode(raw)
	. = list()
	for(var/list/row in rows)
		.[row["name"]] = row["self"]
	profile_fetches++
	profile_fetch_ms = MC_AVERAGE(profile_fetch_ms, TICK_DELTA_TO_MS(TICK_USAGE_REAL - started))

/// What called what in the stack the server spent most of the window in, hippie_prof's last ~16 s (profiler.dm recent_stacks()): the top
/// eight frames, so a freeze says not just which proc held it but how it got there
/datum/mc_watchdog/proc/profile_stack(window_ds)
	if(!SSprofiler?.profiling || SSprofiler.engine != "hippie")
		return
	var/list/stacks = SSprofiler.recent_stacks(window_ds * 100)
	if(!length(stacks))
		return
	var/list/heaviest = stacks[1]
	if(heaviest["ms"] < 100)
		return
	var/list/frames = heaviest["stack"]
	var/list/shown = frames.Copy(max(1, length(frames) - 7))
	return "Mostly in: [jointext(shown, " > ")] ([round(heaviest["ms"] / 1000, 0.1)] s)."

/// The procs that took the most time since the last copy of the profiler's figures, when it's running
/datum/mc_watchdog/proc/profile_top(count, window_ds = 30 SECONDS)
	if(SSprofiler?.profiling && SSprofiler.engine == "hippie")
		var/list/ran = SSprofiler.recent(window_ds * 100)
		var/list/named = list()
		for(var/name in ran)
			if(ran[name] >= 0.1)
				named += "[name] [round(ran[name], 0.1)] s"
			if(named.len >= count)
				break
		return named.len ? "Running in those [round(window_ds / 10)] s: [jointext(named, ", ")]." : null
	if(!SSprofiler?.profiling || isnull(profile_baseline))
		return
	var/list/now = profile_read()
	var/list/took = list()
	for(var/name in now)
		var/self = now[name] - (profile_baseline[name] || 0)
		if(self >= 0.1)
			took[name] = self
	if(!took.len)
		return
	sortTim(took, GLOBAL_PROC_REF(cmp_numeric_dsc), TRUE)
	var/list/top = list()
	for(var/name in took)
		top += "[name] [round(took[name], 0.1)] s"
		if(top.len >= count)
			break
	var/share = SSprofiler.sampled_share()
	return "Profiler, last [round((REALTIMEOFDAY - profile_baseline_real) / 10)] s[share < 1 ? " (on [round(share * 100)]% of the time)" : ""]: [jointext(top, ", ")]."

////////////////////
// The stack end detector (ported from tg, code/controllers/master.dm uses it): Loop() keeps the canary in a local, its only
// reference, so the canary is deleted when that stack ends however it ended, and the weakref stops resolving.
////////////////////

/datum/stack_end_detector
	var/datum/weakref/_WF
	var/datum/stack_canary/_canary

/datum/stack_end_detector/New()
	_canary = new()
	_WF = WEAKREF(_canary)

/// Hands the canary over: the caller must keep it in a local var for as long as its stack should be watched
/datum/stack_end_detector/proc/prime_canary()
	if(!_canary)
		CRASH("prime_canary() called twice")
	var/datum/stack_canary/canary = _canary
	_canary = null
	return canary

/// TRUE while the stack that holds the canary is still there
/datum/stack_end_detector/proc/check()
	return !!_WF.resolve()

/datum/stack_canary

/// Gives the local var a use, so it's clearly meant to be held
/datum/stack_canary/proc/use_variable()

////////////////////
// Telling admins
////////////////////

/// An alert of the Server kind: admin chat, the Alerts window, Discord. Safe with the MC down; logged either way. `links`: admin
/// links for its chat line (mc_watchdog_link())
/proc/mc_watchdog_alert(text, links)
	log_world("MC watchdog alert: [text]")
	if(!istype(SSadmin_alerts))
		return
	SSadmin_alerts.raise("server", text, TRUE, chat_links = links)

/// PROFILE 30 S on a lag alert: the BYOND profiler fully on for 30 s of real time, then an alert with the procs that took the
/// time. It slows every proc call while it's on (~255 ns each, subsystems +20-45% in Bot Shifts), so it's on only for this,
/// or for a share of the time with AUTO_PROFILE (hippiestation/code/controllers/subsystem/profiler.dm), which this tops up.
/datum/mc_watchdog/proc/profile_for(seconds, who)
	set waitfor = FALSE
	if(profiling_for)
		return FALSE
	if(SSprofiler.profiling && SSprofiler.engine == "hippie") // it's on anyway: just the 30 s from now
		profiling_for = TRUE
		sleep(seconds * 10)
		var/ran = profile_top(6, seconds * 10)
		profiling_for = FALSE
		mc_watchdog_alert("[who] profiled the server for [seconds] s. [ran || "No proc took 0.1 s or more."]")
		return TRUE
	var/cycling = SSprofiler.profiling && SSprofiler.duty < 100
	if(SSprofiler.profiling && !cycling) // always on: every report names the procs already
		return FALSE
	profiling_for = TRUE
	if(cycling)
		SSprofiler.full_until = REALTIMEOFDAY + seconds * 10 + 1 SECONDS
		sleep(world.tick_lag * 2) // the cycle turns it on
		profile_baseline = profile_read() // the round's figures so far: the 30 s are what's added to them
	else
		SSprofiler.profiling = TRUE
		world.Profile(PROFILE_CLEAR)
		SSprofiler.StartProfiling()
		profile_baseline = list()
	profile_baseline_real = REALTIMEOFDAY
	var/began = REALTIMEOFDAY
	while(REALTIMEOFDAY - began < seconds * 10)
		sleep(1 SECONDS)
	var/top = profile_top(6)
	if(!cycling) // it was off before
		SSprofiler.StopProfiling()
		SSprofiler.profiling = FALSE
	profile_baseline = null
	profiling_for = FALSE
	mc_watchdog_alert("[who] profiled the server for [seconds] s. [top || "No proc took 0.1 s or more."]")
	return TRUE

/// An alert's link (hippieTopic, topic.dm)
/proc/mc_watchdog_admin_action(action, ss_type)
	if(action == "profile")
		if(MCWatchdog.profiling_for)
			to_chat(usr, "<span class='notice'>The profiler is already fully on: the next report names the procs.</span>", confidential = TRUE)
			return
		MCWatchdog.profile_for(30, key_name(usr))
		log_admin("[key_name(usr)] started the profiler for 30 s.")
		message_admins("[key_name_admin(usr)] started the profiler for 30 s.")
		return
	var/datum/controller/subsystem/SS
	for(var/datum/controller/subsystem/candidate as anything in Master?.subsystems)
		if(candidate.type == ss_type)
			SS = candidate
			break
	if(!SS)
		to_chat(usr, "<span class='warning'>That subsystem isn't running.</span>", confidential = TRUE)
		return
	switch(action)
		if("enable")
			if(SS.can_fire)
				to_chat(usr, "<span class='notice'>[SS.name] is already on.</span>", confidential = TRUE)
				return
			mc_watchdog_turn_on(SS)
		if("wake")
			if(!mc_watchdog_wake(SS))
				to_chat(usr, "<span class='notice'>[SS.name] has already woken up.</span>", confidential = TRUE)
				return
		else
			return
	var/msg = "[key_name(usr)] [action == "enable" ? "turned [SS.name] back on" : "started [SS.name] afresh"]."
	log_admin(msg)
	message_admins(msg)

#undef MC_WATCHDOG_FREEZE_LOG
#undef MC_WATCHDOG_FREEZE_ALERT
#undef MC_WATCHDOG_FREEZE_WINDOW
#undef MC_WATCHDOG_ASLEEP_WARN
#undef MC_WATCHDOG_ASLEEP_RESTART
#undef MC_WATCHDOG_LAG_WINDOW
#undef MC_WATCHDOG_LAG_SPEED
#undef MC_WATCHDOG_LAG_REALERT
#undef MC_WATCHDOG_TIMERS_LATE
#undef MC_WATCHDOG_BACKLOG
#undef MC_WATCHDOG_PROFILE_EVERY
#undef MC_WATCHDOG_ACTIONS_KEPT
