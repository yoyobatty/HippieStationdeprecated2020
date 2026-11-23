// Formats numbers in a busy loop for a sampler: "[i]" whole numbers, then num2text of fractions, 15 s each.
/world
	fps = 20
/world/New()
	..()
	spawn(5)
		var/s
		var/start = world.timeofday
		while(world.timeofday - start < 150)
			for(var/i in 1 to 20000)
				s = "[i]"
			sleep(world.tick_lag)
		start = world.timeofday
		while(world.timeofday - start < 150)
			for(var/i in 1 to 20000)
				s = num2text(i / 7)
			sleep(world.tick_lag)
		world.log << "done[s]"
		del(world)
