// Human limits (the plan's foundation/human_limits.dm; the user's ruling 2026-11-12: "human limits, perfect decisions"). An apex bot decides
// perfectly but moves its hands no faster than a quick player: everything it does with them goes through human_pause() (bot_human.dm),
// which these set the pace of. Below apex the pace is exactly what it was.
//
//  - click_interval(): between clicks. A steady player clicks every 0.4-0.7 s; a quick one every 0.3-0.5 s, and nobody faster.
//  - reaction_delay(): turning to something new. 0.1-0.3 s; a quick player 0.1-0.2 s.
//  - perception_delay(): from something happening in sight to acting on it (threat reading, milestone 2): 0.2-0.4 s, a quick player's
//    0.18-0.3 s. Nothing reads what a player's screen wouldn't show.

/datum/bot_brain/proc/click_interval()
	return is_apex() ? rand(3, 5) : rand(4, 7)

/datum/bot_brain/proc/reaction_delay()
	return is_apex() ? rand(1, 2) : rand(1, 3)

/datum/bot_brain/proc/perception_delay()
	return is_apex() ? rand(18, 30) / 10 : rand(20, 40) / 10
