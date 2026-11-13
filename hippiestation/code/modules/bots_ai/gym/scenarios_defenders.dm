// Bot Gym: defenders (apex/defenders.dm, apex/survivors.dm), the user's ruling 2026-11-13: stopping an apex traitor, and surviving one.
//
// Layout letters used here: M somebody carrying something (a stand-in), k a plasma canister.

// ---------------------------------------------------------------------------------------------
// A tank bomb where it has no business
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/defence_bomb
	job = "Assistant"
	time_limit = 20 SECONDS
	layout = list(
		"#########################",
		"#.........B..M..........#",
		"#.......................#",
		"#########################")
	var/crowd = TRUE
	var/mob/living/carbon/human/bomber

/datum/bot_scenario/defence_bomb/setup()
	if("crowd_room" in arena_area.vars)
		arena_area.vars["crowd_room"] = crowd

/datum/bot_scenario/defence_bomb/make_goal()
	return null

/datum/bot_scenario/defence_bomb/post_spawn()
	brain.gym_scripted = FALSE //a scripted bot has no reflexes
	bomber = stand_in(first_marker("M"), "Bo Bomber")
	var/obj/item/transfer_valve/V = bot_gym_tank_bomb(get_turf(bomber)) //a timer on it, not running: a saboteur's maxcap on its way
	bomber.put_in_hands(V)

/datum/bot_scenario/defence_bomb/release_run()
	bot_clear_wanted(bomber)
	return ..()

/datum/bot_scenario/defence_bomb/crew
	name = "defence: somebody walks into the Bar carrying a tank bomb on a timer, and the crew calls it out and gets away"
	desc = "The kill planner's maxcap on its way to where people are (apex/kill_planner.dm): an assistant in the Bar, three tiles from somebody holding a tank bomb with a timer on it. It says so on the radio and gets well away. Before, only a bomb on a dead man's switch, or held by somebody already wanted, was anything to worry about."

/datum/bot_scenario/defence_bomb/crew/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (get_dist(bot, bomber) >= 8 && bot_transcript_said("has a bomb in their hands")) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/defence_bomb/lab
	name = "defence: a scientist's tank bomb in the lab is nobody's business"
	desc = "The same bomb in a room that isn't one people gather in (the toxins lab, the way to the range): the assistant leaves it be."
	crowd = FALSE
	time_limit = 10 SECONDS

/datum/bot_scenario/defence_bomb/lab/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("has a bomb in their hands"))
		fail_reason = "made a fuss of a bomb in the lab"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/defence_bomb/lab/on_timeout()
	return BOT_GYM_PASS

/datum/bot_scenario/defence_bomb/officer
	name = "defence: an officer sees somebody carrying a tank bomb into the Bar, puts it on the record and goes for them"
	desc = "An officer in the Bar, somebody nobody's after walking about with a tank bomb on a timer. It's Possession of explosives: on the record, and the officer goes to arrest them (from range, as for any bomber)."
	job = "Security Officer"
	kit_backpack = list(/obj/item/restraints/handcuffs)

/datum/bot_scenario/defence_bomb/officer/post_spawn()
	..()
	brain.register_security()

/datum/bot_scenario/defence_bomb/officer/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (bot_get_wanted_entry(bomber) && brain.state == BOT_STATE_ARREST) ? BOT_GYM_PASS : BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// Plasma dragged into where people are
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/defence_drag
	job = "Assistant"
	time_limit = 20 SECONDS
	layout = list(
		"#########################",
		"#.........B..Mk.........#",
		"#.......................#",
		"#########################")
	var/mob/living/carbon/human/dragger
	var/obj/machinery/portable_atmospherics/canister/toxins/canister

/datum/bot_scenario/defence_drag/setup()
	if("crowd_room" in arena_area.vars)
		arena_area.vars["crowd_room"] = TRUE
	canister = new(first_marker("k"))
	place("k", canister)

/datum/bot_scenario/defence_drag/make_goal()
	return null

/datum/bot_scenario/defence_drag/post_spawn()
	brain.gym_scripted = FALSE
	dragger = stand_in(first_marker("M"), "Dee Dragger")
	dragger.start_pulling(canister)

/datum/bot_scenario/defence_drag/release_run()
	bot_clear_wanted(dragger)
	if(!QDELETED(canister))
		qdel(canister)
	return ..()

/datum/bot_scenario/defence_drag/crew
	name = "defence: a crewman sees somebody dragging a plasma canister into the Bar and calls it in"
	desc = "The kill planner's plasma fire on its way (apex/kill_planner.dm): somebody hauling a full plasma canister into where people are. The assistant calls it in to Security before it's opened. Before, nobody thought anything of it till the valve was open."

/datum/bot_scenario/defence_drag/crew/post_spawn()
	..()
	brain.skill_override = 1 //it notices: chance-based below apex in a shift (notices_threat())

/datum/bot_scenario/defence_drag/crew/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return bot_transcript_said("called in Dee Dragger") ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/defence_drag/officer
	name = "defence: an officer sees somebody dragging a plasma canister into the Bar and goes to stop them"
	desc = "The same with an officer watching: on the record as Attempted sabotage, and it goes to arrest them before the valve's open."
	job = "Security Officer"
	kit_backpack = list(/obj/item/restraints/handcuffs)

/datum/bot_scenario/defence_drag/officer/post_spawn()
	..()
	brain.register_security()
	brain.skill_override = 1

/datum/bot_scenario/defence_drag/officer/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (bot_get_wanted_entry(dragger) && brain.state == BOT_STATE_ARREST) ? BOT_GYM_PASS : BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// The armory for a killer
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/duty/armory_opens/ordered/killer
	name = "security: three of the crew dead and the killer loose, an apex Head of Security orders the armory open"
	desc = "No nanosuit this time: somebody in a jumpsuit with three of the crew's bodies to their name. The armory's for them as much as for a suit, and an apex Head of Security doesn't give red alert a minute first. Before, only a suit got the armory opened."
	time_limit = 40 SECONDS

/datum/bot_scenario/duty/armory_opens/ordered/killer/post_spawn()
	..()
	qdel(suspect.wear_suit)
	if("skill_override" in hos.bot_brain.vars)
		hos.bot_brain.vars["skill_override"] = 1
	for(var/i in 1 to 3)
		var/mob/living/carbon/human/body = new(get_turf(suspect))
		body.real_name = "Dead Crewman [i]"
		body.mind_initialize()
		body.mind.assigned_role = "Assistant"
		body.last_assailant = suspect.real_name
		body.death()

// ---------------------------------------------------------------------------------------------
// Surviving it (apex/survivors.dm)
// ---------------------------------------------------------------------------------------------

/// Bodies of the crew in the arena, with `killer`'s name on them: what makes it a shift gone bad here (massacre_killer(), goals/massacre.dm)
/datum/bot_scenario/proc/gym_bodies_by(mob/living/carbon/human/killer, count = 3)
	for(var/i in 1 to count)
		var/mob/living/carbon/human/body = new(get_turf(killer))
		body.real_name = "Dead Crewman [i]"
		body.mind_initialize()
		body.mind.assigned_role = "Assistant"
		body.last_assailant = killer.real_name
		body.death()

/datum/bot_scenario/duty/survive
	job = "Assistant"
	time_limit = 25 SECONDS
	layout = list(
		"###############",
		"#B..........L.#",
		"#.............#",
		"#k............#",
		"###############")
	var/duty_name = "/datum/bot_duty/hide_from_killer"
	var/bot_nerve = 0.2
	var/mob/living/carbon/human/killer

/datum/bot_scenario/duty/survive/New()
	..()
	duty_type = text2path(duty_name) //by name: a build without it has none

/datum/bot_scenario/duty/survive/post_spawn()
	brain.nerve = bot_nerve
	killer = stand_in(first_marker("k"), "Kit Killer")
	gym_bodies_by(killer)

/datum/bot_scenario/duty/survive/proc/locker_shut_on_bot()
	var/obj/structure/closet/C = bot.loc
	return istype(C) && !C.opened

/datum/bot_scenario/duty/survive/hide
	name = "survive: alone with a killer in sight, a timid crewman shuts itself in a locker, and comes out once they're cuffed"
	desc = "Three of the crew dead in the room and their killer two tiles off; a timid assistant, nobody else up. It doesn't run about the open floor: it gets into the locker at the far end, out of their way, shuts itself in and keeps still. Once the killer's in cuffs it comes out."
	var/hid_at = 0
	var/came_out = FALSE

/datum/bot_scenario/duty/survive/hide/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!hid_at)
		if(locker_shut_on_bot())
			hid_at = world.time
		return BOT_GYM_PENDING
	if(!killer.handcuffed)
		if(!locker_shut_on_bot())
			fail_reason = "got out again with the killer still loose"
			return BOT_GYM_FAIL
		if(world.time > hid_at + 5 SECONDS)
			killer.handcuffed = new /obj/item/restraints/handcuffs(killer)
			killer.update_handcuffed()
			log_line("the killer's in cuffs")
		return BOT_GYM_PENDING
	return isturf(bot.loc) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/survive/brave
	name = "survive: a brave crewman in the same room doesn't hide"
	desc = "The same with a crewman with plenty of nerve: no locker."
	bot_nerve = 0.8
	time_limit = 12 SECONDS

/datum/bot_scenario/duty/survive/brave/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(locker_shut_on_bot())
		fail_reason = "hid, brave as it is"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/duty/survive/brave/on_timeout()
	return BOT_GYM_PASS

/datum/bot_scenario/duty/survive/vigilante
	name = "survive: a brave, robust crewman with nothing to fight with picks up a toolbox while a killer's about"
	desc = "Three of the crew dead and their killer still about; a crewman with nerve, a robust player, empty-handed. It gets the toolbox from the other end of the room. Armed, it's one of those who go for a killer on sight."
	duty_name = "/datum/bot_duty/vigilante_arm_up"
	bot_nerve = 0.8
	layout = list(
		"###############",
		"#B..........T.#",
		"#.............#",
		"#.......k.....#",
		"###############")

/datum/bot_scenario/duty/survive/vigilante/post_spawn()
	..()
	brain.skill_override = 0.7

/datum/bot_scenario/duty/survive/vigilante/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return brain.find_carried_tool(/obj/item/storage/toolbox) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/book_killer
	name = "defence: three bodies with the same killer's name on them, a robust officer books them for Murder"
	desc = "Three of the crew dead, nobody saw it done, the one who did it about. A robust officer works it out from the bodies and puts it on the record, and the hunt's on. Before, only a killing somebody saw made the records."
	job = "Security Officer"
	time_limit = 10 SECONDS
	layout = list(
		"###############",
		"#B............#",
		"#............k#",
		"###############")
	var/mob/living/carbon/human/killer

/datum/bot_scenario/duty/book_killer/New()
	..()
	duty_type = text2path("/datum/bot_duty/book_the_killer")

/datum/bot_scenario/duty/book_killer/post_spawn()
	brain.register_security()
	brain.skill_override = 0.7
	killer = stand_in(first_marker("k"), "Kit Killer")
	gym_bodies_by(killer)

/datum/bot_scenario/duty/book_killer/release_run()
	bot_clear_wanted(killer)
	return ..()

/datum/bot_scenario/duty/book_killer/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/datum/bot_wanted/W = bot_get_wanted_entry(killer)
	return (W && W.severity >= BOT_CRIME_MURDER) ? BOT_GYM_PASS : BOT_GYM_PENDING
