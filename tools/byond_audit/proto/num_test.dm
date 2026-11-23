// Test for numfmt.dll: number-to-text timed before and after install, and all text compared with the engine's own.
// dm num_test.dm; dd num_test.dmb -invisible -trusted (numfmt.dll next to the dmb). Results to world.log.

#define DLL "numfmt.dll"
#define PASSES 100000

/world
	fps = 20

var/failures = 0

/proc/ms()
	return world.tick_usage * world.tick_lag

/proc/numbers()
	. = list(0, -0, 1, -1, 0.5, 0.1, 0.0001, 0.00001, 123456, 999999, 999999.5, 1000000, 16777215, 16777216, 16777217,
		-16777216, 1e20, -1e-20, 3.14159265, 2.5, 0.125, 1.5e-4, 65535.99, 1/3, 2/3, -7/9)
	for(var/i in 1 to 4000)
		. += i
		. += -i * 17
		. += i / 7
		. += -i / 3
		. += i * 0.001
		. += i * 1.37e-5
		. += i * 251.3
		. += i * i * 1.01

/proc/render(list/L)
	. = list()
	for(var/x in L)
		. += "[x]"
		. += num2text(x)
		. += num2text(x, 3)
		. += num2text(x, 12)
		. += "a[x]b"

/proc/timings(label)
	sleep(1)
	var/s
	var/t0 = ms()
	for(var/i in 1 to PASSES)
		s = "[i]"
	var/int_ns = (ms() - t0) * 1e6 / PASSES
	sleep(1)
	t0 = ms()
	for(var/i in 1 to PASSES)
		s = "[i / 7]"
	var/frac_ns = (ms() - t0) * 1e6 / PASSES
	sleep(1)
	t0 = ms()
	for(var/i in 1 to PASSES)
		s = num2text(i / 7)
	var/n2t_ns = (ms() - t0) * 1e6 / PASSES
	world.log << "[label]: \"\[i]\" [round(int_ns)] ns, \"\[i / 7]\" [round(frac_ns)] ns, num2text(i / 7) [round(n2t_ns)] ns[s ? "" : " "]"

/world/New()
	..()
	spawn(10)
		world.log << "BYOND [world.byond_version].[world.byond_build]"
		var/list/nums = numbers()
		var/list/want = render(nums)
		timings("engine")
		timings("engine")
		world.log << call_ext(DLL, "install")()
		var/list/got = render(nums)
		for(var/i in 1 to length(want))
			if(want[i] != got[i])
				failures++
				if(failures < 20)
					world.log << "FAIL: [want[i]] became [got[i]]"
		world.log << "compared [length(want)] texts, [failures] differ"
		timings("fast")
		timings("fast")
		world.log << call_ext(DLL, "stats")()
		world.log << call_ext(DLL, "uninstall")()
		timings("engine again")
		world.log << "done, [failures] failures"
		del(world)
