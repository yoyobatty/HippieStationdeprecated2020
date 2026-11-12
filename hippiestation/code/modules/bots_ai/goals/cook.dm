// Cook: keeps a few plates of something out on the kitchen's serving counter, where anyone hungry
// helps themselves (goals/eat_and_drink.dm).
//
// The menu is the food a new cook starts on - one kind of ingredient, one machine, one button:
// eggs, meat or corn in the microwave; potatoes or carrots through the food processor; potatoes in the
// deep fryer. Produce comes out of the smartfridge the botanists stock, eggs and meat out of the
// kitchen's own fridges.
//
// One batch is one goal: gather a few of the ingredient (each fetch its own small errand, like the
// botanist's supplies), carry them to the machine, put them in one at a time, start it, wait, take
// what comes out over to the counter and set it down. All with the player's clicks: food on the
// microwave puts it in (microwave/attackby()) and Alt-click starts it; food on the processor puts it
// in and an empty-handed click runs it (processor/interact()); a dish on a table sets it down. The fryer
// takes one thing at a time: in with a click, out with an empty hand once it dings (deepfryer/attackby(),
// attack_hand()), and left twice as long it's burnt.

/// Ingredients in one batch.
#define BOT_COOK_BATCH 3
/// The counter is stocked enough at this many plates.
#define BOT_COOK_COUNTER_TARGET 6
#define BOT_KITCHEN_REACH 30

/datum/bot_recipe
	var/name
	/// What goes in, and how many of them make a batch worth starting the machine for.
	var/ingredient
	var/machine_type

/datum/bot_recipe/boiled_eggs
	name = "boiled eggs"
	ingredient = /obj/item/reagent_containers/food/snacks/egg
	machine_type = /obj/machinery/microwave

/datum/bot_recipe/steak
	name = "steak"
	ingredient = /obj/item/reagent_containers/food/snacks/meat/slab
	machine_type = /obj/machinery/microwave

/datum/bot_recipe/popcorn
	name = "popcorn"
	ingredient = /obj/item/reagent_containers/food/snacks/grown/corn
	machine_type = /obj/machinery/microwave

/datum/bot_recipe/tater_tots
	name = "tater tots"
	ingredient = /obj/item/reagent_containers/food/snacks/grown/potato
	machine_type = /obj/machinery/processor

/datum/bot_recipe/carrot_fries
	name = "carrot fries"
	ingredient = /obj/item/reagent_containers/food/snacks/grown/carrot
	machine_type = /obj/machinery/processor

/datum/bot_recipe/fried_potatoes
	name = "fried potatoes"
	ingredient = /obj/item/reagent_containers/food/snacks/grown/potato
	machine_type = /obj/machinery/deepfryer

/// Cooking oil a fryer wants in it to be worth starting a batch: one thing fried takes about five units.
#define BOT_FRYER_OIL 15

GLOBAL_LIST_INIT(bot_cook_menu, init_bot_cook_menu())

/proc/init_bot_cook_menu()
	. = list()
	for(var/path in subtypesof(/datum/bot_recipe))
		. += new path

/datum/bot_brain
	/// Machine or ingredient source -> world.time before it's worth another try.
	var/list/kitchen_blocked
	var/dishes_served = 0
	var/next_food_call_time = 0

/datum/bot_brain/proc/is_cook_job()
	return work_role() == "Cook"

/// Whether A is part of this cook's kitchen. A Bot Gym cook's kitchen is its arena.
/datum/bot_brain/proc/in_kitchen(atom/A)
	if(!A || QDELETED(A) || A.z != owner.z)
		return FALSE
	var/area/AR = get_area(A)
	return gym_run ? (AR == get_area(owner)) : istype(AR, /area/crew_quarters/kitchen)

/datum/bot_brain/proc/kitchen_usable(atom/A)
	return in_kitchen(A) && !(LAZYACCESS(kitchen_blocked, A) > world.time)

/// What's the kitchen's, to its cook: the dishes it has set out for the crew, the ingredients, the milk, the salt and pepper. Not
/// something to pocket on a stroll (find_item_goal(), bot_items.dm). In twelve shifts cooks took their own dishes back off the counter
/// 82 times, often within a second of setting them out, so the crew couldn't have them and the counter count fell and it cooked again
/// for its own pockets; the kitchen's milk, condiments and drinks went the same way another hundred times. A hungry cook still eats
/// there (have_meal).
/datum/bot_brain/proc/is_kitchen_stock(obj/item/I)
	return is_cook_job() && istype(I, /obj/item/reagent_containers/food) && in_kitchen(I)

// ---------------------------------------------------------------------------------------------
// Finding things in the kitchen
// ---------------------------------------------------------------------------------------------

/datum/bot_brain/proc/carried_ingredients(ingredient_type)
	. = list()
	for(var/obj/item/I in owner.GetAllContents())
		if(istype(I, ingredient_type))
			. += I

/// A machine of machine_type in the kitchen that's fit to use right now.
/datum/bot_brain/proc/find_kitchen_machine(machine_type)
	var/obj/machinery/best
	var/best_dist
	for(var/obj/machinery/M as anything in bot_instances_of(machine_type))
		if(!kitchen_usable(M) || (M.stat & (BROKEN|NOPOWER)) || M.panel_open || !M.anchored || taken_by_another(M))
			continue
		if(istype(M, /obj/machinery/microwave))
			var/obj/machinery/microwave/W = M
			if(W.operating || W.broken || W.dirty >= 100)
				continue
		if(istype(M, /obj/machinery/processor))
			var/obj/machinery/processor/P = M
			if(P.processing || istype(P, /obj/machinery/processor/slime))
				continue
		if(istype(M, /obj/machinery/deepfryer))
			var/obj/machinery/deepfryer/F = M
			if(F.frying || F.reagents?.get_reagent_amount(/datum/reagent/consumable/cooking_oil) < BOT_FRYER_OIL)
				continue //somebody's frying in it, or it's all but out of oil
		var/dist = get_dist(owner, M)
		if(!best || dist < best_dist)
			best = M
			best_dist = dist
	return best

/// Where to get one more of an ingredient: loose in the kitchen (an egg box counts for eggs), in the produce
/// smartfridge, or in a kitchen fridge that wants opening first.
/datum/bot_brain/proc/find_ingredient_source(ingredient_type)
	var/atom/best
	var/best_dist
	var/list/loose_types = list(ingredient_type)
	if(ispath(ingredient_type, /obj/item/reagent_containers/food/snacks/egg))
		loose_types += /obj/item/storage/fancy/egg_box
	for(var/loose_type in loose_types)
		for(var/obj/item/I as anything in bot_instances_of(loose_type))
			if(!isturf(I.loc) || !kitchen_usable(I) || (istype(I, /obj/item/storage) && !length(I.contents)))
				continue
			var/dist = get_dist(owner, I)
			if(!best || dist < best_dist)
				best = I
				best_dist = dist
	if(best)
		return best
	var/obj/machinery/smartfridge/fridge = find_produce_fridge() //goals/tend_hydroponics.dm
	if(fridge && !(LAZYACCESS(kitchen_blocked, fridge) > world.time) && (locate(ingredient_type) in fridge))
		return fridge
	for(var/obj/structure/closet/C as anything in bot_instances_of(/obj/structure/closet/secure_closet/freezer))
		if(C.opened || !kitchen_usable(C) || (C.locked && !C.allowed(owner)))
			continue
		var/holds = FALSE
		for(var/loose_type in loose_types)
			if(locate(loose_type) in C)
				holds = TRUE
				break
		if(!holds)
			continue
		var/dist = get_dist(owner, C)
		if(!best || dist < best_dist)
			best = C
			best_dist = dist
	return best

/// Dishes laid out on the kitchen's tables.
/datum/bot_brain/proc/dishes_on_counter()
	. = 0
	for(var/obj/item/reagent_containers/food/snacks/F as anything in bot_instances_of(/obj/item/reagent_containers/food/snacks))
		if(isturf(F.loc) && in_kitchen(F) && is_edible_now(F) && (locate(/obj/structure/table) in F.loc))
			.++

/// Whether a table has room on it for setting things down: no appliance sitting on it. The shutters and firelock a
/// serving hatch is built with don't count - leaving those tables out sent every dish to a table inside the kitchen.
/datum/bot_brain/proc/table_is_bare(obj/structure/table/T)
	for(var/obj/machinery/M in T.loc)
		if(!istype(M, /obj/machinery/door))
			return FALSE
	return TRUE

/// The table to set dishes down on: one the crew can reach from outside the kitchen, the emptiest first.
/datum/bot_brain/proc/find_serving_table()
	var/obj/structure/table/best
	var/best_score
	for(var/obj/structure/table/T as anything in bot_instances_of(/obj/structure/table))
		if(!in_kitchen(T) || !table_is_bare(T))
			continue
		var/reachable_from_outside = !!gym_run
		for(var/turf/open/next_to in get_adjacent_open_turfs(T))
			if(!in_kitchen(next_to) && !is_blocked_turf(next_to, TRUE))
				reachable_from_outside = TRUE
				break
		var/plates = 0
		for(var/obj/item/reagent_containers/food/snacks/F in T.loc)
			plates++
		// A counter the crew can get at beats any amount of space on a table they can't.
		var/score = (reachable_from_outside ? 0 : 100) + plates * 5 + get_dist(owner, T) * 0.1
		if(!best || score < best_score)
			best = T
			best_score = score
	return best

/// What to make next: something on the menu whose machine is free and whose ingredient can be had.
/datum/bot_brain/proc/pick_recipe()
	for(var/datum/bot_recipe/R as anything in shuffle(GLOB.bot_cook_menu))
		if(!find_kitchen_machine(R.machine_type))
			continue
		if(length(carried_ingredients(R.ingredient)) || find_ingredient_source(R.ingredient))
			return R
	return null

// ---------------------------------------------------------------------------------------------
// The round
// ---------------------------------------------------------------------------------------------

/datum/bot_duty/cook
	name = "cooking"
	jobs = list("Cook")
	interval_min = 60
	interval_max = 150

/datum/bot_duty/cook/try_start(datum/bot_brain/bot)
	if(bot.state == BOT_STATE_GOAL && bot.current_goal)
		return FALSE
	if(bot.dishes_on_counter() >= BOT_COOK_COUNTER_TARGET)
		return FALSE
	var/datum/bot_recipe/R = bot.pick_recipe()
	if(!R || !bot.find_serving_table())
		return FALSE
	return bot.assign_goal(new /datum/bot_goal/cook_dish(R))

/datum/bot_brain/proc/continue_cook_round()
	if(prob((1 - diligence) * 40))
		return
	var/datum/bot_duty/cook/duty = bot_duty_of(/datum/bot_duty/cook)
	continue_goal_chain(CALLBACK(duty, TYPE_PROC_REF(/datum/bot_duty, try_start), src))

// ---------------------------------------------------------------------------------------------
// One batch
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/cook_dish
	lawful = TRUE
	exclusive = TRUE //one cook to a machine
	var/datum/bot_recipe/recipe
	var/obj/structure/table/counter
	/// What came out of the machine, to be carried over and set down.
	var/list/obj/item/dishes
	/// More came out than it had a hand or bag room for: the rest is still where the machine put it, to come back for (on_success())
	var/left_at_machine = FALSE
	/// A trip back to the machine for what was left there, not a batch of its own: nothing to gather and nothing to put in
	var/obj/machinery/collect_from
	/// Trips back so far for what was left
	var/trips = 0

/datum/bot_goal/cook_dish/New(datum/bot_recipe/recipe)
	. = ..()
	src.recipe = recipe
	doing = "making [recipe.name]"

/datum/bot_goal/cook_dish/resolve_target(datum/bot_brain/bot)
	if(collect_from)
		target = bot.dishes_left_at(collect_from, recipe) ? collect_from : null
	else
		target = bot.find_kitchen_machine(recipe.machine_type)
	counter = bot.find_serving_table()
	if(!counter)
		target = null

/datum/bot_goal/cook_dish/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/cook/S = new
	var/datum/bot_step/move_to/to_counter = new
	to_counter.step_target = counter
	S.steps = collect_from ? list() : list(new /datum/bot_step/gather_ingredients())
	S.steps += list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/run_kitchen_machine(), to_counter, new /datum/bot_step/paced/serve_dishes())
	return list(S)

/datum/bot_goal/cook_dish/on_success(datum/bot_brain/bot)
	// What it had no hand for is still where the machine put it: back for it before anything new, as a cook carrying what it can at a
	// time does (run_kitchen_machine/do_click()). A few trips at most.
	if(left_at_machine && trips < 3 && bot.dishes_left_at(target, recipe))
		bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, fetch_dishes_left), recipe, target, trips + 1))
		return
	bot.continue_cook_round()

/// Food a kitchen machine put out that's still lying where it put it, and not what goes into it
/datum/bot_brain/proc/dishes_left_at(obj/machinery/machine, datum/bot_recipe/recipe)
	if(!machine || QDELETED(machine))
		return FALSE
	for(var/obj/item/reagent_containers/food/snacks/F in get_turf(machine))
		if(!istype(F, recipe.ingredient) && is_edible_now(F))
			return TRUE
	return FALSE

/// Back to the machine for the plates it had no hand for (cook_dish/on_success()), and over to the counter with them
/datum/bot_brain/proc/fetch_dishes_left(datum/bot_recipe/recipe, obj/machinery/machine, trip)
	var/datum/bot_goal/cook_dish/G = new(recipe)
	G.collect_from = machine
	G.trips = trip
	if(!assign_goal(G))
		return FALSE
	bot_log(src, "back to [machine] for the rest of the [recipe.name]")
	return TRUE

/datum/bot_goal/cook_dish/on_give_up(datum/bot_brain/bot)
	if(target)
		LAZYSET(bot.kitchen_blocked, target, world.time + 2 MINUTES)

/datum/bot_strategy/cook/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// A batch of the ingredient in the bag, fetched a source at a time. Makes do with fewer if that's all there is.
/datum/bot_step/gather_ingredients
	var/fetches = 0

/datum/bot_step/gather_ingredients/execute(datum/bot_brain/bot)
	var/datum/bot_goal/cook_dish/G = bot.current_goal
	if(!istype(G))
		return GOAL_STEP_FAIL
	var/have = length(bot.carried_ingredients(G.recipe.ingredient))
	if(have >= BOT_COOK_BATCH)
		return GOAL_STEP_SUCCESS
	if(fetches < 6)
		var/atom/source = bot.find_ingredient_source(G.recipe.ingredient)
		if(source)
			// One or two make a batch when that's all it has somewhere for (has_room_for(), goals/tend_hydroponics.dm: a free hand, or room
			// in the bag). Going for a third with its hands and bag full meant setting the last one down to pick the next one up: a cook
			// swapped the same two ears of corn at its feet five times running.
			var/obj/item/next_one = isitem(source) ? source : (locate(G.recipe.ingredient) in source)
			if(have && next_one && !bot.has_room_for(next_one))
				return GOAL_STEP_SUCCESS
			fetches++
			if(bot.suspend_goal_for(new /datum/bot_goal/fetch_ingredient(G.recipe.ingredient, source)))
				return GOAL_STEP_PENDING
	return have ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// One trip to one place an ingredient is kept.
/datum/bot_goal/fetch_ingredient
	lawful = TRUE
	doing = "getting ingredients"
	var/ingredient_type

/datum/bot_goal/fetch_ingredient/New(ingredient_type, atom/source)
	. = ..()
	src.ingredient_type = ingredient_type
	target = source

/datum/bot_goal/fetch_ingredient/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target))
		target = null

/datum/bot_goal/fetch_ingredient/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/cook/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/take_ingredient())
	return list(S)

/datum/bot_goal/fetch_ingredient/on_give_up(datum/bot_brain/bot)
	if(target)
		LAZYSET(bot.kitchen_blocked, target, world.time + 3 MINUTES)

/// At the source: open the fridge, take the produce out of the smartfridge, or pick the thing up - into the bag.
/datum/bot_step/take_ingredient/execute(datum/bot_brain/bot)
	var/datum/bot_goal/fetch_ingredient/G = bot.current_goal
	var/atom/source = G?.target
	if(!istype(G) || QDELETED(source) || !bot.owner.Adjacent(source))
		return GOAL_STEP_FAIL
	if(istype(source, /obj/structure/closet))
		bot_log(bot, "opening [source] for ingredients")
		return bot.open_closet(source) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
	if(istype(source, /obj/machinery/smartfridge))
		var/obj/machinery/smartfridge/fridge = source
		var/taken = 0
		// The fridge's own "release one" button, pressed once per item (smartfridge/ui_act()): it comes out into the hand.
		while(taken < BOT_COOK_BATCH && length(bot.carried_ingredients(G.ingredient_type)) < BOT_COOK_BATCH)
			var/obj/item/I = locate(G.ingredient_type) in fridge
			if(!I)
				break
			bot.human_pause(fridge)
			if(QDELETED(fridge) || QDELETED(I) || I.loc != fridge || !bot.owner.Adjacent(fridge))
				break
			// A hand for it before the button's pressed. With both full and no room in the bag, put_in_hands() tips what the fridge lets go of
			// onto the floor and says no: 55 of the 57 trips to the smartfridge given up in a batch of shifts were that, and each one wrote
			// the fridge off for three minutes. The first one gets a hand whatever that takes (make_hand_free(), goals/take_item.dm: what's
			// in it goes down for a moment, as it does for an ingredient off the floor); after that, only as many as there's somewhere for.
			if(taken && !bot.has_room_for(I))
				break
			bot.make_hand_free()
			bot.owner.face_atom(fridge)
			bot.telemetry_ui_action(fridge, "release [I.name]")
			if(!bot.owner.put_in_hands(I))
				break
			fridge.update_icon()
			bot.put_away(I, allow_equip = FALSE)
			taken++
		if(taken)
			bot_log(bot, "took [taken] [G.ingredient_type] out of [fridge]")
		return taken ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
	if(!bot.take_in_hand(source)) //goals/take_item.dm
		return GOAL_STEP_FAIL
	bot.put_away(source, allow_equip = FALSE)
	return GOAL_STEP_SUCCESS

/// At the machine: ingredients in one at a time, start it, wait for it, pick up what comes out.
/datum/bot_step/paced/run_kitchen_machine
	max_clicks = 40
	var/obj/machinery/machine
	var/loaded = 0
	var/started = FALSE
	var/waited = 0

/datum/bot_step/paced/run_kitchen_machine/start(datum/bot_brain/bot)
	machine = bot.current_goal?.target
	loaded = 0
	var/datum/bot_goal/cook_dish/G = bot.current_goal
	started = istype(G) && !!G.collect_from //back for what was left: nothing to put in, only to take out
	waited = 0
	return istype(machine) && !QDELETED(machine) && bot.owner.Adjacent(machine)

/datum/bot_step/paced/run_kitchen_machine/proc/still_running()
	var/obj/machinery/microwave/W = machine
	if(istype(W))
		return W.operating
	var/obj/machinery/processor/P = machine
	return istype(P) && P.processing

/// The fryer: one in, a wait for the ding, out with an empty hand and into the bag, and the next one in.
/datum/bot_step/paced/run_kitchen_machine/proc/fry_click(datum/bot_brain/bot, datum/bot_goal/cook_dish/G)
	var/obj/machinery/deepfryer/fryer = machine
	if(fryer.frying)
		if(!fryer.frying_fried)
			if(++waited > 150)
				return FALSE
			wait_for = 10
			if(prob(30))
				bot.idle_fidget()
			return TRUE
		var/obj/item/done = fryer.frying
		bot.make_hand_free() //goals/take_item.dm: it comes out into the hand
		bot.human_pause(fryer)
		if(QDELETED(fryer) || !bot.owner.Adjacent(fryer) || fryer.frying != done)
			return FALSE
		bot.use_atom(fryer)
		if(fryer.frying || QDELETED(done))
			return FALSE
		if(!bot.is_carried(done) && !bot.take_in_hand(done))
			return FALSE
		LAZYADD(G.dishes, done)
		bot.put_away(done, allow_equip = FALSE)
		waited = 0
		return TRUE
	var/list/ingredients = bot.carried_ingredients(G.recipe.ingredient)
	if(!length(ingredients) || loaded >= BOT_COOK_BATCH)
		return FALSE //the batch is done
	if(!loaded)
		bot_log(bot, "frying [G.recipe.name] in [fryer]")
	if(!bot.use_tool_on(ingredients[1], fryer) || !fryer.frying)
		return FALSE //it wouldn't go in
	loaded++
	return TRUE

/datum/bot_step/paced/run_kitchen_machine/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/cook_dish/G = bot.current_goal
	if(!istype(G) || QDELETED(machine) || !bot.owner.Adjacent(machine))
		return FALSE
	if(istype(machine, /obj/machinery/deepfryer))
		return fry_click(bot, G)
	if(!started)
		var/list/ingredients = bot.carried_ingredients(G.recipe.ingredient)
		if(length(ingredients) && loaded < BOT_COOK_BATCH)
			var/obj/item/I = ingredients[1]
			if(!loaded)
				bot_log(bot, "loading [machine] for [G.recipe.name]")
			if(!bot.use_tool_on(I, machine) || bot.is_carried(I))
				return FALSE //it wouldn't go in
			loaded++
			return TRUE
		if(!loaded)
			return FALSE
		started = TRUE
		bot.human_pause(machine)
		bot.owner.face_atom(machine)
		if(istype(machine, /obj/machinery/microwave))
			bot.telemetry_ui_action(machine, "start")
			machine.AltClick(bot.owner)
		else
			bot.use_atom(machine) //processor/interact(): runs it, and only returns once it's finished
		return TRUE
	if(still_running())
		if(G.collect_from)
			return FALSE //somebody's put a batch of their own on since: what was left is theirs to take out with it
		waited++
		if(waited > 60)
			return FALSE
		wait_for = 10
		if(prob(30))
			bot.idle_fidget()
		return TRUE
	// Done: take what came out, one thing at a time, as many as it has a hand or room in the bag for. With its hands and bag full each
	// one taken put the one before it down at its feet (make_hand_free()), beside a machine out of the counter's reach: never served, and
	// the cook went back for them later and kept them or ate them (bugs1112b: 11 plates in 10 batches; run11 Marlow Singh two steaks of
	// three, run6 Lee Montague ate the carrot fries it set down). The rest is left where the machine put it, and it comes back for it once
	// these are out (cook_dish/on_success()).
	for(var/obj/item/reagent_containers/food/snacks/F in get_turf(machine))
		if(istype(F, G.recipe.ingredient) || !bot.is_edible_now(F))
			continue
		if(length(G.dishes) && !bot.has_room_for(F)) //goals/tend_hydroponics.dm
			G.left_at_machine = TRUE
			return FALSE
		if(bot.take_in_hand(F))
			LAZYADD(G.dishes, F)
			return TRUE
	return FALSE

/datum/bot_step/paced/run_kitchen_machine/finish(datum/bot_brain/bot)
	var/datum/bot_goal/cook_dish/G = bot.current_goal
	machine = null
	return (istype(G) && length(G.dishes)) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// At the counter: each dish set down on the table.
/datum/bot_step/paced/serve_dishes
	max_clicks = 12
	var/served = 0

/datum/bot_step/paced/serve_dishes/start(datum/bot_brain/bot)
	var/datum/bot_goal/cook_dish/G = bot.current_goal
	served = 0
	return istype(G) && !QDELETED(G.counter) && bot.owner.Adjacent(G.counter)

/datum/bot_step/paced/serve_dishes/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/cook_dish/G = bot.current_goal
	if(!istype(G) || QDELETED(G.counter))
		return FALSE
	var/obj/item/dish = next_dish(bot, G.dishes)
	if(!dish)
		return FALSE
	G.dishes -= dish
	if(bot.use_tool_on(dish, G.counter) && !bot.is_carried(dish))
		served++
		bot.dishes_served++
	return TRUE

/// The next dish to put out: one in its hands, then one in its bag, then one it set down for a moment within reach. The hands come first,
/// the way the ingredients went into the machine (carried_ingredients() lists the hands before the bag). Bag first, a plate drawn out of
/// it with one in each hand set those two down at its feet to free a hand (ready_in_hand() -> free_hand_for()), and they were skipped as
/// no longer carried: a batch of three went out as one plate, and the cook went back for the other two and kept them (16 serves in 12
/// shifts). Last, one it set down beside a machine that stands by the counter, with nowhere to put the plate before it.
/datum/bot_step/paced/serve_dishes/proc/next_dish(datum/bot_brain/bot, list/dishes)
	for(var/obj/item/D in dishes)
		if(!QDELETED(D) && (D in bot.owner.held_items))
			return D
	for(var/obj/item/D in dishes)
		if(!QDELETED(D) && bot.is_carried(D))
			return D
	for(var/obj/item/D in dishes)
		if(!QDELETED(D) && isturf(D.loc) && bot.owner.Adjacent(D))
			return D
	return null

/datum/bot_step/paced/serve_dishes/finish(datum/bot_brain/bot)
	var/datum/bot_goal/cook_dish/G = bot.current_goal
	if(served && istype(G))
		bot_log(bot, "put [served] [G.recipe.name] out on the counter")
		// Lets the station know, now and then - the way a cook does when there's finally something to eat.
		if(world.time >= bot.next_food_call_time && !bot.gym_scripted)
			bot.next_food_call_time = world.time + 8 MINUTES
			bot.say_after_typing(";[pick("Food's up in the kitchen.", "Fresh [G.recipe.name] on the kitchen counter, help yourselves.", "Kitchen's open - [G.recipe.name] on the counter.")]")
	return served ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

#undef BOT_COOK_BATCH
#undef BOT_FRYER_OIL
#undef BOT_COOK_COUNTER_TARGET
#undef BOT_KITCHEN_REACH
