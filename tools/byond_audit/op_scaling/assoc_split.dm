// Splits the assoc "insert + remove" flag: which half grows with N? Also key-check alternatives.
// dm assoc_split.dm, then dd assoc_split.dmb -invisible. Results to world.log in ns per op.

#define REPS 1000

/world
	fps = 20

/proc/ms()
	return world.tick_usage * world.tick_lag

/proc/fill(n)
	var/list/A = list()
	for(var/i in 1 to n)
		A["key_[i]"] = i
	return A

/world/New()
	..()
	spawn(10)
		world.log << "BYOND [world.byond_version].[world.byond_build]"
		var/list/news = list()
		for(var/i in 1 to REPS)
			news += "new_[i]"
		for(var/n in list(10, 1000, 100000, 300000))
			var/list/A = fill(n)
			sleep(1)
			var/t0 = ms()
			for(var/k in news)
				A[k] = 1
			var/ins = (ms() - t0) * 1e6 / REPS
			sleep(1)
			t0 = ms()
			for(var/k in news)
				A -= k
			var/rem = (ms() - t0) * 1e6 / REPS
			sleep(1)
			for(var/k in news)
				A[k] = 1
			t0 = ms()
			for(var/k in news)
				A.Remove(k)
			var/remcall = (ms() - t0) * 1e6 / REPS
			sleep(1)
			var/k1 = "key_[n]"
			var/x
			t0 = ms()
			for(var/i in 1 to REPS)
				x = !isnull(A[k1])
			var/isn = (ms() - t0) * 1e6 / REPS
			sleep(1)
			t0 = ms()
			for(var/i in 1 to REPS)
				x = (k1 in A)
			var/inn = (ms() - t0) * 1e6 / REPS
			world.log << "N [n] | insert new key [round(ins, 0.1)] | A -= key (new keys at end) [round(rem, 0.1)] | A.Remove(key) [round(remcall, 0.1)] | !isnull(A\[k\]) [round(isn, 0.1)] | k in A [round(inn, 0.1)] [x]"
		world.log << "done"
		del(world)
