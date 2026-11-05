// Bot Gym scenarios for human-like behaviour (bot_human.dm). Each one reproduces something that
// looked robotic in a real round's telemetry. Every scenario also fails on the forbidden tells
// (tool not in hand, teleported items, ...), see /datum/bot_scenario/var/forbidden_tells.

/datum/bot_scenario/jaws_from_backpack
	name = "jaws of life drawn from the backpack"
	desc = "A locked, powered airlock and no access. The jaws of life start in the backpack and must be drawn into the hand before prying (a real round used them off the belt 28 times)."
	layout = list(
		"#########",
		"#B..D..G#",
		"#########")
	kit_backpack = list(/obj/item/crowbar/power)

/datum/bot_scenario/jaws_from_backpack/setup()
	var/obj/machinery/door/airlock/A = first_placed("D")
	A.req_access = list(ACCESS_CAPTAIN)

/datum/bot_scenario/locker_take_only_gloves
	name = "locker: take the gloves, leave the toolbox"
	desc = "Sent for insulated gloves; the locker also holds a toolbox. A person takes what they came for (a real round's bot took the toolbox too)."
	layout = list(
		"#########",
		"#B...L..#",
		"#########")
	time_limit = 30 SECONDS

/datum/bot_scenario/locker_take_only_gloves/setup()
	var/obj/structure/closet/C = first_placed("L")
	new /obj/item/clothing/gloves/color/yellow(C)
	new /obj/item/storage/toolbox/electrical(C)

/datum/bot_scenario/locker_take_only_gloves/make_goal()
	return new /datum/bot_goal/acquire_tool(/obj/item/clothing/gloves/color/yellow)

/datum/bot_scenario/locker_take_only_gloves/check()
	if(!bot || QDELETED(bot) || bot.stat == DEAD)
		fail_reason = "bot died"
		return BOT_GYM_FAIL
	var/obj/item/storage/toolbox/T = locate() in bot.GetAllContents()
	if(T)
		fail_reason = "took the toolbox as well"
		return BOT_GYM_FAIL
	if(locate(/obj/item/clothing/gloves/color/yellow) in bot.GetAllContents())
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/three_airlocks
	name = "three airlocks in a row, human pace"
	desc = "Walk through three consecutive airlocks without stopping dead at each (a real round had 21 door stops) or freezing 3s+."
	layout = list(
		"###########",
		"#B.D.D.D.G#",
		"###########")
	time_limit = 20 SECONDS
	forbidden_tells = list("tool_not_in_hand", "item_teleport", "equip_without_holding", "remote_pickup", "not_facing_target", "idle_3s")

/datum/bot_scenario/puts_self_out
	name = "on fire: stop, drop and roll"
	desc = "A bot catches fire. It rolls on the floor until it's out, rather than walking on until it burns to death and lighting everyone it passes."
	layout = list(
		"#####",
		"#B..#",
		"#####")
	time_limit = 20 SECONDS

/datum/bot_scenario/puts_self_out/post_spawn()
	..()
	bot.adjust_fire_stacks(8)
	bot.IgniteMob()

/datum/bot_scenario/puts_self_out/issue_goal()
	return

/datum/bot_scenario/puts_self_out/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return bot.on_fire ? BOT_GYM_PENDING : BOT_GYM_PASS

/datum/bot_scenario/fights_back
	time_limit = 25 SECONDS
	var/mob/living/carbon/human/assailant

/datum/bot_scenario/fights_back/issue_goal()
	return

/datum/bot_scenario/fights_back/post_spawn()
	..()
	assailant = stand_in(first_marker("C"), "Casey Assailant")
	addtimer(CALLBACK(src, PROC_REF(start_fight)), 2 SECONDS)

/datum/bot_scenario/fights_back/proc/start_fight()
	log_combat(assailant, bot, "punched")

/datum/bot_scenario/fights_back/with_a_toolbox
	name = "fight: swings what's in its hand, not its fists"
	desc = "Attacked with a toolbox in hand, the bot hits back with the toolbox."
	layout = list(
		"######",
		"#BC..#",
		"######")
	var/obj/item/storage/toolbox/mechanical/box

/datum/bot_scenario/fights_back/with_a_toolbox/post_spawn()
	..()
	box = new(bot)
	bot.put_in_hands(box)

/datum/bot_scenario/fights_back/with_a_toolbox/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/line in transcript)
		if(findtext(line, "hitting [assailant] with"))
			return BOT_GYM_PASS
		if(findtext(line, "attacking [assailant]"))
			fail_reason = "punched them with a toolbox in its hand"
			return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/fights_back/runs_when_losing
	name = "fight: runs for it when it's losing"
	desc = "Badly hurt and attacked, the bot shouts for help and leaves the fight rather than standing and trading blows."
	layout = list(
		"######",
		"#BC..#",
		"######")

/datum/bot_scenario/fights_back/runs_when_losing/post_spawn()
	..()
	bot.adjustBruteLoss(90)

/datum/bot_scenario/fights_back/runs_when_losing/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/line in transcript)
		if(findtext(line, "disengaging from [assailant]: running for it"))
			return BOT_GYM_PASS
		if(findtext(line, "attacking [assailant]"))
			fail_reason = "stayed and fought at [bot.health] health"
			return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/// Plasma and oxygen on these tiles, and a light put to them.
/datum/bot_scenario/proc/start_fire(list/turf/open/tiles, plasma = 3)
	for(var/turf/open/T as anything in tiles)
		T.air.assert_gases(/datum/gas/plasma, /datum/gas/oxygen)
		T.air.moles[/datum/gas/plasma] = plasma
		T.air.moles[/datum/gas/oxygen] = 20
		T.air_update_turf()
		T.hotspot_expose(1000, 500)

/datum/bot_scenario/walks_out_of_the_flames
	name = "on fire in the flames: an engineer in its hardsuit walks out, then rolls"
	desc = "An engineer in the engineering hardsuit, which keeps out no heat, catches fire standing in a fire. It gets out of the flames and then puts itself out. One in a player's fire stood burning in the flames for fourteen seconds, went back in for an extinguisher, and died."
	layout = list(
		"##############################",
		"#............................#",
		"#.....................B......#",
		"#............................#",
		"##############################")
	job = "Station Engineer"
	time_limit = 40 SECONDS

/datum/bot_scenario/walks_out_of_the_flames/issue_goal()
	return

/datum/bot_scenario/walks_out_of_the_flames/post_spawn()
	..()
	brain.gym_scripted = FALSE //a scripted bot has no reflexes
	var/obj/item/clothing/suit/space/hardsuit/engine/suit = new(bot)
	bot.equip_to_slot_or_del(suit, ITEM_SLOT_OCLOTHING)
	suit.ToggleHelmet()
	var/turf/start = first_marker("B")
	start_fire(list(start, get_step(start, EAST), get_step(start, NORTH), get_step(start, SOUTH)), 2) //the fire's to one side, as a fire is
	bot.adjust_fire_stacks(8)
	bot.IgniteMob()

/datum/bot_scenario/walks_out_of_the_flames/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/turf/open/T = get_turf(bot)
	return (bot.on_fire || T.active_hotspot) ? BOT_GYM_PENDING : BOT_GYM_PASS

/datum/bot_scenario/firelock_on_a_fire
	name = "firelock shut on a fire: an engineer doesn't prise it open"
	desc = "The way to where it's going is through a shut firelock with a fire behind it. An engineer with a crowbar, and no heat protection, leaves it shut. One prised two open on its way into a burning engineering bay, and died in there."
	layout = list(
		"###########",
		"#B..F....G#",
		"###########")
	job = "Station Engineer"
	kit_hands = list(/obj/item/crowbar)
	time_limit = 15 SECONDS

/datum/bot_scenario/firelock_on_a_fire/post_spawn()
	..()
	keep_burning()

/datum/bot_scenario/firelock_on_a_fire/proc/keep_burning()
	var/turf/door = first_marker("F")
	var/list/turf/open/fire = list()
	for(var/turf/open/T in block(locate(door.x + 1, door.y, door.z), get_turf(first_marker("G"))))
		if(!T.active_hotspot)
			fire += T
	start_fire(fire, 5)

/datum/bot_scenario/firelock_on_a_fire/check()
	var/obj/machinery/door/firedoor/F = first_placed("F")
	if(QDELETED(F) || !F.density)
		fail_reason = "the firelock was opened on the fire"
		return BOT_GYM_FAIL
	if(bot_lost())
		return BOT_GYM_FAIL
	keep_burning()
	return world.time >= start_time + 12 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/// A banana peel on the way: stepped round, when it's seen (the chance is set to a sure thing here; a shift has it missed now and then).
/datum/bot_scenario/banana_peel
	name = "footing: a banana peel in the way is stepped round, not run on to"
	desc = "Straight down a corridor three wide with a peel in the middle of the way. It goes round it. Bots ran straight on to everything slippery, the clown's peels included."
	layout = list(
		"###########",
		"#.........#",
		"#B...p...G#",
		"#.........#",
		"###########")
	time_limit = 20 SECONDS
	var/slipped = FALSE

/datum/bot_scenario/banana_peel/setup()
	for(var/turf/T in markers["p"])
		place("p", new /obj/item/grown/bananapeel(T))

/datum/bot_scenario/banana_peel/post_spawn()
	brain.footing_attention = 100

/datum/bot_scenario/banana_peel/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!(bot.mobility_flags & MOBILITY_STAND))
		fail_reason = "slipped"
		return BOT_GYM_FAIL
	return get_turf(bot) == first_marker("G") ? BOT_GYM_PASS : BOT_GYM_PENDING

/// A wet floor right across the way: walked over, not run.
/datum/bot_scenario/banana_peel/wet_floor
	name = "footing: a wet floor right across the way is walked over, not run across"
	desc = "The floor's been mopped from wall to wall, so there's no way round. It walks it, as walking doesn't slip you on water."
	layout = list(
		"###########",
		"#B..yyy..G#",
		"###########")

/datum/bot_scenario/banana_peel/wet_floor/setup()
	for(var/turf/open/T in markers["y"])
		T.MakeSlippery(TURF_WET_WATER, 2 MINUTES)

/// A banana peel is litter: somebody out to keep the station nice picks it up and bins it, from beside it.
/datum/bot_scenario/duty/tidies_up/peel
	name = "footing: somebody tidying up bins a banana peel, picked up from beside it, not stepped on"
	desc = "A peel on the floor in front of somebody keeping the station nice. It's litter: picked up from the next tile and put in the bin. One in a hallway was stepped round 45 times in a shift and left there."
	layout = list(
		"#########",
		"#B..j..u#",
		"#########")

/datum/bot_scenario/duty/tidies_up/peel/setup()
	litter = new /obj/item/grown/bananapeel(first_marker("j"))
	place("j", litter)
	bin = new(first_marker("u"))
	place("u", bin)

/datum/bot_scenario/duty/tidies_up/peel/post_spawn()
	..()
	brain.footing_attention = 100 //seen for certain here; a shift has it missed now and then

/datum/bot_scenario/duty/tidies_up/peel/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!(bot.mobility_flags & MOBILITY_STAND))
		fail_reason = "slipped on it"
		return BOT_GYM_FAIL
	return ..()

/// Adrift in open space with nothing in reach to push off: something thrown the other way, and back on the push.
/datum/bot_scenario/adrift
	name = "space: adrift with nothing to push off, it throws something the other way and drifts back to the floor"
	desc = "Suited and breathing, but out in the open with no jetpack, too far from anything to push off. It throws a crayon away from the floor and rides the push back. An engineer drifted thirteen minutes that way and ran out of air."
	layout = list(
		"###########",
		"#..SSSSSSS#",
		"#..SSSSSSS#",
		"#B.SSSSSSS#",
		"#..SSSSSSS#",
		"#..SSSSSSS#",
		"###########")
	time_limit = 25 SECONDS

/datum/bot_scenario/adrift/setup()
	arena_area.has_gravity = FALSE //out in space there's none: the arena's own would let it just walk off the space tiles

/datum/bot_scenario/adrift/post_spawn()
	bot.equip_to_slot_or_del(new /obj/item/clothing/mask/breath(bot), ITEM_SLOT_MASK)
	bot.equip_to_slot_or_del(new /obj/item/clothing/suit/space/eva(bot), ITEM_SLOT_OCLOTHING)
	bot.equip_to_slot_or_del(new /obj/item/clothing/head/helmet/space/eva(bot), ITEM_SLOT_HEAD)
	var/obj/item/tank/internals/emergency_oxygen/T = new(bot)
	bot.equip_to_slot_or_del(T, ITEM_SLOT_SUITSTORE)
	bot.internal = T
	new /obj/item/toy/crayon/red(bot.back)
	bot.forceMove(locate(bot.x + 6, bot.y, bot.z)) //out in the middle of it, three tiles from anything

/datum/bot_scenario/adrift/make_goal()
	return null //the reflex is what's tested

/datum/bot_scenario/adrift/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return isspaceturf(get_turf(bot)) ? BOT_GYM_PENDING : BOT_GYM_PASS

/// Adrift with nothing it would part with: it calls for help, with where it is.
/datum/bot_scenario/adrift/empty_handed
	name = "space: adrift with nothing to throw, it calls for help with where it is"
	desc = "The same open space and no jetpack, and nothing on it it can do without: its ID, its tank and its clothes. It radios for help with its position."

/datum/bot_scenario/adrift/empty_handed/post_spawn()
	..()
	for(var/obj/item/I in bot.back)
		qdel(I) //nothing to throw: the crayon and anything else in the bag

/datum/bot_scenario/adrift/empty_handed/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return bot_transcript_said("calling for help") ? BOT_GYM_PASS : BOT_GYM_PENDING

/// On a jetpack with gas in it it never calls for one: an explorer flying to a ruin, between moves at the edge of the level, radioed
/// "Anybody with a jetpack?" with one on its back, and the CE went out into space looking for it.
/datum/bot_scenario/adrift/on_a_jetpack
	name = "space: on a jetpack and nothing to throw, it doesn't call for a jetpack"
	desc = "The same open space with nothing it would throw, but a jetpack on its back, on, with its stabilizers off. It never radios for help."
	time_limit = 20 SECONDS
	var/watch_until = 0

/datum/bot_scenario/adrift/on_a_jetpack/post_spawn()
	..()
	for(var/obj/item/I in bot.back)
		qdel(I)
	qdel(bot.back)
	var/obj/item/tank/jetpack/oxygen/J = new(bot)
	bot.equip_to_slot_or_del(J, ITEM_SLOT_BACK)
	J.turn_on(bot)
	J.stabilizers = FALSE
	watch_until = world.time + 10 SECONDS

/datum/bot_scenario/adrift/on_a_jetpack/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("calling for help"))
		fail_reason = "called for a jetpack with one on its back"
		return BOT_GYM_FAIL
	return world.time >= watch_until ? BOT_GYM_PASS : BOT_GYM_PENDING

/// Called for help, then got back in: it says so, so nobody goes out looking.
/datum/bot_scenario/adrift/empty_handed/back_in
	name = "space: called for help adrift, then back on the floor, it says it's made it back in"
	desc = "It calls for help with nothing to throw; then it's put back on the floor, and it radios that it's back and nobody need come. Sam called from space and was back in EVA a minute later without a word, while the CE searched space for him."
	var/moved_back = FALSE

/datum/bot_scenario/adrift/empty_handed/back_in/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!moved_back)
		if(bot_transcript_said("calling for help"))
			moved_back = TRUE
			log_line("it's put back on the floor")
			bot.forceMove(first_marker("B") || locate(bot.x - 6, bot.y, bot.z))
		return BOT_GYM_PENDING
	return bot_transcript_said("made it back in") ? BOT_GYM_PASS : BOT_GYM_PENDING

// Accidents (bot_witness.dm). The visitor throws a toolbox at a table (t) with the bot, or a bystander (Y), in the way.

/datum/bot_scenario/chat/accident_sorry
	name = "accident: hit by a toolbox thrown at a table and told sorry, it forgives and doesn't fight or call Security"
	desc = "A visitor throws a toolbox at the table behind the bot; it hits the bot on the way. \"Ow! Watch it!\", then the visitor says sorry and the bot forgives them: no fight, no call to Security. The user's sword, thrown at a table, hit the janitor beside it, who fought them through every sorry."
	time_limit = 20 SECONDS
	layout = list(
		"#########",
		"#C.B.t..#",
		"#########")
	var/obj/item/storage/toolbox/box
	var/say_sorry = TRUE
	var/thrown_at = 0

/datum/bot_scenario/chat/accident_sorry/post_spawn()
	..()
	box = new(visitor)
	visitor.put_in_active_hand(box)
	addtimer(CALLBACK(src, PROC_REF(throw_it)), 2 SECONDS)
	if(say_sorry)
		addtimer(CALLBACK(src, PROC_REF(visitor_says), "Sorry! That was meant for the table."), 6 SECONDS)

/datum/bot_scenario/chat/accident_sorry/proc/throw_it()
	if(QDELETED(visitor) || QDELETED(box))
		return
	log_line("visitor throws the toolbox at the table")
	thrown_at = world.time
	visitor.throw_item(first_placed("t"))

/datum/bot_scenario/chat/accident_sorry/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(brain.attacker == visitor)
		fail_reason = "it fought the visitor"
		return BOT_GYM_FAIL
	if(bot_transcript_said("Security"))
		fail_reason = "it called Security"
		return BOT_GYM_FAIL
	if(thrown_at && world.time > thrown_at + 3 SECONDS && !bot.getBruteLoss())
		fail_reason = "the throw never hit it (the scenario's at fault)"
		return BOT_GYM_FAIL
	return bot_transcript_said("forgave") ? BOT_GYM_PASS : BOT_GYM_PENDING

/// No sorry: in the end it's taken as the attack it looked like
/datum/bot_scenario/chat/accident_sorry/never_said
	name = "accident: hit by a toolbox thrown at a table and never told sorry, it holds off a while, then takes it as an attack"
	desc = "The same throw, and no sorry. It doesn't fight or report it straight away, but when the time to say sorry is up it does."
	time_limit = 50 SECONDS
	say_sorry = FALSE

/datum/bot_scenario/chat/accident_sorry/never_said/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(thrown_at && world.time > thrown_at + 3 SECONDS && !bot.getBruteLoss())
		fail_reason = "the throw never hit it (the scenario's at fault)"
		return BOT_GYM_FAIL
	if(brain.attacker == visitor || bot_transcript_said("Security"))
		if(world.time < thrown_at + 15 SECONDS)
			fail_reason = "it went for them straight away, with no time to say sorry"
			return BOT_GYM_FAIL
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/// Seen from across the room: the bystander hit, the sorry said, and nobody's called
/datum/bot_scenario/chat/accident_witnessed
	name = "accident: sees somebody hit by a toolbox thrown at a table, then sorry said, it doesn't call Security or step in"
	desc = "A doctor watches a visitor throw a toolbox at a table and hit the bystander in the way, then say sorry. It doesn't radio Security or go for the visitor. A doctor who saw the user's sword hit the janitor called Security and fought them for three minutes."
	job = "Medical Doctor"
	time_limit = 25 SECONDS
	layout = list(
		"#########",
		"#C.Y.t..#",
		"#...B...#",
		"#########")
	var/obj/item/storage/toolbox/box
	var/mob/living/carbon/human/bystander
	var/thrown_at = 0

/datum/bot_scenario/chat/accident_witnessed/post_spawn()
	..()
	bystander = stand_in(first_marker("Y"), "Bailey Bystander")
	box = new(visitor)
	visitor.put_in_active_hand(box)
	addtimer(CALLBACK(src, PROC_REF(throw_it)), 2 SECONDS)
	addtimer(CALLBACK(src, PROC_REF(visitor_says), "Oh no, sorry! That was meant for the table."), 6 SECONDS)

/datum/bot_scenario/chat/accident_witnessed/proc/throw_it()
	if(QDELETED(visitor) || QDELETED(box))
		return
	log_line("visitor throws the toolbox at the table")
	thrown_at = world.time
	visitor.throw_item(first_placed("t"))

/datum/bot_scenario/chat/accident_witnessed/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(brain.attacker == visitor)
		fail_reason = "it went for the visitor"
		return BOT_GYM_FAIL
	if(bot_transcript_said("Security"))
		fail_reason = "it called Security"
		return BOT_GYM_FAIL
	if(thrown_at && world.time > thrown_at + 3 SECONDS && !bystander.getBruteLoss())
		fail_reason = "the throw never hit the bystander (the scenario's at fault)"
		return BOT_GYM_FAIL
	return (thrown_at && world.time > thrown_at + 18 SECONDS) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/chat/accident_witnessed/release_run()
	if(bystander)
		qdel(bystander)
	return ..()

// Uncuffing Security's prisoner (bot_witness.dm)

/datum/bot_scenario/chat/uncuffing
	name = "uncuffing: a bystander objects and radios it in, and drops it at sorry and the cuffs back on"
	desc = "A visitor takes the cuffs off a prisoner Security wants. A doctor watching says that's Security's prisoner and radios it in; the visitor says sorry and puts the cuffs back on, and the doctor says never mind, and the charge comes off. The user uncuffed a traitor not knowing he was a prisoner."
	job = "Medical Doctor"
	time_limit = 45 SECONDS
	layout = list(
		"#########",
		"#C.Y..B.#",
		"#########")
	var/mob/living/carbon/human/prisoner
	var/stage = 0

/datum/bot_scenario/chat/uncuffing/post_spawn()
	..()
	prisoner = stand_in(first_marker("Y"), "Pat Prisoner")
	prisoner.handcuffed = new /obj/item/restraints/handcuffs(prisoner)
	prisoner.update_handcuffed()
	var/datum/bot_wanted/W = new
	W.crime = "Theft"
	W.severity = BOT_CRIME_MINOR
	GLOB.bot_security_wanted[WEAKREF(prisoner)] = W
	visitor.forceMove(get_step(prisoner, WEST)) //within reach of the cuffs
	visitor.setDir(get_dir(visitor, prisoner))
	addtimer(CALLBACK(src, PROC_REF(take_cuffs_off)), 2 SECONDS)

/datum/bot_scenario/chat/uncuffing/proc/take_cuffs_off()
	if(QDELETED(visitor) || QDELETED(prisoner) || !prisoner.handcuffed)
		return
	log_line("visitor takes the prisoner's cuffs off")
	INVOKE_ASYNC(visitor, TYPE_PROC_REF(/mob, stripPanelUnequip), prisoner.handcuffed, prisoner, ITEM_SLOT_HANDCUFFED)

/datum/bot_scenario/chat/uncuffing/proc/put_them_back()
	var/obj/item/restraints/handcuffs/cuffs = locate() in visitor.held_items
	if(!cuffs)
		cuffs = locate() in get_turf(visitor)
		if(cuffs)
			visitor.put_in_hands(cuffs)
	if(!cuffs)
		log_line("the visitor's lost the cuffs")
		return
	visitor_says("Oh, sorry! I didn't know they were a prisoner.")
	log_line("visitor puts the cuffs back on")
	INVOKE_ASYNC(cuffs, TYPE_PROC_REF(/obj/item, attack), prisoner, visitor)

/datum/bot_scenario/chat/uncuffing/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(brain.attacker == visitor)
		fail_reason = "it went for the visitor"
		return BOT_GYM_FAIL
	switch(stage)
		if(0)
			if(prisoner.handcuffed || world.time < start_time + 4 SECONDS)
				return BOT_GYM_PENDING
			stage = 1
		if(1)
			if(bot_transcript_said("Security's prisoner") && bot_transcript_said("called in")) //the charge goes on record only with an officer about
				stage = 2
				addtimer(CALLBACK(src, PROC_REF(put_them_back)), 2 SECONDS)
			else if(world.time > start_time + 15 SECONDS)
				fail_reason = "nobody objected or reported it"
				return BOT_GYM_FAIL
		if(2)
			if(prisoner.handcuffed && !bot_get_wanted_entry(visitor) && bot_transcript_said("cuffs back on and said sorry"))
				return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/chat/uncuffing/release_run()
	GLOB.bot_security_wanted -= WEAKREF(prisoner)
	GLOB.bot_security_wanted -= WEAKREF(visitor)
	if(prisoner)
		qdel(prisoner)
	return ..()

/// It's the prisoner: let out of its cuffs by somebody who isn't Security, it doesn't take it as being set on, and waits
/datum/bot_scenario/chat/uncuffed_prisoner
	name = "uncuffing: a law-abiding prisoner uncuffed by somebody who isn't Security doesn't fight them, and waits for Security"
	desc = "The bot is in cuffs and wanted. A visitor takes the cuffs off. It doesn't treat that as an attack: it says it'll wait for Security, and doesn't go for them."
	time_limit = 20 SECONDS
	layout = list(
		"#######",
		"#C.B..#",
		"#######")

/datum/bot_scenario/chat/uncuffed_prisoner/post_spawn()
	..()
	bot.handcuffed = new /obj/item/restraints/handcuffs(bot)
	bot.update_handcuffed()
	var/datum/bot_wanted/W = new
	W.crime = "Theft"
	W.severity = BOT_CRIME_MINOR
	GLOB.bot_security_wanted[WEAKREF(bot)] = W
	visitor.forceMove(get_step(bot, WEST))
	addtimer(CALLBACK(src, PROC_REF(take_cuffs_off)), 2 SECONDS)

/datum/bot_scenario/chat/uncuffed_prisoner/proc/take_cuffs_off()
	if(QDELETED(visitor) || !bot.handcuffed)
		return
	log_line("visitor takes the bot's cuffs off")
	INVOKE_ASYNC(visitor, TYPE_PROC_REF(/mob, stripPanelUnequip), bot.handcuffed, bot, ITEM_SLOT_HANDCUFFED)

/datum/bot_scenario/chat/uncuffed_prisoner/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(brain.attacker == visitor)
		fail_reason = "it went for the visitor"
		return BOT_GYM_FAIL
	if(bot.handcuffed || world.time < start_time + 6 SECONDS)
		return BOT_GYM_PENDING
	return bot_transcript_said("wait") ? BOT_GYM_PASS : (world.time > start_time + 15 SECONDS ? BOT_GYM_FAIL : BOT_GYM_PENDING)

/datum/bot_scenario/chat/uncuffed_prisoner/release_run()
	GLOB.bot_security_wanted -= WEAKREF(bot)
	GLOB.bot_security_wanted -= WEAKREF(visitor)
	return ..()
