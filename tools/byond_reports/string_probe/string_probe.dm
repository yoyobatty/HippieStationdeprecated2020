// Why does building a string look slow in the game and not in a tiny world? One thing changed at a time, same code in both.
// Tiny world: dm string_probe.dm, then dd string_probe.dmb -invisible, results in world.log.
// In the game: HARNESS=../string_probe/string_probe.dm bash tools/byond_reports/ref_stall/hippie_check.sh, results in data/ref_stall.txt.
// Only the lines between t0 and t1 are timed. Samples go to a list after t1.

#define SP_N 5000

/datum/sp_probe
	var/n = 0

/proc/sp_report(label, list/samples)
	var/list/counts = new/list(10000)
	var/total = 0
	var/worst = 0
	for(var/s in samples)
		var/us = s * world.tick_lag * 1000
		total += us
		worst = max(worst, us)
		counts[min(max(round(us * 10) + 1, 1), 10000)]++
	var/seen = 0
	var/median = -1
	var/p99 = -1
	for(var/slot in 1 to 10000)
		seen += counts[slot]
		if(median < 0 && seen >= SP_N / 2)
			median = (slot - 1) / 10
		if(p99 < 0 && seen >= SP_N * 0.99)
			p99 = (slot - 1) / 10
	sp_log("[label]: mean [round(total / SP_N, 0.01)] us, median [median], 99% under [p99], worst [round(worst, 0.1)]")

/proc/sp_empty(list/samples)
	for(var/i in 1 to SP_N)
		var/t0 = world.tick_usage
		var/t1 = world.tick_usage
		samples[i] = t1 - t0

/proc/sp_repeat_text(list/samples)
	var/v = 12345
	var/text
	for(var/i in 1 to SP_N)
		var/t0 = world.tick_usage
		text = "repeat [v]"
		var/t1 = world.tick_usage
		samples[i] = t1 - t0
	return text

/proc/sp_unique_kept(list/samples, tag)
	var/list/store = new/list(SP_N)
	for(var/i in 1 to SP_N)
		var/t0 = world.tick_usage
		var/text = "k[tag]x[i]"
		var/t1 = world.tick_usage
		store[i] = text
		samples[i] = t1 - t0

/proc/sp_unique_dropped(list/samples, tag)
	var/text
	for(var/i in 1 to SP_N)
		var/t0 = world.tick_usage
		text = "d[tag]x[i]"
		var/t1 = world.tick_usage
		samples[i] = t1 - t0
	return text

/proc/sp_new(list/samples, list/store)
	for(var/i in 1 to SP_N)
		var/t0 = world.tick_usage
		var/datum/sp_probe/P = new
		var/t1 = world.tick_usage
		store[i] = P
		samples[i] = t1 - t0

/proc/sp_after_new_empty(list/samples, list/store)
	for(var/i in 1 to SP_N)
		var/datum/sp_probe/P = new
		store[i] = P
		var/t0 = world.tick_usage
		var/t1 = world.tick_usage
		samples[i] = t1 - t0

/proc/sp_after_new_repeat(list/samples, list/store)
	var/v = 12345
	var/text
	for(var/i in 1 to SP_N)
		var/datum/sp_probe/P = new
		store[i] = P
		var/t0 = world.tick_usage
		text = "repeat [v]"
		var/t1 = world.tick_usage
		samples[i] = t1 - t0
	return text

/proc/sp_after_new_unique(list/samples, list/store, tag)
	var/text
	for(var/i in 1 to SP_N)
		var/datum/sp_probe/P = new
		store[i] = P
		var/t0 = world.tick_usage
		text = "a[tag]x[i]"
		var/t1 = world.tick_usage
		samples[i] = t1 - t0
	return text

/proc/sp_ref_of(list/samples, list/store)
	var/text
	for(var/i in 1 to SP_N)
		var/datum/sp_probe/P = store[i]
		var/t0 = world.tick_usage
		text = "\ref[P]"
		var/t1 = world.tick_usage
		samples[i] = t1 - t0
	return text

/proc/sp_after_new_ref(list/samples, list/store)
	var/text
	for(var/i in 1 to SP_N)
		var/datum/sp_probe/P = new
		store[i] = P
		var/t0 = world.tick_usage
		text = "\ref[P]"
		var/t1 = world.tick_usage
		samples[i] = t1 - t0
	return text

/proc/sp_cases()
	sp_log("BYOND [world.byond_version].[world.byond_build], [world.fps] ticks, tick_lag [world.tick_lag]")
	var/list/samples = new/list(SP_N)
	for(var/pass in 1 to 2)
		var/list/store = new/list(SP_N)
		var/list/store2 = new/list(SP_N)
		sp_log("pass [pass]")
		sp_empty(samples)
		sp_report("nothing", samples)
		sleep(2)
		sp_repeat_text(samples)
		sp_report("text that already exists", samples)
		sleep(2)
		sp_unique_kept(samples, pass)
		sp_report("unique text, kept", samples)
		sleep(2)
		sp_unique_dropped(samples, pass)
		sp_report("unique text, dropped", samples)
		sleep(2)
		sp_new(samples, store)
		sp_report("new datum", samples)
		sleep(2)
		sp_ref_of(samples, store)
		sp_report("\\ref of a kept datum, first time", samples)
		sleep(2)
		sp_ref_of(samples, store)
		sp_report("\\ref of a kept datum, second time", samples)
		sleep(2)
		sp_after_new_empty(samples, store2)
		sp_report("after an untimed new: nothing", samples)
		sleep(2)
		sp_after_new_repeat(samples, store2)
		sp_report("after an untimed new: text that already exists", samples)
		sleep(2)
		sp_after_new_unique(samples, store2, pass)
		sp_report("after an untimed new: unique text", samples)
		sleep(2)
		sp_after_new_ref(samples, store2)
		sp_report("after an untimed new: \\ref of it", samples)
		sleep(2)
	sp_log("done")
	del(world)

#ifdef UNTIL

/datum/controller/master
	sleep_offline_after_initializations = FALSE

/proc/sp_log(text)
	text2file(text, "data/ref_stall.txt")

/world/New()
	. = ..()
	spawn(0)
		UNTIL(SSticker.initialized)
		SSticker.timeLeft = -1
		sleep(100)
		sp_cases()

#else

/world
	fps = 20

/proc/sp_log(text)
	world.log << text

/world/New()
	. = ..()
	spawn(5)
		sp_cases()

#endif
