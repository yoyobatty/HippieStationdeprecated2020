// Bot Gym scenarios for the crew against a blob (goals/blob.dm).
//
// Layout letters used here: e a spare emitter, standing loose as it does in Secure Storage; p a P.A.C.M.A.N. running on the cable,
// for power; k a blob core (an overmind nobody drives, so it only grows round its core); b a plain bit of blob belonging to it.

/datum/bot_scenario/blob_emitter
	job = "Station Engineer"
	time_limit = 240 SECONDS
	max_goal_attempts = 30 //a second apart: the generator's power is on the cable a few seconds in
	var/obj/structure/blob/core/core

/datum/bot_scenario/blob_emitter/setup()
	for(var/turf/T in markers["p"])
		var/obj/structure/cable/C = new(T)
		propagate_network(C, new /datum/powernet()) //cable laid at runtime is on no circuit until something makes it one
		var/obj/machinery/power/port_gen/pacman/P = new(T)
		P.anchored = TRUE
		P.connect_to_network()
		P.sheets = 50
		P.TogglePower()
		place("p", P)
	for(var/turf/T in markers["e"])
		place("e", new /obj/machinery/power/emitter(T))
	var/turf/core_at = first_marker("k")
	if(!core_at)
		return
	// The core made here by hand, and kept here: an overmind started anywhere off the station takes itself there, and a core is
	// station-loving like the nuke disk, back to the station the moment it's off it. The first tries at this put a blob on the station
	// for every run.
	var/mob/camera/blob/overmind = new(core_at, 0)
	core = new(core_at, overmind, 1)
	qdel(core.GetComponent(/datum/component/stationloving))
	core.forceMove(core_at)
	core.overmind = overmind
	overmind.blob_core = core
	overmind.placed = TRUE
	overmind.blobs_legit |= core
	core.update_icon()
	for(var/turf/T in markers["b"])
		new /obj/structure/blob/normal(T, overmind)

/datum/bot_scenario/blob_emitter/post_spawn()
	give_job_id(list(ACCESS_ENGINE, ACCESS_ENGINE_EQUIP, ACCESS_MAINT_TUNNELS))

/datum/bot_scenario/blob_emitter/make_goal()
	if(goal_attempts % 5 == 1) //what the engineer has to go on, while it waits
		var/obj/machinery/power/port_gen/pacman/P = first_placed("p")
		log_line("generator [P?.active ? "running" : "off"], [P?.powernet ? "[P.powernet.avail] W on its cable" : "no cable"]; blob [length(core?.overmind?.blobs_legit)] tiles, core at [bot_coord(get_turf(core))]")
	return new /datum/bot_goal/blob_emitter()

/// The blob gone with the run: its overmind keeps the shuttle from being called for as long as it's about.
/datum/bot_scenario/blob_emitter/release_run()
	var/mob/camera/blob/overmind = core?.overmind
	if(overmind)
		for(var/obj/structure/blob/B as anything in overmind.blobs_legit.Copy())
			if(istype(B))
				qdel(B)
		qdel(overmind)
	if(!QDELETED(core))
		qdel(core)
	return ..()

/// An emitter that's on and welded down, facing the blob along a clear line.
/datum/bot_scenario/blob_emitter/proc/emitter_on_the_blob()
	for(var/obj/machinery/power/emitter/E in placed["e"])
		if(!QDELETED(E) && E.active && E.state == 2 && bot_emitter_line_worth(get_turf(E), E.dir))
			return E
	return null

/datum/bot_scenario/blob_emitter/sets_one_up
	name = "engineer sets an emitter up on the blob"
	desc = "A spare emitter, a toolbox, a cable run powered by a P.A.C.M.A.N. and a blob down the far end. The engineer drags the emitter well back from the blob onto the cable, turns it to face the blob, wrenches it down, welds it and switches it on, then stands by it out of its line."
	layout = list(
		"##############################",
		"#B.T.e.......................#",
		"#p=================......bbk.#",
		"#............................#",
		"##############################")

/datum/bot_scenario/blob_emitter/sets_one_up/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/machinery/power/emitter/E = emitter_on_the_blob()
	if(!E)
		return BOT_GYM_PENDING
	if(bot_in_emitter_fire(get_turf(bot)))
		fail_reason = "it stood in front of its own emitter"
		return BOT_GYM_FAIL
	var/obj/structure/blob/near = locate() in orange(2, get_turf(E)) //where the engineer would be dragging it back again
	if(near)
		fail_reason = "the emitter is set down [get_dist(E, near)] tiles from the blob"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/blob_emitter/round_the_corner
	name = "engineer hauls an emitter round a corner to the blob"
	desc = "The same, with the emitter in a side room off the corridor, the way Secure Storage is. The engineer pulls it out through the door and along to the cable, turning in the corridor without the emitter it's pulling getting in its way."
	layout = list(
		"##############################",
		"#....e#......................#",
		"#.T...D......................#",
		"#######p=================.bbk#",
		"#B...........................#",
		"##############################")

/datum/bot_scenario/blob_emitter/turns_it_to_face
	name = "engineer turns an emitter to face the blob"
	desc = "The cable runs along under the blob, so the emitter is dragged along it and comes to the spot facing the way it was dragged, side on to the blob. The engineer alt-clicks it round a quarter at a time until it faces the blob, then wrenches, welds and switches it on."
	layout = list(
		"#####################",
		"#.........bbk.......#",
		"#...................#",
		"#...................#",
		"#...................#",
		"#...................#",
		"#...................#",
		"#...................#",
		"#p==================#",
		"#B.T.e..............#",
		"#####################")

/datum/bot_scenario/blob_emitter/turns_it_to_face/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/machinery/power/emitter/E = emitter_on_the_blob()
	if(!E)
		return BOT_GYM_PENDING
	if(E.dir != NORTH)
		fail_reason = "switched on facing [dir2text(E.dir)]"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/blob_emitter/round_the_corner/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return emitter_on_the_blob() ? BOT_GYM_PASS : BOT_GYM_PENDING
