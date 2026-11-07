// The chem lab, past pills straight off the dispenser (goals/synthesize_medicine.dm).
//
//  - Brews come in stages: dispense, heat or cool, pressurise, spin, dispense some more. Each is a walk to the machine, the beaker in,
//    the machine worked the way its panel does it, the beaker out. The heater is on every map; the pressure chamber and the centrifuge
//    (lcasschem.dm) are only on the Hippie map, and without them a chemist makes what it can.
//  - A chemist also makes things for itself, and how far that goes is the chemist: everybody keeps a couple of heals, an antag hunter
//    or a paranoid one knockouts on top, and the ones that way inclined something lethal. The most serious of them go to the trouble of
//    the nerve agent. Knockouts and lethals go into syringes, and it brings a syringe gun.
//  - What's on it gets used (try_chem_weapon()): a knockout in anybody it's fighting, a lethal only where Space Law allows lethal force
//    (bot_may_use_lethal_force(), bot_law.dm), and never on somebody it's already dosed.
//  - The paranoid and the powergamers go one further: a smoke grenade full of knockout. Smoke doesn't care who it's on, so it's kept for
//    a real fight, thrown from a distance, with nobody friendly by them (try_smoke_grenade()).

#define BOT_CHEM_HEAL "heal"
#define BOT_CHEM_KNOCKOUT "knockout"
#define BOT_CHEM_LETHAL "lethal"
#define BOT_CHEM_GRENADE "grenade"
/// The longest a machine gets to do what it's asked.
#define BOT_CHEM_MACHINE_LIMIT (2 MINUTES)
/// Between one needle and the next.
#define BOT_NEEDLE_REST (6 SECONDS)

/// Amounts are for a 100u beaker and scale to whatever beaker there is. A stage is list("add", amounts), list("heat" or "cool", kelvin),
/// list("press", pressure), or list("spin"). `serious` is for the chemist who's really into it (pick_brew()).
GLOBAL_LIST_INIT(bot_brews, list(
	list("label" = "tricordrazine", "reagent" = /datum/reagent/medicine/tricordrazine, "kind" = BOT_CHEM_HEAL, "form" = "pill", "stages" = list(
		list("add", list(/datum/reagent/carbon = 20, /datum/reagent/oxygen = 10, /datum/reagent/consumable/sugar = 10, /datum/reagent/silicon = 20, /datum/reagent/nitrogen = 10, /datum/reagent/potassium = 10)),
	)),
	list("label" = "sodium fluoride", "reagent" = /datum/reagent/medicine/sodiumf, "kind" = BOT_CHEM_HEAL, "form" = "pill", "stages" = list(
		list("add", list(/datum/reagent/consumable/ethanol = 20, /datum/reagent/fluorine = 10)),
		list("heat", 320),
		list("add", list(/datum/reagent/sodium = 40)),
		list("heat", 470),
	)),
	list("label" = "aluminium fluorate", "reagent" = /datum/reagent/medicine/aluminiumf, "kind" = BOT_CHEM_HEAL, "form" = "pill", "stages" = list(
		list("add", list(/datum/reagent/consumable/ethanol = 20, /datum/reagent/fluorine = 10)),
		list("heat", 320),
		list("add", list(/datum/reagent/oxygen = 20, /datum/reagent/aluminium = 20)),
		list("cool", 230),
		list("press", 25),
	)),
	list("label" = "chloral hydrate", "reagent" = /datum/reagent/toxin/chloralhydrate, "kind" = BOT_CHEM_KNOCKOUT, "form" = "syringe", "stages" = list(
		list("add", list(/datum/reagent/consumable/ethanol = 20, /datum/reagent/chlorine = 60, /datum/reagent/water = 20)),
	)),
	list("label" = "sleep toxin", "reagent" = /datum/reagent/medicine/morphine, "kind" = BOT_CHEM_KNOCKOUT, "form" = "syringe", "stages" = list(
		list("add", list(/datum/reagent/carbon = 30, /datum/reagent/hydrogen = 30, /datum/reagent/consumable/ethanol = 15, /datum/reagent/oxygen = 15)),
		list("heat", 480),
	)),
	list("label" = "cyanide", "reagent" = /datum/reagent/toxin/cyanide, "kind" = BOT_CHEM_LETHAL, "form" = "syringe", "stages" = list(
		list("add", list(/datum/reagent/fuel = 10, /datum/reagent/carbon = 10, /datum/reagent/hydrogen = 40, /datum/reagent/nitrogen = 10, /datum/reagent/oxygen = 30)),
		list("heat", 380),
	)),
	list("label" = "sarin", "reagent" = /datum/reagent/toxin/sarin, "kind" = BOT_CHEM_LETHAL, "form" = "syringe", "serious" = TRUE, "stages" = list(
		list("add", list(/datum/reagent/water = 36, /datum/reagent/carbon = 18, /datum/reagent/aluminium = 1)),
		list("add", list(/datum/reagent/hydrogen = 15, /datum/reagent/carbon = 5, /datum/reagent/phosphorus = 5, /datum/reagent/oxygen = 5, /datum/reagent/fluorine = 10)),
		list("press", 26),
		list("heat", 700),
		list("cool", 430), //any hotter and the last step goes up in the chemist's face
		list("press", 95), //and the same at 100
		list("spin"),
	)),
	// For somebody who's asked (bot_collabs.dm): left in its beaker, on their counter.
	list("label" = "unstable mutagen", "reagent" = /datum/reagent/toxin/mutagen, "kind" = "order", "form" = "beaker", "stages" = list(
		list("add", list(/datum/reagent/uranium/radium = 20, /datum/reagent/phosphorus = 20, /datum/reagent/chlorine = 20)),
	)),
	// With the dispenser flat, what Botany sent over goes through the grinder. It comes out in the beaker.
	list("label" = "poppy bicaridine", "reagent" = /datum/reagent/medicine/bicaridine, "kind" = "poppy", "form" = "pill", "stages" = list(
		list("grind"),
	)),
	// Potassium and sugar in with the knockout, the phosphorus in a beaker of its own: they don't meet until the grenade goes off.
	list("label" = "knockout smoke", "reagent" = /datum/reagent/toxin/chloralhydrate, "kind" = BOT_CHEM_GRENADE, "form" = "grenade", "stages" = list(
		list("add", list(/datum/reagent/consumable/ethanol = 20, /datum/reagent/chlorine = 60, /datum/reagent/water = 20)),
		list("add", list(/datum/reagent/potassium = 20, /datum/reagent/consumable/sugar = 20)),
		list("second beaker", list(/datum/reagent/phosphorus = 20)),
	)),
))

/// What each kind of chemist keeps on it: BOT_CHEM_* -> how many.
GLOBAL_LIST_INIT(bot_chemist_stock, list(
	BOT_STYLE_NORMAL = list(BOT_CHEM_HEAL = 2),
	BOT_STYLE_HOPPER = list(BOT_CHEM_HEAL = 2),
	BOT_STYLE_HUNTER = list(BOT_CHEM_HEAL = 3, BOT_CHEM_KNOCKOUT = 2),
	BOT_STYLE_PARANOID = list(BOT_CHEM_HEAL = 3, BOT_CHEM_KNOCKOUT = 2, BOT_CHEM_LETHAL = 1, BOT_CHEM_GRENADE = 1),
	BOT_STYLE_POWERGAMER = list(BOT_CHEM_HEAL = 4, BOT_CHEM_KNOCKOUT = 3, BOT_CHEM_LETHAL = 2, BOT_CHEM_GRENADE = 1),
	BOT_STYLE_ROBUST = list(BOT_CHEM_HEAL = 3, BOT_CHEM_KNOCKOUT = 2),
))

/datum/bot_brain
	/// When it can next use a needle on somebody.
	var/next_needle_time = 0

/// Reagent type -> BOT_CHEM_*.
/proc/bot_chem_kind(reagent_type)
	var/static/list/kinds
	if(!kinds)
		kinds = list(
			/datum/reagent/toxin/mutagen = null,
			/datum/reagent/medicine/bicaridine = BOT_CHEM_HEAL,
			/datum/reagent/medicine/kelotane = BOT_CHEM_HEAL,
			/datum/reagent/medicine/styptic_powder = BOT_CHEM_HEAL,
			/datum/reagent/medicine/silver_sulfadiazine = BOT_CHEM_HEAL,
		)
		for(var/list/brew in GLOB.bot_brews)
			if(brew["form"] != "grenade" && brew["form"] != "beaker" && brew["kind"] != "poppy") //what's in a grenade is what's in the knockout syringes
				kinds[brew["reagent"]] = brew["kind"]
	return kinds[reagent_type]

/// What a pill, a patch or a syringe is for, going by what's mostly in it.
/proc/bot_chem_kind_of(obj/item/reagent_containers/C)
	var/datum/reagent/R = C.reagents?.get_master_reagent()
	return R ? bot_chem_kind(R.type) : null

/// How many of this kind it's got on it.
/datum/bot_brain/proc/carried_chems(kind)
	. = 0
	if(kind == BOT_CHEM_GRENADE)
		return bot_ready_grenade() ? 1 : 0
	for(var/obj/item/reagent_containers/C in owner.GetAllContents(/obj/item/reagent_containers))
		if((istype(C, /obj/item/reagent_containers/pill) || istype(C, /obj/item/reagent_containers/syringe)) && bot_chem_kind_of(C) == kind)
			.++

/// What this chemist means to keep on it, BOT_CHEM_* -> how many. Nothing, for anybody who isn't one. A mild one leaves the lethals alone.
/datum/bot_brain/proc/chem_wishlist()
	if(work_role() != "Chemist" && !(gym_run && job_is_chemist_for_gym))
		return null
	var/list/wanted = GLOB.bot_chemist_stock[hardened ? BOT_STYLE_PARANOID : playstyle]
	wanted = wanted.Copy()
	if(temper < 0.3)
		wanted -= BOT_CHEM_LETHAL
	return wanted

/datum/bot_brain
	/// Set by a Bot Gym scenario with a chemist in it that isn't called one.
	var/job_is_chemist_for_gym = FALSE

/// A machine of this type in Medbay, working.
/datum/bot_brain/proc/find_chem_machine(machine_type)
	for(var/obj/machinery/M as anything in bot_instances_of(machine_type))
		if(M.z == owner.z && !(M.stat & (NOPOWER|BROKEN)) && is_medbay_chemistry(M))
			return M
	return null

/datum/bot_brain/proc/chem_machine_for(stage)
	switch(stage)
		if("heat", "cool")
			return find_chem_machine(/obj/machinery/chem_heater)
		if("press")
			return find_chem_machine(/obj/machinery/chem/pressure)
		if("spin")
			return find_chem_machine(/obj/machinery/chem/centrifuge)
		if("grind")
			return find_chem_machine(/obj/machinery/reagentgrinder)

/// Whether every machine this brew needs is here to be had.
/datum/bot_brain/proc/can_brew(list/brew)
	if(brew["form"] == "grenade" && !grenade_case() && !find_empty_case())
		return FALSE
	for(var/list/stage in brew["stages"])
		if(stage[1] != "add" && stage[1] != "second beaker" && stage[1] != "beaker" && stage[1] != "pour" && !chem_machine_for(stage[1]))
			return FALSE
	return TRUE

/datum/bot_brain/proc/bot_ready_grenade()
	for(var/obj/item/grenade/chem_grenade/G in owner.GetAllContents(/obj/item/grenade/chem_grenade))
		if(G.stage == GRENADE_READY && !G.active && !bot_grenade_explosive(G)) //a saboteur's (goals/sabotage_grenades.dm) isn't for a fight
			return G
	return null

/// An empty grenade case on it.
/datum/bot_brain/proc/grenade_case()
	for(var/obj/item/grenade/chem_grenade/G in owner.GetAllContents(/obj/item/grenade/chem_grenade))
		if(G.stage != GRENADE_READY)
			return G
	return null

/// An empty one lying about: there's one in most chem labs. Not the janitor's cleaner grenades.
/datum/bot_brain/proc/find_empty_case()
	for(var/obj/item/grenade/chem_grenade/G as anything in bot_instances_of(/obj/item/grenade/chem_grenade))
		if(G.stage == GRENADE_EMPTY && !QDELETED(G) && isturf(G.loc) && G.z == owner.z && (gym_run ? get_area(G) == get_area(owner) : can_walk_lawfully_to(G)))
			return G
	return null

/// One brew of this kind that it's able to make, and would. The nerve agent's for somebody who's really into it.
/datum/bot_brain/proc/pick_brew(kind)
	var/list/options = list()
	for(var/list/brew in GLOB.bot_brews)
		if(brew["kind"] != kind || !can_brew(brew))
			continue
		if(brew["serious"] && playstyle != BOT_STYLE_POWERGAMER && !(is_paranoid() && competence >= 0.7))
			continue
		options += list(brew)
	return length(options) ? pick(options) : null

/// The first thing short on its own list, as a brew to make.
/datum/bot_brain/proc/brew_for_self()
	var/list/wanted = chem_wishlist()
	for(var/kind in wanted)
		if(carried_chems(kind) >= wanted[kind])
			continue
		var/list/brew = pick_brew(kind)
		if(brew)
			return brew
	return null

/// What Medbay's fridge gets next: a chemist often as not goes past the three everybody knows.
/datum/bot_brain/proc/pick_medicine_recipe()
	if(work_role() == "Chemist" && prob(50))
		var/list/brew = pick_brew(BOT_CHEM_HEAL)
		if(brew)
			return brew
	return pick(GLOB.bot_medicine_recipes)

/// Whether it hangs on to this rather than put it in the fridge.
/datum/bot_brain/proc/keeps_for_self(obj/item/reagent_containers/C)
	var/list/wanted = chem_wishlist()
	var/kind = bot_chem_kind_of(C)
	return kind && carried_chems(kind) <= wanted?[kind]

/// The beaker it's working with: the one with something in it, or failing that any it's got.
/datum/bot_brain/proc/brew_beaker()
	if(brew_beaker_override && !QDELETED(brew_beaker_override) && brew_beaker_override.loc && get_turf(brew_beaker_override) == get_turf(owner))
		return brew_beaker_override
	var/obj/item/reagent_containers/glass/beaker/spare
	for(var/obj/item/reagent_containers/glass/beaker/B in owner.GetAllContents(/obj/item/reagent_containers/glass/beaker))
		if(B.reagents.total_volume)
			return B
		spare = spare || B
	return spare

/datum/bot_brain/proc/empty_syringe()
	for(var/obj/item/reagent_containers/syringe/S in owner.GetAllContents(/obj/item/reagent_containers/syringe))
		if(!S.reagents.total_volume)
			return S
	return null

// ---------------------------------------------------------------------------------------------
// The brew
// ---------------------------------------------------------------------------------------------

/datum/bot_strategy/brew
	var/datum/bot_goal/synthesize_medicine/goal

/datum/bot_strategy/brew/New(datum/bot_goal/synthesize_medicine/G, datum/bot_brain/bot)
	. = ..()
	goal = G
	steps = list(new /datum/bot_step/ensure_beaker())
	if(G.recipe["form"] == "syringe")
		steps += new /datum/bot_step/ensure_syringes()
	if(G.recipe["form"] == "grenade")
		steps += new /datum/bot_step/ensure_grenade_parts()
	for(var/list/stage in G.recipe["stages"])
		var/datum/bot_step/move_to/to_machine = new()
		// More than one beaker on the go (goals/sabotage_grenades.dm's superboom): which one's being worked, and one poured into another
		if(stage[1] == "beaker")
			steps += new /datum/bot_step/use_beaker(stage[2])
			continue
		if(stage[1] == "pour")
			steps += new /datum/bot_step/pour_beaker(stage[2], stage[3])
			continue
		if(stage[1] == "add" || stage[1] == "second beaker")
			to_machine.step_target = G.dispenser
			if(stage[1] == "second beaker")
				steps += new /datum/bot_step/ensure_beaker()
			steps += to_machine
			steps += new /datum/bot_step/load_beaker_into_dispenser(G.dispenser, stage[1] == "second beaker")
			steps += new /datum/bot_step/dispense_ingredients(G.dispenser, stage[2])
			steps += new /datum/bot_step/retrieve_beaker_from_dispenser(G.dispenser)
			continue
		var/obj/machinery/M = bot.chem_machine_for(stage[1])
		to_machine.step_target = M
		if(stage[1] == "grind")
			steps += new /datum/bot_step/fetch_poppy()
			steps += to_machine
			steps += new /datum/bot_step/paced/grind_poppy(M)
			continue
		steps += to_machine
		steps += new /datum/bot_step/paced/run_chem_machine(M, stage[1], length(stage) > 1 ? stage[2] : 0, length(stage) > 2 && stage[3] == "exact")
	if(G.recipe["form"] == "grenade")
		steps += new /datum/bot_step/paced/assemble_grenade()
		return
	if(G.recipe["form"] == "beaker")
		return //carried straight over to whoever asked (on_success(), goals/synthesize_medicine.dm)
	var/datum/bot_step/move_to/to_master = new()
	to_master.step_target = G.master
	if(G.recipe["form"] == "syringe")
		steps += new /datum/bot_step/paced/fill_syringes()
		steps += to_master
		steps += new /datum/bot_step/load_beaker_into_master(G.master)
		steps += new /datum/bot_step/rinse_beaker(G.master)
		return
	steps += to_master
	steps += new /datum/bot_step/load_beaker_into_master(G.master)
	steps += new /datum/bot_step/produce_medicine(G.master)
	if(G.fridge && !G.for_self)
		var/datum/bot_step/move_to/to_fridge = new()
		to_fridge.step_target = G.fridge
		steps += to_fridge
		steps += new /datum/bot_step/store_products(G.fridge)

/datum/bot_strategy/brew/is_feasible(datum/bot_brain/bot)
	return goal.dispenser && !QDELETED(goal.dispenser) && goal.master && !QDELETED(goal.master)

/// One machine, one job. What it says on the panel, done with the panel's own vars (ui_act(), lcasschem.dm and chem_heater.dm).
/datum/bot_step/paced/run_chem_machine
	var/obj/machinery/machine
	var/job
	var/value = 0
	var/ends_at = 0
	/// The heater set to just what it's after, not past it: for what goes off a few degrees on (superboom at 315 K)
	var/exact = FALSE

/datum/bot_step/paced/run_chem_machine/New(obj/machinery/M, stage, amount, set_exact = FALSE)
	. = ..()
	machine = M
	job = stage
	exact = set_exact
	value = stage == "press" ? CEILING(amount, 5) : amount //the gauge goes up in fives

/datum/bot_step/paced/run_chem_machine/proc/machine_beaker()
	var/obj/machinery/chem/C = machine
	if(istype(C))
		return C.beaker
	var/obj/machinery/chem_heater/H = machine
	return H.beaker

/datum/bot_step/paced/run_chem_machine/proc/switch_machine(on)
	var/obj/machinery/chem/C = machine
	if(istype(C))
		C.on = on
		return
	var/obj/machinery/chem_heater/H = machine
	H.on = on

/datum/bot_step/paced/run_chem_machine/start(datum/bot_brain/bot)
	if(QDELETED(machine) || !bot.owner.Adjacent(machine) || (machine.stat & (NOPOWER|BROKEN)) || machine_beaker())
		return FALSE
	var/obj/item/reagent_containers/glass/beaker/B = bot.brew_beaker()
	if(!B || !bot.use_item_on(B, machine) || machine_beaker() != B)
		return FALSE
	bot.telemetry_ui_action(machine, "[job] [value]")
	bot.human_pause(machine)
	var/obj/machinery/chem_heater/H = machine
	if(istype(H))
		H.target_temperature = value + (job == "cool" ? -1 : 1) * (exact ? 1 : 30) //it only ever creeps up on what it's set to
	switch_machine(TRUE)
	ends_at = world.time + BOT_CHEM_MACHINE_LIMIT
	return TRUE

/datum/bot_step/paced/run_chem_machine/do_click(datum/bot_brain/bot)
	var/obj/item/reagent_containers/B = machine_beaker()
	if(!B || world.time > ends_at || !bot.owner.Adjacent(machine))
		return FALSE
	var/datum/reagents/R = B.reagents
	switch(job)
		if("heat")
			if(R.chem_temp >= value)
				return FALSE
		if("cool")
			if(R.chem_temp <= value)
				return FALSE
		if("spin")
			var/obj/machinery/chem/centrifuge/C = machine
			if(!C.on)
				return FALSE
		if("press")
			// Watching the gauge: it climbs in fives, and comes down again if it's turned off. What the beaker takes away is
			// what the gauge said when it came out, and some of these don't forgive a reading too high.
			if(R.chem_pressure == value)
				return FALSE
			if(R.chem_pressure > value)
				switch_machine(FALSE)
	wait_for = 1
	return TRUE

/datum/bot_step/paced/run_chem_machine/finish(datum/bot_brain/bot)
	switch_machine(FALSE)
	if(QDELETED(machine) || !machine_beaker())
		return GOAL_STEP_FAIL
	var/obj/item/reagent_containers/out = machine_beaker()
	var/list/parts = list()
	for(var/datum/reagent/R in out.reagents.reagent_list)
		parts += "[R.name] [round(R.volume, 0.1)]"
	bot_log_verbose(bot, "[job] [value] done: [round(out.reagents.chem_temp)] K, [out.reagents.chem_pressure] kPa: [jointext(parts, ", ")]")
	var/timed_out = world.time > ends_at
	var/obj/machinery/chem/C = machine
	if(istype(C))
		C.replace_beaker(bot.owner)
	else
		var/obj/machinery/chem_heater/H = machine
		H.replace_beaker(bot.owner)
	return timed_out ? GOAL_STEP_FAIL : GOAL_STEP_SUCCESS

/// A box of syringes, if it hasn't got any empty ones.
/datum/bot_step/ensure_syringes
	var/tried_fetch = FALSE

/datum/bot_step/ensure_syringes/execute(datum/bot_brain/bot)
	if(bot.empty_syringe())
		return GOAL_STEP_SUCCESS
	if(!tried_fetch)
		tried_fetch = TRUE
		var/datum/bot_goal/acquire_item_type/sub = new()
		sub.item_type = /obj/item/storage/box/syringes
		sub.lawful = TRUE
		if(bot.suspend_goal_for(sub))
			return GOAL_STEP_PENDING
	bot_log(bot, "no empty syringes to be had")
	return GOAL_STEP_FAIL

/// From the beaker to as many syringes as there's stuff for, and into the bag.
/datum/bot_step/paced/fill_syringes
	max_clicks = 6
	var/filled = 0

/datum/bot_step/paced/fill_syringes/start(datum/bot_brain/bot)
	filled = 0
	return TRUE

/datum/bot_step/paced/fill_syringes/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/synthesize_medicine/G = bot.current_goal
	var/obj/item/reagent_containers/glass/beaker/B = bot.brew_beaker()
	var/reagent_type = G.recipe["reagent"]
	var/amount = B?.reagents.get_reagent_amount(reagent_type)
	if(amount < 5)
		return FALSE
	var/obj/item/reagent_containers/syringe/S = bot.empty_syringe()
	if(!S || !bot.ready_in_hand(S))
		return FALSE
	bot.human_pause(B)
	B.reagents.trans_id_to(S, reagent_type, min(S.volume, amount))
	S.mode = S.reagents.total_volume ? 1 : 0 //that's the plunger the right way round, the same as filling one by hand
	S.update_icon()
	filled++
	bot.put_away(S)
	return TRUE

/datum/bot_step/paced/fill_syringes/finish(datum/bot_brain/bot)
	var/datum/bot_goal/synthesize_medicine/G = bot.current_goal
	bot_log(bot, "filled [filled] syringe\s with [G.recipe["label"]]")
	return filled ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// What's left down the ChemMaster's drain, so the beaker's fit to use again.
/datum/bot_step/rinse_beaker
	var/obj/machinery/chem_master/master

/datum/bot_step/rinse_beaker/New(obj/machinery/chem_master/M)
	. = ..()
	master = M

/datum/bot_step/rinse_beaker/execute(datum/bot_brain/bot)
	if(QDELETED(master) || !master.beaker)
		return GOAL_STEP_SUCCESS
	bot.empty_master_beaker(master)
	master.replace_beaker(bot.owner)
	return GOAL_STEP_SUCCESS

/// A case, a length of cable and a screwdriver, from wherever they can be had by the door.
/datum/bot_step/ensure_grenade_parts
	var/tried_case = FALSE
	var/tried_coil = FALSE
	var/tried_driver = FALSE

/datum/bot_step/ensure_grenade_parts/execute(datum/bot_brain/bot)
	if(!bot.grenade_case() && !tried_case)
		tried_case = TRUE
		var/obj/item/grenade/chem_grenade/case = bot.find_empty_case()
		if(case && bot.suspend_goal_for(new /datum/bot_goal/take_item/exact(case)))
			return GOAL_STEP_PENDING
	for(var/needed in list(/obj/item/stack/cable_coil, /obj/item/screwdriver))
		if(bot.find_carried_tool(needed))
			continue
		if(needed == /obj/item/stack/cable_coil ? tried_coil : tried_driver)
			continue
		if(needed == /obj/item/stack/cable_coil)
			tried_coil = TRUE
		else
			tried_driver = TRUE
		var/datum/bot_goal/acquire_item_type/fetch = new()
		fetch.item_type = needed
		fetch.lawful = TRUE
		if(bot.suspend_goal_for(fetch))
			return GOAL_STEP_PENDING
	if(bot.grenade_case() && bot.find_carried_tool(/obj/item/stack/cable_coil) && bot.find_carried_tool(/obj/item/screwdriver))
		return GOAL_STEP_SUCCESS
	bot_log(bot, "can't get what it takes to make a grenade")
	return GOAL_STEP_FAIL

/// Wire the case, both beakers in, and the screwdriver to lock it. Then it's just a matter of pulling the pin.
/datum/bot_step/paced/assemble_grenade
	max_clicks = 8
	var/obj/item/grenade/chem_grenade/case

/datum/bot_step/paced/assemble_grenade/start(datum/bot_brain/bot)
	case = bot.grenade_case()
	return !!case

/datum/bot_step/paced/assemble_grenade/do_click(datum/bot_brain/bot)
	if(QDELETED(case) || case.stage == GRENADE_READY)
		return FALSE
	if(case.stage == GRENADE_EMPTY)
		bot.use_item_on(bot.find_carried_tool(/obj/item/stack/cable_coil), case)
		return TRUE
	var/obj/item/reagent_containers/glass/beaker/B = bot.brew_beaker()
	if(B?.reagents.total_volume && length(case.beakers) < 2)
		bot.use_item_on(B, case)
		return TRUE
	bot.use_item_on(bot.find_carried_tool(/obj/item/screwdriver), case)
	return TRUE

/datum/bot_step/paced/assemble_grenade/finish(datum/bot_brain/bot)
	if(QDELETED(case) || case.stage != GRENADE_READY)
		return GOAL_STEP_FAIL
	var/explosive = bot_grenade_explosive(case)
	bot_log(bot, "made [explosive ? "an explosive" : "a knockout smoke"] grenade")
	bot_tally(explosive ? "explosive grenades made" : "smoke grenades made")
	bot.put_away(case)
	return GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// Using it
// ---------------------------------------------------------------------------------------------

/datum/bot_brain/proc/loaded_syringe(kind)
	for(var/obj/item/reagent_containers/syringe/S in owner.GetAllContents(/obj/item/reagent_containers/syringe))
		if(S.reagents.total_volume && bot_chem_kind_of(S) == kind)
			return S
	return null

/// The pin out and over they go, from where it won't reach this bot, with nobody on its own side near them.
/datum/bot_brain/proc/try_smoke_grenade(mob/living/foe)
	var/dist = get_dist(owner, foe)
	if(world.time < next_needle_time || dist < 3 || dist > 6 || !fight_is_serious(foe) || !has_clear_shot(foe))
		return FALSE
	var/obj/item/grenade/chem_grenade/G = bot_ready_grenade()
	if(!G)
		return FALSE
	for(var/mob/living/carbon/human/H in view(3, foe))
		if(H != foe && H != owner && bot_means_well(H))
			return FALSE
	if(!ready_in_hand(G))
		return FALSE
	next_needle_time = world.time + BOT_NEEDLE_REST
	bot_log(src, "throwing a smoke grenade at [foe]")
	bot_tally("smoke grenades thrown")
	owner.face_atom(foe)
	G.attack_self(owner)
	owner.throw_item(foe)
	return TRUE

/// In a fight: a needle up close, the syringe gun from further off. A lethal if it's that sort of bot and Space Law says so, otherwise
/// something to put them to sleep.
/datum/bot_brain/proc/try_chem_weapon(mob/living/foe)
	if(world.time < next_needle_time || !iscarbon(foe))
		return FALSE
	var/obj/item/reagent_containers/syringe/S
	if((playstyle == BOT_STYLE_HUNTER || playstyle == BOT_STYLE_POWERGAMER || is_paranoid()) && bot_may_use_lethal_force(foe))
		S = loaded_syringe(BOT_CHEM_LETHAL)
	S = S || loaded_syringe(BOT_CHEM_KNOCKOUT)
	if(!S)
		return FALSE
	var/datum/reagent/dose = S.reagents.get_master_reagent()
	if(foe.reagents?.has_reagent(dose.type))
		return FALSE //it's working on them, or it isn't going to
	if(owner.Adjacent(foe))
		next_needle_time = world.time + BOT_NEEDLE_REST
		bot_log(src, "sticking [foe] with [dose.name]")
		bot_tally("needled")
		INVOKE_ASYNC(src, PROC_REF(use_item_on), S, foe)
		return TRUE
	var/obj/item/gun/syringe/G = find_carried_tool(/obj/item/gun/syringe)
	if(!G || !has_clear_shot(foe))
		return FALSE
	if(!length(G.syringes))
		INVOKE_ASYNC(src, PROC_REF(use_item_on), S, G)
		next_needle_time = world.time + 2 SECONDS
		return TRUE
	next_needle_time = world.time + BOT_NEEDLE_REST
	bot_log(src, "shooting [foe] with [dose.name]")
	bot_tally("needled")
	return try_shoot_at(foe)

#undef BOT_CHEM_HEAL
#undef BOT_CHEM_KNOCKOUT
#undef BOT_CHEM_LETHAL
#undef BOT_CHEM_GRENADE
#undef BOT_CHEM_MACHINE_LIMIT
#undef BOT_NEEDLE_REST

// ---------------------------------------------------------------------------------------------
// More than one beaker on the go
// ---------------------------------------------------------------------------------------------

/datum/bot_brain
	/// The beaker a multi-beaker brew is working on right now (use_beaker): what brew_beaker() hands back while it's set.
	var/obj/item/reagent_containers/glass/beaker/brew_beaker_override

/datum/bot_goal/synthesize_medicine
	/// "1", "2"... -> the beaker that number is, for a brew that wants more than one
	var/list/numbered_beakers

/// Work on beaker N from here on: the one already numbered that, or an empty one it's got, or one fetched.
/datum/bot_step/use_beaker
	var/number
	var/tried_fetch = FALSE

/datum/bot_step/use_beaker/New(N)
	. = ..()
	number = "[N]"

/datum/bot_step/use_beaker/execute(datum/bot_brain/bot)
	var/datum/bot_goal/synthesize_medicine/G = bot.current_goal
	if(!istype(G))
		return GOAL_STEP_FAIL
	var/obj/item/reagent_containers/glass/beaker/B = LAZYACCESS(G.numbered_beakers, number)
	if(B && !QDELETED(B) && bot.is_carried(B))
		bot.brew_beaker_override = B
		return GOAL_STEP_SUCCESS
	var/list/taken = list()
	for(var/key in G.numbered_beakers)
		taken += G.numbered_beakers[key]
	for(var/obj/item/reagent_containers/glass/beaker/E in bot.owner.GetAllContents(/obj/item/reagent_containers/glass/beaker))
		if(!E.reagents.total_volume && !(E in taken))
			B = E
			break
	if(B)
		LAZYSET(G.numbered_beakers, number, B)
		bot.brew_beaker_override = B
		return GOAL_STEP_SUCCESS
	if(!tried_fetch)
		tried_fetch = TRUE
		var/datum/bot_goal/acquire_item_type/sub = new()
		sub.item_type = /obj/item/reagent_containers/glass/beaker
		sub.lawful = TRUE
		if(bot.suspend_goal_for(sub))
			return GOAL_STEP_PENDING
	bot_log(bot, "no beaker [number] to be had")
	return GOAL_STEP_FAIL

/// One beaker into another, all of it, and the second one's worked on from there.
/datum/bot_step/pour_beaker
	var/from_number
	var/to_number

/datum/bot_step/pour_beaker/New(from_N, to_N)
	. = ..()
	from_number = "[from_N]"
	to_number = "[to_N]"

/datum/bot_step/pour_beaker/execute(datum/bot_brain/bot)
	var/datum/bot_goal/synthesize_medicine/G = bot.current_goal
	var/obj/item/reagent_containers/glass/beaker/from = LAZYACCESS(G?.numbered_beakers, from_number)
	var/obj/item/reagent_containers/glass/beaker/into = LAZYACCESS(G?.numbered_beakers, to_number)
	if(!from || !into || QDELETED(from) || QDELETED(into))
		return GOAL_STEP_FAIL
	bot.human_pause(into)
	bot.telemetry_ui_action(into, "pour beaker [from_number] into [to_number]")
	from.reagents.trans_to(into, from.reagents.total_volume, transfered_by = bot.owner)
	bot.brew_beaker_override = into
	bot_log(bot, "poured beaker [from_number] into beaker [to_number]")
	return GOAL_STEP_SUCCESS
