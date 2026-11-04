// Red alert, the user's "regroup and gear up" for somebody Security can't handle: the head of Security, or the most senior head
// about, takes the station to red, and red is when Space Law lets Security use lethal force on anybody (bot_may_use_lethal_force(),
// bot_law.dm). A comms console only goes as far as blue (goals/repair_damage.dm); red takes two heads at two keycard devices, one
// pressing "Red Alert" and the other swiping within two seconds of it (keycard_authentication.dm). So it's a plan between two of them:
// the one who calls it picks the nearest other head, says so on the radio, and each goes to a device; once both are stood at one, the
// press and the swipe. A traitor in a nanosuit killed twenty of a crew in seven minutes with Security firing disablers at it.

/// When the plan gives up: neither of them got there.
#define BOT_RED_ALERT_PLAN_TIME (3 MINUTES)

/// Who's taking the station to red, and where.
/datum/bot_red_alert_plan
	var/datum/bot_brain/initiator
	var/datum/bot_brain/confirmer
	var/obj/machinery/keycard_auth/first
	var/obj/machinery/keycard_auth/second
	var/started_at = 0

GLOBAL_DATUM(bot_red_alert_plan, /datum/bot_red_alert_plan)
/// After a try that came to nothing, not again before this: a head walking to the keycard device every two minutes isn't anybody.
GLOBAL_VAR_INIT(bot_red_alert_next_try, 0)

/// Somebody at large Security can't deal with as things are: in a nanosuit and wanted for something serious, or two murderers loose.
/proc/bot_red_alert_called_for()
	if(GLOB.security_level >= SEC_LEVEL_RED)
		return FALSE
	var/murderers = 0
	for(var/datum/weakref/ref as anything in GLOB.bot_security_wanted)
		var/mob/living/carbon/human/H = ref.resolve()
		var/datum/bot_wanted/W = GLOB.bot_security_wanted[ref]
		if(!istype(H) || H.stat == DEAD || H.handcuffed)
			continue
		if(W.severity >= BOT_CRIME_MAJOR && istype(H.wear_suit, /obj/item/clothing/suit/space/hardsuit/nano))
			return TRUE
		if(W.severity >= BOT_CRIME_MURDER)
			murderers++
	return murderers >= 2

/// The heads, most senior for this first: whoever's first on the list and fit for it calls the alert.
GLOBAL_LIST_INIT(bot_red_alert_heads, list("Head of Security", "Captain", "Head of Personnel", "Chief Engineer", "Research Director", "Chief Medical Officer"))

/// A head bot that could go to a device now: up, aboard, not cuffed, not in a fight or making an arrest.
/proc/bot_head_free_for_alert(datum/bot_brain/B)
	if(QDELETED(B) || QDELETED(B.owner) || B.owner.stat != CONSCIOUS || B.owner.handcuffed || !(is_station_level(B.owner.z) || B.gym_run))
		return FALSE
	if(B.state == BOT_STATE_COMBAT || B.state == BOT_STATE_ARREST || B.gone_loud()) //goals/robust.dm
		return FALSE
	return (B.work_role() in GLOB.bot_red_alert_heads)

/// The device it'd go to: the nearest working one it can walk to, other than `not_this`.
/datum/bot_brain/proc/nearest_keycard_device(obj/machinery/keycard_auth/not_this)
	var/obj/machinery/keycard_auth/best
	var/best_dist
	for(var/obj/machinery/keycard_auth/K as anything in bot_instances_of(/obj/machinery/keycard_auth))
		if(QDELETED(K) || K == not_this || K.z != owner.z || (K.stat & (BROKEN|NOPOWER)))
			continue
		if(gym_run && get_area(K) != get_area(owner))
			continue
		var/dist = get_dist(owner, K)
		if(best && dist >= best_dist)
			continue
		if(!can_walk_lawfully_to(K))
			continue
		best = K
		best_dist = dist
	return best

/datum/bot_duty/red_alert
	name = "calling red alert"
	jobs = list("Head of Security", "Captain", "Head of Personnel", "Chief Engineer", "Research Director", "Chief Medical Officer")
	tier = BOT_DUTY_URGENT
	priority = 30
	interval_min = 100
	interval_max = 200

/datum/bot_duty/red_alert/try_start(datum/bot_brain/bot)
	var/datum/bot_red_alert_plan/P = GLOB.bot_red_alert_plan
	if(P && (world.time > P.started_at + BOT_RED_ALERT_PLAN_TIME || GLOB.security_level >= SEC_LEVEL_RED || QDELETED(P.initiator) || QDELETED(P.confirmer)))
		GLOB.bot_red_alert_plan = null
		P = null
	if(P || world.time < GLOB.bot_red_alert_next_try || !bot_red_alert_called_for() || !bot_head_free_for_alert(bot))
		return FALSE
	// The most senior head who's free calls it; anybody junior to one who could leaves it to them.
	var/rank = GLOB.bot_red_alert_heads.Find(bot.work_role())
	var/datum/bot_brain/partner
	var/partner_dist
	for(var/datum/bot_brain/B as anything in GLOB.bot_brains)
		if(B == bot || !bot_head_free_for_alert(B) || B.owner.z != bot.owner.z)
			continue
		if(bot.gym_run && B.gym_run != bot.gym_run)
			continue
		if(GLOB.bot_red_alert_heads.Find(B.work_role()) < rank)
			return FALSE
		var/dist = get_dist(bot.owner, B.owner)
		if(!partner || dist < partner_dist)
			partner = B
			partner_dist = dist
	if(!partner)
		return FALSE
	var/obj/machinery/keycard_auth/mine = bot.nearest_keycard_device()
	var/obj/machinery/keycard_auth/theirs = mine && partner.nearest_keycard_device(mine)
	if(!theirs)
		return FALSE
	P = new
	P.initiator = bot
	P.confirmer = partner
	P.first = mine
	P.second = theirs
	P.started_at = world.time
	GLOB.bot_red_alert_plan = P
	if(!bot.assign_goal(new /datum/bot_goal/red_alert(mine, P)))
		bot_log(bot, "couldn't set off for a keycard device to call red alert")
		GLOB.bot_red_alert_plan = null
		return FALSE
	if(partner.state == BOT_STATE_GOAL)
		partner.drop_goals("red alert")
	if(!partner.assign_goal(new /datum/bot_goal/red_alert(theirs, P)))
		bot_log(bot, "[partner.owner] couldn't set off for a keycard device")
		GLOB.bot_red_alert_plan = null
		bot.drop_goals("nobody to swipe for red alert")
		return FALSE
	bot_log(bot, "calling red alert with [partner.owner] at [mine] and [theirs]")
	bot_say(bot.owner, ";[partner.owner.first_name()], to your keycard device. We're going to red alert.")
	return TRUE

/datum/bot_goal/red_alert
	lawful = TRUE
	never_rests = TRUE
	doing = "on my way to a keycard device, we're going to red alert"

/datum/bot_goal/red_alert
	/// The plan it's part of: only that one is given up with it.
	var/datum/bot_red_alert_plan/plan

/datum/bot_goal/red_alert/New(obj/machinery/keycard_auth/K, datum/bot_red_alert_plan/P)
	. = ..()
	target = K
	plan = P

/datum/bot_goal/red_alert/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target) || !GLOB.bot_red_alert_plan)
		target = null

/datum/bot_goal/red_alert/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/red_alert/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/keycard_swipe())
	return list(S)

/datum/bot_goal/red_alert/on_give_up(datum/bot_brain/bot)
	if(plan && GLOB.bot_red_alert_plan == plan)
		GLOB.bot_red_alert_plan = null
		if(!bot.gym_run)
			GLOB.bot_red_alert_next_try = world.time + 5 MINUTES

/datum/bot_strategy/red_alert/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// Stood at its device, waiting for the other: once both are there, the one who called it presses "Red Alert" and the other swipes
/// in the two seconds the devices give it.
/datum/bot_step/paced/keycard_swipe
	max_clicks = 10
	var/until = 0
	var/pressed = FALSE

/datum/bot_step/paced/keycard_swipe/start(datum/bot_brain/bot)
	until = world.time + 90 SECONDS
	pressed = FALSE
	return bot.owner.Adjacent(bot.current_goal?.target)

/datum/bot_step/paced/keycard_swipe/do_click(datum/bot_brain/bot)
	var/datum/bot_red_alert_plan/P = GLOB.bot_red_alert_plan
	if(GLOB.security_level >= SEC_LEVEL_RED)
		if(pressed)
			bot_log(bot, "red alert's up")
			bot_tally("red alerts")
			bot_say(bot.owner, ";Red alert. Security, lethals are authorised. Everybody else, stay out of their way.")
		return FALSE
	if(!P || world.time > until || !bot.owner.Adjacent(bot.current_goal?.target))
		return FALSE
	wait_for = 10
	if(bot != P.initiator || pressed)
		return TRUE //the one who called it does the pressing; once it has, the alert takes a moment to go up
	var/mob/living/carbon/human/other = P.confirmer?.owner
	if(QDELETED(other) || other.stat != CONSCIOUS || QDELETED(P.first) || QDELETED(P.second) || !other.Adjacent(P.second))
		return TRUE
	pressed = TRUE
	bot.owner.face_atom(P.first)
	other.face_atom(P.second)
	bot.telemetry_ui_action(P.first, "Red Alert")
	P.confirmer.telemetry_ui_action(P.second, "swipe")
	INVOKE_ASYNC(GLOBAL_PROC, GLOBAL_PROC_REF(bot_press_and_swipe), bot.owner, other, P.first, P.second) //the alert going up sleeps
	return TRUE

/// "Red Alert" on one device and the swipe on the other, inside the two seconds: what the two of them do at once.
/proc/bot_press_and_swipe(mob/living/carbon/human/presser, mob/living/carbon/human/swiper, obj/machinery/keycard_auth/first, obj/machinery/keycard_auth/second)
	usr = presser //the device takes whoever pressed it from usr (sendEvent()), as its own ui_act() would have it
	first.sendEvent("Red Alert") //KEYCARD_RED_ALERT, which keycard_authentication.dm keeps to itself
	if(second.event_source == first)
		second.event_source.trigger_event(swiper)
		second.event_source = null

/datum/bot_step/paced/keycard_swipe/finish(datum/bot_brain/bot)
	var/datum/bot_red_alert_plan/P = GLOB.bot_red_alert_plan
	if(GLOB.security_level >= SEC_LEVEL_RED)
		if(P && P.initiator == bot)
			GLOB.bot_red_alert_plan = null
		return GOAL_STEP_SUCCESS
	return GOAL_STEP_FAIL

#undef BOT_RED_ALERT_PLAN_TIME
