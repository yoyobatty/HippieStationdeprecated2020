// Accidents (the user's ruling, 2026-11-06): at BOT_CHAOS 2 the ordinary crew get things wrong as well as the saboteurs getting them
// right. Three of them, now and then, from the chaos director (bot_chaos.dm), each on somebody who's at that work:
//
//  - a slime out of Xenobiology: the scientist working the pens leaves the door, and a hungry slime ends up in the corridor. What
//    the crew does about a loose slime is the same as for one let out on purpose (goals/sabotage_slimes.dm).
//  - a chemist's beaker goes up: the wrong thing into the wrong beaker at the dispenser, a small blast in the lab (the potassium and
//    water any chemist knows not to mix). The hurt go to Medbay as they would after any blast.
//  - a careless virologist: a culture knocked over, and an experimental virus in the virologist (accident_virus_leak(), below).

/// From the chaos director at level 2: a slime gets out past a scientist at the pens. TRUE if it happened.
/datum/bot_chaos/proc/accident_slime_out()
	for(var/datum/bot_brain/B as anything in shuffle(GLOB.bot_brains.Copy()))
		if(B.owner.stat != CONSCIOUS || !(B.work_role() in list("Scientist", "Research Director")) || !B.in_xenobiology(B.owner) || B.gym_run)
			continue
		var/obj/machinery/computer/camera_advanced/xenobio/X = B.find_xeno_console()
		var/obj/machinery/door/airlock/exit = X ? B.xeno_exit_door(X) : null
		if(!exit)
			continue
		var/mob/living/simple_animal/slime/loose
		for(var/mob/living/simple_animal/slime/S as anything in B.lab_slimes())
			if(!S.docile && !S.buckled)
				loose = S
				break
		if(!loose)
			continue
		// Out of the far side of the door, into the corridor
		var/turf/out
		for(var/d in GLOB.cardinals)
			var/turf/T = get_step(exit, d)
			if(T && !T.density && !istype(T.loc, /area/science/xenobiology) && !is_blocked_turf(T, TRUE))
				out = T
				break
		if(!out)
			continue
		loose.forceMove(out)
		bot_log(B, "ACCIDENT: left the lab door, and [loose] got out")
		log_game("BOT CHAOS: [loose] got out of Xenobiology at [AREACOORD(out)] past [key_name(B.owner)]")
		bot_say(B.owner, pick(";Uh, one of the slimes got out of Xenobiology! Sorry!", ";Slime's out of the lab, it got past me at the door!"), TRUE)
		GLOB.bot_loose_slime_reports[get_area(out)] = world.time //it said so on the radio
		return TRUE
	return FALSE

/// From the chaos director at level 2: a chemist at the dispenser mixes what doesn't mix. TRUE if it happened.
/datum/bot_chaos/proc/accident_chem_mishap()
	for(var/datum/bot_brain/B as anything in shuffle(GLOB.bot_brains.Copy()))
		if(B.owner.stat != CONSCIOUS || B.work_role() != "Chemist" || B.gym_run || !istype(B.current_goal, /datum/bot_goal/synthesize_medicine))
			continue
		var/obj/machinery/chem_dispenser/D = locate() in range(1, B.owner)
		if(!D)
			continue
		bot_log(B, "ACCIDENT: the wrong beaker - it's going up")
		log_game("BOT CHAOS: [key_name(B.owner)] had a beaker go up at [AREACOORD(B.owner)]")
		bot_say(B.owner, pick("Oh no. Oh no no no-", "That's not the right one-", "Wait, that's water!"), TRUE)
		var/datum/effect_system/reagents_explosion/boom = new()
		boom.set_up(3, get_turf(B.owner), 0, 0)
		boom.start()
		return TRUE
	return FALSE

/// A careless virologist (the user's list): a culture knocked over in Virology, and an experimental virus in whoever was working
/// on it. It says so on the radio; curing it is the medics' as for any other (goals/sabotage_virus.dm), the virologist's own included.
/datum/bot_chaos/proc/accident_virus_leak()
	for(var/datum/bot_brain/B as anything in shuffle(GLOB.bot_brains.Copy()))
		if(B.owner.stat != CONSCIOUS || B.work_role() != "Virologist" || B.gym_run || B.saboteur || !istype(get_area(B.owner), /area/medical/virology))
			continue
		var/datum/disease/advance/random/D = new(rand(3, 5), 6)
		if(!B.owner.ForceContractDisease(D, FALSE, TRUE))
			continue
		bot_log(B, "ACCIDENT: knocked over a culture - [D.name] ([bot_virus_symptoms(D)])")
		log_game("BOT CHAOS: [key_name(B.owner)] knocked over a culture and caught [D.name] ([bot_virus_symptoms(D)]) at [AREACOORD(B.owner)]")
		bot_say(B.owner, pick("Ugh, that went everywhere.", "Oh, that's not good."), TRUE)
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(bot_say), B.owner, ";Virology here, I've had a spill. Anybody feeling ill, come and see me."), 3 SECONDS)
		GLOB.bot_sick_known[WEAKREF(B.owner)] = world.time
		return TRUE
	return FALSE
