// Role-hoppers: a job nobody's doing gets picked up by somebody who wasn't hired for it, healing first.
//
// It's the transfer a player gets. Ask on the radio, leave the ID at the HoP's door, and the HoP carries it to the ID console,
// reassigns it and brings it back. After that the card says Medical Doctor, which is all staff go by, and work_role() says the
// same to everything in here that asks what this bot does. With no HoP to ask, it gets on with what its own ID opens.
//
// The engine isn't anybody's to pick up lightly: only with the power going, and only a very competent bot.

#define BOT_HOP_COMPETENCE 0.8
/// Enough of the station off the mains that somebody ought to go and see why.
#define BOT_HOP_POWER_OUT 0.25
#define BOT_HOP_TRANSFER_WAIT (3 MINUTES)
#define BOT_HOP_REST (10 MINUTES)

/// What can be picked up, the most pressing first, and who's already doing it.
GLOBAL_LIST_INIT(bot_cover_jobs, list(
	"Medical Doctor" = list("Medical Doctor", "Chief Medical Officer", "Paramedic", "Geneticist", "Virologist"),
	"Chemist" = list("Chemist"),
	"Station Engineer" = list("Station Engineer", "Chief Engineer"),
	"Janitor" = list("Janitor"),
	"Botanist" = list("Botanist"),
	"Cook" = list("Cook"),
	"Bartender" = list("Bartender"),
	"Cargo Technician" = list("Cargo Technician", "Quartermaster"),
))

/// Jobs that run something the whole station leans on: the last one doing it stays put, or it's only moved the hole.
GLOBAL_LIST_INIT(bot_posts_to_keep, list("Medical Doctor", "Chemist", "Station Engineer", "Atmospheric Technician", "Scientist", "Roboticist"))

/// Transfers waiting on the HoP.
GLOBAL_LIST_EMPTY(bot_transfers)

/datum/bot_brain
	/// The job it's picked up, if it's a role-hopper that has.
	var/standing_in_for
	/// The job it's gone to ask for, which is as good as taken: the next one along should look elsewhere.
	var/applying_for
	var/next_hop_time = 0

/// What this bot does for a living, which isn't always what it was hired as.
/datum/bot_brain/proc/work_role()
	return standing_in_for || owner.mind?.assigned_role

/proc/bot_job_of(mob/living/carbon/human/H)
	return H.bot_brain ? H.bot_brain.work_role() : H.mind?.assigned_role

/// Somebody else alive and aboard doing one of these jobs.
/proc/bot_on_duty(list/jobs, mob/living/carbon/human/asking)
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H == asking || !H.mind || !bot_fit_to_command(H) || !((bot_job_of(H) in jobs) || (H.bot_brain?.applying_for in jobs)))
			continue
		if(H.bot_brain?.gym_run && asking && get_area(H) != get_area(asking))
			continue
		return TRUE
	return FALSE

/// A good part of the station on its batteries or dark. Bot Gym and drills can say so.
/proc/bot_power_failing()
	if(!isnull(GLOB.bot_power_out_drill))
		return GLOB.bot_power_out_drill
	var/total = 0
	var/out = 0
	for(var/obj/machinery/power/apc/A as anything in GLOB.apcs_list)
		if(!is_station_level(A.z))
			continue
		total++
		if(!A.main_status)
			out++
	return total && out / total >= BOT_HOP_POWER_OUT

/// Says whether the power's failing, whatever the APCs do: a drill's or a Bot Gym scenario's say-so.
GLOBAL_VAR(bot_power_out_drill)

/// Anybody can mop. An engine can go badly wrong, and it's left alone until it has to be seen to.
/datum/bot_brain/proc/may_take_on(job)
	return job != "Station Engineer" || (competence >= BOT_HOP_COMPETENCE && bot_power_failing())

/// The first job with nobody else on it. Null if that's the one this bot's already doing.
/datum/bot_brain/proc/short_handed_job()
	var/mine = work_role()
	if((mine in GLOB.bot_posts_to_keep) && !bot_on_duty(list(mine), owner))
		return null
	for(var/job in GLOB.bot_cover_jobs)
		if(!may_take_on(job))
			continue
		if(!bot_on_duty(GLOB.bot_cover_jobs[job], owner))
			return job == work_role() ? null : job
	return null

/// The card to plan a route by. Doors take the one in the hand or the one worn (allowed()), so it's whichever opens more:
/// somebody else's in the hand, a head doing a transfer say, isn't to shut it in its own office.
/datum/bot_brain/proc/route_card()
	var/obj/item/card/id/held = owner.get_idcard(TRUE)
	var/obj/item/card/id/worn = owner.get_idcard(FALSE)
	if(!held || !worn)
		return held || worn
	return length(worn.access) > length(held.access) ? worn : held

/// Its card in its hand, out of the PDA if it's in one. Null if it hasn't got one.
/datum/bot_brain/proc/card_in_hand()
	var/obj/item/card/id/card = owner.get_idcard(FALSE)
	if(!card)
		return null
	if(is_carried(card) && (owner.get_active_held_item() == card || owner.get_inactive_held_item() == card))
		return card
	make_hand_free()
	var/obj/item/pda/P = card.loc
	if(istype(P))
		P.id = null
		P.update_icon()
	else
		owner.temporarilyRemoveItemFromInventory(card)
	if(!owner.put_in_hands(card))
		card.forceMove(owner.drop_location())
		return null
	return card

/// Back in the PDA it came out of, or on its chest.
/datum/bot_brain/proc/wear_card(obj/item/card/id/card)
	var/obj/item/pda/P = owner.wear_id
	if(istype(P) && !P.id)
		P.id_check(owner, card)
	else if(!istype(P))
		equip_displacing(card, ITEM_SLOT_ID)

/datum/bot_brain/proc/take_up_job(job)
	standing_in_for = job
	applying_for = null
	duties = null //worked out again, for what it does now
	bot_log(src, "HOPPER: covering [job]")
	bot_tally("jobs covered")
	bot_news("[owner.real_name]'s covering [lowertext(job)] now, nobody else was", owner)

/datum/bot_duty/cover_short_handed
	name = "picking up what's short-handed"
	tier = BOT_DUTY_URGENT
	interval_min = 600
	interval_max = 1200
	priority = -10

/datum/bot_duty/cover_short_handed/applies_to(datum/bot_brain/bot)
	var/role = bot.owner.mind?.assigned_role
	return bot.playstyle == BOT_STYLE_HOPPER && !(role in GLOB.command_positions) && !(role in GLOB.security_positions)

/datum/bot_duty/cover_short_handed/try_start(datum/bot_brain/bot)
	if(world.time < bot.next_hop_time)
		return FALSE
	if(!bot.gym_run && world.time < SSticker.round_start_time + 5 MINUTES)
		return FALSE //give the place time to fill up and see who's here
	var/job = bot.short_handed_job()
	if(!job)
		return FALSE
	bot.next_hop_time = world.time + BOT_HOP_REST
	bot.applying_for = job
	var/datum/bot_goal/job_transfer/ask = new(job)
	if(bot_find_hop(bot.owner) && bot.assign_goal(ask))
		return TRUE
	bot_say(bot.owner, ";Nobody on [job], so I'm covering it.")
	bot.take_up_job(job)
	return TRUE

/// The HoP, if there's one up and about.
/proc/bot_find_hop(mob/living/carbon/human/asking)
	for(var/mob/living/carbon/human/H in GLOB.carbon_list)
		if(H.mind?.assigned_role != "Head of Personnel" || H.stat != CONSCIOUS || !bot_fit_to_command(H))
			continue
		if(H.bot_brain?.gym_run && asking && get_area(H) != get_area(asking))
			continue
		return H
	return null

// ---------------------------------------------------------------------------------------------
// Asking
// ---------------------------------------------------------------------------------------------

/// A card left out for the HoP.
/datum/bot_transfer
	var/obj/item/card/id/card
	var/job
	var/mob/living/carbon/human/who
	/// Whichever HoP's gone to fetch it.
	var/datum/weakref/taken_by
	var/done = FALSE

/datum/bot_transfer/New(obj/item/card/id/C, title, mob/living/carbon/human/H)
	card = C
	job = title
	who = H
	GLOB.bot_transfers += src

/datum/bot_transfer/Destroy()
	GLOB.bot_transfers -= src
	card = null
	who = null
	return ..()

/// Out to the HoP's door, and a word on the radio.
/datum/bot_goal/job_transfer
	lawful = TRUE
	doing = "asking the HoP for a transfer"
	var/job

/datum/bot_goal/job_transfer/New(title)
	. = ..()
	job = title

/datum/bot_goal/job_transfer/resolve_target(datum/bot_brain/bot)
	target = bot.department_doorstep(null, /area/crew_quarters/heads/hop)
	if(!target && bot.gym_run)
		target = get_turf(bot.owner)

/datum/bot_goal/job_transfer/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/await_transfer(job))
	return list(S)

/datum/bot_goal/job_transfer/on_give_up(datum/bot_brain/bot)
	bot.take_up_job(job) //no way of asking: on with what its own ID opens

/// Card on the floor at the door, and stood over it until it comes back.
/datum/bot_step/paced/await_transfer
	max_clicks = 3
	optional = TRUE
	var/job
	var/datum/bot_transfer/transfer
	var/give_up_at

/datum/bot_step/paced/await_transfer/New(title)
	. = ..()
	job = title

/datum/bot_step/paced/await_transfer/start(datum/bot_brain/bot)
	var/obj/item/card/id/card = bot.card_in_hand()
	if(!card || !bot.owner.dropItemToGround(card))
		bot.take_up_job(job)
		return FALSE
	transfer = new(card, job, bot.owner)
	give_up_at = world.time + BOT_HOP_TRANSFER_WAIT
	bot_say(bot.owner, ";Nobody on [job]. HoP, could I get a transfer? My card's at your door.")
	bot_log(bot, "HOPPER: left [card] for the HoP, for [job]")
	return TRUE

/datum/bot_step/paced/await_transfer/do_click(datum/bot_brain/bot)
	var/obj/item/card/id/card = transfer.card
	if(QDELETED(card))
		return FALSE
	if(transfer.done ? (isturf(card.loc) && bot.owner.Adjacent(card)) : (isturf(card.loc) && world.time > give_up_at && bot.owner.Adjacent(card)))
		bot.try_pickup_target(card)
		bot.wear_card(card)
		return FALSE
	if(world.time > give_up_at + BOT_HOP_TRANSFER_WAIT)
		return FALSE
	bot.telemetry_last_activity = world.time //waiting at a door for somebody isn't going quiet
	wait_for = 3 SECONDS
	return TRUE

/datum/bot_step/paced/await_transfer/finish(datum/bot_brain/bot)
	var/got_it = transfer.done
	qdel(transfer)
	transfer = null
	if(!got_it)
		bot_log(bot, "HOPPER: nobody came for the card")
	bot.take_up_job(job)
	return GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// The HoP's end of it
// ---------------------------------------------------------------------------------------------

/datum/bot_duty/job_transfers
	name = "seeing to transfers"
	tier = BOT_DUTY_URGENT
	jobs = list("Head of Personnel")
	interval_min = 50
	interval_max = 100
	priority = 15

/datum/bot_duty/job_transfers/try_start(datum/bot_brain/bot)
	for(var/datum/bot_transfer/T as anything in GLOB.bot_transfers)
		if(!T.taken_by?.resolve() && !T.done && isturf(T.card?.loc) && bot.find_id_console() && (!bot.gym_run || get_area(T.card) == get_area(bot.owner)))
			return bot.assign_goal(new /datum/bot_goal/process_transfer(T))
	return FALSE

/// The console that does reassignments, not the departmental ones.
/datum/bot_brain/proc/find_id_console()
	var/obj/machinery/computer/card/best
	for(var/obj/machinery/computer/card/C as anything in bot_instances_of(/obj/machinery/computer/card))
		if(QDELETED(C) || C.z != owner.z || C.target_dept || !C.is_operational() || (gym_run && get_area(C) != get_area(owner)))
			continue
		if(istype(get_area(C), /area/crew_quarters/heads/hop))
			return C
		if(!best || get_dist(owner, C) < get_dist(owner, best))
			best = C
	return best

/// Pick the card up, reassign it, bring it back.
/datum/bot_goal/process_transfer
	lawful = TRUE
	doing = "doing a transfer"
	var/datum/bot_transfer/transfer

/datum/bot_goal/process_transfer/New(datum/bot_transfer/T)
	. = ..()
	transfer = T

/datum/bot_goal/process_transfer/resolve_target(datum/bot_brain/bot)
	if(!QDELETED(transfer) && !QDELETED(transfer.card) && !transfer.done)
		target = bot.find_id_console()

/datum/bot_goal/process_transfer/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	var/datum/bot_step/move_to/back = new
	back.step_target = transfer.who
	S.steps = list(new /datum/bot_step/fetch_transfer_card(transfer), new /datum/bot_step/move_to(), new /datum/bot_step/paced/reassign_card(transfer), back, new /datum/bot_step/hand_back_card(transfer))
	return list(S)

/datum/bot_goal/process_transfer/on_give_up(datum/bot_brain/bot)
	if(!QDELETED(transfer) && !transfer.done)
		transfer.taken_by = null
		if(bot.is_carried(transfer.card)) //back where it can be found
			bot.owner.dropItemToGround(transfer.card)

/datum/bot_step/fetch_transfer_card
	var/datum/bot_transfer/transfer

/datum/bot_step/fetch_transfer_card/New(datum/bot_transfer/T)
	. = ..()
	transfer = T

/datum/bot_step/fetch_transfer_card/execute(datum/bot_brain/bot)
	if(QDELETED(transfer) || QDELETED(transfer.card))
		return GOAL_STEP_FAIL
	if(bot.is_carried(transfer.card))
		bot.put_away(transfer.card) //in the hand, it's the card the doors and the route would go by
		return GOAL_STEP_SUCCESS
	transfer.taken_by = WEAKREF(bot)
	if(isturf(transfer.card.loc) && bot.suspend_goal_for(new /datum/bot_goal/take_item/exact(transfer.card)))
		return GOAL_STEP_PENDING
	return GOAL_STEP_FAIL

/// The console's own buttons (card.dm Topic()): both cards in, log in, assign, both cards out. Whatever they could already open
/// stays on the card: nobody loses the way home.
/datum/bot_step/paced/reassign_card
	max_clicks = 5
	var/datum/bot_transfer/transfer
	var/obj/item/card/id/own

/datum/bot_step/paced/reassign_card/New(datum/bot_transfer/T)
	. = ..()
	transfer = T

/datum/bot_step/paced/reassign_card/start(datum/bot_brain/bot)
	own = bot.card_in_hand()
	return !QDELETED(transfer) && !QDELETED(transfer.card) && own && istype(bot.current_goal?.target, /obj/machinery/computer/card)

/datum/bot_step/paced/reassign_card/do_click(datum/bot_brain/bot)
	var/obj/machinery/computer/card/C = bot.current_goal.target
	if(QDELETED(C) || !bot.owner.Adjacent(C))
		return FALSE
	if(!C.scan)
		return bot.use_item_on(own, C) && C.scan == own
	if(!C.modify)
		return bot.use_item_on(transfer.card, C) && C.modify == transfer.card
	if(C.scan != own || C.modify != transfer.card)
		return FALSE //somebody's using it
	if(!(ACCESS_CHANGE_IDS in own.access))
		return FALSE
	var/datum/job/J = SSjob.GetJob(transfer.job)
	if(!J)
		return FALSE
	C.modify.access |= J.get_access()
	C.modify.assignment = transfer.job
	if(C.modify.registered_account)
		C.modify.registered_account.account_job = J
	playsound(C, 'sound/machines/terminal_prompt_confirm.ogg', 50, 0)
	C.eject_id_modify(bot.owner)
	C.eject_id_scan(bot.owner)
	bot.wear_card(own)
	bot.put_away(transfer.card)
	transfer.done = TRUE
	bot_log(bot, "HOPPER: made [transfer.who] a [transfer.job]")
	bot_tally("transfers")
	return FALSE

/datum/bot_step/paced/reassign_card/finish(datum/bot_brain/bot)
	if(transfer?.done)
		return GOAL_STEP_SUCCESS
	var/obj/machinery/computer/card/C = bot.current_goal?.target
	if(istype(C) && bot.owner.Adjacent(C)) //both back out, before anything else
		if(C.modify == transfer?.card)
			C.eject_id_modify(bot.owner)
		if(C.scan == own)
			C.eject_id_scan(bot.owner)
	if(own?.loc != bot.owner.wear_id)
		bot.wear_card(own)
	return GOAL_STEP_FAIL

/datum/bot_step/hand_back_card
	var/datum/bot_transfer/transfer

/datum/bot_step/hand_back_card/New(datum/bot_transfer/T)
	. = ..()
	transfer = T

/datum/bot_step/hand_back_card/execute(datum/bot_brain/bot)
	if(QDELETED(transfer) || QDELETED(transfer.card))
		return GOAL_STEP_SUCCESS //they've gone: it's their loss
	bot.owner.dropItemToGround(transfer.card)
	bot_say(bot.owner, "There you go, [transfer.who.name]. You're a [transfer.job] now.")
	return GOAL_STEP_SUCCESS

#undef BOT_HOP_COMPETENCE
#undef BOT_HOP_POWER_OUT
#undef BOT_HOP_TRANSFER_WAIT
#undef BOT_HOP_REST
