// Moving a plain /obj onto and off a turf, against how many plain /objs are already there.
// None of the types override Cross, Crossed, Uncross, Uncrossed, Enter, Entered, Exit or Exited.
// Stand-alone: dm turf_entry.dm, then dd turf_entry.dmb -invisible. Results go to world.log.

#define REPS 500

/world
	fps = 20
	maxx = 5
	maxy = 5
	maxz = 1

/proc/ms()
	return world.tick_usage * world.tick_lag

/world/New()
	..()
	spawn(10)
		world.log << "BYOND [world.byond_version].[world.byond_build]"
		var/turf/pile = locate(2, 2, 1)
		var/turf/beside = locate(3, 2, 1)
		var/obj/mover = new(beside)
		var/have = 0
		for(var/n in list(0, 10, 100, 1000, 5000, 20000))
			while(have < n)
				new /obj(pile)
				have++
			sleep(1)
			var/t0 = ms()
			for(var/i in 1 to REPS)
				mover.loc = pile
				mover.loc = beside
			var/both = (ms() - t0) * 1e6 / REPS
			sleep(1)
			t0 = ms()
			for(var/i in 1 to REPS)
				mover.loc = beside
				mover.loc = beside
			var/control = (ms() - t0) * 1e6 / REPS
			world.log << "[n] objs on the turf: onto it and off again [round(both)] ns, same moves on an empty turf [round(control)] ns"
		world.log << "done"
		del(world)
