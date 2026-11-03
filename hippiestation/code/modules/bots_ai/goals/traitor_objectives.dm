// Traitor objectives past killing and stealing (goals/traitor.dm).
//
//  - Download: the station's research on a technology disk. A disk comes off a protolathe (it's in every techweb from the start), and
//    the R&D console puts the research on it: the disk in, "Load Technology to Disk", the disk out. The tree has to have grown for it
//    to count, so it goes back every so often and copies it again, the way a player tops their disk up before the shuttle.

/// Between one copy and the next, while the station's research is still short of what the objective wants.
#define BOT_DOWNLOAD_AGAIN (8 MINUTES)
/// After a try that didn't come off: no lathe with the materials, no console it could get to.
#define BOT_DOWNLOAD_RETRY (2 MINUTES)

/datum/bot_brain/proc/carried_tech_disk()
	return locate(/obj/item/disk/tech_disk) in owner.GetAllContents()

/// A protolathe that can print a technology disk right now.
/datum/bot_brain/proc/find_disk_lathe()
	var/datum/design/D = SSresearch.techweb_design_by_id("tech_disk")
	var/obj/machinery/rnd/production/protolathe/best
	var/best_dist
	for(var/obj/machinery/rnd/production/protolathe/L as anything in bot_instances_of(/obj/machinery/rnd/production/protolathe))
		if(QDELETED(L) || L.z != owner.z || L.panel_open || (L.stat & (BROKEN|NOPOWER)) || L.busy || !L.materials?.mat_container || L.materials.on_hold())
			continue
		if(gym_run && get_area(L) != get_area(owner)) //the arena next door is somebody else's
			continue
		if(L.requires_console && !L.linked_console?.stored_research?.researched_designs[D.id])
			continue
		if(!bot_lathe_can_afford(L, D, 1)) //goals/rnd_bench.dm
			continue
		var/dist = get_dist(owner, L)
		if(!best || dist < best_dist)
			best = L
			best_dist = dist
	return best

/// An R&D console on the station's research that will take a disk.
/datum/bot_brain/proc/find_download_console()
	var/obj/machinery/computer/rdconsole/best
	var/best_dist
	for(var/obj/machinery/computer/rdconsole/C as anything in bot_instances_of(/obj/machinery/computer/rdconsole))
		if(QDELETED(C) || C.z != owner.z || (C.stat & (BROKEN|NOPOWER)) || C.locked || C.stored_research != SSresearch.science_tech || C.t_disk)
			continue
		if(gym_run && get_area(C) != get_area(owner))
			continue
		var/dist = get_dist(owner, C)
		if(!best || dist < best_dist)
			best = C
			best_dist = dist
	return best

/datum/bot_goal/traitor_download
	doing = "on an errand"
	breaks_in = TRUE
	var/datum/objective/download/objective

/datum/bot_goal/traitor_download/New(datum/objective/download/O)
	. = ..()
	objective = O

/// No disk yet: a lathe to print one. With one: a console to put the research on it.
/datum/bot_goal/traitor_download/resolve_target(datum/bot_brain/bot)
	target = bot.carried_tech_disk() ? bot.find_download_console() : bot.find_disk_lathe()

/datum/bot_goal/traitor_download/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/traitor_download/S = new
	S.steps = list(new /datum/bot_step/move_to(), istype(target, /obj/machinery/computer/rdconsole) ? new /datum/bot_step/paced/copy_research() : new /datum/bot_step/paced/print_tech_disk())
	return list(S)

/datum/bot_goal/traitor_download/on_success(datum/bot_brain/bot)
	if(istype(target, /obj/machinery/computer/rdconsole))
		LAZYSET(bot.objectives_parked, objective, world.time + BOT_DOWNLOAD_AGAIN) //disk printed: straight on to a console next time

/datum/bot_goal/traitor_download/on_give_up(datum/bot_brain/bot)
	LAZYSET(bot.objectives_parked, objective, world.time + BOT_DOWNLOAD_RETRY)

/datum/bot_strategy/traitor_download/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// The protolathe's print link for a technology disk, and the disk off its tile once it's out.
/datum/bot_step/paced/print_tech_disk
	max_clicks = 3
	var/printed = FALSE

/datum/bot_step/paced/print_tech_disk/start(datum/bot_brain/bot)
	printed = FALSE
	return bot.owner.Adjacent(bot.current_goal?.target)

/datum/bot_step/paced/print_tech_disk/do_click(datum/bot_brain/bot)
	var/obj/machinery/rnd/production/protolathe/L = bot.current_goal?.target
	if(!istype(L) || QDELETED(L) || !bot.owner.Adjacent(L))
		return FALSE
	if(!printed)
		bot.human_pause(L)
		bot.owner.face_atom(L)
		bot.telemetry_ui_action(L, "print Technology Data Storage Disk")
		if(!L.user_try_print_id("tech_disk", 1))
			return FALSE
		printed = TRUE
		wait_for = 4 SECONDS //it takes a moment to come out
		return TRUE
	var/obj/item/disk/tech_disk/disk = locate() in get_turf(L)
	if(!disk)
		wait_for = 2 SECONDS
		return TRUE
	if(bot.try_pickup_target(disk))
		bot.stash_stolen(disk)
	return FALSE

/datum/bot_step/paced/print_tech_disk/finish(datum/bot_brain/bot)
	return bot.carried_tech_disk() ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// The disk in, the research onto it, the disk out and away: three clicks on the console, the way its menu has them.
/datum/bot_step/paced/copy_research
	max_clicks = 4
	var/stage = 0

/datum/bot_step/paced/copy_research/start(datum/bot_brain/bot)
	stage = 0
	return bot.owner.Adjacent(bot.current_goal?.target)

/datum/bot_step/paced/copy_research/do_click(datum/bot_brain/bot)
	var/obj/machinery/computer/rdconsole/C = bot.current_goal?.target
	if(!istype(C) || QDELETED(C) || !bot.owner.Adjacent(C) || (C.stat & (BROKEN|NOPOWER)))
		return FALSE
	bot.human_pause(C)
	bot.owner.face_atom(C)
	usr = bot.owner
	switch(stage)
		if(0)
			var/obj/item/disk/tech_disk/disk = bot.carried_tech_disk()
			if(!disk || !bot.ready_in_hand(disk))
				return FALSE
			bot.use_item_on(disk, C)
			if(C.t_disk != disk)
				return FALSE
		if(1)
			bot.telemetry_ui_action(C, "load technology to disk")
			C.Topic(null, list("copy_tech" = "1"))
		if(2)
			bot.telemetry_ui_action(C, "eject technology disk")
			var/obj/item/disk/tech_disk/disk = C.t_disk
			C.Topic(null, list("eject_tech" = "1"))
			if(disk && bot.try_pickup_target(disk))
				bot.stash_stolen(disk)
			stage++
			return FALSE
	stage++
	return TRUE

/datum/bot_step/paced/copy_research/finish(datum/bot_brain/bot)
	var/obj/item/disk/tech_disk/disk = bot.carried_tech_disk()
	if(!disk)
		return GOAL_STEP_FAIL
	bot_log(bot, "copied the research: [length(disk.stored_research.researched_nodes)] nodes on the disk")
	bot.telemetry_event("download", list("nodes" = length(disk.stored_research.researched_nodes)))
	return GOAL_STEP_SUCCESS

#undef BOT_DOWNLOAD_AGAIN
#undef BOT_DOWNLOAD_RETRY

// ---------------------------------------------------------------------------------------------
// Hijack
// ---------------------------------------------------------------------------------------------
// The shuttle gets to CentCom with nobody loyal alive aboard it and out of custody (is_hijacked(), emergency.dm: the brig's red floor
// counts as custody). The traitor does its other business through the shift like anybody and boards with everybody else. Once the
// doors are about to shut it starts on whoever's aboard, nearest first, and keeps on through the flight: nobody new can get aboard by
// then, and Security on the station can't get to it.

/// How long before the shuttle leaves a hijacker starts on the people aboard.
#define BOT_HIJACK_START (45 SECONDS)

/datum/bot_brain
	var/hijack_started = FALSE
	var/hijack_noted = FALSE

/datum/bot_brain/proc/hijack_objective()
	var/datum/antagonist/traitor/T = owner.mind?.has_antag_datum(/datum/antagonist/traitor)
	return T && (locate(/datum/objective/hijack) in T.objectives)

/// Aboard, with the shuttle about to go or gone.
/datum/bot_brain/proc/hijack_time()
	var/obj/docking_port/mobile/emergency/E = SSshuttle.emergency
	if(!E || !bot_aboard_shuttle(owner) || !hijack_objective())
		return FALSE
	if(E.mode == SHUTTLE_IGNITING || E.mode == SHUTTLE_ESCAPE)
		return TRUE
	return E.mode == SHUTTLE_DOCKED && E.timeLeft(1) <= BOT_HIJACK_START

/// Everybody aboard who'd stop it counting as hijacked: loyal crew, alive, and not held in the brig.
/proc/bot_shuttle_loyalists()
	. = list()
	var/obj/docking_port/mobile/emergency/E = SSshuttle.emergency
	if(!E?.shuttle_areas)
		return
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H.stat == DEAD || !H.mind || !E.shuttle_areas[get_area(H)] || H.mind.has_antag_datum(/datum/antagonist))
			continue
		var/turf/T = get_turf(H)
		if(istype(T, /turf/open/floor/plasteel/shuttle/red) || istype(T, /turf/open/floor/mineral/plastitanium/red/brig))
			continue
		. += H

/// From the evacuation duty, for a bot aboard (goals/evacuate.dm), which otherwise just has it sit tight.
/datum/bot_brain/proc/hijack_business()
	if(!hijack_time() || owner.incapacitated())
		return FALSE
	if(istype(current_goal, /datum/bot_goal/traitor_kill/robust/hijack))
		return TRUE
	var/list/aboard = bot_shuttle_loyalists()
	var/mob/living/carbon/human/nearest
	for(var/mob/living/carbon/human/H as anything in aboard)
		if(LAZYACCESS(robust_rested, WEAKREF(H)) > world.time)
			continue
		if(!nearest || get_dist(owner, H) < get_dist(owner, nearest))
			nearest = H
	if(!length(aboard))
		if(!hijack_noted)
			hijack_noted = TRUE
			log_game("BOT HIJACK: [owner.real_name] has the shuttle to itself (hijacked: [SSshuttle.emergency.is_hijacked() ? "yes" : "no"])")
		return FALSE
	if(!nearest)
		return FALSE
	if(!hijack_started)
		hijack_started = TRUE
		log_game("BOT HIJACK: [owner.real_name] starts on the shuttle, [length(aboard)] loyal aboard")
		var/obj/item/melee/transforming/energy/sword/S = find_carried_tool(/obj/item/melee/transforming/energy/sword)
		if(S && ready_in_hand(S) && !S.active)
			toggle_in_hand(S)
		say_something_hostile()
	return assign_goal(new /datum/bot_goal/traitor_kill/robust/hijack(null, nearest))

/datum/bot_goal/traitor_kill/robust/hijack
	doing = "taking the shuttle"

/datum/bot_goal/traitor_kill/robust/hijack/on_give_up(datum/bot_brain/bot)
	if(mark_ref)
		LAZYSET(bot.robust_rested, mark_ref, world.time + 10 SECONDS) //somebody else first, then back to them
	bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, hijack_business)), TRUE)

/datum/bot_goal/traitor_kill/robust/hijack/on_success(datum/bot_brain/bot)
	bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, hijack_business)), TRUE)

#undef BOT_HIJACK_START
