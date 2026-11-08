// The CPU stress bench (stress-bench=1 on a Bot Shift; tools/bot_gym/run_stress_bench.sh <label> [runs]): the worst a round gets, the
// same way every run, to measure what the server costs and whether a change made it any cheaper. The run script brings 40 bot crew, two
// traitors and random events; this adds a fixed list of disasters at set times on top, each its own phase (see `schedule`):
//   crew arriving, calm, aurora, grid check, rad storm, plasma fire, hull breaches, meteors, maxcap, tesla (taken away when the aftermath
//   starts), aftermath
// They stack: the fire still burns through the breaches, the station stays holed for the tesla.
// stress-calm=1 runs an ordinary shift of the same length instead, no disasters, as four calm phases.
// Every bot counts as a player for what waits until a player is near (SSlighting.test_eyes), where a plain Bot Shift counts one.
// Spots are picked from a fixed seed before the crew arrives, so they're the same every run (and so is the crew's first roll of jobs).
//
// Each phase records
//  - every tick's real length on timewarp's clock: with the wait skipped, that's everything the server did that tick, in the MC or not
//  - what each subsystem cost (exact: /datum/controller/subsystem/var/total_ms) and how often it fired, since one that falls behind
//    fires less and would look cheaper
//  - what the station is like at its end (tiles changed, fires, air, deaths, lights waiting), to tell a faster build from one doing less
// Results: <bot-results>stress.txt and stress.json (data/stress_bench/ without bot-results). Compare builds with
// tools/bot_gym/stress_report.py. The bots' own thinking can't be timed from here (pathfinding sleeps mid-search): profile a run
// (PROFILE=1) and read it with tools/bot_gym/shift_profile.py for that split.

#define STRESS_BENCH_SEED 1337
/// How many bots count as players watching
#define STRESS_BENCH_EYES 40
/// A tick that took longer than this was over budget at 40 ticks a second: the game slowed down
#define STRESS_BENCH_BUDGET_MS 25

GLOBAL_DATUM(stress_bench, /datum/stress_bench)

/datum/stress_phase
	var/name
	/// world.time it began
	var/started_at
	/// Game time it lasted, deciseconds
	var/game_ds = 0
	/// Real time of the ticks in it, ms
	var/real_ms = 0
	var/list/tick_ms = list()
	var/worst_ms = 0
	/// Deciseconds into the phase the worst tick came
	var/worst_at = 0
	var/over_budget = 0
	var/over_100 = 0
	/// Subsystem name -> its total_ms as the phase began, then what the phase added
	var/list/ss_ms = list()
	/// Subsystem name -> times_fired as the phase began, then how many times it fired in the phase
	var/list/ss_fired = list()
	/// What the station was like at the end, see /datum/stress_bench/proc/survey()
	var/list/state
	/// SSair's stages (SSair.stage_ms) and the tile engine's packing, native and follow-up time: totals as the phase began, then
	/// what the phase added
	var/list/atmos_ms = list()

/datum/stress_phase/proc/add_tick(gap)
	real_ms += gap
	tick_ms += gap
	if(gap > worst_ms)
		worst_ms = gap
		worst_at = world.time - started_at
	if(gap > STRESS_BENCH_BUDGET_MS)
		over_budget++
	if(gap > 100)
		over_100++

/datum/stress_phase/proc/seconds()
	return max(game_ds / 10, 0.1)

/datum/stress_phase/proc/percentile(fraction)
	if(!length(tick_ms))
		return 0
	var/list/sorted = sortTim(tick_ms.Copy(), GLOBAL_PROC_REF(cmp_numeric_asc))
	return sorted[clamp(round(length(sorted) * fraction), 1, length(sorted))]

/datum/stress_phase/proc/mc_ms()
	. = 0
	for(var/name in ss_ms)
		. += ss_ms[name]

/datum/stress_phase/proc/line()
	var/seconds = seconds()
	var/list/top = ss_ms.Copy()
	sortTim(top, GLOBAL_PROC_REF(cmp_numeric_dsc), associative = TRUE)
	var/list/parts = list()
	for(var/name in top)
		if(length(parts) >= 8 || top[name] / seconds < 0.1)
			break
		parts += "[name] [round(top[name] / seconds, 0.1)]"
	return "[pad(name, 14)] [pad(bot_shift_duration(game_ds), 7)] real [pad(round(real_ms / seconds, 0.1), 6)] ms/s (MC [round(mc_ms() / seconds, 0.1)], \
		outside [round((real_ms - mc_ms()) / seconds, 0.1)]); ticks worst [round(worst_ms)] ms at +[round(worst_at / 10)]s, p99 [round(percentile(0.99), 0.1)], \
		[over_budget] over [STRESS_BENCH_BUDGET_MS] ms, [over_100] over 100 | [jointext(parts, ", ")]"

/datum/stress_phase/proc/pad(text, width)
	text = "[text]"
	while(length(text) < width)
		text += " "
	return text

/datum/stress_phase/proc/to_list()
	return list("name" = name, "seconds" = seconds(), "real_ms" = real_ms, "ticks" = length(tick_ms), "worst_ms" = worst_ms, "worst_at" = worst_at / 10,
		"p99" = percentile(0.99), "p999" = percentile(0.999), "over_budget" = over_budget, "over_100" = over_100, "mc_ms" = mc_ms(),
		"ss_ms" = ss_ms, "ss_fired" = ss_fired, "state" = state, "atmos_ms" = atmos_ms)

/datum/stress_bench
	var/datum/bot_shift/shift
	/// Phase name -> seconds into the shift it starts at, in order. "end" closes the last one.
	var/list/schedule = list(
		"crew arriving" = 0,
		"calm" = 150,
		"aurora" = 270,
		"grid check" = 390,
		"rad storm" = 510,
		"plasma fire" = 630,
		"hull breaches" = 750,
		"meteors" = 870,
		"maxcap" = 1020,
		"tesla" = 1140,
		"aftermath" = 1380,
		"end" = 1560
	)
	var/list/datum/stress_phase/phases = list()
	var/datum/stress_phase/current
	var/z
	var/turf/open/floor/fire_spot
	var/list/turf/closed/wall/breach_walls = list()
	var/turf/open/floor/boom_spot
	var/turf/open/floor/tesla_spot
	var/obj/singularity/energy_ball/ball
	/// GLOB.station_turfs as the bench began, and their types in the same order
	var/list/turf/station_turfs_start
	var/list/station_types_start
	var/list/lines = list()
	var/next_eyes = 0
	/// light-tally=1: why light sources worked their light out, and what it cost: "<why> <what>" -> count, and -> ms
	var/list/light_tally
	var/list/light_ms
	/// light-shadow=1: the old and new tests for which waiting lights somebody can see, set against each other (see update_eyes() below)
	var/list/light_shadow

/datum/stress_bench/New(datum/bot_shift/shift)
	src.shift = shift
	shift.length = max(shift.length, (schedule["end"] + 30) SECONDS)
	if(world.params["light-tally"])
		light_tally = list()
		light_ms = list()
	if(world.params["light-shadow"])
		light_shadow = list("checked" = 0, "taken out" = 0, "old only" = 0, "new only" = 0)

// light-tally=1: every light update, by why it ran and what the light is on. Only while the bench runs with it.
/datum/light_source/update_corners()
	var/datum/stress_bench/B = GLOB.stress_bench
	if(!B?.light_tally || B.shift.elapsed() < B.schedule["calm"] SECONDS)
		return ..()
	var/why
	switch(needs_update)
		if(LIGHTING_VIS_UPDATE)
			why = "door/opacity"
		if(LIGHTING_FORCE_UPDATE)
			why = "forced"
		else
			var/atom/top = top_atom || source_atom
			why = ((isturf(top) ? top : top?.loc) != source_turf) ? "moved" : "changed"
	var/what
	if(isturf(source_atom))
		what = "turf ([source_atom.type])"
	else if(top_atom && top_atom != source_atom)
		what = "carried by [ismob(top_atom) ? "a mob" : "[top_atom.type]"] ([source_atom?.type])"
	else
		what = "[source_atom?.type]"
	var/key = "[why] [what]"
	var/start = TICK_USAGE_REAL
	. = ..()
	var/took = TICK_USAGE_REAL - start
	B.light_tally[key] += 1
	B.light_ms[key] += took > 0 ? TICK_DELTA_TO_MS(took) : 0

// light-shadow=1: every time SSlighting looks where the players are, works out which waiting lights the old test (each light near an
// eye against every eye, with can_wait_unseen()) would have taken out of waiting, and counts any that the real one didn't, or the other
// way round. The two should always agree.
/datum/controller/subsystem/lighting/update_eyes()
	var/datum/stress_bench/B = GLOB.stress_bench
	if(!B?.light_shadow || !defer_unseen)
		return ..()
	var/list/waiting = list()
	var/list/waiting_at = list()
	for(var/cell in unseen_cells)
		for(var/datum/light_source/L as anything in unseen_cells[cell])
			waiting += L
			waiting_at += L.unseen_at
	. = ..()
	for(var/i in 1 to length(waiting))
		var/datum/light_source/L = waiting[i]
		var/turf/at = waiting_at[i]
		var/new_back = !L.unseen_cell
		var/scanned = FALSE
		for(var/turf/eye as anything in eyes)
			var/range = eyes[eye] + LIGHTING_UNSEEN_MARGIN + LIGHTING_UNSEEN_MAX_REACH
			if(eye.z == at.z && abs(LIGHTING_UNSEEN_CELL_OF(at.x) - LIGHTING_UNSEEN_CELL_OF(clamp(at.x, eye.x - range, eye.x + range))) == 0 \
				&& abs(LIGHTING_UNSEEN_CELL_OF(at.y) - LIGHTING_UNSEEN_CELL_OF(clamp(at.y, eye.y - range, eye.y + range))) == 0)
				scanned = TRUE
				break
		var/old_back = scanned && !L.can_wait_unseen(eyes)
		B.light_shadow["checked"]++
		if(new_back)
			B.light_shadow["taken out"]++
		if(old_back != new_back)
			B.light_shadow[old_back ? "old only" : "new only"]++

/datum/bot_shift/proc/stress_bench()
	GLOB.stress_bench = new /datum/stress_bench(src)
	GLOB.stress_bench.go()

/datum/stress_bench/proc/go()
	if(world.params["stress-calm"]) // an ordinary shift instead: no disasters, the same length, in four parts so any drift shows
		schedule = list("crew arriving" = 0, "calm 1" = 150, "calm 2" = 500, "calm 3" = 850, "calm 4" = 1200, "end" = 1560)
	z = SSmapping.levels_by_trait(ZTRAIT_STATION)[1]
	pick_spots()
	station_turfs_start = GLOB.station_turfs.Copy()
	station_types_start = list()
	for(var/turf/T as anything in station_turfs_start)
		station_types_start += T.type
	var/list/names = list()
	for(var/name in schedule)
		names += name
	var/next = 1
	var/last = timewarp_real_ms()
	var/spike_log = world.params["spike-log"] // spike-log=1: what each tick over 60 ms went on, by subsystem
	if(world.params["reconcile-check"]) // reconcile-check=1: every pipeline's sharing out of its gas against the old way's
		GLOB.reconcile_check = list("same" = 0, "different" = 0)
	if(world.params["tesla-zap-check"]) // tesla-zap-check=1: every tesla zap's choice against the old loop's
		GLOB.tesla_zap_check = list("same" = 0, "different" = 0)
	if(world.params["timer-census"]) // timer-census=1: what the Timer subsystem's time goes on, by the timers' procs
		SStimer.census = list()
		SStimer.census_count = list()
	var/list/ss_before
	var/list/air_before
	while(next <= length(names))
		var/name = names[next]
		if(shift.elapsed() >= schedule[name] SECONDS)
			next++
			if(current)
				close_phase()
			if(name == "end")
				break
			start_phase(name)
			last = timewarp_real_ms() // what the survey took isn't counted, what setting the disaster off takes is
			set_off(name)
			continue
		if(spike_log)
			ss_before = list()
			for(var/datum/controller/subsystem/SS as anything in Master.subsystems)
				ss_before += SS.total_ms
			air_before = atmos_totals()
		sleep(world.tick_lag)
		var/now = timewarp_real_ms()
		current?.add_tick(now - last)
		if(spike_log && current && now - last > 60)
			note_spike(now - last, ss_before, air_before)
		if(world.time >= next_eyes)
			refresh_eyes()
		last = timewarp_real_ms()
	write_results()

/datum/stress_bench
	/// spike-log=1: SSobj's time in its fire now going, by the type of thing processed (ms), for note_spike()
	var/list/obj_slowest

/// spike-log=1: SSobj's loop (processing.dm) with each thing timed, so a slow Objects tick says what it was
/datum/controller/subsystem/processing/obj/fire(resumed = 0)
	var/datum/stress_bench/B = GLOB.stress_bench
	if(!B || !world.params["spike-log"])
		return ..()
	if(!resumed)
		currentrun = processing.Copy()
		B.obj_slowest = list()
	var/list/current_run = currentrun
	var/list/slowest = B.obj_slowest
	while(current_run.len)
		var/datum/thing = current_run[current_run.len]
		current_run.len--
		var/started = TICK_USAGE_REAL
		var/kind = "[thing?.type]"
		if(QDELETED(thing))
			processing -= thing
		else if(thing.process(wait) == PROCESS_KILL)
			STOP_PROCESSING(src, thing)
		var/ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - started)
		if(ms >= 0.5)
			slowest[kind] += ms
		if(MC_TICK_CHECK)
			return

/// spike-log=1: a tick that took `gap` ms, and the subsystems that took the most of it
/datum/stress_bench/proc/note_spike(gap, list/ss_before, list/air_before)
	var/list/took = list()
	var/in_mc = 0
	var/i = 0
	for(var/datum/controller/subsystem/SS as anything in Master.subsystems)
		i++
		var/ms = SS.total_ms - ss_before[i]
		in_mc += ms
		if(ms >= 2)
			took["[SS.name]"] = ms
	sortTim(took, GLOBAL_PROC_REF(cmp_numeric_dsc), associative = TRUE)
	var/list/parts = list()
	for(var/name in took)
		parts += "[name] [round(took[name], 0.1)]"
		if(length(parts) >= 4)
			break
	lines += "spike in [current.name] at [round((world.time - current.started_at) / 10, 0.1)] s: [round(gap)] ms, [round(in_mc)] in the MC ([jointext(parts, ", ")]), [round(gap - in_mc)] outside it"
	if(took["Objects"] >= 30 && length(obj_slowest)) // and which things SSobj spent it on
		var/list/kinds = obj_slowest.Copy()
		sortTim(kinds, GLOBAL_PROC_REF(cmp_numeric_dsc), associative = TRUE)
		var/list/named = list()
		for(var/kind in kinds)
			named += "[kind] [round(kinds[kind], 0.1)]"
			if(length(named) >= 4)
				break
		lines += "    Objects on: [jointext(named, ", ")]"
	if(SSprofiler?.engine == "hippie") // the procs that ran in it, from hippie_prof's last samples (self time)
		var/list/ran = SSprofiler.recent(gap + 2)
		var/list/procs = list()
		for(var/proc_name in ran)
			if(findtext(proc_name, "(idle") == 1)
				continue
			procs += "[proc_name] [round(ran[proc_name] * 1000)]"
			if(length(procs) >= 5)
				break
		if(length(procs))
			lines += "    procs (ms): [jointext(procs, ", ")]"
	if(took["Atmospherics"] >= 20) // which of SSair's stages
		var/list/air_now = atmos_totals()
		var/list/stages = list()
		for(var/key in air_now)
			var/ms = air_now[key] - air_before[key]
			if(!findtext(key, "#") && ms >= 2)
				stages += "[key] [round(ms, 0.1)]"
		lines += "    atmos stages: [jointext(stages, ", ")]"

/datum/stress_bench/proc/note(text)
	lines += text
	shift.note("stress bench: [text]")

/datum/stress_bench/proc/start_phase(name)
	current = new
	current.name = name
	current.started_at = world.time
	for(var/datum/controller/subsystem/SS as anything in Master.subsystems)
		current.ss_ms[SS.name] = SS.total_ms
		current.ss_fired[SS.name] = SS.times_fired
	phases += current
	current.atmos_ms = atmos_totals()
	refresh_eyes()
	if(replacetext("[world.params["profile-phase"]]", "_", " ") == name) // profile-phase=<name> (underscores for spaces): BYOND's profiler over that phase alone, into <results>profile_<name>.json
		world.Profile(PROFILE_CLEAR)
		world.Profile(PROFILE_START)

/datum/stress_bench/proc/close_phase()
	current.game_ds = world.time - current.started_at
	for(var/datum/controller/subsystem/SS as anything in Master.subsystems)
		current.ss_ms[SS.name] = SS.total_ms - current.ss_ms[SS.name]
		current.ss_fired[SS.name] = SS.times_fired - current.ss_fired[SS.name]
	var/list/atmos_now = atmos_totals()
	for(var/key in atmos_now)
		current.atmos_ms[key] = atmos_now[key] - current.atmos_ms[key]
	if(replacetext("[world.params["profile-phase"]]", "_", " ") == current.name)
		var/dir = world.params["bot-results"] || "data/stress_bench/"
		text2file(world.Profile(PROFILE_REFRESH, format = "json"), "[dir]profile_[replacetext(current.name, " ", "_")].json")
		world.Profile(PROFILE_STOP)
	current.state = survey()
	if(world.params["pack-bench"] == current.name)
		pack_bench()
	log_world("STRESS BENCH: [current.line()]")
	current = null

/// SSair's stage totals and the tile engine's own
/datum/stress_bench/proc/atmos_totals()
	. = SSair.stage_ms.Copy()
	.["tile pack"] = SSair.tile_engine_pack_ms
	.["tile native"] = SSair.tile_engine_native_ms
	.["tile apply"] = SSair.tile_engine_apply_ms
	// counts, not ms (stress_report.py shows them a game second all the same)
	.["#packed"] = SSair.tile_engine_total_packed
	.["#immutable"] = SSair.tile_engine_total_immutable
	.["#rounds"] = SSair.tile_engine_total_rounds
	.["#changed"] = SSair.tile_engine_total_changed
	.["#turns"] = SSair.tile_engine_total_turns
	for(var/part in SSair.tile_engine_apply_parts)
		.["apply [part]"] = SSair.tile_engine_apply_parts[part]

/// Who counts as a player watching: up to STRESS_BENCH_EYES living bots, the same ones while they live
/datum/stress_bench/proc/refresh_eyes()
	next_eyes = world.time + 30 SECONDS
	if(shift.elapsed() < schedule["calm"] SECONDS)
		return // the shift watches its one bot while the crew arrives
	var/list/eyes = list()
	for(var/datum/bot_shift_member/M as anything in shift.members)
		if(length(eyes) >= STRESS_BENCH_EYES)
			break
		var/mob/living/body = M.body
		if(!QDELETED(body) && body.stat != DEAD)
			eyes += body
	if(length(eyes))
		SSlighting.test_eyes = eyes

/datum/stress_bench/proc/run_event(type)
	for(var/datum/round_event_control/C in SSevents.control)
		if(C.type == type)
			C.runEvent()
			return
	note("no [type] event to run")

/datum/stress_bench/proc/set_off(name)
	switch(name)
		if("aurora")
			run_event(/datum/round_event_control/aurora_caelus)
		if("grid check")
			run_event(/datum/round_event_control/grid_check)
		if("rad storm")
			SSweather.run_weather(/datum/weather/rad_storm)
		if("plasma fire")
			var/tiles = 0
			for(var/turf/open/floor/F in range(3, fire_spot))
				var/datum/gas_mixture/air = F.air
				if(!air || istype(air, /datum/gas_mixture/immutable))
					continue
				air.assert_gases(/datum/gas/plasma, /datum/gas/oxygen)
				air.moles[/datum/gas/plasma] += 60
				air.moles[/datum/gas/oxygen] += 40
				SSair.add_to_active(F)
				tiles++
			fire_spot.hotspot_expose(1000, CELL_VOLUME)
			note("plasma fire on [tiles] tiles round [AREACOORD(fire_spot)]")
		if("hull breaches")
			var/list/done = list()
			for(var/turf/closed/wall/W in breach_walls)
				done += "([W.x],[W.y])"
				W.ChangeTurf(/turf/open/floor/plating)
			note("hull walls knocked out: [jointext(done, " ")]")
		if("meteors")
			run_event(/datum/round_event_control/meteor_wave/threatening)
		if("maxcap")
			explosion(boom_spot, GLOB.MAX_EX_DEVESTATION_RANGE, GLOB.MAX_EX_HEAVY_RANGE, GLOB.MAX_EX_LIGHT_RANGE, GLOB.MAX_EX_FLASH_RANGE)
			note("maxcap at [AREACOORD(boom_spot)]")
		if("tesla")
			ball = new(tesla_spot, 200)
			for(var/i in 1 to 5)
				ball.new_mini_ball()
			note("tesla loose at [AREACOORD(tesla_spot)]")
		if("aftermath")
			if(!QDELETED(ball))
				note("tesla taken away at [AREACOORD(ball)]")
				qdel(ball)
			ball = null // it was this bench's own reference that hard deleted the ball

/// The same spots every run: everything is picked straight after seeding, before the crew arrives
/datum/stress_bench/proc/pick_spots()
	rand_seed(STRESS_BENCH_SEED)
	var/list/room_floors = list()
	var/list/hall_floors = list()
	var/list/hull_walls = list()
	var/sx = 0
	var/sy = 0
	var/n = 0
	for(var/turf/T as anything in GLOB.station_turfs)
		if(T.z != z)
			continue
		sx += T.x
		sy += T.y
		n++
	for(var/turf/T as anything in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		var/area/A = T.loc
		if(istype(T, /turf/open/floor))
			if(istype(A, /area/hallway))
				hall_floors += T
			else if(!istype(A, /area/space) && !istype(A, /area/maintenance) && !istype(A, /area/solar) && !istype(A, /area/shuttle) && !istype(A, /area/engine))
				room_floors += T
		else if(istype(T, /turf/closed/wall) && !istype(T, /turf/closed/wall/r_wall))
			for(var/dir in GLOB.cardinals)
				var/turf/inside = get_step(T, dir)
				var/turf/outside = get_step(T, turn(dir, 180))
				if(istype(inside, /turf/open/floor) && istype(inside.loc, /area/hallway) && istype(outside, /turf/open/space))
					hull_walls += T
					break
	// The maxcap: the open floor nearest the middle of the station, where the boom drills set theirs off (boom_drill.dm)
	if(n)
		var/turf/middle = locate(round(sx / n), round(sy / n), z)
		for(var/turf/open/floor/F in range(15, middle))
			if(!boom_spot || get_dist(F, middle) < get_dist(boom_spot, middle))
				boom_spot = F
	// The fire: a floor in a room, with floor all round it, air on it and no space near
	for(var/i in 1 to 200)
		var/turf/open/floor/F = pick(room_floors)
		if(!F.air || F.air.total_moles() < 50)
			continue
		var/ok = TRUE
		for(var/turf/T in range(3, F))
			if(isspaceturf(T))
				ok = FALSE
				break
		for(var/dir in GLOB.cardinals)
			if(!istype(get_step(F, dir), /turf/open/floor))
				ok = FALSE
		if(ok)
			fire_spot = F
			break
	// Six hull breaches off hallways, well apart
	shuffle_inplace(hull_walls)
	for(var/turf/closed/wall/W as anything in hull_walls)
		if(length(breach_walls) >= 6)
			break
		var/too_close = FALSE
		for(var/turf/other as anything in breach_walls)
			if(get_dist(W, other) < 15)
				too_close = TRUE
				break
		if(!too_close)
			breach_walls += W
	// The tesla: a hallway well away from the maxcap's crater
	for(var/i in 1 to 200)
		var/turf/open/floor/F = pick(hall_floors)
		if(!boom_spot || get_dist(F, boom_spot) >= 30)
			tesla_spot = F
			break
	lines += "Spots (seed [STRESS_BENCH_SEED]): fire [fire_spot ? AREACOORD(fire_spot) : "none"], maxcap [boom_spot ? AREACOORD(boom_spot) : "none"], \
		tesla [tesla_spot ? AREACOORD(tesla_spot) : "none"], [length(breach_walls)] hull walls"

/// What the station is like now: to set a faster build against one that simply does less
/datum/stress_bench/proc/survey()
	var/list/S = list()
	var/changed = 0
	var/to_space = 0
	for(var/i in 1 to length(station_turfs_start))
		var/turf/T = station_turfs_start[i]
		if(T.type != station_types_start[i])
			changed++
			if(isspaceturf(T))
				to_space++
	S["tiles changed"] = changed
	S["tiles now space"] = to_space
	var/moles = 0
	var/low = 0
	var/hot = 0
	for(var/turf/open/T in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		var/datum/gas_mixture/air = T.air
		if(!air || istype(air, /datum/gas_mixture/immutable))
			continue
		moles += air.total_moles()
		if(air.return_pressure() < 20)
			low++
		if(air.temperature > T0C + 100)
			hot++
	S["station mol"] = round(moles)
	S["turfs under 20 kPa"] = low
	S["turfs over 100 C"] = hot
	S["burning"] = length(SSair.hotspots)
	S["active turfs"] = length(SSair.active_turfs)
	var/alive = 0
	var/dead = 0
	var/gone = 0
	for(var/datum/bot_shift_member/M as anything in shift.members)
		if(QDELETED(M.body))
			gone++
		else if(M.body.stat == DEAD)
			dead++
		else
			alive++
	S["crew alive"] = alive
	S["crew dead"] = dead
	S["crew bodies gone"] = gone
	var/apcs = 0
	for(var/obj/machinery/power/apc/A as anything in GLOB.apcs_list)
		if(A.z == z && A.equipment > 1)
			apcs++
	S["APCs running"] = apcs
	S["lights waiting unseen"] = SSlighting.unseen_count
	S["lights queued"] = length(SSlighting.sources_queue)
	S["atoms"] = length(world.contents)
	S["objects processing"] = length(SSobj.processing)
	S["machines"] = length(GLOB.machines)
	S["timers"] = length(SStimer.timer_id_dict)
	return S

/datum/stress_bench/proc/write_results()
	var/dir = world.params["bot-results"] || "data/stress_bench/"
	var/real = 0
	var/mc = 0
	var/seconds = 0
	var/worst = 0
	var/over_budget = 0
	var/over_100 = 0
	var/list/ss_total = list()
	var/list/out = list("CPU STRESS BENCH on [SSmapping.config?.map_name], BYOND [world.byond_version].[world.byond_build], [world.fps] ticks a second, \
		[length(shift.members)] crew, [STRESS_BENCH_EYES] watching")
	out += lines
	out += ""
	for(var/datum/stress_phase/P as anything in phases)
		out += P.line()
		if(P.name == "crew arriving")
			continue
		real += P.real_ms
		mc += P.mc_ms()
		seconds += P.seconds()
		worst = max(worst, P.worst_ms)
		over_budget += P.over_budget
		over_100 += P.over_100
		for(var/name in P.ss_ms)
			ss_total[name] += P.ss_ms[name]
	sortTim(ss_total, GLOBAL_PROC_REF(cmp_numeric_dsc), associative = TRUE)
	var/list/parts = list()
	for(var/name in ss_total)
		if(ss_total[name] / max(seconds, 1) >= 0.1)
			parts += "[name] [round(ss_total[name] / max(seconds, 1), 0.1)]"
	out += ""
	out += "From calm on: real [round(real / max(seconds, 1), 0.1)] ms a game second (MC [round(mc / max(seconds, 1), 0.1)], outside [round((real - mc) / max(seconds, 1), 0.1)]), \
		worst tick [round(worst)] ms, [over_budget] ticks over [STRESS_BENCH_BUDGET_MS] ms, [over_100] over 100"
	out += "Subsystems from calm on, ms a game second: [jointext(parts, ", ")]"
	out += ""
	out += "What the station was like at the end of each phase:"
	for(var/datum/stress_phase/P as anything in phases)
		var/list/state_parts = list()
		for(var/key in P.state)
			state_parts += "[key] [P.state[key]]"
		out += "  [P.name]: [jointext(state_parts, ", ")]"
	if(light_tally)
		var/list/why_ms = list()
		var/all_ms = 0
		var/all_count = 0
		for(var/key in light_ms)
			all_ms += light_ms[key]
			all_count += light_tally[key]
			var/why = copytext(key, 1, findtext(key, " "))
			why_ms[why] += light_ms[key]
		sortTim(light_ms, GLOBAL_PROC_REF(cmp_numeric_dsc), associative = TRUE)
		out += ""
		out += "Light updates from calm on (light-tally): [all_count], [round(all_ms)] ms; by why: [json_encode(why_ms)]"
		var/shown = 0
		for(var/key in light_ms)
			if(++shown > 30)
				break
			out += "  [round(light_ms[key])] ms, [light_tally[key]] updates ([round(1000 * light_ms[key] / max(light_tally[key], 1))] us each): [key]"
	if(light_shadow)
		out += ""
		out += "Light shadow check (light-shadow): [json_encode(light_shadow)]"
	if(SSlighting.native && SSlighting.native_view & LIGHTING_VIEW_SHADOW) // lighting-view=shadow
		var/different = call_ext(LIGHTING_ENGINE_LIB, "byond:lighting_view_report")()
		out += ""
		out += "Light views, the engine's against view(): [different] with different turfs (data/lighting_view_check.txt)"
	if(GLOB.reconcile_check) // reconcile-check=1
		out += ""
		out += "Pipeline reconciles, gas mixtures against the old way's: [json_encode(GLOB.reconcile_check)]"
	if(GLOB.tesla_zap_check) // tesla-zap-check=1
		out += ""
		out += "Tesla zaps, against what the old loop would have chosen: [json_encode(GLOB.tesla_zap_check)]"
	if(SStimer.census) // timer-census=1
		var/list/census = SStimer.census.Copy()
		sortTim(census, GLOBAL_PROC_REF(cmp_numeric_dsc), associative = TRUE)
		var/total = 0
		for(var/key in census)
			total += census[key]
		out += ""
		out += "Timers, by proc (ms over the whole run, how many fired), [round(total)] ms in all:"
		var/shown = 0
		for(var/key in census)
			out += "  [round(census[key])] ms, [SStimer.census_count[key]] fired: [key]"
			if(++shown >= 20)
				break
	if(SSair.tile_engine_writes_check) // atmos-engine-writes=check: what the tile engine wrote into turfs, against what DM would have
		out += ""
		out += "Tile engine's writes, against what DM would have written: [json_encode(SSair.tile_engine_writes_check)]"
	// References held to station turfs' air and gas lists: a leak would have them climb with every tick a turf's air changed
	var/airs = 0
	var/air_refs = 0
	var/air_most = 0
	var/list_refs = 0
	var/list_most = 0
	for(var/turf/open/T in GLOB.station_turfs)
		var/datum/gas_mixture/air = T.air
		if(!air)
			continue
		airs++
		var/count = refcount(air)
		air_refs += count
		air_most = max(air_most, count)
		var/list/moles = air.moles
		count = refcount(moles)
		list_refs += count
		list_most = max(list_most, count)
	out += ""
	out += "References to station turfs' air: [airs] mixtures, [round(air_refs / max(1, airs), 0.01)] each on average, most [air_most]; their gas lists [round(list_refs / max(1, airs), 0.01)] on average, most [list_most]"
	if(SSair.tile_engine_cache_shadow) // atmos-engine-cache=shadow: what the tile engine kept of turfs, against what DM sent
		var/list/check = SSair.tile_engine_cache_check()
		out += ""
		out += "Tile engine's kept turf kinds and neighbours, against what DM sent: [length(check) == 2 ? "[check[1]] checked, [check[2]] different" : "no answer"]"
	if(SSair.atmos_idle_shadow) // atmos-idle-shadow=1: the idle registry set against the old check, every machine every tick
		out += ""
		out += "Idle atmos machines, the registry against the old check: [json_encode(SSair.atmos_idle_shadow)]"
	out += ""
	out += "Lighting engine: [SSlighting.native_status]"
	if(SSlighting.native_shadow) // lighting-engine=shadow: the engine followed the DM code through the whole round
		out += SSlighting.native_shadow_check(z)
	var/list/json_phases = list()
	for(var/datum/stress_phase/P as anything in phases)
		json_phases += list(P.to_list())
	fdel("[dir]stress.txt")
	fdel("[dir]stress.json")
	text2file(jointext(out, "\n"), "[dir]stress.txt")
	text2file(json_encode(list("map" = SSmapping.config?.map_name, "crew" = length(shift.members), "fps" = world.fps, "phases" = json_phases)), "[dir]stress.json")
	log_world("STRESS BENCH: done, [dir]stress.txt")

#undef STRESS_BENCH_SEED
#undef STRESS_BENCH_EYES
#undef STRESS_BENCH_BUDGET_MS

/// pack-bench=<phase name>: at the end of that phase, times the parts of the tile engine's packing on the turfs awake then and
/// their neighbours, each part on its own, in turn, best of five. A note in the results; for deciding what to keep natively.
/datum/stress_bench/proc/pack_bench()
	var/list/turf/open/turfs = list()
	for(var/turf/open/T as anything in SSair.active_turfs)
		turfs |= T
		for(var/turf/open/N as anything in T.atmos_adjacent_turfs)
			turfs |= N
	var/n = length(turfs)
	if(!n)
		note("pack bench: no awake turfs")
		return
	var/list/best = list()
	for(var/rep in 1 to 5)
		for(var/part in list("full", "no neighbours", "no neighbours or kind", "air only", "touch"))
			var/start = TICK_USAGE_REAL
			pack_bench_part(part, turfs)
			var/us = TICK_DELTA_TO_MS(TICK_USAGE_REAL - start) * 1000 / n
			if(!best[part] || us < best[part])
				best[part] = us
	var/list/parts = list()
	for(var/part in best)
		parts += "[part] [round(best[part], 0.01)]"
	note("pack bench, [n] turfs, us a turf: [jointext(parts, ", ")]")

/datum/stress_bench/proc/pack_bench_part(part, list/turf/open/turfs)
	var/list/tiles = list()
	var/list/adjacent = list()
	switch(part)
		if("full")
			SSair.tile_engine_pack(turfs, tiles, adjacent)
		if("no neighbours")
			for(var/turf/open/T as anything in turfs)
				var/datum/gas_mixture/air = isopenturf(T) ? T.air : null
				if(!air)
					tiles += -1
					continue
				var/list/moles = air.moles
				tiles += length(moles)
				for(var/gas_type, amount in moles)
					tiles += gas_type
					tiles += amount
				var/kind = 0
				if(istype(air, /datum/gas_mixture/immutable))
					kind = istype(air, /datum/gas_mixture/immutable/space) ? 1 : 2
				else if(T.planetary_atmos)
					kind = 3 + SSair.tile_engine_planetary(T.initial_gas_mix)
				var/datum/excited_group/group = T.excited_group
				tiles.Add(air.temperature, kind, group ? group.tile_engine_number : 0, T.significant_share_ticker, T.active_hotspot ? 1 : 0, T.tile_engine_drawn)
		if("no neighbours or kind")
			for(var/turf/open/T as anything in turfs)
				var/datum/gas_mixture/air = isopenturf(T) ? T.air : null
				if(!air)
					tiles += -1
					continue
				var/list/moles = air.moles
				tiles += length(moles)
				for(var/gas_type, amount in moles)
					tiles += gas_type
					tiles += amount
				var/datum/excited_group/group = T.excited_group
				tiles.Add(air.temperature, group ? group.tile_engine_number : 0, T.significant_share_ticker, T.active_hotspot ? 1 : 0, T.tile_engine_drawn)
		if("air only")
			for(var/turf/open/T as anything in turfs)
				var/datum/gas_mixture/air = isopenturf(T) ? T.air : null
				if(!air)
					tiles += -1
					continue
				var/list/moles = air.moles
				tiles += length(moles)
				for(var/gas_type, amount in moles)
					tiles += gas_type
					tiles += amount
				tiles += air.temperature
		if("touch")
			for(var/turf/open/T as anything in turfs)
				var/datum/gas_mixture/air = isopenturf(T) ? T.air : null
				if(air)
					tiles += air.temperature

/// tesla-zap-check=1: what tesla_zap()'s old single loop chose from the same view, to set against what it chooses now
/proc/tesla_zap_old_choice(atom/source, zap_range, tesla_flags, list/shocked_targets, list/seen, list/things_to_shock, list/blacklisted_tesla_types)
	var/closest_dist = 0
	var/closest_atom
	var/obj/machinery/power/tesla_coil/closest_tesla_coil
	var/obj/machinery/power/grounding_rod/closest_grounding_rod
	var/mob/living/closest_mob
	var/obj/machinery/closest_machine
	var/obj/structure/closest_structure
	var/obj/structure/blob/closest_blob
	for(var/A in typecache_filter_multi_list_exclusion(seen, things_to_shock, blacklisted_tesla_types))
		if(!(tesla_flags & TESLA_ALLOW_DUPLICATES) && LAZYACCESS(shocked_targets, A))
			continue

		if(istype(A, /obj/machinery/power/tesla_coil))
			var/dist = get_dist(source, A)
			var/obj/machinery/power/tesla_coil/C = A
			if(dist <= zap_range && (dist < closest_dist || !closest_tesla_coil) && !(C.obj_flags & BEING_SHOCKED))
				closest_dist = dist

				//we use both of these to save on istype and typecasting overhead later on
				//while still allowing common code to run before hand
				closest_tesla_coil = C
				closest_atom = C


		else if(closest_tesla_coil)
			continue //no need checking these other things

		else if(istype(A, /obj/machinery/power/grounding_rod))
			var/dist = get_dist(source, A)-2
			if(dist <= zap_range && (dist < closest_dist || !closest_grounding_rod))
				closest_grounding_rod = A
				closest_atom = A
				closest_dist = dist

		else if(closest_grounding_rod)
			continue

		else if(isliving(A))
			var/dist = get_dist(source, A)
			var/mob/living/L = A
			if(dist <= zap_range && (dist < closest_dist || !closest_mob) && L.stat != DEAD && !(L.flags_1 & TESLA_IGNORE_1))
				closest_mob = L
				closest_atom = A
				closest_dist = dist

		else if(closest_mob)
			continue

		else if(ismachinery(A))
			var/obj/machinery/M = A
			var/dist = get_dist(source, A)
			if(dist <= zap_range && (dist < closest_dist || !closest_machine) && !(M.obj_flags & BEING_SHOCKED))
				closest_machine = M
				closest_atom = A
				closest_dist = dist

		else if(closest_machine)
			continue

		else if(istype(A, /obj/structure/blob))
			var/obj/structure/blob/B = A
			var/dist = get_dist(source, A)
			if(dist <= zap_range && (dist < closest_dist || !closest_tesla_coil) && !(B.obj_flags & BEING_SHOCKED))
				closest_blob = B
				closest_atom = A
				closest_dist = dist

		else if(closest_blob)
			continue

		else if(isstructure(A))
			var/obj/structure/S = A
			var/dist = get_dist(source, A)
			if(dist <= zap_range && (dist < closest_dist || !closest_tesla_coil) && !(S.obj_flags & BEING_SHOCKED))
				closest_structure = S
				closest_atom = A
				closest_dist = dist

		else if(closest_structure)
			continue
	return closest_atom

/// reconcile-check=1: reconcile_air()'s old sharing out, run on copies of what the new one was given, and every mixture compared
/// exactly (each gas's amount, in order, the temperature and the volume)
/datum/pipeline/proc/reconcile_check_against_old(list/datum/gas_mixture/GL, list/datum/gas_mixture/before)
	var/total_thermal_energy = 0
	var/total_heat_capacity = 0
	var/datum/gas_mixture/total_gas_mixture = new(0)
	var/list/total_gases = total_gas_mixture.moles
	for(var/i in before)
		var/datum/gas_mixture/G = i
		total_gas_mixture.volume += G.volume
		var/list/giver_gases = G.moles
		for(var/giver_id in giver_gases)
			var/giver_gas_amount = giver_gases[giver_id]
			ASSERT_GAS(giver_id, total_gas_mixture)
			total_gases[giver_id] += giver_gas_amount
			total_heat_capacity += giver_gas_amount * GAS_META[META_GAS_SPECIFIC_HEAT][giver_id]
		total_thermal_energy += THERMAL_ENERGY(G)
	total_gas_mixture.temperature = total_heat_capacity ? (total_thermal_energy/total_heat_capacity) : 0
	total_gas_mixture.garbage_collect()
	if(total_gas_mixture.volume > 0)
		for(var/i in before)
			var/datum/gas_mixture/G = i
			G.copy_from(total_gas_mixture)
			var/list/G_gases = G.moles
			for(var/id in G_gases)
				G_gases[id] *= G.volume/total_gas_mixture.volume
	for(var/n in 1 to length(GL))
		var/datum/gas_mixture/now = GL[n]
		var/datum/gas_mixture/old = before[n]
		var/why
		if(now.temperature != old.temperature)
			why = "temperature [now.temperature] against [old.temperature]"
		else if(now.volume != old.volume)
			why = "volume [now.volume] against [old.volume]"
		else if(length(now.moles) != length(old.moles))
			why = "[length(now.moles)] gases against [length(old.moles)]"
		else
			for(var/k in 1 to length(now.moles))
				var/id_now = now.moles[k]
				var/id_old = old.moles[k]
				if(id_now != id_old || now.moles[id_now] != old.moles[id_old])
					why = "gas [k]: [id_now] [now.moles[id_now]] against [id_old] [old.moles[id_old]]"
					break
		if(why)
			GLOB.reconcile_check["different"]++
			if(!GLOB.reconcile_check["first"])
				GLOB.reconcile_check["first"] = "[src] mixture [n] of [length(GL)] ([now.type]): [why]"
		else
			GLOB.reconcile_check["same"]++
