// Cost of touching `args`, of variadic procs, of locals, and of default args. -> argscost.log
#define REPS 200000
#define TRIES 9
/world
	fps = 10
	maxx = 10
	maxy = 10
	maxz = 1
	loop_checks = 0

/proc/p2(a, b)
	return a
/proc/p2v(a, b, ...)
	return a
/proc/p2v_len(a, b, ...)
	return length(args) > 2 ? 1 : a
/proc/p2_len(a, b)
	return length(args) > 2 ? 1 : a
/proc/p2_def(a, b = 0)
	return a
/proc/p2_def_null(a, b)
	if(isnull(b))
		b = 0
	return a
/proc/locals0()
	return 1
/proc/locals10u()
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
	return 1
/proc/locals1()
	var/a1 = 1
	return a1
/proc/dot_ret()
	. = 1
/proc/sig_like(a, b)
	return a

/proc/case_run(c, reps)
	var/d
	var/t0 = world.tick_usage
	switch(c)
		if(1)
			for(var/i in 1 to reps)
				d = i
		if(2)
			for(var/i in 1 to reps)
				d = p2(i, 0)
		if(3)
			for(var/i in 1 to reps)
				d = p2v(i, 0)
		if(4)
			for(var/i in 1 to reps)
				d = p2v_len(i, 0)
		if(5)
			for(var/i in 1 to reps)
				d = p2_len(i, 0)
		if(6)
			for(var/i in 1 to reps)
				d = p2_def(i)
		if(7)
			for(var/i in 1 to reps)
				d = p2_def_null(i)
		if(8)
			for(var/i in 1 to reps)
				d = locals0()
		if(9)
			for(var/i in 1 to reps)
				d = locals10u()
		if(10)
			for(var/i in 1 to reps)
				d = locals1()
		if(11)
			for(var/i in 1 to reps)
				d = dot_ret()
		if(12)
			for(var/i in 1 to reps)
				d = p2(i)
	d = d
	return (world.tick_usage - t0) * world.tick_lag * 1e6 / reps

/world/New()
	..()
	spawn(5)
		var/list/names = list("baseline", "p(a,b)", "p(a,b,...)", "p(a,b,...) reads length(args)", "p(a,b) reads length(args)", "p(a, b=0) called with 1 arg", "p(a,b) isnull(b) default, 1 arg", "0 locals", "10 unset locals", "1 local", ". = 1 (no return)", "p(a,b) called with 1 arg")
		var/list/best = list()
		for(var/c in 1 to names.len)
			best += 1e9
		for(var/t in 1 to TRIES)
			for(var/c in 1 to names.len)
				sleep(1)
				best[c] = min(best[c], case_run(c, REPS))
		for(var/c in 1 to names.len)
			world.log << "RESULT | [names[c]] | [round(best[c] - best[1], 0.1)] ns"
		world.log << "DONE"
		shutdown()
