// \ref costs either about 0.4 us or about 11 us in the game, by datum. What decides which? Per datum: its ref, \ref timed twice, then the
// same text built without \ref. Slow text as well means the string table, fast text means \ref's own work.
// HARNESS=../string_probe/ref_ids.dm bash tools/byond_reports/ref_stall/hippie_check.sh, per-datum rows in data/ref_ids.csv.
// Tiny world: dm ref_ids.dm, then dd ref_ids.dmb -invisible.

#define RI_N 20000
#define RI_SLOW_US 3

/datum/ri_probe
	var/n = 0

/proc/ri_set(label, list/datums, list/rows)
	var/slow_ref = 0
	var/slow_again = 0
	var/slow_text = 0
	var/first
	var/last
	var/text
	for(var/i in 1 to length(datums))
		var/datum/ri_probe/P = datums[i]
		var/t0 = world.tick_usage
		text = "\ref[P]"
		var/t1 = world.tick_usage
		var/ref = text
		var/ref_us = (t1 - t0) * world.tick_lag * 1000
		text = null
		ref = "[ref]"
		var/front = copytext(ref, 1, 6)
		var/back = copytext(ref, 6)
		ref = null
		t0 = world.tick_usage
		text = "\ref[P]"
		t1 = world.tick_usage
		var/again_us = (t1 - t0) * world.tick_lag * 1000
		ref = text
		text = null
		t0 = world.tick_usage
		text = "[front][back]"
		t1 = world.tick_usage
		var/text_us = (t1 - t0) * world.tick_lag * 1000
		if(text != ref)
			ri_log("[label]: the rebuilt text differs: [text] and [ref]")
		first = first || ref
		last = ref
		slow_ref += ref_us > RI_SLOW_US
		slow_again += again_us > RI_SLOW_US
		slow_text += text_us > RI_SLOW_US
		rows += "[label],[i],[ref],[round(ref_us, 0.1)],[round(again_us, 0.1)],[round(text_us, 0.1)]"
	ri_log("[label]: [length(datums)] datums, [first] to [last], slow \\ref [slow_ref], slow again [slow_again], slow rebuilt text [slow_text]")

/proc/ri_cases()
	ri_log("BYOND [world.byond_version].[world.byond_build], [world.fps] ticks")
	var/list/rows = list("set,index,ref,ref_us,again_us,text_us")
	var/list/sets = list()
	for(var/s in 1 to 4)
		var/list/made = new/list(RI_N)
		for(var/i in 1 to RI_N)
			made[i] = new /datum/ri_probe
		sets += list(made)
		sleep(2)
		ri_set("set[s]", made, rows)
		sleep(2)
	ri_set("set1again", sets[1], rows)
	sets[2] = null
	sleep(2)
	var/list/remade = new/list(RI_N)
	for(var/i in 1 to RI_N)
		remade[i] = new /datum/ri_probe
	sleep(2)
	ri_set("remade", remade, rows)
	ri_save(jointext(rows, "\n"))
	ri_log("done")
	del(world)

#ifdef UNTIL

/datum/controller/master
	sleep_offline_after_initializations = FALSE

/proc/ri_log(text)
	text2file(text, "data/ref_stall.txt")

/proc/ri_save(text)
	fdel("data/ref_ids.csv")
	text2file(text, "data/ref_ids.csv")

/world/New()
	. = ..()
	spawn(0)
		UNTIL(SSticker.initialized)
		SSticker.timeLeft = -1
		sleep(100)
		ri_cases()

#else

/world
	fps = 20

/proc/ri_log(text)
	world.log << text

/proc/ri_save(text)
	return

/world/New()
	. = ..()
	spawn(5)
		ri_cases()

#endif
