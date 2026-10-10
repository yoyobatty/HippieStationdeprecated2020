// Evacuation: what the whole crew does when the emergency shuttle is called.
//
// Nobody downs tools the moment it's called - people finish what they're on and drift towards
// departures as it gets close, each in their own time (evac_lead). Once it docks, everybody who isn't
// in the middle of saving a life drops what they're doing, boards, and takes a seat; they stay sat
// until it's over. A recall sends them back to work.
//
// The game sends its shuttle announcements straight to players' chat windows, which a bot hasn't got,
// so a bot reads the shuttle's state off the shuttle itself each time this duty comes round - and now
// and then says something about it, as people do.

/// How many bots have remarked on the shuttle's current state, so the whole crew doesn't chorus.
GLOBAL_VAR_INIT(bot_shuttle_remarks, 0)
GLOBAL_VAR(bot_shuttle_remark_mode)
/// Shuttle seat -> the brain of the bot walking to it.
GLOBAL_LIST_EMPTY(bot_seat_claims)

/datum/bot_brain
	/// How long before the shuttle arrives this bot sets off for departures, in deciseconds.
	var/evac_lead = 0
	/// The shuttle state this bot last took in (SHUTTLE_CALL...), for noticing when it changes.
	var/evac_seen_mode
	/// Times in a row it has set off for a seat and not got there - after a few it stands where it is.
	var/evac_board_failures = 0
	/// The seats those were.
	var/list/evac_failed_seats

/proc/bot_shuttle_boarding()
	var/obj/docking_port/mobile/emergency/E = SSshuttle.emergency
	return E && (E.mode == SHUTTLE_DOCKED || E.mode == SHUTTLE_IGNITING)

/proc/bot_aboard_shuttle(atom/A)
	var/obj/docking_port/mobile/emergency/E = SSshuttle.emergency
	return E?.shuttle_areas && E.shuttle_areas[get_area(A)]

/// Whether A is aboard the evacuation shuttle at a point where it stays aboard: docked and boarding, or under way.
/proc/bot_staying_aboard(atom/A)
	var/obj/docking_port/mobile/emergency/E = SSshuttle.emergency
	if(!E || !bot_aboard_shuttle(A))
		return FALSE
	return E.mode == SHUTTLE_DOCKED || E.mode == SHUTTLE_IGNITING || E.mode == SHUTTLE_ESCAPE || E.mode == SHUTTLE_ENDGAME

/proc/bot_in_departures(atom/A)
	return istype(get_area(A), /area/hallway/secondary/exit)

/datum/bot_duty/evacuate
	name = "evacuation"
	tier = BOT_DUTY_URGENT
	priority = 100
	interval_min = 30
	interval_max = 80
	interrupts = TRUE

/// Whether it's time this bot was on its way: the shuttle is in, or close enough for this one to set off.
/datum/bot_duty/evacuate/proc/time_to_go(datum/bot_brain/bot)
	var/obj/docking_port/mobile/emergency/E = SSshuttle.emergency
	if(!E)
		return FALSE
	if(E.mode == SHUTTLE_DOCKED || E.mode == SHUTTLE_IGNITING)
		return TRUE
	if(E.mode != SHUTTLE_CALL)
		return FALSE
	if(!bot.evac_lead)
		// Heads and security see everyone else off first.
		var/role = bot.owner.mind?.assigned_role
		var/last_out = (role in GLOB.command_positions) || (role in GLOB.security_positions)
		bot.evac_lead = last_out ? rand(450, 900) : rand(900, 2400)
	return E.timeLeft(1) <= bot.evac_lead

/datum/bot_duty/evacuate/try_start(datum/bot_brain/bot)
	var/obj/docking_port/mobile/emergency/E = SSshuttle.emergency
	if(!E)
		return FALSE
	bot.notice_shuttle(E.mode)
	if(bot_aboard_shuttle(bot.owner))
		if(!keep_holding(bot))
			return FALSE
		bot.holding_duty = src
		// Aboard but on its feet: sit down if there's a seat to be had, and at the very least get clear of the doors.
		if(!bot.owner.buckled)
			var/stuck_by_the_door = !bot.safe_standing_aboard()
			if(stuck_by_the_door || (bot.evac_board_failures < 3 && bot.pick_shuttle_seat()))
				return bot.assign_goal(new /datum/bot_goal/evacuate/board())
		return TRUE
	if(!time_to_go(bot))
		return FALSE
	if(bot_shuttle_boarding())
		return bot.assign_goal(new /datum/bot_goal/evacuate/board())
	if(bot_in_departures(bot.owner))
		bot.holding_duty = src
		return TRUE
	return bot.assign_goal(new /datum/bot_goal/evacuate/go_to_departures())

/datum/bot_duty/evacuate/should_interrupt(datum/bot_brain/bot)
	if(istype(bot.current_goal, /datum/bot_goal/evacuate) || bot_aboard_shuttle(bot.owner) || !time_to_go(bot))
		return FALSE
	// Someone's life or liberty in hand: seen through, until the shuttle is nearly gone.
	var/datum/bot_goal/G = bot.suspended_goal || bot.current_goal
	if(istype(G, /datum/bot_goal/revive_patient) || istype(G, /datum/bot_goal/escort_to_sleeper) || istype(G, /datum/bot_goal/brig_prisoner))
		var/obj/docking_port/mobile/emergency/E = SSshuttle.emergency
		return bot_shuttle_boarding() && E.timeLeft(1) <= 900
	return bot_shuttle_boarding() || !bot_in_departures(bot.owner)

/// Waiting at departures while the shuttle is on its way; staying aboard once on it.
/datum/bot_duty/evacuate/keep_holding(datum/bot_brain/bot)
	var/obj/docking_port/mobile/emergency/E = SSshuttle.emergency
	if(!E)
		return FALSE
	if(bot_aboard_shuttle(bot.owner))
		return E.mode == SHUTTLE_DOCKED || E.mode == SHUTTLE_IGNITING || E.mode == SHUTTLE_ESCAPE || E.mode == SHUTTLE_ENDGAME
	return E.mode == SHUTTLE_CALL && bot_in_departures(bot.owner)

/// Takes in what the shuttle is doing, and now and then says something about it.
/datum/bot_brain/proc/notice_shuttle(mode)
	if(mode == evac_seen_mode)
		return
	var/first_look = isnull(evac_seen_mode)
	evac_seen_mode = mode
	if(first_look || gym_scripted)
		return
	if(GLOB.bot_shuttle_remark_mode != mode)
		GLOB.bot_shuttle_remark_mode = mode
		GLOB.bot_shuttle_remarks = 0
	var/list/lines
	switch(mode)
		if(SHUTTLE_CALL)
			lines = list("Shuttle's been called.", "Evacuating already?", "About time we got out of here.", "Guess that's the shift, then.", "Wonder what set that off.")
		if(SHUTTLE_RECALL)
			lines = list("Recalled? Seriously?", "Back to work, I suppose.", "Make your minds up.")
		if(SHUTTLE_DOCKED)
			lines = list("Shuttle's here.", "Time to go.", "That's our ride.", "Right, I'm off.")
	if(lines && GLOB.bot_shuttle_remarks < 3 && prob(15 + 40 * sociability))
		GLOB.bot_shuttle_remarks++
		say_after_typing(pick(lines))

// ---------------------------------------------------------------------------------------------
// Where to go
// ---------------------------------------------------------------------------------------------

/// Somewhere to wait in the departures hallway: a free chair if there is one, otherwise a clear bit of floor.
/datum/bot_brain/proc/pick_departures_spot()
	var/area/departures = GLOB.areas_by_type[/area/hallway/secondary/exit]
	if(!departures)
		return null
	var/list/floor = list()
	var/list/seats = list()
	for(var/turf/open/T in departures)
		if(T.z != owner.z || !is_wanderable_turf(T) || (locate(/obj/machinery/door) in T) || (locate(/mob/living) in T))
			continue
		var/obj/structure/chair/C = locate() in T
		if(C && !C.has_buckled_mobs())
			seats += T
		else if(!C)
			floor += T
	if(length(seats) && prob(60))
		return pick(seats)
	return length(floor) ? pick(floor) : (length(seats) ? pick(seats) : null)

/// The shuttle floor that can actually be walked to, as turf -> steps in from the door (or from the bot, if it's
/// aboard already). Somebody sat down fills their tile and the route planner doesn't know it: the first bots aboard
/// used to take the seats by the door, and one that couldn't get past them stood in the doorway until the shuttle
/// left and threw it out into space.
/datum/bot_brain/proc/shuttle_floor_in_reach()
	var/list/steps = list()
	var/obj/docking_port/mobile/emergency/E = SSshuttle.emergency
	if(!E?.shuttle_areas)
		return steps
	var/list/queue = list()
	var/turf/here = get_turf(owner)
	if(E.shuttle_areas[here.loc])
		queue += here
	else
		// Not aboard yet: in through whichever of the shuttle's airlocks open onto the station.
		for(var/area/A as anything in E.shuttle_areas)
			for(var/obj/machinery/door/airlock/D in A)
				if(D.locked || D.welded || !D.allowed(owner))
					continue //the cell's own airlock: not this bot's way in, even stood open
				var/turf/doorway = get_turf(D)
				for(var/d in GLOB.cardinals)
					var/turf/open/outside = get_step(doorway, d)
					if(istype(outside) && !isspaceturf(outside) && !E.shuttle_areas[outside.loc])
						queue |= doorway
						break
	for(var/turf/T as anything in queue)
		steps[T] = 0
	var/at = 1
	while(at <= length(queue))
		var/turf/T = queue[at++]
		for(var/d in GLOB.cardinals)
			var/turf/open/next = get_step(T, d)
			if(!istype(next) || !isnull(steps[next]) || !E.shuttle_areas[next.loc] || shuttle_tile_blocked(next))
				continue
			steps[next] = steps[T] + 1
			queue += next
	return steps

/// A shuttle tile there's no walking through: furniture, machinery, someone sat down or laid out on it - or a door
/// this bot's ID doesn't open (the cockpit, the cell).
/datum/bot_brain/proc/shuttle_tile_blocked(turf/T)
	for(var/atom/movable/AM in T)
		if(AM == owner)
			continue
		if(isliving(AM))
			var/mob/living/L = AM
			if(L.buckled || L.stat != CONSCIOUS)
				return TRUE
		else if(istype(AM, /obj/machinery/door))
			var/obj/machinery/door/D = AM
			if(D.density && (D.locked || D.welded || !D.allowed(owner)))
				return TRUE
		else if(AM.density)
			return TRUE
	return FALSE

/// A shuttle seat nobody has that this bot can get to - not one of the cell's, which would count it as a prisoner.
/// The furthest in that's free, give or take, so the seats by the door are the last to go and nobody has to climb
/// over anybody.
/datum/bot_brain/proc/pick_shuttle_seat()
	var/obj/docking_port/mobile/emergency/E = SSshuttle.emergency
	if(!E?.shuttle_areas)
		return null
	var/list/steps = shuttle_floor_in_reach()
	var/list/seats = list()
	var/deepest = 0
	for(var/area/A as anything in E.shuttle_areas)
		for(var/obj/structure/chair/C in A)
			var/turf/T = get_turf(C)
			if(!T || isnull(steps[T]) || C.has_buckled_mobs() || istype(T, /turf/open/floor/mineral/plastitanium/red/brig))
				continue
			if(C in evac_failed_seats)
				continue //set off for it once and didn't get there
			var/datum/bot_brain/claimant = GLOB.bot_seat_claims[C]
			if(claimant && claimant != src && !QDELETED(claimant) && !QDELETED(claimant.owner) && claimant.owner.stat == CONSCIOUS)
				continue
			seats[C] = steps[T]
			deepest = max(deepest, steps[T])
	var/list/far_end = list()
	for(var/obj/structure/chair/C as anything in seats)
		if(seats[C] >= deepest - 3)
			far_end += C
	return length(far_end) ? pick(far_end) : null

/// Standing room aboard, for when the seats have gone: well inside, and not in or beside a doorway.
/datum/bot_brain/proc/pick_shuttle_floor()
	var/list/steps = shuttle_floor_in_reach()
	var/turf/best
	for(var/turf/open/T as anything in steps)
		if(istype(T, /turf/open/floor/mineral/plastitanium/red/brig) || (locate(/obj/structure/chair) in T) || (locate(/mob/living) in (T.contents - owner)))
			continue
		if(locate(/obj/machinery/door) in range(1, T))
			continue
		if(!best || steps[T] > steps[best])
			best = T
	return best

/// Whether the bot is stood somewhere aboard it can stay for the flight: clear of the doors.
/datum/bot_brain/proc/safe_standing_aboard()
	return bot_aboard_shuttle(owner) && !(locate(/obj/machinery/door) in range(1, get_turf(owner)))

// ---------------------------------------------------------------------------------------------
// The goals
// ---------------------------------------------------------------------------------------------

// Not `lawful`: a bot gets to the shuttle by the proper route if there is one, and through whatever is in the way
// if there isn't. One that had ended up somewhere its ID doesn't open (a doctor in the kitchen, after a beaker)
// used to be left behind for want of a door it was allowed through.
/datum/bot_goal/evacuate
	doing = "heading for the shuttle"
	/// The chair this bot means to sit on when it gets there, if any.
	var/obj/structure/chair/seat

/datum/bot_goal/evacuate/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/evacuate/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/settle_for_shuttle())
	return list(S)

/datum/bot_goal/evacuate/proc/release_seat(datum/bot_brain/bot)
	if(seat && GLOB.bot_seat_claims[seat] == bot)
		GLOB.bot_seat_claims -= seat

/datum/bot_goal/evacuate/on_success(datum/bot_brain/bot)
	release_seat(bot)
	bot.evac_board_failures = 0

/datum/bot_goal/evacuate/on_give_up(datum/bot_brain/bot)
	release_seat(bot)
	bot.evac_board_failures++
	// No way to the shuttle from in here: somebody with the right ID might get the door (bot_requests.dm).
	bot.next_call_time = min(bot.next_call_time, world.time)
	bot.maybe_ask_to_be_let_out()
	if(seat)
		LAZYOR(bot.evac_failed_seats, seat)

/datum/bot_strategy/evacuate
	max_attempts = 2

/datum/bot_strategy/evacuate/is_feasible(datum/bot_brain/bot)
	return TRUE

/datum/bot_goal/evacuate/go_to_departures/resolve_target(datum/bot_brain/bot)
	target = bot.pick_departures_spot()
	if(target)
		seat = locate(/obj/structure/chair) in target
		bot_log(bot, "shuttle's nearly here - heading to departures")

/datum/bot_goal/evacuate/board/resolve_target(datum/bot_brain/bot)
	seat = bot.pick_shuttle_seat()
	if(seat)
		GLOB.bot_seat_claims[seat] = bot
		target = get_turf(seat)
	else
		target = bot.pick_shuttle_floor()
	if(target)
		bot_log(bot, "boarding the shuttle[seat ? "" : " - standing room only"]")

/// Arrived: sit down if the seat's still free, and wait there (the evacuation duty decides for how long).
/datum/bot_step/settle_for_shuttle/execute(datum/bot_brain/bot)
	var/datum/bot_goal/evacuate/G = bot.current_goal
	var/obj/structure/chair/seat = istype(G) ? G.seat : null
	if(seat && !QDELETED(seat) && !seat.has_buckled_mobs() && get_turf(bot.owner) == get_turf(seat) && !bot.owner.buckled)
		bot.human_pause(seat)
		if(!QDELETED(seat) && !seat.has_buckled_mobs() && get_turf(bot.owner) == get_turf(seat))
			bot.telemetry_event("sit", list("on" = "[seat]"))
			if(seat.user_buckle_mob(bot.owner, bot.owner))
				bot.hangout_until = world.time + 1 HOURS
	bot.holding_duty = bot_duty_of(/datum/bot_duty/evacuate)
	return GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// Whoever is in the cells
// ---------------------------------------------------------------------------------------------

// Nobody gets left in a cell when the station is evacuated. Once the shuttle is on its way, an officer with
// nothing more pressing goes round the brig timers that are still running and ends each sentence at the timer
// (door_timer/timer_end(), what its Stop button does) - the cell opens, and whoever is inside has a shuttle to
// catch like everybody else.

/// A brig timer that's still running, the nearest this bot can walk to.
/datum/bot_brain/proc/find_running_brig_timer()
	var/obj/machinery/door_timer/best
	var/best_dist
	for(var/obj/machinery/door_timer/T as anything in bot_instances_of(/obj/machinery/door_timer))
		if(QDELETED(T) || T.z != owner.z || !T.timing || (T.stat & (NOPOWER|BROKEN)) || taken_by_another(T))
			continue
		if(gym_run && get_area(T) != get_area(owner))
			continue
		var/dist = get_dist(owner, T)
		if(!best || dist < best_dist)
			best = T
			best_dist = dist
	return (best && can_walk_lawfully_to(best)) ? best : null

// Switched off: it has never been run. It needs somebody in a cell while the shuttle is on its way, which no Bot
// Shift has produced yet, and the Bot Gym can't call the emergency shuttle without every other scenario seeing it.
// Until then prisoners are left in their cells at an evacuation, as they were before.
/datum/bot_duty/release_prisoners
	name = "letting the cells out"
	enabled = FALSE
	tier = BOT_DUTY_URGENT
	priority = 110 //ahead of the officer's own walk to departures
	interval_min = 100
	interval_max = 200

/datum/bot_duty/release_prisoners/applies_to(datum/bot_brain/bot)
	return bot.is_security_job()

/datum/bot_duty/release_prisoners/try_start(datum/bot_brain/bot)
	var/obj/docking_port/mobile/emergency/E = SSshuttle.emergency
	if(!E || !(E.mode == SHUTTLE_CALL || E.mode == SHUTTLE_DOCKED) || bot_aboard_shuttle(bot.owner))
		return FALSE
	if(E.mode == SHUTTLE_DOCKED && E.timeLeft(1) < 600)
		return FALSE //too late to go back for anybody
	var/obj/machinery/door_timer/T = bot.find_running_brig_timer()
	return T ? bot.assign_goal(new /datum/bot_goal/release_prisoner(T)) : FALSE

/datum/bot_goal/release_prisoner
	lawful = TRUE
	exclusive = TRUE
	doing = "letting the cells out for the evacuation"

/datum/bot_goal/release_prisoner/New(obj/machinery/door_timer/T)
	. = ..()
	target = T

/datum/bot_goal/release_prisoner/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target))
		target = null

/datum/bot_goal/release_prisoner/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/release_prisoner/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/stop_brig_timer())
	return list(S)

/datum/bot_strategy/release_prisoner/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/datum/bot_step/stop_brig_timer/execute(datum/bot_brain/bot)
	var/obj/machinery/door_timer/T = bot.current_goal?.target
	if(!istype(T) || QDELETED(T) || !bot.owner.Adjacent(T))
		return GOAL_STEP_FAIL
	if(!T.timing)
		return GOAL_STEP_SUCCESS //run out, or somebody else got to it
	bot.human_pause(T)
	if(QDELETED(T) || !bot.owner.Adjacent(T) || !T.allowed(bot.owner))
		return GOAL_STEP_FAIL
	bot.owner.face_atom(T)
	bot.telemetry_ui_action(T, "stop")
	T.timer_end(forced = TRUE)
	bot_log(bot, "ended the sentence in [T] - everybody out for the shuttle")
	if(!bot.gym_scripted)
		bot_say(bot.owner, pick("Shuttle's coming - out you come, get to departures.", "Sentence is over. Evacuation - go.", "You're free to go. Don't miss the shuttle."))
	return GOAL_STEP_SUCCESS
