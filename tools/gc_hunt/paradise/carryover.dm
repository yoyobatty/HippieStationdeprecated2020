// Does what was found on HippieStation apply here? Local test, not part of any PR. EXTRA="carryover" tools/live_bench/run.sh <label>
// Results in data/live_bench/carryover.txt:
// - how big one rebuild of BYOND's string table is here, forced with 3000 sorted kept strings
// - new UID()s, which keep a string that rises with the datum's id: count, time, and how many hit a stall
// - shuttle transit docks and the grid check, each call timed
// - ticks the MC really finishes late, with what ran in them
// - for hard deletes, what still points at the thing

#define CO_STALL_MS 5
#define CO_LATE_KEEP 80
#define CO_MAX_SEARCHES 8
#define CO_MAX_HITS 8

var/global/list/co_uid = list("calls" = 0, "ms" = 0, "stalls" = 0, "stall_ms" = 0, "worst" = 0)
var/global/list/co_tick = list()
var/global/list/co_late = list()
var/global/co_ticks = 0
var/global/co_late_count = 0
var/global/co_late_ms = 0
var/global/co_searches = 0
var/global/co_playing = FALSE
var/global/list/co_skip = list("vars" = TRUE, "verbs" = TRUE, "overlays" = TRUE, "underlays" = TRUE, "type" = TRUE, "parent_type" = TRUE, "tag" = TRUE, "vis_locs" = TRUE)

/proc/co_log(text)
	text2file(text, "data/live_bench/[world.params["live-round"]]_co.txt")

/// co-ticklag=<n>: the tick rate the config would ask for, the way a server owner would change it.
/datum/configuration_section/mc_configuration/load_data(list/data)
	. = ..()
	if("co-ticklag" in world.params)
		ticklag = text2num(world.params["co-ticklag"])

/datum/UID()
	if(unique_datum_id)
		return ..()
	var/t0 = world.tick_usage
	. = ..()
	var/ms = (world.tick_usage - t0) * world.tick_lag
	var/list/stats = co_uid
	stats["calls"]++
	stats["ms"] += ms
	stats["worst"] = max(stats["worst"], ms)
	if(ms > CO_STALL_MS)
		stats["stalls"]++
		stats["stall_ms"] += ms

/proc/co_uid_text()
	var/list/stats = co_uid
	return "[stats["calls"]] new UIDs, [round(stats["ms"])] ms, [round(stats["ms"] * 1000 / max(stats["calls"], 1), 0.1)] us each, [stats["stalls"]] over [CO_STALL_MS] ms costing [round(stats["stall_ms"])] ms, worst [round(stats["worst"], 0.1)] ms"

/// Keeps 3000 ascending strings, each timed, to see one rebuild's size in this world.
/proc/co_forced()
	var/total = 0
	var/stalls = 0
	var/stall_ms = 0
	var/worst = 0
	var/last = 0
	var/list/gaps = list()
	var/list/kept = list()
	for(var/i in 1 to 3000)
		var/middle = num2text(i, 8, 16)
		var/t0 = world.tick_usage
		var/text = "zzzz[middle]"
		var/ms = (world.tick_usage - t0) * world.tick_lag
		kept += text
		total += ms
		worst = max(worst, ms)
		if(ms > CO_STALL_MS)
			stalls++
			stall_ms += ms
			if(last)
				gaps += i - last
			last = i
	co_log("forced: 3000 kept ascending strings, [round(total)] ms, mean [round(total * 1000 / 3000, 0.1)] us, [stalls] rebuilds averaging [round(stall_ms / max(stalls, 1), 0.1)] ms, worst [round(worst, 0.1)] ms, gaps [jointext(gaps, " ")]")

/datum/controller/master/RunQueue()
	. = ..()
	if(!co_playing)
		return
	co_ticks++
	var/usage = TICK_USAGE
	if(usage > 100)
		co_late_count++
		co_late_ms += (usage - 100) * world.tick_lag
		if(length(co_late) < CO_LATE_KEEP)
			co_late += "[round(world.time / 10)]s [round(usage)]% over by [round((usage - 100) * world.tick_lag, 0.1)] ms: [jointext(co_tick, ", ")]"
	co_tick.Cut()

/datum/controller/subsystem/ignite(resumed = FALSE)
	set waitfor = FALSE
	var/t0 = world.tick_usage
	var/time0 = world.time
	. = ..()
	if(co_playing && world.time == time0)
		var/ms = (world.tick_usage - t0) * world.tick_lag
		if(ms >= 3)
			co_tick += "[name] [round(ms, 0.1)]"

/datum/controller/subsystem/shuttle/generate_transit_dock(obj/docking_port/mobile/M)
	var/t0 = world.tick_usage
	var/time0 = world.time
	. = ..()
	co_log("transit dock for [M]: [world.time == time0 ? "[round((world.tick_usage - t0) * world.tick_lag, 0.1)] ms in one go" : "spread over [round((world.time - time0) / world.tick_lag)] ticks"]")

/// co-spread=1: Hippie's fix, the same loop with a tick check after each APC.
/datum/event/grid_check/proc/co_spread_power(state = TRUE)
	var/list/skipped_areas_apc = list(
		/area/station/turret_protected/ai,
		/area/station/command/office/ce)
	skipped_areas_apc += subtypesof(/area/station/engineering)
	skipped_areas_apc += subtypesof(/area/station/telecomms)
	for(var/obj/machinery/power/apc/power_controller in GLOB.apcs)
		var/area/current_area = get_area(power_controller)
		if((current_area.type in skipped_areas_apc) || !is_station_level(power_controller.z))
			continue
		if(power_controller.operating == state)
			power_controller.toggle_breaker()
			CHECK_TICK

/datum/event/grid_check/toggle_power(state = TRUE)
	var/t0 = world.tick_usage
	var/time0 = world.time
	if("co-spread" in world.params)
		co_spread_power(state)
	else
		. = ..()
	co_log("grid check toggle_power([state]): [world.time == time0 ? "[round((world.tick_usage - t0) * world.tick_lag, 0.1)] ms in one go" : "spread over [round((world.time - time0) / world.tick_lag)] ticks"]")

/proc/co_note(list/hits, text)
	if(length(hits) < CO_MAX_HITS)
		hits += text

/proc/co_list(list/L, label, datum/D, list/hits, depth)
	if(depth > 4)
		return
	var/place = 0
	for(var/item in L)
		place++
		if(item == D)
			co_note(hits, "[label]\[[place]]")
		else if(islist(item))
			co_list(item, "[label]\[[place]]", D, hits, depth + 1)
		if(!isnum(item) && !isnull(item))
			var/value
			try
				value = L[item]
			catch
				continue
			if(value == D)
				co_note(hits, "[label]\[[item]] (value)")
			else if(islist(value))
				co_list(value, "[label]\[[item]]", D, hits, depth + 1)

/proc/co_scan(datum/thing, label, datum/D, list/hits)
	var/skip_contents = isarea(thing)
	var/list/own = thing.vars
	for(var/name in own)
		if(co_skip[name] || (skip_contents && name == "contents"))
			continue
		var/value = own[name]
		if(value == D)
			co_note(hits, "[label].[name]")
		else if(islist(value))
			co_list(value, "[label].[name]", D, hits, 1)

/proc/co_find(datum/D)
	var/started = world.timeofday
	var/list/hits = list()
	var/references = refcount(D)
	co_scan(GLOB, "GLOB", D, hits)
	for(var/turf/T in world)
		if(length(T.vis_contents) && (D in T.vis_contents))
			co_note(hits, "[T.type].vis_contents")
	for(var/datum/thing in world)
		if(!isturf(thing))
			co_scan(thing, "[thing.type]", D, hits)
	for(var/datum/thing)
		co_scan(thing, "[thing.type]", D, hits)
	for(var/client/C)
		co_scan(C, "client", D, hits)
	co_log("[D.type]: refcount [references], [length(hits)] found in [(world.timeofday - started) / 10]s")
	for(var/hit in hits)
		co_log("    [hit]")

/datum/controller/subsystem/garbage/HardDelete(datum/D)
	if(co_searches < CO_MAX_SEARCHES)
		co_searches++
		try
			co_find(D)
		catch(var/exception/E)
			co_log("[D.type]: the search failed: [E] at [E.file]:[E.line]")
	else
		co_log("[D.type] hard deleted, no search")
	return ..()

/proc/co_run()
	UNTIL(SSticker && SSticker.initialized)
	UNTIL(SSticker.current_state >= GAME_STATE_PLAYING)
	co_log("BYOND [world.byond_version].[world.byond_build], [world.fps] ticks, [world.maxx] x [world.maxy] x [world.maxz]")
	co_log("through boot: [co_uid_text()]")
	co_playing = TRUE
	sleep(100)
	co_forced()
	var/minutes = 0
	while(TRUE)
		sleep(600)
		minutes++
		if(minutes == 1 && SSshuttle.supply)
			var/obj/docking_port/stationary/transit/forced = SSshuttle.generate_transit_dock(SSshuttle.supply)
			co_log("forced a transit dock: [forced]")
			qdel(forced)
			if("co-quick" in world.params)
				sleep(50)
				co_log("done")
				del(world)
		co_log("[minutes] minutes in: [co_uid_text()], [co_ticks] ticks, [co_late_count] late, [round(co_late_ms)] ms over")
		if(minutes == 5)
			for(var/line in co_late)
				co_log(line)

/world/New()
	. = ..()
	spawn(0)
		co_run()
