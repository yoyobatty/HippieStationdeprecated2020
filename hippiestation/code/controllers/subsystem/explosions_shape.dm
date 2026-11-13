// Shaped explosions (the user's ruling, 2026-11-09): the same power as before, but walls, doors and windows absorb and block the blast and
// it spreads through openings. Before, every tile added up whatever blocked the one straight line back to the epicenter: a wall between
// you and the bomb shielded you even with an open door beside you, and nothing came round a corner. Now a tile is as far from the
// epicenter as the cheapest way there, where leaving a tile costs its explosion block on top of the step (tools/path_engine/src/blast.rs
// in native code; the same search is below in DM). Out in the open an explosion is exactly what it was.
//
// World param explosion-shape=native (the default, worked out in DM where the path engine library hasn't got it), dm, check (both,
// compared, differences in the world log) or line (the straight line, as before 2026-11-09).

/// What a tile the blast can't get to at all comes back as (blast.rs UNREACHABLE)
#define EXPLOSION_SHAPE_UNREACHABLE 1000000
/// Below this the extra is float noise from adding up steps (blast.rs NOISE)
#define EXPLOSION_SHAPE_NOISE 0.001

GLOBAL_VAR_INIT(explosion_shape_mode, world.params["explosion-shape"] || "native")
/// What a block counts for in the shaped blast (world param explosion-block-weight). 1.5, the user's pick (2026-11-09): with blocks as they
/// were, a wall was paid for once instead of two or three times along a slanting line, and bombs reached about a fifth further into the
/// station (150 maxcaps on Hippie: 23% more tiles hit light, 14% heavy). At 1.5 the totals are today's, with the new shape
/// (tools/explosion_preview).
GLOBAL_VAR_INIT(explosion_block_weight, text2num(world.params["explosion-block-weight"]) || 1.5)
/// Whether the path engine library has path_blast: null until it's first asked
GLOBAL_VAR(explosion_shape_native)
/// For the check: explosions compared, and ones that came out different
GLOBAL_VAR_INIT(explosion_shape_checked, 0)
GLOBAL_VAR_INIT(explosion_shape_differed, 0)

/// turf -> how much further than the straight line the blast comes to reach it, for each turf in `blocks` (turf -> its explosion block,
/// CaculateExplosionBlock()), all within the square of `range` round `epicenter`. Null for the straight line, which explode() does itself.
/proc/explosion_shape(turf/epicenter, range, list/blocks)
	var/mode = GLOB.explosion_shape_mode
	if(mode == "line")
		return null
	range = CEILING(range, 1) //a delaminating supermatter's is 27.37 and the like: the grid's in whole tiles
	var/size = range * 2 + 1
	var/list/grid = new(size * size)
	for(var/i in 1 to length(grid))
		grid[i] = -1 //no tile: off the map
	var/x0 = epicenter.x - range
	var/y0 = epicenter.y - range
	var/weight = GLOB.explosion_block_weight
	for(var/turf/T as anything in blocks)
		grid[(T.y - y0) * size + (T.x - x0) + 1] = blocks[T] * weight
	var/list/extra
	if(mode != "dm")
		extra = explosion_shape_native(grid, size)
	if(!extra || mode == "check")
		var/list/in_dm = explosion_shape_dm(grid, size)
		if(extra)
			explosion_shape_compare(extra, in_dm, epicenter, size)
		extra = extra || in_dm
	. = list()
	for(var/turf/T as anything in blocks)
		.[T] = extra[(T.y - y0) * size + (T.x - x0) + 1]

/proc/explosion_shape_native(list/grid, size)
	if(GLOB.explosion_shape_native == FALSE)
		return null
	var/list/out = list()
	var/result
	try
		result = call_ext(GLOB.path_engine_lib, "byond:path_blast")(grid, size, out)
	catch(var/exception/E)
		GLOB.explosion_shape_native = FALSE
		log_world("Shaped explosions: [GLOB.path_engine_lib] has no path_blast ([E.name]), so they're worked out in DM")
		return null
	if(result != size * size || length(out) != size * size)
		log_world("Shaped explosions: path_blast returned [result] with [length(out)] of [size * size] tiles; worked out in DM")
		return null
	GLOB.explosion_shape_native = TRUE
	return out

/// blast.rs shape() in DM: Dijkstra from the middle of the square over a binary heap kept in two lists, with the same steps, the same
/// corner rule and the same sums in the same order, so it comes out the same to the bit
/proc/explosion_shape_dm(list/grid, size)
	var/n = size * size
	var/list/extra = new(n)
	for(var/i in 1 to n)
		extra[i] = EXPLOSION_SHAPE_UNREACHABLE
	var/r = (size - 1) / 2
	var/center = r * size + r + 1
	if(grid[center] < 0)
		return extra
	var/list/cost = new(n)
	for(var/i in 1 to n)
		cost[i] = INFINITY
	cost[center] = 0
	var/list/heap_cost = list(0)
	var/list/heap_at = list(center)
	var/diagonal = sqrt(2)
	while(length(heap_cost))
		var/c = heap_cost[1]
		var/i = heap_at[1]
		var/last = length(heap_cost)
		heap_cost[1] = heap_cost[last]
		heap_at[1] = heap_at[last]
		heap_cost.len--
		heap_at.len--
		// sift the moved one down
		var/count = last - 1
		var/at = 1
		while(TRUE)
			var/child = at * 2
			if(child > count)
				break
			if(child < count && explosion_shape_before(heap_cost[child + 1], heap_at[child + 1], heap_cost[child], heap_at[child]))
				child++
			if(!explosion_shape_before(heap_cost[child], heap_at[child], heap_cost[at], heap_at[at]))
				break
			heap_cost.Swap(at, child)
			heap_at.Swap(at, child)
			at = child
		if(c > cost[i])
			continue
		var/leaving = max(grid[i], 0)
		var/x = (i - 1) % size
		var/y = round((i - 1) / size)
		for(var/dy in -1 to 1)
			for(var/dx in -1 to 1)
				if(!dx && !dy)
					continue
				var/nx = x + dx
				var/ny = y + dy
				if(nx < 0 || ny < 0 || nx >= size || ny >= size)
					continue
				var/j = ny * size + nx + 1
				if(grid[j] < 0)
					continue
				var/step = 1
				if(dx && dy)
					if(grid[y * size + nx + 1] != 0 && grid[ny * size + x + 1] != 0)
						continue //not between two wall corners
					step = diagonal
				var/next = c + step + leaving
				if(next < cost[j])
					cost[j] = next
					// push, then sift up
					heap_cost += next
					heap_at += j
					var/up = length(heap_cost)
					while(up > 1)
						var/parent = round(up / 2)
						if(!explosion_shape_before(heap_cost[up], heap_at[up], heap_cost[parent], heap_at[parent]))
							break
						heap_cost.Swap(up, parent)
						heap_at.Swap(up, parent)
						up = parent
	var/edge = diagonal - 1
	for(var/i in 1 to n)
		if(cost[i] >= INFINITY)
			continue
		var/dx = abs((i - 1) % size - r)
		var/dy = abs(round((i - 1) / size) - r)
		var/more = cost[i] - (max(dx, dy) + edge * min(dx, dy))
		extra[i] = more < EXPLOSION_SHAPE_NOISE ? 0 : more
	return extra

/// The heap's order, as blast.rs's: cheaper first, then the lower index
/proc/explosion_shape_before(cost_a, at_a, cost_b, at_b)
	return cost_a < cost_b || (cost_a == cost_b && at_a < at_b)

/proc/explosion_shape_compare(list/native, list/in_dm, turf/epicenter, size)
	GLOB.explosion_shape_checked++
	var/differ = 0
	var/first
	for(var/i in 1 to length(native))
		if(abs(native[i] - in_dm[i]) > 0.01)
			differ++
			first = first || "tile [i]: native [native[i]], DM [in_dm[i]]"
	if(differ)
		GLOB.explosion_shape_differed++
		log_world("Shaped explosion check at [AREACOORD(epicenter)], [size]x[size]: [differ] tiles differ, first [first]")

/// What an explosion of this size at `epicenter` does to each turf, as explode() works it out: turf -> EXPLODE_DEVASTATE, EXPLODE_HEAVY,
/// EXPLODE_LIGHT or EXPLODE_FAR (glass only). `mode` as explosion-shape, null for the server's own, or "none" for nothing blocking it at
/// all. `realism` TRUE or FALSE for realistic blasts on or off (explosion_realism/), null for the server's own. For the admins' Check
/// Bomb Impact and the before/after pictures.
/proc/explosion_severity_map(turf/epicenter, devastation_range, heavy_impact_range, light_impact_range, mode, realism)
	. = list()
	// hippie -- realistic blasts, as explode() has them
	var/was_realism = GLOB.explosion_realism
	if(!isnull(realism))
		GLOB.explosion_realism = realism
	var/far_range = 0
	var/confine_boost = 1
	var/list/confined
	if(GLOB.explosion_realism)
		var/list/real = explosion_realism_ranges(epicenter, devastation_range, heavy_impact_range, light_impact_range, 0)
		devastation_range = real[1]
		heavy_impact_range = real[2]
		light_impact_range = real[3]
		far_range = real[5]
		confine_boost = real[7]
		confined = real[8]
	var/max_range = max(devastation_range, heavy_impact_range, light_impact_range)
	var/reach_range = max(max_range, far_range)
	var/list/affected = SSexplosions.GatherSpiralTurfs(reach_range, epicenter)
	var/plain = mode == "none"
	var/list/blocks
	var/list/shape
	if(!plain)
		blocks = SSexplosions.CaculateExplosionBlock(affected)
		var/was = GLOB.explosion_shape_mode
		if(mode)
			GLOB.explosion_shape_mode = mode
		shape = explosion_shape(epicenter, reach_range, blocks)
		GLOB.explosion_shape_mode = was
	GLOB.explosion_realism = was_realism
	for(var/turf/T as anything in affected)
		var/dist = cheap_hypotenuse(T.x, T.y, epicenter.x, epicenter.y)
		if(plain)
			pass()
		else if(shape)
			dist += shape[T]
		else
			var/turf/along = T
			while(along && along != epicenter)
				along = get_step_towards(along, epicenter)
				dist += blocks[along]
		if(confined && confined[T])
			dist /= confine_boost
		if(dist < devastation_range)
			.[T] = EXPLODE_DEVASTATE
		else if(dist < heavy_impact_range)
			.[T] = EXPLODE_HEAVY
		else if(dist < light_impact_range)
			.[T] = EXPLODE_LIGHT
		else if(dist < far_range)
			.[T] = EXPLODE_FAR

#undef EXPLOSION_SHAPE_UNREACHABLE
#undef EXPLOSION_SHAPE_NOISE
