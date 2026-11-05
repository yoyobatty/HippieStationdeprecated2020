// Bot Gym scenarios for Security against somebody armed (goals/security_armed.dm), after the user's round: as Chief Engineer with an
// energy sword they killed the chemist and the Head of Security in the Kitchen while four officers stood off and never hit them, their
// hybrid tasers spent. The griefer (C) here holds a lit energy sword, is wanted for murder, and swings at whoever's beside them.
//
// Layout letters used here: O a second officer, V a crew member the griefer is cutting down, R a recharger.

/datum/bot_scenario/griefed/officer/armed
	time_limit = 40 SECONDS
	kit_backpack = list(/obj/item/restraints/handcuffs, /obj/item/melee/baton/loaded, /obj/item/gun/energy/e_gun/advtaser, /obj/item/assembly/flash/handheld)
	/// What's left in the bot's hybrid taser: 1000 is full, 200 a taser shot, 50 a disabler shot.
	var/gun_charge = 1000
	var/obj/item/melee/transforming/energy/sword/saber/sword
	var/list/mob/living/carbon/human/officers = list()

/datum/bot_scenario/griefed/officer/armed/grief()
	sword = griefer_holds(/obj/item/melee/transforming/energy/sword/saber)
	sword.attack_self(griefer) //lit
	brain.file_crime(griefer, "Murder", "Killed the chemist with an energy sword.", BOT_CRIME_MURDER)
	officers = list(bot)
	set_charge(bot, gun_charge)
	brain.begin_arrest(griefer)
	keep_at_it(PROC_REF(swing), 15)

/datum/bot_scenario/griefed/officer/armed/proc/set_charge(mob/living/carbon/human/H, charge)
	for(var/obj/item/gun/energy/G in H.GetAllContents())
		G.cell.charge = charge

/// The griefer cuts at whoever's beside them, officers first. TRUE while it can carry on.
/datum/bot_scenario/griefed/officer/armed/proc/swing()
	if(QDELETED(griefer) || griefer.stat != CONSCIOUS || griefer.handcuffed || griefer.IsParalyzed() || griefer.IsKnockdown())
		return !QDELETED(griefer) && !griefer.handcuffed
	if(griefer.get_active_held_item() != sword)
		return FALSE //disarmed
	for(var/mob/living/carbon/human/H in range(1, griefer))
		if(H != griefer && H.stat != DEAD)
			griefer_swing(sword, H)
			break
	return TRUE

/datum/bot_scenario/griefed/officer/armed/proc/officer_down()
	for(var/mob/living/carbon/human/H in officers)
		if(QDELETED(H) || H.stat == DEAD)
			return TRUE
	return FALSE

/datum/bot_scenario/griefed/officer/armed/release_run()
	bot_clear_wanted(griefer)
	if("bot_lethal_said" in GLOB.vars) // the fix's: a build without it has no such list
		var/list/said = GLOB.vars["bot_lethal_said"]
		said -= REF(griefer)
	return ..()

/datum/bot_scenario/griefed/officer/armed/disabler
	name = "security: with its taser setting spent, an officer shoots an armed killer with the disabler setting"
	desc = "The officer's hybrid taser has 150 charge left: not enough for a taser shot (200), enough for three disabler shots (50). It fires them, where it used to read the gun as empty and stand off."
	gun_charge = 150
	layout = list(
		"###########",
		"#B.......C#",
		"###########")

/datum/bot_scenario/griefed/officer/armed/disabler/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	return bot_transcript_said("firing") ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/officer/armed/flash_together
	name = "security: two officers with spent guns go in together, flash and cuff an armed killer"
	desc = "Neither officer's gun has a shot left. Together they walk up, the flash puts the griefer down (a sword can't block it), and the cuffs go on. They used to stand off and call for backup that was already there."
	gun_charge = 0
	time_limit = 60 SECONDS
	layout = list(
		"###########",
		"#B.......C#",
		"#O........#",
		"###########")

/datum/bot_scenario/griefed/officer/armed/flash_together/grief()
	..()
	var/mob/living/carbon/human/O = second_bot(first_marker("O"), "Officer Oduya")
	O.mind.assigned_role = "Security Officer"
	O.bot_brain.register_security()
	O.put_in_hands(new /obj/item/melee/baton/loaded(O))
	O.equip_to_slot_or_del(new /obj/item/assembly/flash/handheld(O), ITEM_SLOT_LPOCKET)
	O.equip_to_slot_or_del(new /obj/item/restraints/handcuffs(O), ITEM_SLOT_RPOCKET)
	O.bot_brain.begin_arrest(griefer)
	officers += O

/datum/bot_scenario/griefed/officer/armed/flash_together/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(officer_down())
		fail_reason = "an officer died"
		return BOT_GYM_FAIL
	return griefer.handcuffed ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/griefed/officer/armed/protect
	name = "security: alone with a spent gun, an officer goes in on somebody cutting down the crew in front of it"
	desc = "No shots left and no backup, but the griefer is cutting down a crew member beside them. The officer goes in with the flash and the baton instead of watching from a distance."
	gun_charge = 0
	time_limit = 40 SECONDS
	layout = list(
		"###########",
		"#B......VC#",
		"#.........#",
		"###########")
	var/mob/living/carbon/human/victim

/datum/bot_scenario/griefed/officer/armed/protect/grief()
	victim = stand_in(first_marker("V"), "Riley Chemist")
	..()
	griefer_swing(sword, victim)
	brain.nerve = 0.6

/datum/bot_scenario/griefed/officer/armed/protect/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("flashing") || griefer.handcuffed)
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/griefed/officer/armed/lethal
	name = "security: an officer going lethal on somebody who's killed says so on the radio"
	desc = "The user's ruling: lethal force after a witnessed kill. An officer with a laser fires it at the griefer, wanted for murder, and says on the security channel that it's going lethal."
	time_limit = 20 SECONDS
	kit_backpack = list(/obj/item/restraints/handcuffs, /obj/item/melee/baton/loaded, /obj/item/gun/energy/laser)
	layout = list(
		"###########",
		"#B.......C#",
		"###########")

/datum/bot_scenario/griefed/officer/armed/lethal/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot_transcript_said("firing") && !bot_transcript_said("Going lethal on"))
		if(world.time > start_time + 12 SECONDS)
			fail_reason = "fired a laser without saying it was going lethal"
			return BOT_GYM_FAIL
		return BOT_GYM_PENDING
	return bot_transcript_said("Going lethal on") && bot_transcript_said("firing") ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/duty/recharge_gun
	name = "security: an officer with a run-down gun charges it at a recharger and takes it back"
	desc = "Its hybrid taser is at 10%. Free, it walks to the recharger, puts the gun in, waits by it until it's full and takes it back out. Guns used to stay as empty as the last arrest left them."
	job = "Security Officer"
	time_limit = 60 SECONDS
	kit_backpack = list(/obj/item/gun/energy/e_gun/advtaser)
	layout = list(
		"##########",
		"#B......R#",
		"##########")
	var/obj/item/gun/energy/gun

/datum/bot_scenario/duty/recharge_gun/setup()
	duty_type = text2path("/datum/bot_duty/recharge_gun") // by name: a build without the fix has no such duty
	for(var/turf/T in markers["R"])
		place("R", new /obj/machinery/recharger(T))

/datum/bot_scenario/duty/recharge_gun/post_spawn()
	..()
	brain.register_security()
	gun = locate(/obj/item/gun/energy/e_gun/advtaser) in bot.GetAllContents()
	if(gun)
		gun.cell.charge = 100

/datum/bot_scenario/duty/recharge_gun/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!gun || QDELETED(gun))
		fail_reason = "no gun"
		return BOT_GYM_FAIL
	return (gun.cell.charge >= gun.cell.maxcharge * 0.9 && (gun in bot.GetAllContents())) ? BOT_GYM_PASS : BOT_GYM_PENDING
