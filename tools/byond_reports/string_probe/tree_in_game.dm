// What BYOND's string tree costs the game: a forced rebuild's size, SSgarbage.Queue() through boot and play, and subsystem spikes in a bot shift.
// Not part of the game. HARNESS=../string_probe/tree_in_game.dm PARAMS="bot-shift=20&bot-crew=fill:20&bot-events=1&bot-quiet=1&timewarp=0" bash tools/byond_reports/ref_stall/hippie_check.sh

#define TI_STALL_MS 5
#define TI_SPIKE_MS 25

GLOBAL_LIST_INIT(ti_queue, list("calls" = 0, "ms" = 0, "stalls" = 0, "stall_ms" = 0, "worst" = 0))
GLOBAL_LIST_EMPTY(ti_spikes)
GLOBAL_LIST_EMPTY(ti_kept)

/proc/ti_log(text)
	text2file(text, "data/ref_stall.txt")

/datum/controller/subsystem/garbage/Queue(datum/D, level)
	var/t0 = world.tick_usage
	. = ..()
	var/ms = (world.tick_usage - t0) * world.tick_lag
	var/list/stats = GLOB.ti_queue
	if(!stats) // qdels from global init, before this list exists
		return
	stats["calls"]++
	stats["ms"] += ms
	stats["worst"] = max(stats["worst"], ms)
	if(ms > TI_STALL_MS)
		stats["stalls"]++
		stats["stall_ms"] += ms

/datum/controller/subsystem/ignite(resumed = FALSE)
	set waitfor = FALSE
	var/t0 = world.tick_usage
	var/time0 = world.time
	. = ..()
	if(world.time == time0)
		var/ms = (world.tick_usage - t0) * world.tick_lag
		if(ms > TI_SPIKE_MS)
			GLOB.ti_spikes += "[round(world.time / 10)]s [name] [round(ms)]ms"

/proc/ti_queue_text()
	var/list/stats = GLOB.ti_queue
	return "[stats["calls"]] Queue() calls, [round(stats["ms"])] ms, [round(stats["ms"] * 1000 / max(stats["calls"], 1), 0.1)] us each, [stats["stalls"]] over [TI_STALL_MS] ms costing [round(stats["stall_ms"])] ms, worst [round(stats["worst"], 0.1)] ms"

/// Keeps 3000 ascending strings, each timed, to see one rebuild's size in this world.
/proc/ti_forced()
	var/total = 0
	var/stalls = 0
	var/stall_ms = 0
	var/worst = 0
	var/last = 0
	var/list/gaps = list()
	for(var/i in 1 to 3000)
		var/middle = num2text(i, 8, 16)
		var/t0 = world.tick_usage
		var/text = "zzzz[middle]"
		var/ms = (world.tick_usage - t0) * world.tick_lag
		GLOB.ti_kept += text
		total += ms
		worst = max(worst, ms)
		if(ms > TI_STALL_MS)
			stalls++
			stall_ms += ms
			if(last)
				gaps += i - last
			last = i
	ti_log("forced: 3000 kept ascending strings, [round(total)] ms, mean [round(total * 1000 / 3000, 0.1)] us, [stalls] rebuilds averaging [round(stall_ms / max(stalls, 1), 0.1)] ms, worst [round(worst, 0.1)] ms, gaps [jointext(gaps, " ")]")

/proc/ti_run()
	UNTIL(SSticker.initialized)
	UNTIL(SSticker.current_state >= GAME_STATE_PLAYING)
	ti_log("BYOND [world.byond_version].[world.byond_build], [world.fps] ticks")
	ti_log("through boot: [ti_queue_text()]")
	sleep(50)
	ti_forced()
	var/list/at_start = GLOB.ti_queue.Copy()
	var/minutes = 0
	while(TRUE)
		sleep(600)
		minutes++
		if(!(minutes % 5))
			ti_log("[minutes] minutes in: [ti_queue_text()], [length(GLOB.ti_spikes)] spikes over [TI_SPIKE_MS] ms so far (boot and play)")
			ti_log("spikes: [jointext(GLOB.ti_spikes, ", ")]")
			ti_log("since the round began: [GLOB.ti_queue["calls"] - at_start["calls"]] calls, [round(GLOB.ti_queue["ms"] - at_start["ms"])] ms, [GLOB.ti_queue["stalls"] - at_start["stalls"]] stalls")

/world/New()
	. = ..()
	spawn(0)
		ti_run()
