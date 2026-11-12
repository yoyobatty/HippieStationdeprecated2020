// Breaks. The user's ruling (2026-11-12): bots take breaks at the bar, the kitchen or the dorms in quiet times, sit together, order
// food and drinks, and chat. Until now a bot sat down only if a stroll happened to end on a chair (try_sit_down()), for half a minute.
//
//  - Now and then in a quiet shift (no red alert, nobody being killed), less often the keener it is: a few minutes on a break.
//  - It picks somewhere to go by who it is (a barfly the bar) and who's there: where a friend's sitting, never where somebody it can't
//    stand is. It takes a seat next to people it likes, or anybody, before an empty table.
//  - At the bar with a bartender about, it asks for a drink out loud, the way a player would, and the bartender (bot or player) hears it.
//  - Sitting there it talks more (handle_idle_chat()), and gets up when the break's over, or the moment something's wrong.
//  - Friends plan one together (bot_threads.dm: "Bar after this?" "Go on then."), and a friend nearby may come along.

/// The places people go to sit down: the words in their area names.
GLOBAL_LIST_INIT(bot_hangout_words, list("Bar", "Cafeteria", "Dormitories", "Lounge", "Diner", "Kitchen"))

/datum/bot_brain
	/// When its break's over (0 when it isn't on one)
	var/break_until = 0
	/// A break a friend asked it to: where, and until when it'll still go
	var/area/break_planned_in
	var/break_planned_until = 0

/datum/bot_brain/proc/on_break()
	if(!break_until)
		return FALSE
	if(world.time < break_until && owner.buckled)
		return TRUE
	break_until = 0 //over, or it got up for something
	if(owner.stat == CONSCIOUS && state == BOT_STATE_WANDER && prob(30))
		bot_say(owner, pick("Right, back to it.", "Break's over.", "Better get back to work.", "See you lot."))
	return FALSE

/// A quiet stretch of shift: nobody's going to mind somebody sitting down.
/datum/bot_brain/proc/quiet_enough_for_a_break()
	if((bot_shift_gone_bad() && !gym_run) || seclevel2num(get_security_level()) >= SEC_LEVEL_RED || hardened && nerve < 0.4)
		return FALSE
	if(owner.health < owner.maxHealth * 0.8 || bot_traitor || gone_loud() || op_team || bot_wizard)
		return FALSE
	return TRUE

/// Whether it'll go for a break with them now.
/datum/bot_brain/proc/will_hang_out_with(mob/living/M)
	if(!quiet_enough_for_a_break() || dislikes(M))
		return FALSE
	if(state == BOT_STATE_GOAL && current_goal && !current_goal.off_duty && !istype(current_goal, /datum/bot_goal/tag_along))
		return regard_of(M) >= 4 && diligence < 0.8 //a friend can talk it out of work, unless it's a keen one
	return regard_of(M) >= 1.5 || sociability >= 0.55

/// The hangouts on its level it'd go to, best first by who it is and who's there.
/datum/bot_brain/proc/pick_hangout(mob/living/with)
	var/turf/here = get_turf(owner)
	var/area/best
	var/best_score
	for(var/area_name in GLOB.teleportlocs)
		var/word
		for(var/w in GLOB.bot_hangout_words)
			if(findtext(area_name, w))
				word = w
				break
		if(!word)
			continue
		var/area/A = GLOB.teleportlocs[area_name]
		var/turf/spot = locate(/turf/open) in A
		if(!spot || spot.z != here.z || (locate(/obj/structure/chair) in A) == null)
			continue
		var/score = -get_dist(here, spot) / 10
		if(word == "Bar")
			score += has_habit(BOT_HABIT_BARFLY) ? 6 : 2
		if(word == "Dormitories")
			score += sociability < 0.4 ? 2 : -1 //somewhere quiet
		for(var/mob/living/carbon/human/H in A)
			if(H.stat != CONSCIOUS || H == owner)
				continue
			if(H == with || is_friend(H))
				score += 4
			else if(dislikes(H))
				score -= 8
			else
				score += 0.5
		if(!best || score > best_score)
			best = A
			best_score = score
	return best

/// A seat in the area: next to somebody it likes, or anybody, before an empty spot; never next to somebody it can't stand.
/datum/bot_brain/proc/pick_seat(area/A)
	var/obj/structure/chair/best
	var/best_score
	for(var/obj/structure/chair/C in A)
		if(!C.can_buckle || C.has_buckled_mobs() || !isturf(C.loc) || (locate(/mob/living) in C.loc) || istype(C, /obj/structure/chair/e_chair))
			continue //stools can't be sat on here (can_buckle 0): 208 breaks given up at bar stools in two batches
		var/score = rand(0, 10) / 10
		for(var/mob/living/carbon/human/H in range(2, C))
			if(H == owner || H.stat != CONSCIOUS)
				continue
			if(is_friend(H))
				score += 3
			else if(dislikes(H))
				score -= 6
			else
				score += 1
		if(!best || score > best_score)
			best = C
			best_score = score
	return best

/// Off on a break. TRUE if it set off.
/datum/bot_brain/proc/go_on_break(area/where, mob/living/with)
	where = where || pick_hangout(with)
	if(!where)
		return FALSE
	var/obj/structure/chair/seat = pick_seat(where)
	if(!seat || !can_walk_lawfully_to(seat))
		return FALSE
	var/datum/bot_goal/take_a_break/G = new(seat, where)
	if(!assign_goal(G))
		return FALSE
	bot_tally("breaks")
	bot_log(src, "taking a break in [get_area_name(where, TRUE)][with ? " with [with]" : ""]")
	return TRUE

/// The other half of "Bar after this?" (bot_threads.dm): it goes, and tells its friend where.
/datum/bot_brain/proc/plan_a_break(datum/weakref/friend_ref)
	var/mob/living/carbon/human/friend = friend_ref?.resolve()
	if(!friend?.bot_brain || QDELETED(owner) || owner.stat != CONSCIOUS)
		return
	var/area/where = pick_hangout(friend)
	if(!where)
		return
	friend.bot_brain.break_planned_in = where
	friend.bot_brain.break_planned_until = world.time + 4 MINUTES
	if(state == BOT_STATE_GOAL && current_goal && !current_goal.off_duty && !istype(current_goal, /datum/bot_goal/tag_along))
		break_planned_in = where //after this
		break_planned_until = world.time + 4 MINUTES
		return
	go_on_break(where, friend)

// ---------------------------------------------------------------------------------------------
// The duty
// ---------------------------------------------------------------------------------------------

/datum/bot_duty/take_a_break
	name = "taking a break"
	tier = BOT_DUTY_LEISURE
	interval_min = 6000
	interval_max = 15000

/datum/bot_duty/take_a_break/try_start(datum/bot_brain/bot)
	if(bot.gym_run || !bot.quiet_enough_for_a_break())
		return FALSE
	// A break somebody asked it on
	if(bot.break_planned_in && world.time < bot.break_planned_until)
		var/area/A = bot.break_planned_in
		bot.break_planned_in = null
		return bot.go_on_break(A)
	// Its own: the keen less often, the sociable and anyone out for a social more
	var/chance = 25 + 40 * (1 - bot.diligence) + 20 * bot.sociability + (bot.pursuit == BOT_PURSUIT_SOCIAL ? 30 : 0)
	if(bot.is_security_job() || (bot.work_role() in GLOB.command_positions))
		chance /= 2
	if(!prob(chance))
		return FALSE
	if(!bot.go_on_break())
		return FALSE
	bot.invite_a_friend()
	return TRUE

/// A friend standing about nearby gets asked along, now and then.
/datum/bot_brain/proc/invite_a_friend()
	for(var/mob/living/carbon/human/H in view(7, owner))
		if(H == owner || H.stat != CONSCIOUS || !is_friend(H))
			continue
		var/datum/bot_goal/take_a_break/G = current_goal
		if(!istype(G))
			return
		var/place = get_area_name(G.hangout, TRUE)
		if(!prob(40 + 40 * sociability))
			return
		bot_say(owner, pick("[H.first_name()], break? [place].", "Coming to [place], [H.first_name()]?", "[place]? I need a sit down."))
		var/datum/bot_brain/other = H.bot_brain
		if(other)
			if(other.will_hang_out_with(owner))
				addtimer(CALLBACK(other, TYPE_PROC_REF(/datum/bot_brain, say_after_typing), pick("Sure.", "Go on then.", "Yeah, alright.")), 1)
				other.break_planned_in = G.hangout
				other.break_planned_until = world.time + 3 MINUTES
				addtimer(CALLBACK(other, TYPE_PROC_REF(/datum/bot_brain, join_break)), rand(3 SECONDS, 8 SECONDS))
			else
				addtimer(CALLBACK(other, TYPE_PROC_REF(/datum/bot_brain, say_after_typing), pick("Can't, sorry.", "Maybe later.", "Busy.")), 1)
		return

/// Asked along on a break just now: off it goes, if it's free.
/datum/bot_brain/proc/join_break()
	if(!break_planned_in || world.time > break_planned_until || QDELETED(owner) || owner.stat != CONSCIOUS)
		return
	if(state != BOT_STATE_WANDER || current_goal)
		return //after what it's doing: the duty picks it up
	var/area/A = break_planned_in
	break_planned_in = null
	go_on_break(A)

// ---------------------------------------------------------------------------------------------
// The break
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/take_a_break
	lawful = TRUE
	off_duty = TRUE
	var/obj/structure/chair/seat
	var/area/hangout

/datum/bot_goal/take_a_break/New(obj/structure/chair/seat, area/hangout)
	. = ..()
	src.seat = seat
	src.hangout = hangout
	doing = "on a break"

/datum/bot_goal/take_a_break/resolve_target(datum/bot_brain/bot)
	target = QDELETED(seat) ? null : seat

/datum/bot_goal/take_a_break/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/favour/S = new
	// To the seat's own tile: a walk to the seat itself counts as there from a few tiles off, and the bar stools were never reached
	// (164 breaks given up in batch standin1112c, nearly all at stools)
	var/datum/bot_step/move_to/walk = new
	walk.step_target = get_turf(seat)
	S.steps = list(walk, new /datum/bot_step/sit_down_for_break())
	return list(S)

/// Sits down. The goal's done once it's sat; hangout_until (bot_brain.dm) keeps it there, as at a desk (goals/civilians.dm).
/datum/bot_step/sit_down_for_break/execute(datum/bot_brain/bot)
	var/datum/bot_goal/take_a_break/G = bot.current_goal
	if(!istype(G) || QDELETED(G.seat) || G.seat.has_buckled_mobs())
		return GOAL_STEP_FAIL
	if(get_turf(bot.owner) != get_turf(G.seat) && bot.owner.Adjacent(G.seat)) //the walk can end beside it
		bot.owner.Move(get_turf(G.seat), get_dir(bot.owner, G.seat))
	if(get_turf(bot.owner) != get_turf(G.seat) || !G.seat.user_buckle_mob(bot.owner, bot.owner))
		return GOAL_STEP_FAIL
	bot.break_until = world.time + rand(2 MINUTES, 3 MINUTES) + round((1 - bot.diligence) * 3 MINUTES)
	bot.hangout_until = bot.break_until
	bot.next_chat_time = min(bot.next_chat_time, world.time + rand(10 SECONDS, 30 SECONDS))
	bot.telemetry_event("sit", list("on" = "[G.seat]", "break" = TRUE))
	addtimer(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, order_at_the_bar)), rand(5 SECONDS, 15 SECONDS))
	return GOAL_STEP_SUCCESS

/// At the bar with somebody behind it: a drink, asked for out loud, the way a player orders. The bartender hears it as an order
/// (goals/orders.dm) whether it's a bot or a person.
/datum/bot_brain/proc/order_at_the_bar(certain = FALSE)
	if(QDELETED(owner) || owner.stat != CONSCIOUS || (!certain && !on_break()))
		return FALSE
	if(!certain && (!findtext(get_area_name(owner, TRUE), "Bar") || !prob(40 + 40 * sociability)))
		return FALSE
	var/mob/living/carbon/human/barkeep
	for(var/mob/living/carbon/human/H in view(7, owner))
		if(H != owner && H.stat == CONSCIOUS && H.mind?.assigned_role == "Bartender")
			barkeep = H
			break
	if(!barkeep)
		return FALSE
	var/datum/bot_drink/D = length(GLOB.bot_bar_menu) ? pick(GLOB.bot_bar_menu) : null
	var/what = D ? D.name : pick("a beer", "something strong", "whatever's going")
	say_after_typing(pick("Can I get [D ? "a [what]" : what], [barkeep.first_name()]?", "[barkeep.first_name()], [D ? "a [what]" : what] please.", "One [D ? what : "drink"] over here when you get a sec."))
	var/datum/bot_request_kind/kind = locate(/datum/bot_request_kind/bar_order) in GLOB.bot_request_kinds
	if(kind && barkeep.bot_brain)
		var/datum/bot_request/R = bot_new_request(kind, owner, null, get_turf(owner))
		R.detail = D
		R.only_for = barkeep.bot_brain
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(bot_offer_request), R), rand(10, 25))
	bot_tally("drinks ordered")
	return TRUE
