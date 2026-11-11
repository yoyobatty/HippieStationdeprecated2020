// What a cyborg does with the rest of its module, and where it goes between jobs (overnight 2026-11-10). In the user's round
// (round-20.37.50) both cyborgs spent the shift "heading for" a random crew member a hundred tiles off, gave up within a minute,
// and picked another: 120 of 135 lines. They also stepped every 0.2 s where a player's cyborg runs at the run delay, half again
// as quick.
//
// Now each module keeps to its posts (its department and the halls round it), and does the jobs a player's cyborg is given the
// tools for:
//  - Engineering: holes in the hull (rods, then a floor tile, from its own synthesisers), fires (its extinguisher), other cyborgs'
//    dents (its welder), cracked windows (silicon.dm).
//  - Janitor: broken and missing lights (its light replacer), litter (its trash bag, emptied into a disposal bin when full), mess.
//  - Medical and Security: as before, from their posts.
// Low on charge, any of them goes to a recharging station and climbs in, as a player does when the cell warning comes up.
//
// Subverted (emagged, or laws that name somebody to go for):
//  - An emagged cyborg stands up for its master (anybody hitting them is the next target) and uses its module's emag tool: the
//    security laser, the engineering stun arm, the hacked hypospray, the lube spray.
//  - Its master dead, it goes after whoever killed them.
//  - A law naming somebody as not human, or to be killed or harmed, has it go for them the way an order would.

#define BORG_CHARGE_LOW 0.2
#define BORG_CHARGE_FULL 0.95
#define BORG_WORK_SIGHT 7
#define BORG_WORK_RANGE 40
/// /obj/machinery/light status (lighting.dm undefines its own)
#define BORG_LIGHT_OK 0

/datum/bot_silicon/borg
	/// Where it's patrolling to, and how long it stays there once it is.
	var/turf/patrol_spot
	var/patrol_linger_until = 0
	/// The recharging station it's on the way to or sitting in.
	var/datum/weakref/charger_ref
	var/next_charger_look = 0
	/// Its master's killer, once they're gone.
	var/datum/weakref/avenge_ref

// ---------------------------------------------------------------------------------------------
// Moving like a player's cyborg
// ---------------------------------------------------------------------------------------------

/// A step at the delay a player's would get (run, plus any slowdown), with the glide set to match so it slides rather than hops.
/datum/bot_silicon/borg/proc/step_delay()
	return max(1, owner.movement_delay())

// ---------------------------------------------------------------------------------------------
// Posts
// ---------------------------------------------------------------------------------------------

/// Area types it keeps to, by module: its department first, then the halls.
/datum/bot_silicon/borg/proc/post_areas()
	var/mob/living/silicon/robot/R = owner
	switch(R.module.type)
		if(/obj/item/robot_module/medical)
			return list(/area/medical, /area/hallway)
		if(/obj/item/robot_module/engineering)
			return list(/area/engine, /area/maintenance, /area/hallway)
		if(/obj/item/robot_module/janitor)
			return list(/area/hallway, /area/crew_quarters, /area/janitor)
		if(/obj/item/robot_module/security)
			return list(/area/security, /area/hallway)
	return list(/area/hallway)

/// Area type -> floor turfs, for picking a spot to walk to. Built once a type is first asked for.
GLOBAL_LIST_EMPTY(bot_borg_post_turfs)

/proc/bot_borg_post_turfs(area_type, z)
	var/key = "[area_type]|[z]"
	var/list/turfs = GLOB.bot_borg_post_turfs[key]
	if(turfs)
		return turfs
	turfs = list()
	for(var/area/A in GLOB.sortedAreas)
		if(!istype(A, area_type))
			continue
		for(var/turf/open/floor/T in A)
			if(T.z == z && !is_blocked_turf(T, TRUE))
				turfs += T
	GLOB.bot_borg_post_turfs[key] = turfs
	return turfs

/// Off to somewhere on its rounds, or stood looking about where it got to. TRUE if that's what it's doing.
/datum/bot_silicon/borg/proc/patrol()
	if(patrol_spot && get_dist(owner, patrol_spot) <= 1)
		patrol_spot = null
		patrol_linger_until = world.time + rand(8, 25) SECONDS
		owner.setDir(pick(GLOB.cardinals))
		return TRUE
	if(world.time < patrol_linger_until)
		return TRUE
	var/list/areas = post_areas()
	for(var/tries in 1 to 4)
		var/area_type = (tries == 1 || prob(60)) ? areas[1] : pick(areas)
		var/list/turfs = bot_borg_post_turfs(area_type, owner.z)
		if(!length(turfs))
			continue
		// Nearer spots more often: a round of its own department, not the length of the station every leg.
		var/turf/best
		for(var/i in 1 to 3)
			var/turf/T = pick(turfs)
			if(!best || get_dist(owner, T) < get_dist(owner, best))
				best = T
		if(get_dist(owner, best) > 70 || get_dist(owner, best) < 4)
			continue
		if(go_to(best, 0))
			patrol_spot = best
			wandering = TRUE //looks for work on the way
			next_job_look = world.time + 2 SECONDS
			return TRUE
	return FALSE

// ---------------------------------------------------------------------------------------------
// Charge
// ---------------------------------------------------------------------------------------------

/datum/bot_silicon/borg/proc/charge_fraction()
	var/mob/living/silicon/robot/R = owner
	if(!R.cell || !R.cell.maxcharge)
		return 1
	return R.cell.charge / R.cell.maxcharge

/// In a station: stays till it's full, then out. Low: to the nearest free working one, in, and the door shut (the click a player
/// makes on it once they're stood in it).
/datum/bot_silicon/borg/proc/see_to_charge()
	var/mob/living/silicon/robot/R = owner
	var/obj/machinery/recharge_station/in_station = R.loc
	if(istype(in_station))
		if(charge_fraction() >= BORG_CHARGE_FULL || (in_station.stat & (NOPOWER|BROKEN)))
			in_station.relaymove(R) //the way out: any move key
			charger_ref = null
			note("charged to [round(charge_fraction() * 100)]%: out of [in_station]")
		return TRUE
	var/obj/machinery/recharge_station/S = charger_ref?.resolve()
	if(!S && (charge_fraction() >= BORG_CHARGE_LOW || world.time < next_charger_look))
		return FALSE
	if(!S || S.occupant || (S.stat & (NOPOWER|BROKEN)) || S.z != owner.z)
		S = find_charger()
		if(!S)
			next_charger_look = world.time + 1 MINUTES
			charger_ref = null
			return FALSE
		charger_ref = WEAKREF(S)
		note("charge at [round(charge_fraction() * 100)]%: off to [S] ([get_area_name(S, TRUE)])")
	if(get_turf(R) == get_turf(S))
		if(S.state_open)
			R.ClickOn(S, "") //attack_robot() -> interact(): shuts it with us inside
		return TRUE
	if(get_dist(R, S) == 1 && S.state_open)
		route = null
		heading_for = null
		R.set_glide_size(DELAY_TO_GLIDE_SIZE(step_delay()))
		step(R, get_dir(R, S))
		return TRUE
	if(heading_for == S && keep_walking())
		return TRUE
	if(!go_to(S, 1))
		charger_ref = null
		next_charger_look = world.time + 1 MINUTES
		return FALSE
	return TRUE

/datum/bot_silicon/borg/proc/find_charger()
	var/obj/machinery/recharge_station/best
	var/best_dist
	for(var/obj/machinery/recharge_station/S as anything in bot_instances_of(/obj/machinery/recharge_station))
		if(QDELETED(S) || S.z != owner.z || S.occupant || !S.state_open || (S.stat & (NOPOWER|BROKEN)) || skipping(S))
			continue
		var/dist = get_dist(owner, S)
		if(!best || dist < best_dist)
			best = S
			best_dist = dist
	return best

// ---------------------------------------------------------------------------------------------
// Engineering
// ---------------------------------------------------------------------------------------------

/// A hole in the hull near enough: a rod over it for a lattice, then a floor tile, from beside it. It needs no air to do it.
/datum/bot_silicon/borg/proc/patch_breach()
	var/turf/open/space/best
	var/best_dist
	for(var/turf/T as anything in GLOB.bot_hull_breaches)
		if(!istype(T, /turf/open/space) || T.z != owner.z || skipping(T))
			continue
		var/dist = get_dist(owner, T)
		if(dist > BORG_WORK_RANGE || (best && dist >= best_dist))
			continue
		best = T
		best_dist = dist
	if(!best)
		return FALSE
	if(!owner.Adjacent(best))
		var/turf/spot = bot_hull_standing_spot(best)
		return spot ? go_to(spot, 0) : FALSE
	if(!(locate(/obj/structure/lattice) in best))
		var/obj/item/stack/rods/rods = tool(/obj/item/stack/rods)
		if(!rods || rods.get_amount() < 1)
			skip(best)
			return FALSE
		use_on(rods, best)
		return TRUE
	var/obj/item/stack/tile/plasteel/tile = tool(/obj/item/stack/tile/plasteel)
	if(!tile || tile.get_amount() < 1)
		skip(best)
		return FALSE
	use_on(tile, best)
	if(!istype(best, /turf/open/space))
		note("patched the hull at [AREACOORD(best)]")
		bot_tally("hull breaches patched by a cyborg")
		GLOB.bot_hull_breaches -= best
	return TRUE

/// Fire in sight: the extinguisher at it, safety off first (it comes on, as anybody's does).
/datum/bot_silicon/borg/proc/put_out_fire()
	var/obj/item/extinguisher/E = tool(/obj/item/extinguisher)
	if(!E || E.reagents.total_volume < 5)
		return FALSE
	var/obj/effect/hotspot/best
	var/best_dist
	for(var/obj/effect/hotspot/H in view(BORG_WORK_SIGHT, owner))
		var/dist = get_dist(owner, H)
		if(!best || dist < best_dist)
			best = H
			best_dist = dist
	var/mob/living/burning
	if(!best)
		for(var/mob/living/L in view(BORG_WORK_SIGHT, owner))
			if(L.on_fire && L != owner)
				burning = L
				break
	var/atom/target = best || burning
	if(!target)
		return FALSE
	if(get_dist(owner, target) > 4)
		return go_to(target, 3)
	if(E.safety)
		E.attack_self(owner)
	use_on(E, target)
	return TRUE

/// Another cyborg knocked about: the welder over its dents, as anybody fixes one.
/datum/bot_silicon/borg/proc/fix_cyborg()
	var/obj/item/weldingtool/welder = tool(/obj/item/weldingtool)
	if(!welder || welder.get_fuel() < 2)
		return FALSE
	for(var/mob/living/silicon/robot/other in view(BORG_WORK_SIGHT, owner))
		if(other == owner || other.stat == DEAD || other.getBruteLoss() < 15 || skipping(other))
			continue
		if(!owner.Adjacent(other))
			return go_to(other)
		if(!welder.welding)
			welder.attack_self(owner)
		use_on(welder, other)
		return TRUE
	return FALSE

// ---------------------------------------------------------------------------------------------
// Janitor
// ---------------------------------------------------------------------------------------------

/// A broken or empty light in sight: its replacer on the tile, from beside it.
/datum/bot_silicon/borg/proc/replace_lights()
	var/obj/item/lightreplacer/replacer = tool(/obj/item/lightreplacer)
	if(!replacer || replacer.uses < 1)
		return FALSE
	var/obj/machinery/light/best
	var/best_dist
	for(var/obj/machinery/light/L in view(BORG_WORK_SIGHT, owner))
		if(L.status == BORG_LIGHT_OK || skipping(L))
			continue
		var/dist = get_dist(owner, L)
		if(!best || dist < best_dist)
			best = L
			best_dist = dist
	if(!best)
		return FALSE
	var/turf/T = get_turf(best)
	if(!owner.Adjacent(T) && get_turf(owner) != T)
		return go_to(T, 1)
	var/was = best.status
	use_on(replacer, T)
	if(best.status == was)
		skip(best) //out of reach behind a window, or nothing came of it
	else
		note("replaced the light in [get_area_name(best, TRUE)]")
	return TRUE

/// Litter on the floor in sight: the trash bag on it. Full, it goes to the nearest disposal bin and empties it in.
/datum/bot_silicon/borg/proc/pick_up_litter()
	var/obj/item/storage/bag/trash/bag = tool(/obj/item/storage/bag/trash)
	if(!bag)
		return FALSE
	var/datum/component/storage/STR = bag.GetComponent(/datum/component/storage)
	if(STR && length(bag.contents) >= STR.max_items - 2)
		return empty_bag(bag)
	var/obj/item/best
	var/best_dist
	for(var/obj/item/trash/I in view(BORG_WORK_SIGHT, owner))
		if(!isturf(I.loc) || skipping(I))
			continue
		var/dist = get_dist(owner, I)
		if(!best || dist < best_dist)
			best = I
			best_dist = dist
	if(!best)
		return FALSE
	if(!owner.Adjacent(best))
		return go_to(best, 1)
	use_on(bag, best)
	if(isturf(best.loc))
		skip(best) //picked up a moment later by the bag's do_after, or wouldn't go in at all: not stood over
	return TRUE

/datum/bot_silicon/borg/proc/empty_bag(obj/item/storage/bag/trash/bag)
	var/obj/machinery/disposal/bin/best
	var/best_dist
	for(var/obj/machinery/disposal/bin/D as anything in bot_instances_of(/obj/machinery/disposal/bin))
		if(QDELETED(D) || D.z != owner.z || skipping(D) || (D.stat & BROKEN))
			continue
		var/dist = get_dist(owner, D)
		if(dist <= BORG_WORK_RANGE && (!best || dist < best_dist))
			best = D
			best_dist = dist
	if(!best)
		return FALSE
	if(!owner.Adjacent(best))
		return go_to(best)
	use_on(bag, best)
	note("emptied [bag] into [best] ([get_area_name(best, TRUE)])")
	return TRUE

// ---------------------------------------------------------------------------------------------
// Subverted
// ---------------------------------------------------------------------------------------------

/// Whoever's been hitting its master in the last little while.
/datum/bot_silicon/borg/proc/master_attacker(mob/living/master)
	var/key_end = ">[REF(master)]"
	var/mob/living/latest
	var/latest_at = 0
	for(var/key in GLOB.bot_recent_aggression)
		var/at = GLOB.bot_recent_aggression[key]
		if(world.time - at > 20 SECONDS || at <= latest_at || !findtext(key, key_end))
			continue
		var/mob/living/L = locate(copytext(key, 1, findtext(key, ">")))
		if(!istype(L) || L == owner || L.stat == DEAD || L.z != owner.z)
			continue
		latest = L
		latest_at = at
	return latest

/// The module's nastiest tool, emag ones first: a laser over the disabler, the stun arm over a welder.
/datum/bot_silicon/borg/proc/weapon_for(mob/living/target)
	var/mob/living/silicon/robot/R = owner
	if(R.emagged)
		var/obj/item/gun/energy/laser/cyborg/laser = tool(/obj/item/gun/energy/laser/cyborg)
		if(laser)
			return laser
		var/obj/item/borg/stun/arm = tool(/obj/item/borg/stun)
		if(arm && owner.Adjacent(target))
			return arm
		var/obj/item/reagent_containers/borghypo/hacked/hypo = tool(/obj/item/reagent_containers/borghypo/hacked)
		if(hypo && owner.Adjacent(target))
			hypo.mode = rand(1, length(hypo.reagent_ids))
			return hypo
	return null

/// Laws that name somebody to hurt, as an uploaded or ion law would: "X is not human", "kill X", "X must be harmed". The living
/// crew it names, nearest first.
/proc/bot_law_targets(mob/living/silicon/S)
	. = list()
	var/datum/ai_laws/L = S.laws
	if(!L)
		return
	var/list/lines = list()
	if(L.zeroth)
		lines += L.zeroth
	lines += L.hacked
	lines += L.ion
	lines += L.supplied
	for(var/law in lines)
		var/lower = lowertext(law)
		if(!bot_text_has_any(lower, list("not human", "nonhuman", "non-human", "kill", "harm", "terminate", "eliminate", "murder", "destroy")))
			continue
		if(findtext(lower, "only") && findtext(lower, "human"))
			continue //"only X is human": somebody to obey, not somebody to go for
		for(var/mob/living/carbon/human/H in GLOB.alive_mob_list)
			if(H.real_name && length(H.real_name) > 2 && findtext(lower, lowertext(H.real_name)))
				. |= H

/// Laws telling it to go for somebody: the nearest of them, as an order would be.
/datum/bot_silicon/borg/proc/law_target()
	var/mob/living/carbon/human/best
	for(var/mob/living/carbon/human/H in bot_law_targets(owner))
		if(H.stat == DEAD || H.z != owner.z)
			continue
		if(!best || get_dist(owner, H) < get_dist(owner, best))
			best = H
	return best

/// Its master's dead: whoever did it, then it lies low.
/datum/bot_silicon/borg/proc/avenge()
	var/mob/living/target = avenge_ref?.resolve()
	if(!target || target.stat == DEAD || target.z != owner.z)
		avenge_ref = null
		return FALSE
	return attack(target)

/// Whatever it has that hurts most, used on them.
/datum/bot_silicon/borg/proc/attack(mob/living/target)
	var/obj/item/special = weapon_for(target)
	if(owner.Adjacent(target))
		use_on(special || hardest_hitter(), target, INTENT_HARM)
		return TRUE
	var/obj/item/gun/G = istype(special, /obj/item/gun) ? special : tool(/obj/item/gun)
	if(G && (target in view(BORG_WORK_SIGHT, owner)))
		use_on(G, target, INTENT_HARM)
		return TRUE
	if(heading_for == target && keep_walking())
		return TRUE
	return go_to(target)

#undef BORG_CHARGE_LOW
#undef BORG_CHARGE_FULL
#undef BORG_WORK_SIGHT
#undef BORG_WORK_RANGE
#undef BORG_LIGHT_OK
