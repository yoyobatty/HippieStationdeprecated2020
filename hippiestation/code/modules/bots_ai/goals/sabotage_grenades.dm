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
))

/// Lines a bomber shouts with the pin out.
GLOBAL_LIST_INIT(bot_bomber_lines, list("For the Syndicate!", "Death to Nanotrasen!", "Glory to the Syndicate!", "Nobody leaves!", "See you in hell, Nanotrasen!"))

/datum/bot_brain
	/// A saboteur wants an explosive grenade made: the next brew it starts is that (synthesize_medicine resolve_target()).
	var/wants_bomb_grenade = FALSE
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
	if(!wants_bomb_grenade || bot_ready_bomb_grenade())
		wants_bomb_grenade = FALSE
		return null
	var/list/brew = GLOB.bot_sabotage_brews[1]
	return can_brew(brew) ? brew : null

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
