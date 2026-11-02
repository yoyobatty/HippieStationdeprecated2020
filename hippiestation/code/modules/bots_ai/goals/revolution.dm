// Playing the revolution. Head revolutionaries are the game's own: a flash, and anybody conscious who gets flashed by one in
// the face joins, unless they're Command or have a mindshield in them. So a head revolutionary keeps its job for a while, and
// catches people on their own. Once there's enough of them, or it's been long enough, the whole lot go after the heads of staff,
// which is what the team's objectives ask for (/datum/objective/mutiny). Everybody else finds out the way anybody does.

/// The earliest anybody gets flashed, after the revolution starts.
#define BOT_REV_SETTLE_IN (5 MINUTES)
#define BOT_REV_RECRUIT_GAP (2 MINUTES)
/// How many of them before it stops being a secret.
#define BOT_REV_ENOUGH 6
/// Or how long.
#define BOT_REV_UPRISING_AFTER (18 MINUTES)
#define BOT_REV_RANGE 80

/datum/bot_brain
	/// When it next thinks about the revolution.
	var/rev_next_work = 0
	/// People it's flashed over to the cause.
	var/recruited = 0

/// Makes `count` of the crew's bots head revolutionaries, chosen at random. Returns the ones it made.
/proc/bot_start_revolution(count)
	. = list()
	var/list/candidates = list()
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H.bot_brain && H.mind && H.stat != DEAD && bot_traitor_job_allowed(H.mind.assigned_role) && !H.mind.special_role && !HAS_TRAIT(H, TRAIT_MINDSHIELD))
			candidates += H
	if(!length(candidates))
		return
	var/datum/team/revolution/team = new
	team.update_objectives()
	team.update_heads()
	GLOB.bot_rev_started = world.time
	while(length(candidates) && length(.) < count)
		var/mob/living/carbon/human/H = pick_n_take(candidates)
		var/datum/antagonist/rev/head/leader = new
		leader.give_flash = TRUE
		H.bot_brain.being_issued_kit = TRUE
		H.mind.add_antag_datum(leader, team)
		H.bot_brain.being_issued_kit = FALSE
		H.bot_brain.rev_next_work = world.time + BOT_REV_SETTLE_IN + rand(0, 3 MINUTES)
		bot_log(H.bot_brain, "I'm a head revolutionary")
		. += H

GLOBAL_VAR_INIT(bot_rev_started, 0)

/// Null if it isn't one: has_antag_datum() says 0, and ?. takes that for something to read.
/datum/bot_brain/proc/rev_datum()
	return owner.mind?.has_antag_datum(/datum/antagonist/rev) || null

/// The nearest head of staff still standing that it can get to.
/datum/bot_brain/proc/find_head_of_staff(datum/team/revolution/team)
	var/mob/living/carbon/human/best
	for(var/datum/objective/mutiny/O in team.objectives)
		var/mob/living/carbon/human/H = O.target?.current
		if(!istype(H) || H.stat == DEAD || H.z != owner.z || get_dist(owner, H) > BOT_REV_RANGE)
			continue
		if((!best || get_dist(owner, H) < get_dist(owner, best)) && can_walk_lawfully_to(H))
			best = H
	return best

/// Somebody on their own who could be brought round. The nearest few.
/datum/bot_brain/proc/find_recruit(datum/antagonist/rev/R)
	var/list/options = list() //mob -> how far off
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H == owner || !H.mind || H.stat != CONSCIOUS || H.z != owner.z || H.mind.has_antag_datum(/datum/antagonist/rev))
			continue
		if(get_dist(owner, H) <= BOT_REV_RANGE && R.can_be_converted(H))
			options[H] = get_dist(owner, H)
	var/tries = 0
	while(length(options) && tries++ < 4)
		var/mob/living/carbon/human/nearest
		for(var/mob/living/carbon/human/H as anything in options)
			if(!nearest || options[H] < options[nearest])
				nearest = H
		options -= nearest
		if(can_walk_lawfully_to(nearest))
			return nearest
	return null

/datum/bot_duty/revolution
	name = "the revolution"
	tier = BOT_DUTY_URGENT
	priority = 20
	interval_min = 100
	interval_max = 300

/datum/bot_duty/revolution/try_start(datum/bot_brain/bot)
	if(world.time < bot.rev_next_work)
		return FALSE
	var/datum/antagonist/rev/R = bot.rev_datum()
	if(!R?.rev_team)
		return FALSE
	var/datum/team/revolution/team = R.rev_team
	if(length(team.members) >= BOT_REV_ENOUGH || world.time > GLOB.bot_rev_started + BOT_REV_UPRISING_AFTER)
		var/mob/living/carbon/human/head = bot.find_head_of_staff(team)
		if(head && bot.assign_goal(new /datum/bot_goal/traitor_kill/uprising(head)))
			return TRUE
	if(!istype(R, /datum/antagonist/rev/head))
		return FALSE
	bot.rev_next_work = world.time + BOT_REV_RECRUIT_GAP
	var/mob/living/carbon/human/H = bot.find_recruit(R)
	return H ? bot.assign_goal(new /datum/bot_goal/traitor_kill/recruit(H)) : FALSE

/// Somebody caught on their own, and a flash in the face.
/datum/bot_goal/traitor_kill/recruit
	doing = "looking for somebody"
	var/mob/living/carbon/human/mark

/datum/bot_goal/traitor_kill/recruit/New(mob/living/carbon/human/H)
	. = ..(null)
	mark = H

/datum/bot_goal/traitor_kill/recruit/victim()
	return mark

/datum/bot_goal/traitor_kill/recruit/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/traitor_kill/S = new
	S.steps = list(new /datum/bot_step/paced/stalk(), new /datum/bot_step/paced/flash_recruit())
	return list(S)

/datum/bot_goal/traitor_kill/recruit/on_give_up(datum/bot_brain/bot)
	return

/datum/bot_step/paced/flash_recruit
	max_clicks = 4

/datum/bot_step/paced/flash_recruit/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/traitor_kill/G = bot.current_goal
	var/mob/living/carbon/human/V = G?.victim()
	var/obj/item/assembly/flash/flash = bot.find_carried_tool(/obj/item/assembly/flash)
	if(QDELETED(V) || !flash || flash.burnt_out || V.mind?.has_antag_datum(/datum/antagonist/rev) || !bot.owner.Adjacent(V))
		return FALSE
	bot.use_item_on(flash, V)
	bot.owner.changeNext_move(CLICK_CD_MELEE)
	wait_for = CLICK_CD_MELEE
	return TRUE

/datum/bot_step/paced/flash_recruit/finish(datum/bot_brain/bot)
	var/datum/bot_goal/traitor_kill/G = bot.current_goal
	var/mob/living/carbon/human/V = G?.victim()
	if(!V?.mind?.has_antag_datum(/datum/antagonist/rev))
		return GOAL_STEP_FAIL
	bot.recruited++
	bot_tally("flashed over to the revolution")
	bot_log(bot, "brought [V] over to the revolution")
	return GOAL_STEP_SUCCESS

/// In the open, by now. Fists if that's all there is: there's a lot of them.
/datum/bot_goal/traitor_kill/uprising
	doing = "going after a head of staff"
	var/mob/living/carbon/human/head

/datum/bot_goal/traitor_kill/uprising/New(mob/living/carbon/human/H)
	. = ..(null)
	head = H

/datum/bot_goal/traitor_kill/uprising/victim()
	return head

/datum/bot_goal/traitor_kill/uprising/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/traitor_kill/S = new
	S.steps = list(new /datum/bot_step/paced/go_after(), new /datum/bot_step/paced/strike())
	return list(S)

/datum/bot_goal/traitor_kill/uprising/on_give_up(datum/bot_brain/bot)
	bot.rev_next_work = world.time + 1 MINUTES

/datum/bot_goal/traitor_kill/uprising/on_success(datum/bot_brain/bot)
	bot_tally("heads of staff brought down")

/datum/bot_step/paced/go_after
	max_clicks = 100
	var/caught_up = FALSE

/datum/bot_step/paced/go_after/start(datum/bot_brain/bot)
	caught_up = FALSE
	return TRUE

/datum/bot_step/paced/go_after/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/traitor_kill/G = bot.current_goal
	var/mob/living/V = G?.victim()
	var/turf/there = get_turf(V)
	if(!there || V.stat == DEAD || there.z != bot.owner.z)
		return FALSE
	if(bot.owner.Adjacent(V))
		caught_up = TRUE
		return FALSE
	if(bot.pursuing_kind != "follow")
		if(!bot.can_walk_lawfully_to(V))
			return FALSE
		bot.pursue(V, "follow", force = TRUE)
	wait_for = 20
	return TRUE

/datum/bot_step/paced/go_after/finish(datum/bot_brain/bot)
	bot.stop_pursuit()
	return caught_up ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

#undef BOT_REV_SETTLE_IN
#undef BOT_REV_RECRUIT_GAP
#undef BOT_REV_ENOUGH
#undef BOT_REV_UPRISING_AFTER
#undef BOT_REV_RANGE
