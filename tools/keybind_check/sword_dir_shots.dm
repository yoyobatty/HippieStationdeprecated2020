// Real-client pictures of a lit energy sword in hand, its glow drawn four ways, at each facing (round-13.09.35: "energy sword overlay
// shows on wrong direction on my player"). Not part of the game:
// HARNESS=sword_dir_shots.dm SENDER=shot.ps1 MAP=testbench tools/keybind_check/run.sh sword
// Pictures in data/previews/sword_dir_*.png, notes in data/keycheck_sword.txt. Left to right: the game's own in-hand glow (nested in the
// in-hand overlay, KEEP_APART), the glow as a sibling overlay on the mob, nested without KEEP_APART, a sibling without KEEP_APART.

GLOBAL_VAR_INIT(keycheck_running, FALSE)

/datum/preferences/save_preferences()
	return FALSE

/datum/preferences/save_character()
	return FALSE

/proc/kc_log(text)
	text2file(text, "data/keycheck.txt")

/client/New()
	. = ..()
	if(. && !GLOB.keycheck_running)
		GLOB.keycheck_running = TRUE
		spawn(50)
			sword_shots_run(src)

/proc/sword_shot(name)
	text2file(name, "data/keycheck_shot")
	var/deadline = world.time + 15 SECONDS
	while(fexists("data/keycheck_shot") && world.time < deadline)
		sleep(1)
	sleep(2)

/// A glow overlay: on one of the emissive planes
/proc/sword_is_glow(appearance)
	var/plane = appearance:plane //not through new /mutable_appearance(): its New() sets plane to FLOAT_PLANE
	return plane == EMISSIVE_UNBLOCKABLE_PLANE || plane == EMISSIVE_BLOOM_PLANE || plane == EMISSIVE_PLANE

/// Redraws H's in-hand overlays with the glow moved out to the mob (sibling) and/or without KEEP_APART
/proc/sword_redraw(mob/living/carbon/human/H, sibling, keep_apart)
	var/list/hands = H.overlays_standing[HANDS_LAYER]
	if(!islist(hands))
		hands = hands ? list(hands) : list()
	var/list/redone = list()
	for(var/mutable_appearance/standing in hands)
		var/mutable_appearance/copy = new(standing)
		var/list/glows = list()
		for(var/each in standing.overlays)
			if(sword_is_glow(each))
				var/mutable_appearance/G = new(each)
				G.plane = each:plane
				if(!keep_apart)
					G.appearance_flags &= ~KEEP_APART
				glows += G
		for(var/each in standing.overlays)
			if(sword_is_glow(each))
				copy.overlays -= each
		if(sibling)
			redone += copy
			redone += glows
		else
			copy.overlays += glows
			redone += copy
	H.remove_overlay(HANDS_LAYER)
	H.overlays_standing[HANDS_LAYER] = redone
	H.apply_overlay(HANDS_LAYER)
	kc_log("[H.name]: [length(redone)] hand overlays, sibling [sibling], keep_apart [keep_apart]")

/proc/sword_dump(mob/living/carbon/human/H)
	var/list/hands = H.overlays_standing[HANDS_LAYER]
	kc_log("hands layer: [islist(hands) ? "list of [length(hands)]" : "[hands]"]")
	for(var/mutable_appearance/standing in (islist(hands) ? hands : list(hands)))
		kc_log("  standing [standing.icon_state] plane [standing.plane] dir [standing.dir] flags [standing.appearance_flags], [length(standing.overlays)] overlays")
		for(var/each in standing.overlays)
			kc_log("    sub [each:icon] [each:icon_state] plane [each:plane] dir [each:dir] flags [each:appearance_flags]")
	for(var/each in H.overlays)
		var/mutable_appearance/M = new(each)
		if(findtext("[M.icon_state]", "sword") || M.plane != FLOAT_PLANE)
			kc_log("  mob overlay [M.icon] [M.icon_state] plane [M.plane] dir [M.dir] flags [M.appearance_flags] subs [length(M.overlays)]")
	for(var/atom/movable/V in H.vis_contents)
		kc_log("  vis [V.type] [V.icon] [V.icon_state] plane [V.plane] dir [V.dir] vis_flags [V.vis_flags]")

/proc/sword_holder(turf/T, name)
	var/mob/living/carbon/human/H = new(T)
	H.real_name = name
	H.name = name
	H.equipOutfit(/datum/outfit/job/assistant)
	var/obj/item/melee/transforming/energy/sword/saber/red/S = new(T)
	H.put_in_r_hand(S)
	S.transform_weapon(H, TRUE)
	H.update_inv_hands()
	kc_log("[name]: sword [S.icon_state] in hand [H.get_held_index_of_item(S)]")
	if(name == "game")
		sword_dump(H)
	return H

/// Five clear floor tiles in a row with two clear rows below, in a hallway on the station
/proc/sword_find_row()
	var/z = SSmapping.levels_by_trait(ZTRAIT_STATION)[1]
	for(var/turf/open/floor/T in block(locate(1, 1, z), locate(world.maxx - 6, world.maxy, z)))
		if(!istype(T.loc, /area/hallway))
			continue
		var/ok = TRUE
		for(var/i in 0 to 4)
			for(var/j in 0 to 2)
				var/turf/U = locate(T.x + i, T.y - j, T.z)
				if(!istype(U, /turf/open/floor) || !istype(U.loc, /area/hallway) || is_blocked_turf(U, TRUE))
					ok = FALSE
					break
			if(!ok)
				break
		if(ok && !(locate(/obj/machinery/light) in range(4, T)))
			ok = FALSE
		if(ok)
			return T
	return null

/proc/sword_shots_run(client/C)
	fdel("data/keycheck_shot")
	fdel("data/keycheck_shots_done")
	GLOB.master_mode = "extended"
	SSticker.start_immediately = TRUE
	var/wait_for_round = world.time + 3 MINUTES
	while(SSticker.current_state < GAME_STATE_PLAYING && world.time < wait_for_round)
		sleep(1 SECONDS)
	sleep(5 SECONDS)
	text2file("go", "data/keycheck_sendkeys") //starts shot.ps1
	var/turf/row = sword_find_row()
	if(!row)
		kc_log("no clear hallway row")
		text2file("done", "data/keycheck_shots_done")
		kc_log("done")
		del(world)
		return
	kc_log("row at ([row.x],[row.y],[row.z]) in [get_area(row)]")
	var/list/holders = list()
	var/list/names = list("game", "sibling", "nested_no_apart", "sibling_no_apart")
	for(var/i in 1 to 4)
		holders += sword_holder(locate(row.x + i - 1, row.y, row.z), names[i])
	sword_redraw(holders[2], TRUE, TRUE)
	sword_redraw(holders[3], FALSE, FALSE)
	sword_redraw(holders[4], TRUE, FALSE)
	var/mob/living/carbon/human/viewer = new(locate(row.x + 1, row.y - 2, row.z))
	viewer.mind_initialize()
	viewer.equipOutfit(/datum/outfit/job/assistant)
	viewer.ckey = C.ckey
	var/obj/item/melee/transforming/energy/sword/saber/red/mine = new(viewer.loc)
	viewer.put_in_r_hand(mine)
	mine.transform_weapon(viewer, TRUE)
	viewer.update_inv_hands()
	sleep(3 SECONDS)
	for(var/lit in list(TRUE, FALSE))
		for(var/obj/machinery/light/L in range(10, row))
			L.on = lit
			L.update(FALSE)
		sleep(2 SECONDS)
		for(var/d in list(EAST, NORTH, WEST, SOUTH))
			for(var/mob/living/carbon/human/H in holders + viewer)
				H.setDir(d)
			sleep(1 SECONDS)
			sword_shot("sword_dir_[lit ? "lit" : "dark"]_[dir2text(d)]")
	text2file("done", "data/keycheck_shots_done")
	sleep(5)
	kc_log("done")
	winset(C, null, "command=.quit")
	sleep(5)
	del(world)
