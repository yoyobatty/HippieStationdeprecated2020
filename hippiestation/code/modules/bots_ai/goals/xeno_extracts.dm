// What Xenobiology's extracts are for (the user's ask, 2026-11-12: "full science"; goals/xenobiology.dm is the breeding and the
// harvest). A player in the lab doesn't leave the cores in the fridge: a drop of plasma on one, or of water, sets it off
// (reagents/chemistry/recipes/slime_extracts.dm), and the useful ones get made and used.
//
//  - Plasma: a sheet of the lab's through the grinder into a beaker (reagentgrinder/grind()). Water: a beaker under the sink.
//  - A dropper of it onto the extract, set down at its feet (dropper/afterattack(): five units, and one is all a reaction wants).
//  - What comes of it, by colour:
//      metal: metal sheets (plasma), or glass (water) when somebody's short of glass   -> the protolathe, which takes sheets for the
//      dark purple: plasma sheets; adamantine: adamantine; bluespace: a bluespace crystal   ore silo every lathe draws on
//      yellow: a slime power cell   -> left on a table in Robotics, for whoever wants a cell
//      purple: steroid   -> on a baby slime from the console, for one more extract out of it
//      red: mutator   -> on a slime from the console, for more new colours from its splits: breeding on purpose
//      cerulean: enhancer   -> on another extract, for one more use of it
//    The rest stay in the fridge: orange is fire, gold makes monsters, oil goes off, green and black turn people into slimes.
//  - Potions go on the slimes through the console (its potion slot: xenobio/attackby(), then the potion on the slime where the camera
//    sees it, XenoSlimeClickAlt()), so nobody goes into a pen for it.

/// Colour -> the reagent that makes something useful of it.
GLOBAL_LIST_INIT(bot_extract_reagents, list(
	/obj/item/slime_extract/metal = /datum/reagent/toxin/plasma,
	/obj/item/slime_extract/darkpurple = /datum/reagent/toxin/plasma,
	/obj/item/slime_extract/adamantine = /datum/reagent/toxin/plasma,
	/obj/item/slime_extract/bluespace = /datum/reagent/toxin/plasma,
	/obj/item/slime_extract/yellow = /datum/reagent/toxin/plasma,
	/obj/item/slime_extract/purple = /datum/reagent/toxin/plasma,
	/obj/item/slime_extract/red = /datum/reagent/toxin/plasma,
	/obj/item/slime_extract/cerulean = /datum/reagent/toxin/plasma,
))

/// Potions it keeps for the slimes, or for an extract.
GLOBAL_LIST_INIT(bot_slime_potions, list(/obj/item/slimepotion/slime/steroid, /obj/item/slimepotion/slime/mutator, /obj/item/slimepotion/enhancer))

/datum/bot_brain
	var/extracts_used = 0
	var/potions_given = 0
	var/xeno_extract_rest_until = 0

/// The reagent this extract wants, if it's a colour worth using and it has a use left.
/proc/bot_extract_reagent(obj/item/slime_extract/E)
	if(!istype(E) || E.Uses <= 0)
		return null
	. = GLOB.bot_extract_reagents[E.type]
	if(istype(E, /obj/item/slime_extract/metal) && bot_mineral_wanted(MAT_GLASS))
		return /datum/reagent/water //somebody's short of glass: water makes glass of it

/// An extract worth using: one it carries, one lying about the lab, or one in the extract fridge.
/datum/bot_brain/proc/usable_extract()
	for(var/obj/item/slime_extract/E in owner.GetAllContents(/obj/item/slime_extract))
		if(bot_extract_reagent(E))
			return E
	for(var/obj/item/slime_extract/E as anything in bot_instances_of(/obj/item/slime_extract))
		if(QDELETED(E) || !bot_extract_reagent(E) || taken_by_another(E))
			continue
		var/turf/T = get_turf(E)
		if(!T || T.z != my_z() || !in_xenobiology(E))
			continue
		if(isturf(E.loc) || istype(E.loc, /obj/machinery/smartfridge))
			return E
	return null

/// A potion it has, and what it's for: TRUE if there's something to use it on.
/datum/bot_brain/proc/carried_slime_potion()
	for(var/path in GLOB.bot_slime_potions)
		var/obj/item/slimepotion/P = locate(path) in owner.GetAllContents(path)
		if(P)
			return P
	return null

/// What came out of an extract that wants taking somewhere: sheets and crystals for the protolathe, a power cell for Robotics.
/datum/bot_brain/proc/carried_extract_produce()
	for(var/obj/item/I in owner.GetAllContents())
		if(I.bot_extract_produce)
			return I
	return null

/// Marked on what an extract made, so it's known for what it is when it's being carried about.
/obj/item/var/bot_extract_produce = FALSE

/datum/bot_duty/xeno_extracts
	name = "using the slime extracts"
	jobs = list("Scientist", "Research Director")
	priority = 3
	interval_min = 300
	interval_max = 700

/datum/bot_duty/xeno_extracts/try_start(datum/bot_brain/bot)
	if(world.time < bot.xeno_extract_rest_until)
		return FALSE
	var/obj/item/produce = bot.carried_extract_produce()
	if(produce)
		return bot.assign_goal(new /datum/bot_goal/xeno_extract/deliver(produce))
	var/obj/item/slimepotion/potion = bot.carried_slime_potion()
	if(potion)
		var/datum/bot_goal/xeno_extract/use_potion/G = new(potion)
		if(bot.assign_goal(G))
			return TRUE
	var/obj/item/slime_extract/E = bot.usable_extract()
	return E ? bot.assign_goal(new /datum/bot_goal/xeno_extract/activate(E)) : FALSE

// ---------------------------------------------------------------------------------------------
// The errands: a stage at a time, each look deciding the next
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/xeno_extract
	lawful = TRUE
	doing = "working with the slime extracts"

/datum/bot_goal/xeno_extract/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/staged())
	return list(S)

/datum/bot_goal/xeno_extract/on_give_up(datum/bot_brain/bot)
	bot.xeno_extract_rest_until = world.time + 3 MINUTES

/// The errand's own look: GOAL_STEP_PENDING by way of step.again(), or SUCCESS or FAIL.
/datum/bot_goal/proc/staged_work(datum/bot_brain/bot, datum/bot_step/staged/step)
	return GOAL_STEP_SUCCESS

/// A step that's a run of looks, each one the goal's staged_work(), on its own timer.
/datum/bot_step/staged
	var/stage = "start"
	var/actions = 0
	var/tries = 0

/datum/bot_step/staged/proc/again(datum/bot_brain/bot, delay = 5)
	addtimer(CALLBACK(src, PROC_REF(carry_on), bot, bot.current_goal), delay)
	return GOAL_STEP_PENDING

/datum/bot_step/staged/proc/carry_on(datum/bot_brain/bot, datum/bot_goal/goal)
	if(QDELETED(bot) || bot.state != BOT_STATE_GOAL || bot.current_goal != goal || !bot.on_this_step(src))
		return
	var/result
	try
		result = execute(bot)
	catch(var/exception/e)
		bot_log_exception(bot, "[bot.current_goal?.type] staged", e)
		result = GOAL_STEP_FAIL
	if(result != GOAL_STEP_PENDING)
		bot.advance_goal_step(result == GOAL_STEP_SUCCESS)

/datum/bot_step/staged/execute(datum/bot_brain/bot)
	if(!bot.current_goal || ++actions > 120)
		return GOAL_STEP_FAIL
	return bot.current_goal.staged_work(bot, src)

/// Walk to something, as part of a stage: PENDING while it's on its way.
/datum/bot_step/staged/proc/go_to(datum/bot_brain/bot, atom/A)
	if(++tries > 6)
		return GOAL_STEP_FAIL
	return bot.suspend_goal_for(new /datum/bot_goal/walk_up_to(A)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL

/// Fetch an item lying somewhere into its hands or bag, as part of a stage.
/datum/bot_step/staged/proc/fetch(datum/bot_brain/bot, obj/item/I)
	if(++tries > 6)
		return GOAL_STEP_FAIL
	return bot.suspend_goal_for(new /datum/bot_goal/take_item/exact(I)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// Setting one off
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/xeno_extract/activate
	doing = "using a slime extract"
	var/obj/item/slime_extract/extract
	var/reagent
	var/list/before
	/// Where it set the extract down, and what it made lands: an extract used up is deleted (slime reactions' use_slime_core())
	var/turf/drop_turf

/datum/bot_goal/xeno_extract/activate/New(obj/item/slime_extract/E)
	. = ..()
	extract = E
	target = E
	reagent = bot_extract_reagent(E)

/datum/bot_goal/xeno_extract/activate/resolve_target(datum/bot_brain/bot)
	if(QDELETED(extract) || !reagent)
		target = null

/// A beaker it's carrying with enough of the reagent in it for a dropper.
/datum/bot_brain/proc/beaker_with(reagent)
	for(var/obj/item/reagent_containers/glass/beaker/B in owner.GetAllContents(/obj/item/reagent_containers/glass/beaker))
		if(B.reagents.get_reagent_amount(reagent) >= 5)
			return B
	return null

/datum/bot_brain/proc/empty_beaker()
	for(var/obj/item/reagent_containers/glass/beaker/B in owner.GetAllContents(/obj/item/reagent_containers/glass/beaker))
		if(!B.reagents.total_volume)
			return B
	return null

/// Something in the lab nobody's carrying: a beaker, the dropper, a sheet of plasma.
/datum/bot_brain/proc/lab_item(path, empty = FALSE)
	for(var/obj/item/I as anything in bot_instances_of(path))
		if(QDELETED(I) || !isturf(I.loc) || I.z != my_z() || !in_xenobiology(I) || taken_by_another(I))
			continue
		if(empty && I.reagents?.total_volume)
			continue
		return I
	return null

/datum/bot_brain/proc/lab_machine(path)
	for(var/obj/machinery/M as anything in bot_instances_of(path))
		if(!QDELETED(M) && M.z == my_z() && in_xenobiology(M) && !(M.stat & (NOPOWER|BROKEN)))
			return M
	return null

/datum/bot_goal/xeno_extract/activate/staged_work(datum/bot_brain/bot, datum/bot_step/staged/step)
	if(QDELETED(extract) && step.stage != "collect")
		return GOAL_STEP_FAIL
	var/mob/living/carbon/human/H = bot.owner
	switch(step.stage)
		if("start")
			// The extract first: out of the fridge (its own button: smartfridge/ui_act()), or off the floor.
			if(bot.is_carried(extract))
				step.stage = "reagent"
				step.tries = 0
				return step.again(bot, 1)
			if(istype(extract.loc, /obj/machinery/smartfridge))
				var/obj/machinery/smartfridge/F = extract.loc
				if(!H.Adjacent(F))
					return step.go_to(bot, F)
				bot.human_pause(F)
				if(QDELETED(extract) || extract.loc != F)
					return GOAL_STEP_FAIL
				bot.make_hand_free()
				bot.telemetry_ui_action(F, "release [extract.name]")
				if(!H.put_in_hands(extract))
					extract.forceMove(F.drop_location())
				return step.again(bot, 5)
			return step.fetch(bot, extract)
		if("reagent")
			if(bot.beaker_with(reagent))
				step.stage = "drop"
				step.tries = 0
				return step.again(bot, 1)
			var/obj/item/reagent_containers/glass/beaker/B = bot.empty_beaker()
			if(!B)
				B = bot.lab_item(/obj/item/reagent_containers/glass/beaker, TRUE)
				return B ? step.fetch(bot, B) : GOAL_STEP_FAIL
			if(reagent == /datum/reagent/water)
				var/obj/structure/sink/S = locate() in range(30, H)
				if(!S || !bot.in_xenobiology(S))
					return GOAL_STEP_FAIL
				if(!H.Adjacent(S))
					return step.go_to(bot, S)
				bot.use_tool_on(B, S) //sink/attackby(): fills it
				return step.again(bot, 5)
			return grind_plasma(bot, step, B)
		if("drop")
			var/obj/item/reagent_containers/dropper/D = locate() in H.GetAllContents(/obj/item/reagent_containers/dropper)
			if(!D)
				D = bot.lab_item(/obj/item/reagent_containers/dropper)
				return D ? step.fetch(bot, D) : GOAL_STEP_FAIL
			if(!D.reagents.has_reagent(reagent))
				if(D.reagents.total_volume)
					D.reagents.clear_reagents() //what was in it from last time, squeezed out
				var/obj/item/reagent_containers/glass/beaker/B = bot.beaker_with(reagent)
				if(!B)
					step.stage = "reagent"
					return step.again(bot, 1)
				if(!bot.ready_in_hand(B))
					return GOAL_STEP_FAIL
				bot.use_tool_on(D, B) //an empty dropper draws (dropper/afterattack())
				return step.again(bot, 5)
			// The extract set down at its feet, and the dropper squeezed over it: what it makes lands there.
			if(bot.is_carried(extract))
				H.dropItemToGround(extract)
			drop_turf = get_turf(extract)
			before = list()
			for(var/obj/item/I in drop_turf)
				before += I
			bot.telemetry_ui_action(extract, "dropper on [extract]")
			bot.use_tool_on(D, extract)
			step.stage = "collect"
			return step.again(bot, 1 SECONDS)
		if("collect")
			var/turf/T = drop_turf || get_turf(H)
			var/list/made = list()
			for(var/obj/item/I in T)
				if(!(I in before) && I != extract)
					made += I
			if(!length(made))
				if(++step.tries > 3)
					bot_log(bot, "XENO: the extract did nothing with [reagent == /datum/reagent/water ? "water" : "plasma"] on it")
					return GOAL_STEP_FAIL
				return step.again(bot, 1 SECONDS)
			bot.extracts_used++
			bot_tally("slime extracts used")
			bot_log(bot, "XENO: the extract made [english_list(made)]")
			for(var/obj/item/I in made)
				I.bot_extract_produce = !istype(I, /obj/item/slimepotion) //the potions are for the slimes, the rest goes where it's wanted
				bot.take_in_hand_or_bag(I)
			// What's left of it: back in the fridge if it's got another go in it, otherwise it's nothing now
			if(!QDELETED(extract) && extract.Uses > 0)
				var/obj/machinery/smartfridge/extract/fridge = locate() in range(20, H)
				if(fridge)
					bot.take_in_hand_or_bag(extract)
					bot.store_extract(extract, fridge)
			return GOAL_STEP_SUCCESS
	return GOAL_STEP_FAIL

/// A beaker of plasma: a sheet of it through the lab's grinder.
/datum/bot_goal/xeno_extract/activate/proc/grind_plasma(datum/bot_brain/bot, datum/bot_step/staged/step, obj/item/reagent_containers/glass/beaker/B)
	var/obj/machinery/reagentgrinder/G = bot.lab_machine(/obj/machinery/reagentgrinder)
	if(!G)
		return GOAL_STEP_FAIL
	var/obj/item/stack/sheet/mineral/plasma/sheets = locate() in bot.owner.GetAllContents(/obj/item/stack/sheet/mineral/plasma)
	if(!sheets && !length(G.holdingitems))
		sheets = bot.lab_item(/obj/item/stack/sheet/mineral/plasma)
		if(!sheets)
			bot_log(bot, "XENO: no plasma in the lab for the extracts")
			return GOAL_STEP_FAIL
		return step.fetch(bot, sheets)
	if(!bot.owner.Adjacent(G))
		return step.go_to(bot, G)
	if(G.operating)
		return step.again(bot, 1 SECONDS)
	if(!G.beaker)
		bot.use_item_on(B, G)
		return step.again(bot, 3)
	if(!length(G.holdingitems))
		// One sheet of the stack: it gives twenty units, four goes of the dropper, and the rest stay sheets
		var/obj/item/stack/sheet/mineral/plasma/one = sheets.get_amount() > 1 ? sheets.change_stack(bot.owner, 1) : sheets //into a hand (stack/change_stack())
		if(!one)
			return GOAL_STEP_FAIL
		if(!bot.is_carried(one))
			return step.fetch(bot, one)
		bot.use_item_on(one, G)
		return step.again(bot, 3)
	bot.telemetry_ui_action(G, "grind")
	G.grind(bot.owner)
	addtimer(CALLBACK(G, TYPE_PROC_REF(/obj/machinery/reagentgrinder, replace_beaker), bot.owner), 6 SECONDS) //the beaker back out once it's done
	return step.again(bot, 7 SECONDS)

/// Into a free hand, or the bag.
/datum/bot_brain/proc/take_in_hand_or_bag(obj/item/I)
	if(QDELETED(I) || is_carried(I))
		return
	if(!owner.put_in_hands(I))
		stow_item(I)

// ---------------------------------------------------------------------------------------------
// The potions, on the slimes through the console
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/xeno_extract/use_potion
	doing = "giving a slime a potion"
	var/obj/item/slimepotion/potion
	var/mob/living/simple_animal/slime/slime
	var/obj/item/slime_extract/extract

/datum/bot_goal/xeno_extract/use_potion/New(obj/item/slimepotion/P)
	. = ..()
	potion = P

/// Which slime (or extract) it's for. A steroid: a baby, for one more extract out of it. A mutator: one that hasn't had three, the colour
/// with the most new colours still to come out of it first. An enhancer: an extract worth another use.
/datum/bot_goal/xeno_extract/use_potion/resolve_target(datum/bot_brain/bot)
	target = null
	if(QDELETED(potion))
		return
	if(istype(potion, /obj/item/slimepotion/enhancer))
		for(var/obj/item/slime_extract/E as anything in bot_instances_of(/obj/item/slime_extract))
			if(!QDELETED(E) && E.Uses > 0 && E.Uses < 5 && !E.recurring && GLOB.bot_extract_reagents[E.type] && E.z == bot.my_z() && bot.in_xenobiology(E))
				extract = E
				target = istype(E.loc, /obj/machinery/smartfridge) ? E.loc : E
				return
		return
	var/obj/machinery/computer/camera_advanced/xenobio/X = bot.find_xeno_console()
	if(!X)
		return
	var/best_score
	for(var/mob/living/simple_animal/slime/S as anything in bot.lab_slimes())
		if(S.stat || !bot_camera_sees(get_turf(S)))
			continue
		var/score
		if(istype(potion, /obj/item/slimepotion/slime/steroid))
			if(S.is_adult || S.cores >= 5)
				continue
			score = -S.cores
		else if(istype(potion, /obj/item/slimepotion/slime/mutator))
			if(S.mutator_amount >= 3)
				continue
			score = 0
			for(var/colour in list(S.slime_mutation[1], S.slime_mutation[2], S.slime_mutation[3], S.slime_mutation[4]))
				if(!GLOB.bot_slime_colours[colour])
					score++ //a colour nobody's bred yet this shift
		else
			return
		if(isnull(best_score) || score > best_score)
			best_score = score
			slime = S
	if(slime)
		target = X

/datum/bot_goal/xeno_extract/use_potion/staged_work(datum/bot_brain/bot, datum/bot_step/staged/step)
	if(QDELETED(potion))
		return GOAL_STEP_SUCCESS
	var/mob/living/carbon/human/H = bot.owner
	if(extract)
		if(QDELETED(extract))
			return GOAL_STEP_FAIL
		if(istype(extract.loc, /obj/machinery/smartfridge))
			var/obj/machinery/smartfridge/F = extract.loc
			if(!H.Adjacent(F))
				return step.go_to(bot, F)
			bot.make_hand_free()
			bot.telemetry_ui_action(F, "release [extract.name]")
			if(!H.put_in_hands(extract))
				extract.forceMove(F.drop_location())
			return step.again(bot, 5)
		if(!bot.is_carried(extract) && !H.Adjacent(extract))
			return step.fetch(bot, extract)
		var/uses = extract.Uses
		bot.use_tool_on(potion, extract) //slime_extract/attackby(): another use
		if(extract.Uses > uses)
			bot.potions_given++
			bot_log(bot, "XENO: put the enhancer on [extract]: [extract.Uses] uses now")
			var/obj/machinery/smartfridge/extract/fridge = locate() in range(20, H)
			if(fridge)
				bot.take_in_hand_or_bag(extract)
				bot.store_extract(extract, fridge)
			return GOAL_STEP_SUCCESS
		return GOAL_STEP_FAIL
	var/obj/machinery/computer/camera_advanced/xenobio/X = target
	if(QDELETED(X) || QDELETED(slime) || slime.stat)
		return GOAL_STEP_FAIL
	if(!H.Adjacent(X))
		return step.go_to(bot, X)
	if(X.current_potion != potion)
		bot.human_pause(X)
		bot.use_item_on(potion, X) //into the console's potion slot
		return step.again(bot, 3)
	bot.human_pause(X)
	if(QDELETED(slime) || QDELETED(X) || X.current_potion != potion || !bot_camera_sees(get_turf(slime)))
		return GOAL_STEP_FAIL
	bot.telemetry_ui_action(X, "potion on [slime]")
	var/name_was = "[potion]"
	X.current_potion.attack(slime, H)
	if(QDELETED(potion) || X.current_potion != potion)
		bot.potions_given++
		bot_tally("slime potions given")
		bot_log(bot, "XENO: gave [slime] the [name_was] from the console")
		if(prob(30))
			bot_say(H, pick("Fed the [slime.colour] slime a [name_was].", "That should get us something new out of the pens.", "Potion's in."))
		return GOAL_STEP_SUCCESS
	return GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// What it made, where it's wanted
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/xeno_extract/deliver
	doing = "taking what the extracts made where it's wanted"
	var/obj/item/produce

/datum/bot_goal/xeno_extract/deliver/New(obj/item/I)
	. = ..()
	produce = I

/datum/bot_goal/xeno_extract/deliver/resolve_target(datum/bot_brain/bot)
	target = null
	if(QDELETED(produce))
		return
	if(istype(produce, /obj/item/stack/sheet) || istype(produce, /obj/item/stack/ore/bluespace_crystal))
		target = bot.find_science_protolathe()
		return
	// A cell or anything else: a table in Robotics, for whoever wants it
	for(var/obj/structure/table/T as anything in bot_instances_of(/obj/structure/table))
		if(!QDELETED(T) && T.z == bot.my_z() && bot.in_robotics(T) && bot.can_walk_lawfully_to(T))
			target = T
			return

/datum/bot_brain/proc/find_science_protolathe()
	for(var/obj/machinery/rnd/production/protolathe/P as anything in bot_instances_of(/obj/machinery/rnd/production/protolathe))
		if(!QDELETED(P) && P.z == my_z() && !(P.stat & (NOPOWER|BROKEN)) && (gym_run ? get_area(P) == get_area(owner) : istype(get_area(P), /area/science)) && can_walk_lawfully_to(P))
			return P
	return null

/datum/bot_goal/xeno_extract/deliver/staged_work(datum/bot_brain/bot, datum/bot_step/staged/step)
	if(QDELETED(produce))
		return GOAL_STEP_SUCCESS
	var/mob/living/carbon/human/H = bot.owner
	if(!H.Adjacent(target))
		return step.go_to(bot, target)
	produce.bot_extract_produce = FALSE
	if(istype(target, /obj/machinery/rnd/production))
		bot.use_tool_on(produce, target) //into the ore silo by way of the lathe
		bot_log(bot, "XENO: [produce] into [target]")
	else
		if(!bot.ready_in_hand(produce))
			return GOAL_STEP_FAIL
		H.transferItemToLoc(produce, get_turf(target))
		bot_log(bot, "XENO: left [produce] on a table in Robotics")
		if(prob(50))
			bot_say(H, pick(";Slime power cell on the Robotics table if anybody wants one.", ";Left a slime cell in Robotics."))
	bot_tally("extract produce delivered")
	return GOAL_STEP_SUCCESS
