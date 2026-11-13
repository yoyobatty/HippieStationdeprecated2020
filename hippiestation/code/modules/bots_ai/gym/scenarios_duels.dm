// Bot Gym: the duel ladder (the plan's M4 proof: "a duel ladder arena across apex, robust and normal"). Two real bots set on each other in a
// room, to the end; a run "passes" when the first one (the bot) comes out ahead: the other down, or the other worse off when the time's up.
// These are measures, not tests (ladder_only: never in the full suite). tools/bot_gym/apex_ladder.sh runs them many times and gives the
// win rate of each pairing; the pairings come in twos, one with the thing being measured and one without.

/datum/bot_scenario/duel
	ladder_only = TRUE
	job = "Assistant"
	time_limit = 40 SECONDS
	layout = list(
		"################",
		"#..............#",
		"#...B......C...#",
		"#..............#",
		"#..............#",
		"################")
	var/a_skill = 1
	var/b_skill = 0.4
	var/a_nerve = 0.5
	var/b_nerve = 0.5
	var/list/b_kit
	var/mob/living/carbon/human/other

/datum/bot_scenario/duel/post_spawn()
	brain.skill = a_skill
	brain.nerve = a_nerve
	other = second_bot(first_marker("C"), "Ollie Opponent")
	var/datum/bot_brain/them = other.bot_brain
	them.skill = b_skill
	them.nerve = b_nerve
	for(var/path in b_kit)
		other.put_in_hands(new path(other))
	brain.on_attacked(other, "attacked", null)
	them.on_attacked(bot, "attacked", null)

/datum/bot_scenario/duel/make_goal()
	return null

/// Down: out, in crit, cuffed, or on the floor. Put on the floor is the fight won for the crew: they stop there (handle_combat())
/proc/bot_duel_down(mob/living/L)
	return QDELETED(L) || L.stat != CONSCIOUS || L.health <= HEALTH_THRESHOLD_CRIT || (iscarbon(L) && L:handcuffed) || !(L.mobility_flags & MOBILITY_STAND)

/datum/bot_scenario/duel/check()
	var/they_down = bot_duel_down(other)
	var/me_down = bot_duel_down(bot)
	if(they_down && !me_down)
		return BOT_GYM_PASS
	if(me_down && !they_down)
		fail_reason = "went down first"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/duel/on_timeout()
	if(!bot_duel_down(bot) && bot.health > other.health)
		return BOT_GYM_PASS
	fail_reason = "time up, no better off ([bot.health] against [other.health])"
	return BOT_GYM_FAIL

// Kiting: a gun against a melee weapon, with and without it
/datum/bot_scenario/duel/kite
	name = "duel: a robust bot with a laser against a robust bot with a claymore"
	a_skill = 0.7
	b_skill = 0.7
	b_nerve = 1
	kit_hands = list(/obj/item/gun/energy/laser)
	b_kit = list(/obj/item/claymore)

/datum/bot_scenario/duel/kite_low
	name = "duel: an ordinary bot with a laser against a robust bot with a claymore"
	a_skill = 0.3
	b_skill = 0.7
	b_nerve = 1
	kit_hands = list(/obj/item/gun/energy/laser)
	b_kit = list(/obj/item/claymore)

// Skill alone, the same weapons
/datum/bot_scenario/duel/apex_toolbox
	name = "duel: an apex bot against an ordinary bot, a toolbox each"
	a_skill = 1
	b_skill = 0.3
	kit_hands = list(/obj/item/storage/toolbox/mechanical)
	b_kit = list(/obj/item/storage/toolbox/mechanical)

/datum/bot_scenario/duel/even_toolbox
	name = "duel: an ordinary bot against an ordinary bot, a toolbox each"
	a_skill = 0.3
	b_skill = 0.3
	kit_hands = list(/obj/item/storage/toolbox/mechanical)
	b_kit = list(/obj/item/storage/toolbox/mechanical)

// Choosing fights: bare hands against a claymore. The apex bot gets out; the ordinary one stays, being brave
/datum/bot_scenario/duel/outmatched_apex
	name = "duel: an apex bot with bare hands against a robust bot with a claymore"
	a_skill = 1
	a_nerve = 1
	b_skill = 0.7
	b_nerve = 1
	b_kit = list(/obj/item/claymore)

/datum/bot_scenario/duel/outmatched_apex/on_timeout()
	if(!bot_duel_down(bot))
		return BOT_GYM_PASS //it got out alive: for bare hands against a claymore, that's the win
	return ..()

/datum/bot_scenario/duel/outmatched_low
	name = "duel: an ordinary bot with bare hands against a robust bot with a claymore"
	a_skill = 0.3
	a_nerve = 1
	b_skill = 0.7
	b_nerve = 1
	b_kit = list(/obj/item/claymore)

/datum/bot_scenario/duel/outmatched_low/on_timeout()
	if(!bot_duel_down(bot))
		return BOT_GYM_PASS
	return ..()
