// Eating and drinking. Bots get hungry like anyone - nutrition drains about 3 a minute, faster on the
// move - and used to do nothing about it: what they bought from vending machines stayed in their
// pockets for the rest of the shift.
//
//  - peckish, with nothing better to do: eat. Whatever's already in a pocket first, then a dish off the
//    kitchen's counter if the cook has put any out, then the nearest snack machine.
//  - properly hungry: the same, but ahead of work, and work stops chaining straight into more work
//    until it's seen to (has_pressing_need(), continue_goal_chain()).
//  - a coffee or a can from a machine now and then, drunk a gulp at a time over a minute.
//  - the wrapper goes in a bin if there's one within reach, and on the floor if there isn't.
//
// All with the player's own clicks: food in hand used on yourself is a bite (snacks/attack()), a drink
// a gulp (drinks/attack()), a can's tab pulled first (attack_self()).

/// Below this a bot stops what it's doing to eat. NUTRITION_LEVEL_HUNGRY is 250; the game's "starving" is 150.
#define BOT_NUTRITION_HUNGRY 200
/// Stops eating about here, even with food left (NUTRITION_LEVEL_WELL_FED is 450).
#define BOT_NUTRITION_ENOUGH 440
#define BOT_MEAL_REACH 50
#define BOT_DRINK_REACH 20

/// Food nobody eats as it comes: raw ingredients, and things that only look like food.
GLOBAL_LIST_INIT(bot_inedible_food, typecacheof(list(
	/obj/item/reagent_containers/food/snacks/grown,
	/obj/item/reagent_containers/food/snacks/meat/slab,
	/obj/item/reagent_containers/food/snacks/meat/rawcutlet,
	/obj/item/reagent_containers/food/snacks/dough,
	/obj/item/reagent_containers/food/snacks/flatdough,
	/obj/item/reagent_containers/food/snacks/doughslice,
	/obj/item/reagent_containers/food/snacks/egg,
	/obj/item/reagent_containers/food/snacks/monkeycube,
	/obj/item/reagent_containers/food/snacks/deadmouse,
	/obj/item/reagent_containers/food/snacks/badrecipe,
)))

/datum/bot_brain
	/// Nutrition below which this bot starts thinking about food - everyone's stomach is different.
	var/hunger_point = 0
	/// Nothing to eat was to be had: not before this again.
	var/meal_retry_time = 0
	/// Vending machine -> when to consider it again: ones it set off for and couldn't get to.
	var/list/vendor_blocked
	var/meals_eaten = 0
	var/drinks_drunk = 0

/datum/bot_brain/proc/is_peckish()
	if(HAS_TRAIT(owner, TRAIT_NOHUNGER))
		return FALSE
	if(!hunger_point)
		hunger_point = rand(240, 320)
	return owner.nutrition < hunger_point

/datum/bot_brain/proc/is_hungry()
	return owner.nutrition < BOT_NUTRITION_HUNGRY && !HAS_TRAIT(owner, TRAIT_NOHUNGER)

/// A need of the bot's own that work shouldn't carry on over - see continue_goal_chain() (bot_brain.dm).
/datum/bot_brain/proc/has_pressing_need()
	return !gym_scripted && is_hungry() && world.time >= meal_retry_time

/datum/bot_brain/proc/is_edible_now(obj/item/reagent_containers/food/snacks/F)
	if(QDELETED(F) || !F.reagents?.total_volume || is_type_in_typecache(F, GLOB.bot_inedible_food))
		return FALSE
	// Not out of a box of ingredients or a bag of produce - that's somebody's work, their own included.
	return !istype(F.loc, /obj/item/storage/box/ingredients) && !istype(F.loc, /obj/item/storage/bag)

/datum/bot_brain/proc/carried_food()
	for(var/obj/item/reagent_containers/food/snacks/F in owner.GetAllContents())
		if(is_edible_now(F))
			return F
	return null

/// A dish somebody has put out on a table in the kitchen, the bar or the cafeteria. In the Bot Gym, on any table in the arena.
/datum/bot_brain/proc/find_served_food()
	var/obj/item/best
	var/best_dist
	for(var/obj/item/reagent_containers/food/snacks/F as anything in bot_instances_of(/obj/item/reagent_containers/food/snacks))
		if(!isturf(F.loc) || F.z != owner.z || !is_edible_now(F) || !(locate(/obj/structure/table) in F.loc))
			continue
		var/dist = get_dist(owner, F)
		if(dist > BOT_MEAL_REACH || (best && dist >= best_dist) || LAZYACCESS(kitchen_blocked, F.loc) > world.time)
			continue
		var/area/A = get_area(F)
		if(gym_run ? (A != get_area(owner)) : (!istype(A, /area/crew_quarters/kitchen) && !istype(A, /area/crew_quarters/bar) && !istype(A, /area/crew_quarters/cafeteria)))
			continue
		best = F
		best_dist = dist
	return best

/// What V has in stock that's a kind of base_type, as product records.
/datum/bot_brain/proc/vendor_fare(obj/machinery/vending/V, base_type)
	. = list()
	for(var/datum/data/vending_product/R in V.product_records)
		if(R.amount > 0 && ispath(R.product_path, base_type))
			. += R

/// The nearest working machine of one of vendor_types with something of base_type to sell.
/datum/bot_brain/proc/find_fare_vendor(list/vendor_types, base_type, reach)
	var/obj/machinery/vending/best
	var/best_dist
	for(var/vendor_type in vendor_types)
		for(var/obj/machinery/vending/V as anything in bot_instances_of(vendor_type))
			if(QDELETED(V) || V.z != owner.z || V.panel_open || (V.stat & (BROKEN|NOPOWER)) || LAZYACCESS(vendor_blocked, V) > world.time)
				continue
			var/dist = get_dist(owner, V)
			if(dist > reach || (best && dist >= best_dist))
				continue
			if(gym_run && get_area(V) != get_area(owner))
				continue
			if(!length(vendor_fare(V, base_type)))
				continue
			best = V
			best_dist = dist
	return best

/// What's left in the hands after a meal: into a bin if one is within reach, dropped where it stands otherwise.
/datum/bot_brain/proc/dispose_of_leftovers()
	for(var/obj/item/I in owner.held_items)
		var/empty_drink = istype(I, /obj/item/reagent_containers/food/drinks) && !I.reagents?.total_volume && !istype(I, /obj/item/reagent_containers/food/drinks/drinkingglass)
		if(!istype(I, /obj/item/trash) && !empty_drink)
			continue
		var/obj/machinery/disposal/bin/bin = locate() in range(1, owner)
		if(bin && use_item_on(I, bin))
			continue
		human_pause(owner)
		owner.dropItemToGround(I)

// ---------------------------------------------------------------------------------------------
// The duties
// ---------------------------------------------------------------------------------------------

/datum/bot_duty/eat_when_hungry
	name = "getting something to eat"
	tier = BOT_DUTY_URGENT
	priority = 10
	interval_min = 100
	interval_max = 200

/datum/bot_duty/eat_when_hungry/try_start(datum/bot_brain/bot)
	if(!bot.is_hungry() || world.time < bot.meal_retry_time)
		return FALSE
	return bot.assign_goal(new /datum/bot_goal/have_meal())

/datum/bot_duty/eat_when_peckish
	name = "having a bite"
	tier = BOT_DUTY_LEISURE
	interval_min = 150
	interval_max = 300

/datum/bot_duty/eat_when_peckish/try_start(datum/bot_brain/bot)
	if(!bot.is_peckish() || world.time < bot.meal_retry_time)
		return FALSE
	return bot.assign_goal(new /datum/bot_goal/have_meal())

/datum/bot_duty/have_a_drink
	name = "having a drink"
	tier = BOT_DUTY_LEISURE
	interval_min = 1800
	interval_max = 4200

/datum/bot_duty/have_a_drink/try_start(datum/bot_brain/bot)
	if(!prob(40 + bot.sociability * 40))
		return FALSE
	return bot.assign_goal(new /datum/bot_goal/have_drink())

// ---------------------------------------------------------------------------------------------
// A meal
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/have_meal
	lawful = TRUE
	doing = "getting something to eat"
	/// What it's eating, once that's in hand.
	var/obj/item/reagent_containers/food/snacks/food

/datum/bot_goal/have_meal/resolve_target(datum/bot_brain/bot)
	food = bot.carried_food()
	if(food)
		target = bot.owner
		return
	target = bot.find_served_food() || bot.find_fare_vendor(list(/obj/machinery/vending/snack), /obj/item/reagent_containers/food/snacks, BOT_MEAL_REACH)
	if(!target)
		bot.meal_retry_time = world.time + 3 MINUTES

/datum/bot_goal/have_meal/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/refreshment/S = new
	if(target == bot.owner)
		S.steps = list(new /datum/bot_step/paced/eat_food())
	else if(istype(target, /obj/machinery/vending))
		var/datum/data/vending_product/pick = pick(bot.vendor_fare(target, /obj/item/reagent_containers/food/snacks))
		S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/vend_products(list(pick.product_path)), new /datum/bot_step/paced/eat_food())
	else
		S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/take_in_hand(), new /datum/bot_step/paced/eat_food())
	return list(S)

/datum/bot_goal/have_meal/on_give_up(datum/bot_brain/bot)
	// A dish it couldn't get to (on a table inside the kitchen, not on the counter): that table is left alone for a
	// while and it tries for something else. Anything else failing means there's nothing to be had just now.
	if(istype(target, /obj/item) && isturf(target.loc))
		LAZYSET(bot.kitchen_blocked, target.loc, world.time + 5 MINUTES)
	else if(istype(target, /obj/machinery/vending))
		// The nearest machine was in a room this ID doesn't open (the heads' meeting room, for one): the next nearest.
		LAZYSET(bot.vendor_blocked, target, world.time + 10 MINUTES)
	else
		bot.meal_retry_time = world.time + 3 MINUTES

/datum/bot_strategy/refreshment/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// One bite at a time until it's gone or the bot has had enough.
/datum/bot_step/paced/eat_food
	max_clicks = 40
	var/obj/item/reagent_containers/food/snacks/food
	var/bites = 0

/datum/bot_step/paced/eat_food/start(datum/bot_brain/bot)
	var/datum/bot_goal/have_meal/G = bot.current_goal
	food = (istype(G) && !QDELETED(G.food)) ? G.food : null
	if(!food)
		// The dish it walked over for, if it's now in hand; otherwise whatever it has just bought.
		var/obj/item/reagent_containers/food/snacks/fetched = bot.current_goal?.target
		food = (istype(fetched) && bot.is_carried(fetched)) ? fetched : bot.carried_food()
	bites = 0
	if(food)
		bot_log(bot, "eating [food]")
	return !!food

/datum/bot_step/paced/eat_food/do_click(datum/bot_brain/bot)
	if(QDELETED(food) || !food.reagents?.total_volume || bites >= 40)
		return FALSE
	if(bot.owner.nutrition >= BOT_NUTRITION_ENOUGH)
		return FALSE
	if(!bot.ready_in_hand(food))
		return FALSE
	var/before = food.reagents.total_volume
	bot.use_item_on(food, bot.owner)
	if(!QDELETED(food) && food.reagents?.total_volume >= before)
		return FALSE //wouldn't go down (too full, or something over the mouth)
	bites++
	wait_for = rand(6, 14) //chewing
	return TRUE

/datum/bot_step/paced/eat_food/finish(datum/bot_brain/bot)
	if(bites)
		bot.meals_eaten++
		// What it ate takes a few minutes to count (15 nutrition a unit, 0.4u a tick): not straight back for another.
		bot.meal_retry_time = world.time + (bot.is_hungry() ? 45 SECONDS : 2 MINUTES)
	// What's left of it goes back in a pocket for later rather than being carried about in the hand.
	if(!QDELETED(food) && (food in bot.owner.held_items))
		bot.put_away(food, allow_equip = FALSE)
	food = null
	bot.dispose_of_leftovers()
	return bites ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// A drink
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/have_drink
	lawful = TRUE
	doing = "getting a drink"

/datum/bot_goal/have_drink/resolve_target(datum/bot_brain/bot)
	// Something the bartender has poured, if the bar's near enough - a regular will cross the station for it -
	// and it hasn't had enough already. Otherwise a machine.
	if(bot.owner.drunkenness < 20)
		target = bot.find_served_drink(bot.has_habit(BOT_HABIT_BARFLY) ? 80 : BOT_DRINK_REACH) //goals/bartender.dm
	if(!target)
		target = bot.find_fare_vendor(list(/obj/machinery/vending/coffee, /obj/machinery/vending/cola), /obj/item/reagent_containers/food/drinks, BOT_DRINK_REACH)

/datum/bot_goal/have_drink/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/refreshment/S = new
	if(istype(target, /obj/machinery/vending))
		var/datum/data/vending_product/pick = pick(bot.vendor_fare(target, /obj/item/reagent_containers/food/drinks))
		S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/vend_products(list(pick.product_path)), new /datum/bot_step/paced/drink_up(pick.product_path))
	else
		doing = "having a drink at the bar"
		S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/take_in_hand(), new /datum/bot_step/paced/drink_up())
	return list(S)

/// A drink on the bar it couldn't get to (the wrong side of the counter): not that table again for a while.
/datum/bot_goal/have_drink/on_give_up(datum/bot_brain/bot)
	if(istype(target, /obj/machinery/vending))
		LAZYSET(bot.vendor_blocked, target, world.time + 10 MINUTES)
	else if(target)
		LAZYSET(bot.bar_blocked, get_turf(target), world.time + 5 MINUTES)

/// A gulp, a pause, a gulp, until the cup's empty.
/datum/bot_step/paced/drink_up
	max_clicks = 30
	var/drink_type
	var/obj/item/reagent_containers/food/drinks/drink
	var/gulps = 0

/datum/bot_step/paced/drink_up/New(drink_type)
	. = ..()
	src.drink_type = drink_type

/datum/bot_step/paced/drink_up/start(datum/bot_brain/bot)
	if(drink_type)
		drink = bot.find_carried_tool(drink_type)
	else
		// The glass it walked over to the bar for.
		var/obj/item/reagent_containers/food/drinks/poured = bot.current_goal?.target
		drink = (istype(poured) && bot.is_carried(poured)) ? poured : null
	gulps = 0
	return drink && drink.reagents?.total_volume

/datum/bot_step/paced/drink_up/do_click(datum/bot_brain/bot)
	if(QDELETED(drink) || !drink.reagents?.total_volume || gulps >= 20)
		return FALSE
	if(!bot.ready_in_hand(drink))
		return FALSE
	if(!drink.is_drainable())
		bot.toggle_in_hand(drink) //a can: pull the tab
		if(!drink.is_drainable())
			return FALSE
		wait_for = rand(5, 10)
		return TRUE
	var/before = drink.reagents.total_volume
	bot.use_item_on(drink, bot.owner)
	if(!QDELETED(drink) && drink.reagents.total_volume >= before)
		return FALSE
	gulps++
	bot.idle_fidget() //looks about between mouthfuls rather than staring at the machine
	wait_for = rand(30, 80)
	return TRUE

/datum/bot_step/paced/drink_up/finish(datum/bot_brain/bot)
	if(gulps)
		bot.drinks_drunk++
	// A bar glass goes back on the bar, empty or not, for the bartender to deal with.
	if(istype(drink, /obj/item/reagent_containers/food/drinks/drinkingglass) && !QDELETED(drink) && (drink in bot.owner.held_items))
		var/obj/structure/table/bar_top = locate() in range(1, bot.owner)
		if(!bar_top || !bot.use_tool_on(drink, bar_top))
			bot.put_away(drink, allow_equip = FALSE)
	drink = null
	bot.dispose_of_leftovers()
	return gulps ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

#undef BOT_NUTRITION_HUNGRY
#undef BOT_NUTRITION_ENOUGH
#undef BOT_MEAL_REACH
#undef BOT_DRINK_REACH
