// The tactical map (the plan's foundation/tactical_map.dm, M1): the station as rooms and the ways between them, for what's built on it.
// Hunting (where somebody could have gone, where to cut a runner off, which dead end to check) and tactics (which doorway to hold, where a
// fuel tank would catch somebody) read it; the route search doesn't, it has the tiles.
//
// Built once a level, at round start, in the background (a pass over the level's tiles, ~65,000 on the station, with CHECK_TICK):
//  - links: each room's neighbours, and how many tiles cross between them (an airlock is one, an open archway several);
//  - dead ends: rooms with one way in;
//  - chokepoints: rooms that cut the station in two if they're shut (articulation points of the room graph): the corridor everything
//    goes through, the airlock lobby, a maintenance junction.
// Hiding spots (tactical_hiding_spots()) are looked up when they're wanted, since lockers move about.
// Rooms are areas: the station's maintenance is a few big areas joined up, so a maintenance "room" is a stretch of it.

GLOBAL_LIST_EMPTY(tactical_maps)

/// The map of level z, built the first time it's asked for if round start didn't.
/proc/tactical_map(z)
	var/datum/tactical_map/M = GLOB.tactical_maps["[z]"]
	if(!M)
		M = new(z)
		GLOB.tactical_maps["[z]"] = M
		M.build()
	return M.built ? M : null

/proc/tactical_maps_at_roundstart()
	for(var/z in SSmapping.levels_by_trait(ZTRAIT_STATION))
		INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(tactical_map), z)

/datum/controller/subsystem/ticker/Initialize(timeofday)
	. = ..()
	OnRoundstart(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(tactical_maps_at_roundstart)))

/datum/tactical_map
	var/z
	var/built = FALSE
	var/building = FALSE
	/// area -> list(neighbouring area -> tiles crossing between them)
	var/list/links = list()
	/// area -> TRUE: one way in
	var/list/dead_ends = list()
	/// area -> TRUE: shut it, and the rooms either side can't reach each other
	var/list/chokepoints = list()

/datum/tactical_map/New(z)
	src.z = z

/// A room for the map: not space round the station, and not the gym's arenas.
/proc/tactical_area_counts(area/A)
	return A && !istype(A, /area/space) && !istype(A, /area/bot_gym)

/datum/tactical_map/proc/build()
	if(built || building)
		return
	building = TRUE
	var/started = REALTIMEOFDAY
	var/crossings = 0
	for(var/turf/T as anything in block(locate(1, 1, z), locate(world.maxx, world.maxy, z)))
		if(T.density || isspaceturf(T))
			continue
		var/area/A = T.loc
		if(!tactical_area_counts(A))
			continue
		for(var/d in list(EAST, NORTH))
			var/turf/N = get_step(T, d)
			if(!N || N.density || isspaceturf(N))
				continue
			var/area/B = N.loc
			if(B == A || !tactical_area_counts(B))
				continue
			var/list/mine = links[A] || (links[A] = list())
			var/list/theirs = links[B] || (links[B] = list())
			mine[B] = (mine[B] || 0) + 1
			theirs[A] = (theirs[A] || 0) + 1
			crossings++
		CHECK_TICK
	for(var/area/A as anything in links)
		if(length(links[A]) == 1)
			dead_ends[A] = TRUE
	find_chokepoints()
	built = TRUE
	building = FALSE
	var/list/choke_names = list()
	for(var/area/A as anything in chokepoints)
		choke_names += A.name
	log_game("TACTICAL MAP: level [z]: [length(links)] rooms, [crossings] tiles crossing between them, [length(dead_ends)] dead ends, [length(chokepoints)] chokepoints ([jointext(choke_names, ", ")]), [(REALTIMEOFDAY - started) * 100] ms with the waits")

/// Articulation points of the room graph (Tarjan's, without recursion: a station has a few hundred rooms).
/datum/tactical_map/proc/find_chokepoints()
	var/list/disc = list()
	var/list/low = list()
	var/list/parent = list()
	var/list/next_index = list()
	var/t = 0
	for(var/area/root as anything in links)
		if(disc[root])
			continue
		disc[root] = ++t
		low[root] = t
		var/root_children = 0
		var/list/stack = list(root)
		while(length(stack))
			var/area/u = stack[length(stack)]
			var/list/neighbours = links[u]
			var/i = (next_index[u] || 0) + 1
			if(i <= length(neighbours))
				next_index[u] = i
				var/area/v = neighbours[i]
				if(!disc[v])
					parent[v] = u
					disc[v] = ++t
					low[v] = t
					stack += v
					if(u == root)
						root_children++
				else if(v != parent[u])
					low[u] = min(low[u], disc[v])
				continue
			stack.len--
			var/area/p = parent[u]
			if(p)
				low[p] = min(low[p], low[u])
				if(p != root && low[u] >= disc[p])
					chokepoints[p] = TRUE
		if(root_children > 1)
			chokepoints[root] = TRUE

/datum/tactical_map/proc/neighbours(area/A)
	return links[A] || list()

/datum/tactical_map/proc/is_dead_end(area/A)
	return dead_ends[A]

/datum/tactical_map/proc/is_chokepoint(area/A)
	return chokepoints[A]

/// Where somebody could be out of sight in A right now: lockers, crates, body bags, morgue trays.
/proc/tactical_hiding_spots(area/A)
	. = list()
	for(var/obj/structure/closet/C in A)
		if(!C.anchored || istype(C, /obj/structure/closet/body_bag))
			. += C
	for(var/obj/structure/bodycontainer/B in A)
		. += B
