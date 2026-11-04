// A round of the job, the user's ruling for every job: "rounds by personality. Walk a round of what matters every 5-15 min and fix what's
// wrong; diligent more often, lazy less." Every so often a bot goes past two or three of what matters in its department, stops at each
// for a look, and whatever duty's for putting it right takes it from there if something isn't (a sleeper with somebody dead in it, a
// cell timer run out, the SMES flat). Bots went only where a duty sent them, and in between stood about or wandered off anywhere.
// How often comes from the duty's interval and the bot's diligence (next_look(), bot_duties.dm): about five minutes for a keen one, a
// quarter of an hour for a slacker.

/// Department -> what's worth a look on a round of it.
GLOBAL_LIST_INIT(bot_round_machines, list(
	"engineering" = list(/obj/machinery/power/smes, /obj/machinery/computer/monitor, /obj/machinery/computer/station_alert),
	"medical" = list(/obj/machinery/sleeper, /obj/machinery/computer/crew, /obj/machinery/computer/cloning, /obj/machinery/atmospherics/components/unary/cryo_cell),
	"science" = list(/obj/machinery/computer/rdconsole, /obj/machinery/rnd/production/protolathe, /obj/machinery/rnd/server),
	"security" = list(/obj/machinery/door_timer, /obj/machinery/computer/secure_data, /obj/machinery/computer/security),
	"supply" = list(/obj/machinery/computer/cargo, /obj/machinery/requests_console),
	"command" = list(/obj/machinery/computer/communications, /obj/machinery/computer/card),
))

/// How many stops on a round.
#define BOT_ROUND_STOPS 3

/datum/bot_duty/job_round
	name = "doing the rounds"
	tier = BOT_DUTY_WORK
	priority = 1
	interval_min = 3000
	interval_max = 7200

/datum/bot_duty/job_round/applies_to(datum/bot_brain/bot)
	return length(bot.my_departments()) > 0

/datum/bot_duty/job_round/try_start(datum/bot_brain/bot)
	if(bot.state == BOT_STATE_GOAL && bot.current_goal)
		return FALSE
	if(bot.owner.bot_life_sentence || bot.is_in_active_cell(bot.owner) || !(is_station_level(bot.owner.z) || bot.gym_run))
		return FALSE
	var/department = pick(bot.my_departments())
	var/list/stops = list()
	for(var/path in GLOB.bot_round_machines[department])
		for(var/obj/machinery/M as anything in bot_instances_of(path))
			if(QDELETED(M) || M.z != bot.owner.z || bot_department_of(get_area(M)) != department)
				continue
			if(bot.gym_run && get_area(M) != get_area(bot.owner))
				continue
			stops += M
	if(!length(stops))
		return FALSE
	stops = shuffle(stops)
	stops.Cut(min(length(stops), BOT_ROUND_STOPS) + 1)
	return bot.assign_goal(new /datum/bot_goal/job_round(stops))

/datum/bot_goal/job_round
	lawful = TRUE
	doing = "doing my rounds"
	var/list/stops

/datum/bot_goal/job_round/New(list/L)
	. = ..()
	stops = L

/datum/bot_goal/job_round/resolve_target(datum/bot_brain/bot)
	for(var/obj/machinery/M as anything in stops)
		if(QDELETED(M))
			stops -= M
	target = length(stops) ? stops[1] : null

/datum/bot_goal/job_round/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/robotics/S = new
	S.steps = list(new /datum/bot_step/paced/round_of_stops())
	return list(S)

/// From one stop to the next: walked to, a look at it, a moment stood there, and on.
/datum/bot_step/paced/round_of_stops
	max_clicks = 12
	var/at = 1
	var/tries = 0

/datum/bot_step/paced/round_of_stops/start(datum/bot_brain/bot)
	at = 1
	tries = 0
	return TRUE

/datum/bot_step/paced/round_of_stops/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/job_round/G = bot.current_goal
	if(!istype(G) || at > length(G.stops))
		return FALSE
	var/obj/machinery/M = G.stops[at]
	if(QDELETED(M))
		at++
		return TRUE
	if(!bot.owner.Adjacent(M))
		if(bot.pursuing_kind)
			wait_for = 10
			return TRUE
		if(++tries > 3) //no way to it: on to the next
			at++
			tries = 0
			return TRUE
		bot.pursue(M, "follow", force = TRUE) //not "goal": that one's arrival ends the step (on_goal_pursuit_finished())
		wait_for = 10
		return TRUE
	bot.owner.face_atom(M)
	bot.human_pause(M)
	bot_tally("round stops")
	if(at == length(G.stops) && prob(20))
		bot_say(bot.owner, pick("All looks fine.", "Everything's in order.", "Nothing wrong here.", "Rounds done."))
	at++
	tries = 0
	wait_for = rand(15, 40)
	return TRUE

#undef BOT_ROUND_STOPS
