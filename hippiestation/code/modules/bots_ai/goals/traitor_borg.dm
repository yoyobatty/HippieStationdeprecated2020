// A traitor with an emag subverts a cyborg (overnight 2026-11-10: the user's brief, "borgs ... especially if gone hacked or rogue,
// which bots should do"). The way a player does it: catches one on its own, tells it to follow them somewhere quiet, emags the cover
// lock, crowbars the cover open, emags the interface, and from then on it's theirs (goals/silicon.dm serve_master()): it keeps by them,
// stands up for them, and goes for whoever they name.
//
// The cyborg isn't blind to it: one whose cover lock is scrambled says so on the radio about half the time, as players often do.

/datum/bot_brain
	var/next_borg_subvert = 0
	var/borgs_subverted = 0

/// A cyborg alone near a traitor with an emag and nobody else about: worth the try. TRUE if it's going for one.
/datum/bot_brain/proc/try_subvert_cyborg()
	if(world.time < next_borg_subvert || borgs_subverted >= 1 || owner.incapacitated() || gone_loud())
		return FALSE
	next_borg_subvert = world.time + 3 MINUTES
	if(!find_carried_tool(/obj/item/card/emag) || competence < 0.4)
		return FALSE
	var/mob/living/silicon/robot/best
	for(var/datum/bot_silicon/borg/B in GLOB.bot_silicons)
		var/mob/living/silicon/robot/R = B.owner
		if(!istype(R) || R.stat != CONSCIOUS || R.emagged || B.master_ref || R.z != owner.z || R.shell || get_dist(owner, R) > 14)
			continue
		if(!best || get_dist(owner, R) < get_dist(owner, best))
			best = R
	if(!best)
		return FALSE
	for(var/mob/living/carbon/human/H in view(BOT_SIGHT_RANGE, owner))
		if(H != owner && H.stat == CONSCIOUS && !is_blind(H))
			return FALSE //not in front of the crew
	return assign_goal(new /datum/bot_goal/subvert_cyborg(best))

/datum/bot_goal/subvert_cyborg
	doing = "having a word with a cyborg"
	exclusive = TRUE

/datum/bot_goal/subvert_cyborg/New(mob/living/silicon/robot/R)
	. = ..()
	target = R

/datum/bot_goal/subvert_cyborg/resolve_target(datum/bot_brain/bot)
	var/mob/living/silicon/robot/R = target
	if(!istype(R) || QDELETED(R) || R.stat != CONSCIOUS || R.emagged)
		target = null

/datum/bot_goal/subvert_cyborg/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/subvert_cyborg/S = new
	S.steps = list(new /datum/bot_step/borg_crowbar(), new /datum/bot_step/paced/subvert_cyborg())
	return list(S)

/datum/bot_goal/subvert_cyborg/on_success(datum/bot_brain/bot)
	bot.borgs_subverted++
	bot_tally("cyborgs subverted by a traitor")
	var/mob/living/silicon/robot/R = target
	bot_log(bot, "subverted [R]")
	var/datum/antagonist/traitor/T = bot.owner.mind?.has_antag_datum(/datum/antagonist/traitor) || null //0 for anybody else (the gym's bot with an emag isn't a traitor), and 0?.objectives throws
	var/mob/living/carbon/human/mark
	for(var/datum/objective/assassinate/O in T?.objectives)
		var/mob/living/carbon/human/H = O.target?.current
		if(istype(H) && H.stat != DEAD && H.z == R.z)
			mark = H
			break
	if(mark)
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(bot_say), bot.owner, "[R.name], kill [mark.real_name]."), 3 SECONDS)
	else
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(bot_say), bot.owner, "[R.name], you're with me now."), 3 SECONDS)

/datum/bot_strategy/subvert_cyborg/is_feasible(datum/bot_brain/bot)
	return bot.find_carried_tool(/obj/item/card/emag)

/// A crowbar for the cover, fetched if it hasn't one: once.
/datum/bot_step/borg_crowbar
	var/tried = FALSE

/datum/bot_step/borg_crowbar/execute(datum/bot_brain/bot)
	if(bot.find_carried_tool(/obj/item/crowbar))
		return GOAL_STEP_SUCCESS
	if(tried)
		return GOAL_STEP_FAIL
	tried = TRUE
	return bot.suspend_goal_for(new /datum/bot_goal/acquire_tool(/obj/item/crowbar)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL

/// "Follow me", then up close: the cover lock, the cover, the interface.
/datum/bot_step/paced/subvert_cyborg
	max_clicks = 30
	var/asked = FALSE

/datum/bot_step/paced/subvert_cyborg/do_click(datum/bot_brain/bot)
	var/mob/living/silicon/robot/R = bot.current_goal?.target
	var/mob/living/carbon/human/H = bot.owner
	if(!istype(R) || QDELETED(R) || R.stat != CONSCIOUS || H.incapacitated() || R.emagged)
		return FALSE
	if(get_dist(H, R) > 10)
		return FALSE //gone off
	if(!asked)
		asked = TRUE
		bot_say(H, pick("[R.name], follow me.", "Hey, [R.name], follow me. Need you for something.", "[R.name], come with me."))
		wait_for = 2 SECONDS
		return TRUE
	if(!H.Adjacent(R))
		step_towards(H, R)
		wait_for = 4
		return TRUE
	var/obj/item/card/emag/E = bot.find_carried_tool(/obj/item/card/emag)
	if(!E)
		return FALSE
	if(!R.opened && R.locked)
		bot.use_item_on(E, R)
		wait_for = 6
		return TRUE
	if(!R.opened)
		var/obj/item/crowbar/C = bot.find_carried_tool(/obj/item/crowbar)
		if(!C)
			return FALSE
		bot.use_item_on(C, R)
		wait_for = 6
		return TRUE
	bot.use_item_on(E, R)
	wait_for = 2 SECONDS
	return TRUE

/datum/bot_step/paced/subvert_cyborg/finish(datum/bot_brain/bot)
	var/mob/living/silicon/robot/R = bot.current_goal?.target
	var/obj/item/card/emag/E = bot.find_carried_tool(/obj/item/card/emag)
	if(E)
		bot.put_away(E)
	return (istype(R) && R.emagged) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// A cyborg whose cover lock has just been scrambled: half the time it says so, as a player's often does.
/mob/living/silicon/robot/proc/bot_cover_tampered(mob/user)
	var/datum/bot_silicon/borg/B = bot_silicon
	if(!istype(B) || stat != CONSCIOUS || !prob(50))
		return
	B.note("cover lock tampered with by [user]")
	B.say_it(";[user.name] is tampering with my cover in [get_area_name(src, TRUE)]!")
