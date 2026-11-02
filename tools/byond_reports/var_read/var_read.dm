// One var read from each of 65,025 turfs, in DM and through Byondapi. Stand-alone apart from var_read.dll: run build.bat, then
// dm var_read.dm, then dd var_read.dmb -trusted -invisible. Results go to world.log.
// Turfs carry 24 vars with 12 of them changed from the default on every turf, roughly what a real game's turfs look like.

#define PASSES 6

/world
	fps = 20
	maxx = 255
	maxy = 255
	maxz = 1
	turf = /turf/test

/turf/test
	var/a1 = 0
	var/a2 = 0
	var/a3 = 0
	var/a4 = 0
	var/a5 = 0
	var/a6 = 0
	var/a7 = 0
	var/a8 = 0
	var/a9 = 0
	var/a10 = 0
	var/a11 = 0
	var/heat = 0
	var/b1 = 1
	var/b2 = 1
	var/b3 = 1
	var/b4 = 1
	var/b5 = 1
	var/b6 = 1
	var/b7 = 1
	var/b8 = 1
	var/b9 = 1
	var/b10 = 1
	var/b11 = 1
	var/untouched = 1

/proc/ns_a_read_dm(list/turfs, which)
	var/total = 0
	var/start = world.tick_usage
	if(which == "heat")
		for(var/turf/test/T as anything in turfs)
			total += T.heat
	else
		for(var/turf/test/T as anything in turfs)
			total += T.untouched
	var/ms = (world.tick_usage - start) * world.tick_lag
	return total ? ms * 1000000 / length(turfs) : -1

/proc/ns_a_loop_dm(list/turfs)
	var/total = 0
	var/start = world.tick_usage
	for(var/turf/test/T as anything in turfs)
		total += 1
	var/ms = (world.tick_usage - start) * world.tick_lag
	return total ? ms * 1000000 / length(turfs) : -1

/proc/median(list/values)
	var/list/sorted = values.Copy()
	for(var/i in 2 to length(sorted))
		var/value = sorted[i]
		var/j = i - 1
		while(j >= 1 && sorted[j] > value)
			sorted[j + 1] = sorted[j]
			j--
		sorted[j + 1] = value
	return round(sorted[round((length(sorted) + 1) / 2)], 0.1)

/proc/run_cases()
	world.log << "BYOND [world.byond_version].[world.byond_build]"
	var/list/turfs = list()
	for(var/turf/test/T in world)
		T.a1 = 2
		T.a2 = 2
		T.a3 = 2
		T.a4 = 2
		T.a5 = 2
		T.a6 = 2
		T.a7 = 2
		T.a8 = 2
		T.a9 = 2
		T.a10 = 2
		T.a11 = 2
		T.heat = 2
		turfs += T
	world.log << "[length(turfs)] turfs, median of [PASSES] passes, ns a read"
	var/list/loop = list()
	var/list/dm_heat = list()
	var/list/dm_untouched = list()
	var/list/api_heat = list()
	var/list/api_untouched = list()
	var/list/api_whole = list()
	for(var/pass in 1 to PASSES)
		sleep(1)
		loop += ns_a_loop_dm(turfs)
		sleep(1)
		dm_heat += ns_a_read_dm(turfs, "heat")
		sleep(1)
		dm_untouched += ns_a_read_dm(turfs, "untouched")
		sleep(1)
		api_heat += call_ext("var_read.dll", "byond:read_var_each")(turfs, "heat")
		sleep(1)
		api_untouched += call_ext("var_read.dll", "byond:read_var_each")(turfs, "untouched")
		sleep(1)
		api_whole += call_ext("var_read.dll", "byond:read_list_whole")(turfs)
	world.log << "DM, the loop alone: [median(loop)]"
	world.log << "DM, loop and a var changed on every turf: [median(dm_heat)]"
	world.log << "DM, loop and a var left at its default: [median(dm_untouched)]"
	world.log << "Byondapi, one call a turf, changed var: [median(api_heat)]"
	world.log << "Byondapi, one call a turf, default var: [median(api_untouched)]"
	world.log << "Byondapi, the whole list in one call, per item: [median(api_whole)]"
	world.log << "done"
	del(world)

/world/New()
	. = ..()
	spawn(5)
		run_cases()
