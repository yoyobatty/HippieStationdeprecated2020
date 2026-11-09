// Crafting, the way a player does it: the parts out of the bag onto the floor at its feet, and the crafting menu's Make
// (/datum/component/personal_crafting/construct_item(), the proc the menu's button runs, do_after and all). The user's ruling
// (2026-11-09), on the crew against a nanosuit: "Crafting is super useful for bots, bats, spiked bags, home made
// slows/stuns/weapons etc. they need to get creative here". What gets made, and where its parts come from:
//  - a bola: cable restraints (15 cable, through the coil's own menu) and six metal sheets. Thrown at a suit's legs.
//  - a stunprod: restraints, a rod (from a metal sheet) and an igniter, then a charged cell put in it.
//  - a spear: restraints, a glass shard and a rod. Only with a shard to hand: there are one to six on a whole map.
//  - a spiked bat: a baseball bat and five rods.
// Made in a hurry with a suit about (goals/fight_the_suit.dm), or ahead of time in a quiet shift, just in case.

/// The recipe datum the crafting menu uses, by type.
/proc/bot_crafting_recipe(recipe_type)
	RETURN_TYPE(/datum/crafting_recipe)
	for(var/datum/crafting_recipe/R as anything in GLOB.crafting_recipes)
		if(R.type == recipe_type)
			return R
	return null

/// One lot of `result_type` from a stack it's carrying, through the stack's own menu (stack/Topic "make"): rods and floor tiles
/// from metal, restraints from cable. Stacks made land on the floor and are picked up; anything else comes out in a hand.
/datum/bot_brain/proc/make_from_stack(stack_type, result_type, multiplier = 1)
	var/obj/item/stack/S = carried_stack(stack_type, 1)
	if(!S || !ready_in_hand(S))
		bot_log_verbose(src, "make_from_stack: [S ? "couldn't get [S] into a hand" : "no [stack_type] on it"]")
		return FALSE
	var/index = 0
	for(var/i in 1 to length(S.recipes))
		var/datum/stack_recipe/R = S.recipes[i]
		if(istype(R) && R.result_type == result_type)
			index = i
			break
	if(!index)
		return FALSE
	human_pause(S)
	if(QDELETED(S) || owner.get_active_held_item() != S)
		return FALSE
	usr = owner //the menu goes by whoever clicked it
	S.Topic(null, list("make" = "[index]", "multiplier" = "[multiplier]"))
	var/obj/item/made = locate(result_type) in owner.drop_location()
	if(made)
		free_hand_for(made) //bot_items.dm: both hands full (the stack and a shard) left the rods on the floor
		if(owner.put_in_hands(made))
			put_away(made, allow_equip = FALSE) //in the bag: the other hand's wanted for the next lot
	if(!find_carried_tool(result_type))
		bot_log_verbose(src, "make_from_stack: nothing made from [S] (left: [QDELETED(S) ? 0 : S.get_amount()], on the floor: [made || "nothing"])")
		return FALSE
	var/atom/what = result_type
	var/atom/from = stack_type
	bot_log(src, "made [initial(what.name)] from [initial(from.name)]")
	return TRUE

// ---------------------------------------------------------------------------------------------
// The parts
// ---------------------------------------------------------------------------------------------

/// How many of a recipe's part it has on it: a stack's amount, or a count of the things.
/datum/bot_brain/proc/craft_part_count(part_type)
	. = 0
	for(var/obj/item/I in owner.GetAllContents())
		if(!istype(I, part_type))
			continue
		if(istype(I, /obj/item/stack))
			var/obj/item/stack/S = I
			. += S.get_amount()
		else
			.++

/// The part of a recipe it hasn't got enough of yet, if any.
/datum/bot_brain/proc/craft_part_missing(datum/crafting_recipe/R)
	for(var/part_type in R.reqs)
		if(craft_part_count(part_type) < R.reqs[part_type])
			return part_type
	return null

/// Makes the part from something it's carrying, the way it's made by hand. TRUE if it made some.
/datum/bot_brain/proc/make_craft_part(part_type, needed)
	if(ispath(part_type, /obj/item/restraints/handcuffs/cable))
		return carried_stack(/obj/item/stack/cable_coil, 15) && make_from_stack(/obj/item/stack/cable_coil, /obj/item/restraints/handcuffs/cable)
	if(ispath(part_type, /obj/item/stack/rods))
		var/short = needed - craft_part_count(/obj/item/stack/rods)
		var/sheets = CEILING(short / 2, 1) //two rods a sheet
		return carried_stack(/obj/item/stack/sheet/metal, sheets) && make_from_stack(/obj/item/stack/sheet/metal, /obj/item/stack/rods, sheets)
	if(ispath(part_type, /obj/item/melee/baseball_bat)) //five planks, through the planks' own menu
		return carried_stack(/obj/item/stack/sheet/mineral/wood, 5) && make_from_stack(/obj/item/stack/sheet/mineral/wood, /obj/item/melee/baseball_bat)
	return FALSE

/// What to go and get for a part it can't make from what it has: the cable or the metal it's made from, or the thing itself.
/proc/bot_craft_part_source(part_type)
	if(ispath(part_type, /obj/item/restraints/handcuffs/cable))
		return /obj/item/stack/cable_coil
	if(ispath(part_type, /obj/item/stack/rods))
		return /obj/item/stack/sheet/metal
	if(ispath(part_type, /obj/item/melee/baseball_bat))
		return /obj/item/stack/sheet/mineral/wood
	return part_type

/// Whether it could make this right now from what's on it, without going anywhere: for a fight that's already on.
/datum/bot_brain/proc/can_craft_now(recipe_type)
	var/datum/crafting_recipe/R = bot_crafting_recipe(recipe_type)
	if(!R)
		return FALSE
	var/sheets_for_rods = 0
	for(var/part_type in R.reqs)
		var/short = R.reqs[part_type] - craft_part_count(part_type)
		if(short <= 0)
			continue
		if(ispath(part_type, /obj/item/restraints/handcuffs/cable))
			if(craft_part_count(/obj/item/stack/cable_coil) < 15)
				return FALSE
		else if(ispath(part_type, /obj/item/stack/rods))
			sheets_for_rods += CEILING(short / 2, 1)
		else
			return FALSE
	// The rods come out of whatever metal the recipe doesn't take as it is
	return craft_part_count(/obj/item/stack/sheet/metal) - (R.reqs[/obj/item/stack/sheet/metal] || 0) >= sheets_for_rods

// ---------------------------------------------------------------------------------------------
// The goal
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/craft
	lawful = TRUE
	doing = "making something"
	var/recipe_type
	/// Kept in hand for a fight that's on now, rather than put in the bag for later.
	var/keep_in_hand = FALSE
	/// Only what it's carrying: no going off for parts (a fight that's already on).
	var/no_fetching = FALSE
	/// What it made, once it has.
	var/obj/item/made
	/// Parts set down on the floor to work with, and picked back up after.
	var/list/laid_out

/datum/bot_goal/craft/New(recipe_type, keep_in_hand = FALSE, no_fetching = FALSE)
	. = ..()
	src.recipe_type = recipe_type
	src.keep_in_hand = keep_in_hand
	src.no_fetching = no_fetching
	var/datum/crafting_recipe/R = bot_crafting_recipe(recipe_type)
	if(R)
		doing = "making \a [lowertext(R.name)]"

/datum/bot_goal/craft/resolve_target(datum/bot_brain/bot)
	target = bot_crafting_recipe(recipe_type) && bot.owner.GetComponent(/datum/component/personal_crafting) ? bot.owner : null

/datum/bot_goal/craft/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/craft/S = new
	S.steps = list(new /datum/bot_step/get_craft_parts(), new /datum/bot_step/craft_it(), new /datum/bot_step/cell_for_it())
	return list(S)

/datum/bot_goal/craft/on_give_up(datum/bot_brain/bot)
	pick_up_laid_out(bot)

/datum/bot_goal/craft/proc/pick_up_laid_out(datum/bot_brain/bot)
	for(var/obj/item/I as anything in laid_out)
		if(QDELETED(I) || !isturf(I.loc) || get_dist(bot.owner, I) > 1)
			continue
		if(bot.owner.put_in_hands(I))
			bot.put_away(I, allow_equip = FALSE)
	laid_out = null

/datum/bot_strategy/craft/is_feasible(datum/bot_brain/bot)
	return TRUE

/// Each part it's short of: made from what it has (restraints from cable, rods from metal), or else fetched, once.
/datum/bot_step/get_craft_parts
	var/list/fetched

/datum/bot_step/get_craft_parts/execute(datum/bot_brain/bot)
	var/datum/bot_goal/craft/G = bot.current_goal
	var/datum/crafting_recipe/R = bot_crafting_recipe(G?.recipe_type)
	if(!R)
		return GOAL_STEP_FAIL
	// What it can make from what it has, one part after another (PENDING is only for waiting on a fetch: nothing calls back otherwise)
	var/part_type
	for(var/i in 1 to length(R.reqs))
		part_type = bot.craft_part_missing(R)
		if(!part_type)
			return GOAL_STEP_SUCCESS
		if(!bot.make_craft_part(part_type, R.reqs[part_type]))
			break
	bot.pick_up_set_down_here() //the toolbox put down to make rods comes straight back up
	part_type = bot.craft_part_missing(R)
	if(!part_type)
		return GOAL_STEP_SUCCESS
	var/source = bot_craft_part_source(part_type)
	var/atom/what = source
	// One trip for each, and up to three for planks: a barricade gives three, and a bat takes five
	var/trips = LAZYACCESS(fetched, source) || 0
	var/is_wood = ispath(source, /obj/item/stack/sheet/mineral/wood)
	if(G.no_fetching || trips >= (is_wood ? 3 : 1))
		bot_log(bot, "no [initial(what.name)] to be had for \a [lowertext(R.name)]")
		return GOAL_STEP_FAIL
	LAZYSET(fetched, source, trips + 1)
	if(is_wood)
		return bot.suspend_goal_for(new /datum/bot_goal/get_planks()) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL
	var/datum/bot_goal/acquire_item_type/get = new
	get.item_type = source
	get.lawful = TRUE
	get.doing = "getting [initial(what.name)] to make \a [lowertext(R.name)]"
	return bot.suspend_goal_for(get) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL

/// The parts out of the bag onto the floor at its feet, hands empty, and Make.
/datum/bot_step/craft_it

/datum/bot_step/craft_it/execute(datum/bot_brain/bot)
	var/datum/bot_goal/craft/G = bot.current_goal
	var/datum/crafting_recipe/R = bot_crafting_recipe(G?.recipe_type)
	var/datum/component/personal_crafting/menu = bot.owner.GetComponent(/datum/component/personal_crafting)
	var/mob/living/carbon/human/H = bot.owner
	if(!R || !menu || H.incapacitated() || !isturf(H.loc))
		return GOAL_STEP_FAIL
	// The crafting menu only sees what's in hand, in a pocket or within reach. Hands empty for the work: a part in one goes down on
	// the floor with the rest, anything else in the bag. What's in the bag comes out onto the floor.
	for(var/obj/item/I in H.held_items)
		if(is_type_in_list(I, R.reqs))
			if(H.dropItemToGround(I))
				LAZYADD(G.laid_out, I)
		else
			bot.stow_or_drop(I)
	for(var/part_type in R.reqs)
		for(var/obj/item/I in H.GetAllContents())
			if(!istype(I, part_type) || isturf(I.loc) || I == H.l_store || I == H.r_store || I == H.handcuffed)
				continue //already down, or in a pocket (within reach anyway)
			if(I.loc == H)
				if(!H.dropItemToGround(I)) //on the belt or in suit storage
					continue
			else
				I.forceMove(H.drop_location())
			LAZYADD(G.laid_out, I)
	bot.human_pause(H)
	var/list/where = list()
	var/turf/here = H.drop_location()
	for(var/part_type in R.reqs)
		for(var/obj/item/I in H.GetAllContents() + here.contents)
			if(istype(I, part_type))
				where += "[I] in [I.loc]"
	bot_log_verbose(bot, "parts for \a [lowertext(R.name)]: [jointext(where, ", ")]")
	bot_log(bot, "making \a [lowertext(R.name)]")
	var/failed = menu.construct_item(H, R) //waits out the recipe's time, as the menu does
	if(failed)
		var/list/seen = list()
		for(var/obj/item/I in menu.get_environment(H))
			seen += "[I]"
		bot_log(bot, "couldn't make \a [lowertext(R.name)][failed] (within reach: [jointext(seen, ", ")]; in hand: [jointext(H.held_items, ", ")])")
		G.pick_up_laid_out(bot)
		return GOAL_STEP_FAIL
	menu.on_recipe_crafted(H, R)
	G.made = locate(R.result) in H.held_items
	if(!G.made)
		G.made = locate(R.result) in H.drop_location()
		if(G.made && !H.put_in_hands(G.made))
			G.made = null
	G.pick_up_laid_out(bot)
	if(!G.made)
		return GOAL_STEP_FAIL
	bot_log(bot, "made \a [G.made]")
	bot_tally("crafted \a [lowertext(R.name)]")
	if(G.keep_in_hand)
		bot.ready_in_hand(G.made)
	else
		bot.put_away(G.made, allow_equip = FALSE)
	return GOAL_STEP_SUCCESS

/// A stunprod comes out of the menu with no cell: one that'll hold a stun's worth (a high-capacity one, a basic cell won't take)
/// goes in, from the bag or fetched. Anything else it made is done with.
/datum/bot_step/cell_for_it
	var/fetched = FALSE

/datum/bot_step/cell_for_it/execute(datum/bot_brain/bot)
	var/datum/bot_goal/craft/G = bot.current_goal
	var/obj/item/melee/baton/B = G?.made
	if(!istype(B) || B.cell)
		return GOAL_STEP_SUCCESS
	if(QDELETED(B) || !bot.is_carried(B))
		return GOAL_STEP_FAIL
	var/obj/item/stock_parts/cell/C
	for(var/obj/item/stock_parts/cell/candidate in bot.owner.GetAllContents())
		if(candidate.maxcharge >= B.hitcost && candidate.charge >= B.hitcost)
			C = candidate
			break
	if(!C)
		if(fetched)
			bot_log(bot, "no cell to be had for [B]")
			return GOAL_STEP_FAIL
		fetched = TRUE
		var/datum/bot_goal/acquire_item_type/get = new
		get.item_type = /obj/item/stock_parts/cell/high
		get.lawful = TRUE
		get.doing = "getting a cell for [B]"
		return bot.suspend_goal_for(get) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL
	if(!bot.ready_in_hand(C))
		return GOAL_STEP_FAIL
	bot.human_pause(B)
	B.attackby(C, bot.owner)
	if(!B.cell)
		bot_log(bot, "couldn't get [C] into [B]")
		return GOAL_STEP_FAIL
	bot_log(bot, "put [C] in [B]")
	if(!G.keep_in_hand)
		bot.put_away(B, allow_equip = FALSE)
	return GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// Planks, for a bat
// ---------------------------------------------------------------------------------------------

/// Planks lying about, or else a wooden barricade broken up for its planks (three from one, one from a crude one): maintenance has
/// them. The user's ruling (2026-11-09): bats are made from wooden planks, which come from breaking wooden barricades in maintenance.
/datum/bot_goal/get_planks
	lawful = TRUE
	doing = "getting some planks"

/datum/bot_goal/get_planks/resolve_target(datum/bot_brain/bot)
	var/list/sources = list() //source -> how far off
	for(var/obj/item/stack/sheet/mineral/wood/W as anything in bot_instances_of(/obj/item/stack/sheet/mineral/wood))
		if(!QDELETED(W) && isturf(W.loc) && W.z == bot.owner.z && get_dist(bot.owner, W) <= 60)
			sources[W] = get_dist(bot.owner, W)
	for(var/obj/structure/barricade/wooden/B in bot_instances_of(/obj/structure/barricade/wooden))
		if(!QDELETED(B) && B.z == bot.owner.z && get_dist(bot.owner, B) <= 60)
			sources[B] = get_dist(bot.owner, B) + 5 //breaking one up takes a while
	var/tries = 0
	while(length(sources) && tries++ < 8)
		var/atom/nearest
		for(var/atom/A as anything in sources)
			if(!nearest || sources[A] < sources[nearest])
				nearest = A
		sources -= nearest
		if(bot.gym_run ? get_area(nearest) == get_area(bot.owner) : bot.can_walk_lawfully_to(nearest))
			target = nearest
			return

/datum/bot_goal/get_planks/get_strategies(datum/bot_brain/bot)
	if(istype(target, /obj/item))
		return list(new /datum/bot_strategy/grab_item())
	var/datum/bot_strategy/craft/S = new
	var/datum/bot_step/move_to/walk = new
	walk.step_target = target
	S.steps = list(walk, new /datum/bot_step/paced/break_barricade())
	return list(S)

/// What it set down a moment ago within reach, back in hand or in the bag: a person who puts a toolbox down to use both hands
/// picks it up again once they're done.
/datum/bot_brain/proc/pick_up_set_down_here()
	for(var/obj/item/I as anything in set_down_items)
		if(QDELETED(I) || !isturf(I.loc) || !owner.Adjacent(I))
			continue
		free_hand_for(I)
		if(!owner.put_in_hands(I))
			continue
		LAZYREMOVE(set_down_items, I)
		if(!put_away(I, allow_equip = FALSE))
			continue //too big for the bag (a toolbox): it stays in hand

/// The heaviest thing on it that isn't a crafting part (a rod or a plank does next to nothing to a barricade).
/datum/bot_brain/proc/heaviest_smasher()
	RETURN_TYPE(/obj/item)
	var/obj/item/heaviest
	for(var/obj/item/I in owner.GetAllContents())
		if(istype(I, /obj/item/gun) || istype(I, /obj/item/stack) || istype(I, /obj/item/storage/backpack) || HAS_TRAIT(I, TRAIT_NODROP))
			continue
		if(I.loc == owner && !(I in owner.held_items))
			continue //worn
		if(I.force > 0 && (!heaviest || I.force > heaviest.force))
			heaviest = I
	return heaviest

/// Swings at the barricade with the heaviest thing on it until it comes apart, then picks up the planks.
/datum/bot_step/paced/break_barricade
	max_clicks = 30
	var/obj/structure/barricade/wooden/barricade
	var/turf/where

/datum/bot_step/paced/break_barricade/start(datum/bot_brain/bot)
	barricade = bot.current_goal?.target
	where = get_turf(barricade)
	return istype(barricade) && bot.owner.Adjacent(barricade)

/datum/bot_step/paced/break_barricade/do_click(datum/bot_brain/bot)
	if(QDELETED(barricade))
		return FALSE
	var/obj/item/heaviest = bot.heaviest_smasher()
	if(!heaviest || !bot.ready_in_hand(heaviest))
		bot_log(bot, "nothing to break [barricade] up with")
		return FALSE
	if(clicks == 0)
		bot_log(bot, "breaking up [barricade] for the planks, with [heaviest]")
	bot.owner.changeNext_move(CLICK_CD_MELEE)
	bot.use_item_on(heaviest, barricade, TRUE)
	return TRUE

/datum/bot_step/paced/break_barricade/finish(datum/bot_brain/bot)
	if(!QDELETED(barricade))
		bot_log(bot, "couldn't get [barricade] apart")
		return GOAL_STEP_FAIL
	var/got = 0
	for(var/obj/item/stack/sheet/mineral/wood/W in where)
		bot.free_hand_for(W)
		if(bot.owner.put_in_hands(W))
			got += W.get_amount()
			bot.put_away(W, allow_equip = FALSE)
	bot_log(bot, "broke up a barricade: [got] planks")
	return got ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
