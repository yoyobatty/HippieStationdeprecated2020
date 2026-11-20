// What a fresh datum's first var writes cost: new + K writes + del, and whether writing a var's own default (null) costs the same.
// dm newwrites.dm && dd newwrites.dmb -invisible -trusted -logself  -> newwrites.log
#define REPS 50000
#define TRIES 9
/world
	fps = 10
	maxx = 10
	maxy = 10
	maxz = 1
	loop_checks = 0

/datum/t16
	var/a1
	var/a2
	var/a3
	var/a4
	var/a5
	var/a6
	var/a7
	var/a8
	var/a9
	var/a10
	var/a11
	var/a12
	var/a13
	var/a14
	var/a15
	var/a16
	var/n1 = 5

/proc/case_run(c, reps)
	var/datum/t16/d
	var/t0 = world.tick_usage
	switch(c)
		if(1)
			for(var/i in 1 to reps)
				d = new
		if(2)
			for(var/i in 1 to reps)
				d = new
				d.a1 = i
		if(3)
			for(var/i in 1 to reps)
				d = new
				d.a1 = i
				d.a2 = i
				d.a3 = i
				d.a4 = i
				d.a5 = i
		if(4)
			for(var/i in 1 to reps)
				d = new
				d.a1 = i
				d.a2 = i
				d.a3 = i
				d.a4 = i
				d.a5 = i
				d.a6 = i
				d.a7 = i
				d.a8 = i
				d.a9 = i
				d.a10 = i
				d.a11 = i
				d.a12 = i
				d.a13 = i
				d.a14 = i
				d.a15 = i
		if(5) // 5 real values + 10 writes of null (the default)
			for(var/i in 1 to reps)
				d = new
				d.a1 = i
				d.a2 = i
				d.a3 = i
				d.a4 = i
				d.a5 = i
				d.a6 = null
				d.a7 = null
				d.a8 = null
				d.a9 = null
				d.a10 = null
				d.a11 = null
				d.a12 = null
				d.a13 = null
				d.a14 = null
				d.a15 = null
		if(6) // 15 writes in reverse order (insert at the front of a sorted array each time)
			for(var/i in 1 to reps)
				d = new
				d.a15 = i
				d.a14 = i
				d.a13 = i
				d.a12 = i
				d.a11 = i
				d.a10 = i
				d.a9 = i
				d.a8 = i
				d.a7 = i
				d.a6 = i
				d.a5 = i
				d.a4 = i
				d.a3 = i
				d.a2 = i
				d.a1 = i
		if(7) // rewrite an existing override 15 times
			d = new
			d.a1 = 1
			for(var/i in 1 to reps)
				d.a1 = i
				d.a1 = i
				d.a1 = i
				d.a1 = i
				d.a1 = i
				d.a1 = i
				d.a1 = i
				d.a1 = i
				d.a1 = i
				d.a1 = i
				d.a1 = i
				d.a1 = i
				d.a1 = i
				d.a1 = i
				d.a1 = i
		if(8) // write default (numeric 5) to n1
			for(var/i in 1 to reps)
				d = new
				d.n1 = 5
	. = (world.tick_usage - t0) * world.tick_lag * 1e6 / reps

/world/New()
	..()
	spawn(5)
		var/list/names = list("new+del, 0 writes", "1 write", "5 writes", "15 writes", "5 writes + 10 null writes", "15 writes reverse order", "15 rewrites of one existing var (per 15)", "write own default 5")
		var/list/best = list()
		for(var/c in 1 to names.len)
			best += 1e9
		for(var/t in 1 to TRIES)
			for(var/c in 1 to names.len)
				sleep(1)
				best[c] = min(best[c], case_run(c, REPS))
		for(var/c in 1 to names.len)
			world.log << "RESULT | [names[c]] | [round(best[c], 0.1)] ns"
		// does a null write make an override? read speed + vars check
		var/datum/t16/x = new
		x.a6 = null
		world.log << "null write shows in vars as changed: [x.vars["a6"] != initial(x.a6)]"
		world.log << "DONE"
		shutdown()
