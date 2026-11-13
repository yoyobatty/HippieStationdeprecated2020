// The rest of the tech tree (the user's ask, 2026-11-12: "full science"; goals/science.dm spends the points, goals/rnd_bench.dm prints
// and fits the parts):
//
//  - Analysis: the destructive analyzer takes apart what's worth learning from. Something of a type a node lists (boost_item_paths)
//    that isn't researched yet takes points off it, and the hidden nodes, the alien and the Syndicate ones, only show at all once
//    something of theirs has been through it. Anything else worth points (techweb_item_point_check()) is, the first time a type
//    goes in. The department's own kit stays out of it.
//    Its "are you sure" (destructive_analyzer/user_try_decon_id()'s tgui_input_list()) is a window a bot can't answer: what its
//    Proceed does is done here instead, the same two calls.
//  - Hand-outs: what the tree unlocks for other departments gets printed at Science's protolathe and left on a table of theirs, once a
//    shift each, with a word on the radio: the jaws of life, the hand drill and the experimental welder for Engineering, the advanced
//    health analyzer, the compact defibrillator and a health HUD for Medbay, the diamond drill and the plasma cutter for Mining.

/// Design id -> the area (and its subtypes) it goes to.
GLOBAL_LIST_INIT(bot_science_handouts, list(
	"jawsoflife" = /area/engine,
	"handdrill" = /area/engine,
	"exwelder" = /area/engine,
	"healthanalyzer_advanced" = /area/medical,
	"defibrillator_compact" = /area/medical,
	"health_hud" = /area/medical,
	"drill_diamond" = /area/quartermaster/miningdock,
	"plasmacutter" = /area/quartermaster/miningdock,
))
/// Design ids handed out this shift.
GLOBAL_LIST_EMPTY(bot_science_handouts_given)

/// Kit the department works with, never analysed: tools, parts, containers, cards, clothes, the slime lab's, the mech bay's, the
/// circuit lab's, signallers (anomalies), what explorers bring that's for somebody else (boards, disks).
GLOBAL_LIST_INIT(bot_analysis_keep, typecacheof(list(/obj/item/stock_parts, /obj/item/reagent_containers, /obj/item/storage, /obj/item/card,
	/obj/item/pda, /obj/item/clothing, /obj/item/slime_extract, /obj/item/slimepotion, /obj/item/stack, /obj/item/paper, /obj/item/pen,
	/obj/item/folder, /obj/item/circuitboard, /obj/item/disk, /obj/item/assembly, /obj/item/mecha_parts, /obj/item/bodypart, /obj/item/organ,
	/obj/item/mmi, /obj/item/tank, /obj/item/radio, /obj/item/integrated_circuit, /obj/item/electronic_assembly, /obj/item/relic,
	/obj/item/storage, /obj/item/flashlight, /obj/item/multitool, /obj/item/t_scanner, /obj/item/analyzer, /obj/item/healthanalyzer,
	/obj/item/experi_scanner, /obj/item/slime_scanner, /obj/item/nanite_remote, /obj/item/nanite_scanner, /obj/item/disk/nanite_program)))

/obj/item/var/bot_handout_for

/datum/bot_brain
	var/items_analysed = 0
	var/handouts_given = 0
	var/rnd_analysis_rest_until = 0

/// What analysing this would get the station, or null: a node id, or RESEARCH_MATERIAL_RECLAMATION_ID for its points.
/proc/bot_research_worth(obj/item/I, datum/techweb/web)
	if(!istype(I) || !web || I.tool_behaviour || is_type_in_typecache(I, GLOB.bot_analysis_keep) || I.bot_handout_for)
		return null
	var/list/boosts = techweb_item_boost_check(I) //node id -> list(point type = points), whatever its comment says
	for(var/id in boosts)
		var/datum/techweb_node/N = SSresearch.techweb_node_by_id(id)
		if(!N || web.researched_nodes[id])
			continue
		if(web.hidden_nodes[id])
			return id //shows the node at all
		var/list/already = web.boosted_nodes[id]
		var/list/worths = boosts[id]
		for(var/kind in worths)
			if(min(worths[kind], N.research_costs[kind]) - (already ? already[kind] : 0) > 0)
				return N.id
	var/list/points = techweb_item_point_check(I)
	if(length(points) && !web.deconstructed_items[I.type])
		return RESEARCH_MATERIAL_RECLAMATION_ID
	return null

/// The destructive analyzer in Science with a console to it.
/datum/bot_brain/proc/find_research_analyzer()
	for(var/obj/machinery/rnd/destructive_analyzer/D as anything in bot_instances_of(/obj/machinery/rnd/destructive_analyzer))
		if(QDELETED(D) || D.z != my_z() || (D.stat & (NOPOWER|BROKEN)) || D.panel_open || !D.linked_console || D.busy)
			continue
		if(gym_run ? get_area(D) != get_area(owner) : !istype(get_area(D), /area/science))
			continue
		return D
	return null

/// Science's own rooms and the RD's office, where loot gets left (goals/exploring.dm) and what's lying about is the department's to use.
/datum/bot_brain/proc/in_science_rooms(atom/A)
	var/area/where = get_area(A)
	return gym_run ? where == get_area(owner) : (istype(where, /area/science) || istype(where, /area/crew_quarters/heads/hor))

/// Something lying in Science that's worth analysing, nearest first.
/datum/bot_brain/proc/thing_to_analyse(datum/techweb/web)
	var/list/seen = list()
	for(var/area/A in gym_run ? list(get_area(owner)) : GLOB.sortedAreas)
		if(!gym_run && !(istype(A, /area/science) || istype(A, /area/crew_quarters/heads/hor)))
			continue
		for(var/obj/item/I in A)
			if(!isturf(I.loc) || I.z != my_z() || I.anchored || seen[I.type] || taken_by_another(I))
				continue
			seen[I.type] = TRUE
			if(bot_research_worth(I, web))
				return I
	return null

/datum/bot_duty/rnd_analysis
	name = "analysing for research"
	jobs = list("Scientist", "Research Director")
	priority = 4
	interval_min = 400
	interval_max = 900

/datum/bot_duty/rnd_analysis/try_start(datum/bot_brain/bot)
	if(world.time < bot.rnd_analysis_rest_until)
		return FALSE
	// A hand-out it's carrying, or one it printed waiting on the lathe
	for(var/obj/item/I in bot.owner.GetAllContents())
		if(I.bot_handout_for)
			return bot.assign_goal(new /datum/bot_goal/science_handout(I))
	for(var/obj/machinery/rnd/production/protolathe/P as anything in bot_instances_of(/obj/machinery/rnd/production/protolathe))
		if(P.z != bot.my_z())
			continue
		for(var/obj/item/I in get_turf(P))
			if(I.bot_handout_for && !bot.taken_by_another(I))
				return bot.assign_goal(new /datum/bot_goal/take_item/exact(I))
	var/obj/machinery/rnd/destructive_analyzer/D = bot.find_research_analyzer()
	if(D)
		var/obj/item/I = bot.thing_to_analyse(D.linked_console.stored_research)
		if(I)
			return bot.assign_goal(new /datum/bot_goal/analyse_for_research(D, I))
	return bot.start_science_handout()

/// The next hand-out due: researched, not handed out this shift, and the lathe can make it.
/datum/bot_brain/proc/start_science_handout()
	var/obj/machinery/rnd/production/protolathe/P = find_science_protolathe() //goals/xeno_extracts.dm
	if(!P)
		return FALSE
	for(var/id in GLOB.bot_science_handouts)
		if(GLOB.bot_science_handouts_given[id] || !P.stored_research?.researched_designs[id])
			continue
		var/datum/design/D = SSresearch.techweb_design_by_id(id)
		if(!D || !P.check_mat(D, 1))
			continue
		GLOB.bot_science_handouts_given[id] = TRUE
		var/datum/bot_goal/print_design/handout/G = new(P, D, 1)
		G.area_type = GLOB.bot_science_handouts[id]
		return assign_goal(G)
	return FALSE

/datum/bot_goal/print_design/handout
	doing = "printing something for another department"
	chain_duty = null
	var/area_type

/// What it printed, marked for where it's going: the duty's next look picks it up off the lathe.
/datum/bot_goal/print_design/handout/on_success(datum/bot_brain/bot)
	var/obj/machinery/rnd/production/L = target
	for(var/obj/item/I in get_turf(L))
		if(istype(I, design.build_path) && !I.bot_handout_for)
			I.bot_handout_for = area_type
			bot_log(bot, "SCIENCE: printed [I] for [area_type]")
			bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, take_print), I)) //goals/powergame.dm
			return

/datum/bot_goal/print_design/handout/on_give_up(datum/bot_brain/bot)
	GLOB.bot_science_handouts_given[design?.id] = FALSE

// ---------------------------------------------------------------------------------------------
// Analysing
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/analyse_for_research
	lawful = TRUE
	doing = "analysing something for research"
	var/obj/machinery/rnd/destructive_analyzer/analyzer
	var/obj/item/thing

/datum/bot_goal/analyse_for_research/New(obj/machinery/rnd/destructive_analyzer/D, obj/item/I)
	. = ..()
	analyzer = D
	thing = I
	target = I

/datum/bot_goal/analyse_for_research/resolve_target(datum/bot_brain/bot)
	if(QDELETED(analyzer) || QDELETED(thing))
		target = null

/datum/bot_goal/analyse_for_research/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/staged())
	return list(S)

/datum/bot_goal/analyse_for_research/on_give_up(datum/bot_brain/bot)
	bot.rnd_analysis_rest_until = world.time + 3 MINUTES

/datum/bot_goal/analyse_for_research/staged_work(datum/bot_brain/bot, datum/bot_step/staged/step)
	if(QDELETED(analyzer) || !analyzer.linked_console)
		return GOAL_STEP_FAIL
	var/mob/living/carbon/human/H = bot.owner
	var/datum/techweb/web = analyzer.linked_console.stored_research
	if(analyzer.loaded_item != thing)
		if(QDELETED(thing))
			return GOAL_STEP_FAIL
		if(!bot.is_carried(thing))
			return step.fetch(bot, thing)
		if(!H.Adjacent(analyzer))
			return step.go_to(bot, analyzer)
		if(analyzer.loaded_item || analyzer.busy)
			return step.again(bot, 2 SECONDS)
		if(!bot.ready_in_hand(thing))
			return GOAL_STEP_FAIL
		bot.use_item_on(thing, analyzer) //rnd/destructive_analyzer/Insert_Item()
		return step.again(bot, 2 SECONDS) //the loading animation
	if(analyzer.busy)
		return step.again(bot, 1 SECONDS)
	var/id = bot_research_worth(thing, web)
	if(!id)
		analyzer.unload_item()
		return GOAL_STEP_FAIL
	bot.human_pause(analyzer.linked_console)
	if(QDELETED(thing) || analyzer.loaded_item != thing)
		return GOAL_STEP_FAIL
	var/path = thing.type
	var/name_was = "[thing]"
	bot.telemetry_ui_action(analyzer.linked_console, "deconstruct [name_was]")
	// What the analyzer's Proceed does (user_try_decon_id()), the "are you sure" being a window no bot can answer
	if(id == RESEARCH_MATERIAL_RECLAMATION_ID)
		var/list/points = techweb_item_point_check(thing)
		if(!analyzer.destroy_item(thing))
			return GOAL_STEP_FAIL
		web.add_point_list(points)
		web.deconstructed_items[path] = points
		bot_log(bot, "SCIENCE: analysed [name_was] for [json_encode(points)] points")
	else
		var/datum/techweb_node/N = SSresearch.techweb_node_by_id(id)
		var/was_hidden = !!web.hidden_nodes[id]
		if(!analyzer.destroy_item(thing))
			return GOAL_STEP_FAIL
		web.boost_with_path(N, path)
		bot_log(bot, "SCIENCE: analysed [name_was]: [was_hidden ? "[N.display_name] is on the tree now" : "[N.display_name] costs less"]")
		if(was_hidden && !bot.gym_scripted)
			bot_say(H, pick(";Took [name_was] apart in the analyzer. [N.display_name]'s on the tech tree now.", ";Analyzer just opened up [N.display_name] from [name_was]."))
	bot.items_analysed++
	bot_tally("items analysed for research")
	return GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// Handing out
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/science_handout
	lawful = TRUE
	doing = "taking something Science made to the department it's for"
	var/obj/item/handout
	var/obj/structure/table/table

/datum/bot_goal/science_handout/New(obj/item/I)
	. = ..()
	handout = I

/// A table in the department, the nearest one its own doors get it to.
/datum/bot_goal/science_handout/resolve_target(datum/bot_brain/bot)
	target = null
	if(QDELETED(handout) || !handout.bot_handout_for)
		return
	var/best_dist
	for(var/obj/structure/table/T as anything in bot_instances_of(/obj/structure/table))
		if(QDELETED(T) || T.z != bot.my_z() || !istype(get_area(T), handout.bot_handout_for))
			continue
		var/dist = get_dist(bot.owner, T)
		if((!table || dist < best_dist) && bot.can_walk_lawfully_to(T))
			table = T
			best_dist = dist
	target = table

/datum/bot_goal/science_handout/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/case_work/S = new
	S.steps = list(new /datum/bot_step/staged())
	return list(S)

/datum/bot_goal/science_handout/on_give_up(datum/bot_brain/bot)
	if(!QDELETED(handout))
		handout.bot_handout_for = null //it's the bot's now, for whatever: nowhere it could get it to

/datum/bot_goal/science_handout/staged_work(datum/bot_brain/bot, datum/bot_step/staged/step)
	if(QDELETED(handout) || QDELETED(table))
		return GOAL_STEP_FAIL
	var/mob/living/carbon/human/H = bot.owner
	if(!H.Adjacent(table))
		return step.go_to(bot, table)
	if(!bot.ready_in_hand(handout))
		return GOAL_STEP_FAIL
	var/area/A = get_area(table)
	handout.bot_handout_for = null
	H.transferItemToLoc(handout, get_turf(table))
	bot.handouts_given++
	bot_tally("science hand-outs")
	bot_log(bot, "SCIENCE: left [handout] in [A.name]")
	if(!bot.gym_scripted)
		bot_say(H, pick(";Left [handout] on the table in [A.name] for you.", ";R&D's made [handout] - it's in [A.name].", ";New kit from R&D: [handout], [A.name]."))
	return GOAL_STEP_SUCCESS
