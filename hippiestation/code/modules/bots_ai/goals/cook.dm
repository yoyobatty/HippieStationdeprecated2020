// Cook: keeps a few plates of something out on the kitchen's serving counter, where anyone hungry
// helps themselves (goals/eat_and_drink.dm).
//
// The menu is the food a new cook starts on - one kind of ingredient, one machine, one button:
// eggs, meat or corn in the microwave; potatoes or carrots through the food processor. Produce comes
// out of the smartfridge the botanists stock, eggs and meat out of the kitchen's own fridges.
//
// One batch is one goal: gather a few of the ingredient (each fetch its own small errand, like the
// botanist's supplies), carry them to the machine, put them in one at a time, start it, wait, take
// what comes out over to the counter and set it down. All with the player's clicks: food on the
// microwave puts it in (microwave/attackby()) and Alt-click starts it; food on the processor puts it
// in and an empty-handed click runs it (processor/interact()); a dish on a table sets it down.

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
	return owner.mind?.assigned_role == "Cook"

/// Whether A is part of this cook's kitchen. A Bot Gym cook's kitchen is its arena.
/datum/bot_brain/proc/in_kitchen(atom/A)
	if(!A || QDELETED(A) || A.z != owner.z)
		return FALSE
	var/area/AR = get_area(A)
	return gym_run ? (AR == get_area(owner)) : istype(AR, /area/crew_quarters/kitchen)

/datum/bot_brain/proc/kitchen_usable(atom/A)
	return in_kitchen(A) && !(LAZYACCESS(kitchen_blocked, A) > world.time)

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

/datum/bot_goal/cook_dish/New(datum/bot_recipe/recipe)
	. = ..()
	src.recipe = recipe
	doing = "making [recipe.name]"

/datum/bot_goal/cook_dish/resolve_target(datum/bot_brain/bot)
	target = bot.find_kitchen_machine(recipe.machine_type)
	counter = bot.find_serving_table()
	if(!counter)
		target = null

/datum/bot_goal/cook_dish/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/cook/S = new
	var/datum/bot_step/move_to/to_counter = new
	to_counter.step_target = counter
	S.steps = list(new /datum/bot_step/gather_ingredients(), new /datum/bot_step/move_to(), new /datum/bot_step/paced/run_kitchen_machine(), to_counter, new /datum/bot_step/paced/serve_dishes())
	return list(S)

/datum/bot_goal/cook_dish/on_success(datum/bot_brain/bot)
	bot.continue_cook_round()

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
			bot.owner.face_atom(fridge)
			bot.telemetry_ui_action(fridge, "release [I.name]")
			if(bot.owner.get_active_held_item() && bot.owner.get_inactive_held_item())
				bot.put_away(bot.owner.get_active_held_item(), allow_equip = FALSE)
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
	started = FALSE
	waited = 0
	return istype(machine) && !QDELETED(machine) && bot.owner.Adjacent(machine)

/datum/bot_step/paced/run_kitchen_machine/proc/still_running()
	var/obj/machinery/microwave/W = machine
	if(istype(W))
		return W.operating
	var/obj/machinery/processor/P = machine
	return istype(P) && P.processing

/datum/bot_step/paced/run_kitchen_machine/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/cook_dish/G = bot.current_goal
	if(!istype(G) || QDELETED(machine) || !bot.owner.Adjacent(machine))
		return FALSE
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
		waited++
		if(waited > 60)
			return FALSE
		wait_for = 10
		if(prob(30))
			bot.idle_fidget()
		return TRUE
	// Done: take what came out, one thing at a time.
	for(var/obj/item/reagent_containers/food/snacks/F in get_turf(machine))
		if(istype(F, G.recipe.ingredient) || !bot.is_edible_now(F))
			continue
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
	for(var/obj/item/dish in G.dishes)
		G.dishes -= dish
		if(QDELETED(dish) || !bot.is_carried(dish))
			continue
		if(bot.use_tool_on(dish, G.counter) && !bot.is_carried(dish))
			served++
			bot.dishes_served++
		return TRUE
	return FALSE

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
#undef BOT_COOK_COUNTER_TARGET
#undef BOT_KITCHEN_REACH
