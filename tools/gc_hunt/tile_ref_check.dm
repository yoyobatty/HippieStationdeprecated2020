// Tile reference check: does something on one tile keep hold of what goes onto it? A hunt (gc_hunt.dm with gh-watch) that keeps
// finding hard deletes of a kind on the same tile with nothing in any var holding them has narrowed it to that tile; this makes
// one of the kind next to it, steps it on and deletes it there, again and again, against a plain tile for comparison, and then
// once more with each thing on the tile moved off in turn: the one whose going makes the extra reference go is the holder.
// refcount() counts what no var shows too (a sleeping proc, an image's loc), so it finds what the search can't.
//
//   AT_END=1 HARNESS=../../gc_hunt/tile_ref_check.dm PORT=45607 SECONDS_LIMIT=300 \
//     PARAMS="bot-shift=10&bot-crew=Assistant&bot-quiet=1&timewarp=0&trc-type=obj/effect/particle_effect/sparks&trc-at=124,120,2&trc-dir=1" \
//     bash tools/byond_reports/ref_stall/hippie_check.sh        (from the repo root; prints data/ref_stall.txt)
//
// World params: trc-type (the kind, no leading slash: Git Bash rewrites one), trc-at (x,y,z of the tile), trc-dir (the direction it
// steps on from: 1 north of it, 2 south, 4 east, 8 west; default 1), trc-control (x,y,z of a plain tile to compare with; default
// three tiles west), trc-trials (default 6), trc-wait (deciseconds after the delete before counting, default 30: past a QDEL_IN).

/datum/controller/master
	sleep_offline_after_initializations = FALSE

/proc/trc_log(text)
	text2file(text, "data/ref_stall.txt")

/proc/trc_turf(text)
	var/list/parts = splittext(text || "", ",")
	if(length(parts) != 3)
		return null
	return locate(text2num(parts[1]), text2num(parts[2]), text2num(parts[3]))

/datum/controller/subsystem/ticker/Initialize(timeofday)
	. = ..()
	OnRoundstart(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(trc_start)))

/proc/trc_start()
	set waitfor = FALSE
	sleep(5 SECONDS)
	var/type_text = world.params["trc-type"]
	var/path = text2path(copytext(type_text, 1, 2) == "/" ? type_text : "/[type_text]")
	var/turf/target = trc_turf(world.params["trc-at"])
	if(!path || !target)
		trc_log("tile ref check: needs trc-type and trc-at (got [type_text], [world.params["trc-at"]])")
		trc_log("done")
		return
	var/dir = text2num(world.params["trc-dir"]) || NORTH
	var/turf/control = trc_turf(world.params["trc-control"]) || locate(target.x - 3, target.y, target.z)
	var/trials = text2num(world.params["trc-trials"]) || 6
	var/wait = text2num(world.params["trc-wait"]) || 30
	trc_log("tile ref check: [path] onto [AREACOORD(target)] from the [dir2text(dir)], [trials] trials each, against [AREACOORD(control)]")
	trc_log("  on the tile: [jointext(trc_contents(target), ", ")]")
	trc_log("  plain tile:  [trc_report(path, control, dir, trials, wait)]")
	trc_log("  the tile:    [trc_report(path, target, dir, trials, wait)]")
	// each thing moved off the tile in turn (to the tile it's stepped on from, which is put back after)
	for(var/atom/movable/thing as anything in trc_movables(target))
		var/turf/aside = get_step(target, dir)
		if(QDELETED(thing) || thing.loc != target)
			continue
		var/was_anchored = thing.anchored
		thing.forceMove(locate(target.x + 1, target.y + 1, target.z) || aside)
		trc_log("  without [thing.type]: [trc_report(path, target, dir, trials, wait)]")
		thing.forceMove(target)
		thing.anchored = was_anchored
	trc_log("done")

/proc/trc_movables(turf/T)
	. = list()
	for(var/atom/movable/thing in T)
		if(!istype(thing, /atom/movable/lighting_object))
			. += thing

/proc/trc_contents(turf/T)
	. = list()
	for(var/atom/movable/thing in T)
		. += "[thing.type]"

/// Extra references left on each trial's thing once it's deleted and the wait is over, beyond what this proc holds itself
/proc/trc_report(path, turf/target, dir, trials, wait)
	var/list/moved = list()
	var/list/left = list()
	for(var/i in 1 to trials)
		var/list/result = trc_trial(path, target, dir, wait)
		moved += "[result[1]]"
		left += "[result[2]]"
	return "references gained in the step [jointext(moved, " ")]; left after the delete [jointext(left, " ")]"

/// One: made beside the tile, stepped on, deleted there. list(references gained in the step, references left after the wait)
/proc/trc_trial(path, turf/target, dir, wait)
	var/turf/start = get_step(target, dir)
	var/atom/movable/A = new path(start)
	sleep(1)
	if(QDELETED(A))
		return list("gone before the step", "-")
	var/before = refcount(A)
	A.Move(target, get_dir(start, target))
	var/after = refcount(A)
	if(A.loc != target)
		qdel(A)
		return list("blocked", "-")
	qdel(A)
	sleep(wait)
	// what's still counted: this proc's A and refcount()'s own argument are 2
	return list(after - before, refcount(A) - 2)
