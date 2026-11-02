// Where is the slow text inside the game? Times ref-shaped text across the id range, with nothing kept. Not part of the game:
// HARNESS=../string_probe/string_map.dm bash tools/byond_reports/ref_stall/hippie_check.sh

#define SM_STEP 0x2000
#define SM_EACH 60

/datum/controller/master
	sleep_offline_after_initializations = FALSE

/proc/sm_log(text)
	text2file(text, "data/ref_stall.txt")

/// Median us to build ref-shaped text around this id, for text nobody has made.
/proc/sm_probe(id)
	var/list/times = new/list(SM_EACH)
	var/text
	for(var/i in 1 to SM_EACH)
		var/middle = num2text(id + i * 16 + 7, 6, 16)
		var/t0 = world.tick_usage
		text = "\[0x21[middle]]"
		var/t1 = world.tick_usage
		times[i] = (t1 - t0) * world.tick_lag * 1000
	sortTim(times, GLOBAL_PROC_REF(cmp_numeric_asc))
	return times[round(SM_EACH / 2)] + (text ? 0 : 0)

/proc/sm_run()
	UNTIL(SSticker.initialized)
	SSticker.timeLeft = -1
	sleep(100)
	var/datum/P = new
	sm_log("BYOND [world.byond_version].[world.byond_build], [world.fps] ticks, a new datum is [ref(P)]")
	var/run_start = -1
	var/run_slow = FALSE
	var/run_total = 0
	var/run_count = 0
	for(var/id = 0, id <= 0x300000, id += SM_STEP)
		var/us = sm_probe(id)
		var/slow = us > 2
		if(run_start < 0)
			run_start = id
			run_slow = slow
		if(slow != run_slow)
			sm_log("[num2text(run_start, 6, 16)] to [num2text(id - 1, 6, 16)]: [run_slow ? "SLOW" : "fast"], mean of medians [round(run_total / run_count, 0.1)] us")
			run_start = id
			run_slow = slow
			run_total = 0
			run_count = 0
		run_total += us
		run_count++
		if(!(id % 0x40000))
			sleep(1)
	sm_log("[num2text(run_start, 6, 16)] to end: [run_slow ? "SLOW" : "fast"], mean of medians [round(run_total / run_count, 0.1)] us")
	sm_log("done")
	del(world)

/world/New()
	. = ..()
	spawn(0)
		sm_run()
