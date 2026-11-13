// Threat reading (the plan's foundation/threat_read.dm, M2): what a bot sees about to hurt it, and what it does about it. Every bot reads
// threats; the skill dial (skill.dm) sets how often it notices, each look at its own reaction time (human_limits.dm): a low-skill bot some
// of the time, a robust one most of the time, apex every time.
//
//  - Stood by a fuel tank in a fight with somebody holding a gun: it gets away from the tank. A shot into one is a blast on the tiles
//    beside it (foundation/tactics.dm), and a bot stood there was a free kill.

/datum/bot_brain
	var/next_tank_look = 0
	/// Getting away from a tank until then: the rest of the fight waits
	var/tank_dodge_until = 0

/// Whether it notices this time (above)
/datum/bot_brain/proc/notices_threat()
	return prob(is_apex() ? 100 : (skill_at_least(BOT_SKILL_MID) ? 70 : 30))

/proc/bot_holds_gun(mob/living/L)
	for(var/obj/item/gun/G in L?.held_items)
		return TRUE
	return FALSE

/// From handle_combat() (bot_brain.dm). TRUE while it's getting away from a tank.
/datum/bot_brain/proc/mind_the_tank(mob/living/foe)
	if(world.time < tank_dodge_until)
		return TRUE
	if(world.time < next_tank_look || !bot_holds_gun(foe))
		return FALSE
	var/obj/structure/reagent_dispensers/fueltank/tank = bot_fuel_tank_near(owner, 2)
	if(!tank)
		return FALSE
	next_tank_look = world.time + perception_delay() + 2 SECONDS
	if(!notices_threat())
		return FALSE
	var/turf/away = furthest_open_floor_from(tank, 4)
	if(!away)
		return FALSE
	bot_log(src, "THREAT: stood by [tank] with [foe] holding a gun - getting away from it")
	bot_tally("got away from a fuel tank")
	tank_dodge_until = world.time + 2 SECONDS
	combat_chase(away)
	return TRUE
