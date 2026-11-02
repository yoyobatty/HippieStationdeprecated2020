// The E.X.P.E.R.I-MENTOR: strange objects from around the station get their purpose found out, and anything else that's going
// spare gets put through the tests to see what it does. Every item type answers to one of six tests, and nothing says which, so
// the only way to find out is to try them, one a sitting, and remember what's been tried. It lives up to its reputation: it
// burns, shocks and gasses whoever is standing by it now and then, and that's the job. Whoever is on it minds its own air and
// fire the same as anywhere else.

/// The six tests (SCANTYPE_POKE to SCANTYPE_OBLITERATE in experimentor.dm) and "discover", which is relics only.
#define BOT_EXPERIMENT_TESTS 6
#define BOT_EXPERIMENT_DISCOVER 7
/// Tests in a sitting: the machine gets its breath back between them.
#define BOT_EXPERIMENT_SITTING 3

/// Item type -> list of the tests already tried on it. Shared: the department keeps its notes.
GLOBAL_LIST_EMPTY(bot_experiment_notes)
/// Item type -> the test it turned out to answer to.
GLOBAL_LIST_EMPTY(bot_experiment_findings)

/datum/bot_brain
	var/experiments_run = 0
	var/relics_revealed = 0
	var/experiment_blocked_until = 0

/datum/bot_brain/proc/find_experimentor()
	for(var/obj/machinery/rnd/experimentor/E as anything in bot_instances_of(/obj/machinery/rnd/experimentor))
		if(!QDELETED(E) && E.z == owner.z && !E.panel_open && !(E.stat & (BROKEN|NOPOWER)) && in_science(E) && !taken_by_another(E))
			return E
	return null

/// Whether an item type still has tests nobody has tried on it.
/proc/bot_worth_testing(item_type)
	if(GLOB.bot_experiment_findings[item_type])
		return FALSE
	return LAZYLEN(GLOB.bot_experiment_notes[item_type]) < BOT_EXPERIMENT_TESTS

/// Something to put in the machine: a strange object first, on the bot or in the department, then a spare part from the bench.
/datum/bot_brain/proc/find_test_subject()
	var/obj/item/relic/carried = find_carried_tool(/obj/item/relic)
	if(carried && !carried.revealed)
		return carried
	for(var/obj/item/relic/R as anything in bot_instances_of(/obj/item/relic))
		if(!QDELETED(R) && !R.revealed && isturf(R.loc) && R.z == owner.z && in_science(R))
			return R
	for(var/part_type in list(/obj/item/stock_parts/manipulator, /obj/item/stock_parts/matter_bin, /obj/item/stock_parts/micro_laser, /obj/item/stock_parts/capacitor, /obj/item/stock_parts/scanning_module))
		for(var/obj/item/stock_parts/part as anything in bot_instances_of(part_type))
			if(!QDELETED(part) && isturf(part.loc) && part.z == owner.z && in_science(part) && bot_worth_testing(part.type))
				return part
	return null

/datum/bot_duty/experimentor
	name = "experimentor"
	jobs = list("Scientist", "Research Director")
	interval_min = 400
	interval_max = 900

/datum/bot_duty/experimentor/try_start(datum/bot_brain/bot)
	if(world.time < bot.experiment_blocked_until || !bot.find_experimentor())
		return FALSE
	var/obj/item/subject = bot.find_test_subject()
	if(!subject)
		return FALSE
	return bot.assign_goal(new /datum/bot_goal/run_experiment(subject))

/datum/bot_goal/run_experiment
	lawful = TRUE
	exclusive = TRUE
	doing = "running experiments"
	var/obj/item/subject

/datum/bot_goal/run_experiment/New(obj/item/I)
	. = ..()
	subject = I

/datum/bot_goal/run_experiment/resolve_target(datum/bot_brain/bot)
	target = !QDELETED(subject) && bot.find_experimentor()

/datum/bot_goal/run_experiment/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/robotics/S = new
	S.steps = list(new /datum/bot_step/carry_subject(), new /datum/bot_step/move_to(), new /datum/bot_step/paced/run_experiment())
	return list(S)

/datum/bot_goal/run_experiment/on_give_up(datum/bot_brain/bot)
	bot.experiment_blocked_until = world.time + 5 MINUTES

/// Into a hand, if it isn't there already.
/datum/bot_step/carry_subject
	var/tries = 0

/datum/bot_step/carry_subject/execute(datum/bot_brain/bot)
	var/datum/bot_goal/run_experiment/G = bot.current_goal
	if(!istype(G) || QDELETED(G.subject) || ++tries > 3)
		return GOAL_STEP_FAIL
	if(bot.is_carried(G.subject))
		return GOAL_STEP_SUCCESS
	return bot.suspend_goal_for(new /datum/bot_goal/take_item/exact(G.subject)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL

/// Loads it, runs a test or three on it, and takes it out again if there's anything left to take.
/datum/bot_step/paced/run_experiment
	max_clicks = 40
	var/tests = 0

/datum/bot_step/paced/run_experiment/start(datum/bot_brain/bot)
	tests = 0
	return TRUE

/datum/bot_step/paced/run_experiment/do_click(datum/bot_brain/bot)
	var/datum/bot_goal/run_experiment/G = bot.current_goal
	var/obj/machinery/rnd/experimentor/E = G?.target
	if(!istype(G) || !istype(E) || QDELETED(E) || !bot.owner.Adjacent(E) || (E.stat & (BROKEN|NOPOWER)))
		return FALSE
	if(!E.loaded_item)
		if(tests || QDELETED(G.subject))
			return FALSE
		if(!E.linked_console) //its "Scan for R&D Console" link
			E.linked_console = locate(/obj/machinery/computer/rdconsole) in oview(3, E)
			if(!E.linked_console)
				return FALSE
			bot.telemetry_ui_action(E, "scan for console")
		if(!bot.use_tool_on(G.subject, E) || !E.loaded_item)
			return FALSE
		bot_log(bot, "loaded [E.loaded_item] into [E]")
		return TRUE
	if(E.recentlyExperimented)
		wait_for = 10
		return TRUE
	var/obj/item/item = E.loaded_item
	if(tests >= BOT_EXPERIMENT_SITTING)
		return FALSE
	var/test = next_test(item)
	if(!test)
		return FALSE
	bot.human_pause(E)
	if(QDELETED(E) || E.loaded_item != item || E.recentlyExperimented)
		return TRUE
	bot.owner.face_atom(E)
	bot.telemetry_ui_action(E, "test [test] on [item]")
	var/item_type = item.type
	var/result = test == BOT_EXPERIMENT_DISCOVER ? test : E.matchReaction(item, test)
	LAZYADD(GLOB.bot_experiment_notes[item_type], test)
	usr = bot.owner //who gets the blame in the admin log, if it goes wrong
	E.experiment(result, item)
	E.use_power(750)
	tests++
	bot.experiments_run++
	if(result != 8) //FAIL in experimentor.dm
		GLOB.bot_experiment_findings[item_type] = test
		bot_log(bot, "[item] reacts to test [test]")
		if(test == BOT_EXPERIMENT_DISCOVER)
			bot.relics_revealed++
		if(!bot.gym_scripted && prob(60))
			bot.say_after_typing(":n [pick("Got a reaction out of [item].", "[capitalize(item.name)] does something, come and look.", "That's a result on [item].")]")
		return FALSE
	bot_log(bot, "no reaction from [item] on test [test]")
	wait_for = 20
	return TRUE

/datum/bot_step/paced/run_experiment/proc/next_test(obj/item/item)
	if(istype(item, /obj/item/relic))
		return BOT_EXPERIMENT_DISCOVER
	var/list/tried = GLOB.bot_experiment_notes[item.type]
	var/list/left = list()
	for(var/test in 1 to BOT_EXPERIMENT_TESTS)
		if(!(test in tried))
			left += test
	return length(left) ? pick(left) : null

/datum/bot_step/paced/run_experiment/finish(datum/bot_brain/bot)
	var/obj/machinery/rnd/experimentor/E = bot.current_goal?.target
	if(istype(E) && !QDELETED(E) && E.loaded_item && !E.recentlyExperimented)
		E.ejectItem()
	return tests ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

#undef BOT_EXPERIMENT_TESTS
#undef BOT_EXPERIMENT_DISCOVER
#undef BOT_EXPERIMENT_SITTING
