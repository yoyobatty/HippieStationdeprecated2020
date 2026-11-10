// Lighting bench - headless benchmark and snapshot of the lighting engine, for working on it.
//
// Boots the station, then on the station z-level: relights every light, walks lights of a couple of sizes around,
// and opens and closes airlocks, timing how long the lighting engine takes over each. Checks the engine's bookkeeping
// adds up afterwards, then snapshots what every lit tile looks like, for tools/lighting_bench/render.py to draw over
// the map. It does all of that twice: once with bounce lighting off, once with it on.
//
// Run it:   tools/lighting_bench/run_lighting_bench.sh [profile|starlight|directional|tail]
// or boot:  DreamDaemon hippiestation.dmb -params "lighting-bench=1" ("lighting-bench=profile" to also profile,
//           "lighting-bench=directional" to also try out directional lights, see lighting_bench_directional(),
//           "lighting-bench=tail" to also try the soft falloff at a few lengths, see lighting_bench_tail())
// Results:  data/lighting_bench/results.txt (timings), snapshot_<mode>.txt (every lit tile's corners), and with
//           profiling, profile_<mode>.json (BYOND's profiler over one more run of the workloads)

#define LIGHTING_BENCH_DIR "data/lighting_bench/"
/// How many times each workload is repeated; the median is reported
#define LIGHTING_BENCH_REPEATS 3
/// How many spots the moving lights are moved to
#define LIGHTING_BENCH_MOVES 400
/// How many airlocks get opened and closed
#define LIGHTING_BENCH_DOORS 150

/proc/run_lighting_bench(option)
	// Headless: nobody is connected, and with sleep_offline on the world pauses - this would wait forever.
	Master.sleep_offline_after_initializations = FALSE
	world.sleep_offline = FALSE
	sleep(5 SECONDS) // let anything the first ticks turn on settle
	fdel(LIGHTING_BENCH_DIR)

	var/z = SSmapping.levels_by_trait(ZTRAIT_STATION)[1]
	var/list/lines = list("Lighting bench - station z-level [z], BYOND [world.byond_version].[world.byond_build], lighting engine [SSlighting.native_status]")

	// Spots for the moving lights, and airlocks to open and close. Same picks every run, so runs compare.
	rand_seed(1337)
	var/list/turf/spots = list()
	var/list/obj/machinery/door/airlock/doors = list()
	for(var/turf/T as anything in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		if(T.lighting_object && !IS_OPAQUE_TURF(T))
			spots += T
		for(var/obj/machinery/door/airlock/door in T)
			if(door.opacity && door.density)
				doors += door
	shuffle_inplace(spots)
	shuffle_inplace(doors)
	spots.Cut(min(length(spots), LIGHTING_BENCH_MOVES) + 1)
	doors.Cut(min(length(doors), LIGHTING_BENCH_DOORS) + 1)
	lines += "[length(spots)] spots for the moving lights, [length(doors)] airlocks"

	if(option == "tone") // the tone curve and eye adaptation alone
		lines += ""
		lines += "== the tone curve and eye adaptation =="
		lines += lighting_bench_tone(z)
		text2file(jointext(lines, "\n"), "[LIGHTING_BENCH_DIR]results.txt")
		log_world("LIGHTING BENCH: done")
		Master.Shutdown()
		qdel(world)
		return

	// Lighting worked out afresh should match lighting as it booted: nothing should depend on which lights worked theirs
	// out first. Nor should turning bounce lighting off and back on (the admin verb) leave any tile changed.
	lighting_bench_snapshot(z, "[LIGHTING_BENCH_DIR]snapshot_booted.txt")
	SSlighting.relight_all()
	lighting_bench_flush()
	lighting_bench_snapshot(z, "[LIGHTING_BENCH_DIR]snapshot_relit.txt")
	lines += "relighting everything: [lighting_bench_compare_snapshots("[LIGHTING_BENCH_DIR]snapshot_booted.txt", "[LIGHTING_BENCH_DIR]snapshot_relit.txt")]"
	// The engine looking around for the lights (lighting-view=native) should light every tile as view() does: everything relit
	// with view(), then straight after with the engine's own view, nothing in between to change a light
	if(SSlighting.native && SSlighting.native_view_capable)
		var/old_view = SSlighting.native_view
		SSlighting.native_view = LIGHTING_VIEW_DM
		SSlighting.relight_all()
		lighting_bench_flush()
		lighting_bench_snapshot(z, "[LIGHTING_BENCH_DIR]snapshot_view_dm.txt")
		SSlighting.native_view = LIGHTING_VIEW_NATIVE
		SSlighting.relight_all()
		lighting_bench_flush()
		lighting_bench_snapshot(z, "[LIGHTING_BENCH_DIR]snapshot_view_native.txt")
		SSlighting.native_view = old_view
		var/view_different = lighting_bench_count_differences("[LIGHTING_BENCH_DIR]snapshot_view_dm.txt", "[LIGHTING_BENCH_DIR]snapshot_view_native.txt")
		lines += "the engine's own view against view(), everything relit with each: [view_different ? "[view_different] TILES DIFFER" : "every tile the same"]"
	var/was_on = SSlighting.bounce_lighting
	SSlighting.set_bounce_lighting(!was_on)
	lighting_bench_flush()
	SSlighting.set_bounce_lighting(was_on)
	lighting_bench_flush()
	lighting_bench_snapshot(z, "[LIGHTING_BENCH_DIR]snapshot_toggled.txt")
	lines += "toggling bounce lighting [was_on ? "off and on" : "on and off"]: [lighting_bench_compare_snapshots("[LIGHTING_BENCH_DIR]snapshot_booted.txt", "[LIGHTING_BENCH_DIR]snapshot_toggled.txt")]"
	// Nor should the update stamps starting over (see /datum/controller/subsystem/lighting/proc/reset_lighting_stamps()),
	// which only happens every LIGHTING_STAMP_LIMIT light source updates: here, in the middle of relighting everything
	SSlighting.lighting_stamp = LIGHTING_STAMP_LIMIT - 100
	SSlighting.relight_all()
	lighting_bench_flush()
	lighting_bench_snapshot(z, "[LIGHTING_BENCH_DIR]snapshot_restamped.txt")
	lines += "starting the update stamps over, mid-relight: [lighting_bench_compare_snapshots("[LIGHTING_BENCH_DIR]snapshot_booted.txt", "[LIGHTING_BENCH_DIR]snapshot_restamped.txt")]"
	// A light source destroyed while it sits in the lighting queue, or the null a hard deleted one leaves there, is
	// dropped from it: SSlighting's fire() used to go round on the one forever, and crash on the other every time it fired
	var/obj/effect/dummy/lighting_obj/doomed = new(spots[1], LIGHT_COLOR_WHITE, 3, 1)
	lighting_bench_flush()
	var/datum/light_source/ghost = doomed.light
	qdel(doomed)
	SSlighting.sources_queue += ghost
	SSlighting.sources_queue += null
	lighting_bench_flush()
	lines += "a destroyed light source and a null in the lighting queue: [length(SSlighting.sources_queue) ? "STILL THERE" : "dropped"]"
	ghost = null

	for(var/mode in list("bounce_off", "bounce_on"))
		SSlighting.set_bounce_lighting(mode == "bounce_on")
		lighting_bench_flush()
		var/list/datum/light_source/sources = list()
		for(var/datum/light_source/L)
			if(!QDELETED(L) && L.source_turf?.z == z) // destroyed ones can linger, while anything still holds them
				sources += L

		lines += ""
		lines += "== [mode] =="
		lines += "relight all [length(sources)] lights: [lighting_bench_time(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(lighting_bench_relight), sources))] ms"
		for(var/range in list(4, 7))
			var/ms = lighting_bench_time(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(lighting_bench_carry), spots, range)) / length(spots)
			lines += "moving range [range] light: [round(ms, 0.001)] ms per move"
		var/ms = lighting_bench_time(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(lighting_bench_doors), doors)) / (2 * max(1, length(doors)))
		lines += "airlock opening or closing: [round(ms, 0.001)] ms each"

		var/corners = 0
		for(var/datum/lighting_corner/C)
			if(!QDELETED(C))
				corners++
		lines += "[corners] lighting corners in the world"
		lines += lighting_bench_check()
		lines += lighting_bench_falloff_check(spots.Copy(1, min(length(spots), 100) + 1))
		lighting_bench_snapshot(z, "[LIGHTING_BENCH_DIR]snapshot_[mode].txt")
		lines += lighting_bench_in_place_check(z, mode)

		if(option == "profile")
			world.Profile(PROFILE_CLEAR)
			world.Profile(PROFILE_START)
			lighting_bench_relight(sources)
			lighting_bench_carry(spots, 4)
			lighting_bench_doors(doors)
			text2file(world.Profile(PROFILE_REFRESH, format = "json"), "[LIGHTING_BENCH_DIR]profile_[mode].json")
			world.Profile(PROFILE_STOP)

	// Bounce lighting tuned past its limits through View Variables, as an admin could: it should clamp, relight, and
	// still add up and only ever fade
	lines += ""
	lines += "== bounce tuned to its limits =="
	var/list/tuned = list("bounce_strength" = 5, "bounce_falloff" = 2, "bounce_depth" = 50, "bounce_cutoff" = 0)
	var/list/was = list()
	for(var/var_name in tuned)
		was[var_name] = SSlighting.vars[var_name]
		SSlighting.vv_edit_var(var_name, tuned[var_name])
	lighting_bench_flush()
	lines += "asked for strength 5, falloff 2, depth 50, cutoff 0; clamped to strength [SSlighting.bounce_strength], falloff [SSlighting.bounce_falloff], depth [SSlighting.bounce_depth], cutoff [SSlighting.bounce_cutoff]"
	lines += lighting_bench_check()
	lines += lighting_bench_falloff_check(spots.Copy(1, min(length(spots), 100) + 1))
	for(var/var_name in was)
		SSlighting.vv_edit_var(var_name, was[var_name])
	lighting_bench_flush()

	if(option == "starlight")
		// Starlight, bounce lighting on throughout: as tgstation had it in 2020 (power 0.25, from normal light height),
		// as it is (tgstation's current power, from just under the floor), and that bouncing too
		lines += ""
		lines += "== starlight =="
		for(var/list/variant in list(
				list("starlight_2020", 0.25, LIGHTING_HEIGHT, FALSE, GLOB.starlight_range),
				list("starlight", GLOB.starlight_power, LIGHTING_HEIGHT_SPACE, FALSE, GLOB.starlight_range),
				list("starlight_bounce", GLOB.starlight_power, LIGHTING_HEIGHT_SPACE, TRUE, GLOB.starlight_range),
				// reaching a tile further than tgstation's, with room to cast shadows for bounce to fill
				list("starlight_range3_bounce", GLOB.starlight_power, LIGHTING_HEIGHT_SPACE, TRUE, 3),
				// at its brightest during Aurora Caelus (see /datum/round_event/aurora_caelus/proc/fade_space())
				list("starlight_aurora", GLOB.starlight_power * 0.6, LIGHTING_HEIGHT_SPACE, FALSE, GLOB.starlight_range * 1.75),
				list("starlight_aurora_bounce", GLOB.starlight_power * 0.6, LIGHTING_HEIGHT_SPACE, TRUE, GLOB.starlight_range * 1.75)))
			var/start = TICK_USAGE_REAL
			lighting_bench_set_starlight(variant[2], variant[3], variant[4], variant[5])
			lines += "[variant[1]] (range [variant[5]], power [variant[2]], height [variant[3]], bounce [variant[4] ? "on" : "off"]): relighting [length(GLOB.starlight)] starlit tiles took [round(TICK_DELTA_TO_MS(TICK_USAGE_REAL - start), 0.1)] ms"
			lighting_bench_snapshot(z, "[LIGHTING_BENCH_DIR]snapshot_[variant[1]].txt")

	if(option == "directional")
		lines += ""
		lines += "== directional lighting =="
		lines += lighting_bench_directional(z)

	if(option == "tail")
		lines += ""
		lines += "== soft falloff =="
		lines += lighting_bench_tail(z, spots, doors)

	if(option == "sections")
		lines += ""
		lines += "== where a lamp's update goes =="
		lines += lighting_bench_sections(z)

	if(option == "engines")
		lines += ""
		lines += "== the engine against the DM code =="
		lines += lighting_bench_engines(z, spots, doors)

	if(option == "shadow") // booted with lighting-engine=shadow: the engine followed the DM code through everything above
		lines += ""
		lines += "== the engine shadowing the DM code =="
		lines += SSlighting.native_shadow_check(z)

	text2file(jointext(lines, "\n"), "[LIGHTING_BENCH_DIR]results.txt")
	log_world("LIGHTING BENCH: done")
	Master.Shutdown()
	qdel(world)

/**
 * Directional lighting: crew holding lit seclites in rooms with their lights switched off, bounce lighting on. Checks the cones point the way
 * their holders face - turning, and after being dropped - and that a mech's headlights turn with it, times turning in
 * place, and snapshots the cones (snapshot_directional_cone), without the light they scatter around them
 * (snapshot_directional_noscatter) and the same lights lighting all around them (snapshot_directional_omni), for:
 * python tools/lighting_bench/render.py --before directional_omni --after directional_cone (or --before directional_noscatter)
 */
/proc/lighting_bench_directional(z)
	var/list/lines = list()
	SSlighting.set_bounce_lighting(TRUE)
	lighting_bench_flush()

	// Rooms with their lights switched off, a holder in the middle of each, so each cone is seen lighting a room of its own
	var/list/area/darkened = list()
	var/list/turf/dark = lighting_bench_darken_rooms(z, darkened)
	var/list/mob/living/carbon/human/holders = list()
	var/list/obj/item/flashlight/lights = list()
	for(var/i in 1 to length(dark))
		var/mob/living/carbon/human/holder = new(dark[i])
		var/obj/item/flashlight/seclite/light = new(dark[i])
		holder.put_in_hands(light)
		light.on = TRUE
		light.update_brightness(holder)
		holder.setDir(GLOB.cardinals[(i % 4) + 1])
		holders += holder
		lights += light
	lighting_bench_flush()
	lines += "[length(holders)] crew holding lit seclites, in the middle of [length(darkened)] rooms with their lights switched off"

	var/wrong = 0
	for(var/i in 1 to length(holders))
		var/mob/living/carbon/human/holder = holders[i]
		var/obj/item/flashlight/light = lights[i]
		if(light.light?.top_atom != holder || light.light.light_dir != holder.dir)
			wrong++
	lines += "held, pointing the way their holder faces: [wrong ? "[wrong] WRONG" : "all"]"
	lighting_bench_snapshot(z, "[LIGHTING_BENCH_DIR]snapshot_directional_cone.txt")
	// The same cones without the light they scatter around them
	var/scatter = SSlighting.cone_scatter
	SSlighting.vv_edit_var(NAMEOF(SSlighting, cone_scatter), 0)
	lighting_bench_flush()
	lighting_bench_snapshot(z, "[LIGHTING_BENCH_DIR]snapshot_directional_noscatter.txt")
	lines += lighting_bench_check()
	SSlighting.vv_edit_var(NAMEOF(SSlighting, cone_scatter), scatter)
	lighting_bench_flush()

	var/turns = 0
	var/start = TICK_USAGE_REAL
	for(var/mob/living/carbon/human/holder as anything in holders)
		for(var/j in 1 to 4)
			holder.setDir(turn(holder.dir, 90))
			lighting_bench_flush()
			turns++
	lines += "turning in place with a lit seclite: [round(TICK_DELTA_TO_MS(TICK_USAGE_REAL - start) / max(1, turns), 0.001)] ms per turn"
	wrong = 0
	for(var/mob/living/carbon/human/holder as anything in holders)
		holder.setDir(turn(holder.dir, 90))
	lighting_bench_flush()
	for(var/i in 1 to length(holders))
		var/mob/living/carbon/human/holder = holders[i]
		var/obj/item/flashlight/light = lights[i]
		if(light.light?.light_dir != holder.dir)
			wrong++
	lines += "after turning: [wrong ? "[wrong] WRONG" : "all following"]"

	wrong = 0
	for(var/i in 1 to length(holders))
		var/mob/living/carbon/human/holder = holders[i]
		var/obj/item/flashlight/light = lights[i]
		var/facing = holder.dir
		holder.dropItemToGround(light)
		lighting_bench_flush()
		holder.setDir(turn(facing, 180))
		lighting_bench_flush()
		if(light.light?.top_atom != light || light.light.light_dir != facing)
			wrong++
	lines += "dropped, still pointing where they were facing: [wrong ? "[wrong] WRONG" : "all"]"

	if(length(dark))
		var/obj/mecha/working/ripley/mech = new(dark[1])
		mech.set_light(mech.lights_power)
		mech.setDir(EAST)
		lighting_bench_flush()
		var/east = mech.light?.light_dir
		mech.setDir(NORTH)
		lighting_bench_flush()
		lines += "mech headlights turning east then north: [east == EAST && mech.light?.light_dir == NORTH ? "followed" : "WRONG ([east], [mech.light?.light_dir])"]"
		mech.set_light(0)
		lighting_bench_flush()
		lines += "mech headlights off: [mech.light ? "STILL LIT" : "off"]"
		qdel(mech)

	// Back in hand, facing as first snapshotted, then the same lights lighting all around them
	for(var/i in 1 to length(holders))
		var/mob/living/carbon/human/holder = holders[i]
		holder.put_in_hands(lights[i])
		holder.setDir(GLOB.cardinals[(i % 4) + 1])
	lighting_bench_flush()
	for(var/obj/item/flashlight/light as anything in lights)
		light.light_angle = 360
		light.update_light()
	lighting_bench_flush()
	lighting_bench_snapshot(z, "[LIGHTING_BENCH_DIR]snapshot_directional_omni.txt")
	lines += lighting_bench_check()

	QDEL_LIST(lights)
	QDEL_LIST(holders)
	lighting_bench_light_rooms(darkened)
	lighting_bench_flush()
	return lines

/// Switches off the lights in up to 12 rooms well apart on the z-level, adding them to `darkened`, and returns a floor
/// turf in the middle of each, to light a room of its own
/proc/lighting_bench_darken_rooms(z, list/area/darkened)
	var/list/turf/dark = list()
	for(var/area/A in GLOB.sortedAreas)
		if(A.z != z || !A.lightswitch || !IS_DYNAMIC_LIGHTING(A))
			continue
		var/floors = 0
		var/sum_x = 0
		var/sum_y = 0
		for(var/turf/open/floor/F in A)
			floors++
			sum_x += F.x
			sum_y += F.y
		if(floors < 40 || floors > 300)
			continue
		var/turf/open/floor/middle = locate(round(sum_x / floors), round(sum_y / floors), z)
		if(!istype(middle) || get_area(middle) != A || is_blocked_turf(middle, TRUE))
			continue
		var/lonely = TRUE
		for(var/turf/other as anything in dark)
			if(get_dist(middle, other) < 14)
				lonely = FALSE
				break
		if(!lonely)
			continue
		A.lightswitch = FALSE
		A.power_change()
		darkened += A
		dark += middle
		if(length(dark) >= 12)
			break
	return dark

/// Switches the lights back on in rooms lighting_bench_darken_rooms() switched them off in
/proc/lighting_bench_light_rooms(list/area/darkened)
	for(var/area/A as anything in darkened)
		A.lightswitch = TRUE
		A.power_change()

/**
 * The soft falloff (see LIGHTING_FALLOFF_TAIL) at a few lengths, bounce lighting on, with a lamp in the middle of a dozen
 * rooms with their lights switched off, to see a light's falloff on its own: how long the workloads take at each, the
 * checks, and snapshots (snapshot_tail_<length>) for: python tools/lighting_bench/render.py --before tail_1 --after tail_1.4
 */
/proc/lighting_bench_tail(z, list/turf/spots, list/obj/machinery/door/airlock/doors)
	var/list/lines = list()
	var/tail = SSlighting.falloff_tail
	SSlighting.set_bounce_lighting(TRUE)
	var/list/area/darkened = list()
	var/list/obj/effect/dummy/lighting_obj/lamps = list()
	for(var/turf/middle as anything in lighting_bench_darken_rooms(z, darkened))
		lamps += new /obj/effect/dummy/lighting_obj(middle, LIGHT_COLOR_WHITE, 7, 1)
	lighting_bench_flush()
	lines += "a range 7 lamp in the middle of [length(lamps)] rooms with their lights switched off"
	for(var/tail_length in list(1, 1.25, 1.4, 1.5))
		SSlighting.vv_edit_var(NAMEOF(SSlighting, falloff_tail), tail_length)
		lighting_bench_flush()
		lighting_bench_snapshot(z, "[LIGHTING_BENCH_DIR]snapshot_tail_[tail_length].txt")
		lines += lighting_bench_workload_timings("tail [tail_length]", z, spots, doors)
		var/corners = 0
		for(var/datum/lighting_corner/C)
			if(!QDELETED(C))
				corners++
		lines += "[corners] lighting corners in the world"
		lines += lighting_bench_check()
		lines += lighting_bench_falloff_check(spots.Copy(1, min(length(spots), 100) + 1))
	QDEL_LIST(lamps)
	lighting_bench_light_rooms(darkened)
	SSlighting.vv_edit_var(NAMEOF(SSlighting, falloff_tail), tail)
	lighting_bench_flush()
	return lines

/// The lighting bench's workloads, timed, on one line
/proc/lighting_bench_workload_timings(label, z, list/turf/spots, list/obj/machinery/door/airlock/doors)
	var/list/datum/light_source/sources = list()
	for(var/datum/light_source/L)
		if(!QDELETED(L) && L.source_turf?.z == z) // destroyed ones can linger, while anything still holds them
			sources += L
	var/relight = lighting_bench_time(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(lighting_bench_relight), sources))
	var/range4 = lighting_bench_time(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(lighting_bench_carry), spots, 4)) / length(spots)
	var/range7 = lighting_bench_time(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(lighting_bench_carry), spots, 7)) / length(spots)
	var/door = lighting_bench_time(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(lighting_bench_doors), doors)) / (2 * max(1, length(doors)))
	return "[label]: relight all [length(sources)] lights [round(relight, 0.1)] ms, moving range 4 light [round(range4, 0.001)] ms, range 7 [round(range7, 0.001)] ms, airlock [round(door, 0.001)] ms"

/**
 * Where a lamp's update goes ("lighting-bench=sections"), bounce lighting on: every lamp on the station is put through the parts of
 * update_corners() one at a time, cumulatively - BYOND's view() alone, then going through what it hands back for the turfs, then
 * reading their corners - and then through a whole update forced, and one for a door (vis_update()).
 */
/proc/lighting_bench_sections(z)
	SSlighting.set_bounce_lighting(TRUE)
	lighting_bench_flush()
	var/list/datum/light_source/lamps = list()
	for(var/obj/machinery/light/fitting in GLOB.machines)
		if(fitting.z == z && fitting.light && !QDELETED(fitting.light))
			lamps += fitting.light
	var/n = max(length(lamps), 1)
	var/atoms = 0
	var/turfs = 0
	var/start = TICK_USAGE_REAL
	for(var/datum/light_source/L as anything in lamps)
		var/turf/source = L.source_turf
		var/old = source.luminosity
		source.luminosity = ceil(L.light_reach * 1.5)
		var/list/seen = view(L.light_reach, source)
		source.luminosity = old
		atoms += length(seen)
	var/view_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
	start = TICK_USAGE_REAL
	for(var/datum/light_source/L as anything in lamps)
		var/turf/source = L.source_turf
		var/old = source.luminosity
		source.luminosity = ceil(L.light_reach * 1.5)
		for(var/turf/T in view(L.light_reach, source))
			turfs++
		source.luminosity = old
	var/loop_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
	start = TICK_USAGE_REAL
	var/corners = 0
	for(var/datum/light_source/L as anything in lamps)
		var/turf/source = L.source_turf
		var/old = source.luminosity
		source.luminosity = ceil(L.light_reach * 1.5)
		for(var/turf/T in view(L.light_reach, source))
			if((!IS_DYNAMIC_LIGHTING(T) && !T.light_sources) || IS_OPAQUE_TURF(T))
				continue
			if(T.lighting_corner_NE)
				corners++
			if(T.lighting_corner_SE)
				corners++
			if(T.lighting_corner_SW)
				corners++
			if(T.lighting_corner_NW)
				corners++
		source.luminosity = old
	var/corner_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
	start = TICK_USAGE_REAL
	for(var/datum/light_source/L as anything in lamps)
		L.force_update()
	lighting_bench_flush()
	var/force_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
	start = TICK_USAGE_REAL
	for(var/datum/light_source/L as anything in lamps)
		L.vis_update()
	lighting_bench_flush()
	var/vis_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
	var/effect_corners = 0
	var/bounce_corners = 0
	for(var/datum/light_source/L as anything in lamps)
		effect_corners += length(L.effect_str)
		bounce_corners += length(L.bounce_str)
	return list("[length(lamps)] lamps; each sees [round(atoms / n)] atoms, [round(turfs / n)] of them turfs, [round(corners / n)] corners on those; lights [round(effect_corners / n)] corners, bounces onto [round(bounce_corners / n)]",
		"  view() alone [round(1000 * view_ms / n)] us a lamp; + going through it for turfs [round(1000 * loop_ms / n)] us; + reading their corners [round(1000 * corner_ms / n)] us",
		"  whole update, forced [round(1000 * force_ms / n)] us a lamp; for a door (vis_update) [round(1000 * vis_ms / n)] us (both with the corner and lighting object stages after)")

/**
 * Lamps going dimmer and changing colour are relit where they are (/datum/light_source/proc/relight_in_place()), not worked out
 * afresh: checks that lights every tile exactly as working them out afresh does, and the bookkeeping still adds up.
 */
/proc/lighting_bench_in_place_check(z, mode)
	var/list/obj/machinery/light/fittings = list()
	for(var/obj/machinery/light/fitting in GLOB.machines)
		if(fitting.z == z && fitting.light && !QDELETED(fitting.light) && length(fittings) < 300)
			fittings += fitting
	var/list/was = list()
	for(var/obj/machinery/light/fitting as anything in fittings)
		was[fitting] = list(fitting.light_range, fitting.light_power, fitting.light_color)
	var/before = SSlighting.relit_in_place
	var/start = TICK_USAGE_REAL
	for(var/obj/machinery/light/fitting as anything in fittings)
		fitting.set_light(fitting.light_range, fitting.light_power * 0.83, "#FFD0A0")
	lighting_bench_flush()
	var/in_place_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
	var/in_place = SSlighting.relit_in_place - before
	lighting_bench_snapshot(z, "[LIGHTING_BENCH_DIR]snapshot_in_place_[mode].txt")
	start = TICK_USAGE_REAL
	for(var/obj/machinery/light/fitting as anything in fittings)
		fitting.light?.force_update()
	lighting_bench_flush()
	var/afresh_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
	lighting_bench_snapshot(z, "[LIGHTING_BENCH_DIR]snapshot_afresh_[mode].txt")
	. = list("relit in place: [length(fittings)] lamps dimmed and recoloured, [in_place] of them in place ([round(1000 * in_place_ms / max(1, length(fittings)))] us a lamp, afresh [round(1000 * afresh_ms / max(1, length(fittings)))] us): [lighting_bench_compare_snapshots("[LIGHTING_BENCH_DIR]snapshot_afresh_[mode].txt", "[LIGHTING_BENCH_DIR]snapshot_in_place_[mode].txt")]")
	. += lighting_bench_check()
	for(var/obj/machinery/light/fitting as anything in fittings)
		var/list/old = was[fitting]
		fitting.set_light(old[1], old[2], old[3])
	lighting_bench_flush()

/// With the engine on: whether every lighting object on the z-level draws what the engine's corners say it should
/proc/lighting_bench_objects_check(z)
	if(!SSlighting.native)
		return "objects check: only with the engine on"
	var/list/values = list()
	var/checked = 0
	var/list/wrong = list()
	for(var/turf/T as anything in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		var/atom/movable/lighting_object/O = T.lighting_object
		if(!O)
			continue
		checked++
		values.Cut()
		call_ext(LIGHTING_ENGINE_LIB, "byond:lighting_object")(T, values)
		var/was_state = O.icon_state
		var/list/was_color = O.color
		var/was_luminosity = O.luminosity
		O.draw(values[1], values[2], values[3], values[4], values[5], values[6], values[7], values[8], values[9], values[10], values[11], values[12], values[13])
		if(was_state != O.icon_state || was_luminosity != O.luminosity || jointext(was_color || list(), ",") != jointext(O.color || list(), ","))
			if(length(wrong) < 5)
				wrong += "([T.x],[T.y]) drew [was_state] [was_luminosity] [jointext(was_color || list(), ",")], should be [O.icon_state] [O.luminosity] [jointext(O.color || list(), ",")]"
			else
				wrong += "-"
	. = "objects check: [checked] lighting objects, [length(wrong)] not drawing what the engine has"
	for(var/line in wrong)
		if(line != "-")
			. += "\n  [line]"

/// With the engine on: corner "x|y" (as the engine numbers them, corners at x + 0.5) -> the light's strength there, direct or bounce
/proc/lighting_bench_native_light(datum/light_source/light)
	if(!SSlighting.native || !light?.native_id)
		return null
	var/list/values = list()
	call_ext(LIGHTING_ENGINE_LIB, "byond:lighting_light")(light.native_id, values)
	. = list()
	for(var/i = 1, i <= length(values), i += 4)
		var/key = "[values[i]]|[values[i + 1]]"
		.[key] = max(.[key], values[i + 2])

/**
 * The engine against the DM code ("lighting-bench=engines", booted with the engine on): everything relit from scratch by
 * each, then airlocks opened and closed and lights carried around by each, compared tile by tile. They should never differ.
 */
/proc/lighting_bench_engines(z, list/turf/spots, list/obj/machinery/door/airlock/doors)
	. = list()
	if(!SSlighting.native)
		. += "the engine isn't on ([SSlighting.native_status])"
		return
	SSlighting.set_bounce_lighting(TRUE)
	lighting_bench_flush()
	for(var/round in 1 to 2)
		SSlighting.native_failed("the lighting bench is comparing it with the DM code")
		lighting_bench_flush()
		lighting_bench_snapshot(z, "[LIGHTING_BENCH_DIR]snapshot_dm_relit.txt")
		if(round == 2)
			lighting_bench_doors(doors)
			lighting_bench_carry(spots.Copy(1, min(length(spots), 100) + 1), 7)
			lighting_bench_snapshot(z, "[LIGHTING_BENCH_DIR]snapshot_dm_worked.txt")
		var/start = TICK_USAGE_REAL
		if(!SSlighting.native_restart())
			. += "the engine wouldn't start again: [SSlighting.native_status]"
			return
		lighting_bench_flush()
		var/relight_ms = TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
		lighting_bench_snapshot(z, "[LIGHTING_BENCH_DIR]snapshot_engine_relit.txt")
		if(round == 1)
			. += "everything relit from scratch, engine against DM code: [lighting_bench_compare_snapshots("[LIGHTING_BENCH_DIR]snapshot_dm_relit.txt", "[LIGHTING_BENCH_DIR]snapshot_engine_relit.txt")] (engine relit it in [round(relight_ms)] ms)"
			. += lighting_bench_check()
		else
			lighting_bench_doors(doors)
			lighting_bench_carry(spots.Copy(1, min(length(spots), 100) + 1), 7)
			lighting_bench_snapshot(z, "[LIGHTING_BENCH_DIR]snapshot_engine_worked.txt")
			. += "after [length(doors)] airlocks opened and closed and a light carried to 100 spots, engine against DM code: [lighting_bench_compare_snapshots("[LIGHTING_BENCH_DIR]snapshot_dm_worked.txt", "[LIGHTING_BENCH_DIR]snapshot_engine_worked.txt")]"
			. += lighting_bench_check()
			. += lighting_bench_objects_check(z)

/// The median time a workload takes, in milliseconds
/proc/lighting_bench_time(datum/callback/workload)
	var/list/timings = list()
	for(var/i in 1 to LIGHTING_BENCH_REPEATS)
		var/start = TICK_USAGE_REAL
		workload.Invoke()
		timings += TICK_DELTA_TO_MS(TICK_USAGE_REAL - start)
	timings = sortList(timings, GLOBAL_PROC_REF(cmp_numeric_asc))
	return timings[ceil(length(timings) / 2)]

/// Relights everything, as at roundstart or when the whole station's power comes back
/proc/lighting_bench_relight(list/datum/light_source/sources)
	for(var/datum/light_source/L as anything in sources)
		L.force_update()
	lighting_bench_flush()

/// A light being carried around: moved to each spot in turn, relit each time
/proc/lighting_bench_carry(list/turf/spots, range)
	var/obj/effect/dummy/lighting_obj/carried = new(spots[1], LIGHT_COLOR_WHITE, range, 1)
	lighting_bench_flush()
	for(var/turf/T as anything in spots)
		carried.forceMove(T)
		lighting_bench_flush()
	qdel(carried)
	lighting_bench_flush()

/// Airlocks opening and closing, which makes every light that can see them look again
/proc/lighting_bench_doors(list/obj/machinery/door/airlock/doors)
	for(var/obj/machinery/door/airlock/door as anything in doors)
		door.set_opacity(FALSE)
		lighting_bench_flush()
		door.set_opacity(TRUE)
		lighting_bench_flush()

/// Relights every starlit space tile with the given power, light height, bounce lighting and range, and waits for it to settle
/proc/lighting_bench_set_starlight(power, height, bounce, range)
	for(var/turf/open/space/starlit as anything in GLOB.starlight)
		starlit.light_bounce = bounce
		starlit.set_light(range, power, GLOB.starlight_color, l_height = height)
		starlit.light?.force_update() // light_bounce alone isn't something a light source checks for
	lighting_bench_flush()

/// Processes everything SSlighting has queued, right now, without yielding
/**
 * The tone curve and eye adaptation (lighting_tone.dm, eye_adapt.dm): how bright corners get on the station before the curve;
 * snapshots with tg's cut-off and the curve at a few knees, for
 *   python tools/lighting_bench/render.py --before tone_1 --after tone_0.75
 * and how bright a player's view looks round the station, with the exposure their eyes would settle on (data/lighting_bench/
 * tone_eyes_<knee>.txt, every spot by area).
 */
/proc/lighting_bench_tone(z)
	. = list()
	var/old_knee = GLOB.lighting_tone_knee
	// The brightest channel of each lit corner, bounce light added as update_objects() adds it: what the curve goes by
	var/list/brightest = list()
	if(SSlighting.native)
		var/list/dump = list()
		call_ext(LIGHTING_ENGINE_LIB, "byond:lighting_dump")(z, dump)
		for(var/i = 1, i <= length(dump), i += 11)
			var/largest = 0
			for(var/k in 0 to 2)
				var/lum = dump[i + 2 + k]
				largest = max(largest, lum + dump[i + 5 + k] * clamp(1 - lum, 0, 1))
			if(largest > 0)
				brightest += largest
	else
		for(var/datum/lighting_corner/C)
			if(C.z != z || QDELETED(C))
				continue
			var/largest = max(C.lum_r + C.bounce_r * clamp(1 - C.lum_r, 0, 1), C.lum_g + C.bounce_g * clamp(1 - C.lum_g, 0, 1), C.lum_b + C.bounce_b * clamp(1 - C.lum_b, 0, 1))
			if(largest > 0)
				brightest += largest
	var/list/edges = list(0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 3)
	var/list/counts = list()
	counts.len = length(edges) + 1
	for(var/i in 1 to length(counts))
		counts[i] = 0
	for(var/largest in brightest)
		var/bin = length(edges) + 1
		for(var/e in 1 to length(edges))
			if(largest <= edges[e])
				bin = e
				break
		counts[bin]++
	var/list/hist = list()
	var/low = 0
	for(var/i in 1 to length(counts))
		hist += "[low]-[i <= length(edges) ? edges[i] : "up"]: [round(100 * counts[i] / max(1, length(brightest)), 0.1)]%"
		if(i <= length(edges))
			low = edges[i]
	. += "[length(brightest)] lit corners, by brightest channel: [jointext(hist, ", ")]"

	// Spots for eyes: up to four clear lit tiles in every area on the z-level, the same ones each run
	rand_seed(4242)
	var/list/area_spots = list()
	for(var/turf/T as anything in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		if(!T.lighting_object || IS_OPAQUE_TURF(T) || isspaceturf(T))
			continue
		var/area/A = T.loc
		LAZYADD(area_spots[A], T)
	for(var/area/A as anything in area_spots)
		var/list/turfs = area_spots[A]
		shuffle_inplace(turfs)
		turfs.Cut(min(length(turfs), 4) + 1)

	var/fake_view = "19x15" // the default widescreen view: 9 tiles each way, 7 up and down
	for(var/knee in list(1, 0.85, 0.75))
		SSlighting.set_tone(knee)
		var/old_limit = Master.current_ticklimit
		Master.current_ticklimit = INFINITY
		SSlighting.fire(FALSE, TRUE)
		Master.current_ticklimit = old_limit
		lighting_bench_flush()
		var/path = "[LIGHTING_BENCH_DIR]snapshot_tone_[knee].txt"
		lighting_bench_snapshot(z, path)
		if(SSlighting.native_shadow) // booted with lighting-engine=shadow: the DM curve and the engine's, every corner
			. += "knee [knee], [SSlighting.native_shadow_check(z)]"
		var/list/tiles = splittext(file2text(path), "\n")
		var/full = 0
		for(var/line in tiles)
			if(copytext(line, -1) == "L")
				full++
		// Eyes round the station
		var/list/eyes = list()
		var/list/exposures = list()
		var/list/by_band = list(0, 0, 0, 0)
		for(var/area/A as anything in area_spots)
			var/total_brightness = 0
			var/total_exposure = 0
			var/list/turfs = area_spots[A]
			for(var/turf/T as anything in turfs)
				var/brightness = SSeye_adapt.eye_brightness_at(T, 9, 7)
				var/exposure = brightness < 0 ? 1 : clamp(EYE_ADAPT_KEY / max(brightness, 0.01), 1, EYE_ADAPT_MAX)
				total_brightness += brightness
				total_exposure += exposure
				exposures += exposure
				by_band[exposure <= 1 ? 1 : exposure < 1.25 ? 2 : exposure < EYE_ADAPT_MAX ? 3 : 4]++
			eyes += "[round(total_brightness / length(turfs), 0.01)]\t[round(total_exposure / length(turfs), 0.01)]\t[A.name] ([A.type])"
		eyes = sortList(eyes)
		text2file("brightness\texposure\tarea ([length(exposures)] spots, view [fake_view], knee [knee])\n[jointext(eyes, "\n")]", "[LIGHTING_BENCH_DIR]tone_eyes_[knee].txt")
		. += "knee [knee]: [full] of [length(tiles)] lit tiles drawn at full; eyes at [length(exposures)] spots in [length(area_spots)] areas: \
			[round(100 * by_band[1] / max(1, length(exposures)))]% left as they are, [round(100 * by_band[2] / max(1, length(exposures)))]% turned up under 1.25x, \
			[round(100 * by_band[3] / max(1, length(exposures)))]% 1.25x up to [EYE_ADAPT_MAX]x, [round(100 * by_band[4] / max(1, length(exposures)))]% at [EYE_ADAPT_MAX]x"
	SSlighting.set_tone(old_knee)
	var/old_limit = Master.current_ticklimit
	Master.current_ticklimit = INFINITY
	SSlighting.fire(FALSE, TRUE)
	Master.current_ticklimit = old_limit
	lighting_bench_flush()

/proc/lighting_bench_flush()
	var/old_limit = Master.current_ticklimit
	Master.current_ticklimit = INFINITY // init_tick_checks mode only stops for CHECK_TICK, which this turns off
	while(length(SSlighting.sources_queue) || length(SSlighting.corners_queue) || length(SSlighting.objects_queue))
		SSlighting.fire(FALSE, TRUE)
	Master.current_ticklimit = old_limit

/**
 * Checks the lighting engine's bookkeeping adds up: that every corner's light is exactly what the light sources
 * affecting it say they're giving it, and that corners and light sources agree on which affects which.
 */
/proc/lighting_bench_check()
	if(SSlighting.native) // the engine checks its own books: see tools/lighting_engine/src/engine.rs, Engine::check()
		var/native_problems = call_ext(LIGHTING_ENGINE_LIB, "byond:lighting_check")()
		return list("bookkeeping check (the engine's): [native_problems ? "[native_problems] PROBLEMS (see the server's error output)" : "all consistent"]")
	var/list/problems = list()
	var/list/expected = list() // corner -> list(red, green, blue, bounce red, bounce green, bounce blue)
	var/checked_sources = 0
	for(var/datum/light_source/L)
		if(QDELETED(L))
			continue
		checked_sources++
		for(var/datum/lighting_corner/C as anything in (L.effect_str || list()) + (L.bounce_str || list()))
			if(QDELETED(C))
				problems += "a light source still affects a deleted corner at [C.x],[C.y]"
		for(var/datum/lighting_corner/C as anything in L.effect_str)
			if(LAZYACCESS(L.bounce_str, C))
				problems += "a light source both lights and bounces light onto a corner at [C.x],[C.y]"
			if(!(L in C.affecting))
				problems += "a corner at [C.x],[C.y] doesn't know a light source lights it"
			var/list/sums = expected[C] || (expected[C] = list(0, 0, 0, 0, 0, 0))
			var/strength = L.effect_str[C]
			sums[1] += strength * L.applied_lum_r
			sums[2] += strength * L.applied_lum_g
			sums[3] += strength * L.applied_lum_b
		for(var/datum/lighting_corner/C as anything in L.bounce_str)
			if(!(L in C.affecting))
				problems += "a corner at [C.x],[C.y] doesn't know a light source bounces light onto it"
			var/list/sums = expected[C] || (expected[C] = list(0, 0, 0, 0, 0, 0))
			var/strength = L.bounce_str[C]
			sums[4] += strength * L.applied_lum_r
			sums[5] += strength * L.applied_lum_g
			sums[6] += strength * L.applied_lum_b
	var/checked_corners = 0
	var/bounced_corners = 0
	for(var/datum/lighting_corner/C)
		if(QDELETED(C))
			continue
		checked_corners++
		var/list/sums = expected[C] || list(0, 0, 0, 0, 0, 0)
		if(abs(C.lum_r - sums[1]) > 0.001 || abs(C.lum_g - sums[2]) > 0.001 || abs(C.lum_b - sums[3]) > 0.001)
			problems += "a corner at [C.x],[C.y] has light [C.lum_r],[C.lum_g],[C.lum_b], but its light sources give it [sums[1]],[sums[2]],[sums[3]]"
		if(abs(C.bounce_r - sums[4]) > 0.001 || abs(C.bounce_g - sums[5]) > 0.001 || abs(C.bounce_b - sums[6]) > 0.001)
			problems += "a corner at [C.x],[C.y] has bounce light [C.bounce_r],[C.bounce_g],[C.bounce_b], but its light sources give it [sums[4]],[sums[5]],[sums[6]]"
		if(sums[4] || sums[5] || sums[6])
			bounced_corners++
		var/list/seen = list()
		for(var/datum/light_source/L as anything in C.affecting)
			if(seen[L])
				problems += "a corner at [C.x],[C.y] lists a light source affecting it twice"
			seen[L] = TRUE
			if(isnull(LAZYACCESS(L.effect_str, C)) && isnull(LAZYACCESS(L.bounce_str, C)))
				problems += "a corner at [C.x],[C.y] thinks a light source affects it, but it doesn't"
	. = list("bookkeeping check: [checked_sources] light sources, [checked_corners] corners ([bounced_corners] with bounce light): [length(problems) ? "[length(problems)] PROBLEMS" : "all consistent"]")
	for(var/i in 1 to min(length(problems), 10))
		. += "  [problems[i]]"

/**
 * Checks light never gets brighter further out along a straight, open line from its source. Bounce light spilling out
 * brighter than it arrived shows up that way: a dark band, then a glow beyond it.
 *
 * Puts lights of a few sizes at each spot and walks out from them in each direction until something opaque (or unlit), reading
 * that light's own contribution (direct or bounce) at the far corners of each tile along the way.
 */
/proc/lighting_bench_falloff_check(list/turf/spots)
	var/walks = 0
	var/list/problems = list()
	for(var/range in list(3, 4, 7, 8))
		for(var/turf/spot as anything in spots)
			var/obj/effect/dummy/lighting_obj/probe = new(spot, LIGHT_COLOR_WHITE, range, 1)
			lighting_bench_flush()
			var/datum/light_source/light = probe.light
			var/list/native_map = lighting_bench_native_light(light)
			for(var/direction in GLOB.cardinals)
				walks++
				var/turf/T = spot
				var/previous = INFINITY
				for(var/distance in 1 to ceil(range * SSlighting.falloff_tail) + SSlighting.bounce_depth + 1)
					T = get_step(T, direction)
					// Nor past a turf that isn't lit dynamically, like space off the edge of the station: no light is drawn there,
					// so lights don't keep track of it, and read as dark across it - then light again past it, if they reach
					if(!T || IS_OPAQUE_TURF(T) || (!IS_DYNAMIC_LIGHTING(T) && !T.light_sources))
						break
					var/list/far_corners
					switch(direction)
						if(NORTH)
							far_corners = list(T.lighting_corner_NW, T.lighting_corner_NE)
						if(SOUTH)
							far_corners = list(T.lighting_corner_SW, T.lighting_corner_SE)
						if(EAST)
							far_corners = list(T.lighting_corner_NE, T.lighting_corner_SE)
						if(WEST)
							far_corners = list(T.lighting_corner_NW, T.lighting_corner_SW)
					var/here = 0
					if(native_map)
						var/list/far = list()
						switch(direction)
							if(NORTH)
								far = list("[T.x - 1]|[T.y]", "[T.x]|[T.y]")
							if(SOUTH)
								far = list("[T.x - 1]|[T.y - 1]", "[T.x]|[T.y - 1]")
							if(EAST)
								far = list("[T.x]|[T.y]", "[T.x]|[T.y - 1]")
							if(WEST)
								far = list("[T.x - 1]|[T.y]", "[T.x - 1]|[T.y - 1]")
						for(var/key in far)
							here = max(here, native_map[key])
					for(var/datum/lighting_corner/C in far_corners)
						here = max(here, LAZYACCESS(light?.effect_str, C), LAZYACCESS(light?.bounce_str, C))
					if(here > previous + 0.001)
						problems += "range [range] light at [spot.x],[spot.y] going [dir2text(direction)]: [round(previous, 0.001)] then [round(here, 0.001)] [distance] tiles out"
					previous = here
			qdel(probe)
			lighting_bench_flush()
	. = list("falloff check: [walks] straight lines out from [length(spots) * 4] lights: [length(problems) ? "[length(problems)] GET BRIGHTER FURTHER OUT" : "light only ever fades"]")
	for(var/i in 1 to min(length(problems), 5))
		. += "  [problems[i]]"

/**
 * Writes what every lit tile on the z-level looks like: its corners' colors, as its lighting object draws them.
 *
 * One line per tile with a lighting object: "x y visible" then red, green and blue for the southwest, southeast,
 * northwest and northeast corners - or just "x y visible L" for fully lit tiles and "x y visible D" for dark ones.
 */
/proc/lighting_bench_snapshot(z, path)
	var/list/out = list()
	var/list/native_corners = list()
	for(var/turf/T as anything in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		var/atom/movable/lighting_object/object = T.lighting_object
		if(!object)
			continue
		if(SSlighting.native) // the engine keeps the corners: NE, SE, SW, NW, each light (3), bounce (3), colour (3), brightest
			native_corners.Cut()
			call_ext(LIGHTING_ENGINE_LIB, "byond:lighting_corners")(T, native_corners)
			var/list/native_values = list()
			var/native_sum = 0
			for(var/corner in list(3, 2, 4, 1)) // SW, SE, NW, NE
				var/at = (corner - 1) * 10 + 7
				native_values += list(native_corners[at], native_corners[at + 1], native_corners[at + 2])
				native_sum += native_corners[at] + native_corners[at + 1] + native_corners[at + 2]
			var/native_prefix = "[T.x] [T.y] [object.luminosity ? 1 : 0]"
			if(native_sum >= 12)
				out += "[native_prefix] L"
			else if(!native_sum)
				out += "[native_prefix] D"
			else
				out += "[native_prefix] [jointext(native_values, " ")]"
			continue
		var/list/values = list()
		var/sum = 0
		for(var/datum/lighting_corner/C in list(T.lighting_corner_SW, T.lighting_corner_SE, T.lighting_corner_NW, T.lighting_corner_NE))
			values += list(C.cache_r, C.cache_g, C.cache_b)
			sum += C.cache_r + C.cache_g + C.cache_b
		var/prefix = "[T.x] [T.y] [object.luminosity ? 1 : 0]"
		if(length(values) == 12 && sum >= 12)
			out += "[prefix] L"
		else if(!sum)
			out += "[prefix] D"
		else
			// a missing corner is dark, as it is to the lighting object
			var/list/padded = list()
			for(var/datum/lighting_corner/C as anything in list(T.lighting_corner_SW, T.lighting_corner_SE, T.lighting_corner_NW, T.lighting_corner_NE))
				padded += C ? "[C.cache_r] [C.cache_g] [C.cache_b]" : "0 0 0"
			out += "[prefix] [jointext(padded, " ")]"
	text2file(jointext(out, "\n"), path)

#undef LIGHTING_BENCH_DIR
#undef LIGHTING_BENCH_REPEATS
#undef LIGHTING_BENCH_MOVES
#undef LIGHTING_BENCH_DOORS

/// Compares two snapshots from lighting_bench_snapshot(), tile by tile
/// How many tiles two snapshots have differently lit (-1 if they don't have the same tiles)
/proc/lighting_bench_count_differences(path_a, path_b)
	var/list/a = splittext(file2text(path_a), "\n")
	var/list/b = splittext(file2text(path_b), "\n")
	if(length(a) != length(b))
		return -1
	. = 0
	for(var/i in 1 to length(a))
		if(a[i] != b[i])
			.++

/proc/lighting_bench_compare_snapshots(path_a, path_b)
	var/list/a = splittext(file2text(path_a), "\n")
	var/list/b = splittext(file2text(path_b), "\n")
	if(length(a) != length(b))
		return "DIFFERENT TILES LIT ([length(a)] vs [length(b)])"
	var/differing = 0
	for(var/i in 1 to length(a))
		if(a[i] != b[i])
			differing++
	return differing ? "[differing] TILES DIFFER from how they booted" : "every tile as it booted"
