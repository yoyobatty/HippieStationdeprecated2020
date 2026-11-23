// Test for var_cache.dll: var reads timed before and after install, and every read checked against what it must be.
// dm var_test.dm; dd var_test.dmb -invisible -trusted (var_cache.dll next to the dmb). Results to world.log.

#define DLL "var_cache.dll"
#define N 2000
#define PASSES 200000

/world
	fps = 20
	maxx = 5
	maxy = 5
	maxz = 1

var/failures = 0
var/global_thing = 77

/proc/check(what, ok)
	if(!ok)
		failures++
		if(failures < 20)
			world.log << "FAIL: [what]"

/proc/ms()
	return world.tick_usage * world.tick_lag

// many vars, so the lists are long enough for the binary searches to matter
/datum/wide
	var/v01 = 1
	var/v02 = 2
	var/v03 = 3
	var/v04 = 4
	var/v05 = 5
	var/v06 = 6
	var/v07 = 7
	var/v08 = 8
	var/v09 = 9
	var/v10 = 10
	var/v11 = 11
	var/v12 = 12
	var/v13 = 13
	var/v14 = 14
	var/v15 = 15
	var/v16 = 16
	var/v17 = 17
	var/v18 = 18
	var/v19 = 19
	var/v20 = 20
	var/name = "wide"
	var/list/stuff

/datum/wide/sub
	v05 = 500
	v17 = "seventeen"

/obj/item
	var/force = 3

/proc/expected(datum/wide/W, i, which)
	// set in make(): odd i writes v02, v09, v19; i % 3 == 0 writes v12; subtypes default v05, v17
	switch(which)
		if(2)
			return i % 2 ? i * 2 : 2
		if(5)
			return istype(W, /datum/wide/sub) ? 500 : 5
		if(9)
			return i % 2 ? i * 9 : 9
		if(12)
			return i % 3 == 0 ? "s[i]" : 12
		if(17)
			return istype(W, /datum/wide/sub) ? "seventeen" : 17
		if(19)
			return i % 2 ? i * 19 : 19
	return which

var/list/things = list()

/proc/make()
	for(var/i in 1 to N)
		var/datum/wide/W = i % 4 ? new /datum/wide : new /datum/wide/sub
		if(i % 2)
			W.v02 = i * 2
			W.v09 = i * 9
			W.v19 = i * 19
		if(i % 3 == 0)
			W.v12 = "s[i]"
		things += W

/proc/correctness(label)
	for(var/i in 1 to N)
		var/datum/wide/W = things[i]
		check("[label] [i] v01", W.v01 == 1)
		check("[label] [i] v02", W.v02 == expected(W, i, 2))
		check("[label] [i] v05", W.v05 == expected(W, i, 5))
		check("[label] [i] v09", W.v09 == expected(W, i, 9))
		check("[label] [i] v12", W.v12 == expected(W, i, 12))
		check("[label] [i] v17", W.v17 == expected(W, i, 17))
		check("[label] [i] v19", W.v19 == expected(W, i, 19))
		check("[label] [i] v20", W.v20 == 20)
		check("[label] [i] vars", W.vars["v19"] == expected(W, i, 19))
		check("[label] [i] initial", initial(W.v05) == expected(W, i, 5))
		check("[label] [i] type", W.type == (i % 4 ? /datum/wide : /datum/wide/sub))
	// write then read back, and put back
	for(var/i in 1 to N)
		var/datum/wide/W = things[i]
		W.v07 = "w[i]"
		check("[label] [i] write", W.v07 == "w[i]")
		W.v07 = initial(W.v07)
		check("[label] [i] put back", W.v07 == 7)
	// atoms, the world, globals
	var/obj/item/O = new
	check("[label] obj force", O.force == 3)
	O.force = 9
	check("[label] obj force set", O.force == 9)
	check("[label] obj name", O.name == "item")
	check("[label] global", global_thing == 77)
	check("[label] world", world.maxx == 5)
	world.log << "[label]: correctness done, failures so far [failures]"

/proc/timings(label)
	sleep(1)
	var/datum/wide/A = things[1] // odd: overridden v02, v09, v19
	var/datum/wide/B = things[2] // even: nothing overridden
	var/t0 = ms()
	var/sum = 0
	for(var/i in 1 to PASSES)
		sum += A.v19 + A.v02
	var/over_ns = (ms() - t0) * 1e6 / PASSES
	sleep(1)
	t0 = ms()
	for(var/i in 1 to PASSES)
		sum += B.v19 + B.v02
	var/def_ns = (ms() - t0) * 1e6 / PASSES
	sleep(1)
	t0 = ms()
	for(var/i in 1 to PASSES)
		var/datum/wide/W = things[(i % N) + 1]
		sum += W.v20
	var/many_ns = (ms() - t0) * 1e6 / PASSES
	world.log << "[label]: two overridden vars [round(over_ns)] ns, two default vars [round(def_ns)] ns, var of 2000 objects in turn [round(many_ns)] ns[sum ? "" : " "]"

/world/New()
	..()
	spawn(10)
		world.log << "BYOND [world.byond_version].[world.byond_build]"
		make()
		timings("engine")
		timings("engine")
		correctness("engine")
		world.log << call_ext(DLL, "install")()
		timings("cache")
		timings("cache")
		correctness("cache")
		world.log << call_ext(DLL, "stats")()
		world.log << call_ext(DLL, "uninstall")()
		correctness("engine again")
		timings("engine again")
		world.log << "done, [failures] failures"
		del(world)
