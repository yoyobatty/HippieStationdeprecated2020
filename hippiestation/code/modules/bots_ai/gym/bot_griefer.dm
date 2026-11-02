// A griefer for a Bot Shift (griefer=1): what a player did to a round of bots, on a loop, on the real map. It has no bot
// brain, so to the crew it's a player. Everything it does is the real click. Every few seconds it finds somebody and shoves,
// grabs, punches, strips, axes or cuffs them, or smashes what's beside it, and a new one turns up when the last one is
// arrested or killed. The Chaos line in the report says how long each lasted and what it got up to.

/// How often it does something. About what a person manages between walking about.
#define BOT_GRIEFER_TICK (2 SECONDS)
/// How many of its turns between setting on somebody new.
#define BOT_GRIEFER_ATTENTION 10

GLOBAL_DATUM(bot_griefer, /datum/bot_griefer)

/datum/bot_griefer
	var/mob/living/carbon/human/body
	var/obj/item/twohanded/fireaxe/axe
	var/turns_on_mark = 0
	var/spawned_at = 0
	/// What became of them, and how long they lasted.
	var/arrested = 0
	var/killed = 0
	var/list/lasted = list()
	/// Move -> how many times.
	var/list/did = list()

/datum/bot_griefer/New()
	. = ..()
	addtimer(CALLBACK(src, PROC_REF(take_a_turn)), 3 MINUTES)

/datum/bot_griefer/proc/report()
	var/list/parts = list()
	for(var/move in did)
		parts += "[move] [did[move]]"
	var/average = 0
	for(var/how_long in lasted)
		average += how_long
	average = length(lasted) ? round(average / length(lasted) / 600, 0.1) : 0
	return "griefer: [length(lasted) + 1] of them, [arrested] arrested, [killed] killed, lasting [average] minutes on average; [jointext(parts, ", ")]"

/datum/bot_griefer/proc/new_body()
	var/turf/T = next_to_somebody()
	if(!T)
		return FALSE
	body = new(T)
	var/name = "[pick("Griff", "Terry", "Dana", "Rob")] [pick("Griefer", "Rampage", "Mcfrag", "Tidewell")]"
	body.real_name = name
	body.name = name
	body.equipOutfit(/datum/outfit/job/assistant)
	body.mind_initialize()
	body.mind.assigned_role = "Assistant"
	axe = new(body)
	body.put_in_active_hand(axe)
	spawned_at = world.time
	turns_on_mark = 0
	return TRUE

/// A floor tile beside a random crew member, out of the way of their eyes if it can be.
/datum/bot_griefer/proc/next_to_somebody()
	var/list/crew = list()
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(B.owner.stat == CONSCIOUS && isturf(B.owner.loc) && is_station_level(B.owner.z))
			crew += B.owner
	if(!length(crew))
		return null
	var/mob/living/carbon/human/mark = pick(crew)
	var/list/spots = get_adjacent_open_turfs(mark)
	for(var/turf/open/T in spots)
		if(!is_blocked_turf(T, TRUE))
			return T
	return null

/datum/bot_griefer/proc/take_a_turn()
	if(!SSticker.IsRoundInProgress())
		return
	addtimer(CALLBACK(src, PROC_REF(take_a_turn)), BOT_GRIEFER_TICK)
	if(QDELETED(body) || body.stat != CONSCIOUS || body.handcuffed)
		if(body)
			lasted += world.time - spawned_at
			if(body.handcuffed)
				arrested++
			else
				killed++
		if(new_body())
			body.say(";[pick("get griefed lol", "hi", "where's the armory", "unga bunga")]")
		return
	if(body.incapacitated())
		return
	if(turns_on_mark++ >= BOT_GRIEFER_ATTENTION)
		turns_on_mark = 0
		var/turf/T = next_to_somebody()
		if(T)
			body.forceMove(T)
	var/mob/living/carbon/human/mark
	for(var/mob/living/carbon/human/H in range(1, body))
		if(H != body && H.stat != DEAD)
			mark = H
			break
	if(!mark)
		smash_something()
		return
	do_something_to(mark)

/datum/bot_griefer/proc/do_something_to(mob/living/carbon/human/mark)
	body.face_atom(mark)
	var/move = pick("shove", "shove", "grab", "punch", "punch", "axe", "strip", "throw", "stuff")
	did[move]++
	body.a_intent = INTENT_HELP
	switch(move)
		if("shove")
			body.a_intent = INTENT_DISARM
			body.UnarmedAttack(mark, TRUE)
		if("grab")
			body.a_intent = INTENT_GRAB
			body.UnarmedAttack(mark, TRUE)
			body.UnarmedAttack(mark, TRUE)
		if("punch")
			body.a_intent = INTENT_HARM
			body.UnarmedAttack(mark, TRUE)
		if("axe")
			if(QDELETED(axe) || !(axe in body.held_items))
				return
			body.a_intent = INTENT_HARM
			axe.melee_attack_chain(body, mark)
		if("strip")
			var/obj/item/I = mark.get_item_by_slot(ITEM_SLOT_LPOCKET)
			if(I)
				INVOKE_ASYNC(body, TYPE_PROC_REF(/mob/living, stripPanelUnequip), I, mark, ITEM_SLOT_LPOCKET)
			else if(mark.wear_id)
				INVOKE_ASYNC(body, TYPE_PROC_REF(/mob/living, stripPanelUnequip), mark.wear_id, mark, ITEM_SLOT_ID)
		if("throw")
			var/obj/item/storage/toolbox/box = new(get_turf(body))
			box.throw_at(mark, 3, 2, body)
		if("stuff")
			var/obj/structure/closet/C = locate() in range(1, mark)
			if(C && C.opened && !mark.buckled)
				mark.forceMove(get_turf(C))
				C.close(body)
				C.welded = TRUE
				C.update_icon()

/datum/bot_griefer/proc/smash_something()
	if(QDELETED(axe) || !(axe in body.held_items))
		return
	for(var/obj/structure/O in orange(1, body))
		if(!is_type_in_typecache(O, GLOB.bot_vandal_targets) || bot_holds_back_space(O) || (O.resistance_flags & INDESTRUCTIBLE))
			continue
		did["smash"]++
		body.a_intent = INTENT_HARM
		axe.melee_attack_chain(body, O)
		return

#undef BOT_GRIEFER_TICK
#undef BOT_GRIEFER_ATTENTION
