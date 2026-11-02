// What's still holding things that fail to garbage collect. When the GC is about to hard delete something, searches every datum, atom, global
// and client for what points at it, and logs the path. No hits with references still counted means something no var shows: a sleeping proc's
// src or locals, walk(), or BYOND's own lists. Not part of the game, and needs no TESTING build:
// AT_END=1 HARNESS=../../gc_hunt/gc_hunt.dm PARAMS="bot-shift=120&bot-round=1&bot-crew=fill:20&bot-events=1&bot-quiet=1&timewarp=0" SECONDS_LIMIT=590 bash tools/byond_reports/ref_stall/hippie_check.sh
// Results in data/ref_stall.txt. Turfs only have vis_contents looked at: there are 780,000 of them, and they hold nothing else that matters here.

#define GH_MAX_PER_TYPE 4
#define GH_DEPTH 5
#define GH_MAX_HITS 12

GLOBAL_LIST_EMPTY(gh_searched)
GLOBAL_LIST_INIT(gh_skip_vars, list("vars" = TRUE, "verbs" = TRUE, "overlays" = TRUE, "underlays" = TRUE, "type" = TRUE, "parent_type" = TRUE, "tag" = TRUE, "vis_locs" = TRUE))

/datum/controller/master
	sleep_offline_after_initializations = FALSE

/proc/gh_log(text)
	text2file(text, "data/ref_stall.txt")

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
	var/stat_text = isliving(D) ? ", stat [D:stat]" : ""
	gh_log("[D.type] at [round(world.time / 10)]s: refcount [references], [length(hits)] found in [(world.timeofday - started) / 10]s[extra][stat_text]")
	for(var/hit in hits)
		gh_log("    [hit]")

/// How a slime came to be deleted: they're the commonest failure, and the search can't see a sleeping proc.
/mob/living/simple_animal/slime/Destroy()
	var/list/chain = list()
	var/callee/step = caller
	while(step && length(chain) < 8)
		chain += "[step.proc]"
		step = step.caller
	gh_log("slime [src] destroyed at [round(world.time / 10)]s, stat [stat], in [loc], [jointext(chain, " < ")]")
	return ..()

/datum/controller/subsystem/garbage/HardDelete(datum/D)
	var/path = D.type
	gh_log("hard delete [D] [path]")
	if(GLOB.gh_searched[path] < GH_MAX_PER_TYPE)
		GLOB.gh_searched[path]++
		try
			gh_find(D)
		catch(var/exception/E)
			gh_log("[path]: the search failed: [E] at [E.file]:[E.line]")
	else
		gh_log("[path] again at [round(world.time / 10)]s, refcount [refcount(D)]")
	return ..()

/// An overlay on the managed list that isn't in vis_contents is what the GC later trips on. Catches it the moment a rotation leaves one.
/datum/controller/subsystem/vis_overlays/rotate_vis_overlay(atom/thing, old_dir, new_dir)
	var/list/before = list()
	for(var/obj/effect/overlay/vis/O in thing.managed_vis_overlays)
		before += "[O.icon_state] dir [O.dir] plane [O.plane] unique [O.cache_expiration == -1]"
	var/atom/movable/holder = thing
	var/before_vis = length(holder.vis_contents)
	. = ..()
	for(var/obj/effect/overlay/vis/O in thing.managed_vis_overlays)
		if(!(O in holder.vis_contents))
			gh_log("STALE on [thing.type] at [round(world.time / 10)]s, old_dir [old_dir], new_dir [new_dir], thing.dir [thing.dir]: [O.icon_state] dir [O.dir], managed before [jointext(before, " / ")], vis before [before_vis], managed now [length(thing.managed_vis_overlays)], vis now [length(holder.vis_contents)]")
			break

GLOBAL_VAR_INIT(gh_callbacks, 0)

/// A callback made on something already deleted, and who made it: addtimer's own warning arrives with no stack.
/datum/callback/New(thingtocall, proctocall, ...)
	var/datum/gone = istype(thingtocall, /datum) ? thingtocall : null
	if(GLOB && gone && QDELETED(gone) && !QDESTROYING(gone) && GLOB.gh_callbacks < 40)
		GLOB.gh_callbacks++
		var/list/chain = list()
		var/callee/step = caller
		while(step && length(chain) < 7)
			chain += "[step.proc]"
			step = step.caller
		gh_log("CALLBACK on deleted [gone.type] to [proctocall] at [round(world.time / 10)]s: [jointext(chain, " < ")]")
	return ..()
