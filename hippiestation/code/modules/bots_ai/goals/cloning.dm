// Cloning: what happens to somebody the paddles can't bring back (goals/treat_patient.dm).
//
// A doctor or a geneticist drags the body to the DNA scanner and shuts it in, scans it at the console beside it, and starts the
// pod, the buttons a player presses. A few minutes later the same person climbs out, with everything they knew and nothing on:
// the bot's brain goes with its mind (/datum/mind/transfer_to(), hippiestation/code/datums/mind.dm). Everything it owns is on the
// body it left, and without its ID it can't get through a door, so that's the first place it goes.
//
// Nobody's left in the scanner: it's opened again, and the body's left by the pod for its owner, and then for the Chaplain. Pod and
// scanner can be a door apart, and a clone has no ID: one woke up behind the shower door with its card on the other side of it.

/// How long a body with somebody to bring back is left alone by the Chaplain, for the doctors to get to it.
#define BOT_CLONE_MORGUE_WAIT (10 MINUTES)
/// How long a body that couldn't be cloned is left before another try.
#define BOT_CLONE_RETRY (5 MINUTES)
/// How many goes a clone has at getting to its old body, a door being in the way of it, and how far apart.
#define BOT_RECLAIM_TRIES 5
#define BOT_RECLAIM_GAP (45 SECONDS)

/datum/bot_brain
	/// The body it was in before it was cloned, while its things are still on it.
	var/mob/living/carbon/human/old_body
	/// Body -> when it's worth another try.
	var/list/clone_blocked
	/// Goes it's had at getting its things back, and when it next can.
	var/reclaim_tries = 0
	var/next_reclaim_time = 0

/// Whether a clone's coming back for this body, with its ID and everything else still on it. The doctor who'd just cloned somebody
/// used to file the old one in the morgue a few seconds later, and all of them climbed out to nothing.
/proc/bot_body_wanted_back(mob/living/carbon/human/H)
	var/mob/living/carbon/human/now = H.last_mind?.current
	return istype(now) && now != H && now.bot_brain?.old_body == H

/// Into the new body the mind has just gone to: the same person, whatever they were in the middle of aside.
/datum/bot_brain/proc/move_to_body(mob/living/carbon/human/new_body)
	var/mob/living/carbon/human/body_before = owner
	drop_goals("waking up somewhere else")
	attacker = null
	state = BOT_STATE_WANDER
	var/fake_key = body_before.key
	body_before.bot_brain = null
	GLOB.bot_crew_members -= body_before
	body_before.key = null
	owner = new_body
	new_body.bot_brain = src
	new_body.key = fake_key
	GLOB.bot_crew_members |= new_body
	old_body = body_before
	reclaim_tries = 0
	next_reclaim_time = 0
	asked_after_things = FALSE
	if(!owner.hud_used) //see New()
		owner.hud_used = new owner.hud_type(owner)
		owner.update_sight()
		SEND_SIGNAL(owner, COMSIG_MOB_HUD_CREATED)
	bot_log(src, "in a new body, in [get_area_name(owner)]")

/// A working cloner: a console with its scanner, and a pod with nobody in it.
/datum/bot_brain/proc/find_cloner()
	var/best_dist
	for(var/obj/machinery/computer/cloning/C as anything in bot_instances_of(/obj/machinery/computer/cloning))
		if(QDELETED(C) || C.z != owner.z || (C.stat & (NOPOWER|BROKEN)))
			continue
		C.updatemodules(TRUE)
		var/obj/machinery/dna_scannernew/S = C.scanner
		if(!S || !S.is_operational() || S.locked || (S.occupant && !S.state_open) || !C.GetAvailablePod())
			continue
		if(gym_run && get_area(C) != get_area(owner))
			continue
		var/dist = get_dist(owner, C)
		if(!. || dist < best_dist)
			. = C
			best_dist = dist

/// The scanner's own refusals (cloning.dm, scan_occupant()), read before anybody drags anything anywhere.
/proc/bot_clonable(mob/living/carbon/human/H)
	if(QDELETED(H) || H.stat != DEAD || !H.mind || H.mind.current != H || H.mind.no_cloning_at_all || H.mind.damnation_type)
		return FALSE
	if(H.suiciding || H.hellbound || HAS_TRAIT(H, TRAIT_HUSK) || HAS_TRAIT(H, TRAIT_BADDNA) || !H.has_dna())
		return FALSE
	return !!H.bot_brain || !!H.mind.get_ghost() //a player has to be there to come back to it

/// The nearest body it can get to, and get to the scanner from.
/datum/bot_brain/proc/find_body_to_clone(obj/machinery/computer/cloning/console)
	// The one somebody asked it to clone (bot_asks.dm), once whoever brought it has let go of it.
	var/mob/living/carbon/human/asked = clone_wanted?.resolve()
	if(asked && world.time < clone_wanted_until && asked.z == owner.z && isturf(asked.loc) && !asked.buckled && !asked.pulledby && bot_clonable(asked) && !taken_by_another(asked) && can_walk_lawfully_to(asked))
		return asked
	var/list/bodies = list() //body -> how far off
	for(var/mob/living/carbon/human/H in GLOB.dead_mob_list)
		if(H.z != owner.z || !isturf(H.loc) || H.buckled || H.pulledby || !bot_clonable(H))
			continue
		if(LAZYACCESS(clone_blocked, H) > world.time || taken_by_another(H))
			continue
		if(gym_run && get_area(H) != get_area(owner))
			continue
		bodies[H] = get_dist(owner, H)
	var/tries = 0
	while(length(bodies) && tries++ < 3)
		var/mob/living/carbon/human/nearest
		for(var/mob/living/carbon/human/H as anything in bodies)
			if(!nearest || bodies[H] < bodies[nearest])
				nearest = H
		bodies -= nearest
		if(can_walk_lawfully_to(nearest))
			return nearest
		LAZYSET(clone_blocked, nearest, world.time + BOT_CLONE_RETRY)
	return null

/datum/bot_goal/clone_body
	doing = "taking somebody to the cloner"
	exclusive = TRUE
	var/obj/machinery/computer/cloning/console
	var/obj/machinery/dna_scannernew/scanner
	var/turf/scanner_spot
	var/turf/console_spot
	var/turf/pod_spot

/datum/bot_goal/clone_body/resolve_target(datum/bot_brain/bot)
	console = bot.find_cloner()
	if(!console)
		return
	scanner = console.scanner
	scanner_spot = bot.spot_beside(scanner)
	console_spot = bot.spot_beside(console)
	pod_spot = bot.spot_beside(console.GetAvailablePod()) //a pod in a corner has none: the body stays by the scanner
	if(!scanner_spot || !console_spot)
		return
	target = bot.find_body_to_clone(console)

/datum/bot_goal/clone_body/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/clone_body/S = new
	var/datum/bot_step/move_to/to_scanner = new
	to_scanner.step_target = scanner_spot
	var/datum/bot_step/move_to/to_console = new
	to_console.step_target = console_spot
	var/datum/bot_step/move_to/back_to_scanner = new
	back_to_scanner.step_target = scanner_spot
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/take_hold_of_body(), to_scanner, new /datum/bot_step/load_scanner(), to_console, new /datum/bot_step/paced/work_cloner(), back_to_scanner, new /datum/bot_step/open_scanner())
	if(pod_spot)
		var/datum/bot_step/move_to/to_pod = new
		to_pod.step_target = pod_spot
		S.steps += list(new /datum/bot_step/take_hold_of_body(), to_pod, new /datum/bot_step/let_go_of_body())
	return list(S)

/datum/bot_goal/clone_body/on_give_up(datum/bot_brain/bot)
	bot.owner.stop_pulling()
	if(target)
		LAZYSET(bot.clone_blocked, target, world.time + BOT_CLONE_RETRY)
	if(scanner?.occupant == target && !scanner.state_open && bot.owner.Adjacent(scanner))
		scanner.open_machine()

/datum/bot_strategy/clone_body/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// At the scanner with the body in tow: open it if it's shut, and in they go.
/datum/bot_step/load_scanner/execute(datum/bot_brain/bot)
	var/datum/bot_goal/clone_body/G = bot.current_goal
	var/mob/living/body = G?.target
	var/obj/machinery/dna_scannernew/S = istype(G) ? G.scanner : null
	if(QDELETED(body) || QDELETED(S) || bot.owner.pulling != body || !bot.owner.Adjacent(S) || S.locked)
		return GOAL_STEP_FAIL
	if(!S.state_open)
		if(S.occupant)
			return GOAL_STEP_FAIL //somebody got there first
		bot.use_atom(S)
		if(!S.state_open)
			return GOAL_STEP_FAIL
	bot.human_pause(S)
	if(QDELETED(body) || QDELETED(S) || !bot.owner.Adjacent(S) || !bot.owner.Adjacent(body))
		return GOAL_STEP_FAIL
	bot.owner.face_atom(S)
	bot.owner.stop_pulling()
	bot.telemetry_event("drag_onto", list("what" = "[body]", "onto" = "[S]"))
	S.MouseDrop_T(body, bot.owner)
	return S.occupant == body ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// The console's two buttons, a click each: scan, and clone (cloning.dm, Topic()).
/datum/bot_step/paced/work_cloner
	max_clicks = 4
	var/started = FALSE

/datum/bot_step/paced/work_cloner/start(datum/bot_brain/bot)
	var/datum/bot_goal/clone_body/G = bot.current_goal
	started = FALSE
	return istype(G) && !QDELETED(G.console) && bot.owner.Adjacent(G.console) && G.scanner?.occupant == G.target

/datum/bot_step/paced/work_cloner/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/clone_body/G = bot.current_goal
	var/mob/living/carbon/human/body = G.target
	var/obj/machinery/computer/cloning/C = G.console
	if(started || QDELETED(C) || QDELETED(body) || !bot.owner.Adjacent(C))
		return FALSE
	bot.human_pause(C)
	if(QDELETED(C) || QDELETED(body) || !bot.owner.Adjacent(C))
		return FALSE
	bot.owner.face_atom(C)
	var/datum/data/record/R = find_record("mindref", REF(body.mind), C.records)
	if(!R)
		bot.telemetry_ui_action(C, "scan")
		C.scan_occupant(G.scanner.occupant, bot.owner, FALSE)
		wait_for = 2 SECONDS //the console takes a moment over a scan
		clicks++
		if(!find_record("mindref", REF(body.mind), C.records))
			bot_log(bot, "the scan of [body] failed: [strip_html(C.scantemp)]")
			return FALSE
		return TRUE
	var/obj/machinery/clonepod/pod = C.GetAvailablePod()
	if(!pod || pod.occupant || !CONFIG_GET(flag/revival_cloning))
		return FALSE
	bot.telemetry_ui_action(C, "clone [body.real_name]")
	var/result = grow_clone_from_record(pod, R, FALSE)
	if(result & CLONING_SUCCESS)
		started = TRUE
		bot_log(bot, "cloning [body.real_name]")
		bot_tally("clones started")
	if(result & CLONING_DELETE_RECORD)
		C.records -= R
	return FALSE

/datum/bot_step/paced/work_cloner/finish(datum/bot_brain/bot)
	return started ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// The body out of the scanner again: the next one needs it, and its owner wants what's on it.
/datum/bot_step/open_scanner/execute(datum/bot_brain/bot)
	var/datum/bot_goal/clone_body/G = bot.current_goal
	var/obj/machinery/dna_scannernew/S = istype(G) ? G.scanner : null
	if(!QDELETED(S) && !S.state_open && bot.owner.Adjacent(S))
		bot.use_atom(S)
	return GOAL_STEP_SUCCESS

/// By the pod, for whoever climbs out of it.
/datum/bot_step/let_go_of_body/execute(datum/bot_brain/bot)
	bot.owner.stop_pulling()
	return GOAL_STEP_SUCCESS

/// What's next on the list, for a clone with nothing on. The uniform comes first, for everything that hangs off one, and what falls
/// out of it lands by the body, in reach.
GLOBAL_LIST_INIT(bot_clone_dress_order, list(ITEM_SLOT_ICLOTHING, ITEM_SLOT_FEET, ITEM_SLOT_ID, ITEM_SLOT_BELT, ITEM_SLOT_BACK, ITEM_SLOT_OCLOTHING, ITEM_SLOT_GLOVES, ITEM_SLOT_HEAD, ITEM_SLOT_MASK, ITEM_SLOT_EYES, ITEM_SLOT_EARS, ITEM_SLOT_LPOCKET, ITEM_SLOT_RPOCKET))

/// Out of the pod with the clone's damage on it, and its things back: into a cryo cell with something in it to mend that, until it's fit to
/// get up (convalescing(), bot_goals.dm), and how fit that is goes by its nerve. The user's ruling (2026-11-10): "cloned bodies need their
/// stuff back and need to go into cryo cells to fix their genetic damage after cloning". In their round two of the crew came out of the
/// pod at 60 cloning damage and went straight back to the man who'd killed them, and died again.
/datum/bot_duty/clone_recovery
	name = "getting the cloning damage seen to"
	tier = BOT_DUTY_URGENT
	priority = 39 //just after getting its things back
	interval_min = 10
	interval_max = 20

/datum/bot_duty/clone_recovery/applies_to(datum/bot_brain/bot)
	return TRUE

/datum/bot_duty/clone_recovery/try_start(datum/bot_brain/bot)
	var/mob/living/carbon/human/H = bot.owner
	if(H.getCloneLoss() < 10 || bot.old_body || istype(H.loc, /obj/machinery/atmospherics/components/unary/cryo_cell) || bot.state == BOT_STATE_COMBAT)
		return FALSE
	if(world.time < bot.next_clone_recovery) //been in once lately: a cell that isn't cold enough mends nothing, and it isn't going back every few minutes
		return FALSE
	if(H.health >= H.maxHealth * clamp(0.75 - 0.6 * bot.nerve, 0.15, 0.75))
		return FALSE //the fearless shrug it off
	var/obj/machinery/atmospherics/components/unary/cryo_cell/C = bot.cryo_for_cloning_damage()
	if(!C)
		return FALSE
	var/datum/bot_goal/clone_recovery/G = new()
	G.cell = C
	return bot.assign_goal(G)

/// A free cryo cell with cryoxadone or clonexadone in its beaker, the nearest it can walk to
/datum/bot_brain/proc/cryo_for_cloning_damage()
	var/obj/machinery/atmospherics/components/unary/cryo_cell/best
	var/best_dist
	for(var/obj/machinery/atmospherics/components/unary/cryo_cell/C as anything in bot_instances_of(/obj/machinery/atmospherics/components/unary/cryo_cell))
		if(QDELETED(C) || C.z != owner.z || C.occupant || (C.stat & (BROKEN|NOPOWER)) || !C.beaker)
			continue
		if(gym_run && get_area(C) != get_area(owner))
			continue
		if(!C.beaker.reagents?.has_reagent(/datum/reagent/medicine/cryoxadone) && !C.beaker.reagents?.has_reagent(/datum/reagent/medicine/clonexadone))
			continue
		var/dist = get_dist(owner, C)
		if((!best || dist < best_dist) && can_walk_lawfully_to(C))
			best = C
			best_dist = dist
	return best

/datum/bot_goal/clone_recovery
	doing = "getting into cryo"
	var/obj/machinery/atmospherics/components/unary/cryo_cell/cell

/datum/bot_goal/clone_recovery/resolve_target(datum/bot_brain/bot)
	if(cell && !QDELETED(cell) && !cell.occupant)
		target = cell

/datum/bot_goal/clone_recovery/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/self_admit(cell)) //goals/self_heal.dm

/datum/bot_goal/clone_recovery/on_success(datum/bot_brain/bot)
	bot_log(bot, "in [cell] for the cloning damage")
	bot.next_clone_recovery = world.time + 10 MINUTES

/datum/bot_brain
	/// Not into cryo for the cloning damage again before this (the duty above)
	var/next_clone_recovery = 0

/datum/bot_duty/reclaim_belongings
	name = "getting my things back"
	tier = BOT_DUTY_URGENT
	priority = 40
	interval_min = 30
	interval_max = 80

/datum/bot_duty/reclaim_belongings/applies_to(datum/bot_brain/bot)
	return TRUE

/datum/bot_duty/reclaim_belongings/try_start(datum/bot_brain/bot)
	if(!bot.old_body || world.time < bot.next_reclaim_time)
		return FALSE
	if(QDELETED(bot.old_body))
		bot.old_body = null
		return FALSE
	// Stripped: somebody's had its things, and it asks who (goals/own_upkeep.dm).
	if(!length(bot.old_body.get_equipped_items(TRUE)))
		bot.ask_after_my_things(bot.old_body)
		bot.old_body = null
		return FALSE
	// In a morgue tray or a body bag it gets it out (body_out); anywhere else (somebody's carrying it, a machine) it can't.
	var/atom/holder = bot.old_body.loc
	if(!isturf(holder) && !istype(holder, /obj/structure/bodycontainer) && !istype(holder, /obj/structure/closet))
		bot.old_body = null
		return FALSE
	return bot.assign_goal(new /datum/bot_goal/reclaim_belongings())

/datum/bot_goal/reclaim_belongings
	doing = "getting my things back"

/datum/bot_goal/reclaim_belongings/resolve_target(datum/bot_brain/bot)
	target = bot.old_body

/datum/bot_goal/reclaim_belongings/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/reclaim_belongings/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/body_out(), new /datum/bot_step/paced/take_things_back())
	return list(S)

/datum/bot_goal/reclaim_belongings/on_success(datum/bot_brain/bot)
	bot.old_body = null
	bot_log(bot, "got my things back")

/// With no ID there may be a door in the way, and somebody on the other side of it sooner or later (bot_requests.dm).
/datum/bot_goal/reclaim_belongings/on_give_up(datum/bot_brain/bot)
	bot.next_reclaim_time = world.time + BOT_RECLAIM_GAP
	if(bot.old_body && !bot.can_walk_lawfully_to(bot.old_body)) //no ID to get through the door with: it asks (goals/own_upkeep.dm)
		bot.ask_to_be_let_in_for_body(bot.old_body)
	if(++bot.reclaim_tries >= BOT_RECLAIM_TRIES)
		bot.old_body = null

/datum/bot_strategy/reclaim_belongings/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// A thing at a time, the way a player strips a body: off it, and on.
/datum/bot_step/paced/take_things_back
	max_clicks = 16
	/// Item -> the slot it goes back in, taken down before anything comes off.
	var/list/wanted

/datum/bot_step/paced/take_things_back/start(datum/bot_brain/bot)
	var/mob/living/carbon/human/body = bot.current_goal?.target
	if(!istype(body) || !bot.owner.Adjacent(body))
		return FALSE
	wanted = list()
	for(var/slot in GLOB.bot_clone_dress_order)
		var/obj/item/I = body.get_item_by_slot(slot)
		if(I)
			wanted[I] = slot
	return length(wanted) > 0

/datum/bot_step/paced/take_things_back/do_click(datum/bot_brain/bot)
	var/mob/living/carbon/human/body = bot.current_goal?.target
	while(length(wanted))
		var/obj/item/I = wanted[1]
		var/slot = wanted[I]
		wanted -= I
		if(QDELETED(I) || (I.loc != body && !bot.owner.Adjacent(I)))
			continue
		bot.human_pause(I)
		if(QDELETED(I) || QDELETED(body))
			continue
		if(I.loc == body)
			body.dropItemToGround(I, TRUE)
		if(!bot.owner.equip_to_slot_if_possible(I, slot, FALSE, TRUE, TRUE))
			bot.try_pickup_target(I)
		return TRUE
	return FALSE

/datum/bot_step/paced/take_things_back/finish(datum/bot_brain/bot)
	wanted = null
	return GOAL_STEP_SUCCESS

#undef BOT_CLONE_RETRY
#undef BOT_RECLAIM_TRIES
#undef BOT_RECLAIM_GAP
