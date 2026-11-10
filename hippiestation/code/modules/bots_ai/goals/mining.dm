// Mining: a Shaft Miner kits out at the dock, takes the shuttle down to Lavaland, works outwards from the base with a
// scanner and a pick, and comes back with a full satchel for the ore redemption machine, which feeds the ore silo every
// lathe on the station draws on.
//
//  - the kit is in the miners' lockers: a pick, the automatic scanner, a kinetic accelerator. The mask and tank are in the
//    survival box the job starts with. Every bit of that is what a player takes.
//  - the shuttle: the console aboard sends it, the one at the dock calls it (computer/shuttle Topic(), "move"). It only runs
//    between the two docks here; the bridge and the aux base have consoles of their own that are nothing to do with this.
//  - the scanner (mineral_scan_pulse(), adv_mining_scanner) shows the ore a few tiles round the miner, through the rock.
//    Plain rock looks the same as rock with ore in it, so ore nobody has scanned isn't known about: a miner walks to a rock
//    face it hasn't tried, pulses the scanner there and digs out what comes up. A seam inside the rock is tunnelled to.
//  - gibtonite shows up on the scanner too, and it goes off when it's dug: left alone.
//  - ore is picked up by walking over it, with the satchel on the belt or in a pocket (bag/ore Pickup_ores()), so a dug
//    tile gets stepped on before the next one is started.
//  - the machine takes ore off the floor on its input side (ore_redemption/process()), and clicking the machine with a
//    satchel does nothing, so a miner stands there and empties the satchel at its feet (storage quick_empty()).

/// Ore in the satchel at which a miner calls that a load (it holds 50, and a wall can give five at once).
#define BOT_MINER_LOAD 44
/// How long a miner stays down there before going back with whatever it has.
#define BOT_MINER_TRIP_LIMIT (15 MINUTES)
/// How far a miner goes looking for rock it hasn't tried, in steps from where it stands.
#define BOT_MINER_PROSPECT_REACH 1500
/// How far from the dock a miner will work: half a minute's warning of a storm is about this far at a run. They went on to the
/// next rock face and the next one until a storm caught them a hundred tiles from any roof.
#define BOT_MINER_RANGE 45
/// Share of its health below which a miner heads back to base.
#define BOT_MINER_HURT 0.5
/// A roof this near is run for, not sheltered from with a capsule.
#define BOT_MINER_NEAR_COVER 8
/// Suffocation damage at which it does the same: something's wrong with the tank or the mask, and the base has air.
#define BOT_MINER_SHORT_OF_BREATH 20
/// How long a seam stays crossed off once a miner has found it can't be got at.
#define BOT_MINER_SEAM_REST (5 MINUTES)
/// Sheets of something in the silo that answer a request for it.
#define BOT_MINER_ENOUGH_SHEETS 30
/// Sand a miner digs at one stop, when somebody is short of glass.
#define BOT_MINER_SAND_LOAD 20
/// How far the automatic scanner from the locker reads, and a manual one (the whole screen).
#define BOT_MINER_SCANNER_RANGE 4
#define BOT_MINER_MANUAL_SCANNER_RANGE 7

/// Materials somebody at a lathe has said they're short of: material -> when they said so (goals/lathe_work.dm). Miners dig
/// these first when the scanner shows a choice, and nothing beyond that: ore is where it is.
GLOBAL_LIST_EMPTY(bot_wanted_minerals)
/// What ore each kind of seam gives, for telling a wanted seam when one comes up on the scanner.
GLOBAL_LIST_INIT(bot_seam_materials, list(
	/turf/closed/mineral/iron = MAT_METAL,
	/turf/closed/mineral/uranium = MAT_URANIUM,
	/turf/closed/mineral/diamond = MAT_DIAMOND,
	/turf/closed/mineral/gold = MAT_GOLD,
	/turf/closed/mineral/silver = MAT_SILVER,
	/turf/closed/mineral/titanium = MAT_TITANIUM,
	/turf/closed/mineral/plasma = MAT_PLASMA,
	/turf/closed/mineral/bananium = MAT_BANANIUM,
	/turf/closed/mineral/bscrystal = MAT_BLUESPACE,
))

/datum/bot_brain
	var/ores_mined = 0
	var/ores_delivered = 0
	var/ore_trips = 0
	/// When this miner stepped off the shuttle.
	var/mining_since = 0
	/// Rock faces it has already scanned from: turf -> TRUE.
	var/list/mining_scanned
	/// Seams it couldn't get to: turf -> when it's worth another look.
	var/list/mining_dead_seams
	/// The storm it last tried its capsule against.
	var/datum/weather/capsule_tried_on
	var/mining_gear_blocked_until = 0

/datum/bot_brain/proc/is_miner()
	return work_role() == "Shaft Miner"

/datum/bot_brain/proc/on_lavaland()
	return is_mining_level(owner.z)

/datum/bot_brain/proc/ore_satchel()
	for(var/obj/item/storage/bag/ore/bag in owner)
		return bag
	return find_carried_tool(/obj/item/storage/bag/ore)

/datum/bot_brain/proc/ore_in_satchel()
	. = 0
	var/obj/item/storage/bag/ore/bag = ore_satchel()
	if(!bag)
		return
	for(var/obj/item/stack/ore/O in bag)
		. += O.amount

/// The first thing on the miner's list it hasn't got: all of it from the lockers at the dock, or lying about the base.
/datum/bot_brain/proc/miner_missing_gear()
	if(!find_carried_tool(/obj/item/pickaxe))
		return /obj/item/pickaxe
	if(!find_carried_tool(/obj/item/t_scanner/adv_mining_scanner) && !find_carried_tool(/obj/item/mining_scanner))
		return /obj/item/t_scanner/adv_mining_scanner
	if(!find_carried_tool(/obj/item/gun/energy/kinetic_accelerator))
		return /obj/item/gun/energy/kinetic_accelerator
	if(!find_carried_tool(/obj/item/survivalcapsule))
		return /obj/item/survivalcapsule
	return null

/// Dressed for the surface: a mask and a tank it can reach. It isn't a vacuum down there, just thin, bad air.
/datum/bot_brain/proc/ready_for_lavaland()
	var/obj/item/clothing/mask/mask = owner.wear_mask
	return istype(mask) && (mask.clothing_flags & MASKINTERNALS) && eva_tank()

/// How far this miner's scanner reads, or 0 without one: the best of what it's carrying. The locker's automatic one reads four
/// tiles, and the one the vendor sells for points (goals/mining_points.dm) the whole screen.
/datum/bot_brain/proc/mining_scan_range()
	if(find_carried_tool(/obj/item/mining_scanner))
		return BOT_MINER_MANUAL_SCANNER_RANGE
	. = 0
	for(var/obj/item/t_scanner/adv_mining_scanner/S in owner.GetAllContents(/obj/item/t_scanner/adv_mining_scanner))
		. = max(., S.range)

// ---------------------------------------------------------------------------------------------
// The round
// ---------------------------------------------------------------------------------------------

/datum/bot_duty/mining
	name = "mining"
	jobs = list("Shaft Miner")
	interval_min = 20
	interval_max = 60

/datum/bot_duty/mining/next_look(datum/bot_brain/bot)
	return rand(interval_min, interval_max) //once it has started, the next thing follows straight on, slacker or not

/datum/bot_duty/mining/try_start(datum/bot_brain/bot)
	if(bot.state == BOT_STATE_GOAL && bot.current_goal)
		return FALSE
	if(bot.on_lavaland())
		if(bot_storm_over(bot.owner.z))
			return FALSE
		if(bot.time_to_head_back())
			return bot.assign_goal(new /datum/bot_goal/ride_mining_shuttle("mining_home"))
		return bot.assign_goal(new /datum/bot_goal/mine_ore())
	if(!is_station_level(bot.owner.z))
		return FALSE
	if(bot.ore_in_satchel())
		return bot.assign_goal(new /datum/bot_goal/deliver_ore())
	if(bot.try_mining_points()) //goals/mining_points.dm: the voucher, the points in the machine, the vendor
		return TRUE
	if(bot_going_home_soon())
		return FALSE //nobody sets off for the mine with the shuttle on its way
	if(world.time < bot.mining_gear_blocked_until)
		return FALSE
	var/needed = bot.miner_missing_gear()
	if(needed)
		var/datum/bot_goal/acquire_item_type/fetch = new()
		fetch.item_type = needed
		fetch.lawful = TRUE
		if(!bot.assign_goal(fetch))
			bot.mining_gear_blocked_until = world.time + 2 MINUTES
			return FALSE
		return TRUE
	if(!bot.ready_for_lavaland())
		return bot.assign_goal(new /datum/bot_goal/dress_for_lavaland())
	return bot.assign_goal(new /datum/bot_goal/ride_mining_shuttle("mining_away"))

/// Whether the emergency shuttle is on its way or here.
/proc/bot_going_home_soon()
	var/obj/docking_port/mobile/emergency/E = SSshuttle.emergency
	return E && (E.mode == SHUTTLE_CALL || E.mode == SHUTTLE_DOCKED || E.mode == SHUTTLE_IGNITING)

/datum/bot_brain/proc/time_to_head_back()
	if(bot_going_home_soon() || ore_in_satchel() >= BOT_MINER_LOAD)
		return TRUE
	if(mining_since && world.time > mining_since + BOT_MINER_TRIP_LIMIT)
		return TRUE
	return owner.health < owner.maxHealth * BOT_MINER_HURT || owner.getOxyLoss() > BOT_MINER_SHORT_OF_BREATH

/// The wildlife: a miner shoots what it can see with the accelerator it carries for that, whatever else it's doing. It doesn't wait
/// to be bitten. A goliath stood in a tunnel doesn't attack anything it isn't bored of, and three miners waited behind one for it to
/// move until their tanks ran out.
/datum/bot_brain/proc/mind_fauna()
	if(!(is_miner() || pursuit == BOT_PURSUIT_EXPLORE) || !(on_lavaland() || gym_run) || world.time < next_taser_time || state == BOT_STATE_COMBAT)
		return //an explorer down there shoots what comes at it as well (goals/exploring.dm)
	for(var/mob/living/simple_animal/hostile/asteroid/beast in view(BOT_SIGHT_RANGE, owner))
		if(beast.stat == CONSCIOUS && try_shoot_at(beast))
			return

/datum/bot_brain/proc/continue_mining_round()
	var/datum/bot_duty/mining/duty = bot_duty_of(/datum/bot_duty/mining)
	continue_goal_chain(CALLBACK(duty, TYPE_PROC_REF(/datum/bot_duty, try_start), src))

// ---------------------------------------------------------------------------------------------
// Dressing
// ---------------------------------------------------------------------------------------------

/// The mask and tank out of the survival box: the tank goes in a pocket or on the belt, where the valve can be reached.
/datum/bot_goal/dress_for_lavaland
	lawful = TRUE
	doing = "getting my mask on"

/datum/bot_goal/dress_for_lavaland
	braves_bad_air = TRUE //the outpost's EVA room, where the suit is put on, is open to the air outside

/datum/bot_goal/dress_for_lavaland/resolve_target(datum/bot_brain/bot)
	target = bot.owner

/datum/bot_goal/dress_for_lavaland/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/mining/S = new
	S.steps = list(new /datum/bot_step/dress_for_lavaland())
	return list(S)

/datum/bot_goal/dress_for_lavaland/on_give_up(datum/bot_brain/bot)
	bot.mining_gear_blocked_until = world.time + 2 MINUTES

/datum/bot_goal/dress_for_lavaland/on_success(datum/bot_brain/bot)
	bot.continue_mining_round()

/datum/bot_strategy/mining/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/datum/bot_step/dress_for_lavaland/execute(datum/bot_brain/bot)
	var/mob/living/carbon/human/H = bot.owner
	var/obj/item/clothing/suit/hooded/explorer/suit = bot.find_carried_tool(/obj/item/clothing/suit/hooded/explorer)
	if(suit && H.wear_suit != suit)
		bot.wear(suit, ITEM_SLOT_OCLOTHING) //goals/exploring.dm fetches it out of the outpost's suit storage
	var/obj/item/clothing/mask/mask = H.wear_mask
	if(!istype(mask) || !(mask.clothing_flags & MASKINTERNALS))
		var/obj/item/clothing/mask/spare
		for(var/obj/item/clothing/mask/M in H.GetAllContents())
			if(M.clothing_flags & MASKINTERNALS)
				spare = M
				break
		if(!spare || !bot.wear(spare, ITEM_SLOT_MASK))
			return GOAL_STEP_FAIL
	if(bot.eva_tank())
		return GOAL_STEP_SUCCESS
	var/obj/item/tank/internals/tank
	for(var/obj/item/tank/internals/T in H.GetAllContents())
		if(!tank || T.air_contents.return_pressure() > tank.air_contents.return_pressure())
			tank = T
	if(!tank || !bot.ready_in_hand(tank))
		return GOAL_STEP_FAIL
	// The belt if it's free (the PDA goes in the ID slot), a pocket if not, with what's in it put in the bag: anywhere it
	// stays on the body. Just holding it doesn't count, the hands get tidied.
	for(var/slot in list(ITEM_SLOT_BELT, ITEM_SLOT_LPOCKET, ITEM_SLOT_RPOCKET, ITEM_SLOT_DEX_STORAGE))
		if(H.equip_to_slot_if_possible(tank, slot, FALSE, TRUE, TRUE))
			bot_log(bot, "got [tank] where I can reach the valve")
			return GOAL_STEP_SUCCESS
	var/obj/item/reagent_containers/hypospray/medipen/pen = H.l_store
	if(istype(pen) && SEND_SIGNAL(H.back, COMSIG_TRY_STORAGE_INSERT, pen, H, TRUE) && H.equip_to_slot_if_possible(tank, ITEM_SLOT_LPOCKET, FALSE, TRUE, TRUE))
		bot_log(bot, "got [tank] where I can reach the valve")
		return GOAL_STEP_SUCCESS
	return GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// The shuttle
// ---------------------------------------------------------------------------------------------

/proc/bot_mining_shuttle()
	return SSshuttle.getShuttle("mining")

/// Whether the mining shuttle is sat at this dock, doors ready.
/proc/bot_mining_shuttle_at(dock_id)
	var/obj/docking_port/mobile/M = bot_mining_shuttle()
	return M && M.mode == SHUTTLE_IDLE && M.getDockedId() == dock_id

/proc/bot_aboard_mining_shuttle(atom/A)
	var/obj/docking_port/mobile/M = bot_mining_shuttle()
	return M?.shuttle_areas && M.shuttle_areas[get_area(A)]

/// The console aboard the shuttle.
/proc/bot_mining_shuttle_console()
	for(var/obj/machinery/computer/shuttle/mining/C as anything in bot_instances_of(/obj/machinery/computer/shuttle/mining))
		if(!QDELETED(C) && bot_aboard_mining_shuttle(C))
			return C
	return null

/// The mining shuttle's dock on this level.
/proc/bot_mining_dock(z_level)
	for(var/obj/docking_port/stationary/S in SSshuttle.stationary)
		if(S.z == z_level && (S.id == "mining_home" || S.id == "mining_away"))
			return S
	return null

/// The console that calls the shuttle to this level's dock: the one nearest the dock itself, which is how the one in the
/// mining office gets told from the ones on the bridge and at the aux base.
/proc/bot_mining_dock_console(z_level)
	var/obj/docking_port/stationary/dock = bot_mining_dock(z_level)
	if(!dock)
		return null
	var/obj/machinery/computer/shuttle/mining/best
	var/best_dist
	for(var/obj/machinery/computer/shuttle/mining/C as anything in bot_instances_of(/obj/machinery/computer/shuttle/mining))
		if(QDELETED(C) || C.z != z_level || bot_aboard_mining_shuttle(C) || (C.stat & (BROKEN|NOPOWER)))
			continue
		var/dist = get_dist(C, dock)
		if(!best || dist < best_dist)
			best = C
			best_dist = dist
	return best

/// Gets the bot to the other end: calls the shuttle if it's away, boards it, sends it, rides it.
/datum/bot_goal/ride_mining_shuttle
	lawful = TRUE
	/// The dock it wants to end up at.
	var/destination

/datum/bot_goal/ride_mining_shuttle/New(destination)
	. = ..()
	src.destination = destination
	doing = destination == "mining_away" ? "heading down to the mine" : "heading back to the station"

/datum/bot_goal/ride_mining_shuttle/resolve_target(datum/bot_brain/bot)
	var/here = destination == "mining_away" ? "mining_home" : "mining_away"
	target = (bot_mining_shuttle_at(here) || bot_aboard_mining_shuttle(bot.owner)) ? bot_mining_shuttle_console() : bot_mining_dock_console(bot.owner.z)

/datum/bot_goal/ride_mining_shuttle/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/mining/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/ride_mining_shuttle())
	return list(S)

/datum/bot_goal/ride_mining_shuttle/on_success(datum/bot_brain/bot)
	bot.continue_mining_round()

/// Stood at a console: sends the shuttle where it's needed, and waits for it. Aboard, that's the ride. At the dock, it's
/// the wait for the shuttle to come in, and the goal ends there, for the duty to start it again for the walk aboard.
/datum/bot_step/paced/ride_mining_shuttle
	max_clicks = 240
	var/pressed = FALSE
	/// How many looks it's had at somebody right outside the doors, waiting for them to get on.
	var/held = 0

/datum/bot_step/paced/ride_mining_shuttle/start(datum/bot_brain/bot)
	pressed = FALSE
	held = 0
	return TRUE

/// Somebody just outside the shuttle's doors, not aboard: on their way on, most likely. Nobody sends a shuttle off in their face (an
/// assistant behind two others in the dock's doorway walked on to where the floor had been).
/proc/bot_somebody_boarding(obj/machinery/computer/shuttle/mining/C)
	for(var/obj/machinery/door/airlock/A in range(7, C))
		if(!bot_aboard_mining_shuttle(A))
			continue
		for(var/mob/living/carbon/human/P in orange(2, A))
			if(P.stat == CONSCIOUS && !P.handcuffed && !bot_aboard_mining_shuttle(P))
				return P
	return null

/datum/bot_step/paced/ride_mining_shuttle/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/ride_mining_shuttle/G = bot.current_goal
	var/obj/docking_port/mobile/M = bot_mining_shuttle()
	if(!istype(G) || !M)
		return FALSE
	var/aboard = bot_aboard_mining_shuttle(bot.owner)
	var/wanted = aboard ? G.destination : (G.destination == "mining_away" ? "mining_home" : "mining_away")
	if(bot_mining_shuttle_at(wanted))
		return FALSE //here, or it's come in for us
	wait_for = 20
	if(M.mode != SHUTTLE_IDLE)
		return TRUE //under way, or recharging: nothing to do but wait for it
	if(pressed)
		return FALSE //it was sent and it hasn't gone anywhere
	var/obj/machinery/computer/shuttle/mining/C = G.target
	if(!istype(C) || QDELETED(C) || !bot.owner.Adjacent(C))
		return FALSE
	bot.human_pause(C)
	if(QDELETED(C) || !bot.owner.Adjacent(C) || M.mode != SHUTTLE_IDLE)
		return TRUE
	if(aboard && held < 15)
		var/mob/living/carbon/human/boarding = bot_somebody_boarding(C)
		if(boarding)
			if(!held)
				bot_say(bot.owner, pick("Getting on? Shuttle's leaving.", "Hop on, [boarding.first_name()], we're off.", "Coming? I'm sending it."))
			held++
			return TRUE
	bot.owner.face_atom(C)
	bot.telemetry_ui_action(C, "send shuttle to [wanted]")
	var/result = SSshuttle.moveShuttle("mining", wanted, TRUE)
	if(result)
		bot_log(bot, "the mining shuttle can't go to [wanted] (result [result])")
		return FALSE
	pressed = TRUE
	C.say("Shuttle departing. Please stand away from the doors.")
	bot_log(bot, "sent the mining shuttle to [wanted]")
	return TRUE

/datum/bot_step/paced/ride_mining_shuttle/finish(datum/bot_brain/bot)
	var/datum/bot_goal/ride_mining_shuttle/G = bot.current_goal
	if(!istype(G))
		return GOAL_STEP_FAIL
	if(bot_mining_shuttle_at(G.destination) && bot_aboard_mining_shuttle(bot.owner))
		if(G.destination == "mining_away")
			bot.mining_since = world.time
			bot.mining_scanned = null
			bot.ore_trips++
		else
			bot.mining_since = 0
		bot_log(bot, "arrived at [G.destination]")
		return GOAL_STEP_SUCCESS
	return bot_mining_shuttle_at(G.destination == "mining_away" ? "mining_home" : "mining_away") ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// Finding ore
// ---------------------------------------------------------------------------------------------

/// Whether a turf is ore worth digging: on the scanner, and not gibtonite, which is left well alone.
/proc/bot_turf_is_ore(turf/closed/mineral/M)
	return istype(M) && M.mineralType && M.mineralAmt > 0 && !istype(M, /turf/closed/mineral/gibtonite)

/// Lava sets off what's in the air around it, and whoever is stood there goes up with it. Both of the first miners to dig a
/// seam on the edge of a lava lake burned to death there, one after the other, asleep from the BZ.
/proc/bot_beside_lava(turf/T)
	for(var/turf/open/lava/L in range(2, T))
		return TRUE
	return FALSE

/// Whether a material is still wanted: somebody has asked, and the silo hasn't caught up. Having caught up clears the request.
/proc/bot_mineral_wanted(mat)
	if(!GLOB.bot_wanted_minerals[mat])
		return FALSE
	var/datum/component/material_container/stores = GLOB.ore_silo_default?.GetComponent(/datum/component/material_container)
	if(stores && stores.amount(mat) >= BOT_MINER_ENOUGH_SHEETS * MINERAL_MATERIAL_AMOUNT)
		GLOB.bot_wanted_minerals -= mat
		return FALSE
	return TRUE

/// How much a seam is worth going for: nearer is better, and what somebody's asked for is worth a walk.
/datum/bot_brain/proc/seam_score(turf/closed/mineral/M)
	. = -get_dist(owner, M)
	for(var/seam_type in GLOB.bot_seam_materials)
		if(istype(M, seam_type))
			if(bot_mineral_wanted(GLOB.bot_seam_materials[seam_type]))
				. += 6
			break

/// The ore this miner's scanner shows from where it stands, best first. Pulses the scanner, for anybody watching.
/datum/bot_brain/proc/scan_for_ore()
	. = list()
	var/range = mining_scan_range()
	if(!range)
		return
	var/turf/here = get_turf(owner)
	mineral_scan_pulse(here, range)
	var/list/scores = list()
	for(var/turf/closed/mineral/M in range(range, here))
		if(bot_turf_is_ore(M) && LAZYACCESS(mining_dead_seams, M) <= world.time && !bot_beside_lava(M))
			scores[M] = seam_score(M)
	while(length(scores))
		var/turf/best
		for(var/turf/T as anything in scores)
			if(!best || scores[T] > scores[best])
				best = T
		. += best
		scores -= best

/// Walks the ground from here, by the doors its ID opens and not on lava, and returns the nearest tile `test` (a proc on
/// the brain, given the turf) says yes to. Outdoors the ordinary route search has a whole world to open, so it pays to
/// know where it's going first.
/datum/bot_brain/proc/nearest_on_foot(test)
	var/turf/start = get_turf(owner)
	var/obj/item/card/id/id_card = owner.get_idcard(TRUE)
	var/list/seen = list()
	seen[start] = TRUE
	var/list/queue = list(start)
	var/at = 1
	while(at <= length(queue) && at <= BOT_MINER_PROSPECT_REACH)
		var/turf/T = queue[at++]
		if(call(src, test)(T))
			return T
		for(var/direction in GLOB.cardinals)
			var/turf/next = get_step(T, direction)
			if(next && !seen[next] && T.bot_reachable_strict(owner, next, id_card, TRUE))
				seen[next] = TRUE
				queue += next
	return null

/// Outdoors, beside rock, and not somewhere it has scanned from.
/datum/bot_brain/proc/is_untried_rock_face(turf/T)
	var/area/A = T.loc
	if(T == get_turf(owner) || LAZYACCESS(mining_scanned, T) || !A.outdoors)
		return FALSE
	var/obj/docking_port/stationary/dock = bot_mining_dock(T.z)
	if(dock && get_dist(T, dock) > BOT_MINER_RANGE)
		return FALSE
	for(var/direction in GLOB.cardinals)
		if(ismineralturf(get_step(T, direction)))
			return !bot_beside_lava(T)
	return FALSE

/datum/bot_brain/proc/find_rock_face()
	return nearest_on_foot(PROC_REF(is_untried_rock_face))

/// Crosses this spot and everything the scanner read from it off the list of places worth trying.
/datum/bot_brain/proc/note_scanned_from(turf/T)
	var/range = mining_scan_range()
	for(var/turf/open/near in range(max(range - 1, 1), T))
		LAZYSET(mining_scanned, near, TRUE)

// ---------------------------------------------------------------------------------------------
// Digging
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/mine_ore
	lawful = TRUE
	doing = "digging for ore"

/// Somewhere to scan from: where it's standing, if that's beside rock it hasn't tried, or else the nearest place that is.
/datum/bot_goal/mine_ore/resolve_target(datum/bot_brain/bot)
	target = bot.find_rock_face()

/datum/bot_goal/mine_ore/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/mining/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/dig_out_ore())
	return list(S)

/datum/bot_goal/mine_ore/on_success(datum/bot_brain/bot)
	bot.continue_mining_round()

/datum/bot_goal/mine_ore/on_give_up(datum/bot_brain/bot)
	if(target) //a spot it couldn't get to, as good as tried
		LAZYSET(bot.mining_scanned, get_turf(target), TRUE)

/// At a rock face with a pick in hand: a pulse of the scanner, then whatever it shows, nearest first. Down one seam, step
/// onto the ore to take it up, and on to the next. Rock in the way is dug through a tile at a time.
/datum/bot_step/paced/dig_out_ore
	max_clicks = 180
	var/list/seams
	var/turf/closed/mineral/seam
	var/sand_taken = 0

/datum/bot_step/paced/dig_out_ore/start(datum/bot_brain/bot)
	bot.note_scanned_from(get_turf(bot.owner))
	seams = bot.scan_for_ore()
	seam = null
	if(length(seams))
		bot_log(bot, "the scanner shows [length(seams)] seam\s here")
	return TRUE

/datum/bot_step/paced/dig_out_ore/proc/next_seam()
	seam = null
	while(length(seams) && !seam)
		var/turf/closed/mineral/M = seams[1]
		seams.Cut(1, 2)
		if(bot_turf_is_ore(M))
			seam = M

/datum/bot_step/paced/dig_out_ore/proc/give_up_on_seam(datum/bot_brain/bot)
	LAZYSET(bot.mining_dead_seams, seam, world.time + BOT_MINER_SEAM_REST)
	bot_log(bot, "can't get at the seam at [bot_coord(seam)]")
	next_seam()

/// Sand for glass: the ground here gives five a tile, far quicker than any rock, so it's only dug when somebody's short of
/// glass, and only up to a share of the satchel.
/datum/bot_step/paced/dig_out_ore/proc/dig_for_sand(datum/bot_brain/bot, obj/item/pickaxe/pick)
	if(sand_taken >= BOT_MINER_SAND_LOAD || !bot_mineral_wanted(MAT_GLASS) || bot_beside_lava(get_turf(bot.owner)))
		return FALSE
	var/turf/open/floor/plating/asteroid/ground
	for(var/direction in GLOB.cardinals)
		var/turf/open/floor/plating/asteroid/near = get_step(bot.owner, direction)
		if(!istype(near) || near.dug)
			continue
		var/area/near_area = near.loc
		if(near_area.outdoors && !is_blocked_turf(near, TRUE))
			ground = near
			break
	if(!ground || !bot.use_tool_on(pick, ground))
		return FALSE
	if(ground.dug)
		sand_taken += 5
		bot.ores_mined += 5
		bot_log(bot, "dug out some sand at [bot_coord(ground)]")
		bot.bot_step_towards(ground)
	wait_for = rand(3, 6)
	return TRUE

/datum/bot_step/paced/dig_out_ore/do_click(datum/bot_brain/bot)
	var/mob/living/carbon/human/H = bot.owner
	if(bot.time_to_head_back())
		bot_log_verbose(bot, "dig_out_ore: time to head back")
		return FALSE
	var/obj/item/pickaxe/pick = bot.find_carried_tool(/obj/item/pickaxe)
	if(!pick)
		bot_log_verbose(bot, "dig_out_ore: no pick on me")
		return FALSE
	if(dig_for_sand(bot, pick))
		return TRUE
	if(!bot_turf_is_ore(seam))
		next_seam()
		if(!seam)
			bot_log_verbose(bot, "dig_out_ore: no seams left here")
			return FALSE
	// Square on, never on the diagonal: bots route on the four sides of a tile, so a tunnel that turns a corner by a diagonal
	// step has no way back along it. Miners dug themselves into pockets like that and stood there until their tanks ran out.
	var/turf/here = get_turf(H)
	var/x_off = seam.x - here.x
	var/y_off = seam.y - here.y
	var/turf/next = get_step(here, abs(x_off) >= abs(y_off) ? (x_off > 0 ? EAST : WEST) : (y_off > 0 ? NORTH : SOUTH))
	if(!next || next == here)
		give_up_on_seam(bot)
		return TRUE
	if(ismineralturf(next))
		if(istype(next, /turf/closed/mineral/gibtonite))
			give_up_on_seam(bot)
			return TRUE
		return dig(bot, pick, next)
	if(!here.bot_reachable_strict(H, next, H.get_idcard(TRUE), TRUE) || !bot.bot_step_towards(next))
		give_up_on_seam(bot)
		return TRUE
	wait_for = rand(2, 4)
	return TRUE

/// One tile of rock, and a step onto where it was: ore lying there goes in the satchel on the way across.
/datum/bot_step/paced/dig_out_ore/proc/dig(datum/bot_brain/bot, obj/item/pickaxe/pick, turf/closed/mineral/rock)
	var/mob/living/carbon/human/H = bot.owner
	var/was_ore = bot_turf_is_ore(rock)
	var/amount = rock.mineralAmt
	if(!bot.use_tool_on(pick, rock))
		bot_log_verbose(bot, "dig_out_ore: couldn't get a swing at [rock] with [pick]")
		return FALSE
	var/turf/now = locate(rock.x, rock.y, rock.z)
	if(ismineralturf(now))
		wait_for = 5 //it wasn't having it: somebody got in the way, say
		return TRUE
	if(was_ore)
		bot.ores_mined += amount
		bot_log(bot, "dug out [amount] ore at [bot_coord(now)]")
	if(H.Adjacent(now))
		bot.bot_step_towards(now)
	wait_for = rand(3, 6)
	return TRUE

/datum/bot_step/paced/dig_out_ore/finish(datum/bot_brain/bot)
	return GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// Ash storms
// ---------------------------------------------------------------------------------------------

// A storm blows in over the surface every five to ten minutes and burns anybody out in it to death inside a minute: 4 burn
// a second, and an explorer suit with the hood up doesn't stop it on this server, whatever it did elsewhere. It's announced
// half a minute ahead (weather/telegraph()), which is as long as anybody needs to get indoors. Nobody can tell an ember fall
// from a storm until it arrives, so an ember fall sends everybody in too, and out again when they see it's harmless.

/// The ash storm on its way to, or blowing over, this level.
/proc/bot_storm_over(z_level)
	for(var/datum/weather/ash_storm/W in SSweather.processing)
		if(!(z_level in W.impacted_z_levels))
			continue
		if(W.stage == STARTUP_STAGE || (W.stage == MAIN_STAGE && !W.aesthetic))
			return W
	return null

/datum/bot_brain/proc/out_in_the_open()
	var/area/A = get_area(owner)
	return A?.outdoors

/datum/bot_brain/proc/is_under_cover(turf/T)
	var/area/A = T.loc
	return !A.outdoors

/datum/bot_duty/shelter_from_storm
	name = "sheltering from the storm"
	tier = BOT_DUTY_URGENT
	priority = 200
	interval_min = 10
	interval_max = 20
	interrupts = TRUE

/datum/bot_duty/shelter_from_storm/should_interrupt(datum/bot_brain/bot)
	if(!bot.on_lavaland() || !bot.out_in_the_open())
		return FALSE
	var/datum/weather/ash_storm/storm = bot_storm_over(bot.owner.z)
	if(!storm)
		return FALSE
	// Still running for it when the storm hits: the capsule, if it hasn't been tried.
	return !istype(bot.current_goal, /datum/bot_goal/shelter_from_storm) || (storm.stage == MAIN_STAGE && storm != bot.capsule_tried_on && bot.find_carried_tool(/obj/item/survivalcapsule))

/datum/bot_duty/shelter_from_storm/try_start(datum/bot_brain/bot)
	if(!bot.on_lavaland() || !bot_storm_over(bot.owner.z))
		return FALSE
	if(bot.out_in_the_open())
		if(bot.pop_shelter())
			return TRUE
		return bot.assign_goal(new /datum/bot_goal/shelter_from_storm())
	bot.holding_duty = src
	return FALSE

/// The survival capsule from the locker, when the storm is on it and a roof is further off than it can run. It takes five seconds
/// and comes down around the bot, so it needs a clear patch of ground.
/datum/bot_brain/proc/pop_shelter()
	var/datum/weather/ash_storm/storm = bot_storm_over(owner.z)
	var/obj/docking_port/stationary/dock = bot_mining_dock(owner.z)
	if(storm == capsule_tried_on || (storm?.stage != MAIN_STAGE && (!dock || get_dist(owner, dock) <= BOT_MINER_RANGE)))
		return FALSE
	// The one go a storm: on rough ground it won't open, and a miner who stood there trying it again burned to death in sight of
	// the base. Nor when the door is a few steps off.
	capsule_tried_on = storm
	for(var/turf/T in range(BOT_MINER_NEAR_COVER, owner))
		var/area/A = T.loc
		if(!T.density && !A.outdoors)
			return FALSE
	var/obj/item/survivalcapsule/capsule = find_carried_tool(/obj/item/survivalcapsule)
	if(!capsule || capsule.used || !ready_in_hand(capsule))
		return FALSE
	bot_log(src, "the storm's here and there's no roof near: popping [capsule]")
	stop_pursuit()
	INVOKE_ASYNC(capsule, TYPE_PROC_REF(/obj/item, attack_self), owner)
	hold_still_for(7 SECONDS)
	return TRUE

/datum/bot_duty/shelter_from_storm/keep_holding(datum/bot_brain/bot)
	return bot.on_lavaland() && !bot.out_in_the_open() && bot_storm_over(bot.owner.z)

/datum/bot_goal/shelter_from_storm
	lawful = TRUE
	never_rests = TRUE
	braves_bad_air = TRUE
	doing = "getting out of the storm"

/datum/bot_goal/shelter_from_storm/resolve_target(datum/bot_brain/bot)
	target = bot.nearest_on_foot(TYPE_PROC_REF(/datum/bot_brain, is_under_cover))

/datum/bot_goal/shelter_from_storm/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/mining/S = new
	S.steps = list(new /datum/bot_step/move_to())
	return list(S)

/datum/bot_goal/shelter_from_storm/on_success(datum/bot_brain/bot)
	bot.holding_duty = bot_duty_of(/datum/bot_duty/shelter_from_storm)

// ---------------------------------------------------------------------------------------------
// Delivering
// ---------------------------------------------------------------------------------------------

/// The ore redemption machine nearest the dock that's working.
/datum/bot_brain/proc/find_orm()
	var/obj/machinery/mineral/ore_redemption/best
	var/best_dist
	for(var/obj/machinery/mineral/ore_redemption/O as anything in bot_instances_of(/obj/machinery/mineral/ore_redemption))
		if(QDELETED(O) || O.z != owner.z || (O.stat & (BROKEN|NOPOWER)) || O.panel_open)
			continue
		var/dist = get_dist(owner, O)
		if(!best || dist < best_dist)
			best = O
			best_dist = dist
	return best

/datum/bot_goal/deliver_ore
	lawful = TRUE
	doing = "dropping off ore"

/// The tile on the machine's input side: that's what it takes ore from. Aboard the shuttle a miner takes whatever way off there
/// is: on Delta something at the dock doors now and then left the everyday route closed, with the doors standing open, and a miner
/// sat aboard for the rest of the round and missed the evacuation.
/datum/bot_goal/deliver_ore/resolve_target(datum/bot_brain/bot)
	var/obj/machinery/mineral/ore_redemption/O = bot.find_orm()
	target = O && get_step(O, O.input_dir)
	lawful = !bot_aboard_mining_shuttle(bot.owner)

/datum/bot_goal/deliver_ore/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/mining/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/empty_satchel())
	return list(S)

/datum/bot_goal/deliver_ore/on_success(datum/bot_brain/bot)
	bot.continue_mining_round()

/// Satchel in hand and upended, then back in the pocket: it only picks ore up where it's worn.
/datum/bot_step/empty_satchel/execute(datum/bot_brain/bot)
	var/mob/living/carbon/human/H = bot.owner
	var/obj/item/storage/bag/ore/bag = bot.ore_satchel()
	if(!bag || !bot.ready_in_hand(bag))
		return GOAL_STEP_FAIL
	var/load = bot.ore_in_satchel()
	bot.human_pause(H)
	if(QDELETED(bag))
		return GOAL_STEP_FAIL
	bot.telemetry_ui_action(bag, "empty satchel")
	SEND_SIGNAL(bag, COMSIG_TRY_STORAGE_QUICK_EMPTY, get_turf(H))
	var/left = bot.ore_in_satchel()
	bot.ores_delivered += load - left
	bot_log(bot, "emptied [load - left] ore out for the machine")
	if(!QDELETED(bag) && (bag in H.held_items))
		if(!H.equip_to_slot_if_possible(bag, ITEM_SLOT_RPOCKET, FALSE, TRUE, TRUE) && !H.equip_to_slot_if_possible(bag, ITEM_SLOT_LPOCKET, FALSE, TRUE, TRUE))
			H.equip_to_slot_if_possible(bag, ITEM_SLOT_BELT, FALSE, TRUE, TRUE)
	if(load == left)
		return GOAL_STEP_FAIL
	if(load >= 10 && !bot.gym_scripted && prob(60))
		bot.say_after_typing(";[pick("Just dropped [load] ore off at the redemption machine.", "[load] ore in the machine. More on the way.", "Fresh load in the redemption machine, [load] ore.")]")
	return GOAL_STEP_SUCCESS

#undef BOT_MINER_ENOUGH_SHEETS
#undef BOT_MINER_SAND_LOAD
#undef BOT_MINER_LOAD
#undef BOT_MINER_TRIP_LIMIT
#undef BOT_MINER_PROSPECT_REACH
#undef BOT_MINER_RANGE
#undef BOT_MINER_HURT
#undef BOT_MINER_SHORT_OF_BREATH
#undef BOT_MINER_NEAR_COVER
#undef BOT_MINER_SEAM_REST
#undef BOT_MINER_SCANNER_RANGE
#undef BOT_MINER_MANUAL_SCANNER_RANGE
