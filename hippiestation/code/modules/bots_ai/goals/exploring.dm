// Exploring: what's out there. A bot out to explore this part of the shift (bot_pursuits.dm) goes down to Lavaland on the mining
// shuttle, has a look round one of the ruins near the base, takes what's lying about worth having, and brings it home: the user's
// "have some of them explore ruins and get the spoils there".
//
//  - access: the shuttle and the miners' lockers are Mining's. Anybody else asks the HoP for it, card left at the door, the same
//    as a transfer (bot_hopping.dm), and goes without if nobody comes.
//  - kit: a kinetic accelerator from the miners' lockers for the wildlife (mind_fauna() shoots with it), and the mask and tank out
//    of the survival box, as a miner dresses (goals/mining.dm). Hurt, short of breath, or loaded up, it heads back.
//  - the ruins are where the map put them (GLOB.ruin_landmarks), the nearest the base first, and one already seen is left for
//    somebody else. Inside, it opens what can be opened and takes what's worth taking (bot_ruin_loot()), up to a bagful.
//  - home, it says what it found. Risk and reward: nobody goes with the shuttle called, or hurt, or without a gun.

/// How long it stays down there.
#define BOT_EXPLORE_TRIP (12 MINUTES)
/// How far from the dock it walks to a ruin.
#define BOT_EXPLORE_RANGE 110 //routes stop at 250 steps, and most ruins further out are behind rock nobody digs through yet
/// Things it brings back before it calls it a haul.
#define BOT_EXPLORE_HAUL 5

/// Ruin landmarks somebody's been through already this round.
GLOBAL_LIST_EMPTY(bot_ruins_explored)
/// Until when there's nothing down there anybody can get to: nobody else goes down to find that out.
GLOBAL_VAR_INIT(bot_lavaland_done_until, 0)

/datum/bot_brain
	var/exploring_since = 0
	/// What it's found, weakrefs, until it's back to say so.
	var/list/spoils
	var/next_explore_access_ask = 0
	var/explore_blocked_until = 0

/datum/bot_duty/explore
	name = "exploring"
	tier = BOT_DUTY_WORK
	priority = 5
	interval_min = 40
	interval_max = 100

/datum/bot_duty/explore/applies_to(datum/bot_brain/bot)
	return bot.pursuit == BOT_PURSUIT_EXPLORE && !bot.is_security_job()

/datum/bot_duty/explore/next_look(datum/bot_brain/bot)
	return rand(interval_min, interval_max) //once it's set out, the next thing follows straight on

/datum/bot_duty/explore/try_start(datum/bot_brain/bot)
	if(bot.state == BOT_STATE_GOAL && bot.current_goal)
		return FALSE
	if(bot.on_lavaland())
		if(bot_storm_over(bot.owner.z))
			return FALSE
		// The explorer suit out of the outpost's suit storage before going out, as a miner goes: armour against what's out there.
		// Explorers walked out in their jumpsuits, and a watcher or a goliath had one in about the time it takes to read this.
		if(!bot.explore_time_up() && !istype(bot.owner.wear_suit, /obj/item/clothing/suit/hooded/explorer))
			var/obj/item/clothing/suit/hooded/explorer/carried = bot.find_carried_tool(/obj/item/clothing/suit/hooded/explorer)
			if(carried)
				return bot.assign_goal(new /datum/bot_goal/dress_for_lavaland())
			if(world.time >= bot.explorer_suit_tried_until)
				bot.explorer_suit_tried_until = world.time + 10 MINUTES
				var/obj/machinery/suit_storage_unit/unit = bot.explorer_suit_storage()
				if(unit && bot.assign_goal(new /datum/bot_goal/explorer_suit_up(unit)))
					return TRUE
		var/obj/effect/landmark/ruin/R = bot.explore_time_up() ? null : bot.ruin_to_explore()
		if(!R)
			if(!bot.explore_time_up())
				GLOB.bot_lavaland_done_until = world.time + 20 MINUTES //nothing left down here to get to
			return bot.assign_goal(new /datum/bot_goal/ride_mining_shuttle/exploring("mining_home"))
		return bot.assign_goal(new /datum/bot_goal/explore_ruin(R))
	if(!is_station_level(bot.owner.z) || world.time < bot.explore_blocked_until)
		return FALSE
	if(length(bot.spoils))
		bot.show_off_spoils()
	if(bot.stashed_bag && bot.take_back_bag()) //goals/space_ruins.dm: the backpack left in EVA for the jetpack
		return TRUE
	if(length(bot.spoils_to_deliver) && bot.deliver_next_spoil())
		return TRUE
	if(bot.pursuit != BOT_PURSUIT_EXPLORE || bot_going_home_soon() || bot.owner.health < bot.owner.maxHealth * 0.8)
		return FALSE
	// Lavaland is the miners' (the user's ruling, 2026-11-04): about one explorer a batch from the station was killed by a goliath
	// down there. Anybody else out exploring goes for the space ruins instead.
	if(!bot.is_miner())
		return bot.try_space_ruin()
	if(world.time < GLOB.bot_lavaland_done_until)
		bot.pick_pursuit("nothing left to explore down there") //maintenance is still there for an explorer (maint_crawl), or something else
		return FALSE
	if(!bot.has_mining_access())
		if(world.time < bot.next_explore_access_ask)
			return FALSE
		bot.next_explore_access_ask = world.time + 10 MINUTES
		if(!bot_find_card_granter(bot.owner)) //nobody to give it: it doesn't go, and keeps its card
			bot.explore_blocked_until = world.time + 10 MINUTES
			return FALSE
		return bot.assign_goal(new /datum/bot_goal/job_transfer/access(list(ACCESS_MINING, ACCESS_MINING_STATION, ACCESS_MAILSORTING), "mining"))
	var/kit_needed = !bot.find_carried_tool(/obj/item/gun/energy/kinetic_accelerator) ? /obj/item/gun/energy/kinetic_accelerator : (!bot.find_carried_tool(/obj/item/pickaxe) ? /obj/item/pickaxe : null)
	if(kit_needed)
		var/datum/bot_goal/acquire_item_type/fetch = new()
		fetch.item_type = kit_needed
		fetch.lawful = TRUE
		if(!bot.assign_goal(fetch))
			bot.explore_blocked_until = world.time + 5 MINUTES //none to be had: another time
			return FALSE
		return TRUE
	if(!bot.ready_for_lavaland())
		if(world.time < bot.mining_gear_blocked_until) //no mask or no tank to be had (dress_for_lavaland's on_give_up()): another time
			bot.explore_blocked_until = world.time + 5 MINUTES
			return FALSE
		return bot.assign_goal(new /datum/bot_goal/dress_for_lavaland())
	if(!bot.exploring_since)
		bot_say(bot.owner, pick(";Heading down to Lavaland, gonna check out a ruin.", "Off exploring. Back in a bit.", ";Anyone want anything from Lavaland?"))
	return bot.assign_goal(new /datum/bot_goal/ride_mining_shuttle/exploring("mining_away"))

/datum/bot_brain
	var/explorer_suit_tried_until = 0

/// The mining outpost's suit storage nearest the bot, suit in it or not: where somebody out on Lavaland runs back to.
/datum/bot_brain/proc/lavaland_outpost()
	var/obj/machinery/suit_storage_unit/mining/nearest
	for(var/obj/machinery/suit_storage_unit/mining/U as anything in bot_instances_of(/obj/machinery/suit_storage_unit/mining))
		if(!QDELETED(U) && U.z == owner.z && (!nearest || get_dist(owner, U) < get_dist(owner, nearest)))
			nearest = U
	return nearest

/// The nearest suit storage unit down here with an explorer suit still in it, that it can walk to.
/datum/bot_brain/proc/explorer_suit_storage()
	var/obj/machinery/suit_storage_unit/best
	for(var/obj/machinery/suit_storage_unit/mining/U as anything in bot_instances_of(/obj/machinery/suit_storage_unit/mining))
		if(QDELETED(U) || U.z != owner.z || !istype(U.suit, /obj/item/clothing/suit/hooded/explorer) || U.locked || (U.stat & (BROKEN|NOPOWER)))
			continue
		if(best && get_dist(owner, U) >= get_dist(owner, best))
			continue
		if(can_walk_lawfully_to(U))
			best = U
	return best

/// Over to the suit storage, the suit out of it and on: only the suit (a raid for EVA gear takes the lot, and with its hands full the
/// suit went in the bag or on the floor and never on).
/datum/bot_goal/explorer_suit_up
	lawful = TRUE
	braves_bad_air = TRUE
	doing = "getting an explorer suit on"

/datum/bot_goal/explorer_suit_up/New(obj/machinery/suit_storage_unit/U)
	. = ..()
	target = U

/datum/bot_goal/explorer_suit_up/resolve_target(datum/bot_brain/bot)
	var/obj/machinery/suit_storage_unit/U = target
	if(QDELETED(U) || !istype(U.suit, /obj/item/clothing/suit/hooded/explorer))
		target = null

/datum/bot_goal/explorer_suit_up/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/robotics/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/explorer_suit_up())
	return list(S)

/datum/bot_goal/explorer_suit_up/on_success(datum/bot_brain/bot)
	var/datum/bot_duty/explore/duty = bot_duty_of(/datum/bot_duty/explore)
	bot.continue_goal_chain(CALLBACK(duty, TYPE_PROC_REF(/datum/bot_duty, try_start), bot))

/// The unit's door, its "dispense suit" (it lands on the unit's tile, as the panel does it), picked up and put on.
/datum/bot_step/explorer_suit_up/execute(datum/bot_brain/bot)
	var/obj/machinery/suit_storage_unit/U = bot.current_goal?.target
	if(istype(bot.owner.wear_suit, /obj/item/clothing/suit/hooded/explorer))
		return GOAL_STEP_SUCCESS //got one on since, on the way over
	if(!istype(U) || QDELETED(U) || !bot.owner.Adjacent(U))
		return GOAL_STEP_FAIL
	bot.human_pause(U)
	if(QDELETED(U) || !bot.owner.Adjacent(U))
		return GOAL_STEP_FAIL
	bot.owner.face_atom(U)
	if(!U.state_open)
		bot.telemetry_ui_action(U, "door")
		U.open_machine(0)
		U.update_icon()
	var/obj/item/clothing/suit/hooded/explorer/suit = U.suit
	if(!istype(suit))
		return GOAL_STEP_FAIL
	bot.telemetry_ui_action(U, "dispense suit")
	U.suit = null
	suit.forceMove(U.loc)
	U.update_icon()
	if(bot.try_pickup_target(suit))
		bot.wear(suit, ITEM_SLOT_OCLOTHING)
	// By what's on, not wear()'s answer: the equip under it can say no and have put it on all the same.
	if(bot.owner.wear_suit != suit)
		bot_log(bot, "couldn't get [suit] on over [bot.owner.wear_suit || "nothing"]")
		return GOAL_STEP_FAIL
	bot_log(bot, "put on [suit]")
	return GOAL_STEP_SUCCESS

/datum/bot_brain/proc/has_mining_access()
	if(is_miner())
		return TRUE
	var/obj/item/card/id/card = owner.get_idcard(FALSE)
	return card && (ACCESS_MINING in card.access)

/datum/bot_brain/proc/explore_time_up()
	if(bot_going_home_soon() || length(spoils) >= BOT_EXPLORE_HAUL || pursuit != BOT_PURSUIT_EXPLORE)
		return TRUE
	if(exploring_since && world.time > exploring_since + BOT_EXPLORE_TRIP)
		return TRUE
	return owner.health < owner.maxHealth * 0.6 || owner.getOxyLoss() > 20

/// The nearest ruin down here nobody's been through, near enough the base to walk to and back.
/datum/bot_brain/proc/ruin_to_explore()
	var/obj/machinery/computer/shuttle/mining/dock = bot_mining_dock_console(owner.z)
	var/list/candidates = list()
	for(var/obj/effect/landmark/ruin/R as anything in GLOB.ruin_landmarks)
		if(QDELETED(R) || R.z != owner.z || GLOB.bot_ruins_explored[R] || bot_ruin_deadly(R))
			continue
		var/dist = get_dist(dock || owner, R)
		if(dist <= BOT_EXPLORE_RANGE)
			candidates[R] = dist
	var/tries = 0
	while(length(candidates) && tries++ < 2)
		var/obj/effect/landmark/ruin/nearest
		for(var/obj/effect/landmark/ruin/R as anything in candidates)
			if(!nearest || candidates[R] < candidates[nearest])
				nearest = R
		candidates -= nearest
		var/turf/spot = bot_ruin_spot(nearest)
		// With a pick, the rock between is no obstacle: it's dug through on the way (head_for_ruin), the way a miner tunnels.
		if(spot && (find_carried_tool(/obj/item/pickaxe) || can_walk_lawfully_to(spot)))
			return nearest
		bot_log(src, "can't get to [nearest.ruin_template?.name || "a ruin"] at [bot_coord(get_turf(nearest))] on foot ([spot ? "no way there" : "nowhere to stand in it"])")
		GLOB.bot_ruins_explored[nearest] = TRUE //nobody's getting in there on foot
	bot_log(src, "no ruin to explore: [length(GLOB.ruin_landmarks)] on the map, [length(candidates)] left in reach")
	return null

/// Where something lives that kills whoever walks in: the megafauna's arenas, the ash walkers' nest. Nobody who means to come back goes
/// there for the fun of it.
/proc/bot_ruin_deadly(obj/effect/landmark/ruin/R)
	var/name = lowertext(R.ruin_template?.name)
	for(var/word in list("hierophant", "blood-drunk", "colossus", "bubblegum", "legion", "ash walker", "drake", "dragon", "necropolis", "tendril"))
		if(findtext(name, word))
			return TRUE
	return FALSE

/// Somewhere to stand in a ruin: the middle of it, or the open floor nearest the middle.
/proc/bot_ruin_spot(obj/effect/landmark/ruin/R)
	var/turf/middle = get_turf(R)
	if(!middle)
		return null
	if(isopenturf(middle) && !is_blocked_turf(middle, TRUE))
		return middle
	for(var/turf/open/T in range(4, middle))
		if(!is_blocked_turf(T, TRUE) && !istype(T, /turf/open/lava))
			return T
	return null

/// Back aboard, a word about what it brought.
/datum/bot_brain/proc/show_off_spoils()
	var/list/names = list()
	for(var/datum/weakref/ref as anything in spoils)
		var/obj/item/I = ref.resolve()
		if(I && (I in owner.GetAllContents()))
			names |= I.name
			LAZYADD(spoils_to_deliver, ref) //then what it's for: kept, given to whoever needs it, or sold (deliver_next_spoil())
	spoils = null
	exploring_since = 0
	if(length(names))
		var/where = is_miner() ? "Lavaland" : "space" //everybody else's ruins are out in space (goals/space_ruins.dm)
		bot_say(owner, pick(";Back from [where]. Found [english_list(names)] in a ruin!", ";Back from the ruins with [english_list(names)].", "Look what I found out there: [english_list(names)]."))
		bot_tally("came back with spoils")

// ---------------------------------------------------------------------------------------------
// What the finds are for
// ---------------------------------------------------------------------------------------------

// The user's ruling (2026-11-04): what's brought back is kept and used, given to whoever needs it, or sold at Cargo.
//  - Minerals, cash and coins go to Cargo to sell: on to the cargo shuttle if it can get to it, on Cargo's desk if not.
//  - Circuit boards and disks go to Science, medical kits and hyposprays to Medbay (unless it's Medical itself), a space suit back to EVA.
//  - Guns, armour and anything heavy are kept by those who'd use them (Security, hunters, powergamers, the robust, the paranoid) and
//    handed in to Security by everybody else.
//  - The rest is kept, and worn where there's a slot free for it.

/datum/bot_brain
	/// Weakrefs of what it brought back and hasn't seen to yet.
	var/list/spoils_to_deliver

/// Where a find goes: an atom to take it to, or null to keep it.
/datum/bot_brain/proc/spoil_destination(obj/item/I)
	if(istype(I, /obj/item/stack/sheet/mineral) || istype(I, /obj/item/stack/ore) || istype(I, /obj/item/stack/spacecash) || istype(I, /obj/item/coin))
		return cargo_shuttle_floor() || nearest_desk_in(/area/quartermaster)
	if(istype(I, /obj/item/circuitboard) || istype(I, /obj/item/disk))
		return is_science_job() ? null : nearest_desk_in(/area/science)
	if(istype(I, /obj/item/storage/firstaid) || istype(I, /obj/item/reagent_containers/hypospray))
		return is_medical_job() ? null : nearest_desk_in(/area/medical)
	if(istype(I, /obj/item/clothing/suit/space))
		return eva_suit_storage() || nearest_desk_in(/area/ai_monitored/storage/eva)
	if(istype(I, /obj/item/gun) || istype(I, /obj/item/clothing/suit/armor) || I.force >= 15)
		if(is_security_job() || playstyle == BOT_STYLE_HUNTER || playstyle == BOT_STYLE_POWERGAMER || plays_robust() || is_paranoid())
			return null
		return nearest_desk_in(/area/security)
	return null

/// The nearest table in that sort of place that it can walk up to: a department's front desk, from the public side, when it has no
/// access further in.
/datum/bot_brain/proc/nearest_desk_in(area_type)
	var/list/by_dist = list()
	for(var/obj/structure/table/T as anything in bot_instances_of(/obj/structure/table))
		if(QDELETED(T) || T.z != owner.z || get_dist(owner, T) > 150)
			continue
		if(gym_run ? get_area(T) != get_area(owner) : !istype(get_area(T), area_type))
			continue //in the Bot Gym, the arena's table is everybody's desk
		by_dist[T] = get_dist(owner, T)
	sortTim(by_dist, GLOBAL_PROC_REF(cmp_numeric_asc), TRUE)
	var/tries = 0
	for(var/obj/structure/table/T as anything in by_dist)
		if(can_walk_lawfully_to(T))
			return T
		if(++tries >= 4)
			break
	return null

/// A free tile aboard the cargo shuttle while it's docked at the station, if this bot can walk on to it: what's put aboard is sold when
/// it's sent.
/datum/bot_brain/proc/cargo_shuttle_floor()
	var/obj/docking_port/mobile/supply/S = SSshuttle.supply
	if(!S || S.mode != SHUTTLE_IDLE || !is_station_level(S.z))
		return null
	for(var/area/A in S.shuttle_areas)
		for(var/turf/open/floor/T in A)
			if(!is_blocked_turf(T, TRUE) && can_walk_lawfully_to(T))
				return T
	return null

/// The next find seen to: off to wherever it goes, or kept (and put on, if there's a slot for it).
/datum/bot_brain/proc/deliver_next_spoil()
	while(length(spoils_to_deliver))
		var/datum/weakref/ref = spoils_to_deliver[1]
		spoils_to_deliver.Cut(1, 2)
		var/obj/item/I = ref.resolve()
		if(!I || !(I in owner.GetAllContents()))
			continue
		var/atom/where = spoil_destination(I)
		if(!where)
			keep_spoil(I)
			continue
		return assign_goal(new /datum/bot_goal/deliver_spoil(I, where))
	return FALSE

/// Kept: on, if it's something worn and the slot's free, and in the bag otherwise.
/datum/bot_brain/proc/keep_spoil(obj/item/I)
	var/slot
	if(istype(I, /obj/item/clothing/suit/armor) && !owner.wear_suit)
		slot = ITEM_SLOT_OCLOTHING
	else if(istype(I, /obj/item/clothing/glasses) && !owner.glasses)
		slot = ITEM_SLOT_EYES
	else if(istype(I, /obj/item/clothing/shoes) && owner.shoes && istype(owner.shoes, /obj/item/clothing/shoes/sneakers))
		slot = ITEM_SLOT_FEET
	if(slot && wear(I, slot))
		bot_log(src, "keeping [I], and wearing it")
	else
		bot_log(src, "keeping [I]")

/datum/bot_goal/deliver_spoil
	lawful = TRUE
	doing = "taking something I found where it's wanted"
	var/datum/weakref/item_ref

/datum/bot_goal/deliver_spoil/New(obj/item/I, atom/where)
	. = ..()
	item_ref = WEAKREF(I)
	target = where

/datum/bot_goal/deliver_spoil/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/robotics/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/hand_in_spoil())
	return list(S)

/datum/bot_goal/deliver_spoil/on_success(datum/bot_brain/bot)
	var/datum/bot_duty/explore/duty = bot_duty_of(/datum/bot_duty/explore)
	bot.continue_goal_chain(CALLBACK(duty, TYPE_PROC_REF(/datum/bot_duty, try_start), bot))

/// On the table or the unit with a click, or down on the cargo shuttle's floor, and a word to whoever it's for.
/datum/bot_step/hand_in_spoil/execute(datum/bot_brain/bot)
	var/datum/bot_goal/deliver_spoil/G = bot.current_goal
	var/obj/item/I = G?.item_ref?.resolve()
	var/atom/where = G?.target
	if(!I || !where || !(I in bot.owner.GetAllContents()))
		return GOAL_STEP_FAIL
	if(isturf(where))
		if(get_turf(bot.owner) != where && !bot.owner.Adjacent(where))
			return GOAL_STEP_FAIL
		if(!bot.ready_in_hand(I))
			return GOAL_STEP_FAIL
		bot.human_pause(where)
		bot.owner.dropItemToGround(I)
		bot_say(bot.owner, pick(";Cargo, left [I] on your shuttle to sell.", ";Put [I] on the cargo shuttle, Cargo. Should fetch something."))
		bot_tally("finds sold")
		return GOAL_STEP_SUCCESS
	if(!bot.owner.Adjacent(where) || !bot.ready_in_hand(I))
		return GOAL_STEP_FAIL
	bot.human_pause(where)
	if(istype(where, /obj/structure/table))
		bot.use_item_on(I, where) //on to the table, the way anything's put on one
	else
		bot.owner.dropItemToGround(I) //by the suit storage
	var/area/A = get_area(where)
	bot_say(bot.owner, pick(";Left [I] at [A.name] for you. Found it in a ruin.", ";[A.name], there's [I] on your desk. Thought you'd want it.", "Dropping this off: [I]."))
	bot_tally("finds handed in")
	return GOAL_STEP_SUCCESS

/datum/bot_goal/ride_mining_shuttle/exploring/on_success(datum/bot_brain/bot)
	if(destination == "mining_away" && bot.on_lavaland())
		bot.exploring_since = world.time
	var/datum/bot_duty/explore/duty = bot_duty_of(/datum/bot_duty/explore)
	bot.continue_goal_chain(CALLBACK(duty, TYPE_PROC_REF(/datum/bot_duty, try_start), bot))

// ---------------------------------------------------------------------------------------------
// In a ruin
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/explore_ruin
	lawful = TRUE
	braves_bad_air = TRUE //dressed for it before it came down (ready_for_lavaland()), the same as a miner (goals/mining.dm)
	doing = "exploring a ruin"
	var/obj/effect/landmark/ruin/ruin

/datum/bot_goal/explore_ruin/New(obj/effect/landmark/ruin/R)
	. = ..()
	ruin = R

/datum/bot_goal/explore_ruin/resolve_target(datum/bot_brain/bot)
	target = QDELETED(ruin) ? null : bot_ruin_spot(ruin)

/datum/bot_goal/explore_ruin/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/explore_ruin/S = new
	S.steps = list(new /datum/bot_step/paced/head_for_ruin(), new /datum/bot_step/paced/loot_ruin())
	return list(S)

/datum/bot_goal/explore_ruin/on_success(datum/bot_brain/bot)
	GLOB.bot_ruins_explored[ruin] = TRUE
	bot_log(bot, "been through [ruin.ruin_template?.name || "a ruin"]")
	bot_tally("ruins explored")

/datum/bot_goal/explore_ruin/on_give_up(datum/bot_brain/bot)
	GLOB.bot_ruins_explored[ruin] = TRUE

/datum/bot_strategy/explore_ruin/is_feasible(datum/bot_brain/bot)
	return !!bot.current_goal?.target

/// Over the ground to it, the way a person crosses Lavaland: straight at it, through the rock with the pick, round lava and over
/// what's open, and the last few tiles by the ordinary route in. Lavaland's ruins sit in rock or out past the routes' reach (they
/// stop at 250 steps); every one the explorers tried by route alone was out of it.
/datum/bot_step/paced/head_for_ruin
	max_clicks = 400
	var/stuck = 0
	/// Whether it has looked for the walkable ground nearest the ruin from where it stands now.
	var/looked = FALSE
	/// Turf -> times it has stepped on to it on the way.
	var/list/trodden

/datum/bot_step/paced/head_for_ruin/start(datum/bot_brain/bot)
	stuck = 0
	looked = FALSE
	trodden = list()
	var/turf/spot = get_turf(bot.current_goal?.target)
	return spot && bot.owner.z == spot.z

/datum/bot_step/paced/head_for_ruin/do_click(datum/bot_brain/bot)
	var/turf/spot = get_turf(bot.current_goal?.target)
	var/mob/living/carbon/human/H = bot.owner
	var/turf/here = get_turf(H)
	if(!spot || !here || bot.explore_time_up() || H.incapacitated())
		return FALSE
	if(get_dist(here, spot) <= 1 || here.z != spot.z)
		return FALSE //there, or carried off by the shuttle
	if(bot.pursuing_kind)
		wait_for = 10 //walking it, by route
		return TRUE
	if(get_dist(here, spot) <= 6 && bot.pursue(spot, "follow", force = TRUE))
		wait_for = 10
		return TRUE
	// Out of the shuttle and the outpost, round a wall, along a path: as far as the ground goes towards it, before the pick comes out.
	// Every explorer stood at the shuttle's console with its walls on all sides and called it "no way on".
	if(!looked)
		looked = TRUE
		var/turf/nearest = bot.nearest_walkable_toward(spot)
		if(nearest && get_dist(nearest, spot) < get_dist(here, spot) - 2 && bot.pursue(nearest, "follow", force = TRUE))
			wait_for = 10
			return TRUE
	var/obj/item/pickaxe/pick = bot.find_carried_tool(/obj/item/pickaxe)
	var/x_off = spot.x - here.x
	var/y_off = spot.y - here.y
	var/major = abs(x_off) >= abs(y_off) ? (x_off > 0 ? EAST : WEST) : (y_off > 0 ? NORTH : SOUTH)
	var/minor = abs(x_off) >= abs(y_off) ? (y_off > 0 ? NORTH : SOUTH) : (x_off > 0 ? EAST : WEST)
	for(var/direction in list(major, minor, turn(major, 90), turn(major, -90)))
		var/turf/next = get_step(here, direction)
		if(!next || bot_turf_is_deadly(next) || istype(next, /turf/closed/mineral/gibtonite))
			continue
		if(ismineralturf(next))
			if(!pick || !bot.ready_in_hand(pick) || !bot.use_tool_on(pick, next))
				continue
			wait_for = rand(3, 6)
			stuck = 0
			looked = FALSE
			return TRUE
		// Not back over ground it has been over twice already. With lava ahead and to the side, the best step from each of two tiles
		// was the other: two explorers paced the same two tiles at the edge of a lava river for most of a minute, and one burned to
		// death there.
		if(trodden[next] >= 2)
			continue
		if(here.bot_reachable_strict(H, next, H.get_idcard(TRUE), TRUE) && bot.bot_step_towards(next))
			trodden[next] = trodden[next] + 1
			wait_for = rand(2, 4)
			stuck = 0
			looked = FALSE
			return TRUE
	if(++stuck > 5)
		bot_log(bot, "no way on to the ruin from [bot_coord(here)]")
		return FALSE
	wait_for = 10
	return TRUE

/// The tile it can walk to by an ordinary route that's nearest `spot`, from a flood of the ground round about.
/datum/bot_brain/proc/nearest_walkable_toward(turf/spot, limit = 900)
	var/turf/start = get_turf(owner)
	if(!start || !spot)
		return null
	var/obj/item/card/id/id_card = route_card()
	var/list/seen = list()
	seen[start] = TRUE
	var/list/queue = list(start)
	var/at = 1
	var/turf/best = start
	var/best_dist = (start.x - spot.x) ** 2 + (start.y - spot.y) ** 2
	while(at <= length(queue) && length(queue) < limit)
		var/turf/T = queue[at++]
		for(var/d in GLOB.cardinals)
			var/turf/next = get_step(T, d)
			if(!next || seen[next] || !T.bot_reachable_strict(owner, next, id_card, TRUE))
				continue
			seen[next] = TRUE
			queue += next
			var/dist = (next.x - spot.x) ** 2 + (next.y - spot.y) ** 2
			if(dist < best_dist)
				best = next
				best_dist = dist
	return best

/datum/bot_step/paced/head_for_ruin/finish(datum/bot_brain/bot)
	var/turf/spot = get_turf(bot.current_goal?.target)
	return (spot && get_dist(bot.owner, spot) <= 6) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// What's worth taking from a ruin: something that'd help, or sells, or is just good to have. Not rubbish, not the furniture.
/proc/bot_ruin_loot(obj/item/I)
	if(I.anchored || HAS_TRAIT(I, TRAIT_NODROP) || is_type_in_typecache(I, GLOB.bot_litter_types))
		return FALSE
	if(istype(I, /obj/item/gun) || istype(I, /obj/item/storage/firstaid) || istype(I, /obj/item/reagent_containers/hypospray) || istype(I, /obj/item/clothing/suit/space) || istype(I, /obj/item/clothing/suit/armor) || istype(I, /obj/item/disk) || istype(I, /obj/item/organ/heart/cursed) || istype(I, /obj/item/circuitboard))
		return TRUE
	if(istype(I, /obj/item/stack/sheet/mineral) || istype(I, /obj/item/stack/ore/diamond) || istype(I, /obj/item/stack/ore/gold) || istype(I, /obj/item/stack/ore/bluespace_crystal) || istype(I, /obj/item/stack/spacecash) || istype(I, /obj/item/coin))
		return TRUE
	return I.force >= 15 || istype(I, /obj/item/storage/toolbox) || istype(I, /obj/item/clothing/glasses/thermal) || istype(I, /obj/item/clothing/shoes/magboots)

/// A look round: opens what can be opened nearby, walks over to what's worth taking and takes it, until there's nothing more or the
/// bag's full.
/datum/bot_step/paced/loot_ruin
	max_clicks = 14
	var/list/opened
	/// What it's walking over to, how many looks it's had at getting there, and what it's given up on.
	var/atom/heading_for
	var/looks = 0
	var/list/skipped

/datum/bot_step/paced/loot_ruin/start(datum/bot_brain/bot)
	opened = list()
	skipped = list()
	heading_for = null
	return TRUE

/// Walking over to something: a few looks at getting there, then it's let be.
/datum/bot_step/paced/loot_ruin/proc/go_to(datum/bot_brain/bot, atom/A)
	if(heading_for != A)
		heading_for = A
		looks = 0
	if(++looks > 6)
		skipped += A
		heading_for = null
		return FALSE
	bot.pursue(A, "follow", force = TRUE) //not "goal": that one's arrival ends the step (on_goal_pursuit_finished()), after the first crate
	wait_for = 10
	return TRUE

/datum/bot_step/paced/loot_ruin/do_click(datum/bot_brain/bot)
	if(length(bot.spoils) >= BOT_EXPLORE_HAUL || bot.explore_time_up())
		return FALSE
	if(bot.pursuing_kind)
		wait_for = 10
		return TRUE
	// Something to open first: a closet or a crate, shut, that it hasn't tried.
	for(var/obj/structure/closet/C in view(5, bot.owner))
		if(C.opened || C.locked || C.welded || (C in opened) || (C in skipped))
			continue
		if(!bot.owner.Adjacent(C))
			if(go_to(bot, C))
				return TRUE
			continue
		opened += C
		bot.human_pause(C)
		C.open(bot.owner)
		return TRUE
	var/obj/item/best
	var/list/have = list()
	for(var/datum/weakref/ref as anything in bot.spoils)
		var/obj/item/kept = ref.resolve()
		if(kept)
			have[kept.type] = TRUE
	for(var/obj/item/I in view(6, bot.owner))
		if(have[I.type]) //one of each: an explorer came back with four of the same tool
			continue
		if(isturf(I.loc) && !(I in skipped) && bot_ruin_loot(I) && !bot.taken_by_another(I) && (!best || get_dist(bot.owner, I) < get_dist(bot.owner, best)))
			best = I
	if(!best)
		return FALSE
	if(!bot.owner.Adjacent(best))
		return go_to(bot, best) || TRUE
	bot.try_pickup_target(best)
	if(best.loc == bot.owner)
		bot.put_away(best)
		LAZYADD(bot.spoils, WEAKREF(best))
		bot_log(bot, "found [best] in a ruin")
		bot_tally("ruin loot")
	return TRUE

// ---------------------------------------------------------------------------------------------
// Asking the HoP for the access
// ---------------------------------------------------------------------------------------------

/// To the HoP's door, card down, a word on the radio, and a wait: a transfer (bot_hopping.dm) with access instead of a job.
/datum/bot_goal/job_transfer/access
	doing = "asking the HoP for access"
	var/list/add_access
	var/access_names

/datum/bot_goal/job_transfer/access/New(list/accesses, names)
	. = ..(null)
	add_access = accesses
	access_names = names

/datum/bot_goal/job_transfer/access/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/await_transfer/access(add_access, access_names))
	return list(S)

/datum/bot_goal/job_transfer/access/on_give_up(datum/bot_brain/bot)
	return //no job to fall back on: it goes without

/datum/bot_step/paced/await_transfer/access
	var/list/add_access
	var/access_names

/datum/bot_step/paced/await_transfer/access/New(list/accesses, names)
	. = ..(null)
	add_access = accesses
	access_names = names

/datum/bot_step/paced/await_transfer/access/start(datum/bot_brain/bot)
	var/obj/item/card/id/card = bot.card_in_hand()
	if(!card || !bot.owner.dropItemToGround(card))
		return FALSE
	transfer = new(card, null, bot.owner)
	transfer.add_access = add_access
	transfer.access_names = access_names
	give_up_at = world.time + 3 MINUTES
	if(bot_find_hop(bot.owner))
		bot_say(bot.owner, ";HoP, could I get [access_names] access? Want to go exploring. My card's at your door.")
	else
		bot_say(bot.owner, ";Captain, there's no HoP on. Could I get [access_names] access? Want to go exploring. My card's at the HoP's door.")
	bot_log(bot, "left [card] for the HoP, for [access_names] access")
	return TRUE

/datum/bot_step/paced/await_transfer/access/finish(datum/bot_brain/bot)
	var/got_it = transfer?.done
	bot.check_card_back(transfer?.card)
	qdel(transfer)
	transfer = null
	bot_log(bot, got_it ? "got [access_names] access" : "nobody came for the card")
	return got_it ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

#undef BOT_EXPLORE_TRIP
#undef BOT_EXPLORE_RANGE
#undef BOT_EXPLORE_HAUL
