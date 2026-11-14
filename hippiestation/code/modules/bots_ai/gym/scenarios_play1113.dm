// Bot Gym: the user's Captain round, 2026-11-13 evening (round-17.21.40). A traitor shut in EVA walked about with its emag in its hand
// and its energy sword on the floor; a body lay in Fore Maintenance with engineers walking past it; Security stood and took the user's
// shots, from somewhere they couldn't see; nobody used a slip.
//
// Layout letters used here: k an item the scenario puts down, R a ruin landmark, S the shooter / somebody else, M Medbay's lobby.

// ---------------------------------------------------------------------------------------------
// Traitor kit (goals/traitor.dm stash_stolen(), bot_items.dm make_room_for_item())
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/kit_kept
	name = "traitor kit: no bag, the emag and sword in its hands, it stocks up on a flashlight without putting the sword down"
	desc = "No bag on its back (a jetpack's there in EVA), a sheet of paper in each pocket, its emag in one hand and its energy sword in the other. Off for a flashlight on the floor, the card goes in a pocket and the sword stays with it. Kai Lindqvist, a traitor shut in EVA, set its energy sword down \"for a moment\" for a flashlight, never had a hand free to go back for it, and walked about with the emag out until the Captain picked the sword up and killed it with it (round-17.21.40)."
	job = "Assistant"
	kit_hands = list(/obj/item/card/emag, /obj/item/melee/transforming/energy/sword/saber)
	layout = list(
		"##########",
		"#B.....k.#",
		"##########")
	time_limit = 30 SECONDS
	max_goal_attempts = 1
	var/obj/item/flashlight/torch
	var/obj/item/melee/transforming/energy/sword/sword
	var/obj/item/card/emag/card

/datum/bot_scenario/kit_kept/post_spawn()
	qdel(bot.back)
	bot.equip_to_slot_or_del(new /obj/item/paper(bot), ITEM_SLOT_LPOCKET)
	bot.equip_to_slot_or_del(new /obj/item/paper(bot), ITEM_SLOT_RPOCKET)
	sword = locate() in bot.held_items
	card = locate() in bot.held_items
	torch = new(first_marker("k"))
	place("k", torch)

/datum/bot_scenario/kit_kept/make_goal()
	var/datum/bot_goal/acquire_item_type/G = new
	G.item_type = /obj/item/flashlight
	return G

/datum/bot_scenario/kit_kept/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(sword) || isturf(sword.loc))
		fail_reason = "put the sword on the floor"
		return BOT_GYM_FAIL
	if(QDELETED(card) || isturf(card.loc))
		fail_reason = "put the emag on the floor"
		return BOT_GYM_FAIL
	if(torch.loc != bot && torch.loc?.loc != bot)
		return BOT_GYM_PENDING
	if(card in bot.held_items)
		fail_reason = "has the flashlight, and the emag out in its hand"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/kit_kept/on_timeout()
	fail_reason = (card in bot.held_items) && (sword in bot.held_items) ? "never took the flashlight: both hands still full of kit" : "timed out"
	return BOT_GYM_FAIL

// ---------------------------------------------------------------------------------------------
// A space trip that never left the station (goals/space_ruins.dm fly_to_ruin)
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/ruin_never_left
	name = "exploring: shut in EVA, suited and with a jetpack, it doesn't count a ruin as been through or loot EVA for it"
	desc = "Suited, a jetpack on, set on a ruin, and shut in a room with no way out. It gives the trip up. Kai Lindqvist, shut in EVA by its firelocks, \"explored\" eight ruins in a row without leaving: each trip ended \"couldn't get to the ruin - heading back\", it looted the room it was in, said on the radio it was back from the ruins with EVA's own magboots, and logged the ruin as been through (round-17.21.40)."
	job = "Assistant"
	layout = list(
		"################",
		"#B.k#.........R#",
		"#...#..........#",
		"################")
	time_limit = 25 SECONDS
	max_goal_attempts = 1
	var/obj/effect/landmark/ruin/ruin
	var/obj/item/clothing/shoes/magboots/boots

/datum/bot_scenario/ruin_never_left/setup()
	ruin = new(first_marker("R"), null)
	place("R", ruin)
	boots = new(first_marker("k"))
	place("k", boots)

/datum/bot_scenario/ruin_never_left/post_spawn()
	qdel(bot.back)
	bot.equip_to_slot_or_del(new /obj/item/clothing/suit/space(bot), ITEM_SLOT_OCLOTHING)
	bot.equip_to_slot_or_del(new /obj/item/clothing/head/helmet/space(bot), ITEM_SLOT_HEAD)
	bot.equip_to_slot_or_del(new /obj/item/clothing/mask/breath(bot), ITEM_SLOT_MASK)
	bot.equip_to_slot_or_del(new /obj/item/tank/internals/oxygen(bot), ITEM_SLOT_SUITSTORE)
	var/obj/item/tank/jetpack/J = new /obj/item/tank/jetpack/carbondioxide(bot)
	bot.equip_to_slot_or_del(J, ITEM_SLOT_BACK)
	J.turn_on(bot)
	brain.set_pursuit(BOT_PURSUIT_EXPLORE, 10 MINUTES, "the gym")

/datum/bot_scenario/ruin_never_left/make_goal()
	return new /datum/bot_goal/explore_ruin/space(ruin)

/datum/bot_scenario/ruin_never_left/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("not fit to go out"))
		fail_reason = "the test isn't testing: it wasn't fit to go out at all"
		return BOT_GYM_FAIL
	if(bot_transcript_said("been through"))
		fail_reason = "counted the ruin as been through without leaving the room"
		return BOT_GYM_FAIL
	if(QDELETED(boots) || !isturf(boots.loc))
		fail_reason = "looted the room it was shut in for the ruin's spoils"
		return BOT_GYM_FAIL
	if(istype(brain.current_goal, /datum/bot_goal/explore_ruin))
		return BOT_GYM_PENDING
	return GLOB.bot_ruins_explored[ruin] ? BOT_GYM_FAIL : BOT_GYM_PASS

/datum/bot_scenario/ruin_never_left/release_run()
	GLOB.bot_ruins_explored -= ruin
	return ..()

// ---------------------------------------------------------------------------------------------
// Shot from out of sight, and the pace of a gunfight (foundation/gunfight.dm)
// ---------------------------------------------------------------------------------------------

/// The griefer here stands out of sight (invisible: the gym's lit all over, dynamic lighting off, so this stands in for the dark) and
/// fires a laser at the bot every second and a half.
/datum/bot_scenario/griefed/unseen
	time_limit = 20 SECONDS
	griefer_name = "Dee Dark"
	layout = list(
		"############",
		"#B.Y.....C.#",
		"############")
	var/obj/item/gun/energy/laser/laser
	var/shots = 0

/datum/bot_scenario/griefed/unseen/grief()
	laser = griefer_holds(/obj/item/gun/energy/laser)
	griefer.invisibility = INVISIBILITY_OBSERVER
	keep_at_it(PROC_REF(fire), 15)

/datum/bot_scenario/griefed/unseen/proc/fire()
	if(QDELETED(griefer) || QDELETED(bot) || bot.stat == DEAD)
		return FALSE
	if(griefer.stat != CONSCIOUS || griefer.IsParalyzed() || griefer.IsKnockdown() || !(griefer.mobility_flags & MOBILITY_STAND))
		return TRUE //down: it doesn't shoot, and may get up again
	laser.cell.charge = laser.cell.maxcharge
	shots++
	griefer.face_atom(bot)
	laser.afterattack(bot, griefer, FALSE)
	log_line("shot [shots] at the bot: bot health [bot.health], [get_dist(griefer, bot)] tiles")
	return TRUE

/datum/bot_scenario/griefed/unseen/proc/griefer_hit()
	return griefer.getStaminaLoss() + griefer.getFireLoss() + griefer.getBruteLoss() > 0

/datum/bot_scenario/griefed/unseen/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(griefer_hit())
		return BOT_GYM_PASS
	if(shots >= 5)
		fail_reason = "took [shots] shots from out of sight without hitting back"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/griefed/unseen/officer
	name = "security: an officer shot by its suspect from out of sight fires back where the shots come from"
	desc = "Arresting a killer it's lost sight of, at the spot it last saw them, it's shot with a laser from six tiles off by somebody it can't see. It turns and fires its taser back along the shot. Casey Nakamura, arresting the user, stood on the spot she'd last seen them and took seven laser shots in three seconds from five tiles off, her taser in her hand, and died (round-17.21.40)."
	job = "Security Officer"
	kit_hands = list(/obj/item/gun/energy/e_gun/advtaser)
	kit_backpack = list(/obj/item/restraints/handcuffs, /obj/item/melee/baton/loaded)

/datum/bot_scenario/griefed/unseen/officer/post_spawn()
	..()
	give_job_id(list(ACCESS_SECURITY, ACCESS_BRIG))
	brain.register_security()

/datum/bot_scenario/griefed/unseen/officer/grief()
	..()
	brain.file_crime(griefer, "Murder", "Gym.", BOT_CRIME_MURDER)
	brain.begin_arrest(griefer)
	brain.arrest_last_seen_turf = first_marker("Y") //lost them here a moment ago
	brain.arrest_last_seen = world.time

/datum/bot_scenario/griefed/unseen/officer/release_run()
	bot_clear_wanted(griefer)
	return ..()

/datum/bot_scenario/griefed/unseen/armed_crew
	name = "fights: shot from out of sight with a gun of its own, it fires back where the shots come from"
	desc = "An assistant with a laser gun is shot from six tiles off by somebody it can't see. It fires back along the shot rather than walking at the spot."
	job = "Assistant"
	kit_hands = list(/obj/item/gun/energy/laser)

/datum/bot_scenario/griefed/unseen/unarmed
	name = "fights: shot from out of sight with nothing to shoot back with, it gets out of the line"
	desc = "An assistant with nothing to shoot with is shot down a corridor by somebody it can't see, a side passage beside it. Into the passage, out of the line, not walking up the corridor at the spot the shots came from."
	job = "Assistant"
	time_limit = 10 SECONDS
	layout = list(
		"###########",
		"#....B...C#",
		"#####.#####",
		"#####.#####",
		"###########")

/datum/bot_scenario/griefed/unseen/unarmed/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(shots && !bot_clear_line(get_turf(griefer), bot))
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/griefed/unseen/unarmed/on_timeout()
	fail_reason = "still in the line of fire after [shots] shots, at [bot_coord(bot)]"
	return BOT_GYM_FAIL

/datum/bot_scenario/griefed/fire_rate
	name = "fights: in a gunfight it fires at a player's pace, not once a second"
	desc = "A steady (mid-skill) assistant with a laser gun fights somebody five tiles off who keeps shooting it. Two shots a second or so, as a player clicking does: it used to fire once a decision, one a second, while the user fired two and a half a second and won every exchange (round-17.21.40)."
	job = "Assistant"
	kit_hands = list(/obj/item/gun/energy/laser)
	time_limit = 15 SECONDS
	layout = list(
		"##########",
		"#B....C..#",
		"##########")
	var/first_shot = 0

/datum/bot_scenario/griefed/fire_rate/post_spawn()
	..()
	brain.skill = 0.7
	griefer.status_flags |= GODMODE //on its feet the whole time, to be shot at

/datum/bot_scenario/griefed/fire_rate/grief()
	keep_at_it(PROC_REF(hit), 15)

/// What on_attacked() hears from a shot at it, without the damage: the fight goes on
/datum/bot_scenario/griefed/fire_rate/proc/hit()
	if(QDELETED(bot) || bot.stat == DEAD)
		return FALSE
	brain.on_attacked(griefer, "shot", null)
	return TRUE

/datum/bot_scenario/griefed/fire_rate/proc/shots_fired()
	. = 0
	for(var/line in transcript)
		if(findtext(line, "firing the laser gun at"))
			.++

/datum/bot_scenario/griefed/fire_rate/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/fired = shots_fired()
	if(fired && !first_shot)
		first_shot = world.time
	if(!first_shot || world.time - first_shot < 5 SECONDS)
		return BOT_GYM_PENDING
	if(fired >= 8)
		return BOT_GYM_PASS
	fail_reason = "[fired] shots in the first five seconds"
	return BOT_GYM_FAIL

// ---------------------------------------------------------------------------------------------
// A body found (bot_playstyles.dm see_to_body())
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/body_found
	name = "bodies: crew who come across a body say so on the radio and bring it to Medbay"
	desc = "An atmospheric technician comes across a miner lying dead. It says where on the radio and drags the body to Medbay's door for the doctors. Lee Montague lay dead in Fore Maintenance for nine minutes, an atmospheric technician and an engineer walking past her, and nobody said a word or brought her out (round-17.21.40)."
	job = "Atmospheric Technician"
	layout = list(
		"############",
		"#B...K....M#",
		"############")
	time_limit = 40 SECONDS
	var/mob/living/carbon/human/body

/datum/bot_scenario/body_found/make_goal()
	return null

/datum/bot_scenario/body_found/post_spawn()
	body = stand_in(first_marker("K"), "Lee Gone")
	body.mind_initialize()
	body.mind.assigned_role = "Shaft Miner"
	body.death()
	brain.sociability = 1
	if("body_carry_bias" in brain.vars)
		brain.vars["body_carry_bias"] = 100
	brain.gym_medbay_spot = first_marker("M")

/datum/bot_scenario/body_found/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(brain.state == BOT_STATE_WANDER)
		brain.look_round_the_room() //what keep_an_eye_out() does every few seconds off the gym (bot_witness.dm)
	if(get_dist(body, first_marker("M")) > 1 || bot.pulling == body)
		return BOT_GYM_PENDING
	if(!bot_transcript_said("dead in"))
		fail_reason = "brought the body out without a word on the radio"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/datum/bot_scenario/body_found/on_timeout()
	fail_reason = "[bot_transcript_said("dead in") ? "said so, but " : ""]left the body where it lay, [get_dist(body, first_marker("M"))] tiles from Medbay's door"
	return BOT_GYM_FAIL

// ---------------------------------------------------------------------------------------------
// Slips (bot_hazards.dm mind_the_footing(), foundation/slips.dm)
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/griefed/wet_chase
	name = "footing: chasing somebody who hit it across a wet floor, it walks the wet and doesn't slip"
	desc = "Somebody hits it from across a floor that's wet from wall to wall, and it goes after them. It saw the wet floor (seen for certain here) and walks it. Bots in the user's round said \"wet floor ahead - walking\" and slipped on that very tile a moment later, fifteen times, most of them chasing the user (round-17.21.40)."
	job = "Assistant"
	time_limit = 15 SECONDS
	layout = list(
		"############",
		"#B..yyyy..C#",
		"############")

/datum/bot_scenario/griefed/wet_chase/setup()
	for(var/turf/open/T in markers["y"])
		T.MakeSlippery(TURF_WET_WATER, 2 MINUTES, 0, MAXIMUM_WET_TIME, TRUE) //for good: the arena's air dries a floor in a second or two

/datum/bot_scenario/griefed/wet_chase/check()
	var/turf/open/T = first_marker("y")
	var/datum/component/wet_floor/W = T.GetComponent(/datum/component/wet_floor)
	if(!W || W.highest_strength != TURF_WET_WATER)
		fail_reason = "the test isn't testing: the floor isn't wet water ([W?.highest_strength])"
		return BOT_GYM_FAIL
	return judge_chase()

/datum/bot_scenario/griefed/wet_chase/post_spawn()
	..()
	brain.footing_attention = 100
	griefer.status_flags |= GODMODE

/datum/bot_scenario/griefed/wet_chase/grief()
	brain.on_attacked(griefer, "punched", null)
	keep_at_it(PROC_REF(hit), 20)

/datum/bot_scenario/griefed/wet_chase/proc/hit()
	if(QDELETED(bot) || bot.stat == DEAD)
		return FALSE
	brain.on_attacked(griefer, "punched", null) //it stays a fight: they're still at it
	return TRUE

/datum/bot_scenario/griefed/wet_chase/proc/judge_chase()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!(bot.mobility_flags & MOBILITY_STAND))
		fail_reason = "slipped at [bot_coord(bot)] ([bot.m_intent])"
		return BOT_GYM_FAIL
	return get_dist(bot, griefer) <= 1 ? BOT_GYM_PASS : BOT_GYM_PENDING

/// Lube that's worn off a floor that's still wet with water: it reads as water, and walking it is safe.
/datum/bot_scenario/griefed/wet_chase/lube_worn_off
	name = "footing: a floor the lube has worn off, still wet with water, is walked over without a slip"
	desc = "Lube and water on the one floor, and the lube wears off first. The floor kept the lube's slip, walking or not (wet_floor.dm update_flags(): LoadComponent() keeps whatever slip the floor already has), while it looked and read as plain water: in the user's round bots said \"wet floor ahead - walking\" and went down on that very tile, fifteen times (round-17.21.40)."

/datum/bot_scenario/griefed/wet_chase/lube_worn_off/setup()
	for(var/turf/open/T in markers["y"])
		T.MakeSlippery(TURF_WET_LUBE, 2 MINUTES, 0, MAXIMUM_WET_TIME, TRUE)
		var/datum/component/wet_floor/W = T.GetComponent(/datum/component/wet_floor)
		W.add_wet(TURF_WET_WATER, 2 MINUTES)
		W.time_left_list["[TURF_WET_LUBE]"] = 0 //worn off, as dry() leaves it (wet_floor/process())
		W.check()

/// Somebody after it on foot (the griefer here walks at it a step every third of a second, and hits it when it's beside it): the slip goes
/// down in their way.
/datum/bot_scenario/griefed/slip_user
	job = "Assistant"
	time_limit = 20 SECONDS
	kit_hands = list(/obj/item/grown/bananapeel)
	layout = list(
		"##################",
		"#......B...C.....#",
		"##################")
	var/slipped = FALSE

/datum/bot_scenario/griefed/slip_user/post_spawn()
	..()
	brain.skill = 0.7 //a robust player's trick
	brain.nerve = 0.2

/datum/bot_scenario/griefed/slip_user/grief()
	keep_at_it(PROC_REF(come_on), 3)

/datum/bot_scenario/griefed/slip_user/proc/come_on()
	if(QDELETED(bot) || bot.stat == DEAD)
		return FALSE
	if(griefer.IsParalyzed() && (locate(/obj/item/grown/bananapeel) in get_turf(griefer)))
		slipped = TRUE //down on the peel, not on a punch
	if(griefer.incapacitated() || !(griefer.mobility_flags & MOBILITY_STAND))
		return TRUE
	if(griefer.Adjacent(bot))
		griefer_hand(INTENT_HARM)
		return TRUE
	step_towards(griefer, bot)
	return TRUE

/datum/bot_scenario/griefed/slip_user/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return slipped ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/slip_user/on_timeout()
	fail_reason = "they never went down: the peel's [carried_where()]"
	return BOT_GYM_FAIL

/datum/bot_scenario/griefed/slip_user/proc/carried_where()
	for(var/obj/item/grown/bananapeel/P in bot.GetAllContents())
		return "still on it"
	return "on the floor somewhere"

/datum/bot_scenario/griefed/slip_user/fleeing
	name = "slips: running from somebody on its heels, it drops its banana peel in their way"
	desc = "A robust (mid-skill) assistant runs from somebody coming after it, a banana peel in its hand. It drops it underfoot for them to run on to. The user went at the crew with slips in their round; no bot ever used one (round-17.21.40)."

/datum/bot_scenario/griefed/slip_user/fleeing/make_goal()
	return new /datum/bot_goal/run_from(griefer)

/datum/bot_scenario/griefed/slip_user/fleeing/issue_goal()
	addtimer(CALLBACK(src, TYPE_PROC_REF(/datum/bot_scenario, issue_goal_now)), 2 SECONDS) //once they're coming

/datum/bot_scenario/proc/issue_goal_now()
	goal_attempts++
	var/datum/bot_goal/G = make_goal()
	if(G && !brain.assign_goal(G))
		log_line("assign_goal refused")

/datum/bot_scenario/griefed/slip_user/fight
	name = "slips: somebody coming at it to hit it, it throws its banana peel down in front of them"
	desc = "A robust (mid-skill) assistant who's been hit is fighting somebody coming at it from four tiles off, a banana peel in its bag (in the hand, a punch knocks it to the floor where they tread on it anyway). It gets it out and throws it down in their way."
	kit_hands = null
	kit_backpack = list(/obj/item/grown/bananapeel)

/datum/bot_scenario/griefed/slip_user/fight/grief()
	brain.on_attacked(griefer, "punched", null)
	..()

/datum/bot_scenario/griefed/sword_kept
	name = "security: an officer holding a confiscated energy sword tasers a suspect without putting the sword on the floor"
	desc = "An officer has an energy sword it confiscated in one hand and nothing in the other, its taser on its suit. Going after somebody wanted for a major crime, the taser comes out into the free hand. Emptying both hands for the taser put confiscated swords on the floor 25 to 49 times a batch (shift batches door3 to play1113a), for anybody to pick up: the user did, in their Captain round."
	job = "Security Officer"
	time_limit = 15 SECONDS
	kit_hands = list(/obj/item/melee/transforming/energy/sword/saber)
	kit_backpack = list(/obj/item/restraints/handcuffs, /obj/item/gun/energy/e_gun/advtaser)
	layout = list(
		"###########",
		"#B.....C..#",
		"###########")
	var/obj/item/melee/transforming/energy/sword/sword

/datum/bot_scenario/griefed/sword_kept/post_spawn()
	..()
	give_job_id(list(ACCESS_SECURITY, ACCESS_BRIG))
	brain.register_security()
	sword = locate() in bot.held_items
	// A bag that's been round a shift and pockets with things in: nowhere to put the sword away
	var/obj/item/storage/bag = bot.get_item_by_slot(ITEM_SLOT_BACK)
	for(var/i in 1 to 7)
		SEND_SIGNAL(bag, COMSIG_TRY_STORAGE_INSERT, new /obj/item/storage/box(bot.loc), bot, TRUE, TRUE) //boxes: sheets of metal merge into one stack
	log_line("bag holds [length(bag.contents)] things")
	bot.equip_to_slot_or_del(new /obj/item/paper(bot), ITEM_SLOT_LPOCKET)
	bot.equip_to_slot_or_del(new /obj/item/paper(bot), ITEM_SLOT_RPOCKET)

/datum/bot_scenario/griefed/sword_kept/grief()
	brain.file_crime(griefer, "Murder", "Gym.", BOT_CRIME_MURDER)
	brain.begin_arrest(griefer)

/datum/bot_scenario/griefed/sword_kept/release_run()
	bot_clear_wanted(griefer)
	return ..()

/datum/bot_scenario/griefed/sword_kept/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(QDELETED(sword) || isturf(sword.loc))
		fail_reason = "put the sword on the floor"
		return BOT_GYM_FAIL
	return griefer.handcuffed ? BOT_GYM_PASS : BOT_GYM_PENDING
