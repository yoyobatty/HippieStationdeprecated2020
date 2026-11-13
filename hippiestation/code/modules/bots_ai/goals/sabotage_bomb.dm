// A maxcap in Security or on the Bridge (goals/sabotage.dm): a traitor scientist makes the toxins lab's bomb as it always does
// (goals/toxins.dm), at the server's cap, but puts a timer on it rather than a dead man's switch, keeps it, and leaves it ticking in
// Security or on the Bridge with a minute on the clock.
//
// And the crew's side, for anybody's bomb: a tank bomb with its timer running, lying where somebody can see it, isn't left. Somebody
// with the nerve for it (Security, or an engineer who's steady) goes and takes the timer off, which is what stops one (the valve's
// "Remove" for the device, transfer_valve.dm); everybody else shouts, calls it in, and gets well away.

/// How long a saboteur's bomb is set for: time to be well clear of a maxcap.
#define BOT_BOMB_FUSE 60
/// Below this many seconds left, nobody walks up to one.
#define BOT_BOMB_TOO_LATE 6
/// How long a saboteur waits for the lab to come up with one before trying something else.
#define BOT_MAXCAP_PATIENCE (25 MINUTES)

/// Tank bombs with a timer running, lying somewhere: -> TRUE. Fed by the timers themselves (timer process()).
GLOBAL_LIST_EMPTY(bot_ticking_bombs)

/datum/bot_brain
	/// A saboteur scientist: the toxins lab's next bomb is for Security.
	var/wants_maxcap = FALSE
	var/maxcap_wanted_at = 0
	var/next_bomb_look = 0

/// The bomb it's carrying with a timer on it, ready.
/datum/bot_brain/proc/carried_timer_bomb()
	for(var/obj/item/transfer_valve/V in owner.GetAllContents(/obj/item/transfer_valve))
		if(V.tank_one && V.tank_two && istype(V.attached_device, /obj/item/assembly/timer))
			return V
	if(armed_bomb && istype(armed_bomb.attached_device, /obj/item/assembly/timer) && isturf(armed_bomb.loc) && get_dist(owner, armed_bomb) <= 7)
		return armed_bomb
	return null

/datum/bot_sabotage/maxcap
	id = "maxcap"
	name = "a bomb in Security or on the Bridge"

/datum/bot_sabotage/maxcap/weight(datum/bot_brain/bot)
	if(bot.carried_timer_bomb())
		return 10
	if(!(bot.work_role() in list("Scientist", "Research Director")))
		return 0
	if(GLOB.bot_toxins?.finished && !bot.wants_maxcap)
		return 0 //the lab's made its bomb for the round
	if(bot.wants_maxcap && world.time > bot.maxcap_wanted_at + BOT_MAXCAP_PATIENCE)
		return 0
	return 5

/datum/bot_sabotage/maxcap/start(datum/bot_brain/bot)
	var/obj/item/transfer_valve/V = bot.carried_timer_bomb()
	if(V)
		var/turf/spot = bot.bomb_spot()
		return spot ? bot.assign_goal(new /datum/bot_goal/sabotage_plant_bomb(V, spot, src)) : FALSE
	if(!bot.wants_maxcap)
		bot.wants_maxcap = TRUE
		bot.maxcap_wanted_at = world.time
		bot_log(bot, "SABOTAGE: the lab's next bomb gets a timer, and it's going to Security")
	bot.sabotage_underway = src //the toxins duty makes it (goals/toxins.dm): back here once it's on the valve
	return FALSE

/// A bit of floor on the Bridge or in Security's office, whichever it can get to, out of the doorway.
/datum/bot_brain/proc/bomb_spot()
	if(gym_sabotage_spot)
		return gym_sabotage_spot
	if(apex_strike) //apex/kill_planner.dm: out to kill everybody, it goes where everybody is
		var/turf/crowd = sabotage_crowd_spot()
		if(crowd)
			return crowd
	var/list/rooms = shuffle(list(/area/bridge, /area/security/main, /area/security/brig))
	for(var/room_type in rooms)
		var/list/floors = list()
		for(var/area/A in GLOB.sortedAreas)
			if(!istype(A, room_type) || A.z != owner.z)
				continue
			for(var/turf/open/floor/T in A)
				if(!is_blocked_turf(T, TRUE) && !(locate(/obj/machinery/door) in T))
					floors += T
		var/tries = 0
		while(length(floors) && tries++ < 4)
			var/turf/T = pick_n_take(floors)
			if(get_dist(owner, T) <= 120)
				return T
	return null

/datum/bot_goal/sabotage_plant_bomb
	doing = "dropping something off"
	breaks_in = TRUE
	var/obj/item/transfer_valve/bomb
	var/turf/spot
	var/datum/bot_sabotage/act

/datum/bot_goal/sabotage_plant_bomb/New(obj/item/transfer_valve/V, turf/T, datum/bot_sabotage/A)
	. = ..()
	bomb = V
	spot = T
	act = A

/datum/bot_goal/sabotage_plant_bomb/resolve_target(datum/bot_brain/bot)
	if(!QDELETED(bomb) && spot)
		target = spot

/datum/bot_goal/sabotage_plant_bomb/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/sabotage/S = new
	S.steps = list(new /datum/bot_step/fetch_bomb(src), new /datum/bot_step/move_to(), new /datum/bot_step/paced/sabotage_set_bomb(src))
	return list(S)

/datum/bot_goal/sabotage_plant_bomb/on_success(datum/bot_brain/bot)
	bot.armed_bomb = null //it's meant to be left there now (toxins.dm mind_armed_bomb())
	bot.wants_maxcap = FALSE
	bot.sabotage_finished(act, get_area_name(spot, TRUE))
	bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, run_from), bomb || spot, "a bomb going off"))

/// In its hands, if it's been put down.
/datum/bot_step/fetch_bomb
	var/datum/bot_goal/sabotage_plant_bomb/goal

/datum/bot_step/fetch_bomb/New(datum/bot_goal/sabotage_plant_bomb/G)
	. = ..()
	goal = G

/datum/bot_step/fetch_bomb/execute(datum/bot_brain/bot)
	var/obj/item/transfer_valve/V = goal.bomb
	if(QDELETED(V))
		return GOAL_STEP_FAIL
	if(bot.is_carried(V))
		return GOAL_STEP_SUCCESS
	if(isturf(V.loc) && bot.suspend_goal_for(new /datum/bot_goal/take_item/exact(V)))
		return GOAL_STEP_PENDING
	return GOAL_STEP_FAIL

/// Nobody looking, it goes down and the timer starts.
/datum/bot_step/paced/sabotage_set_bomb
	max_clicks = 40
	var/datum/bot_goal/sabotage_plant_bomb/goal
	var/waiting_since = 0
	var/set_it = FALSE

/datum/bot_step/paced/sabotage_set_bomb/New(datum/bot_goal/sabotage_plant_bomb/G)
	. = ..()
	goal = G

/datum/bot_step/paced/sabotage_set_bomb/start(datum/bot_brain/bot)
	waiting_since = world.time
	return TRUE

/datum/bot_step/paced/sabotage_set_bomb/do_click(datum/bot_brain/bot)
	var/obj/item/transfer_valve/V = goal.bomb
	if(set_it || QDELETED(V) || !bot.is_carried(V))
		return FALSE
	if(!bot.sabotage_unwatched(waiting_since))
		wait_for = 10
		return TRUE
	if(!bot.ready_in_hand(V))
		return FALSE
	var/obj/item/assembly/timer/T = V.attached_device
	if(!istype(T))
		return FALSE
	bot.human_pause(V)
	if(!T.secured)
		T.toggle_secure()
	T.time = BOT_BOMB_FUSE
	T.timing = TRUE
	T.update_icon()
	bot.owner.dropItemToGround(V)
	set_it = TRUE
	bot_log(bot, "SABOTAGE: left [V] in [get_area_name(V, TRUE)] with [BOT_BOMB_FUSE] seconds on the timer")
	log_game("BOT SABOTAGE: [key_name(bot.owner)] set a tank bomb ([BOT_BOMB_FUSE]s) at [AREACOORD(V)]")
	message_admins("BOT SABOTAGE: [ADMIN_LOOKUPFLW(bot.owner)] set a tank bomb ([BOT_BOMB_FUSE]s) at [ADMIN_VERBOSEJMP(V)]")
	bot_witness_sabotage(bot.owner, "left a bomb")
	return FALSE

/datum/bot_step/paced/sabotage_set_bomb/finish(datum/bot_brain/bot)
	return set_it ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// The crew's side: a ticking bomb
// ---------------------------------------------------------------------------------------------

/obj/item/assembly/timer/process()
	. = ..()
	if(timing && istype(loc, /obj/item/transfer_valve) && length(GLOB.bot_brains))
		GLOB.bot_ticking_bombs[loc] = TRUE

/// One that's lying about with its timer running: not carried, and not on the toxins range's mass driver, where it's meant to be.
/proc/bot_bomb_ticking(obj/item/transfer_valve/V)
	if(QDELETED(V) || !isturf(V.loc))
		return FALSE
	var/obj/item/assembly/timer/T = V.attached_device
	if(!istype(T) || !T.timing || !V.tank_one || !V.tank_two)
		return FALSE
	return !(locate(/obj/machinery/mass_driver) in V.loc)

/// From the reflexes (bot_reflexes.dm), every couple of seconds while there's a bomb ticking anywhere: one it can see, it deals with.
/datum/bot_brain/proc/mind_ticking_bombs()
	if(!length(GLOB.bot_ticking_bombs) || world.time < next_bomb_look || owner.incapacitated() || state == BOT_STATE_ARREST)
		return FALSE
	next_bomb_look = world.time + 2 SECONDS
	for(var/obj/item/transfer_valve/V as anything in GLOB.bot_ticking_bombs)
		if(!bot_bomb_ticking(V))
			GLOB.bot_ticking_bombs -= V
			continue
		if(V.z != owner.z || get_dist(owner, V) > BOT_SIGHT_RANGE || !(V in view(BOT_SIGHT_RANGE, owner)))
			continue
		return react_to_bomb(V)
	return FALSE

/datum/bot_brain/proc/react_to_bomb(obj/item/transfer_valve/V)
	if(istype(current_goal, /datum/bot_goal/defuse_bomb) || istype(current_goal, /datum/bot_goal/run_from) || istype(current_goal, /datum/bot_goal/sabotage_plant_bomb))
		return FALSE
	if(armed_bomb == V || bot_traitor && saboteur)
		return FALSE //its own, or somebody else's handiwork it's glad of
	var/obj/item/assembly/timer/T = V.attached_device
	var/brave = (is_security_job() && nerve >= 0.3) || (is_fire_response_job() && nerve >= 0.6) || nerve >= 0.85
	if(brave && T.time > BOT_BOMB_TOO_LATE && !taken_by_another(V))
		bot_say(owner, pick(";There's a bomb in [get_area_name(V, TRUE)]! I'm on it, everybody get clear!", ";Bomb in [get_area_name(V, TRUE)], ticking! Going to pull the timer, stay back!"), TRUE)
		drop_goals("a bomb to defuse")
		return assign_goal(new /datum/bot_goal/defuse_bomb(V))
	if(world.time >= world_time_next_grenade_shout)
		world_time_next_grenade_shout = world.time + 15 SECONDS
		bot_say(owner, pick(";There's a bomb in [get_area_name(V, TRUE)]! It's ticking!", ";BOMB! [get_area_name(V, TRUE)]! Everybody out!", "Bomb! Run!"), TRUE)
	return run_from(V, "a ticking bomb")

/datum/bot_goal/defuse_bomb
	doing = "pulling a bomb's timer"
	exclusive = TRUE
	never_rests = TRUE
	braves_bad_air = TRUE
	breaks_in = TRUE

/datum/bot_goal/defuse_bomb/New(obj/item/transfer_valve/V)
	. = ..()
	target = V

/datum/bot_goal/defuse_bomb/resolve_target(datum/bot_brain/bot)
	if(!bot_bomb_ticking(target))
		target = null

/datum/bot_goal/defuse_bomb/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/sabotage/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/pull_bomb_timer())
	return list(S)

/datum/bot_step/pull_bomb_timer/execute(datum/bot_brain/bot)
	var/obj/item/transfer_valve/V = bot.current_goal?.target
	if(QDELETED(V) || !bot.owner.Adjacent(V))
		return GOAL_STEP_FAIL
	var/obj/item/assembly/timer/T = V.attached_device
	if(!T)
		return GOAL_STEP_SUCCESS //somebody's beaten it to it
	bot.human_pause(V)
	if(QDELETED(V) || V.attached_device != T)
		return GOAL_STEP_SUCCESS
	T.on_detach()
	V.attached_device = null
	V.update_icon()
	GLOB.bot_ticking_bombs -= V
	bot_log(bot, "pulled the timer off [V] in [get_area_name(V, TRUE)]")
	bot_tally("bombs defused")
	log_game("BOT: [key_name(bot.owner)] defused a tank bomb at [AREACOORD(V)]")
	bot_say(bot.owner, pick(";Bomb's safe, timer's off. [get_area_name(V, TRUE)].", ";Got it, the bomb in [get_area_name(V, TRUE)] is safe."), TRUE)
	return GOAL_STEP_SUCCESS

#undef BOT_BOMB_FUSE
#undef BOT_BOMB_TOO_LATE
#undef BOT_MAXCAP_PATIENCE
