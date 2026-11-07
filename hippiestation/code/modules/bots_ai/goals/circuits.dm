// Circuits: Science's tinkerers build integrated circuits the way an experienced player does (the user's rulings, 2026-11-07,
// IC_PRINTING on). They keep their designs as save strings, like anyone with a notes file, and paste them into the printer.
//
//  - The printer comes from research (Advanced Data Theory, asked for through the department's research list) printed at the
//    protolathe, or the Cargo starter crate. The advanced designs disk from the same node goes into it: every design here
//    draws its power from the room's APC with a tesla power relay, and that's an advanced circuit.
//  - Metal sheets into the printer, Load Program, paste, Print Assembly, and a wait while it prints (metal / 15 deciseconds).
//  - A locator that has to know what it's looking for gets a debugger slid over the builder, then a click on its pin.
//  - A power cell, the screwdriver, and it's done. A wall-mounted one goes up first and gets its cell on the wall, so it
//    isn't announcing everybody in the corridors on the way there.
//
// What gets built (all four of the user's kinds; this file has the first three designs, the drones and department helpers
// come after): a motion alarm where something's worth guarding and the builder's ID opens the door, which calls on the radio
// whoever it sees, and Security comes (on_heard_circuit_alarm()); a greeter that welcomes people by name in the bar, at arrivals
// or in the Medbay lobby; a pocket pal that says something silly when its button's pressed.

/// Not before this far into the round: research and a printer take a while, and nobody starts on a hobby straight away.
#define BOT_CIRCUIT_SETTLE_IN (8 MINUTES)
/// How long to leave it after something didn't work out.
#define BOT_CIRCUIT_REST (6 MINUTES)
/// The most a station has of each wall-mounted kind.
#define BOT_CIRCUIT_MAX_ALARMS 3
#define BOT_CIRCUIT_MAX_GREETERS 2
/// The most one bot builds in a round.
#define BOT_CIRCUIT_MAX_PER_BOT 3
/// The longest it'll stand watching a print.
#define BOT_CIRCUIT_PRINT_WAIT (4 MINUTES)

/// Rooms worth an alarm, if the builder's card opens them.
GLOBAL_LIST_INIT(bot_circuit_alarm_sites, list(/area/ai_monitored/turret_protected/ai_upload, /area/ai_monitored/nuke_storage, /area/ai_monitored/security/armory,
	/area/storage/tech, /area/teleporter, /area/engine/gravity_generator))
/// Where people come in and could do with a hello.
GLOBAL_LIST_INIT(bot_circuit_greeter_sites, list(/area/crew_quarters/bar, /area/hallway/secondary/entry, /area/medical/medbay/lobby))
/// Area type -> weakref to what's mounted there.
GLOBAL_LIST_EMPTY(bot_circuit_sites)
/// Area type -> when somebody set off to make something for it: spoken for a while, so two don't build for the same wall.
GLOBAL_LIST_EMPTY(bot_circuit_reserved)
/// Assemblies the bots made -> design id.
GLOBAL_LIST_EMPTY(bot_circuit_made)
/// Area -> the airlocks that lead into it (worked out once).
GLOBAL_LIST_EMPTY(bot_area_airlocks)

/datum/bot_brain
	/// Whether circuits are this one's thing: null until it's first asked.
	var/circuit_tinkerer
	var/circuit_blocked_until = 0
	var/circuits_built = 0
	/// When it last asked Cargo for the starter crate.
	var/circuit_crate_asked = 0
	/// A Bot Gym run's design and site, instead of choosing (gym/scenarios_circuits.dm).
	var/circuit_forced_design
	var/area/circuit_forced_site
	/// When it last played with its pocket pal.
	var/next_gadget_play = 0

// ---------------------------------------------------------------------------------------------
// Designs
// ---------------------------------------------------------------------------------------------

/datum/bot_circuit_design
	var/id
	/// What the builder calls it.
	var/name
	/// The case, by its printer name.
	var/case_name
	/// The circuits, by their printer names, in order: the save's component numbers.
	var/list/parts
	/// list(part, input pin, value). A value that's a key of the build's context ("prefix") is swapped for it.
	var/list/constants
	/// list(part, "O" or "A", pin, part, "I" or "A", pin)
	var/list/wires
	/// list(part, input pin): set with the debugger's ref scanner, slid over the builder (a person for the locator to look for).
	var/list/scan_pins
	var/wall_mounted = FALSE

/// The save string to paste, with the context's words in place.
/datum/bot_circuit_design/proc/save_string(list/context)
	var/list/components = list()
	var/list/inputs_by_part = list()
	for(var/list/C in constants)
		var/value = C[3]
		if(istext(value) && context && (value in context))
			value = context[value]
		var/list/part_inputs = inputs_by_part["[C[1]]"]
		if(!part_inputs)
			part_inputs = list()
			inputs_by_part["[C[1]]"] = part_inputs
		part_inputs += list(list(C[2], FALSE, value))
	for(var/i in 1 to length(parts))
		var/list/component = list("type" = parts[i])
		if(inputs_by_part["[i]"])
			component["inputs"] = inputs_by_part["[i]"]
		components += list(component)
	var/list/wire_list = list()
	for(var/list/W in wires)
		wire_list += list(list(list(W[1], W[2], W[3]), list(W[4], W[5], W[6])))
	var/list/blocks = list("assembly" = list("type" = case_name, "name" = name), "components" = components)
	if(length(wire_list))
		blocks["wires"] = wire_list
	return json_encode(blocks)

/// Whoever it sees, said once as they turn up: a ticker, a locator looking for people, their name, and a list of who it's already said,
/// cleared every five minutes by a second, slow ticker. (Remembering only the last one, with two people about it said one, then the
/// other, then the first again: the locator picks one at random every tick. Clearing the list whenever nobody was in range, a busy
/// bar's greeter welcomed the same bartender twice in ten seconds.)
/datum/bot_circuit_design/announcer
	case_name = "light wall-mounted electronic assembly"
	wall_mounted = TRUE
	parts = list("slow ticker", "advanced locator", "reference to string", "search circuit", "append circuit", "memory chip", "memory chip", "concatenator", "text-to-speech circuit", "tesla power relay", "custom ticker")
	scan_pins = list(list(2, 1))
	wires = list(
		list(1, "A", 1, 2, "A", 1), //tick: look
		list(2, "O", 1, 3, "I", 1), //what it saw, as a name
		list(2, "A", 2, 3, "A", 1),
		list(3, "O", 1, 4, "I", 2), //already said?
		list(3, "O", 1, 5, "I", 2),
		list(3, "O", 1, 8, "I", 2),
		list(3, "A", 2, 4, "A", 1),
		list(4, "A", 3, 5, "A", 1), //no: onto the list,
		list(5, "O", 1, 6, "I", 1),
		list(5, "A", 2, 6, "A", 1), //kept,
		list(5, "A", 2, 8, "A", 1), //and said
		list(6, "O", 1, 4, "I", 1),
		list(6, "O", 1, 5, "I", 1),
		list(8, "O", 1, 9, "I", 1),
		list(8, "A", 2, 9, "A", 1),
		list(11, "A", 1, 7, "A", 1), //every five minutes: the list starts again
		list(7, "O", 1, 6, "I", 1),
		list(7, "A", 2, 6, "A", 1))

/datum/bot_circuit_design/announcer/alarm
	id = "motion_alarm"
	name = "motion alarm"
	parts = list("slow ticker", "advanced locator", "reference to string", "search circuit", "append circuit", "memory chip", "memory chip", "concatenator", "text-to-radio circuit", "tesla power relay", "custom ticker")
	constants = list(list(1, 1, 1), list(2, 2, 3), list(4, 1, "empty"), list(5, 1, "empty"), list(7, 1, "empty"), list(8, 1, "prefix"), list(8, 3, "."), list(9, 2, 1459), list(11, 1, 1), list(11, 2, 3000))

/datum/bot_circuit_design/announcer/greeter
	id = "greeter"
	name = "greeter"
	constants = list(list(1, 1, 1), list(2, 2, 2), list(4, 1, "empty"), list(5, 1, "empty"), list(7, 1, "empty"), list(8, 1, "prefix"), list(8, 3, "!"), list(11, 1, 1), list(11, 2, 3000))

/// A button, a list of things to say and a speaker.
/datum/bot_circuit_design/pocket_pal
	id = "pocket_pal"
	name = "pocket pal"
	case_name = "electronic device"
	parts = list("button", "pick circuit", "text-to-speech circuit", "tesla power relay")
	constants = list(list(2, 1, "lines"))
	wires = list(
		list(1, "A", 1, 2, "A", 1),
		list(2, "O", 1, 3, "I", 1),
		list(2, "A", 2, 3, "A", 1))

GLOBAL_LIST_INIT(bot_circuit_designs, init_bot_circuit_designs())

/proc/init_bot_circuit_designs()
	. = list()
	for(var/path in subtypesof(/datum/bot_circuit_design))
		var/datum/bot_circuit_design/D = new path
		if(D.id)
			.[D.id] = D

GLOBAL_LIST_INIT(bot_pocket_pal_lines, list("Beep boop!", "I am a circuit. I have no feelings. Beep.", "Have you tried turning it off and on again?",
	"Science rules!", "Warning: fun levels critical.", "Hello, friend!", "Please do not lick the circuitry.", "Calculating... calculating... 42.",
	"I'm not a bomb, I promise.", "Ping!"))

// ---------------------------------------------------------------------------------------------
// Where things go
// ---------------------------------------------------------------------------------------------

/// The airlocks into an area: the doors standing in it, or on its edge with it on one side.
/proc/bot_area_airlocks(area/A)
	. = GLOB.bot_area_airlocks[A]
	if(.)
		return
	. = list()
	for(var/obj/machinery/door/airlock/D in A)
		. += D
	GLOB.bot_area_airlocks[A] = .

/// Whether this card would let its holder into the area: one of its doors opens to it, or it has no doors at all.
/proc/bot_card_opens_area(obj/item/card/id/card, area/A)
	var/list/doors = bot_area_airlocks(A)
	if(!length(doors))
		return TRUE
	if(!card)
		return FALSE
	for(var/obj/machinery/door/airlock/D as anything in doors)
		if(!QDELETED(D) && D.check_access(card))
			return TRUE
	return FALSE

/// The first area of one of these types on this z-level, as the map has it.
/proc/bot_find_area_of(list/types, z)
	for(var/area_type in types)
		for(var/area/A in GLOB.sortedAreas)
			if(istype(A, area_type) && A.z == z)
				return A

/// Somewhere in the area to stand and put something on the wall: a clear floor tile with a wall straight beside it and nothing on that
/// wall already, as near the middle of the room as there is. Returns list(floor, wall).
/proc/bot_circuit_mount_spot(area/A)
	var/list/turfs = list()
	for(var/turf/open/floor/F in A)
		turfs += F
	if(!length(turfs))
		return null
	var/cx = 0
	var/cy = 0
	for(var/turf/F as anything in turfs)
		cx += F.x
		cy += F.y
	cx /= length(turfs)
	cy /= length(turfs)
	var/list/best
	var/best_dist
	for(var/turf/open/floor/F as anything in turfs)
		if(F.density || is_blocked_turf(F, TRUE))
			continue
		for(var/dir in GLOB.cardinals)
			var/turf/closed/wall/W = get_step(F, dir)
			if(!istype(W) || gotwallitem(F, dir))
				continue
			var/dist = abs(F.x - cx) + abs(F.y - cy)
			if(!best || dist < best_dist)
				best = list(F, W)
				best_dist = dist
	return best

/// Something the bot's carrying, or lying about Science or Robotics, of this type.
/datum/bot_brain/proc/find_circuit_supply(item_type, check_type = null)
	var/obj/item/carried = find_carried_tool(item_type)
	if(carried)
		return carried
	var/obj/item/best
	var/best_dist
	for(var/obj/item/I as anything in bot_instances_of(item_type))
		if(QDELETED(I) || !isturf(I.loc) || I.anchored || I.z != owner.z || (!in_science(I) && !in_robotics(I)))
			continue
		if(check_type && !istype(I, check_type))
			continue
		if(istype(I, /obj/item/electronic_assembly) || (istype(I, /obj/item/stock_parts/cell) && (locate(/obj/machinery/cell_charger) in I.loc)))
			continue
		var/dist = get_dist(owner, I)
		if(!best || dist < best_dist)
			best = I
			best_dist = dist
	return best

/// A circuit printer this bot can use: its own, or one lying about the department.
/datum/bot_brain/proc/find_circuit_printer()
	var/obj/item/integrated_circuit_printer/carried = find_carried_tool(/obj/item/integrated_circuit_printer)
	if(carried)
		return carried
	var/obj/item/integrated_circuit_printer/best
	var/best_dist
	for(var/obj/item/integrated_circuit_printer/P as anything in bot_instances_of(/obj/item/integrated_circuit_printer))
		if(QDELETED(P) || !isturf(P.loc) || P.z != owner.z || P.cloning || (!in_science(P) && !in_robotics(P)))
			continue
		if(taken_by_another(P))
			continue
		var/dist = get_dist(owner, P)
		if(!best || dist < best_dist)
			best = P
			best_dist = dist
	return best

/// Nobody can stand here: a wall, or a machine or anything else dense on it (a table's fine to reach over).
/proc/bot_tile_blocked(turf/T)
	if(T.density)
		return TRUE
	for(var/obj/O in T)
		if(O.density && !istype(O, /obj/structure/table))
			return TRUE
	return FALSE

/proc/bot_circuit_site_taken(area/A)
	var/datum/weakref/ref = GLOB.bot_circuit_sites[A.type]
	var/obj/item/electronic_assembly/E = ref?.resolve()
	if(E && !QDELETED(E))
		return TRUE
	return GLOB.bot_circuit_reserved[A.type] && world.time < GLOB.bot_circuit_reserved[A.type] + 20 MINUTES

/proc/bot_circuit_count(id)
	. = 0
	for(var/obj/item/electronic_assembly/E as anything in GLOB.bot_circuit_made)
		if(QDELETED(E))
			GLOB.bot_circuit_made -= E
		else if(GLOB.bot_circuit_made[E] == id)
			.++

/// What this bot would build next, and where: list(design, context, site area), or null.
/datum/bot_brain/proc/next_circuit_build()
	var/obj/item/card/id/card = owner.get_idcard(TRUE)
	if(circuit_forced_design)
		var/datum/bot_circuit_design/forced = GLOB.bot_circuit_designs[circuit_forced_design]
		return list(forced, circuit_context(forced, circuit_forced_site), circuit_forced_site)
	if(bot_circuit_count("motion_alarm") < BOT_CIRCUIT_MAX_ALARMS)
		for(var/area_type in GLOB.bot_circuit_alarm_sites)
			var/area/A = bot_find_area_of(list(area_type), owner.z)
			if(A && !bot_circuit_site_taken(A) && bot_card_opens_area(card, A) && bot_circuit_mount_spot(A))
				var/datum/bot_circuit_design/alarm = GLOB.bot_circuit_designs["motion_alarm"]
				return list(alarm, circuit_context(alarm, A), A)
	if(bot_circuit_count("greeter") < BOT_CIRCUIT_MAX_GREETERS)
		for(var/area_type in GLOB.bot_circuit_greeter_sites)
			var/area/A = bot_find_area_of(list(area_type), owner.z)
			if(A && !bot_circuit_site_taken(A) && bot_card_opens_area(card, A) && bot_circuit_mount_spot(A))
				var/datum/bot_circuit_design/greeter = GLOB.bot_circuit_designs["greeter"]
				return list(greeter, circuit_context(greeter, A), A)
	if(!find_carried_tool(/obj/item/electronic_assembly/small))
		var/datum/bot_circuit_design/pal = GLOB.bot_circuit_designs["pocket_pal"]
		return list(pal, circuit_context(pal, null), null)
	return null

/// The words that go into a design for where it's going.
/datum/bot_brain/proc/circuit_context(datum/bot_circuit_design/D, area/A)
	. = list("empty" = list())
	var/place = A ? get_area_name(A, TRUE) : null
	switch(D.id)
		if("motion_alarm")
			.["prefix"] = "Motion alarm, [place]: "
		if("greeter")
			.["prefix"] = "Welcome to [place], "
		if("pocket_pal")
			var/list/lines = GLOB.bot_pocket_pal_lines.Copy()
			shuffle_inplace(lines)
			lines.Cut(6)
			.["lines"] = lines

// ---------------------------------------------------------------------------------------------
// The duty
// ---------------------------------------------------------------------------------------------

/datum/bot_duty/circuitry
	name = "circuitry"
	jobs = list("Scientist", "Research Director")
	interval_min = 1200
	interval_max = 2400

/datum/bot_duty/circuitry/try_start(datum/bot_brain/bot)
	if(isnull(bot.circuit_tinkerer))
		bot.circuit_tinkerer = bot.gym_run || prob(bot.work_role() == "Research Director" ? 60 : 35)
	if(!bot.circuit_tinkerer || world.time < bot.circuit_blocked_until || bot.circuits_built >= BOT_CIRCUIT_MAX_PER_BOT)
		return FALSE
	if(!bot.gym_run && world.time - SSticker.round_start_time < BOT_CIRCUIT_SETTLE_IN)
		return FALSE
	var/list/build = bot.next_circuit_build()
	if(!build)
		bot.circuit_blocked_until = world.time + BOT_CIRCUIT_REST * 2
		return FALSE
	var/datum/bot_circuit_design/D = build[1]
	// The printer, first: printed at the lathe once it's been researched, or the starter crate from Cargo.
	var/obj/item/integrated_circuit_printer/printer = bot.find_circuit_printer()
	if(!printer)
		return bot.get_circuit_printer()
	// The advanced designs disk, if it isn't in yet: every design here wants the power relay.
	if(!printer.upgraded && !bot.find_circuit_supply(/obj/item/disk/integrated_circuit/upgrade/advanced))
		return bot.print_for_circuits("icupgadv")
	// A cell for it.
	if(!bot.find_circuit_supply(/obj/item/stock_parts/cell))
		return bot.print_for_circuits("basic_cell")
	// Metal: what's in the printer, and what's about.
	var/datum/component/material_container/mats = printer.GetComponent(/datum/component/material_container)
	var/list/program = SScircuit.validate_electronic_assembly(D.save_string(build[2]))
	if(!islist(program))
		bot_log(bot, "the [D.name] design doesn't load: [program]")
		bot.circuit_blocked_until = world.time + BOT_CIRCUIT_REST * 10
		return FALSE
	if(mats.amount(MAT_METAL) < program["metal_cost"] + 400 && !bot.find_circuit_supply(/obj/item/stack/sheet/metal))
		bot.ask_for_materials(list(MAT_METAL = TRUE))
		bot.circuit_blocked_until = world.time + BOT_CIRCUIT_REST
		return FALSE
	var/datum/bot_goal/build_circuit/G = new(printer, D, build[2], build[3])
	if(!bot.assign_goal(G))
		return FALSE
	if(build[3])
		GLOB.bot_circuit_reserved[G.site.type] = world.time
	return TRUE

/// No printer about: print one if it's been researched, or ask for the research, and Cargo for the crate.
/datum/bot_brain/proc/get_circuit_printer()
	if(bot_researched_design("icprinter"))
		return print_for_circuits("icprinter")
	GLOB.bot_research_wanted["adv_datatheory"] = world.time
	if(!gym_scripted && world.time > circuit_crate_asked + 20 MINUTES)
		circuit_crate_asked = world.time
		ask_cargo_for(/datum/supply_pack/science/circuitry, "a circuitry starter pack", "science", /obj/item/integrated_circuit_printer)
	circuit_blocked_until = world.time + BOT_CIRCUIT_REST
	return FALSE

/// One thing printed at the lathe for the circuits, after which it comes back here.
/datum/bot_brain/proc/print_for_circuits(design_id)
	var/datum/design/D = bot_researched_design(design_id)
	var/obj/machinery/rnd/production/protolathe/lathe = find_lathe()
	if(!D || !lathe)
		circuit_blocked_until = world.time + BOT_CIRCUIT_REST
		return FALSE
	var/list/short = list()
	if(!bot_lathe_can_afford(lathe, D, 1, short))
		ask_for_materials(short)
		circuit_blocked_until = world.time + BOT_CIRCUIT_REST
		return FALSE
	var/datum/bot_goal/print_design/P = new(lathe, D, 1)
	P.chain_duty = /datum/bot_duty/circuitry
	return assign_goal(P)

// ---------------------------------------------------------------------------------------------
// Building one
// ---------------------------------------------------------------------------------------------

/datum/bot_goal/build_circuit
	lawful = TRUE
	exclusive = TRUE
	doing = "building a circuit"
	var/datum/bot_circuit_design/design
	var/list/context
	var/area/site
	var/loaded = FALSE
	var/print_started = 0
	var/list/already_there
	var/obj/item/electronic_assembly/made
	var/scans_done = 0

/datum/bot_goal/build_circuit/New(obj/item/integrated_circuit_printer/P, datum/bot_circuit_design/D, list/context, area/site)
	. = ..()
	target = P
	design = D
	src.context = context
	src.site = site
	doing = "building a [D.name]"

/datum/bot_goal/build_circuit/resolve_target(datum/bot_brain/bot)
	if(QDELETED(target))
		target = null

/datum/bot_goal/build_circuit/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/robotics/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/work_circuit())
	return list(S)

/datum/bot_goal/build_circuit/on_give_up(datum/bot_brain/bot)
	bot.circuit_blocked_until = world.time + BOT_CIRCUIT_REST
	if(site && !made)
		GLOB.bot_circuit_reserved -= site.type
	bot_log(bot, "gave up on the [design.name]")

/datum/bot_goal/build_circuit/on_success(datum/bot_brain/bot)
	bot.circuits_built++
	GLOB.bot_circuit_made[made] = design.id
	if(site)
		GLOB.bot_circuit_sites[site.type] = WEAKREF(made)
	bot_log(bot, "built a [design.name][site ? " for [site]" : ""]")
	if(design.wall_mounted)
		bot.continue_goal_chain(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, mount_circuit), made, site, design))
	else
		bot.put_away(made)

/// The printer, the paste, the print, and what's left to do to it after: one thing at a time, coming back after each.
/datum/bot_step/work_circuit
	var/fetches = 0

/// Over to it and into a hand. Something on a machine's tile (what the lathe prints lands on the lathe) is reached for from beside it:
/// nobody can walk on to it, and take_item/exact tried, and gave up on it.
/datum/bot_step/work_circuit/proc/fetch(datum/bot_brain/bot, obj/item/I)
	if(!I || fetches >= 12)
		return GOAL_STEP_FAIL
	fetches++
	if(isturf(I.loc) && bot_tile_blocked(I.loc))
		if(bot.owner.Adjacent(I))
			return bot.take_in_hand(I) ? again(bot) : GOAL_STEP_FAIL
		return bot.suspend_goal_for(new /datum/bot_goal/walk_up_to(I)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL
	return bot.suspend_goal_for(new /datum/bot_goal/take_item/exact(I)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL

/datum/bot_step/work_circuit/proc/again(datum/bot_brain/bot, delay)
	addtimer(CALLBACK(src, PROC_REF(carry_on), bot, bot.current_goal), delay || rand(4, 8))
	return GOAL_STEP_PENDING

/datum/bot_step/work_circuit/proc/carry_on(datum/bot_brain/bot, datum/bot_goal/goal)
	if(QDELETED(bot) || bot.state != BOT_STATE_GOAL || bot.current_goal != goal || bot.current_strategy?.steps?[bot.current_step_index] != src)
		return
	var/result
	try
		result = execute(bot)
	catch(var/exception/e)
		bot_log_exception(bot, "work_circuit", e)
		result = GOAL_STEP_FAIL
	if(result != GOAL_STEP_PENDING)
		bot.advance_goal_step(result == GOAL_STEP_SUCCESS)

/// Clicks the printer's window the way its links do.
/datum/bot_step/work_circuit/proc/printer_click(datum/bot_brain/bot, obj/item/integrated_circuit_printer/P, list/href_list, what)
	bot.human_pause(P)
	if(QDELETED(P) || !bot.owner.Adjacent(P))
		return FALSE
	bot.telemetry_ui_action(P, what)
	usr = bot.owner
	P.Topic(list2params(href_list), href_list)
	return TRUE

/datum/bot_step/work_circuit/execute(datum/bot_brain/bot)
	var/datum/bot_goal/build_circuit/G = bot.current_goal
	var/obj/item/integrated_circuit_printer/P = G?.target
	if(!istype(G) || !istype(P) || QDELETED(P))
		return GOAL_STEP_FAIL
	if(G.made)
		return finish_assembly(bot, G, P)
	if(!bot.owner.Adjacent(P))
		if(fetches >= 12)
			return GOAL_STEP_FAIL
		fetches++
		return bot.suspend_goal_for(new /datum/bot_goal/walk_up_to(P)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL
	// Still on the lathe it came out of: off it and down on the floor, where what it prints can be picked up. (An alarm printed on to the
	// lathe's own tile was out of everybody's reach.)
	if(isturf(P.loc) && bot_tile_blocked(P.loc))
		if(!bot.take_in_hand(P))
			return GOAL_STEP_FAIL
		bot.owner.dropItemToGround(P)
		bot_log(bot, "took [P] off the machine and put it down")
		return again(bot)
	var/datum/component/material_container/mats = P.GetComponent(/datum/component/material_container)
	// Printing: stood watching it, like anyone.
	if(G.print_started)
		for(var/obj/item/electronic_assembly/E in get_turf(P))
			if(!(E in G.already_there))
				G.made = E
				bot_log(bot, "the printer's done: [E]")
				return again(bot)
		if(!P.cloning || world.time > G.print_started + BOT_CIRCUIT_PRINT_WAIT)
			bot_log(bot, "the print never came out")
			return GOAL_STEP_FAIL
		return again(bot, 2 SECONDS)
	// The advanced designs disk.
	if(!P.upgraded)
		var/obj/item/disk/integrated_circuit/upgrade/advanced/disk = bot.find_circuit_supply(/obj/item/disk/integrated_circuit/upgrade/advanced)
		if(!disk)
			return GOAL_STEP_FAIL
		if(!(disk in bot.owner.GetAllContents()))
			return fetch(bot, disk)
		bot_log(bot, "putting [disk] into [P]")
		if(!bot.use_tool_on(disk, P) || !P.upgraded)
			return GOAL_STEP_FAIL
		bot.put_away(disk) //kept for the next printer, as anybody would
		return again(bot)
	var/list/program = SScircuit.validate_electronic_assembly(G.design.save_string(G.context))
	if(!islist(program))
		return GOAL_STEP_FAIL
	// Metal.
	if(mats.amount(MAT_METAL) < program["metal_cost"] + 400)
		var/obj/item/stack/sheet/metal/sheets = bot.find_circuit_supply(/obj/item/stack/sheet/metal)
		if(!sheets)
			return GOAL_STEP_FAIL
		if(!(sheets in bot.owner.GetAllContents()))
			return fetch(bot, sheets)
		bot_log(bot, "feeding [sheets.amount] metal to [P]")
		var/before = mats.amount(MAT_METAL)
		if(!bot.use_tool_on(sheets, P) || mats.amount(MAT_METAL) <= before)
			return GOAL_STEP_FAIL
		if(!QDELETED(sheets) && (sheets in bot.owner.held_items))
			bot.owner.dropItemToGround(sheets) //what the printer had no room for, put back down
		return again(bot)
	// A debugger, for a design with a pin to scan: off the printer's Tools page.
	if(length(G.design.scan_pins) && !bot.find_carried_tool(/obj/item/integrated_electronics/debugger))
		var/obj/item/integrated_electronics/debugger/loose = bot.find_circuit_supply(/obj/item/integrated_electronics/debugger)
		if(loose)
			return fetch(bot, loose)
		if(!printer_click(bot, P, list("category" = "Tools"), "Tools"))
			return GOAL_STEP_FAIL
		if(!printer_click(bot, P, list("build" = "[/obj/item/integrated_electronics/debugger]"), "print a circuit debugger"))
			return GOAL_STEP_FAIL
		var/obj/item/integrated_electronics/debugger/printed = bot.find_carried_tool(/obj/item/integrated_electronics/debugger) || locate() in get_turf(bot.owner)
		if(!printed)
			return GOAL_STEP_FAIL
		if(isturf(printed.loc))
			bot.take_in_hand(printed)
		bot.put_away(printed)
		return again(bot)
	// Load Program: the design pasted in from its notes.
	if(!G.loaded)
		bot.human_pause(P)
		bot.telemetry_ui_action(P, "Load Program")
		sleep(rand(15, 35)) //finding it in the notes, and the paste
		if(QDELETED(P) || !bot.owner.Adjacent(P) || P.cloning)
			return GOAL_STEP_FAIL
		P.program = program
		G.loaded = TRUE
		bot_log(bot, "loaded the [G.design.name] into [P]: [program["metal_cost"]] metal, complexity [program["complexity"]]/[program["max_complexity"]]")
		return again(bot)
	// Print Assembly.
	G.already_there = list()
	for(var/obj/item/electronic_assembly/E in get_turf(P))
		G.already_there += E
	if(!printer_click(bot, P, list("print" = "print"), "Print Assembly"))
		return GOAL_STEP_FAIL
	if(!P.cloning)
		for(var/obj/item/electronic_assembly/E in get_turf(P))
			if(!(E in G.already_there))
				G.made = E
				return again(bot)
		bot_log(bot, "[P] wouldn't print the [G.design.name]")
		return GOAL_STEP_FAIL
	G.print_started = world.time
	bot_log(bot, "printing the [G.design.name]")
	return again(bot, 2 SECONDS)

/// The print in hand: the debugger over itself and onto the pins that want a person, then a cell and the screwdriver (a wall-mounted
/// one gets those on the wall).
/datum/bot_step/work_circuit/proc/finish_assembly(datum/bot_brain/bot, datum/bot_goal/build_circuit/G, obj/item/integrated_circuit_printer/P)
	var/obj/item/electronic_assembly/A = G.made
	if(QDELETED(A))
		return GOAL_STEP_FAIL
	if(!(A in bot.owner.GetAllContents()))
		if(isturf(A.loc) && bot.owner.Adjacent(A))
			return bot.take_in_hand(A) ? again(bot) : GOAL_STEP_FAIL
		return fetch(bot, A)
	if(G.scans_done < length(G.design.scan_pins))
		var/list/scan = G.design.scan_pins[G.scans_done + 1]
		var/obj/item/integrated_circuit/IC = A.assembly_components[scan[1]]
		var/datum/integrated_io/pin = IC?.inputs[scan[2]]
		var/obj/item/integrated_electronics/debugger/debugger = bot.find_carried_tool(/obj/item/integrated_electronics/debugger)
		if(!pin || !debugger || !bot.ready_in_hand(debugger))
			return GOAL_STEP_FAIL
		// The ref scanner on, slid over itself, and a click on the pin in the assembly's window.
		bot.human_pause(debugger)
		bot.telemetry_ui_action(debugger, "ref scanner")
		debugger.accepting_refs = TRUE
		debugger.copy_values = FALSE
		bot.human_pause(bot.owner)
		debugger.afterattack(bot.owner, bot.owner, TRUE)
		bot.human_pause(A)
		bot.telemetry_ui_action(A, "write to [IC.displayed_name]'s [pin.name]")
		debugger.write_data(pin, bot.owner)
		G.scans_done++
		bot_log(bot, "scanned itself into [IC.displayed_name]'s [pin.name]")
		bot.put_away(debugger)
		return again(bot)
	if(G.design.wall_mounted)
		// Its cell, carried up with it.
		if(!bot.find_carried_tool(/obj/item/stock_parts/cell))
			var/obj/item/stock_parts/cell/cell = bot.find_circuit_supply(/obj/item/stock_parts/cell)
			if(!cell)
				return GOAL_STEP_FAIL
			return fetch(bot, cell)
		return GOAL_STEP_SUCCESS
	if(!A.battery && !bot.find_carried_tool(/obj/item/stock_parts/cell))
		var/obj/item/stock_parts/cell/loose = bot.find_circuit_supply(/obj/item/stock_parts/cell)
		if(!loose)
			return GOAL_STEP_FAIL
		return fetch(bot, loose)
	if(bot.needs_screwdriver_for(A))
		return bot.seek_tool_for_obstacle(/obj/item/screwdriver) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL
	return bot.power_and_close_circuit(A) ? (A.opened ? again(bot) : GOAL_STEP_SUCCESS) : GOAL_STEP_FAIL

/// The cell's in and the panel wants shutting, and there's no screwdriver on it.
/datum/bot_brain/proc/needs_screwdriver_for(obj/item/electronic_assembly/A)
	return A.battery && A.opened && !find_or_transform_tool(/obj/item/screwdriver)

/// A cell in and the panel shut, a click at a time: TRUE while it's getting on with it.
/datum/bot_brain/proc/power_and_close_circuit(obj/item/electronic_assembly/A)
	if(!A.battery)
		var/obj/item/stock_parts/cell/cell = find_carried_tool(/obj/item/stock_parts/cell)
		if(!cell)
			cell = find_circuit_supply(/obj/item/stock_parts/cell)
			if(!cell || !isturf(cell.loc) || !owner.Adjacent(cell))
				return FALSE
		if(!use_tool_on(cell, A) || A.battery != cell)
			return FALSE
		bot_log(src, "put [cell] in [A]")
		return TRUE
	if(A.opened)
		var/obj/item/screwdriver/S = find_or_transform_tool(/obj/item/screwdriver)
		if(!S)
			return FALSE
		if(!use_tool_on(S, A) || A.opened)
			return FALSE
		bot_log(src, "closed [A] up")
	return TRUE

// ---------------------------------------------------------------------------------------------
// Putting it up
// ---------------------------------------------------------------------------------------------

/datum/bot_brain/proc/mount_circuit(obj/item/electronic_assembly/A, area/site, datum/bot_circuit_design/D)
	if(QDELETED(A) || !site)
		return
	var/list/spot = bot_circuit_mount_spot(site)
	if(!spot)
		bot_log(src, "nowhere on the walls of [site] for [A]")
		put_away(A)
		return
	var/datum/bot_goal/mount_circuit/G = new(A, spot[1], spot[2])
	if(!assign_goal(G))
		put_away(A)

/datum/bot_goal/mount_circuit
	lawful = TRUE
	doing = "putting something up on a wall"
	var/obj/item/electronic_assembly/assembly
	var/turf/closed/wall/wall

/datum/bot_goal/mount_circuit/New(obj/item/electronic_assembly/A, turf/floor, turf/closed/wall/W)
	. = ..()
	assembly = A
	target = floor
	wall = W
	doing = "putting a [A.name] up"

/datum/bot_goal/mount_circuit/resolve_target(datum/bot_brain/bot)
	if(QDELETED(assembly) || QDELETED(wall))
		target = null

/datum/bot_goal/mount_circuit/get_strategies(datum/bot_brain/bot)
	var/datum/bot_strategy/robotics/S = new
	S.steps = list(new /datum/bot_step/move_to(), new /datum/bot_step/mount_circuit())
	return list(S)

/datum/bot_goal/mount_circuit/on_give_up(datum/bot_brain/bot)
	bot_log(bot, "couldn't get [assembly] up")
	bot.circuit_blocked_until = world.time + BOT_CIRCUIT_REST

/datum/bot_goal/mount_circuit/on_success(datum/bot_brain/bot)
	bot_log(bot, "put [assembly] up in [get_area(assembly)]")
	bot_tally("circuits put up")
	if(!bot.gym_scripted && prob(60))
		bot.say_after_typing(";[pick("Put a [assembly.name] up in [get_area_name(assembly, TRUE)].", "There's a [assembly.name] in [get_area_name(assembly, TRUE)] now, courtesy of Science.")]")

/// On the wall, the cell in, the panel shut, and the bolts wrenched down: a click each, back after each.
/datum/bot_step/mount_circuit
	var/tries = 0

/datum/bot_step/mount_circuit/proc/again(datum/bot_brain/bot)
	addtimer(CALLBACK(src, PROC_REF(carry_on), bot, bot.current_goal), rand(4, 8))
	return GOAL_STEP_PENDING

/datum/bot_step/mount_circuit/proc/carry_on(datum/bot_brain/bot, datum/bot_goal/goal)
	if(QDELETED(bot) || bot.state != BOT_STATE_GOAL || bot.current_goal != goal || bot.current_strategy?.steps?[bot.current_step_index] != src)
		return
	var/result
	try
		result = execute(bot)
	catch(var/exception/e)
		bot_log_exception(bot, "mount_circuit", e)
		result = GOAL_STEP_FAIL
	if(result != GOAL_STEP_PENDING)
		bot.advance_goal_step(result == GOAL_STEP_SUCCESS)

/datum/bot_step/mount_circuit/execute(datum/bot_brain/bot)
	var/datum/bot_goal/mount_circuit/G = bot.current_goal
	var/obj/item/electronic_assembly/wallmount/A = G?.assembly
	if(!istype(G) || !istype(A) || QDELETED(A) || ++tries > 12)
		return GOAL_STEP_FAIL
	if(A in bot.owner.GetAllContents())
		if(get_turf(bot.owner) != G.target)
			return bot.suspend_goal_for(new /datum/bot_goal/walk_up_to(G.target)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL
		if(!bot.use_tool_on(A, G.wall) || (A in bot.owner.GetAllContents()))
			bot_log(bot, "[A] wouldn't go on [G.wall]")
			return GOAL_STEP_FAIL
		return again(bot)
	if(!isturf(A.loc))
		return GOAL_STEP_FAIL
	if(!bot.owner.Adjacent(A)) //back from fetching a tool
		return bot.suspend_goal_for(new /datum/bot_goal/walk_up_to(A)) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL
	if(!A.battery || A.opened)
		if(bot.needs_screwdriver_for(A))
			return bot.seek_tool_for_obstacle(/obj/item/screwdriver) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL
		return bot.power_and_close_circuit(A) ? again(bot) : GOAL_STEP_FAIL
	if(!A.anchored)
		var/obj/item/wrench/W = bot.find_or_transform_tool(/obj/item/wrench)
		if(!W)
			return bot.seek_tool_for_obstacle(/obj/item/wrench) ? GOAL_STEP_PENDING : GOAL_STEP_FAIL
		if(!bot.use_tool_on(W, A))
			return GOAL_STEP_FAIL
		sleep(25) //the bolts take a moment
		return A.anchored ? GOAL_STEP_SUCCESS : again(bot)
	return GOAL_STEP_SUCCESS

// ---------------------------------------------------------------------------------------------
// The pocket pal, now and then
// ---------------------------------------------------------------------------------------------

/datum/bot_duty/circuit_gadget
	name = "playing with a gadget"
	tier = BOT_DUTY_LEISURE
	interval_min = 1800
	interval_max = 4800

/datum/bot_duty/circuit_gadget/try_start(datum/bot_brain/bot)
	var/obj/item/electronic_assembly/A = bot.find_carried_tool(/obj/item/electronic_assembly/small)
	if(!A || GLOB.bot_circuit_made[A] != "pocket_pal" || !A.battery || bot.owner.incapacitated())
		return FALSE
	if(!bot.ready_in_hand(A))
		return FALSE
	bot.human_pause(A)
	bot.telemetry_shortcut("attack_self", A, null)
	A.attack_self(bot.owner)
	bot_log(bot, "pressed the button on [A]")
	addtimer(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, put_away), A), rand(20, 40))
	return FALSE //nothing to see through: back to whatever it was doing

// ---------------------------------------------------------------------------------------------
// Security answers the alarm
// ---------------------------------------------------------------------------------------------

/// A motion alarm on the radio, heard by an officer: the person it names is looked up among who's there, and somebody whose card opens the
/// place (the Warden in the armory) is let be. Anybody else gets a visit (on_heard_security_call(), goals/security_patrol.dm).
/datum/bot_brain/proc/on_heard_circuit_alarm(obj/item/electronic_assembly/A, raw_message, radio_freq)
	var/lower = lowertext(raw_message)
	if(!findtext(lower, "alarm") && !findtext(lower, "intruder"))
		return
	var/turf/T = get_turf(A)
	var/area/where = get_area(T)
	if(!T || T.z != owner.z || world.time < next_security_call_time)
		return
	var/mob/living/carbon/human/named
	for(var/mob/living/carbon/human/H in view(7, T))
		if(findtext(raw_message, H.name))
			named = H
			break
	if(named && (named == owner || bot_card_opens_area(named.get_idcard(TRUE), where)))
		bot_log(src, "heard the alarm in [where] about [named], who's allowed in there")
		return
	next_security_call_time = world.time + 600
	if(state == BOT_STATE_GOAL)
		abandon_goals_for_arrest()
	var/datum/bot_goal/respond_to_call/alarm/G = new()
	G.caller_turf = T
	G.caller_name = "the [A.name]"
	G.alarm_area = where
	if(assign_goal(G))
		bot_say(owner, ":s Responding to the [A.name] in [get_area_name(T, TRUE)].")
		bot_tally("alarms answered")

/datum/bot_goal/respond_to_call/alarm
	var/area/alarm_area

/// There, a look at who's in the room: anybody who's got no business there is told to get out, and arrested if they're still there.
/datum/bot_goal/respond_to_call/alarm/on_success(datum/bot_brain/bot)
	. = ..()
	for(var/mob/living/carbon/human/H in view(7, bot.owner))
		if(H == bot.owner || H.stat == DEAD || H.handcuffed || get_area(H) != alarm_area)
			continue
		if(bot_card_opens_area(H.get_idcard(TRUE), alarm_area) || (H.mind?.assigned_role in GLOB.security_positions))
			continue
		bot.owner.face_atom(H)
		bot_say(bot.owner, "[H.name], you're not meant to be in here. Out.")
		addtimer(CALLBACK(bot, TYPE_PROC_REF(/datum/bot_brain, alarm_trespass_check), WEAKREF(H), alarm_area), 10 SECONDS)
		return

/datum/bot_brain/proc/alarm_trespass_check(datum/weakref/ref, area/where)
	var/mob/living/carbon/human/H = ref?.resolve()
	if(!H || QDELETED(owner) || owner.stat != CONSCIOUS || get_area(H) != where || H.handcuffed)
		return
	file_crime(H, bot_trespass_charge(where, world.time < H.bot_broke_in_at + 5 MINUTES), "Set off the motion alarm in [get_area_name(where, TRUE)] and stayed.", BOT_CRIME_MINOR)
	begin_arrest(H)

#undef BOT_CIRCUIT_SETTLE_IN
#undef BOT_CIRCUIT_REST
#undef BOT_CIRCUIT_MAX_ALARMS
#undef BOT_CIRCUIT_MAX_GREETERS
#undef BOT_CIRCUIT_MAX_PER_BOT
#undef BOT_CIRCUIT_PRINT_WAIT
