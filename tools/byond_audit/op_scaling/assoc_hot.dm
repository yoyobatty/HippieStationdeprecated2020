// Inserts new keys into a 300k assoc list for ~15 s so a sampler can see where the time goes.
/world/New()
	..()
	spawn(5)
		var/list/A = list()
		for(var/i in 1 to 300000)
			A["key_[i]"] = i
		var/end = world.timeofday + 150
		var/n = 0
		while(world.timeofday < end)
			A["new_[n++]"] = 1
			if(!(n % 200))
				sleep(world.tick_lag)
		world.log << "inserted [n]"
		del(world)
