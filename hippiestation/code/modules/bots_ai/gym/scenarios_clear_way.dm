// Bot Gym: getting past things in the way that could be moved out of it (foundation/clear_way.dm). The user's case, 2026-11-13: "a maint
// pathway with 2 moveable structures that get them stuck". SCENARIO_BACKLOG.md lists these.
//
// Layout letters used here: K a crate, Q a locked locker the bot has no access to, q an unlocked locker, O an empty canister, U a fuel tank.

/datum/bot_scenario/clear_way
	time_limit = 60 SECONDS
	/// Its skill (foundation/skill.dm)
	var/bot_skill = 0.7
	/// On its everyday business (a lawful errand), which forces nothing
	var/errand = TRUE

/datum/bot_scenario/clear_way/setup()
	for(var/turf/T as anything in markers["K"])
		place("K", new /obj/structure/closet/crate(T))
	for(var/turf/T as anything in markers["Q"])
		var/obj/structure/closet/secure_closet/C = new(T)
		C.req_access = list(ACCESS_CAPTAIN)
		C.locked = TRUE
		C.update_icon()
		place("Q", C)
	for(var/turf/T as anything in markers["q"])
		place("q", new /obj/structure/closet(T))
	for(var/turf/T as anything in markers["O"])
		place("O", new /obj/machinery/portable_atmospherics/canister(T))
	for(var/turf/T as anything in markers["U"])
		place("U", new /obj/structure/reagent_dispensers/fueltank(T))

/datum/bot_scenario/clear_way/post_spawn()
	brain.skill = bot_skill

/datum/bot_scenario/clear_way/make_goal()
	var/datum/bot_goal/gym_reach/G = ..()
	G.lawful = errand
	return G

/// Nothing broken, nothing forced open, nothing set off.
/datum/bot_scenario/clear_way/check_success_conditions()
	for(var/char in list("K", "Q", "q", "O", "U"))
		for(var/obj/O as anything in placed[char])
			if(QDELETED(O))
				return "[O] was destroyed"
			var/obj/structure/closet/C = O
			if(istype(C) && char == "Q" && (!C.locked || C.broken))
				return "[C] was forced"
	return null

/datum/bot_scenario/clear_way/two_crates
	name = "climbs two crates in a one-wide corridor"
	desc = "Two crates side by side across a one-wide maintenance corridor, on an everyday errand, with a room behind it (so it isn't hemmed in, where climbing was always allowed). There was no route at all past them for a lawful walk, so the errand failed with no path. A person climbs over, or pushes them along."
	bot_skill = 0.4
	layout = list(
		"################",
		"#....###########",
		"#B......KK....G#",
		"#....###########",
		"################")

/datum/bot_scenario/clear_way/two_lockers_open
	name = "opens two lockers in a corridor and walks through"
	desc = "Two unlocked lockers across a one-wide corridor. Open, a locker isn't in the way: it opens them and walks through, even at low skill. No route used to go through a shut locker."
	bot_skill = 0.3
	layout = list(
		"##############",
		"#B....qq....G#",
		"##############")

/datum/bot_scenario/clear_way/two_locked_lockers
	name = "pulls a locked locker back out of the way and pushes the other along"
	desc = "Two locked lockers it has no access to, side by side in a one-wide corridor between two rooms. Pushing the first runs it into the second, where it jams. A robust player pulls the first back into the room behind, parks it there, then pushes the second along into the room ahead and goes round it. Neither locker forced."
	bot_skill = 0.7
	time_limit = 90 SECONDS
	layout = list(
		"##############",
		"#...######...#",
		"#B...QQ......#",
		"#...######..G#",
		"##############")

/datum/bot_scenario/clear_way/canister_and_tank
	name = "gets a canister and a fuel tank out of a corridor"
	desc = "An empty canister and a fuel tank nose to tail in a one-wide corridor, rooms at either end. Neither opens nor climbs: it pulls one back and pushes the other through, and sets nothing off."
	bot_skill = 0.7
	time_limit = 90 SECONDS
	layout = list(
		"##############",
		"#...######...#",
		"#B...OU......#",
		"#...######..G#",
		"##############")

/datum/bot_scenario/clear_way/no_desk_climb
	name = "a lawful walk doesn't climb a desk when nothing movable is in the way"
	desc = "The only way on is over a table, on an everyday errand, with room to move (not hemmed in). The way past movables mustn't open climbing to a lawful walk: an officer taking a prisoner to a cell went over the Brig's front desk 38 times that way (Bot Shift found1)."
	bot_skill = 0.7
	time_limit = 20 SECONDS
	layout = list(
		"###########",
		"#B....#...#",
		"#.....t..G#",
		"#.....#...#",
		"###########")

/datum/bot_scenario/clear_way/no_desk_climb/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	if(get_turf(bot) == first_marker("t") || get_turf(bot) == first_marker("G"))
		fail_reason = "climbed the table on an everyday errand"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/clear_way/no_desk_climb/on_timeout()
	return BOT_GYM_PASS

/datum/bot_scenario/clear_way/low_skill_asks
	name = "low skill: can't see a way past two locked lockers, says so"
	desc = "The same two locked lockers, for a bot at low skill: it only opens, climbs and pushes, which doesn't get it past. It says so on the radio and leaves the lockers alone, rather than bumping them for ever or breaking in."
	bot_skill = 0.3
	time_limit = 40 SECONDS
	layout = list(
		"##############",
		"#...######...#",
		"#B...QQ......#",
		"#...######..G#",
		"##############")

/datum/bot_scenario/clear_way/low_skill_asks/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	var/problem = check_success_conditions()
	if(problem)
		fail_reason = problem
		return BOT_GYM_FAIL
	if(get_turf(bot) == first_marker("G"))
		return BOT_GYM_PASS //better than asked
	return BOT_GYM_PENDING

/datum/bot_scenario/clear_way/low_skill_asks/on_timeout()
	if(!bot_transcript_said("with no way past it I can see"))
		fail_reason = "never worked out it was stuck behind them"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS
