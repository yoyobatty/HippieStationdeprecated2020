// Seeing to yourself, the small things a person does without thinking about it.
//
//  - Shoes. Nobody walks round barefoot if they can help it: broken glass cuts bare feet, and barefoot bots walked straight over
//    it (the route planner keeps a barefoot bot off it now, bot_hazards.dm). A bot that's lost its shoes (cloned, stripped,
//    thrown off in a fire) finds a pair.
//  - A clone's things. Its old body's by the cloner as a rule (goals/cloning.dm) and it fetches them. If it can't get to it, it asks
//    to be let in; if somebody's had them off the body, it asks who; a body in a morgue tray or a bag comes out of it first.

/datum/bot_duty/find_shoes
	name = "finding some shoes"
	tier = BOT_DUTY_URGENT
	priority = 20
	interval_min = 150
	interval_max = 300

/datum/bot_duty/find_shoes/try_start(datum/bot_brain/bot)
	var/mob/living/carbon/human/H = bot.owner
	if(H.shoes || H.handcuffed || H.bot_life_sentence || bot.is_in_active_cell(H) || !H.get_num_legs())
		return FALSE
	var/obj/item/clothing/shoes/S = bot.find_carried_tool(/obj/item/clothing/shoes)
	if(S)
		if(bot.ready_in_hand(S) && H.equip_to_slot_if_possible(S, ITEM_SLOT_FEET, FALSE, TRUE))
			bot_log(bot, "put [S] on")
		return FALSE
	var/datum/bot_goal/acquire_item_type/G = new()
	G.item_type = /obj/item/clothing/shoes
	G.lawful = TRUE
	if(!bot.assign_goal(G))
		return FALSE
	bot_log(bot, "barefoot: off to find some shoes")
	return TRUE

// ---------------------------------------------------------------------------------------------
// A clone's things
// ---------------------------------------------------------------------------------------------

/datum/bot_brain
	/// Whether it's asked about its things already, this body.
	var/asked_after_things = FALSE

/// Its things are gone off its old body: it asks after them, once.
/datum/bot_brain/proc/ask_after_my_things(mob/living/carbon/human/body)
	if(asked_after_things || QDELETED(owner) || owner.stat != CONSCIOUS)
		return
	asked_after_things = TRUE
	var/where = get_area_name(body || owner, TRUE)
	bot_say(owner, ";[pick("Has anyone got my stuff? It's all gone off my body in [where].", "Somebody's had everything off my old body in [where]. Anyone seen my ID?", "Who's taken my things? My body in [where]'s been stripped.")]")
	bot_log(src, "asked after its things")

/// Can't get to its old body: whoever's about with the access is asked to open up, the way a shut-in bot asks (bot_requests.dm).
/datum/bot_brain/proc/ask_to_be_let_in_for_body(mob/living/carbon/human/body)
	var/list/doors = list()
	for(var/obj/machinery/door/airlock/D in range(12, owner))
		if(D.density && !D.allowed(owner))
			doors += D
	if(!length(doors))
		return FALSE
	var/where = get_area_name(body, TRUE)
	return call_for(/datum/bot_request_kind/let_out, pick("Can somebody let me into [where]? My things are on my old body in there.", "I need into [where] to get my stuff back, can anyone open up?", "Anyone near [where]? My ID's on my old body in there."), doors)

/// Out of the morgue tray or the bag it's in, so it can be got at: the tray's pulled out, the bag's unzipped.
/datum/bot_step/body_out
/datum/bot_step/body_out/execute(datum/bot_brain/bot)
	var/mob/living/carbon/human/body = bot.current_goal?.target
	if(!istype(body))
		return GOAL_STEP_FAIL
	if(isturf(body.loc))
		return GOAL_STEP_SUCCESS
	var/atom/movable/holder = body.loc
	if(!bot.owner.Adjacent(holder))
		return GOAL_STEP_FAIL
	bot.human_pause(holder)
	if(istype(holder, /obj/structure/closet))
		var/obj/structure/closet/C = holder
		C.open(bot.owner)
	else
		bot.use_atom(holder)
	return isturf(body.loc) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
