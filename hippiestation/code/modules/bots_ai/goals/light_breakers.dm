// Lighting breakers: an APC with its lighting switched off. Tired wiring trips a department's at round start
// (station_looks/looks_wiring.dm): its lamps run red off their own cells for ten minutes or so, then go dark. Anybody can
// switch one off too. An engineer who knows goes to each of the room's APCs, swipes its ID, sets Lighting to Auto and locks
// the panel again: the APC window's "channel" action (apc.dm ui_act()), a button a beat.
//
// What it knows is what a player would: the shift notes name the department (everyone gets them as the round starts), and a
// station room it's standing in with its lighting switched off is a room it can see is dark. It doesn't go looking at every
// APC on the station.

/datum/bot_brain
	/// Station areas this bot has stood in with their lighting switched off, area -> TRUE
	var/list/dark_areas_seen
	/// REF(APC) -> world.time it can be tried again, after a give-up (by REF: a ref held here would keep a deconstructed one from deleting)
	var/list/breaker_blocked
	/// find_tripped_apc()'s door to ask the AI at for the APC it found, list(floor, door), for the goal it's handed to straight after
	var/list/breaker_plan
	var/breakers_reset = 0

/// An APC with its lighting switched off at the panel: what an engineer can put right with a click. Off for want of power
/// (1, auto-off) wants the power seen to, not the switch.
/proc/bot_apc_lighting_off(obj/machinery/power/apc/A)
	return !QDELETED(A) && A.lighting == 0 && A.operating && !(A.stat & (BROKEN|MAINT)) && !A.opened && !(A.obj_flags & EMAGGED) && A.cell?.charge > 0

/// The areas the shift notes said have their lighting tripped, as a typecache, or null.
/proc/bot_breaker_areas_in_notes()
	var/datum/station_look/tired_wiring/W = SSstation_looks.looks["tired_wiring"]
	if(!W?.active || !W.department)
		return null
	var/static/list/cached = list()
	if(!cached[W.department])
		cached[W.department] = typecacheof(W.departments[W.department])
	return cached[W.department]

/// The nearest APC this bot knows has its lighting switched off and can walk to, or null.
/datum/bot_brain/proc/find_tripped_apc()
	var/area/here = get_area(owner)
	// A station room it's standing in: it can see the lights are out (maintenance is dim anyway, and not its business here)
	var/sees_here = gym_run || ((here?.type in GLOB.the_station_areas) && !istype(here, /area/maintenance))
	var/list/told = bot_breaker_areas_in_notes()
	var/list/apcs = list() //APC -> how far off
	for(var/obj/machinery/power/apc/A as anything in GLOB.apcs_list)
		if(A.z != owner.z || !bot_apc_lighting_off(A))
			continue
		var/area/room = get_area(A) //where it hangs, which is what anybody goes by (a gym-built APC's own area var is unset)
		if(room == here && sees_here)
			LAZYSET(dark_areas_seen, room, TRUE)
		if(!LAZYACCESS(dark_areas_seen, room) && !(told && is_type_in_typecache(room, told)))
			continue
		if(gym_run && room != here)
			continue
		if(LAZYACCESS(breaker_blocked, REF(A)) > world.time || taken_by_another(A))
			continue
		apcs[A] = get_dist(owner, A)
	var/tries = 0
	while(length(apcs) && tries++ < 3)
		var/obj/machinery/power/apc/nearest
		for(var/obj/machinery/power/apc/A as anything in apcs)
			if(!nearest || apcs[A] < apcs[nearest])
				nearest = A
		apcs -= nearest
		// The door to ask the AI at, worked out whether or not the walk looks open: a route can count a door somebody else had open, or
		// an exit button meant for inside, and Research's front door stopped every engineer that way
		var/list/door_plan = breaker_doorstep(nearest)
		if(door_plan || can_walk_lawfully_to(nearest))
			breaker_plan = door_plan
			return nearest
		LAZYSET(breaker_blocked, REF(nearest), world.time + 10 MINUTES)
	return null

/// Where to ask the AI to open up from, for an APC behind doors this bot's ID doesn't open (an engineer's doesn't open Science, Cargo,
/// Medbay or the Bar): list(the floor outside, the door), or null with no AI about to ask or no such door it can get to. The APC's own
/// room's door first, which gets it right up to the APC; then any door into its department from outside it. The nearest to the APC
/// first, six tried at most: the nearest few are often doors between the department's own rooms, or from somewhere else locked.
/datum/bot_brain/proc/breaker_doorstep(obj/machinery/power/apc/A)
	if(!bot_ai_awake())
		return null
	var/area/room = get_area(A)
	var/department = bot_department_of(room)
	var/list/room_spots = list() //floor outside -> list(door, how far the door is from the APC)
	var/list/department_spots = list()
	for(var/obj/machinery/door/airlock/D as anything in bot_instances_of(/obj/machinery/door/airlock))
		if(QDELETED(D) || D.z != A.z || istype(D, /obj/machinery/door/airlock/external) || get_dist(D, A) > 40)
			continue
		var/area/door_area = get_area(D)
		var/into_room = door_area == room
		if(!into_room && (!department || bot_department_of(door_area) != department))
			continue
		for(var/direction in GLOB.cardinals)
			var/turf/T = get_step(D, direction)
			if(!isopenturf(T) || is_blocked_turf(T, TRUE))
				continue
			var/area/outside = get_area(T)
			if(outside == room || (department && bot_department_of(outside) == department))
				continue
			if(into_room)
				room_spots[T] = list(D, get_dist(D, A))
			else
				department_spots[T] = list(D, get_dist(D, A))
	var/tries = 0
	for(var/list/spots in list(room_spots, department_spots))
		while(length(spots) && tries < 6)
			var/turf/nearest
			for(var/turf/T as anything in spots)
				if(!nearest || spots[T][2] < spots[nearest][2])
					nearest = T
			var/obj/machinery/door/airlock/D = spots[nearest][1]
			spots -= nearest
			tries++
			if(can_walk_lawfully_to(nearest))
				return list(nearest, D)
	return null

/// An AI up and running to ask for a door.
/proc/bot_ai_awake()
	for(var/mob/living/silicon/ai/AI as anything in GLOB.ai_list)
		if(AI.stat != DEAD && !AI.control_disabled)
			return TRUE
	return FALSE

/datum/bot_duty/light_breakers
	name = "tripped lighting"
	jobs = list("Station Engineer", "Chief Engineer")
	interval_min = 300
	interval_max = 900
	priority = 5

/datum/bot_duty/light_breakers/try_start(datum/bot_brain/bot)
	var/obj/machinery/power/apc/A = bot.find_tripped_apc()
	var/list/plan = bot.breaker_plan
	bot.breaker_plan = null
	return A ? bot.assign_goal(new /datum/bot_goal/reset_light_breaker(A, plan)) : FALSE

/datum/bot_goal/reset_light_breaker
	lawful = TRUE
	exclusive = TRUE
	doing = "putting the lights back on"
	/// Where to stand to ask the AI to open up, and the door: null if there's no asking to be done
	var/turf/door_step
	var/datum/weakref/door_ref

/datum/bot_goal/reset_light_breaker/New(obj/machinery/power/apc/A, list/plan)
	. = ..()
	target = A
	if(length(plan) == 2)
		door_step = plan[1]
		door_ref = WEAKREF(plan[2])

/datum/bot_goal/reset_light_breaker/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target))
		target = null

/datum/bot_goal/reset_light_breaker/get_strategies(datum/bot_brain/bot)
	. = list()
	// Straight there, if its ID opens the way
	if(target && bot.can_walk_lawfully_to(target))
		var/datum/bot_strategy/light_breaker/S = new
		S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/reset_light_breaker())
		. += S
	// Behind doors it doesn't open, or the way in turned out shut when it got there: to the door, and the AI is asked to open it, as
	// a player asks
	if(door_step && door_ref?.resolve())
		var/datum/bot_strategy/light_breaker/S = new
		var/datum/bot_step/move_to/to_door = new
		to_door.step_target = door_step
		S.steps = list(to_door, new /datum/bot_step/paced/ask_ai_to_open(), new /datum/bot_step/move_to(), new /datum/bot_step/paced/reset_light_breaker())
		. += S

/// At a door its ID doesn't open: asks the AI over the radio, with what it's for, and waits for that door to open. Twice at most, a
/// little apart, then it gives the job up for now.
/datum/bot_step/paced/ask_ai_to_open
	max_clicks = 4
	var/until = 0
	var/asked_at = -INFINITY
	var/asks = 0

/datum/bot_step/paced/ask_ai_to_open/start(datum/bot_brain/bot)
	until = world.time + 70 SECONDS
	asked_at = -INFINITY
	asks = 0
	return TRUE

/// The door it's asking at, or null
/datum/bot_step/paced/ask_ai_to_open/proc/door(datum/bot_brain/bot)
	var/datum/bot_goal/reset_light_breaker/G = bot.current_goal
	return istype(G) ? G.door_ref?.resolve() : null

/datum/bot_step/paced/ask_ai_to_open/do_click(datum/bot_brain/bot)
	var/obj/machinery/door/airlock/D = door(bot)
	if(world.time > until || !D || QDELETED(D) || !D.density)
		return FALSE //open: in (another door near it, the one it came through, doesn't count)
	if(asks < 2 && world.time > asked_at + 30 SECONDS)
		asked_at = world.time
		asks++
		var/area/room = get_area(bot.current_goal?.target)
		bot.say_after_typing(pick(
			";AI, open this door please, I need to fix the lighting in [room?.name || "there"].",
			";AI, door please. Engineering, here to fix the lights in [room?.name || "there"].",
			";AI, could you open up for me? I'm here to fix [room?.name || "the"] lighting."))
	wait_for = 10
	return TRUE

/datum/bot_step/paced/ask_ai_to_open/finish(datum/bot_brain/bot)
	var/obj/machinery/door/airlock/D = door(bot)
	if(D && !QDELETED(D) && !D.density)
		bot_log(bot, "[D] opened for it: in to [bot.current_goal?.target]")
		return GOAL_STEP_SUCCESS
	bot_log(bot, "asked the AI to open [D || "the door"] for [bot.current_goal?.target] and nobody did")
	return GOAL_STEP_FAIL

/datum/bot_goal/reset_light_breaker/on_success(datum/bot_brain/bot)
	// The department has more than one APC as a rule: on to the next while it's here
	bot.continue_goal_chain(CALLBACK(bot_duty_of(/datum/bot_duty/light_breakers), TYPE_PROC_REF(/datum/bot_duty, try_start), bot))

/datum/bot_goal/reset_light_breaker/on_give_up(datum/bot_brain/bot)
	if(target)
		LAZYSET(bot.breaker_blocked, REF(target), world.time + 10 MINUTES)

/datum/bot_strategy/light_breaker/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// At the APC: ID swipe (interface unlocked), Lighting to Auto, ID swipe (locked again). An APC already unlocked is left as found.
/datum/bot_step/paced/reset_light_breaker
	max_clicks = 4
	/// It was locked when the bot got there, so it's locked again after
	var/unlocked_it = FALSE
	var/set_it = FALSE

/datum/bot_step/paced/reset_light_breaker/start(datum/bot_brain/bot)
	unlocked_it = FALSE
	set_it = FALSE
	return bot.owner.Adjacent(bot.current_goal?.target)

/datum/bot_step/paced/reset_light_breaker/do_click(datum/bot_brain/bot)
	var/obj/machinery/power/apc/A = bot.current_goal?.target
	if(!istype(A) || QDELETED(A) || !bot.owner.Adjacent(A))
		return FALSE
	bot.human_pause(A)
	if(QDELETED(A) || !bot.owner.Adjacent(A))
		return FALSE
	if(!set_it)
		if(!bot_apc_lighting_off(A))
			set_it = TRUE //someone else got there first
			return unlocked_it
		if(A.locked)
			if(unlocked_it)
				return FALSE //swiped and still locked: no access
			usr = bot.owner
			bot.telemetry_ui_action(A, "swipe ID")
			A.togglelock(bot.owner)
			unlocked_it = !A.locked
			return unlocked_it
		bot.telemetry_ui_action(A, "lighting auto")
		A.lighting = A.setsubsystem(3)
		A.update_icon()
		A.update()
		set_it = TRUE
		return TRUE
	if(unlocked_it && !A.locked)
		usr = bot.owner
		bot.telemetry_ui_action(A, "swipe ID")
		A.togglelock(bot.owner)
	return FALSE

/datum/bot_step/paced/reset_light_breaker/finish(datum/bot_brain/bot)
	var/obj/machinery/power/apc/A = bot.current_goal?.target
	if(!istype(A) || QDELETED(A) || A.lighting < 2)
		return GOAL_STEP_FAIL
	bot.breakers_reset++
	bot_log(bot, "set the lighting back to auto at [A] in [get_area_name(A, TRUE)]")
	return GOAL_STEP_SUCCESS
