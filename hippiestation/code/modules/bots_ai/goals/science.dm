// Science: a Scientist or the Research Director keeps research moving. Points come in by themselves
// while the servers run (about one cheap node's worth a minute); what the department has to do is
// spend them, at the R&D console, node by node down the tech tree - cheapest first, which is how a
// player who just wants the tree unlocked does it. The click is the console's "research" link
// (rdconsole/research_node()), a node at a time.

/datum/bot_brain
	var/nodes_researched = 0
	var/list/science_blocked

/datum/bot_brain/proc/is_science_job()
	var/role = work_role()
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

/// What a department goes for first when it has a choice: the parts that make everything after them cheaper, the labs'
/// own tools, and bluespace. Everything else follows, cheapest first.
GLOBAL_LIST_INIT(bot_research_priorities, list("engineering", "biotech", "datatheory", "nanite_base", "adv_engi", "high_efficiency", "bio_process", "bluespace_basic", "practical_bluespace", "robotics", "adv_power", "adv_mining", "micro_bluespace"))

/// Machine parts, in the order they're worth having (the user's ruling, 2026-11-04: science queues up machine parts research, the
/// bluespace RPED first, as it upgrades machines from a distance and far quicker): each the node with the next tier in, reached by the
/// way there from what's researched (bot_research_path()).
GLOBAL_LIST_INIT(bot_parts_research, list("engineering", "practical_bluespace", "high_efficiency", "adv_power", "emp_adv", "micro_bluespace", "bluespace_power", "emp_super"))
/// Nodes somebody asked Science for -> when (the research request, below): before the parts.
GLOBAL_LIST_EMPTY(bot_research_wanted)
#define BOT_RESEARCH_WANTED_FOR (20 MINUTES)

/// The nodes still to research on the way to `id`, prerequisites first: the R&D console's "the way there" (interfaces/RdConsole.js).
/proc/bot_research_path(datum/techweb/web, id)
	. = list()
	bot_research_path_visit(web, id, ., list())

/proc/bot_research_path_visit(datum/techweb/web, id, list/order, list/seen)
	if(seen[id] || web.researched_nodes[id])
		return
	seen[id] = TRUE
	var/datum/techweb_node/N = SSresearch.techweb_node_by_id(id)
	if(!N)
		return
	for(var/prereq in N.prereq_ids)
		bot_research_path_visit(web, prereq, order, seen)
	order += id

/// The next step on the way to whatever's asked for, then to the next tier of parts: its id, or null when that step wants more points
/// than there are, which are saved for it. FALSE when there's nothing on either list it can get to.
/proc/bot_research_next_wanted(datum/techweb/web)
	for(var/id in GLOB.bot_research_wanted)
		if(web.researched_nodes[id] || world.time > GLOB.bot_research_wanted[id] + BOT_RESEARCH_WANTED_FOR)
			GLOB.bot_research_wanted -= id
	for(var/target in GLOB.bot_research_wanted + GLOB.bot_parts_research)
		if(web.researched_nodes[target])
			continue
		var/list/path = bot_research_path(web, target)
		var/next
		for(var/id in path)
			if(web.hidden_nodes[id])
				next = null //something in the way the analyzer has to reveal first: not this one
				break
			if(!next && web.available_nodes[id])
				next = id
		if(!next)
			continue
		var/datum/techweb_node/N = SSresearch.techweb_node_by_id(next)
		return web.can_afford(N.get_price(web)) ? next : null
	return FALSE

/// The node to unlock next, as its id - or null: what's been asked for, then the parts, saving up for the next of them, then the first
/// of the priorities the points cover, or the cheapest there is.
/datum/bot_brain/proc/next_research_node(obj/machinery/computer/rdconsole/C)
	var/datum/techweb/web = C?.stored_research
	if(!web)
		return null
	var/wanted = bot_research_next_wanted(web)
	if(wanted != FALSE)
		return wanted
	for(var/id in GLOB.bot_research_priorities)
		if(!web.available_nodes[id] || web.researched_nodes[id] || web.hidden_nodes[id])
			continue
		var/datum/techweb_node/priority = SSresearch.techweb_node_by_id(id)
		if(istype(priority) && web.can_afford(priority.get_price(web)))
			return id
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

/// Whoever asked for research, told when what they asked for is done, on the channel they asked on.
/datum/bot_brain/proc/tell_who_asked(list/ids)
	var/mob/living/asker = research_asked_by?.resolve()
	if(!asker)
		return
	var/list/done = list()
	for(var/id in ids)
		if(id in research_asked_for)
			var/datum/techweb_node/N = SSresearch.techweb_node_by_id(id)
			done += N.display_name
			research_asked_for -= id
	if(!length(done))
		return
	var/their_name = asker.name != "Unknown" ? "[asker.first_name()], " : ""
	say_after_typing(bot_radio_prefix(research_asked_freq) + "[their_name][english_list(done)] [length(done) > 1 ? "are" : "is"] researched[length(research_asked_for) ? ", more on the way" : ""].")
	if(!length(research_asked_for))
		research_asked_by = null

/datum/bot_strategy/research/is_feasible(datum/bot_brain/bot)
	return bot.current_goal?.target && !QDELETED(bot.current_goal.target)

/// At the console: unlock what can be afforded, up to a few nodes a sitting.
/datum/bot_step/paced/research_nodes
	max_clicks = 4
	var/list/unlocked
	var/list/unlocked_ids
	var/misses = 0

/datum/bot_step/paced/research_nodes/start(datum/bot_brain/bot)
	unlocked = list()
	unlocked_ids = list()
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
	unlocked_ids += id
	bot.nodes_researched++
	bot_log(bot, "researched [node.display_name]")
	return TRUE

/datum/bot_step/paced/research_nodes/finish(datum/bot_brain/bot)
	// Tells the department what's new, some of the time - the designs are no use to anyone who doesn't know they're there.
	if(length(unlocked) && !bot.gym_scripted && prob(40 + bot.sociability * 40))
		bot.say_after_typing(":n [english_list(unlocked)] researched.")
	bot.tell_who_asked(unlocked_ids)
	return length(unlocked) ? GOAL_STEP_SUCCESS : GOAL_STEP_FAIL

// ---------------------------------------------------------------------------------------------
// Asked for research
// ---------------------------------------------------------------------------------------------

// "Science, can you research stock parts?" (the user, on the radio, in a played round: "where?", and then nothing). By who it is, a
// scientist either puts it at the front of what it researches and says so, or tells them to come and do it themselves and lets them
// into R&D when they turn up (the user's ruling, 2026-11-04).

/datum/bot_brain
	/// Who asked for research, what of it isn't done yet, and the channel they asked on.
	var/datum/weakref/research_asked_by
	var/list/research_asked_for
	var/research_asked_freq
	/// Somebody told to come and research it themselves, to be let into R&D, and until when.
	var/datum/weakref/research_visitor
	var/research_visitor_until = 0

/datum/bot_request
	/// A research request whoever took it would rather they did themselves.
	var/self_serve = FALSE

/// What a line asks to be researched, as node ids: the parts path for parts and upgrades, or the nodes nearest to hand whose name, or a
/// design's, has a word of what they said.
/proc/bot_research_topic(lower_msg)
	if(bot_text_has_any(lower_msg, list("stock part", "stock parts", "machine part", "machine parts", "parts", "part upgrades", "upgrades", "upgrade", "rped", "better parts", "tier")))
		return GLOB.bot_parts_research.Copy()
	var/static/list/filler = list("some", "more", "please", "could", "would", "with", "that", "this", "your", "into", "stuff", "things", "them", "those", "these", "anything", "something", "science", "about", "research", "researched", "unlock", "maybe")
	var/at = findtext(lower_msg, "research")
	var/list/words = list()
	for(var/word in splittext(copytext(lower_msg, at ? at + 8 : 1), regex("\\W+")))
		if(length(word) >= 4 && !(word in filler))
			words += word
	if(!length(words))
		return list()
	var/datum/techweb/web = SSresearch.science_tech
	var/list/found = list()
	for(var/id in SSresearch.techweb_nodes)
		var/datum/techweb_node/N = SSresearch.techweb_nodes[id]
		if(web.hidden_nodes[id])
			continue
		var/haystack = lowertext(N.display_name)
		for(var/design_id in N.design_ids)
			var/datum/design/D = SSresearch.techweb_design_by_id(design_id)
			if(D)
				haystack += " [lowertext(D.name)]"
		for(var/word in words)
			if(findtext(haystack, word))
				found[id] = length(bot_research_path(web, id))
				break
	sortTim(found, GLOBAL_PROC_REF(cmp_numeric_asc), associative = TRUE)
	. = list()
	for(var/id in found)
		. += id
		if(length(.) >= 3)
			break

/datum/bot_request_kind/research
	name = "research"
	jobs = list("Scientist", "Research Director")
	role_words = list("science", "scientist", "scientists", "rnd", "rd")
	walks_there = FALSE
	needs_place = FALSE
	precedence = 10
	doing = "researching something somebody asked for"

/datum/bot_request_kind/research/matches(lower_msg, named, turf/near)
	var/text = replacetext(lower_msg, "research director", "rd") //the title, not the verb
	if(!bot_text_has_any(text, list("research", "unlock")))
		return FALSE
	if(!bot_text_has_any(text, GLOB.bot_request_words))
		return FALSE
	return named || bot_text_has_any(text, role_words)

/datum/bot_request_kind/research/read_details(datum/bot_request/R, lower_msg)
	R.detail = bot_research_topic(lower_msg)

/datum/bot_request_kind/research/ack_for(datum/bot_brain/bot, datum/bot_request/R)
	var/obj/machinery/computer/rdconsole/C = bot.find_rd_console()
	var/datum/techweb/web = C?.stored_research || SSresearch.science_tech
	var/list/topic = R.detail
	if(!length(topic))
		return pick("Research what, exactly?", "What do you need researched?", "Which bit of the tree?")
	var/list/todo = list()
	for(var/id in topic)
		if(!web.researched_nodes[id])
			todo += id
	if(!length(todo))
		return pick("That's all researched already, the protolathe can print it.", "Already done, it's on the lathe.", "We've got that one, ask at the protolathe.")
	// The ones who'd sooner not, and say so: the console's theirs to use (the user's ruling).
	if(bot.diligence < 0.5)
		R.self_serve = TRUE
		return bot.mood_pick(list("I'll let you in if you want to research it yourself! Come by R&D.", "Come by R&D and I'll let you in, the console's all yours."), list("Come by R&D, I'll let you in. Research it yourself if you like.", "I'll let you in if you wanna just research it yourself."), list("Do it yourself, I'll let you in. R&D.", "Console's in R&D. I'll get the door."))
	var/next
	var/list/path = bot_research_path(web, todo[1])
	for(var/id in path)
		if(web.available_nodes[id])
			next = id
			break
	var/datum/techweb_node/N = SSresearch.techweb_node_by_id(next || todo[1])
	var/short = max(0, (N.get_price(web)[TECHWEB_POINT_TYPE_GENERIC] || 0) - (web.research_points[TECHWEB_POINT_TYPE_GENERIC] || 0))
	return "[pick("On it.", "Sure.", "Will do.")] [N.display_name] [length(path) > 1 ? "first, it's on the way" : "next"][short ? ", once we've [round(short)] more points" : ""]."

/datum/bot_request_kind/research/attend(datum/bot_brain/bot, datum/bot_request/R)
	var/mob/living/asker = R.caller_ref?.resolve()
	var/obj/machinery/computer/rdconsole/C = bot.find_rd_console()
	var/datum/techweb/web = C?.stored_research || SSresearch.science_tech
	var/list/todo = list()
	for(var/id in R.detail)
		if(!web.researched_nodes[id])
			todo += id
	if(!length(todo) || !asker)
		return
	if(R.self_serve)
		bot.research_visitor = WEAKREF(asker)
		bot.research_visitor_until = world.time + 5 MINUTES
		bot_log(bot, "told [asker] to come and research it themselves")
		return
	for(var/id in todo)
		GLOB.bot_research_wanted[id] = world.time
	bot.research_asked_by = WEAKREF(asker)
	bot.research_asked_for = todo
	bot.research_asked_freq = R.radio_freq
	bot_log(bot, "asked to research [english_list(todo)] - at the front of the list")
	if(bot.state == BOT_STATE_WANDER && !bot.current_goal && bot.next_research_node(C))
		bot.assign_goal(new /datum/bot_goal/research())

/// Somebody told to come and research it themselves, at a door into Science they can't open: over to it, and in they come.
/datum/bot_duty/let_researcher_in
	name = "letting somebody into R&D"
	jobs = list("Scientist", "Research Director")
	tier = BOT_DUTY_URGENT
	priority = 24
	interval_min = 20
	interval_max = 40

/datum/bot_duty/let_researcher_in/try_start(datum/bot_brain/bot)
	var/mob/living/visitor = bot.research_visitor?.resolve()
	if(!visitor || world.time > bot.research_visitor_until || visitor.stat != CONSCIOUS)
		bot.research_visitor = null
		return FALSE
	if(get_dist(bot.owner, visitor) > 15)
		return FALSE
	// At the door, whether it can see them or not: the door buzzes at a card it won't take, and it's waiting for them.
	for(var/obj/machinery/door/airlock/D in range(2, visitor))
		if(!D.density || D.locked || D.welded || !D.hasPower() || D.allowed(visitor) || !D.allowed(bot.owner) || get_dist(bot.owner, D) > 12)
			continue
		if(!istype(get_area(D), /area/science) && !bot.gym_run)
			continue
		bot.research_visitor = null
		bot_say(bot.owner, "[bot.open_a_door_for(visitor)] [pick("Console's just in there.", "The R&D console's that one.", "Help yourself.")]")
		bot_log(bot, "letting [visitor] in to do their own research")
		return FALSE
	return FALSE

#undef BOT_RESEARCH_WANTED_FOR
