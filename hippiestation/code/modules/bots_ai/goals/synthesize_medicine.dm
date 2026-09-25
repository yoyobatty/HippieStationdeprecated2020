// Medicine production: a Chemist (or a Doctor/CMO with nothing more urgent to do)
// dispenses base reagents into a beaker, lets the chemical_reaction engine auto-mix
// them into a real medicine, runs it through the ChemMaster to package it as either a
// pill (swallowed) or a patch (touch-applied), then stashes the output in a smart
// chemical fridge for other staff to grab. Every reaction below only uses base
// reagents already on the STANDARD chem dispenser's dispensable_reagents list
// (chem_dispenser.dm) - nothing here depends on upgraded parts or emag-only chemicals.
GLOBAL_LIST_INIT(bot_medicine_recipes, list(
	list("reagent" = /datum/reagent/medicine/bicaridine, "ingredients" = list(/datum/reagent/carbon = 10, /datum/reagent/oxygen = 10, /datum/reagent/consumable/sugar = 10), "form" = "pill", "label" = "bicaridine"),
	list("reagent" = /datum/reagent/medicine/kelotane, "ingredients" = list(/datum/reagent/carbon = 10, /datum/reagent/silicon = 10), "form" = "pill", "label" = "kelotane"),
	list("reagent" = /datum/reagent/medicine/styptic_powder, "ingredients" = list(/datum/reagent/aluminium = 5, /datum/reagent/hydrogen = 5, /datum/reagent/oxygen = 5, /datum/reagent/toxin/acid = 5), "form" = "patch", "label" = "styptic powder"),
))

/datum/bot_brain/proc/is_chem_producer_job()
	var/role = owner.mind?.assigned_role
	return role == "Medical Doctor" || role == "Chief Medical Officer" || role == "Chemist"

#define BOT_CHEM_REACH 60

/datum/bot_brain/proc/find_reachable_chem_dispenser()
	var/obj/machinery/chem_dispenser/best
	var/best_dist
	for(var/obj/machinery/chem_dispenser/D in GLOB.machines)
		if(istype(D, /obj/machinery/chem_dispenser/drinks) || istype(D, /obj/machinery/chem_dispenser/mutagen))
			continue //not a chemistry dispenser
		if(D.z != owner.z || !D.is_operational())
			continue
		var/dist = get_dist(owner, D)
		if(dist > BOT_CHEM_REACH)
			continue
		if(!best || dist < best_dist)
			best = D
			best_dist = dist
	return best

/datum/bot_brain/proc/find_reachable_chem_master()
	var/obj/machinery/chem_master/best
	var/best_dist
	for(var/obj/machinery/chem_master/M in GLOB.machines)
		if(istype(M, /obj/machinery/chem_master/condimaster))
			continue
		if(M.z != owner.z)
			continue
		var/dist = get_dist(owner, M)
		if(dist > BOT_CHEM_REACH)
			continue
		if(!best || dist < best_dist)
			best = M
			best_dist = dist
	return best

// Optional - a fridge to stock isn't essential to the goal succeeding, see
// synthesize_medicine/get_strategies() below.
/datum/bot_brain/proc/find_reachable_chem_fridge()
	var/obj/machinery/smartfridge/chemistry/best
	var/best_dist
	for(var/obj/machinery/smartfridge/chemistry/F in GLOB.machines)
		if(istype(F, /obj/machinery/smartfridge/chemistry/virology))
			continue //samples, not medicine
		if(F.z != owner.z || (F.stat & (BROKEN|NOPOWER)))
			continue
		var/dist = get_dist(owner, F)
		if(dist > BOT_CHEM_REACH)
			continue
		if(!best || dist < best_dist)
			best = F
			best_dist = dist
	return best

#undef BOT_CHEM_REACH

/datum/bot_brain/proc/find_empty_beaker()
	for(var/obj/item/reagent_containers/glass/beaker/B in owner.GetAllContents())
		if(!B.reagents || !B.reagents.total_volume)
			return B
	return null

// Replicates chem_dispenser's own ui_act("dispense",...) logic (chem_dispenser.dm)
// directly against the object instead of going through Topic()/params, which needs a
// real `usr` this bot doesn't have.
/datum/bot_brain/proc/dispense_into_beaker(obj/machinery/chem_dispenser/D, reagent_type, amount)
	if(!D || QDELETED(D) || !D.beaker || !D.cell || !D.is_operational())
		return FALSE
	if(!D.dispensable_reagents.Find(reagent_type))
		return FALSE
	var/datum/reagents/R = D.beaker.reagents
	var/free = R.maximum_volume - R.total_volume
	var/actual = min(amount, (D.cell.charge * D.powerefficiency) * 10, free)
	if(actual <= 0)
		return FALSE
	if(!D.cell.use(actual / D.powerefficiency))
		return FALSE
	R.add_reagent(reagent_type, actual)
	D.work_animation()
	D.update_icon()
	return TRUE

/datum/bot_goal/synthesize_medicine
	var/list/recipe
	var/obj/machinery/chem_dispenser/dispenser
	var/obj/machinery/chem_master/master
	var/atom/fridge //may stay null - see find_reachable_chem_fridge()
	var/list/produced_items

/datum/bot_goal/synthesize_medicine/resolve_target(datum/bot_brain/bot)
	var/obj/machinery/chem_dispenser/D = bot.find_reachable_chem_dispenser()
	if(!D)
		return
	var/obj/machinery/chem_master/M = bot.find_reachable_chem_master()
	if(!M)
		return
	recipe = pick(GLOB.bot_medicine_recipes)
	dispenser = D
	master = M
	fridge = bot.find_reachable_chem_fridge()
	target = D

/datum/bot_goal/synthesize_medicine/get_strategies(datum/bot_brain/bot)
	return list(new /datum/bot_strategy/synthesize(dispenser, master, fridge))

/datum/bot_goal/synthesize_medicine/on_success(datum/bot_brain/bot)
	bot.continue_medical_round()

/datum/bot_strategy/synthesize
	var/obj/machinery/chem_dispenser/dispenser
	var/obj/machinery/chem_master/master
	var/atom/fridge

/datum/bot_strategy/synthesize/New(obj/machinery/chem_dispenser/D, obj/machinery/chem_master/M, atom/F)
	. = ..()
	dispenser = D
	master = M
	fridge = F
	var/datum/bot_step/move_to/to_master = new()
	to_master.step_target = M
	steps = list(
		new /datum/bot_step/ensure_beaker(),
		new /datum/bot_step/move_to(), //to dispenser (goal.target)
		new /datum/bot_step/load_beaker_into_dispenser(D),
		new /datum/bot_step/dispense_ingredients(D),
		new /datum/bot_step/retrieve_beaker_from_dispenser(D),
		to_master,
		new /datum/bot_step/load_beaker_into_master(M),
		new /datum/bot_step/produce_medicine(M),
	)
	if(fridge)
		var/datum/bot_step/move_to/to_fridge = new()
		to_fridge.step_target = F
		steps += to_fridge
		steps += new /datum/bot_step/store_products(F)

/datum/bot_strategy/synthesize/is_feasible(datum/bot_brain/bot)
	return dispenser && !QDELETED(dispenser) && master && !QDELETED(master)

/datum/bot_step/ensure_beaker
	var/tried_fetch = FALSE

/datum/bot_step/ensure_beaker/execute(datum/bot_brain/bot)
	if(bot.find_empty_beaker())
		return GOAL_STEP_SUCCESS
	if(!tried_fetch)
		tried_fetch = TRUE
		var/datum/bot_goal/acquire_item_type/sub = new()
		sub.item_type = /obj/item/reagent_containers/glass/beaker
		if(bot.suspend_goal_for(sub))
			return GOAL_STEP_PENDING
	bot_log(bot, "no empty beaker reachable to synthesize medicine with")
	return GOAL_STEP_FAIL

/datum/bot_step/load_beaker_into_dispenser
	var/obj/machinery/chem_dispenser/dispenser

/datum/bot_step/load_beaker_into_dispenser/New(obj/machinery/chem_dispenser/D)
	. = ..()
	dispenser = D

/datum/bot_step/load_beaker_into_dispenser/execute(datum/bot_brain/bot)
	if(!dispenser || QDELETED(dispenser))
		return GOAL_STEP_FAIL
	if(dispenser.beaker)
		return GOAL_STEP_SUCCESS
	if(!bot.owner.Adjacent(dispenser))
		return GOAL_STEP_FAIL
	var/obj/item/reagent_containers/glass/beaker/B = bot.find_empty_beaker()
	if(!B)
		return GOAL_STEP_FAIL
	bot.use_item_on(B, dispenser)
	return dispenser.beaker ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// Pace-limited the same way pickup_tool_from_target (bot_goals.dm) grabs multiple tools
// one at a time - dispensing every ingredient in a single synchronous instant reads as
// an obviously inhuman "vacuum" rather than someone actually working the machine.
/datum/bot_step/dispense_ingredients
	var/obj/machinery/chem_dispenser/dispenser
	var/list/pending

/datum/bot_step/dispense_ingredients/New(obj/machinery/chem_dispenser/D)
	. = ..()
	dispenser = D

/datum/bot_step/dispense_ingredients/execute(datum/bot_brain/bot)
	if(!dispenser || QDELETED(dispenser) || !dispenser.beaker)
		return GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(dispenser))
		return GOAL_STEP_FAIL
	if(!pending)
		var/datum/bot_goal/synthesize_medicine/goal = bot.current_goal
		pending = goal.recipe["ingredients"].Copy()
	return dispense_next(bot)

/datum/bot_step/dispense_ingredients/proc/dispense_next(datum/bot_brain/bot)
	if(!pending || !pending.len)
		pending = null
		return GOAL_STEP_SUCCESS
	var/reagent_type = pending[1]
	var/amount = pending[reagent_type]
	pending -= reagent_type
	bot.dispense_into_beaker(dispenser, reagent_type, amount)
	bot.owner.changeNext_move(CLICK_CD_MELEE)
	if(pending.len)
		addtimer(CALLBACK(src, PROC_REF(continue_dispense), bot), CLICK_CD_MELEE)
		return GOAL_STEP_PENDING
	pending = null
	return GOAL_STEP_SUCCESS

/datum/bot_step/dispense_ingredients/proc/continue_dispense(datum/bot_brain/bot)
	if(QDELETED(bot) || bot.state != BOT_STATE_GOAL || bot.current_strategy?.steps?[bot.current_step_index] != src)
		return //goal moved on while we were waiting - don't act on stale state
	var/result = dispense_next(bot)
	if(result != GOAL_STEP_PENDING)
		bot.advance_goal_step(result == GOAL_STEP_SUCCESS)

/datum/bot_step/retrieve_beaker_from_dispenser
	var/obj/machinery/chem_dispenser/dispenser

/datum/bot_step/retrieve_beaker_from_dispenser/New(obj/machinery/chem_dispenser/D)
	. = ..()
	dispenser = D

/datum/bot_step/retrieve_beaker_from_dispenser/execute(datum/bot_brain/bot)
	if(!dispenser || QDELETED(dispenser))
		return GOAL_STEP_FAIL
	if(!dispenser.beaker)
		return GOAL_STEP_SUCCESS
	if(!bot.owner.Adjacent(dispenser))
		return GOAL_STEP_FAIL
	dispenser.replace_beaker(bot.owner)
	return GOAL_STEP_SUCCESS

/datum/bot_step/load_beaker_into_master
	var/obj/machinery/chem_master/master

/datum/bot_step/load_beaker_into_master/New(obj/machinery/chem_master/M)
	. = ..()
	master = M

/datum/bot_step/load_beaker_into_master/execute(datum/bot_brain/bot)
	if(!master || QDELETED(master))
		return GOAL_STEP_FAIL
	if(master.beaker)
		return GOAL_STEP_SUCCESS
	if(!bot.owner.Adjacent(master))
		return GOAL_STEP_FAIL
	var/obj/item/reagent_containers/glass/beaker/B = locate(/obj/item/reagent_containers/glass/beaker) in bot.owner.GetAllContents()
	if(!B)
		return GOAL_STEP_FAIL
	bot.use_item_on(B, master)
	return master.beaker ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// Moves the synthesized reagent from the loaded beaker into the ChemMaster's buffer
// (replicating ui_act("transfer",...)'s beaker->buffer branch, chem_master.dm) and
// packages it as a pill or a patch depending on the recipe's "form" - matching how
// this codebase's own premade products split: touch-applied trauma treatments
// (styptic/silver_sulf) ship as patches, ingested ones (bicaridine/kelotane) as pills.
/datum/bot_step/produce_medicine
	var/obj/machinery/chem_master/master

/datum/bot_step/produce_medicine/New(obj/machinery/chem_master/M)
	. = ..()
	master = M

/datum/bot_step/produce_medicine/execute(datum/bot_brain/bot)
	if(!master || QDELETED(master) || !master.beaker)
		return GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(master))
		return GOAL_STEP_FAIL
	var/datum/bot_goal/synthesize_medicine/goal = bot.current_goal
	var/reagent_type = goal.recipe["reagent"]
	var/amount = master.beaker.reagents.get_reagent_amount(reagent_type)
	if(amount <= 0)
		bot_log(bot, "the mix didn't yield any [goal.recipe["label"]] - discarding and returning the beaker")
		master.replace_beaker(bot.owner)
		return GOAL_STEP_FAIL
	master.beaker.reagents.trans_id_to(master, reagent_type, amount)
	master.replace_beaker(bot.owner) //hands the (now empty of the useful reagent) beaker back for reuse

	var/vol_each = min(20, master.reagents.total_volume)
	var/produce_amount = clamp(round(master.reagents.total_volume / max(vol_each, 1)), 1, 5)
	var/list/produced = list()
	for(var/i in 1 to produce_amount)
		var/obj/item/reagent_containers/pill/P
		if(goal.recipe["form"] == "patch")
			P = new /obj/item/reagent_containers/pill/patch(master.drop_location())
			P.name = trim("[goal.recipe["label"]] patch")
		else
			P = new /obj/item/reagent_containers/pill(master.drop_location())
			P.name = trim("[goal.recipe["label"]] pill")
		master.reagents.trans_to(P, vol_each, transfered_by = bot.owner)
		bot.try_pickup_target(P) //carried onward - fridge delivery (store_products) expects these already in hand, not left sitting by the master
		produced += P
	goal.produced_items = produced
	bot_log(bot, "produced [produced.len]x [goal.recipe["label"]] [goal.recipe["form"]][goal.produced_items.len ? "" : " (couldn't carry any of it)"]")
	return GOAL_STEP_SUCCESS

/datum/bot_step/store_products
	var/atom/fridge

/datum/bot_step/store_products/New(atom/F)
	. = ..()
	fridge = F

/datum/bot_step/store_products/execute(datum/bot_brain/bot)
	var/datum/bot_goal/synthesize_medicine/goal = bot.current_goal
	if(!fridge || QDELETED(fridge) || !goal.produced_items || !goal.produced_items.len)
		return GOAL_STEP_SUCCESS //nothing left to store - not a failure, the medicine still exists (on the bot or the floor)
	if(!bot.owner.Adjacent(fridge))
		return GOAL_STEP_FAIL
	return store_next(bot)

/datum/bot_step/store_products/proc/store_next(datum/bot_brain/bot)
	var/datum/bot_goal/synthesize_medicine/goal = bot.current_goal
	while(goal.produced_items.len)
		var/obj/item/I = goal.produced_items[1]
		goal.produced_items.Cut(1, 2)
		if(QDELETED(I))
			continue
		bot.use_item_on(I, fridge)
		bot.owner.changeNext_move(CLICK_CD_MELEE)
		if(goal.produced_items.len)
			addtimer(CALLBACK(src, PROC_REF(continue_store), bot), CLICK_CD_MELEE)
			return GOAL_STEP_PENDING
		break
	return GOAL_STEP_SUCCESS

/datum/bot_step/store_products/proc/continue_store(datum/bot_brain/bot)
	if(QDELETED(bot) || bot.state != BOT_STATE_GOAL || bot.current_strategy?.steps?[bot.current_step_index] != src)
		return
	var/result = store_next(bot)
	if(result != GOAL_STEP_PENDING)
		bot.advance_goal_step(result == GOAL_STEP_SUCCESS)
