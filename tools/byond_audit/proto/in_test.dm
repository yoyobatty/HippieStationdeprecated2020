// Test for in_index.dll: "k in L" after every kind of list change, answered by the engine and then with the DLL
// installed; every answer must match. Then timings on a large keyed list.
// dm in_test.dm; dd in_test.dmb -invisible -trusted (in_index.dll next to the dmb). Results to world.log.

#define DLL "in_index.dll"

/world
	fps = 20

/datum/key
	var/n

var/failures = 0
var/list/answers

/proc/ms()
	return world.tick_usage * world.tick_lag

/proc/probe(label, list/L, list/keys)
	for(var/k in keys)
		answers += "[label] [k] [(k in L) ? 1 : 0]"

/proc/scenarios()
	answers = list()
	var/list/K = list("a", "b", "c", "d", "e", "x", "zz")
	var/list/L

	L = list(); L["a"] = 1; L["b"] = 2; L["c"] = 3
	probe("assoc", L, K)
	L = list("a", "b"); L["c"] = 3; L += "d"
	probe("mixed", L, K)
	L = list("a" = 1, "b" = 2, "c")
	probe("constructor", L, K)

	L = list(); L += "a"; L["a"] = 1; L += "a"
	probe("dup", L, K)
	L -= "a"
	probe("dup -1", L, K)
	L -= "a"
	probe("dup -2", L, K)
	L["a"] = 5
	probe("dup readd", L, K)

	L = list("a" = 1, "b" = 2, "c" = 3, "d" = 4)
	L.Cut(2, 3)
	probe("cut", L, K)
	L.Remove("c")
	probe("remove", L, K)
	L.Insert(1, "e")
	probe("insert", L, K)
	L.Swap(1, 2)
	probe("swap", L, K)
	L[1] = "x"
	probe("replace element", L, K)
	L.len = 1
	probe("len 1", L, K)
	L.len = 0
	probe("len 0", L, K)

	L = list("a" = 1, "b" = 2, "c" = 3)
	L -= list("a", "c")
	probe("minus list", L, K)
	L |= list("c", "d")
	probe("or list", L, K)
	L &= list("b", "d")
	probe("and list", L, K)
	L ^= list("b", "e")
	probe("xor list", L, K)
	L = list("a" = 1, "b" = 2) + list("c" = 3)
	probe("plus", L, K)
	var/list/C = L.Copy(2)
	probe("copy", C, K)
	L = list("a" = 1, "b" = 2, "c" = 3)
	L.Splice(2, 3, "x", "zz")
	probe("splice", L, K)
	L = list("a" = 1, "b" = 2, "c" = 3)
	L["b"] = null
	probe("assoc null", L, K)
	L = list("a" = "b")
	probe("value not key", L, K)

	// object keys, deleted keys and refs that come back
	var/list/objs = list()
	L = list()
	for(var/i in 1 to 50)
		var/datum/key/D = new
		D.n = i
		objs += D
		L[D] = i
	for(var/i in 1 to 50 step 2)
		var/datum/key/D = objs[i]
		objs[i] = null
		del(D)
	for(var/i in 1 to 50)
		var/datum/key/D = new
		D.n = 100 + i
		objs += D
	for(var/datum/key/D in objs)
		answers += "objs [D.n] [(D in L) ? 1 : 0]"
	answers += "objs len [length(L)]"

	// numbers in a list with associations
	L = list("a" = 1, 0, 1.5)
	answers += "num 0 [(0 in L) ? 1 : 0] -0 [(-0 in L) ? 1 : 0] 1.5 [(1.5 in L) ? 1 : 0] 2 [(2 in L) ? 1 : 0]"
	// a list as key
	var/list/inner = list(1)
	L = list(); L[inner] = 1
	answers += "list key [(inner in L) ? 1 : 0] [(list(1) in L) ? 1 : 0]"
	return answers

/proc/timings(label)
	var/list/L = list()
	for(var/i in 1 to 100000)
		L["k[i]"] = i
	sleep(1)
	var/t0 = ms()
	var/n = 0
	for(var/i in 1 to 200)
		if("k[100000 - i]" in L)
			n++
	var/hit_us = (ms() - t0) * 1e3 / 200
	sleep(1)
	t0 = ms()
	for(var/i in 1 to 200)
		if("nope[i]" in L)
			n++
	var/miss_us = (ms() - t0) * 1e3 / 200
	world.log << "[label]: 100,000 keys: hit [round(hit_us, 0.01)] us, miss [round(miss_us, 0.01)] us ([n])"

/world/New()
	..()
	spawn(10)
		world.log << "BYOND [world.byond_version].[world.byond_build]"
		var/list/want = scenarios()
		timings("engine")
		world.log << call_ext(DLL, "install")()
		var/list/got = scenarios()
		if(length(want) != length(got))
			failures++
			world.log << "FAIL: [length(want)] answers became [length(got)]"
		for(var/i in 1 to min(length(want), length(got)))
			if(want[i] != got[i])
				failures++
				world.log << "FAIL: [want[i]] became [got[i]]"
		world.log << "compared [length(want)] answers, [failures] differ"
		timings("index")
		world.log << call_ext(DLL, "stats")()
		world.log << call_ext(DLL, "uninstall")()
		world.log << "done, [failures] failures"
		del(world)
