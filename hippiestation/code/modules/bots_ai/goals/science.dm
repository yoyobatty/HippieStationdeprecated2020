// Science: a Scientist or the Research Director keeps research moving. Points come in by themselves
// while the servers run (about one cheap node's worth a minute); what the department has to do is
// spend them, at the R&D console, node by node down the tech tree - cheapest first, which is how a
// player who just wants the tree unlocked does it. The click is the console's "research" link
// (rdconsole/research_node()), a node at a time.

/datum/bot_brain
	var/nodes_researched = 0
	var/list/science_blocked

/datum/bot_brain/proc/is_science_job()
	var/role = owner.mind?.assigned_role
	return role == "Scientist" || role == "Research Director"

/// An R&D console in Science that can unlock nodes. A Bot Gym scientist's is in its arena.
/datum/bot_brain/proc/find_rd_console()
	var/obj/machinery/computer/rdconsole/best
	var/best_dist
	for(var/obj/machinery/computer/rdconsole/C as anything in bot_instances_of(/obj/machinery/computer/rdconsole))
		if(QDELETED(C) || C.z != owner.z || (C.stat & (BROKEN|NOPOWER)) || C.locked || !C.research_control || !C.stored_research)
			continue
		if(gym_run ? (get_area(C) != get_area(owner)) : !istype(get_area(C), /area/science))
			continue
		if(LAZYACCESS(science_blocked, C) > world.time)
			continue
		var/dist = get_dist(owner, C)
		if(!best || dist < best_dist)
			best = C
			best_dist = dist
	return best

/// The cheapest node the console's techweb can unlock right now, as its id - or null.
/datum/bot_brain/proc/next_research_node(obj/machinery/computer/rdconsole/C)
	var/datum/techweb/web = C?.stored_research
	if(!web)
		return null
	var/best
	var/best_cost
	for(var/id in web.available_nodes)
		if(web.researched_nodes[id] || web.hidden_nodes[id])
			continue
		var/datum/techweb_node/node = SSresearch.techweb_node_by_id(id)
		if(!istype(node))
			continue
		var/list/price = node.get_price(web)
		if(!web.can_afford(price))
			continue
		var/cost = 0
		for(var/point_type in price)
			cost += price[point_type]
		if(!best || cost < best_cost)
			best = id
			best_cost = cost
	return best

/datum/bot_duty/research
	name = "research"
	jobs = list("Scientist", "Research Director")
	interval_min = 600
	interval_max = 1500

/datum/bot_duty/research/try_start(datum/bot_brain/bot)
	var/obj/machinery/computer/rdconsole/C = bot.find_rd_console()
	if(!C || !bot.next_research_node(C))
		return FALSE
	return bot.assign_goal(new /datum/bot_goal/research())

/datum/bot_goal/research
	lawful = TRUE
	exclusive = TRUE //one at the console
	doing = "doing some research"

/datum/bot_goal/research/resolve_target(datum/bot_brain/bot)
	target = bot.find_rd_console()

/datum/bot_goal/research/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/research/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/paced/research_nodes())
	return list(S)

/datum/bot_goal/research/on_give_up(datum/bot_brain/bot)
	if(target)
		LAZYSET(bot.science_blocked, target, world.time + 3 MINUTES)

/datum/bot_strategy/research/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// At the console: unlock what can be afforded, up to a few nodes a sitting.
/datum/bot_step/paced/research_nodes
	max_clicks = 4
	var/list/unlocked
	var/misses = 0

/datum/bot_step/paced/research_nodes/start(datum/bot_brain/bot)
	unlocked = list()
	misses = 0
	return bot.owner.Adjacent(bot.current_goal?.target)

/datum/bot_step/paced/research_nodes/do_click(datum/bot_brain/bot)
	var/obj/machinery/computer/rdconsole/C = bot.current_goal?.target
	if(!istype(C) || QDELETED(C) || !bot.owner.Adjacent(C) || (C.stat & (BROKEN|NOPOWER)))
		return FALSE
	var/id = bot.next_research_node(C)
	if(!id)
		return FALSE
	var/datum/techweb_node/node = SSresearch.techweb_node_by_id(id)
	bot.human_pause(C)
	if(QDELETED(C) || !bot.owner.Adjacent(C))
		return FALSE
	bot.owner.face_atom(C)
	bot.telemetry_ui_action(C, "research [node.display_name]")
	if(!C.research_node(id, bot.owner))
		// Somebody at another console got to it first, or the points went on something else: look again in a moment.
		wait_for = rand(5, 20)
		return ++misses < 6
	unlocked += node.display_name
	bot.nodes_researched++
	bot_log(bot, "researched [node.display_name]")
	return TRUE

/datum/bot_step/paced/research_nodes/finish(datum/bot_brain/bot)
	// Tells the department what's new, some of the time - the designs are no use to anyone who doesn't know they're there.
	if(length(unlocked) && !bot.gym_scripted && prob(40 + bot.sociability * 40))
		bot.say_after_typing(":n [english_list(unlocked)] researched.")
	return length(unlocked) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL
