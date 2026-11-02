// Does "\ref" on a new datum that stays alive stall the server? Stand-alone, nothing else in the project.
// dm ref_stall.dm, then dd ref_stall.dmb -invisible. Results go to world.log and the world closes itself.
// Each case makes new datums and times only the line that builds a string. The controls build a unique string
// of the same length with no \ref, and take a \ref of a datum that's dropped straight away.

#define STALL_MS 5
#define PER_CASE 5000

/world
	fps = 20

/datum/probe
	var/n = 0

var/global/list/background = list()
var/global/list/kept = list()

/proc/ms_since(start)
	return (world.tick_usage - start) * world.tick_lag

/proc/report(label, count, total_ms, stalls, worst, gap_total, wall_start)
	var/wall_ms = (world.timeofday - wall_start) * 100
	var/gaps = stalls > 1 ? "one every [round(gap_total / (stalls - 1))] calls" : "no pattern"
	world.log << "[label], [length(background)] other datums alive: [count] calls, mean [round(total_ms * 1000 / count, 0.1)] us, [stalls] over [STALL_MS] ms, worst [round(worst, 0.1)] ms, [gaps], about [wall_ms] ms by the wall clock"

/proc/ref_kept()
	var/total = 0
	var/stalls = 0
	var/worst = 0
	var/last = 0
	var/gap_total = 0
	var/wall = world.timeofday
	for(var/i in 1 to PER_CASE)
		var/datum/probe/P = new
		var/start = world.tick_usage
		var/text = "\ref[P]"
		var/ms = ms_since(start)
		P.n = length(text)
		kept += P
		total += ms
		worst = max(worst, ms)
		if(ms > STALL_MS)
			if(stalls)
				gap_total += i - last
			last = i
			stalls++
	report("\\ref, datum kept alive", PER_CASE, total, stalls, worst, gap_total, wall)

/proc/ref_dropped()
	var/total = 0
	var/stalls = 0
	var/worst = 0
	var/last = 0
	var/gap_total = 0
	var/wall = world.timeofday
	for(var/i in 1 to PER_CASE)
		var/datum/probe/P = new
		var/start = world.tick_usage
		var/text = "\ref[P]"
		var/ms = ms_since(start)
		P.n = length(text)
		P = null
		total += ms
		worst = max(worst, ms)
		if(ms > STALL_MS)
			if(stalls)
				gap_total += i - last
			last = i
			stalls++
	report("\\ref, datum dropped straight away", PER_CASE, total, stalls, worst, gap_total, wall)

/proc/plain_text()
	var/total = 0
	var/stalls = 0
	var/worst = 0
	var/last = 0
	var/gap_total = 0
	var/wall = world.timeofday
	for(var/i in 1 to PER_CASE)
		var/datum/probe/P = new
		var/start = world.tick_usage
		var/text = "\[0x21[1000000 + world.time + i * 7]]"
		var/ms = ms_since(start)
		P.n = length(text)
		kept += P
		total += ms
		worst = max(worst, ms)
		if(ms > STALL_MS)
			if(stalls)
				gap_total += i - last
			last = i
			stalls++
	report("unique text, no \\ref, datum kept alive", PER_CASE, total, stalls, worst, gap_total, wall)

/proc/ref_again()
	var/total = 0
	var/stalls = 0
	var/worst = 0
	var/last = 0
	var/gap_total = 0
	var/wall = world.timeofday
	var/count = min(length(kept), PER_CASE)
	for(var/i in 1 to count)
		var/datum/probe/P = kept[i]
		var/start = world.tick_usage
		var/text = "\ref[P]"
		var/ms = ms_since(start)
		P.n = length(text)
		total += ms
		worst = max(worst, ms)
		if(ms > STALL_MS)
			if(stalls)
				gap_total += i - last
			last = i
			stalls++
	report("\\ref again of a kept datum", count, total, stalls, worst, gap_total, wall)

/proc/fill_background(upto)
	while(length(background) < upto)
		background += new /datum/probe
		if(!(length(background) % 10000))
			sleep(1)

/proc/run_cases()
	world.log << "BYOND [world.byond_version].[world.byond_build]"
	for(var/upto in list(0, 100000, 1000000))
		fill_background(upto)
		sleep(1)
		plain_text()
		sleep(1)
		ref_kept()
		sleep(1)
		ref_again()
		sleep(1)
		ref_dropped()
		sleep(1)
	world.log << "done"
	del(world)

/world/New()
	. = ..()
	spawn(5)
		run_cases()
