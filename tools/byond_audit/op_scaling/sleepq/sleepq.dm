// 20,000 sleepers, then spawn(rand) in a busy loop for a sampler. 20 s.
/world
	fps = 20
/proc/sleeper()
	set waitfor = FALSE
	sleep(rand(3000, 6000))
/proc/noop()
	set waitfor = FALSE
	sleep(rand(1, 100))
/world/New()
	..()
	spawn(5)
		for(var/i in 1 to 20000)
			sleeper()
		var/start = world.timeofday
		while(world.timeofday - start < 200)
			for(var/i in 1 to 500)
				noop()
			sleep(world.tick_lag)
		del(world)
