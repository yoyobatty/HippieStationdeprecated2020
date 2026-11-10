// Surgery. Doctors had none: somebody out cold with the sleepers full was left where they lay, because a bandage only goes so far and the
// paddles are for the dead. The commonest operation on any server is tending wounds, on a table, so that's what's here. It's the same
// clicks a player makes: the tools off the Surgery tables, the patient dragged over and put on the table, then each step with the right
// tool in hand (surgery_step.dm), and the wound closed after.
//
// Two things aren't a player's way. Starting an operation asks for a choice in an input() window that never answers for a bot, so the
// procedure is started directly, as attempt_initiate_surgery() does with the answer. And it doesn't strip them first, because a uniform
// taking the ID, belt and pockets with it would leave a bot with nothing to walk out with. What a doctor does for the dead is unchanged:
// the paddles work for two minutes and the body's mostly past surgery by then, so that's cloning (goals/cloning.dm).

/// Brute or burn a patient has to have to be worth a table.
#define BOT_SURGERY_HURT 40
/// Below this it closes up: a scratch isn't worth an open chest.
#define BOT_SURGERY_DONE 10
/// How far a doctor goes for one.
#define BOT_SURGERY_RANGE 40
/// Tries at fetching one tool, before going without.
#define BOT_SURGERY_FETCHES 2

GLOBAL_LIST_INIT(bot_surgery_tools, list(/obj/item/scalpel, /obj/item/retractor, /obj/item/hemostat, /obj/item/cautery))

/// The nearest operating table with nobody on it.
/datum/bot_brain/proc/find_free_optable()
	var/obj/structure/table/optable/best
	var/best_dist
	for(var/obj/structure/table/optable/T as anything in bot_instances_of(/obj/structure/table/optable))
		if(QDELETED(T) || T.z != owner.z || (gym_run && get_area(T) != get_area(owner)))
			continue
		var/occupied = FALSE
		for(var/mob/living/L in T.loc)
			if(L.stat != DEAD)
				occupied = TRUE
				break
		if(occupied)
			continue
		var/dist = get_dist(owner, T)
		if((!best || dist < best_dist) && can_walk_lawfully_to(T))
			best = T
			best_dist = dist
	return best

/// Somebody down and badly hurt, on the floor where a doctor can get at them.
/datum/bot_brain/proc/find_surgery_patient()
	var/mob/living/carbon/human/best
	var/best_score
	for(var/mob/living/carbon/human/H in GLOB.alive_mob_list)
		if(H == owner || H.z != owner.z || H.stat == CONSCIOUS || H.stat == DEAD || !isturf(H.loc) || H.handcuffed)
			continue
		if(max(H.getBruteLoss(), H.getFireLoss()) < BOT_SURGERY_HURT || LAZYACCESS(unreachable_patients, H) > world.time)
			continue
		var/dist = get_dist(owner, H)
		if(dist > BOT_SURGERY_RANGE || (gym_run && get_area(H) != get_area(owner)))
			continue
		var/score = patient_injury_score(H) - dist
		if(!best || score > best_score)
			best = H
			best_score = score
	return best

/datum/bot_goal/operate
	lawful = TRUE
	exclusive = TRUE
	doing = "operating on somebody"
	var/obj/structure/table/optable/table

/datum/bot_goal/operate/resolve_target(datum/bot_brain/bot)
	var/mob/living/carbon/human/patient = bot.find_surgery_patient()
	if(!patient)
		return
	// Somebody it can walk to. It used to fetch all four tools first and then find the patient was in the engine room, behind doors
	// its ID doesn't open: six of the six operations that got their tools in a batch ended at "no path" to the patient.
	if(!bot.can_walk_lawfully_to(patient))
		LAZYSET(bot.unreachable_patients, patient, world.time + 2 MINUTES) //goals/treat_patient.dm
		bot.cant_reach_casualty(patient) //goals/carry_casualty.dm
		return
	table = bot.find_free_optable()
	if(table)
		target = patient

/datum/bot_goal/operate/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/operate/S = new
	var/datum/bot_step/move_to/to_table = new
	to_table.step_target = table
	S.steps = list(new /datum/bot_step/surgery_tools(), new /datum/bot_step/move_to(), new /datum/bot_step/grab_patient(), to_table, new /datum/bot_step/onto_table(), new /datum/bot_step/paced/operate())
	return list(S)

/datum/bot_goal/operate/on_success(datum/bot_brain/bot)
	bot.owner.stop_pulling()
	bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, after_operating), table))

/datum/bot_goal/operate/on_give_up(datum/bot_brain/bot)
	bot.owner.stop_pulling()
	bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, after_operating), table))

// The tools go back when it's done with them, or has given up. There's one set in Surgery, and whoever went for it first kept what
// it had got in its bag: on MetaStation a doctor who found the scalpel and not the retractor walked off with the scalpel, and the
// other two doctors tried the same patient eight times between them with "knows of no scalpel".

/// The table by an operating table that the tools are kept on: the nearest to this bot that isn't an operating table itself.
/datum/bot_brain/proc/surgery_tray(obj/structure/table/optable/near)
	var/obj/structure/table/best
	var/best_dist
	for(var/obj/structure/table/T in range(4, near))
		if(QDELETED(T) || istype(T, /obj/structure/table/optable))
			continue
		var/dist = get_dist(owner, T)
		if(!best || dist < best_dist)
			best = T
			best_dist = dist
	return best

/// After an operation, done or given up: the tools back on the tray, then the rest of the round.
/datum/bot_brain/proc/after_operating(obj/structure/table/optable/near)
	if(state != BOT_STATE_WANDER || current_goal)
		return
	var/list/tools = list()
	for(var/tool_type in GLOB.bot_surgery_tools)
		var/obj/item/I = find_carried_tool(tool_type)
		if(I)
			tools += I
	var/obj/structure/table/tray = (length(tools) && !QDELETED(near)) ? surgery_tray(near) : null
	if(tray && assign_goal(new /datum/bot_goal/return_surgery_tools(tray, tools)))
		return
	try_medical_round()

/datum/bot_goal/return_surgery_tools
	lawful = TRUE
	doing = "putting the surgery tools back"
	var/obj/structure/table/tray
	var/list/tools

/datum/bot_goal/return_surgery_tools/New(obj/structure/table/T, list/L)
	tray = T
	tools = L

/datum/bot_goal/return_surgery_tools/resolve_target(datum/bot_brain/bot)
	target = QDELETED(tray) ? null : tray

/datum/bot_goal/return_surgery_tools/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/return_surgery_tools/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/empty_into(tray, tools)) //goals/clear_bag.dm
	return list(S)

/datum/bot_strategy/return_surgery_tools/is_feasible(datum/bot_brain/bot)
	return TRUE

/datum/bot_goal/return_surgery_tools/on_success(datum/bot_brain/bot)
	bot.continue_medical_round()

/datum/bot_strategy/operate/is_feasible(datum/bot_brain/bot)
	var/datum/bot_goal/operate/G = bot.current_goal
	return G?.table && !QDELETED(G.table) && G.target && !QDELETED(G.target)

/// What doesn't come out of a doctor's bag to make room for the tools: the tools, and what it treats people with.
/datum/bot_brain/proc/keeps_for_surgery(obj/item/I)
	if(keeps_in_bag(I) || is_type_in_list(I, GLOB.bot_surgery_tools)) //goals/traitor.dm
		return TRUE
	return istype(I, /obj/item/storage/firstaid) || istype(I, /obj/item/stack/medical) || istype(I, /obj/item/reagent_containers/pill) \
		|| istype(I, /obj/item/reagent_containers/hypospray) || istype(I, /obj/item/reagent_containers/medspray) || istype(I, /obj/item/reagent_containers/syringe)

/// A surgery tool out of the hand: a pocket, the bag, and with the bag full the smallest thing in it that isn't a doctor's comes out for
/// it, left on the table the tool came off if there's one in reach. By the end of a shift nearly every bag is full, and a tool left in
/// the hand was what got set down to pick the next one up: scalpel down for the retractor, retractor down for the scalpel, twice each,
/// and "no scalpel to be had". Every operation tried in six shifts ended there.
/datum/bot_brain/proc/bag_surgery_tool(obj/item/I)
	if(!(I in owner.held_items) || put_away(I, allow_equip = FALSE))
		return TRUE
	for(var/slot in list(ITEM_SLOT_LPOCKET, ITEM_SLOT_RPOCKET))
		if(!owner.get_item_by_slot(slot) && owner.equip_to_slot_if_possible(I, slot, FALSE, TRUE))
			return TRUE
	var/obj/item/storage/bag = worn_bag() //goals/clear_bag.dm
	if(!bag)
		return FALSE
	var/atom/onto = owner.drop_location()
	for(var/obj/structure/table/tray in range(1, owner))
		if(!istype(tray, /obj/structure/table/optable))
			onto = get_turf(tray)
			break
	for(var/size in WEIGHT_CLASS_TINY to WEIGHT_CLASS_GIGANTIC)
		for(var/obj/item/junk in bag)
			if(junk.w_class != size || keeps_for_surgery(junk))
				continue
			human_pause(bag)
			if(QDELETED(I) || !(I in owner.held_items))
				return FALSE
			if(QDELETED(junk) || junk.loc != bag || !SEND_SIGNAL(bag, COMSIG_TRY_STORAGE_TAKE, junk, onto))
				continue
			bot_log(src, "taking [junk] out of the bag to make room for [I]")
			if(put_away(I, allow_equip = FALSE))
				return TRUE
	return FALSE

/// Every tool on it before it sets off, in the bag: a doctor doesn't find out halfway through that there's no cautery.
/datum/bot_step/surgery_tools
	var/list/fetches

/datum/bot_step/surgery_tools/execute(datum/bot_brain/bot)
	for(var/tool_type in GLOB.bot_surgery_tools)
		var/obj/item/I = bot.find_carried_tool(tool_type)
		if(I)
			if(I in bot.owner.held_items)
				bot.bag_surgery_tool(I)
			continue
		if(LAZYACCESS(fetches, tool_type) >= BOT_SURGERY_FETCHES)
			bot_log(bot, "no [tool_type] to be had")
			return GOAL_STEP_FAIL
		LAZYSET(fetches, tool_type, LAZYACCESS(fetches, tool_type) + 1)
		var/datum/bot_goal/acquire_item_type/G = new()
		G.item_type = tool_type
		G.lawful = TRUE
		if(bot.suspend_goal_for(G))
			return GOAL_STEP_PENDING
		return GOAL_STEP_FAIL
	return GOAL_STEP_SUCCESS

/datum/bot_step/onto_table/execute(datum/bot_brain/bot)
	var/datum/bot_goal/operate/G = bot.current_goal
	var/mob/living/carbon/human/patient = G?.target
	if(!istype(patient) || QDELETED(G.table) || !bot.owner.Adjacent(G.table) || bot.owner.pulling != patient)
		return GOAL_STEP_FAIL
	bot.human_pause(G.table)
	if(QDELETED(G.table) || QDELETED(patient) || bot.owner.pulling != patient)
		return GOAL_STEP_FAIL
	G.table.tableplace(bot.owner, patient)
	bot.owner.stop_pulling()
	return patient.loc == G.table.loc ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// What it's got on it for this step: the likeliest tool that does the job.
/datum/bot_brain/proc/tool_for_surgery_step(datum/surgery_step/step)
	var/obj/item/best
	var/best_chance = 0
	for(var/obj/item/I in owner.GetAllContents())
		for(var/key in step.implements)
			if((ispath(key) && istype(I, key)) || I.tool_behaviour == key)
				if(step.implements[key] > best_chance)
					best = I
					best_chance = step.implements[key]
	return best

/// Tending wounds, for whichever's worse. Each step, with the right thing in hand, until the procedure says it's finished.
/datum/bot_step/paced/operate
	max_clicks = 80
	var/datum/surgery/procedure

/datum/bot_step/paced/operate/start(datum/bot_brain/bot)
	var/mob/living/carbon/human/patient = bot.current_goal?.target
	if(!istype(patient) || QDELETED(patient))
		return FALSE
	var/path = patient.getFireLoss() > patient.getBruteLoss() ? /datum/surgery/healing/burn/basic : /datum/surgery/healing/brute/basic
	procedure = new path(patient, BODY_ZONE_CHEST, patient.get_bodypart(BODY_ZONE_CHEST))
	procedure.ignore_clothes = TRUE
	bot.telemetry_action = "operating on [patient]"
	log_combat(bot.owner, patient, "operated on", null, "(OPERATION TYPE: [procedure.name]) (TARGET AREA: [procedure.location])")
	return TRUE

/datum/bot_step/paced/operate/do_click(datum/bot_brain/bot)
	var/mob/living/carbon/human/patient = bot.current_goal?.target
	if(QDELETED(procedure) || QDELETED(patient) || patient.stat == DEAD || !bot.owner.Adjacent(patient) || !isturf(patient.loc))
		return FALSE
	var/datum/surgery_step/step = procedure.get_surgery_step()
	// Tending is a step that goes on for as long as it's asked to. Picking up the cautery instead is how it's left.
	if(istype(step, /datum/surgery_step/heal) && max(patient.getBruteLoss(), patient.getFireLoss()) < BOT_SURGERY_DONE)
		step = procedure.get_surgery_next_step()
	var/obj/item/tool = bot.tool_for_surgery_step(step)
	if(!tool || !bot.ready_in_hand(tool))
		bot_log(bot, "nothing to [step.name] with")
		return FALSE
	bot.owner.a_intent = INTENT_HELP
	bot.owner.zone_selected = BODY_ZONE_CHEST
	bot_log_verbose(bot, "[step.name] with [tool]")
	bot.use_item_on(tool, patient)
	wait_for = 3
	return TRUE

/datum/bot_step/paced/operate/finish(datum/bot_brain/bot)
	bot.telemetry_action = null
	var/mob/living/carbon/human/patient = bot.current_goal?.target
	if(!QDELETED(procedure)) //walked away from: a job half done doesn't stay on them
		bot_log(bot, "had to stop operating on [patient]")
		QDEL_NULL(procedure)
		return GOAL_STEP_FAIL
	bot_log(bot, "finished operating on [patient]")
	return GOAL_STEP_SUCCESS

#undef BOT_SURGERY_HURT
#undef BOT_SURGERY_DONE
#undef BOT_SURGERY_RANGE
#undef BOT_SURGERY_FETCHES
