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
