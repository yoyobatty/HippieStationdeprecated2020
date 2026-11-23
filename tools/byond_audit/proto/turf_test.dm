// Test for turf_chain.dll: the same seeded run of moves, adds, deletes and contents edits, once on the engine and
// once with the DLL; every loc's contents (in order) must match after each round. Then the pile timings.
// dm turf_test.dm; dd turf_test.dmb -invisible -trusted (turf_chain.dll next to the dmb). Results to world.log.

#define DLL "turf_chain.dll"
#define REPS 500

/world
	fps = 20
	maxx = 6
	maxy = 6
	maxz = 1

/obj/thing
/obj/box
/mob/holder

var/failures = 0
var/serial = 0

/proc/ms()
	return world.tick_usage * world.tick_lag

/proc/named(type, loc)
	var/atom/movable/A = new type(loc)
	A.name = "[++serial]"
	return A

/proc/snapshot(list/places)
	. = list()
	for(var/atom/P in places)
		var/list/names = list()
		for(var/atom/movable/A in P.contents)
			names += A.name
		. += "[P.name]: [jointext(names, ",")]"

/proc/run_world(label)
	rand_seed(12345)
	serial = 0
	var/list/turfs = block(locate(1, 1, 1), locate(4, 4, 1))
	var/list/places = turfs.Copy()
	var/list/movers = list()
	for(var/i in 1 to 6)
		var/obj/box/B = named(/obj/box, pick(turfs))
		B.name = "box[i]"
		places += B
	for(var/i in 1 to 2)
		var/mob/holder/M = named(/mob/holder, pick(turfs))
		M.name = "mob[i]"
		places += M
	for(var/i in 1 to 300)
		movers += named(/obj/thing, pick(places))
	. = list()
	for(var/round in 1 to 30)
		for(var/i in 1 to 200)
			var/obj/thing/T = pick(movers)
			switch(rand(1, 10))
				if(1 to 4)
					T.loc = pick(places)
				if(5)
					T.Move(pick(turfs))
				if(6)
					var/atom/P = pick(places)
					P.contents += T
				if(7)
					if(T.loc)
						var/atom/L = T.loc
						L.contents -= T
				if(8)
					movers -= T
					del(T)
					movers += named(/obj/thing, pick(places))
				if(9)
					T.loc = null
				if(10)
					movers += named(/obj/thing, pick(places))
		. += snapshot(places)
	for(var/atom/movable/A in movers)
		del(A)
	for(var/atom/P in places)
		if(ismovable(P))
			del(P)

/proc/timings(label)
	var/turf/pile = locate(5, 5, 1)
	var/turf/beside = locate(6, 5, 1)
	var/obj/mover = new(beside)
	var/list/made = list()
	for(var/n in list(0, 1000, 20000))
		while(length(made) < n)
			made += new /obj(pile)
		sleep(1)
		var/t0 = ms()
		for(var/i in 1 to REPS)
			mover.loc = pile
			mover.loc = beside
		world.log << "[label]: [n] objs on the turf: onto it and off again [round((ms() - t0) * 1e6 / REPS)] ns"
	for(var/obj/O in made)
		del(O)
	del(mover)

/world/New()
	..()
	spawn(10)
		world.log << "BYOND [world.byond_version].[world.byond_build]"
		var/list/want = run_world("engine")
		timings("engine")
		world.log << call_ext(DLL, "install")()
		var/list/got = run_world("chain")
		if(length(want) != length(got))
			failures++
		for(var/i in 1 to min(length(want), length(got)))
			if(want[i] != got[i])
				failures++
				if(failures < 10)
					world.log << "FAIL: [want[i]]\n  became [got[i]]"
		world.log << "compared [length(want)] contents lists, [failures] differ"
		timings("chain")
		world.log << call_ext(DLL, "stats")()
		world.log << call_ext(DLL, "uninstall")()
		var/list/again = run_world("engine again")
		for(var/i in 1 to min(length(want), length(again)))
			if(want[i] != again[i])
				failures++
		world.log << "done, [failures] failures"
		del(world)
