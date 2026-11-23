// Stand-alone BYOND op scaling probe: does an op that should cost the same at any size slow down as N grows?
// dm op_scaling.dm, then dd op_scaling.dmb -invisible. Results go to world.log as
// "op | N | ns per op" lines, then a FLAG line for each op whose cost grows more than 3x from N=10 to the largest N.
// Timing: world.tick_usage deltas over REPS ops, best of TRIES, minus an empty-loop baseline.

#define REPS 2000
#define TRIES 7

/world
	fps = 20
	maxx = 20
	maxy = 20
	maxz = 1

/datum/probe_item
	var/a = 1
	var/b = 2

/obj/probe_obj

var/list/sizes = list(10, 1000, 100000, 300000)
var/list/ops = list(
	"list index read", "list append+pop", "list.len read", "assoc read (text key)", "assoc write existing",
	"assoc insert+remove new key", "assoc read (datum key)", "key in assoc list (hit, last)",
	"new string (unsorted)", "new string (ascending)", "\\ref of new datum", "locate(ref string)",
	"locate(tag)", "new+del datum (N alive)", "turf.contents add+remove obj", "locate(type) in turf (hit last)",
	"spawn with N sleepers", "list.Copy (5 items)", "num2text", "text2path")
var/list/results = list()

var/list/L
var/list/A
var/list/D
var/list/keys
var/list/datums
var/list/kept_strings
var/datum/probe_item/last_datum
var/turf/probe_turf
var/obj/probe_obj/last_obj
var/serial = 0
var/sleepers_release = 0

/proc/now_ms()
	return world.tick_usage * world.tick_lag

/proc/setup(op, n)
	L = new/list(n)
	for(var/i in 1 to n)
		L[i] = i
	switch(op)
		if("assoc read (text key)", "assoc write existing", "assoc insert+remove new key", "key in assoc list (hit, last)")
			A = list()
			keys = list()
			for(var/i in 1 to n)
				var/k = "key_[i]"
				A[k] = i
				keys += k
		if("assoc read (datum key)")
			D = list()
			datums = list()
			for(var/i in 1 to n)
				var/datum/probe_item/d = new
				D[d] = i
				datums += d
		if("new string (unsorted)", "new string (ascending)", "\\ref of new datum")
			kept_strings = new/list(n)
			for(var/i in 1 to n)
				kept_strings[i] = "pre_[num2text(rand(1, 16777215) * 64 + (i % 64), 12)]"
		if("locate(ref string)", "locate(tag)", "new+del datum (N alive)")
			datums = new/list(n)
			for(var/i in 1 to n)
				var/datum/probe_item/d = new
				datums[i] = d
				if(op == "locate(tag)")
					d.tag = "tag_[i]"
			last_datum = datums[n]
		if("turf.contents add+remove obj", "locate(type) in turf (hit last)")
			probe_turf = locate(1, 1, 1)
			for(var/atom/movable/M in probe_turf)
				M.loc = null
			for(var/i in 1 to min(n, 20000))
				new /obj(probe_turf)
			last_obj = new /obj/probe_obj(probe_turf)
		if("spawn with N sleepers")
			sleepers_release = 0
			for(var/i in 1 to min(n, 20000))
				spawn(rand(100, 100000))
					return
	return TRUE

/proc/teardown(op)
	if(probe_turf)
		for(var/atom/movable/M in probe_turf)
			M.loc = null
		probe_turf = null
	L = null; A = null; D = null; keys = null; datums = null; kept_strings = null; last_datum = null; last_obj = null

/proc/run_op(op, n, reps)
	var/x
	var/t0 = now_ms()
	switch(op)
		if("baseline")
			for(var/i in 1 to reps)
				x = i
		if("list index read")
			for(var/i in 1 to reps)
				x = L[(i % n) + 1]
		if("list append+pop")
			for(var/i in 1 to reps)
				L += i
				L.len--
		if("list.len read")
			for(var/i in 1 to reps)
				x = L.len
		if("assoc read (text key)")
			for(var/i in 1 to reps)
				x = A[keys[(i % n) + 1]]
		if("assoc write existing")
			for(var/i in 1 to reps)
				A[keys[(i % n) + 1]] = i
		if("assoc insert+remove new key")
			for(var/i in 1 to reps)
				A["zz_new"] = i
				A -= "zz_new"
		if("assoc read (datum key)")
			for(var/i in 1 to reps)
				x = D[datums[(i % n) + 1]]
		if("key in assoc list (hit, last)")
			var/k = keys[n]
			for(var/i in 1 to reps)
				x = (k in A)
		if("new string (unsorted)")
			for(var/i in 1 to reps)
				x = "u_[num2text(rand(1, 16777215), 12)]_[serial++]"
		if("new string (ascending)")
			for(var/i in 1 to reps)
				x = "pre_[num2text(16777215 * 64 + serial++, 12)]"
		if("\\ref of new datum")
			for(var/i in 1 to reps)
				var/datum/probe_item/d = new
				x = "\ref[d]"
		if("locate(ref string)")
			var/r = "\ref[last_datum]"
			for(var/i in 1 to reps)
				x = locate(r)
		if("locate(tag)")
			for(var/i in 1 to reps)
				x = locate("tag_[n]")
		if("new+del datum (N alive)")
			for(var/i in 1 to reps)
				var/datum/probe_item/d = new
				del(d)
		if("turf.contents add+remove obj")
			for(var/i in 1 to reps)
				var/obj/o = new /obj(probe_turf)
				o.loc = null
		if("locate(type) in turf (hit last)")
			for(var/i in 1 to reps)
				x = locate(/obj/probe_obj) in probe_turf
		if("spawn with N sleepers")
			for(var/i in 1 to reps)
				spawn(rand(100, 100000))
					return
		if("list.Copy (5 items)")
			var/list/small = list(1, 2, 3, 4, 5)
			for(var/i in 1 to reps)
				x = small.Copy()
		if("num2text")
			for(var/i in 1 to reps)
				x = num2text(i * 1.5)
		if("text2path")
			for(var/i in 1 to reps)
				x = text2path("/datum/probe_item")
	var/t1 = now_ms()
	return t1 - t0

/proc/measure(op, n)
	var/best = 1e9
	for(var/t in 1 to TRIES)
		sleep(1)
		best = min(best, run_op(op, n, REPS))
	return best

/world/New()
	..()
	spawn(10)
		world.log << "BYOND [world.byond_version].[world.byond_build]"
		var/base = measure("baseline", 10)
		world.log << "baseline loop [round(base * 1e6 / REPS, 0.1)] ns per op"
		for(var/op in ops)
			var/list/row = list()
			for(var/n in sizes)
				setup(op, n)
				var/ms = measure(op, n) - base
				var/ns = max(0, ms * 1e6 / REPS)
				row += ns
				world.log << "[op] | [n] | [round(ns, 0.1)]"
				teardown(op)
			results[op] = row
		for(var/op in results)
			var/list/row = results[op]
			var/lo = max(row[1], 5)
			var/hi = row[row.len]
			if(hi > lo * 3)
				world.log << "FLAG [op]: [round(row[1], 0.1)] ns at N=10 -> [round(hi, 0.1)] ns at N=[sizes[sizes.len]] ([round(hi / lo, 0.1)]x)"
		world.log << "done"
		del(world)
