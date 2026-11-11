// Bot Gym scenarios for playstyles and Space Law: bot_personality.dm, bot_playstyles.dm, bot_law.dm. What a capital case comes to takes a
// whole brig, so that's a Bot Shift drill (LAW_DRILL=permabrig or injection, tools/bot_gym/run_bot_shift.sh).

/datum/bot_scenario/griefed/proc/make_griefer_wanted(crime = "Assault with a Deadly Weapon", severity = BOT_CRIME_MAJOR)
	var/datum/bot_wanted/W = new
	W.severity = severity
	W.crime = crime
	W.last_seen = get_turf(griefer)
	W.last_seen_at = world.time
	GLOB.bot_security_wanted[WEAKREF(griefer)] = W

/datum/bot_scenario/griefed/release_run()
	GLOB.bot_security_wanted -= WEAKREF(griefer)
	return ..()

/datum/bot_scenario/griefed/holds_down
	name = "law: somebody Security wants is kept on the floor for it"
	desc = "A wanted man on the floor after a fight. The bot doesn't walk off: it calls Security, stays with them, and puts them back down when they get up."
	layout = list(
		"#########",
		"#..BC...#",
		"#########")
	time_limit = 40 SECONDS

/datum/bot_scenario/griefed/holds_down/post_spawn()
	..()
	make_griefer_wanted()
	griefer.Paralyze(4 SECONDS)

/datum/bot_scenario/griefed/holds_down/grief()
	brain.after_the_fight(griefer)

/datum/bot_scenario/griefed/holds_down/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return bot_transcript_said("called Security") && bot_transcript_said("shoving") ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/cuffs_them
	name = "law: with cuffs on it, it cuffs them itself"
	desc = "Same as being held down, but this one's got a pair of handcuffs in its bag."
	layout = list(
		"#########",
		"#..BC...#",
		"#########")
	kit_backpack = list(/obj/item/restraints/handcuffs)

/datum/bot_scenario/griefed/cuffs_them/post_spawn()
	..()
	make_griefer_wanted()
	griefer.Paralyze(20 SECONDS)

/datum/bot_scenario/griefed/cuffs_them/grief()
	brain.after_the_fight(griefer)

/datum/bot_scenario/griefed/cuffs_them/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return griefer.handcuffed ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/contraband
	name = "law: syndicate gear out in the open isn't called in, but the word goes round"
	desc = "Somebody stood in plain sight with an energy sword, not lit. An ordinary crewmember doesn't run to Security over it (the user, after a Science bot did that the moment they picked one up): it notices, and it's news for whoever it talks to next."
	layout = list(
		"#########",
		"#.B...C.#",
		"#########")
	time_limit = 20 SECONDS

/datum/bot_scenario/griefed/contraband/post_spawn()
	..()
	brain.gym_scripted = FALSE
	brain.set_playstyle(BOT_STYLE_NORMAL)
	brain.next_sighting_call = 0
	griefer_holds(/obj/item/melee/transforming/energy/sword/saber)

/datum/bot_scenario/griefed/contraband/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("called in"))
		fail_reason = "called Security on them for having it"
		return BOT_GYM_FAIL
	if(world.time - start_time < 12 SECONDS)
		return BOT_GYM_PENDING
	for(var/list/item as anything in GLOB.bot_news)
		if(findtext(item[1], griefer_name) && findtext(item[1], "was seen with"))
			return BOT_GYM_PASS
	fail_reason = "never noticed it"
	return BOT_GYM_FAIL

/datum/bot_scenario/griefed/contraband_charge
	name = "law: somebody coming at it with an energy sword lit is called in, and it gets away"
	desc = "Somebody with a lit energy sword walks up to an ordinary crewmember. That is reason enough: it calls Security and gets away from them."
	layout = list(
		"###############",
		"#.......B....C#",
		"###############")
	time_limit = 30 SECONDS
	var/obj/item/melee/transforming/energy/sword/saber/sword

/datum/bot_scenario/griefed/contraband_charge/post_spawn()
	..()
	brain.gym_scripted = FALSE
	brain.set_playstyle(BOT_STYLE_NORMAL)
	brain.nerve = 0.3
	sword = griefer_holds(/obj/item/melee/transforming/energy/sword/saber)
	sword.transform_weapon(griefer, TRUE)

/datum/bot_scenario/griefed/contraband_charge/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!QDELETED(griefer) && get_dist(griefer, bot) > 1)
		step_towards(griefer, bot) //a step a second, at it
	if(bot_transcript_said("called in") && bot_transcript_said("getting away from"))
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/contraband_kept
	name = "law: an officer keeps an energy sword left lying on the floor"
	desc = "An energy sword on the floor of the room, nobody's. Security picks a traitor's kit like that up and keeps it (the user, 2026-11-10), as do the kinds that would want one."
	job = "Security Officer"
	layout = list(
		"#########",
		"#B.....s#",
		"#########")
	time_limit = 20 SECONDS
	var/obj/item/melee/transforming/energy/sword/saber/sword

/datum/bot_scenario/contraband_kept/setup()
	sword = new(first_marker("s"))
	place("s", sword)

/datum/bot_scenario/contraband_kept/make_goal()
	var/path = text2path("/datum/bot_goal/pocket_contraband") //named, so the build before it compiles
	return path ? new path() : null

/datum/bot_scenario/contraband_kept/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return (!QDELETED(sword) && (sword in bot.GetAllContents())) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/captains_id
	name = "law: somebody with the Captain's ID gets called in"
	desc = "The spare ID on somebody who isn't in charge of anything: Grand Larceny, a capital charge."
	layout = list(
		"#########",
		"#..BC...#",
		"#########")
	time_limit = 20 SECONDS

/datum/bot_scenario/griefed/captains_id/post_spawn()
	..()
	brain.gym_scripted = FALSE
	griefer.equip_to_slot_or_del(new /obj/item/card/id/captains_spare(griefer), ITEM_SLOT_ID)

/datum/bot_scenario/griefed/captains_id/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return bot_transcript_said("Grand Larceny") ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/hardens
	name = "law: attacked, a normal bot turns paranoid and stocks up"
	desc = "An ordinary crewmember hit in the face plays it paranoid for the rest of the round: it goes and gets the crowbar it never wanted before."
	layout = list(
		"#########",
		"#.CB...t#",
		"#########")
	time_limit = 30 SECONDS

/datum/bot_scenario/griefed/hardens/post_spawn()
	..()
	brain.set_playstyle(BOT_STYLE_NORMAL)

/datum/bot_scenario/griefed/hardens/build_tile(turf/T, char)
	if(char == "t")
		place(char, new /obj/item/crowbar(T))
		return
	..()

/datum/bot_scenario/griefed/hardens/grief()
	griefer_hand(INTENT_HARM)
	griefer.forceMove(first_marker("."))
	addtimer(CALLBACK(src, PROC_REF(after_hit)), 2 SECONDS)

/datum/bot_scenario/griefed/hardens/proc/after_hit()
	QDEL_NULL(griefer)
	brain.kit_rests = null
	bot_duty_of(/datum/bot_duty/stock_up).try_start(brain)

/datum/bot_scenario/griefed/hardens/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(result != BOT_GYM_PENDING || !brain.hardened)
		return BOT_GYM_PENDING
	return brain.find_carried_tool(/obj/item/crowbar) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/acting_captain
	name = "law: with no Captain aboard, the HoP takes command and says so"
	desc = "No Captain on the crew. The next head in line says on the radio that they're acting captain, once."
	duty_type = /datum/bot_duty/chain_of_command
	job = "Head of Personnel"
	time_limit = 10 SECONDS
	layout = list(
		"#####",
		"#.B.#",
		"#####")

/datum/bot_scenario/duty/acting_captain/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return bot_transcript_said("in command now") ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/hunter
	name = "law: an antag hunter goes to where the name on the radio was last seen"
	desc = "Somebody wanted, last seen at the far end of the room, and a hunter with a crowbar. It drops what it's doing and goes to look."
	layout = list(
		"###################",
		"#B...............C#",
		"###################")
	time_limit = 30 SECONDS
	kit_backpack = list(/obj/item/crowbar)

/datum/bot_scenario/griefed/hunter/post_spawn()
	..()
	brain.set_playstyle(BOT_STYLE_HUNTER)
	make_griefer_wanted()

/datum/bot_scenario/griefed/hunter/grief()
	bot_duty_of(/datum/bot_duty/hunt_valids).try_start(brain)

/datum/bot_scenario/griefed/hunter/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return get_dist(bot, griefer) <= 2 ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/vigilante
	name = "law: a hunter who hits somebody nobody wants goes on the record for it"
	desc = "Space Law 104. Security arrests a vigilante who goes too far: a blow on somebody with nothing against them is Vigilantism, not Assault."
	layout = list(
		"#######",
		"#.BC..#",
		"#######")
	time_limit = 10 SECONDS

/datum/bot_scenario/griefed/vigilante/post_spawn()
	..()
	brain.set_playstyle(BOT_STYLE_HUNTER)

/datum/bot_scenario/griefed/vigilante/check()
	var/list/verdict = bot_classify_crime(bot, griefer, "punched", null)
	if(verdict[1] != "Vigilantism")
		fail_reason = "charged with [verdict[1]]"
		return BOT_GYM_FAIL
	return bot_sentence_for("Vigilantism", BOT_CRIME_MINOR) == 5 MINUTES ? BOT_GYM_PASS : BOT_GYM_FAIL

/datum/bot_scenario/griefed/fair_game
	name = "law: hitting a wanted traitor isn't a crime, even reported by the traitor"
	desc = "A traitor in a nanosuit Security's already after (a bot) is punched by a crew member in front of an officer. The traitor doesn't get to report it, the officer doesn't charge it, and nobody goes after the crew member. A player was arrested for this while the traitor stood beside them."
	job = "Security Officer"
	layout = list(
		"###########",
		"#B...TC...#",
		"###########")
	time_limit = 15 SECONDS
	kit_backpack = list(/obj/item/restraints/handcuffs)
	var/mob/living/carbon/human/traitor

/datum/bot_scenario/griefed/fair_game/post_spawn()
	..()
	traitor = second_bot(first_marker("T"), "Max Traitor")
	traitor.bot_brain.bot_traitor = TRUE
	var/datum/bot_wanted/W = new
	W.severity = BOT_CRIME_MAJOR
	W.crime = "Possession of Dangerous Equipment"
	W.last_seen = get_turf(traitor)
	W.last_seen_at = world.time
	GLOB.bot_security_wanted[WEAKREF(traitor)] = W

/datum/bot_scenario/griefed/fair_game/grief()
	for(var/i in 1 to 3)
		if(QDELETED(griefer) || QDELETED(traitor))
			return
		griefer.a_intent = INTENT_HARM
		griefer.UnarmedAttack(traitor, TRUE)
		sleep(8)

/datum/bot_scenario/griefed/fair_game/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/datum/bot_wanted/W = bot_get_wanted_entry(griefer)
	if(W)
		fail_reason = "the crew member is wanted for [W.crime]"
		return BOT_GYM_FAIL
	if(brain.arrest_suspect == griefer)
		fail_reason = "the officer went after the crew member"
		return BOT_GYM_FAIL
	return world.time >= start_time + 10 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/fair_game/release_run()
	GLOB.bot_security_wanted -= WEAKREF(traitor)
	return ..()

/datum/bot_scenario/two_officers_lose_him
	name = "law: two officers lose the same man, and stand where he was seen rather than swapping places on it"
	desc = "Two officers after one wanted man, who gets away out of sight. Both make for where he was last seen. The first stands on the spot and the second stops beside it: two officers took turns walking on to the spot and swapping the other off it for half a minute."
	job = "Security Officer"
	layout = list(
		"###############",
		"#B.O.......K..#",
		"###############",
		"#P#############",
		"###############")
	time_limit = 30 SECONDS
	kit_backpack = list(/obj/item/restraints/handcuffs)
	var/mob/living/carbon/human/officer
	var/mob/living/carbon/human/suspect
	var/turf/spot
	var/arrived_at = 0
	var/moves = 0

/datum/bot_scenario/two_officers_lose_him/post_spawn()
	officer = second_bot(first_marker("O"), "Sam Second")
	officer.mind.assigned_role = "Security Officer"
	officer.put_in_hands(new /obj/item/restraints/handcuffs(officer))
	suspect = stand_in(first_marker("K"), "Wes Wanted")
	var/datum/bot_wanted/W = new
	W.severity = BOT_CRIME_MAJOR
	W.crime = "Assault with a Deadly Weapon"
	W.last_seen = get_turf(suspect)
	W.last_seen_at = world.time
	GLOB.bot_security_wanted[WEAKREF(suspect)] = W
	brain.begin_arrest(suspect)
	officer.bot_brain.begin_arrest(suspect)
	RegisterSignal(bot, COMSIG_MOVABLE_MOVED, PROC_REF(stepped))
	RegisterSignal(officer, COMSIG_MOVABLE_MOVED, PROC_REF(stepped))
	addtimer(CALLBACK(src, PROC_REF(gets_away)), 5)

/datum/bot_scenario/two_officers_lose_him/make_goal()
	return null //the arrest is the job

/datum/bot_scenario/two_officers_lose_him/proc/gets_away()
	if(QDELETED(suspect))
		return
	spot = get_turf(suspect)
	suspect.forceMove(first_marker("P"))

/datum/bot_scenario/two_officers_lose_him/check()
	if(bot_lost() || QDELETED(officer))
		return BOT_GYM_FAIL
	if(!spot)
		return BOT_GYM_PENDING
	if(!arrived_at)
		return BOT_GYM_PENDING
	if(moves > 6)
		fail_reason = "the two of them shuffled on and off the spot: [moves] steps"
		return BOT_GYM_FAIL
	return world.time > arrived_at + 12 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/// Every step either of them takes once one has got to the spot.
/datum/bot_scenario/two_officers_lose_him/proc/stepped(atom/movable/mover)
	SIGNAL_HANDLER
	if(!spot)
		return
	if(!arrived_at)
		if(get_turf(mover) == spot)
			arrived_at = world.time
		return
	moves++

/datum/bot_scenario/two_officers_lose_him/release_run()
	GLOB.bot_security_wanted -= WEAKREF(suspect)
	if(bot)
		UnregisterSignal(bot, COMSIG_MOVABLE_MOVED)
	if(officer)
		UnregisterSignal(officer, COMSIG_MOVABLE_MOVED)
	return ..()

/datum/bot_scenario/colleague_cuffs_him
	name = "law: with a colleague already cuffing the man, the second officer stands by rather than walking into them"
	desc = "Two officers after one man who stands still for it, at the end of a corridor with room beside him for one. The officer there cuffs him and the other waits. Two officers took turns swapping each other off the tile beside a man, every pair of cuffs cut short and counted as him resisting."
	job = "Security Officer"
	layout = list(
		"#######",
		"#KOB..#",
		"#######")
	time_limit = 20 SECONDS
	kit_backpack = list(/obj/item/restraints/handcuffs)
	var/mob/living/carbon/human/officer
	var/mob/living/carbon/human/suspect
	var/moves = 0

/datum/bot_scenario/colleague_cuffs_him/post_spawn()
	officer = second_bot(first_marker("O"), "Sam Second")
	officer.mind.assigned_role = "Security Officer"
	officer.put_in_hands(new /obj/item/restraints/handcuffs(officer))
	suspect = stand_in(first_marker("K"), "Wes Wanted")
	var/datum/bot_wanted/W = new
	W.severity = BOT_CRIME_MINOR
	W.crime = "Assault"
	W.last_seen = get_turf(suspect)
	W.last_seen_at = world.time
	GLOB.bot_security_wanted[WEAKREF(suspect)] = W
	officer.bot_brain.begin_arrest(suspect)
	brain.begin_arrest(suspect)
	RegisterSignal(bot, COMSIG_MOVABLE_MOVED, PROC_REF(stepped))
	RegisterSignal(officer, COMSIG_MOVABLE_MOVED, PROC_REF(stepped))

/datum/bot_scenario/colleague_cuffs_him/make_goal()
	return null //the arrest is the job

/datum/bot_scenario/colleague_cuffs_him/proc/stepped()
	SIGNAL_HANDLER
	moves++

/datum/bot_scenario/colleague_cuffs_him/check()
	if(bot_lost() || QDELETED(officer) || QDELETED(suspect))
		return BOT_GYM_FAIL
	if(moves > 4)
		fail_reason = "the two of them shuffled round him: [moves] steps"
		return BOT_GYM_FAIL
	if(suspect.handcuffed)
		if(suspect.getStaminaLoss() > 0 || suspect.AmountParalyzed() > 0)
			fail_reason = "he stood still for it and was stunned all the same"
			return BOT_GYM_FAIL
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/colleague_cuffs_him/release_run()
	GLOB.bot_security_wanted -= WEAKREF(suspect)
	if(bot)
		UnregisterSignal(bot, COMSIG_MOVABLE_MOVED)
	if(officer)
		UnregisterSignal(officer, COMSIG_MOVABLE_MOVED)
	return ..()

/datum/bot_scenario/minor_behind_door
	name = "law: after somebody for something minor, behind a door its ID doesn't open, it asks for the door rather than hacking it"
	desc = "A man wanted for a scuffle stands behind the Kitchen's door. The officer has the tools to hack it, but a minor charge isn't worth breaking into a department for: it asks the AI over the radio and waits. An officer once hacked the Kitchen's door and bolted it open over a low-level Assault."
	job = "Security Officer"
	layout = list(
		"##########",
		"#B...DK..#",
		"##########")
	time_limit = 15 SECONDS
	kit_backpack = list(/obj/item/restraints/handcuffs, /obj/item/multitool, /obj/item/wirecutters, /obj/item/screwdriver)
	var/mob/living/carbon/human/suspect
	var/obj/machinery/door/airlock/glass/door

/datum/bot_scenario/minor_behind_door/setup()
	var/turf/T = first_marker("D")
	for(var/obj/machinery/door/airlock/A in T)
		qdel(A)
	door = new(T)
	door.req_access = list(ACCESS_KITCHEN)

/datum/bot_scenario/minor_behind_door/post_spawn()
	suspect = stand_in(first_marker("K"), "Wes Wanted")
	var/datum/bot_wanted/W = new
	W.severity = BOT_CRIME_MINOR
	W.crime = "Assault"
	W.last_seen = get_turf(suspect)
	W.last_seen_at = world.time
	GLOB.bot_security_wanted[WEAKREF(suspect)] = W
	brain.begin_arrest(suspect)

/datum/bot_scenario/minor_behind_door/make_goal()
	return null //the arrest is the job

/datum/bot_scenario/minor_behind_door/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(door) || !door.density || door.locked || door.wires.is_cut(WIRE_OPEN) || bot_transcript_said("hacking"))
		fail_reason = "it broke the door open over a minor charge"
		return BOT_GYM_FAIL
	return (world.time > start_time + 10 SECONDS && bot_transcript_said("asking the AI")) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/minor_behind_door/release_run()
	GLOB.bot_security_wanted -= WEAKREF(suspect)
	return ..()

/datum/bot_scenario/suspect_in_pool
	name = "law: somebody wanted stood in the pool is gone in after and cuffed, not left there"
	desc = "A man wanted for a scuffle stands in the middle of the pool. The officer goes in after him, taking the fall into the water, and cuffs him. Nobody would walk into a pool for a stroll, but anybody in one used to be out of Security's reach."
	job = "Security Officer"
	layout = list(
		"############",
		"#B...qqqqq.#",
		"#....qqqqq.#",
		"#....qqKqq.#",
		"#....qqqqq.#",
		"#....qqqqq.#",
		"############")
	time_limit = 40 SECONDS
	kit_backpack = list(/obj/item/restraints/handcuffs)
	var/mob/living/carbon/human/suspect

/datum/bot_scenario/suspect_in_pool/setup()
	for(var/char in list("q", "K"))
		for(var/turf/T in markers[char])
			T.ChangeTurf(/turf/open/pool)

/datum/bot_scenario/suspect_in_pool/post_spawn()
	suspect = stand_in(first_marker("K"), "Wes Wanted")
	suspect.swimming = TRUE
	var/datum/bot_wanted/W = new
	W.severity = BOT_CRIME_MINOR
	W.crime = "Assault"
	W.last_seen = get_turf(suspect)
	W.last_seen_at = world.time
	GLOB.bot_security_wanted[WEAKREF(suspect)] = W
	brain.begin_arrest(suspect)

/datum/bot_scenario/suspect_in_pool/make_goal()
	return null //the arrest is the job

/datum/bot_scenario/suspect_in_pool/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return suspect.handcuffed ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/suspect_in_pool/release_run()
	GLOB.bot_security_wanted -= WEAKREF(suspect)
	return ..()

/datum/bot_scenario/suit_loose_no_drink
	name = "security: an officer doesn't stop for a drink with a nanosuit loose"
	desc = "Somebody in a nanosuit is wanted, out of sight behind a wall, and there's a cola machine beside the officer. It doesn't stop for a drink: the Head of Security went for one between the first fight with a suit and the second."
	job = "Security Officer"
	layout = list(
		"#########",
		"#B.V#..N#",
		"#...#...#",
		"#########")
	time_limit = 12 SECONDS
	var/mob/living/carbon/human/suspect

/datum/bot_scenario/suit_loose_no_drink/post_spawn()
	give_job_id(list(ACCESS_SECURITY))
	suspect = stand_in(first_marker("N"), "Nano Suit")
	suspect.equip_to_slot_or_del(new /obj/item/clothing/suit/space/hardsuit/nano(suspect), ITEM_SLOT_OCLOTHING)
	brain.file_crime(suspect, "Murder", "Gym.", BOT_CRIME_MAJOR)

/datum/bot_scenario/suit_loose_no_drink/make_goal()
	return new /datum/bot_goal/have_drink()

/datum/bot_scenario/suit_loose_no_drink/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(istype(brain.current_goal, /datum/bot_goal/have_drink))
		fail_reason = "went for a drink"
		return BOT_GYM_FAIL
	return world.time > start_time + 10 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/// Fighting a nanosuit is no crime, whether or not it's on the wanted list. In the user's round (2026-11-10) the suit had just been let go,
/// and the officer who saw the cook and the atmos tech hitting it booked both for Assault with a Deadly Weapon.
/datum/bot_scenario/fighting_a_suit
	name = "security: an officer who sees somebody hit a nanosuit with a toolbox doesn't book them"
	desc = "Somebody in a nanosuit, not on the wanted list, is hit with a toolbox in front of an officer. Hitting a confirmed antagonist is no crime: the officer files nothing against whoever hit it."
	job = "Security Officer"
	layout = list(
		"#########",
		"#B..C.N.#",
		"#########")
	time_limit = 12 SECONDS
	var/mob/living/carbon/human/crew
	var/mob/living/carbon/human/suited
	var/hit_at

/datum/bot_scenario/fighting_a_suit/post_spawn()
	brain.register_security()
	crew = stand_in(first_marker("C"), "Devon Cook")
	suited = stand_in(first_marker("N"), "Nano Suit")
	suited.equip_to_slot_or_del(new /obj/item/clothing/suit/space/hardsuit/nano(suited), ITEM_SLOT_OCLOTHING)
	crew.put_in_hands(new /obj/item/storage/toolbox/mechanical(crew))
	addtimer(CALLBACK(src, PROC_REF(hit_it)), 2 SECONDS)

/datum/bot_scenario/fighting_a_suit/make_goal()
	return null

/datum/bot_scenario/fighting_a_suit/proc/hit_it()
	bot_clear_wanted(suited) //let go after a search, as in the round
	var/obj/item/storage/toolbox/T = locate() in crew.held_items
	log_combat(crew, suited, "attacked", T)
	hit_at = world.time

/datum/bot_scenario/fighting_a_suit/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/datum/bot_wanted/W = bot_get_wanted_entry(crew)
	if(W)
		fail_reason = "booked them for [W.crime]"
		return BOT_GYM_FAIL
	return (hit_at && world.time > hit_at + 3 SECONDS) ? BOT_GYM_PASS : BOT_GYM_PENDING

/// The Warden went for "something heavier" with three nanosuits loose and came back with a practice laser (2026-11-10)
/datum/bot_scenario/heavier_not_practice
	name = "security: sent for a laser, an officer takes the real one, not the practice laser beside it"
	desc = "A practice laser lies two tiles off and a real laser gun further on. Asked for a laser, the officer walks past the practice one and takes the real one."
	job = "Warden"
	layout = list(
		"##########",
		"#B.q....k#",
		"##########")
	time_limit = 20 SECONDS

/datum/bot_scenario/heavier_not_practice/setup()
	place("q", new /obj/item/gun/energy/laser/practice(first_marker("q")))
	place("k", new /obj/item/gun/energy/laser(first_marker("k")))

/datum/bot_scenario/heavier_not_practice/make_goal()
	var/datum/bot_goal/acquire_item_type/G = new()
	G.item_type = /obj/item/gun/energy/laser
	return G

/datum/bot_scenario/heavier_not_practice/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(brain.find_carried_tool(/obj/item/gun/energy/laser/practice))
		fail_reason = "took the practice laser"
		return BOT_GYM_FAIL
	var/obj/item/real = first_placed("k")
	return (real && real.loc && get(real.loc, /mob) == bot) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/fighting_a_suit/release_run()
	GLOB.bot_security_wanted -= WEAKREF(crew)
	GLOB.bot_security_wanted -= WEAKREF(suited)
	return ..()

/datum/bot_scenario/knocked_gun_back
	name = "security: knocked flat and the gun dropped, it goes back a few steps for it"
	desc = "An officer with an energy gun out is knocked down, the gun falls, and it's three tiles on by the time it's up. It walks back and picks the gun up. An officer knocked down by a nanosuit went on with the arrest and left his gun on the floor where he fell."
	job = "Security Officer"
	kit_hands = list(/obj/item/gun/energy/e_gun)
	layout = list(
		"#########",
		"#B......#",
		"#########")
	time_limit = 20 SECONDS
	var/obj/item/gun/energy/e_gun/gun

/datum/bot_scenario/knocked_gun_back/post_spawn()
	gun = locate() in bot.held_items
	addtimer(CALLBACK(src, PROC_REF(knock_down)), 2 SECONDS)

/datum/bot_scenario/knocked_gun_back/make_goal()
	return null //the reflex is what's tested

/datum/bot_scenario/knocked_gun_back/proc/knock_down()
	bot.Paralyze(30)
	addtimer(CALLBACK(src, PROC_REF(drag_on)), 1 SECONDS)

/datum/bot_scenario/knocked_gun_back/proc/drag_on()
	bot.forceMove(locate(bot.x + 3, bot.y, bot.z))
	log_line("gun at [bot_coord(gun)], bot dragged on to [bot_coord(bot)]")

/datum/bot_scenario/knocked_gun_back/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return brain.is_carried(gun) && world.time > start_time + 5 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

// The Captain, the highest authority (bot_is_the_captain(), bot_law.dm). The user, as Captain, punched somebody in the Bar: Security
// came for them for assault, ignored "im cap", and it ended with the Captain killing the HoS and an officer (round-08.58.42, 2026-11-10).
/datum/bot_scenario/griefed/captain
	job = "Security Officer"
	griefer_name = "Cora Captain"
	griefer_job = "Captain"
	kit_backpack = list(/obj/item/restraints/handcuffs)
	layout = list(
		"##########",
		"#B...C.V.#",
		"##########")
	var/mob/living/carbon/human/victim
	var/hits = 0

/datum/bot_scenario/griefed/captain/post_spawn()
	..()
	brain.gym_scripted = FALSE
	victim = stand_in(first_marker("V"), "Vic Victim")

/datum/bot_scenario/griefed/captain/release_run()
	GLOB.bot_security_wanted -= WEAKREF(victim)
	return ..()

/datum/bot_scenario/griefed/captain/proc/arrested()
	return (brain.state == BOT_STATE_ARREST && brain.arrest_suspect == griefer) || bot_get_wanted_entry(griefer)

/datum/bot_scenario/griefed/captain/punch
	name = "law: the Captain throwing a punch isn't Security's to arrest"
	desc = "The Captain punches a crewman three times in front of an officer. Assault is a minor charge, and Security leaves the station's highest authority be over one: no record, no arrest. The officer used to cuff them for it."
	time_limit = 15 SECONDS

/datum/bot_scenario/griefed/captain/punch/grief()
	keep_at_it("punch", 1 SECONDS)

/datum/bot_scenario/griefed/captain/punch/proc/punch()
	if(++hits > 3)
		return FALSE
	griefer.forceMove(get_step(victim, WEST))
	griefer_hand(INTENT_HARM, victim)
	return TRUE

/datum/bot_scenario/griefed/captain/punch/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(arrested())
		fail_reason = "went to arrest the Captain for a punch"
		return BOT_GYM_FAIL
	return world.time > start_time + 12 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/captain/toolbox
	name = "law: the Captain beating somebody with a toolbox is arrested like anybody"
	desc = "The Captain beats a crewman with a toolbox in front of an officer: Assault with a Deadly Weapon, a major charge. That's dealt with as it would be for anybody: the officer goes to arrest them."
	time_limit = 20 SECONDS

/datum/bot_scenario/griefed/captain/toolbox/grief()
	griefer_holds(/obj/item/storage/toolbox/mechanical)
	keep_at_it("hit", 1 SECONDS)

/datum/bot_scenario/griefed/captain/toolbox/proc/hit()
	if(++hits > 3 || arrested())
		return FALSE
	griefer.forceMove(get_step(victim, WEST))
	griefer_swing(griefer.get_active_held_item(), victim)
	return TRUE

/datum/bot_scenario/griefed/captain/toolbox/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return arrested() ? BOT_GYM_PASS : BOT_GYM_PENDING

// A player griefing, not a bot (bot_witness.dm bot_saw_player_sabotage()): the user's ruling, 2026-11-10, bots subdue anybody blatantly
// at it. Only bot saboteurs were ever seen at it before: a player could open plasma in a hallway in front of an officer.
/datum/tgui/bot_gym_stub/New()
	status = UI_INTERACTIVE

/datum/bot_scenario/griefed/player_plasma
	name = "law: a player letting plasma out of a canister in front of an officer is arrested for sabotage"
	desc = "Somebody who isn't a bot opens a full plasma canister in a hallway, an officer watching. The officer calls it in as Sabotage and goes to arrest them."
	job = "Security Officer"
	griefer_name = "Greg Griefer"
	time_limit = 20 SECONDS
	kit_backpack = list(/obj/item/restraints/handcuffs)
	layout = list(
		"###########",
		"#B....Ck..#",
		"#.........#",
		"###########")
	var/obj/machinery/portable_atmospherics/canister/toxins/canister

/datum/bot_scenario/griefed/player_plasma/setup()
	canister = new(first_marker("k"))
	place("k", canister)

/datum/bot_scenario/griefed/player_plasma/post_spawn()
	..()
	brain.gym_scripted = FALSE

/datum/bot_scenario/griefed/player_plasma/grief()
	usr = griefer
	canister.ui_act("valve", list(), new /datum/tgui/bot_gym_stub)
	log_line("valve [canister.valve_open ? "open" : "shut"]")

/datum/bot_scenario/griefed/player_plasma/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/datum/bot_wanted/W = bot_get_wanted_entry(griefer)
	return (W?.crime == "Sabotage" || (brain.state == BOT_STATE_ARREST && brain.arrest_suspect == griefer)) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/player_plasma/release_run()
	if(!QDELETED(canister))
		canister.valve_open = FALSE
		qdel(canister)
	return ..()

/// The same, done other ways: what's let out that isn't air is a flood, however it's let out (the user, 2026-11-10)
/datum/bot_scenario/griefed/player_plasma/smashed
	name = "law: a player smashing a plasma canister open in front of an officer is arrested for sabotage"
	desc = "Somebody who isn't a bot beats a plasma canister with a toolbox till it bursts. The officer calls it in as Sabotage and goes to arrest them."

/datum/bot_scenario/griefed/player_plasma/smashed/grief()
	var/obj/item/T = griefer_holds(/obj/item/storage/toolbox/mechanical)
	griefer_swing(T, canister)
	canister.take_damage(canister.max_integrity) //the rest of the beating
	log_line("canister [(canister.stat & BROKEN) ? "broken" : "whole"]")

/datum/bot_scenario/griefed/player_plasma/pumped
	name = "law: a player pumping N2O out of a portable pump in front of an officer is arrested for sabotage"
	desc = "Somebody who isn't a bot switches on a portable pump full of sleeping gas, pumping out into the hallway. The officer calls it in as Sabotage."
	var/obj/machinery/portable_atmospherics/pump/pump

/datum/bot_scenario/griefed/player_plasma/pumped/setup()
	..()
	pump = new(get_step(first_marker("k"), SOUTH))
	place("p", pump)
	pump.air_contents.moles[/datum/gas/nitrous_oxide] = 600

/datum/bot_scenario/griefed/player_plasma/pumped/grief()
	usr = griefer
	pump.ui_act("power", list(), new /datum/tgui/bot_gym_stub)
	log_line("pump [pump.on ? "on" : "off"], [pump.direction]")

/datum/bot_scenario/griefed/player_plasma/pumped/release_run()
	if(!QDELETED(pump))
		pump.on = FALSE
		qdel(pump)
	return ..()

/datum/bot_scenario/griefed/player_plasma/oxygen
	name = "law: a player letting oxygen out of a canister isn't griefing"
	desc = "Somebody opens an oxygen canister in the hallway, an officer watching. Air and what it's made of is no flood: nobody's called in."
	time_limit = 12 SECONDS

/datum/bot_scenario/griefed/player_plasma/oxygen/setup()
	canister = new /obj/machinery/portable_atmospherics/canister/oxygen(first_marker("k"))
	place("k", canister)

/datum/bot_scenario/griefed/player_plasma/oxygen/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_get_wanted_entry(griefer) || (brain.state == BOT_STATE_ARREST && brain.arrest_suspect == griefer))
		fail_reason = "called oxygen a flood"
		return BOT_GYM_FAIL
	return world.time > start_time + 10 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/player_plasma/smashed/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/datum/bot_wanted/W = bot_get_wanted_entry(griefer)
	return W?.crime == "Sabotage" ? BOT_GYM_PASS : BOT_GYM_PENDING

/// Plain air judged by what it does (the user, 2026-11-10): dumped, the lesser charge; into plasma or scalding, as bad as plasma
/datum/bot_scenario/griefed/player_plasma/judged
	name = "unnamed" //a parent type, for its children
	/// The charge it should come to
	var/expect_crime = "Vandalism"

/datum/bot_scenario/griefed/player_plasma/judged/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/datum/bot_wanted/W = bot_get_wanted_entry(griefer)
	if(W && W.crime != expect_crime)
		fail_reason = "charged with [W.crime]"
		return BOT_GYM_FAIL
	return W ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/player_plasma/judged/nitrogen
	name = "law: a player dumping a nitrogen canister at full pressure is arrested for vandalism"
	desc = "A nitrogen canister let out at its highest release pressure into a hallway with its air: no flood, but nothing left to breathe if it goes on. The lesser charge, Vandalism."

/datum/bot_scenario/griefed/player_plasma/judged/nitrogen/setup()
	canister = new /obj/machinery/portable_atmospherics/canister/nitrogen(first_marker("k"))
	place("k", canister)
	canister.release_pressure = canister.can_max_release_pressure

/datum/bot_scenario/griefed/player_plasma/judged/into_plasma
	name = "law: a player letting oxygen into a room with plasma in it is arrested for sabotage"
	desc = "Plasma hangs in the hallway already, which can't burn on its own. Opening an oxygen canister into it gives it what it needs: as bad as the plasma itself."
	expect_crime = "Sabotage"

/datum/bot_scenario/griefed/player_plasma/judged/into_plasma/setup()
	canister = new /obj/machinery/portable_atmospherics/canister/oxygen(first_marker("k"))
	place("k", canister)
	for(var/turf/open/T in arena_area)
		T.air.moles[/datum/gas/plasma] += 20
		T.air_update_turf()

/datum/bot_scenario/griefed/player_plasma/judged/scalding
	name = "law: a player letting scalding air out of a canister is arrested for sabotage"
	desc = "An air canister heated to 600 K, let out into the hallway: it burns whoever's in it. Sabotage."
	expect_crime = "Sabotage"

/datum/bot_scenario/griefed/player_plasma/judged/scalding/setup()
	canister = new /obj/machinery/portable_atmospherics/canister/air(first_marker("k"))
	place("k", canister)
	canister.air_contents.temperature = 600

// The user's rulings after their Captain round (2026-11-10): somebody who tries to kill is a confirmed antagonist, called kill on sight on
// the radio, unless somebody senior says otherwise; the Captain's "arrest X" and "release X" are followed, and "execute X" is checked.

/datum/bot_scenario/command_order
	job = "Security Officer"
	kit_backpack = list(/obj/item/restraints/handcuffs)
	layout = list(
		"##########",
		"#B..C..M.#",
		"##########")
	time_limit = 15 SECONDS
	var/mob/living/carbon/human/captain
	var/mob/living/carbon/human/max

/datum/bot_scenario/command_order/post_spawn()
	brain.register_security()
	captain = stand_in(first_marker("C"), "Cass Captain")
	captain.mind_initialize()
	captain.mind.assigned_role = "Captain"
	max = stand_in(first_marker("M"), "Max Adeyemi")

/datum/bot_scenario/command_order/make_goal()
	return null

/datum/bot_scenario/command_order/proc/captain_says(line)
	if(result == BOT_GYM_PENDING && !QDELETED(captain))
		log_line("captain: \"[line]\"")
		captain.say(line)

/datum/bot_scenario/command_order/release_run()
	GLOB.bot_security_wanted -= WEAKREF(max)
	return ..()

/datum/bot_scenario/command_order/beaten_to_crit
	name = "security: somebody who beats a crew member into crit in front of an officer is called kill on sight"
	desc = "Max beats the Captain into crit with a toolbox in front of the officer. That's attempted murder, a confirmed antagonist: the officer puts it on the radio that Max is to be killed on sight."

/datum/bot_scenario/command_order/beaten_to_crit/post_spawn()
	..()
	max.put_in_hands(new /obj/item/storage/toolbox/mechanical(max))
	addtimer(CALLBACK(src, PROC_REF(beat)), 2 SECONDS)

/datum/bot_scenario/command_order/beaten_to_crit/proc/beat()
	captain.apply_damage(130, BRUTE, BODY_ZONE_CHEST)
	var/obj/item/storage/toolbox/T = locate() in max.held_items
	log_combat(max, captain, "attacked", T)

/datum/bot_scenario/command_order/beaten_to_crit/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/datum/bot_wanted/W = bot_get_wanted_entry(max)
	if(W && ("kill_on_sight" in W.vars) && W.vars["kill_on_sight"] && bot_transcript_said("kill on sight"))
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/command_order/take_alive
	name = "security: the Captain says to take a kill-on-sight suspect alive, and that's that"
	desc = "Max is wanted for murder, which is kill on sight. The Captain says \"take Max alive\". The officer acknowledges it, and Max isn't kill on sight any more."

/datum/bot_scenario/command_order/take_alive/post_spawn()
	..()
	brain.file_crime(max, "Murder", "Gym.", BOT_CRIME_MURDER)
	addtimer(CALLBACK(src, PROC_REF(captain_says), "Take Max alive!"), 2 SECONDS)

/datum/bot_scenario/command_order/take_alive/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/datum/bot_wanted/W = bot_get_wanted_entry(max)
	if(!W || !("kill_on_sight" in W.vars))
		fail_reason = "no kill on sight to call off"
		return BOT_GYM_FAIL
	return (!W.vars["kill_on_sight"] && world.time > start_time + 4 SECONDS) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/command_order/execute_checked
	name = "security: the Captain orders somebody in for theft executed, and the officer won't"
	desc = "Max is wanted for theft. The Captain says \"execute Max\". The officer pushes back: theft isn't a killing matter. Max isn't made kill on sight."

/datum/bot_scenario/command_order/execute_checked/post_spawn()
	..()
	brain.file_crime(max, "Theft", "Gym.", BOT_CRIME_MINOR)
	addtimer(CALLBACK(src, PROC_REF(captain_says), "Execute Max."), 2 SECONDS)

/datum/bot_scenario/command_order/execute_checked/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/datum/bot_wanted/W = bot_get_wanted_entry(max)
	if(W && ("kill_on_sight" in W.vars) && W.vars["kill_on_sight"])
		fail_reason = "made them kill on sight for theft"
		return BOT_GYM_FAIL
	return bot_transcript_said("killing matter") || bot_transcript_said("do their time") ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/command_order/arrest
	name = "security: the Captain says \"arrest Max\", and the officer does"
	desc = "Max hasn't done anything Security knows of. The Captain tells the officer to arrest Max. It goes and cuffs Max."
	time_limit = 25 SECONDS

/datum/bot_scenario/command_order/arrest/post_spawn()
	..()
	addtimer(CALLBACK(src, PROC_REF(captain_says), "Arrest Max."), 2 SECONDS)

/datum/bot_scenario/command_order/arrest/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return max.handcuffed ? BOT_GYM_PASS : BOT_GYM_PENDING

// The user's second Captain round (round-20.37.50, 2026-11-10): the Captain's Attempted Murder was written over by Assaulting an Officer, a
// charge of the same weight, and the Warden he shot bled out two minutes later without it ever becoming murder.

/datum/bot_scenario/command_order/kos_keeps_charge
	name = "security: somebody kill on sight for attempted murder who then hits an officer is still wanted for attempted murder"
	desc = "Max is wanted for Attempted Murder, kill on sight. He punches the officer, which on its own is Assaulting an Officer, a charge of the same weight. The record still says Attempted Murder and Max is still fair game. In the user's Captain round the second charge wrote over the first."
	var/hit_at = 0

/datum/bot_scenario/command_order/kos_keeps_charge/post_spawn()
	..()
	brain.file_crime(max, "Attempted Murder", "Gym.", BOT_CRIME_MAJOR)
	addtimer(CALLBACK(src, PROC_REF(punch)), 2 SECONDS)

/datum/bot_scenario/command_order/kos_keeps_charge/proc/punch()
	if(result != BOT_GYM_PENDING || QDELETED(max))
		return
	max.forceMove(get_step(bot, EAST))
	log_combat(max, bot, "punched")
	hit_at = world.time
	log_line("Max punched the officer")

/datum/bot_scenario/command_order/kos_keeps_charge/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!hit_at || world.time < hit_at + 3 SECONDS)
		return BOT_GYM_PENDING
	var/datum/bot_wanted/W = bot_get_wanted_entry(max)
	if(W?.crime != "Attempted Murder" || !bot_is_fair_game(max))
		fail_reason = "the record says [W?.crime || "nothing"], fair game [bot_is_fair_game(max)]"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/command_order/died_of_it
	name = "security: somebody wanted for beating a man who dies of it later is wanted for murder"
	desc = "Max beats Vic with a toolbox in front of the officer: Assault with a Deadly Weapon. Vic dies of it a few seconds later. Max is wanted for Murder now, and the officer says so on the radio. In the user's Captain round the Warden bled out two minutes after being shot, and the Captain stayed wanted for Assaulting an Officer."
	var/mob/living/carbon/human/vic
	var/died_at = 0

/datum/bot_scenario/command_order/died_of_it/post_spawn()
	..()
	vic = stand_in(first_marker("."), "Vic Okafor")
	vic.mind_initialize()
	vic.mind.assigned_role = "Assistant"
	max.put_in_hands(new /obj/item/storage/toolbox/mechanical(max))
	addtimer(CALLBACK(src, PROC_REF(beat)), 2 SECONDS)
	addtimer(CALLBACK(src, PROC_REF(dies)), 5 SECONDS)

/datum/bot_scenario/command_order/died_of_it/proc/beat()
	if(result != BOT_GYM_PENDING || QDELETED(max) || QDELETED(vic))
		return
	max.forceMove(get_step(vic, EAST))
	vic.apply_damage(40, BRUTE, BODY_ZONE_CHEST)
	var/obj/item/storage/toolbox/T = locate() in max.held_items
	log_combat(max, vic, "attacked", T)
	var/datum/bot_wanted/W = bot_get_wanted_entry(max)
	log_line("Max beat Vic with the toolbox: [W?.crime]")

/datum/bot_scenario/command_order/died_of_it/proc/dies()
	if(result != BOT_GYM_PENDING || QDELETED(vic))
		return
	vic.death()
	died_at = world.time
	log_line("Vic died of it")

/datum/bot_scenario/command_order/died_of_it/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!died_at || world.time < died_at + 3 SECONDS)
		return BOT_GYM_PENDING
	var/datum/bot_wanted/W = bot_get_wanted_entry(max)
	if(W?.crime != "Murder")
		fail_reason = "the record says [W?.crime || "nothing"]"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS
