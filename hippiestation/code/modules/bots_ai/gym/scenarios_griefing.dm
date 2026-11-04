// Bot Gym scenarios for what a player griefing a round of bots turned up: each one is something that round's telemetry
// showed a bot doing that a person couldn't, or wouldn't.

/datum/bot_scenario/knocked_out_stops_walking
	name = "knocked out: stops walking, carries on when it comes round"
	desc = "Knocked out mid-walk. The walk runs on its own timer, which nothing stopped: an atmos tech walked round a kitchen at -80 health and crowbarred a firelock on the way."
	layout = list(
		"################################",
		"#B............................G#",
		"################################")
	time_limit = 30 SECONDS
	var/turf/fell_at

/datum/bot_scenario/knocked_out_stops_walking/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!fell_at && get_dist(bot, first_marker("B")) >= 2)
		fell_at = get_turf(bot)
		bot.Unconscious(6 SECONDS)
	if(fell_at && bot.IsUnconscious() && get_turf(bot) != fell_at)
		fail_reason = "walked from [COORD(fell_at)] to [COORD(bot)] while unconscious"
		return BOT_GYM_FAIL
	return ..()

/datum/bot_scenario/knocked_out_stops_walking/check_success_conditions()
	if(!fell_at)
		return "got there without being knocked out, so nothing was tested"

/datum/bot_scenario/leaves_the_flames
	name = "in the flames: an atmos tech gets out"
	desc = "Fire breaks out around an atmos tech. Jobs with a tank to hand used to have no reflex for this and worked on through it until they burned to death."
	layout = list(
		"######################",
		"#.......B............#",
		"######################")
	job = "Atmospheric Technician"
	time_limit = 20 SECONDS

/datum/bot_scenario/leaves_the_flames/issue_goal()
	return

/datum/bot_scenario/leaves_the_flames/post_spawn()
	..()
	brain.gym_scripted = FALSE //a scripted bot has no reflexes
	var/turf/start = first_marker("B")
	for(var/turf/open/T in range(1, start))
		T.air.moles[/datum/gas/plasma] = 3 //a small fire: any more in a sealed corridor burns the lot, and there's no out to get to
		T.air.moles[/datum/gas/oxygen] = 20
		T.air_update_turf()
		T.hotspot_expose(1000, 500)

/datum/bot_scenario/leaves_the_flames/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/turf/open/T = get_turf(bot)
	if(T.active_hotspot)
		return BOT_GYM_PENDING
	for(var/line in transcript)
		if(findtext(line, "can't breathe here") || findtext(line, "in the flames at")) //seek_air, or the flames reflex first (goals/respond_to_fire.dm)
			return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/someone_at_the_machine
	name = "somebody stood at the only spot by a machine"
	desc = "A machine with one tile free beside it, and somebody on that tile. A person swaps places or waits. Bots used to find no way to it at all: the Booze-O-Mat has just the one tile, and a bartender could go minutes without a glass."
	layout = list(
		"#########",
		"#B....CV#",
		"#########")
	time_limit = 20 SECONDS

/datum/bot_scenario/someone_at_the_machine/post_spawn()
	..()
	stand_in(first_marker("C"), "Pat Bystander")

/datum/bot_scenario/someone_at_the_machine/make_goal()
	var/datum/bot_goal/gym_reach/G = new
	G.target = first_placed("V")
	return G

/datum/bot_scenario/someone_at_the_machine/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return get_dist(bot, first_placed("V")) <= 1 ? BOT_GYM_PASS : BOT_GYM_PENDING
