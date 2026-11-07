// A plague out of Virology (goals/sabotage.dm): the user's "lethal viruses", both sides.
//
// The saboteur, a Virologist, does what a player does with what's in the lab. The virus fridge on every map holds a flu culture
// (blood with the flu in it, one symptom: a cough) and a bottle of liquid plasma, and plasma dropped into blood with a virus in it
// gives the virus a new symptom of level 4 to 6, a different one every time (mix_virus_3, chemistry/recipes/others.dm). Two of the
// twenty-four it can get kill: Necrotizing Fasciitis and Spontaneous Combustion. So: the flu into a beaker, the plasma in five units at
// a time (the least a bottle pours), and a look at it in the PanDEMIC after each, until it kills or the plasma's gone - about half the
// time it kills, and the rest it's still a plague of narcolepsy, blindness or confusion (in Bot Shifts it was more often a healing
// one: 0 of 4 killed). Hippie Station's Virology keeps two plasma sheets and a grinder: those ground give it eight more drops. Then
// the drinks left out on the bar get a
// splash each: anybody who drinks one has it (blood swallowed infects whatever the virus's spread). What's poured into a glass shows
// only to the one pouring, so nobody calls it in.
//
// The crew: a Virologist or a doctor with a health analyzer sees what somebody's got and what cures it (an advanced virus's cure is
// one of eleven plain chemicals, by how resistant it is: salt, sugar, orange juice, spaceacillin, saline-glucose, ethanol...). It
// makes a pill of it at the dispenser, or takes an antiviral syringe out of the virus fridge for spaceacillin, and doses them. Nobody
// in the bot crew did anything about a disease but say they'd noticed it.

/// Symptoms a saboteur is after: they kill.
GLOBAL_LIST_INIT(bot_lethal_symptoms, typecacheof(list(/datum/symptom/fire, /datum/symptom/flesh_eating, /datum/symptom/flesh_death, /datum/symptom/asphyxiation, /datum/symptom/alkali)))

/// The advanced virus in this container's blood, if there is one.
/proc/bot_virus_in(obj/item/reagent_containers/C)
	var/datum/reagent/blood/B = C?.reagents?.has_reagent(/datum/reagent/blood)
	if(!B || !islist(B.data) || !islist(B.data["viruses"]))
		return null
	for(var/datum/disease/advance/D in B.data["viruses"])
		return D
	return null

/proc/bot_virus_kills(datum/disease/advance/D)
	for(var/datum/symptom/S as anything in D?.symptoms)
		if(GLOB.bot_lethal_symptoms[S.type])
			return TRUE
	return FALSE

/proc/bot_virus_symptoms(datum/disease/advance/D)
	var/list/names = list()
	for(var/datum/symptom/S as anything in D?.symptoms)
		names += S.name
	return english_list(names, "none")

// ---------------------------------------------------------------------------------------------
// The saboteur
// ---------------------------------------------------------------------------------------------

/datum/bot_sabotage/virus
	id = "virus"
	name = "a plague out of Virology"

/datum/bot_sabotage/virus/weight(datum/bot_brain/bot)
	if(bot.work_role() != "Virologist" && !(bot.gym_run && bot.owner.mind?.assigned_role == "Virologist"))
		return 0
	return (bot.carried_plague() || bot.virus_fridge()) ? 10 : 0

/datum/bot_sabotage/virus/start(datum/bot_brain/bot)
	if(bot.carried_plague())
		return bot.assign_goal(new /datum/bot_goal/sabotage_spike_drinks(src))
	var/obj/machinery/smartfridge/F = bot.virus_fridge()
	return F ? bot.assign_goal(new /datum/bot_goal/sabotage_virus(F, src)) : FALSE

/// The virus fridge with what it takes in it: a flu (or cold) culture and the plasma.
/datum/bot_brain/proc/virus_fridge()
	for(var/obj/machinery/smartfridge/chemistry/virology/F as anything in bot_instances_of(/obj/machinery/smartfridge/chemistry/virology))
		if(F.z != owner.z || (F.stat & (BROKEN|NOPOWER)) || (gym_run && get_area(F) != get_area(owner)))
			continue
		if((locate(/obj/item/reagent_containers/glass/bottle/flu_virion) in F) || (locate(/obj/item/reagent_containers/glass/bottle/cold) in F))
			if(locate(/obj/item/reagent_containers/glass/bottle/plasma) in F)
				return F
	return null

/// What it brewed, ready to go: a beaker with a virus in it that's been worked on (more than the flu's cough).
/datum/bot_brain/proc/carried_plague()
	for(var/obj/item/reagent_containers/glass/beaker/B in owner.GetAllContents(/obj/item/reagent_containers/glass/beaker))
		var/datum/disease/advance/D = bot_virus_in(B)
		if(D && length(D.symptoms) > 1 && B.reagents.total_volume >= 5)
			return B
	return null

/datum/bot_goal/sabotage_virus
	doing = "working in Virology"
	breaks_in = TRUE
	var/datum/bot_sabotage/act
	var/obj/item/reagent_containers/glass/beaker/brew
	/// Back at it with ground plasma (/datum/bot_goal/sabotage_grind_plasma): the brew's started already, and there's no grinding again.
	var/resumed = FALSE

/datum/bot_goal/sabotage_virus/New(obj/machinery/smartfridge/F, datum/bot_sabotage/A, obj/item/reagent_containers/glass/beaker/resume)
	. = ..()
	target = F
	act = A
	if(resume)
		brew = resume
		resumed = TRUE

/datum/bot_goal/sabotage_virus/resolve_target(datum/bot_brain/bot)
	if(resumed)
		target = bot.nearest_pandemic() || bot.owner
	else if(QDELETED(target))
		target = bot.virus_fridge()

/datum/bot_goal/sabotage_virus/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/sabotage/S = new
	S.steps = resumed ? list() : list(new /datum/bot_step/move_to(), new /datum/bot_step/take_virus_makings(), new /datum/bot_step/get_virus_beaker())
	var/obj/machinery/computer/pandemic/P = bot.nearest_pandemic()
	if(P)
		var/datum/bot_step/move_to/to_pandemic = new
		to_pandemic.step_target = P
		S.steps += to_pandemic
	S.steps += new /datum/bot_step/paced/evolve_virus(src)
	return list(S)

/datum/bot_goal/sabotage_virus/on_success(datum/bot_brain/bot)
	var/datum/disease/advance/D = bot_virus_in(brew)
	if(!resumed && D && !bot_virus_kills(D) && bot.plasma_to_grind() && bot.virology_grinder())
		bot_log(bot, "SABOTAGE: more plasma: the sheets, ground")
		bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, assign_goal), new /datum/bot_goal/sabotage_grind_plasma(act, brew)))
		return
	bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, assign_goal), new /datum/bot_goal/sabotage_spike_drinks(act)))

/// Plasma sheets lying in the room it's in (Hippie Station's Virology keeps two on a table).
/datum/bot_brain/proc/plasma_to_grind()
	var/area/here = get_area(owner)
	for(var/obj/item/stack/sheet/mineral/plasma/P as anything in bot_instances_of(/obj/item/stack/sheet/mineral/plasma))
		if(!QDELETED(P) && isturf(P.loc) && get_area(P) == here)
			return P
	return locate(/obj/item/stack/sheet/mineral/plasma) in owner.GetAllContents()

/// A working grinder in the room, with its own empty beaker in it to grind into.
/datum/bot_brain/proc/virology_grinder()
	var/area/here = get_area(owner)
	for(var/obj/machinery/reagentgrinder/R as anything in bot_instances_of(/obj/machinery/reagentgrinder))
		if(!QDELETED(R) && get_area(R) == here && !(R.stat & (NOPOWER|BROKEN)) && R.beaker && !R.beaker.reagents.total_volume)
			return R
	return null

/datum/bot_goal/sabotage_grind_plasma
	doing = "working in Virology"
	breaks_in = TRUE
	var/datum/bot_sabotage/act
	var/obj/item/reagent_containers/glass/beaker/brew
	var/obj/machinery/reagentgrinder/grinder

/datum/bot_goal/sabotage_grind_plasma/New(datum/bot_sabotage/A, obj/item/reagent_containers/glass/beaker/B)
	. = ..()
	act = A
	brew = B

/datum/bot_goal/sabotage_grind_plasma/resolve_target(datum/bot_brain/bot)
	target = bot.plasma_to_grind()
	grinder = bot.virology_grinder()
	if(!grinder)
		target = null

/datum/bot_goal/sabotage_grind_plasma/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/sabotage/S = new
	var/datum/bot_step/move_to/to_grinder = new
	to_grinder.step_target = grinder
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/take_plasma_sheet(), to_grinder, new /datum/bot_step/grind_plasma())
	return list(S)

/datum/bot_goal/sabotage_grind_plasma/on_success(datum/bot_brain/bot)
	bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, assign_goal), new /datum/bot_goal/sabotage_virus(null, act, brew)))

/datum/bot_goal/sabotage_grind_plasma/on_give_up(datum/bot_brain/bot)
	bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, assign_goal), new /datum/bot_goal/sabotage_spike_drinks(act)))

/datum/bot_step/take_plasma_sheet/execute(datum/bot_brain/bot)
	var/obj/item/stack/sheet/mineral/plasma/P = bot.current_goal?.target
	if(!istype(P))
		return GOAL_STEP_FAIL
	if(P in bot.owner.GetAllContents())
		return GOAL_STEP_SUCCESS
	if(!bot.owner.Adjacent(P) || !bot.take_in_hand(P)) //goals/take_item.dm
		return GOAL_STEP_FAIL
	bot_log(bot, "took [P]")
	return GOAL_STEP_SUCCESS

/// The sheets into the grinder, ground into the beaker in it, and the beaker out: more plasma to drop in.
/datum/bot_step/grind_plasma/execute(datum/bot_brain/bot)
	var/datum/bot_goal/sabotage_grind_plasma/G = bot.current_goal
	var/obj/machinery/reagentgrinder/R = G?.grinder
	var/obj/item/stack/sheet/mineral/plasma/P = locate() in bot.owner.GetAllContents()
	if(!R || !P || !R.beaker || !bot.owner.Adjacent(R) || !bot.ready_in_hand(P))
		return GOAL_STEP_FAIL
	bot.human_pause(R)
	bot.owner.face_atom(R)
	bot.telemetry_ui_action(R, "put [P.name] in")
	R.attackby(P, bot.owner)
	if(!length(R.holdingitems))
		return GOAL_STEP_FAIL
	bot.human_pause(R)
	bot.telemetry_ui_action(R, "grind")
	R.grind(bot.owner)
	bot.telemetry_ui_action(R, "eject")
	var/obj/item/reagent_containers/ground = R.beaker
	R.replace_beaker(bot.owner)
	if(!ground || ground.reagents.get_reagent_amount(/datum/reagent/toxin/plasma) < 1)
		return GOAL_STEP_FAIL
	if(!(ground in bot.owner.GetAllContents()))
		bot.take_in_hand(ground)
	bot_log(bot, "SABOTAGE: ground [ground.reagents.get_reagent_amount(/datum/reagent/toxin/plasma)]u of plasma")
	return (ground in bot.owner.GetAllContents()) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/datum/bot_brain/proc/nearest_pandemic()
	var/obj/machinery/computer/pandemic/best
	for(var/obj/machinery/computer/pandemic/P as anything in bot_instances_of(/obj/machinery/computer/pandemic))
		if(P.z != owner.z || (P.stat & (BROKEN|NOPOWER)) || (gym_run && get_area(P) != get_area(owner)))
			continue
		if(!best || get_dist(owner, P) < get_dist(owner, best))
			best = P
	return best

/// At the fridge: the culture and the plasma, each with the fridge's own "release one" button (smartfridge/ui_act()).
/datum/bot_step/take_virus_makings/execute(datum/bot_brain/bot)
	var/obj/machinery/smartfridge/F = bot.current_goal?.target
	if(!istype(F) || !bot.owner.Adjacent(F))
		return GOAL_STEP_FAIL
	var/list/wanted = list()
	if(!(locate(/obj/item/reagent_containers/glass/bottle/flu_virion) in bot.owner.GetAllContents()) && !(locate(/obj/item/reagent_containers/glass/bottle/cold) in bot.owner.GetAllContents()))
		wanted += (locate(/obj/item/reagent_containers/glass/bottle/flu_virion) in F) || (locate(/obj/item/reagent_containers/glass/bottle/cold) in F)
	if(!(locate(/obj/item/reagent_containers/glass/bottle/plasma) in bot.owner.GetAllContents()))
		wanted += locate(/obj/item/reagent_containers/glass/bottle/plasma) in F
	for(var/obj/item/I in wanted)
		bot.human_pause(F)
		if(QDELETED(F) || QDELETED(I) || I.loc != F || !bot.owner.Adjacent(F))
			return GOAL_STEP_FAIL
		bot.owner.face_atom(F)
		bot.telemetry_ui_action(F, "release [I.name]")
		if(bot.owner.get_active_held_item() && bot.owner.get_inactive_held_item())
			bot.put_away(bot.owner.get_active_held_item(), allow_equip = FALSE)
		if(!bot.owner.put_in_hands(I))
			return GOAL_STEP_FAIL
		F.update_icon()
		bot.put_away(I, allow_equip = FALSE)
		bot_log(bot, "took [I] out of [F]")
	var/has_culture = (locate(/obj/item/reagent_containers/glass/bottle/flu_virion) in bot.owner.GetAllContents()) || (locate(/obj/item/reagent_containers/glass/bottle/cold) in bot.owner.GetAllContents())
	return (has_culture && (locate(/obj/item/reagent_containers/glass/bottle/plasma) in bot.owner.GetAllContents())) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

/// An empty beaker to work in: the culture bottle's too small for twenty units and the plasma on top. One it has, or one fetched.
/datum/bot_step/get_virus_beaker
	var/fetched = FALSE

/datum/bot_step/get_virus_beaker/execute(datum/bot_brain/bot)
	var/datum/bot_goal/sabotage_virus/G = bot.current_goal
	if(!istype(G))
		return GOAL_STEP_FAIL
	if(G.brew && !QDELETED(G.brew) && (G.brew in bot.owner.GetAllContents()))
		return GOAL_STEP_SUCCESS
	G.brew = bot.find_empty_beaker() //goals/synthesize_medicine.dm
	if(G.brew)
		return GOAL_STEP_SUCCESS
	if(fetched)
		return GOAL_STEP_FAIL
	fetched = TRUE
	var/datum/bot_goal/acquire_item_type/fetch = new
	fetch.item_type = /obj/item/reagent_containers/glass/beaker
	return bot.suspend_goal_for(fetch) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL

/// At the PanDEMIC: the culture into the beaker, then the plasma five units at a time, and a look at what it's become after each.
/datum/bot_step/paced/evolve_virus
	max_clicks = 30
	var/datum/bot_goal/sabotage_virus/goal
	var/waiting_since = 0
	var/poured_culture = FALSE
	var/drops = 0
	var/done = FALSE

/datum/bot_step/paced/evolve_virus/New(datum/bot_goal/sabotage_virus/G)
	. = ..()
	goal = G

/datum/bot_step/paced/evolve_virus/start(datum/bot_brain/bot)
	waiting_since = world.time
	return goal?.brew && !QDELETED(goal.brew)

/datum/bot_step/paced/evolve_virus/do_click(datum/bot_brain/bot)
	var/obj/item/reagent_containers/glass/beaker/B = goal.brew
	if(done || QDELETED(B))
		return FALSE
	if(!bot.sabotage_unwatched(waiting_since))
		wait_for = 10
		return TRUE
	var/obj/item/reagent_containers/glass/bottle/culture = (locate(/obj/item/reagent_containers/glass/bottle/flu_virion) in bot.owner.GetAllContents()) || (locate(/obj/item/reagent_containers/glass/bottle/cold) in bot.owner.GetAllContents())
	var/obj/item/reagent_containers/plasma //the bottle, or a beaker of it ground from sheets
	for(var/obj/item/reagent_containers/C in bot.owner.GetAllContents(/obj/item/reagent_containers))
		if(C != B && C.reagents?.get_reagent_amount(/datum/reagent/toxin/plasma) >= 1)
			plasma = C
			break
	if(!poured_culture && bot_virus_in(B))
		poured_culture = TRUE //back with more plasma (/datum/bot_goal/sabotage_grind_plasma)
	if(!poured_culture)
		if(!culture || !culture.reagents.total_volume)
			return FALSE
		bot.human_pause(B)
		bot.telemetry_ui_action(B, "pour [culture.name] into [B.name]")
		culture.reagents.trans_to(B, culture.reagents.total_volume, transfered_by = bot.owner)
		poured_culture = TRUE
		bot_log(bot, "SABOTAGE: the [culture.name] into [B]")
		wait_for = 10
		return TRUE
	var/datum/disease/advance/D = bot_virus_in(B)
	if(!D)
		return FALSE
	if(bot_virus_kills(D))
		done = TRUE
		bot_log(bot, "SABOTAGE: it kills now: [bot_virus_symptoms(D)]")
		return FALSE
	if(!plasma || plasma.reagents.get_reagent_amount(/datum/reagent/toxin/plasma) < 1 || B.reagents.total_volume >= B.volume)
		done = TRUE
		bot_log(bot, "SABOTAGE: out of plasma, and it doesn't kill: [bot_virus_symptoms(D)]")
		return FALSE
	bot.human_pause(B)
	bot.telemetry_ui_action(B, "drop 5u plasma into [B.name]")
	plasma.reagents.trans_to(B, 5, transfered_by = bot.owner)
	drops++
	// A look at it in the PanDEMIC, as a player puts the beaker in and reads the symptoms off its screen.
	var/obj/machinery/computer/pandemic/P = bot.nearest_pandemic()
	if(P && bot.owner.Adjacent(P))
		bot.owner.face_atom(P)
		bot.telemetry_ui_action(P, "read the symptoms")
	bot_log(bot, "SABOTAGE: plasma drop [drops]: [bot_virus_symptoms(bot_virus_in(B))]")
	wait_for = 20
	return TRUE

/datum/bot_step/paced/evolve_virus/finish(datum/bot_brain/bot)
	var/datum/disease/advance/D = bot_virus_in(goal.brew)
	if(!D || length(D.symptoms) <= 1)
		return GOAL_STEP_FAIL
	log_game("BOT SABOTAGE: [key_name(bot.owner)] brewed [D.name] ([bot_virus_symptoms(D)][bot_virus_kills(D) ? ", lethal" : ""]) at [AREACOORD(bot.owner)]")
	return GOAL_STEP_SUCCESS

/// The drinks left out on the bar, a splash in each: it goes from one to the next while there's any of it left and drinks to spike.
/datum/bot_goal/sabotage_spike_drinks
	doing = "having a drink"
	breaks_in = TRUE
	var/datum/bot_sabotage/act
	var/spiked = 0
	var/list/done_glasses

/datum/bot_goal/sabotage_spike_drinks/New(datum/bot_sabotage/A, spiked_so_far = 0, list/glasses)
	. = ..()
	act = A
	spiked = spiked_so_far
	done_glasses = glasses || list()

/datum/bot_goal/sabotage_spike_drinks/resolve_target(datum/bot_brain/bot)
	target = null
	if(!bot.carried_plague())
		return
	var/best_dist
	for(var/obj/item/reagent_containers/food/drinks/drinkingglass/G as anything in bot_instances_of(/obj/item/reagent_containers/food/drinks/drinkingglass))
		if((G in done_glasses) || !isturf(G.loc) || !bot.in_bar(G) || !G.reagents.total_volume || G.reagents.total_volume > G.volume - 5)
			continue
		var/dist = get_dist(bot.owner, G)
		if(!target || dist < best_dist)
			target = G
			best_dist = dist

/datum/bot_goal/sabotage_spike_drinks/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/sabotage/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/spike_drink(src))
	return list(S)

/datum/bot_goal/sabotage_spike_drinks/on_success(datum/bot_brain/bot)
	spiked++
	done_glasses += target
	if(spiked < 5 && bot.carried_plague())
		var/datum/bot_goal/sabotage_spike_drinks/next = new(act, spiked, done_glasses)
		next.resolve_target(bot)
		if(next.target)
			bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, assign_goal), next))
			return
	bot.sabotage_finished(act, "the Bar ([spiked] drinks)")
	bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, assign_goal), new /datum/bot_goal/lay_low()))

/datum/bot_step/paced/spike_drink
	max_clicks = 10
	var/datum/bot_goal/sabotage_spike_drinks/goal
	var/waiting_since = 0
	var/poured = FALSE

/datum/bot_step/paced/spike_drink/New(datum/bot_goal/sabotage_spike_drinks/G)
	. = ..()
	goal = G

/datum/bot_step/paced/spike_drink/start(datum/bot_brain/bot)
	waiting_since = world.time
	return TRUE

/datum/bot_step/paced/spike_drink/do_click(datum/bot_brain/bot)
	var/obj/item/reagent_containers/food/drinks/drinkingglass/G = goal.target
	var/obj/item/reagent_containers/glass/beaker/B = bot.carried_plague()
	if(poured || QDELETED(G) || !B || !isturf(G.loc) || !bot.owner.Adjacent(G)) //on the bar still: one was "spiked" in a customer's hand
		return FALSE
	if(!bot.sabotage_unwatched(waiting_since))
		wait_for = 10
		return TRUE
	bot.human_pause(G)
	bot.owner.face_atom(G)
	bot.telemetry_ui_action(G, "pour 5u of [B.name] into [G.name]")
	B.reagents.trans_to(G, 5, transfered_by = bot.owner)
	poured = TRUE
	bot_log(bot, "SABOTAGE: spiked [G]")
	log_game("BOT SABOTAGE: [key_name(bot.owner)] spiked [G] with a virus at [AREACOORD(bot.owner)]")
	// Not called in as sabotage by whoever's about: what's poured into a glass shows only to the one pouring it, and a Box bystander
	// had a virologist up for Sabotage for standing by the drinks, and it gave up the act for a rampage.
	return FALSE

/datum/bot_step/paced/spike_drink/finish(datum/bot_brain/bot)
	return poured ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// The crew
// ---------------------------------------------------------------------------------------------

/// Cures a bot can get hold of: the dispenser's, as a pill (goals/synthesize_medicine.dm's brews), and spaceacillin, which the virus
/// fridge keeps in syringes. Orange juice, leporazine, lipolicide and gold aren't to be had there: whoever's got one of those, has it.
GLOBAL_LIST_INIT(bot_cure_brews, list(
	/datum/reagent/consumable/sodiumchloride = list("label" = "salt", "reagent" = /datum/reagent/consumable/sodiumchloride, "kind" = "cure", "form" = "pill", "stages" = list(
		list("add", list(/datum/reagent/water = 10, /datum/reagent/sodium = 10, /datum/reagent/chlorine = 10)))),
	/datum/reagent/consumable/sugar = list("label" = "sugar", "reagent" = /datum/reagent/consumable/sugar, "kind" = "cure", "form" = "pill", "stages" = list(
		list("add", list(/datum/reagent/consumable/sugar = 30)))),
	/datum/reagent/medicine/salglu_solution = list("label" = "saline-glucose", "reagent" = /datum/reagent/medicine/salglu_solution, "kind" = "cure", "form" = "pill", "stages" = list(
		list("add", list(/datum/reagent/water = 10, /datum/reagent/sodium = 10, /datum/reagent/chlorine = 10)),
		list("add", list(/datum/reagent/water = 30, /datum/reagent/consumable/sugar = 30)))),
	/datum/reagent/consumable/ethanol = list("label" = "ethanol", "reagent" = /datum/reagent/consumable/ethanol, "kind" = "cure", "form" = "pill", "stages" = list(
		list("add", list(/datum/reagent/consumable/ethanol = 30)))),
	/datum/reagent/medicine/synaptizine = list("label" = "synaptizine", "reagent" = /datum/reagent/medicine/synaptizine, "kind" = "cure", "form" = "pill", "stages" = list(
		list("add", list(/datum/reagent/consumable/sugar = 10, /datum/reagent/lithium = 10, /datum/reagent/water = 10)))),
	/datum/reagent/silver = list("label" = "silver", "reagent" = /datum/reagent/silver, "kind" = "cure", "form" = "pill", "stages" = list(
		list("add", list(/datum/reagent/silver = 30)))),
))

/// Who's been seen sick (weakref -> when), by a medic with an analyzer: the medics go round them.
GLOBAL_LIST_EMPTY(bot_sick_known)

/datum/bot_brain
	/// The cure it's making, for synthesize_medicine (brew_for_cure()).
	var/wanted_cure
	/// Patients it got nowhere with (weakref -> until when).
	var/list/uncurable_patients

/// What somebody's got that a health analyzer would show, and a cure it names: one cure, which is what an advanced virus has.
/proc/bot_curable_disease(mob/living/carbon/human/H)
	for(var/datum/disease/D as anything in H.diseases)
		if((D.visibility_flags & HIDDEN_SCANNER) || length(D.cures) != 1 || !(D.disease_flags & CURABLE))
			continue
		return D
	return null

/// Somebody sick this medic knows of: in sight now (and so known to all of them from here on), or seen before and still sick.
/datum/bot_brain/proc/find_sick_patient()
	for(var/mob/living/carbon/human/H in view(BOT_SIGHT_RANGE, owner)) //itself as well: a virologist knows what it's caught
		if(H.stat != DEAD && bot_curable_disease(H))
			GLOB.bot_sick_known[WEAKREF(H)] = world.time
	var/mob/living/carbon/human/best
	for(var/datum/weakref/ref as anything in GLOB.bot_sick_known)
		var/mob/living/carbon/human/H = ref.resolve()
		if(!H || H.stat == DEAD || !bot_curable_disease(H))
			GLOB.bot_sick_known -= ref
			continue
		if(H.z != owner.z || LAZYACCESS(uncurable_patients, ref) > world.time || (gym_run && get_area(H) != get_area(owner)))
			continue
		var/datum/disease/D = bot_curable_disease(H)
		if(H.reagents?.has_reagent(D.cures[1]))
			continue //dosed already: it takes a little while
		if(!best || get_dist(owner, H) < get_dist(owner, best))
			best = H
	return best

/// A dose of this it has on it: a pill or a syringe with it in.
/datum/bot_brain/proc/find_cure_dose(cure)
	for(var/obj/item/reagent_containers/C in owner.GetAllContents(/obj/item/reagent_containers))
		if((istype(C, /obj/item/reagent_containers/pill) || istype(C, /obj/item/reagent_containers/syringe)) && C.reagents?.get_reagent_amount(cure) >= 5)
			return C
	return null

/// For synthesize_medicine: the cure it's set on, while it hasn't one.
/datum/bot_brain/proc/brew_for_cure()
	if(!wanted_cure || find_cure_dose(wanted_cure))
		return null
	return GLOB.bot_cure_brews[wanted_cure]

/// Seen sick, and what cures it: a dose given, or one made or fetched first.
/datum/bot_duty/cure_the_sick
	name = "curing the sick"
	tier = BOT_DUTY_URGENT
	jobs = list("Virologist", "Medical Doctor", "Chief Medical Officer")
	priority = 25
	interval_min = 30
	interval_max = 60

/datum/bot_duty/cure_the_sick/try_start(datum/bot_brain/bot)
	if(bot.saboteur)
		return FALSE
	var/mob/living/carbon/human/patient = bot.find_sick_patient()
	if(!patient)
		return FALSE
	var/datum/disease/D = bot_curable_disease(patient)
	var/cure = D.cures[1]
	if(bot.find_cure_dose(cure))
		return bot.assign_goal(new /datum/bot_goal/cure_patient(patient, cure))
	if(cure == /datum/reagent/medicine/spaceacillin)
		var/obj/machinery/smartfridge/F = bot.antiviral_fridge()
		if(F)
			bot_log(bot, "[patient] has [D.name]: spaceacillin cures it, there's some in [F]")
			return bot.assign_goal(new /datum/bot_goal/fetch_antiviral(F))
	if(GLOB.bot_cure_brews[cure])
		bot.wanted_cure = cure
		var/datum/bot_goal/synthesize_medicine/brew = new
		if(bot.assign_goal(brew))
			bot_log(bot, "[patient] has [D.name]: making some [GLOB.bot_cure_brews[cure]["label"]] for it")
			return TRUE
		// The dispenser's somebody else's just now (one at a time), or out of reach: again in a couple of minutes. Three medics on
		// Meta wrote a necrotizing fasciitis patient off for ten minutes each, the moment the Chemist had the dispenser.
		bot_log(bot, "[patient] has [D.name]: [GLOB.bot_cure_brews[cure]["label"]] cures it, and the dispenser's not to be had just now")
		LAZYSET(bot.uncurable_patients, WEAKREF(patient), world.time + 2 MINUTES)
		return FALSE
	var/datum/reagent/R = cure
	bot_log(bot, "[patient] has [D.name], and there's no [initial(R.name)] to be had for it")
	LAZYSET(bot.uncurable_patients, WEAKREF(patient), world.time + 10 MINUTES)
	return FALSE

/datum/bot_brain/proc/antiviral_fridge()
	for(var/obj/machinery/smartfridge/F as anything in bot_instances_of(/obj/machinery/smartfridge))
		if(F.z == owner.z && !(F.stat & (BROKEN|NOPOWER)) && (locate(/obj/item/reagent_containers/syringe/antiviral) in F) && (!gym_run || get_area(F) == get_area(owner)) && can_walk_lawfully_to(F))
			return F
	return null

/datum/bot_goal/fetch_antiviral
	lawful = TRUE
	doing = "fetching spaceacillin"

/datum/bot_goal/fetch_antiviral/New(obj/machinery/smartfridge/F)
	. = ..()
	target = F

/datum/bot_goal/fetch_antiviral/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new //bot_law.dm: feasible while there's a target
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/take_antiviral())
	return list(S)

/datum/bot_goal/fetch_antiviral/on_success(datum/bot_brain/bot)
	bot.continue_goal_chain(CALLBACK(bot_duty_of(/datum/bot_duty/cure_the_sick), TYPE_PROC_REF(/datum/bot_duty, try_start), bot))

/datum/bot_step/take_antiviral/execute(datum/bot_brain/bot)
	var/obj/machinery/smartfridge/F = bot.current_goal?.target
	var/obj/item/reagent_containers/syringe/antiviral/S = istype(F) ? (locate() in F) : null
	if(!S || !bot.owner.Adjacent(F))
		return GOAL_STEP_FAIL
	bot.human_pause(F)
	if(QDELETED(S) || S.loc != F)
		return GOAL_STEP_FAIL
	bot.telemetry_ui_action(F, "release [S.name]")
	if(bot.owner.get_active_held_item() && bot.owner.get_inactive_held_item())
		bot.put_away(bot.owner.get_active_held_item(), allow_equip = FALSE)
	if(!bot.owner.put_in_hands(S))
		return GOAL_STEP_FAIL
	F.update_icon()
	bot.put_away(S, allow_equip = FALSE)
	bot_log(bot, "took [S] out of [F]")
	return GOAL_STEP_SUCCESS

/datum/bot_goal/cure_patient
	lawful = TRUE
	doing = "seeing to a patient"
	var/cure

/datum/bot_goal/cure_patient/New(mob/living/carbon/human/patient, cure_type)
	. = ..()
	target = patient
	cure = cure_type

/datum/bot_goal/cure_patient/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target) || target:stat == DEAD)
		target = null
		return
	var/mob/living/carbon/human/H = target
	H.bot_brain?.wait_for_doctor(bot)

/datum/bot_goal/cure_patient/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new //bot_law.dm: feasible while there's a target
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/give_cure())
	return list(S)

/datum/bot_goal/cure_patient/on_give_up(datum/bot_brain/bot)
	if(target)
		LAZYSET(bot.uncurable_patients, WEAKREF(target), world.time + 3 MINUTES)

/// Beside them: the pill swallowed, or the syringe in, the way treat_patient gives a pill. It follows them a little if they walk on.
/datum/bot_step/give_cure
	var/chases = 0

/datum/bot_step/give_cure/execute(datum/bot_brain/bot)
	var/datum/bot_goal/cure_patient/G = bot.current_goal
	var/mob/living/carbon/human/patient = G?.target
	if(!istype(patient) || QDELETED(patient) || !bot_curable_disease(patient))
		return GOAL_STEP_SUCCESS
	if(patient.reagents?.has_reagent(G.cure))
		return GOAL_STEP_SUCCESS
	if(!bot.owner.Adjacent(patient))
		if(chases++ >= 3 || get_dist(bot.owner, patient) > 12)
			return GOAL_STEP_FAIL
		if(chases == 1 && !bot.gym_scripted)
			bot_say(bot.owner, pick("[patient.first_name()], hold still, I've got something for what you've got.", "Wait up, [patient.first_name()] - medicine."))
		patient.bot_brain?.hold_still_for(12 SECONDS)
		bot.current_step_index = 1
		return GOAL_STEP_PENDING
	var/obj/item/reagent_containers/dose = bot.find_cure_dose(G.cure)
	if(!dose)
		return GOAL_STEP_FAIL
	if(istype(dose, /obj/item/reagent_containers/syringe))
		var/obj/item/reagent_containers/syringe/S = dose
		S.mode = SYRINGE_INJECT
	bot.owner.changeNext_move(CLICK_CD_MELEE)
	bot_log(bot, "giving [patient] [dose] for their [bot_curable_disease(patient)]")
	bot.use_item_on(dose, patient)
	if(patient.reagents?.has_reagent(G.cure))
		bot_tally("sick dosed")
		if(!bot.gym_scripted && prob(60))
			bot_say(bot.owner, pick("That should clear it up.", "Give it a minute, you'll feel better.", "Stay away from the bar for a bit."))
		return GOAL_STEP_SUCCESS
	return GOAL_STEP_FAIL
