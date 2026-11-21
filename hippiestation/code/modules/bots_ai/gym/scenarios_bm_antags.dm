// Bot gym scenarios from the 2026-11-21 bot audit, antags area.

// ---------------------------------------------------------------------------------------------
// Space vines (goals/anomalies.dm)
// ---------------------------------------------------------------------------------------------

/// A botanist with a hatchet in a hall with vines in it, as the Spacevine event leaves them: it goes along them and cuts them all back.
/// Nobody on the crew did a thing about vines before: they spread across the halls all shift.
/datum/bot_scenario/duty/vines
	name = "vines: a botanist with a hatchet cuts back the vines in the hall"
	desc = "Three space vines along the hall and a botanist with a hatchet in its bag. It cuts them all down. Nobody did anything about the Spacevine event."
	job = "Botanist"
	kit_backpack = list(/obj/item/hatchet)
	layout = list(
		"##################",
		"#B.....1...2...3.#",
		"##################")
	time_limit = 75 SECONDS
	var/list/vines = list()

/datum/bot_scenario/duty/vines/setup()
	duty_type = text2path("/datum/bot_duty/cut_vines") //by name: a build without the duty has none
	for(var/n in list("1", "2", "3"))
		var/turf/T = first_marker(n)
		if(T)
			vines += new /obj/structure/spacevine(T)
	seen_vines()

/// Somebody's seen them, as a scripted bot in a gym arena doesn't look round to.
/datum/bot_scenario/duty/vines/proc/seen_vines()
	if(!("bot_vine_reports" in GLOB.vars))
		return //a build without the sighting list
	var/list/reports = GLOB.vars["bot_vine_reports"]
	for(var/obj/structure/spacevine/V in vines)
		reports[get_area(V)] = world.time

/datum/bot_scenario/duty/vines/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/obj/structure/spacevine/V in vines)
		if(!QDELETED(V))
			return BOT_GYM_PENDING
	return BOT_GYM_PASS

/datum/bot_scenario/duty/vines/release_run()
	for(var/obj/structure/spacevine/V in vines)
		if(!QDELETED(V))
			qdel(V)
	vines = null
	return ..()

/// A hardened vine across a one-wide corridor (it's dense), and a keen assistant with a toolbox: it cuts through.
/datum/bot_scenario/duty/vines/hardened
	name = "vines: a hardened vine across the corridor, an assistant with a toolbox cuts through"
	desc = "A hardened (dense) vine stands across a corridor and an assistant who's got a toolbox in its bag is on its way past. It cuts the vine down, a swing at a time."
	job = "Assistant"
	kit_hands = list(/obj/item/storage/toolbox/mechanical) //it doesn't fit a backpack: kit_backpack would drop it
	layout = list(
		"##########",
		"#B..1....#",
		"##########")
	time_limit = 75 SECONDS

/datum/bot_scenario/duty/vines/hardened/setup()
	..()
	for(var/obj/structure/spacevine/V in vines)
		V.density = TRUE

/datum/bot_scenario/duty/vines/hardened/post_spawn()
	..()
	brain.diligence = 0.9 //keen: not every assistant gets round to it


/// Nothing to cut with, and no business with the vines: it doesn't wander off at them and it doesn't fail.
/datum/bot_scenario/duty/vines/bare_handed
	name = "vines: a clerk with nothing to cut with leaves them be"
	desc = "A keen assistant with empty hands and an empty bag, and vines in the hall. There's nothing it can cut them with, so it goes on as it was: nothing's started, nothing's cut."
	job = "Assistant"
	kit_backpack = null
	time_limit = 30 SECONDS

/datum/bot_scenario/duty/vines/bare_handed/post_spawn()
	..()
	brain.diligence = 0.9

/datum/bot_scenario/duty/vines/bare_handed/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/obj/structure/spacevine/V in vines)
		if(QDELETED(V))
			fail_reason = "cut a vine with nothing to cut it with"
			return BOT_GYM_FAIL
	if("[brain.current_goal?.type]" == "/datum/bot_goal/cut_vines") //by name: a build without the duty has no such type
		fail_reason = "set off for the vines with nothing to cut them with"
		return BOT_GYM_FAIL
	return world.time >= start_time + 20 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// Steal objectives with a condition (objective_items.dm check_special_completion): goals/traitor.dm
// ---------------------------------------------------------------------------------------------

/// "Steal 28 moles of plasma (full tank)" asks for any tank, but it only counts with the plasma in it. The traitor's goal took the nearest
/// tank of any kind and called it done: in a generated-map batch one bagged five oxygen tanks in two minutes, and the objective stayed undone.
/datum/bot_scenario/duty/traitor/plasma_tank
	name = "traitor: after a tank of plasma it takes the full plasma tank, not the oxygen tanks nearer"
	desc = "The objective is 28 moles of plasma in a tank. Two oxygen tanks lie near, a full plasma tank further off. It takes the plasma one and none of the others."
	layout = list(
		"###############",
		"#B..O.O......P#",
		"###############")
	time_limit = 60 SECONDS

/datum/bot_scenario/duty/traitor/plasma_tank/setup()
	for(var/turf/T in markers["O"])
		place("O", new /obj/item/tank/internals/oxygen(T))
	for(var/turf/T in markers["P"])
		place("P", new /obj/item/tank/internals/plasma/full(T))

/datum/bot_scenario/duty/traitor/plasma_tank/proc/set_plasma_objective()
	var/datum/objective/steal/S = new //fills the list of what can be asked for
	S.owner = bot.mind
	for(var/datum/objective_item/I in GLOB.possible_items)
		if(I.targetitem == /obj/item/tank)
			S.targetinfo = I
	S.steal_target = /obj/item/tank
	S.explanation_text = "Steal [S.targetinfo?.name]"
	antag.objectives += S

/datum/bot_scenario/duty/traitor/plasma_tank/post_spawn()
	..()
	set_plasma_objective()

/datum/bot_scenario/duty/traitor/plasma_tank/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/obj/item/tank/T in bot.GetAllContents())
		if(!istype(T, /obj/item/tank/internals/plasma))
			fail_reason = "took [T] for a plasma objective"
			return BOT_GYM_FAIL
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/// And with only oxygen tanks about, it leaves them: nothing to take, and nothing in the bag after a minute.
/datum/bot_scenario/duty/traitor/plasma_tank/none
	name = "traitor: after a tank of plasma with only oxygen tanks about it takes none of them"
	desc = "The same objective and only oxygen tanks on the floor. It doesn't pocket one and call it done."
	layout = list(
		"##########",
		"#B..O.O..#",
		"##########")
	time_limit = 40 SECONDS

/datum/bot_scenario/duty/traitor/plasma_tank/none/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/obj/item/tank/T in bot.GetAllContents())
		fail_reason = "took [T] for a plasma objective"
		return BOT_GYM_FAIL
	return world.time >= start_time + 25 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/// "Steal the nuclear authentication disk" and the Captain has it in a pocket (where it's kept): the traitor can't walk up to it, so it
/// takes it off them. The steal goal only went for what lay about, and a traitor with this objective did nothing about it all shift.
/datum/bot_scenario/duty/traitor/disk_off_the_captain
	name = "traitor: after the disk the Captain's carrying, with the Captain alone, it puts them down and takes it"
	desc = "The objective is the nuclear disk and the Captain has it in a pocket, alone in the room. The traitor buys a sword, kills the Captain and takes the disk off the body."
	layout = list(
		"#########",
		"#B.....V#",
		"#########")
	var/mob/living/carbon/human/captain
	var/obj/item/disk/nuclear/disk

/datum/bot_scenario/duty/traitor/disk_off_the_captain/post_spawn()
	..()
	captain = stand_in(first_marker("V"), "Cap Tain")
	captain.mind_initialize()
	captain.mind.assigned_role = "Captain"
	disk = new(get_turf(captain))
	qdel(disk.GetComponent(/datum/component/stationloving)) //it would take itself back to the station, off the gym's z-level
	captain.equip_to_slot_or_del(disk, ITEM_SLOT_LPOCKET)
	var/datum/objective/steal/S = new //fills the list of what can be asked for
	S.owner = bot.mind
	for(var/datum/objective_item/I in GLOB.possible_items)
		if(I.targetitem == /obj/item/disk/nuclear)
			S.targetinfo = I
	S.steal_target = /obj/item/disk/nuclear
	S.explanation_text = "Steal [S.targetinfo?.name]"
	antag.objectives += S

/datum/bot_scenario/duty/traitor/disk_off_the_captain/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(captain) || captain.stat != DEAD)
		return BOT_GYM_PENDING
	return brain.find_carried_tool(/obj/item/disk/nuclear) ? BOT_GYM_PASS : BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// Midround events (bot_round_type.dm)
// ---------------------------------------------------------------------------------------------

/// An event wants players aboard (space vines 10) and counted only people with a client, so a round of bots and one person never had
/// one. The bot crew count now, in a live round: this switches the count on for the one check, and off again for the other.
/datum/bot_scenario/events_count
	name = "events: the bot crew count towards an event's minimum players"
	desc = "Space vines want ten players. With one fewer than that counted and the bot crew counting, the event can run; with them not counting, it can't."
	station_wide = TRUE
	job = "Assistant" //a station job is what counts as crew
	layout = list(
		"#####",
		"#B..#",
		"#####")
	time_limit = 20 SECONDS

/datum/bot_scenario/events_count/make_goal()
	return null //it's a check, not a walk

/datum/bot_scenario/events_count/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/datum/round_event_control/vines
	for(var/datum/round_event_control/E in SSevents.control)
		if(E.typepath == /datum/round_event/spacevine)
			vines = E
	if(!vines)
		fail_reason = "no space vine event"
		return BOT_GYM_FAIL
	var/few = vines.min_players - 1
	var/early = vines.earliest_start //events don't start for twenty minutes: not the question here
	vines.earliest_start = 0
	GLOB.vars["bot_events_count_test"] = FALSE
	var/without = vines.canSpawnEvent(few, "extended")
	GLOB.vars["bot_events_count_test"] = TRUE
	var/with = vines.canSpawnEvent(few, "extended")
	GLOB.vars["bot_events_count_test"] = null
	vines.earliest_start = early
	if(without)
		fail_reason = "ran short of players with the bots not counting"
		return BOT_GYM_FAIL
	if(!with)
		fail_reason = "the bot crew weren't counted as players"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/events_count/release_run()
	GLOB.vars["bot_events_count_test"] = null
	return ..()

// ---------------------------------------------------------------------------------------------
// A rogue vending machine (goals/anomalies.dm)
// ---------------------------------------------------------------------------------------------

/// The Brand Intelligence event's first machine has just shouted its marketing a few tiles away from an engineer. It says so on the radio and
/// smashes it with its toolbox, which ends the event. Nobody did anything about it: the machines got up as mimics and killed 17 of 33 crew.
/datum/bot_scenario/duty/rogue_machine
	name = "vending: an engineer who hears the rogue machine shout calls it in and smashes it"
	desc = "The machine the Brand Intelligence event began with shouts its marketing six tiles from an engineer with a toolbox. The engineer goes and smashes it down."
	job = "Station Engineer"
	kit_hands = list(/obj/item/storage/toolbox/mechanical)
	layout = list(
		"############",
		"#B.....M...#",
		"############")
	time_limit = 90 SECONDS
	var/obj/machinery/vending/cola/machine
	var/datum/round_event/brand_intelligence/event
	var/shouted = FALSE

/datum/bot_scenario/duty/rogue_machine/setup()
	duty_type = text2path("/datum/bot_duty/silence_machine") //by name: a build without the duty has none
	machine = new /obj/machinery/vending/cola(first_marker("M"))
	machine.shoot_inventory = TRUE
	event = new /datum/round_event/brand_intelligence(FALSE) //not running: it's only there to say which machine is the one
	event.originMachine = machine

/datum/bot_scenario/duty/rogue_machine/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!shouted && world.time >= start_time + 3 SECONDS)
		shouted = TRUE
		machine.speak("Consume!")
	return QDELETED(machine) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/rogue_machine/release_run()
	event?.kill()
	event = null
	if(!QDELETED(machine))
		qdel(machine)
	return ..()

/// An ordinary machine that shouts a slogan, as every machine does, is nobody's business.
/datum/bot_scenario/duty/rogue_machine/ordinary
	name = "vending: a machine shouting its ordinary slogan is left alone"
	desc = "The same engineer, the same machine, but it isn't the event's: it only says what vending machines say. The engineer leaves it."
	time_limit = 25 SECONDS

/datum/bot_scenario/duty/rogue_machine/ordinary/setup()
	..()
	event.originMachine = null //nothing's gone rogue

/datum/bot_scenario/duty/rogue_machine/ordinary/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!shouted && world.time >= start_time + 3 SECONDS)
		shouted = TRUE
		machine.speak("Buy something!")
	if(QDELETED(machine) || machine.obj_integrity < machine.max_integrity)
		fail_reason = "went for a machine that had done nothing"
		return BOT_GYM_FAIL
	return world.time >= start_time + 20 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/// A carp coming at an officer whose e-gun is on disable, as it starts: the officer's attacked, so it's the ordinary fight and not a
/// loose creature called in. A disabler does nothing to a carp: it puts the gun on kill. (Before, a hybrid taser's electrodes went at
/// vending machines that had got up as mimics, 21 shots of 31.)
/datum/bot_scenario/animal_fight
	name = "creatures: attacked by a carp with its e-gun on disable, an officer switches to kill"
	desc = "A carp that's bitten the officer, who has an energy gun on disable, stands (stunned) six tiles off. It puts the gun on its kill setting and shoots the carp dead."
	job = "Security Officer"
	kit_backpack = list(/obj/item/gun/energy/e_gun)
	layout = list(
		"############",
		"#B.....c...#",
		"############")
	time_limit = 60 SECONDS
	var/mob/living/simple_animal/hostile/carp/carp

/datum/bot_scenario/animal_fight/setup()
	carp = new(first_marker("c"))
	carp.Stun(100 SECONDS, ignore_canstun = TRUE) //it stays at range: this is about what the officer shoots it with, not a scrap up close

/datum/bot_scenario/animal_fight/post_spawn()
	..()
	brain.register_security()
	brain.on_attacked(carp, "bitten") //it's been bitten: the ordinary fight, not a creature called in

/datum/bot_scenario/animal_fight/make_goal()
	return null

/datum/bot_scenario/animal_fight/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(brain.attacker == carp)
		brain.last_hit_by_attacker = world.time //a stunned carp doesn't bite again: it's still the same fight
	if(!QDELETED(carp) && carp.stat != DEAD)
		return BOT_GYM_PENDING
	var/obj/item/gun/energy/e_gun/G = locate() in bot.GetAllContents()
	if(!G || brain.is_nonlethal_shot(G.ammo_type[G.select]))
		fail_reason = "beat it down with the gun still on disable"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/animal_fight/release_run()
	if(!QDELETED(carp))
		qdel(carp)
	return ..()
