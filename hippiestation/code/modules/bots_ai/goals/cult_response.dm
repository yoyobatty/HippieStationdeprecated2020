// The blood cult, from the crew's side (goals/cult.dm is the cult's). The user's ruling (2026-11-12): the crew notice cultists,
// deconvert them with holy water, and the chaplain matters. Until now a cult went about its business unremarked: nobody minded a rune
// in maintenance or a hooded figure with a dagger, and a cultist Security happened to hold went back out a cultist.
//
//  - Cult kit seen (the robes, the hood, the dagger, the blade): it's contraband as traitor kit is (bot_law.dm), and on the records as
//    Cultism, which Security arrests for and the chaplain answers.
//  - A rune outside the Chapel: called in on the radio ("Sec, blood runes in maint"), Security sent, and the Chaplain goes and breaks
//    it with the null rod ("BEGONE FOUL MAGIKS!!", the rod's own words).
//  - A cultist held, cuffed or in a cell, and on the records for it: the Chaplain fetches a flask of holy water from the Chapel and
//    makes them drink it, a mouthful at a time, until they come back to themselves (holy water does that, given time in the blood).

/// The cult's things, by type: seen on somebody, it's Cultism.
GLOBAL_LIST_INIT(bot_cult_kit, typecacheof(list(/obj/item/melee/cultblade, /obj/item/clothing/suit/cultrobes, /obj/item/clothing/head/culthood,
	/obj/item/clothing/suit/hooded/cultrobes, /obj/item/clothing/head/hooded/cult_hoodie)))

/// Runes somebody's reported, for the Chaplain (weakrefs), and every rune ever reported (REF -> when), so each is called in once
GLOBAL_LIST_EMPTY(bot_runes_to_clean)
GLOBAL_LIST_EMPTY(bot_runes_reported)

/datum/bot_brain
	var/next_rune_look = 0
	var/next_holy_feed = 0
	/// Not before this, after a try at fetching the null rod came to nothing
	var/next_rod_fetch = 0

/// What somebody seen with this is wanted for.
/proc/bot_contraband_crime(obj/item/I)
	return is_type_in_typecache(I, GLOB.bot_cult_kit) ? "Cultism" : "Possession of Dangerous Equipment"

// ---------------------------------------------------------------------------------------------
// Runes
// ---------------------------------------------------------------------------------------------

/// A look round for runes, from keep_an_eye_out() (bot_witness.dm). The first to see one outside the Chapel calls it in.
/datum/bot_brain/proc/notice_runes()
	if(bot_cultist || iscultist(owner) || world.time < next_rune_look || gone_loud())
		return FALSE
	next_rune_look = world.time + 8 SECONDS
	for(var/obj/effect/rune/R in view(5, owner))
		if(GLOB.bot_runes_reported[REF(R)] || istype(get_area(R), /area/chapel))
			continue
		GLOB.bot_runes_reported[REF(R)] = world.time
		GLOB.bot_runes_to_clean += WEAKREF(R)
		var/where = get_area_name(R, TRUE)
		bot_news("somebody's been drawing blood runes in [where]")
		bot_tally("runes reported")
		bot_log(src, "saw a rune in [where]: calling it in")
		bot_say(owner, ";[pick("Sec, there's blood runes in [where].", "Security! Somebody's drawn cult runes in [where].", "Cult runes in [where]. Somebody get the chaplain.")]")
		bot_dispatch_security(get_turf(R), "runes in [where]", owner) //goals/security_tactics.dm
		return TRUE
	return FALSE

/datum/bot_duty/break_runes
	name = "breaking runes"
	jobs = list("Chaplain")
	tier = BOT_DUTY_URGENT
	priority = 6
	interval_min = 100
	interval_max = 200

/datum/bot_duty/break_runes/try_start(datum/bot_brain/bot)
	if(bot.bot_cultist || iscultist(bot.owner) || bot.state != BOT_STATE_WANDER || !length(GLOB.bot_runes_to_clean))
		return FALSE
	var/obj/item/nullrod/rod = bot.find_carried_tool(/obj/item/nullrod)
	var/obj/effect/rune/best
	for(var/datum/weakref/ref as anything in GLOB.bot_runes_to_clean.Copy())
		var/obj/effect/rune/R = ref.resolve()
		if(QDELETED(R))
			GLOB.bot_runes_to_clean -= ref
			continue
		if(R.z != bot.owner.z || (bot.gym_run && get_area(R) != get_area(bot.owner)))
			continue
		if(!best || get_dist(bot.owner, R) < get_dist(bot.owner, best))
			best = R
	if(!best || !bot.can_walk_lawfully_to(best))
		return FALSE
	// The first Chaplain of a shift starts without the rod (job_types/chaplain.dm gives one only to the ones after): it's in the Chapel
	// office, on both maps
	if(!rod)
		// A fetch that came to nothing isn't tried again for a while: in batch cultchap1112c no Chaplain found a way to the office's rod by
		// its own doors, and each tried 60-70 times a shift
		if(world.time < bot.next_rod_fetch)
			return FALSE
		bot.next_rod_fetch = world.time + 5 MINUTES
		for(var/obj/item/nullrod/R as anything in bot_instances_of(/obj/item/nullrod))
			if(!QDELETED(R) && isturf(R.loc) && istype(get_area(R), /area/chapel))
				bot.note_seen(R, R.loc) //its own office: it knows where the rod's kept (it asked the radio where to get one, in batch cultchap1112b)
		var/datum/bot_goal/acquire_item_type/fetch = new
		fetch.item_type = /obj/item/nullrod
		fetch.lawful = TRUE
		fetch.doing = "getting the null rod"
		return bot.assign_goal(fetch)
	if(!bot.assign_goal(new /datum/bot_goal/break_rune(best)))
		return FALSE
	bot.say_after_typing(";[pick("On my way to deal with that rune.", "Chaplain here, I'll take care of the runes.", "Leave the runes to me.")]")
	return TRUE

/datum/bot_goal/break_rune
	lawful = TRUE
	doing = "breaking a rune"
	var/obj/effect/rune/rune

/datum/bot_goal/break_rune/New(obj/effect/rune/R)
	. = ..()
	rune = R

/datum/bot_goal/break_rune/resolve_target(datum/bot_brain/bot)
	target = QDELETED(rune) ? null : rune

/datum/bot_goal/break_rune/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/favour/S = new //bot_favours.dm
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/break_the_rune())
	return list(S)

/datum/bot_step/break_the_rune/execute(datum/bot_brain/bot)
	var/datum/bot_goal/break_rune/G = bot.current_goal
	var/obj/item/nullrod/rod = bot.find_carried_tool(/obj/item/nullrod)
	if(!istype(G) || QDELETED(G.rune) || !rod || !bot.owner.Adjacent(G.rune))
		return GOAL_STEP_FAIL
	if(!bot.ready_in_hand(rod))
		return GOAL_STEP_FAIL
	bot.use_item_on(rod, G.rune) //the rod's attackby: "BEGONE FOUL MAGIKS!!", and it's gone
	if(!QDELETED(G.rune))
		return GOAL_STEP_FAIL
	bot_tally("runes broken")
	bot_log(bot, "broke a rune")
	bot.put_away(rod)
	return GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// Holy water
// ---------------------------------------------------------------------------------------------

/// Somebody held who's on the records for Cultism, or seen with cult kit by this bot, who isn't themselves yet (the change shows: a
/// cultist coming back to the old faith is plain to see).
/datum/bot_brain/proc/held_cultist()
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H.stat == DEAD || H.z != owner.z || !iscultist(H) || (gym_run && get_area(H) != get_area(owner)))
			continue
		if(!H.handcuffed && !is_in_active_cell(H))
			continue
		var/datum/bot_wanted/W = bot_get_wanted_entry(H)
		if(W?.crime == "Cultism" || length(facts_about(H.real_name, list(BOT_FACT_CONTRABAND), TRUE, FALSE)))
			return H
	return null

/datum/bot_duty/deconvert
	name = "bringing somebody back from the cult"
	jobs = list("Chaplain")
	tier = BOT_DUTY_URGENT
	priority = 6
	interval_min = 50
	interval_max = 100

/datum/bot_duty/deconvert/try_start(datum/bot_brain/bot)
	if(bot.bot_cultist || iscultist(bot.owner) || bot.state != BOT_STATE_WANDER)
		return FALSE
	var/mob/living/carbon/human/H = bot.held_cultist()
	if(!H)
		return FALSE
	var/obj/item/reagent_containers/food/drinks/bottle/holywater/flask = bot.find_carried_tool(/obj/item/reagent_containers/food/drinks/bottle/holywater)
	if(!flask || !flask.reagents?.has_reagent(/datum/reagent/water/holywater))
		var/datum/bot_goal/acquire_item_type/fetch = new
		fetch.item_type = /obj/item/reagent_containers/food/drinks/bottle/holywater
		fetch.lawful = TRUE
		fetch.doing = "fetching holy water"
		return bot.assign_goal(fetch)
	if(!bot.assign_goal(new /datum/bot_goal/give_holy_water(H)))
		return FALSE
	bot_tally("holy water given")
	return TRUE

/datum/bot_goal/give_holy_water
	lawful = TRUE
	doing = "giving somebody holy water"
	var/mob/living/carbon/human/cultist

/datum/bot_goal/give_holy_water/New(mob/living/carbon/human/H)
	. = ..()
	cultist = H

/datum/bot_goal/give_holy_water/resolve_target(datum/bot_brain/bot)
	target = QDELETED(cultist) ? null : cultist

/datum/bot_goal/give_holy_water/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/favour/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/holy_water())
	return list(S)

/// A mouthful at a time, a few seconds apart, until it's gone in or they're themselves again.
/datum/bot_step/paced/holy_water
	max_clicks = 20
	var/said = FALSE

/datum/bot_step/paced/holy_water/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/give_holy_water/G = bot.current_goal
	var/mob/living/carbon/human/H = G?.cultist
	var/obj/item/reagent_containers/food/drinks/bottle/holywater/flask = bot.find_carried_tool(/obj/item/reagent_containers/food/drinks/bottle/holywater)
	if(!istype(H) || H.stat == DEAD || !iscultist(H) || !flask || !flask.reagents?.total_volume || !bot.owner.Adjacent(H))
		return FALSE
	if(H.reagents?.get_reagent_amount(/datum/reagent/water/holywater) >= 20)
		wait_for = 50 //enough in them for now
		return TRUE
	if(!said)
		said = TRUE
		bot_say(bot.owner, pick("Drink. You'll thank me later.", "Open up. This is for your own good.", "The light's still in you. Drink."))
	if(!bot.ready_in_hand(flask))
		return FALSE
	bot.use_item_on(flask, H) //drinks/attack(): fed to them, the time it takes
	return TRUE

/datum/bot_step/paced/holy_water/finish(datum/bot_brain/bot)
	var/datum/bot_goal/give_holy_water/G = bot.current_goal
	if(G?.cultist && !iscultist(G.cultist))
		bot_tally("cultists brought back")
		bot.say_after_typing(pick("Welcome back.", "There you are.", "Back with us. Good."))
	return GOAL_STEP_SUCCESS
