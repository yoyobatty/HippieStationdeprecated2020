// Bot Gym: the tactics library and threat reading (foundation/tactics.dm, foundation/threat_read.dm). The user's case, 2026-11-13: "a fuel
// tank, dragging it, pushing it into a player, backing off and shooting it, dealing an easy stunning blow". SCENARIO_BACKLOG.md lists these.
//
// Layout letters used here: U a fuel tank, k somebody (a stand-in), V the mark.

/datum/bot_scenario/tactics
	time_limit = 20 SECONDS
	blast_margin = 6 //a fuel tank's blast reaches five tiles
	var/bot_skill = 0.7
	var/obj/structure/reagent_dispensers/fueltank/tank
	var/mob/living/carbon/human/foe

/datum/bot_scenario/tactics/setup()
	var/turf/T = first_marker("U")
	if(T)
		tank = new(T)
		place("U", tank)

/datum/bot_scenario/tactics/post_spawn()
	brain.skill = bot_skill

/datum/bot_scenario/tactics/make_goal()
	return null //the fight is the job

/datum/bot_scenario/tactics/proc/tank_went_off()
	return QDELETED(tank)

// ---------------------------------------------------------------------------------------------
// The fuel tank in a fight (tier 2)
// ---------------------------------------------------------------------------------------------

/// In a fight with somebody with a claymore, who's stood beside a fuel tank six tiles off, the bot holding a laser.
/datum/bot_scenario/tactics/fight
	job = "Assistant"
	kit_hands = list(/obj/item/gun/energy/laser)
	layout = list(
		"##############",
		"#B.....Uk....#",
		"#............#",
		"##############")

/datum/bot_scenario/tactics/fight/post_spawn()
	..()
	foe = stand_in(first_marker("k"), "Kit Killer")
	var/obj/item/claymore/C = new(foe)
	foe.put_in_hands(C)
	brain.on_attacked(foe, "attacked", C)

/datum/bot_scenario/tactics/fight/shoots
	name = "tactics: a robust crewman in a fight shoots the fuel tank the killer is stood beside"
	desc = "Mid skill, a laser in hand, in a fight with somebody swinging a claymore who's stood beside a fuel tank, itself six tiles off. It shoots the tank, not them: a blast on the tiles beside it, and it's clear of it."

/datum/bot_scenario/tactics/fight/shoots/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!tank_went_off())
		return BOT_GYM_PENDING
	if(bot.health < bot.maxHealth * 0.8)
		fail_reason = "set off the tank and got caught in it ([bot.health] health)"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/tactics/fight/low_skill
	name = "tactics: a low-skill crewman in the same fight doesn't think of the tank"
	desc = "The same fight for an ordinary player: it shoots at the killer, as it always did, and never thinks of the tank."
	bot_skill = 0.3
	time_limit = 12 SECONDS

/datum/bot_scenario/tactics/fight/low_skill/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(tank_went_off())
		fail_reason = "a low-skill bot set the tank off"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/tactics/fight/low_skill/on_timeout()
	return BOT_GYM_PASS

/datum/bot_scenario/tactics/fight/bystander
	name = "tactics: a robust crewman doesn't set off a tank with somebody else beside it"
	desc = "The same fight, with an innocent stood by the tank too: no tank shot."
	time_limit = 12 SECONDS
	layout = list(
		"##############",
		"#B.....Uk....#",
		"#......c.....#",
		"##############")

/datum/bot_scenario/tactics/fight/bystander/post_spawn()
	..()
	stand_in(first_marker("c"), "Ivy Innocent")

/datum/bot_scenario/tactics/fight/bystander/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(tank_went_off())
		fail_reason = "set off a tank with an innocent beside it"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/tactics/fight/bystander/on_timeout()
	return BOT_GYM_PASS

// ---------------------------------------------------------------------------------------------
// The fuel tank set up for a killing (tier 3, apex)
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/tactics/opener
	name = "tactics: an apex killer drags a fuel tank to its mark, backs off and shoots it"
	desc = "The user's case: apex, a laser on it, after somebody with a fuel tank a few tiles from them. It fetches the tank, drags it up to them, steps aside so the tank comes on to the tile beside them, lets go, backs off out of the blast where it can see the tank, and shoots it; then it finishes them."
	bot_skill = 1
	time_limit = 60 SECONDS
	kit_hands = list(/obj/item/gun/energy/laser)
	layout = list(
		"################",
		"#..............#",
		"#.B............#",
		"#..............#",
		"#.......U......#",
		"#..............#",
		"#....V.........#",
		"#..............#",
		"#..............#",
		"################")

/datum/bot_scenario/tactics/opener/post_spawn()
	..()
	foe = stand_in(first_marker("V"), "Mark Target")

/datum/bot_scenario/tactics/opener/make_goal()
	return new /datum/bot_goal/traitor_kill/robust(null, foe)

/datum/bot_scenario/tactics/opener/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	if(!tank_went_off())
		return BOT_GYM_PENDING
	if(!bot_transcript_said("is beside Mark Target - backing off"))
		fail_reason = "the tank went off, but not set up beside the mark"
		return BOT_GYM_FAIL
	if(bot.health < bot.maxHealth * 0.8)
		fail_reason = "got caught in its own blast ([bot.health] health)"
		return BOT_GYM_FAIL
	if(QDELETED(foe) || foe.health >= foe.maxHealth)
		fail_reason = "the blast missed the mark"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

// ---------------------------------------------------------------------------------------------
// Reading the threat
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/tactics/threat_tank
	name = "threat: stood by a fuel tank, a gunman across the room, it gets away from the tank"
	desc = "Apex, unarmed, beside a fuel tank, in a fight with somebody holding a laser behind a window it can't get through. It doesn't stay by the tank for them to shoot: it gets four tiles off it."
	bot_skill = 1
	time_limit = 10 SECONDS
	layout = list(
		"###############",
		"#.........#...#",
		"#.........#...#",
		"#...UB....W.k.#",
		"#.........#...#",
		"#.........#...#",
		"###############")

/datum/bot_scenario/tactics/threat_tank/post_spawn()
	..()
	brain.nerve = 1 //it stands and fights rather than running from a gun (try_run_for_it(), bot_brain.dm), which would get it off the tank anyway
	foe = stand_in(first_marker("k"), "Gus Gunman")
	var/obj/item/gun/energy/laser/L = new(foe)
	foe.put_in_hands(L)
	brain.on_attacked(foe, "shot", L)

/datum/bot_scenario/tactics/threat_tank/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return get_dist(bot, tank) >= 3 ? BOT_GYM_PASS : BOT_GYM_PENDING
