// ref_stall.dm finds no stall in a tiny world, so this is the same measurement inside the game after a normal boot: does it need
// something the game has? Not part of the game: tools/byond_reports/ref_stall/hippie_check.sh

#define RP_STALL_MS 5
#define RP_PER_CASE 5000

/datum/controller/master
	sleep_offline_after_initializations = FALSE

/datum/ref_probe
	var/n = 0

GLOBAL_LIST_EMPTY(ref_probe_kept)

/proc/rp_log(text)
	text2file(text, "data/ref_stall.txt")

/proc/rp_ms(start)
	return (world.tick_usage - start) * world.tick_lag

/proc/rp_report(label, total, stalls, worst, list/where)
	rp_log("[label]: [RP_PER_CASE] calls, mean [round(total * 1000 / RP_PER_CASE, 0.1)] us, [stalls] over [RP_STALL_MS] ms, worst [round(worst, 0.1)] ms, at [jointext(where, " ")]")

/proc/rp_case(label, mode)
	var/total = 0
	var/stalls = 0
	var/worst = 0
	var/list/where = list()
	for(var/i in 1 to RP_PER_CASE)
		var/datum/ref_probe/P = mode == 3 ? GLOB.ref_probe_kept[i] : new
		var/text
		var/start = world.tick_usage
		if(mode == 0)
			text = "\[0x21[1000000 + world.time + i * 7]]"
		else
			text = "\ref[P]"
		var/ms = rp_ms(start)
		P.n = length(text)
		if(mode == 0 || mode == 1)
			GLOB.ref_probe_kept += P
		total += ms
		worst = max(worst, ms)
		if(ms > RP_STALL_MS)
			stalls++
			if(length(where) < 12)
				where += "[i]=[round(ms)]ms"
	rp_report(label, total, stalls, worst, where)

/proc/ref_probe_run()
	UNTIL(SSticker.initialized)
	SSticker.timeLeft = -1
	sleep(100)
	var/atoms = 0
	for(var/atom/A in world)
		atoms++
	rp_log("BYOND [world.byond_version].[world.byond_build], [world.fps] ticks, [world.maxx] x [world.maxy] x [world.maxz], [atoms] atoms")
	for(var/pass in 1 to 2)
		rp_log("pass [pass]")
		rp_case("unique text, no \\ref, datum kept alive", 0)
		sleep(5)
		rp_case("\\ref, datum kept alive", 1)
		sleep(5)
		rp_case("\\ref again of a kept datum", 3)
		sleep(5)
		rp_case("\\ref, datum dropped straight away", 2)
		sleep(5)
	rp_log("done")
	del(world)

/world/New()
	. = ..()
	spawn(0)
		ref_probe_run()
