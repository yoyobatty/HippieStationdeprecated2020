// Is building text slow where it lands in BYOND's string tree? In the game: which texts are slow. In a tiny world: keep ascending ref strings
// alive and see whether the same slowdown appears, then the same number of strings kept alive in shuffled order.
// HARNESS=../string_probe/string_tree.dm bash tools/byond_reports/ref_stall/hippie_check.sh
// Tiny world: dm string_tree.dm, then dd string_tree.dmb -invisible.

#define ST_SAMPLES 3000

/datum/st_probe
	var/n = 0

/proc/st_median(list/values)
	var/list/counts = new/list(5000)
	for(var/value in values)
		counts[min(max(round(value * 10) + 1, 1), 5000)]++
	var/seen = 0
	for(var/slot in 1 to 5000)
		seen += counts[slot]
		if(seen * 2 >= length(values))
			return (slot - 1) / 10
	return -1

/// Times building front + a 6 hex digit counter + back, text nobody has made, ST_SAMPLES of them.
/proc/st_text(label, front, back, start_at)
	var/list/times = new/list(ST_SAMPLES)
	var/text
	for(var/i in 1 to ST_SAMPLES)
		var/middle = num2text(start_at + i * 16, 6, 16)
		var/t0 = world.tick_usage
		text = "[front][middle][back]"
		var/t1 = world.tick_usage
		times[i] = (t1 - t0) * world.tick_lag * 1000
	st_log("[label], like [text]: median [st_median(times)] us")
	sleep(1)

/proc/st_fresh_refs(label)
	var/list/times = new/list(ST_SAMPLES)
	var/list/keep = new/list(ST_SAMPLES)
	var/text
	for(var/i in 1 to ST_SAMPLES)
		var/datum/st_probe/P = new
		keep[i] = P
		var/t0 = world.tick_usage
		text = "\ref[P]"
		var/t1 = world.tick_usage
		times[i] = (t1 - t0) * world.tick_lag * 1000
	st_log("[label]: \\ref of a new datum, like [text]: median [st_median(times)] us")
	sleep(1)

/// In the game: which texts are slow.
/proc/st_in_game()
	var/datum/st_probe/P = new
	st_log("a new datum's ref is [ref(P)]")
	st_text("just past the boot ids", "\[0x21", "]", 0x60000)
	st_text("far past them", "\[0x21", "]", 0x700000)
	st_text("below the boot ids, but not a ref anything made", "\[0x21", "z]", 0x10000)
	st_text("next type byte", "\[0x22", "]", 0x60000)
	st_text("type byte below", "\[0x20", "]", 0x60000)
	st_text("lists", "\[0x0f", "]", 0x60000)
	st_text("bracket only", "\[", "]", 0x60000)
	st_text("no bracket", "0x21", "]", 0x60000)
	st_text("letters first", "zz", "]", 0x60000)
	st_text("sorts before \[", "A", "]", 0x60000)
	st_text("sorts just after \[", "\\", "]", 0x60000)
	st_fresh_refs("in the game")

/// Tiny world: ascending ref strings kept alive, then the same count shuffled.
/proc/st_tiny()
	var/list/datums = list()
	var/list/strings = list()
	for(var/target in list(1000, 10000, 50000, 200000, 500000))
		while(length(datums) < target)
			var/datum/st_probe/P = new
			datums += P
			strings += "\ref[P]"
			if(!(length(datums) % 10000))
				sleep(1)
		st_fresh_refs("[target] ascending ref strings alive")
		st_text("same size, text past them", "\[0x21", "]", 0x700000)
		st_text("same size, unrelated text", "unrelated ", "]", 0x60000)
	strings.Cut()
	strings = null
	sleep(5)
	st_fresh_refs("those strings released")
	var/list/order = new/list(length(datums))
	for(var/i in 1 to length(order))
		order[i] = i
	for(var/i in length(order) to 2 step -1)
		order.Swap(i, rand(1, i))
	var/list/kept = list()
	for(var/n in order)
		kept += "\ref[datums[n]]"
		if(!(length(kept) % 10000))
			sleep(1)
	st_fresh_refs("[length(kept)] of the same strings alive, made in shuffled order")
	st_text("shuffled, text past them", "\[0x21", "]", 0x700000)

#ifdef UNTIL

/datum/controller/master
	sleep_offline_after_initializations = FALSE

/proc/st_log(text)
	text2file(text, "data/ref_stall.txt")

/world/New()
	. = ..()
	spawn(0)
		UNTIL(SSticker.initialized)
		SSticker.timeLeft = -1
		sleep(100)
		st_log("BYOND [world.byond_version].[world.byond_build], [world.fps] ticks")
		st_in_game()
		st_log("done")
		del(world)

#else

/world
	fps = 20

/proc/st_log(text)
	world.log << text

/world/New()
	. = ..()
	spawn(5)
		st_log("BYOND [world.byond_version].[world.byond_build], [world.fps] ticks")
		st_tiny()
		st_log("done")
		del(world)

#endif
