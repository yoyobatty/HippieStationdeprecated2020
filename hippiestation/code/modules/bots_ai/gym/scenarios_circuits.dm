// Bot Gym scenarios for circuits (goals/circuits.dm).
//
// Layout letters: p a circuit printer (not upgraded), d the advanced designs disk, e a stack of metal, o an empty cell (as the lathe
// prints them), H a real wall to mount things on (the arena's own are indestructible, and nothing mounts on those).

/datum/bot_scenario/duty/circuits
	duty_type = /datum/bot_duty/circuitry
	job = "Scientist"
	time_limit = 300 SECONDS
	kit_backpack = list(/obj/item/screwdriver, /obj/item/wrench)
	/// What it's to build, by design id.
	var/design_id
	var/list/heard = list()

/datum/bot_scenario/duty/circuits/setup()
	CONFIG_SET(flag/ic_printing, TRUE)
	for(var/turf/T in markers["H"])
		T.ChangeTurf(/turf/closed/wall, flags = CHANGETURF_IGNORE_AIR)
	for(var/turf/T in markers["p"])
		place("p", new /obj/item/integrated_circuit_printer(T))
	for(var/turf/T in markers["d"])
		place("d", new /obj/item/disk/integrated_circuit/upgrade/advanced(T))
	for(var/turf/T in markers["e"])
		place("e", new /obj/item/stack/sheet/metal/fifty(T))
	for(var/turf/T in markers["o"])
		place("o", new /obj/item/stock_parts/cell/empty(T))

/datum/bot_scenario/duty/circuits/post_spawn()
	brain.circuit_forced_design = design_id
	brain.circuit_forced_site = arena_area
	brain.circuit_tinkerer = TRUE
	RegisterSignal(bot, COMSIG_MOVABLE_HEAR, PROC_REF(scenario_heard))

/datum/bot_scenario/duty/circuits/proc/scenario_heard(datum/source, list/hearing_args)
	SIGNAL_HANDLER
	var/atom/movable/speaker = hearing_args[HEARING_SPEAKER]
	if(istype(speaker, /obj/item/electronic_assembly))
		var/said = html_decode("[hearing_args[HEARING_RAW_MESSAGE]]") //"I&#39;m not a bomb" never matched the line it came from
		heard += said
		log_line("[speaker] said \"[said]\"")

/datum/bot_scenario/duty/circuits/release_run()
	UnregisterSignal(bot, COMSIG_MOVABLE_HEAR)
	return ..()

/// What it made, wherever it is.
/datum/bot_scenario/duty/circuits/proc/made()
	for(var/obj/item/electronic_assembly/E as anything in GLOB.bot_circuit_made)
		if(!QDELETED(E) && get_area(E) == arena_area && GLOB.bot_circuit_made[E] == design_id)
			return E

/datum/bot_scenario/duty/circuits/greeter
	name = "circuits: scientist builds a greeter and puts it up"
	desc = "A printer that isn't upgraded, the advanced designs disk, metal and an empty cell lying about, and a wall. The scientist upgrades the printer, feeds it metal, pastes the greeter in through Load Program and prints it, scans itself into the locator with a debugger it prints, puts it up on the wall, fits the cell and closes it, and wrenches it down. It greets whoever it sees, by name."
	design_id = "greeter"
	layout = list(
		"###########",
		"#B..p.....#",
		"#.........#",
		"#.d.e.o..H#",
		"###########")

/datum/bot_scenario/duty/circuits/greeter
	var/mob/living/carbon/human/visitor
	var/up_at
	var/greeted_at
	/// What it says to the visitor, besides their name.
	var/expect = "Welcome to"

/// Up and wrenched down, and then somebody comes in: it says hello to them by name. (The builder may or may not get its own hello: the
/// cell comes out of the lathe empty, and the first pulse can find it before the relay's put enough in it to speak.)
/datum/bot_scenario/duty/circuits/greeter/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/item/electronic_assembly/E = made()
	if(!E || !E.anchored || E.opened || !E.battery)
		return BOT_GYM_PENDING
	if(!isturf(E.loc) || !(E.pixel_x || E.pixel_y))
		fail_reason = "the greeter's anchored but not on a wall"
		return BOT_GYM_FAIL
	if(!up_at)
		up_at = world.time
		log_line("the greeter's up: charge [E.battery.charge]")
	if(!visitor && world.time > up_at + 8 SECONDS)
		visitor = stand_in(get_step(get_turf(E), pick(GLOB.cardinals)), "Casey Visitor")
		if(visitor.loc.density)
			visitor.forceMove(get_turf(E))
		log_line("Casey Visitor walks in")
	// The visitor greeted, and then, with the two of them stood by it for a while, nobody greeted twice: the locator picks one of them at
	// random every tick, and a greeter that only remembered the last name said hello to each in turn, over and over.
	if(!greeted_at)
		for(var/line in heard)
			if(findtext(line, expect) && findtext(line, "Casey Visitor"))
				greeted_at = world.time
				log_line("the visitor's been greeted; both stay near it for 25 seconds")
		return BOT_GYM_PENDING
	if(get_dist(bot, E) > 2)
		bot.forceMove(get_turf(visitor))
	if(world.time < greeted_at + 25 SECONDS)
		return BOT_GYM_PENDING
	var/list/count = list()
	for(var/line in heard)
		count[line]++
		if(count[line] > 1)
			fail_reason = "it said \"[line]\" more than once with the same two people stood there"
			return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/duty/circuits/greeter/release_run()
	if(visitor)
		qdel(visitor)
	return ..()

/// From a Box shift: the printer, its disk and the cell were printed at the protolathe and lay on the lathe's own tile, the alarm printed
/// on to it too, out of reach, and the scientist gave up; another had no wrench, fetched one, and gave up on the wall it had walked away from.
/// Letters: h a protolathe with the printer, disk and cell on its tile, u a wrench lying across the room.
/datum/bot_scenario/duty/circuits/greeter/off_the_lathe
	name = "circuits: printer left on the lathe, and no wrench to hand"
	desc = "Everything the build needs came out of the protolathe and is sitting on it. The scientist takes the printer off the lathe and puts it down, reaches the disk and cell from beside the machine, and when it comes to bolting the greeter down, goes for the wrench across the room and comes back to finish."
	kit_backpack = list(/obj/item/screwdriver)
	layout = list(
		"############",
		"#B..h......#",
		"#..........#",
		"#.e......uH#",
		"############")

/datum/bot_scenario/duty/circuits/greeter/off_the_lathe/setup()
	. = ..()
	for(var/turf/T in markers["h"])
		place("h", new /obj/machinery/rnd/production/protolathe(T))
		place("p", new /obj/item/integrated_circuit_printer(T))
		place("d", new /obj/item/disk/integrated_circuit/upgrade/advanced(T))
		place("o", new /obj/item/stock_parts/cell/empty(T))
	for(var/turf/T in markers["u"])
		place("u", new /obj/item/wrench(T))

/datum/bot_scenario/duty/circuits/pocket_pal
	name = "circuits: scientist builds a pocket pal"
	desc = "The same bench, and nothing to put up anywhere: it makes itself a pocket pal, with a cell in and the panel shut, and its button says something when pressed."
	design_id = "pocket_pal"
	layout = list(
		"##########",
		"#B..p....#",
		"#.d.e.o..#",
		"##########")

/datum/bot_scenario/duty/circuits/pocket_pal/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/item/electronic_assembly/E = brain.find_carried_tool(/obj/item/electronic_assembly/small)
	if(!E || E.opened || !E.battery || brain.state != BOT_STATE_WANDER)
		return BOT_GYM_PENDING
	// Its button, pressed the way the bot presses it.
	if(!length(heard))
		E.attack_self(bot)
		return BOT_GYM_PENDING
	return (heard[1] in GLOB.bot_pocket_pal_lines) ? BOT_GYM_PASS : BOT_GYM_PENDING

/// An officer hears a motion alarm call somebody in: walks over, tells them to get out, and arrests them when they don't.
/// Letters: A where the alarm is, I the intruder.
/datum/bot_scenario/circuit_alarm
	name = "circuits: officer answers a motion alarm and deals with the intruder"
	desc = "A motion alarm on the wall of a locked room radios that an assistant's in there. The officer goes, tells them to get out, and when they stay put, arrests them. The Warden named by the same alarm is let be."
	job = "Security Officer"
	time_limit = 90 SECONDS
	kit_backpack = list(/obj/item/restraints/handcuffs, /obj/item/melee/baton/loaded)
	layout = list(
		"############",
		"#B........D#",
		"#..........#",
		"#.....A..I.#",
		"############")
	var/mob/living/carbon/human/intruder
	var/obj/item/electronic_assembly/wallmount/light/alarm
	var/heard_warden = FALSE

/datum/bot_scenario/circuit_alarm/issue_goal()
	return

/datum/bot_scenario/circuit_alarm/post_spawn()
	alarm = new(first_marker("A"))
	alarm.name = "motion alarm"
	intruder = stand_in(first_marker("I"), "Ivy Intruder")
	// The room's door wants an access the intruder hasn't got (bot_card_opens_area() looks at the doors).
	var/obj/machinery/door/airlock/D = first_placed("D")
	D.req_access = list(ACCESS_ARMORY)
	GLOB.bot_area_airlocks -= arena_area
	// First the Warden: no call for somebody whose card opens the place.
	var/mob/living/carbon/human/warden = stand_in(get_step(first_marker("I"), WEST), "Wes Warden")
	var/obj/item/card/id/card = new(warden)
	card.access = list(ACCESS_ARMORY)
	warden.equip_to_slot_or_del(card, ITEM_SLOT_ID)
	brain.on_heard_circuit_alarm(alarm, "Motion alarm, Bot Gym Arena: Wes Warden.", FREQ_COMMON)
	heard_warden = istype(brain.current_goal, /datum/bot_goal/respond_to_call)
	qdel(warden)
	brain.on_heard_circuit_alarm(alarm, "Motion alarm, Bot Gym Arena: Ivy Intruder.", FREQ_COMMON)

/datum/bot_scenario/circuit_alarm/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(heard_warden)
		fail_reason = "it went after the Warden, whose card opens the room"
		return BOT_GYM_FAIL
	if(intruder.handcuffed)
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/duty/circuits/greeter/readout
	name = "circuits: scientist puts up the Medbay health readout"
	desc = "The same bench and a wall. The scientist builds the health readout, puts it up and bolts it down, and when somebody walks up to it, it says their name and how healthy they are, once."
	design_id = "health_readout"
	expect = "% health."

// ---------------------------------------------------------------------------------------------
// Drones (goals/circuit_drones.dm). Letters: p a printer, d the advanced designs disk, e metal, o an empty cell, Q the target.
// The special delivery carries a flashbang here: the real one's a minibomb, and the arenas sit side by side.
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/circuit_drone
	job = "Scientist"
	time_limit = 300 SECONDS
	max_goal_attempts = 20
	kit_backpack = list(/obj/item/screwdriver, /obj/item/grenade/flashbang)
	var/plan = "delivery_drone"
	var/mob/living/carbon/human/victim
	var/list/heard = list()
	var/obj/item/electronic_assembly/drone/drone
	layout = list(
		"#################",
		"#B..p...........#",
		"#.d.e.o.........#",
		"#..............Q#",
		"#################")

/datum/bot_scenario/circuit_drone/setup()
	CONFIG_SET(flag/ic_printing, TRUE)
	for(var/turf/T in markers["p"])
		place("p", new /obj/item/integrated_circuit_printer(T))
	for(var/turf/T in markers["d"])
		place("d", new /obj/item/disk/integrated_circuit/upgrade/advanced(T))
	for(var/turf/T in markers["e"])
		place("e", new /obj/item/stack/sheet/metal/fifty(T))
	for(var/turf/T in markers["o"])
		place("o", new /obj/item/stock_parts/cell/empty(T))

/datum/bot_scenario/circuit_drone/post_spawn()
	victim = stand_in(first_marker("Q"), "Vic Target")
	brain.drone_plan = plan
	brain.drone_plan_since = world.time
	RegisterSignal(victim, COMSIG_MOVABLE_HEAR, PROC_REF(victim_heard))

/datum/bot_scenario/circuit_drone/proc/victim_heard(datum/source, list/hearing_args)
	SIGNAL_HANDLER
	var/atom/movable/speaker = hearing_args[HEARING_SPEAKER]
	if(istype(speaker, /obj/item/electronic_assembly))
		heard += "[hearing_args[HEARING_RAW_MESSAGE]]"

/// What a traitor's objective would hand it, as the traitor duty asks for it: the next step towards the drone.
/datum/bot_scenario/circuit_drone/issue_goal()
	if(brain.state != BOT_STATE_WANDER || brain.goal_chain_pending)
		return
	var/datum/bot_goal/G = brain.drone_goal_for_victim(victim)
	if(istype(G) && brain.assign_goal(G))
		goal_attempts++
		log_line("drone plan: [G.type]")

/datum/bot_scenario/circuit_drone/release_run()
	if(victim)
		UnregisterSignal(victim, COMSIG_MOVABLE_HEAR)
	return ..()

/datum/bot_scenario/circuit_drone/proc/find_drone()
	if(!drone)
		for(var/obj/item/electronic_assembly/drone/D in GLOB.bot_circuit_made)
			if(!QDELETED(D) && get_area(D) == arena_area && GLOB.bot_circuit_made[D] == plan)
				drone = D
				log_line("built: [D]")
	return drone

/datum/bot_scenario/circuit_drone/delivery
	name = "circuits: traitor scientist sends a special delivery after its target"
	desc = "A traitor Scientist with a kill target across the room, a printer, the disk, metal and a cell lying about, and a grenade in its bag. It builds the special delivery with the grenade in its primer, walks it into sight of the target, puts it down, powers it up, shuts it, and gets clear. The drone finds the target by name, chases them saying a lot of polite things at once, and goes off beside them."

/datum/bot_scenario/circuit_drone/delivery/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!find_drone())
		return BOT_GYM_PENDING
	var/obj/item/integrated_circuit/manipulation/grenade/primer = locate() in drone.assembly_components
	if(primer?.attached_grenade && !QDELETED(primer.attached_grenade))
		return BOT_GYM_PENDING
	var/dist = get_dist(drone, victim)
	log_line("it went off [dist] tiles from Vic; heard: [jointext(heard, " | ")]")
	if(dist > 2)
		fail_reason = "it went off [dist] tiles from its target"
		return BOT_GYM_FAIL
	if(!findtext(jointext(heard, "|"), "Vic Target! You have a package"))
		fail_reason = "it never told Vic about the package"
		return BOT_GYM_FAIL
	if(length(uniqueList(heard)) < 5)
		fail_reason = "only [length(uniqueList(heard))] different lines: it's meant to say lots at once"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/circuit_drone/hunter
	name = "circuits: traitor scientist sends a hunter drone after its target"
	desc = "The same, with a mini energy crossbow in the bag instead: a hunter drone that finds the target by name, closes in and shoots."
	plan = "hunter_drone"
	kit_backpack = list(/obj/item/screwdriver, /obj/item/gun/energy/kinetic_accelerator/crossbow)

/datum/bot_scenario/circuit_drone/hunter/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!find_drone())
		return BOT_GYM_PENDING
	if(victim.getStaminaLoss() > 0 || victim.getToxLoss() > 0 || victim.IsKnockdown() || victim.IsParalyzed())
		log_line("Vic's been shot: stamina [victim.getStaminaLoss()], tox [victim.getToxLoss()]")
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/// A special delivery already on its way, as somebody's left it: powered, shut, with a flashbang in it.
/datum/bot_scenario/proc/gym_delivery_drone(turf/T, mob/living/carbon/human/victim)
	var/datum/bot_circuit_design/D = GLOB.bot_circuit_designs["delivery_drone"]
	var/list/program = SScircuit.validate_electronic_assembly(D.save_string(brain.drone_context(D, victim)))
	if(!islist(program))
		log_line("the delivery design doesn't load: [program]")
		return null
	var/obj/item/electronic_assembly/A = SScircuit.load_electronic_assembly(T, program)
	var/obj/item/integrated_circuit/manipulation/grenade/primer = A.assembly_components[D.payload_part]
	primer.attach_grenade(new /obj/item/grenade/flashbang(primer))
	A.battery = new /obj/item/stock_parts/cell/high(A)
	A.opened = FALSE
	A.update_icon()
	GLOB.bot_circuit_made[A] = D.id
	return A

/// Letters: A where the drone starts, Q its target.
/datum/bot_scenario/circuit_drone_shot
	name = "circuits: officer shoots down a drone with a bomb on it"
	desc = "A special delivery trundling across the room after somebody, an officer with a laser between them. The officer shoots it to pieces before it gets there: a disabler does nothing to an assembly."
	job = "Security Officer"
	time_limit = 90 SECONDS
	kit_backpack = list(/obj/item/gun/energy/laser)
	layout = list(
		"################",
		"#A.....B.......#",
		"#..............#",
		"#.............Q#",
		"################")
	var/mob/living/carbon/human/victim
	var/obj/item/electronic_assembly/drone

/datum/bot_scenario/circuit_drone_shot/issue_goal()
	return

/datum/bot_scenario/circuit_drone_shot/post_spawn()
	victim = stand_in(first_marker("Q"), "Vic Target")
	drone = gym_delivery_drone(first_marker("A"), victim)

/datum/bot_scenario/circuit_drone_shot/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!drone || QDELETED(drone))
		return BOT_GYM_PASS
	var/obj/item/integrated_circuit/manipulation/grenade/primer = locate() in drone.assembly_components
	if(!primer?.attached_grenade || QDELETED(primer.attached_grenade))
		fail_reason = "it got to Vic and went off ([drone.obj_integrity]/[drone.max_integrity] left)"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/// Letters: A where the drone starts, Q its target.
/datum/bot_scenario/circuit_drone_flee
	name = "circuits: an assistant gets away from a drone with a bomb on it"
	desc = "A special delivery comes into the room after somebody else, talking about bombs. An unarmed assistant with no great nerve gets away from it."
	job = "Assistant"
	time_limit = 40 SECONDS
	layout = list(
		"##############",
		"#A..B........#",
		"#............#",
		"#...........Q#",
		"##############")
	var/mob/living/carbon/human/victim
	var/obj/item/electronic_assembly/drone
	var/ran = FALSE

/datum/bot_scenario/circuit_drone_flee/issue_goal()
	return

/datum/bot_scenario/circuit_drone_flee/post_spawn()
	brain.nerve = 0.3
	victim = stand_in(first_marker("Q"), "Vic Target")
	drone = gym_delivery_drone(first_marker("A"), victim)

/// By where it is, not what it's doing: it gets away inside a second, before a check has seen it go.
/datum/bot_scenario/circuit_drone_flee/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(istype(brain.current_goal, /datum/bot_goal/run_from) || get_dist(bot, drone) >= 6)
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/circuit_drone_flee/release_run()
	if(drone && !QDELETED(drone))
		qdel(drone)
	return ..()

/datum/bot_scenario/circuit_drone_shot/release_run()
	if(drone && !QDELETED(drone))
		qdel(drone)
	return ..()
