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
	name = "law: syndicate gear out in the open gets called in"
	desc = "Somebody stood in plain sight with an energy sword. A bot sees it and gets on the radio."
	layout = list(
		"#########",
		"#..B.C..#",
		"#########")
	time_limit = 20 SECONDS

/datum/bot_scenario/griefed/contraband/post_spawn()
	..()
	brain.gym_scripted = FALSE
	griefer_holds(/obj/item/melee/transforming/energy/sword/saber)

/datum/bot_scenario/griefed/contraband/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return bot_transcript_said("called in") ? BOT_GYM_PASS : BOT_GYM_PENDING

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
