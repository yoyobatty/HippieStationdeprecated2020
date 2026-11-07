// The lighting engine (tools/lighting_engine, hippie_lighting.dll). DM still decides when a light needs working out and finds
// what it can see with view(), as it always has; the engine does the rest - what each corner gets, its bounce light, what
// each lighting object draws - with the same sums in the same order as the DM code it stands in for
// (/datum/light_source/proc/update_corners() and co.), and keeps the corners itself. Lighting objects are still drawn here.
// Without the DLL, or if it ever fails, the DM code relights everything from scratch and carries on as before.
//
// World params:  lighting-engine=dm      the DM code only
//                lighting-engine=shadow  the DM code lights the station and the engine follows along with every change:
//                                        native_shadow_check() compares every corner (tools/lighting_bench, stress bench)
//
// The engine keeps four things about each turf (lighting_engine_flags()) and is told whenever one changes: the turf's
// has_opaque_atom, its dynamic_lighting, whether it has light sources of its own, and whether it has a lighting object.

/// How many lighting objects to draw per call to the engine
#define LIGHTING_ENGINE_BATCH 400

/datum/controller/subsystem/lighting
	/// The engine works the lighting out
	var/native = FALSE
	/// The DM code works it out, and the engine follows along to be compared with it
	var/native_shadow = FALSE
	/// Turfs can tell the engine about themselves: their flags have all been handed over
	var/native_flags_ready = FALSE
	/// Why the engine is or isn't running
	var/native_status = "not started"
	/// Light source ids, as the engine knows them -> the light source
	var/list/datum/light_source/native_lights = list()
	var/list/native_free_ids = list()
	/// Light sheet number -> whether the engine has it
	var/list/native_sheets_sent = list()
	/// The world's size when the engine was set up: it numbers turfs by it
	var/native_maxx = 0
	var/native_maxy = 0

/datum/light_source
	/// What the engine knows us by, or 0
	var/native_id = 0
	/// lighting_sheet_number() of our sheet, set alongside it by get_sheet()
	var/sheet_id = 0
	/// lighting_sheet_number() of the sheet our scattered light spills from, set by get_scatter_sheet()
	var/spill_sheet_id = 0

/// Light sheet key -> its number, and number -> the sheet, for the engine
GLOBAL_LIST_EMPTY(lighting_sheet_numbers)
GLOBAL_LIST_EMPTY(lighting_sheet_list)

/proc/lighting_sheet_number(key, list/sheet)
	. = GLOB.lighting_sheet_numbers[key]
	if(!.)
		GLOB.lighting_sheet_list += list(sheet)
		. = length(GLOB.lighting_sheet_list)
		GLOB.lighting_sheet_numbers[key] = .

/// Starts the engine, unless the world params say not to or it isn't there. Called in Initialize(), before the first lights
/// are worked out; their turfs' flags are handed over by native_ready() once the lighting objects and starlight are up.
/datum/controller/subsystem/lighting/proc/native_setup()
	var/mode = world.params["lighting-engine"]
	if(mode == "dm")
		native_status = "off (lighting-engine=dm)"
		log_world("Lighting: worked out in DM ([native_status])")
		return
	var/list/turfs = list()
	var/list/coordinates = list()
	for(var/list/spot in list(list(1, 1, 1), list(world.maxx, 1, 1), list(1, world.maxy, 1), list(world.maxx, world.maxy, world.maxz), list(round(world.maxx / 2), round(world.maxy / 3), max(1, world.maxz - 1))))
		var/turf/T = locate(spot[1], spot[2], spot[3])
		if(T)
			turfs += T
			coordinates += spot
	var/result
	try
		result = call_ext(LIGHTING_ENGINE_LIB, "byond:lighting_setup")(world.maxx, world.maxy, world.maxz, turfs, coordinates)
	catch(var/exception/error)
		result = "[error]"
	if(result != LIGHTING_ENGINE_VERSION)
		native_status = "off: [result]"
		log_world("Lighting: worked out in DM ([native_status])")
		return
	native_maxx = world.maxx
	native_maxy = world.maxy
	if(mode == "shadow")
		native_shadow = TRUE
		native_status = "shadowing the DM code"
	else
		native = TRUE
		native_status = "on"

/// Hands every turf's flags over: from here on, turfs tell the engine when theirs change
/datum/controller/subsystem/lighting/proc/native_ready()
	if(!LIGHTING_ENGINE_ON)
		return
	var/list/flags = list()
	for(var/turf/T in world)
		var/turf_flags = T.lighting_engine_flags()
		T.lighting_engine_pushed = turf_flags // what the engine will have, so a push that changes nothing can be skipped
		if(turf_flags)
			flags.Add(T, turf_flags)
	var/result = call_ext(LIGHTING_ENGINE_LIB, "byond:lighting_flags")(flags)
	if(result < 0)
		native_failed("handing over turfs: [result]")
		return
	native_flags_ready = TRUE
	log_world("Lighting: engine [native_status], [round(length(flags) / 2)] turfs handed over")

/// Something went wrong with the engine: the DM code takes over, relighting everything from scratch
/datum/controller/subsystem/lighting/proc/native_failed(reason)
	if(!LIGHTING_ENGINE_ON)
		return
	var/was_native = native
	native = FALSE
	native_shadow = FALSE
	native_flags_ready = FALSE
	native_status = "failed: [reason]"
	log_world("Lighting: the engine [native_status], switching to the DM code")
	stack_trace("Lighting: the engine [native_status]")
	native_lights.Cut()
	native_free_ids.Cut()
	native_sheets_sent.Cut()
	if(!was_native)
		for(var/datum/light_source/L)
			L.native_id = 0
		return
	// Any corners the DM code had before the engine took over hold light from back then: start them dark
	for(var/datum/lighting_corner/C)
		C.lum_r = 0
		C.lum_g = 0
		C.lum_b = 0
		C.bounce_r = 0
		C.bounce_g = 0
		C.bounce_b = 0
		C.affecting = null
	for(var/datum/light_source/L)
		L.native_id = 0
		if(QDELETED(L))
			continue
		L.effect_str = null
		L.bounce_str = null
		L.bounce_levels = null
		L.applied = FALSE
		L.force_update()

/// Starts the engine afresh and has it relight everything from scratch (the lighting bench's engine comparison)
/datum/controller/subsystem/lighting/proc/native_restart()
	native_lights.Cut()
	native_free_ids.Cut()
	native_sheets_sent.Cut()
	native = FALSE
	native_shadow = FALSE
	native_flags_ready = FALSE
	native_setup()
	native_ready()
	if(!native)
		return FALSE
	for(var/datum/light_source/L)
		L.native_id = 0
		if(QDELETED(L))
			continue
		L.effect_str = null
		L.bounce_str = null
		L.bounce_levels = null
		L.applied = FALSE
		L.force_update()
	return TRUE

/datum/controller/subsystem/lighting/proc/native_id_for(datum/light_source/L)
	var/id
	if(length(native_free_ids))
		id = native_free_ids[length(native_free_ids)]
		native_free_ids.len--
	else
		id = length(native_lights) + 1
		native_lights.len = id
	native_lights[id] = L
	L.native_id = id
	return id

/// The light source is gone: the engine takes its light off and forgets it
/datum/controller/subsystem/lighting/proc/native_forget(datum/light_source/L)
	var/id = L.native_id
	L.native_id = 0
	if(!id)
		return
	call_ext(LIGHTING_ENGINE_LIB, "byond:lighting_forget")(id)
	if(id <= length(native_lights))
		native_lights[id] = null
		native_free_ids += id

/datum/controller/subsystem/lighting/proc/native_send_sheet(number)
	if(number <= length(native_sheets_sent) && native_sheets_sent[number])
		return TRUE
	if(number > length(native_sheets_sent))
		native_sheets_sent.len = number
	var/list/rows = GLOB.lighting_sheet_list[number]
	var/list/flat = list()
	for(var/list/row as anything in rows)
		flat += row
	var/result = call_ext(LIGHTING_ENGINE_LIB, "byond:lighting_sheet")(number, length(rows), flat)
	if(result != 1)
		native_failed("sheet [number]: [result]")
		return FALSE
	native_sheets_sent[number] = TRUE
	return TRUE

/// update_corners() once it's looked around: the engine does the rest
/datum/controller/subsystem/lighting/proc/native_update(datum/light_source/L, list/seen, vis_only, bounces, scatters)
	var/spill = scatters ? L.spill_sheet_id : L.sheet_id
	if(!native_send_sheet(L.sheet_id) || !native_send_sheet(spill))
		return
	var/turf/T = L.source_turf
	var/result = call_ext(LIGHTING_ENGINE_LIB, "byond:lighting_update")(L.native_id || native_id_for(L), T.x, T.y, T.z, L.light_reach, L.light_power, L.lum_r, L.lum_g, L.lum_b, \
		L.sheet_id, spill, (vis_only ? 1 : 0) | (bounces ? 2 : 0) | (scatters ? 4 : 0), bounce_cutoff, bounce_strength, bounce_falloff, bounce_cutoff, bounce_depth, seen)
	if(result != 1)
		native_failed("update: [result]")

/// SSlighting's corner and lighting object stages, from the engine. TRUE if it got through everything.
/datum/controller/subsystem/lighting/proc/native_draw(init_tick_checks)
	if(world.maxx != native_maxx || world.maxy != native_maxy)
		native_failed("the world changed size")
		return TRUE
	// Lighting objects made since: they draw what the engine has for their turf
	var/list/queue = objects_queue
	var/i = 0
	var/list/values = list()
	while(i < length(queue))
		i++
		var/atom/movable/lighting_object/O = queue[i]
		if(QDELETED(O) || !isturf(O.myturf))
			continue
		values.Cut()
		call_ext(LIGHTING_ENGINE_LIB, "byond:lighting_object")(O.myturf, values)
		if(length(values) == 13)
			O.draw(values[1], values[2], values[3], values[4], values[5], values[6], values[7], values[8], values[9], values[10], values[11], values[12], values[13])
		O.needs_update = FALSE
		if(init_tick_checks)
			CHECK_TICK
		else if(MC_TICK_CHECK)
			break
	if(i)
		queue.Cut(1, i + 1)
	if(length(queue))
		return FALSE
	// Then the engine's: the corners it changed, and the lighting objects that draw them
	var/list/out = list()
	var/left = 1
	while(left > 0)
		out.Cut()
		left = call_ext(LIGHTING_ENGINE_LIB, "byond:lighting_flush")(LIGHTING_ENGINE_BATCH, out)
		if(!isnum(left) || left < 0)
			native_failed("drawing: [left]")
			return TRUE
		for(var/at = 1, at <= length(out), at += 14)
			var/turf/T = out[at]
			var/atom/movable/lighting_object/O = T.lighting_object
			if(O)
				O.draw(out[at + 1], out[at + 2], out[at + 3], out[at + 4], out[at + 5], out[at + 6], out[at + 7], out[at + 8], out[at + 9], out[at + 10], out[at + 11], out[at + 12], out[at + 13])
		if(init_tick_checks)
			CHECK_TICK
		else if(left > 0 && MC_TICK_CHECK)
			return FALSE
	return TRUE

/// What the engine keeps about a turf
/turf/proc/lighting_engine_flags()
	. = 0
	if(has_opaque_atom)
		. |= LIGHTING_FLAG_OPAQUE
	if(dynamic_lighting)
		. |= LIGHTING_FLAG_DYNAMIC
	if(length(light_sources))
		. |= LIGHTING_FLAG_SOURCES
	if(lighting_object)
		. |= LIGHTING_FLAG_OBJECT

/turf
	/// The flags the engine was last told for this turf, -1 if it may have something else (a turf made since it was told)
	var/tmp/lighting_engine_pushed = -1

/// Tells the engine this turf's flags, if they changed since it was last told
/turf/proc/lighting_engine_push()
	if(SSlighting.native_flags_ready)
		var/flags = lighting_engine_flags()
		if(flags != lighting_engine_pushed)
			lighting_engine_pushed = flags
			call_ext(LIGHTING_ENGINE_LIB, "byond:lighting_flag")(src, flags)

/// Compares the DM code's corners on a z-level with the engine's, every value exactly, in the shadow check. Returns a line.
/datum/controller/subsystem/lighting/proc/native_shadow_check(z)
	if(!native_shadow)
		return "shadow check: the engine isn't shadowing the DM code ([native_status])"
	// Both up to date: the DM code's corner stage, and the engine's
	var/old_limit = Master.current_ticklimit
	Master.current_ticklimit = INFINITY
	while(length(sources_queue) || length(corners_queue) || length(objects_queue))
		fire(FALSE, TRUE)
	Master.current_ticklimit = old_limit
	var/list/dump = list()
	call_ext(LIGHTING_ENGINE_LIB, "byond:lighting_dump")(z, dump)
	var/list/native_at = list()
	for(var/i = 1, i <= length(dump), i += 11)
		native_at["[dump[i]]|[dump[i + 1]]"] = i
	var/checked = 0
	var/drawn_differently = 0
	var/list/wrong = list()
	var/list/seen_keys = list()
	for(var/datum/lighting_corner/C)
		if(QDELETED(C) || C.z != z)
			continue
		checked++
		var/key = "[C.x - 0.5]|[C.y - 0.5]"
		seen_keys[key] = TRUE
		var/at = native_at[key]
		var/list/mine = list(C.lum_r, C.lum_g, C.lum_b, C.bounce_r, C.bounce_g, C.bounce_b, C.cache_r, C.cache_g, C.cache_b)
		var/list/theirs = at ? dump.Copy(at + 2, at + 11) : list(0, 0, 0, 0, 0, 0, 0, 0, 0)
		if(mine[7] != theirs[7] || mine[8] != theirs[8] || mine[9] != theirs[9])
			drawn_differently++
		for(var/k in 1 to 9)
			if(mine[k] != theirs[k])
				if(length(wrong) < 8)
					var/list/mine_text = list()
					var/list/theirs_text = list()
					for(var/v in 1 to 9)
						mine_text += num2text(mine[v], 12)
						theirs_text += num2text(theirs[v], 12)
					var/list/lights = list()
					for(var/datum/light_source/L as anything in C.affecting)
						lights += "[L.source_atom?.type] at [L.source_turf?.x],[L.source_turf?.y]"
					wrong += "([key]) DM [jointext(mine_text, ",")] engine [jointext(theirs_text, ",")] lights: [jointext(lights, "; ")]"
				else
					wrong += "-"
				break
	var/engine_only = 0
	for(var/key in native_at)
		if(!seen_keys[key])
			engine_only++
	var/books = call_ext(LIGHTING_ENGINE_LIB, "byond:lighting_check")()
	. = "shadow check z[z]: [checked] DM corners, [length(native_at)] lit in the engine; [length(wrong)] differ, [drawn_differently] of them in the colour drawn; [engine_only] lit only in the engine; engine's books: [books] problems"
	for(var/line in wrong)
		if(line != "-")
			. += "\n  [line]"

#undef LIGHTING_ENGINE_BATCH
