// Gym scenarios for the bot behaviour fixes of 2026-11-12, from the 12-shift batch bugs1112base. Each fails on the code before its fix
// and passes after (tools/bot_gym/ab_gym.sh). Anything only a fix adds is reached by name (GLOB.vars, text2path, call()), so the
// "before" build compiles too.

/datum/bot_scenario/fixes1112

// ---------------------------------------------------------------------------------------------
// Kitchen (fixes 2026-11-12): the cook with its hands and bag full, its own counter, the cold room, and tools taken in passing
// ---------------------------------------------------------------------------------------------

/// Flashlights in both pockets and a fannypack of three on the belt: with a full bag, nowhere left to put anything away
/// (as /datum/bot_scenario/hands_full_of_tools/post_spawn(), scenarios_crafting.dm).
/datum/bot_scenario/fixes1112/proc/kitchen_fill_pockets_and_belt()
	for(var/slot in list(ITEM_SLOT_LPOCKET, ITEM_SLOT_RPOCKET))
		if(!bot.get_item_by_slot(slot))
			bot.equip_to_slot_or_del(new /obj/item/flashlight(bot), slot)
	if(!bot.get_item_by_slot(ITEM_SLOT_BELT))
		bot.equip_to_slot_or_del(new /obj/item/storage/belt/fannypack(bot), ITEM_SLOT_BELT)
	var/obj/item/storage/belt/fannypack/F = bot.get_item_by_slot(ITEM_SLOT_BELT)
	if(istype(F))
		for(var/i in 1 to 3)
			new /obj/item/flashlight(F)

// A tool beside the way, with both hands and the bag full (grab_passing_tools(), bot_items.dm)

/datum/bot_scenario/fixes1112/errand_kept_in_passing
	name = "items: hands and bag full on an errand, it keeps the ear of corn rather than take a crowbar it passes"
	desc = "A welder in one hand, an ear of corn in the other, the bag, pockets and belt full, and a crowbar beside the way. The crowbar is left where it lies. Batch 2026-11-12: a cook set its crowbar down to pick up an ear of corn, set the corn down to take the crowbar back in passing on the next step, got to the microwave with nothing to put in it, and gave up the dish 20 times in one shift (Drew Halvorsen, run2)."
	time_limit = 20 SECONDS
	kit_hands = list(/obj/item/weldingtool, /obj/item/reagent_containers/food/snacks/grown/corn)
	kit_backpack = list(/obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher)
	layout = list(
		"#########",
		"#B.....G#",
		"#...c...#",
		"#########")

/datum/bot_scenario/fixes1112/errand_kept_in_passing/post_spawn()
	..()
	kitchen_fill_pockets_and_belt()

/datum/bot_scenario/fixes1112/errand_kept_in_passing/check_success_conditions()
	if(!(locate(/obj/item/reagent_containers/food/snacks/grown/corn) in bot.held_items))
		return "put the corn down for the crowbar it passed"
	if(bot_transcript_said("setting the ear of corn down"))
		return "set the corn down on the way"
	var/obj/item/crowbar/C = first_placed("c")
	if(QDELETED(C) || C.loc != first_marker("c"))
		return "took the crowbar with nowhere to put it"
	return null

// The cook's own counter and stock, on a stroll (find_item_goal(), bot_items.dm; is_kitchen_stock(), goals/cook.dm)

/datum/bot_scenario/fixes1112/kitchen_stock_left
	name = "cook: on a stroll it leaves the kitchen's dishes and stock where they are, and still picks up a crowbar"
	desc = "A boiled egg and a salt shaker on the kitchen table and a potato on the floor: the cook's stroll goes for none of them. An Assistant's would, and the cook's still goes for a crowbar. Batch 2026-11-12: cooks took their own dishes back off the counter 82 times, often within a second of setting them out (Jean Kovac run5, Pat Holloway run10), and the kitchen's milk, condiments and drinks about 105 times more."
	job = "Cook"
	time_limit = 10 SECONDS
	layout = list(
		"########",
		"#B.toz.#",
		"########")

/datum/bot_scenario/fixes1112/kitchen_stock_left/setup()
	var/turf/table = first_marker("t")
	place("e", new /obj/item/reagent_containers/food/snacks/boiledegg(table))
	place("s", new /obj/item/reagent_containers/food/condiment/saltshaker(table))
	place("o", new /obj/item/reagent_containers/food/snacks/grown/potato(first_marker("o")))

/// No errand. A scripted bot doesn't stroll, so the stroll's own look round (find_item_goal()) is asked directly.
/datum/bot_scenario/fixes1112/kitchen_stock_left/issue_goal()
	return

/datum/bot_scenario/fixes1112/kitchen_stock_left/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/atom/A = brain.find_item_goal()
	log_line("the cook looks round its kitchen: [A || "nothing it wants"]")
	if(A)
		fail_reason = "went for [A] in its own kitchen"
		return BOT_GYM_FAIL
	// Anybody else still takes food that's lying about
	bot.mind.assigned_role = "Assistant"
	A = brain.find_item_goal()
	bot.mind.assigned_role = "Cook"
	log_line("an Assistant in its place looks round: [A || "nothing it wants"]")
	if(!istype(A, /obj/item/reagent_containers/food))
		fail_reason = "an Assistant left the food as well ([A || "nothing"])"
		return BOT_GYM_FAIL
	// And a tool in the kitchen is still worth picking up
	var/obj/item/crowbar/C = place("z", new /obj/item/crowbar(first_marker("z")))
	A = brain.find_item_goal()
	log_line("with a crowbar on the floor: [A || "nothing it wants"]")
	if(A != C)
		fail_reason = "walked past the crowbar too ([A || "nothing"])"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

// The cold room isn't somewhere to stroll to (is_wanderable_turf(), bot_brain.dm)

/datum/bot_scenario/fixes1112/cold_room_no_stroll
	name = "cold room: nobody strolls into the freezer, or to the spot behind its delivery flaps"
	desc = "Past the door the air is the kitchen cold room's, -80 C and otherwise fine, and on this side a tile behind plastic flaps. Neither is picked to stroll to; the cold room is still somewhere a cook may go for meat. Batch 2026-11-12: 36 strolls into the MetaStation cold room in six shifts ended \"can't breathe here - getting out\", and the room was kept out of for three minutes after, so the next fetch for meat found no way to the cold room floor (Morgan Vance, run12)."
	job = "Cook"
	time_limit = 10 SECONDS
	layout = list(
		"##########",
		"#B...D..G#",
		"##########")

/datum/bot_scenario/fixes1112/cold_room_no_stroll/setup()
	var/turf/door = first_marker("D")
	for(var/turf/open/floor/F in range(10, door))
		if(F.x > door.x && F.y == door.y && get_area(F) == arena_area)
			F.air.parse_gas_string(KITCHEN_COLDROOM_ATMOS)
			F.update_visuals()
			SSair.add_to_active(F)
	place("f", new /obj/structure/plasticflaps/opaque(get_step(get_step(first_marker("B"), EAST), EAST)))

/// No errand: where it would stroll to is asked directly (is_wanderable_turf(), pick_local_destination()).
/datum/bot_scenario/fixes1112/cold_room_no_stroll/issue_goal()
	return

/datum/bot_scenario/fixes1112/cold_room_no_stroll/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/turf/door = first_marker("D")
	var/turf/cold = first_marker("G")
	var/turf/warm = get_step(first_marker("B"), EAST)
	var/turf/behind_flaps = get_step(warm, EAST)
	if(!brain.turf_air_just_cold(cold))
		fail_reason = "the floor past the door isn't cold room air, so this shows nothing"
		return BOT_GYM_FAIL
	if(!brain.is_wanderable_turf(warm))
		fail_reason = "won't stroll to the warm floor either"
		return BOT_GYM_FAIL
	if(brain.in_bad_air(cold))
		fail_reason = "counts the cold room as air it can't go into, so the meat's out of reach"
		return BOT_GYM_FAIL
	if(brain.is_wanderable_turf(cold))
		fail_reason = "would stroll into the cold room"
		return BOT_GYM_FAIL
	if(brain.is_wanderable_turf(behind_flaps))
		fail_reason = "would stroll to a spot behind plastic flaps"
		return BOT_GYM_FAIL
	for(var/i in 1 to 40)
		var/turf/T = brain.pick_local_destination()
		if(T && (T == behind_flaps || T.x > door.x))
			fail_reason = "picked [T] [bot_coord(T)] to stroll to"
			return BOT_GYM_FAIL
	return BOT_GYM_PASS

// A cook on its own round, as /datum/bot_scenario/duty/cook (scenarios_cook.dm). Layout letters: u a microwave, p a food processor,
// R the produce smartfridge, o a loose potato, t the serving table.

/datum/bot_scenario/fixes1112/kitchen_duty
	job = "Cook"
	time_limit = 120 SECONDS
	max_goal_attempts = 20
	var/dish_type = /obj/item/reagent_containers/food/snacks/tatortot
	/// What the smartfridge starts with.
	var/list/fridge_stock

/datum/bot_scenario/fixes1112/kitchen_duty/setup()
	for(var/turf/T in markers["u"])
		place("u", new /obj/machinery/microwave(T))
	for(var/turf/T in markers["p"])
		place("p", new /obj/machinery/processor(T))
	for(var/turf/T in markers["o"])
		place("o", new /obj/item/reagent_containers/food/snacks/grown/potato(T))
	for(var/turf/T in markers["R"])
		var/obj/machinery/smartfridge/fridge = new(T)
		for(var/path in fridge_stock)
			new path(fridge)
		fridge.update_icon()
		place("R", fridge)

/datum/bot_scenario/fixes1112/kitchen_duty/post_spawn()
	..()
	give_job_id(list(ACCESS_KITCHEN))
	kitchen_fill_pockets_and_belt()

/// The cooking duty, asked once a second while the bot is idle (as /datum/bot_scenario/duty/issue_goal()).
/datum/bot_scenario/fixes1112/kitchen_duty/issue_goal()
	var/datum/bot_duty/D = bot_duty_of(/datum/bot_duty/cook)
	if(D && D.try_start(brain))
		goal_attempts++
		log_line("cooking: started on [brain.current_goal ? brain.current_goal.type : "it"] (attempt [goal_attempts]/[max_goal_attempts])")

/datum/bot_scenario/fixes1112/kitchen_duty/proc/served()
	. = 0
	for(var/turf/T in markers["t"])
		for(var/obj/item/I in T)
			if(istype(I, dish_type))
				.++

// Plates in its hands go out before the one in its bag (serve_dishes, goals/cook.dm)

/datum/bot_scenario/fixes1112/kitchen_duty/serve_hands_first
	name = "cook: bag full, it puts the plates in its hands out before the one in its bag"
	desc = "Two potatoes in its hands and one in a bag that's otherwise full: three tater tots come out, one goes in the bag to free a hand, and all three go out on the counter without a plate set down at its feet. Batch 2026-11-12: 16 serves set the two plates in hand down by the counter to draw the one in the bag, and put out one plate (Jordan Blake, run3 and run11)."
	layout = list(
		"###########",
		"#..p...t..#",
		"#B........#",
		"###########")
	kit_hands = list(/obj/item/reagent_containers/food/snacks/grown/potato, /obj/item/reagent_containers/food/snacks/grown/potato)
	// 6 x 3 + 2 x 1 + 1: full, and once the potato's out, room for one tater tot
	kit_backpack = list(/obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher,
		/obj/item/pen, /obj/item/pen, /obj/item/reagent_containers/food/snacks/grown/potato)

/datum/bot_scenario/fixes1112/kitchen_duty/serve_hands_first/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("setting the tator tot down"))
		fail_reason = "set a plate down at the counter to get one out of its bag"
		return BOT_GYM_FAIL
	if(bot_transcript_said("put 1 tater tots out") || bot_transcript_said("put 2 tater tots out"))
		fail_reason = "put out fewer than it made"
		return BOT_GYM_FAIL
	return (served() >= 3 && bot_transcript_said("put 3 tater tots out")) ? BOT_GYM_PASS : BOT_GYM_PENDING

// The smartfridge with both hands and the bag full (take_ingredient, goals/cook.dm)

/datum/bot_scenario/fixes1112/kitchen_duty/fridge_full_hands
	name = "cook: at the smartfridge with its hands and bag full, it still takes a potato out and makes tater tots"
	desc = "A rolling pin and a glass in its hands, the bag, pockets and belt full. The rolling pin goes down for a moment, one potato comes out into the hand, and a plate of tater tots goes out. Batch 2026-11-12: 55 trips to the smartfridge were given up this way, the produce tipped onto the floor and the fridge written off for three minutes each time (Jordan Blake, run3)."
	layout = list(
		"###########",
		"#R.p...t..#",
		"#B........#",
		"###########")
	kit_hands = list(/obj/item/kitchen/rollingpin, /obj/item/reagent_containers/food/drinks/drinkingglass)
	kit_backpack = list(/obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher)
	fridge_stock = list(/obj/item/reagent_containers/food/snacks/grown/potato, /obj/item/reagent_containers/food/snacks/grown/potato, /obj/item/reagent_containers/food/snacks/grown/potato)

/datum/bot_scenario/fixes1112/kitchen_duty/fridge_full_hands/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/machinery/smartfridge/fridge = first_placed("R")
	if(bot_transcript_said("giving up on /datum/bot_goal/fetch_ingredient") || (fridge && LAZYACCESS(brain.kitchen_blocked, fridge)))
		fail_reason = "gave the smartfridge up with its hands full"
		return BOT_GYM_FAIL
	for(var/char in markers)
		for(var/turf/T in markers[char])
			if(locate(/obj/item/reagent_containers/food/snacks/grown/potato) in T)
				fail_reason = "the smartfridge's potato went on the floor"
				return BOT_GYM_FAIL
	return served() >= 1 ? BOT_GYM_PASS : BOT_GYM_PENDING

// A batch of what it can carry (gather_ingredients, goals/cook.dm)

/datum/bot_scenario/fixes1112/kitchen_duty/bag_full_loose_potatoes
	name = "cook: bag full, it makes a batch of the two potatoes it can carry instead of swapping potatoes at its feet"
	desc = "Three loose potatoes, empty hands, and the bag, pockets and belt full. It takes two, one in each hand, and cooks those, rather than set one down to pick up the third. Batch 2026-11-12: a cook set the same two ears of corn down and picked them up five times running (Morgan Vance, run12)."
	layout = list(
		"###########",
		"#..p...t..#",
		"#B.ooo....#",
		"###########")
	kit_backpack = list(/obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher)

/datum/bot_scenario/fixes1112/kitchen_duty/bag_full_loose_potatoes/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("setting the potato down for a moment"))
		fail_reason = "set one potato down to pick up the next"
		return BOT_GYM_FAIL
	return served() >= 2 ? BOT_GYM_PASS : BOT_GYM_PENDING

// <<< medical_scenarios.dm
// ---------------------------------------------------------------------------------------------
// Medical (fixes 2026-11-12): a doctor who walks to where a patient was and gives them up there, every doctor going for the one patient,
// a chemist promising pills it can't bring, and a chemist with a full bag setting the brew's beaker down for its next part.
// ---------------------------------------------------------------------------------------------

/// A doctor and a stand-in patient with 30 brute, as /datum/bot_scenario/patient (scenarios_medical.dm). One try: a goal issued again
/// would hide the give-up these are after.
/datum/bot_scenario/fixes1112/med_patient
	job = "Medical Doctor"
	time_limit = 60 SECONDS
	max_goal_attempts = 1
	var/mob/living/carbon/human/patient

/datum/bot_scenario/fixes1112/med_patient/post_spawn()
	patient = stand_in(first_marker("C"), "Pat Patient")
	patient.apply_damage(30, BRUTE, BODY_ZONE_CHEST)

/datum/bot_scenario/fixes1112/med_patient/make_goal()
	return new /datum/bot_goal/treat_patient()

/datum/bot_scenario/fixes1112/med_patient/proc/patched_up()
	return patient.getBruteLoss() <= 10 && patient.getFireLoss() <= 10

// Layout letter k: a brute kit (styptic patches), there from the start so it counts as the arena's own.
/datum/bot_scenario/fixes1112/med_patient/kit_back
	name = "doctor: back with a kit from eighteen tiles off, it goes back to the patient"
	desc = "Beside a patient with nothing to treat them with, the doctor fetches the brute kit from the far end of the room, and takes the treatment up again over there, eighteen tiles from them. It gave them up on the spot: 14 of the 59 'couldn't get beside' in bugs1112base came straight after a kit run (run1 Emery Haldane, Parker Osei 49 tiles off). It goes back over and patches them up."
	layout = list(
		"######################",
		"#k.................CB#",
		"######################")

/datum/bot_scenario/fixes1112/med_patient/kit_back/setup()
	for(var/turf/T in markers["k"])
		place("k", new /obj/item/storage/firstaid/brute(T))

/datum/bot_scenario/fixes1112/med_patient/kit_back/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("couldn't get beside") || bot_transcript_said("nothing reachable to restock with"))
		fail_reason = "gave the patient up from where the kit was"
		return BOT_GYM_FAIL
	if(!patched_up())
		return BOT_GYM_PENDING
	if(!bot_transcript_said("going to restock") || !bot_transcript_said("going after them"))
		fail_reason = "patched them up without the kit run and the walk back that this is about"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// The same kit, emptied as the doctor sets off for it: it comes back with nothing to treat them with.
/datum/bot_scenario/fixes1112/med_patient/kit_empty
	name = "doctor: back with an empty kit, it doesn't walk back to the patient with nothing"
	desc = "As above, but the kit turns out to be empty. The doctor says it's out of supplies where it stands, and doesn't walk back over (or radio that it's on its way) with nothing to put on them: 2 of the 14 kit runs in bugs1112base came back empty-handed (run1 Emery Haldane, run8 Sam Delacroix)."
	layout = list(
		"######################",
		"#k.................CB#",
		"######################")
	time_limit = 40 SECONDS
	var/emptied = FALSE

/datum/bot_scenario/fixes1112/med_patient/kit_empty/setup()
	for(var/turf/T in markers["k"])
		place("k", new /obj/item/storage/firstaid/brute(T))

/datum/bot_scenario/fixes1112/med_patient/kit_empty/post_spawn()
	..()
	addtimer(CALLBACK(src, PROC_REF(watch_fetch)), 1)

/// The moment it sets off for the kit, what's in it goes.
/datum/bot_scenario/fixes1112/med_patient/kit_empty/proc/watch_fetch()
	if(emptied || result != BOT_GYM_PENDING || QDELETED(brain))
		return
	var/obj/item/storage/firstaid/kit = istype(brain.current_goal, /datum/bot_goal/acquire_item_type) ? brain.current_goal.target : null
	if(istype(kit))
		emptied = TRUE
		for(var/obj/item/I in kit.contents.Copy())
			qdel(I)
		log_line("the kit it's gone for turns out to be empty")
		return
	addtimer(CALLBACK(src, PROC_REF(watch_fetch)), 1)

/datum/bot_scenario/fixes1112/med_patient/kit_empty/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("going after them"))
		fail_reason = "set off back to the patient with nothing to treat them with"
		return BOT_GYM_FAIL
	if(bot_transcript_said("couldn't get beside"))
		fail_reason = "gave them up for being far off, not for having nothing to treat them with"
		return BOT_GYM_FAIL
	if(!emptied || !bot_transcript_said("nothing reachable to restock with"))
		return BOT_GYM_PENDING
	return BOT_GYM_PASS

// Layout letter j: where the patient has got to by the time the doctor arrives.
/datum/bot_scenario/fixes1112/med_patient/walked_far
	name = "doctor: a patient twenty tiles on by the time it gets there, it goes after them"
	desc = "The walk is to where the patient stood when the doctor set out, and they're off on an errand of their own: twenty tiles on by the time it gets there. It gave them up on the spot, 44 of the 59 'couldn't get beside' in bugs1112base (run1 Emery Haldane after Riley Osei, 21 tiles; run11 Morgan Vance after Blake Ferreira, 50). It goes on after them and patches them up. The patient is moved when the doctor is four tiles off, so the run doesn't hang on how fast either walks."
	layout = list(
		"###########################################",
		"#B...................C...................j#",
		"###########################################")
	kit_backpack = list(/obj/item/stack/medical/bruise_pack, /obj/item/stack/medical/ointment)
	var/moved = FALSE

/datum/bot_scenario/fixes1112/med_patient/walked_far/post_spawn()
	..()
	addtimer(CALLBACK(src, PROC_REF(watch_doctor)), 1)

/datum/bot_scenario/fixes1112/med_patient/walked_far/proc/watch_doctor()
	if(moved || result != BOT_GYM_PENDING || QDELETED(patient) || QDELETED(bot))
		return
	var/turf/stood = first_marker("C")
	var/turf/far_end = first_marker("j")
	if(!stood || !far_end)
		return
	if(get_dist(bot, stood) <= 4)
		moved = TRUE
		log_line("patient: off to the far end, twenty tiles on, as the doctor comes up")
		patient.forceMove(far_end)
		return
	addtimer(CALLBACK(src, PROC_REF(watch_doctor)), 1)

/datum/bot_scenario/fixes1112/med_patient/walked_far/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("couldn't get beside"))
		fail_reason = "gave them up where they'd been standing"
		return BOT_GYM_FAIL
	if(!patched_up())
		return BOT_GYM_PENDING
	if(!moved || !bot_transcript_said("going after them"))
		fail_reason = "patched them up without their having walked on"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

// Layout letters s: a second patient, O: another doctor, already on its way to the first.
/datum/bot_scenario/fixes1112/med_patient/colleague
	name = "doctor: a patient a colleague is already seeing to, it takes the next worst off"
	desc = "Pat is worse off and nearer, but Col League, another doctor, is already on the way to Pat. The doctor sees to Sam instead. Every doctor on shift went for the same worst-off patient: 63 of the 274 treatments in bugs1112base were a second or third doctor setting out for somebody a colleague had (run7 Corey Ishikawa and Devon Whitfield on Val Castillo), and 45 of them got there to find nothing to do."
	layout = list(
		"#############",
		"#B..C..s..O.#",
		"#...........#",
		"#############")
	kit_backpack = list(/obj/item/stack/medical/bruise_pack)
	time_limit = 30 SECONDS
	var/mob/living/carbon/human/second
	var/mob/living/carbon/human/colleague

/datum/bot_scenario/fixes1112/med_patient/colleague/post_spawn()
	..()
	second = stand_in(first_marker("s"), "Sam Second")
	second.apply_damage(15, BRUTE, BODY_ZONE_CHEST)
	colleague = second_bot(first_marker("O"), "Col League")
	colleague.mind.assigned_role = "Medical Doctor"
	// Its brain on Pat by hand: a goal with no strategy is left alone (handle_goal()), so it stands holding it.
	var/datum/bot_goal/treat_patient/G = new
	G.target = patient
	colleague.bot_brain.current_goal = G
	colleague.bot_brain.state = BOT_STATE_GOAL
	log_line("Col League, another doctor, is on its way to Pat")

/datum/bot_scenario/fixes1112/med_patient/colleague/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/datum/bot_goal/treat_patient/G = brain.current_goal
	if((istype(G) && G.target == patient) || patient.getBruteLoss() < 30)
		fail_reason = "went for the patient a colleague already had"
		return BOT_GYM_FAIL
	return second.getBruteLoss() <= 10 ? BOT_GYM_PASS : BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// Pills for whoever asks (goals/powergame.dm): a chemist with three tricordrazine pills, as /datum/bot_scenario/powergame_chemist
// (scenarios_powergame.dm). Layout letter C: whoever asks.
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/fixes1112/pills
	job = "Chemist"
	time_limit = 40 SECONDS
	var/mob/living/carbon/human/visitor
	var/datum/bot_request/asked

/datum/bot_scenario/fixes1112/pills/post_spawn()
	for(var/i in 1 to 3)
		var/obj/item/reagent_containers/pill/P = new(bot)
		P.name = "tricordrazine pill"
		P.reagents.add_reagent(/datum/reagent/medicine/tricordrazine, 15)
		bot.equip_to_slot_or_del(P, ITEM_SLOT_BACKPACK)
	visitor = stand_in(first_marker("C"), "Casey Visitor")
	addtimer(CALLBACK(src, PROC_REF(ask)), 2 SECONDS)

/datum/bot_scenario/fixes1112/pills/make_goal()
	return null

/datum/bot_scenario/fixes1112/pills/proc/pills_kind()
	return locate(/datum/bot_request_kind/heal_chems) in GLOB.bot_request_kinds

/datum/bot_scenario/fixes1112/pills/proc/ask()
	if(result != BOT_GYM_PENDING || QDELETED(visitor))
		return
	var/datum/bot_request_kind/kind = pills_kind()
	if(!kind)
		log_line("there's no such request")
		return
	log_line("visitor (over the radio): 'Chemistry, could I get a couple of tricord pills?'")
	asked = bot_new_request(kind, visitor, null, visitor)
	bot_offer_request(asked)

/datum/bot_scenario/fixes1112/pills/no_way_in
	name = "powergame: a chemist doesn't promise pills behind a door its card won't open"
	desc = "Whoever asks is behind a Kitchen door the chemist's card doesn't open. It doesn't take the call. It took it, said 'On my way with them', found no way in at the first step and dropped it with the call still down as taken, and the asker stood a minute and a half waiting: 26 of the 30 hand-overs given up in bugs1112base (run12 Jo Sandoval to Pat Holloway in the Kitchen)."
	layout = list(
		"##########",
		"#B...D..C#",
		"##########")
	time_limit = 20 SECONDS

/datum/bot_scenario/fixes1112/pills/no_way_in/setup()
	for(var/turf/T in markers["D"])
		for(var/obj/machinery/door/airlock/A in T)
			A.req_access = list(ACCESS_KITCHEN)

/datum/bot_scenario/fixes1112/pills/no_way_in/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if((asked && asked.taken_by == brain) || bot_transcript_said("taking a heal chems call") || bot_transcript_said("giving up on /datum/bot_goal/hand_over"))
		fail_reason = "took a call for pills from behind a door it has no way through"
		return BOT_GYM_FAIL
	if(!asked || world.time < start_time + 12 SECONDS)
		return BOT_GYM_PENDING
	return BOT_GYM_PASS

// Layout letter n: somebody else who asks, while the chemist is on its way to the first.
/datum/bot_scenario/fixes1112/pills/second_call
	name = "powergame: a chemist taking pills over doesn't drop them for the next call"
	desc = "Two calls for pills, the second while the chemist is on its way with the first. It takes the first over. It used to drop the first hand-over for the second call, and the first asker stood the whole minute and a half (bugs1112base run3 Sage Whitlock, Terry Mwangi left waiting)."
	layout = list(
		"##############",
		"#C..........B#",
		"#...........n#",
		"##############")
	var/mob/living/carbon/human/other_asker
	var/datum/bot_request/asked_second

/datum/bot_scenario/fixes1112/pills/second_call/post_spawn()
	..()
	other_asker = stand_in(first_marker("n"), "Eli Elsewhere")

/datum/bot_scenario/fixes1112/pills/second_call/ask()
	..()
	if(result != BOT_GYM_PENDING || QDELETED(other_asker))
		return
	log_line("chemist on [brain.current_goal ? brain.current_goal.type : "nothing"] when the second call comes")
	log_line("Eli (over the radio): 'Chem, any healing pills going?'")
	asked_second = bot_new_request(pills_kind(), other_asker, null, other_asker)
	bot_offer_request(asked_second)

/datum/bot_scenario/fixes1112/pills/second_call/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("dropping /datum/bot_goal/hand_over"))
		fail_reason = "dropped the first hand-over for the second call"
		return BOT_GYM_FAIL
	for(var/obj/item/reagent_containers/pill/P in range(1, visitor))
		if(isturf(P.loc) && P.reagents.has_reagent(/datum/reagent/medicine/tricordrazine))
			return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/fixes1112/pills_called_off
	name = "powergame: somebody who stops waiting for pills calls it off"
	desc = "It's asked Chemistry for pills and nobody takes the call. After twenty seconds it stops waiting, and the call goes with it: left open, a chemist who couldn't get to it took it up to three minutes on, once it was out in a hallway, and brought pills to somebody no longer waiting (bugs1112base run2 Val Castillo)."
	job = "Assistant"
	layout = list(
		"######",
		"#B...#",
		"######")
	time_limit = 40 SECONDS
	max_goal_attempts = 1
	var/datum/bot_request/asked

/datum/bot_scenario/fixes1112/pills_called_off/make_goal()
	var/datum/bot_request_kind/kind = locate(/datum/bot_request_kind/heal_chems) in GLOB.bot_request_kinds
	if(!kind)
		log_line("there's no such request")
		return null
	log_line("bot (over the radio): 'Chemistry, could I get a couple of tricord pills?' Nobody's on Chemistry.")
	asked = bot_new_request(kind, bot, FREQ_COMMON, get_turf(bot))
	return new /datum/bot_goal/await_activator/pills()

/datum/bot_scenario/fixes1112/pills_called_off/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!bot_transcript_said("giving up on /datum/bot_goal/await_activator/pills"))
		return BOT_GYM_PENDING
	if(asked in GLOB.bot_requests)
		fail_reason = "stopped waiting, and left its call for pills open for a chemist to take minutes later"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

// ---------------------------------------------------------------------------------------------
// Brews with the hands and the bag full (goals/chem_lab.dm): the lab of /datum/bot_scenario/chem_brew (scenarios_chem.dm), a lamp in
// each hand and one on the belt (a lamp goes on a belt, so the belt's taken), a lighter in each pocket, and a bag full of jumpsuits. The
// lamps go nowhere but down, and the bag's the only room. Layout letters k: a large beaker, e: an empty grenade case, o: cable.
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/fixes1112/brew
	layout = list(
		"#########",
		"#D.H.P.C#",
		"#.......#",
		"#.Bk..b.#",
		"#......M#",
		"#########")
	job = "Chemist"
	time_limit = 240 SECONDS
	max_goal_attempts = 1
	kit_hands = list(/obj/item/flashlight/lamp, /obj/item/flashlight/lamp)
	kit_backpack = list(/obj/item/clothing/under/color/grey, /obj/item/clothing/under/color/grey, /obj/item/clothing/under/color/grey, /obj/item/clothing/under/color/grey,
		/obj/item/clothing/under/color/grey, /obj/item/clothing/under/color/grey, /obj/item/clothing/under/color/grey)
	/// The brew's label (GLOB.bot_brews).
	var/label
	/// The lab's beakers it has picked up.
	var/list/beakers_taken = list()

/datum/bot_scenario/fixes1112/brew/build_tile(turf/T, char)
	switch(char)
		if("D")
			place(char, new /obj/machinery/chem_dispenser(T))
		if("H")
			place(char, new /obj/machinery/chem_heater(T))
		if("P")
			place(char, new /obj/machinery/chem/pressure(T))
		if("C")
			place(char, new /obj/machinery/chem/centrifuge(T))
		if("M")
			place(char, new /obj/machinery/chem_master(T))
		if("b")
			place(char, new /obj/item/storage/box/syringes(T))
		if("k")
			place(char, new /obj/item/reagent_containers/glass/beaker/large(T))
		if("e")
			place(char, new /obj/item/grenade/chem_grenade(T))
		if("o")
			place(char, new /obj/item/stack/cable_coil(T))
		else
			return ..()

/datum/bot_scenario/fixes1112/brew/post_spawn()
	brain.set_playstyle(BOT_STYLE_POWERGAMER)
	brain.job_is_chemist_for_gym = TRUE
	bot.equip_to_slot_or_del(new /obj/item/flashlight/lamp(bot), ITEM_SLOT_BELT)
	bot.equip_to_slot_or_del(new /obj/item/lighter(bot), ITEM_SLOT_LPOCKET)
	bot.equip_to_slot_or_del(new /obj/item/lighter(bot), ITEM_SLOT_RPOCKET)

/datum/bot_scenario/fixes1112/brew/proc/brew()
	for(var/list/B in GLOB.bot_brews)
		if(B["label"] == label)
			return B

/datum/bot_scenario/fixes1112/brew/make_goal()
	var/datum/bot_goal/synthesize_medicine/fixed/G = new
	G.brew = brew()
	return G

/// A reason to fail if it set one of the lab's beakers down in the middle of the brew, or got to the dispenser with no beaker on it.
/datum/bot_scenario/fixes1112/brew/proc/beaker_problem()
	if(bot_transcript_said("no empty beaker on me"))
		return "no empty beaker on it at the dispenser: it had set the brew's beaker down"
	var/brewing = istype(brain.current_goal, /datum/bot_goal/synthesize_medicine) || istype(brain.suspended_goal, /datum/bot_goal/synthesize_medicine)
	for(var/obj/item/reagent_containers/glass/beaker/B in placed["k"])
		if(QDELETED(B))
			continue
		if(!isturf(B.loc))
			beakers_taken |= B
		else if(brewing && (B in beakers_taken))
			return "set the brew's beaker down in the middle of the brew"
	return null

/datum/bot_scenario/fixes1112/brew/release_run()
	beakers_taken = null
	return ..()

/datum/bot_scenario/fixes1112/brew/chloral
	name = "chem: chloral hydrate with both hands and the bag full, the brew's beaker stays with it"
	desc = "Chloral hydrate into syringes, with the beaker and the box of syringes to fetch, both hands full of lamps and the bag full. The beaker it fetched went down for the box of syringes, and it was 'no empty beaker on me' at the dispenser: 17 brews in bugs1112base (run5 Micah, run7 Robin, run2 Robin, run12 Jo). Each part goes in the bag as it comes, a jumpsuit out of it to make room, and the syringes get filled."
	label = "chloral hydrate"

/datum/bot_scenario/fixes1112/brew/chloral/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/problem = beaker_problem()
	if(problem)
		fail_reason = problem
		return BOT_GYM_FAIL
	if(!bot_transcript_said("to make room for"))
		return BOT_GYM_PENDING
	var/list/B = brew()
	for(var/obj/item/reagent_containers/syringe/S in bot.GetAllContents(/obj/item/reagent_containers/syringe))
		var/datum/reagent/R = S.reagents.get_master_reagent()
		if(R?.type == B["reagent"])
			log_line("made [S] with [S.reagents.get_reagent_amount(R.type)]u of [R.name]")
			return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/fixes1112/brew/smoke
	name = "chem: knockout smoke with both hands and the bag full, the brew's parts stay with it"
	desc = "A knockout smoke grenade from parts lying about (two beakers, the case, the cable; the screwdriver's in the bag), both hands full of lamps and the bag full. Each part fetched went down for the next: the beaker for the cable, the cable for the second beaker (bugs1112base run5 Micah, run7 Robin). Each goes in the bag as it comes, and the grenade gets made."
	label = "knockout smoke"
	time_limit = 120 SECONDS
	layout = list(
		"#########",
		"#D.H.P.C#",
		"#.......#",
		"#.Bkkeo.#",
		"#......M#",
		"#########")
	kit_backpack = list(/obj/item/clothing/under/color/grey, /obj/item/clothing/under/color/grey, /obj/item/clothing/under/color/grey, /obj/item/clothing/under/color/grey,
		/obj/item/clothing/under/color/grey, /obj/item/clothing/under/color/grey, /obj/item/screwdriver, /obj/item/lighter)

/datum/bot_scenario/fixes1112/brew/smoke/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/problem = beaker_problem()
	if(problem)
		fail_reason = problem
		return BOT_GYM_FAIL
	if(!bot_transcript_said("to make room for"))
		return BOT_GYM_PENDING
	return brain.bot_ready_grenade() ? BOT_GYM_PASS : BOT_GYM_PENDING

// <<< sci_service_scenarios.dm
// Group sci_service (shift batch bugs1112base): Toxins, the janitor's kit, the R&D bench, nanite disks, the clown's act, strolls into
// running cells, Security's cuffs and backing off from a suit. Each scenario fails on the build before its fix and passes after it.
// Nothing here names a proc or type only a fix adds, so the "before" build (tools/bot_gym/ab_gym.sh) compiles too.
//
// Layout letters used here, beyond build_tile()'s own: n a tank on the floor; o blood, M a mop, U an empty bucket, K a water tank;
// h a protolathe, C an R&D console (lathe) or somebody stood there (others), e metal, z glass (bench); k a box of nanite program disks,
// H a nanite program hub, Q a nanite cloud controller; d/k a cell's windoor, l/n its locker, i/j its timer, a a free tile in the cell;
// p and z a pair of cuffs (restock).

// ---------------------------------------------------------------------------------------------
// Toxins: both tanks on the valve with a full bag and a hand it can't empty (goals/toxins.dm gather_tanks)
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/fixes1112/tank_juggle
	name = "toxins: a full bag and a wrench in one hand, and both tanks still go on the valve"
	desc = "Shift bugs1112base run10, Elliot Mbeki: bag 21/21 and a wrench in one hand. Picking up one tank set the other down at its feet, the step sent it for that one, and the two changed places fifteen times a try, nine tries in a shift: no bomb. A tank at its feet will do, and the valve takes each one up from where it lies."
	job = "Scientist"
	time_limit = 45 SECONDS
	kit_hands = list(/obj/item/wrench)
	// 3 + 2 + 5 x 3 = 20 of the backpack's 21: neither a tank (3) nor the wrench (2) will go in
	kit_backpack = list(/obj/item/transfer_valve, /obj/item/assembly/timer, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher)
	layout = list(
		"########",
		"#B..n..#",
		"########")
	var/datum/bot_toxins/lab

/datum/bot_scenario/fixes1112/tank_juggle/setup()
	lab = new
	lab.stage = 20
	lab.rest_until = world.time + 10 MINUTES //the duty its success chains to (try_start()) finds nothing more to do
	GLOB.bot_toxins = lab
	lab.hot_tank = place("n", new /obj/item/tank/internals/oxygen/empty(first_marker("n")))

/datum/bot_scenario/fixes1112/tank_juggle/post_spawn()
	// Pockets and belt full too, as hands_full_of_tools has them: nothing in a hand has anywhere to go
	for(var/slot in list(ITEM_SLOT_LPOCKET, ITEM_SLOT_RPOCKET))
		if(!bot.get_item_by_slot(slot))
			bot.equip_to_slot_or_del(new /obj/item/flashlight(bot), slot)
	if(!bot.get_item_by_slot(ITEM_SLOT_BELT))
		bot.equip_to_slot_or_del(new /obj/item/storage/belt/fannypack(bot), ITEM_SLOT_BELT)
	var/obj/item/storage/belt/fannypack/F = bot.get_item_by_slot(ITEM_SLOT_BELT)
	if(istype(F))
		for(var/i in 1 to 3)
			new /obj/item/flashlight(F)
	// The cold tank in the ACTIVE hand and the wrench in the other, as run10's were: kit_hands put the wrench in the active one
	lab.cold_tank = new /obj/item/tank/internals/oxygen/empty(bot)
	bot.swap_hand()
	bot.put_in_active_hand(lab.cold_tank)
	if(bot.get_active_held_item() != lab.cold_tank || !istype(bot.get_inactive_held_item(), /obj/item/wrench))
		log_line("SETUP: active hand [bot.get_active_held_item() || "empty"], other hand [bot.get_inactive_held_item() || "empty"], not the cold tank and the wrench")

/datum/bot_scenario/fixes1112/tank_juggle/make_goal()
	if(goal_attempts > 1)
		return null
	return new /datum/bot_goal/toxins/assemble(lab)

/datum/bot_scenario/fixes1112/tank_juggle/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/set_downs = 0
	for(var/line in transcript)
		if(findtext(line, "setting the oxygen tank down for a moment")) //both tanks are oxygen tanks
			set_downs++
	var/gave_up = bot_transcript_said("given up too many times trying to get things")
	if(set_downs > 2 || gave_up)
		fail_reason = "juggled the tanks: set one down [set_downs] time\s[gave_up ? ", and gave the bomb up" : ""]"
		return BOT_GYM_FAIL
	var/obj/item/transfer_valve/V = lab.valve
	if(V && V.tank_one && V.tank_two && V.attached_device)
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/fixes1112/tank_juggle/release_run()
	if(lab)
		STOP_PROCESSING(SSprocessing, lab)
		if(GLOB.bot_toxins == lab)
			GLOB.bot_toxins = null
	return ..()

// ---------------------------------------------------------------------------------------------
// Janitor: the mop, bucket and water it can get to (goals/janitor.dm)
// ---------------------------------------------------------------------------------------------

/// The janitor's rounds, as /datum/bot_scenario/duty/janitor runs them (scenarios_janitor.dm), with every bucket empty and the door locked.
/datum/bot_scenario/fixes1112/janitor_kit
	job = "Janitor"
	time_limit = 120 SECONDS
	max_goal_attempts = 20
	/// Transcript lines that mean it went by a mop, bucket or tap it couldn't get to.
	var/list/bad_lines

/datum/bot_scenario/fixes1112/janitor_kit/setup()
	for(var/turf/T in markers["o"])
		place("o", new /obj/effect/decal/cleanable/blood(T))
	for(var/turf/T in markers["M"])
		place("M", new /obj/item/mop(T))
	for(var/turf/T in markers["U"])
		place("U", new /obj/item/reagent_containers/glass/bucket(T))
	for(var/turf/T in markers["K"])
		place("K", new /obj/structure/reagent_dispensers/watertank(T))
	var/obj/machinery/door/airlock/A = first_placed("D")
	if(A)
		A.req_access = list(ACCESS_CAPTAIN)

/datum/bot_scenario/fixes1112/janitor_kit/post_spawn()
	give_job_id(list(ACCESS_JANITOR))

/datum/bot_scenario/fixes1112/janitor_kit/issue_goal()
	var/datum/bot_duty/D = bot_duty_of(/datum/bot_duty/janitor)
	if(!D)
		log_line("no janitor duty")
		return
	if(D.try_start(brain))
		goal_attempts++
		log_line("[D.name]: started on [brain.current_goal ? brain.current_goal.type : "it"] (attempt [goal_attempts]/[max_goal_attempts])")

/datum/bot_scenario/fixes1112/janitor_kit/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/line in transcript)
		for(var/bad in bad_lines)
			if(findtext(line, bad))
				fail_reason = "went by one it couldn't get to ([line])"
				return BOT_GYM_FAIL
	if(bot.IsKnockdown() || bot.IsParalyzed() || !(bot.mobility_flags & MOBILITY_STAND))
		fail_reason = "slipped on its own wet floor"
		return BOT_GYM_FAIL
	for(var/turf/T in arena_area)
		if(brain.turf_has_mess(T))
			return BOT_GYM_PENDING
	return BOT_GYM_PASS

/datum/bot_scenario/fixes1112/janitor_kit/reachable_kit
	name = "janitor: takes the mop and bucket it can get to, not the nearer ones behind a door"
	desc = "Shift bugs1112base run8, Blake Ferreira on Meta: the nearest mop as the crow flies was in a locked room in Port Bow Maintenance and the nearest bucket was Hydroponics', so it was \"no way to the mop\" and \"no bucket it can get to\" for three minutes at a time, though it stood at its JaniDrobe two tiles from its own, and it mopped its first tile fourteen minutes in. Here a mop and a bucket are behind a door its ID doesn't open, and another pair is further down the corridor with the only water: it goes for those."
	layout = list(
		"##################",
		"#MUD.B...o.o..MUK#",
		"##################")
	bad_lines = list("no way to the mop", "no bucket it can get to", "nowhere to get a", "there's a way to", "no water to be had")
	var/obj/item/mop/locked_mop
	var/obj/item/reagent_containers/glass/bucket/locked_bucket

/datum/bot_scenario/fixes1112/janitor_kit/reachable_kit/setup()
	..()
	locked_mop = first_placed("M") //the layout's first of each, behind the door
	locked_bucket = first_placed("U")

/datum/bot_scenario/fixes1112/janitor_kit/reachable_kit/check()
	. = ..()
	if(. == BOT_GYM_FAIL)
		return
	var/list/carried = bot.GetAllContents()
	if((locked_mop in carried) || (locked_bucket in carried))
		fail_reason = "got hold of the one behind the door"
		return BOT_GYM_FAIL

/datum/bot_scenario/fixes1112/janitor_kit/water_by_bucket
	name = "janitor: counts on the water by the bucket, not the taps nearest itself"
	desc = "Shift bugs1112base run5, Jamie Novak in the Bar: the five taps nearest it were the kitchen's, the bar's and Hydroponics', behind doors its ID doesn't open, so it was \"no water to be had for the mop\" for three minutes, with a tank it could get to second-nearest the bucket it would have fetched. Here five tanks behind a locked door are the nearest to it, and the bucket is down the corridor with the only tank it can get to beside it."
	layout = list(
		"######################",
		"#KKKKKD.BM.o.o.....UK#",
		"######################")
	bad_lines = list("no water to be had", "no water for the mop bucket", "giving up on /datum/bot_goal/fill_bucket", "no bucket it can get to", "nowhere to get a")

// ---------------------------------------------------------------------------------------------
// The R&D bench: a lathe left with its panel off (goals/rnd_bench.dm fit_upgrades)
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/fixes1112/lathe_panel_off
	name = "upgrades: driven off a lathe with its panel off, the scientist shuts it and carries on"
	desc = "Shift bugs1112base run9, Sam Delacroix: the lathe caught fire the click after its panel came off, stop-drop-and-roll knocked the screwdriver out of its hand, and the fit was given up with the panel still off. That wrote the lathe off for thirty minutes, off the list of panels to shut as well, and a lathe with its panel off is no lathe: Sync pressed 41 times, nothing printed or fitted. Here the panel's off and the fit given up as the fire left them: it shuts the panel first, syncs, and the round goes on, the lathe included."
	job = "Scientist"
	time_limit = 240 SECONDS //long enough for the lathe to catch fire and the bot to start again, as the bench scenarios allow
	max_goal_attempts = 10
	kit_backpack = list(/obj/item/screwdriver)
	layout = list(
		"##########",
		"#B.h.C...#",
		"#........#",
		"#e.z.....#",
		"##########")
	/// When the panel was first seen shut again.
	var/shut_at = 0

/datum/bot_scenario/fixes1112/lathe_panel_off/setup()
	place("h", new /obj/machinery/rnd/production/protolathe(first_marker("h")))
	var/obj/machinery/computer/rdconsole/core/C = place("C", new /obj/machinery/computer/rdconsole/core(first_marker("C")))
	C.SyncRDevices()
	place("e", new /obj/item/stack/sheet/metal/fifty(first_marker("e")))
	place("z", new /obj/item/stack/sheet/glass/fifty(first_marker("z")))
	new /obj/item/storage/part_replacer(first_marker("h")) //an RPED waiting on the lathe, as in the upgrade round scenarios
	SSresearch.science_tech.research_node_id("engineering", TRUE, FALSE)

/datum/bot_scenario/fixes1112/lathe_panel_off/post_spawn()
	var/obj/machinery/rnd/production/protolathe/L = first_placed("h")
	var/obj/machinery/computer/rdconsole/C = first_placed("C")
	var/obj/item/screwdriver/S = locate() in bot.GetAllContents()
	L.attackby(S, bot) //the fit's first click: the panel off, and the lathe unlinked from the console
	var/datum/bot_goal/fit_upgrades/G = new(L)
	G.on_give_up(brain) //what the fire came to: the fit given up with the panel still off
	log_line("SETUP: panel [L.panel_open ? "off" : "on"], written off until [LAZYACCESS(brain.upgrade_blocked, L) || "-"] (now [world.time]), console linked to [C.linked_lathe || "nothing"]")

/datum/bot_scenario/fixes1112/lathe_panel_off/issue_goal()
	var/datum/bot_duty/D = bot_duty_of(/datum/bot_duty/rnd_bench)
	if(!D)
		log_line("no R&D bench duty")
		return
	if(D.try_start(brain))
		goal_attempts++
		log_line("[D.name]: started on [brain.current_goal ? brain.current_goal.type : "it"] (attempt [goal_attempts]/[max_goal_attempts])")

/datum/bot_scenario/fixes1112/lathe_panel_off/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/machinery/rnd/production/protolathe/L = first_placed("h")
	var/obj/machinery/computer/rdconsole/C = first_placed("C")
	if(!shut_at)
		if(!L.panel_open)
			shut_at = world.time
			log_line("the lathe's panel is on again")
		else
			var/syncs = 0
			for(var/line in transcript)
				if(findtext(line, "for /datum/bot_goal/sync_console"))
					syncs++
			if(syncs >= 2)
				fail_reason = "pressed Sync [syncs] times at a lathe with its panel off, and never shut it"
				return BOT_GYM_FAIL
			if(world.time > start_time + 45 SECONDS)
				fail_reason = "left the lathe with its panel off (written off until [LAZYACCESS(brain.upgrade_blocked, L) || "-"], now [world.time])"
				return BOT_GYM_FAIL
			return BOT_GYM_PENDING
	// Then the round, as /datum/bot_scenario/duty/bench/upgrade judges it. The panel comes off again for the fit: only shut once mattered above.
	if(!brain.machines_upgraded || L.panel_open)
		return BOT_GYM_PENDING
	var/rating = 0
	for(var/obj/item/stock_parts/manipulator/M in L.component_parts)
		rating = max(rating, M.rating)
	if(rating < 2)
		fail_reason = "it says it upgraded the lathe, and the lathe's manipulators are still tier [rating]"
		return BOT_GYM_FAIL
	return C.linked_lathe == L ? BOT_GYM_PASS : BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// Nanites: a blank disk with both hands full (goals/nanites.dm nanite_program_run)
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/fixes1112/nanite_disk_hands_full
	name = "nanites: both hands full, and it still takes a blank disk and gets the program on the cloud"
	desc = "Shift bugs1112base run8, Noel Abernathy, a screwdriver and an RPED in its hands: at the disk box it put the disk in neither, put_in_hands() tipped it onto the floor, and the upload was given up, the nanite work rested three minutes. 8 of the batch's 17 upload give-ups went that way. It frees a hand first, a full bag or not."
	job = "Scientist"
	time_limit = 60 SECONDS
	kit_hands = list(/obj/item/screwdriver, /obj/item/storage/part_replacer)
	kit_backpack = list(/obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher) //21 of 21
	layout = list(
		"###########",
		"#B..k.H.Q.#",
		"#.........#",
		"###########")
	var/obj/item/screwdriver/tool

/datum/bot_scenario/fixes1112/nanite_disk_hands_full/setup()
	place("k", new /obj/item/storage/box/disks_nanite(first_marker("k")))
	place("H", new /obj/machinery/nanite_program_hub(first_marker("H")))
	place("Q", new /obj/machinery/computer/nanite_cloud_controller(first_marker("Q")))
	SSresearch.science_tech.research_node_id("nanite_base", TRUE)

/datum/bot_scenario/fixes1112/nanite_disk_hands_full/post_spawn()
	for(var/slot in list(ITEM_SLOT_LPOCKET, ITEM_SLOT_RPOCKET))
		if(!bot.get_item_by_slot(slot))
			bot.equip_to_slot_or_del(new /obj/item/flashlight(bot), slot)
	if(!bot.get_item_by_slot(ITEM_SLOT_BELT))
		bot.equip_to_slot_or_del(new /obj/item/storage/belt/fannypack(bot), ITEM_SLOT_BELT)
	var/obj/item/storage/belt/fannypack/F = bot.get_item_by_slot(ITEM_SLOT_BELT)
	if(istype(F))
		for(var/i in 1 to 3)
			new /obj/item/flashlight(F)
	tool = locate(/obj/item/screwdriver) in bot.held_items

/datum/bot_scenario/fixes1112/nanite_disk_hands_full/make_goal()
	if(goal_attempts > 1)
		return null
	for(var/id in GLOB.bot_nanite_programs)
		if(bot_researched_design(id))
			return new /datum/bot_goal/upload_nanite_program(first_placed("Q"), id)
	log_line("SETUP: no nanite program researched to upload")
	return null

/datum/bot_scenario/fixes1112/nanite_disk_hands_full/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	// First: a second upload chained on after the first can set the first disk down, and that's not this run's business
	if(brain.nanite_programs_uploaded >= 1)
		if(tool && !(tool in bot.GetAllContents()) && !(tool in brain.set_down_items))
			fail_reason = "set the screwdriver down for the disk and forgot it"
			return BOT_GYM_FAIL
		return BOT_GYM_PASS
	if(bot_transcript_said("giving up on /datum/bot_goal/upload_nanite_program"))
		fail_reason = "gave the upload up at the disk box, both hands full"
		return BOT_GYM_FAIL
	for(var/turf/T in arena_area)
		for(var/obj/item/disk/nanite_program/D in T)
			if(get_dist(bot, D) > 1)
				fail_reason = "tipped [D] onto the floor and left it"
				return BOT_GYM_FAIL
	return BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// The clown's act: nobody about at the first look (goals/civilians.dm perform)
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/fixes1112/clown_looks_again
	name = "clown: nobody about at its first look, and it's performing within seconds of somebody walking in"
	desc = "Shift bugs1112base run3, Flop O'Honker: horn on it, in and out of the bar, and its first act 21 minutes in. It looked for an audience every one to three and a half minutes, and a look that found nobody waited the whole gap. With its act ready and nobody about, it looks again in a few seconds."
	job = "Clown"
	time_limit = 60 SECONDS
	kit_backpack = list(/obj/item/bikehorn)
	layout = list(
		"#########",
		"#B....C.#",
		"#########")
	var/mob/living/carbon/human/visitor
	var/arrived_at = 0
	var/started_at = 0

/datum/bot_scenario/fixes1112/clown_looks_again/post_spawn()
	brain.diligence = 1
	brain.my_duties(BOT_DUTY_WORK)
	brain.duty_next_check[bot_duty_of(/datum/bot_duty/perform)] = world.time //its first look is now, and finds nobody
	addtimer(CALLBACK(src, PROC_REF(sci_arrive)), 8 SECONDS)

/datum/bot_scenario/fixes1112/clown_looks_again/proc/sci_arrive()
	if(result != BOT_GYM_PENDING)
		return
	visitor = stand_in(first_marker("C"), "Casey Visitor")
	visitor.setDir(get_dir(visitor, bot))
	arrived_at = world.time
	log_line("Casey Visitor walks in")

/// The perform duty on run_duties()'s timing (bot_duties.dm), and nothing else: the stock duty harness asks every second, which would
/// hide the gap between looks, and run_duties() itself would set the clown's other work duties going too.
/datum/bot_scenario/fixes1112/clown_looks_again/issue_goal()
	var/datum/bot_duty/D = bot_duty_of(/datum/bot_duty/perform)
	if(!D || !brain.duty_next_check || world.time < brain.duty_next_check[D])
		return
	brain.duty_next_check[D] = world.time + D.next_look(brain)
	if(D.try_start(brain))
		goal_attempts++
		log_line("performing: started (attempt [goal_attempts])")

/datum/bot_scenario/fixes1112/clown_looks_again/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!started_at && (istype(brain.current_goal, /datum/bot_goal/perform) || brain.shows_put_on))
		started_at = world.time
	if(started_at && !arrived_at)
		fail_reason = "performed to nobody"
		return BOT_GYM_FAIL
	if(arrived_at && !started_at && world.time - arrived_at > 20 SECONDS)
		var/datum/bot_duty/D = bot_duty_of(/datum/bot_duty/perform)
		var/next = brain.duty_next_check ? brain.duty_next_check[D] : 0
		fail_reason = "no act [round((world.time - arrived_at) / 10)]s after somebody walked in (its next look in [round((next - world.time) / 10)]s)"
		return BOT_GYM_FAIL
	if(brain.shows_put_on && brain.state == BOT_STATE_WANDER)
		if(locate(/obj/item/bikehorn) in bot.held_items)
			fail_reason = "left holding the horn"
			return BOT_GYM_FAIL
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// The Brig: no strolls into a cell with a sentence running (bot_brain.dm is_wanderable_turf())
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/fixes1112/cell_stroll
	name = "brig: an officer on a stroll doesn't pick a tile in a cell somebody's serving time in"
	desc = "Shift bugs1112base run4, Alexis Byrne: a stroll picked a tile inside Cell 3 halfway through the janitor's ten-minute sentence, the officer's ID opened the cell, they swapped places, and the janitor walked out without its things. The cell's tiles aren't somewhere to stroll to while a sentence runs, and are again once it's served."
	job = "Security Officer"
	time_limit = 30 SECONDS
	layout = list(
		"#########",
		"#...Bi..#",
		"####d####",
		"###.C.###",
		"###a.l###",
		"#########")
	var/mob/living/carbon/human/prisoner
	var/obj/machinery/door_timer/timer
	/// The sentence has been called served (the 15 s mark).
	var/lifted = FALSE

/datum/bot_scenario/fixes1112/cell_stroll/issue_goal()
	return //no errand: the checks ask its stroll picks directly, every second

/// A cell as /datum/bot_scenario/brigged builds one: a windoor opening south into it, a locker inside, the timer outside.
/datum/bot_scenario/fixes1112/cell_stroll/proc/sci_make_cell(door_mark, locker_mark, timer_mark)
	var/id = "gymcell[rand(1, 99999)]"
	var/obj/machinery/door/window/brigdoor/door = new(first_marker(door_mark))
	door.dir = SOUTH
	door.id = id
	place(door_mark, door)
	var/obj/structure/closet/secure_closet/brig/locker = new(first_marker(locker_mark))
	locker.id = id
	place(locker_mark, locker)
	var/obj/machinery/door_timer/T = new(first_marker(timer_mark))
	T.id = id
	T.targets = list(door, locker)
	T.stat &= ~BROKEN
	place(timer_mark, T)
	return T

/datum/bot_scenario/fixes1112/cell_stroll/setup()
	timer = sci_make_cell("d", "l", "i")

/datum/bot_scenario/fixes1112/cell_stroll/post_spawn()
	give_job_id(list(ACCESS_SECURITY, ACCESS_BRIG))
	prisoner = stand_in(first_marker("C"), "Pat Prisoner")
	timer.set_timer(10 MINUTES)
	timer.timer_start()

/// Fails the run if a stroll from where the bot is could end in `cell`'s interior: any tile of it a stroll may pick, or any of 20 picks.
/datum/bot_scenario/fixes1112/cell_stroll/proc/sci_strolls_into(obj/machinery/door_timer/cell, what)
	var/list/interior = bot_get_cell_interior(cell)
	if(!length(interior))
		fail_reason = "SETUP: no interior found for [what]"
		return TRUE
	for(var/turf/T as anything in interior)
		if(brain.is_wanderable_turf(T))
			fail_reason = "a stroll could pick [bot_coord(T)], in [what] with a sentence running"
			return TRUE
	for(var/i in 1 to 20)
		var/turf/pick = brain.pick_local_destination()
		if(pick && (pick in interior))
			fail_reason = "picked [bot_coord(pick)], in [what] with a sentence running, to stroll to"
			return TRUE
	return FALSE

/datum/bot_scenario/fixes1112/cell_stroll/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!lifted)
		if(sci_strolls_into(timer, "the occupied cell"))
			return BOT_GYM_FAIL
		if(world.time > start_time + 15 SECONDS)
			lifted = TRUE
			timer.timing = FALSE //served; set by hand, as timer_end() would open the door
			log_line("sentence served")
		return BOT_GYM_PENDING
	if(!brain.is_wanderable_turf(first_marker("a")))
		fail_reason = "the cell's still off limits with no sentence running"
		return BOT_GYM_FAIL
	return world.time > start_time + 20 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/fixes1112/cell_stroll/release_run()
	// A running timer outlives the arena, and the next arena built on these turfs would read as inside a cell
	for(var/mark in list("i", "j"))
		for(var/obj/machinery/door_timer/T in placed[mark])
			if(!QDELETED(T) && T.timing)
				T.timer_end(forced = TRUE)
			GLOB.bot_brig_cell_interiors -= T
	return ..()

/datum/bot_scenario/fixes1112/cell_stroll/next_cell
	name = "brig: an officer in one running cell doesn't pick a tile in the next one to stroll to"
	desc = "The same rule from inside a cell. Meta's cells are four tiles apart, so a stroll's pick from inside one reaches the next: an officer in one running cell (seeing to a prisoner) could stroll into the occupied one beside it and open it with its ID, and a prisoner in one kept picking the next cell's tiles. Only its own cell's tiles are allowed it."
	layout = list(
		"#############",
		"#....i....j.#",
		"####d#####k##",
		"###aB.###.C.#",
		"###..l###..n#",
		"#############")
	var/obj/machinery/door_timer/timer_b

/datum/bot_scenario/fixes1112/cell_stroll/next_cell/setup()
	..()
	timer_b = sci_make_cell("k", "n", "j")

/datum/bot_scenario/fixes1112/cell_stroll/next_cell/post_spawn()
	..() //the prisoner (C) is in the second cell
	timer_b.set_timer(10 MINUTES)
	timer_b.timer_start()

/datum/bot_scenario/fixes1112/cell_stroll/next_cell/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!(get_turf(bot) in bot_get_cell_interior(timer)))
		fail_reason = "SETUP: the officer isn't in the first cell"
		return BOT_GYM_FAIL
	if(sci_strolls_into(timer_b, "the next cell"))
		return BOT_GYM_FAIL
	if(!brain.is_wanderable_turf(first_marker("a")))
		fail_reason = "won't even pace its own cell"
		return BOT_GYM_FAIL
	return world.time > start_time + 5 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// Security: cuffs from where it can walk to (goals/security_patrol.dm try_security_round)
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/fixes1112/cuffs_restock
	name = "security: out of cuffs, an officer goes for a pair it can walk to, not the nearer pair behind a door"
	desc = "Shift bugs1112base: 127 of Security's 373 restocks were given up, set off for the nearest pair as the crow flies on the Bridge's desk, in the Head of Personnel's office or walled up in maintenance, and run4's officer started on the Captain's Quarters door for a pair. Here the nearer pair is behind a door its ID doesn't open: it goes for the other."
	job = "Security Officer"
	time_limit = 40 SECONDS
	max_goal_attempts = 4
	layout = list(
		"############",
		"#p.D.B....z#",
		"############")
	var/obj/item/restraints/handcuffs/near
	var/obj/item/restraints/handcuffs/far

/datum/bot_scenario/fixes1112/cuffs_restock/setup()
	var/obj/machinery/door/airlock/A = first_placed("D")
	A.req_access = list(ACCESS_CAPTAIN)
	near = place("p", new /obj/item/restraints/handcuffs(first_marker("p")))
	far = place("z", new /obj/item/restraints/handcuffs(first_marker("z")))

/datum/bot_scenario/fixes1112/cuffs_restock/post_spawn()
	give_job_id(list(ACCESS_SECURITY))
	bot.equip_to_slot_or_del(new /obj/item/clothing/glasses/hud/security/sunglasses(bot), ITEM_SLOT_EYES) //no going for a HUD first

/// The security round as handle_wander() runs it (gym-scripted bots skip that), with the restock due.
/datum/bot_scenario/fixes1112/cuffs_restock/issue_goal()
	brain.next_security_restock_time = 0
	if(brain.try_security_round())
		goal_attempts++
		log_line("security round: [brain.current_goal ? brain.current_goal.type : "something"] (attempt [goal_attempts]/[max_goal_attempts])")

/datum/bot_scenario/fixes1112/cuffs_restock/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("trying a route through a locked door"))
		fail_reason = "planned a way through somebody else's door for a pair of cuffs"
		return BOT_GYM_FAIL
	if(bot_transcript_said("giving up on /datum/bot_goal/acquire_item_type"))
		fail_reason = "gave the restock up"
		return BOT_GYM_FAIL
	var/list/carried = bot.GetAllContents()
	if(near in carried)
		fail_reason = "got the pair from behind the door"
		return BOT_GYM_FAIL
	return (far in carried) ? BOT_GYM_PASS : BOT_GYM_PENDING

// ---------------------------------------------------------------------------------------------
// Security: backing off from a suit with its back to the wall (goals/security_tactics.dm step_back_from())
// ---------------------------------------------------------------------------------------------

/// The suit 4 tiles off (get_step_away()'s Max is 5). From B the one step that gains is up into the nook; from the nook every step that
/// gains is blocked, and the engine's fallback is back down. W round the nook and the room's east side: they block a step as Vic's table,
/// windows and vendor did, and the suit stays in sight from the nook.
/datum/bot_scenario/fixes1112/backoff_nook
	name = "security: waiting on the others with its back to the wall, it stands still instead of stepping in and out of a nook"
	desc = "Shift bugs1112base run7, Vic Sorrento: alone on a suit and waiting for two more, it backed into a nook and stepped out of it and back once a second, the step \"away\" the engine offered being round the obstacle and back towards the suit. run11's Jamie Novak went round three tiles of the Brig the same way. Only a step that gets it further off: in the nook it stays."
	job = "Security Officer"
	time_limit = 20 SECONDS
	kit_backpack = list(/obj/item/restraints/handcuffs, /obj/item/melee/baton/loaded, /obj/item/gun/energy/e_gun/advtaser)
	layout = list(
		"#########",
		"#####W.W#",
		"#.....BW#",
		"#.C....W#",
		"#########")
	var/mob/living/carbon/human/griefer
	/// Its steps since the arrest began, and how many of them ended nearer the suit than they started.
	var/moves = 0
	var/closer = 0

/datum/bot_scenario/fixes1112/backoff_nook/issue_goal()
	return

/datum/bot_scenario/fixes1112/backoff_nook/post_spawn()
	griefer = stand_in(first_marker("C"), "Griff Griefer")
	griefer.mind_initialize()
	griefer.mind.assigned_role = "Assistant"
	griefer.setDir(get_dir(griefer, bot))
	RegisterSignal(bot, COMSIG_MOVABLE_MOVED, PROC_REF(sci_stepped))
	addtimer(CALLBACK(src, PROC_REF(sci_suit_up)), 2 SECONDS)

/// As /datum/bot_scenario/griefed/officer does it: the suit on, the crime on file, and the arrest begun by an officer on its own.
/datum/bot_scenario/fixes1112/backoff_nook/proc/sci_suit_up()
	if(result != BOT_GYM_PENDING || QDELETED(griefer))
		return
	var/obj/item/clothing/suit/space/hardsuit/nano/N = new(griefer.loc)
	griefer.equip_to_slot_if_possible(N, ITEM_SLOT_OCLOTHING, FALSE, TRUE, TRUE)
	brain.file_crime(griefer, "Murder", "Gym.", BOT_CRIME_MURDER)
	brain.begin_arrest(griefer)

/datum/bot_scenario/fixes1112/backoff_nook/proc/sci_stepped(atom/movable/mover, atom/old_loc)
	SIGNAL_HANDLER
	if(result != BOT_GYM_PENDING || QDELETED(griefer))
		return
	moves++
	var/turf/was = get_turf(old_loc)
	var/turf/now = get_turf(mover)
	var/turf/them = get_turf(griefer)
	if(was && now && them && (now.x - them.x) ** 2 + (now.y - them.y) ** 2 < (was.x - them.x) ** 2 + (was.y - them.y) ** 2)
		closer++

/datum/bot_scenario/fixes1112/backoff_nook/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(closer)
		fail_reason = "stepped back towards the suit [closer] time\s ([moves] step\s in all)"
		return BOT_GYM_FAIL
	if(moves > 2)
		fail_reason = "in and out of the nook: [moves] steps"
		return BOT_GYM_FAIL
	if(world.time <= start_time + 15 SECONDS)
		return BOT_GYM_PENDING
	if(!bot_transcript_said("holding back from"))
		fail_reason = "never held back from the suit"
		return BOT_GYM_FAIL
	return brain.state == BOT_STATE_ARREST ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/fixes1112/backoff_nook/release_run()
	if(bot)
		UnregisterSignal(bot, COMSIG_MOVABLE_MOVED)
	if(griefer)
		bot_clear_wanted(griefer)
	return ..()

// <<< antags_eva_scenarios.dm
// ---------------------------------------------------------------------------------------------
// Antagonists, getting away, pets, raids and EVA (fixes 2026-11-12)
// ---------------------------------------------------------------------------------------------

/// Driven by one duty, as /datum/bot_scenario/duty is (scenarios_duties.dm): asked once a second while the bot is idle.
/datum/bot_scenario/fixes1112/ae_duty
	max_goal_attempts = 10
	var/duty_type

/datum/bot_scenario/fixes1112/ae_duty/issue_goal()
	var/datum/bot_duty/D = bot_duty_of(duty_type)
	if(!D)
		log_line("no such duty: [duty_type]")
		return
	if(D.try_start(brain))
		goal_attempts++
		log_line("[D.name]: started on [brain.current_goal ? brain.current_goal.type : "it"] (attempt [goal_attempts]/[max_goal_attempts])")

/// The step the bot's goal is on, or null.
/datum/bot_scenario/fixes1112/proc/ae_current_step()
	var/datum/bot_strategy/S = brain?.current_strategy
	if(!S || brain.current_step_index < 1 || brain.current_step_index > length(S.steps))
		return null
	return S.steps[brain.current_step_index]

// Traitors (goals/traitor.dm), as /datum/bot_scenario/duty/traitor (scenarios_traitor.dm): the real antagonist datum, with the
// scenario's own objectives.

/datum/bot_scenario/fixes1112/ae_duty/traitor
	duty_type = /datum/bot_duty/traitor
	job = "Assistant"
	time_limit = 90 SECONDS
	var/datum/antagonist/traitor/antag

/datum/bot_scenario/fixes1112/ae_duty/traitor/post_spawn()
	give_job_id(list())
	brain.set_playstyle(BOT_STYLE_NORMAL)
	antag = brain.become_traitor() //no PDA on a gym bot: the uplink goes in a pen
	antag.objectives.Cut()

/datum/bot_scenario/fixes1112/ae_duty/traitor/proc/set_steal_objective(item_type)
	var/datum/objective/steal/S = new
	S.owner = bot.mind
	S.steal_target = item_type
	S.explanation_text = "Steal [item_type]"
	antag.objectives += S

/datum/bot_scenario/fixes1112/ae_duty/traitor/proc/set_kill_objective(mob/living/carbon/human/victim)
	var/datum/objective/assassinate/A = new
	A.owner = bot.mind
	if(!victim.mind)
		victim.mind_initialize()
	A.target = victim.mind
	A.explanation_text = "Assassinate [victim.real_name]"
	antag.objectives += A

/// The card or a sword lying on the floor more than a step from the bot, or null.
/datum/bot_scenario/fixes1112/ae_duty/traitor/proc/kit_left_lying()
	for(var/turf/T as anything in reservation?.reserved_turfs)
		for(var/obj/item/I in T)
			if((istype(I, /obj/item/card/emag) || istype(I, /obj/item/melee/transforming/energy/sword)) && get_dist(I, bot) > 1)
				return I
	return null

/datum/bot_scenario/fixes1112/ae_duty/traitor/keeps_its_kit
	name = "traitor: hands and bag full, it makes room for what it buys and takes the card and the sword through the door"
	desc = "A toolbox in each hand and a bag full of metal. The emag and the sword off the uplink come into a hand it's freed, not down on the floor, and go in its pockets; the card gets it through a door its ID doesn't open and the sword does the job. Batch 2026-11-12: a cook with a boiled egg and its emag in its hands bought an energy sword that landed at its feet, logged that it had bought nothing, and punched its target for 17 seconds until Security came (Kit Brannigan, run8); another set its new sword down at the first door it swiped and punched a Security Officer (Parker Osei, run5)."
	layout = list(
		"#########",
		"#B..D..V#",
		"#########")
	time_limit = 120 SECONDS
	kit_hands = list(/obj/item/storage/toolbox/mechanical, /obj/item/storage/toolbox/mechanical)
	var/mob/living/carbon/human/victim

/datum/bot_scenario/fixes1112/ae_duty/traitor/keeps_its_kit/setup()
	var/obj/machinery/door/airlock/A = first_placed("D")
	A.req_access = list(ACCESS_CAPTAIN)

/datum/bot_scenario/fixes1112/ae_duty/traitor/keeps_its_kit/post_spawn()
	..()
	var/obj/item/storage/bag = bot.get_item_by_slot(ITEM_SLOT_BACK)
	for(var/i in 1 to 7)
		SEND_SIGNAL(bag, COMSIG_TRY_STORAGE_INSERT, new /obj/item/stack/sheet/metal(bot.loc), bot, TRUE, TRUE)
	victim = stand_in(first_marker("V"), "Vic Tim")
	set_kill_objective(victim)

/datum/bot_scenario/fixes1112/ae_duty/traitor/keeps_its_kit/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("bought nothing off the uplink"))
		fail_reason = "what it bought landed at its feet and stayed there"
		return BOT_GYM_FAIL
	var/obj/item/left = kit_left_lying()
	if(left)
		fail_reason = "left [left] on the floor [get_dist(left, bot)] tiles back"
		return BOT_GYM_FAIL
	if(QDELETED(victim) || victim.stat != DEAD || brain.state != BOT_STATE_WANDER)
		return BOT_GYM_PENDING
	var/obj/machinery/door/airlock/A = first_placed("D")
	if(QDELETED(A) || !(A.obj_flags & EMAGGED))
		fail_reason = "got to them, but not with the card"
		return BOT_GYM_FAIL
	if(!brain.find_carried_tool(/obj/item/melee/transforming/energy/sword) || !brain.find_carried_tool(/obj/item/card/emag))
		fail_reason = "did the job without its card and its sword on it"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/fixes1112/ae_duty/traitor/keeps_its_loot
	name = "traitor: no bag and its pockets full, it keeps hold of the medal box it stole rather than set it down for a sword"
	desc = "No bag, a pen and a sheet of paper in its pockets, the emag in one hand and the Captain's medal box it has stolen in the other. Nothing it holds is set down for a sword: it goes for its target with what it has, the box still in its hand. Batch 2026-11-12: a cook with no backpack set the medal box down to pick up the energy sword it had bought, walked off to the Brig without it, and finished the shift with the medal not stolen (Jude Marlowe, run1)."
	layout = list(
		"#############",
		"#B.........V#",
		"#############")
	time_limit = 60 SECONDS
	kit_hands = list(/obj/item/card/emag, /obj/item/storage/lockbox/medal)
	var/mob/living/carbon/human/victim
	var/obj/item/storage/lockbox/medal/box

/datum/bot_scenario/fixes1112/ae_duty/traitor/keeps_its_loot/post_spawn()
	// Pockets filled before the role's handed out, so the uplink goes in the pen there: the bag is going.
	bot.equip_to_slot_or_del(new /obj/item/pen(bot), ITEM_SLOT_LPOCKET)
	bot.equip_to_slot_or_del(new /obj/item/paper(bot), ITEM_SLOT_RPOCKET)
	..()
	qdel(bot.back)
	box = locate(/obj/item/storage/lockbox/medal) in bot.held_items
	var/obj/item/card/emag/E = locate() in bot.held_items
	if(bot.get_active_held_item() != E)
		bot.swap_hand() //the box in the other hand, the one a full-handed pickup frees (make_room_for_item())
	victim = stand_in(first_marker("V"), "Vic Tim")
	set_steal_objective(/obj/item/clothing/accessory/medal/gold/captain)
	set_kill_objective(victim)

/datum/bot_scenario/fixes1112/ae_duty/traitor/keeps_its_loot/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(box))
		fail_reason = "the medal box is gone"
		return BOT_GYM_FAIL
	if(isturf(box.loc) && get_dist(box, bot) > 1)
		fail_reason = "set the medal box down and walked off [get_dist(box, bot)] tiles from it"
		return BOT_GYM_FAIL
	if(QDELETED(victim) || (victim.stat == CONSCIOUS && !victim.getBruteLoss()))
		return BOT_GYM_PENDING
	return (box in bot.GetAllContents()) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/fixes1112/ae_duty/traitor/keeps_its_loot/on_timeout()
	fail_reason = "never went for its target (timed out after [time_limit / 10]s)"
	return BOT_GYM_FAIL

/datum/bot_scenario/fixes1112/ae_duty/traitor/through_a_windoor
	name = "traitor: swipes the card through a windoor its ID doesn't open, to what it's after"
	desc = "A hand teleporter behind a windoor for the Captain. The emag opens a windoor as it does an airlock: it walks up, swipes it, and takes the teleporter, with nothing broken. Batch 2026-11-12: on MetaStation the Captain's desk is glass with two windoors in it, and traitors after the jetpack behind it found no path 14 times (Nico Faulkner run2, Ray Dubois run4)."
	layout = list(
		"#########",
		"#B..o..I#",
		"#########")
	time_limit = 120 SECONDS
	var/obj/machinery/door/window/windoor

/datum/bot_scenario/fixes1112/ae_duty/traitor/through_a_windoor/setup()
	windoor = new(first_marker("o"))
	windoor.setDir(WEST) //faces the bot: stepping on to its tile crosses the glass
	windoor.req_access = list(ACCESS_CAPTAIN)
	place("o", windoor)
	for(var/turf/T in markers["I"])
		place("I", new /obj/item/hand_tele(T))

/datum/bot_scenario/fixes1112/ae_duty/traitor/through_a_windoor/post_spawn()
	..()
	set_steal_objective(/obj/item/hand_tele)

/datum/bot_scenario/fixes1112/ae_duty/traitor/through_a_windoor/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("giving up on /datum/bot_goal/traitor_steal"))
		fail_reason = "found no way past the windoor and gave the theft up"
		return BOT_GYM_FAIL
	if(!(locate(/obj/item/hand_tele) in bot.GetAllContents()))
		return BOT_GYM_PENDING
	if(QDELETED(windoor) || !(windoor.obj_flags & EMAGGED) || windoor.obj_integrity < windoor.max_integrity)
		fail_reason = "got it, but not with the card"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/fixes1112/ae_duty/traitor/hijacker_suits_up
	name = "robust: a hijacker going in a nanosuit spends its crystals on the suit, not a sword first"
	desc = "A robust traitor on a rampage, with Hijack among its objectives. It goes shopping and comes away in a nanosuit, with no sword: the suit is all twenty crystals. Batch 2026-11-12: both of run3's rampage hijackers bought the sword first, couldn't buy a nanosuit, and were cuffed in their jumpsuits within a minute (Corey Ishikawa, Charlie Vasquez)."
	time_limit = 60 SECONDS
	layout = list(
		"#####",
		"#B..#",
		"#####")

/datum/bot_scenario/fixes1112/ae_duty/traitor/hijacker_suits_up/post_spawn()
	..()
	brain.set_playstyle(BOT_STYLE_ROBUST)
	brain.traitor_plan = BOT_TRAITOR_RAMPAGE
	var/datum/objective/hijack/O = new
	O.owner = bot.mind
	antag.objectives += O

/datum/bot_scenario/fixes1112/ae_duty/traitor/hijacker_suits_up/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(brain.find_carried_tool(/obj/item/melee/transforming/energy/sword))
		fail_reason = "spent its crystals on a sword"
		return BOT_GYM_FAIL
	if(bot_transcript_said("couldn't buy a nanosuit"))
		fail_reason = "couldn't afford the nanosuit"
		return BOT_GYM_FAIL
	var/obj/item/clothing/suit/space/hardsuit/nano/N = brain.nanosuit_on()
	if(!N || !brain.traitor_shopped || brain.state != BOT_STATE_WANDER)
		return BOT_GYM_PENDING
	if(!bot.wear_id)
		fail_reason = "left its ID on the floor"
		return BOT_GYM_FAIL
	return bot.back ? BOT_GYM_PASS : BOT_GYM_PENDING

// Pets (goals/leisure.dm), as /datum/bot_scenario/duty/leisure/pet (scenarios_leisure.dm): corgis that stay put on each i.

/datum/bot_scenario/fixes1112/ae_duty/pet
	duty_type = /datum/bot_duty/pet_animal
	job = "Assistant"
	time_limit = 40 SECONDS
	/// The dog furthest from where the bot starts: the one it can get to.
	var/mob/living/simple_animal/pet/dog/corgi/far_dog

/datum/bot_scenario/fixes1112/ae_duty/pet/setup()
	var/turf/start = first_marker("B")
	for(var/turf/T in markers["i"])
		var/mob/living/simple_animal/pet/dog/corgi/dog = new(T)
		dog.stop_automated_movement = TRUE
		dog.wander = FALSE
		place("i", dog)
		if(!far_dog || get_dist(start, T) > get_dist(start, far_dog))
			far_dog = dog

/datum/bot_scenario/fixes1112/ae_duty/pet/post_spawn()
	give_job_id()

/datum/bot_scenario/fixes1112/ae_duty/pet/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	for(var/mob/living/simple_animal/dog in placed["i"])
		if(QDELETED(dog) || dog.stat == DEAD || dog.health < dog.maxHealth)
			fail_reason = "hurt a dog"
			return BOT_GYM_FAIL
	if(bot_transcript_said("giving up on /datum/bot_goal/pet_animal"))
		fail_reason = "set off for a dog it couldn't get to, and gave it up"
		return BOT_GYM_FAIL
	return (brain.animals_petted && brain.state == BOT_STATE_WANDER && get_dist(bot, far_dog) <= 1) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/fixes1112/ae_duty/pet/behind_glass
	name = "leisure: the animal lover pets the dog it can get to, not the nearer one behind the glass"
	desc = "Two corgis: the nearer shut in behind a window, as Runtime is in the CMO's office, and one across the room. It goes to the one across the room. Batch 2026-11-12: 32 of 43 pets given up on were the head's or performer's pet seen through office glass (Runtime 13, Poly 10, Ian 4), set off for and given up at the end of the route search (Jo Sandoval run2, Reese Tanaka run1)."
	layout = list(
		"#######",
		"#i#####",
		"#w#####",
		"#.....#",
		"#B....#",
		"#....i#",
		"#######")

/datum/bot_scenario/fixes1112/ae_duty/pet/glass_side
	name = "leisure: the animal lover pets the dog from an open side, not across the window on its tile"
	desc = "A corgi with a window on the side of its tile that faces the bot, as the cow is in its pen. It walks round to a side it can reach it from, and pets it. Batch 2026-11-12: the cow on Hippie Station was walked up to on the glass side and the petting failed there 6 times, and Ian on the HoP's desk windoor twice (Casey Nakamura run1, Avery Solano run12)."
	layout = list(
		"#########",
		"#.......#",
		"#B...i..#",
		"#.......#",
		"#########")

/datum/bot_scenario/fixes1112/ae_duty/pet/glass_side/setup()
	..()
	place("glass", new /obj/structure/window/reinforced(get_turf(far_dog), WEST))

// Raids (bot_departments.dm), as /datum/bot_scenario/raid (scenarios_depts.dm): a greytider after insulated gloves on each y.

/datum/bot_scenario/fixes1112/ae_raid
	max_goal_attempts = 1
	kit_backpack = list(/obj/item/screwdriver, /obj/item/multitool)

/datum/bot_scenario/fixes1112/ae_raid/build_tile(turf/T, char)
	if(char == "y")
		place(char, new /obj/item/clothing/gloves/color/yellow(T))
		return
	..()

/datum/bot_scenario/fixes1112/ae_raid/post_spawn()
	brain.greytider = TRUE

/datum/bot_scenario/fixes1112/ae_raid/make_goal()
	return new /datum/bot_goal/tide/raid(/obj/item/clothing/gloves/color/yellow)

/datum/bot_scenario/fixes1112/ae_raid/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("giving up on /datum/bot_goal/tide/raid"))
		fail_reason = "set off for gloves it had no way to"
		return BOT_GYM_FAIL
	return istype(bot.gloves, /obj/item/clothing/gloves/color/yellow) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/fixes1112/ae_raid/first_go
	name = "dept: a greytider takes the gloves it can get to the first time, not the walled-up pair nearer it"
	desc = "Insulated gloves walled up three steps off, as on the AI satellite, and another pair across the room. One go at it: it goes for the pair across the room. Batch 2026-11-12: gloves in a toolbox on the AI satellite, across space, were set off for and given up 11 times by six raiders in one shift (run3), 31 of the batch's 51 raids ending on no path."
	time_limit = 40 SECONDS
	layout = list(
		"###########",
		"#..#y#....#",
		"#B.###...y#",
		"#.........#",
		"###########")

/datum/bot_scenario/fixes1112/ae_raid/out_again
	name = "dept: a greytider shut in when the raid comes to mind doesn't write the gloves off, and gets them once it's out"
	desc = "The bot is behind a welded door when it thinks of the gloves down the corridor, and there's no way to them. Then the door's unwelded, and once its last look round has gone stale it tries again, and gets them. Batch 2026-11-12: prisoners in the Brig and a bot shut in a pocket of the Bridge made 6 of the raids that ended on no path (Shay Okonkwo run8, three times), and a raider remembers a place it couldn't reach for ten minutes."
	time_limit = 60 SECONDS
	max_goal_attempts = 3
	layout = list(
		"#########",
		"#BX....y#",
		"#########")
	var/opened_at = 0

/datum/bot_scenario/fixes1112/ae_raid/out_again/issue_goal()
	// The first go while it's shut in; the next once it's out, and the region it last searched (kept 20 seconds, BOT_REGION_FLOOD_TTL,
	// bot_pathing_permissive.dm) has gone stale.
	if(goal_attempts && (!opened_at || world.time < opened_at + 25 SECONDS))
		return
	..()

/datum/bot_scenario/fixes1112/ae_raid/out_again/check()
	if(!opened_at && world.time >= start_time + 3 SECONDS)
		var/obj/machinery/door/airlock/A = first_placed("X")
		if(A)
			A.welded = FALSE
			A.update_icon()
		opened_at = world.time
		log_line("the door's unwelded")
	return ..()

// Keeping clear of a bomb (bot_fighting.dm), as /datum/bot_scenario/bomber_crew and /datum/bot_scenario/defuses_bomb/runs
// (scenarios_sabotage.dm). The bot isn't scripted: it has to see the bomb for itself.

/datum/bot_scenario/fixes1112/ae_bomber
	job = "Assistant"
	time_limit = 45 SECONDS
	var/mob/living/carbon/human/bomber

/datum/bot_scenario/fixes1112/ae_bomber/make_goal()
	return null

/datum/bot_scenario/fixes1112/ae_bomber/post_spawn()
	brain.gym_scripted = FALSE //a scripted bot has no reflexes
	bomber = stand_in(first_marker("M"), "Bo Bomber")
	bot_gym_dead_mans_bomb(bomber)

/datum/bot_scenario/fixes1112/ae_bomber/walks_up_again
	name = "bomb: got away from somebody holding a tank bomb, and they walk up again: it gets away again, not stood where it ran to"
	desc = "Somebody holding a tank bomb on a dead man's switch. The bot gets ten tiles off and keeps clear; then they walk up to three tiles of where it stopped. It gets away again. Batch 2026-11-12: a traitor scientist carried one about Science, and the Head of Personnel, who had run to a spot ten tiles off, stood there while he came and worked four tiles away and walked past, until the goal was failed for going quiet three minutes on (Rowan Kessler, run5)."
	layout = list(
		"#########################################",
		"#...................B..M................#",
		"#.......................................#",
		"#########################################")
	var/walked_up = FALSE

/datum/bot_scenario/fixes1112/ae_bomber/walks_up_again/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("has gone quiet"))
		fail_reason = "stood where it had run to until the goal was failed for going quiet"
		return BOT_GYM_FAIL
	if(!walked_up)
		if(istype(brain.current_goal, /datum/bot_goal/run_from) && istype(ae_current_step(), /datum/bot_step/paced/keep_clear) && get_dist(bot, bomber) >= 8)
			var/turf/T = locate(bot.x + 3, bot.y, bot.z)
			if(T && !T.density && T.loc == arena_area)
				bomber.forceMove(T)
				walked_up = TRUE
				log_line("[bomber] walks up to three tiles of it")
		return BOT_GYM_PENDING
	return get_dist(bot, bomber) >= 8 ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/fixes1112/ae_bomber/walks_up_again/on_timeout()
	fail_reason = walked_up ? "stood [get_dist(bot, bomber)] tiles from the bomb, where it had run to" : "never got clear of the bomb to begin with"
	return BOT_GYM_FAIL

/datum/bot_scenario/fixes1112/ae_bomber/back_to_it
	name = "bomb: away from somebody who goes on holding a tank bomb, it's back to its rounds inside half a minute"
	desc = "Somebody holding a tank bomb on a dead man's switch, who stays where they are. The bot gets well away, and with nothing counting down it's back to its own business inside half a minute, the run done, not failed. Batch 2026-11-12: everybody who saw a traitor scientist's tank bomb stood where they'd run to until the run was failed for going quiet, 3 minutes each, 7 times in run5, and 4 more stood still for 1m29s to 2m37s."
	layout = list(
		"#########################",
		"#.........B..M..........#",
		"#.......................#",
		"#########################")
	var/got_clear = FALSE

/datum/bot_scenario/fixes1112/ae_bomber/back_to_it/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("has gone quiet"))
		fail_reason = "stood where it had run to until the goal was failed for going quiet"
		return BOT_GYM_FAIL
	if(get_dist(bot, bomber) >= 8)
		got_clear = TRUE
	return (got_clear && bot_transcript_said("goal /datum/bot_goal/run_from succeeded")) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/fixes1112/ae_bomber/back_to_it/on_timeout()
	fail_reason = got_clear ? "still stood where it ran to, [get_dist(bot, bomber)] tiles off" : "never got clear of the bomb"
	return BOT_GYM_FAIL

/datum/bot_scenario/fixes1112/ae_bomb_waits_out_timer
	name = "bomb: keeps clear of a timed tank bomb until its timer has run out, not a minute and back"
	desc = "A guard for the fix above: a tank bomb with 40 ticks on its timer (80 seconds, a tick every two seconds). A timid assistant gets well away and stays away until the timer has run out. Capping every wait at a minute had it back at its rounds with the timer still going; a saboteur's fuse is two minutes. It passes before the fix and after."
	job = "Assistant"
	time_limit = 110 SECONDS
	layout = list(
		"#######################",
		"#.......B...g.........#",
		"#.....................#",
		"#######################")
	var/obj/item/transfer_valve/bomb
	var/got_clear = FALSE

/datum/bot_scenario/fixes1112/ae_bomb_waits_out_timer/make_goal()
	return null

/datum/bot_scenario/fixes1112/ae_bomb_waits_out_timer/post_spawn()
	brain.gym_scripted = FALSE //a scripted bot has no reflexes
	brain.nerve = 0.2
	brain.next_wander_time = world.time + 5 MINUTES //no stroll first: one walked off past the bomb before it had seen it, and back
	bomb = bot_gym_tank_bomb(first_marker("g"), TRUE, 40)

/datum/bot_scenario/fixes1112/ae_bomb_waits_out_timer/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(bomb))
		fail_reason = "the bomb's gone"
		return BOT_GYM_FAIL
	var/obj/item/assembly/timer/fuse = bomb.attached_device
	if(!istype(fuse))
		fail_reason = "went and pulled the timer, with no nerve for it"
		return BOT_GYM_FAIL
	if(!fuse.timing)
		if(got_clear)
			return BOT_GYM_PASS
		fail_reason = "the timer ran out with it [get_dist(bot, bomb)] tiles off"
		return BOT_GYM_FAIL
	if(get_dist(bot, bomb) >= 8 && bot_transcript_said("getting away from")) //clear by running from it, not by where a stroll took it
		got_clear = TRUE
	else if(got_clear && get_dist(bot, bomb) < 8)
		fail_reason = "came back to [get_dist(bot, bomb)] tiles of it with [fuse.time] ticks on the timer"
		return BOT_GYM_FAIL
	if(bot_transcript_said("goal /datum/bot_goal/run_from succeeded"))
		fail_reason = "stopped keeping clear with [fuse.time] ticks on the timer"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/fixes1112/ae_bomb_waits_out_timer/release_run()
	if(!QDELETED(bomb))
		qdel(bomb)
	return ..()

// Running from somebody (bot_fighting.dm), as /datum/bot_scenario/runs_in_thin_air (scenarios_asks.dm).

/datum/bot_scenario/fixes1112/ae_runs_where_it_can
	name = "survival: running from somebody, it runs somewhere it can get to, not to a spot behind a door that won't open"
	desc = "Something it means to get away from is two tiles off. Past a door for the Captain (and the bot has no ID) there's a room with more space in it than anything on the bot's side, and no way in. It runs to the end of the corridor it has. Batch 2026-11-12: 47 of 133 runs from danger were given up the moment they began, the spot picked being somewhere the bot had no route to (the Armory, Xenobiology, the Captain's office, a hallway past a door it couldn't open), and the bot was left beside what it meant to get away from (Jean Kovac run2, Blake Ferreira run4, five times)."
	job = "Assistant"
	time_limit = 20 SECONDS
	layout = list(
		"###############",
		"#K.B.D........#",
		"######........#",
		"######........#",
		"######........#",
		"###############")
	var/mob/living/carbon/human/foe

/// A door its ID doesn't open, not a welded one: when this was written the route planner counted a welded airlock that wants no access as
/// a way through, and the bot walked up to it and gave the run up there, a run in three (fixed since: bot_doors.dm CanAStarPass()).
/datum/bot_scenario/fixes1112/ae_runs_where_it_can/setup()
	var/obj/machinery/door/airlock/A = first_placed("D")
	A.req_access = list(ACCESS_CAPTAIN)

/datum/bot_scenario/fixes1112/ae_runs_where_it_can/post_spawn()
	foe = stand_in(first_marker("K"), "Big Beast")
	addtimer(CALLBACK(brain, TYPE_PROC_REF(/datum/bot_brain, run_from), foe, "the gym"), 1 SECONDS)

/datum/bot_scenario/fixes1112/ae_runs_where_it_can/make_goal()
	return null //running is the job

/datum/bot_scenario/fixes1112/ae_runs_where_it_can/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("giving up on /datum/bot_goal/run_from"))
		fail_reason = "picked somewhere it had no way to, and didn't run"
		return BOT_GYM_FAIL
	if(!bot_transcript_said("trying /datum/bot_strategy/run_from"))
		return BOT_GYM_PENDING
	if(get_dist(bot, foe) < 2)
		fail_reason = "ran towards it"
		return BOT_GYM_FAIL
	return (get_dist(bot, foe) >= 3 && bot_transcript_said("goal /datum/bot_goal/run_from succeeded")) ? BOT_GYM_PASS : BOT_GYM_PENDING

// EVA (goals/space_ruins.dm), as /datum/bot_scenario/space_suit_up/cased (scenarios_asks.dm): Meta's jetpack case.

/datum/bot_scenario/fixes1112/ae_jetpack_heads_only
	name = "pursuits: the jetpack case is for heads of staff and there's no AI to ask: no jetpack counted on, and a head's still is"
	desc = "A jetpack on a rack behind a windoor for heads of staff, a window between it and the suit storage unit beside it, and no AI in the round. The jetpack isn't counted as one to be had: not from across the room, not stood at the case, not with the unit beside it opened. Given a head's access, it is. Batch 2026-11-12: on MetaStation 38 of 39 suit-ups were given up, explorers taking a suit out of EVA's units and walking up to the case to find no jetpack to be had there (Parker Osei, Robin Castellanos run2), and 37 asks for EVA access left at the HoP's door. It changes whether there's an AI to ask, so it runs on its own."
	job = "Assistant"
	station_wide = TRUE //an AI in another arena would be somebody to ask
	time_limit = 30 SECONDS
	layout = list(
		"#########",
		"#B.....j#",
		"#......U#",
		"#########")
	var/stage = 0
	var/obj/item/tank/jetpack/jetpack
	var/turf/front

/datum/bot_scenario/fixes1112/ae_jetpack_heads_only/setup()
	for(var/turf/T in markers["U"])
		place("U", new /obj/machinery/suit_storage_unit/standard_unit(T))
	var/turf/case_at = first_marker("j")
	place("j", new /obj/structure/rack(case_at))
	jetpack = new /obj/item/tank/jetpack/carbondioxide(case_at)
	place("j", jetpack)
	var/obj/machinery/door/window/W = new(case_at)
	W.setDir(WEST)
	W.req_access = list(ACCESS_HEADS)
	place("j", W)
	place("j", new /obj/structure/window/reinforced(case_at, SOUTH)) //the unit's side: opened, it's no way to the rack
	front = get_step(case_at, WEST)

/datum/bot_scenario/fixes1112/ae_jetpack_heads_only/make_goal()
	return null //the question is what try_space_ruin() asks before it sends anybody for a suit

/datum/bot_scenario/fixes1112/ae_jetpack_heads_only/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	switch(stage)
		if(0)
			if(brain.nearest_free_jetpack())
				fail_reason = "counted on a jetpack in a case its ID doesn't open, with no AI to ask"
				return BOT_GYM_FAIL
			if(hascall(brain, "jetpack_to_hope_for") && call(brain, "jetpack_to_hope_for")())
				fail_reason = "hoped for a jetpack in a case its ID doesn't open, with no AI to ask"
				return BOT_GYM_FAIL
			stage = 1
			log_line("walking up to the case")
			brain.pursue(front, "follow", force = TRUE)
			return BOT_GYM_PENDING
		if(1)
			if(get_turf(bot) != front)
				return BOT_GYM_PENDING
			if(brain.nearest_free_jetpack())
				fail_reason = "stood at the case, counted on the jetpack in it"
				return BOT_GYM_FAIL
			var/obj/machinery/suit_storage_unit/U = first_placed("U")
			U.open_machine(0)
			log_line("the unit beside the rack is opened")
			if(brain.nearest_free_jetpack())
				fail_reason = "with the unit beside the rack open, counted on the jetpack through the window"
				return BOT_GYM_FAIL
			stage = 2
			give_job_id(list(ACCESS_HEADS))
			log_line("given a head's access")
			return BOT_GYM_PENDING
	if(brain.nearest_free_jetpack() != jetpack)
		fail_reason = "with a head's access, didn't count on the jetpack in the case"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

// <<< cargo_scenarios.dm
// ---------------------------------------------------------------------------------------------
// Cargo (fixes 2026-11-12): the supply shuttle's air through a flight, and the airlock checks at its dock
// ---------------------------------------------------------------------------------------------

/// supply-shuttle-vented-by-loading-doors (door_seals.dm /turf/lateShuttleMove(), goals/cargo.dm supply_shuttle_airless()). The station's own
/// supply shuttle is called in from CentCom and flies through transit, so this runs alone (station_wide) on whatever station the round has:
/// the testbench by default, and bot-map=metastation for MetaStation's dock, where the station side of the dock is the part that's judged.
/// The bot is moved from its arena into the station's cargo bay.
/datum/bot_scenario/fixes1112/shuttle_air
	name = "cargo shuttle: it docks with its air in, and cargo walks aboard by the airlocks and leaves the loading doors shut"
	desc = "The supply shuttle flies in from CentCom with two crates aboard. Its hull doors come in sharing the cabin's air, and so does the station side of the dock. One crate is set aside, as after a walk out to it that came to nothing, and for ten seconds so is the other: the cargo technician, asked by the cargo round all the while, doesn't open the loading doors or call Engineering about the air. Then it walks aboard through the dock's airlocks and unloads the other crate into the bay. Batch bugs1112base: 'no path to the shuttle floor' on the first trip in 10 shifts of 12 with good air in the cabin (run1 Wren Gallagher 16:07:26), the loading doors opened for it (16:07:36), and the shuttle flew back open to space: crates sat aboard from the second trip to the end of the shift in runs 1, 4, 5, 7, 9, 10 and 12, and Science's silver came round once in 12."
	job = "Cargo Technician"
	time_limit = 210 SECONDS
	max_goal_attempts = 10
	station_wide = TRUE //the station's own supply shuttle, called in from CentCom
	layout = list(
		"#####",
		"#B..#",
		"#####")
	/// Unloaded once the first ten seconds at the dock are up
	var/obj/structure/closet/crate/fetched
	/// Set aside for the whole run, as after a walk out to it that came to nothing
	var/obj/structure/closet/crate/set_aside
	var/setup_problem
	var/docked_at
	var/reach_checked = FALSE
	var/station_checked = FALSE
	/// Times the cargo round was asked while both crates were set aside, with the loading doors' button in reach
	var/asks_in_hold = 0
	/// Blast doors on and beside the docked shuttle, all shut when it came in
	var/list/obj/machinery/door/poddoor/loading_doors
	var/saved_last_order
	var/saved_air_asked

/datum/bot_scenario/fixes1112/shuttle_air/setup()
	saved_last_order = GLOB.bot_cargo_last_order
	saved_air_asked = GLOB.bot_cargo_air_asked
	GLOB.bot_cargo_last_order = world.time //no staples ordered while it runs: not what's judged here
	var/obj/docking_port/mobile/supply/S = SSshuttle.supply
	if(!S || S.mode != SHUTTLE_IDLE || S.getDockedId() != "supply_away")
		setup_problem = "setup: the supply shuttle isn't sat idle at CentCom ([S ? "[S.mode] at [S.getDockedId()]" : "no supply shuttle"])"
		return
	var/list/turf/spots = list()
	for(var/area/A as anything in S.shuttle_areas)
		for(var/turf/open/floor/T in A)
			if(T.z != S.z || is_blocked_turf(T, TRUE) || (locate(/obj/machinery/door) in range(1, T)) || (locate(/obj/machinery/conveyor) in T))
				continue
			if(!T.air || T.air.return_pressure() < 90) //the airless plating by its engines is the shuttle's area as well
				continue
			spots += T
	if(length(spots) < 2)
		setup_problem = "setup: no room aboard the supply shuttle for two crates"
		return
	fetched = new(spots[1])
	set_aside = new(spots[length(spots)])
	if(SSshuttle.moveShuttle("supply", "supply_home", TRUE)) //timed: through transit, as the console calls it
		setup_problem = "setup: the supply shuttle wouldn't take the call"

/datum/bot_scenario/fixes1112/shuttle_air/post_spawn()
	..()
	give_job_id(list(ACCESS_CARGO))
	if(set_aside)
		LAZYSET(brain.cargo_blocked, set_aside, world.time + 30 MINUTES)
	// Into the station's cargo bay, on the floor nearest the dock that isn't by a door or on a belt
	var/obj/docking_port/stationary/home = SSshuttle.getDock("supply_home")
	var/area/bay = GLOB.areas_by_type[/area/quartermaster/storage]
	var/turf/start
	if(home && bay)
		for(var/turf/open/floor/T in bay)
			if(T.z != home.z || is_blocked_turf(T, TRUE) || (locate(/obj/machinery/door) in range(1, T)) || (locate(/obj/machinery/conveyor) in T))
				continue
			if(!start || get_dist(T, home) < get_dist(start, home))
				start = T
	if(!start)
		setup_problem = setup_problem || "setup: no floor in the cargo bay to start on"
		return
	bot.forceMove(start)
	log_line("bot moved to the cargo bay at [bot_coord(start)]")

/// The cargo round asks itself every second the bot is idle (as /datum/bot_scenario/duty/issue_goal(), scenarios_duties.dm)
/datum/bot_scenario/fixes1112/shuttle_air/issue_goal()
	if(setup_problem)
		return
	if(docked_at && reach_checked && LAZYACCESS(brain.cargo_blocked, fetched) > world.time)
		asks_in_hold++
	var/datum/bot_duty/D = bot_duty_of(/datum/bot_duty/cargo)
	if(D && D.try_start(brain))
		goal_attempts++
		log_line("cargo: started on [brain.current_goal ? brain.current_goal.type : "it"] (attempt [goal_attempts]/[max_goal_attempts])")

/// The docked supply shuttle's own turfs, as an assoc list
/datum/bot_scenario/fixes1112/shuttle_air/proc/aboard_turfs()
	. = list()
	var/obj/docking_port/mobile/supply/S = SSshuttle.supply
	for(var/turf/T as anything in S.return_turfs())
		if(S.shuttle_areas[T.loc])
			.[T] = TRUE

/// Every shut door aboard shares its tile's air with a floor tile of the shuttle that has no shut door on it, and that air can be breathed
/datum/bot_scenario/fixes1112/shuttle_air/proc/hull_door_problem()
	var/list/aboard = aboard_turfs()
	var/doors = 0
	for(var/turf/open/T in aboard)
		var/obj/door
		for(var/obj/O in T)
			if(O.seals_shut && O.density)
				door = O
				break
		if(!door)
			continue
		doors++
		var/turf/side = T.seal_dir > 0 ? get_step(T, T.seal_dir) : null
		if(!isopenturf(side) || !aboard[side] || side.seal_shut())
			return "[door] at [bot_coord(T)] came in sharing its air with [side ? "[side] at [bot_coord(side)][aboard[side] ? ", another shut door" : ", off the shuttle"]" : "nothing"]"
		var/pressure = T.air.return_pressure()
		if(pressure < 80 || !brain.turf_air_is_breathable(T))
			return "[door] at [bot_coord(T)] came in at [round(pressure, 0.1)] kPa"
	if(!doors)
		return "setup: no shut doors aboard the supply shuttle"
	log_line("[doors] shut door\s aboard came in sharing the cabin's air")
	return null

/// The station's external airlocks at the dock (within 2 tiles of the shuttle), and the air each shares with off the shuttle, can be breathed:
/// the dock's chamber on MetaStation was thinned by its loading door's tile of vacuum
/datum/bot_scenario/fixes1112/shuttle_air/proc/station_side_problem()
	var/obj/docking_port/mobile/supply/S = SSshuttle.supply
	var/list/aboard = aboard_turfs()
	var/checked = 0
	for(var/obj/machinery/door/airlock/external/D in GLOB.airlocks)
		var/turf/open/spot = get_turf(D)
		if(!istype(spot) || spot.z != S.z || aboard[spot] || get_dist(D, S) > 15)
			continue
		var/near = FALSE
		for(var/turf/T in range(2, spot))
			if(aboard[T])
				near = TRUE
				break
		if(!near)
			continue
		checked++
		if(!brain.turf_air_is_breathable(spot))
			return "[D] at [bot_coord(spot)] holds [round(spot.air.return_pressure(), 0.1)] kPa nobody could breathe, with the shuttle docked"
		for(var/dir in GLOB.cardinals)
			var/turf/open/side = get_step(spot, dir)
			if(!istype(side) || aboard[side] || isspaceturf(side) || !spot.seal_side_open(dir))
				continue
			if(!brain.turf_air_is_breathable(side))
				return "beside [D] at [bot_coord(spot)], [side] at [bot_coord(side)] holds [round(side.air.return_pressure(), 0.1)] kPa nobody could breathe, with the shuttle docked"
	log_line("[checked] dock airlock\s on the station side, and the air beside them, can be breathed")
	return null

/// The bay's loading blast door onto the docked supply shuttle, shut: the one the cargo round of before 2026-11-12 opened to let the bay's air
/// in (goals/cargo.dm's own finder for it went with that)
/datum/bot_scenario/fixes1112/shuttle_air/proc/loading_door_onto_shuttle()
	var/obj/docking_port/mobile/supply/S = SSshuttle.supply
	if(!S || !bot_supply_shuttle_docked())
		return null
	var/list/aboard = list()
	for(var/turf/T as anything in S.return_turfs())
		aboard[T] = TRUE
	for(var/obj/machinery/door/poddoor/P as anything in bot_instances_of(/obj/machinery/door/poddoor))
		if(QDELETED(P) || P.z != S.z || !P.density || !P.id || aboard[get_turf(P)] || get_dist(P, S) > 20)
			continue
		for(var/d in GLOB.cardinals)
			if(aboard[get_step(P, d)])
				return P //onto the shuttle: its own loading door (Hippie) or its flaps (Meta)
	return null

/// What the cargo round of before the fix needed to open the loading doors: a console, a loading door onto the shuttle, and its button in reach.
/// Without them, its not opening them would prove nothing.
/datum/bot_scenario/fixes1112/shuttle_air/proc/vent_reach_problem()
	if(!brain.find_cargo_console())
		return "setup: no supply console on the station the cargo round could use"
	var/obj/machinery/door/poddoor/gate = loading_door_onto_shuttle()
	if(!gate)
		return "setup: no shut loading blast door onto the docked shuttle"
	if(!brain.blast_door_button_for(gate))
		return "setup: no button for [gate] the bot could get to"
	log_line("the console and the button for [gate] are in reach")
	return null

/datum/bot_scenario/fixes1112/shuttle_air/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(setup_problem)
		fail_reason = setup_problem
		return BOT_GYM_FAIL
	if(!bot_supply_shuttle_docked())
		if(docked_at)
			fail_reason = "the supply shuttle left again before the crate was unloaded"
			return BOT_GYM_FAIL
		return BOT_GYM_PENDING
	if(!docked_at)
		docked_at = world.time
		log_line("the supply shuttle has docked")
		var/problem = hull_door_problem()
		if(problem)
			fail_reason = problem
			return BOT_GYM_FAIL
		loading_doors = list()
		for(var/turf/T as anything in aboard_turfs())
			for(var/turf/near in range(1, T))
				for(var/obj/machinery/door/poddoor/P in near)
					if(P.density)
						loading_doors |= P
		// As after a walk out to it that came to nothing (/datum/bot_goal/unload_crate/on_give_up()): set aside for a moment, with the
		// cabin's air as good as ever. The cargo round is asked meanwhile, with the loading doors and the radio call within its reach.
		LAZYSET(brain.cargo_blocked, fetched, world.time + 10 SECONDS)
		return BOT_GYM_PENDING
	for(var/obj/machinery/door/poddoor/P as anything in loading_doors)
		if(QDELETED(P))
			fail_reason = "a loading door at the dock was destroyed"
			return BOT_GYM_FAIL
		if(!P.density)
			fail_reason = "[P] at [bot_coord(get_turf(P))] was opened on a supply shuttle with its air in"
			return BOT_GYM_FAIL
	if(bot_transcript_said("came in without air"))
		fail_reason = "went to open the loading doors for a supply shuttle with its air in"
		return BOT_GYM_FAIL
	if(bot_transcript_said("air I can't work in"))
		fail_reason = "called Engineering about the air on a supply shuttle with its air in"
		return BOT_GYM_FAIL
	if(!reach_checked && world.time >= docked_at + 2 SECONDS)
		reach_checked = TRUE
		var/problem = vent_reach_problem()
		if(problem)
			fail_reason = problem
			return BOT_GYM_FAIL
	if(!station_checked && world.time >= docked_at + 8 SECONDS)
		station_checked = TRUE
		var/problem = station_side_problem()
		if(problem)
			fail_reason = problem
			return BOT_GYM_FAIL
	if(!station_checked || brain.crates_unloaded < 1 || QDELETED(fetched) || bot_aboard_supply_shuttle(fetched) || !istype(get_area(fetched), /area/quartermaster))
		return BOT_GYM_PENDING
	if(asks_in_hold < 5)
		fail_reason = "the cargo round was asked only [asks_in_hold] time\s while the crates were set aside"
		return BOT_GYM_FAIL
	log_line("unloaded with the loading doors shut, after [asks_in_hold] asks with both crates set aside")
	return BOT_GYM_PASS

/datum/bot_scenario/fixes1112/shuttle_air/on_timeout()
	if(!docked_at)
		fail_reason = "timed out: the supply shuttle never docked"
	else
		fail_reason = "timed out: [brain.crates_unloaded] crate\s unloaded, the one to fetch at [fetched ? bot_coord(get_turf(fetched)) : "nowhere"]"
	return BOT_GYM_FAIL

/datum/bot_scenario/fixes1112/shuttle_air/release_run()
	GLOB.bot_cargo_last_order = saved_last_order
	GLOB.bot_cargo_air_asked = saved_air_asked
	if(bot_supply_shuttle_docked())
		SSshuttle.moveShuttle("supply", "supply_away", TRUE)
	return ..()

/// vacuum-check-reads-doorway-tile (bot_doors.dm /obj/machinery/door/airlock/external/CanAStarPass(), bot_items.dm bot_door_opens_on_vacuum()).
/// The hatch's tile is the pocket a docked shuttle's airlock tile was: vacuum, sharing only with a shut blast door's tile beside it. The room
/// on the bot's side is 15 tiles, so it isn't hemmed in (is_hemmed_in(), bot_movement.dm) and no climbing pass skips the air check.
/datum/bot_scenario/fixes1112/hatch_doorway
	name = "walking: a shut hatch beyond an airlock is a doorway, not a vacuum"
	desc = "An external airlock, a shut hatch straight beyond it, and a small room with air past the hatch, where the screwdriver is: a dock airlock with a docked shuttle's own airlock behind it. The hatch's tile holds vacuum and shares only with a shut blast door's tile beside it. The bot opens the airlock and the hatch and takes the screwdriver, and leaves the blast door shut. Batch bugs1112base: 'pass 1 (legit route) to the shuttle floor: 0 nodes' with good air in the cabin behind the shuttle's airlock (run1 Wren Gallagher 16:07:26, and the same on the first trip in 10 shifts of 12), and 'Supply Dock Airlock opens on to vacuum' with a shut door's tile its only thin neighbour (run8 Avery Solano 16:14:11)."
	job = "Cargo Technician"
	time_limit = 40 SECONDS
	max_goal_attempts = 3
	layout = list(
		"###########",
		"#.....#####",
		"#B....eh.s#",
		"#.....#p###",
		"###########")
	var/obj/item/screwdriver/wanted
	var/obj/machinery/door/poddoor/blast
	var/setup_problem

/datum/bot_scenario/fixes1112/hatch_doorway/setup()
	wanted = new(first_marker("s"))
	var/turf/open/airlock_spot = first_marker("e")
	var/turf/open/hatch_spot = first_marker("h")
	var/turf/open/blast_spot = first_marker("p")
	place("e", new /obj/machinery/door/airlock/external(airlock_spot))
	place("h", new /obj/machinery/door/airlock(hatch_spot))
	blast = place("p", new /obj/machinery/door/poddoor(blast_spot))
	// Each door's tile picked its side as it was made (door_seals.dm): the airlock's took the hatch's tile in the tie. Pinned: the
	// airlock's tile shares with the bot's room, the hatch's with the blast door's tile, and that one with nothing else.
	airlock_spot.seal_dir = WEST
	hatch_spot.seal_dir = SOUTH
	blast_spot.seal_dir = SEAL_PENDING
	for(var/turf/open/T in list(airlock_spot, blast_spot, hatch_spot))
		T.ImmediateCalculateAdjacentTurfs()
	for(var/turf/open/T in list(hatch_spot, blast_spot))
		T.air.parse_gas_string("TEMP=2.7")
		T.update_visuals()
		SSair.add_to_active(T, TRUE)

/// After the two seconds' settling start() gives the arena: the hatch's tile still holds vacuum, and the room past it air
/datum/bot_scenario/fixes1112/hatch_doorway/post_spawn()
	..()
	var/turf/open/hatch_spot = first_marker("h")
	if(hatch_spot.air.return_pressure() > 5)
		setup_problem = "setup: the hatch's tile holds [round(hatch_spot.air.return_pressure(), 0.1)] kPa, not vacuum"
	else if(!brain.turf_air_is_breathable(first_marker("s")))
		setup_problem = "setup: the room past the hatch has no air"

/datum/bot_scenario/fixes1112/hatch_doorway/make_goal()
	var/datum/bot_goal/acquire_item_type/get = new
	get.item_type = /obj/item/screwdriver
	get.lawful = TRUE
	return get

/datum/bot_scenario/fixes1112/hatch_doorway/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(setup_problem)
		fail_reason = setup_problem
		return BOT_GYM_FAIL
	if(QDELETED(blast) || !blast.density)
		fail_reason = "opened the blast door beside the hatch"
		return BOT_GYM_FAIL
	if(LAZYLEN(brain.vacuum_doors))
		fail_reason = "called a doorway a vacuum: [english_list(brain.vacuum_doors)]"
		return BOT_GYM_FAIL
	return (wanted in bot.GetAllContents()) ? BOT_GYM_PASS : BOT_GYM_PENDING

// <<< doors_brig_scenarios.dm
// Bot Gym scenarios for the fixes from Bot Shift batch bugs1112base (2026-11-12). This file goes after every other scenario file; each
// group's scenarios are under /datum/bot_scenario/fixes1112/.

/// The fixes of 2026-11-12. Nothing set: no name or layout, so the runner passes it over.

// ---------------------------------------------------------------------------------------------
// Doors and the Brig: an officer keeping a hurt prisoner for a doctor (goals/security_medevac.dm), a doctor let in at a Security door
// (bot_requests.dm ask_let_in, bot_doors.dm), a shut-in bot let out (bot_requests.dm let_out), a door's button behind a desk (bot_doors.dm).
//
// Layout letters used here: K where the officer keeps the prisoner, C the prisoner or a rescuer, o a doctor's tile or an outer door,
// h a hallway (an /area/hallway of its own), q a patient, s/i side and inner doors, l a lobby or a locker, k a dead end or a door button,
// d a cell door.
// ---------------------------------------------------------------------------------------------

/// Security's side of a door, in an arena (bot_department_of())
/area/bot_gym/fixes1112_sec
	name = "Bot Gym Security"
	department = "security"

/// A hallway in an arena: where a way out of somewhere leads (doors_shutting_me_in()), and where bot_sealed_pocket() stops looking, so a
/// search from inside that finds nothing is remembered (region_floods) as one on the station is
/area/hallway/fixes1112_hall
	name = "Bot Gym Hallway"
	icon_state = "yellow"
	requires_power = FALSE
	has_gravity = STANDARD_GRAVITY
	dynamic_lighting = DYNAMIC_LIGHTING_DISABLED

/// doors_brig's scenarios: the helpers. No name or layout of its own.
/datum/bot_scenario/fixes1112/doors

/// The tiles with these layout letters, moved into A
/datum/bot_scenario/fixes1112/doors/proc/move_into(area/A, list/chars)
	for(var/char in chars)
		for(var/turf/T as anything in markers[char])
			var/area/old_area = T.loc
			old_area.contents -= T
			A.contents += T
			T.change_area(old_area, A)
	return A

/// A shut airlock on the first tile with this letter, that only this access opens
/datum/bot_scenario/fixes1112/doors/proc/airlock_on(char, list/access, door_name)
	var/obj/machinery/door/airlock/A = new(first_marker(char))
	A.req_access = access
	A.req_one_access = null
	if(door_name)
		A.name = door_name
	place(char, A)
	return A

/// What a shut-in bot's strolls leave behind: a search for somewhere outside, by the rules its walk out will be planned by (pass 1 of a
/// lawful errand, shut in: try_path_to_no_climb()), that finds nothing. A failed search remembers the whole region it reached for 20 s
/// (region_floods, bot_pathing_permissive.dm). A gym bot is scripted and doesn't stroll, so the scenario looks for it. FALSE, with a
/// fail_reason, if it found a way.
/datum/bot_scenario/fixes1112/doors/proc/stroll_out_fails(turf/outside)
	if(!brain.is_shut_in())
		fail_reason = "isn't shut in to begin with"
		return FALSE
	var/list/path = brain.bot_path_to(outside, /turf/proc/Distance_cardinal, /turf/proc/bot_reachable_strict, brain.route_card(), !brain.can_path_through_space())
	if(length(path))
		fail_reason = "found a way out with every door shut"
		return FALSE
	return TRUE

/// The call to be let out, as maybe_ask_to_be_let_out() makes it on the station (an arena isn't on a station level, so a gym bot never
/// asks by itself): the doors it's shut in by, on the radio.
/datum/bot_scenario/fixes1112/doors/proc/ask_out(list/doors)
	brain.gym_scripted = FALSE //call_for() keeps a scripted bot quiet
	. = brain.call_for(/datum/bot_request_kind/let_out, "I'm shut in here - could someone get the door?", doors)
	brain.gym_scripted = TRUE

// ---------------------------------------------------------------------------------------------
// Kept in the Brig for a doctor
// ---------------------------------------------------------------------------------------------

/// An officer with a prisoner in cuffs who's pale from losing blood and wanted for assault: one who doesn't leave Security, kept just
/// inside the door (K) with Medical called (brig_care, security_medevac.dm).
/datum/bot_scenario/fixes1112/doors/brig
	job = "Security Officer"
	kit_backpack = list(/obj/item/restraints/handcuffs)
	var/mob/living/carbon/human/prisoner
	var/asked = FALSE

/datum/bot_scenario/fixes1112/doors/brig/post_spawn()
	give_job_id(list(ACCESS_SECURITY, ACCESS_BRIG))
	prisoner = stand_in(first_marker("C"), "Pat Prisoner")
	var/obj/item/card/id/card = new(prisoner)
	card.registered_name = prisoner.real_name
	prisoner.equip_to_slot_or_del(card, ITEM_SLOT_ID)
	prisoner.handcuffed = new /obj/item/restraints/handcuffs(prisoner)
	prisoner.update_handcuffed()
	var/datum/bot_wanted/W = new
	W.crime = "Assault"
	W.severity = BOT_CRIME_MINOR
	GLOB.bot_security_wanted[WEAKREF(prisoner)] = W
	keep_pale()
	brain.gym_brig_spot = first_marker("K")

/// Under BLOOD_VOLUME_SAFE ("pale skin"), and kept there for the run: what the body makes back in a minute or two would have them "seen to"
/// with nobody having come. Not as low as to run up suffocation over a long run.
/datum/bot_scenario/fixes1112/doors/brig/proc/keep_pale()
	if(!QDELETED(prisoner))
		prisoner.blood_volume = min(prisoner.blood_volume, 460)

/datum/bot_scenario/fixes1112/doors/brig/make_goal()
	return null

/datum/bot_scenario/fixes1112/doors/brig/issue_goal()
	if(!asked)
		asked = TRUE
		brain.start_brig_escort(prisoner)

/// The officer's call to Medical for them (brig_care_wait/start()), once it's made
/datum/bot_scenario/fixes1112/doors/brig/proc/call_for_prisoner()
	for(var/datum/bot_request/R as anything in GLOB.bot_requests)
		if(R.caller_ref?.resolve() == prisoner && istype(R.kind, /datum/bot_request_kind/medical))
			return R
	return null

/// A stand-in doctor nobody drives: the scenario moves it
/datum/bot_scenario/fixes1112/doors/brig/proc/doctor_on(char)
	var/mob/living/carbon/human/H = stand_in(first_marker(char), "Medbay Doctor")
	H.mind_initialize()
	H.mind.assigned_role = "Medical Doctor"
	return H

/datum/bot_scenario/fixes1112/doors/brig/release_run()
	for(var/datum/bot_request/R as anything in GLOB.bot_requests.Copy())
		if(R.caller_ref?.resolve() == prisoner)
			GLOB.bot_requests -= R
	return ..()

/datum/bot_scenario/fixes1112/doors/brig/door_two_off
	name = "brig: the officer keeping a prisoner for a doctor walks to the door two steps off and lets the doctor in"
	desc = "The officer keeps the prisoner two steps in from a Security door, as brig_care_spot() picks, and a doctor whose ID doesn't open it waits outside. The officer lets go of them, goes to the door, opens it, and comes back and takes hold of them again. Only a door a step away was looked at: at Hippie's Labor Shuttle door a doctor asked three times and went, and the officer stood there until the stall check gave the wait up (bugs1112base run11, and run5)."
	layout = list(
		"###########",
		"#BC..K.Do.#",
		"###########")
	time_limit = 40 SECONDS
	var/mob/living/carbon/human/doctor
	var/opened_at = 0

/datum/bot_scenario/fixes1112/doors/brig/door_two_off/setup()
	var/obj/machinery/door/airlock/A = first_placed("D")
	A.req_access = list(ACCESS_BRIG)
	A.req_one_access = null

/datum/bot_scenario/fixes1112/doors/brig/door_two_off/post_spawn()
	..()
	doctor = doctor_on("o")

/datum/bot_scenario/fixes1112/doors/brig/door_two_off/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	keep_pale()
	var/obj/machinery/door/airlock/A = first_placed("D")
	if(!opened_at)
		if(QDELETED(A) || A.density)
			return BOT_GYM_PENDING
		opened_at = world.time
		log_line("the door's open for the doctor")
		return BOT_GYM_PENDING
	return bot.pulling == prisoner ? BOT_GYM_PASS : BOT_GYM_PENDING //and back with them, held again while the doctor isn't in yet

/datum/bot_scenario/fixes1112/doors/brig/door_two_off/on_timeout()
	fail_reason = opened_at ? "let the doctor in, and never took hold of the prisoner again" : "never let in the doctor waiting at the door two steps off"
	return BOT_GYM_FAIL

/datum/bot_scenario/fixes1112/doors/brig/doctor_in_the_way
	name = "brig: the officer keeping a prisoner lets go and steps aside for the doctor, then takes hold again"
	desc = "A doctor walks in to the prisoner the officer is keeping for them, to the tile they were on when Medical was called, which is where a doctor's walk ends (answer_call). Nobody gets past somebody holding a prisoner, nor on to a held prisoner's tile (living/MobBump()): in Hippie's Courtroom eight doctors over five waits walked into the officer or the prisoner and gave up stuck, and the waits froze for three minutes (bugs1112base run1, run5, run7). The officer lets go and steps out of the way, stays by them, and takes hold again once the doctor has gone."
	layout = list(
		"#############",
		"#...........#",
		"#o.....K.BC.#",
		"#############")
	time_limit = 30 SECONDS
	var/mob/living/carbon/human/doctor
	var/turf/spot
	var/arrived_at = 0

/datum/bot_scenario/fixes1112/doors/brig/doctor_in_the_way/post_spawn()
	..()
	doctor = doctor_on("o")

/datum/bot_scenario/fixes1112/doors/brig/doctor_in_the_way/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	keep_pale()
	if(QDELETED(doctor) || QDELETED(prisoner))
		fail_reason = "lost the doctor or the prisoner"
		return BOT_GYM_FAIL
	if(!spot)
		var/datum/bot_request/R = call_for_prisoner()
		if(!R)
			return BOT_GYM_PENDING
		spot = get_turf(R.place)
		log_line("Medical called: the doctor walks in to [bot_coord(spot)]")
	if(!arrived_at)
		if(get_turf(doctor) != spot)
			step_towards(doctor, spot) //a step a second: the officer looks every second
			return BOT_GYM_PENDING
		if(get_dist(bot, prisoner) > 2)
			fail_reason = "walked off from the prisoner"
			return BOT_GYM_FAIL
		arrived_at = world.time
		log_line("the doctor's at the prisoner, and goes again")
		doctor.forceMove(first_marker("o"))
		return BOT_GYM_PENDING
	if(bot.pulling == prisoner)
		return BOT_GYM_PASS
	if(world.time > arrived_at + 8 SECONDS)
		fail_reason = "let go of the prisoner for the doctor and never took hold of them again"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/fixes1112/doors/brig/doctor_in_the_way/on_timeout()
	fail_reason = "the doctor never got past the officer to the prisoner"
	return BOT_GYM_FAIL

/datum/bot_scenario/fixes1112/doors/brig/nobody_comes
	name = "brig: with no doctor coming, the officer's wait ends before the stall check and the prisoner is celled"
	desc = "Nobody answers the call for a doctor. The wait was four minutes, and the stall check fails a step after three on it with nothing done: all seven waits in the batch were given up as gone quiet, the prisoner left cuffed by the door and the next officer to come by waiting three minutes more (bugs1112base). The wait ends by itself inside three minutes, and the officer cells them, as start_brig_escort() means to when nobody's seen to them."
	layout = list(
		"#########",
		"#BC.Ki..#",
		"####d####",
		"###...###",
		"###..l###",
		"#########")
	time_limit = 200 SECONDS
	var/obj/machinery/door_timer/timer

/datum/bot_scenario/fixes1112/doors/brig/nobody_comes/setup()
	var/id = "gymcell[rand(1, 99999)]"
	var/obj/machinery/door/window/brigdoor/door = new(first_marker("d"))
	door.dir = SOUTH
	door.id = id
	place("d", door)
	var/obj/structure/closet/secure_closet/brig/locker = new(first_marker("l"))
	locker.id = id
	place("l", locker)
	timer = new(first_marker("i"))
	timer.id = id
	timer.targets = list(door, locker)
	timer.stat &= ~BROKEN
	place("i", timer)

/datum/bot_scenario/fixes1112/doors/brig/nobody_comes/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	keep_pale()
	if(bot_transcript_said("has gone quiet on /datum/bot_step/paced/brig_care_wait"))
		fail_reason = "waited for a doctor past the stall check: given up as gone quiet, the prisoner left by the door"
		return BOT_GYM_FAIL
	if(bot_transcript_said("giving up on /datum/bot_goal/brig_prisoner/brig_care"))
		fail_reason = "gave up keeping the prisoner for a doctor"
		return BOT_GYM_FAIL
	if(!bot_transcript_said("goal /datum/bot_goal/brig_prisoner/brig_care succeeded"))
		return BOT_GYM_PENDING
	if(timer.timing || (brain.current_goal?.type == /datum/bot_goal/brig_prisoner && bot.pulling == prisoner))
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/fixes1112/doors/brig/nobody_comes/on_timeout()
	fail_reason = bot_transcript_said("goal /datum/bot_goal/brig_prisoner/brig_care succeeded") ? "the wait ended, and the prisoner wasn't taken to the cell" : "still waiting for a doctor at the time limit"
	return BOT_GYM_FAIL

// ---------------------------------------------------------------------------------------------
// A doctor let in at a Security door
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/fixes1112/doors/let_in_doctor
	name = "call: a doctor let in at a Security door its ID doesn't open walks through it to the patient"
	desc = "A patient is behind a Security door the doctor's ID doesn't open. The doctor goes to the door and asks to be let in, and the officer inside opens it. It walks in. Answering a call is a lawful errand, so a door its ID doesn't open counted as shut even stood open (no tailgating): two doctors at Hippie's Labor Shuttle door found it open, found no way through it, said so and went, and the prisoner they'd come for died (bugs1112base run5). Seventy-two tiles on the doctor's side, so it isn't shut in itself."
	job = "Medical Doctor"
	layout = list(
		"##############",
		"#B...........#",
		"#............#",
		"#............#",
		"#............#",
		"#............#",
		"#............#",
		"######D#######",
		"#####sqs######",
		"##############")
	time_limit = 40 SECONDS
	var/mob/living/carbon/human/patient
	var/area/bot_gym/fixes1112_sec/sec
	var/at_door_since = 0
	var/opened = FALSE

/datum/bot_scenario/fixes1112/doors/let_in_doctor/setup()
	sec = move_into(new /area/bot_gym/fixes1112_sec, list("D", "s", "q"))
	var/obj/machinery/door/airlock/A = first_placed("D")
	A.req_access = list(ACCESS_BRIG)
	A.req_one_access = null

/datum/bot_scenario/fixes1112/doors/let_in_doctor/post_spawn()
	give_job_id(list(ACCESS_MEDICAL))
	patient = stand_in(first_marker("q"), "Pat Prisoner")
	patient.apply_damage(30, BRUTE, BODY_ZONE_CHEST)

/datum/bot_scenario/fixes1112/doors/let_in_doctor/make_goal()
	var/datum/bot_request_kind/medical/kind = locate() in GLOB.bot_request_kinds
	return new /datum/bot_goal/answer_call(bot_new_request(kind, patient, FREQ_MEDICAL, get_turf(patient)))

/datum/bot_scenario/fixes1112/doors/let_in_doctor/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("giving up on /datum/bot_goal/answer_call"))
		fail_reason = opened ? "let in, it found no way through the door held open for it" : "gave up before it was let in"
		return BOT_GYM_FAIL
	if(bot_transcript_said("trying to hack it"))
		fail_reason = "hacked its way into Security"
		return BOT_GYM_FAIL
	var/obj/machinery/door/airlock/A = first_placed("D")
	// The officer inside: somebody stood at the door a couple of seconds gets it opened for them
	if(!opened && !QDELETED(A))
		if(A.density && get_area(bot) != sec && bot.Adjacent(A))
			if(!at_door_since)
				at_door_since = world.time
			else if(world.time >= at_door_since + 2 SECONDS)
				opened = TRUE
				log_line("the officer inside opens the door for the doctor")
				INVOKE_ASYNC(A, TYPE_PROC_REF(/obj/machinery/door/airlock, open))
		else
			at_door_since = 0
	if(get_area(bot) == sec && bot_transcript_said("goal /datum/bot_goal/answer_call succeeded"))
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/fixes1112/doors/let_in_doctor/on_timeout()
	fail_reason = opened ? "let in, and never got to the patient" : "never got to the door to be let in"
	return BOT_GYM_FAIL

/datum/bot_scenario/fixes1112/doors/let_in_doctor/release_run()
	for(var/datum/bot_request/R as anything in GLOB.bot_requests.Copy())
		if(R.caller_ref?.resolve() == patient)
			GLOB.bot_requests -= R
	return ..()

// ---------------------------------------------------------------------------------------------
// Let out
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/fixes1112/doors/let_out_stale
	name = "dept: shut in, its last look having found no way out, it walks out through the door opened for it and not to the window"
	desc = "A cook shut in a small room off a hallway, whose door wants the Captain's access, has just looked for a way out and found none, as a shut-in bot's strolls do every few seconds (that search is remembered for 20 s). It calls, a colleague opens the door, and it walks out: through the door, to the floor beyond it, not to the window beside it. 130 of 546 walks out of a door opened for somebody were given up in the same tick, the search from a moment before saying there was no way (bugs1112base run6, Charlie Vasquez in the Captain's Quarters three times), and one in Patient Room A was sent to the window beside the door (run2)."
	job = "Cook"
	layout = list(
		"##########",
		"####w#####",
		"#B..D.hhC#",
		"##########")
	time_limit = 40 SECONDS
	var/mob/living/carbon/human/rescuer
	var/area/hallway/fixes1112_hall/hall
	var/asked = FALSE
	var/next_look = 0

/datum/bot_scenario/fixes1112/doors/let_out_stale/setup()
	hall = move_into(new /area/hallway/fixes1112_hall, list("h"))
	var/obj/machinery/door/airlock/A = first_placed("D")
	A.req_access = list(ACCESS_CAPTAIN)
	A.req_one_access = null

/datum/bot_scenario/fixes1112/doors/let_out_stale/post_spawn()
	rescuer = second_bot(first_marker("C"), "Res Cuer")
	var/obj/item/card/id/card = new(rescuer)
	card.access = list(ACCESS_CAPTAIN)
	rescuer.equip_to_slot_or_del(card, ITEM_SLOT_ID)

/datum/bot_scenario/fixes1112/doors/let_out_stale/make_goal()
	return null

/datum/bot_scenario/fixes1112/doors/let_out_stale/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/obj/machinery/door/airlock/A = first_placed("D")
	if(bot_transcript_said("giving up on /datum/bot_goal/walk_up_to"))
		fail_reason = "told the door was open, it found no way through it and gave the walk up"
		return BOT_GYM_FAIL
	var/datum/bot_goal/G = brain.current_goal
	if(G?.type == /datum/bot_goal/walk_up_to && (locate(/obj/structure/window) in get_turf(G.target)))
		fail_reason = "sent to the window beside the door, not the floor beyond it"
		return BOT_GYM_FAIL
	if(isturf(bot.loc) && bot.x > A.x)
		return BOT_GYM_PASS
	if(A.density && world.time >= next_look)
		next_look = world.time + 3 SECONDS
		if(!stroll_out_fails(first_marker("h")))
			return BOT_GYM_FAIL
	if(!asked && world.time > start_time + 2 SECONDS)
		asked = TRUE
		var/list/doors = brain.doors_shutting_me_in()
		if(!length(doors))
			fail_reason = "found no door to ask at"
			return BOT_GYM_FAIL
		if(!ask_out(doors))
			fail_reason = "couldn't make its call"
			return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/fixes1112/doors/let_out_stale/on_timeout()
	fail_reason = "never got out through the door opened for it"
	return BOT_GYM_FAIL

/datum/bot_scenario/fixes1112/doors/let_out_lobby
	name = "dept: let out of a room with a lobby, the door towards the hallway first, then it asks for the next one"
	desc = "Shut in a room like the Brig's hall: a side door to a dead end beside it, and the way out a door into a lobby with another door on to the hallway. It asks once and is let out by the door towards the hallway, not the side door it's stood by; through it, it asks for the lobby's outer door a few seconds later, not two minutes. Only 12 of some 85 doors opened for somebody calling from the Brig were a Brig door: a cook released from a cell was let into the Security Office, the Security Desk four times, the labour shuttle and the Prison Wing, asked ten times in sixteen minutes and never got out (bugs1112base run6)."
	job = "Cook"
	layout = list(
		"#############",
		"#hhhhhhhh.CC#",
		"#######o#####",
		"######ll#####",
		"######ll#####",
		"#######i#####",
		"#kksB.......#",
		"#############")
	time_limit = 90 SECONDS
	var/area/hallway/fixes1112_hall/hall
	var/obj/machinery/door/airlock/side_door
	var/obj/machinery/door/airlock/inner_door
	var/obj/machinery/door/airlock/outer_door
	/// 1 once it's asked for the first door, 2 for the second
	var/asked = 0
	var/next_look = 0
	var/opened_at = 0
	var/clock_checked = FALSE

/datum/bot_scenario/fixes1112/doors/let_out_lobby/setup()
	hall = move_into(new /area/hallway/fixes1112_hall, list("h"))
	side_door = airlock_on("s", list(ACCESS_SECURITY), "Interrogation")
	inner_door = airlock_on("i", list(ACCESS_SECURITY), "Brig")
	outer_door = airlock_on("o", list(ACCESS_SECURITY), "Brig Lobby")

/// Two officers in the hall, so the second call has somebody free for it while the first holds the inner door
/datum/bot_scenario/fixes1112/doors/let_out_lobby/post_spawn()
	var/officers = 0
	for(var/turf/T as anything in markers["C"])
		officers++
		var/mob/living/carbon/human/H = second_bot(T, "Officer [officers]")
		var/obj/item/card/id/card = new(H)
		card.access = list(ACCESS_SECURITY)
		H.equip_to_slot_or_del(card, ITEM_SLOT_ID)

/datum/bot_scenario/fixes1112/doors/let_out_lobby/make_goal()
	return null

/datum/bot_scenario/fixes1112/doors/let_out_lobby/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(istype(get_area(bot), /area/hallway))
		return BOT_GYM_PASS
	if(get_turf(bot) in markers["k"])
		fail_reason = "went through the side door into the dead end"
		return BOT_GYM_FAIL
	var/room_y = first_marker("B").y
	if(!opened_at)
		if(!inner_door.density)
			opened_at = world.time
			log_line("[inner_door] is open")
			return BOT_GYM_PENDING
		if(world.time >= next_look)
			next_look = world.time + 3 SECONDS
			if(!stroll_out_fails(first_marker("h")))
				return BOT_GYM_FAIL
		if(!asked && world.time > start_time + 2 SECONDS)
			asked = 1
			var/list/doors = brain.doors_shutting_me_in()
			if(!length(doors) || doors[1] != inner_door)
				fail_reason = "asked to be let out by [length(doors) ? "[doors[1]]" : "no door"] first, not the door towards the hallway"
				return BOT_GYM_FAIL
			if(!ask_out(doors))
				fail_reason = "couldn't make its call"
				return BOT_GYM_FAIL
		return BOT_GYM_PENDING
	// A second after the door's opened (the helper's click is over by then): when it may ask again
	if(!clock_checked && world.time >= opened_at + 1 SECONDS)
		clock_checked = TRUE
		if(brain.next_let_out_call > world.time + 10 SECONDS)
			fail_reason = "through the inner door, it would wait [round((brain.next_let_out_call - world.time) / 10)] s to ask for the next one"
			return BOT_GYM_FAIL
	if(world.time >= opened_at + 5 SECONDS && bot.y == room_y)
		fail_reason = "gave up the walk out through the door opened for it"
		return BOT_GYM_FAIL
	// In the lobby, once it may ask again and the outer door the helper came in by has shut behind them
	if(asked == 1 && clock_checked && bot.y != room_y && world.time >= brain.next_let_out_call && outer_door.density && !outer_door.operating)
		asked = 2
		var/list/doors = brain.doors_shutting_me_in()
		if(length(doors) != 1 || doors[1] != outer_door)
			var/list/names = list()
			for(var/obj/machinery/door/airlock/D as anything in doors)
				names += D.name
			fail_reason = "in the lobby, asked to be let out by [length(names) ? english_list(names) : "no door"], not the outer door"
			return BOT_GYM_FAIL
		if(!ask_out(doors))
			fail_reason = "couldn't make its second call"
			return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/fixes1112/doors/let_out_lobby/on_timeout()
	fail_reason = asked == 2 ? "asked for the outer door and never got out to the hallway" : "never asked for the outer door from the lobby"
	return BOT_GYM_FAIL

// ---------------------------------------------------------------------------------------------
// A door's button behind a desk
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/fixes1112/doors/button_behind_desk
	name = "doors: a door's button boxed in behind a desk is no way through, and isn't walked over to"
	desc = "On an everyday errand to the far side of a door its ID doesn't open. The door's button is on the bot's side, a few steps off, but boxed in behind a desk. Nobody on this side can get to it, so the door is no way through: no route through it, no walk up to it, no setting off for the button. MetaStation's Medbay Doors Controls (behind the reception desk and in the Security post) and the Research Exterior Airlock button (on the desk in Science's post) had 57 errands given up in six shifts that way (bugs1112base)."
	job = "Assistant"
	layout = list(
		"##########",
		"#B...D..G#",
		"#.tt######",
		"#.tk######",
		"##########")
	time_limit = 20 SECONDS

/datum/bot_scenario/fixes1112/doors/button_behind_desk/setup()
	var/door_id = "gym_desk_[REF(src)]"
	var/obj/machinery/door/airlock/A = first_placed("D")
	A.req_access = list(ACCESS_MEDICAL)
	A.req_one_access = null
	A.id_tag = door_id
	for(var/turf/T in markers["k"])
		var/obj/machinery/button/door/B = new(T)
		B.name = "Medbay Doors Control"
		B.id = door_id
		B.normaldoorcontrol = TRUE
		place("k", B)

/datum/bot_scenario/fixes1112/doors/button_behind_desk/make_goal()
	var/datum/bot_goal/gym_reach/G = ..()
	G.lawful = TRUE
	return G

/datum/bot_scenario/fixes1112/doors/button_behind_desk/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("going over to"))
		fail_reason = "set off for a door's button with a desk between it and the door"
		return BOT_GYM_FAIL
	if(get_turf(bot) == get_step(first_marker("D"), WEST))
		fail_reason = "walked up to a door it had no way through, by a button it couldn't get to"
		return BOT_GYM_FAIL
	if(get_turf(bot) == first_marker("G"))
		fail_reason = "got through a door it has no access to"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/fixes1112/doors/button_behind_desk/on_timeout()
	var/obj/machinery/door/airlock/A = first_placed("D")
	if(QDELETED(A) || A.panel_open || (A.stat & BROKEN))
		fail_reason = "the door was forced"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

// <<< hazards_scenarios.dm
// ---------------------------------------------------------------------------------------------
// Hazards (fixes 2026-11-12): the pool, the doorway of a held door, running hurt, a radiation storm's shelter, and two bots after one tile
// ---------------------------------------------------------------------------------------------

// The pool: an officer goes in only after somebody who's in it, only with the breath for it, and lowers itself in off the side
// (bot_may_jump_in(), bot_pathing_permissive.dm; poolside_instead() and try_escape_pool(), bot_items.dm; do_step_next_node(), bot_movement.dm)

/// An officer after somebody wanted for a scuffle, in the pool or by it (as /datum/bot_scenario/suspect_in_pool, scenarios_law.dm). Every
/// step it takes off dry floor into the water is noted with its suffocation as it got there (a fall's mouthful of water is in it by then).
/datum/bot_scenario/fixes1112/pool
	job = "Security Officer"
	kit_backpack = list(/obj/item/restraints/handcuffs)
	var/mob/living/carbon/human/suspect
	/// The layout characters that are water
	var/list/water = list("q", "K")
	/// Suffocation at each step into the water from dry floor
	var/list/entries = list()

/datum/bot_scenario/fixes1112/pool/setup()
	for(var/char in water)
		for(var/turf/T as anything in markers[char])
			T.ChangeTurf(/turf/open/pool)

/datum/bot_scenario/fixes1112/pool/post_spawn()
	suspect = stand_in(first_marker("K"), "Wes Wanted")
	if(istype(suspect.loc, /turf/open/pool))
		suspect.swimming = TRUE
	var/datum/bot_wanted/W = new
	W.severity = BOT_CRIME_MINOR
	W.crime = "Assault"
	W.last_seen = get_turf(suspect)
	W.last_seen_at = world.time
	GLOB.bot_security_wanted[WEAKREF(suspect)] = W
	brain.begin_arrest(suspect)
	RegisterSignal(bot, COMSIG_MOVABLE_MOVED, PROC_REF(bot_moved))

/datum/bot_scenario/fixes1112/pool/make_goal()
	return null //the arrest is the job

/datum/bot_scenario/fixes1112/pool/proc/bot_moved(atom/movable/mover, atom/old_loc)
	SIGNAL_HANDLER
	if(istype(bot.loc, /turf/open/pool) && !istype(old_loc, /turf/open/pool))
		entries += bot.getOxyLoss()
		log_line("into the water at [bot.getOxyLoss()] suffocation")

/datum/bot_scenario/fixes1112/pool/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	// In under 10 (bot_breath_for_the_pool()) reads under 15 even with a fall's mouthful, and lowered in it takes none
	for(var/oxy in entries)
		if(oxy >= 15)
			fail_reason = "went into the water after him at [oxy] suffocation"
			return BOT_GYM_FAIL
	if(suspect.handcuffed)
		return BOT_GYM_PASS
	if(bot_transcript_said("no path to suspect") || brain.state != BOT_STATE_ARREST)
		fail_reason = "gave the arrest up ([brain.state])"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/fixes1112/pool/release_run()
	GLOB.bot_security_wanted -= WEAKREF(suspect)
	if(bot)
		UnregisterSignal(bot, COMSIG_MOVABLE_MOVED)
	return ..()

/datum/bot_scenario/fixes1112/pool/dry_suspect
	name = "pool: an officer walks round the pool to somebody stood beside it, not through the water"
	desc = "A man wanted for a scuffle stands on the far side of the pool, on dry floor. The way across a corner of the water is five steps, round it eleven: the officer walks round. Batch 2026-11-12 run1: two officers after a man stood on the poolside were routed through the water on a tie with the dry way, fell in, climbed out, were walked back in by the same route, and drowned."
	water = list("q")
	layout = list(
		"#########",
		"#B.qqq.K#",
		"#..qqq..#",
		"#..qqq..#",
		"#.......#",
		"#########")
	time_limit = 40 SECONDS

/datum/bot_scenario/fixes1112/pool/dry_suspect/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(length(entries))
		fail_reason = "walked into the water after somebody stood on dry floor"
		return BOT_GYM_FAIL
	return ..()

/datum/bot_scenario/fixes1112/pool/breath_lost
	name = "pool: an officer short of breath on the way waits by the side, then lowers itself in after him"
	desc = "A man wanted for a scuffle stands in the middle of the pool. The officer sets off after him and is winded on its first step (20 suffocation), with a route planned through the water. It stops at the side, waits for its breath, lowers itself in and cuffs him: it doesn't walk on in, and it doesn't give him up. Batch 2026-11-12 run1: an officer short of breath was walked into the water by the route it had planned, and drowned."
	layout = list(
		"############",
		"#B...qqqqq.#",
		"#....qqqqq.#",
		"#....qqKqq.#",
		"#....qqqqq.#",
		"#....qqqqq.#",
		"############")
	time_limit = 70 SECONDS
	var/winded = FALSE

/datum/bot_scenario/fixes1112/pool/breath_lost/bot_moved(atom/movable/mover, atom/old_loc)
	if(!winded)
		winded = TRUE
		bot.adjustOxyLoss(20) //its route into the water was planned with its breath: it's winded on the way
		log_line("winded on the way over")
	return ..()

/datum/bot_scenario/fixes1112/pool/climbed_out
	name = "pool: an officer that climbed out short of breath waits for its breath before going back in"
	desc = "The officer is in the pool after a man wanted for a scuffle, out of breath (35 suffocation, where it climbs out). It climbs out, waits by the side until it has its breath back, then lowers itself in and cuffs him. Batch 2026-11-12 run1: an officer that had climbed out short of breath walked straight back in, fell, and drowned."
	water = list("q", "K", "B")
	layout = list(
		"############",
		"#....qqqqq.#",
		"#....Bqqqq.#",
		"#....qqKqq.#",
		"#....qqqqq.#",
		"#....qqqqq.#",
		"############")
	time_limit = 100 SECONDS

/datum/bot_scenario/fixes1112/pool/climbed_out/post_spawn()
	..()
	bot.swimming = TRUE
	bot.adjustOxyLoss(35) //past where it stays in (try_escape_pool(), bot_items.dm): it climbs out

// A held door's doorway: a holder put in it by somebody coming through steps back to its own side (hold_door, bot_requests.dm)

/// Holding a door open for somebody shut in, from the south. A north-south door, so the side it holds it from isn't the first one in the
/// order the cardinals come in.
/datum/bot_scenario/fixes1112/hold_door
	job = "Station Engineer"
	layout = list(
		"###",
		"#C#",
		"#.#",
		"#.#",
		"#D#",
		"#B#",
		"#.#",
		"###")
	time_limit = 20 SECONDS
	max_goal_attempts = 1
	var/mob/living/carbon/human/shut_in
	var/swapped = FALSE

/datum/bot_scenario/fixes1112/hold_door/setup()
	var/obj/machinery/door/airlock/A = first_placed("D")
	A.req_access = list(ACCESS_CAPTAIN)
	A.autoclose = FALSE
	INVOKE_ASYNC(A, TYPE_PROC_REF(/obj/machinery/door/airlock, open))

/datum/bot_scenario/fixes1112/hold_door/post_spawn()
	give_job_id(list(ACCESS_CAPTAIN))
	shut_in = stand_in(first_marker("C"), "Shut In")

/datum/bot_scenario/fixes1112/hold_door/make_goal()
	return new /datum/bot_goal/hold_door(first_placed("D"), shut_in)

/// Put in the doorway, a couple of seconds into the hold, as a passer-by changing places with it would
/datum/bot_scenario/fixes1112/hold_door/proc/swap_in_due()
	if(swapped || world.time <= start_time + 2 SECONDS)
		return FALSE
	if(!istype(brain.current_goal, /datum/bot_goal/hold_door))
		fail_reason = "never took up holding the door"
		return FALSE
	swapped = TRUE
	return TRUE

/datum/bot_scenario/fixes1112/hold_door/firelock
	name = "hold door: put in the doorway by somebody passing, it steps back to its side before the firelock drops"
	desc = "The bot holds a door from the south for somebody shut in. Somebody passing changes places with it and leaves it in the doorway, under the firelock. It steps back to the side it held the door from and holds on there, and the firelock drops on nobody. Batch 2026-11-12 run8: a Chief Engineer at 10 health held on in a doorway for seventeen seconds until an alarm dropped the firelock on him twice."
	var/obj/machinery/door/firedoor/firelock
	var/dropped = FALSE

/datum/bot_scenario/fixes1112/hold_door/firelock/setup()
	..()
	firelock = new(get_turf(first_placed("D")))

/datum/bot_scenario/fixes1112/hold_door/firelock/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot.getBruteLoss() > 0)
		fail_reason = "crushed by the firelock"
		return BOT_GYM_FAIL
	var/turf/doorway = first_marker("D")
	if(!swapped)
		if(swap_in_due())
			bot.forceMove(doorway) //somebody passing changed places with it
			log_line("put in the doorway")
		return fail_reason ? BOT_GYM_FAIL : BOT_GYM_PENDING
	if(!dropped)
		if(world.time <= start_time + 6 SECONDS) //at least three seconds on: a click of the hold, every two
			return BOT_GYM_PENDING
		dropped = TRUE
		if(get_turf(bot) == doorway)
			fail_reason = "still stood in the doorway, under the firelock"
			return BOT_GYM_FAIL
		if(get_turf(bot) != first_marker("B"))
			fail_reason = "stepped off the doorway to [bot_coord(get_turf(bot))], not back to the side it held the door from"
			return BOT_GYM_FAIL
		INVOKE_ASYNC(firelock, TYPE_PROC_REF(/obj/machinery/door, close)) //an alarm drops it
		return BOT_GYM_PENDING
	if(world.time <= start_time + 9 SECONDS)
		return BOT_GYM_PENDING
	if(!istype(brain.current_goal, /datum/bot_goal/hold_door))
		fail_reason = "let go of the door with them still shut in"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/fixes1112/hold_door/let_through
	name = "hold door: the one it holds it for comes through and swaps with it, and it lets go"
	desc = "The bot holds a door from the south for somebody shut in. They come out on to its tile and change places with it, leaving it in the doorway with them through and beside it. It sees them through and lets the door go, where it read the doorway as the east side and held on for the full 45 seconds. Batch 2026-11-12: 195 of 547 holds had the holder in the doorway, 45 of them for 30 seconds or more."

/datum/bot_scenario/fixes1112/hold_door/let_through/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!swapped)
		if(swap_in_due())
			bot.forceMove(first_marker("D")) //walking out, they change places with it
			shut_in.forceMove(first_marker("B"))
			log_line("they came through and changed places with it")
		return fail_reason ? BOT_GYM_FAIL : BOT_GYM_PENDING
	if(!istype(brain.current_goal, /datum/bot_goal/hold_door))
		return BOT_GYM_PASS
	if(world.time > start_time + 7 SECONDS)
		fail_reason = "held on in the doorway with them through and stood beside it"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

// Running hurt: a hurt bot with no sleeper to go to gets away all the same, and doesn't go back in (try_run_for_it(), bot_brain.dm;
// badly_hurt(), bot_fighting.dm; on_saw_violence(), bot_witness.dm)

/datum/bot_scenario/fixes1112/hurt_keeps_out
	name = "hurt and running: badly hurt, it calls in a nanosuit beating somebody and keeps out of it"
	desc = "Somebody in a nanosuit is beating somebody five tiles from the bot, which is at a tenth of its health with all the nerve in the world. It calls it in and gets clear: it doesn't go for the suit, or for something to hit it with. Batch 2026-11-12 run8: a Chief Engineer at 21 health ran from a nanosuit shouting for help and was back at it a tenth of a second later."
	layout = list(
		"#################",
		"#...............#",
		"#...B...VC......#",
		"#...............#",
		"#################")
	time_limit = 10 SECONDS
	var/mob/living/carbon/human/griefer
	var/mob/living/carbon/human/victim

/datum/bot_scenario/fixes1112/hurt_keeps_out/issue_goal()
	return

/datum/bot_scenario/fixes1112/hurt_keeps_out/post_spawn()
	griefer = stand_in(first_marker("C"), "Griff Griefer")
	var/obj/item/clothing/suit/space/hardsuit/nano/N = new(griefer.loc)
	griefer.equip_to_slot_if_possible(N, ITEM_SLOT_OCLOTHING, FALSE, TRUE, TRUE)
	victim = stand_in(first_marker("V"), "Vic Victim")
	griefer.setDir(get_dir(griefer, victim))
	brain.nerve = 0.9 //all the nerve there is: it's the hurt that keeps it out
	// A tenth of its health or less, under the 15% it runs at with that nerve (health_to_run_at(), bot_fighting.dm), and still on its feet. A
	// little at a time: a body's damage is scaled by the server's damage multiplier on the way in, and 90 in one go left it at 25.
	for(var/i in 1 to 60)
		if(bot.health <= bot.maxHealth * 0.1)
			break
		bot.adjustBruteLoss(5)
	addtimer(CALLBACK(src, PROC_REF(beat)), 2 SECONDS)

/datum/bot_scenario/fixes1112/hurt_keeps_out/proc/beat()
	if(result != BOT_GYM_PENDING || QDELETED(griefer) || QDELETED(victim) || victim.stat != CONSCIOUS)
		return
	griefer.a_intent = INTENT_HARM
	griefer.UnarmedAttack(victim, TRUE)
	addtimer(CALLBACK(src, PROC_REF(beat)), 15)

/datum/bot_scenario/fixes1112/hurt_keeps_out/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("in the nanosuit") || bot_transcript_said("stepping in against") || bot_transcript_said("something to hit") || (brain.state == BOT_STATE_COMBAT && brain.attacker == griefer))
		fail_reason = "went for the suit at [bot.health] health"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/fixes1112/hurt_keeps_out/on_timeout()
	if(!bot_transcript_said("called in "))
		fail_reason = "never called it in"
		return BOT_GYM_FAIL
	if(!bot_transcript_said("run_from"))
		fail_reason = "stood where it was at [bot.health] health"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/fixes1112/hurt_gets_away
	name = "hurt and running: badly hurt with no sleeper to run to, it still gets away"
	desc = "Attacked at 10 health with no sleeper in reach, the bot runs for it and gets away from the one attacking it, where it used to look for a sleeper, find none and stand beside them. Batch 2026-11-12: 60 of 116 runs from a fight found no sleeper and went nowhere."
	layout = list(
		"###################",
		"#...............BC#",
		"###################")
	time_limit = 25 SECONDS
	var/mob/living/carbon/human/assailant
	var/ran_at = 0

/datum/bot_scenario/fixes1112/hurt_gets_away/issue_goal()
	return

/datum/bot_scenario/fixes1112/hurt_gets_away/post_spawn()
	assailant = stand_in(first_marker("C"), "Casey Assailant")
	bot.adjustBruteLoss(90)
	addtimer(CALLBACK(src, PROC_REF(start_fight)), 2 SECONDS)

/datum/bot_scenario/fixes1112/hurt_gets_away/proc/start_fight()
	if(result != BOT_GYM_PENDING || QDELETED(assailant))
		return
	log_combat(assailant, bot, "punched")

/datum/bot_scenario/fixes1112/hurt_gets_away/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!ran_at)
		if(bot_transcript_said("disengaging from [assailant]: running for it"))
			ran_at = world.time
		else if(bot_transcript_said("attacking [assailant]"))
			fail_reason = "stayed and fought at [bot.health] health"
			return BOT_GYM_FAIL
		return BOT_GYM_PENDING
	if(bot_transcript_said("trying /datum/bot_strategy/run_from") && get_dist(bot, assailant) >= 3)
		return BOT_GYM_PASS
	if(world.time > ran_at + 5 SECONDS)
		fail_reason = "ran for it and went nowhere ([get_dist(bot, assailant)] tiles off them)"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

// A radiation storm: under cover, it stays there (assign_goal(), bot_goals.dm; rad_shelter_spot() and rad_storm_errand_ok(), goals/rad_storm.dm;
// idle_fidget(), bot_human.dm)

/// The tunnel a scenario's radiation storm keeps out of
/area/bot_gym/fixes1112_tunnel
	name = "Bot Gym tunnel"

/// A radiation storm blowing on the arenas' level, that the tunnel (tunnel_chars) keeps out. Station-wide: it's for every arena on the level,
/// so it runs by name, on its own. Nobody's irradiated: it was never telegraphed, so it has no impacted areas (weather.dm can_weather_act()).
/datum/bot_scenario/fixes1112/rad
	job = "Assistant"
	station_wide = TRUE
	time_limit = 30 SECONDS
	var/list/tunnel_chars = list("u") //not "m", which is a mouse in the gym's legend (bot_gym.dm build_tile())
	var/area/bot_gym/fixes1112_tunnel/tunnel
	var/datum/weather/rad_storm/storm

/datum/bot_scenario/fixes1112/rad/setup()
	tunnel = new
	for(var/char in tunnel_chars)
		for(var/turf/T as anything in markers[char])
			var/area/old_area = T.loc
			old_area.contents -= T
			tunnel.contents += T
			T.change_area(old_area, tunnel)
	var/turf/start = first_marker("B")
	storm = new(list(start.z))
	storm.protected_areas = list(/area/bot_gym/fixes1112_tunnel)
	storm.stage = MAIN_STAGE
	SSweather.processing += storm

/datum/bot_scenario/fixes1112/rad/issue_goal()
	return

/datum/bot_scenario/fixes1112/rad/proc/storm_over()
	if(storm)
		SSweather.processing -= storm
		storm.stage = END_STAGE

/datum/bot_scenario/fixes1112/rad/proc/in_tunnel(atom/movable/A)
	return istype(get_area(A), /area/bot_gym/fixes1112_tunnel)

/datum/bot_scenario/fixes1112/rad/release_run()
	storm_over()
	QDEL_NULL(storm)
	return ..()

/datum/bot_scenario/fixes1112/rad/errand_waits
	name = "rad storm: under cover, an errand outside waits till it's passed"
	desc = "A radiation storm is blowing and the bot is in the tunnel. An errand out in the hall is turned down, one in the tunnel is taken, and once the storm has passed the errand outside is done. Batch 2026-11-12 run1: sheltered crew took a meal, a call, a traitor's mark out into the storm, were turned round at the door and walked out again, 169 dashes for shelter by 28 crew in one storm."
	tunnel_chars = list("u", "B")
	layout = list(
		"###########",
		"#uuBuD...o#",
		"###########")
	time_limit = 60 SECONDS
	var/phase = 0

/datum/bot_scenario/fixes1112/rad/errand_waits/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(storm && (storm in SSweather.processing) && !in_tunnel(bot))
		fail_reason = "left the tunnel with the storm still blowing"
		return BOT_GYM_FAIL
	switch(phase)
		if(0)
			if(world.time > start_time + 1 SECONDS)
				phase = 1
				if(brain.assign_goal(new /datum/bot_goal/walk_up_to(first_marker("o"))))
					fail_reason = "took an errand out into the storm"
					return BOT_GYM_FAIL
		if(1)
			if(world.time > start_time + 2 SECONDS)
				phase = 2
				if(!brain.assign_goal(new /datum/bot_goal/walk_up_to(first_marker("u"))))
					fail_reason = "turned down an errand in the tunnel too"
					return BOT_GYM_FAIL
		if(2)
			if(world.time > start_time + 6 SECONDS && !brain.current_goal)
				phase = 3
				storm_over()
				log_line("the storm has passed")
		if(3)
			var/turf/here = get_turf(bot)
			if(bot_rad_storm(here.z))
				return BOT_GYM_PENDING //another rad storm scenario's storm, run beside this one: the level isn't clear yet
			if(!brain.current_goal)
				brain.assign_goal(new /datum/bot_goal/walk_up_to(first_marker("o")))
			if(get_dist(bot, first_marker("o")) <= 1)
				return BOT_GYM_PASS
	return BOT_GYM_PENDING

/// Stood in the tunnel's doorway, an airlock with the hall to the north of it: what idle_fidget() does about it
/datum/bot_scenario/fixes1112/rad/doorway
	name = "rad storm: idling in a maintenance doorway it steps in, not out"
	desc = "A radiation storm is blowing and the bot is stood in the open airlock into the tunnel, the hall to the north. Fidgeting off the doorway, it steps into the tunnel, where it used to take the first way off in north-south-east-west order. Batch 2026-11-12 run1: put on a maintenance door's tile by the next one in, an officer stepped off it on the hallway side and ran back in for shelter, twenty times in one storm."
	time_limit = 10 SECONDS
	tunnel_chars = list("u", "B")
	layout = list(
		"###",
		"#.#",
		"#.#",
		"#B#",
		"#u#",
		"#u#",
		"###")
	var/fidgeted = FALSE

/datum/bot_scenario/fixes1112/rad/doorway/setup()
	..()
	var/obj/machinery/door/airlock/A = new(first_marker("B"))
	A.autoclose = FALSE
	INVOKE_ASYNC(A, TYPE_PROC_REF(/obj/machinery/door/airlock, open))
	place("d", A)

/datum/bot_scenario/fixes1112/rad/doorway/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(world.time <= start_time + 1 SECONDS)
		return BOT_GYM_PENDING
	if(!fidgeted)
		fidgeted = TRUE
		brain.next_fidget_time = 0
		brain.idle_fidget()
		log_line("fidgeted: now at [bot_coord(get_turf(bot))]")
	if(!in_tunnel(bot))
		fail_reason = "stepped out of the doorway into the storm"
		return BOT_GYM_FAIL
	return (get_turf(bot) in markers["u"]) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/fixes1112/rad/doorway/someone_inside
	name = "rad storm: idling in the doorway it doesn't step on to the one sheltering inside"
	desc = "As above, with somebody sheltering on the tile just inside. The bot stays in the doorway: not out into the storm, and not on to them, which would swap them into the doorway to step off it next."
	tunnel_chars = list("u", "B", "h")
	layout = list(
		"###",
		"#.#",
		"#.#",
		"#B#",
		"#h#",
		"#u#",
		"###")
	var/mob/living/carbon/human/sheltering

/datum/bot_scenario/fixes1112/rad/doorway/someone_inside/post_spawn()
	sheltering = stand_in(first_marker("h"), "Shel Tering")

/datum/bot_scenario/fixes1112/rad/doorway/someone_inside/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(world.time <= start_time + 1 SECONDS)
		return BOT_GYM_PENDING
	if(!fidgeted)
		fidgeted = TRUE
		brain.next_fidget_time = 0
		brain.idle_fidget()
		log_line("fidgeted: now at [bot_coord(get_turf(bot))]")
		if(!in_tunnel(bot))
			fail_reason = "stepped out of the doorway into the storm"
			return BOT_GYM_FAIL
		if(get_turf(bot) != first_marker("B"))
			fail_reason = "stepped on to whoever was sheltering inside"
			return BOT_GYM_FAIL
	return world.time > start_time + 3 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/fixes1112/rad/second_stops_short
	name = "rad storm: the second one in stops short of the first"
	desc = "A radiation storm, and two crew run for the one tunnel door. The first in stands a few steps in, and the second stops short of it: the second doesn't walk into the first and swap it out into the doorway. Batch 2026-11-12 run1: two officers sheltering by one maintenance door put each other back out into the storm twenty times each."
	time_limit = 40 SECONDS
	max_goal_attempts = 10
	layout = list(
		"#############",
		"#B.O..Duuuuu#",
		"#############")
	var/mob/living/carbon/human/other
	var/first_in = FALSE
	var/both_in_at = 0
	var/left_cover = FALSE

/datum/bot_scenario/fixes1112/rad/second_stops_short/post_spawn()
	other = second_bot(first_marker("O"), "Sam Second")
	other.mind.assigned_role = "Assistant"
	RegisterSignal(bot, COMSIG_MOVABLE_MOVED, PROC_REF(first_moved))

/// The shelter duty drives the first bot, as it would in a round (as /datum/bot_scenario/duty/issue_goal(), scenarios_duties.dm)
/datum/bot_scenario/fixes1112/rad/second_stops_short/issue_goal()
	var/datum/bot_duty/D = bot_duty_of(/datum/bot_duty/rad_shelter)
	if(D && D.try_start(brain))
		goal_attempts++
		log_line("[D.name]: [brain.current_goal ? brain.current_goal.type : "started"]")

/datum/bot_scenario/fixes1112/rad/second_stops_short/proc/first_moved(atom/movable/mover, atom/old_loc)
	SIGNAL_HANDLER
	if(first_in && !in_tunnel(bot))
		left_cover = TRUE

/datum/bot_scenario/fixes1112/rad/second_stops_short/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(other) || other.stat == DEAD)
		fail_reason = "the second one died"
		return BOT_GYM_FAIL
	if(left_cover)
		fail_reason = "the first one in was put back out into the storm"
		return BOT_GYM_FAIL
	if(!first_in)
		if(in_tunnel(bot) && !brain.current_goal)
			first_in = TRUE
			log_line("first one in, at [bot_coord(get_turf(bot))]")
		return BOT_GYM_PENDING
	var/datum/bot_brain/second = other.bot_brain
	if(!in_tunnel(other))
		if(both_in_at)
			fail_reason = "the second one left the tunnel"
			return BOT_GYM_FAIL
		if(!second.current_goal)
			var/datum/bot_duty/D = bot_duty_of(/datum/bot_duty/rad_shelter)
			if(D && D.try_start(second))
				log_line("[other] heads for shelter")
		return BOT_GYM_PENDING
	if(!both_in_at)
		if(!second.current_goal)
			both_in_at = world.time
			log_line("both in: [bot_coord(get_turf(bot))] and [bot_coord(get_turf(other))]")
		return BOT_GYM_PENDING
	if(world.time < both_in_at + 8 SECONDS)
		return BOT_GYM_PENDING
	var/turf/door = first_marker("D")
	var/turf/just_inside = first_marker("u")
	var/turf/mine = get_turf(bot)
	var/turf/theirs = get_turf(other)
	if(mine == theirs || mine == door || theirs == door || mine == just_inside || theirs == just_inside)
		fail_reason = "ended at [bot_coord(mine)] and [bot_coord(theirs)]: on top of one another, in the doorway or just inside it"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/fixes1112/rad/second_stops_short/release_run()
	if(bot)
		UnregisterSignal(bot, COMSIG_MOVABLE_MOVED)
	return ..()

// Two bots after one tile take turns, not a swap a second (bot_step_towards(), yields_tile(), bot_movement.dm; keep_it_at_range(),
// goals/security_tactics.dm)

/datum/bot_scenario/fixes1112/swap_hold_down
	name = "swap: two holding one man down take turns on the tile beside him, not a swap every second"
	desc = "A man wanted for a major crime lies stunned at the end of a corridor with room beside him for one. One crewman is on that tile holding him for Security, and the bot comes to hold him too. They change places once, and then take turns at most every ten seconds: neither walks back into the other a moment after being put off the tile, and neither gives up holding him. Batch 2026-11-12: two holding a man down traded places 18-20 times in 20 seconds (run7, run2); place swaps were half of all pacing (33 of 66)."
	job = "Assistant"
	layout = list(
		"#######",
		"#KOB..#",
		"#######")
	time_limit = 25 SECONDS
	var/mob/living/carbon/human/other
	var/mob/living/carbon/human/captive
	var/moves = 0

/datum/bot_scenario/fixes1112/swap_hold_down/post_spawn()
	captive = stand_in(first_marker("K"), "Wes Wanted")
	var/datum/bot_wanted/W = new
	W.severity = BOT_CRIME_MAJOR
	W.crime = "Assault with a Deadly Weapon"
	W.last_seen = get_turf(captive)
	W.last_seen_at = world.time
	GLOB.bot_security_wanted[WEAKREF(captive)] = W
	captive.Paralyze(60 SECONDS)
	other = second_bot(first_marker("O"), "Sam Second")
	other.bot_brain.assign_goal(new /datum/bot_goal/hold_for_security(captive))
	RegisterSignal(bot, COMSIG_MOVABLE_MOVED, PROC_REF(stepped))
	RegisterSignal(other, COMSIG_MOVABLE_MOVED, PROC_REF(stepped))

/datum/bot_scenario/fixes1112/swap_hold_down/make_goal()
	return new /datum/bot_goal/hold_for_security(captive)

/datum/bot_scenario/fixes1112/swap_hold_down/proc/stepped()
	SIGNAL_HANDLER
	moves++

/datum/bot_scenario/fixes1112/swap_hold_down/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(other) || QDELETED(captive))
		fail_reason = "lost one of the others"
		return BOT_GYM_FAIL
	if(moves > 6)
		fail_reason = "the two of them took turns on the tile beside him: [moves] steps"
		return BOT_GYM_FAIL
	if(world.time < start_time + 18 SECONDS)
		return BOT_GYM_PENDING
	if(!istype(brain.current_goal, /datum/bot_goal/hold_for_security) || !istype(other.bot_brain.current_goal, /datum/bot_goal/hold_for_security))
		fail_reason = "one of them gave up holding him"
		return BOT_GYM_FAIL
	if(!bot.Adjacent(captive) && !other.Adjacent(captive))
		fail_reason = "nobody beside him"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/fixes1112/swap_hold_down/release_run()
	GLOB.bot_security_wanted -= WEAKREF(captive)
	if(bot)
		UnregisterSignal(bot, COMSIG_MOVABLE_MOVED)
	if(other)
		UnregisterSignal(other, COMSIG_MOVABLE_MOVED)
	return ..()

/datum/bot_scenario/fixes1112/swap_spot_short
	name = "swap: the second officer stops behind a colleague on the spot short of a dangerous man"
	desc = "Two officers with disablers after a man wanted for attempted murder, one five tiles short of him and the other a tile further. The one behind stops there, where the two of them used to take turns walking on to the one spot short of him and swapping the other off it. Batch 2026-11-12 run11: two officers in the Brig traded the spot every couple of seconds."
	job = "Security Officer"
	layout = list(
		"############",
		"#K.....OB..#",
		"############")
	time_limit = 30 SECONDS
	var/mob/living/carbon/human/other
	var/mob/living/carbon/human/suspect
	var/counting_from = 0
	var/moves = 0

/datum/bot_scenario/fixes1112/swap_spot_short/post_spawn()
	suspect = stand_in(first_marker("K"), "Wes Wanted")
	suspect.status_flags |= GODMODE //never down for the cuffs: the two of them keep their range the whole time
	var/datum/bot_wanted/W = new
	W.severity = BOT_CRIME_MURDER
	W.crime = "Attempted Murder"
	W.last_seen = get_turf(suspect)
	W.last_seen_at = world.time
	GLOB.bot_security_wanted[WEAKREF(suspect)] = W
	other = second_bot(first_marker("O"), "Sam Second")
	other.mind.assigned_role = "Security Officer"
	arm_with_disabler(bot)
	arm_with_disabler(other)
	brain.begin_arrest(suspect)
	other.bot_brain.begin_arrest(suspect)
	RegisterSignal(bot, COMSIG_MOVABLE_MOVED, PROC_REF(stepped))
	RegisterSignal(other, COMSIG_MOVABLE_MOVED, PROC_REF(stepped))

/// A disabler that won't run dry in the run: out of shots, an officer with another beside it goes in (keep_it_at_range())
/datum/bot_scenario/fixes1112/swap_spot_short/proc/arm_with_disabler(mob/living/carbon/human/H)
	var/obj/item/gun/energy/disabler/G = new(H)
	G.cell.maxcharge = 100000
	G.cell.charge = 100000
	H.put_in_hands(G)
	// And cuffs: with nothing to cuff him with, begin_arrest() (goals/security_patrol.dm) turns the arrest down, and neither officer moved
	H.equip_to_slot_or_del(new /obj/item/restraints/handcuffs(H), ITEM_SLOT_BACKPACK)

/datum/bot_scenario/fixes1112/swap_spot_short/make_goal()
	return null //the arrest is the job

/datum/bot_scenario/fixes1112/swap_spot_short/proc/stepped()
	SIGNAL_HANDLER
	moves++

/datum/bot_scenario/fixes1112/swap_spot_short/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(other) || QDELETED(suspect))
		fail_reason = "lost one of the others"
		return BOT_GYM_FAIL
	if(!counting_from)
		if(get_dist(bot, suspect) <= 6 && get_dist(other, suspect) <= 6)
			counting_from = world.time
			moves = 0
			log_line("both within six of him: [get_dist(bot, suspect)] and [get_dist(other, suspect)]")
		return BOT_GYM_PENDING
	if(moves > 3)
		fail_reason = "the two of them shuffled on and off the spot short of him: [moves] steps"
		return BOT_GYM_FAIL
	if(world.time < counting_from + 12 SECONDS)
		return BOT_GYM_PENDING
	var/mine = get_dist(bot, suspect)
	var/theirs = get_dist(other, suspect)
	if(min(mine, theirs) != 5 || max(mine, theirs) != 6)
		fail_reason = "ended [mine] and [theirs] tiles from him"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/fixes1112/swap_spot_short/release_run()
	GLOB.bot_security_wanted -= WEAKREF(suspect)
	if(bot)
		UnregisterSignal(bot, COMSIG_MOVABLE_MOVED)
	if(other)
		UnregisterSignal(other, COMSIG_MOVABLE_MOVED)
	return ..()

// <<< welded_scenarios.dm
// ---------------------------------------------------------------------------------------------
// Welded doors on the way (bot_doors.dm, the airlock CanAStarPass(); can_unweld() in reach_rules(), bot_pathing_permissive.dm)
// ---------------------------------------------------------------------------------------------

/// A welded airlock that wants no access, in the wall between two rooms, and the long way round open below it. The bot has no ID: an
/// airlock with no access set opens for anybody (check_access()).
/datum/bot_scenario/fixes1112/welded_long_way
	name = "walking: a welded door on the short way and no welder: it goes the long way round"
	desc = "A welded airlock that wants no access is the short way to the far side, and the long way round is open. With nothing to unweld it with, the bot goes the long way, on an everyday errand. Batch 2026-11-12 (bugs1112b): routes were planned through welded doors, tg's route check never asking about welding. A janitor's mop errand and six strolls in a row were each planned through the same welded maintenance door and given up at it (Vic Sorrento run3); 78 stops at welded doors in the batch, 26 errands given up there, at the abandoned maintenance doors and storerooms a round can start welded."
	time_limit = 25 SECONDS
	layout = list(
		"###########",
		"#B...X...G#",
		"#....#....#",
		"#....#....#",
		"#.........#",
		"###########")

/datum/bot_scenario/fixes1112/welded_long_way/make_goal()
	var/datum/bot_goal/gym_reach/G = ..()
	G.lawful = TRUE //an everyday errand, as a stroll or a mop round is
	return G

/datum/bot_scenario/fixes1112/welded_long_way/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("welded shut - not mine to force"))
		fail_reason = "planned its way through the welded door, walked up to it and stopped there"
		return BOT_GYM_FAIL
	return ..()

/datum/bot_scenario/fixes1112/welded_long_way/check_success_conditions()
	var/obj/machinery/door/airlock/A = first_placed("X")
	if(QDELETED(A) || !A.welded)
		return "got through the welded door instead of going round"
	return null

/// The guard: what a bot that can deal with a welded door did before, it still does.
/datum/bot_scenario/fixes1112/welded_long_way/with_welder
	name = "walking: a welded door on the short way and a welder in hand: it unwelds the door and goes through"
	desc = "The same arena, with a welder in the bot's hand. It plans through the welded door and unwelds it when it gets there (clear_one_blocker(), bot_items.dm), as it did before: only a bot with nothing to unweld it with goes round."
	time_limit = 30 SECONDS
	kit_hands = list(/obj/item/weldingtool)

/datum/bot_scenario/fixes1112/welded_long_way/with_welder/check_success_conditions()
	var/obj/machinery/door/airlock/A = first_placed("X")
	if(QDELETED(A))
		return "broke the door down"
	if(A.welded)
		return "went the long way round with a welder in its hand"
	return null

/// The welded door is the only way. A route search that finds no way there is kept 20 seconds as the region the bot can reach
/// (remember_region(), bot_pathing_permissive.dm), under its reach_rules(): those have to know whether it can unweld a door.
/datum/bot_scenario/fixes1112/welded_only_way
	name = "walking: a welded door is the only way: no welder, it doesn't walk up to it; handed one, it unwelds the door and goes through"
	desc = "A welded airlock that wants no access is the only way to the far side. With nothing to unweld it with there's no way there, and the bot doesn't walk up to the door. Handed a welder three seconds in and sent again, it goes through at once: the search that found no way was for a bot without one, and isn't taken as the answer for a bot with one. Batch 2026-11-12 (bugs1112b): 78 stops at welded doors on everyday errands, the route planned through each of them (Vic Sorrento run3, Dana Petrov run12)."
	time_limit = 18 SECONDS //inside the 20 seconds a region is kept (BOT_REGION_FLOOD_TTL)
	max_goal_attempts = 2
	layout = list(
		"##########",
		"#B...X..G#",
		"#....#####",
		"#....#####",
		"##########")
	var/handed_at = 0

/datum/bot_scenario/fixes1112/welded_only_way/make_goal()
	var/datum/bot_goal/gym_reach/G = ..()
	G.lawful = TRUE
	return G

/datum/bot_scenario/fixes1112/welded_only_way/issue_goal()
	if(goal_attempts && !handed_at)
		return //the second go once it has a welder
	..()

/datum/bot_scenario/fixes1112/welded_only_way/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!handed_at)
		if(bot_transcript_said("welded shut - not mine to force"))
			fail_reason = "walked up to the welded door with nothing to unweld it with"
			return BOT_GYM_FAIL
		if(world.time < start_time + 3 SECONDS || brain.current_goal)
			return BOT_GYM_PENDING
		bot.put_in_hands(new /obj/item/weldingtool(bot))
		handed_at = world.time
		log_line("handed a welder")
		return BOT_GYM_PENDING
	return ..()

/datum/bot_scenario/fixes1112/welded_only_way/check_success_conditions()
	var/obj/machinery/door/airlock/A = first_placed("X")
	if(QDELETED(A))
		return "broke the door down"
	return null

// <<< badair_scenarios.dm
// <<< badair_scenarios.dm
// ---------------------------------------------------------------------------------------------
// Bad air (fixes 2026-11-12, batch bugs1112b): turned down once for the air somewhere and not sent there again every look (bot_goals.dm
// assign_goal(), refused_for_air()); the supermatter's next job past one in bad air (goals/setup_supermatter.dm sm_part_free()); a miner's
// tank on it, not in a hand, before it counts as ready for Lavaland (goals/mining.dm ready_for_lavaland(), dress_for_lavaland)
// ---------------------------------------------------------------------------------------------

/// Let out of a cell, its shoes are in the cell locker, and the duty that sends it back for its things (/datum/bot_duty/collect_confiscated,
/// goals/released_prisoner.dm) is asked once a second while it's idle. Layout letter v: a floor with no air, walled in, the locker on it.
/datum/bot_scenario/fixes1112/air_turned_down_once
	name = "brig: its things in a cell locker where there's no air, it's turned down once and not sent for them again every look"
	desc = "Let out of a cell, its shoes are in the cell locker, which stands where there's no air. The duty that sends it back for its things asks once a second, and the air turns it down: once, and then nothing there is taken on for a minute. Batch bugs1112b run5: a saboteur opened a plasma canister by the Brig (Fore Primary Hallway, 18:40:34); the Head of Security, let out of Cell 4, was turned down for its locker 41 times in 16 seconds and an assistant out of Cell 3 for its locker 20 times. Run3: three officers 117 times for a cuffed traitor lying in Atmospherics as its air went."
	job = "Assistant"
	time_limit = 30 SECONDS
	max_goal_attempts = 10
	layout = list(
		"#########",
		"#B....#v#",
		"#########")
	var/obj/structure/closet/locker
	var/obj/item/clothing/shoes/sneakers/brown/shoes
	var/started

/datum/bot_scenario/fixes1112/air_turned_down_once/setup()
	locker = place("v", new /obj/structure/closet(first_marker("v")))
	shoes = new(locker)

/datum/bot_scenario/fixes1112/air_turned_down_once/post_spawn()
	bot_note_confiscated(bot, shoes, ITEM_SLOT_FEET, locker)
	started = world.time

/// The duty, asked once a second while the bot is idle (as /datum/bot_scenario/duty/issue_goal(), scenarios_duties.dm)
/datum/bot_scenario/fixes1112/air_turned_down_once/issue_goal()
	var/datum/bot_duty/D = bot_duty_of(/datum/bot_duty/collect_confiscated)
	if(D?.try_start(brain))
		goal_attempts++
		log_line("[D.name]: started on [brain.current_goal ? brain.current_goal.type : "it"] (attempt [goal_attempts]/[max_goal_attempts])")

/datum/bot_scenario/fixes1112/air_turned_down_once/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/turned_down = 0
	for(var/line in transcript)
		if(findtext(line, "somewhere I can't breathe"))
			turned_down++
	if(turned_down > 1)
		fail_reason = "sent for its things and turned down for the air [turned_down] times in [round((world.time - started) / 10)] s"
		return BOT_GYM_FAIL
	if(!turned_down && world.time > started + 5 SECONDS)
		fail_reason = "never sent for its things: the duty didn't ask, so this shows nothing"
		return BOT_GYM_FAIL
	if(!length(brain.confiscated))
		fail_reason = "set off for its things in the airless locker, or gave them up"
		return BOT_GYM_FAIL
	return world.time > started + 20 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/// A crystal losing integrity (a hugbox shard standing in for the station's, at no power, so with no radiation round it) and two of its
/// emitters still switched on (no cable, and kept from processing, which would switch them off). The one made first, which the job list
/// comes to first, stands in a walled-in pocket with no air; the other is down the corridor. Layout letters: Y the crystal, v the airless
/// pocket, e the emitter in reach. The crystal's two duties are asked once a second while the engineer is idle.
/datum/bot_scenario/fixes1112/sm_next_job_past_bad_air
	name = "supermatter: the first job on its list is where there's no air, so it does the next one it can get to"
	desc = "The crystal's losing integrity and two of its emitters are on. The one its list comes to first stands where there's no air, and the engineer has no hardsuit; the other is down the corridor. It switches that one off, rather than being handed the airless one, turned down, and handed it again. Batch bugs1112b run4: the crystal's pipes burst in flames (18:38:53), the pump 'External Gas to Loop' in the bad air came first on its list from then on, and an engineer with no hardsuit to be had (Terry Mwangi) was handed it and turned it down 74 times, 18:39:07 to 18:40:33."
	job = "Station Engineer"
	station_wide = TRUE //it stands in for the station's own crystal while it runs
	time_limit = 20 SECONDS
	max_goal_attempts = 10
	layout = list(
		"#############",
		"#B........e##",
		"###########v#",
		"#############",
		"######Y######",
		"#############")
	var/obj/machinery/power/supermatter_crystal/crystal
	var/obj/machinery/power/supermatter_crystal/stations_own
	var/obj/machinery/power/emitter/anchored/airless
	var/obj/machinery/power/emitter/anchored/reachable
	/// The job list comes to the airless one first, as this needs
	var/order_ok = FALSE

/datum/bot_scenario/fixes1112/sm_next_job_past_bad_air/setup()
	crystal = place("Y", new /obj/machinery/power/supermatter_crystal/shard/hugbox(first_marker("Y")))
	crystal.anchored = TRUE
	SSair.stop_processing_machine(crystal) //only here to be failing
	crystal.power = 0 //no radiation round it, so no radiation suit in the plan
	crystal.damage = crystal.explosion_point * 0.3
	stations_own = GLOB.main_supermatter_engine
	GLOB.main_supermatter_engine = crystal

/// The emitters once the bot's brain has filed every obj there is (bot_registry.dm), so the job list has them in the order they're made.
/datum/bot_scenario/fixes1112/sm_next_job_past_bad_air/post_spawn()
	airless = place("v", new /obj/machinery/power/emitter/anchored(first_marker("v")))
	reachable = place("e", new /obj/machinery/power/emitter/anchored(first_marker("e")))
	for(var/obj/machinery/power/emitter/E in list(airless, reachable))
		STOP_PROCESSING(SSfastprocess, E) //no cable: processing would switch it off again
		E.setDir(NORTH) //facing the wall: no beam to keep clear of
		E.active = TRUE
		E.update_icon()
	for(var/obj/machinery/power/emitter/anchored/E as anything in bot_instances_of(/obj/machinery/power/emitter/anchored))
		if(E == airless || E == reachable)
			order_ok = (E == airless)
			break
	bot_refresh_hazards()

/// The crystal's two duties, the urgent one first (bot_duties.dm run_duties())
/datum/bot_scenario/fixes1112/sm_next_job_past_bad_air/issue_goal()
	for(var/duty_type in list(/datum/bot_duty/crystal_emergency, /datum/bot_duty/supermatter))
		var/datum/bot_duty/D = bot_duty_of(duty_type)
		if(D?.try_start(brain))
			goal_attempts++
			log_line("[D.name]: started on [brain.current_goal?.target || "it"] (attempt [goal_attempts]/[max_goal_attempts])")
			return

/datum/bot_scenario/fixes1112/sm_next_job_past_bad_air/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!order_ok)
		fail_reason = "the job list comes to the emitter in reach first, so this shows nothing"
		return BOT_GYM_FAIL
	if(!brain.sm_crystal_failing())
		fail_reason = "the crystal doesn't read as failing: nothing to do"
		return BOT_GYM_FAIL
	if(!brain.in_bad_air(airless) || brain.in_bad_air(reachable))
		fail_reason = "the air isn't as this needs it: none round one emitter, good air round the other"
		return BOT_GYM_FAIL
	if(!airless.active)
		fail_reason = "switched off the emitter where there's no air"
		return BOT_GYM_FAIL
	return reachable.active ? BOT_GYM_PENDING : BOT_GYM_PASS

/datum/bot_scenario/fixes1112/sm_next_job_past_bad_air/on_timeout()
	var/turned_down = 0
	for(var/line in transcript)
		if(findtext(line, "somewhere I can't breathe"))
			turned_down++
	fail_reason = "never switched off the emitter it could get to; handed the one where there's no air and turned it down [turned_down] times"
	return BOT_GYM_FAIL

/datum/bot_scenario/fixes1112/sm_next_job_past_bad_air/release_run()
	for(var/obj/machinery/power/emitter/E in list(airless, reachable))
		E.active = FALSE //left on, it would be on the job list of every crystal on this level after
		E.update_icon()
	if(GLOB.main_supermatter_engine == crystal)
		GLOB.main_supermatter_engine = stations_own
	. = ..()
	bot_refresh_hazards()

/// A miner with its mask on and its tank in a hand, the webbing on its belt, a flashlight in one pocket and the ore satchel in the other
/// (the miner in bugs1112a run7 had a beer where the flashlight is). Dressing for Lavaland (goals/mining.dm dress_for_lavaland) puts the
/// flashlight in its bag and the tank in that pocket, and only then is it ready to go down.
/datum/bot_scenario/fixes1112/miner_tank_on
	name = "mining: a tank held in a hand isn't ready for Lavaland, so a pocket goes into the bag and the tank into the pocket"
	desc = "A miner dressing for Lavaland with its mask on and its tank in a hand, the webbing on its belt, a flashlight in one pocket and the ore satchel in the other. It puts the flashlight in its bag and the tank in that pocket, and the satchel stays where it picks the ore up. Batch bugs1112a run7 (Cam Oyelaran): no room on it for the tank, so it stayed in a hand (18:29:59), the hand counted as ready, the miner went down, the tank was knocked out of the hand as the shuttle set off (18:30:10), and at the outpost it was turned down for the air 63 times for the next rock face."
	job = "Shaft Miner"
	time_limit = 10 SECONDS
	kit_hands = list(/obj/item/tank/internals/emergency_oxygen)
	layout = list(
		"#####",
		"#B..#",
		"#####")
	var/obj/item/tank/internals/emergency_oxygen/tank
	var/obj/item/flashlight/torch
	var/obj/item/storage/bag/ore/satchel

/datum/bot_scenario/fixes1112/miner_tank_on/post_spawn()
	tank = locate() in bot.held_items
	bot.equip_to_slot_or_del(new /obj/item/clothing/mask/gas/explorer(bot), ITEM_SLOT_MASK)
	bot.equip_to_slot_or_del(new /obj/item/storage/belt/mining(bot), ITEM_SLOT_BELT)
	torch = new(bot)
	bot.equip_to_slot_or_del(torch, ITEM_SLOT_LPOCKET)
	satchel = new(bot)
	bot.equip_to_slot_or_del(satchel, ITEM_SLOT_RPOCKET)

/datum/bot_scenario/fixes1112/miner_tank_on/make_goal()
	return new /datum/bot_goal/dress_for_lavaland()

/datum/bot_scenario/fixes1112/miner_tank_on/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(tank) || QDELETED(torch) || QDELETED(satchel) || !istype(bot.wear_mask, /obj/item/clothing/mask/gas/explorer) || !bot.belt)
		fail_reason = "set-up: the tank, the flashlight, the satchel, the mask or the belt didn't make it"
		return BOT_GYM_FAIL
	if(bot.is_holding(tank))
		fail_reason = brain.ready_for_lavaland() ? "counts itself ready for Lavaland with its tank only in a hand" : "its tank's still in a hand"
		return BOT_GYM_FAIL
	if(bot.l_store != tank && bot.r_store != tank && bot.belt != tank)
		fail_reason = "its tank isn't anywhere it can reach the valve: it's in [tank.loc]"
		return BOT_GYM_FAIL
	if(bot.l_store != satchel && bot.r_store != satchel && bot.belt != satchel)
		fail_reason = "the ore satchel came out of its pocket, where it picks the ore up"
		return BOT_GYM_FAIL
	if(!brain.ready_for_lavaland())
		fail_reason = "the tank's on it and it still isn't ready for Lavaland"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

// <<< brig2_scenarios.dm
// <<< brig2_scenarios.dm
// ---------------------------------------------------------------------------------------------
// brig2 (fixes 2026-11-12, round 3, from bugs1112b/a/base): a doctor at a prisoner Security's keeping for it, down in crit
// (goals/treat_patient.dm stabilise), an officer walking a prisoner out past a pet sat in the doorway (bot_movement.dm haul_past()), and a
// cook with more plates out of the machine than hands (goals/cook.dm). Nothing only the fixes add is named, so the "before" build compiles.
//
// Layout letters used here: C the prisoner, O the officer keeping them, q a second casualty, s a sleeper, P a pug, i/d/l the cell's
// timer, door and locker, p a food processor, t the serving table.
// ---------------------------------------------------------------------------------------------

/// A doctor, and a prisoner in cuffs down in crit (110 brute: -10) that an officer is keeping for a doctor: the officer's brain set on
/// brig_care for them by hand, with the claim on them start_brig_care() takes, holding them, and nothing to walk (a goal with no strategy
/// is left alone, handle_goal()). Medical was called for them, and this doctor has come: the scenario asks for its round as
/// bot_request_kind/medical/attend() does on arrival. No name or layout of its own.
/datum/bot_scenario/fixes1112/brig2_kept
	job = "Medical Doctor"
	kit_backpack = list(/obj/item/reagent_containers/hypospray/medipen, /obj/item/reagent_containers/hypospray/medipen, /obj/item/stack/medical/bruise_pack)
	time_limit = 30 SECONDS
	max_goal_attempts = 1
	var/mob/living/carbon/human/prisoner
	var/mob/living/carbon/human/officer
	var/asked = FALSE

/datum/bot_scenario/fixes1112/brig2_kept/post_spawn()
	give_job_id(list(ACCESS_MEDICAL))
	prisoner = stand_in(first_marker("C"), "Pat Prisoner")
	prisoner.handcuffed = new /obj/item/restraints/handcuffs(prisoner)
	prisoner.update_handcuffed()
	prisoner.apply_damage(110, BRUTE, BODY_ZONE_CHEST)
	officer = second_bot(first_marker("O"), "Sam Officer")
	officer.mind.assigned_role = "Security Officer"
	var/datum/bot_goal/brig_prisoner/brig_care/G = new(prisoner, null)
	officer.bot_brain.current_goal = G
	officer.bot_brain.state = BOT_STATE_GOAL
	GLOB.bot_work_claims[REF(prisoner)] = officer.bot_brain
	officer.start_pulling(prisoner)
	log_line("Sam Officer keeps [prisoner] (at [round(prisoner.health)], [prisoner.stat == CONSCIOUS ? "on their feet" : "down"]) by the door for a doctor, holding them")

/datum/bot_scenario/fixes1112/brig2_kept/make_goal()
	return null

/// Medical called for the prisoner, and the doctor's here: its round, once
/datum/bot_scenario/fixes1112/brig2_kept/issue_goal()
	if(asked)
		return
	asked = TRUE
	goal_attempts++
	brain.called_patient = WEAKREF(prisoner)
	brain.called_patient_until = world.time + 2 MINUTES
	log_line("the doctor answered the call for [prisoner]: its round")
	brain.try_medical_round()

/// Seen to where they lie: the epinephrine in them, or a stabilise gone through
/datum/bot_scenario/fixes1112/brig2_kept/proc/seen_to()
	return prisoner.reagents?.has_reagent(/datum/reagent/medicine/epinephrine) || bot_transcript_said("goal /datum/bot_goal/stabilise succeeded")

/// The officer's hold on them taken for a doctor already at them, and the doctor turned away
/datum/bot_scenario/fixes1112/brig2_kept/proc/turned_away()
	return bot_transcript_said("is already being seen to - leaving /datum/bot_goal/stabilise")

/// Whether `first` is in the transcript ahead of `second` (or without it)
/datum/bot_scenario/fixes1112/brig2_kept/proc/said_first(first, second)
	var/first_at = 0
	var/second_at = 0
	var/i = 0
	for(var/line in transcript)
		i++
		if(!first_at && findtext(line, first))
			first_at = i
		if(!second_at && findtext(line, second))
			second_at = i
	return first_at && (!second_at || first_at < second_at)

/datum/bot_scenario/fixes1112/brig2_kept/release_run()
	if(prisoner)
		GLOB.bot_work_claims -= REF(prisoner)
	return ..()

/datum/bot_scenario/fixes1112/brig2_kept/first_aid
	name = "brig: a doctor at a prisoner Security's keeping for it, down in crit, gives first aid there and leaves the officer its hold"
	desc = "A prisoner in cuffs at -10, held by the officer keeping them by the Brig door for Medical, and the doctor who answered the call beside them with medipens and a bruise pack. It gives them first aid where they lie, and the officer's claim on them stays the officer's. The officer's escort claimed them, and the doctor's first aid (stabilise, one to a casualty) took that for another medic at them: 'already being seen to - leaving stabilise to them', 14 times at a prisoner down in crit in bugs1112b/a/base, and four of those prisoners died where they lay within the minute (bugs1112b run9 Sam Delacroix, bugs1112a run8 Val Castillo and run12 Corey Ishikawa, bugs1112base run6 Morgan Vance)."
	layout = list(
		"#########",
		"#..BCO..#",
		"#########")

/datum/bot_scenario/fixes1112/brig2_kept/first_aid/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(prisoner) || prisoner.stat == DEAD)
		fail_reason = "the prisoner died"
		return BOT_GYM_FAIL
	if(turned_away())
		fail_reason = "took the officer keeping the prisoner for a doctor for a doctor already at them, and left them"
		return BOT_GYM_FAIL
	if(!seen_to())
		return BOT_GYM_PENDING
	if(GLOB.bot_work_claims[REF(prisoner)] != officer.bot_brain)
		fail_reason = "saw to the prisoner, and took Security's hold on them off the officer"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/fixes1112/brig2_kept/first_aid/on_timeout()
	fail_reason = "never gave the prisoner first aid"
	return BOT_GYM_FAIL

/datum/bot_scenario/fixes1112/brig2_kept/before_the_next
	name = "brig: a doctor called to a prisoner down in crit by the Brig door sees to them before dragging anybody else to a sleeper"
	desc = "As the last, with a sleeper in the room and a second casualty down in crit at the far end that nobody's holding. The doctor came for the prisoner: it gives them first aid before it takes anybody to the sleeper. Its round went down its list, and a sleeper run for somebody else comes before first aid: a doctor answering the call for a prisoner at -3 by MetaStation's Brig door dragged a man from the Theatre to the sleeper first, and the prisoner died at the door (bugs1112base run6, Max Adeyemi and Morgan Vance)."
	layout = list(
		"############",
		"#s...BCO...#",
		"#.........q#",
		"############")
	var/mob/living/carbon/human/other_patient

/datum/bot_scenario/fixes1112/brig2_kept/before_the_next/setup()
	place("s", new /obj/machinery/sleeper(first_marker("s")))

/datum/bot_scenario/fixes1112/brig2_kept/before_the_next/post_spawn()
	..()
	other_patient = stand_in(first_marker("q"), "Quinn Other")
	other_patient.apply_damage(130, BRUTE, BODY_ZONE_CHEST)
	log_line("[other_patient] is down in crit too (at [round(other_patient.health)]), and nobody's holding them")

/datum/bot_scenario/fixes1112/brig2_kept/before_the_next/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(prisoner) || prisoner.stat == DEAD)
		fail_reason = "the prisoner died"
		return BOT_GYM_FAIL
	if(turned_away())
		fail_reason = "took the officer keeping the prisoner for a doctor for a doctor already at them, and left them"
		return BOT_GYM_FAIL
	if(said_first("trying /datum/bot_strategy/escort", "trying /datum/bot_strategy/stabilise"))
		fail_reason = "went to take [other_patient || "somebody else"] to the sleeper before seeing to the prisoner it was called to"
		return BOT_GYM_FAIL
	return seen_to() ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/fixes1112/brig2_kept/before_the_next/on_timeout()
	fail_reason = "never gave the prisoner first aid"
	return BOT_GYM_FAIL

// An officer walking a prisoner out of a nook whose one way out has the Head of Security's pug sat in it, to a cell, as
// /datum/bot_scenario/brigged (scenarios_asks.dm) does it.

/datum/bot_scenario/fixes1112/brig2_pug
	name = "brig: walking a prisoner out past the HoS's pug sat in the doorway, the officer nudges the dog aside and cells them"
	desc = "An officer has cuffed a trespasser in a nook whose one way out is the tile the pug Handcuffs sits on, as in Hippie's Head of Security's Office. It nudges the dog aside and walks them to the cell. It waited on the dog with the prisoner in tow ('Handcuffs is in the way with Rhea Asker in tow - waiting for them to move'), the wait ran out and the escort was given up as stalled, the prisoner left in cuffs in the office: 17 times in bugs1112b/a/base (bugs1112b run1, run5, run7 Ollie Strand three times; bugs1112base run5 four times)."
	job = "Security Officer"
	kit_backpack = list(/obj/item/restraints/handcuffs)
	layout = list(
		"##########",
		"#CBP.....#",
		"####...i.#",
		"######d###",
		"#####...##",
		"#####..l##",
		"##########")
	time_limit = 60 SECONDS
	var/mob/living/carbon/human/prisoner
	var/mob/living/simple_animal/pet/dog/pug/pug
	var/obj/machinery/door_timer/timer

/datum/bot_scenario/fixes1112/brig2_pug/setup()
	var/id = "gymcell[rand(1, 99999)]"
	var/obj/machinery/door/window/brigdoor/door = new(first_marker("d"))
	door.dir = SOUTH
	door.id = id
	place("d", door)
	var/obj/structure/closet/secure_closet/brig/locker = new(first_marker("l"))
	locker.id = id
	place("l", locker)
	timer = new(first_marker("i"))
	timer.id = id
	timer.targets = list(door, locker)
	timer.stat &= ~BROKEN
	place("i", timer)
	pug = new(first_marker("P"))
	pug.name = "Handcuffs"
	pug.real_name = "Handcuffs"
	pug.wander = FALSE //it stays sat where it is, as the HoS's pug did through every one of these
	pug.stop_automated_movement = TRUE

/datum/bot_scenario/fixes1112/brig2_pug/post_spawn()
	give_job_id(list(ACCESS_SECURITY, ACCESS_BRIG))
	prisoner = stand_in(first_marker("C"), "Pat Prisoner")
	prisoner.handcuffed = new /obj/item/restraints/handcuffs(prisoner)
	prisoner.update_handcuffed()
	var/datum/bot_wanted/W = new
	W.crime = "Assault"
	W.severity = BOT_CRIME_MINOR
	GLOB.bot_security_wanted[WEAKREF(prisoner)] = W
	log_line("[prisoner] is cuffed in the nook, and [pug] sits in the one way out")

/datum/bot_scenario/fixes1112/brig2_pug/make_goal()
	var/datum/bot_goal/brig_prisoner/G = new()
	G.prisoner = prisoner
	return G

/datum/bot_scenario/fixes1112/brig2_pug/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("is in the way with Pat Prisoner in tow"))
		fail_reason = "stood waiting on the pug in the doorway with the prisoner in tow"
		return BOT_GYM_FAIL
	if(bot_transcript_said("has stalled with nothing walking it") || bot_transcript_said("giving up on /datum/bot_goal/brig_prisoner"))
		fail_reason = "gave the prisoner up in the nook"
		return BOT_GYM_FAIL
	if(QDELETED(pug) || pug.stat != CONSCIOUS)
		fail_reason = "the pug got hurt"
		return BOT_GYM_FAIL
	return timer.timing ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/fixes1112/brig2_pug/on_timeout()
	fail_reason = "never got the prisoner to the cell"
	return BOT_GYM_FAIL

/datum/bot_scenario/fixes1112/brig2_pug/release_run()
	if(prisoner)
		GLOB.bot_security_wanted -= WEAKREF(prisoner)
	return ..()

// A cook with two hands and a full bag, and three plates out of the processor (run_kitchen_machine, goals/cook.dm), on its own round as
// /datum/bot_scenario/fixes1112/kitchen_duty.

/datum/bot_scenario/fixes1112/kitchen_duty/plates_left_for_later
	name = "cook: three plates out and two hands, it leaves the third at the processor and comes back for it"
	desc = "Two potatoes in its hands and one in a pocket, the bag and belt full: three tater tots come out of the processor, four tiles from the counter. It takes the two it has hands for, puts them out, and goes back for the third, rather than set a plate down by the processor for each one it picks up. That way, plates were left beside the machine out of the counter's reach and the cook went back for them later and kept or ate them: 11 in 10 batches in bugs1112b (run11 Marlow Singh, two steaks of three; run6 Lee Montague ate the carrot fries it set down), about 47 a batch in bugs1112base."
	layout = list(
		"###########",
		"#..p...t..#",
		"#B........#",
		"###########")
	kit_hands = list(/obj/item/reagent_containers/food/snacks/grown/potato, /obj/item/reagent_containers/food/snacks/grown/potato)
	// 7 x 3: full
	kit_backpack = list(/obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher, /obj/item/extinguisher)

/// The third potato in a pocket, before kitchen_fill_pockets_and_belt() fills the pockets: the pocket's free once it's in the processor,
/// and a plate never goes in a pocket (put_away() doesn't use them)
/datum/bot_scenario/fixes1112/kitchen_duty/plates_left_for_later/post_spawn()
	bot.equip_to_slot_or_del(new /obj/item/reagent_containers/food/snacks/grown/potato(bot), ITEM_SLOT_LPOCKET)
	..()

/datum/bot_scenario/fixes1112/kitchen_duty/plates_left_for_later/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("setting the tator tot down"))
		fail_reason = "set a plate down by the processor to pick up the next"
		return BOT_GYM_FAIL
	return served() >= 3 ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/fixes1112/kitchen_duty/plates_left_for_later/on_timeout()
	fail_reason = "put [served()] of the 3 plates out on the counter"
	return BOT_GYM_FAIL

// <<< cargo_air_scenarios.dm
// <<< cargo_air_scenarios.dm
// ---------------------------------------------------------------------------------------------
// Cargo in air it can't breathe (the user's ruling, 2026-11-12): in for the crate on its mask and tank, in a fire suit and helmet as well
// if the air's hot, in a space suit from EVA's storage for a vacuum, and the kit off again once the crate's out. The loading doors stay shut.
// Arena layout letters: Q where the crate's to go, e an external airlock, n the room past it, k the crate, z a fire closet, U EVA's suit
// storage unit.
// ---------------------------------------------------------------------------------------------

/// The unload to the arena's own spot for it: an arena has no cargo bay (find_bay_spot(), goals/cargo.dm)
/datum/bot_goal/unload_crate/fixes1112_arena
	var/turf/arena_drop

/datum/bot_goal/unload_crate/fixes1112_arena/resolve_target(datum/bot_brain/bot)
	drop_spot = arena_drop
	if(QDELETED(target) || !drop_spot)
		target = null

/// cargo-air-on-internals (goals/cargo.dm, goals/refill_internals.dm, bot_goals.dm, bot_doors.dm). A crate in a small room past an external
/// airlock whose air the cargo technician can't breathe, at a normal pressure and temperature, and a breath mask and an emergency tank in
/// its bag. The unload is given while it's idle (the cargo round's own pick is the shuttle scenario's to judge); once the crate's out, the
/// cargo round is asked instead, as a cargo technician's is.
/datum/bot_scenario/fixes1112/crate_air
	name = "cargo: a crate in nitrogen, it goes in for it on its mask and tank and takes them off after"
	desc = "A crate in a small room past an external airlock, full of nitrogen at 101 kPa and 20 C, and a breath mask and an emergency oxygen tank in the cargo technician's bag. It puts the mask on and opens the tank where it stands, goes through the airlock, pulls the crate out, and once it's out shuts the valve and puts the mask back in its bag. It's never in the nitrogen with its tank shut. The user's ruling, 2026-11-12: Cargo uses internals for a crate in air it can't breathe. Batch bugs1112b run5: Science's silver sat aboard the supply shuttle in air nobody could breathe from about ten minutes in to the end of the shift ('The silver sheets crate is somewhere I can't breathe and I'm not suited up - leaving it for now', 23 times), the loading doors were opened on it twice and Engineering called five times, with an emergency tank in each cargo technician's bag."
	job = "Cargo Technician"
	time_limit = 60 SECONDS
	max_goal_attempts = 10
	kit_backpack = list(/obj/item/clothing/mask/breath, /obj/item/tank/internals/emergency_oxygen) //as a crew member's survival box has
	layout = list(
		"###############",
		"#Q.........####",
		"#..........enk#",
		"#..B.......#nn#",
		"###############")
	/// The air in the room past the airlock (the n and k tiles): 104 mol a tile is about 101 kPa at 20 C
	var/room_air = "n2=104;TEMP=293.15"
	var/obj/structure/closet/crate/crate
	var/setup_problem
	/// The airlock's x: the crate's out once it's west of that
	var/door_x = 0
	/// When the crate came out
	var/unloaded_at

/datum/bot_scenario/fixes1112/crate_air/setup()
	var/turf/open/door_spot = first_marker("e")
	door_x = door_spot.x
	place("e", new /obj/machinery/door/airlock/external(door_spot))
	for(var/char in list("n", "k"))
		for(var/turf/open/F in markers[char])
			F.air.parse_gas_string(room_air)
			F.update_visuals()
			SSair.add_to_active(F)
	crate = place("k", new /obj/structure/closet/crate(first_marker("k")))

/datum/bot_scenario/fixes1112/crate_air/post_spawn()
	..()
	give_job_id(list(ACCESS_CARGO))
	var/turf/open/crate_spot = first_marker("k")
	if(brain.turf_air_is_breathable(crate_spot))
		setup_problem = "setup: the air by the crate at [bot_coord(crate_spot)] can be breathed ([round(crate_spot.air.return_pressure(), 0.1)] kPa, [round(crate_spot.air.temperature)] K)"
	else if(!brain.turf_air_is_breathable(first_marker("Q")))
		setup_problem = "setup: the air where the crate's to go, at [bot_coord(first_marker("Q"))], can't be breathed"

/datum/bot_scenario/fixes1112/crate_air/issue_goal()
	if(setup_problem || QDELETED(crate))
		return
	if(unloaded_at)
		var/datum/bot_duty/D = bot_duty_of(/datum/bot_duty/cargo)
		D?.try_start(brain) //the cargo round, asked while it's idle as a cargo technician's is (goals/cargo.dm): what takes the kit off again
		return
	goal_attempts++
	if(before_unload())
		return
	var/datum/bot_goal/unload_crate/fixes1112_arena/G = new(crate)
	G.arena_drop = first_marker("Q")
	log_line("the unload of [crate] given (attempt [goal_attempts]/[max_goal_attempts])")
	if(!brain.assign_goal(G))
		log_line("assign_goal refused")

/// What it does before it's given the unload: TRUE if that's under way instead
/datum/bot_scenario/fixes1112/crate_air/proc/before_unload()
	return FALSE

/// What was wrong with how it went in, or null
/datum/bot_scenario/fixes1112/crate_air/proc/kit_problem()
	var/turf/open/here = get_turf(bot)
	if(!unloaded_at && istype(here) && !brain.turf_air_is_breathable(here) && !bot.internal)
		return "in air it can't breathe at [bot_coord(here)] with its tank shut"
	return null

/// Still in what it put on for the air
/datum/bot_scenario/fixes1112/crate_air/proc/still_kitted()
	return bot.internal || istype(bot.wear_mask, /obj/item/clothing/mask/breath)

/// What it has on for the air, for a failure
/datum/bot_scenario/fixes1112/crate_air/proc/kit_text()
	return "tank [bot.internal ? "open" : "shut"], wearing [bot.wear_mask || "no mask"], [bot.wear_suit || "no suit"] and [bot.head || "nothing on its head"]"

/// What a pass also asks, once the crate's out and the kit's off
/datum/bot_scenario/fixes1112/crate_air/proc/pass_check()
	return BOT_GYM_PASS

/datum/bot_scenario/fixes1112/crate_air/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(setup_problem)
		fail_reason = setup_problem
		return BOT_GYM_FAIL
	if(QDELETED(crate))
		fail_reason = "the crate is gone"
		return BOT_GYM_FAIL
	GLOB.bot_cargo_strays -= crate //an unload given up puts it there, where another arena's cargo technician would go for it
	var/problem = kit_problem()
	if(problem)
		fail_reason = problem
		return BOT_GYM_FAIL
	if(!unloaded_at)
		var/turf/crate_at = get_turf(crate)
		if(brain.crates_unloaded < 1 || !crate_at || crate_at.x >= door_x)
			return BOT_GYM_PENDING
		unloaded_at = world.time
		log_line("the crate is out, at [bot_coord(crate_at)]")
	if(!bot_transcript_said("kitted out for the air at"))
		fail_reason = "brought the crate out without kitting up for the air it was in"
		return BOT_GYM_FAIL
	if(still_kitted())
		if(world.time > unloaded_at + 20 SECONDS)
			fail_reason = "still kitted out 20 s after the crate was out: [kit_text()]"
			return BOT_GYM_FAIL
		return BOT_GYM_PENDING
	return pass_check()

/datum/bot_scenario/fixes1112/crate_air/on_timeout()
	if(unloaded_at)
		fail_reason = "timed out with the crate out and the kit still on: [kit_text()]"
	else
		fail_reason = "timed out: the crate's still at [crate ? bot_coord(get_turf(crate)) : "nowhere"], [brain.crates_unloaded] unloaded"
	return BOT_GYM_FAIL

/datum/bot_scenario/fixes1112/crate_air/release_run()
	GLOB.bot_cargo_strays -= crate
	GLOB.bot_cargo_brought_in -= crate
	return ..()

/// The same, the room's air at 800 K and a normal pressure, and a fire closet beside the bot (the user's ruling: a fire suit if one's to be had)
/datum/bot_scenario/fixes1112/crate_air/hot
	name = "cargo: a crate in air hot enough to burn, it puts on a fire suit and helmet from the fire closet and goes in on its tank"
	desc = "The room past the airlock holds air at 800 K and about 101 kPa, and there's a fire closet beside the cargo technician. It takes the fire suit and the firefighter helmet out of the closet and puts them on, then the mask and the tank, goes in for the crate, and takes the lot off once the crate's out: the suit left on the floor, the helmet and mask in its bag. It doesn't pull itself out of the hot air it's dressed for, and it's never in air over the body's heat limit without both on and its tank open. The user's ruling, 2026-11-12: Cargo uses internals and, if one's to be had, a fire suit to grab the crate."
	time_limit = 90 SECONDS
	layout = list(
		"###############",
		"#Q.........####",
		"#..........enk#",
		"#zB........#nn#",
		"###############")
	room_air = "o2=8;n2=30;TEMP=800" //38 mol a tile: about 101 kPa at 800 K

/datum/bot_scenario/fixes1112/crate_air/hot/setup()
	..()
	place("z", new /obj/structure/closet/firecloset(first_marker("z")))

/datum/bot_scenario/fixes1112/crate_air/hot/kit_problem()
	if(bot_transcript_said("in the flames at"))
		return "got itself out of the hot air it was dressed for (try_escape_flames())"
	var/turf/open/here = get_turf(bot)
	if(!unloaded_at && istype(here) && here.air.temperature > BODYTEMP_HEAT_DAMAGE_LIMIT && (!bot.internal || bot.get_heat_protection(here.air.temperature) < 0.99)) //0.9999999 in full kit: 32-bit floats (kept_from_heat())
		return "in air at [round(here.air.temperature)] K at [bot_coord(here)] with its tank [bot.internal ? "open" : "shut"], wearing [bot.wear_suit || "no suit"] and [bot.head || "nothing on its head"]"
	return null

/datum/bot_scenario/fixes1112/crate_air/hot/still_kitted()
	return ..() || istype(bot.wear_suit, /obj/item/clothing/suit/fire) || istype(bot.head, /obj/item/clothing/head/hardhat/red)

/datum/bot_scenario/fixes1112/crate_air/hot/pass_check()
	if(!bot_transcript_said("fire suit, helmet and internals"))
		fail_reason = "kitted out for the hot air without a fire suit and helmet"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// The same, the room a vacuum, and EVA's suit storage unit beside the bot (the user's ruling: a vacuum wants a suit, if one's to be had)
/datum/bot_scenario/fixes1112/crate_air/vacuum
	name = "cargo: a crate in a vacuum, it takes a space suit from the EVA suit storage unit and goes in for it"
	desc = "The room past the airlock is a vacuum, and EVA's suit storage unit stands beside the cargo technician, its own doors no bar to it. It takes the space suit, helmet and mask out of the unit and puts them on, opens its tank, goes in for the crate, and shuts the valve once the crate's out. It's never in the vacuum without the suit. The user's ruling, 2026-11-12: for a vacuum, a space suit if one's to be had, and Engineering called if not (a cargo technician's access opens no EVA storage on the station)."
	time_limit = 90 SECONDS
	layout = list(
		"###############",
		"#Q.........####",
		"#..........enk#",
		"#UB........#nn#",
		"###############")
	room_air = "TEMP=2.7"

/datum/bot_scenario/fixes1112/crate_air/vacuum/setup()
	..()
	place("U", new /obj/machinery/suit_storage_unit/standard_unit(first_marker("U")))

/// The suit first, as the cargo round has it (goals/cargo.dm try_suit_up_for_crates(), which the code before this fix hadn't)
/datum/bot_scenario/fixes1112/crate_air/vacuum/before_unload()
	if(brain.is_eva_ready() || !hascall(brain, "try_suit_up_for_crates"))
		return FALSE
	if(call(brain, "try_suit_up_for_crates")(list(crate)))
		log_line("cargo: off to suit up for the crate")
		return TRUE
	return FALSE

/datum/bot_scenario/fixes1112/crate_air/vacuum/kit_problem()
	var/turf/open/here = get_turf(bot)
	if(!unloaded_at && istype(here) && here.air.return_pressure() < HAZARD_LOW_PRESSURE && !brain.in_plain_space_suit())
		return "at [round(here.air.return_pressure(), 0.1)] kPa at [bot_coord(here)] without a space suit"
	return null

/datum/bot_scenario/fixes1112/crate_air/vacuum/still_kitted()
	return bot.internal

/datum/bot_scenario/fixes1112/crate_air/vacuum/pass_check()
	if(!brain.in_plain_space_suit())
		fail_reason = "brought the crate out of the vacuum without a space suit on"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// cargo-air-on-internals on the station's own supply shuttle: the flight of the scenario above it (shuttle_air), with the cabin filled with
/// nitrogen at a normal pressure once it's docked. Station-wide like it, so it runs alone and only by name.
/datum/bot_scenario/fixes1112/shuttle_air/nitrogen
	name = "cargo shuttle: it docks full of nitrogen, and cargo goes aboard on its mask and tank for the crate"
	desc = "The supply shuttle flies in from CentCom with two crates aboard, and once it's docked its cabin is filled with nitrogen at a normal pressure. The cargo technician, a breath mask and an emergency oxygen tank in its bag, puts them on in the bay, goes aboard by the dock's airlocks, brings the crate it's free to unload into the bay and takes the mask off there. It doesn't open the loading doors or call Engineering, and it's never in the nitrogen with its tank shut. Batch bugs1112b run5 (Charlie Vasquez, Reese Tanaka, Emery Haldane): Science's silver aboard in air nobody could breathe from about ten minutes in to the end of the shift, the loading doors opened on it at 18:38:19 and 18:38:31, and five calls to Engineering."
	kit_backpack = list(/obj/item/clothing/mask/breath, /obj/item/tank/internals/emergency_oxygen) //as a crew member's survival box has
	/// The cabin's tiles given nitrogen, given air again before the shuttle goes back
	var/list/turf/open/filled
	/// When the crate came off
	var/unloaded_at

/// Nitrogen at about 101 kPa on every tile of the docked shuttle with air on it (not the airless plating by its engines)
/datum/bot_scenario/fixes1112/shuttle_air/nitrogen/proc/fill_cabin()
	filled = list()
	for(var/turf/open/T in aboard_turfs())
		if(!T.air || T.air.return_pressure() < 50)
			continue
		T.air.parse_gas_string("n2=104;TEMP=293.15")
		T.update_visuals()
		SSair.add_to_active(T)
		filled += T

/datum/bot_scenario/fixes1112/shuttle_air/nitrogen/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(setup_problem)
		fail_reason = setup_problem
		return BOT_GYM_FAIL
	if(!bot_supply_shuttle_docked())
		if(docked_at)
			fail_reason = "the supply shuttle left again before the crate was unloaded"
			return BOT_GYM_FAIL
		return BOT_GYM_PENDING
	if(!docked_at)
		docked_at = world.time
		fill_cabin()
		log_line("the supply shuttle has docked, and [length(filled)] tiles of its cabin are full of nitrogen")
		if(QDELETED(fetched) || brain.turf_air_is_breathable(get_turf(fetched)))
			fail_reason = "setup: the crate to fetch isn't in the nitrogen ([fetched ? bot_coord(get_turf(fetched)) : "no crate"])"
			return BOT_GYM_FAIL
		loading_doors = list()
		for(var/turf/T as anything in aboard_turfs())
			for(var/turf/near in range(1, T))
				for(var/obj/machinery/door/poddoor/P in near)
					if(P.density)
						loading_doors |= P
		return BOT_GYM_PENDING
	for(var/obj/machinery/door/poddoor/P as anything in loading_doors)
		if(QDELETED(P))
			fail_reason = "a loading door at the dock was destroyed"
			return BOT_GYM_FAIL
		if(!P.density)
			fail_reason = "[P] at [bot_coord(get_turf(P))] was opened on the supply shuttle"
			return BOT_GYM_FAIL
	if(bot_transcript_said("came in without air"))
		fail_reason = "went to open the loading doors for the shuttle's air"
		return BOT_GYM_FAIL
	if(bot_transcript_said("air I can't work in"))
		fail_reason = "called Engineering about the shuttle's air, a mask and tank in its bag"
		return BOT_GYM_FAIL
	var/turf/open/here = get_turf(bot)
	if(!unloaded_at && istype(here) && !brain.turf_air_is_breathable(here) && !bot.internal)
		fail_reason = "in air it can't breathe at [bot_coord(here)] with its tank shut"
		return BOT_GYM_FAIL
	if(!unloaded_at)
		if(brain.crates_unloaded < 1 || QDELETED(fetched) || bot_aboard_supply_shuttle(fetched))
			return BOT_GYM_PENDING
		unloaded_at = world.time
		log_line("the crate is off the shuttle, at [bot_coord(get_turf(fetched))]")
	if(!bot_transcript_said("kitted out for the air at"))
		fail_reason = "brought the crate off without kitting up for the nitrogen"
		return BOT_GYM_FAIL
	if(bot.internal || istype(bot.wear_mask, /obj/item/clothing/mask/breath))
		if(world.time > unloaded_at + 30 SECONDS)
			fail_reason = "still [bot.internal ? "on its tank" : "in its mask"] 30 s after the crate was off"
			return BOT_GYM_FAIL
		return BOT_GYM_PENDING
	log_line("mask off and tank shut again in the bay")
	return BOT_GYM_PASS

/datum/bot_scenario/fixes1112/shuttle_air/nitrogen/release_run()
	if(bot_supply_shuttle_docked()) //its air back before it goes, for whatever flies on it next
		for(var/turf/open/T as anything in filled)
			T.air.parse_gas_string(OPENTURF_DEFAULT_ATMOS)
			T.update_visuals()
			SSair.add_to_active(T)
	return ..()
