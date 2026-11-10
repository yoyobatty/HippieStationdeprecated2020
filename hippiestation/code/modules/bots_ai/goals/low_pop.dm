// A quiet shift (the user, 2026-11-09: "What I often did during low pop was just spend my time learning, researching, understanding and
// going over hard to achieve cool stuff, like end of science tech tree, going to ruins/Lava land in a mech to get rare items.").
//
// With ten or fewer on the station there's less to do for each other and more time for yourself: the bar and a chat count for less,
// powergaming and exploring for more (bot_pursuits.dm's weights, doubled and halved), and whoever's out exploring goes down to
// Lavaland for the ruins, which on a full station the miners keep to (goals/exploring.dm), in the Ripley if Robotics has one
// (goals/mech_pilot.dm).

/// This many on the station or fewer is a quiet shift.
#define BOT_LOW_POP 10

/// People on the station and playing: alive, not logged off, a player or a bot. Counted once a minute.
/proc/bot_station_population()
	var/static/count = 0
	var/static/counted_at = -1
	if(counted_at >= 0 && world.time < counted_at + 1 MINUTES)
		return count
	counted_at = world.time
	count = 0
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H.stat != DEAD && H.mind?.assigned_role && !H.bot_logged_off && (H.client || H.bot_brain) && is_station_level(H.z))
			count++
	return count

/proc/bot_low_pop()
	return bot_station_population() <= BOT_LOW_POP

/datum/bot_brain/pursuit_weights()
	. = ..()
	if(gym_run || !bot_low_pop())
		return
	var/list/W = .
	W[BOT_PURSUIT_POWER] *= 2
	W[BOT_PURSUIT_EXPLORE] *= 2 //nothing for Security or a head: theirs is 0
	W[BOT_PURSUIT_SOCIAL] *= 0.5

/// Whether this bot goes to Lavaland's ruins though it's no miner: a quiet shift, and not Security's or a head's.
/datum/bot_brain/proc/low_pop_lavaland()
	if(is_security_job() || (work_role() in GLOB.command_positions))
		return FALSE
	if(!gym_run && !bot_low_pop())
		return FALSE
	// Anybody out exploring on a quiet shift: the user's own way of playing one. With the Ripley out of Robotics it's safer still.
	return TRUE

#undef BOT_LOW_POP
