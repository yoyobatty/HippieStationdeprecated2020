// Breach toolkit - how a bot gets through something physically in its way.
//
// Three ideas:
//  - Urgency gates destruction. A calm bot goes around, unwelds, pries or hacks - it doesn't
//    smash station property to save a few steps. Only a bot in real danger (fire, bad air,
//    burning) is willing to break windows, grilles, tables and machines to get through.
//    Pre-existing fire-axe door smashing (bot_items.dm) is left as it was.
//  - Damage is predicted, not guessed. bot_breach_damage() runs the object's own armor code
//    (run_obj_armor(): damage_deflection, melee armor, armour penetration) for each candidate
//    weapon, so "how many swings will this take" comes from the same numbers the game uses.
//  - Weapons are chosen, not just grabbed. Everything carried, loose within sight, or sitting in
//    a nearby extinguisher cabinet is scored by total time (walk there + swings), so a bot will
//    detour three tiles for an extinguisher that breaks a window in 6 hits rather than spend 14
//    with a crowbar. Weapon/target pairs that turn out to do nothing are remembered and skipped.
//
// Admins can test without setting anything on fire: VV a bot's bot_brain and set
// urgency_override (0 calm, 1 concerned, 2 emergency, 3 panic; -1 = back to real perception).

#define BOT_URGENCY_CALM 0
#define BOT_URGENCY_CONCERNED 1
#define BOT_URGENCY_EMERGENCY 2
#define BOT_URGENCY_PANIC 3

/// Most swings a breach may need before it isn't worth attempting, per urgency level.
#define BOT_BREACH_MAX_HITS_EMERGENCY 30
#define BOT_BREACH_MAX_HITS_PANIC 80
/// How far (tiles) to look for a better improvised weapon.
#define BOT_BREACH_SEARCH_RANGE 6
/// How long (deciseconds) a snapshot of available weapons stays valid - pathing asks per turf.
#define BOT_BREACH_KIT_TTL 20
/// Air hotter than this (K) with no heat protection is a panic, not just an emergency.
#define BOT_PANIC_TEMPERATURE 500
/// Fuel a welder needs before the bot will plan a route through a welded door.
#define BOT_UNWELD_MIN_FUEL 3

/datum/bot_brain
	/// Debug/admin override for get_urgency(); -1 means use real perception.
	var/urgency_override = -1
	/// "[target type]|[weapon type]" -> TRUE for pairs that verifiably did no damage.
	var/list/ineffective_breach_pairs
	/// Target type -> how many different weapons that should have worked did nothing. At 2 the
	/// type is treated as unbreakable (vending machines route item clicks into loading, etc).
	var/list/breach_failures_by_type
	/// Cached get_breach_kit() result and when it was built.
	var/list/breach_kit_cache
	var/breach_kit_time = 0
	/// Set only while try_unlock_route() plans hypothetically: "if I had a welder / that toolbox".
	var/pathing_assume_welder = FALSE
	var/pathing_assume_nearby_weapons = FALSE
	/// Last urgency level logged, so transitions are logged once instead of every check.
	var/last_logged_urgency = BOT_URGENCY_CALM

// ---------------------------------------------------------------------------------------------
// Urgency
// ---------------------------------------------------------------------------------------------

/// How much danger the bot is in right now, from its own tile and immediate surroundings.
/// Deliberately cheap - pathing calls this per candidate turf through destruction_allowed().
/datum/bot_brain/proc/get_urgency()
	if(urgency_override >= 0)
		return urgency_override
	var/mob/living/carbon/human/H = owner
	if(!istype(H) || H.stat == DEAD)
		return BOT_URGENCY_CALM
	if(H.on_fire)
		return BOT_URGENCY_PANIC
	. = BOT_URGENCY_CALM
	var/turf/T = get_turf(H)
	var/datum/gas_mixture/air = T?.return_air()
	if(air)
		// calculate_affecting_pressure() accounts for a sealed suit+helmet, same as the damage code
		var/pressure = H.calculate_affecting_pressure(air.return_pressure())
		if(pressure < HAZARD_LOW_PRESSURE)
			. = BOT_URGENCY_PANIC
		else if(pressure < WARNING_LOW_PRESSURE)
			. = max(., BOT_URGENCY_EMERGENCY)
		var/temperature = air.return_temperature()
		if(temperature > BODYTEMP_HEAT_DAMAGE_LIMIT && !bot_is_heat_immune_to(temperature))
			. = max(., temperature > BOT_PANIC_TEMPERATURE ? BOT_URGENCY_PANIC : BOT_URGENCY_EMERGENCY)
	if(. < BOT_URGENCY_EMERGENCY)
		for(var/obj/effect/hotspot/fire in range(2, H))
			if(QDELETED(fire) || bot_is_heat_immune_to(fire.temperature))
				continue
			. = max(., get_dist(H, fire) <= 1 ? BOT_URGENCY_EMERGENCY : BOT_URGENCY_CONCERNED)
	// Badly hurt AND in danger: one step more desperate.
	if(. >= BOT_URGENCY_CONCERNED && . < BOT_URGENCY_PANIC && H.health < H.maxHealth * 0.4)
		.++

/proc/bot_urgency_name(urgency)
	switch(urgency)
		if(BOT_URGENCY_CALM)
			return "calm"
		if(BOT_URGENCY_CONCERNED)
			return "concerned"
		if(BOT_URGENCY_EMERGENCY)
			return "emergency"
	return "panic"

/// get_urgency(), logging when the level changes. Use outside of pathing.
/datum/bot_brain/proc/check_urgency()
	. = get_urgency()
	if(. != last_logged_urgency)
		bot_log(src, "urgency [bot_urgency_name(last_logged_urgency)] -> [bot_urgency_name(.)]")
		last_logged_urgency = .

/// Whether the bot is currently desperate enough to break things that aren't doors.
/datum/bot_brain/proc/destruction_allowed()
	return get_urgency() >= BOT_URGENCY_EMERGENCY

/datum/bot_brain/proc/breach_hit_budget()
	switch(get_urgency())
		if(BOT_URGENCY_PANIC)
			return BOT_BREACH_MAX_HITS_PANIC
		if(BOT_URGENCY_EMERGENCY)
			return BOT_BREACH_MAX_HITS_EMERGENCY
	return 0

// ---------------------------------------------------------------------------------------------
// Damage prediction
// ---------------------------------------------------------------------------------------------

/// Integrity one melee swing of W would remove from O, using O's own armor code. 0 = useless.
/proc/bot_breach_damage(obj/item/W, obj/O)
	if(!W || !O || QDELETED(W) || QDELETED(O))
		return 0
	if((O.resistance_flags & INDESTRUCTIBLE) || istype(O, /obj/mecha))
		return 0 //mecha armor code has side effects (booster reactions) - never predict against it
	if(W.item_flags & (NOBLUDGEON|ABSTRACT))
		return 0
	if(bot_breach_tool_intercepted(W, O))
		return 0
	var/force = W.force
	var/bonus = 0
	if(istype(W, /obj/item/twohanded/fireaxe))
		var/obj/item/twohanded/fireaxe/axe = W
		force = axe.force_wielded //ready_fireaxe() wields it before swinging
		// fireaxe/afterattack() (twohanded.dm) adds a second hit when wielded: 200 to windows, 40 to grilles
		if(istype(O, /obj/structure/window))
			bonus = O.run_obj_armor(200, BRUTE, "melee", null, 0)
		else if(istype(O, /obj/structure/grille))
			bonus = O.run_obj_armor(40, BRUTE, "melee", null, 0)
	if(force <= 0)
		return 0
	return O.run_obj_armor(force, W.damtype, "melee", null, W.armour_penetration) + bonus

/// True if clicking O with W does a tool action (unscrew, pry, weld, anchor...) instead of a hit.
/// A lit welder on a door on harm intent WELDS IT SHUT - exactly the wrong thing mid-escape.
/// Window/grille/table rules verified against real clicks (crowbars DO hit those).
/proc/bot_breach_tool_intercepted(obj/item/W, obj/O)
	var/tool = W.tool_behaviour
	if(!tool)
		return FALSE
	if(istype(O, /obj/structure/window))
		return tool == TOOL_SCREWDRIVER || tool == TOOL_WRENCH //a crowbar only pries an already-unscrewed pane; it hits a secured one
	if(istype(O, /obj/structure/grille))
		return tool == TOOL_SCREWDRIVER || tool == TOOL_WIRECUTTER //wirecutters cut it - handled separately
	if(istype(O, /obj/structure/table))
		return tool == TOOL_SCREWDRIVER || tool == TOOL_WRENCH //these take it apart instead
	return istype(O, /obj/machinery) || istype(O, /obj/structure/rack) || istype(O, /obj/structure/closet)

/proc/bot_breach_hits(obj/item/W, obj/O)
	var/damage = bot_breach_damage(W, O)
	if(damage <= 0)
		return INFINITY
	// A grille stops blocking once it breaks (integrity_failure), well before it's destroyed.
	var/to_remove = O.obj_integrity
	if(istype(O, /obj/structure/grille))
		to_remove = max(O.obj_integrity - O.integrity_failure, 1)
	return max(ceil(to_remove / damage), 1)

// ---------------------------------------------------------------------------------------------
// Weapon choice
// ---------------------------------------------------------------------------------------------

/datum/bot_brain/proc/is_carried(obj/item/I)
	if(!I || QDELETED(I))
		return FALSE
	return I.loc == owner || (I.loc && I.loc.loc == owner)

/// The weapon an entry in the breach kit stands for (a cabinet stands for its extinguisher).
/proc/bot_breach_kit_weapon(atom/source)
	var/obj/structure/extinguisher_cabinet/C = source
	if(istype(C))
		return C.stored_extinguisher
	return source

/// Everything the bot could hit something with: carried items, loose items in view, and
/// extinguishers in nearby wall cabinets. Cached briefly since pathing asks about every window.
/datum/bot_brain/proc/get_breach_kit()
	if(breach_kit_cache && world.time < breach_kit_time + BOT_BREACH_KIT_TTL)
		return breach_kit_cache
	var/list/kit = list()
	for(var/obj/item/I in owner)
		if(istype(I, /obj/item/storage))
			for(var/obj/item/stored in I)
				kit += stored
			if(!(I in owner.held_items))
				continue //a worn backpack/belt isn't something you swing - but a toolbox in hand is
		if(istype(I, /obj/item/clothing) || istype(I, /obj/item/card) || istype(I, /obj/item/pda))
			continue
		kit += I
	for(var/obj/item/I in view(BOT_BREACH_SEARCH_RANGE, owner))
		if(isturf(I.loc) && !I.anchored && I.w_class <= WEIGHT_CLASS_BULKY)
			kit += I
	for(var/obj/structure/extinguisher_cabinet/C in view(BOT_BREACH_SEARCH_RANGE, owner))
		if(C.stored_extinguisher)
			kit += C
	breach_kit_cache = kit
	breach_kit_time = world.time
	return kit

/// Best way to break O with what's around: list(source, estimated deciseconds, hits), or null.
/// `carried_only` is for pathing, which shouldn't plan around items it hasn't picked up yet.
/datum/bot_brain/proc/choose_breach_weapon(obj/O, carried_only = FALSE)
	var/budget = breach_hit_budget()
	if(budget <= 0 || LAZYACCESS(breach_failures_by_type, O.type) >= 2)
		return null
	var/move_delay = max(owner.movement_delay(), 1)
	var/atom/best
	var/best_cost
	var/best_hits
	for(var/atom/source in get_breach_kit())
		var/obj/item/W = bot_breach_kit_weapon(source)
		if(!W || QDELETED(W))
			continue
		var/carried = is_carried(W)
		if(carried_only && !carried)
			continue
		if(LAZYACCESS(ineffective_breach_pairs, "[O.type]|[W.type]"))
			continue
		var/hits = bot_breach_hits(W, O)
		if(hits > budget)
			continue
		var/cost = hits * CLICK_CD_MELEE
		if(!carried)
			cost += (get_dist(owner, source) + get_dist(source, O)) * move_delay + 10
		if(!best || cost < best_cost)
			best = source
			best_cost = cost
			best_hits = hits
	if(!best)
		return null
	return list(best, best_cost, best_hits)

/// Pathing check: could the bot get through O right now with what it's carrying?
/datum/bot_brain/proc/can_breach_now(obj/O)
	if(!destruction_allowed())
		return FALSE
	if(istype(O, /obj/structure/grille) && !(O.flags_1 & NODECONSTRUCT_1) && can_eventually_provide_tool(/obj/item/wirecutters))
		return TRUE
	return !!choose_breach_weapon(O, carried_only = !pathing_assume_nearby_weapons)

// ---------------------------------------------------------------------------------------------
// Doing it
// ---------------------------------------------------------------------------------------------

/// Break (or cut) through O. Returns TRUE if progress was made or a detour to fetch a better
/// weapon was started; FALSE if the bot won't or can't.
/datum/bot_brain/proc/try_breach(obj/O)
	var/urgency = check_urgency()
	if(urgency < BOT_URGENCY_EMERGENCY)
		bot_log(src, "[O] is in the way - not an emergency ([bot_urgency_name(urgency)]), so I won't break it")
		return FALSE
	// A grille comes apart with one wirecutter snip - far faster than beating it down.
	if(istype(O, /obj/structure/grille) && !(O.flags_1 & NODECONSTRUCT_1))
		var/obj/item/cutters = find_or_transform_tool(/obj/item/wirecutters)
		if(cutters)
			bot_log(src, "cutting through [O] with [cutters] ([bot_urgency_name(urgency)])")
			use_item_on(cutters, O)
			if(QDELETED(O) || !O.density)
				return TRUE
	var/list/choice = choose_breach_weapon(O)
	if(!choice)
		bot_log(src, "[O] is in the way and nothing I have or can see nearby would break it in time ([bot_urgency_name(urgency)])")
		return FALSE
	var/atom/source = choice[1]
	var/obj/item/W = bot_breach_kit_weapon(source)
	if(!is_carried(W))
		if(owner.Adjacent(source))
			if(istype(source, /obj/structure/extinguisher_cabinet))
				use_atom(source)
			else
				try_pickup_target(W)
			breach_kit_cache = null
			if(!is_carried(W))
				bot_log(src, "couldn't grab [W] to break [O] with")
				return FALSE
		else
			bot_log(src, "grabbing [W] [get_dist(owner, source)] tiles away to break through [O] (~[choice[3]] hits, [bot_urgency_name(urgency)])")
			breach_kit_cache = null
			var/datum/bot_goal/fetch_breach_weapon/fetch = new
			fetch.target = source
			return suspend_goal_for(fetch)
	return swing_at_blocker(W, O, choice[3])

/// One swing of W at O. Records the pair as useless if it verifiably did nothing.
/datum/bot_brain/proc/swing_at_blocker(obj/item/W, obj/O, expected_hits)
	if(istype(W, /obj/item/twohanded/fireaxe))
		W = ready_fireaxe() || W
	var/integrity_before = O.obj_integrity
	bot_log(src, "breaking through [O] with [W] (~[expected_hits] hits)")
	use_item_on(W, O, TRUE)
	if(QDELETED(O) || !O.density || O.obj_integrity < integrity_before)
		stuck_repeat_count = 0
		last_stuck_turf = null
		failed_blocker_count = 0
		return TRUE
	bot_log(src, "[W] isn't doing anything to [O] - won't try that pairing again")
	LAZYSET(ineffective_breach_pairs, "[O.type]|[W.type]", TRUE)
	LAZYSET(breach_failures_by_type, O.type, LAZYACCESS(breach_failures_by_type, O.type) + 1)
	breach_kit_cache = null
	return FALSE

// ---------------------------------------------------------------------------------------------
// Unwelding
// ---------------------------------------------------------------------------------------------

/datum/bot_brain/proc/can_unweld()
	if(pathing_assume_welder)
		return TRUE
	var/obj/item/weldingtool/W = find_carried_tool(/obj/item/weldingtool)
	return W && W.get_fuel() >= BOT_UNWELD_MIN_FUEL

/// Unweld a welded airlock or firelock with a carried welder - the same harm-intent welder
/// click a player uses (door/attackby() -> try_to_weld(), 4 second do_after). Returns TRUE if
/// the door is no longer welded.
/datum/bot_brain/proc/try_unweld(obj/machinery/door/D)
	if(!D.welded)
		return TRUE
	var/obj/item/weldingtool/W = find_carried_tool(/obj/item/weldingtool)
	if(!W)
		bot_log(src, "[D] is welded shut and I don't have a welder")
		return FALSE
	if(W.get_fuel() < 1)
		bot_log(src, "[D] is welded shut and my welder is out of fuel")
		return FALSE
	equip_welding_eye_protection()
	if(!W.isOn())
		toggle_in_hand(W)
	if(!W.isOn())
		bot_log(src, "couldn't light [W] to unweld [D]")
		return FALSE
	bot_log(src, "unwelding [D] ([describe_pursuit_purpose()])")
	use_item_on(W, D, TRUE) //harm intent: on help intent an airlock treats a welder as a repair
	if(W.isOn())
		toggle_in_hand(W)
	if(D.welded)
		bot_log(src, "[D] is still welded after trying")
		return FALSE
	return TRUE

// ---------------------------------------------------------------------------------------------
// Detour goal: go get the chosen breach weapon, then resume
// ---------------------------------------------------------------------------------------------

/// target is preset by try_breach(): a loose item, or an extinguisher cabinet.
/datum/bot_goal/fetch_breach_weapon

/datum/bot_goal/fetch_breach_weapon/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target))
		target = null
		return
	var/obj/structure/extinguisher_cabinet/C = target
	if(istype(C))
		if(!C.stored_extinguisher)
			target = null
		return
	var/obj/item/I = target
	if(!istype(I) || !isturf(I.loc))
		target = null

/datum/bot_goal/fetch_breach_weapon/get_strategies(datum/bot_brain/bot)
	if(istype(target, /obj/structure/extinguisher_cabinet))
		return list(new /datum/bot_strategy/grab_from_extinguisher_cabinet())
	return list(new /datum/bot_strategy/grab_item())

/datum/bot_strategy/grab_from_extinguisher_cabinet/New()
	. = ..()
	steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/take_from_extinguisher_cabinet())

/datum/bot_strategy/grab_from_extinguisher_cabinet/is_feasible(datum/bot_brain/bot)
	return TRUE

/datum/bot_step/take_from_extinguisher_cabinet/execute(datum/bot_brain/bot)
	var/obj/structure/extinguisher_cabinet/C = bot.current_goal?.target
	if(!istype(C) || QDELETED(C) || !C.stored_extinguisher)
		return GOAL_STEP_FAIL
	var/obj/item/extinguisher/E = C.stored_extinguisher
	bot.use_atom(C) //one click takes it (extinguisher_cabinet/attack_hand())
	return bot.is_carried(E) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// No route? Work out what would open one, and go get it
// ---------------------------------------------------------------------------------------------

/// Called by do_repath() when no route exists with what the bot is carrying. Plans again as if it
/// had a welder, then (in an emergency) as if it held the best weapon lying nearby; if either
/// imagined route exists, fetches the missing thing and returns TRUE (the goal resumes and
/// replans once it has it). Found by the Bot Gym: a welder in a locker, or a toolbox on the floor
/// two tiles away, used to mean "no path, give up".
/datum/bot_brain/proc/try_unlock_route(turf/dest, obj/item/card/id/id_card)
	if(state != BOT_STATE_GOAL || !current_goal || suspended_goal)
		return FALSE //only for a real goal, and never nested inside another fetch
	if(!can_unweld())
		pathing_assume_welder = TRUE
		var/list/welder_path = try_path_to_no_climb(dest, id_card)
		pathing_assume_welder = FALSE
		if(length(welder_path) && bot_path_has_welded_door(welder_path))
			bot_log(src, "the only way to [dest] is through a welded door - going to get a welder")
			if(seek_tool_for_obstacle(/obj/item/weldingtool))
				return TRUE
	if(destruction_allowed())
		pathing_assume_nearby_weapons = TRUE
		breach_kit_cache = null
		var/list/breach_path = try_path_to_no_climb(dest, id_card)
		pathing_assume_nearby_weapons = FALSE
		for(var/turf/T in breach_path)
			for(var/obj/O in T)
				if(!O.density || !bot_is_breach_target(O))
					continue
				var/list/choice = choose_breach_weapon(O)
				if(!choice)
					continue
				var/atom/source = choice[1]
				if(is_carried(bot_breach_kit_weapon(source)))
					return FALSE //already has what it needs - the route failed for another reason
				bot_log(src, "no way to [dest] except through [O] - fetching [bot_breach_kit_weapon(source)] to break it ([bot_urgency_name(get_urgency())])")
				var/datum/bot_goal/fetch_breach_weapon/fetch = new
				fetch.target = source
				return suspend_goal_for(fetch)
	return FALSE

/proc/bot_path_has_welded_door(list/path)
	for(var/turf/T in path)
		for(var/obj/machinery/door/D in T)
			if(D.welded && D.density)
				return TRUE
	return FALSE

/// The things route planning is allowed to break through (see bot_can_break_through()).
/proc/bot_is_breach_target(obj/O)
	return istype(O, /obj/structure/window) || istype(O, /obj/structure/grille) || istype(O, /obj/machinery/door/window)
