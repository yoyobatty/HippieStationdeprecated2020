// The Chapel (overnight 2026-11-07: the Chaplain was the one job with no work of its own - a three-shift batch had its
// Chaplains doing nothing but eat and drink, their only duty the morgue, shared with the doctors and empty most shifts).
//
//  - every so often the Chaplain holds a service: says so on the radio, goes to the altar (the wooden table at the front
//    of the Chapel, or the middle of it), waits a minute or so for people, says a few words, remembers anybody the
//    station has lost this shift by name, and sends them off
//  - crew with a quiet minute who like company go along now and then: to a free seat in the Chapel, sat until it's over

#define BOT_SERVICE_WAIT (60 SECONDS) //from the call to the first words
#define BOT_SERVICE_LENGTH (3 MINUTES) //how long attendees will stay for one

GLOBAL_VAR_INIT(bot_chapel_service_until, 0)
GLOBAL_DATUM(bot_chapel_service_spot, /turf)

GLOBAL_LIST_INIT(bot_service_calls, list(
	";Service in the Chapel in a minute or two. Everybody's welcome.",
	";There'll be a service in the Chapel shortly, if anybody wants a quiet moment.",
	";Chapel service starting soon. Come as you are.",
))
GLOBAL_LIST_INIT(bot_sermon_lines, list(
	"Thank you all for coming. It's not every shift people find the time.",
	"Out here there's a lot of nothing between us and the stars. All the more reason to look after each other.",
	"Whatever you believe, or don't, you're welcome here.",
	"Every one of us is one hull breach from finding out what comes next. Let's not rush it.",
	"Be kind to the engineers. They're all that's keeping the dark outside.",
	"If something's weighing on you, my door is open. The Chapel's open all shift.",
	"Mind each other in the halls. Tempers run short when the air does.",
	"Take a moment. Breathe. The station will still be here in a minute.",
	"We work hard and we don't always get thanked for it. So: thank you.",
	"Whatever's out there, it's no excuse to forget the people in here.",
	"Look in on somebody today. You'd be surprised what a word does.",
	"Let's have a moment's quiet together.",
))
GLOBAL_LIST_INIT(bot_service_endings, list(
	"Go in peace, and watch the airlocks.",
	"That's all. Look after yourselves out there.",
	"Thank you. Go well.",
))

/datum/bot_brain
	var/services_held = 0
	var/services_attended = 0
	/// The service (by its end time) it last went to, so it doesn't go twice
	var/last_service_attended = 0

/// Somewhere in the Chapel to stand and speak from: beside its altar table, or its middle.
/proc/bot_chapel_altar_spot()
	var/area/chapel/main/A = GLOB.areas_by_type[/area/chapel/main]
	if(!A)
		return null
	var/list/floors = list()
	for(var/turf/open/floor/F in A)
		if(!is_blocked_turf(F, TRUE))
			floors += F
	if(!length(floors))
		return null
	for(var/obj/structure/table/wood/T in A)
		for(var/dir in GLOB.cardinals)
			var/turf/F = get_step(T, dir)
			if((F in floors) && !(locate(/obj/structure/chair) in F))
				return F
	// No altar: the middle of it.
	var/x = 0
	var/y = 0
	for(var/turf/F in floors)
		x += F.x
		y += F.y
	var/turf/first = floors[1]
	var/turf/middle = locate(round(x / length(floors)), round(y / length(floors)), first.z)
	if(middle in floors)
		return middle
	return floors[round(length(floors) / 2) || 1]

/// A free seat in the Chapel, or a free floor if they're all taken.
/proc/bot_chapel_free_seat(turf/near)
	var/area/A = get_area(near)
	if(!A)
		return null
	var/turf/best
	var/best_dist
	for(var/obj/structure/chair/C in A)
		if(C.has_buckled_mobs() || !isturf(C.loc))
			continue
		var/dist = get_dist(C, near)
		if(dist < 1)
			continue
		if(!best || dist < best_dist)
			best = C.loc
			best_dist = dist
	return best

// ---------------------------------------------------------------------------------------------
// The Chaplain's service
// ---------------------------------------------------------------------------------------------

/datum/bot_duty/chapel_service
	name = "holding a service"
	jobs = list("Chaplain")
	interval_min = 6000
	interval_max = 12000

/datum/bot_duty/chapel_service/try_start(datum/bot_brain/bot)
	if(world.time < 5 MINUTES || GLOB.security_level >= SEC_LEVEL_RED || bot.gone_loud())
		return FALSE //not straight off, and not with the station in trouble
	if(world.time < GLOB.bot_chapel_service_until + 10 MINUTES)
		return FALSE //one's just been held
	var/turf/spot = bot_chapel_altar_spot()
	if(!spot || spot.z != bot.owner.z || get_dist(bot.owner, spot) > 80)
		return FALSE
	return bot.assign_goal(new /datum/bot_goal/chapel_service(spot))

/datum/bot_goal/chapel_service
	lawful = TRUE
	doing = "holding a service in the Chapel"

/datum/bot_goal/chapel_service/New(turf/spot)
	. = ..()
	target = spot

/datum/bot_goal/chapel_service/resolve_target(datum/bot_brain/bot)
	if(!isturf(target))
		target = null

/datum/bot_goal/chapel_service/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/leisure/S = new
	S.steps = list(new /datum/bot_step/call_service(), new /datum/bot_step/move_to(), new /datum/bot_step/paced/hold_service())
	return list(S)

/datum/bot_goal/chapel_service/on_give_up(datum/bot_brain/bot)
	if(GLOB.bot_chapel_service_spot == target)
		GLOB.bot_chapel_service_until = world.time //over: nobody waits on

/// Said on the radio as it sets off, so people have the walk's time to come.
/datum/bot_step/call_service/execute(datum/bot_brain/bot)
	GLOB.bot_chapel_service_spot = bot.current_goal?.target
	GLOB.bot_chapel_service_until = world.time + BOT_SERVICE_WAIT + BOT_SERVICE_LENGTH
	bot_say(bot.owner, pick(GLOB.bot_service_calls), TRUE)
	bot_log(bot, "called a service in the Chapel")
	return GOAL_STEP_SUCCESS

/// At the altar: a wait for people, a few words a few seconds apart, the dead remembered, and an ending.
/datum/bot_step/paced/hold_service
	max_clicks = 40
	var/started_at
	var/list/said
	var/list/remembered
	var/lines

/datum/bot_step/paced/hold_service/start(datum/bot_brain/bot)
	started_at = world.time
	said = list()
	remembered = list()
	lines = rand(3, 5)
	return TRUE

/datum/bot_step/paced/hold_service/do_click(datum/bot_brain/bot)
	var/turf/spot = bot.current_goal?.target
	// Waits for people till the minute's up, or sooner once a few are sat.
	var/list/here = list()
	for(var/mob/living/carbon/human/H in view(6, bot.owner))
		if(H != bot.owner && H.stat == CONSCIOUS)
			here += H
	if(!length(said) && world.time < started_at + BOT_SERVICE_WAIT && length(here) < 3)
		wait_for = 30
		return TRUE
	if(get_turf(bot.owner) != spot && get_dist(bot.owner, spot) > 1)
		return FALSE //moved off it (pulled away, a fight): it's over
	if(length(said) < lines)
		var/line
		if(!length(said))
			line = length(here) ? "Thank you all for coming." : "Nobody? That's alright. I'll say a few words anyway."
		else
			line = pick(GLOB.bot_sermon_lines - said)
		said += line
		bot_say(bot.owner, line)
		wait_for = rand(40, 70)
		return TRUE
	// Anybody the station's lost this shift, by name.
	var/list/lost = list()
	for(var/mob/living/carbon/human/H in GLOB.dead_mob_list)
		if(H.mind?.assigned_role && H.real_name && !(H.real_name in remembered) && is_station_level(H.z))
			lost += H.real_name
	if(length(lost) && !length(remembered))
		remembered = lost.Copy(1, min(length(lost), 4) + 1)
		bot_say(bot.owner, "Let's remember [english_list(remembered)], who we've lost this shift.")
		wait_for = 60
		return TRUE
	bot_say(bot.owner, pick(GLOB.bot_service_endings))
	bot.services_held++
	bot_tally("chapel services held")
	bot_log(bot, "held a service for [length(here)]")
	GLOB.bot_chapel_service_until = world.time + 10 SECONDS
	return FALSE

/datum/bot_step/paced/hold_service/finish(datum/bot_brain/bot)
	return bot.services_held && length(said) >= lines ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// Going along
// ---------------------------------------------------------------------------------------------

/datum/bot_duty/attend_service
	name = "going to a service"
	tier = BOT_DUTY_LEISURE
	interval_min = 300
	interval_max = 900

/datum/bot_duty/attend_service/try_start(datum/bot_brain/bot)
	if(world.time > GLOB.bot_chapel_service_until || GLOB.bot_chapel_service_until == bot.last_service_attended)
		return FALSE
	if(bot.work_role() == "Chaplain" || bot.sociability < 0.4 || bot.gone_loud() || !prob(35))
		return FALSE
	var/turf/spot = GLOB.bot_chapel_service_spot
	if(!spot || spot.z != bot.owner.z || get_dist(bot.owner, spot) > 50)
		return FALSE
	var/turf/seat = bot_chapel_free_seat(spot)
	if(!seat)
		return FALSE
	bot.last_service_attended = GLOB.bot_chapel_service_until
	return bot.assign_goal(new /datum/bot_goal/attend_service(seat))

/datum/bot_goal/attend_service
	lawful = TRUE
	doing = "at a service in the Chapel"

/datum/bot_goal/attend_service/New(turf/seat)
	. = ..()
	target = seat

/datum/bot_goal/attend_service/resolve_target(datum/bot_brain/bot)
	if(!isturf(target) || world.time > GLOB.bot_chapel_service_until)
		target = null

/datum/bot_goal/attend_service/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/leisure/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/sit_through_service())
	return list(S)

/// Sat (on the chair if there is one) till the Chaplain's done, quiet.
/datum/bot_step/paced/sit_through_service
	max_clicks = 60

/datum/bot_step/paced/sit_through_service/start(datum/bot_brain/bot)
	var/obj/structure/chair/C = locate(/obj/structure/chair) in get_turf(bot.owner)
	if(C && !C.has_buckled_mobs())
		C.buckle_mob(bot.owner)
	bot.services_attended++
	return TRUE

/datum/bot_step/paced/sit_through_service/do_click(datum/bot_brain/bot)
	if(world.time > GLOB.bot_chapel_service_until)
		if(bot.owner.buckled)
			bot.owner.buckled.unbuckle_mob(bot.owner)
		return FALSE
	var/turf/spot = GLOB.bot_chapel_service_spot
	if(spot)
		bot.owner.face_atom(spot)
	wait_for = 30
	return TRUE

/datum/bot_step/paced/sit_through_service/finish(datum/bot_brain/bot)
	if(bot.owner.buckled)
		bot.owner.buckled.unbuckle_mob(bot.owner)
	return GOAL_STEP_SUCCESS

#undef BOT_SERVICE_WAIT
#undef BOT_SERVICE_LENGTH
