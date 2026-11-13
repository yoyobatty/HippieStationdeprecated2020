// Bot Gym: the crew-kill planner (apex/kill_planner.dm), driven by the real traitor duty (scenarios_traitor.dm's base). What the planner
// adds is reached by name, so a build without it compiles, and fails.
//
// Layout letters used here: k the plasma canister, O where the people are (the sabotage's crowd spot), p somebody there.

/datum/bot_scenario/duty/traitor/kill_plan
	job = "Station Engineer"
	time_limit = 45 SECONDS
	kit_backpack = list(/obj/item/lighter/greyscale, /obj/item/card/emag)
	layout = list(
		"#########################",
		"#B..k...................#",
		"#.......................#",
		"#.............Op........#",
		"#.......................#",
		"#.......................#",
		"#########################")
	var/bot_skill = 1
	var/obj/machinery/portable_atmospherics/canister/toxins/canister
	var/mob/living/carbon/human/crew

/datum/bot_scenario/duty/traitor/kill_plan/setup()
	canister = new(first_marker("k"))
	place("k", canister)

/datum/bot_scenario/duty/traitor/kill_plan/post_spawn()
	..()
	brain.skill_override = bot_skill //a traitor is apex whatever it rolled (bot_antags_apex()): the dial's set here
	brain.set_playstyle(BOT_STYLE_ROBUST)
	brain.traitor_plan = BOT_TRAITOR_RAMPAGE
	brain.traitor_shopped = TRUE //no suit to buy: the plan's what this is about
	brain.traitor_business_after = 0
	brain.gym_sabotage_spot = first_marker("O")
	crew = stand_in(first_marker("p"), "Cass Crowd")
	if(hascall(brain, "plan_crew_kill"))
		call(brain, "plan_crew_kill")()

/datum/bot_scenario/duty/traitor/kill_plan/release_run()
	if(!QDELETED(canister))
		canister.valve_open = FALSE
		qdel(canister)
	return ..()

/datum/bot_scenario/duty/traitor/kill_plan/proc/flooded()
	if(QDELETED(canister) || !canister.valve_open || get_dist(canister, first_marker("O")) > 3)
		return FALSE
	for(var/turf/open/T in arena_area)
		if(T.active_hotspot)
			return TRUE
	return FALSE

/datum/bot_scenario/duty/traitor/kill_plan/apex
	name = "kill plan: an apex traitor out to kill everybody opens with a plasma fire where the people are, not a swing at one of them"
	desc = "Apex, the rampage plan, a lighter and a plasma canister across the room from where people are. A player out to kill everybody takes the most of them at once first: it drags the canister to them, opens it and lights it, and goes for anybody after. Before, it went about its rampage the usual way, one at a time, and never thought of the canister."

/datum/bot_scenario/duty/traitor/kill_plan/apex/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(flooded())
		return BOT_GYM_PASS
	if(!QDELETED(crew) && crew.health < crew.maxHealth && !QDELETED(canister) && !canister.valve_open)
		fail_reason = "went for [crew] before any strike"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/duty/traitor/kill_plan/low_skill
	name = "kill plan: a traitor below apex out to kill everybody goes straight for them, as it always did"
	desc = "The same with skill 0.7: no planned strike, the rampage it always had."
	bot_skill = 0.7
	time_limit = 20 SECONDS

/datum/bot_scenario/duty/traitor/kill_plan/low_skill/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!QDELETED(canister) && canister.valve_open)
		fail_reason = "opened the canister: that's the apex strike"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/duty/traitor/kill_plan/low_skill/on_timeout()
	if(bot_transcript_said("KILL PLAN"))
		fail_reason = "made a kill plan below apex"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

// Denying escape. Letters: n somebody near, x somebody at departures (the far end).

/datum/bot_scenario/duty/traitor/deny_escape
	job = "Assistant"
	time_limit = 15 SECONDS
	layout = list(
		"##################",
		"#B..n............#",
		"#.............x..#",
		"##################")
	var/evac = TRUE
	var/mob/living/carbon/human/near
	var/mob/living/carbon/human/leaving

/datum/bot_scenario/duty/traitor/deny_escape/post_spawn()
	..()
	brain.skill_override = 1
	brain.set_playstyle(BOT_STYLE_ROBUST)
	brain.traitor_plan = BOT_TRAITOR_RAMPAGE
	brain.traitor_shopped = TRUE
	brain.traitor_business_after = 0
	near = stand_in(first_marker("n"), "Nell Near")
	leaving = stand_in(first_marker("x"), "Lee Leaving")
	for(var/mob/living/carbon/human/H in list(near, leaving))
		H.mind_initialize() //crew, as next_victim() goes by
		H.mind.assigned_role = "Assistant"
	if("evac_under_way" in vars)
		vars["evac_under_way"] = evac
		vars["departure_turfs"] = list(first_marker("x"))

/datum/bot_scenario/duty/traitor/deny_escape/proc/going_for()
	var/datum/bot_goal/traitor_kill/G = brain.current_goal
	return istype(G) ? G.victim() : null

/datum/bot_scenario/duty/traitor/deny_escape/shuttle
	name = "kill plan: the shuttle's coming, an apex rampager goes for somebody at departures before somebody nearer"
	desc = "Apex, out to kill everybody, the shuttle on its way: an assistant three tiles off, another at departures across the room. The one at departures is about to get away, so it goes for them first. Before, it went for whoever was nearest."

/datum/bot_scenario/duty/traitor/deny_escape/shuttle/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/mob/living/V = going_for()
	if(V == leaving)
		return BOT_GYM_PASS
	if(V == near)
		fail_reason = "went for the one nearest, not the one getting away"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/duty/traitor/deny_escape/no_shuttle
	name = "kill plan: no shuttle coming, an apex rampager goes for whoever's nearest, as it always did"
	desc = "The same with no shuttle called: departures is just another room."
	evac = FALSE

/datum/bot_scenario/duty/traitor/deny_escape/no_shuttle/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/mob/living/V = going_for()
	if(V == near)
		return BOT_GYM_PASS
	if(V == leaving)
		fail_reason = "went past somebody nearer with no shuttle coming"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING
