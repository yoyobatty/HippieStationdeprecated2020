// Mining in the Ripley (the user, 2026-11-12: "There should also always be a miner who uses the mech in cargo/mining and mines
// materials, avoiding enemies and returns them to the station").
//
//  - One Shaft Miner is the mech miner: the first bot miner on, and the next one along once it's gone. The others dig on foot
//    (goals/mining.dm), and so does the mech miner while there's no Ripley to be had. bot_population.dm always has one bot miner aboard.
//  - The Ripley: Hippie's Mining keeps one on its charger with a drill, a clamp, an ore box in the hold and a scanner
//    (/obj/mecha/working/ripley/mining_roundstart). The drill takes the rock in front of it three tiles at a go, and with the clamp
//    fitted and a box in the hold the ore off it goes straight in the box (drill/move_ores(), ripley/collect_ore()).
//  - Down: the Ripley driven aboard the shuttle while it's in (take_mech_down, goals/mech_pilot.dm), out of it to work the console, and
//    the ride. Down there: in again, off the shuttle, and out to the rock. The scanner fitted to it shows the seams for seven tiles.
//  - The wildlife: it drives off from anything that comes for it rather than stopping to fight it, and if it keeps having to, it goes
//    home. Only cornered does it use the drill on it. The ash storms are nothing to it inside (ash_storm/is_ash_immune()).
//  - Back: with a box worth bringing, or the cell or the armour run down, aboard again, out, and the ride up. At the station the box is
//    set down on the redemption machine's input, where the machine empties it (ore_redemption/process()); the clamp takes it back up
//    and the Ripley goes back on its charger.

/// Ore in the box that's a load worth taking up.
#define BOT_MECH_LOAD 150
/// How long a trip out lasts at most.
#define BOT_MECH_TRIP_LIMIT (20 MINUTES)
/// The cell's share at which it heads back, and the share it wants before it goes down again.
#define BOT_MECH_LOW_CELL 0.35
#define BOT_MECH_READY_CELL 0.6
/// A tank this full is full enough for a trip (they come at 1,013 kPa).
#define BOT_MECH_TANK_FULL 900
/// Ore in the box worth a drive to the redemption machine.
#define BOT_MECH_WORTH_UNLOADING 10
/// The armour's share at which it heads back.
#define BOT_MECH_HURT 0.5
/// How near the wildlife can get before it moves off.
#define BOT_MECH_FAUNA_RANGE 5
/// How far it drives off.
#define BOT_MECH_RETREAT 8
/// Times it's had to drive off in one trip before it calls it a day.
#define BOT_MECH_RETREATS 5
/// What the Ripley's scanner reads: the whole screen, like the manual one (mecha_equipment/mining_scanner).
#define BOT_MECH_SCANNER_RANGE 7

/// The bot miner who works the Ripley.
GLOBAL_DATUM(bot_mech_miner, /datum/weakref)

/datum/bot_brain
	/// Times it drove off from the wildlife this trip.
	var/mech_retreats = 0
	/// When it noticed there's no rock left in reach this trip.
	var/mech_dug_out = FALSE
	/// It's called this trip done: home it goes, whatever a refill at the outpost does for its tank in the meantime. Topped up there with 134
	/// ore in the box, the pilot set off again, lost the Ripley on the shuttle, and the ore never came up (Bot Shift, 2026-11-12).
	var/mech_trip_over = FALSE
	var/mech_refill_tried_until = 0

/// Whether this is the miner who works the Ripley: whoever it already is, or this one if that one's gone. In the gym, one per arena.
/datum/bot_brain/proc/is_mech_miner()
	if(!is_miner() || gone_loud() || bot_traitor)
		return FALSE
	var/datum/bot_brain/B = GLOB.bot_mech_miner?.resolve()
	if(B == src)
		return TRUE
	if(B && !QDELETED(B.owner) && B.owner.stat != DEAD && !B.logged_off && B.gym_run == gym_run && (B.is_miner() || istype(B.in_mech(), /obj/mecha/working/ripley)))
		return FALSE //still at it, or still in the Ripley
	GLOB.bot_mech_miner = WEAKREF(src)
	bot_log(src, "MECH: I'm the one on the Ripley")
	return TRUE

/// In the Ripley, the scanner fitted to it is what shows the seams.
/datum/bot_brain/mining_scan_range()
	. = ..()
	var/obj/mecha/M = in_mech()
	if(M && (locate(/obj/item/mecha_parts/mecha_equipment/mining_scanner) in M.equipment))
		. = max(., BOT_MECH_SCANNER_RANGE)

/proc/bot_mech_clamp(obj/mecha/M)
	return locate(/obj/item/mecha_parts/mecha_equipment/hydraulic_clamp) in M?.equipment

/proc/bot_mech_ore_box(obj/mecha/working/ripley/R)
	return istype(R) ? (locate(/obj/structure/ore_box) in R.cargo) : null

/proc/bot_ore_count(atom/A)
	. = 0
	for(var/obj/item/stack/ore/O in A)
		. += O.amount

/proc/bot_mech_cell_share(obj/mecha/M)
	return M?.cell ? M.cell.charge / M.cell.maxcharge : 0

/// A Ripley fitted for mining, a drill and a clamp, on this level (or aboard the shuttle here) with nobody else in it: the nearest.
/datum/bot_brain/proc/mining_ripley()
	var/turf/here = get_turf(owner)
	if(!here)
		return null
	var/obj/mecha/working/ripley/best
	var/best_dist
	for(var/obj/mecha/working/ripley/R in GLOB.mechas_list)
		if(QDELETED(R) || (R.occupant && R.occupant != owner) || R.z != here.z || !bot_mech_drill(R) || !bot_mech_clamp(R))
			continue
		if(gym_run && get_area(R) != get_area(owner))
			continue
		if(taken_by_another(R))
			continue
		var/dist = get_dist(here, R)
		if(!best || dist < best_dist)
			best = R
			best_dist = dist
	return best

/// Whether to call this trip done and take the Ripley home.
/datum/bot_brain/proc/mech_time_to_head_back(obj/mecha/working/ripley/R)
	if(mech_trip_over || bot_going_home_soon() || mech_dug_out || mech_retreats >= BOT_MECH_RETREATS)
		return TRUE
	if(bot_ore_count(bot_mech_ore_box(R)) >= BOT_MECH_LOAD)
		return TRUE
	if(mining_since && world.time > mining_since + BOT_MECH_TRIP_LIMIT)
		return TRUE
	if(bot_mech_cell_share(R) < BOT_MECH_LOW_CELL || R.obj_integrity < R.max_integrity * BOT_MECH_HURT)
		return TRUE
	// The cockpit's open: the pilot's on its own mask and tank the whole trip, and there's nowhere down here to fill it
	if(tank_running_out() || owner.getOxyLoss() > 20)
		return TRUE
	return owner.health < owner.maxHealth * BOT_MECH_HURT

/// The mining duty's look on Lavaland, for the mech miner: TRUE if it's started on something. FALSE leaves it to dig on foot.
/datum/bot_brain/proc/mech_mining_on_lavaland()
	if(!is_mech_miner())
		return FALSE
	var/obj/mecha/working/ripley/R = in_mech() || mining_ripley()
	if(!istype(R) || !bot_mech_ore_box(R))
		if(in_mech())
			climb_out_of_mech()
		return FALSE
	var/heading_back = mech_time_to_head_back(R)
	if(!heading_back && !in_mech() && mech_top_up_tank()) //at the outpost's canister before setting off
		return TRUE
	if(bot_aboard_mining_shuttle(R))
		if(!heading_back)
			return assign_goal(new /datum/bot_goal/mech_mine(R))
		if(in_mech())
			climb_out_of_mech()
		return assign_goal(new /datum/bot_goal/ride_mining_shuttle("mining_home"))
	if(!heading_back)
		return assign_goal(new /datum/bot_goal/mech_mine(R))
	if(bot_mining_shuttle_at("mining_away"))
		return assign_goal(new /datum/bot_goal/mech_aboard(R, "mining_away"))
	// The shuttle's up at the station: parked by the dock, and out to call it from the console there (ride_mining_shuttle does the
	// calling). Once it's in, the next look drives the Ripley aboard.
	var/obj/docking_port/stationary/dock = bot_mining_dock(my_z())
	if(dock && get_dist(R, dock) > 8)
		if(!in_mech() && !owner.Adjacent(R))
			return assign_goal(new /datum/bot_goal/walk_up_to(R))
		if(!climb_into_mech(R))
			return FALSE
		var/turf/near = nearest_walkable_toward(get_turf(dock))
		return near ? assign_goal(new /datum/bot_goal/walk_up_to(near)) : FALSE
	if(in_mech())
		climb_out_of_mech()
	return assign_goal(new /datum/bot_goal/ride_mining_shuttle("mining_home"))

/// At the station, before anything else on the mining round: the box unloaded, a box found, the cell charged. TRUE if it's started on one.
/datum/bot_brain/proc/mech_station_chores()
	if(!is_mech_miner())
		return FALSE
	var/obj/mecha/working/ripley/R = in_mech() || mining_ripley()
	if(!istype(R))
		return FALSE
	// One Robotics built for Mining (a map with none in the dock, goals/mech_build.dm) is behind Robotics' doors: robotics access from the
	// HoP first, the way anybody borrowing it would.
	var/obj/item/card/id/card = route_card()
	if(!in_mech() && in_robotics(R) && !(ACCESS_ROBOTICS in card?.access))
		if(world.time < next_explore_access_ask || !bot_find_card_granter(owner))
			return FALSE
		next_explore_access_ask = world.time + 10 MINUTES
		bot_log(src, "MECH: asking for robotics access, for the Ripley")
		return assign_goal(new /datum/bot_goal/job_transfer/access(list(ACCESS_ROBOTICS), "robotics"))
	var/obj/structure/ore_box/box = bot_mech_ore_box(R)
	if(box && bot_ore_count(box) >= BOT_MECH_WORTH_UNLOADING) //not a stray ore or two it drove over in the dock
		return assign_goal(new /datum/bot_goal/mech_unload(R))
	if(!box)
		var/obj/structure/ore_box/spare = spare_ore_box(R)
		return spare ? assign_goal(new /datum/bot_goal/mech_get_box(R, spare)) : FALSE
	if(bot_mech_cell_share(R) < BOT_MECH_READY_CELL && !bot_mech_on_charger(R) && !bot_aboard_mining_shuttle(R))
		return assign_goal(new /datum/bot_goal/mech_to_charger(R))
	if(in_mech() && !bot_aboard_mining_shuttle(R))
		climb_out_of_mech() //parked: on foot for the rest of the round's business
	return FALSE

/// At the station and ready to go down: the Ripley aboard first, if it's charged and the shuttle's in. TRUE if it's started on it.
/datum/bot_brain/proc/mech_take_down()
	if(!is_mech_miner())
		return FALSE
	mech_retreats = 0
	mech_dug_out = FALSE
	mech_trip_over = FALSE //back up here: the next trip's a new one
	var/obj/mecha/working/ripley/R = mining_ripley()
	if(!istype(R) || !bot_mech_ore_box(R) || bot_aboard_mining_shuttle(R) || bot_mech_cell_share(R) < BOT_MECH_READY_CELL || !bot_mining_shuttle_at("mining_home"))
		return FALSE
	if(!can_walk_lawfully_to(R))
		return FALSE
	if(mech_top_up_tank())
		return TRUE
	return assign_goal(new /datum/bot_goal/take_mech_down(R))

/// The cockpit's open, so a trip lasts as long as the pilot's tank: topped up before one, from an oxygen canister it can get to by its own
/// doors (the outpost's down there; up here, wherever its ID lets it). A pilot that went down on a part-used tank ran it dry on the way
/// back, and the next went hacking into Engineering's maintenance for a canister (Bot Shift, 2026-11-12). TRUE if it's gone to.
/datum/bot_brain/proc/mech_top_up_tank()
	var/obj/item/tank/internals/tank = eva_tank()
	if(!istype(tank) || tank.air_contents.return_pressure() >= BOT_MECH_TANK_FULL || world.time < mech_refill_tried_until)
		return FALSE
	mech_refill_tried_until = world.time + 3 MINUTES
	var/obj/machinery/portable_atmospherics/canister/C = find_oxygen_canister()
	if(!C || !can_walk_lawfully_to(C))
		return FALSE
	var/datum/bot_goal/refill_internals/G = new
	G.lawful = TRUE
	if(!assign_goal(G))
		return FALSE
	bot_log(src, "MECH: topping up [tank] before the trip ([round(tank.air_contents.return_pressure())] kPa)")
	return TRUE

/// An ore box nobody has, near enough the Ripley to fetch: the hold's is empty after a wreck, or it's a new Ripley.
/// Mining keeps them by the dock, so it looks there as well as round the Ripley.
/datum/bot_brain/proc/spare_ore_box(obj/mecha/working/ripley/R)
	var/obj/docking_port/stationary/dock = bot_mining_dock(R.z)
	for(var/atom/near in list(R, dock))
		for(var/obj/structure/ore_box/box in range(30, get_turf(near)))
			if(isturf(box.loc) && !taken_by_another(box) && can_walk_lawfully_to(box))
				return box
	return null

/proc/bot_mech_on_charger(obj/mecha/M)
	return istype(get_turf(M), /turf/open/floor/mech_bay_recharge_floor)

/// The nearest charger floor with its port beside it, powered.
/proc/bot_mech_charger_near(atom/A, range = 40)
	var/turf/best
	var/best_dist
	for(var/obj/machinery/mech_bay_recharge_port/P in range(range, get_turf(A)))
		if(P.stat & (NOPOWER|BROKEN))
			continue
		var/turf/open/floor/mech_bay_recharge_floor/F = get_step(P, P.dir)
		if(!istype(F))
			continue
		var/obj/mecha/on_it = locate() in F
		if(on_it && on_it != A) //the one asking is welcome on it
			continue
		var/dist = get_dist(A, F)
		if(!best || dist < best_dist)
			best = F
			best_dist = dist
	return best

// ---------------------------------------------------------------------------------------------
// The Ripley's errands: in, a drive and whatever's at the end of it, a look at a time
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/mech_errand
	lawful = TRUE
	exclusive = TRUE
	braves_bad_air = TRUE //the cabin's own air
	var/obj/mecha/working/ripley/mech

/datum/bot_goal/mech_errand/New(obj/mecha/working/ripley/R)
	. = ..()
	mech = R
	target = R

/datum/bot_goal/mech_errand/resolve_target(datum/bot_brain/bot)
	if(QDELETED(mech) || (mech.occupant && mech.occupant != bot.owner))
		target = null

/datum/bot_goal/mech_errand/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/mech_errand())
	return list(S)

/datum/bot_goal/mech_errand/on_success(datum/bot_brain/bot)
	bot.continue_mining_round()

/// The stages, one look each. Each errand fills in what happens once it's aboard (stage "work").
/datum/bot_step/mech_errand
	var/stage = "board"
	var/actions = 0
	var/tries = 0

/datum/bot_step/mech_errand/proc/again(datum/bot_brain/bot, delay = 5)
	addtimer(CALLBACK(src, PROC_REF(carry_on), bot, bot.current_goal), delay)
	return GOAL_STEP_PENDING

/datum/bot_step/mech_errand/proc/carry_on(datum/bot_brain/bot, datum/bot_goal/goal)
	if(QDELETED(bot) || bot.state != BOT_STATE_GOAL || bot.current_goal != goal || !bot.on_this_step(src))
		return
	var/result
	try
		result = execute(bot)
	catch(var/exception/e)
		bot_log_exception(bot, "mech_errand", e)
		result = GOAL_STEP_FAIL
	if(result != GOAL_STEP_PENDING)
		bot.advance_goal_step(result == GOAL_STEP_SUCCESS)

/datum/bot_step/mech_errand/execute(datum/bot_brain/bot)
	var/datum/bot_goal/mech_errand/G = bot.current_goal
	if(!istype(G) || QDELETED(G.mech) || ++actions > 900)
		return GOAL_STEP_FAIL
	if(stage == "board")
		if(bot.in_mech() == G.mech)
			stage = "work"
			return again(bot, 1)
		if(!bot.owner.Adjacent(G.mech))
			if(++tries > 3)
				return GOAL_STEP_FAIL
			return bot.suspend_goal_for(new /datum/bot_goal/walk_up_to(G.mech)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL
		if(!bot.climb_into_mech(G.mech))
			if(++tries > 3)
				return GOAL_STEP_FAIL
			return again(bot, 2 SECONDS) //a goliath's tentacle or a watcher's freeze in the climb: another go
		stage = "work"
		tries = 0
		return again(bot, 1)
	if(bot.in_mech() != G.mech)
		stage = "board"
		return again(bot, 1)
	return G.work(bot, src)

/// Once aboard: the errand's own part. Returns GOAL_STEP_PENDING (via step.again()), SUCCESS or FAIL.
/datum/bot_goal/mech_errand/proc/work(datum/bot_brain/bot, datum/bot_step/mech_errand/step)
	return GOAL_STEP_SUCCESS

/// Something loose into the hold with the clamp: from beside it and facing it, since the clamp's wait ends in a check that it's in front
/// (do_after_cooldown()), and on the same tile nothing is. Stood on it, a step off first.
/datum/bot_goal/mech_errand/proc/clamp_up(datum/bot_brain/bot, datum/bot_step/mech_errand/step, obj/O)
	var/obj/item/mecha_parts/mecha_equipment/hydraulic_clamp/C = bot_mech_clamp(mech)
	if(!C || QDELETED(O) || !isturf(O.loc))
		return GOAL_STEP_FAIL
	var/turf/here = get_turf(mech)
	if(O.loc == here)
		for(var/direction in GLOB.cardinals)
			var/turf/T = get_step(here, direction)
			if(T && !T.density && !bot_turf_is_deadly(T) && !is_blocked_turf(T, TRUE) && bot.bot_step_towards(T))
				return step.again(bot, 1 SECONDS)
		return GOAL_STEP_FAIL
	if(!mech.Adjacent(O))
		var/turf/beside = bot_free_turf_beside(O, here)
		return beside && drive_to(bot, beside) ? step.again(bot, 5) : GOAL_STEP_FAIL
	mech.setDir(get_dir(mech, O))
	mech.selected = C
	bot.telemetry_ui_action(mech, "clamp [O]")
	INVOKE_ASYNC(mech, TYPE_PROC_REF(/obj/mecha, click_action), O, bot.owner)
	return step.again(bot, 2 SECONDS) //the clamp's own wait

/// A free floor tile next to something, square on, nearest the given spot.
/proc/bot_free_turf_beside(atom/A, turf/near)
	var/turf/best
	for(var/direction in GLOB.cardinals)
		var/turf/T = get_step(A, direction)
		if(!T || T.density || bot_turf_is_deadly(T) || is_blocked_turf(T, TRUE))
			continue
		if(!best || get_dist(near, T) < get_dist(near, best))
			best = T
	return best

/// Driving it somewhere: a route for the exosuit, as for anybody on foot (bot_step_towards() steps it). TRUE while it's under way.
/datum/bot_goal/mech_errand/proc/drive_to(datum/bot_brain/bot, turf/T)
	if(get_turf(mech) == T)
		return FALSE
	if(bot.pursuing_kind)
		return TRUE
	if(get_dist(mech, T) == 1 && !T.density)
		bot.bot_step_towards(T)
		return TRUE
	return bot.pursue(T, "follow", force = TRUE)

// ---------------------------------------------------------------------------------------------
// Out on the rock
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/mech_mine
	parent_type = /datum/bot_goal/mech_errand
	doing = "mining in the Ripley"
	var/list/seams
	var/turf/closed/mineral/seam
	var/turf/rock_face
	var/looks = 0
	var/ore_at_start = -1

/datum/bot_goal/mech_mine/work(datum/bot_brain/bot, datum/bot_step/mech_errand/step)
	if(ore_at_start < 0)
		ore_at_start = bot_ore_count(bot_mech_ore_box(mech))
		bot_log(bot, "MECH: out to the rock in [mech] (cell [round(bot_mech_cell_share(mech) * 100)]%, [ore_at_start] ore in the box)")
	if(bot.mech_time_to_head_back(mech))
		bot.mech_trip_over = TRUE
		var/got = bot_ore_count(bot_mech_ore_box(mech)) - ore_at_start
		bot.ores_mined += max(got, 0)
		bot_log(bot, "MECH: calling it a trip: [got] ore this time, cell [round(bot_mech_cell_share(mech) * 100)]%, armour [round(100 * mech.obj_integrity / mech.max_integrity)]%[bot.mech_retreats ? ", drove off from the wildlife [bot.mech_retreats] time\s" : ""]")
		return GOAL_STEP_SUCCESS
	if(steer_clear(bot))
		return step.again(bot, 10)
	if(bot.pursuing_kind)
		return step.again(bot, 5)
	var/turf/here = get_turf(mech)
	if(!seam || !bot_turf_is_ore(seam))
		seam = next_seam(bot)
	if(!seam)
		if(rock_face && here != rock_face && drive_to(bot, rock_face))
			return step.again(bot, 5)
		rock_face = null
		LAZYSET(bot.mining_scanned, here, TRUE)
		bot.note_scanned_from(here)
		seams = bot.scan_for_ore()
		seam = next_seam(bot)
		if(seam)
			bot_log(bot, "MECH: the scanner shows [length(seams) + 1] seam\s from [bot_coord(here)]")
			return step.again(bot, 3)
		rock_face = bot.find_rock_face()
		if(!rock_face)
			bot.mech_dug_out = TRUE
			bot_log(bot, "MECH: no rock left in reach that I haven't tried")
			return step.again(bot, 1)
		return drive_to(bot, rock_face) ? step.again(bot, 5) : step.again(bot, 10)
	// Square on, as on foot: the exosuit routes on the four sides of a tile too.
	var/x_off = seam.x - here.x
	var/y_off = seam.y - here.y
	var/turf/next = get_step(here, abs(x_off) >= abs(y_off) ? (x_off > 0 ? EAST : WEST) : (y_off > 0 ? NORTH : SOUTH))
	if(!next || next == here || bot_turf_is_deadly(next))
		give_up_on_seam(bot)
		return step.again(bot, 2)
	if(ismineralturf(next))
		if(gibtonite_in_the_way(here, get_dir(here, next)))
			give_up_on_seam(bot)
			return step.again(bot, 2)
		if(!bot.mech_drill_at(next))
			give_up_on_seam(bot)
			return step.again(bot, 2)
		return step.again(bot, 25) //the drill's own wait (equip_cooldown and drill_delay), then the next look
	if(next.density || !bot.bot_step_towards(next))
		if(++step.tries > 4)
			step.tries = 0
			give_up_on_seam(bot)
		return step.again(bot, 5)
	step.tries = 0
	return step.again(bot, 3)

/datum/bot_goal/mech_mine/proc/next_seam(datum/bot_brain/bot)
	while(length(seams))
		var/turf/closed/mineral/M = seams[1]
		seams.Cut(1, 2)
		if(bot_turf_is_ore(M) && LAZYACCESS(bot.mining_dead_seams, M) <= world.time)
			return M
	return null

/datum/bot_goal/mech_mine/proc/give_up_on_seam(datum/bot_brain/bot)
	if(seam)
		LAZYSET(bot.mining_dead_seams, seam, world.time + 5 MINUTES)
	seam = null

/// The drill takes what's in front of it in an arc (mineral/drill_act()): gibtonite anywhere in that arc goes off.
/datum/bot_goal/mech_mine/proc/gibtonite_in_the_way(turf/here, facing)
	for(var/turf/closed/mineral/gibtonite/G in range(1, here))
		if(get_dir(here, G) & facing)
			return TRUE
	return FALSE

/// Wildlife closing in: off the other way, toward the dock if that's away from it, and the seams round it left for a couple of minutes.
/// Cornered, the drill. TRUE if it had to do something about it.
/datum/bot_goal/mech_mine/proc/steer_clear(datum/bot_brain/bot)
	var/turf/here = get_turf(mech)
	var/mob/living/simple_animal/hostile/asteroid/beast
	for(var/mob/living/simple_animal/hostile/asteroid/A in view(BOT_MECH_FAUNA_RANGE, here))
		if(A.stat == CONSCIOUS && (!beast || get_dist(here, A) < get_dist(here, beast)))
			beast = A
	if(!beast)
		return FALSE
	for(var/turf/closed/mineral/M in range(4, beast))
		LAZYSET(bot.mining_dead_seams, M, world.time + 2 MINUTES)
	seam = null
	rock_face = null
	bot.mech_retreats++
	var/away = get_dir(beast, here) || pick(GLOB.cardinals)
	var/obj/docking_port/stationary/dock = bot_mining_dock(here.z)
	if(dock && (get_dir(here, dock) & away))
		away = get_dir(here, dock)
	var/turf/far = get_ranged_target_turf(here, away, BOT_MECH_RETREAT)
	var/turf/spot = far && bot.nearest_walkable_toward(far, 300)
	bot.stop_pursuit()
	if(spot && spot != here && bot.pursue(spot, "follow", force = TRUE))
		bot_log(bot, "MECH: [beast] coming at me - driving off toward [bot_coord(spot)] ([bot.mech_retreats] this trip)")
		return TRUE
	if(get_dist(here, beast) <= 1)
		bot_log(bot, "MECH: cornered by [beast] - the drill")
		bot.fight_in_reach(beast)
		return TRUE
	return FALSE

// ---------------------------------------------------------------------------------------------
// Aboard the shuttle, down there
// ---------------------------------------------------------------------------------------------

/// Onto the shuttle at this end, and out of it to the console.
/datum/bot_goal/mech_aboard
	parent_type = /datum/bot_goal/mech_errand
	doing = "driving the Ripley aboard the shuttle"
	var/dock_id
	var/turf/parking

/datum/bot_goal/mech_aboard/New(obj/mecha/working/ripley/R, dock_id)
	. = ..()
	src.dock_id = dock_id

/datum/bot_goal/mech_aboard/work(datum/bot_brain/bot, datum/bot_step/mech_errand/step)
	if(bot_aboard_mining_shuttle(mech))
		bot.climb_out_of_mech()
		bot_log(bot, "MECH: [mech] is aboard")
		return GOAL_STEP_SUCCESS
	if(!bot_mining_shuttle_at(dock_id))
		return GOAL_STEP_FAIL
	if(!parking || (locate(/obj/mecha) in parking) && get_turf(mech) != parking)
		parking = bot_shuttle_parking()
	if(!parking)
		return GOAL_STEP_FAIL
	bot.region_floods = null //it's just come in (drive_mech_aboard, goals/mech_pilot.dm)
	return drive_to(bot, parking) ? step.again(bot, 5) : step.again(bot, 2)

// ---------------------------------------------------------------------------------------------
// Back at the station
// ---------------------------------------------------------------------------------------------

/// The box onto the redemption machine's input, emptied, back in the hold, and the Ripley onto its charger.
/datum/bot_goal/mech_unload
	parent_type = /datum/bot_goal/mech_errand
	doing = "unloading the Ripley at the ore machine"
	var/obj/machinery/mineral/ore_redemption/machine
	var/obj/structure/ore_box/box
	var/phase = "drive"
	var/delivered = 0
	var/waited = 0

/datum/bot_goal/mech_unload/resolve_target(datum/bot_brain/bot)
	..()
	box = bot_mech_ore_box(mech)
	machine = bot_nearest_ore_machine(mech)
	if(!box || !machine)
		target = null

/proc/bot_nearest_ore_machine(atom/A)
	var/obj/machinery/mineral/ore_redemption/best
	for(var/obj/machinery/mineral/ore_redemption/O as anything in bot_instances_of(/obj/machinery/mineral/ore_redemption))
		if(QDELETED(O) || O.z != A.z || (O.stat & (NOPOWER|BROKEN)) || O.panel_open)
			continue
		if(!best || get_dist(A, O) < get_dist(A, best))
			best = O
	return best

/datum/bot_goal/mech_unload/work(datum/bot_brain/bot, datum/bot_step/mech_errand/step)
	var/turf/input = get_step(machine, machine.input_dir)
	switch(phase)
		if("drive")
			if(QDELETED(machine) || !input || input.density)
				return GOAL_STEP_FAIL
			if(drive_to(bot, input))
				return step.again(bot, 5)
			if(get_turf(mech) != input)
				return ++step.tries > 5 ? GOAL_STEP_FAIL : step.again(bot, 10)
			delivered = bot_ore_count(box)
			usr = bot.owner
			bot.telemetry_ui_action(mech, "unload [box]")
			mech.Topic("", list("drop_from_cargo" = REF(box)))
			if(box.loc != input)
				return GOAL_STEP_FAIL
			bot_log(bot, "MECH: set the ore box down on [machine]'s input with [delivered] ore in it")
			phase = "wait"
			return step.again(bot, 2 SECONDS)
		if("wait")
			if(bot_ore_count(box) && ++waited < 15)
				return step.again(bot, 2 SECONDS) //it takes what's in a box on its input every machine tick
			bot.ores_delivered += delivered - bot_ore_count(box)
			bot_tally("ore brought up in the Ripley")
			phase = "clamp"
			return step.again(bot, 1)
		if("clamp")
			if(box in mech.cargo)
				phase = "park"
				return step.again(bot, 1)
			if(++step.tries > 10)
				return GOAL_STEP_FAIL
			return clamp_up(bot, step, box)
		if("park")
			var/turf/charger = bot_mech_charger_near(mech)
			if(!charger || bot_mech_on_charger(mech))
				bot.climb_out_of_mech()
				bot_log(bot, "MECH: [mech] parked[charger ? " on the charger" : " (no charger free)"], cell [round(bot_mech_cell_share(mech) * 100)]%")
				return GOAL_STEP_SUCCESS
			return drive_to(bot, charger) ? step.again(bot, 5) : step.again(bot, 10)
	return GOAL_STEP_FAIL

/// The Ripley onto a charger, and out.
/datum/bot_goal/mech_to_charger
	parent_type = /datum/bot_goal/mech_errand
	doing = "putting the Ripley on charge"

/datum/bot_goal/mech_to_charger/work(datum/bot_brain/bot, datum/bot_step/mech_errand/step)
	var/turf/charger = bot_mech_charger_near(mech)
	if(!charger || bot_mech_on_charger(mech))
		bot.climb_out_of_mech()
		return charger ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
	if(drive_to(bot, charger))
		return step.again(bot, 5)
	return ++step.tries > 5 ? GOAL_STEP_FAIL : step.again(bot, 10)

/// An ore box into the hold with the clamp, for a Ripley that hasn't one.
/datum/bot_goal/mech_get_box
	parent_type = /datum/bot_goal/mech_errand
	doing = "fetching an ore box for the Ripley"
	var/obj/structure/ore_box/box

/datum/bot_goal/mech_get_box/New(obj/mecha/working/ripley/R, obj/structure/ore_box/B)
	. = ..()
	box = B

/datum/bot_goal/mech_get_box/work(datum/bot_brain/bot, datum/bot_step/mech_errand/step)
	if(box in mech.cargo)
		bot_log(bot, "MECH: [box] loaded")
		return GOAL_STEP_SUCCESS
	if(QDELETED(box) || !isturf(box.loc) || ++step.tries > 40)
		return GOAL_STEP_FAIL
	return clamp_up(bot, step, box)

#undef BOT_MECH_LOAD
#undef BOT_MECH_TANK_FULL
#undef BOT_MECH_WORTH_UNLOADING
#undef BOT_MECH_TRIP_LIMIT
#undef BOT_MECH_LOW_CELL
#undef BOT_MECH_READY_CELL
#undef BOT_MECH_HURT
#undef BOT_MECH_FAUNA_RANGE
#undef BOT_MECH_RETREAT
#undef BOT_MECH_RETREATS
#undef BOT_MECH_SCANNER_RANGE
