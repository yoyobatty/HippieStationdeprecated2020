// Bot Gym: combat smarts (apex/combat.dm, foundation/meta_book.dm).
//
// Layout letters used here: k the one it's fighting (a stand-in).

/datum/bot_scenario/combat_smarts
	job = "Assistant"
	time_limit = 10 SECONDS
	var/bot_skill = 1
	var/mob/living/carbon/human/foe
	/// What the foe holds
	var/foe_weapon

/datum/bot_scenario/combat_smarts/post_spawn()
	brain.skill = bot_skill
	foe = stand_in(first_marker("k"), "Kit Killer")
	var/obj/item/W
	if(foe_weapon)
		W = new foe_weapon(foe)
		foe.put_in_hands(W)
	brain.on_attacked(foe, "attacked", W)

/datum/bot_scenario/combat_smarts/make_goal()
	return null //the fight is the job

/datum/bot_scenario/combat_smarts/proc/ran()
	return istype(brain.current_goal, /datum/bot_goal/run_from) || bot_transcript_said("running for it")

// ---------------------------------------------------------------------------------------------
// Kiting
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/combat_smarts/kite
	name = "combat: a robust bot with a laser keeps a swordsman coming at it at arm's length"
	desc = "Mid skill, brave, a laser in hand, in a fight with somebody with a claymore walking straight at it a tile a second down a long room. It steps back out of reach and shoots, rather than letting him close and trading blows."
	bot_skill = 0.7
	time_limit = 7 SECONDS //self-defence ends eight seconds after the last blow (BOT_COMBAT_CALM_DOWN), and a stand-in never lands one
	foe_weapon = /obj/item/claymore
	kit_hands = list(/obj/item/gun/energy/laser)
	layout = list(
		"######################",
		"#k..B................#",
		"######################")
	var/closed_in = FALSE

/datum/bot_scenario/combat_smarts/kite/post_spawn()
	..()
	brain.nerve = 1 //it stands and fights rather than running from a claymore

/datum/bot_scenario/combat_smarts/kite/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!QDELETED(foe) && foe.stat == CONSCIOUS)
		var/turf/T = get_step_towards(foe, bot)
		if(T && !T.density && !(locate(/mob/living) in T))
			foe.forceMove(T)
	if(get_dist(bot, foe) <= 1)
		closed_in = TRUE
	if(closed_in)
		fail_reason = "let him close in to arm's reach"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/combat_smarts/kite/on_timeout()
	if(!bot_transcript_said("firing"))
		fail_reason = "kept away but never shot"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

// ---------------------------------------------------------------------------------------------
// Choosing its fights
// ---------------------------------------------------------------------------------------------

/datum/bot_scenario/combat_smarts/withdraw
	name = "combat: an apex bot with bare hands gets out of a fight with a claymore, brave as it is"
	desc = "Apex and brave, unarmed, in a fight with somebody swinging a claymore: they'd put it down in a few seconds and it'd take it a quarter of a minute to put them down. It gets out rather than standing there, which its nerve alone would have it do."
	foe_weapon = /obj/item/claymore
	layout = list(
		"################",
		"#B.k...........#",
		"################")

/datum/bot_scenario/combat_smarts/withdraw/post_spawn()
	..()
	brain.nerve = 1

/datum/bot_scenario/combat_smarts/withdraw/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return ran() ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/combat_smarts/press
	name = "combat: a hurt apex bot with a claymore stays in a fight with somebody unarmed"
	desc = "Apex, hurt past where it would run, a claymore in hand, in a fight with somebody with bare hands: it'd put them down well before they could it. It stays in, where its nerve alone would have it run."
	time_limit = 6 SECONDS
	kit_hands = list(/obj/item/claymore)
	layout = list(
		"################",
		"#B.k...........#",
		"################")

/datum/bot_scenario/combat_smarts/press/post_spawn()
	..()
	brain.nerve = 0.2
	bot.adjustBruteLoss(65)

/datum/bot_scenario/combat_smarts/press/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(ran())
		fail_reason = "ran from a fight it was winning"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/combat_smarts/press/on_timeout()
	return BOT_GYM_PASS

/datum/bot_scenario/combat_smarts/press_low
	name = "combat: a hurt low-skill bot with a claymore runs as it always did"
	desc = "The same for an ordinary player: hurt past its nerve, it runs."
	bot_skill = 0.3
	time_limit = 6 SECONDS
	kit_hands = list(/obj/item/claymore)
	layout = list(
		"################",
		"#B.k...........#",
		"################")

/datum/bot_scenario/combat_smarts/press_low/post_spawn()
	..()
	brain.nerve = 0.2
	bot.adjustBruteLoss(65)

/datum/bot_scenario/combat_smarts/press_low/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return ran() ? BOT_GYM_PASS : BOT_GYM_PENDING
