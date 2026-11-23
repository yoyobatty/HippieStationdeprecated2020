// Test for sleep_queue.dll: the order sleeping procs wake in, engine against DLL, for the same seeded run; then the
// cost of one spawn() against how many procs already sleep.
// dm sleep_test.dm; dd sleep_test.dmb -invisible -trusted (sleep_queue.dll next to the dmb). Results to world.log.

#define DLL "sleep_queue.dll"

/world
	fps = 20

var/list/woke
var/failures = 0
var/released = 0

/proc/ms()
	return world.tick_usage * world.tick_lag

/proc/sleeper(id, ds)
	set waitfor = FALSE
	sleep(ds)
	woke += id
	if(id % 7 == 0) // some sleep again from inside the wake-up pass
		sleep(rand(0, 5))
		woke += -id

/proc/order_run()
	rand_seed(777)
	woke = list()
	for(var/i in 1 to 6000)
		sleeper(i, rand(0, 40))
		if(i % 500 == 0)
			sleep(world.tick_lag)
	sleep(60)
	return woke

/proc/parked()
	set waitfor = FALSE
	while(!released)
		sleep(36000)

/proc/one()
	set waitfor = FALSE
	sleep(rand(1, 2000))

/proc/timings(label)
	released = 0
	var/have = 0
	for(var/n in list(10, 1000, 20000))
		while(have < n)
			parked()
			have++
		sleep(1)
		var/t0 = ms()
		for(var/i in 1 to 2000)
			one()
		world.log << "[label]: [n] sleepers: spawn one more [round((ms() - t0) * 1e6 / 2000)] ns"
	released = 1

/world/New()
	..()
	spawn(10)
		world.log << "BYOND [world.byond_version].[world.byond_build]"
		var/list/want = order_run()
		timings("engine")
		world.log << call_ext(DLL, "install")()
		var/list/got = order_run()
		if(length(want) != length(got))
			failures++
			world.log << "FAIL: [length(want)] wake-ups became [length(got)]"
		for(var/i in 1 to min(length(want), length(got)))
			if(want[i] != got[i])
				failures++
				if(failures < 10)
					world.log << "FAIL: wake-up [i] was [want[i]], now [got[i]]"
		world.log << "compared [length(want)] wake-ups, [failures] differ"
		timings("memmove")
		world.log << call_ext(DLL, "stats")()
		world.log << call_ext(DLL, "uninstall")()
		timings("engine again")
		world.log << "done, [failures] failures"
		del(world)
