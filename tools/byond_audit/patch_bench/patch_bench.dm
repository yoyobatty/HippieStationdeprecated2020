// Bench for hotpatch.py: the same mixed DM work timed every 2 seconds for 60 seconds, so a patch switched on or off
// mid-run shows as a step. Stand-alone: dm patch_bench.dm, then dd patch_bench.dmb -invisible -trusted. world.log has
// one line per round: seconds since start, then ns per loop pass for each kind of work.

#define PASSES 20000

/world
	fps = 20
	maxx = 5
	maxy = 5
	maxz = 1

/datum/thing
	var/a = 1
	var/b = 2
	var/name = "thing"
	var/datum/thing/other
	var/list/stuff

/datum/thing/proc/add(x, y)
	return x + y + a

/proc/ms()
	return world.tick_usage * world.tick_lag

/world/New()
	..()
	spawn(10)
		world.log << "BYOND [world.byond_version].[world.byond_build]"
		var/datum/thing/T = new
		T.other = new /datum/thing
		T.stuff = list()
		for(var/i in 1 to 100)
			T.stuff["k[i]"] = i
		var/list/nums = list()
		for(var/i in 1 to 100)
			nums += i
		var/start = world.timeofday
		while(world.timeofday - start < 600)
			sleep(1)
			var/t0 = ms()
			var/sum = 0
			for(var/i in 1 to PASSES) // numbers: vars, proc call, list read
				sum += T.add(i, T.b) + nums[(i % 100) + 1] + T.other.a
			var/numeric = (ms() - t0) * 1e6 / PASSES
			sleep(1)
			t0 = ms()
			var/s
			for(var/i in 1 to PASSES) // datums and strings
				var/datum/thing/O = T.other
				s = O.name
				O.other = T
				O.other = null
				s = T.stuff["k[(i % 100) + 1]"]
			var/objects = (ms() - t0) * 1e6 / PASSES
			world.log << "[round((world.timeofday - start) / 10)] s: numbers [round(numeric)] ns, objects+strings [round(objects)] ns[sum && s ? "" : " "]"
			sleep(19)
		world.log << "done"
		del(world)
