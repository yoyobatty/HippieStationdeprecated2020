// Round start's two spikes, timed where they happen (2026-11-28): SSgarbage.Queue() and the first emissive_glow_state() of each
// icon sheet, from boot to a few minutes into a Bot Shift while the crew arrives, then one forced string-table rebuild for what
// a rebuild costs in this world. Not part of the game:
// AT_END=1 HARNESS=../string_probe/roundstart_probe.dm PARAMS="bot-shift=6&bot-crew=fill:40&bot-quiet=1&timewarp=0" SECONDS_LIMIT=480 bash tools/byond_reports/ref_stall/hippie_check.sh
// Results in data/ref_stall.txt:
//  - Queue() by stage (boot, lobby, play): calls, ms, how many of the queued datums had an id past every one before it (a
//    rising series of "\ref" text), and each call over RS_STALL_MS. BYOND's string tree rebuilds itself every ~982 strings kept
//    alive in sorted order (tools/byond_reports/sorted_strings), ~90-110 ms a rebuild in the game by the time the crew arrives.
//  - each icon sheet's first emissive_glow_state() (through build_worn_icon() and update_state_glow()), timed. Before
//    emissive_glow_sheets.dm that was icon_states() on a sheet the server hadn't loaded, which decodes the whole PNG. rs-compare=1
//    also finds each one's masks the old way and says whether they're the same; rs-compare-all=1 does that for every .dmi in the
//    game's folders at the end.
//  - with stress-bench=1&spike-log=1 in PARAMS, the bench's spike lines up to then (what ran in each tick over 60 ms).
//  - rs-repro=1: the Queue() stall on demand (rs_repro()), before the forced rebuild: 4000 new datums with ids past every one in
//    use, their "\ref" text kept as the old Queue() kept it, the same text kept in shuffled order, and qdel() through this
//    build's Queue().
// RS_QUIT_AFTER seconds into the round it writes everything and closes the world.

#define RS_STALL_MS 5
#define RS_QUIT_AFTER 200
#define RS_FILLER 300000

GLOBAL_LIST_EMPTY(rs_lines)
GLOBAL_LIST_EMPTY(rs_queue)
GLOBAL_LIST_EMPTY(rs_queue_stalls)
GLOBAL_LIST_EMPTY(rs_top_id)
GLOBAL_VAR_INIT(rs_since_stall, 0)
GLOBAL_LIST_EMPTY(rs_sheets)
GLOBAL_VAR_INIT(rs_sheet_ms, 0)
GLOBAL_LIST_EMPTY(rs_repro_kept)

/proc/rs_log(text)
	text2file(text, "data/ref_stall.txt")

/proc/rs_stage()
	if(!Master.current_runlevel)
		return "boot"
	if(!SSticker || SSticker.current_state < GAME_STATE_PLAYING)
		return "lobby"
	return "play"

/proc/rs_round_seconds()
	return SSticker?.round_start_time ? round((world.time - SSticker.round_start_time) / 10, 0.1) : 0

/datum/controller/subsystem/garbage/Queue(datum/D, level)
	if(isnull(D) || !GLOB.rs_queue) // qdels from global init, before these lists exist
		return ..()
	var/ref_text = "\ref[D]"
	var/kind = copytext(ref_text, 4, -7)
	var/id = text2num(copytext(ref_text, -7, -1), 16)
	var/t0 = TICK_USAGE_REAL
	. = ..()
	var/ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - t0)
	var/stage = rs_stage()
	var/list/stats = GLOB.rs_queue[stage]
	if(!stats)
		stats = GLOB.rs_queue[stage] = list("calls" = 0, "ms" = 0, "rising" = 0, "stalls" = 0, "stall_ms" = 0, "worst" = 0)
	stats["calls"]++
	stats["ms"] += ms
	stats["worst"] = max(stats["worst"], ms)
	var/rising = id > GLOB.rs_top_id[kind]
	if(rising)
		GLOB.rs_top_id[kind] = id
		stats["rising"]++
		GLOB.rs_since_stall++
	if(ms > RS_STALL_MS)
		stats["stalls"]++
		stats["stall_ms"] += ms
		GLOB.rs_queue_stalls += "[stage] [rs_round_seconds()]s: [round(ms, 0.1)] ms, [ref_text] [rising ? "past every id before it" : "under the highest id"], [GLOB.rs_since_stall] rising Queue() calls since the last stall"
		GLOB.rs_since_stall = 0

/// A sheet's first emissive_glow_state(), timed. With rs-compare=1 the sheet's masks are found the old way as well, by
/// icon_states() (which loads the sheet, so leave it off for timing), and set against what the proc found.
/proc/rs_glow_sheet(icon, state, via)
	if(!icon || !state || GLOB.emissive_glow_states[icon] || !GLOB.rs_lines)
		return
	var/t0 = TICK_USAGE_REAL
	emissive_glow_state(icon, state)
	var/ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - t0)
	GLOB.rs_sheet_ms += ms
	var/line = "[rs_stage()] [rs_round_seconds()]s tick [world.time] [icon] via [via]: emissive_glow_state() [round(ms, 0.01)] ms"
	if(world.params["rs-compare"])
		var/t1 = TICK_USAGE_REAL
		var/list/old = rs_old_masks(icon)
		line += ", the old way [round(TICK_DELTA_TO_MS(TICK_USAGE_REAL - t1), 0.01)] ms, [length(old)] masks, [rs_same(old, GLOB.emissive_glow_states[icon]) ? "same" : "DIFFERENT"]"
	GLOB.rs_sheets += line

/// What emissive_glow_state() found for a sheet before the build-time list: {state: mask} from icon_states()
/proc/rs_old_masks(icon)
	. = list()
	for(var/each in icon_states(icon))
		if(length(each) > 5 && copytext(each, -5) == "_glow")
			.[copytext(each, 1, -5)] = each

/proc/rs_same(list/a, list/b)
	if(length(a) != length(b))
		return FALSE
	for(var/key in a)
		if(a[key] != b[key])
			return FALSE
	return TRUE

/// rs-compare-all=1: every .dmi under the build list's folders, the build list's masks against icon_states()'s
/proc/rs_compare_all()
	var/lookup = text2path("/proc/emissive_glow_masks") // by name, so this file builds without emissive_glow_sheets.dm too
	if(!lookup || !("emissive_glow_sheet_roots" in GLOB.vars))
		rs_log("every sheet: this build has no emissive_glow_sheets.dm")
		return
	var/list/folders = list()
	for(var/root in GLOB.vars["emissive_glow_sheet_roots"])
		folders += root
	var/sheets = 0
	var/masks = 0
	var/list/different = list()
	while(length(folders))
		var/folder = folders[length(folders)]
		folders.len--
		for(var/name in flist(folder))
			if(copytext(name, -1) == "/")
				folders += "[folder][name]"
			else if(lowertext(copytext(name, -4)) == ".dmi")
				var/sheet = file("[folder][name]")
				var/list/old = rs_old_masks(sheet)
				sheets++
				masks += length(old)
				if(!rs_same(old, call(lookup)(sheet)))
					different += "[folder][name]"
		CHECK_TICK
	rs_log("every sheet: [sheets] .dmi files, [masks] masks by icon_states(), [length(different)] where the build list differs[length(different) ? ": [jointext(different, ", ")]" : ""]")

/obj/item/build_worn_icon(state = "", default_layer = 0, default_icon_file = null, isinhands = FALSE, femaleuniform = NO_FEMALE_UNIFORM)
	rs_glow_sheet((!isinhands && alternate_worn_icon) || default_icon_file, state, "worn [type]")
	return ..()

/atom/update_state_glow(list/extra)
	rs_glow_sheet(icon, icon_state, "state [type]")
	return ..()

/datum/rs_probe

/// rs-repro=1: the round-start stall on demand, with datums that stay alive (as the late-joining crew's new things do) and ids
/// past every one in use: RS_FILLER datums are made first, kept, to use up the ids freed earlier, whose "\ref" text may still
/// exist (an id given out again finds its text in the table already, and adds nothing to it). Each case times one line per datum:
///  - "kept": the datum's "\ref" text kept in a list, as Queue() kept it before (list(gctime, "\ref[D]")), in the order made
///  - "kept shuffled": the same text kept in shuffled order: as many strings, no sorted run
///  - "qdel": qdel() through this build's real SSgarbage.Queue()
/proc/rs_repro(mode)
	if(!length(GLOB.rs_repro_kept))
		for(var/i in 1 to RS_FILLER)
			GLOB.rs_repro_kept += new /datum/rs_probe
	var/list/made = list()
	for(var/i in 1 to 4000)
		made += new /datum/rs_probe
	var/list/ids = list()
	var/next_ones = 0
	for(var/i in 1 to length(made))
		ids += text2num(copytext("\ref[made[i]]", -7, -1), 16)
		if(i > 1 && ids[i] == ids[i - 1] + 1)
			next_ones++
	if(mode == "kept shuffled")
		for(var/i in length(made) to 2 step -1)
			made.Swap(i, rand(1, i))
	var/list/kept = list()
	var/total = 0
	var/stalls = 0
	var/stall_ms = 0
	var/worst = 0
	var/last = 0
	var/list/gaps = list()
	for(var/i in 1 to length(made))
		var/datum/D = made[i]
		var/t0 = TICK_USAGE_REAL
		if(mode == "qdel")
			qdel(D)
		else
			kept[++kept.len] = list(world.time, "\ref[D]")
		var/ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - t0)
		total += ms
		worst = max(worst, ms)
		if(ms > RS_STALL_MS)
			stalls++
			stall_ms += ms
			if(last)
				gaps += i - last
			last = i
	GLOB.rs_repro_kept += made
	GLOB.rs_repro_kept += kept
	rs_log("repro, [mode]: 4000 new datums after [RS_FILLER] kept ones, [next_ones] ids one past the last, [round(total)] ms, mean [round(total * 1000 / length(made), 0.1)] us, [stalls] over [RS_STALL_MS] ms costing [round(stall_ms)] ms, worst [round(worst, 0.1)] ms, gaps [jointext(gaps, " ")]")

/// Keeps 3000 rising strings alive, each timed: what one rebuild of the string tree costs now, and how far apart they come.
/proc/rs_forced()
	var/list/kept = list()
	var/total = 0
	var/stalls = 0
	var/stall_ms = 0
	var/worst = 0
	var/last = 0
	var/list/gaps = list()
	for(var/i in 1 to 3000)
		var/middle = num2text(i, 8, 16)
		var/t0 = TICK_USAGE_REAL
		var/text = "zzzz[middle]"
		var/ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - t0)
		kept += text
		total += ms
		worst = max(worst, ms)
		if(ms > RS_STALL_MS)
			stalls++
			stall_ms += ms
			if(last)
				gaps += i - last
			last = i
	rs_log("forced: 3000 rising strings kept, [round(total)] ms, [stalls] rebuilds averaging [round(stall_ms / max(stalls, 1), 0.1)] ms, worst [round(worst, 0.1)] ms, gaps [jointext(gaps, " ")]")

/proc/rs_run()
	UNTIL(SSticker?.initialized)
	UNTIL(SSticker.current_state >= GAME_STATE_PLAYING)
	UNTIL(rs_round_seconds() >= RS_QUIT_AFTER)
	rs_log("BYOND [world.byond_version].[world.byond_build], [world.fps] ticks, round [rs_round_seconds()] s in")
	for(var/stage in GLOB.rs_queue)
		var/list/stats = GLOB.rs_queue[stage]
		rs_log("Queue() in [stage]: [stats["calls"]] calls, [round(stats["ms"])] ms, [stats["rising"]] with a new highest id, [stats["stalls"]] over [RS_STALL_MS] ms costing [round(stats["stall_ms"])] ms, worst [round(stats["worst"], 0.1)] ms")
	for(var/line in GLOB.rs_queue_stalls)
		rs_log("  [line]")
	rs_log("emissive_glow_state() first calls: [length(GLOB.rs_sheets)] sheets, [round(GLOB.rs_sheet_ms)] ms in all")
	for(var/line in GLOB.rs_sheets)
		rs_log("  [line]")
	var/datum/stress_bench/bench = GLOB.stress_bench
	if(bench) // stress-bench=1&spike-log=1: its spike lines so far
		for(var/line in bench.lines)
			rs_log("bench: [line]")
	if(world.params["rs-repro"])
		for(var/mode in list("kept shuffled", "qdel", "kept"))
			rs_repro(mode)
			sleep(10)
	rs_forced()
	if(world.params["rs-compare-all"])
		rs_compare_all()
	rs_log("done")
	del(world)

/world/New()
	. = ..()
	spawn(0)
		rs_run()

#undef RS_STALL_MS
#undef RS_QUIT_AFTER
#undef RS_FILLER
