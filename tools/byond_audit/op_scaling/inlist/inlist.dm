// "k in L" on a 100,000-key assoc list in a busy loop, for a sampler. 20 s.
/world
	fps = 20
/world/New()
	..()
	spawn(5)
		var/list/L = list()
		for(var/i in 1 to 100000)
			L["k[i]"] = i
		var/n = 0
		var/start = world.timeofday
		while(world.timeofday - start < 200)
			for(var/i in 1 to 20)
				if("k[100000 - i]" in L)
					n++
			sleep(world.tick_lag)
		world.log << "done [n]"
		del(world)
