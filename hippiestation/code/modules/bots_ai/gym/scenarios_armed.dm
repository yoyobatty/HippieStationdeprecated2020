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

// A prisoner brought in bleeding (security_brig_first_aid.dm)

/datum/bot_scenario/brigged/bleeding
	name = "brig: a prisoner who's bleeding is patched up before they're left"
	desc = "An officer brigs somebody cut up in a fight (30 brute on each arm, bleeding). There's a first aid kit in the Brig; the officer takes it on the way and patches them in the cell before the cuffs come off. Prisoners used to bleed out in their cells."
	layout = list(
		"#########",
		"#BC..ik.#",
		"####d####",
		"###...###",
		"###..l###",
		"#########")

/datum/bot_scenario/brigged/bleeding/setup()
	..()
	if(length(markers["k"]))
		new /obj/item/storage/firstaid/regular(first_marker("k"))

/datum/bot_scenario/brigged/bleeding/post_spawn()
	..()
	prisoner.apply_damage(30, BRUTE, BODY_ZONE_L_ARM)
	prisoner.apply_damage(30, BRUTE, BODY_ZONE_R_ARM)

/// The limbs still bleeding (20 brute or more, blood.dm)
/datum/bot_scenario/brigged/bleeding/proc/still_bleeding()
	. = list()
	for(var/obj/item/bodypart/BP as anything in prisoner.bodyparts)
		if(BP.brute_dam >= 20)
			. += "[BP.name] ([round(BP.brute_dam)])"

/datum/bot_scenario/brigged/bleeding/check()
	. = ..()
	if(. != BOT_GYM_PASS)
		return
	var/list/bleeding = still_bleeding()
	if(length(bleeding))
		fail_reason = "left in the cell still bleeding from the [english_list(bleeding)]"
		return BOT_GYM_FAIL

/datum/bot_scenario/brigged/bleeding/no_kit
	name = "brig: with nothing to patch a bleeding prisoner with, it takes them to a doctor in their cuffs"
	desc = "The same, wanted for theft, with no first aid kit anywhere. The officer doesn't leave them in a cell no doctor's ID opens: it takes them to Medbay (M) in their cuffs. It used to call Medical, uncuff them and start the timer; the doctor said to come by Medbay, which a prisoner in a cell can't."
	layout = list(
		"#########",
		"#BC..i.M#",
		"####d####",
		"###...###",
		"###..l###",
		"#########")

/datum/bot_scenario/brigged/bleeding/no_kit/post_spawn()
	..()
	var/datum/bot_wanted/W = bot_get_wanted_entry(prisoner)
	W.crime = "Theft" //not dangerous: they can go to Medbay
	if("gym_medbay_spot" in brain.vars)
		brain.vars["gym_medbay_spot"] = first_marker("M")

/datum/bot_scenario/brigged/bleeding/no_kit/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(timer.timing && !prisoner.handcuffed)
		fail_reason = "uncuffed them in the cell still bleeding from the [english_list(still_bleeding())] and started the timer"
		return BOT_GYM_FAIL
	return (get_dist(prisoner, first_marker("M")) <= 1 && prisoner.handcuffed && bot.pulling != prisoner) ? BOT_GYM_PASS : BOT_GYM_PENDING

/// Went for the officer the moment the cuffs came off: cuffed again, and this time left in them (goals/released_prisoner.dm). In
/// play5f run6 a prisoner was uncuffed, punched the officer and was cuffed again six times over in the one cell.
/datum/bot_scenario/brigged/fights_uncuffing
	name = "brig: a prisoner who punches the officer as the cuffs come off is left cuffed the next time"
	desc = "An officer brigs somebody wanted for assault. The moment the cuffs come off, they punch the officer. The officer cuffs them again and brings them back to the cell, and this time leaves the cuffs on and starts the timer. It used to uncuff them again, get punched again, and go round."
	time_limit = 70 SECONDS
	var/punched = 0
	var/recuffed = FALSE
	var/uncuffed_after_punch = FALSE

/datum/bot_scenario/brigged/fights_uncuffing/post_spawn()
	..()
	watch_cuffs()

/// Every tick: the cuffs off in the cell, a punch at once. Once only; cuffs off again after they've been put back on is the failure.
/datum/bot_scenario/brigged/fights_uncuffing/proc/watch_cuffs()
	if(result != BOT_GYM_PENDING || QDELETED(prisoner) || QDELETED(bot))
		return
	if(punched && prisoner.handcuffed)
		recuffed = TRUE
	if(!prisoner.handcuffed && prisoner.Adjacent(bot) && (!punched || recuffed))
		if(punched)
			uncuffed_after_punch = TRUE
			return
		punched++
		log_line("[prisoner] punches [bot] as the cuffs come off")
		prisoner.a_intent = INTENT_HARM
		prisoner.UnarmedAttack(bot)
	addtimer(CALLBACK(src, PROC_REF(watch_cuffs)), 1)

/datum/bot_scenario/brigged/fights_uncuffing/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(uncuffed_after_punch)
		fail_reason = "uncuffed them again after they'd punched it"
		return BOT_GYM_FAIL
	if(!punched)
		if(timer.timing)
			fail_reason = "the punch never happened (the timer started first)"
			return BOT_GYM_FAIL
		return BOT_GYM_PENDING
	return (timer.timing && prisoner.handcuffed && (get_turf(prisoner) in bot_get_cell_interior(timer))) ? BOT_GYM_PASS : BOT_GYM_PENDING

/// Out of the cell: its things back from the cell locker (goals/released_prisoner.dm)
/datum/bot_scenario/duty/released_prisoner
	name = "brig: let out at the end of a sentence, it takes its ID, headset and jumpsuit back from the cell locker"
	desc = "The bot has just served a sentence: it's in orange, and its ID, headset and own jumpsuit are in the cell's locker, unlocked now the timer's run out. It opens the locker and puts them back on, the ID first. Nobody did: a chemist let out in play5f run6 walked the Brig without an ID until they bled to death there."
	job = "Chemist"
	time_limit = 40 SECONDS
	layout = list(
		"#######",
		"#B...l#",
		"#######")
	var/obj/structure/closet/secure_closet/brig/locker
	var/obj/item/card/id/card
	var/obj/item/radio/headset/headset
	var/obj/item/clothing/under/own_suit

/datum/bot_scenario/duty/released_prisoner/setup()
	duty_type = text2path("/datum/bot_duty/collect_confiscated") // by name: a build without the fix has no such duty
	locker = new(first_marker("l"))
	place("l", locker)

/datum/bot_scenario/duty/released_prisoner/post_spawn()
	..()
	own_suit = bot.w_uniform
	bot.dropItemToGround(own_suit, TRUE)
	own_suit.forceMove(locker)
	bot.equip_to_slot_or_del(new /obj/item/clothing/under/rank/prisoner(bot), ITEM_SLOT_ICLOTHING)
	card = new(locker)
	card.registered_name = bot.real_name
	card.assignment = job
	headset = new(locker)
	locker.locked = FALSE //the timer's run out (door_timer/timer_end())
	locker.update_icon()
	var/noted = text2path("/proc/bot_note_confiscated")
	if(noted) // processing notes these as it takes them (security_patrol.dm)
		call(noted)(bot, card, ITEM_SLOT_ID, locker)
		call(noted)(bot, headset, ITEM_SLOT_EARS, locker)
		call(noted)(bot, own_suit, ITEM_SLOT_ICLOTHING, locker)

/datum/bot_scenario/duty/released_prisoner/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(bot.ears == headset && bot.w_uniform == own_suit && (bot.wear_id == card || bot.get_idcard(FALSE) == card))
		return BOT_GYM_PASS
	return BOT_GYM_PENDING

/datum/bot_scenario/duty/released_prisoner/on_timeout()
	var/list/missing = list()
	if(bot.wear_id != card && bot.get_idcard(FALSE) != card)
		missing += "its ID ([card?.loc])"
	if(bot.ears != headset)
		missing += "its headset ([headset?.loc])"
	if(bot.w_uniform != own_suit)
		missing += "its jumpsuit ([own_suit?.loc])"
	fail_reason = "still without [english_list(missing)]"
	return BOT_GYM_FAIL

// A Bot Shift drill, only with sword-drill=1 in the parameters (it would change every batch's deaths otherwise): at 8 minutes somebody
// turns up in the Bar with a lit energy sword and goes at whoever's nearest, as the user did as Chief Engineer. Security has to stop
// them - cuffed or dead - within 6 minutes. Who they cut and who died of it are counted.
/datum/bot_shift_check/sword_drill
	name = "security: somebody with an energy sword in the Bar is stopped (drill)"
	jobs = list("Security Officer", "Warden", "Head of Security")
	deadline = 14 MINUTES
	var/starts_at = 8 MINUTES
	var/started = FALSE
	var/mob/living/carbon/human/swordsman
	var/obj/item/melee/transforming/energy/sword/saber/sword
	var/next_swing = 0
	var/list/cut = list()

/datum/bot_shift_check/sword_drill/worker()
	if(!world.params["sword-drill"])
		return null
	return ..()

/datum/bot_shift_check/sword_drill/poll()
	if(!started && shift.elapsed() >= starts_at)
		started = TRUE
		start()
	..()

/datum/bot_shift_check/sword_drill/proc/start()
	var/area/bar = GLOB.areas_by_type[/area/crew_quarters/bar]
	var/turf/spot
	for(var/turf/open/floor/T in bar)
		if(!is_blocked_turf(T, TRUE))
			spot = T
			break
	if(!spot)
		shift.note("[name]: no Bar on this map to start in")
		return
	swordsman = new(spot)
	swordsman.real_name = "Ed Sword"
	swordsman.name = swordsman.real_name
	swordsman.equipOutfit(/datum/outfit/job/assistant)
	sword = new(swordsman)
	swordsman.put_in_active_hand(sword)
	sword.attack_self(swordsman) //lit
	shift.note("[name]: Ed Sword turns up in the Bar with a lit energy sword")
	addtimer(CALLBACK(src, PROC_REF(act)), 5)

/// Twice a second: over to whoever's nearest, and a swing every second and a half once beside them
/datum/bot_shift_check/sword_drill/proc/act()
	if(QDELETED(swordsman) || swordsman.stat == DEAD || swordsman.handcuffed)
		return
	if(swordsman.stat == CONSCIOUS && !swordsman.IsParalyzed() && !swordsman.IsKnockdown() && !swordsman.IsStun() && !swordsman.IsUnconscious() && swordsman.get_active_held_item() == sword)
		var/mob/living/carbon/human/target
		var/best
		for(var/mob/living/carbon/human/H in view(7, swordsman))
			if(H == swordsman || H.stat == DEAD)
				continue
			var/d = get_dist(H, swordsman)
			if(!target || d < best)
				target = H
				best = d
		if(target)
			if(best <= 1)
				if(world.time >= next_swing)
					next_swing = world.time + 15
					swordsman.a_intent = INTENT_HARM
					sword.melee_attack_chain(swordsman, target)
					cut |= target.real_name
			else
				step_towards(swordsman, target)
	addtimer(CALLBACK(src, PROC_REF(act)), 5)

/datum/bot_shift_check/sword_drill/done()
	return started && swordsman && (QDELETED(swordsman) || swordsman.stat == DEAD || swordsman.handcuffed)

/datum/bot_shift_check/sword_drill/progress()
	if(!started)
		return "not started yet"
	if(!swordsman)
		return "didn't start: no Bar"
	var/killed = 0
	for(var/mob/living/carbon/human/H in GLOB.dead_mob_list)
		if(H.lastattacker == swordsman.real_name)
			killed++
	var/state = "still free"
	if(QDELETED(swordsman) || swordsman.stat == DEAD)
		state = "dead"
	else if(swordsman.handcuffed)
		state = "cuffed"
	return "Ed Sword [state], cut [length(cut)] crew, [killed] of them dead"

// Prisoners who need a doctor (security_medevac.dm). M is the arena's stand-in for Medbay's lobby.

/datum/bot_scenario/brigged/pale
	name = "brig: a prisoner pale from losing blood is taken to Medbay, not a cell"
	desc = "An officer has somebody in cuffs who's lost a lot of blood (pale skin, under BLOOD_VOLUME_SAFE). It takes them to Medbay and leaves them for a doctor. Prisoners like that used to be put in a cell, collapse in it and die there, where no doctor could get to them."
	layout = list(
		"#########",
		"#BC..i.M#",
		"####d####",
		"###...###",
		"###..l###",
		"#########")
	var/asked = FALSE

/datum/bot_scenario/brigged/pale/post_spawn()
	..()
	prisoner.blood_volume = 400
	var/datum/bot_wanted/W = bot_get_wanted_entry(prisoner)
	W.crime = "Theft" //not dangerous: they can go to Medbay
	if("gym_medbay_spot" in brain.vars) // the fix's: a build without it has no such var
		brain.vars["gym_medbay_spot"] = first_marker("M")

/datum/bot_scenario/brigged/pale/make_goal()
	return null

/datum/bot_scenario/brigged/pale/issue_goal()
	if(!asked)
		asked = TRUE
		brain.start_brig_escort(prisoner)

/datum/bot_scenario/brigged/pale/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(timer.timing)
		fail_reason = "put them in the cell"
		return BOT_GYM_FAIL
	return (get_dist(prisoner, first_marker("M")) <= 1 && bot.pulling != prisoner) ? BOT_GYM_PASS : BOT_GYM_PENDING

/// The same, and in orange when it gets there, from the cell's locker: nobody in Medbay could tell the user's janitor was a prisoner
/datum/bot_scenario/brigged/pale/in_orange
	name = "brig: a prisoner pale from losing blood is put in orange from the brig locker and taken to Medbay"
	desc = "The same pale prisoner. On the way, the officer dresses them in the prison jumpsuit and shoes from the locker, so whoever sees them in Medbay knows they're Security's. The user uncuffed a traitor janitor left in Medbay in his own clothes, not knowing he was a prisoner."

/datum/bot_scenario/brigged/pale/in_orange/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(timer.timing)
		fail_reason = "put them in the cell"
		return BOT_GYM_FAIL
	if(get_dist(prisoner, first_marker("M")) > 1 || bot.pulling == prisoner)
		return BOT_GYM_PENDING
	if(!istype(prisoner.w_uniform, /obj/item/clothing/under/rank/prisoner))
		fail_reason = "left in Medbay in [prisoner.w_uniform || "nothing"]"
		return BOT_GYM_FAIL
	return BOT_GYM_PASS

/// Wanted for carrying something, and nothing on them when searched: let go, not brigged
/// Taken to Medbay, and the officer waits with them; seen to, they go back to the Brig. The Warden left the user's janitor alone
/// in Medbay and went to eat.
/datum/bot_scenario/brigged/pale/stays
	name = "brig: a prisoner taken to Medbay has the officer stay with them, and goes back to the cell once seen to"
	desc = "The pale prisoner, wanted for something minor, goes to Medbay. The officer waits with them; once their blood's back (a doctor's seen to them) it takes them back and cells them."
	time_limit = 70 SECONDS
	var/healed = FALSE

/datum/bot_scenario/brigged/pale/stays/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(!healed)
		if(get_dist(prisoner, first_marker("M")) <= 1 && bot.pulling != prisoner)
			healed = TRUE
			log_line("a doctor sees to the prisoner")
			prisoner.blood_volume = BLOOD_VOLUME_NORMAL
		return BOT_GYM_PENDING
	if(timer.timing)
		return BOT_GYM_PASS
	if(get_dist(bot, prisoner) > 3 && !istype(brain.current_goal, /datum/bot_goal/brig_prisoner))
		fail_reason = "left them in Medbay"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/// Somebody dangerous who needs a doctor stays in Security: kept by the door, and Medical called there
/datum/bot_scenario/brigged/kept_in_brig
	name = "brig: a dangerous prisoner pale from losing blood stays in the Brig, kept by the door, and Medical's called there"
	desc = "The prisoner's wanted for assault and is pale from losing blood. The officer doesn't take them to Medbay (M): it keeps them just inside Security's door (K) and calls Medical to come to them. The user's ruling: violent prisoners and traitors don't leave Security."
	layout = list(
		"#########",
		"#BC.Ki.M#",
		"####d####",
		"###...###",
		"###..l###",
		"#########")
	var/asked = FALSE

/datum/bot_scenario/brigged/kept_in_brig/post_spawn()
	..()
	prisoner.blood_volume = 300
	if("gym_medbay_spot" in brain.vars)
		brain.vars["gym_medbay_spot"] = first_marker("M")
	if("gym_brig_spot" in brain.vars)
		brain.vars["gym_brig_spot"] = first_marker("K")

/datum/bot_scenario/brigged/kept_in_brig/make_goal()
	return null

/datum/bot_scenario/brigged/kept_in_brig/issue_goal()
	if(!asked)
		asked = TRUE
		brain.start_brig_escort(prisoner)

/datum/bot_scenario/brigged/kept_in_brig/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(get_dist(prisoner, first_marker("M")) <= 1)
		fail_reason = "took them to Medbay"
		return BOT_GYM_FAIL
	if(!bot_transcript_said("isn't leaving Security"))
		return BOT_GYM_PENDING
	for(var/datum/bot_request/R as anything in GLOB.bot_requests)
		if(R.caller_ref?.resolve() == prisoner && istype(R.kind, /datum/bot_request_kind/medical))
			return get_dist(prisoner, first_marker("K")) <= 1 ? BOT_GYM_PASS : BOT_GYM_PENDING
	return BOT_GYM_PENDING

/datum/bot_scenario/brigged/kept_in_brig/release_run()
	for(var/datum/bot_request/R as anything in GLOB.bot_requests.Copy())
		if(R.caller_ref?.resolve() == prisoner)
			GLOB.bot_requests -= R
	return ..()

/datum/bot_scenario/brigged/searched_clean
	name = "brig: somebody arrested for carrying contraband with none on them is searched and let go"
	desc = "An officer has somebody in cuffs who's wanted for Possession of Dangerous Equipment, but has nothing of the kind on them. It searches them, uncuffs them and lets them go. The user was arrested for a sword they'd thrown away three minutes earlier."
	var/asked = FALSE

/datum/bot_scenario/brigged/searched_clean/post_spawn()
	..()
	var/datum/bot_wanted/W = bot_get_wanted_entry(prisoner)
	W.crime = "Possession of Dangerous Equipment"
	W.severity = BOT_CRIME_MAJOR

/datum/bot_scenario/brigged/searched_clean/make_goal()
	return null

/datum/bot_scenario/brigged/searched_clean/issue_goal()
	if(!asked)
		asked = TRUE
		brain.start_brig_escort(prisoner)

/datum/bot_scenario/brigged/searched_clean/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(timer.timing)
		fail_reason = "brigged them"
		return BOT_GYM_FAIL
	if(istype(brain.current_goal, /datum/bot_goal/brig_prisoner))
		fail_reason = "took them off to a cell"
		return BOT_GYM_FAIL
	return (!prisoner.handcuffed && !bot_get_wanted_entry(prisoner)) ? BOT_GYM_PASS : BOT_GYM_PENDING

/// The same, in a nanosuit: kept. In the user's round (2026-11-10) an officer cuffed a nanosuit, searched it, found nothing and let it go.
/datum/bot_scenario/brigged/searched_clean/suited
	name = "brig: somebody in a nanosuit, arrested for dangerous equipment, isn't searched and let go"
	desc = "As above, but the prisoner's wearing a nanosuit. A search turns up nothing, since the suit's worn and not carried. The officer keeps them cuffed and on the wanted list."
	time_limit = 20 SECONDS

/datum/bot_scenario/brigged/searched_clean/suited/post_spawn()
	..()
	prisoner.equip_to_slot_or_del(new /obj/item/clothing/suit/space/hardsuit/nano(prisoner), ITEM_SLOT_OCLOTHING)

/datum/bot_scenario/brigged/searched_clean/suited/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(timer.timing || istype(brain.current_goal, /datum/bot_goal/brig_prisoner))
		return BOT_GYM_PASS //uncuffed in the cell, once processed: that's the Brig, not letting them go
	if(!bot_get_wanted_entry(prisoner))
		fail_reason = "searched them and let them go"
		return BOT_GYM_FAIL
	return BOT_GYM_PENDING

/datum/bot_scenario/brigged/collapsed
	name = "brig: a prisoner who's collapsed in a cell is let out and taken to Medbay"
	desc = "A prisoner is down in crit in a cell with the timer running, and an officer sees them through the door. It stops the timer, gets them out and takes them to Medbay. They used to be left in there until they died."
	layout = list(
		"#########",
		"#...Bi.M#",
		"####d####",
		"###.C.###",
		"###..l###",
		"#########")

/datum/bot_scenario/brigged/collapsed/post_spawn()
	..()
	prisoner.uncuff()
	timer.set_timer(5 MINUTES)
	timer.timer_start()
	GLOB.bot_brig_sentences[timer] = WEAKREF(prisoner)
	prisoner.apply_damage(130, BRUTE, BODY_ZONE_CHEST)
	var/datum/bot_wanted/W = bot_get_wanted_entry(prisoner)
	if(W)
		W.crime = "Theft" //not dangerous: they can go to Medbay
	if("gym_medbay_spot" in brain.vars)
		brain.vars["gym_medbay_spot"] = first_marker("M")

/datum/bot_scenario/brigged/collapsed/make_goal()
	return null

/datum/bot_scenario/brigged/collapsed/issue_goal()
	var/datum/bot_duty/D = bot_duty_of(text2path("/datum/bot_duty/prisoner_down")) // by name: a build without the fix has no such duty
	D?.try_start(brain)

/datum/bot_scenario/brigged/collapsed/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(prisoner.stat == DEAD)
		fail_reason = "the prisoner died"
		return BOT_GYM_FAIL
	return (get_dist(prisoner, first_marker("M")) <= 1 && bot.pulling != prisoner) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/brigged/collapsed/release_run()
	GLOB.bot_brig_sentences -= timer
	return ..()

// Crossfire (bot_brain.dm, stray_shot_from())

/datum/bot_scenario/crossfire
	name = "security: an officer hit by a colleague's shot at a suspect doesn't turn on the colleague"
	desc = "Another officer is arresting somebody and its taser shot hits this officer. It says to watch it and carries on. Officers used to take that as an attack and fight each other with batons in the middle of the Brig."
	job = "Security Officer"
	layout = list(
		"#########",
		"#B.O..C.#",
		"#########")
	time_limit = 15 SECONDS
	var/mob/living/carbon/human/colleague
	var/mob/living/carbon/human/suspect
	var/shot_at = 0

/datum/bot_scenario/crossfire/post_spawn()
	give_job_id(list(ACCESS_SECURITY, ACCESS_BRIG))
	brain.register_security()
	colleague = second_bot(first_marker("O"), "Col League")
	colleague.mind.assigned_role = "Security Officer"
	colleague.bot_brain.register_security()
	colleague.put_in_hands(new /obj/item/restraints/handcuffs(colleague)) //nothing to arrest with, no arrest
	suspect = stand_in(first_marker("C"), "Sus Pect")
	colleague.bot_brain.file_crime(suspect, "Assault", "Gym.", BOT_CRIME_MINOR)
	colleague.bot_brain.begin_arrest(suspect)

/datum/bot_scenario/crossfire/make_goal()
	return null

/datum/bot_scenario/crossfire/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	if(brain.state == BOT_STATE_COMBAT && brain.attacker == colleague)
		fail_reason = "turned on its colleague"
		return BOT_GYM_FAIL
	if(!shot_at)
		if(colleague.bot_brain.state != BOT_STATE_ARREST || colleague.bot_brain.arrest_suspect != suspect)
			if(colleague.bot_brain.state != BOT_STATE_ARREST && !colleague.bot_brain.begin_arrest(suspect))
				fail_reason = "the colleague won't arrest the suspect (state [colleague.bot_brain.state])"
				return BOT_GYM_FAIL
			return BOT_GYM_PENDING
		shot_at = world.time
		log_line("Col League's taser shot at Sus Pect hits this officer")
		brain.on_attacked(colleague, "shot", null) // what log_combat() feeds it for a hit from a projectile (bot_notice_combat())
		return BOT_GYM_PENDING
	return world.time - shot_at > 5 SECONDS ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/crossfire/release_run()
	bot_clear_wanted(suspect)
	if(colleague?.bot_brain)
		qdel(colleague.bot_brain) //gym bots outlive their run: an officer left thinking went on arresting people in the arenas after
	return ..()

/datum/bot_scenario/brigged/colleague
	// Run by name, on its own: in the full gym the arenas alongside it went wrong, and stayed wrong with its colleague kept quiet
	station_wide = TRUE
	name = "brig: a colleague after the same prisoner leaves them be once they're in the cell"
	desc = "Another officer wants the prisoner for the same charge and goes for them the moment the cuffs come off in the cell. It leaves them to the officer brigging them. It used to taser and cuff them again in the cell and drag them out, which the first officer took for a jailbreak."
	layout = list(
		"#########",
		"#BC..iO.#",
		"####d####",
		"###...###",
		"###..l###",
		"#########")
	time_limit = 60 SECONDS
	var/mob/living/carbon/human/colleague
	var/tried = 0

/datum/bot_scenario/brigged/colleague/post_spawn()
	..()
	colleague = second_bot(first_marker("O"), "Col League")
	colleague.mind.assigned_role = "Security Officer" // not register_security(): a registered officer standing idle here took the calls from
	// the arenas running alongside, and their scenarios failed
	colleague.put_in_hands(new /obj/item/restraints/handcuffs(colleague))
	colleague.put_in_hands(new /obj/item/melee/baton/loaded(colleague))

/datum/bot_scenario/brigged/colleague/check()
	if(bot_lost())
		return BOT_GYM_FAIL
	var/list/interior = bot_get_cell_interior(timer)
	if(!tried && !prisoner.handcuffed && (get_turf(prisoner) in interior))
		tried = world.time
		log_line("Col League goes for Pat Prisoner, uncuffed in the cell")
		colleague.bot_brain.begin_arrest(prisoner)
	if(colleague.bot_brain && tried && world.time - tried > 2 SECONDS)
		if(colleague.bot_brain.state == BOT_STATE_ARREST && colleague.bot_brain.arrest_suspect == prisoner)
			fail_reason = "the colleague went after a prisoner already in the cell"
			return BOT_GYM_FAIL
		qdel(colleague.bot_brain) // judged: no more thinking for it
	if(tried && prisoner.handcuffed)
		fail_reason = "the colleague cuffed them again in the cell"
		return BOT_GYM_FAIL
	if(tried && !(get_turf(prisoner) in interior))
		fail_reason = "the prisoner was taken out of the cell"
		return BOT_GYM_FAIL
	return (timer.timing && tried && world.time - tried > 8 SECONDS) ? BOT_GYM_PASS : BOT_GYM_PENDING

/datum/bot_scenario/brigged/colleague/release_run()
	if(colleague?.bot_brain)
		qdel(colleague.bot_brain) //gym bots outlive their run: an officer left thinking went on arresting people in the arenas after
	return ..()
