// Local test, not part of any PR. Hippie's tools/gc_hunt/gc_hunt.dm on Paradise: when the GC is about to hard delete something, searches
// every global, atom, datum and client for what points at it, there and then, and logs the path. Paradise's own finder
// (REFERENCE_TRACKING) stops the GC while it searches, and a holder that lets go a few minutes later is gone by the time it looks.
// Results in data/boom/gc_hunt.txt. No hits with references still counted means something no var shows: a sleeping proc's src or
// locals, walk(), or BYOND's own lists. Two searches a type.

#define GH_MAX_PER_TYPE 2
#define GH_DEPTH 5
#define GH_MAX_HITS 12

GLOBAL_LIST_EMPTY(gh_searched)
GLOBAL_LIST_INIT(gh_skip_vars, list("vars" = TRUE, "verbs" = TRUE, "overlays" = TRUE, "underlays" = TRUE, "type" = TRUE, "parent_type" = TRUE, "tag" = TRUE, "vis_locs" = TRUE))

/proc/gh_log(text)
	text2file(text, "data/boom/gc_hunt.txt")

/proc/gh_note(list/hits, text)
	if(length(hits) < GH_MAX_HITS)
		hits += text

/proc/gh_list(list/L, label, datum/D, list/hits, depth)
	if(depth > GH_DEPTH)
		return
	var/place = 0
	for(var/item in L)
		place++
		if(item == D)
			gh_note(hits, "[label]\[[place]]")
		else if(islist(item))
			gh_list(item, "[label]\[[place]]", D, hits, depth + 1)
		if(!isnum(item) && !isnull(item))
			var/value
			try
				value = L[item]
			catch
				continue
			if(value == D)
				gh_note(hits, "[label]\[[item]] (value)")
			else if(islist(value))
				gh_list(value, "[label]\[[item]]", D, hits, depth + 1)

/proc/gh_scan(datum/thing, label, datum/D, list/hits)
	var/skip_contents = isarea(thing)
	var/list/own = thing.vars
	for(var/name in own)
		if(GLOB.gh_skip_vars[name] || (skip_contents && name == "contents"))
			continue
		var/value = own[name]
		if(value == D)
			gh_note(hits, "[label].[name]")
		else if(islist(value))
			gh_list(value, "[label].[name]", D, hits, 1)

/proc/gh_label(datum/thing)
	if(thing == null)
		return "null"
	var/turf/where = isatom(thing) ? get_turf(thing) : null
	return "[thing.type][where ? " at [where.x],[where.y],[where.z]" : ""]"

/proc/gh_find(datum/D)
	var/started = world.timeofday
	var/list/hits = list()
	var/references = refcount(D)
	gh_scan(GLOB, "GLOB", D, hits)
	for(var/turf/T in world)
		if(length(T.vis_contents) && (D in T.vis_contents))
			gh_note(hits, "[T.type] at [T.x],[T.y],[T.z].vis_contents")
		if(length(T.opacity_sources) && (D in T.opacity_sources))
			gh_note(hits, "[T.type] at [T.x],[T.y],[T.z].opacity_sources")
		var/turf/simulated/S = T
		if(istype(S) && S.wind_effect == D)
			gh_note(hits, "[T.type] at [T.x],[T.y],[T.z].wind_effect")
	for(var/datum/thing in world)
		if(!isturf(thing))
			gh_scan(thing, gh_label(thing), D, hits)
	for(var/datum/thing)
		gh_scan(thing, gh_label(thing), D, hits)
	for(var/client/C)
		gh_scan(C, "client [C.ckey]", D, hits)
	var/atom/movable/AM = D
	var/extra = ""
	if(istype(AM))
		extra = ", loc [AM.loc], vis_locs [length(AM.vis_locs)]"
	gh_log("[D.type] at [round(world.time / 10)]s: refcount [references], [length(hits)] found in [(world.timeofday - started) / 10]s[extra]")
	for(var/hit in hits)
		gh_log("    [hit]")

/datum/controller/subsystem/garbage/HardDelete(datum/D)
	var/path = D.type
	if(GLOB.gh_searched[path] < GH_MAX_PER_TYPE)
		GLOB.gh_searched[path]++
		gh_log("hard delete [D] [path]")
		try
			gh_find(D)
		catch(var/exception/E)
			gh_log("[path]: the search failed: [E] at [E.file]:[E.line]")
	return ..()

#undef GH_MAX_PER_TYPE
#undef GH_DEPTH
#undef GH_MAX_HITS
