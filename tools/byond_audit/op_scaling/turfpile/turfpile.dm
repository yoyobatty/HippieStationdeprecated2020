// A plain /obj moved onto and off a turf holding 20,000 plain /objs, in a busy loop for a sampler. 20 s.
/world
	fps = 20
	maxx = 5
	maxy = 5
	maxz = 1
/world/New()
	..()
	spawn(5)
		var/turf/pile = locate(2, 2, 1)
		var/turf/beside = locate(3, 2, 1)
		var/obj/mover = new(beside)
		for(var/i in 1 to 20000)
			new /obj(pile)
		var/start = world.timeofday
		while(world.timeofday - start < 200)
			for(var/i in 1 to 50)
				mover.loc = pile
				mover.loc = beside
			sleep(world.tick_lag)
		del(world)
