// What blocks a blast on each turf, kept as things come and go, for CaculateExplosionBlock(). It read every object on every tile of
// the blast, and almost none of them block anything: 3.4 ms for a maxcap's 1,681 tiles and 32 ms for a range-50 blast's 10,000 on a
// fresh Hippie Station, without the air (7.4 and 56 ms in a profiled round). Now 1.6 and 9.6 ms (tools/explosion_preview/block_bench.dm).
//  - Each turf keeps what its objects with a fixed block add up to (explosion_block_static), and a list of the ones that work theirs
//    out each time (explosion_block EXPLOSION_BLOCK_PROC: doors while shut, windows while reinforced and full-tile), which are asked
//    as before. The turf's own block is read as before, so a wall going up or coming down needs nothing.
//  - An object is counted on the turf it's on (explosion_block_turf) once it's initialised (SSatoms InitAtom()), and again whenever it
//    moves (Moved(), moveToNullspace(), a shuttle setting loc) or has explosion_block var-edited. ChangeTurf() takes the counts across
//    to the new turf, as the objects stay.
//  - Moved() reads one var for everything else: explosion_block. So anything that sets explosion_block once the object's initialised
//    calls explosion_block_refresh() after (vv_edit_var() below does), or a blocker set to 0 would stay counted where it was.
//  - Reading a turf's own vars is slow (BYOND 516.1689, the station: 275 to 670 ns each, more once a round has gone on), its builtins
//    (x, y, density) and a list entry quick. So a grid for each z-level (explosion_block_grids) marks the turfs with anything counted,
//    and CaculateExplosionBlock() reads only those turfs' cache vars.
//  - The answer is an alist: building a list keyed by turfs costs about 0.5 to 1.3 us a turf, an alist 0.2. explosion_shape() answers
//    with one too.
// World params: explosion-block-cache=off for the old loop; explosion-block-check=1 has every blast's blocks checked against the old
// loop as it goes off (differences in the world log). The admins' Debug verb "Check Explosion Block Cache" recounts the whole map.
// tools/explosion_preview/run_block_bench.sh times it and checks it through a round.

GLOBAL_VAR_INIT(explosion_block_cache, world.params["explosion-block-cache"] != "off")
GLOBAL_VAR_INIT(explosion_block_check, !!text2num(world.params["explosion-block-check"]))
/// For the check: blasts checked, and ones whose blocks came out different
GLOBAL_VAR_INIT(explosion_block_checked, 0)
GLOBAL_VAR_INIT(explosion_block_differed, 0)
/// z -> null, or a list over that level ((y - 1) * width + x) that's TRUE where the turf has anything counted (explosion_block_static
/// or explosion_block_dynamic), so the blast reads only those turfs' vars
GLOBAL_LIST_EMPTY(explosion_block_grids)
/// The world.maxx and maxy the grids were made for: if the world grows they're made again (explosion_block_grid())
GLOBAL_VAR_INIT(explosion_block_grid_width, 0)
GLOBAL_VAR_INIT(explosion_block_grid_height, 0)

/turf
	/// What the objects counted here with a fixed explosion_block add up to
	var/explosion_block_static = 0
	/// The objects counted here whose block is worked out each time (explosion_block EXPLOSION_BLOCK_PROC), or null
	var/list/explosion_block_dynamic

/atom/movable
	/// The turf this is counted on for explosion blocks, or null
	var/turf/explosion_block_turf
	/// What it was counted as there: its explosion_block then (EXPLOSION_BLOCK_PROC for the turf's list)
	var/explosion_block_counted = 0

/// Takes this off the turf it was counted on and counts it on the one it's on now, as its explosion_block is now. Safe to call any
/// time; only objects on a turf with a block are counted, as the old loop only read objects on the turf.
/atom/movable/proc/explosion_block_refresh()
	var/turf/old = explosion_block_turf
	if(old)
		explosion_block_turf = null
		if(explosion_block_counted == EXPLOSION_BLOCK_PROC)
			LAZYREMOVE(old.explosion_block_dynamic, src)
		else
			old.explosion_block_resum()
		explosion_block_counted = 0
		old.explosion_block_mark()
	var/block = explosion_block
	var/turf/T = loc
	if(!block || !isturf(T) || !isobj(src))
		return
	explosion_block_turf = T
	explosion_block_counted = block
	if(block == EXPLOSION_BLOCK_PROC)
		LAZYADD(T.explosion_block_dynamic, src)
	else
		T.explosion_block_resum()
	T.explosion_block_mark()

/// Adds up the fixed blocks counted here afresh, in the order the objects are here, as the old loop did. Only when one of them comes,
/// goes or changes, which is rare: on the station only blob structures have a fixed block.
/turf/proc/explosion_block_resum()
	var/total = 0
	for(var/obj/O in src)
		if(O.explosion_block_turf == src && O.explosion_block_counted != EXPLOSION_BLOCK_PROC)
			total += O.explosion_block_counted
	explosion_block_static = total

/// Marks this turf on its level's grid if it has anything counted, or clears it
/turf/proc/explosion_block_mark()
	var/has = explosion_block_static || explosion_block_dynamic
	var/list/grid = explosion_block_grid(z, has)
	if(grid)
		grid[(y - 1) * GLOB.explosion_block_grid_width + x] = has ? TRUE : null

/// The grid for level `z`, made if `make` and it's not there yet: null for a level with nothing counted on it
/proc/explosion_block_grid(z, make)
	var/list/grids = GLOB.explosion_block_grids
	if(GLOB.explosion_block_grid_width != world.maxx || GLOB.explosion_block_grid_height != world.maxy)
		explosion_block_regrid()
		grids = GLOB.explosion_block_grids
	if(z > length(grids))
		if(!make)
			return null
		grids.len = z
	. = grids[z]
	if(!. && make)
		. = new /list(world.maxx * world.maxy)
		grids[z] = .

/// The grids made afresh from every turf's vars, for a world that's grown (or the first time): a few hundred ms over the whole map
/proc/explosion_block_regrid()
	var/had = GLOB.explosion_block_grid_width
	GLOB.explosion_block_grid_width = world.maxx
	GLOB.explosion_block_grid_height = world.maxy
	GLOB.explosion_block_grids = list()
	if(!had)
		return //nothing's been counted yet
	for(var/z in 1 to world.maxz)
		for(var/turf/T as anything in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
			if(T.explosion_block_static || T.explosion_block_dynamic)
				T.explosion_block_mark()

/atom/movable/moveToNullspace()
	. = ..()
	if(explosion_block_turf)
		explosion_block_refresh()

/atom/movable/onShuttleMove(turf/newT, turf/oldT, list/movement_force, move_dir, obj/docking_port/stationary/old_dock, obj/docking_port/mobile/moving_dock)
	. = ..()
	if(explosion_block || explosion_block_turf) // it set loc, without Moved()
		explosion_block_refresh()

/atom/movable/vv_edit_var(var_name, var_value)
	. = ..()
	if(var_name == "explosion_block")
		explosion_block_refresh()

/// Turf -> its explosion block, for every turf in the list: the turf's own while it's dense, and what's on it.
/datum/controller/subsystem/explosions/CaculateExplosionBlock(list/affected_turfs)
	if(!GLOB.explosion_block_cache)
		return ..()
	. = alist()
	var/width = GLOB.explosion_block_grid_width
	var/z = 0
	var/list/grid
	for(var/turf/T as anything in affected_turfs)
		if(T.z != z)
			z = T.z
			grid = explosion_block_grid(z, FALSE)
			width = GLOB.explosion_block_grid_width
		var/block = T.density ? T.explosion_block : 0
		if(grid && grid[(T.y - 1) * width + T.x])
			block += T.explosion_block_static
			var/list/dynamic = T.explosion_block_dynamic
			if(dynamic)
				for(var/obj/O as anything in dynamic)
					var/b = O.explosion_block
					block += b == EXPLOSION_BLOCK_PROC ? O.GetExplosionBlock() : b
		.[T] = block
	if(GLOB.explosion_block_check)
		explosion_block_check_blast(., affected_turfs)

/// The old loop, every object on every turf, as tg's CaculateExplosionBlock() has it: for the checks
/proc/explosion_block_recount_list(list/affected_turfs)
	. = list()
	for(var/turf/T as anything in affected_turfs)
		var/block = T.density ? T.explosion_block : 0
		for(var/obj/O in T)
			var/b = O.explosion_block
			block += b == EXPLOSION_BLOCK_PROC ? O.GetExplosionBlock() : b
		.[T] = block

/// explosion-block-check=1: one blast's blocks against the old loop
/proc/explosion_block_check_blast(list/blocks, list/affected_turfs)
	GLOB.explosion_block_checked++
	var/list/old = explosion_block_recount_list(affected_turfs)
	var/differ = 0
	var/first
	for(var/turf/T as anything in old)
		if(old[T] != blocks[T])
			differ++
			first = first || "[T.x],[T.y],[T.z] [T.type]: cache [blocks[T]], old loop [old[T]]"
	if(differ)
		GLOB.explosion_block_differed++
		log_world("Explosion block check: [differ] of [length(old)] tiles differ, first [first]")

/// Every turf in the world: its cached block against the old loop's, its list of objects that work theirs out (each one on it, once,
/// still working it out, not deleted), and every object on it with a block counted there. Returns how many things are wrong, and
/// writes the first 50 to `file` if given. Sleeps as it goes (CHECK_TICK): a whole station's few hundred thousand turfs take seconds.
/proc/explosion_block_cache_check(file)
	var/wrong = 0
	var/list/lines = list()
	for(var/z in 1 to world.maxz)
		var/list/grid = explosion_block_grid(z, FALSE)
		for(var/turf/T as anything in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
			var/cached = (T.density ? T.explosion_block : 0) + T.explosion_block_static
			var/list/dynamic = T.explosion_block_dynamic
			for(var/obj/O as anything in dynamic)
				var/b = O.explosion_block
				cached += b == EXPLOSION_BLOCK_PROC ? O.GetExplosionBlock() : b
				if(QDELETED(O) || O.loc != T || O.explosion_block_turf != T || O.explosion_block_counted != EXPLOSION_BLOCK_PROC)
					wrong++
					if(length(lines) < 50)
						lines += "[T.x],[T.y],[T.z]: [O] ([O.type]) on the list here, but at [O.loc ? "[O.x],[O.y],[O.z]" : "nowhere"], counted on [O.explosion_block_turf ? "[O.explosion_block_turf.x],[O.explosion_block_turf.y]" : "none"] as [O.explosion_block_counted][QDELETED(O) ? ", deleted" : ""]"
			if(length(dynamic) && length(uniqueList(dynamic)) != length(dynamic))
				wrong++
				if(length(lines) < 50)
					lines += "[T.x],[T.y],[T.z]: an object twice on the list"
			var/old = T.density ? T.explosion_block : 0
			for(var/obj/O in T)
				var/b = O.explosion_block
				old += b == EXPLOSION_BLOCK_PROC ? O.GetExplosionBlock() : b
				if(b && O.explosion_block_turf != T)
					wrong++
					if(length(lines) < 50)
						lines += "[T.x],[T.y],[T.z]: [O] ([O.type]) blocks [b] here but is counted on [O.explosion_block_turf ? "[O.explosion_block_turf.x],[O.explosion_block_turf.y],[O.explosion_block_turf.z]" : "none"]"
			var/marked = grid ? !!grid[(T.y - 1) * GLOB.explosion_block_grid_width + T.x] : FALSE
			if(marked != !!(T.explosion_block_static || dynamic))
				wrong++
				if(length(lines) < 50)
					lines += "[T.x],[T.y],[T.z]: [marked ? "marked on the grid with nothing counted" : "not marked on the grid, with [T.explosion_block_static] fixed and [length(dynamic)] on the list"]"
			if(cached != old)
				wrong++
				if(length(lines) < 50)
					lines += "[T.x],[T.y],[T.z] [T.type]: cache [cached] (fixed [T.explosion_block_static], [length(dynamic)] on the list), old loop [old]"
			CHECK_TICK
	if(file)
		fdel(file)
		if(length(lines))
			text2file(jointext(lines, "\n"), file)
	log_world("Explosion block cache check: [wrong] wrong[length(lines) ? ", first [lines[1]]" : ""]")
	return wrong

/datum/controller/subsystem/ticker/Initialize(timeofday)
	. = ..()
	if(GLOB.explosion_block_check)
		OnRoundstart(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(explosion_block_check_rounds)))

/// explosion-block-check=1: the whole map recounted every five minutes of the round too, into the world log
/proc/explosion_block_check_rounds()
	set waitfor = FALSE
	while(SSticker.current_state < GAME_STATE_FINISHED)
		sleep(5 MINUTES)
		var/start = REALTIMEOFDAY
		var/wrong = explosion_block_cache_check("data/explosion_block_check.txt")
		log_world("Explosion block check at [round(world.time / 600, 0.1)] minutes: [wrong] wrong over the map ([round((REALTIMEOFDAY - start) / 10, 0.1)] s), blasts so far [GLOB.explosion_block_checked] checked, [GLOB.explosion_block_differed] different")

/client/proc/cmd_check_explosion_block_cache()
	set name = "Check Explosion Block Cache"
	set category = "Debug"
	set desc = "Recounts what blocks blasts on every turf of the map and compares it with what each turf keeps for explosions."
	if(!check_rights(R_DEBUG))
		return
	to_chat(src, "<span class='notice'>Recounting every turf's explosion block...</span>")
	var/start = REALTIMEOFDAY
	var/wrong = explosion_block_cache_check("data/explosion_block_check.txt")
	to_chat(src, "<span class='[wrong ? "warning" : "notice"]'>Explosion block cache: [wrong] wrong[wrong ? " (the first 50 in data/explosion_block_check.txt)" : ""], [round((REALTIMEOFDAY - start) / 10, 0.1)] s.</span>")
	message_admins("[key_name_admin(src)] checked the explosion block cache: [wrong] wrong.")
