// The chemist's grenades (goals/sabotage.dm): potassium in one beaker and water in the other, which don't meet until the grenade goes
// off (pyrotechnics.dm's potassium explosion, power a tenth of what reacts: two large beakers make a 1/3/6 blast). Made at the
// dispenser like any brew (goals/chem_lab.dm), into a case with a screwdriver. Then either thrown into a crowd from a few tiles off,
// with the bot away before it goes, or - for the hotheads, and more often at chaos 2 - carried into the middle of them, primed and held.
//
// And the crew's side: anybody who sees it primed gets clear of it and stays clear (bot_note_bomb(), bot_witness.dm, and run_from,
// bot_fighting.dm), and anybody who saw it thrown calls it in (bot_witness_sabotage()).

/// Brews nobody makes for Medbay or for themselves, only a saboteur.
GLOBAL_LIST_INIT(bot_sabotage_brews, list(
	list("label" = "explosive", "reagent" = /datum/reagent/potassium, "kind" = "sabotage", "form" = "grenade", "stages" = list(
		list("add", list(/datum/reagent/potassium = 100)),
		list("second beaker", list(/datum/reagent/water = 100)),
	)),
	// Hippie's superboom (N-amino azidotetrazole), worked out in a probe on 2026-11-07: sboom made hot and under pressure with the goop
	// sodium fluoride leaves behind; the tabun_pb catalyst in after it, enough over to eat the dimethylamine that comes with the sboom;
	// the diethyl zinc made cold in a beaker of its own (from 290 K it heats itself past 310 and
	// boils off: the mercury goes into ethanol already at 200 K) and the ammonia in a third; both poured in, and the lot to 311 K
	// exactly, still under the pressure from before. It goes off at 315 K. About 12u (kept under a large beaker's 100u at every stage), isolated into one pill (isolated, it's unstabilised: it can go off by itself a few minutes on). Every
	// amount a whole number of the recipe it's for: a reaction only runs in whole batches, and half a batch made nothing. Only where there's a pressure chamber (Hippie Station).
	list("label" = "multivitamin", "reagent" = /datum/reagent/superboom, "kind" = "sabotage", "form" = "pill", "stages" = list(
		list("beaker", 1),
		list("add", list(/datum/reagent/consumable/ethanol = 4, /datum/reagent/fluorine = 2)),
		list("add", list(/datum/reagent/sodium = 4)),
		list("heat", 480),
		list("add", list(/datum/reagent/water = 12, /datum/reagent/carbon = 6, /datum/reagent/aluminium = 1)),
		list("add", list(/datum/reagent/nitrogen = 12, /datum/reagent/carbon = 6)),
		list("heat", 600),
		list("press", 55),
		list("cool", 300),
		list("add", list(/datum/reagent/chlorine = 33, /datum/reagent/phosphorus = 11, /datum/reagent/oxygen = 11)),
		list("beaker", 2),
		list("add", list(/datum/reagent/consumable/ethanol = 6)),
		list("cool", 200),
		list("add", list(/datum/reagent/mercury = 3)),
		list("beaker", 3),
		list("add", list(/datum/reagent/hydrogen = 9, /datum/reagent/nitrogen = 3)),
		list("pour", 2, 1),
		list("pour", 3, 1),
		list("heat", 311, "exact"), //still at the 55 kPa it was pressed to for the sboom: 35 will do. Pressing it back down to 40 never settled
	)),
))

/proc/bot_sabotage_brew(reagent_type)
	for(var/list/brew in GLOB.bot_sabotage_brews)
		if(brew["reagent"] == reagent_type)
			return brew
	return null

/// Lines a bomber shouts with the pin out.
GLOBAL_LIST_INIT(bot_bomber_lines, list("For the Syndicate!", "Death to Nanotrasen!", "Glory to the Syndicate!", "Nobody leaves!", "See you in hell, Nanotrasen!"))

/datum/bot_brain
	/// A saboteur wants an explosive grenade made: the next brew it starts is that (synthesize_medicine resolve_target()).
	var/wants_bomb_grenade = FALSE
	/// ...or a superboom pill.
	var/wants_superboom = FALSE
	/// Bot Gym: a bomber, not a thrower, whatever its temper.
	var/gym_suicide_bomber = FALSE

/// Water and potassium in it: one of these. Not a knockout smoke grenade, which has potassium too, with the sugar and phosphorus.
/proc/bot_grenade_explosive(obj/item/grenade/chem_grenade/G)
	var/water = FALSE
	var/potassium = FALSE
	for(var/obj/item/reagent_containers/B in G?.beakers)
		if(B.reagents?.has_reagent(/datum/reagent/phosphorus))
			return FALSE
		water = water || B.reagents?.has_reagent(/datum/reagent/water)
		potassium = potassium || B.reagents?.has_reagent(/datum/reagent/potassium)
	return water && potassium

/datum/bot_brain/proc/bot_ready_bomb_grenade()
	for(var/obj/item/grenade/chem_grenade/G in owner.GetAllContents(/obj/item/grenade/chem_grenade))
		if(G.stage == GRENADE_READY && !G.active && bot_grenade_explosive(G))
			return G
	return null

/// From synthesize_medicine's resolve_target(): the explosive brew, while a saboteur wants one and hasn't got one.
/datum/bot_brain/proc/brew_for_sabotage()
	if(wants_superboom)
		var/list/boom = bot_sabotage_brew(/datum/reagent/superboom)
		if(!superboom_pill() && can_brew(boom))
			return boom
		wants_superboom = FALSE
	if(!wants_bomb_grenade || bot_ready_bomb_grenade())
		wants_bomb_grenade = FALSE
		return null
	var/list/brew = GLOB.bot_sabotage_brews[1]
	return can_brew(brew) ? brew : null

/// A pill with enough superboom in it to matter, on it.
/datum/bot_brain/proc/superboom_pill()
	for(var/obj/item/reagent_containers/pill/P in owner.GetAllContents(/obj/item/reagent_containers/pill))
		if(P.reagents?.get_reagent_amount(/datum/reagent/superboom) >= 5)
			return P
	return null

/datum/bot_sabotage/grenade
	id = "grenade"
	name = "a grenade in a crowd"

/datum/bot_sabotage/grenade/weight(datum/bot_brain/bot)
	// The job it was hired for, as well as what it's doing now: a chemist covering somewhere short-handed still knows its chemistry.
	var/static/list/chemists = list("Chemist", "Chief Medical Officer")
	if(!(bot.work_role() in chemists) && !(bot.owner.mind?.assigned_role in chemists) && !bot.job_is_chemist_for_gym)
		return 0
	if(!bot.bot_ready_bomb_grenade() && !bot.can_brew(GLOB.bot_sabotage_brews[1]))
		return 0
	return 8 //its own trade first: a chemist that went for a plasma canister instead never came back to it

/datum/bot_sabotage/grenade/start(datum/bot_brain/bot)
	if(!bot.bot_ready_bomb_grenade())
		bot.wants_bomb_grenade = TRUE
		return bot.assign_goal(new /datum/bot_goal/synthesize_medicine()) //it comes back once it's made (try_sabotage())
	var/turf/spot = bot.sabotage_crowd_spot()
	if(!spot)
		return FALSE
	var/suicide = bot.gym_suicide_bomber || world.params["bot-sabotage-suicide"] || bot.temper >= 0.75 || (GLOB.bot_chaos_level >= 2 && prob(35))
	return bot.assign_goal(new /datum/bot_goal/sabotage_grenade(spot, suicide, src))

/datum/bot_goal/sabotage_grenade
	doing = "heading over"
	breaks_in = TRUE //the emag through any door (bot_doors.dm emag_for_doors())
	var/turf/spot
	var/suicide = FALSE
	var/datum/bot_sabotage/act
	/// The grenade, once it's thrown: what it gets away from.
	var/obj/item/grenade/thrown

/datum/bot_goal/sabotage_grenade/New(turf/T, is_suicide, datum/bot_sabotage/A)
	. = ..()
	spot = T
	suicide = is_suicide
	act = A

/datum/bot_goal/sabotage_grenade/resolve_target(datum/bot_brain/bot)
	if(!spot || !bot.bot_ready_bomb_grenade())
		return
	if(suicide)
		target = spot
		return
	// A few tiles short of them, where it can see them: as far as a grenade goes, and further than it blows.
	var/turf/best
	var/best_score
	for(var/turf/open/T in view(6, spot))
		var/d = get_dist(T, spot)
		if(d < 4 || is_blocked_turf(T, TRUE) || isspaceturf(T))
			continue
		var/score = get_dist(T, bot.owner)
		if(!best || score < best_score)
			best = T
			best_score = score
	target = best

/datum/bot_goal/sabotage_grenade/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/sabotage/S = new
	S.steps = list(new /datum/bot_step/move_to(), suicide ? new /datum/bot_step/paced/sabotage_hold_grenade(src) : new /datum/bot_step/paced/sabotage_throw_grenade(src))
	return list(S)

/datum/bot_goal/sabotage_grenade/on_success(datum/bot_brain/bot)
	bot.sabotage_finished(act, get_area_name(spot, TRUE))
	if(!suicide && !QDELETED(bot.owner) && bot.owner.stat != DEAD)
		bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, run_from), thrown || spot, "a grenade going off"))

/// The pin out and over it goes, at where they are.
/datum/bot_step/paced/sabotage_throw_grenade
	max_clicks = 6
	var/datum/bot_goal/sabotage_grenade/goal
	var/thrown = FALSE

/datum/bot_step/paced/sabotage_throw_grenade/New(datum/bot_goal/sabotage_grenade/G)
	. = ..()
	goal = G

/datum/bot_step/paced/sabotage_throw_grenade/do_click(datum/bot_brain/bot)
	if(thrown)
		return FALSE
	var/obj/item/grenade/chem_grenade/G = bot.bot_ready_bomb_grenade()
	if(!G || !bot.ready_in_hand(G))
		return FALSE
	bot.owner.face_atom(goal.spot)
	bot.human_pause(G)
	G.attack_self(bot.owner)
	if(!G.active)
		return TRUE //another go at the pin
	bot_log(bot, "SABOTAGE: throwing [G] at [goal.spot] ([get_area_name(goal.spot, TRUE)])")
	bot.owner.throw_item(goal.spot)
	thrown = TRUE
	goal.thrown = G
	bot_witness_sabotage(bot.owner, "threw a grenade")
	return FALSE

/datum/bot_step/paced/sabotage_throw_grenade/finish(datum/bot_brain/bot)
	return thrown ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// In among them: a shout, the pin out, and it holds on to it.
/datum/bot_step/paced/sabotage_hold_grenade
	max_clicks = 30
	var/datum/bot_goal/sabotage_grenade/goal
	var/obj/item/grenade/chem_grenade/bomb

/datum/bot_step/paced/sabotage_hold_grenade/New(datum/bot_goal/sabotage_grenade/G)
	. = ..()
	goal = G

/datum/bot_step/paced/sabotage_hold_grenade/do_click(datum/bot_brain/bot)
	if(bomb)
		if(QDELETED(bomb) || !bomb.active)
			return FALSE //it's gone off
		wait_for = 5
		return TRUE
	var/obj/item/grenade/chem_grenade/G = bot.bot_ready_bomb_grenade()
	if(!G || !bot.ready_in_hand(G))
		return FALSE
	bot.human_pause(G)
	bot_say(bot.owner, pick(GLOB.bot_bomber_lines), TRUE)
	G.attack_self(bot.owner)
	if(!G.active)
		return TRUE
	bomb = G
	bot_log(bot, "SABOTAGE: holding [G], primed, in [get_area_name(bot.owner, TRUE)]")
	log_game("BOT SABOTAGE: [key_name(bot.owner)] primed [G] in hand at [AREACOORD(bot.owner)]")
	wait_for = 5
	return TRUE

/datum/bot_step/paced/sabotage_hold_grenade/finish(datum/bot_brain/bot)
	return bomb ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// The crew's side, getting clear of a live grenade, is the game's own bomber log: bot_note_bomb() (bot_witness.dm) has everybody who
// sees one primed run from it, and run_from (bot_fighting.dm) keeps them clear of it until it's gone off.

/datum/bot_brain
	var/world_time_next_grenade_shout = 0

// ---------------------------------------------------------------------------------------------
// The superboom bomber: Hippie's own, in among them, running, and the pill down
// ---------------------------------------------------------------------------------------------
//
// Superboom in somebody who's running goes off in their first few seconds of it (superboom on_mob_life(): run intent, the first five
// cycles), as big as there is of it in them. So the bomber walks into the crowd, breaks into a run and swallows the pill there.

/datum/bot_sabotage/superboom
	id = "superboom"
	name = "a superboom bomber"

/datum/bot_sabotage/superboom/weight(datum/bot_brain/bot)
	if(bot.superboom_pill())
		return 10
	var/static/list/chemists = list("Chemist", "Chief Medical Officer")
	if(!(bot.work_role() in chemists) && !(bot.owner.mind?.assigned_role in chemists) && !bot.job_is_chemist_for_gym)
		return 0
	return bot.can_brew(bot_sabotage_brew(/datum/reagent/superboom)) ? 6 : 0

/datum/bot_sabotage/superboom/start(datum/bot_brain/bot)
	var/obj/item/reagent_containers/pill/P = bot.superboom_pill()
	if(!P)
		bot.wants_superboom = TRUE
		return bot.assign_goal(new /datum/bot_goal/synthesize_medicine()) //it comes back once it's made (try_sabotage())
	var/turf/spot = bot.sabotage_crowd_spot()
	return spot ? bot.assign_goal(new /datum/bot_goal/sabotage_superboom(spot, src)) : FALSE

/datum/bot_goal/sabotage_superboom
	doing = "heading over"
	breaks_in = TRUE
	var/datum/bot_sabotage/act

/datum/bot_goal/sabotage_superboom/New(turf/T, datum/bot_sabotage/A)
	. = ..()
	target = T
	act = A

/datum/bot_goal/sabotage_superboom/resolve_target(datum/bot_brain/bot)
	if(!bot.superboom_pill())
		target = null

/datum/bot_goal/sabotage_superboom/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/sabotage/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/sabotage_swallow_superboom())
	return list(S)

/datum/bot_goal/sabotage_superboom/on_success(datum/bot_brain/bot)
	bot.sabotage_finished(act, get_area_name(target, TRUE))

/datum/bot_step/paced/sabotage_swallow_superboom
	max_clicks = 12
	var/swallowed = FALSE

/datum/bot_step/paced/sabotage_swallow_superboom/do_click(datum/bot_brain/bot)
	if(swallowed)
		if(QDELETED(bot.owner) || bot.owner.stat == DEAD)
			return FALSE
		wait_for = 5 //a moment for it to take
		return TRUE
	var/obj/item/reagent_containers/pill/P = bot.superboom_pill()
	if(!P || !bot.ready_in_hand(P))
		return FALSE
	if(bot.owner.m_intent != MOVE_INTENT_RUN)
		bot.owner.toggle_move_intent()
	bot_say(bot.owner, pick(GLOB.bot_bomber_lines), TRUE)
	bot_log(bot, "SABOTAGE: swallowing [P] ([round(P.reagents.get_reagent_amount(/datum/reagent/superboom))]u of superboom), running, in [get_area_name(bot.owner, TRUE)]")
	log_game("BOT SABOTAGE: [key_name(bot.owner)] swallowed a superboom pill at [AREACOORD(bot.owner)]")
	P.attack(bot.owner, bot.owner)
	swallowed = TRUE
	wait_for = 5
	return TRUE

/datum/bot_step/paced/sabotage_swallow_superboom/finish(datum/bot_brain/bot)
	return swallowed ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
