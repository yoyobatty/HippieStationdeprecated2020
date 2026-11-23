// Test for string_hash.dll: timings before and after install, then correctness under churn, uninstall, reinstall.
// dm string_test.dm; dd string_test.dmb -invisible -trusted (string_hash.dll next to the dmb). Results to world.log.

#define DLL "string_hash.dll"
#define KEEP 200000

/world
	fps = 20

/proc/ms()
	return world.tick_usage * world.tick_lag

var/list/kept = list()
var/serial = 0
var/failures = 0

/proc/check(what, ok)
	if(!ok)
		failures++
		world.log << "FAIL: [what]"

// ascending strings that stay alive (the tree's worst case), then the same number made and dropped at once
/proc/timings(label)
	sleep(1)
	var/t0 = ms()
	for(var/i in 1 to 20000)
		serial++
		kept += "\[0x[num2text(serial + 33554432, 8, 16)]\]|thing|[serial]"
	var/kept_ns = (ms() - t0) * 1e6 / 20000
	sleep(1)
	t0 = ms()
	var/s
	for(var/i in 1 to 20000)
		serial++
		s = "08:[serial] gone again [i]"
	var/temp_ns = (ms() - t0) * 1e6 / 20000
	sleep(1)
	t0 = ms()
	var/hits = 0
	for(var/i in 1 to 20000) // building a string that already exists: found, not made
		s = "\[0x[num2text(33554432 + 1 + (i % 1000), 8, 16)]\]|thing|[1 + (i % 1000)]"
		hits += length(s)
	var/hit_ns = (ms() - t0) * 1e6 / 20000
	world.log << "[label]: [length(kept)] kept; new kept string [round(kept_ns)] ns, new string dropped at once [round(temp_ns)] ns, existing string [round(hit_ns)] ns[s && hits >= 0 ? "" : " "]"

/proc/correctness(label)
	// equal strings built different ways are the same string
	for(var/i in 1 to 2000)
		var/a = "k[i]_[i * 7]"
		var/b = "k" + num2text(i) + "_" + num2text(i * 7)
		check("[label] equal [a]", a == b)
		check("[label] differ [a]", a != "k[i]_[i * 7 + 1]")
	// keyed lists by strings made at different times
	var/list/L = list()
	for(var/i in 1 to 5000)
		L["key[i]"] = i
	for(var/i in 1 to 5000)
		check("[label] L key[i]", L["k" + "ey[i]"] == i)
	// churn: make and drop many strings, keep a few, check the kept ones are still right
	var/list/few = list()
	for(var/i in 1 to 50000)
		var/t = "churn [i] [label]"
		if(i % 997 == 0)
			few[t] = i
	for(var/t in few)
		check("[label] churn [t]", few[t] == text2num(splittext(t, " ")[2]))
	for(var/i in 1 to 100)
		var/k = kept[length(kept) - i + 1]
		check("[label] kept text", findtext(k, "|thing|") > 0)
	// text2path, findtext, replacetext, uppercase all intern their results
	check("[label] path", text2path("/datum") == /datum)
	check("[label] replace", replacetext("aXbXc", "X", "-") == "a-b-c")
	check("[label] upper", uppertext("abc") == "ABC")
	world.log << "[label]: correctness done, failures so far [failures]"

/world/New()
	..()
	spawn(10)
		world.log << "BYOND [world.byond_version].[world.byond_build]"
		timings("tree")
		timings("tree")
		correctness("tree")
		world.log << call_ext(DLL, "install")()
		timings("hash")
		timings("hash")
		correctness("hash")
		world.log << call_ext(DLL, "stats")()
		// drop most kept strings (release path), then make them again
		kept.Cut(1, length(kept) - 1000)
		correctness("hash after drop")
		timings("hash after drop")
		world.log << call_ext(DLL, "stats")()
		world.log << call_ext(DLL, "uninstall")()
		correctness("tree again")
		timings("tree again")
		world.log << call_ext(DLL, "install")()
		correctness("hash again")
		world.log << call_ext(DLL, "stats")()
		world.log << call_ext(DLL, "uninstall")()
		world.log << "done, [failures] failures"
		del(world)
