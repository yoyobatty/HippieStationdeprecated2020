// The same strings kept alive, made in sorted order and then in shuffled order. Stand-alone: dm sorted_strings.dm, then dd sorted_strings.dmb -invisible.
// Results go to world.log. Only the line that builds each string is timed.

#define TOTAL 300000
#define STALL_MS 1

/world
	fps = 20

/proc/make_strings(label, list/numbers)
	var/list/kept = new/list(TOTAL)
	var/total = 0
	var/stalls = 0
	var/stall_total = 0
	var/worst = 0
	var/last = 0
	var/gap = 0
	for(var/i in 1 to TOTAL)
		var/n = numbers[i]
		var/t0 = world.tick_usage
		var/text = "item [num2text(n, 8, 16)]"
		var/ms = (world.tick_usage - t0) * world.tick_lag
		kept[i] = text
		total += ms
		worst = max(worst, ms)
		if(ms > STALL_MS)
			stalls++
			stall_total += ms
			if(last)
				gap = i - last
			last = i
		if(!(i % 10000))
			sleep(1)
	world.log << "[label]: [round(total)] ms for [TOTAL] strings, mean [round(total * 1000 / TOTAL, 0.1)] us, [stalls] stalls over [STALL_MS] ms costing [round(stall_total)] ms, worst [round(worst, 0.1)] ms, last gap between stalls [gap] strings"

/proc/run_cases()
	world.log << "BYOND [world.byond_version].[world.byond_build]"
	var/list/numbers = new/list(TOTAL)
	for(var/i in 1 to TOTAL)
		numbers[i] = i
	make_strings("sorted", numbers)
	sleep(5)
	for(var/i in TOTAL to 2 step -1)
		numbers.Swap(i, rand(1, i))
	make_strings("shuffled", numbers)
	world.log << "done"
	del(world)

/world/New()
	. = ..()
	spawn(5)
		run_cases()
