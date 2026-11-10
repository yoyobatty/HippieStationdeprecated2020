// Bartender: keeps a few mixed drinks out on the bar for whoever wants one (goals/eat_and_drink.dm
// - someone after a drink goes to the bar before a vending machine, if there's one poured).
//
// A drink is a glass from the Booze-O-Mat (or an empty one off the counter), the spirit from the booze
// dispenser and the mixer from the soda dispenser. The clicks are the player's: the glass on the
// machine puts it in (chem_dispenser/attackby()), the machine's button pours, taking the glass out
// again hands it back (replace_beaker()); the two mix in the glass; the glass on the bar counter sets
// it down.

/// The bar is stocked enough with this many drinks out.
#define BOT_BAR_COUNTER_TARGET 4
#define BOT_BAR_REACH 30

/datum/bot_drink
	var/name
	/// Reagent type -> units, in the order poured. 30u in all fills most of a glass.
	var/list/pours

/datum/bot_drink/gin_tonic
	name = "gin and tonic"
	pours = list(/datum/reagent/consumable/ethanol/gin = 20, /datum/reagent/consumable/tonic = 10)

/datum/bot_drink/rum_coke
	name = "rum and coke"
	pours = list(/datum/reagent/consumable/ethanol/rum = 20, /datum/reagent/consumable/space_cola = 10)

/datum/bot_drink/screwdriver
	name = "screwdriver"
	pours = list(/datum/reagent/consumable/ethanol/vodka = 20, /datum/reagent/consumable/orangejuice = 10)

/datum/bot_drink/whiskey_cola
	name = "whiskey cola"
	pours = list(/datum/reagent/consumable/ethanol/whiskey = 20, /datum/reagent/consumable/space_cola = 10)

/datum/bot_drink/martini
	name = "martini"
	pours = list(/datum/reagent/consumable/ethanol/gin = 20, /datum/reagent/consumable/ethanol/vermouth = 10)

/datum/bot_drink/black_russian
	name = "black russian"
	pours = list(/datum/reagent/consumable/ethanol/vodka = 18, /datum/reagent/consumable/ethanol/kahlua = 12)

GLOBAL_LIST_INIT(bot_bar_menu, init_bot_bar_menu())

/proc/init_bot_bar_menu()
	. = list()
	for(var/path in subtypesof(/datum/bot_drink))
		. += new path

/datum/bot_brain
	var/list/bar_blocked
	var/drinks_served = 0
	/// Drinks mixed because somebody asked for them (goals/orders.dm).
	var/orders_filled = 0

/datum/bot_brain/proc/is_bartender_job()
	return work_role() == "Bartender"

/// Whether A is in the bar. A Bot Gym bartender's bar is its arena.
/datum/bot_brain/proc/in_bar(atom/A)
	if(!A || QDELETED(A) || A.z != owner.z)
		return FALSE
	var/area/AR = get_area(A)
	return gym_run ? (AR == get_area(owner)) : istype(AR, /area/crew_quarters/bar)

/// The working drinks dispenser in the bar that pours reagent_type.
/datum/bot_brain/proc/find_bar_dispenser(reagent_type)
	var/obj/machinery/chem_dispenser/best
	var/best_dist
	for(var/obj/machinery/chem_dispenser/drinks/D as anything in bot_instances_of(/obj/machinery/chem_dispenser/drinks))
		if(!in_bar(D) || !D.is_operational() || !D.cell || !D.dispensable_reagents.Find(reagent_type) || LAZYACCESS(bar_blocked, D) > world.time)
			continue
		var/dist = get_dist(owner, D)
		if(dist > BOT_BAR_REACH || (best && dist >= best_dist))
			continue
		best = D
		best_dist = dist
	return best

/datum/bot_brain/proc/carried_empty_glass()
	for(var/obj/item/reagent_containers/food/drinks/drinkingglass/G in owner.GetAllContents())
		if(!istype(G, /obj/item/reagent_containers/food/drinks/drinkingglass/shotglass) && !G.reagents.total_volume)
			return G
	return null

/// Where to get a glass: an empty left on a table in the bar, or the Booze-O-Mat. Only one it has a way to: the nearest was taken
/// whatever stood between, and a bartender set off for the Speakeasy's Booze-O-Mat behind a wall, or across a bar with the air
/// gone out of it, and gave up at the end of the route search (51 times in twelve shifts, and a drink given up each time). One it
/// can't get to is left a few minutes.
/datum/bot_brain/proc/find_glass_source()
	var/list/glasses = list()
	glance_at_items()
	for(var/obj/item/reagent_containers/food/drinks/drinkingglass/G as anything in bot_instances_of(/obj/item/reagent_containers/food/drinks/drinkingglass))
		if(!isturf(G.loc) || !in_bar(G) || G.reagents.total_volume || istype(G, /obj/item/reagent_containers/food/drinks/drinkingglass/shotglass) || !knows_of_in_room(G)) //what it knows of, or can see round the bar (bot_knowledge.dm)
			continue
		if(LAZYACCESS(bar_blocked, G.loc) <= world.time)
			glasses[G] = get_dist(owner, G)
	. = nearest_reachable_bar_thing(glasses)
	if(.)
		return
	var/list/vendors = list()
	for(var/obj/machinery/vending/boozeomat/V as anything in bot_instances_of(/obj/machinery/vending/boozeomat))
		if(!in_bar(V) || V.panel_open || (V.stat & (BROKEN|NOPOWER)) || LAZYACCESS(bar_blocked, V.loc) > world.time || !length(vendor_stock(V, list(/obj/item/reagent_containers/food/drinks/drinkingglass))))
			continue
		vendors[V] = get_dist(owner, V)
	return nearest_reachable_bar_thing(vendors)

/// Of things and their distances, the nearest this bot has a way to; where the ones it hasn't are is left alone three minutes (bar_blocked).
/// A few route searches at most.
/datum/bot_brain/proc/nearest_reachable_bar_thing(list/things)
	for(var/tries in 1 to 3)
		var/atom/nearest
		for(var/atom/A as anything in things)
			if(!nearest || things[A] < things[nearest])
				nearest = A
		if(!nearest)
			return null
		if(can_walk_lawfully_to(nearest))
			return nearest
		things -= nearest
		LAZYSET(bar_blocked, get_turf(nearest), world.time + 3 MINUTES) //the turf: a glass is gone soon enough, and a list holding it is a hard delete
	return null

/// A drink that's been poured and left out: a filled glass on a table in the bar. `reach` is how far this bot would walk for one.
/datum/bot_brain/proc/find_served_drink(reach)
	var/obj/item/best
	var/best_dist
	for(var/obj/item/reagent_containers/food/drinks/drinkingglass/G as anything in bot_instances_of(/obj/item/reagent_containers/food/drinks/drinkingglass))
		if(!isturf(G.loc) || !in_bar(G) || !G.reagents.total_volume || !(locate(/obj/structure/table) in G.loc))
			continue
		var/dist = get_dist(owner, G)
		if(dist > reach || (best && dist >= best_dist) || LAZYACCESS(bar_blocked, G.loc) > world.time)
			continue
		best = G
		best_dist = dist
	return best

/datum/bot_brain/proc/drinks_on_bar()
	. = 0
	for(var/obj/item/reagent_containers/food/drinks/drinkingglass/G as anything in bot_instances_of(/obj/item/reagent_containers/food/drinks/drinkingglass))
		if(isturf(G.loc) && in_bar(G) && G.reagents.total_volume && (locate(/obj/structure/table) in G.loc))
			.++

/// The table to put drinks on: one with a bar stool beside it, the emptiest first; failing that any bare table in the bar.
/datum/bot_brain/proc/find_bar_counter()
	var/obj/structure/table/best
	var/best_score
	for(var/obj/structure/table/T as anything in bot_instances_of(/obj/structure/table))
		if(!in_bar(T) || !table_is_bare(T)) //goals/cook.dm
			continue
		var/has_stool = !!gym_run
		for(var/turf/next_to in get_adjacent_open_turfs(T))
			if(locate(/obj/structure/chair/stool) in next_to)
				has_stool = TRUE
				break
		var/glasses = 0
		for(var/obj/item/reagent_containers/food/drinks/D in T.loc)
			glasses++
		var/score = (has_stool ? 0 : 100) + glasses * 5 + get_dist(owner, T) * 0.1
		if(!best || score < best_score)
			best = T
			best_score = score
	return best

/datum/bot_brain/proc/pick_drink_to_mix()
	for(var/datum/bot_drink/D as anything in shuffle(GLOB.bot_bar_menu))
		if(can_mix(D))
			return D
	return null

/// Whether the bar's dispensers have everything a drink takes.
/datum/bot_brain/proc/can_mix(datum/bot_drink/D)
	for(var/reagent_type in D.pours)
		if(!find_bar_dispenser(reagent_type))
			return FALSE
	return TRUE

// ---------------------------------------------------------------------------------------------
// The round
// ---------------------------------------------------------------------------------------------

/datum/bot_duty/bartender
	name = "tending bar"
	jobs = list("Bartender")
	interval_min = 80
	interval_max = 200

/datum/bot_duty/bartender/try_start(datum/bot_brain/bot)
	if(bot.state == BOT_STATE_GOAL && bot.current_goal)
		return FALSE
	// What somebody has asked for comes before stocking the bar (goals/orders.dm). Something it can't make - "a
	// beer" - gets whatever it would have mixed next.
	var/datum/bot_request/order = bot.next_bar_order()
	if(!order && bot.drinks_on_bar() >= BOT_BAR_COUNTER_TARGET)
		return FALSE
	var/datum/bot_drink/D = order?.detail
	if(!D || !bot.can_mix(D))
		D = bot.pick_drink_to_mix()
	var/obj/structure/table/counter = bot.find_bar_counter()
	// A bar it can't get to (the air gone out of it, or shut in somewhere else) is no bar to tend.
	if(!D || !counter || (!bot.carried_empty_glass() && !bot.find_glass_source()) || !bot.can_walk_lawfully_to(counter))
		return FALSE
	var/datum/bot_goal/mix_drink/G = new(D)
	G.order = order
	return bot.assign_goal(G)

/datum/bot_brain/proc/continue_bar_round()
	if(prob((1 - diligence) * 40))
		return
	var/datum/bot_duty/bartender/duty = bot_duty_of(/datum/bot_duty/bartender)
	continue_goal_chain(CALLBACK(duty, TYPE_PROC_REF(/datum/bot_duty, try_start), src))

// ---------------------------------------------------------------------------------------------
// One drink
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/mix_drink
	lawful = TRUE
	var/datum/bot_drink/drink
	var/obj/structure/table/counter
	/// The glass it's being mixed in.
	var/obj/item/reagent_containers/food/drinks/drinkingglass/glass
	/// The order this one is for, if somebody asked for it.
	var/datum/bot_request/order

/datum/bot_goal/mix_drink/New(datum/bot_drink/drink)
	. = ..()
	src.drink = drink
	doing = "mixing a [drink.name]"

/datum/bot_goal/mix_drink/resolve_target(datum/bot_brain/bot)
	counter = bot.find_bar_counter()
	target = counter

/datum/bot_goal/mix_drink/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/bartender/S = new
	S.steps = list(new /datum/bot_step/get_glass())
	for(var/reagent_type in drink.pours)
		var/obj/machinery/chem_dispenser/D = bot.find_bar_dispenser(reagent_type)
		if(!D)
			return list()
		var/datum/bot_step/move_to/to_machine = new
		to_machine.step_target = D
		S.steps += to_machine
		S.steps += new /datum/bot_step/pour_at_dispenser(D, reagent_type, drink.pours[reagent_type])
	S.steps += new /datum/bot_step/move_to() //the counter
	S.steps += new /datum/bot_step/serve_drink()
	return list(S)

/datum/bot_goal/mix_drink/on_success(datum/bot_brain/bot)
	if(order)
		LAZYREMOVE(bot.bar_orders, order)
		bot.orders_filled++
		var/mob/living/who = order.caller_ref?.resolve()
		if(who)
			var/line = "[capitalize(drink.name)] for [who.first_name()], on the bar."
			bot_say(bot.owner, bot_radio_prefix(order.radio_freq) + line)
			bot_log(bot, "said \"[line]\"")
	bot.continue_bar_round()

/// An order it couldn't fill is tried again - somebody was stood at the dispenser, the glass got knocked - but
/// not over and over.
/datum/bot_goal/mix_drink/on_give_up(datum/bot_brain/bot)
	if(order && ++order.failures >= 4)
		LAZYREMOVE(bot.bar_orders, order)
		var/mob/living/who = order.caller_ref?.resolve()
		if(who && who.stat == CONSCIOUS)
			bot.say_after_typing(bot_radio_prefix(order.radio_freq) + pick("Sorry, [who.first_name()] - can't get that one made just now.", "No luck with that order, sorry."))

/datum/bot_strategy/bartender/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// An empty glass in hand: one already carried, or fetched - an empty off the counter, or a new one from the Booze-O-Mat.
/datum/bot_step/get_glass
	var/fetched = FALSE

/datum/bot_step/get_glass/execute(datum/bot_brain/bot)
	var/datum/bot_goal/mix_drink/G = bot.current_goal
	if(!istype(G))
		return GOAL_STEP_FAIL
	G.glass = bot.carried_empty_glass()
	if(G.glass)
		return GOAL_STEP_SUCCESS
	if(fetched)
		return GOAL_STEP_FAIL
	fetched = TRUE
	var/atom/source = bot.find_glass_source()
	if(!source)
		return GOAL_STEP_FAIL
	if(bot.suspend_goal_for(new /datum/bot_goal/fetch_glass(source)))
		return GOAL_STEP_PENDING
	return GOAL_STEP_FAIL

/datum/bot_goal/fetch_glass
	lawful = TRUE
	doing = "getting a glass"

/datum/bot_goal/fetch_glass/New(atom/source)
	. = ..()
	target = source

/datum/bot_goal/fetch_glass/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target))
		target = null

/// Where it couldn't get one is left a few minutes, so the next look goes elsewhere. A Booze-O-Mat set into the bar's wall passed the
/// route check from where the bartender stood and then had "no path to the wall": rested after a few tries, it went on being chosen and
/// turned down, and the drink given up, 14 times in a shift.
/datum/bot_goal/fetch_glass/on_give_up(datum/bot_brain/bot)
	var/turf/T = get_turf(target)
	if(T)
		LAZYSET(bot.bar_blocked, T, world.time + 3 MINUTES)

/datum/bot_goal/fetch_glass/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/bartender/S = new
	if(istype(target, /obj/machinery/vending))
		S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/vend_products(list(/obj/item/reagent_containers/food/drinks/drinkingglass)))
	else
		S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/take_in_hand())
	return list(S)

/// At a dispenser: glass in if it isn't already, the button for the reagent, glass back out.
/datum/bot_step/pour_at_dispenser
	var/obj/machinery/chem_dispenser/dispenser
	var/reagent_type
	var/amount

/datum/bot_step/pour_at_dispenser/New(obj/machinery/chem_dispenser/dispenser, reagent_type, amount)
	. = ..()
	src.dispenser = dispenser
	src.reagent_type = reagent_type
	src.amount = amount

/datum/bot_step/pour_at_dispenser/execute(datum/bot_brain/bot)
	var/datum/bot_goal/mix_drink/G = bot.current_goal
	var/obj/item/reagent_containers/glass = G?.glass
	if(!istype(G) || QDELETED(glass) || QDELETED(dispenser))
		return GOAL_STEP_FAIL
	// Each way this goes wrong says so: 41 drinks in a batch were given up here with nothing in the log to say why.
	if(!bot.owner.Adjacent(dispenser))
		bot_log(bot, "can't reach [dispenser] from here ([get_dist(bot.owner, dispenser)] tiles, [get_dist(bot.owner, dispenser) <= 1 ? "something in the way across the corner" : "not beside it"])")
		return GOAL_STEP_FAIL
	if(dispenser.beaker != glass)
		if(!bot.is_carried(glass))
			bot_log(bot, "lost hold of [glass] on the way to [dispenser] ([glass.loc])")
			return GOAL_STEP_FAIL
		if(!bot.use_tool_on(glass, dispenser) || dispenser.beaker != glass)
			bot_log(bot, "[glass] wouldn't go in [dispenser] (in my hands: [english_list(bot.owner.held_items, "nothing")], in it: [dispenser.beaker || "nothing"])")
			return GOAL_STEP_FAIL
	bot.human_pause(dispenser)
	if(QDELETED(dispenser) || dispenser.beaker != glass || !bot.owner.Adjacent(dispenser))
		return GOAL_STEP_FAIL
	bot.owner.face_atom(dispenser)
	var/datum/reagent/poured = reagent_type
	bot.telemetry_ui_action(dispenser, "dispense [initial(poured.name)]")
	var/ok = bot.dispense_into_beaker(dispenser, reagent_type, amount) //goals/synthesize_medicine.dm
	// Glass back out, whether or not anything came (the machine's eject button).
	bot.human_pause(dispenser)
	if(QDELETED(dispenser) || !bot.owner.Adjacent(dispenser))
		return GOAL_STEP_FAIL //jostled away from the machine by somebody squeezing past: no pressing its buttons from over there
	bot.owner.face_atom(dispenser)
	bot.telemetry_ui_action(dispenser, "eject")
	if(bot.owner.get_active_held_item() && bot.owner.get_inactive_held_item())
		bot.put_away(bot.owner.get_active_held_item(), allow_equip = FALSE)
	dispenser.replace_beaker(bot.owner)
	if(!ok)
		LAZYSET(bot.bar_blocked, dispenser, world.time + 3 MINUTES)
		bot_log(bot, "[dispenser] wouldn't pour any [initial(poured.name)]")
		return GOAL_STEP_FAIL
	return bot.is_carried(glass) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// At the counter: the drink set down on the bar.
/datum/bot_step/serve_drink/execute(datum/bot_brain/bot)
	var/datum/bot_goal/mix_drink/G = bot.current_goal
	if(!istype(G) || QDELETED(G.glass) || QDELETED(G.counter) || !bot.is_carried(G.glass))
		return GOAL_STEP_FAIL
	if(!bot.use_tool_on(G.glass, G.counter) || bot.is_carried(G.glass))
		return GOAL_STEP_FAIL
	bot.drinks_served++
	bot_log(bot, "put a [G.drink.name] out on the bar")
	return GOAL_STEP_SUCCESS

#undef BOT_BAR_COUNTER_TARGET
#undef BOT_BAR_REACH
