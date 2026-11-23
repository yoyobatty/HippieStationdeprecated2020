// Keyed list costs against list size. Stand-alone: dm assoc_key.dm, then dd assoc_key.dmb -invisible.
// Results go to world.log in ns per operation (1000 operations, world.tick_usage deltas).

#define REPS 1000

/world
	fps = 20

/proc/ms()
	return world.tick_usage * world.tick_lag

/world/New()
	..()
	spawn(10)
		world.log << "BYOND [world.byond_version].[world.byond_build]"
		var/list/fresh = list()
		for(var/i in 1 to REPS)
			fresh += "new_[i]"
		for(var/n in list(10, 1000, 10000, 100000, 300000))
			var/list/A = list()
			for(var/i in 1 to n)
				A["key_[i]"] = i
			var/hit = "key_[n]"
			var/x
			sleep(1)
			var/t0 = ms()
			for(var/k in fresh)
				A[k] = 1
			var/insert = (ms() - t0) * 1e6 / REPS
			sleep(1)
			t0 = ms()
			for(var/k in fresh)
				A[k] = 2
			var/overwrite = (ms() - t0) * 1e6 / REPS
			sleep(1)
			t0 = ms()
			for(var/i in 1 to REPS)
				x = (hit in A)
			var/in_test = (ms() - t0) * 1e6 / REPS
			sleep(1)
			t0 = ms()
			for(var/i in 1 to REPS)
				x = !isnull(A[hit])
			var/read_test = (ms() - t0) * 1e6 / REPS
			world.log << "[n] keys: new key [round(insert)] ns, existing key [round(overwrite)] ns, key in list [round(in_test)] ns, !isnull(list\[key\]) [round(read_test)] ns[x ? "" : " "]"
		world.log << "done"
		del(world)
